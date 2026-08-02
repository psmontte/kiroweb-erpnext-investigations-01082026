# 47 — E-Invoice and E-Way Bill: External State Machines

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, `17.0.0-dev`).
>
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/`; India Compliance citations are prefixed `india_compliance/` and are relative to
> `/projects/sandbox/india_compliance/india_compliance`.

Docs [45](45-gst-registration-settings-hsn-and-tax-structure.md) and
[46](46-gst-place-of-supply-and-component-determination.md) covered configuration and determination — both
internal. This document covers the part of GST that is **not internal**: two government endpoints that mint
legally binding artefacts.

That changes the engineering problem entirely. Everywhere else in this investigation, a duplicate write is a
constraint violation we can prevent. Here, a duplicate write **creates a second legal document with a real
tax consequence**, and the remote system — not our database — is the system of record. Three properties
follow:

1. **Success may be unknown.** A request can succeed at the portal while the response is lost.
2. **Correction is time-boxed by statute**, not by policy: an IRN can be cancelled for 24 hours, and after
   that the only remedy is a credit note.
3. **The artefact is signed**, and the signature is the evidence — not our copy of the numbers.

Invariants continue from doc 46 at **G17**.

---

## 1. The two artefacts

| | e-Invoice | e-Way Bill |
|---|---|---|
| Identifier | **IRN** (Invoice Reference Number) | **e-Waybill number** |
| What it proves | the invoice was reported to the portal before supply | goods in transit are authorised |
| Implementation | `india_compliance/gst_india/utils/e_invoice.py` (1,035 lines) | `india_compliance/gst_india/utils/e_waybill.py` (2,013 lines) |
| Log | `e-Invoice Log` — a bare `Document` (`india_compliance/gst_india/doctype/e_invoice_log/e_invoice_log.py:8-9`) | `e-Waybill Log` — one print hook (`india_compliance/gst_india/doctype/e_waybill_log/e_waybill_log.py:12-20`) |
| Lifecycle | generate → (cancel ≤ 24h) | generate → update vehicle → extend validity → cancel |

Both logs are keyed by the **portal's identifier**, not by our document — which is the right instinct, and
becomes important in §3.

---

## 2. Applicability: when the obligation exists

`validate_e_invoice_applicability` refuses in a fixed order
(`india_compliance/gst_india/utils/e_invoice.py:531-578`):

| Condition | Outcome |
|---|---|
| `doc.irn` already set | `AlreadyGeneratedError` |
| `company_gstin == billing_address_gstin` | not applicable — a supply to yourself |
| neither `96-Other Countries` nor a billing GSTIN | not applicable — B2C |
| `enable_e_invoice` off | not applicable |
| policy is `Do Not Generate` and **no** item is in `TAXABLE_GST_TREATMENTS` | not applicable |
| no applicability date for the company | not applicable |
| `applicability_date > posting_date` | not applicable |

This is a well-formed obligation test, and the self-supply exclusion matches the GST rule doc 46 §3 already
enforces. Note the third row: B2C is excluded **unless** the place of supply is the magic
`"96-Other Countries"` string — the same display-string-as-code coupling doc 46 §2.1 flagged, now deciding
whether a legal obligation exists.

Separately, `e_invoice_reporting_time_limit_days` blocks generation once the posting date is older than the
configured window (`india_compliance/gst_india/utils/e_invoice.py:120-150`). A statutory deadline expressed
as a settings integer.

> **Invariant G17 — a statutory obligation is a derived, dated fact.** Whether an external artefact is
> required for a document is decided by the jurisdiction rule revision in force **on the posting date**, and
> the decision is recorded on the document with the rule identity and the reason. Obligation is never
> re-derived from current settings, and never depends on parsing a display label.

---

## 3. Generating an IRN, and the duplicate problem

### 3.1 The happy path and its error ladder

`generate_e_invoice` builds the payload, calls `generate_irn`, and then handles outcomes in a specific order
(`india_compliance/gst_india/utils/e_invoice.py:120-268`):

```text
if result.InfCd == "DUPIRN":                      → reconcile against the existing IRN (§3.2)
if result.error_code in (3028, 3029, 3001):       → sync the GSTIN, then RETRY generate_irn once
if not result.Irn:                                → throw "e-Invoice generation failed"
```

The exception ladder is where the design shows real care:

| Exception | Handling |
|---|---|
| `GSPServerError` | `handle_server_errors` → status `Auto-Retry`, **no rollback** |
| `AlreadyGeneratedError` | warn, return |
| `NotApplicableError` | **rollback**, status `Not Applicable`, commit |
| `ValidationError` / `MandatoryError` | **rollback**, status `Failed`, commit |
| anything else | **rollback**, status `Failed`, commit, re-raise |

Distinguishing "the portal is down" (retry) from "this invoice is wrong" (fail) from "no obligation exists"
(not applicable) is exactly the right taxonomy, and each branch persists its status with an explicit commit
so the outcome survives the rollback. This is the most mature error handling in the whole tranche.

### 3.2 `DUPIRN`: idempotency by reconciliation

When the portal reports a duplicate, the app does not assume the existing IRN belongs to this invoice. It
fetches it and **compares identity** (`india_compliance/gst_india/utils/e_invoice.py:269-332`):

```text
fetch IRN details by IRN
  if error 2283 ("generated more than 2 days ago") and portal fetch enabled → retry via taxpayer API
  if a SignedInvoice came back → verify_e_invoice_details(...)
