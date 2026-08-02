# 34 — Operations, Routing, Workstations and Capacity

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This document follows the BOM source/projection boundary from doc 33 into execution planning. It covers
all eight Manufacturing parents in this area: `Operation`, `Routing`, `Workstation`, `Workstation Type`,
`Workstation Operating Component`, `Downtime Entry`, `Plant Floor`, and `Manufacturing Settings`; the
passive child rows behind them; and the BOM, Work Order, Job Card and Manufacture Stock Entry paths that
actually consume those masters.

The central finding is that ERPNext does not have one capacity model. It has a chain of mutable copies:
an Operation supplies default minutes, a Routing stores reusable `BOM Operation` rows, a BOM copies a
subset, a Work Order rescales another copy, and Job Cards persist planned and actual intervals. Capacity
is then enforced by unlocked read-before-write overlap queries over those Job Card children. The
calendar splitter, manual time-log validator and Workstation Type allocator implement different notions
of availability; `Downtime Entry` is not consulted by any of them. Cost follows a parallel chain from
mutable workstation component rates into BOM/Work Order snapshots and finally remaining-cost allocation
on Manufacture Stock Entries.

Our boundary is therefore the same as doc 33: approved route and resource revisions are immutable
sources; a schedule is a versioned, atomically reserved projection; actual work and downtime are
append-only events; and production valuation consumes explicit fixed-decimal cost snapshots rather than
re-reading a mutable machine master.

---

## 1. Data model — reusable definitions, copied execution rows and interval projections

### 1.1 `Operation` and immediate sub-operations

`Operation` is a mutable setup master. Besides name/description and a default Workstation, it stores a
work instruction, quality-inspection template, corrective-operation flag, Job Card batch-splitting flag
and batch size, immediate `Sub Operation` children, and a copied total operation time
(`manufacturing/doctype/operation/operation.py:9-33`). Its validation is small but mutating: blank
description becomes the Operation name, each direct child Operation may occur once, a direct self-child
is rejected, and:

```text
Operation.total_operation_time = Σ Sub Operation.time_in_mins
```

(`manufacturing/doctype/operation/operation.py:35-58`). `Sub Operation` is a passive child carrying
`operation`, non-negative minutes and description (`manufacturing/doctype/sub_operation/sub_operation.py:7-24`).

The relation is not a recursively validated graph. `A → B → A` and longer cycles are accepted because
only `self.name == row.operation` is tested. Zero-minute children are accepted, and the parent total is
a float sum with no explicit rounding. Runtime expansion is intentionally only one level: a Job Card
queries the selected Operation's direct child rows and copies operation/index, not configured child
minutes or grandchildren (`manufacturing/doctype/job_card/job_card.py:270-281`). A `BOM Operation`
fetches `Operation.total_operation_time` only when its own time is empty, so later edits to the master do
not continuously update Routing, BOM or Work Order copies.

> **Invariant M7 — versioned process definition.** An approved route revision owns ordered operation
> nodes and explicit dependency edges. Nodes have stable IDs; duration, batch rule, inspection rule,
> work instruction and required resource capability are immutable within the revision. The database
> rejects self and transitive cycles. Sub-steps are either recursively valid nodes or an explicitly
> one-level checklist, never a partly-recursive relation.

### 1.2 `Routing` does not have a Routing-specific child type

`Routing` stores `routing_name`, `disabled` and `operations`; those rows are the same passive
`BOM Operation` child type used by BOM, distinguished only by `parenttype = 'Routing'`
(`manufacturing/doctype/routing/routing.py:11-24`,
`manufacturing/doctype/bom_operation/bom_operation.py:7-47`). That shared row can carry sequence,
Operation, Workstation or Workstation Type, minutes, fixed/batch costing flags, semi-finished output and
BOM, subcontract/quality flags, source/WIP/FG warehouses, and transaction/base costs. Most of those
fields make sense only once the row belongs to a BOM, but the table itself does not enforce a per-parent
shape.

This is a template, not a revision. It is editable in place, and existing BOM rows are snapshots.
`disabled` is just a field on the parent: neither Routing validation nor the server-side BOM-copy path
rejects a disabled Routing (`manufacturing/doctype/routing/routing.py:11-33`,
`manufacturing/doctype/bom/bom.py:488-525`).

### 1.3 Workstation, Type, costs and calendars

`Workstation` is the concrete capacity resource. It stores identity/type, Plant Floor, disabled/status,
parallel Job Card capacity, warehouse, per-hour `Workstation Cost` children and net hour rate, working-
hour children and total hours, a Holiday List, and status images (`manufacturing/doctype/workstation/workstation.py:39-68`).
`Workstation Working Hour` is passive and carries start/end and an `enabled` flag
(`manufacturing/doctype/workstation_working_hour/workstation_working_hour.py:7-23`).

`Workstation Type` stores only identity, description, the same cost-child shape and an aggregate hour
rate (`manufacturing/doctype/workstation_type/workstation_type.py:10-24`). It is a cost template and
selection label, not a resource calendar or capacity pool. Its helper returns every concrete
Workstation of that type ordered by creation, without filtering disabled state, operational status,
calendar, Plant Floor or capacity (`manufacturing/doctype/workstation_type/workstation_type.py:26-58`).

`Workstation Operating Component` is a naming/account master whose server controller is otherwise
passive (`manufacturing/doctype/workstation_operating_component/workstation_operating_component.py:7-25`).
Its company-account children are also passive and permit an optional expense account
(`manufacturing/doctype/workstation_operating_component_account/workstation_operating_component_account.py:7-24`).
A `Workstation Cost` links one such component to an hourly amount. Workstation and Workstation Type
reject duplicate component links in their own cost table, but the component master does not enforce one
account row per company or validate that the account belongs to that company.

