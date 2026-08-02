# S04 — Stock Transfer Between Warehouses, Including In-Transit

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev). Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.
>
> Continues **[S01](S01-order-to-cash.md)**–**[S03](S03-procure-to-pay.md)**. This is the flow with
> **no party, no revenue, and no receivable** — pure inventory movement — which makes it the
> cleanest place to see how valuation actually propagates.

---

## 1. Why this flow is harder than it looks

A transfer moves value, not just quantity. Four things have to be right simultaneously:

1. **The outgoing rate** must be the source warehouse's current valuation — which depends on the
   valuation method and on every prior movement of that item.
2. **The incoming rate** must equal the outgoing rate *plus* any cost added in transit (freight,
   handling), otherwise the transfer invents or destroys inventory value.
3. **The GL must balance** — and if source and target warehouses map to different stock accounts,
   the transfer posts a real journal, not a no-op.
4. **The two legs of an in-transit transfer** must not double-count, and the goods must be
   *somewhere* on the balance sheet while they are on a truck.

ERPNext gets 1–3 substantially right and 4 partially right, at the cost of a lot of machinery.

---

## 2. `Stock Entry` — one document, nine purposes

`stock/doctype/stock_entry/stock_entry.py:73` (`class StockEntry(StockController, SubcontractingInwardController)`).

`_configure_purpose_class` (`stock/doctype/stock_entry/stock_entry.py:196`) dispatches to a
purpose-specific class:

```python
purpose_map = {
    "Manufacture":                          ManufactureStockEntry,
    "Repack":                               RepackStockEntry,
    "Material Transfer":                    MaterialTransferStockEntry,
    "Material Transfer for Manufacture":    MaterialTransferForManufactureStockEntry,
    "Material Consumption for Manufacture": MaterialConsumptionForManufactureStockEntry,
    "Disassemble":                          DisassembleStockEntry,
    "Send to Subcontractor":                SendToSubcontractorStockEntry,
    "Material Issue":                       MaterialIssueStockEntry,
    "Material Receipt":                     MaterialReceiptStockEntry,
}
self.purpose_cls = purpose_map.get(self.purpose)
if self.purpose == "Material Transfer" and self.transfer_for_material_request():
    self.purpose_cls = MaterialRequestStockEntry            # ← a tenth behaviour
```

This is a **good** refactor (v17): the strategy classes live in
`stock/doctype/stock_entry/services/` and the base controller delegates via
`if self.purpose_cls and hasattr(self.purpose_cls, "on_submit")`
(`stock/doctype/stock_entry/stock_entry.py:332`).

But note what the shape implies: **one table, `tabStock Entry`, with one child table
`tabStock Entry Detail`, carries nine structurally different documents.** A `Manufacture` entry, a
warehouse transfer, and a subcontracting dispatch share every column. Fields meaningful for one
purpose are nullable noise for the others — `bom_no`, `work_order`, `fg_completed_qty`,
`process_loss_qty`, `subcontracting_order`, `add_to_transit`, `outgoing_stock_entry`,
`per_transferred`, `sample_size`, `scrap_items`.

The `s_warehouse` / `t_warehouse` pair on the **child row** is what makes this work:

| Purpose | `s_warehouse` | `t_warehouse` | SLEs per row |
|---|---|---|---|
| Material Receipt | — | set | 1 (in) |
| Material Issue | set | — | 1 (out) |
| **Material Transfer** | **set** | **set** | **2 (out + in)** |
| Manufacture | set (RM) / — (FG) | — (RM) / set (FG) | 1 per row |

---

## 3. The worked example

Company **AlphaCo**. Item **WIDGET-A**, moving average.

| Warehouse | Stock account | On hand | Valuation |
|---|---|---:|---:|
| Main (Mumbai) | `Stock In Hand - Main` | 440 | 300.00 |
| Depot (Delhi) | `Stock In Hand - Depot` | 60 | 310.00 |
| Transit | `Stock In Transit` | 0 | — |

Transfer **100 units Main → Depot**, freight **2 500** paid to a carrier, goods in transit 3 days.

---

## 4. Path A — direct transfer (no transit)

One Stock Entry, `purpose = 'Material Transfer'`, one row with both warehouses set.

### 4.1 Validation

`MaterialTransferStockEntry.validate`
(`stock/doctype/stock_entry/services/material_transfer.py:154`):

