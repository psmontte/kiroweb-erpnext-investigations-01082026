# S12 — GST: Determination → E-Invoice → E-Way Bill → GSTR-1

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`,
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, `17.0.0-dev`).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`, or prefixed `frappe/` /
> `india_compliance/`.
>
> Continues **[S01](S01-order-to-cash.md)** — the same order-to-cash flow, but the seller is registered under
> Indian GST, so determination, two government endpoints and a monthly return all attach to it. Subsystem
> detail is in **[docs 45–49](../logic/45-gst-registration-settings-hsn-and-tax-structure.md)**.
>
> This is an investigation document. It shows what is written, in what order, and where the design does and
> does not hold.

---

## 1. The worked example

AlphaCo (Maharashtra, GSTIN `27AACCA1234A1Z5`) sells to two customers in one week, generates e-invoices and
an e-way bill, then files GSTR-1 for the period.

| Fact | Value |
|---|---|
| Company GSTIN | `27AACCA1234A1Z5` — state `27` (Maharashtra) |
| **Invoice A** | Customer in Maharashtra, GSTIN `27AAFCB5678B1Z3` — **intra-state** |
| Invoice A items | 10 × `WIDGET-1` @ 5,000.00, HSN `84819010`, GST 18% |
| **Invoice B** | Customer in Karnataka, GSTIN `29AAGCC9012C1Z1` — **inter-state** |
| Invoice B items | 4 × `WIDGET-1` @ 5,000.00, HSN `84819010`, GST 18% |
| E-way bill | Invoice B only (goods crossing a state boundary, value above threshold) |
| Return | GSTR-1 for the month, B2B section |

Assumptions that make every number deterministic: single currency (INR), no discounts, no cess, no reverse
charge, no TDS, `enable_e_invoice` and `enable_e_waybill` both on, API not in sandbox mode,
`validate_gstin_status` on, and no prior filing for the period. Accounts: Debtors, Sales, Output CGST,
Output SGST, Output IGST.

---

## 2. Stage 1 — determination on Invoice A (intra-state)

### 2.1 Place of supply and supply type

`before_validate_transaction` sets GST tax types and place of supply, then recomputes taxes
(`india_compliance/gst_india/overrides/transaction.py:1574-1614`).

```text
place_of_supply  = "27-Maharashtra"            (from the customer's billing GSTIN)
source_state     = company_gstin[:2] = "27"    (sales doctype rule)
is_inter_state   = place_of_supply[:2] != source_state
                 = "27" != "27" → False        → INTRA-STATE
```

(`india_compliance/gst_india/overrides/transaction.py:545-576`,
`india_compliance/gst_india/overrides/transaction.py:577-592`,
`india_compliance/gst_india/overrides/transaction.py:593-625`).

Note what just happened: the tax treatment was decided by comparing **the first two characters of a
human-readable label** with the first two characters of a registration number. Both happen to be `"27"`.
Doc 46 §2.1 is this line.

### 2.2 Applicable components

`get_applicable_gst_accounts` filters by supply type
(`india_compliance/gst_india/overrides/transaction.py:209-245`):

```text
account_types = ["Output"]
intra-state → IGST excluded ; CGST and SGST applicable
```

The `Item Tax Template` for HSN `84819010` carries `gst_rate = 18` with two rows at 9% each, and
`validate_tax_rates` has already enforced the doubling rule at template-save time
(`india_compliance/gst_india/overrides/item_tax_template.py:27-67`):

```text
intra-state account → require gst_rate == tax_rate × 2 → 18 == 9 × 2 ✔
```

### 2.3 Amounts

```text
taxable value = 10 × 5,000.00 = 50,000.00
CGST @ 9%     =  4,500.00
SGST @ 9%     =  4,500.00
invoice total = 59,000.00
```

`GSTAccounts.validate` then runs its five checks, including `validate_for_same_party_gstin` — which passes
here because `27AACCA1234A1Z5 != 27AAFCB5678B1Z3`
(`india_compliance/gst_india/overrides/transaction.py:283-300`).

