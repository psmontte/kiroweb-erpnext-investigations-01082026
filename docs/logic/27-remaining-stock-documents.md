# 27 — The Remaining Stock Documents

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Docs 02, 03, 16, 17 and **[S04](../scenarios/S04-stock-transfer-and-in-transit.md)** covered the
stock ledger, valuation, the GL bridge, reservation/picking, the item master, and transfers. This
document closes the remaining inventory documents: **Stock Reconciliation** (the only document that
can override valuation directly), **Item Standard Cost** (new in v17, and unusually well designed),
**Putaway Rule**, **Serial No**, **Product Bundle**, **Packing Slip**, and the logistics documents.

Closes the `docs/COVERAGE.md` gaps for `Stock Reconciliation`, `Stock Entry Type`,
`Putaway Rule`, `Serial No`, `Item Standard Cost`, `Product Bundle`, `Packing Slip`,
`Delivery Trip`, `Shipment`, and `Stock Ledger Entry` — the last of these being the SLE **doctype
controller** (§6), which is a different body of rules from the valuation algorithm in doc 02 and had
not been read.

---

## 1. `Stock Reconciliation` — the valuation override

`StockReconciliation(StockController)`
(`stock/doctype/stock_reconciliation/stock_reconciliation.py:35`). This is the only document that
can **set** an item's quantity and valuation rate to an absolute value rather than moving it by a
delta. It is therefore the opening-stock mechanism (S05 §7.3), the physical-count adjustment, and
the valuation-correction tool, all in one.

### 1.1 `validate` — twenty steps, in a load-bearing order

`validate` (`:68`):

```python
sbb = SerialBatchBundleService(self)
self.validate_standard_cost_items()          # :240
self.validate_items_exist()
if not self.expense_account:
    self.expense_account = frappe.get_cached_value("Company", self.company, "stock_adjustment_account")
if not self.cost_center:
    self.cost_center = frappe.get_cached_value("Company", self.company, "cost_center")
self.validate_posting_time()
self.set_current_serial_and_batch_bundle()   # :280  ← snapshots what is there NOW
self.set_new_serial_and_batch_bundle()       # :540  ← what it should become
sbb.validate_duplicate_serial_and_batch_bundle("items")
self.remove_items_with_no_change()           # :606
self.validate_data()                         # :709
self.change_row_indexes()                    # :791
self.validate_expense_account()              # :1098
self.validate_customer_provided_item()
self.set_zero_value_for_customer_provided_items()   # :1113
sbb.clean_serial_nos()
self.set_total_qty_and_amount()              # :1130
validate_putaway_capacity(self)              # putaway_rule.py:338
self.validate_inventory_dimension()          # :105
self.validate_uom_is_integer("stock_uom", "qty")
if self._action == "submit":
    self.validate_reserved_stock()            # :829
```

The **current/new bundle pair** (`:280`, `:540`) is the heart of it: a reconciliation must know both
the existing serial/batch composition and the intended one, then post the difference.
`get_bundle_for_specific_serial_batch` (`:459`), `has_change_in_serial_batch` (`:516`),
`update_existing_serial_and_batch_bundle` (`:587`) and
`merge_similar_item_serial_nos` (`:1063`) support it.

`remove_items_with_no_change` (`:606`) with its inner `_changed` (`:612`) drops rows where nothing
actually differs — necessary because the UI fetches *all* items in a warehouse
(`get_items`, `:1264`; `get_items_for_stock_reco`, `:1330`; `get_item_and_warehouses`, `:1316`).

**`validate_inventory_dimension`** (`:105`) is a notable restriction:

```python
for dimension in get_inventory_dimensions():
    for row in self.items:
        if not row.batch_no and row.current_qty and row.get(dimension.get("source_fieldname")):
            frappe.throw(_("Row #{0}: You cannot use the inventory dimension '{1}' in Stock "
                           "Reconciliation to modify the quantity or valuation rate. Stock "
                           "reconciliation with inventory dimensions is intended solely for "
                           "performing opening entries."))
```

So a dimensioned item can be *opened* by reconciliation but not *adjusted* — the guard being
`not row.batch_no and row.current_qty`. Batched rows escape the check entirely.

### 1.2 `update_stock_ledger` — three paths and an "adjustment entry"

`update_stock_ledger` (`:872`). The docstring states the model: *"find difference between current
and expected entries and create stock ledger entries based on the difference"*.

```python
for row in self.items:
    if not row.qty and not row.valuation_rate and not row.current_qty:
        self.make_adjustment_entry(row, sl_entries); continue          # :946
    item = frappe.get_cached_value("Item", row.item_code, ["has_serial_no", "has_batch_no"], as_dict=1)
    if (item.has_serial_no or item.has_batch_no) and not is_standard_cost_item(row.item_code, self.company):
        self.get_sle_for_serialized_items(row, sl_entries)             # :961
    else:
        if row.serial_and_batch_bundle:
            frappe.throw(_("Row #{0}: Item {1} is not a Serialized/Batched Item. ..."))
        previous_sle = get_previous_sle({...})
        if previous_sle:
            if row.qty in ("", None):            row.qty = previous_sle.get("qty_after_transaction", 0)
            if row.valuation_rate in ("", None): row.valuation_rate = previous_sle.get("valuation_rate", 0)
        if row.qty and not row.valuation_rate and not row.allow_zero_valuation_rate:
            frappe.throw(_("Valuation Rate required for Item {0} at row {1}"))
        if (previous_sle and row.qty == previous_sle.get("qty_after_transaction")
                and (row.valuation_rate == previous_sle.get("valuation_rate") or row.qty == 0)) \
           or (not previous_sle and not row.qty):
            continue
        sl_entries.append(self.get_sle_for_items(row))                  # :986
if sl_entries:
    ...
    self.make_sl_entries(sl_entries, allow_negative_stock=allow_negative_stock)
elif self.docstatus == 1:
    frappe.throw(_("No stock ledger entries were created. Please set the quantity or valuation "
                   "rate for the items properly and try again."))
```

Findings:

1. **Blank means "keep current".** `row.qty in ("", None)` and
   `row.valuation_rate in ("", None)` fall back to the previous SLE (`:914`–`:918`). An empty string
   and `None` are both treated as unset — so the *absence* of a value and the *string* `""` are
   interchangeable, which is only meaningful because these are `varchar`-backed form fields.
