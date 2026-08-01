# 1. The GL posting engine

How a submitted document becomes balanced, validated, immutable ledger rows.

Primary files:
- `accounts/general_ledger.py` (739 lines) — the engine
- `accounts/services/gl_validator.py` — all map-level gates
- `accounts/services/base_gl_composer.py` — how a single GL row is assembled (`get_gl_dict`)
- `accounts/doctype/gl_entry/gl_entry.py` — per-row validation on insert
- `accounts/utils.py` — balance reads (`get_balance_on`), immutable-ledger flag

---

## 1.1 The call chain

```
<voucher>.on_submit()
  └─ <voucher>.make_gl_entries()                     # per doctype, e.g. sales_invoice.py:1030
       ├─ gl_map = <Doctype>GLComposer(doc).compose()  # <doctype>/services/gl_composer.py
       │     └─ get_gl_dict(doc, args, ...)            # services/base_gl_composer.py:27
       ├─ make_gl_entries(gl_map, ...)                 # accounts/general_ledger.py:34
       └─ make_exchange_gain_loss_journal()            # services/exchange_gain_loss.py
```

`gl_map` is a list of `frappe._dict` rows for **one voucher**. `gl_map[0]` is treated as
authoritative for `company`, `posting_date`, `voucher_type`, `voucher_no` — a real coupling to be
aware of: validation only ever inspects the first row's date and company.

## 1.2 `make_gl_entries` — exact order (accounts/general_ledger.py:34-74)

```
if not gl_map: return                       # silent no-op
if not cancel:
    BudgetValidation(gl_map).validate()             # unless Accounts Settings.use_legacy_budget_controller
                                                   # skipped for Period Closing Voucher
    make_acc_dimensions_offsetting_entry(gl_map)    # :77-111  appends mirror rows
    validate_accounting_period(gl_map)              # gl_validator.py:40
    validate_disabled_accounts(gl_map)              # gl_validator.py:21
    gl_map = process_gl_map(gl_map, merge_entries)  # :141-153
    if len(gl_map) > 1:
        create_payment_ledger_entry(...)            # skipped for Period Closing Voucher
        save_entries(gl_map, ...)                   # :359-374
    elif gl_map:
        throw("Incorrect number of General Ledger Entries found...")
else:
    make_reverse_gl_entries(...)                    # :593
```

> **Invariant** A voucher produces either **zero** rows or **at least two**. A single surviving row
> is always an error (it cannot balance).

### `process_gl_map` (:141-153) — three transformations, in order

1. **Cost-center allocation split** (`distribute_gl_based_on_cost_center_allocation`, :156-192).
   If an active `Cost Center Allocation` exists for the row's cost center
   (`valid_from <= posting_date`, newest first, `@request_cache`d at :195), the row is deep-copied
   per sub-cost-center and `debit`, `credit`, `debit_in_account_currency`,
   `credit_in_account_currency` are each scaled `flt(value * pct/100, precision)`.
   ⚠ `debit_in_transaction_currency` is **not** scaled — a live asymmetry.

2. **Merge** (`merge_similar_entries`, :226-280). Merge key (`get_merge_properties`, :282-298):
   ```
   (account, cost_center, party, party_type, voucher_detail_no,
    against_voucher, against_voucher_type, project, finance_book, voucher_no,
    advance_voucher_type, advance_voucher_no, *enabled_accounting_dimensions)
   ```
   All six amount columns are summed. Rows flagged `_skip_merge` bypass merging (only producer:
   `purchase_invoice/services/gl_composer.py:123`). Afterwards, rows where **both** `debit` and
   `credit` round to 0 are dropped — *except* for Journal Entries whose
   `voucher_type == "Exchange Gain Or Loss"`, where zero-amount legs are meaningful.
   Note `debit_in_reporting_currency` is not merged; it is recomputed per row later.

3. **Sign normalisation** (`toggle_debit_credit_if_negative`, :316-351), per row, for the three
   pairs `debit/credit`, `*_in_account_currency`, `*_in_transaction_currency`:
   ```
   if debit<0 and credit<0 and debit==credit: negate both
   if debit  < 0: credit -= debit ; debit  = 0
   if credit < 0: debit  -= credit; credit = 0
   if row.post_net_value and debit and credit: keep only the larger side (net presentation)
   ```