### 2.4 GL on submit

| Account | Debit | Credit |
|---|---:|---:|
| Debtors | **59,000.00** | |
| Sales | | 50,000.00 |
| Output CGST | | **4,500.00** |
| Output SGST | | **4,500.00** |
| **Total** | **59,000.00** | **59,000.00** |

| Representation after Invoice A | Value |
|---|---|
| `tabSales Invoice` + 1 item + 2 tax rows | 1 + 1 + 2 |
| `tabGL Entry` | **4** |
| `tabGSTIN` rows consulted | 2 (company, customer) |
| determination facts recorded | **0** — the values live in the document's own fields |

That last row is doc 46 §8: there is no record of which rate schedule, which engine version, or which rule
resolved the place of supply.

---

## 3. Stage 2 — determination on Invoice B (inter-state)

Same item, same rate, different state:

```text
place_of_supply = "29-Karnataka"     source_state = "27"
is_inter_state  = "29" != "27" → True
account filter  → CGST and SGST excluded ; IGST applicable
taxable value   = 4 × 5,000.00 = 20,000.00
IGST @ 18%      = 3,600.00
invoice total   = 23,600.00
```

| Account | Debit | Credit |
|---|---:|---:|
| Debtors | **23,600.00** | |
| Sales | | 20,000.00 |
| Output IGST | | **3,600.00** |
| **Total** | **23,600.00** | **23,600.00** |

The same 18% resolves to `9 + 9` in one invoice and `18` in the other, from one template — the duality doc 45
§5.1 identified, working correctly.

**What would have happened with a missing place of supply:** `is_inter_state_supply` returns `False`
(`india_compliance/gst_india/overrides/transaction.py:577-592`), so Invoice B would have been taxed
`CGST 1,800.00 + SGST 1,800.00` — the right total, wrong components, wrong state's revenue, and wrong GSTR-1
section. No error raised.

---

## 4. Stage 3 — e-invoice for Invoice A

### 4.1 Applicability

`validate_e_invoice_applicability` runs its ladder
(`india_compliance/gst_india/utils/e_invoice.py:531-578`):

```text
doc.irn empty                                        → continue
company_gstin != billing_address_gstin               → continue
billing_address_gstin present (B2B)                  → continue
enable_e_invoice on                                  → continue
items include a TAXABLE_GST_TREATMENTS item          → continue
applicability_date present and <= posting_date       → APPLICABLE
```

### 4.2 Generation

`generate_e_invoice` builds the payload, calls `generate_irn`, and on success logs and processes it
(`india_compliance/gst_india/utils/e_invoice.py:120-268`). Suppose the portal returns:

```text
Irn   = "a1b2c3…"   (64 chars)
AckNo = "112410000123456"
AckDt = "2026-08-03 11:42:00"
SignedInvoice = <JWT>
```

`log_and_process_e_invoice_generation` then updates the document and **enqueues** the log write
(`india_compliance/gst_india/utils/e_invoice.py:367-415`,
`india_compliance/gst_india/utils/e_invoice.py:507-517`).

So immediately after generation:

| Where | State |
|---|---|
| `Sales Invoice.irn` | set |
| `Sales Invoice.einvoice_status` | `Generated` |
| `e-Invoice Log` | **not yet written** — queued on the short queue |
| `acknowledged_on` | only in the log, once that job runs |

If the queue is lost here, the invoice claims an IRN and the log has no record of when it was acknowledged —
which §5 shows is exactly what the cancellation window depends on.

### 4.3 The duplicate case

Suppose instead the portal replies `InfCd == "DUPIRN"` because a retry already succeeded.
`handle_duplicate_irn_error` fetches the existing IRN and compares
(`india_compliance/gst_india/utils/e_invoice.py:269-332`,
`india_compliance/gst_india/utils/e_invoice.py:333-366`):

```text
decode SignedInvoice                      ← jwt.decode(..., verify_signature=False)
compare BuyerDtls.Gstin  : 27AAFCB5678B1Z3 == 27AAFCB5678B1Z3   ✔
compare ValDtls.TotInvVal:      59,000.00 ==      59,000.00     ✔
→ attach the existing IRN
```

