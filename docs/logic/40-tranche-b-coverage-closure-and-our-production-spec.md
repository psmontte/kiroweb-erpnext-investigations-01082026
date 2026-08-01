# 40 — Tranche B Coverage Closure and Our Production Specification

> **Tranche B deliverable.** This closes the production investigation and consolidates docs
> [33](33-bom-costing-explosion-and-update-jobs.md)–[39](39-quality-inspection-templates-readings-and-gates.md)
> and scenarios [S07](../scenarios/S07-make-to-order-manufacturing.md)–[S10](../scenarios/S10-customer-owned-subcontracting-inward.md)
> into the backend/database contract we will build.
>
> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev). ERPNext citations are
> `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are prefixed
> `frappe/`.

This is a specification, not an implementation report. **Application implementation has not started.**
Assets and depreciation remain **deferred**, to be investigated before implementation; CRM, Projects,
Support and Maintenance remain out of scope. The production design below extends
[`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md); it does not supersede the accounting, stock, trade,
settlement or platform guarantees already fixed there and in [doc 25](25-our-platform-spec.md).

---

## 1. Measured closure, not an assertion

The generated audit in [`docs/COVERAGE.md`](../COVERAGE.md) measures a parent DocType as covered only
when its controller is cited at a line number. The final measured state is exactly:

| Module | DocTypes | Controller cited | Uncited (submittable) | Uncited (config) | Excluded |
|---|---:|---:|---:|---:|---:|
| Accounts | 92 | 78 | 0 | 0 | 14 |
| Stock | 45 | 42 | 0 | 0 | 3 |
| Selling | 12 | 9 | 0 | 0 | 3 |
| Buying | 10 | 5 | 0 | 0 | 5 |
| Subcontracting | 4 | 4 | 0 | 0 | 0 |
| Manufacturing | 18 | 18 | 0 | 0 | 0 |
| Quality Management | 8 | 8 | 0 | 0 | 0 |
| **Total** | **189** | **164** | **0** | **0** | **25** |

