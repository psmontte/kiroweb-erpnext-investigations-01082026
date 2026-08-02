# S07 — Make-to-Order Manufacturing: Sales Order → Production → Delivery

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Continues **[S01](S01-order-to-cash.md)** at the point where an ordered Item is made rather than
> taken from finished-goods stock. The subsystem background is **[doc 33](../logic/33-bom-costing-explosion-and-update-jobs.md)**
> through **[doc 37](../logic/37-manufacturing-stock-consumption-scrap-wip-and-gl.md)**.
>
> This document covers in-house manufacture only. Subcontracting is deferred to S08. Quality appears
> only where it gates a Job Card or Stock Entry; inspection execution is deferred to S09.

---

## 1. The worked example

Customer **ACME** orders **10 EA FG-MTO** from company **AlphaCo** for 100.00 each. The submitted Sales
Order line names `BOM-FG-MTO-001`; there is no finished stock, so all 10 must be made.

The released BOM and route are:

| Kind | Item / operation | Per gross unit | Total for WO 10 | Valuation / cost |
|---|---|---:|---:|---:|
| Raw material | RM-A | 2 kg | 20 kg | 4.00/kg = 80.00 |
| Raw material | RM-B | 1 kg | 10 kg | 6.00/kg = 60.00 |
| Secondary output | SCRAP-A | 0.1 kg | 1 kg | 2.00/kg = 2.00 |
| Operation 10 | Cut | 3 min | 30 min | included below |
| Operation 20 | Assemble | 6 min | 60 min | included below |
| Added operation cost | labour/machine | | | **30.00** |

The BOM quantity basis is one finished unit. `SCRAP-A` is a legacy scrap row for this worked valuation:
its 2.00 total value is credited out of principal FG basic cost. Modern secondary-output allocation has
additional defects discussed in doc 37 §7.2; using legacy scrap keeps the arithmetic deterministic
without hiding that distinction.

Execution is deliberately partial:

1. transfer all raw material to WIP;
2. complete the first execution lots for gross quantity 6 and manufacture **6 accepted FG**;
3. at that point, **RM-A 8 kg + RM-B 4 kg = 56.00 remains in WIP**;
4. complete the remaining gross quantity 4, but Assemble records **1 unit process loss**;
5. manufacture **3 accepted FG**, so the Work Order completes as `9 produced + 1 loss = 10`;
6. deliver the 9 physical units. The Sales Order remains short by 1 unless the commercial quantity is
   amended or another Work Order is authorised; production completion and delivery completion are not
   the same fact.

The canonical posting path below uses **direct consumption on each Manufacture Stock Entry**. Section 7
shows the separate `Material Consumption for Manufacture` branch and why it is not interchangeable in
partial production.

---

## 2. Stage 1 — Sales Order and Production Plan

### 2.1 Sales Order: demand, not production evidence

Submitting **SO-MTO-0001** persists the order and reserves finished stock if configured, exactly as in
S01 §2. It creates no Work Order, Job Card, Stock Ledger Entry or GL Entry. The manufacturing-relevant
fields are on `tabSales Order Item`: `item_code=FG-MTO`, `stock_qty=10`, `bom_no=BOM-FG-MTO-001`,
`production_plan_qty=0`, `work_order_qty=0`, `produced_qty=0`, and `delivered_qty=0`.

`make_production_plan` maps a submitted Sales Order into an unsaved Production Plan and calls the
planning service (`selling/doctype/sales_order/mapper.py:879-910`). The source query requires a
submitted Sales Order Item with an active BOM and calculates:

```text
available demand basis = stock_qty - stock_reserved_qty
pending_qty = available demand basis
              - max(work_order_qty, delivered_qty × conversion_factor, 0)
```

The query and formula are in
`manufacturing/doctype/production_plan/services/sales_order_planning.py:140-190` and
`manufacturing/doctype/production_plan/services/sales_order_planning.py:285-320`.
For this example all counters are zero, so pending quantity is 10.

### 2.2 Draft Production Plan writes

Fetching Sales Orders appends the production item with Item/BOM, warehouse, UOM, source Sales Order and
line identity, planned quantity and pending quantity
(`manufacturing/doctype/production_plan/services/sales_order_planning.py:216-267`). With
`combine_items=0`, saving **PP-MTO-0001** writes:

| Table | Rows | Worked values |
|---|---:|---|
| `tabProduction Plan` | 1 | company AlphaCo, source `Sales Order`, total planned qty 10 |
| `tabProduction Plan Sales Order` | 1 | `sales_order=SO-MTO-0001` |
| `tabProduction Plan Item` | 1 | FG-MTO, BOM, `planned_qty=10`, `pending_qty=10`, SO and SO-item links |
| `tabProduction Plan Item Reference` | 0 | used when combined demand must retain multiple SO allocations |
| `tabProduction Plan Sub Assembly Item` | 0 | no subassembly in this example |
| `tabMaterial Request Plan Item` | 2 if raw-material planning is fetched | RM-A 20, RM-B 10; planning rows, not allocations |

When combination is enabled, the planner combines by BOM and stores hidden source allocations in
`Production Plan Item Reference` rows
(`manufacturing/doctype/production_plan/services/sales_order_planning.py:228-283`). That retained
reference is useful, but the visible production row has already lost one-demand-line identity.

### 2.3 Submit order

`ProductionPlan.on_submit` performs, in order:

