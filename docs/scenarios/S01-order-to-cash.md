# S01 — Order to Cash: Sales Order → Delivery Note → Sales Invoice

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Docs 01–25 are organised **by subsystem**. This document is organised **by business flow** —
> it traces one order end to end and shows every table written, in order, with worked numbers.

---

## 1. The worked example

Customer **ACME**, company **AlphaCo** (base currency INR), sells:

| Line | Item | Qty | Rate | Amount |
|---|---|---:|---:|---:|
| 1 | WIDGET-A | 100 EA | 500.00 | 50 000.00 |
| 2 | WIDGET-B | 40 EA | 250.00 | 10 000.00 |
| | | | **Net** | **60 000.00** |
| | | | GST 18 % | 10 800.00 |
| | | | **Grand total** | **70 800.00** |

Stock on hand for WIDGET-A: 500 @ moving-average valuation 300.00.
WIDGET-B: 200 @ 150.00.

Fulfilment plan (deliberately messy, because that is the real case):

1. **SO-0001** for all 140 units.
2. **DN-0001** ships 60 of WIDGET-A only.
3. **SI-0001** bills DN-0001.
4. **DN-0002** ships remaining 40 of WIDGET-A + all 40 of WIDGET-B.
5. **SI-0002** bills DN-0002, but only 30 of the 40 WIDGET-B (dispute).
6. Customer returns 10 WIDGET-A.

Payments are covered in **S02**.

---

## 2. Stage 1 — Sales Order submit

### 2.1 Draft: what happens before anything is written

On every save (draft or submit), `validate` runs the calculation pipeline (doc 05):

```
SalesOrder.validate                      selling/doctype/sales_order/sales_order.py:219
  → SellingController.validate           controllers/selling_controller.py:60
  → AccountsController.validate          controllers/accounts_controller.py:213
      set_missing_values                 controllers/accounts_controller.py:569
      calculate_taxes_and_totals         controllers/accounts_controller.py:576
        → calculate                      controllers/taxes_and_totals.py:46
          → _calculate                   controllers/taxes_and_totals.py:78
            → determine_exclusive_rate   controllers/taxes_and_totals.py:303
            → calculate_taxes            controllers/taxes_and_totals.py:424
      validate_due_date                  controllers/accounts_controller.py:615
      set_advances                       controllers/accounts_controller.py:969  (doc 11 §2.1)
  → validate_delivery_date               selling/doctype/sales_order/sales_order.py:361
  → validate_warehouse                   selling/doctype/sales_order/sales_order.py:395
  → validate_with_previous_doc           selling/doctype/sales_order/sales_order.py:414
```

Note `set_advances` runs on a **Sales Order** too — if the customer already has unallocated
advance payments, they are pulled onto the order at draft time (doc 11 §2.1).

### 2.2 Submit

`SalesOrder.on_submit` (`selling/doctype/sales_order/sales_order.py:450`), in exact order:

```python
super().update_prevdoc_status()      # → Quotation Item.ordered_qty  (status_updater cfg :187)
self.check_credit_limit()            # :514
self.update_reserved_qty()           # :544 → Bin.reserved_qty
DeliveryScheduleService(self).delete_removed_delivery_schedule_items()
frappe.get_cached_doc("Authorization Control").validate_approving_authority(
    self.doctype, self.company, self.base_grand_total, self)     # ← the "approval" (doc 09 §1.5a)
self.update_project()                # :505
self.update_prevdoc_status("submit")
self.update_blanket_order()
update_linked_doc(...)               # inter-company mirror (doc 15 §1)
if self.coupon_code: update_coupon_code_count(...)
if self.get("reserve_stock") and not self.get("is_subcontracted"):
    self.create_stock_reservation_entries()      # :658 (doc 16 §2)
```

### 2.3 What is now on disk