### 1.4 Planned and actual intervals are Job Card child projections

Capacity does not have its own reservation table. A draft Job Card owns `Job Card Scheduled Time`
children `(from_time, to_time, time_in_mins)`; actual work is stored in `Job Card Time Log` children,
which add employee, operation/sub-operation and completed quantity
(`manufacturing/doctype/job_card_scheduled_time/job_card_scheduled_time.py:8-24`,
`manufacturing/doctype/job_card_time_log/job_card_time_log.py:7-27`). The Job Card also copies its
Work Order operation ID, sequence, concrete Workstation/Type, expected and actual dates, required and
completed quantities, minutes and hourly rate (`manufacturing/doctype/job_card/job_card.py:60-151`).

These rows are mutable children, not immutable reservations/events. Draft scheduled rows participate in
capacity only while their parent has no actual minutes; actual rows from any non-cancelled Job Card take
over as the other overlap source (§4). There is no database exclusion constraint connecting either
child table to Workstation capacity.

### 1.5 The remaining four parents

- `Downtime Entry` stores Workstation, operator, start/end, calculated downtime minutes, reason and
  remarks; its only hook calculates a float duration (`manufacturing/doctype/downtime_entry/downtime_entry.py:8-38`).
- `Plant Floor` stores only optional company/warehouse and floor identity. Its parent controller has no
  validation hook; it is a dashboard/API container (`manufacturing/doctype/plant_floor/plant_floor.py:10-23`).
- `Manufacturing Settings` is a mutable Single containing material/BOM rules, overproduction and
  transfer allowances, Job Card/corrective-cost flags, and the five capacity controls discussed in §8
  (`manufacturing/doctype/manufacturing_settings/manufacturing_settings.py:10-47`). Its only save-time
  normalization clears component-quantity validation when backflush is no longer BOM-based
  (`manufacturing/doctype/manufacturing_settings/manufacturing_settings.py:48-55`).

---

## 2. Routing lifecycle, exact formulas and the copy chain

### 2.1 Routing save: row cost and non-decreasing sequence

On validation, Routing calculates each operation before assigning sequence IDs. A falsey row rate is
looked up from its concrete Workstation; there is no Workstation Type fallback in this controller. The
stored transaction is:

```text
row.hour_rate      = row.hour_rate or Workstation.hour_rate
row.operating_cost = round_field(row.hour_rate × row.time_in_mins / 60)
```

(`manufacturing/doctype/routing/routing.py:27-43`).

`on_update` calls the cost calculation again after
the normal validation/write pipeline (`manufacturing/doctype/routing/routing.py:31-33`).

Sequence assignment walks child order with a running prior ID:

```text
blank sequence = previous sequence + 1
explicit sequence < previous sequence -> reject
explicit sequence = previous sequence -> allowed parallel group
```

(`manufacturing/doctype/routing/routing.py:44-57`). It does not require the first explicit ID to be 1,
prevent gaps, or require a positive ID. The stricter Work Order copy later requires row 1 to be sequence
1 and every subsequent ID to be the same or exactly the next number
(`manufacturing/doctype/work_order/work_order.py:340-363`). Therefore a Routing can save a sequence
shape that its resulting Work Order rejects.

The whitelisted operation-search API queries the shared `BOM Operation` table and, when supplied, adds
only `parent = routing`; it omits `parenttype = 'Routing'` and does not request distinct operation names
(`manufacturing/doctype/routing/routing.py:60-76`). A BOM and Routing with the same parent name can
cross-contaminate results.

### 2.2 Workstation saves rewrite Routing rows

Before every Workstation save, a changed Workstation Type copies the type's cost rows, then the concrete
resource recomputes:

```text
Workstation.hour_rate          = Σ truthy component.operating_cost
working_hour.hours             = round_field(end_time - start_time in hours)
Workstation.total_working_hours = Σ working_hour.hours
```

and forces status `Off` when disabled (`manufacturing/doctype/workstation/workstation.py:85-113`). Type
cost is the same float sum (`manufacturing/doctype/workstation_type/workstation_type.py:26-51`). The
copy is snapshot-based. Later Type edits do not propagate. If a newly selected Type has no cost rows,
old concrete Workstation rows survive because the table is cleared only when query results are truthy
(`manufacturing/doctype/workstation/workstation.py:114-141`).

After update, Workstation finds shared operation rows with this Workstation and
`parenttype = 'Routing'`, then bulk-writes:

```text
Routing row.hour_rate      = Workstation.hour_rate
Routing row.operating_cost = Workstation.hour_rate × row.time_in_mins / 60
```

(`manufacturing/doctype/workstation/workstation.py:194-212`). It does not update BOM-owned rows.
That split is deliberate snapshot behavior, but it is not labelled as such: Routing changes silently,
submitted BOM rows remain old until a separate BOM cost refresh, and doc 33 showed that refresh mutates
submitted BOMs.

### 2.3 Routing → BOM is a lossy snapshot

During BOM validation, Routing rows are imported only when operations are enabled and the BOM table is
empty; operation validation and costing follow in the same pipeline
(`manufacturing/doctype/bom/bom.py:299-331`, `manufacturing/doctype/bom/bom.py:922-946`). The copy is
ordered by `(sequence_id, idx)` and converts the company-currency Routing rate into BOM currency:

```text
BOM row.hour_rate = round_field(Routing row.hour_rate / BOM.conversion_rate)
```

(`manufacturing/doctype/bom/bom.py:488-525`). There is no zero-conversion guard here and no disabled-
Routing check.

The allow-list copies sequence, operation, concrete/type resource, description, minutes, batch size,
operating cost, index, rate, BOM-quantity costing flag and fixed-time flag. It silently drops shared-row
fields for semi-finished output/BOM, subcontracting, quality inspection, source/WIP/FG warehouses,
material-transfer skip and WIP backflush (`manufacturing/doctype/bom/bom.py:503-525`). Configuring
those fields on Routing creates data that does not survive publication to BOM.

