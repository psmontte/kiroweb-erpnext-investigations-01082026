# 33 — BOM Costing, Explosion and Update Jobs

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev)
> and `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`, or are prefixed
> `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

This is the first Tranche B document. It covers the structure that every production flow consumes:
`BOM`, its four child tables, the recursive tree and flat explosion, exact costing, `BOM Creator`, and
the two site-wide mutation paths behind `BOM Update Tool` / `BOM Update Log`.

The central finding is that ERPNext stores **three representations of one recipe** — direct BOM rows,
a recursively flattened `BOM Explosion Item` table, and copied rates/totals on every ancestor — then
maintains them by delete/reinsert and background mutation. The cost updater understands dependency
order but is non-atomic and has no durable restart protocol; BOM replacement does not even preserve
dependency order. That distinction is the design boundary for ours: approved recipe revisions are
immutable sources, explosion and cost are reproducible projections, and a projection refresh never
rewrites historical production valuation.

---

## 1. Data model — a recipe, four child tables, and copied totals

### 1.1 `BOM`

`BOM` is a submittable `WebsiteGenerator`, not a stock or accounting transaction. Its controller
contains four groups of persisted state (`manufacturing/doctype/bom/bom.py:127-206`):

| Concern | Meaningful fields |
|---|---|
| Output and identity | `company`, manufactured `item`, output `quantity`, stock `uom`, `project`; the generated name is a per-item `BOM-<item>-NNN` version-like code (`manufacturing/doctype/bom/bom.py:213-283`) |
| Structure and execution | `items`, `operations`, `secondary_items`; `with_operations`, `routing`, `track_semi_finished_goods`, `transfer_material_against`, `backflush_based_on`, `is_phantom_bom`, source/target warehouses |
| Cost policy | `rm_cost_as_per`, `buying_price_list`, `price_list_currency`, `plc_conversion_rate`, BOM `currency`, `conversion_rate`, `set_rate_of_sub_assembly_item_based_on_bom`, finished-good-based operating-cost flags |
| Copied results | transaction- and company-currency operating, raw-material, secondary-item and total costs; finished-good allocation and process-loss values; the persisted `exploded_items` projection |
| Lifecycle | `is_active`, `is_default`, `amended_from`, and `bom_creator` / untyped `bom_creator_item` provenance |

`conversion_rate` has schema precision 9, but cost and quantity columns otherwise use Frappe's
site/field precision rather than a BOM-wide fixed decimal contract. That becomes important in §4:
the calculation code explicitly rounds only selected intermediates.

### 1.2 Source children

The three source child controllers are passive `Document` classes; their generated Python field
blocks are therefore the concise database contract:

- **`BOM Item`** carries the component identity, direct/nested `bom_no`, `do_not_explode`, operation
  and semi-finished-operation association, quantity/UOM/conversion/stock quantity, transaction and
  base rates/amounts, source warehouse, manufacturing/supplier flags, and phantom/subassembly flags
  (`manufacturing/doctype/bom_item/bom_item.py:7-42`).
- **`BOM Operation`** carries sequence, workstation or workstation type, minutes/fixed-time/batch
  size, transaction/base rates and costs, optional semi-finished output and BOM, transfer/WIP/FG
  warehouses, subcontract and inspection flags (`manufacturing/doctype/bom_operation/bom_operation.py:7-44`).
- **`BOM Secondary Item`** carries co-product/by-product/scrap/additional-FG type, output quantity and
  UOM conversion, cost-allocation percentage, process-loss percentage/quantity, allocated cost, and
  a legacy rate representation (`manufacturing/doctype/bom_secondary_item/bom_secondary_item.py:8-36`).

These rows are sources only in an application-level sense. They are ordinary mutable child records;
there is no database rule that freezes them when the parent is submitted. `BOM.update_cost` sets
`ignore_validate_update_after_submit` and directly updates rows and the parent when refreshing cost
(`manufacturing/doctype/bom/services/costing.py:67-94`).

### 1.3 The fourth child is a materialised projection

**`BOM Explosion Item`** has item, operation, source warehouse, stock quantity/UOM, company-currency
rate/amount, per-unit consumption and manufacturing/supplier/subassembly flags
(`manufacturing/doctype/bom_explosion_item/bom_explosion_item.py:7-32`). It is not user-authored
recipe data. It is a flattened leaf projection rebuilt from `BOM Item` and already-built child
explosions (§5), yet it is stored as child rows and queried directly by production consumers.

> **Ours — source/projection boundary.** A versioned `bom_revision` owns source `bom_component`,
> `bom_operation` and `bom_secondary_output` rows. An approved revision is immutable; change means a
> new revision with `supersedes_id`. `bom_explosion` and `bom_cost_snapshot` are labelled projections
> carrying `source_revision_id`, algorithm version and `computed_at`. They may be deleted and rebuilt
> without changing the recipe or any posted production movement.

---

## 2. Save, submit, cancel and default-BOM lifecycle

### 2.1 Validation is an ordered mutation pipeline

Before validation, missing component conversion factors are looked up by `(item, uom)` and default to
1 (`manufacturing/doctype/bom/bom.py:286-297`). `validate` then runs three ordered phases
(`manufacturing/doctype/bom/bom.py:299-340`):

1. **Setup:** clear operations when disabled, clear inspection when disabled, hydrate the main item,
   validate currencies, import operation-BOM materials for semi-finished tracking, establish exchange
   rates, and apply whole-number UOM checks.
2. **Materials and cost:** hydrate component and secondary rows, validate materials/transfer/routing/
   operations, calculate cost, construct the explosion in memory, update stock quantities, and run a
   second cost calculation without saving or propagating to parents.
3. **UOM and outputs:** calculate process loss, validate UOMs, normalise stock UOMs, validate
   semi-finished and secondary outputs, allocate finished-good cost, and require total allocation of
   exactly 100%.

That ordering is not merely organisational. The first explosion is computed **before**
`update_stock_qty`. If a user edits a row quantity/UOM while the row retains an old non-zero
`stock_qty`, material hydration fills only falsey fields, the explosion consumes the old quantity,
and the later second cost calculation does not rebuild it (`manufacturing/doctype/bom/bom.py:318-331`,
`manufacturing/doctype/bom/bom.py:527-618`, `manufacturing/doctype/bom/bom.py:696-705`).

⚠️ **Finding — an ordinary BOM save can persist a stale flat quantity.** This is a direct consequence
of the validation order. The source component receives its new `stock_qty`; the in-memory explosion
can still describe its previous quantity.

### 2.2 Material and operation gates

A BOM requires at least one component. Every component must have positive `qty`; a linked BOM is
validated; and fixed-asset items are rejected (`manufacturing/doctype/bom/bom.py:718-740`). A linked
BOM must be active and submitted (the submission check is disabled in tests), and the requested item
is accepted if it is the BOM output, its variant template, **or any component or secondary item in
that BOM** (`manufacturing/doctype/bom/bom.py:1425-1455`).

⚠️ The last rule is broader than “this BOM produces this component”: a BOM Item can point at a BOM in
which its item merely appears as a raw material. Secondary outputs explain part of the breadth, but a
component match does not prove output ownership.

When operations are enabled, submission requires at least one operation. Every operation defaults
`batch_size` to 1, requires a workstation or workstation type, and requires positive minutes
(`manufacturing/doctype/bom/bom.py:924-956`). A routing is copied by `(sequence_id, idx)` and its
company-currency hour rate is divided by the BOM conversion rate
(`manufacturing/doctype/bom/bom.py:486-526`). Semi-finished tracking requires exactly one operation
marked as the final finished good, and every operation without its own BOM must have a component
linked through `operation_row_id` (`manufacturing/doctype/bom/bom.py:342-413`).

Secondary outputs cannot equal the main finished good unless they are legacy rows; their process-loss
percentage must be below 100 (`manufacturing/doctype/bom/bom.py:378-397`). The finished-good and all
secondary allocation percentages must sum to **exactly** 100; if the FG starts at 100, validation
silently reduces it by the secondary percentages (`manufacturing/doctype/bom/bom.py:458-474`).

### 2.3 Submit, update-after-submit and cancel

Every save clears the child-tree cache and checks recursion. Submit then manages the default BOM and,
if applicable, writes progress back to `BOM Creator` (`manufacturing/doctype/bom/bom.py:423-458`).
The allow-on-submit active/default fields are checked again after an update to a submitted BOM
(`manufacturing/doctype/bom/bom.py:476-478`).

Cancellation first `db_set`s `is_active = 0` and `is_default = 0`, then refuses the operation if a
submitted active parent still links to this BOM, updates the default pointer, and updates Creator
status (`manufacturing/doctype/bom/bom.py:433-458`, `manufacturing/doctype/bom/bom.py:892-923`). The
pre-validation writes remain in the same request transaction and therefore normally roll back when
link validation throws, but they bypass the normal field-level audit path.

### 2.4 “Default” is two denormalised values

An active selected BOM invokes Frappe's `set_default` over sibling BOMs and writes
`Item.default_bom`. If no submitted default exists, any active BOM being processed promotes itself.
Otherwise it unsets itself; cancellation/deactivation clears `Item.default_bom` if it points here
(`manufacturing/doctype/bom/bom.py:620-642`).

⚠️ Cancelling the default does **not** elect another submitted active BOM. The item may have usable
BOMs but no default. The same fact is represented by both `BOM.is_default` and `Item.default_bom`,
maintained by controller writes rather than one uniqueness/FK rule.

> **Invariant M1 — revision lifecycle.** A production document references one approved, effective BOM
> revision. Approval freezes its structure, quantities, UOMs and cost policy; cancellation/supersession
> never edits the revision and cannot invalidate an already-posted production document.
>
> **Invariant M2 — one default.** At most one active revision is the default for `(company, item,
> effective range)`, enforced by an exclusion/partial unique constraint. The item does not store a
> second pointer. Removing a default is an explicit audited decision; automatic fallback, if enabled,
> is deterministic by effective date and revision number.

---

## 3. Recursion and `BOMTree`

### 3.1 Cycle detection is a recursive database read after write

`check_recursion` calls `traverse_tree`, whose recursive CTE starts with this BOM's non-empty
`BOM Item.bom_no` links and repeatedly follows child BOM Items. It returns this BOM plus all reachable
BOM names (`manufacturing/doctype/bom/bom.py:742-771`, `manufacturing/doctype/bom/bom.py:865-890`).
The controller then rejects:

- a descendant edge back to the current BOM;
- a BOM-bearing descendant whose `item_code` equals the current BOM's output, even through a different
  BOM; and
- an immediate self-link in the current child rows (`manufacturing/doctype/bom/bom.py:742-808`).

The same finished item is allowed as a leaf only when it has no BOM link; the error tells the user to
use `Do Not Explode`. The CTE filters `parenttype = 'BOM'` and empty links, but does not filter child
BOM activity or docstatus (`manufacturing/doctype/bom/bom.py:865-890`). Because the hook is
`on_update`, child rows have already been written before the CTE runs and correctness relies on the
surrounding transaction rolling back on error (`manufacturing/doctype/bom/bom.py:423-427`).

### 3.2 `BOMTree` is a second recursive implementation

`BOMTree` loads a cached BOM and constructs ordered children recursively. For each row:

```text
qty_per_parent_unit = item.stock_qty / parent_bom.quantity
child.exploded_qty  = parent.exploded_qty × qty_per_parent_unit
```

A row with `bom_no` becomes another BOM node; otherwise it becomes an item leaf. Breadth-first
traversal excludes the root and preserves sibling order (`manufacturing/doctype/bom/bom.py:53-116`).
It does not distinguish phantom from stocked subassemblies, recheck active/submitted state, or keep a
visited set. It assumes the persisted graph passed `check_recursion`; corrupted/bypass-created data
can recurse indefinitely during construction.

> **Ours — acyclicity in the write model.** The service validates the proposed complete graph in the
> same transaction before publishing a revision, while the database stores a revision closure table
> used to reject `(ancestor_revision_id = descendant_revision_id)`. Tree consumers never perform
> cycle detection as a side effect of reading. `do_not_explode` is an explicit component consumption
> mode, not a way to hide an illegal graph edge.

---

## 4. Costing — exact source order and formulas

`BOMCostingService` is composed around the document; `BOM` retains thin delegates so old imports and
whitelisted paths continue to work (`manufacturing/doctype/bom/bom.py:996-1058`).

### 4.1 Raw-material rate precedence

For each component, `get_rm_rate` follows this exact order
(`manufacturing/doctype/bom/services/costing.py:26-64`):

1. If the Item is customer-provided, or the BOM row is supplier-sourced, return zero.
2. If the row has `bom_no` and either the parent requests BOM-based subassembly rates **or the row is
   phantom**, use the active child BOM's `base_total_cost / quantity`, multiplied by the component
   conversion factor. This takes precedence over the selected material-rate policy.
3. Otherwise use the selected source:
   - **Valuation Rate:** company-scoped weighted Bin value `SUM(stock_value) / SUM(actual_qty)`,
     optionally for one warehouse. Only when the Bin query returns a non-null value `<= 0` does it
     read the latest positive non-cancelled SLE; a null “no Bin rows” result skips SLE and falls to
     `Item.valuation_rate` (`manufacturing/doctype/bom/bom.py:1065-1120`).
   - **Last Purchase Rate:** use the supplied row value if truthy, otherwise
     `Item.last_purchase_rate`; there is no valuation fallback (`manufacturing/doctype/bom/bom.py:1065-1077`).
   - **Price List:** require a buying price list and call the ordinary price-list engine with row
     quantity/UOM/conversion but with both exchange rates deliberately set to 1; a missing rate stays
     zero and causes a warning (`manufacturing/doctype/bom/bom.py:1079-1104`,
     `manufacturing/doctype/bom/services/costing.py:51-64`).
4. Convert every result to BOM transaction currency:

```text
row.rate = source_rate × (plc_conversion_rate or 1) / (conversion_rate or 1)
```

Valuation and last-purchase policies force `plc_conversion_rate = 1`; price-list policy obtains it
from price-list currency to company currency (`manufacturing/doctype/bom/services/costing.py:26-35`,
`manufacturing/doctype/bom/bom.py:706-716`).

⚠️ **SLE fallback leaks across companies.** The Bin average is company-scoped; the latest-SLE query
filters only item, positive valuation and cancellation, then orders globally by posting datetime and
creation. Another company's SLE can supply the fallback (`manufacturing/doctype/bom/bom.py:1089-1120`).

⚠️ **The no-Bin behavior contradicts its own docstring.** “If no value, get last valuation rate from
SLE” is not what the `is not None and <= 0` condition implements (`manufacturing/doctype/bom/bom.py:1106-1120`).

⚠️ **BOM-derived rates can be double-converted under Price List policy.** Child unit cost is already
company currency (`base_total_cost / quantity`), but the unconditional final formula multiplies it by
`plc_conversion_rate` before dividing by the BOM conversion rate
(`manufacturing/doctype/bom/services/costing.py:30-49`,
`manufacturing/doctype/bom/services/costing.py:128-138`).

### 4.2 Operation formulas

For a workstation/type operation, the service optionally refreshes company-currency hour rate and
converts it into BOM currency. It then calculates (`manufacturing/doctype/bom/services/costing.py:182-220`):

```text
operation.operating_cost      = hour_rate × time_in_mins / 60
operation.base_operating_cost = operating_cost × conversion_rate
operation.cost_per_unit       = operating_cost / (batch_size or 1)
operation.base_cost_per_unit  = base_operating_cost / (batch_size or 1)
```

The parent contribution is the row operating cost, unless `set_cost_based_on_bom_qty`, in which case
it is `cost_per_unit × BOM.quantity`. Finished-good-based operating cost instead uses
`BOM.quantity × operating_cost_per_bom_quantity`; its base value is explicitly rounded to **2**
decimals (`manufacturing/doctype/bom/services/costing.py:157-181`).

### 4.3 Material, secondary-output and total formulas

Stock and phantom component rates are refreshed; a non-stock, non-phantom row retains its entered
rate. For each row (`manufacturing/doctype/bom/services/costing.py:221-254`):

```text
base_rate = rate × conversion_rate
amount = round(round(rate, rate_precision) × round(qty, qty_precision), amount_precision)
base_amount = amount × conversion_rate
qty_consumed_per_unit = round(stock_qty, stock_qty_precision)
                        / round(BOM.quantity, quantity_precision)
