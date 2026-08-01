# S06 — Multi-Currency: Invoice → Payment → FX Revaluation

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev). Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.
>
> Continues **[S01](S01-order-to-cash.md)** / **[S02](S02-payments-and-allocation.md)**. Multi-currency
> is where ERPNext's "store both figures on every row" approach is most defensible — and where the
> **four** simultaneous currency dimensions become genuinely hard to keep straight.

---

## 1. Four currencies, not two

Every amount in ERPNext potentially exists in four denominations:

| # | Name | Where it lives | Example |
|---|---|---|---|
| 1 | **Transaction currency** | `Sales Invoice.currency`, and every `*_fc`-style field (`grand_total`, `rate`, `amount`) | USD — what the customer is billed in |
| 2 | **Base / company currency** | `Company.default_currency`, `base_*` fields, `GL Entry.debit`/`credit` | INR — the books |
| 3 | **Account currency** | `Account.account_currency`, `GL Entry.debit_in_account_currency` | a USD bank account or a USD receivable |
| 4 | **Reporting currency** | `Company.reporting_currency`, `GL Entry.debit_in_reporting_currency` | EUR — group consolidation |

Dimensions 1 and 2 are the familiar pair. Dimension 3 exists because a *ledger account* can be
denominated — a USD bank account holds USD, and its balance in USD must be exact regardless of
what rate was used on any given day. Dimension 4 was added for group reporting (surfaced in
S05 §5.5 via `set_amount_in_reporting_currency`).

`GLEntry.set_amount_in_reporting_currency`
(`accounts/doctype/gl_entry/gl_entry.py:302`) populates dimension 4, and
`set_amount_in_reporting_currency`
(`accounts/doctype/account_closing_balance/account_closing_balance.py:156`) does the same for
closing snapshots.

`set_transaction_currency_and_rate_in_gl_map`
(`accounts/services/exchange_gain_loss.py:205`) carries dimension 1 onto GL rows, and
`AccountsController.set_transaction_currency_and_rate_in_gl_map`
(`controllers/accounts_controller.py:1366`) is the thin shim.

**The invariant that matters:** for a given GL row,
`debit == debit_in_account_currency × rate(account_currency → base)`. When that stops holding —
because the rate moved after posting — you have an unrealised FX position, which is what §6 exists
to measure.

---

## 2. Rate resolution — `get_exchange_rate`

`setup/utils.py:62`. This one function is the entire rate policy, and it has **five fallback
layers**.

```python
if not (from_currency and to_currency): return          # silent None
if from_currency == to_currency:        return 1
if not transaction_date: transaction_date = nowdate()

currency_settings = frappe.get_cached_doc("Accounts Settings")
allow_stale_rates = currency_settings.get("allow_stale")

filters = [["date", "<=", get_datetime_str(transaction_date)],
           ["from_currency", "=", from_currency],
           ["to_currency", "=", to_currency]]
if args == "for_buying":  filters.append(["for_buying", "=", "1"])
elif args == "for_selling": filters.append(["for_selling", "=", "1"])
if not allow_stale_rates:
    stale_days = currency_settings.get("stale_days")
    checkpoint_date = add_days(transaction_date, -stale_days)
    filters.append(["date", ">", get_datetime_str(checkpoint_date)])

entries = frappe.get_all("Currency Exchange", fields=["exchange_rate"], filters=filters,
                         order_by="date desc, name desc", limit=1)
if entries: return flt(entries[0].exchange_rate)                          # ← layer 1

if frappe.get_single_value("Currency Exchange Settings", "disabled"): return 0.00   # ← layer 2

pegged_currencies = {}
if currency_settings.allow_pegged_currencies_exchange_rates:
    pegged_currencies = get_pegged_currencies()                            # :13
    if rate := get_pegged_rate(pegged_currencies, from_currency, to_currency, transaction_date):
        return rate                                                        # ← layer 3
try:
    ... HTTP call to Currency Exchange Settings.api_endpoint, cached 6h ...  # ← layer 4
    return flt(value)
except Exception:
    frappe.log_error("Unable to fetch exchange rate")
    frappe.msgprint(_("Unable to find exchange rate for {0} to {1} for key date {2}. "
                      "Please create a Currency Exchange record manually"))
    return 0.0                                                             # ← layer 5
```

### 2.1 Findings

1. **Three distinct code paths return `0` as a rate**: layer 2 (`return 0.00`), layer 5
   (`return 0.0`), and a missing `from_currency`/`to_currency` returns bare `None` (`:69`).
   A zero rate silently makes every `base_*` amount zero — and S05 showed
   `reconcile_header_tax_totals`-style arithmetic multiplying by a rate without checking it. The
   caller is expected to notice; nothing enforces `rate > 0`.

