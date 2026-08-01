# Ledger anatomy — the four engines that actually hold the truth

Everything else in ERPNext is data entry. Four append-style tables carry the state that
reports and balances are computed from. If we get these right, the rest of our ERP is
CRUD plus validation.

| Engine | Table | Answers |
|---|---|---|
| General ledger | `GL Entry` | what is the balance of any account, any dimension, any date |
| Receivable/payable subledger | `Payment Ledger Entry` | what does each party owe us / do we owe them, per invoice |
| Stock ledger | `Stock Ledger Entry` | how much stock exists where, and what is it worth |
| Stock balance cache | `Bin` | fast current quantity per item+warehouse (derived, not authoritative) |

Traceability adds `Serial and Batch Bundle` + `Serial and Batch Entry`.

---

## 1. `GL Entry` — double-entry general ledger

31 columns, `is_submittable`, naming `ACC-GLE-.YYYY.-.#####`, indexed on
`account`, `posting_date`, `voucher_no`, `party`, `against_voucher`, `company`, `is_cancelled`.

### Column groups and what they are for

**When**
- `posting_date` — the accounting date. This, not `creation`, drives every report.
- `transaction_date` — the commercial date of the source document, informational.
- `fiscal_year` — denormalised period bucket; also the guard for closed-period checks.
- `due_date` — copied from the invoice, used for ageing of receivables.

**Where (the account and the party)**
- `account` → `Account`. The only mandatory dimension.
- `account_currency` — the account's own currency.
- `party_type` + `party` — polymorphic party (`Customer`, `Supplier`, `Employee`, …).
  Present only on receivable/payable rows.
- `against` — free-text list of the counter-accounts of the same voucher. Pure display
  convenience; **not** a reliable relation. Drop it in our design.

**Provenance (why this row exists)**
- `voucher_type` + `voucher_no` — polymorphic pointer to the source document.
- `voucher_detail_no` — the specific child row (invoice line) that produced this posting.
  This is the join key used when a document is partially cancelled or reposted.
- `against_voucher_type` + `against_voucher` — the document this row settles. On a payment
  row it points at the invoice. **This single column pair is how outstanding amounts are
  computed** (sum of debits minus credits grouped by `against_voucher`).

**Amounts** — the same value stored in up to four currencies:
- `debit` / `credit` — in company base currency. Exactly one of the pair is non-zero.
- `debit_in_account_currency` / `credit_in_account_currency`
- `debit_in_transaction_currency` / `credit_in_transaction_currency`
- `debit_in_reporting_currency` / `credit_in_reporting_currency`
- `transaction_exchange_rate`, `reporting_currency_exchange_rate`

**Dimensions** — `cost_center`, `project`, `finance_book`, `company`, plus any user-defined
dimension injected as an extra column by the `Accounting Dimension` doctype (see below).

**Flags** — `is_opening`, `is_advance`, `is_cancelled`, `to_rename`, `remarks`.

### Invariants the code enforces (not the database)
1. Per voucher: `sum(debit) == sum(credit)` in base currency.
2. `posting_date` must fall inside an open `Fiscal Year` and outside any closed
   `Accounting Period` / company freeze date.
3. A row is never updated once submitted, with one exception: `is_cancelled`.
4. Rows are never created directly by a user; only by a submitting voucher.

### Cancellation — two different behaviours, both present in the code
Verified in `erpnext/accounts/general_ledger.py::make_reverse_gl_entries`:

- **Immutable ledger enabled** (`Accounts Settings.enable_immutable_ledger`): the original
  rows keep `is_cancelled = 0` and a *reversing set* of rows is inserted with debit and
  credit swapped, dated on the cancellation date.
- **Immutable ledger disabled** (legacy): the original rows are updated in place to
  `is_cancelled = 1` and excluded from every report by a `where is_cancelled = 0` filter.

**For our schema:** implement only the immutable variant. Reversal is a new row, never an
update. That removes `is_cancelled` from every query and makes the ledger genuinely
append-only, which is also what auditors expect.

### The accounting-dimension escape hatch
`Accounting Dimension` is a *master that adds columns*: creating a dimension row runs a
schema migration that adds a column of that name to `GL Entry`, `Budget`, and every
transaction table. `Allowed Dimension` / `Accounting Dimension Detail` hold the per-company
defaults and restrictions.