raw_material_cost      = Σ amount
base_raw_material_cost = Σ base_amount
```

For each non-legacy secondary output (`manufacturing/doctype/bom/services/costing.py:256-280`):

```text
secondary.cost      = round(raw_material_cost × allocation_percent / 100,
                            raw_material_cost_precision)
secondary.base_cost = round(secondary.cost × conversion_rate,
                            raw_material_cost_precision)
secondary_items_cost      = Σ secondary.cost
base_secondary_items_cost = Σ secondary.base_cost
```

Finally (`manufacturing/doctype/bom/services/costing.py:140-156`):

```text
total_cost      = operating_cost + raw_material_cost - secondary_items_cost
base_total_cost = base_operating_cost + base_raw_material_cost - base_secondary_items_cost
```

The main finished-good allocation is separately `raw_material_cost × FG allocation% / 100`, not a
share of operation cost or total cost (`manufacturing/doctype/bom/bom.py:458-474`). Parent process
loss is `quantity × process_loss_percentage / 100`; secondary process loss is
`stock_qty × process_loss_per / 100`, rounded with the **parent quantity's precision**. Percentages
over 100 and fractional loss in a whole-number UOM are rejected
(`manufacturing/doctype/bom/bom.py:958-985`).

### 4.4 Precision is field-dependent, not formula-dependent

Component amount and secondary allocation explicitly use field precision; the finished-good-based
base operation cost hard-codes 2 decimals. Most sums, operation intermediates, base component amount
and final totals use Python floats and depend on later DocField/database coercion
(`manufacturing/doctype/bom/services/costing.py:140-280`). Secondary `base_cost` is rounded using the
**transaction-currency raw-material-cost precision**, not its own base/company-currency precision
(`manufacturing/doctype/bom/services/costing.py:256-272`).

> **Invariant M3 — deterministic costing.** Quantity, conversion and unit-rate arithmetic uses
> `numeric(21,9)`; money uses the company's declared money scale, with one named rounding point per
> formula. Cost source is stored as `(kind, source_record_id, source_effective_at, source_currency,
> source_rate, exchange_rate)`, not inferred later from mutable Item/Bin/price-list state.
>
> **Ours — cost is a snapshot, not a mutable BOM property.** `bom_cost_snapshot` is keyed by revision,
> company, costing policy, effective timestamp and algorithm version. An authorised manual rate is an
> `audited_override` carrying actor, reason and prior/source values. Production valuation snapshots the
> chosen cost on the production movement; a later refresh never rewrites posted stock or GL entries.

---

## 5. Explosion — recursive flattening as a stored, lossy projection

### 5.1 Rebuild algorithm

`BOMExplodedItemsService` rebuilds from scratch (`manufacturing/doctype/bom/services/exploded_items.py:13-123`):

1. Clear a transient map.
2. A direct leaf contributes its stock quantity and company-currency stock-UOM rate
   `base_rate / (conversion_factor or 1)`.
3. Any row with `bom_no` — ordinary or phantom — reads the submitted child BOM's already-persisted
   explosion and scales each leaf:

```text
child_leaf_qty = child_flat.stock_qty / child_BOM.quantity × parent_row.stock_qty
```

   The child's operation wins; an empty child operation inherits the parent-row operation.
4. Aggregate by `item_code`, or by `(item_code, operation)` when operation is present. Only
   `stock_qty` is added; rate, warehouse, description and flags survive from the first row.
5. Clear the document child list; when saving, delete every old database explosion row; append sorted
   rows; compute `amount = stock_qty × rate` and `qty_consumed_per_unit = stock_qty / BOM.quantity`;
   then insert each child row.

The flat table is therefore a materialised **leaf** projection. All nested BOMs disappear from it,
not only phantom BOMs. It is recursively compositional but not self-contained: rebuilding a parent
trusts that each child's stored explosion is current.

⚠️ Aggregation loses distinctions. The same item/operation from different warehouses, with different
rates, descriptions, supplier flags or manufacturing flags collapses to one row; quantity is summed
and first-encountered metadata wins (`manufacturing/doctype/bom/services/exploded_items.py:27-58`).
Cost-only refresh has a second lossy map keyed only by item code, so rates from repeated child paths
can overwrite each other (`manufacturing/doctype/bom/services/costing.py:282-307`).

⚠️ Rebuild is delete-then-row-insert, not an atomic projection swap. A failure after deletion can
leave a partial projection unless the caller's whole transaction remains intact
(`manufacturing/doctype/bom/services/exploded_items.py:110-123`).

### 5.2 “Exploded”, direct, nested and phantom are separate read semantics

`get_bom_items_as_dict` chooses one of three stored child tables. Semi-finished tracking or requesting
secondary items forcibly disables exploded mode. The direct query normalises each row by BOM output
quantity; exploded mode groups flat leaves by item/stock-UOM/operation; semi-finished direct mode
groups by operation-row ID (`manufacturing/doctype/bom/bom.py:1172-1324`).

Direct mode preserves `(bom_no, is_phantom_item)` as a pair. A phantom direct row is recursively
replaced by its child projection and duplicate quantities are added; an ordinary nested row remains a
subassembly item (`manufacturing/doctype/bom/bom.py:1326-1388`). Thus:

- the **stored flat table** explodes every linked BOM;
- a **direct production read** explodes only phantom rows;
- **`BOMTree`** traverses every linked BOM and preserves subassembly nodes.

Those are three valid views, but they are three implementations with different grouping keys and
failure modes rather than one parameterised graph projection.

### 5.3 Deeper helper defects

The operating-cost helper intended to walk subassemblies adds a direct child's cost, then recursively
calls itself without assigning the returned total; deeper costs are discarded. It also never scales
child cost by the BOM-row quantity (`manufacturing/doctype/bom/services/operations_cost.py:266-281`).

The backward-compatible secondary-output helper mutates the `qty` accumulator while walking siblings,
so a later sibling inherits earlier siblings' multiplier; it also `dict.update`s duplicate outputs
rather than summing them (`manufacturing/doctype/bom/services/operations_cost.py:284-300`).

> **Invariant M4 — projection equivalence.** For a revision and requested output quantity, direct
> expansion, materialised expansion and production consumption must resolve to the same component
> multiset under the same explicit policy (`stop_at_subassembly`, `explode_phantom`, or `explode_all`).
> Grouping includes every semantic dimension: item, UOM, operation, warehouse/source mode and ownership.
>
> **Ours.** One pure recursive query/function defines expansion. A materialised projection is replaced
> atomically and carries the source-revision fingerprint; readers reject a stale fingerprint rather
> than mixing parent source with child cache. Phantom is a component/revision policy controlling where
> production stops, not a second costing implementation.

---

## 6. `BOM Creator` — a tree editor that submits a hierarchy in one job

### 6.1 Its persisted tree model

`BOMCreator` is a submittable `Document` with finished item/quantity/UOM, company/project/routing,
material-rate and currency fields, warehouse-rate fields, a computed preview total, status/error and
one child table (`manufacturing/doctype/bom_creator/bom_creator.py:37-70`). `BOM Creator Item` stores
component/finished-good identity, quantity/UOM/rates, operation and supplier/phantom flags, plus tree
bookkeeping: `is_expandable`, `parent_row_no`, stable `fg_reference_id`, and `bom_created`
(`manufacturing/doctype/bom_creator_item/bom_creator_item.py:8-43`).

On each save, Creator derives status, globally infers expandability by item code, defaults conversion
factors, translates mutable row indices into child names, and recursively recalculates preview cost
(`manufacturing/doctype/bom_creator/bom_creator.py:72-78`,
`manufacturing/doctype/bom_creator/bom_creator.py:167-231`). Validation forbids a stock final item
being phantom and a non-stock final item being non-phantom, rejects obvious parent-row shape errors,
and tries to reject duplicate `(item_code, fg_reference_id)` rows
(`manufacturing/doctype/bom_creator/bom_creator.py:80-131`).

⚠️ Repeated-item structure is instance-aware during generation but **not during preview costing**.
Generation keys nodes by `(item_code, child-row name)`; preview recursion selects all rows by
`fg_item == item_code`. Two occurrences of the same subassembly with different children each include
both branches in their displayed rate (`manufacturing/doctype/bom_creator/bom_creator.py:189-224`,
`manufacturing/doctype/bom_creator/bom_creator.py:267-312`). Expandability has the same item-global
problem and can turn a leaf occurrence into an empty subassembly.

⚠️ Duplicate root materials have a two-stage defect. On the first save, rows whose
`fg_reference_id` is still blank are skipped by duplicate validation; Frappe runs `validate` before
`before_save`, and only `before_save` populates each root row with the Creator name. On a later save,
the duplicate key is visible, but the error path searches for a **child row** whose name equals the
Creator document name and raises `StopIteration` instead of the intended validation message
(`manufacturing/doctype/bom_creator/bom_creator.py:72-105`,
`manufacturing/doctype/bom_creator/bom_creator.py:167-183`,
`frappe/model/document.py:1827-1855`).

### 6.2 Submit and generation order

Submission requires a non-empty items table and enqueues the bound `create_boms` method on the short
queue with a 600-second timeout (`manufacturing/doctype/bom_creator/bom_creator.py:238-265`). The
worker marks In Progress, builds buckets for the root and each expandable occurrence, reverses
insertion order, and calls `create_bom` for each node — intended to be leaf-first
(`manufacturing/doctype/bom_creator/bom_creator.py:267-312`).

Each node first checks for an already-submitted BOM with the exact `(creator, item, creator-item
occurrence)`. Otherwise it constructs a Production BOM, copies a six-field parent allowlist, links
child occurrences to the BOM names created earlier, saves ignoring permissions and submits
(`manufacturing/doctype/bom_creator/bom_creator.py:327-386`). Generated BOM validation, costing,
explosion, recursion and default selection all run normally, so one Creator job can also change
`Item.default_bom` (§2).

The reverse of child-table insertion order is **not a topological sort**. It works only while UI
mutators have inserted every parent before its descendants. Import/reorder can make a parent run before
its child and therefore write a blank sub-BOM link (`manufacturing/doctype/bom_creator/bom_creator.py:267-312`).

Only the root gets routing/operation mode. A child-row `operation` can make the root
`with_operations = 1`, but Creator never appends `BOM Operation` rows; without a routing, generated
BOM submission rejects the empty operation table (`manufacturing/doctype/bom_creator/bom_creator.py:340-383`,
`manufacturing/doctype/bom/bom.py:924-946`). Creator fields for warehouse-specific valuation,
price-list conversion and remarks, and child instruction/subcontract fields, are not in the copy
allowlists (`manufacturing/doctype/bom_creator/bom_creator.py:14-34`).

⚠️ Creator's preview is not currency-equivalent to the generated BOM. Preview costing calls
`get_bom_item_rate` directly and bypasses `BOMCostingService.get_rm_rate`'s final
`plc_conversion_rate / conversion_rate`; valuation and last-purchase rates are therefore summed
without conversion into Creator currency (`manufacturing/doctype/bom_creator/bom_creator.py:189-224`,
`manufacturing/doctype/bom/services/costing.py:26-35`). Generation copies `currency`,
`conversion_rate` and `buying_price_list` but omits `price_list_currency` and
`plc_conversion_rate`. In particular, a price list already denominated in BOM currency can fall back
to `plc_conversion_rate = 1` and then be divided by the BOM conversion rate
(`manufacturing/doctype/bom_creator/bom_creator.py:14-21`,
`manufacturing/doctype/bom_creator/bom_creator.py:340-386`,
`manufacturing/doctype/bom/bom.py:706-716`, `manufacturing/doctype/bom/bom.py:1079-1104`).

### 6.3 Queue, failure, retry and cancellation semantics

The enqueue has no `enqueue_after_commit`, stable job ID or deduplication
(`manufacturing/doctype/bom_creator/bom_creator.py:255-265`). Frappe otherwise supports all three and
publishes immediately unless `enqueue_after_commit` is requested
(`frappe/utils/background_jobs.py:68-122`, `frappe/utils/background_jobs.py:140-219`). Therefore a
worker can start before Creator submission commits, and repeated manual retries can run concurrently.
The existence check is a non-atomic check-then-create with no row lock or database uniqueness rule.

Generation catches every exception **inside** the job, rolls back the entire hierarchy transaction,
writes Failed plus traceback, and returns normally (`manufacturing/doctype/bom_creator/bom_creator.py:307-325`).
Frappe commits a normally-returning job and retries only escaped deadlock/timeout or explicit retry
errors (`frappe/utils/background_jobs.py:245-295`). RQ therefore records the expected Creator failure
as a successful job and performs no automatic retry. A pre-loop error or hard worker loss instead
escapes/rolls back without a Creator failure transition or stale-job recovery.

Manual rerun is superficially idempotent, but when an existing child BOM is found `create_bom`
returns without placing its name into the in-memory bucket. If the child exists while its parent does
not, the recreated parent can link no BOM or an unrelated Item default
(`manufacturing/doctype/bom_creator/bom_creator.py:327-383`).

Creator completion requires every expandable row's `bom_created` plus existence of a Creator-linked
root BOM, but the root existence check does not require `docstatus = 1`. Cancelling the root can leave
Creator `Completed`; attempting to cancel Creator while submitted generated BOMs still link through
`BOM.bom_creator` is blocked by Frappe's generic post-`on_cancel` backlink check, so the Creator
status write rolls back. If those submitted backlinks are cleared first, Creator's own cancellation
still only changes its status: it has no cascade that cancels or deactivates generated BOMs
(`manufacturing/doctype/bom_creator/bom_creator.py:133-161`,
`manufacturing/doctype/bom/bom.py:127-206`, `frappe/model/document.py:1881-1904`,
`frappe/model/delete_doc.py:301-369`).

> **Ours.** Tree editing stays draft-only and uses immutable node IDs, never row numbers. Publish
> validates the graph and inserts every revision and edge in one database transaction; no background
> job is needed for ordinary hierarchy size. If asynchronous publication is required, the job has
> `UNIQUE(kind, creator_id, source_version)`, starts after commit, locks/leases the creator, stores a
> dependency DAG, and either publishes the complete root atomically or publishes nothing.

---

## 7. `BOM Update Tool` and `BOM Update Log`

### 7.1 The Tool is only a launcher

`BOMUpdateTool` is a passive Single controller with current/new BOM fields
(`manufacturing/doctype/bom_update_tool/bom_update_tool.py:15-28`). Its whitelisted endpoints create
and immediately submit a `BOM Update Log`; no update state lives on the Tool
(`manufacturing/doctype/bom_update_tool/bom_update_tool.py:31-45`,
`manufacturing/doctype/bom_update_tool/bom_update_tool.py:68-84`).

`BOM Update Log` is the durable parent work record: update type, Queued/In Progress/Completed/Failed/
Cancelled status, replacement links, Error Log link, JSON `processed_boms`, `current_level`, and
`BOM Update Batch` children (`manufacturing/doctype/bom_update_log/bom_update_log.py:24-44`). Each
batch stores level, batch number, JSON BOM names and Pending/Completed status; there is no failed state
or checkpoint per BOM (`manufacturing/doctype/bom_update_batch/bom_update_batch.py:8-25`).

Validation requires replacement BOMs to exist as fields, differ, and produce the same item. Cost
update requests one matching Queued/In Progress log without an explicit `order_by`; Frappe applies
the DocType's default ordering, then the controller rejects creation only when that selected row's
`modified` date is less than one day old. Every validation resets status to Queued
(`manufacturing/doctype/bom_update_log/bom_update_log.py:58-106`,
`frappe/model/db_query.py:1379-1414`). The guard is neither a lock nor a uniqueness rule, and the
server-side replacement check does not itself require active submitted BOMs.

### 7.2 Replace BOM — audited, but unordered and internally inconsistent

Submit enqueues replacement after commit with a 40,000-second timeout, but no job ID/deduplication
(`manufacturing/doctype/bom_update_log/bom_update_log.py:107-125`). The worker commits In Progress,
enables Frappe's “auto commit on too many writes”, performs replacement, and writes Completed; errors
are caught and converted to Failed (`manufacturing/doctype/bom_update_log/bom_update_log.py:128-149`).
Frappe's threshold path commits after the configured/default transaction-write ceiling, so a large
replacement can become partially durable (`frappe/database/database.py:477-501`).

Replacement (`manufacturing/doctype/bom_update_log/bom_updation_utils.py:16-43`):

1. computes `new_bom.total_cost / new_bom.quantity`;
2. bulk-updates every non-cancelled BOM Item pointing to the old BOM — including draft and inactive
   parents — changing `bom_no`, transaction `rate` and `amount`;
3. finds every transitive ancestor with a cycle-terminating recursive `UNION` CTE;
4. for each returned ancestor, snapshots the document for versioning, rebuilds its explosion,
   calculates cost, propagates its unit cost into parent rows, updates the parent and writes a Version
   linked to the update log (`manufacturing/doctype/bom_update_log/bom_updation_utils.py:70-115`).

Version linkage is good intent, but the “before” snapshot is taken **after** the bulk child-link rewrite.
The Version is linked to the update log and can record subsequent explosion/cost changes, but it does
not reliably show the old→new `bom_no` transition itself
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:16-43`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:99-115`). The ancestor CTE returns no
depth and has no `ORDER BY`; each ancestor is processed once in database return order. A higher parent
can rebuild from a lower parent's old explosion
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:70-96`). There is no BOM row lock.

