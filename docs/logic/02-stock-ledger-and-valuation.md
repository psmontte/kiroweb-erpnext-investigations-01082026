# 2. The stock ledger and valuation engine

The hardest part of the system. Get this wrong and inventory value, COGS and the balance sheet all
drift. Read this one twice.

Primary files:
- `stock/stock_ledger.py` (2706 lines) — the engine
- `stock/valuation.py` — FIFO/LIFO queue mechanics
- `stock/doctype/repost_item_valuation/repost_item_valuation.py` — backdating
- `stock/serial_batch_bundle.py` — serial/batch valuation
- `stock/doctype/bin/bin.py`, `stock/stock_balance.py`, `stock/utils.py` — the balance cache
- `stock/doctype/stock_reconciliation/stock_reconciliation.py` — absolute → delta conversion

---

## 2.1 The row and its ordering

A `Stock Ledger Entry` (SLE) carries both the **event** and the **derived state after the event**:

| Group | Columns |
|---|---|
| identity | `item_code`, `warehouse`, `posting_date`, `posting_time`, `posting_datetime`, `company` |
| provenance | `voucher_type`, `voucher_no`, `voucher_detail_no`, `dependant_sle_voucher_detail_no` |
| event | `actual_qty` (signed delta), `incoming_rate`, `outgoing_rate` |
| derived state | `qty_after_transaction`, `valuation_rate`, `stock_value`, `stock_value_difference`, `stock_queue` (JSON `[[qty, rate], …]`) |
| traceability | `serial_and_batch_bundle`, `batch_no`, `serial_no`, `has_batch_no`, `has_serial_no` |
| flags | `is_cancelled`, `is_adjustment_entry`, `recalculate_rate`, `to_rename` |

**Canonical order is `(posting_datetime ASC, creation ASC)`** and every read uses exactly that:
`get_stock_ledger_entries` (:2081), `get_previous_sle_of_current_voucher` (:1944),
`update_entries_after.sort_sles` (:805).

`posting_datetime` is computed **in Python** by `get_combine_datetime(posting_date, posting_time)`
(`stock/utils.py:665`) and written by `make_sl_entries` (:147) — there is no DB-side generated column.

"Future" means `posting_datetime > X` **OR** (`posting_datetime == X AND creation > anchor.creation`)
(:2242, :2362). Ties at the same instant are broken by insertion order.

> **Ours** `posting_at timestamptz NOT NULL` as a **stored generated column** from
> `(posting_date, posting_time)`, plus a monotonic `seq bigint` from a sequence for tie-breaking.
> Order by `(posting_at, seq)` — never by `creation`, which is a wall-clock value that can collide
> and is not meaningful after a data import.

## 2.2 Two execution modes

`update_entries_after` (:572) — the engine class — runs in one of two modes:

| Mode | Trigger | Scope |
|---|---|---|
| **current-voucher** | `args.sle_id` set, from `repost_current_voucher` (:172) | only the SLEs of this voucher at this instant |
| **repost** | no `sle_id`, from `repost_future_sle` (:304) | every SLE from an anchor datetime forward for that (item, warehouse), plus cascaded dependants |

## 2.3 Submit path (`make_sl_entries`, :104-169)

```
for pair in sorted({(item_code, warehouse)}): sle_processing_gate(*pair)   # deterministic lock order
cancelled = sl_entries[0].is_cancelled
if cancelled: validate_cancellation(...) ; set_as_cancel(voucher_type, voucher_no)
else:         validate_standard_cost_posting_date(...)
future_sle_exists(args, sl_entries)                # warms a per-request cache
for row in sl_entries:
    if cancelled: row.actual_qty = -row.actual_qty ; fill missing rate from get_incoming_outgoing_rate_for_cancel
    make_entry(row)                                # insert + submit the SLE
    if not is_stock_item: skip
    bin_name = get_or_make_bin(...) ; args.reserved_stock = Bin.reserved_stock
    repost_current_voucher(args, ...)              # valuation for this instant
    update_bin_qty(bin_name, args)                 # bin.py:update_qty
```

Sorting the (item, warehouse) pairs before taking locks is the deadlock-avoidance trick — copy it.

