# S11 — Asset Lifecycle: Purchase → Capitalisation → Depreciation → Repair → Disposal

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Continues **[S03](S03-procure-to-pay.md)** at the Purchase Receipt, and ends at a **[S01](S01-order-to-cash.md)**
> Sales Invoice — but the item in between is a fixed asset, so neither stock valuation nor ordinary
> revenue recognition applies. The complete subsystem trace is
> **[docs 41–43](../logic/41-asset-identity-acquisition-and-finance-books.md)**.
>
> This is an investigation document. It distinguishes acquisition evidence, recognition, plan versions,
> posted depreciation facts, cost additions and disposal; it does not prescribe an operational workaround.

---

## 1. The worked example and posting assumptions

AlphaCo buys two identical machines on one Purchase Receipt line, capitalises them as one asset of
quantity 2, depreciates monthly, repairs one of them with a capitalised cost, sells one and scraps the
other.

| Fact | Value |
|---|---|
| Item | `MACHINE-A`, fixed asset, non-stock |
| Purchase Receipt | 2 units at 60,000.00 = **120,000.00**, dated 2026-01-15 |
| Asset | one `Asset` with `asset_quantity = 2`, cost 120,000.00 |
| Available for use | 2026-01-31 |
| Depreciation | Straight Line, 60 monthly periods, salvage 20,000.00, one finance book |
| Repair | 3,000.00 of external service, capitalised, on 2026-04-30 |
| Sale | 1 unit for 45,000.00 on 2026-05-31 |
| Scrap | the remaining unit on 2026-06-30 |

Assumptions that make every number deterministic: CWIP accounting is **enabled** for the asset category,
so the receipt debits Capital Work in Progress; perpetual inventory is on but irrelevant (a fixed-asset
item is non-stock); `Accounts Settings.book_asset_depreciation_entry_automatically` is on; there are no
taxes, landed costs, currency differences, shifts or accounting dimensions; the company's
`accounts_frozen_till_date` is unset; and float precision is 2. Accounts used: Capital Work in Progress,
Fixed Asset — Machinery, Accumulated Depreciation, Depreciation Expense, Asset Received But Not Billed,
Repairs Expense, Gain/Loss on Asset Disposal, Debtors.

The scenario deliberately uses `asset_quantity = 2` because that is what forces ERPNext's **split**
machinery (doc 43 §5) and exposes how one identity is retrofitted into two.

---

## 2. Stage 1 — Purchase Receipt

The Purchase Receipt line is a fixed-asset item, so no Stock Ledger Entry is written for it. With CWIP
accounting enabled, the receipt debits Capital Work in Progress:

| Account | Debit | Credit |
|---|---:|---:|
| Capital Work in Progress | **120,000.00** | |
| Asset Received But Not Billed | | **120,000.00** |

| Representation after the receipt | Value |
|---|---|
| `tabPurchase Receipt` + 1 item row | 2 units, 120,000.00 |
| `tabStock Ledger Entry` | **0** — fixed assets are not stock |
| `tabGL Entry` | **2** |
| `tabAsset` | **0** — no asset exists yet |

Nothing in the receipt creates the asset. The asset is a separate document that will later *claim* this
receipt line.

---

## 3. Stage 2 — the Asset document

### 3.1 Creating it, and how the link is resolved

**ASS-0001** is created for `MACHINE-A` with `asset_quantity = 2`, `net_purchase_amount = 120,000.00`,
`purchase_receipt = PR-0001`, `purchase_date = 2026-01-15`, `available_for_use_date = 2026-01-31`.

`set_purchase_doc_row_item` copies `net_purchase_amount` into `purchase_amount` and resolves the receipt
child row (`assets/doctype/asset/asset.py:295-313`). Because `asset_quantity > 1`, `get_linked_item`
matches on `base_net_amount == net_purchase_amount and qty == asset_quantity`, falling back to
quantity-only matching (`assets/doctype/asset/asset.py:314-325`):

```text
asset_quantity = 2 > 1
row 1: base_net_amount 120,000.00 == 120,000.00 and qty 2 == 2  → matched
```

The item code is never compared. A second receipt row of a *different* fixed-asset item with the same
amount and quantity would match just as well.

`validate_asset_qty_with_purchase_doc` then checks the quantity ceiling
(`assets/doctype/asset/asset.py:521-562`):

```text
existing = Σ asset_quantity of other non-cancelled Assets for (MACHINE-A, PR-0001) = 0
purchased = Σ PR item qty for MACHINE-A = 2
0 + 2 > 2 ? no → accepted
```

The read and the insert are not serialised, so two concurrent asset creations for this receipt can both
see `existing = 0` and both pass (doc 41 §9, defect 3).

`validate_gross_and_purchase_amount` confirms `net_purchase_amount == purchase_amount`
(`assets/doctype/asset/asset.py:564-575`), and `before_save` derives
`total_asset_cost = 120,000.00 + 0` and `status = "Draft"`
(`assets/doctype/asset/asset.py:139-141`, `assets/doctype/asset/asset.py:785-817`).

### 3.2 Finance book and draft schedule

The category supplies the finance-book row (`assets/doctype/asset/asset.py:397-407`,
`assets/doctype/asset/asset.py:1112-1137`); we set Straight Line, 60 periods, monthly frequency, salvage
20,000.00. `validate_asset_finance_books` defaults `depreciation_start_date` to the last day of the
available-for-use month — 2026-01-31 — and validates the dates and counts
(`assets/doctype/asset/asset.py:612-636`, `assets/doctype/asset/asset.py:666-693`).

`set_depr_rate_and_value_after_depreciation` sets, on the asset and by `db_set` on every book row
(`assets/doctype/asset/asset.py:219-234`):

```text
value_after_depreciation = 120,000.00 − 0 + 0 = 120,000.00
```