> **Invariant** No negative amount is ever stored in `GL Entry`. Direction is expressed *only* by
> which of debit/credit is non-zero. Composers may freely emit negative debits; the engine flips them.

### `save_entries` (:359-374)

```
if not from_repost: validate_cwip_accounts(gl_map)        # gl_validator.py:73  (Journal Entry only)
process_debit_credit_difference(gl_map)                   # :372  balance + round-off
dimension_filter_map = get_dimension_filter_map()
check_freezing_date(gl_map[0].posting_date, company, adv_adj)
is_opening = any(d.is_opening == "Yes")
if voucher_type != "Period Closing Voucher": validate_against_pcv(is_opening, posting_date, company)
for entry in gl_map:
    validate_allowed_dimensions(entry, dimension_filter_map)
    make_entry(entry, adv_adj, update_outstanding, from_repost)   # one doc insert+submit per row
```

`make_entry` (:377-391) creates a `GL Entry` doc and `submit()`s it — **one document insert per
row**, no bulk insert. `GL Entry.autoname` is a random 10-char hash with `to_rename = 1`; a scheduled
`rename_gle_sle_docs` job later renames them to the series (gl_entry.py:75-82, and the job at gl_entry.py:494-523).

## 1.3 Balancing and rounding (`process_debit_credit_difference`, :397-426)

```
precision = precision of GL Entry.debit in company currency          # normally 2
allowance  = 5.0/10**precision  (= 0.05)  for Journal Entry / Payment Entry
           = 0.5                          for every other voucher type
diff, trx_diff = get_debit_credit_difference(gl_map, precision)      # :404, also rounds rows in place
if abs(diff) > allowance:
    throw "Debit and Credit not equal for {vt} #{vn}. Difference is {diff}."
        unless JE with voucher_type == "Exchange Gain Or Loss"
elif abs(diff) >= 1.0/10**precision:                                  # 0.01 .. allowance
    make_round_off_gle(gl_map, diff, trx_diff, precision)             # :435
recompute; if still > allowance: throw
```

- Balancing is checked **only in company (base) currency**. Account-currency and
  transaction-currency legs are never balance-checked.
- The 0.5 allowance for trade documents is deliberately loose — it exists so tax rounding cannot
  block a submit; the residue is pushed to the round-off account.
- `make_round_off_gle` (:475-558) posts the residue to `Company.round_off_account`
  (fallback `default_expense_account`) at `Company.round_off_cost_center`; if **any** row has
  `is_opening == "Yes"` it must instead use `Company.round_off_for_opening` and throws if unset.
  It first tries to fold the diff into an existing row on that account and removes that row if the
  result falls under 0.01. Dimensions for the new row come from `update_accounting_dimensions`
  (:543-568): parent-doc values when the voucher has every dimension field, else the per-company
  `default_dimension` for dimensions mandatory for the account's `report_type`.
- **Exchange differences are not absorbed here.** They are posted as a separate system-generated
  Journal Entry with `voucher_type = "Exchange Gain Or Loss"` (`services/exchange_gain_loss.py`),
  which is exactly why that subtype is exempted from: the balance check, twice, in
  `process_debit_credit_difference` (`accounts/general_ledger.py:413` and `:425`, either side of
  `make_round_off_gle`), the zero-amount merge filter in `merge_similar_entries` (`:273`), the
  zero-amount row check (`accounts/doctype/gl_entry/gl_entry.py:163`) and `update_outstanding_amt`
  (`:109`).

> **Ours** Balance in base currency with **zero tolerance**, enforced by a deferred constraint
> trigger over the voucher. Rounding residue is computed and posted explicitly by the calculation
> layer, not discovered by the ledger. If a document cannot produce a balanced set, it does not post.

## 1.4 Validation gates (`services/gl_validator.py`)

