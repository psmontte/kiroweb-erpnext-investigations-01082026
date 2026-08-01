# ERPNext schema reverse engineering — overview

Generated from the ERPNext DocType JSON definitions. Every non-single DocType maps to
exactly one physical table named `tab<DocType Name>`; child tables are the physical
storage for repeating line items and are always referenced from a parent through a
`Table` field.

**Total DocTypes parsed: 997** across 37 modules.

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

| Module | DocTypes | Masters | Trees | Transactions | Child tables | Singles | Columns |
|---|--:|--:|--:|--:|--:|--:|--:|
| App | Module | DocTypes | Masters | Trees | Transactions | Child tables | Singles | Columns |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| erpnext | Accounts | 191 | 47 | 2 | 31 | 99 | 12 | 2323 |
| erpnext | Assets | 26 | 5 | 1 | 8 | 12 | 0 | 270 |
| erpnext | Bulk Transaction | 2 | 2 | 0 | 0 | 0 | 0 | 12 |
| erpnext | Buying | 19 | 5 | 0 | 4 | 9 | 1 | 489 |
| erpnext | CRM | 28 | 12 | 0 | 1 | 13 | 2 | 219 |
| erpnext | Communication | 2 | 1 | 0 | 0 | 1 | 0 | 9 |
| erpnext | EDI | 2 | 2 | 0 | 0 | 0 | 0 | 14 |
| erpnext | ERPNext Integrations | 1 | 0 | 0 | 0 | 0 | 1 | 6 |
| erpnext | Maintenance | 5 | 0 | 0 | 2 | 3 | 0 | 64 |
| erpnext | Manufacturing | 48 | 8 | 0 | 8 | 30 | 2 | 628 |
| erpnext | Portal | 2 | 0 | 0 | 0 | 2 | 0 | 2 |
| erpnext | Projects | 15 | 6 | 1 | 2 | 5 | 1 | 166 |
| erpnext | Quality Management | 16 | 7 | 1 | 0 | 8 | 0 | 61 |
| erpnext | Regional | 5 | 4 | 0 | 0 | 1 | 0 | 21 |
| erpnext | Selling | 20 | 5 | 0 | 5 | 8 | 2 | 494 |
| erpnext | Setup | 40 | 17 | 8 | 1 | 12 | 2 | 405 |
| erpnext | Stock | 77 | 22 | 1 | 17 | 32 | 5 | 1358 |
| erpnext | Subcontracting | 13 | 1 | 0 | 3 | 9 | 0 | 280 |
| erpnext | Support | 11 | 5 | 0 | 0 | 5 | 1 | 114 |
| erpnext | Telephony | 5 | 3 | 0 | 1 | 1 | 0 | 30 |
| erpnext | Utilities | 4 | 1 | 0 | 0 | 1 | 2 | 18 |
| frappe | Automation | 9 | 5 | 0 | 0 | 4 | 0 | 49 |
| frappe | Contacts | 7 | 5 | 0 | 0 | 2 | 0 | 47 |
| frappe | Core | 108 | 52 | 0 | 1 | 42 | 13 | 875 |
| frappe | Custom | 5 | 3 | 0 | 0 | 1 | 1 | 171 |
| frappe | Desk | 59 | 29 | 0 | 0 | 25 | 5 | 433 |
| frappe | Email | 17 | 13 | 0 | 0 | 4 | 0 | 195 |
| frappe | Geo | 2 | 2 | 0 | 0 | 0 | 0 | 13 |
| frappe | Integrations | 24 | 12 | 0 | 0 | 6 | 6 | 195 |
| frappe | Printing | 8 | 7 | 0 | 0 | 0 | 1 | 91 |
| frappe | Website | 39 | 19 | 0 | 0 | 15 | 5 | 289 |
| frappe | Workflow | 9 | 5 | 0 | 0 | 4 | 0 | 45 |
| hrms | HR | 116 | 39 | 1 | 36 | 36 | 4 | 1021 |
| hrms | Payroll | 43 | 6 | 0 | 17 | 18 | 2 | 442 |
| payments | Payment Gateways | 9 | 5 | 0 | 0 | 0 | 4 | 52 |
| payments | Payments | 1 | 1 | 0 | 0 | 0 | 0 | 3 |
| webshop | Webshop | 9 | 3 | 0 | 0 | 5 | 1 | 91 |
| | **TOTAL** | **997** | | | | | | **10995** |

## Fieldtype usage (drives our type mapping)

