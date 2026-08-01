# 42 — The Depreciation Engine: Schedules, Shifts and Adjustments

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev)
> and `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe
> citations are prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

[Doc 41](41-asset-identity-acquisition-and-finance-books.md) established how an asset comes into
existence and where its cost lands. This document covers the only subsystem in ERPNext where **value
changes because time passed** rather than because a document was submitted: depreciation.

Three things make it structurally different from everything in docs 01–40:

1. **The plan is a submittable document.** `Asset Depreciation Schedule` holds one row per future
   period, each of which later acquires a `journal_entry` link. The plan and the postings therefore
   live in the same mutable child table.
2. **Re-planning is implemented as cancel-and-copy.** Any change — disposal, revaluation, shift
   reallocation — cancels the active schedule *without cancelling its journals* and submits a copy
   (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:193-219`).
3. **Posting is a scheduled job that commits per asset.** `book_depreciation_entries` commits after
   each asset and records failures on the asset itself
   (`assets/doctype/asset/depreciation.py:46-79`).

The findings that matter most:

- the schedule generator is a **stateful loop over instance attributes** set up by
  `initialize_variables`, and several of those attributes (`prev_per_day_depr`,
  `yearly_wdv_depr_amount`) are either unused or only conditionally initialised
  (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:99-112`,
  `assets/doctype/asset_depreciation_schedule/depreciation_methods.py:113-120`);
- **uniqueness of "one schedule per asset per book" is a `db.exists` probe**, not a constraint
  (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:59-86`);
- the daily posting job **skips frozen companies by adding a `WHERE` clause per company**, so a single
  query filters on a role check evaluated in the *scheduler's* session
  (`assets/doctype/asset/depreciation.py:81-127`);
- disposal-date value is computed by **building a temporary copy of the schedule in memory**
  (`assets/doctype/asset/depreciation.py:799-838`,
  `assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:234-244`); and
- restoring an asset **clears `journal_entry` on a submitted child row with
  `update_modified=False`** and adds the amount back to `value_after_depreciation`
  (`assets/doctype/asset/depreciation.py:570-577`).

Invariants continue from doc 41 at **A10**.

---

## 1. The three depreciation parents and one child

| DocType | Submittable | Controller | Role |
|---|:--:|---|---|
| Asset Depreciation Schedule | yes | `AssetDepreciationSchedule(DepreciationScheduleController)` (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:18-52`) | the plan, and the register of what has been posted |
| Asset Shift Allocation | yes | `AssetShiftAllocation(Document)` (`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:23-40`) | reallocates shift codes across schedule rows |
| Asset Value Adjustment | yes | `AssetValueAdjustment(Document)` (`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:21-43`) | revalues the asset and re-plans the remainder |
| Asset Shift Factor | no | `AssetShiftFactor(Document)` (`assets/doctype/asset_shift_factor/asset_shift_factor.py:9-22`) | shift name → numeric factor, with one default |
| Depreciation Schedule | child | `DepreciationSchedule(Document)` (`assets/doctype/depreciation_schedule/depreciation_schedule.py:8-27`) | `schedule_date`, `depreciation_amount`, `accumulated_depreciation_amount`, `journal_entry`, `shift` |

The child has no behaviour; it is the join point between plan and posting, which is exactly the design
problem this document keeps returning to.

`Asset Shift Factor` enforces at most one default by probing for an existing default and refusing
(`assets/doctype/asset_shift_factor/asset_shift_factor.py:26-35`) — a check-then-write with no unique
index, so two concurrent saves can both become default.

---

## 2. Schedule identity, lifecycle and the uniqueness probe

### 2.1 Validate

`AssetDepreciationSchedule.validate` does three things
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:53-58`):

1. reject a second live schedule for the same asset and book;
2. **generate the schedule** when `finance_book_id` is not set; and
3. regenerate it when shift-based and still a draft.

The uniqueness rule matches on asset, finance book (`is not set` when blank) and `docstatus < 2`
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:59-86`). Because the probe
runs in the document's own validation, two concurrent inserts for one asset/book can both see nothing
and both succeed. Every reader then resolves "the" schedule with
`frappe.get_all(..., limit=1)` and takes the first row
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:298-322`) — so which
schedule is authoritative becomes an ordering accident.

`update_shift_depr_schedule` regenerates the whole schedule on every save of a shift-based **draft**
that is not brand new (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:123-127`).

### 2.2 Submit and cancel

`on_submit` verifies that the asset calculates depreciation and is submitted, then `db_set`s
`status = "Active"` (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:87-105`).
So `status` is a second state machine running alongside `docstatus`.

`on_cancel` sets `status = "Cancelled"` and — unless the caller set
`flags.should_not_cancel_depreciation_entries` — cancels every linked `Journal Entry`, refusing when one
of them is still a draft (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:106-122`).

That flag is the pivot of the whole re-planning design: `reschedule_depreciation` and
`AssetShiftAllocation` both set it so that the *old* schedule can be cancelled while its posted
depreciation journals survive and are carried into the copy
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:193-219`,
`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:189-225`).

### 2.3 Field snapshot

`fetch_asset_details` copies the asset and finance-book policy onto the schedule: opening values, net
purchase amount, method, count, frequency, rate, `value_after_depreciation`, salvage value, daily-prorata
and shift flags, and `status = "Draft"`
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:143-161`). `finance_book_id`
is the finance-book row's `idx` — a positional identifier, not a stable key, so reordering the asset's
finance-book table silently re-points every schedule.

`get_finance_book_row` resolves the row either from the caller or by querying `Asset Finance Book` for
this asset and book (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:128-142`).

> **Invariant A10 — the plan is not the posting.** A depreciation plan is an immutable, versioned
> projection of an approved policy revision over an asset's remaining book value. Posted depreciation is
> a separate append-only fact referencing the plan period it satisfies. Replanning supersedes plan
> versions; it never edits, re-links or silently inherits posted facts.

---

## 3. Generating a schedule

`create_depreciation_schedule` is five steps: record the disposal date, load the asset, resolve the
finance-book row, snapshot details, `clear()`, `create()`, then compute accumulated depreciation
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:28-37`).

### 3.1 `clear` keeps posted rows

`clear` walks existing rows and keeps them **only up to the first row without a `journal_entry`**; that
index becomes `first_non_depreciated_row_idx`, and the untouched original list is retained as
`schedules_before_clearing` for shift lookups
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:38-53`).

