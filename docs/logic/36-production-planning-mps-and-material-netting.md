# 36 — Production Planning, MPS and Material Netting

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This document follows docs 33–35 from BOM/route definitions and shop-floor execution back to the
planning layer. It traces `Production Plan`, its seven children and split services; demand imported from
Sales Orders and Manufacture Material Requests; subassembly and raw-material explosion; projected-stock,
safety-stock, MOQ, UOM and warehouse-transfer netting; creation of Material Requests, Work Orders and
subcontract Purchase Orders; reservation/Bin/status roll-ups; and the newer Sales Forecast, Master
Production Schedule and Material Requirements Planning report.

The two planning paths are materially different. Production Plan is a submitted allocation-like document
whose mutable children drive downstream drafts and Bin projections. MPS is a draft/report prototype: it
combines selected demand into dated item rows, the report recalculates a point-in-time proposal, and a
separate command inserts Purchase Orders and Work Orders from caller-supplied report rows. Its controller
contains an `on_submit` enqueue for `make_mrp`, but the DocType is not submittable and no `make_mrp`
implementation or MRP Log DocType exists in this source revision. Sales Forecast generation is similarly
skeletal: every selected item gets demand `1.0` per period, mapping creates only an unsaved MPS header,
and the advertised `MPS Generated` status is never written.

The shared architectural problem is that neither path creates one immutable, versioned planning run.
Demand, BOMs, item policies, Bin projections and open supply are reread at different times; previews are
saved as editable children or not saved at all; downstream creation has no proposal identity or
idempotency key; and most availability/allocation checks are unlocked. The target boundary is therefore
a planning snapshot with explicit demand/supply allocations and a separately authorised release.

---

## 1. Production Plan data model — one parent and seven passive children

`Production Plan` is a submittable planning document. Its meaningful parent state is:

| Concern | Meaningful fields |
|---|---|
| Identity and scope | company, posting date, project, item/customer/warehouse filters and transaction/delivery date range |
| Demand sources | `get_items_from`, Sales Order status, `sales_orders`, `material_requests` |
| Planned output | `po_items`, hidden `prod_plan_references`, total planned/produced quantity |
| Subassemblies | `sub_assembly_items`, warehouse, combine and skip-available policies |
| Material planning | non-stock/subcontract/safety/MOQ flags, projected-stock flag, availability group/target/source warehouses, `mr_items` |
| Allocation and lifecycle | `reserve_stock`, status and amended-from |

The generated parent types enumerate those fields and all seven child relations
(`manufacturing/doctype/production_plan/production_plan.py:52-123`). The children are data-only
`Document` classes:

- **`Production Plan Item`** stores item/BOM, explosion flag, planned/pending/ordered/produced quantities,
  target warehouse/start date, SO/MR provenance, product-bundle item and temporary/reference identities
  (`manufacturing/doctype/production_plan_item/production_plan_item.py:8-39`).
- **`Production Plan Sub Assembly Item`** stores parent/subassembly/BOM/level, gross `required_qty`,
  shortage `qty`, actual/projected stock, `In House`/`Subcontract`/`Material Request` classification,
  supplier/PO, output provenance, ordered/received/WO-produced quantities, reservation and warehouse/date
  (`manufacturing/doctype/production_plan_sub_assembly_item/production_plan_sub_assembly_item.py:9-47`).
- **`Material Request Plan Item`** stores component/BOM provenance, request type, purchase UOM and
  conversion, gross and net quantities, requested/ordered/reserved quantities, actual/projected stock,
  safety/MOQ, source/target warehouse and SO link
  (`manufacturing/doctype/material_request_plan_item/material_request_plan_item.py:8-49`).
- **`Production Plan Sales Order`** and **`Production Plan Material Request`** are selected-source headers;
  **`Production Plan Item Reference`** stores hidden combined-SO line allocations; and
  **`Production Plan Material Request Warehouse`** stores selectable source warehouses. None has domain
  methods; the parent and services own all behavior.

This is not a frozen planning snapshot. The rows carry copied quantities but no demand/BOM/policy
revision, stock-as-of position, planning-run identity or calculation fingerprint. They remain editable,
and later Work Order, Material Request, Purchase Order/Receipt and reservation callbacks directly rewrite
their counters.

> **Invariant M21 — immutable planning snapshot.** A planning run names an as-of instant and immutable
> revisions of demand, BOM, item sourcing, lead-time, lot-sizing, calendar and warehouse policies. Gross
> requirements, available supply and every netting allocation retain source identities and calculation
> inputs. Editing assumptions creates a new run; it never silently rewrites a released plan.

---

## 2. Construction and validation — source demand is copied, not allocated

### 2.1 Sales Order demand

