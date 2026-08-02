# 7. Period control, period close and opening balances

Year-end, the closing-balance snapshot mechanism, what blocks a posting, and how a business gets its
first numbers into the system.

Primary files:
- `accounts/doctype/period_closing_voucher/period_closing_voucher.py`
- `accounts/doctype/account_closing_balance/account_closing_balance.py`
- `accounts/doctype/process_period_closing_voucher/process_period_closing_voucher.py`
- `accounts/doctype/accounting_period/accounting_period.py`, `accounts/services/gl_validator.py`
- `accounts/doctype/fiscal_year/fiscal_year.py`, `accounts/utils.py:66-201`
- `accounts/doctype/opening_invoice_creation_tool/opening_invoice_creation_tool.py`
- `accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py`
- `accounts/report/financial_statements.py`, `report/trial_balance/trial_balance.py`

Naming note: the methods named in older docs (`validate_account_head`, `validate_posting_date`,
`get_pl_balances`, `get_grouped_gl_entries`) do not exist under those names in v17; the equivalents are
mapped below.

---

## 7.1 Period Closing Voucher (PCV) — validation

`validate()` (:43-49) runs, in order:

1. **`validate_start_and_end_date`** (:58-77)
   ```
   fy_start_date, fy_end_date = Fiscal Year.year_start_date, .year_end_date
   prev_end = get_previous_closed_period_in_current_year(fiscal_year, company)   # MAX(period_end_date) of submitted PCVs, same FY + company
   valid_start_date = add_days(prev_end, 1) if prev_end else fy_start_date
   throw unless period_start_date == valid_start_date        "Period Start Date must be {0}"
   throw if period_start_date > period_end_date
   throw if period_end_date > fy_end_date
   ```
   > **Invariant** PCVs must **tile the fiscal year contiguously from the FY start**, with no gaps or
   > overlaps. This is what makes intra-year (monthly/quarterly) closings possible.

2. **`check_if_previous_year_closed`** (:79-113): the previous fiscal year must either have a submitted
   PCV, or contain **no** non-cancelled GL entries (an empty year needs no closing), else
   "Previous Year is not closed, please close it first". Note the in-source comment about a real bug
   fixed here: `previous_fiscal_year[1]` vs the old `[0][1]`, which read the 2nd character of the FY
   *name* — MariaDB silently coerced it to NULL, Postgres rejected it. A good example of why we want
   real types.

3. **`block_if_future_closing_voucher_exists`** (:113-126): any submitted PCV with a later
   `period_end_date` blocks **both create and cancel**.
   > **Invariant** Closes are append-only in time; cancels are LIFO.

4. **`check_closing_account_type`**: `Account.root_type` of `closing_account_head` must be
   `Liability` or `Equity` (retained earnings). Note it checks *root_type*, not `report_type`.

5. **`check_closing_account_currency`**: must equal `Company.default_currency`.

6. **`validate_accounts_not_frozen`** (:51-56) → `check_freezing_date(period_end_date, company)`;
   on cancel it passes `getdate()` (today) instead when the immutable ledger is enabled.

`validate_accounting_period_on_doc_save` (accounting_period.py:105) special-cases PCV and tests
`period_end_date` against closed Accounting Periods.

## 7.2 What PCV posts

`on_submit` (:144-150): sets `gle_processing_status = "In Progress"`, then either
`make_gl_entries()` (legacy, when `Accounts Settings.use_legacy_controller_for_pcv`, **default 1**) or
creates + submits a `Process Period Closing Voucher` (see §7.4).

`make_gl_entries` (:182-196): if `frappe.db.estimate_count("GL Entry") > 100_000` it enqueues
`process_gl_and_closing_entries` (timeout 1800) and msgprints; else runs inline.

```
process_gl_and_closing_entries(doc):
    gl_entries = doc.get_pcv_gl_entries()
    if gl_entries: make_gl_entries(gl_entries, merge_entries=False)
    closing_entries = doc.get_account_closing_balances()
    make_closing_entries(closing_entries, doc.name, doc.company, doc.period_end_date)
    set gle_processing_status = "Completed"
except:  rollback ; log_error ; set error_message + gle_processing_status = "Failed"
```
> A failed PCV stays **submitted but flagged** — no automatic retry. Plan for that state explicitly.

### The rows

