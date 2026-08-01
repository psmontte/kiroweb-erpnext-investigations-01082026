# 16 — Stock Reservation, Picking, and Warehouse Structure

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Reservation and picking are the two places where ERPNext has to answer "can I promise this
stock?" concurrently, and the code contains explicit, comment-documented admissions that the
answer depends on the database engine. Those comments are the most valuable evidence in the
entire codebase for why our design must push these guarantees into the schema.

---

## 1. `Bin` — the on-hand cache

`stock/doctype/bin/bin.py:12`. One row per `(item_code, warehouse)` holding:

`actual_qty`, `ordered_qty`, `indented_qty` (requested), `planned_qty`, `reserved_qty`,
`reserved_qty_for_production`, `reserved_qty_for_sub_contract`,
`reserved_qty_for_production_plan`, `reserved_stock`, `projected_qty`, `stock_uom`,
`valuation_rate`, `stock_value`.

Twelve derived quantities in one unlocked row. Maintenance:

- `update_qty(bin_name, args)` (`:261`) — the classic read-modify-write.
- `recalculate_values` (`:40`) — full recompute.
- `set_projected_qty` (`:78`) — `projected_qty` as an arithmetic combination of the others.
- `update_reserved_qty_for_production_plan` (`:90`),
  `update_reserved_qty_for_for_sub_assembly` (`:117`) *(the doubled `for_for` is in the source)*,
  `update_reserved_qty_for_production` (`:138`),
  `update_reserved_qty_for_sub_contracting` (`:154`),
  `update_reserved_stock` (`:227`) — five separate reservation counters, each maintained by its
  own recompute path.
- `get_actual_qty` (`:313`), `get_last_sle_values` (`:317`), `get_bin_details` (`:243`).

`projected_qty` is a **stored** column derived from other stored columns derived from ledger
aggregates. Three levels of cache, no constraint tying any level to the next.

---

## 2. `Stock Reservation Entry` (SRE)

`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:17`. A submittable document,
one per `(item, warehouse, voucher_detail_no)`, holding `reserved_qty`, `delivered_qty`,
`transferred_qty`, `consumed_qty`, `available_qty`, `voucher_qty`, `reservation_based_on`
(`Qty` or `Serial and Batch`), `from_voucher_type`/`_no`/`_detail_no`, and a
`Serial and Batch Entry` child table.

Lifecycle: `validate` (`:77`), `before_submit` (`:87`), `on_submit` (`:93`),
`on_update_after_submit` (`:99`), `before_cancel` (`:117`), `on_cancel` (`:110`).
Validations: `validate_reserved_entries` (`:120`), `validate_amended_doc` (`:222`),
`validate_mandatory` (`:231`), `validate_group_warehouse` (`:251`),
`validate_uom_is_integer` (`:258`), `set_reservation_based_on` (`:272`),
`validate_reservation_based_on_qty` (`:280`),
`validate_reservation_based_on_serial_and_batch` (`:344`),
`can_be_updated` (`:555`), `validate_with_allowed_qty` (`:574`).
Propagation: `update_unreserved_qty_in_sre` (`:148`), `update_reserved_qty_in_voucher` (`:459`),
`update_reserved_qty_in_pick_list` (`:497`), `update_reserved_stock_in_bin` (`:523`),
`update_status` (`:530`).
Orchestration: class `StockReservation` (`:1104`) with `make_stock_reservation_entries` (`:1166`),
`cancel_stock_reservation_entries` (`:1131`), `transfer_reservation_entries_to` (`:1301`),
`make_stock_reservation_entry` (`:1436`), `get_reserved_entries` (`:1484`),
`get_items_to_reserve` (`:1540`), `update_delivered_qty` (`:1418`);
plus module functions `create_stock_reservation_entries_for_so_items` (`:1611`),
`cancel_stock_reservation_entries` (`:1820`),
`get_stock_reservation_entries_for_voucher` (`:1870`),
`update_serial_batch_delivered_qty` (`:1909`), `get_reserved_materials` (`:1932`),
`validate_stock_reservation_settings` (`:675`), `has_reserved_stock` (`:1093`).