| Gate | Line | Rule | Bypass |
|---|--:|---|---|
| `validate_disabled_accounts` | 21 | no row may hit `Account.disabled = 1` | none |
| `validate_accounting_period` | 40 | join `Accounting Period` ⋈ `Closed Document` on company, `disabled=0`, `closed=1`, `document_type == voucher_type`, `start_date <= posting_date <= end_date` → `ClosedAccountingPeriod` | `Accounting Period.exempted_role` |
| `validate_cwip_accounts` | 73 | Journal Entry may not touch `account_type = "Capital Work in Progress"` when any Asset Category has CWIP accounting | none |
| `check_freezing_date` | 98 | `getdate(posting_date) <= Company.accounts_frozen_till_date` → throw | `Company.role_allowed_for_frozen_entries`, **but Administrator is explicitly excluded**; and `adv_adj=True` skips the check entirely |
| `validate_against_pcv` | 135 | `posting_date <= MAX(submitted PCV.period_end_date)` → "Period Closed"; plus any `is_opening` row is rejected outright once **any** PCV exists | **none** |
| `validate_allowed_dimensions` | 150 | per (dimension, account): mandatory-and-empty → `MandatoryAccountDimensionError`; Allow-list violation or Restrict-list hit → `InvalidAccountDimensionError` | none |

Note two deliberate design quirks worth copying or rejecting consciously:
- **Administrator cannot bypass the freeze date** (docstring at gl_validator.py:96: Administrator
  holds every role, so the role check would always pass; they hard-code the exclusion).
- **`adv_adj=True` bypasses the freeze**, which is how internal adjustments and reposts get past a
  frozen period. That is a real hole: a repost can write into a frozen period.

> **Ours** One `posting_guard(company_id, posting_date, doc_type, is_opening)` function called from a
> single place, with an explicit `override_reason` + `overridden_by` audit column when a privileged
> role bypasses it. No implicit bypass flag like `adv_adj`.

## 1.5 Building one GL row (`accounts/services/base_gl_composer.py`, `get_gl_dict` :27-123)

Order matters:

1. `posting_date = args.posting_date or doc.posting_date`; resolve fiscal year via
   `get_fiscal_years(posting_date, company)` — **throws if more than one matches**
   ("Multiple fiscal years exist for the date … Please set company in Fiscal Year").
2. Seed: company, posting_date, fiscal_year, `voucher_type = doc.doctype`, `voucher_no = doc.name`,
   remarks, all four amount columns zeroed, `is_opening = doc.is_opening or "No"`, party fields None,
   project, `post_net_value`, `voucher_detail_no`, `voucher_subtype` (:40-60, `get_voucher_subtype`
   at :171).
3. Regional + app hooks (`update_gl_dict_with_regional_fields` :63,
   `update_gl_dict_with_app_based_fields`).
4. Dimensions: for each enabled dimension fieldname, `doc.get(dim)` overridden by `item.get(dim)`.
5. **`gl_dict.update(args)` (:75) — caller args win over everything above.**
6. `account_currency = account_currency or get_account_currency(account)`.
7. `validate_account_currency` (called at :88, defined at :206) — skipped for JE, PCV, PE, PR, PI
   **and Stock Entry**. Valid currencies are the company currency plus `doc.currency`.
8. `set_balance_in_account_currency` (called at :95, defined in
   `accounts/services/taxes.py:325-348`) — skipped for JE, PCV, PE.
   Only fills the account-currency leg **if still zero**:
   `debit_in_account_currency = debit` when account currency == company currency, else
   `flt(debit / conversion_rate, 2)` — note the **hard-coded precision 2**.
9. Transaction-currency leg (`accounts/services/base_gl_composer.py`,
   `get_value_in_transaction_currency` :200): reuse the account-currency
   value when the currencies coincide, else `base / conversion_rate`. Skipped for PI, SI, JE, PE,
   which set it explicitly (`exchange_gain_loss.py:205`).
10. `against_voucher_type` / `against_voucher` inherited from `doc` only if the caller did not supply
    them (:115-121).

### The four currency pairs and where each comes from

| Columns | Currency | Written by | Used for |
|---|---|---|---|
| `debit`, `credit` | company (base) | composer, from `base_*` document fields | **the only pair that is balance-checked**; round-off; `validate_balance_type` |
| `debit_in_account_currency`, `credit_in_account_currency` | the account's own | composer, else derived at step 8 | `update_outstanding_amt`, account-currency balances, the whole AR/AP subledger |
| `debit_in_transaction_currency`, `credit_in_transaction_currency` + `transaction_currency`, `transaction_exchange_rate` | the document's | step 9 or explicitly | reporting in document currency; merged and swapped on reversal, **not** balance-checked, **not** scaled by cost-center allocation |
| `debit_in_reporting_currency`, `credit_in_reporting_currency` + `reporting_currency_exchange_rate` | group/reporting | **only** `GLEntry.set_amount_in_reporting_currency` (gl_entry.py:302-335) | consolidated Trial Balance |