The open-order query requires submitted, non-Stopped/non-Closed Sales Orders in the company and at least
one line with `qty > production_plan_qty`; optional date, delivery-date, customer, project, status and
item filters are applied, and a direct or packed item needs an active BOM
(`manufacturing/doctype/production_plan/services/planning_queries.py:107-166`). Fetching only populates
the selected SO header table.

Finished-good lines are then read when:

```text
(stock_qty - stock_reserved_qty) > work_order_qty
pending_qty = (stock_qty - stock_reserved_qty)
              - max(work_order_qty, delivered_qty × conversion_factor, 0)
```

(`manufacturing/doctype/production_plan/services/sales_order_planning.py:140-190`,
`manufacturing/doctype/production_plan/services/sales_order_planning.py:285-320`). Packed-item demand is:

```text
if work_order_qty > delivered_qty:
    pending = (SO qty - work_order_qty) × packed qty / SO qty
else:
    pending = (SO qty - delivered_qty) × packed qty / SO qty
```

(`manufacturing/doctype/production_plan/services/sales_order_planning.py:322-349`). Rows with zero
pending quantity or no resolvable BOM are silently omitted. The resulting plan row copies its BOM,
warehouse, stock UOM, planned/pending quantity, start time and source identities
(`manufacturing/doctype/production_plan/services/sales_order_planning.py:216-267`).

When `combine_items` is enabled, references are grouped only by BOM. The code nevertheless appends an
output row for every input and later writes the same BOM aggregate onto every matching row, while the
hidden references point at only one source row (`manufacturing/doctype/production_plan/services/sales_order_planning.py:228-283`). Multiple inputs sharing a BOM can therefore duplicate the combined total.

### 2.2 Manufacture Material Request demand

Pending source requests must be submitted Manufacture Material Requests, not Stopped, in the same
company, with a line where `qty > ordered_qty` and an active BOM
(`manufacturing/doctype/production_plan/services/sales_order_planning.py:42-83`). Imported stock demand is:

```text
pending_qty = (Material Request Item.qty - ordered_qty) × conversion_factor
```

and is copied with MR parent/line provenance
(`manufacturing/doctype/production_plan/services/sales_order_planning.py:192-214`,
`manufacturing/doctype/production_plan/services/sales_order_planning.py:351-381`). Production Plan submit
does not reserve that source gap; only a later submitted Work Order changes the MR's ordered projection.
Two plans can therefore copy the same pending request.

### 2.3 Validation pipeline and holes

Validation initialises pending quantities, totals planned quantity, derives status, repairs temporary
child identities, enforces whole-number stock UOMs, revalidates selected SOs, clears invalid transfer
sources, validates the raw-material warehouse hierarchy and applies automatic reservation
(`manufacturing/doctype/production_plan/production_plan.py:134-179`). The helper that validates each BOM
against its item and rejects zero planned quantity exists, but `validate()` never calls it
(`manufacturing/doctype/production_plan/production_plan.py:205-220`).

The independent-row initialiser is also broader than its comment:

```text
if not sales_order OR not material_request:
    pending_qty = planned_qty
```

A row normally has only one source, so almost every draft row is reset
(`manufacturing/doctype/production_plan/production_plan.py:198-204`). Client-created temporary output IDs
are translated to persisted child names so subassembly rows retain their parent-output reference
(`manufacturing/doctype/production_plan/production_plan.py:221-242`).

SO revalidation asks only whether each selected order still has any eligible item. It neither validates
each copied plan line nor locks the source order/lines between availability check and submit. Concurrent
plans can both pass, and their later aggregate updates can last-write a stale `production_plan_qty`.

> **Invariant M22 — atomic demand allocation.** Plan demand is an allocation against a stable source
> line and dated requirement, keyed uniquely by planning run and source. Remaining demand is checked and
> allocated under the source-owner lock. Combined requirements preserve item, warehouse, due date,
> customer/project and source-line dimensions; presentation grouping never changes quantity.

---

## 3. Subassembly discovery and classification

`SubAssemblyService` clears existing rows and recursively traverses each output BOM. A BOM configured to
track semi-finished goods is skipped with a message; projected-stock subtraction requires a subassembly
warehouse (`manufacturing/doctype/production_plan/services/sub_assembly.py:17-78`). Only expandable BOM
children participate. For each child:

```text
required_qty = child.stock_qty / child.parent_bom_qty × parent_to_produce_qty
```

(`manufacturing/doctype/production_plan/services/sub_assembly_queries.py:17-84`). `required_qty` remains
gross demand; `stock_qty`, later copied to `qty`, is the residual after projected availability.

Classification is caller override, otherwise `Subcontract` when the Item is subcontracted and `In House`
otherwise. A non-group configured warehouse becomes `fg_warehouse`; default suppliers come from Item
Default (`manufacturing/doctype/production_plan/services/sub_assembly.py:86-138`). Combination uses:

```text
(production_item, fg_warehouse, bom_no, type_of_manufacturing)
```

and sums shortage quantities while retaining the deepest BOM level
(`manufacturing/doctype/production_plan/services/sub_assembly.py:140-161`). It discards per-order/date
identity when combined.

Projected-stock consumption is unreliable across repeated branches. `_consume_projected_qty` resets
`original_projected_qty` from the unchanged Bin projection on every invocation; a fully covered first
occurrence is not recorded as consumed, allowing later branches to reuse it. For group warehouses, the
displayed actual/projected quantities are taken from only the first Bin row
(`manufacturing/doctype/production_plan/services/sub_assembly_queries.py:86-140`).

> **Ours.** Explosion returns a graph keyed by immutable BOM line and requirement source. A separate
> allocation pass consumes each supply lot/projection once across all demands in deterministic
> priority order. Manufacture, buy, transfer and subcontract are explicit sourcing decisions with
> effective-dated policy and approval, not mutable labels on a child row.

---

## 4. Raw-material explosion — three algorithms

Material planning is a whitelisted preview over a serialized document. It requires only Production Plan
read permission, clears the local `mr_items`, collects output rows plus subassemblies classified
`Material Request`, explodes them and returns dictionaries; it does not save or re-run automatically on
plan validation/submit (`manufacturing/doctype/production_plan/services/material_request.py:141-230`).

There are three paths:

1. **Flattened explosion.** When exploded and subcontracted items are included, `BOM Explosion Item`
   produces leaf demand:

   ```text
   component qty = Σ(explosion.stock_qty / BOM.quantity) × planned_qty
   ```

   grouped by item and stock UOM and excluding subassembly rows
   (`manufacturing/doctype/production_plan/services/bom_explosion.py:12-70`).
2. **Recursive direct BOM.** Otherwise each level computes:

   ```text
   component qty = parent_qty × Σ(BOM Item.stock_qty / BOM.quantity) × planned_qty
   ```

   A child is emitted when explosion is disabled or it has no child BOM; eligible manufacture/purchase,
   included subcontract and phantom children recurse. Phantom rows are removed from final demand
   (`manufacturing/doctype/production_plan/services/bom_explosion.py:75-190`).
3. **Selected residual subassemblies.** When available subassemblies are skipped, recursion follows only
   retained `(item_code, bom_no)` shortage rows, while phantoms always recurse
   (`manufacturing/doctype/production_plan/services/sub_assembly_queries.py:143-252`).

If any subassembly rows exist, a source row that says not to explode is forcibly changed to exploded
before dispatch (`manufacturing/doctype/production_plan/services/material_request.py:239-253`). Raw
materials are accumulated by Sales Order and item, so safety stock and MOQ can be applied independently
to each SO partition rather than globally (`manufacturing/doctype/production_plan/services/material_request.py:354-369`).

The recursive functions have no local active-BOM/visited set. Normal BOM validation should reject cycles,
but imported or corrupt cyclic references can recurse until Python's limit. The same missing guard recurs
in MPS lead-time and report explosion (§10).

> **Invariant M23 — one cycle-safe explosion.** BOM explosion is one pure, versioned graph function used
> by costing, Production Plan and MRP. It normalises every line by BOM output quantity, preserves phantom
> and subassembly semantics, detects an active-path cycle with the complete path, and returns quantities
> by source requirement and BOM-line identity before any netting or grouping.

---

## 5. Material netting — projected stock, safety, MOQ and UOM

### 5.1 Bin scope and the net formula

The Bin query returns projected, actual, ordered, reserved-for-production and planned quantities for one
warehouse or all descendants of a group (`manufacturing/doctype/production_plan/services/planning_queries.py:27-76`). Material planning sums the descendant rows. `actual_qty` is display data; subtraction uses
persisted `projected_qty`, whose inventory formula is:

```text
projected = actual + ordered + indented + planned
            - reserved_sales - reserved_production
            - reserved_subcontract - reserved_production_plan
```

Thus existing requests and reservations enter indirectly through the Bin cache rather than as traceable
supply/demand allocations.

For each component, safety stock is included only when selected. Net requirement is
(`manufacturing/doctype/production_plan/services/material_request.py:489-536`):

```text
if projected-stock consideration is disabled OR projected_qty < 0:
    required = MOQ_adjust(gross_BOM_qty + safety_stock)
else:
    available = projected_qty - already_consumed[(item, availability_scope)]
    required = MOQ_adjust(max(0, gross_BOM_qty - (available - safety_stock)))
    already_consumed += gross_BOM_qty - required
```

A negative projection is not added as shortage; it causes projected stock to be ignored. MOQ is applied
before consumed availability is updated. If MOQ raises required above gross, `gross - required` becomes
negative and increases apparent availability for later rows. Safety is likewise applied per SO/item
partition.

