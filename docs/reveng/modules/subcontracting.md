# Module deep dive: Subcontracting

Toll/contract manufacturing: `Subcontracting Order` and `Subcontracting Receipt` move raw
material to a supplier warehouse and receive finished goods, consuming the supplied items
and rolling their value into the finished item cost.

13 DocTypes / 280 columns.

## Contents

**Master** (1): [Subcontracting BOM](#subcontracting-bom)

**Transaction (submittable)** (3): [Subcontracting Inward Order](#subcontracting-inward-order), [Subcontracting Order](#subcontracting-order), [Subcontracting Receipt](#subcontracting-receipt)

**Child / line-item table** (9): [Subcontracting Inward Order Item](#subcontracting-inward-order-item), [Subcontracting Inward Order Received Item](#subcontracting-inward-order-received-item), [Subcontracting Inward Order Secondary Item](#subcontracting-inward-order-secondary-item), [Subcontracting Inward Order Service Item](#subcontracting-inward-order-service-item), [Subcontracting Order Item](#subcontracting-order-item), [Subcontracting Order Service Item](#subcontracting-order-service-item), [Subcontracting Order Supplied Item](#subcontracting-order-supplied-item), [Subcontracting Receipt Item](#subcontracting-receipt-item), [Subcontracting Receipt Supplied Item](#subcontracting-receipt-supplied-item)

---

# Masters

## Subcontracting BOM

- **Table**: `tabSubcontracting BOM`  (proposed: `subcontracting_bom`)
- **Kind**: Master
- **Naming**: `format:SB-{####}`  (Expression)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `is_active` | Check | `smallint` | default=1 |  |
| 2 | `finished_good` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 3 | `finished_good_qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 4 | `finished_good_bom` | Link | `varchar(140)` | NOT NULL, INDEX, denorm←finished_good.default_bom | → `BOM` |
| 5 | `service_item` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 6 | `service_item_qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 7 | `service_item_uom` | Link | `varchar(140)` | NOT NULL, denorm←service_item.stock_uom | → `UOM` |
| 8 | `conversion_factor` | Float | `numeric(21,9)` | ro |  |
| 9 | `finished_good_uom` | Link | `varchar(140)` | ro, denorm←finished_good.stock_uom | → `UOM` |

---

# Transaction (submittable)s

## Subcontracting Inward Order

- **Table**: `tabSubcontracting Inward Order`  (proposed: `subcontracting_inward_order`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, transaction_date, customer`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: SCI-ORD-.YYYY.- |
| 3 | `sales_order` | Link | `varchar(140)` | NOT NULL | → `Sales Order` |
| 4 | `customer` | Link | `varchar(140)` | NOT NULL, INDEX, ro | → `Customer` |
| 5 | `customer_name` | Data | `varchar(140)` | NOT NULL, ro, denorm←customer.customer_name |  |
| 6 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 7 | `transaction_date` | Date | `date` | NOT NULL, INDEX, denorm←sales_order.transaction_date, default=Today |  |
| 8 | `amended_from` | Link | `varchar(140)` | ro | → `Subcontracting Inward Order` |
| 9 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, Open, Ongoing, Produced, Delivered, Returned, Cancelled, Closed |
| 10 | `per_delivered` | Percent | `numeric(21,9)` | ro |  |
| 11 | `per_produced` | Percent | `numeric(21,9)` | ro |  |
| 12 | `per_process_loss` | Percent | `numeric(21,9)` | ro |  |
| 13 | `set_delivery_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 14 | `customer_warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 15 | `per_returned` | Percent | `numeric(21,9)` | ro |  |
| 16 | `per_raw_material_returned` | Percent | `numeric(21,9)` | ro |  |
| 17 | `per_raw_material_received` | Percent | `numeric(21,9)` | ro |  |
| 18 | `currency` | Link | `varchar(140)` | ro, hidden, denorm←customer.default_currency | → `Currency` *(frappe core)* |

**Child tables (1-N):**

- `items` → `Subcontracting Inward Order Item` (line items)
- `service_items` → `Subcontracting Inward Order Service Item` (line items)
- `received_items` → `Subcontracting Inward Order Received Item` (line items)
- `secondary_items` → `Subcontracting Inward Order Secondary Item` (line items)

**Referenced by (3):** `Work Order`.`subcontracting_inward_order`, `Stock Entry`.`subcontracting_inward_order`, `Subcontracting Inward Order`.`amended_from`

## Subcontracting Order

- **Table**: `tabSubcontracting Order`  (proposed: `subcontracting_order`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, transaction_date, supplier`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: SC-ORD-.YYYY.- |
| 3 | `purchase_order` | Link | `varchar(140)` | NOT NULL | → `Purchase Order` |
| 4 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 5 | `supplier_name` | Data | `varchar(140)` | NOT NULL, ro, denorm←supplier.supplier_name |  |
| 6 | `supplier_warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 8 | `transaction_date` | Date | `date` | NOT NULL, INDEX, denorm←purchase_order.transaction_date, default=Today |  |
| 9 | `schedule_date` | Date | `date` | ro, denorm←purchase_order.schedule_date |  |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `Subcontracting Order` |
| 11 | `supplier_address` | Link | `varchar(140)` | denorm←supplier.supplier_primary_address | → `Address` *(frappe core)* |
| 12 | `address_display` | Text Editor | `text` | ro |  |
| 13 | `contact_person` | Link | `varchar(140)` | denorm←supplier.supplier_primary_contact | → `Contact` *(frappe core)* |
| 14 | `contact_display` | Small Text | `text` | ro |  |
| 15 | `contact_mobile` | Small Text | `text` | ro |  |
| 16 | `contact_email` | Small Text | `text` | ro |  |
| 17 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 18 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 19 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 20 | `billing_address_display` | Text Editor | `text` | ro |  |
| 21 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 22 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 23 | `total` | Currency | `numeric(21,9)` | ro |  |
| 24 | `set_reserve_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 25 | `total_additional_costs` | Currency | `numeric(21,9)` | ro |  |
| 26 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, Open, Partially Received, Completed, Material Transferred, Partial Material Transferred, Cancelled, Closed |
| 27 | `per_received` | Percent | `numeric(21,9)` | ro |  |
| 28 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe core)* |
| 29 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 30 | `distribute_additional_costs_based_on` | Select | `varchar(140)` | default=Qty | enum: Qty, Amount |
| 31 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 32 | `project` | Link | `varchar(140)` |  | → `Project` |
| 33 | `supplier_currency` | Link | `varchar(140)` | ro, hidden, denorm←purchase_order.currency | → `Currency` *(frappe core)* |
| 34 | `reserve_stock` | Check | `smallint` | default=0 |  |
| 35 | `production_plan` | Data | `varchar(140)` | ro, hidden |  |

**Child tables (1-N):**

- `items` → `Subcontracting Order Item` (line items)
- `service_items` → `Subcontracting Order Service Item` (line items)
- `supplied_items` → `Subcontracting Order Supplied Item` (line items)
- `additional_costs` → `Landed Cost Taxes and Charges` (line items)

**Referenced by (4):** `Stock Entry`.`subcontracting_order`, `Subcontracting Order`.`amended_from`, `Subcontracting Receipt Item`.`subcontracting_order`, `Subcontracting Receipt Supplied Item`.`subcontracting_order`

## Subcontracting Receipt

- **Table**: `tabSubcontracting Receipt`  (proposed: `subcontracting_receipt`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, posting_date, supplier`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-SCR-.YYYY.-, MAT-SCR-RET-.YYYY.- |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 4 | `supplier_name` | Data | `varchar(140)` | ro, denorm←supplier.supplier_name |  |
| 5 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 6 | `posting_time` | Time | `time(6)` | NOT NULL, default=Now |  |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 8 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 9 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 10 | `address_display` | Text Editor | `text` | ro |  |
| 11 | `contact_display` | Small Text | `text` | ro |  |
| 12 | `contact_mobile` | Small Text | `text` | ro |  |
| 13 | `contact_email` | Small Text | `text` | ro |  |
| 14 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 15 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 16 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 17 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 18 | `supplier_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 19 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 20 | `total` | Currency | `numeric(21,9)` | ro |  |
| 21 | `in_words` | Data | `varchar(140)` | ro |  |
| 22 | `bill_no` | Data | `varchar(140)` | hidden |  |
| 23 | `bill_date` | Date | `date` | hidden |  |
| 24 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, Completed, Return, Return Issued, Cancelled, Closed |
| 25 | `amended_from` | Link | `varchar(140)` | ro, hidden | → `Subcontracting Receipt` |
| 26 | `range` | Data | `varchar(140)` | hidden |  |
| 27 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe core)* |
| 28 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 29 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe core)* |
| 30 | `language` | Data | `varchar(140)` | ro |  |
| 31 | `instructions` | Small Text | `text` |  |  |
| 32 | `remarks` | Small Text | `text` |  |  |
| 33 | `transporter_name` | Data | `varchar(140)` |  |  |
| 34 | `lr_no` | Data | `varchar(140)` |  |  |
| 35 | `lr_date` | Date | `date` |  |  |
| 36 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 37 | `billing_address_display` | Text Editor | `text` | ro |  |
| 38 | `represents_company` | Link | `varchar(140)` | ro, denorm←supplier.represents_company | → `Company` |
| 39 | `is_return` | Check | `smallint` | ro, default=0 |  |
| 40 | `return_against` | Link | `varchar(140)` | ro | → `Subcontracting Receipt` |
| 41 | `per_returned` | Percent | `numeric(21,9)` | ro |  |
| 42 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 43 | `project` | Link | `varchar(140)` |  | → `Project` |
| 44 | `distribute_additional_costs_based_on` | Select | `varchar(140)` | default=Qty | enum: Qty, Amount |
| 45 | `total_additional_costs` | Currency | `numeric(21,9)` | ro |  |
| 46 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 47 | `supplier_delivery_note` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `Subcontracting Receipt Item` (line items)
- `supplied_items` → `Subcontracting Receipt Supplied Item` (line items)
- `additional_costs` → `Landed Cost Taxes and Charges` (line items)

**Referenced by (3):** `Purchase Receipt`.`subcontracting_receipt`, `Subcontracting Receipt`.`amended_from`, `Subcontracting Receipt`.`return_against`

---

# Child / line-item tables

## Subcontracting Inward Order Item

- **Table**: `tabSubcontracting Inward Order Item`  (proposed: `subcontracting_inward_order_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Search fields**: `item_name`
- **Embedded in**: `Subcontracting Inward Order`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX, ro | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | NOT NULL, ro, denorm←item_code.item_name |  |
| 3 | `qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 4 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 5 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden, default=1 |  |
| 6 | `bom` | Link | `varchar(140)` | NOT NULL, denorm←item_code.default_bom | → `BOM` |
| 7 | `include_exploded_items` | Check | `smallint` | default=0 |  |
| 8 | `delivered_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 9 | `returned_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 10 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 11 | `subcontracting_conversion_factor` | Float | `numeric(21,9)` | ro, hidden |  |
| 12 | `produced_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 13 | `process_loss_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 14 | `delivery_warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |

## Subcontracting Inward Order Received Item

- **Table**: `tabSubcontracting Inward Order Received Item`  (proposed: `subcontracting_inward_order_received_item`)
- **Kind**: Child / line-item table
- **Embedded in**: `Subcontracting Inward Order`.`received_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `main_item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 2 | `rm_item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 3 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 4 | `bom_detail_no` | Data | `varchar(140)` | ro |  |
| 5 | `reference_name` | Data | `varchar(140)` | NOT NULL, ro |  |
| 6 | `required_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 7 | `received_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 8 | `consumed_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 9 | `returned_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 10 | `work_order_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 11 | `is_customer_provided_item` | Check | `smallint` | NOT NULL, ro, default=0 |  |
| 12 | `warehouse` | Link | `varchar(140)` | ro | → `Warehouse` |
| 13 | `billed_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 14 | `is_additional_item` | Check | `smallint` | ro, default=0 |  |
| 15 | `rate` | Currency | `numeric(21,9)` | ro, default=0 |  |

## Subcontracting Inward Order Secondary Item

- **Table**: `tabSubcontracting Inward Order Secondary Item`  (proposed: `subcontracting_inward_order_secondary_item`)
- **Kind**: Child / line-item table
- **Embedded in**: `Subcontracting Inward Order`.`secondary_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 2 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 3 | `reference_name` | Data | `varchar(140)` | NOT NULL, ro |  |
| 4 | `produced_qty` | Float | `numeric(21,9)` | NOT NULL, default=0 |  |
| 5 | `delivered_qty` | Float | `numeric(21,9)` | NOT NULL, default=0 |  |
| 6 | `fg_item_code` | Link | `varchar(140)` | NOT NULL, ro | → `Item` |
| 7 | `warehouse` | Link | `varchar(140)` | NOT NULL, ro | → `Warehouse` |
| 8 | `secondary_item_type` | Select | `varchar(140)` | NOT NULL, ro | enum: Co-Product, By-Product, Scrap, Additional Finished Good |

## Subcontracting Inward Order Service Item

- **Table**: `tabSubcontracting Inward Order Service Item`  (proposed: `subcontracting_inward_order_service_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Search fields**: `item_name`
- **Embedded in**: `Subcontracting Inward Order`.`service_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | NOT NULL, denorm←item_code.item_name |  |
| 3 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 4 | `rate` | Currency | `numeric(21,9)` | NOT NULL, denorm←item_code.standard_rate |  |
| 5 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 6 | `fg_item` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 7 | `fg_item_qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 8 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 9 | `uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |

## Subcontracting Order Item

- **Table**: `tabSubcontracting Order Item`  (proposed: `subcontracting_order_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Search fields**: `item_name`
- **Embedded in**: `Subcontracting Order`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX, ro | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | NOT NULL, denorm←item_code.item_name |  |
| 3 | `schedule_date` | Date | `date` | ro |  |
| 4 | `expected_delivery_date` | Date | `date` | INDEX |  |
| 5 | `description` | Text Editor | `text` | denorm←item_code.description |  |
| 6 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 7 | `qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 8 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 9 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden, default=1 |  |
| 10 | `rate` | Currency | `numeric(21,9)` | NOT NULL, ro, denorm←item_code.standard_rate |  |
| 11 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 12 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 13 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 14 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 15 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 16 | `bom` | Link | `varchar(140)` | NOT NULL, denorm←item_code.default_bom | → `BOM` |
| 17 | `include_exploded_items` | Check | `smallint` | default=0 |  |
| 18 | `service_cost_per_qty` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 19 | `additional_cost_per_qty` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 20 | `rm_cost_per_qty` | Currency | `numeric(21,9)` | ro |  |
| 21 | `page_break` | Check | `smallint` | default=0 |  |
| 22 | `received_qty` | Float | `numeric(21,9)` | ro |  |
| 23 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 24 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 25 | `project` | Link | `varchar(140)` |  | → `Project` |
| 26 | `material_request` | Link | `varchar(140)` | INDEX, ro | → `Material Request` |
| 27 | `material_request_item` | Data | `varchar(140)` | INDEX, ro |  |
| 28 | `purchase_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 29 | `job_card` | Link | `varchar(140)` | ro | → `Job Card` |
| 30 | `subcontracting_conversion_factor` | Float | `numeric(21,9)` | ro, hidden |  |
| 31 | `production_plan_sub_assembly_item` | Data | `varchar(140)` | ro, hidden |  |

## Subcontracting Order Service Item

- **Table**: `tabSubcontracting Order Service Item`  (proposed: `subcontracting_order_service_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Search fields**: `item_name`
- **Embedded in**: `Subcontracting Order`.`service_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | NOT NULL, denorm←item_code.item_name |  |
| 3 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 4 | `rate` | Currency | `numeric(21,9)` | NOT NULL, denorm←item_code.standard_rate |  |
| 5 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 6 | `fg_item` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 7 | `fg_item_qty` | Float | `numeric(21,9)` | NOT NULL, default=1 |  |
| 8 | `purchase_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 9 | `material_request` | Link | `varchar(140)` | ro | → `Material Request` |
| 10 | `material_request_item` | Data | `varchar(140)` | ro |  |

## Subcontracting Order Supplied Item

- **Table**: `tabSubcontracting Order Supplied Item`  (proposed: `subcontracting_order_supplied_item`)
- **Kind**: Child / line-item table
- **Embedded in**: `Subcontracting Order`.`supplied_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `main_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `rm_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 3 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 4 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden, default=1 |  |
| 5 | `reserve_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 6 | `bom_detail_no` | Data | `varchar(140)` | ro |  |
| 7 | `reference_name` | Data | `varchar(140)` | ro |  |
| 8 | `rate` | Currency | `numeric(21,9)` |  |  |
| 9 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 10 | `required_qty` | Float | `numeric(21,9)` | ro |  |
| 11 | `supplied_qty` | Float | `numeric(21,9)` | ro |  |
| 12 | `consumed_qty` | Float | `numeric(21,9)` | ro |  |
| 13 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `total_supplied_qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 15 | `stock_reserved_qty` | Float | `numeric(21,9)` | ro, default=0 |  |

## Subcontracting Receipt Item

- **Table**: `tabSubcontracting Receipt Item`  (proposed: `subcontracting_receipt_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Embedded in**: `Subcontracting Receipt`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | denorm←item_code.item_name |  |
| 3 | `description` | Text Editor | `text` | denorm←item_code.description |  |
| 4 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 5 | `received_qty` | Float | `numeric(21,9)` | NOT NULL, ro, default=0 |  |
| 6 | `qty` | Float | `numeric(21,9)` |  |  |
| 7 | `rejected_qty` | Float | `numeric(21,9)` |  |  |
| 8 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro, denorm←item_code.stock_uom | → `UOM` |
| 9 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden, default=1 |  |
| 10 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 11 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 12 | `rm_cost_per_qty` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 13 | `service_cost_per_qty` | Currency | `numeric(21,9)` | NOT NULL, ro, default=0 |  |
| 14 | `additional_cost_per_qty` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 15 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 16 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 17 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 18 | `subcontracting_order` | Link | `varchar(140)` | INDEX, ro | → `Subcontracting Order` |
| 19 | `schedule_date` | Date | `date` | ro |  |
| 20 | `serial_no` | Small Text | `text` |  |  |
| 21 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 22 | `rejected_serial_no` | Small Text | `text` |  |  |
| 23 | `subcontracting_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 24 | `bom` | Link | `varchar(140)` |  | → `BOM` |
| 25 | `brand` | Link | `varchar(140)` | ro, hidden, denorm←item_code.brand | → `Brand` |
| 26 | `rm_supp_cost` | Currency | `numeric(21,9)` | ro, hidden |  |
| 27 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 28 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 29 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 30 | `subcontracting_receipt_item` | Data | `varchar(140)` | ro, hidden |  |
| 31 | `project` | Link | `varchar(140)` |  | → `Project` |
| 32 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 33 | `page_break` | Check | `smallint` | default=0 |  |
| 34 | `returned_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 35 | `serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |
| 36 | `rejected_serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |
| 37 | `reference_name` | Data | `varchar(140)` | ro, hidden |  |
| 38 | `purchase_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 39 | `purchase_order` | Link | `varchar(140)` | INDEX, ro, hidden | → `Purchase Order` |
| 40 | `include_exploded_items` | Check | `smallint` | default=0 |  |
| 41 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 42 | `job_card` | Link | `varchar(140)` | INDEX, ro | → `Job Card` |
| 43 | `landed_cost_voucher_amount` | Currency | `numeric(21,9)` | ro |  |
| 44 | `service_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 45 | `secondary_item_type` | Select | `varchar(140)` | ro | enum: Co-Product, By-Product, Scrap, Additional Finished Good |
| 46 | `secondary_items_cost_per_qty` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 47 | `is_legacy_scrap_item` | Check | `smallint` | ro, default=0 |  |
| 48 | `process_loss_qty` | Float | `numeric(21,9)` | default=0 |  |

## Subcontracting Receipt Supplied Item

- **Table**: `tabSubcontracting Receipt Supplied Item`  (proposed: `subcontracting_receipt_supplied_item`)
- **Kind**: Child / line-item table
- **Naming**: Autoincrement
- **Embedded in**: `Subcontracting Receipt`.`supplied_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `main_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `rm_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 3 | `description` | Text Editor | `text` | ro |  |
| 4 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 5 | `serial_no` | Text | `text` |  |  |
| 6 | `required_qty` | Float | `numeric(21,9)` | ro |  |
| 7 | `consumed_qty` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 8 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 9 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 10 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden, default=1 |  |
| 12 | `current_stock` | Float | `numeric(21,9)` | ro |  |
| 13 | `reference_name` | Data | `varchar(140)` | ro, hidden |  |
| 14 | `bom_detail_no` | Data | `varchar(140)` | ro, hidden |  |
| 15 | `item_name` | Data | `varchar(140)` | ro |  |
| 16 | `subcontracting_order` | Link | `varchar(140)` | ro, hidden | → `Subcontracting Order` |
| 17 | `available_qty_for_consumption` | Float | `numeric(21,9)` | ro, default=0 |  |
| 18 | `serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |
| 19 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 20 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 21 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
