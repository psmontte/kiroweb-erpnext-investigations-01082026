# S05 — Period Close and Opening Balances, Walked Through

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev). Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.
>
> Doc 07 is the subsystem reference for period control. This document **walks a full year-end
> through**, in order, with numbers — and then walks the *opening* of a brand-new company, which is
> the same machinery run in reverse.

---

## 1. Two separate mechanisms that are easy to confuse

| | `Accounting Period` | `Period Closing Voucher` |
|---|---|---|
| Purpose | **Prevent posting** into a date range | **Roll P&L into equity** and snapshot balances |
| Effect on GL | none — it is a gate | writes GL entries |
| Granularity | per document type | whole company |
| Reversible | disable the record | cancel the voucher |
| Table | `tabAccounting Period` + `tabClosed Document` | `tabPeriod Closing Voucher` + `tabAccount Closing Balance` |

Plus a **third**, unrelated gate: `Accounts Settings.acc_frozen_upto` /
`frozen_accounts_modifier`, checked by `check_freezing_date` (doc 07). And a **fourth** for
inventory: `Stock Closing Entry`.

Four independent mechanisms, no shared model. A date can be open in one and closed in another.

---

## 2. Setting: AlphaCo, FY 2025-26 (1 Apr 2025 – 31 Mar 2026)

Trial balance at 31 Mar 2026 (company currency INR, simplified):

| Account | Report type | Debit | Credit |
|---|---|---:|---:|
| Debtors | Balance Sheet | 1 240 000 | |
| Stock In Hand | Balance Sheet | 860 000 | |
| Bank | Balance Sheet | 2 100 000 | |
| Creditors | Balance Sheet | | 740 000 |
| Share Capital | Balance Sheet | | 1 000 000 |
| Retained Earnings | Balance Sheet | | 1 460 000 |
| **Sales — Revenue** | **P&L** | | **9 800 000** |
| **Cost of Goods Sold** | **P&L** | **6 300 000** | |
| **Salaries** | **P&L** | **1 900 000** | |
| **Freight** | **P&L** | **240 000** | |
| **Round Off** | **P&L** | **360** | |
| | | **12 400 360** | **12 400 360** |

Net profit for the year = 9 800 000 − (6 300 000 + 1 900 000 + 240 000 + 360) = **1 359 640**.

Two cost centres carry the P&L: `Main - AC` (70 %) and `Depot - AC` (30 %).

---

## 3. Stage 1 — Fiscal Year exists and does not overlap

`FiscalYear` (`accounts/doctype/fiscal_year/fiscal_year.py:12`):
`validate_dates` (`:42`), `validate_overlap` (`:57`), `on_update` (`:36`), `on_trash` (`:39`),
`auto_create_fiscal_year` (`:96`, a scheduled job), `get_from_and_to_date` (`:136`).

`validate_overlap` (`:57`) is an application-level scan. Fiscal years are **company-scoped through
a child table** (`Fiscal Year Company`), not a column — so "the fiscal year for company X" is a
join, and two companies can legitimately have different year boundaries.

`get_fiscal_year` (`accounts/utils.py:66`) / `get_fiscal_years` (`:99`) /
`_get_fiscal_years` (`:147`) resolve a date to a year, and
`validate_fiscal_year` (`accounts/utils.py:195`) is the per-document check.

---

## 4. Stage 2 — Close the *posting window* with `Accounting Period`

`AccountingPeriod` (`accounts/doctype/accounting_period/accounting_period.py:19`).

```python
def validate(self):                     # :39
    self.validate_dates()               # :43
    self.validate_overlap()             # :61

def validate_dates(self):               # :43
    if getdate(self.start_date) > getdate(self.end_date):
        frappe.throw(_("Start Date cannot be after End Date"))
    if getdate(self.end_date) > getdate(nowdate()):
        frappe.throw(_("Accounting Period cannot be created for a future date. End Date {0} is after today."))
```

⚠️ **You cannot create an Accounting Period ending in the future** (`:48`–`:53`). So you cannot
pre-close a period, and you cannot lock a window before it elapses. Combined with §4.2, the
practical effect is that closing is always a *reactive* action.

`autoname` (`:57`) is `period_name + " - " + company_abbr` — the company is baked into the
primary key, as with `Warehouse` (doc 16 §4).

`validate_overlap` (`:61`):

```python
query = (frappe.qb.from_(AccountingPeriod).select(AccountingPeriod.name)
    .where(AccountingPeriod.start_date <= self.end_date)
    .where(AccountingPeriod.end_date >= self.start_date)
    .where(AccountingPeriod.name != self.name)
    .where(AccountingPeriod.company == self.company))
if len(existing_accounting_period) > 0:
    frappe.throw(_("Accounting Period overlaps with {0}"), OverlapError)
```

Correct overlap logic (`start <= other_end AND end >= other_start`), implemented as a scan with no
lock — two concurrent inserts can both pass. A PostgreSQL `EXCLUDE USING gist` on
`(company, daterange)` would make it structural.