The loop breaks at the first unposted row, so posted rows *after* a gap are discarded. Since
`first_non_depreciated_row_idx` is assigned `num_of_depreciations_completed` at the break, a schedule
whose second row posted but whose first did not keeps zero rows and restarts from index 0 — while its
posted journal survives, now unlinked from any plan row.

### 3.2 Setup

`initialize_variables` seeds pending value from the finance-book row's `value_after_depreciation`, notes
whether the start date is a month end, and computes pending months, final count, non-yearly proration and
pending days/years (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:99-112`).

`get_final_number_of_depreciations` starts from
`total_number_of_depreciations − opening_number_of_booked_depreciations`, adds **one extra period** when
proration applies, and may add more for `increase_in_asset_life`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:113-143`):

```text
final_schedule_date = available_for_use_date
                      + total_number_of_depreciations × frequency + increase_in_asset_life  (months)
schedule_date       = depreciation_start_date + pending_depreciations × frequency
if final_schedule_date > schedule_date:
    final_number_of_depreciations += month_diff // frequency + 1
```

`_check_is_pro_rata` decides whether the first period is partial
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:151-187`). For Straight
Line and Manual it measures from `available_for_use_date` to the notional previous start date; for the
declining methods it measures from a modified start date. `days <= 0` raises an error whose message
interpolates the same value twice
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:167-187`); `days <
total_days` sets `has_pro_rata`.

`get_total_days` derives the period length by stepping back one frequency from a date, snapping to month
end when the date is a month end, and returning `date_diff` **without** the `+1` used elsewhere
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:205-210`). Proration
amounts, however, are computed with `days = date_diff + 1`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:211-216`), so numerator
and denominator use different day conventions.

### 3.3 The generation loop

```text
for row_idx in first_non_depreciated_row_idx .. final_number_of_depreciations-1:
    if skip_row: continue
    detect fiscal-year change; if changed, yearly_opening_wdv = pending
    remember previous row's amount
    schedule_date = depreciation_start_date + row_idx × frequency   (snapped to month end if applicable)
    depreciation_amount = method-specific amount
    if disposal_date and schedule_date >= disposal_date: prorate to disposal and break
    if row_idx == 0: apply first-row proration
    elif has_pro_rata and row_idx == final-1: apply last-row handling
    round to asset precision; if zero, break
    pending -= amount
    adjust for salvage value
    if amount > 0: append row
```

(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:54-98`).

Two loop properties are worth stating plainly. First, `if not self.depreciation_amount: break` means a
single zero-valued period **truncates the rest of the schedule** rather than skipping that period.
Second, the loop `continue`s when `skip_row` is set, so once salvage adjustment fires the loop spins to
completion doing nothing instead of exiting.

`set_accumulated_depreciation` then walks rows, resuming from the stored accumulated amount on posted
rows and accumulating from `opening_accumulated_depreciation` otherwise
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:411-422`).

---

## 4. The four methods, with worked numbers

`get_depreciation_amount` dispatches Straight Line and Manual to the straight-line family and everything
else to the WDV family (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:423-428`).
**Manual is not a separate algorithm**: it is straight line, differing only in that
`has_depreciation_settings_changed` will actually diff a manual schedule instead of regenerating it
(doc 41 §5.3).

### 4.1 Straight line, fixed periods

```text
depreciable_value = value_after_depreciation − expected_value_after_useful_life
pending_periods   = pending_months / frequency_of_depreciation
amount            = depreciable_value / pending_periods
```

(`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:16-32`).

Worked: cost 120,000.00, salvage 20,000.00, 60 monthly periods, available for use and first schedule date
2026-01-31.

```text
depreciable_value = 100,000.00
pending_months    = 60 × 1 = 60
pending_periods   = 60
amount            = 1,666.6666… → 1,666.67 at 2 decimals
```

The final period is where rounding lands. `adjust_depr_amount_for_salvage_value` fires when the loop
reaches `final_number_of_depreciations − 1` and pending value differs from salvage value, or whenever
pending has fallen **below** salvage value; it then adds `pending − salvage` to the current amount and
sets `skip_row`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:364-379`):

```text
after 59 periods: accumulated = 59 × 1,666.67 = 98,333.53 ; pending = 21,666.47
period 60 raw    = 1,666.67
adjustment       = 21,666.47 − 20,000.00 − 1,666.67 = −0.20 relative to raw
final amount     = 1,666.67 + (21,666.47 − 20,000.00) − … → exactly 1,666.47
accumulated      = 100,000.00 ; book value = 20,000.00
```

The mechanism is correct in outcome — the schedule always lands exactly on salvage value — but it is
implemented by mutating the amount that was just computed, and the adjustment is rounded with
`self.precision("value_after_depreciation")` while every other amount uses
`asset_doc.precision("net_purchase_amount")`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:364-379`).

### 4.2 Straight line, daily prorata

```text
if Accounts Settings.calculate_depr_using_total_days:
    daily = depreciable_value / total_pending_days
else:
    daily = (depreciable_value / total_pending_years) / days_in_current_depr_fiscal_year
amount = daily × days_in_this_period
```

(`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:33-46`,
`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:429-440`).

`total_pending_days` subtracts an extra day when a previous depreciation exists and does not when it
does not (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:252-263`):

```text
last_depr_date exists : total_pending_days = date_diff(final_schedule_date, last_depr_date) − 1
otherwise             : total_pending_days = date_diff(final_schedule_date, available_for_use_date)
```

`_get_total_days` computes each period's day count as `date_diff(to_date, from_date) + 1`, snapping to
month boundaries when the start date is a month end
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:429-436`). It is called
with `row_idx`, and computes `from_date` at `(row_idx − 1) × frequency` — so the *first* row asks for a
period that starts one frequency **before** the depreciation start date.

Worked, 365-day year, cost 120,000.00, salvage 0.00, 12 monthly periods, `calculate_depr_using_total_days`
off, fiscal year 2026-04-01 → 2027-03-31:

```text
yearly = 120,000.00 / 1 = 120,000.00
daily  = 120,000.00 / 365 = 328.7671232876712…
April (30 days) = 9,863.01
May   (31 days) = 10,191.78
```

Because `daily` is recomputed per period from the *fiscal year* length, a leap year inside the asset's
life changes the daily rate mid-schedule; the salvage adjustment absorbs the drift in the last period.

### 4.3 Written down value and double declining

```text
if fiscal year changed since previous row:
    yearly = pending_depreciation_amount × rate_of_depreciation / 100
    amount = yearly × frequency_of_depreciation / 12
