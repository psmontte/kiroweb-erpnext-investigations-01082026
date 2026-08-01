# 37 — Manufacturing Stock Consumption, Scrap, WIP and GL

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Docs 33–36 traced the recipe, route, execution and planning layers. This document follows the point at
which those plans become inventory and accounting evidence. It covers every manufacturing-facing Stock
Entry purpose: **Material Transfer for Manufacture**, **Material Consumption for Manufacture**,
**Manufacture**, **Repack** and **Disassemble**. It also follows the Work Order and Job Card builders,
raw-material selection, semi-finished and secondary outputs, process loss, serial/batch identity,
valuation, additional costs, Stock Ledger Entry ordering, GL composition, cancellation and all mutable
roll-ups.

The central finding is that WIP is not a special production ledger. It is ordinary item stock in an
ordinary Warehouse, moved and valued through the same SLE engine as every other warehouse. A
manufacturing conversion is likewise not one atomic cost object: it is a submitted Stock Entry whose
source SLEs consume materials, whose target SLEs receive FG/secondary outputs, and whose GL rows bridge
the value difference and additional costs. Work Order, Job Card, reservation, planned quantity and
status fields around that posting are mutable projections. Repack uses the same conversion machinery;
Disassemble constructs a scaled reverse conversion. Corrective work changes Job Card/Work Order cost
and then ordinary FG valuation. **There is no separate rework ledger.**

---

## 1. One controller, purpose-specific services

`Stock Entry` is the one posting document. Assigning `purpose` selects a service class:

| Purpose | Service | Manufacturing meaning |
|---|---|---|
| Material Transfer for Manufacture | `MaterialTransferForManufactureStockEntry` | source warehouse → WIP warehouse |
| Material Consumption for Manufacture | `MaterialConsumptionForManufactureStockEntry` | raw/WIP stock → no target |
| Manufacture | `ManufactureStockEntry` | raw/WIP stock → FG, semi-FG and secondary outputs |
| Repack | `RepackStockEntry` | arbitrary source items → one or more target items |
| Disassemble | `DisassembleStockEntry` | FG and secondary outputs → recovered source material |

The dispatch table is in `stock/doctype/stock_entry/stock_entry.py:196`. The common controller calls the
service's `before_validate` and `validate`, then performs shared UOM, BOM, process-loss, serial/batch,
inspection, finished-good and accounting validation before calculating rates and amounts
(`stock/doctype/stock_entry/stock_entry.py:246`). `get_items()` clears the child table, delegates to the
purpose service, applies reservations and recalculates rates (`stock/doctype/stock_entry/stock_entry.py:1408`).

This split is important but incomplete. The service owns item generation and purpose callbacks; the
parent still owns valuation, SLE construction, reservations and the GL hand-off. The true command path
therefore crosses both classes and several Work Order/Job Card services.

> **Invariant M30 — conversion identity.** One posted production conversion has one immutable command
> identity and typed input/output lines. Every material issue, output receipt, secondary output, cost
> allocation, serial/batch assignment and GL posting references that identity. Purpose dispatch may
> select policy, but it cannot scatter ownership of one conversion across mutable parent callbacks.

---

## 2. Builders — Work Order and Job Card feed different shapes

### 2.1 Work Order builder

`make_stock_entry(work_order_id, purpose, qty, ...)` returns an unsaved Stock Entry. It copies company,
project, Work Order/BOM, multi-level policy and:

```text
fg_completed_qty = explicit qty
                   else Work Order.qty - Work Order.produced_qty
```

For transfer it sets target = non-group WIP warehouse. For every other manufacturing purpose it sets
source = WIP, except `skip_transfer && !from_wip_warehouse`, which uses the Work Order source warehouse;
target is FG warehouse. Disassemble reverses that direction and may name a specific Manufacture Stock
Entry (`manufacturing/doctype/work_order/mapper.py:230-286`). The mapper also carries
`is_additional_transfer_entry`, so ordinary and excess transfers are later summed into different Work
Order fields.

The builder calls `get_items()` immediately. It is a preview, not posting evidence, but its output has
already incorporated live Work Order counters, settings, transfer history and valuation reads. Repeating
the preview later can therefore produce different rows.

### 2.2 Job Card material-transfer builder

The Job Card mapper emits **Material Transfer for Manufacture**. Per Job Card Item:

```text
pending_rm_qty = required_qty - transferred_qty
header fg_completed_qty = max(for_quantity - transferred_qty, 0)
source = Job Card Item.source_warehouse
target = Job Card.wip_warehouse
```

It retains `job_card_item`, applies Work Order and Item alternative-item permission, and calls
`set_previous_operation_serial_batch()` so an operation can pull the exact serials/batches produced by
an earlier semi-finished operation (`manufacturing/doctype/job_card/mapper.py:88-158`).

### 2.3 Job Card semi-finished/final output builder

A completed Job Card with `finished_good` uses a different path. It builds `ManufactureEntry` with:

```text
for_quantity     = Job Card.for_quantity - manufactured_qty
process_loss_qty = max(Job Card.process_loss_qty - already posted loss, 0)
```

and copies Job Card, Work Order, semi-FG BOM, WIP and target warehouses. It then builds raw/FG lines,
replaces operation costs with Job-Card-scoped costs, and appends Job Card secondary outputs
(`manufacturing/doctype/job_card/job_card.py:1652-1717`). `ManufactureEntry` chooses Job Card material,
uses `transferred_qty - consumed_qty` under transfer backflush, pulls earlier-operation serial/batch
identity, and receives `for_quantity - process_loss_qty` as FG
(`stock/doctype/stock_entry_type/stock_entry_type.py:68-292`).

This path can save or auto-submit. It is not the same builder as Work Order → Stock Entry, even though
both ultimately create purpose `Manufacture`.

> **Ours.** A pure `preview_conversion(command)` accepts a released Work Order operation allocation and
> returns proposed typed lines with an `as_of_event_seq`. `post_conversion(idempotency_key, preview_hash)`
> revalidates under the Work Order/operation lock and writes the event. Work Order, Job Card and UI
> callers do not own independent builders.