2. **The no-op detection compares floats directly** (`:924`–`:929`):
   `row.qty == previous_sle.get("qty_after_transaction")` and
   `row.valuation_rate == previous_sle.get("valuation_rate")`. No `flt(x, precision)`. A rate that
   differs in the ninth decimal produces a real SLE with an effectively-zero value change.
3. **`make_adjustment_entry`** (`:946`) is the odd one. When a row has *no* qty, rate, or current
   qty, it posts:

   ```python
   difference_amount = get_stock_value_difference(row.item_code, row.warehouse,
                                                  self.posting_date, self.posting_time, self.name)
   if not difference_amount: return
   args = self.get_sle_for_items(row)
   args.update({"stock_value_difference": -1 * difference_amount, "is_adjustment_entry": 1})
   ```

   An SLE whose `stock_value_difference` is set **directly to the negation of accumulated drift**,
   flagged `is_adjustment_entry = 1`. This is the mechanism that zeroes out valuation discrepancies
   without changing quantity — a *value-only* stock movement. It exists because
   `stock_value_difference` is a stored column that can disagree with the recomputed value
   (doc 02, doc 03).
4. `set_zero_value_for_customer_provided_items` (`:1113`) forces customer-owned stock to zero value.
5. `recalculate_difference_amount_from_ledger` (`:1140`) and
   `get_current_qty_from_ledger` (`:1185`) re-derive the difference after posting;
   `calculate_difference_amount` (`:694`) computes it per row at validate time. **Two computations
   of the same figure**, before and after.
6. `submit` (`:1236`) and `cancel` (`:1247`) are overridden to enqueue when the item count is large
   — the same size-dependent branching as `Journal Entry` (doc 26 §4.7) and PCV (S05 §5.2).
7. `make_sle_on_cancel` (`:1046`) reverses by posting the mirror-image reconciliation.

### 1.3 GL and reserved stock

`get_gl_entries` (`:1091`) routes through the standard stock GL composer (doc 03), with
`validate_expense_account` (`:1098`) ensuring the difference account exists —
`Company.stock_adjustment_account` by default (`:75`–`:78`).

`validate_reserved_stock` (`:829`) runs **only on submit** (`:99`–`:100`) and blocks reducing
quantity below what is reserved (doc 16 §2).

---

## 2. `Item Standard Cost` — the best-designed document in the stock module

`ItemStandardCost` (`stock/doctype/item_standard_cost/item_standard_cost.py:14`). New in v17, and
worth reading closely because it does what the rest of the codebase does not: **it states its
invariants as named rules in comments and enforces them.**

### 2.1 The rules

`validate` (`:32`):

```python
self.validate_item()                                    # :56
self.validate_effective_date()                          # :67
self.validate_rate()                                    # :83
self.warn_backdated_transactions_will_be_blocked()      # :38
```

`validate_item` (`:56`) requires `is_stock_item` **and** that
`get_valuation_method(...) == "Standard Cost"`.

`validate_effective_date` (`:67`) — two rules, each with its reasoning in the source:

```python
# Standard cost is set "as of now"; future-dating would leave a gap where new receipts
# are valued at a rate that is not yet effective.
if getdate(self.effective_date) > getdate(today()):
    frappe.throw(_("Effective Date cannot be a future date."))

# Effective dates must be strictly increasing so the rate history can be read by date.
last = self.get_last_standard_cost()                     # :255
if last and getdate(self.effective_date) <= getdate(last.effective_date):
    frappe.throw(_("Effective Date must be after {0} (the last Standard Cost {1})."))
```

**Strictly increasing effective dates** — which is exactly the `EXCLUDE USING gist` property we
specify for `fx_rate` (S06 §8.2) and `item_price` (doc 17 §7.4), achieved here by validation.

`validate_rate` (`:83`):

```python
if flt(self.standard_rate) <= 0:
    frappe.throw(_("Standard Valuation Rate must be greater than zero."))

if self.get_last_standard_cost() is None:
    # First-ever rate for this item+company: only allowed when no stock movement exists,
    # so the item starts its life under Standard Cost (no historical revaluation needed).
    if self.has_any_sle():                                # :281
        frappe.throw(_("Standard Cost can only be set up for {0} in {1} before any stock "
                       "transaction exists."))
    return

# R1: a rate change must be effective on/after the latest stock activity, so the
# revaluation entry it creates never sits behind existing transactions.
last_sle_date = self.get_last_sle_date()                  # :270
if last_sle_date and getdate(self.effective_date) < getdate(last_sle_date):
    frappe.throw(_("Effective Date cannot be before the last stock transaction date {0}."))
```

**`rate > 0` enforced.** Contrast `get_exchange_rate` returning `0.0` (S06 §2.1).

`warn_backdated_transactions_will_be_blocked` (`:38`) names the second rule explicitly:

> Heads-up while creating (**R2** enforces it later on every stock voucher): once this rate is
> effective, the item's stock transactions cannot be dated before the effective date.

So **R1** = a rate change cannot precede existing stock activity; **R2** = once a rate is effective,
no backdated stock movement is permitted for that item. Together they make standard-cost valuation
*monotonic in time*, which is what makes it safe without a repost engine.

### 2.2 Submit, revaluation, and cancellation

`on_submit` (`:108`):

```python
# Drop any request-cached lookup that may have read the previous (or missing) rate earlier
# in the request, so the revaluation below — and anything else in this request — reads the
# newly submitted rate.
clear_item_standard_rate_cache()                          # :326

# When a Stock Reconciliation captured this rate (opening entry or rate change), it has set
# revaluation_entry to itself and performs the revaluation. Don't spawn another one.
if self.revaluation_entry: return
self.create_revaluation_entry()                           # :182
```

**Explicit cache invalidation with a stated reason**, and **explicit idempotency** via
`revaluation_entry` — a real link, not a content comparison (contrast
`gain_loss_journal_already_booked`, S06 §4.2).

`create_revaluation_entry` (`:182`) posts a Stock Reconciliation revaluing on-hand stock at the new
rate, using `get_revaluation_posting_time` (`:214`) and
`get_warehouse_wise_balance` (`:240`).

