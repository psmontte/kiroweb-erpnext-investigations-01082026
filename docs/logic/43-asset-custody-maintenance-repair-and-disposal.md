# 43 — Asset Custody, Maintenance, Repair, Split and Disposal

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev)
> and `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe
> citations are prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

[Doc 41](41-asset-identity-acquisition-and-finance-books.md) covered identity and acquisition;
[doc 42](42-depreciation-engine-schedules-shifts-and-adjustments.md) covered the depreciation engine.
This document covers everything that happens to an asset **between** capitalisation and removal from the
books: where it physically is, who holds it, how it is maintained and repaired, how one asset becomes two,
and how it finally leaves — scrapped, sold, or consumed into another asset.

Five properties define this half of the subsystem:

1. **Custody is a scalar recomputed from movement history.** `Asset.location` and `Asset.custodian` are
   `db.set_value` writes derived from the latest submitted `Asset Movement`
   (`assets/doctype/asset_movement/asset_movement.py:128-160`).
2. **Maintenance is a planner that writes logs, and logs write back to the planner.** `Asset Maintenance`
   creates and updates `Asset Maintenance Log` rows, and a submitted log saves the parent's task row and
   then the parent itself (`assets/doctype/asset_maintenance/asset_maintenance.py:55-72`,
   `assets/doctype/asset_maintenance_log/asset_maintenance_log.py:62-78`).
3. **Repair capitalises cost by saving a submitted asset.** `AssetRepair.update_asset_value` mutates
   `total_asset_cost`, `additional_asset_cost` and every finance book's `value_after_depreciation`, then
   saves the asset with `ignore_validate_update_after_submit`
   (`assets/doctype/asset_repair/asset_repair.py:242-254`).
4. **Splitting an asset copies the document and scales every amount.** Quantities, costs, opening
   depreciation and schedules are multiplied by a scaling factor, and posted depreciation journals are
   *edited* to reference the new asset (`assets/doctype/asset/mapper.py:218-249`,
   `assets/doctype/asset/mapper.py:272-288`).
5. **Sale is a Sales Invoice side effect.** Disposal GL, status, disposal date and depreciation-to-date
   are produced by a Sales Invoice service, and the same service reverses them on return or cancellation
   (`accounts/doctype/sales_invoice/services/fixed_assets.py:62-130`).

Invariants continue from doc 42 at **A19**.

---

## 1. The five remaining parents

| DocType | Submittable | Controller | Role |
|---|:--:|---|---|
| Asset Movement | yes | `AssetMovement(Document)` (`assets/doctype/asset_movement/asset_movement.py:13-32`) | custody/location transfer |
| Asset Repair | yes | `AssetRepair(AccountsController)` (`assets/doctype/asset_repair/asset_repair.py:22-59`) | repair cost, consumed stock, capitalisation, life extension |
| Asset Maintenance | no | `AssetMaintenance(Document)` (`assets/doctype/asset_maintenance/asset_maintenance.py:14-35`) | recurring task plan per asset |
| Asset Maintenance Log | yes | `AssetMaintenanceLog(Document)` (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:14-43`) | one occurrence of a task |
| Asset Maintenance Team | no | `AssetMaintenanceTeam(Document)` (`assets/doctype/asset_maintenance_team/asset_maintenance_team.py:8-28`) | team and manager, no behaviour |

Their children — `Asset Movement Item`, `Asset Maintenance Task`, `Asset Repair Consumed Item`,
`Asset Repair Purchase Invoice`, `Maintenance Team Member` — are all bare `Document` subclasses
(`assets/doctype/asset_movement_item/asset_movement_item.py:9-30`,
`assets/doctype/asset_maintenance_task/asset_maintenance_task.py:8-36`,
`assets/doctype/asset_repair_consumed_item/asset_repair_consumed_item.py:8-29`,
`assets/doctype/asset_repair_purchase_invoice/asset_repair_purchase_invoice.py:8-25`,
`assets/doctype/maintenance_team_member/maintenance_team_member.py:8-25`). With this document, all 14
Assets parents are cited.

---

## 2. Asset Movement: custody as a recomputed scalar

### 2.1 Purposes and validation

`purpose` is `Issue`, `Receipt`, `Transfer` or `Transfer and Issue`
(`assets/doctype/asset_movement/asset_movement.py:13-32`). `validate` loops the child rows and applies
asset, movement and date checks (`assets/doctype/asset_movement/asset_movement.py:33-38`):

- **asset**: `Transfer` is refused for `Draft`, `Scrapped` and `Sold` assets, and the asset's company must
  equal the movement's company (`assets/doctype/asset_movement/asset_movement.py:39-46`);
- **dispatch**: `Transfer and Issue` validates both location and employee, `Receipt`/`Transfer` validate
  location, and everything else validates employee
  (`assets/doctype/asset_movement/asset_movement.py:47-54`);
- **date**: the movement's `transaction_date` may not precede the latest submitted movement's date for the
  same asset (`assets/doctype/asset_movement/asset_movement.py:55-66`).

Location validation, for transfers, compares the asset's current `location` to `source_location` — or
**fills `source_location` in from the asset** when blank — then requires a target different from the
source. For receipts it requires a target location and checks the receiving employee's company
(`assets/doctype/asset_movement/asset_movement.py:71-94`). Employee validation requires
`from_employee` for `Transfer and Issue`, requires `from_employee` to match the asset's current
`custodian` when given, requires `to_employee`, and checks its company
(`assets/doctype/asset_movement/asset_movement.py:95-115`).

Note the asymmetry: `Issue` does not require a location and `Receipt` does not require an employee, but
`validate_movement` routes any purpose other than the three named ones — including a blank purpose — to
`validate_employee`, which then demands `to_employee`.

### 2.2 Submit and cancel do the same thing

Both `on_submit` and `on_cancel` call `set_latest_location_and_custodian_in_asset`
(`assets/doctype/asset_movement/asset_movement.py:116-127`), which for each asset re-queries the latest
submitted movement row ordered by `transaction_date` then `name` descending, and writes the result onto
the asset (`assets/doctype/asset_movement/asset_movement.py:128-152`):

```text
current_location, current_employee = target_location, to_employee   of the latest submitted movement
if employee differs from asset.custodian : db.set_value(custodian)
if location and location differs         : db.set_value(location)
```