## 2.4 The row-by-row core (`stock/stock_ledger.py`, `process_sle` :1008-1195)

This is the function to reimplement most carefully.

```python
wh_data = prev_sle_dict[(item, warehouse)]         # seeded from get_previous_sle_of_current_voucher
if isinstance(wh_data.stock_queue, str): json.loads(it)
if not wh_data.prev_stock_value: wh_data.prev_stock_value = wh_data.stock_value

# (a) negative-stock gate
if (sle.serial_no and not via_lcv) or not allow_negative_stock:
    if not validate_negative_stock(sle):
        wh_data.qty_after_transaction += actual_qty      # qty still moves...
        return                                            # ...but valuation is SKIPPED

# (b) repost mode only: refresh dynamic rates
if not args.sle_id: get_dynamic_incoming_outgoing_rate(sle)

# (c) internal transfer anchor for PR/PI
if voucher_type in (Purchase Receipt, Purchase Invoice) and is_internal_transfer(sle):
    rate = get_incoming_rate_for_inter_company_transfer(sle)     # :2555
    actual_qty < 0 ? sle.outgoing_rate = rate : sle.incoming_rate = rate

# (d) VALUATION BRANCH
if   valuation_method == "Standard Cost":        process_standard_cost(sle)          # :985
elif sle.serial_and_batch_bundle:               calculate_valuation_for_serial_batch_bundle(sle)  # :1243
elif sle.serial_no and not args.sle_id:         get_serialized_values(sle); qty += actual_qty
                                                stock_value = qty * valuation_rate
elif sle.batch_no and Batch.use_batchwise_valuation and not args.sle_id:
                                                update_batched_values(sle)          # :1774
elif voucher_type == "Stock Reconciliation" and not batch_no and no inventory dimensions:
                                                # ABSOLUTE SNAPSHOT ROW
                                                wh_data.valuation_rate        = sle.valuation_rate
                                                wh_data.qty_after_transaction = sle.qty_after_transaction
                                                wh_data.stock_value           = qty * rate
                                                if method != "Moving Average":
                                                    wh_data.stock_queue = [[qty, rate]]   # queue RESET
elif valuation_method == "Moving Average":      get_moving_average_values(sle)      # :1678
                                                wh_data.qty_after_transaction += actual_qty
                                                wh_data.stock_value = qty_after * valuation_rate
                                                if qty_after != 0:
                                                    valuation_rate = stock_value / qty_after
else:                                           update_queue_values(sle)            # :1717 FIFO/LIFO

# (e) rounding, delta, write-back
wh_data.stock_value = flt(wh_data.stock_value, currency_precision)
if not wh_data.qty_after_transaction: wh_data.stock_value = 0.0        # ← zero qty liquidates value
if sle.actual_qty < 0: sle.incoming_rate = 0
stock_value_difference   = wh_data.stock_value - wh_data.prev_stock_value
wh_data.prev_stock_value = wh_data.stock_value
sle.qty_after_transaction = flt(wh_data.qty_after_transaction, flt_precision)
sle.valuation_rate        = wh_data.valuation_rate
sle.stock_value           = wh_data.stock_value
sle.stock_queue           = json.dumps(wh_data.stock_queue)
old_svd = sle.stock_value_difference ; sle.stock_value_difference = stock_value_difference
if sle.is_adjustment_entry and qty_after == 0 and (stock_value != 0 or svd == 0):
    sle.stock_value_difference = -get_stock_value_difference(...)      # force cumulative value to 0
frappe.get_doc(sle).db_update()                # in-place UPDATE, no new row
prev_sle_dict[key] = sle                       # ← the row just written becomes "previous"

# (f) side effects
if not args.sle_id or auto_created_bundle: update_outgoing_rate_on_transaction(sle)   # :1519
if flt(old_svd) == flt(new_svd): return                    # nothing changed ⇒ no GL repost
if not perpetual_inventory(company): return
if (args.item_code, args.warehouse) != (sle.item_code, sle.warehouse):
    repost_affected_transaction.add((voucher_type, voucher_no))     # feeds GL reposting
```