else:
    amount = previous row's amount
```

(`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:88-106`). `is_fiscal_year_changed`
compares the schedule date's fiscal-year start with `prev_fy_start_date` and updates it as a side
effect (`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:101-106`) — while the
controller has its *own* `has_fiscal_year_changed` maintaining `current_fiscal_year_end_date`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:264-279`). Two
independent fiscal-year detectors run over the same loop.

Rate itself comes from the asset (doc 41 §5.4). Worked: cost 100,000.00, WDV rate 40%, annual frequency:

```text
year 1: 100,000.00 × 40% = 40,000.00 → pending 60,000.00
year 2: 60,000.00 × 40%  = 24,000.00 → pending 36,000.00
year 3: 36,000.00 × 40%  = 14,400.00 → pending 21,600.00
```

With `frequency = 3` (quarterly), each quarter books `yearly × 3/12`, and `is_fiscal_year_changed`
ensures the yearly base is only recomputed once per fiscal year — the mechanism that makes non-annual
declining balance arithmetically consistent.

`get_wdv_or_dd_depr_amount` is decorated `@erpnext.allow_regional`
(`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:76-86`), so a regional app can
replace the entire declining-balance calculation; doc 21 §4 covers why session-derived region selection
is unacceptable for us. `flags.wdv_it_act_applied` is consulted in first-row proration
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:318-341`) but is never
set in this repository — it exists purely for that regional override.

The daily-prorata WDV path reads `self.yearly_wdv_depr_amount`, which is assigned **only inside the
fiscal-year-changed branch** (`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:113-120`).
It is not initialised in `initialize_variables`
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:99-112`), so the
attribute exists on the first call only because the first row always reports a fiscal-year change.

### 4.4 Shift-based straight line

```text
if no prior schedule rows:
    amount = depreciable_value / (pending_months / frequency)
else:
    shift        = shift of this row in schedules_before_clearing (else None)
    shift_factor = factor_map[shift] or 0
    factors_sum  = Σ factor_map[row.shift] over rows without a journal_entry
    amount       = depreciable_value / factors_sum × shift_factor
```

(`assets/doctype/asset_depreciation_schedule/depreciation_methods.py:47-74`). Worked: remaining
depreciable value 90,000.00 over three unposted rows with shifts Single (1), Double (2), Triple (3):

```text
factors_sum = 6
Single: 90,000.00 / 6 × 1 = 15,000.00
Double: 90,000.00 / 6 × 2 = 30,000.00
Triple: 90,000.00 / 6 × 3 = 45,000.00
```

A shift name with no matching `Asset Shift Factor` contributes factor `0`, which produces a zero amount —
and by §3.3 a zero amount **truncates the schedule**. `factors_sum` of zero raises `ZeroDivisionError`.

New rows get the shift from the pre-clear list, or the single default shift factor's name
(`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:393-410`).

> **Invariant A11 — deterministic, complete, exact schedules.** A plan version is a pure function of
> (policy revision, book value, opening state, calendar, shift plan) at full precision, computed with one
> day/period convention. Every period is either an amount or an explicit zero-with-reason; a zero never
> truncates a plan. The sum of planned amounts equals depreciable value exactly, with the residual
> assigned by a named deterministic rule rather than by mutating the last computed amount.

---

## 5. Posting: the daily job

### 5.1 Selection

`post_depreciation_entries` returns immediately unless
`Accounts Settings.book_asset_depreciation_entry_automatically` is set
(`assets/doctype/asset/depreciation.py:37-43`); it is registered in the daily long list
(`hooks.py:496-527`).

`get_depreciable_assets_data` joins `Asset Depreciation Schedule` to `Asset` and to the child rows and
selects `(schedule name, asset name, MIN(idx) − 1, MAX(idx))` for
(`assets/doctype/asset/depreciation.py:81-112`):

- `Asset.calculate_depreciation = 1`, `Asset.docstatus = 1`;
- `Asset.status IN ('Submitted', 'Partially Depreciated')`;
- schedule `docstatus = 1`;
- child `journal_entry IS NULL` and `schedule_date <= date`.

Then, for every company with a frozen-till date whose override role the **current session** lacks, it
appends `(company != X) OR (schedule_date > frozen_upto)`
(`assets/doctype/asset/depreciation.py:113-127`). Two consequences: the set of postable rows depends on
the roles of whoever triggers the run, and the filter is per company rather than per posting date.

`MIN(idx) − 1` and `MAX(idx)` become Python slice bounds, so the job passes an index window rather than
the exact set of due rows. Since `MIN`/`MAX` are taken over the *filtered* rows but the slice is applied
to the *whole* child table, any already-posted or not-yet-due row inside that window is included in the
slice — and `_make_journal_entry_for_depreciation` short-circuits its own due-date check whenever both
slice bounds are supplied (§5.2).

Status is part of the filter, so an asset whose status was set to `Out of Order` or `In Maintenance` by
the daily maintenance scan (doc 41 §2.4) is **silently excluded from depreciation** that day.

### 5.2 Posting one asset

`book_depreciation_entries` loops assets, calls `make_depreciation_entry`, commits per asset, and on
exception rolls back, records the asset name and logs the error
(`assets/doctype/asset/depreciation.py:46-79`). Failures set `depr_entry_posting_status = "Failed"` on
each asset and email a role
(`assets/doctype/asset/depreciation.py:315-336`).

`make_depreciation_entry` resolves accounts, cost centre and series, then for each row in the slice sets
a savepoint, attempts a journal, and on exception rolls back to the savepoint and **remembers only the
last error**; afterwards it reloads the asset, recomputes status, and either marks
`depr_entry_posting_status = "Successful"` or re-raises
(`assets/doctype/asset/depreciation.py:169-218`).