`before_cancel` (`:121`) → `validate_no_stock_activity_on_or_after_effective_date` (`:150`) with
`has_stock_activity_on_or_after_effective_date` (`:124`); `on_cancel` (`:165`) unwinds.
**Cancellation is blocked if any stock moved under this rate** — the correct rule.

### 2.3 Variance accounts

`get_purchase_price_variance_account` (`:334`) and
`get_manufacturing_variance_account` (`:356`) are consumed by the GL composers
(S04 §4.5 quoted `_append_receipt_variance_gl_entries` and
`_append_manufacturing_variance_gl_entries`). Standard costing needs variance accounts, and v17
provides them — this is the piece that makes ERPNext's costing genuinely usable for
manufacturing.

`get_item_standard_rate` (`:291`), `has_item_standard_cost` (`:314`),
`get_standard_cost_items` (`:381`) are the accessors, and
`is_standard_cost_item` (`stock/doctype/stock_reconciliation/stock_reconciliation.py:1259`) is the
predicate the reconciliation uses (§1.2) to route serialized items through the *non*-bundle path —
because a standard-cost item's rate does not depend on which serial you picked.

### 2.4 Assessment

This document is the counter-example to most of this investigation's findings: explicit named
invariants, positive rate enforcement, monotonic effective dating, real link-based idempotency,
documented cache invalidation, and cancellation blocked by downstream activity. **We adopt its
rules more or less verbatim** (§7.2).

---

## 3. `Putaway Rule` — capacity by (item, warehouse)

`PutawayRule` (`stock/doctype/putaway_rule/putaway_rule.py:18`).

```python
def validate(self):                          # :40
    self.validate_duplicate_rule()           # :47
    self.validate_warehouse_and_company()    # :63
    self.validate_capacity()                 # :73
    self.validate_priority()                 # :59
    self.set_stock_capacity()                # :88
```

`validate_duplicate_rule` (`:47`) enforces **one rule per (item_code, warehouse)** by
`frappe.db.exists` — a scan, no unique index. `validate_priority` (`:59`) requires `priority >= 1`
but **does not require priorities to be distinct**, so ties are resolved by whatever
`get_ordered_putaway_rules` (`:244`) returns.

`validate_capacity` (`:73`) compares against **current** stock:

```python
balance_qty = get_stock_balance(self.item_code, self.warehouse, nowdate())
if flt(self.stock_capacity) < flt(balance_qty):
    frappe.throw(_("Warehouse Capacity for Item '{0}' must be greater than the existing stock "
                   "level of {1} {2}."), title=_("Insufficient Capacity"))
if not self.capacity:
    frappe.throw(_("Capacity must be greater than 0"), title=_("Invalid"))
```

`set_stock_capacity` (`:88`) is `stock_capacity = (conversion_factor or 1) * capacity` — capacity is
entered in a chosen UOM and stored in stock UOM.

### 3.1 Allocation and the capacity check

`apply_putaway_rule` (`:103`) rewrites a document's item rows, splitting a receipt across
warehouses by rule priority: `get_ordered_putaway_rules` (`:244`),
`add_row` (`:278`), `get_serial_nos_to_allocate` (`:329`),
`show_unassigned_items_message` (`:305`), `_items_changed` (`:204`).

`get_available_putaway_capacity` (`:93`):

```python
stock_capacity, item_code, warehouse = frappe.db.get_value("Putaway Rule", rule,
    ["stock_capacity", "item_code", "warehouse"])
balance_qty = get_stock_balance(item_code, warehouse, nowdate())
free_space = flt(stock_capacity) - flt(balance_qty)
return free_space if free_space > 0 else 0
```

`validate_putaway_capacity` (`:338`) is the enforcement, called from Purchase Receipt,
Stock Entry, Purchase Invoice, and Stock Reconciliation (`:341`–`:346`):

```python
if not frappe.get_all("Putaway Rule", limit=1): return      # ← fast exit if no rules at all
if doc.doctype == "Purchase Invoice" and doc.get("update_stock") == 0: valid_doctype = False
if valid_doctype:
    rule_map = defaultdict(dict)
    for item in doc.get("items"):
        warehouse_field = "t_warehouse" if doc.doctype == "Stock Entry" else "warehouse"
        rule = frappe.db.get_value("Putaway Rule",
            {"item_code": item.get("item_code"), "warehouse": item.get(warehouse_field)},
            ["stock_capacity", "name", "disable"], as_dict=True)
        if rule:
            if rule.get("disable"): continue
            if doc.doctype == "Stock Reconciliation": stock_qty = flt(item.qty)
            else: stock_qty = flt(item.transfer_qty) if doc.doctype == "Stock Entry" else flt(item.stock_qty)
            ...
            rule_map[rule_name]["capacity"] = (rule.stock_capacity
                if doc.doctype == "Stock Reconciliation" else get_available_putaway_capacity(rule_name))
            rule_map[rule_name]["qty_put"] += flt(stock_qty)
    for rule, values in rule_map.items():
        if flt(values["qty_put"]) > flt(values["capacity"]):
            frappe.throw(msg=_prepare_over_receipt_message(rule, values), title=_("Over Receipt"))
```

Four findings:

1. **The quantity field differs per doctype** (`:369`–`:373`): `qty` for Stock Reconciliation,
   `transfer_qty` for Stock Entry, `stock_qty` otherwise. A doctype not in the chain uses
   `stock_qty` whether or not that is the right unit.
2. **The capacity basis differs per doctype** (`:381`–`:384`): Stock Reconciliation compares against
   *total* `stock_capacity` (because it *sets* absolute quantity), everything else against
   *free space*. Correct, and subtle.
3. **`get_stock_balance(..., nowdate())`** (`:97`) — capacity is checked against **today's** balance,
   not the posting date's. A backdated receipt is validated against current stock.
4. **The check is a read-then-write with no lock.** Two concurrent receipts into a
   near-full bin both compute the same `free_space` and both pass.

---

## 4. `Serial No`

`SerialNo(StockController)` (`stock/doctype/serial_no/serial_no.py:28`).

