# 41 — Asset Identity, Acquisition and Finance Books

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev)
> and `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe
> citations are prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

This opens **Tranche C**, the deferred assets investigation. Docs 33–40 closed production; assets are
the remaining subsystem that creates long-lived balance-sheet objects whose value changes on a
**schedule** rather than on a transaction. Before depreciation can be specified (doc 42) or disposal
traced (doc 43), three questions have to be answered exactly:

1. **What is an asset, and when does one exist?** ERPNext's `Asset` is a submittable document that is
   *also* a mutable register row: quantity, purchase amount, status, `value_after_depreciation` and
   `booked_fixed_asset` are all rewritten after submission by other documents and by scheduled jobs.
2. **Where does its cost come from?** Three different acquisition paths (Purchase Receipt, Purchase
   Invoice with `update_stock`, and Asset Capitalization) reach the fixed-asset account through
   different accounts, at different times, with a *conditional* capitalisation posting.
3. **Which policy governs its depreciation?** `Asset Finance Book` rows are a per-asset copy of
   `Asset Category` policy with no revision identity, and one row per Finance Book is the multi-book
   mechanism.

The findings that matter for our design:

- an asset's identity is **not** conserved against its purchase document: the link is resolved by
  *matching amounts and quantities*, and total asset quantity against a purchase document is checked
  by an unlocked aggregate (`assets/doctype/asset/asset.py:314-325`,
  `assets/doctype/asset/asset.py:521-562`);
- capitalisation to the fixed-asset account is **conditional on which GL rows already exist**, decided
  by four `frappe.db.exists` probes rather than by a typed acquisition state
  (`assets/doctype/asset/asset.py:859-898`);
- a daily scheduled job posts the deferred capitalisation entry for assets whose
  `available_for_use_date` is exactly today, so a missed run silently leaves cost in CWIP
  (`assets/doctype/asset/asset.py:1085-1103`, `hooks.py:496-527`);
- `Asset Capitalization` rewrites its target asset's `net_purchase_amount`, `purchase_amount` and
  `total_asset_cost` with read-modify-write arithmetic on a submitted document
  (`assets/doctype/asset_capitalization/asset_capitalization.py:425-450`); and
- asset accounts are resolved by a three-level fallback (category row → company default → error) with
  no company scoping on the category-account lookup itself
  (`assets/doctype/asset/asset.py:1139-1163`, `assets/doctype/asset_category/asset_category.py:195-216`).

---

## 1. The fourteen Assets parents and what each really is

`Assets` has 26 tables, of which 14 are parents and 8 are submittable. This document covers the
identity/acquisition half; doc 42 covers depreciation, doc 43 covers custody, upkeep and disposal.

| Parent | Submittable | Controller | Real role |
|---|:--:|---|---|
| Asset | yes | `Asset(AccountsController)` (`assets/doctype/asset/asset.py:41-121`) | register row + acquisition voucher + depreciation policy holder |
| Asset Category | no | `AssetCategory(Document)` (`assets/doctype/asset_category/asset_category.py:11-35`) | account map per company + default finance-book policy |
| Asset Capitalization | yes | `AssetCapitalization(StockController)` (`assets/doctype/asset_capitalization/asset_capitalization.py:45-100`) | converts stock, assets and services into one composite asset |
| Asset Activity | no | `AssetActivity(Document)` (`assets/doctype/asset_activity/asset_activity.py:9-25`) | free-text audit trail row |
| Location | no | `Location(NestedSet)` (`assets/doctype/location/location.py:15-44`) | nested-set place with GeoJSON area arithmetic |
| Asset Depreciation Schedule | yes | doc 42 | the schedule document |
| Asset Shift Allocation | yes | doc 42 | shift-based depreciation input |
| Asset Value Adjustment | yes | doc 42 | revaluation |
| Asset Movement | yes | doc 43 | custody transfer |
| Asset Repair | yes | doc 43 | repair cost and capitalisation |
| Asset Maintenance / Maintenance Log / Maintenance Team | log only | doc 43 | upkeep planning |
| Asset Shift Factor | no | doc 42 | shift multiplier master |

`Asset Finance Book` is a child table with **no controller behaviour at all** — it is a bare
`Document` subclass whose fields carry the entire per-asset depreciation policy
(`assets/doctype/asset_finance_book/asset_finance_book.py:8-37`).

> **Invariant A1 — an asset is an identified, conserved object.** An asset has one immutable identity
> created by an authorised acquisition event, and every later cost, depreciation, custody, impairment
> or disposal fact references that identity. Identity is never inferred by matching amounts or
> quantities against a purchase document, and the number of assets recognised from a purchase line can
> never exceed the quantity that line actually received.

---

## 2. Asset as a document and as a register row

### 2.1 Validation order

`Asset.validate` runs a fixed sequence: category, precision, linked purchase documents, purchase-row
resolution, asset values, company/reference agreement, item, cost centre, missing values, gross versus
purchase amount, finance books; then, when `calculate_depreciation` is set, it **forces
`is_fully_depreciated = 0`** (`assets/doctype/asset/asset.py:122-137`).

`before_save` then derives two stored fields:

```text
total_asset_cost = net_purchase_amount + additional_asset_cost
status           = get_status()
```

(`assets/doctype/asset/asset.py:139-141`). Both are projections stored on the document, and `status`
is later rewritten by `db_set` from several unrelated places (§2.4).

`Item` must be a non-disabled fixed-asset, non-stock item (`assets/doctype/asset/asset.py:342-354`).
The cost centre must belong to the company and must not be a group; otherwise the company must define
`depreciation_cost_center` (`assets/doctype/asset/asset.py:355-383`). `net_purchase_amount` is
mandatory unless the asset is a Composite Asset, and when CWIP accounting is enabled for the category
a purchase document is required — with a Purchase Invoice additionally required to have `update_stock`
(`assets/doctype/asset/asset.py:454-497`).

### 2.2 Four asset types, three of which change the rules

`asset_type` is `Existing Asset`, `Composite Asset` or `Composite Component`, or blank for an ordinary
purchased asset (`assets/doctype/asset/asset.py:41-121`). The type silently switches validation and
posting:

| Type | Effect |
|---|---|
| blank (purchased) | full purchase-document validation and CWIP/fixed-asset posting |
| `Existing Asset` | skips purchase-row resolution and the available-for-use/purchase-date ordering check; may carry opening accumulated depreciation; a Purchase Invoice link is rejected (`assets/doctype/asset/asset.py:295-299`, `assets/doctype/asset/asset.py:337-341`, `assets/doctype/asset/asset.py:454-497`) |
| `Composite Asset` | may have zero `net_purchase_amount`, is `Work In Progress` while draft, **cannot be submitted without a submitted Asset Capitalization**, and always attempts capitalisation posting (`assets/doctype/asset/asset.py:249-254`, `assets/doctype/asset/asset.py:785-817`, `assets/doctype/asset/asset.py:859-864`) |
| `Composite Component` | skips the available-for-use requirement, posts no asset GL and is exempt from reverse GL on cancel (`assets/doctype/asset/asset.py:255-282`, `assets/doctype/asset/asset.py:384-396`) |

Opening values are handled asymmetrically: for any type other than `Existing Asset`, both
`opening_accumulated_depreciation` and `opening_number_of_booked_depreciations` are **silently reset to
zero** during finance-book validation rather than rejected (`assets/doctype/asset/asset.py:612-636`).

### 2.3 Submit and cancel ordering

`on_submit` runs: in-use date validation → create and submit an `Asset Movement` → `reload()` →
conditional GL → activate draft depreciation schedules → `set_status` → activity row
(`assets/doctype/asset/asset.py:255-269`).

`on_cancel` runs: cancellation validation → cancel movement entries → `reload()` → cancel depreciation
journals → cancel schedules → `set_status` → declare `GL Entry` and `Stock Ledger Entry` as ignored
links → reverse asset GL and clear `booked_fixed_asset` → activity row
(`assets/doctype/asset/asset.py:270-282`).

Three properties of that ordering matter:

1. **Submitting an asset creates and submits another document.** `make_asset_movement` inserts and
   submits an `Asset Movement` with purpose `Receipt`, dated from the purchase document's posting date
   and time when one exists (`assets/doctype/asset/asset.py:576-606`). A receipt custody fact is
   therefore a side effect of asset submission, not an independent authorised event.
2. **Cancellation cancels other people's journals.** `delete_depreciation_entries` cancels each
   depreciation `Journal Entry` found on the active schedule; for non-depreciating assets it cancels
   every manual depreciation journal it can find and then `db_set`s `value_after_depreciation` back to
   `net_purchase_amount − opening_accumulated_depreciation`
   (`assets/doctype/asset/asset.py:760-778`). Those manual entries are located by querying GL for
   debits to the depreciation expense account with `against_voucher = asset`
   (`assets/doctype/asset/asset.py:841-857`) — a *heuristic*, not a link.
3. **Cancellation is refused only by status.** `validate_cancellation` blocks `In Maintenance` and
   `Out of Order`, and otherwise requires status in `Submitted`, `Partially Depreciated` or
   `Fully Depreciated` (`assets/doctype/asset/asset.py:733-742`). Because status itself is a mutable
   projection, the cancellation gate is only as reliable as the last thing that wrote `status`.

### 2.4 Status is a mutable projection with many writers

`get_status` derives status from `docstatus`, `journal_entry_for_scrap`, and — for depreciating assets
— the **default finance book row's** `value_after_depreciation` against
`expected_value_after_useful_life` (`assets/doctype/asset/asset.py:785-817`). `set_status` writes it
with `db_set` (`assets/doctype/asset/asset.py:779-783`).

Writers include asset submit/cancel; the daily maintenance scan, which — **only for assets with
`maintenance_required = 1` and no `disposal_date`** — sets `Out of Order` when a pending `Asset Repair`
exists and `In Maintenance` when a maintenance task is due today
(`assets/doctype/asset/asset.py:1070-1082`); `Asset Repair.validate`, which sets `Out of Order`
unconditionally while its own status is `Pending` (`assets/doctype/asset_repair/asset_repair.py:177-187`,
doc 43 §4.1); and `Asset Capitalization`, which sets consumed assets to `Capitalized` and restores them on
cancellation (`assets/doctype/asset_capitalization/asset_capitalization.py:467-485`).

`get_default_finance_book_idx` resolves the default book from the asset field or the company default
(`assets/doctype/asset/asset.py:831-839`). If neither matches a finance-book row it returns `None`, and
`get_status` then indexes row `0` — so a multi-book asset whose default book is not in its own table
reports status from an arbitrary book.

> **Invariant A2 — asset state is derived, never stored authority.** Draft/active/impaired/in
> maintenance/disposed state is projected from typed authorised events (acquisition, depreciation
> posting, adjustment, custody, repair, disposal). No scheduled scan or unrelated document may write
> the state field directly, and multi-book valuation never collapses into one ambiguous row.

---

## 3. Acquisition: three paths to the fixed-asset account

### 3.1 Resolving the purchase row by matching numbers

For ordinary purchased assets, `set_purchase_doc_row_item` copies `net_purchase_amount` into
`purchase_amount` and then resolves the purchase child row
(`assets/doctype/asset/asset.py:295-313`). `get_linked_item` iterates the purchase document's items
and matches (`assets/doctype/asset/asset.py:314-325`):

```text
if asset_quantity > 1:
    match item.base_net_amount == net_purchase_amount and item.qty == asset_quantity
    else fall back to the first row with item.qty == asset_quantity