(`assets/doctype/asset_movement/asset_movement.py:153-160`). Then a translated activity row is added,
with three different phrasings depending on which of location/employee is set
(`assets/doctype/asset_movement/asset_movement.py:161-179`).

Four consequences follow from that implementation:

1. **Recompute-from-latest is the right idea, executed on a mutable scalar.** Cancelling any movement
   correctly re-derives custody from what remains — but the derivation writes two fields with
   `db.set_value`, so nothing prevents another process from writing them directly (doc 41 §2.1 shows
   `Asset` itself creating a `Receipt` movement on submit).
2. **A blank `target_location` never clears the location**, because the write is guarded by `if location`.
   An `Issue` with no target therefore leaves the previous location in place while changing custodian.
3. **Ordering is by `transaction_date` then `name`.** Names are series-based (doc 20 §1), so for two
   movements with the same timestamp the tie-break is lexicographic on the series counter, not on
   creation order after a series reset.
4. **The date monotonicity check is per asset but the recompute is per company.** `validate_transaction_date`
   filters only on asset and `docstatus = 1`
   (`assets/doctype/asset_movement/asset_movement.py:55-66`) while the latest-movement query adds
   `company = self.company` (`assets/doctype/asset_movement/asset_movement.py:128-152`).

There is no lock across "read latest movement → write asset fields", so two movements submitted
concurrently can both compute a latest row and write in either order.

> **Invariant A19 — custody and place are event-sourced.** Every custody or location change is an
> immutable, dated, authorised event naming the asset, source and target place, source and target
> custodian, and the reason. Current place and custodian are projections over the unreversed event chain;
> no document writes them directly, and a movement that does not specify a dimension leaves that
> dimension's projection explicitly unchanged rather than accidentally stale.

---

## 3. Maintenance: a planner and its logs, mutually writing

### 3.1 Plan validation

`AssetMaintenance.validate` walks the task rows, rejecting `start_date >= end_date`, marking a task
`Overdue` when its next due date has passed, and refusing a draft whose task has no assignee
(`assets/doctype/asset_maintenance/asset_maintenance.py:36-44`).

`on_update` assigns each task via Frappe's ToDo assignment and then synchronises logs
(`assets/doctype/asset_maintenance/asset_maintenance.py:45-49`). `assign_tasks` looks up the member's
`User.email`, and inserts a ToDo only when no open ToDo exists for that reference and owner
(`assets/doctype/asset_maintenance/asset_maintenance.py:73-96`).

`sync_maintenance_tasks` upserts one log per task and then marks every log whose task is no longer in the
table as `Cancelled` via `db_set` (`assets/doctype/asset_maintenance/asset_maintenance.py:55-72`).

`update_maintenance_log` finds an existing `Planned`/`Overdue` log for the task; if absent it inserts one,
otherwise it copies the task's fields onto it and saves
(`assets/doctype/asset_maintenance/asset_maintenance.py:134-174`). The inserted log sets
`asset_name = asset_maintenance` — the **maintenance document's name**, not the asset's
(`assets/doctype/asset_maintenance/asset_maintenance.py:134-174`), while `get_maintenance_log` queries
logs by `asset_name` expecting an asset (`assets/doctype/asset_maintenance/asset_maintenance.py:192-198`).
`periodicity` is stored as `str(task.periodicity)`, a text copy of a select value.

`after_delete` resets the asset's status when it was `In Maintenance`
(`assets/doctype/asset_maintenance/asset_maintenance.py:50-54`).

### 3.2 Due-date arithmetic

`calculate_next_due_date` defaults the start to now when neither start nor last completion is given,
prefers the last completion date when it is later, and adds a fixed offset per periodicity — daily,
weekly, monthly, quarterly, half-yearly, yearly, two-yearly, three-yearly
(`assets/doctype/asset_maintenance/asset_maintenance.py:97-133`).

Its terminal condition is the notable part:

```text
if end_date and ((start_date and start_date >= end_date)
                 or (last_completion_date and last_completion_date >= end_date)
                 or next_due_date):
    next_due_date = ""
```

Because the freshly computed `next_due_date` is itself part of the `or`, **any** task with an `end_date`
returns an empty next due date, regardless of whether the schedule has actually ended. Note also that the
function takes `next_due_date` as a parameter and falls through with it unchanged when the periodicity
matches none of the listed values.

### 3.3 Logs