```python
def validate(self):                                                   # :67
    if self.get("__islocal") and self.warehouse and not self.via_stock_ledger:
        frappe.throw(_("New Serial No cannot have Warehouse. Warehouse must be set by "
                       "Stock Entry or Purchase Receipt"), SerialNoCannotCreateDirectError)
    self.set_maintenance_status()                                      # :87
    self.validate_warehouse()                                          # :79

def validate_warehouse(self):                                          # :79
    if not self.get("__islocal"):
        item_code, warehouse = frappe.db.get_value("Serial No", self.name, ["item_code", "warehouse"])
        if not self.via_stock_ledger and item_code != self.item_code:
            frappe.throw(_("Item Code cannot be changed for Serial No."), SerialNoCannotCannotChangeError)
        if not self.via_stock_ledger and warehouse != self.warehouse:
            frappe.throw(_("Warehouse cannot be changed for Serial No."), SerialNoCannotCannotChangeError)
```

Good discipline: a serial's `item_code` and `warehouse` may only be changed **through the stock
ledger** (`via_stock_ledger`, a transient flag). Note the exception class name has a typo —
`SerialNoCannotCannotChangeError` (`:20`).

**`Serial No.warehouse` is a mutable column that tracks current location.** That is the design doc
17 §7.6 replaces with a partial unique index on the serial's current location, because a column
maintained by convention can drift from the ledger.

`on_trash` (`:103`) is the one to note:

```python
sl_entries = frappe.get_all("Stock Ledger Entry",
    filters={"serial_no": ["like", f"%{self.name}%"], "item_code": self.item_code, "is_cancelled": 0},
    fields=["serial_no"])
sle_exists = False
for d in sl_entries:
    if self.name.upper() in get_serial_nos(d.serial_no):
        sle_exists = True; break
if sle_exists:
    frappe.throw(_("Cannot delete Serial No {0}, as it is used in stock transactions"))
```

⚠️ **A `LIKE '%SN-001%'` scan of `tabStock Ledger Entry`, followed by exact matching in Python.**
`Stock Ledger Entry.serial_no` is a **newline-delimited text column** of serial numbers, so
referential integrity for serials is a substring search. `get_serial_nos` (`:147`) splits it;
`clean_serial_no_string` (`:165`) normalises it; `get_serial_nos_from_sle_list` (`:154`) aggregates
across bundles. The `Serial and Batch Bundle` model (doc 17 §6) was introduced to replace this, and
both representations coexist — governed by `Stock Settings.use_serial_batch_fields`.

Other functions: `get_available_serial_nos` (`:123`), `get_new_serial_number` (`:131`),
`auto_fetch_serial_number` (`:187`), `fetch_serial_numbers` (`:261`),
`get_serial_nos_for_outward` (`:295`), `get_pos_reserved_serial_nos` (`:224`, doc 13 §3),
`update_maintenance_status` (`:173`, a scheduled job), `get_items_html` (`:138`),
`on_doctype_update` (`:308`).

`set_maintenance_status` (`:87`) derives `Under Warranty` / `Out of Warranty` / `Under AMC` /
`Out of AMC` from two date fields — and the four `if` statements are **sequential, not exclusive**
(`:88`–`:101`), so the last matching condition wins. A serial under warranty and out of AMC ends up
`Under Warranty` purely because that check is last.

---

## 5. `Product Bundle`, `Packing Slip`, and logistics

### 5.1 `Product Bundle` — versioned, and done well

`ProductBundle` (`selling/doctype/product_bundle/product_bundle.py:16`) is submittable and
**versioned**, which is unusual and correct.

`autoname` (`:35`) — the docstring explains the scheme:

> BOM-style versioned name: `PB-<parent item>-001`. Amended copies are excluded while computing the
> current index so that an amendment naturally becomes the next version of the bundle.

```python
search_key = f"{NAME_PREFIX}-{self.new_item_code}-%"
existing = frappe.get_all("Product Bundle",
    filters={"name": ("like", search_key), "amended_from": ["is", "not set"]}, pluck="name")
index = get_next_version_index(existing)                    # :165
self.name = build_bundle_name(self.new_item_code, index)    # :153
```

`build_bundle_name` (`:153`) truncates the item part to keep the name within 140 characters —
the `varchar(140)` PK limit leaking into naming logic (doc 09 §6).
`get_next_version_index` (`:165`) parses the trailing index by splitting on `/` or `-`:

```python
pattern = "|".join(re.escape(delim) for delim in ("/", "-"))
parts = [re.split(pattern, name) for name in existing_names]
valid = [p for p in parts if len(p) > 1 and p[-1]]
return max(cint(p[-1]) for p in valid) + 1 if valid else 1
```

An item code containing a hyphen therefore contributes its own trailing segment to the version
parse. `cint()` of a non-numeric segment is 0, so it degrades rather than crashes.

`make_active` (`:72`) maintains **one active version per parent item**:

```python
if not self.is_active: self.db_set("is_active", 1)
others = frappe.get_all("Product Bundle",
    filters={"new_item_code": self.new_item_code, "is_active": 1, "docstatus": 1,
             "name": ("!=", self.name)}, pluck="name")
for name in others:
    frappe.db.set_value("Product Bundle", name, "is_active", 0)
```

Read-then-write, unlocked — two concurrent activations both deactivate the other and both set
themselves active. A partial unique index (`UNIQUE (new_item_code) WHERE is_active`) makes it
structural.

`get_active_product_bundle` (`:175`) is the single resolution entry point, and its docstring records
the migration:

> This is the single resolution entry point for every consumer of bundles; it replaces the legacy
> `exists("Product Bundle", {name/new_item_code, disabled: 0})` lookups that assumed one mutable
> bundle per item.

`on_update_after_submit` (`:64`) documents the `is_active` vs `disabled` distinction: `disabled`
parks a version *without ceding the active slot*. Two orthogonal booleans, clearly reasoned.

`make_new_version` (`:194`) with `post_process` (`:202`); `validate_main_item` (`:127`),
`validate_child_items` (`:134`), `validate_child_items_qty_non_zero` (`:143`);
`on_trash` (`:91`) checks a hard-coded list of eight linked doctypes.

### 5.2 `Packing Slip`

`PackingSlip(StatusUpdater)` (`stock/doctype/packing_slip/packing_slip.py:13`).

