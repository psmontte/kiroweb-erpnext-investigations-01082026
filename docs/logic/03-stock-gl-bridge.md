# 3. The stock → GL bridge

How inventory valuation and the general ledger stay reconciled, document by document.

Primary files:
- `stock/services/base_stock_gl_composer.py` — **the canonical SLE → GL engine**
- `controllers/stock_controller.py` — entry point, account resolution, repost triggers
- `stock/services/stock_ledger_service.py` — `get_stock_ledger_details` (formerly `get_voucher_wise_stock_value`)
- `<doctype>/services/gl_composer.py` — per-document rules
- `stock/doctype/landed_cost_voucher/landed_cost_voucher.py`
- `accounts/utils.py:1656-1956` — GL reposting + drift primitives

---

## 3.1 The master invariant

> **Invariant** For any stock voucher:
> `Σ (debit − credit) on inventory accounts == Σ stock_value_difference of its non-cancelled SLEs`.
>
> Nothing writes inventory GL amounts from document amounts. Purchase Receipt and Subcontracting
> Receipt read `stock_value_difference` explicitly; Purchase Invoice *reconciles to it* via
> `make_stock_adjustment_entry`. Any difference between what the document says the goods are worth and
> what the ledger says they are worth is forced into a named variance account.

## 3.2 Entry point (`StockController.make_gl_entries`, stock_controller.py:178-212)

```
if docstatus == 2: make_reverse_gl_entries(voucher_type=doctype, voucher_no=name)
provisional = Company.enable_provisional_accounting_for_non_stock_items
is_asset_pr  = any(d.is_fixed_asset for d in items)
need_map = (get_stock_items() or packed_items) and is_perpetual_inventory_enabled(company)
if need_map: inventory_account_map = get_inventory_account_map()
if (need_map or provisional or is_asset_pr) and docstatus == 1:
    gl_entries = self.get_gl_entries(inventory_account_map)      # -> BaseStockGLComposer
    make_gl_entries(gl_entries, from_repost=from_repost)
```

> **Perpetual inventory off + no provisional accounting + no asset PR ⇒ a stock voucher writes zero GL
> rows.** Inventory then only hits the books via the periodic entry / purchase expense route.

`make_gl_entries_on_cancel` (:281) cancels the FX gain/loss journal and re-runs `make_gl_entries`
**only if GL rows exist** for the voucher — reversal is by writing rows, never by deleting.

### Account resolution (:127-172, :906-957)

- `Company.enable_item_wise_inventory_account` on → map keyed by item:
  item default → item-group default → brand default → else throw "Please set default inventory account
  for item…".
- Off → keyed by warehouse via `get_warehouse_account_map(company)` (`stock/__init__.py:19`).
  `get_warehouse_account` (:54) resolves: `Warehouse.account` → nearest ancestor warehouse account by
  `lft/rgt` → `Company.default_inventory_account` → the company's single non-group Stock-type account
  → else throw.
- `get_inventory_account_dict(row, map, warehouse_field)` picks the account per row, which is how
  `from_warehouse`, `target_warehouse`, `t_warehouse`, `supplier_warehouse` and `rejected_warehouse`
  all resolve.

Accounts used, and where they come from:

| Role | Source |
|---|---|
| inventory / warehouse | `Warehouse.account` → ancestor → `Company.default_inventory_account` |
| Stock Received But Not Billed | `Company.stock_received_but_not_billed` (asset twin: `asset_received_but_not_billed`) |
| Stock Delivered But Not Billed | `Company.stock_delivered_but_not_billed` (+ `enable_stock_delivered_but_not_billed`, `disable_sdbnb_in_sr`) |
| Stock Adjustment | `Company.stock_adjustment_account` |
| COGS | `Company.default_expense_account` |
| expenses added to stock | `expenses_added_to_stock_account` / `_contra_account` (item → item group → brand → Company) |
| purchase expense | `purchase_expense_account` / `_contra_account` (buying_controller.py:1279) |

