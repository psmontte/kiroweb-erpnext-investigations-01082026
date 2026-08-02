# 32 — Stock Configuration and the Remaining Item Masters

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This is the coverage-closure document. It covers the eleven Stock and Selling configuration DocTypes
that the rest of the investigation referenced constantly but never read: `Stock Settings` (cited by
name in docs 02, 16, 17, 27 and S04 without its controller ever being opened),
`Stock Reposting Settings`, `Item Attribute`, `Item Variant Settings`, `Item Manufacturer`,
`Manufacturer`, `Item Lead Time`, `Stock Closing Balance`, `Shipment Parcel Template`,
`Delivery Settings` and `Delivery Schedule Item`.

Two of them are substantial and change the conclusions of earlier documents:

- **`Stock Settings`** contains the best irreversibility guards in the application — and also mutates
  field precision across eleven doctypes and rewrites every `Item.description` on the site.
- **`Stock Reposting Settings`** ships a **weekly job whose purpose is to detect that the stock↔GL
  invariant has broken and repair it**. That is upstream's own admission of the problem decision 6
  exists to prevent, and it is the single strongest piece of evidence in this investigation.

With this document, **Accounts, Stock, Selling and Buying are at zero uncited DocTypes** —
submittable and configuration alike. See `docs/COVERAGE.md` §"Status against that definition".

---

## 1. `Stock Settings` — 47 flags, and what saving it does

`StockSettings` (`stock/doctype/stock_settings/stock_settings.py:17`).

### 1.1 Guards that protect existing data — the pattern to copy

