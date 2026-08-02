# 35 — Work Orders, Job Cards and Shop-Floor Execution

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This document follows docs 33–34 from immutable BOM/route definitions and capacity into production
execution. It traces `Work Order` and `Job Card` end to end: their persisted children; validation and
lifecycle; BOM material and operation snapshots; Job Card splitting; actual work, loss and corrective
operations; material transfer, consumption and manufacture; quality gating; all mapper outputs; and the
mutable roll-ups into Sales Order, Material Request, Production Plan, Stock Reservation Entry and Bin.

The central finding is that ERPNext has a useful recompute-from-submitted-documents pattern, but no one
execution ledger. A submitted Stock Entry and its Stock Ledger/GL rows are the strongest posting
evidence. Around them, Work Order quantities, operation completion, Job Card material quantities,
upstream fulfilment counters, reservation rows and Bin quantities are mutable projections repeatedly
rewritten with `db_set`, query-builder updates and update-after-submit bypasses. Job Card time logs are
execution evidence, but even submitted-card totals and child logs remain mutable. Aggregate validation
is almost entirely unlocked, so concurrent valid requests can oversubscribe an order or last-write a
stale projection.

Our boundary remains the one established in docs 33–34: a Work Order authorises a fixed production lot
against immutable BOM, route and policy revisions; reservations and operation executions are explicit,
uniquely allocated records; actual work and material/output movements are append-only evidence; and all
status, remaining quantity and Bin-style numbers are rebuildable projections.

---

## 1. Data model — authorisation, two copied plans and five Job Card children

### 1.1 `Work Order`

`Work Order` is a submittable production authorisation. Its meaningful persisted parent state is:

| Concern | Meaningful fields |
|---|---|
| Identity and demand | `company`, `production_item`, `bom_no`, `qty`, stock UOM, project, planned/actual dates and expected delivery |
| Warehouses and material policy | source/WIP/finished-good/scrap warehouses, `use_multi_level_bom`, alternative-item permission, skip-transfer/from-WIP flags, `transfer_material_against`, stock reservation |
| Execution plan | persisted `required_items` and `operations`; semi-finished tracking; serial/batch creation settings |
| Mutable progress | status, material/additional transfer, produced/disassembled/process-loss quantities, planned/actual lead time |
| Cost projection | planned, actual, additional, corrective and total operating cost |
| Upstream provenance | Sales Order/item, Material Request/item, Production Plan/item/subassembly, MPS, product-bundle item and subcontracting-inward links |

The generated controller types show that `non_stock_items` and `secondary_items` look like child tables,
but both are Python properties: the first is recalculated from BOM non-stock rows, while the second reads
submitted Stock Entry secondary outputs when any exist and otherwise scales BOM secondary rows
(`manufacturing/doctype/work_order/work_order.py:127-242`). They are views, not persisted Work Order
sources.

The two durable child tables are passive documents:

- **`Work Order Item`** stores item, source warehouse, required/transferred/consumed/returned/reserved
  quantities, rate/amount, operation and operation-row association, inclusion/alternative flags, and
  additional/customer-provided provenance. Its only custom database rule is a non-unique
  `(item_code, source_warehouse)` index (`manufacturing/doctype/work_order_item/work_order_item.py:7-48`).
- **`Work Order Operation`** stores the copied BOM/operation identities, sequence, concrete/type
  resource, planned and actual minutes/dates/cost, batch and fixed-time semantics, semi-finished output
  and BOM, warehouses, subcontract/quality/transfer flags, and mutable completed/loss/pending quantities
  and status (`manufacturing/doctype/work_order_operation/work_order_operation.py:7-51`).

These are snapshots only by convention. Submitted operation rows are rewritten from Job Card aggregates;
required rows can be appended after submission; and the BOM refresh endpoint clears and recreates both
sets (§2, §9).

### 1.2 `Job Card`

A Job Card is one execution lot for one Work Order operation. It carries Work Order and operation-row
identity, sequence, requested/pending/completed/loss/manufactured/transferred quantities, concrete
Workstation/Type, expected and actual dates, hourly rate, source/WIP/target warehouses, semi-finished
BOM/output, subcontract and corrective flags, Quality Inspection, pause state and status
(`manufacturing/doctype/job_card/job_card.py:54-151`). `operation_id` is the durable child-row identity;
`operation_row_id` is the copied ordinal and is not sufficient identity.

Its five meaningful child shapes are:

- `Job Card Item`: proportional required material plus mutable transferred/consumed quantities
  (`manufacturing/doctype/job_card_item/job_card_item.py:7-33`);
- `Job Card Time Log`: employee, actual interval, optional sub-operation, minutes and completed quantity
  (`manufacturing/doctype/job_card_time_log/job_card_time_log.py:7-27`);
- `Job Card Scheduled Time`: planned interval segments (`manufacturing/doctype/job_card_scheduled_time/job_card_scheduled_time.py:7-23`);
- `Job Card Operation`: immediate sub-operation, status, completed minutes and quantity
  (`manufacturing/doctype/job_card_operation/job_card_operation.py:8-26`);
- `Job Card Secondary Item`: BOM secondary output identity/type and stock quantity
  (`manufacturing/doctype/job_card_secondary_item/job_card_secondary_item.py:7-28`).

The `employee` Table MultiSelect reuses `Job Card Time Log` rows under another `parentfield`. The parent
rebuilds it from actual logs during validation; it is another projection, not a separate labour source
(`manufacturing/doctype/job_card/job_card.py:1445-1467`).

