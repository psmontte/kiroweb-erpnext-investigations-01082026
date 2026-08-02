# Business logic of the accounting, trade/inventory and production engine

What the code actually does, function by function, so we can reimplement it deliberately.

> **Looking for a flow rather than a subsystem?** See
> **[../scenarios/](../scenarios/README.md)** — Sales Order → Delivery Note → Sales Invoice,
> payments against invoices, and Purchase Order → Receipt → Invoice, each traced end to end with
> worked numbers and every table write in order, including manufacturing, supplier/customer-owned
> subcontracting and quality-gated production.

## Source anchor

Everything here was read from source at these exact commits. **Line numbers only mean anything
against these commits** — re-verify after a pull.

| App | Version | Commit | Date |
|---|---|---|---|
| `erpnext` | `17.0.0-dev` | `ceefd4add77715d2762c19db337fb83e28a477de` | 2026-08-01 |
| `frappe` | `17.0.0-dev` | `5da68e856ca7f036b20d2583167b9d00c4a8db56` | 2026-07-31 |

**Important:** v17 is mid-refactor. Logic that older ERPNext tutorials place in
`controllers/accounts_controller.py` has been extracted into service modules:

```
erpnext/accounts/services/   base_gl_composer.py  gl_validator.py  taxes.py  advances.py
                             exchange_gain_loss.py  payment_schedule.py  billing_validation.py
                             internal_transfer.py  deferred_accounting.py  party_validation.py
erpnext/stock/services/      base_stock_gl_composer.py  stock_ledger_service.py
                             serial_batch_bundle_service.py  internal_transfer.py
<doctype>/services/          gl_composer.py, status.py, billing_status.py, ...
```

Notably: `AccountsController` has **no** `make_gl_entries` any more (each voucher defines its own,
delegating to a composer), and per-voucher GL rules live in `<doctype>/services/gl_composer.py`.

## Reading order

| Read | File | Covers |
|---|---|---|
| 1 | [01-gl-posting-engine.md](01-gl-posting-engine.md) | how a document becomes balanced GL rows: gl_map pipeline, merge, sign normalisation, round-off, validation gates, reversal, balance reads |
| 2 | [02-stock-ledger-and-valuation.md](02-stock-ledger-and-valuation.md) | the hardest part: SLE ordering, FIFO/LIFO/moving-average/standard-cost, `stock_value_difference`, backdating and the repost engine, negative stock, batch/serial valuation, Bin |
| 3 | [03-stock-gl-bridge.md](03-stock-gl-bridge.md) | how inventory valuation and the ledger stay reconciled; per-document debit/credit tables; landed cost; drift detection |
| 4 | [04-ar-ap-and-settlement.md](04-ar-ap-and-settlement.md) | payment subledger, outstanding computation, allocation, advances, reconciliation, FX gain/loss, ageing, credit limit |
| 5 | [05-taxes-totals-and-pricing.md](05-taxes-totals-and-pricing.md) | the totals pipeline, all charge types, inclusive-tax back-calculation, discounts, rounding, pricing rules, payment schedule, withholding |
| 6 | [06-lifecycle-status-and-returns.md](06-lifecycle-status-and-returns.md) | draft/submit/cancel, fulfilment roll-ups and `per_*`, tolerances, returns, amendment, closed/hold, locking |
| 7 | [07-period-close-and-opening-balances.md](07-period-close-and-opening-balances.md) | period closing voucher, closing-balance snapshots, freeze/period gates, fiscal years, opening balances (AR/AP/stock), FX revaluation, report reads |
| 8 | [08-our-implementation-spec.md](08-our-implementation-spec.md) | **the deliverable**: invariants to enforce, what we keep/change, decisions taken, and the provisional build spec (parked — see [../INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md)) |
| 26 | [26-journal-entry-chart-of-accounts-dimensions.md](26-journal-entry-chart-of-accounts-dimensions.md) | the structures that define *where* posting happens: `Account` as a nested set with 14 validations, `Cost Center`, the **runtime-DDL dimension mechanism** (`Accounting Dimension` / `Inventory Dimension`), and `Journal Entry` — 16 voucher types in one table, with a **documented balancing exemption** |
| 27 | [27-remaining-stock-documents.md](27-remaining-stock-documents.md) | `Stock Reconciliation` (the only valuation override), `Item Standard Cost` (**the one design we adopt verbatim**), `Putaway Rule`, `Serial No`, `Product Bundle`/`Packing Slip`, `Delivery Trip`/`Shipment`, `Stock Entry Type`, and the `Stock Ledger Entry` **controller** — deferred naming, a second backward-only negative-stock check, three more freeze mechanisms |
| 28 | [28-tax-determination.md](28-tax-determination.md) | *which* tax applies, before doc 05 calculates it: `Tax Category` (a label with an unread flag), `Tax Rule`'s twenty-column matcher where **specificity outranks `priority`** and blank means wildcard except for `tax_category`, `Item Tax Template` slab selection (with a live sort-key bug), withholding category/group/rate selection, and Lower Deduction Certificates keyed on the **tax ID** rather than the party |

