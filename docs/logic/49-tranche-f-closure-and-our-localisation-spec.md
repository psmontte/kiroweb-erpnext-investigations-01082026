# 49 — Tranche F Closure and Our Localisation Specification

> **Tranche F deliverable.** This closes the localisation investigation and consolidates docs
> [45](45-gst-registration-settings-hsn-and-tax-structure.md)–[48](48-gst-returns-reconciliation-and-imports.md)
> into the backend/database contract we will build.
>
> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, `17.0.0-dev`).
> ERPNext citations are relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are prefixed
> `frappe/`; India Compliance citations are prefixed `india_compliance/`.

This is a specification, not an implementation report. **Application implementation has not started.** The
localisation design extends [`FINAL-SCHEMA.md` §24–§28](../design/FINAL-SCHEMA.md); it does not supersede the
accounting, stock, trade, production, quality or asset guarantees already fixed there and in
[doc 25](25-our-platform-spec.md), [doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) and
[doc 44](44-tranche-c-closure-and-our-asset-spec.md).

---

## 1. What this tranche measured

Tranche F is the first tranche whose subject is **not in ERPNext**. India GST was removed from core in v14
(`patches/v14_0/remove_india_localisation.py:5-21`), and the removal patch deletes the DocTypes, print
formats and reports that used to implement it
(`patches/v14_0/remove_india_localisation.py:23-64`). A whole-tree search for GST identifiers in the pinned
ERPNext returns four files: three patches and one demo fixture.

So the coverage question is different here. There is no ERPNext module to close; there is a **third
repository** to read.

| | |
|---|---|
| App | `resilient-tech/india-compliance`, pinned `205c3de` |
| Version alignment | `17.0.0-dev`, requires `frappe >=17.0.0-dev` — matches our pinned frappe/erpnext exactly |
| Python | ~49,000 lines across ~313 files, excluding `test_*` and `tests/` |
| DocTypes | **26** |
| Documents | 45 (identity, settings, classification, tax structure), 46 (determination), 47 (external artefacts), 48 (returns, reconciliation, imports) |

The ERPNext-side coverage matrix is unchanged and remains closed: **203 parents, 178 cited, zero uncited
submittable, zero uncited configuration, 25 recorded exclusions**
([`COVERAGE.md`](../COVERAGE.md)). Tranche F adds no ERPNext parents, because it reads a different app.

### 1.1 Why the mechanism had to be rejected before the content could be designed

Two upstream extension mechanisms shape everything in docs 45–48, and both are unacceptable for us:

- **`@erpnext.allow_regional`** — 20 call sites in the pinned tree, replacing a function's implementation
  based on company country at call time. Doc 42 §4.3 found it wrapping
  `get_wdv_or_dd_depr_amount`: a jurisdiction plugin can silently replace a **depreciation calculation**.