```

`verify_e_invoice_details` decodes the signed payload and compares the **buyer GSTIN** and the **total
invoice value** against the current document; on mismatch it refuses to attach the IRN and tells the user to
issue a new invoice (`india_compliance/gst_india/utils/e_invoice.py:333-366`).

That is genuine idempotency-by-reconciliation against an external system of record, and it is the pattern our
design should adopt. But the decode is:

```python
jwt.decode(signed_data, options={"verify_signature": False})
```

(`india_compliance/gst_india/utils/e_invoice.py:333-366`). **The government's signature is not verified.**
The signed invoice is the legally meaningful artefact precisely *because* it is signed; discarding the
signature reduces it to a self-asserted blob, and the comparison that guards against attaching someone
else's IRN trusts unauthenticated content. Two fields are compared — GSTIN and total — so a duplicate with
matching totals but different line detail passes.

### 3.3 The log is written asynchronously

`log_e_invoice` **enqueues** the log write on the short queue and separately updates the document's onload
cache (`india_compliance/gst_india/utils/e_invoice.py:507-517`). `_log_e_invoice` then does a get-or-create
keyed by IRN, swallowing the not-found message
(`india_compliance/gst_india/utils/e_invoice.py:518-530`).

So the record of a legally binding artefact is written **outside the transaction that recorded its effect**,
by a background job, with no idempotency receipt of its own. If that job is lost, the document says an IRN
exists and the log does not — and §4 shows the log is where the cancellation window is read from.

### 3.4 Manual assertion

`mark_e_invoice_as_generated` lets a user record an IRN, acknowledgement number and date by hand, with status
`Manually Generated` and **no portal verification**
(`india_compliance/gst_india/utils/e_invoice.py:471-487`); `mark_e_invoice_as_cancelled` does the same for
cancellation (`india_compliance/gst_india/utils/e_invoice.py:488-506`). Operationally necessary — portals
fail, and businesses must move — but it means the system contains two classes of artefact with identical
downstream treatment and very different evidential weight.

> **Invariant G18 — external artefacts are reconciled, not assumed.** Every request to a statutory endpoint
> is an append-only attempt record with an idempotency key, request hash and outcome, written **in the
> transaction that commits its effect**. A duplicate response triggers reconciliation against the remote
> record, and attachment requires that the returned artefact's **verified signature** and its full identifying
> content match this document. Manually asserted artefacts are a distinct, explicitly marked evidence class
> that cannot satisfy a rule requiring portal confirmation.

---

## 4. Cancellation windows

### 4.1 The 24-hour IRN rule

`validate_if_e_invoice_can_be_cancelled` requires an IRN and reads `acknowledged_on`
(`india_compliance/gst_india/utils/e_invoice.py:580-596`):

```text
if not acknowledged_on or acknowledged_on + 1 day < now:
    throw "e-Invoice can only be cancelled upto 24 hours after it is generated"