Query helpers (nine of them, all aggregate scans):
`get_available_qty_to_reserve` (`:693`), `get_available_serial_nos_to_reserve` (`:749`),
`get_sre_reserved_qty_for_item_and_warehouse` (`:803`),
`get_sre_reserved_qty_for_items_and_warehouses` (`:826`),
`get_sre_reserved_qty_details_for_voucher` (`:861`),
`get_sre_reserved_warehouses_for_voucher` (`:883`),
`get_sre_reserved_qty_for_voucher_detail_no` (`:912`),
`get_sre_reserved_serial_nos_details` (`:958`),
`get_sre_reserved_batch_nos_details` (`:986`), `get_sre_details_for_voucher` (`:1018`),
`get_serial_batch_entries_for_voucher` (`:1046`), `get_ssb_bundle_for_voucher` (`:1067`).

### 2.1 The engine-dependent locking

`get_available_qty_to_reserve` (`:693`). The source comment (verbatim, `:718`–`:721`):

> Lock the rows being aggregated so a concurrent reservation can't change them mid-transaction.
> MariaDB carries the lock on the aggregate query itself (its gap locks also serialize two
> FIRST reservations, when no SRE rows exist yet); postgres has no gap locks, so gate on the
> Bin row (exists once there is stock), then lock the matching SREs in a plain SELECT.

The code:

```python
available_qty = get_stock_balance(item_code, warehouse)
if available_qty:
    conditions = ((sre.docstatus == 1) & (sre.item_code == item_code)
                  & (sre.warehouse == warehouse) & (sre.delivered_qty < sre.reserved_qty))
    if ignore_sre: conditions &= sre.name != ignore_sre

    if frappe.db.db_type == "postgres":
        frappe.qb.from_(bin_table).select(bin_table.name) \
            .where((bin_table.item_code == item_code) & (bin_table.warehouse == warehouse)) \
            .for_update().run()
        frappe.qb.from_(sre).select(sre.name).where(conditions).orderby(sre.name).for_update().run()

    query = frappe.qb.from_(sre).select(
        Sum(sre.reserved_qty - sre.delivered_qty - sre.transferred_qty - sre.consumed_qty)
    ).where(conditions)
    if frappe.db.db_type != "postgres":
        query = query.for_update()

    reserved_qty = query.run()[0][0] or 0.0
    if reserved_qty: return available_qty - reserved_qty
return available_qty
```

Read carefully, this says:

- **The correctness of stock reservation depends on which database you run.**
- On PostgreSQL the serialisation point is **the `Bin` row** — a *cache table* is being used as a
  mutex for the reservation ledger. The comment even notes the caveat: "exists once there is
  stock". **If no `Bin` row exists** (a brand-new item/warehouse pair), there is nothing to lock
  and two concurrent first reservations can both succeed.
- `available_qty = get_stock_balance(item_code, warehouse)` is read **before** any lock is taken
  (`:706`), so the on-hand figure is not protected by the lock that follows.
- The `if reserved_qty:` guard (`:743`) means a computed `reserved_qty` of exactly `0.0` returns
  the raw `available_qty` — correct here, but the pattern of "falsey means skip" recurs
  (see doc 17 §5 for the reorder variant, where it is a real bug).

### 2.2 `validate_with_allowed_qty` — a five-term minimum

`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:574`:

```python
self.db_set("available_qty", get_available_qty_to_reserve(self.item_code, self.warehouse,
                                                          ignore_sre=self.name))
total_reserved_qty = get_sre_reserved_qty_for_voucher_detail_no(...)   # :587
voucher_delivered_qty = 0
if self.voucher_type == "Sales Order":
    voucher_detail_no = self.voucher_detail_no
    if not frappe.db.exists("Sales Order Item", self.voucher_detail_no):
        voucher_detail_no = frappe.get_value("Packed Item", self.voucher_detail_no,
                                              "parent_detail_docname")
    delivered_qty, conversion_factor = frappe.db.get_value("Sales Order Item", voucher_detail_no,
                                                           ["delivered_qty", "conversion_factor"])
    voucher_delivered_qty = flt(delivered_qty) * flt(conversion_factor)

allowed_qty = min(self.available_qty,
                  (self.voucher_qty - voucher_delivered_qty - total_reserved_qty))
```

