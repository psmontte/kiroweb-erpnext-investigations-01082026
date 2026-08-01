# 22 — Background Jobs, Scheduling, and Locking

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Tranche A kept running into the same thing: work that should be part of a transaction has been
pushed into a background job, and the job's failure mode is an email to a human
(`notify_error_to_stock_managers`, doc 15 §8). This document explains the job infrastructure, why
it is used the way it is, and what our design does instead.

---

## 1. The queue: Redis + RQ

`frappe/utils/background_jobs.py`. Redis Queue with five named queues sized by
`get_queues_timeout` (`frappe/utils/background_jobs.py:54`) — conventionally
`short` (300 s), `default` (300 s), `long` (1500 s), plus `@ + site` variants.

Enqueue: `enqueue` (`frappe/utils/background_jobs.py:79`) with inner
`enqueue_call` (`:197`), `enqueue_doc` (`:218`), `run_doc_method` (`:241`).
Queue plumbing: `get_queue` (`:541`), `validate_queue` (`:553`),
`get_queue_list` (`:508`), `get_queues` (`:622`), `generate_qname` (`:628`),
`is_queue_accessible` (`:638`), `get_redis_conn` (`:574`),
`get_redis_connection_without_auth` (`:614`), `_check_queue_size` (`:725`),
`_site_count` (`:746`).
Introspection: `get_jobs` (`:482`) with `add_to_dict` (`:486`), `get_workers` (`:522`),
`get_running_jobs_in_queue` (`:530`), `get_worker_name` (`:471`),
`create_job_id` (`:655`), `is_job_enqueued` (`:672`), `get_job_status` (`:676`),
`get_job` (`:682`), `truncate_failed_registry` (`:710`).
Workers: `start_worker` (`:326`), `start_worker_pool` (`:417`),
`FrappeWorker` (`:367`) with `work` (`:368`), `run_maintenance_tasks` (`:373`),
`start_frappe_scheduler` (`:378`); `FrappeWorkerNoFork` (`:385`) with
`execute_job` (`:394`), `no_fork_exception_handler` (`:400`),
`get_heartbeat_ttl` (`:406`), `kill_horse` (`:412`); `set_niceness` (`:692`).

Two doctypes mirror the queue into the database for the UI: `RQ Job` and `RQ Worker`
(virtual doctypes, doc 18 §3.2).

### 1.1 The job wrapper and its transaction semantics

`execute_job` (`frappe/utils/background_jobs.py:245`) is the important function:

```python
if is_async:
    frappe.init(site, force=True, is_job=True); frappe.connect()
    if user: frappe.set_user(user)
if isinstance(method, str): method_name = method; method = frappe.get_attr(method)
frappe.local.job = frappe._dict(site=..., method=method_name, job_name=..., kwargs=..., user=...,
                                after_job=CallbackManager())
for before_job_task in frappe.get_hooks("before_job"):
    frappe.call(before_job_task, method=method_name, kwargs=kwargs, transaction_type="job")
try:
    retval = method(**kwargs)
except (frappe.db.InternalError, frappe.RetryBackgroundJobError) as e:
    frappe.db.rollback(chain=True)
    if retry < 5 and (isinstance(e, frappe.RetryBackgroundJobError)
                      or frappe.db.is_deadlocked(e) or frappe.db.is_timedout(e)):
        frappe.job.after_job.reset(); frappe.destroy(); time.sleep(retry + 1)
        return execute_job(site, method, event, job_name, kwargs, is_async=is_async, retry=retry + 1)
    else:
        frappe.log_error(title=method_name); raise
except Exception as e:
    frappe.db.rollback(chain=True); frappe.log_error(title=method_name)
    frappe.monitor.add_data_to_monitor(exception=e.__class__.__name__)
    frappe.db.commit(chain=True)          # ← commit AFTER a rollback, on the error path
    print(frappe.get_traceback()); raise
else:
    frappe.db.commit(chain=True); return retval
finally:
    ...
    for after_job_task in frappe.get_hooks("after_job"): frappe.call(after_job_task, ...)
    frappe.local.job.after_job.run()
    if is_async: frappe.destroy()
```

Observations that matter for correctness:

- **Retry is bounded at 5 and keyed on deadlock/timeout only** (`:283`–`:287`), with a linear
  backoff of `retry + 1` seconds. Any other exception is logged and re-raised — RQ then moves the
  job to the failed registry, and `truncate_failed_registry` (`:710`) eventually discards it.
  **There is no dead-letter table in the database**, so a permanently failing job's payload is
  lost once the Redis registry is truncated.