### 4.1 What gets closed is a list of document types

`before_insert` (`:54`) → `bootstrap_doctypes_for_closing` (`:93`) → `get_doctypes_for_closing`
(`:82`):

```python
doctypes = frappe.get_hooks("period_closing_doctypes")
closed_doctypes = [{"document_type": doctype, "closed": 1} for doctype in doctypes]
```

So the set of things a period can close is **`period_closing_doctypes` in `hooks.py`**
(doc 21 §2.2) — a Python list. Each Accounting Period gets a `Closed Document` child row per
doctype with a `closed` checkbox, defaulted to 1.

**A posting doctype that is not in that hook list cannot be closed by an Accounting Period at
all.** Adding a new document that writes GL without adding it to the list leaves a hole.

### 4.2 The gate itself

`validate_accounting_period_on_doc_save`
(`accounts/doctype/accounting_period/accounting_period.py:105`), wired as a `doc_events`
`validate` hook for `tuple(period_closing_doctypes)` (doc 21 §2.2):

```python
if doc.doctype == "Bank Clearance":            return          # ← exempt entirely
elif doc.doctype == "Asset":
    if doc.asset_type == "Existing Asset":     return
    else: date = doc.available_for_use_date
elif doc.doctype == "Asset Repair":            date = doc.completion_date
elif doc.doctype == "Period Closing Voucher":  date = doc.period_end_date
else:                                          date = doc.posting_date
...
accounting_period = (frappe.qb.from_(ap).from_(cd)
    .select(ap.name, ap.exempted_role)
    .where((ap.name == cd.parent) & (ap.company == doc.company) & (ap.disabled == 0) ...))
```

Findings:

- **`Bank Clearance` is exempt unconditionally** (`:106`–`:107`). Clearing a cheque in a closed
  period is always allowed — defensible (it does not post GL), but it *does* mutate
  `clearance_date` on documents inside the closed period (doc 14 §1.3).
- The **date field differs per doctype**, resolved by an `if/elif` chain. A doctype whose effective
  date is not `posting_date` and is not in this chain is gated on the wrong field.
- `exempted_role` — a role that bypasses the period lock. Same pattern as the budget approver
  (doc 12 §1.3) and over-delivery bypass (doc 10 §1.3): a hard control downgradable by role, with
  **nothing recorded** about the bypass.
- `ap.disabled == 0` — disabling the period re-opens it, silently, with no audit of who or when.

### 4.3 Our design

```sql
CREATE TABLE accounting_period (
    id           uuid PRIMARY KEY,
    company_id   uuid NOT NULL REFERENCES company(id),
    code         text NOT NULL,
    period_from  date NOT NULL,
    period_to    date NOT NULL,
    state        period_state NOT NULL,   -- 'open','soft_closed','closed','permanently_closed'
    closed_at    timestamptz,
    closed_by    uuid REFERENCES app_user(id),
    CONSTRAINT ap_range CHECK (period_from <= period_to),
    UNIQUE (company_id, code),
    EXCLUDE USING gist (company_id WITH =, daterange(period_from, period_to, '[]') WITH &&)
);
CREATE TABLE period_override (
    id             uuid PRIMARY KEY,
    period_id      uuid NOT NULL REFERENCES accounting_period(id),
    resource       resource_kind,           -- NULL = all
    granted_to     uuid NOT NULL REFERENCES app_user(id),
    granted_by     uuid NOT NULL REFERENCES app_user(id),
    granted_at     timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,
    reason         text NOT NULL
);
```

- **`EXCLUDE USING gist`** makes overlap impossible, not merely validated (§4).
- **Future periods are creatable.** Pre-closing and scheduled locks work.
- **The gate is a trigger** on every ledger table checking the voucher's `posting_date` against
  `accounting_period.state`, so it applies to *every* posting path — there is no
  `period_closing_doctypes` list to forget (§4.1), and no per-doctype date-field chain (§4.2).
- **Bypass is a `period_override` row** with `granted_by`, `reason`, and `expires_at` — auditable
  and time-boxed, not a role check (§4.2). This is the same construct S02 §12.9 uses for
  `settlement.effective_date` and doc 12 §1.6 for budget overrides.
- **Re-opening is a state transition** writing `lifecycle_event` (doc 20 §3.3), not a `disabled`
  checkbox.

---

## 5. Stage 3 — `Period Closing Voucher`: roll P&L into equity

`PeriodClosingVoucher(AccountsController)`
(`accounts/doctype/period_closing_voucher/period_closing_voucher.py:22`).

### 5.1 Six validations

```python
def validate(self):                              # :43
    self.validate_start_and_end_date()           # :58
    self.check_if_previous_year_closed()         # :79
    self.block_if_future_closing_voucher_exists()# :113
    self.check_closing_account_type()            # :130
    self.check_closing_account_currency()        # :138
    self.validate_accounts_not_frozen()          # :51
```

**`validate_start_and_end_date`** (`:58`) enforces that periods are **contiguous and gapless**:

```python
prev_closed_period_end_date = get_previous_closed_period_in_current_year(self.fiscal_year, self.company)  # :545
valid_start_date = (add_days(prev_closed_period_end_date, 1) if prev_closed_period_end_date
                    else self.fy_start_date)
if getdate(self.period_start_date) != getdate(valid_start_date):
    frappe.throw(_("Period Start Date must be {0}").format(formatdate(valid_start_date)))
```

Good design: you cannot close April and then June, skipping May. The start date is *computed*, not
chosen.

**`check_if_previous_year_closed`** (`:79`) — and note the comment at `:87`–`:89`, a fixed bug worth
recording because it is exactly the class of defect a typed schema prevents:

> `get_fiscal_year()` returns a single (name, start_date, end_date) tuple, so the start date is
> [1]; the old [0][1] read the 2nd char of the name ('T'), which MariaDB silently coerced to NULL
> but postgres rejects as an invalid date.

**A string index was being used as a date** and MariaDB accepted it. The check was silently
inert on MySQL for however long. This is the strongest single argument in the codebase for
`numeric`/`date` columns and a strict database.

The logic then permits closing if the previous year has **no GL entries at all** (`:135`–`:139`),
so a fresh install does not need a fictitious prior close.

**`check_closing_account_type`** (`:130`): the closing account's `root_type` must be
`Liability` or `Equity`. **`check_closing_account_currency`** (`:138`): it must be in company
currency.

**`block_if_future_closing_voucher_exists`** (`:113`) prevents both creating a PCV before an
existing later one, and cancelling one that has a later PCV after it — so the chain can only be
unwound from the end.

**`validate_accounts_not_frozen`** (`:51`) — with an interesting wrinkle:

```python
posting_date = self.period_end_date
if for_cancellation and is_immutable_ledger_enabled():
    posting_date = getdate()          # ← cancel checks TODAY's freeze, not the period's
check_freezing_date(posting_date, self.company)
```

Under immutable-ledger mode, cancelling a PCV is validated against **today**, because the reversal
will be posted today rather than in the closed period (doc 01 §7, doc 09 §3.1).

### 5.2 Submit — two engines, chosen by a setting

`on_submit` (`:144`):

```python
self.db_set("gle_processing_status", "In Progress")
if frappe.get_single_value("Accounts Settings", "use_legacy_controller_for_pcv"):
    self.make_gl_entries()                        # :182 — in-process, or enqueued if large
else:
    ppcv = frappe.get_doc({"doctype": "Process Period Closing Voucher",
                           "parent_pcv": self.name})
    ppcv.save().submit()                          # parallel, chunked, resumable
```

**Two complete implementations of year-end close**, selected by a global setting:

| | Legacy (`use_legacy_controller_for_pcv = 1`) | Default |
|---|---|---|
| Driver | `make_gl_entries` (`:182`) → `process_gl_and_closing_entries` (`:479`) | `Process Period Closing Voucher` (`accounts/doctype/process_period_closing_voucher/process_period_closing_voucher.py:19`) |
| Execution | in-process, or `frappe.enqueue(timeout=1800)` if `GL Entry` count > 100 000 (`:183`–`:196`) | `initialize_parallel_threads` (`:92`), `start_pcv_processing` (`:137`), `schedule_next_date` (`:256`), `process_individual_date` (`:543`) |
| Control | none | `pause_pcv_processing` (`:144`), `resume_pcv_processing` (`:173`), `cancel_pcv_processing` (`:159`) |

The existence of **pause and resume buttons on year-end close** tells you how long it runs. And
`make_gl_entries` (`:182`) branching on `frappe.db.estimate_count("GL Entry") > 100_000` means the
*algorithm* changes based on table size.

Note the duplication: `get_gle_for_pl_account` exists at
`accounts/doctype/period_closing_voucher/period_closing_voucher.py:218` **and** at
`accounts/doctype/process_period_closing_voucher/process_period_closing_voucher.py:195`;
`get_gle_for_closing_account` at `:248` and `:227`; `get_closing_entry` at `:420` and `:462`;
`update_default_dimensions` at `:276` and `:190`. **Two copies of the year-end algorithm** that
must be kept in agreement by hand.

### 5.3 Computing the balances

`get_account_balances_based_on_dimensions` (`:280`):

```python
self.get_accounting_dimension_fields()                       # :298
acc_bal_dict = frappe._dict()
with frappe.db.unbuffered_cursor():
    gl_entries = self.get_gl_entries_for_current_period(report_type, as_iterator=True)   # :302
    for gle in gl_entries:
        acc_bal_dict = self.set_account_balance_dict(gle, acc_bal_dict)                  # :341
if report_type == "Balance Sheet" and self.is_first_period_closing_voucher():            # :445
    opening_entries = self.get_gl_entries_for_current_period(report_type, only_opening_entries=True)
    for gle in opening_entries:
        acc_bal_dict = self.set_account_balance_dict(gle, acc_bal_dict)
```