`set_amount_in_reporting_currency` throws `ReportingCurrencyExchangeNotFoundError` when no
`Currency Exchange` row exists for `Company.default_currency → Company.reporting_currency` on
`transaction_date or posting_date`. **A missing FX rate blocks posting entirely.**

> **Ours** Store `amount` + `currency_id` + `exchange_rate_used` once, and derive base/reporting
> amounts as generated columns or in the reporting layer. Four independently-written pairs is four
> chances to disagree; we saw one already (`*_in_transaction_currency` not scaled in the cost-center
> split).

## 1.6 Per-row enforcement (`gl_entry.py`)

`validate()` (:84-96): `validate_and_set_fiscal_year` → `pl_must_have_cost_center` →
[unless `from_repost` or PCV] `check_mandatory`, `validate_cost_center`, `check_pl_account`,
`validate_party`, `validate_currency` → `set_amount_in_reporting_currency` (always).

`on_update()` (:98-127): `validate_account_details` → `validate_dimensions_for_pl_and_bs` →
`validate_balance_type` → `validate_frozen_account` → then, **only for non-receivable/payable
accounts**, `update_outstanding_amt(...)` when `against_voucher_type` is one of
`Journal Entry, Sales Invoice, Purchase Invoice, Fees`.

Selected rules worth copying:
- `check_mandatory` (:128): a Receivable account row requires a Customer, a Payable row requires a
  Supplier ("{vt} {vn}: Customer is required against Receivable account {acct}"); and a row must have
  a non-zero debit or credit.
- `pl_must_have_cost_center` (:168): every `report_type = "Profit and Loss"` row needs a cost center.
- `validate_currency` (:269): the row's `account_currency` must equal the account's; and
  `validate_party_gle_currency` means **a party may only ever transact in one currency per company**.
- `validate_balance_type` (:338): if `Account.balance_must_be` is set, it runs
  `SELECT SUM(debit)-SUM(credit) FROM tabGL Entry WHERE is_cancelled=0 AND account=?` —
  **company-wide, all dates, no company filter, once per inserted row.** A guaranteed hot spot.
- `on_cancel` (:325) always throws: "Individual GL Entry cannot be cancelled." Rows are only ever
  reversed by `make_reverse_gl_entries`.

### Indexes it relies on (`on_doctype_update`, :462-490)

```
(voucher_type, voucher_no)
(posting_date, company)
(party_type, party)
-- Postgres only:
gle_active_detail (company, posting_date, account)          WHERE is_cancelled = 0
gle_active_cover  (company, account, posting_date)          WHERE is_cancelled = 0 INCLUDE (debit, credit)
```
The partial + covering indexes already exist for Postgres — directly reusable in our schema.

## 1.7 Cancellation and the immutable-ledger switch (`accounts/general_ledger.py`, `make_reverse_gl_entries` :607-726, `set_as_cancel` :728)

```
immutable = is_immutable_ledger_enabled()        # accounts/utils.py:2748 -> Accounts Settings.enable_immutable_ledger
gl_entries = SELECT * FROM `tabGL Entry` WHERE voucher_type=? AND voucher_no=? AND is_cancelled=0 FOR UPDATE
create_payment_ledger_entry(gl_entries, cancel=1, ...)
validate_accounting_period(gl_entries)
validation_date = today()                if immutable else original posting_date
check_freezing_date(validation_date, ...) ; validate_against_pcv(is_opening, validation_date, ...)

if partial_cancel:   UPDATE matching rows (by voucher_detail_no too) ...
elif not immutable:  UPDATE ... SET is_cancelled = 1 WHERE name IN (...)   # history mutated
for entry in gl_entries:
    new = deepcopy(entry); swap debit<->credit for all three pairs
    new.remarks = "On cancellation of " + voucher_no
    new.is_cancelled = 1
    if immutable: new.is_cancelled = 0 ; new.posting_date = today()
    if new.debit or new.credit: make_entry(new, ...)
```

So there are two entirely different semantics:

| | Originals | Reversal rows | Reversal date | Reports filter |
|---|---|---|---|---|
| **Immutable off** (legacy default) | `is_cancelled = 1` | `is_cancelled = 1` | original date | `WHERE is_cancelled = 0` everywhere |
| **Immutable on** | untouched | live (`is_cancelled = 0`) | **today** | no filter needed |