Availability scope is the raw-material group warehouse, else target warehouse, else the component's BOM
source/default. Target is the concrete receiving warehouse. Both local variables are initialised outside
the component loops and filled with `scope = scope or fallback`, so without a plan-level warehouse the
first component's fallback can leak into later components
(`manufacturing/doctype/production_plan/services/material_request.py:374-426`).

### 5.2 UOM conversion and whole-number behavior

Purchase-UOM factors come from the item, variant template or stock-UOM conversion fallback
(`manufacturing/doctype/production_plan/services/planning_queries.py:15-27`). The apparent conversion in
`_adjust_required_qty_for_uom` is indented below `frappe.throw` and therefore unreachable. It rounds the
stock-space requirement with the purchase UOM's whole-number rule, then the output row divides by the
conversion factor:

```text
output quantity = adjusted_required_stock_qty / purchase_conversion_factor
```

(`manufacturing/doctype/production_plan/services/material_request.py:525-583`). Five stock units with a
factor of ten can therefore become `0.5` of a purchase UOM even when that UOM must be whole. Download mode
can suppress the missing-factor exception and fall back to factor one.

### 5.3 Warehouse-transfer split

Selected source groups expand to leaf warehouses and normally exclude the target. Pick List availability
is queried without validation/locking. Available quantities become one `Material Transfer` row per source
in stock UOM with conversion factor one; the residual becomes a Purchase row
(`manufacturing/doctype/production_plan/services/material_request.py:586-655`). MOQ can be applied once
before splitting and again to the purchase remainder, so transfer plus purchase can exceed the first
net requirement. The location read creates no reservation; concurrent planners can select the same stock.

> **Invariant M24 — dimensionally correct, allocative netting.** All gross requirements and supply are
> fixed-decimal stock-UOM quantities at item+warehouse+date+lot identity. Netting allocates on-hand,
> scheduled receipts and reservations once, then applies safety stock and lot-sizing exactly once at the
> configured aggregation boundary. Conversion to order UOM occurs after lot sizing with an explicit
> rounding rule and a stored stock-UOM equivalent. Negative projected stock is represented as demand,
> not discarded by a branch.

---

## 6. Downstream Material Requests

`make_material_request` validates subcontract classifications, skips rows exactly equal to their
`requested_qty`, groups documents by Sales Order and request type, and writes:

```text
Material Request Item.qty = plan quantity - requested_qty
```

with source/target warehouse, schedule, SO/project and Production Plan child identity. It saves with
`ignore_permissions=1` and optionally submits according to a transient client flag
(`manufacturing/doctype/production_plan/services/material_request.py:39-136`). Validation still runs;
permission does not.

The Material Request validates each referenced child against `quantity - requested_qty`, but the query is
unlocked (`stock/doctype/material_request/material_request.py:237-258`). Submit first updates each plan
child by read-add-write, then updates Bin indented quantity; cancel subtracts and recomputes plan status
(`stock/doctype/material_request/material_request.py:264-325`,
`stock/doctype/material_request/material_request.py:427-463`). Draft requests do not increment the plan,
so repeated commands can create duplicates. Concurrent submissions can both pass the ceiling and either
over-request or lose one increment.

> **Ours.** Releasing a buy/transfer request consumes a unique planning-proposal allocation under lock.
> Draft generation is idempotent by `(planning_run, proposal_line, revision)`; submit does not maintain a
> read-add-write counter. Requested quantity is an aggregate over surviving released allocations.

---

## 7. Work Orders and subcontract Purchase Orders

Creation order is finished-good Work Orders, in-house subassembly Work Orders while collecting
subcontract rows, then subcontract Purchase Orders
(`manufacturing/doctype/production_plan/services/work_order_planning.py:100-145`). Finished-good quantity
is normally `planned_qty - ordered_qty`; a plan sourced from Material Request instead uses full
`planned_qty`. Subassembly quantity is `qty - ordered_qty`. If explicit subassemblies exist, finished-good
Work Orders force multi-level BOM off
(`manufacturing/doctype/production_plan/services/work_order_planning.py:31-98`,
`manufacturing/doctype/production_plan/services/work_order_planning.py:146-165`).

Each Work Order has operations and required items prebuilt, then is inserted as a draft with both
`ignore_mandatory` and `ignore_validate`. `OverProductionError` is caught and discarded without a message
(`manufacturing/doctype/production_plan/services/work_order_planning.py:216-241`). This bypasses the Work
Order's company/warehouse/date/quantity/sequence/reservation validator and its Production Plan ceiling;
the catch is normally unreachable precisely because validation is skipped. A later submit can fail.
Prebuilding children is not validation.