Four validations refuse a configuration change because data already exists that the change would
invalidate. This is the right instinct and mostly absent elsewhere (compare doc 29 §2.2, where a price
list's currency can be changed under stored prices):

```python
def validate_do_not_use_batchwise_valuation(self):            # :117
    if not frappe.db.exists("Serial and Batch Bundle", {"docstatus": 1}): return
    if doc_before_save.do_not_use_batchwise_valuation and not self.do_not_use_batchwise_valuation:
        frappe.throw(_("Cannot disable {0} as it may lead to incorrect stock valuation."))

def validate_serial_and_batch_no_settings(self):              # :131
    if before and not now and frappe.db.exists("Serial and Batch Bundle", {"docstatus": 1}):
        frappe.throw(_("Cannot disable Serial and Batch No for Item, as there are existing records…"))

def cant_change_valuation_method(self):                       # :154
    # refuse if any SLE exists for an item that has no valuation_method of its own
    …
def validate_pending_reposts(self):                           # :190
    if self.stock_frozen_upto: check_pending_reposting(self.stock_frozen_upto)
```

`cant_change_valuation_method` (`:154`) is the most interesting: it only blocks the change when a
Stock Ledger Entry exists for an item that *relies* on the global default, correctly permitting the
change when every transacting item overrides it. `validate_pending_reposts` (`:190`) is the
counterpart of doc 02 §2.8 — you cannot freeze a period while reposts are queued.

`validate_stock_reservation` (`:194`) enforces mutual exclusion between `allow_negative_stock` and
`enable_stock_reservation` in both directions, and refuses to disable reservation while undelivered
`Stock Reservation Entry` rows exist. But:

```python
# Skip validation for tests
if frappe.in_test:
    return
```

⚠️ The guard is **switched off in the test suite**, so the tests run against a configuration the
product declares impossible — negative stock *and* reservation enabled together. Doc 16 §2 showed
reservation correctness already depends on engine-level locking; testing it in a state the product
forbids means the interaction is untested in the state it actually ships in.

> **Ours** These guards become the normal case rather than the exception, and they move into the
> database: `valuation_method` is a column on `item` with `NOT NULL` and no global default to change;
> `tracking_mode` is immutable once a `stock_move` exists (trigger); negative stock is not a setting at
> all (doc 02 §7 — `qty_on_hand >= 0` is a deferred constraint, with a per-item
> `allow_negative` column if a business genuinely needs it, so the exception is data and scoped).
> Nothing is skipped in tests: the test suite runs the same constraints as production, because they are
> in the schema.

### 1.2 Saving it writes eight global defaults — one of which no longer exists

```python
def validate(self):                                           # :75
    for key in ["item_naming_by", "item_group", "stock_uom", "allow_negative_stock",
                "set_qty_in_transactions_based_on_serial_no_input", "use_serial_batch_fields",
                "enable_serial_and_batch_no_for_item",
                "set_serial_and_batch_bundle_naming_based_on_naming_series"]:
        frappe.db.set_default(key, self.get(key, ""))
```

⚠️ `set_qty_in_transactions_based_on_serial_no_input` is **not a field on the doctype** — it does not
appear in the auto-generated type block (`:24`-`:71`). So every save writes `""` into a `DefaultValue`
row for a setting that no longer exists, and any code still reading that default gets a permanently
false value. This is the two-sources-of-truth problem from doc 30 §10.1 with the second source now
outliving the first.

### 1.3 Saving it changes field metadata in three ways

1. **Naming.** `set_by_naming_series("Item", "item_code", …, hide_name_field=True)` (`:88`) — the same
   metadata mutation as doc 30 §10.2.
2. **Barcode visibility.**
   ```python
   for name in ["barcode", "barcodes", "scan_barcode"]:
       frappe.make_property_setter({"fieldname": name, "property": "hidden",
                                    "value": 0 if self.show_barcode_field else 1},
                                   validate_fields_for_doctype=False)
   ```
   ⚠️ Note there is **no doctype** in that dict. The Property Setter is created by *fieldname alone*,
   so it applies to **every doctype in the site** that has a field called `barcode`, `barcodes` or
   `scan_barcode` — including any a third-party app or a customer added.
3. ⚠️ **Numeric precision.** `change_precision_for_for_sales` (`:238`, note the doubled `for` in the
   method name), `change_precision_for_purchase` (`:250`) and `change_precision_for_stock_entry`
   (`:266`) call `make_property_setter_for_precision` (`:279`), which sets `conversion_factor`
   **precision to 9** across eleven doctypes:

   ```python
   if property_name := frappe.db.exists("Property Setter",
           {"doc_type": doctype, "field_name": "conversion_factor", "property": "precision"}):
       frappe.db.set_value("Property Setter", property_name, "value", 9)
       continue
   make_property_setter(doctype, "conversion_factor", "precision", 9, "Float", validate_fields_for_doctype=False)
   ```

   Three consequences: a checkbox changes the **numeric precision of stored calculations** (doc 17 §2
   showed how much depends on `conversion_factor` precision); the change is **one-way** — unticking
   the box never restores the original precision; and the existing-Property-Setter branch writes with
   `frappe.db.set_value`, so it bypasses the Property Setter's own validation.

### 1.4 Saving it can rewrite every item's description

```python
def validate_clean_description_html(self):                    # :181
    if int(self.clean_description_html or 0) and not int(self.db_get("clean_description_html") or 0):
        frappe.enqueue("…stock_settings.clean_all_descriptions", now=frappe.in_test, enqueue_after_commit=True)

def clean_all_descriptions():                                 # :318
    for item in frappe.get_all("Item", ["name", "description"]):
        if item.description:
            clean_description = clean_html(item.description)
            if item.description != clean_description:
                frappe.db.set_value("Item", item.name, "description", clean_description)
```

⚠️ Ticking a checkbox enqueues a job that **destructively rewrites master data across the whole
site**, one `UPDATE` per item, with no dry run, no record of what changed, and no way back — `db_set`
writes are invisible to `Version` (doc 20 §5). On a 100,000-item catalogue this is 100,000
uninstrumented updates started by a settings save.

### 1.5 The flag catalogue

47 fields, grouped by what they decide:

| Concern | Flags |
|---|---|
| **Valuation** | `valuation_method`, `do_not_use_batchwise_valuation`, `allow_internal_transfer_at_arms_length_price` |
| **Negative stock** | `allow_negative_stock`, `allow_negative_stock_for_batch` |
| **Freeze** | `stock_frozen_upto`, `stock_frozen_upto_days`, `stock_auth_role`, `role_allowed_to_create_edit_back_dated_transactions` (doc 27 §6.5 — three of the freeze mechanisms) |
| **Serial / batch** | `enable_serial_and_batch_no_for_item`, `use_serial_batch_fields`, `auto_create_serial_and_batch_bundle_for_outward`, `auto_reserve_serial_and_batch`, `allow_existing_serial_no`, `disable_serial_no_and_batch_selector`, `do_not_update_serial_batch_on_creation_of_auto_bundle`, `set_serial_and_batch_bundle_naming_based_on_naming_series`, `use_inline_serial_batch_editor`, `pick_serial_and_batch_based_on` (`FIFO`/`LIFO`/`Expiry`) |
| **Reservation** | `enable_stock_reservation`, `auto_reserve_stock`, `allow_partial_reservation`, `auto_reserve_stock_for_sales_order_on_purchase` |
| **Tolerance + override role** | `over_delivery_receipt_allowance`, `over_picking_allowance`, `mr_qty_allowance`, `role_allowed_to_over_deliver_receive` |
| **UOM precision** | `allow_to_edit_stock_uom_qty_for_sales` / `_purchase` / `_stock_entry`, `allow_uom_with_conversion_rate_defined_in_item`, `stock_uom` |
| **Pricing side effects** | `auto_insert_price_list_rate_if_missing`, `update_existing_price_list_rate`, `update_price_list_based_on` |
| **Quality gate** (Tranche B) | `action_if_quality_inspection_is_not_submitted` (`Stop`/`Warn`), `action_if_quality_inspection_is_rejected`, `allow_to_make_quality_inspection_after_purchase_or_delivery` |
| **Transfer** | `validate_material_transfer_warehouses` (S04 §4) |
| **Naming / display** | `item_naming_by`, `naming_series_prefix`, `use_naming_series`, `item_group`, `show_barcode_field`, `clean_description_html` |
| **Reorder** | `auto_indent`, `reorder_email_notify` (doc 17 §5) |

`validate_auto_insert_price_list_rate_if_missing` (`:224`) msgprints a warning about the same
known-bad combination that `Selling Settings.validate_fallback_to_default_price_list` warns about from
the other side (doc 30 §10.3). **Both sides describe the resulting data corruption; neither prevents
it.**

---

## 2. `Stock Reposting Settings` — a scheduled job that repairs the ledger

`StockRepostingSettings` (`stock/doctype/stock_reposting_settings/stock_reposting_settings.py:20`).
This is newer code and, unusually, well documented in-source.

### 2.1 The repost window

```python
def set_minimum_reposting_time_slot(self):                    # :58
    """Ensure that timeslot for reposting is at least 12 hours."""
    …
    if diff < 10:
        self.end_time = get_time_str(add_to_date(self.start_time, hours=10, as_datetime=True))
```

⚠️ The docstring says twelve hours; the code enforces ten. A minor mismatch, but this is exactly the
class of divergence that makes a comment worse than none — and the value is load-bearing, because
`limit_reposting_timeslot` plus `limits_dont_apply_on` (a single weekday) decides when the valuation
engine is allowed to run at all.

`reset_parallel_reposting_settings` (`:50`) silently clears `enable_parallel_reposting` unless
`item_based_reposting` is on, and defaults `no_of_parallel_reposting` to 4.

### 2.2 A data migration behind a settings button

`convert_to_item_wh_reposting` (`:71`) is a whitelisted `POST` on the settings document that:

1. reads every `Repost Item Valuation` with status `Queued`/`In Progress` and `based_on = Transaction`;
2. reads their Stock Ledger Entries to derive the distinct `(item, warehouse)` pairs and each pair's
   earliest posting date;
3. **submits a new `Repost Item Valuation`** per pair (`create_repost_item_valuation`, `:114`, with
   `allow_negative_stock: True` hard-coded);
4. marks all the originals `Skipped` by `frappe.db.set_value`;
5. `db_set("item_based_reposting", 1)`.

A one-way data migration, executed synchronously from a settings form, that abandons queued repost
work and replaces it with differently-shaped work. There is no record linking the skipped rows to
their replacements.

### 2.3 The self-healing job

```python
def repost_incorrect_valuation_entries():                     # :135
    """Weekly scheduler entry point.

    When `repost_incorrect_valuation_entries` is enabled in Stock Reposting Settings, scan each
    company's Stock Ledger Variance and Stock and Account Value Comparison reports for incorrect stock
    valuation in the current financial year and auto-create reposts to correct them. …
    Disabled by default; does nothing unless explicitly turned on."""
```

Read that again. ERPNext ships a **weekly job that scans two diagnostic reports for evidence that
stock valuation is wrong, and automatically creates reposts to fix it**:

- `_repost_stock_ledger_variance` (`:174`) uses the `Stock Ledger Variance` report — item-warehouses
  whose ledger valuation is *internally inconsistent* (the docstring names the cause: "typically a
  wrong previous-SLE pick", which is doc 02 §2.4's `get_previous_sle` ordering problem).
- `_repost_stock_account_value_comparison` (`:200`) uses `Stock and Account Value Comparison` —
  vouchers whose stock value does not match the GL (doc 03 §5's drift detection).
- ⚠️ Both are scoped to the **current financial year** (`fy_start_date`, `:171`), so a valuation
  error dated before the current year is detected by the reports and **never repaired by this job**.
- Journal Entries are excluded, correctly (no stock ledger to repost).
- `get_voucher_warehouse_accounts` (`:250`) checks whether each warehouse's account is of
  `account_type = 'Stock'`; if not, reposting can never reconcile, so
  `notify_incorrect_stock_account` (`:285`) emails System Managers instead of looping forever. That is
  genuinely good engineering — it distinguishes "recoverable drift" from "misconfiguration".
- `has_pending_valuation_repost` (`:311`) prevents week-on-week duplicate reposts, and the per-company
  enqueue uses `job_id=f"repost_incorrect_valuation::{company}"` with `deduplicate=True` (`:148`) —
  the RQ-level idempotency that doc 31 §1.3 was missing.

**Why this matters more than any other finding in the investigation.** Docs 02, 03 and 15 argued that
storing derived valuation state, and repairing it with reposts, makes the stock↔GL invariant
*eventually* true at best. This job is upstream agreeing: the invariant is expected to break in normal
operation, often enough to warrant a scheduled repair, and the repair is bounded to one financial year
because repairing further back is impractical.

> **Ours** There is nothing for this job to do, and that is the test of decision 6. `stock_move` is
> immutable and append-only; `stock_valuation_state` and `stock_on_hand` are **projections** rebuilt
> from it, never edited in place; and the stock↔GL relationship is not a reconciliation between two
> stored numbers but a single insert path — `ledger_entry` rows for an inventory movement are
> **generated from the same `stock_move` rows** in one transaction, with invariant F2
> (`Σ ledger_entry.amount_base for inventory accounts = Σ stock_valuation_state.value_delta` per
> voucher) enforced as a deferred constraint. A drift-detection report is still worth having as an
> operational check, but a *repair* job cannot exist, because there is no independently-stored value to
> repair. If F2 could fail we would have the same problem, which is precisely why it is a constraint
> and not a report.
>
> Ordering — the "wrong previous-SLE pick" the docstring blames — is likewise structural: `stock_move`
> is ordered by `(posting_datetime, id)` with `id` a monotonic `bigint`, so "the previous move" is a
> total order with no ties to resolve at read time (doc 02 §7.1).

---

## 3. Variants and attributes

Doc 17 §3 covered the variant *model*. These are the controllers.

### 3.1 `Item Attribute`

`ItemAttribute` (`stock/doctype/item_attribute/item_attribute.py:24`).

```python
def on_update(self):                                          # :48
    update_variant_attribute_values(self)
    update_variant_item_codes_for_abbr_renames(self)
    self.validate_exising_items()
    self.set_enabled_disabled_in_items()
```

⚠️ **`update_variant_item_codes_for_abbr_renames` renames items.** Variant item codes are built from
attribute-value abbreviations (doc 17 §3.2), so editing an abbreviation on the attribute master
**rewrites the primary keys of every variant using it** — and in Frappe a rename cascades across every
table that links to it (doc 09 §2). A master-data edit is therefore a site-wide key migration.

`validate_exising_items` (`:64`, and the typo is the method name) re-validates **every existing
variant** of the attribute on every save, via one query plus a per-item Python check — so saving an
attribute with 5,000 variants runs 5,000 validations.

`set_enabled_disabled_in_items` (`:52`) bulk-`UPDATE`s `Item Variant Attribute.disabled` for the
attribute — the `disabled` flag is **denormalised onto every variant row** rather than read by join.

⚠️ `validate_numeric` (`:93`) **silently discards data**:

```python
if self.numeric_values:
    self.set("item_attribute_values", [])
```

Ticking "numeric values" empties the attribute's entire value table without warning. If the tick was
a mistake, the list is gone.

`validate_duplication` (`:104`) checks both value and abbreviation uniqueness **case-insensitively**
in Python — the right rule, enforced by a list scan rather than a constraint.

### 3.2 `Item Variant Settings`

`ItemVariantSettings` (`stock/doctype/item_variant_settings/item_variant_settings.py:11`) decides
which `Item` fields are copied from template to variant.

`set_default_fields` (`:30`) enumerates `frappe.get_meta("Item").fields`, subtracts a hard-coded
`exclude_fields` set of twelve names, and skips `no_copy` fields and five fieldtypes. So **which data
a variant inherits is derived from field metadata at configuration time** — add a field to `Item` and
whether variants inherit it depends on when the setting was last regenerated.

`invalid_fields_for_copy_fields_in_variants` (`:28`) is a `ClassVar` blocklist containing exactly
`["barcodes"]`, enforced in `validate` (`:64`); `remove_invalid_fields_for_copy_fields_in_variants`
(`:57`) filters the table and calls `self.save()` **from inside the method**, so a helper triggers a
full document save.

### 3.3 `Item Manufacturer` and `Manufacturer`

`ItemManufacturer` (`stock/doctype/item_manufacturer/item_manufacturer.py:11`) links an item to a
manufacturer part number. `manage_default_item_manufacturer` (`:49`) writes
`default_item_manufacturer` and `default_manufacturer_part_no` **back onto the `Item` master** with
`frappe.db.set_value` — a child-ish master mutating its parent, invisible to `Version`.

Two defects:

- ⚠️ `on_trash` (`:32`) calls `manage_default_item_manufacturer(delete=True)`, but `delete` is only
  read inside the `elif self.is_default:` branch (`:60`). Deleting a **non-default** row therefore
  falls into the `if not self.is_default:` branch, which clears the Item's default **if it happens to
  match this row's manufacturer and part number** — so deleting a duplicate non-default row can wipe
  the item's default.
- `validate_duplicate_entry` (`:34`) only runs `if self.is_new()`, so an existing row can be *edited*
  into a duplicate of another.

`Manufacturer` (`stock/doctype/manufacturer/manufacturer.py:13`) is `onload` only — a contact-bearing
master with no validation, named by `short_name`.

---

## 4. The remaining thin masters

| DocType | Controller | What it is |
|---|---|---|
| `Stock Closing Balance` | `stock/doctype/stock_closing_balance/stock_closing_balance.py:9` (`pass`) | the snapshot rows written by `Stock Closing Entry` (doc 27, S05 §6). ⚠️ `fifo_queue: DF.LongText` stores the **JSON-serialised FIFO queue** and `inventory_dimension_key: DF.SmallText` packs a **composite key into a string** — two structures flattened into text columns, so neither can be joined, indexed or constrained. |
| `Delivery Settings` | `stock/doctype/delivery_settings/delivery_settings.py:9` (`pass`) | four fields for driver dispatch notifications (`dispatch_template`, `dispatch_attachment`, `send_with_attachment`, `stop_delay`). Belongs with `Delivery Trip` (doc 27 §5.3). |
| `Delivery Schedule Item` | `selling/doctype/delivery_schedule_item/delivery_schedule_item.py:9` (`pass`, 2025) | scheduled delivery lines against a Sales Order. ⚠️ `sales_order_item: DF.Data` — a **child-row name held in a `Data` field**, not a Link, so there is no referential integrity to the line it schedules. |
| `Item Lead Time` | `stock/doctype/item_lead_time/item_lead_time.py:9` (`pass`, 2025) | `purchase_time`, `manufacturing_time_in_mins`, `no_of_workstations`, `shift_time_in_hours`, `capacity_per_day`, `daily_yield`, `buffer_time`. Capacity and yield planning inputs with **no validation at all** — no non-negative checks, no percentage bound on `daily_yield`. Consumed by production planning, so the rules belong in **Tranche B**. |
| `Shipment Parcel Template` | `stock/doctype/shipment_parcel_template/shipment_parcel_template.py:9` (`pass`) | `length`/`width`/`height` as `Int`, `weight` as `Float`, **no unit of measure on any of them** — the dimensions are unitless numbers, so a template is only interpretable by convention. |
| `Manufacturer` | `stock/doctype/manufacturer/manufacturer.py:13` | §3.3 |

> **Ours** `stock_closing_balance` becomes the materialised view of decision 23, with the FIFO queue as
> `jsonb` (queryable) or, preferably, as `stock_valuation_layer` rows — a queue is a *list of layers*
> and belongs in a table. `inventory_dimension_key` disappears: dimensions are the `dim1..dim4` FK
> columns of decision 13, so the "key" is the tuple itself. `delivery_schedule_line.order_line_id` is a
> real FK. Every physical dimension carries a `uom_id`, enforced by `NOT NULL` — a length without a
> unit is not a length.

---

## 5. Coverage closure

### 5.1 Where the four modules stand

| Module | Parent DocTypes | Controller cited | Uncited submittable | Uncited config | Excluded |
|---|---:|---:|---:|---:|---:|
| Accounts | 92 | 78 | **0** | **0** | 14 |
| Stock | 45 | 38 | **0** | **0** | 7 |
| Selling | 12 | 9 | **0** | **0** | 3 |
| Buying | 10 | 5 | **0** | **0** | 5 |
| Subcontracting | 4 | 1 | 2 | 1 | 0 |

Subcontracting's three remaining DocTypes (`Subcontracting Order`, `Subcontracting Inward Order`,
`Subcontracting BOM`) are **deferred to Tranche B by decision** — their valuation and GL behaviour is
already documented in doc 03 §3.6 and S04; what is missing is the order lifecycle and supplied-item
consumption, which only makes sense alongside manufacturing.

The generated table in `docs/COVERAGE.md` is the authority; regenerate with
`PYTHONPATH=tools python3 tools/update_coverage_doc.py`.

### 5.2 What "covered" means here

Per `docs/COVERAGE.md`, a DocType counts as covered when its **controller file is cited at a line
number** in `docs/` — which only happens if someone read the code. The audit is reproducible
(`python3 tools/coverage_audit.py`) and the citations are mechanically verified
(`python3 tools/verify_refs.py`, 0 problems across 3,300+ citations including the shorthand form).

Two caveats stated plainly:

1. **Coverage is not exhaustiveness.** A cited controller means it was read and its load-bearing logic
   documented, not that every line is described. Where a document glosses something, it says so.
2. **Child tables are covered with their parents.** The 99 Accounts and 32 Stock child tables are
   documented column-by-column in `docs/reveng/`, and their behaviour is documented with the parent
   that owns them.

### 5.3 The invariant register

The design invariants accumulated across the investigation, by prefix:

| Prefix | Area | Doc |
|---|---|---|
| F1–F7 | GL balance, stock↔GL, transfer pairing, FX | 01, 03, S04, S06 |
| P1–P7 | Pricing, item price validity, coupons, shipping slabs, eligibility | 29 |
| S1–S2 | Settlement, payment schedule | 11, 05 |
| T1–T6 | Tax determination and withholding | 28 |
| U1–U8 | Upstream trade, agreements, translated values, drop-ship | 30 |
| B1–B8 | Batch jobs, subscriptions, loyalty, statement balances, policy | 31 |
| P1–P5 (period) | Period ranges, closed-period posting, close-to-zero, opening balances | S05 |

Consolidated, with the target DDL, in `docs/design/FINAL-SCHEMA.md`.

---

## 6. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| **Refusing to change valuation method while dependent SLEs exist** | **ADOPT** | `item.valuation_method NOT NULL`; no global default to change |
| **Refusing to disable batchwise valuation / serial-batch once bundles exist** | **ADOPT** | `tracking_mode` immutable once a `stock_move` exists (trigger) |
| **Refusing to freeze a period with pending reposts** | **ADOPT** | no reposts exist; period state is decision 22 |
| **Negative-stock ↔ reservation mutual exclusion** | **ADOPT the rule** | `qty_on_hand >= 0` deferred constraint; per-item `allow_negative` |
| `if frappe.in_test: return` skipping that guard | **Reject** | tests run production constraints |
| Eight `frappe.db.set_default` mirrors, one for a **deleted field** | **Reject (bug)** | one source of truth |
| Property Setter created by **fieldname with no doctype** | **Reject (bug)** | no runtime metadata |
| A checkbox setting `conversion_factor` precision to 9 on 11 doctypes, one-way | **Reject** | `numeric(21,9)` in the schema, always |
| `frappe.db.set_value` on an existing Property Setter (bypassing its validation) | **Reject** | — |
| A checkbox enqueuing a rewrite of **every** `Item.description` | **Reject** | data migrations are explicit, dry-runnable, audited |
| Two settings each warning about the same bad combination, neither preventing it | **Reject** | schema-validated `policy` (doc 31 §7.3) |
| Repost window docstring (12h) disagreeing with the code (10h) | **Reject** | — |
| `convert_to_item_wh_reposting` as a one-way migration behind a settings button | **Reject** | versioned migrations (doc 23) |
| **A weekly job that detects and repairs broken stock valuation** | **Reject the need** | immutable `stock_move` + projections + F2 as a deferred constraint (decision 6) |
| Repair scoped to the current financial year only | **Reject** | nothing to repair |
| **Distinguishing recoverable drift from misconfiguration and notifying a human** | **ADOPT** | same, as an operational check |
| **`deduplicate=True` + `job_id` on the enqueue** | **ADOPT** | `UNIQUE (job_kind, dedupe_key)` (doc 31 B2) |
| Editing an attribute abbreviation **renaming every variant's primary key** | **Reject** | `uuid` PKs; codes are `display_code` columns |
| Re-validating every existing variant on each attribute save | **Reject** | constraints, checked per row on write |
| `disabled` denormalised onto every `Item Variant Attribute` row | **Reject** | read by join |
| Ticking "numeric values" **silently emptying** the value table | **Reject (bug)** | mutually exclusive representations, no data loss |
| Case-insensitive uniqueness by Python list scan | **Reject the mechanism, keep the rule** | `UNIQUE` on `lower(value)` / `citext` |
| Which fields a variant inherits derived from **field metadata** | **Reject** | explicit `variant_inherited_field` rows |
| A helper method calling `self.save()` | **Reject** | pure functions; one save per operation |
| `Item Manufacturer` writing defaults back onto `Item` | **Reject** | `is_default` on the child + partial unique index |
| `on_trash` clearing the Item default when deleting a **non-default** row | **Reject (bug)** | FK + partial unique index |
| Duplicate check only `if self.is_new()` | **Reject (bug)** | `UNIQUE` constraint |
| `fifo_queue` as a JSON `LongText` | **Reject** | `stock_valuation_layer` rows |
| `inventory_dimension_key` as a packed string | **Reject** | `dim1..dim4` FK columns (decision 13) |
| `Delivery Schedule Item.sales_order_item` as `DF.Data` | **Reject** | FK to `order_line` |
| `Item Lead Time` with no validation at all | **Reject** | `CHECK` per column; rules in Tranche B |
| Parcel dimensions with **no unit of measure** | **Reject** | `uom_id NOT NULL` on every physical quantity |

---

Cross-references: doc 02 §2.4 and §2.8 (previous-SLE ordering and the repost engine — §2.3's job
exists because of them), doc 03 §5 (stock↔GL drift detection), doc 09 §2 (rename cascade),
doc 15 §4 (the three repost subsystems), doc 16 §2 (reservation and engine-level locking),
doc 17 §2–§3 (UOM precision, variants and attributes), doc 20 §5 (`db_set` and the audit trail),
doc 18 §3 (runtime metadata), doc 27 §6.5 (the freeze mechanisms), doc 30 §10 and doc 31 §7 (the
Selling/Buying and Accounts settings catalogues this completes),
**[S04](../scenarios/S04-stock-transfer-and-in-transit.md)** §4,
**[S05](../scenarios/S05-period-close-and-opening-balances.md)** §6,
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