BOM then defaults blank descriptions, normalises non-positive batch size to 1, requires concrete
Workstation or Type, and requires positive minutes (`manufacturing/doctype/bom/bom.py:927-946`). Cost
uses concrete Workstation before Type and converts a company-rate master into BOM currency. For each
row:

```text
base_hour_rate      = hour_rate × BOM.conversion_rate
operating_cost      = hour_rate × time_in_mins / 60
base_operating_cost = operating_cost × BOM.conversion_rate
cost_per_unit       = operating_cost / (batch_size or 1)
base_cost_per_unit  = base_operating_cost / (batch_size or 1)
```

If `set_cost_based_on_bom_qty`, the BOM contribution is `cost_per_unit × BOM.quantity`; otherwise it
is the row operating cost (`manufacturing/doctype/bom/services/costing.py:157-219`). As doc 33 found,
these are float intermediates with field/database coercion rather than one declared decimal contract.

### 2.4 BOM → Work Order rescales and snapshots again

The Work Order service clears its operation table, collects root BOM rows and, for multi-level mode,
all descendant BOM rows bottom-up. Its shared-child query filters only `parent = bom_no`, not
`parenttype = 'BOM'`, so a same-named Routing can contaminate collection
(`manufacturing/doctype/work_order/services/operations.py:162-228`). It copies `base_hour_rate AS
hour_rate`, which means the Work Order rate is in company currency, plus the operation/resource,
sequence, quantity/cost flags and warehouse semantics
(`manufacturing/doctype/work_order/services/operations.py:29-56`).

For a non-fixed operation, exact duration scaling is:

```text
root ordinary:       WO minutes = BOM minutes / BOM output qty × WO qty
root batch-card op:  WO minutes = BOM minutes / operation batch size × WO qty
nested ordinary:     pre-scale = BOM minutes × child exploded qty / child BOM qty
                     WO minutes = pre-scale × WO qty
fixed_time:          WO minutes = BOM minutes
```

The service implements the nested/root pre-scaling first and multiplies all non-fixed rows by Work
Order quantity afterward (`manufacturing/doctype/work_order/services/operations.py:199-249`). A
positive operation time is required; batch size is normalised to 1
(`manufacturing/doctype/work_order/work_order.py:939-946`).

Work Order row and parent costs are:

```text
planned row = round_field(hour_rate × planned minutes / 60)
actual row  = round_field(hour_rate × actual minutes / 60)
planned total = Σ planned row
actual total  = Σ actual row
variable total = actual total or planned total
total = additional + variable total + corrective
```

(`manufacturing/doctype/work_order/services/operations.py:58-86`). The `or` applies to the entire
aggregate. As soon as any actual operation cost makes the total non-zero, planned cost for every
unstarted operation disappears from `total_operating_cost`; a legitimate zero actual aggregate falls
back to plan.

> **Ours — one route compiler.** Route approval compiles one typed execution graph. BOM costing and
> Work Order planning reference that revision and derive quantity-scaled durations from one pure
> function. Every copied projection carries `source_route_revision_id`, algorithm version and input
> fingerprint. A resource-rate revision never silently rewrites a route; a new cost snapshot names the
> rate revision and currency.

---

## 3. Work Order scheduling and Job Card creation

### 3.1 Batch splitting and copied quantities

Work Order submission performs its stock/reservation roll-ups and then creates Job Cards
(`manufacturing/doctype/work_order/work_order.py:615-628`). For each operation the service repeatedly
splits the Work Order quantity. When the Operation master does not request batch cards, the batch is the
requested quantity (manual API) or whole Work Order quantity. Otherwise each card receives:

```text
job_card_qty = min(remaining_qty, operation.batch_size)
remaining_qty -= job_card_qty
```

Serials are selected by subtracting serial numbers already present on non-cancelled cards for the same
Work Order operation, sorting, and taking the first `job_card_qty`
(`manufacturing/doctype/work_order/mapper.py:321-365`). These allocation reads are unlocked.

The new Job Card copies Work Order/operation identity, sequence, Workstation/Type, company/project,
company-currency hour rate and warehouse/transfer semantics. Its expected duration and material demand
are proportional:

```text
Job Card.time_required = WO operation minutes / WO.qty × card.qty
Job Card item.required_qty = WO item.required_qty / WO.qty × card.qty
```

(`manufacturing/doctype/work_order/mapper.py:406-459`,
`manufacturing/doctype/job_card/job_card.py:783-826`).

The whitelisted manual `make_job_card` endpoint checks Job Card create permission and validates positive
requested quantity no greater than caller-supplied pending quantity, then uses the same splitter
(`manufacturing/doctype/work_order/mapper.py:291-389`). It calls creation without enabling capacity
planning, so manually generated cards have no planned interval reservation. Two callers can both pass
the pending/serial reads and over-create cards or assign the same serials.

### 3.2 Operation sequence determines only an initial candidate

With capacity enabled, the first operation starts at `Work Order.planned_start_date`. Without sequence
IDs, each later operation starts after the previous end plus the global gap. With sequence IDs, equal-ID
rows share a start; the next sequence starts after the **latest** planned end among the preceding group
plus the gap (`manufacturing/doctype/work_order/services/operations.py:133-160`).

The global helper returns a `relativedelta` of configured minutes but treats zero as **10**, so zero
cannot mean “no gap” (`manufacturing/doctype/manufacturing_settings/manufacturing_settings.py:57-60`).
The initial end is start plus operation minutes. Zero duration is rejected. This interval is only a
candidate; Job Card scheduling can move and split it around occupancy and calendars.

