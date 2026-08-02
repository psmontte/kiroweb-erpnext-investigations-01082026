# 09 — Document Lifecycle, Approval, Reversals, and Deletions

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev) and
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (ERPNext) or
> `/projects/sandbox/frappe/frappe` (Frappe). Frappe paths are prefixed `frappe/`.

This is the document that ties everything else together. Every posting document in ERPNext
(invoice, payment, delivery, receipt, journal, stock entry) moves through the *same*
lifecycle machinery, implemented once in Frappe and specialised by ERPNext controllers.
If you get this layer wrong, everything downstream (ledgers, fulfilment, settlement) inherits
the defect.

---

## 1. The canonical state machine

### 1.1 `docstatus` is the only persisted state

Every submittable table has a single `docstatus smallint` column with exactly three values,
defined in `frappe/model/docstatus.py:5`:

| Value | Name      | Meaning                                    |
|-------|-----------|--------------------------------------------|
| `0`   | Draft     | Editable, no side effects posted           |
| `1`   | Submitted | Immutable (except allow-on-submit fields), side effects posted |
| `2`   | Cancelled | Side effects reversed; row retained        |

`DocStatus` is a subclass of `int` with `is_draft()`, `is_submitted()`, `is_cancelled()`
helpers (`frappe/model/docstatus.py:6`, `:9`, `:12`).

### 1.2 The legal transitions

`Document.check_docstatus_transition` (`frappe/model/document.py:1410`) is the whole
state machine. It is a hard-coded table:

```
0 → 0   _action = "save"
0 → 1   _action = "submit"                (requires meta.is_submittable, "submit" perm)
0 → 2   DocstatusTransitionError          ← cannot cancel a draft
1 → 1   _action = "update_after_submit"   (requires "submit" perm)
1 → 2   _action = "cancel"                (requires "cancel" perm)
1 → 0   DocstatusTransitionError          ← no un-submit
2 → *   ValidationError("Cannot edit cancelled document")
```

Key observations:

- **`2` is terminal.** There is no re-open. The only forward path from a cancelled document is
  *amend* — a brand-new document that copies the old one (§4).
- The transition check is bypassable: `self.flags.skip_docstatus_validation`
  (`frappe/model/document.py:1425`) short-circuits the entire function. Internal code paths
  set this flag freely.
- `0 → 2` is blocked, but `discard()` (`frappe/model/document.py:1793`) writes `docstatus = 2`
  *directly with `db_set`*, deliberately routing around `check_docstatus_transition`
  by setting `_action = "discard"`. So a draft *can* reach state 2 — it just goes through a
  different door and fires `before_discard`/`on_discard` instead of `before_cancel`/`on_cancel`.
  A discarded draft and a cancelled submitted document are indistinguishable by `docstatus`
  alone; you must inspect the audit trail to tell them apart. **This is a schema defect.**

### 1.3 The optimistic-lock check

`check_if_latest` (`frappe/model/document.py:1379`) reloads the row `FOR UPDATE`
(`load_doc_before_save`, `frappe/model/document.py:1859`) and compares
`previous.modified` with `self._original_modified`. Mismatch → `TimestampMismatchError`.

This is a **timestamp-based** optimistic lock, not a version counter. Consequences:

- Two writes inside the same `modified` granularity (microsecond in MariaDB `datetime(6)`)
  can both pass. Rare but real.
- Any code path that uses `db_set(..., update_modified=False)`
  (`frappe/model/document.py:1951`) mutates a submitted row *without* advancing the lock
  token. ERPNext uses this heavily for cached counters (`per_delivered_qty`, `outstanding_amount`).
  Those writes are therefore **unserialised** — see doc 04 §6 and doc 10 §7.

### 1.4 Hook ordering

`run_before_save_methods` (`frappe/model/document.py:1827`) and
`run_post_save_methods` (`frappe/model/document.py:1881`) define the full hook sequence:

