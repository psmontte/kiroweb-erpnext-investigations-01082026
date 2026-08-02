# Investigation plan and coverage map

We are in **investigation mode**: the output of this repo is documents, not application code.
**Application implementation has not started.** Every audited module — including Assets (Tranche C) —
is now investigated; building starts only once the investigation is declared complete.

Anchor commits for everything so far: `erpnext@ceefd4add7` (v17.0.0-dev), `frappe@5da68e856c`, and — for
Tranche F only — `india-compliance@205c3de939` (`develop`, `17.0.0-dev`, requires `frappe >=17.0.0-dev`).
**India GST is not in ERPNext core**: it was removed in v14 and lives in a separate app
(`patches/v14_0/remove_india_localisation.py:5-21`), so Tranche F pins a third repository.

---

## 1. Coverage so far

### Schema (`docs/reveng/`) — complete for the studied modules

| Scope | Status |
|---|---|
| All 997 DocTypes across `frappe`, `erpnext`, `payments`, `hrms`, `webshop` catalogued | done |
| Column-level reference for Accounts, Stock, Selling, Buying, Subcontracting, Setup | done |
| Cross-cutting patterns, document-flow graph, ER diagrams, table-count reconciliation | done |
| PostgreSQL DDL (as-is + normalised), executed and verified | done |

### Business logic (`docs/logic/`) — complete for the accounting + trade core

| Area | Doc | Depth |
|---|---|---|
| GL posting engine, validation gates, cancellation, balance reads | 01 | full |
| Stock ledger, all four valuation methods, backdating/repost, Bin, reconciliation, serial/batch valuation | 02 | full |
| Stock↔GL bridge, per-document postings, landed cost, drift detection | 03 | full |
| AR/AP subledger, outstanding, allocation, advances, reconciliation, FX, ageing, credit limit | 04 | full |
| Totals/taxes/pricing, payment schedule, tax withholding, multi-currency | 05 | full |
| Lifecycle, fulfilment roll-ups, tolerances, returns, amendment, cancel ordering | 06 | full |
| Period control, period close, closing snapshots, opening balances, FX revaluation, report reads | 07 | full |
| Our design intent: invariants, target tables, posting algorithm, test plan | 08 | full |

### Tranche A (`docs/logic/09`–`17`) — **complete**

| Area | Doc | Depth |
|---|---|---|
| Document lifecycle, hook ordering, approval (and its absence), submit/cancel/amend/delete/rename | 09 | full |
| Fulfilment engine: `StatusUpdater`, counters, percentages, allowances, the lost-update race | 10 | full |
| Advances, payment allocation, reconciliation (cancel/split/resubmit), the five representations | 11 | full |
| Budgets + budget controller, deferred revenue/expense, cost-center allocation | 12 | full |
| POS lifecycle: opening/closing entry, POS Invoice, merge log, availability, loyalty | 13 | full |
| Banking: bank transaction, matching engine, clearance, payment requests, dunning, invoice discounting, statements | 14 | full |
| Inter-company + common party; `Repost Accounting Ledger` / `Repost Payment Ledger` / `Repost Item Valuation`; `Unreconcile Payment`; deletion | 15 | full |
| Stock reservation entries, pick-list allocation, `Bin`, warehouse structure | 16 | full |
| Item master, UOM conversion, variants & attributes, `Item Price` validity, reorder, batch/serial + FEFO | 17 | full |

Consolidated target design: **`docs/design/FINAL-SCHEMA.md`** (finalised tables, data flow,
business rules, lifecycle state machine, fulfilment views, settlement model, invariant register).

Citation verification across `docs/logic/`: superseded — see the current coverage matrix
(**5,181 citations, 0 problems** across logic and scenarios, shorthand included).

~~**Still named but not chased**~~: putaway rules (doc 27 §3), warehouse capacity (doc 27 §3, doc 16
§4), stock closing entry (doc 27, S05 §6), loyalty program internals (doc 31 §4), payment-gateway
accounts (doc 31 §5.3) — **all now covered**. The quality-inspection gate remains in Tranche B with
the rest of quality management.

### Trade / inventory / accounts closure (`docs/logic/26`–`32`, `docs/scenarios/S04`–`S06`) — **complete**

Requested explicitly: stock transfer + in-transit, period close + opening balances, multi-currency
invoice → payment → FX revaluation — plus everything needed to call the three modules fully covered.