`get_accounting_dimension_fields` (`:298`):

```python
default_dimensions = ["cost_center", "finance_book", "project"]
self.accounting_dimension_fields = default_dimensions + get_accounting_dimensions()
```

So closing is **dimension-wise**: one closing entry per (account × cost centre × finance book ×
project × every custom dimension) combination. Our two cost centres double the row count.

`get_gl_entries_for_current_period` (`:302`):

```sql
SELECT name, posting_date, account, account_currency,
       debit_in_account_currency, credit_in_account_currency, debit, credit,
       cost_center, finance_book, project, <custom dimensions...>
FROM `tabGL Entry`
WHERE company = ?
  AND voucher_type != 'Period Closing Voucher'      -- ← exclude prior closes
  AND is_cancelled = 0
  AND account IN (SELECT name FROM `tabAccount` WHERE report_type = ?)
  AND posting_date BETWEEN ? AND ? AND is_opening = 'No'
```

Note:

- **A full scan of the year's GL, streamed** (`unbuffered_cursor`, `:288`) and aggregated **in
  Python**. On a large ledger this is the expensive step, and it is why the parallel engine exists.
- `voucher_type != 'Period Closing Voucher'` excludes prior closing entries, so closes do not
  compound.
- `is_opening = 'No'` excludes opening entries — **except** for Balance Sheet accounts on the
  *first* PCV (`:292`–`:296`), where openings must be included or the carried-forward balance is
  wrong. `is_first_period_closing_voucher` (`:445`) has an implicit `return None` when a *later*
  PCV exists, which reads as falsey — correct, but only by omission.

### 5.4 The GL entries produced

`get_pcv_gl_entries` (`:198`):

```python
pl_account_balances = self.get_account_balances_based_on_dimensions(report_type="Profit and Loss")
for dimensions, account_balances in pl_account_balances.items():
    for acc, balances in account_balances.items():
        balance_in_company_currency = flt(balances.debit) - flt(balances.credit)
        if balance_in_company_currency and acc != "balances":
            self.pl_accounts_reverse_gle.append(self.get_gle_for_pl_account(acc, balances, dimensions))
    self.closing_account_gle.append(
        self.get_gle_for_closing_account(account_balances["balances"], dimensions))
return self.pl_accounts_reverse_gle + self.closing_account_gle
```

`get_gle_for_pl_account` (`:218`) writes the **reversal** of each P&L account, with
`is_period_closing_voucher_entry = 1`:

```python
"debit":  abs(balance_in_company_currency) if balance_in_company_currency < 0 else 0,
"credit": abs(balance_in_company_currency) if balance_in_company_currency > 0 else 0,
```

For `Main - AC` (70 % of each P&L account):

| Account | Cost Centre | Debit | Credit |
|---|---|---:|---:|
| Sales — Revenue | Main - AC | 6 860 000 | |
| Cost of Goods Sold | Main - AC | | 4 410 000 |
| Salaries | Main - AC | | 1 330 000 |
| Freight | Main - AC | | 168 000 |
| Round Off | Main - AC | | 252 |
| **Retained Earnings** (closing account) | Main - AC | | **951 748** |

`get_gle_for_closing_account` (`:248`) posts the net per dimension combination:
`debit if balance > 0 else credit`. 6 860 000 − (4 410 000 + 1 330 000 + 168 000 + 252) = 951 748
credited to equity. Mirror rows for `Depot - AC` at 30 % → 407 892. Total 1 359 640 ✓.

**Every P&L account now has a zero balance for the closed period**, and equity carries the profit.
`is_opening` is set to `"No"` on both (`:243`, `:271`) — a closing entry is not an opening entry.

### 5.5 `Account Closing Balance` — the snapshot

`get_account_closing_balances` (`:384`) assembles **three** groups:

```python
pl_closing_entries  = self.get_closing_entries_for_pl_accounts()             # :391
bs_closing_entries  = self.get_closing_entries_for_balance_sheet_accounts()  # :406
cls_account_entries = self.get_closing_entries_for_closing_account()         # :438
```

`get_closing_entries_for_pl_accounts` (`:391`) is subtle — it stores **both** directions:

```python
closing_entries = copy.deepcopy(self.pl_accounts_reverse_gle)      # the reversal, flag = 1
for d in self.pl_accounts_reverse_gle:
    gle_copy = copy.deepcopy(d)
    gle_copy.debit  = d.credit                                     # un-reversed = actual balance
    gle_copy.credit = d.debit
    gle_copy.debit_in_account_currency  = d.credit_in_account_currency
    gle_copy.credit_in_account_currency = d.debit_in_account_currency
    gle_copy.is_period_closing_voucher_entry = 0                    # flag = 0
    gle_copy.period_closing_voucher = self.name
    closing_entries.append(gle_copy)
```