```

Correct statute, enforced at the right moment. Two weaknesses in *how* it is enforced.

First, `acknowledged_on` is read from `doc.get_onload()["e_invoice_info"]` — an **onload cache** populated by
a document hook — not from the log row directly. The comment says so explicitly ("this works because we do
run_onload in load_doc above"). A statutory deadline is being evaluated against a view-layer cache.

Second, when `acknowledged_on` is missing the branch **also** throws — which is safe, but is
indistinguishable from an expired window, and §3.3 established that the log write is asynchronous and can be
lost.

### 4.2 Cancellation erases the identifier

`_cancel_e_invoice` cancels a linked e-way bill first, sends the cancellation, logs it, then cancels the
document (`india_compliance/gst_india/utils/e_invoice.py:416-443`). The ordering is right — the e-way bill
depends on the IRN, so it goes first.

Then `log_and_process_e_invoice_cancellation` does this
(`india_compliance/gst_india/utils/e_invoice.py:444-470`):

```python
doc.db_set({"einvoice_status": "Cancelled", "irn": ""})
```

**The IRN is blanked on the document.** The identifier of a legally reported artefact is deleted from the
record that reported it, surviving only in a log row written by a background job. The e-way bill path does
the same: `data = {"ewaybill": ""}`
(`india_compliance/gst_india/utils/e_waybill.py:414-442`).

The stated reason is discoverable from `validate_e_invoice_applicability`: `if doc.irn: return _throw(...)`
(`india_compliance/gst_india/utils/e_invoice.py:531-578`). A non-empty `irn` means "already generated", so
clearing it is what permits regeneration. A **field doing double duty as a state flag** forces the erasure of
history.

There is also a fallback that fabricates a timestamp: when the portal returns error `9999`
("already cancelled"), `cancelled_on` is set to `get_datetime()` instead of the portal's `CancelDate`
(`india_compliance/gst_india/utils/e_invoice.py:444-470`). The e-way bill equivalent uses error `312`
(`india_compliance/gst_india/utils/e_waybill.py:414-442`). So a reconciled cancellation records **our** clock,
not the authority's.

> **Invariant G19 — statutory identifiers are append-only.** An IRN, e-way bill number or equivalent is
> recorded once with its issue instant, its status transitions and the authority's own timestamps, and is
> never blanked, overwritten or reused. Regeneration eligibility is derived from the artefact's **state**, not
> from the emptiness of an identifier field. Where the authority's timestamp is unavailable, the fact is
> marked as locally timestamped rather than presented as the authority's.

---

## 5. The e-way bill adds a mutable middle

An e-way bill is not write-once: while goods are in transit, the vehicle can change and validity can be
extended.

`update_vehicle_info` captures the old values before updating
(`india_compliance/gst_india/utils/e_waybill.py:443-512`) — good instinct, and `update_transporter`
(`india_compliance/gst_india/utils/e_waybill.py:572-623`) is the analogous path.

`extend_validity` writes vehicle and transport fields onto the document, calls the extend API, sets
`distance`, and updates the log
(`india_compliance/gst_india/utils/e_waybill.py:624-660`). Note the ordering: `doc.db_set(...)` happens
**before** the API call, so a failed extension leaves the document claiming details the portal never
accepted.

Scheduled extension is where the design gets fragile:

```text
get_e_waybills_to_extend():
    is_cancelled = 0 AND extension_scheduled = 1
    AND valid_upto BETWEEN (now − 1 day) AND now