The resulting Work Order operation is then overwritten with the Job Card's **last scheduled segment**
start/end, not the full Job Card min start/max end. The Work Order parent `planned_end_date` is copied
from the last operation row, not the maximum across parallel final operations
(`manufacturing/doctype/work_order/services/operations.py:88-129`). A split operation can therefore
show only its final segment at Work Order-row level, and a slower parallel operation that is not last in
child order can extend beyond parent planned end.

The capacity horizon is checked only after recursive scheduling returns. It compares calendar
`date_diff(row.planned_end_time, Work Order.planned_start_date)` to configured days, defaulting falsey
values to 30 (`manufacturing/doctype/work_order/services/operations.py:88-129`). It is a postcondition,
not a recursion bound.

---

## 4. Capacity and overlap — exact database projections, algorithm and races

### 4.1 Two child tables form the availability query

For a candidate interval, Job Card unions overlap rows from:

- `Job Card Time Log` under every Job Card with `docstatus < 2`; and
- `Job Card Scheduled Time` only under draft Job Cards whose `total_time_in_mins == 0`.

It projects parent name, child name, from/to, concrete Workstation and Type. The current child/parent is
excluded. Actual rows may additionally filter employee; scheduled rows for an employee are limited to
cards returned by the “open Job Card” query
(`manufacturing/doctype/job_card/job_card.py:443-534`).

Overlap is the disjunction:

```text
existing.from < candidate.from < existing.to
existing.from < candidate.to   < existing.to
existing.from >= candidate.from AND existing.to <= candidate.to
```

(`manufacturing/doctype/job_card/job_card.py:459-485`). Strict endpoint comparisons correctly permit
`[10:00,11:00]` followed by `[11:00,12:00]`. Open/zero-end rows are not a durable interval reservation
and have database-dependent comparison behavior.

If a concrete Workstation is set, both Type and Workstation filters apply. If only Type is set, all
existing Job Cards of that Type share one temporary pool until a concrete Workstation is chosen
(`manufacturing/doctype/job_card/job_card.py:487-507`). `production_capacity` is read only from a
concrete Workstation and uses `value or 1`, so configured zero and a Type-only card both behave as
capacity 1 (`manufacturing/doctype/job_card/job_card.py:398-401`).

### 4.2 Capacity is greedy interval-lane packing

For capacity greater than one, overlaps are sorted by start. The first creates lane 1. Each subsequent
interval enters the first lane whose prior end is `<=` its start; otherwise a new lane is opened.
Capacity is full when lane count is at least the configured capacity
(`manufacturing/doctype/job_card/job_card.py:412-440`). For the already-overlapping input set this is a
reasonable maximum-concurrency calculation, and endpoint-touching intervals remain sequential.

Employee capacity is different. A matching employee on any other draft Job Card is treated as
currently working, even when that historical time-log row already has `to_time`; the query does not
require an open interval (`manufacturing/doctype/job_card/job_card.py:513-534`). The same employee can
therefore be blocked by a closed log attached to a still-draft card.

### 4.3 Type-based Workstation allocation is not capacity-aware

If Type-wide overlap exists, the allocator gets every Workstation of that Type, groups existing rows by
minute-truncated exact `(from_time, to_time)`, and returns the lexicographically first Workstation absent
from the first group with any availability (`manufacturing/doctype/job_card/job_card.py:536-563`). If
there is no overlap, it simply assigns the first Type member in creation order
(`manufacturing/doctype/job_card/job_card.py:565-601`,
`manufacturing/doctype/workstation_type/workstation_type.py:53-58`).

This has four independent correctness gaps:

1. disabled, Off, Problem and Maintenance resources remain candidates;
2. each resource is treated as binary busy/free, ignoring concrete capacity above one;
3. differently bounded but overlapping intervals occupy different exact-time groups, so a Workstation
   busy in another group can be selected;
4. seconds are discarded, and no candidate calendar/holiday is compared before selection.

The no-conflict and conflict paths also use different tie-breakers (creation order versus lexical name).

### 4.4 There is no concurrency guarantee

All of this is read/check/insert. There is no `FOR UPDATE`, advisory lock, resource-timeslot lease,
unique key or exclusion constraint around either overlap query or concrete Workstation assignment. Two
transactions can both observe one free lane and both insert a scheduled or actual interval. The same
pattern affects Job Card aggregate quantity validation: active card quantity is an unlocked `SUM`, then
the current card is saved (`manufacturing/doctype/job_card/job_card.py:214-257`).

Recursive collision handling advances the candidate after one conflicting end plus the global gap and
calls itself again, without a bounded search horizon or claim (`manufacturing/doctype/job_card/job_card.py:565-601`).
Work Order's day limit is checked only afterward. These checks are useful UI validation under serial
usage, not capacity integrity.

> **Invariant M8 — atomic finite-capacity reservation.** A schedule reservation names one concrete
> resource, capability, half-open interval `[start,end)`, capacity units and source operation revision.
> PostgreSQL range/exclusion logic or a serializable resource-day allocator prevents committed overlap
> above capacity. Type assignment and interval claim occur in one transaction; disabled/unavailable
> resources are excluded by constraint-backed state, not a later filter.

---

## 5. Calendars and holidays — three incompatible meanings of availability

### 5.1 Workstation calendar validation

Before save, every working-hour row must have `start_time < end_time`; overnight shifts are impossible.
Hours and daily total are recalculated using field precision
(`manufacturing/doctype/workstation/workstation.py:85-108`). On update, each row is compared with
persisted siblings through inclusive `BETWEEN`/containment predicates, so adjacent shifts such as
09:00–13:00 and 13:00–17:00 can be rejected as overlapping
(`manufacturing/doctype/workstation/workstation.py:169-192`).