⚠️ **Replacement mixes old base values with new transaction values.** The initial bulk update does
not change `base_rate`/`base_amount`; ancestor explosion is rebuilt **before** cost recalculation and
reads component `base_rate`; `calculate_cost()` defaults to `save_updates=False`, so changed child rows
are not persisted (`manufacturing/doctype/bom_update_log/bom_updation_utils.py:26-43`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:99-115`,
`manufacturing/doctype/bom/services/costing.py:140-154`). A replacement can therefore publish a new
link and transaction rate alongside stale base values and a freshly rebuilt stale-rate explosion.

### 7.3 Update Cost — the dependency-aware path

Cost update submit enqueues `process_boms_cost_level_wise` on the long queue after commit
(`manufacturing/doctype/bom_update_log/bom_update_log.py:118-125`). Initial processing selects
submitted active **leaf** BOMs, stores `{}` in `processed_boms`, moves to In Progress at level 0, and
queues work (`manufacturing/doctype/bom_update_log/bom_update_log.py:152-183`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:157-171`).

Dependency maps contain child→parents and parent→children for submitted active parent BOMs. A parent
enters the next frontier only when every referenced child is in the processed map. This is the right
bottom-up/topological rule (`manufacturing/doctype/bom_update_log/bom_updation_utils.py:131-154`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:175-207`).

Each level is sliced into **7,000-BOM** batches, despite three comments saying 20k. For each slice the
coordinator inserts a Pending child and immediately enqueues a long worker
(`manufacturing/doctype/bom_update_log/bom_update_log.py:185-212`). A worker checks only for parent
status Failed, then loads every BOM `for_update=True`, refreshes workstation rates and all cost
projections, and updates the parent. After the whole slice it writes the complete BOM-name JSON and
marks the batch Completed (`manufacturing/doctype/bom_update_log/bom_updation_utils.py:46-67`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:119-128`).