> **Invariant M13 — immutable execution authorisation.** A released Work Order names one BOM revision,
> route revision, policy revision, output quantity/UOM, warehouse chain and demand allocation. Release
> freezes those inputs. A changed material, route or quantity creates an authorised revision/change
> order; it never silently rewrites the released plan or already-recorded execution.

---

## 2. Work Order construction — multiple creators and two snapshot compilers

### 2.1 Required materials

`RequiredItemsService.set_required_items` calls `get_bom_items_as_dict` for the Work Order quantity.
`use_multi_level_bom` selects the flattened BOM view; otherwise direct components are used. It then
copies rate/amount, operation and operation-row ID, item metadata, required quantity, warehouse,
inclusion and alternative-item flags. Source warehouse precedence is Work Order source → BOM row → Item
default; Production Plan may force the Work Order source (`manufacturing/doctype/work_order/services/required_items.py:57-131`).

When required rows already exist and Manufacturing Settings disallows editing, ordinary validation calls
this service with `reset_only_qty=True`. That mode updates only rows whose item code still exists and
fills a missing operation; it does **not** delete removed BOM items or append newly introduced ones
(`manufacturing/doctype/work_order/work_order.py:284-318`,
`manufacturing/doctype/work_order/services/required_items.py:71-101`). The explicit BOM-refresh method
is the only path that clears both materials and operations
(`manufacturing/doctype/work_order/services/required_items.py:57-61`).

⚠️ **A normal draft save can preserve a structurally stale material snapshot.** Changing BOM structure
without invoking the full refresh leaves old rows and omits new rows; quantities alone may update.

Available quantities at source/WIP are live informational reads, not reservations or release-time facts
(`manufacturing/doctype/work_order/services/required_items.py:63-69`).

### 2.2 Operations

`OperationsService` clears Work Order operations and reads selected `BOM Operation` fields: resource,
sequence, rate, duration, batch/fixed-time flags, semi-finished output/BOM, warehouses, subcontract,
quality and material-transfer semantics (`manufacturing/doctype/work_order/services/operations.py:19-46`,
`manufacturing/doctype/work_order/services/operations.py:160-234`). In multi-level mode it traverses
`BOMTree` bottom-up, scales each nested operation by exploded child quantity/BOM quantity, appends root
operations, then scales every non-fixed duration by Work Order quantity. Batch-card operations use their
batch size in the pre-scaling formula (`manufacturing/doctype/work_order/services/operations.py:183-249`).

The child query filters `parent = bom_no` but not `parenttype = 'BOM'`, so a same-named Routing can
contaminate the snapshot. Doc 34 §2 traces this shared-child defect and the exact duration/cost formulas;
they are not repeated here.

### 2.3 Creators do not share one validation boundary

The Work Order mapper returns an unsaved Work Order, resolves the selected/default/variant BOM, and
builds both snapshots only when quantity is positive
(`manufacturing/doctype/work_order/mapper.py:27-153`). Other parents create Work Orders differently:

- Sales Order inserts a Work Order first, then sets operations and saves again
  (`selling/doctype/sales_order/mapper.py:844-876`).
- Material Request builds both snapshots, then saves with `ignore_validate` and `ignore_mandatory`
  (`stock/doctype/material_request/material_request.py:553-603`).
- Production Plan builds operation/material snapshots, then inserts with both bypass flags
  (`manufacturing/doctype/production_plan/services/work_order_planning.py:198-231`).

⚠️ **Production Plan and Material Request can bypass the Work Order validator.** Production Plan even
catches `OverProductionError` around an insert whose `ignore_validate` suppresses the Work Order check.
The bypass also skips company/warehouse, sequence, reservation, date and quantity gates. Prebuilding the
children is not equivalent to validating the parent.

> **Ours.** Every creator calls one `release_work_order` application service. It validates the same
> command, compiles material and route snapshots once, writes demand allocations and the Work Order in
> one transaction, and returns the same typed result regardless of its Sales Order, plan, request or
> manual origin. No internal caller has a general `ignore_validate` capability.

---

## 3. Work Order validation and quantity ceilings

Validation is an ordered mutating pipeline: production item/BOM and Sales Order checks; warehouse
defaults, operation warehouses and company checks; WIP policy; operating cost; quantity; transfer mode;
operations; status; Workstation Type; multi-level reset; stock-reservation policy and FG warehouse;
dates; source warehouse propagation; whole-number UOM; required material rebuild; automatic reserve;
sequence; and subcontract-inward validation (`manufacturing/doctype/work_order/work_order.py:284-329`).
`before_save` then copies the parent skip-transfer flag into semi-finished operation rows
(`manufacturing/doctype/work_order/work_order.py:330-339`).

Important gates are:

- output quantity must be positive and integral when its UOM requires whole numbers;
- every operation gets batch size 1 when falsey and must have positive minutes;
- submitted operations require Workstation or Workstation Type;
- submitted orders need a transfer mode; no-operation orders are forced to Work Order mode;
- planned/actual end cannot precede start;
- WIP is mandatory unless transfer is skipped, and FG warehouse is mandatory;
- operation sequence must begin at 1 and each next row may repeat the current sequence or increment by
  exactly one (`manufacturing/doctype/work_order/work_order.py:321-371`,
  `manufacturing/doctype/work_order/work_order.py:844-946`).

Subcontracting-inward validation fixes source and FG warehouses to the inward order, requires each
customer-provided item to exist exactly once, and compares its Work Order requirement with received −
returned − already allocated quantity. Non-customer items cannot source from customer warehouses
(`manufacturing/doctype/work_order/work_order.py:372-449`). The later allocation update is a direct
CASE increment/decrement on received-item rows rather than a recomputed allocation table
(`manufacturing/doctype/work_order/work_order.py:660-720`).