> **Invariant 1** Per (item, warehouse) stream ordered by `(posting_datetime, creation)`:
> `qty_after_transaction(n) = qty_after_transaction(n-1) + actual_qty(n)` — **except** Stock
> Reconciliation snapshot rows, which are absolute.

> **Invariant 2** `stock_value_difference(n) = stock_value(n) − stock_value(n-1)`, by construction,
> because `prev_stock_value` is re-derived from the previous row's `stock_value`. Therefore
> `Σ stock_value_difference` over a stream = current `stock_value` = `Bin.stock_value`.
> **This is the invariant that keeps the GL reconciled** (see doc 03).

> **Invariant 3** `qty_after_transaction == 0 ⇒ stock_value == 0` (:1126). All accumulated rounding
> residue is flushed into that row's `stock_value_difference`, i.e. into COGS/expense.

> **Invariant 4** `valuation_rate = stock_value / qty_after_transaction` when qty ≠ 0; when qty is 0
> the previous rate is **retained** (sticky).

Note the negative-stock gate: when validation fails, quantity still advances but valuation is
skipped, leaving stale `valuation_rate`/`stock_value`/`stock_queue` on that row. The transaction is
aborted later by `raise_exceptions` (:1848) with `NegativeStockError`. If negative stock *is* allowed,
valuation proceeds with negative queue bins and fallback rates.

`update_outgoing_rate_on_transaction` (:1519-1539) writes the realised rate
`abs(stock_value_difference)/abs(actual_qty)` **back into the source document row**
(`Stock Entry Detail.basic_rate`, `{DN,SI} Item.incoming_rate`, `{PR,PI} Item.valuation_rate`,
`Subcontracting Receipt Supplied Item.rate`) and recomputes the parent's amounts. So submitting a
delivery mutates the delivery note's own cost fields.

## 2.5 FIFO / LIFO queue mechanics (`stock/valuation.py`)

`StockBin = [qty, rate]`. `round_off_if_near_zero(n, precision=7)`: `|n| < 1e-7 → 0.0` (:260).

**`add_stock(qty, rate)`** (:76-101, identical in LIFO at :178):
```
if queue empty: queue.append([0, 0])
if queue[-1].rate == rate: queue[-1].qty += qty          # merge same-rate tail
elif queue[-1].qty > 0:    queue.append([qty, rate])     # normal new bin
else:                                                     # tail is a NEGATIVE bin
    qty = queue[-1].qty + qty
    if qty > 0: queue[-1] = [qty, rate]                  # flipped positive: adopt the new rate
    else:       queue[-1].qty = qty                      # still negative: KEEP THE OLD RATE
```

**`remove_stock(qty, outgoing_rate=0, rate_generator=None, is_return_purchase_entry=False)`** (:102-160):
```
while qty:
    if queue empty: queue.append([0, rate_generator()])            # default 0.0
    index = (first bin whose rate == outgoing_rate) if outgoing_rate>0 or is_return_purchase_entry else 0
    bin = queue[index]
    if qty >= bin.qty:                        # full-bin consumption
        qty = round_off_if_near_zero(qty - bin.qty)
        consumed.append(queue.pop(index))
        if not queue and qty:                 # UNDERFLOW
            queue.append([-qty, outgoing_rate or bin.rate])        # one negative bin
            break
    else:                                     # PARTIAL: bin mutated in place, rate untouched
        bin.qty = round_off_if_near_zero(bin.qty - qty) ; qty = 0
```
LIFO (:212) is identical except `index = -1` always, and `outgoing_rate` is **ignored for selection**.

Gotchas to reproduce or fix:
- Bin selection by `outgoing_rate` uses **exact float equality**; a rounding mismatch silently
  degrades to plain FIFO order.
- A partial consumption does not split into two bins; it decrements in place.
- Underflow produces a single negative bin — that is how negative stock carries a value.
- `is_return_purchase_entry` (PR/PI with `is_return`) makes a purchase return consume the exact bin
  it was received at.

