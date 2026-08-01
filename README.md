# erp — our own ERP (backend / database)

**Investigation mode.** We are documenting the Frappe/ERPNext data model and business logic first;
application code starts only once the investigation is complete. Coverage map, remaining tranches and
open questions: [docs/INVESTIGATION-PLAN.md](docs/INVESTIGATION-PLAN.md).

Parsed the full standard app set — `frappe`, `erpnext`, `payments`, `hrms`, `webshop`:
**997 DocTypes → 908 physical tables → 10,995 columns.** The accounting and trade/inventory
modules of `erpnext` are documented at column level.

```
docs/reveng/     schema study — start at docs/reveng/README.md
docs/logic/      business-logic study — start at docs/logic/README.md
docs/design/     FINAL-SCHEMA.md — the finalised tables, data flow, business rules,
                 lifecycle state machine, fulfilment views, settlement model, invariants
schema/          machine-readable catalog (JSON + CSV) and generated DDL
schema/ddl/      *_asis.sql  = ERPNext physical layout as PostgreSQL
                 clean_*.sql = normalised reference schema
tools/reveng/    the parser toolkit — re-runnable against any Frappe app
tools/verify_ddl.sh  loads the generated DDL into a throwaway PostgreSQL and reports errors
tools/verify_refs.py checks every source citation in docs/logic against the source tree
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
      (357 source citations across `docs/logic/` verified against erpnext@ceefd4a)
- [x] **Tranche E complete** — the platform we must build rather than inherit: metadata + runtime
      DDL, permissions/RLS, naming + identity + audit, hooks + regional overlay, jobs + scheduling +
      locking, migrations + patches, reporting (`docs/logic/18`–`24`), plus
      [`docs/logic/25-our-platform-spec.md`](docs/logic/25-our-platform-spec.md) — build/buy/drop
      per capability, the four-layer enforcement rule, and 10 requirements on the orchestration engine
- [ ] Tranches B/C/D — manufacturing, assets, projects/quality/CRM (**scope to be confirmed** —
      see open question 1 in the investigation plan)
- [ ] Build — deferred by decision until the investigation is complete