### 3.1 Three separate overproduction ceilings

1. **Sales Order release.** Existing submitted, non-Closed Work Orders contribute
   `qty - process_loss_qty`; candidate quantity is compared with direct plus packed Sales Order quantity
   and the Sales Order overproduction percentage
   (`manufacturing/doctype/work_order/services/status.py:23-86`).
2. **Production Plan release.** A main plan item permits `planned_qty + WO allowance - ordered_qty`.
   This branch does not cover subassembly plan rows
   (`manufacturing/doctype/work_order/work_order.py:869-927`).
3. **Posted transfer/manufacture.** Submitted Stock Entry totals are compared with Work Order quantity
   plus Work Order allowance; transfer falls back to the extra-material allowance when the Work Order
   allowance is zero. Additional transfer has its own parent-level ceiling
   (`manufacturing/doctype/work_order/services/status.py:193-246`,
   `manufacturing/doctype/work_order/work_order.py:571-594`).

Operation completion separately permits completed + process loss through the Work Order allowance
(`manufacturing/doctype/work_order/services/operations.py:270-300`). Job Card creation has yet another
aggregate ceiling (§6).

None of the Sales Order, Production Plan or Job Card aggregate checks locks the demand row or allocation
set before the later insert/write. Two requests can both observe remaining quantity and both pass.

> **Invariant M14 — atomic quantity allocation.** Demand→Work Order, Work Order→execution lot,
> operation-predecessor and serial/batch allocations are rows with non-negative residual constraints and
> unique source/ordinal keys. Allocation and ceiling validation occur under one owner-row lock or
> serializable transaction. Global percentages are snapshotted policy inputs, not mutable values reread
> at each stage.

---

## 4. Work Order submit, stop, close and cancel

### 4.1 Submit ordering

`before_submit` may create finished-good Batches and inactive Serial Nos. Batch splitting follows Work
Order batch size; serial rows are bulk inserted and associated with generated batches
(`manufacturing/doctype/work_order/work_order.py:721-842`). After the Work Order and children are stored
as submitted, `on_submit` performs, in order:

1. warehouse validation;
2. Sales Order `work_order_qty` update, using either combined-plan or ordinary logic;
3. Production Plan ordered quantity/status;
4. raw-material Bin reservation projection;
5. Material Request ordered/per-ordered projection;
6. finished-good planned quantity and MR requested/Bin projection;
7. Job Card creation;
8. explicit Stock Reservation Entry transfer/creation when enabled;
9. subcontracting-inward received-item allocation.

(`manufacturing/doctype/work_order/work_order.py:612-633`). These writes share the request transaction,
so an escaped exception normally rolls them back. However, the sequence makes upstream and Bin
projections visible to later in-transaction hooks before Job Card generation or reservation succeeds.

### 4.2 Status is a mutable projection

Submitted status starts from transfer/skip-transfer state, becomes Completed when produced + process
loss reaches quantity, and becomes In Process when any operation is not Pending. Reservation status is
overlaid only on Not Started (`manufacturing/doctype/work_order/services/status.py:88-191`). The
reservation overlay skips every material row whose reserved quantity is zero; one fully reserved row
plus one completely unreserved row can therefore report **Stock Reserved**, not Partially Reserved
(`manufacturing/doctype/work_order/services/status.py:176-190`).

`stop_unstop` and `close_work_order` are direct status commands, not document-state transitions. Stop
rewrites status and planned quantity. Close rejects only submitted Job Cards currently labelled Work In
Progress, then runs the same upstream/Bin/reservation roll-down as cancellation
(`manufacturing/doctype/work_order/work_order.py:1122-1185`). Open or Completed cards do not block close.

### 4.3 Cancel and dependency policy

Cancellation rejects a Stopped Work Order and any submitted Stock Entry carrying its `work_order` link.
It then writes Cancelled and, in order, reverses Sales Order, Material Request, FG planned quantity,
Production Plan, raw-material Bin, explicit reservations and subcontract-inward projections
(`manufacturing/doctype/work_order/work_order.py:635-658`,
`manufacturing/doctype/work_order/work_order.py:844-861`). Draft Job Cards are not deleted. Other
submitted links depend on Frappe's generic backlink check rather than one production dependency model.

This creates three materially different endings:

- **stop** leaves docstatus submitted, preserves most links and only changes planned quantity;
- **close** leaves docstatus submitted but removes several demand/reservation projections;
- **cancel** changes docstatus and is explicitly blocked only by submitted Stock Entry.

> **Invariant M15 — explicit production lifecycle and dependencies.** `released`, `started`,
> `completed`, `closed` and `cancelled/reversed` have one transition table. A dependency table records
> reservations, execution lots, quality evidence and material/output postings. Close is allowed only by
> an explicit residual policy; cancellation either reverses every dependent posting in dependency order
> or is rejected with the complete blocker set. Status is derived from those facts.

---

## 5. Material quantities, reservations and Bin projections

### 5.1 Submitted Stock Entry rows are the material source

After relevant Stock Entry submit **or cancel**, Work Order required quantities are recomputed, not
incremented: return transfers; Manufacture/Material Consumption source quantities; ordinary transfers;
Bin production reservation; then explicit reservation consistency
(`manufacturing/doctype/work_order/services/required_items.py:30-55`). Alternative material attribution
uses `original_item` and transfer aggregates group by `(item_code, original_item)` before folding to the
required code (`manufacturing/doctype/work_order/services/required_items.py:133-234`).

The resulting mutable fields are written directly on each Work Order Item. Consumption is:

```text
consumed(item) = submitted Manufacture/Material Consumption source transfer_qty
                 where item_code = item OR original_item = item
                 + returned_qty
```

