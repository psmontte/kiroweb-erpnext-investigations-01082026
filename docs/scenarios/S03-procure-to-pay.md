# S03 — Procure to Pay: Purchase Order → Purchase Receipt → Purchase Invoice

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev). Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.
>
> The mirror of **[S01](S01-order-to-cash.md)**. Structurally symmetric, but **four asymmetries
> are real and consequential** — this document exists mainly to name them.

---

## 1. The worked example

Supplier **BETA Supplies**, company **AlphaCo** (INR):

| Line | Item | Qty | Rate | Amount |
|---|---|---:|---:|---:|
| 1 | RAW-X | 200 KG | 120.00 | 24 000.00 |
| 2 | RAW-Y | 50 EA | 800.00 | 40 000.00 |
| | | | **Net** | **64 000.00** |
| | | | Freight (Actual, valuation) | 3 000.00 |
| | | | GST 18 % | 11 520.00 |
| | | | **Grand total** | **78 520.00** |

Flow: **PO-0001** → **PR-0001** receives 200 KG RAW-X + 40 EA RAW-Y (10 short) →
**PI-0001** bills the receipt → **Landed Cost Voucher** adds 1 200 customs after the fact →
10 EA RAW-Y rejected and returned.

---

## 2. Stage 1 — Purchase Order submit

`PurchaseOrder.on_submit`. `status_updater` config at
`buying/doctype/purchase_order/purchase_order.py:167`, pointing at
`Material Request Item.ordered_qty` and `Supplier Quotation Item`.

Writes:

| Table | Effect |
|---|---|
| `tabPurchase Order` | `docstatus=1`, `status='To Receive and Bill'`, `per_received=0`, `per_billed=0` |
| `tabPurchase Order Item` | `received_qty=0`, `billed_amt=0`, `returned_qty=0` |
| `tabBin` | `ordered_qty` += 200 / 50 (inbound commitment, not `reserved_qty`) |
| `tabMaterial Request Item` | `ordered_qty` updated if PO came from an MR |

No GL, no SLE. Same as S01 §2.

### 2.1 ⚠️ Asymmetry 1 — `per_billed` uses `== 100`, not `>= 100`

`status_map["Purchase Order"]` (`controllers/status_updater.py:69`):

```
To Bill              per_received >= 100 and per_billed <  100 and docstatus == 1
To Receive           per_received <  100 and per_billed == 100 and docstatus == 1
To Receive and Bill  per_received <  100 and per_billed <  100 and docstatus == 1
Completed            per_received >= 100 and per_billed == 100 and docstatus == 1
```

versus Sales Order (`:43`), which uses `per_billed >= 100` throughout.

**Consequence: over-billing a Purchase Order leaves it permanently not `Completed`.** Bill
64 000 worth of goods as 64 100 (a legitimate price variance within the billing allowance) and
`per_billed = 100.15`, which satisfies neither `< 100` nor `== 100` — the PO falls through every
condition and lands on whatever earlier match applies. Over-billing a **Sales** Order completes
normally.

This is not a documented design choice. It is an inconsistency between two adjacent list literals
in the same module.

---

## 3. Stage 2 — Purchase Receipt PR-0001

Links, on `Purchase Receipt Item`:

```
purchase_order_item = <PO-0001 item row>      ← the fulfilment link
purchase_order      = PO-0001
```

`status_updater` config at `stock/doctype/purchase_receipt/purchase_receipt.py:153`.

### 3.1 Receipt with rejection

Received 40 of 50 RAW-Y, of which **5 rejected**:

| `Purchase Receipt Item` column | Value |
|---|---:|
| `qty` (accepted) | 35 |
| `rejected_qty` | 5 |
| `received_qty` | 40 |
| `warehouse` | Stores |
| `rejected_warehouse` | Rejected |

### 3.2 ⚠️ Asymmetry 2 — three quantities, and the counter tracks the middle one

Sales has one quantity per line. Purchase has **`received_qty` = `qty` + `rejected_qty`**, and
they go to **different warehouses**, producing **two** Stock Ledger Entries per line.

`Purchase Order Item.received_qty` is fed from `Purchase Receipt Item.received_qty` (including
rejects), while stock valuation and the GL are driven by `qty` and `rejected_qty` separately. So
"how much did we receive against the PO" and "how much is in usable stock" are different numbers by
design, and the reconciliation between them is per-report.

### 3.3 Valuation — the incoming side

This is the genuinely harder direction. `Purchase Receipt Item` carries:

```
rate                        120.00     -- supplier's price
landed_cost_voucher_amount    0.00     -- added later (§5)
rm_supp_cost                  0.00     -- subcontracting
item_tax_amount               0.00     -- non-recoverable tax portion
valuation_rate            <derived>    -- what actually hits the ledger
```