1. refresh Production Plan reservation quantities in `tabBin`;
2. recompute `Sales Order Item.production_plan_qty`;
3. link raw-material plan rows to subassembly rows;
4. create/update explicit `Stock Reservation Entry` rows when `reserve_stock=1`.

That order is explicit at
`manufacturing/doctype/production_plan/production_plan.py:243-304`. `update_sales_order` aggregates
submitted plan rows and directly writes `production_plan_qty`; `update_bin_qty` takes a `for_update`
lock on each affected Bin before rebuilding reservation projections
(`manufacturing/doctype/production_plan/production_plan.py:305-397`).

After submit, `SO Item.production_plan_qty=10`. There are still **no SLEs and no GL entries**. The plan,
its material rows, the Sales Order counter, Bin reservation fields and optional reservation records are
planning/allocation representations, not inventory or accounting evidence.

---

## 3. Stage 2 — Production Plan creates the Work Order

### 3.1 The creator bypasses validation

`WorkOrderCreationService.get_production_items` calculates finished-goods quantity as
`planned_qty - ordered_qty`; it retains Sales Order, plan-item, BOM, warehouse, project and start-date
provenance (`manufacturing/doctype/production_plan/services/work_order_planning.py:31-98`). The service
creates finished-goods Work Orders before in-house subassembly Work Orders
(`manufacturing/doctype/production_plan/services/work_order_planning.py:100-145`).

For FG-MTO it builds **WO-MTO-0001**, compiles operation and required-item children, then inserts the
*draft* with both `ignore_mandatory` and `ignore_validate`; the surrounding `OverProductionError`
handler cannot restore checks that were skipped
(`manufacturing/doctype/production_plan/services/work_order_planning.py:198-241`). This is not a minor
UI shortcut: company/warehouse, dates, quantity, sequence and reservation checks do not share one
creation boundary across all callers.

### 3.2 The Work Order snapshot

A normal save/submit runs Work Order validation, including BOM/Sales Order, warehouse, WIP, quantity,
transfer mode, operation/resource, date, whole-number UOM, required-item and sequence checks
(`manufacturing/doctype/work_order/work_order.py:284-371`). Required items copy BOM rate/amount,
operation identity, quantity, source warehouse and inclusion/alternative flags
(`manufacturing/doctype/work_order/services/required_items.py:57-131`).

Before submit the relevant persisted shape is:

| Table | Rows | Worked values |
|---|---:|---|
| `tabWork Order` | 1 | FG-MTO, `qty=10`, source Raw, WIP, FG and Scrap warehouses, SO/PP provenance |
| `tabWork Order Item` | 2 | RM-A required 20 @ Raw; RM-B required 10 @ Raw |
| `tabWork Order Operation` | 2 | Cut sequence 1; Assemble sequence 2; copied resource/time/rate data |

Calling these children a snapshot is generous. Stock Entry callbacks later rewrite material transferred,
consumed and returned quantities; Job Card callbacks rewrite operation completion, loss, pending, actual
time, dates, workstation and cost. Doc 35 §§1–3 traces the two compilers and the stale-refresh paths.

### 3.3 Submit writes, exactly ordered

After the Work Order and children are stored as submitted, `WorkOrder.on_submit` executes:

1. validate warehouses;
2. write `Sales Order Item.work_order_qty` (or combined-plan references);
3. recompute Production Plan item/subassembly `ordered_qty` and status;
4. rebuild raw-material `Bin.reserved_qty_for_production`;
5. rebuild linked Material Request ordered/completion counters;
6. rebuild FG `Bin.planned_qty`;
7. create Job Cards;
8. transfer/create explicit Stock Reservation Entries when enabled;
9. update subcontract-inward allocations (not used here).

The order is
`manufacturing/doctype/work_order/work_order.py:612-633`. Our worked projections become:

| Row | Before | After WO submit |
|---|---:|---:|
| `Sales Order Item.work_order_qty` | 0 | 10 |
| `Production Plan Item.ordered_qty` | 0 | 10 |
| FG `Bin.planned_qty` | 0 | 10 |
| RM-A `Bin.reserved_qty_for_production` | 0 | 20 |
| RM-B `Bin.reserved_qty_for_production` | 0 | 10 |

Again: **no stock and no GL moved**. All five values are mutable roll-ups over an authorisation.

---

## 4. Stage 3 — Job Cards record shop-floor execution

### 4.1 Four cards are created; only the first lot is submitted initially

Assume both Operation masters request Job Cards by batch size 6. The splitter repeatedly takes
`min(remaining, batch_size)`, so Work Order submit creates a 6-unit and a 4-unit draft card for each
operation (`manufacturing/doctype/work_order/mapper.py:290-389`). Each card copies the exact Work Order
operation row (`operation_id`), sequence, workstation/type, rate, proportional quantity/time,
warehouses and BOM provenance (`manufacturing/doctype/work_order/mapper.py:391-468`).

| Job Card | Operation | `for_quantity` | Eventual result | Submitted before |
|---|---|---:|---|---|
| JC-CUT-1 | Cut | 6 | completed 6, loss 0 | Manufacture 1 |
| JC-ASM-1 | Assemble | 6 | completed 6, loss 0 | Manufacture 1 |
| JC-CUT-2 | Cut | 4 | completed 4, loss 0 | Manufacture 2 only |
| JC-ASM-2 | Assemble | 4 | completed 3, **process loss 1** | Manufacture 2 only |

