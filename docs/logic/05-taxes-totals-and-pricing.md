# 5. Totals, taxes and pricing

Every monetary field on a trade document comes from this pipeline. It runs on the server on save and
is mirrored in JS on the client.

Primary files:
- `controllers/taxes_and_totals.py` — the engine
- `accounts/services/taxes.py` — the validators
- `accounts/services/payment_schedule.py` — instalments
- `accounts/doctype/pricing_rule/utils.py` + `pricing_rule.py` — rule discovery and application
- `stock/get_item_details.py` — price list resolution
- `accounts/doctype/tax_withholding_entry/tax_withholding_entry.py` — withholding
- `setup/utils.py::get_exchange_rate` — FX

---

## 5.1 Pipeline

`AccountsController.calculate_taxes_and_totals()` (accounts_controller.py:576) instantiates
`calculate_taxes_and_totals(doc)`, which does the work **in the constructor** (:31-39):
1. `frappe.flags.round_off_applicable_accounts = get_round_off_applicable_accounts(...)` — accounts
   whose tax amount is rounded to whole units (regional hook).
2. `frappe.flags.round_row_wise_tax = Accounts Settings.round_row_wise_tax`.
3. `self._items = filter_rows() if doctype == "Quotation" else doc.items` — Quotation excludes
   `is_alternative` rows from **all** totals.
4. `self.calculate()`.

`calculate()` (:46-76):
```
if not doc.items: return                       # no-op, existing totals untouched
discount_amount_applied = False ; need_recomputation = False
_calculate()                                   # full pass, pre-discount
if field discount_amount exists: set_discount_amount() ; apply_discount_amount()   # may re-run _calculate()
if need_recomputation: return calculate(ignore_tax_template_validation=True)       # one recursive re-entry
if apply_discount_on == "Grand Total" and is_cash_or_non_trade_discount:
    grand_total -= discount_amount ; base_grand_total -= base_discount_amount
    rounding_adjustment = base_rounding_adjustment = 0 ; set_rounded_total()
calculate_shipping_charges()                   # Shipping Rule.apply() then _calculate() AGAIN
if SI/PI: calculate_total_advance()
if field other_charges_calculation: set_item_wise_tax_breakup()
```

`_calculate()` (:78-89) — the atomic unit, and it must be **idempotent** because shipping rules,
transaction pricing rules and the discount pass all re-enter it:
```
1  validate_conversion_rate
2  calculate_item_values
3  validate_item_tax_template
4  update_item_tax_map
5  initialize_taxes
6  determine_exclusive_rate          # inclusive-tax back-calculation
7  calculate_net_total
8  calculate_taxes
9  adjust_grand_total_for_inclusive_tax
10 calculate_totals                  # ends with set_rounded_total()
11 calculate_total_net_weight
```

## 5.2 Item values

`calculate_item_rate` (:166-222) — resolves rate vs margin vs discount:
```
if not price_list_rate: clear margin+discount ; rate_with_margin = 0 ; return
if pricing_rules and not ignore_pricing_rule: re-read margin from the applied Pricing Rules
rate_with_margin = get_rate_with_margin(item)          # :1221
    Percentage -> flt(price_list_rate * (1 + margin/100), precision)
    Amount     -> flt(price_list_rate + margin, precision)
if discount_percentage > 0: discount_amount = flt(rate_with_margin * pct/100, precision)
calculated_rate = flt(rate_with_margin - discount_amount, precision("rate"))
if pricing_rules or not item.rate: item.rate = calculated_rate ; return
if item.rate == calculated_rate: return
# user rate wins -> back-solve
if item.rate > price_list_rate: margin_type="Amount"; margin = rate - price_list_rate; clear discount
else:                           rate_with_margin = price_list_rate
                                discount_amount  = price_list_rate - rate ; discount_percentage = 0 ; clear margin
```

