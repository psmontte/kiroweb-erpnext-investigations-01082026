# 17 — Item Master, UOM, Variants, Batch/Serial Selection, and Reorder

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

The item master is the most-referenced table in the system (`Item.name` appears as a foreign key
in over 100 tables). Its design decisions therefore propagate everywhere. This document covers
identity, UOM, variants, pricing validity, batch/serial selection, and reorder.

---

## 1. `Item` identity

`stock/doctype/item/item.py:54`.

`autoname` (`:164`) resolves the item code from `item_code`, a naming series, or the item name,
depending on `Stock Settings.item_naming_by`. So **`Item.name` is a business-meaningful string
primary key**, referenced by every stock, sales, buying, and manufacturing table.

The cost of that decision is visible in the rename machinery:

- `before_rename` (`:639`), `after_rename` (`:648`)
- `delete_old_bins` (`:663`)
- `validate_duplicate_item_in_stock_reconciliation` (`:666`)
- `validate_properties_before_merge` (`:695`)
- `validate_duplicate_product_bundles_before_merge` (`:708`)
- `set_last_purchase_rate` (`:724`)
- `recalculate_bin_qty` (`:728`)
- `update_bom_item_desc` (`:750`)

Merging two items (`merge = True`) requires reconciling `Bin` rows, product bundles, BOM
descriptions, and last-purchase rates — eight methods of cleanup, on top of Frappe's generic
`rename_doc` cascade across every referring column (doc 09 §6).

Immutability is enforced by `cant_change` (`:1092`), which compares a list of fields against the
pre-save document and throws if a stock/asset/submitted document exists. Supporting checks:
`stock_ledger_created` (`:610`), `has_submitted_assets` (`:617`),
`_get_linked_submitted_documents` (`:1156`), `validate_serialized_change_with_bundle` (`:1137`),
`validate_standard_cost_change` (`:1068`), `is_standard_cost_valuation_change` (`:1082`).

This is a hand-maintained list of "columns that become read-only under conditions discovered by
querying other tables". Miss a field, and a silent data corruption becomes possible.

Other validations: `validate_description` (`:256`),
`validate_customer_provided_part` (`:281`), `validate_fixed_asset` (`:372`),
`validate_retain_sample` (`:389`) / `clear_retain_sample` (`:401`),
`validate_item_tax_net_rate_range` (`:421`), `validate_item_type` (`:469`),
`validate_naming_series` (`:476`), `check_for_active_boms` (`:504`),
`fill_customer_code` (`:512`), `check_item_tax` (`:520`), `validate_barcode` (`:535`),
`validate_warehouse_for_reorder` (`:571`), `validate_item_defaults` (`:776`),
`update_defaults_from_item_group` (`:784`),
`validate_auto_reorder_enabled_in_stock_settings` (`:1213`),
`convert_erpnext_to_barcodenumber` (`:1224`), `set_opening_stock` (`:309`),
`add_price` (`:289`) / `make_item_price` (`:1249`) / `update_item_price` (`:620`).
Guards used elsewhere: `validate_end_of_life` (`:1275`), `validate_is_stock_item` (`:1288`),
`validate_cancelled_item` (`:1296`).

---

## 2. UOM and conversion

Three concepts:

- `Item.stock_uom` — the unit the ledger is kept in.
- `Item.purchase_uom` / `sales_uom` — defaults on documents.
- `UOM Conversion Detail` child rows on `Item` — `uom` + `conversion_factor` to stock UOM.
- `UOM Conversion Factor` — a *global* from-UOM/to-UOM factor table.
- `UOM.must_be_whole_number` — integrality flag.

Validation: `validate_uom` (`:1001`), `validate_uom_conversion_factor` (`:1020`),
`validate_conversion_factor` (`:452`), `add_default_uom_in_conversion_factor_table` (`:408`).

### 2.1 `check_stock_uom_with_bin` rewrites the `Bin`

`stock/doctype/item/item.py:1402`:

```python
if stock_uom == frappe.db.get_value("Item", item, "stock_uom"): return

ref_uom = frappe.db.get_value("Stock Ledger Entry", {"item_code": item}, "stock_uom")
if ref_uom and cstr(ref_uom) != cstr(stock_uom):
    frappe.throw("Default Unit of Measure ... cannot be changed directly ...")

bin_list = frappe.get_all("Bin",
    filters={"item_code": item, "stock_uom": ["!=", stock_uom]},
    or_filters=[["reserved_qty", ">", 0], ["ordered_qty", ">", 0],
                ["indented_qty", ">", 0], ["planned_qty", ">", 0]],
    pluck="name", limit=1)
if bin_list:
    frappe.throw("Default Unit of Measure ... cannot be changed directly ...")

# No SLE or documents against item. Bin UOM can be changed safely.
frappe.qb.update(bin_dt).set(bin_dt.stock_uom, stock_uom).where(bin_dt.item_code == item).run()
```

