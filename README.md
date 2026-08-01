# erp — our own ERP (backend / database)

Stage 1: reverse engineer ERPNext's data model, then design our own.

```
docs/reveng/     study output — start at docs/reveng/README.md
schema/          machine-readable catalog (JSON + CSV) and generated DDL
schema/ddl/      *_asis.sql  = ERPNext layout as PostgreSQL (verified: 338 tables, 0 errors)
                 clean_*.sql = normalised reference schema (verified: 388 tables, 1590 FKs)
tools/reveng/    the parser toolkit — re-runnable against any Frappe app
```

## Regenerate everything

```bash
python3 tools/reveng/run.py --app /path/to/erpnext/erpnext --out .
```

No third-party dependencies — standard library only.

## Verify the DDL actually loads

```bash
initdb -D pgdata && postgres -D pgdata -k pgdata -p 5433 &
createdb -h pgdata -p 5433 clean
psql -h pgdata -p 5433 -d clean -f schema/ddl/clean_01_tables.sql
psql -h pgdata -p 5433 -d clean -f schema/ddl/clean_02_constraints.sql
```

## Toolkit layout

| File | Responsibility |
|---|---|
| `frappe_schema.py` | DocType/Field model, fieldtype → SQL type maps (transcribed from frappe core), registry + relationship queries |
| `catalog.py` | JSON + CSV catalog of every table, column and relation |
| `render.py` | overview, full table catalog, per-module column-level reference |
| `erd.py` | Mermaid ER and dependency diagrams |
| `flows.py` | auto-derives the document chain from real Link columns |
| `patterns.py` | cross-cutting patterns: shared child tables, polymorphism, denormalisation, naming, trees |
| `ddl.py` | PostgreSQL DDL emitters (as-is and normalised) |
| `run.py` | entry point |

## Status

- [x] ERPNext cloned and parsed (532 DocTypes, 6,983 columns)
- [x] Full catalog of all modules
- [x] Deep dive: Accounts, Selling, Buying, Stock, Subcontracting, Setup
- [x] Ledger anatomy documented (GL, AR/AP, stock ledger, bin, batch/serial)
- [x] Reference DDL generated and executed against PostgreSQL 15
- [ ] Our own schema — blocked on the decisions in `docs/reveng/06-findings-and-target-schema.md` §4