`calculate_item_values` (:224-244) — **skipped entirely when `doc.is_consolidated` or
`discount_amount_applied`**, which is why the discount pass keeps discounted nets:
```
round_floats_in(item, do_not_round_fields=["valuation_rate","incoming_rate","sales_incoming_rate"])
calculate_item_rate(item)
net_rate = rate
amount = flt(-1*rate, prec)  if qty==0 and is_return and doctype != "Purchase Receipt"
       = flt(rate, prec)     if qty==0 and is_debit_note
       = flt(rate*qty, prec) otherwise
net_amount = amount
_set_in_company_currency(item, [price_list_rate, rate_with_margin, rate, net_rate, amount, net_amount])
item_tax_amount = 0
```

**The only base-field formula** (`_set_in_company_currency`, :246-252):
```
base_X = flt( flt(X, precision(X)) * conversion_rate , precision("base_X") )
```
Round to transaction precision **first**, multiply, round again. Never `flt(x*rate)` in one step (with
one deliberate exception in the purchase branch of `calculate_totals`).

## 5.3 Charge types

Rate resolution `_get_tax_rate` (:390): if `tax.account_head` is a key in the item's `item_tax_rate`
map, use that (so **Item Tax Templates are per-row rate overrides keyed by account head**); the
sentinel `NOT_APPLICABLE_TAX` means the item contributes neither tax nor taxable amount for that row.

`get_current_tax_and_net_amount` (:597-641):

| `charge_type` | taxable (net) amount | tax amount |
|---|---|---|
| `Actual` | `item.net_amount` | `item.net_amount * flt(tax.tax_amount) / doc.net_total`, and **`0.0` when `net_total == 0`** |
| `On Net Total` | `item.net_amount` only if the account is in the item's tax map, else 0 | `(rate/100) * item._unrounded_net_amount` when inclusive and not `discount_amount_applied`; otherwise `(rate/100) * item.net_amount` |
| `On Previous Row Amount` | `taxes[row_id-1].tax_amount_for_current_item` | `(rate/100) * that` |
| `On Previous Row Total` | `taxes[row_id-1].grand_total_for_current_item` | `(rate/100) * that` |
| `On Item Quantity` | 0 (deliberately not summed — the field is Currency) | `rate * item.qty` (rate is an amount per unit) |
| custom | `get_item_taxable_base(item, tax)` via the `erpnext_taxable_base_resolvers` hook (:643) | `(rate/100) * base` |
| `On Paid Amount` | Payment Entry only | computed in `payment_entry.py` |

`row_id` chaining rules (`services/taxes.py:239-262`): `Actual`, `On Net Total`, `On Paid Amount` may
not have a `row_id`; `On Previous Row *` cannot be row 1, requires `row_id`, and
`cint(row_id) >= cint(idx)` throws — **so the chain is a DAG evaluable in index order**. `Actual` forces
`tax.rate = None`.

Other modifiers:
- `included_in_print_rate` (inclusive) — validated in `validate_inclusive_tax` (taxes.py:298): not
  allowed on `Actual`; `On Previous Row Amount` requires the referenced row inclusive; `On Previous Row
  Total` requires **all** rows `1..row_id-1` inclusive; `Valuation` category cannot be inclusive.
- `category`: `Valuation` rows contribute **0** to totals (`get_tax_amount_if_for_valuation_or_deduction`,
  :574) and are excluded from the print breakup; `Total` / `Valuation and Total` hit the totals.
- `add_deduct_tax` (purchase): negates the slope/intercept, negates the amount, flips the item-wise
  multiplier, and splits `taxes_and_charges_added` vs `taxes_and_charges_deducted`.
- `is_tax_withholding_account` + `dont_recompute_tax`: TDS rows, preserved across recomputation.

## 5.4 Inclusive tax: the affine model

`determine_exclusive_rate` (:303-342) generalises inclusive tax to `tax = slope*net + intercept`:

```
per item:
  for each tax row i:
      (slope, intercept_per_qty) = get_current_tax_fraction(tax, item_tax_map, item)     # :347
      tax.inclusive_amount_per_qty = intercept_per_qty
      i == 0 ? grand_total_fraction = 1 + slope         : = prev.grand_total_fraction + slope
      i == 0 ? grand_total_amount_per_qty = intercept   : = prev.grand_total_amount_per_qty + intercept
      total_tax_slope     += slope
      total_tax_intercept += intercept_per_qty * qty
  if not discount_amount_applied and qty and (slope or intercept):
      amount = item.amount - total_tax_intercept
      item._unrounded_net_amount = amount / (1 + total_tax_slope)
      item.net_amount = flt(_unrounded_net_amount, precision)
      item.net_rate   = flt(net_amount / qty, precision)
```
`get_current_tax_fraction` returns per charge type: `On Net Total` → slope `rate/100`;
`On Previous Row Amount` → `slope = rate/100 * row.tax_fraction_for_current_item`,
`intercept = rate/100 * row.inclusive_amount_per_qty`; `On Previous Row Total` → same using the
cumulative fields; `On Item Quantity` → `intercept = rate`; custom → `intercept = (rate/100)*base/qty`.
`Deduct` negates both.

Keeping `_unrounded_net_amount` is what avoids double rounding when the same inclusive tax is then
computed "forward" in `calculate_taxes`.

`adjust_grand_total_for_inclusive_tax` (:739-767; the old name `manipulate_grand_total_for_inclusive_tax`
is a deprecated shim at :729):
```
diff = doc.total + Σ non-inclusive tax_amount_after_discount_amount − flt(last_tax.total)
if discount_amount_applied and discount_amount: diff -= flt(discount_amount)
diff = flt(diff, precision("rounding_adjustment"))
grand_total_diff = diff if abs(diff) <= 5.0/10**last_tax.precision("tax_amount") else 0
```
> Only sub-half-cent drift is absorbed. A larger deviation is **not** silently corrected — it just
> shows up in the grand total.

## 5.5 `calculate_taxes` (:424-518)

```
actual_tax_dict = {tax.idx: flt(tax.tax_amount) for Actual rows}          # the target to hit exactly
for n, item in enumerate(_items):
  for i, tax in enumerate(doc.taxes):
      (net, amt) = get_current_tax_and_net_amount(item, tax, item_tax_map)
      if flags.round_row_wise_tax: round both per item
      if tax.charge_type == "Actual":                                     # divisional-loss fix
          actual_tax_dict[idx] -= amt
          if n == last: amt += actual_tax_dict[idx]
      if charge_type != "Actual" and not (discount_applied and apply_discount_on == "Grand Total"):
          tax.tax_amount += amt ; tax.net_amount += net
      tax.tax_amount_for_current_item = amt                               # feeds On Previous Row Amount
      tax.tax_amount_after_discount_amount += amt                         # always; used by totals + GL
      amt = get_tax_amount_if_for_valuation_or_deduction(amt, tax)
      tax.grand_total_for_current_item = (i==0 ? item.net_amount : taxes[i-1].grand_total_for_current_item) + amt
# then per row: round_off_totals -> _set_in_company_currency -> round_off_base_values -> set_cumulative_total
adjust_rounding_in_item_wise_tax_details()
```

`set_cumulative_total` (:588):
`tax.total = (row 0 ? doc.net_total : taxes[n-1].total) + adj(tax_amount_after_discount_amount)`.

**Item-wise breakup with error diffusion** (`set_item_wise_tax`, :~660): each item's stored base amount
is derived as a *delta of the running cumulative total*, so the sum is exact by construction:
```
tax._running_txn_tax_total += current_tax_amount * multiplier
new_base_total = flt(flt(_running_txn_tax_total, prec) * conversion_rate, base_prec)
item_wise_amount = flt(new_base_total - tax._running_base_tax_total, base_prec)
tax._running_base_tax_total = new_base_total
```
`adjust_rounding_in_item_wise_tax_details` (:520-572) then adds the residual (tolerance 0.5, or 1.0 for
zero-precision currencies like JPY) to the **last** breakup row, and **throws** listing
"Row {idx} (Difference: {diff})" if it is larger.