| Area | Doc | Depth |
|---|---|---|
| `Journal Entry`, chart of accounts, cost centers, the runtime-DDL dimension mechanism | 26 | full |
| Remaining stock documents: reconciliation, standard cost, putaway, serial no, bundles, logistics, the SLE controller | 27 | full |
| Tax determination: `Tax Category`, `Tax Rule`, `Item Tax Template`, charge templates, withholding + LDC | 28 | full |
| Pricing determination: `Price List`, `Pricing Rule`, `Promotional Scheme`, `Coupon Code`, `Shipping Rule`, eligibility, alternatives | 29 | full |
| Upstream trade + parties: `Quotation`, `Proforma Invoice`, RFQ, `Supplier Quotation`, `Blanket Order`, `Material Request`, drop-ship, terms, Selling/Buying Settings | 30 | full |
| Batch processes, instruments that post nothing, `Subscription`, loyalty, banking config, `Accounts Settings` | 31 | full |
| **Coverage closure** — `Stock Settings`, `Stock Reposting Settings`, attributes/variants, thin masters, and the closure statement | 32 | deliverable |
| Stock transfer between warehouses, including in-transit | S04 | scenario |
| Period close and opening balances, walked through | S05 | scenario |
| Multi-currency: invoice → payment → FX revaluation | S06 | scenario |

**Coverage: `Accounts`, `Stock`, `Selling`, `Buying`, `Manufacturing` and `Subcontracting` are at
zero uncited DocTypes** — submittable and configuration alike (`docs/COVERAGE.md`, generated).
Citations: **5,181 verified, 0 problems**, including the shorthand form.

Three findings from this closure changed how confident we are in earlier decisions:

- `Stock Reposting Settings` ships a **weekly job that scans for a broken stock↔GL invariant and
  repairs it** (doc 32 §2.3) — upstream agreeing with decision 6.
- `quote_status` is stored as the output of `_()`, written by three code paths with two different
  value domains (doc 30 §3.2) — which is why "no stored value is ever a translation" is now invariant
  U7.
- Submitting a `Request for Quotation` **creates `User` accounts** and writes to the `Supplier` master
  with validation disabled (doc 30 §3.1) — the clearest case for the "side effects documents may not
  have" table in doc 30 §11.4.

### Tranche B (`docs/logic/33`–`40`, `docs/scenarios/S07`–`S10`) — **complete**

Manufacturing, both subcontracting ownership directions and operational/management quality are closed
at controller and design depth. [Doc 40](logic/40-tranche-b-coverage-closure-and-our-production-spec.md)
consolidates M1–M69, enforcement layers, concrete target tables, deterministic locking/idempotency,
write/reversal ordering and the Adopt/Change/Reject decisions. Final measured production coverage is
Manufacturing **18/18**, Subcontracting **4/4**, Quality Management **8/8**, with zero submittable and
zero configuration gaps. Application implementation has not started.


### Tranche E (`docs/logic/18`–`25`) — **complete**

| Area | Doc | Depth |
|---|---|---|
| Metadata meta-schema, `Meta` assembly, runtime DDL, custom fields / property setters / Customize Form, Singles, virtual doctypes | 18 | full |
| Permissions: roles, `if_owner`, user permissions, sharing, controller hooks, `permission_query_conditions`, field-level | 19 | full |
| Naming (11 strategies), the `Series` counter, rename/amend, `Version` / `Audit Trail` / log family, retention | 20 | full |
| `hooks.py` resolution and merge semantics, `doc_events`, `@allow_regional`, `override_doctype_class`, Server/Client Scripts | 21 | full |
| RQ + workers, `execute_job` transaction semantics, scheduler and cron mapping, all three locking mechanisms | 22 | full |
| `bench migrate` pipeline, `patches.txt`, patch execution, `Patch Log`, install/app lifecycle | 23 | full |
| Five report types, ERPNext financial reports, post-hoc permission filtering, dashboards, print | 24 | full |
| **Platform specification** — build/buy/drop per capability, four-layer enforcement rule, engine requirements | 25 | deliverable |

Citation verification: superseded — see the closure block above.

## 2. What is left

Sized by DocType count from `schema/catalog_tables.csv` (erpnext app only).

