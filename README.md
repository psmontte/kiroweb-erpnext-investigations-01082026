# erp — our own ERP (backend / database)

**Investigation mode.** We are documenting the Frappe/ERPNext data model and business logic first;
**application implementation has not started** and starts only once the investigation is declared
complete. Tranches A, B, C, E and F are done; Tranche D (CRM, projects, support) is out of scope. Coverage map and remaining work:
[docs/INVESTIGATION-PLAN.md](docs/INVESTIGATION-PLAN.md).

Parsed the full standard app set — `frappe`, `erpnext`, `payments`, `hrms`, `webshop`:
**997 DocTypes → 908 physical tables → 10,995 columns.** The accounting and trade/inventory
modules of `erpnext` are documented at column level.

```
docs/reveng/     schema study — start at docs/reveng/README.md
docs/logic/      business-logic study by subsystem — start at docs/logic/README.md
docs/scenarios/  end-to-end flow walkthroughs with worked numbers (SO→DN→SI, payments, PO→PR→PI)
docs/design/     FINAL-SCHEMA.md — the finalised tables, data flow, business rules,
                 lifecycle state machine, fulfilment views, settlement model, invariants
schema/          machine-readable catalog (JSON + CSV) and generated DDL
schema/ddl/      *_asis.sql  = ERPNext physical layout as PostgreSQL
                 clean_*.sql = normalised reference schema
tools/reveng/    the parser toolkit — re-runnable against any Frappe app
tools/verify_ddl.sh  loads the generated DDL into a throwaway PostgreSQL and reports errors
tools/verify_refs.py checks every source citation in docs/ against the source tree
tools/coverage_audit.py measures DocType coverage by whether a controller is cited at a line
```

## Regenerate everything

```bash
python3 tools/reveng/run.py --out . \
  --app erpnext=/path/to/erpnext/erpnext \
  --app frappe=/path/to/frappe/frappe \
  --app payments=/path/to/payments/payments \
  --app hrms=/path/to/hrms/hrms \
  --app webshop=/path/to/webshop/webshop
```

Only `--app erpnext=...` is strictly required; adding the others makes every `Link` column
resolve to a known owner instead of "unknown". No third-party dependencies — standard
library only.

## Verify the DDL actually loads

```bash
./tools/verify_ddl.sh
```

The script installs PostgreSQL if it is missing (the sandbox is reset periodically),
initialises its own data directory, loads both schemas and reports per-file errors.

Last run:

```
as-is DDL   accounts / buying / selling / setup / stock / subcontracting   all OK
clean DDL   clean_01_tables.sql, clean_02_constraints.sql                  all OK
  asis:  338 tables, 0 FKs, 815 indexes      (faithful ERPNext layout — it has no FKs)
  clean: 429 tables, 2051 FKs, 1193 indexes
  dangling FK targets: 0
```

## Toolkit layout

| File | Responsibility |
|---|---|
| `frappe_schema.py` | DocType/Field model, fieldtype → SQL type maps (transcribed from frappe core), multi-app registry + relationship queries |
| `catalog.py` | JSON + CSV catalog of every table, column and relation |
| `render.py` | overview, full table catalog, per-module column-level reference |
| `erd.py` | Mermaid ER and dependency diagrams |
| `flows.py` | auto-derives the document chain from real Link columns |
| `patterns.py` | cross-cutting patterns: shared child tables, polymorphism, denormalisation, naming, trees |
| `counts.py` | reconciles the "532 or 1,000 tables?" question per app |
| `ddl.py` | PostgreSQL DDL emitters (as-is and normalised, with out-of-scope stubs) |
| `run.py` | entry point |

## Status

- [x] Bench cloned and parsed — 997 DocTypes, 100% coverage verified
- [x] Full catalog of all apps and modules
- [x] Deep dive: Accounts, Selling, Buying, Stock, Subcontracting, Setup
- [x] Ledger anatomy documented (GL, AR/AP, stock ledger, bin, batch/serial)
- [x] Reference DDL generated and executed against PostgreSQL 15
- [x] Business logic documented — GL posting, stock valuation, stock↔GL bridge, AR/AP settlement,
      taxes/totals/pricing, lifecycle/fulfilment/returns, period close and opening balances
      (`docs/logic/01`–`08`)
- [x] Implementation spec written — invariant register, Phase 0-2 tables, posting algorithm
      (`docs/logic/08-our-implementation-spec.md`)
- [x] **Tranche A complete** — document lifecycle/approval/reversals/deletions, the fulfilment
      engine, advances + payment allocation, budgets/deferrals/cost-centre allocation, POS,
      banking + collections, inter-company + history rewriting, stock reservation/picking/warehouse,
      item/UOM/variants/batch/reorder (`docs/logic/09`–`17`)
- [x] **Finalised schema** — [`docs/design/FINAL-SCHEMA.md`](docs/design/FINAL-SCHEMA.md):
      tables, how data flows through them, business rules, and the invariant register
      (citations verified against erpnext@ceefd4a)
- [x] **Tranche E complete** — the platform we must build rather than inherit: metadata + runtime
      DDL, permissions/RLS, naming + identity + audit, hooks + regional overlay, jobs + scheduling +
      locking, migrations + patches, reporting (`docs/logic/18`–`24`), plus
      [`docs/logic/25-our-platform-spec.md`](docs/logic/25-our-platform-spec.md) — build/buy/drop
      per capability, the four-layer enforcement rule, and 10 requirements on the orchestration engine
