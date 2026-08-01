# How many tables? Reconciling the count

Counting only the `erpnext` app gives 532 DocTypes. A working ERPNext site is
`frappe` + `erpnext` + the apps that ship with it, and that is where the ~1,000
figure comes from. Both numbers are correct; they answer different questions.

## Per app

| App | Role | DocTypes | Physical tables | Child tables | Singles (no table) | Virtual (no table) | Columns |
|---|---|--:|--:|--:|--:|--:|--:|
| `erpnext` | accounting, trade, inventory, manufacturing, assets, projects, support | 532 | 496 | 251 | 31 | 6 | 6983 |
| `frappe` | the framework itself: users, roles, files, comments, workflow, print, email, Address/Contact/Currency masters | 287 | 245 | 103 | 31 | 13 | 2403 |
| `hrms` | HR and payroll (separate app since v14) | 159 | 153 | 54 | 6 | 1 | 1463 |
| `payments` | payment gateway integrations | 10 | 6 | 0 | 4 | 0 | 55 |
| `webshop` | storefront (split out of erpnext in v15) | 9 | 8 | 5 | 1 | 0 | 91 |
| **TOTAL** | | **997** | **908** | **413** | **73** | **20** | **10995** |

## So which number is 'the' number?

- **997 DocTypes** are defined across the standard app set. This is the ~1,000 count.
- **908 of them get a physical `tab<Name>` table**. The rest are:
  - **73 singles** — stored as rows in the shared `tabSingles` key/value table,
  - **20 virtual** — backed by code or an external service, no storage at all
    (4 DocTypes are both single and virtual, hence 997 - 908 = 89, not 93).
- **413 of the 908 tables are child tables** — they only ever hold line items
  belonging to a parent document. They are real tables, but they are not entities.
- So the *entity* count is roughly **495**, and that is the number that
  matters when we design our own model.

Add the framework tables that are not DocTypes at all:

| Table | Purpose |
|---|---|
| `tabSingles` | key/value store holding every `issingle` DocType's fields |
| `tabSeries` | naming-series counters (`current` per prefix) |
| `tabDefaultValue` | per-user / per-parent default values |
| `tabSessions` | active sessions |
| `__Auth` | password and secret hashes, kept out of the doctype tables |
| `__global_search` | full-text search index across doctypes |
| `__UserSettings` | per-user list view / filter state |

A freshly installed bench with these five apps therefore lands at roughly
**915 tables**, before any custom DocType, and every
`Custom Field` a user adds widens an existing table rather than creating a new one.

## Shape of the whole thing

| Metric | Count |
|---|--:|
| DocTypes | 997 |
| Physical tables | 908 |
| Entity tables (excluding child tables) | 495 |
| Child (line-item) tables | 413 |
| Submittable documents (draft/submit/cancel lifecycle) | 138 |
| Tree masters (nested set) | 15 |
| Total columns defined | 10995 |
| Link (FK-by-name) columns | 3062 |
| Child-table relations | 530 |
| Polymorphic (Dynamic Link) columns | 122 |

## What this means for our build

We are not competing with 1,000 tables. Stripping out HR, payroll, webshop, the
framework's own plumbing (users, files, comments, workflow, print formats, email),
and the modules outside our scope, the accounting + trade + inventory core we studied
is what actually matters — and even that is only worth building in the phases listed in
`06-findings-and-target-schema.md`. Phase 0 to 2 is under 30 tables and covers the
general ledger and inventory valuation, which is the part that is genuinely hard.
