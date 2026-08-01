# 38 — Subcontracting Orders, Transfer, Consumption, Receipt and GL

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Docs 33–37 followed production from BOM and capacity through Work Order execution, stock consumption,
WIP and GL. This document traces both kinds of subcontracting across the same boundary. In the ordinary
**supplier** flow, a Purchase Order buys a non-stock service, a Subcontracting Order authorises finished
goods and company-owned raw material, Stock Entry moves that material into a supplier warehouse, and a
Subcontracting Receipt consumes it while receiving finished and secondary stock. In the newer
**customer-owned inward** flow, a Sales Order sells the service, customer material enters a
customer-tagged warehouse at zero valuation, ordinary internal Work Orders manufacture the output, and
Stock Entry delivers it back to the customer.

The central findings are:

1. a supplier or customer warehouse is still an ordinary Warehouse whose quantity, valuation, serial,
   batch, reservation and Bin state use the common stock engine;
2. legal ownership is not a stock-ledger dimension — supplier stock remains company inventory, while
   customer stock is represented indirectly by Item/Warehouse metadata and a forced zero valuation;
3. the supplier receipt is the strongest conversion posting: its SLEs consume supplier-held material
   and receive FG/secondary output, and its dedicated GL composer explicitly separates service, raw
   material, additional cost, landed cost and stock-adjustment variance;
4. most order, supplied/consumed, received/returned, produced/delivered and percentage fields are
   mutable projections written before or after stock evidence; and
5. no Subcontracting Order/Inward Order owner lock serialises the many remaining-quantity checks.

---

## 1. Four parents and two shared controllers

All four parent DocTypes are now source-covered:

| Parent | Controller | Role |
|---|---|---|
| Subcontracting BOM | `SubcontractingBOM(Document)` (`subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:10-28`) | active FG ↔ service-item conversion master |
| Subcontracting Order | `SubcontractingOrder(SubcontractingController)` (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:20-91`) | supplier-side authorisation derived from a Purchase Order |
| Subcontracting Receipt | `SubcontractingReceipt(SubcontractingController)` (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:30-95`) | supplier-side conversion, stock and accounting evidence |
| Subcontracting Inward Order | `SubcontractingInwardOrder(SubcontractingController)` (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:14-62`) | reverse-ownership customer-material authorisation derived from a Sales Order |

`SubcontractingController` itself inherits `StockController`. Its constructor switches an internal
metadata bundle by document type: ordinary subcontracting uses `Subcontracting Order`,
`subcontracting_order`, `sco_rm_detail` and the SCO/SCR supplied-item tables; inward subcontracting uses
`Subcontracting Inward Order`, `subcontracting_inward_order` and `scio_detail`
(`controllers/subcontracting_controller.py:27-47`). Shared `before_validate` removes blank child rows
and defaults item conversion factors. Shared `validate` checks stock/subcontracted items, rebuilds the
raw-material table and values receipt raw material (`controllers/subcontracting_controller.py:49-75`).

A second mixin, `SubcontractingInwardController`, is mixed into Stock Entry rather than the inward
order. It dispatches validation and submit/cancel projection updates by Stock Entry purpose:
`Receive from Customer`, `Return Raw Material to Customer`, `Material Transfer for Manufacture`,
`Manufacture`, `Subcontracting Delivery` and `Subcontracting Return`
(`controllers/subcontracting_inward_controller.py:12-55`). This means the parent authorises the flow,
but ordinary Stock Entry and Work Order controllers own its physical execution.

> **Invariant M41 — subcontracting command identity.** One subcontracting authorisation has stable,
> typed service, finished-good and material-allocation identities. Every transfer, return, consumption,
> output, service-cost source, tracked-unit allocation and GL line references those identities; shared
> controllers may implement policy but cannot erase line provenance by Item-code aggregation.

---

## 2. Subcontracting BOM — the commercial/physical conversion master

`Subcontracting BOM` is a configuration document, not posting evidence. Validation requires:

- finished good enabled, stock, marked `is_sub_contracted_item`, and with a default BOM;
- service item enabled and **non-stock**; and
- at most one application-visible active record per finished good.

The checks are in `subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:30-82`. Before save:

```text
conversion_factor = service_item_qty / finished_good_qty
```

(`subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:84-85`). Lookup APIs return active
mappings by finished good or service item (`subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:88-114`).
The factor is **service units per FG unit**. It lets a Purchase/Sales Order express the commercial line
as a non-stock service while downstream documents express the physical line as stock FG.

Two important boundaries follow:

- the active Subcontracting BOM chooses `finished_good_bom`; otherwise order builders fall back to the
  Item default BOM;
- changing this master does not revise already-copied order rows, but a new order preview reads the live
  active mapping.

The uniqueness rule is only `db.exists(...)` followed by save. There is no unique database constraint
or lock in this controller, so two concurrent active records can both pass. `finished_good_qty` is also
divided without a local zero guard.

> **Ours.** `subcontracting_recipe_revision` is immutable and effective-dated. A unique partial index
> enforces one active revision per `(company, finished_good, commercial_service)`. The stored rational
> conversion factor, BOM revision and ownership policy are snapshotted into every order allocation.

---

## 3. Supplier flow origin — Purchase Order service becomes SCO finished good

### 3.1 Purchase Order contract

A subcontracted Purchase Order row buys a service Item but carries `fg_item`, `fg_item_qty` and a BOM.
Validation requires the FG, requires it to be subcontracted, requires a BOM/default BOM and rejects zero
FG quantity (`buying/doctype/purchase_order/services/subcontracting.py:12-37`). When the user supplies an
FG but no service Item, an active Subcontracting BOM fills:

```text
PO service item = Subcontracting BOM.service_item
PO service qty  = PO fg_item_qty × Subcontracting BOM.conversion_factor
PO service UOM  = Subcontracting BOM.service_item_uom
```

(`buying/doctype/purchase_order/services/subcontracting.py:39-65`). A setting can auto-create an SCO on
PO submission (`buying/doctype/purchase_order/services/subcontracting.py:80-86`).

### 3.2 PO → SCO mapping and remaining quantity

The mapper rejects a fully subcontracted PO, copies each pending PO Item into an SCO service row, calls
`populate_items_table()`, and can save/submit under a savepoint
(`buying/doctype/purchase_order/mapper.py:221-332`). For PO Item quantities:

```text
available_service_qty = PO Item.qty - PO Item.subcontracted_qty
service_per_fg         = PO Item.qty / PO Item.fg_item_qty
SCO finished_good_qty = available_service_qty / service_per_fg
service_amount         = available_service_qty × PO Item.rate
```

The active Subcontracting BOM supplies the finished-good BOM, else Item.default_bom does
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:240-293`). Shared item validation
independently calculates pending stock quantity from `stock_qty - subcontracted_qty`, divides it by the
row conversion factor and rejects SCO quantity above that result
(`controllers/subcontracting_controller.py:135-206`).