**For our schema:** never migrate DDL at runtime. Either
(a) a fixed set of dimension FK columns (`cost_center_id`, `project_id`, `department_id`, …)
plus a `gl_entry_dimension(gl_entry_id, dimension_id, value_id)` side table for the rest, or
(b) a `jsonb dimensions` column with expression indexes. Option (a) keeps reporting SQL sane.

---

## 2. `Payment Ledger Entry` — the AR/AP subledger

20 columns, submittable, no naming series (`name` set by controller), heavily indexed.

This table exists because computing "what is still unpaid" from `GL Entry` alone requires
scanning the whole ledger. Every receivable/payable posting is mirrored here with:

- `account_type` — enum `Receivable` | `Payable`. The subledger only tracks these two.
- `account`, `party_type`, `party`, `company`, `cost_center`, `project`, `finance_book`
- `voucher_type` + `voucher_no` — the row's own document
- `against_voucher_type` + `against_voucher_no` — the document being settled
- `amount` (base currency) + `amount_in_account_currency` + `account_currency`
- `due_date` — for ageing buckets
- `delinked` — the cancellation marker used here instead of `is_cancelled`
- `voucher_detail_no` — line-level provenance

**Outstanding of an invoice** = `sum(amount)` over all rows where
`against_voucher_no = <invoice>` and `delinked = 0`. A positive sum means still owed.

**For our schema:** keep this as a materialised subledger but derive it from the GL rows in
the same transaction, and add a `settlement` table `(invoice_id, payment_id, amount,
settled_on)` instead of the `against_voucher_*` polymorphic pair. Allocation between a
payment and many invoices is genuinely a many-to-many with an amount — that is a table, not
a column pair.

Related supporting tables: `Payment Reconciliation` (+ `Allocation`, `Invoice`, `Payment`
children) is a UI scratchpad for matching; `Advance Payment Ledger Entry` tracks advances
booked to a separate party account.

---

## 3. `Stock Ledger Entry` (SLE) — quantity *and* valuation in one row

31 columns, submittable, naming `MAT-SLE-.YYYY.-.#####`.

### Identity of a movement
- `item_code`, `warehouse`, `posting_date`, `posting_time`, `posting_datetime`
- `voucher_type` + `voucher_no` + `voucher_detail_no` — provenance, same pattern as GL
- `company`, `project`, `stock_uom`

### Quantity
- `actual_qty` — signed delta. Positive = receipt, negative = issue. A transfer is two rows.
- `qty_after_transaction` — **running balance** for this item+warehouse at this point in the
  ordered ledger. Denormalised so that stock-as-of-date needs no aggregation.

### Valuation — the hard part
- `incoming_rate` / `outgoing_rate` — unit cost of this movement
- `valuation_rate` — the item+warehouse valuation rate *after* the movement
- `stock_value` — total value of the item+warehouse after the movement
- `stock_value_difference` — the delta, and this is the number that is posted to the GL as
  the stock/COGS amount. GL and stock stay reconciled only because of this column.
- `stock_queue` — a JSON list of `[qty, rate]` pairs: the actual FIFO/LIFO queue state
  snapshotted on every row. Valuation methods available: **FIFO, Moving Average, LIFO,
  Standard Cost** (`Stock Settings.valuation_method`, default FIFO).

### Ordering, backdating and reposting
The ledger is ordered by `(posting_datetime, creation)` per item+warehouse. Inserting a
*backdated* row invalidates `qty_after_transaction`, `valuation_rate`, `stock_value` and
`stock_queue` of every later row. ERPNext handles this asynchronously:
`Repost Item Valuation` rows are queued and `repost_future_sle()`
(`erpnext/stock/stock_ledger.py`) walks the affected ledger forward, rewriting those columns
and then re-posting the corresponding GL amounts. `dependant_sle_voucher_detail_no`,
`recalculate_rate` and `is_adjustment_entry` exist purely to drive that machinery.