Note: v17 has **renamed** the classic "Expenses Included In Valuation" / "Stock In Hand" fields into
the `expenses_added_to_stock_*` and `purchase_expense_*` pairs plus `default_inventory_account`.

## 3.3 The canonical pair (`stock/services/base_stock_gl_composer.py`, `BaseStockGLComposer.compose` :30-155)

```
sle_map = doc.get_stock_ledger_details()      # stock_ledger_service.py:56 — SLEs grouped by voucher_detail_no
for item_row in doc.items:
  for sle in sle_map[item_row.name]:
      if inventory_account resolves:
          check_expense_account(item_row)
          expense_account = target-warehouse account if item_row.target_warehouse else item_row.expense_account
          emit { account: inventory_account, debit:      flt(sle.stock_value_difference, precision) }
          emit { account: expense_account,   debit: -1 * flt(sle.stock_value_difference, precision) }
```

Both rows are written as **`debit` with a sign**; `process_gl_map` /
`toggle_debit_credit_if_negative` normalises the negative one into a credit. Consequence:

| Movement | SVD sign | Inventory account | Expense account |
|---|---|---|---|
| inward (receipt) | positive | **Dr** | Cr |
| outward (issue/delivery) | negative | Cr | **Dr** (COGS) |

Cost center / project come from the SLE row, then the item row, then the document.

Two extra layers in the same composer:

- **Internal-transfer rounding gain/loss** (:99-149): if `|Σ SVD for the row| > 1/10^precision` and
  `doc.is_internal_transfer()`, the residual is booked `Company.default_expense_account` Dr vs the
  warehouse asset account Cr (target warehouse for `is_internal_customer`, source for
  `is_internal_supplier`). Throws if `default_expense_account` is unset.
- **`book_expenses_added_to_stock`** (:178-241, gated by `Accounts Settings.book_stock_expense_gl_entries`):
  for stock rows with non-zero Σ SVD, Dr `expenses_added_to_stock_account` / Cr
  `expenses_added_to_stock_contra_account`. Enabled on Stock Entry and Stock Reconciliation composers.

`check_expense_account` (:262-289): throws if no `expense_account`; if `enforce_pl_expense_account`
(class attribute, default True) and the account's `report_type != "Profit and Loss"` → "Expense /
Difference account ({0}) must be a 'Profit or Loss' account"; if it *is* P&L and the row has no cost
center → "Cost Center is mandatory for Item {2}". Delivery Note, Stock Entry and Stock Reconciliation
composers set `enforce_pl_expense_account = False` because they legitimately post to balance-sheet
accounts (SDBNB, Temporary Opening).

Unresolvable warehouses are collected and throw: "Warehouse {0} is not linked to any account…" (:145).

> **Ours** One function `stock_gl_pair(move, accounts) -> [(account_id, signed_amount)]` reading
> `stock_valuation_state.value_delta`. Signed amounts everywhere internally; convert to debit/credit
> once at persist time. `enforce_pl_expense_account` becomes an explicit per-document-type policy
> constant, not a mutable class attribute.

## 3.4 Per-document posting rules

Sign convention below: "Dr X / Cr Y". "(neg-debit)" = written as a negative debit and flipped by the engine.

### Purchase Receipt (`stock/doctype/purchase_receipt/services/gl_composer.py`)

Does **not** use the base loop. `compose` (:26) = `_make_item_gl_entries` + `_make_tax_gl_entries` +
`set_gl_entry_for_purchase_expense` + regional. Per item row, gated by
`flt(d.qty) and (flt(d.valuation_rate) or doc.is_return)`:

| Account | Amount source | Side |
|---|---|---|
| warehouse / inventory (or `d.expense_account` for fixed assets) | `get_stock_value_difference(doc.name, d.name, d.warehouse)` (purchase_receipt.py:523); fixed assets: `base_net_amount + item_tax_amount + landed_cost_voucher_amount` | **Dr** |
| `Company.stock_received_but_not_billed` (or `asset_received_but_not_billed`, or the **from_warehouse** account on inbound internal transfer) | `base_net_amount`; internal transfer: `abs(SVD(from_warehouse))`; `+ SVD(rejected_warehouse)` when `set_valuation_rate_for_rejected_materials` | **Cr** |
| each LCV `taxes.expense_account` | `get_item_account_wise_lcv_entries` share | **Cr** |
| `expenses_added_to_stock_account` / contra | `item.landed_cost_voucher_amount` | Dr / Cr |
| SRBNB again | `item.amount_difference_with_purchase_invoice` | **Cr** |
| `supplier_warehouse` account | `item.rm_supp_cost` | **Cr** |
| divisional-loss account | `(outgoing_amount + landed_cost_voucher_amount + rm_supp_cost + item_tax_amount + amount_difference_with_purchase_invoice) − SVD` | **Dr** |
| each Valuation tax `account_head` | `Σ item.item_tax_amount` apportioned by `get_capitalized_valuation_tax()` | **Cr** |
| `purchase_expense_account` / contra | `valuation_rate * stock_qty − landed_cost_voucher_amount` | Dr / Cr |

`get_divisional_loss_account` (:382): Standard-Cost item → purchase price variance; else
`Company.default_expense_account` → fallback SRBNB; on a return → `item.expense_account`.
Extra rows: an exchange-rate discrepancy pair when the linked PI used a different conversion rate
(:133); a rejected-warehouse inward pair; and a provisional entry for **non-stock** rows when
`enable_provisional_accounting_for_non_stock_items`.

### Delivery Note (`delivery_note/services/gl_composer.py`, 17 lines)

Pure base loop, `enforce_pl_expense_account = False`, no extra rows:
warehouse account **Cr** SVD / `item.expense_account` **Dr** the same magnitude.

`DeliveryNote.validate_expense_account` (delivery_note.py:438-479) decides that account: for stock,
non-asset, non-subcontracted rows not billed against a Sales Invoice, `item.expense_account =
Company.stock_delivered_but_not_billed` when `enable_stock_delivered_but_not_billed`; on a sales return
with `disable_sdbnb_in_sr` it reverts to `default_expense_account`; SDBNB is forbidden on rows linked
to a Sales Invoice; final fallback `default_expense_account`.

### Stock Entry (`stock_entry/services/gl_composer.py`)

Base loop (source warehouse Cr, target Dr), then:
- **Additional costs** (`_build_additional_cost_per_item_account` :189,
  `_append_additional_cost_gl_entries` :219-273): each `additional_costs.expense_account` **Cr**
  `t.amount * (basic_amount or qty) / divide_based_on`; contra is `d.expense_account` **Dr**.
- **LCV** (`_append_lcv_gl_entries` :275): LCV expense account **Cr** `base_amount`,
  `item.expense_account` Dr.
- **Standard-cost variances**: `Manufacture`/`Repack` → `item.amount − Σ positive SVD` to
  `get_manufacturing_variance_account` (:59); `Material Receipt` → the same delta to
  `get_purchase_price_variance_account` (:82).

### Stock Reconciliation (`stock_reconciliation/services/gl_composer.py`)

Throws if no cost center. Because SR has no expense rows, `get_voucher_details` (:33) **synthesises a
pseudo-row per SLE** keyed by `voucher_detail_no`, with `is_opening = "Yes"` when
`purpose == "Opening Stock"`. Then: warehouse account ± SVD vs `doc.expense_account` (default
`Company.stock_adjustment_account`), plus the `expenses_added_to_stock` pair.
`validate_expense_account`
(`stock/doctype/stock_reconciliation/stock_reconciliation.py:1098`) forces an
**Asset/Liability** difference account for
`Opening Stock` → `OpeningEntryAccountError`.

### Sales Invoice (`accounts/doctype/sales_invoice/services/gl_composer.py`)

`compose` order (:23-59): customer → taxes → internal transfer → items → SDBNB reversal → precision
loss → discounts → regional → `merge_similar_entries` → loyalty → POS → write-off → rounding.