So a run in which rows 1 and 3 fail reports one error, and a run in which every row succeeds writes a
success flag that is a *scalar on the asset* rather than a fact about a period.

`_make_journal_entry_for_depreciation` returns early only when the slice bounds were **not** both
supplied and the row is either already posted or not yet due
(`assets/doctype/asset/depreciation.py:220-254`). When both bounds are supplied — which is exactly what
the scheduler does — that guard is bypassed entirely and the row is posted regardless of its date or
existing journal.

The journal is `voucher_type = "Depreciation Entry"`, posted on `schedule_date`, carrying the schedule's
finance book and a translated remark (`assets/doctype/asset/depreciation.py:255-267`). Both legs
reference the asset, use the depreciation cost centre, and copy accounting dimensions from the asset
according to each dimension's mandatory-for-BS/PL flags
(`assets/doctype/asset/depreciation.py:268-299`).

`get_credit_and_debit_accounts` inspects the depreciation expense account's root type: for `Expense` it
credits accumulated depreciation and debits expense; for `Income` it swaps them; anything else raises
(`assets/doctype/asset/depreciation.py:300-314`).

Worked monthly entry of 1,666.67:

| Account | Debit | Credit |
|---|---:|---:|
| Depreciation Expense | **1,666.67** | |
| Accumulated Depreciation | | **1,666.67** |

The journal balances by construction because both legs use `depr_schedule.depreciation_amount`. Nothing
verifies that the sum of posted amounts for the asset equals the schedule's accumulated column, and
nothing verifies that accumulated depreciation in GL equals `net_purchase_amount − value_after_depreciation`.

The schedule child row's `journal_entry` is set by Journal Entry submission (via its own asset handling),
not by this function — which is why the "already posted" test everywhere in this subsystem is
`if d.journal_entry`.

> **Invariant A12 — depreciation posting is idempotent per period.** Each (asset, book, period) has at
> most one unreversed depreciation fact, enforced by a unique key rather than by a nullable link column.
> Selection is by due date and unposted state only — never by mutable asset status, never by index
> windows, and never dependent on the roles of the session that happens to run the job. Period control
> is evaluated per posting date, and a failed period is a durable, per-period failure record.

---

## 6. Re-planning: cancel, copy, submit

`reschedule_depreciation` is the single entry point for every change to a live schedule
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:193-219`):

```text
for each finance book row:
    if disposal_date and value_after_depreciation <= expected_value_after_useful_life: skip
    current = the live schedule (any status)
    new = copy of current if submitted, current itself if draft, else a brand-new document
    set_modified_depreciation_rate(...)
    new.create_depreciation_schedule(row, disposal_date)
    new.notes = notes
    if current was submitted:
        current.flags.should_not_cancel_depreciation_entries = True
        current.cancel()
    new.submit()
```

`set_modified_depreciation_rate` recomputes the declining-balance rate, `db_set`s it onto the asset's
finance-book row, and copies it to the new schedule
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:221-232`). The old schedule is
cancelled **after** the new one has been built but **before** it is submitted, so the uniqueness probe in
§2.1 sees the old document already at `docstatus = 2`.

`frappe.copy_doc` carries the child rows including `journal_entry`, so posted periods appear in the new
schedule too. The consequence is that one posted depreciation journal is referenced by a chain of
schedules: the original (cancelled), and every successor copy. There is no field saying which schedule
version "owns" the posting.

`get_temp_depr_schedule_doc` builds a **throwaway** copy purely to compute numbers, optionally after
substituting a caller-supplied row set (`asset_depreciation_schedule.py:234-244`,
`asset_depreciation_schedule.py:256-270`). It is used for disposal-date valuation (§8) and shift preview
(§7). `get_current_asset_depr` throws when no active schedule exists
(`asset_depreciation_schedule.py:245-255`).

`make_draft_asset_depr_schedule` is **dead and wrong**: it calls
`create_depreciation_schedule(asset_doc, row)` while the signature is
`create_depreciation_schedule(fb_row=None, disposal_date=None)`
(`asset_depreciation_schedule.py:163-171`,
`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:28-37`). The asset
document would be used as the finance-book row and the row as a disposal date. Nothing in the app calls
it.

`is_first_day_of_the_month` is defined and unused in this module
(`asset_depreciation_schedule.py:323-326`).

---

## 7. Asset Shift Allocation

`AssetShiftAllocation` edits the shift column of a copy of the active schedule and then swaps schedules.

`after_insert` fetches the active schedule's rows into itself, requiring that schedule to be shift-based
and to exist (`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:47-52`,
`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:169-188`). It saves itself with
`flags.ignore_validate = True`.

`validate`, for drafts with rows, refuses to change the shift of any row that already has a
`journal_entry` — comparing **by positional index** against the active schedule
(`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:41-61`). If the active schedule has
fewer rows, that indexing raises.

`adjust_depr_shifts` then conserves the **total shift factor**
(`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:76-130`):

```text
factor_diff = Σ new row factors − Σ original row factors
if factor_diff > 0: drop or downgrade rows from the end until the excess is consumed
if factor_diff < 0: append rows using the largest factor that fits, repeatedly
```

Both directions rely on `reverse_shift_factors_map`, built by inverting the name→factor map
(`asset_shift_allocation.py:76-91`). Two shift factors with the same numeric value therefore collapse:
one name is lost, and a downgrade can rename a row's shift to an arbitrary one of them. If no exact
factor fits the remaining difference, `add_depr_shifts` throws
(`asset_shift_allocation.py:116-130`) — so a factor set of `{1, 2, 3}` cannot represent a difference of
`0.5`, and a set without `1` cannot represent many differences at all.

Appended rows are dated one frequency after the last row, snapped to month end
(`asset_shift_allocation.py:131-146`).

`update_depr_schedule` then generates a temporary schedule from the edited rows and replaces its own rows
with the computed ones (`asset_shift_allocation.py:62-75`, `asset_shift_allocation.py:156-168`), so the
document displays real amounts before submission.

`on_submit` copies the active schedule, replaces its rows with the allocation's rows, writes a translated
note, cancels the old schedule with `should_not_cancel_depreciation_entries`, submits the new one and
appends an activity row (`asset_shift_allocation.py:189-225`).