`AssetMaintenanceLog.validate` marks the log `Overdue` when its due date has passed and it is not already
`Completed`/`Cancelled`, requires a completion date for `Completed`, and forbids a completion date
otherwise (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:44-56`).

`on_submit` refuses anything but `Completed`/`Cancelled` and then writes back to the plan
(`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:57-61`).
`update_maintenance_task` loads the `Asset Maintenance Task` **child document directly**, and on
completion recomputes its next due date from the log's periodicity string, sets
`last_completion_date`, sets the task back to `Planned` and saves the child; on cancellation it sets the
task `Cancelled`; then it loads and saves the parent `Asset Maintenance`
(`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:62-78`).

Saving a child document independently of its parent, and then saving the parent — which re-runs
`sync_maintenance_tasks` and can insert or update logs — is a write cycle between two documents. A
completed log therefore triggers plan validation, which can reclassify other tasks as `Overdue`, which
updates their logs.

`update_asset_maintenance_log_status` is a daily job that bulk-updates `Planned` logs whose due date has
passed to `Overdue` with a single `UPDATE`
(`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:80-91`); it is registered in the daily
hook list (`hooks.py:496-527`). This is the one place in the subsystem that does a set-based update
instead of a document loop — and it bypasses document validation entirely.

Maintenance also drives asset status indirectly: the daily maintenance scan sets `In Maintenance` when an
`Asset Maintenance Task` is due today (doc 41 §2.4, `assets/doctype/asset/asset.py:1070-1082`), and doc 42
§5.1 showed that status excludes the asset from depreciation posting that day.

> **Invariant A20 — maintenance plans and occurrences are separate, non-cyclic records.** A plan revision
> defines tasks and recurrence; each occurrence is a dated fact with due date, outcome, actor and
> evidence. Occurrence completion appends the next occurrence deterministically from the recurrence rule;
> it never saves the plan, and the plan never rewrites occurrence outcomes. Recurrence end conditions are
> evaluated on dates only.

---

## 4. Asset Repair: cost, consumption and capitalisation

### 4.1 Validation

`AssetRepair.validate` loads the asset lazily, then validates asset, dates, purchase invoices, status,
consumed-item cost, repair cost, total and repair status
(`assets/doctype/asset_repair/asset_repair.py:60-70`).

`validate_asset` refuses `Sold`/`Scrapped` assets and — when the asset's computed status is
`Fully Depreciated` — **silently zeroes** `capitalize_repair_cost` and `increase_in_asset_life`
(`assets/doctype/asset_repair/asset_repair.py:71-81`). `validate_dates` refuses a completion date before
the failure date (`assets/doctype/asset_repair/asset_repair.py:82-87`).

Purchase-invoice validation is the most carefully built part of the Assets module
(`assets/doctype/asset_repair/asset_repair.py:88-95`):

1. duplicates are detected on `(purchase_invoice, expense_account)` pairs
   (`assets/doctype/asset_repair/asset_repair.py:96-116`);
2. every referenced invoice must be submitted
   (`assets/doctype/asset_repair/asset_repair.py:117-142`);
3. the expense account must be one of the invoice's **non-stock, non-fixed-asset** item expense accounts
   (`assets/doctype/asset_repair/asset_repair.py:143-157`,
   `assets/doctype/asset_repair/asset_repair.py:417-458`); and
4. the row's `repair_cost` may not exceed the unallocated amount for that invoice and account
   (`assets/doctype/asset_repair/asset_repair.py:158-176`).

`get_unallocated_repair_cost` computes `total − already allocated`, where the total is the **net GL
movement** on that account for that invoice and the allocated amount is the sum over submitted
`Asset Repair Purchase Invoice` rows excluding this document
(`assets/doctype/asset_repair/asset_repair.py:459-514`):

```text
total_amount = Σ gl_entry.debit − Σ gl_entry.credit
               where voucher_type = 'Purchase Invoice' and voucher_no = PI
                 and account = expense_account and is_cancelled = 0
used_amount  = Σ Asset Repair Purchase Invoice.repair_cost  (docstatus = 1, other parents)
available    = total_amount − used_amount
```

This is a genuine residual allocation check against the ledger — the only one in the Assets module. It is
still read-then-write with no lock on the invoice, so two repairs can each allocate the same residual.

`update_status`, called from `validate`, sets the **asset** to `Out of Order` with `db.set_value` while the
repair is `Pending`, otherwise recomputes asset status
(`assets/doctype/asset_repair/asset_repair.py:177-187`). A validation method mutating another document is
what makes a merely-saved draft repair suppress that asset's depreciation (doc 42 §5.1).

Costs are simple sums (`assets/doctype/asset_repair/asset_repair.py:188-200`):

```text
consumed_items_cost = Σ valuation_rate × consumed_quantity
repair_cost         = Σ invoice row repair_cost
total_repair_cost   = repair_cost + consumed_items_cost
```

`check_repair_status` refuses submission while the status is still `Pending`
(`assets/doctype/asset_repair/asset_repair.py:238-241`).

### 4.2 Submit

`on_submit` issues the consumed stock, and **only when `capitalize_repair_cost` is set** updates the asset
value, extends life, re-plans depreciation, logs activity and posts GL
(`assets/doctype/asset_repair/asset_repair.py:201-213`).

`decrease_stock_quantity` builds one `Stock Entry` of type `Material Issue` tagged with `asset_repair`,
copies cost centre, project and every accounting dimension onto each row, and submits it
(`assets/doctype/asset_repair/asset_repair.py:258-294`). Serial-bearing items require a bundle, and the
bundle is repointed to `type_of_transaction = "Outward"` and `voucher_type = "Stock Entry"` by direct
`db.set_value` (`assets/doctype/asset_repair/asset_repair.py:295-311`).

`update_asset_value` applies the signed total — negated on cancellation — to `total_asset_cost` and
`additional_asset_cost`, adds it to **every** finance book's `value_after_depreciation`, and saves the
submitted asset with `flags.ignore_validate_update_after_submit`
(`assets/doctype/asset_repair/asset_repair.py:242-254`). `set_increase_in_asset_life` adds (or subtracts)
the configured months to every book's `increase_in_asset_life` with `db_update`
(`assets/doctype/asset_repair/asset_repair.py:322-329`), and doc 42 §3.2 showed how that lengthens the
generated schedule.

Both loops apply to **all** finance books with no per-book apportionment, so a two-book asset receives the
full repair cost twice over in its two book values.

### 4.3 GL

`AssetRepairGLComposer.compose` resolves the fixed-asset account and builds two groups
(`assets/doctype/asset_repair/services/gl_composer.py:20-29`).

Repair cost: credit each invoice row's expense account, then one debit to the fixed-asset account for the
whole `repair_cost`, carrying `against_voucher_type = "Asset"` and `against_voucher = asset`, all dated on
`completion_date` (`assets/doctype/asset_repair/services/gl_composer.py:30-75`).

Consumed items: locate the Stock Entry by its `asset_repair` tag, read its detail rows, and for each
positive amount credit the row's expense account (or the company default when perpetual inventory is off)
and debit the fixed-asset account, with `against_voucher_type = "Stock Entry"`
(`assets/doctype/asset_repair/services/gl_composer.py:76-130`).

Worked repair: 3,000.00 of service on a submitted Purchase Invoice, plus 2 spare parts valued 250.00 each,
capitalised.

Stock Entry (`Material Issue`) posts the ordinary stock legs:

| Account | Debit | Credit |
|---|---:|---:|
| Expenses Included in Asset Valuation (or item expense account) | 500.00 | |
| Stores Inventory | | 500.00 |

Asset Repair then posts:

| Account | Debit | Credit |
|---|---:|---:|
| Fixed Asset — Machinery | **3,000.00** | |
| Repairs Expense (from the PI) | | **3,000.00** |
| Fixed Asset — Machinery | **500.00** | |
| Expenses Included in Asset Valuation | | **500.00** |
| **Total** | **3,500.00** | **3,500.00** |

Net effect: 3,500.00 moves from expense accounts into the fixed asset, the inventory reduction stands, and
the asset's book value rises by 3,500.00. The journal balances because each credit is paired with an equal
debit by construction.

`make_gl_entries` only posts when `total_repair_cost > 0`
(`assets/doctype/asset_repair/asset_repair.py:312-321`), and the composer's repair-cost block also
returns early at zero (`assets/doctype/asset_repair/services/gl_composer.py:30-38`).

### 4.4 Cancel and delete

`on_cancel` — again only when `capitalize_repair_cost` is set — declares GL and SLE as ignored links,
re-loads the asset, reverses the value change, posts reversing GL, reverses the life extension, re-plans
depreciation and logs activity; then it cancels serial/batch bundles
(`assets/doctype/asset_repair/asset_repair.py:221-234`). `cancel_sabb` clears each row's
`serial_and_batch_bundle` with `db_set` before cancelling the bundle
(`assets/doctype/asset_repair/asset_repair.py:214-220`).

Two gaps are visible. First, the **Stock Entry is not cancelled** — the consumed parts stay issued while
the capitalised value is reversed, so cost that left inventory now sits nowhere. Second, a repair with
`capitalize_repair_cost` unset issues stock on submit and does nothing at all on cancel, so that Stock
Entry is orphaned by design. `after_delete` merely recomputes asset status
(`assets/doctype/asset_repair/asset_repair.py:235-237`).

> **Invariant A21 — repair and improvement are allocated cost facts.** A repair records downtime, actions
> and evidence; any capitalised portion is an `asset_cost_event` allocated from an exact source (invoice
> line residual or issued inventory lot) and, for multi-book assets, apportioned per book by policy. Life
> extension is a policy-revision change, not an increment on a mutable counter. Reversal reverses every
> fact it created — stock issue included — or refuses.

---

## 5. Splitting an asset

`split_asset` loads the asset, validates the split quantity, computes the remainder, creates the new
asset and updates the existing one (`assets/doctype/asset/mapper.py:189-206`). `split_qty` must be
strictly less than the asset's quantity (`assets/doctype/asset/mapper.py:203-206`).

`process_asset_split` computes `scaling_factor = split_qty / asset_quantity`, copies the document for the
new asset, sets `flags.is_split_asset`, scales values, logs activity and updates finance books
(`assets/doctype/asset/mapper.py:218-230`).

`set_split_asset_values` scales `net_purchase_amount`, `purchase_amount`, `additional_asset_cost`,
`opening_accumulated_depreciation`, `value_after_depreciation`, and each book's `value_after_depreciation`
and `expected_value_after_useful_life`; sets `asset_quantity`; sets `split_from` on the new asset; and for
the existing asset sets `ignore_validate_update_after_submit` before saving
(`assets/doctype/asset/mapper.py:232-250`). `total_asset_cost` is recomputed as
`net_purchase_amount + additional_asset_cost`.

Worked split of 10 units at 120,000.00 total, 40,000.02 accumulated depreciation, into 3 and 7:

```text
new asset  : factor 0.3 → cost 36,000.00 ; value_after_depreciation × 0.3 ; qty 3 ; split_from set
existing   : factor 0.7 → cost 84,000.00 ; value_after_depreciation × 0.7 ; qty 7
```

Note what is **not** scaled: there is no accumulated-depreciation field on `Asset`.
`set_split_asset_values` scales `opening_accumulated_depreciation` — zero for an ordinary purchased asset —
and `value_after_depreciation` (`assets/doctype/asset/mapper.py:232-250`). For an asset whose 40,000.02 came
from posted depreciation, accumulated depreciation is split **only** through the journal rewrite below, never
through a stored quantity.

Because `flags.is_split_asset` short-circuits `validate_linked_purchase_documents`
(`assets/doctype/asset/asset.py:499-520`), the split children skip the purchase-document quantity ceiling
that doc 41 §3.1 relies on — which is necessary, since neither child matches the original purchase line
any more, and which is also why that ceiling cannot be trusted as a conservation rule.

`log_asset_activity` inserts, submits and re-derives status for the new asset, and logs on the existing one
(`assets/doctype/asset/mapper.py:252-271`).

`update_finance_books` re-plans each book, and for the new asset walks the active schedule and, for every
row with a posted journal, calls `add_reference_in_jv_on_split`
(`assets/doctype/asset/mapper.py:272-288`). That function does more than amend: it saves the journal with
`ignore_validate_update_after_submit`, then sets `docstatus = 2`, calls `make_gl_entries(1)` to cancel the
posted GL rows, sets `docstatus` back to `1` and re-posts them
(`assets/doctype/asset/mapper.py:345-360`). **Submitted GL is cancelled and re-created in place** — the
sharpest violation of the append-only contract anywhere in the Assets module.

It does conserve the total, and that matters for our design: `adjust_account_balance` reduces the source
asset's leg by exactly the amount `add_new_entries` adds for the target
(`assets/doctype/asset/mapper.py:362-390`), so accumulated depreciation in GL stays correct **and becomes
attributable per asset**. Any replacement must reproduce that attribution, not merely the apportionment
record (§8.4).

`reschedule_depr_for_updated_asset` copies the active schedule, points the copy at the target asset and
finance-book row, re-fetches details, scales the depreciation terms, adds notes, cancels the old schedule
with `should_not_cancel_depreciation_entries` for the existing asset, and submits the copy
(`assets/doctype/asset/mapper.py:290-311`, `assets/doctype/asset/mapper.py:313-319`). This is the same
cancel-and-copy mechanism doc 42 §6 rejected, now applied to two assets at once.

> **Invariant A22 — splitting is an authorised transformation, not an edit.** Splitting or merging assets
> is one event that closes the source identity's active state and opens target identities, with explicit
> apportionment of cost, accumulated depreciation, revaluation and remaining life per book. Posted
> depreciation facts are never amended; the split records how prior accumulated depreciation is
> attributed, and every derived value is recomputed from facts.

---

## 6. Disposal

There are three ways an asset leaves the books, and they share one GL builder.

### 6.1 The shared disposal legs

`get_gl_entries_on_asset_disposal` credits the fixed-asset account for `net_purchase_amount`, debits
accumulated depreciation when non-zero, and posts the gain or loss
(`assets/doctype/asset/depreciation.py:639-695`):

```text
accumulated_depr_amount = net_purchase_amount − value_after_depreciation(finance_book)
profit_amount           = selling_amount − value_after_depreciation
```

(`assets/doctype/asset/depreciation.py:696-716`). `get_profit_gl_entries` credits the disposal account for
a gain and debits it for a loss (`assets/doctype/asset/depreciation.py:763-784`), resolving the account and
cost centre from company defaults (`assets/doctype/asset/depreciation.py:785-798`).

`get_gl_entries_on_asset_regain` is the mirror used for returns: debit the fixed asset, credit accumulated
depreciation, and compute profit from **absolute** values
(`assets/doctype/asset/depreciation.py:586-638`).

Doc 42 §8 already noted the consequence of deriving accumulated depreciation by subtraction: any
revaluation booked against the fixed-asset account is silently reclassified as accumulated depreciation at
disposal.

### 6.2 Scrap

`scrap_asset` writes `disposal_date` first, then validates, then depreciates to the scrap date, then
builds the journal (`assets/doctype/asset/depreciation.py:367-379`, doc 42 §9).
`create_journal_entry_for_scrap` posts a `voucher_type = "Asset Disposal"` journal using the company's
depreciation series, appends the disposal legs with `reference_type`/`reference_name` pointing at the
asset, submits unless a workflow exists, and logs activity
(`assets/doctype/asset/depreciation.py:431-456`).

`restore_asset` reverses the disposal-date depreciation, resets the schedule, cancels the scrap journal,
recomputes status and logs activity (`assets/doctype/asset/depreciation.py:457-472`).
`cancel_journal_entry_for_scrap` clears `disposal_date` and `journal_entry_for_scrap` before cancelling
(`assets/doctype/asset/depreciation.py:473-480`). Status becomes `Scrapped` purely because
`journal_entry_for_scrap` is set (doc 41 §2.4) — and nothing in `create_journal_entry_for_scrap` writes
that field, so the link is established by the Journal Entry's own asset handling.

### 6.3 Sale through a Sales Invoice

`FixedAssetService.validate_fixed_asset` requires an `asset` on every fixed-asset row, requires
`return_against` on returns, forbids `update_stock` on a fixed-asset sale, and refuses assets that are
`Scrapped`/`Cancelled`/`Capitalized`/`Sold`
(`accounts/doctype/sales_invoice/services/fixed_assets.py:23-57`).

`split_asset_based_on_sale_qty` compares sale quantity to asset quantity per asset and splits off the
remainder when only part of a multi-quantity asset is sold
(`accounts/doctype/sales_invoice/services/fixed_assets.py:74-87`,
`accounts/doctype/sales_invoice/services/fixed_assets.py:131-159`). So selling 3 of 10 units triggers §5's
split of the other 7.

`process_asset_depreciation` skips internal transfers and then chooses direction by
`(is_return, docstatus)` (`accounts/doctype/sales_invoice/services/fixed_assets.py:62-73`):

```text
(is_return and docstatus == 2) or (not is_return and docstatus == 1) → depreciate to disposal date
otherwise                                                            → restore
```

`get_disposal_date` uses the original invoice's posting date for a return and the invoice's own date
otherwise (`accounts/doctype/sales_invoice/services/fixed_assets.py:88-93`).
`_depreciate_asset_on_sale` depreciates each depreciating, not-fully-depreciated asset to that date
(`accounts/doctype/sales_invoice/services/fixed_assets.py:94-101`); `_restore_asset` reverses the
disposal-date entry and resets the schedule
(`accounts/doctype/sales_invoice/services/fixed_assets.py:102-109`).

`_update_asset` then sets `disposal_date` and status per direction, using `db.set_value` and
`asset.set_status(asset_status)` (`accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`).
Note that it reassigns its own `disposal_date` local inside the loop, so once one row clears the date,
subsequent rows in the same invoice write `None` too.

The GL comes from the Sales Invoice composer: for a return it uses the regain legs, otherwise the
disposal legs, with `against` set to the customer
(`accounts/doctype/sales_invoice/services/gl_composer.py:407-431`).

Worked sale of the machine for 90,000.00 (cost 120,000.00, accumulated 40,000.02, book 79,999.98):

| Account | Debit | Credit |
|---|---:|---:|
| Accumulated Depreciation | **40,000.02** | |
| Fixed Asset — Machinery | | **120,000.00** |
| Gain on Asset Disposal | | **10,000.02** |
| **subtotal (asset legs)** | **40,000.02** | **130,000.02** |
| Debtors (from the ordinary invoice legs) | 90,000.00 | |
| **Total** | **130,000.02** | **130,000.02** |

The asset legs alone do not balance — they are completed by the receivable and income legs of the same
invoice. That is why fixed-asset rows must use an asset-disposal income account rather than ordinary
revenue (`accounts/doctype/sales_invoice/services/fixed_assets.py:58-61`).

### 6.4 Consumption into another asset

The third exit is `Asset Capitalization` consuming the asset (doc 41 §4.3): the same disposal legs are
generated, `disposal_date` is written, and status becomes `Capitalized`
(`assets/doctype/asset_capitalization/services/gl_composer.py:82-116`).

So four different callers — scrap, sale, capitalisation, and their reversals — each drive disposal through
`depreciate_asset` plus `get_gl_entries_on_asset_disposal`, and each sets `disposal_date` and status with
its own `db.set_value`.

> **Invariant A23 — disposal is one event with one exit reason.** Scrap, sale, transfer out and
> consumption are typed disposal events sharing one derivation: cost removed, accumulated depreciation
> removed, revaluation reserve released, proceeds recognised, gain or loss computed from facts. Each has
> a unique identity, exactly one unreversed disposal per asset, and its own reversal event. Status,
> disposal date and register entries are projections of that event.

---

## 7. Evidence versus projection

| Representation | Classification |
|---|---|
| submitted `Asset Movement` + items | custody command evidence |
| `Asset.location`, `Asset.custodian` | recomputed mutable scalars |
| `Asset Maintenance` task rows | editable plan |
| `Asset Maintenance Task.next_due_date`, `last_completion_date`, `maintenance_status` | mutable counters written by logs |
| submitted `Asset Maintenance Log` | occurrence evidence |
| `Asset Maintenance Log.maintenance_status` | mutable, also bulk-updated by a daily `UPDATE` |
| ToDo assignments | side-effect records |
| `Asset Repair` + invoice/consumed rows | repair command evidence |
| `Asset Repair Purchase Invoice.repair_cost` | ledger-checked allocation, unlocked |
| repair `Stock Entry` and its SLE | stock evidence, not reversed on repair cancellation |
| repair GL rows | accounting evidence |
| `Asset.total_asset_cost`, `additional_asset_cost` | mutable scalars written by repair and capitalisation |
| `Asset Finance Book.increase_in_asset_life` | mutable counter that changes future schedules |
| split child assets and `split_from` | new identities created by document copy |
| amended depreciation journals after split | posted evidence edited in place |
| scrap / sale / capitalisation disposal GL | accounting evidence |
| `Asset.disposal_date`, `journal_entry_for_scrap`, status | mutable scalars written by four different callers |
| `Asset Activity` rows | translated human log |

The audit question "what happened to this asset" is answerable only by joining movements, maintenance
logs, repairs, splits, schedules and four kinds of disposal caller — with the asset's own fields being the
least reliable source, because every one of them is a recomputed or incremented scalar.

> **Invariant A24 — evidence before custody and disposal projections.** Custody events, maintenance
> occurrences, repair cost allocations, split transformations and disposal events commit atomically with
> their accounting and stock evidence and an outbox event. Location, custodian, maintenance state, cost,
> life, status and the fixed-asset register are rebuilt from those facts.

---

## 8. Target backend and database model

Extends `docs/design/FINAL-SCHEMA.md`, doc 41 §8 and doc 42 §11. Money `numeric(19,4)`; quantities and
rates `numeric(21,9)`; every table `company_id`-scoped with RLS and `FORCE RLS`; stable enum codes.

### 8.1 Custody

| Target table | Key columns and constraints |
|---|---|
| `asset_custody_event` | asset, `event_kind` (`receipt`/`issue`/`transfer`/`return`/`transfer_out`), `effective_at`, `from_location_id`, `to_location_id`, `from_custodian_id`, `to_custodian_id`, reason, authority, `command_receipt_id`, `reverses_event_id`; unique `(company_id, command_receipt_id)`; check that at least one dimension changes; check `from_* <> to_*` |
| `asset_custody_projection` | current location, custodian, `as_of_event_id`; rebuilt from the unreversed chain |

The projection is derived by a projector keyed on the asset, so "recompute from the latest event" becomes
the only mechanism rather than one of several writers. A transfer's source dimensions are **stored**, not
inferred from the asset's current state, so a chain can be validated end to end.

### 8.2 Maintenance

| Target table | Key columns and constraints |
|---|---|
| `maintenance_plan` / `maintenance_plan_revision` | asset, revision, effective range, team, state; unique `(company_id, asset_id, revision_no)` |
| `maintenance_task_revision` | plan revision, stable `task_key`, description, `recurrence_rule`, certificate requirement, assignee role; unique `(company_id, plan_revision_id, task_key)` |
| `maintenance_occurrence` | task revision, `occurrence_no`, `due_date`, state (`planned`/`overdue`/`completed`/`cancelled`), completion date, actor, evidence; unique `(company_id, task_revision_id, occurrence_no)`; unique `(company_id, task_revision_id, due_date)` |
| `maintenance_occurrence_event` | append-only outcome events per occurrence |

Overdue is a **view** (`due_date < current_date AND state = 'planned'`), not a stored value maintained by a
daily `UPDATE`. Completing an occurrence inserts the next one under a unique key, so retries are
idempotent and the plan is never saved as a side effect.

### 8.3 Repair and improvement

| Target table | Key columns and constraints |
|---|---|
| `asset_service_event` | asset, kind (`repair`/`improvement`/`inspection`), failure/completion timestamps, downtime, actions, state; unique `(company_id, command_receipt_id)` |
| `asset_service_cost_allocation` | service event, source (`purchase_invoice_line`/`stock_issue_move`/`internal_labour`), source id, amount, `is_capitalised`, per-book apportionment ordinal; unique `(company_id, source_type, source_id, asset_service_event_id, ordinal)`; deferred trigger caps Σ allocated at the source residual under a source lock |
| `asset_life_extension` | service event, finance book, months added, resulting policy revision; unique `(company_id, asset_service_event_id, finance_book_id)` |

Capitalised allocations insert `asset_cost_event` rows (doc 41 §8.2) and are apportioned per book by an
explicit policy — never applied in full to every book. Cancelling a service event reverses **all** of its
facts, including the inventory issue, or the reversal is refused.

### 8.4 Split, merge and disposal

| Target table | Key columns and constraints |
|---|---|
| `asset_transformation` | kind (`split`/`merge`), effective date, authority; unique `(company_id, command_receipt_id)` |
| `asset_transformation_part` | transformation, role (`source`/`target`), asset, quantity, apportioned cost, apportioned accumulated depreciation per book, apportioned revaluation; unique `(company_id, asset_transformation_id, role, asset_id)`; deferred trigger requires Σ source = Σ target exactly per measure and book |
| `asset_disposal` | asset, `disposal_kind` (`scrap`/`sale`/`capitalisation`/`transfer_out`), effective date, proceeds, source document line, `voucher_id`, `command_receipt_id`, `reverses_disposal_id`; **at most one unreversed disposal per asset** (deferred trigger under the asset lock); unique `(company_id, command_receipt_id)` |

Apportionment is stored, so no posted depreciation journal is ever amended: the transformation states how
much of the prior accumulated depreciation belongs to each target, and every projection follows from that.

### 8.5 Write ordering

```text
custody
1 claim idempotency ; 2 lock asset ; 3 validate chain continuity and dates ;
4 insert asset_custody_event ; 5 outbox ; 6 commit ; 7 project location/custodian

repair with capitalisation
1 claim idempotency ; 2 lock asset and each cost source (invoice line, stock stream) in sorted order ;
3 validate residuals and per-book apportionment ; 4 insert service event and allocations ;
5 insert stock moves for consumed items ; 6 insert asset_cost_event rows ;
7 insert voucher + gl_entry ; 8 insert life extension and the new policy revision ;
9 generate the next depreciation plan version ; 10 outbox ; 11 commit ; 12 project

split
1 claim idempotency ; 2 lock the source asset ;
3 validate quantity and compute apportionment per measure and book ;
4 insert transformation + parts ; 5 open target asset identities ;
6 close the source identity's active state, or keep it open when it survives as a target part ;
7 generate a plan version per target and book ; 8 outbox ; 9 commit ; 10 project

disposal
1 claim idempotency ; 2 lock the asset ; 3 require no unreversed disposal ;
4 post depreciation for the final partial period as an ordinary period fact ;
5 insert asset_disposal ; 6 insert voucher + gl_entry from cost, accumulated depreciation,
  revaluation reserve and proceeds ; 7 supersede the active plan as closed ;
8 outbox ; 9 commit ; 10 project status and register
```

Reversal in every case appends compensating facts in reverse dependency order — disposal before plan
reopening, capitalised cost before stock issue, transformation targets before the source — and never
clears a link or edits a posted journal.

> **Invariant A25 — relational custody, service and disposal integrity.** Unique, foreign-key, check and
> partial-unique constraints enforce one unreversed disposal per asset, one occurrence per task and due
> date, bounded service-cost allocation, exact split apportionment and continuous custody chains. No rule
> depends on a scalar recomputed by whichever document ran last.

---

## 9. Defects and races

1. **Custody scalars written by many callers.** `Asset Movement` recomputes them, and `Asset` itself
   creates a `Receipt` movement on submit
   (`assets/doctype/asset_movement/asset_movement.py:153-160`, `assets/doctype/asset/asset.py:576-606`).
2. **Blank target location never clears the location.** The write is guarded by `if location`
   (`assets/doctype/asset_movement/asset_movement.py:153-160`).
3. **Latest-movement recompute is unlocked.** Read-then-write per asset
   (`assets/doctype/asset_movement/asset_movement.py:128-160`).
4. **Date check and recompute use different scopes.** Per asset versus per asset and company
   (`assets/doctype/asset_movement/asset_movement.py:55-66`,
   `assets/doctype/asset_movement/asset_movement.py:128-152`).
5. **Blank purpose falls through to employee validation.** The `else` branch
   (`assets/doctype/asset_movement/asset_movement.py:47-54`).
6. **`calculate_next_due_date` returns empty for any task with an end date.** The freshly computed value
   is part of the terminating `or` (`assets/doctype/asset_maintenance/asset_maintenance.py:97-133`).
7. **Unlisted periodicity silently returns the caller's value.** No else branch
   (`assets/doctype/asset_maintenance/asset_maintenance.py:97-133`).
8. **Log `asset_name` is set to the maintenance document's name.** While readers query it as an asset
   (`assets/doctype/asset_maintenance/asset_maintenance.py:134-174`,
   `assets/doctype/asset_maintenance/asset_maintenance.py:192-198`).
9. **Plan and log write to each other.** A submitted log saves the task child and then the parent, whose
   save re-syncs logs (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:62-78`,
   `assets/doctype/asset_maintenance/asset_maintenance.py:55-72`).