2. **The rate is directional and purpose-specific.** `Currency Exchange` has `for_buying` and
   `for_selling` flags, so USD→INR can legitimately have two different rates on the same date.
   `CurrencyExchange.autoname` (`setup/doctype/currency_exchange/currency_exchange.py:29`) bakes the
   purpose into the primary key:

   ```python
   purpose = "Selling-Buying"
   if cint(self.for_buying) == 0 and cint(self.for_selling) == 1: purpose = "Selling"
   if cint(self.for_buying) == 1 and cint(self.for_selling) == 0: purpose = "Buying"
   self.name = "{}-{}-{}{}".format(formatdate(get_datetime_str(self.date), "yyyy-MM-dd"),
                                   self.from_currency, self.to_currency,
                                   ("-" + purpose) if purpose else "")
   ```

   So the PK is `2026-08-01-USD-INR-Selling`. Changing the flags on an existing record changes its
   identity, which means a rename cascade (doc 09 §6). And **a rate record with both flags set has
   a different name** from either single-purpose record — three rows can coexist for one
   (date, pair), and `order_by="date desc, name desc"` picks by **string ordering of the name**
   when dates tie. `"…-Selling"` > `"…-Selling-Buying"` > `"…-Buying"` lexically, so the tie-break
   is alphabetical, not semantic.

3. **`validate`** (`setup/doctype/currency_exchange/currency_exchange.py:48`) enforces
   `exchange_rate > 0`, `from != to`, and at least one of buying/selling — good, but it does
   **not** prevent two records for the same (date, pair, purpose) if the name differs, nor is there
   a uniqueness constraint on the tuple.

4. **Staleness is a global setting.** `Accounts Settings.allow_stale` / `stale_days` decide whether
   an old rate may be used, for the whole installation. There is no per-currency-pair policy — a
   pair that publishes daily and one that publishes monthly get the same tolerance.

5. **Layer 4 makes an HTTP request during document validation.** `requests.get(...)` inside
   `get_exchange_rate`, cached in Redis for 6 hours (`cache.setex(..., time=21600, ...)`). So saving
   an invoice can block on a third-party API, and the response is walked by a
   **configurable key path** (`settings.result_key`, applied through
   `format_ces_api`, `setup/utils.py:165`) — a JSON path stored as rows.

### 2.2 Pegged currencies

`get_pegged_currencies` (`setup/utils.py:13`) loads `Pegged Currency Details` rows
(`source_currency`, `pegged_against`, `pegged_exchange_rate`).
`get_pegged_rate` (`setup/utils.py:30`) handles four cases:

```python
if from_currency in pegged_map and to_currency in pegged_map:
    if from_entry["pegged_against"] == to_entry["pegged_against"]:            # case 1
        return (1 / from_entry["ratio"]) * to_entry["ratio"]
    base_rate = get_exchange_rate(from_entry["pegged_against"], to_entry["pegged_against"], transaction_date)
    if not base_rate: return None
    return (1 / from_entry["ratio"]) * base_rate * to_entry["ratio"]          # case 2 (recursive)
if from_entry and from_entry["pegged_against"] == to_currency:                 # case 3
    return flt(from_entry["ratio"])
if to_entry and to_entry["pegged_against"] == from_currency:                   # case 4
    return 1 / flt(to_entry["ratio"])
return None
```

Correct cross-rate arithmetic for pegs (AED and SAR both pegged to USD → derive AED/SAR exactly).
Case 2 **recurses into `get_exchange_rate`**, which can reach layer 4 — so a pegged cross-rate can
trigger an HTTP call. And in layer 4 the peg is applied *after* the API call
(`setup/utils.py:141`–`:145`): the API is asked for the *base* pair and the ratios are then applied
by multiplication/division.

No guard against a **peg cycle** (A pegged to B, B pegged to A) — case 2 would recurse until the
`from`/`to` pair resolves or the API answers.

---

## 3. Stage 1 — the invoice

**AlphaCo** (base INR, reporting EUR) invoices **US-CORP** in **USD**.

| | |
|---|---|
| Invoice | SI-USD-001, 2026-06-10 |
| Net | USD 20 000.00 |
| Receivable account | `Debtors - USD`, `account_currency = USD` |
| Rate USD→INR on 10 Jun | **83.50** |
| Rate INR→EUR on 10 Jun | 0.0110 |

`AccountsController.set_price_list_currency`
(`controllers/accounts_controller.py:640`) resolves the price-list currency and
`check_conversion_rate` (`controllers/accounts_controller.py:1308`) validates
`conversion_rate`. `calculate_taxes_and_totals` (`:576`) then produces both denominations —
doc 05 covers the pipeline; the relevant part here is that **every monetary field has a `base_`
twin**, computed as `field × conversion_rate` and rounded independently.