Worked: 3 unposted periods, remaining depreciable value 90,000.00, original shifts
`Single, Single, Single` (factor sum 3), changed to `Double, Single, Single` (sum 4):

```text
factor_diff = 4 − 3 = 1  → reduce from the end
last row factor 1 <= 1   → row dropped ; factor_diff = 0
remaining rows: Double(2), Single(1) ; factors_sum = 3
Double: 90,000.00 / 3 × 2 = 60,000.00
Single: 90,000.00 / 3 × 1 = 30,000.00
```

Total depreciation is preserved and the asset finishes one period earlier — which is the intended
semantics of shift-based depreciation, implemented by list surgery on a mutable child table.

> **Invariant A13 — shift plans are explicit, conserved and named.** A shift plan is a versioned set of
> (period, shift code, factor revision) rows. Factor codes are unique and never inverted by value.
> Re-allocating shifts produces a new plan version whose total factor-weighted depreciation equals the
> remaining depreciable value exactly, with periods added or removed as explicit plan changes and posted
> periods immutable by identity rather than by list position.

---

## 8. Asset Value Adjustment

`AssetValueAdjustment` revalues an asset and re-plans the remainder.

`validate` rejects a date before the asset's purchase date, defaults `current_asset_value` from the
asset's value after depreciation, and computes
`difference_amount = new_asset_value − current_asset_value`
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:44-65`). Note that the default only
applies when `current_asset_value` is empty
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:62-65`) — a stale value typed by the
user is preserved and becomes the basis of the difference.

`on_submit` posts the revaluation journal, updates the asset and logs activity; `on_cancel` cancels the
journal and updates the asset again
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:66-85`).

`make_asset_revaluation_entry` resolves depreciation accounts and company defaults and builds a
two-line journal (`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:86-130`):

| Direction | Debit | Credit |
|---|---|---|
| increase (`difference_amount > 0`) | fixed asset | difference account |
| decrease (`difference_amount < 0`) | difference account | fixed asset |

(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:131-158`). Worked decrease of
15,000.00 on an asset with book value 80,000.00:

| Account | Debit | Credit |
|---|---:|---:|
| Impairment/Revaluation (difference account) | **15,000.00** | |
| Fixed Asset — Machinery | | **15,000.00** |

Dimensions are copied from the adjustment, not the asset, using the mandatory-for-BS/PL flags
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:159-169`).

A `difference_amount` of exactly zero leaves `credit_entry` and `debit_entry` **unbound**, so
`update_accounting_dimensions` raises `UnboundLocalError`
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:86-130`). The journal is submitted
directly with `ignore_permissions`, then its name is `db_set` onto the adjustment.

`update_asset_value_after_depreciation` applies the signed difference — negated on cancellation — to the
matching finance-book row's `value_after_depreciation`, adjusts
`expected_value_after_useful_life` by `difference × salvage_value_percentage / 100`, and adds the
difference to the asset's own `value_after_depreciation`, all with `db_update`
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:187-209`). `update_asset` then
re-plans via `reschedule_depreciation` and recomputes status
(`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:181-186`).

The revaluation credits the **fixed asset** account, so cost and accumulated depreciation stop
reconciling to `net_purchase_amount − value_after_depreciation`: the asset's `net_purchase_amount` is
untouched while its book value moved. Disposal then computes accumulated depreciation as
`net_purchase_amount − value_after_depreciation`
(`assets/doctype/asset/depreciation.py:696-716`), which now includes the impairment. An impaired asset's
disposal journal therefore debits an accumulated-depreciation figure that GL never accumulated.

`get_value_after_depreciation_on_disposal_date` handles the value-at-a-date question by building a
temporary schedule to the disposal date and returning
`net_purchase_amount − accumulated_depreciation_amount` of its last row
(`assets/doctype/asset/depreciation.py:799-838`). Its finance-book lookup defaults `idx = 1` and then
indexes `finance_books[idx − 1]`, so an unmatched book silently uses the first row.

> **Invariant A14 — revaluation is an explicit, reconciled event.** Impairment and revaluation are typed
> facts with effective date, amount, reason and authority, posted against named revaluation accounts and
> **kept separate from accumulated depreciation**. Cost, accumulated depreciation, revaluation reserve and
> net book value each remain reconcilable to the ledger independently; disposal derives each from its own
> facts rather than from one subtraction.

---

## 9. Disposal-time depreciation and restoration

`depreciate_asset` re-plans to the disposal date, posts the depreciation entries on the (new) active
schedule, reloads and calls the regional hook `cancel_depreciation_entries` — which is a no-op here and
exists for the India Compliance override
(`assets/doctype/asset/depreciation.py:481-500`).

`set_depreciation_amount_for_disposal` prorates from the day after the last posted row (or the modified
available-for-use date) to the disposal date, and if positive appends one row dated on the disposal date
and breaks (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:297-317`).

`scrap_asset` sets `disposal_date` **before** validating, then validates, depreciates and creates the
scrap journal (`assets/doctype/asset/depreciation.py:367-379`). Validation rejects non-submitted assets,
already-disposed statuses, future dates, dates before purchase, and dates before the last posted
depreciation (`assets/doctype/asset/depreciation.py:380-424`). Because `db_set` precedes validation, a
rejected scrap leaves `disposal_date` written unless the request rolls back.

`get_gl_entries_on_asset_disposal` credits the fixed asset for `net_purchase_amount`, debits accumulated
depreciation when non-zero, and posts `selling_amount − value_after_depreciation` to the disposal account
(`assets/doctype/asset/depreciation.py:639-695`, `assets/doctype/asset/depreciation.py:763-784`).
`get_gl_entries_on_asset_regain` is the mirror, with the profit sign computed from absolute values
(`assets/doctype/asset/depreciation.py:586-638`).

Worked scrap of the machine after 24 months (cost 120,000.00, accumulated 40,000.02, book 79,999.98,
no proceeds):

| Account | Debit | Credit |
|---|---:|---:|
| Accumulated Depreciation | **40,000.02** | |
| Loss on Asset Disposal | **79,999.98** | |
| Fixed Asset — Machinery | | **120,000.00** |
| **Total** | **120,000.00** | **120,000.00** |