> **Ours** Immutable only. Reversal is always a new row set dated on the cancellation date, linked by
> `reverses_voucher_id`. Enforce with a rule/trigger: `UPDATE`/`DELETE` on `gl_entry` is denied
> outright, so `is_cancelled` does not need to exist and no query needs the filter.

## 1.8 The accounting-dimension escape hatch

`Accounting Dimension` is a master that **adds a column at runtime** to `GL Entry`, `Budget`, and
every transaction table. Supporting metadata:
`get_accounting_dimensions()` (accounting_dimension.py:250), `get_checks_for_pl_and_bs_accounts()`
(:263) for the mandatory-per-report-type rules, `get_dimension_with_children()` (:286) for tree
dimensions, and `accounting_dimension_filter` for allow/restrict lists.

Dimensions enter a GL row at four points: `get_gl_dict` step 4; offsetting rows copy them wholesale;
the round-off row gets them from `update_accounting_dimensions`; and they are part of the merge key
(so differing dimensions prevent merging).

There is also **automatic dimension balancing** (`make_acc_dimensions_offsetting_entry`, :77-111):
when a dimension is configured with `automatically_post_balancing_accounting_entry` and the voucher
uses more than one value of that dimension, a mirror row (debit/credit swapped, divided by the number
of qualifying dimensions) is appended on `dimension.offsetting_account`, with party and
against_voucher forced to None. This makes every dimension internally balanced — clever, and it
roughly doubles the row count.

> **Ours** No runtime DDL, ever. Fixed FK columns for the dimensions we ship (`cost_center_id`,
> `project_id`, `finance_book_id`, `department_id`) plus `gl_entry_dimension(gl_entry_id,
> dimension_id, value_id)` for user-defined ones. Keep the offsetting-account idea as an option per
> dimension — it is the only way to get a balanced per-dimension trial balance.

## 1.9 Balance reads

`get_balance_on(...)` (accounts/utils.py:204-355) builds raw SQL and runs one aggregate:

```sql
SELECT sum(round(debit[_in_account_currency], p)) - sum(round(credit[_in_account_currency], p))
FROM `tabGL Entry` gle
WHERE is_cancelled = 0
  [AND posting_date >= start_date] [AND posting_date <= date]
  [AND cost-center subtree via EXISTS on lft/rgt   -- only for Profit and Loss accounts]
  [AND (account subtree via EXISTS on tabAccount lft/rgt) OR gle.account = <account>]
  [AND gle.party_type = ? AND gle.party = ?]
  [AND gle.company = ?]
  [AND (finance_book IN (...) OR finance_book IS NULL)]
```
Behaviour to note: missing arguments are silently pulled from `frappe.form_dict` (:218); a
`FiscalYearError` for a **past** date returns `0.0` while a future date re-raises (:241); for a group
account in company currency `in_account_currency` is forced off (:284).

`get_count_on` (:358-476) is an **N+1 pattern**: it pulls all matching rows and, for
`invoiced_amount`/`payables`, runs a correlated `SUM(credit-debit)` per row. Do not copy.

Report shapes: `report/general_ledger/general_ledger.py — see report/general_ledger/general_ledger.py:160-223` (one raw SQL, ordered
`posting_date, account, creation`) and `report/trial_balance/trial_balance.py:144-320` (prefers the
`Account Closing Balance` snapshot — see doc 07). Note the date predicate
`(posting_date >= %(from_date)s OR is_opening = 'Yes')` which **defeats index range scans**, and the
`Accounts Settings.ignore_is_opening_check_for_reporting` toggle that exists to turn it off.

> **Ours** Balances come from `account_period_balance` (materialised per account × period ×
> dimensions, maintained in the posting transaction) with a fallback aggregate over `gl_entry` for
> ad-hoc dates. Never scan the ledger to answer "what is the balance of this account".

---

## What to take from this chapter

**Copy:** the map → validate → normalise → persist pipeline; line-level provenance
(`voucher_detail_no`); the merge key concept; reversal-not-mutation; the Postgres partial/covering
indexes; `report_type`-driven cost-center and dimension requirements.

**Reject:** four independently-written currency pairs; the 0.5 balance tolerance; per-row full-account
`SUM()` in `validate_balance_type`; one INSERT per row; runtime DDL for dimensions; `adv_adj`
silently bypassing the freeze date; `frappe.form_dict` fallbacks inside a balance function.