So each P&L account gets **two** `Account Closing Balance` rows: one with
`is_period_closing_voucher_entry = 1` (the closing movement) and one with `0` (the period's actual
activity). `generate_key`
(`accounts/doctype/account_closing_balance/account_closing_balance.py:93`) includes that flag in the
key, keeping them separate. A P&L report reading closing balances must know which flag it wants —
an undocumented, load-bearing discriminator.

`make_closing_entries` (`accounts/doctype/account_closing_balance/account_closing_balance.py:46`)
is where the **cumulative** carry-forward happens:

```python
previous_closing_entries = get_previous_closing_entries(company, closing_date, accounting_dimensions)  # :119
combined_entries = closing_entries + previous_closing_entries
merged_entries = aggregate_with_last_account_closing_balance(combined_entries, accounting_dimensions)   # :70
for _key, value in merged_entries.items():
    cle = frappe.new_doc("Account Closing Balance")
    cle.update(value); cle.update(value["dimensions"])
    cle.update({"period_closing_voucher": voucher_name, "closing_date": closing_date})
    set_amount_in_reporting_currency(cle, company, closing_date)      # :156
    cle.flags.ignore_permissions = True
    cle.flags.ignore_links = True
    cle.submit()
```

`get_previous_closing_entries` (`:119`) reads the **single most recent** PCV's closing balances
(`order_by="period_end_date desc", limit=1`) and `aggregate_with_last_account_closing_balance`
(`:70`) sums them with this period's. So `Account Closing Balance` is a **running cumulative
snapshot**, and each PCV's set is self-sufficient — a balance sheet as at any closed date is one
indexed read rather than a scan from inception (doc 07).

That is the right idea. Three caveats:

1. **It depends on an unbroken chain.** If a mid-year PCV is cancelled and not re-created, later
   snapshots silently carry a stale base — `get_previous_closing_entries` just takes the latest
   surviving one.
2. `cle.submit()` **per row** — one document insert per (account × dimension combination) × 2 for
   P&L. A 500-account, 20-cost-centre, 3-project chart produces tens of thousands of document
   inserts through the full ORM (`ignore_permissions`, `ignore_links` set to make it survivable).
3. `set_amount_in_reporting_currency` (`:156`) translates into the company's `reporting_currency`
   at close time — a third currency dimension beyond transaction and base (S06).

### 5.6 Cancellation

`on_cancel` (`:152`) → `cancel_gl_entries`
(`accounts/doctype/period_closing_voucher/period_closing_voucher.py:456`):

```python
if self.get_gle_count_against_current_pcv() > 5000:          # :472
    frappe.enqueue(process_cancellation, voucher_type="Period Closing Voucher",
                   voucher_no=self.name, queue="long", enqueue_after_commit=True)
else:
    process_cancellation(voucher_type="Period Closing Voucher", voucher_no=self.name)
```

`process_cancellation` (`accounts/doctype/period_closing_voucher/period_closing_voucher.py:504`) →
`delete_closing_entries` (`:526`) — the `Account Closing Balance`
rows are **deleted**, not reversed. And `on_cancel` sets:

```python
self.ignore_linked_doctypes = ("GL Entry", "Stock Ledger Entry", "Payment Ledger Entry",
                               "Account Closing Balance", "Process Period Closing Voucher")
```

disabling the back-link guard for five doctypes (doc 09 §1.4). `on_trash` (`:174`)
force-deletes the `Process Period Closing Voucher` children.

---

## 6. Stage 4 — `Stock Closing Entry`: the inventory snapshot

`StockClosingEntry` (`stock/doctype/stock_closing_entry/stock_closing_entry.py:16`) — a
**completely separate** mechanism from PCV, with no linkage.

`validate_duplicate` (`:53`) — and the comment at `:62`–`:63` is a nice piece of clarity:

```python
# two date ranges overlap when each starts on or before the other ends;
# this also catches one range being fully contained within the other
& (table.from_date <= self.to_date) & (table.to_date >= self.from_date)
for fieldname in ["warehouse", "item_code", "item_group", "warehouse_type"]:
    if self.get(fieldname):
        query = query.where(table[fieldname] == self.get(fieldname))
```

⚠️ The scope filters are added **only when set**, so a company-wide closing entry and a
warehouse-specific one for the same dates do **not** collide: the company-wide row has
`warehouse = NULL`, so `table.warehouse == self.warehouse` is never added when checking the
narrower one. **Overlapping snapshots at different scopes are permitted**, and which one a report
picks up depends on `get_last_stock_closing_entry` (`:340`).

`on_submit` (`:82`) → `enqueue_job` (`:95`):

```python
self.db_set("status", "In Progress")
enqueue(prepare_closing_stock_balance, name=self.name, queue="long", timeout=1500)
```

**Always asynchronous**, 25-minute timeout. `regenerate_closing_balance` (`:105`) exists as a
manual retry (doc 22 §2.2 — the `retry` tell).

`create_stock_closing_balance_entries` (`:109`) → `StockClosing` (`:159`):