10. **Removed tasks cancel logs by `db_set`.** Bypassing log validation
    (`assets/doctype/asset_maintenance/asset_maintenance.py:55-72`).
11. **Daily bulk `UPDATE` sets `Overdue`.** No document validation, no audit
    (`assets/doctype/asset_maintenance_log/asset_maintenance_log.py:80-91`).
12. **Periodicity stored as text.** `str(task.periodicity)`
    (`assets/doctype/asset_maintenance/asset_maintenance.py:134-174`).
13. **A draft repair sets the asset `Out of Order` from `validate`.** Which suppresses depreciation
    (`assets/doctype/asset_repair/asset_repair.py:177-187`, doc 42 §5.1).
14. **`Fully Depreciated` silently disables capitalisation and life extension.** No message
    (`assets/doctype/asset_repair/asset_repair.py:71-81`).
15. **Invoice residual allocation is unlocked.** Read-then-write against the ledger
    (`assets/doctype/asset_repair/asset_repair.py:158-176`,
    `assets/doctype/asset_repair/asset_repair.py:459-514`).
16. **Repair cost added to every finance book, and to GL once.** Each book's `value_after_depreciation`
    rises by the full amount (`assets/doctype/asset_repair/asset_repair.py:242-254`), which is defensible —
    each book measures the same asset — but `total_asset_cost` and `additional_asset_cost` are single fields
    shared by all books while the GL debit happens once, so a two-book asset has no representation of which
    book's depreciable base changed. The defect is the absent per-book depreciable-base record, not the
    uniform amount.