> **Invariant** For each tax row: `Σ item_wise_tax_details.amount == base_tax_amount_after_discount_amount × (±1 by add_deduct_tax)`.
> **Invariant** For `Actual`: `Σ per-item shares == flt(tax.tax_amount)` exactly (residual on the last item).

## 5.6 Discounts

**Line level** — `discount_percentage` → `discount_amount` → `rate` (§5.2), with the user's typed rate
winning and the discount/margin back-solved.

**Document level** — `set_discount_amount` (:851):
`discount_amount = flt(flt(doc.get(scrub(apply_discount_on))) * additional_discount_percentage / 100)`,
i.e. the base is `net_total` or `grand_total` depending on `apply_discount_on`. For returns, the sum of
discounts on all submitted returns against the same invoice is added before validating. Validation
(only when `_action` is set): `discount_amount > grand_total` → throw.

`apply_discount_amount` (:896-951):
```
base_discount_amount = flt(discount_amount * conversion_rate, prec)
if cash/non-trade discount on Grand Total: discount_amount_applied = True ; return      # total-level only
total_for_discount_amount = get_total_for_discount_amount()
for item in _items:
    distributed        = discount_amount * item.net_amount / total_for_discount_amount
    adjusted           = item.net_amount - distributed
    expected_net_total += adjusted
    item.net_amount    = flt(adjusted, prec) ; net_total += item.net_amount
    item.distributed_discount_amount = flt(distributed, prec)
    if rounding_difference := flt(expected_net_total - net_total, precision("net_total")):
        item.net_amount += it ; item.distributed_discount_amount = flt(distributed + it) ; net_total += it
    item.net_rate = flt(item.net_amount/item.qty, prec) if qty else 0
discount_amount_applied = True ; _calculate()          # full second pass on discounted nets
```
The rounding correction runs **inside** the loop, so drift is corrected continuously instead of dumped
on the last row.

`get_total_for_discount_amount` (:953-994) — the denominator:
`apply_discount_on == "Net Total"` or no taxes → `doc.net_total`; else
`(grand_total_for_distributing_discount or grand_total) − total_actual_tax`, where `total_actual_tax`
accumulates `Actual` and `On Item Quantity` rows plus the `On Previous Row *` rows referencing them.
Rationale: percentage taxes scale with the discounted net, fixed amounts do not, so they must be
excluded from the proportional base.

> **Invariant** `Σ item.distributed_discount_amount == doc.discount_amount`.

## 5.7 Precision and rounding — the complete list

- `flt(value, precision)` is the universal primitive; `doc.precision(field)` derives from the field
  type, the document currency and `System Settings.currency_precision`.
- `_set_in_company_currency` composition rule (round → multiply → round).
- `Accounts Settings.round_row_wise_tax` → round each item's contribution before accumulating.
- Regional whole-unit rounding: accounts in `frappe.flags.round_off_applicable_accounts` get
  `round(x, 0)` on both transaction and base tax amounts (`round_off_totals` :712,
  `round_off_base_values` :723).
- `rounded_total = round_based_on_smallest_currency_fraction(grand_total, currency, precision)`;
  `rounding_adjustment = rounded_total − grand_total`; both forced to 0 when
  `disable_rounded_total` (doc field, else `Global Defaults`).
- GL side: `make_round_off_gle` (see doc 01).

Drift corrections, all of them:
1. `Actual` charge → residual on the **last item**.
2. `adjust_rounding_in_item_wise_tax_details` → residual on the **last breakup row**, else throw.
3. `apply_discount_amount` → `rounding_difference` folded into the current item, in-loop.
4. `adjust_grand_total_for_inclusive_tax` → `grand_total_diff`, capped at `5/10**precision`.
5. `calculate_taxes` discount-on-grand-total second pass → `grand_total_diff`.
6. `rounding_adjustment` + the GL round-off row.

> **Ours** Money as `numeric(19,4)` (see doc 08 §decisions) with a single `round_money()` helper, and
> **one** documented residual-absorption point per computation (line taxes → last line; document total
> → rounding adjustment). Six independent drift corrections is how you get invoices that are off by a
> cent in a way nobody can explain. Every invariant in this chapter becomes a property-based test.