```

(`india_compliance/gst_india/utils/e_waybill.py:661-684`). A **bounded window** — so an e-way bill whose
`valid_upto` fell outside that one-day band, because the job did not run, is never picked up. This is the
same defect class as the asset recognition job's `= nowdate()` filter (doc 41 §3.4), and it fails the same
way: silently, permanently, and on exactly the days when a scheduler outage matters.

Then `extend_scheduled_e_waybills` clears `extension_scheduled = 0` **before** attempting the extension, and
logs failures (`india_compliance/gst_india/utils/e_waybill.py:685-712`). So a failed extension is both
unscheduled and unextended: the flag that would cause a retry has already been consumed.

`find_matching_e_waybill` (`india_compliance/gst_india/utils/e_waybill.py:820-851`) and
`get_valid_and_invalid_e_waybill_log` (`india_compliance/gst_india/utils/e_waybill.py:938-1001`) exist to
recover from exactly these divergences — reconciliation tooling that is necessary because the state machine
leaks.

The PDF handling is a smaller version of the same issue: `attach_e_waybill_pdf`, `delete_file` and
`publish_pdf_update` (`india_compliance/gst_india/utils/e_waybill.py:884-932`) manage a derived artefact as
a mutable file attachment.

> **Invariant G20 — in-transit amendments are events, and scheduled work is self-healing.** Vehicle changes,
> transporter changes and validity extensions are append-only amendment facts against the artefact, each with
> its own idempotency key, request record and authority response. Local fields are updated only **after** the
> authority accepts. Scheduled work selects by open obligation (`due_at <= now AND not satisfied`), never by a
> bounded window, and a work claim is released on failure rather than consumed before the attempt.

---

## 6. Retry: a Single, a status string and a cleared flag

`retry_e_invoice_e_waybill_generation` is the recovery loop
(`india_compliance/gst_india/utils/e_invoice.py:597-612`):

```text
if sandbox_mode and not in_test:                                     return
if not (enable_retry and is_retry_einv_ewb_generation_pending):       return
settings.db_set("is_retry_einv_ewb_generation_pending", 0, update_modified=False)
generate_pending_e_invoices()
generate_pending_e_waybills()
```

The pending queues are **status scans**: Sales Invoices with `einvoice_status == "Auto-Retry"`
(`india_compliance/gst_india/utils/e_invoice.py:613-625`) and documents with
`e_waybill_status == "Auto-Retry"` (`india_compliance/gst_india/utils/e_waybill.py:765-787`).

Three problems, in increasing severity:

1. **The gate is cleared before the work.** If the process dies mid-run, `is_retry_einv_ewb_generation_pending`
   is already `0`, so the loop will not run again until something re-sets it — while documents remain in
   `Auto-Retry`.
2. **`update_modified=False`** means the flag change is invisible to optimistic concurrency and to audit.
3. **A status string is the queue.** There is no work item, no attempt count, no lease, no next-attempt time
   and no terminal failure state — so a permanently failing invoice is retried forever with no backoff, and
   two concurrent runs can pick up the same document.

Generation itself also refuses to run while a retry is pending unless forced: `raise GSPServerError` when
`enable_retry and is_retry_einv_ewb_generation_pending` and not `force`
(`india_compliance/gst_india/utils/e_invoice.py:120-150`). A global degraded-mode switch — sensible in
intent, and implemented as a mutable Single field that any process may clear.

> **Invariant G21 — external submission is durable work with a lease.** Each pending submission is a durable
> row with state, attempt count, next-attempt time, lease owner and expiry, and a terminal failure state with
> a reason. Claims use `FOR UPDATE SKIP LOCKED`; the claim is released or advanced **after** the attempt, never
> before. Degraded mode is a recorded, time-bounded condition, not a boolean any worker may clear.

---

## 7. Evidence versus projection

| Representation | Classification |
|---|---|
| the portal's signed invoice (JWT) | **the legal artefact** — decoded but signature unverified, not stored as such |
| `Sales Invoice.irn` | mutable field, **blanked on cancellation**, doubles as a state flag |
| `Sales Invoice.ewaybill` | same |
| `einvoice_status` / `e_waybill_status` | mutable status that also serves as the retry queue |
| `e-Invoice Log` row | keyed by IRN, written **asynchronously**, get-or-create |
| `e-Waybill Log` row | keyed by e-way bill number; carries `valid_upto`, `extension_scheduled`, `extension_data` |
| `acknowledged_on` (read at cancel time) | read from an **onload cache**, governs a statutory deadline |
| `cancelled_on` | authority timestamp, or **our clock** on a reconciled cancellation |
| `is_retry_einv_ewb_generation_pending` | mutable Single flag, cleared before the work it guards |
| `Manually Generated` / `Manually Cancelled` | user assertion, indistinguishable downstream |
| attached e-way bill PDF | derived file, deleted and recreated |
| `extension_scheduled` | consumed before the attempt |

Nothing in this table is an append-only attempt record. The request/response pair — the only thing that can
answer "what did we send, what did they say, and when" — is not persisted at all; only its digested outcome
is, and only sometimes, and sometimes by a job that may not run.

---

## 8. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md), doc 45 §8 and doc 46 §9. Money `numeric(19,4)`;
`company_id`-scoped with RLS and `FORCE RLS`; stable enum codes; append-only facts.

```sql
statutory_artefact(id, company_id, artefact_type statutory_artefact_enum /*e_invoice|e_waybill|
                       e_invoice_cancellation|import_declaration*/,
    jurisdiction_revision_id, tax_registration_id,
    source_doc_type text, source_doc_id bigint, tax_determination_id bigint NOT NULL,
    obligation_basis text NOT NULL,          -- which rule made this required
    authority_identifier varchar(128) NULL,  -- IRN / e-way bill number, once issued
    issued_at timestamptz NULL,              -- the AUTHORITY's timestamp
    valid_until timestamptz NULL,
    evidence_class evidence_class_enum /*authority_confirmed|manually_asserted*/,
    signed_payload text NULL, signature_verified bool NULL, signing_cert_id bigint NULL,
    state artefact_state_enum /*required|pending|issued|cancelled|expired|not_applicable|failed*/,
    command_receipt_id)
   UNIQUE (company_id, artefact_type, authority_identifier)
      WHERE authority_identifier IS NOT NULL
   UNIQUE (company_id, artefact_type, source_doc_type, source_doc_id, generation_no)
   CHECK ((state = 'issued') = (authority_identifier IS NOT NULL))
   CHECK (evidence_class <> 'authority_confirmed' OR signature_verified IS TRUE)
   -- authority_identifier is NEVER blanked; regeneration inserts a new row with generation_no + 1