(`manufacturing/doctype/work_order/services/required_items.py:196-264`,
`manufacturing/doctype/work_order/services/reservation.py:662-683`).

⚠️ Aggregates are keyed by item code, then the complete value is written to every matching Work Order
row. If additional material creates duplicate item rows, each duplicate can receive the same total.
Reservation mapping similarly collapses required rows to `{item_code: row.name}`, so the last duplicate
wins (`manufacturing/doctype/work_order/services/required_items.py:133-149`,
`manufacturing/doctype/work_order/services/reservation.py:206-234`).

Material-transferred FG-equivalent quantity normally sums submitted transfer Stock Entry
`fg_completed_qty`. Pick List/MR flows can leave that field zero; the fallback computes the minimum
transferred fraction across included required item codes and multiplies by Work Order quantity
(`manufacturing/doctype/work_order/services/required_items.py:152-194`). Job Card transfer mode uses the
minimum completed operation quantity instead (§8).

### 5.2 Two reservation representations

Legacy `Bin.reserved_qty_for_production` is a live aggregate over open submitted Work Order Items:

```text
transfer required: required_qty - transferred_qty
skip transfer:     required_qty - consumed_qty
```

Stopped, Completed and Closed Work Orders are excluded
(`manufacturing/doctype/work_order/services/reservation.py:685-730`). `Bin` then recalculates:

```text
projected = actual + ordered + indented + planned
            - reserved_sales - reserved_production
            - reserved_subcontract - reserved_production_plan
```

and directly rewrites production reservation, plan reservation and projected quantity
(`stock/doctype/bin/bin.py:78-151`).

Explicit `Stock Reservation Entry` is a second representation. Work Order submission may transfer plan
or subcontract-inward reservations, or create new ones; Stock Entry transfer and consumption update
`transferred_qty`, `consumed_qty`, serial/batch consumption, status and Bin reserved stock. Manufacture
can reserve finished goods against Sales Order, subassembly, inward order or Job Card; cancellation
finds records by the creating Stock Entry's `from_voucher_no`
(`manufacturing/doctype/work_order/services/reservation.py:58-190`,
`manufacturing/doctype/work_order/services/reservation.py:191-452`,
`manufacturing/doctype/work_order/services/reservation.py:547-618`). Subcontract-send quantity is
reconstructed indirectly through Job Card → Purchase/Subcontracting Order → submitted Send to
Subcontractor Stock Entry (`manufacturing/doctype/work_order/services/reservation.py:454-545`).

The Work Order Bin path does not lock the Bin row. Production Plan's comparable refresh explicitly loads
Bin `for_update=True`, demonstrating the missing serialization
(`manufacturing/doctype/production_plan/production_plan.py:343-355`). FG `planned_qty` is another
unlocked aggregate of `qty - produced_qty`, written through `update_bin_qty`
(`stock/stock_balance.py:256-287`).

> **Ours — one reservation ledger.** A reservation names owner line, item, warehouse, quantity,
> optional serial/batch, stage and transfer chain. Transfer and consumption create allocation events;
> they never maintain a parallel Bin reservation fact. `available_to_allocate` and planned supply are
> transactionally consistent views over stock postings, demand and reservation rows.

---

## 6. Job Card creation and splitting

Work Order submission iterates operation rows. Each operation repeatedly calls the batch splitter and
inserts cards; capacity planning optionally schedules each card and writes the last scheduled segment
back to the Work Order operation (`manufacturing/doctype/work_order/services/operations.py:88-129`).
Doc 34 §§3–5 covers scheduling, calendars and overlap internals; this document treats scheduled rows as
the output projection only.

If the Operation master does not request batch cards, one card receives the requested/Work Order
quantity. Otherwise:

```text
card_qty = min(remaining_qty, operation.batch_size)
remaining_qty -= card_qty
```

For serialized outputs, the splitter reads all Work Order serials, subtracts serials already present on
non-cancelled cards for that operation row, sorts and takes the first `card_qty`
(`manufacturing/doctype/work_order/mapper.py:321-365`). These reads are unlocked; concurrent creators
can allocate the same serials.

Each card copies Work Order/operation identity, sequence, Workstation/Type and company-currency hour
rate, plus proportional duration and warehouses:

```text
Job Card.time_required = WO operation minutes / WO.qty × card_qty
```

It also copies semi-finished BOM/output, subcontract and material-transfer flags, derives proportional
materials when transfer is against Job Card or semi-finished tracking is enabled, derives secondary
outputs, optionally schedules, and inserts with `ignore_mandatory`
(`manufacturing/doctype/work_order/mapper.py:391-468`). Manual `make_job_card` validates requested
quantity against caller-supplied pending quantity, but disables capacity planning; it uses the same
splitter (`manufacturing/doctype/work_order/mapper.py:291-389`).

After each Job Card update, the controller sums `for_quantity` for all non-cancelled cards on the same
operation row, subtracts already-completed Work Order operation quantity, and compares with Work Order
quantity plus allowance (`manufacturing/doctype/job_card/job_card.py:214-267`). This is an unlocked
check after the child has been written. Two concurrent inserts can both pass.

> **Invariant M16 — execution-lot identity.** Job/execution lots are deterministic allocations keyed by
> `(work_order_operation_id, ordinal)` with allocated output quantity and serial/batch set. Their total
> cannot exceed the operation authorisation under a database constraint/locked allocator. An
> unscheduled lot is explicit state; manual creation never silently bypasses reservation.

---

## 7. Job Card validation, time logs, sequencing and status

### 7.1 Validation and operation identity