## 5.8 Pricing

### Rule discovery (`pricing_rule/utils.py`)

`get_pricing_rules(args, doc)` (:26) iterates `apply_on in ["Item Code", "Item Group", "Brand"]`,
continuing past the first hit if it `has_priority`, breaking early if the collected rules are not all
`apply_multiple_pricing_rules`.

`_get_pricing_rules` (:105-177) is raw SQL joining `tabPricing Rule` with
`tabPricing Rule {Item Code|Item Group|Brand}`, matching: the child key (or
`apply_rule_on_other`/`other_item_code`), UOM match **or blank**, `variant_of` fallback,
`disable = 0`, `selling`/`buying` by doctype, warehouse tree by `lft/rgt`,
`coalesce(for_price_list,'') in (price_list,'')`, each party field equal **or blank** (and required
blank when the arg is absent), Customer Group / Territory / Supplier Group trees, and
`transaction_date between coalesce(valid_from,'2000-01-01') and coalesce(valid_upto,'2500-12-31')`.
`ORDER BY coalesce(priority,'') desc, name desc`.

`filter_pricing_rule_based_on_condition` (:83) runs `frappe.safe_eval(rule.condition, None,
doc.as_dict())`; evaluation errors are logged and the rule dropped.

`filter_pricing_rules` (:276-361) then gates on qty/amount where `amount = price_list_rate * qty`:
- `mixed_conditions` → `get_qty_and_rate_for_mixed_conditions` sums qty/amount across all matching doc
  rows;
- `is_cumulative` → `get_qty_amount_data_for_cumulative` adds historical submitted qty/amount within
  the validity window (warehouse-tree filtered);
- `filter_pricing_rules_for_qty_amount` (:396): `qty >= min_qty*cf and qty <= max_qty*cf` and the same
  for amount, where `cf = get_conversion_factor(item, rule.uom)` (forced to 1 when the rule UOM equals
  the transaction UOM);
- near-misses produce a `threshold_percentage` suggestion msgprint;
- tie-breaking: currency match → highest `priority` → for all-`Discount Percentage` ties prefer
  `for_price_list == args.price_list` → else **throw `MultiplePricingRuleConflict`**.

If **all** rules allow stacking, `sorted_by_priority` (:63) emits them bucketed by
`cint(priority)` ascending, so higher priority applies last.

### Application (`pricing_rule.py::apply_price_discount_rule`, :572-632)

- Margin applies when `margin_type in ("Amount","Percentage") and rule.currency == args.currency`, or
  always for `Percentage`. With `apply_multiple_pricing_rules`, margins **accumulate**.
- `rate_or_discount == "Rate"`: `price_list_rate = rule.rate * (conversion_factor if rule.uom != args.uom else 1)`,
  `discount_percentage = 0`.
- `Discount Amount` / `Discount Percentage`: with `apply_discount_on_rate` and an existing discount they
  **compound**: `field += (100 − field) * (rule[field]/100)`; else a percentage is converted to an
  amount against `price_list_rate` and amounts accumulate with `+=`.

**Free items** (`get_product_discount_rule`, pricing_rule/utils.py:650-718): `qty = rule.free_qty or 1`;
`is_recursive` → `qty = transaction_qty * free_qty / recurse_for`, and with `round_free_qty`
`qty = (transaction_qty // recurse_for) * free_qty`. The row is appended with
`rate = free_item_rate or 0`, `is_free_item = 1`. Free rows are skipped by
`get_pricing_rule_for_item` so they never recursively earn discounts.

**Transaction-level rules** (`apply_pricing_rule_on_transaction`, :582-660) set `apply_discount_on`
and `additional_discount_percentage`/`discount_amount` then call `doc.calculate_taxes_and_totals()`.

### Price list resolution (`stock/get_item_details.py`)