statutory_artefact_event(id, company_id, statutory_artefact_id, event_no integer,
    event_type artefact_event_enum /*requested|issued|vehicle_updated|transporter_updated|
                                    validity_extended|cancelled|expired|rejected*/,
    authority_timestamp timestamptz NULL, local_timestamp timestamptz NOT NULL,
    timestamp_source timestamp_source_enum /*authority|local_fallback*/,
    reason_code text NULL, payload jsonb, domain_event_id bigint NOT NULL)
   UNIQUE (company_id, statutory_artefact_id, event_no)
   CHECK ((timestamp_source = 'authority') = (authority_timestamp IS NOT NULL))

statutory_submission_attempt(id, company_id, statutory_artefact_id, attempt_no integer,
    endpoint text, request_hash char(64), request_payload jsonb,
    response_code text NULL, response_payload jsonb NULL,
    outcome attempt_outcome_enum /*issued|duplicate_reconciled|rejected|transport_error|
                                  timeout_unknown|refused_locally*/,
    started_at timestamptz, completed_at timestamptz NULL,
    idempotency_key varchar(128) NOT NULL, command_receipt_id)
   UNIQUE (company_id, statutory_artefact_id, attempt_no)
   UNIQUE (company_id, idempotency_key)

statutory_submission_work(id, company_id, statutory_artefact_id,
    state work_state_enum /*queued|running|retryable|failed|completed|cancelled*/,
    attempts integer NOT NULL DEFAULT 0, next_attempt_at timestamptz,
    lease_owner text NULL, lease_until timestamptz NULL,
    terminal_reason text NULL)
   UNIQUE (company_id, statutory_artefact_id) WHERE state IN ('queued','running','retryable')

statutory_cancellation_window(company_id, jurisdiction_revision_id, artefact_type,
    window_hours integer, basis window_basis_enum /*authority_issue_time|posting_date*/)
   UNIQUE (company_id, jurisdiction_revision_id, artefact_type)
```

The decisions that matter:

- **`timeout_unknown` is a first-class outcome.** A lost response is neither success nor failure; the next
  action is *reconcile*, never *resubmit*. This is the case upstream handles only via `DUPIRN` after the
  fact.
- **`signature_verified` gates `authority_confirmed`.** A signed artefact whose signature we did not verify
  cannot be recorded as authority-confirmed, so the `jwt.decode(..., verify_signature=False)` shortcut is
  structurally unavailable.
- **The cancellation window is a rule revision**, evaluated against `issued_at` — the authority's timestamp —
  not against an onload cache, and not a literal `days=1`.
- **`authority_identifier` is never blanked**, so `UNIQUE (company_id, artefact_type, authority_identifier)`
  can be a real constraint and history survives cancellation. Regeneration is a new row.
- **Timestamp provenance is explicit.** `timestamp_source` records whether the authority told us or we
  guessed.

**Write ordering** for a submission:

```text
1  determine obligation from the jurisdiction rule revision on the posting date → statutory_artefact(state=required)
2  claim statutory_submission_work under FOR UPDATE SKIP LOCKED; set lease
3  insert statutory_submission_attempt (request_hash, idempotency_key) BEFORE the call
4  call the endpoint
5a issued              → insert 'issued' event with the authority timestamp; state=issued; complete work
5b duplicate           → fetch remote artefact; VERIFY signature; compare full identifying content;
                         attach only on exact match, else state=failed with a reason