| `_action`              | Before write                               | After write                                  |
|------------------------|--------------------------------------------|----------------------------------------------|
| `save`                 | `before_validate`, `validate`, `before_save` | `on_update`                                |
| `submit`               | `before_validate`, `validate`, `before_submit` | `on_update`, `on_submit`                  |
| `cancel`               | `before_cancel`                             | `on_cancel`, `check_no_back_links_exist`    |
| `update_after_submit`  | `before_update_after_submit`                | `on_update_after_submit`                    |

Then, unconditionally: `clear_cache`, `notify_update`, `update_global_search`,
`save_version`, `on_change`.

Two things matter enormously here:

1. **`validate` runs on submit too.** So validation code cannot assume "this is a draft".
   ERPNext exploits this: much of the posting *preparation* (totals, taxes, advances) happens
   in `validate`, and only the ledger writes happen in `on_submit`.
2. **`check_no_back_links_exist` runs *after* `on_cancel`.** By the time ERPNext discovers a
   dependent submitted document exists, `on_cancel` has already deleted GL entries, unlinked
   payments, and mutated other documents. The transaction is rolled back on throw, but any
   `frappe.db.commit()` inside `on_cancel` (and there are several in background paths) breaks
   that guarantee.
3. `flags.ignore_validate` (`frappe/model/document.py:1843`) skips *all four* before-write
   hooks including `validate`. Set by importers, patches, and several ERPNext internal calls.

### 1.5 There is no approval state

**This is the single most important structural finding of this document.**

ERPNext has *no* `approval_state` column and no approval step in the state machine. The
lifecycle is Draft → Submitted, period. Approval is grafted on in three unrelated,
non-composable ways:

**(a) Authorization Control** — `setup/doctype/authorization_control/authorization_control.py:154`
(`validate_approving_authority`). This is a *validation*, called from inside the submit path.
For Sales Invoice it is invoked at `accounts/doctype/sales_invoice/sales_invoice.py:424`.
The mechanics:

- `get_appr_user_role` (`:24`) resolves which role/user may approve, based on
  `Authorization Rule` rows matched by doctype, `based_on`, value bracket, company, and
  master (customer/item).
- `bifurcate_based_on_type` (`:117`) branches on `based_on`:
  `Grand Total`, `Average Discount`, `Customer-wise Discount`, `Itemwise Discount`,
  `Item-wise Discount`, `Not Applicable`.
- If the current user lacks the approving role, it **throws**. The document simply does not
  submit.

So "approval" here means: *the approver must be the person who clicks Submit.* There is no
"submitted, pending approval" state. A €1M invoice sits in Draft — indistinguishable from a
half-typed one — until a director personally opens it and submits it.

**(b) Workflow** — `frappe/model/workflow.py`. A `Workflow` document overlays a
*separate* field (`workflow_state_field`, typically `workflow_state`, a `Select`) with its own
states and transitions. `apply_workflow` (`frappe/model/workflow.py:119`) walks a transition,
then maps the target state's `doc_status` ("0"/"1"/"2") onto `docstatus`
(`frappe/model/workflow.py:205`). `validate_workflow` (`frappe/model/workflow.py:246`) is
called from `Document._validate` to reject illegal state moves.

Problems with this design:

- Workflow state lives in a **`Select` string column**, not a FK. No referential integrity to
  `Workflow Document State`. Renaming a state orphans every existing row.
- Workflow and Authorization Control do not know about each other. A workflow can drive a
  document to `docstatus = 1` while Authorization Control simultaneously throws — or, worse,
  the workflow's "approve" transition is performed by a user with the `submit` permission but
  not the approving role, and the throw surfaces as an opaque workflow failure.
- Cancellation is discoverable only by scanning states for `doc_status == "2"`
  (`can_cancel_document`, `frappe/model/workflow.py:234`).
- `set_workflow_state_on_action` (`frappe/model/workflow.py:446`) maps
  `{"update_after_submit": "1", "submit": "1", "cancel": "2"}` — i.e. direct
  `submit()`/`cancel()` calls *retro-fit* a workflow state, so the workflow can be desynchronised
  by any code that calls `doc.submit()` directly.