`get_pcv_gl_entries()`:
- for every **P&L** account (`Account.report_type == "Profit and Loss"`) with a non-zero balance in a
  dimension bucket → one **reversing** row (`get_gle_for_pl_account`):
  ```
  bal_company = debit − credit ; bal_account_ccy = debit_in_account_currency − credit_in_account_currency
  debit  = abs(bal) if bal < 0 else 0
  credit = abs(bal) if bal > 0 else 0          # account-currency legs computed independently
  posting_date = period_end_date ; voucher_type = "Period Closing Voucher"
  is_period_closing_voucher_entry = 1 ; is_opening = "No"
  ```
- exactly **one** row per dimension bucket on `closing_account_head`
  (`get_gle_for_closing_account`), with `debit = bal if bal > 0 else 0`,
  `credit = abs(bal) if bal < 0 else 0` where `bal = Σ (debit − credit)` of that bucket's P&L rows.

> Net **profit** (credits exceed debits ⇒ `bal < 0`) → P&L accounts debited, closing account
> **credited** (equity up). Net **loss** → closing account debited.
> **Balance-sheet accounts get no GL rows at all.**

The GL map is balanced per bucket, so `process_debit_credit_difference` has nothing to fix.
PCV also bypasses several engine steps (see doc 01 §1.2): budget validation, PLE creation,
`validate_against_pcv`, and budget checks in `make_entry`.

### Dimension grouping

`get_accounting_dimension_fields()` = `["cost_center", "finance_book", "project"] + get_accounting_dimensions()`.
`get_key(gle)` is the tuple of those values; `set_account_balance_dict` accumulates
`{dim_key: {account: {debit, credit, debit_in_account_currency, credit_in_account_currency,
account_currency}, "balances": {...}}}`.

> **Invariant** P&L is zeroed **per full dimension tuple**, and retained earnings is booked per tuple,
> so cost-center-wise / project-wise equity is preserved. NULL dimensions form their own bucket.

### Source query (`get_gl_entries_for_current_period`)

```sql
company = ? AND voucher_type != 'Period Closing Voucher' AND is_cancelled = 0
AND account IN (SELECT name FROM tabAccount WHERE report_type = ?)
AND ( only_opening_entries ? is_opening = 'Yes'
                           : posting_date BETWEEN period_start_date AND period_end_date AND is_opening = 'No' )
```
Streamed with `frappe.db.unbuffered_cursor()` + `as_iterator=True` for memory control. Excluding
`voucher_type != 'Period Closing Voucher'` is what stops a close from re-closing its own reversals.
For **Balance Sheet**, `get_account_balances_based_on_dimensions` additionally folds in **all**
`is_opening = 'Yes'` entries (any date) when `is_first_period_closing_voucher()` — so the very first PCV
absorbs opening balances into the snapshot exactly once.

## 7.3 `Account Closing Balance` — the snapshot store

The doctype has no logic; it is columns only: `company, account, account_currency, closing_date,
cost_center, project, finance_book, debit/credit (+ account-currency and reporting-currency twins),
reporting_currency_exchange_rate, is_period_closing_voucher_entry, period_closing_voucher` + dimension
columns.

`make_closing_entries(closing_entries, voucher_name, company, closing_date)` (:46-70):
1. `get_previous_closing_entries(company, closing_date, dimensions)`
   (`accounts/doctype/account_closing_balance/account_closing_balance.py:119`) — finds the single
   latest submitted PCV with `period_end_date < closing_date` and reads **all** its
   `Account Closing Balance` rows.
   > **Invariant** Closing balances are **cumulative snapshots**: each PCV's rows = its own period
   > movement + the entire previous snapshot. So reading a balance as of a closing date is a
   > single-PCV lookup with no history scan.
2. `combined = closing_entries + previous_closing_entries`, then
   `aggregate_with_last_account_closing_balance` sums the four amount columns per key.
3. Key (`generate_key`, :97): `(account, account_currency, cost_center, project, finance_book,
   cint(is_period_closing_voucher_entry), *dimensions)`, all `cstr()`-normalised so NULL and `""`
   collapse. `company` is carried but **not** part of the key (the query is already company-scoped).
4. Each bucket is inserted and submitted, after `set_amount_in_reporting_currency` (:156) which throws
   `ReportingCurrencyExchangeNotFoundError` when no rate exists for
   `Company.default_currency → reporting_currency` on the closing date.
   > **A missing FX rate on the closing date aborts the entire close.**

What PCV stores, in three groups (`get_account_closing_balances`):
1. **P&L**: the reversing rows (`is_period_closing_voucher_entry = 1`) **plus** a mirrored copy with
   debit/credit swapped and `is_period_closing_voucher_entry = 0`. The two cancel out, so the *net*
   stored P&L balance is 0, while the flag lets reports include or exclude the closing leg.