The child has `enabled`, but total calculation, overlap validation and scheduling never inspect it
(`manufacturing/doctype/workstation_working_hour/workstation_working_hour.py:7-23`,
`manufacturing/doctype/workstation/workstation.py:97-108`). A disabled shift still contributes hours,
can conflict, and accepts production.

### 5.2 Automatic scheduling splits by row order

If the selected Workstation has no working-hour rows, or global `allow_overtime` is true, Job Card
accepts the whole interval and appends one scheduled child. Otherwise it checks the start date's holiday
and consumes remaining minutes through working-hour rows in **child order**, appending one interval per
segment (`manufacturing/doctype/job_card/job_card.py:602-713`).

A row is usable only when candidate start is inclusively inside that slot. Consequences follow directly:

- a start before the first slot or in a same-day gap is not snapped to the next slot; no row matches and
  the job moves to the first slot of the next day;
- a start exactly at slot end can append a zero-minute segment;
- unsorted child rows can move the candidate backward;
- after all rows, remaining work starts next day at row 1, regardless of `enabled`;
- when no working hours exist, Holiday List is also bypassed because the no-calendar branch returns
  before holiday adjustment.

Holiday validation bypasses the list if there is no list or global holiday production is enabled. On a
holiday it adds one day and recursively calls with `skip_holiday_list_check=True`; this suppresses the
next check entirely, so only one day of consecutive holidays is skipped
(`manufacturing/doctype/workstation/workstation.py:214-225`).

### 5.3 Manual actual-log validation checks duration, not containment

Manual Job Card time validation takes a different path. It rejects any listed holiday in the inclusive
date range unless globally allowed. With overtime disabled it computes operation duration and succeeds
when **any one configured shift is at least that long**; it never checks whether the submitted timestamp
falls inside that shift (`manufacturing/doctype/workstation/workstation.py:360-415`). Thus an overnight
off-hours interval can pass because its length fits a daytime shift, while valid work spanning two
shifts fails because no individual row is long enough. No working-hour rows again means unrestricted.

The scheduler can split a long operation over many slots, while the manual validator demands that it
fit one slot. They do not enforce one calendar invariant.

> **Invariant M9 — one effective calendar.** Resource calendars are versioned sets of sorted,
> non-overlapping half-open intervals with explicit timezone, exception/holiday intervals and capacity.
> Disabled shifts are absent. One function answers containment, next availability and interval splitting
> for planning and actual validation. Overnight shifts and consecutive closures are first-class, and
> every schedule records the calendar revision used.

---

## 6. Actual work, sub-operations and mutable roll-ups

### 6.1 Immediate sub-operation roll-up

When a Job Card first validates, it copies only immediate Operation children and marks them Pending.
Time logs identify a sub-operation by Operation name. For each child, no log means Pending; an open or
zero-minute log means Work In Progress; a non-zero closed log means Complete; paused parent overrides to
Pause (`manufacturing/doctype/job_card/job_card.py:258-281`,
`manufacturing/doctype/job_card/job_card.py:717-781`).

Both completed minutes and quantity are summed, then divided by the count of distinct employees on the
logs. The parent Job Card's completed quantity is the **minimum** child completed quantity
(`manufacturing/doctype/job_card/job_card.py:347-355`,
`manufacturing/doctype/job_card/job_card.py:741-781`). This makes the slowest immediate child a sensible
completion gate, but employee normalization assumes parallel duplicate recording. Sequential or unequal
employee work is undercounted, blank employee is a distinct divisor, configured sub-operation minutes
are ignored, and grandchildren never participate.

Normal time-log duration is correctly:

```text
time_in_mins = (to_time - from_time in hours) × 60
```

and a reversed interval is rejected (`manufacturing/doctype/job_card/job_card.py:302-326`). Workstation's
separate `complete_job` API instead writes `time_diff_in_hours / 60`, so a one-hour job becomes 0.0167
minutes before later Job Card recalculation may repair it (`manufacturing/doctype/workstation/workstation.py:227-253`).

### 6.2 Completion and prior-operation gates

Submission normally requires at least one time log; when `enforce_time_logs` is on, every row requires
both endpoints. A paused card and a stopped Work Order are rejected. At field precision:

```text
completed_qty + process_loss_qty + pending_qty = for_quantity
```

(`manufacturing/doctype/job_card/job_card.py:913-990`). Before save, process loss is reset to
`for_quantity - completed - pending` only when completed is positive and below requested quantity; the
formula itself can produce negative loss if a caller supplies excessive pending quantity outside the
special completion API (`manufacturing/doctype/job_card/job_card.py:992-1003`).

For sequenced work, a non-new, non-corrective card reads all lower-sequence Work Order rows. Each prior
row must have completion, and current aggregate completion cannot exceed prior completion. Same-sequence
operations are parallel and do not gate each other (`manufacturing/doctype/job_card/job_card.py:1412-1467`).
The aggregates are unlocked.

### 6.3 Submit/cancel rewrites submitted Work Orders

On submit and cancel, Job Card recomputes submitted non-corrective cards for its operation:

```text
completed = Σ total_completed_qty
minutes   = Σ total_time_in_mins
loss      = Σ process_loss_qty
pending   = Σ pending_qty
actual start/end = MIN(actual log start), MAX(actual log end)
```

It loads the already-submitted Work Order, replaces those values on the operation row, replaces
Workstation and rate when the Job Card resource differs, recalculates status/cost/dates, bypasses the
update-after-submit guard and saves (`manufacturing/doctype/job_card/job_card.py:1005-1038`,
`manufacturing/doctype/job_card/job_card.py:1092-1162`). Semi-finished completion has a second direct
`db.set_value` path (`manufacturing/doctype/job_card/job_card.py:1040-1063`). There is no Work Order row
lock or retry. Concurrent Job Card completions can race aggregate snapshots and last-write the roll-up.