5c rejected            → state=failed, terminal_reason, no retry
5d transport/timeout   → outcome recorded; work state=retryable with backoff; NEVER resubmit blind
6  release the lease; outbox ; commit ; project document-facing status
```

Every branch persists an attempt row, so "what did we send and what came back" is always answerable — which
is the one question the current implementation cannot answer.

> **Invariant G22 — relational artefact integrity.** Unique, foreign-key, check and partial-unique
> constraints enforce one artefact per document per generation, one attempt per number, uniqueness of an
> authority identifier per type, at most one open work item per artefact, and the coupling between state,
> identifier, evidence class and signature verification.

---

## 9. Defects, races and unfinished paths

1. **The authority's signature is not verified.** `jwt.decode(signed_data, options={"verify_signature":
   False})` guards the duplicate-IRN comparison
   (`india_compliance/gst_india/utils/e_invoice.py:333-366`).
2. **Duplicate reconciliation compares only two fields** — buyer GSTIN and total value
   (`india_compliance/gst_india/utils/e_invoice.py:333-366`).
3. **The IRN is blanked on cancellation**, destroying the identifier on the document
   (`india_compliance/gst_india/utils/e_invoice.py:444-470`); same for `ewaybill`
   (`india_compliance/gst_india/utils/e_waybill.py:414-442`).
4. **An identifier field doubles as a state flag**, which is what forces the erasure
   (`india_compliance/gst_india/utils/e_invoice.py:531-578`).
5. **The log write is enqueued**, outside the transaction that recorded the effect, with no idempotency
   receipt (`india_compliance/gst_india/utils/e_invoice.py:507-530`).
6. **A statutory deadline is read from an onload cache**
   (`india_compliance/gst_india/utils/e_invoice.py:580-596`).
7. **The 24-hour window is a literal**, not a jurisdiction rule
   (`india_compliance/gst_india/utils/e_invoice.py:580-596`).
8. **Our clock is recorded as the cancellation time** on reconciled cancellations — error `9999` for
   e-invoice (`india_compliance/gst_india/utils/e_invoice.py:444-470`), `312` for e-way bill
   (`india_compliance/gst_india/utils/e_waybill.py:414-442`).
9. **No request/response is persisted** — only digested outcomes (§7).
10. **The retry gate is cleared before the work it guards**, with `update_modified=False`
    (`india_compliance/gst_india/utils/e_invoice.py:597-612`).
11. **A status string is the work queue** — no attempts, lease, backoff or terminal state
    (`india_compliance/gst_india/utils/e_invoice.py:613-625`,
    `india_compliance/gst_india/utils/e_waybill.py:765-787`).
12. **Scheduled extension selects a bounded one-day window**, so a missed run never recovers
    (`india_compliance/gst_india/utils/e_waybill.py:661-684`).
13. **`extension_scheduled` is consumed before the attempt**, so a failure loses the retry
    (`india_compliance/gst_india/utils/e_waybill.py:685-712`).
14. **Extension writes local fields before the API accepts them**
    (`india_compliance/gst_india/utils/e_waybill.py:624-660`).
15. **Manually asserted artefacts are indistinguishable downstream**
    (`india_compliance/gst_india/utils/e_invoice.py:471-506`).
16. **Obligation depends on a display string** — `place_of_supply == "96-Other Countries"`
    (`india_compliance/gst_india/utils/e_invoice.py:531-578`).
17. **A statutory reporting deadline is a settings integer**
    (`india_compliance/gst_india/utils/e_invoice.py:120-150`).
18. **Degraded mode is a mutable Single field** any process may clear
    (`india_compliance/gst_india/utils/e_invoice.py:120-150`).
19. **Reconciliation tooling exists because the state machine leaks** —
    `find_matching_e_waybill` (`india_compliance/gst_india/utils/e_waybill.py:820-851`),
    `get_valid_and_invalid_e_waybill_log` (`india_compliance/gst_india/utils/e_waybill.py:938-1001`).

No lock, lease or unique constraint was found around: `Auto-Retry` scan → generation; retry-flag read →
clear; `extension_scheduled` read → extension; or IRN presence check → `generate_irn`.

> **Invariant G23 — serializable external submission.** Obligation creation, submission claiming, artefact
> attachment, amendment and cancellation are bounded writes under deterministic locks with idempotency keys
> and database uniqueness. Two workers cannot submit the same obligation, and no submission occurs without an
> attempt row committed first.

---

## 10. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Applicability test before generation | **Adopt** | obligation derived from the dated jurisdiction rule |
| Self-supply and B2C exclusions | **Adopt** | same rules, typed |
| Obligation keyed off `"96-Other Countries"` | **Reject** | area code with an outside-jurisdiction flag |
| Reporting time limit | **Adopt as a rule** | jurisdiction rule revision, not a settings integer |
| Error taxonomy: server / not-applicable / validation | **Adopt** | same taxonomy as typed attempt outcomes |
| Status persisted with an explicit commit through rollback | **Adopt the intent** | attempt row committed before the call |
| `DUPIRN` reconciliation | **Adopt and strengthen** | verify signature, compare full identifying content |
| `jwt.decode(verify_signature=False)` | **Reject** | verified signature required for `authority_confirmed` |
| Retry once after GSTIN sync | **Adopt** | typed recoverable outcome with one bounded retry |
| Logs keyed by the authority identifier | **Adopt** | `UNIQUE (company_id, artefact_type, authority_identifier)` |
| Asynchronous log write | **Reject** | artefact facts commit with their effect |
| Blanking the IRN on cancellation | **Reject** | append-only identifier; state carries eligibility |
| Local clock as the cancellation timestamp | **Change** | `timestamp_source = local_fallback`, explicitly marked |
| 24-hour cancellation window | **Adopt as a rule** | `statutory_cancellation_window` on the jurisdiction revision |
| Reading the window basis from an onload cache | **Reject** | evaluated against the stored authority `issued_at` |
| Cancelling the e-way bill before the IRN | **Adopt** | dependency-ordered reversal |
| Manual generate / cancel marking | **Adopt as a distinct class** | `evidence_class = manually_asserted`, never authority-confirmed |
| Vehicle / transporter updates | **Adopt** | append-only amendment events |
| Capturing old values before update | **Adopt** | the amendment event carries before and after |
| Writing local fields before the API accepts | **Reject** | update after acceptance only |
| Validity extension | **Adopt** | amendment event with its own idempotency key |
| Bounded-window scheduled extension | **Reject** | `due_at <= now AND not satisfied`, self-healing |
| Clearing `extension_scheduled` before the attempt | **Reject** | lease released after the attempt |
| `Auto-Retry` status as the queue | **Reject** | `statutory_submission_work` with lease and backoff |
| Retry gate cleared before the work | **Reject** | durable work rows; no global pending flag |
| `update_modified=False` on the flag | **Reject** | all state changes are visible and audited |
| Global degraded mode | **Change** | recorded, time-bounded condition |
| PDF attach / delete / republish | **Change** | derived artefact regenerated from the stored payload |
| `find_matching_e_waybill`, valid/invalid log split | **Adopt as reconciliation** | a reconciler over attempt records, not a repair for lost state |

Invariants introduced here are **G17–G23**. Doc 48 continues at **G24** with returns and reconciliation.

---

Cross-references: [doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) (settings, credentials,
GSTIN status), [doc 46](46-gst-place-of-supply-and-component-determination.md) (determination the payload is
built from), [doc 06](06-lifecycle-status-and-returns.md) (returns and credit notes — the remedy once the
cancellation window closes), [doc 09](09-lifecycle-reversals-deletions.md) (cancel ordering),
[doc 22](22-background-jobs-scheduling-and-locking.md) (job identity, leases and the locking mechanisms this
subsystem lacks), [doc 41 §3.4](41-asset-identity-acquisition-and-finance-books.md) (the same bounded-window
scheduler defect in asset recognition),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (outbox and idempotency contract), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 48 — GSTR-1/3B, purchase reconciliation,
Bill of Entry and amendment semantics.