```python
self.validate_warehouse()                        # :18  both s_ and t_ required
self.validate_same_source_target_warehouse()     # :25
```

`validate_warehouse` (`:18`) throws unless **both** `s_warehouse` and `t_warehouse` are set on
every row — this is what distinguishes Transfer from Issue/Receipt at the row level.

`validate_same_source_target_warehouse` (`:25`) is more interesting:

```python
if not frappe.get_single_value("Stock Settings", "validate_material_transfer_warehouses"):
    return                                        # ← the check is OPTIONAL
inventory_dimensions = get_inventory_dimensions()
for item in self.doc.items:
    if cstr(item.s_warehouse) == cstr(item.t_warehouse):
        if not inventory_dimensions:
            frappe.throw("Row #{0}: Source and Target Warehouse cannot be the same ...")
        else:
            difference_found = False
            for dimension in inventory_dimensions:
                fieldname = (dimension.source_fieldname
                             if dimension.source_fieldname.startswith("to_")
                             else f"to_{dimension.source_fieldname}")
                if (item.get(dimension.source_fieldname) and item.get(fieldname)
                        and item.get(dimension.source_fieldname) != item.get(fieldname)):
                    difference_found = True; break
            if not difference_found:
                frappe.throw("Row #{0}: Source, Target Warehouse and Inventory Dimensions cannot be the exact same ...")
```

Three findings:

1. **The check is behind a global setting** (`Stock Settings.validate_material_transfer_warehouses`).
   With it off, a transfer from Main to Main is permitted — producing an SLE pair that nets to zero
   but still writes two rows and still triggers valuation recalculation.
2. **Inventory Dimensions make same-warehouse transfers legitimate** — moving between two *bins*
   or two *lots* within one warehouse. The dimension is identified by a **`to_` string prefix
   convention** on the fieldname (`:47`–`:52`). A dimension whose `source_fieldname` does not
   follow that convention silently never matches, and the transfer is rejected as a duplicate.
3. The condition requires **both** sides to be non-empty (`item.get(source) and item.get(to_)`), so
   moving *from* a bin *to* unspecified does not count as a difference.

Other validations in the shared path: `validate_item` (`stock/doctype/stock_entry/stock_entry.py:463`),
`set_transfer_qty` (`:446`), `validate_batch` (`:1519`),
`validate_difference_account` (`:516`), `set_default_cost_center` (`:264`).

### 4.2 Valuation — outgoing side

`set_basic_rate` (`stock/doctype/stock_entry/stock_entry.py:556`) →
`set_rate_for_outgoing_items` (`:682`):

```python
outgoing_items_cost = 0.0
for d in self.get("items"):
    if d.s_warehouse:
        if reset_outgoing_rate:
            args = self.get_args_for_incoming_rate(d)      # :698
            rate = get_incoming_rate(args, raise_error_if_no_rate)
            if rate >= 0: d.basic_rate = rate
        d.basic_amount = flt(flt(d.transfer_qty) * flt(d.basic_rate), d.precision("basic_amount"))
        if not d.t_warehouse:
            outgoing_items_cost += flt(d.basic_amount)     # ← only counted if NOT a transfer
```

`get_incoming_rate` resolves the source warehouse's valuation as at
(`posting_date`, `posting_time`) — so a **backdated** transfer picks up the rate as it was then,
not as it is now.

Note the last two lines: `outgoing_items_cost` accumulates **only rows without a target
warehouse**. For a pure transfer every row has both, so `outgoing_items_cost = 0` — that variable
exists for Repack/Manufacture, where consumed value funds the finished good
(`get_basic_rate_for_repacked_items`, `:717`; `get_basic_rate_for_manufactured_item`, `:735`).

Our row: `basic_rate = 300.00`, `basic_amount = 30 000.00`.

### 4.3 Valuation — freight capitalised into the receiving warehouse

`distribute_additional_costs` (`stock/doctype/stock_entry/stock_entry.py:811`):

```python
if not any(d.item_code for d in self.items if d.t_warehouse):
    self.additional_costs = []                       # no inbound rows → no additional costs
self.total_additional_costs = sum(flt(t.base_amount) for t in self.get("additional_costs"))
if self.purpose in ("Repack", "Manufacture"):
    incoming_items_cost = sum(flt(t.basic_amount) for t in self.get("items") if t.is_finished_item)
else:
    incoming_items_cost = sum(flt(t.basic_amount) for t in self.get("items") if t.t_warehouse)
if not incoming_items_cost: return
for d in self.get("items"):
    ...
    d.additional_cost = (flt(d.basic_amount) / incoming_items_cost) * self.total_additional_costs
```