Operation status uses `completed + process_loss`: zero Pending, below Work Order quantity Work in
Progress, up to quantity plus global overproduction allowance Completed, above it rejected
(`manufacturing/doctype/work_order/services/operations.py:270-292`). Corrective Job Cards are excluded
from normal completion and, when enabled, add:

```text
corrective cost = Σ(corrective minutes / 60 × Job Card hour_rate)
```

then mutate Work Order cost (`manufacturing/doctype/job_card/job_card.py:1065-1077`).

> **Invariant M10 — actual work is an event stream.** Start, pause, resume, complete, quantity output,
> process loss and employee participation are append-only, actor/time-stamped events referencing one
> operation execution and concrete resource. Corrections reverse or supersede events. Work Order
> completion, actual duration and status are transactional aggregates/views, never values rewritten by
> whichever Job Card saves last.

---

## 7. Workstation component cost and production valuation

### 7.1 Mutable hourly composition

Workstation and Type calculate net hour rate as the float sum of component amounts; only duplicate
component names within that one table are rejected (`manufacturing/doctype/workstation/workstation.py:70-113`,
`manufacturing/doctype/workstation_type/workstation_type.py:26-51`). A Work Order receives the BOM's
base rate, but an executing Job Card may change concrete Workstation. On Job Card roll-up, Work Order
then replaces the operation rate with that Workstation's **current** net rate
(`manufacturing/doctype/job_card/job_card.py:1135-1162`). There is no effective date or rate revision.

### 7.2 Component-wise Manufacture Stock Entry allocation

For each Work Order operation having actual minutes, Manufacture Stock Entry reads the selected
Workstation's current cost components and already-consumed submitted operating costs. Per component:

```text
actual_remaining = round_row(component hourly rate × actual minutes / 60
                             - previously consumed component cost)
remaining_qty    = operation.completed_qty - previously consumed qty
candidate_cost   = actual_remaining / (remaining_qty or 1) × entry.fg_completed_qty
entry amount     = round_money(min(candidate_cost, actual_remaining))
entry allocated qty = min(remaining_qty, entry.fg_completed_qty)
```

It appends a `Landed Cost Taxes and Charges` row naming operation and component
(`manufacturing/doctype/bom/services/operations_cost.py:72-143`). Expense account comes from the first
matching component/company child, otherwise the caller's default operating-cost account
(`manufacturing/doctype/bom/services/operations_cost.py:145-149`). Duplicate company mappings therefore
choose an unspecified row.

If no component row is added, a Work Order-level remaining operating-cost fallback is allocated by
finished-good quantity, except Job Card-specific Manufacture entries skip that fallback. Additional and
corrective cost are separate rows (`manufacturing/doctype/bom/services/operations_cost.py:152-252`).

There is no lock between reading consumed component cost and appending the new charge. Concurrent
Manufacture submissions can each allocate the same remainder. Consumed amount greater than actual or
consumed quantity greater than completed can produce negative remainder/quantity; only a falsey exact
zero suppresses a row. The source component rates are current Workstation master data, not the rates
used when Job Card work occurred.

Doc 33's multilevel defects also affect the setting that imports subassembly cost: recursive operating-
cost calls discard the returned deeper accumulator and do not quantity-scale child cost; secondary-item
recursion mutates the sibling quantity accumulator and overwrites duplicates
(`manufacturing/doctype/bom/services/operations_cost.py:256-305`).

> **Invariant M11 — costed resource usage.** Every actual resource interval snapshots component rate
> revision, company, currency and fixed-decimal rate. Manufacture valuation consumes each usage-cost
> event exactly once through an allocation table with `UNIQUE(usage_cost_id, production_output_id)` and
> non-negative residual constraints. Company/account mappings are unique and FK-constrained. Later
> Workstation rate changes never reprice historical work.

---

## 8. `Manufacturing Settings` — global switches in this flow

The parent is a mutable site-wide Single, so changing one value immediately changes validation and
future scheduling for every company. There is no effective date, company scope or snapshot on existing
Work Orders (`manufacturing/doctype/manufacturing_settings/manufacturing_settings.py:10-55`). Relevant
settings have these exact effects:

| Setting | Read path and effect |
|---|---|
| `disable_capacity_planning` | Work Order submission still creates Job Cards but omits scheduled children when true (`manufacturing/doctype/work_order/services/operations.py:88-104`). Manual Job Card creation omits planning regardless (`manufacturing/doctype/work_order/mapper.py:291-311`). |
| `capacity_planning_for_days` | Falsey becomes 30; post-schedule Work Order-row end must be within that many date-difference days (`manufacturing/doctype/work_order/services/operations.py:88-129`). |
| `mins_between_operations` | Falsey, including zero, becomes 10 minutes; used between serial/sequence groups and when pushing after a conflict (`manufacturing/doctype/manufacturing_settings/manufacturing_settings.py:57-60`, `manufacturing/doctype/job_card/job_card.py:565-601`). |
| `allow_overtime` | Automatic planning ignores all working-hour rows; manual actual validation skips the single-slot duration test (`manufacturing/doctype/job_card/job_card.py:602-613`, `manufacturing/doctype/workstation/workstation.py:360-369`). |
| `allow_production_on_holidays` | Automatic and manual paths bypass Holiday List checks (`manufacturing/doctype/workstation/workstation.py:214-225`, `manufacturing/doctype/workstation/workstation.py:360-415`). |
| `overproduction_percentage_for_work_order` | Raises unlocked aggregate Job Card quantity and operation completion ceilings (`manufacturing/doctype/job_card/job_card.py:214-257`, `manufacturing/doctype/work_order/services/operations.py:270-292`). |
| `enforce_time_logs` | Submission requires both endpoints on every Job Card time row; without it, the card still normally needs a row but that row may be open (`manufacturing/doctype/job_card/job_card.py:913-943`). |
| `add_corrective_operation_cost_in_finished_good_valuation` | Enables corrective Job Card cost write-back and remaining corrective-cost allocation to Manufacture valuation (`manufacturing/doctype/job_card/job_card.py:1005-1025`, `manufacturing/doctype/bom/services/operations_cost.py:202-252`). |
| `set_op_cost_and_secondary_items_from_sub_assemblies` | Enables multilevel Work Order/Stock Entry cost imports, subject to the recursive defects in §7 (`manufacturing/doctype/bom/services/operations_cost.py:256-305`). |
| `update_bom_costs_automatically` | Launches the mutable BOM cost refresh described in doc 33; it can change the BOM snapshots from which later Work Orders copy rates. |
| `job_card_excess_transfer` | Loaded onto Job Card and controls whether material-transfer aggregate may exceed required item quantity (`manufacturing/doctype/job_card/job_card.py:146-151`, `manufacturing/doctype/job_card/job_card.py:1190-1245`). |