Correct outcome, reached by reading an artefact whose signature was deliberately not verified, comparing two
fields. Had the buyer or total differed, it refuses and tells the user to raise a new invoice — which is the
right behaviour, and the reason doc 49 §5 treats this as the tranche's signature finding.

---

## 5. Stage 4 — cancelling within the window

AlphaCo spots an error on Invoice A the same afternoon and cancels.

`validate_if_e_invoice_can_be_cancelled` reads `acknowledged_on` from the **onload cache** and applies a
literal 24 hours (`india_compliance/gst_india/utils/e_invoice.py:580-596`):

```text
acknowledged_on = 2026-08-03 11:42:00
+ 1 day         = 2026-08-04 11:42:00   > now → allowed
```

`_cancel_e_invoice` cancels the e-way bill first if present, sends the cancellation, logs it, then cancels the
document (`india_compliance/gst_india/utils/e_invoice.py:416-443`). Then:

```python
doc.db_set({"einvoice_status": "Cancelled", "irn": ""})
```

(`india_compliance/gst_india/utils/e_invoice.py:444-470`).

**The IRN is erased from the invoice.** The identifier of a document reported to the government now exists
only in the `e-Invoice Log` row — written earlier by a background job. And the reason it must be erased is
that `validate_e_invoice_applicability` treats a non-empty `irn` as "already generated"
(`india_compliance/gst_india/utils/e_invoice.py:531-578`), so the field is doing double duty as a state flag.

Had the portal replied error `9999` ("already cancelled"), `cancelled_on` would have been set to
`get_datetime()` — **our clock**, presented as the cancellation time
(`india_compliance/gst_india/utils/e_invoice.py:444-470`).

**After the window closes** there is no cancellation. The only remedy is a credit note, which is an ordinary
return document (doc 06 §6.6) reported in its own GSTR-1 section.

---

## 6. Stage 5 — e-way bill for Invoice B

Goods move to Karnataka. `_generate_e_waybill` builds and sends the payload
(`india_compliance/gst_india/utils/e_waybill.py:159-334`), and
`log_and_process_e_waybill_generation` records it
(`india_compliance/gst_india/utils/e_waybill.py:335-378`).

Say the portal returns e-way bill `181012345678`, `valid_upto = 2026-08-05 23:59`.

The vehicle then breaks down and transit will overrun. Two paths exist:

**Immediate extension** — `extend_validity` writes vehicle and transport details onto the document, calls the
API, sets `distance`, and updates the log
(`india_compliance/gst_india/utils/e_waybill.py:624-660`). Note the ordering: the local fields are written
**before** the call, so a rejected extension leaves the document asserting details the portal never accepted.

**Scheduled extension** — `schedule_ewaybill_for_extension` stores the intent on the log
(`india_compliance/gst_india/utils/e_waybill.py:723-764`), and a job picks it up
(`india_compliance/gst_india/utils/e_waybill.py:661-684`):

```text
WHERE is_cancelled = 0
  AND extension_scheduled = 1
  AND valid_upto BETWEEN (now − 1 day) AND now
```

Then `extend_scheduled_e_waybills` clears `extension_scheduled = 0` **before** attempting
(`india_compliance/gst_india/utils/e_waybill.py:685-712`).

Two failure modes follow directly, and both are silent:

| If | Then |
|---|---|
| the scheduler does not run for a day | `valid_upto` falls outside the one-day window and the e-way bill is **never** extended |
| the extension call fails | `extension_scheduled` is already consumed, so it is neither scheduled nor extended |

This is the same bounded-window defect as asset recognition's `= nowdate()` filter (doc 41 §3.4), with goods
in transit as the consequence.

---

## 7. Stage 6 — GSTR-1 for the period

### 7.1 Building the working set