| Table | Rows | Notable columns |
|---|---|---|
| `tabSales Order` | 1 | `docstatus=1`, `status='To Deliver and Bill'`, `per_delivered=0`, `per_billed=0`, `grand_total=70800` |
| `tabSales Order Item` | 2 | `delivered_qty=0`, `billed_amt=0`, `returned_qty=0`, `work_order_qty=0`, `picked_qty=0` |
| `tabSales Taxes and Charges` | 1 | GST row, `tax_amount=10800` |
| `tabPayment Schedule` | 1+ | derived from Payment Terms Template (doc 05) |
| `tabBin` | 2 | `reserved_qty` += 100 / 40 |
| `tabStock Reservation Entry` | 0 or 2 | only if `reserve_stock` |

**No GL entries. No Stock Ledger Entries.** An order is a commitment, not a posting. Correct.

`status` came from `status_map["Sales Order"]` (`controllers/status_updater.py:43`) — the eval
string `per_delivered < 100 and per_billed < 100 and docstatus == 1` → `'To Deliver and Bill'`.

---

## 3. Stage 2 — Delivery Note DN-0001 (60 × WIDGET-A)

### 3.1 The link is created at draft time

The FE (or `make_delivery_note` mapper) copies SO lines and sets, **on the Delivery Note Item
row**:

```
so_detail            = <SO-0001 Item row 1 name>       ← the fulfilment link
against_sales_order  = SO-0001                          ← header-level convenience column
```

`DeliveryNote.validate_with_previous_doc` (`stock/doctype/delivery_note/delivery_note.py:299`)
and `validate_sales_order_references` (`:351`) check consistency.

### 3.2 Submit — the ordering matters enormously

`DeliveryNote.on_submit` (`stock/doctype/delivery_note/delivery_note.py:481`):

```python
self.validate_packed_qty()                     # :619
self.update_pick_list_status()
frappe.get_cached_doc("Authorization Control").validate_approving_authority(...)

# update delivered qty in sales order
self.update_prevdoc_status()                   # ← StatusUpdater, doc 10 §1.1
self.update_billing_status()                   # :645

if not self.is_return: self.check_credit_limit()          # :586
elif self.issue_credit_note: BillingStatusService(self).make_return_invoice()

for table_name in ["items", "packed_items"]:
    self.make_bundle_for_sales_purchase_return(table_name)
    self.make_bundle_using_old_serial_batch_fields(table_name)

self.validate_standalone_serial_nos_customer()
self.update_stock_reservation_entries()

# Updating stock ledger should always be called after updating prevdoc status,
# because updating reserved qty in bin depends upon updated delivered qty in SO
self.update_stock_ledger()                     # controllers/selling_controller.py:676
self.make_gl_entries()                         # controllers/stock_controller.py:178
self.repost_future_sle_and_gle()
```

That comment (`:508`–`:509`) is the load-bearing sentence of the whole flow: **`Bin.reserved_qty`
is derived from `Sales Order Item.delivered_qty`, so the SO counter must be updated before the
stock ledger touches `Bin`.** Three caches in a dependency chain, maintained by ordering
convention inside one Python method.

### 3.3 Step A — `update_prevdoc_status` walks the config

Delivery Note declares **three** `status_updater` edges
(`stock/doctype/delivery_note/delivery_note.py:157`). For our case the SO edge fires:

```
source_dt = Delivery Note Item, target_dt = Sales Order Item
join_field = so_detail, source_field = qty, target_field = delivered_qty
second_source_dt = Sales Invoice Item (where SI.update_stock = 1)
target_parent_field = per_delivered, status_field = delivery_status
```

`update_qty` (`controllers/status_updater.py:533`) → `_update_children` (`:550`):

```sql
-- for SO-0001 Item row 1
SELECT COALESCE(SUM(qty),0) FROM `tabDelivery Note Item`
 WHERE so_detail = 'SO-Item-1' AND (docstatus = 1 OR parent = 'DN-0001')
-- → 60
-- plus second source (SI with update_stock=1) → 0
UPDATE `tabSales Order Item` SET delivered_qty = 60 WHERE name = 'SO-Item-1'
```

Then `_update_percent_field` (`:658`) → `_calculate_target_parent_percentage` (`:606`):