The settings controlling material consumption, backflush, component-quantity validation, editable Work
Order materials, transfer-extra percentage, Sales Order overproduction, and automatic serial/batch
creation affect adjacent production-stock behavior and will be traced with Work Order and manufacturing
Stock Entry in docs 35/37. They share the same design problem: a current mutable singleton is read at
action time rather than a company-scoped policy revision being named by the production document.

> **Ours — policy revisions.** Capacity, overproduction, logging and valuation policy is company-scoped,
> effective-dated and versioned. A Work Order snapshots its policy revision; an operator action is
> validated under that named revision unless an authorised migration explicitly changes it. Zero is a
> valid configured gap/horizon value, not an implicit default sentinel.

---

## 9. `Downtime Entry` — reporting data disconnected from capacity

Validation performs only:

```text
downtime minutes = (to_time - from_time in hours) × 60
```

(`manufacturing/doctype/downtime_entry/downtime_entry.py:33-38`). It does not require end after start,
check Workstation working hours, reject overlap with another downtime or planned/actual Job Card, alter
Workstation status, or block scheduling. Reversed intervals persist negative minutes, duplicate overlap
is allowed, and concurrent entries need no coordination.

The Downtime Analysis projection filters for entries **fully contained** in its window:
`from_time >= filter.from` and `to_time <= filter.to`. It divides stored minutes by 60 and sums hours per
Workstation for the chart (`manufacturing/report/downtime_analysis/downtime_analysis.py:18-61`). An
interval crossing either report boundary is omitted rather than clipped. The report is the only runtime
consumer found; capacity and Workstation Type selection never query `Downtime Entry`.

> **Invariant M12 — downtime is a capacity event.** Downtime is a non-negative half-open resource
> interval with reason, actor/source and lifecycle. It atomically reduces available capacity and
> conflicts with or triggers an explicit reschedule of reservations. Reporting clips interval overlap to
> the requested window. Workstation status is a derived current-state projection over actual work,
> downtime and manual state events.

---

## 10. `Plant Floor` — read projections and command shortcuts, not a scheduler

The Plant Floor parent has no domain validation. Its whitelisted `make_stock_entry` method accepts
caller arguments, creates an **unsaved** Stock Entry, sets company/from/to/purpose/current posting time,
adds one item at conversion factor 1, calls `set_missing_values`, and returns the document
(`manufacturing/doctype/plant_floor/plant_floor.py:24-66`). It does not explicitly check Stock Entry
create permission, validate positive quantity, or constrain supplied company/warehouses to the Plant
Floor. Normal permission/domain checks occur only if the caller subsequently saves the returned
transaction.

The stock-summary API checks read permission for Warehouse and optional Item/Item Group, then projects
at most 20 `Bin` rows for one warehouse ordered by actual quantity. It selects actual/projected,
sales/production/subcontract reservations, production-plan reservation and reserved stock
(`manufacturing/doctype/plant_floor/plant_floor.py:68-132`). Display derivation is:

```text
actual_or_pending = projected + reserved_sales + reserved_production + reserved_subcontract
total_reserved    = reserved_sales + reserved_production + reserved_subcontract
pending           = max(actual_or_pending - actual, 0)
```

It omits selected `reserved_qty_for_production_plan` and `reserved_stock` from those totals. `max_count`
is a running maximum attached per row, so rows processed before the global maximum use a different bar
scale (`manufacturing/doctype/plant_floor/plant_floor.py:79-96`). This is a dashboard projection over
Bin, not a production-capacity projection.

Workstation's `get_workstations` API is the visual floor projection. It explicitly checks Workstation
read permission, filters exact Plant Floor and `disabled = 0`, optionally filters type/name/status, and
derives status image, CSS state, color and links (`manufacturing/doctype/workstation/workstation.py:418-471`).
This safe display filter contrasts with Type-based capacity selection, which includes disabled rows.

Workstation publishes realtime floor state only from its document `on_update`, and only when status
changed (`manufacturing/doctype/workstation/workstation.py:143-167`). Job Card instead writes
Workstation status through `frappe.db.set_value`: Open/Completed → Off, Work In Progress → Production,
On Hold → Idle (`manufacturing/doctype/job_card/job_card.py:1554-1574`). That bypasses Workstation's
hook, so the database can change without a realtime Plant Floor event. Concurrent draft cards also
last-write one scalar status; the loop orders by status text rather than event time or severity.

There is a second edge failure: disabling a Workstation forces status Off, then `on_update` can publish.
The publisher indexes the first result from `get_workstations`, but that query excludes the now-disabled
row, so the result can be empty (`manufacturing/doctype/workstation/workstation.py:85-95`,
`manufacturing/doctype/workstation/workstation.py:143-167`,
`manufacturing/doctype/workstation/workstation.py:418-439`).