```python
stk_cl_obj = StockClosing(self.company, self.from_date, self.to_date)
entries = stk_cl_obj.get_stock_closing_entries()          # :168
for key in entries:
    row = entries[key]
    if row.actual_qty == 0.0 and row.stock_value_difference == 0.0:
        continue                                          # ← zero rows dropped
    if row.fifo_queue is not None:
        row.fifo_queue = json.dumps(row.fifo_queue)       # ← the FIFO queue is SERIALISED
    new_doc = frappe.new_doc("Stock Closing Balance"); new_doc.update(row)
    ...
    new_doc.save()
```

Supporting: `get_sle_entries` (`:250`), `update_fifo_queue` (`:198`),
`get_initialized_entry` (`:213`), `get_entries` (`:303`),
`get_last_stock_closing_entry` (`:340`), `get_keys` (`:351`),
`get_stock_closing_balance` (`:396`).

Two observations:

- **The FIFO queue is snapshotted as a JSON string** (`:120`). That is the only way to make a FIFO
  balance resumable — and it means the closing balance carries a serialised data structure whose
  format is coupled to `stock/valuation.py` (doc 02).
- `on_cancel` (`:86`) → `remove_stock_closing` (`:90`) issues a raw
  `DELETE FROM tabStock Closing Balance WHERE stock_closing_entry = ?`. Deleted, not reversed.

**Nothing ties `Stock Closing Entry` to `Period Closing Voucher`.** You can close the accounts for
March and never snapshot stock, or snapshot stock for a range that straddles a PCV boundary.

---

## 7. Stage 5 — Opening balances for a *new* company

The reverse operation. Three separate paths.

### 7.1 GL opening balances — a Journal Entry with `is_opening = 'Yes'`

An `Opening Entry` voucher type on `Journal Entry`, with `is_opening = "Yes"` on every row.
The offsetting account is **`Temporary Opening`** (`Account.account_type = 'Temporary'`).

`get_gl_entries_for_current_period`
(`accounts/doctype/period_closing_voucher/period_closing_voucher.py:302`) filters
`is_opening = 'No'`, so opening entries are
excluded from period movement — and included for Balance Sheet accounts on the first PCV only
(§5.3).

### 7.2 AR/AP opening — `Opening Invoice Creation Tool`

`OpeningInvoiceCreationTool`
(`accounts/doctype/opening_invoice_creation_tool/opening_invoice_creation_tool.py:17`).

`validate_mandatory_invoice_fields` (`:110`):

```python
if self.create_missing_party:
    if not row.party and not row.party_name:
        frappe.throw(_("Row #{0}: Either Party ID or Party Name is required"))
    if not row.party and row.party_name:
        row.party = self.add_party(row.party_type, row.party_name)          # :175
    if row.party and not frappe.db.exists(row.party_type, row.party):
        row.party = self.add_party(row.party_type, row.party)               # ← creates a party named after an ID
...
for d in ("Outstanding Amount", "Temporary Opening Account"):
    if not row.get(scrub(d)):
        frappe.throw(mandatory_error_msg.format(row.idx, d, self.invoice_type))
self.validate_temporary_opening_account(row)                               # :138
```

⚠️ At `:118`–`:119`: if `party` is set but does not exist, a party is **created using the ID as its
name**. A typo in a customer code silently creates a customer called `CUST-00X1`.

`validate_temporary_opening_account` (`:138`) enforces `account_type == 'Temporary'`.
`get_temporary_opening_account` (`:337`):

```python
accounts = frappe.get_all("Account", filters={"company": company, "account_type": "Temporary"})
if not accounts:
    frappe.throw(_("Please add a Temporary Opening account in Chart of Accounts"))
return accounts[0].name          # ← arbitrary if several exist
```

`get_invoice_dict` (`:191`) with inner `get_item_dict` (`:192`) fabricates a **single line item**
carrying the whole outstanding amount, `make_invoices` (`:256`) → `start_import` (`:281`) →
`publish` (`:322`) run it in the background with progress events.

So opening receivables are **real invoices** with a synthetic item, posting
`Dr Debtors / Cr Temporary Opening` — which means they participate in ageing, dunning, and
allocation (S02) exactly like real invoices. That is the right outcome, achieved by fabricating
documents.

### 7.3 Stock opening — `Stock Reconciliation`

Opening inventory is a `Stock Reconciliation` (purpose `Opening Stock`) with an
`expense_account` of type `Temporary` — the same offset. Covered in doc 27.

### 7.4 The closing loop

Once all three are entered, `Temporary Opening` should net to **zero**. A non-zero balance is the
classic sign of a botched migration — and **nothing enforces it**. There is no
"opening balance complete" state, no assertion, no report that asserts it. It is a convention.

---

## 8. Full write trace, year-end close

| Stage | GL | Account Closing Balance | Stock Closing Balance | Notes |
|---|---:|---:|---:|---|
| `Accounting Period` insert | 0 | 0 | 0 | + N `Closed Document` child rows from the hook list |
| PCV submit — P&L reversal | 5 accounts × 2 CCs = **10** | | | one row per account × dimension combo |
| PCV submit — closing account | **2** | | | one per dimension combo |
| PCV — ACB snapshot | | P&L: 5×2×**2** = 20; BS: 6×2 = 12; closing: 2 → **34** | | plus prior-period carry-forward merged in |
| `Stock Closing Entry` submit | 0 | 0 | one per (item × warehouse × batch × dimensions) | async, FIFO queue JSON-serialised |