`GSTReturnLog` composes generation, filing and persistence
(`india_compliance/gst_india/doctype/gst_return_log/gst_return_log.py:28-40`). Invoices A (cancelled) and B
are classified into the prescribed subcategories
(`india_compliance/gst_india/utils/gstr_1/__init__.py:29-162`); B lands in **B2B Regular**, and A's credit
note — if one was raised — lands in the credit/debit note section.

If `is_latest_data` is set, previously computed JSON is returned instead of recomputing
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-290`). So a statutory working set
can be served from a memoised blob whose inputs have since changed.

### 7.2 Reconciling against the portal

The portal's version of our filed data is downloaded and compared
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:263-351`). Suppose the portal shows
Invoice B with a taxable value of 20,000.00 but **IGST of 3,599.00** — a one-rupee difference from a rounding
mismatch upstream in their system.

`get_reconciled_row` computes the difference field by field
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:363-440`):

```text
match_status = "Matched"
taxable_value : flt(20,000.00 − 20,000.00, 2) = 0.00   → no difference
igst          : flt( 3,600.00 −  3,599.00, 2) = 1.00   → DIFFERENT
→ match_status = "Mismatch", differences = "Igst"
row keeps: books = {…}, gov = {…}, igst = 1.00
```

The finding **is** the difference, with both sides retained. That is the right shape, and doc 48 §1.3 adopts
it directly.

Then the books-side row is annotated in place:

```text
books row upload_status = "Mismatch"
```

and, for anything present at the portal but absent from books, a synthetic row is inserted into the
books structure with `upload_status = "Missing in Books"`
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:263-351`) — later deleted by
`sanitize_books_data` on the next pass
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:352-362`). Reconciliation output is
written into one of its own inputs, then cleaned up before the next run.

Note also that `TAX_RATE` and `DOC_VALUE` are excluded from comparison
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:252-262`), so `Matched` means "amounts
agree", not "everything agrees".

### 7.3 Filing, and what it locks

`filing_status` advances to `Filed`
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:998-1010`). Two consequences fire:

1. reconciliation stops updating books-side match status
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-290`); and
2. **no document in that period can be submitted or cancelled**
   (`india_compliance/gst_india/overrides/transaction.py:626-635`, via
   `india_compliance/gst_india/doctype/gst_settings/gst_settings.py:567-601`).

That second point is a genuine statutory period close — implemented as a per-document lookup against a Single,
rather than as a period record.

---

## 8. Complete write trace

| Stage | Primary writes | GL | External calls | Projections mutated |
|---|---|---:|---:|---|
| Invoice A determination | SI 1 + item 1 + 2 tax rows | **4** | 0 | `place_of_supply`, `gst_tax_type` per row, item GST details |
| Invoice A e-invoice | `e-Invoice Log` 1 (**enqueued**) | 0 | 1 | `irn`, `einvoice_status`, onload cache |
| Invoice A cancellation | log update (**enqueued**) | 4 reversing | 1 | `einvoice_status`, **`irn` blanked** |
| Invoice B determination | SI 1 + item 1 + 1 tax row | **3** | 0 | as above |
| Invoice B e-invoice | `e-Invoice Log` 1 | 0 | 1 | `irn`, `einvoice_status` |
| Invoice B e-way bill | `e-Waybill Log` 1 | 0 | 1 | `ewaybill`, `e_waybill_status` |
| Extension (scheduled) | log update | 0 | 1 | `vehicle_no`, `lr_no`, `distance`, `extension_scheduled` cleared |
| GSTR-1 build | `GST Return Log` JSON blobs | 0 | 1 (download) | `books`, `gov`, `reconcile`, `is_latest_data` |
| GSTR-1 file | filing status | 0 | 1 | `filing_status` → `Filed` |

**Accounting proof** (Invoice B, the surviving invoice):

```text
Dr Debtors 23,600.00 / Cr Sales 20,000.00 + Cr Output IGST 3,600.00
```

Balanced. The GST components tie exactly to the declared taxable value at 18%, and the return reports
20,000.00 / 3,600.00 for that invoice — with the portal disagreeing by 1.00, held as a finding.

### 8.1 Evidence versus projection

