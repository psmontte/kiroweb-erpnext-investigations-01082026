# 6. Lifecycle, fulfilment, returns and cancellation

How a document moves through states, how "how much is still to deliver/bill" is computed, and what
happens on cancel and amend.

Primary files:
- `controllers/status_updater.py` — status map + roll-up engine
- `controllers/sales_and_purchase_return.py` — returns
- `frappe/model/document.py` — docstatus transitions, amendment, locking
- `controllers/accounts_controller.py`, `controllers/stock_controller.py` — cancel ordering
- `accounts/services/billing_validation.py` — the second over-billing gate

---

## 6.1 Status is declarative (`status_map`, status_updater.py:21-180)

Evaluation (`get_status`, :219-264): the doctype's list is **copied and reversed**, then scanned; the
first match wins — so **later entries in the literal list have higher priority**. A condition is
`None` (unconditional fallback, always the first `Draft` entry), an `"eval:<expr>"` string evaluated by
`frappe.safe_eval` with `{self, getdate, nowdate, get_value}`, or a **method name** on the controller.
`get_status()` returns a **dict** so subclasses can piggyback extra fields for a single bulk `db_set`.

Sales Order (highest priority last):
```
Draft                | None
To Deliver and Bill  | per_delivered < 100 and per_billed < 100 and docstatus == 1
To Bill              | (per_delivered >= 100 or skip_delivery_note) and per_billed < 100 and docstatus == 1
To Deliver           | per_delivered < 100 and per_billed >= 100 and docstatus == 1 and not skip_delivery_note
To Pay               | advance_payment_status == 'Requested' and docstatus == 1
Completed            | (per_delivered >= 100 or skip_delivery_note) and per_billed >= 100 and docstatus == 1
Cancelled            | docstatus == 2
Closed               | status == 'Closed' and docstatus != 2
On Hold              | status == 'On Hold'
```
Purchase Order is the mirror but uses `per_billed == 100` (exact) for `To Receive` and `Completed`.
Delivery Note uses `per_billed == 100` (exact) for `Completed`, plus `Return Issued`
(`per_returned == 100`) and `Return` (`is_return == 1 and per_billed == 0`). Purchase Receipt adds a
zero-value clause: `Completed` also when `grand_total == 0 and per_returned != 100 and is_return == 0`.
Material Request has eight states keyed on `material_request_type`.

> Two traps to avoid copying: (a) `Closed`/`On Hold`/`Stopped` are **self-referential** — they are
> re-derived from the persisted `status` column, so `set_status()` can never leave them unless the
> status is explicitly reset; (b) mixing `== 100` and `>= 100` across doctypes means over-billing beyond
> 100% can leave a Delivery Note in *Partially Billed* forever.

`set_status` (:198-217): a new document with `amended_from` is forced to `Draft`; otherwise the derived
status is written with `db_set` (bypassing validation) and a timeline comment is added — except for the
noisy set `("Cancelled","Partially Ordered","Ordered","Issued","Transferred")`.

> **Ours** Status is a **pure function** `derive_status(doc) -> status`, computed on read (or in a
> generated column / view), never stored as an input to itself. Lifecycle states that a *user sets*
> (`on_hold`, `closed`) are separate boolean/enum columns, so the derived status can always be
> recomputed from facts.

## 6.2 The roll-up engine

`update_prevdoc_status` (:194) = `update_qty()` then `validate_qty()` — **roll up first, validate
after**, so tolerance is checked against the freshly aggregated totals.

`update_qty` (:533) injects the current-document condition, which is the whole trick (the document's own
`docstatus` is not yet committed when the hook runs):
```
docstatus == 1 (submit): args["cond"] = " or parent = <self.name>"      # force-include
docstatus == 2 (cancel): args["cond"] = " and parent != <self.name>"    # force-exclude
```

`_update_children` (:550-603) per child row:
```sql
-- primary source
SELECT coalesce(sum({source_field}),0) FROM `tab{source_dt}`
WHERE `{join_field}` = :detail_id AND (docstatus = 1 {cond}) {extra_cond}
-- optional second source (e.g. a stock-updating Sales Invoice also counts as a delivery)
SELECT coalesce((SELECT sum({second_source_field}) FROM `tab{second_source_dt}`
                 WHERE `{second_join_field}` = :detail_id AND docstatus = 1 {second_source_extra_cond}),0)
-- write back
UPDATE `tab{target_dt}` SET {target_field} = <sum1 + sum2> {,modified,modified_by} WHERE name = :detail_id
```
`source_field` may be an SQL expression (`"-1 * qty"`, `"-1 * stock_qty"`) interpolated straight into
the statement.