GL on submit:

| Account | `debit` (INR) | `credit` (INR) | `debit_in_account_currency` | `credit_in_account_currency` | account ccy |
|---|---:|---:|---:|---:|---|
| `Debtors - USD` | 1 670 000.00 | | 20 000.00 | | USD |
| `Sales — Revenue` | | 1 670 000.00 | | 1 670 000.00 | INR |

Note the revenue line: its account is INR, so its account-currency amount **equals** its base
amount. Only the receivable carries a genuine USD figure.

`GLEntry.set_amount_in_reporting_currency` (`accounts/doctype/gl_entry/gl_entry.py:302`) adds
dimension 4: `1 670 000 × 0.0110 = EUR 18 370.00`.

`Payment Ledger Entry` (doc 04, S02 §3.2) mirrors the receivable — and this is the important
detail: **PLE stores `amount` in account currency and `amount_in_account_currency` separately**, so
outstanding in USD stays exact while base-currency outstanding is a derived figure.

`Sales Invoice.outstanding_amount = 20 000.00` — **in transaction currency**.

---

## 4. Stage 2 — payment at a different rate (realised gain/loss)

Customer pays **USD 20 000** on 2026-07-20. Rate USD→INR that day: **84.90**.

The customer's obligation was USD 20 000 and they paid USD 20 000 — the *receivable in USD is
fully settled*. But the books recorded INR 1 670 000 and we received INR 1 698 000. The
**INR 28 000 difference is a realised exchange gain**.

### 4.1 Where the difference is computed

`PaymentEntry.set_amounts` (`accounts/doctype/payment_entry/payment_entry.py:953`) and
`set_difference_amount` (`:1166`) compute it; each `Payment Entry Reference` row carries
`exchange_rate` and `exchange_gain_loss`.

For the advance case, `set_advance_gain_or_loss`
(`accounts/services/advances.py:128`) does the equivalent on the invoice side (S02 §7.4) — with the
early return that silently skips gain/loss when
`get_account_currency(party_account) != doc.currency`.

### 4.2 The gain/loss journal

`make_exchange_gain_loss_journal` (`accounts/services/exchange_gain_loss.py:49`):

```python
if doc.docstatus != 1: return
if dimensions_dict is None:
    dimensions_dict = frappe._dict()
    for dim in get_dimensions()[0]:
        dimensions_dict[dim.fieldname] = doc.get(dim.fieldname)

if doc.get("doctype") == "Journal Entry":
    for arg in args:
        if (flt(arg.get("difference_amount", 0), precision) != 0
                or flt(arg.get("exchange_gain_loss", 0), precision) != 0) and arg.get("difference_account"):
            difference_amount = arg.get("difference_amount") or arg.get("exchange_gain_loss")
            if difference_amount > 0:
                dr_or_cr = "debit" if arg.get("party_type") == "Customer" else "credit"
            else:
                dr_or_cr = "credit" if arg.get("party_type") == "Customer" else "debit"
            reverse_dr_or_cr = "debit" if dr_or_cr == "credit" else "credit"
            if not gain_loss_journal_already_booked(gain_loss_account, difference_amount,
                                                    doc.doctype, doc.name, arg.get("referenced_row")):
                posting_date = (arg.get("difference_posting_date")
                                or frappe.db.get_value(arg.voucher_type, arg.voucher_no, "posting_date"))
                je = create_gain_loss_journal(...)                # accounts/utils.py:2534
                frappe.msgprint(_("Exchange Gain/Loss amount has been booked through {0}"))

if doc.get("doctype") == "Payment Entry":
    gain_loss_to_book = [x for x in doc.references if x.exchange_gain_loss != 0]
    ...
```

So the FX difference is **a separate `Journal Entry` with `voucher_type = 'Exchange Gain Or Loss'`**,
not extra lines on the payment. Consequences:

- The payment voucher balances on its own; the FX journal balances on its own. Two vouchers for one
  economic event, linked only by `reference_type`/`reference_name`/`reference_detail_no` on the
  journal's child rows.