---

## 3. Material Transfer for Manufacture — WIP is real stock

### 3.1 Generated quantities

The service starts from persisted Work Order required rows. Job-Card transfer mode narrows them to Item
codes present on that card; rows with `include_item_in_manufacturing = 0` are omitted. Alternative item
permission is copied, and a non-group Work Order WIP warehouse becomes the target
(`stock/doctype/stock_entry/services/material_transfer.py:231-346`).

For Work Order output quantity `W`, requested transfer-equivalent output `F`, required material `R` and
already transferred `T`:

```text
pending_to_issue    = R - T
desired_transfer    = F × R / W
additional_envelope = R × transfer_extra_materials_percentage / 100
```

`_resolve_transfer_qty()` returns desired quantity when it is positive and allowed, otherwise remaining
pending quantity (`stock/doctype/stock_entry/services/material_transfer.py:254-281`,
`stock/doctype/stock_entry/services/material_transfer.py:479`). Transfer is considered allowed when the
desired amount fits pending, the global backflush mode is **Material Transferred for Manufacture**, or
the header output quantity remains inside an overproduction/extra-material envelope. If both percentage
settings exist, `transfer_extra_materials_percentage` wins because the code uses `extra or
overproduction`, not the maximum of both.

### 3.2 Validation and additional materials

Every row requires source and target. Optional Stock Settings validation rejects an identical warehouse
unless at least one inventory dimension differs. When strict BOM component validation is enabled, rows
and rounded quantities must match BOM components. Otherwise the service aggregates transfer quantity
by required Item/original Item and blocks values above `required_qty - transferred_qty`. That excess
check is skipped for returns and entirely skipped when transfer-based backflush is configured
(`stock/doctype/stock_entry/services/material_transfer.py:158-230`).

A manually added non-BOM line is not kept in a separate exception ledger. On submit the service appends
a **new Work Order Item** with:

```text
is_additional_item        = 1
required_qty              = Stock Entry Detail.transfer_qty
voucher_detail_reference  = Stock Entry Detail.name
```

and saves the already-submitted Work Order under `ignore_validate_update_after_submit`; cancellation
deletes the matching child (`manufacturing/doctype/work_order/services/required_items.py:263-301`).
This converts posting input into a mutable authorisation snapshot after release.

### 3.3 Posting effect

A transfer row is two ordinary SLEs. For 10 kg of RM-A at realised source value 4.00/kg:

| Evidence | Warehouse/account | Qty | Value / signed GL |
|---|---|---:|---:|
| source SLE | Raw Materials | -10 | `stock_value_difference = -40` |
| target SLE | WIP | +10 | `stock_value_difference = +40` |
| GL | Raw Materials inventory | | Cr 40 |
| GL | WIP inventory | | Dr 40 |

The target does not receive a special production cost layer. Its incoming rate is the transfer row's
valuation rate, and the target SLE is marked for dependent-rate recalculation. The WIP warehouse can use
its own inventory account exactly like any other warehouse. If both warehouses map to the same account,
the merged GL may net to zero even though both SLEs remain.

> **Invariant M31 — WIP conservation.** A transfer to WIP changes location and allocation, not total
> item quantity or company inventory value: `Σ qty(item) = 0` and `Σ value_delta(item) = 0` across its
> two stock moves, subject only to an explicit transfer variance event. WIP is ordinary warehouse stock;
> production ownership is an allocation, never inferred from warehouse balance alone.

---

## 4. Material Consumption for Manufacture — issue without output

This service subclasses Manufacture but requires a Work Order and emits only source rows. It chooses
Work Order/BOM quantities when backflush is **BOM** or the Work Order skips transfer; otherwise it uses
remaining material transferred to WIP (`stock/doctype/stock_entry/services/manufacturing.py:852-868`).
There is no FG target on this document.

### 4.1 BOM/Work Order basis

For each required row:

```text
with Work Order: qty = required_item.required_qty / Work Order.qty × fg_completed_qty
without WO:      qty = BOM_row.qty × fg_completed_qty
```

Warehouse precedence is explicit Stock Entry source → Work Order WIP when `from_wip_warehouse` → BOM
default source → required-row source (`stock/doctype/stock_entry/services/manufacturing.py:414-456`).
Alternative material actually transferred for the Work Order can replace the BOM Item while retaining
`original_item`.

### 4.2 Transfer basis

The service reads every submitted Material Transfer for Manufacture row for the Work Order, aggregates
it by `(item_code, target WIP warehouse)`, and subtracts raw rows already present on submitted
**Manufacture** entries. Remaining serials and batch quantities are also subtracted. For remaining pool
`A`, current output `F`, transferred-equivalent output `M` and already produced output `P`:

```text
consumption qty = A × F / (M - P)
```

It then takes the first required serials or splits multiple batches into separate detail rows
(`stock/doctype/stock_entry/services/manufacturing.py:499-688`). Despite the method name
`get_consumption_entries`, this pool-subtraction query reads Manufacture raw rows, not purpose
Material Consumption rows.

### 4.3 Separate-consumption switch

When Manufacturing Settings enables material consumption, Manufacture asks only whether **any**
submitted Material Consumption for Manufacture entry exists for the Work Order. If yes,
`raw_materials_already_consumed()` suppresses every raw row on Manufacture
(`stock/doctype/stock_entry/services/manufacturing.py:392-419`). It does not test whether consumption is
complete for the output quantity.

An optional second setting, `get_rm_cost_from_consumption_entry`, changes FG costing. Manufacture then:

1. rejects raw-material rows on the Manufacture entry;
2. permits only one submitted Manufacture entry for the Work Order; and
3. sets raw cost to `Σ consumption_detail.valuation_rate × transfer_qty` over all submitted consumption
   entries (`stock/doctype/stock_entry/stock_entry.py:735-809`).

Without that setting, a no-input Manufacture estimates raw cost from BOM only when there is no actual
consumption basis. A genuine consumed cost of zero remains zero rather than falling back to an Item
valuation rate.