> **Ours — floor is a projection.** Plant-floor tiles, status and stock summaries are read models over
> resource-state, capacity-reservation, actual-work, downtime and inventory events. Commands call typed
> application services with normal permissions and idempotency keys; a dashboard endpoint never builds a
> privileged half-validated transaction. Projection lag is visible by `computed_at`/event position.

---

## 11. Findings and decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Operation master with work instruction, batch and inspection defaults | **Adopt concept** | immutable operation-definition revision |
| Direct duplicate/self-child checks | **Adopt minimum, strengthen** | FK edges + transitive acyclicity and positive duration constraints |
| Immediate-only sub-operation execution | **Make explicit** | typed one-level checklist or recursively compiled DAG, never accidental mix |
| Routing shared `BOM Operation` child | **Reject representation** | route-operation source table separate from BOM/WO projections |
| Equal sequence IDs for parallel work | **Adopt intent** | explicit dependency edges; parallelism is absence of precedence, not repeated integers |
| Routing permits sequence shapes Work Order rejects | **Reject (inconsistent)** | validate once at route publication |
| Routing operation search omits `parenttype` | **Reject (bug)** | typed FK/table; no discriminator collision |
| Disabled Routing can be copied | **Reject (bug)** | approved/effective revision FK required |
| Routing → BOM partial allow-list | **Reject (data loss)** | one compiler copies every semantic field or references immutable source |
| Workstation save rewriting Routing rates | **Reject mutation** | append cost-rate revision/snapshot |
| Concrete Workstation before Type for BOM rate | **Adopt precedence explicitly** | typed cost-source record with currency/effective time |
| Quantity/batch/fixed-time scaling | **Adopt formulas** | one fixed-decimal duration function with named rounding |
| Work Order aggregate `actual or planned` cost | **Reject** | per-operation actual-if-finalised else committed/plan, with clear forecast vs actual totals |
| Sequence-group initial scheduling | **Adopt intent** | DAG earliest-start calculation over explicit predecessors |
| Scheduled/actual Job Card child tables | **Adopt as projections/events respectively** | immutable reservations + actual interval events |
| Greedy capacity-lane calculation | **Adopt for availability query** | database-serialised capacity-unit reservation |
| Strict endpoint overlap | **Adopt** | canonical half-open `[start,end)` intervals |
| Unlocked overlap check then insert | **Reject (race)** | exclusion/serializable resource-day allocator |
| Type pool selecting disabled/off machines | **Reject (bug)** | eligible-resource query includes capability, state, calendar and capacity |
| Exact-time busy grouping, binary resource occupancy | **Reject (bug)** | interval/capacity-unit allocation per concrete resource |
| Workstation zero capacity becoming one | **Reject** | `CHECK(capacity > 0)`; disabled state is separate |
| Working-hour `enabled` ignored | **Reject (bug)** | disabled intervals absent from effective calendar |
| Adjacent working hours rejected while jobs may touch | **Reject inconsistency** | half-open interval rule everywhere |
| Calendar splitter by unsorted row order | **Reject** | database-constrained sorted interval set |
| Only one consecutive holiday skipped | **Reject (bug)** | next-availability function over exception intervals |
| Manual validator compares duration, not timestamp containment | **Reject (bug)** | same calendar function for plan and actual |
| Manual Job Card API bypasses capacity planning | **Reject ambiguity** | explicit unscheduled queue state or atomic reservation; never silent bypass |
| Batch splitter | **Adopt** | deterministic execution-lot generation with unique source/ordinal |
| Serial subtraction before insert | **Reject race** | locked/unique serial assignment |
| Minimum sub-operation quantity gates parent | **Adopt when sub-steps are mandatory** | aggregate over immutable output events and explicit node dependencies |
| Employee-count division of time and output | **Reject assumption** | labour intervals and machine/output events recorded separately |
| Job Card aggregate rewrite of submitted Work Order | **Reject** | transactional aggregate/view over execution events |
| Workstation component hourly decomposition | **Adopt** | effective-dated company/currency rate revisions |
| Remaining component-cost allocation | **Adopt intent, reject race** | fixed-decimal usage-cost events and unique allocation rows |
| Duplicate/optional component account mappings | **Reject** | unique `(component, company)` and company-consistent required account |
| Downtime as isolated report data | **Reject** | downtime consumes capacity and drives rescheduling/status |
| Fully-contained downtime report filter | **Reject (bug)** | overlap query plus clipped duration |
| Plant Floor Bin/Workstation projections | **Adopt as read models** | event-positioned projections with one reservation vocabulary |
| Plant Floor returning an unsaved Stock Entry | **Reject boundary** | typed stock command with full permission/domain validation |
| Job Card `db.set_value` bypassing realtime hook | **Reject** | status derived from events; projection publishes changes transactionally |
| Global mutable Manufacturing Settings | **Reject** | company-scoped effective policy revisions named by Work Order |

The six production invariants added here are **M7–M12**: versioned process definitions, atomic finite-
capacity reservations, one effective calendar, append-only actual work, costed resource usage, and
downtime as a capacity event. Together with doc 33's M1–M6 they establish the source/projection and
concurrency boundaries that Work Order and Job Card lifecycle analysis must preserve.

---

Cross-references: doc 17 §2 (fixed-decimal quantity/UOM), doc 20 (identity and audit gaps), doc 22
(background jobs and locking), doc 33 (immutable BOM revisions, cost snapshots and projection
fingerprints), `docs/design/FINAL-SCHEMA.md` (fixed-decimal and immutable-event principles). Next: doc
35, Work Orders and Job Cards end to end.