| Representation | Classification |
|---|---|
| posted invoice + tax rows | the closest thing to a determination fact |
| `place_of_supply` | **composite display string**, sliced for the statutory code |
| rate schedule / engine version used | **not recorded anywhere** |
| the portal's signed invoice (JWT) | the legal artefact — decoded unverified, not retained as evidence |
| `Sales Invoice.irn` | mutable, **blanked on cancellation**, doubles as a state flag |
| `e-Invoice Log` | keyed by IRN, written **asynchronously** |
| `acknowledged_on` | read from an onload cache; governs a statutory deadline |
| `e-Waybill Log.valid_upto`, `extension_scheduled` | drives a bounded-window scheduler; flag consumed pre-attempt |
| `GST Return Log` JSON blobs | memoised working set gated by `is_latest_data` |
| `upload_status` on books rows | reconciliation output written into its own input |
| `filing_status` | period-close authority, written by `db_set` in seven places |
| request / response payloads | **not persisted at all** |

The audit path from "why does this invoice carry this tax" to evidence stops at the invoice's own mutable
fields. The path from "what did the government tell us" stops at a digested log row written by a job that may
not have run.

---

## 9. Cancellation and reversal order

1. **Return filing.** Once `Filed`, nothing in the period may be posted or cancelled
   (`india_compliance/gst_india/overrides/transaction.py:626-635`). Corrections move to the next period as
   amendments.
2. **E-way bill** before the IRN — `_cancel_e_invoice` does this explicitly
   (`india_compliance/gst_india/utils/e_invoice.py:416-443`).
3. **E-invoice** within 24 hours of acknowledgement
   (`india_compliance/gst_india/utils/e_invoice.py:580-596`); after that, a credit note.
4. **Invoice** — ordinary cancellation, reversing GL.

The ordering is correct. What is missing is that steps 2–3 leave no durable record of the request that
performed them, and step 3 erases the identifier it acted on.

---

## 10. The same flow in our design

### 10.1 Determination becomes a fact

```text
tax_registration_snapshot(source=SI-B, party_role=customer,
    registration_no='29AAGCC9012C1Z1', category='registered_regular',
    tax_area_id→'29', status='active', retrieved_at=…)     ← captured BEFORE the write, blocking

tax_determination(source=SI-B, jurisdiction_revision=IN-r7, engine_version='1.4.0',
    supply_type='inter', liability_direction='forward',
    place_of_supply_area_id→'29', place_of_supply_basis='party_registration',
    source_area_id→'27',        source_basis='company_registration',
    money_precision=2)
tax_determination_line(source_line=SI-B-1, classification_revision=HSN-84819010-r3,
    tax_rate_revision=IN-84819010-inter-r2, taxable_amount=20,000.00)
tax_determination_component(component=igst, role=output, rate=18.000000, amount=3,600.00)
```

Now the questions upstream cannot answer are queries: which rate schedule (`tax_rate_revision`), which rule
resolved the place of supply (`place_of_supply_basis`), what the customer's registration status was at the
time (`tax_registration_snapshot`), and which engine computed it (`engine_version`).

A missing place of supply cannot silently mean intra-state, because `place_of_supply_area_id` is
`NOT NULL` and the basis must be recorded (`FINAL-SCHEMA` §25).

### 10.2 The e-invoice becomes an attempt plus an artefact

```text
statutory_artefact(type=e_invoice, source=SI-B, generation_no=1,
    obligation_basis='IN-r7:b2b_taxable_above_threshold', state=required)
statutory_submission_work(artefact=…, state=queued)
    ↓ claim FOR UPDATE SKIP LOCKED, set lease
statutory_submission_attempt(attempt_no=1, endpoint='…/generate', request_hash=…,
    idempotency_key='einv:SI-B:1')                          ← inserted BEFORE the call
    ↓ call
statutory_artefact_event(type=issued, authority_timestamp='2026-08-03 11:42:00',
    timestamp_source='authority')
statutory_artefact ← authority_identifier='a1b2c3…', issued_at=…, signed_payload=<JWT>,
    signature_verified=TRUE, evidence_class='authority_confirmed', state=issued
```