`restore_asset` reverses the disposal-date depreciation, resets the schedule, cancels the scrap journal,
recomputes status and logs activity (`assets/doctype/asset/depreciation.py:457-472`).

`reverse_depreciation_entry_made_on_disposal` finds the posted row dated on `disposal_date` and reverses
it **unless** the disposal fell exactly on the row's original schedule date and is not in the future
(`assets/doctype/asset/depreciation.py:508-547`). The reversal is a reverse Journal Entry posted on
**today's date** rather than the original date (`assets/doctype/asset/depreciation.py:548-569`), and
`update_value_after_depreciation_on_asset_restore` then clears `journal_entry` on the submitted child row
with `update_modified=False` and adds the amount back to the finance-book row
(`assets/doctype/asset/depreciation.py:570-578`). The amount is read from the reversal journal's **first**
account line, whichever side it happens to be
(`assets/doctype/asset/depreciation.py:579-585`).

Clearing a link on a submitted document while deliberately suppressing the modified timestamp is the
sharpest example of the plan/posting confusion: the journal still exists, the reversal exists, and the
plan row now claims nothing was ever posted.

> **Invariant A15 — disposal-period depreciation and reversal are dated facts.** Depreciation up to a
> disposal date is a normal period fact with an explicit partial-period basis. Reversal is a compensating
> fact dated by policy (original date or reversal date, stated explicitly), linked to the exact fact it
> reverses, and never implemented by unlinking a posted period from its plan.

---

## 10. Evidence versus projection

| Representation | Classification |
|---|---|
| approved policy on `Asset Finance Book` | editable copy, not a revision (doc 41 §5.2) |
| `Asset Depreciation Schedule` header snapshot | policy copy at generation time |
| `Depreciation Schedule` rows without `journal_entry` | plan projection |
| `Depreciation Schedule.journal_entry` | mutable link that doubles as "posted" evidence |
| `Depreciation Schedule.accumulated_depreciation_amount` | recomputed projection, resumed from posted rows |
| submitted depreciation `Journal Entry` + GL rows | the real accounting evidence |
| `Asset Finance Book.value_after_depreciation` | mutable projection written by adjustment, restore and asset save |
| `Asset.depr_entry_posting_status` | mutable per-asset scalar for a per-period outcome |
| `Asset Depreciation Schedule.status` | second state machine beside `docstatus` |
| `Asset Shift Allocation` rows | proposed plan edit, computed via a throwaway copy |
| `Asset Value Adjustment` + its journal | revaluation command and accounting evidence |
| `Asset Value Adjustment.journal_entry` | mutable link written by `db_set` |
| temporary schedule from `get_temp_depr_schedule_doc` | in-memory calculation, never persisted |
| scrap/disposal `Journal Entry` | accounting evidence |
| reverse depreciation `Journal Entry` | accounting evidence, dated today |

The audit path from "why is this asset worth this much" to evidence is:

```text
Asset Finance Book policy (editable)
  → Asset Depreciation Schedule version N (cancelled) … version N+k (active)
  → Depreciation Schedule rows, some carrying journal_entry
  → Depreciation Entry journals + GL
  ± Asset Value Adjustment journals (against the fixed-asset account)
  ± reverse depreciation journals (dated today, sometimes with the plan link cleared)
```

Every schedule version after the first is a copy, and posted rows appear in all of them.

> **Invariant A16 — evidence before depreciation projection.** Plan versions, posted period facts,
> revaluation facts and reversals commit atomically with their accounting evidence and an outbox event.
> Book value per asset and book, accumulated depreciation, remaining life and register reports are
> rebuilt from those facts; replaying the log reproduces the same values exactly.

---

## 11. Target backend and database model

Extends `docs/design/FINAL-SCHEMA.md` and doc 41 §8. Money `numeric(19,4)`; rates and factors
`numeric(21,9)`; percentages `numeric(9,6)`; every table `company_id`-scoped with RLS and `FORCE RLS`;
stable lower-case enum codes.

### 11.1 Plan

| Target table | Key columns and constraints |
|---|---|
| `depreciation_plan` | asset, finance book, `plan_version`, `asset_policy_revision_id`, generated_at, `generator_version`, `input_hash`, `state`, `supersedes_plan_id`; unique `(company_id, asset_id, finance_book_id, plan_version)`; at most one `active` per `(asset, finance_book)` by partial unique index |
| `depreciation_plan_period` | plan, `period_no`, `period_start`, `period_end`, `basis_days`, `shift_code`, `shift_factor_revision_id`, `planned_amount`, `planned_accumulated`; unique `(company_id, depreciation_plan_id, period_no)`; check `period_end >= period_start`; check `planned_amount >= 0` |
| `depreciation_shift_factor` / `_revision` | stable `shift_code`, factor revision with effective range; unique `(company_id, shift_code)`; exactly one default enforced by partial unique index |

Plan periods carry **no** journal link. The plan is immutable once `active`; replanning inserts a new
version and supersedes the old one, and every superseded version remains readable.

### 11.2 Posting and correction

| Target table | Key columns and constraints |
|---|---|
| `depreciation_period` | canonical period identity: asset, finance book, `period_start`, `period_end`; unique `(company_id, asset_id, finance_book_id, period_start)` |
| `depreciation_posting` | period, plan version satisfied, amount, posting date, `voucher_id`, `command_receipt_id`, `reverses_posting_id`; **unique partial index: one unreversed posting per `depreciation_period`**; unique `(company_id, command_receipt_id)` |
| `depreciation_posting_attempt` | period, attempt_no, outcome (`posted`/`failed`/`skipped`), error code, occurred_at; unique `(company_id, depreciation_period_id, attempt_no)` |
| `asset_revaluation` | asset, finance book, effective date, `previous_book_value`, `new_book_value`, difference, revaluation account, reason, authority, `voucher_id`, `reverses_revaluation_id`; unique `(company_id, command_receipt_id)` |
| `asset_disposal_depreciation` | period fact flagged as partial-period-to-disposal with its basis, referencing the disposal event |

`depreciation_period` is what makes idempotency real: the unique key is on the period, not on a nullable
link, so a retried run cannot double-post and a reversal is a new row rather than a cleared field.
`depreciation_posting_attempt` replaces `depr_entry_posting_status` with per-period durable outcomes.