SCO validation then normalises its service rows again:

```text
service.qty         = FG.qty × FG.subcontracting_conversion_factor
service.fg_item_qty = FG.qty
service.amount      = service.qty × service.rate
```

and rejects stock service Items (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:141-171`).
On submit, every PO Item's mutable `subcontracted_qty` is read, incremented and written; cancellation
subtracts it (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:336-357`).

> **Invariant M42 — commercial/physical conservation.** For each source order line,
> `allocated_service_qty = allocated_fg_qty × snapshotted_service_per_fg`. The allocation is unique and
> bounded by the source-line residual under one lock. A mutable `subcontracted_qty` cache is not the
> allocation itself.

---

## 4. SCO raw-material expansion and planned rate

### 4.1 BOM expansion

The shared controller reads direct `BOM Item` or flattened `BOM Explosion Item` according to
`include_exploded_items`. It computes:

```text
qty_consumed_per_unit = BOM row.stock_qty / BOM.quantity
required_rm_qty       = qty_consumed_per_unit × FG qty basis × FG conversion_factor
```

It omits `sourced_by_supplier`, recursively expands phantom rows, retains `bom_detail_no`, UOM, rate and
source warehouse, and places SCO material in `set_reserve_warehouse` or the FG warehouse
(`controllers/subcontracting_controller.py:560-622`,
`controllers/subcontracting_controller.py:932-983`). Each SCO supplied row stores `required_qty` and
`amount = required_qty × BOM rate`.

This is a requirement snapshot only in the weak sense that child rows are persisted. A later save can
clear and rebuild them from the then-current BOM. Alternative Items are folded through `original_item`
in transfer/receipt logic rather than represented as immutable substitutions.

### 4.2 Planned FG cost

The SCO calculates:

```text
service_cost_per_qty = matching service row.amount / FG qty
rm_cost_per_qty      = Σ direct BOM Item.amount / BOM.quantity
FG planned rate      = rm_cost_per_qty + service_cost_per_qty + additional_cost_per_qty
FG planned amount    = FG qty × FG planned rate
```

(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:189-214`). The service match is
by `purchase_order_item`, not table position.

Additional costs exclude secondary/legacy-scrap rows and use one of two distributions:

```text
Amount basis:
  item.additional_cost_per_qty =
      ((item.amount / Σ eligible item.amount) × total_additional_cost) / item.qty

Qty basis:
  item.additional_cost_per_qty = total_additional_cost / Σ eligible item.qty
```

(`controllers/subcontracting_controller.py:1240-1284`). Non-zero additional cost with zero eligible
amount/quantity has no explicit denominator guard.

The SCO's planned raw-material cost is not authoritative for stock or GL. Receipt material is repriced
from supplier-warehouse valuation at its posting time; inventory GL then reads actual receipt SLE
`stock_value_difference`.

> **Invariant M43 — actual cost authority.** Order cost is a quote/planning snapshot. Posted supplier
> material cost comes from exact consumed stock layers, posted output inventory comes from stock
> `value_delta`, and every difference from commercial or planned cost is a named allocation or variance.

---

## 5. Reservation and Bin effects

SCO submit optionally creates one `Stock Reservation Entry` request per supplied row, keyed by the SCO
raw-material child. Default reserved quantity is `required_qty`; callers can override warehouse/quantity
or transfer reservation provenance from a Stock Entry/Production Plan
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:359-430`). Cancellation of the
SCO itself does not call the displayed reservation-cancel method; cancellation paths and linked stock
flows rely on the broader reservation machinery and document links.

Two parallel representations coexist:

1. explicit Stock Reservation Entries, including serial/batch allocations; and
2. legacy/recomputed `Bin.reserved_qty_for_sub_contract`.

SCO status refresh writes FG `Bin.ordered_qty` from `get_ordered_qty`, and for every supplied Item calls
`Bin.update_reserved_qty_for_sub_contracting()`
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:216-237`). It also recomputes
Material Request requested quantity (`controllers/subcontracting_controller.py:1314-1333`). A send
Stock Entry transfers or consumes explicit reservations, then refreshes the Bin subcontract-reserved
projection.

The supplier warehouse itself is ordinary company stock: send transfer increases its Bin actual
quantity and receipt consumption decreases it. It is not merely a memorandum location.

> **Invariant M44 — supplier material allocation.** Company material sent to a supplier remains
> company-owned inventory and is allocated by exact transfer line/lot to a subcontract order output.
> `required`, `reserved`, `sent`, `returned`, `available` and `consumed` are projections over immutable
> allocation edges and cannot be independently writable counters.

---

## 6. Send to supplier and return from supplier

### 6.1 Builder and stock evidence

`make_rm_stock_entry` creates purpose **Send to Subcontractor**. Per supplied row:

```text
qty_to_send = explicit qty
              or max(required_qty - total_supplied_qty, 0)