Creation writes four draft `tabJob Card` parents. Actual `tabJob Card Time Log` children arrive as the
lots execute; scheduled segments, sub-operations, required materials and secondary items produce the
other Job Card child tables only when configured. No SLE or GL row follows from a time log.

The chronology is load-bearing. **Before STE-MFG-0001, only JC-CUT-1 and JC-ASM-1 are submitted.**
JC-CUT-2 and the loss-bearing JC-ASM-2 remain draft. Otherwise the final cumulative operation loss
would already be visible, and ERPNext would reset the first Manufacture entry's process loss to 1.

The completion identity is important. `operation_id` points to the durable `Work Order Operation` child;
`operation_row_id` is only its copied ordinal. Job Card creation and its child shapes are detailed in
doc 35 §6.

### 4.2 First-lot completion snapshot

Job Card validation requires, at field precision:

```text
total_completed_qty + process_loss_qty + pending_qty = for_quantity
```

and `set_process_loss` derives loss as the residual when completion is positive and below the card
quantity (`manufacturing/doctype/job_card/job_card.py:967-1003`). The first cards both balance
`6 + 0 + 0 = 6`.

On submit, Job Card validates any configured in-process quality gate, material transfer, stopped/hold
state, time and completion; then it rewrites Work Order operation aggregates
(`manufacturing/doctype/job_card/job_card.py:826-990`). Submitted siblings are summed, min/max log
times are read, the submitted Work Order Operation is rewritten, operating cost/dates/status are
recalculated and the Work Order is saved under `ignore_validate_update_after_submit`
(`manufacturing/doctype/job_card/job_card.py:1005-1159`).

Immediately before the first Manufacture entry the projection is therefore:

| `tabWork Order Operation` | Completed | Loss | Pending | Evidence source |
|---|---:|---:|---:|---|
| Cut | 6 | 0 | 0 | JC-CUT-1 only |
| Assemble | 6 | 0 | 0 | JC-ASM-1 only |

The Job Card parent and time logs are intended execution evidence, but even submitted logs/totals are
mutable through direct-write paths (doc 35 §7). The Work Order Operation values are unequivocally
**projections** over those cards.

Quality boundary: if both BOM inspection and the exact Work Order Operation flag require inspection,
Job Card submission requires its Quality Inspection link and applies Stop/Warn policy
(`manufacturing/doctype/job_card/job_card.py:842-890`). Stock Entry can separately require transaction
inspection. This scenario assumes both gates pass; S09 will inspect their distinct subjects.

---

## 5. Stage 4 — transfer all material to WIP

### 5.1 Builder and quantities

The Work Order mapper creates an unsaved `Material Transfer for Manufacture`, copies Work Order/BOM,
sets `fg_completed_qty`, and targets the non-group WIP warehouse
(`manufacturing/doctype/work_order/mapper.py:228-288`). The purpose service reads Work Order required
rows, omits excluded rows and builds source→WIP details
(`stock/doctype/stock_entry/services/material_transfer.py:231-346`).

For required quantity `R`, Work Order output `W=10`, requested gross transfer basis `F=10`, and already
transferred `T=0`:

```text
desired transfer = F × R / W
pending transfer = R - T
```

The cap/allowance selection is in
`stock/doctype/stock_entry/services/material_transfer.py:254-281`. **STE-WIP-0001** therefore has:

| Detail | Source | Target | Qty | Realised source rate | Value |
|---|---|---|---:|---:|---:|
| RM-A | Raw | WIP | 20 | 4.00 | 80.00 |
| RM-B | Raw | WIP | 10 | 6.00 | 60.00 |

### 5.2 Physical write order

Stock Entry submit first invokes the purpose callback. That callback recomputes Job Card transfer fields,
may append non-BOM material as a new child on the already-submitted Work Order, and rebuilds Work Order
quantities/status/dates
(`stock/doctype/stock_entry/services/material_transfer.py:367-395` and
`manufacturing/doctype/work_order/services/required_items.py:263-301`). The common controller then:
serial/batch conversion → reservation adjustment → SLE posting → WIP/FG reservation → related-document
updates → GL → future repost → project/QI updates
(`stock/doctype/stock_entry/stock_entry.py:331-356`).

So the domain projection callback physically runs **before** the stock evidence it summarises. There is
no intermediate commit, so an escaped error normally rolls the transaction back, but the dependency is
still implicit call ordering.

### 5.3 Source-before-target SLEs

`update_stock_ledger` constructs **all source SLEs first, then all targets**, and reverses the complete
list on cancellation (`stock/doctype/stock_entry/stock_entry.py:977-1120`):

| SLE order | Item / warehouse | `actual_qty` | `incoming_rate` | `stock_value_difference` |
|---:|---|---:|---:|---:|
| 1 | RM-A / Raw | −20 | 0 | **−80.00** |
| 2 | RM-B / Raw | −10 | 0 | **−60.00** |
| 3 | RM-A / WIP | +20 | 4.00 | **+80.00** |
| 4 | RM-B / WIP | +10 | 6.00 | **+60.00** |

The source details set dependent SLE links and transfer targets are marked for rate recalculation. WIP
is not a production ledger: these are ordinary Item/Warehouse stock rows using ordinary valuation.

`BaseStockGLComposer` reads the SLE `stock_value_difference` and creates the warehouse↔detail-account
pairs (`stock/services/base_stock_gl_composer.py:27-102`). After merging the clearing legs, the economic
journal is:

| Account | Debit | Credit |
|---|---:|---:|
| WIP Inventory | 140.00 | |
| Raw Materials Inventory | | 140.00 |

Balanced. If Raw and WIP warehouses share one stock account, the merged GL can be empty while all four
SLEs remain. The durable writes are one `tabStock Entry`, two `tabStock Entry Detail`, four
`tabStock Ledger Entry`, updated Raw/WIP `tabBin` rows, normally two merged `tabGL Entry`, and any
serial/batch or reservation rows.

---

## 6. Stage 5 — partial Manufacture with direct consumption

### 6.1 Row generation order

For purpose `Manufacture`, the service constructs rows in this order:

```text
raw materials → process loss → principal FG → BOM secondary outputs
→ additional/operation costs → Job Card secondary outputs
```

(`stock/doctype/stock_entry/services/manufacturing.py:384-391`). The Stock Ledger later normalises that
into all sources before all targets.

With direct BOM backflush, each raw quantity is:

```text
Work Order Item.required_qty / Work Order.qty × Stock Entry.fg_completed_qty
```

and source warehouse resolves to WIP for this Work Order
(`stock/doctype/stock_entry/services/manufacturing.py:414-456`). Transfer-based backflush instead
reconstructs transferred residual by `(item_code, WIP warehouse)` and subtracts prior Manufacture
source rows (`stock/doctype/stock_entry/services/manufacturing.py:499-688`).

### 6.2 First Manufacture: gross 6, accepted 6

**STE-MFG-0001** has `fg_completed_qty=6`, `process_loss_qty=0` and operation cost 18.00. In the
worked time/rate snapshot, the first-lot cards carry 60% of the route's actual 30.00 cost. ERPNext
clears/rebuilds Stock Entry additional costs, derives component actual cost from operation time, subtracts
cost already consumed, and scales the residual to the current gross quantity
(`manufacturing/doctype/bom/services/operations_cost.py:16-126`). The second lot therefore receives the
remaining 12.00 after its cards are submitted. Secondary rows scale BOM quantity by gross completed
quantity; Scrap uses the Work Order scrap warehouse
(`stock/doctype/stock_entry/services/manufacturing.py:45-110`).

Outgoing cost is `48 + 36 = 84`. Legacy scrap basic value is `0.6 × 2 = 1.20`, so principal FG basic
value is `84 - 1.20 = 82.80`. The rate constructor subtracts legacy scrap then divides by accepted FG
quantity (`stock/doctype/stock_entry/stock_entry.py:735-809`). Additional cost is allocated to the
principal FG and the final amount/rate include it
(`stock/doctype/stock_entry/stock_entry.py:811-862`):

```text
FG basic rate       = 82.80 / 6 = 13.80
FG final amount     = 82.80 + 18.00 = 100.80
FG valuation rate   = 100.80 / 6 = 16.80
```

Source-before-target SLEs:

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-A / WIP | −12 | **−48.00** |
| 2 | RM-B / WIP | −6 | **−36.00** |
| 3 | FG-MTO / Finished Goods | +6 | **+100.80** |
| 4 | SCRAP-A / Scrap | +0.6 | **+1.20** |

Within the target phase, actual row order follows the item table; the invariant is that no target SLE
precedes a source SLE. The balanced, merged GL is:

| Account | Debit | Credit |
|---|---:|---:|
| Finished Goods Inventory | 100.80 | |
| Scrap Inventory | 1.20 | |
| WIP Inventory | | 84.00 |
| Operation Cost source | | 18.00 |
| **Total** | **102.00** | **102.00** |

The base stock pairs come from SLE value; `StockEntryGLComposer` adds and clears the operation-cost
source (`stock/doctype/stock_entry/services/gl_composer.py:13-48` and
`stock/doctype/stock_entry/services/gl_composer.py:189-274`).

### 6.3 What “partial” means after STE-MFG-0001

The posting leaves:

| Location/item | Qty | Value |
|---|---:|---:|
| WIP / RM-A | 8 | 32.00 |
| WIP / RM-B | 4 | 24.00 |
| **WIP remaining** | | **56.00** |
| Finished Goods / FG-MTO | 6 | 100.80 |
| Scrap / SCRAP-A | 0.6 | 1.20 |

`Work Order.produced_qty` is rebuilt from submitted Manufacture **finished-item detail quantity**, not
from gross `fg_completed_qty`; process loss is separately summed from Manufacture headers
(`manufacturing/doctype/work_order/services/status.py:193-294`). The projection is therefore
`produced_qty=6`, `process_loss_qty=0`, status `In Process`. Production Plan produced/pending, Sales
Order produced quantity, FG planned quantity, Work Order required-item consumed quantity and Job Card
manufactured/consumed fields are also rewritten.

The 56.00 WIP residual is the strongest practical demonstration of the model: it is real stock and real
balance-sheet value, but warehouse balance does not say **which Work Order owns it**. Work Order and
reservation links supply mutable attribution around the ordinary SLEs.

### 6.4 Second-lot cards, then Manufacture: gross 4, accepted 3, loss 1

Only after STE-MFG-0001 is submitted do JC-CUT-2 and JC-ASM-2 receive time logs and submit. JC-ASM-2
balances `3 completed + 1 loss + 0 pending = 4`. Their callbacks change the cumulative Work Order
operation projections to Cut `10/0/0` and Assemble `9/1/0` for completed/loss/pending. This interleaving
is essential because Manufacture reads the *current cumulative* Work Order Operation loss, not a loss
allocation tied to one output lot.