12 GL rows, 34 closing-balance documents, and an async inventory snapshot — for a five-account,
two-cost-centre toy. Real charts multiply the ACB count by hundreds.

---

## 9. Same scenario in our design

### 9.1 Period state is one enum, enforced by trigger

§4.3 gives the table. The gate is a `BEFORE INSERT` constraint trigger on `gl_entry`,
`stock_move`, `ar_ap_entry`, and `settlement`:

```
period := (SELECT state FROM accounting_period
            WHERE company_id = NEW.company_id
              AND NEW.posting_date BETWEEN period_from AND period_to);
IF period IN ('closed','permanently_closed')
   AND NOT EXISTS (SELECT 1 FROM period_override o
                    WHERE o.period_id = ... AND o.granted_to = current_user_id()
                      AND o.expires_at > now()
                      AND (o.resource IS NULL OR o.resource = <this table>))
THEN RAISE;
```

One gate, every ledger, no doctype list, no per-doctype date field, no exempt document type, and
bypass only via an audited, expiring grant.

`permanently_closed` cannot be re-opened at all — the transition is absent from the state machine,
so a statutory lock is enforceable.

### 9.2 Closing is a voucher; the snapshot is a materialised view

**The P&L roll-up stays a voucher** — it is a real accounting event and belongs in the ledger:

```sql
INSERT INTO voucher (id, company_id, doc_type, doc_no, lifecycle_state, posting_date)
     VALUES (:pcv, :co, 'period_close', 'PCV-2026-Q4', 'posted', '2026-03-31');
INSERT INTO gl_entry (voucher_id, account_id, cost_center_id, debit_base, credit_base, is_closing)
SELECT :pcv, account_id, cost_center_id,
       CASE WHEN net < 0 THEN -net ELSE 0 END,
       CASE WHEN net > 0 THEN  net ELSE 0 END,
       true
FROM (SELECT account_id, cost_center_id, SUM(debit_base - credit_base) AS net
        FROM gl_entry g JOIN account a ON a.id = g.account_id
       WHERE a.report_type = 'profit_and_loss' AND g.company_id = :co
         AND g.posting_date BETWEEN :from AND :to AND NOT g.is_closing
       GROUP BY 1, 2) t
WHERE net <> 0;
-- plus the equity offset per dimension combination
```

Set-based, in SQL, one statement — not a streamed cursor aggregated in Python (§5.3).
`is_closing boolean` replaces `is_period_closing_voucher_entry` and `voucher_type != 'Period
Closing Voucher'` filtering.

**`Account Closing Balance` becomes a materialised view**, not 34 submitted documents:

```sql
CREATE MATERIALIZED VIEW account_balance_snapshot AS
SELECT company_id, account_id, cost_center_id, project_id, dim1_id, dim2_id,
       date_trunc('month', posting_date)::date AS period,
       SUM(debit_base)  AS debit_base,
       SUM(credit_base) AS credit_base,
       SUM(debit_base - credit_base) AS net_base
FROM gl_entry GROUP BY 1,2,3,4,5,6,7;
CREATE UNIQUE INDEX ON account_balance_snapshot (company_id, account_id, cost_center_id,
        project_id, dim1_id, dim2_id, period);
```

`REFRESH MATERIALIZED VIEW CONCURRENTLY` after close. Because `gl_entry` is append-only (H1), a
refresh is **always correct** — there is no cumulative chain to break (§5.5 caveat 1), no
per-row document insert (caveat 2), and nothing to delete on cancellation (§5.6).

Cumulative balances are a window function over the view, not a merged carry-forward:

```sql
SELECT account_id, period,
       SUM(net_base) OVER (PARTITION BY company_id, account_id, cost_center_id ORDER BY period) AS cumulative
FROM account_balance_snapshot;
```

Per doc 24 §5.3, the materialised view is wrapped by a policy-bearing view so RLS still applies.

### 9.3 One closing mechanism covers inventory

`stock_valuation_state` is already a projection (D6). A period-end inventory snapshot is the same
materialised-view pattern keyed by `(item_id, warehouse_id, serial_batch_id, period)`, refreshed by
the same close operation — **in the same transaction as the GL close**, so accounts and inventory
cannot be closed to different dates (§6).

The FIFO queue does not need serialising into JSON (§6): it lives in `stock_valuation_layer` rows
(one per unconsumed receipt lot) which are ordinary tuples, so a snapshot is a `WHERE posted_at <=
:as_of` read.

### 9.4 Opening balances are a first-class operation