**(c) `pre_submit_validation`** — `accounts/utils.py:2774`, a doc-event hook that runs
`_run_pre_submit_checks` (`:2786`) → `_check_prev_docstatus` (`:2797`),
`_check_credit_limit_warn` (`:2805`), `_check_packed_qty_warn` (`:2856`). These are *warnings*
in one configuration and *throws* in another, governed by settings. Approval-adjacent policy
expressed as configurable validation severity.

**Our decision (D10).** We model approval as first-class state:

```
draft → pending_approval → approved → posted → {reversed}
                ↓
            rejected
```

`approval_state` is an enum column on every trade/financial document, with
`approval_policy_id` FK naming the policy that governed it, plus an append-only
`approval_event` table (`document_type`, `document_id`, `from_state`, `to_state`,
`actor_user_id`, `acted_at`, `comment`, `policy_rule_id`). Submit is then a *pure* state
transition that requires `approval_state = 'approved'`; posting is a separate transition.
The approver need not be the submitter. See `docs/design/FINAL-SCHEMA.md` §Lifecycle.

---

## 2. Submit: what actually happens

`submit()` → `_submit()` (`frappe/model/document.py:1763`) sets `docstatus = 1` and calls
`save()`. So *submission is a save* with a different `_action`. Everything happens in the
hooks.

For an ERPNext accounting document the effective sequence is:

```
before_validate       (regional overrides, e-invoice field prep)
validate              → set_missing_values          accounts_controller.py:569
                      → calculate_taxes_and_totals  accounts_controller.py:576
                      → set_advances                accounts_controller.py:969
                      → validate_due_date           accounts_controller.py:615
                      → validate_company_in_accounting_dimension  :467
                      → validate_against_voucher_outstanding      :172
                      → (doctype-specific) validate_approving_authority
before_submit         (final gates: mandatory accounts, freeze dates)
--- DB write: docstatus 0 → 1 ---
on_update             (child-table sync, cached-field writes)
on_submit             → make_gl_entries         (doc 01)
                      → update_stock_ledger     (doc 02)
                      → update_prevdoc_status   (doc 06 / doc 10)
                      → update_outstanding      (doc 04)
on_change / save_version
```

The critical property: **the row is already `docstatus = 1` before any ledger row exists.**
Between the DB write and the end of `on_submit` there is a window where a submitted invoice
has no GL entries. Inside one transaction this is invisible. But ERPNext commits inside
several `on_submit` paths (repost enqueueing, background stock processing), and the
`Repost Item Valuation`/`Repost Accounting Ledger` machinery deliberately defers work to
background jobs. So the window is *observable in production*.

**Our decision.** Posting is its own state transition (`approved → posted`) executed in the
same transaction as the ledger inserts, and `posted_at` is `NOT NULL` whenever
`lifecycle_state = 'posted'`. A document is never "submitted but unposted"; it is either
`approved` (no ledger rows, enforced by a trigger/constraint check) or `posted`
(ledger rows exist, enforced by the balanced-voucher invariant F1).

---

## 3. Cancel: reversal by mutation and deletion

`cancel()` → `_cancel()` (`frappe/model/document.py:1768`) sets `docstatus = 2` and saves.
`on_cancel` then performs the reversal. ERPNext's reversal is **not** a compensating entry
in the general case — it is a mix of three different strategies depending on the ledger:

### 3.1 GL: flag-flip, or delete

`make_reverse_gl_entries` (`accounts/general_ledger.py:607`) is the "correct" path: it reads
the original entries and writes **negated copies** with `is_cancelled = 1`, then
`set_as_cancel` (`accounts/general_ledger.py:728`) marks the originals
`is_cancelled = 1`. Every downstream report must therefore filter `is_cancelled = 0`
(see doc 01 §7). Forgetting that filter is a recurring class of ERPNext bug.

But `AccountsController.on_trash` (`controllers/accounts_controller.py:419`) shows the other
path: if `Accounts Settings.delete_linked_ledger_entries` is on, deletion **physically
deletes** GL Entry, Stock Ledger Entry, Payment Ledger Entry, and Advance Payment Ledger
Entry rows for the voucher, via raw query-builder deletes (`:433`–`:447`).
So the immutability of the ledger is a *setting*, not a property.