Apportioned **by value**, not by weight or volume — a heavy cheap item and a light expensive item
on one transfer get freight in proportion to their *value*. There is no alternative basis.

Then `update_valuation_rate` (`stock/doctype/stock_entry/stock_entry.py:835`):

```python
d.amount = flt(flt(d.basic_amount) + flt(d.additional_cost) + flt(d.landed_cost_voucher_amount),
               d.precision("amount"))
# Do not round off valuation rate to avoid precision loss
d.valuation_rate = flt(d.basic_rate) + (
    flt(flt(d.additional_cost) + flt(d.landed_cost_voucher_amount)) / flt(d.transfer_qty))
```

Our row: `additional_cost = 2 500`, `amount = 32 500`,
`valuation_rate = 300 + 2500/100 = 325.00`. The comment at `:843` is correct and deliberate —
the rate is left unrounded because rounding it would leak value.

`set_total_incoming_outgoing_value` (`:850`):

```python
total_incoming_value = Σ amount where t_warehouse    = 32 500
total_outgoing_value = Σ amount where s_warehouse    = 32 500   # same row, counted both ways
value_difference     = 0
```

⚠️ For a transfer row, `amount` is added to **both** totals because the row has both warehouses.
So `value_difference` is 0 even though 2 500 of new value entered inventory. The freight shows up
in the GL through the additional-cost entries (§4.5), not through `value_difference`.

### 4.4 Stock Ledger — two entries, ordered and linked

`update_stock_ledger` (`stock/doctype/stock_entry/stock_entry.py:977`) builds source entries first,
then target.

`get_sle_for_source_warehouse` (`:1018`):

```python
sle = self.get_sl_entries(d, {"warehouse": cstr(d.s_warehouse),
                              "actual_qty": -flt(d.transfer_qty),
                              "incoming_rate": 0})
if cstr(d.t_warehouse):
    sle.dependant_sle_voucher_detail_no = d.name          # ← :1035
```

`get_sle_for_target_warehouse` (`:1079`):

```python
sle = self.get_sl_entries(d, {"warehouse": cstr(d.t_warehouse),
                              "actual_qty": flt(d.transfer_qty),
                              "incoming_rate": flt(d.valuation_rate)})
if cstr(d.s_warehouse) or (finished_item_row and d.name == finished_item_row.name):
    sle.recalculate_rate = 1                              # ← :1092
```

Two flags carry the whole design:

- **`dependant_sle_voucher_detail_no`** tells the repost engine that the *inbound* SLE depends on
  the *outbound* one. When a backdated movement changes the source warehouse's valuation, the
  repost must recompute the outbound rate **and then** propagate the new rate to the inbound SLE and
  everything after it in the target warehouse. This is how valuation crosses warehouses
  (doc 02, doc 15 §8).
- **`recalculate_rate = 1`** tells `process_sle` (`stock/stock_ledger.py:1008`) not to trust the
  stored `incoming_rate` but to re-derive it. So the inbound rate is *recomputed* during reposting
  rather than being frozen at submit.

Resulting SLEs:

| # | Warehouse | `actual_qty` | `incoming_rate` | `qty_after_transaction` | `valuation_rate` | `stock_value_difference` |
|---|---|---:|---:|---:|---:|---:|
| 1 | Main | −100 | 0 | 340 | 300.00 | **−30 000.00** |
| 2 | Depot | +100 | 325.00 | 160 | (60×310 + 100×325)/160 = **319.375** | **+32 500.00** |

Depot's moving average moves from 310.00 to 319.375. The 2 500 of freight is now **inventory**, and
will be released to COGS when those units are sold.

### 4.5 GL entries

`get_gl_entries` (`stock/doctype/stock_entry/stock_entry.py:1122`) →
`StockEntryGLComposer` (`stock/doctype/stock_entry/services/gl_composer.py:13`), whose class
docstring states the design:

> Extends the base stock GL loop with additional-cost entries (from the `additional_costs` child
> table) and landed-cost voucher adjustments. The difference is posted to warehouse/balance-sheet
> accounts, so P&L enforcement on the expense account is off.

```python
enforce_pl_expense_account = False
book_expenses_added_to_stock = True
```

`compose` (`stock/doctype/stock_entry/services/gl_composer.py:25`):