Subcontract rows are grouped by supplier. Fully received rows are removed, partial `received_qty` is
subtracted, and a draft subcontract Purchase Order is populated with finished-good/BOM/plan/SO links and
service items. It too inserts with mandatory and validation bypasses
(`manufacturing/doctype/production_plan/services/work_order_planning.py:164-214`,
`manufacturing/doctype/production_plan/services/work_order_planning.py:244-256`). Missing supplier,
minimum quantity and other normal gates can survive initial insertion.

When downstream documents are submitted, projections change:

- Work Order submit/cancel recomputes Production Plan child `ordered_qty = Σ submitted Work Order.qty`
  and writes plan status (`manufacturing/doctype/work_order/services/status.py:372-406`).
- Purchase Order submit installs the Production Plan status-updater before previous-document and Bin
  updates, budget/authority checks and subcontract-order creation
  (`buying/doctype/purchase_order/purchase_order.py:369-455`).
- Purchase Receipt later computes subcontract finished-good progress as:

  ```text
  received_qty = Σ(PO Item.received_qty / (PO Item.qty / PO Item.fg_item_qty))
  ```

  and directly writes the subassembly row
  (`stock/doctype/purchase_receipt/purchase_receipt.py:385-429`).

Counters do not change when draft WOs/POs are inserted, so repeated or concurrent creation can duplicate
drafts. There is no command idempotency key.

> **Invariant M25 — validated, idempotent release.** Every Work Order, transfer request, purchase request
> and subcontract order is created through its ordinary validator from one authorised proposal line.
> A unique release key makes retries return the existing document. No caller can set general validation
> bypass flags, and an over-allocation exception is surfaced with its source demand and residual.

---

## 8. Production Plan submit, status, cancellation and reservations

Submit writes, in order: Bin Production Plan projections; Sales Order `production_plan_qty`; raw-material
to-subassembly references; then explicit Stock Reservation Entries when enabled. Cancel writes status
Cancelled, deletes linked draft Work Orders, updates Bins and Sales Orders, then releases reservations
(`manufacturing/doctype/production_plan/production_plan.py:243-304`). Draft Material Requests and draft
subcontract Purchase Orders are not similarly deleted. Normal request rollback protects an escaped
failure, but the ordering exposes mutable intermediate state to in-transaction hooks.

SO planned quantity is a recomputed sum over submitted plan rows, then directly written per SO line.
Bin updates lock one Bin at a time and refresh raw-material and in-house-subassembly reservation
projections (`manufacturing/doctype/production_plan/production_plan.py:306-359`). Child order determines
lock order, so overlapping plans can deadlock; aggregate source rows are not themselves locked.

Status starts from docstatus, becomes In Process when any production exists and Completed when every
output is within `0.000001` of plan and all active submitted WOs are Completed. Otherwise requested
material gives Material Requested and any ordered output/subassembly overrides it to In Process. Close
and reopen are direct status writes plus optional Bin refresh
(`manufacturing/doctype/production_plan/production_plan.py:360-397`,
`manufacturing/doctype/production_plan/services/sub_assembly.py:163-181`). An empty active-WO set makes
`all(...)` true, so produced output alone can complete a plan.

Legacy Bin reservation uses gross BOM requirement, not net request quantity:

```text
raw-material reserved = Σ open plan required_bom_qty
                        - Work Order reserved_for_production, floored at zero
subassembly reserved = Σ((qty if qty > 0 else required_qty) - wo_produced_qty)
```

(`manufacturing/doctype/production_plan/services/reservation.py:27-113`). It is refreshed on plan
submit/cancel regardless of the explicit `reserve_stock` flag.

Explicit SRE reservation intends to reserve `sub_assembly_items.required_qty` at `fg_warehouse` and
`mr_items.required_bom_qty` at `warehouse`
(`manufacturing/doctype/production_plan/services/reservation.py:14-25`,
`manufacturing/doctype/production_plan/services/reservation.py:114-176`). However, `StockReservation`
places the Production Plan configuration branch inside `if doctype == "Work Order"`, making it
unreachable for a Production Plan. Generic `items/stock_qty/warehouse` defaults remain
(`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:1104-1130`). Even if fixed, available
quantity is stock balance minus active SRE remainder with no lock
(`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:1262-1290`).

> **Invariant M26 — one reservation and projection model.** Planning allocations, released production
> reservations and physical stock reservations are distinct typed stages in one ledger, with atomic
> transitions and no parallel Bin truth. Projections are rebuilt after evidence commits, lock keys in a
> deterministic order, carry source event position and can be reconciled from allocation rows.

---

## 9. Sales Forecast — a manual placeholder, not forecasting

Sales Forecast stores company, parent warehouse, start date, weekly/monthly frequency, number of periods,
selected items and generated item/date/UOM/demand rows
(`manufacturing/doctype/sales_forecast/sales_forecast.py:10-31`,
`manufacturing/doctype/sales_forecast_item/sales_forecast_item.py:8-28`). It has no customer or territory
dimension.