Two problems:

1. **`frappe.db.get_value("Stock Ledger Entry", {"item_code": item}, "stock_uom")` returns one
   arbitrary row.** There is no `ORDER BY`, no `LIMIT` semantics guaranteed, and — critically —
   no `is_cancelled = 0` filter. If cancelled SLEs exist with a different `stock_uom`, the guard
   fires spuriously; if the arbitrary row happens to match, the guard passes even though other
   rows do not.
2. **`Bin.stock_uom` is bulk-rewritten** by a raw `UPDATE` with no `Bin` document load, no
   version guard, and no check that the `Bin`'s existing quantities are meaningful in the new
   unit. The comment says "safely" on the strength of two existence checks, one of which
   (`actual_qty`) is not even in the `or_filters` list — a `Bin` with non-zero `actual_qty` but
   zero reserved/ordered/indented/planned passes and gets its UOM rewritten **while holding
   stock**.

That `Bin` even *has* a `stock_uom` column is the underlying issue: it duplicates
`Item.stock_uom`, so the two can disagree.

### 2.2 Conversion factors live in two places

`UOM Conversion Detail` (per item) and `UOM Conversion Factor` (global) both define factors, with
per-item rows taking precedence. Neither is guaranteed consistent with the other, and neither
constrains transitivity: `1 box = 12 ea` and `1 case = 4 box` do not imply `1 case = 48 ea` unless
someone enters it.

`must_be_whole_number` is checked in scattered places
(e.g. `StockReservationEntry.validate_uom_is_integer`,
`stock/doctype/stock_reservation_entry/stock_reservation_entry.py:258`), not by a constraint.

---

## 3. Variants

Model: a template `Item` with `has_variants = 1`, `variant_based_on` ∈ {`Item Attribute`,
`Manufacturer`}, and `Item Variant Attribute` child rows. Each variant is a **separate `Item`
row** with `variant_of` set and its own `Item Variant Attribute` rows.
`Item Attribute` + `Item Attribute Value` define the domain (or `from_range`/`to_range`/
`increment` for `numeric_values`).

Validation: `validate_variant` (`:854`), `validate_has_variants` (`:896`),
`validate_attributes_in_variants` (`:904`), `validate_stock_exists_for_template_item` (`:973`),
`validate_variant_based_on_change` (`:994`), `validate_attributes` (`:1027`),
`validate_variant_attributes` (`:1046`), `update_variants` (`:833`),
`update_template_tables` (`:432`).

### 3.1 Variant identity is procedural, not constrained

`validate_variant` (`:854`) checks that each attribute exists on the template
(`frappe.db.exists("Item Variant Attribute", {"attribute": d.attribute, "parent": self.variant_of})`,
`:864`), is not disabled (`:879`), and that non-numeric values exist in
`Item Attribute Value` (`:882`–`:893`).

`validate_variant_attributes` (`:1046`) is where uniqueness *would* live. But there is **no
unique constraint on the attribute combination**. Nothing in the schema prevents two variants of
the same template with identical `(Colour=Red, Size=L)`. The check is a query over sibling
variants performed in Python at save time — which means:

- Concurrent creation of two identical variants both pass.
- A variant created by a bulk import with `ignore_validate` bypasses it entirely.
- The "identity" of a variant is a *set of child rows*, which no relational constraint can make
  unique without a normalised key.

`validate_attributes_in_variants` (`:904`) handles the reverse case — removing an attribute from
the template while variants still use it — by fetching all variants, diffing attribute sets, and
building an **HTML table** inside the validator (`:941`–`:972`) to report offenders.
Presentation logic inside a data-integrity check.

`validate_stock_exists_for_template_item` (`:973`) freezes `has_variants`, `variant_of`, and the
`attributes` child table once an SLE exists — using `is_child_table_same("attributes")`
(`:986`), a row-by-row Python comparison.

---

## 4. `Item Price` — validity without overlap detection