| Tranche | Area | DocTypes | Why it matters |
|---|---|--:|---|
| ~~**A**~~ | ~~**Accounts remainder**~~ — budget controller, deferred revenue/expense, POS lifecycle, bank matching + reconciliation, payment requests, dunning, invoice discounting, inter-company + common party, repost subsystems, `Unreconcile Payment`, statements | ~60 of the 191 | **DONE** — `docs/logic/11`–`15` |
| ~~**A**~~ | ~~**Stock remainder**~~ — stock reservation entries, pick-list allocation, reorder / auto material request, batch expiry + FEFO picking, item variants & attributes, UOM conversion precision, warehouse structure | ~35 of the 77 | **DONE** — `docs/logic/16`–`17` |
| ~~**A**~~ | ~~**Trade / inventory / accounts closure**~~ — Journal Entry + CoA + dimensions, remaining stock documents, tax determination, pricing determination, upstream trade + parties, batch processes + instruments + recurring, stock configuration | the remainder | **DONE** — `docs/logic/26`–`32`, `docs/scenarios/S04`–`S06`. Accounts/Stock/Selling/Buying at **zero uncited DocTypes** |
| ~~**B**~~ | ~~**Manufacturing** — BOM (+ cost roll-up, exploded items, update-cost job), Work Order, Job Card, Operations/Routing, Workstation capacity, Production Plan, Master Production Schedule, scrap & rework, WIP accounting~~ | 48 total / 18 parents (8 submittable) | **DONE** — docs 33–37 + S07; 18/18 parent controllers cited, 0 gaps |
| ~~**B**~~ | ~~**Subcontracting deep dive** — order/receipt lifecycle, supplied-item consumption, RM transfer, `Subcontracting BOM`, customer-owned inward flow~~ | 13 total / 4 parents (3 submittable) | **DONE** — doc 38 + S08 + S10; 4/4 parent controllers cited, 0 gaps |
| ~~**C**~~ | ~~**Assets** — asset lifecycle, depreciation engine + schedules, finance books, shifts, capitalization, disposal, repair, movement~~ | 26 total / 14 parents (8 submittable) | **DONE** — docs 41–44 + S11; 14/14 parent controllers cited, 0 gaps |
| **F** | **Localisation — India GST first** — jurisdiction as data, HSN/SAC, place of supply, CGST/SGST/IGST/cess components, reverse charge, TDS/TCS interaction, statutory numbering, GSTR/e-invoice extracts, amendment and credit-note semantics | 27 parents in `india_compliance` | **IN PROGRESS** — docs 45–47 done (registration/settings/HSN/tax structure; determination core; external artefacts). Register **G1–G23**. ERPNext's `@allow_regional` overlay is **rejected** (doc 21 §4, doc 42 §4.3) |

### Tranche F deliverables

| Order | Document | Scope |
|---:|---|---|
| 45 | [`45-gst-registration-settings-hsn-and-tax-structure.md`](logic/45-gst-registration-settings-hsn-and-tax-structure.md) | **DONE** — GST's absence from core, the app's attachment mechanism, GSTIN/PAN identity and status caching, GST Settings, five-component tax structure, HSN/SAC |
| 46 | [`46-gst-place-of-supply-and-component-determination.md`](logic/46-gst-place-of-supply-and-component-determination.md) | **DONE** — place of supply and provenance, intra/inter split, applicable component sets, reverse charge and refund balance rules, ineligible ITC into inventory/asset cost, item-wise distribution, statutory period control |
| 47 | [`47-e-invoice-and-e-waybill-external-state-machines.md`](logic/47-e-invoice-and-e-waybill-external-state-machines.md) | **DONE** — obligation, submission attempts, duplicate reconciliation and signature verification, cancellation windows, in-transit amendments, durable retry |
| 48 | `48-gst-returns-and-reconciliation.md` | GSTR-1/3B, purchase reconciliation, Bill of Entry, amendment semantics |
| 49 | `49-tranche-f-closure-and-our-localisation-spec.md` | closure, G-register, jurisdiction-as-data schema, build order |

Scenario: **S12** GST invoice → e-invoice → GSTR-1.
| ~~**D**~~ | ~~**Projects, Support, Maintenance, CRM**~~ — project costing, timesheet → billing, Support (11), Maintenance (5), CRM lead/opportunity/prospect (28) | ~75 | **OUT OF SCOPE** — dropped by decision. Not investigated, not built. |
| ~~**B**~~ | ~~**Quality Management + operational quality** — Quality Management records plus Stock-owned inspection templates/readings and gates on receipts, deliveries, Stock Entry and Job Card~~ | 16 total / 8 module parents, plus 4 Stock parents | **DONE** — doc 39 + S09; all 12 parents cited, 0 gaps |
| ~~**E**~~ | ~~**Platform mechanics we must replace, not copy**~~ — permission model, naming series, `hooks.py` extensibility, `@allow_regional` overlay, background jobs + scheduler, patch/migration system, query-report framework, custom fields & Customize Form, virtual doctypes | — | **DONE** — `docs/logic/18`–`25`, with a build/buy/drop decision per capability in `25-our-platform-spec.md` |

### Tranche B deliverables

| Order | Completed document | Scope |
|---:|---|---|
| 33 | `33-bom-costing-explosion-and-update-jobs.md` | BOM lifecycle, recursion, rates, roll-up, explosion and background refresh |
| 34 | `34-operations-routing-workstations-and-capacity.md` | Operation, Routing, workstation calendars/capacity/cost and shop-floor masters |
| 35 | `35-work-orders-job-cards-and-shop-floor.md` | Work Order, Job Card, reservations, scheduling, time, completion and in-process quality |
| 36 | `36-production-planning-mps-and-material-netting.md` | Production Plan, demand/netting, generated supply, Sales Forecast and MPS |
| 37 | `37-manufacturing-stock-consumption-scrap-wip-and-gl.md` | Stock Entry, consumption/backflush, outputs/loss, SLE, WIP and GL |
| 38 | `38-subcontracting-orders-transfer-consumption-receipt-and-gl.md` | BOM, supplier Order/Receipt and customer-owned Inward Order |
| 39 | `39-quality-inspection-templates-readings-and-gates.md` | Stock-owned operational inspection plus Quality Management records |
| 40 | [`40-tranche-b-coverage-closure-and-our-production-spec.md`](logic/40-tranche-b-coverage-closure-and-our-production-spec.md) | **DONE** — measured closure, M1–M69, target production schema/ordering and decisions |

