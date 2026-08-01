# ERPNext schema reverse engineering — overview

Generated from the ERPNext DocType JSON definitions. Every non-single DocType maps to
exactly one physical table named `tab<DocType Name>`; child tables are the physical
storage for repeating line items and are always referenced from a parent through a
`Table` field.

**Total DocTypes parsed: 532** across 21 modules.

## Framework conventions you must decide to keep or drop

| Convention | How ERPNext does it | Notes for our build |
|---|---|---|
| Primary key | `name varchar(140)` — a *business* key (naming series like `ACC-SINV-.YYYY.-.#####`), not an integer | Human-readable but expensive as FK; consider surrogate `bigint`/`uuid` PK + separate `doc_no` |
| Foreign keys | Plain `varchar(140)` columns, **no DB-level FK constraints**; integrity enforced in Python | We can enforce real FKs |
| Lifecycle | `docstatus tinyint`: 0 Draft, 1 Submitted, 2 Cancelled. Submitted rows are immutable | Core accounting invariant — keep the concept |
| Line items | Separate child table per parent field with `parent`, `parenttype`, `parentfield`, `idx` | `parenttype` makes a child table shareable across parents; real FKs need one table per parent |
| Polymorphism | `Dynamic Link`: value column + a sibling column naming the target DocType (e.g. `party_type`/`party`) | Blocks FK constraints; consider explicit nullable FKs or a party supertype table |
| Denormalisation | `fetch_from` copies values from linked docs into the row at save time | Heavy read-optimisation; decide per field vs. views |
| Settings | `issingle` DocTypes are stored as key/value rows in `tabSingles`, not their own table | Prefer a real typed settings table |
| Hierarchies | `is_tree` uses nested sets (`lft`, `rgt`, `old_parent`) | Alternative: `ltree`/recursive CTE with `parent_id` |
| Audit | `owner`, `creation`, `modified`, `modified_by` on every table + a `tabVersion` diff log | Keep; consider proper temporal tables |

## Standard columns present on every table

| Column | Type (Postgres) | Meaning |
|---|---|---|
| `name` | `varchar(140)` PK | business identifier / naming-series value |
| `creation` | `timestamp` | insert time |
| `modified` | `timestamp` | last update time (used for optimistic locking) |
| `modified_by` | `varchar(140)` | user id |
| `owner` | `varchar(140)` | creating user id |
| `docstatus` | `smallint` | 0 draft / 1 submitted / 2 cancelled |
| `idx` | `integer` | row order (position inside parent for child tables) |

Child tables additionally carry: `parent`, `parentfield`, `parenttype`.

## Modules

| Module | DocTypes | Masters | Trees | Transactions | Child tables | Singles | Columns |
|---|--:|--:|--:|--:|--:|--:|--:|
| Accounts | 191 | 47 | 2 | 31 | 99 | 12 | 2323 |
| Assets | 26 | 5 | 1 | 8 | 12 | 0 | 270 |
| Bulk Transaction | 2 | 2 | 0 | 0 | 0 | 0 | 12 |
| Buying | 19 | 5 | 0 | 4 | 9 | 1 | 489 |
| CRM | 28 | 12 | 0 | 1 | 13 | 2 | 219 |
| Communication | 2 | 1 | 0 | 0 | 1 | 0 | 9 |
| EDI | 2 | 2 | 0 | 0 | 0 | 0 | 14 |
| ERPNext Integrations | 1 | 0 | 0 | 0 | 0 | 1 | 6 |
| Maintenance | 5 | 0 | 0 | 2 | 3 | 0 | 64 |
| Manufacturing | 48 | 8 | 0 | 8 | 30 | 2 | 628 |
| Portal | 2 | 0 | 0 | 0 | 2 | 0 | 2 |
| Projects | 15 | 6 | 1 | 2 | 5 | 1 | 166 |
| Quality Management | 16 | 7 | 1 | 0 | 8 | 0 | 61 |
| Regional | 5 | 4 | 0 | 0 | 1 | 0 | 21 |
| Selling | 20 | 5 | 0 | 5 | 8 | 2 | 494 |
| Setup | 40 | 17 | 8 | 1 | 12 | 2 | 405 |
| Stock | 77 | 22 | 1 | 17 | 32 | 5 | 1358 |
| Subcontracting | 13 | 1 | 0 | 3 | 9 | 0 | 280 |
| Support | 11 | 5 | 0 | 0 | 5 | 1 | 114 |
| Telephony | 5 | 3 | 0 | 1 | 1 | 0 | 30 |
| Utilities | 4 | 1 | 0 | 0 | 1 | 2 | 18 |
| **TOTAL** | **532** | | | | | | **6983** |

## Fieldtype usage (drives our type mapping)