`stock/doctype/item_price/item_price.py:16`. Columns: `item_code`, `price_list`, `uom`,
`valid_from`, `valid_upto`, `customer`, `supplier`, `batch_no`, `packing_unit`,
`price_list_rate`, `currency`.

`check_duplicates` (`:87`):

```python
query = (from Item Price
         .select(price_list_rate)
         .where((item_code == self.item_code) & (price_list == self.price_list)
                & (name != self.name)))

data_fields   = ("uom", "valid_from", "valid_upto", "customer", "supplier", "batch_no")
number_fields = ["packing_unit"]

for field in data_fields:
    if self.get(field): query = query.where(item_price[field] == self.get(field))
    else:               query = query.where(Criterion.any([item_price[field].isnull(),
                                                           Cast_(item_price[field], "varchar") == ""]))
for field in number_fields:
    if self.get(field): query = query.where(item_price[field] == self.get(field))
    else:               query = query.where(Criterion.any([item_price[field].isnull(),
                                                           item_price[field] == 0]))
if query.run(as_dict=True): frappe.throw(..., ItemPriceDuplicateItem)
```

**This detects only exact equality of `valid_from` and `valid_upto`.** Two rows for the same
item/price-list/customer with validity `2026-01-01 → 2026-06-30` and `2026-03-01 → 2026-12-31`
are *not* duplicates by this test and both save. Which price applies on 2026-04-01 is then decided
by whatever `ORDER BY` the price-fetching code happens to use.

Consequences:

- **Price is non-deterministic in the overlap region.** The same order line, priced twice, can
  produce two different rates.
- `valid_from IS NULL` means "from the beginning of time" and `valid_upto IS NULL` means
  "forever", but the duplicate check treats NULL as a value to match rather than as an unbounded
  endpoint — so an open-ended row and a dated row never collide.
- The `Cast_(field, "varchar") == ""` clause (`:118`) exists because these columns can hold
  either `NULL` or the empty string. Two representations of "not set" in one column.
- `before_save` (`:146`) sets `reference = customer if selling else supplier` — a **third**
  column duplicating one of two others, to make list views searchable.

Other methods: `validate_item` (`:54`), `update_price_list_details` (`:63`),
`update_item_details` (`:75`), `validate_item_template` (`:81`).

The same "validity implied, not constrained" pattern appears in `Cost Center Allocation`
(doc 12 §3.2) and `Pricing Rule`.

---

## 5. Reorder

`stock/reorder_item.py`. Entry: `reorder_item` (`:14`) → `_reorder_item` (`:24`) with inner
`add_to_material_request` (`:38`); then `create_material_request` (`:213`),
`send_email_notification` (`:312`), `get_email_list` (`:326`),
`get_comapny_wise_users` (`:352`) *(misspelling in source)*, `notify_errors` (`:367`).

Reorder rules are `Item Reorder` child rows on `Item`: `warehouse`, `warehouse_group`,
`warehouse_reorder_level`, `warehouse_reorder_qty`, `material_request_type`.

### 5.1 Variant inheritance

`get_items_for_reorder` (`:118`) collects reorder rows joined to live items
(`_item_is_alive`, `:108`), then `get_reorder_levels_for_variants` (`:156`):

```python
for row in variants_item:
    if not itemwise_reorder.get(row.name) and itemwise_reorder.get(row.variant_of):
        itemwise_reorder.setdefault(row.name, []).extend(itemwise_reorder.get(row.variant_of, []))
```

A variant with no reorder rule inherits the **template's** rules verbatim — including the
template's `warehouse_reorder_level` and `warehouse_reorder_qty`. So a template with 20 variants
generates 20 reorder rules each with the *same* level, which is almost never the intent
(a level of 100 per variant vs 100 across variants).

### 5.2 The warehouse-group rollup bug

`get_item_warehouse_projected_qty` (`:181`):

```python
warehouse_parent_map = frappe._dict(frappe.get_all("Warehouse",
                                    fields=["name","parent_warehouse"], as_list=True))

for item_code, warehouse, projected_qty in frappe.get_all("Bin",
        filters={"item_code": ["in", items_to_consider], "warehouse": ["is","set"]},
        fields=["item_code","warehouse","projected_qty"], as_list=True):

    if item_code not in item_warehouse_projected_qty:
        item_warehouse_projected_qty.setdefault(item_code, {})
    if warehouse not in item_warehouse_projected_qty.get(item_code):
        item_warehouse_projected_qty[item_code][warehouse] = flt(projected_qty)

    parent_warehouse = warehouse_parent_map.get(warehouse)
    while parent_warehouse:
        if not item_warehouse_projected_qty.get(item_code, {}).get(parent_warehouse):
            item_warehouse_projected_qty.setdefault(item_code, {})[parent_warehouse] = flt(projected_qty)
        else:
            item_warehouse_projected_qty[item_code][parent_warehouse] += flt(projected_qty)
        parent_warehouse = warehouse_parent_map.get(parent_warehouse)
```