Note:

- `voucher_detail_no` is a **polymorphic reference**: it may be a `Sales Order Item` name *or* a
  `Packed Item` name, disambiguated by `frappe.db.exists` (`:600`). A probe query to determine
  the type of a foreign key.
- `delivered_qty × conversion_factor` — the SO line's `delivered_qty` is in transaction UOM and
  must be converted to stock UOM. So `Sales Order Item.delivered_qty` (doc 10 §2 point 4) is
  being unit-converted at read time in the reservation validator, while
  `Pick List Item.delivered_qty` holds stock UOM. The same column name means different units on
  different tables.
- **`db_set("available_qty", ...)` writes a submitted document from inside a validator** (`:577`).
- The error message (`:626`–`:648`) is an eleven-placeholder HTML `<ul>` explaining the formula to
  the user — a strong signal that the model is not comprehensible without a tutorial.
- If `allowed_qty <= 0` on a non-submit action, the code **cancels itself** and returns a
  `msgprint` (`:617`–`:622`): `self.cancel()` inside a validation.

### 2.3 Reservation is not consumed atomically with delivery

Delivery updates `delivered_qty` on the SRE via `update_delivered_qty` (`:1418`) /
`update_serial_batch_delivered_qty` (`:1909`), and `update_reserved_stock_in_bin` (`:523`)
refreshes `Bin.reserved_stock`. Three tables (`Stock Ledger Entry`, `Stock Reservation Entry`,
`Bin`) must agree, maintained by three separate write paths.

`transfer_reservation_entries_to` (`:1301`) moves reservations between vouchers (SO → Pick List,
Pick List → Delivery Note) by **rewriting the SRE rows**, not by linking.

---

## 3. `Pick List`

`stock/doctype/pick_list/pick_list.py:44`.

Structure: `Pick List` header (`parent_warehouse`, `purpose`, `work_order`,
`material_request`, `consider_rejected_warehouses`) with `Pick List Item` rows carrying
`item_code`, `warehouse`, `batch_no`, `serial_no`, `qty`, `stock_qty`, `picked_qty`,
`delivered_qty`, `sales_order`, `sales_order_item`, `material_request_item`.

Lifecycle: `validate` (`:110`), `before_save` (`:117`), `before_submit` (`:240`),
`on_submit` (`:277`), `on_update` (`:380`), `on_update_after_submit` (`:343`),
`on_cancel` (`:350`), `on_trash` (`:391`).
Validations: `validate_stock_qty` (`:126`), `validate_warehouses` (`:169`),
`check_serial_no_status` (`:194`), `validate_with_previous_doc` (`:217`),
`validate_sales_order_percentage` (`:229`), `validate_sales_order` (`:244`),
`validate_picked_items` (`:263`), `validate_expired_batches` (`:286`),
`validate_serial_and_batch_bundle` (`:399`), `validate_picked_qty` (`:536`),
`validate_for_qty` (`:712`).
Status/propagation: `update_status` (`:406`), `get_transfer_status` (`:422`),
`is_fully_transferred` (`:444`), `is_partially_transferred` (`:447`),
`stock_entry_exists` (`:413`), `update_reference_qty` (`:450`),
`update_packed_items_qty` (`:466`), `update_sales_order_item_qty` (`:477`),
`update_sales_order_picking_status` (`:488`), `update_bundle_picked_qty` (`:746`).
Reservation bridge: `create_stock_reservation_entries` (`:498`),
`cancel_stock_reservation_entries` (`:525`), `has_unreserved_stock` (`:910`),
`has_reserved_stock` (`:922`).

### 3.1 Allocation: `set_item_locations`

`stock/doctype/pick_list/pick_list.py:550`. The concurrency comment (verbatim, `:553`–`:557`):

> Serialize concurrent allocations per item on postgres. MariaDB's gap locks on the
> picked-items locking read below already make two simultaneous allocations take turns;
> postgres locking reads can't see the rows another in-flight allocation is inserting, so
> both could claim the same stock. Sorted so overlapping documents can't deadlock.