The per-BOM `FOR UPDATE` is the only domain lock. There is no lock/claim around creating the active
log, level transition, inserting batches or aggregating processed state. Batch rows have no uniqueness
rule on `(parent, level, batch_no)`.

### 7.4 Commits and the enqueue visibility race

The coordinator commits the parent level/status before fan-out, but each batch row is `db_insert`ed
and its job is published immediately without `enqueue_after_commit` or an intervening commit
(`manufacturing/doctype/bom_update_log/bom_update_log.py:178-212`). A fast worker can finish before
its batch row is visible; its completion `UPDATE` matches no row, after which the coordinator commits
the still-Pending row and waits forever. If later enqueueing fails, rollback removes uncommitted rows
while already-published workers can still run.

Cost workers deliberately commit within a batch, but `if index % 50 == 0` commits after index 0, then
50, 100 — after the first BOM and then groups of fifty, not after clean fifty-row groups
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:119-128`). A failure later in a 7,000-BOM
batch therefore leaves prior BOM costs durable while the batch remains uncompleted and the parent is
marked Failed.

### 7.5 Scheduler, completion and unreachable BOMs

The resume coordinator is registered by cron at `0/15 * * * *`, every **15 minutes**; its docstring
says five (`hooks.py:468-473`, `manufacturing/doctype/bom_update_log/bom_update_log.py:214-224`). For
each In Progress cost log it waits while the current level has no batches or any Pending batch. When
all complete, it decodes every JSON list, merges processed names, computes the next frontier, commits
state, and either queues the next level or marks Completed and deletes all batch rows
(`manufacturing/doctype/bom_update_log/bom_update_log.py:226-286`).

Normal Scheduled Job dispatch has an RQ ID derived from the Scheduled Job Type and avoids queueing a
second active invocation (`frappe/core/doctype/scheduled_job_type/scheduled_job_type.py:73-103`). That
protects ordinary scheduler dispatch, not manual/direct coordinator calls or the database level
transition itself.

A graph with no leaves — for example corrupted active cyclic data — starts In Progress with no batch;
the coordinator's “no batches: continue” rule leaves it there forever
(`manufacturing/doctype/bom_update_log/bom_update_log.py:162-183`,
`manufacturing/doctype/bom_update_log/bom_update_log.py:234-242`). An active parent referencing a
draft/inactive child is not a leaf, while that child never enters the active submitted leaf set; the
parent remains unreachable and the reachable graph can still be declared Completed
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:157-207`,
`manufacturing/doctype/bom_update_log/bom_update_log.py:244-262`).