Plus valuation-bearing rows in `tabPurchase Taxes and Charges` where
`category ∈ ('Valuation', 'Total and Valuation')` — our 3 000 freight — apportioned across lines
(by amount or qty per `Buying Settings`).

`process_sle` (`stock/stock_ledger.py:1008`) then writes, for RAW-X:

| SLE column | Value |
|---|---:|
| `actual_qty` | +200 |
| `incoming_rate` | 120.00 + freight share |
| `qty_after_transaction` | new balance |
| `stock_value_difference` | **+ (200 × effective rate)** |

Freight apportionment on 24 000 / 64 000 = 37.5 % → 1 125 to RAW-X → effective rate
120 + (1 125 / 200) = **125.625**. SVD = +25 125.00.

### 3.4 GL entries

`StockController.make_gl_entries` (`controllers/stock_controller.py:178`) again reads
`stock_value_difference` back from the SLEs:

| Account | Debit | Credit |
|---|---:|---:|
| Stock In Hand | 25 125.00 | |
| Stock In Hand (RAW-Y accepted, 35 units) | 33 000.00 | |
| Stock In Hand (RAW-Y rejected warehouse, 5 units) | 4 714.29 | |
| **Stock Received But Not Billed** | | 62 839.29 |

**`Stock Received But Not Billed` is the key account and has no sales-side counterpart.** It is a
liability accrual: goods are ours, the invoice has not arrived. When PI-0001 posts, it is cleared.
The sales side has no equivalent — a Delivery Note posts COGS with no matching unbilled-revenue
accrual (S01 §3.5). **Asymmetric accrual treatment, same framework.**

### 3.5 Counter propagation

```
PO Item 1: received_qty = 200   (ref qty 200)
PO Item 2: received_qty = 40    (ref qty 50)
Σ LEAST(received, qty) = 200 + 40 = 240 ;  Σ qty = 250
per_received = 96.000000  → 'Partly Received'
```

PO status: `per_received < 100 and per_billed < 100` → stays `'To Receive and Bill'`.

---

## 4. Stage 3 — Purchase Invoice PI-0001

Links on `Purchase Invoice Item`:

```
po_detail = <PO-0001 item row>      ← billing progress on the order
pr_detail = <PR-0001 item row>      ← billing progress on the receipt
purchase_order = PO-0001, purchase_receipt = PR-0001
```

`status_updater` config at `accounts/doctype/purchase_invoice/purchase_invoice.py:224`.

### 4.1 ⚠️ Asymmetry 3 — `status_updater` is emptied in two places

```python
self.status_updater = []      # accounts/doctype/purchase_invoice/purchase_invoice.py:615
self.status_updater = []      # accounts/doctype/purchase_invoice/purchase_invoice.py:731
```

Sales Invoice does the same at `:433` and `:523`. So under certain conditions (returns,
consolidated/POS invoices, specific update paths) **status propagation is switched off entirely** by
assigning an empty list — the document posts, and no upstream counter moves. Recovering the correct
`per_billed` afterwards requires a repost.

This is the single most common cause of "the order says To Bill but everything is invoiced".

### 4.2 GL entries

| Account | Debit | Credit |
|---|---:|---:|
| **Stock Received But Not Billed** | 62 839.29 | ← clears the accrual |
| Input GST 18 % | 11 520.00 | |
| Expenses Included In Valuation *(if variance)* | Δ | |
| Creditors (BETA) | | 74 359.29 |

The interesting part is **the variance**. If the invoice rate differs from the receipt rate, the
difference does **not** silently adjust inventory; it goes to
`Stock Adjustment` / `Expenses Included In Valuation`, or triggers a repost, depending on
`Buying Settings` and whether the item is still in stock. Doc 03 covers the drift-detection path
(`compare_existing_and_expected_gle`, `accounts/utils.py:1843`;
`get_stock_and_account_balance`, `:1906`).

### 4.3 Payment Ledger mirror

Identical to S01 §4.5 but on the payable side:

| `tabPayment Ledger Entry` | Value |
|---|---|
| `party_type` / `party` | Supplier / BETA |
| `account` | Creditors |
| `against_voucher_no` | PI-0001 |
| `amount` | **−74 359.29** (payables are negative in the same subledger) |

→ `Purchase Invoice.outstanding_amount = 74 359.29`.