```python
if frappe.db.db_type == "postgres" and hasattr(frappe.db, "transaction_advisory_lock"):
    for item_code in sorted({d.item_code for d in items}):
        frappe.db.transaction_advisory_lock(("pick-allocate", item_code))
```

So on PostgreSQL, allocation is serialised by an **advisory lock keyed on `item_code` alone** —
not `(item_code, warehouse)`. Every pick of the same item across every warehouse in every company
contends on one lock. And the guard is conditional on `hasattr(frappe.db,
"transaction_advisory_lock")`: on a build without that method, there is no serialisation at all.

The allocation itself:

1. `aggregate_item_qty` (`:679`) sums required qty per item, **skipping rows with `picked_qty`**
   (`:685`–`:686`) so already-picked rows are left alone.
2. `get_picked_items_details` (`:761`) and `update_picked_item_from_current_pick_list` (`:810`)
   compute what other pick lists have already claimed.
3. Rows with no `picked_qty` are **removed from the child table** (`:592`–`:598`), including on a
   submitted document.
4. `get_available_item_locations` (`:1041`) returns candidate bins;
   `get_locations_based_on_required_qty` (`:1098`) applies `priority_warehouses`;
   `filter_locations_by_picked_materials` (`:1143`) removes what is already claimed;
   `validate_picked_materials` (`:1118`) checks the result;
   `get_available_item_locations_for_serial_and_batched_item` (`:1170`) handles serials/batches;
   `get_items_with_location_and_quantity` (`:986`) shapes rows.
5. Rows are merged by the key
   `(item_code, warehouse, uom, batch_no, serial_no, sales_order_item or material_request_item)`
   (`:634`–`:641`) — note `sales_order_item or material_request_item`, so a pick line's source
   identity is "whichever of two columns is populated".
6. `item_doc.idx = None; item_doc.name = None` (`:627`–`:628`) — **child row identity is
   deliberately discarded** and re-indexed (`:653`). So any external reference to a
   `Pick List Item.name` (e.g. `Delivery Note Item.pick_list_item`, doc 10 §2) can be invalidated
   by re-running allocation.
7. `if location.picked_qty > location.stock_qty: location.picked_qty = location.stock_qty`
   (`:650`–`:651`) — silent clamping.
8. If the table ends up empty on a submitted pick list, rows are re-added with
   `stock_qty = 0, picked_qty = 0` and a red "Out of Stock" message (`:658`–`:676`) — placeholder
   rows to avoid an empty child table.

`get_picked_items_qty` (`:941`) and `update_pick_list_status` (`:935`) close the loop.

### 3.2 Bundles

`_get_product_bundles` (`:870`), `_get_product_bundle_qty_map` (`:889`),
`_compute_picked_qty_for_bundle` (`:896`) — note the return type is `int` (`:896`),
so a bundle picked quantity is truncated to a whole number, and
`update_bundle_picked_qty` (`:746`) writes it. Fractional bundle picks are not representable.

---

## 4. `Warehouse` — a nested-set tree with an account attached

`stock/doctype/warehouse/warehouse.py:21`, a `NestedSet` subclass (so `lft`/`rgt`/`old_parent`).

`autoname` (`:55`) appends the company abbreviation to the warehouse name — so the **primary key
encodes the company**, and renaming a company's abbreviation renames every warehouse
(via `rename_doc`, doc 09 §6).

`validate` (`:73`), `on_update` (`:76`), `update_nsm_model` (`:79`), `on_trash` (`:82`),
`warn_about_multiple_warehouse_account` (`:110`), `check_if_sle_exists` (`:131`),
`check_if_child_exists` (`:137`), `convert_to_group_or_ledger` (`:140`),
`convert_to_ledger` (`:146`), `convert_to_group` (`:156`), `unlink_from_items` (`:164`).
Helpers: `get_children` (`:169`), `add_node` (`:195`),
`convert_to_group_or_ledger` (`:207`), `get_child_warehouses` (`:214`),
`get_warehouses_based_on_account` (`:221`), `apply_warehouse_filter` (`:253`),
`get_warehouses_for_reorder` (`:290`).

Structural notes:

- **Group vs leaf is mutable** (`convert_to_group` / `convert_to_ledger`), guarded only by
  `check_if_sle_exists` (`:131`) and `check_if_child_exists` (`:137`). A warehouse that has held
  stock can become a group if its SLEs are all cancelled.
- `warn_about_multiple_warehouse_account` (`:110`) is a **warning** that two warehouses share one
  stock account — which breaks the stock-to-GL reconciliation (doc 03) but is permitted.
- `unlink_from_items` (`:164`) nulls the warehouse on `Item Default` rows on delete.
- Nested sets mean **every insert or move rewrites `lft`/`rgt` across the subtree**, under a
  table-level contention pattern, and the rollup queries in budgets (doc 12 §1.2), reorder
  (doc 17 §5), and picking (`get_descendants_of`, `:576`, `:610`) all depend on those values being
  current.

---

## 5. Our design

### 5.1 On-hand is a projection, not a cache

Per decision D6:

```sql
-- immutable event
CREATE TABLE stock_move (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES company(id),
    item_id       uuid NOT NULL REFERENCES item(id),
    warehouse_id  uuid NOT NULL REFERENCES warehouse(id),
    voucher_id    uuid NOT NULL REFERENCES voucher(id),
    voucher_line_id uuid NOT NULL,
    posting_at    timestamptz NOT NULL,
    qty_stock     numeric(21,9) NOT NULL,     -- signed, stock UOM only
    serial_batch_id uuid REFERENCES serial_batch(id),
    reverses_move_id uuid UNIQUE REFERENCES stock_move(id),
    CONSTRAINT stock_move_nonzero CHECK (qty_stock <> 0)
);
CREATE INDEX stock_move_pos ON stock_move (item_id, warehouse_id, posting_at, id);

-- recomputable projection, one row per (item, warehouse)
CREATE TABLE stock_on_hand (
    item_id       uuid NOT NULL REFERENCES item(id),
    warehouse_id  uuid NOT NULL REFERENCES warehouse(id),
    company_id    uuid NOT NULL,
    qty_on_hand   numeric(21,9) NOT NULL DEFAULT 0,
    rebuilt_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, warehouse_id)
);
```

`stock_on_hand` is maintained by a trigger on `stock_move` that does
`INSERT ... ON CONFLICT (item_id, warehouse_id) DO UPDATE SET qty_on_hand = qty_on_hand + NEW.qty_stock`.
That statement takes the row lock **as part of the update**, so it is a genuine serialisation
point on `(item_id, warehouse_id)` — on any engine, cross-host, released at transaction end.
No `Bin` mutex (§2.1), no advisory lock on `item_code` alone (§3.1), no engine branch.

`projected_qty` and the five `reserved_qty_for_*` counters (§1) become **views**.

### 5.2 Reservation as an append-only ledger

```sql
CREATE TABLE stock_reservation (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid NOT NULL REFERENCES company(id),
    item_id         uuid NOT NULL REFERENCES item(id),
    warehouse_id    uuid NOT NULL REFERENCES warehouse(id),
    demand_line_id  uuid NOT NULL,            -- stable line id (doc 09 §4)
    purpose         reservation_purpose NOT NULL,  -- 'sales','production','subcontract','plan','pick','pos'
    qty_stock       numeric(21,9) NOT NULL,    -- signed: + reserve, - release
    serial_batch_id uuid REFERENCES serial_batch(id),
    expires_at      timestamptz,
    reverses_id     uuid UNIQUE REFERENCES stock_reservation(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid NOT NULL REFERENCES app_user(id),
    CONSTRAINT sr_nonzero CHECK (qty_stock <> 0)
);
CREATE INDEX sr_pos ON stock_reservation (item_id, warehouse_id) WHERE reverses_id IS NULL;
```

- **One table, one signed column, six purposes.** Replaces `Stock Reservation Entry` plus five
  `Bin.reserved_qty_for_*` counters (§1), plus `delivered_qty`/`transferred_qty`/`consumed_qty`
  on the SRE (§2) — consumption is a negative row, not a counter update.