`get_item_details` order (:58-186): `get_basic_details` → item tax template + map →
`get_party_item_code` → (invoices) tax withholding category → (SO/Quotation) `set_valuation_rate` →
`update_party_blanket_order` → **`get_price_list_rate`** (with `customer` temporarily nulled for
purchase doctypes so a customer-specific price can never leak in) → optional fallback to
`Selling Settings.selling_price_list` → POS profile overrides → bin details →
**`get_pricing_rule_for_item`** (rules run *after* the price is known and can overwrite it) →
serial/batch, lead time, BOM, bundle, gross profit.

`get_price_list_rate` (:1055-1097) — the key formula:
```
out.price_list_rate = flt(price_list_rate) * flt(plc_conversion_rate) / flt(conversion_rate)
```
i.e. price-list currency → company currency → transaction currency. If no price is found (or
`Stock Settings.update_existing_price_list_rate`), `insert_item_price(ctx)` may auto-create an
`Item Price` at `rate / conversion_factor`.

`get_item_price` (:1212-1265) selection order:
```
ORDER BY valid_from IS NULL asc, valid_from desc, coalesce(batch_no,'') desc, uom desc,
         [party match desc,] name desc          -- name desc added deliberately: MariaDB and Postgres differed
```
then party-specific first, then party-agnostic, then a retry with `uom = stock_uom`.
`check_packing_list` (:1330) rejects a price whose `packing_unit` does not divide the desired qty.
UOM handling: exact UOM match → as-is; else if not `price_list_uom_dependant` →
`rate * conversion_factor`; else as-is.

`get_blanket_order_details` (:1771) returns `blanket_order_rate` from a submitted `Blanket Order`
matching company/item/party with `to_date >= transaction_date`.

> **Ours** Pricing is a **pure resolver**: `resolve_price(item, uom, qty, party, price_list, date,
> company) -> {price, source_rule_ids[], discount[], margin[]}` with no document mutation and a
> deterministic total order over candidate rules (priority, specificity, id). Conflicts resolve by that
> order and are logged, never thrown at the user mid-save. Stacking is opt-in per rule and the
> application order is recorded on the line so a price is always explainable.

## 5.9 Payment schedule (`accounts/services/payment_schedule.py`)

`set_payment_schedule` (:17-111):
1. POS SI or `is_opening == "Yes"` → clear the template and return.
2. `posting_date = bill_date or posting_date or transaction_date`; `due_date = doc.due_date or posting_date`.
3. `base_grand_total = base_rounded_total or base_grand_total` (and the txn twin);
   for SI/PI subtract the write-off.
4. Advance adjustment: if `party_account_currency == company_currency`,
   `base_grand_total -= total_advance` then `grand_total = base/conversion_rate`; else the mirror.
5. Empty schedule → fetch from the linked SO/PO (when `automatically_fetch_payment_terms` and all items
   share one order that has terms), else `get_payment_terms(template, ...)`, else a single 100% row.
6. Re-proportioning: rows with `invoice_portion` get
   `payment_amount = flt(grand_total * invoice_portion/100, prec)` (percentage instalments); rows
   without keep the user's `payment_amount` and only derive the base (fixed-amount instalments).

`get_due_date` (:413):
```
"Day(s) after invoice date"                    -> add_days(date, credit_days)
"Day(s) after the end of the invoice month"    -> add_days(get_last_day(date), credit_days)
"Month(s) after the end of the invoice month"  -> get_last_day(add_months(date, credit_months))
clamped: if due_date < posting_date: due_date = posting_date
```
`get_discount_date` (:416) is the same three modes on `discount_validity_based_on`.

`set_due_date` (:209): `doc.due_date = max(schedule.due_date)`.
`validate_payment_schedule_dates` (:214): clears `discount_date` without a discount, validates
`discount_date <= due_date`, forbids a due date before `transaction_date` for SO/Quotation, and rejects
duplicate due dates.
`validate_payment_schedule_amount` (:246):

> **Invariant** `|Σ payment_amount − grand_total| <= 0.1` **and** `|Σ base_payment_amount −
> base_grand_total| <= 0.1`, after write-off and advance adjustment. Note: an absolute 0.1 tolerance,
> not precision-based.

## 5.10 Tax withholding (TDS/TCS)