| Fieldtype | Count | Postgres type |
|---|--:|---|
| Link | 3062 | `varchar(140)` |
| Section Break | 2131 | *layout only — no column* |
| Column Break | 1867 | *layout only — no column* |
| Check | 1730 | `smallint` |
| Data | 1621 | `varchar(140)` |
| Currency | 886 | `numeric(21,9)` |
| Select | 812 | `varchar(140)` |
| Float | 674 | `numeric(21,9)` |
| Table | 491 | *child table relation — no column* |
| Date | 460 | `date` |
| Tab Break | 335 | *layout only — no column* |
| Int | 324 | `integer` |
| Small Text | 283 | `text` |
| Text Editor | 196 | `text` |
| HTML | 185 | *layout only — no column* |
| Code | 184 | `text` |
| Dynamic Link | 122 | `varchar(140)` |
| Datetime | 118 | `timestamp` |
| Button | 113 | *layout only — no column* |
| Text | 105 | `text` |
| Percent | 81 | `numeric(21,9)` |
| Read Only | 81 | `varchar(140)` |
| Time | 52 | `time(6)` |
| Attach | 44 | `text` |
| Attach Image | 42 | `text` |
| Table MultiSelect | 39 | *child table relation — no column* |
| Password | 33 | `text` |
| Long Text | 33 | `text` |
| Image | 20 | *layout only — no column* |
| Color | 17 | `varchar(140)` |
| Duration | 15 | `numeric(21,9)` |
| HTML Editor | 13 | `text` |
| JSON | 12 | `jsonb` |
| Autocomplete | 12 | `varchar(140)` |
| Rating | 9 | `numeric(3,2)` |
| Heading | 7 | *layout only — no column* |
| Icon | 6 | `varchar(140)` |
| Markdown Editor | 5 | `text` |
| Geolocation | 3 | `text` |
| Signature | 1 | `text` |
| Barcode | 1 | `text` |

## Most referenced entities (inbound Link count) — the true core of the model

| Target DocType | Inbound links | Owned by (app/module) |
|---|--:|---|
| `Company` | 218 | erpnext/Setup |
| `Account` | 187 | erpnext/Accounts |
| `DocType` | 174 | frappe/Core |
| `Warehouse` | 133 | erpnext/Stock |
| `Item` | 118 | erpnext/Stock |
| `UOM` | 111 | erpnext/Setup |
| `Currency` | 106 | frappe/Geo |
| `User` | 93 | frappe/Core |
| `Cost Center` | 84 | erpnext/Accounts |
| `Employee` | 76 | erpnext/Setup |
| `Project` | 65 | erpnext/Projects |
| `Address` | 60 | frappe/Contacts |
| `Department` | 58 | erpnext/Setup |
| `Customer` | 44 | erpnext/Selling |
| `Role` | 36 | frappe/Core |
| `Supplier` | 36 | erpnext/Buying |
| `Contact` | 33 | frappe/Contacts |
| `Item Group` | 32 | erpnext/Setup |
| `Designation` | 31 | erpnext/Setup |
| `Letter Head` | 29 | frappe/Printing |
| `Module Def` | 27 | frappe/Core |
| `BOM` | 27 | erpnext/Manufacturing |
| `Price List` | 25 | erpnext/Stock |
| `Customer Group` | 23 | erpnext/Setup |
| `Serial and Batch Bundle` | 22 | erpnext/Stock |
| `Territory` | 21 | erpnext/Setup |
| `Batch` | 21 | erpnext/Stock |
| `Sales Order` | 21 | erpnext/Selling |
| `Email Template` | 19 | frappe/Email |
| `Mode of Payment` | 18 | erpnext/Accounts |
| `Print Heading` | 18 | frappe/Printing |
| `Asset` | 18 | erpnext/Assets |
| `Brand` | 18 | erpnext/Setup |
| `Terms and Conditions` | 17 | erpnext/Setup |
| `Bank Account` | 16 | erpnext/Accounts |
| `Language` | 16 | frappe/Core |
| `Tax Category` | 16 | erpnext/Accounts |
| `Material Request` | 16 | erpnext/Stock |
| `Country` | 16 | frappe/Geo |
| `Finance Book` | 15 | erpnext/Accounts |

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
| `System Settings` | Core | single | 79 |
| `Quotation` | Selling | transaction | 77 |
| `Purchase Order Item` | Buying | child | 75 |
| `Delivery Note Item` | Stock | child | 74 |
| `Item` | Stock | master | 72 |
| `POS Invoice Item` | Accounts | child | 71 |
| `Supplier Quotation` | Buying | transaction | 69 |
| `Employee` | Setup | tree-master | 67 |
| `User` | Core | master | 67 |
| `DocField` | Core | child | 66 |
| `DocType` | Core | master | 66 |
| `Accounts Settings` | Accounts | single | 64 |
| `Payment Entry` | Accounts | transaction | 63 |
| `Salary Slip` | Payroll | transaction | 62 |
| `Email Account` | Email | master | 60 |
| `Pricing Rule` | Accounts | master | 59 |
| `Custom Field` | Custom | master | 58 |
| `Customize Form Field` | Custom | child | 58 |