JC-ASM-2 has now made the Assemble operation's aggregate loss 1. `set_process_loss_qty` uses the maximum
loss stored on Work Order Operation; otherwise it uses the BOM percentage. Principal FG quantity is
`fg_completed_qty - process_loss_qty`
(`stock/doctype/stock_entry/services/manufacturing.py:111-167`). The shared validator requires
`FG detail qty + process_loss_qty = fg_completed_qty`
(`stock/doctype/stock_entry/stock_entry.py:500-545`).

**STE-MFG-0002** has gross 4, accepted FG 3, loss 1 and operation cost 12.00:

```text
raw cost             = RM-A 8×4 + RM-B 4×6 = 56.00
scrap value          = 0.4×2 = 0.80
FG basic amount      = 56.00 - 0.80 = 55.20
FG basic rate        = 55.20 / 3 = 18.40
FG final amount      = 55.20 + 12.00 = 67.20
FG valuation rate    = 67.20 / 3 = 22.40
```

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-A / WIP | −8 | **−32.00** |
| 2 | RM-B / WIP | −4 | **−24.00** |
| 3 | FG-MTO / Finished Goods | +3 | **+67.20** |
| 4 | SCRAP-A / Scrap | +0.4 | **+0.80** |

| Account | Debit | Credit |
|---|---:|---:|
| Finished Goods Inventory | 67.20 | |
| Scrap Inventory | 0.80 | |
| WIP Inventory | | 56.00 |
| Operation Cost source | | 12.00 |
| **Total** | **68.00** | **68.00** |

There is **no process-loss Stock Entry Detail, SLE, serial/batch allocation or GL row**. The physical
fact exists only as Job Card/Work Order/Stock Entry scalar quantities. Economically, the second run's
55.20 principal input value is spread over three accepted units, raising their unit rate. Doc 37 §5.2
explains why this is quantity policy rather than complete loss evidence.

Final moving-average FG inventory is `100.80 + 67.20 = 168.00` for 9 units, or
**18.666666… per accepted unit**. Scrap is 1 unit worth 2.00. WIP is zero. Work Order status becomes
Completed because `produced_qty 9 + process_loss_qty 1 >= qty 10`; the exact status rule is
`manufacturing/doctype/work_order/services/status.py:88-191`.

### 6.5 Optional Standard Cost branch

If FG-MTO uses Standard Cost 18.00, source and scrap values do not change, but each FG SLE posts at
standard. The composer computes:

```text
manufacturing variance = Stock Entry Detail.amount
                         - Σ positive FG SLE.stock_value_difference
```

and reclassifies it to Manufacturing Variance
(`stock/doctype/stock_entry/services/gl_composer.py:53-176`).

| Run | Intended FG amount | Standard FG SVD | Variance | Posting |
|---|---:|---:|---:|---|
| gross 6 / accepted 6 | 100.80 | 108.00 | −7.20 | **Cr** variance 7.20 (favourable) |
| gross 4 / accepted 3 | 67.20 | 54.00 | +13.20 | **Dr** variance 13.20 (unfavourable) |
| total | 168.00 | 162.00 | **+6.00** | net Dr variance 6.00 |

The two net journals become:

| Run 1 account | Debit | Credit |
|---|---:|---:|
| FG Inventory | 108.00 | |
| Scrap Inventory | 1.20 | |
| WIP Inventory | | 84.00 |
| Operation Cost source | | 18.00 |
| Manufacturing Variance | | 7.20 |

| Run 2 account | Debit | Credit |
|---|---:|---:|
| FG Inventory | 54.00 | |
| Scrap Inventory | 0.80 | |
| Manufacturing Variance | 13.20 | |
| WIP Inventory | | 56.00 |
| Operation Cost source | | 12.00 |

Inventory GL remains exactly equal to SLE standard value; actual-vs-standard is named rather than
forced into inventory. This is the correct accounting boundary.

---

## 7. Alternate branch — separate material consumption

When Manufacturing Settings enables material consumption, a `Material Consumption for Manufacture`
Stock Entry requires a Work Order and emits source rows only. BOM/skip-transfer mode uses proportional
Work Order/BOM quantities; transfer mode uses remaining transferred WIP
(`stock/doctype/stock_entry/services/manufacturing.py:852-868`).

For the first gross 6, **STE-CONS-0001** would write:

| SLE | Warehouse | Qty | SVD |
|---|---|---:|---:|
| RM-A | WIP | −12 | −48.00 |
| RM-B | WIP | −6 | −36.00 |

and the merged GL is `Dr Manufacturing/WIP Clearing 84 / Cr WIP Inventory 84`. A later Manufacture with
no raw rows receives FG/scrap and credits the detail clearing account; operation cost is capitalised in
the same additional-cost path. This can balance operationally only when account policy and quantity
attribution are consistent across the separate documents; the schema does not force a dedicated
per-Work-Order clearing account.

The dangerous branch is in `add_raw_materials`: if **any** submitted Material Consumption entry exists
for the Work Order, Manufacture suppresses **all** raw rows
(`stock/doctype/stock_entry/services/manufacturing.py:392-419`). It does not ask whether consumption is
complete for this output lot.

If `get_rm_cost_from_consumption_entry=1`, rate construction additionally:

1. rejects raw rows on Manufacture;
2. allows only one submitted Manufacture entry for the Work Order;
3. takes raw cost from the sum of every submitted consumption detail's
   `valuation_rate × transfer_qty`.

Those checks are in `stock/doctype/stock_entry/stock_entry.py:735-809`. They conflict directly with this
scenario's two partial Manufacture postings. Therefore the canonical worked flow uses direct
consumption. In our design, separate issue and conversion remain valid only because output explicitly
allocates exact issue-event residuals; existence of one issue document is never “consumption complete.”

---

## 8. Stage 6 — Delivery Note ships the 9 accepted units

Production does not create a Delivery Note. `make_delivery_note` maps only the Sales Order's remaining
quantity and sets `Sales Order Item.name → Delivery Note Item.so_detail` plus parent
`against_sales_order` (`selling/doctype/sales_order/mapper.py:226-421`). The mapper proposes 10 because
`delivered_qty=0`; the user must reduce **DN-MTO-0001** to the 9 physical FG units.

Delivery Note submit first updates Sales Order delivered/billing/status projections and reservations,
then posts stock, then GL. The source explicitly requires counter update before stock ledger because Bin
reservation depends on delivered quantity
(`stock/doctype/delivery_note/delivery_note.py:481-540`).

Under moving average, one outgoing SLE is:

| Item / warehouse | `actual_qty` | rate | `stock_value_difference` |
|---|---:|---:|---:|
| FG-MTO / Finished Goods | −9 | 18.666666… | **−168.00** |

and the GL is:

| Account | Debit | Credit |
|---|---:|---:|
| Cost of Goods Sold | 168.00 | |
| Finished Goods Inventory | | 168.00 |

Under the optional Standard Cost branch it is 162.00 instead; the 6.00 net manufacturing variance was
already recognised on production. Delivery does not re-create it.

Writes are one `tabDelivery Note`, one `tabDelivery Note Item`, one outgoing `tabStock Ledger Entry`,
updated FG `tabBin`, two `tabGL Entry` and serial/batch/reservation rows when applicable. Mutable
fulfilment projections become:

| Projection | Value |
|---|---:|
| `Sales Order Item.delivered_qty` | 9 |
| `Sales Order.per_delivered` | 90% |
| `Sales Order Item.produced_qty` | 9 |
| Work Order status | Completed |
| Production Plan Item produced/pending | 9 / 1 |

The last two states expose the semantic split: the Work Order is completed by accepted output plus loss,
but the customer demand and Production Plan still have one physical unit pending.

---

## 9. Complete write trace

The counts below exclude optional taxes, payment schedules, serial/batch bundles, reservations and
Version rows; those depend on configuration. “GL rows” means merged economic rows after processing.

| Stage | Primary document/children | SLE | GL | Mutable projections written |
|---|---|---:|---:|---|
| SO submit | SO 1 + Item 1 | 0 | 0 | SO status, Bin/SRE reservation |
| PP save/submit | PP 1 + SO ref 1 + Item 1 (+ material-plan 2) | 0 | 0 | SO `production_plan_qty`, PP status, Bin/SRE plan reservation |
| WO create/submit | WO 1 + Item 2 + Operation 2 + draft Job Card 4 | 0 | 0 | SO `work_order_qty`, PP `ordered_qty`, RM reserved, FG planned, status |
| First-lot execution | Card 2 submitted + Time Log 2+ | 0 | 0 | WO operation completion/time/cost/dates/status for gross 6 |
| Transfer to WIP | SE 1 + Detail 2 | **4** | **2** | WO/JC transferred qty, required-item qty, Bin/reservation/status |
| Manufacture 1 | SE 1 + Detail 4 + Additional Cost 1 | **4** | **4** | WO/JC/PP/SO produced/consumed/planned/status fields |
| Second-lot execution | remaining Card 2 submitted + Time Log 2+ | 0 | 0 | cumulative WO operation completion/loss/time/cost/dates/status |
| Manufacture 2 | SE 1 + Detail 4 + Additional Cost 1 | **4** | **4** | same projections; WO becomes Completed |
| Delivery 9 | DN 1 + Item 1 | **1** | **2** | SO delivered/status, Bin/reservation/billing projections |
| **Posting total after SO** | | **13 SLE** | **12 merged GL** | dozens of direct aggregate writes |

With Standard Cost, each Manufacture adds a Manufacturing Variance account row after merging, so the
worked GL count is 14 rather than 12. Separate consumption adds two Stock Entries, four source SLEs and
two two-line clearing journals for the two partial issues, while removing source SLEs from Manufacture;
the total physical raw-material movements are unchanged but the command and accounting chain is longer.

### 9.1 Evidence versus projection

| Representation | Classification |
|---|---|
| Submitted Sales Order / Production Plan / Work Order | commercial demand, plan and production authorisation; not stock/accounting evidence |
| Job Card + time logs | execution approval/evidence in intent, but mutable after submit through direct-write paths |
| Work Order Item/Operation quantities, dates, costs and status | mutable projection over Stock Entries and Job Cards |
| SO/PP produced, planned, ordered, delivered and percentage fields | mutable projection |
| Bin planned/reserved/projected quantities | mutable projection/cache |
| Submitted Stock Entry + Detail | strongest production posting command/evidence |
| SLE item, warehouse, actual quantity, voucher/detail and bundle | stock movement evidence |
| SLE running quantity/value/rate/queue and SVD | derived valuation state stored on and rewritable with the SLE |
| GL Entry | accounting evidence in business meaning, but repost can compare/delete/recreate physical rows |
| Serial and Batch Bundle/Entry | tracked-unit allocation evidence, with mutable/cancellation packaging semantics |
| Delivery Note + Detail, outgoing SLE and GL | fulfilment command plus stock/accounting evidence |