The rollup uses **`if not ...get(parent_warehouse)`** — a *falsiness* test, not a presence test.
So when the accumulated parent total is `0` (or `0.0`), the branch takes the **assignment** path
instead of the **increment** path, and the previously accumulated value is **overwritten**.

Concretely, for a parent warehouse with children A (`+50`), B (`-50`), C (`+30`), iterated in that
order:

```
A: parent absent            → parent = 50
B: parent = 50 (truthy)     → parent = 50 + (-50) = 0
C: parent = 0   (FALSEY!)   → parent = 30          ← should be 30, coincidentally right
```

but for children A (`+50`), B (`-50`), C (`0`), D (`+30`):

```
A → 50 ;  B → 0 ;  C: 0 is falsey → parent = 0 (overwrite, was 0, fine)
D: 0 is falsey → parent = 30      ← should be 30. Fine.
```

and for A (`0`), B (`+50`):

```
A: absent → parent = 0
B: 0 is falsey → parent = 50      ← should be 50. Fine.
```

The bug bites whenever a **non-zero** accumulated total is followed by a child whose running sum
brings it to zero and then further children arrive — the earlier contributions are silently
dropped rather than added. Combined with a multi-level hierarchy (the `while` walks all
ancestors), group-warehouse projected quantities are unreliable, which means **group-level
reorder rules fire at the wrong times**.

The same shape of falsiness-vs-presence error is the `if reserved_qty:` guard in
`get_available_qty_to_reserve` (doc 16 §2.1), where it is benign. Here it is not.

Also note the rollup **assigns the child's own `projected_qty`** to the parent when the parent is
absent, rather than starting at zero and adding — so the first child's value is set, not
accumulated. Functionally equivalent to `0 + child` only because the parent starts absent.

`create_material_request` (`:213`) then builds Material Requests grouped by company and
`material_request_type`, and `notify_errors` (`:367`) emails failures.
`validate_warehouse_for_reorder` (`stock/doctype/item/item.py:571`) rejects duplicate reorder rows
per warehouse (`DuplicateReorderRows`, `:38`).

---

## 6. Batch and serial selection

### 6.1 `Batch`

`stock/doctype/batch/batch.py:88`. Naming: `autoname` (`:117`), `get_name_from_hash` (`:20`),
`batch_uses_naming_series` (`:34`), `_get_batch_prefix` (`:43`),
`_make_naming_series_key` (`:58`), `get_batch_naming_series` (`:72`),
`get_name_from_naming_series` (`:222`).
Quantity: `recalculate_batch_qty` (`:160`), `get_batch_qty` (`:235`),
`get_batches_by_oldest` (`:296`), `get_available_batches` (`:434`),
`get_pos_reserved_batch_qty` (`:404`).
Other: `set_batchwise_valuation` (`:179`), `set_expiry_date` (`:194`),
`item_has_batch_enabled` (`:155`), `split_batch` (`:305`), `make_batch` (`:397`),
`make_batch_bundle` (`:351`), `validate_serial_no_with_batch` (`:383`),
`get_batch_no` (`:459`), `after_delete` (`:148`).

`Batch.batch_qty` is a **stored aggregate** with `recalculate_batch_qty` (`:160`) to rebuild it —
another cache in the doc 15 §10 family.

`split_batch` (`:305`) creates a new batch and moves quantity by posting a Stock Entry — so batch
splitting is a stock transaction, which is correct, but the new batch's identity is a fresh
string PK with no link back to the parent batch beyond the Stock Entry.

### 6.2 FEFO selection

`get_auto_batch_nos` (`stock/doctype/serial_and_batch_bundle/serial_and_batch_bundle.py:2986`)
is the batch picker. The pipeline:

```python
if kwargs.against_sales_order and (only_consider_batches := get_batches_to_be_considered(...)):
    kwargs.batch_no  = [b.batch_no  for b in only_consider_batches]
    kwargs.warehouse = [b.warehouse for b in only_consider_batches]

available_batches      = get_available_batches(kwargs)          # :3230
stock_ledgers_batches  = get_stock_ledgers_batches(kwargs)
pos_invoice_batches    = get_reserved_batches_for_pos(kwargs)   unless for_stock_levels
sre_reserved_batches   = get_reserved_batches_for_sre(kwargs)   unless ignore_reserved_stock
picked_batches         = get_picked_batches(kwargs)             if is_pick_list

if any of those: update_available_batches(available_batches, ...)
if not ignore_reserved_stock and not for_stock_levels:
    available_batches = remove_reservation_conflict_batches(available_batches, kwargs)   # :3050

if kwargs.based_on == "Expiry":
    available_batches = sorted(available_batches, key=lambda x: x.expiry_date or getdate("9999-12-31"))

if not do_not_check_future_batches and posting_datetime:
    filter_zero_near_batches(available_batches, kwargs)
if not consider_negative_batches:
    available_batches = [d for d in available_batches if flt(d.qty, precision) > 0]

qty = flt(kwargs.qty)
if not qty: return available_batches
return get_qty_based_available_batches(available_batches, qty)
```

Observations:

- **FEFO is opt-in** (`kwargs.based_on == "Expiry"`, `:3032`). The default ordering comes from
  `get_available_batches` (`:3230`), which orders by `Max(batch.expiry_date)` only when configured
  (`:3289`); otherwise by creation. So "sell the oldest first" is a setting, and the fallback is
  insertion order.
- `x.expiry_date or getdate("9999-12-31")` (`:3033`) — batches with no expiry sort **last**. In
  `get_serial_nos_based_on_filters` the equivalent is
  `orderby(order_by_column.isnull(), order=desc)` then `orderby(order_by_column)`
  (`:2526`–`:2527`), i.e. nulls **first**. Two opposite null-ordering conventions for the same
  concept in one file.
- Availability is assembled by **subtracting four independent reservation sources in Python**
  (POS, SRE, picked, stock-ledger). Each is its own query; none is under a shared lock. The same
  batch can be handed to two concurrent transactions.
- `remove_reservation_conflict_batches` (`:3050`) then removes cross-warehouse reservation
  conflicts — a fifth pass.
- `get_available_batches` filters expired batches with
  `(expiry_date >= today()) | expiry_date.isnull()` (`:3256`), so **`today()` is evaluated at
  query time, not from the posting date**. Backdated entries see today's expiry set.
- The duplicated block at `:3582`–`:3622` mirrors `:3245`–`:3289` — two near-identical batch
  availability queries.

`Serial and Batch Bundle` / `Serial and Batch Entry` is the transaction-side container, with
`get_available_serial_nos` and `get_serial_nos_based_on_filters` (`:2516`) handling serials,
ordered by `creation` or `amc_expiry_date` (`:2442`–`:2446`).

---

## 7. Our design

### 7.1 Item identity

```sql
CREATE TABLE item (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    item_code       text NOT NULL,               -- mutable, one-row UPDATE
    item_name       text NOT NULL,
    item_group_id   uuid NOT NULL REFERENCES item_group(id),
    stock_uom_id    uuid NOT NULL REFERENCES uom(id),
    kind            item_kind NOT NULL,          -- 'stock','service','fixed_asset','non_stock'
    tracking        item_tracking NOT NULL,      -- 'none','batch','serial','batch_and_serial'
    template_id     uuid REFERENCES item(id),    -- variant parent
    is_template     boolean NOT NULL DEFAULT false,
    disabled        boolean NOT NULL DEFAULT false,
    end_of_life     date,
    UNIQUE (item_code),
    CONSTRAINT item_template_not_self CHECK (template_id <> id),
    CONSTRAINT item_template_flag CHECK (NOT (is_template AND template_id IS NOT NULL))
);
```

- **`uuid` PK, mutable `item_code`.** Renaming is one UPDATE; merging is a documented data
  migration, not eight cleanup methods (§1).
- **`tracking` is an enum**, replacing the `has_batch_no`/`has_serial_no` boolean pair, so
  contradictory combinations are unrepresentable.
- **Immutability is a trigger**, not a hand-maintained field list (§1): once a `stock_move` exists
  for the item, `stock_uom_id`, `tracking`, `template_id`, and `is_template` are frozen by a
  `BEFORE UPDATE` trigger comparing `OLD`/`NEW`. Adding a field to the frozen set is a one-line
  trigger change that cannot be bypassed by `ignore_validate`.

