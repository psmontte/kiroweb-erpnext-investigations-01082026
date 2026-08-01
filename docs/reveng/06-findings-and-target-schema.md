# Findings and the schema we should build

Conclusions from parsing all 532 ERPNext DocTypes (6,983 columns), with the accounting and
trade/inventory modules studied field by field.

---

## Part 1 — What ERPNext gets right (copy this)

1. **Every financial fact is a ledger row, never a mutable balance.** Balances are
   aggregates. `Bin` is a cache, not a truth.
2. **Draft / Submitted / Cancelled as a first-class lifecycle.** Only submitted documents
   post to ledgers; submitted documents are immutable. This is what makes the books
   defensible.
3. **Line-level provenance everywhere.** `voucher_detail_no` on ledger rows means every
   number can be traced to the exact invoice line that produced it. Non-negotiable.
4. **`stock_value_difference` on the stock ledger.** One column keeps inventory valuation and
   the general ledger reconciled. Any design that recomputes COGS separately in two places
   will drift.
5. **The document chain is data, not workflow config.** Quotation → Order → Receipt/Delivery
   → Invoice → Payment are linked by real columns, and fulfilment is tracked with roll-up
   quantities on the predecessor line (`delivered_qty`, `billed_amt`, `received_qty`, `per_*`).
   See `03-document-flows.md` — all of it derived from actual columns.
6. **Company as a hard boundary.** `company` appears on 156 tables. Multi-entity is designed
   in from row one, not added later.
7. **Buying mirrors Selling almost field for field.** `Purchase Order Item` (75 cols) vs
   `Sales Order Item` (82 cols) are the same shape. That symmetry is real and should be one
   abstraction in our code, two views for users.
8. **Parallel valuation books** (`Finance Book`) and **accounting dimensions** are the right
   concepts, even if the implementation is rough.

## Part 2 — What we should not copy