17. **Life extension added in full to every finance book.**
    (`assets/doctype/asset_repair/asset_repair.py:322-329`).
18. **Submitted asset saved with validation suppressed.** `ignore_validate_update_after_submit`
    (`assets/doctype/asset_repair/asset_repair.py:242-254`).
19. **Repair cancellation does not cancel the Stock Entry.** Consumed parts stay issued
    (`assets/doctype/asset_repair/asset_repair.py:221-234`,
    `assets/doctype/asset_repair/asset_repair.py:258-294`).
20. **Non-capitalised repairs do nothing on cancel.** The whole block is conditional
    (`assets/doctype/asset_repair/asset_repair.py:221-234`).
21. **Bundle repointing by direct write.** `type_of_transaction` and `voucher_type` set with
    `db.set_value` (`assets/doctype/asset_repair/asset_repair.py:295-311`).
22. **Split bypasses the purchase-quantity ceiling.** Via `flags.is_split_asset`
    (`assets/doctype/asset/mapper.py:218-230`, `assets/doctype/asset/asset.py:499-520`).
23. **Split cancels and re-posts submitted depreciation journals and their GL rows.**
    (`assets/doctype/asset/mapper.py:345-360`), reached from
    (`assets/doctype/asset/mapper.py:272-288`).
24. **Split scales by float ratio with no residual rule.** Two children need not sum to the parent
    (`assets/doctype/asset/mapper.py:232-250`).