```
Σ LEAST(delivered_qty, qty) = LEAST(60,100) + LEAST(0,40) = 60
Σ qty                       = 140
per_delivered = 60/140 × 100 = 42.857143
```

`_determine_status` (`:633`) → `delivery_status = 'Partly Delivered'`.
Then `target.get_status()` re-evaluates `status_map` → SO stays `'To Deliver and Bill'`.
All written via `db_set(..., notify=True)` (`:678`) — **on a submitted Sales Order, bypassing the
timestamp lock** (doc 09 §1.3).

**Over-delivery check** (`validate_qty`, `:266` → `check_overflow_with_allowance`, `:419`) runs in
`validate`, before this — `overflow_percent = (achieved − ordered)/ordered × 100`, compared
against `Item.over_delivery_receipt_allowance` → `Stock Settings.over_delivery_receipt_allowance`,
bypassable by `Stock Settings.role_allowed_to_over_deliver_receive`.

### 3.4 Step B — `update_stock_ledger`

`SellingController.update_stock_ledger` (`controllers/selling_controller.py:676`) builds SL entries
via `get_sle_for_source_warehouse` (`:708`), then `make_sl_entries`
(`stock/stock_ledger.py:104`) → `process_sle` (`stock/stock_ledger.py:1008`).

Outgoing 60 × WIDGET-A at moving average 300.00:

| `tabStock Ledger Entry` column | Value |
|---|---|
| `item_code` / `warehouse` | WIDGET-A / Main |
| `actual_qty` | −60 |
| `qty_after_transaction` | 440 |
| `valuation_rate` | 300.00 |
| `stock_value` | 132 000.00 |
| `stock_value_difference` | **−18 000.00** |
| `voucher_type` / `voucher_no` / `voucher_detail_no` | Delivery Note / DN-0001 / `<DN item row>` |

`Bin` is updated: `actual_qty` 500 → 440, and `reserved_qty` recomputed from
`SO Item.delivered_qty` (now 60) → 100 − 60 = 40 still reserved.

**Note `stock_value_difference` = −18 000.** This single column is the bridge to accounting
(doc 03).

### 3.5 Step C — `make_gl_entries`

`StockController.make_gl_entries` (`controllers/stock_controller.py:178`) →
`base_stock_gl_composer.compose` (`stock/services/base_stock_gl_composer.py:27`), reading
`stock_value_difference` **back from the SLE rows just written**:

| Account | Debit | Credit |
|---|---:|---:|
| Cost of Goods Sold | 18 000.00 | |
| Stock In Hand | | 18 000.00 |

Then `make_gl_entries` (`accounts/general_ledger.py:34`) → `process_gl_map` (`:141`) →
`merge_similar_entries` (`:226`) → `toggle_debit_credit_if_negative` (`:316`) →
`process_debit_credit_difference` (`:397`) → `save_entries` (`:359`) → `make_entry` (`:377`).

**A Delivery Note posts COGS but no revenue.** Revenue arrives with the invoice. Between DN and
SI, the P&L carries cost without matching income — the classic unbilled-shipment gap. ERPNext's
answer is a report, not an accrual.

### 3.6 State after DN-0001

| Table | Change |
|---|---|
| `tabDelivery Note` | `docstatus=1`, `status='To Bill'`, `per_billed=0` |
| `tabSales Order Item` row 1 | `delivered_qty=60` |
| `tabSales Order` | `per_delivered=42.857143`, `delivery_status='Partly Delivered'` |
| `tabStock Ledger Entry` | 1 row, `stock_value_difference=-18000` |
| `tabBin` WIDGET-A | `actual_qty=440`, `reserved_qty=40` |
| `tabGL Entry` | 2 rows (COGS / Stock In Hand) |

---

## 4. Stage 3 — Sales Invoice SI-0001 (bills DN-0001)

### 4.1 The links

`Sales Invoice Item` carries **two** upstream links:

```
so_detail = <SO Item row 1>      → for billing progress on the order
dn_detail = <DN-0001 item row>   → for billing progress on the delivery
sales_order = SO-0001, delivery_note = DN-0001   (header convenience columns)
```

`so_dn_required` (`accounts/doctype/sales_invoice/sales_invoice.py:854`) can force these to be
present; `validate_with_previous_doc` (`:784`) checks consistency.

### 4.2 Submit

`SalesInvoice.on_submit` (`accounts/doctype/sales_invoice/sales_invoice.py:421`), abridged to the
flow-relevant parts:

```python
POSService(self).validate_pos_paid_amount()
if not self.auto_repeat:
    Authorization Control.validate_approving_authority(...)     # ← :424, doc 09 §1.5a
self.check_prev_docstatus()
if self.is_return and not self.update_billed_amount_in_sales_order:
    self.status_updater = []          # ← returns skip status propagation entirely
SalesTaxWithholding(self).on_submit()
self.update_status_updater_args()     # :594 — adds SO/Pick List edges IF update_stock=1
self.update_prevdoc_status()          # → SO Item.billed_amt, DN Item.billed_amt
self.update_billing_status_in_dn()
self.clear_unallocated_mode_of_payments()
if self.update_stock == 1:
    ... bundles ...
    self.update_stock_reservation_entries()
    self.update_stock_ledger()        # ← only if update_stock
FixedAssetService(...)...
self.make_gl_entries()                # :1030
if self.update_stock == 1:
    self.repost_future_sle_and_gle(); self.update_pick_list_status()
if not self.is_return:
    self.update_billing_status_for_zero_amount_refdoc("Delivery Note")   # doc 10 §3
    self.update_billing_status_for_zero_amount_refdoc("Sales Order")
    self.check_credit_limit()
    self.check_overdue_billing_threshold()
if cint(self.is_pos) != 1 and not self.is_return:
    self.update_against_document_in_jv()      # controllers/accounts_controller.py:1023 → advances
TimesheetBillingService(...)...
if Selling Settings.sales_update_frequency == "Each Transaction":
    update_company_current_month_sales(self.company); self.update_project()
update_linked_doc(...)                # inter-company
... coupon, loyalty ...
self.process_common_party_accounting()
self.update_billed_qty_in_scio()
```

**`update_stock` is the fork.** A Sales Invoice with `update_stock = 1` *also* moves stock — which
is why `Sales Order Item.delivered_qty` has **two source tables** (doc 10 §2 point 5) and why
`update_status_updater_args` (`:594`) conditionally injects extra edges with an
`extra_cond` containing a correlated `EXISTS` on `update_stock = 1`, written as a Python string.

Our case: `update_stock = 0` (stock already moved by the DN), so only billing counters move.

### 4.3 Billing propagation

Sales Invoice's base `status_updater` (`accounts/doctype/sales_invoice/sales_invoice.py:260`)
targets **amount**, not qty:

```
source_dt = Sales Invoice Item, target_dt = Sales Order Item
join_field = so_detail, source_field = amount, target_field = billed_amt
target_ref_field = amount, target_parent_field = per_billed
```

SI-0001 bills 60 × 500 = 30 000 net.

```
SO Item row 1: billed_amt = 30 000   (ref amount = 50 000)
SO Item row 2: billed_amt = 0        (ref amount = 10 000)
Σ LEAST(billed, amount) = 30 000
Σ amount                = 60 000
per_billed = 50.000000  → billing_status = 'Partly Billed'
```

And on the Delivery Note, `update_billing_status_in_dn` sets DN-0001
`per_billed = 100` → `status = 'Completed'`.

⚠️ **Note the unit mismatch:** the order's delivery progress is measured in **quantity**
(`delivered_qty` vs `qty`) while billing progress is measured in **amount** (`billed_amt` vs
`amount`). A line billed at a different rate than ordered makes `per_billed` diverge from any
quantity-based intuition — and a zero-value line makes the denominator zero, which is why
`update_billing_status_for_zero_amount_refdoc` (`controllers/status_updater.py:694`) exists.