> **Invariant** This is **absolute recomputation, never a delta** — so re-running
> `update_prevdoc_status` is idempotent. That property is what makes cancel/repost/amend safe.

### The percentage formula (`_calculate_target_parent_percentage`, :605-630)

```python
sum_ref = Σ abs(row[target_ref_field])
pct = round(Σ min(abs(row[target_field]), abs(row[ref_field])) / sum_ref * 100, 6) if sum_ref else 0
```
Properties, all deliberate:
- **row-wise capping via `min()`** — over-delivery on one line cannot compensate a short delivery on
  another, so the parent percentage never exceeds 100 from this path;
- `abs()` so return documents (negative qty) roll up correctly;
- rounded to 6 decimals; `sum_ref == 0 ⇒ 0`.

`_update_percent_field` (:658-683) loads the target with `frappe.get_lazy_doc`, applies the new
percentage **before** calling `target.get_status()` (so the status rules see fresh numbers), merges the
returned dict and writes everything in one `db_set`.

`_determine_status` (:633): `< 0.001 → "Not <keyword>"`, `>= 99.999999 → "Fully <keyword>"`, else
`"Partly <keyword>"` — this drives `delivery_status` / `billing_status`.

`update_billing_status_for_zero_amount_refdoc` (:694-743): when `base_net_total == 0`, billing % is
computed on **quantity** instead: `per_billed = safe_div(min(ref_doc_qty, billed_qty), ref_doc_qty)*100`.

### Every `per_*` and where it comes from

| Target field | Config | Source | Parent percentage |
|---|---|---|---|
| `Sales Order Item.delivered_qty` | delivery_note.py:157 | Σ `DN Item.qty` on `so_detail` **+** Σ `SI Item.qty` on `so_detail` where the SI has `update_stock=1` | `SO.per_delivered`, `delivery_status` |
| `Sales Invoice Item.delivered_qty` | delivery_note.py:194 | Σ `DN Item.qty` on `si_detail`, `no_allowance: 1` | — |
| `Pick List Item.delivered_qty` | delivery_note.py:206 | Σ `DN Item.stock_qty` on `pick_list_item` | `Pick List.per_delivered` |
| `Sales Order Item.returned_qty` | delivery_note.py:222 (only if `is_return`) | Σ `-1*qty` from return DNs + return SIs with `update_stock=1` | — |
| `Delivery Note Item.returned_qty` | delivery_note.py:240 | Σ `-1*stock_qty` on `dn_detail` | `DN.per_returned` on `return_against` |
| `Quotation Item.ordered_qty` | sales_order.py:187 | Σ `SO Item.stock_qty` on `quotation_item` | — (Quotation uses methods) |
| `Material Request Item.ordered_qty` | purchase_order.py:167 | Σ `PO Item.stock_qty` (or `fg_item_qty` when subcontracted) | `MR.per_ordered`; allowance overridden to `Buying Settings.over_order_allowance` |
| `Purchase Order Item.received_qty` | purchase_receipt.py:153 | Σ `PR Item.received_qty` **+** Σ `PI Item.received_qty` where the PI has `update_stock=1` | `PO.per_received` |
| `Material Request Item.received_qty` | purchase_receipt.py:177 | Σ `PR Item.stock_qty`, **`validate_qty: False`** | `MR.per_received` |
| `Purchase Invoice Item.received_qty` | purchase_receipt.py:189 | Σ `PR Item.received_qty` | `PI.per_received` |
| `Purchase Receipt Item.returned_qty` | purchase_receipt.py:229 | Σ `-1*received_stock_qty` | `PR.per_returned` |
| `Sales Order Item.billed_amt` | sales_invoice.py:260 | Σ `SI Item.amount` on `so_detail` | `SO.per_billed`, `billing_status` |
| `Purchase Order Item.billed_amt` | purchase_invoice.py:224 | Σ `PI Item.amount` on `po_detail` | `PO.per_billed` |