```python
gl_entries = super().compose(inventory_account_map)          # base: SVD per warehouse
total_basic_amount = sum(flt(t.basic_amount) for t in doc.get("items") if t.t_warehouse)
divide_based_on = total_basic_amount
if doc.get("additional_costs") and not total_basic_amount:
    divide_based_on = sum(item.qty for item in doc.get("items"))    # ← falls back to QTY
item_account_wise_additional_cost = self._build_additional_cost_per_item_account(
    total_basic_amount, divide_based_on)                     # :189
if item_account_wise_additional_cost:
    self._append_additional_cost_gl_entries(gl_entries, item_account_wise_additional_cost)  # :219
self._append_lcv_gl_entries(gl_entries, inventory_account_map)     # :275
if doc.purpose in ("Repack", "Manufacture"):
    self._append_manufacturing_variance_gl_entries(gl_entries, inventory_account_map)       # :53
elif doc.purpose == "Material Receipt":
    self._append_receipt_variance_gl_entries(gl_entries)                                    # :77
return process_gl_map(gl_entries, from_repost=frappe.flags.through_repost_item_valuation)
```

Note the fallback at `:33`–`:35`: if there is no basic amount (all-zero-value items) but there
*are* additional costs, apportionment switches from **value** to **quantity**. Two different
apportionment bases depending on whether the goods happen to have a valuation.

Our GL:

| Account | Debit | Credit |
|---|---:|---:|
| `Stock In Hand - Depot` | 32 500.00 | |
| `Stock In Hand - Main` | | 30 000.00 |
| Freight (the additional-cost source account) | | 2 500.00 |

Balanced, and the freight expense account is **credited** — the cost is capitalised out of expense
into inventory. That is why `enforce_pl_expense_account = False`: the offsetting account here is a
balance-sheet account, not a P&L one.

**If both warehouses map to the same stock account**, the first two lines merge in
`merge_similar_entries` (`accounts/general_ledger.py:226`) and the entry reduces to
`Dr Stock In Hand 2 500 / Cr Freight 2 500` — only the freight moves. A same-account transfer with
no additional cost produces **no GL entries at all**, which is correct.

### 4.6 What is on disk after Path A

| Table | Rows |
|---|---|
| `tabStock Entry` | 1 — `purpose='Material Transfer'`, `docstatus=1`, `total_incoming_value=32500`, `total_outgoing_value=32500`, `value_difference=0` |
| `tabStock Entry Detail` | 1 — `s_warehouse=Main`, `t_warehouse=Depot`, `basic_rate=300`, `additional_cost=2500`, `valuation_rate=325` |
| `tabLanded Cost Taxes and Charges` (`additional_costs`) | 1 — Freight 2 500 |
| `tabStock Ledger Entry` | **2** |
| `tabBin` | 2 — Main 440→340, Depot 60→160 |
| `tabGL Entry` | 3 |

**No party, no `Payment Ledger Entry`, no receivable.** Clean.

---

## 5. Path B — in-transit transfer (two legs)

Now the realistic version: goods leave Mumbai on Monday, arrive in Delhi on Thursday. During those
three days they are neither in Main nor in Depot, but they **are** an asset of the company.

### 5.1 Leg 1 — out of Main, into Transit

Stock Entry **STE-OUT**: `purpose = 'Material Transfer'`, **`add_to_transit = 1`**,
row `s_warehouse = Main`, `t_warehouse = Transit`.

`before_validate` (`stock/doctype/stock_entry/stock_entry.py:243`) reads
`add_to_transit` (declared at `:87`). The transit warehouse is an ordinary `Warehouse` record —
typically `Warehouse.warehouse_type = 'Transit'` — with its own stock account.

Everything in §4 applies: 2 SLEs (Main −100, Transit +100), and GL:

| Account | Debit | Credit |
|---|---:|---:|
| `Stock In Transit` | 32 500.00 | |
| `Stock In Hand - Main` | | 30 000.00 |
| Freight | | 2 500.00 |

**The goods are now on the balance sheet in a Transit account.** This is the part ERPNext gets
right, and it is the reason the two-leg design exists at all.

`per_transferred = 0` on STE-OUT.

### 5.2 Leg 2 — out of Transit, into Depot

Created from STE-OUT by `make_stock_in_entry`
(`stock/doctype/stock_entry/stock_entry.py:1570`):