Generation clears output rows and, for every selected item and period, appends:

```text
monthly delivery date = from_date + (index + 1) months
weekly delivery date  = from_date + (index + 1) weeks
demand_qty             = 1.0
```

(`manufacturing/doctype/sales_forecast/sales_forecast.py:37-66`). It reads item name/UOM, does not copy a
row warehouse, does not use history and does not save. Persistence depends on a later client save.

Mapping a submitted forecast returns an unsaved MPS with only forecast identity and `from_date`; no
forecast children are copied and no source status is changed
(`manufacturing/doctype/sales_forecast/sales_forecast.py:69-91`). `on_discard` alone writes Cancelled.
Repository search found no writer for the advertised `MPS Generated` status.

The MRP report later reinterprets each monthly point as equal demand over every calendar day in that
month and each weekly point as equal demand over seven days starting at its date:

```text
monthly daily qty = forecast qty / days_in_month
weekly daily qty  = forecast qty / 7
```

(`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:1145-1277`). The generated date is therefore both a future point and a period label, with ambiguous
semantics.

> **Ours.** A forecast series has model/version, dimensions, source history, bucket start/end, quantity,
> confidence and approval. Manual forecasts are explicit manual inputs, not hard-coded unit demand.
> Forecast-to-actual consumption occurs within a named time fence and dimension set, preserving both
> original series and consumption allocations.

---

## 10. Master Production Schedule — aggregation, schedules and lead time

### 10.1 Model and actual demand

MPS stores company/date range, parent warehouse, optional Sales Forecast, selected item filters, selected
SO/MR headers and output items. Each item stores item/BOM/UOM/warehouse, delivery date, planned quantity,
cumulative lead time and release date
(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:10-42`,
`manufacturing/doctype/master_production_schedule_item/master_production_schedule_item.py:9-31`).

`get_actual_demand` clears items, reads selected SO and MR demand, aggregates, enriches item/BOM/lead-time
data, appends rows and saves only when the MPS already exists
(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:45-60`). New documents
remain in memory.

MR demand uses full `stock_qty` and schedule date from selected request lines, with date bounds but no
parent docstatus/status recheck (`manufacturing/doctype/master_production_schedule/master_production_schedule.py:170-199`). SO demand uses submitted item rows. A line with any standalone Delivery Schedule
rows is wholly replaced by those rows; the schedule query has a lower date bound but no upper bound and
no parent status join (`manufacturing/doctype/master_production_schedule/master_production_schedule.py:201-266`). Delivery schedules themselves are saved one by one with ignored permissions, stale rows are
deleted, the first input date—not a sorted minimum—is copied to the SO line, and the SO saves last
(`selling/doctype/sales_order/services/delivery_schedule.py:22-94`). Concurrent schedule replacements
are last-writer/delete races.

Aggregation is:

```text
MPS demand[(item_code, delivery_date)] = Σ source.stock_qty
```

across SO lines, schedules and MRs (`manufacturing/doctype/master_production_schedule/master_production_schedule.py:268-289`). Warehouse, source, customer and project are not in the key; territory never enters.
The aggregate also fails to copy the source warehouse, so output falls back to parent warehouse. UOM is
first-writer without a compatibility check.

### 10.2 Cumulative lead time and release date

Item lead time is:

```text
item days = manufacturing_time_in_mins / 1440
            + purchase_time + buffer_time
```

(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:449-466`). Recursive BOM
lead time then **adds every child branch**:

```text
L(item) = L_item + Σ L(each BOM-bearing child) + Σ L(each leaf child)
release_date = delivery_date - ceil(L(item)) calendar days
```

(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:115-162`,
`manufacturing/doctype/master_production_schedule/master_production_schedule.py:291-301`). Parallel
branches should ordinarily contribute their critical-path maximum, not their sum, subject to capacity and
calendar constraints. There is no active-path cycle guard, so corrupt cyclic BOMs recurse indefinitely.
Calendar days ignore holidays and resource calendars.

Validation recomputes `to_date` from MPS and linked forecast children and checks company equality. The
forecast child query filters by parent but not `parentfield`, even though selector and generated rows
reuse the same child DocType (`manufacturing/doctype/master_production_schedule/master_production_schedule.py:62-106`). Demand queries use the old `to_date` before the final save recomputes it.

> **Invariant M27 — dimensioned demand and feasible dates.** MPS demand is keyed by item, warehouse,
> requirement date, demand class and source allocation; UOM is canonical. Release dates come from a
> cycle-safe precedence DAG, working calendars, transfer/purchase/manufacture lead-time definitions and
> finite-capacity policy. Parallel independent paths use the longest feasible path, never an unexplained
> sum of all branches.