source      = row.warehouse or reserve_warehouse
target      = SCO.supplier_warehouse
```

It carries SCO/SCO-RM, FG, UOM, alternative Item and serial/batch references
(`controllers/subcontracting_controller.py:1354-1454`). Stock Entry writes source SLE before target
SLE: source `actual_qty = -transfer_qty`, target `actual_qty = +transfer_qty`; target valuation uses the
row valuation rate and receives a transfer bundle (`stock/doctype/stock_entry/stock_entry.py:977-1120`).
Thus the movement conserves company quantity and value while changing custody/location.

### 6.2 Validation policies

`SendToSubcontractorStockEntry` selects policy from Buying Settings
(`stock/doctype/stock_entry/services/subcontracting.py:12-35`). Under **BOM** backflush:

```text
required_by_item = Σ SCO supplied required_qty for rm_item_code
allowed          = required_by_item × (1 + over_transfer_allowance / 100)
net_after_send   = prior sent for this sco_rm_detail + current transfer - prior returns
require net_after_send <= allowed
```

(`stock/doctype/stock_entry/services/subcontracting.py:36-94`). Notice the mismatch: required quantity
is aggregated by Item across the SCO, while prior send/return is scoped to one SCO RM detail. If one RM
appears under multiple FG/detail rows, each detail can be validated against the whole-SCO requirement.

Under **Material Transferred for Subcontract**, validation requires the FG reference and tries to link an
SCO RM detail, but applies no quantity ceiling (`stock/doctype/stock_entry/services/subcontracting.py:96-112`).
The builder default is conservative; the server invariant is not.

### 6.3 Recomputed sent/returned/total

On send/return submit and cancel, the service queries submitted linked Stock Entry rows and overwrites
each SCO supplied child:

```text
supplied_qty       = Σ non-return transfer_qty
returned_qty       = Σ return transfer_qty
total_supplied_qty = supplied_qty - returned_qty
```

(`stock/doctype/stock_entry/services/subcontracting.py:166-249`). The query does not filter Stock Entry
purpose; it classifies every linked submitted row solely by `is_return`, so an unexpected linked purpose
can pollute the projection.

`get_materials_from_supplier` reconstructs supplier availability from sent transfers minus transfer
returns and prior SCR consumption. It creates purpose **Material Transfer**, `is_return = 1`, source
supplier warehouse, target original reserve/source warehouse, splitting batches and carrying available
serials (`controllers/subcontracting_controller.py:1456-1557`).

> **Invariant M45 — custody conservation.** Send/return writes paired stock moves whose total company
> quantity and value are zero, preserving exact serial/batch identity. Net quantity at supplier equals
> sent minus returned minus consumed for the same material-allocation identity — never merely the same
> Item code.

---

## 7. Receipt raw-material selection and backflush

### 7.1 Available-material fold

For a receipt, the shared controller reads submitted send and supplier-return Stock Entries, keyed by:

```text
(raw_material, subcontracted_finished_good, subcontract_order)
```

It adds send quantity, subtracts returns, reconstructs inward supplier serial/batch bundles, then
subtracts supplied-item consumption from submitted Subcontracting Receipts
(`controllers/subcontracting_controller.py:285-557`). It separately computes pending FG as SCO Item
`qty - received_qty` (`controllers/subcontracting_controller.py:252-283`).

The resulting availability is a read-time in-memory fold. No SCO/SCO-item/SCO-RM row lock is acquired
before a new receipt allocates from it.

### 7.2 BOM backflush

For each receipt FG, BOM mode regenerates raw rows using:

```text
basis_fg_qty = received_qty, else accepted qty + rejected qty
consumed_rm  = BOM qty per unit × basis_fg_qty × FG conversion_factor
```

Returns deliberately use BOM mode even when the global policy is transferred-material backflush
(`controllers/subcontracting_controller.py:932-983`). Submit validates aggregate consumed quantity by RM
Item against the BOM requirement, unless alternative Items are allowed; transferred-material policy can
skip the check when `validate_consumed_qty` is off
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:603-649`).

Because this validation aggregates only by RM Item across the whole receipt, duplicate FG/BOM roles are
not allocation identities.

### 7.3 Transferred-material backflush

For partial receipt:

```text
allocated_rm = receipt_fg_qty × available_transferred_rm / pending_fg_qty
```

Serialized and whole-number-UOM quantities are rounded up. The in-memory available balance is decremented
as rows are generated (`controllers/subcontracting_controller.py:911-930`,
`controllers/subcontracting_controller.py:961-983`). If the current receipt equals all pending FG, it
takes the complete remaining transfer balance.

The receipt stores `available_qty_for_consumption = total_supplied_qty - consumed_qty` aggregated over
matching SCO/FG/RM supplied rows (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:452-494`).
On submit/cancel, SCO supplied-row `consumed_qty` is recomputed from all submitted receipts, allocated in
child `idx` order and capped by **gross `supplied_qty`**, not net `total_supplied_qty`
(`controllers/subcontracting_controller.py:1110-1144`). A return after a receipt can therefore expose a
projection in which consumed exceeds material still net-supplied.

> **Invariant M46 — consumption completeness.** Every received output quantity references a complete,
> locked set of supplier-material allocations or an explicit authorised exception. BOM policy and
> transferred-material policy are versioned algorithms; neither may consume an unlocked aggregate
> residual or treat gross sent quantity as net availability.

---

## 8. Serial and batch continuity

Transfer availability reads modern Serial and Batch Bundles and the legacy serial/batch fields. Receipt
allocation sorts available serials, slices the required integer quantity, and consumes positive batch
balances until filled. It creates a draft supplier-warehouse bundle with `Outward` direction for normal
consumption and `Inward` for negative/return consumption
(`controllers/subcontracting_controller.py:623-713`,
`controllers/subcontracting_controller.py:748-895`). Under transferred-material policy it validates
that selected batch/serial identity was actually transferred (`controllers/subcontracting_controller.py:1045-1101`).

Stock Entry send creates a target package from the source outward bundle; SCR submit converts legacy
fields to bundles before SLEs. A later valuation repost can reprice supplied rows, but tracked identity
remains tied to the voucher/detail bundle.

This is stronger than Item-only quantity validation, but bundle selection still occurs from an unlocked
availability preview. Stock-ledger serial uniqueness and negative-stock checks catch some concurrent
conflicts only after both business allocations have passed.

> **Invariant M47 — subcontract tracked-unit continuity.** A serial or batch quantity has one custody
> owner and one open allocation at every stage: source warehouse → supplier custody → receipt
> consumption/output or exact return. Selection and allocation commit under the same lock; repost may
> change value projections, never identity edges.

---

## 9. Subcontracting Receipt outputs and valuation

### 9.1 SCO → SCR and process loss

The mapper defaults:

```text
mapped received basis = SCO Item.qty - SCO Item.received_qty
process_loss_qty      = mapped basis × BOM.process_loss_percentage / 100
accepted qty          = mapped basis - process_loss_qty
```

and links SCO/SCO Item/PO Item (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:435-493`).
Rejected quantity is separate. As in manufacturing, process loss has no stock row: it increases the
cost allocated over accepted/rejected/output quantities.