- **Retry re-invokes the same function with the same kwargs.** There is no idempotency key. A job
  that partially committed before deadlocking (via an inner `frappe.db.commit()`, which several
  ERPNext jobs do — see doc 15 §6.2) will **redo its already-committed work** on retry.
- `frappe.db.commit(chain=True)` on the *generic exception* path (`:307`) commits after a
  rollback. Its purpose is to persist the `Error Log` row, but it means the failure path issues a
  commit — so anything written between the rollback and that commit lands.
- `before_job` / `after_job` hooks (`:277`, `:317`) are arbitrary extension points inside the job
  boundary (doc 21).
- Jobs run as a **user** (`frappe.set_user(user)`, `:259`), so permission checks inside a job
  depend on which user enqueued it. Scheduled jobs run as `Administrator` — which, per doc 19 §2,
  bypasses everything.

### 1.2 `enqueue_after_commit`

`Document.queue_action` (`frappe/model/document.py:2321`) defaults `enqueue_after_commit = True`
and enqueues `frappe.model.document.execute_action`. So a document action can be performed
asynchronously, after the current transaction commits — and `Document.lock`
(`frappe/model/document.py:2334`) is what stops two such actions colliding. See §3.

---

## 2. The scheduler

`frappe/utils/scheduler.py`. `start_scheduler` (`:38`),
`_get_scheduler_lock_file` (`:59`), `is_schduler_process_running` (`:63`)
*(misspelling in source)*, `sleep_duration` (`:78`),
`enqueue_events_for_all_sites` (`:96`), `enqueue_events_for_site` (`:112`) with
`log_exc` (`:113`), `enqueue_events` (`:134`),
`is_scheduler_inactive` (`:151`), `is_scheduler_disabled` (`:168`),
`toggle_scheduler` (`:181`), `enable_scheduler` (`:185`), `disable_scheduler` (`:189`),
`schedule_jobs_based_on_activity` (`:194`), `is_dormant` (`:215`),
`_get_last_creation_timestamp` (`:235`), `activate_scheduler` (`:242`),
`get_scheduler_status` (`:257`), `get_scheduler_tick` (`:263`).

Job definitions come from `hooks.py` → `Scheduled Job Type` rows:
`sync_jobs` (`frappe/core/doctype/scheduled_job_type/scheduled_job_type.py:223`),
`insert_events` (`:230`), `insert_cron_jobs` (`:242`), `insert_event_jobs` (`:251`),
`insert_single_event` (`:260`), `clear_events` (`:298`) with `event_exists` (`:299`).

### 2.1 Due-time computation

`ScheduledJobType.get_next_execution`
(`frappe/core/doctype/scheduled_job_type/scheduled_job_type.py:109`):

```python
maintenance_offset = int(hashlib.sha1(frappe.local.site.encode()).hexdigest(), 16) % 60
CRON_MAP = {"Yearly": "0 0 1 1 *", "Annual": "0 0 1 1 *", "Monthly": "0 0 1 * *",
            "Monthly Long": "0 0 1 * *", "Weekly": "0 0 * * 0", "Weekly Long": "0 0 * * 0",
            "Daily": "0 0 * * *", "Daily Long": "0 0 * * *", "Daily Maintenance": "0 0 * * *",
            "Hourly": "0 * * * *", "Hourly Long": "0 * * * *", "Hourly Maintenance": "0 * * * *",
            "All": f"*/{(frappe.get_conf().scheduler_interval or 240) // 60} * * * *"}
if not self.cron_format: self.cron_format = CRON_MAP.get(self.frequency)
last_execution = get_datetime(self.last_execution or self.creation)
next_execution = parse_cron(self.cron_format).get_next(datetime, start_time=last_execution)
if self.frequency in ("Hourly Maintenance", "Daily Maintenance"):
    next_execution += timedelta(minutes=maintenance_offset)
return parse_cron(self.cron_format).get_next(datetime, start_time=last_execution)
```

Note the last three lines: `next_execution` is computed, **conditionally adjusted by
`maintenance_offset`, and then the function returns a freshly recomputed value that ignores the
adjustment.** The `maintenance_offset` — whose entire purpose, per the comment at `:110`–`:112`,
is to spread maintenance jobs across sites in a multi-tenant deployment — is computed, applied to
a local variable, and discarded. Maintenance jobs therefore all fire on the hour, on every site,
simultaneously. **This is a live bug in v17.**