**Payment against a purchase invoice is the same machinery as S02**, with
`payment_type='Pay'` and `party_type='Supplier'`. The direction branch in
`allocate_amount_to_references` (`accounts/doctype/payment_entry/payment_entry.py:1662`) treats
`("Pay", "Supplier")` and `("Receive", "Customer")` identically — so **S02 applies verbatim**,
including the silent credit-note (here: debit-note) consumption on short payment.

### 4.4 One extra gate on the payable side

`AccountsController.ensure_supplier_is_not_blocked`
(`controllers/accounts_controller.py:153`) with `get_supplier_block_status`
(`controllers/accounts_controller.py:1556`) — a supplier can be blocked from invoicing or from
payment, with a `release_date`. There is no customer-side equivalent (the customer analogue is
`check_credit_limit`, which is a different mechanism entirely).

---

## 5. Stage 4 — Landed Cost Voucher (1 200 customs, after the fact)

This is the flow with no sales-side analogue at all.

A `Landed Cost Voucher` references PR-0001, adds 1 200 of customs duty, apportions it across
lines, and then:

1. **Updates `Purchase Receipt Item.landed_cost_voucher_amount`** on the submitted receipt.
2. **Recomputes `valuation_rate`** on those receipt lines.
3. **Rewrites the Stock Ledger Entries' valuation** for that receipt.
4. **Triggers `Repost Item Valuation`** (doc 15 §8) to cascade the new valuation through every
   *subsequent* movement of those items — because `qty_after_transaction`, `valuation_rate`, and
   `stock_value` are stored **inside** each SLE row (doc 02, decision D6).
5. **Reposts the GL** for the affected vouchers.

So a 1 200 adjustment can rewrite thousands of ledger rows, asynchronously, in a configured
off-hours window (`in_configured_timeslot`,
`stock/doctype/repost_item_valuation/repost_item_valuation.py:933`), with failures emailed to
humans (`notify_error_to_stock_managers`, `:759`).

**In our design** (D6): the landed cost is a new `stock_move`-adjacent
`valuation_adjustment` row with its own effective date; `stock_valuation_state` is a **projection**
recomputed forward from that point for one `(item, warehouse)` inside the same transaction. The
event log is never touched, there is no queue, and there is no window in which valuation is
knowably wrong.

---

## 6. Stage 5 — Purchase Return (the 10 short-shipped + 5 rejected)

Same machinery as S01 §6 (`controllers/sales_and_purchase_return.py`), with two purchase-specific
functions:

```
get_returned_qty_map_for_purchase_flow    controllers/sales_and_purchase_return.py:323
get_returned_qty_map_for_row             controllers/sales_and_purchase_return.py:385
```

and `make_return_doc(..., return_against_rejected_qty=False)`
(`controllers/sales_and_purchase_return.py:430`) — the flag exists specifically to return the
**rejected** quantity out of the rejected warehouse rather than the accepted quantity out of
stores.

`Purchase Receipt` status becomes `'Return Issued'` when `per_returned == 100`
(`controllers/status_updater.py:108`).

### 6.1 ⚠️ Asymmetry 4 — `Purchase Receipt` has an extra `Completed` clause

`status_map["Purchase Receipt"]` (`controllers/status_updater.py:103`):

```
Completed   (per_billed >= 100 and docstatus == 1)
            or (docstatus == 1 and grand_total == 0 and per_returned != 100 and is_return == 0)
```

versus `status_map["Delivery Note"]` (`:93`), which is simply `per_billed == 100`.

Four documents, four different comparison conventions on the same derived number:
DN uses `== 0` / `== 100`, PR uses `>= 100` with a zero-total escape, SO uses `>= 100`,
PO uses `== 100`.

---

## 7. Complete write trace

| Stage | GL | SLE | PLE | Counters on submitted docs |
|---|---:|---:|---:|---|
| PO-0001 submit | 0 | 0 | 0 | MR Item.ordered_qty, Bin.ordered_qty |
| PR-0001 submit | 4 | 3 | 0 | PO Item.received_qty, PO.per_received, PO.status, Bin.actual_qty × 2, Bin.ordered_qty |
| PI-0001 submit | 4 | 0 | 1 | PO Item.billed_amt, PO.per_billed, PO.status, PR.per_billed, PR.status, PI.outstanding_amount |
| Landed Cost Voucher | **repost** | **rewrite** | 0 | PR Item.landed_cost_voucher_amount, PR Item.valuation_rate, + N downstream SLEs |
| Purchase Return | 3 | 2 | 0 | PO Item.returned_qty, PR.per_returned, PR.status |
| Payment (S02) | 2 | 0 | 1 | PI.outstanding_amount, PI.status |

The Landed Cost row is the one that has no bound. Everything else is comparable to S01.

---

## 8. Same scenario in our design