25. **Split re-plans by cancel-and-copy on both assets.**
    (`assets/doctype/asset/mapper.py:290-311`).
26. **`_update_asset` reassigns `disposal_date` inside its loop.** Later rows can write `None`
    (`accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`).
27. **Disposal derives accumulated depreciation by subtraction.** Revaluation is absorbed
    (`assets/doctype/asset/depreciation.py:696-716`, doc 42 §8).
28. **Four callers each write `disposal_date` and status.** Scrap, sale, capitalisation and reversals
    (`assets/doctype/asset/depreciation.py:367-379`,
    `accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`,
    `assets/doctype/asset_capitalization/services/gl_composer.py:82-116`).
29. **`Scrapped` status depends on a link the scrap function never writes.**
    (`assets/doctype/asset/depreciation.py:431-456`, `assets/doctype/asset/asset.py:785-817`).
30. **Regain profit computed from absolute values.** Sign handling differs from disposal
    (`assets/doctype/asset/depreciation.py:586-638`).
31. **No uniqueness on disposal.** Nothing structurally prevents two disposal journals for one asset
    (`assets/doctype/asset/depreciation.py:639-695`).
32. **Maintenance team has no validation at all.** Bare `Document`
    (`assets/doctype/asset_maintenance_team/asset_maintenance_team.py:8-28`).