- [x] **Scenario walkthroughs** — [`docs/scenarios/`](docs/scenarios/README.md): the flows traced
      end to end with worked numbers, every table write in order, ERPNext vs ours side by side —
      **S01** Sales Order → Delivery Note → Sales Invoice (partial delivery, partial billing,
      dispute, return), **S02** payments against invoices (exact, partial, multi-invoice,
      credit-note offset, advances, un-allocation, over-payment), **S03** Purchase Order →
      Receipt → Invoice (rejection, landed cost, return), **S04** warehouse transfer including
      in-transit, **S05** period close + opening balances, **S06** multi-currency invoice →
      payment → FX revaluation, **S07** make-to-order manufacturing with partial production, WIP,
      process loss, scrap and Standard Cost variance, **S08** supplier subcontracting, **S09**
      quality-gated receipt/production, and **S10** customer-owned subcontracting inward
- [x] **Trade / inventory / accounts closed out** (`docs/logic/26`–`32`) — Journal Entry + chart of
      accounts + dimensions, the remaining stock documents, tax determination, pricing
      determination, upstream trade + parties, batch processes + instruments + recurring, and stock
      configuration. **Accounts, Stock, Selling and Buying are at zero uncited DocTypes** —
      submittable and configuration alike; see [`docs/COVERAGE.md`](docs/COVERAGE.md) (generated)
      and the closure statement in
      [`docs/logic/32`](docs/logic/32-stock-configuration-and-remaining-masters.md) §5.
      **5,962 citations verified across `docs/logic` and `docs/scenarios`, 0 problems** (6,050
      including `docs/design`).
- [x] **Tranche B complete** (`docs/logic/33`–`40`, scenarios `S07`–`S10`) — manufacturing,
      supplier/customer-owned subcontracting, quality, coverage closure and the consolidated production
      specification. Final measured coverage: **Manufacturing 18/18**, **Subcontracting 4/4** and
      **Quality Management 8/8** parent controllers cited, with **0 submittable and 0 configuration
      gaps**; see [`docs/logic/40`](docs/logic/40-tranche-b-coverage-closure-and-our-production-spec.md).
- [x] **Tranche C complete** (`docs/logic/41`–`44`, scenario `S11`) — asset identity/acquisition and
      finance books, the depreciation engine (schedules, methods, shifts, revaluation), custody,
      maintenance, repair, split and disposal, and the consolidated asset specification. **Assets: 14/14
      parent controllers cited, 0 submittable and 0 configuration gaps.** Invariant register **A1–A26**;
      see [`docs/logic/44`](docs/logic/44-tranche-c-closure-and-our-asset-spec.md).
- [x] **Tranche F complete** (`docs/logic/45`–`49`, scenario `S12`) — localisation with **India GST**.
      India GST is **not in ERPNext** (removed in v14), so this tranche pins a third repository,
      `india-compliance@205c3de` (`17.0.0-dev`, ~49,000 LOC, **26 DocTypes**), read at controller depth:
      registration identity and status, settings, HSN/SAC, the five-component tax structure, place of supply
      and component determination, reverse charge, ineligible ITC, e-invoice/e-way bill as external state
      machines, GSTR-1/3B, purchase reconciliation and Bill of Entry. ERPNext's `@allow_regional` overlay and
      settings-toggled custom fields are **rejected** in favour of jurisdiction-as-data. Invariant register
      **G1–G29**; see [`docs/logic/49`](docs/logic/49-tranche-f-closure-and-our-localisation-spec.md).
- [x] ~~Tranche D~~ — CRM, projects, support: **out of scope** by decision
- [x] **Tranche G complete** (`docs/logic/50`–`57`, scenario `S13`) — security, tenancy and multi-entity.
      Every prior tranche asserted `company_id` + RLS + `FORCE RLS` and an authenticated tenant-context
      function across twenty-three schema sections; **none tested it, and none said where the context comes
      from**. Measured result: **there is no tenant isolation mechanism in the pinned tree** — the only
      use of Postgres's `current_setting()` in either repository is in one query-builder test — and **892** call sites switch the
      application-level check off (`ignore_permissions=True`). Worse than absent, the mechanism that exists
      **fails open**: an empty result from the scoping lookup means *unrestricted*. Covered: authentication
      and session identity, the permission model traced branch by branch, **tenant isolation under attack**
      with an executable per-table test matrix and a generated `rls_conformance` build gate, multi-company
      (group structure, inter-company crossings, transfer pricing), multi-currency (transaction / functional /
      presentation layering, revaluation vs translation), multi-location/branch/segment, and consolidation
      (eliminations, ownership weighting, minority interest, fiscal-calendar alignment). **84 defects**
      catalogued. Invariant register **T1–T30**, target tables in
      [`FINAL-SCHEMA` §29–§37](docs/design/FINAL-SCHEMA.md); see
      [`docs/logic/57`](docs/logic/57-tranche-g-closure-and-our-security-spec.md) and
      [`S13`](docs/scenarios/S13-cross-company-consolidation-and-isolation.md).
- [ ] Build — **application implementation has not started**. The investigation is complete: all planned
      tranches (A, B, C, E, F, G) are closed. What remains before building is three answers — **scale
      targets** (decides materialised vs computed balances), **audit retention** for the auth/access event
      streams, and **which jurisdictions besides India** — plus the two open localisation seams in
      [`docs/logic/49`](docs/logic/49-tranche-f-closure-and-our-localisation-spec.md) §7.2. The build order
      itself is fixed: [`docs/logic/57`](docs/logic/57-tranche-g-closure-and-our-security-spec.md) §8, whose
      **step 0** is the boundary, because retrofitting scope columns and an execution-context contract onto
      populated tables is a rewrite.