- **Custom fields toggled by settings** — `GST Settings.update_custom_fields` creates, hides or deletes whole
  field groups when a checkbox changes
  (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:210-218`,
  `india_compliance/utils/custom_fields.py:7-37`). Fields carrying **statutory** meaning are settings-derived
  runtime metadata.

Everything in §4 follows from replacing those two with one idea: **jurisdiction is data**.

---

## 2. Governing localisation model

The four-layer rule from [doc 25 §2](25-our-platform-spec.md#2-the-layering-rule) applies unchanged.
Localisation adds five consequences.

1. **A jurisdiction is a row with approved, effective-dated rule revisions.** Adding a second regime adds
   data, never a code path selected at runtime.
2. **Statutory identity is captured, not looked up.** A registration number, its category and its status at
   the moment it was relied upon are immutable snapshots on the posted document.
3. **Determination is a recorded computation.** Place of supply, supply type, rate revision, component
   amounts and their provenance are facts, not fields recomputed from current configuration.
4. **The authority is a separate system of record.** Every request is an attempt record committed before the
   call; a lost response means *reconcile*, never *resubmit*; an authority identifier is append-only.
5. **A return period is an immutable working set plus append-only findings.** Reconciliation never writes
   into the data it compares, and a filed period closes to posting through the same mechanism as an
   accounting period.

All localisation tables carry `company_id NOT NULL`, company-scoped keys, `ENABLE ROW LEVEL SECURITY` and
`FORCE ROW LEVEL SECURITY` with policies bound to authenticated tenant context. Money is `numeric(19,4)`;
rates and percentages `numeric(9,6)`; quantities `numeric(21,9)`. Persisted codes are stable lower-case enum
codes, never translated display text — an invariant this tranche tests harder than any other, because
upstream stores place of supply as `"NN-State Name"` and slices it for the statutory code
(`india_compliance/gst_india/overrides/transaction.py:545-592`).

---

## 3. G1–G29: exact register and enforcement owner

Names are preserved exactly from docs 45–48.

| ID | Exact invariant name | Primary enforcement |
|---|---|---|
| G1 | jurisdiction is data, not code | L1 `tax_jurisdiction_revision` + approved-range exclusion constraint |
| G2 | statutory fields are schema, not settings | L1 versioned columns; no runtime metadata mutation |
| G3 | counterparty registration is evidence, captured at the moment it is relied upon | L1 immutable `tax_registration_snapshot` + L3 blocking synchronous capture |
| G4 | tax components are typed, and their arithmetic is a constraint | L1 `tax_component`/`tax_component_account` uniqueness + L2 exact-sum trigger |
| G5 | classification and rate are effective-dated revisions | L1 revision tables with exclusion constraints |
| G6 | evidence before compliance projection | L2 atomic facts/outbox; projector position after commit |
| G7 | relational jurisdiction integrity | L1 unique/FK/check/exclusion constraints |
| G8 | serializable compliance decisions | L2 deterministic owner locks + L1 idempotency uniqueness |
| G9 | determination is a recorded computation, not a document mutation | L1 append-only `tax_determination` + immutability trigger |
| G10 | place of supply is a resolved code with recorded provenance | L1 area FK + `place_of_supply_basis`; absence is a refusal |
| G11 | component applicability is derived, and unmapped accounts are refusals | L2 applicability trigger over the component set |
| G12 | liability direction is typed, and its balance is exact | L2 deferred exact-cancellation at declared precision |
| G13 | blocked credit is a typed cost allocation | L1 `tax_credit_block` with exactly one destination |
| G14 | statutory period control is a period record | L1 `return_period` exclusion + L2 posting guard |
| G15 | relational determination integrity | L1 unique/FK/check constraints on determination rows |
| G16 | serializable determination | L2 registration/period/document locks + L1 idempotency |
| G17 | a statutory obligation is a derived, dated fact | L1 `statutory_artefact.obligation_basis` from the dated rule |
| G18 | external artefacts are reconciled, not assumed | L1 attempt rows committed pre-call + L2 signature/content match |
| G19 | statutory identifiers are append-only | L1 identifier uniqueness; never blanked; `generation_no` |
| G20 | in-transit amendments are events, and scheduled work is self-healing | L1 append-only amendment events + L3 `due_at <= now` selection |
| G21 | external submission is durable work with a lease | L1 `statutory_submission_work` partial unique + lease columns |
| G22 | relational artefact integrity | L1 unique/FK/check/partial-unique constraints |
| G23 | serializable external submission | L2 `FOR UPDATE SKIP LOCKED` claim + L1 idempotency |
| G24 | a return period is an immutable working set plus append-only reconciliation facts | L1 versioned `return_working_set` + immutable findings |
| G25 | a filed return is an immutable artefact with a declared format version | L1 `return_filing` + `return_format_revision` FK |
| G26 | matching is a declared, versioned policy and every decision is a fact | L1 `match_policy_*` revisions + append-only decisions |
| G27 | statutory import assessment is a first-class document with typed allocations | L1 `customs_assessment` + bounded allocation trigger |
| G28 | relational return integrity | L1 unique/FK/exclusion constraints on periods and filings |
| G29 | serializable return operations | L2 (registration, return type, period) locks + L1 idempotency |

Every invariant gets at least one refusal test at its primary layer, and one concurrency/retry test where
L2/L3 participates. Submission invariants additionally require a **duplicate-response** test and a
**lost-response** test, because those are the two failure modes that cannot be prevented, only reconciled.

---

## 4. What we adopt, and what we refuse

Docs 45–48 each carry a full Adopt/Change/Reject matrix. Consolidated, the tranche's decisions cluster into
five themes.

### 4.1 Adopt wholesale — upstream got these right

| Mechanism | Why |
|---|---|
| **The declarative purchase-match ladder** (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:79-260`) | Named tiers, explicit per-field comparison modes, explicit strictness ordering. The best-designed thing in the tranche; we promote it from a Python tuple to versioned rows. |
| **Reconciliation where the difference is the payload** (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:363-440`) | Signed per-field difference with both sides retained is exactly the right shape for a comparison fact. |
| **`DUPIRN` reconciliation** (`india_compliance/gst_india/utils/e_invoice.py:269-332`) | Refusing to attach a duplicate IRN whose buyer and amount differ is genuine idempotency against an external system of record. |
| **The submission error taxonomy** (`india_compliance/gst_india/utils/e_invoice.py:120-268`) | Server error → retry, validation error → fail, not-applicable → no obligation. Persisting the outcome through a rollback with an explicit commit is right. |
| **Registration status as a write-time gate** (`india_compliance/gst_india/doctype/gstin/gstin.py:166-206`) | Turning a statutory condition into a refusal before posting, rather than a filing-time surprise. |
| **Self-supply produces no tax** (`india_compliance/gst_india/overrides/transaction.py:283-300`) | Real statute enforced structurally. |
| **The intra/inter rate-split validation** (`india_compliance/gst_india/overrides/item_tax_template.py:27-67`) | `headline = component × 2` intra-state, `= component` inter-state — one equality capturing GST's duality. |
| **Reverse-charge cancellation model** (`india_compliance/gst_india/overrides/transaction.py:996-1061`) | Forward tax and booked liability must cancel; the concept is correct. |
| **Cancelling the e-way bill before the IRN** (`india_compliance/gst_india/utils/e_invoice.py:416-443`) | Dependency-ordered reversal. |
| **Bill of Entry as a posting document** (`india_compliance/gst_india/doctype/bill_of_entry/bill_of_entry.py:38-112`) | Customs assessment genuinely is its own accounting event. |
| **GSTR-1-filed backdating restriction** (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:567-601`) | A real statutory period-close mechanism. |