Because `CHECK (evidence_class <> 'authority_confirmed' OR signature_verified IS TRUE)`, the
`verify_signature=False` shortcut is unavailable: an unverified artefact can only be recorded as
`manually_asserted`, and any rule requiring authority confirmation refuses it.

A lost response records `outcome = 'timeout_unknown'`, and the next action is **reconcile** — fetch by our
document reference, compare full identifying content — never a blind resubmission that could mint a second
IRN.

### 10.3 Cancellation keeps the identifier

```text
statutory_cancellation_window(jurisdiction_revision=IN-r7, artefact_type=e_invoice,
    window_hours=24, basis='authority_issue_time')
```

evaluated against the stored `issued_at`, not an onload cache and not a literal. Cancellation appends:

```text
statutory_artefact_event(type=cancelled, authority_timestamp=…, timestamp_source='authority')
statutory_artefact.state = cancelled          -- authority_identifier UNTOUCHED
```

Regeneration inserts `generation_no = 2`. Nothing is erased, so
`UNIQUE (company_id, artefact_type, authority_identifier)` is a real constraint and history survives. Where
the authority's timestamp is unavailable, `timestamp_source = 'local_fallback'` marks it as ours.

### 10.4 The e-way bill extension self-heals

Selection becomes `due_at <= now AND not satisfied` rather than a one-day band, and the work lease is
released **after** the attempt — so a scheduler outage delays an extension instead of losing it, and a failed
call leaves the item retryable (`FINAL-SCHEMA` §26).

### 10.5 The return period becomes immutable facts

```text
return_period(registration=27AACCA1234A1Z5, return_type='gstr1',
    period_start=2026-08-01, period_end=2026-08-31, state=working)
return_working_set(version=1, source_watermark=…, content_hash=…,
    return_format_revision_id=gstr1-r12, output_precision=2)
authority_dataset(dataset_type='gstr1_filed', payload_hash=…, attempt=…)
reconciliation_run(working_set=1, dataset=…, match_policy_revision=IN-gstr1-r3,
    comparison_precision=2)
reconciliation_finding(subcategory='b2b_regular', natural_key='SI-B',
    finding='mismatch', differing_fields={'igst'},
    signed_difference={'igst': 1.00},
    books_payload={…}, authority_payload={…})
```

The finding retains upstream's best idea and adds what it lacked: the working set is **versioned and hashed**
so `is_latest_data` is unnecessary, the comparison precision is a **declared column** rather than a literal
`2`, the match policy is a **named revision**, and nothing is written back into the books data.

Accepting the mismatch is then a fact, not an edit:

```text
reconciliation_decision(finding=…, decision='accept_match', actor=…,
    reason_code='authority_rounding', match_policy_revision=IN-gstr1-r3)
```

Filing inserts `return_filing` with its payload hash and working-set version, and sets
`return_period.state = filed` — which the **same period-control trigger family as accounting periods** then
enforces, rather than a per-document lookup against a Single.

---

## 11. Side by side

| Question | ERPNext + India Compliance | Ours |
|---|---|---|
| Where is the supply made | `"NN-State Name"`, sliced `[:2]` | `tax_area` FK + recorded basis |
| Missing place of supply | silently intra-state | refusal |
| Which rate schedule applied | not recorded | `tax_rate_revision` on the determination line |
| Counterparty status when relied upon | cached row, may be validated async | immutable snapshot, captured synchronously |
| Component arithmetic | validated with a message | exact-sum deferred constraint |
| Reverse-charge cancellation | `flt(…, 2) == 0` | exact at declared precision |
| What we sent to the portal | not persisted | `statutory_submission_attempt`, pre-call |
| Lost response | no representation | `timeout_unknown` → reconcile |
| Authority signature | decoded with verification off | verified; gates `authority_confirmed` |
| IRN after cancellation | **blanked** | retained; `generation_no` increments |
| Cancellation window | literal 24h from an onload cache | jurisdiction rule against stored `issued_at` |
| Retry queue | a status string + a Single flag | leased durable work with backoff |
| Scheduled extension | one-day window, flag consumed first | `due_at <= now`, lease released after |
| Return working set | memoised blob + `is_latest_data` | versioned, watermarked, hashed |
| Reconciliation output | written into its own input | append-only findings |
| Comparison precision | hard-coded `2`, three places | declared per run and per format |
| Match rules | Python tuple | versioned `match_policy_*` rows |
| Match decisions | mutable link edits | append-only decisions with rule revision |
| Statutory period close | Single consulted per document | `return_period` + shared period guard |