`is_event_due` (`:92`) is `get_next_execution() <= now`, and scheduling is driven off
`last_execution` (`:135`–`:139`), with `creation` as the cold-start fallback and a comment
explaining why a dynamic fallback would be worse.

### 2.2 Deduplication

`enqueue` (`frappe/core/doctype/scheduled_job_type/scheduled_job_type.py:73`):

```python
if self.is_event_due() or force:
    if not self.is_job_in_queue():
        enqueue("...run_scheduled_job", queue=self.get_queue_name(),
                job_type=self.method, job_id=self.rq_job_id, scheduled_job_type=self.name)
        return True
    else:
        frappe.logger("scheduler").error(f"Skipped queueing {self.method} because it was found in queue for {frappe.local.site}")
```

with `rq_job_id = f"scheduled_job||{self.name}"` (`:101`–`:104`) — "Unique ID created to
deduplicate jobs with single RQ call."

So deduplication is: **check Redis for a job with this id; if absent, enqueue**. A classic
check-then-act, in Redis, across scheduler processes. `_get_scheduler_lock_file`
(`frappe/utils/scheduler.py:59`) is the coarse guard: only one scheduler process per bench should
be running, enforced by a **file**.

`execute` (`:145`), `log_status` (`:165`), `update_scheduler_log` (`:170`),
`execute_event` (`:197`), `skip_next_execution` (`:205`),
`run_scheduled_job` (`:213`) complete the loop, with `Scheduled Job Log` rows recording outcomes.

`is_dormant` (`frappe/utils/scheduler.py:215`) /
`schedule_jobs_based_on_activity` (`:194`) — jobs are **skipped entirely on sites with no
recent activity**, determined by `_get_last_creation_timestamp` (`:235`) over the log types. A
site that is quiet does not run its scheduled jobs. For an ERP, that means month-end automation
can be skipped on a low-traffic company.

### 2.3 What ERPNext schedules

`erpnext/hooks.py:468` (`scheduler_events`), starting with a `cron` block at `0/15 * * * *`.
The financially significant ones, all documented in Tranche A:

| Job | Doc |
|---|---|
| `execute_repost_item_valuation` / `repost_entries` | 15 §8 — inventory valuation correctness |
| `process_deferred_accounting` | 12 §2 — revenue recognition |
| `update_invoice_status` (`controllers/accounts_controller.py:1492`) | 10 §1.2 — document status |
| `auto_create_exchange_rate_revaluation_*` (`accounts/utils.py:2003`, `:2010`, `:2017`) | 07 — FX revaluation |
| `run_ledger_health_checks` (`accounts/utils.py:2631`) | 04 — **detects ledger inconsistency after the fact** |
| `sync_auto_reconcile_config` (`accounts/utils.py:2672`) / auto reconciliation | 14 §2.2 |
| `reorder_item` (`stock/reorder_item.py:14`) | 17 §5 |
| `send_auto_email` (`accounts/doctype/process_statement_of_accounts/process_statement_of_accounts.py:579`) | 14 §5 |
| `update_asset_value`/depreciation posting | Tranche C |

Two of these deserve emphasis:

- **`run_ledger_health_checks`** is a scheduled job whose job is to *find books that do not
  balance*. Its existence concedes that the invariants are not enforced.
- **`execute_repost_item_valuation`** is gated by `in_configured_timeslot`
  (`stock/doctype/repost_item_valuation/repost_item_valuation.py:933`) — inventory valuation is
  corrected only during a configured off-hours window (doc 15 §8).

---

## 3. Locking

Three unrelated mechanisms.

### 3.1 File locks — "weak", and the module says so

`frappe/utils/file_lock.py`. The module docstring (`:4`–`:8`):

> This file implements a "weak" form lock which is not suitable for synchroniztion. This is only
> used for document locking for queue_action. Use `frappe.utils.synchroniztion.filelock` for
> process synchroniztion.

`create_lock` (`:25`) — its own docstring (`:28`–`:31`):

> Note: This is a "weak lock" and is prone to race conditions. Do not use this lock for small
> sections of code that execute immediately.

Implementation: `touch_file(get_lock_path(name))` where the path is
`<site>/locks/<name>.lock` (`get_lock_path`, `:66`). `check_lock` (`:49`) raises
`LockTimeoutError` if the file is older than 600 s. `lock_exists` (`:39`),
`lock_age` (`:44`), `delete_lock` (`:58`).