---

## 11. MRP report — the effective MPS engine

The report, not the MPS controller, performs useful MRP. It reads MPS rows, adds linked forecast,
recursively explodes BOMs, loads Bin/open WO/PO/SO supply and mutates in-memory pools in delivery-date
order (`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:37-62`). MPS selection requires the entire MPS range to be contained by the report range and has no
MPS docstatus filter (`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:822-862`).

Forecast is matched to MPS only on exact `(item, day)` after daily spreading. Finished-good demand is:

```text
demand = max(actual MPS planned qty, same-day forecast qty)
planned = demand + ad-hoc unselected Sales Order qty
```

(`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:203-232`,
`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:433-451`). Actual demand on another day in the same forecast week/month does not consume that bucket, so
both can survive.

For each dated requirement, netting consumes in-hand stock, eligible open POs and WOs, then adds safety
stock (`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:493-572`). These are mutable in-memory pools, so earlier dates consume first. Bin data is grouped by item;
warehouse is only the report filter, not each MPS line's warehouse. There are no locks or stored
allocations.

The report has a second inconsistent lead-time model. Manufacture returns:

```text
rate-like value = 1440 / manufacturing_time_in_mins + buffer_time
reported lead days = ceil(required_qty / rate-like value)
```

while purchase is `purchase_time + buffer_time`
(`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:1205-1235`,
`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:433-490`). Adding day-valued buffer to units/day is dimensionally suspect. When finished-good lead time is
zero, recursive fallback again sums every material branch. Raw-material output uses
`material.stock_qty × parent required_qty` even though explosion separately computed
`stock_qty / parent_qty`; BOMs with output quantity other than one can be overstated
(`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:782-820`,
`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:913-945`). Neither recursion has a cycle guard.

The detailed chart sorts on `delivery_date` but reads misspelled `deliver_date`, an apparent runtime
failure path (`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:263-276`).

---

## 12. MPS submit and order creation — explicit unfinished behavior

The controller defines:

```text
on_submit -> enqueue_doc("Master Production Schedule", name, "make_mrp")
message: "MRP Log documents are being created"
```