**`update_queue_values`** (stock/stock_ledger.py:1717-1766) is the only production caller:
```
qty_after = round_off_if_near_zero(qty_after + actual_qty)
q = LIFOValuation(stock_queue) if method == "LIFO" else FIFOValuation(stock_queue)
_, prev_value = q.get_total_stock_and_value()            # value FROM THE QUEUE
actual_qty > 0 ? q.add_stock(actual_qty, incoming_rate) : q.remove_stock(|actual_qty|, outgoing_rate, ...)
_, value = q.get_total_stock_and_value()
stock_value = round_off_if_near_zero(stock_value + (value - prev_value))    # accumulate the DELTA
if not stock_queue: stock_queue = [[0, incoming_rate or outgoing_rate or valuation_rate]]
if qty_after: valuation_rate = stock_value / qty_after
```
⚠ `wh_data.stock_value` accumulates the queue **delta** rather than being set from the queue, so
`Σ queue(qty×rate)` and `stock_value` can drift; a Stock Reconciliation snapshot re-synchronises them.
`rate_generator` is `0.0` when `allow_zero_valuation_rate` else `get_fallback_rate(sle)` → `get_valuation_rate`.

## 2.6 Moving average (`get_moving_average_values`, :1678-1715)

```
new_stock_qty = qty_after_transaction + actual_qty
if new_stock_qty >= 0:
    if actual_qty > 0:
        if qty_after_transaction <= 0: valuation_rate = sle.incoming_rate          # reset from zero/negative
        else: valuation_rate = (qty_after*valuation_rate + actual_qty*incoming_rate) / new_stock_qty
    elif sle.outgoing_rate:                                                        # outward WITH a rate
        valuation_rate = (qty_after*valuation_rate + actual_qty*outgoing_rate)/new_stock_qty  if new_stock_qty
                       else sle.outgoing_rate
    # outward WITHOUT outgoing_rate: rate UNCHANGED (issue at current average)
else:                                                                              # goes negative
    if qty_after >= 0 and sle.outgoing_rate: valuation_rate = sle.outgoing_rate
    if not valuation_rate and actual_qty > 0: valuation_rate = sle.incoming_rate
    if not valuation_rate and voucher_detail_no and not allow_zero_valuation_rate:
        valuation_rate = get_fallback_rate(sle)
```
Then the caller derives `stock_value = qty_after_transaction * valuation_rate` — note this is the
**opposite direction** from FIFO, where value is primary and rate is derived. Combined with
Invariant 3 (`qty 0 ⇒ value 0`), that is where moving-average rounding drift gets flushed.

Valuation methods available (`Stock Settings.valuation_method`, default **FIFO**):
`FIFO | Moving Average | LIFO | Standard Cost`.
Resolution order (`stock/utils.py:350`, request-cached): `Item.valuation_method` →
`Company.valuation_method` → `Stock Settings.valuation_method` → `"FIFO"`.

## 2.7 Negative stock

`validate_negative_stock` (:1367-1385):
```
diff = flt(qty_after_transaction + actual_qty - reserved_stock, flt_precision)
threshold = 0.0001   (or 10**-flt_precision when flt_precision > 4)
if diff < 0 and abs(diff) > threshold: record exception ; return False
```
`is_negative_stock_allowed(item_code)` (:2547) = `Stock Settings.allow_negative_stock` **OR**
`Item.allow_negative_stock`.

`validate_negative_qty_in_future_sle` (:2370-2416) checks whether the *future* goes negative after
this insert: first future row with `qty_after_transaction < 0` (:2434); for batches it uses a window
function `sum(actual_qty) over (order by posting_datetime, creation)` and tests `cumulative_total < 0`
(:2459). `reserved_stock` is validated separately (:2485).

## 2.8 Backdating: `update_qty_in_future_sle` + the repost engine

Two different mechanisms, and the distinction matters.

### (a) Cheap synchronous quantity fix-up (`update_qty_in_future_sle`, :2227-2280)

Runs on **every** submit/cancel. No valuation.
```
qty_shift = args.actual_qty  (or get_stock_reco_qty_shift(args) for reconciliations)   # :2283
UPDATE Stock Ledger Entry
   SET qty_after_transaction = qty_after_transaction + qty_shift
 WHERE item_code=? AND warehouse=? AND is_cancelled=0
   AND (future condition)
   AND posting_datetime < (next Stock Reconciliation)          -- get_next_stock_reco :2324
validate_negative_qty_in_future_sle(args, allow_negative_stock)
```
The stop-at-next-reconciliation rule exists because a reconciliation row carries an **absolute**
`qty_after_transaction`; shifts must not propagate past it.

