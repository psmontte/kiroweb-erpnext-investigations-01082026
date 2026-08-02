# 44 — Tranche C Coverage Closure and Our Asset Specification

> **Tranche C deliverable.** This closes the assets investigation and consolidates docs
> [41](41-asset-identity-acquisition-and-finance-books.md)–[43](43-asset-custody-maintenance-repair-and-disposal.md)
> and scenario [S11](../scenarios/S11-asset-lifecycle.md) into the backend/database contract we will build.
>
> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev). ERPNext citations are `path:line`
> relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are prefixed `frappe/`.

This is a specification, not an implementation report. **Application implementation has not started.**
The asset design below extends [`FINAL-SCHEMA.md` §19–§23](../design/FINAL-SCHEMA.md); it does not supersede
the accounting, stock, trade, settlement, production or platform guarantees already fixed there and in
[doc 25](25-our-platform-spec.md) and [doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md).

Assets were **deferred by decision** through Tranches A, B and E and are now investigated. With this
document, every module we chose to audit is closed at controller depth, and the remaining named gap is
**localisation — India GST first** (§11).

---

## 1. Measured closure, not an assertion

The generated audit in [`docs/COVERAGE.md`](../COVERAGE.md) measures a parent DocType as covered only when
its controller is cited at a line number. The final measured state across every audited module is exactly:

| Module | DocTypes | Controller cited | Uncited (submittable) | Uncited (config) | Excluded |
|---|---:|---:|---:|---:|---:|
| Accounts | 92 | 78 | 0 | 0 | 14 |
| Stock | 45 | 42 | 0 | 0 | 3 |
| Selling | 12 | 9 | 0 | 0 | 3 |
| Buying | 10 | 5 | 0 | 0 | 5 |
| Subcontracting | 4 | 4 | 0 | 0 | 0 |
| Manufacturing | 18 | 18 | 0 | 0 | 0 |
| Quality Management | 8 | 8 | 0 | 0 | 0 |
| **Assets** | **14** | **14** | **0** | **0** | **0** |
| **Total** | **203** | **178** | **0** | **0** | **25** |