### 9.2 Secondary outputs

Every BOM Secondary Item becomes an ordinary incoming SCR Item linked by `reference_name` to its FG.
The implementation calculates:

```text
per_unit          = secondary.stock_qty / BOM.quantity
received_qty      = FG.received_qty × per_unit
net secondary qty = FG.received_qty ×
                    (per_unit - secondary.process_loss_qty / BOM.quantity)
```

For non-legacy secondary output:

```text
FG allocable pool = (RM/unit + prior secondary/unit + additional/unit
                     + LCV/unit + service/unit) × FG.received_qty
secondary rate    = FG allocable pool × cost_allocation_percent / net secondary qty
```

Legacy scrap instead uses current warehouse valuation/BOM fallback
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:339-435`). The row stores
`qty = received_qty` for non-legacy output but `amount = net secondary qty × rate`; later costing uses
`received_qty - process_loss_qty`. A 100%-loss secondary can divide by zero before submit validation,
because validation checks stored row `qty`, not the local denominator.

### 9.3 Final receipt cost

Each supplied row is repriced from supplier-warehouse stock at posting date/time and exact bundle:

```text
RM amount             = consumed_qty × realised supplier-warehouse rate
FG rm_supp_cost       = Σ linked RM amount
FG rm_cost_per_qty    = rm_supp_cost / (received_qty or accepted qty)
FG pre-allocation rate = RM/unit + service/unit + additional/unit + LCV/unit
received_qty          = accepted + rejected + process_loss
FG amount             = received_qty × rate × BOM.cost_allocation_per / 100
stored FG rate         = FG amount / (accepted qty or rejected qty)
```

(`controllers/subcontracting_controller.py:77-107`,
`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:496-562`). Secondary output
cost is accumulated separately into `secondary_items_cost_per_qty`.

This is not one clean coproduct equation: modern secondary output rates can use current document amount
or an independently reconstructed pool, legacy scrap uses live valuation, and the principal FG applies
its BOM allocation percentage separately.

> **Invariant M48 — subcontract yield and cost allocation.** For each receipt conversion,
> `Σ output_value + explicit_loss_or_variance = Σ realised_material_value + service_cost + additional_cost + landed_cost`.
> FG, rejected output, scrap, by-product and process loss are typed facts. Allocation weights are
> snapshotted and one deterministic residual rule allocates every value unit exactly once.

---

## 10. Exact SCR Stock Ledger Entries

`SubcontractingController.update_stock_ledger` first refreshes linked SCO ordered/reserved Bins, then
builds all accepted/rejected output SLEs, then supplier-material SLEs
(`controllers/subcontracting_controller.py:1146-1230`):

| Evidence | Warehouse | Quantity | Rate/dependency |
|---|---|---:|---|
| accepted FG or secondary | item warehouse | `+ item.qty × conversion_factor` | rounded `item.rate`, `recalculate_rate = 1` |
| rejected FG | rejected warehouse | `+ rejected_qty × conversion_factor` | incoming rate 0 |
| consumed raw material | supplier warehouse | `- consumed_qty` | outgoing valuation; depends into FG `reference_name` |
| return SCR FG/output | same rows with negative document quantities | outward | original return mechanics/rates |
| return SCR raw material | supplier warehouse | positive | `item.rate` as incoming rate |

There is no SLE for service or Additional Cost. They are capitalised by increasing output incoming rate.
The inventory value actually posted is the SLE `stock_value_difference`, not `item.amount`.

Source/dependency ordering lets a valuation repost propagate a changed raw-material layer into the output
and then into future stock. Cancellation reverses quantities through common ledger cancellation and
reposts future SLE/GL.

> **Invariant M49 — subcontract stock projection.** A receipt conversion's immutable stock moves include
> every material issue and output receipt under one conversion ID. Projection processing consumes input
> dependencies before outputs; replay can change running rates/value deltas but never the event rows.

---

## 11. Exact SCR GL composer

The dedicated composer returns no rows when perpetual inventory is disabled. Otherwise it builds rows
then passes them through `process_gl_map`
(`subcontracting/doctype/subcontracting_receipt/services/gl_composer.py:20-30`). For each non-zero-rate,
non-zero-qty accepted output whose warehouse resolves:

| Leg | Amount | Side |
|---|---:|---|
| accepted output inventory | exact active output SLE `stock_value_difference` | **Dr** |
| FG detail expense/clearing | `SVD - service_cost` | **Cr** |
| service expense account (fallback FG expense) | `service_cost_per_qty × accepted qty` | **Cr** |
| supplier-warehouse inventory per consumed RM | `consumed_qty × realised RM rate` | **Cr** |
| supplied-RM expense/clearing | same RM amount | **Dr** |
| FG expense/clearing, Additional Cost offset | `accepted qty × additional_cost_per_qty` | **Dr** |
| each Additional Cost expense account | child `base_amount`, or transaction amount under its currency rule | **Cr** |
| stock-adjustment account | `item.amount - output SVD` | **Cr** |
| FG expense/clearing variance offset | same signed divisional loss | **Dr** |

The item, service, RM and divisional-loss rows are in
`subcontracting/doctype/subcontracting_receipt/services/gl_composer.py:32-182`; Additional Cost credits
are at `subcontracting/doctype/subcontracting_receipt/services/gl_composer.py:184-203`. Negative values
are normalised by the GL engine.

The divisional-loss pair is the crucial reconciliation rule:

```text
output inventory amount = SLE stock_value_difference
intended receipt amount  = SCR Item.amount
divisional loss          = intended receipt amount - SLE stock_value_difference
```

Inventory is never forced to the document amount. The difference goes to Company
`stock_adjustment_account` against the item expense/clearing account.

LCV adds a second pair: each landed-cost expense account is credited by its allocated share and the FG
expense/clearing account receives the opposite debit; the revised inventory amount still comes from the
revalued SLE (`subcontracting/doctype/subcontracting_receipt/services/gl_composer.py:205-260`).

### Worked receipt

Assume supplier stock supplies RM value 40, service cost 12 and Additional Cost 3. The output SLE receives
FG at 55, while document allocation/rounding says 56:

| Account | Debit | Credit |
|---|---:|---:|
| FG inventory, exact SLE | 55 | |
| FG expense/clearing base | | 43 |
| service expense | | 12 |
| supplier RM inventory | | 40 |
| RM expense/clearing | 40 | |
| FG expense/clearing additional offset | 3 | |
| additional-cost source | | 3 |
| FG expense/clearing divisional offset | 1 | |
| stock adjustment | | 1 |

Clearing legs net; final economics are `Dr FG inventory 55 + Dr variance/clearing treatment 1` against
`Cr supplier RM inventory 40 + Cr service 12 + Cr additional source 3 + Cr stock adjustment 1`, subject
to account merging. Most importantly, inventory remains exactly 55, the stock projection value.

> **Invariant M50 — subcontract stock/GL bridge.** Per receipt and inventory account,
> `Σ GL signed inventory amount = Σ SLE value_delta`. Material, service, additional and landed-cost
> sources are explicit balanced legs; intended-vs-projected and rounding differences use named variance
> accounts.

---

## 12. Receipt lifecycle, upstream projections and optional Purchase Receipt

### 12.1 Submit and cancel order

SCR submit performs:

```text
validate SCO open + BOM consumption
StatusUpdater: SCO Item.received_qty / parent per_received
refresh SCO status
recompute SCO consumed_qty
create/convert serial-batch bundles
update reservations
post SLEs
post GL
repost future valuation
set SCR status
optionally create Purchase Receipt
refresh Job Card manufactured quantity
```

(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:168-187`). Cancellation updates
upstream quantities/consumption/status before reversing SLE, reservation and GL, then reposts and cleans
bundles (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:192-213`).

SCO status is `Completed`/`Partially Received` by `per_received`; otherwise it compares aggregate
`supplied_qty` with aggregate `required_qty` to choose `Material Transferred`, `Partial Material
Transferred` or `Open`. Cancel is `Cancelled`; `Closed` is a manual override
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:296-335`). SCR status is Draft,
Completed, Return, Return Issued or Cancelled
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:651-704`).

A latent bug exists in shared status propagation: the SCR branch references
`self.__get_subcontract_orders` without calling it. Ordinary validation usually populated
`self.subcontract_orders`, masking stale/missing state (`controllers/subcontracting_controller.py:1228-1239`).

### 12.2 Optional Purchase Receipt

Buying Settings can auto-create a Purchase Receipt after SCR submission
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:706-708`). It does **not**
receive the FG again. It maps the original PO's non-stock service row and converts accepted/rejected FG
back to service quantity:

```text
service_per_fg      = PO service qty / PO fg_item_qty
PR service qty      = service_per_fg × SCR accepted FG qty
PR rejected service = service_per_fg × SCR rejected FG qty
```

It links `subcontracting_receipt_item`, copies posting time/supplier warehouse and marks the PR
subcontracted (`subcontracting/doctype/subcontracting_receipt/mapper.py:20-129`). The PR completes the
commercial PO receipt/SRBNB/provisional flow; the SCR remains the only FG/material stock conversion.

> **Invariant M51 — evidence before projection.** Receipt stock moves, tracked-unit allocations and GL
> journal commit atomically before SCO/PO/Job Card/Bin/status projections advance from the committed
> event position. Optional commercial service receipt is idempotently linked and cannot duplicate the
> physical FG receipt.

---

## 13. Customer-owned Subcontracting Inward Order — distinct reverse-ownership flow

The inward flow is not ordinary subcontracting with party names exchanged. The company is the service
supplier. A Sales Order authorises the service; customer material enters company custody; internal
Work Orders consume customer and company material; FG is delivered back. Its ownership and accounting
rules therefore need separate treatment.

### 13.1 Sales Order → SCIO

The mapper copies every not-fully-subcontracted Sales Order Item into SCIO service rows and, only when
exactly one non-disabled/non-rejected customer Warehouse exists, defaults it
(`selling/doctype/sales_order/mapper.py:1055-1122`). It does not filter that auto-selected warehouse by
company.

`populate_items_table` calculates:

```text
available_service_stock_qty = SO Item.stock_qty - SO Item.subcontracted_qty
service_per_fg               = SO Item.stock_qty / SO Item.fg_item_qty
SCIO FG qty                  = available_service_stock_qty / service_per_fg
```

and selects active Subcontracting BOM/default BOM
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:165-218`). On
submit/cancel, the SCIO loads each Sales Order Item and saves an increment/decrement to
`subcontracted_qty` (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:133-142`).

Shared BOM expansion puts Items flagged `is_customer_provided_item` in `customer_warehouse`; company
material keeps its BOM/default source. SCIO requires at least one customer-provided RM per FG and checks
only that `Warehouse.customer == SCIO.customer`
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:220-234`,
`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:143-151`). It does not
at that point enforce warehouse company, leaf, enabled or immutable ownership.

> **Invariant M52 — explicit inventory ownership.** Customer-owned stock carries an immutable owner on
> every stock lot/move/allocation. Custody warehouse is not ownership; zero value is an accounting
> policy, not legal provenance. Generic transfers cannot cross owner boundaries without an authorised
> ownership event.

### 13.2 Receive and return customer material

`make_rm_stock_entry_inward` creates purpose **Receive from Customer**, target-only rows for
customer-provided material:

```text
qty to receive = required_qty - received_qty + returned_qty
                 + BOM stock_qty × SCIO FG process_loss_qty