### 4.4 GL entries

`SalesInvoice.make_gl_entries` (`accounts/doctype/sales_invoice/sales_invoice.py:1030`):

| Account | Debit | Credit |
|---|---:|---:|
| Debtors (party = ACME) | 35 400.00 | |
| Sales — Revenue | | 30 000.00 |
| Output GST 18 % | | 5 400.00 |

`GL Entry` rows carry `against_voucher_type='Sales Invoice'`, `against_voucher='SI-0001'`,
`party_type='Customer'`, `party='ACME'` on the Debtors line.

### 4.5 The Payment Ledger mirror

Inside `make_gl_entries` → `accounts/general_ledger.py:34`, the receivable line is mirrored into
the payment subledger:

```
get_payment_ledger_entries      accounts/utils.py:2024
create_payment_ledger_entry     accounts/utils.py:2151
update_voucher_outstanding      accounts/utils.py:2175
```

| `tabPayment Ledger Entry` | Value |
|---|---|
| `voucher_type` / `voucher_no` | Sales Invoice / SI-0001 |
| `against_voucher_type` / `against_voucher_no` | Sales Invoice / SI-0001 (self) |
| `party_type` / `party` | Customer / ACME |
| `account` | Debtors |
| `amount` | +35 400.00 |
| `delinked` | 0 |

and `Sales Invoice.outstanding_amount = 35 400.00`, plus a row in `ac_doc_balances`-equivalent
(`update_voucher_outstanding`). **`outstanding_amount` is a cached column** — doc 04 §6 documents
the unlocked read-then-write race.

### 4.6 State after SI-0001

| Table | Change |
|---|---|
| `tabSales Invoice` | `docstatus=1`, `status='Unpaid'`, `outstanding_amount=35400` |
| `tabSales Order Item` row 1 | `billed_amt=30000` |
| `tabSales Order` | `per_delivered=42.857143`, `per_billed=50.000000`, `status='To Deliver and Bill'` |
| `tabDelivery Note` | `per_billed=100`, `status='Completed'` |
| `tabGL Entry` | +3 rows |
| `tabPayment Ledger Entry` | +1 row |

---

## 5. Stage 4 — DN-0002, then partial SI-0002

**DN-0002**: 40 × WIDGET-A + 40 × WIDGET-B.

```
SO Item 1: delivered_qty = 60 + 40 = 100
SO Item 2: delivered_qty = 0 + 40  = 40
Σ LEAST(delivered, qty) = 100 + 40 = 140 ;  Σ qty = 140
per_delivered = 100.000000  →  delivery_status = 'Fully Delivered'
```

SO status re-evaluates: `per_delivered >= 100 and per_billed < 100` → **`'To Bill'`**.

Stock: WIDGET-A −40 (SVD −12 000), WIDGET-B −40 @150 (SVD −6 000). GL: COGS 18 000 / Stock In
Hand 18 000.

**SI-0002** bills 40 × WIDGET-A (20 000) but only 30 × WIDGET-B (7 500):

```
SO Item 1: billed_amt = 30 000 + 20 000 = 50 000   (ref 50 000)  ✓ fully billed
SO Item 2: billed_amt = 7 500                       (ref 10 000)
Σ LEAST(billed, amount) = 50 000 + 7 500 = 57 500
Σ amount                = 60 000
per_billed = 95.833333  →  billing_status = 'Partly Billed'
```

SO status: `per_delivered >= 100` but `per_billed = 95.83 < 100` → **stays `'To Bill'`**.
DN-0002 `per_billed = (20 000 + 7 500)/(20 000 + 10 000) × 100 = 91.666667` →
`status = 'Partially Billed'`.

**The order is now fully shipped but permanently `'To Bill'`** — 2 500 will never be invoiced
because it is a commercial dispute. The only closures available are:

- `close_or_unclose_sales_orders` (`selling/doctype/sales_order/sales_order.py:714`) — writes the
  string `'Closed'` into `status`, which then satisfies its own eval condition (doc 10 §4). No
  `closed_by`, no `closed_at`, no reason.