```sql
CREATE TABLE opening_balance_run (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    as_of_date    date NOT NULL,
    suspense_account_id uuid NOT NULL REFERENCES account(id),
    state         opening_state NOT NULL,   -- 'draft','posted','balanced','closed'
    UNIQUE (company_id)                      -- one per company, ever
);
```

- GL, AR/AP, and inventory openings all reference **one** `opening_balance_run`.
- `state = 'balanced'` is only reachable when the suspense account nets to zero — a
  **deferred constraint trigger**, not a convention (§7.4).
- `state = 'closed'` freezes it; the `UNIQUE (company_id)` means a company cannot be opened twice.
- Party creation is never implicit: an unknown party id is an FK violation, not a silently created
  master (§7.2).
- `suspense_account_id` is an explicit FK, not `frappe.get_all(...)[0]` (§7.2).

### 9.5 Contiguity kept

ERPNext's `validate_start_and_end_date` (§5.1) computing the required start date is **good** and we
keep it, as a trigger: a new `accounting_period` for a company must start the day after the latest
existing one. Combined with `EXCLUDE USING gist`, periods are provably contiguous and
non-overlapping — properties ERPNext achieves for PCV but not for `Accounting Period` (which merely
forbids overlap, permitting gaps).

---

## 10. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Mechanisms controlling "is this date closed?" | **4** (Accounting Period, `acc_frozen_upto`, PCV chain, Stock Closing Entry) | 1 (`accounting_period.state`) |
| Which documents a period closes | `period_closing_doctypes` in `hooks.py` | every ledger, by trigger |
| Effective date per doctype | `if/elif` chain | `posting_date`, uniformly |
| Exempt document types | `Bank Clearance`, unconditionally | none |
| Bypass | `exempted_role`, unrecorded | `period_override` with `granted_by`, `reason`, `expires_at` |
| Re-open | flip `disabled`, no audit | state transition + `lifecycle_event` |
| Future/pre-emptive close | **forbidden** | allowed |
| Period overlap | validated by scan | `EXCLUDE USING gist` |
| Period gaps | permitted for Accounting Period | forbidden (contiguity trigger) |
| Statutory permanent lock | not expressible | `permanently_closed` state |
| Year-end implementations | **2**, chosen by a setting, with duplicated algorithms | 1 |
| Balance computation | streamed cursor + Python aggregation | one `INSERT … SELECT … GROUP BY` |
| Algorithm depends on table size | yes (`> 100_000`) | no |
| Pause/resume needed | yes | no |
| Closing snapshot | 34 submitted documents, cumulative chain | materialised view, refreshable |
| Broken chain risk | yes (cancelled mid-year PCV) | none — derived from the ledger |
| P&L snapshot discriminator | `is_period_closing_voucher_entry` 0/1, two rows per account | `is_closing` on the ledger row; the view has no duplicate grain |
| Cancellation of a close | deletes ACB rows, `ignore_linked_doctypes` for 5 doctypes | reversal voucher; view refresh |
| Stock vs accounts close | unlinked | same operation, same transaction |
| FIFO snapshot | JSON-serialised queue | `stock_valuation_layer` rows |
| Opening balance completeness | convention | `state='balanced'` enforced by trigger |
| Opening party creation | implicit, from an ID | FK violation |
| A string index used as a date | fixed bug, silent on MariaDB (`:87`–`:89`) | impossible — `date` columns, strict database |

---

## 11. Invariants exercised

- **F1** every voucher balances in base currency — including the closing voucher, per dimension
  combination.
- **P1** (new) `accounting_period` ranges per company are **non-overlapping and contiguous**
  (`EXCLUDE USING gist` + contiguity trigger).
- **P2** (new) no ledger row may exist with a `posting_date` inside a `closed` period without a
  live `period_override` covering the actor and resource.
- **P3** (new) after a period close, `Σ (debit_base − credit_base)` over all
  `report_type = 'profit_and_loss'` accounts for that period, including `is_closing` rows, is
  **exactly zero** per dimension combination.
- **P4** (new) `opening_balance_run` may reach `state = 'balanced'` only when its suspense account
  nets to zero.
- **H1** ledgers append-only, so closing snapshots are always reproducible and a cancelled close
  leaves a reversal rather than a hole.
- **S5** `settlement.effective_date` respects the same period gate (S02 §12.9) — one mechanism, so
  advance adjustment cannot slip into a closed period the way `adv_adj=1` does
  (doc 11 §4.2, S02 §9.2c).

---

Cross-references: doc 07 (period control, closing, opening balances — the subsystem reference),
doc 01 §7 (`is_cancelled`, immutable ledger), doc 12 (dimensions and budgets),
doc 21 §2.2 (`period_closing_doctypes`), doc 22 §2 (the batch-process pattern),
doc 24 §5.3 (materialised views and RLS), doc 26 (chart of accounts and dimensions),
doc 27 (Stock Reconciliation, Stock Closing Entry), **[S02](S02-payments-and-allocation.md)** §12.9,
**[S06](S06-multi-currency.md)** (reporting currency), `docs/design/FINAL-SCHEMA.md`.
