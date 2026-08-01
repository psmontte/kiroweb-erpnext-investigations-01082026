# Module deep dive: Stock

Inventory truth: `Item` and its variants/UOMs, `Warehouse` (tree), `Bin` (per item+warehouse
running balances), `Stock Ledger Entry` (append-only movement log with moving-average /
FIFO valuation state), plus `Batch`/`Serial No` traceability and the documents that move
stock (`Stock Entry`, `Delivery Note`, `Purchase Receipt`, `Stock Reconciliation`).

77 DocTypes / 1358 columns.

## Contents

**Single (settings)** (5): [Delivery Settings](#delivery-settings), [Item Variant Settings](#item-variant-settings), [Quick Stock Balance](#quick-stock-balance), [Stock Reposting Settings](#stock-reposting-settings), [Stock Settings](#stock-settings)

**Master** (22): [Batch](#batch), [Bin](#bin), [Customs Tariff Number](#customs-tariff-number), [Inventory Dimension](#inventory-dimension), [Item](#item), [Item Alternative](#item-alternative), [Item Attribute](#item-attribute), [Item Lead Time](#item-lead-time), [Item Manufacturer](#item-manufacturer), [Item Price](#item-price), [Manufacturer](#manufacturer), [Price List](#price-list), [Putaway Rule](#putaway-rule), [Quality Inspection Parameter](#quality-inspection-parameter), [Quality Inspection Parameter Group](#quality-inspection-parameter-group), [Quality Inspection Template](#quality-inspection-template), [Serial No](#serial-no), [Shipment Parcel Template](#shipment-parcel-template), [Stock Closing Balance](#stock-closing-balance), [Stock Entry Type](#stock-entry-type), [UOM Category](#uom-category), [Warehouse Type](#warehouse-type)

**Tree master (hierarchy)** (1): [Warehouse](#warehouse)

**Transaction (submittable)** (17): [Delivery Note](#delivery-note), [Delivery Trip](#delivery-trip), [Item Standard Cost](#item-standard-cost), [Landed Cost Voucher](#landed-cost-voucher), [Material Request](#material-request), [Packing Slip](#packing-slip), [Pick List](#pick-list), [Purchase Receipt](#purchase-receipt), [Quality Inspection](#quality-inspection), [Repost Item Valuation](#repost-item-valuation), [Serial and Batch Bundle](#serial-and-batch-bundle), [Shipment](#shipment), [Stock Closing Entry](#stock-closing-entry), [Stock Entry](#stock-entry), [Stock Ledger Entry](#stock-ledger-entry), [Stock Reconciliation](#stock-reconciliation), [Stock Reservation Entry](#stock-reservation-entry)

**Child / line-item table** (32): [Company Restriction](#company-restriction), [Delivery Note Item](#delivery-note-item), [Delivery Stop](#delivery-stop), [Item Attribute Value](#item-attribute-value), [Item Barcode](#item-barcode), [Item Customer Detail](#item-customer-detail), [Item Default](#item-default), [Item Quality Inspection Parameter](#item-quality-inspection-parameter), [Item Reorder](#item-reorder), [Item Supplier](#item-supplier), [Item Tax](#item-tax), [Item Variant](#item-variant), [Item Variant Attribute](#item-variant-attribute), [Item Website Specification](#item-website-specification), [Landed Cost Item](#landed-cost-item), [Landed Cost Purchase Receipt](#landed-cost-purchase-receipt), [Landed Cost Taxes and Charges](#landed-cost-taxes-and-charges), [Landed Cost Vendor Invoice](#landed-cost-vendor-invoice), [Material Request Item](#material-request-item), [Packed Item](#packed-item), [Packing Slip Item](#packing-slip-item), [Pick List Item](#pick-list-item), [Price List Country](#price-list-country), [Purchase Receipt Item](#purchase-receipt-item), [Quality Inspection Reading](#quality-inspection-reading), [Serial and Batch Entry](#serial-and-batch-entry), [Shipment Delivery Note](#shipment-delivery-note), [Shipment Parcel](#shipment-parcel), [Stock Entry Detail](#stock-entry-detail), [Stock Reconciliation Item](#stock-reconciliation-item), [UOM Conversion Detail](#uom-conversion-detail), [Variant Field](#variant-field)

---

# Single (settings)s

## Delivery Settings

- **Table**: `tabDelivery Settings`  (proposed: `delivery_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `dispatch_template` | Link | `varchar(140)` |  | → `Email Template` *(frappe/Email)* |
| 2 | `dispatch_attachment` | Link | `varchar(140)` |  | → `Print Format` *(frappe/Printing)* |
| 3 | `send_with_attachment` | Check | `smallint` | default=0 |  |
| 4 | `stop_delay` | Int | `integer` |  |  |

## Item Variant Settings

- **Table**: `tabItem Variant Settings`  (proposed: `item_variant_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `do_not_update_variants` | Check | `smallint` | default=0 |  |
| 2 | `allow_rename_attribute_value` | Check | `smallint` | default=0 |  |
| 3 | `allow_different_uom` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `fields` → `Variant Field` (line items)

## Quick Stock Balance

- **Table**: `tabQuick Stock Balance`  (proposed: `quick_stock_balance`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 2 | `item` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 3 | `item_barcode` | Data | `varchar(140)` |  |  |
| 4 | `item_name` | Data | `varchar(140)` | ro, denorm←item.item_name |  |
| 5 | `item_description` | Small Text | `text` | ro, denorm←item.description, default=   |  |
| 6 | `qty` | Float | `numeric(21,9)` | ro |  |
| 7 | `value` | Currency | `numeric(21,9)` | ro |  |
| 8 | `date` | Date | `date` | NOT NULL, default=Today |  |

## Stock Reposting Settings

- **Table**: `tabStock Reposting Settings`  (proposed: `stock_reposting_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `start_time` | Time | `time(6)` |  |  |
| 2 | `end_time` | Time | `time(6)` |  |  |
| 3 | `limits_dont_apply_on` | Select | `varchar(140)` |  | enum: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday |
| 4 | `limit_reposting_timeslot` | Check | `smallint` | default=0 |  |
| 5 | `item_based_reposting` | Check | `smallint` | default=1 |  |
| 6 | `notify_reposting_error_to_role` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 7 | `enable_parallel_reposting` | Check | `smallint` | default=0 |  |
| 8 | `no_of_parallel_reposting` | Int | `integer` | default=4 |  |
| 9 | `enable_separate_reposting_for_gl` | Check | `smallint` | default=0 |  |
| 10 | `do_not_fetch_incoming_rate_from_serial_no` | Check | `smallint` | default=0 |  |
| 11 | `repost_incorrect_valuation_entries` | Check | `smallint` | default=0 |  |

## Stock Settings

- **Table**: `tabStock Settings`  (proposed: `stock_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Stock
- **Description**: Default settings for your stock-related transactions

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_naming_by` | Select | `varchar(140)` | default=Item Code | enum: Item Code, Naming Series |
| 2 | `item_group` | Link | `varchar(140)` |  | → `Item Group` |
| 3 | `stock_uom` | Link | `varchar(140)` |  | → `UOM` |
| 4 | `valuation_method` | Select | `varchar(140)` |  | enum: FIFO, Moving Average, LIFO, Standard Cost |
| 5 | `over_delivery_receipt_allowance` | Float | `numeric(21,9)` |  |  |
| 6 | `action_if_quality_inspection_is_not_submitted` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn |
| 7 | `show_barcode_field` | Check | `smallint` | default=1 |  |
| 8 | `clean_description_html` | Check | `smallint` | default=1 |  |
| 9 | `auto_insert_price_list_rate_if_missing` | Check | `smallint` | default=0 |  |
| 10 | `allow_negative_stock` | Check | `smallint` | default=0 |  |
| 11 | `auto_indent` | Check | `smallint` | default=0 |  |
| 12 | `reorder_email_notify` | Check | `smallint` | default=0 |  |
| 13 | `stock_frozen_upto` | Date | `date` |  |  |
| 14 | `stock_frozen_upto_days` | Int | `integer` |  |  |
| 15 | `stock_auth_role` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 16 | `use_naming_series` | Check | `smallint` | default=0 |  |
| 17 | `naming_series_prefix` | Data | `varchar(140)` | default=BATCH- |  |
| 18 | `role_allowed_to_create_edit_back_dated_transactions` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 19 | `disable_serial_no_and_batch_selector` | Check | `smallint` | default=0 |  |
| 20 | `role_allowed_to_over_deliver_receive` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 21 | `action_if_quality_inspection_is_rejected` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn |
| 22 | `mr_qty_allowance` | Float | `numeric(21,9)` |  |  |
| 23 | `update_existing_price_list_rate` | Check | `smallint` | default=0 |  |
| 24 | `enable_stock_reservation` | Check | `smallint` | default=0 |  |
| 25 | `allow_partial_reservation` | Check | `smallint` | default=1 |  |
| 26 | `pick_serial_and_batch_based_on` | Select | `varchar(140)` | default=FIFO | enum: FIFO, LIFO, Expiry |
| 27 | `auto_create_serial_and_batch_bundle_for_outward` | Check | `smallint` | default=1 |  |
| 28 | `auto_reserve_serial_and_batch` | Check | `smallint` | default=1 |  |
| 29 | `allow_to_edit_stock_uom_qty_for_sales` | Check | `smallint` | default=0 |  |
| 30 | `allow_to_edit_stock_uom_qty_for_purchase` | Check | `smallint` | default=0 |  |
| 31 | `allow_to_edit_stock_uom_qty_for_stock_entry` | Check | `smallint` | default=0 |  |
| 32 | `auto_reserve_stock_for_sales_order_on_purchase` | Check | `smallint` | default=0 |  |
| 33 | `use_serial_batch_fields` | Check | `smallint` | default=1 |  |
| 34 | `do_not_update_serial_batch_on_creation_of_auto_bundle` | Check | `smallint` | default=1 |  |
| 35 | `allow_internal_transfer_at_arms_length_price` | Check | `smallint` | default=0 |  |
| 36 | `do_not_use_batchwise_valuation` | Check | `smallint` | default=0 |  |
| 37 | `over_picking_allowance` | Percent | `numeric(21,9)` |  |  |
| 38 | `allow_existing_serial_no` | Check | `smallint` | default=1 |  |
| 39 | `auto_reserve_stock` | Check | `smallint` | default=0 |  |
| 40 | `set_serial_and_batch_bundle_naming_based_on_naming_series` | Check | `smallint` | default=0 |  |
| 41 | `allow_uom_with_conversion_rate_defined_in_item` | Check | `smallint` | default=0 |  |
| 42 | `allow_to_make_quality_inspection_after_purchase_or_delivery` | Check | `smallint` | default=0 |  |
| 43 | `update_price_list_based_on` | Select | `varchar(140)` | default=Rate | enum: Rate, Price List Rate |
| 44 | `validate_material_transfer_warehouses` | Check | `smallint` | default=0 |  |
| 45 | `allow_negative_stock_for_batch` | Check | `smallint` | default=0 |  |
| 46 | `enable_serial_and_batch_no_for_item` | Check | `smallint` | default=0 |  |
| 47 | `use_inline_serial_batch_editor` | Check | `smallint` | default=1 |  |

---

# Masters

## Batch

- **Table**: `tabBatch`  (proposed: `batch`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:batch_id`  (By fieldname)
- **Title field**: `batch_id`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `disabled` | Check | `smallint` | default=0 |  |
| 2 | `batch_id` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 3 | `item` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 4 | `image` | Attach Image | `text` | hidden |  |
| 5 | `parent_batch` | Link | `varchar(140)` | ro | → `Batch` |
| 6 | `manufacturing_date` | Date | `date` | default=Today |  |
| 7 | `expiry_date` | Date | `date` |  |  |
| 8 | `supplier` | Link | `varchar(140)` | ro | → `Supplier` |
| 9 | `reference_doctype` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 10 | `reference_name` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `reference_doctype` |
| 11 | `description` | Small Text | `text` |  |  |
| 12 | `item_name` | Data | `varchar(140)` | ro, denorm←item.item_name |  |
| 13 | `batch_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `stock_uom` | Link | `varchar(140)` | ro, denorm←item.stock_uom | → `UOM` |
| 15 | `qty_to_produce` | Float | `numeric(21,9)` | ro |  |
| 16 | `produced_qty` | Float | `numeric(21,9)` | ro |  |
| 17 | `use_batchwise_valuation` | Check | `smallint` | ro, default=0 |  |
| 18 | `allow_negative_stock_for_batch` | Check | `smallint` | default=0 |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_doctype`

**Referenced by (21):** `POS Invoice Item`.`batch_no`, `Purchase Invoice Item`.`batch_no`, `Sales Invoice Item`.`batch_no`, `Asset Capitalization Stock Item`.`batch_no`, `Purchase Receipt Item Supplied`.`batch_no`, `Job Card`.`batch_no`, `Batch`.`parent_batch`, `Delivery Note Item`.`batch_no`, `Item Price`.`batch_no`, `Packed Item`.`batch_no`, `Packing Slip Item`.`batch_no`, `Pick List Item`.`batch_no`, `Purchase Receipt Item`.`batch_no`, `Quality Inspection`.`batch_no`, `Serial No`.`batch_no` … (+6 more)

## Bin

- **Table**: `tabBin`  (proposed: `bin`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Title field**: `item_code`
- **Search fields**: `item_code,warehouse`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `warehouse` | Link | `varchar(140)` | NOT NULL, INDEX, ro | → `Warehouse` |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 3 | `reserved_qty` | Float | `numeric(21,9)` | ro, default=0.00 |  |
| 4 | `actual_qty` | Float | `numeric(21,9)` | ro, default=0.00 |  |
| 5 | `ordered_qty` | Float | `numeric(21,9)` | ro, default=0.00 |  |
| 6 | `indented_qty` | Float | `numeric(21,9)` | ro, default=0.00 |  |
| 7 | `planned_qty` | Float | `numeric(21,9)` | ro |  |
| 8 | `projected_qty` | Float | `numeric(21,9)` | ro |  |
| 9 | `reserved_qty_for_production` | Float | `numeric(21,9)` | ro |  |
| 10 | `reserved_qty_for_sub_contract` | Float | `numeric(21,9)` | ro |  |
| 11 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 12 | `company` | Link | `varchar(140)` | ro, denorm←warehouse.company | → `Company` |
| 13 | `valuation_rate` | Float | `numeric(21,9)` | ro |  |
| 14 | `stock_value` | Float | `numeric(21,9)` | ro |  |
| 15 | `reserved_qty_for_production_plan` | Float | `numeric(21,9)` | ro |  |
| 16 | `reserved_stock` | Float | `numeric(21,9)` | ro, default=0 |  |

## Customs Tariff Number

- **Table**: `tabCustoms Tariff Number`  (proposed: `customs_tariff_number`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:tariff_number`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `tariff_number` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Data | `varchar(140)` |  |  |

**Referenced by (1):** `Item`.`customs_tariff_number`

## Inventory Dimension

- **Table**: `tabInventory Dimension`  (proposed: `inventory_dimension`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:dimension_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_document` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 2 | `dimension_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 3 | `document_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 4 | `istable` | Check | `smallint` | ro, hidden, denorm←document_type.istable, default=0 |  |
| 5 | `condition` | Code | `text` |  |  |
| 6 | `apply_to_all_doctypes` | Check | `smallint` | default=1 |  |
| 7 | `target_fieldname` | Data | `varchar(140)` | ro |  |
| 8 | `source_fieldname` | Data | `varchar(140)` | ro |  |
| 9 | `type_of_transaction` | Select | `varchar(140)` |  | enum: Inward, Outward, Both |
| 10 | `fetch_from_parent` | Select | `varchar(140)` |  |  |
| 11 | `mandatory_depends_on` | Small Text | `text` |  |  |
| 12 | `reqd` | Check | `smallint` | default=0 |  |
| 13 | `validate_negative_stock` | Check | `smallint` | default=0 |  |

## Item

- **Table**: `tabItem`  (proposed: `item`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:item_code`  (By fieldname)
- **Title field**: `item_name`
- **Description**: A Product or a Service that is bought, sold or kept in stock.
- **Search fields**: `item_name,description,item_group,customer_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: STO-ITEM-.YYYY.- |
| 2 | `item_code` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 3 | `variant_of` | Link | `varchar(140)` | INDEX, ro | → `Item` |
| 4 | `item_name` | Data | `varchar(140)` | INDEX |  |
| 5 | `item_group` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item Group` |
| 6 | `stock_uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 7 | `disabled` | Check | `smallint` | INDEX, default=0 |  |
| 8 | `allow_alternative_item` | Check | `smallint` | default=0 |  |
| 9 | `is_stock_item` | Check | `smallint` | default=1 |  |
| 10 | `include_item_in_manufacturing` | Check | `smallint` | default=1 |  |
| 11 | `opening_stock` | Float | `numeric(21,9)` | hidden |  |
| 12 | `valuation_rate` | Currency | `numeric(21,9)` |  |  |
| 13 | `standard_rate` | Currency | `numeric(21,9)` |  |  |
| 14 | `is_fixed_asset` | Check | `smallint` | default=0 |  |
| 15 | `asset_category` | Link | `varchar(140)` |  | → `Asset Category` |
| 16 | `asset_naming_series` | Select | `varchar(140)` |  |  |
| 17 | `image` | Attach Image | `text` | hidden |  |
| 18 | `brand` | Link | `varchar(140)` |  | → `Brand` |
| 19 | `description` | Text Editor | `text` |  |  |
| 20 | `shelf_life_in_days` | Int | `integer` |  |  |
| 21 | `end_of_life` | Date | `date` | default=2099-12-31 |  |
| 22 | `default_material_request_type` | Select | `varchar(140)` | default=Purchase | enum: Purchase, Material Transfer, Material Issue, Manufacture, Customer Provided |
| 23 | `valuation_method` | Select | `varchar(140)` |  | enum: FIFO, Moving Average, LIFO, Standard Cost |
| 24 | `warranty_period` | Data | `varchar(140)` |  |  |
| 25 | `weight_per_unit` | Float | `numeric(21,9)` |  |  |
| 26 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 27 | `has_batch_no` | Check | `smallint` | default=0 |  |
| 28 | `create_new_batch` | Check | `smallint` | default=0 |  |
| 29 | `batch_number_series` | Data | `varchar(140)` |  |  |
| 30 | `has_expiry_date` | Check | `smallint` | default=0 |  |
| 31 | `retain_sample` | Check | `smallint` | default=0 |  |
| 32 | `sample_quantity` | Int | `integer` |  |  |
| 33 | `has_serial_no` | Check | `smallint` | default=0 |  |
| 34 | `serial_no_series` | Data | `varchar(140)` |  |  |
| 35 | `has_variants` | Check | `smallint` | default=0 |  |
| 36 | `variant_based_on` | Select | `varchar(140)` | default=Item Attribute | enum: Item Attribute, Manufacturer |
| 37 | `is_purchase_item` | Check | `smallint` | default=1 |  |
| 38 | `purchase_uom` | Link | `varchar(140)` |  | → `UOM` |
| 39 | `min_order_qty` | Float | `numeric(21,9)` | default=0.00 |  |
| 40 | `safety_stock` | Float | `numeric(21,9)` |  |  |
| 41 | `lead_time_days` | Int | `integer` |  |  |
| 42 | `last_purchase_rate` | Float | `numeric(21,9)` | ro |  |
| 43 | `is_customer_provided_item` | Check | `smallint` | default=0 |  |
| 44 | `delivered_by_supplier` | Check | `smallint` | default=0 |  |
| 45 | `country_of_origin` | Link | `varchar(140)` |  | → `Country` *(frappe/Geo)* |
| 46 | `customs_tariff_number` | Link | `varchar(140)` |  | → `Customs Tariff Number` |
| 47 | `sales_uom` | Link | `varchar(140)` |  | → `UOM` |
| 48 | `is_sales_item` | Check | `smallint` | default=1 |  |
| 49 | `max_discount` | Float | `numeric(21,9)` |  |  |
| 50 | `enable_deferred_revenue` | Check | `smallint` | default=0 |  |
| 51 | `no_of_months` | Int | `integer` |  |  |
| 52 | `enable_deferred_expense` | Check | `smallint` | default=0 |  |
| 53 | `no_of_months_exp` | Int | `integer` |  |  |
| 54 | `inspection_required_before_purchase` | Check | `smallint` | default=0 |  |
| 55 | `inspection_required_before_delivery` | Check | `smallint` | default=0 |  |
| 56 | `quality_inspection_template` | Link | `varchar(140)` |  | → `Quality Inspection Template` |
| 57 | `default_bom` | Link | `varchar(140)` | ro | → `BOM` |
| 58 | `is_sub_contracted_item` | Check | `smallint` | default=0 |  |
| 59 | `customer_code` | Small Text | `text` | hidden |  |
| 60 | `total_projected_qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 61 | `over_delivery_receipt_allowance` | Float | `numeric(21,9)` |  |  |
| 62 | `over_billing_allowance` | Float | `numeric(21,9)` |  |  |
| 63 | `auto_create_assets` | Check | `smallint` | default=0 |  |
| 64 | `default_item_manufacturer` | Link | `varchar(140)` | ro | → `Manufacturer` |
| 65 | `default_manufacturer_part_no` | Data | `varchar(140)` | ro |  |
| 66 | `grant_commission` | Check | `smallint` | default=1 |  |
| 67 | `is_grouped_asset` | Check | `smallint` | default=0 |  |
| 68 | `allow_negative_stock` | Check | `smallint` | default=0 |  |
| 69 | `production_capacity` | Int | `integer` |  |  |
| 70 | `purchase_tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 71 | `sales_tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 72 | `restrict_to_companies` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `barcodes` → `Item Barcode` (line items)
- `reorder_levels` → `Item Reorder` (line items)
- `uoms` → `UOM Conversion Detail` (line items)
- `attributes` → `Item Variant Attribute` (line items)
- `item_defaults` → `Item Default` (line items)
- `supplier_items` → `Item Supplier` (line items)
- `customer_items` → `Item Customer Detail` (line items)
- `taxes` → `Item Tax` (line items)
- `allowed_companies` → `Company Restriction` (multi-select)

**Referenced by (118):** `POS Invoice Item`.`item_code`, `Pricing Rule`.`other_item_code`, `Pricing Rule`.`free_item`, `Pricing Rule Item Code`.`item_code`, `Promotional Scheme`.`other_item_code`, `Promotional Scheme Product Discount`.`free_item`, `Purchase Invoice Item`.`item_code`, `Sales Invoice Item`.`item_code`, `Subscription Plan`.`item`, `Tax Rule`.`item`, `Asset`.`item_code`, `Asset Capitalization`.`target_item_code`, `Asset Capitalization Asset Item`.`item_code`, `Asset Capitalization Service Item`.`item_code`, `Asset Capitalization Stock Item`.`item_code` … (+103 more)

## Item Alternative

- **Table**: `tabItem Alternative`  (proposed: `item_alternative`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Title field**: `item_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` |  | → `Item` |
| 2 | `alternative_item_code` | Link | `varchar(140)` |  | → `Item` |
| 3 | `two_way` | Check | `smallint` | default=0 |  |
| 4 | `item_name` | Read Only | `varchar(140)` | denorm←item_code.item_name |  |
| 5 | `alternative_item_name` | Read Only | `varchar(140)` | denorm←alternative_item_code.item_name |  |

## Item Attribute

- **Table**: `tabItem Attribute`  (proposed: `item_attribute`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:attribute_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `attribute_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `numeric_values` | Check | `smallint` | default=0 |  |
| 3 | `from_range` | Float | `numeric(21,9)` | default=0 |  |
| 4 | `increment` | Float | `numeric(21,9)` | default=0 |  |
| 5 | `to_range` | Float | `numeric(21,9)` | default=0 |  |
| 6 | `disabled` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `item_attribute_values` → `Item Attribute Value` (line items)

**Referenced by (3):** `Website Attribute`.`attribute`, `Item Variant`.`item_attribute`, `Item Variant Attribute`.`attribute`

## Item Lead Time

- **Table**: `tabItem Lead Time`  (proposed: `item_lead_time`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:item_code`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | UNIQUE | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 3 | `buffer_time` | Int | `integer` |  |  |
| 4 | `no_of_shift` | Int | `integer` | default=1 |  |
| 5 | `manufacturing_time_in_mins` | Int | `integer` |  |  |
| 6 | `total_workstation_time` | Int | `integer` |  |  |
| 7 | `daily_yield` | Percent | `numeric(21,9)` | default=90 |  |
| 8 | `capacity_per_day` | Int | `integer` |  |  |
| 9 | `no_of_units_produced` | Int | `integer` |  |  |
| 10 | `purchase_time` | Int | `integer` |  |  |
| 11 | `shift_time_in_hours` | Int | `integer` |  |  |
| 12 | `no_of_workstations` | Int | `integer` |  |  |
| 13 | `stock_uom` | Link | `varchar(140)` | ro, denorm←item_code.stock_uom | → `UOM` |

## Item Manufacturer

- **Table**: `tabItem Manufacturer`  (proposed: `item_manufacturer`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Title field**: `item_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `manufacturer` | Link | `varchar(140)` | NOT NULL | → `Manufacturer` |
| 2 | `manufacturer_part_no` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 4 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 5 | `description` | Small Text | `text` | ro, denorm←item_code.description |  |
| 6 | `is_default` | Check | `smallint` | default=0 |  |

## Item Price

- **Table**: `tabItem Price`  (proposed: `item_price`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Title field**: `item_name`
- **Description**: Log the selling and buying rate of an Item

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `uom` | Link | `varchar(140)` | NOT NULL, denorm←item_code.stock_uom | → `UOM` |
| 3 | `packing_unit` | Int | `integer` | default=0 |  |
| 4 | `item_name` | Data | `varchar(140)` | ro |  |
| 5 | `brand` | Link | `varchar(140)` | ro, denorm←item_code.brand | → `Brand` |
| 6 | `item_description` | Text | `text` | ro |  |
| 7 | `price_list` | Link | `varchar(140)` | NOT NULL, INDEX | → `Price List` |
| 8 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 9 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 10 | `buying` | Check | `smallint` | ro, default=0 |  |
| 11 | `selling` | Check | `smallint` | ro, default=0 |  |
| 12 | `currency` | Link | `varchar(140)` | ro, denorm←price_list.currency | → `Currency` *(frappe/Geo)* |
| 13 | `price_list_rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 14 | `valid_from` | Date | `date` | default=Today |  |
| 15 | `lead_time_days` | Int | `integer` | default=0 |  |
| 16 | `valid_upto` | Date | `date` |  |  |
| 17 | `note` | Text | `text` |  |  |
| 18 | `reference` | Data | `varchar(140)` |  |  |
| 19 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |

## Manufacturer

- **Table**: `tabManufacturer`  (proposed: `manufacturer`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:short_name`
- **Title field**: `short_name`
- **Description**: Manufacturers used in Items
- **Search fields**: `short_name, full_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `short_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `full_name` | Data | `varchar(140)` |  |  |
| 3 | `website` | Data | `varchar(140)` |  |  |
| 4 | `country` | Link | `varchar(140)` |  | → `Country` *(frappe/Geo)* |
| 5 | `logo` | Attach Image | `text` |  |  |
| 6 | `notes` | Small Text | `text` |  |  |

**Referenced by (9):** `Purchase Invoice Item`.`manufacturer`, `Purchase Order Item`.`manufacturer`, `Supplier Quotation Item`.`manufacturer`, `Item`.`default_item_manufacturer`, `Item Manufacturer`.`manufacturer`, `Material Request Item`.`manufacturer`, `Purchase Receipt Item`.`manufacturer`, `Subcontracting Order Item`.`manufacturer`, `Subcontracting Receipt Item`.`manufacturer`

## Price List

- **Table**: `tabPrice List`  (proposed: `price_list`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:price_list_name`  (By fieldname)
- **Description**: A Price List is a collection of Item Prices either Selling, Buying, or both
- **Search fields**: `currency`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `enabled` | Check | `smallint` | default=1 |  |
| 2 | `price_list_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 3 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 4 | `buying` | Check | `smallint` | default=0 |  |
| 5 | `selling` | Check | `smallint` | default=0 |  |
| 6 | `price_not_uom_dependent` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `countries` → `Price List Country` (line items)

**Referenced by (25):** `POS Invoice`.`selling_price_list`, `POS Profile`.`selling_price_list`, `Pricing Rule`.`for_price_list`, `Promotional Scheme Price Discount`.`for_price_list`, `Purchase Invoice`.`buying_price_list`, `Sales Invoice`.`selling_price_list`, `Subscription Plan`.`price_list`, `Buying Settings`.`buying_price_list`, `Purchase Order`.`buying_price_list`, `Supplier`.`default_price_list`, `Supplier Quotation`.`buying_price_list`, `BOM`.`buying_price_list`, `BOM Creator`.`buying_price_list`, `Import Supplier Invoice`.`default_buying_price_list`, `Customer`.`default_price_list` … (+10 more)

## Putaway Rule

- **Table**: `tabPutaway Rule`  (proposed: `putaway_rule`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `PUT-.####`  (Expression (old style))
- **Title field**: `item_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 3 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 4 | `capacity` | Float | `numeric(21,9)` | NOT NULL, default=0 |  |
| 5 | `stock_uom` | Link | `varchar(140)` | ro, denorm←item_code.stock_uom | → `UOM` |
| 6 | `priority` | Int | `integer` | default=1 |  |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 8 | `disable` | Check | `smallint` | default=0 |  |
| 9 | `uom` | Link | `varchar(140)` |  | → `UOM` |
| 10 | `stock_capacity` | Float | `numeric(21,9)` | ro |  |
| 11 | `conversion_factor` | Float | `numeric(21,9)` | ro, default=1 |  |

**Referenced by (2):** `Purchase Receipt Item`.`putaway_rule`, `Stock Entry Detail`.`putaway_rule`

## Quality Inspection Parameter

- **Table**: `tabQuality Inspection Parameter`  (proposed: `quality_inspection_parameter`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:parameter`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `parameter` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Text Editor | `text` |  |  |
| 3 | `parameter_group` | Link | `varchar(140)` |  | → `Quality Inspection Parameter Group` |

**Referenced by (2):** `Item Quality Inspection Parameter`.`specification`, `Quality Inspection Reading`.`specification`

## Quality Inspection Parameter Group

- **Table**: `tabQuality Inspection Parameter Group`  (proposed: `quality_inspection_parameter_group`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:group_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (3):** `Item Quality Inspection Parameter`.`parameter_group`, `Quality Inspection Parameter`.`parameter_group`, `Quality Inspection Reading`.`parameter_group`

## Quality Inspection Template

- **Table**: `tabQuality Inspection Template`  (proposed: `quality_inspection_template`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:quality_inspection_template_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `quality_inspection_template_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Child tables (1-N):**

- `item_quality_inspection_parameter` → `Item Quality Inspection Parameter` (line items)

**Referenced by (5):** `BOM`.`quality_inspection_template`, `Job Card`.`quality_inspection_template`, `Operation`.`quality_inspection_template`, `Item`.`quality_inspection_template`, `Quality Inspection`.`quality_inspection_template`

## Serial No

- **Table**: `tabSerial No`  (proposed: `serial_no`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:serial_no`  (By fieldname)
- **Description**: Distinct unit of an Item
- **Search fields**: `item_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `serial_no` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 3 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 4 | `description` | Text | `text` | ro, denorm←item_code.description |  |
| 5 | `item_group` | Link | `varchar(140)` | ro | → `Item Group` |
| 6 | `brand` | Link | `varchar(140)` | ro | → `Brand` |
| 7 | `asset` | Link | `varchar(140)` | ro | → `Asset` |
| 8 | `asset_status` | Select | `varchar(140)` | ro | enum: Issue, Receipt, Transfer |
| 9 | `location` | Link | `varchar(140)` | ro | → `Location` |
| 10 | `employee` | Link | `varchar(140)` | ro | → `Employee` |
| 11 | `maintenance_status` | Select | `varchar(140)` | INDEX, ro | enum: Under Warranty, Out of Warranty, Under AMC, Out of AMC |
| 12 | `warranty_period` | Int | `integer` | ro, denorm←item_code.warranty_period |  |
| 13 | `warranty_expiry_date` | Date | `date` |  |  |
| 14 | `amc_expiry_date` | Date | `date` |  |  |
| 15 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 16 | `work_order` | Link | `varchar(140)` |  | → `Work Order` |
| 17 | `warehouse` | Link | `varchar(140)` | ro | → `Warehouse` |
| 18 | `batch_no` | Link | `varchar(140)` | ro | → `Batch` |
| 19 | `purchase_rate` | Float | `numeric(21,9)` | ro |  |
| 20 | `status` | Select | `varchar(140)` | ro | enum: Active, Inactive, Consumed, Delivered, Expired |
| 21 | `customer` | Link | `varchar(140)` | ro | → `Customer` |
| 22 | `reference_doctype` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 23 | `reference_name` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `reference_doctype` |
| 24 | `posting_date` | Date | `date` | ro |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_doctype`

**Referenced by (4):** `Maintenance Visit Purpose`.`serial_no`, `Quality Inspection`.`item_serial_no`, `Serial and Batch Entry`.`serial_no`, `Warranty Claim`.`serial_no`

## Shipment Parcel Template

- **Table**: `tabShipment Parcel Template`  (proposed: `shipment_parcel_template`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:parcel_template_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `length` | Float | `numeric(21,9)` | NOT NULL |  |
| 2 | `width` | Float | `numeric(21,9)` | NOT NULL |  |
| 3 | `height` | Float | `numeric(21,9)` | NOT NULL |  |
| 4 | `weight` | Float | `numeric(21,1)` | NOT NULL |  |
| 5 | `parcel_template_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (1):** `Shipment`.`parcel_template`

## Stock Closing Balance

- **Table**: `tabStock Closing Balance`  (proposed: `stock_closing_balance`)
- **Kind**: Master
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | INDEX, ro | → `Item` |
| 2 | `warehouse` | Link | `varchar(140)` | INDEX, ro | → `Warehouse` |
| 3 | `posting_date` | Date | `date` | INDEX, ro |  |
| 4 | `posting_time` | Time | `time(6)` | ro |  |
| 5 | `posting_datetime` | Datetime | `timestamp` | INDEX, ro |  |
| 6 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 7 | `valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 8 | `stock_value` | Currency | `numeric(21,9)` | ro |  |
| 9 | `company` | Link | `varchar(140)` | INDEX, ro | → `Company` |
| 10 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 11 | `stock_value_difference` | Currency | `numeric(21,9)` | ro |  |
| 12 | `item_name` | Data | `varchar(140)` | ro |  |
| 13 | `item_group` | Link | `varchar(140)` | ro | → `Item Group` |
| 14 | `stock_closing_entry` | Link | `varchar(140)` | INDEX, ro | → `Stock Closing Entry` |
| 15 | `inventory_dimension_key` | Small Text | `text` | ro |  |
| 16 | `batch_no` | Link | `varchar(140)` | INDEX, ro | → `Batch` |
| 17 | `fifo_queue` | Long Text | `text` | ro |  |

## Stock Entry Type

- **Table**: `tabStock Entry Type`  (proposed: `stock_entry_type`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `Prompt`  (Set by user)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `purpose` | Select | `varchar(140)` | NOT NULL, default=Material Issue | enum: Material Issue, Material Receipt, Material Transfer, Material Transfer for Manufacture, Material Consumption for Manufacture, Manufacture, Repack, Send to Subcontractor … (+5) |
| 2 | `add_to_transit` | Check | `smallint` | default=0 |  |
| 3 | `is_standard` | Check | `smallint` | ro, default=0 |  |

**Referenced by (1):** `Stock Entry`.`stock_entry_type`

## UOM Category

- **Table**: `tabUOM Category`  (proposed: `uom_category`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `field:category_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `category_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (2):** `UOM`.`category`, `UOM Conversion Factor`.`category`

## Warehouse Type

- **Table**: `tabWarehouse Type`  (proposed: `warehouse_type`)
- **Kind**: Master
- **Owned by**: erpnext / Stock
- **Naming**: `Prompt`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `description` | Small Text | `text` |  |  |

**Referenced by (1):** `Warehouse`.`warehouse_type`

---

# Tree master (hierarchy)s

## Warehouse

- **Table**: `tabWarehouse`  (proposed: `warehouse`)
- **Kind**: Tree master (hierarchy)
- **Owned by**: erpnext / Stock
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: A logical Warehouse against which stock entries are made.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `warehouse_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `is_group` | Check | `smallint` | default=0 |  |
| 3 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 4 | `disabled` | Check | `smallint` | hidden, default=0 |  |
| 5 | `account` | Link | `varchar(140)` |  | → `Account` |
| 6 | `email_id` | Data | `varchar(140)` | hidden |  |
| 7 | `phone_no` | Data | `varchar(140)` |  |  |
| 8 | `mobile_no` | Data | `varchar(140)` |  |  |
| 9 | `address_line_1` | Data | `varchar(140)` |  |  |
| 10 | `address_line_2` | Data | `varchar(140)` |  |  |
| 11 | `city` | Data | `varchar(140)` |  |  |
| 12 | `state` | Data | `varchar(140)` |  |  |
| 13 | `pin` | Data | `varchar(140)` |  |  |
| 14 | `parent_warehouse` | Link | `varchar(140)` | INDEX | → `Warehouse` |
| 15 | `lft` | Int | `integer` | ro, hidden |  |
| 16 | `rgt` | Int | `integer` | ro, hidden |  |
| 17 | `old_parent` | Link | `varchar(140)` | ro, hidden | → `Warehouse` |
| 18 | `warehouse_type` | Link | `varchar(140)` |  | → `Warehouse Type` |
| 19 | `default_in_transit_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 20 | `is_rejected_warehouse` | Check | `smallint` | default=0 |  |
| 21 | `customer` | Link | `varchar(140)` |  | → `Customer` |

**Referenced by (133):** `POS Invoice`.`set_warehouse`, `POS Invoice Item`.`warehouse`, `POS Invoice Item`.`target_warehouse`, `POS Profile`.`warehouse`, `Pricing Rule`.`warehouse`, `Promotional Scheme Price Discount`.`warehouse`, `Promotional Scheme Product Discount`.`warehouse`, `Purchase Invoice`.`set_warehouse`, `Purchase Invoice`.`rejected_warehouse`, `Purchase Invoice`.`set_from_warehouse`, `Purchase Invoice`.`supplier_warehouse`, `Purchase Invoice Item`.`warehouse`, `Purchase Invoice Item`.`rejected_warehouse`, `Purchase Invoice Item`.`from_warehouse`, `Sales Invoice`.`set_warehouse` … (+118 more)

---

# Transaction (submittable)s

## Delivery Note

- **Table**: `tabDelivery Note`  (proposed: `delivery_note`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status,customer,customer_name, territory,base_grand_total`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-DN-.YYYY.-, MAT-DN-RET-.YYYY.- |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL, INDEX | → `Customer` |
| 3 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 4 | `amended_from` | Link | `varchar(140)` | ro | → `Delivery Note` |
| 5 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 6 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 7 | `posting_time` | Time | `time(6)` | NOT NULL, default=Now |  |
| 8 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 9 | `is_return` | Check | `smallint` | ro, default=0 |  |
| 10 | `issue_credit_note` | Check | `smallint` | default=0 |  |
| 11 | `return_against` | Link | `varchar(140)` | INDEX, ro | → `Delivery Note` |
| 12 | `po_no` | Small Text | `text` |  |  |
| 13 | `po_date` | Date | `date` |  |  |
| 14 | `shipping_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 15 | `shipping_address` | Text Editor | `text` | ro |  |
| 16 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 17 | `contact_display` | Small Text | `text` | ro |  |
| 18 | `contact_mobile` | Small Text | `text` | ro, hidden |  |
| 19 | `contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 20 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 21 | `tax_id` | Data | `varchar(140)` | ro |  |
| 22 | `address_display` | Text Editor | `text` | ro |  |
| 23 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 24 | `company_address_display` | Text Editor | `text` | ro |  |
| 25 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 26 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 27 | `selling_price_list` | Link | `varchar(140)` | NOT NULL | → `Price List` |
| 28 | `price_list_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 29 | `plc_conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 30 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 31 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 32 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 33 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 34 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 35 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 36 | `total` | Currency | `numeric(21,9)` | ro |  |
| 37 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 38 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 39 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 40 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 41 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 42 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 43 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 44 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 45 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 46 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 47 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 48 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 49 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 50 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 51 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 52 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 53 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 54 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 55 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 56 | `in_words` | Data | `varchar(140)` | ro |  |
| 57 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 58 | `terms` | Text Editor | `text` |  |  |
| 59 | `transporter` | Link | `varchar(140)` |  | → `Supplier` |
| 60 | `driver` | Link | `varchar(140)` |  | → `Driver` |
| 61 | `lr_no` | Data | `varchar(140)` |  |  |
| 62 | `vehicle_no` | Data | `varchar(140)` |  |  |
| 63 | `transporter_name` | Data | `varchar(140)` | ro, denorm←transporter.supplier_name |  |
| 64 | `driver_name` | Data | `varchar(140)` | denorm←driver.full_name |  |
| 65 | `lr_date` | Date | `date` | default=Today |  |
| 66 | `project` | Link | `varchar(140)` |  | → `Project` |
| 67 | `per_billed` | Percent | `numeric(21,9)` | ro |  |
| 68 | `customer_group` | Link | `varchar(140)` | hidden | → `Customer Group` |
| 69 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 70 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 71 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 72 | `language` | Link | `varchar(140)` | ro, denorm←customer.language | → `Language` *(frappe/Core)* |
| 73 | `print_without_amount` | Check | `smallint` | default=0 |  |
| 74 | `group_same_items` | Check | `smallint` | default=0 |  |
| 75 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, To Bill, Partially Billed, Completed, Return, Return Issued, Cancelled, Closed |
| 76 | `per_installed` | Percent | `numeric(21,9)` | ro |  |
| 77 | `installation_status` | Select | `varchar(140)` | hidden |  |
| 78 | `excise_page` | Data | `varchar(140)` | hidden |  |
| 79 | `instructions` | Text | `text` |  |  |
| 80 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 81 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 82 | `commission_rate` | Float | `numeric(21,9)` | denorm←sales_partner.commission_rate |  |
| 83 | `total_commission` | Currency | `numeric(21,9)` |  |  |
| 84 | `is_internal_customer` | Check | `smallint` | ro, denorm←customer.is_internal_customer, default=0 |  |
| 85 | `inter_company_reference` | Link | `varchar(140)` |  | → `Purchase Receipt` |
| 86 | `per_returned` | Percent | `numeric(21,9)` | ro |  |
| 87 | `set_target_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 88 | `represents_company` | Link | `varchar(140)` | ro, denorm←customer.represents_company | → `Company` |
| 89 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 90 | `dispatch_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 91 | `dispatch_address` | Text Editor | `text` | ro |  |
| 92 | `amount_eligible_for_commission` | Currency | `numeric(21,9)` | ro |  |
| 93 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 94 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 95 | `named_place` | Data | `varchar(140)` |  |  |
| 96 | `delivery_trip` | Link | `varchar(140)` |  | → `Delivery Trip` |
| 97 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Medium` *(frappe/Website)* |
| 98 | `utm_content` | Data | `varchar(140)` |  |  |
| 99 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 100 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 101 | `company_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 102 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `Delivery Note Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `packed_items` → `Packed Item` (line items)
- `taxes` → `Sales Taxes and Charges` (line items)
- `sales_team` → `Sales Team` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (9):** `POS Invoice Item`.`delivery_note`, `Sales Invoice Item`.`delivery_note`, `Delivery Note`.`amended_from`, `Delivery Note`.`return_against`, `Delivery Stop`.`delivery_note`, `Packing Slip`.`delivery_note`, `Purchase Receipt`.`inter_company_reference`, `Shipment Delivery Note`.`delivery_note`, `Stock Entry`.`delivery_note_no`

## Delivery Trip

- **Table**: `tabDelivery Trip`  (proposed: `delivery_trip`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `driver_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: MAT-DT-.YYYY.- |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `email_notification_sent` | Check | `smallint` | ro, default=0 |  |
| 4 | `driver` | Link | `varchar(140)` |  | → `Driver` |
| 5 | `driver_name` | Data | `varchar(140)` | ro, denorm←driver.full_name |  |
| 6 | `total_distance` | Float | `numeric(21,2)` | ro |  |
| 7 | `uom` | Link | `varchar(140)` | ro | → `UOM` |
| 8 | `vehicle` | Link | `varchar(140)` | NOT NULL | → `Vehicle` |
| 9 | `departure_time` | Datetime | `timestamp` | NOT NULL |  |
| 10 | `status` | Select | `varchar(140)` | ro | enum: Draft, Scheduled, In Transit, Completed, Cancelled |
| 11 | `amended_from` | Link | `varchar(140)` | ro | → `Delivery Trip` |
| 12 | `driver_address` | Link | `varchar(140)` | denorm←driver.address | → `Address` *(frappe/Contacts)* |
| 13 | `driver_email` | Data | `varchar(140)` | ro |  |
| 14 | `employee` | Link | `varchar(140)` | ro, denorm←driver.employee | → `Employee` |

**Child tables (1-N):**

- `delivery_stops` → `Delivery Stop` (line items)

**Referenced by (3):** `Delivery Note`.`delivery_trip`, `Delivery Trip`.`amended_from`, `Expense Claim`.`delivery_trip`

## Item Standard Cost

- **Table**: `tabItem Standard Cost`  (proposed: `item_standard_cost`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL, default=ISC-.YYYY.- | enum: ISC-.YYYY.- |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 3 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 4 | `standard_rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 5 | `effective_date` | Date | `date` | NOT NULL, default=Today |  |
| 6 | `revaluation_entry` | Link | `varchar(140)` | ro | → `Stock Reconciliation` |
| 7 | `amended_from` | Link | `varchar(140)` | INDEX, ro | → `Item Standard Cost` |

**Referenced by (1):** `Item Standard Cost`.`amended_from`

## Landed Cost Voucher

- **Table**: `tabLanded Cost Voucher`  (proposed: `landed_cost_voucher`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-LCV-.YYYY.- |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 4 | `distribute_charges_based_on` | Select | `varchar(140)` | NOT NULL | enum: Qty, Amount, Distribute Manually |
| 5 | `amended_from` | Link | `varchar(140)` | ro | → `Landed Cost Voucher` |
| 6 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 7 | `total_vendor_invoices_cost` | Currency | `numeric(21,9)` | ro |  |

**Child tables (1-N):**

- `purchase_receipts` → `Landed Cost Purchase Receipt` (line items)
- `items` → `Landed Cost Item` (line items)
- `taxes` → `Landed Cost Taxes and Charges` (line items)
- `vendor_invoices` → `Landed Cost Vendor Invoice` (line items)

**Referenced by (1):** `Landed Cost Voucher`.`amended_from`

## Material Request

- **Table**: `tabMaterial Request`  (proposed: `material_request`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `title`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status,transaction_date`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-MR-.YYYY.- |
| 2 | `title` | Data | `varchar(140)` | hidden |  |
| 3 | `material_request_type` | Select | `varchar(140)` | NOT NULL | enum: Purchase, Material Transfer, Material Issue, Manufacture, Subcontracting, Customer Provided |
| 4 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 5 | `schedule_date` | Date | `date` |  |  |
| 6 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 7 | `amended_from` | Link | `varchar(140)` | ro | → `Material Request` |
| 8 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 9 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 10 | `status` | Select | `varchar(140)` | INDEX, ro | enum: Draft, Submitted, Stopped, Cancelled, Pending, Partially Ordered, Partially Received, Ordered … (+3) |
| 11 | `per_ordered` | Percent | `numeric(21,9)` | ro |  |
| 12 | `per_received` | Percent | `numeric(21,9)` | ro |  |
| 13 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 14 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 15 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 16 | `terms` | Text Editor | `text` |  |  |
| 17 | `job_card` | Link | `varchar(140)` | ro | → `Job Card` |
| 18 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 19 | `set_from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 20 | `transfer_status` | Select | `varchar(140)` | ro | enum: Not Started, In Transit, Completed |
| 21 | `work_order` | Link | `varchar(140)` | ro | → `Work Order` |
| 22 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 23 | `auto_created_via_reorder` | Check | `smallint` | ro, default=0 |  |

**Child tables (1-N):**

- `items` → `Material Request Item` (line items)

**Referenced by (16):** `Purchase Invoice Item`.`material_request`, `Purchase Order Item`.`material_request`, `Request for Quotation Item`.`material_request`, `Supplier Quotation Item`.`material_request`, `Production Plan Item`.`material_request`, `Production Plan Material Request`.`material_request`, `Work Order`.`material_request`, `Sales Order Item`.`material_request`, `Delivery Note Item`.`material_request`, `Material Request`.`amended_from`, `Pick List`.`material_request`, `Pick List Item`.`material_request`, `Purchase Receipt Item`.`material_request`, `Stock Entry Detail`.`material_request`, `Subcontracting Order Item`.`material_request` … (+1 more)

## Packing Slip

- **Table**: `tabPacking Slip`  (proposed: `packing_slip`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `MAT-PAC-.YYYY.-.#####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Description**: Generate packing slips for packages to be delivered. Used to notify package number, package contents and its weight.
- **Search fields**: `delivery_note`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `delivery_note` | Link | `varchar(140)` | NOT NULL | → `Delivery Note` |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-PAC-.YYYY.- |
| 3 | `from_case_no` | Int | `integer` | NOT NULL |  |
| 4 | `to_case_no` | Int | `integer` |  |  |
| 5 | `net_weight_pkg` | Float | `numeric(21,9)` | ro |  |
| 6 | `net_weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 7 | `gross_weight_pkg` | Float | `numeric(21,9)` |  |  |
| 8 | `gross_weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 9 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `Packing Slip` |

**Child tables (1-N):**

- `items` → `Packing Slip Item` (line items)

**Referenced by (1):** `Packing Slip`.`amended_from`

## Pick List

- **Table**: `tabPick List`  (proposed: `pick_list`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `parent_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 3 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 4 | `work_order` | Link | `varchar(140)` |  | → `Work Order` |
| 5 | `for_qty` | Float | `numeric(21,9)` | ro |  |
| 6 | `amended_from` | Link | `varchar(140)` | ro | → `Pick List` |
| 7 | `purpose` | Select | `varchar(140)` | default=Material Transfer for Ma | enum: Material Transfer for Manufacture, Material Transfer, Delivery |
| 8 | `material_request` | Link | `varchar(140)` |  | → `Material Request` |
| 9 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: STO-PICK-.YYYY.- |
| 10 | `group_same_items` | Check | `smallint` | default=0 |  |
| 11 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 12 | `scan_mode` | Check | `smallint` | default=0 |  |
| 13 | `prompt_qty` | Check | `smallint` | default=0 |  |
| 14 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 15 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, hidden, default=Draft | enum: Draft, Open, Partly Delivered, Partially Transferred, Completed, Cancelled |
| 16 | `consider_rejected_warehouses` | Check | `smallint` | default=0 |  |
| 17 | `pick_manually` | Check | `smallint` | default=0 |  |
| 18 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 19 | `delivery_status` | Select | `varchar(140)` | hidden | enum: Not Delivered, Fully Delivered, Partly Delivered |
| 20 | `per_delivered` | Percent | `numeric(21,9)` | ro |  |

**Child tables (1-N):**

- `locations` → `Pick List Item` (line items)

**Referenced by (4):** `Sales Invoice Item`.`against_pick_list`, `Delivery Note Item`.`against_pick_list`, `Pick List`.`amended_from`, `Stock Entry`.`pick_list`

## Purchase Receipt

- **Table**: `tabPurchase Receipt`  (proposed: `purchase_receipt`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, posting_date, supplier`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-PRE-.YYYY.-, MAT-PR-RET-.YYYY.- |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 4 | `supplier_name` | Data | `varchar(140)` | ro, denorm←supplier.supplier_name |  |
| 5 | `supplier_delivery_note` | Data | `varchar(140)` |  |  |
| 6 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 7 | `posting_time` | Time | `time(6)` | NOT NULL, default=Now |  |
| 8 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 9 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 10 | `is_return` | Check | `smallint` | ro, default=0 |  |
| 11 | `return_against` | Link | `varchar(140)` | INDEX, ro | → `Purchase Receipt` |
| 12 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 13 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 14 | `address_display` | Text Editor | `text` | ro |  |
| 15 | `contact_display` | Small Text | `text` | ro |  |
| 16 | `contact_mobile` | Small Text | `text` | ro |  |
| 17 | `contact_email` | Small Text | `text` | ro |  |
| 18 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 19 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 20 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 21 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 22 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 23 | `price_list_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 24 | `plc_conversion_rate` | Float | `numeric(21,9)` |  |  |
| 25 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 26 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 27 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 28 | `is_subcontracted` | Check | `smallint` | ro, default=0 |  |
| 29 | `supplier_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 30 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 31 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 32 | `base_net_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 33 | `total` | Currency | `numeric(21,9)` | ro |  |
| 34 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 35 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 36 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 37 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 38 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 39 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 40 | `base_taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 41 | `base_taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 42 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 43 | `taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 44 | `taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 45 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 46 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 47 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 48 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 49 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 50 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 51 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 52 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 53 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 54 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 55 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 56 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 57 | `in_words` | Data | `varchar(140)` | ro |  |
| 58 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 59 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 60 | `terms` | Text Editor | `text` |  |  |
| 61 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, Partly Billed, To Bill, Completed, Return, Return Issued, Cancelled, Closed |
| 62 | `amended_from` | Link | `varchar(140)` | ro, hidden | → `Purchase Receipt` |
| 63 | `range` | Data | `varchar(140)` | hidden |  |
| 64 | `project` | Link | `varchar(140)` |  | → `Project` |
| 65 | `per_billed` | Percent | `numeric(21,9)` | ro |  |
| 66 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 67 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 68 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 69 | `language` | Data | `varchar(140)` | ro |  |
| 70 | `group_same_items` | Check | `smallint` | default=0 |  |
| 71 | `instructions` | Small Text | `text` |  |  |
| 72 | `remarks` | Small Text | `text` |  |  |
| 73 | `transporter_name` | Data | `varchar(140)` |  |  |
| 74 | `lr_no` | Data | `varchar(140)` |  |  |
| 75 | `lr_date` | Date | `date` |  |  |
| 76 | `is_internal_supplier` | Check | `smallint` | ro, denorm←supplier.is_internal_supplier, default=0 |  |
| 77 | `inter_company_reference` | Link | `varchar(140)` | INDEX, ro | → `Delivery Note` |
| 78 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 79 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 80 | `billing_address_display` | Text Editor | `text` | ro |  |
| 81 | `apply_putaway_rule` | Check | `smallint` | default=0 |  |
| 82 | `per_returned` | Percent | `numeric(21,9)` | ro |  |
| 83 | `set_from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 84 | `represents_company` | Link | `varchar(140)` | ro, denorm←supplier.represents_company | → `Company` |
| 85 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 86 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 87 | `named_place` | Data | `varchar(140)` |  |  |
| 88 | `subcontracting_receipt` | Link | `varchar(140)` | INDEX, ro | → `Subcontracting Receipt` |
| 89 | `dispatch_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 90 | `dispatch_address_display` | Text Editor | `text` | ro |  |

**Child tables (1-N):**

- `items` → `Purchase Receipt Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `supplied_items` → `Purchase Receipt Item Supplied` (line items)
- `taxes` → `Purchase Taxes and Charges` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (7):** `Purchase Invoice Item`.`purchase_receipt`, `Asset`.`purchase_receipt`, `Delivery Note`.`inter_company_reference`, `Purchase Receipt`.`return_against`, `Purchase Receipt`.`amended_from`, `Stock Entry`.`purchase_receipt_no`, `Stock Entry Detail`.`reference_purchase_receipt`

## Quality Inspection

- **Table**: `tabQuality Inspection`  (proposed: `quality_inspection`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `item_code, report_date, reference_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-QA-.YYYY.- |
| 2 | `report_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 3 | `inspection_type` | Select | `varchar(140)` | NOT NULL | enum: Incoming, Outgoing, In Process |
| 4 | `reference_type` | Select | `varchar(140)` | NOT NULL | enum: Purchase Receipt, Purchase Invoice, Subcontracting Receipt, Delivery Note, Sales Invoice, Stock Entry, Job Card |
| 5 | `reference_name` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `reference_type` |
| 6 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 7 | `item_serial_no` | Link | `varchar(140)` |  | → `Serial No` |
| 8 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 9 | `sample_size` | Float | `numeric(21,9)` | NOT NULL |  |
| 10 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 11 | `description` | Small Text | `text` | denorm←item_code.description |  |
| 12 | `inspected_by` | Link | `varchar(140)` | NOT NULL, default=user | → `User` *(frappe/Core)* |
| 13 | `verified_by` | Data | `varchar(140)` |  |  |
| 14 | `bom_no` | Link | `varchar(140)` | ro | → `BOM` |
| 15 | `remarks` | Text | `text` |  |  |
| 16 | `amended_from` | Link | `varchar(140)` | ro | → `Quality Inspection` |
| 17 | `quality_inspection_template` | Link | `varchar(140)` |  | → `Quality Inspection Template` |
| 18 | `status` | Select | `varchar(140)` | NOT NULL, default=Accepted | enum: Accepted, Rejected, Cancelled |
| 19 | `manual_inspection` | Check | `smallint` | default=0 |  |
| 20 | `child_row_reference` | Data | `varchar(140)` | ro, hidden |  |
| 21 | `company` | Link | `varchar(140)` |  | → `Company` |
| 22 | `letter_head` | Link | `varchar(140)` | denorm←company.default_letter_head | → `Letter Head` *(frappe/Printing)* |

**Child tables (1-N):**

- `readings` → `Quality Inspection Reading` (line items)

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_type`

**Referenced by (9):** `POS Invoice Item`.`quality_inspection`, `Purchase Invoice Item`.`quality_inspection`, `Sales Invoice Item`.`quality_inspection`, `Job Card`.`quality_inspection`, `Delivery Note Item`.`quality_inspection`, `Purchase Receipt Item`.`quality_inspection`, `Quality Inspection`.`amended_from`, `Stock Entry Detail`.`quality_inspection`, `Subcontracting Receipt Item`.`quality_inspection`

## Repost Item Valuation

- **Table**: `tabRepost Item Valuation`  (proposed: `repost_item_valuation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` |  | → `Item` |
| 2 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 3 | `posting_date` | Date | `date` | NOT NULL, denorm←voucher_no.posting_date |  |
| 4 | `posting_time` | Time | `time(6)` | denorm←voucher_no.posting_time |  |
| 5 | `status` | Select | `varchar(140)` | ro, default=Queued | enum: Queued, In Progress, Completed, Skipped, Failed, Cancelled |
| 6 | `amended_from` | Link | `varchar(140)` | ro | → `Repost Item Valuation` |
| 7 | `error_log` | Long Text | `text` | ro |  |
| 8 | `company` | Link | `varchar(140)` | denorm←warehouse.company | → `Company` |
| 9 | `voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 10 | `voucher_no` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `voucher_type` |
| 11 | `based_on` | Select | `varchar(140)` | NOT NULL, default=Transaction | enum: Transaction, Item and Warehouse |
| 12 | `allow_negative_stock` | Check | `smallint` | default=1 |  |
| 13 | `via_landed_cost_voucher` | Check | `smallint` | default=0 |  |
| 14 | `allow_zero_rate` | Check | `smallint` | default=0 |  |
| 15 | `items_to_be_repost` | Code | `text` | ro, hidden |  |
| 16 | `current_index` | Int | `integer` | ro, hidden |  |
| 17 | `gl_reposting_index` | Int | `integer` | ro, hidden, default=0 |  |
| 18 | `total_reposting_count` | Int | `integer` | ro |  |
| 19 | `recreate_stock_ledgers` | Check | `smallint` | default=0 |  |
| 20 | `reposting_reference` | Data | `varchar(140)` | INDEX, ro |  |
| 21 | `repost_only_accounting_ledgers` | Check | `smallint` | default=0 |  |
| 22 | `total_vouchers` | Int | `integer` | ro |  |
| 23 | `vouchers_posted` | Int | `integer` | ro |  |
| 24 | `reposting_data_file` | Attach | `text` | ro |  |
| 25 | `recalculate_valuation_rate` | Check | `smallint` | default=0 |  |

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

**Referenced by (1):** `Repost Item Valuation`.`amended_from`

## Serial and Batch Bundle

- **Table**: `tabSerial and Batch Bundle`  (proposed: `serial_and_batch_bundle`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Title field**: `item_code`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `item_group` | Link | `varchar(140)` | hidden, denorm←item_code.item_group | → `Item Group` |
| 3 | `has_serial_no` | Check | `smallint` | ro, denorm←item_code.has_serial_no, default=0 |  |
| 4 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 5 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 6 | `has_batch_no` | Check | `smallint` | ro, denorm←item_code.has_batch_no, default=0 |  |
| 7 | `voucher_type` | Link | `varchar(140)` | NOT NULL, INDEX | → `DocType` *(frappe/Core)* |
| 8 | `voucher_no` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `voucher_type` |
| 9 | `is_cancelled` | Check | `smallint` | ro, default=0 |  |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `Serial and Batch Bundle` |
| 11 | `avg_rate` | Float | `numeric(21,9)` | ro |  |
| 12 | `total_amount` | Float | `numeric(21,9)` | ro |  |
| 13 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 15 | `type_of_transaction` | Select | `varchar(140)` | NOT NULL | enum: Inward, Outward, Maintenance, Asset Repair |
| 16 | `is_rejected` | Check | `smallint` | ro, default=0 |  |
| 17 | `voucher_detail_no` | Data | `varchar(140)` | INDEX, ro |  |
| 18 | `returned_against` | Data | `varchar(140)` | ro |  |
| 19 | `naming_series` | Select | `varchar(140)` | default=SABB-.######## | enum: SABB-.######## |
| 20 | `is_packed` | Check | `smallint` | default=0 |  |
| 21 | `posting_datetime` | Datetime | `timestamp` |  |  |

**Child tables (1-N):**

- `entries` → `Serial and Batch Entry` (line items)

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

**Referenced by (22):** `POS Invoice Item`.`serial_and_batch_bundle`, `Purchase Invoice Item`.`serial_and_batch_bundle`, `Purchase Invoice Item`.`rejected_serial_and_batch_bundle`, `Sales Invoice Item`.`serial_and_batch_bundle`, `Asset Capitalization Stock Item`.`serial_and_batch_bundle`, `Asset Repair Consumed Item`.`serial_and_batch_bundle`, `Maintenance Schedule Item`.`serial_and_batch_bundle`, `Job Card`.`serial_and_batch_bundle`, `Installation Note Item`.`serial_and_batch_bundle`, `Delivery Note Item`.`serial_and_batch_bundle`, `Packed Item`.`serial_and_batch_bundle`, `Pick List Item`.`serial_and_batch_bundle`, `Purchase Receipt Item`.`serial_and_batch_bundle`, `Purchase Receipt Item`.`rejected_serial_and_batch_bundle`, `Serial and Batch Bundle`.`amended_from` … (+7 more)

## Shipment

- **Table**: `tabShipment`  (proposed: `shipment`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `SHIPMENT-.#####`  (Expression)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `pickup_from_type` | Select | `varchar(140)` | default=Company | enum: Company, Customer, Supplier |
| 2 | `pickup_company` | Link | `varchar(140)` |  | → `Company` |
| 3 | `pickup_customer` | Link | `varchar(140)` |  | → `Customer` |
| 4 | `pickup_supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 5 | `pickup` | Data | `varchar(140)` | ro, hidden |  |
| 6 | `pickup_address_name` | Link | `varchar(140)` | NOT NULL | → `Address` *(frappe/Contacts)* |
| 7 | `pickup_address` | Text Editor | `text` | ro |  |
| 8 | `pickup_contact_name` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 9 | `pickup_contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 10 | `pickup_contact` | Text Editor | `text` | ro |  |
| 11 | `delivery_to_type` | Select | `varchar(140)` | default=Customer | enum: Company, Customer, Supplier |
| 12 | `delivery_company` | Link | `varchar(140)` |  | → `Company` |
| 13 | `delivery_customer` | Link | `varchar(140)` |  | → `Customer` |
| 14 | `delivery_supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 15 | `delivery_to` | Data | `varchar(140)` | ro, hidden |  |
| 16 | `delivery_address_name` | Link | `varchar(140)` | NOT NULL | → `Address` *(frappe/Contacts)* |
| 17 | `delivery_address` | Text Editor | `text` | ro |  |
| 18 | `delivery_contact_name` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 19 | `delivery_contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 20 | `delivery_contact` | Text Editor | `text` | ro |  |
| 21 | `parcel_template` | Link | `varchar(140)` |  | → `Shipment Parcel Template` |
| 22 | `pallets` | Select | `varchar(140)` | default=No | enum: No, Yes |
| 23 | `value_of_goods` | Currency | `numeric(21,2)` | NOT NULL |  |
| 24 | `pickup_date` | Date | `date` | NOT NULL |  |
| 25 | `pickup_from` | Time | `time(6)` | NOT NULL, default=09:00 |  |
| 26 | `pickup_to` | Time | `time(6)` | NOT NULL, default=17:00 |  |
| 27 | `shipment_type` | Select | `varchar(140)` | default=Goods | enum: Goods, Documents |
| 28 | `pickup_type` | Select | `varchar(140)` | default=Pickup | enum: Pickup, Self delivery |
| 29 | `description_of_content` | Small Text | `text` | NOT NULL |  |
| 30 | `service_provider` | Data | `varchar(140)` |  |  |
| 31 | `shipment_id` | Data | `varchar(140)` |  |  |
| 32 | `shipment_amount` | Currency | `numeric(21,2)` |  |  |
| 33 | `status` | Select | `varchar(140)` | ro | enum: Draft, Submitted, Booked, Cancelled, Completed |
| 34 | `tracking_url` | Small Text | `text` | ro, hidden |  |
| 35 | `carrier` | Data | `varchar(140)` |  |  |
| 36 | `carrier_service` | Data | `varchar(140)` |  |  |
| 37 | `awb_number` | Data | `varchar(140)` |  |  |
| 38 | `tracking_status` | Select | `varchar(140)` |  | enum: In Progress, Delivered, Returned, Lost |
| 39 | `tracking_status_info` | Data | `varchar(140)` | ro |  |
| 40 | `amended_from` | Link | `varchar(140)` | ro, hidden | → `Shipment` |
| 41 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 42 | `pickup_contact_person` | Link | `varchar(140)` |  | → `User` *(frappe/Core)* |
| 43 | `total_weight` | Float | `numeric(21,9)` | ro |  |

**Child tables (1-N):**

- `shipment_parcel` → `Shipment Parcel` (line items)
- `shipment_delivery_note` → `Shipment Delivery Note` (line items)

**Referenced by (1):** `Shipment`.`amended_from`

## Stock Closing Entry

- **Table**: `tabStock Closing Entry`  (proposed: `stock_closing_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: CBAL-.##### |
| 2 | `company` | Link | `varchar(140)` | INDEX | → `Company` |
| 3 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Queued, In Progress, Completed, Failed, Cancelled |
| 4 | `from_date` | Date | `date` |  |  |
| 5 | `to_date` | Date | `date` |  |  |
| 6 | `amended_from` | Link | `varchar(140)` | INDEX, ro | → `Stock Closing Entry` |

**Referenced by (2):** `Stock Closing Balance`.`stock_closing_entry`, `Stock Closing Entry`.`amended_from`

## Stock Entry

- **Table**: `tabStock Entry`  (proposed: `stock_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `stock_entry_type`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `posting_date, from_warehouse, to_warehouse, purpose, remarks`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-STE-.YYYY.- |
| 2 | `stock_entry_type` | Link | `varchar(140)` | NOT NULL, INDEX | → `Stock Entry Type` |
| 3 | `outgoing_stock_entry` | Link | `varchar(140)` | ro | → `Stock Entry` |
| 4 | `source_stock_entry` | Link | `varchar(140)` |  | → `Stock Entry` |
| 5 | `purpose` | Select | `varchar(140)` | INDEX, ro, hidden, denorm←stock_entry_type.purpose | enum: Material Issue, Material Receipt, Material Transfer, Material Transfer for Manufacture, Material Consumption for Manufacture, Manufacture, Repack, Send to Subcontractor … (+5) |
| 6 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 7 | `work_order` | Link | `varchar(140)` | INDEX | → `Work Order` |
| 8 | `purchase_order` | Link | `varchar(140)` |  | → `Purchase Order` |
| 9 | `subcontracting_order` | Link | `varchar(140)` | ro | → `Subcontracting Order` |
| 10 | `delivery_note_no` | Link | `varchar(140)` | INDEX, ro | → `Delivery Note` |
| 11 | `sales_invoice_no` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 12 | `purchase_receipt_no` | Link | `varchar(140)` | INDEX, ro | → `Purchase Receipt` |
| 13 | `posting_date` | Date | `date` | INDEX, default=Today |  |
| 14 | `posting_time` | Time | `time(6)` | default=Now |  |
| 15 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 16 | `inspection_required` | Check | `smallint` | default=0 |  |
| 17 | `from_bom` | Check | `smallint` | default=0 |  |
| 18 | `bom_no` | Link | `varchar(140)` |  | → `BOM` |
| 19 | `fg_completed_qty` | Float | `numeric(21,9)` |  |  |
| 20 | `use_multi_level_bom` | Check | `smallint` | default=1 |  |
| 21 | `from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 22 | `source_warehouse_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 23 | `source_address_display` | Text Editor | `text` | ro |  |
| 24 | `to_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 25 | `target_warehouse_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 26 | `target_address_display` | Text Editor | `text` | ro |  |
| 27 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 28 | `total_incoming_value` | Currency | `numeric(21,9)` | ro |  |
| 29 | `total_outgoing_value` | Currency | `numeric(21,9)` | ro |  |
| 30 | `value_difference` | Currency | `numeric(21,9)` | ro |  |
| 31 | `total_additional_costs` | Currency | `numeric(21,9)` | ro |  |
| 32 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 33 | `supplier_name` | Data | `varchar(140)` | ro |  |
| 34 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 35 | `address_display` | Text Editor | `text` |  |  |
| 36 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 37 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 38 | `is_opening` | Select | `varchar(140)` |  | enum: No, Yes |
| 39 | `project` | Link | `varchar(140)` |  | → `Project` |
| 40 | `remarks` | Text | `text` |  |  |
| 41 | `per_transferred` | Percent | `numeric(21,9)` | ro |  |
| 42 | `total_amount` | Currency | `numeric(21,9)` | ro |  |
| 43 | `job_card` | Link | `varchar(140)` | INDEX, ro | → `Job Card` |
| 44 | `amended_from` | Link | `varchar(140)` | ro | → `Stock Entry` |
| 45 | `credit_note` | Link | `varchar(140)` | hidden | → `Journal Entry` |
| 46 | `pick_list` | Link | `varchar(140)` | INDEX, ro | → `Pick List` |
| 47 | `add_to_transit` | Check | `smallint` | denorm←stock_entry_type.add_to_transit, default=0 |  |
| 48 | `apply_putaway_rule` | Check | `smallint` | default=0 |  |
| 49 | `is_return` | Check | `smallint` | ro, hidden, default=0 |  |
| 50 | `process_loss_qty` | Float | `numeric(21,9)` |  |  |
| 51 | `process_loss_percentage` | Percent | `numeric(21,9)` |  |  |
| 52 | `asset_repair` | Link | `varchar(140)` | ro | → `Asset Repair` |
| 53 | `is_additional_transfer_entry` | Check | `smallint` | ro, hidden, default=0 |  |
| 54 | `subcontracting_inward_order` | Link | `varchar(140)` | ro | → `Subcontracting Inward Order` |
| 55 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |

**Child tables (1-N):**

- `items` → `Stock Entry Detail` (line items)
- `additional_costs` → `Landed Cost Taxes and Charges` (line items)

**Referenced by (5):** `Journal Entry`.`stock_entry`, `Stock Entry`.`outgoing_stock_entry`, `Stock Entry`.`source_stock_entry`, `Stock Entry`.`amended_from`, `Stock Entry Detail`.`against_stock_entry`

## Stock Ledger Entry

- **Table**: `tabStock Ledger Entry`  (proposed: `stock_ledger_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `MAT-SLE-.YYYY.-.#####`  (Expression)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `serial_no` | Long Text | `text` | ro |  |
| 3 | `batch_no` | Data | `varchar(140)` | INDEX, ro |  |
| 4 | `warehouse` | Link | `varchar(140)` | ro | → `Warehouse` |
| 5 | `posting_date` | Date | `date` | ro |  |
| 6 | `posting_time` | Time | `time(6)` | ro |  |
| 7 | `voucher_type` | Link | `varchar(140)` | INDEX, ro | → `DocType` *(frappe/Core)* |
| 8 | `voucher_no` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `voucher_type` |
| 9 | `voucher_detail_no` | Data | `varchar(140)` | INDEX, ro |  |
| 10 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 11 | `incoming_rate` | Currency | `numeric(21,9)` | ro |  |
| 12 | `outgoing_rate` | Currency | `numeric(21,9)` | ro |  |
| 13 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 14 | `qty_after_transaction` | Float | `numeric(21,9)` | ro |  |
| 15 | `valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `stock_value` | Currency | `numeric(21,9)` | ro |  |
| 17 | `stock_value_difference` | Currency | `numeric(21,9)` | ro |  |
| 18 | `stock_queue` | Long Text | `text` | ro |  |
| 19 | `project` | Link | `varchar(140)` |  | → `Project` |
| 20 | `company` | Link | `varchar(140)` | ro | → `Company` |
| 21 | `fiscal_year` | Data | `varchar(140)` | ro |  |
| 22 | `is_cancelled` | Check | `smallint` | default=0 |  |
| 23 | `to_rename` | Check | `smallint` | INDEX, hidden, default=1 |  |
| 24 | `dependant_sle_voucher_detail_no` | Data | `varchar(140)` |  |  |
| 25 | `recalculate_rate` | Check | `smallint` | ro, default=0 |  |
| 26 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 27 | `has_batch_no` | Check | `smallint` | denorm←item_code.has_batch_no, default=0 |  |
| 28 | `has_serial_no` | Check | `smallint` | denorm←item_code.has_serial_no, default=0 |  |
| 29 | `is_adjustment_entry` | Check | `smallint` | default=0 |  |
| 30 | `auto_created_serial_and_batch_bundle` | Check | `smallint` | default=0 |  |
| 31 | `posting_datetime` | Datetime | `timestamp` |  |  |

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

## Stock Reconciliation

- **Table**: `tabStock Reconciliation`  (proposed: `stock_reconciliation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Description**: This tool helps you to update or fix the quantity and valuation of stock in the system. It is typically used to synchronise the system values and what actually exists in your warehouses.
- **Search fields**: `posting_date`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-RECO-.YYYY.- |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `purpose` | Select | `varchar(140)` | NOT NULL | enum: Opening Stock, Stock Reconciliation |
| 4 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 5 | `posting_time` | Time | `time(6)` | NOT NULL, default=Now |  |
| 6 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 7 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 8 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 9 | `difference_amount` | Currency | `numeric(21,9)` | ro |  |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `Stock Reconciliation` |
| 11 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 12 | `scan_mode` | Check | `smallint` | default=0 |  |
| 13 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |

**Child tables (1-N):**

- `items` → `Stock Reconciliation Item` (line items)

**Referenced by (2):** `Item Standard Cost`.`revaluation_entry`, `Stock Reconciliation`.`amended_from`

## Stock Reservation Entry

- **Table**: `tabStock Reservation Entry`  (proposed: `stock_reservation_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Stock
- **Naming**: `MAT-SRE-.YYYY.-.#####`  (Expression)
- **Title field**: `voucher_no`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | INDEX, ro | → `Item` |
| 2 | `warehouse` | Link | `varchar(140)` | INDEX, ro | → `Warehouse` |
| 3 | `voucher_type` | Select | `varchar(140)` | ro | enum: Sales Order, Work Order, Subcontracting Inward Order, Production Plan, Subcontracting Order |
| 4 | `voucher_no` | Dynamic Link | `varchar(140)` | INDEX, ro | → polymorphic, doctype in `voucher_type` |
| 5 | `voucher_detail_no` | Data | `varchar(140)` | INDEX, ro |  |
| 6 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 7 | `project` | Link | `varchar(140)` | INDEX, ro | → `Project` |
| 8 | `company` | Link | `varchar(140)` | INDEX, ro | → `Company` |
| 9 | `reserved_qty` | Float | `numeric(21,9)` | ro |  |
| 10 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Partially Reserved, Reserved, Partially Delivered, Partially Used, Delivered, Cancelled, Closed |
| 11 | `delivered_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 12 | `amended_from` | Link | `varchar(140)` | ro | → `Stock Reservation Entry` |
| 13 | `available_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 14 | `voucher_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 15 | `has_serial_no` | Check | `smallint` | ro, default=0 |  |
| 16 | `has_batch_no` | Check | `smallint` | ro, default=0 |  |
| 17 | `reservation_based_on` | Select | `varchar(140)` | ro, default=Qty | enum: Qty, Serial and Batch |
| 18 | `from_voucher_type` | Select | `varchar(140)` | ro | enum: Pick List, Purchase Receipt, Stock Entry, Work Order, Production Plan, Subcontracting Inward Order |
| 19 | `from_voucher_detail_no` | Data | `varchar(140)` | ro |  |
| 20 | `from_voucher_no` | Dynamic Link | `varchar(140)` | INDEX, ro | → polymorphic, doctype in `from_voucher_type` |
| 21 | `consumed_qty` | Float | `numeric(21,9)` |  |  |
| 22 | `transferred_qty` | Float | `numeric(21,9)` |  |  |

**Child tables (1-N):**

- `sb_entries` → `Serial and Batch Entry` (line items)

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`
- `from_voucher_no` — target DocType read from `from_voucher_type`

**Referenced by (1):** `Stock Reservation Entry`.`amended_from`

---

# Child / line-item tables

## Company Restriction

- **Table**: `tabCompany Restriction`  (proposed: `company_restriction`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Supplier`.`allowed_companies`, `Customer`.`allowed_companies`, `Item`.`allowed_companies`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

## Delivery Note Item

- **Table**: `tabDelivery Note Item`  (proposed: `delivery_note_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Delivery Note`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 3 | `is_product_bundle` | Check | `smallint` | ro, hidden, default=0 |  |
| 4 | `product_bundle` | Link | `varchar(140)` |  | → `Product Bundle` |
| 5 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 6 | `customer_item_code` | Data | `varchar(140)` | ro, hidden |  |
| 7 | `description` | Text Editor | `text` |  |  |
| 8 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 9 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 10 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 11 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 12 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 13 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 15 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 17 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 18 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 19 | `discount_percentage` | Float | `numeric(21,9)` |  |  |
| 20 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 21 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 22 | `rate` | Currency | `numeric(21,9)` |  |  |
| 23 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 24 | `base_rate` | Currency | `numeric(21,9)` | ro |  |
| 25 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 26 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 27 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 28 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 29 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 30 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 31 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 32 | `weight_per_unit` | Float | `numeric(21,9)` |  |  |
| 33 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 34 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 35 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 36 | `target_warehouse` | Link | `varchar(140)` | hidden | → `Warehouse` |
| 37 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 38 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 39 | `actual_batch_qty` | Float | `numeric(21,9)` | ro |  |
| 40 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 41 | `brand` | Link | `varchar(140)` | ro, hidden | → `Brand` |
| 42 | `item_tax_rate` | Small Text | `text` | ro, hidden |  |
| 43 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 44 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 45 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 46 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 47 | `against_sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 48 | `against_sales_invoice` | Link | `varchar(140)` | INDEX, ro | → `Sales Invoice` |
| 49 | `so_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 50 | `si_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 51 | `installed_qty` | Float | `numeric(21,9)` | ro |  |
| 52 | `billed_amt` | Currency | `numeric(21,9)` | ro |  |
| 53 | `page_break` | Check | `smallint` | default=0 |  |
| 54 | `project` | Link | `varchar(140)` |  | → `Project` |
| 55 | `dn_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 56 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 57 | `incoming_rate` | Currency | `numeric(21,9)` | ro |  |
| 58 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 59 | `grant_commission` | Check | `smallint` | ro, denorm←item_code.grant_commission, default=0 |  |
| 60 | `pick_list_item` | Data | `varchar(140)` | ro, hidden |  |
| 61 | `purchase_order` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 62 | `purchase_order_item` | Data | `varchar(140)` | ro |  |
| 63 | `has_item_scanned` | Check | `smallint` | ro, default=0 |  |
| 64 | `material_request` | Link | `varchar(140)` |  | → `Material Request` |
| 65 | `material_request_item` | Data | `varchar(140)` |  |  |
| 66 | `received_qty` | Float | `numeric(21,9)` | ro |  |
| 67 | `packed_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 68 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 69 | `serial_no` | Text | `text` |  |  |
| 70 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 71 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 72 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 73 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |
| 74 | `against_pick_list` | Link | `varchar(140)` | INDEX, ro | → `Pick List` |

## Delivery Stop

- **Table**: `tabDelivery Stop`  (proposed: `delivery_stop`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Delivery Trip`.`delivery_stops`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 2 | `address` | Link | `varchar(140)` | NOT NULL | → `Address` *(frappe/Contacts)* |
| 3 | `locked` | Check | `smallint` | default=0 |  |
| 4 | `customer_address` | Small Text | `text` | ro |  |
| 5 | `visited` | Check | `smallint` | default=0 |  |
| 6 | `delivery_note` | Link | `varchar(140)` | ro | → `Delivery Note` |
| 7 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 8 | `contact` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 9 | `email_sent_to` | Data | `varchar(140)` | ro |  |
| 10 | `customer_contact` | Small Text | `text` | ro |  |
| 11 | `distance` | Float | `numeric(21,2)` | ro |  |
| 12 | `estimated_arrival` | Datetime | `timestamp` |  |  |
| 13 | `lat` | Float | `numeric(21,9)` | hidden |  |
| 14 | `uom` | Link | `varchar(140)` | ro | → `UOM` |
| 15 | `lng` | Float | `numeric(21,9)` | hidden |  |
| 16 | `details` | Text Editor | `text` |  |  |

## Item Attribute Value

- **Table**: `tabItem Attribute Value`  (proposed: `item_attribute_value`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Item Attribute`.`item_attribute_values`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `attribute_value` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `abbr` | Data | `varchar(140)` | NOT NULL, INDEX |  |

## Item Barcode

- **Table**: `tabItem Barcode`  (proposed: `item_barcode`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Item`.`barcodes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `barcode_type` | Select | `varchar(140)` |  | enum: EAN, UPC-A, CODE-39, EAN-13, EAN-8, GS1, GTIN, GTIN-14 … (+7) |
| 3 | `uom` | Link | `varchar(140)` |  | → `UOM` |

## Item Customer Detail

- **Table**: `tabItem Customer Detail`  (proposed: `item_customer_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`
- **Description**: For the convenience of customers, these codes can be used in print formats like Invoices and Delivery Notes
- **Embedded in**: `Item`.`customer_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer_name` | Link | `varchar(140)` | INDEX | → `Customer` |
| 2 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 3 | `ref_code` | Data | `varchar(140)` | NOT NULL, INDEX |  |

## Item Default

- **Table**: `tabItem Default`  (proposed: `item_default`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Brand`.`brand_defaults`, `Item Group`.`item_group_defaults`, `Item`.`item_defaults`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `default_warehouse` | Link | `varchar(140)` | INDEX | → `Warehouse` |
| 3 | `default_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 4 | `default_discount_account` | Link | `varchar(140)` |  | → `Account` |
| 5 | `default_inventory_account` | Link | `varchar(140)` |  | → `Account` |
| 6 | `inventory_account_currency` | Link | `varchar(140)` | ro, denorm←default_inventory_account.account_currency | → `Currency` *(frappe/Geo)* |
| 7 | `buying_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 8 | `default_supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 9 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 10 | `default_provisional_account` | Link | `varchar(140)` |  | → `Account` |
| 11 | `purchase_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 12 | `purchase_expense_contra_account` | Link | `varchar(140)` |  | → `Account` |
| 13 | `expenses_added_to_stock_account` | Link | `varchar(140)` |  | → `Account` |
| 14 | `expenses_added_to_stock_contra_account` | Link | `varchar(140)` |  | → `Account` |
| 15 | `purchase_price_variance_account` | Link | `varchar(140)` |  | → `Account` |
| 16 | `manufacturing_variance_account` | Link | `varchar(140)` |  | → `Account` |
| 17 | `selling_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 18 | `income_account` | Link | `varchar(140)` |  | → `Account` |
| 19 | `default_cogs_account` | Link | `varchar(140)` |  | → `Account` |
| 20 | `deferred_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 21 | `deferred_revenue_account` | Link | `varchar(140)` |  | → `Account` |

## Item Quality Inspection Parameter

- **Table**: `tabItem Quality Inspection Parameter`  (proposed: `item_quality_inspection_parameter`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`
- **Embedded in**: `Quality Inspection Template`.`item_quality_inspection_parameter`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `specification` | Link | `varchar(140)` | NOT NULL | → `Quality Inspection Parameter` |
| 2 | `value` | Data | `varchar(140)` |  |  |
| 3 | `acceptance_formula` | Code | `text` |  |  |
| 4 | `formula_based_criteria` | Check | `smallint` | default=0 |  |
| 5 | `min_value` | Float | `numeric(21,9)` |  |  |
| 6 | `max_value` | Float | `numeric(21,9)` |  |  |
| 7 | `numeric` | Check | `smallint` | default=1 |  |
| 8 | `parameter_group` | Link | `varchar(140)` | ro, denorm←specification.parameter_group | → `Quality Inspection Parameter Group` |

## Item Reorder

- **Table**: `tabItem Reorder`  (proposed: `item_reorder`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Item`.`reorder_levels`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `warehouse_group` | Link | `varchar(140)` |  | → `Warehouse` |
| 2 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 3 | `warehouse_reorder_level` | Float | `numeric(21,9)` |  |  |
| 4 | `warehouse_reorder_qty` | Float | `numeric(21,9)` |  |  |
| 5 | `material_request_type` | Select | `varchar(140)` | NOT NULL | enum: Purchase, Transfer, Material Issue, Manufacture |

## Item Supplier

- **Table**: `tabItem Supplier`  (proposed: `item_supplier`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Item`.`supplier_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier` | Link | `varchar(140)` | NOT NULL | → `Supplier` |
| 2 | `supplier_part_no` | Data | `varchar(140)` |  |  |

## Item Tax

- **Table**: `tabItem Tax`  (proposed: `item_tax`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Item Group`.`taxes`, `Item`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_tax_template` | Link | `varchar(140)` | NOT NULL | → `Item Tax Template` |
| 2 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 3 | `valid_from` | Date | `date` |  |  |
| 4 | `maximum_net_rate` | Float | `numeric(21,9)` |  |  |
| 5 | `minimum_net_rate` | Float | `numeric(21,9)` |  |  |

## Item Variant

- **Table**: `tabItem Variant`  (proposed: `item_variant`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_attribute` | Link | `varchar(140)` | NOT NULL | → `Item Attribute` |
| 2 | `item_attribute_value` | Data | `varchar(140)` | NOT NULL |  |

## Item Variant Attribute

- **Table**: `tabItem Variant Attribute`  (proposed: `item_variant_attribute`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Item`.`attributes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `variant_of` | Link | `varchar(140)` | INDEX | → `Item` |
| 2 | `attribute` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item Attribute` |
| 3 | `attribute_value` | Data | `varchar(140)` |  |  |
| 4 | `numeric_values` | Check | `smallint` | default=0 |  |
| 5 | `from_range` | Float | `numeric(21,9)` |  |  |
| 6 | `increment` | Float | `numeric(21,9)` |  |  |
| 7 | `to_range` | Float | `numeric(21,9)` |  |  |
| 8 | `disabled` | Check | `smallint` | denorm←attribute.disabled, default=0 |  |

## Item Website Specification

- **Table**: `tabItem Website Specification`  (proposed: `item_website_specification`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Description**: Table for Item that will be shown in Web Site
- **Embedded in**: `Website Item`.`website_specifications`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `label` | Data | `varchar(140)` |  |  |
| 2 | `description` | Text Editor | `text` |  |  |

## Landed Cost Item

- **Table**: `tabLanded Cost Item`  (proposed: `landed_cost_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Landed Cost Voucher`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 2 | `description` | Text Editor | `text` | ro |  |
| 3 | `receipt_document_type` | Select | `varchar(140)` | ro | enum: Purchase Invoice, Purchase Receipt, Stock Entry, Subcontracting Receipt |
| 4 | `receipt_document` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `receipt_document_type` |
| 5 | `qty` | Float | `numeric(21,9)` | ro |  |
| 6 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 7 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 8 | `applicable_charges` | Currency | `numeric(21,9)` |  |  |
| 9 | `purchase_receipt_item` | Data | `varchar(140)` | ro, hidden |  |
| 10 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 11 | `is_fixed_asset` | Check | `smallint` | ro, hidden, denorm←item_code.is_fixed_asset, default=0 |  |
| 12 | `stock_entry_item` | Data | `varchar(140)` | ro |  |

**Polymorphic references:**

- `receipt_document` — target DocType read from `receipt_document_type`

## Landed Cost Purchase Receipt

- **Table**: `tabLanded Cost Purchase Receipt`  (proposed: `landed_cost_purchase_receipt`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Landed Cost Voucher`.`purchase_receipts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `receipt_document_type` | Select | `varchar(140)` | NOT NULL | enum: Purchase Invoice, Purchase Receipt, Stock Entry, Subcontracting Receipt |
| 2 | `receipt_document` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `receipt_document_type` |
| 3 | `supplier` | Link | `varchar(140)` | ro | → `Supplier` |
| 4 | `posting_date` | Date | `date` | ro |  |
| 5 | `grand_total` | Currency | `numeric(21,9)` | ro |  |

**Polymorphic references:**

- `receipt_document` — target DocType read from `receipt_document_type`

## Landed Cost Taxes and Charges

- **Table**: `tabLanded Cost Taxes and Charges`  (proposed: `landed_cost_taxes_and_charges`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Landed Cost Voucher`.`taxes`, `Stock Entry`.`additional_costs`, `Subcontracting Order`.`additional_costs`, `Subcontracting Receipt`.`additional_costs`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `description` | Small Text | `text` | NOT NULL |  |
| 2 | `amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 3 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 4 | `account_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 5 | `exchange_rate` | Float | `numeric(21,9)` |  |  |
| 6 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 7 | `has_corrective_cost` | Check | `smallint` | ro, default=0 |  |
| 8 | `has_operating_cost` | Check | `smallint` | ro, default=0 |  |
| 9 | `operation_id` | Data | `varchar(140)` | ro, hidden |  |
| 10 | `qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 11 | `operating_component` | Data | `varchar(140)` | ro, hidden |  |

## Landed Cost Vendor Invoice

- **Table**: `tabLanded Cost Vendor Invoice`  (proposed: `landed_cost_vendor_invoice`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Landed Cost Voucher`.`vendor_invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `vendor_invoice` | Link | `varchar(140)` | INDEX | → `Purchase Invoice` |
| 2 | `amount` | Currency | `numeric(21,9)` | ro |  |

## Material Request Item

- **Table**: `tabMaterial Request Item`  (proposed: `material_request_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Material Request`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | INDEX |  |
| 3 | `description` | Text Editor | `text` |  |  |
| 4 | `image` | Attach Image | `text` | ro, denorm←item_code.image |  |
| 5 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 6 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 7 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 8 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 9 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 10 | `schedule_date` | Date | `date` | NOT NULL |  |
| 11 | `rate` | Currency | `numeric(21,9)` |  |  |
| 12 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 13 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `item_group` | Link | `varchar(140)` | INDEX, ro | → `Item Group` |
| 15 | `brand` | Link | `varchar(140)` | ro | → `Brand` |
| 16 | `lead_time_date` | Date | `date` | ro |  |
| 17 | `sales_order` | Link | `varchar(140)` | ro | → `Sales Order` |
| 18 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 19 | `project` | Link | `varchar(140)` |  | → `Project` |
| 20 | `production_plan` | Link | `varchar(140)` | ro | → `Production Plan` |
| 21 | `material_request_plan_item` | Data | `varchar(140)` | ro |  |
| 22 | `min_order_qty` | Float | `numeric(21,9)` | ro |  |
| 23 | `projected_qty` | Float | `numeric(21,9)` | ro |  |
| 24 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 25 | `ordered_qty` | Float | `numeric(21,9)` | ro |  |
| 26 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 27 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 28 | `page_break` | Check | `smallint` | default=0 |  |
| 29 | `received_qty` | Float | `numeric(21,9)` | ro |  |
| 30 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 31 | `manufacturer_part_no` | Data | `varchar(140)` | ro |  |
| 32 | `from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 33 | `bom_no` | Link | `varchar(140)` |  | → `BOM` |
| 34 | `job_card_item` | Data | `varchar(140)` | hidden |  |
| 35 | `wip_composite_asset` | Link | `varchar(140)` |  | → `Asset` |
| 36 | `price_list_rate` | Currency | `numeric(21,9)` | ro, hidden |  |
| 37 | `reorder_level` | Float | `numeric(21,9)` | ro |  |
| 38 | `reorder_qty` | Float | `numeric(21,9)` | ro |  |
| 39 | `projected_on_hand` | Float | `numeric(21,9)` | ro |  |
| 40 | `picked_qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 41 | `packed_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |

## Packed Item

- **Table**: `tabPacked Item`  (proposed: `packed_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `POS Invoice`.`packed_items`, `Sales Invoice`.`packed_items`, `Quotation`.`packed_items`, `Sales Order`.`packed_items`, `Delivery Note`.`packed_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `parent_item` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `item_code` | Link | `varchar(140)` | ro | → `Item` |
| 3 | `product_bundle` | Link | `varchar(140)` | ro | → `Product Bundle` |
| 4 | `item_name` | Data | `varchar(140)` | ro |  |
| 5 | `description` | Text Editor | `text` |  |  |
| 6 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 7 | `target_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 8 | `qty` | Float | `numeric(21,9)` | ro |  |
| 9 | `serial_no` | Text | `text` |  |  |
| 10 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 11 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 12 | `projected_qty` | Float | `numeric(21,9)` | ro |  |
| 13 | `uom` | Link | `varchar(140)` | ro | → `UOM` |
| 14 | `page_break` | Check | `smallint` | ro, default=0 |  |
| 15 | `prevdoc_doctype` | Data | `varchar(140)` | ro, hidden |  |
| 16 | `parent_detail_docname` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 17 | `actual_batch_qty` | Float | `numeric(21,9)` | ro |  |
| 18 | `incoming_rate` | Currency | `numeric(21,9)` | ro |  |
| 19 | `conversion_factor` | Float | `numeric(21,9)` |  |  |
| 20 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 21 | `ordered_qty` | Float | `numeric(21,9)` | ro |  |
| 22 | `picked_qty` | Float | `numeric(21,9)` | ro |  |
| 23 | `packed_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 24 | `serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |
| 25 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 26 | `delivered_by_supplier` | Check | `smallint` | ro, default=0 |  |
| 27 | `requested_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 28 | `reserve_stock` | Check | `smallint` | default=0 |  |

## Packing Slip Item

- **Table**: `tabPacking Slip Item`  (proposed: `packing_slip_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Packing Slip`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 3 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 4 | `description` | Text Editor | `text` |  |  |
| 5 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 6 | `net_weight` | Float | `numeric(21,9)` |  |  |
| 7 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 8 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 9 | `page_break` | Check | `smallint` | default=0 |  |
| 10 | `dn_detail` | Data | `varchar(140)` | ro, hidden |  |
| 11 | `pi_detail` | Data | `varchar(140)` | ro, hidden |  |

## Pick List Item

- **Table**: `tabPick List Item`  (proposed: `pick_list_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Pick List`.`locations`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 2 | `picked_qty` | Float | `numeric(21,9)` |  |  |
| 3 | `warehouse` | Link | `varchar(140)` | ro | → `Warehouse` |
| 4 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 5 | `description` | Text | `text` | ro, denorm←item_code.description |  |
| 6 | `serial_no` | Small Text | `text` |  |  |
| 7 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 8 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 9 | `uom` | Link | `varchar(140)` |  | → `UOM` |
| 10 | `conversion_factor` | Float | `numeric(21,9)` | ro |  |
| 11 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 12 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 13 | `sales_order` | Link | `varchar(140)` | ro | → `Sales Order` |
| 14 | `sales_order_item` | Data | `varchar(140)` | ro, hidden |  |
| 15 | `material_request` | Link | `varchar(140)` | INDEX, ro | → `Material Request` |
| 16 | `material_request_item` | Data | `varchar(140)` | ro |  |
| 17 | `item_group` | Data | `varchar(140)` | ro, denorm←item_code.item_group |  |
| 18 | `product_bundle_item` | Data | `varchar(140)` | ro, hidden |  |
| 19 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 20 | `stock_reserved_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 21 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 22 | `delivered_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 23 | `transferred_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 24 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 25 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |

## Price List Country

- **Table**: `tabPrice List Country`  (proposed: `price_list_country`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Price List`.`countries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `country` | Link | `varchar(140)` | NOT NULL | → `Country` *(frappe/Geo)* |

## Purchase Receipt Item

- **Table**: `tabPurchase Receipt Item`  (proposed: `purchase_receipt_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Purchase Receipt`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 3 | `supplier_part_no` | Data | `varchar(140)` | ro, hidden |  |
| 4 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 5 | `description` | Text Editor | `text` |  |  |
| 6 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 7 | `received_qty` | Float | `numeric(21,9)` | NOT NULL, ro, default=0 |  |
| 8 | `qty` | Float | `numeric(21,9)` |  |  |
| 9 | `rejected_qty` | Float | `numeric(21,9)` |  |  |
| 10 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 11 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 12 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 13 | `retain_sample` | Check | `smallint` | ro, denorm←item_code.retain_sample, default=0 |  |
| 14 | `sample_quantity` | Int | `integer` | denorm←item_code.sample_quantity |  |
| 15 | `price_list_rate` | Currency | `numeric(21,9)` |  |  |
| 16 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 17 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 18 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 19 | `rate` | Currency | `numeric(21,9)` |  |  |
| 20 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 21 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 22 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 23 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 24 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 25 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 26 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 27 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 28 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 29 | `weight_per_unit` | Float | `numeric(21,9)` |  |  |
| 30 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 31 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 32 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 33 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 34 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 35 | `is_fixed_asset` | Check | `smallint` | ro, hidden, default=0 |  |
| 36 | `purchase_order` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 37 | `schedule_date` | Date | `date` | ro |  |
| 38 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 39 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 40 | `project` | Link | `varchar(140)` |  | → `Project` |
| 41 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 42 | `purchase_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 43 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 44 | `billed_amt` | Currency | `numeric(21,9)` | ro |  |
| 45 | `landed_cost_voucher_amount` | Currency | `numeric(21,9)` | ro |  |
| 46 | `brand` | Link | `varchar(140)` | ro, hidden, denorm←item_code.brand | → `Brand` |
| 47 | `item_group` | Link | `varchar(140)` | ro, denorm←item_code.item_group | → `Item Group` |
| 48 | `rm_supp_cost` | Currency | `numeric(21,9)` | ro, hidden |  |
| 49 | `item_tax_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 50 | `valuation_rate` | Currency | `numeric(21,9)` | ro, hidden |  |
| 51 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 52 | `page_break` | Check | `smallint` | default=0 |  |
| 53 | `material_request` | Link | `varchar(140)` | ro | → `Material Request` |
| 54 | `material_request_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 55 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 56 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 57 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 58 | `asset_location` | Link | `varchar(140)` |  | → `Location` |
| 59 | `asset_category` | Link | `varchar(140)` | ro, denorm←item_code.asset_category | → `Asset Category` |
| 60 | `from_warehouse` | Link | `varchar(140)` | hidden | → `Warehouse` |
| 61 | `purchase_receipt_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 62 | `putaway_rule` | Link | `varchar(140)` | ro | → `Putaway Rule` |
| 63 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 64 | `received_stock_qty` | Float | `numeric(21,9)` | ro |  |
| 65 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 66 | `delivery_note_item` | Data | `varchar(140)` | INDEX, ro |  |
| 67 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 68 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 69 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 70 | `base_rate_with_margin` | Currency | `numeric(21,9)` |  |  |
| 71 | `purchase_invoice` | Link | `varchar(140)` | ro | → `Purchase Invoice` |
| 72 | `purchase_invoice_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 73 | `product_bundle` | Link | `varchar(140)` | ro, hidden | → `Product Bundle` |
| 74 | `provisional_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 75 | `has_item_scanned` | Check | `smallint` | ro, default=0 |  |
| 76 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 77 | `serial_no` | Text | `text` |  |  |
| 78 | `rejected_serial_no` | Text | `text` |  |  |
| 79 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 80 | `rejected_serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 81 | `wip_composite_asset` | Link | `varchar(140)` |  | → `Asset` |
| 82 | `sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 83 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 84 | `subcontracting_receipt_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 85 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 86 | `return_qty_from_rejected_warehouse` | Check | `smallint` | ro, default=0 |  |
| 87 | `sales_incoming_rate` | Currency | `numeric(21,9)` | hidden |  |
| 88 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 89 | `amount_difference_with_purchase_invoice` | Currency | `numeric(21,9)` | ro |  |

## Quality Inspection Reading

- **Table**: `tabQuality Inspection Reading`  (proposed: `quality_inspection_reading`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`
- **Embedded in**: `Quality Inspection`.`readings`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `specification` | Link | `varchar(140)` | NOT NULL | → `Quality Inspection Parameter` |
| 2 | `value` | Data | `varchar(140)` |  |  |
| 3 | `reading_1` | Data | `varchar(140)` |  |  |
| 4 | `reading_2` | Data | `varchar(140)` |  |  |
| 5 | `reading_3` | Data | `varchar(140)` |  |  |
| 6 | `reading_4` | Data | `varchar(140)` |  |  |
| 7 | `reading_5` | Data | `varchar(140)` |  |  |
| 8 | `reading_6` | Data | `varchar(140)` |  |  |
| 9 | `reading_7` | Data | `varchar(140)` |  |  |
| 10 | `reading_8` | Data | `varchar(140)` |  |  |
| 11 | `reading_9` | Data | `varchar(140)` |  |  |
| 12 | `reading_10` | Data | `varchar(140)` |  |  |
| 13 | `status` | Select | `varchar(140)` | default=Accepted | enum: Accepted, Rejected |
| 14 | `acceptance_formula` | Code | `text` |  |  |
| 15 | `formula_based_criteria` | Check | `smallint` | default=0 |  |
| 16 | `min_value` | Float | `numeric(21,9)` |  |  |
| 17 | `max_value` | Float | `numeric(21,9)` |  |  |
| 18 | `reading_value` | Data | `varchar(140)` |  |  |
| 19 | `manual_inspection` | Check | `smallint` | default=0 |  |
| 20 | `numeric` | Check | `smallint` | default=1 |  |
| 21 | `parameter_group` | Link | `varchar(140)` | ro, denorm←specification.parameter_group | → `Quality Inspection Parameter Group` |

## Serial and Batch Entry

- **Table**: `tabSerial and Batch Entry`  (proposed: `serial_and_batch_entry`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Serial and Batch Bundle`.`entries`, `Stock Reservation Entry`.`sb_entries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `serial_no` | Link | `varchar(140)` |  | → `Serial No` |
| 2 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 3 | `qty` | Float | `numeric(21,9)` | default=1 |  |
| 4 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 5 | `incoming_rate` | Float | `numeric(21,9)` | ro |  |
| 6 | `outgoing_rate` | Float | `numeric(21,9)` | ro, hidden |  |
| 7 | `stock_value_difference` | Float | `numeric(21,9)` | ro |  |
| 8 | `is_outward` | Check | `smallint` | ro, hidden, default=0 |  |
| 9 | `stock_queue` | Small Text | `text` | ro |  |
| 10 | `delivered_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 11 | `reference_for_reservation` | Data | `varchar(140)` | ro, hidden |  |
| 12 | `posting_datetime` | Datetime | `timestamp` | ro |  |
| 13 | `voucher_type` | Data | `varchar(140)` | ro |  |
| 14 | `voucher_no` | Data | `varchar(140)` | ro |  |
| 15 | `voucher_detail_no` | Data | `varchar(140)` | INDEX, ro |  |
| 16 | `type_of_transaction` | Data | `varchar(140)` | ro |  |
| 17 | `is_cancelled` | Check | `smallint` | ro, default=0 |  |
| 18 | `item_code` | Link | `varchar(140)` | ro | → `Item` |

## Shipment Delivery Note

- **Table**: `tabShipment Delivery Note`  (proposed: `shipment_delivery_note`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Shipment`.`shipment_delivery_note`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `delivery_note` | Link | `varchar(140)` | NOT NULL | → `Delivery Note` |
| 2 | `grand_total` | Currency | `numeric(21,9)` | ro |  |

## Shipment Parcel

- **Table**: `tabShipment Parcel`  (proposed: `shipment_parcel`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Shipment`.`shipment_parcel`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `length` | Float | `numeric(21,9)` |  |  |
| 2 | `width` | Float | `numeric(21,9)` |  |  |
| 3 | `height` | Float | `numeric(21,9)` |  |  |
| 4 | `weight` | Float | `numeric(21,1)` | NOT NULL |  |
| 5 | `count` | Int | `integer` | NOT NULL, default=1 |  |

## Stock Entry Detail

- **Table**: `tabStock Entry Detail`  (proposed: `stock_entry_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`  (Random)
- **Embedded in**: `Stock Entry`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `s_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 3 | `t_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 4 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 5 | `item_name` | Data | `varchar(140)` | ro |  |
| 6 | `description` | Text Editor | `text` |  |  |
| 7 | `image` | Attach | `text` | hidden |  |
| 8 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 9 | `basic_rate` | Currency | `numeric(21,9)` |  |  |
| 10 | `basic_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `additional_cost` | Currency | `numeric(21,9)` | ro |  |
| 12 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 13 | `valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 14 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 15 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 16 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro, denorm←item_code.stock_uom | → `UOM` |
| 17 | `transfer_qty` | Float | `numeric(21,9)` | ro |  |
| 18 | `retain_sample` | Check | `smallint` | ro, denorm←item_code.retain_sample, default=0 |  |
| 19 | `sample_quantity` | Int | `integer` |  |  |
| 20 | `serial_no` | Text | `text` |  |  |
| 21 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 22 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 23 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 24 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 25 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 26 | `actual_qty` | Float | `numeric(21,9)` | INDEX, ro |  |
| 27 | `bom_no` | Link | `varchar(140)` | hidden | → `BOM` |
| 28 | `allow_alternative_item` | Check | `smallint` | ro, default=0 |  |
| 29 | `material_request` | Link | `varchar(140)` | INDEX, ro, hidden | → `Material Request` |
| 30 | `material_request_item` | Link | `varchar(140)` | ro, hidden | → `Material Request Item` |
| 31 | `pick_list_item` | Link | `varchar(140)` | ro, hidden | → `Pick List Item` |
| 32 | `original_item` | Link | `varchar(140)` | ro, hidden | → `Item` |
| 33 | `subcontracted_item` | Link | `varchar(140)` |  | → `Item` |
| 34 | `against_stock_entry` | Link | `varchar(140)` | INDEX, ro | → `Stock Entry` |
| 35 | `ste_detail` | Data | `varchar(140)` | INDEX, ro |  |
| 36 | `transferred_qty` | Float | `numeric(21,9)` | ro |  |
| 37 | `item_group` | Data | `varchar(140)` | denorm←item_code.item_group |  |
| 38 | `reference_purchase_receipt` | Link | `varchar(140)` | INDEX, ro | → `Purchase Receipt` |
| 39 | `project` | Link | `varchar(140)` |  | → `Project` |
| 40 | `po_detail` | Data | `varchar(140)` | ro, hidden |  |
| 41 | `sco_rm_detail` | Data | `varchar(140)` | ro, hidden |  |
| 42 | `set_basic_rate_manually` | Check | `smallint` | default=0 |  |
| 43 | `putaway_rule` | Link | `varchar(140)` | ro | → `Putaway Rule` |
| 44 | `is_finished_item` | Check | `smallint` | default=0 |  |
| 45 | `job_card_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 46 | `has_item_scanned` | Check | `smallint` | ro, default=0 |  |
| 47 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 48 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 49 | `landed_cost_voucher_amount` | Currency | `numeric(21,9)` | ro |  |
| 50 | `customer_provided_item_cost` | Currency | `numeric(21,9)` | ro |  |
| 51 | `scio_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 52 | `against_fg` | Link | `varchar(140)` |  | → `Subcontracting Inward Order Item` |
| 53 | `secondary_item_type` | Select | `varchar(140)` |  | enum: Co-Product, By-Product, Scrap, Additional Finished Good |
| 54 | `bom_secondary_item` | Data | `varchar(140)` | ro, hidden |  |
| 55 | `is_legacy_scrap_item` | Check | `smallint` | ro, default=0 |  |

## Stock Reconciliation Item

- **Table**: `tabStock Reconciliation Item`  (proposed: `stock_reconciliation_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Stock Reconciliation`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 3 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 4 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 5 | `qty` | Float | `numeric(21,9)` |  |  |
| 6 | `stock_uom` | Link | `varchar(140)` | ro, denorm←item_code.stock_uom | → `UOM` |
| 7 | `valuation_rate` | Currency | `numeric(21,9)` |  |  |
| 8 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 9 | `serial_no` | Long Text | `text` |  |  |
| 10 | `current_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 11 | `current_serial_no` | Long Text | `text` | ro |  |
| 12 | `current_valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 13 | `current_amount` | Currency | `numeric(21,9)` | ro |  |
| 14 | `quantity_difference` | Read Only | `varchar(140)` |  |  |
| 15 | `amount_difference` | Currency | `numeric(21,9)` | ro |  |
| 16 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 17 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 18 | `has_item_scanned` | Data | `varchar(140)` | ro |  |
| 19 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 20 | `current_serial_and_batch_bundle` | Link | `varchar(140)` | ro | → `Serial and Batch Bundle` |
| 21 | `item_group` | Link | `varchar(140)` | denorm←item_code.item_group | → `Item Group` |
| 22 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 23 | `reconcile_all_serial_batch` | Check | `smallint` | default=0 |  |

## UOM Conversion Detail

- **Table**: `tabUOM Conversion Detail`  (proposed: `uom_conversion_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Naming**: `hash`
- **Embedded in**: `Item`.`uoms`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 2 | `conversion_factor` | Float | `numeric(21,9)` |  |  |

## Variant Field

- **Table**: `tabVariant Field`  (proposed: `variant_field`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Stock
- **Embedded in**: `Item Variant Settings`.`fields`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `field_name` | Autocomplete | `varchar(140)` | NOT NULL |  |