`validate_delivery_note` (`:79`): *"A Packing Slip can only be created for a Draft Delivery Note."*
So packing precedes shipping, strictly.

`validate_case_nos` (`:85`) is a genuine range-overlap check:

```python
if cint(self.from_case_no) <= 0:
    frappe.throw(_("The 'From Package No.' field must not be empty or have a value less than 1."))
elif not self.to_case_no: self.to_case_no = self.from_case_no
elif cint(self.to_case_no) < cint(self.from_case_no):
    frappe.throw(_("'To Package No.' cannot be less than 'From Package No.'"))
else:
    res = (frappe.qb.from_(ps).select(ps.name).where(
        (ps.delivery_note == self.delivery_note) & (ps.docstatus == 1)
        & ((ps.from_case_no.between(self.from_case_no, self.to_case_no))
           | (ps.to_case_no.between(self.from_case_no, self.to_case_no))
           | ((ps.from_case_no <= self.from_case_no) & (ps.to_case_no >= self.from_case_no))))).run()
    if res:
        frappe.throw(_("""Package No(s) already in use. Try from Package No {0}""")
                     .format(self.get_recommended_case_no()))
```

Three OR'd conditions to express range overlap, and note the `elif` chain means **the overlap check
is skipped entirely when `to_case_no` was defaulted from `from_case_no`** (`:93`) — a single-package
slip is never checked against existing ranges. `get_recommended_case_no` (`:170`) suggests the next
free number; `calculate_net_total_pkg` (`:184`) totals weights.

An `EXCLUDE USING gist` on `(delivery_note, int4range(from_case_no, to_case_no, '[]'))` replaces all
of it, including the skipped case.

### 5.3 `Delivery Trip` and `Shipment`

`DeliveryTrip` (`stock/doctype/delivery_trip/delivery_trip.py:14`) — route planning with
Google Maps integration: `process_route` (`:153`), `form_route_list` (`:206`),
`rearrange_stops` (`:244`), `get_directions` (`:266`), `sanitize_address` (`:379`),
`notify_customers` (`:400`), `get_attachments` (`:447`), `get_driver_email` (`:466`).

`update_status` (`:100`) derives trip status from the visited flags:

```python
status = {0: "Draft", 1: "Scheduled", 2: "Cancelled"}[self.docstatus]
if self.docstatus == 1:
    visited_stops = [stop.visited for stop in self.delivery_stops]
    if all(visited_stops):   status = "Completed"
    elif any(visited_stops): status = "In Transit"
self.db_set("status", status)
```

Clean — and note `all([])` is `True` in Python, so a trip with **no stops** is `Completed`.