`Document.lock` (`frappe/model/document.py:2334`):

```python
signature = self.get_signature()
if file_lock.lock_exists(signature):
    lock_exists = True
    if file_lock.lock_age(signature) > DOCUMENT_LOCK_EXPIRY:
        file_lock.delete_lock(signature); lock_exists = False
    if timeout:
        for _ in range(timeout):
            time.sleep(1)
            if not file_lock.lock_exists(signature): lock_exists = False; break
    if lock_exists: raise frappe.DocumentLockedError
file_lock.create_lock(signature)
frappe.local.locked_documents.append(self)
```

`check-then-touch`, with a 1-second polling loop and an age-based steal. And this is what
`Repost Accounting Ledger` uses to serialise **general-ledger rewrites** — doc 15 §6.1 quoted
that module's own comment:

> These are file locks under the site directory: they serialise nothing across hosts that do not
> share it, and a worker killed outright leaves them behind until they expire.

`Document.is_locked` (`frappe/model/document.py:493`),
`check_if_locked` (`frappe/model/document.py:777`), `unlock` (`:2356`).

### 3.2 Database locks, used ad hoc

`SELECT ... FOR UPDATE` appears where someone thought about it:
`getseries` (`frappe/model/naming.py:432`), `revert_series_if_last`
(`frappe/model/naming.py:496`), `validate_rename`
(`frappe/model/rename_doc.py:352`), `load_doc_before_save`
(`frappe/model/document.py:1859`), and — with an explicit engine branch —
`get_available_qty_to_reserve` (`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:722`).

And advisory locks in exactly one place:
`frappe.db.transaction_advisory_lock(("pick-allocate", item_code))`
(`stock/doctype/pick_list/pick_list.py:559`), guarded by
`hasattr(frappe.db, "transaction_advisory_lock")`.

There is no convention. Whether a given aggregate is protected depends on whether the author of
that particular function considered concurrency — which is precisely the pattern behind every
lost-update defect in Tranche A (doc 10 §7, doc 11 §6.3, doc 12 §1.3, doc 16 §2.1).

### 3.3 Optimistic locking

`check_if_latest` (`frappe/model/document.py:1379`) — the `modified` timestamp comparison
(doc 09 §1.3), bypassed by every `db_set(..., update_modified=False)`.

---

## 4. Why so much is asynchronous

Collecting the Tranche A findings, ERPNext defers work to background jobs for four reasons:

1. **The write is too slow to do inline.** Repost of stock valuation after a backdated entry is
   O(subsequent entries) — because valuation state is stored inside the event row (doc 02, D6).
2. **The write would take a long lock.** Recomputing `Bin`, `outstanding_amount`,
   `per_delivered_qty` for many documents.
3. **The write is a bulk operation.** `Transaction Deletion Record` (doc 09 §5.1),
   POS consolidation (doc 13 §4).
4. **The write is genuinely external.** Email, gateway calls, PDF generation.

Only (4) is intrinsic. (1)–(3) are consequences of storing derived state — and each carries the
same cost: **a window in which the database is knowably wrong**, plus a retry story with no
idempotency, plus an email to a human when it fails.

---

## 5. Our design

### 5.1 Correctness never depends on a job

The load-bearing rule: **anything that must be true is true at commit time.**

| ERPNext job | Why it exists | Our answer |
|---|---|---|
| `Repost Item Valuation` | valuation state inside the event row | `stock_move` (immutable) + `stock_valuation_state` (projection) — a backdated move recomputes the projection **in the same transaction**, bounded by moves after that point for one `(item, warehouse)` (D6, doc 16 §5.1) |
| `Repost Payment Ledger` | `outstanding_amount` is a cache | `outstanding` is a view (D9) |
| `Repost Accounting Ledger` | GL rows embed derived values | GL is append-only; corrections are new vouchers (D5) |
| `update_invoice_status` | `status` is a stored column | status is a view over `fulfilment_doc` + `schedule_outstanding` (doc 10 §5.3) |
| `run_ledger_health_checks` | invariants unenforced | invariants are constraints; there is nothing to check |
| POS consolidation | POS posts nothing at submit | POS sales post inline (doc 13 §7.1) |
| Bin recomputation | twelve cached counters | trigger-maintained projection + views (doc 16 §5.1) |