The **25 deliberate exclusions are retained**: equity/cap-table records, supplier scorecards,
diagnostic/maintenance tools, one-time import tools and trivial lookups listed in
[`COVERAGE.md`](../COVERAGE.md#deliberate-exclusions). They are decisions, not hidden gaps. Child tables
remain covered with their parents and are catalogued column-by-column under `docs/reveng/`.

Production depth is supplied by:

- [doc 33](33-bom-costing-explosion-and-update-jobs.md): BOM revisions, explosion, costing and refresh;
- [doc 34](34-operations-routing-workstations-and-capacity.md): routes, resources, calendars and capacity;
- [doc 35](35-work-orders-job-cards-and-shop-floor.md): Work Orders, execution lots and shop floor;
- [doc 36](36-production-planning-mps-and-material-netting.md): Production Plan, MPS and MRP;
- [doc 37](37-manufacturing-stock-consumption-scrap-wip-and-gl.md): conversion, WIP, SLE and GL;
- [doc 38](38-subcontracting-orders-transfer-consumption-receipt-and-gl.md): both ownership directions;
- [doc 39](39-quality-inspection-templates-readings-and-gates.md): criteria, samples and release gates;
- [S07](../scenarios/S07-make-to-order-manufacturing.md), [S08](../scenarios/S08-supplier-subcontracting.md),
  [S09](../scenarios/S09-quality-gated-production-and-receipt.md) and
  [S10](../scenarios/S10-customer-owned-subcontracting-inward.md): worked writes, numbers and reversals.

---

## 2. Governing production model

The four-layer rule from [doc 25 §2](25-our-platform-spec.md#2-the-layering-rule) applies unchanged:
structural truth at **L1 schema**, cross-row truth/tenancy/immutability at **L2 triggers and RLS**,
ordered commands at **L3 orchestration**, and pure computation/external I/O at **L4 services**.
Production adds five non-negotiable consequences.

1. **Definition is versioned; execution names the version.** Approved BOM, route, criterion, calendar,
   rate and policy revisions are immutable. Release never points at “latest”.
2. **Authority, evidence and projection are different records.** A Work Order authorises; work events,
   stock moves, quality decisions and GL rows prove; status/counters/dashboards project.
3. **Every bounded write has one lock owner.** The owner is the source demand line, Work Order material
   or operation, item+warehouse+owner stock stream, quality requirement, resource-day or schedule
   occurrence—not whichever child row happens to be inserted first.
4. **Every retry has an idempotency identity.** Commands and outbox records use company-scoped unique
   keys; workers lease durable rows and projectors advance monotonically by event position.
5. **Correction is additive.** Posted production, quality, stock and accounting facts are never updated
   or deleted. Reversal/supersession rows retain exact provenance.

All business tables have `company_id NOT NULL`, company-scoped keys and both `ENABLE ROW LEVEL
SECURITY` and `FORCE ROW LEVEL SECURITY`. Policies call `authenticated_company_id()`, which reads a
transaction-local protected context row created only by the narrowly granted `SECURITY DEFINER`
`begin_tenant_transaction(auth_session_token,company_id)`. Protected schema tables concretely store a
hashed-token `principal_auth_session` (principal, gateway nonce, issue/expiry and consumed
backend/time), effective-range `principal_company_membership` plus immutable revocation, and a unique
`authenticated_tenant_context(backend_pid,transaction_id)` tied to that session/membership/company. The
function locks and compare-and-sets one active unexpired unconsumed session, validates an unrevoked
current membership, and inserts one context; `authenticated_company_id()` rejoins and rechecks those
protected rows. Commit makes token replay fail; rollback removes token consumption and context together
so the failed request may retry. Security-definer owner/search path/grants are fixed and objects fully
qualified. The application role cannot write/read these tables, forge principal identity or select a
company by setting a GUC. Only the migration role bypasses RLS. Required tests set fake `app.company_id`/principal GUCs, attempt direct
context writes, foreign/expired/replayed tokens and non-member companies, and prove all fail plus pooled
connections lose context at commit/rollback. Money is `numeric(19,4)`; quantities, conversion factors
and rates are `numeric(21,9)`; percentages are `numeric(9,6)`. Persisted state/type codes are stable
lower-case enum codes, never translated display text.

---

## 3. M1–M69: exact register and enforcement owner

Names below are preserved exactly from docs 33–39. Duplicate names are intentional: **M32 and M46 are
both “consumption completeness”** at internal-production and supplier-subcontract boundaries;
**M38 and M51 are both “evidence before projection”** at those same boundaries.

| ID | Exact invariant name | Primary enforcement |
|---|---|---|
| M1 | revision lifecycle | L1 revision FKs/state checks + L2 immutability trigger |
| M2 | one default | L1 company/item effective-range exclusion + partial unique index |
| M3 | deterministic costing | L1 fixed decimals/source FKs + L4 pure versioned calculator |
| M4 | projection equivalence | L3 one explosion service + L2 fingerprint/publish check |
| M5 | dependency-safe refresh | L1 DAG/input fingerprint + L2 publish trigger |
| M6 | durable jobs | L1 job/outbox uniqueness, lease and attempt state |
| M7 | versioned process definition | L1 immutable route/node/edge revision tables |
| M8 | atomic finite-capacity reservation | L1 common resource-day commitment slices + L2 deferred summed trigger/lock |
| M9 | one effective calendar | L1 approved range checks/non-overlap for operation/route/rate/capacity/calendar |
| M10 | actual work is an event stream | L2 append-only work-event trigger |
| M11 | costed resource usage | L1 unique usage/output allocation + exact sum trigger |
| M12 | downtime is a capacity event | L1 interval checks + L2 capacity conflict/reschedule rule |
| M13 | immutable execution authorisation | L1 released Work Order revision FKs + L2 freeze trigger |
| M14 | atomic quantity allocation | L1 unique allocation/residual constraints + L2 owner lock |
| M15 | explicit production lifecycle and dependencies | L1 transition/dependency tables + L3 ordered command |
| M16 | execution-lot identity | L1 unique `(work_order_operation_id, ordinal)` + ceiling trigger |
| M17 | append-only actual work | L2 event append-only/reversal enforcement |
| M18 | quality evidence gates the exact transition | L1 scoped release FK + L2 gate-consumption trigger |
| M19 | authoritative events and rebuildable projections | L2 append-only facts + projector checkpoints |
| M20 | serializable projection ownership | L2 owner lock or L1 idempotent projector position |
| M21 | immutable planning snapshot | L1 planning-run input revisions/watermark/hash |
| M22 | atomic demand allocation | L1 unique source allocation + L2 demand-owner lock |
| M23 | one cycle-safe explosion | L3 one pure graph function + L1 published acyclicity evidence |
| M24 | dimensionally correct, allocative netting | L1 typed dated supply allocations + exact sum trigger |
| M25 | validated, idempotent release | L1 unique release key + L3 ordinary validators |
| M26 | one reservation and projection model | L1 typed allocation ledger; stock balance is projection only |
| M27 | dimensioned demand and feasible dates | L1 canonical demand dimensions + L4 calendar/DAG calculation |
| M28 | planning is separate from release | L1 frozen proposal rows and separate release records |
| M29 | serializable planning ownership and audit | L2 deterministic locks + append-only allocation/audit rows |
| M30 | conversion identity | L1 production command and typed line FKs |
| M31 | WIP conservation | L2 deferred paired-move quantity/value constraint |
| M32 | consumption completeness | L1 exact input/output allocation + L2 locked residual check |
| M33 | yield and coproduct identity | L1 typed output/loss rows + exact allocation trigger |
| M34 | reversal provenance | L1 unique original-allocation reversal FKs |
| M35 | one cost allocation equation | L2 output+normal absorption+scrap+abnormal expense+variance exact trigger |
| M36 | tracked-unit continuity | L1 serial uniqueness/batch sum + L2 allocator lock |
| M37 | manufacturing stock/GL bridge | L1 immutable value events/voucher links + L2 exact event↔GL trigger |
| M38 | evidence before projection | L2 atomic facts/outbox; projector position after commit |
| M39 | immutable production posting | L2 append-only and reversal-only triggers |
| M40 | serializable production allocation | L1 bounded allocations + L2 deterministic owner locks |
| M41 | subcontracting command identity | L1 authorisation/service/material/output identities |
| M42 | commercial/physical conservation | L2 exact service-to-FG equation + source-line lock |
| M43 | actual cost authority | L1 initial/adjustment value-event provenance and frozen policy revisions |
| M44 | supplier material allocation | L1 exact custody transfer/allocation ledger |
| M45 | custody conservation | L2 deferred paired moves and net-custody equation |
| M46 | consumption completeness | L1 complete supplier-input/output set + L2 owner lock |
| M47 | subcontract tracked-unit continuity | L1 serial/batch custody allocation uniqueness |
| M48 | subcontract yield and cost allocation | L2 deferred exact cost equation |
| M49 | subcontract stock projection | L1 move dependencies + deterministic stock projector |
| M50 | subcontract stock/GL bridge | L1 immutable value events/voucher links + L2 exact event↔GL trigger |
| M51 | evidence before projection | L2 atomic facts/outbox; idempotent commercial/projection links |
| M52 | explicit inventory ownership | L1 owner on lot/move/allocation and owner-aware stock keys |
| M53 | inward fulfilment semantics | L1 typed fulfilment facts + derived net-obligation view |
| M54 | immutable subcontract posting | L2 append-only/reversal-only triggers |
| M55 | serializable subcontract allocation | L1 bounded allocations + L2 deterministic owner locks |
| M56 | bounded quality authority | L1 frozen full criterion set/release qty + L2 summed consumption residual |
| M57 | explicit quality lifecycle | L1 attempt/evaluation/disposition/release plus concrete QM fact/event tables |
| M58 | criterion revision identity | L1 approved immutable criterion revision FK |
| M59 | complete canonical sample | L1 bounded positions/unit agreement + L2 exact set/completeness trigger |
| M60 | deterministic evaluation and disposition | L1 engine/version/trace + L4 constrained pure evaluator |
| M61 | one inspection claim | L1 unreversed-chain uniqueness + L2 quality-owner lock |
| M62 | stock release gate | L2 exact scoped release/exception consumption before stock insert |
| M63 | operation release gate | L2 exact scoped release/exception before completion event |
| M64 | versioned QM snapshots | L1 concrete feedback/goal/procedure/objective typed revision FKs |
| M65 | idempotent scheduled review | L1 unique company/goal-revision/occurrence key |
| M66 | append-only quality correction | L2 append-only and reversal/supersession triggers |
| M67 | evidence before quality projection | L2 atomic evidence/outbox; monotonic projector checkpoint |
| M68 | relational quality integrity | L1 FKs, unique, check and exclusion constraints |
| M69 | serializable quality decisions | L2 deterministic owner locks + L1 idempotency/uniqueness |

Every invariant gets at least one refusal test at its primary layer and one concurrency/retry test where
L2/L3 participates. No scheduled “repair” job is accepted as enforcement.

---

## 4. Concrete records and keys

[`FINAL-SCHEMA.md` §11–§17](../design/FINAL-SCHEMA.md) contains the complete production table contract.
This section states the ownership boundaries and keys that commands depend on.

### 4.1 BOM, route and policy revisions

- `bom` is stable identity; `bom_revision(company_id,bom_id,revision_no)` is effective-dated and freezes
  output quantity/UOM, explosion, backflush and cost policy at approval. `bom_component` and
  `bom_output` use stable line IDs and bind to immutable route nodes through operation keys. Active
  defaults are exclusion/partial-unique guarded.
- `bom_revision_edge` is the typed dependency DAG. A component BOM must declare the matching output;
  an item merely appearing as an input is not ownership—ERPNext currently accepts that broader match
  (`manufacturing/doctype/bom/bom.py:1425-1455`).
- `bom_cost_snapshot` and `bom_cost_source` are append-only and identify source kind, row, effective
  instant, currency/rate and calculator version. ERPNext's child cost formula divides child base cost by
  child output quantity (`manufacturing/doctype/bom/services/costing.py:128-138`); we retain the formula
  with typed currency and fixed decimal arithmetic, not mutable submitted-BOM totals.
- `route_revision`, `operation_revision`, `resource_rate_revision` and
  `resource_calendar_revision` each require `effective_to > effective_from` and a GiST exclusion over
  approved half-open ranges for their stable identity. Date resolution therefore yields exactly one
  approved revision; execution may cite an exact revision, but overlap is never a way to choose it.
  `route_operation` and `route_edge` hold explicit precedence. Parallelism is absence of an edge, never
  repeated sequence integers. `production_policy_revision` freezes backflush, loss, coproduct, Standard
  Cost, quality and overproduction policy named by a Work Order.

### 4.2 Planning, MPS and release

`planning_run` freezes `as_of_at`, source watermark and revision set. `planning_demand` preserves item,
warehouse, owner, custodian, due date, demand class, source line and stock-UOM quantity.
`planning_requirement`, `planning_supply_allocation` and `planning_proposal` preserve explosion path and exact netting. Supply
is allocated once by dated identity; safety stock, MOQ and lot sizing are applied once.

Approval freezes proposal rows; `proposal_release` is a separate idempotent command keyed by
`(company_id, proposal_id, release_kind)`. It re-locks source owners and invokes ordinary WO/transfer/
purchase/subcontract validators. Caller-supplied report rows are never commitments.

This explicitly rejects the pinned MPS path: `on_submit` enqueues `make_mrp`
(`manufacturing/doctype/master_production_schedule/master_production_schedule.py:439-447`), but the
DocType is not submittable and the pinned tree contains no `make_mrp` or MRP Log. We implement a real
persisted run and durable job, or expose no submit promise—never an unreachable hook.

### 4.3 Capacity and shop-floor execution

A resource has approved non-overlapping `resource_capacity_revision`, `resource_rate_revision` and
`resource_calendar_revision` rows. Reservation and downtime snapshot the exact revisions, expand their
half-open interval into `resource_capacity_commitment` slices on the single
`resource_day_capacity(company,resource,local_date,capacity_revision)` surface, and lock every affected
day in sorted order. One deferred summed trigger counts reservation **and** downtime units at every
instant against snapshotted available capacity; unit and parallel resources use the same rule. A
multi-day reversal compensates the identical slice set. Downtime that conflicts must be refused or, in
the same locked transaction, reverse affected reservations and append replacement slices—no mutable
reschedule flag. ERPNext instead checks overlap before later writes without one owner lock (see doc 34
§5 and `manufacturing/doctype/job_card/job_card.py:443-601`).

`work_order` is immutable after release and names exact BOM/route/policy revisions, output, warehouses,
owner, custodian and demand allocation. `work_order_material` and `work_order_operation` are compiled
snapshots. `execution_lot` has unique `(work_order_operation_id,ordinal)`. `work_event` records start/pause/resume/
stop/output/loss/employee participation; `resource_usage_cost` snapshots rate revision and is allocated
once to output. Status, planned/actual totals and floor tiles are projections.

### 4.4 Production conversion, WIP and costing

One immutable `production_conversion` authorisation owns quantity-only `production_input`,
`production_output` and `production_loss` lines. Those rows are complete on insert and never contain a
move ID, later valuation or voucher ID. Stock moves cite stable line IDs; later append-only
`production_*_stock_link`, `production_*_value` and `production_conversion_voucher` facts associate
moves, authoritative values and the existing voucher only after each exists. Inputs name exact locked
residual allocations; outputs distinguish principal FG, semi-finished, scrap, by-product and rejected
output. Loss distinguishes normal/abnormal reason. A partial Material Consumption cannot suppress
unrelated Manufacture inputs: ERPNext's existence-based `raw_materials_already_consumed` creates that
defect (doc 37 §14.2); M32 requires quantity-complete allocation.

For every conversion, in company currency, exactly once:

```text
Σ output stock value
  (principal + semi-finished + by-product + valued scrap,
   including the one normal-loss absorption allocated into surviving outputs)
+ Σ abnormal-loss expense
+ Σ explicit variance
  = Σ realised input value + Σ resource/service cost + Σ landed cost
```

Normal loss has zero separate value/expense and is represented once by the named absorption component
inside surviving output values. Abnormal loss is represented once by its named expense/variance account
leg. Valued scrap is a `production_output(output_role='scrap')` and cannot also carry loss value. Under
Standard Cost, output value uses exact `item_standard_cost`; actual minus standard posts once to the
named manufacturing variance account. No variance is hidden in WIP or FG. Money balances exactly at
`numeric(19,4)`; deterministic residual assignment creates an explicit final allocation line.

WIP transfer is paired immutable stock evidence with the same item, owner, policy revision and tracked
units: total quantity and authoritative company inventory value are both zero across source/target.
`stock_move` is immutable quantity authority. `stock_value_event` is immutable signed value authority:
every valued move gets one initial event, and a backdated replay appends net adjustment events and linked
balanced adjustment vouchers rather than changing conversion/GL facts. `stock_valuation_state` remains
a rebuildable candidate/projection. Stream watermarks record replay through-sequence and closed-through
posting time; replay may insert behind a watermark only while locked and advances it only after all
adjustments/vouchers exist. Closed-period history uses ordinary override/current-period adjustment rules.
The bridge is the signed sum of **all** value-event kinds (initial, backdate adjustment, manual
revaluation and negative reversal) = the signed sum of exact `stock_value_gl_allocation` rows. Each
allocation names one inventory `gl_entry`; every event's allocations sum to its delta and every inventory
leg is allocated exactly once, so one voucher may serve multiple events without duplicate counting. The
projection reconciles to that authority through its watermark. Source value authority completes before
dependent outputs.

### 4.5 Supplier subcontracting and customer-owned custody

`subcontract_authorisation` names supplier/customer direction, commercial source line, service/FG
ratio, recipe and policy revisions. `subcontract_material_allocation` identifies each required/sent/
returned/consumed lot. Inventory owner/custodian records are company-scoped and their party-bearing kinds
are constraint-trigger checked against `party.kind` and company. Valuation policy is an approved,
non-overlapping immutable `inventory_owner_policy_revision` snapshotted on every move/conversion.

`custody_transfer` stores explicit from/to owner, custodian and owner-policy revisions, source/target
moves and value events, tracked-scope hash and typed title authority. A deferred paired constraint proves
opposite quantity, identical tracked units (or batch sums), exact before/after dimensions and value/GL
conservation. Custody-only transfer preserves owner; title transfer alone may change it and requires the
named authority and either value conservation or one balanced policy-change voucher. Supplier-held
company material remains company-owned. Customer-provided material has customer owner and company
custodian; zero company valuation is policy, not provenance.

The base stock stream key is `(company_id,item_id,warehouse_id,owner_id,custodian_id)`; batch/serial
allocations and valuation add their tracked scope. Generic transfer cannot change owner. This fixes
ERPNext's inward gap: SLE has no owner and ownership is inferred from mutable Item/Warehouse plus zero
valuation; SCIO validates a customer tag but not matching warehouse company
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:143-151`).

BOM and transferred-material backflush remain separate versioned policies. Both consume exact allocation
residuals; neither reads unlocked item/warehouse aggregates. [S08](../scenarios/S08-supplier-subcontracting.md)
shows the same transfer/output consuming different RM quantities under the two upstream policies. We
preserve the choice but remove policy divergence from identity, locking and completeness guarantees.

### 4.6 Quality evidence, release and QM

`quality_criterion_revision` has exact mode checks: numeric requires canonical UOM and at least one
bound and forbids text/formula fields; value requires nonblank expected text and forbids UOM/bounds/
formula; formula requires a validated constrained AST, canonical hash and frozen evaluator version and
forbids expected/bounds. `inspection_requirement` freezes one complete approved template criterion set,
its count/order/UOM/hash and full company/owner/custodian/source/item/quantity/lot/direction scope.
Attempts have ordinal identity. Each observation points to a requirement-criterion, has an exact position
in `1..required_observations`, and stores mode-compatible canonical decimal/text plus original locale.
A deferred trigger proves attempt/requirement/criterion agreement, exact complete positions, subject UOM
compatibility and one snapshotted canonical conversion. Evaluations store pass/fail/error, expression
hash/version and trace; missing, blank, extra, duplicate, wrong-unit or wrong-criterion samples hold.

Disposition/release is aggregate authority over that complete frozen criterion set. Under the quality-
owner lock there is exactly one current unreversed disposition and release/hold per requirement revision;
Accepted/release requires a current pass for every criterion and the exact coverage hash. Released
quantity is mandatory. `quality_gate_consumption.consumed_qty` is positive, scoped, and the deferred
residual rule requires the unreversed sum not exceed released/exception quantity. Stock/operation
consumption must match the whole foreign scope and full criterion coverage before dependent evidence.
Warn consumes a separate authorised unexpired exception, never Accepted fiction. One external receipt
may create plural gate rows using stable child ordinals/scope hashes.

Concrete immutable/versioned QM records close M57/M64: feedback template/question revisions and
responses; goal/objective revisions, scheduled review occurrences and review results; procedure
revisions/edges; non-conformance; actions, tasks and append-only action events; meetings/items; and typed
`quality_evidence_link` rows whose source-revision enum maps to a concrete immutable revision FK.
Scheduled review identity is `(company_id,goal_revision_id,due_date,occurrence_no)` and inserts-or-gets
under a unique constraint. This removes the pinned scheduler duplicate path, whose insert has no
existence check or unique occurrence (`quality_management/doctype/quality_review/quality_review.py:67-72`).

---

## 5. Deterministic locks, idempotency and projectors

### 5.1 Canonical state machine and lock order

This section and [`FINAL-SCHEMA.md` §17](../design/FINAL-SCHEMA.md) are one normative state machine;
all commands in §6 reference it. Establish the authenticated transaction-local tenant context first;
this is not a business write. Then, before any business side effect, run the idempotency insert-or-select/
replay/wait-or-takeover/commit-discovery protocol in §5.2. Apply company/period/lifecycle guards after the
receipt claim. Commands acquire only needed owners, sorted lexicographically inside
these classes and never acquire an earlier class after a later one:

1. period/company policy;
2. commercial/demand source lines;
3. definition/effective-range publish owners;
4. Work Order, material, operation, subcontract and allocation owners;
5. quality owner/requirement;
6. resource-day capacity owners;
7. stock streams `(item,warehouse,owner,custodian,batch/serial)`;
8. account-balance owners.

Under those locks validate all residual, revision, capacity, quality, tracked-unit and dependency rules;
insert complete immutable authorisation/quantity facts; insert source-before-target quantity/tracked
stock evidence and links; append initial/adjustment value authority and value links to the watermark;
insert exact cost allocations and existing voucher/GL/link facts; run deferred checks; allocate
contiguous event/outbox positions; commit; publish receipt result; then project. Preview allocates
nothing, and a stock-stream lock never substitutes for a Work Order ceiling lock.

### 5.2 Idempotency and durable work

Every externally callable command has one durable
`(company_id,command_kind,idempotency_key) UNIQUE` receipt with request hash, actor, state, lease,
attempt, business-commit token, result hash/children and retained error. Before side effects it performs
insert-or-select. Different hash is terminal; matching succeeded/terminal-failed replays exactly;
matching live in-progress waits and reselects; expired lease or retryable failure is taken over by
compare-and-swap. The receipt's business-commit token is company-scoped unique. The fact transaction
reserves one deferred commit-marker ID, writes the complete receipt-linked authority graph and event/
outbox rows, then inserts one append-only
`command_business_commit(receipt,token,result_manifest,result_set_hash,root_count,event_set_hash)`.
Deferred checks recompute its graph/count/hashes. Takeover treats that one-to-one marker as the sole
commit-discovery proof: present means publish child results/replay success, absent means the business
transaction rolled back and may be retried. Success is published after the business commit. Terminal/
retryable error is retained in a separate control transaction after business rollback, so a failed
business transaction leaves no partial facts but never loses its receipt.
A crash between commit and receipt completion is repaired by discovery. One external receipt has plural
`command_result_child(command_receipt_id,child_ordinal,result_scope_hash,...)`; child tables use that
ordinal/scope hash, never `UNIQUE(command_receipt_id)`.

Each aggregate has one locked `production_aggregate_owner.next_event_position`. The fact transaction
allocates exactly that position, inserts one append-only `production_event` and exactly one
`transactional_outbox(event_id UNIQUE FK)` row, and advances the owner; all commit or roll back together,
so aborted work consumes no position and committed streams have no gaps. Outbox aggregate/type/position/
payload are derived by joining the event, never duplicated independently. Publication uses
`FOR UPDATE SKIP LOCKED`. A projector checkpoint advances only to the next contiguous event and modifies
projections only. BOM refresh, planning and schedules use the same lease/takeover/retained-failure
protocol. Projection lag is observable; projectors never create authority or posting evidence.

---

## 6. Exact command/write ordering

### 6.1 Definition publication and refresh

**BOM/route/criterion/calendar publish:** lock stable definition and effective-range owner → validate
positive quantities/UOMs/company and graph acyclicity → insert immutable revision and children/edges →
insert approval event/default range → insert outbox → commit. Cost/explosion refresh then claims a
durable work item, locks one projection key, verifies exact child fingerprints, appends cost snapshot,
atomically replaces projection, advances checkpoint and completes attempt. It never mutates approved
revision rows. This replaces upstream BOM update paths that mutate submitted BOMs and publish work
before its batch row commits (doc 33 §§7.2–7.5).

**Revision reversal/supersession:** lock definition/default owner → insert superseding revision or
withdrawal event/effective-end → preserve old revision and all production FKs → elect a new default only
by explicit policy → outbox/project. Posted production is never repointed.

### 6.2 Planning and release

**Plan/MPS:** lock planning command idempotency row → freeze watermark/revision set → insert demand → run
one cycle-safe explosion → insert gross requirements → lock supply owners in order and insert allocation
rows → apply safety/lot policy once → insert exceptions/proposals/result hash → approval event/outbox →
commit. **Release:** lock proposal and source owners → revalidate residual/date/capacity/policy → insert
ordinary WO/transfer/purchase/subcontract authorisation with unique release key → insert allocations →
outbox → commit.

**Plan reversal:** reverse only unreleased allocations/proposals first. Released supply is an independent
authorisation and must be reversed in downstream dependency order; the plan then receives linked
release-reversal facts and is closed. No generated document is silently deleted.

### 6.3 Capacity, Work Order and Job Card/execution

**WO release:** after canonical idempotency claim, lock demand/proposal and production owners → validate
immutable revision FKs → insert WO, material/operation snapshots and demand/material allocations →
create deterministic execution-lot identities with receipt child ordinals → reserve capacity by expanding
snapshotted capacity/calendar intervals under sorted resource-day locks → event/outbox → commit → project.
**Actual work:** claim receipt → lock operation/execution lot/resource and quality owner → append work,
resource-usage and required aggregate quality-consumption events → event/outbox → commit → project.

**Reversal:** in one canonical deferred transaction reverse operation/output quality consumptions first
→ append work-event/resource-cost/capacity-commitment reversals → reverse execution-lot serial and output
allocations through unreversed chains → reverse WO demand/material allocations → append a
`work_order_lifecycle_event('reverse')`. No `is_current`, mutable state or “mark reversed” write exists.
A WO with surviving conversion/custody/output facts cannot reverse.

### 6.4 WIP/conversion, stock, Standard Cost and GL

One database transaction follows §5.1/`FINAL-SCHEMA` §17:

1. establish authenticated tenant context, then claim/replay/wait/take over idempotency and perform
   business-commit discovery **before business side effects**;
2. apply company/period/lifecycle guards; lock WO/material/output, quality, resource-day,
   stock-stream and account owners in canonical order;
3. validate exact residuals, tracked units, frozen owner/policy revisions, complete aggregate quality
   coverage and output/loss entitlement;
4. insert complete immutable conversion authorisation plus quantity-only input/output/loss lines and
   bounded quality gate consumptions;
5. insert source, paired WIP and dependent output stock moves, tracked edges and append-only stock links;
6. compute valuation to locked stream watermarks; append initial and required replay-adjustment
   `stock_value_event` rows and complete input/output value links—never update conversion/GL facts;
7. allocate normal-loss absorption, valued scrap, abnormal-loss expense and Standard Cost variance once
   under the §4.4 equation;
8. insert existing voucher/GL rows, exact value-to-GL allocations and conversion-voucher links;
   deferred checks require exact journal balance, all-signed-value-event↔GL, ownership, quality and
   conversion-cost equality;
9. insert contiguous event/unique-outbox pairs and the validated one-to-one command commit marker;
   commit; publish receipt results; then project.

**Exact reversal:** claim idempotency before effects and take the same locks → require downstream
delivery/billing already reversed or included → insert reversals of all affected gate consumptions
**first** → append dependent operation/work/capacity reversals → append target-before-source stock/
tracked reversals → append reversing value events and balanced voucher/links → append conversion/cost/
allocation/lifecycle reversals → event/outbox → commit/project. Deferred checks permit intermediate
rows only inside this transaction and require the complete compensation at commit. A Work Order-wide
average recovery is a new authorised transformation, not exact reversal. [S07 §10](../scenarios/S07-make-to-order-manufacturing.md#10-cancellation-blockers-and-safe-reversal-order)
shows the business dependency order: Delivery → Manufacture outputs newest-first → separate Consumption
→ WIP Transfer → Job Cards → Work Order → Production Plan.

### 6.5 Supplier/customer subcontracting

**Supplier:** after canonical receipt claim, lock PO service line/SCO/material owners → insert service/FG
authorisation → reserve/send explicit paired custody moves with from/to dimensions → append value events/
GL links (normally value-conserving) → event/outbox/project. Receipt locks exact transfer residuals →
inserts one conversion with material inputs and FG/secondary/scrap/loss outputs → appends stock/value
links → service/additional/landed cost allocation → balanced GL/links → optional idempotent commercial
receipt link → event/outbox/project.

**Customer-owned inward:** lock SO service line/customer-owner custody stream → receipt paired moves at
zero company asset value → allocate exact owner lots to ordinary WO/execution → conversion may add only
company cost/value allowed by policy → customer-facing delivery references exact output lots → billing
separately allocates service and company material. Owner remains customer until explicit title transfer.

**Reversal:** use the canonical one-transaction reversal: affected quality gate consumption first, then
commercial billing/receipt dependencies, customer delivery/output, conversion receipt, material
consumption and custody return/send, followed by value/GL and source-authorisation compensations in the
canonical evidence order. Each row cites original owner, custodian, policy, lot, paired transfer and cost
allocation; projections follow committed reversal evidence.

### 6.6 Quality

For Accepted, claim idempotency first; lock owner/requirement/source; verify the frozen full criterion set
and exact samples; append observations/evaluations, one current signed disposition and aggregate release;
then append quantity-bounded gate consumptions in the same transaction as operation/stock evidence under
the canonical state machine. For Warn, append and consume a quantity-bounded authorised exception with
actor/reason/expiry, never Accepted fiction. Missing/foreign/draft/rejected/incomplete evidence blocks
before dependent writes. Plural generated requirements/gates use one receipt plus child ordinals.

**Quality reversal:** in the same deferred transaction, append gate-consumption reversals first, then
operation/stock/value/accounting compensations in canonical order, then release/disposition
supersession/reversal. Retain observations/evaluation trace. Event/outbox and receipt publication follow
the canonical protocol. Scheduled reviews use unique occurrence identity; retries replay the child.

---

## 7. Evidence versus projection

| Authoritative append-only facts | Rebuildable projections/read models |
|---|---|
| approved definition revisions and approval/supersession events | current/default BOM/route/criterion |
| planning run inputs, requirements, supply allocations and releases | projected demand/supply, MPS dashboard |
| WO authorisation and allocation rows | WO/operation percent, planned/produced/lost/status |
| capacity reservations, downtime and actual work events | resource availability, Plant Floor tiles |
| production/subcontract conversions and exact allocations | pending/transferred/consumed/received quantities |
| owner-aware stock moves/tracked edges; initial and adjustment `stock_value_event`; linked vouchers | valuation candidate/state, stock balance/Bin |
| cost-source/normal-loss/scrap/abnormal-loss allocations and balanced GL entries | WIP/account balances and cost summaries |
| observations, evaluations, dispositions, aggregate release/exception consumption; QM version/evidence facts | QI links/status, QM roll-ups and dashboards |

A projection can lag or be rebuilt; it cannot authorise, release, value or post. Projection drift raises
an operational alert and replay, not a mutation of facts. The weekly upstream repair job that scans
stock valuation/account variance is therefore not copied (doc 32 §2.3).

---

## 8. Adopt / Change / Reject matrix

| Upstream mechanism | Decision | Target |
|---|---|---|
| BOM positive quantities, operation gates and recursive cycle technique | **Adopt rules** | publish-time constraints and one graph function |
| Submitted mutable BOM totals/explosion | **Reject** | immutable revision + append-only cost snapshot/rebuildable explosion |
| BOM update bottom-up frontier and durable log concept | **Adopt/Change** | fingerprinted DAG work items, leases, outbox, visible failure |
| Operation/routing/workstation concepts | **Adopt/Change** | immutable route/resource/calendar/rate revisions |
| Half-open capacity intervals and greedy availability query | **Adopt** | database-serialised reservation |
| Unlocked overlap checks and inconsistent calendar functions | **Reject** | exclusion/resource-day lock and one calendar function |
| Work Order authorisation, batch splitting and Job Card facts | **Adopt concepts** | frozen WO, deterministic lots, append-only work events |
| Mutable submitted counters/direct `db_set` roll-ups | **Reject** | event-positioned projectors |
| Production Plan demand collection and BOM explosion intent | **Adopt/Change** | immutable dimensioned planning run and one explosion engine |
| In-memory MRP report rows creating supply | **Reject boundary** | approved proposal + locked idempotent release |
| MPS dead submit hook/missing `make_mrp` | **Reject unfinished** | real durable implementation or no feature promise |
| WIP as ordinary warehouse inventory | **Adopt** | owner-aware stock plus production allocation |
| Source-before-target valuation and SLE value driving GL | **Adopt/strengthen** | dependencies plus immutable initial/adjustment value events and exact linked-GL trigger |
| BOM and transferred-material backflush | **Adopt as named policies** | versioned complete exact allocation algorithms |
| Partial-consumption existence suppressing all inputs | **Reject defect** | M32 quantity completeness |
| Standard Cost variance | **Adopt exactly** | standard stock value, actual-standard named GL variance |
| Supplier warehouse custody and receipt conversion | **Adopt** | owner/custodian allocation and common conversion ledger |
| Customer warehouse as ownership proxy | **Reject gap** | explicit immutable owner on every stock identity |
| Operational QI separate from QM | **Adopt boundary** | exact release service; QM references but cannot post |
| Template criteria/order and inclusive min/max | **Adopt/Change** | immutable revisions, canonical observations, complete samples |
| `reading_1..10`, mutable locale parsing and runtime formula shape | **Reject** | observation rows and constrained versioned evaluator |
| Stop gate | **Adopt default** | exact Accepted release required |
| Warn/draft/rejected and allow-after loop return | **Reject/Change** | durable authorised exception; every row checked |
| Scheduler-created reviews | **Adopt/Change** | unique occurrence and retry-safe insert |
| Append-only stock/GL accounting core | **Adopt and strengthen** | value-adjustment events/vouchers, universal reversal links, exact balance, authenticated RLS/owner dimensions |

---

## 9. Pinned upstream defects and unfinished paths

These findings remain explicit acceptance tests; they are not “implementation details” to rediscover.

1. **MPS is unfinished:** non-submittable metadata, dead `on_submit`, missing `make_mrp` and MRP Log
   (`manufacturing/doctype/master_production_schedule/master_production_schedule.py:439-447`).
2. **BOM save/update consistency:** explosion can be saved before stock quantity refresh
   (`manufacturing/doctype/bom/bom.py:318-331`); deep operation recursion discards its returned total
   (`manufacturing/doctype/bom/services/operations_cost.py:266-281`); Creator preview/publish currency
   paths diverge; work can publish before commit (`frappe/utils/background_jobs.py:68-122`); and Update
   Log mutates submitted ancestors (doc 33 §§4–7).
3. **Capacity races:** overlap/capacity selection and the later insert have no owner lock
   (`manufacturing/doctype/job_card/job_card.py:443-601`); disabled/off resources can enter type pools;
   calendar paths disagree on adjacency, row ordering and consecutive holidays
   (`manufacturing/doctype/workstation/workstation.py:169-225`,
   `manufacturing/doctype/job_card/job_card.py:602-713`).
4. **Partial consumption:** one submitted partial consumption can suppress every Manufacture input
   (`stock/doctype/stock_entry/services/manufacturing.py:392-419`).
5. **Ownership gaps:** customer stock has no SLE owner, cross-company custody validation is incomplete,
   and zero value is used as legal provenance
   (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:143-151`; S10 §§3–6).
6. **Backflush policy divergence:** BOM versus transferred-material modes can consume 10/5 versus 8/4
   for the same supplier transfer/output (S08 §§7–8; source algorithms in
   `controllers/subcontracting_controller.py:932-956` and
   `controllers/subcontracting_controller.py:911-983`); policy must be explicit, versioned and complete.
7. **QI early return:** allow-after exits the whole transaction-row loop, making validation row-order
   dependent (`stock/services/quality_inspection_service.py:84-109`).
8. **QI foreign scope:** gates trust a mutable QI link/status without proving company/line/item/quantity/
   lot/direction/revision scope (`stock/services/quality_inspection_service.py:110-149`).
9. **QI formulas/samples:** ten optional Data readings
   (`stock/doctype/quality_inspection_reading/quality_inspection_reading.json:14-218`), no sample-size
   reconciliation (`stock/doctype/quality_inspection/quality_inspection.py:302-309`), locale-dependent
   parsing (`stock/doctype/quality_inspection/quality_inspection.py:512-527`) and runtime `safe_eval`
   formulas (`stock/doctype/quality_inspection/quality_inspection.py:311-351`) cannot establish
   deterministic evidence.
10. **QI scheduler/procedure races:** review insertion has no unique occurrence
    (`quality_management/doctype/quality_review/quality_review.py:67-72`); procedure reciprocal writes
    are unlocked (`quality_management/doctype/quality_procedure/quality_procedure.py:74-126`); direct
    writeback can evade normal audit (doc 39 §§9–13).

---

## 10. Build sequence and boundary

No application implementation has started. When Assets have been investigated and implementation is
authorised, build in dependency order:

1. **Foundation:** migrations, stable enums, authenticated principal/membership tenant context,
   RLS + `FORCE RLS` and forgery tests, durable lease/takeover command receipts with child results,
   append-only triggers, aggregate-owner event/unique-outbox checkpoints and exact-decimal helpers.
2. **Existing accounting/stock core:** typed owner/custodian keys and versioned policy snapshots,
   immutable quantity moves plus initial/adjustment value events and linked vouchers, valuation
   projections/watermarks, voucher/GL exact balance, canonical reversal and value-event↔GL checks.
3. **Versioned definitions:** production policy, BOM/route/operation/resource capacity/calendar/rate and
   quality criterion/template revisions; approved effective-range exclusions, graph publication and
   cost/explosion snapshots.
4. **Planning/capacity:** planning runs, demand/supply allocations, proposals/releases and one
   snapshotted resource-day commitment surface for reservation plus downtime.
5. **Execution:** WO snapshots/lifecycle events, deterministic execution lots, unreversed tracked-unit
   chains, actual-work/resource-cost facts, reservations and projections.
6. **Conversion/accounting:** quantity authorisations followed by append-only stock/value/voucher links,
   WIP, complete input/output/loss equation, Standard Cost variance, exact reversal, tracked continuity
   and authoritative value/GL bridge.
7. **Subcontracting/ownership:** supplier custody, customer-owned inward, explicit from/to owner/
   custodian/title authority and both backflush policies.
8. **Quality/QM:** frozen complete requirement sets, exact canonical samples/evaluation/disposition,
   bounded aggregate stock/operation releases/exceptions, feedback/goals/reviews/non-conformance/actions/
   meetings and typed evidence links.
9. **Scenario/concurrency acceptance:** reproduce S07–S10, then run duplicate retry/lease takeover/
   commit discovery, interleaving, backdated valuation adjustment, reversal, RLS forgery and projection-
   rebuild tests for every M invariant.

**Assets remain deferred before implementation.** Tranche C must specify capitalisation, depreciation,
movement, impairment/repair and disposal against the same immutable voucher/GL boundary before the
investigation can be declared complete.

---

Cross-references: [FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md),
[INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md), [COVERAGE.md](../COVERAGE.md),
[docs 33–39](README.md#tranche-b--production-investigation-complete), and
[scenarios S07–S10](../scenarios/README.md#the-scenarios).