### 11.3 Projections

`asset_book_value_projection(company_id, asset_id, finance_book_id, as_of_date)` carries cost,
accumulated depreciation, accumulated revaluation, net book value, periods posted, periods remaining and
plan version, rebuilt from `asset_cost_event`, `depreciation_posting` and `asset_revaluation` with a
projector checkpoint. Depreciation expense by period, book and dimension is a view over `gl_entry`.

Continuous deferred checks:

1. `Σ depreciation_posting.amount` (unreversed) per asset/book equals accumulated depreciation in GL for
   that asset's accumulated-depreciation account and book;
2. `Σ plan_period.planned_amount` per plan version equals depreciable value at generation exactly;
3. net book value never falls below salvage value for an unreversed plan;
4. no posting exists for a period beyond the plan's final period; and
5. cost, accumulated depreciation and revaluation reserve each reconcile to their own GL accounts —
   revaluation is never merged into accumulated depreciation.

### 11.4 Write ordering

```text
posting run
1  select due periods: plan active, period_end <= as_of, no unreversed posting
2  per period: claim idempotency (asset, book, period_start)
3  lock asset book owner; re-check period control for that posting date
4  insert depreciation_posting + balanced voucher/gl_entry
5  insert attempt outcome + outbox event ; commit
6  on failure: insert failed attempt outcome (separate transaction), continue

replanning (revaluation, shift change, life change, disposal)
1  claim idempotency ; lock asset book owner
2  insert the triggering fact (revaluation / shift plan / disposal) and its voucher
3  generate plan version N+1 from the policy revision and current book value
4  mark version N superseded ; insert version N+1 as active
5  outbox ; commit ; projectors rebuild book value and registers
```

Posted periods are never copied into the new plan: they are separate facts that the new plan simply does
not re-plan. That single change removes the entire cancel-copy-inherit mechanism.

> **Invariant A17 — relational depreciation integrity.** Unique, foreign-key, check and partial-unique
> constraints enforce one active plan per asset and book, one period row per period, one unreversed
> posting per period, non-overlapping plan periods, and factor/policy revision references. No rule
> depends on a nullable link column or on child-row position.

---

## 12. Defects and races