`is_immutable_ledger_enabled` (`accounts/utils.py:2748`) gates a third behaviour where
cancellation must post a reversal on a *new* date rather than the original date.
Three coexisting reversal semantics, selected by configuration.

### 3.2 Payment Ledger: delink and rewrite

`on_cancel` (`controllers/accounts_controller.py:1109`) calls, in order:

1. `remove_from_bank_transaction(self.doctype, self.name)` — strips the voucher from any
   `Bank Transaction Payments` child rows (doc 14).
2. For invoices/payments/journals: `cancel_system_generated_credit_debit_notes()` (`:1091`)
   cancels auto-created credit/debit-note Journal Entries; then
   `cancel_exchange_gain_loss_journal` (`accounts/utils.py:847`) and
   `cancel_common_party_journal` (`accounts/utils.py:924`).
3. If `Accounts Settings.unlink_payment_on_cancellation_of_invoice`:
   `unlink_ref_doc_from_payment_entries` (`accounts/utils.py:1035`) → which calls
   `remove_ref_doc_link_from_jv` (`:1042`) and `remove_ref_doc_link_from_pe` (`:1084`).
   These **UPDATE** the payment's child rows to blank the reference, then
   `update_accounting_ledgers_after_reference_removal` (`accounts/utils.py:964`) rewrites
   GL/PLE rows.
4. For orders, the same unlinking gated by
   `unlink_advance_payment_on_cancelation_of_order`.
5. `Sales Order.on_cancel` additionally calls `unlink_ref_doc_from_po`
   (`controllers/accounts_controller.py:1138`) which **nulls `sales_order` / `sales_order_item`
   on live `Purchase Order Item` rows** via a filtered `frappe.db.set_value`. A cancelled SO
   therefore silently severs the drop-ship link on a *submitted* PO, and the PO's own
   `modified` is not the guard — the write is a bulk update.

The pattern: cancellation **edits other submitted documents in place**. There is no
compensating record of the un-linking; the previous allocation is simply gone
(except for the optional `Unreconcile Payment` document, doc 04 §5).

### 3.3 The `before_cancel` reference sweep

`_remove_references_in_repost_doctypes` (`controllers/accounts_controller.py:362`) refuses
to proceed if any **cancelled** `Repost Payment Ledger Items` / `Repost Accounting Ledger Items`
row references the voucher (`:377`–`:384`), demanding the user delete them manually. Otherwise
it strips the rows from the parent repost document with
`flags.ignore_validate_update_after_submit = True` and `flags.ignore_links = True` (`:405`–`:407`)
— i.e. it edits a submitted repost document while explicitly disabling the guards that exist
to prevent exactly that.

`_remove_references_in_unreconcile` (`:331`) does the same to `Unreconcile Payment`, and then
(`:355`–`:361`) **cancels and deletes** any `Unreconcile Payment` whose `voucher_no` is this
document. So the audit record of a previous un-allocation is destroyed when the voucher is
cancelled.

`_remove_advance_payment_ledger_entries` (`:410`) hard-deletes `Advance Payment Ledger Entry`
rows in both directions (`voucher_*` and `against_voucher_*`).

### 3.4 Our reversal model

**Decision D5 (immutable ledgers).** No `is_cancelled`, no `delinked`, no physical deletes.

- `gl_entry`, `stock_move`, `ar_ap_entry`, `settlement` are **append-only**
  (enforced by `REVOKE UPDATE, DELETE` and a `BEFORE UPDATE OR DELETE` trigger that raises).
- Reversal is a **new voucher**: `reverses_voucher_id uuid UNIQUE REFERENCES voucher(id)`.
  `UNIQUE` gives idempotency — a voucher can be reversed at most once, enforced by the
  database rather than by a flag check.
- The reversal voucher carries its own `posting_date` (which may differ from the original,
  satisfying the closed-period case that ERPNext handles with
  `is_immutable_ledger_enabled`) and its own `approval_state`.