- Or edit the submitted SO's line quantity/amount (`update_items`), rewriting history.

⚠️ There is **no way to close one line** and leave the rest open.

---

## 6. Stage 5 — Return of 10 × WIDGET-A

A return is a **negative Delivery Note** (or negative Sales Invoice) with `is_return = 1` and
`return_against = DN-0002`.

```
validate_return                 controllers/sales_and_purchase_return.py:22
validate_return_against         controllers/sales_and_purchase_return.py:32
validate_returned_items         controllers/sales_and_purchase_return.py:86
validate_quantity               controllers/sales_and_purchase_return.py:172
get_already_returned_items      controllers/sales_and_purchase_return.py:274
make_return_doc                 controllers/sales_and_purchase_return.py:430
get_rate_for_return             controllers/sales_and_purchase_return.py:741
```

`validate_qty` (`controllers/status_updater.py:266`) enforces the sign rule: return rows must
have `qty < 0`, non-return rows `qty > 0` (`:280`–`:287`).

Effects:

- **Stock**: SLE with `actual_qty = +10`. Incoming rate for a sales return comes from
  `get_rate_for_return` (`:741`) — the **original outgoing valuation**, not current market, so the
  return does not distort the moving average.
- **`returned_qty`**: a separate `status_updater` edge appended only for returns, with
  `source_field = "-1 * qty"` (`accounts/doctype/sales_invoice/sales_invoice.py:638`–`:650`,
  writing `target_field = "returned_qty"` at `:643`) updates `SO Item.returned_qty` and
  `per_returned`. Note its `extra_cond` restricts it to invoices with
  `update_stock = 1 and is_return = 1`.
- **`delivered_qty` is NOT reduced.** The return is tracked in a parallel counter. So
  `per_delivered` stays 100 while 10 units are back in the warehouse. Two counters, one truth.
- **DN status**: `per_returned == 100` → `'Return Issued'`; the return document itself gets
  `'Return'` (`controllers/status_updater.py:97`–`:98`).
- **Credit note**: if `issue_credit_note`, `BillingStatusService(self).make_return_invoice()`
  (`stock/doctype/delivery_note/delivery_note.py:497`) creates a negative Sales Invoice, which
  posts reversing GL and a **negative Payment Ledger Entry** — reducing the receivable.

---

## 7. Full write ledger for the whole scenario

| Stage | GL Entry | SLE | PLE | Counters mutated on submitted docs |
|---|---:|---:|---:|---|
| SO-0001 submit | 0 | 0 | 0 | Quotation Item.ordered_qty, Bin.reserved_qty |
| DN-0001 submit | 2 | 1 | 0 | SO Item.delivered_qty, SO.per_delivered, SO.delivery_status, SO.status, Bin.actual_qty, Bin.reserved_qty |
| SI-0001 submit | 3 | 0 | 1 | SO Item.billed_amt, SO.per_billed, SO.billing_status, SO.status, DN.per_billed, DN.status, SI.outstanding_amount |
| DN-0002 submit | 2 | 2 | 0 | same set as DN-0001 |
| SI-0002 submit | 3 | 0 | 1 | same set as SI-0001 |
| Return DN | 2 | 1 | 0 | SO Item.returned_qty, SO.per_returned, DN.per_returned, DN.status |
| Credit note | 3 | 0 | 1 | SI.outstanding_amount (of the return), original SI unchanged |

**15 GL rows, 5 SLE rows, 3 PLE rows — and ~30 cached-counter writes to already-submitted
documents,** every one of them through `db_set` outside the optimistic lock.

That ratio is the finding. The *ledger* work is small and correct. The *counter* work is large,
unprotected, and is where every fulfilment bug in ERPNext lives (doc 10 §7).

---

## 8. Same scenario in our design

### 8.1 SO-0001 posted