| Fieldtype | Count | Postgres type |
|---|--:|---|
| Link | 2183 | `varchar(140)` |
| Section Break | 1467 | *layout only — no column* |
| Column Break | 1339 | *layout only — no column* |
| Check | 891 | `smallint` |
| Data | 875 | `varchar(140)` |
| Currency | 738 | `numeric(21,9)` |
| Float | 568 | `numeric(21,9)` |
| Select | 461 | `varchar(140)` |
| Date | 325 | `date` |
| Table | 299 | *child table relation — no column* |
| Tab Break | 215 | *layout only — no column* |
| Int | 169 | `integer` |
| Small Text | 164 | `text` |
| Text Editor | 151 | `text` |
| HTML | 101 | *layout only — no column* |
| Dynamic Link | 78 | `varchar(140)` |
| Button | 77 | *layout only — no column* |
| Percent | 70 | `numeric(21,9)` |
| Read Only | 61 | `varchar(140)` |
| Datetime | 59 | `timestamp` |
| Text | 56 | `text` |
| Time | 46 | `time(6)` |
| Attach | 30 | `text` |
| Code | 26 | `text` |
| Table MultiSelect | 24 | *child table relation — no column* |
| Long Text | 20 | `text` |
| Attach Image | 19 | `text` |
| Image | 18 | *layout only — no column* |
| Duration | 10 | `numeric(21,9)` |
| Heading | 7 | *layout only — no column* |
| JSON | 4 | `jsonb` |
| Autocomplete | 4 | `varchar(140)` |
| Color | 3 | `varchar(140)` |
| Password | 2 | `text` |
| Geolocation | 1 | `text` |
| Signature | 1 | `text` |
| Barcode | 1 | `text` |

## Most referenced entities (inbound Link count) — the true core of the model

| Target DocType | Inbound links | In ERPNext app |
|---|--:|---|
| `Account` | 165 | yes |
| `Company` | 156 | yes |
| `Warehouse` | 131 | yes |
| `Item` | 114 | yes |
| `UOM` | 110 | yes |
| `Currency` | 80 | no (frappe core) |
| `Cost Center` | 76 | yes |
| `DocType` | 75 | no (frappe core) |
| `Project` | 59 | yes |
| `Address` | 59 | no (frappe core) |
| `Customer` | 43 | yes |
| `User` | 35 | no (frappe core) |
| `Supplier` | 33 | yes |
| `Contact` | 33 | no (frappe core) |
| `Item Group` | 30 | yes |
| `BOM` | 27 | yes |
| `Letter Head` | 24 | no (frappe core) |
| `Price List` | 24 | yes |
| `Customer Group` | 22 | yes |
| `Serial and Batch Bundle` | 22 | yes |
| `Territory` | 21 | yes |
| `Batch` | 21 | yes |
| `Sales Order` | 21 | yes |
| `Employee` | 19 | yes |
| `Asset` | 18 | yes |
| `Role` | 17 | no (frappe core) |
| `Print Heading` | 17 | no (frappe core) |
| `Brand` | 17 | yes |
| `Tax Category` | 16 | yes |
| `Terms and Conditions` | 16 | yes |
| `Material Request` | 16 | yes |
| `Finance Book` | 15 | yes |
| `Bank Account` | 15 | yes |
| `Mode of Payment` | 14 | yes |
| `Sales Invoice` | 14 | yes |
| `Auto Repeat` | 12 | no (frappe core) |
| `Payment Terms Template` | 12 | yes |
| `Purchase Order` | 12 | yes |
| `Operation` | 12 | yes |
| `UTM Campaign` | 11 | no (frappe core) |

## Widest tables (column count) — candidates for normalisation in our design

| DocType | Module | Kind | Columns |
|---|---|---|--:|
| `Sales Invoice` | Accounts | transaction | 143 |
| `Purchase Invoice` | Accounts | transaction | 125 |
| `POS Invoice` | Accounts | transaction | 115 |
| `Sales Order` | Selling | transaction | 104 |
| `Delivery Note` | Stock | transaction | 102 |
| `Company` | Setup | tree-master | 100 |
| `Purchase Order` | Buying | transaction | 97 |
| `Purchase Receipt` | Stock | transaction | 90 |
| `Purchase Receipt Item` | Stock | child | 89 |
| `Sales Invoice Item` | Accounts | child | 84 |
| `Purchase Invoice Item` | Accounts | child | 82 |
| `Sales Order Item` | Selling | child | 82 |
| `Quotation` | Selling | transaction | 77 |
| `Purchase Order Item` | Buying | child | 75 |
| `Delivery Note Item` | Stock | child | 74 |
| `Item` | Stock | master | 72 |
| `POS Invoice Item` | Accounts | child | 71 |
| `Supplier Quotation` | Buying | transaction | 69 |
| `Employee` | Setup | tree-master | 67 |
| `Accounts Settings` | Accounts | single | 64 |
| `Payment Entry` | Accounts | transaction | 63 |
| `Pricing Rule` | Accounts | master | 59 |
| `Work Order` | Manufacturing | transaction | 55 |
| `Quotation Item` | Selling | child | 55 |
| `Stock Entry` | Stock | transaction | 55 |
| `Stock Entry Detail` | Stock | child | 55 |
| `BOM` | Manufacturing | transaction | 53 |
| `Asset` | Assets | transaction | 51 |
| `Job Card` | Manufacturing | transaction | 50 |
| `Supplier Quotation Item` | Buying | child | 49 |