else:
    match item.base_net_rate == net_purchase_amount and item.qty == asset_quantity
```

The item code is not compared, and the fallback branch matches on quantity alone. Two rows with the
same quantity are therefore interchangeable, and the first is taken.

Quantity conservation is checked separately:

```text
existing = Σ Asset.asset_quantity for same item_code, same purchase doc, docstatus != 2, other names
purchased = Σ purchase-document item qty for the same item_code
reject when existing + this asset_quantity > purchased
```

(`assets/doctype/asset/asset.py:521-562`). The read and the insert are not serialised by any lock on
the purchase line, so two concurrent asset creations can each observe the same residual. The check also
aggregates by item code across the whole purchase document, so it cannot distinguish two lines of the
same item.

`validate_gross_and_purchase_amount` then insists `net_purchase_amount == purchase_amount` for
non-existing assets, explicitly to stop several assets' cost being booked against one asset
(`assets/doctype/asset/asset.py:564-575`). This is the only defence against cost aggregation, and it is
a field-equality check on values that `Asset Capitalization` later rewrites (§4.4).

`get_values_from_purchase_doc` is the UI path: it takes the **first** matching item and returns
`net_purchase_amount = valuation_rate × qty` (`assets/doctype/asset/asset.py:1190-1212`). Note that the
document-side resolution matches on `base_net_amount`/`base_net_rate` while this helper proposes
`valuation_rate × qty` — two different money bases for the same field.

### 3.2 Whether to post at all

`validate_make_gl_entry` decides whether the asset itself posts the capitalisation journal
(`assets/doctype/asset/asset.py:859-898`):

| Situation | Probe | Decision |
|---|---|---|
| Composite Asset | prior capitalisation GL | post unless the capitalisation already debited the target account, or no submitted capitalisation exists (`assets/doctype/asset/asset.py:984-1001`) |
| no purchase document | none | do not post |
| bought with invoice, fixed-asset account already debited on it | `GL Entry` exists | do not post |
| bought with invoice, CWIP already booked on it | `GL Entry` exists | post |
| bought with receipt, no CWIP account resolvable | account lookup | do not post |
| bought with receipt | CWIP `GL Entry` exists | post iff it exists |

`get_purchase_document` treats the Purchase Invoice as the purchase document only when it has
`update_stock`, otherwise the Purchase Receipt (`assets/doctype/asset/asset.py:900-906`). The invoice
branch has no explicit `return` when neither probe matches, so the method returns `None` and the caller
treats it as falsy.

This is the crux: **acquisition state is reconstructed by looking for GL rows**, so the correctness of
capitalisation depends on ledger archaeology rather than on a recorded acquisition stage.

### 3.3 The capitalisation journal

`make_gl_entries` first returns early when a submitted `Asset Capitalization` for this target asset has
already debited the target fixed-asset account (`assets/doctype/asset/asset.py:936-983`,
`assets/doctype/asset/asset.py:984-1001`, `assets/doctype/asset/asset.py:1054-1067`). Otherwise, when
the asset is a Composite Asset **or** has both a purchase document and a `purchase_amount`, and
`available_for_use_date <= today`, it posts exactly two rows dated on `available_for_use_date` and sets
`booked_fixed_asset = 1`:

| Account | Debit | Credit |
|---|---:|---:|
| Fixed asset | `purchase_amount` | |
| Capital work in progress | | `purchase_amount` |

Worked example — a 120,000.00 machine received on a Purchase Receipt that debited CWIP, available for
use the same day:

| Stage | Account | Debit | Credit |
|---|---|---:|---:|
| Purchase Receipt | Capital Work in Progress | 120,000.00 | |
| Purchase Receipt | Asset Received But Not Billed | | 120,000.00 |
| Asset submit | Fixed Asset — Machinery | **120,000.00** | |
| Asset submit | Capital Work in Progress | | **120,000.00** |

Net position: `Dr Fixed Asset 120,000.00 / Cr Asset Received But Not Billed 120,000.00`, with CWIP flat.
The journal balances because both legs use the same `purchase_amount` scalar — not because anything
reconciles it against what the receipt actually booked. If `purchase_amount` has since diverged from
the CWIP debit, the asset posts the *new* number against an account that holds the *old* one, and the
difference is left in CWIP with no exception raised.

### 3.4 Deferred capitalisation by scheduled job

When `available_for_use_date` is in the future, `make_gl_entries` posts nothing and
`booked_fixed_asset` stays `0`. The daily job `make_post_gl_entry` then scans, per asset category with
`enable_cwip_accounting`, for submitted assets with `booked_fixed_asset = 0` and
`available_for_use_date = nowdate()`, and calls `make_gl_entries` on each
(`assets/doctype/asset/asset.py:1085-1103`). It is registered in the daily long list
(`hooks.py:496-527`).

Two consequences follow directly from the equality filter:

1. an asset whose available-for-use date fell on a day the scheduler did not run is **never** picked
   up again, because the filter is `= nowdate()` rather than `<= nowdate()`; and
2. assets in categories **without** `enable_cwip_accounting` are skipped by this job entirely, even
   though `make_gl_entries` itself only requires a resolvable CWIP account.

There is no per-asset idempotency key on the posting; the guard is the mutable `booked_fixed_asset`
flag, which asset cancellation resets (`assets/doctype/asset/asset.py:270-282`).

> **Invariant A3 — capitalisation is an explicit, complete, idempotent event.** Recognition of an asset
> into service is one authorised event with its own identity, effective date and exact amount, derived
> from the acquisition cost actually accrued. It is retried safely by identity, never by a mutable
> boolean, and never skipped because a scheduled run was missed. Cost still held in construction in
> progress is reconciled continuously against the assets that will absorb it.

---

## 4. Asset Capitalization: stock, assets and services become one asset

### 4.1 What it accepts

`AssetCapitalization` is a `StockController` with three consumption tables and one target
(`assets/doctype/asset_capitalization/asset_capitalization.py:45-100`). Validation requires:

- the target item to be a fixed-asset item (`asset_capitalization.py:176-183`);
- the target asset, when named, to be a **Composite Asset**, of the target item, of this company, not
  `Scrapped`/`Sold`/`Capitalized`, and **still a draft** (`asset_capitalization.py:184-214`);
- consumed stock rows to be stock items with positive quantity (`asset_capitalization.py:215-227`);
- consumed asset rows to be submitted assets of this company, not the target, and not
  `Draft`/`Scrapped`/`Sold`/`Capitalized` (`asset_capitalization.py:228-260`);
- consumed service rows to be neither stock nor fixed-asset items, with positive quantity and rate
  (`asset_capitalization.py:261-279`); and
- at least one consumption row at submit (`asset_capitalization.py:280-287`).

### 4.2 How value is computed

`set_asset_values` reads each consumed asset's current value after depreciation and its value on the
posting date (`asset_capitalization.py:310-320`). `calculate_totals` then sums
(`asset_capitalization.py:339-364`):

```text
stock_items_total   = Σ stock_qty × valuation_rate
asset_items_total   = Σ asset_value
service_items_total = Σ qty × rate
total_value         = stock + asset + service
target_incoming_rate = total_value
```

Consumed stock valuation comes from the ordinary stock machinery: `get_warehouse_details` returns
previous-SLE quantity and `get_incoming_rate` with `raise_error_if_no_rate=False`
(`asset_capitalization.py:593-608`). A missing rate therefore yields **zero**, not an error, at
preview time.

### 4.3 Submit: stock, GL, repost, then rewrite the target

`on_submit` runs bundle creation → stock ledger → GL → repost future SLE/GLE → update target asset
(`asset_capitalization.py:109-115`). `update_stock_ledger` emits one negative SLE per consumed stock row
and reverses the list on cancellation (`asset_capitalization.py:365-380`).

The GL composer builds, in order (`assets/doctype/asset_capitalization/services/gl_composer.py:23-49`):

1. **consumed stock** — credit the inventory account (or the company default expense account when
   perpetual inventory is off) with `-1 × stock_value_difference` (`assets/doctype/asset_capitalization/services/gl_composer.py:50-81`);
2. **consumed assets** — for each non-`Composite Component` asset, depreciate it up to the posting date,
   reload, then append the standard disposal legs; then `db_set("disposal_date", …)` and set the
   consumed asset's status (`assets/doctype/asset_capitalization/services/gl_composer.py:82-116`);
3. **consumed services** — credit each service row's expense account with its amount
   (`assets/doctype/asset_capitalization/services/gl_composer.py:117-138`); and
4. **the target** — debit `total_value − composite_component_value` to the target account
   (`assets/doctype/asset_capitalization/services/gl_composer.py:139-160`).

The target account is CWIP when the target asset's category enables CWIP accounting, otherwise the
target fixed-asset account (`asset_capitalization.py:403-416`).

Worked example — build a composite asset from 5 units of stock at 400.00, one consumed asset with
book value 6,000.00 (cost 10,000.00, accumulated depreciation 4,000.00), and 1,500.00 of service:

```text
stock_items_total   = 5 × 400.00 = 2,000.00
asset_items_total   = 6,000.00
service_items_total = 1,500.00
total_value         = 9,500.00
```

| Leg | Account | Debit | Credit |
|---|---|---:|---:|
| consumed stock | Stores Inventory | | 2,000.00 |
| consumed asset | Accumulated Depreciation | 4,000.00 | |
| consumed asset | Fixed Asset — old | | 10,000.00 |
| consumed service | Installation Expense | | 1,500.00 |
| target | Fixed Asset — composite (or CWIP) | 9,500.00 | |
| **Total** | | **13,500.00** | **13,500.00** |

One SLE is written: `−5 units` from the source warehouse with `stock_value_difference = −2,000.00`, and
the inventory credit is exactly that magnitude — the same stock→GL bridge as every other stock document
(doc 03). The consumed asset contributes no SLE; assets are not stock.

`composite_component_value` deliberately excludes `Composite Component` assets from the target debit
(`asset_capitalization.py:417-424`), because those components were never separately capitalised.

### 4.4 The target rewrite

`update_target_asset` reads the target asset, adds (or on cancel subtracts) `total_value` from
`net_purchase_amount`, `purchase_amount` and `total_asset_cost`, and `db_set`s all three
(`asset_capitalization.py:425-450`). This is a read-modify-write against a document that is a *draft*
at submit time but a *register row* thereafter, with no lock, no per-capitalisation allocation row and
no idempotency key. Two concurrent capitalisations against the same target both read the same base.

On cancel, `restore_consumed_asset_items` reverses the disposal depreciation entry, resets the
depreciation schedule and clears `disposal_date` for each consumed asset
(`asset_capitalization.py:452-466`). Cancellation also declares `Asset`, `Asset Movement`, `GL Entry`,
`Stock Ledger Entry`, `Repost Item Valuation` and `Serial and Batch Bundle` as ignored links
(`asset_capitalization.py:116-130`), so the ordinary "successor exists" protection does not apply to
those.

`get_items_tagged_to_wip_composite_asset` builds the consumption proposal from submitted Purchase
Receipt Items tagged to the target asset, skipping stock rows already capitalised and matching fixed-asset
rows to assets by item code plus purchase receipt plus status
(`asset_capitalization.py:678-757`). The already-capitalised probe is a `db.exists` on the child table,
which is a preview filter and not a constraint.

> **Invariant A4 — additions to an asset are allocation facts.** Every subsequent capitalisation,
> improvement or landed cost is an immutable allocation row referencing the asset, the source
> (consumed inventory lot, consumed asset, or service claim), the amount and the effective date. Asset
> cost and net book value are projections over those rows plus depreciation facts. No document adds to
> an asset by reading and rewriting a scalar.

---

## 5. Categories, accounts and finance books

### 5.1 Account resolution and its gaps

`get_asset_category_account` reads one field from the `Asset Category Account` row matched on
`(parent = asset_category, company_name = company)`; when called without a category it derives category
and company from the asset (`assets/doctype/asset_category/asset_category.py:195-216`).
`get_asset_account` then applies the fallback chain: asset-scoped lookup → category lookup → company
default → throw (`assets/doctype/asset/asset.py:1139-1163`).

`Asset Category` validates that each account row's currency equals the company's default currency
(`asset_category.py:44-71`), that each field's account has the expected `account_type`
(`asset_category.py:72-99`), that companies are not duplicated across rows
(`asset_category.py:105-109`), that CWIP accounts exist somewhere when CWIP accounting is enabled
(`asset_category.py:110-128`), and — only for companies that already have active depreciating assets in
this category — that accumulated-depreciation and depreciation-expense accounts are resolvable
(`asset_category.py:129-193`).

The duplicate-company check compares the number of distinct `company_name` values to the number of
rows (`asset_category.py:105-109`); it therefore also fires when a row's company is blank in a way that
collapses the set, and the underlying table has no unique constraint. Category defaults for finance
books are validated only for positive counts and frequencies (`asset_category.py:36-43`).

### 5.2 Finance books are copied policy, not versioned policy

`set_missing_values` copies finance-book rows from the category when the asset has none
(`assets/doctype/asset/asset.py:397-407`), via `get_item_details`, which computes
`expected_value_after_useful_life = net_purchase_amount × salvage_value_percentage / 100` and defaults
`depreciation_start_date` to today when the category has none (`assets/doctype/asset/asset.py:1112-1137`).

After that copy the asset row is independent. `validate_finance_books` rejects duplicate books and
blank book names **only when there is more than one row**
(`assets/doctype/asset/asset.py:408-429`); a single row may therefore have no Finance Book at all, which
is exactly the state that makes `get_default_finance_book_idx` return `None` (§2.4).

`validate_asset_finance_books` rounds and bounds the salvage value, defaults
`depreciation_start_date` to the last day of the available-for-use month, and validates dates and
counts (`assets/doctype/asset/asset.py:612-636`, `assets/doctype/asset/asset.py:666-693`). Opening
values are validated only for `Existing Asset` (`assets/doctype/asset/asset.py:637-665`):

```text
depreciable = net_purchase_amount − expected_value_after_useful_life
reject opening_accumulated_depreciation > depreciable
require opening_number_of_booked_depreciations when opening depreciation exists
reject total_number_of_depreciations <= opening_number_of_booked_depreciations
```

`set_depr_rate_and_value_after_depreciation` returns immediately for a split child
(`assets/doctype/asset/asset.py:219-221`) — which is the only thing stopping a split's scaled book value
being overwritten — and otherwise computes
`value_after_depreciation = net_purchase_amount − opening_accumulated_depreciation +
additional_asset_cost` and `db_set`s it onto **every** finance-book row, the same value for all books, then
clears the table entirely when `calculate_depreciation` is off
(`assets/doctype/asset/asset.py:219-234`).

`set_total_booked_depreciations` recounts booked depreciations by scanning the active schedule for rows
with a journal entry and `db_set`s the count per book (`assets/doctype/asset/asset.py:694-704`).
`validate_expected_value_after_useful_life` compares the draft schedule's maximum accumulated
depreciation against the configured salvage value and *fills the field in* when it is blank
(`assets/doctype/asset/asset.py:705-732`).

Both of those run from `on_update`, together with schedule creation
(`assets/doctype/asset/asset.py:244-248`), so they fire on **every draft save and again at submit**.

They do **not** fire when a submitted asset is saved. Frappe routes a docstatus-1 save to
`_action = "update_after_submit"` and runs only `on_update_after_submit`
(`frappe/model/document.py:1447-1450`, `frappe/model/document.py:1889-1897`), which `Asset` does not define.
That makes the submitted-asset case sharper rather than milder: when `AssetRepair.update_asset_value` or
`set_split_asset_values` save a submitted asset with `flags.ignore_validate_update_after_submit`
(`assets/doctype/asset_repair/asset_repair.py:242-254`, `assets/doctype/asset/mapper.py:232-250`), the amount
fields are rewritten with **no validation and no derivation at all** — the only reason a schedule is
regenerated is the explicit `reschedule_depreciation` call those callers make.

### 5.3 Schedule regeneration is decided by field comparison

`create_asset_depreciation_schedule` skips split assets and non-depreciating assets, then for each book
either creates a new `Asset Depreciation Schedule` or evaluates whether the existing **draft** one must
be regenerated (`assets/doctype/asset/asset.py:143-168`). The decision compares net purchase amount,
opening accumulated depreciation and opening booked count
(`assets/doctype/asset/asset.py:180-188`), plus method, count, frequency, first schedule date and
salvage value (`assets/doctype/asset/asset.py:189-203`); regeneration also happens whenever no schedule
rows exist (`assets/doctype/asset/asset.py:204-218`).

`has_depreciation_settings_changed` returns `True` immediately when the book's method is not `Manual`
(`assets/doctype/asset/asset.py:189-203`), so for every automatic method the comparison of individual
settings is unreachable and the draft schedule is regenerated on each qualifying save. Manual schedules
are the only ones actually diffed — which is the opposite of what a reader would expect, and the reason
a hand-edited automatic schedule cannot survive a save. Doc 42 traces what regeneration then computes.

### 5.4 Depreciation rate helpers live on the asset

`get_depreciation_rate` dispatches on method and returns `None` for Straight Line and Manual
(`assets/doctype/asset/asset.py:1003-1012`). Double declining uses
`200 / ((total_number_of_depreciations × frequency_of_depreciation) / 12)`
(`assets/doctype/asset/asset.py:1013-1025`). Written-down value solves for the geometric rate
(`assets/doctype/asset/asset.py:1026-1052`):

```text
value   = expected_value_after_useful_life / current_asset_value
pending = total_number_of_depreciations − opening_booked − total_booked
years   = (pending × frequency_of_depreciation + increase_in_asset_life) / 12
rate    = 100 × (1 − value ** (1 / years))
```

Both are rounded to System Settings `float_precision`, defaulting to **2**
(`assets/doctype/asset/asset.py:1003-1012`). The written-down formula divides by
`current_asset_value` and raises to `1/years`, so a zero current value or zero pending duration is an
arithmetic error rather than a validation message. Rate is stored as a percent on the finance-book row
and is recomputed on validate, which means a stored schedule and a recomputed rate can disagree.

> **Invariant A5 — depreciation policy is an approved revision.** Method, useful life, frequency,
> salvage value, proration rule, shift policy and effective interval form an immutable policy revision
> per asset and book. An asset names revisions; it does not hold editable copies. Rate is either part
> of the revision or a pure function of it at full precision, never a rounded field that can disagree
> with the schedule it produced.

---

## 6. Locations and the activity trail

`Location` is a nested set keyed on `parent_location` (`assets/doctype/location/location.py:15-44`).
Saving recomputes the GeoJSON area and, for existing records with a parent, pushes the difference up the
ancestor chain: each ancestor's feature list is rewritten and its area is `db_set` to
`area + area_difference` (`assets/doctype/location/location.py:55-109`). Deletion subtracts the child's
area from every ancestor (`assets/doctype/location/location.py:110-120`).

That is incremental aggregate maintenance by direct write, on a tree, with no lock: two concurrent child
saves under one ancestor can both read the same area and lose an update. `area_difference` is not even a
declared field on the document — it is set as an attribute during validation
(`assets/doctype/location/location.py:55-61`) — so it exists only for the duration of the save.

`Asset Activity` has no controller logic; `add_asset_activity` inserts a row with the session user and
`now_datetime()`, using `ignore_permissions=True` and `ignore_links=True`
(`assets/doctype/asset_activity/asset_activity.py:27-36`). Its `subject` is a translated, formatted
sentence built at each call site — for example asset submitted/cancelled/created/deleted
(`assets/doctype/asset/asset.py:255-294`) and capitalisation status changes
(`assets/doctype/asset_capitalization/asset_capitalization.py:467-485`).

An audit trail whose payload is a translated sentence cannot be queried by meaning, cannot be
reconciled against the events it claims to describe, and changes with the user's language. It is a
useful human log and not an event stream.

> **Invariant A6 — place, custody and audit are typed facts.** Location is an immutable-revision place
> hierarchy whose derived measures are projections, not incrementally patched scalars. Every asset
> lifecycle record is a typed event with stable event code, actor, timestamp and references; human-readable
> text is rendered from the event, never stored as the event's identity.

---

## 7. Evidence versus projection

| Representation | Classification |
|---|---|
| submitted Purchase Receipt / Purchase Invoice and their GL rows | acquisition cost evidence |
| submitted `Asset` document | acquisition authorisation, mixed with register state |
| `Asset.purchase_receipt_item` / `purchase_invoice_item` | link resolved by amount/quantity matching — inference, not evidence |
| `Asset.net_purchase_amount`, `purchase_amount`, `total_asset_cost` | mutable scalars rewritten by capitalisation |
| `Asset.booked_fixed_asset` | mutable idempotency proxy for the capitalisation journal |
| capitalisation `GL Entry` pair | accounting evidence of recognition |
| `Asset.status` | mutable projection with many writers |
| `Asset Finance Book` rows | copied editable policy with per-row mutable counters |
| `Asset Finance Book.value_after_depreciation` | mutable projection, written identically to all books |
| `Asset Capitalization` + children | consumption/valuation command evidence |
| Asset Capitalization SLE and GL rows | stock and accounting evidence |
| target asset amount rewrite | unlocked read-modify-write projection |
| `Asset Movement` created by asset submit | custody evidence produced as a side effect |
| `Asset Activity` | translated human log, not an event stream |
| `Location.area` and ancestor areas | incrementally patched aggregates |

The strongest audit path today is:

```text
Purchase Receipt/Invoice line → CWIP or fixed-asset GL rows
  → Asset document (linked by matched amount/quantity)
  → conditional capitalisation GL pair (or deferred daily job)
  → Asset Capitalization consumption SLE/GL → target amount rewrite