```sql
INSERT INTO voucher (id, company_id, doc_type, doc_no, lifecycle_state, approval_state,
                     party_id, currency_code, exchange_rate, posting_date, ...)
     VALUES (:so_id, ..., 'sales_order', 'SO-0001', 'posted', 'approved', ...);
INSERT INTO sales_order_line (id, voucher_id, line_no, item_id, qty_stock, uom_id, rate, ...) × 2;
INSERT INTO line_registry (line_id, doc_type, doc_id, company_id) × 2;   -- trigger
INSERT INTO payment_schedule (...) × 1;
INSERT INTO lifecycle_event (resource, resource_id, from_state, to_state, actor_user_id) × N;  -- trigger
```

No `delivered_qty`, no `billed_amt`, no `per_delivered`, no `status` column, no `Bin.reserved_qty`.
Progress is a **view** (doc 10 §5.2).

### 8.2 DN-0001 posted — one transaction

```sql
-- 1. the document
INSERT INTO delivery_note ...;  INSERT INTO delivery_note_line ... (60 × WIDGET-A);

-- 2. the fulfilment link  (replaces SO Item.delivered_qty)
INSERT INTO doc_link (source_doc_type, source_doc_id, source_line_id,
                      target_doc_type, target_doc_id, target_line_id,
                      link_kind, qty_stock, amount_base)
     VALUES ('sales_order', :so_id, :so_line_1, 'delivery_note', :dn_id, :dn_line_1,
             'deliver', 60, 30000.00);

-- 3. the stock event  (immutable)
INSERT INTO stock_move (item_id, warehouse_id, voucher_id, voucher_line_id,
                        posting_at, qty_stock)
     VALUES (:widget_a, :main, :dn_id, :dn_line_1, now(), -60);
--    trigger: stock_on_hand ON CONFLICT DO UPDATE qty_on_hand = qty_on_hand + (-60)
--             ^ takes the row lock as part of the statement (doc 16 §5.1)
--    trigger: stock_valuation_state → consumes 60 @ 300 → cogs_base = 18000

-- 4. the GL  (append-only, balanced by constraint F1)
INSERT INTO gl_entry (voucher_id, account_id, debit_base, credit_base) VALUES
       (:dn_id, :cogs,          18000, 0),
       (:dn_id, :stock_in_hand,     0, 18000);
```

Four inserts and two triggers. **Zero updates to SO-0001.** The order row is untouched from the
moment it was posted until it is closed or reversed.

`per_delivered` is read on demand:

```sql
SELECT per_delivered, per_billed, delivery_complete, billing_complete
FROM fulfilment_doc WHERE doc_id = :so_id;
-- 42.857143 | 0 | false | false
```

### 8.3 SI-0001 posted

```sql
INSERT INTO sales_invoice ...; INSERT INTO sales_invoice_line ...;

-- two links, one per upstream concern — expressible because doc_link is many-to-many
INSERT INTO doc_link VALUES
  (..., 'sales_order',   :so_id, :so_line_1, 'sales_invoice', :si_id, :si_line_1, 'bill', 60, 30000.00),
  (..., 'delivery_note', :dn_id, :dn_line_1, 'sales_invoice', :si_id, :si_line_1, 'bill', 60, 30000.00);

INSERT INTO gl_entry VALUES
  (:si_id, :debtors,    35400, 0),
  (:si_id, :revenue,        0, 30000),
  (:si_id, :output_gst,     0, 5400);

INSERT INTO ar_ap_entry (voucher_id, party_type, party_id, account_id, amount_base, ...)
     VALUES (:si_id, 'customer', :acme, :debtors, 35400.00);
INSERT INTO payment_schedule (voucher_id, due_date, amount) VALUES (:si_id, ..., 35400.00);
```

`outstanding_amount` is **not written**. It is:

```sql
SELECT outstanding_amount FROM voucher_outstanding WHERE voucher_id = :si_id;   -- 35400.00
```

### 8.4 The dispute — closing one line

This is the case ERPNext cannot express:

```sql
UPDATE sales_order_line
   SET is_closed = true, closed_at = now(), closed_by = :user, close_reason = 'Customer dispute — 10 units'
 WHERE id = :so_line_2;
```