### (b) Asynchronous valuation repost (`Repost Item Valuation`)

Triggered by `repost_future_sle_and_gle` (`controllers/stock_controller.py:360` →
`stock/services/stock_ledger_service.py:219`):
```
force = (docstatus == 2)
if force or future_sle_exists(args) or repost_required_for_queue(doc):
    Stock Reposting Settings.item_based_reposting ? create_item_wise_repost_entries(...) : create_repost_item_valuation_entry(args)
```
`repost_required_for_queue` (stock_controller.py:597-628) additionally forces a repost when one
voucher consumes the same (item, warehouse) in multiple rows **and** a FIFO/LIFO queue is in use —
because intra-voucher consumption order changes the result.

The traversal (`repost_stock_ledgers`, :769-803) walks forward in `(posting_datetime, creation)`
order, deduplicating by SLE name, and **cascades across streams** via
`dependant_sle_voucher_detail_no` (:814-836): a transfer's target leg, a repack/manufacture FG row or
a subcontracting row depends on another (item, warehouse)'s outgoing rate, so reposting one must pull
the other stream into the same ordered deque (re-sorting the whole deque each time). `prev_sle_dict`
is keyed per (item, warehouse), so interleaved streams stay correct.

Durability: every 2000 rows it checkpoints (`update_data_in_repost`, :867) by writing
`current_index`, `items_to_be_repost`, counters and a **gzip-JSON `File` attachment** holding
`{repost_affected_transaction, item_wh_wise_last_posted_sle, item_wh_first_reposted}` (:368-420),
then commits. So a repost is **not a single transaction** — a crash resumes from the checkpoint.

`Repost Item Valuation` states: `Queued | In Progress | Completed | Skipped | Failed | Cancelled`.
`RecoverableErrors = (JobTimeoutException, QueryDeadlockError, QueryTimeoutError)` leave the doc
`In Progress` for re-pickup; anything else is `Failed` and needs `restart_reposting()`.
Scheduling: hourly, or parallel (`no_of_parallel_reposting`, default 4) with
`job_id = repost_item_valuation_entry_<name>`, `deduplicate=True`, at most one in-flight job per
`item_code`, gated by `in_configured_timeslot()`. Three separate dedup mechanisms exist
(`deduplicate_similar_repost`, `skipped_similar_reposts`, `skip_reposts_covered_by_dependents` using
the `item_wh_first_reposted` coverage map + a 24h redis key).

Reposting is blocked before Period Closing Vouchers, closed Accounting Periods, Stock Closing Entries
and `Company.accounts_frozen_till_date`; conversely `check_pending_reposting` (stock/utils.py:542) blocks
freezing while reposts are pending (`PendingRepostingError`).

> **Ours — the single most important design decision in the system.**
> Split the immutable event from the derived projection:
>
> | Table | Nature | Contents |
> |---|---|---|
> | `stock_move` | **immutable, append-only** | item, warehouse, signed qty, rate, source doc + line, `posting_at`, `seq` |
> | `stock_valuation_state` | **derived, recomputable** | per (item, warehouse, seq): running qty, running value, `value_delta`, queue (`jsonb`), `computed_from_seq`, `version` |
> | `stock_balance` | cache | current qty/value + demand columns |
>
> Backdating then means "invalidate the projection from `seq >= X` and recompute", not "rewrite
> history". Recompute is a pure function of `stock_move` rows, so it is restartable, testable and
> comparable (we can recompute into a shadow table and diff before swapping). `value_delta` is what
> the GL reads — same invariant as ERPNext, without mutating the event.
>
> Keep: the deterministic lock order, the dependency cascade (model it explicitly as
> `stock_move_dependency(move_id, depends_on_move_id)`), stop-at-snapshot semantics, and the
> "block period close while recompute is pending" rule.

## 2.9 Serial and batch valuation