- Un-allocation is a **compensating `settlement` row** with negated `allocated_amount` and
  `reverses_settlement_id` (decision D8), not an UPDATE of the payment document.
- Balances are views (decision D9), so a reversal automatically corrects every derived figure
  with no cache invalidation, no repost queue, and no `is_cancelled` filter to forget.

Full invariant list in `docs/design/FINAL-SCHEMA.md` §Invariant register (F1–U1).

---

## 4. Amend: the pseudo-edit

Because `2` is terminal and `1 → 0` is illegal, "editing a posted document" is expressed as:
cancel, then **amend**. Amend creates a *new* document with `amended_from` pointing at the
cancelled one.

- `validate_amended_from` (`frappe/model/document.py:868`) clears `amended_from` unless the
  referenced doc is actually cancelled.
- `copy_attachments_from_amended_from` (`frappe/model/document.py:875`) re-attaches files.
- `_set_amended_name` (`frappe/model/naming.py:569`) derives the new name. With
  `Document Naming Settings.amend_naming_override` behaviour, the amended name is either
  `ORIG-1`, `ORIG-2`, … or a fresh series number. **The suffix scheme means the document
  identifier encodes revision history in a string**, which is unparseable and non-monotonic
  across renames.
- `AccountsController.clear_clearance_date_on_amend`
  (`controllers/accounts_controller.py:120`) wipes bank clearance dates on the new copy.
- `revert_series_if_last` (`frappe/model/naming.py:446`) attempts to *decrement* the naming
  counter when the last-issued name is deleted. This is a read-modify-write on
  `Series.current` and is not safe under concurrency; it exists purely to avoid gaps in
  legally-numbered sequences.

The amend chain is therefore: `D-0001` (cancelled) ← `D-0001-1` (cancelled) ← `D-0001-2` (live).
Reconstructing "what did this order look like on Tuesday" requires walking `amended_from`
across rows whose child-row identities are entirely different (child `name` values are
regenerated). **There is no stable line identity across an amend.** Every fulfilment link
(`sales_order_item`) that pointed at the old line is dangling or was rewritten.

**Our decision.** Documents have a stable `id uuid` and lines have a stable `line_id uuid`
that survive revisions. Revisions are `document_revision` rows (append-only snapshot of the
mutable header/line payload with `revision_no`, `superseded_at`), not new documents. Posted
documents are corrected by reversal + new document, but *fulfilment links target the stable
`line_id`*, so a correction does not orphan the chain.

---

## 5. Delete: the linked-document maze

`frappe.delete_doc` (`frappe/model/delete_doc.py:24`) is the entry point. The order of
operations:

1. `check_permission_and_not_submitted` (`:280`) — a **submitted** document cannot be
   deleted; it must be cancelled first (unless `force`).
2. `check_if_doc_is_linked` (`:376`) → `get_linked_docs` (`:301`) scans every `Link` field
   pointing at this doctype and throws `raise_link_exists_exception` (`:474`) if a live
   referrer exists.
3. `check_if_doc_is_dynamically_linked` (`:464`) → `get_dynamic_linked_docs` (`:386`) does
   the same for `Dynamic Link` (`link_doctype`/`link_name`) pairs. **This is a full scan of
   every table with a Dynamic Link field**, because there is no index that maps
   (`link_doctype`, `link_name`) globally.
4. `add_to_deleted_document` (`:226`) stores a JSON snapshot in `Deleted Document` — the only
   trace left.
5. `update_naming_series` (`:238`) reverts the counter.
6. `delete_from_table` (`:247`) deletes the row and its child rows.
7. `delete_dynamic_links` (`:490`), `delete_references` (`:508`), `clear_references` (`:520`),
   `clear_timeline_references` (`:538`) clean up Comments, ToDos, Versions, etc.

The design flaw is structural: **referential integrity is enforced in application code by
scanning, not by the database.** There are no `FOREIGN KEY` constraints in a stock Frappe
schema. Consequences:

- Any code path with `ignore_links = True` (used liberally, e.g.
  `controllers/accounts_controller.py:406`, `:351`) creates dangling references immediately.