Master (`tax_withholding_category.py`): per-group date ranges must not overlap; one row per company;
`cumulative_threshold >= single_threshold`. `TaxWithholdingDetails.get()` (:130-172) builds per-category
context: `tax_rate, from_date, to_date, single_threshold, cumulative_threshold, tax_deduction_basis
(Gross Total|Net Total), round_off_tax_amount, tax_on_excess_amount, disable_cumulative_threshold,
disable_transaction_threshold, account_head, tax_id` plus a Lower Deduction Certificate overlay
(`ldc_certificate, ldc_unutilized_amount = certificate_limit − consumed, ldc_rate`) where consumption is
`Σ taxable_amount` of submitted `Tax Withholding Entry` rows with status in (`Settled`, `Over Withheld`).

Controller (`tax_withholding_entry.py::TaxWithholdingController`, :352, with `PurchaseTaxWithholding`,
`SalesTaxWithholding`, `PaymentTaxWithholding`, `JournalTaxWithholding` subclasses):
```
calculate(): _get_category_details -> _update_taxable_amounts -> _generate_withholding_entries -> _process_withholding_entries
```
Taxable base (`_update_amount_for_item`, :531):
`taxable = item.base_net_amount` (or `+ item._item_total_tax_amount` when
`tax_deduction_basis == "Gross Total"`), where `_item_total_tax_amount` sums the item's tax breakup
**excluding** rows flagged `is_tax_withholding_account` — **no TDS on TDS**. All amounts are in company
currency.

Threshold logic (`_is_threshold_crossed_for_category`, :581):
```
ignore_tax_withholding_threshold        -> crossed
disable_cumulative_threshold           -> taxable_amount >= single_threshold
cumulative_threshold == 0              -> crossed
tax_on_excess_amount                   -> crossed (excess handled separately)
else _check_historical_threshold_status:
    group Σ taxable_amount by status over submitted entries in the rate row's window (by tax_id else party)
    if Settled > 0: crossed            # "once deducted, always deducted" — deliberate, conservative
    remaining = cumulative_threshold − Under Withheld total
    unless disable_transaction_threshold: remaining = min(remaining, single_threshold)
    crossed iff taxable_amount >= remaining
```
`compute_withheld_amount` (:1069): `taxable * rate/100`, rounded to 0 dp when `round_off_tax_amount`.

Insertion into the tax table (`update_tax_rows`, :710-744): per account,
`tax_amount = flt(base_amount / conversion_rate, precision)`; an existing row with the same
`account_head` and `is_tax_withholding_account` is overwritten and marked `dont_recompute_tax = 1`,
else a new row is appended with `{is_tax_withholding_account: 1, category: "Total",
charge_type: "Actual", dont_recompute_tax: 1}` and `add_deduct_tax = "Deduct"` for suppliers /
`"Add"` for customers. Then `_set_item_wise_tax_for_tds` (:762) writes the breakup:
```
item_effective_taxable = max(0, item_base_taxable − (item_base_taxable/total_taxable)*unused_threshold)
item_tax_amount        = flt(withholding_amount * item_effective_taxable / category.taxable_amount, prec)
```
and finally `_remove_zero_tax_rows()` + `calculate_taxes_and_totals()` — **the whole engine re-runs** so
the grand total reflects the TDS row.

`Tax Withholding Entry` itself is a ledger with statuses `Settled | Under Withheld | Over Withheld` and
proportional re-allocation across older entries.

## 5.11 Multi-currency

- `conversion_rate` = transaction → company. Normalised in `validate_conversion_rate` (:150) and
  `services/taxes.py:225` ("… is mandatory. Maybe Currency Exchange record is not created for X to Y").
- `plc_conversion_rate` = price-list → company, from `get_price_list_currency_and_exchange_rate`
  (get_item_details.py:1662), which picks `for_selling`/`for_buying` by doctype.
- `base_*` fields exist **only** via `_set_in_company_currency`, with `base_grand_total` special-cased
  to equal `base_net_total` when there are no taxes (avoiding a second rounding).