### 7.2 UOM

```sql
CREATE TABLE uom (
    id            uuid PRIMARY KEY,
    code          text NOT NULL UNIQUE,
    dimension     uom_dimension NOT NULL,      -- 'count','mass','volume','length','time','area'
    whole_only    boolean NOT NULL DEFAULT false
);
CREATE TABLE item_uom (
    item_id       uuid NOT NULL REFERENCES item(id) ON DELETE CASCADE,
    uom_id        uuid NOT NULL REFERENCES uom(id),
    factor_num    bigint NOT NULL,             -- exact rational to stock UOM
    factor_den    bigint NOT NULL,
    role          uom_role[] NOT NULL DEFAULT '{}',  -- 'purchase','sales','stock','packing'
    PRIMARY KEY (item_id, uom_id),
    CONSTRAINT item_uom_factor CHECK (factor_num > 0 AND factor_den > 0)
);
```

- **No `stock_uom` on the on-hand projection.** `stock_on_hand` (doc 16 §5.1) has no UOM column;
  it is always the item's stock UOM. `check_stock_uom_with_bin` and its bulk `UPDATE Bin` (§2.1)
  have no analogue.
- **Exact rational factors**, so `1 case = 48 ea` is `48/1` and no floating-point drift
  accumulates in conversions.
- **`dimension`** prevents a mass UOM being related to a count UOM.
- **`whole_only`** is enforced by a `CHECK` on every quantity column that carries a UOM,
  evaluated in a trigger against `item_uom` — not by scattered validators (§2.2).
- Transitivity is not required because every `item_uom` row carries the factor **to the stock
  UOM directly**. There is no global conversion table to disagree with (§2.2).

### 7.3 Variants with a real identity constraint

```sql
CREATE TABLE item_attribute (
    id          uuid PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    is_numeric  boolean NOT NULL DEFAULT false,
    range_from  numeric(21,9), range_to numeric(21,9), range_step numeric(21,9)
);
CREATE TABLE item_attribute_value (
    id            uuid PRIMARY KEY,
    attribute_id  uuid NOT NULL REFERENCES item_attribute(id),
    value         text NOT NULL,
    sort_order    integer NOT NULL,
    UNIQUE (attribute_id, value)
);
CREATE TABLE item_variant_attribute (
    item_id       uuid NOT NULL REFERENCES item(id) ON DELETE CASCADE,
    attribute_id  uuid NOT NULL REFERENCES item_attribute(id),
    value_id      uuid REFERENCES item_attribute_value(id),
    numeric_value numeric(21,9),
    PRIMARY KEY (item_id, attribute_id),
    CONSTRAINT iva_one_value CHECK ((value_id IS NULL) <> (numeric_value IS NULL))
);
-- variant identity, enforced by the database
ALTER TABLE item ADD COLUMN variant_key text;
CREATE UNIQUE INDEX item_variant_unique ON item (template_id, variant_key)
    WHERE template_id IS NOT NULL;
```

`variant_key` is maintained by a trigger on `item_variant_attribute` as the canonical
serialisation of the sorted `(attribute_code, value)` pairs. The `UNIQUE INDEX` then makes
**duplicate variants impossible** — closing the hole in §3.1, including under concurrency and
under bulk import. A template's attribute set is checked against its variants by an FK from
`item_variant_attribute.attribute_id` to a `template_attribute` row, so removing an attribute
from a template with existing variants is an FK violation, not an HTML table (§3).

### 7.4 Prices with exclusion constraints

```sql
CREATE TABLE item_price (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES company(id),
    price_list_id   uuid NOT NULL REFERENCES price_list(id),
    item_id         uuid NOT NULL REFERENCES item(id),
    uom_id          uuid NOT NULL REFERENCES uom(id),
    party_id        uuid REFERENCES party(id),        -- one column, not customer + supplier + reference
    min_qty         numeric(21,9) NOT NULL DEFAULT 0,
    batch_id        uuid REFERENCES serial_batch(id),
    rate            numeric(19,4) NOT NULL,
    currency_code   char(3) NOT NULL,
    valid_from      date NOT NULL DEFAULT '-infinity',
    valid_to        date NOT NULL DEFAULT 'infinity',
    CONSTRAINT ip_range CHECK (valid_from < valid_to),
    EXCLUDE USING gist (
        company_id WITH =, price_list_id WITH =, item_id WITH =, uom_id WITH =,
        coalesce(party_id, '00000000-0000-0000-0000-000000000000') WITH =,
        coalesce(batch_id, '00000000-0000-0000-0000-000000000000') WITH =,
        numrange(min_qty, min_qty, '[]') WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&
    )
);
```