Scenarios: **S07** make-to-order manufacturing; **S08** supplier subcontracting; **S09**
quality-gated receipt/production; **S10** customer-owned subcontracting inward.

## 3. Order (confirmed: "Your order")

1. ~~**Tranche A** (accounts + stock remainder)~~ — **complete**, `docs/logic/09`–`17`, and it did
   change the design: `doc_link` + fulfilment views (D7), insert-only `settlement` (D8),
   explicit `approval_state` (D10), and the reservation/on-hand trigger model all came out of it.
2. ~~**Tranche E** (platform mechanics)~~ — **complete**, `docs/logic/18`–`25`. Answer to
   "how much framework are we writing ourselves": small-to-medium and mostly one-off. The large
   remaining items (report view library, front end, localisation data) are not framework.
   See `25-our-platform-spec.md` §6.
3. **Scenario walkthroughs** (`docs/scenarios/`) — cross-cutting flow traces tying the subsystem
   documents together. S01–S11 cover trade/inventory/accounts, manufacturing, subcontracting, quality and
   the asset lifecycle.
4. ~~**Tranche B** — manufacturing → subcontracting → quality → closure/specification~~ —
   **complete**, docs 33–40 and scenarios S07–S10. Doc 40 consolidates the measured closure, M1–M69,
   target schema and build order.
5. ~~**Tranche C** (assets + depreciation)~~ — **complete**, `docs/logic/41`–`44` and `S11`; invariant
   register **A1–A26**. Doc 44 consolidates the measured closure, enforcement mapping, asset schema and
   build order.
5a. **Tranche F** (localisation, **India GST first**) — **next**, and now a confirmed requirement rather
   than an open question. Scoped in doc 44 §11.
6. ~~**Tranche D**~~ — **dropped**: no CRM, no projects, no support.
7. **Implementation** — has not started.

Each tranche produces documents in the same shape as `docs/logic/`: pinned commit, `file.py:line`
citations, invariants, and an "ours" decision per behaviour, verified by `tools/verify_refs.py`.

## 4. Open questions

Answers change the order and the depth, not the method.

1. ~~**Scope for v1**~~ — **answered for investigation order.** CRM, projects, and support are
   **out of scope**. Manufacturing, subcontracting, and quality are complete in Tranche B, and assets
   and depreciation are now complete in Tranche C (docs 41–43, S11). Application implementation has not
   started.
2. **Inventory features that change the core design** — which of these are real requirements:
   batch/serial with expiry and FEFO picking, stock reservation, multi-warehouse transfers,
   landed cost, subcontracting, consignment/customer-owned stock?
3. ~~**Localisation**~~ — **answered: India GST is required, and it is the priority.** More than one
   regime is in scope, so replacing the regional-overlay mechanism is now urgent rather than theoretical —
   ERPNext resolves `@erpnext.allow_regional` overrides from company country at call time (doc 21 §4), and
   doc 42 §4.3 found that mechanism sitting directly on the declining-balance depreciation calculation. We
   reject it. Tranche F is scoped in [doc 44 §11](logic/44-tranche-c-closure-and-our-asset-spec.md).
   Still open: which **additional** jurisdictions v1 must handle alongside India.
4. **Scale targets** — rough rows/day on the ledgers, number of companies, concurrent users. This decides
   whether balances are materialised (doc 01 §1.9) or computed, and whether the valuation projection needs
   partitioning.
5. **Upstream tracking** — ERPNext ships continuously. Do you want a periodic "delta report" against a new
   commit (what changed in the areas we documented), or is the pinned snapshot sufficient for now?
6. **Document format** — is Markdown-in-git the right final form, or do these need to become something
   else (Confluence, PDF, a spec site) for review by people outside the repo?

## 5. Method (unchanged, for the record)

1. Pin the commit; never cite a moving target.
2. Read the code, not the manual — every claim carries `file.py:line`.
3. Write the **algorithm**, not a description: exact formulas, order of operations, error conditions.
4. State the **invariants** separately from the implementation; they are what we must preserve.
5. Record an explicit **ours** decision per behaviour (copy / reject / replace) with the reason.
6. Verify citations mechanically (`tools/verify_refs.py`) before pushing.