- **Idempotency is by content comparison**, not by a key. `gain_loss_journal_already_booked`
  (`accounts/services/exchange_gain_loss.py:14`):

  ```python
  res = frappe.db.get_all("Journal Entry Account", filters={
      "docstatus": 1, "account": gain_loss_account, "reference_type": ref2_dt,
      "reference_name": ref2_dn, "reference_detail_no": ref2_detail_no}, pluck="parent")
  if exc_vouchers := frappe.db.get_all("Journal Entry",
          filters={"name": ["in", res], "voucher_type": "Exchange Gain Or Loss"},
          fields=["voucher_type", "total_debit", "total_credit"]):
      booked_voucher = exc_vouchers[0]
      if (booked_voucher.total_debit == exc_gain_loss
              and booked_voucher.total_credit == exc_gain_loss
              and booked_voucher.voucher_type == "Exchange Gain Or Loss"):
          return True
  return False
  ```

  ⚠️ **`booked_voucher.total_debit == exc_gain_loss` is raw float equality on money** — the same
  class of defect as `advance_payment_status` (S02 §7.2). And it inspects only
  `exc_vouchers[0]`, discarding any others. If the amount differs by a rounding unit, the check
  returns `False` and **a second gain/loss journal is booked**, double-counting the FX.

- `is_payable_account` (`accounts/services/exchange_gain_loss.py:196`) decides the sign for
  supplier-side entries.

Resulting FX journal:

| Account | Debit (INR) | Credit (INR) |
|---|---:|---:|
| `Debtors - USD` | 28 000.00 | |
| Exchange Gain / Loss | | 28 000.00 |

`create_gain_loss_journal` (`accounts/utils.py:2534`) builds it;
`cancel_exchange_gain_loss_journal` (`accounts/utils.py:847`),
`delete_exchange_gain_loss_journal` (`accounts/utils.py:872`), and
`get_linked_exchange_gain_loss_journal` (`accounts/utils.py:897`) manage its lifecycle — invoked
from `AccountsController.on_cancel` (`controllers/accounts_controller.py:1109`) and
`on_trash` (`:419`), doc 09 §3.2.

### 4.3 The full picture after payment

| | USD | INR |
|---|---:|---:|
| Invoice | 20 000.00 | 1 670 000.00 |
| Payment | (20 000.00) | (1 698 000.00) |
| FX journal | — | 28 000.00 |
| **Receivable balance** | **0.00** | **0.00** |

Both denominations close to zero. That is the correct outcome, achieved with **three vouchers**
(invoice, payment, FX journal) and the settlement recorded in five places (S02 §2).

---

## 5. Stage 3 — a partially-paid foreign invoice at period end

Second invoice **SI-USD-002**, 2026-08-05, USD 50 000 at rate 84.20 → INR 4 210 000.
Customer pays USD 30 000 on 2026-08-25 at 85.10.

Realised gain on the paid portion: `30 000 × (85.10 − 84.20) = INR 27 000`.

Remaining: **USD 20 000 outstanding, carried in the books at 84.20 = INR 1 684 000.**

At 31 Aug the rate is **85.60**. The receivable is *really* worth INR 1 712 000. The books are
understated by **INR 28 000** — an **unrealised** gain. Nothing has posted it, because no
transaction occurred. That is what §6 fixes.

---

## 6. Stage 4 — `Exchange Rate Revaluation`

`ExchangeRateRevaluation` (`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:20`).

### 6.1 Finding the exposed balances

`fetch_and_calculate_accounts_data` (`:159`) → `get_accounts_data` (`:167`) →
`get_account_balance_from_gle` (`:187`), then
`calculate_new_account_balance` (`:280`).

The core computation (`:280`):

```python
for d in [x for x in account_details if not x.zero_balance]:
    current_exchange_rate = (d.balance / d.balance_in_account_currency
                             if d.balance_in_account_currency else 0)
    new_exchange_rate = get_exchange_rate(d.account_currency, company_currency, posting_date)
    new_balance_in_base_currency = flt(d.balance_in_account_currency * new_exchange_rate)
    gain_loss = flt(new_balance_in_base_currency, precision) - flt(d.balance, precision)
```

`current_exchange_rate` is **derived by division** — `base_balance / account_currency_balance` —
i.e. the *implied blended rate* of everything booked so far, not any rate that was ever quoted.
That is the right approach for revaluation, and it means the guard
`if d.balance_in_account_currency else 0` silently yields a zero implied rate when the account
currency balance is zero (handled by the second branch).

Our case: `4 210 000 − (30 000 × 84.20) = 1 684 000` base against `20 000` USD →
implied rate `84.20`. New rate `85.60` → new base `1 712 000` → **`gain_loss = +28 000`**. ✓

### 6.2 The zero-balance case

The second loop (`:316`–`:352`) handles accounts where one denomination is zero and the other is
not — the residue of rounding and of settlements that closed one side but not the other:

```python
for d in [x for x in account_details if x.zero_balance]:
    if d.balance != 0:                          # base non-zero, account ccy zero
        current_exchange_rate = new_exchange_rate = 0
        new_balance_in_account_currency = 0
        new_balance_in_base_currency = 0
        gain_loss = flt(new_balance_in_base_currency, precision) - flt(d.balance, precision)
    else:                                       # base zero, account ccy non-zero
        new_exchange_rate = 0
        new_balance_in_base_currency = 0
        new_balance_in_account_currency = 0
        current_exchange_rate = (calculate_exchange_rate_using_last_gle(
            company, d.account, d.party_type, d.party) or 0.0)          # :649
        gain_loss = new_balance_in_account_currency - (current_exchange_rate * d.balance_in_account_currency)
```

⚠️ Note the first branch: `new_exchange_rate` is forced to **0**, and the entire base balance is
written off as gain/loss. That is arguably correct (a zero foreign balance *should* have zero base
value) but it is doing so by **setting the rate to zero**, which then appears in the
`Exchange Rate Revaluation Account` child row as the "new exchange rate" — a stored rate of 0.

`calculate_exchange_rate_using_last_gle` (`:649`) recovers an implied rate from the most recent GL
entry when the base balance is zero.

`throw_invalid_response_message` (`:356`) distinguishes "no outstanding invoices" from
"none require revaluation".

### 6.3 Posting the revaluation

`validate` (`:43`) → `validate_rounding_loss_allowance` (`:47`),
`set_total_gain_loss` (`:51`), `validate_mandatory` (`:74`);
`before_submit` (`:78`) → `remove_accounts_without_gain_loss` (`:81`).

`make_jv_entries` (`:374`) dispatches to:

- `make_jv_for_zero_balance` (`:393`) — writes off the stranded one-sided balances (§6.2);
- `make_jv_for_revaluation` (`:506`) — the ordinary unrealised gain/loss journal.

`get_for_unrealized_gain_loss_account` (`:363`) resolves the P&L account
(`Company.unrealized_exchange_gain_loss_account`).

Our journal, 31 Aug:

| Account | Debit (INR) | Credit (INR) |
|---|---:|---:|
| `Debtors - USD` | 28 000.00 | |
| Unrealized Exchange Gain / Loss | | 28 000.00 |

Note the `debit_in_account_currency` on the receivable line is **0** — the USD balance does not
change, only its INR translation.

### 6.4 Reversal on the first of the next month

`make_reverse_journal` (`:605`) and `check_journal_and_reversal` (`:97`), with
`on_cancel` (`:93`).

Unrealised revaluation is conventionally **reversed at the start of the next period**, so the
underlying receivable returns to its historical rate and the next revaluation computes from a clean
base. ERPNext supports this via a reversal journal — and `check_journal_and_reversal` (`:97`)
guards the pairing.

⚠️ But the reversal is a **separate document that someone must create**, and the schedule that
would create it automatically is `auto_create_exchange_rate_revaluation_daily/weekly/monthly`
(`accounts/utils.py:2003`, `:2010`, `:2017`) → `_auto_create_exchange_rate_revaluation_for`
(`accounts/utils.py:1983`) and `create_err_and_its_journals` (`accounts/utils.py:1965`). So
whether your unrealised FX is reversed depends on a **scheduled job running** (doc 22 §2.2 — and
recall dormant sites skip scheduled jobs entirely).

---

## 7. Full write trace

| Stage | Vouchers | GL rows | PLE rows | Notes |
|---|---:|---:|---:|---|
| SI-USD-001 | 1 | 2 | 1 | 4 currency figures per row |
| Payment (full, rate moved) | 1 | 2 | 1 | |
| FX gain journal | **1** | 2 | 0 | separate `Exchange Gain Or Loss` JE |
| SI-USD-002 | 1 | 2 | 1 | |
| Partial payment | 1 | 2 | 1 | |
| FX gain journal | **1** | 2 | 0 | |
| Exchange Rate Revaluation, 31 Aug | 1 (+1 JE) | 2 | 0 | unrealised |
| Reversal, 1 Sep | 1 JE | 2 | 0 | if the job ran |
| **Total** | **8 vouchers** | **16** | **5** | for two invoices and two payments |

**Eight vouchers for two sales.** Half of them exist purely to record currency movement.

---

## 8. Same scenario in our design

### 8.1 Store the pair, derive the rest

Per decision **D1** (`numeric(19,4)` money, `numeric(21,9)` rates), every monetary row stores
**exactly two** figures plus the rate that relates them:

```sql
CREATE TABLE gl_entry (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid NOT NULL REFERENCES company(id),
    voucher_id        uuid NOT NULL REFERENCES voucher(id),
    account_id        uuid NOT NULL REFERENCES account(id),
    -- account currency (dimension 3): exact, never derived
    amount_acct       numeric(19,4) NOT NULL,          -- signed; + debit, − credit
    account_currency  char(3) NOT NULL,
    -- base currency (dimension 2): the books
    amount_base       numeric(19,4) NOT NULL,
    rate_acct_to_base numeric(21,9) NOT NULL,
    -- transaction currency (dimension 1) lives on the voucher, not repeated per row
    posting_date      date NOT NULL,
    CONSTRAINT gl_rate_positive CHECK (rate_acct_to_base > 0),
    CONSTRAINT gl_base_consistent CHECK (
        abs(amount_base - round(amount_acct * rate_acct_to_base, 4)) <= 0.0001
    )
);
```

Three changes with real consequences:

- **`CHECK (rate_acct_to_base > 0)`** makes a zero rate impossible. The three code paths in
  `get_exchange_rate` that return `0` (§2.1) cannot corrupt the ledger — the insert fails.
- **`CHECK (gl_base_consistent)`** makes the relationship between the two denominations a
  *database invariant*, not an arithmetic convention. A bug in the totals pipeline that produces
  mismatched `base_*` fields is caught at insert.
- **Signed single amounts** instead of four columns (`debit`, `credit`,
  `debit_in_account_currency`, `credit_in_account_currency`) removes the
  `toggle_debit_credit_if_negative` step entirely (doc 01, `accounts/general_ledger.py:316`).

**Reporting currency (dimension 4) is not stored.** It is a view:

```sql
CREATE VIEW gl_entry_reporting AS
SELECT g.*, round(g.amount_base * r.rate, 4) AS amount_reporting, c.reporting_currency
FROM gl_entry g
JOIN company c ON c.id = g.company_id
JOIN LATERAL (SELECT rate FROM fx_rate f
               WHERE f.from_currency = c.default_currency
                 AND f.to_currency  = c.reporting_currency
                 AND f.rate_type    = 'closing'
                 AND g.posting_date BETWEEN f.valid_from AND f.valid_to
               LIMIT 1) r ON true;
```

Storing it (as ERPNext does, `accounts/doctype/gl_entry/gl_entry.py:302`) means **the reporting
figure is frozen at posting time** and cannot be restated when the group changes its presentation
currency or when a closing rate is corrected. As a view it is always current, and a historical
restatement is a `fx_rate` correction, not a data migration across every GL row.

### 8.2 Rates are effective-dated data with an exclusion constraint

```sql
CREATE TABLE fx_rate (
    id             uuid PRIMARY KEY,
    from_currency  char(3) NOT NULL,
    to_currency    char(3) NOT NULL,
    rate_type      fx_rate_type NOT NULL,     -- 'spot','buying','selling','closing','average','peg'
    rate           numeric(21,9) NOT NULL,
    source         fx_source NOT NULL,        -- 'manual','provider','peg_derived'
    provider_ref   text,
    valid_from     date NOT NULL,
    valid_to       date NOT NULL DEFAULT 'infinity',
    CONSTRAINT fx_rate_positive CHECK (rate > 0),
    CONSTRAINT fx_distinct CHECK (from_currency <> to_currency),
    EXCLUDE USING gist (
        from_currency WITH =, to_currency WITH =, rate_type WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&
    )
);
```

- **`EXCLUDE USING gist`** makes overlapping rates for the same (pair, type) **impossible**. No
  `order_by="date desc, name desc"` tie-break by alphabetical name (§2.1 point 2), no ambiguity
  between `-Selling`, `-Buying`, and `-Selling-Buying` records.
- **`rate_type` is an enum**, replacing the `for_buying`/`for_selling` boolean pair — and adding
  `closing` and `average`, which statutory translation requires and ERPNext has no concept of.
- **The rate is never part of a primary key**, so changing its type is an ordinary UPDATE, not a
  rename cascade (§2.1 point 2).
- **`source` + `provider_ref`** record provenance. A rate that came from an API is
  distinguishable from one a user typed — ERPNext keeps no such record.

Staleness becomes a policy row, per pair, not a global setting (§2.1 point 4):

```sql
CREATE TABLE fx_rate_policy (
    from_currency  char(3) NOT NULL,
    to_currency    char(3) NOT NULL,
    max_age_days   smallint NOT NULL,
    on_missing     fx_missing_action NOT NULL,   -- 'reject','use_last','use_peg'
    PRIMARY KEY (from_currency, to_currency)
);
```

`on_missing = 'reject'` is the default: **a document that cannot be priced does not post.**
ERPNext's `return 0.0` after a `msgprint` (§2.1 point 1) has no analogue.

### 8.3 Pegs are derived rows, not runtime arithmetic