`Delivery Note.per_billed` / `Purchase Receipt.per_billed` are special
(`StockController.update_billing_percentage`, stock_controller.py:308-329): for a DN with partial
returns the reference becomes the SQL expression
`{"SUB": ["amount", {"MUL": ["returned_qty","rate"]}]}` — **billing is measured against amount net of
returned value**, but only while `total_returned < total_amount`. The per-DN distribution of SO-level
billing is `delivery_note/services/billing_status.py:58-134`: invoices billed directly against the SO
are spread over DN rows ordered `posting_date, posting_time, name`, capped at each row's `amount`.

Drop-ship SOs bypass the engine entirely (`sales_order/services/status.py:47`), recomputing
`delivered_qty` from `PO Item.received_qty`.

## 6.3 Tolerances

`validate_qty` (:266-384) per config block:
1. Reset the allowance caches (so blocks do not leak values).
2. Sign checks over all children: `qty < 0` on a non-return, `qty > 0` on a return, `rate < 0` unless
   `Selling/Buying Settings.allow_negative_rates_for_items` → throw.
3. `fetch_items_with_pending_qty` (:386-417) selects only rows where
   `target_ref_field < target_field AND docstatus = 1`; when the ref field name contains `"qty"` it
   **joins `Item` and requires `is_stock_item = 1`** — so non-stock rows are never qty-checked.
4. `no_allowance` config → throw when `target_field − target_ref_field > 0.01`.
5. Else `check_overflow_with_allowance` (:419-466):
   ```
   overflow_percent = (target_field − target_ref_field) / target_ref_field * 100
   if overflow_percent − allowance > 0.01:
       max_allowed = flt(target_ref_field * (100 + allowance)/100)
       reduce_by   = target_field − max_allowed
       role in frappe.get_roles() ? warn_about_bypassing_with_role : limits_crossed_error
   ```

| Allowance | Global source | Item override | Bypass role |
|---|---|---|---|
| over receipt/delivery (qty) | `Stock Settings.over_delivery_receipt_allowance` | `Item.over_delivery_receipt_allowance` | `Stock Settings.role_allowed_to_over_deliver_receive` |
| over order (qty, MR targets) | `Buying Settings.over_order_allowance` | `Item.over_order_allowance` | as above |
| over billing (amount) | `Accounts Settings.over_billing_allowance` | `Item.over_billing_allowance` | `Accounts Settings.role_allowed_to_over_bill` |
| over picking | `Stock Settings.over_picking_allowance` | — | — |

`get_allowance_for` (:746+) memoises per item and **prefers the item value when truthy**, else the
singles value.

`limits_crossed_error` (:468-514) silently returns (no error at all) for **internal customer** amount
overflows on SI/DN and **internal supplier** amount overflows on PI/PR.

A second, independent over-billing gate exists: `accounts/services/billing_validation.py:16-62`
`validate_multiple_billing`: `max_allowed_amt = flt(ref_amt * (100 + allowance)/100)`, throwing when
`overbill_amt > 1/10**precision`, sign-flipping when both are negative (credit notes), skipped for PI
when `Buying Settings.bill_for_rejected_quantity_in_purchase_invoice`.
And a third at payment time: `payment_entry.py:2613` refuses SO/PO references where
`flt(doc.per_billed, 2) >= 100 + over_billing_allowance`.

> **Ours** One `fulfilment` module. `rollup(target_line) -> {ordered, delivered, received, billed,
> returned}` as **queries** over successor lines, with `per_*` as generated/derived values using the
> same `Σ min(achieved, ordered) / Σ ordered` formula. One tolerance resolution function
> (`allowance(item, kind) -> pct`) and one enforcement point. Over-limit is either an error or an
> explicitly recorded, attributed override — never a silent return based on `is_internal_customer`.

## 6.4 Submit / cancel (frappe `model/document.py`)

- `submit()` → `_submit()` (:1763): `docstatus = 1` then `save()`. `cancel()` → `_cancel()` (:1768):
  `docstatus = 2` then `save()` — **cancel goes through the full save path** (validate → update →
  post-save hooks).