- **Overlapping validity is impossible** (§4). Price resolution is deterministic by construction:
  at most one row can match a given (item, price list, uom, party, batch, qty, date).
- **`valid_from`/`valid_to` are `NOT NULL` with `-infinity`/`infinity` defaults**, so "unbounded"
  is a value the range operators understand — no NULL-vs-empty-string ambiguity (§4).
- **One `party_id`** replaces `customer` + `supplier` + `reference` (§4).
- Tiered pricing by `min_qty` is a first-class dimension of the exclusion key.

The same `EXCLUDE USING gist` pattern is used for `fulfilment_allowance` (doc 10 §5.4) and
`cost_allocation_rule` (doc 12 §3.3). It is our standard answer to "effective-dated master data".

### 7.5 Reorder as declarative policy

```sql
CREATE TABLE reorder_rule (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES company(id),
    item_id         uuid REFERENCES item(id),
    item_group_id   uuid REFERENCES item_group(id),
    warehouse_id    uuid NOT NULL REFERENCES warehouse(id),
    scope           reorder_scope NOT NULL,       -- 'warehouse','warehouse_subtree'
    method          reorder_method NOT NULL,      -- 'min_max','reorder_point','periodic_review'
    reorder_level   numeric(21,9) NOT NULL,
    reorder_qty     numeric(21,9),
    max_level       numeric(21,9),
    request_type    material_request_type NOT NULL,
    is_active       boolean NOT NULL DEFAULT true,
    CONSTRAINT rr_target CHECK ((item_id IS NULL) <> (item_group_id IS NULL)),
    UNIQUE (company_id, item_id, item_group_id, warehouse_id, scope)
);
```

- **Variants do not silently inherit a template's absolute levels** (§5.1). A rule targets either
  an item or an item group; a template's variants are covered by an `item_group` rule with
  proportional or per-variant levels, or by explicit per-variant rules. Inheritance, if wanted, is
  a documented resolution order, not a `dict.extend`.
- **The subtree rollup is a recursive CTE**, so the falsiness bug (§5.2) cannot exist:

```sql
WITH RECURSIVE tree AS (
    SELECT id, id AS root_id FROM warehouse
    UNION ALL
    SELECT w.id, t.root_id FROM warehouse w JOIN tree t ON w.parent_id = t.id
)
SELECT r.id AS reorder_rule_id,
       SUM(a.available_qty) AS subtree_available
FROM reorder_rule r
JOIN tree t ON t.root_id = r.warehouse_id
JOIN stock_available a ON a.warehouse_id = t.id AND a.item_id = r.item_id
GROUP BY r.id;
```

  `SUM` over a join. No accumulator, no falsiness test, no per-row Python loop, and correct for
  arbitrary hierarchy depth and mixed-sign quantities.
- Reorder consumption is netted against `budget_commitment`-style **open supply**
  (`doc_link` of kind `order`), so a rule does not re-request what is already on order — computed
  in the same query rather than from `Bin.ordered_qty`.

### 7.6 Batch and serial

```sql
CREATE TABLE serial_batch (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES company(id),
    item_id       uuid NOT NULL REFERENCES item(id),
    kind          sb_kind NOT NULL,             -- 'batch','serial'
    code          text NOT NULL,
    parent_id     uuid REFERENCES serial_batch(id),   -- batch split lineage
    manufactured_on date,
    expires_on    date,
    UNIQUE (company_id, item_id, kind, code)
);
CREATE INDEX sb_fefo ON serial_batch (item_id, expires_on NULLS LAST) WHERE kind = 'batch';
```

- **No `batch_qty` column.** Batch on-hand is `stock_on_hand` extended with `serial_batch_id` in
  the projection key, maintained by the same trigger (doc 16 §5.1). Nothing to
  `recalculate_batch_qty` (§6.1).
- **`parent_id`** records split lineage (§6.1).
- **One availability view**, not four Python subtractions (§6.2):