The best ERPNext audit chain is therefore:

```text
SO Item → PP Item → WO → WO Item/Operation → Job Card/Time Log
        → Stock Entry Detail → SLE / Serial-Batch Bundle → GL Entry
        → Delivery Note Item → outgoing SLE → GL Entry
```

The middle Stock Entry→SLE→GL chain is the authoritative inventory/accounting boundary. Most values on
both sides of it are mutable summaries.

---

## 10. Cancellation blockers and safe reversal order

The operational reverse order is **Delivery Note → Manufacture 2 → Manufacture 1 → separate
Consumption if used → WIP Transfer → Job Cards → Work Order → Production Plan**.

1. **Delivery Note.** Cancellation rejects a submitted Sales Invoice or Installation Note downstream,
   then reverses SO counters/reservations, SLE and GL
   (`stock/doctype/delivery_note/delivery_note.py:542-572` and
   `stock/doctype/delivery_note/delivery_note.py:650-671`).
2. **Manufacture/transfer.** Stock Entry cancel invokes the purpose callback with cancelled docstatus,
   cancels reservations/projections, reverses the SLE list target-before-source, then reverses GL and
   queues repost (`stock/doctype/stock_entry/stock_entry.py:354-405` and
   `stock/doctype/stock_entry/stock_entry.py:977-1120`). Future stock, negative stock and tracked-unit
   dependencies can block reversal; downstream output should be reversed first.
3. **Separate consumption.** It cannot be cancelled while the Work Order status is Completed
   (`stock/doctype/stock_entry/stock_entry.py:422-427`). Manufacture must be cancelled first so Work
   Order recomputation reopens it.
4. **Job Card.** Cancellation is rejected if Work Order produced quantity would exceed surviving
   submitted operation completion + loss + pending; the error tells the user to cancel Manufacturing
   Entries first (`manufacturing/doctype/job_card/job_card.py:1079-1095`).
5. **Work Order.** A Stopped Work Order must be un-stopped, and any submitted Stock Entry linked to it
   blocks cancellation (`manufacturing/doctype/work_order/work_order.py:844-861`). Cancellation then
   reverses SO, Material Request, FG planned, Production Plan, raw-material Bin, reservation and other
   projections (`manufacturing/doctype/work_order/work_order.py:635-658`). Draft Job Cards are not the
   explicit blocker checked there.
6. **Production Plan.** Cancellation deletes linked *draft* Work Orders, then reverses Bin, Sales Order
   and reservation projections (`manufacturing/doctype/production_plan/production_plan.py:263-304`). A
   submitted Work Order must be cancelled first and generic backlinks may add blockers.

There is no dedicated WIP-residual cancellation object. Consuming WIP creates downstream stock facts;
that dependency is enforced indirectly through linked vouchers, stock availability, serial/batch and
negative-stock behavior rather than one declared production allocation graph.

---

## 11. The same scenario in our design

### 11.1 One immutable demand-to-execution allocation chain

A released Work Order points to immutable BOM, route and policy revisions (docs 33–35). Quantity is not
copied into five unlocked counters as the source of truth. Allocation rows link the exact identities:

```text
sales_order_line 10
  └─ production_plan_allocation 10
       └─ work_order_authorisation gross 10
            ├─ operation_lot Cut/1 gross 6
            ├─ operation_lot Cut/2 gross 4
            ├─ operation_lot Assemble/1 gross 6
            └─ operation_lot Assemble/2 gross 4
```

Each allocation has a unique source/ordinal key and a non-negative residual checked while its owner row
is locked. `planned`, `ordered`, `produced`, `lost` and `delivered` are views over allocations/events,
not fields independently maintained by callbacks.

### 11.2 WIP transfer is paired stock evidence plus ownership

The transfer posts paired immutable `stock_move` rows as in S04, but an allocation edge also says the
WIP stock belongs to WO-MTO-0001:

```text
RM-A Raw −20 / WIP +20, value 80, allocation WO/RM-A
RM-B Raw −10 / WIP +10, value 60, allocation WO/RM-B
```

The quantity/value conservation check is deferred across the pair, and warehouse locks are acquired in
canonical order. WIP remains ordinary inventory; production ownership is explicit rather than inferred
from warehouse and mutable Work Order counters.

### 11.3 Conversion is one immutable event graph

Each partial run is one `production_conversion` command containing typed facts:

- exact input allocations (issue-event or WIP residual IDs);
- accepted FG output;
- secondary/scrap output;
- **explicit normal/abnormal loss event** with operation, reason and quantity;
- operation/resource cost-source allocations;
- serial/batch allocation edges;
- stock moves and one balanced GL journal.

For run 2 the cost equation is recorded, not reconstructed from mutable headers:

```text
input value 56 + resource cost 12
  = FG value 67.20 + scrap value 0.80 + explicit variance 0
```

Under Standard Cost:

```text
input value 56 + resource cost 12
  = FG standard value 54 + scrap 0.80 + manufacturing variance 13.20
```