2. **Balance sheet**: the **actual period movement** of every BS account with a non-zero balance, stored
   as raw debit/credit.
3. **Closing account**: copies of the retained-earnings rows with `period_closing_voucher = self.name`.

Invalidation is only via `delete_closing_entries(voucher_no)` (:~486) — a **hard SQL delete** of all
rows with that `period_closing_voucher`, bypassing docstatus and permissions. Safe only because cancels
are forced LIFO. Reports fall back to raw GL when
`Accounts Settings.ignore_account_closing_balance` is set (its description: *"should be enabled if PCV is
not posted for all years sequentially or missing"*).

`on_cancel` (:152-170): `ignore_linked_doctypes` includes `Account Closing Balance`;
`block_if_future_closing_voucher_exists`; then `process_cancellation` →
`make_reverse_gl_entries(...)` **then** `delete_closing_entries(...)`. If >5000 GL rows exist against the
PCV it is enqueued on the `long` queue.

> **Ours** Same concept, different mechanics: `account_period_balance(company_id, account_id,
> period_id, dimension_key, debit, credit, closing_kind)` maintained **incrementally in the posting
> transaction** (so it is always current, not only at close), plus an immutable
> `period_close(id, company_id, fiscal_year_id, period_start, period_end, closed_at, closed_by)`
> header. The retained-earnings posting is an ordinary balanced voucher of type `period_close`. No hard
> deletes: cancelling a close posts a reversing voucher and marks the header `reversed_by`.
> Contiguity and LIFO-cancel stay as constraints (`EXCLUDE USING gist` on the period range per company
> + fiscal year gives us the no-overlap guarantee for free).

## 7.4 Parallel close (`Process Period Closing Voucher`)

Used when `use_legacy_controller_for_pcv = 0`; `pcv_job_timeout` default 3600.

- `validate()` → status `Queued`, then `populate_processing_tables()`:
  `generate_pcv_dates()` creates one `normal_balances` child row **per calendar day** × `{Profit and
  Loss, Balance Sheet}`; `generate_opening_balances_dates()` (only for the first PCV) creates one
  `z_opening_balances` row per day between `MIN(GL Entry.posting_date)` and `MAX(...)`.
- `on_submit` → `initialize_parallel_threads`: sets `Running`, picks up to **4** queued rows with
  `.for_update(skip_locked=True)` ordered `(parentfield, idx, processing_date)`, marks each `Running`,
  enqueues `process_individual_date` on the `long` queue, and **commits to keep the transaction short**
  (the source comments cite REPEATABLE READ concurrency).
- `process_individual_date` returns early unless the row is still `Running`, runs one grouped query per
  day:
  ```sql
  SELECT account, <dims>, SUM(debit), SUM(credit),
         SUM(debit_in_account_currency), SUM(credit_in_account_currency), MAX(account_currency)
  FROM `tabGL Entry`
  WHERE company = ? AND is_cancelled = 0 AND posting_date = ? AND account IN (accounts of report_type)
    AND is_opening = ('Yes' if parentfield == 'z_opening_balances' else 'No')
  GROUP BY account, <dims>
  ```
  stores the JSON on the child row, marks `Completed`, commits, then `schedule_next_date` (self-chaining).
- When all rows are `Completed`, `summarize_and_post_ledger_entries` rebuilds the dimension-wise balance
  from the daily JSON blobs, posts the same reversing + closing-account rows, and calls the same
  `make_closing_entries`.
- Controls: `start`, `pause` (also unsticks `Running` rows), `resume`, `cancel`.

> ⚠ The P&L / closing-account row builders are **duplicated** at module level in this file — any formula
> change must be applied in both places. Exactly the kind of thing our single `close_period()` function
> avoids.

## 7.5 What blocks a posting — the complete rule set

| Gate | Where | Rule | Exemption |
|---|---|---|---|
| Closed Accounting Period (document save) | `accounting_period.py:105-149` | join `Accounting Period` ⋈ `Closed Document` on company, `disabled=0`, `closed=1`, `document_type == doc.doctype`, date between start/end → `ClosedAccountingPeriod`. Date selection: `Bank Clearance` skipped; `Asset` → `available_for_use_date`; `Asset Repair` → `completion_date`; `PCV` → `period_end_date`; else `posting_date` | `exempted_role` |
| Closed Accounting Period (GL level) | `gl_validator.py:39-69` | same join keyed on `gl_map[0]`; **only called when not cancelling**, so reversal rows are not blocked here | `exempted_role` |
| Freeze date | `gl_validator.py:96-118` | `getdate(posting_date) <= Company.accounts_frozen_till_date` → throw | `Company.role_allowed_for_frozen_entries`, **Administrator explicitly excluded**; `adv_adj=True` skips entirely |
| PCV period lock | `gl_validator.py:134-147` | `posting_date <= MAX(submitted PCV.period_end_date)` → "Period Closed" | **none** |
| Opening entry after any close | `gl_validator.py:120` | any `is_opening = "Yes"` row while **any** submitted PCV exists → "Invalid Opening Entry" | **none** |
| Stock repost | `repost_item_valuation.py:93-102` | blocked before PCVs, closed Accounting Periods, Stock Closing Entries and the freeze date | — |
| Freezing while reposts pending | `stock/utils.py:542` | `PendingRepostingError` | — |

Note `Accounting Period.validate_dates` also refuses a period whose `end_date > nowdate()`
("cannot be created for a future date"), and `validate_overlap`
(`accounts/doctype/accounting_period/accounting_period.py:61`) does **not** exclude disabled
periods from the overlap test.

The migration `patches/v16_0/migrate_account_freezing_settings_to_company.py` moved
`Accounts Settings.acc_frozen_upto` / `frozen_accounts_modifier` to
`Company.accounts_frozen_till_date` / `role_allowed_for_frozen_entries` — i.e. freezing became
per-company, which is the right call for multi-entity.

> **Ours** One function:
> ```
> assert_postable(company_id, posting_date, doc_type, is_opening, actor)
>   -> ok | Denied(reason, overridable_by_role)
> ```
> called from exactly one place in the posting path, for both normal and reversing entries, with every
> override written to `posting_override_log`. No `adv_adj`-style silent bypass.

## 7.6 Fiscal years

`validate_dates` (:42-55): unless `is_short_year`, `year_end_date` must equal
`year_start_date + 1 year − 1 day`, else `InvalidDates`.
`validate_overlap` (:57-94): another FY overlapping by date is an error when **both** are
company-agnostic **or** they share a company via `Fiscal Year Company` →
"Year start date or end date is overlapping with {link}. To avoid please set company"
(`frappe.NameError`). So parallel fiscal years are legal only when scoped to disjoint companies.
The overlap query does not filter `disabled`.

`auto_create_fiscal_year()` (`accounts/doctype/fiscal_year/fiscal_year.py:96`, scheduled): for
non-short FYs ending in 3 days, creates the next
one inside `frappe.db.savepoint("auto_create_fiscal_year")`, copying `disabled` and the company rows,
`auto_created = 1`; a `frappe.NameError` rolls back to the savepoint (explicitly so a duplicate does not
poison the scheduler transaction on Postgres).

Date → fiscal year (`accounts/utils.py:99-201`): `_get_fiscal_years(company)` caches per-company lists
(`Fiscal Year where disabled = 0`, and when a company is given, `NOT EXISTS(Fiscal Year Company)` OR
`EXISTS(... company = ?)`), `ORDER BY year_start_date DESC`. `get_fiscal_years` returns the **first**
match; `get_fiscal_year` returns `fiscal_years[0]`. **Because of the DESC ordering, if two overlapping
years are visible to a company the newest wins.** `validate_fiscal_year` (:195) either silently repairs
`doc.fiscal_year` or throws "{label} '{date}' not in Fiscal Year {fy}".

## 7.7 Opening balances

### Opening AR/AP (`Opening Invoice Creation Tool`)

`make_invoices()`: `< 50` invoices run inline, else enqueued (`job_id = opening_invoice::<name>`,
timeout 6000).
Per row (`get_invoice_dict`): a **single item line** with `rate = outstanding_amount / qty`,
`qty = qty or 1`, and crucially `income_account` (Sales) / `expense_account` (Purchase) **= the
Temporary Opening account** (`Account.account_type == "Temporary"`, validated). Header:
`is_opening = "Yes"`, `set_posting_time = 1`, `is_pos = 0`, **`update_stock = 0`**,
`disable_rounded_total = 1`, and the user-supplied `invoice_number` becomes the docname
(`doc.insert(set_name=invoice_number)`).

Resulting GL: Debtors/Creditors on the party side, **Temporary Opening** as the contra — an
asset/liability account, so opening AR/AP never touches P&L.

`start_import` wraps each invoice in `frappe.db.savepoint(f"opening_invoice_{hash}")` with
`flags.ignore_mandatory = True`, inserting, submitting and committing per invoice; on error it rolls back
to the savepoint and logs (the comment notes a full rollback would lose earlier invoices *and* the error
logs on Postgres).

### Opening GL (`Journal Entry`)

`journal_entry.py` `validate()` (:140-186):
```
if voucher_type == "Opening Entry": is_opening = "Yes"
if is_opening == "Yes": validate_opening_entry_against_pcv(company)
```
The conventional shape is one row per real balance-sheet account and the balancing row on **Temporary
Opening**; when the trial balance nets to zero, Temporary Opening ends at zero.
`before_submit` → `validate_total_debit_and_credit()` enforces total debit == total credit **in company
currency**, so a multi-currency opening whose rates do not tie out must be plugged.

### Opening stock

`Item.after_insert` → `set_opening_stock()` (item.py:309): requires `is_stock_item`, a serial series for
serialised items, a batch series for batched items, and a `valuation_rate` ("Valuation Rate is mandatory
if Opening Stock entered"). Per `item_defaults` row it resolves the warehouse
(`default_warehouse` → `Company.default_warehouse` → the company's `Stores`) and
`opening_account = Account where company, account_type = "Temporary", is_group = 0` (throws if missing),
then creates a Stock Reconciliation with `expense_account = opening_account`.

`Stock Reconciliation.purpose ∈ {"", "Opening Stock", "Stock Reconciliation"}`. For `Opening Stock` the
difference account must be **Asset/Liability** → `OpeningEntryAccountError`
("Difference Account must be an Asset/Liability type account, since this Stock Reconciliation is an
Opening Entry"); a normal reconciliation posts the difference to `Stock Adjustment` (P&L).
The same rule applies to Stock Entries (`stock_entry_detail.py:138-161`).
Resulting GL: Dr warehouse stock account / Cr Temporary Opening.

> **Ours** An explicit `opening_batch` document that owns all three: opening GL rows, opening AR/AP
> (one row per open invoice, with `doc_no` preserved for reference) and opening stock (one
> `stock_move` per item+warehouse with `is_opening = true`). One contra account (`temporary_opening`),
> one validation ("the batch must net to zero on the contra account before it can be posted"), and a
> single reversible unit. Opening rows are ordinary immutable rows with an `is_opening` flag — kept,
> because reports genuinely need to separate "brought forward" from "transacted".

## 7.8 Exchange Rate Revaluation

Candidate selection
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py`,
`get_account_balance_from_gle` :187): accounts with `is_group = 0`,
`report_type = "Balance Sheet"`, `root_type IN (Asset, Liability, Equity)`,
`account_type != "Stock"`, and `account_currency != company_currency`. Per
`(account, NULLIF(party_type,''), NULLIF(party,''))` over non-cancelled GL rows up to the posting date:
```
balance                     = SUM(debit) − SUM(credit)                                    -- company ccy
balance_in_account_currency = SUM(debit_in_account_currency) − SUM(credit_in_account_currency)
HAVING balance != balance_in_account_currency AND (either is non-zero)
```
(`Max(party_type)`/`Max(party)`/`Max(account_currency)` are used to keep the GROUP BY Postgres-valid.)
Both are rounded and snapped to 0 within `rounding_loss_allowance`.

`calculate_new_account_balance` (:280-372):
```
current_rate = balance / balance_in_account_currency
new_rate     = get_exchange_rate(account_currency, company_currency, posting_date)
new_balance_in_base = balance_in_account_currency * new_rate
gain_loss    = flt(new_balance_in_base, precision) − flt(balance, precision)
zero-balance cases: if balance != 0 (account ccy side 0) -> gain_loss = 0 − balance
                    if balance == 0 -> current_rate from the last GLE; gain_loss = −current_rate * balance_in_account_currency
```

`make_jv_entries()` creates up to two Journal Entries, both `voucher_type = "Exchange Gain Or Loss"`,
`multi_currency = 1`, every row referencing the ERR:
- `make_jv_for_zero_balance()` — reverses the residual on whichever side is stranded, contra
  `Company.unrealized_exchange_gain_loss_account`, `exchange_rate = 0` on the stranded leg;
- `make_jv_for_revaluation()` — the account leg carries the **base-currency delta only**, contra to the
  unrealised account.

Because these deliberately break debit==credit in *account* currency, `voucher_type == "Exchange Gain Or
Loss"` is whitelisted from the balance check (doc 01 §1.3).

## 7.9 Report reads — how snapshots and `is_opening` avoid double counting

`set_gl_entries_by_account` (financial_statements.py:617-685) is the key function:
```
ignore_closing_balances = Accounts Settings.ignore_account_closing_balance
if not from_date and not ignore_closing_balances:                       # Balance Sheet path
    last_pcv = latest submitted PCV with period_end_date < filters.period_start_date
    if last_pcv:
        gl_entries += get_accounting_entries("Account Closing Balance", ..., period_closing_voucher=last_pcv.name)
        from_date = add_days(last_pcv.period_end_date, 1)
        ignore_opening_entries = True                                   # ← the anti-double-count guard
gl_entries += get_accounting_entries("GL Entry", from_date, to_date, ..., ignore_opening_entries=...)
```
> **Balance-sheet history before the last close is read from one snapshot instead of scanning the
> ledger**, and because that snapshot already contains the pre-history opening entries, the GL leg then
> skips `is_opening = "Yes"` rows.

`get_accounting_entries` (:688-790) is polymorphic over `GL Entry` and `Account Closing Balance` —
possible only because the debit/credit column names are identical (the ACB branch aliases
`closing_date as posting_date`). `apply_additional_conditions` (:800-870) maps
`ignore_closing_entries` to `GL Entry.voucher_type != "Period Closing Voucher"` **or**
`Account Closing Balance.is_period_closing_voucher_entry == 0` — which is exactly why the ACB table
stores both legs of the P&L close.

`calculate_values` (:406-437):
```
for each entry, for each period:
    if entry.posting_date <= period.to_date
       and (accumulated_values or entry.posting_date >= period.from_date)
       and (not ignore_accumulated_values_for_fy or entry.fiscal_year == period.to_date_fiscal_year):
           d[period.key] += debit − credit
if not grouped_by_dimension and entry.posting_date < period_list[0].year_start_date:
    d["opening_balance"] += debit − credit         # snapshot rows carry closing_date, so they land here
```
`prepare_data` flips sign for `balance_must_be == "Credit"`, rounds to 3.

Trial Balance (`trial_balance.py:100-330`) uses the same primitives, plus the `is_opening` predicate that
matters most:
```
no PCV, no start_date : posting_date < from_date OR is_opening = 'Yes'      -- back-dated openings always in opening
with start_date       : posting_date BETWEEN start_date AND from_date-1 AND is_opening = 'No'
unless with_period_closing_entry_for_opening: exclude the closing leg
show_unclosed_fy_pl_balances off: P&L openings limited to posting_date >= year_start_date
```
`Accounts Settings.ignore_is_opening_check_for_reporting` disables the legacy `is_opening` behaviour so
date is the only criterion.

> **Ours** Reports read `account_period_balance` (always current) and never the ledger for period
> aggregates. `is_opening` stays a real column because "opening vs movement" is a genuine reporting
> distinction, but it is **not** a substitute for a date: an opening row must still fall inside the
> opening period. That single rule deletes the entire `is_opening OR posting_date` predicate family and
> the toggle that exists to work around it.

---

## Invariants and edge cases

1. **Contiguity:** a PCV must start exactly at the FY start or the day after the previous closed period
   in the same FY; no later PCV may exist (blocks create **and** cancel).
2. **Closing a year twice is structurally impossible**: the second PCV would need
   `period_start_date == prev_end + 1`, which lies outside the FY once fully closed. Belt and braces:
   PCV queries exclude `voucher_type = 'Period Closing Voucher'`.
3. **Posting into a closed period has no role exemption.** Accounting Period closure does
   (`exempted_role`); the freeze date does (with Administrator excluded); the PCV lock does not.
4. **Opening entries must be entered before the first close** — any `is_opening` row is refused once any
   PCV exists, and a pre-PCV date also fails the period lock.
5. `is_first_period_closing_voucher()` returns True when the earliest submitted PCV is missing **or is
   this one**, which is how opening balances are folded into the snapshot exactly once.
6. P&L is zeroed per dimension tuple, not just per account; NULL dimensions form their own bucket.
7. Multi-currency: the account-currency reversal is computed independently of the company-currency one
   (their signs can theoretically diverge); the closing account is forced to company currency; a missing
   reporting-currency rate on the closing date aborts the close.
8. Async: legacy path enqueues above 100k GL rows and cancels asynchronously above 5k rows against the
   PCV; failures leave `gle_processing_status = "Failed"` on a submitted document. The parallel path
   shards per day × report type with 4 workers, `skip_locked`, frequent commits, and duplicated row
   builders.