`update_delivery_notes` (`:112`) pushes driver/vehicle details **onto the linked Delivery Notes**,
and `on_trash` / `on_cancel` (`:68`, `:77`) call it with `delete=True` to strip them. So a trip
mutates submitted Delivery Notes (doc 09 §3.2's pattern).

`validate_delivery_note_not_draft` (`:86`) blocks submitting a trip whose Delivery Notes are still
draft — the inverse of Packing Slip's rule (§5.2).

`Shipment` (`stock/doctype/shipment/shipment.py:14`) is the third-party-carrier document:
`validate_weight` (`:94`), `set_total_weight` (`:99`), `get_total_weight` (`:102`),
`validate_pickup_time` (`:105`), `set_value_of_goods` (`:109`).

⚠️ `set_value_of_goods` (`:109`):

```python
value_of_goods = 0
for entry in self.get("shipment_delivery_note"):
    value_of_goods += flt(entry.get("grand_total"))
self.value_of_goods = value_of_goods if value_of_goods else self.value_of_goods
```

The final line **keeps the previous value when the computed total is zero** — so a manually entered
`value_of_goods` survives, but so does a stale one. And `on_submit` (`:84`) then throws if
`value_of_goods == 0`, meaning the fallback exists specifically to let a manual value through.

`status` is maintained by `db_set` in `validate`/`on_submit`/`on_cancel`
(`stock/doctype/shipment/shipment.py:82`, `:89`, `:92`) with no state machine.

### 5.4 `Stock Entry Type`

`StockEntryType` (`stock/doctype/stock_entry_type/stock_entry_type.py:16`):

```python
def validate(self):                                     # :44
    self.validate_standard_type()                       # :49
    if self.add_to_transit and self.purpose != "Material Transfer":
        self.add_to_transit = 0                         # ← silently corrected

def validate_standard_type(self):                       # :49
    if self.is_standard and self.name not in [
        "Material Issue", "Material Receipt", "Material Transfer",
        "Material Transfer for Manufacture", "Material Consumption for Manufacture",
        "Manufacture", "Repack", "Send to Subcontractor", "Disassemble",
        "Receive from Customer", "Return Raw Material to Customer",
        "Subcontracting Delivery", "Subcontracting Return"]:
        frappe.throw(_("Stock Entry Type {0} cannot be set as standard"))
```

**Thirteen hard-coded standard type names, matched against the PK.** So `Stock Entry Type` is a
user-extensible master whose *standard* members are identified by string equality with a Python
list — and `Stock Entry.purpose` (nine values, S04 §2) is a separate `Select` field. A custom type
maps to one of the nine purposes; the purpose drives behaviour.

The same file also contains `ManufactureEntry` (`:68`) — a helper class building manufacture stock
entries (`make_stock_entry` `:73`, `add_raw_materials` `:107`, `add_finished_good` `:311`,
`get_items_from_job_card` `:269`, `parse_available_serial_batches` `:148`) which belongs to
**Tranche B**; noted here only because it lives in this module.

---

## 6. `Stock Ledger Entry` — the document, as opposed to the algorithm

Doc 02 covered `stock/stock_ledger.py`: the valuation algorithm that *writes* SLE rows. The SLE
**doctype controller** is a separate body of rules, and it is where the row-level guards live:
`StockLedgerEntry` (`stock/doctype/stock_ledger_entry/stock_ledger_entry.py:37`).

### 6.1 `autoname` — named twice on purpose

```python
def autoname(self):                                    # :77
    self.name = frappe.generate_hash(txt="", length=10)
    if self.meta.autoname == "hash":
        self.to_rename = 0
```

A random hash at insert time, with a `to_rename` flag telling a **scheduled job** to apply the real
naming series later (doc 20 §4 covers `rename_gle_sle_docs`, the same trick on `GL Entry`). Inserting
thousands of ledger rows must not serialise on a naming-series counter, so naming is deferred.

> **Ours** No renaming job at all. Ledger rows get a `bigint` identity PK and no human-facing series.
> A document number is a property of the *voucher*, never of a ledger row. This deletes an entire
> background job, its failure modes, and the `to_rename` column.

### 6.2 `validate` — ten checks, and the ordering is not arbitrary

`validate` (`:86`):

```python
self.set_posting_datetime()                       # :101  posting_date + posting_time -> one column
self.validate_mandatory()                         # :194
self.validate_batch()                             # :287
validate_disabled_warehouse(self.warehouse)
validate_warehouse_company(self.warehouse, self.company)
self.scrub_posting_time()                         # :283
self.validate_and_set_fiscal_year()               # :301
self.block_transactions_against_group_warehouse() # :311
self.validate_with_last_transaction_posting_time()# :316
self.validate_inventory_dimension_negative_stock()# :106
```

Notable behaviours:

- **`validate_mandatory` (`:194`)** requires `warehouse, posting_date, voucher_type, voucher_no,
  company`, then requires a non-zero `actual_qty` **except for `Stock Reconciliation`** — the
  rate-only revaluation row (§2) legitimately moves zero quantity.
- **`scrub_posting_time` (`:283`)** repairs `posting_time == "00:0"`. A defensive string fix-up that
  exists because `posting_time` is stored as text.
- **`validate_batch` (`:287`)** rejects posting against an **expired** batch, but exempts
  `Stock Entry` entirely, and exempts returns (negative PR/PI, positive DN/SI) — you must always be
  able to take expired stock back off the books.
- **`block_transactions_against_group_warehouse` (`:311`)** — leaf warehouses only.
- **`validate_and_set_fiscal_year` (`:301`)** derives the fiscal year if absent, else validates it.
  Note this makes an inventory row carry an *accounting* period attribute.

### 6.3 Negative stock is enforced per inventory dimension, separately

`validate_inventory_dimension_negative_stock` (`:106`) is a **second, independent** negative-stock
check, distinct from the one in the valuation engine (doc 02 §2.7,
`validate_negative_qty_in_future_sle`). It fires only when `actual_qty < 0`, and only for
`Inventory Dimension` rows with `validate_negative_stock` set (`_get_inventory_dimensions` `:162`).

```python
available_qty = SUM(actual_qty)                                 # :121
   WHERE item_code = ? AND warehouse = ? AND company = ?
     AND posting_datetime < self.posting_datetime AND is_cancelled = 0
     AND <each dimension> = <value>
diff = available_qty + self.actual_qty
if diff < 0 and abs(diff) > 0.0001:                             # :117
    throw InventoryDimensionNegativeStockError                  # :143
```

Two problems worth naming:

1. **It looks only backwards.** `posting_datetime < self.posting_datetime`. A backdated issue is
   checked against history but nothing re-checks the *future* rows for the dimension, unlike the
   main engine which does exactly that. So dimension-level negative stock can be created by
   backdating.
2. **`0.0001` is a hard-coded tolerance** on a quantity comparison, sitting beside a
   `float_precision` default that is read but only used to round `diff`.

> **Ours** One negative-stock rule, evaluated on one projection. `stock_on_hand` is keyed by
> `(company_id, item_id, warehouse_id, dim1..dim4)` — the dimension case is not a special path, it
> is the same unique key with more columns bound. The check runs as a deferred constraint over the
> projection after all rows of the voucher are applied, so backdating is caught in both directions
> by construction. Tolerance is `0` at `numeric(21,9)`.

### 6.4 `on_submit` — bundle creation, and two escape hatches

`on_submit` (`:174`) calls `check_stock_frozen_date` (`:255`), then returns early if
`frappe.in_test and frappe.flags.ignore_serial_batch_bundle_validation`, and again if
`is_adjustment_entry`. Otherwise it constructs `SerialBatchBundle(...)` unless
`via_landed_cost_voucher`, then `validate_serial_batch_no_bundle` (`:203`).

`validate_serial_batch_no_bundle` also **writes to the row it is validating**: if `has_batch_no` /
`has_serial_no` disagree with the Item master it issues a `db_set` to correct them (`:225`-`:231`).
A validation method performing a repair write is exactly the pattern our design forbids — the value
should not be duplicated onto the ledger row at all.

It then enforces: item exists; template items (`has_variants`) can never hold stock
(`ItemTemplateCannotHaveStock`); `is_stock_item` must be 1; a bundle is **mandatory** when the item
has serial or batch tracking, **unless** `is_standard_cost_revaluation` (`:243`) — a Stock
Reconciliation on a Standard Cost item changes only the rate, so it carries no bundle; and
conversely a bundle is **forbidden** when the item tracks neither.

### 6.5 Two more freeze mechanisms

`check_stock_frozen_date` (`:255`) adds `Stock Settings.stock_frozen_upto` (an absolute date) **and**
`stock_frozen_upto_days` (a rolling window), both bypassed by `stock_auth_role`, raising
`StockFreezeError`. `validate_with_last_transaction_posting_time` (`:316`) is a third: if
`Stock Settings.role_allowed_to_create_edit_back_dated_transactions` is set, a user outside that role
cannot post earlier than `MAX(posting_datetime)` for that `(item, warehouse)`, raising
`BackDatedStockTransaction` — note it is skipped entirely when the setting is blank, so the default
configuration permits unrestricted backdating.

Together with the accounting freezes catalogued in doc 07, this is why decision 22 collapses **all**
period control into one `accounting_period.state` enum plus an audited `period_override`.

### 6.6 `on_cancel` is a hard refusal

```python
def on_cancel(self):                                  # :358
    frappe.throw(_("Individual Stock Ledger Entry cannot be cancelled."))
```

The row is only ever retired by cancelling its voucher, which flips `is_cancelled` in bulk. This is
the right instinct, implemented as a runtime exception rather than a schema property.

> **Ours** `stock_move` has no cancel path to refuse: no `UPDATE`/`DELETE` grant, enforced by
> `REVOKE` plus a trigger, so the guarantee holds for every connection rather than for callers who
> go through the ORM (doc 19 lists the eight ways ERPNext's app-level checks are bypassed).

### 6.7 The indexes are declared in code, and one is Postgres-only

`on_doctype_update` (`:364`) adds `(voucher_no, voucher_type)` and
`(item_code, warehouse, posting_datetime, creation)`, plus — **on Postgres only** — a partial index
`sle_active_posting (company, posting_datetime, creation) WHERE is_cancelled = 0`, with a comment
explaining that the item-leading composite cannot serve an all-items date scan for the Stock Ledger
and Stock Balance reports.

This is the same pattern as the `GL Entry` partial indexes in doc 01 §1.6: upstream has already
worked out which Postgres partial indexes the ledger reports need. Both are directly reusable, and
in our schema they are ordinary migration DDL rather than a hook that runs on every migrate.

---

## 7. Our design

### 7.1 Reconciliation is a normal movement with an absolute target

```sql
CREATE TABLE stock_count (                       -- replaces Stock Reconciliation
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     uuid NOT NULL REFERENCES company(id),
    voucher_id     uuid NOT NULL UNIQUE REFERENCES voucher(id),
    purpose        stock_count_purpose NOT NULL,   -- 'opening','physical_count','valuation_correction'
    difference_account_id uuid NOT NULL REFERENCES account(id),
    counted_at     timestamptz NOT NULL
);
CREATE TABLE stock_count_line (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_count_id    uuid NOT NULL REFERENCES stock_count(id) ON DELETE CASCADE,
    line_no           smallint NOT NULL,
    item_id           uuid NOT NULL REFERENCES item(id),
    warehouse_id      uuid NOT NULL REFERENCES warehouse(id),
    serial_batch_id   uuid REFERENCES serial_batch(id),
    -- the observation, not the delta
    counted_qty       numeric(21,9),
    counted_rate      numeric(21,9),
    -- snapshotted for audit, never used for arithmetic
    system_qty_at_count  numeric(21,9) NOT NULL,
    system_rate_at_count numeric(21,9) NOT NULL,
    UNIQUE (stock_count_id, item_id, warehouse_id, serial_batch_id),
    CONSTRAINT sc_something_counted CHECK (counted_qty IS NOT NULL OR counted_rate IS NOT NULL)
);
```

- **`NULL` means "not counted"** — a real three-valued distinction, not `"" or None`
  interchangeably (§1.2 finding 1).
- The **delta is computed by the posting routine** and emitted as ordinary `stock_move` rows plus a
  `valuation_adjustment` row (S04 §8.3) — so there is no `is_adjustment_entry` flag and no SLE with
  a hand-set `stock_value_difference` (§1.2 finding 3). Value-only corrections are
  `valuation_adjustment` rows, which is what that construct already is.
- **No-change detection compares at the column's scale** (`numeric(21,9)`), not with float `==`
  (§1.2 finding 2).
- `system_qty_at_count` / `system_rate_at_count` make the count **auditable**: what the system
  believed versus what was found, retained forever. ERPNext recomputes it twice and keeps neither
  (§1.2 finding 5).
- The `UNIQUE` key prevents the same item/warehouse/batch appearing twice in one count —
  ERPNext relies on `validate_duplicate_serial_and_batch_bundle`.

### 7.2 Standard cost — adopted, with the rules as constraints

```sql
CREATE TABLE item_standard_cost (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES company(id),
    item_id        uuid NOT NULL REFERENCES item(id),
    standard_rate  numeric(21,9) NOT NULL CHECK (standard_rate > 0),
    effective_from date NOT NULL,
    effective_to   date NOT NULL DEFAULT 'infinity',
    revaluation_voucher_id uuid REFERENCES voucher(id),
    EXCLUDE USING gist (
        company_id WITH =, item_id WITH =,
        daterange(effective_from, effective_to, '[)') WITH &&
    )
);
```

- **`CHECK (standard_rate > 0)`** — ERPNext's `validate_rate` (§2.1) as a constraint.
- **`EXCLUDE USING gist`** — ERPNext's strictly-increasing effective dates (§2.1) as a constraint,
  and it additionally gives contiguity when `effective_to` is maintained.
- **R1** (a rate change is effective on/after the latest stock activity) and **R2** (no backdated
  movement once a rate is effective) become **deferred constraint triggers** on `stock_move`,
  checked against `item_standard_cost` — so R2 is enforced on every insert rather than by
  remembering to call a validator on every voucher type.
- `revaluation_voucher_id` is already the link-based idempotency ERPNext uses (§2.2) — kept.
- Variance accounts (§2.3) become `account_type IN ('purchase_price_variance',
  'manufacturing_variance')` resolved per company, with a `CHECK` that they are P&L accounts.

### 7.3 Putaway becomes capacity on the location

```sql
CREATE TABLE storage_capacity (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    warehouse_id  uuid NOT NULL REFERENCES warehouse(id),
    location_id   uuid REFERENCES warehouse_location(id),
    item_id       uuid REFERENCES item(id),
    item_group_id uuid REFERENCES item_group(id),
    capacity_qty_stock numeric(21,9) NOT NULL CHECK (capacity_qty_stock > 0),
    priority      smallint NOT NULL,
    is_enabled    boolean NOT NULL DEFAULT true,
    CONSTRAINT cap_one_target CHECK ((item_id IS NULL) <> (item_group_id IS NULL)),
    UNIQUE (company_id, warehouse_id, location_id, item_id, item_group_id),
    UNIQUE (company_id, warehouse_id, priority)          -- ← priorities are distinct
);
```

- **`UNIQUE (…, priority)`** removes the tie-break ambiguity (§3).
- **`item_group_id`** allows a capacity rule for a category — ERPNext requires one rule per item.
- Enforcement is a **deferred constraint trigger on `stock_move`** comparing
  `stock_on_hand.qty_on_hand` (already row-locked, doc 16 §5.1) against capacity **as at the
  posting date**, not `nowdate()` (§3 finding 3), and under the lock (§3 finding 4).
- Quantity is always `qty_stock` — no per-doctype field chain (§3 finding 1).
- The "absolute vs incremental" distinction (§3 finding 2) is explicit: `stock_count` posts a
  computed delta like everything else, so the capacity check has one formulation.

### 7.4 Serial numbers

Per doc 17 §7.6: `serial_batch` rows with `kind = 'serial'`, and current location tracked by the
`stock_move` ledger rather than a mutable `warehouse` column.

- **No `LIKE '%SN%'` scan.** `stock_move.serial_batch_id` is a real FK, so "is this serial used?" is
  an indexed `EXISTS`, and deletion is prevented by `ON DELETE RESTRICT` rather than a Python loop
  over a substring match (§4).
- **No newline-delimited serial text column.** The dual representation governed by
  `Stock Settings.use_serial_batch_fields` does not exist.
- `maintenance_status` becomes a **generated column** from the two expiry dates with an explicit
  precedence rule, not four sequential `if`s where the last wins (§4).

### 7.5 Bundles, packing, logistics

- **`product_bundle`**: keep the versioning; replace the "one active per item" scan with
  `CREATE UNIQUE INDEX ON product_bundle (item_id) WHERE is_active AND NOT disabled` (§5.1). Version
  numbering comes from a `numbering_series` (doc 20 §3.2), not by parsing the PK on `-`/`/`.
- **`packing_slip`**: `EXCLUDE USING gist` on `(delivery_note_id, int4range(from_case_no,
  to_case_no, '[]'))` — covering the single-package case ERPNext skips (§5.2).
- **`delivery_trip`**: a trip does **not** write to delivery notes. `trip_stop` rows reference the
  delivery, and driver/vehicle live on the trip; the delivery's shipping details are a view over
  its trip (§5.3). `status` is derived from `trip_stop.visited_at IS NOT NULL`, with
  `count(*) = 0 → 'empty'` rather than `all([]) = True → Completed`.
- **`shipment`**: `value_of_goods` is either derived or explicitly overridden with
  `value_override_reason` — never "keep the old value if the computed one is zero" (§5.3).
- **`stock_entry_type`**: the nine purposes become the `stock_document_kind` enum on separate
  tables (S04 §8.1); a user-defined "type" is a `stock_reason_code` row referencing a purpose, so
  the thirteen-name hard-coded list (§5.4) has no analogue.

---

## 8. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| `Stock Reconciliation` as qty+rate override | **Keep the capability** | `stock_count` with absolute observations; deltas computed on posting |
| `""` and `None` both mean "unset" | **Reject** | `NULL` only |
| No-change detection by float `==` | **Reject** | `numeric` comparison at column scale |
| `is_adjustment_entry` SLE with hand-set `stock_value_difference` | **Reject** | `valuation_adjustment` rows (S04 §8.3) |
| Difference recomputed before and after posting | **Reject** | computed once; observations retained |
| Inventory dimensions blocked from adjustment (opening only) | **Reject** | dimensions are ordinary FK slots on `stock_move` |
| **`Item Standard Cost` rules R1/R2, `rate > 0`, monotonic dates, link-based idempotency** | **ADOPT** | as constraints + deferred triggers (§7.2) |
| Standard-cost variance accounts | **Keep** | typed `account_type` values |
| `Putaway Rule` one-per-(item,warehouse) by scan | **Reject** | `UNIQUE`, plus item-group rules |
| Non-distinct priorities | **Reject** | `UNIQUE (company, warehouse, priority)` |
| Capacity vs `nowdate()` balance | **Reject** | vs posting-date balance, under the row lock |
| Per-doctype quantity field chain | **Reject** | `qty_stock` always |
| `Serial No.warehouse` mutable column | **Reject** | location from the ledger (doc 17 §7.6) |
| `LIKE '%SN%'` scan for serial integrity | **Reject** | FK + `ON DELETE RESTRICT` |
| Newline-delimited `serial_no` text | **Reject** | `serial_batch_id` FK |
| `maintenance_status` by 4 sequential `if`s | **Reject** | generated column with explicit precedence |
| `Product Bundle` versioning + `is_active`/`disabled` split | **Keep** | plus a partial unique index |
| Version index parsed from the PK on `-`/`/` | **Reject** | `numbering_series` |
| `Packing Slip` case-range overlap check (skipped for single packages) | **Reject** | `EXCLUDE USING gist` |
| `Delivery Trip` writing to submitted Delivery Notes | **Reject** | trip owns its own rows; delivery reads a view |
| `all([]) → Completed` for an empty trip | **Reject** | explicit `empty` state |
| `Shipment.value_of_goods` keeping a stale value when computed is 0 | **Reject** | derived, or explicit override with a reason |
| `Stock Entry Type` standard members by hard-coded name list | **Reject** | `stock_document_kind` enum + `stock_reason_code` rows |
| SLE named by hash then renamed by a scheduled job | **Reject** | `bigint` identity PK; series belong to vouchers (§6.1) |
| Two independent negative-stock checks, one backward-only | **Reject** | one deferred check over `stock_on_hand`, dimensions in the key (§6.3) |
| `0.0001` hard-coded qty tolerance | **Reject** | exact `numeric(21,9)` comparison |
| `validate` repairing `has_batch_no`/`has_serial_no` via `db_set` | **Reject** | not duplicated onto the ledger row at all (§6.4) |
| Three more freeze mechanisms in Stock Settings | **Reject** | one `accounting_period.state` + `period_override` (decision 22, §6.5) |
| `on_cancel` refusing at runtime | **Keep the rule** | enforced by `REVOKE` + trigger, not an exception (§6.6) |
| Postgres partial index `WHERE is_cancelled = 0` for ledger reports | **ADOPT** | as migration DDL, not a migrate-time hook (§6.7) |

---

Cross-references: doc 02 (stock ledger and valuation methods), doc 03 (stock↔GL bridge),
doc 16 (reservation, picking, warehouse structure), doc 17 (item master, serial/batch, FEFO),
doc 26 §3.5 (`Inventory Dimension`),
**[S04](../scenarios/S04-stock-transfer-and-in-transit.md)** (Stock Entry and transfers),
**[S05](../scenarios/S05-period-close-and-opening-balances.md)** §6–§7 (Stock Closing Entry,
opening stock), `docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
