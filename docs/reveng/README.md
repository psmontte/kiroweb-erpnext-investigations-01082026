# ERPNext reverse engineering — reading order

Source: `frappe/erpnext` (cloned at `/projects/sandbox/erpnext`), 532 DocTypes, 6,983 columns.
Everything here is generated or verified from the actual DocType JSON definitions and
controller code — not from documentation.

| Read | File | Why |
|---|---|---|
| 1 | [00-overview.md](00-overview.md) | the shape of the whole system, framework conventions, type mapping, most-referenced entities |
| 2 | [01-all-tables.md](01-all-tables.md) | every table, grouped by module — the index you will keep coming back to |
| 3 | [02-core-erd.md](02-core-erd.md) | visual: masters, order-to-cash, procure-to-pay, inventory, ledgers |
| 4 | [03-document-flows.md](03-document-flows.md) | how documents feed each other, and the roll-up columns that make status derivable |
| 5 | [04-patterns.md](04-patterns.md) | the cross-cutting tricks (shared child tables, polymorphism, denormalisation, naming, trees) |
| 6 | [05-ledger-anatomy.md](05-ledger-anatomy.md) | **the important one** — the four ledger engines, field by field, with invariants |
| 7 | [06-findings-and-target-schema.md](06-findings-and-target-schema.md) | what to copy, what to reject, proposed build order, open decisions |

Column-level reference per module:

- [modules/accounts.md](modules/accounts.md) (191 doctypes) · [erd](modules/accounts-erd.md)
- [modules/stock.md](modules/stock.md) (77) · [erd](modules/stock-erd.md)
- [modules/selling.md](modules/selling.md) (20) · [erd](modules/selling-erd.md)
- [modules/buying.md](modules/buying.md) (19) · [erd](modules/buying-erd.md)
- [modules/subcontracting.md](modules/subcontracting.md) (13) · [erd](modules/subcontracting-erd.md)
- [modules/setup.md](modules/setup.md) (40 — shared masters: Company, UOM, Item Group, Territory …) · [erd](modules/setup-erd.md)

Machine-readable: `../../schema/erpnext_doctypes.json`, `../../schema/catalog_*.csv`,
DDL in `../../schema/ddl/`.