Identical shape to S01 §8, with three purchase-specific points:

### 8.1 Received / accepted / rejected are separate links

```sql
INSERT INTO doc_link (source_doc_type, source_doc_id, source_line_id,
                      target_doc_type, target_doc_id, target_line_id, link_kind, qty_stock, amount_base)
VALUES ('purchase_order', :po, :po_line_2, 'purchase_receipt', :pr, :pr_line_2, 'receive', 40, 32000.00);

INSERT INTO stock_move (item_id, warehouse_id, voucher_id, voucher_line_id, posting_at, qty_stock) VALUES
       (:raw_y, :stores,   :pr, :pr_line_2, now(), +35),
       (:raw_y, :rejected, :pr, :pr_line_2, now(),  +5);
```

One `receive` link of 40 (what the PO delivered against), two `stock_move` rows to two warehouses
(where the goods physically are). The two questions get two answers from two tables, instead of one
column that half-answers both (§3.2).

### 8.2 The accrual is symmetric

Both directions post the same shape:

| | Receipt (goods in, unbilled) | Delivery (goods out, unbilled) |
|---|---|---|
| ERPNext | `Stock Received But Not Billed` ✅ | *nothing* ❌ |
| Ours | `goods_received_not_invoiced` | `goods_delivered_not_invoiced` |

Both cleared by the invoice, both queryable as `received − billed` / `delivered − billed` from
`fulfilment_line` (doc 10 §5.2). No asymmetry (§3.4).

### 8.3 Landed cost does not rewrite history

```sql
INSERT INTO valuation_adjustment (id, company_id, item_id, warehouse_id,
                                  source_voucher_id, effective_at, amount_base, reason_code)
     VALUES (:adj, ..., :raw_x, :stores, :pr, :customs_date, 1125.00, 'landed_cost:customs');
-- trigger: recompute stock_valuation_state forward from :customs_date for (item, warehouse)
--          inside this transaction, holding the row lock
```

`stock_move` rows are untouched (invariant H1). No `Repost Item Valuation`, no queue, no
off-hours window, no email on failure (§5).

### 8.4 One status convention

`fulfilment_doc` (doc 10 §5.2) exposes `per_received`, `per_billed`,
`receipt_complete`, `billing_complete` computed by **one formula** for every document type, with
`Σ ordered = 0 → 100`. The four conventions of §2.1 and §6.1 collapse to one, and
`doc_status_rule` predicates read the view rather than the field they are computing (doc 10 §5.3).

---

## 9. Side-by-side (purchase-specific only — see S01 §9 for the shared items)

| Question | ERPNext | Ours |
|---|---|---|
| Over-billing completes the order? | **No** (PO uses `== 100`) | Yes — one convention |
| received vs accepted vs rejected | one counter, two SLEs, per-report reconciliation | one `receive` link + N `stock_move` rows |
| Unbilled-goods accrual | receipt side only | both sides |
| Landed cost after receipt | rewrites SLEs + async repost, unbounded | `valuation_adjustment` + forward projection recompute, in-transaction |
| Invoice-vs-receipt rate variance | to `Expenses Included In Valuation` or a repost, config-dependent | explicit `purchase_price_variance` posting, always |
| `status_updater = []` disabling propagation | two places per invoice type | no counters to propagate |
| Supplier block | `ensure_supplier_is_not_blocked` + `release_date` | `party_hold` rows with reason + `hold_until`, symmetric for customers |
| Return of rejected qty | `return_against_rejected_qty` flag | `link_kind='return'` from the rejected-warehouse `stock_move` |

---

## 10. Invariants exercised

- **F1** every voucher balances in base currency — receipt, invoice, landed cost, return.
- **F2** `Σ stock_move` value into an account == `Σ gl_entry` on that account for the same
  vouchers — the stock↔GL reconciliation (doc 03) becomes an invariant because
  `warehouse.stock_account_id` is `UNIQUE` (doc 16 §5.4).
- **F3** `goods_received_not_invoiced` nets to zero per receipt line once fully billed.
- **H1** `stock_move` append-only, so landed cost cannot rewrite it.
- **D7** over-receipt enforced by a deferred trigger against `fulfilment_allowance`.
- **S1/S2** payment allocation, identical to S02.

---

Cross-references: **[S01 — Order to Cash](S01-order-to-cash.md)**,
**[S02 — Payments and Allocation](S02-payments-and-allocation.md)**;
doc 02 (valuation), doc 03 (stock↔GL bridge, landed cost, drift detection),
doc 10 (fulfilment engine), doc 15 §8 (Repost Item Valuation),
`docs/design/FINAL-SCHEMA.md`.