Accounting is two-stage. Consumption credits raw/WIP inventory and debits the line expense/clearing
account. Later Manufacture debits FG inventory and credits its line expense/clearing account. Nothing in
the schema forces all documents for one Work Order to use one dedicated WIP clearing account.

> **Invariant M32 — consumption completeness.** Output posting is allowed only when its input allocation
> is explicit: each output lot references the exact issue events or a locked remaining-input allocation.
> Existence of one partial consumption document is never evidence that every raw input was consumed.

---

## 5. Manufacture — raw selection and conversion outputs

`ManufactureStockEntry.add_items()` executes this order:

```text
raw materials
process-loss calculation
principal finished good
BOM secondary items
additional/non-stock/operation costs
Job Card secondary items
```

(`stock/doctype/stock_entry/services/manufacturing.py:384-391`). Generation order is later normalized
into source-before-target SLE order (§10), but it controls which rows and costs exist before valuation.

### 5.1 Four raw-material modes

| Separate material consumption | Backflush basis | Raw lines on Manufacture |
|---|---|---|
| off | BOM, or Work Order skips transfer | proportional Work Order/BOM requirement |
| off | Material Transferred for Manufacture | remaining WIP transfer pool prorated to output |
| on, no prior consumption doc | BOM | remaining unconsumed Work Order requirement prorated to output |
| on, no prior consumption doc | transfer | remaining transfer pool prorated to output |
| on, any prior consumption doc | either | **none** |

For the “remaining unconsumed BOM” branch:

```text
work_order_output_basis = material_transferred_for_manufacturing or Work Order.qty
remaining_output        = work_order_output_basis - produced_qty
material_basis          = transferred_qty or required_qty
remaining_material      = material_basis - consumed_qty
required_each           = min(remaining_material / remaining_output,
                              required_qty / Work Order.qty)
row qty                 = required_each × Stock Entry.fg_completed_qty
```

A zero remaining-output denominator is silently replaced by 1
(`stock/doctype/stock_entry/services/manufacturing.py:384-444`). Transfer-based consumption uses the
formula in §4.2. Strict component validation, when enabled, accepts original or alternative Item and
compares rounded quantity against the BOM (`stock/doctype/stock_entry/services/manufacturing.py:870-917`).

### 5.2 Principal FG and process loss

The principal FG receives:

```text
finished_good_qty = fg_completed_qty - process_loss_qty
```

Process loss is the maximum `Work Order Operation.process_loss_qty` when one exists; otherwise BOM
percentage is used:

```text
loss_qty = fg_completed_qty × process_loss_percentage / 100
loss_pct = process_loss_qty / fg_completed_qty × 100
```

(`stock/doctype/stock_entry/services/manufacturing.py:111-167`). Validation requires
`FG qty + process_loss_qty = fg_completed_qty` at field precision
(`stock/doctype/stock_entry/stock_entry.py:500-545`).

**Process loss creates no item row and no SLE.** Its economic effect is that the same input and added
cost is divided over fewer accepted FG units. The Work Order later stores the sum of Manufacture header
loss quantities as a mutable counter.

### 5.3 Secondary outputs, scrap and by-products

BOM Secondary Item rows become ordinary incoming Stock Entry Detail rows. They retain
`secondary_item_type`, `bom_secondary_item` and `is_legacy_scrap_item`; Scrap prefers Work Order scrap
warehouse, while every other secondary output uses the normal target. Per row:

```text
secondary qty before UOM rounding = BOM secondary qty × fg_completed_qty
secondary qty after own loss      = qty × (1 - process_loss_per / 100)
```

(`stock/doctype/stock_entry/services/manufacturing.py:45-110`). “Scrap”, “By-product” and other
secondary types are labels on ordinary target stock. There is no separate scrap or by-product ledger.

Submitted Job Card secondary rows are grouped by `(item_code, secondary_item_type)`. Quantities already
posted on Manufacture/Repack are subtracted, then the remainder is prorated:

```text
row stock_qty = (completed-card secondary qty - already posted qty)
                × current fg_completed_qty / pending completed-card output
```

(`stock/doctype/stock_entry/services/manufacturing.py:690-803`). A Job Card semi-FG output follows the
same Manufacture/SLE mechanism; it is distinguished by Work Order operation and Job Card provenance,
not a different inventory ledger.

### 5.4 Additional material versus additional cost

These are unrelated concepts:

- **additional material** is an extra source/transfer Item row, later appended as a mutable Work Order
  required row (§3.2);
- **Stock Entry Additional Cost** is a `Landed Cost Taxes and Charges` child with an expense account,
  included in target valuation and posted separately to GL (§7 and §11).

> **Invariant M33 — yield and coproduct identity.** Accepted FG, semi-FG, scrap, by-product and explicit
> loss are separate typed output facts tied to one conversion. `input_qty = output_qty` is not generally
> valid across different Items, but every input value unit is allocated exactly once among output value,
> variance and explicit loss/expense. Process loss cannot exist only as a mutable header scalar.

---

## 6. Repack and Disassemble

### 6.1 Repack

Repack loads BOM source rows from `from_warehouse`, applies the same process-loss and principal-FG
creation, then appends secondary outputs (`stock/doctype/stock_entry/services/manufacturing.py:811-850`).
It can represent a generic many-input/many-output conversion without a Work Order.

If exactly one FG is not manually rated:

```text
FG basic_rate = total source-only basic_amount / FG transfer_qty
```

For multiple unmanually-rated targets the helper can divide by their total quantity, but validation now
requires **all** FGs to be manually rated whenever more than one distinct FG exists
(`stock/doctype/stock_entry/stock_entry.py:717-733`,
`stock/doctype/stock_entry/services/manufacturing.py:819-828`). Repack and Manufacture both receive the
Standard Cost manufacturing-variance branch in GL.

### 6.2 Disassemble priority and direction

Disassemble chooses its basis in this order:

1. one named source Manufacture Stock Entry;
2. all submitted Manufacture entries for the Work Order;
3. BOM-only reconstruction.

If a Work Order has exactly one submitted Manufacture entry, it auto-selects it
(`stock/doctype/stock_entry/services/disassemble.py:137-171`). For source FG quantity `Qsrc` and requested
disassembly `Qd`:

```text
scale = Qd / Qsrc
FG                         → source/outward qty Qd
original source material   → target/inward qty source_qty × scale
secondary output           → source/outward qty source_qty × scale
```

A Work Order-wide reverse uses `Qsrc = Work Order.produced_qty`. BOM-only mode consumes FG and secondary
outputs and receives BOM raw materials (`stock/doctype/stock_entry/services/disassemble.py:172-317`).

Validation requires consumed FG stock quantity to equal `fg_completed_qty`. Every non-FG row must match
the named source detail or source Item aggregate times scale within one unit at quantity precision; a
foreign Item is rejected (`stock/doctype/stock_entry/services/disassemble.py:27-136`). A named source
entry is capped by:

```text
available = source Manufacture.fg_completed_qty
            - Σ submitted Disassemble.fg_completed_qty against that source
```

(`manufacturing/doctype/work_order/work_order.py:1091-1110`). Work Order `disassembled_qty` is separately
incremented/decremented and checked against `produced_qty`.

For a named source, serial/batch bundles are reconstructed proportionally from that voucher. Otherwise
the service reconstructs currently available identity from Work Order Manufacture, Consumption,
Transfer and Disassemble history. Serial numbers are sliced to integer quantity; batches are consumed
until requested quantity is filled (`stock/doctype/stock_entry/services/disassemble.py:393-515`).

Work Order-wide detail grouping is only by `item_code`. Quantity is summed and rate is quantity-weighted,
but role, warehouse, UOM, secondary type and bundle fields use `MAX()` under an assumption that one Item
has one role and warehouse across the Work Order (`stock/doctype/stock_entry/services/disassemble.py:319-391`).
That assumption is not enforced.

> **Invariant M34 — reversal provenance.** Disassembly/reversal outputs reference the exact original
> conversion input/output allocations and serial/batch lots. A broad Work Order average is a new
> transformation policy, not an “exact reversal”, and must be named and authorised as such.

---

## 7. Valuation and rate assignment

This section covers manufacturing-specific rate construction; generic FIFO/moving-average queue
mechanics remain in doc 02.

### 7.1 Source cost

Every source row is repriced from its source warehouse and bundle at posting date/time through
`get_incoming_rate()`. The row stores:

```text
basic_amount = transfer_qty × realised source basic_rate
outgoing_items_cost = Σ basic_amount for source-only rows
```

Transfer rows with both source and target do not contribute to `outgoing_items_cost`; their incoming
side carries the same row valuation (`stock/doctype/stock_entry/stock_entry.py:682-714`).

### 7.2 Principal Manufacture rate

For ordinary Manufacture:

```text
legacy_scrap_cost = Σ basic_amount where is_legacy_scrap_item
FG basic_rate     = (raw_material_cost - legacy_scrap_cost) / FG transfer_qty
```

Only **legacy** scrap is credited out of principal FG cost this way. Modern secondary outputs use their
own cost-allocation policy. If separate material consumption and “get RM cost from consumption entry”
are enabled, raw cost becomes the all-entry sum described in §4.3
(`stock/doctype/stock_entry/stock_entry.py:735-809`).

A BOM principal output `cost_allocation_per` multiplies the calculated FG basic rate. The same
function contains an apparent secondary-output allocation branch:

```text
secondary basic_rate = outgoing_items_cost × allocation_percentage
                       / secondary transfer_qty
```

but that `elif secondary_item_type ...` is nested inside `elif d.is_finished_item` and follows
`if self.bom_no`. Normal Manufacture secondary rows are not finished items and a BOM secondary is on a
document with `bom_no`, so the branch is not reachable for the ordinary case. The secondary row instead
falls back to its target Item valuation rate. A zero principal-FG rate derived from genuinely zero-cost
consumed input is retained; it does not trigger fallback
(`stock/doctype/stock_entry/stock_entry.py:614-675`).

### 7.3 Operation, non-stock and corrective costs

Manufacture clears and rebuilds the `additional_costs` child. It may add:

- non-stock BOM cost:
  `Σ non-stock BOM amount × fg_completed_qty / BOM.quantity`;
- workstation component actual cost:
  `component hourly rate × actual_operation_time / 60 - already consumed component cost`, allocated
  across the current FG quantity and capped at remaining actual cost;
- fallback Work Order/BOM operating cost per output unit;
- `Work Order.additional_operating_cost / Work Order.qty × fg_completed_qty`;
- remaining corrective-operation cost.

The implementation is in `manufacturing/doctype/bom/services/operations_cost.py:16-243`.

Corrective work is a submitted `Job Card` with `is_corrective_job_card`, `for_job_card` and
`for_operation`; it is excluded from normal completion aggregation. Its time is repriced into mutable
`Work Order.corrective_operation_cost`. If configured, Manufacture adds:

```text
remaining corrective cost = WO.corrective_operation_cost
                            - Σ corrective cost already attached to submitted Manufacture entries
available output           = minimum completed qty among non-corrective operations
                            - WO.produced_qty
current corrective cost    = remaining corrective cost / available output × fg_completed_qty
```

(`manufacturing/doctype/bom/services/operations_cost.py:201-243`). **No Rework Ledger, rework stock
ledger or separate rework accounting path exists.** Rework/correction is represented by corrective Job
Cards, mutable Work Order cost, a Stock Entry additional-cost row, ordinary output SLE and ordinary GL.

### 7.4 Final row value

Additional costs are distributed only to principal FGs for Manufacture/Repack, in proportion to FG
`basic_amount`. Other purposes distribute across all targets. If incoming basic amount is zero, the GL
composer falls back to quantity for account allocation. Final target detail fields are:

```text
additional_cost(row) = row.basic_amount / Σ eligible basic_amount × total additional costs
amount                = basic_amount + additional_cost + landed_cost_voucher_amount
valuation_rate        = basic_rate
                        + (additional_cost + landed_cost_voucher_amount) / transfer_qty
value_difference      = total incoming amount - total outgoing amount
```

(`stock/doctype/stock_entry/stock_entry.py:811-862`). Header `value_difference` is descriptive; actual
inventory GL still comes from SLE `stock_value_difference`.