- `check_docstatus_transition` (:1410-1470) is the only gatekeeper. Allowed: 0→0 (`save`), 0→1
  (`submit`, requires `is_submittable` + submit perm), 1→1 (`update_after_submit`, submit perm), 1→2
  (`cancel`, cancel perm). Forbidden: 0→2 (`DocstatusTransitionError`), 1→0, and **anything from 2**
  ("Cannot edit cancelled document").
- `validate_update_after_submit` (:1477): only fields flagged `allow_on_submit` may change after submit;
  `flags.ignore_validate_update_after_submit` bypasses it — used liberally by ERPNext when patching
  submitted documents.
- `run_post_save_methods` (:1881): `save`→`on_update`; `submit`→`on_update` then `on_submit`;
  `cancel`→`on_cancel` **then `check_no_back_links_exist()`**; `update_after_submit`→
  `on_update_after_submit`. Then cache clear, notify, global search, version, `on_change`.
- `check_no_back_links_exist` (:2016): unless `flags.ignore_links`, runs `check_if_doc_is_linked` +
  `check_if_doc_is_dynamically_linked`. **This is what refuses cancellation when a submitted successor
  links to the document** — and `self.ignore_linked_doctypes` (honoured in `model/delete_doc.py:310`)
  whitelists doctypes to skip, set *inside* `on_cancel`, i.e. immediately before the check runs.

### Cancel ordering is load-bearing

`AccountsController.on_cancel` (:1109-1136):
```
remove_from_bank_transaction
if SI/PI/PE/JE:
    cancel_system_generated_credit_debit_notes()      # :1091 cancels system Credit/Debit Note JEs
    cancel_exchange_gain_loss_journal()               # BEFORE unlinking
    cancel_common_party_journal()
    if Accounts Settings.unlink_payment_on_cancellation_of_invoice: unlink_ref_doc_from_payment_entries()
elif SO/PO:
    if unlink_advance_payment_on_cancelation_of_order: unlink_ref_doc_from_payment_entries()
    if SO: unlink_ref_doc_from_po()                   # :1138 nulls sales_order/sales_order_item on PO Item
```

`DeliveryNote.on_cancel` (delivery_note.py:515-545) — note the comment in the source explaining the
order: **stock must follow prevdoc status** because Bin reserved qty depends on SO `delivered_qty`:
```
super().on_cancel()
check_sales_order_on_hold_or_close("against_sales_order")
check_next_docstatus()                 # throws if a submitted SI or Installation Note references it
update_prevdoc_status() ; update_billing_status()
update stock reservation entries
update_stock_ledger()                  # ← only now
cancel packing slips ; pick-list status
make_gl_entries_on_cancel() ; repost_future_sle_and_gle()
ignore_linked_doctypes = ("GL Entry","Stock Ledger Entry","Repost Item Valuation","Serial and Batch Bundle")
delete_auto_created_batches()
```
`SalesOrder.on_cancel` (sales_order.py:473) sets `ignore_linked_doctypes` **first**, refuses if
`status == "Closed"` ("Unclose to cancel"), and calls `check_nextdoc_docstatus()`.

Every submittable doctype carries an `ignore_linked_doctypes` tuple; typical members: `GL Entry`,
`Stock Ledger Entry`, `Payment Ledger Entry`, `Advance Payment Ledger Entry`, `Repost Item Valuation`,
`Serial and Batch Bundle`, `Unreconcile Payment`.

`on_trash` (accounts_controller.py:422+) removes repost/unreconcile references, serial-batch bundles,
and — if `Accounts Settings.delete_linked_ledger_entries` — **hard-deletes** GL, PLE, SLE and Advance
PLE rows for the voucher.

> **Ours** Cancellation is an explicit ordered pipeline per document type, declared as data:
> ```
> CANCEL_STEPS = [detach_successors, reverse_settlements, reverse_gl, reverse_stock,
>                 recompute_projections, recompute_fulfilment, set_state]
> ```
> Every step is idempotent and logged to `document_event`. Successor existence is checked **before**
> any write, by an explicit query, not by a framework link scan with a per-doctype opt-out list. And
> `delete_linked_ledger_entries` does not exist — ledgers are never deleted.

## 6.5 Amendment

- An amendment is a **new document** with `amended_from` = the cancelled document's name.
  `validate_amended_from` (document.py:868) throws unless the source `docstatus == 2`.
  Because the amendment is itself a draft, it cannot be amended again until *it* is cancelled — that is
  the only guard. **There is no unique constraint on `amended_from`**, so two concurrent amendments of
  the same cancelled document are not structurally prevented.