What remains asynchronous is only category (4) plus genuinely deferrable business processes
(deferral recognition, dunning runs, statement mailing, reorder proposals) — and each of those
produces **proposals or communications**, never a correction to something that was already wrong.

### 5.2 The job table is in the database

```sql
CREATE TABLE job (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     uuid REFERENCES company(id),
    kind           job_kind NOT NULL,             -- enum, compile-time registry (doc 21 §6.1)
    idempotency_key text NOT NULL,
    payload        jsonb NOT NULL,
    state          job_state NOT NULL DEFAULT 'queued',   -- 'queued','running','succeeded','failed','dead'
    priority       smallint NOT NULL DEFAULT 100,
    run_after      timestamptz NOT NULL DEFAULT now(),
    attempts       smallint NOT NULL DEFAULT 0,
    max_attempts   smallint NOT NULL DEFAULT 8,
    locked_by      text,
    locked_at      timestamptz,
    last_error     text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz,
    UNIQUE (kind, idempotency_key)
);
CREATE INDEX job_claim ON job (state, run_after, priority) WHERE state = 'queued';
```

Claiming:

```sql
UPDATE job SET state='running', locked_by=$worker, locked_at=now(), attempts=attempts+1
WHERE id = (SELECT id FROM job
            WHERE state='queued' AND run_after <= now()
            ORDER BY priority, run_after
            FOR UPDATE SKIP LOCKED LIMIT 1)
RETURNING *;
```

Why this rather than Redis+RQ:

- **`UNIQUE (kind, idempotency_key)` makes deduplication a database constraint**, not a
  check-then-enqueue against Redis (§2.2). Enqueueing the same logical job twice is a no-op via
  `ON CONFLICT DO NOTHING`.
- **Enqueue is transactional.** A job row is inserted in the same transaction as the business
  change that requires it. No `enqueue_after_commit` flag (§1.2), no "committed but job lost"
  window, no "job ran before the data was visible".
- **`FOR UPDATE SKIP LOCKED`** is a real, cross-host claim. A crashed worker's row is reclaimed by
  a reaper on `locked_at` age — same idea as the file-lock steal (§3.1), but with the lock in the
  database where the work is.
- **`state = 'dead'` is a durable dead-letter** with the full payload and `last_error`, in the
  database, queryable, retryable. Nothing is lost to registry truncation (§1.1).
- **Handlers must be idempotent, and the `idempotency_key` makes that testable.** Retry after a
  partial commit is safe because handlers are written as "apply if not already applied", keyed on
  the same key.
- Exponential backoff via `run_after = now() + interval`, not `time.sleep(retry + 1)` inside the
  worker (§1.1).

The cost is throughput: a database-backed queue tops out lower than Redis. That is an acceptable
trade for financial work, and nothing prevents adding a Redis fast path later for the
non-transactional category (4) jobs.

### 5.3 Scheduling

```sql
CREATE TABLE schedule (
    id            uuid PRIMARY KEY,
    company_id    uuid REFERENCES company(id),
    kind          job_kind NOT NULL,
    cron          text NOT NULL,
    timezone      text NOT NULL,               -- IANA, per company
    jitter_seconds integer NOT NULL DEFAULT 0,
    is_enabled    boolean NOT NULL DEFAULT true,
    last_fired_at timestamptz,
    next_fire_at  timestamptz NOT NULL,
    UNIQUE (company_id, kind)
);
```

- **`timezone` per company**, so "daily at 00:00" means the company's midnight. ERPNext's
  `CRON_MAP` (§2.1) is evaluated in the site's single timezone — wrong for a group spanning
  regions, and a real problem for period-boundary jobs.
- **`jitter_seconds` is actually applied** when computing `next_fire_at`, fixing the discarded
  `maintenance_offset` (§2.1).
- **Firing is a claim on `next_fire_at`**, in the database:
  `UPDATE schedule SET next_fire_at = <next>, last_fired_at = now() WHERE id = $1 AND next_fire_at <= now()`
  — zero rows means another scheduler already fired it. No file lock (§2.2), no leader election
  needed for correctness.
- **No dormancy skipping.** Scheduled financial work runs whether or not the company was busy
  (§2.2 last point).
- Firing inserts a `job` row, so scheduled work and enqueued work share one execution path,
  one dead-letter, one idempotency model.

### 5.4 Locking

One rule: **contention is resolved by the database, on the row that owns the invariant.**