### 4.2 Reject — mechanism

`@allow_regional` function replacement; custom fields toggled by settings; a settings document mutating
`Scheduled Job Type` rows
(`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:132-155`); company fixtures as unversioned
generated master data (`india_compliance/gst_india/overrides/company.py:25-100`); and the global
`ignore_gst_validations` bypass (`india_compliance/gst_india/overrides/transaction.py:1838-1842`).

### 4.3 Reject — display text as data

Place of supply stored as `"NN-State Name"` and sliced for its statutory code
(`india_compliance/gst_india/overrides/transaction.py:545-592`); `"96"` as a magic literal for outside the
jurisdiction (`india_compliance/gst_india/overrides/transaction.py:593-625`); and e-invoice **obligation**
depending on `place_of_supply == "96-Other Countries"`
(`india_compliance/gst_india/utils/e_invoice.py:531-578`). This is invariant U7 from doc 30 §3.2, applied
where the consequence is tax rather than presentation.

### 4.4 Reject — defaults and tolerances that decide money

| Upstream | Ours |
|---|---|
| missing place of supply → **intra-state** (`india_compliance/gst_india/overrides/transaction.py:577-592`) | refusal |
| unregistered purchase falls back to `company_gstin` (`india_compliance/gst_india/overrides/transaction.py:593-625`) | explicit area resolution or refusal |
| reverse-charge balance at hard-coded `flt(…, 2)` (`india_compliance/gst_india/overrides/transaction.py:996-1061`) | exact at the document's declared precision |
| GSTR-1 comparison at hard-coded `flt(…, 2)` (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:363-440`) | `comparison_precision` per run |
| GSTR-3B output at `format_values(precision=2)` (`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:267-283`) | `output_precision` per format revision |
| unmapped account → `gst_tax_type = None`, invisible to validation (`india_compliance/gst_india/overrides/transaction.py:272-282`) | refusal |
| 24-hour cancellation window as a literal, read from an onload cache (`india_compliance/gst_india/utils/e_invoice.py:580-596`) | jurisdiction rule against the stored authority `issued_at` |
| statutory rollout pinned to `2099-12-31` (`india_compliance/gst_india/constants/__init__.py:10-12`) | dated rule revision |

### 4.5 Reject — mutable facts

Blanking the IRN on cancellation because the field doubles as a state flag
(`india_compliance/gst_india/utils/e_invoice.py:444-470`); the log written by a background job outside the
transaction (`india_compliance/gst_india/utils/e_invoice.py:507-530`); `is_latest_data` memoisation of a
statutory working set (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-290`);
reconciliation writing `upload_status` into its own input
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:263-362`); match results as mutable
link edits with no decision history
(`india_compliance/gst_india/doctype/purchase_reconciliation_tool/purchase_reconciliation_tool.py:269-323`);
GST fields mutable after submission (`india_compliance/gst_india/overrides/transaction.py:1861-1966`); and
ineligible ITC patching valuation rates in place
(`india_compliance/gst_india/overrides/ineligible_itc.py:291-312`).

---

## 5. The signature finding

One defect deserves separate statement because it is the only place in the entire investigation where a
**cryptographic guarantee is discarded**.

`verify_e_invoice_details` decodes the government's signed invoice to compare it against ours:

```python
invoice_data = json.loads(jwt.decode(signed_data, options={"verify_signature": False})["data"])
```

(`india_compliance/gst_india/utils/e_invoice.py:333-366`). The signed invoice is the legally meaningful
artefact **precisely because it is signed**. Discarding the signature reduces it to unauthenticated content,
and the comparison that exists to stop us attaching someone else's IRN is then performed on data we cannot
attest to — while comparing only two fields, buyer GSTIN and total value.

Our schema makes this structurally unavailable:

```sql
CHECK (evidence_class <> 'authority_confirmed' OR signature_verified IS TRUE)
```

An artefact whose signature was not verified **cannot** be recorded as authority-confirmed, so any rule
requiring authority confirmation refuses it (`FINAL-SCHEMA` §26).

---

## 6. Concrete records and ordering

[`FINAL-SCHEMA.md` §24–§28](../design/FINAL-SCHEMA.md) holds the complete contract:

| Section | Content |
|---|---|
| §24 | jurisdiction and rule revisions, areas and postal ranges, registrations, **immutable registration snapshots**, classification schemes and revisions, typed components with role-unique accounts, treatments, rate revisions with the exact-sum component trigger |
| §25 | `tax_determination` with place-of-supply area and basis, lines bound to classification and rate revisions, components with applicability/sum/cancellation triggers, `tax_credit_block` with exactly one destination |
| §26 | `statutory_artefact` with append-only identifiers and the signature check, artefact events with timestamp provenance, attempts committed pre-call with `timeout_unknown`, leased durable work, cancellation windows as rules |
| §27 | return periods with exclusion constraints, versioned format revisions and working sets, authority datasets by payload hash, **match policy as versioned rows**, immutable findings, append-only decisions, filings, customs assessment with bounded allocations |
| §28 | the G1–G29 register mapped to structure |

Write ordering for determination, external submission and return periods is fixed in
[`FINAL-SCHEMA.md` §27.1](../design/FINAL-SCHEMA.md). Two orderings carry the most weight:

- **Registration snapshot capture is step 3 of the posting funnel, and it blocks.** That single placement is
  what makes doc 45 §3.3's asynchronous, log-only GSTIN validation impossible.
- **The attempt row is inserted before the call.** That is what makes "what did we send and what came back"
  always answerable — the question upstream cannot answer, because only digested outcomes are persisted and
  only sometimes.

---

## 7. Build sequence and boundary

No application implementation has started. Localisation depends on the foundation and accounting/stock core
from [doc 40 §10](40-tranche-b-coverage-closure-and-our-production-spec.md#10-build-sequence-and-boundary)
steps 1–2, and on nothing in production or assets — but assets and stock both *consume* it (§8).

1. **Jurisdiction foundation:** jurisdictions and rule revisions with approved-range exclusions, areas and
   postal ranges, classification schemes, treatments, components and role-unique component accounts.
2. **Registration:** registrations with per-category format and check-digit validation, status fetch attempts,
   and **immutable snapshots** wired into the posting funnel as a blocking step.
3. **Rates:** classification and rate revisions, `tax_rate_component` with the exact-sum trigger, item
   classification references.
4. **Determination:** the pure determination function, place-of-supply resolution with recorded basis,
   applicability, per-line and per-component sum triggers, forward/reverse exact cancellation.
5. **Blocked credit:** `tax_credit_block` wired to `stock_move` value components and `asset_cost_event` rows.
6. **Artefacts:** obligation derivation, leased submission work, attempts committed pre-call, signature
   verification, reconciliation on duplicate, append-only identifiers, cancellation windows.
7. **In-transit amendments:** vehicle, transporter and validity events with self-healing scheduled selection.
8. **Return periods:** versioned working sets, format revisions, authority datasets, period control wired
   into the accounting period guard.
9. **Reconciliation:** match policy revisions, findings, append-only decisions, projected linkage.
10. **Imports:** customs assessment with bounded allocations into creditable components, inventory value and
    asset cost.
11. **Acceptance:** reproduce **S12** end to end, then run duplicate-response, lost-response, concurrent
    submission, period-close race, backdating-refusal, RLS and projection-rebuild tests for every G invariant.

### 7.1 Where localisation touches what we already built

This tranche is the most cross-cutting of all, and the seams must be built deliberately:

| Seam | Consequence |
|---|---|
| `doc_tax` / `doc_tax_line_alloc` (§5) | determination components are the source of tax lines, not a parallel structure |
| `voucher` / `gl_entry` (§3) | component amounts and credit blocks post through the existing boundary |
| `stock_move` value components (§4, §14) | blocked credit and customs duty enter inventory value here |
| `asset_cost_event` (§19.2) | blocked credit and customs duty on capital goods enter asset cost here — and doc 46 §5 confirms upstream already does this, by patching a valuation rate |
| accounting period control (§2) | `return_period` reuses the same guard family |
| `doc_link` (§5) | import coverage is a link graph, replacing `pending_boe_qty` |
| `domain_event` / outbox / `projection_checkpoint` (§10) | localisation facts and events use the shared stream |
| withholding and LDC (doc 28 §7) | TDS/TCS interaction remains as specified there; GST does not duplicate it |

### 7.2 What remains open in localisation

- **Additional jurisdictions.** The design is jurisdiction-agnostic, but only India has been read at
  controller depth. UAE VAT, South Africa VAT and Italy exist in ERPNext's `regional/` tree and were **not**
  investigated; each will need a rule-revision mapping exercise, not new code.
- **Statutory formats will change.** `return_format_revision` exists so a format change is a row, but the
  actual GSTR-1/3B field maps (`gstr_1_json_map.py`, 2,702 lines) are a volume of detail we have specified
  the *container* for, not transcribed.
- ~~**Statutory document-numbering rules** per jurisdiction~~ — **CLOSED by
  [doc 58](58-statutory-numbering-and-the-withholding-gst-seam.md) Part A**, register G30–G35. Reading them
  found the statutory number *is* the row's primary key, so amendment rewrites it, and an unlawful number is
  silently excluded from GSTR-1 after the tax has been posted and paid.
- ~~**TDS/TCS interaction**~~ — **CLOSED by
  [doc 58](58-statutory-numbering-and-the-withholding-gst-seam.md) Part B**, register G36–G41. Note this
  entry was wrong in a way worth recording: "TDS/TCS" names *two unrelated systems*, and GST TDS/TCS
  (s.51/s.52) is absent from both trees. Doc 58 §8 scopes it explicitly instead of implying it was handled.
- **API credential handling and session management** (`GST Credential`, `api_classes/`) were read only far
  enough to establish the submission contract. Credential storage is in scope for **Tranche G**.
- **Audit trail** (`india_compliance/audit_trail/`) and **income tax / VAT India** modules were out of scope.

---

## 8. Investigation status after Tranche F

| Tranche | Scope | Status |
|---|---|---|
| A | accounting, stock, trade core | complete — docs 01–17, 26–32, S01–S06 |
| B | production, subcontracting, quality | complete — docs 33–40, S07–S10 |
| C | assets and depreciation | complete — docs 41–44, S11 |
| D | CRM, projects, support | **out of scope** by decision |
| E | platform mechanics | complete — docs 18–25 |
| **F** | **localisation, India GST** | **complete — docs 45–49, S12** |
| **G** | security, tenancy, multi-company/currency/location, consolidation | **next — planned docs 50–57, S13** |

ERPNext coverage remains **203 parents / 178 cited / 0 uncited submittable / 0 uncited configuration / 25
exclusions**, plus 26 India Compliance DocTypes read at controller depth. Invariant registers: `L/S/D/P`,
`F/T/R/V/U`, `M1–M69`, `A1–A26`, `G1–G29`. Scenarios **S01–S12**.

**Application implementation has not started.** With this tranche the named *functional* gaps are closed. What
remains before building is **Tranche G** — every tranche so far asserted `company_id` + RLS + `FORCE RLS` and
an authenticated tenant-context function without ever testing that boundary, and none of them specified
consolidation or the transaction/functional/presentation currency layering end to end — plus the open items in
§7.2 and the scale question that decides whether balances are materialised or computed (doc 01 §1.9).

---

Cross-references: [FINAL-SCHEMA.md §24–§28](../design/FINAL-SCHEMA.md),
[doc 45](45-gst-registration-settings-hsn-and-tax-structure.md),
[doc 46](46-gst-place-of-supply-and-component-determination.md),
[doc 47](47-e-invoice-and-e-waybill-external-state-machines.md),
[doc 48](48-gst-returns-reconciliation-and-imports.md),
[S12](../scenarios/S12-gst-invoice-e-invoice-and-gstr1.md),
[doc 25](25-our-platform-spec.md) (layering rule),
[doc 28](28-tax-determination.md) (the core tax engine GST rides on),
[doc 21](21-extensibility-hooks-and-regional.md) (the regional mechanism we reject),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) and
[doc 44](44-tranche-c-closure-and-our-asset-spec.md) (command/lock/idempotency/outbox contract),
[INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md) and [COVERAGE.md](../COVERAGE.md).