| Method | Account | Amount | Side |
|---|---|---|---|
| `make_customer_gl_entry` :228 | `doc.debit_to` | `base_rounded_total` / `base_grand_total`; `against_voucher = return_against` when a return not tracking its own outstanding (`_resolve_against_voucher` :679) | **Dr** (skipped entirely for internal transfer) |
| `make_tax_gl_entries` :269 | each `tax.account_head` | `base_tax_amount_after_discount_amount` | **Cr** |
| `_append_item_income_gl_entry` :355 | `item.income_account`, or **`item.deferred_revenue_account`** when deferred revenue is on and not a return | `base_net_amount` | **Cr** |
| stock side :385 | `gl_entries += super().get_gl_entries()` — only when `update_stock` and perpetual | warehouse Cr / COGS Dr from SVD |
| `stock_delivered_but_not_billed_gl_entries` :163 | SDBNB Cr / `item.expense_account` Dr | `(SLE.stock_value_difference / SLE.actual_qty of the DN row) * item.stock_qty` | reclassifies the DN's SDBNB into COGS at billing time; only when **not** `update_stock` |
| `make_pos_gl_entries` :492 | `debit_to` Cr / `payment_mode.account` Dr | `payment_mode.base_amount` | + change-amount pair |
| `make_write_off_gl_entry` :604 | `debit_to` Cr / `write_off_account` Dr | `base_write_off_amount` | POS only |
| `make_loyalty_point_redemption_gle` :449 | `debit_to` Cr / `loyalty_redemption_account` Dr | `loyalty_amount` | |
| discounts / precision loss / rounding | `discount_account`, round-off | `discount_amount*qty`, `base_net_total − net_total*conversion_rate`, `base_rounding_adjustment` | |

### Purchase Invoice (`accounts/doctype/purchase_invoice/services/gl_composer.py`)

`compose` (:18): supplier → items → precision loss → taxes → internal transfer → TDS → regional →
merge → payment → write-off → rounding → purchase expense.