**Assets: 14/14 parents cited, zero submittable and zero configuration gaps, zero exclusions.** The 25
deliberate exclusions elsewhere are retained and listed in
[`COVERAGE.md`](../COVERAGE.md#deliberate-exclusions); none of them is an asset DocType. Child tables are
covered with their parents.

Asset depth is supplied by:

- [doc 41](41-asset-identity-acquisition-and-finance-books.md): identity, the four asset types, acquisition
  paths, conditional capitalisation, Asset Capitalization, categories/accounts, finance books, Locations,
  activity;
- [doc 42](42-depreciation-engine-schedules-shifts-and-adjustments.md): schedule generation, all methods,
  proration and salvage landing, the daily posting job, replanning, shifts, revaluation, disposal-date
  depreciation and restoration;
- [doc 43](43-asset-custody-maintenance-repair-and-disposal.md): custody, maintenance planning and logs,
  repair cost and consumption, splitting, and all four disposal callers; and
- [S11](../scenarios/S11-asset-lifecycle.md): the worked lifecycle with exact numbers, every table write in
  order, and the balance proof showing which two accounts are misstated and why.

### 1.1 The finding that frames the whole design

S11 §8 runs one asset through purchase, recognition, six depreciation periods, a capitalised repair, a
partial sale and a scrap, and ends with both balance-sheet accounts non-zero:

```text
Fixed Asset — Machinery : 123,000.00 debited, 120,000.00 removed  → 3,000.00 left (debit)
Accumulated Depreciation:   7,629.45 posted,    4,629.44 removed  → 3,000.01 left (credit)
```

The two residuals are **the same number with opposite signs**, and provably so: each disposal debits
accumulated depreciation with `net_purchase_amount − value_after_depreciation`, so the residual on both
sides is exactly `additional_asset_cost` regardless of instalment, period count or disposal timing (S11
§8.1 carries the algebra; the trailing 0.01 is the split-rounding cent).

That makes the finding narrower and sharper than "the books do not close":

- every voucher balances, **net book value removed is correct**, and both gain and loss are correct;
- but **cost is overstated by 3,000.00 and accumulated depreciation is overstated by 3,000.00** — the
  capitalised repair is silently reclassified as depreciation on the balance sheet.

Invisible in the P&L and in net assets; visible in the gross-cost and accumulated-depreciation columns of
every fixed-asset register, in depreciation-to-cost ratios, and in any statutory note that discloses the two
separately. A revaluation reclassifies identically (doc 42 §8).

The root cause is one thing: disposal removes `net_purchase_amount` and an accumulated-depreciation figure
**derived by subtraction** (`assets/doctype/asset/depreciation.py:639-695`,
`assets/doctype/asset/depreciation.py:696-716`) while capitalised repair raised book value through a
different field (`assets/doctype/asset_repair/asset_repair.py:242-254`). **Cost and accumulated depreciation
must each be read from their own ledger** — which is what §4–§8 enforce structurally.

---

## 2. Governing asset model

The four-layer rule from [doc 25 §2](25-our-platform-spec.md#2-the-layering-rule) applies unchanged:
structural truth at **L1 schema**, cross-row truth/tenancy/immutability at **L2 triggers and RLS**, ordered
commands at **L3 orchestration**, pure computation at **L4 services**. Assets add five consequences.

1. **An asset is one identified unit.** There is no `asset_quantity`. Multiple units are multiple assets, or
   an explicit composite with member rows. Identity is allocated from a source line, never matched by amount.
2. **Cost is a stream, book value is a projection.** Gross cost, accumulated depreciation, revaluation
   reserve and impairment are each `Σ` over their own facts, reconciled to their own GL accounts.
3. **The plan is not the posting.** A depreciation plan is an immutable version of an approved policy; a
   posted period is a separate fact keyed by period. Replanning supersedes; it never edits, re-links or
   inherits postings.
4. **Time-driven posting is idempotent by period identity.** Selection is by plan state and period dates
   only — never by mutable asset status, index windows, or the roles of the session running the job.
5. **Every exit is one disposal event.** Scrap, sale, capitalisation and transfer-out share one derivation
   and one uniqueness guarantee.

All asset tables carry `company_id NOT NULL`, company-scoped keys, `ENABLE ROW LEVEL SECURITY` and
`FORCE ROW LEVEL SECURITY` with policies bound to authenticated tenant context (not a caller-settable GUC).
Money is `numeric(19,4)`; quantities, factors and rates are `numeric(21,9)`; percentages are
`numeric(9,6)`. Persisted state/kind codes are stable lower-case enum codes, never translated display text.

---

## 3. A1–A26: exact register and enforcement owner

Names are preserved exactly from docs 41–43. Three names intentionally recur across boundaries:
**A7, A16 and A24 are all "evidence before …  projection"** at the acquisition, depreciation and
custody/disposal boundaries respectively; **A8/A17/A25** are the relational-integrity trio; and
**A9/A18/A26** are the serializability trio.

| ID | Exact invariant name | Primary enforcement |
|---|---|---|
| A1 | an asset is an identified, conserved object | L1 `asset_source_allocation` uniqueness + L2 deferred source-residual trigger under source-line lock |
| A2 | asset state is derived, never stored authority | L2 append-only `asset_lifecycle_event`; L1 projector-only `asset_state_projection` |
| A3 | capitalisation is an explicit, complete, idempotent event | L1 partial unique unreversed `asset_recognition` + L3 `effective_on <= as_of` selection |
| A4 | additions to an asset are allocation facts | L1 `asset_cost_event` append-only + `asset_source_allocation` FKs |
| A5 | depreciation policy is an approved revision | L1 `asset_policy_revision` exclusion constraint on approved ranges |
| A6 | place, custody and audit are typed facts | L1 typed event codes and location revisions; L4 text rendered on read |
| A7 | evidence before asset projection | L2 atomic facts/outbox; projector position advances after commit |
| A8 | relational asset integrity | L1 unique/FK/check/exclusion constraints |
| A9 | serializable asset decisions | L2 deterministic asset and source locks + L1 idempotency uniqueness |
| A10 | the plan is not the posting | L1 separate `depreciation_plan_period` and `depreciation_posting`; no journal link on plan rows |
| A11 | deterministic, complete, exact schedules | L4 pure generator + L2 deferred `Σ planned_amount = depreciable_base` |
| A12 | depreciation posting is idempotent per period | L2 deferred unreversed-count trigger on `depreciation_period` under the asset/book lock |
| A13 | shift plans are explicit, conserved and named | L1 `shift_code` identity + factor revisions; L2 plan-total conservation |
| A14 | revaluation is an explicit, reconciled event | L1 separate reserve/impairment accounts + L2 per-account GL equality |
| A15 | disposal-period depreciation and reversal are dated facts | L1 `is_partial_to_disposal` period + `reversal_dating` on the reversal |
| A16 | evidence before depreciation projection | L2 atomic posting/outbox; monotonic projector checkpoint |
| A17 | relational depreciation integrity | L1 plan/period exclusion, partial unique active plan and posting |
| A18 | serializable depreciation decisions | L2 asset/book owner lock + L1 `(asset, book, period_start)` idempotency |
| A19 | custody and place are event-sourced | L1 stored `from_*`/`to_*` + L2 chain-continuity trigger |
| A20 | maintenance plans and occurrences are separate, non-cyclic records | L1 `(task_revision, occurrence_no)` and `(task_revision, due_date)` uniqueness; L3 one-way writes |
| A21 | repair and improvement are allocated cost facts | L1 `asset_service_cost_allocation` + `asset_service_book_apportionment` exact-sum trigger |
| A22 | splitting is an authorised transformation, not an edit | L1 `asset_transformation_part` + L2 per-book conservation trigger |
| A23 | disposal is one event with one exit reason | L2 deferred unreversed-count trigger per asset, plus typed `disposal_kind` |
| A24 | evidence before custody and disposal projections | L2 atomic facts/outbox before any projection write |
| A25 | relational custody, service and disposal integrity | L1 unique/FK/check/exclusion constraints |
| A26 | serializable custody, service and disposal decisions | L2 deterministic asset and source locks + L1 idempotency uniqueness |

Every invariant gets at least one refusal test at its primary layer and one concurrency/retry test where
L2/L3 participates. **No scheduled repair job is accepted as enforcement** — which is also why the
`Stock Reposting Settings` weekly stock↔GL repair scan (doc 32 §2.3) has no asset analogue in our design.

---

## 4. Concrete records and keys

[`FINAL-SCHEMA.md` §19–§23](../design/FINAL-SCHEMA.md) contains the complete asset table contract. This
section states the ownership boundaries and keys commands depend on.

### 4.1 Identity, acquisition and recognition

- `asset` is one identified unit: no quantity column, no four-way `asset_type` switch. Composite structure
  is `asset_component`; a component role is a typed flag, not a status string.
- `asset_source_allocation` binds an asset to the **exact** purchase line, consumed lot, consumed asset or
  service claim, bounded by a deferred residual trigger evaluated while the source line owner is locked.
  ERPNext instead resolves the link by matching `base_net_amount`/`base_net_rate` and quantity, without
  comparing item code, and falls back to quantity-only matching
  (`assets/doctype/asset/asset.py:314-325`); its ceiling is an unlocked aggregate over the whole document
  (`assets/doctype/asset/asset.py:521-562`).
- `asset_cost_event` is append-only and signed. Gross cost is `Σ` by kind class, so
  `net_purchase_amount == purchase_amount` field-equality guards
  (`assets/doctype/asset/asset.py:564-575`) become unnecessary rather than load-bearing.
- `asset_recognition` has one unreversed row per asset and is selected by `effective_on <= as_of`. This
  replaces both the four `frappe.db.exists` GL probes that decide whether to post
  (`assets/doctype/asset/asset.py:859-898`) and the daily job whose filter is
  `available_for_use_date = nowdate()` for CWIP-enabled categories only
  (`assets/doctype/asset/asset.py:1085-1103`). Construction-in-progress residual is the continuous view
  `asset_cip_residual`.
- `asset_capitalisation` children must name a real `stock_move_id` and realised value; a missing valuation
  is an error, not the silent zero of `raise_error_if_no_rate=False`
  (`assets/doctype/asset_capitalization/asset_capitalization.py:593-608`). Consuming an asset requires a
  real `asset_disposal` row, and the target's cost rises only through `asset_cost_event` — never by the
  read-modify-write of three amount fields on a submitted document
  (`assets/doctype/asset_capitalization/asset_capitalization.py:425-450`).

### 4.2 Policy, plans and postings

- `asset_policy_revision` freezes method, life, frequency, salvage, day basis, rate at full precision,
  shift policy and opening state per asset **and finance book**, with approved ranges guarded by an
  exclusion constraint. ERPNext copies category defaults into editable child rows
  (`assets/doctype/asset/asset.py:397-407`, `assets/doctype/asset/asset.py:1112-1137`), validates duplicate
  or blank books only when there is more than one row
  (`assets/doctype/asset/asset.py:408-429`), and rounds derived rates to System Settings
  `float_precision`, default 2 (`assets/doctype/asset/asset.py:1003-1052`).
- `depreciation_plan` has one `active` version per asset and book by partial unique index;
  `depreciation_plan_period` carries `basis_days`, an optional shift code, and **no journal link**, with a
  date-range exclusion constraint and `period_end` uniqueness. A zero amount must state a
  `zero_reason` and does not truncate the plan — upstream breaks out of the generation loop on the first
  zero (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:54-98`).
- `depreciation_period` is canonical period identity and at most one unreversed `depreciation_posting`
  exists per period. That is the guarantee replacing the nullable `journal_entry` column on a plan row, which is
  currently both the plan and the evidence of posting
  (`assets/doctype/depreciation_schedule/depreciation_schedule.py:8-27`).
- `depreciation_posting_attempt` records per-period outcomes, replacing the single per-asset
  `depr_entry_posting_status` scalar and the loop that keeps only the last error
  (`assets/doctype/asset/depreciation.py:169-218`).
- `asset_revaluation` posts to its own reserve or impairment account. ERPNext credits or debits the
  **fixed-asset** account (`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:131-158`) while
  leaving `net_purchase_amount` untouched, which is precisely why disposal later reclassifies the
  impairment as accumulated depreciation.

### 4.3 Custody, service, transformation and disposal

- `asset_custody_event` stores `from_*` and `to_*` dimensions and is chain-continuity checked, so custody
  is verifiable end to end. ERPNext recomputes two scalars from the latest submitted movement and writes
  them with `db.set_value`, guarded such that a blank target location never clears the location
  (`assets/doctype/asset_movement/asset_movement.py:128-160`).
- `maintenance_occurrence` is unique per `(task_revision, occurrence_no)` **and** `(task_revision,
  due_date)`; `overdue` is a view. Upstream has plan and log writing to each other — a submitted log saves
  the task child and then the parent, whose save re-syncs logs
  (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:62-78`,
  `assets/doctype/asset_maintenance/asset_maintenance.py:55-72`) — plus a daily bulk `UPDATE` that sets
  `Overdue` with no validation (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:80-91`).
- `asset_service_cost_allocation` keeps ERPNext's genuine ledger residual check
  (`assets/doctype/asset_repair/asset_repair.py:459-514`) but enforces it under a source lock, and
  `asset_service_book_apportionment` splits cost per finance book. Upstream adds the full repair cost and
  the full life extension to **every** book (`assets/doctype/asset_repair/asset_repair.py:242-254`,
  `assets/doctype/asset_repair/asset_repair.py:322-329`). A service event's reversal must reverse the
  inventory issue too; upstream leaves the `Material Issue` Stock Entry posted
  (`assets/doctype/asset_repair/asset_repair.py:221-234`).
- `asset_transformation_part` stores exact apportionment per measure and finance book, with one residual
  part. Upstream copies the document, scales every amount by a float ratio
  (`assets/doctype/asset/mapper.py:232-250`) and **amends posted depreciation journals** to reference the
  new asset (`assets/doctype/asset/mapper.py:272-288`).
- `asset_disposal` has one unreversed row per asset and derives its voucher from four fact sums. Upstream
  has four callers — scrap, Sales Invoice, Asset Capitalization and their reversals — each writing
  `disposal_date` and status with its own `db.set_value`
  (`assets/doctype/asset/depreciation.py:367-379`,
  `accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`,
  `assets/doctype/asset_capitalization/services/gl_composer.py:82-116`), and no uniqueness anywhere.

### 4.4 The closing identity

For every asset, in company currency and per finance book:

```text
net_book_value = Σ asset_cost_event(cost classes)
               − Σ depreciation_posting(unreversed)
               + Σ asset_revaluation(reserve classes)
               − Σ asset_revaluation(impairment classes)
```

where accumulated depreciation is `Σ depreciation_posting + Σ depreciation_attribution` (the second term
carries a split's share, so a transformation cannot orphan it). At disposal the voucher removes each term
from **its own** account, and because every asset-role `gl_entry` leg carries `asset_id` — and
`finance_book_id` where the account is book-scoped — each balance is a real query:

```text
fixed_asset balance(asset)                          = 0
accumulated_depreciation balance(asset, book)       = 0   for every finance book
revaluation_reserve balance(asset)                  = 0
```

This is the acceptance criterion for S11. The 3,000.00 reclassification of §1.1 is not merely avoided — it is
**unrepresentable**, because no leg is derived by subtraction from a mutable scalar. The split cent is
unrepresentable too: `asset_transformation_part` apportions exactly, with one designated residual part.

---

## 5. Deterministic locks, idempotency and projectors

### 5.1 Lock keys and order

Asset commands acquire only the owners they need, sorted lexicographically by
`(lock_class, company_id, key…)`, and the classes extend the production order in
[doc 40 §5.1](40-tranche-b-coverage-closure-and-our-production-spec.md#51-canonical-state-machine-and-lock-order):

1. period/company policy;
2. commercial source lines (purchase line, sales invoice line, service invoice line);
3. asset policy/plan revision publish keys;
4. **asset owner** `(company, asset)` — and, for book-scoped work, `(company, asset, finance_book)`;
5. quality owner (only where an asset acquisition is quality-gated);
6. stock streams `(item, warehouse, owner, custodian, tracked scope)` for consumed inventory;
7. account balance owners.

No command may acquire an earlier class after a later one. A stock-stream lock never substitutes for the
asset owner lock, and an asset lock never substitutes for the source line lock that bounds allocation.

### 5.2 Idempotency and durable work

Every externally callable asset command has `(company_id, command_kind, idempotency_key) UNIQUE` in the
existing `command_receipt` table (§10 of the schema) and stores request hash, actor, result IDs and terminal
error. The depreciation run additionally derives a **per-period** key `(asset, finance_book, period_start)`,
so the unit of idempotency is the period, not the run.

Recognition, depreciation posting, maintenance occurrence generation and projection rebuilds are durable
rows with `queued/running/retryable/failed/completed/cancelled` state, lease owner/expiry and attempts.
Selection predicates are **self-healing**: `effective_on <= as_of` for recognition, `period_end <= as_of` for
depreciation, `due_date <= as_of` for maintenance. A missed run is caught by the next one, which is the
direct fix for `= nowdate()` (`assets/doctype/asset/asset.py:1085-1103`).

Asset facts, their `voucher`/`gl_entry` rows and their outbox events commit in one transaction.
Projectors advance `projection_checkpoint` monotonically and may write only
`asset_state_projection`, `asset_custody_projection`, `asset_book_value_projection` and register/dashboard
tables. A projector cannot create an acquisition, recognition, posting, revaluation, transformation or
disposal.

---

## 6. Exact command/write ordering

The normative sequences are fixed in [`FINAL-SCHEMA.md` §22](../design/FINAL-SCHEMA.md). Summarised, with
the upstream behaviour each ordering replaces:

| Command | Ordering | Replaces |
|---|---|---|
| **Acquisition** | idempotency → guards → lock source line/stock streams/consumed assets → validate residuals → insert identity + acquisition → allocations + cost events → consumed `stock_move` + valuation → voucher/GL → event/outbox → commit → project | amount-matched linkage and an unlocked quantity ceiling |
| **Recognition** | idempotency → lock asset → verify `asset_cip_residual` → recognition + balanced voucher → event/outbox → commit → project | GL-probe decision, `booked_fixed_asset` flag, single-day job filter |
| **Depreciation run** | per due period: idempotency `(asset, book, period_start)` → lock asset/book → re-evaluate period control for that posting date → posting + voucher → attempt outcome → outbox → commit | index-window slice that bypasses the due-date guard, status-gated selection, session-role frozen-period filtering |
| **Replanning** | idempotency → lock asset/book → insert triggering fact + voucher → generate plan `N+1` → supersede `N` → outbox → commit → project | cancel-active-then-submit-copy, with posted journals copied into the successor |
| **Custody** | idempotency → lock asset → validate chain continuity and dates → custody event → outbox → commit → project | recompute-and-`db_set` of two scalars |
| **Service** | idempotency → lock asset + each cost source → validate residual and apportionment → service event + allocations → stock issue → cost events → voucher/GL → life extension + new policy revision → plan `N+1` → outbox → commit | saving a submitted asset with validation suppressed, full cost to every book |
| **Transformation** | idempotency → lock source asset → compute exact apportionment → transformation + parts → open targets → close/reduce source → plan per target and book → outbox → commit | document copy, float scaling, amended posted journals |
| **Disposal** | idempotency → lock asset → require no unreversed disposal → post final partial period → disposal → voucher from four fact sums → close active plan → outbox → commit → project | four callers, subtraction-derived legs, no uniqueness |

**Exact reversal order**, strictly: disposal → transformation targets before source → capitalised service
cost before its inventory issue → depreciation postings (with `reversal_dating` recorded) → recognition →
acquisition. Each step appends a compensating fact under its own idempotency key. Nothing is updated,
deleted, unlinked or amended — which specifically rules out clearing `journal_entry` on a submitted schedule
row with `update_modified=False` (`assets/doctype/asset/depreciation.py:570-578`) and reading a reversal
amount from a journal's first account line
(`assets/doctype/asset/depreciation.py:579-585`).

A disposal reversal that would leave a transformation, service allocation or posting stranded is **refused**,
not silently partial — the gap where cancelling a Sales Invoice leaves the split asset it created behind
(`accounts/doctype/sales_invoice/services/fixed_assets.py:62-73`, S11 §9).

---

## 7. Evidence versus projection

| Authoritative append-only facts | Rebuildable projections/read models |
|---|---|
| purchase/receipt lines and their CWIP or fixed-asset GL rows | acquisition summary, supplier asset reports |
| `asset_acquisition`, `asset_source_allocation`, `asset_cost_event` | gross cost, addition history, cost by kind |
| `asset_recognition` and its voucher | recognised-versus-in-progress split, `asset_cip_residual` |
| `asset_capitalisation` + typed children, consumed `stock_move` | composite build cost, consumed-inventory reports |
| approved `asset_policy_revision`, `asset_shift_factor_revision` | current method/life/rate/shift display |
| `depreciation_plan` versions and their periods | forecast depreciation, remaining life, plan diff |
| `depreciation_posting`, `depreciation_posting_attempt` | accumulated depreciation, run health, failure dashboards |
| `asset_revaluation` and its voucher | revaluation reserve, impairment history |
| `asset_custody_event` | current location and custodian, custody chain report |
| `maintenance_occurrence` and its events | due/overdue lists, compliance and uptime reporting |
| `asset_service_event`, cost allocations, book apportionment | repair spend per asset, downtime analytics |
| `asset_transformation` + parts | split/merge lineage |
| `asset_disposal` and its voucher | gain/loss reporting, fixed-asset register movement |
| `asset_lifecycle_event` | `asset_state_projection`, activity timeline (text rendered on read) |

A projection can lag or be rebuilt; it cannot authorise, recognise, depreciate, value or post. Projection
drift raises an operational alert and a replay, never a mutation of facts.

Upstream, by contrast, has **no** representation in the left column that is not also mutable: `Asset` itself
carries cost, book value, status and disposal date; the depreciation plan carries the posting link; and
custody, life and cost are all incremented in place (doc 41 §7, doc 42 §10, doc 43 §7).

---

## 8. Adopt / Change / Reject matrix

| Upstream mechanism | Decision | Target |
|---|---|---|
| Asset as a distinct submittable object per unit | **Adopt** | immutable identity created by an authorised acquisition |
| `asset_quantity > 1` on one asset row | **Change** | one asset per unit, or explicit composite members |
| Purchase-row link by amount/quantity matching | **Reject** | `asset_source_allocation` to the exact line |
| Quantity ceiling against the purchase document | **Adopt rule** | same bound under a source-line lock with a residual constraint |
| Four asset types switching validation | **Change** | one asset with typed acquisition kind and component role |
| Opening values silently zeroed for non-existing assets | **Reject** | explicit opening state on the policy revision |
| CWIP → fixed-asset recognition | **Adopt** | explicit `asset_recognition` event with its own voucher |
| `validate_make_gl_entry` GL probes | **Reject** | recognition derived from recorded cost events |
| `booked_fixed_asset` flag | **Reject** | unique unreversed recognition row |
| Daily job filtered `= nowdate()`, CWIP categories only | **Change** | self-healing `<=` selection, category-independent |
| Asset Capitalization consuming stock/assets/services | **Adopt** | one command with typed children and exact allocations |
| Consumed stock valued zero when no rate | **Change** | missing valuation is an error or an authorised policy |
| Target amount rewrite by `db_set` | **Reject** | append cost events; cost is a projection |
| Composite component excluded from the target debit | **Adopt rule** | typed component role prevents double capitalisation |
| Asset submit creating and submitting an Asset Movement | **Change** | custody is its own idempotent command |
| Category account map per company | **Adopt** | same shape with unique keys and typed account-role constraints |
| Company default account fallback | **Adopt** | ordered resolution recorded on the posted event |
| Finance-book rows copied from the category | **Change** | asset names an approved `asset_policy_revision` |
| Mutable per-book counters and `value_after_depreciation` | **Reject** | projections over facts |
| Derived rate rounded to 2 decimals | **Change** | full-precision rate inside the revision |
| A persisted, inspectable schedule per asset and book | **Adopt** | immutable `depreciation_plan` versions |
| Schedule as a submittable document with its own `status` | **Change** | plan state only; no second state machine |
| One schedule per asset/book enforced by probe | **Reject** | partial unique index on active plans |
| `finance_book_id` as a row index | **Reject** | stable finance-book FK |
| `journal_entry` on the plan row | **Reject** | `depreciation_posting` keyed by `depreciation_period` |
| Copying posted rows into successor plan versions | **Reject** | postings are facts; plans never own them |
| Cancel-active-then-submit-copy replanning | **Reject** | append plan version, supersede predecessor |
| Straight line, fixed periods | **Adopt** | same formula at full precision |
| Straight line daily prorata (both settings) | **Adopt as named policies** | explicit `day_basis` on the revision, one convention |
| WDV / double declining with per-fiscal-year base | **Adopt** | same, with one fiscal-year detector |
| Mismatched day conventions between numerator and denominator | **Reject** | one convention, stated and tested |
| `365/12` fractional-month conversion when replanning | **Reject** | exact remaining-period count |
| First/final-period proration | **Adopt** | explicit partial-period basis per period |
| Salvage-value landing adjustment | **Adopt intent** | named residual period, not amount mutation |
| Truncating the plan on a zero amount | **Reject** | explicit zero-with-reason period |
| `skip_row` spinning to the end of the loop | **Reject** | terminate deterministically |
| Shift-factor-weighted depreciation | **Adopt** | factor revisions and per-period shift codes |
| Inverting the factor map by value | **Reject** | shift identity is the code |
| Shift changes by list surgery | **Change** | new plan version from an explicit shift plan |
| Unknown shift name meaning factor 0 | **Reject** | unresolved shift code is a refusal |
| Daily automatic posting job | **Adopt** | due-period selection with per-period idempotency |
| Posting gated by an `Accounts Settings` checkbox | **Change** | posting is required; cadence is configurable |
| Selection gated by mutable asset status | **Reject** | plan state and posted state only |
| Index-window slice bypassing the due check | **Reject** | exact period set |
| Frozen-period filtering by the running session's roles | **Reject** | period control per posting date, audited override |
| `depr_entry_posting_status` scalar | **Reject** | per-period attempt outcomes |
| Per-asset commit inside the run | **Adopt** | per-period transaction with durable failure records |
| Email on posting failure | **Adopt** | notification driven by failure facts |
| `@allow_regional` replacement of the WDV calculation | **Reject** | typed jurisdiction policy revisions |
| Revaluation against the fixed-asset account | **Change** | separate reserve/impairment accounts, independently reconciled |
| Revaluation adjusting salvage proportionally | **Adopt as policy** | explicit `adjust_salvage` flag |
| Zero-difference adjustment raising `UnboundLocalError` | **Reject** | check constraint |
| Movement as a dated document with purposes | **Adopt** | typed `asset_custody_event` |
| Recomputing custody from the latest movement | **Adopt intent** | projector over the unreversed chain |
| `Asset.location` / `custodian` scalars | **Reject** | projection table only |
| Blank target silently leaving a stale dimension | **Reject** | explicit unchanged-versus-cleared semantics |
| Maintenance plan with recurring tasks | **Adopt** | plan and task revisions |
| `calculate_next_due_date` end-condition bug | **Reject** | date-only termination |
| Log ⇄ plan mutual saves | **Reject** | one-way occurrence events |
| Daily bulk `UPDATE` to `Overdue` | **Reject** | overdue is a view |
| Repair capturing downtime, actions and evidence | **Adopt** | `asset_service_event` |
| Repair cost residual checked against GL | **Adopt and strengthen** | same bound under a source lock |
| Duplicate `(invoice, account)` detection | **Adopt** | unique constraint |
| Expense account restricted to non-stock PI items | **Adopt** | typed source validation |
| Adding repair cost / life extension to every book | **Reject** | per-book apportionment and policy revisions |
| Saving a submitted asset with validation suppressed | **Reject** | append cost events |
| Cancel not reversing the stock issue | **Reject** | reverse every fact or refuse |
| Draft repair mutating asset status | **Reject** | state is projected |
| Splitting by document copy and float scaling | **Reject** | `asset_transformation` with exact apportionment |
| Amending posted depreciation journals on split | **Reject** | apportionment recorded; journals immutable |
| Auto-splitting on partial sale | **Change** | explicit transformation command |
| One shared disposal GL derivation | **Adopt** | one disposal projection over facts |
| Accumulated depreciation derived by subtraction | **Reject** | read from its own ledger |
| `disposal_date` written before validation | **Reject** | validate, then insert |
| Status derived from `journal_entry_for_scrap` | **Reject** | projected from the disposal event |
| Sale through Sales Invoice with disposal legs | **Adopt** | disposal event referencing the invoice line |
| Four callers writing `disposal_date`/status | **Reject** | one disposal service, one unreversed disposal |
| Restore/return reversing disposal-date depreciation | **Adopt intent** | compensating facts with explicit dating policy |
| Nested-set Locations with patched ancestor areas | **Reject** | `parent_id` + recursive CTE, area as a projection |
| `Asset Activity` translated sentences | **Change** | typed `asset_lifecycle_event`, text rendered on read |
| Append-only stock/GL accounting core | **Adopt and strengthen** | asset facts reuse `voucher`/`gl_entry` with per-account equality checks |

---

## 9. Pinned upstream defects and unfinished paths

These remain explicit acceptance tests. Docs 41 §9, 42 §12 and 43 §9 carry the full inventories — 17, 32 and
32 items respectively. The ten that most shape the design:

1. **Identity by amount matching.** Item code is never compared and the multi-quantity branch falls back to
   quantity-only matching (`assets/doctype/asset/asset.py:314-325`); the UI helper proposes
   `valuation_rate × qty` while the document matches `base_net_amount`/`base_net_rate`
   (`assets/doctype/asset/asset.py:1190-1212`).
2. **Unlocked quantity ceiling, bypassed by split.** Read-then-write per document
   (`assets/doctype/asset/asset.py:521-562`), skipped entirely for split assets
   (`assets/doctype/asset/asset.py:499-520`, `assets/doctype/asset/mapper.py:218-230`).
3. **Recognition by GL archaeology, and permanently missable.** Four `exists` probes
   (`assets/doctype/asset/asset.py:859-898`) plus a daily job filtered on exact-date equality
   (`assets/doctype/asset/asset.py:1085-1103`).
4. **Plan and posting share one mutable child table.** Replanning cancels a schedule while keeping its
   journals and copies them into the successor
   (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:193-219`,
   `assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:106-122`).
5. **The posting job's slice disables its own guard.** Supplying both index bounds skips the
   unposted/due check (`assets/doctype/asset/depreciation.py:220-254`,
   `assets/doctype/asset/depreciation.py:81-112`), and frozen-period filtering depends on the running
   session's roles (`assets/doctype/asset/depreciation.py:113-127`).
6. **Zero truncates a plan; `skip_row` spins.** Both in the generation loop
   (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:54-98`); an unresolved
   shift name silently yields factor 0
   (`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:47-74`).
7. **A saved draft repair suspends depreciation.** `validate` sets the asset `Out of Order`
   (`assets/doctype/asset_repair/asset_repair.py:177-187`), and status gates posting selection
   (`assets/doctype/asset/depreciation.py:81-112`).
8. **Cost and life added in full to every finance book.**
   (`assets/doctype/asset_repair/asset_repair.py:242-254`,
   `assets/doctype/asset_repair/asset_repair.py:322-329`); repair cancellation does not reverse the stock
   issue (`assets/doctype/asset_repair/asset_repair.py:221-234`).
9. **Split scales by float ratio and amends posted journals.**
   (`assets/doctype/asset/mapper.py:232-250`, `assets/doctype/asset/mapper.py:272-288`), and a cancelled
   sale does not undo the split it caused
   (`accounts/doctype/sales_invoice/services/fixed_assets.py:62-73`).
10. **Disposal is derived by subtraction, has four writers and no uniqueness.**
    (`assets/doctype/asset/depreciation.py:696-716`,
    `accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`,
    `assets/doctype/asset/depreciation.py:639-695`) — the direct cause of S11's stranded balances.

Also pinned as **dead or unreachable**: `make_draft_asset_depr_schedule` calls
`create_depreciation_schedule(asset_doc, row)` against a
`(fb_row=None, disposal_date=None)` signature and is called by nothing
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:163-171`);
`is_first_day_of_the_month` is defined and unused
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:323-326`); and
`flags.wdv_it_act_applied` is consulted but never set in this repository
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:318-341`).

---

## 10. Build sequence and boundary

No application implementation has started. Assets extend the build order in
[doc 40 §10](40-tranche-b-coverage-closure-and-our-production-spec.md#10-build-sequence-and-boundary); they
depend on steps 1–2 there (foundation, accounting/stock core) and on nothing in production.

1. **Asset foundation:** categories and account maps with typed role constraints, asset identity,
   `asset_lifecycle_event`, `asset_location` revisions, projections and checkpoints.
2. **Acquisition and recognition:** source allocation with residual triggers, cost events,
   `asset_recognition`, the construction-in-progress residual view and its continuous reconciliation.
3. **Capitalisation:** typed consumption children, consumed-inventory valuation, consumed-asset disposal
   linkage, exact total constraint.
4. **Policy and plans:** `asset_policy_revision` with approved-range exclusion, the pure plan generator,
   plan/period constraints, shift factor revisions.
5. **Posting:** `depreciation_period`, `depreciation_posting` with per-period uniqueness, attempts, the
   self-healing due-period runner, period-control evaluation per posting date.
6. **Revaluation and impairment:** separate reserve/impairment accounts and the per-account GL equality
   checks; replanning from a new book value.
7. **Custody and maintenance:** custody events with chain continuity, plan/task revisions, occurrence
   generation and the overdue view.
8. **Service:** service events, source-bounded cost allocation, per-book apportionment, life extension as a
   policy revision, full reversal including inventory.
9. **Transformation and disposal:** transformation parts with per-book conservation, single-disposal
   uniqueness, fact-derived disposal vouchers, closing the active plan.
10. **Acceptance:** reproduce S11 exactly, assert **zero** residual on the fixed-asset,
    accumulated-depreciation and revaluation-reserve accounts after both disposals, then run duplicate
    retry, interleaving, reversal, RLS and projection-rebuild tests for every A invariant.

### 10.1 What this closes, and what it does not

**Closed:** Accounts, Stock, Selling, Buying, Subcontracting, Manufacturing, Quality Management and Assets —
203 parents, 178 cited, zero submittable and zero configuration gaps, 25 recorded exclusions. Registers
`L/S/D/P`, `F/T/R/V/U`, `M1–M69` and `A1–A26` are complete, and S01–S11 are the acceptance fixtures.

**Not closed:** localisation. See §11.

---

## 11. Next: localisation, India GST first

Localisation is now a **confirmed requirement, with India GST as the priority**, which makes the
regional-overlay question urgent rather than theoretical. Doc 21 §4 established that ERPNext injects
country behaviour through `@erpnext.allow_regional`, resolving the override from company country at call
time — and doc 42 §4.3 found that mechanism sitting directly on the declining-balance depreciation
calculation (`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:76-86`). A tax regime that
can silently replace a valuation method is not an overlay we can adopt.

The next tranche must specify, against the existing `doc_tax` / `doc_tax_line_alloc` / `voucher` /
`gl_entry` boundary:

- **jurisdiction as data**: a jurisdiction/regime dimension with approved, effective-dated rule revisions,
  replacing runtime function replacement entirely;
- **classification**: HSN/SAC on items and lines, with effective-dated rate schedules;
- **place of supply** resolution from party, address and transaction type, recorded on the posted document
  rather than recomputed;
- **component splitting**: CGST/SGST/IGST/UTGST/cess as typed tax components with exact allocation to
  lines, reusing the error-diffusion rule already fixed in the schema so components sum exactly;
- **reverse charge**, self-invoicing and ineligible/blocked input credit as typed flags with their own GL
  treatment;
- **TDS/TCS** interaction with the withholding design in doc 28;
- **document numbering and statutory series** constraints, including per-jurisdiction uniqueness;
- **statutory extracts** (GSTR-1/3B-shaped returns, e-invoice and e-way-bill payloads) as projections over
  posted facts, never as separate books; and
- **amendment and credit-note semantics** under statutory rules, mapped onto our append-only reversal model.

Assets interact with GST at acquisition (input credit eligibility and capitalisation of ineligible tax) and
at disposal (outward supply of a capital good), so those two seams must be specified in the localisation
tranche rather than retrofitted here.

---

Cross-references: [FINAL-SCHEMA.md §19–§24](../design/FINAL-SCHEMA.md),
[doc 41](41-asset-identity-acquisition-and-finance-books.md),
[doc 42](42-depreciation-engine-schedules-shifts-and-adjustments.md),
[doc 43](43-asset-custody-maintenance-repair-and-disposal.md),
[S11](../scenarios/S11-asset-lifecycle.md),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (command/lock/idempotency/outbox
contract), [doc 25](25-our-platform-spec.md) (layering rule),
[doc 28](28-tax-determination.md) and [doc 21](21-extensibility-hooks-and-regional.md) (the regional
mechanism we reject), [INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md) and
[COVERAGE.md](../COVERAGE.md).