`fulfilment_doc` then reports `billing_complete = true` because
`bool_and(is_closed OR billed_amount >= ordered_amount)` (doc 10 §5.2) — the order is done,
the 2 500 is explicitly written off, and **who did it and why is on the row**.

### 8.5 The return

```sql
INSERT INTO delivery_note ... (is_return via link_kind, not a flag);
INSERT INTO doc_link VALUES
  (..., 'delivery_note', :dn2_id, :dn2_line_1, 'delivery_note', :ret_id, :ret_line_1, 'return', 10, 5000.00);
INSERT INTO stock_move VALUES (:widget_a, :main, :ret_id, :ret_line_1, now(), +10);
```

`fulfilment_line.open_qty` is `ordered − delivered + returned` (doc 10 §5.2), so **one formula**
handles it — there is no parallel `returned_qty` counter that can disagree with `delivered_qty`
(§6).

### 8.6 Point in time

```sql
-- What was the order book at 30 June?
SELECT source_line_id, SUM(qty_stock) FILTER (WHERE link_kind='deliver')
FROM doc_link WHERE created_at < '2026-07-01' GROUP BY 1;
```

ERPNext cannot answer this from its own data — the counters are current-value only.

---

## 9. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Where is "how much is delivered"? | `Sales Order Item.delivered_qty`, recomputed by raw SQL on every DN submit/cancel | `SUM` over `doc_link` in a view |
| Can two concurrent deliveries lose an update? | **Yes** (doc 10 §7) | No — nothing is updated |
| One delivery line → two order lines? | No, must split the line | Two `doc_link` rows |
| Two order lines → one invoice line? | No | Two `doc_link` rows |
| Delivery progress unit | qty | `qty_stock`, always stock UOM |
| Billing progress unit | **amount** | both available; `billing_complete` is explicit |
| Zero-value line completes? | special-case code (`:694`) | `Σ ordered = 0 → 100` in the view |
| Close one line? | **No** | `line.is_closed` + reason + who |
| Close whole order? | write `'Closed'` into `status`, no provenance | `closed_at`/`closed_by`/`close_reason` |
| Return reduces open qty? | No — parallel `returned_qty` counter | Yes, same aggregate |
| Order book as of a past date? | **No** | `WHERE created_at < t` |
| Rows updated on submitted documents per stage | ~6 | **0** |
| COGS without revenue between DN and SI | yes, unaccrued | same postings, but the gap is queryable as `delivered − billed` from one view |
| Amend an order | new document, child rows regenerated, links dangle | `document_revision`; `line_id` stable |

---

## 10. Invariants this scenario exercises

From the register in `docs/design/FINAL-SCHEMA.md`:

- **F1** every voucher's `gl_entry` rows sum to zero in base currency — checked at DN, SI, credit note.
- **F2** `stock_move` → `stock_valuation_state` consistency; COGS on the DN equals consumed value.
- **L1/L2** no ledger row may reference a voucher that is not `posted`/`reversed`.
- **L3** posted rows immutable except a whitelist — which in this design is **empty for
  `sales_order`**, because nothing needs to write back to it.
- **D7** over-fulfilment enforced by a deferred trigger against `fulfilment_allowance`, holding a
  row lock — so §3.3's read-check-write race cannot commit.
- **S6** `Σ payment_schedule = grand_total`, which makes S02's allocation cap compose upward.

---

Next: **[S02 — Payments and Allocation](S02-payments-and-allocation.md)** — how the 35 400 gets
paid, part-paid, over-paid, allocated across invoices, taken as an advance, and un-allocated.

Cross-references: doc 01 (GL posting), doc 02 (stock ledger/valuation), doc 03 (stock↔GL bridge),
doc 05 (taxes/totals), doc 06 (status/returns), doc 09 (lifecycle), doc 10 (fulfilment engine),
doc 16 (reservation), `docs/design/FINAL-SCHEMA.md`.