- **Releases are compensating rows** (`reverses_id UNIQUE`), so the reservation history is
  complete. ERPNext's `transfer_reservation_entries_to` (§2.3) rewrites rows.
- `expires_at` gives POS and web-checkout holds a TTL with no cleanup job needed for
  correctness (expired rows are excluded by the view).
- `demand_line_id` is a **stable line id** referencing `line_registry` (doc 10 §5.1) — no
  `frappe.db.exists` probe to decide whether it is a `Sales Order Item` or a `Packed Item`
  (§2.2).
- All quantities are **stock UOM, always**. The `delivered_qty × conversion_factor` conversion
  in the validator (§2.2) has no analogue.

Availability:

```sql
CREATE VIEW stock_available AS
SELECT h.item_id, h.warehouse_id, h.company_id,
       h.qty_on_hand,
       COALESCE(r.reserved, 0)                       AS reserved_qty,
       h.qty_on_hand - COALESCE(r.reserved, 0)       AS available_qty
FROM stock_on_hand h
LEFT JOIN (
    SELECT item_id, warehouse_id, SUM(qty_stock) AS reserved
    FROM stock_reservation
    WHERE reverses_id IS NULL
      AND (expires_at IS NULL OR expires_at > now())
    GROUP BY item_id, warehouse_id
) r ON r.item_id = h.item_id AND r.warehouse_id = h.warehouse_id;
```

Enforcement is a deferred constraint trigger on `stock_reservation` that does
`SELECT ... FROM stock_on_hand WHERE (item_id, warehouse_id) = (...) FOR UPDATE`
**before** aggregating — so the on-hand read and the reservation sum are under the same lock,
unlike §2.1 where `get_stock_balance` is read before any lock. If the `stock_on_hand` row does
not exist, the trigger inserts a zero row first, which closes the
"no `Bin` row yet" hole (§2.1).

### 5.3 Picking

```sql
CREATE TABLE pick_task (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL,
    from_warehouse_id uuid REFERENCES warehouse(id),
    purpose        pick_purpose NOT NULL,
    state          pick_state NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE pick_allocation (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pick_task_id    uuid NOT NULL REFERENCES pick_task(id),
    line_id         uuid PRIMARY KEY DEFERRABLE,   -- stable, never regenerated
    demand_line_id  uuid NOT NULL,
    item_id         uuid NOT NULL REFERENCES item(id),
    warehouse_id    uuid NOT NULL REFERENCES warehouse(id),
    serial_batch_id uuid REFERENCES serial_batch(id),
    allocated_qty   numeric(21,9) NOT NULL,
    reservation_id  uuid REFERENCES stock_reservation(id),
    picked_qty      numeric(21,9) NOT NULL DEFAULT 0,
    UNIQUE (pick_task_id, demand_line_id, warehouse_id, serial_batch_id)
);
```

- **Allocation rows are never deleted and re-indexed** (§3.1 points 3, 6). `line_id` is stable, so
  `doc_link` references from a delivery survive re-allocation.
- **Each allocation holds a `reservation_id`**, so picking *is* reserving — one mechanism, not two
  that must be kept in sync (§2.3, §3 `create_stock_reservation_entries`).
- Serialisation is the `stock_on_hand` row lock via the reservation trigger — scoped to
  `(item_id, warehouse_id)`, not to `item_code` globally (§3.1).
- `picked_qty > allocated_qty` is a `CHECK`, not a silent clamp (§3.1 point 7).
- Empty allocation is an empty set with an explicit `pick_task.state = 'unfulfillable'` and a
  `pick_shortage` row per shortfall — no zero-quantity placeholder rows (§3.1 point 8).
- Bundle quantities are `numeric(21,9)`, not `int` (§3.2).
- Allocation strategy (`fifo`, `fefo`, `nearest_bin`, `single_bin_preferred`,
  `priority_warehouse`) is a `pick_strategy` policy row, not the implicit ordering of
  `get_available_item_locations`.

### 5.4 Warehouse