warehouse      = SCIO customer warehouse
```

(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:326-382`). Validation
rejects non-customer-provided Items, requires additional material to name its FG, forbids duplicate
additional `(Item, FG)` rows, and forces the target to the customer warehouse
(`controllers/subcontracting_inward_controller.py:61-110`,
`controllers/subcontracting_inward_controller.py:386-418`).

Before SLE construction, Stock Entry forces:

```text
valuation_rate              = 0
customer_provided_item_cost = basic_rate + additional_cost / transfer_qty
```

(`controllers/subcontracting_inward_controller.py:573-594`). The positive customer-warehouse SLE thus
adds quantity with zero inventory value. The memorandum cost is stored only on the Stock Entry detail
and folded into a mutable weighted SCIO child rate:

```text
balance_qty = received - returned - consumed
old_total   = old_rate × balance_qty
new_rate    = (old_total + current_rate × current_qty) / (balance_qty + current_qty)
```

(`controllers/subcontracting_inward_controller.py:748-797`).

`make_rm_return` creates source-only **Return Raw Material to Customer** rows with:

```text
returnable = received_qty - work_order_qty - returned_qty
```

(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:384-438`). The
builder does not filter customer-provided rows; company-owned rows can therefore be proposed, including
negative quantities. Server validation caps the return against the linked child
(`controllers/subcontracting_inward_controller.py:112-159`). Receipt cancellation is blocked when it
would leave less customer stock than already allocated to Work Orders
(`controllers/subcontracting_inward_controller.py:596-616`).

Each receipt also creates a Stock Reservation Entry, copying exact serial/batch entries when present
(`controllers/subcontracting_inward_controller.py:1033-1065`). Return/delivery serials and batches must
belong to that SCIO reservation lineage (`controllers/subcontracting_inward_controller.py:420-488`).

### 13.3 Internal Work Orders

For each incomplete FG, SCIO proposes an ordinary Work Order linked to SCIO/FG, source customer
warehouse, target delivery warehouse and reservation enabled. Maximum producible quantity is:

```text
for each customer RM:
  producible_i = (received_qty - returned_qty - work_order_qty)
                 / (RM required_qty / ordered FG qty)

max_producible = min(producible_i)
qty            = min(max_producible, ordered FG qty - produced_qty)
```

Whole-number UOM floors the result
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:238-312`).

Work Order validates source = customer warehouse, FG warehouse = SCIO delivery warehouse, every
customer Item sourced from customer warehouse, no duplicate customer Item, and:

```text
WO required_qty <= received_qty - returned_qty - prior work_order_qty
```

Company Items may not source from a Warehouse carrying a customer
(`manufacturing/doctype/work_order/work_order.py:364-459`). Submit/cancel increments/decrements SCIO
received-row `work_order_qty`, using Item-code maps and SQL CASE updates
(`manufacturing/doctype/work_order/work_order.py:614-710`). Duplicate same-Item requirement lines lose
identity in those maps.

Manufacture uses ordinary source-before-target Stock Entry/SLE/GL from doc 37. If Work Order
`skip_transfer` is on, customer consumption is checked against SCIO received-minus-returned; otherwise
against Work Order transferred-minus-consumed. Customer Items must come from the customer warehouse
(`controllers/subcontracting_inward_controller.py:228-383`). Their zero valuation contributes no
company-owned material value to FG; company material, operation and Additional Costs do.

On Manufacture submit/cancel, SCIO FG `produced_qty` and `process_loss_qty` are recomputed from submitted
Work Orders (`subcontracting/doctype/subcontracting_inward_order_item/subcontracting_inward_order_item.py:39-52`).
The inward mixin updates consumed RM, creates submitted child rows for extra company material, and
creates/updates secondary-output rows (`controllers/subcontracting_inward_controller.py:798-1017`).
These are projections around the ordinary production stock evidence, not a separate inward ledger.

### 13.4 FG/secondary delivery and return

`make_subcontracting_delivery` creates source-only Stock Entry rows. Normally:

```text
deliverable FG = min(ordered_qty, produced_qty) - delivered_qty
```

When overproduced delivery is enabled, the builder incorrectly proposes the **full cumulative
`produced_qty`**, not produced minus already delivered. Secondary quantity is produced minus delivered
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:440-499`). Server
validation computes its own maximum and rejects excess (`controllers/subcontracting_inward_controller.py:490-572`).
Both FG and secondary rows use normal outward SLE and Stock Entry GL, so company-valued FG leaves the
delivery warehouse as an expense/clearing movement. There is no customer-facing Delivery Note.

`make_subcontracting_return` creates target-only rows for:

```text
returnable FG = delivered_qty - returned_qty
```

with warehouse left for the user (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:501-559`).
Delivery/return counters are grouped by child and updated as SQL `field + delta`, which avoids a simple
lost increment but does not make the preceding maximum check atomic
(`controllers/subcontracting_inward_controller.py:649-705`). Cancellation guards prevent produced or
secondary quantity falling below delivered quantity and company-material consumed quantity below billed
quantity (`controllers/subcontracting_inward_controller.py:618-681`).

### 13.5 Commercial billing

The Sales Order service Item is billed normally. The Sales Invoice mapper additionally appends each
**company-owned** SCIO material at:

```text
billable = max(required_qty, consumed_qty) - billed_qty
```

and invoice submit/cancel updates SCIO `billed_qty`
(`selling/doctype/sales_order/mapper.py:516-555`,
`accounts/doctype/sales_invoice/sales_invoice.py:917-959`,
`accounts/doctype/sales_invoice/sales_invoice.py:1134-1153`). Customer-owned material is not sold back.
This separates service revenue and self-procured material billing from stock custody, but the same
unlocked residual pattern applies.