> **Invariant M35 — one cost allocation equation.** For a conversion in company currency:
> `Σ output_value + explicit_variance = Σ realised_input_value + Σ resource/service_cost + Σ landed_cost`.
> Allocation percentages are snapshotted rational weights whose residual is assigned deterministically.
> No output may independently fall back to a live Item rate after part of the conversion has already
> consumed the shared cost pool.

---

## 8. Worked conversion and process-loss example

Assume a Manufacture Stock Entry consumes:

```text
RM-A: 6 × 4 = 24
RM-B: 2 × 8 = 16
raw cost = 40
legacy scrap: 1 unit allocated basic value 3
fg_completed_qty = 10
process_loss_qty = 1
accepted FG qty = 9
operation cost = 9
```

Manufacturing rate construction is:

```text
FG basic amount = raw cost - legacy scrap cost = 40 - 3 = 37
FG basic rate   = 37 / 9 = 4.111111...
FG final amount = 37 + operation cost 9 = 46
FG valuation    = 46 / 9 = 5.111111...
```

The physical/value evidence is:

| Row | Qty | Basic value | Added cost | Final incoming/outgoing value |
|---|---:|---:|---:|---:|
| RM-A source | -6 | 24 | 0 | -24 |
| RM-B source | -2 | 16 | 0 | -16 |
| legacy scrap target | +1 | 3 | 0 | +3 |
| accepted FG target | +9 | 37 | 9 | +46 |
| process loss | **no row** | | | |
| total | item quantities are incommensurate | 0 net basic | +9 | +9 net inventory value |

The extra company inventory value is exactly the capitalised operation cost. Process loss does not post
one unit of a “loss Item”; it raises accepted-unit cost because 40 of input basic value is allocated over
scrap plus only nine accepted FG units. If policy requires physical loss mass, emissions or a loss
expense, the current Stock Entry model cannot derive that evidence from the header alone.

---

## 9. Serial and batch behavior

### 9.1 Transfer and backflush

Material transfer converts an outward source bundle into an inward target package. Transfer-based
backflush rebuilds availability from submitted transfer bundles, subtracts Manufacture source bundles,
selects the first serials, and splits multiple batches into separate Stock Entry Detail rows
(`stock/doctype/stock_entry/services/manufacturing.py:530-688`). Job Card `ManufactureEntry` performs a
similar transfer-minus-consumption fold over Job-Card-linked Stock Entries
(`stock/doctype/stock_entry_type/stock_entry_type.py:96-246`).

For operation chains, `set_previous_operation_serial_batch()` first verifies that the Item is an output
of a Work Order operation, then computes produced bundles minus later consumed bundles for the same
Item/warehouse. It creates an outward bundle for the next operation, filling what is available and
leaving any shortfall blank for the user (`stock/doctype/stock_entry/services/manufacturing.py:1036-1193`).

### 9.2 Work Order-created FG identity

When configured, Work Order submit pre-creates inactive Serial Nos or empty Batches. Manufacture then
accepts only serials whose `work_order` matches or Batches whose `reference_name` is the Work Order;
invalid selections are reset to Work-Order-linked values. This restriction is skipped for Work Orders
tracking semi-finished goods (`stock/doctype/stock_entry/services/manufacturing.py:269-348`).

Serial selection is ordered by creation and sliced to required integer quantity. Batch selection sorts
batch IDs and consumes until quantity is filled. Those choices are reads before posting; the Stock
Ledger's per-item/warehouse lock eventually protects stock, but the builders themselves do not reserve
the selected identity.

### 9.3 Disassembly identity

A source-entry disassembly scales the source voucher's batch quantities and slices its serial list. A
Work Order/BOM disassembly instead uses currently available identity reconstructed across history. Both
create new inward/outward bundles on the disassembly detail, rather than linking every returned serial
or batch allocation to an immutable original conversion edge
(`stock/doctype/stock_entry/services/disassemble.py:393-515`).

> **Invariant M36 — tracked-unit continuity.** Every serial is allocated at most once at each stage;
> batch quantity allocations balance by lot. Transfer, operation consumption, output and disassembly
> write immutable allocation edges under a unique/locked allocator. “First available” preview selection
> is not ownership.

---

## 10. SLE ordering and WIP valuation

`update_stock_ledger()` always constructs **all source SLEs first**, then all target SLEs. On
cancellation it reverses the whole list before passing it to the ledger engine
(`stock/doctype/stock_entry/stock_entry.py:977-1120`). Therefore:

| Purpose | Source phase | Target phase |
|---|---|---|
| Transfer for Manufacture | consume source warehouse | receive WIP |
| Material Consumption | consume source/WIP | none |
| Manufacture | consume raw/WIP | receive FG, semi-FG, scrap/by-products |
| Repack | consume inputs | receive repacked outputs |
| Disassemble | consume FG and prior secondary outputs | restore prior raw materials |

A source leg with a target on the same detail sets `dependant_sle_voucher_detail_no` to that detail.
Source-only Manufacture inputs depend into the principal FG detail. Targets with a source leg, and the
principal FG target, get `recalculate_rate = 1`. These links let a future valuation repost cascade from
changed input cost into dependent output cost.

The ordering is economically necessary: target incoming valuation is calculated from source value. It
is not atomic evidence, however. The SLE engine inserts rows and stores derived running state in them;
a repost can later mutate valuation fields and GL can be compare-then-replaced (docs 02–03).

WIP has no production-specific valuation table. A component transferred into WIP becomes an ordinary
positive SLE for `(item, WIP warehouse)`. It can be reserved for the Work Order, but its availability,
negative-stock validation, FIFO/average queue, account mapping and later issue are the normal stock
engine. Warehouse location alone does not identify which Work Order owns a WIP balance.

> **Ours.** `stock_move` lines for one conversion are immutable and share `conversion_id`; source lines
> carry negative quantity and target lines positive quantity. Explicit `stock_move_dependency` edges
> connect each output allocation to its input/cost allocation. The valuation projector processes source
> dependencies before targets under sorted item/warehouse locks; replay changes only projection state,
> never event rows.