| Method | Account | Amount | Side |
|---|---|---|---|
| `make_supplier_gl_entry` :80 | `doc.credit_to` | `base_rounded_total` / `base_grand_total` | **Cr** |
| items, stock branch :170 (needs `update_stock and auto_accounting_for_stock`) | warehouse Dr `warehouse_debit_amount`; `from_warehouse` neg-debit; `item.expense_account` Dr | from `make_stock_adjustment_entry` | |
| **`make_stock_adjustment_entry` :562** | variance account (`get_stock_variance_account` :529: Standard Cost → PPV; else `default_expense_account`; on returns `item.expense_account`; else SRBNB) | **`valuation_rate*qty*conversion_factor` (document's intended value) − SLE `stock_value_difference` (actual)** and returns `warehouse_debit_amount = stock_amount` so the warehouse leg always equals the SLE | Dr |
| items, non-stock branch :268 | `item.expense_account` or `item.deferred_expense_account` | `base_amount`. **This is the leg that clears SRBNB**, because `PurchaseInvoiceExpenseAccountService` (`services/expense_account.py:25`) sets `expense_account = Company.stock_received_but_not_billed` for PR-linked stock rows when `update_stock == 0` | Dr |
| SRBNB tax reversal :357 | `doc.stock_received_but_not_billed` | `item.item_tax_amount`, only when the PR did not already book those valuation tax accounts (checked by GL Entry existence); accumulates `negative_expense_to_be_booked` | Dr |
| `make_tax_gl_entries` :645 | Total-category taxes on `account_head`; Valuation taxes credited with `negative_expense_to_be_booked` apportioned by `get_capitalized_valuation_tax()` | | |
| provisional reversal :496 | reverses the PR's provisional entry, prorated `min(pi_qty, pr_qty) * pr_rate * conversion_rate` | | |

> That `make_stock_adjustment_entry` line is the crux of PI stock accounting: **the warehouse leg is
> forced to equal the SLE, and the document-vs-ledger difference goes to a variance account.** Copy the
> principle exactly; the alternative is silent drift.

### Subcontracting Receipt (`subcontracting_receipt/services/gl_composer.py`)

Returns `[]` when perpetual inventory is off. Otherwise:
accepted warehouse **Dr** SVD; `item.expense_account` **Cr** `SVD − service_cost`;
`service_expense_account` **Cr** `service_cost`; per RM row `supplier_warehouse` **Cr**
`rm_item.amount` with `rm_item.expense_account` **Dr**; `item.expense_account` **Dr**
`qty * additional_cost_per_qty`; `Company.stock_adjustment_account` **Cr** `item.amount − SVD`
(divisional loss); additional costs and LCV shares **Cr**.

## 3.5 Rate / valuation interaction

`BuyingController.update_valuation_rate` (buying_controller.py:425-500) is the authority for the
inbound rate:
```
item.item_tax_amount = flt(item_tax_amount + actual_charge_per_item[item.idx], precision)
net_rate = item.base_net_amount                     # or qty*sales_incoming_rate for internal transfer
item.valuation_rate = (net_rate + item.item_tax_amount
                       + flt(item.landed_cost_voucher_amount)
                       + flt(item.amount_difference_with_purchase_invoice)) / qty_in_stock_uom
```
Non-stock/non-asset rows get `valuation_rate = 0`. `item_tax_amount` = "On Net Total" **Valuation**
taxes (`get_item_tax_amount` :528, rounding remainder on the last row) **plus** the row's share of
"Actual" valuation charges (`_spread_charge_over_items` :547 — proportional to `base_net_amount`,
falling back to qty; charges flagged `allocate_full_amount_to_stock_items` spread over stock/asset rows
only). `rm_supp_cost` is *not* in this formula — it enters valuation through the SLE incoming rate on
subcontracted receipts and is credited out of the supplier warehouse in the GL.

Outbound rate: `SellingController.set_incoming_rate` (selling_controller.py:515-672) for DN and for SI
when `update_stock` or internal transfer. Skips non-stock items; zero for expired-batch standalone
credit notes; else `get_incoming_rate({item, warehouse, posting_date/time, ±qty, bundle, voucher…})`;
`reset_incoming_rate()` clears a stale rate when item/warehouse/qty/serial/batch changed; returns
against a reference use `get_rate_for_return(...)` so the return leaves stock at the **original cost**;
internal transfers force `d.rate = incoming_rate * conversion_factor` and zero the discounts.

## 3.6 Landed Cost Voucher

Distribution (`set_applicable_charges_on_item`, :222-252): spread `Σ taxes.base_amount` over rows in
proportion to `qty` or `amount`, remainder on the last row; `Distribute Manually` keeps user values.
`validate_applicable_charges_for_item` (:254) re-checks the sum within 2 units of precision,
auto-absorbing a small diff into `items[-1]`.

`update_landed_cost` (:322-364), run on both submit and cancel, is the rewrite path:
1. `set_landed_cost_voucher_amount` writes `item.landed_cost_voucher_amount = Σ applicable_charges`
   into each receipt row.
2. `doc.update_valuation_rate(reset_outgoing_rate=False)` recomputes valuation.
3. Then per receipt document: `docstatus = 2` → `update_stock_ledger(via_landed_cost_voucher=True)` +
   `make_gl_entries_on_cancel()`; `docstatus = 1` → rebuild bundles → `update_stock_ledger(...)` →
   `make_gl_entries(...)` → `repost_future_sle_and_gle(...)`.
   **So the SLEs are deleted/rewritten with the new valuation and the GL is fully re-derived, then
   everything downstream is reposted.**
4. `update_rate_in_serial_no_for_non_asset_items` pushes the new rate into `Serial No.purchase_rate`.

`get_item_account_wise_lcv_entries(doc)` (:582) returns `{(item_code, row_name): {expense_account:
{amount, base_amount}}}` — consumed by the PR/PI/Stock Entry/SCR composers to credit the landed-cost
expense accounts against inventory.

> **Ours** Landed cost is an *event*, not a rewrite: `landed_cost_allocation(move_id, cost_account_id,
> amount)` rows plus a `revaluation` move with `qty_delta = 0`. The projection recomputes forward from
> that point; no SLE is ever deleted and re-inserted, and the original receipt stays auditable at its
> original value.

## 3.7 GL reposting after a backdated stock change

`accounts/utils.py:1656` `update_gl_entries_after` → `repost_gle_for_stock_vouchers` (:1665-1714):

```
for each future stock voucher (chronologically, sort_stock_vouchers_by_posting_date :1741):
    expected = voucher_obj.get_gl_entries(inventory_account_map)
    toggle_debit_credit_if_negative(expected)
    if not compare_existing_and_expected_gle(existing, expected):     # :1839, per account+cost center within precision
        _delete_accounting_ledger_entries(voucher)                    # delete GL + PLE
        make_gl_entries(expected, from_repost=True)
```
`get_future_stock_vouchers` (:1770-1826) locks the matching SLE rows `FOR UPDATE` (in a separate pass
on Postgres, because `FOR UPDATE` is invalid with `GROUP BY`) so concurrent stock transactions cannot
slip in.

> **Invariant** Reposting is idempotent: GL is only replaced when it differs. `gl_reposting_index`
> allows resume.

Which vouchers get reposted (`repost_item_valuation.py::repost_gl_entries`): all future stock vouchers
for the affected items/warehouses, **plus** `get_affected_transactions(doc)` — the
`(voucher_type, voucher_no)` set collected in `process_sle` whenever a *different* item-warehouse's
SVD changed (persisted in the gz checkpoint file), plus optionally Sales Invoices tied to reposted
Delivery Notes.

## 3.8 Drift detection

- **`stock/report/stock_and_account_value_comparison/`** — throws unless perpetual inventory.
  Groups SLEs by `(voucher_type, voucher_no)` summing `stock_value_difference` (:83) and GL entries on
  Stock-type accounts by voucher summing `debit_in_account_currency − credit_in_account_currency`
  (:108); reports rows where `abs(stock_value − account_value) > 0.1`, plus GL vouchers with **no**
  SLEs at all (:61). Remediation is built in: `create_reposting_entries` submits
  `Repost Item Valuation` docs (transaction-based with `recalculate_valuation_rate = 1` for PR/PI,
  item-and-warehouse-based otherwise), each inside a savepoint to survive `DuplicateEntryError`.
- **`accounts/utils.py:1906 get_stock_and_account_balance(account, posting_date, company)`** returns
  `(account_balance, total_stock_value, related_warehouses)`, narrowing the stock side to the
  warehouses mapped to that account when more than one Stock account exists. Used by
  `JournalEntry.validate_stock_accounts` (journal_entry.py:380) which throws
  `StockAccountInvalidTransaction` "Account: {0} can only be updated via Stock Transactions" **when the
  account balance already equals the stock balance** — i.e. a manual JE would create drift.
- **`stock/report/incorrect_stock_value_report/`** walks day by day from the first SLE until
  `abs(account_bal − stock_bal) > 0.1`, then lists the offending vouchers.
- SLE-internal integrity reports also exist: `stock_ledger_invariant_check`,
  `stock_ledger_variance`, `incorrect_balance_qty_after_transaction`,
  `fifo_queue_vs_qty_after_transaction_comparison`.

> **Ours** These reports are evidence that drift is expected in production. Invert it: make the
> reconciliation a **continuous constraint**, not a report. A nightly (and post-recompute) job asserts
> per company × inventory account × date: `Σ gl_entry.signed_amount == Σ stock_valuation_state.value_delta`
> for the mapped warehouses, and writes the result to `reconciliation_check` with a hard alert on
> failure. Also keep the "manual JE to an inventory account is refused" rule — but unconditionally,
> not only when the balances happen to match.

---

## What to take from this chapter

**Copy:** GL amounts for inventory read from the stock projection, never from document amounts; the
document-vs-ledger difference forced into a named variance account; SRBNB/SDBNB as explicit accrual
accounts with a documented clearing leg; returns valued at the original cost; the
"compare-then-replace" idempotent repost; refusing manual JEs on inventory accounts.

**Reject:** landed cost implemented by deleting and re-inserting ledger rows; per-document composers
that each re-derive account resolution; the same conceptual account under three different field names
across versions; drift detection as an opt-in report.