The controller runs: time-log validation and totals; hold normalization; status derivation;
operation-row resolution; sequence gate; sub-operation copy/roll-up; Work Order openness; and employee
projection. Submitted semi-finished cards additionally require transferred material and nonzero
completion unless subcontracted (`manufacturing/doctype/job_card/job_card.py:144-198`).

`operation_id` is checked against children of the named Work Order. If an Operation occurs once it is
inferred; if it occurs multiple times, a draft must select the exact row
(`manufacturing/doctype/job_card/job_card.py:1358-1390`). Closed or Stopped Work Orders reject Job Card
changes (`manufacturing/doctype/job_card/job_card.py:1455-1475`).

### 7.2 Actual logs are mutable children

Each closed actual row requires start ≤ end, is overlap-checked, and computes:

```text
time_in_mins = (to_time - from_time in hours) × 60
```

Parent total minutes are summed; completed quantity is summed directly only when there are no
sub-operations (`manufacturing/doctype/job_card/job_card.py:319-396`). `before_save` derives expected
and actual min/max dates, leaving actual end blank when the last log is open; process loss is reset to:

```text
process_loss = for_quantity - total_completed_qty - pending_qty
```

only when completion is positive and below requested quantity
(`manufacturing/doctype/job_card/job_card.py:967-1003`). A caller-supplied loss passed to the completion
API is therefore overwritten by save-time derivation.

Timer APIs are direct database mutation paths. Start/pause/resume/complete append rows with `db_update`,
close existing rows directly, `db_set` pause/status/totals and only then save/revalidate the parent
(`manufacturing/doctype/job_card/job_card.py:1392-1608`). Submitted cards cannot use the timer API, but
the schema and `validate_time_logs(save=True)` permit submitted-card time totals to be rewritten through
other save paths (`manufacturing/doctype/job_card/job_card.py:319-369`). Job Card execution is not an
append-only event stream.

### 7.3 Sub-operations and sequence

Immediate Operation children are copied once, without configured minutes. Actual rows are grouped by
sub-operation; status is Pending/WIP/Complete/Pause. Minutes and quantity are divided by the number of
distinct employees, and parent completed quantity is the **minimum** child completed quantity
(`manufacturing/doctype/job_card/job_card.py:270-318`,
`manufacturing/doctype/job_card/job_card.py:706-768`). Grandchildren do not participate.

For non-new, non-corrective cards, every lower-sequence Work Order operation must have completion and
the current aggregate cannot exceed predecessor completion. Same-sequence rows do not gate one another
(`manufacturing/doctype/job_card/job_card.py:1391-1439`). The current quantity is an unlocked sum of
submitted siblings plus this in-memory card.

### 7.4 Completion and status

Submission requires a time log except subcontracted semi-finished cards; `enforce_time_logs` requires
both endpoints. A paused card is rejected, and at field precision:

```text
completed + process_loss + pending = for_quantity
```

(`manufacturing/doctype/job_card/job_card.py:893-990`). Status is recalculated from docstatus, logs,
material transfer, pause, completion and manufacture. A submitted semi-finished card distinguishes
`To Manufacture` from `Completed`; a normal submitted card can be Completed from completed + loss even
without items (`manufacturing/doctype/job_card/job_card.py:1288-1356`). Workstation scalar status is a
separate direct-write projection over draft cards, as analysed in doc 34 §10.

> **Invariant M17 — append-only actual work.** Start, pause, resume, stop, employee participation,
> output, pending and loss are timestamped events referencing one execution lot and actor. Corrections
> reverse/supersede events. Operation completion and actual intervals are transactional aggregates;
> submitted execution evidence is never edited in place or divided by an inferred employee count.

---

## 8. Job Card submit/cancel, operation roll-up and corrective work

Submit ordering is quality gate → material-transfer gate → stopped/hold/time/completion validation →
Work Order roll-up → transferred-quantity recompute. Cancel performs the Work Order and transfer
recomputations after docstatus changes (`manufacturing/doctype/job_card/job_card.py:826-841`).

For ordinary cards, the roll-up sums submitted non-corrective siblings by exact Work Order operation:
completed quantity, time, process loss and pending quantity. It takes min/max actual log dates, rewrites
the Work Order Operation, may replace its Workstation and current hourly rate, recalculates operation
status/cost/Work Order dates, sets `ignore_validate_update_after_submit`, and saves the submitted Work
Order (`manufacturing/doctype/job_card/job_card.py:1005-1159`). Concurrent sibling submit/cancel can
both read old aggregates and last-write a stale child snapshot.

Semi-finished tracking has another path: operation completion is the sum of
`max(manufactured_qty, completed_qty)` across submitted cards. If the operation output equals the Work
Order production item, parent `produced_qty` and status are directly written
(`manufacturing/doctype/job_card/job_card.py:1041-1064`).

Cancellation is blocked when Work Order produced quantity is greater than the remaining submitted
operation completed + loss + pending total; the message requires Manufacture entries to be cancelled
first (`manufacturing/doctype/job_card/job_card.py:1079-1095`). Generic backlinks provide additional,
less explicit blockers.

A corrective card is cloned from another card, stores `for_job_card`/`for_operation`, clears logs,
employees, items and sub-operations, then rebuilds them
(`manufacturing/doctype/job_card/mapper.py:159-194`). It bypasses normal operation sequencing and is
excluded from completion aggregates. When the global setting is enabled, submitted corrective minutes
are repriced as `minutes / 60 × current card hour_rate`, accumulated into Work Order corrective cost,
and saved through the update-after-submit bypass
(`manufacturing/doctype/job_card/job_card.py:1005-1077`). There is no separate generic backend mapper
for an additional out-of-route operation in this revision; `additional_operating_cost` is a mutable Work
Order amount, while corrective Job Card is the special execution path.