| ERPNext choice | Cost | Our replacement |
|---|---|---|
| `varchar(140)` business-key PK, FKs by name | renames cascade across ~2,000 link columns; wide indexes; no referential integrity | `bigint` identity PK; `doc_no varchar(140)` with `UNIQUE (company_id, doc_type, doc_no)` |
| **Zero** FK constraints in the database | integrity depends entirely on the app; orphans are normal in real installs | real FKs (1,590 of them generated in `schema/ddl/clean_02_constraints.sql`) |
| 42 child tables shared by multiple parents via `parenttype` | the direct cause of the no-FK decision | one child table per (parent, field), CASCADE delete |
| `Dynamic Link` polymorphism (78 columns) | unindexable joins, no constraints | `party` supertype table for Customer/Supplier/Employee; typed FK + audit `(source_table, source_id)` pair on ledger rows |
| Runtime DDL for accounting dimensions | migrations at business-config time | fixed dimension FKs + a dimension side table |
| Settings stored in `tabSingles` as key/value strings | untyped, unconstrained config | typed `company_settings` / `stock_settings` tables |
| Nested sets (`lft`/`rgt`) on 13 trees | every insert rewrites the tree | `parent_id` + recursive CTE (Postgres handles this well); closure table only if reporting demands it |
| In-place cancellation (`is_cancelled = 1`) | every query needs the filter; history is mutated | reversing entries only (ERPNext's own `enable_immutable_ledger` mode) |
| `Sales Invoice` with 143 columns, `Item` with 72 | unmaintainable; most columns are optional per business type | split header / totals / tax summary / shipping / e-invoicing extensions |
| 239 `fetch_from` copied columns in scope | silent drift between master and copy | snapshot only where legally required (rates, tax %, printed addresses); views otherwise |
| Amounts stored in 3–4 currency variants side by side | four columns can disagree | `amount` + `currency_id` + `exchange_rate`; base amounts as generated columns |
| `numeric(21,9)` for every money and quantity column | 9 decimals on money invites rounding disputes | money `numeric(19,4)` (or minor units `bigint`), quantity `numeric(21,9)`, rates `numeric(21,9)` |

---

## Part 3 — Proposed build order

Backend/DB only, each phase ends with a loadable schema plus posting logic and tests.

### Phase 0 — foundation
`company`, `fiscal_year`, `accounting_period`, `currency`, `exchange_rate`, `uom`,
`uom_conversion`, `party` (+ `customer`, `supplier`), `address`, `contact`, `tax_authority`,
`doc_sequence` (numbering), `app_user`, audit columns convention.

### Phase 1 — general ledger (the core engine)
`account` (tree, per company), `cost_center`, `dimension` + `dimension_value`,
`journal` (voucher header), `journal_line`, `gl_entry` (immutable, append-only),
`account_period_balance` (rollup).
Invariants enforced in DB where possible: balanced voucher via deferred constraint trigger,
posting date inside an open period, no update/delete on `gl_entry`.

### Phase 2 — items and inventory
`item`, `item_variant`, `item_uom`, `item_group` (tree), `warehouse` (tree),
`stock_move` (immutable event), `stock_valuation_state` (derived projection),
`stock_balance` (cache), `batch`, `serial`, `stock_move_batch`, `stock_move_serial`,
`valuation_method` per item/company.
This is where `05-ledger-anatomy.md` §3 matters most: event vs projection.

### Phase 3 — trade documents (one abstraction, two directions)
`trade_doc` header + `trade_doc_line` with a `direction` (sale/purchase) and `stage`
(quote/order/receipt/invoice) discriminator, or four concrete table pairs sharing a common
column contract. Plus `tax_template`, `tax_line`, `price_list`, `item_price`,
`payment_terms`, `payment_schedule`.
Fulfilment roll-ups (`ordered_qty`, `delivered_qty`, `billed_qty`) live on the line.

### Phase 4 — settlement
`payment`, `payment_allocation` (payment ↔ invoice ↔ amount, replacing
`against_voucher_*`), `ar_ap_entry` (the subledger), `advance`, `write_off`, ageing views.

### Phase 5 — subcontracting
`subcontract_order`, `supplied_item`, `subcontract_receipt`, supplier-warehouse ownership,
raw-material consumption and cost roll-up into the finished item.

---

## Part 4 — Open decisions I need from you

1. **Money representation** — `numeric(19,4)` or integer minor units? Affects every table.
2. **Multi-tenancy** — one schema per company, `company_id` on every row, or Postgres RLS?
3. **Trade documents** — one polymorphic `trade_doc` table, or eight concrete tables
   (quotation/order/delivery/invoice × sale/purchase)? Concrete is simpler to constrain,
   polymorphic is far less code.
4. **Immutability enforcement** — DB triggers/rules blocking UPDATE on ledgers, or
   application-only discipline?
5. **Stack for the business logic layer** (Phase 1 onward) — you said backend/DB for now;
   I need the target language and migration tool before writing posting code.
6. **Scope of "our own"** — a clean-room design informed by ERPNext (recommended, no
   licence entanglement), or an intentionally compatible schema so ERPNext data can be
   migrated in?

---

## Artifacts produced

| Path | What it is |
|---|---|
| `docs/reveng/00-overview.md` | module/fieldtype/reference statistics, framework conventions |
| `docs/reveng/01-all-tables.md` | all 532 DocTypes with physical table, kind, counts, naming |
| `docs/reveng/02-core-erd.md` | Mermaid ER diagrams: masters, O2C, P2P, inventory, ledgers |
| `docs/reveng/03-document-flows.md` | auto-derived document chain + fulfilment roll-up columns |
| `docs/reveng/04-patterns.md` | shared child tables, polymorphism, denormalisation, naming, trees |
| `docs/reveng/05-ledger-anatomy.md` | field-by-field semantics of the four ledger engines |
| `docs/reveng/modules/*.md` | full column-level reference for Accounts, Selling, Buying, Stock, Subcontracting, Setup |
| `schema/erpnext_doctypes.json` | complete machine-readable schema dump |
| `schema/catalog_tables.csv` · `catalog_columns.csv` · `catalog_relations.csv` | spreadsheet-friendly catalog (6,983 columns, all relations) |
| `schema/ddl/*_asis.sql` | ERPNext physical layout as PostgreSQL DDL — **verified: 338 tables created, 0 errors** |
| `schema/ddl/clean_01_tables.sql` + `clean_02_constraints.sql` | normalised reference DDL — **verified: 388 tables, 1,590 FKs, 1,111 indexes, 0 errors** |
| `tools/reveng/` | the parser toolkit, re-runnable against any Frappe app |

Regenerate everything with:

```bash
python3 tools/reveng/run.py --app /path/to/erpnext/erpnext --out /path/to/erp
```