```sql
CREATE TABLE warehouse (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    code          text NOT NULL,
    name          text NOT NULL,
    parent_id     uuid REFERENCES warehouse(id),
    kind          warehouse_kind NOT NULL,   -- 'group','storage','transit','rejected','scrap'
    stock_account_id uuid REFERENCES account(id),
    is_active     boolean NOT NULL DEFAULT true,
    UNIQUE (company_id, code),
    CONSTRAINT wh_group_no_account CHECK (kind <> 'group' OR stock_account_id IS NULL),
    CONSTRAINT wh_storage_has_account CHECK (kind = 'group' OR stock_account_id IS NOT NULL)
);
CREATE UNIQUE INDEX wh_account_unique ON warehouse (stock_account_id) WHERE stock_account_id IS NOT NULL;
```

- **`parent_id` + recursive CTE** (decision D12), not `lft`/`rgt` (§4). Moving a subtree is a
  one-row UPDATE with a cycle-check trigger; no subtree renumbering, no contention.
- **`UNIQUE (company_id, code)`** — the code does not encode the company abbreviation, so
  renaming a company touches one row (§4 `autoname`).
- **`kind` is immutable once `stock_move` rows exist** (trigger), rather than convertible with a
  scan-based guard (§4).
- **`wh_account_unique`** makes "two warehouses sharing one stock account" *impossible*, not a
  warning (§4). This is what makes the stock↔GL reconciliation (doc 03) an invariant rather than
  an aspiration.
- `kind = 'transit'` is explicit, so in-transit stock between warehouses/companies is modelled
  rather than being a naming convention.

---

## 6. Findings carried forward

| Finding | Location | Our fix |
|---|---|---|
| Reservation correctness depends on DB engine | `stock_reservation_entry.py:718`–`:741` | trigger + `FOR UPDATE` on `stock_on_hand`; engine-independent |
| `Bin` row used as a mutex; hole when no `Bin` row exists | `stock_reservation_entry.py:721`–`:731` | trigger inserts the zero row, then locks it |
| `get_stock_balance` read before the lock | `stock_reservation_entry.py:706` | on-hand read is inside the locked region |
| Pick allocation serialised by advisory lock on `item_code` only, and only if the method exists | `pick_list.py:558`–`:560` | row lock on `(item_id, warehouse_id)` via the same trigger |
| `db_set` on a submitted doc from inside a validator | `stock_reservation_entry.py:577` | `available_qty` is a view, never stored |
| `self.cancel()` inside validation | `stock_reservation_entry.py:619` | validation never mutates state |
| `voucher_detail_no` polymorphic, typed by `frappe.db.exists` probe | `stock_reservation_entry.py:600`–`:603` | `line_registry` FK |
| `delivered_qty` in transaction UOM, converted at read | `stock_reservation_entry.py:607`–`:611` | all stock quantities in stock UOM |
| Five separate `Bin.reserved_qty_for_*` counters | `bin.py:90`–`:227` | one signed `stock_reservation` table + views |
| `projected_qty` stored, derived from stored derived values | `bin.py:78` | view |
| Pick list child rows deleted and re-indexed, identity discarded | `pick_list.py:592`–`:598`, `:627`–`:653` | stable `line_id`, rows never re-indexed |
| `picked_qty` silently clamped to `stock_qty` | `pick_list.py:650`–`:651` | `CHECK` constraint |
| Zero-quantity placeholder rows to avoid empty table | `pick_list.py:658`–`:676` | `pick_shortage` rows + explicit state |
| Bundle picked qty is `int` | `pick_list.py:896` | `numeric(21,9)` |
| Two warehouses may share one stock account (warning only) | `warehouse.py:110` | partial `UNIQUE INDEX` |
| Warehouse PK encodes company abbreviation | `warehouse.py:55` | `uuid` PK + `UNIQUE (company_id, code)` |
| Group/leaf convertible after use | `warehouse.py:140`–`:163` | immutable `kind` once moves exist |
| Nested sets (`lft`/`rgt`) | `warehouse.py:21`, `:79` | `parent_id` + recursive CTE (D12) |

Cross-references: doc 02 (stock ledger and valuation), doc 03 (stock↔GL bridge),
doc 10 (fulfilment links), doc 13 (POS availability), doc 17 (item/UOM/batch/reorder),
`docs/design/FINAL-SCHEMA.md`.