| Need | Mechanism |
|---|---|
| Concurrent stock movement on `(item, warehouse)` | `INSERT ... ON CONFLICT DO UPDATE` on `stock_on_hand` — takes the row lock as part of the statement (doc 16 §5.1) |
| Concurrent allocation against an obligation | deferred constraint trigger with `SELECT ... FOR UPDATE` on `payment_schedule` (doc 11 §6.3) |
| Concurrent budget commitment | same pattern on `budget_period` (doc 12 §1.6) |
| Concurrent reservation | same pattern on `stock_on_hand` (doc 16 §5.2) |
| Gapless numbering | `UPDATE ... RETURNING` on `numbering_counter` (doc 20 §3.2) |
| Concurrent document edit | `version integer` + `WHERE version = :expected` (doc 09 §7) |
| Long-running maintenance exclusivity | `pg_advisory_xact_lock` on a documented, enumerated key set |
| Job claim | `FOR UPDATE SKIP LOCKED` (§5.2) |

**No file locks anywhere.** No `hasattr` guards on whether advisory locks are available. No
engine branches. The set of advisory-lock keys is enumerated in one registry so deadlock ordering
can be reasoned about (ERPNext sorts by `item_code` for exactly this reason,
`stock/doctype/pick_list/pick_list.py:558`).

### 5.5 Observability

Because jobs and schedules are tables, the operational questions are queries:

- backlog: `SELECT kind, count(*) FROM job WHERE state='queued' GROUP BY 1`
- stuck: `WHERE state='running' AND locked_at < now() - interval '10 min'`
- dead letters: `WHERE state='dead'`
- overdue schedules: `WHERE next_fire_at < now() - interval '1 hour' AND is_enabled`

ERPNext's equivalents live in Redis (`get_jobs`, `frappe/utils/background_jobs.py:482`;
`RQ Job` virtual doctype) plus `Scheduled Job Log` plus `Error Log` — three places, one of them
non-durable.

---

## 6. Summary

| Frappe mechanism | Verdict | Our replacement |
|---|---|---|
| Redis/RQ queue, jobs not in the database | **Reject** for transactional work | `job` table, `FOR UPDATE SKIP LOCKED` (§5.2) |
| No idempotency key; retry re-runs the same call | **Reject** | `UNIQUE (kind, idempotency_key)` + idempotent handlers |
| Failed jobs discarded with the Redis registry | **Reject** | durable `state='dead'` with payload and error |
| `commit(chain=True)` on the exception path | **Reject** | error recording is a separate transaction |
| Retry only on deadlock/timeout, linear backoff, 5 attempts | **Reject** | configurable `max_attempts`, exponential `run_after` |
| `enqueue_after_commit` flag | **Reject** | enqueue is an insert in the same transaction |
| Scheduled jobs run as `Administrator` | **Reject** | jobs carry an explicit actor; RLS applies (doc 19 §7.1) |
| `maintenance_offset` computed then discarded (bug) | **Fix** | `jitter_seconds` applied to `next_fire_at` |
| Dedup by checking Redis for a job id | **Reject** | unique constraint |
| Scheduler singleton enforced by a file | **Reject** | `UPDATE ... WHERE next_fire_at <= now()` claim |
| Site timezone for all schedules | **Reject** | per-company IANA timezone |
| Dormant sites skip scheduled jobs | **Reject** | financial schedules always run |
| "Weak" file locks, documented as race-prone, used for GL rewrites | **Reject** | database row locks on the invariant-owning row |
| Ad-hoc `FOR UPDATE` where someone remembered | **Reject** | locking is part of each invariant's trigger, not per-call-site discretion |
| `in_configured_timeslot` for valuation correctness | **Reject** | valuation is computed inline (D6) |
| `run_ledger_health_checks` | **Reject** | constraints, not audits |
| `notify_error_to_stock_managers` | **Reject** | inconsistency cannot be committed; jobs that fail are visible as rows, not emails |
| `before_job` / `after_job` hooks | **Keep, narrowed** | fixed instrumentation points (tracing, metrics), not business logic |
| Job introspection UI | **Keep** | queries over `job` / `schedule` (§5.5) |

---

Cross-references: doc 02 (valuation and repost), doc 10 §7 / doc 11 §6.3 / doc 12 §1.3 /
doc 16 §2.1 (the lost-update family), doc 13 §4 (POS consolidation as a job),
doc 15 §6-§8 (the three repost subsystems), doc 21 (hooks, `scheduler_events`),
doc 25 (platform spec), `docs/design/FINAL-SCHEMA.md`.