Process loss is a quantity event even when policy capitalises its value into accepted output. Separate
material issue is safe because the conversion references exact unallocated issue events; one partial
issue cannot suppress unrelated inputs.

### 11.4 Projection order

Stock moves, tracked-unit allocations, cost allocations and balanced GL commit atomically. Only after
that event position advances do idempotent projectors rebuild Work Order, operation, demand and
item/warehouse summaries. A projector either owns one locked row or writes a versioned replacement; it
never runs before the evidence it claims to summarise.

After run 1 the views say accepted 6, loss 0, WIP residual 56. After run 2 they say accepted 9, loss 1,
WIP residual 0. Delivery allocates 9 accepted output units to the SO line, leaving commercial residual 1.
No status formula can convert physical loss into customer delivery.

---

## 12. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| SO→plan→WO quantity | mutable `production_plan_qty`, `work_order_qty`, `ordered_qty` | locked allocation rows; counters are views |
| Production Plan→WO validation | draft insert uses `ignore_validate`/`ignore_mandatory` | one release service for every origin |
| BOM/route on released WO | copied children can later be refreshed/rewritten | immutable revision IDs and fingerprints |
| Execution-lot ceiling | unlocked sibling Job Card aggregate | unique source/ordinal allocation under owner lock |
| Actual work | mutable Job Card/log children | append-only start/stop/labour/machine/output events |
| WIP | ordinary stock, correctly valued; ownership inferred around it | ordinary stock plus explicit WO/input allocation |
| Transfer | source-before-target SLE, dependent-rate hints | paired immutable moves and declared dependency |
| Partial direct consumption | rebuilt from BOM or Item/WIP transfer aggregates | exact WIP allocation residuals |
| Separate consumption completeness | any submitted consumption can suppress all Manufacture inputs | output must allocate exact issue events |
| Process loss | header/Job Card/WO scalars; no stock or accounting row | typed loss event with reason, operation and policy |
| Scrap/by-product | ordinary target stock, which is good; allocation branches differ | typed output move under one versioned allocation policy |
| Operation cost | mutable WO/Job Card totals become Additional Cost | immutable costed usage and allocation facts |
| Standard Cost variance | correctly named GL variance; inventory remains SLE standard | same accounting principle, generated atomically |
| Stock/GL bridge | SLE SVD drives GL; later repost can rewrite/replace | immutable move value delta drives append-only journal/reversal |
| Production progress | callbacks rewrite WO/JC/PP/SO/Bin before/around posting | event-positioned rebuildable projections after evidence |
| Work Order completion | produced + loss can equal authorised gross qty | production authorisation can close, but demand residual remains explicit |
| Cancellation | document-specific blockers plus indirect stock dependencies | dependency graph returns complete blocker set or ordered reversal plan |

---

## 13. Findings and invariants exercised

1. **The accounting core is stronger than the planning shell.** Source-before-target SLE construction,
   SLE-driven inventory GL and Standard Cost variance are coherent. The weak points are unlocked
   allocations and mutable projections around that core.
2. **WIP is real stock, not a special production ledger.** That is good. The missing fact is immutable
   ownership of WIP quantity by Work Order/input allocation.
3. **Gross completion is not accepted output.** ERPNext correctly lets `produced + process loss`
   complete a Work Order, but the Sales Order can still be physically short. These states must never be
   collapsed.
4. **Process loss has economic effect without physical evidence.** It raises accepted-unit cost but has
   no movement, lot allocation, reason or account of its own.
5. **Separate consumption is existence-sensitive.** One submitted partial consumption document can
   suppress every Manufacture input; consumption-derived costing also prohibits multiple partial
   Manufacture entries.
6. **The projection callback runs before posting evidence.** Transaction rollback usually prevents
   committed drift on failure, but ordering and concurrency correctness remain conventions.
7. **Cancellation blockers reveal the real dependency graph.** DN depends on downstream billing; Job
   Card depends on Manufacture; Work Order depends on every submitted Stock Entry; separate consumption
   depends on WO status. The graph is distributed across controllers rather than declared once.

This scenario exercises the manufacturing invariants from docs 33–37, especially **M13–M20**
(authorisation, allocations, execution evidence and serializable projections) and **M30–M40**
(conversion identity, WIP conservation, consumption completeness, loss/coproduct identity, one cost
equation, stock/GL equality and immutable posting). It also reuses **F1** balanced vouchers and **F2**
stock-value-to-inventory-GL equality from S04.

---

Cross-references: **[S01](S01-order-to-cash.md)** (SO and Delivery Note mechanics),
**[S04](S04-stock-transfer-and-in-transit.md)** (paired warehouse movement and valuation);
**[doc 33](../logic/33-bom-costing-explosion-and-update-jobs.md)** (BOM revisions, explosion and cost),
**[doc 34](../logic/34-operations-routing-workstations-and-capacity.md)** (route/resource/capacity),
**[doc 35](../logic/35-work-orders-job-cards-and-shop-floor.md)** (Work Order and Job Card execution),
**[doc 36](../logic/36-production-planning-mps-and-material-netting.md)** (Production Plan/MPS/material
netting), **[doc 37](../logic/37-manufacturing-stock-consumption-scrap-wip-and-gl.md)** (all
manufacturing Stock Entry purposes, WIP, scrap, valuation and GL), and
`docs/design/FINAL-SCHEMA.md` (target immutable-event/allocation schema).