```python
def update_item(source_doc, target_doc, source_parent):
    target_doc.t_warehouse = ""
    if source_doc.material_request_item and source_doc.material_request:
        add_to_transit = frappe.db.get_value("Stock Entry", source_name, "add_to_transit")
        if add_to_transit:
            warehouse = frappe.get_value("Material Request Item",
                                         source_doc.material_request_item, "warehouse")
            target_doc.t_warehouse = warehouse          # ← final destination from the MR
    target_doc.s_warehouse = source_doc.t_warehouse     # Transit becomes the source
    target_doc.qty = source_doc.qty - source_doc.transferred_qty

doclist = get_mapped_doc("Stock Entry", source_name, {
    "Stock Entry":        {"doctype": "Stock Entry",
                           "field_map": {"name": "outgoing_stock_entry"},
                           "validation": {"docstatus": ["=", 1]}},
    "Stock Entry Detail": {"doctype": "Stock Entry Detail",
                           "field_map": {"name": "ste_detail", "parent": "against_stock_entry",
                                         "serial_no": "serial_no", "batch_no": "batch_no"},
                           "postprocess": update_item,
                           "condition": lambda doc: flt(doc.qty) - flt(doc.transferred_qty) > 0.00001}},
    target_doc, set_missing_values)
```

Three links are established:

| Column | On | Points at |
|---|---|---|
| `outgoing_stock_entry` | Stock Entry (header) | STE-OUT |
| `against_stock_entry` | Stock Entry Detail | STE-OUT |
| `ste_detail` | Stock Entry Detail | the STE-OUT **row** |

Note `t_warehouse` is left **blank** unless the transfer originated from a Material Request
(`:1581`–`:1587`). For a transit transfer *not* driven by an MR, **the user must type the final
destination on the inbound leg** — nothing on STE-OUT records where the goods were ultimately
going. The intent is not stored.

There is also a second, server-side builder: `set_items_for_stock_in`
(`stock/doctype/stock_entry/stock_entry.py:1381`):

```python
if self.outgoing_stock_entry and self.purpose == "Material Transfer":
    doc = frappe.get_doc("Stock Entry", self.outgoing_stock_entry)
    if doc.per_transferred == 100:
        frappe.throw(_("Goods are already received against the outward entry {0}").format(doc.name))
    for d in doc.items:
        self.append("items", {"s_warehouse": d.t_warehouse, "item_code": d.item_code,
                              "qty": d.qty, "uom": d.uom, "against_stock_entry": d.parent,
                              "ste_detail": d.name, "stock_uom": d.stock_uom,
                              "conversion_factor": d.conversion_factor})
```

⚠️ **Two builders, two behaviours.** `make_stock_in_entry` subtracts `transferred_qty` so partial
receipts work; `set_items_for_stock_in` copies `d.qty` in full and only guards on
`per_transferred == 100`. A partial in-transit receipt built through the second path over-receives.
Also note the second path does not set `t_warehouse` at all.

### 5.3 Serial/batch identity across the two legs

`make_serial_and_batch_bundle_for_transfer`
(`stock/doctype/stock_entry/stock_entry.py:1057`):

```python
ids = frappe._dict(frappe.get_all("Stock Entry Detail",
        fields=["name", "serial_and_batch_bundle"],
        filters={"parent": self.outgoing_stock_entry, "serial_and_batch_bundle": ("is", "set")},
        as_list=1))
if not ids: return
for d in self.get("items"):
    serial_and_batch_bundle = ids.get(d.ste_detail)
    if not serial_and_batch_bundle: continue
    d.serial_and_batch_bundle = self.make_package_for_transfer(
        serial_and_batch_bundle, d.s_warehouse, "Outward", do_not_submit=True)
```

A **new** `Serial and Batch Bundle` is created for the inbound leg, copied from the outbound one.
So one physical serial number produces four bundle records across a transit transfer
(out-of-Main, into-Transit, out-of-Transit, into-Depot), each a separate document with its own id.
Tracing a serial's history means walking four bundles per hop.

### 5.4 `transferred_qty` / `per_transferred` — a CASE-expression bulk UPDATE

`MaterialTransferStockEntry.on_submit`
(`stock/doctype/stock_entry/services/material_transfer.py:158`) → `update_transferred_qty` (`:68`):

```python
if not self.doc.outgoing_stock_entry: return
stock_entries, child_list = self._collect_transferred_qtys()      # :104
if not stock_entries: return
self._bulk_update_transferred_qty(stock_entries, child_list)      # :116
self._update_per_transferred_field()                              # :133
```