- `frappe.copy_doc` (:2650-2688) deep-copies, clears `name, owner, creation, modified, modified_by,
  docstatus` and explicitly `amended_from`/`amendment_date`, then strips every `no_copy: 1` field on
  parent and children. All fulfilment counters (`per_billed`, `delivered_qty`, `billed_amt`, `status`,
  `returned_qty`) are `no_copy`, so they reset. `set_status` forces `Draft`.
- `save_version` (:2024) diffs the amendment against `amended_from` so version history stays meaningful.

> **Ours** `amends_id bigint UNIQUE REFERENCES same_table(id)` — the unique constraint makes double
> amendment impossible at the DB level. Copy semantics come from an explicit column allow-list, not a
> `no_copy` flag scattered across schema metadata.

## 6.6 Returns (`controllers/sales_and_purchase_return.py`)

`validate_return(doc)` (:22): no-op unless `is_return`; with `return_against` →
`validate_return_against` then `validate_returned_items`.

`validate_return_against` (:32-84): the reference must exist; the party must match; and when company +
party match and the reference is submitted:
- return posting datetime must be `>=` the reference's ("Posting timestamp must be after {0}");
- `conversion_rate` must **equal** the reference's;
- a Sales Invoice with `update_stock` cannot return an invoice that did not update stock.

`validate_returned_items` (:86-170): builds `valid_items` from **all** `{doctype} Item` rows of the
reference (`limit_page_length=0`) plus `Packed Item` rows for DN/SI. The key is
`(item_code, row_name)` where a per-row link exists (`purchase_receipt_item`, `sales_invoice_item`,
`dn_detail`, …), else bare `item_code`; a missing key **raises** for PR/PI/SI/POS but only msgprints
for DN. Warehouse is mandatory for stock items unless PI/SI without `update_stock`. For DN/SI a return
rate greater than the original throws **unless** the item is Moving Average.

`validate_quantity` (:172-231) — columns checked: `stock_qty` (or `qty` for PI/SI without
`update_stock`), plus `received_qty` and `rejected_qty` for PR/PI/SCR:
```
reference_qty      = ref[col] * ref.conversion_factor     (stock_qty used as-is;
                     rejected-warehouse returns use ref.rejected_qty * conversion_factor)
max_returnable_qty = flt(reference_qty, p) − already_returned
throw if args[col] > 0                                   "must be negative in return document"
throw if already_returned >= reference_qty               StockOverReturnError "already been returned"
throw if abs(current) > max_returnable_qty               StockOverReturnError "Cannot return more than {1}"
```
> **Returns have no tolerance allowance at all.**

`get_already_returned_items` (:274-323) aggregates over submitted returns against the same
`return_against`, grouped by `(item_code, ref_field)`, using `Sum(Abs(qty))` — signs normalised to
positive inside the aggregate.

Signing: return quantities are stored **negative** (`make_return_doc.update_item` sets
`qty = -1 * (source.qty − already_returned)`, same for `stock_qty`, `received_qty`, `rejected_qty`;
`packed_items` ×−1; `discount_amount` and `Actual` taxes ×−1; payments ×−1). The roll-up configs then
use `source_field: "-1 * qty"` so `returned_qty` on the target row is positive.

Effect on fulfilment:
- a return does **not** reduce `SO.per_delivered` / `PO.per_received` — the delivered/received sums
  include only non-return parents;
- it sets `DN.per_returned` / `PR.per_returned` on the `return_against` parent, driving *Return Issued*;
- it reduces effective billing on a DN because `update_billing_percentage` subtracts
  `returned_qty * rate` from the reference amount;
- credit/debit notes reduce outstanding through the normal PLE path (doc 04).

`make_return_doc` (:430+) maps with `validation {"docstatus": ["=", 1]}`, sets `is_return = 1`,
`ignore_pricing_rule = 1`, `return_against`, pre-fills only the remaining qty (warehouse-wise for
PR/SCR, including rejected warehouses), de-duplicates already-returned serials, and refuses consolidated
POS invoices.

## 6.7 Closing / holding