### 13.6 Percentages and status

SCIO recomputes and separately `db_set`s:

```text
per_raw_material_received = customer RM received / customer RM required × 100
per_raw_material_returned = customer RM returned / customer RM received × 100
per_produced              = FG produced / FG ordered × 100
per_process_loss          = process loss / FG produced × 100
per_delivered             = FG delivered / FG ordered × 100
per_returned              = FG returned / FG delivered × 100
```

(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:80-131`). Raw
material received, produced and delivered divide without zero guards. Submitted status priority is
`Returned` when `per_returned == 100`, then Delivered, Produced, Ongoing if any customer material was
received, else Open. Therefore delivering and returning 1 of an ordered 100 makes the whole order
`Returned`; delivery is gross and ignores later return. Process-loss percentage uses loss/accepted
production, not loss/(accepted+loss).

> **Invariant M53 — inward fulfilment semantics.** Material custody, attempted production, accepted
> yield, process loss, gross delivery, customer return, net delivery and commercial billing are separate
> fulfilment measures. Terminal status derives from net obligations, never from one ratio whose
> denominator is a partial downstream quantity.

---

## 14. Submit/cancel ordering and evidence boundary

For inward Stock Entry, generic validation/rate/serial checks run before closed-order and inward-purpose
validation. Submit performs purpose callbacks, bundles/reservation changes, SLE/Bin, GL and future
repost, then the inward mixin mutates SCIO child projections and status
(`stock/doctype/stock_entry/stock_entry.py:274-352`). Cancellation reverses stock/GL/reservations before
the final inward projection reversal (`stock/doctype/stock_entry/stock_entry.py:354-405`). Transaction
rollback protects ordinary exceptions, but locks are held across both evidence and many projection
writes.

| Representation | Classification |
|---|---|
| Submitted Subcontracting Order / Inward Order | authorisation snapshot; child requirements durable but rebuildable before submit |
| Submitted send/return Stock Entry + detail | custody movement evidence |
| Submitted Subcontracting Receipt + items/supplied items | strongest supplier conversion command and cost allocation evidence |
| Submitted inward Work Order/Manufacture/Delivery Stock Entry | ordinary production/custody command evidence linked to SCIO |
| SLE quantity, voucher/detail, warehouse, serial/batch | stock evidence |
| SLE running value/rate/queue/SVD | mutable valuation projection rewritten by repost |
| GL Entry | accounting evidence in meaning; replaceable by repost mechanics |
| Serial and Batch Bundle / Stock Reservation Entry lineage | tracked-unit/allocation evidence with mutable delivered/consumed progress |
| PO/SO Item `subcontracted_qty` | mutable allocation projection |
| SCO supplied/consumed/received/status | mutable projection over Stock Entry/SCR |
| SCIO received/work-order/consumed/produced/delivered/returned/billed fields | mutable projection over stock, WO and invoices |
| SCO/SCIO percentages/status | mutable presentation projection |
| Bin actual/value | stock projection from SLE |
| Bin ordered/subcontract-reserved/reserved-stock/projected | planning/allocation projection |
| customer ownership | **not first-class evidence**; inferred from mutable Item/Warehouse plus zero valuation |

> **Invariant M54 — immutable subcontract posting.** Service allocation, custody stock moves, exact
> material consumption, outputs, ownership, tracked-unit edges, cost sources and balanced GL are
> append-only facts. Corrections add linked reversal/supersession facts. Every order/status/Bin/quantity
> counter is a rebuildable projection keyed by event sequence.

---

## 15. Defects and race inventory

### 15.1 Supplier flow defects

1. **Active Subcontracting BOM uniqueness races.** `db.exists` is not a database constraint
   (`subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:70-82`).
2. **BOM-mode over-transfer compares incompatible keys.** Required quantity is all SCO rows for an RM;
   sent/returned is one SCO RM detail (`stock/doctype/stock_entry/services/subcontracting.py:36-94`).
3. **Transferred-material mode has no transfer ceiling.** It validates references only
   (`stock/doctype/stock_entry/services/subcontracting.py:96-112`).
4. **Sent/returned recomputation is purpose-blind.** Every submitted linked Stock Entry is included
   (`stock/doctype/stock_entry/services/subcontracting.py:221-249`).
5. **Consumed is capped by gross supplied, not net supplied.** A later supplier return can leave
   `consumed_qty > total_supplied_qty` (`controllers/subcontracting_controller.py:1110-1144`).
6. **SCR status refresh has a missing call.** `self.__get_subcontract_orders` lacks `()`
   (`controllers/subcontracting_controller.py:1228-1239`).
7. **Secondary-output zero denominator.** Net secondary quantity can be zero while row `qty` remains
   non-zero (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:339-435`).
8. **Additional-cost zero denominator.** Amount/Qty policies divide by eligible totals without local
   guards (`controllers/subcontracting_controller.py:1240-1284`).

### 15.2 Inward-flow defects

1. **Ownership is inferred.** SLE has no owner; `Warehouse.customer` and zero valuation are mutable,
   indirect policy.
2. **Cross-company customer warehouse gap.** SO mapper and SCIO validation do not require the warehouse
   company to equal SCIO company (`selling/doctype/sales_order/mapper.py:1071-1090`,
   `subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:143-151`).
3. **RM return builder includes company material and negative balances.** It neither filters
   customer-provided rows nor requires quantity > 0
   (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:384-438`).
4. **Overproduction delivery builder is cumulative.** It proposes all produced quantity after a prior
   partial delivery (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:440-499`).