(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:439-447`). However, the
MPS DocType metadata at this pin is not submittable and grants no submit/cancel permission. A repository
search found no `make_mrp` method/function/caller beyond this enqueue, and no MRP Log DocType. Normal UI
flow cannot reach the hook; forced submission would enqueue a missing method. This is unfinished, not an
asynchronous planning implementation.

The report's separate `make_order` trusts selected browser rows without recomputing demand. It checks only
Purchase Order create permission even when creating only Work Orders, groups Purchase Orders by supplier
and release date, inserts all POs first, then inserts Work Orders
(`manufacturing/report/material_requirements_planning_report/material_requirements_planning_report.py:1300-1394`). POs apply whole-UOM rounding and MOQ; WOs use release/delivery dates and
`ignore_mandatory` but still run validation. All are drafts. There is no proposal token, idempotency key,
stock/supply lock or second netting pass. Two users can release the same stale rows twice.

There is no explicit commit/savepoint in the command, so normal request rollback should undo earlier PO
inserts if a later WO fails. But ordering matters to hooks, and there is no partial-retry identity. The
command returns no persisted IDs even though the client expects a message for navigation.

> **Invariant M28 — planning is separate from release.** An MRP run is persisted with immutable input
> watermark, exploded requirements, supply allocations, exceptions and deterministic result hash.
> Approval freezes selected proposal lines. Release revalidates under owner locks, consumes proposal
> allocations atomically, creates documents through ordinary permissions/validators with idempotency
> keys, and returns every created/reused ID. Background execution has a real method, durable job/log,
> retry semantics and terminal status.

---

## 13. Transaction, direct-write and race inventory

No explicit commit, savepoint or queue boundary exists in Production Plan services or report release;
normal Frappe request transactions provide rollback for escaped exceptions. The swallowed
`OverProductionError` intentionally keeps a Work Order loop running without surfacing the omission.

Important direct writes and race windows are:

- SO/MR demand selection then plan submit has no owner lock; parallel plans allocate the same gap.
- SO `production_plan_qty`, plan ordered/produced/requested/received fields and status are mutable
  projections rewritten with `set_value`, `db_set` or child `db_update`.
- Material netting and Pick List location selection are unlocked previews; another request can consume
  stock before release.
- Material Request ceiling validation and requested read-add-write are separate unlocked operations.
- Draft WO/PO creation does not update plan counters and has no uniqueness key.
- Work Order/PO insertion bypasses validation; Work Order overproduction is swallowed.
- Bin rows are locked individually only during plan projection refresh; source aggregates are not locked,
  and child-order lock acquisition can deadlock across plans.
- Explicit SRE availability is stock balance minus an unlocked aggregate; the Production Plan field
  initialisation branch is unreachable.
- Delivery Schedule replacement and MPS reads race; stale rows may be planned or concurrently deleted.
- MRP supply pools and selected report rows are not evidence. Repeated release duplicates supply.

> **Invariant M29 — serializable planning ownership and audit.** Each demand allocation, supply
> allocation, reservation transition and proposal release locks one declared owner or executes at
> serializable isolation. Projection writers use deterministic lock order and idempotent event position.
> Every override, lot-size rounding, shortage, validation rejection and released document is audited;
> no `db_set`, permission bypass or validation bypass can create authoritative planning state.

---

## 14. Findings and decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Production Plan as a demand-to-supply planning document | **Adopt concept** | immutable versioned planning run plus separately approved release |
| SO/MR demand import | **Adopt sources** | locked source-line allocations with item+warehouse+date dimensions |
| `production_plan_qty`/`ordered_qty` mutable counters | **Projection only** | aggregate from allocation/release rows |
| BOM-keyed combined SO rows | **Reject** | preserve source/date/warehouse; grouping is presentation only |
| Three raw-material explosion paths | **Unify** | one cycle-safe revision-pinned graph function |
| Phantom and explicit subassembly semantics | **Adopt** | typed graph nodes and sourcing decisions |
| Projected-stock subtraction | **Adopt intent** | allocation against dated supply, not subtraction from a cache |
| Actual quantity as display only | **Clarify** | named supply classes and as-of watermark |
| Negative projected quantity ignored | **Reject** | deficit is explicit prior demand/shortage |
| Safety stock option | **Adopt policy** | effective-dated buffer applied once at configured dimension |
| MOQ before transfer and again after transfer | **Reject** | one lot-sizing stage after allocation policy |
| Purchase-UOM whole-number handling | **Reject bug** | stock-space netting, then order-UOM ceiling and stored stock equivalent |
| Warehouse transfer split via Pick List | **Adopt intent** | locked/reserved source allocations before purchase residual |
| Production Plan MR creation | **Adopt output** | validated idempotent release command |
| WO/PO `ignore_validate` and `ignore_mandatory` | **Reject** | no general bypass; ordinary validators and permissions |
| Swallowed `OverProductionError` | **Reject** | atomic failure with explicit residual/source context |
| Subcontract classification and supplier grouping | **Adopt concept** | policy revision and proposal lines; no missing-supplier draft |
| Gross requirement used for Bin/SRE reservation | **Reject ambiguity** | reservation stage and quantity explicitly selected from allocation |
| Parallel Bin and SRE reservation truths | **Reject** | one allocation/reservation ledger; Bin only cache |
| Unreachable Production Plan SRE initialisation | **Reject bug** | typed adapter covered by lifecycle/concurrency tests |
| Sales Forecast period rows | **Adopt shape** | real/manual forecast versions with bucket bounds and dimensions |
| Hard-coded forecast demand `1.0` | **Reject placeholder** | model/manual input with provenance and confidence |
| Exact-day `max(actual, forecast)` | **Reject** | time-fence bucket consumption allocations |
| MPS item+date aggregation | **Insufficient** | item+warehouse+date+demand class+source |
| Delivery Schedule replacing SO line | **Adopt concept** | transactional children with quantity/date invariant and version lock |
| Sum of all BOM lead-time branches | **Reject** | critical-path DAG with calendars and capacity |
| Two inconsistent lead-time formulas | **Reject** | typed duration/rate model with unit checks |
| MRP report in-memory netting | **Preview only** | persisted reproducible planning run |
| MPS dead submit hook/missing `make_mrp` | **Reject unfinished** | real durable job or no submit promise |
| Report-row PO/WO insertion | **Reject boundary** | approved, revalidated, idempotent proposal release |

The nine planning invariants added here are **M21–M29**: immutable planning snapshots; atomic,
dimension-preserving demand allocation; one cycle-safe explosion; dimensionally correct allocative
netting; validated/idempotent release; one reservation/projection model; feasible critical-path dates;
persisted planning separated from release; and serializable planning ownership/audit. Together with
M1–M20, they connect immutable product/route definitions and execution evidence to a reproducible supply
plan without treating editable counters or report rows as commitments.

---

Cross-references: doc 10 (fulfilment allocations/lost updates), doc 16 (reservation and Bin), doc 17
(item/UOM/reorder), doc 20 (direct-write audit gaps), doc 22 (jobs/locking), doc 33 (BOM graph and
explosion), doc 34 (capacity/calendars/lead time), doc 35 (Work Order release and execution),
`docs/design/FINAL-SCHEMA.md` (fixed-decimal, event/allocation and projection principles). Next: doc 37,
manufacturing Stock Entry, WIP and GL.