---

## 11. Stock Entry GL — SLE value is authoritative

`StockEntryGLComposer` starts with the base stock pair for every SLE-backed detail, then adds Stock Entry
Additional Cost, Landed Cost Voucher and Standard Cost variance rows. It deliberately disables the
P&L-only expense-account rule because transfer/WIP and opening-style counterparts may be balance-sheet
accounts (`stock/doctype/stock_entry/services/gl_composer.py:13-48`).

### 11.1 Base manufacturing pairs

For each SLE, the base composer posts Inventory by SLE `stock_value_difference` and the detail expense
account by its negative. The common patterns are:

| Movement | Inventory | Detail expense/clearing |
|---|---|---|
| raw/WIP source | Cr realised source SVD | Dr realised source SVD |
| FG/secondary target | Dr target SVD | Cr target SVD |
| source→WIP transfer | Cr source inventory + Dr WIP inventory | counterpart rows net |

For the §8 example before Standard Cost:

| GL concern | Debit | Credit |
|---|---:|---:|
| FG inventory | 46 | |
| scrap inventory | 3 | |
| raw-material inventory | | 40 |
| Stock Entry detail expense/clearing, net from base pairs | | 9 |
| Stock Entry detail expense/clearing, additional-cost offset | 9 | |
| operation-cost expense account | | 9 |

The two clearing rows cancel. Net accounting is `Dr inventory 49 / Cr raw inventory 40 / Cr operation
cost 9`. Account mapping may merge rows, but the source amounts remain SLE-derived.

### 11.2 Additional-cost GL

For Manufacture/Repack, each additional-cost account is allocated only to principal FG details,
proportionally to `basic_amount`; quantity is the fallback when total basic amount is zero. The composer
credits the additional cost's expense account and posts the opposite amount to the FG detail expense
account (`stock/doctype/stock_entry/services/gl_composer.py:189-274`). This second pair clears the
imbalance introduced when additional cost made target SVD exceed source SVD.

For non-Standard-Cost Items the opposite leg is expressed as a negative credit and later normalized.
For Standard Cost it is an explicit debit because target SLE value did not absorb the intended added
cost at the document's rate.

### 11.3 Landed-cost adjustment

For target-only details with LCV allocations, the composer credits each LCV expense account and writes
the opposite amount to the detail expense account; inventory itself is still represented by the
revalued SLE (`stock/doctype/stock_entry/services/gl_composer.py:280-327`). As doc 03 explains, LCV
currently rewrites/reposts the stock valuation behind this composer rather than preserving the original
receipt plus an immutable revaluation event.

### 11.4 Standard Cost manufacturing variance

For a Standard Cost principal FG on Manufacture **or Repack**:

```text
standard_value = Σ positive SLE.stock_value_difference for the FG detail
intended_value = Stock Entry Detail.amount
variance       = intended_value - standard_value
```

Positive variance is unfavorable. The composer debits Manufacturing Variance and credits the FG detail
expense account; negative variance reverses those sides
(`stock/doctype/stock_entry/services/gl_composer.py:53-176`).

Example: actual raw + operation allocation intends FG amount 55, while 10 units post to inventory at
standard value 50:

| Account | Debit | Credit |
|---|---:|---:|
| FG inventory, from SLE | 50 | |
| Manufacturing Variance | 5 | |
| raw inventory / operation-cost accounts | | 55 |

The intervening detail expense/clearing rows cancel after the variance and additional-cost pairs. The
important rule is that inventory remains exactly the SLE standard value; the 5 difference is named, not
silently forced into inventory.

> **Invariant M37 — manufacturing stock/GL bridge.** For every conversion and inventory account,
> `Σ GL signed inventory amount = Σ stock valuation value_delta`. Actual-vs-standard, allocation and
> rounding differences post to named variance accounts. Resource/service cost enters inventory only
> through an explicit cost-allocation event and balanced GL source.

---

## 12. Submit, cancel, projections and reservations

### 12.1 Submit order

The common submit path is:

```text
purpose service on_submit
legacy serial/batch → bundle conversion
adjust/update existing reservation entries
release subcontract reservation where applicable
post Stock Ledger Entries
create WIP/FG reservation entries
update subcontract/pick projections
post GL
queue future SLE/GL repost
update project cost and Quality Inspection link
```

(`stock/doctype/stock_entry/stock_entry.py:331-356`). For manufacturing, the first step already
recomputes Job Card and Work Order fields **before** stock evidence posts:

- transfer recomputes Job Card transfer, Job Card Item transfer, adds Work Order additional rows,
  recalculates Work Order quantities/status and dates
  (`stock/doctype/stock_entry/services/material_transfer.py:373-394`);
- Manufacture recomputes Job Card Item consumption/manufactured quantity/operation, then Work Order
  produced/planned/status/required items/dates
  (`stock/doctype/stock_entry/services/manufacturing.py:783-810`);
- Disassemble creates bundle assignments and increments Work Order `disassembled_qty`
  (`stock/doctype/stock_entry/services/disassemble.py:388-515`).

A later exception normally rolls the transaction back, but within the transaction mutable projections
precede the evidence they claim to summarise.

### 12.2 Cancellation order

Cancellation first calls the same purpose update path after docstatus changes, delinks ancillary
objects, cancels WIP/FG reservations, validates Material Consumption cancellation against Work Order
state, cancels inward reservations, and only then reverses SLEs and GL. It subsequently reposts future
valuation and cleans bundles/links (`stock/doctype/stock_entry/stock_entry.py:354-405`). Source/target
SLE order is reversed on cancel so dependent target receipts reverse before source restoration.

### 12.3 Work Order and Job Card projections

Work Order quantities are recomputed from submitted Stock Entries:

```text
produced_qty = Σ finished-item transfer_qty on submitted Manufacture entries
material_transferred_for_manufacturing = Σ normal transfer header fg_completed_qty
additional_transferred_qty = Σ additional transfer header fg_completed_qty
process_loss_qty = Σ Manufacture header process_loss_qty
```