`get_pegged_rate`'s four cases (§2.2) become a **generated `fx_rate` row** with
`source = 'peg_derived'`, produced by a scheduled task from a `currency_peg` table:

```sql
CREATE TABLE currency_peg (
    currency       char(3) PRIMARY KEY,
    pegged_to      char(3) NOT NULL,
    ratio          numeric(21,9) NOT NULL CHECK (ratio > 0),
    valid_from     date NOT NULL,
    valid_to       date NOT NULL DEFAULT 'infinity',
    CONSTRAINT peg_not_self CHECK (currency <> pegged_to)
);
```

Cycle prevention is a recursive-CTE check at insert (`currency` must not be reachable from
`pegged_to`) — the gap noted in §2.2. And because pegs materialise into `fx_rate`, **no rate lookup
ever recurses or makes an HTTP call** (§2.1 point 5): rate fetching is a separate scheduled job
writing `fx_rate` rows, and document posting is a pure indexed read.

### 8.4 Realised FX is part of the settlement, not a separate voucher

The `settlement` table (S02 §12.1) already carries `exchange_rate` and `fx_gain_loss_base`:

```sql
INSERT INTO settlement (payment_voucher_id, payment_ar_ap_entry_id,
                        obligation_voucher_id, obligation_schedule_id,
                        allocated_amount,        -- 20 000.00 USD, account currency
                        allocated_amount_base,   -- 1 698 000.00 INR at payment rate
                        exchange_rate,           -- 84.90
                        fx_gain_loss_base,       -- 28 000.00
                        effective_date, created_by, reason_code)
     VALUES (...);
```

and the GL for the payment voucher includes the FX line **in the same voucher**:

| Account | `amount_acct` | ccy | `rate` | `amount_base` |
|---|---:|---|---:|---:|
| Bank – USD | +20 000.00 | USD | 84.900000000 | +1 698 000.00 |
| `Debtors - USD` | −20 000.00 | USD | 83.500000000 | −1 670 000.00 |
| Realised FX Gain | 0.00 | INR | 1.000000000 | −28 000.00 |

**One voucher, balanced in base currency (F1), and the account-currency column nets to zero for the
USD accounts.** That is the second invariant this design gets for free:

- **F5** (new) for every voucher and every `account_currency`,
  `Σ amount_acct` over accounts of that currency nets consistently with
  `Σ amount_base` at the row rates — the residual, by construction, is exactly the FX line.

No separate `Exchange Gain Or Loss` journal, no
`reference_type`/`reference_name`/`reference_detail_no` triple to link them, and **no
content-comparison idempotency check** — so the double-booking risk from
`gain_loss_journal_already_booked`'s float equality (§4.2) does not exist. Idempotency comes from
`settlement`'s `UNIQUE (kind, idempotency_key)`-style constraints and the
`reverses_settlement_id UNIQUE` reversal rule (S02 §12.7).

### 8.5 Unrealised FX is a view, and the revaluation is a posting from it

```sql
CREATE VIEW fx_exposure AS
SELECT g.company_id, g.account_id, g.account_currency, a.party_type, a.party_id,
       SUM(g.amount_acct) AS balance_acct,
       SUM(g.amount_base) AS balance_base,
       CASE WHEN SUM(g.amount_acct) <> 0
            THEN SUM(g.amount_base) / SUM(g.amount_acct) END AS implied_rate
FROM gl_entry g
LEFT JOIN ar_ap_entry a ON a.voucher_id = g.voucher_id AND a.account_id = g.account_id
JOIN account acc ON acc.id = g.account_id
WHERE acc.is_fx_revalued
GROUP BY 1,2,3,4,5
HAVING SUM(g.amount_acct) <> 0 OR SUM(g.amount_base) <> 0;
```

The revaluation voucher is then `INSERT … SELECT` from that view joined to the closing `fx_rate` —
one statement, set-based, instead of `get_account_balance_from_gle` +
`calculate_new_account_balance` iterating in Python (§6.1).

Three specific improvements:

- **The implied rate is computed the same way** (`balance_base / balance_acct`) — ERPNext's
  approach here is correct and we keep it. But `CASE WHEN … <> 0` returns `NULL`, not `0`, so a
  zero denominator is *absent*, not silently a zero rate (§6.1).
- **The `zero_balance` cases become explicit**: `balance_acct = 0 AND balance_base <> 0` is a
  **stranded base residue**, written off to a distinct `fx_rounding_residue` account with
  `reason_code`, not by "set the new rate to 0" (§6.2). `balance_acct <> 0 AND balance_base = 0` is
  a data-integrity error and raises, because `CHECK (gl_base_consistent)` (§8.1) should have made
  it impossible.