| 29 | [29-pricing-determination.md](29-pricing-determination.md) | which price list, which rule, in what order — plus a `Price List` currency change that re-labels stored amounts without converting them, `Promotional Scheme` **generating and deleting** Pricing Rule documents, an unlocked coupon counter, and a `Shipping Rule` sort that assigns to the wrong attribute |

| 30 | [30-upstream-trade-and-parties.md](30-upstream-trade-and-parties.md) | the pre-commitment layer: `Quotation` (alternatives grouped by **row adjacency**), `Proforma Invoice` (totals computed inside a PDF renderer, no cap on cumulative issue), `Request for Quotation` (**submitting it creates `User` accounts** and stores *translated* status values), `Supplier Quotation`, `Blanket Order` (allowance comparing stock UOM to transaction UOM), `Material Request` in depth, drop-ship (a delivery with no document), and the party/terms masters — plus settings singles that **rewrite DocType metadata** |

| 31 | [31-batch-processes-instruments-recurring.md](31-batch-processes-instruments-recurring.md) | background jobs modelled as **submitted documents** (a state machine of two booleans and RQ job-name strings, with a name typo that defeats its own mutex), instruments that post nothing (`Bank Guarantee`, `Cashier Closing` — which attributes cash by `owner` and **adds** returns), `Subscription` idempotency by date comparison, loyalty, banking config — and `Accounts Settings`, whose save rewrites metadata, reschedules a cron job, flushes the cache and makes posted documents editable |