The service compares each aggregate to Work Order quantity plus allowance and then `db_set`s the result
(`manufacturing/doctype/work_order/services/status.py:193-294`). Pick-list/MR transfers whose header
quantity is zero instead use the minimum transferred/required Item fraction times Work Order quantity.
Job-Card transfer mode uses operation completion rather than the Stock Entry header
(`manufacturing/doctype/work_order/services/required_items.py:133-194`).

Required-item transferred/returned/consumed quantities are rebuilt from submitted Stock Entry rows and
written directly to Work Order Items. Consumption sums Manufacture/Material Consumption source rows,
folding alternative Items through `original_item`, and then Bin production reservation is recalculated
(`manufacturing/doctype/work_order/services/required_items.py:30-55`,
`manufacturing/doctype/work_order/services/required_items.py:196-255`). Job Card Item transfer,
consumption and `manufactured_qty` are likewise mutable aggregates over downstream Stock Entries.

### 12.4 Explicit reservations

For a reserving Work Order, Material Transfer may create reservations against the received WIP stock.
Manufacture can reserve FG for a Sales Order, Production Plan subassembly, subcontracting-inward line,
or next Job Card operation. Reservation records retain `from_voucher_no/detail` pointing to the Stock
Entry and are cancelled by those links (`manufacturing/doctype/work_order/services/reservation.py:191-451`).

The reservation mapper collapses Work Order required rows into an Item-code map in places, so duplicate
required rows can lose source-line identity. It is also separate from legacy
`Bin.reserved_qty_for_production`, which the required-item callback recalculates.

> **Invariant M38 — evidence before projection.** Stock, serial/batch and GL events commit atomically;
> Work Order, Job Card, demand, reservation-summary and Bin projections advance from that committed
> event position. A synchronous projector either locks its owner and writes after evidence, or an
> idempotent after-commit job does so. Projection mutation never precedes posting.

---

## 13. Evidence boundary

| Representation | Classification in this implementation |
|---|---|
| Submitted Stock Entry + Detail | strongest conversion command/evidence; cancelled rather than edited in ordinary flow, but LCV/repost and allowed framework paths can recalculate fields |
| SLE event columns (`actual_qty`, voucher/detail, warehouses, bundle) | posting evidence, although cancellation flags/reversal handling remain framework-managed |
| SLE running qty/value/rate/queue/SVD | mutable derived projection stored on the evidence row and rewritten by repost |
| GL Entry | accounting evidence in business meaning, but compare/repost can delete and recreate physical rows |
| Serial and Batch Bundle/Entry | tracked-unit allocation evidence, with cancellation and rebuilt transfer/disassembly packages |
| Stock Entry Additional Cost | cost-allocation input on the posting command; operation/corrective source totals come from mutable upstream projections |
| Work Order Item transfer/consume/return | mutable projection over submitted Stock Entry rows |
| Work Order produced/loss/disassembled/status/dates/cost | mutable projection |
| Job Card Item transfer/consumption/manufactured quantity | mutable projection |
| Stock Reservation Entry transferred/consumed/status | durable allocation record with mutable progress; overlaps legacy Bin reservation |
| Bin actual/value | stock cache from SLE projection |
| Bin WIP/production/planned/reserved/projected fields | mutable planning/allocation cache |

The current implementation's best audit chain is Stock Entry Detail → SLE/SABB → GL. It is not fully
append-only because valuation repost mutates SLE derived state and replaces GL; cancellation changes
state and emits/reuses reversal mechanics rather than preserving a universal event/reversal table.

> **Invariant M39 — immutable production posting.** A production command, its stock moves, tracked-unit
> allocations, cost-source allocations and balanced GL journal are append-only facts. Corrections write
> linked reversal/supersession facts. Running valuation, Work Order progress, WIP ownership, operation
> completion and account balances are versioned rebuildable projections.

---

## 14. Defects and race inventory

### 14.1 Aggregate checks are not allocations

No Work Order/Job Card owner lock was found around these read-check-write paths:

- remaining required quantity → Material Transfer insert;
- transferred WIP pool → consumption/Manufacture rows;
- produced quantity/allowance → Manufacture submit;
- completed Job Card secondary quantity → secondary output posting;
- source Manufacture availability → Disassemble submit;
- Work Order `disassembled_qty` increment;
- pending FG/reservation quantity → reservation creation.

Two transactions can both read the same residual and each pass. The stock ledger lock protects each
item/warehouse running balance, not Work Order allocation ceilings or coproduct ownership.

### 14.2 Partial consumption suppresses all Manufacture inputs

`raw_materials_already_consumed()` is existence-based. One submitted partial Material Consumption entry
causes a later Manufacture preview to omit every raw material. Unless “get RM cost from consumption
entry” is also enabled and workflow discipline ensures completeness, output can be posted with a
partial physical/cost basis.

### 14.3 Transfer-pool direct indexing

When subtracting prior Manufacture consumption, the code directly indexes the transfer pool by
`(item_code, source warehouse)`. A consumed row not represented in transfer history can fail instead of
producing a controlled validation explaining the missing allocation
(`stock/doctype/stock_entry/services/manufacturing.py:650-673`).

### 14.4 Zero-denominator edges

Job Card secondary proration divides by pending completed-card output with no explicit zero guard
(`stock/doctype/stock_entry/services/manufacturing.py:735-749`). Corrective cost divides by
`minimum completed operation qty - produced_qty` with no zero guard
(`manufacturing/doctype/bom/services/operations_cost.py:201-216`). The unconsumed-BOM branch, by
contrast, silently substitutes denominator 1, which avoids a crash but can create a policy-free
quantity.

### 14.5 Item-code aggregation erases allocation identity

Transfer, required-item and reservation paths frequently aggregate by Item code. Duplicate Work Order
required lines can each receive the same aggregate or one row can win a dictionary assignment. Job Card
secondary outputs group by Item/type and use `MAX()` for the BOM link. Work Order-wide Disassemble
uses Item-only grouping and `MAX()` for role/warehouse/UOM. These are not safe when the same Item appears
in multiple operations, warehouses, source allocations or output roles.

### 14.6 Process loss is quantity policy, not evidence