```

Every arrow except the GL rows themselves is either inferred or mutable.

> **Invariant A7 — evidence before asset projection.** Acquisition, capitalisation, addition, custody
> and disposal facts commit atomically with their accounting evidence and an outbox event; asset cost,
> net book value, status, book counters and registers are rebuilt from those facts. Replaying the event
> log reproduces the same register exactly.

---

## 8. Target backend and database model

These tables extend `docs/design/FINAL-SCHEMA.md` and reuse its existing `voucher`, `gl_entry`,
`stock_move` and projection infrastructure. No parallel asset ledger is introduced. Money is
`numeric(19,4)`; quantities and rates are `numeric(21,9)`; every table carries `company_id`, company-scoped
keys, `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`, and stable lower-case enum codes.

### 8.1 Identity and policy

| Target table | Key columns and constraints |
|---|---|
| `asset` | stable identity, item, category, acquisition kind, custody defaults; **no quantity column** — one asset per identified unit; `state` is a projection, not a column; unique `(company_id, asset_no)` |
| `asset_category` | account map owner and default policy identity; unique `(company_id, code)` |
| `asset_category_account` | one row per `(company_id, asset_category_id, target_company_id)`; account-type and currency checks as constraints |
| `asset_policy_revision` | per asset and finance book: method, life, frequency, salvage, proration, shift policy, effective range, `state`, `supersedes_revision_id`; unique `(company_id, asset_id, finance_book_id, revision_no)`; approved ranges non-overlapping by exclusion constraint |
| `asset_component` | composite structure: parent asset, component asset or item, immutable |

### 8.2 Acquisition and additions

| Target table | Key columns and constraints |
|---|---|
| `asset_acquisition` | asset, acquisition kind (`purchase`, `existing_opening`, `capitalisation`, `split`, `transfer_in`), source document line, currency, amount, acquired_at, `command_receipt_id`; unique `(company_id, asset_id)` per original acquisition |
| `asset_source_allocation` | exact allocation of a purchase line, consumed lot, consumed asset or service claim to one asset; unique `(company_id, source_type, source_line_id, asset_id, ordinal)`; deferred trigger caps Σ allocated quantity/amount at the source residual under a source-line lock |
| `asset_cost_event` | append-only cost movement: acquisition, addition, improvement, landed cost, repair capitalisation, adjustment; amount, effective_at, `voucher_id`, `reverses_event_id` |
| `asset_recognition` | in-service recognition: asset, effective date, amount recognised out of construction-in-progress, `voucher_id`; unique `(company_id, asset_id, recognition_no)` and at most one unreversed current recognition |
| `asset_capitalisation` | command header for composite build; unique `(company_id, command_receipt_id)`; children reference consumed stock moves, consumed assets and service claims with child ordinals |

`asset_recognition` replaces `booked_fixed_asset`. The recognition service selects **all** assets whose
effective date has arrived and which have no unreversed recognition, so a missed run self-heals; the
unique key makes a double run a no-op. Construction-in-progress residual is a view over
`asset_cost_event` minus recognised amounts, reconciled continuously rather than by a nightly repair.

### 8.3 Place, custody metadata and events

| Target table | Purpose |
|---|---|
| `asset_location` / `asset_location_geometry_revision` | place hierarchy with `parent_id` + recursive CTE; measured area is a projection recomputed from immutable geometry revisions |
| `asset_lifecycle_event` | typed lifecycle detail keyed 1:1 to a row in the shared `domain_event` stream (§10): stable `event_code`, references, reason; text is rendered, never stored as identity |
| `asset_state_projection`, `asset_custody_projection`, `asset_book_value_projection` | current state, location/custodian, and per-book cost/accumulated depreciation/net book value; rebuilt from facts with a projector checkpoint |

### 8.4 Write ordering for acquisition

```text
1  claim command idempotency (company, command_kind, idempotency_key)
2  guard company, period, asset lifecycle
3  lock source purchase line / consumed stock streams / consumed asset owners in sorted order
4  validate residual quantity and amount against existing allocations
5  insert asset identity (first acquisition only) and immutable acquisition row
6  insert asset_source_allocation rows and asset_cost_event rows
7  insert consumed stock_move rows, then recompute valuation projections
8  insert voucher + gl_entry from allocated amounts and stock value deltas
9  insert asset_event and outbox rows in the same transaction
10 commit; projectors rebuild register, CIP residual and dashboards
```

Recognition is its own command: lock the asset, verify unrecognised cost, insert `asset_recognition`
plus its balanced voucher, emit an event. Reversal appends reversing cost events, a reversing voucher and
reversing allocations in dependency order — consumed-asset restoration and depreciation reversal before
the acquisition itself — and never deletes evidence.

> **Invariant A8 — relational asset integrity.** Unique, foreign-key, check and exclusion constraints
> enforce one current acquisition, one current recognition, bounded source allocation, non-overlapping
> approved policy revisions, per-book uniqueness and typed account roles. Application helpers improve
> messages; they are not the only barrier.

---

## 9. Defects and races

1. **Purchase-row identity by amount matching.** Item code is not compared, and the multi-quantity
   branch falls back to quantity-only matching (`assets/doctype/asset/asset.py:314-325`).
2. **Two money bases for one field.** Document-side matching uses `base_net_amount`/`base_net_rate`
   while the UI helper proposes `valuation_rate × qty`
   (`assets/doctype/asset/asset.py:314-325`, `assets/doctype/asset/asset.py:1190-1212`).
3. **Unlocked asset-quantity ceiling.** Existing quantity is summed and compared before insert with no
   lock on the purchase line, and aggregation is by item code across the document
   (`assets/doctype/asset/asset.py:521-562`).
4. **Capitalisation decided by GL archaeology.** Four `frappe.db.exists` probes decide whether to post,
   and the invoice branch can fall through to an implicit `None`
   (`assets/doctype/asset/asset.py:859-898`).
5. **Deferred capitalisation can be missed permanently.** The daily job filters
   `available_for_use_date = nowdate()` and only scans CWIP-enabled categories
   (`assets/doctype/asset/asset.py:1085-1103`).
6. **Capitalisation amount is not reconciled.** Both legs use the same `purchase_amount` scalar, so a
   divergence from the CWIP debit silently strands value in CWIP
   (`assets/doctype/asset/asset.py:936-983`).
7. **Submitted-asset amounts are rewritten.** `Asset Capitalization` performs read-modify-write on the
   target's three amount fields with no lock or allocation row
   (`assets/doctype/asset_capitalization/asset_capitalization.py:425-450`).
8. **Zero valuation is silent.** Consumed stock rate falls back to zero because
   `raise_error_if_no_rate=False` (`assets/doctype/asset_capitalization/asset_capitalization.py:593-608`).
9. **Status has many writers and an ambiguous default book.** A missing default finance-book match
   falls back to row 0 (`assets/doctype/asset/asset.py:785-839`,
   `assets/doctype/asset/asset.py:1070-1082`).
10. **Manual-only schedule diffing.** Non-`Manual` methods return "changed" unconditionally, so drafts
    regenerate on every qualifying save (`assets/doctype/asset/asset.py:189-203`).
11. **Same value written to every book.** `value_after_depreciation` is `db_set` identically across all
    finance books (`assets/doctype/asset/asset.py:219-234`).
12. **Manual depreciation entries are found heuristically.** Cancellation locates them by account plus
    `against_voucher` plus non-zero debit (`assets/doctype/asset/asset.py:841-857`).
13. **Single finance-book row may have no book.** Duplicate/blank validation is skipped when there is
    exactly one row (`assets/doctype/asset/asset.py:408-429`).
14. **Rate rounded to two decimals by default.** Both derived rates round to System Settings
    `float_precision` (`assets/doctype/asset/asset.py:1003-1052`).
15. **Location aggregates patched in place.** Ancestor areas are incremented/decremented by direct
    write with no lock (`assets/doctype/location/location.py:82-120`).
16. **Opening values silently zeroed.** Non-`Existing Asset` opening depreciation is reset rather than
    rejected (`assets/doctype/asset/asset.py:612-636`).
17. **Activity subject is translated text.** The audit payload is a localised sentence
    (`assets/doctype/asset_activity/asset_activity.py:27-36`).
18. **Capitalisation values a consumed asset before depreciating it.** `set_asset_values` and
    `calculate_totals` fix `asset_value` and `total_value` at validate
    (`assets/doctype/asset_capitalization/asset_capitalization.py:310-320`,
    `assets/doctype/asset_capitalization/asset_capitalization.py:339-364`), but at submit the GL composer
    depreciates the consumed asset to the posting date and reloads **before** building its disposal legs
    (`assets/doctype/asset_capitalization/services/gl_composer.py:82-116`), while
    `get_gl_entries_on_asset_disposal` computes `profit_amount = selling_amount − value_after_depreciation`
    against the freshly reduced book value (`assets/doctype/asset/depreciation.py:639-695`). If a period
    falls due between save and submit, the build books a phantom gain on the consumed asset and debits the
    target with the pre-depreciation value.

No deterministic owner lock or unique constraint was found around: purchase-line residual → asset
insert; capitalisation total → target amount rewrite; `booked_fixed_asset` read → capitalisation
journal; or location area read → ancestor update.

> **Invariant A9 — serializable asset decisions.** Acquisition against a purchase line, capitalisation
> into a target asset, recognition, addition and custody assignment are bounded writes validated and
> inserted under deterministic locks with idempotency keys and database uniqueness. Individually valid
> concurrent commands may not jointly exceed a source residual or double-recognise an asset.

---

## 10. Adopt / Change / Reject

| ERPNext mechanism | Decision | Ours |
|---|---|---|
| Asset as a distinct submittable object per unit | **Adopt** | immutable asset identity created by an authorised acquisition |
| `asset_quantity > 1` on one asset row | **Change** | one asset per identified unit, or an explicit asset group with member rows |
| Purchase-row link by amount/quantity matching | **Reject** | explicit `asset_source_allocation` to the exact purchase line |
| Quantity ceiling against purchase document | **Adopt rule** | same bound, enforced under a source-line lock with a residual constraint |
| `net_purchase_amount == purchase_amount` guard | **Adopt intent** | cost is Σ allocations; no scalar to keep in agreement |
| Four asset types switching validation | **Change** | one asset with typed acquisition kind and explicit composite structure |
| CWIP → fixed asset recognition | **Adopt** | explicit `asset_recognition` event with its own voucher |
| `validate_make_gl_entry` GL probes | **Reject** | recognition derived from recorded acquisition/cost events |
| `booked_fixed_asset` flag | **Reject** | unique recognition row is the idempotency key |
| Daily `make_post_gl_entry` with `= nowdate()` | **Change** | self-healing `<=` selection, category-independent, retry-safe |
| Asset Capitalization consuming stock/assets/services | **Adopt** | one capitalisation command with typed children and exact allocations |
| Consumed stock valued at zero when no rate | **Change** | missing valuation is an error or an explicit authorised policy |
| Target amount rewrite by `db_set` | **Reject** | append cost events; cost is a projection |
| Composite component exclusion from target debit | **Adopt rule** | typed component role prevents double capitalisation structurally |
| Asset submit creating and submitting an Asset Movement | **Change** | custody is its own command, idempotent, possibly in the same transaction |
| Category account map per company | **Adopt** | same shape, with unique keys and typed account-role constraints |
| Company default account fallback | **Adopt** | explicit ordered resolution recorded on the posted event |
| Finance-book rows copied from category | **Change** | asset names an approved `asset_policy_revision` |
| Mutable per-book counters | **Reject** | booked counts are projections over depreciation facts |
| Derived rate rounded to 2 decimals | **Change** | full-precision rate inside the policy revision |
| Manual-only schedule diffing | **Reject** | regeneration is an explicit versioned action (doc 42) |
| Location nested set | **Change** | `parent_id` + recursive CTE, consistent with the hierarchy decision |
| Incrementally patched location area | **Reject** | recomputed projection from immutable geometry |
| Asset Activity translated log | **Change** | typed `asset_event` with stable codes; text rendered on read |
| Cancelling an asset to unwind depreciation journals | **Reject** | reversal events in dependency order, evidence retained |

Invariants introduced here are **A1–A9**: asset identity conservation; derived state; explicit
idempotent capitalisation; additions as allocation facts; approved policy revisions; typed place/custody/audit;
evidence before projection; relational integrity; and serializable asset decisions. Doc 42 continues at
**A10** with the depreciation engine.

---

Cross-references: [doc 01](01-gl-posting-engine.md) (posting and reversal),
[doc 02](02-stock-ledger-and-valuation.md) and [doc 03](03-stock-gl-bridge.md) (consumed stock valuation
and the stock→GL bridge), [doc 09](09-lifecycle-reversals-deletions.md) (submit/cancel/ignored links),
[doc 20](20-naming-identity-and-audit-trail.md) (identity and audit), [doc 22](22-background-jobs-scheduling-and-locking.md)
(scheduler and locking), [doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (accounts and
dimensions), [doc 27](27-remaining-stock-documents.md) (`Item Standard Cost` and stock documents),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (command/lock/idempotency/outbox
contract reused here) and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next:
[doc 42](42-depreciation-engine-schedules-shifts-and-adjustments.md).