---

## 12. Findings and invariants exercised

1. **Tax treatment is decided by string slicing** — place of supply's first two characters against a GSTIN's
   first two characters — and a missing place of supply silently selects CGST+SGST.
2. **No determination provenance exists.** Rate schedule, engine version and place-of-supply basis are not
   recorded, so an old invoice's tax can only be explained by re-running today's configuration.
3. **Registration validation can arrive after the write**, because the refresh path enqueues the fetch with
   validation as a non-throwing callback.
4. **The authority's signature is discarded** and the duplicate check compares two fields.
5. **The IRN is erased on cancellation**, because the identifier field doubles as an "already generated" flag.
6. **The legal log is written by a background job**, outside the transaction that recorded its effect — and
   the cancellation window is then read from an onload cache.
7. **Our clock can be recorded as the authority's cancellation time.**
8. **Scheduled e-way bill extension uses a bounded one-day window and consumes its flag before attempting**,
   so both a missed run and a failed call lose the extension silently.
9. **The retry queue is a status string plus a Single flag cleared before the work it guards.**
10. **The return working set is a memoised blob**, and reconciliation writes `upload_status` and synthetic
    rows into the data it is comparing.
11. **Three separate hard-coded 2-decimal precisions** govern a statutory balance rule, a reconciliation
    comparison and the values declared to the government.
12. **Match decisions leave no history** — no actor, no rule version, no evidence — despite the matching
    *policy* itself being the best-designed thing in the tranche.

This scenario exercises the whole Tranche F register: **G1–G8** (jurisdiction as data, statutory fields as
schema, registration as captured evidence, typed components with constrained arithmetic, effective-dated
classification and rates, evidence before projection, relational integrity, serializable decisions),
**G9–G16** (recorded determination, resolved place of supply, derived applicability, typed liability with
exact balance, blocked credit as allocation, statutory period control, relational and serializable
determination), **G17–G23** (dated obligation, reconciled artefacts, append-only identifiers, in-transit
amendment events with self-healing work, leased submission, relational and serializable submission), and
**G24–G29** (immutable working sets, versioned filings, declared match policy with decision facts, typed
import assessment, relational and serializable return operations).

It also reuses **F1** (balanced vouchers) from S04 and **U7** (no stored value is ever a translation) from
doc 30 — the latter tested harder here than anywhere else in the investigation, because upstream stores a
statutory code inside a display label.

---

Cross-references: **[S01](S01-order-to-cash.md)** (the underlying order-to-cash flow),
**[S03](S03-procure-to-pay.md)** (the inward side, where reconciliation and Bill of Entry apply),
**[S05](S05-period-close-and-opening-balances.md)** (period control this parallels);
**[doc 45](../logic/45-gst-registration-settings-hsn-and-tax-structure.md)** (registration, settings, HSN,
components), **[doc 46](../logic/46-gst-place-of-supply-and-component-determination.md)** (determination),
**[doc 47](../logic/47-e-invoice-and-e-waybill-external-state-machines.md)** (external artefacts),
**[doc 48](../logic/48-gst-returns-reconciliation-and-imports.md)** (returns and reconciliation),
**[doc 49](../logic/49-tranche-f-closure-and-our-localisation-spec.md)** (closure and the G register),
**[doc 05](../logic/05-taxes-totals-and-pricing.md)** (tax calculation),
**[doc 28](../logic/28-tax-determination.md)** (the core tax engine GST rides on), and
`docs/design/FINAL-SCHEMA.md` §24–§28 (target localisation tables).