- Dynamic Links are unenforceable in principle. `Dynamic Link` scanning is O(tables), and the
  code maintains an `ignored_doctypes` set (`:308`) which grows by convention.
- `Deleted Document` is a JSON blob; child rows are inside the parent's JSON. Restoration is
  best-effort.

### 5.1 Bulk deletion: Transaction Deletion Record

Deleting *a company's* transactions is a whole subsystem:
`setup/doctype/transaction_deletion_record/transaction_deletion_record.py`.

- `get_protected_doctypes` (`:71`) / `_get_protected_doctypes_internal` (`:99`) — a
  hard-coded/derived allowlist of masters that must survive.
- `validate_to_delete_list` (`:172`) and `_is_any_doctype_in_deletion_list` (`:230`).
- `generate_to_delete_list` (`:389`) enumerates every doctype with a company field
  (`get_company_link_fields`, `:78`; `_has_company_field`, `:364`).
- Execution is **chunked background tasks**: `enqueue_task` (`:583`), `execute_task` (`:605`),
  `start_deletion_tasks` (`:655`), with job-name generation (`:238`, `:243`, `:252`) and a
  running-job guard (`validate_running_task_for_doc`, `:632`;
  `is_deletion_doc_running`, `:1096`; `check_for_running_deletion_job`, `:1118`).
- Special-cases: `delete_bins` (`:663`), `delete_lead_addresses` (`:689`),
  `reset_company_values` (`:735`), `delete_version_log` (`:976`),
  `delete_communications` (`:982`), `delete_comments` (`:995`),
  `unlink_attachments` (`:1002`), `update_naming_series` (`:956`).
- `delete_company_transactions` (`:781`) is the legacy monolith still present.

The existence of ~950 lines of code, a protected-doctype allowlist, chunked background jobs,
and a global "deletion in progress" cache to delete rows for one company is the clearest
possible evidence that **`company` is not a real partition key** in this schema.

**Our decision (D2).** `company_id` is `NOT NULL` on every business row, is part of every
composite unique key, and is enforced by row-level security. Deleting a company's data is
`DELETE FROM ... WHERE company_id = $1` in dependency order — or better, a partition drop.
`ON DELETE RESTRICT` on ledger FKs means the database, not a Python allowlist, decides what
may be removed.

---

## 6. Rename: identifiers as data

`rename_doc` (`frappe/model/rename_doc.py:108`) exists because **the primary key is a
human-readable string** (`name varchar(140)`), so business renames are PK updates.
It must therefore rewrite every referring column:

- `get_link_fields` (`:460`) enumerates referrers; `update_link_field_values` (`:421`) updates
  them.
- `rename_parent_and_child` (`:320`), `update_child_docs` (`:411`) fix child rows.
- `update_assignments` (`:236`), `update_user_settings` (`:260`),
  `update_customizations` (`:299`), `update_attachments` (`:303`),
  `rename_versions` (`:312`), `update_options_for_fieldtype` (`:513`),
  `get_select_fields` (`:545`) patch metadata and UI state.
- `validate_rename` (`:335`) does a `SELECT ... FOR UPDATE` existence check (`:352`).
- `merge = True` folds one document into another, deleting the source.

Dynamic Links are **not** reliably updated. Any (`link_doctype`, `link_name`) pair stored
outside the enumerated link fields silently rots.

**Our decision.** Surrogate `uuid` PKs everywhere; the human-facing number is a separate
`doc_no` column with a company-scoped unique index. Renaming is a one-row UPDATE of `doc_no`
with zero cascade. `doc_no` sequences come from a `numbering_series` table with
`nextval`-style allocation (no read-modify-write, no gap-filling, no counter reversion).

---