No deterministic owner lock or unique constraint was found around: latest-movement read → asset write;
task completion → next occurrence insert; invoice residual read → repair allocation insert; split
apportionment → child creation; or disposal check → disposal journal insert.

> **Invariant A26 — serializable custody, service and disposal decisions.** Custody events, occurrence
> creation, service-cost allocation, transformation and disposal are bounded writes validated and
> inserted under deterministic asset (and source) locks with idempotency keys and database uniqueness.
> Concurrent individually valid commands may not create two disposals, duplicate occurrences,
> over-allocated invoice cost, or a broken custody chain.

---

## 10. Adopt / Change / Reject

| ERPNext mechanism | Decision | Ours |
|---|---|---|
| Movement as a dated document with purposes | **Adopt** | typed `asset_custody_event` |
| Recomputing custody from the latest movement | **Adopt intent** | projector over the unreversed event chain |
| `Asset.location` / `custodian` scalars | **Reject** | projection table only |
| Inferring `source_location` from the asset | **Change** | source dimensions stored on the event |
| Guarding the write with `if location` | **Reject** | explicit "unchanged" versus "cleared" semantics |
| Monotonic transaction-date check | **Adopt** | chain continuity constraint per asset |
| Company check on assets and employees | **Adopt** | FK plus company-scoped constraint |
| Maintenance plan with recurring tasks | **Adopt** | `maintenance_plan_revision` + `maintenance_task_revision` |
| Recurrence by fixed offsets | **Adopt** | explicit recurrence rule per task revision |
| `calculate_next_due_date` end-condition bug | **Reject** | date-only termination, unit tested |
| Log ⇄ plan mutual saves | **Reject** | occurrence events; plans are never written by occurrences |
| Cancelling logs by `db_set` when a task is removed | **Reject** | plan revision supersedes; occurrences keep their outcomes |
| Daily bulk `UPDATE` to `Overdue` | **Reject** | overdue is a view |
| ToDo assignment on save | **Change** | assignment is an explicit event with an idempotency key |
| Repair capturing downtime, actions and evidence | **Adopt** | `asset_service_event` |
| Repair cost residual checked against GL | **Adopt and strengthen** | same bound, enforced under a source-line lock |
| Duplicate `(invoice, account)` detection | **Adopt** | unique constraint |
| Expense account restricted to non-stock PI items | **Adopt** | typed source validation |
| Consuming spares via a `Material Issue` Stock Entry | **Adopt** | ordinary stock issue linked as a cost source |
| Adding repair cost to every finance book | **Reject** | per-book apportionment policy |
| Adding life extension to every finance book | **Reject** | explicit policy revision per book |
| Saving a submitted asset with validation suppressed | **Reject** | append `asset_cost_event` |
| Cancel not reversing the stock issue | **Reject** | reverse every fact or refuse |
| Draft repair mutating asset status | **Reject** | state is projected from events |
| Splitting a multi-quantity asset | **Change** | one asset per unit, or an explicit transformation with stored apportionment |
| Float scaling of every amount | **Reject** | exact apportionment with a named residual rule |
| Amending posted depreciation journals on split | **Reject** | apportionment is recorded, journals are immutable |
| Split bypassing purchase-quantity validation | **Change** | conservation is enforced by allocation rows, not by re-validating the purchase |
| One shared disposal GL derivation | **Adopt** | one disposal projection over facts |
| Deriving accumulated depreciation by subtraction | **Reject** | accumulated depreciation and revaluation reserve are separate ledgers |
| Scrap via `Journal Entry` typed `Asset Disposal` | **Adopt intent** | typed `asset_disposal` event with its own voucher |
| `disposal_date` written before validation | **Reject** | validate, then insert |
| Status derived from `journal_entry_for_scrap` | **Reject** | status projected from the disposal event |
| Sale through Sales Invoice with disposal legs | **Adopt** | disposal event referencing the invoice line |
| Auto-splitting on partial sale | **Change** | explicit transformation command, not an implicit side effect |
| Restore/return by reversing the disposal-date depreciation | **Adopt intent** | compensating facts with explicit dating policy |
| Four callers writing `disposal_date`/status | **Reject** | one disposal service, one unreversed disposal per asset |

Invariants introduced here are **A19–A26**. Together with **A1–A18** they form the Tranche C register;
scenario S11 exercises them end to end and the closure document will consolidate them.

---

## 11. Cross-references

[Doc 41](41-asset-identity-acquisition-and-finance-books.md) (identity, acquisition, capitalisation,
locations, activity), [doc 42](42-depreciation-engine-schedules-shifts-and-adjustments.md) (schedules,
posting, revaluation, disposal-date depreciation), [doc 01](01-gl-posting-engine.md) (posting and
reversal), [doc 02](02-stock-ledger-and-valuation.md) and [doc 03](03-stock-gl-bridge.md) (consumed spares
and the stock→GL bridge), [doc 06](06-lifecycle-status-and-returns.md) (returns and status),
[doc 09](09-lifecycle-reversals-deletions.md) (cancel ordering and ignored links),
[doc 20](20-naming-identity-and-audit-trail.md) (identity and audit),
[doc 22](22-background-jobs-scheduling-and-locking.md) (daily jobs and locking),
[doc 27](27-remaining-stock-documents.md) (`Stock Entry` and serial/batch bundles),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (command, lock, idempotency and outbox
contract) and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: scenario **S11**, then the
Tranche C closure document.