`on_update` then creates the draft schedule (`assets/doctype/asset/asset.py:244-248`,
`assets/doctype/asset/asset.py:143-168`). Because the method is not `Manual`,
`has_depreciation_settings_changed` returns `True` unconditionally, so **every** subsequent save of this
asset regenerates the draft schedule (`assets/doctype/asset/asset.py:189-203`, doc 41 §5.3).

**ADS-0001** is generated (`assets/doctype/asset_depreciation_schedule/deppreciation_schedule_controller.py:28-37`):

```text
depreciable_value = 120,000.00 − 20,000.00 = 100,000.00
available_for_use_date 2026-01-31 is a month end → should_get_last_day = True
_check_is_pro_rata: from 2026-01-31 to 2026-01-31 → days = 1, total_days = 31 → has_pro_rata = True
final_number_of_depreciations = 60 − 0 + 1 = 61
pending_months = 60 × 1 + 0 = 60 ; pending_periods = 60
base amount = 100,000.00 / 60 = 1,666.6666… → 1,666.67
```

Row 0 is prorated over one day (`deppreciation_schedule_controller.py:318-341`,
`deppreciation_schedule_controller.py:211-216`):

```text
days = date_diff(2026-01-31, 2026-01-31) + 1 = 1
total_days = get_total_days(2026-01-31) = date_diff(2026-01-31, 2025-12-31) = 31
row 0 amount = 1,666.67 × 1 / 31 = 53.7635… → 53.76
```

Rows 1…59 are 1,666.67 each; row 60 is the last row, and `set_depreciation_amount_for_last_row` plus
`adjust_depr_amount_for_salvage_value` land it exactly on salvage value
(`deppreciation_schedule_controller.py:342-363`, `deppreciation_schedule_controller.py:364-379`):

```text
Σ rows 0..59 = 53.76 + 59 × 1,666.67 = 98,387.29
pending after row 59 = 120,000.00 − 98,387.29 = 21,612.71
row 60 = 21,612.71 − 20,000.00 = 1,612.71
Σ all rows = 100,000.00  exactly ; ending book value = 20,000.00
```

Total periods: 61 rows, the extra one being the proration remainder. The plan is a **draft**; it carries
no journals yet.

### 3.3 Submitting the asset

`on_submit` validates the in-use date, creates and submits an `Asset Movement`, reloads, posts the
capitalisation journal if warranted, activates the draft schedule, sets status and logs activity
(`assets/doctype/asset/asset.py:255-269`).

**ASM-0001** is inserted and submitted automatically, purpose `Receipt`, dated from the receipt's posting
timestamp (`assets/doctype/asset/asset.py:576-606`). It writes `location` and `custodian` back onto the
asset (`assets/doctype/asset_movement/asset_movement.py:153-160`).

`validate_make_gl_entry` probes the ledger (`assets/doctype/asset/asset.py:859-898`):

```text
purchase_document = PR-0001            (no update_stock invoice)
cwip_account resolvable                → yes
GL Entry exists for (PR-0001, CWIP)?   → yes  → post
```

`available_for_use_date` 2026-01-31 has arrived, so `make_gl_entries` posts two rows dated 2026-01-31 and
sets `booked_fixed_asset = 1` (`assets/doctype/asset/asset.py:936-983`):

| Account | Debit | Credit |
|---|---:|---:|
| Fixed Asset — Machinery | **120,000.00** | |
| Capital Work in Progress | | **120,000.00** |

Net of the receipt: `Dr Fixed Asset 120,000.00 / Cr Asset Received But Not Billed 120,000.00`, CWIP flat.