`SalesOrder.update_status(status)` → `StatusService.update_status` (`sales_order/services/status.py:27-40`):
```
check_modified_date()          # throws "has been modified. Please refresh." — optimistic concurrency
doc.set_status(update=True, status=status)
if status == "Draft" and docstatus == 1: re-check credit limit
update_reserved_qty() ; subcontracting order status ; notify_update() ; clear notifications ; update_blanket_order()
```
Because `set_status` feeds the forced status back into the eval rules, passing `"Draft"` is how the
sticky `Closed`/`On Hold` rules are escaped.

Downstream exclusion: `StockController.check_for_on_hold_or_closed_status` (stock_controller.py:524-561)
bulk-fetches referenced parents' status and throws `InvalidStatusError` when On Hold/Closed;
`SellingController.check_sales_order_on_hold_or_close` short-circuits for returns (a return against a
Closed SO is allowed); `update_reserved_qty` refuses to touch bins for Closed (non-return) or Cancelled
SOs. Cancelling a Closed SO is refused outright.

All `Closed` rules carry `and docstatus != 2`, so cancellation always wins over Closed.

## 6.8 Idempotency and concurrency

- Roll-ups are absolute recomputations → re-running is safe. The only stateful trick is the
  submit/cancel `cond`.
- **Row locks:** `frappe.db.get_value(..., for_update=True)` at `account.py:701` (locks the GL Entry
  tail to serialise balance checks, with a comment about MariaDB gap locks),
  `repost_accounting_ledger.py:219`, `appointment.py:129`. Query-builder locks at
  `accounts/general_ledger.py:631`, `accounts/utils.py:1792`, `purchase_invoice.py:786`
  (`Project.total_purchase_cost` read-modify-write), and `.for_update(skip_locked=True)` at
  `process_period_closing_voucher.py:105` to hand work to exactly one worker.
- **Document locks:** `doc.lock()` / `check_if_locked()` (document.py:2334-2360) using
  `frappe.utils.file_lock` with `DOCUMENT_LOCK_EXPIRY` auto-reclaim and a UI "Force Unlock" action;
  raises `frappe.DocumentLockedError`. `queue_action` (:2307) locks then enqueues.
- **Background reposting:** `Repost Item Valuation` docs enqueued with
  `job_id = repost_item_valuation_entry_<name>`, `deduplicate=True`, `queue="long"`, `timeout=1800`,
  capped by `no_of_parallel_reposting` and item-exclusive; recoverable errors re-queue.
- **Savepoints** wrap per-row work so one failure does not roll back a batch:
  `opening_invoice_creation_tool.py:291`, `repost_accounting_ledger.py:319`, `bulk_payment.py:55`,
  `ledger_merge.py:68`, `fiscal_year.py:110` (explicitly to survive a duplicate-key abort on Postgres),
  `payment_entry.py:517`, `asset/depreciation.py:190`.
- **Duplicate submission** is prevented structurally: `check_if_latest` → `TimestampMismatchError` on a
  stale `modified`, then `check_docstatus_transition`; 1→1 is restricted to `allow_on_submit` fields;
  2→anything is refused.

> **Ours** Optimistic concurrency on a `version integer` column checked in the `UPDATE … WHERE version
> = :v` predicate (not a timestamp string comparison), plus the advisory locks from doc 02 for stock
> streams. Long-running recomputes are jobs with an explicit `job` table (state, checkpoint, owner
> lease) rather than a doctype plus a gzipped attachment.

---

## What to take from this chapter

**Copy:** absolute recomputation of every roll-up; the `Σ min(achieved, ordered) / Σ ordered` capped
percentage; declarative status conditions; roll-up-then-validate ordering; returns must reference a
submitted document, post at-or-after it, use the same exchange rate, be negative, and never exceed
`reference − already_returned`; cancel ordering with prevdoc/stock/GL sequencing; `no_copy` semantics on
amendment.

**Reject:** status derived from itself; `== 100` vs `>= 100` inconsistency; three separate over-billing
gates with different tolerances (`0.01`, `1/10**precision`, `100 + allowance`); silent no-error returns
for internal parties; `ignore_linked_doctypes` as a per-doctype opt-out list evaluated after
`on_cancel` already ran; no unique constraint on `amended_from`; SQL expressions interpolated into
roll-up statements; `delete_linked_ledger_entries`.