Modern ERPNext creates a **bundle document** per movement line and hangs individual serial/batch rows
off it (`Serial and Batch Bundle` + `Serial and Batch Entry`); the SLE points at it via
`serial_and_batch_bundle`.

**Per-serial rate** (`SerialNoValuation`, serial_batch_bundle.py:638-795): inward uses the bundle's
`total_amount`; outward resolves each serial's rate from the **latest inward `Serial and Batch Entry`**
for that (item, warehouse, serial) in two stages — `MAX(posting_datetime) <= sle.posting_datetime`
excluding the own voucher, then `MAX(creation)` within that datetime.
`get_incoming_rate() = |stock_value_change / actual_qty|`.

**Per-batch rate** (`BatchNoValuation`, :806-971): aggregates `Serial and Batch Entry` per batch
strictly before `(posting_datetime, creation)`, excluding the own voucher/detail and `Pick List`:
```
batch_avg_rate[b] = Σ stock_value_difference(b) / Σ qty(b)        # batch-wise moving average
stock_value_change += batch_avg_rate[b] * consumed_qty(b)
```
`prepare_batches` (:899) splits batches into `use_batchwise_valuation = 1` (valued per batch) and the
rest (valued through the warehouse-level FIFO queue, also forced when Moving Average +
`Stock Settings.do_not_use_batchwise_valuation`). `validate_negative_batch` raises
`BatchNegativeStockError`.

On the ledger side, `calculate_valuation_for_serial_batch_bundle` (:1243-1278):
```
wh_data.stock_queue = last Serial and Batch Entry.stock_queue (order by idx desc)
wh_data.stock_value = round_off_if_near_zero(wh_data.stock_value + doc.total_amount)
wh_data.qty_after_transaction += flt(sle.actual_qty)      # ← the SLE qty, never doc.total_qty
if qty_after: valuation_rate = stock_value / qty_after
```

Note the leftovers: `Stock Ledger Entry.serial_no` is still `Long Text` and `batch_no` is `Data`
(not a Link) — an unfinished migration.

> **Ours** Model it directly: `stock_move_serial(move_id, serial_id, rate)` and
> `stock_move_batch(move_id, batch_id, qty, rate)`. The bundle document exists only because the
> framework needed a submittable parent for child rows; we do not need it. Batch-wise valuation stays
> as an explicit per-batch projection (`batch_valuation_state`), parallel to the warehouse one.

## 2.10 Bin — the balance cache (`bin.py`, `stock_balance.py`)

`Bin` is unique on `(item_code, warehouse)` and **not** submittable. Authoritative data is the SLE
stream: `Bin.actual_qty`, `valuation_rate`, `stock_value` are set from the **last processed row**
(`update_bin`, :1906) and are fully re-derivable (`get_last_sle_values`, order
`posting_datetime desc, creation desc limit 1`).

Demand columns are maintained **incrementally as deltas** (`bin.py:update_qty`):
```
actual_qty = Bin.actual_qty  (or re-read the last SLE when future SLEs exist / cancelling)
ordered/reserved/indented/planned = Bin.<f> + args.<f>
projected_qty = actual + ordered + indented + planned
              - reserved - reserved_for_production - reserved_for_sub_contract - reserved_qty_for_production_plan
```
Full recompute helpers exist per column and are what `repost_stock` uses:
`stock/stock_balance.py` — `get_reserved_qty` (:89), `get_indented_qty` (:150),
`get_ordered_qty` (:192) = PO + Subcontracting Order, `get_planned_qty` (:256) — and
`Bin.recalculate_values` (`stock/doctype/bin/bin.py:40`).
`repost_stock` creates a repost at `1900-01-01 00:01` for a full replay.

> **Ours** Same idea, but every demand column is defined **only** as a query over open order lines,
> with a nightly consistency job that diffs cache vs query and alerts. Business logic never writes to
> the cache directly, and no accounting number is ever read from it.

## 2.11 Stock Reconciliation: absolute → delta

`update_stock_ledger` (stock_reconciliation.py:872-943) per row:

1. **All of qty, rate, current_qty empty** → `make_adjustment_entry` (:946): emit an SLE with
   `stock_value_difference = -get_stock_value_difference(...)` and `is_adjustment_entry = 1`, driving
   cumulative stock value to exactly zero.