`convert_draft_asset_depr_schedules_into_active` submits ADS-0001, whose `on_submit` `db_set`s
`status = "Active"` (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:173-181`,
`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:87-90`). Asset status becomes
`Submitted`.

**Had the available-for-use date been in the future**, `make_gl_entries` would have posted nothing and
`booked_fixed_asset` would have stayed 0; the daily job `make_post_gl_entry` posts it on exactly that
date and never afterwards, because its filter is `available_for_use_date = nowdate()`
(`assets/doctype/asset/asset.py:1085-1103`, doc 41 §3.4). A scheduler outage on that one day strands
120,000.00 in CWIP permanently.

| Representation after asset submit | Value |
|---|---|
| `tabAsset` | 1, status `Submitted`, `booked_fixed_asset = 1` |
| `tabAsset Finance Book` | 1 row, `value_after_depreciation = 120,000.00` |
| `tabAsset Depreciation Schedule` | 1, status `Active` |
| `tabDepreciation Schedule` | **61** rows, no journals |
| `tabAsset Movement` + item | 1 + 1, purpose `Receipt` |
| `tabAsset Activity` | 2 (created, submitted) |
| `tabGL Entry` | 2 more (4 cumulative) |
| `tabStock Ledger Entry` | **0** |

---

## 4. Stage 3 — three months of depreciation

The daily job runs. `get_depreciable_assets_data` selects the schedule because the asset calculates
depreciation, is submitted, has status `Submitted`, and has child rows with no journal and
`schedule_date <= today` (`assets/doctype/asset/depreciation.py:81-112`).

It returns `(schedule, asset, MIN(idx) − 1, MAX(idx))` — an **index window**, not the exact due set. When
both bounds are passed, `_make_journal_entry_for_depreciation` skips its own due-date and already-posted
guard entirely (`assets/doctype/asset/depreciation.py:220-254`, doc 42 §5.1). In this scenario the window
happens to contain only due rows, so the outcome is correct; the mechanism is not.

Each period posts one journal, `voucher_type = "Depreciation Entry"`, dated on the schedule date, with
both legs referencing the asset (`assets/doctype/asset/depreciation.py:255-299`). Account direction comes
from the expense account's root type (`assets/doctype/asset/depreciation.py:300-314`).

| Period | Date | Amount | Debit | Credit |
|---|---|---:|---|---|
| 1 | 2026-01-31 | **53.76** | Depreciation Expense | Accumulated Depreciation |
| 2 | 2026-02-28 | **1,666.67** | Depreciation Expense | Accumulated Depreciation |
| 3 | 2026-03-31 | **1,666.67** | Depreciation Expense | Accumulated Depreciation |
| 4 | 2026-04-30 | **1,666.67** | Depreciation Expense | Accumulated Depreciation |

After the April run:

```text
accumulated depreciation = 53.76 + 3 × 1,666.67 = 5,053.77
value_after_depreciation = 120,000.00 − 5,053.77 = 114,946.23
```

`make_depreciation_entry` reloads the asset, recomputes status — now `Partially Depreciated` because book
value is below cost and above salvage (`assets/doctype/asset/asset.py:785-817`) — and `db_set`s
`depr_entry_posting_status = "Successful"`, a single scalar covering four periods
(`assets/doctype/asset/depreciation.py:169-218`).

| Representation after four periods | Value |
|---|---|
| `tabJournal Entry` | **4** |
| `tabGL Entry` | 8 more (12 cumulative) |
| `tabDepreciation Schedule` rows with `journal_entry` | 4 of 61 |
| `Asset.status` | `Partially Depreciated` |
| `Asset Finance Book.value_after_depreciation` | 114,946.23 |

Note what is **not** recorded: nothing links a posted journal to the plan version that produced it, and
nothing constrains one posting per period other than the nullable `journal_entry` column.

---

## 5. Stage 4 — a capitalised repair

One machine fails on 2026-04-20 and is repaired for 3,000.00 of external service, invoiced on a submitted
Purchase Invoice **PI-REP-0001** against Repairs Expense. Completion date 2026-04-30, no spare parts,
`capitalize_repair_cost = 1`, `increase_in_asset_life = 0`.

### 5.1 Saving the repair changes the asset immediately

`AssetRepair.validate` runs `update_status`, which — while `repair_status = "Pending"` — sets the **asset**
to `Out of Order` with `db.set_value` (`assets/doctype/asset_repair/asset_repair.py:177-187`).

That has a consequence the user never sees: `get_depreciable_assets_data` only selects assets whose status
is `Submitted` or `Partially Depreciated` (`assets/doctype/asset/depreciation.py:81-112`). **A saved but
unsubmitted repair therefore silently suspends depreciation posting for that asset.** If this repair had
been left pending across the 2026-04-30 run, period 4 would simply not have posted, and — because
selection is by unposted state and date, not by a durable due record — it would post on the next run
after the repair was submitted, dated 2026-04-30. Correct in the end, invisible in the meantime.

### 5.2 Residual validation against the ledger

`validate_purchase_invoice_repair_cost` checks the row against the unallocated amount
(`assets/doctype/asset_repair/asset_repair.py:158-176`,
`assets/doctype/asset_repair/asset_repair.py:459-514`):

```text
total_amount = Σ debit − Σ credit on Repairs Expense for PI-REP-0001 = 3,000.00
used_amount  = Σ repair_cost on submitted Asset Repair Purchase Invoice rows (other parents) = 0
available    = 3,000.00 ; requested 3,000.00 → accepted
```

This is the only genuine residual check in the Assets module — and it is still read-then-write with no
lock on the invoice, so a second repair could allocate the same 3,000.00 concurrently (doc 43 §9,
defect 15).

Costs are summed (`assets/doctype/asset_repair/asset_repair.py:188-200`):

```text
consumed_items_cost = 0.00 ; repair_cost = 3,000.00 ; total_repair_cost = 3,000.00
```

### 5.3 Submit

`repair_status` is set to `Completed` (submission is refused while `Pending`,
`assets/doctype/asset_repair/asset_repair.py:238-241`). `on_submit` issues stock (none here), updates
asset value, sets life extension, re-plans depreciation, logs activity and posts GL
(`assets/doctype/asset_repair/asset_repair.py:201-213`).

`update_asset_value` adds 3,000.00 to `total_asset_cost` and `additional_asset_cost`, adds it to **every**
finance book's `value_after_depreciation`, and saves the submitted asset with
`ignore_validate_update_after_submit` (`assets/doctype/asset_repair/asset_repair.py:242-254`):

```text
total_asset_cost         = 120,000.00 + 3,000.00 = 123,000.00
additional_asset_cost    = 3,000.00
value_after_depreciation = 114,946.23 + 3,000.00 = 117,946.23
```

With one finance book this is right; with two books the same 3,000.00 would be added to both (doc 43 §9,
defect 16).

GL, dated on `completion_date` 2026-04-30
(`assets/doctype/asset_repair/services/gl_composer.py:30-75`):

| Account | Debit | Credit |
|---|---:|---:|
| Fixed Asset — Machinery | **3,000.00** | |
| Repairs Expense | | **3,000.00** |

### 5.4 The re-plan

`reschedule_depreciation` copies the active schedule, regenerates it, cancels the original with
`should_not_cancel_depreciation_entries = True`, and submits the copy
(`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:193-219`).

**ADS-0002** is generated from the new book value. `clear` keeps the four posted rows and restarts at
index 4 (`deppreciation_schedule_controller.py:38-53`); `initialize_variables` seeds pending from
`value_after_depreciation`:

```text
pending value      = 117,946.23
depreciable_value  = 117,946.23 − 20,000.00 = 97,946.23
last_depr_date     = 2026-04-30 (row 3's schedule date)
asset_used_for_months = 1 × (1 + 0) = 1
computed_available_for_use_date = 2026-01-31 + (−1 month) + 1 day = 2026-01-01
                                  → earlier than 2026-01-31, so clamped to 2026-01-31
depr_booked_for_months = (date_diff(2026-04-30, 2026-01-31) + 1) / (365/12)
                       = 90 / 30.4166… = 2.9589…
pending_months     = 60 − 2.9589… = 57.0410…
pending_periods    = 57.0410…
new base amount    = 97,946.23 / 57.0410959… = 1,717.1169… → 1,717.12
```

`get_booked_depr_for_months_count` converts a **day count into fractional months** using `365/12`
(`deppreciation_schedule_controller.py:236-251`), which is why the post-repair instalment is not a round
division of the remaining periods. Four periods were booked, but the engine treats 2.9589 "months" as
consumed.

The new plan therefore has 4 posted rows carried over plus rows 4…60 at 1,717.12, with the final row
adjusted to land on 20,000.00:

```text
Σ posted (rows 0..3)     = 5,053.77
Σ rows 4..59 (56 rows)   = 56 × 1,717.12 = 96,158.72
pending after row 59     = 123,000.00 − 5,053.77 − 96,158.72 = 21,787.51
row 60                   = 21,787.51 − 20,000.00 = 1,787.51
Σ all rows               = 103,000.00 = cost 123,000.00 − salvage 20,000.00  ✔
```

The plan is exact. What is not exact is the **provenance**: ADS-0001 is cancelled but its four journals
survive and now also appear as rows in ADS-0002 (`frappe.copy_doc` carries `journal_entry`), so one posted
depreciation journal belongs to two schedule documents and neither owns it (doc 42 §12, defect 19).

| Representation after the repair | Value |
|---|---|
| `tabAsset Repair` + 1 invoice row | 1 + 1 |
| `tabStock Entry` | 0 (no spares) |
| `tabGL Entry` | 2 more (14 cumulative) |
| `tabAsset Depreciation Schedule` | 2 (ADS-0001 cancelled, ADS-0002 active) |
| `Asset.total_asset_cost` | 123,000.00 |
| `Asset.status` | recomputed from book value → `Partially Depreciated` |

---

## 6. Stage 5 — selling one of the two machines

On 2026-05-31 one machine is sold for 45,000.00 on **SI-0001**, with the fixed-asset row pointing at
ASS-0001 and quantity 1.

Before that, period 5 posts on 2026-05-31: 1,717.12, taking accumulated to
`5,053.77 + 1,717.12 = 6,770.89` and book value to `123,000.00 − 6,770.89 = 116,229.11`.

### 6.1 Validation and the implicit split

`FixedAssetService.validate_fixed_asset` requires the asset, forbids `update_stock`, and refuses
already-disposed statuses (`accounts/doctype/sales_invoice/services/fixed_assets.py:23-57`).

`split_asset_based_on_sale_qty` compares sale quantity to asset quantity and splits the remainder
(`accounts/doctype/sales_invoice/services/fixed_assets.py:74-87`,
`accounts/doctype/sales_invoice/services/fixed_assets.py:131-159`):

```text
actual_qty 2, sale_qty 1 → remaining 1 → split_asset(ASS-0001, 1)
```

`split_asset` creates **ASS-0002** for the split quantity and scales the original
(`assets/doctype/asset/mapper.py:189-206`, `assets/doctype/asset/mapper.py:218-250`):

```text
scaling_factor (new)      = 1 / 2 = 0.5
ASS-0002: net_purchase_amount 60,000.00 ; additional_asset_cost 1,500.00
          total_asset_cost 61,500.00 ; value_after_depreciation 58,114.555 → 58,114.56
          asset_quantity 1 ; split_from ASS-0001
ASS-0001: scaled by 1/2 as well → the same figures, asset_quantity 1
```

Note the arithmetic: the *existing* asset is rescaled with `scaling_factor = remaining_qty / asset_quantity`
in a second `process_asset_split` call, so both halves end at 50% of the pre-split values. **They do not sum
back to the parent even at 1-of-2**: `116,229.11 / 2 = 58,114.555`, which rounds to `58,114.56` for both
halves, so the pair totals `116,229.12` — one cent more than the asset they came from. A 1-of-3 split
multiplies by `1/3` and `2/3` as floats and drifts further, with no residual rule anywhere (doc 43 §9,
defect 24). That cent is the only part of this scenario's final imbalance that is *not* the capitalised
repair.

`flags.is_split_asset` suppresses `validate_linked_purchase_documents`
(`assets/doctype/asset/asset.py:499-520`), so neither half re-checks the receipt ceiling — necessary,
since neither matches the receipt line any more.

`update_finance_books` re-plans both assets by cancel-and-copy, and for the new asset walks the active
schedule and rewrites every posted depreciation journal
(`assets/doctype/asset/mapper.py:272-288`). "Rewrites" is literal: `add_reference_in_jv_on_split` flips the
journal's `docstatus` to 2, calls `make_gl_entries(1)` to cancel the posted GL rows, flips it back to 1 and
re-posts them (`assets/doctype/asset/mapper.py:345-360`). Five submitted journals and their GL rows are
cancelled and re-created in place.

It does, however, **conserve the total**: `adjust_account_balance` reduces the source asset's leg by exactly
the amount `add_new_entries` adds for the target (`assets/doctype/asset/mapper.py:362-390`), so accumulated
depreciation in GL stays correct and becomes attributable per asset. Keep that in mind for §10.4 — it is the
one place upstream is *stricter* than a naive fact-sum design would be.

### 6.2 Depreciation to the disposal date

`process_asset_depreciation` sees a non-return invoice at `docstatus = 1` and depreciates to the disposal
date (`accounts/doctype/sales_invoice/services/fixed_assets.py:62-73`,
`accounts/doctype/sales_invoice/services/fixed_assets.py:94-101`). The disposal date is the invoice's
posting date, 2026-05-31 (`accounts/doctype/sales_invoice/services/fixed_assets.py:88-93`).

Period 5 already posted on exactly that date, so `set_depreciation_amount_for_disposal` computes a
zero-day remainder and adds nothing (`deppreciation_schedule_controller.py:297-317`). Book value of the
sold half stands at `116,229.11 / 2 = 58,114.56` after rounding.

### 6.3 GL

`get_gl_entries_for_fixed_asset` uses the disposal legs, with `against` set to the customer
(`accounts/doctype/sales_invoice/services/gl_composer.py:407-431`). The legs come from
`get_gl_entries_on_asset_disposal` (`assets/doctype/asset/depreciation.py:639-695`,
`assets/doctype/asset/depreciation.py:696-716`):

```text
net_purchase_amount (sold half)  = 60,000.00
value_after_depreciation          = 58,114.56
accumulated_depr_amount           = 60,000.00 − 58,114.56 = 1,885.44
profit_amount = 45,000.00 − 58,114.56 = −13,114.56   → a loss
```

| Account | Debit | Credit |
|---|---:|---:|
| Accumulated Depreciation | **1,885.44** | |
| Loss on Asset Disposal | **13,114.56** | |
| Fixed Asset — Machinery | | **60,000.00** |
| Debtors | **45,000.00** | |
| **Total** | **60,000.00** | **60,000.00** |

The asset legs alone are unbalanced by design; the receivable leg of the same invoice completes them, which
is why a fixed-asset row must use an asset-disposal income account
(`accounts/doctype/sales_invoice/services/fixed_assets.py:58-61`).

Two things about `accumulated_depr_amount` deserve attention. First, it is **derived by subtraction**
(`assets/doctype/asset/depreciation.py:696-716`), so it includes the 1,500.00 of capitalised repair that
raised book value — the debit to Accumulated Depreciation here is not what that account actually
accumulated for this half (which was `6,770.89 / 2 = 3,385.45`). Second, the two figures differ precisely
because the repair was booked to the fixed-asset account while `net_purchase_amount` was left untouched
(doc 42 §8, doc 43 §9 defect 27).

`_update_asset` then writes `disposal_date` and status `Sold` with `db.set_value`
(`accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`).

| Representation after the sale | Value |
|---|---|
| `tabAsset` | 2 (ASS-0001 `Sold`, ASS-0002 active) |
| `tabAsset Depreciation Schedule` | 4 (two cancelled, two active) |
| amended `tabJournal Entry` rows | 5 |
| `tabGL Entry` | 3 asset legs + ordinary invoice legs |
| `tabAsset Activity` | +3 (split created, split updated, sold) |

---

## 7. Stage 6 — scrapping the other machine

On 2026-06-30 ASS-0002 is scrapped. Period 6 posts first for that asset's own plan; for clarity take its
book value at 2026-06-30 as **57,256.00** after one more period of `1,717.12 / 2 = 858.56`.

`scrap_asset` writes `disposal_date` **before** validating
(`assets/doctype/asset/depreciation.py:367-379`), validates status and dates
(`assets/doctype/asset/depreciation.py:380-404`), depreciates to the scrap date and creates the journal
(`assets/doctype/asset/depreciation.py:431-456`):

```text
net_purchase_amount = 60,000.00
value_after_depreciation = 57,256.00
accumulated_depr_amount = 2,744.00
profit_amount = 0.00 − 57,256.00 = −57,256.00 → loss
```

| Account | Debit | Credit |
|---|---:|---:|
| Accumulated Depreciation | **2,744.00** | |
| Loss on Asset Disposal | **57,256.00** | |
| Fixed Asset — Machinery | | **60,000.00** |
| **Total** | **60,000.00** | **60,000.00** |

This journal balances on its own because there are no proceeds. Status becomes `Scrapped` — but only
because `journal_entry_for_scrap` is set on the asset (`assets/doctype/asset/asset.py:785-817`), and
`create_journal_entry_for_scrap` never writes that field
(`assets/doctype/asset/depreciation.py:431-456`); the link is established by the Journal Entry's own asset
handling. `restore_asset` is the documented reversal path
(`assets/doctype/asset/depreciation.py:457-472`, `assets/doctype/asset/depreciation.py:473-480`).

---

## 8. Complete write and balance trace

Counts omit Version rows, ToDo rows and cache internals. GL counts are post-merge economic rows under the
stated account setup.

| Stage | Primary writes | JE | GL | SLE | Projections mutated |
|---|---|---:|---:|---:|---|
| Purchase Receipt | PR 1 + item 1 | 0 | **2** | **0** | PO/billing status |
| Asset create (draft) | Asset 1 + FB 1 + ADS 1 + 61 schedule rows | 0 | 0 | 0 | `purchase_receipt_item`, `total_asset_cost`, `status` |
| Asset submit | ASM 1 + item 1 | 0 | **2** | 0 | `booked_fixed_asset`, `location`, `custodian`, ADS `status`, asset `status` |
| Depreciation ×4 | 4 JE | **4** | **8** | 0 | 4 `journal_entry` links, book value, asset `status`, `depr_entry_posting_status` |
| Repair save | Asset Repair draft | 0 | 0 | 0 | **asset `status` → `Out of Order`** |
| Repair submit | Asset Repair 1 + PI row 1 + ADS 1 | 0 | **2** | 0 | `total_asset_cost`, `additional_asset_cost`, book value, ADS-0001 cancelled |
| Depreciation ×1 (period 5) | 1 JE | **1** | **2** | 0 | 1 link, book value |
| Sale | SI 1 + item 1 + Asset 1 (split) + ADS 2 | 0 | **3** asset legs + invoice legs | 0 | 5 JE cancelled and **re-posted**, scaled amounts on both assets, `disposal_date`, `status` |
| Depreciation ×1 (period 6, scrapped half only) | 1 JE | **1** | **2** | 0 | 1 link, book value |
| Scrap | 1 JE | **1** | **3** | 0 | `disposal_date`, `journal_entry_for_scrap`, `status` |
| **Total** | | **7 depreciation/disposal JE** | **24 economic GL** | **0 SLE** | many direct writes |

Period 6 posts for **ASS-0002 only**. ASS-0001 was set to `Sold`, and `get_depreciable_assets_data` selects
only `Submitted` and `Partially Depreciated` assets
(`assets/doctype/asset/depreciation.py:81-112`), so the sold half stops depreciating — correctly.

The complete accounting proof across the asset's life, treating the two halves together:

```text
receipt:        Dr CWIP 120,000.00        / Cr Received But Not Billed 120,000.00
recognition:    Dr Fixed Asset 120,000.00 / Cr CWIP 120,000.00
depreciation:   Dr Depreciation Expense 6,770.89 / Cr Accumulated Depreciation 6,770.89   (periods 1–5)
repair:         Dr Fixed Asset 3,000.00   / Cr Repairs Expense 3,000.00
period 6:       Dr Depreciation Expense   858.56 / Cr Accumulated Depreciation   858.56   (ASS-0002 only)
sale:           Dr Accum. Depr 1,885.44 + Dr Loss 13,114.56 + Dr Debtors 45,000.00
                / Cr Fixed Asset 60,000.00 (+ ordinary invoice legs)
scrap:          Dr Accum. Depr 2,744.00 + Dr Loss 57,256.00 / Cr Fixed Asset 60,000.00
```

Both accounts end non-zero:

```text
Fixed Asset:              123,000.00 debited − 120,000.00 removed = 3,000.00 left (debit)
Accumulated Depreciation:   7,629.45 posted  −   4,629.44 removed = 3,000.01 left (credit)
```

### 8.1 What the residuals actually prove

The two residuals are **the same number with opposite signs**, and that is not a coincidence of these
inputs. Write `P` for total posted depreciation. Each disposal debits accumulated depreciation with
`net_purchase_amount − value_after_depreciation`, and the two halves' book values sum to `123,000.00 − P`:

```text
accumulated debited = 120,000.00 − (vad₁ + vad₂) = 120,000.00 − (123,000.00 − P)
AccDep residual     = P − (120,000.00 − 123,000.00 + P) = 3,000.00
Fixed-asset residual= 123,000.00 − 120,000.00            = 3,000.00
```

Both equal `additional_asset_cost` exactly, independently of the instalment, the number of periods, or when
the sale happened. The extra **0.01** on the accumulated side is the split-rounding cent from §6.1, nothing
more.

So the honest finding is narrower and more interesting than "the books do not close":

- **Net book value removed is correct.** The two residuals cancel, so total assets are right.
- **The gain and the loss are correct.** Both derive from `value_after_depreciation`, which tracked the
  capitalised repair properly.
- **The balance-sheet split is wrong.** Cost is overstated by 3,000.00 and accumulated depreciation is
  overstated by 3,000.00. The capitalised repair is **silently reclassified as depreciation** at disposal.

That is invisible in the P&L and invisible in net assets. It is visible in the gross-cost and
accumulated-depreciation columns of every fixed-asset register, in depreciation-to-cost ratios, and in any
disclosure note that reports cost and accumulated depreciation separately — which is to say, in exactly the
places a statutory audit looks.

The root cause is still the one this scenario exists to demonstrate: **disposal removes
`net_purchase_amount` and an accumulated-depreciation figure derived by subtraction
(`assets/doctype/asset/depreciation.py:639-695`,
`assets/doctype/asset/depreciation.py:696-716`), rather than reading each amount from its own ledger.** Any
cost addition that raises book value without raising `net_purchase_amount` produces this reclassification,
and a revaluation (doc 42 §8) produces it too.

### 8.1 Evidence versus projection

| Representation | Classification |
|---|---|
| Purchase Receipt + its CWIP GL rows | acquisition cost evidence |
| `Asset` document | acquisition authorisation, mixed with register state |
| `purchase_receipt_item` | inferred by amount/quantity matching |
| capitalisation GL pair | recognition evidence |
| `booked_fixed_asset` | mutable idempotency proxy |
| `Asset Depreciation Schedule` versions | plan snapshots; posted rows appear in several |
| `Depreciation Schedule.journal_entry` | mutable link doubling as posted-state evidence |
| depreciation journals + GL | the real depreciation evidence |
| `Asset Finance Book.value_after_depreciation` | mutable projection written by repair, split, adjustment |
| `Asset Repair` + invoice allocation row | repair command evidence, ledger-checked but unlocked |
| repair GL pair | cost addition evidence |
| `total_asset_cost` / `additional_asset_cost` | mutable scalars |
| split child asset + `split_from` | new identity created by document copy |
| amended depreciation journals | posted evidence edited in place |
| sale/scrap disposal GL | disposal evidence |
| `disposal_date`, `journal_entry_for_scrap`, `status` | mutable scalars written by several callers |
| `Asset Movement` + recomputed `location`/`custodian` | custody evidence plus mutable scalars |
| `Asset Activity` | translated human log |

The strongest audit path is:

```text
PR line → CWIP GL → Asset (matched) → recognition GL
  → plan version(s) → depreciation journals → GL
  → repair invoice allocation → repair GL → new plan version
  → split transformation (document copy) → amended journals
  → disposal GL (sale) and disposal GL (scrap)
```

Every arrow that is not a GL row is either inferred, copied, or mutable.

---

## 9. Cancellation and safe reversal order

Reverse the worked chain in dependency order:

1. **Scrap.** `restore_asset` reverses the disposal-date depreciation, resets the schedule, cancels the
   scrap journal and clears `disposal_date`/`journal_entry_for_scrap`
   (`assets/doctype/asset/depreciation.py:457-480`). The reversal journal is dated **today**, not on the
   original period (`assets/doctype/asset/depreciation.py:548-569`), and
   `update_value_after_depreciation_on_asset_restore` clears `journal_entry` on a submitted schedule row
   with `update_modified=False` (`assets/doctype/asset/depreciation.py:570-578`).
2. **Sale.** Cancelling SI-0001 flips `process_asset_depreciation` to the restore branch
   (`accounts/doctype/sales_invoice/services/fixed_assets.py:62-73`,
   `accounts/doctype/sales_invoice/services/fixed_assets.py:102-109`) and `_update_asset` clears
   `disposal_date` and recomputes status
   (`accounts/doctype/sales_invoice/services/fixed_assets.py:110-130`). **The split is not undone**: ASS-0002
   continues to exist, and the amended journals keep their new references.
3. **Repair.** Cancelling the repair reverses the value change, posts reversing GL, reverses the life
   extension and re-plans (`assets/doctype/asset_repair/asset_repair.py:221-234`). Had spares been
   consumed, the `Material Issue` Stock Entry would **not** be cancelled
   (`assets/doctype/asset_repair/asset_repair.py:258-294`, doc 43 §9 defect 19).
4. **Depreciation.** Individual depreciation journals can be cancelled directly; the schedule's own
   `on_cancel` cancels them all unless the caller suppressed it
   (`assets/doctype/asset_depreciation_schedule/asset_depreciation_schedule.py:106-122`).
5. **Asset.** `on_cancel` refuses `In Maintenance`/`Out of Order` and any status outside
   `Submitted`/`Partially Depreciated`/`Fully Depreciated`
   (`assets/doctype/asset/asset.py:733-742`); it cancels movements, cancels depreciation journals, cancels
   schedules, reverses the recognition GL and clears `booked_fixed_asset`
   (`assets/doctype/asset/asset.py:270-282`).
6. **Purchase Receipt.** Cancel last.

The gap in step 2 is the important one: a reversed sale leaves a split asset behind, so the register has two
identities where the business has one machine — and no event says why.

---

## 10. The same lifecycle in our design

### 10.1 Acquisition and recognition

The receipt line's cost is allocated explicitly:

```text
asset_source_allocation(source = purchase_receipt_line, asset = ASS-A, qty 1, amount 60,000.00)
asset_source_allocation(source = purchase_receipt_line, asset = ASS-B, qty 1, amount 60,000.00)
```

Because we create **one asset per identified unit** (doc 41 §10), there is no `asset_quantity` and no later
split. The allocation rows are bounded by a deferred trigger against the receipt line's residual under a
source-line lock, so the concurrency hole in §3.1 cannot occur.

Recognition is `asset_recognition`, selected by `effective_date <= as_of AND no unreversed recognition`,
so a missed run self-heals and a double run is a no-op (doc 41 §8.2).

### 10.2 Depreciation

`depreciation_plan` version 1 is generated from the approved `asset_policy_revision`; each period is a
`depreciation_plan_period` with an explicit `basis_days`. Posting inserts `depreciation_posting` keyed by
`depreciation_period`, with **at most one unreversed posting per period**, enforced by a deferred trigger
under the asset/book lock (doc 42 §11.2). A partial unique index would forbid re-posting after a reversal.
The four January–April periods are four facts; the plan version they satisfy is recorded on each.

The repair generates plan version 2. Version 1 is superseded, not cancelled, and **no posted fact moves**:
version 2 simply starts at period 5. The `365/12` fractional-month conversion is replaced by an exact
remaining-period count, so the post-repair instalment is:

```text
remaining depreciable = (123,000.00 − 20,000.00) − 5,053.77 = 97,946.23
remaining periods     = 61 − 4 = 57
instalment            = 1,718.35  (with the residual on the final period)
```

### 10.3 Repair

`asset_service_event` records downtime and actions; `asset_service_cost_allocation` allocates 3,000.00 from
the exact invoice line under a source lock; an `asset_cost_event` records the capitalised addition and its
per-book apportionment. Saving the repair changes **nothing** about the asset's state, so depreciation is
never silently suspended (doc 43 §8.3).

### 10.4 Disposal

Each disposal is an `asset_disposal` with **at most one unreversed disposal per asset**, enforced by a
deferred trigger counting unreversed rows under the asset lock (a partial unique index would forbid
re-disposing after a reversal, which §9 shows is a legitimate flow). Its voucher is built from **facts, not
subtraction**.

Because §10.1 gives each machine its own identity, the repaired machine carries its own repair in full —
cost 60,000.00 + 3,000.00, salvage 10,000.00 — rather than having a single-machine repair smeared across two
units. Its own plan yields period instalments of 833.33, a 26.88 prorated first period, and a post-repair
instalment of `(63,000.00 − 10,000.00 − 2,526.87) / 57 = 885.49`:

```text
cost removed                 = Σ asset_cost_event                    = 63,000.00
accumulated depr. removed    = Σ depreciation_posting (5 periods)     =  3,412.36
revaluation reserve released = Σ asset_revaluation                    =      0.00
proceeds                     = 45,000.00
gain/loss                    = 45,000.00 − (63,000.00 − 3,412.36 − 0.00) = −14,587.64
```

The loss differs from §6.3's 13,114.56 precisely *because* the economics differ: upstream spread a
single-machine repair across two units and then halved it, so the machine that was actually repaired carried
only 1,500.00 of the 3,000.00 it consumed. Attributing cost to the unit that incurred it is the point of
one-asset-per-unit, not a rounding difference.

Both machines' disposals remove exactly what was posted, so:

```text
Fixed Asset balance(asset)               = 63,000.00 − 63,000.00 = 0.00
Accumulated Depreciation balance(asset)  =  3,412.36 −  3,412.36 = 0.00
Revaluation reserve balance(asset)       =      0.00
```

The 3,000.00 reclassification of §8 cannot occur, because `cost_removed` and `accumulated_removed` are each
read from their own ledger rather than derived by subtraction. The split cent of §6.1 cannot occur either:
there is no split, and where a genuine transformation is needed, `asset_transformation_part` carries exact
apportionment with one designated residual part.

Cancelling a sale reverses the disposal fact only; there is no split to leave behind, and if a genuine
transformation had occurred it would be reversed by its own `asset_transformation` reversal with stored
apportionment (doc 43 §8.4).

---

## 11. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Which purchase line funded the asset | matched by amount and quantity | explicit `asset_source_allocation` |
| Quantity conservation | unlocked aggregate, bypassed by split | bounded allocation under a source-line lock |
| Multiple units | one asset with `asset_quantity` | one asset per unit |
| Recognition into service | conditional on GL probes + `= nowdate()` job | `asset_recognition`, self-healing, unique |
| Recognition idempotency | `booked_fixed_asset` boolean | unique recognition row |
| Depreciation plan | submittable document, cancel-and-copy | immutable plan versions with supersession |
| Posted period identity | nullable `journal_entry` on a plan row | `depreciation_period` + unique unreversed posting |
| Posting selection | index window, mutable asset status, session roles | due periods only, period control per date |
| Posting outcome | one scalar per asset | per-period attempt records |
| Repair cost residual | GL-checked, unlocked | same bound under a source lock |
| Repair effect on asset | saves a submitted document, all books | `asset_cost_event` with per-book apportionment |
| Draft repair side effect | suspends depreciation via status | none |
| Splitting | document copy, float scaling, journals amended | explicit transformation with stored apportionment, or unnecessary |
| Disposal cost removed | `net_purchase_amount` scalar | Σ cost events |
| Disposal accumulated depreciation | cost − book value (reclassifies additions) | Σ postings |
| Revaluation at disposal | absorbed into accumulated depreciation | released from its own reserve |
| Disposal uniqueness | none | one unreversed disposal per asset |
| Disposal callers | four, each writing status | one disposal service |
| Custody | recomputed scalars | event-sourced with projection |
| Reversal | mixed cancel/clear/amend | append-only compensating facts |
| Audit trail | translated activity sentences | typed events with stable codes |

---

## 12. Findings and invariants exercised

1. **Asset identity is inferred, not allocated.** The receipt link is resolved by matching amount and
   quantity, and the quantity ceiling is an unlocked aggregate that the split path bypasses.
2. **Recognition depends on ledger archaeology and a single-day scheduler filter.** A missed run strands
   cost in CWIP with no retry.
3. **The plan and the postings share a mutable child table.** Re-planning cancels a schedule while keeping
   its journals, and copies those journals into the successor.
4. **A saved draft repair silently suspends depreciation** because posting selection reads mutable asset
   status.
5. **Cost additions are applied to every finance book in full.** With one book that is right; the defect
   is the GL double-count it would cause with two, and the life extension applied uniformly.
6. **Re-planning after a cost change converts booked periods into fractional months** via `365/12`, so the
   new instalment is not a clean division of remaining periods — although the plan still totals exactly.
7. **Selling part of a multi-quantity asset silently creates a second asset**, scales every amount by a
   float ratio that does not conserve even at 1-of-2 (one cent), and **cancels and re-posts submitted
   depreciation journals and their GL rows** — while, to its credit, conserving the accumulated-depreciation
   total across the two assets.
8. **Disposal removes `net_purchase_amount` and a subtracted accumulated depreciation.** Net book value and
   gain/loss stay correct, but cost and accumulated depreciation are each overstated by exactly the
   capitalised addition — 3,000.00 here — so the addition is silently reclassified as depreciation on the
   balance sheet. Revaluations reclassify the same way.
9. **Cancelling a sale does not undo the split** it caused.
10. **Every state answer is a mutable scalar** written by asset submit, movements, repairs, splits,
    schedules, scheduled jobs and four disposal callers.

This scenario exercises the whole Tranche C register: **A1–A9** (identity, derived state, idempotent
capitalisation, additions as allocations, policy revisions, typed place/custody/audit, evidence before
projection, relational integrity, serializable decisions), **A10–A18** (plan versus posting, deterministic
schedules, idempotent posting, shift plans, reconciled revaluation, dated disposal depreciation, evidence
before projection, relational and serializable depreciation), and **A19–A26** (event-sourced custody,
non-cyclic maintenance, allocated repair cost, authorised transformation, single disposal, evidence before
projection, relational and serializable custody/service/disposal). It also reuses **F1** (balanced
vouchers) from S04 — and demonstrates the one case in this repository where every voucher balances, net
assets are right, and the balance sheet is still wrong, because two accounts are misstated by equal and
opposite amounts.

---

Cross-references: **[S03](S03-procure-to-pay.md)** (Purchase Receipt and invoice mechanics),
**[S01](S01-order-to-cash.md)** (Sales Invoice and returns), **[S05](S05-period-close-and-opening-balances.md)**
(period control and frozen dates, which gate depreciation posting);
**[doc 41](../logic/41-asset-identity-acquisition-and-finance-books.md)** (identity, acquisition,
capitalisation, finance books), **[doc 42](../logic/42-depreciation-engine-schedules-shifts-and-adjustments.md)**
(schedules, methods, posting, revaluation), **[doc 43](../logic/43-asset-custody-maintenance-repair-and-disposal.md)**
(custody, maintenance, repair, split, disposal), **[doc 01](../logic/01-gl-posting-engine.md)** (posting and
reversal), **[doc 22](../logic/22-background-jobs-scheduling-and-locking.md)** (scheduler and locking),
**[doc 40](../logic/40-tranche-b-coverage-closure-and-our-production-spec.md)** (command, lock, idempotency
and outbox contract) and `docs/design/FINAL-SCHEMA.md` (target asset tables).