`_get_item_transferred_qty` (`:79`):

```sql
SELECT SUM(transfer_qty) FROM `tabStock Entry Detail`
WHERE against_stock_entry = ? AND ste_detail = ? AND docstatus = 1
```

`_bulk_update_transferred_qty` (`:116`) with `_build_case_expr` (`:125`):

```python
case_expr = Case()
for (parent, name), qty in stock_entries.items():
    case_expr = case_expr.when((sed.parent == parent) & (sed.name == name), qty)
frappe.qb.update(sed).set(sed.transferred_qty, case_expr.else_(sed.transferred_qty)) \
        .where(sed.name.isin(child_list)).run()
```

A single `UPDATE ... SET transferred_qty = CASE WHEN ... END` across all affected rows. Efficient —
and, like every counter in doc 10, **unlocked**: `SELECT SUM(...)` then `UPDATE` with no version
predicate. Two concurrent inbound legs against the same outbound entry both read the same sum.

`_update_per_transferred_field` (`:133`) then reuses `StatusUpdater._update_percent_field_in_targets`
(`controllers/status_updater.py:641`) with a hand-built config (`:136`):

```python
{"source_dt": "Stock Entry Detail", "target_dt": "Stock Entry Detail",
 "join_field": "ste_detail", "target_field": "transferred_qty",
 "target_ref_field": "transfer_qty",
 "target_parent_dt": "Stock Entry", "target_parent_field": "per_transferred",
 "source_field": "transfer_qty", "percent_join_field": "against_stock_entry"}
```

**`source_dt` and `target_dt` are the same table** — a self-referential fulfilment edge, Stock
Entry Detail against Stock Entry Detail. The generic engine handles it, which is a point in the
engine's favour, and it confirms doc 10's reading that the config *is* the model.

`_validate_item_transferred_qty` (`:92`) is the over-receipt guard:

```python
transfer_qty = frappe.get_value("Stock Entry Detail", item.ste_detail, "transfer_qty")
if transferred_qty > transfer_qty:
    frappe.throw(_("Row {0}: Transferred quantity cannot be greater than the requested quantity."))
```

No allowance percentage here — unlike delivery/receipt (doc 10 §1.3), in-transit receipt is
strictly capped at the dispatched quantity. Sensible, and inconsistent with the rest of the system.

### 5.5 Leg 2 postings

SLEs: Transit −100 @ 325.00, Depot +100 @ 325.00.

GL:

| Account | Debit | Credit |
|---|---:|---:|
| `Stock In Hand - Depot` | 32 500.00 | |
| `Stock In Transit` | | 32 500.00 |

The Transit account nets to zero once the second leg posts. **An unreconciled `Stock In Transit`
balance is exactly the goods currently on trucks** — a genuinely useful control account, and one of
the better pieces of design in the stock module.

### 5.6 Full trace, Path B

| Stage | SLE | GL | Counters |
|---|---:|---:|---|
| STE-OUT submit | 2 | 3 | `Bin` Main, `Bin` Transit |
| STE-IN submit | 2 | 2 | `Bin` Transit, `Bin` Depot, **`STE-OUT` row `transferred_qty`**, **`STE-OUT.per_transferred`** |

4 SLEs and 5 GL rows to move one pallet between two warehouses — which is the right answer, because
the goods really did occupy three locations.

---

## 6. Inter-company transfer is a different flow entirely

Moving stock between **two companies** in a group is **not** a Stock Entry. It is a
Delivery Note in the seller and a Purchase Receipt in the buyer, mirrored by
`make_inter_company_purchase_receipt`
(`stock/doctype/delivery_note/mapper.py:409`) /
`make_inter_company_delivery_note`
(`stock/doctype/purchase_receipt/mapper.py:249`) — covered in doc 15 §3, with the
`is_internal_customer` / `represents_company` machinery and the constraint that **both companies
must share the same currency** (doc 15 §3, `accounts/doctype/sales_invoice/mapper.py:149`).

`AccountsController.is_internal_transfer`
(`controllers/accounts_controller.py:1288`) and `init_internal_values` (`:318`) mark such
documents, and the stock side routes through
`stock/services/internal_transfer.py` / `accounts/services/internal_transfer.py` so that no
profit is recognised on an internal sale.

