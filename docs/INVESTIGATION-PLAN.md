# Investigation plan and coverage map

We are in **investigation mode**: the output of this repo is documents, not application code.
Building starts only when the investigation is declared complete.

Anchor commits for everything so far: `erpnext@ceefd4add7` (v17.0.0-dev), `frappe@5da68e856c`.

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

**Mentioned but not investigated** (named in the docs, deliberately not chased):
budget controller, deferred revenue/expense, POS lifecycle, bank reconciliation, inter-company /
common party accounting, cost-center allocation internals, `Repost Accounting Ledger`,
`Unreconcile Payment`, stock reservation entries, pick-list algorithm, quality-inspection gate.

## 2. What is left

Sized by DocType count from `schema/catalog_tables.csv` (erpnext app only).

| Tranche | Area | DocTypes | Why it matters |
|---|---|--:|---|
| **A** | **Accounts remainder** — budgeting + budget controller, deferred revenue/expense, POS lifecycle (opening/closing/merge log), bank transaction matching + reconciliation, payment requests/gateways, dunning, invoice discounting, loyalty, inter-company + common party, `Repost Accounting Ledger`, `Unreconcile Payment`, Process Statement of Accounts | ~60 of the 191 | closes the accounting module; several of these change table design (budgets, deferrals, POS) |
| **A** | **Stock remainder** — stock reservation entries, pick-list allocation, putaway rules, reorder / auto material request, batch expiry + FEFO picking, item variants & attributes, UOM conversion precision, quality-inspection gate, stock closing entry, warehouse capacity | ~35 of the 77 | reservation and FEFO in particular affect the `stock_move` design we already proposed |
| **B** | **Manufacturing** — BOM (+ cost roll-up, exploded items, update-cost job), Work Order, Job Card, Operations/Routing, Workstation capacity, Production Plan, Master Production Schedule, scrap & rework, WIP accounting | 48 (8 submittable) | large, self-contained; only needed if v1 makes things |
| **B** | **Subcontracting deep dive** — order/receipt lifecycle, supplied-item consumption, RM transfer, `Subcontracting BOM` | 13 | partially covered (valuation + GL only, in doc 03) |
| **C** | **Assets** — asset lifecycle, depreciation engine + schedules, finance books, shifts, capitalization, disposal, repair, movement | 26 (8 submittable) | the depreciation engine is a second ledger-posting engine with its own scheduling |
| **D** | **Projects & Quality** — project costing, timesheet → billing, Quality Management (16), Support (11), Maintenance (5) | ~47 | adjacent; mostly CRUD over the core |
| **D** | **CRM** — lead/opportunity/prospect | 28 | lowest priority for an ERP core |
| **E** | **Platform mechanics we must replace, not copy** — permission model (roles, user permissions, share, `if_owner`), naming series, the `hooks.py` extensibility model, `@allow_regional` overlay architecture (how India GST etc. inject fields and override calculations), background jobs + scheduler, patch/migration system, the query-report framework, custom fields & Customize Form, virtual doctypes | — | this is what we are *not* getting for free by leaving Frappe; it needs a deliberate answer per item |

## 3. Proposed order

1. **Tranche A** (accounts + stock remainder) — finishes the two modules we have already modelled, and
   is the only tranche that can still change the Phase 0-2 table designs in `docs/logic/08`.
2. **Tranche E** (platform mechanics) — needed before any build decision, because it determines how much
   framework we are writing ourselves.
3. **Tranche B / C** (manufacturing, assets) — only if in scope for v1.
4. **Tranche D** last.

Each tranche produces documents in the same shape as `docs/logic/`: pinned commit, `file.py:line`
citations, invariants, and an "ours" decision per behaviour, verified by `tools/verify_refs.py`.

## 4. Open questions

Answers change the order and the depth, not the method.

1. **Scope for v1** — is it trade + inventory + accounting only, or do manufacturing (B) and assets (C)
   need to be in the first build? This is the single biggest lever on how long the investigation runs.
2. **Inventory features that change the core design** — which of these are real requirements:
   batch/serial with expiry and FEFO picking, stock reservation, multi-warehouse transfers,
   landed cost, subcontracting, consignment/customer-owned stock?
3. **Localisation** — which countries' tax regimes must v1 handle? If more than one, Tranche E's
   regional-overlay investigation becomes urgent, because that is the mechanism ERPNext uses to inject
   country-specific fields and override tax calculation.
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