A daily-maintenance hook invokes automatic cost update. When Manufacturing Settings enables it, the
Tool creates a log if none is queued/running or if the newest such log's **creation** is over ten days
old (`hooks.py:489-525`, `manufacturing/doctype/bom_update_tool/bom_update_tool.py:48-65`). This can
create a second job beside a genuinely active long-running one; the controller's separate one-day
check tests `modified` on one default-ordered result rather than explicitly selecting the most
recently modified active log, and takes no lock
(`manufacturing/doctype/bom_update_log/bom_update_log.py:90-106`,
`frappe/model/db_query.py:1379-1414`).

### 7.6 Failure, restart and cancellation

Both ERPNext workers catch ordinary exceptions themselves. `handle_exception` rolls back only the
current transaction, creates an Error Log and sets the parent Failed
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:227-232`). Their `finally` blocks commit,
so Frappe/RQ sees normal return and its deadlock/timeout retry path is bypassed
(`manufacturing/doctype/bom_update_log/bom_update_log.py:128-149`,
`manufacturing/doctype/bom_update_log/bom_updation_utils.py:46-67`,
`frappe/utils/background_jobs.py:245-295`). There is no BOM-specific retry endpoint, persisted RQ ID,
checkpoint resume, stale-Pending reaper, or reconciliation of committed BOMs to batch JSON.

A hard worker loss or the visibility race leaves Pending/In Progress forever; cron only skips it. A
Failed parent is no longer scanned. Manual intervention can reapply already committed work.

Cancellation is not implemented for submitted logs. The controller defines only `on_discard`, but
Frappe permits discard only for drafts and dispatches `on_cancel` for submitted cancellation
(`manufacturing/doctype/bom_update_log/bom_update_log.py:68-69`,
`frappe/model/document.py:1788-1812`, `frappe/model/document.py:1881-1904`). No job ID is stored or
cancelled. Replacement never checks parent status; cost batches stop only for Failed, not Cancelled
(`manufacturing/doctype/bom_update_log/bom_updation_utils.py:46-52`).

> **Invariant M5 — dependency-safe refresh.** A parent projection is publishable only from the exact
> completed child projection versions named in its input fingerprint. Dependency order is a stored DAG
> with a uniqueness constraint, not incidental SQL return or child-row insertion order.
>
> **Invariant M6 — durable jobs.** Every refresh has a unique dedupe key, explicit queued/running/
> retryable/failed/completed/cancelled states, lease owner/expiry, attempt rows, and idempotent
> checkpoints. Queue publication occurs after the work row commits. A worker either records the next
> checkpoint and outputs atomically or records a retryable failure; it never swallows failure from the
> queue framework.
>
> **Ours — no in-place BOM replacement.** “Replace BOM” creates new parent revisions that point to the
> replacement child and records the change set, actor and reason. Existing approved revisions and
> posted production retain their old links. A bulk operation may prepare many draft revisions, but
> each publish is dependency-checked and audited. Cost refresh writes new snapshots/projections; it
> does not mutate source rows or historical valuation.

---

## 8. Findings and decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Positive component quantities, fixed-asset rejection, operation time/workstation gates | **Adopt rules** | schema checks plus publish-time graph validation |
| Active/submitted linked-BOM check | **Adopt intent** | FK to an approved immutable revision |
| Linked BOM accepted because item merely occurs in its inputs | **Reject** | component link must target a revision whose declared output matches the component/allowed co-product |
| Recursive CTE cycle detection | **Adopt technique** | validate before publish + persisted closure constraint |
| `BOMTree` with no local cycle/validity guard | **Reject as validator** | readers consume already-validated graph |
| Two denormalised default-BOM values | **Reject** | partial unique/exclusion constraint; one source of truth |
| No fallback election after default cancellation | **Make policy explicit** | deterministic effective-date selection or audited no-default state |
| Valuation → conditional SLE → Item fallback | **Keep explicit policy only** | source snapshot with company/warehouse scope and as-of time |
| Latest-SLE fallback not company-scoped | **Reject (bug)** | company is mandatory in every valuation lookup |
| Child `base_total_cost / quantity` | **Adopt formula** | versioned child cost snapshot, with declared currency |
| Price-list FX applied again to company-currency child cost | **Reject (bug)** | typed currency at every rate boundary |
| Operation, raw and secondary formulas | **Adopt with fixed decimal rules** | `numeric(21,9)` quantities/rates; named money rounding points |
| Secondary output allocation subtracting raw-material allocation from total | **Adopt as explicit joint-cost policy** | allocation basis stored and totals constrained exactly |
| Mixed field precision and one hard-coded 2-decimal result | **Reject** | company currency scale + formula-owned rounding |
| Persisted flat BOM | **Adopt only as projection/cache** | fingerprinted, atomically replaced, rebuildable |
| Flattening all nested BOMs in one path, only phantom in another | **Reject ambiguity** | one expansion function with explicit stop policy |
| Explosion aggregation by item/operation only | **Reject (data loss)** | group by every semantic dimension |
| Saving explosion before refreshing stock quantity | **Reject (bug)** | generated stock quantity; projection runs from final validated source |
| Deep operation-cost recursion discarding the return | **Reject (bug)** | tested recursive fold with quantity scaling |
| BOM Creator occurrence IDs | **Adopt** | stable node IDs, never row-number parentage |
| Creator preview/generated-BOM foreign-currency divergence | **Reject (bug)** | one typed rate pipeline shared by preview and publish |
| Reverse insertion order as dependency order | **Reject** | topological order from explicit edges |
| Creator enqueue before commit and without dedupe | **Reject** | transactional outbox/after-commit + unique job key |
| Creator whole-hierarchy rollback | **Adopt atomic intent** | one publish transaction |
| Creator swallowing worker failure | **Reject** | durable attempts and framework-visible failure |
| Update Log as a durable work document | **Adopt concept** | typed job/attempt/checkpoint tables |
| Version records linked to the Log, but snapshotted after link rewrite | **Adopt intent, reject mechanism** | immutable revision change set captures old/new link + actor/reason |
| Replacement ancestors in unspecified order | **Reject (bug)** | bottom-up dependency DAG |
| Cost update bottom-up frontier | **Adopt algorithm** | persisted dependency inputs/fingerprints |
| Per-BOM `FOR UPDATE` | **Adopt locally** | lease job + lock projection key at atomic publish |
| 7,000-BOM batches with JSON completion lists | **Reject representation** | one typed work item per revision, indexed/checkpointed |
| Commit after first BOM, then each fifty | **Reject** | explicit transaction boundary per idempotent work item/batch |
| Publishing batch jobs before batch-row commit | **Reject (race)** | transactional outbox / enqueue-after-commit |
| 15-minute cron resuming levels | **Reject polling as correctness** | ready work is claimed immediately; reaper handles expired leases |
| Swallowed errors, no retry/reaper, broken cancellation | **Reject** | retry policy, lease expiry, cancellation token, framework-visible errors |
| Cost refresh mutating submitted BOMs and parent copies | **Reject** | immutable recipe + append-only cost snapshots |

The six production invariants introduced here are **M1–M6**: immutable approved revisions, one default,
deterministic/auditable costing, projection equivalence, dependency-safe refresh and durable jobs.
They will be consolidated with Work Order, production-stock/WIP and quality invariants in doc 40.

---

Cross-references: doc 17 §2 (UOM precision and Item identity), doc 20 §5 (`db_set` and Version gaps),
doc 22 (background jobs, scheduler and locking), doc 23 (transactional migrations), doc 31 §1
(batch documents and job identity), doc 32 §2 (repair jobs versus invariant-preserving projections),
`docs/design/FINAL-SCHEMA.md` §4 (fixed-decimal inventory and projection principles). Next: doc 34,
operations, routings, workstations and capacity.