- **Reversal is not a separate document someone must remember.** The revaluation voucher carries
  `auto_reverse_on date`, and a `BEFORE INSERT` trigger on the next period's first posting — or
  simply the `fx_exposure` view being computed *from historical rates* — makes the reversal
  unnecessary in the first place. We take the second option: **unrealised FX is never posted at
  all for internal reporting** (it is a view), and is posted only when a statutory filing requires
  it, with `auto_reverse_on` set and enforced by invariant P5.

### 8.6 Statutory translation for reporting

`rate_type = 'closing'` and `'average'` exist precisely for this. Balance-sheet accounts translate
at closing rate, P&L at average rate, equity at historical — and the residual is the **currency
translation reserve**:

```sql
CREATE VIEW translated_trial_balance AS
SELECT ...
       CASE a.report_type
         WHEN 'balance_sheet' THEN g.amount_base * closing.rate
         WHEN 'profit_and_loss' THEN g.amount_base * average.rate
       END AS amount_reporting
FROM ...
```

with the difference falling to `currency_translation_reserve` by construction. ERPNext's single
stored `*_in_reporting_currency` figure (§8.1) cannot express closing-vs-average translation at
all, which means it cannot produce a compliant consolidated statement.

---

## 9. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Currency figures stored per GL row | 4 denominations × debit/credit = up to 8 columns | 2 amounts + 1 rate |
| Reporting currency | **stored**, frozen at posting | view; restatable |
| Closing vs average vs historical rate | not expressible | `fx_rate.rate_type` |
| Currency translation reserve | not modelled | falls out of the translation view |
| Can a rate be 0? | **yes**, three code paths | `CHECK (rate > 0)` |
| Is `base = acct × rate` enforced? | no | `CHECK` per row |
| Two rates for one (date, pair) | yes — buying/selling/both, tie-broken **alphabetically by name** | `EXCLUDE USING gist`, impossible |
| Rate identity | in the primary key (`2026-08-01-USD-INR-Selling`) | surrogate `uuid` |
| Rate provenance | not recorded | `source` + `provider_ref` |
| Staleness policy | one global setting | per-pair `fx_rate_policy` |
| Missing rate | `msgprint` + `return 0.0` | `on_missing = 'reject'` → document does not post |
| HTTP call during document save | **yes**, cached 6 h | never; a job populates `fx_rate` |
| Peg cross-rates | computed at runtime, can recurse into the API | materialised `fx_rate` rows, cycle-checked |
| Realised FX | **a separate `Exchange Gain Or Loss` journal** | a line in the payment voucher |
| FX idempotency | float equality on `total_debit`, inspects `[0]` only | constraint-based |
| Vouchers for 2 invoices + 2 payments | **8** | **4** |
| Unrealised FX | posted, needs a manual/scheduled reversal | a view; posted only for filings, with `auto_reverse_on` |
| Revaluation computation | Python loop over accounts | one `INSERT … SELECT` from `fx_exposure` |
| Stranded one-sided balance | "set the new rate to 0" | explicit `fx_rounding_residue` posting with a reason |
| Reversal depends on a scheduled job | yes | no |

---

## 10. Invariants exercised

- **F1** every voucher balances in base currency — invoice, payment, FX line included.
- **F5** (new) per voucher and per `account_currency`, the account-currency amounts net
  consistently with base amounts at the row rates; the residual is exactly the FX line.
- **F6** (new) `CHECK (abs(amount_base − round(amount_acct × rate_acct_to_base, 4)) <= 0.0001)`
  on every ledger row, and `rate > 0`.
- **F7** (new) `fx_rate` has no overlapping validity for a (pair, `rate_type`) —
  `EXCLUDE USING gist`.
- **P5** (new) an unrealised-FX voucher must carry `auto_reverse_on`, and a period cannot reach
  `closed` while an unreversed unrealised-FX voucher exists whose `auto_reverse_on` has passed.
- **S1/S2** allocation caps hold in **account currency**, which is the currency the obligation is
  denominated in — so a rate movement can never create or destroy allocatable amount.

---

Cross-references: **[S01](S01-order-to-cash.md)**, **[S02](S02-payments-and-allocation.md)** (the
settlement model this extends), **[S05](S05-period-close-and-opening-balances.md)** §5.5
(reporting currency in closing snapshots);
doc 01 (GL posting, `toggle_debit_credit_if_negative`), doc 04 (AR/AP, multi-currency outstanding),
doc 05 (totals pipeline and `base_*` derivation), doc 07 (FX revaluation in period close),
doc 11 §2.4 (advance FX gain/loss), doc 22 §2.2 (the scheduled revaluation jobs),
doc 26 (chart of accounts, account currency), `docs/design/FINAL-SCHEMA.md`.