**For our schema — the single most important design decision in the whole system:**
separate the *immutable event* from the *derived state*.
- `stock_move` — immutable: item, warehouse, qty delta, rate, source doc, posting instant.
- `stock_valuation_state` — recomputable projection: running qty, running value, queue.
Then backdated entries mean "recompute the projection from date X", not "rewrite history".
Store the projection in its own table (or a materialised view) with a
`(item_id, warehouse_id, posting_datetime)` covering index and version counter.

Flags to note: `is_cancelled` (legacy in-place cancel), `has_batch_no`, `has_serial_no`,
`serial_and_batch_bundle`, `auto_created_serial_and_batch_bundle`, `to_rename`, `fiscal_year`.

---

## 4. `Bin` — the balance cache

16 columns, `autoname = hash`, unique on `(warehouse, item_code)`, **not** submittable.

Pure aggregate cache, rebuilt by `update_bin_qty()` (`erpnext/stock/stock_balance.py`):
- `actual_qty` — physically on hand (from the SLE)
- `ordered_qty` — on purchase orders not yet received
- `indented_qty` — on material requests
- `planned_qty` — from production plans / work orders
- `reserved_qty`, `reserved_qty_for_production`, `reserved_qty_for_sub_contract`,
  `reserved_qty_for_production_plan`, `reserved_stock`
- `projected_qty` — the derived availability figure that reordering logic reads
- `valuation_rate`, `stock_value`, `stock_uom`, `company`

**For our schema:** keep the idea (reorder logic needs a cheap lookup) but treat it as
strictly derived: rebuildable from `stock_move` + open order lines at any time, with a
consistency check job. Never let business logic write to it directly, and never make it the
source of an accounting number.

---

## 5. `Serial and Batch Bundle` + `Serial and Batch Entry` — traceability

Modern ERPNext no longer stores serials as a text blob on the movement; it creates a
*bundle* document per movement line and hangs the individual serial/batch rows off it.

`Serial and Batch Bundle` (21 cols, submittable, `SABB-.########`): `item_code`, `warehouse`,
`company`, `voucher_type`/`voucher_no`/`voucher_detail_no`, `type_of_transaction`
(`Inward` | `Outward` | …), `total_qty`, `avg_rate`, `total_amount`, `is_rejected`,
`is_cancelled`, `posting_datetime`.

`Serial and Batch Entry` (child, 18 cols): `serial_no` → `Serial No`, `batch_no` → `Batch`,
`qty`, `warehouse`, `incoming_rate`, `outgoing_rate`, `stock_value_difference`,
`is_outward`, `stock_queue`, `delivered_qty`.

The SLE then references the bundle through `serial_and_batch_bundle`. Note the legacy
`Stock Ledger Entry.serial_no` (`Long Text`) and `batch_no` (`Data`, not a Link) columns are
still there — evidence of an unfinished migration.

**For our schema:** model it directly — `stock_move_serial(stock_move_id, serial_id, ...)`
and `stock_move_batch(stock_move_id, batch_id, qty, ...)`. The bundle document only exists
because the framework needed a submittable parent for the child rows; we do not need it.

---

## 6. Supporting accounting masters

| Table | Role | Notes for us |
|---|---|---|
| `Account` | chart of accounts, nested set (`lft`/`rgt`/`old_parent`), `is_group`, `root_type` (Asset/Liability/Income/Expense/Equity), `report_type`, `account_type`, `account_currency`, `freeze_account`, `balance_must_be` | one CoA per `company` — the tree is per-tenant, so our PK must include company |
| `Fiscal Year` | `year_start_date`, `year_end_date`, `is_short_year`, + `Fiscal Year Company` child | must allow non-calendar and short years |
| `Accounting Period` | period + `Closed Document` child | the close/freeze mechanism |
| `Cost Center` | nested-set dimension | same tree treatment as `Account` |
| `Finance Book` | parallel valuation books (used for depreciation) | keep: it is how you run two depreciation bases |
| `Currency Exchange` | dated FX rates | needs `(from, to, date)` unique + lookup rule |
| `Account Closing Balance` | pre-aggregated period balances | our answer to "don't scan the GL for every report" |
| `Journal Entry` + `Journal Entry Account` | the manual posting document | the only user-facing writer of arbitrary GL rows |
| `Payment Entry` + `Payment Entry Reference` | money in/out and its allocation to invoices | `Reference` child is the real settlement table |