So there are **two unrelated mechanisms** for "move goods from A to B" depending on whether A and B
are in the same company — with different tables, different links, different valuation handling, and
different validation.

---

## 7. Same scenario in our design

### 7.1 One movement primitive

Per decision **D6**, `stock_move` is an immutable event and `stock_valuation_state` is a
recomputable projection. A transfer is **two `stock_move` rows in one transaction**, linked:

```sql
BEGIN;
INSERT INTO voucher (id, company_id, doc_type, doc_no, lifecycle_state, posting_date)
     VALUES (:ste, :co, 'stock_transfer', 'ST-0001', 'posted', '2026-08-03');

INSERT INTO stock_transfer_line (id, voucher_id, line_no, item_id,
                                 from_warehouse_id, to_warehouse_id, qty_stock)
     VALUES (:line, :ste, 1, :widget_a, :main, :depot, 100);

-- freight, explicit, with its own account and basis
INSERT INTO stock_landed_cost (voucher_id, account_id, amount_base, apportion_basis, reason_code)
     VALUES (:ste, :freight, 2500.00, 'value', 'inbound_freight');

-- the two events
INSERT INTO stock_move (id, company_id, item_id, warehouse_id, voucher_id, voucher_line_id,
                        posting_at, qty_stock, move_kind, paired_move_id)
     VALUES (:out, :co, :widget_a, :main,  :ste, :line, :ts, -100, 'transfer_out', :in),
            (:in,  :co, :widget_a, :depot, :ste, :line, :ts, +100, 'transfer_in',  :out);
COMMIT;
```

`paired_move_id uuid REFERENCES stock_move(id)` with a `CHECK` that the pair has equal absolute
quantity and opposite sign, plus a `UNIQUE` on it — so a transfer **cannot** be half-recorded. That
replaces `dependant_sle_voucher_detail_no` as a *declared* relationship rather than a repost hint.

### 7.2 Valuation is a projection, computed in the transaction

The trigger on `stock_move`:

1. locks `stock_valuation_state` for `(item_id, :main)`, consumes 100 at the current rate,
   yielding `cost_out_base = 30 000`;
2. computes `cost_in_base = cost_out_base + apportioned landed cost = 32 500`;
3. locks `(item_id, :depot)` and adds 100 @ 325.00.

Because both locks are taken in a **canonical order** (by `warehouse_id`), two concurrent transfers
in opposite directions between the same pair cannot deadlock — the ordering is a property of the
trigger, not of each call site (contrast `pick_list.py:558`, doc 16 §5.4).

**Backdating** recomputes the projection forward from that point for the affected
`(item, warehouse)` pairs, in the same transaction — including across the pair, because
`paired_move_id` makes the dependency explicit. No `recalculate_rate` flag, no
`Repost Item Valuation` queue, no off-hours window (doc 15 §10).

### 7.3 In-transit is a warehouse kind, not a flag

`warehouse.kind = 'transit'` already exists in our model (doc 16 §5.4). A transit transfer is
**one voucher with two legs**, not two vouchers:

```sql
INSERT INTO stock_transfer_line (id, voucher_id, line_no, item_id,
                                 from_warehouse_id, via_warehouse_id, to_warehouse_id, qty_stock)
     VALUES (:line, :ste, 1, :widget_a, :main, :transit, :depot, 100);
```

- **Leg 1** posts `main → transit` on dispatch.
- **Leg 2** posts `transit → depot` on arrival, recorded as `stock_receipt_event` rows against the
  same `stock_transfer_line`.
- **The final destination is stored on the line from the start** — fixing §5.2, where the inbound
  leg has to be told where the goods are going unless a Material Request happens to exist.
- **Progress is a view** over the leg-2 events (`Σ received / qty_stock`), not a
  `transferred_qty` column maintained by an unlocked CASE-expression UPDATE (§5.4).
- Over-receipt is a deferred constraint trigger against the line quantity, holding the row lock.

`CHECK (via_warehouse_id IS NULL OR (SELECT kind FROM warehouse WHERE id = via_warehouse_id) = 'transit')`
— enforced by trigger, since a subquery in `CHECK` is not allowed.

### 7.4 One mechanism for intra- and inter-company

An inter-company transfer is the **same** `stock_transfer` voucher with
`to_company_id <> from_company_id`, paired through `intercompany_pair` (doc 15 §5):