```sql
CREATE VIEW batch_available AS
SELECT h.item_id, h.warehouse_id, h.serial_batch_id, sb.expires_on,
       h.qty_on_hand - COALESCE(r.reserved, 0) AS available_qty
FROM stock_on_hand_batch h
JOIN serial_batch sb ON sb.id = h.serial_batch_id
LEFT JOIN (SELECT serial_batch_id, warehouse_id, SUM(qty_stock) AS reserved
           FROM stock_reservation
           WHERE reverses_id IS NULL AND (expires_at IS NULL OR expires_at > now())
           GROUP BY serial_batch_id, warehouse_id) r
  ON r.serial_batch_id = h.serial_batch_id AND r.warehouse_id = h.warehouse_id;
```

  POS, pick, SRE, and ledger reservations are all rows in one `stock_reservation` table
  (doc 16 §5.2), so availability is one `LEFT JOIN`, computed under the same lock as the
  reservation check.
- **Selection strategy is explicit and consistent**: `allocation_strategy` on the item or the
  document (`fefo`, `fifo`, `lifo`, `manual`), with `NULLS LAST` in a single documented place —
  no two opposite null-ordering conventions (§6.2).
- **Expiry is evaluated against the posting date**, not `now()` (§6.2):
  `sb.expires_on IS NULL OR sb.expires_on >= :posting_date`.
- Serial uniqueness: `CREATE UNIQUE INDEX ON serial_batch (company_id, item_id, code) WHERE kind = 'serial'`
  plus a partial unique index on the serial's current location, so a serial cannot be in two
  warehouses or sold twice.

---

## 8. Findings carried forward

| Finding | Location | Our fix |
|---|---|---|
| `Item.name` is a business string PK, referenced by 100+ tables | `item.py:164` | `uuid` PK + mutable `item_code` |
| Item merge needs 8 cleanup methods | `item.py:663`–`:750` | documented migration; no PK cascade |
| Immutability = hand-maintained field list + cross-table probes | `item.py:1092`, `:1156` | `BEFORE UPDATE` trigger, unbypassable |
| `Bin.stock_uom` duplicates `Item.stock_uom` and is bulk-rewritten | `item.py:1402`–`:1438` | projection has no UOM column |
| SLE UOM guard reads one arbitrary row, no `is_cancelled` filter | `item.py:1406` | no such guard needed |
| `Bin` with non-zero `actual_qty` passes the UOM-change guard | `item.py:1416`–`:1422` (`or_filters` omits `actual_qty`) | UOM frozen once any `stock_move` exists |
| Conversion factors in two tables, no transitivity | `UOM Conversion Detail` + `UOM Conversion Factor` | one `item_uom` with exact rationals to stock UOM |
| Variant attribute combination has no unique constraint | `item.py:1046` | `UNIQUE (template_id, variant_key)` |
| HTML table built inside a validator | `item.py:941`–`:972` | FK violation |
| `Item Price` detects only identical validity pairs | `item_price.py:87`–`:141` | `EXCLUDE USING gist` on `daterange` |
| NULL vs `''` both mean "not set" | `item_price.py:118` | `NOT NULL` with `-infinity`/`infinity` |
| `reference` duplicating `customer`/`supplier` | `item_price.py:146`–`:150` | one `party_id` |
| Variants inherit template's absolute reorder levels | `reorder_item.py:156`–`:159` | scoped `reorder_rule` |
| Warehouse-group rollup overwrites on falsey accumulator | `reorder_item.py:203`–`:207` | recursive CTE + `SUM` |
| `Batch.batch_qty` stored aggregate + recompute | `batch.py:160` | projection keyed by `serial_batch_id` |
| FEFO is opt-in; default order is creation | `serial_and_batch_bundle.py:3032`, `:3289` | explicit `allocation_strategy`, FEFO index |
| Opposite null-ordering conventions for expiry | `serial_and_batch_bundle.py:3033` vs `:2526`–`:2527` | one convention, `NULLS LAST` |
| Availability = 4 Python subtractions, no shared lock | `serial_and_batch_bundle.py:3003`–`:3026` | one view, one reservation table, one lock |
| Expiry filtered by `today()`, not posting date | `serial_and_batch_bundle.py:3256`, `:3601` | filtered by `:posting_date` |
| Duplicated batch-availability query blocks | `serial_and_batch_bundle.py:3245`–`:3289` and `:3582`–`:3622` | one view |

Cross-references: doc 02 (stock ledger/valuation), doc 05 (pricing rules and price resolution),
doc 10 (fulfilment), doc 13 (POS availability), doc 16 (reservation/picking/warehouse),
`docs/design/FINAL-SCHEMA.md`.