1. **Schedule uniqueness is a probe.** Concurrent inserts can create two live schedules for one
   asset/book (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:59-86`), and
   readers take `limit=1` (`asset_depreciation_schedule.py:298-322`).
2. **`finance_book_id` is a positional index.** Reordering the asset's finance-book table re-points
   schedules (`asset_depreciation_schedule.py:143-161`).
3. **`clear` discards posted rows after a gap.** The loop breaks at the first unposted row
   (`deppreciation_schedule_controller.py:38-53`).
4. **A zero amount truncates the schedule.** `if not depreciation_amount: break`
   (`deppreciation_schedule_controller.py:54-98`).
5. **`skip_row` spins instead of exiting.** The loop `continue`s for every remaining period
   (`deppreciation_schedule_controller.py:54-98`).
6. **Mismatched day conventions.** `get_total_days` omits the `+1` that `_get_pro_rata_amt` applies
   (`deppreciation_schedule_controller.py:205-216`).
7. **`_get_total_days` starts one period early.** It computes `from_date` at `(row_idx − 1) × frequency`
   (`deppreciation_schedule_controller.py:429-436`).
8. **Two fiscal-year detectors.** The controller and the WDV mixin each maintain their own
   (`deppreciation_schedule_controller.py:264-279`,
   `assets/doctype/asset_depreciation_schedule/depreciation_methods.py:101-106`).
9. **`yearly_wdv_depr_amount` is conditionally initialised.** Only set inside the fiscal-year-changed
   branch (`depreciation_methods.py:113-120`), never in `initialize_variables`
   (`deppreciation_schedule_controller.py:99-112`).
10. **Unknown shift name silently means factor 0.** Which, with defect 4, truncates the plan
    (`depreciation_methods.py:47-74`).
11. **Precision inconsistency in salvage adjustment.** Uses `self.precision("value_after_depreciation")`
    while the loop uses the asset's `net_purchase_amount` precision
    (`deppreciation_schedule_controller.py:364-379`).
12. **Duplicated `get_asset_shift_factors_map`.** Defined in the module and on the mixin
    (`asset_depreciation_schedule.py:272-276`, `depreciation_methods.py:72-74`).
13. **Dead, wrong-arity helper.** `make_draft_asset_depr_schedule` passes `(asset_doc, row)` into
    `(fb_row, disposal_date)` (`asset_depreciation_schedule.py:163-171`).
14. **Scheduler slice bypasses the due-date guard.** Supplying both indices disables the
    unposted/due check (`assets/doctype/asset/depreciation.py:220-254`,
    `assets/doctype/asset/depreciation.py:81-112`).
15. **Frozen-period filtering depends on the running session's roles.**
    (`assets/doctype/asset/depreciation.py:113-127`).
16. **Mutable asset status gates depreciation.** `In Maintenance` / `Out of Order` assets are skipped
    (`assets/doctype/asset/depreciation.py:81-112`, doc 41 §2.4).
17. **Only the last per-row error survives.** `depr_posting_error` is overwritten
    (`assets/doctype/asset/depreciation.py:169-218`).
18. **Posting status is a per-asset scalar.** Success or failure for many periods collapses into one
    field (`assets/doctype/asset/depreciation.py:169-218`,
    `assets/doctype/asset/depreciation.py:315-319`).
19. **Posted journals are shared across schedule versions.** `copy_doc` carries `journal_entry`
    (`asset_depreciation_schedule.py:193-219`).
20. **Restore clears a submitted row's link with `update_modified=False`.**
    (`assets/doctype/asset/depreciation.py:570-578`).
21. **Reversal amount read from the first journal line.** Whichever side it is
    (`assets/doctype/asset/depreciation.py:579-585`).
22. **Reversal posted on today's date.** Not on the original period's date
    (`assets/doctype/asset/depreciation.py:548-569`).
23. **Shift factor inversion collapses equal factors.** `{v: k}` over the factor map
    (`assets/doctype/asset_shift_allocation/asset_shift_allocation.py:76-91`).
24. **Shift difference must be exactly representable.** Otherwise it throws
    (`asset_shift_allocation.py:116-130`).
25. **Shift comparison is positional.** Index-aligned against the active schedule
    (`asset_shift_allocation.py:41-61`).
26. **Zero-difference value adjustment raises `UnboundLocalError`.**
    (`assets/doctype/asset_value_adjustment/asset_value_adjustment.py:86-130`).
27. **Stale `current_asset_value` is trusted.** Only defaulted when empty
    (`asset_value_adjustment.py:62-65`).
28. **Revaluation hides inside accumulated depreciation at disposal.** Disposal derives accumulated as
    `net_purchase_amount − value_after_depreciation`
    (`assets/doctype/asset/depreciation.py:696-716`, `asset_value_adjustment.py:187-209`).
29. **Unmatched finance book falls back to the first row.** In disposal-date valuation
    (`assets/doctype/asset/depreciation.py:799-838`).
30. **`disposal_date` written before validation.** `scrap_asset` `db_set`s first
    (`assets/doctype/asset/depreciation.py:367-379`).
31. **Default shift factor is check-then-write.** No unique index
    (`assets/doctype/asset_shift_factor/asset_shift_factor.py:26-35`).
32. **Declining-balance calculation is regionally replaceable.** `@erpnext.allow_regional`
    (`depreciation_methods.py:76-86`), with `flags.wdv_it_act_applied` consulted but never set here
    (`deppreciation_schedule_controller.py:318-341`).

No deterministic owner lock or unique constraint was found around: schedule existence check → insert;
due-row selection → journal insert; `value_after_depreciation` read → adjustment write; active schedule
read → cancel-and-submit swap; or default shift factor read → save.

> **Invariant A18 — serializable depreciation decisions.** Plan generation, plan activation, period
> posting, revaluation and shift reallocation are bounded writes validated and inserted under
> deterministic asset/book locks with idempotency keys and database uniqueness. Concurrent individually
> valid commands may not create two active plans, two postings for one period, or a plan whose total
> exceeds remaining depreciable value.

---

## 13. Adopt / Change / Reject

| ERPNext mechanism | Decision | Ours |
|---|---|---|
| A persisted, inspectable schedule per asset and book | **Adopt** | immutable `depreciation_plan` versions with periods |
| Schedule as a submittable document with its own `status` | **Change** | plan state only; no second state machine |
| One schedule per asset/book enforced by probe | **Reject** | partial unique index on active plans |
| `finance_book_id` as a row index | **Reject** | stable finance-book FK |
| `journal_entry` on the plan row | **Reject** | separate `depreciation_posting` keyed by period |
| Keeping posted rows by copying them into new versions | **Reject** | postings are facts; plans never own them |
| Cancel-active-then-submit-copy replanning | **Reject** | append plan version, supersede predecessor |
| `should_not_cancel_depreciation_entries` flag | **Reject** | unnecessary once plan and posting are separate |
| Straight line, fixed periods | **Adopt** | same formula at full precision |
| Straight line, daily prorata (both settings) | **Adopt as named policies** | explicit day-basis policy in the revision, one convention |
| WDV / double declining with per-fiscal-year base | **Adopt** | same, with one fiscal-year detector |
| Rate stored on an editable child row | **Change** | rate inside the policy revision |
| `@allow_regional` method replacement | **Reject** | typed jurisdiction policy revisions, no session-derived override |
| First-period and final-period proration | **Adopt** | explicit partial-period basis per period |
| Salvage-value landing adjustment | **Adopt intent** | named residual rule, not amount mutation |
| Truncating on a zero amount | **Reject** | explicit zero-with-reason period |
| Shift-factor-weighted depreciation | **Adopt** | factor revisions and per-period shift codes |
| Inverting the factor map by value | **Reject** | shift identity is the code |
| Shift changes by list surgery | **Change** | new plan version from an explicit shift plan |
| Daily automatic posting job | **Adopt** | due-period selection, per-period idempotency, self-healing |
| Selection gated by `Accounts Settings` checkbox | **Change** | posting is required; automation cadence is configurable |
| Selection gated by mutable asset status | **Reject** | only plan state and posted state |
| Index-window slice bypassing the due check | **Reject** | exact period set |
| Frozen-period filtering by session roles | **Reject** | period control per posting date, audited override |
| `depr_entry_posting_status` scalar | **Reject** | per-period attempt outcomes |
| Per-asset commit inside the run | **Adopt** | per-period transaction with durable failure records |
| Email on failure | **Adopt** | notification driven by failure facts |
| Revaluation journal against the fixed-asset account | **Change** | separate revaluation/impairment accounts, reconciled independently |
| Revaluation adjusting salvage value proportionally | **Adopt as policy** | explicit policy flag on the revaluation |
| Disposal-date proration and reversal | **Adopt intent** | dated facts with explicit reversal policy |
| Clearing `journal_entry` on restore | **Reject** | reversal fact, original posting retained |
| Reversal posted on today's date | **Change** | explicit dating policy recorded on the reversal |
| In-memory temporary schedule for valuation | **Change** | pure valuation function over plan + facts, no throwaway documents |
| Dead `make_draft_asset_depr_schedule` | **Reject** | no unreachable API surface |

Invariants introduced here are **A10–A18**. Doc 43 continues at **A19** with custody, maintenance,
repair and disposal.

---

## 14. Cross-references

[Doc 41](41-asset-identity-acquisition-and-finance-books.md) (asset identity, finance books, account
resolution), [doc 01](01-gl-posting-engine.md) (posting, balance, reversal),
[doc 07](07-period-close-and-opening-balances.md) (period control and frozen dates),
[doc 09](09-lifecycle-reversals-deletions.md) (submit/cancel/amend),
[doc 21](21-extensibility-hooks-and-regional.md) (`@allow_regional` and why we reject it),
[doc 22](22-background-jobs-scheduling-and-locking.md) (scheduler, idempotency, locking),
[doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (`Journal Entry` and dimensions),
[doc 31](31-batch-processes-instruments-recurring.md) (`Accounts Settings` flags that change accounting
semantics), [doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (command, lock,
idempotency and outbox contract) and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md).
Next: doc 43 — asset movement, maintenance, repair and disposal.