## 7. What we take, what we reject

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Three-value `docstatus` | Keep the *idea* | `lifecycle_state` enum: `draft`, `pending_approval`, `approved`, `posted`, `reversed`, `cancelled_draft` |
| Approval by "approver must submit" | **Reject** | `approval_state` + `approval_policy` + `approval_event` audit table (D10) |
| Workflow state in a `Select` column | **Reject** | FK to `workflow_state` rows; transitions validated against `workflow_transition` |
| `validate` running on both save and submit | **Reject** | Distinct `validate_draft` vs `validate_for_posting` rule sets, so posting-only rules cannot be skipped by `ignore_validate` |
| Timestamp optimistic lock | **Reject** | `version integer` column, `WHERE version = $n` on every UPDATE |
| `is_cancelled` flag-flip reversal | **Reject** | Append-only ledgers + `reverses_voucher_id UNIQUE` (D5) |
| Physical delete of ledger rows (`delete_linked_ledger_entries`) | **Reject** | Impossible: `REVOKE DELETE` + trigger |
| Cancellation editing other submitted docs | **Reject** | Compensating rows only (D8); no in-place edits of posted documents |
| `check_no_back_links_exist` *after* `on_cancel` | **Reject** | FK `ON DELETE RESTRICT` / dependency check *before* any side effect |
| Amend chain with regenerated child names | **Reject** | Stable `id`/`line_id`; revisions in `document_revision` (§4) |
| Referential integrity by table scanning | **Reject** | Real `FOREIGN KEY` constraints (2 051 of them in our verified DDL) |
| Dynamic Links | **Reject** | Concrete FK columns per relationship; `doc_link` for the one genuinely polymorphic case (fulfilment, doc 10), with a CHECK-constrained `(from_type, to_type)` pair |
| String PK + `rename_doc` cascade | **Reject** | `uuid` PK + mutable `doc_no` |
| `Transaction Deletion Record` subsystem | **Reject** | `company_id` partition key + RLS (D2) |
| `revert_series_if_last` | **Reject** | Gap-tolerant sequences; legal gapless numbering handled by a separate `document_number_register` assigned at *posting* time |

---

## 8. Our lifecycle, precisely

```
                 ┌────────────────────── create ──────────────────────┐
                 ▼                                                    │
            ┌────────┐  edit (version++)                              │
            │ draft  │◀──────────────┐                                │
            └───┬────┘               │                                │
                │ request_approval   │ withdraw                       │
                ▼                    │                                │
     ┌──────────────────┐────────────┘                                │
     │ pending_approval │──── reject ────▶ ┌──────────┐               │
     └────────┬─────────┘                  │ rejected │──── reopen ───┘
              │ approve                     └──────────┘
              ▼
        ┌──────────┐   post (ledger insert, same txn)
        │ approved │──────────────────────────┐
        └────┬─────┘                          ▼
             │ discard                   ┌────────┐
             ▼                           │ posted │
      ┌───────────────┐                  └───┬────┘
      │ cancelled_draft│                     │ reverse (new voucher)
      └───────────────┘                      ▼
                                        ┌──────────┐
                                        │ reversed │  (terminal)
                                        └──────────┘
```

Rules enforced in the database, not in application code:

- **L1.** `posted_at IS NOT NULL ⟺ lifecycle_state IN ('posted','reversed')`.
- **L2.** No `gl_entry` / `stock_move` / `ar_ap_entry` row may reference a voucher whose
  `lifecycle_state` is not in (`posted`, `reversed`) — deferrable constraint trigger.
- **L3.** `lifecycle_state = 'posted'` rows are immutable except for a whitelist of
  operational fields, enforced by a `BEFORE UPDATE` trigger comparing `OLD`/`NEW`.
- **L4.** `reverses_voucher_id` is `UNIQUE` and the referenced voucher must be `posted`;
  reversing flips it to `reversed` in the same statement.
- **L5.** Every state transition writes exactly one `approval_event` / `lifecycle_event` row
  (`from_state`, `to_state`, `actor`, `at`). Enforced by trigger, so the audit trail cannot be
  bypassed by `db_set`.
- **L6.** `version` increments on every UPDATE (trigger), and all application UPDATEs carry
  `WHERE version = :expected`.

Cross-references: doc 01 (GL posting), doc 04 (settlement), doc 06 (status/returns),
doc 10 (fulfilment), doc 11 (advances/allocation), `docs/design/FINAL-SCHEMA.md`.