- two `stock_move` rows, one in each company, each RLS-scoped to its own company;
- two GL vouchers, one per company, each balanced (F1), linked by `intercompany_pair_id`;
- transfer price from `transfer_pricing_policy`, not "whatever the seller charged";
- **no currency restriction** — the pair records both currencies and the rate.

No `is_internal_customer`, no `represents_company` string matching, no mirrored Delivery
Note/Purchase Receipt pair, and no requirement that group companies share a currency (§6).

### 7.5 Same-warehouse movement is expressible

Moving between bins or lots inside one warehouse is `from_location_id` / `to_location_id` on the
line, where `location` is a real child of `warehouse`. The
"is it the same warehouse?" check becomes
`CHECK (from_warehouse_id <> to_warehouse_id OR from_location_id <> to_location_id)` — a
constraint, not a global setting plus a `to_`-prefix string convention (§4.1).

### 7.6 Freight apportionment is explicit

```sql
apportion_basis  landed_cost_basis NOT NULL   -- 'value','qty','weight','volume','manual'
```

with a per-line override table for `manual`. ERPNext's silent value→quantity fallback when
`total_basic_amount = 0` (§4.5) becomes an explicit basis choice that is recorded on the row.

---

## 8. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Documents for one transfer | 1 (direct) or **2** (transit) | 1, with legs |
| Movement rows | 2 per leg | 2 per leg (same) |
| Transfer atomicity | two SLEs in one submit; two *documents* for transit | `paired_move_id UNIQUE` + `CHECK`; a transfer cannot be half-recorded |
| Cross-warehouse valuation dependency | `dependant_sle_voucher_detail_no` hint + `recalculate_rate` flag, resolved by an async repost | declared `paired_move_id`; projection recomputed in-transaction |
| Final destination of a transit transfer | not stored unless an MR exists | `to_warehouse_id` on the line from the start |
| Transit progress | `transferred_qty` + `per_transferred`, unlocked CASE UPDATE | view over receipt events |
| Two builders for the inbound leg | `make_stock_in_entry` **and** `set_items_for_stock_in`, with different partial-receipt behaviour | one |
| Same-warehouse transfer | blocked by a global setting; legal only via a `to_`-prefix dimension convention | `from_location_id` / `to_location_id` + `CHECK` |
| Freight basis | value; silently falls back to qty when value is 0 | explicit `apportion_basis` |
| Freight in `value_difference` | invisible (row counted on both sides) | `landed_cost` is its own table, always visible |
| Serial/batch across transit | 4 bundle documents per serial per hop | one `serial_batch` id; `stock_move` rows reference it |
| Inter-company transfer | a **different mechanism** (DN↔PR mirror), same-currency only | same voucher, `intercompany_pair`, any currency |
| One table, nine purposes | `tabStock Entry` | `stock_transfer`, `stock_receipt`, `stock_issue`, `stock_adjustment` — separate tables, shared `stock_move` |
| Transit on the balance sheet | ✅ yes, via a transit warehouse's stock account | ✅ same, and `warehouse.kind='transit'` is enforced |

---

## 9. Invariants exercised

- **F1** every voucher balances in base currency — both legs, and the same-account case that
  produces no GL at all.
- **F2** `Σ stock_move` value per warehouse account == `Σ gl_entry` on that account. This is an
  *invariant* for us rather than a reconciliation report, because
  `warehouse.stock_account_id` is `UNIQUE` (doc 16 §5.4) — ERPNext only warns
  (`warehouse.py:110`).
- **F4** (new, from this scenario) **transfer pairing**: for every `stock_move` with
  `move_kind IN ('transfer_out','transfer_in')`, `paired_move_id` is non-null, unique, mutual, and
  the pair has equal `abs(qty_stock)` and opposite sign. Value may differ by exactly the
  apportioned landed cost, and `Σ landed_cost = Σ (in_value) − Σ (out_value)` per voucher.
- **H1** `stock_move` append-only, so a landed-cost adjustment after arrival cannot rewrite the
  transfer.
- **D6** valuation state is a projection, never stored inside the event row.

---

Cross-references: **[S01](S01-order-to-cash.md)**, **[S03](S03-procure-to-pay.md)**;
doc 02 (stock ledger and valuation), doc 03 (stock↔GL bridge, landed cost),
doc 15 §3 (inter-company) and §8 (Repost Item Valuation), doc 16 (warehouse structure),
doc 27 (the remaining stock documents in depth), `docs/design/FINAL-SCHEMA.md`.
