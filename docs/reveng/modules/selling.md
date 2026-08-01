# Module deep dive: Selling

Order-to-cash masters and documents: `Customer`, `Quotation`, `Sales Order` plus pricing,
partner/territory and target structures. Line items live in child tables shared with
Stock/Accounts documents (e.g. `Sales Taxes and Charges`, `Packed Item`).

20 DocTypes / 494 columns.

## Contents

**Single (settings)** (2): [SMS Center](#sms-center), [Selling Settings](#selling-settings)

**Master** (5): [Customer](#customer), [Delivery Schedule Item](#delivery-schedule-item), [Industry Type](#industry-type), [Party Specific Item](#party-specific-item), [Sales Partner Type](#sales-partner-type)

**Transaction (submittable)** (5): [Installation Note](#installation-note), [Product Bundle](#product-bundle), [Proforma Invoice](#proforma-invoice), [Quotation](#quotation), [Sales Order](#sales-order)

**Child / line-item table** (8): [Customer Credit Limit](#customer-credit-limit), [Installation Note Item](#installation-note-item), [Product Bundle Item](#product-bundle-item), [Proforma Invoice Item](#proforma-invoice-item), [Quotation Item](#quotation-item), [Sales Order Item](#sales-order-item), [Sales Team](#sales-team), [Supplier Number At Customer](#supplier-number-at-customer)

---

# Single (settings)s

## SMS Center

- **Table**: `tabSMS Center`  (proposed: `sms_center`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Selling

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `send_to` | Select | `varchar(140)` |  | enum: All Contact, All Customer Contact, All Supplier Contact, All Sales Partner Contact, All Lead (Open), All Employee (Active), All Sales Person |
| 2 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 3 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 4 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 5 | `department` | Link | `varchar(140)` |  | → `Department` |
| 6 | `branch` | Link | `varchar(140)` |  | → `Branch` |
| 7 | `receiver_list` | Code | `text` |  |  |
| 8 | `message` | Text | `text` | NOT NULL |  |
| 9 | `total_characters` | Int | `integer` | ro |  |
| 10 | `total_messages` | Int | `integer` | ro |  |

## Selling Settings

- **Table**: `tabSelling Settings`  (proposed: `selling_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Selling
- **Description**: Settings for Selling Module

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `cust_master_name` | Select | `varchar(140)` | default=Customer Name | enum: Customer Name, Naming Series, Auto Name |
| 2 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 3 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 4 | `selling_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 5 | `so_required` | Select | `varchar(140)` |  | enum: No, Yes |
| 6 | `dn_required` | Select | `varchar(140)` |  | enum: No, Yes |
| 7 | `sales_update_frequency` | Select | `varchar(140)` | NOT NULL, default=Daily | enum: Monthly, Each Transaction, Daily |
| 8 | `maintain_same_sales_rate` | Check | `smallint` | default=0 |  |
| 9 | `editable_price_list_rate` | Check | `smallint` | default=0 |  |
| 10 | `allow_multiple_items` | Check | `smallint` | default=0 |  |
| 11 | `allow_against_multiple_purchase_orders` | Check | `smallint` | default=0 |  |
| 12 | `validate_selling_price` | Check | `smallint` | default=0 |  |
| 13 | `hide_tax_id` | Check | `smallint` | default=0 |  |
| 14 | `maintain_same_rate_action` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn |
| 15 | `role_to_override_stop_action` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 16 | `editable_bundle_item_rates` | Check | `smallint` | default=0 |  |
| 17 | `enable_discount_accounting` | Check | `smallint` | default=0 |  |
| 18 | `allow_sales_order_creation_for_expired_quotation` | Check | `smallint` | default=0 |  |
| 19 | `dont_reserve_sales_order_qty_on_sales_return` | Check | `smallint` | default=0 |  |
| 20 | `allow_negative_rates_for_items` | Check | `smallint` | default=0 |  |
| 21 | `blanket_order_allowance` | Float | `numeric(21,9)` |  |  |
| 22 | `enable_cutoff_date_on_bulk_delivery_note_creation` | Check | `smallint` | default=0 |  |
| 23 | `allow_zero_qty_in_sales_order` | Check | `smallint` | default=0 |  |
| 24 | `allow_zero_qty_in_quotation` | Check | `smallint` | default=0 |  |
| 25 | `allow_delivery_of_overproduced_qty` | Check | `smallint` | default=0 |  |
| 26 | `fallback_to_default_price_list` | Check | `smallint` | default=0 |  |
| 27 | `use_legacy_js_reactivity` | Check | `smallint` | default=0 |  |
| 28 | `set_zero_rate_for_expired_batch` | Check | `smallint` | default=0 |  |
| 29 | `enable_tracking_sales_commissions` | Check | `smallint` | default=0 |  |
| 30 | `enable_utm` | Check | `smallint` | default=0 |  |
| 31 | `deliver_secondary_items` | Check | `smallint` | default=0 |  |
| 32 | `enable_proforma_invoice` | Check | `smallint` | default=0 |  |
| 33 | `default_proforma_print_format` | Link | `varchar(140)` |  | → `Print Format` *(frappe/Printing)* |

---

# Masters

## Customer

- **Table**: `tabCustomer`  (proposed: `customer`)
- **Kind**: Master
- **Owned by**: erpnext / Selling
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Description**: Buyer of Goods and Services.
- **Search fields**: `customer_group,territory, mobile_no,primary_address, alias`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: CUST-.YYYY.- |
| 2 | `customer_name` | Data | `varchar(140)` | NOT NULL, INDEX |  |
| 3 | `gender` | Link | `varchar(140)` |  | → `Gender` *(frappe/Contacts)* |
| 4 | `customer_type` | Select | `varchar(140)` | NOT NULL, default=Company | enum: Company, Individual, Partnership |
| 5 | `default_bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 6 | `lead_name` | Link | `varchar(140)` | ro | → `Lead` |
| 7 | `image` | Attach Image | `text` | hidden |  |
| 8 | `account_manager` | Link | `varchar(140)` |  | → `User` *(frappe/Core)* |
| 9 | `customer_group` | Link | `varchar(140)` | INDEX | → `Customer Group` |
| 10 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 11 | `tax_id` | Data | `varchar(140)` |  |  |
| 12 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 13 | `disabled` | Check | `smallint` | default=0 |  |
| 14 | `is_internal_customer` | Check | `smallint` | default=0 |  |
| 15 | `represents_company` | Link | `varchar(140)` | UNIQUE | → `Company` |
| 16 | `default_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 17 | `default_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 18 | `language` | Link | `varchar(140)` |  | → `Language` *(frappe/Core)* |
| 19 | `website` | Data | `varchar(140)` |  |  |
| 20 | `customer_primary_contact` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 21 | `mobile_no` | Read Only | `varchar(140)` | denorm←customer_primary_contact.mobile_no |  |
| 22 | `email_id` | Read Only | `varchar(140)` | denorm←customer_primary_contact.email_id |  |
| 23 | `customer_primary_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 24 | `primary_address` | Text Editor | `text` | ro |  |
| 25 | `payment_terms` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 26 | `customer_details` | Text | `text` |  |  |
| 27 | `market_segment` | Link | `varchar(140)` |  | → `Market Segment` |
| 28 | `industry` | Link | `varchar(140)` |  | → `Industry Type` |
| 29 | `is_frozen` | Check | `smallint` | default=0 |  |
| 30 | `loyalty_program` | Link | `varchar(140)` |  | → `Loyalty Program` |
| 31 | `loyalty_program_tier` | Data | `varchar(140)` | ro |  |
| 32 | `default_sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 33 | `default_commission_rate` | Float | `numeric(21,9)` |  |  |
| 34 | `customer_pos_id` | Data | `varchar(140)` | ro |  |
| 35 | `so_required` | Check | `smallint` | default=0 |  |
| 36 | `dn_required` | Check | `smallint` | default=0 |  |
| 37 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 38 | `opportunity_name` | Link | `varchar(140)` | ro | → `Opportunity` |
| 39 | `restrict_to_companies` | Check | `smallint` | default=0 |  |
| 40 | `prospect_name` | Link | `varchar(140)` | ro | → `Prospect` |
| 41 | `first_name` | Read Only | `varchar(140)` | hidden, denorm←customer_primary_contact.first_name |  |
| 42 | `last_name` | Read Only | `varchar(140)` | hidden, denorm←customer_primary_contact.last_name |  |
| 43 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 44 | `alias` | Data | `varchar(140)` | UNIQUE |  |

**Child tables (1-N):**

- `companies` → `Allowed To Transact With` (line items)
- `accounts` → `Party Account` (line items)
- `sales_team` → `Sales Team` (line items)
- `credit_limits` → `Customer Credit Limit` (line items)
- `allowed_companies` → `Company Restriction` (multi-select)
- `portal_users` → `Portal User` (line items)
- `supplier_numbers` → `Supplier Number At Customer` (line items)

**Referenced by (44):** `Bank Guarantee`.`customer`, `Coupon Code`.`customer`, `Customer Item`.`customer`, `Discounted Invoice`.`customer`, `Dunning`.`customer`, `Loyalty Point Entry`.`customer`, `POS Invoice`.`customer`, `POS Invoice Merge Log`.`customer`, `POS Invoice Reference`.`customer`, `POS Profile`.`customer`, `Pricing Rule`.`customer`, `Process Statement Of Accounts Customer`.`customer`, `Sales Invoice`.`customer`, `Sales Invoice Reference`.`customer`, `Tax Rule`.`customer` … (+29 more)

## Delivery Schedule Item

- **Table**: `tabDelivery Schedule Item`  (proposed: `delivery_schedule_item`)
- **Kind**: Master
- **Owned by**: erpnext / Selling
- **Title field**: `item_code`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `qty` | Float | `numeric(21,9)` | ro |  |
| 3 | `conversion_factor` | Float | `numeric(21,9)` | ro |  |
| 4 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 5 | `delivery_date` | Date | `date` | ro |  |
| 6 | `sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 7 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro |  |
| 8 | `warehouse` | Link | `varchar(140)` | ro | → `Warehouse` |
| 9 | `uom` | Link | `varchar(140)` | ro | → `UOM` |
| 10 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |

## Industry Type

- **Table**: `tabIndustry Type`  (proposed: `industry_type`)
- **Kind**: Master
- **Owned by**: erpnext / Selling
- **Naming**: `field:industry`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `industry` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (4):** `Lead`.`industry`, `Opportunity`.`industry`, `Prospect`.`industry`, `Customer`.`industry`

## Party Specific Item

- **Table**: `tabParty Specific Item`  (proposed: `party_specific_item`)
- **Kind**: Master
- **Owned by**: erpnext / Selling
- **Title field**: `party`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `party_type` | Select | `varchar(140)` | NOT NULL | enum: Customer, Customer Group, Supplier, Supplier Group |
| 2 | `party` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `party_type` |
| 3 | `restrict_based_on` | Select | `varchar(140)` | NOT NULL | enum: Item, Item Group, Brand |
| 4 | `based_on_value` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `restrict_based_on` |

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `based_on_value` — target DocType read from `restrict_based_on`

## Sales Partner Type

- **Table**: `tabSales Partner Type`  (proposed: `sales_partner_type`)
- **Kind**: Master
- **Owned by**: erpnext / Selling
- **Naming**: `field:sales_partner_type`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_partner_type` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (1):** `Sales Partner`.`partner_type`

---

# Transaction (submittable)s

## Installation Note

- **Table**: `tabInstallation Note`  (proposed: `installation_note`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Selling
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: MAT-INS-.YYYY.- |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL, INDEX | → `Customer` |
| 3 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 4 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 5 | `customer_name` | Data | `varchar(140)` | ro |  |
| 6 | `address_display` | Text Editor | `text` | ro, hidden |  |
| 7 | `contact_display` | Small Text | `text` | ro, hidden |  |
| 8 | `contact_mobile` | Small Text | `text` | ro |  |
| 9 | `contact_email` | Data | `varchar(140)` | ro |  |
| 10 | `territory` | Link | `varchar(140)` | NOT NULL, INDEX | → `Territory` |
| 11 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 12 | `inst_date` | Date | `date` | NOT NULL, INDEX |  |
| 13 | `inst_time` | Time | `time(6)` |  |  |
| 14 | `status` | Select | `varchar(140)` | NOT NULL, ro, default=Draft | enum: Draft, Submitted, Cancelled |
| 15 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 16 | `amended_from` | Link | `varchar(140)` | ro | → `Installation Note` |
| 17 | `remarks` | Small Text | `text` |  |  |
| 18 | `project` | Link | `varchar(140)` |  | → `Project` |

**Child tables (1-N):**

- `items` → `Installation Note Item` (line items)

**Referenced by (1):** `Installation Note`.`amended_from`

## Product Bundle

- **Table**: `tabProduct Bundle`  (proposed: `product_bundle`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Selling
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Description**: Aggregate a group of Items into another Item. This is useful if you are maintaining the stock of the packed items and not the bundled item
- **Search fields**: `new_item_code,description`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `new_item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `description` | Data | `varchar(140)` |  |  |
| 3 | `is_active` | Check | `smallint` | default=1 |  |
| 4 | `disabled` | Check | `smallint` | default=0 |  |
| 5 | `amended_from` | Link | `varchar(140)` | ro | → `Product Bundle` |

**Child tables (1-N):**

- `items` → `Product Bundle Item` (line items)

**Referenced by (10):** `POS Invoice Item`.`product_bundle`, `Purchase Invoice Item`.`product_bundle`, `Sales Invoice Item`.`product_bundle`, `Purchase Order Item`.`product_bundle`, `Product Bundle`.`amended_from`, `Quotation Item`.`product_bundle`, `Sales Order Item`.`product_bundle`, `Delivery Note Item`.`product_bundle`, `Packed Item`.`product_bundle`, `Purchase Receipt Item`.`product_bundle`

## Proforma Invoice

- **Table**: `tabProforma Invoice`  (proposed: `proforma_invoice`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Selling
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: PRO-.YYYY.- |
| 2 | `sales_order` | Link | `varchar(140)` | NOT NULL, ro | → `Sales Order` |
| 3 | `customer` | Link | `varchar(140)` | ro, denorm←sales_order.customer | → `Customer` |
| 4 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 5 | `proforma_date` | Date | `date` | NOT NULL, default=Today |  |
| 6 | `company` | Link | `varchar(140)` | NOT NULL, ro, denorm←sales_order.company | → `Company` |
| 7 | `currency` | Link | `varchar(140)` | ro, denorm←sales_order.currency | → `Currency` *(frappe/Geo)* |
| 8 | `based_on` | Select | `varchar(140)` | ro, default=Quantity | enum: Quantity, Amount |
| 9 | `hide_item_qty` | Check | `smallint` | ro, default=0 |  |
| 10 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 11 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 12 | `print_format` | Link | `varchar(140)` | ro | → `Print Format` *(frappe/Printing)* |
| 13 | `letter_head` | Link | `varchar(140)` | ro | → `Letter Head` *(frappe/Printing)* |
| 14 | `proforma_pdf` | Attach | `text` | ro |  |
| 15 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Issued, Cancelled |
| 16 | `sent_on` | Datetime | `timestamp` | ro |  |
| 17 | `emailed_to` | Small Text | `text` | ro |  |
| 18 | `amended_from` | Link | `varchar(140)` | ro | → `Proforma Invoice` |

**Child tables (1-N):**

- `items` → `Proforma Invoice Item` (line items)

**Referenced by (1):** `Proforma Invoice`.`amended_from`

## Quotation

- **Table**: `tabQuotation`  (proposed: `quotation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Selling
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status,transaction_date,party_name,order_type`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: SAL-QTN-.YYYY.- |
| 2 | `quotation_to` | Link | `varchar(140)` | NOT NULL, default=Customer | → `DocType` *(frappe/Core)* |
| 3 | `party_name` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `quotation_to` |
| 4 | `customer_name` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `amended_from` | Link | `varchar(140)` | ro | → `Quotation` |
| 6 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 7 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 8 | `valid_till` | Date | `date` |  |  |
| 9 | `order_type` | Select | `varchar(140)` | NOT NULL, default=Sales | enum: Sales, Maintenance, Shopping Cart |
| 10 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 11 | `address_display` | Text Editor | `text` | ro |  |
| 12 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 13 | `contact_display` | Small Text | `text` | ro |  |
| 14 | `contact_mobile` | Small Text | `text` | ro |  |
| 15 | `contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 16 | `shipping_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 17 | `shipping_address` | Text Editor | `text` | ro |  |
| 18 | `customer_group` | Link | `varchar(140)` | hidden | → `Customer Group` |
| 19 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 20 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 21 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 22 | `selling_price_list` | Link | `varchar(140)` | NOT NULL | → `Price List` |
| 23 | `price_list_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 24 | `plc_conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 25 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 26 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 27 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 28 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 29 | `total` | Currency | `numeric(21,9)` | ro |  |
| 30 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 31 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 32 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 33 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 34 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 35 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 36 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 37 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 38 | `coupon_code` | Link | `varchar(140)` |  | → `Coupon Code` |
| 39 | `referral_sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 40 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 41 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 42 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 43 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 44 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 45 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 46 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 47 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 48 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 49 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 50 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 51 | `in_words` | Data | `varchar(140)` | ro |  |
| 52 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 53 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 54 | `terms` | Text Editor | `text` |  |  |
| 55 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 56 | `group_same_items` | Check | `smallint` | default=0 |  |
| 57 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 58 | `language` | Link | `varchar(140)` | ro | → `Language` *(frappe/Core)* |
| 59 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 60 | `order_lost_reason` | Small Text | `text` |  |  |
| 61 | `status` | Select | `varchar(140)` | NOT NULL, ro, default=Draft | enum: Draft, Open, Replied, Partially Ordered, Ordered, Lost, Cancelled, Expired |
| 62 | `enq_det` | Text | `text` | ro, hidden |  |
| 63 | `supplier_quotation` | Link | `varchar(140)` |  | → `Supplier Quotation` |
| 64 | `opportunity` | Link | `varchar(140)` | ro | → `Opportunity` |
| 65 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 66 | `company_address_display` | Text Editor | `text` | ro |  |
| 67 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 68 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 69 | `named_place` | Data | `varchar(140)` |  |  |
| 70 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 71 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 72 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Medium` *(frappe/Website)* |
| 73 | `utm_content` | Data | `varchar(140)` |  |  |
| 74 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 75 | `company_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 76 | `has_unit_price_items` | Check | `smallint` | hidden, default=0 |  |
| 77 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `Quotation Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `taxes` → `Sales Taxes and Charges` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `lost_reasons` → `Quotation Lost Reason Detail` (multi-select)
- `packed_items` → `Packed Item` (line items)
- `competitors` → `Competitor Detail` (multi-select)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Polymorphic references:**

- `party_name` — target DocType read from `quotation_to`

**Referenced by (2):** `Quotation`.`amended_from`, `Sales Order Item`.`prevdoc_docname`

## Sales Order

- **Table**: `tabSales Order`  (proposed: `sales_order`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Selling
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status,transaction_date,customer,customer_name, territory,order_type,company`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: SAL-ORD-.YYYY.- |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL, INDEX | → `Customer` |
| 3 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 4 | `order_type` | Select | `varchar(140)` | NOT NULL, default=Sales | enum: Sales, Maintenance, Shopping Cart |
| 5 | `amended_from` | Link | `varchar(140)` | ro, hidden | → `Sales Order` |
| 6 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 7 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 8 | `delivery_date` | Date | `date` |  |  |
| 9 | `po_no` | Data | `varchar(140)` |  |  |
| 10 | `po_date` | Date | `date` |  |  |
| 11 | `tax_id` | Data | `varchar(140)` | ro, denorm←customer.tax_id |  |
| 12 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 13 | `address_display` | Text Editor | `text` | ro |  |
| 14 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 15 | `contact_display` | Small Text | `text` | ro |  |
| 16 | `contact_mobile` | Small Text | `text` | ro |  |
| 17 | `contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 18 | `company_address_display` | Text Editor | `text` | ro |  |
| 19 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 20 | `shipping_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 21 | `shipping_address` | Text Editor | `text` | ro |  |
| 22 | `customer_group` | Link | `varchar(140)` | hidden | → `Customer Group` |
| 23 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 24 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 25 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 26 | `selling_price_list` | Link | `varchar(140)` | NOT NULL | → `Price List` |
| 27 | `price_list_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 28 | `plc_conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 29 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 30 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 31 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 32 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 33 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 34 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 35 | `total` | Currency | `numeric(21,9)` | ro |  |
| 36 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 37 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 38 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 39 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 40 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 41 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 42 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 43 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 44 | `loyalty_points` | Int | `integer` | ro, hidden |  |
| 45 | `loyalty_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 46 | `coupon_code` | Link | `varchar(140)` |  | → `Coupon Code` |
| 47 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 48 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 49 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 50 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 51 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 52 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 53 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 54 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 55 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 56 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 57 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 58 | `in_words` | Data | `varchar(140)` | ro |  |
| 59 | `advance_paid` | Currency | `numeric(21,9)` | ro |  |
| 60 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 61 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 62 | `terms` | Text Editor | `text` |  |  |
| 63 | `inter_company_order_reference` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 64 | `project` | Link | `varchar(140)` | INDEX | → `Project` |
| 65 | `party_account_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 66 | `language` | Link | `varchar(140)` | ro, denorm←customer.language | → `Language` *(frappe/Core)* |
| 67 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 68 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 69 | `group_same_items` | Check | `smallint` | default=0 |  |
| 70 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, On Hold, To Pay, To Deliver and Bill, To Bill, To Deliver, Completed, Cancelled … (+1) |
| 71 | `delivery_status` | Select | `varchar(140)` | hidden | enum: Not Delivered, Fully Delivered, Partly Delivered, Closed, Not Applicable |
| 72 | `per_delivered` | Percent | `numeric(21,9)` | ro |  |
| 73 | `per_billed` | Percent | `numeric(21,9)` | ro |  |
| 74 | `billing_status` | Select | `varchar(140)` | hidden | enum: Not Billed, Fully Billed, Partly Billed, Closed |
| 75 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 76 | `commission_rate` | Float | `numeric(21,9)` | denorm←sales_partner.commission_rate |  |
| 77 | `total_commission` | Currency | `numeric(21,9)` |  |  |
| 78 | `from_date` | Date | `date` |  |  |
| 79 | `to_date` | Date | `date` |  |  |
| 80 | `auto_repeat` | Link | `varchar(140)` |  | → `Auto Repeat` *(frappe/Automation)* |
| 81 | `contact_phone` | Data | `varchar(140)` | ro |  |
| 82 | `skip_delivery_note` | Check | `smallint` | default=0 |  |
| 83 | `is_internal_customer` | Check | `smallint` | ro, denorm←customer.is_internal_customer, default=0 |  |
| 84 | `represents_company` | Link | `varchar(140)` | ro, denorm←customer.represents_company | → `Company` |
| 85 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 86 | `dispatch_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 87 | `dispatch_address` | Text Editor | `text` | ro |  |
| 88 | `amount_eligible_for_commission` | Currency | `numeric(21,9)` | ro |  |
| 89 | `per_picked` | Percent | `numeric(21,9)` | ro |  |
| 90 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 91 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 92 | `named_place` | Data | `varchar(140)` |  |  |
| 93 | `reserve_stock` | Check | `smallint` | default=0 |  |
| 94 | `advance_payment_status` | Select | `varchar(140)` | hidden | enum: Not Requested, Requested, Partially Paid, Fully Paid |
| 95 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Medium` *(frappe/Website)* |
| 96 | `utm_content` | Data | `varchar(140)` |  |  |
| 97 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 98 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 99 | `company_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 100 | `has_unit_price_items` | Check | `smallint` | hidden, default=0 |  |
| 101 | `is_subcontracted` | Check | `smallint` | default=0 |  |
| 102 | `transaction_time` | Time | `time(6)` | default=Now |  |
| 103 | `ignore_default_payment_terms_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 104 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `Sales Order Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `taxes` → `Sales Taxes and Charges` (line items)
- `packed_items` → `Packed Item` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `sales_team` → `Sales Team` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (21):** `POS Invoice Item`.`sales_order`, `Sales Invoice Item`.`sales_order`, `Purchase Order`.`inter_company_order_reference`, `Purchase Order Item`.`sales_order`, `Supplier Quotation Item`.`sales_order`, `Maintenance Schedule Item`.`sales_order`, `Material Request Plan Item`.`sales_order`, `Production Plan Item`.`sales_order`, `Production Plan Item Reference`.`sales_order`, `Production Plan Sales Order`.`sales_order`, `Production Plan Sub Assembly Item`.`sales_order`, `Work Order`.`sales_order`, `Project`.`sales_order`, `Delivery Schedule Item`.`sales_order`, `Proforma Invoice`.`sales_order` … (+6 more)

---

# Child / line-item tables

## Customer Credit Limit

- **Table**: `tabCustomer Credit Limit`  (proposed: `customer_credit_limit`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `Customer`.`credit_limits`, `Customer Group`.`credit_limits`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `credit_limit` | Currency | `numeric(21,9)` |  |  |
| 2 | `overdue_billing_threshold` | Currency | `numeric(21,9)` | hidden |  |
| 3 | `company` | Link | `varchar(140)` |  | → `Company` |
| 4 | `bypass_credit_limit_check` | Check | `smallint` | default=0 |  |

## Installation Note Item

- **Table**: `tabInstallation Note Item`  (proposed: `installation_note_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Naming**: `hash`  (Random)
- **Embedded in**: `Installation Note`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `serial_no` | Small Text | `text` |  |  |
| 3 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 4 | `description` | Text Editor | `text` | ro |  |
| 5 | `prevdoc_detail_docname` | Data | `varchar(140)` | ro, hidden |  |
| 6 | `prevdoc_docname` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 7 | `prevdoc_doctype` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 8 | `serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |

## Product Bundle Item

- **Table**: `tabProduct Bundle Item`  (proposed: `product_bundle_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `Product Bundle`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 3 | `description` | Text Editor | `text` | denorm←item_code.description |  |
| 4 | `rate` | Float | `numeric(21,9)` | hidden |  |
| 5 | `uom` | Link | `varchar(140)` | ro, denorm←item_code.stock_uom | → `UOM` |

## Proforma Invoice Item

- **Table**: `tabProforma Invoice Item`  (proposed: `proforma_invoice_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `Proforma Invoice`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | ro, denorm←item_code.item_name |  |
| 3 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 4 | `uom` | Link | `varchar(140)` | ro | → `UOM` |
| 5 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 6 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 7 | `so_detail` | Data | `varchar(140)` | ro |  |

## Quotation Item

- **Table**: `tabQuotation Item`  (proposed: `quotation_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `Quotation`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | INDEX | → `Item` |
| 2 | `is_product_bundle` | Check | `smallint` | ro, hidden, default=0 |  |
| 3 | `product_bundle` | Link | `varchar(140)` |  | → `Product Bundle` |
| 4 | `customer_item_code` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 6 | `description` | Text Editor | `text` |  |  |
| 7 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 8 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 9 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 10 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 11 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 12 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 13 | `price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 14 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 15 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 16 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 17 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 18 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 19 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 20 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 21 | `rate` | Currency | `numeric(21,9)` |  |  |
| 22 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 23 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 24 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 25 | `base_rate` | Currency | `numeric(21,9)` | ro |  |
| 26 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 27 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 28 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 29 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 30 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 31 | `weight_per_unit` | Float | `numeric(21,9)` | ro |  |
| 32 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 33 | `weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 34 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 35 | `projected_qty` | Float | `numeric(21,9)` | ro |  |
| 36 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 37 | `prevdoc_doctype` | Link | `varchar(140)` | ro, hidden | → `DocType` *(frappe/Core)* |
| 38 | `prevdoc_docname` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `prevdoc_doctype` |
| 39 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 40 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 41 | `page_break` | Check | `smallint` | default=0 |  |
| 42 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 43 | `brand` | Link | `varchar(140)` | ro, hidden | → `Brand` |
| 44 | `additional_notes` | Text | `text` |  |  |
| 45 | `blanket_order` | Link | `varchar(140)` |  | → `Blanket Order` |
| 46 | `blanket_order_rate` | Currency | `numeric(21,9)` | ro |  |
| 47 | `against_blanket_order` | Check | `smallint` | default=0 |  |
| 48 | `valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 49 | `gross_profit` | Currency | `numeric(21,9)` | ro |  |
| 50 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 51 | `is_alternative` | Check | `smallint` | default=0 |  |
| 52 | `has_alternative_item` | Check | `smallint` | ro, hidden, default=0 |  |
| 53 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 54 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |
| 55 | `ordered_qty` | Float | `numeric(21,9)` | NOT NULL, ro, hidden, default=0 |  |

**Polymorphic references:**

- `prevdoc_docname` — target DocType read from `prevdoc_doctype`

## Sales Order Item

- **Table**: `tabSales Order Item`  (proposed: `sales_order_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Naming**: `hash`  (Random)
- **Embedded in**: `Sales Order`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `is_product_bundle` | Check | `smallint` | ro, hidden, default=0 |  |
| 3 | `product_bundle` | Link | `varchar(140)` |  | → `Product Bundle` |
| 4 | `customer_item_code` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `ensure_delivery_based_on_produced_serial_no` | Check | `smallint` | default=0 |  |
| 6 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 7 | `description` | Text Editor | `text` |  |  |
| 8 | `delivery_date` | Date | `date` |  |  |
| 9 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 10 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 11 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 12 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 13 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 14 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 15 | `price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 17 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 18 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 19 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 20 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 21 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 22 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 23 | `rate` | Currency | `numeric(21,9)` |  |  |
| 24 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 25 | `base_rate` | Currency | `numeric(21,9)` | ro |  |
| 26 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 27 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 28 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 29 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 30 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 31 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 32 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 33 | `delivered_by_supplier` | Check | `smallint` | default=0 |  |
| 34 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 35 | `weight_per_unit` | Float | `numeric(21,9)` |  |  |
| 36 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 37 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 38 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 39 | `target_warehouse` | Link | `varchar(140)` | hidden | → `Warehouse` |
| 40 | `prevdoc_docname` | Link | `varchar(140)` | INDEX, ro | → `Quotation` |
| 41 | `brand` | Link | `varchar(140)` | ro, hidden | → `Brand` |
| 42 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 43 | `billed_amt` | Currency | `numeric(21,9)` | ro |  |
| 44 | `valuation_rate` | Currency | `numeric(21,9)` | ro |  |
| 45 | `gross_profit` | Currency | `numeric(21,9)` | ro |  |
| 46 | `blanket_order` | Link | `varchar(140)` |  | → `Blanket Order` |
| 47 | `blanket_order_rate` | Currency | `numeric(21,9)` | ro |  |
| 48 | `projected_qty` | Float | `numeric(21,9)` | ro |  |
| 49 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 50 | `ordered_qty` | Float | `numeric(21,9)` | ro |  |
| 51 | `delivered_qty` | Float | `numeric(21,9)` | ro |  |
| 52 | `work_order_qty` | Float | `numeric(21,9)` | ro |  |
| 53 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 54 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 55 | `page_break` | Check | `smallint` | default=0 |  |
| 56 | `planned_qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 57 | `produced_qty` | Float | `numeric(21,9)` | ro, hidden |  |
| 58 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 59 | `transaction_date` | Date | `date` | ro, hidden |  |
| 60 | `additional_notes` | Text | `text` |  |  |
| 61 | `against_blanket_order` | Check | `smallint` | default=0 |  |
| 62 | `bom_no` | Link | `varchar(140)` |  | → `BOM` |
| 63 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 64 | `grant_commission` | Check | `smallint` | ro, denorm←item_code.grant_commission, default=0 |  |
| 65 | `picked_qty` | Float | `numeric(21,9)` | ro |  |
| 66 | `purchase_order` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 67 | `purchase_order_item` | Data | `varchar(140)` | ro |  |
| 68 | `quotation_item` | Data | `varchar(140)` | ro, hidden |  |
| 69 | `material_request` | Link | `varchar(140)` |  | → `Material Request` |
| 70 | `material_request_item` | Data | `varchar(140)` |  |  |
| 71 | `reserve_stock` | Check | `smallint` | default=1 |  |
| 72 | `stock_reserved_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 73 | `production_plan_qty` | Float | `numeric(21,9)` | ro |  |
| 74 | `is_stock_item` | Check | `smallint` | hidden, denorm←item_code.is_stock_item, default=0 |  |
| 75 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 76 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |
| 77 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 78 | `project` | Link | `varchar(140)` | INDEX | → `Project` |
| 79 | `subcontracted_qty` | Float | `numeric(21,9)` | ro, default=0 |  |
| 80 | `fg_item` | Link | `varchar(140)` |  | → `Item` |
| 81 | `fg_item_qty` | Float | `numeric(21,9)` |  |  |
| 82 | `requested_qty` | Float | `numeric(21,9)` | ro |  |

## Sales Team

- **Table**: `tabSales Team`  (proposed: `sales_team`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `POS Invoice`.`sales_team`, `Sales Invoice`.`sales_team`, `Customer`.`sales_team`, `Sales Order`.`sales_team`, `Delivery Note`.`sales_team`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_person` | Link | `varchar(140)` | NOT NULL, INDEX | → `Sales Person` |
| 2 | `contact_no` | Data | `varchar(140)` | hidden |  |
| 3 | `allocated_percentage` | Float | `numeric(21,9)` |  |  |
| 4 | `allocated_amount` | Currency | `numeric(21,9)` | ro |  |
| 5 | `commission_rate` | Percent | `numeric(21,9)` | ro, denorm←sales_person.commission_rate |  |
| 6 | `incentives` | Currency | `numeric(21,9)` |  |  |

## Supplier Number At Customer

- **Table**: `tabSupplier Number At Customer`  (proposed: `supplier_number_at_customer`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Selling
- **Embedded in**: `Customer`.`supplier_numbers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `supplier_number` | Data | `varchar(140)` |  |  |