2. **Serial/batch item** → `get_sle_for_serialized_items` (:961): **reverse-then-receive** — an
   outgoing SLE for `-current_qty` with the current bundle, then (if `row.qty != 0`) an incoming SLE
   with the new bundle. Never an absolute snapshot.
3. **Plain item** → `get_sle_for_items` (:986):
   ```
   actual_qty            = 0                 # no delta!
   qty_after_transaction = flt(row.qty)      # ABSOLUTE target balance
   valuation_rate        = flt(row.valuation_rate)
   ```
   Rows that match the previous SLE exactly are **skipped entirely** (no ledger churn).
   Inventory-dimension rows are forced into delta form instead (:1034).

Cancellation re-emits mirrored rows carrying `previous_qty_after_transaction` (needed by
`get_stock_reco_qty_shift`) with `stock_value_difference = -amount_difference` (:1013).
`recalculate_difference_amount_from_ledger` (:1140) re-derives the document's amounts from
`Σ stock_value_difference` after a repost. Documents with >100 rows submit/cancel in a background job.

> **Ours** A reconciliation is an explicit `stock_count` document producing an ordinary signed
> `stock_move` delta (`counted_qty − qty_at(posting_at)`) plus, if the rate changed, a separate
> `revaluation` move with `qty_delta = 0` and a value delta. No absolute rows in the event log at all
> — that removes the "stop propagating at the next snapshot" special case, the mirrored-cancel rows,
> and the whole `is_adjustment_entry` branch.

## 2.12 Concurrency

| Mechanism | Where | Scope |
|---|---|---|
| `sle_processing_gate(item, wh)` → `transaction_advisory_lock(("stock-sle", item, wh), 300)` (Postgres only) | :292; called from `make_sl_entries` over the **sorted** pair set (:115) and again in `update_entries_after.__init__` (:613) | txn-scoped, re-entrant; serialises all stock writes per (item, warehouse). Needed because Postgres locking reads cannot see another txn's uncommitted inserts (MariaDB got this from gap locks) |
| `repost_gate(item, wh)` → `advisory_lock(("stock_repost", item, wh), 300)` | :273, wraps each item in `repost_future_sle` | session-level; repost-vs-repost only, deliberately not on the submit path |
| `... limit 1 for update` | `get_previous_sle_of_current_voucher` :1969 | locks the anchor previous row |
| `.for_update()` | `get_sle_against_current_voucher` :1936, `get_stock_ledger_entries(for_update=True)` :2081 | locks the voucher's rows / the whole future range being reposted |
| `transaction_advisory_lock(("batch-valuation", item, wh))` | serial_batch_bundle.py:818 | Postgres cannot use `FOR UPDATE` with `GROUP BY`, so an advisory lock replaces it |
| `frappe.get_lazy_doc(..., for_update=True)` | :1561, :1627, :1636 | row lock before rewriting document amounts |
| Bin unique index + savepoint retry | `stock/utils.py:227` | concurrent Bin creation |

> **Ours** Keep the advisory lock per (item, warehouse) taken in sorted order — it is the correct
> primitive on Postgres and it is what makes the running-balance projection safe. Add
> `SELECT … FOR UPDATE` on the projection row for the anchor. Recompute jobs take the same lock, so a
> recompute and a live posting cannot interleave on one stream.

---

## What to take from this chapter

**Copy:** total order per (item, warehouse); `stock_value_difference` as the single GL amount;
"qty 0 ⇒ value 0"; the dependency cascade concept; the deterministic lock order; blocking period close
while recompute is pending; skip-if-unchanged on reconciliation rows.

**Reject:** derived state stored *inside* the event row; absolute snapshot rows in the event log;
non-transactional multi-commit reposts as the primary correctness mechanism; exact-float rate matching
for queue bin selection; queue value and `stock_value` maintained by two different mechanisms;
ordering on `creation`; a valuation branch tree with seven arms (`Standard Cost` / bundle / legacy
serial / batchwise / reconciliation / moving average / queue) — collapse it to
`strategy(method).apply(prev_state, event) -> new_state`.