The Stock Entry stores one loss scalar and reduces FG quantity. It does not identify where loss
occurred, which material/output lot it affected, whether it was normal or abnormal, or which account
should bear it. Job Card and Work Order loss are mutable upstream aggregates.

### 14.7 Rework is cost-only at the posting boundary

Corrective Job Cards contain execution time, but they do not create a rework material/output ledger.
When enabled, their cost is folded into FG additional cost. Any rework material movement must be an
ordinary Stock Entry, and there is no enforced immutable link from that movement to the corrective Job
Card/reason/output lot. The repository contains a cost-of-poor-quality report over corrective Job Cards,
not a Rework Ledger (`manufacturing/report/cost_of_poor_quality_report/cost_of_poor_quality_report.py:12-43`).

### 14.8 Secondary cost-allocation branch is unreachable in the ordinary case

`_set_incoming_item_rate()` tests `secondary_item_type` only inside the `d.is_finished_item` branch and
only after `if self.bom_no`. A normal Manufacture secondary row is not the principal finished item and
has a BOM-backed parent, so its configured `BOM Secondary Item.cost_allocation_per` does not drive the
shown branch. It falls back to the target Item valuation rate, while only legacy scrap is subtracted
from principal FG cost. The stored allocation percentage therefore does not establish a complete,
deterministic coproduct allocation in this path.

> **Invariant M40 — serializable production allocation.** Remaining Work Order material/output,
> conversion inputs, secondary-output entitlement, source-conversion reversal quantity, reservation
> quantity and corrective-cost capacity are allocations with unique source identities and non-negative
> residual constraints. Validation and insert occur under one owner lock or serializable transaction.

---

## 15. Target decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| One Stock Entry conversion with source and target lines | **Adopt concept** | immutable `production_conversion` command producing typed `stock_move` lines |
| Purpose services | **Adopt policy split** | strategies return proposed facts; one posting service owns transaction and invariants |
| WIP as ordinary warehouse inventory | **Adopt** | ordinary stock projection plus explicit Work Order/operation allocation |
| Source-before-target valuation | **Adopt** | dependency-ordered projection under deterministic stream locks |
| SLE `stock_value_difference` driving GL | **Adopt** | GL inventory amount reads immutable projection `value_delta` |
| Work Order/BOM backflush | **Adopt as named policy** | snapshotted allocation policy with exact source revision and event position |
| Transfer-based backflush | **Adopt intent** | consume exact transfer-allocation residuals, not Item/warehouse aggregates |
| “Any consumption exists” suppressing all Manufacture raw rows | **Reject** | quantity-complete input allocation required per output conversion |
| Additional material appended to submitted Work Order | **Reject** | authorised change/allocation event referencing original released requirement |
| Principal FG = completed minus process loss | **Adopt formula conditionally** | explicit accepted-output and loss events with policy/reason/operation |
| Scrap/by-product as ordinary incoming stock | **Adopt** | typed output move using the same stock valuation projection |
| Legacy scrap special cost subtraction | **Migrate explicitly** | one versioned coproduct allocation policy; no hidden legacy flag branch |
| Secondary output grouping by Item/type | **Reject identity loss** | output entitlement keyed by BOM/operation/execution-lot allocation ID |
| Semi-FG through ordinary Manufacture | **Adopt** | output move allocated to next operation; tracked-unit continuity edge |
| Stock Entry Additional Cost | **Adopt concept** | immutable `conversion_cost_allocation` linked to resource/service GL source |
| Mutable Work Order actual/corrective costs as posting input | **Reject** | costed usage events and snapshotted allocation rows |
| Corrective Job Card | **Adopt execution concept** | authorised rework operation/event with reason, inputs, outputs and cost sources |
| No separate rework ledger | **Reject gap** | no isolated accounting ledger, but explicit rework event/allocation graph in the common production ledger |
| Process loss only as a header scalar | **Reject** | typed normal/abnormal loss event and explicit valuation/account policy |
| Multiple FG manual rates in Repack | **Replace** | deterministic allocation weights with residual rule and variance |
| Exact source-entry Disassemble | **Adopt** | reversal allocations reference original conversion line/lot |
| Work Order-wide averaged Disassemble | **Keep only as explicit transformation** | named recovery policy; never labelled exact reversal |
| Work Order-created serials/batches | **Adopt optional preallocation** | unique tracked-unit allocation under lock |
| Source/target bundle reconstruction | **Replace mutable packaging** | immutable serial/batch allocation edges and reversal links |
| Standard Cost manufacturing variance | **Adopt exactly** | inventory at standard `value_delta`; actual-standard difference to named variance |
| Additional-cost and LCV GL pairs | **Adopt accounting principle** | signed balanced journal generated from cost allocation + stock projection |
| Purpose callback before SLE/GL | **Reject ordering** | evidence first atomically; projections after evidence position advances |
| Work Order/Job Card/Bin `db_set` roll-ups | **Reject as facts** | idempotent rebuildable projections keyed by event sequence |
| Unlocked aggregate ceilings | **Reject** | owner lock plus allocation constraints/idempotency key |

The eleven invariants added here are **M30–M40**: conversion identity; WIP conservation; consumption
completeness; yield/coproduct identity; reversal provenance; one cost-allocation equation; tracked-unit
continuity; the manufacturing stock/GL bridge; evidence before projection; immutable production posting;
and serializable production allocation. Together with M13–M20 from doc 35, they make the boundary
explicit: Work Order and Job Card authorise and record execution, but only append-only conversion,
stock, tracked-unit, cost and GL facts change inventory and the books.

---

Cross-references: doc 02 (valuation and repost), doc 03 (stock→GL invariant and LCV), doc 16
(reservation/Warehouse/Bin), doc 22 (locking/jobs), doc 27 (Stock Entry controller and Standard Cost),
doc 33 (BOM cost/allocation), doc 34 (operation resource cost), doc 35 (Work Order/Job Card execution),
doc 36 (production planning/MPS), and `docs/design/FINAL-SCHEMA.md` (append-only `stock_move`, GL and
projection principles). Next: doc 38, subcontracting execution and accounting.