- Party-currency branching: `calculate_outstanding_amount` and the payment-schedule service compare
  `party_account_currency` with `doc.currency` and switch to `base_*` when they differ (and
  `total_advance` is treated as being in the party-account currency).

`get_exchange_rate` (`setup/utils.py:62-166`):
```
from == to -> 1 ; no date -> nowdate()
Currency Exchange where date <= transaction_date, from/to match [, for_buying|for_selling]
   [, and date > add_days(transaction_date, -stale_days) unless Accounts Settings.allow_stale]
   ORDER BY date desc, name desc LIMIT 1
no record and Currency Exchange Settings.disabled -> 0.00
Accounts Settings.allow_pegged_currencies_exchange_rates -> get_pegged_rate (:29)
   same base: (1/from.ratio) * to.ratio
   diff base: (1/from.ratio) * get_exchange_rate(base_from, base_to) * to.ratio
   from pegged to `to`: from.ratio ; to pegged to `from`: 1/to.ratio
else external API per Currency Exchange Settings, cached 6h, then pegged ratios applied
exception -> error log + msgprint + return 0.0        # which the caller turns into a hard throw
```

`init_landed_taxes_and_totals` (:1380-1414) is the separate FX path for Landed Cost Voucher /
`additional_costs`: per row `exchange_rate = 1` when the account currency is the company currency, else
`get_exchange_rate(posting_date, account, account_currency, company)`, throwing
"Row {idx}: Exchange Rate is mandatory"; `base_amount = flt(amount * exchange_rate, prec)`.

---

## Invariants to assert (these become our test suite)

1. `doc.net_total == Σ item.net_amount` and `doc.total == Σ item.amount` over the filtered item set.
2. `taxes[i].total == (i==0 ? net_total : taxes[i-1].total) + adj(taxes[i].tax_amount_after_discount_amount)`.
3. `grand_total == taxes[-1].total + grand_total_diff`.
4. `total_taxes_and_charges == grand_total − net_total − grand_total_diff`.
5. Per tax row: `Σ item_wise.amount == base_tax_amount_after_discount_amount × (±1)`.
6. `Actual` charge: `Σ per-item shares == flt(tax.tax_amount)` exactly.
7. Inclusive: `Σ item.amount == Σ (net_amount + inclusive taxes)` and
   `grand_total == doc.total + non-inclusive taxes (− discount)` up to `grand_total_diff`.
8. `rounding_adjustment == rounded_total − grand_total` (0 when disabled).
9. `Σ payment_schedule.payment_amount == (rounded_total or grand_total) − write_off − advance` (±0.1).
10. `Σ item.distributed_discount_amount == doc.discount_amount`.

## Known edge cases

- **Inclusive tax + document discount**: `calculate_item_values` is skipped on the discount pass, so
  `_unrounded_net_amount` is not regenerated and the forward computation falls back to the rounded net;
  the drift is absorbed by `grand_total_diff` (with `diff -= discount_amount`).
- **Zero net total**: `Actual` distribution divides by `doc.net_total`, guarded to `0.0`;
  `get_total_for_discount_amount` can then return 0 and discount distribution is skipped entirely.
- **Zero qty rows**: `net_rate` guarded to 0; `determine_exclusive_rate` skips them; return/debit-note
  zero-qty rows get `amount = ∓rate`.
- **Multiple inclusive taxes**: fine via the affine model, but `On Previous Row Total` inclusive
  requires *all* preceding rows inclusive.
- **`NOT_APPLICABLE_TAX`**: an item contributes neither tax nor taxable amount, so
  `tax.net_amount != doc.net_total` in general.
- **`is_consolidated`** (POS closing): item values skipped and `set_rounded_total` returns early when a
  `rounding_adjustment` already exists.
- **`dont_recompute_tax`** rows survive `initialize_taxes`; their breakup is rebuilt by the TDS
  controller, not by `set_item_wise_tax`.
- Shipping rules and transaction pricing rules re-enter `_calculate()`, so it must be idempotent for a
  fixed input state.