| 32 | [32-stock-configuration-and-remaining-masters.md](32-stock-configuration-and-remaining-masters.md) | **the coverage-closure doc**: `Stock Settings` (the best irreversibility guards in the app — and a checkbox that rewrites every item's description, plus one that changes field precision across 11 doctypes), `Stock Reposting Settings` (**a weekly job that detects and repairs a broken stock↔GL invariant** — upstream agreeing with decision 6), attributes and variants, and the thin masters. Ends with the closure statement: Accounts, Stock, Selling and Buying at **zero uncited DocTypes** |
| 33 | [33-bom-costing-explosion-and-update-jobs.md](33-bom-costing-explosion-and-update-jobs.md) | BOM data model and lifecycle; recursion and `BOMTree`; exact material, operation and secondary-output costing; flat explosion semantics; `BOM Creator`; and the dependency, locking, transaction, scheduler and failure behavior of `BOM Update Tool` / `BOM Update Log` |
| 34 | [34-operations-routing-workstations-and-capacity.md](34-operations-routing-workstations-and-capacity.md) | Operation and sub-operation definitions; Routing copy semantics; Workstation/Type calendars, costs and finite-capacity scheduling; Job Card planned/actual intervals and races; operating-component valuation; Downtime Entry; Plant Floor projections; and Manufacturing Settings |
| 35 | [35-work-orders-job-cards-and-shop-floor.md](35-work-orders-job-cards-and-shop-floor.md) | Work Order and Job Card data/lifecycle; BOM material and operation snapshots; required-item, reservation and Bin projections; Job Card splitting, time, loss, corrective work and quality gates; all mapper outputs; downstream Stock Entry evidence; upstream roll-ups; direct mutations and races |
| 36 | [36-production-planning-mps-and-material-netting.md](36-production-planning-mps-and-material-netting.md) | Production Plan and child lifecycle; SO/MR demand; BOM/subassembly explosion; projected-stock, safety, MOQ/UOM and transfer netting; WO/MR/subcontract PO release; reservation/Bin projections; Sales Forecast; MPS demand, delivery schedules, lead time, unfinished submit path, MRP report and races |
| 37 | [37-manufacturing-stock-consumption-scrap-wip-and-gl.md](37-manufacturing-stock-consumption-scrap-wip-and-gl.md) | manufacturing Stock Entry execution and accounting: transfer/consumption/manufacture/repack/disassembly; WIP, backflush, process loss, secondary outputs, serial/batch, valuation/additional costs, Standard Cost variance, GL, projections and races |
| 38 | [38-subcontracting-orders-transfer-consumption-receipt-and-gl.md](38-subcontracting-orders-transfer-consumption-receipt-and-gl.md) | all four Subcontracting parents and both ownership directions: BOM/service conversion, PO/SO origin, supplier/customer material custody, reservation, transfer/return, receipt/Work Order consumption, secondary outputs, serial/batch, SLE/GL, projections and races |
| 39 | [39-quality-inspection-templates-readings-and-gates.md](39-quality-inspection-templates-readings-and-gates.md) | all eight Quality Management parents and four Stock operational-QI parents: schemas/lifecycle, template construction and fallback, locale-formatted readings 1–10, formula evaluation, Accepted/Rejected decisions, reference writeback, transaction and Job Card gates, scheduler reviews, evidence/projections, defects and races |
| 40 | [40-tranche-b-coverage-closure-and-our-production-spec.md](40-tranche-b-coverage-closure-and-our-production-spec.md) | **Tranche B deliverable**: exact final coverage, M1–M69 mapped to enforcement layers, concrete production/ownership/quality schema, transaction and reversal ordering, defect register and build sequence |

### Tranche A — deep dives (accounts + trade/inventory remainder)

| Read | File | Covers |
|---|---|---|
| 9 | [09-lifecycle-reversals-deletions.md](09-lifecycle-reversals-deletions.md) | the canonical `docstatus` state machine, hook ordering, **why ERPNext has no approval state**, submit/cancel/amend/delete/rename, and our `draft → pending_approval → approved → posted → reversed` model |
| 10 | [10-fulfilment-engine.md](10-fulfilment-engine.md) | `StatusUpdater` config-driven counters, `Σ LEAST(achieved, ordered)/Σ ordered`, over-delivery allowance, the lost-update race — and our `doc_link` + `fulfilment_line`/`fulfilment_doc` views |
| 11 | [11-advances-and-payment-allocation.md](11-advances-and-payment-allocation.md) | the **five** representations of "money applied to an obligation", `allocate_amount_to_references` in full, `reconcile_against_document`'s cancel/split/resubmit, and our insert-only `settlement` table |
| 12 | [12-budgets-deferrals-cost-center-allocation.md](12-budgets-deferrals-cost-center-allocation.md) | budget check as an unlocked `SUM`, deferred revenue state inferred from GL postings, cost-centre split rounding — and our commitment ledger + stored deferral schedule + exact-rational allocation |
| 13 | [13-pos-and-retail.md](13-pos-and-retail.md) | POS Invoice posting **no** GL/stock, availability as a live query, what consolidation destroys, session control — and our "POS sales are ordinary sales" model |
| 14 | [14-banking-and-collections.md](14-banking-and-collections.md) | `Bank Transaction` never posting GL, `clearance_date` as a scalar, `rank = 1 + three booleans`, dunning's `Data`-typed FKs — and our `bank_statement_line`/`bank_match` + suspense-account model |
| 15 | [15-intercompany-and-history-rewriting.md](15-intercompany-and-history-rewriting.md) | inter-company mirroring by two cross-pointing columns, and the three repost subsystems + unreconcile that exist only because derived state is stored |
| 16 | [16-stock-reservation-picking-warehouse.md](16-stock-reservation-picking-warehouse.md) | reservation correctness that **depends on the database engine** (with the source's own comments), pick allocation locking, `Bin`'s twelve caches, nested-set warehouses |
| 17 | [17-item-uom-variants-batch-reorder.md](17-item-uom-variants-batch-reorder.md) | item identity, `Bin.stock_uom` rewriting, variants with no uniqueness constraint, `Item Price` with no overlap detection, the reorder rollup bug, FEFO |

### Tranche E — platform mechanics (what we must build ourselves)

| Read | File | Covers |
|---|---|---|
| 18 | [18-metadata-and-runtime-ddl.md](18-metadata-and-runtime-ddl.md) | **the schema is data**: `DocType`/`DocField`/`Meta` assembly, `ALTER TABLE` on user save, silent blank→0 coercion, orphaned columns, Singles as untyped global settings — and our migrations + dimension slots + `setting_def` |
| 19 | [19-permissions-and-access-control.md](19-permissions-and-access-control.md) | six composed mechanisms, all application-level; the `if_owner` collapse; SQL from hooks and DB rows spliced into `WHERE`; eight bypass routes — and our RLS + grant model |
| 20 | [20-naming-identity-and-audit-trail.md](20-naming-identity-and-audit-trail.md) | eleven naming strategies, the `Series` counter, counter reversion by character offset, `Version` diffs that miss every `db_set` — and our `uuid` + `numbering_rule` + trigger-written audit |
| 21 | [21-extensibility-hooks-and-regional.md](21-extensibility-hooks-and-regional.md) | hooks as module-namespace introspection, install-order precedence, `doc_events["*"]`, `@allow_regional` taking the region from the **session** — and our typed `domain_event` + `tax_regime` data + `company_extension` |
| 22 | [22-background-jobs-scheduling-and-locking.md](22-background-jobs-scheduling-and-locking.md) | RQ without idempotency, a live scheduler bug (`maintenance_offset` computed then discarded), "weak" file locks used for GL rewrites — and our `job`/`schedule` tables + row locks in triggers |
| 23 | [23-migrations-and-patches.md](23-migrations-and-patches.md) | no schema migration at all: JSON reconciliation + `exec`'d patch strings, `skip_failing` reporting success, no rollback — and our checksummed transactional migrations |
| 24 | [24-reporting-framework.md](24-reporting-framework.md) | SQL and Python stored in table rows, post-hoc Python row filtering, **aggregates computed before permission filtering** — and our generated queries over RLS-bearing views |
| 25 | [25-our-platform-spec.md](25-our-platform-spec.md) | **the Tranche E deliverable**: build/buy/drop per capability, the four-layer rule, ten requirements on the orchestration engine, honest cost of leaving Frappe |

### Tranche B — production investigation (**complete**)

The confirmed order was **manufacturing → subcontracting → quality → closure**. Manufacturing is
complete in docs **33–37** plus **S07**; subcontracting in **doc 38**, **S08** and **S10**; quality in
**doc 39** and **S09**. [Doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) closes the
tranche with measured coverage, exact M1–M69 enforcement mapping, the concrete target production
schema, write/reversal ordering and build sequence. **Application implementation has not started.**

### Tranche C — assets investigation (**complete**)

| Read | File | Covers |
|---|---|---|
| 41 | [41-asset-identity-acquisition-and-finance-books.md](41-asset-identity-acquisition-and-finance-books.md) | asset identity and the four asset types; purchase-row resolution **by amount matching**; the conditional capitalisation journal decided by four GL probes; the daily job whose filter is `= nowdate()`; Asset Capitalization consuming stock, assets and services; categories, account resolution, finance books as editable policy copies; Locations and the activity log |
| 42 | [42-depreciation-engine-schedules-shifts-and-adjustments.md](42-depreciation-engine-schedules-shifts-and-adjustments.md) | the schedule generator loop; straight line (fixed, daily-prorata, shift-weighted), WDV/double declining, Manual; first/last-period proration and the salvage landing rule; the daily posting job's **index-window slice that bypasses its own due-date guard**; replanning by cancel-and-copy; Asset Shift Allocation's factor conservation; Asset Value Adjustment against the fixed-asset account |
| 43 | [43-asset-custody-maintenance-repair-and-disposal.md](43-asset-custody-maintenance-repair-and-disposal.md) | custody as scalars recomputed from movement history; the maintenance planner and its logs writing to each other; Asset Repair's ledger-checked invoice residual, per-book cost duplication and a cancellation that leaves the stock issue posted; splitting an asset by document copy that **amends posted depreciation journals**; and the four disposal callers sharing one derivation |
| 44 | [44-tranche-c-closure-and-our-asset-spec.md](44-tranche-c-closure-and-our-asset-spec.md) | **Tranche C deliverable**: measured closure across every audited module, A1–A26 mapped to enforcement layers, the concrete asset schema, deterministic locks/idempotency, write and reversal ordering, the Adopt/Change/Reject matrix, the pinned defect catalog, the build sequence — and the localisation/India-GST boundary that comes next |

### Tranche F — localisation, India GST first (**complete**)

India GST is **not in ERPNext**: removed in v14 (`patches/v14_0/remove_india_localisation.py:5-21`) and
maintained as `resilient-tech/india-compliance`, pinned at `205c3de` (`17.0.0-dev`, ~49,000 Python LOC, 26
DocTypes). Verify Tranche F citations with the third app root:

```bash
python3 tools/verify_refs.py --docs docs/logic \
  --app erpnext=/projects/sandbox/erpnext/erpnext \
  --app frappe=/projects/sandbox/frappe/frappe \
  --app india_compliance=/projects/sandbox/india_compliance/india_compliance
```

| Read | File | Covers |
|---|---|---|
| 45 | [45-gst-registration-settings-hsn-and-tax-structure.md](45-gst-registration-settings-hsn-and-tax-structure.md) | why GST cannot be read from ERPNext; how the app attaches (`doc_events` + **custom fields toggled by a settings checkbox**); GSTIN's seven category-specific formats and mod-36 check digit; GSTIN status as a cached external fact whose validation can arrive **after** the write; GST Settings gating scheduler rows; five components → fifteen account roles; the `gst_rate == tax_rate × 2` intra-state rule; HSN/SAC and its unversioned bulk push into item masters |
| 46 | [46-gst-place-of-supply-and-component-determination.md](46-gst-place-of-supply-and-component-determination.md) | the arithmetic core: place of supply stored as a **display string whose first two characters are statutory**; a missing place of supply silently meaning intra-state; source state recovered by slicing a GSTIN with `"96"` as a magic literal; intra/inter account filtering; the reverse-charge forward/booked cancellation and its **hard-coded 2-decimal tolerance** beside a refund rule that uses document precision; ineligible ITC redirecting tax into inventory and **asset** valuation in place; item-wise distribution; and GSTR-1-filed backdating control held in a Single |
| 47 | [47-e-invoice-and-e-waybill-external-state-machines.md](47-e-invoice-and-e-waybill-external-state-machines.md) | the two government endpoints that mint legal artefacts: applicability, the well-built error taxonomy (server / not-applicable / validation), `DUPIRN` reconciliation that compares only two fields **after decoding the authority's JWT with `verify_signature=False`**, the log written by a background job, the IRN **blanked on cancellation** because the field doubles as a state flag, a 24-hour statutory deadline read from an **onload cache**, our clock recorded as the authority's cancellation time, and a retry loop whose gate is cleared before the work it guards |
| 48 | [48-gst-returns-reconciliation-and-imports.md](48-gst-returns-reconciliation-and-imports.md) | the periodic obligations, where **the government holds a competing copy of our data**: GSTR-1's statutory taxonomy and its memoised working set gated by `is_latest_data`; reconciliation that keeps the signed difference (good) but writes `upload_status` back into its own input (bad); three separate hard-coded 2-decimal precisions; the **declarative purchase-matching rule ladder** — exact/fuzzy/rounding tiers as data, the best design in the tranche — undermined by match decisions being mutable link edits with no history; and Bill of Entry posting customs duty into inventory and asset value |
| 49 | [49-tranche-f-closure-and-our-localisation-spec.md](49-tranche-f-closure-and-our-localisation-spec.md) | **Tranche F deliverable**: what the tranche measured (a third repository, not an ERPNext module), G1–G29 mapped to enforcement layers, the five decision themes — adopt wholesale / reject mechanism / reject display-text-as-data / reject defaults and tolerances that decide money / reject mutable facts — the **signature finding**, the concrete schema in `FINAL-SCHEMA` §24–§28, the 11-step build sequence, and the seams where localisation touches stock, assets, periods and the link graph |

### Tranche G — security, tenancy and multi-entity (**complete**)

The boundary every previous tranche asserted and none tested. **Frappe has no row-level security, no tenant
context and no session scope** — a search of the pinned tree returns zero occurrences of `ROW LEVEL SECURITY`,
and the only `current_setting(` is in a query-builder test. Company is a *data dimension* filtered by
`User Permission`, and `ignore_permissions=True` appears **892 times** across Frappe and ERPNext. Worse than
absent, the mechanism that exists **fails open**: an empty result from the scoping lookup means *unrestricted*
(`frappe/permissions.py:351-380`). Invariant prefix **T**, register **T1–T30**, **84 defects** catalogued,
target tables in [`FINAL-SCHEMA` §29–§37](../design/FINAL-SCHEMA.md), walked end to end by
[S13](../scenarios/S13-cross-company-consolidation-and-isolation.md).

| Read | File | Covers |
|---|---|---|
| 50 | [50-authentication-session-and-tenant-context.md](50-authentication-session-and-tenant-context.md) | why there is no tenant context to bind RLS to; the two login paths and the **downgrade-to-`Guest`** fallback; two-axis lockout (adopted); non-interactive auth where a **caller-supplied header chooses the authenticating DocType**, authenticators swallow exceptions, and the fail-closed guard only fires when an `Authorization` header was present; sessions that carry **no company**; and our `principal` / `principal_company_membership` / `auth_session` model with the `auth.current_company()` function RLS actually binds to |
| 51 | [51-permission-model-end-to-end.md](51-permission-model-end-to-end.md) | the decision path traced branch by branch, asking at each one *what happens when the rule is absent* — and finding that **the permission system fails open**: no `User Permission` rows means unrestricted, an empty allowed-list skips the check, an **empty link value evades scope** unless a strictness setting is on, that setting is off by default and switched off again for new documents, `Administrator` bypasses everything first, and **sharing grants** what roles denied. Adopted wholesale: **controllers may only deny**, and permission failures explain themselves |
| 52 | [52-tenant-isolation-and-rls-under-attack.md](52-tenant-isolation-and-rls-under-attack.md) | the adversarial question: from a session in company A, how do you reach company B? Five attack classes — **the database layer applies no permissions at all** (`db.sql`/`get_value`/`get_values` are unguarded), **background jobs default to `Administrator`** and so hold total authorisation by omission, 892 in-code bypasses plus 34 identity switches, reports as a parallel read path gated only by a doctype capability, and count/link endpoints as cardinality and existence oracles. Delivers the **executable test matrix** (read, write, execution-context, authorisation edges) and a generated `rls_conformance` check that fails the build |
| 53 | [53-multi-company-intercompany-and-transfer-pricing.md](53-multi-company-intercompany-and-transfer-pricing.md) | what the system records when a transaction legitimately crosses companies. Two consolidation reports **do** exist and aggregate a company subtree, but they eliminate nothing, weight nothing and store nothing (doc 56) — and the `Company` tree carries no ownership, method or acquisition date. Cross-currency crossings are **refused outright**; the counterparty is **guessed** (`parties[0]`) when several internal parties exist; leg-rate agreement is **opt-in and off by default**; the pairing is two mutable scalars that can be **unlinked after posting**; and unrealised intra-group margin is **parked in an account, never tracked to realisation**. Adopted: bidirectional reference validation, `Allowed To Transact With`, `Party Link`'s non-chaining rules, partial mirroring |
| 54 | [54-multi-currency-layering.md](54-multi-currency-layering.md) | three currency layers where ERPNext has two: functional currency is `default_currency` in all but name, `reporting_currency` is a **label with no translation mechanism**, and there is **no CTA account and no translated balances** — so a multi-currency group cannot be consolidated. Rate resolution fails four different silent ways, including a **`0.00` rate** when settings are disabled and an author's own unresolved 2016 comment asking whether a missing currency should throw. Documents store the rate **value, not its identity**; pegs are **not effective-dated**; a synchronous HTTP fetch sits in the conversion path. Adopted: four-case peg arithmetic with cross-peg recursion, purpose-scoped rates, the **booked/unbooked** FX split |
| 55 | [55-multi-location-branch-and-segment.md](55-multi-location-branch-and-segment.md) | every axis other than company and currency: **two separate dimension systems** (accounting and inventory) that both perform runtime DDL and need a shared dimension defined twice; dimension filters that constrain **writes only**, so no dimension is ever a read boundary; `Warehouse.is_group` **inferred** from whether children exist; **no segment reporting at all**; and the Tranche F seam — a GST registration is **per state, carried on the `Address`**, so a company has plural statutory periods. Our model: one `dimension` as data, one `operating_location` hierarchy, `location_registration`, and `dimension_read_narrowing` that may only subtract from company scope |
| 56 | [56-consolidation-and-group-reporting.md](56-consolidation-and-group-reporting.md) | consolidation **does exist** — two reports, one side-by-side and one genuinely merged, with the codebase's only structural group rule (all companies must share a root). What it does not do is the three things that turn aggregation into consolidation: **no eliminations** (intra-group revenue, cost, receivables and payables all double-counted), **no ownership weighting** (a 60%-owned subsidiary consolidates at 100%), **no minority interest**. Aggregation joins on **`account_name`**, the translation reserve is a **balancing plug** that absorbs missing rates indistinguishably, and **nothing is stored** — so a group statement cannot be reproduced and adjustments cannot be posted |
| 57 | [57-tranche-g-closure-and-our-security-spec.md](57-tranche-g-closure-and-our-security-spec.md) | **Tranche G closure.** Twenty-three schema sections asserted `company_id` + forced RLS + an authenticated tenant-context function; this closes the assumption. The measured result: **no isolation mechanism exists** — the only `current_setting` in either tree is in a query-builder test — and 892 sites switch the application-level filtering off. Consolidates **T1–T30** mapped to enforcement layer, the 84-defect catalogue, the Adopt/Change/Reject decisions in five themes, an explicit **threat model** with its out-of-scope boundary, and a 16-step build sequence that is **step 0** — it precedes every other tranche, because retrofitting scope columns and an execution-context contract onto populated tables is a rewrite |



Assets are documented in docs **41–44** plus **[S11](../scenarios/S11-asset-lifecycle.md)**: all 14
parent controllers are cited with zero submittable and zero configuration gaps, and the register runs
**A1–A26**. S11 is the one scenario in this repository where every voucher balances, net assets are right,
and the balance sheet is still wrong: capitalised repair and revaluation leave equal and opposite residuals
in Fixed Assets and Accumulated Depreciation, because disposal derives both from mutable scalars by
subtraction, silently reclassifying cost as depreciation. **[Doc 44](44-tranche-c-closure-and-our-asset-spec.md)**
closes the tranche and names localisation — India GST first — as what remains.

Tranche G is documented in docs **50–57** plus **[S13](../scenarios/S13-cross-company-consolidation-and-isolation.md)**.
It adds no new ERPNext parents — docs 50–52 read Frappe framework modules, docs 53–56 read controllers and
reports under parents already counted — but it is the tranche the other twenty-three schema sections stand on,
which is why [doc 57](57-tranche-g-closure-and-our-security-spec.md) §8 makes the boundary **step 0** of the
build sequence rather than a later hardening pass. S13 is the only scenario here with an adversarial second
half, and the only one that **cannot be run upstream at all**: cross-currency inter-company documents are
refused outright.

Consolidated target schema: **[../design/FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md)** — finalised
accounting/trade plus concrete production, owner/custodian, planning, capacity, execution,
subcontracting and quality tables, data flow, business rules and invariant registers.

## Verifying the citations

Line numbers drift with every upstream commit. `tools/verify_refs.py` extracts every citation from
these docs, resolves it against the source tree, and reports the enclosing `def`/`class`, so a
drifted line shows up as an obviously wrong symbol name:

```bash
python3 tools/verify_refs.py --docs docs/logic \
  --app erpnext=/path/to/erpnext/erpnext \
  --app frappe=/path/to/frappe/frappe --strict-names
```

Run it once per directory (`docs/logic`, `docs/scenarios`); it does not recurse.

Both citation forms are verified:

| Form | Example | How it is resolved |
|---|---|---|
| full | `accounts/doctype/journal_entry/journal_entry.py:562` | path relative to the app package root, or by unique basename |
| shorthand | a bare line number in parentheses, or a trailing `#` comment inside a quoted code block | "another line of the file under discussion" |

A shorthand ref is resolved against **every file the document cites in full**, preferring the
candidate whose enclosing symbol at that line matches a backticked identifier on the same (or
previous) doc line. That name agreement is the real check — a drifted line number stops matching its
symbol and is reported rather than silently resolving. Where a line number is plausible in more than
one cited file and no name pins it down, the tool reports `AMBIGUOUS` and lists what sits at that
line in each candidate; the fix is to cite that one in full.

Last run against the anchor commits:

| Directory | Citations | Confirmed by symbol name | Problems |
|---|---|---|---|
| `docs/logic` | 5132 | 1593 | 0 |
| `docs/scenarios` | 824 | 164 | 0 |
| `docs/design` | 87 | 0 | 0 |

Name notes under `--strict-names` are advisory: the doc line may legitimately name a symbol defined
elsewhere in the same file. Frappe-side citations are prefixed `frappe/`.

## Conventions used in these docs

- `accounts/general_ledger.py:120-140` — path relative to `erpnext/` (or `frappe/` where stated) at the anchor commit.
- **Invariant** blocks are things the system depends on; break one and the books stop balancing.
- **Ours** blocks state what we do instead, and why.
- Amounts: "base" = company currency, "account currency" = the ledger account's own currency,
  "transaction currency" = the document's currency.

## One-paragraph summary of the whole engine

A user edits a **document**. On save, a calculation pipeline derives every monetary field
(`taxes_and_totals.py`) and a payment schedule. On **submit**, the document produces two kinds of
immutable rows: **stock ledger entries** (quantity + valuation state per
item+warehouse+owner+custodian) and **GL entries** (balanced double-entry rows). Stock rows are
produced first, because the GL inventory amount is read back *from* the stock rows
(`stock_value_difference`) — that single
back-reference is what keeps inventory and accounting reconciled. Receivable/payable GL rows are
mirrored into a **payment subledger** so "what is still unpaid" is one indexed aggregate rather than
a ledger scan. Everything downstream (status, fulfilment percentages, ageing, balances) is *derived*
from those rows, and every derivation is a full recompute rather than an incremental delta — which
is what makes reposting, cancellation and reconciliation idempotent.