5. **Zero rows are generated.** Delivery/return builders skip `< 0`, not `<= 0`.
6. **Terminal Returned can mean one partial delivery was fully returned.** Status ignores the remaining
   ordered obligation (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:80-131`).
7. **Unguarded percentage and producible denominators.** Imported/malformed zero quantity can crash
   status or Work Order preview.
8. **Duplicate-line maps overwrite instead of sum.** Return, Manufacture consumption, Work Order
   required quantity and invoice billing contain dictionary-comprehension paths; physical rows can move
   twice while a child counter moves once. Delivery's `defaultdict(float)` is the safer exception.
9. **Dynamic child insertion uses `count + 1`.** Concurrent receipt/manufacture can create duplicate
   logical rows/indices (`controllers/subcontracting_inward_controller.py:706-797`,
   `controllers/subcontracting_inward_controller.py:798-1017`).
10. **Weighted receipt rate is read/calculate/absolute-write.** Concurrent receipt/cancel can lose
    quantity and corrupt the memo average (`controllers/subcontracting_inward_controller.py:748-797`).

### 15.3 Shared race pattern

No owner `FOR UPDATE`/advisory lock was found around:

- PO Item pending service → SCO allocation → `subcontracted_qty` write;
- SO Item pending service → SCIO allocation → `subcontracted_qty` save;
- SCO RM aggregate validation → send/return insert → supplied projection rewrite;
- transferred supplier availability → SCR material allocation;
- SCIO customer RM residual → Work Order allocation;
- produced residual → delivery, delivered residual → return;
- SCIO company-material consumed residual → billing; or
- SCIO dynamic RM/secondary child lookup → insert.

Some updates use SQL `field + delta`, and stock ledger/Stock Reservation Entry have narrower locks. Those
prevent selected lost updates but do not protect the business ceiling checked earlier. Two transactions
can both validate the same residual, then each commit a individually valid stock document whose sum
exceeds the authorisation.

> **Invariant M55 — serializable subcontract allocation.** Source-order service residual, supplier RM
> transfer/return/consumption, customer RM receipt/return/Work Order allocation, output delivery/return,
> tracked units and billable company material are bounded allocations. Validate and insert under one
> deterministic owner lock with unique allocation identities and non-negative residual constraints.

---

## 16. Target decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Non-stock service Item paired with stock FG | **Adopt** | immutable commercial/physical conversion allocation |
| Subcontracting BOM conversion factor | **Adopt concept** | versioned recipe revision and rational factor; DB-enforced active uniqueness |
| PO → SCO supplier authorisation | **Adopt** | unique bounded allocation against PO service line under lock |
| SO → SCIO customer-service authorisation | **Adopt separately** | reverse-ownership contract with explicit owner/custody policy |
| Supplier warehouse as ordinary stock | **Adopt** | ordinary stock projection plus supplier-custody allocation |
| Customer warehouse as ownership proxy | **Reject** | first-class inventory owner/consignor on lots and moves |
| Customer material forced to zero valuation | **Adopt accounting intent** | explicit owner-valued/memorandum policy; no company inventory asset |
| Mutable memorandum `customer_provided_item_cost` | **Replace** | immutable declared/customer cost observation separate from company valuation |
| Shared BOM expansion | **Adopt policy** | snapshot exact BOM revision and source requirement IDs |
| BOM backflush | **Adopt as named policy** | deterministic complete allocation against snapshotted requirements |
| Transferred-material backflush | **Adopt intent** | consume exact transfer-allocation residuals under owner lock |
| Item-code aggregation | **Reject** | requirement/FG/operation/lot allocation identity |
| Explicit Stock Reservation Entry lineage | **Adopt** | one locked allocation ledger including owner and tracked units |
| Parallel Bin subcontract reservation counters | **Projection only** | rebuild from allocations; never validate from it |
| Send/return paired Stock Entry | **Adopt** | immutable custody transfer and reversal edges |
| Receipt consuming RM and receiving FG/secondary | **Adopt** | one immutable conversion with typed inputs/outputs/loss |
| Process loss only as scalar | **Reject** | typed normal/abnormal loss event and account policy |
| Modern/legacy secondary allocation branches | **Replace** | one versioned coproduct allocation equation and residual rule |
| SCR inventory from SLE SVD | **Adopt exactly** | GL inventory reads stock projection value delta |
| Service/RM/Additional Cost/LCV explicit GL legs | **Adopt** | balanced journal generated from immutable cost-source allocations |
| Divisional loss to stock adjustment | **Adopt principle** | named policy-specific variance account; never force inventory |
| Optional PR for non-stock service | **Adopt** | idempotent commercial receipt linked one-to-one to physical receipt allocation |
| Inward ordinary Work Orders | **Adopt** | common production ledger with explicit customer-owner inputs |
| Inward delivery as internal Stock Entry only | **Replace** | customer-facing fulfilment event referencing exact output lots and valuation |
| Gross independent percentages determining status | **Reject** | net-obligation fulfilment projection with explicit yield/loss measures |
| Mutable PO/SO/SCO/SCIO counters | **Projection only** | idempotent projectors from immutable allocation/posting events |
| Read-check-write ceilings without owner lock | **Reject** | owner lock, bounded insert/update, idempotency key and unique source allocation |

The fifteen invariants added here are **M41–M55**: command identity; commercial/physical conservation;
actual cost authority; supplier allocation; custody conservation; consumption completeness; tracked-unit
continuity; yield and cost allocation; stock projection; stock/GL bridge; evidence before projection;
explicit ownership; inward fulfilment semantics; immutable posting; and serializable allocation.
Together with M30–M40 from doc 37 they define one production boundary: subcontracting changes who owns
or holds material and who performs the work, but stock, tracked-unit, cost and GL correctness still
requires immutable conversion evidence, exact allocation identity and projection-derived books.

---

Cross-references: doc 02 (valuation/repost), doc 03 (stock→GL and landed cost), doc 16 (reservation,
Warehouse and Bin), doc 17 (serial/batch), doc 22 (locking/jobs), doc 28 (tax determination), doc 30
(Purchase/Sales Orders and parties), docs 33–37 (BOM, operations, Work Orders, planning and production
stock/GL), S08/S10 (supplier and inward scenarios), and `docs/design/FINAL-SCHEMA.md` (target stock,
ownership, allocation and GL model). Next: doc 39, operational quality and inspection.