> **Ours.** Corrective/rework operations are explicit route-exception nodes with authoriser, reason,
> predecessor/output links and snapshotted resource rates. Additional cost is derived from usage-cost
> events, never an unexplained scalar. Rework quantity has its own allocation and cannot evade route
> dependencies or output ceilings.

---

## 9. Material transfer, consumption, manufacture and quality

### 9.1 Job Card materials and Stock Entry callbacks

Job Card required material is copied from Work Order required rows matching operation or operation-row,
scaled by `card_qty / Work Order.qty`; corrective cards take all rows
(`manufacturing/doctype/job_card/job_card.py:770-825`). Material Transfer submit **and cancel** recompute
card transfer quantity, each linked Job Card Item transfer aggregate and status, then update Work Order
quantity/status/dates (`stock/doctype/stock_entry/services/material_transfer.py:367-395`). Manufacture
submit/cancel recomputes Job Card Item consumption, manufactured quantity and Work Order operation, then
Work Order produced/planned/status projections (`stock/doctype/stock_entry/services/manufacturing.py:783-810`).
Subcontracting Receipt submit/cancel similarly recomputes manufactured quantity from submitted receipt
items (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:205-226`).

Job Card transfer/consumption children are therefore mutable caches over submitted downstream rows:
`frappe.db.set_value` writes them directly by child identity
(`manufacturing/doctype/job_card/job_card.py:1161-1259`). For non-semi-finished Work Orders transferred
against Job Card, Work Order material-transferred quantity is not a Stock Entry sum: it is the minimum
`completed + process_loss` among all operations, once every operation is nonzero
(`manufacturing/doctype/job_card/job_card.py:1260-1286`).

A submitted semi-finished card can build a Manufacture Stock Entry for remaining quantity and
unconsumed process loss. It links Job Card, Work Order and semi-FG BOM, populates operation/additional
cost and secondary outputs, then saves or auto-submits
(`manufacturing/doctype/job_card/job_card.py:1619-1704`).

### 9.2 Job Card quality is distinct from transaction Quality Inspection

Job Card submission requires quality evidence only when **both** the BOM `inspection_required` and the
exact Work Order Operation `quality_inspection_required` are true. It then requires the card's single
Quality Inspection link and applies Stock Settings Stop/Warn policy to draft or rejected inspection
(`manufacturing/doctype/job_card/job_card.py:842-890`). This is an in-process operation gate.

It is separate from Stock Entry's transaction-level inspection. Work Order→Manufacture mapping copies
BOM inspection requirement to Stock Entry, whose ordinary validation calls `validate_inspection` before
posting; submit/cancel later rewrites QI references on Stock Entry item rows
(`manufacturing/doctype/work_order/mapper.py:260-282`,
`stock/doctype/stock_entry/stock_entry.py:287-315`,
`stock/doctype/stock_entry/stock_entry.py:1528-1541`). One operation may therefore need in-process Job
Card QI and the resulting stock transaction may independently need row-level QI.

The Shop Floor helper creates and submits an `In Process` QI with `reference_type = Job Card`, fills
operation-template readings and links it back. Its existing-inspection check is read-then-create without
a uniqueness constraint (`manufacturing/page/shop_floor/shop_floor.py:168-273`). Generic QI backlink
logic updates the Job Card only when `Job Card.production_item == QI.item_code`; that can miss a
semi-finished `finished_good`, which is why the helper explicitly sets the card link
(`stock/doctype/quality_inspection/quality_inspection.py:77-85`,
`stock/doctype/quality_inspection/quality_inspection.py:199-230`).

> **Invariant M18 — quality evidence gates the exact transition.** A quality decision names operation
> execution/output lot, inspection plan revision, sample/readings, inspector and disposition. A unique
> accepted decision is required by the configured operation/output transition. Transaction receipt or
> stock-movement inspection is a separate gate with its own subject; neither is inferred from a mutable
> single link on the other document.

---

## 10. Mapper and command surface — every output

### 10.1 Work Order-origin outputs

| Output | Backend behavior |
|---|---|
| Unsaved Work Order | `make_work_order` resolves default/variant BOM, creates the parent and optionally compiles items/operations (`manufacturing/doctype/work_order/mapper.py:104-153`). |
| Stock Entry | `make_stock_entry` returns an unsaved Material Transfer, Manufacture, Material Consumption or Disassemble entry; copies Work Order/BOM/policy/warehouses and defaults remaining FG quantity (`manufacturing/doctype/work_order/mapper.py:228-288`). |
| Job Cards | `make_job_card` validates selected operation quantity, splits batches/serials and **inserts** cards; it is a command, not a pure mapper (`manufacturing/doctype/work_order/mapper.py:290-468`). |
| Pick List | maps only submitted pending required rows, scales by requested FG quantity and caps by remaining transfer, then resolves item locations (`manufacturing/doctype/work_order/mapper.py:473-524`). |
| Material Request | maps a submitted Work Order to Material Transfer request with pending `required - transferred` rows and WIP target (`manufacturing/doctype/work_order/mapper.py:526-558`). |
| Stock return | creates an unsaved return Material Transfer for Manufacture and derives returnable transferred materials (`manufacturing/doctype/work_order/mapper.py:560-579`). |
| Reverse-built BOM | `Work Order.make_bom` reads submitted Manufacture consumption and copies the current Work Order operations into an unsaved BOM (`manufacturing/doctype/work_order/work_order.py:947-975`). |

### 10.2 Job Card-origin outputs

| Output | Backend behavior |
|---|---|
| Subcontract Purchase Order | maps remaining semi-FG quantity through Subcontracting BOM service-item ratio; links Job Card, FG, semi-FG BOM and supplier/target warehouses (`manufacturing/doctype/job_card/mapper.py:14-53`). |
| Material Request | maps all Job Card Items at full required quantity, retaining Job Card/item links and WIP target; unlike the Stock Entry mapper it does not subtract transferred quantity (`manufacturing/doctype/job_card/mapper.py:55-84`). |
| Material Transfer Stock Entry | maps positive items at pending `required - transferred`, sets pending non-negative FG quantity, Job Card item links, WIP and prior-operation serial/batch (`manufacturing/doctype/job_card/mapper.py:86-157`). |
| Corrective Job Card | clones the source identity, marks/links correction, clears execution/material children and rebuilds sub-operations/materials (`manufacturing/doctype/job_card/mapper.py:159-194`). |
| Semi-FG Manufacture Stock Entry | builds remaining output/process-loss manufacture, adds costs and secondary items, then saves or submits (`manufacturing/doctype/job_card/job_card.py:1619-1704`). |

The surface mixes pure document builders, saving helpers and inserting commands. The caller cannot infer
transaction or idempotency behavior from the `make_*` name. Job Card Material Request also requests full
required quantity repeatedly unless downstream user logic corrects it, while direct Stock Entry uses the
pending amount.

> **Ours — command/query separation.** Builders are pure previews. Commands have explicit names,
> idempotency keys, permissions and atomic effects, and return persisted IDs. Every mapped line carries
> source allocation identity; repeated invocation returns the same command result or a stated new
> revision, never another full-quantity request by accident.

---

## 11. Cross-document roll-ups, posting order and races

### 11.1 Upstream and Bin roll-ups

Work Order submit/cancel and Stock Entry callbacks rewrite:

- Production Plan item/subassembly `ordered_qty` as submitted Work Order sums, plan produced/pending,
  subassembly `wo_produced_qty`, total produced and status
  (`manufacturing/doctype/work_order/services/status.py:285-404`,
  `manufacturing/doctype/production_plan/production_plan.py:245-262`);
- Sales Order Item `work_order_qty` from submitted non-Closed Work Orders and `produced_qty` from
  submitted linked Work Order projections
  (`manufacturing/doctype/work_order/services/status.py:405-459`,
  `selling/doctype/sales_order/sales_order.py:785-801`);
- Manufacture Material Request Item `ordered_qty` and parent `per_ordered`—despite the method name
  `update_completed_qty`—from submitted non-Closed Work Orders
  (`stock/doctype/material_request/material_request.py:337-407`);
- raw-material production reservation and FG planned quantity in Bin (§5).

Combined-Sales-Order logic is not an aggregate: submit writes each plan-reference quantity, while
cancelling any one Work Order writes zero for every matching reference. Multiple partial Work Orders can
therefore produce an incorrect `work_order_qty`
(`manufacturing/doctype/work_order/services/status.py:436-449`).

### 11.2 Stock posting order

Stock Entry submit first invokes purpose-specific Work Order/Job Card recomputation, then adjusts
reservations, posts Stock Ledger, creates WIP/FG reservations, updates related documents, posts GL,
reposts future entries and finally relinks Quality Inspection. Cancel likewise runs purpose callbacks
and several mutable projections before cancelling stock/GL evidence
(`stock/doctype/stock_entry/stock_entry.py:331-389`). There is no explicit commit, so normal transaction
rollback protects an escaped failure; nevertheless the domain counters are calculated before the stock
posting they summarize.

For Manufacture, callback order is Job Card item consumption → manufactured quantity → Work Order
operation, then Work Order quantities → planned Bin → status/required items → dates
(`stock/doctype/stock_entry/services/manufacturing.py:783-810`). This recompute-from-`docstatus = 1`
pattern is mostly idempotent and cancellation-friendly, but not serialized.

### 11.3 Direct mutation and race inventory

Direct writes include Work Order status/quantities; required-child transfer/consume/return; Work Order
operation completion; Job Card status/material quantities; Production Plan/Sales Order/MR children;
reservation rows; and Bin projected quantities. Additional required rows and operation/corrective
roll-ups set `ignore_validate_update_after_submit` and save submitted Work Orders
(`manufacturing/doctype/work_order/services/required_items.py:266-301`,
`manufacturing/doctype/job_card/job_card.py:1066-1118`). These paths bypass the narrow schema list of
fields editable after submission, ordinary field validation and often Version/audit hooks.

No Work Order/Job Card owner lock was found around:

- Sales Order or Production Plan overproduction check then Work Order insert;
- Job Card aggregate quantity check then insert;
- serial selection then card insert;
- sibling Job Card aggregate then Work Order operation save;
- Stock Entry aggregate then Job Card/Work Order child `set_value`;
- Work Order Bin aggregate then Bin rewrite;
- Shop Floor existing-QI check then create.

A later submit/cancel often recomputes and can heal a stale projection, but correctness should not depend
on an unrelated later transaction.

### 11.4 Evidence boundary

| Representation | Classification |
|---|---|
| Stock Entry + detail and resulting SLE/GL | posting command/evidence; cancellation produces reversal/cancel state, not merely a counter change |
| Submitted Job Card parent | execution approval/completion document, but still mutable through status/totals and update-after-submit paths |
| Job Card Time Log | intended actual-work evidence, but mutable child rows written directly; not immutable evidence |
| Quality Inspection/readings | quality decision document; backlink is a mutable projection |
| Work Order Item/Operation progress | mutable aggregate/cache over Stock Entry and submitted Job Card rows |
| Work Order produced/transfer/loss/status/dates/cost | mutable projection |
| SO/MR/Production Plan quantities/status | mutable projections |
| Stock Reservation Entry | durable allocation record, but transferred/consumed/status are mutable and overlap legacy Bin reservation |
| Bin planned/reserved/projected fields | mutable aggregate cache |

> **Invariant M19 — authoritative events and rebuildable projections.** Material issue/return,
> consumption, output, loss, actual work, quality disposition and reservation allocation are immutable
> event/allocation rows with reversal links. Work Order, operation, demand and inventory summaries are
> projections carrying event position and `computed_at`; they can be rebuilt and atomically replaced.
> Projection writes never precede or masquerade as the evidence they summarize.

> **Invariant M20 — serializable projection ownership.** Each synchronous aggregate update locks one
> declared owner (Work Order operation, demand line, reservation or item+warehouse projection key), or
> is emitted to an idempotent projector after evidence commits. Direct `db_set` cannot bypass domain
> validation/audit. A reconciliation job detects projection drift but is not the normal concurrency
> mechanism.

---

## 12. Findings and decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Work Order as production authorisation linked to demand/BOM | **Adopt concept** | immutable released Work Order naming BOM/route/policy revisions |
| Required material and operation snapshots | **Adopt intent** | one compiler; source revision/fingerprint on every line |
| Ordinary save resetting quantities only | **Reject (stale structure)** | compile complete snapshot atomically; change requires revision |
| Multi-level BOM material option | **Adopt as explicit policy** | named expansion policy from doc 33's one graph function |
| Production Plan/MR `ignore_validate` Work Order creation | **Reject** | one release service for every origin |
| Work Order sequence validation | **Adopt minimum** | route DAG already validated; execution references stable nodes |
| Three independent overproduction checks | **Unify** | locked allocation ledger and one snapshotted allowance policy |
| Submitted Work Order creating Job Cards | **Adopt automation** | deterministic execution-lot ordinals and idempotent creation |
| Batch-size splitting | **Adopt** | fixed-decimal lot allocator with unique source/ordinal |
| Unlocked serial subtraction | **Reject (race)** | unique serial allocation under lock |
| Manual Job Card silently unscheduled | **Reject ambiguity** | explicit unscheduled queue or atomic reservation |
| Job Card exact `operation_id` | **Adopt** | FK to immutable Work Order operation node |
| Actual interval and completion logs | **Adopt domain facts** | append-only work events; correction by reversal/supersession |
| Employee-count division of sub-operation totals | **Reject assumption** | labour and machine intervals separate from output events |
| Minimum mandatory sub-operation quantity | **Adopt when configured** | explicit dependency/all-required-node completion rule |
| Sequence gate by lower integer | **Replace** | DAG predecessor allocation/completion constraint |
| Derived process loss balance | **Adopt formula when policy says residual** | explicit output/loss event totals with non-negative constraint |
| Job Card quality requiring BOM **and** operation flags | **Make policy explicit** | operation/output quality-gate revision |
| Job Card QI separate from Stock Entry QI | **Adopt distinction** | typed subjects and transitions; no overloaded backlink |
| Corrective Job Card | **Adopt concept** | authorised rework node with reason, inputs, rates and allocation |
| Additional operating cost scalar | **Reject as evidence** | costed resource/service usage event |
| Transfer/consume/manufacture recompute from submitted rows | **Adopt algorithm** | deterministic projector over immutable movements |
| Duplicate material roll-up by item code | **Reject (misallocation)** | aggregate by allocation/source-line identity and warehouse/UOM |
| Work Order and explicit SRE reservation representations | **Reject dual truth** | one reservation/allocation ledger |
| Bin production/planned/projected quantities | **Adopt only as cache** | atomically rebuilt item+warehouse projection |
| Work Order submit updating SO/Plan/MR/Bin before card creation | **Reject ordering dependency** | write authorisation/allocations atomically; project after commit |
| Combined-SO cancellation writing every reference to zero | **Reject (bug)** | aggregate from surviving allocation rows |
| `actual or planned` operation cost | **Reject** | separate committed forecast and actual usage totals (doc 34) |
| `db_set`/`set_value` roll-ups | **Reject as domain writes** | typed audited projector with owner lock/idempotency key |
| `ignore_validate_update_after_submit` child mutation | **Reject** | immutable source + append-only evidence + rebuildable projection |
| Stop, close and cancel as overlapping ad hoc paths | **Reject** | one lifecycle transition/dependency table |
| Work Order explicit Stock Entry cancel blocker | **Adopt minimum, strengthen** | complete dependency graph and ordered reversal plan |
| Mapper names mixing preview/insert/save/submit | **Reject boundary** | pure preview queries and explicit idempotent commands |

The eight production invariants added here are **M13–M20**: immutable execution authorisation, atomic
quantity allocation, explicit lifecycle/dependencies, execution-lot identity, append-only actual work,
quality evidence tied to the exact transition, authoritative production events with rebuildable
projections, and serializable projection ownership. Together with M1–M12 they separate recipe/route,
schedule, execution and posting facts before doc 36 moves into Production Plan and MPS.

---

Cross-references: doc 10 (fulfilment aggregates and lost updates), doc 16 (reservation and Bin), doc 20
(`db_set` audit gaps), doc 22 (locking/jobs), doc 33 (immutable BOM revisions and explosion), doc 34
(route snapshots, capacity, calendars and resource cost), `docs/design/FINAL-SCHEMA.md` (fixed-decimal,
immutable-event and projection principles). Next: doc 36, Production Planning and MPS.
