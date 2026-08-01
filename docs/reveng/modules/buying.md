# Module deep dive: Buying

Procure-to-pay masters and documents: `Supplier`, `Request for Quotation`,
`Supplier Quotation`, `Purchase Order`. Mirrors Selling almost field for field — a strong
hint that our own design should share one abstraction for both trade directions.

19 DocTypes / 489 columns.

## Contents

**Single (settings)** (1): [Buying Settings](#buying-settings)

**Master** (5): [Supplier](#supplier), [Supplier Scorecard](#supplier-scorecard), [Supplier Scorecard Criteria](#supplier-scorecard-criteria), [Supplier Scorecard Standing](#supplier-scorecard-standing), [Supplier Scorecard Variable](#supplier-scorecard-variable)

**Transaction (submittable)** (4): [Purchase Order](#purchase-order), [Request for Quotation](#request-for-quotation), [Supplier Quotation](#supplier-quotation), [Supplier Scorecard Period](#supplier-scorecard-period)

**Child / line-item table** (9): [Customer Number At Supplier](#customer-number-at-supplier), [Purchase Order Item](#purchase-order-item), [Purchase Receipt Item Supplied](#purchase-receipt-item-supplied), [Request for Quotation Item](#request-for-quotation-item), [Request for Quotation Supplier](#request-for-quotation-supplier), [Supplier Quotation Item](#supplier-quotation-item), [Supplier Scorecard Scoring Criteria](#supplier-scorecard-scoring-criteria), [Supplier Scorecard Scoring Standing](#supplier-scorecard-scoring-standing), [Supplier Scorecard Scoring Variable](#supplier-scorecard-scoring-variable)

---

# Single (settings)s

## Buying Settings

- **Table**: `tabBuying Settings`  (proposed: `buying_settings`)
- **Kind**: Single (settings)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supp_master_name` | Select | `varchar(140)` | default=Supplier Name | enum: Supplier Name, Naming Series, Auto Name |
| 2 | `supplier_group` | Link | `varchar(140)` |  | → `Supplier Group` |
| 3 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 4 | `po_required` | Select | `varchar(140)` |  | enum: No, Yes |
| 5 | `pr_required` | Select | `varchar(140)` |  | enum: No, Yes |
| 6 | `maintain_same_rate` | Check | `smallint` | default=0 |  |
| 7 | `allow_multiple_items` | Check | `smallint` | default=0 |  |
| 8 | `backflush_raw_materials_of_subcontract_based_on` | Select | `varchar(140)` | default=BOM | enum: BOM, Material Transferred for Subcontract |
| 9 | `over_transfer_allowance` | Float | `numeric(21,9)` |  |  |
| 10 | `maintain_same_rate_action` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn |
| 11 | `role_to_override_stop_action` | Link | `varchar(140)` |  | → `Role` *(frappe core)* |
| 12 | `bill_for_rejected_quantity_in_purchase_invoice` | Check | `smallint` | default=1 |  |
| 13 | `disable_last_purchase_rate` | Check | `smallint` | default=0 |  |
| 14 | `show_pay_button` | Check | `smallint` | default=1 |  |
| 15 | `set_landed_cost_based_on_purchase_invoice_rate` | Check | `smallint` | default=0 |  |
| 16 | `use_transaction_date_exchange_rate` | Check | `smallint` | default=0 |  |
| 17 | `blanket_order_allowance` | Float | `numeric(21,9)` | default=0 |  |
| 18 | `auto_create_subcontracting_order` | Check | `smallint` | default=0 |  |
| 19 | `auto_create_purchase_receipt` | Check | `smallint` | default=0 |  |
| 20 | `project_update_frequency` | Select | `varchar(140)` | default=Each Transaction | enum: Each Transaction, Manual |
| 21 | `allow_zero_qty_in_purchase_order` | Check | `smallint` | default=0 |  |
| 22 | `allow_zero_qty_in_request_for_quotation` | Check | `smallint` | default=0 |  |
| 23 | `allow_zero_qty_in_supplier_quotation` | Check | `smallint` | default=0 |  |
| 24 | `set_valuation_rate_for_rejected_materials` | Check | `smallint` | default=0 |  |
| 25 | `fixed_email` | Link | `varchar(140)` |  | → `Email Account` *(frappe core)* |
| 26 | `validate_consumed_qty` | Check | `smallint` | default=0 |  |
| 27 | `allow_negative_rates_for_items` | Check | `smallint` | default=0 |  |
| 28 | `over_order_allowance` | Float | `numeric(21,9)` |  |  |

---

# Masters

## Supplier

- **Table**: `tabSupplier`  (proposed: `supplier`)
- **Kind**: Master
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Description**: Supplier of Goods or Services.
- **Search fields**: `supplier_group, alias`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: SUP-.YYYY.- |
| 2 | `supplier_name` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `country` | Link | `varchar(140)` |  | → `Country` *(frappe core)* |
| 4 | `default_bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 5 | `tax_id` | Data | `varchar(140)` |  |  |
| 6 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 7 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 8 | `is_transporter` | Check | `smallint` | default=0 |  |
| 9 | `is_internal_supplier` | Check | `smallint` | default=0 |  |
| 10 | `represents_company` | Link | `varchar(140)` |  | → `Company` |
| 11 | `image` | Attach Image | `text` | hidden |  |
| 12 | `supplier_group` | Link | `varchar(140)` |  | → `Supplier Group` |
| 13 | `supplier_type` | Select | `varchar(140)` | NOT NULL, default=Company | enum: Company, Individual, Partnership |
| 14 | `language` | Link | `varchar(140)` |  | → `Language` *(frappe core)* |
| 15 | `disabled` | Check | `smallint` | default=0 |  |
| 16 | `warn_rfqs` | Check | `smallint` | ro, hidden, default=0 |  |
| 17 | `warn_pos` | Check | `smallint` | ro, hidden, default=0 |  |
| 18 | `prevent_rfqs` | Check | `smallint` | ro, hidden, default=0 |  |
| 19 | `prevent_pos` | Check | `smallint` | ro, hidden, default=0 |  |
| 20 | `default_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe core)* |
| 21 | `default_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 22 | `payment_terms` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 23 | `on_hold` | Check | `smallint` | default=0 |  |
| 24 | `hold_type` | Select | `varchar(140)` | default=All | enum: All, Invoices, Payments |
| 25 | `release_date` | Date | `date` |  |  |
| 26 | `website` | Data | `varchar(140)` |  |  |
| 27 | `supplier_details` | Text | `text` |  |  |
| 28 | `is_frozen` | Check | `smallint` | default=0 |  |
| 29 | `allow_purchase_invoice_creation_without_purchase_order` | Check | `smallint` | default=0 |  |
| 30 | `allow_purchase_invoice_creation_without_purchase_receipt` | Check | `smallint` | default=0 |  |
| 31 | `supplier_primary_contact` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 32 | `mobile_no` | Read Only | `varchar(140)` | denorm←supplier_primary_contact.mobile_no |  |
| 33 | `email_id` | Read Only | `varchar(140)` | denorm←supplier_primary_contact.email_id |  |
| 34 | `primary_address` | Text Editor | `text` | ro |  |
| 35 | `supplier_primary_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 36 | `restrict_to_companies` | Check | `smallint` | default=0 |  |
| 37 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 38 | `gender` | Link | `varchar(140)` |  | → `Gender` *(frappe core)* |
| 39 | `alias` | Data | `varchar(140)` | UNIQUE |  |

**Child tables (1-N):**

- `companies` → `Allowed To Transact With` (line items)
- `accounts` → `Party Account` (line items)
- `allowed_companies` → `Company Restriction` (multi-select)
- `portal_users` → `Portal User` (line items)
- `customer_numbers` → `Customer Number At Supplier` (line items)

**Referenced by (33):** `Bank Guarantee`.`supplier`, `Payment Order`.`party`, `Payment Order Reference`.`supplier`, `Pricing Rule`.`supplier`, `Purchase Invoice`.`supplier`, `Supplier Item`.`supplier`, `Tax Rule`.`supplier`, `Asset`.`supplier`, `Purchase Order`.`supplier`, `Request for Quotation`.`vendor`, `Request for Quotation Supplier`.`supplier`, `Supplier Quotation`.`supplier`, `Supplier Scorecard`.`supplier`, `Supplier Scorecard Period`.`supplier`, `Communication Medium`.`provider` … (+18 more)

## Supplier Scorecard

- **Table**: `tabSupplier Scorecard`  (proposed: `supplier_scorecard`)
- **Kind**: Master
- **Naming**: `field:supplier`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier` | Link | `varchar(140)` | UNIQUE | → `Supplier` |
| 2 | `supplier_score` | Data | `varchar(140)` | ro |  |
| 3 | `indicator_color` | Data | `varchar(140)` | hidden |  |
| 4 | `status` | Data | `varchar(140)` | hidden |  |
| 5 | `period` | Select | `varchar(140)` | NOT NULL, default=Per Month | enum: Per Week, Per Month, Per Year |
| 6 | `weighting_function` | Small Text | `text` | NOT NULL, default={total_score} * max( 0,  |  |
| 7 | `warn_rfqs` | Check | `smallint` | ro, default=0 |  |
| 8 | `warn_pos` | Check | `smallint` | ro, default=0 |  |
| 9 | `prevent_rfqs` | Check | `smallint` | ro, default=0 |  |
| 10 | `prevent_pos` | Check | `smallint` | ro, default=0 |  |
| 11 | `notify_supplier` | Check | `smallint` | ro, hidden, default=0 |  |
| 12 | `notify_employee` | Check | `smallint` | ro, hidden, default=0 |  |
| 13 | `employee` | Link | `varchar(140)` | ro, hidden | → `Employee` |

**Child tables (1-N):**

- `standings` → `Supplier Scorecard Scoring Standing` (line items)
- `criteria` → `Supplier Scorecard Scoring Criteria` (line items)

**Referenced by (1):** `Supplier Scorecard Period`.`scorecard`

## Supplier Scorecard Criteria

- **Table**: `tabSupplier Scorecard Criteria`  (proposed: `supplier_scorecard_criteria`)
- **Kind**: Master
- **Naming**: `field:criteria_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `criteria_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `max_score` | Float | `numeric(21,9)` | NOT NULL, default=100 |  |
| 3 | `formula` | Small Text | `text` | NOT NULL |  |
| 4 | `weight` | Percent | `numeric(21,9)` |  |  |

**Referenced by (1):** `Supplier Scorecard Scoring Criteria`.`criteria_name`

## Supplier Scorecard Standing

- **Table**: `tabSupplier Scorecard Standing`  (proposed: `supplier_scorecard_standing`)
- **Kind**: Master
- **Naming**: `field:standing_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `standing_name` | Data | `varchar(140)` | UNIQUE |  |
| 2 | `standing_color` | Select | `varchar(140)` |  | enum: Blue, Purple, Green, Yellow, Orange, Red |
| 3 | `min_grade` | Percent | `numeric(21,9)` |  |  |
| 4 | `max_grade` | Percent | `numeric(21,9)` |  |  |
| 5 | `warn_rfqs` | Check | `smallint` | default=0 |  |
| 6 | `warn_pos` | Check | `smallint` | default=0 |  |
| 7 | `prevent_rfqs` | Check | `smallint` | default=0 |  |
| 8 | `prevent_pos` | Check | `smallint` | default=0 |  |
| 9 | `notify_supplier` | Check | `smallint` | hidden, default=0 |  |
| 10 | `notify_employee` | Check | `smallint` | hidden, default=0 |  |
| 11 | `employee_link` | Link | `varchar(140)` | hidden | → `Employee` |

**Referenced by (1):** `Supplier Scorecard Scoring Standing`.`standing_name`

## Supplier Scorecard Variable

- **Table**: `tabSupplier Scorecard Variable`  (proposed: `supplier_scorecard_variable`)
- **Kind**: Master
- **Naming**: `field:variable_label`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `variable_label` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `is_custom` | Check | `smallint` | default=0 |  |
| 3 | `param_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 4 | `path` | Data | `varchar(140)` | NOT NULL |  |
| 5 | `description` | Small Text | `text` |  |  |

**Referenced by (1):** `Supplier Scorecard Scoring Variable`.`variable_label`

---

# Transaction (submittable)s

## Purchase Order

- **Table**: `tabPurchase Order`  (proposed: `purchase_order`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, transaction_date, supplier, grand_total`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: PUR-ORD-.YYYY.- |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 4 | `supplier_name` | Data | `varchar(140)` | ro, denorm←supplier.supplier_name |  |
| 5 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 6 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 7 | `schedule_date` | Date | `date` |  |  |
| 8 | `order_confirmation_no` | Data | `varchar(140)` |  |  |
| 9 | `order_confirmation_date` | Date | `date` |  |  |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `Purchase Order` |
| 11 | `customer` | Link | `varchar(140)` | ro | → `Customer` |
| 12 | `customer_name` | Data | `varchar(140)` | ro |  |
| 13 | `customer_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 14 | `customer_contact_display` | Small Text | `text` |  |  |
| 15 | `customer_contact_mobile` | Small Text | `text` | hidden |  |
| 16 | `customer_contact_email` | Code | `text` | hidden |  |
| 17 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 18 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 19 | `address_display` | Text Editor | `text` | ro |  |
| 20 | `contact_display` | Small Text | `text` | ro |  |
| 21 | `contact_mobile` | Small Text | `text` | ro |  |
| 22 | `contact_email` | Small Text | `text` | ro |  |
| 23 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 24 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 25 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe core)* |
| 26 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 27 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 28 | `price_list_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe core)* |
| 29 | `plc_conversion_rate` | Float | `numeric(21,9)` |  |  |
| 30 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 31 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 32 | `is_subcontracted` | Check | `smallint` | default=0 |  |
| 33 | `supplier_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 34 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 35 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 36 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 37 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 38 | `total` | Currency | `numeric(21,9)` | ro |  |
| 39 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 40 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 41 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 42 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 43 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 44 | `base_taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 45 | `base_taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 46 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 47 | `taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 48 | `taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 49 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 50 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 51 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 52 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 53 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 54 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 55 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 56 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 57 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 58 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 59 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 60 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 61 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 62 | `in_words` | Data | `varchar(140)` | ro |  |
| 63 | `advance_paid` | Currency | `numeric(21,9)` | ro |  |
| 64 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 65 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 66 | `terms` | Text Editor | `text` |  |  |
| 67 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro, default=Draft | enum: Draft, On Hold, To Receive and Bill, To Bill, To Receive, Completed, Cancelled, Closed … (+1) |
| 68 | `ref_sq` | Link | `varchar(140)` | ro | → `Supplier Quotation` |
| 69 | `party_account_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe core)* |
| 70 | `inter_company_order_reference` | Link | `varchar(140)` | ro | → `Sales Order` |
| 71 | `per_received` | Percent | `numeric(21,9)` | ro |  |
| 72 | `per_billed` | Percent | `numeric(21,9)` | ro |  |
| 73 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 74 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe core)* |
| 75 | `group_same_items` | Check | `smallint` | default=0 |  |
| 76 | `language` | Data | `varchar(140)` |  |  |
| 77 | `from_date` | Date | `date` |  |  |
| 78 | `to_date` | Date | `date` |  |  |
| 79 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe core)* |
| 80 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 81 | `set_reserve_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 82 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 83 | `billing_address_display` | Text Editor | `text` | ro |  |
| 84 | `is_internal_supplier` | Check | `smallint` | ro, denorm←supplier.is_internal_supplier, default=0 |  |
| 85 | `represents_company` | Link | `varchar(140)` | ro, denorm←supplier.represents_company | → `Company` |
| 86 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 87 | `project` | Link | `varchar(140)` |  | → `Project` |
| 88 | `set_from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 89 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 90 | `named_place` | Data | `varchar(140)` |  |  |
| 91 | `advance_payment_status` | Select | `varchar(140)` | hidden | enum: Not Initiated, Initiated, Partially Paid, Fully Paid |
| 92 | `has_unit_price_items` | Check | `smallint` | hidden, default=0 |  |
| 93 | `dispatch_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 94 | `dispatch_address_display` | Text Editor | `text` | ro |  |
| 95 | `supplier_group` | Link | `varchar(140)` | hidden | → `Supplier Group` |
| 96 | `mps` | Link | `varchar(140)` | ro | → `Master Production Schedule` |
| 97 | `transaction_time` | Time | `time(6)` | default=Now |  |

**Child tables (1-N):**

- `items` → `Purchase Order Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `taxes` → `Purchase Taxes and Charges` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (12):** `Purchase Invoice Item`.`purchase_order`, `Sales Invoice Item`.`purchase_order`, `Purchase Order`.`amended_from`, `Purchase Receipt Item Supplied`.`purchase_order`, `Production Plan Sub Assembly Item`.`purchase_order`, `Sales Order`.`inter_company_order_reference`, `Sales Order Item`.`purchase_order`, `Delivery Note Item`.`purchase_order`, `Purchase Receipt Item`.`purchase_order`, `Stock Entry`.`purchase_order`, `Subcontracting Order`.`purchase_order`, `Subcontracting Receipt Item`.`purchase_order`

## Request for Quotation

- **Table**: `tabRequest for Quotation`  (proposed: `request_for_quotation`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `company`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, transaction_date`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: PUR-RFQ-.YYYY.- |
| 2 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 3 | `vendor` | Link | `varchar(140)` | ro, hidden | → `Supplier` |
| 4 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 5 | `email_template` | Link | `varchar(140)` |  | → `Email Template` *(frappe core)* |
| 6 | `message_for_supplier` | Text Editor | `text` | default=Please supply the specif |  |
| 7 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 8 | `terms` | Text Editor | `text` |  |  |
| 9 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe core)* |
| 10 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 11 | `opportunity` | Link | `varchar(140)` | ro | → `Opportunity` |
| 12 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro | enum: Draft, Submitted, Cancelled |
| 13 | `amended_from` | Link | `varchar(140)` | ro | → `Request for Quotation` |
| 14 | `schedule_date` | Date | `date` |  |  |
| 15 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 16 | `named_place` | Data | `varchar(140)` |  |  |
| 17 | `send_attached_files` | Check | `smallint` | default=1 |  |
| 18 | `send_document_print` | Check | `smallint` | default=0 |  |
| 19 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 20 | `billing_address_display` | Text Editor | `text` | ro |  |
| 21 | `has_unit_price_items` | Check | `smallint` | hidden, default=0 |  |
| 22 | `subject` | Data | `varchar(140)` | NOT NULL, default=Request for Quotation |  |
| 23 | `mfs_html` | Code | `text` |  |  |
| 24 | `use_html` | Check | `smallint` | hidden, default=0 |  |
| 25 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 26 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 27 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `suppliers` → `Request for Quotation Supplier` (line items)
- `items` → `Request for Quotation Item` (line items)

**Referenced by (2):** `Request for Quotation`.`amended_from`, `Supplier Quotation Item`.`request_for_quotation`

## Supplier Quotation

- **Table**: `tabSupplier Quotation`  (proposed: `supplier_quotation`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `status, transaction_date, supplier,grand_total`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: PUR-SQTN-.YYYY.- |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 4 | `supplier_name` | Data | `varchar(140)` | ro, denorm←supplier.supplier_name |  |
| 5 | `transaction_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 6 | `amended_from` | Link | `varchar(140)` | ro, hidden | → `Supplier Quotation` |
| 7 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 8 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 9 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 10 | `address_display` | Text Editor | `text` | ro |  |
| 11 | `contact_display` | Small Text | `text` | ro |  |
| 12 | `contact_mobile` | Small Text | `text` | ro |  |
| 13 | `contact_email` | Data | `varchar(140)` | ro |  |
| 14 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe core)* |
| 15 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 16 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 17 | `price_list_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe core)* |
| 18 | `plc_conversion_rate` | Float | `numeric(21,9)` |  |  |
| 19 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 20 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 21 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 22 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 23 | `total` | Currency | `numeric(21,9)` | ro |  |
| 24 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 25 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 26 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 27 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 28 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 29 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 30 | `base_taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 31 | `base_taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 32 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 33 | `taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 34 | `taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 35 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 36 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 37 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 38 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 39 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 40 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 41 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 42 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 43 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 44 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 45 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 46 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 47 | `in_words` | Data | `varchar(140)` | ro |  |
| 48 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 49 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 50 | `terms` | Text Editor | `text` |  |  |
| 51 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe core)* |
| 52 | `group_same_items` | Check | `smallint` | default=0 |  |
| 53 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 54 | `language` | Data | `varchar(140)` | ro |  |
| 55 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe core)* |
| 56 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, ro | enum: Draft, Submitted, Stopped, Cancelled, Expired |
| 57 | `is_subcontracted` | Check | `smallint` | default=0 |  |
| 58 | `opportunity` | Link | `varchar(140)` | ro | → `Opportunity` |
| 59 | `valid_till` | Date | `date` |  |  |
| 60 | `quotation_number` | Data | `varchar(140)` |  |  |
| 61 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 62 | `named_place` | Data | `varchar(140)` |  |  |
| 63 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 64 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 65 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 66 | `billing_address_display` | Text Editor | `text` | ro |  |
| 67 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 68 | `project` | Link | `varchar(140)` |  | → `Project` |
| 69 | `has_unit_price_items` | Check | `smallint` | hidden, default=0 |  |

**Child tables (1-N):**

- `items` → `Supplier Quotation Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `taxes` → `Purchase Taxes and Charges` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (4):** `Purchase Order`.`ref_sq`, `Purchase Order Item`.`supplier_quotation`, `Supplier Quotation`.`amended_from`, `Quotation`.`supplier_quotation`

## Supplier Scorecard Period

- **Table**: `tabSupplier Scorecard Period`  (proposed: `supplier_scorecard_period`)
- **Kind**: Transaction (submittable)
- **Naming**: `naming_series:`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier` | Link | `varchar(140)` | NOT NULL | → `Supplier` |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: PU-SSP-.YYYY.- |
| 3 | `total_score` | Percent | `numeric(21,9)` | ro |  |
| 4 | `start_date` | Date | `date` | NOT NULL |  |
| 5 | `end_date` | Date | `date` | NOT NULL |  |
| 6 | `scorecard` | Link | `varchar(140)` | NOT NULL | → `Supplier Scorecard` |
| 7 | `amended_from` | Link | `varchar(140)` | ro | → `Supplier Scorecard Period` |

**Child tables (1-N):**

- `criteria` → `Supplier Scorecard Scoring Criteria` (line items)
- `variables` → `Supplier Scorecard Scoring Variable` (line items)

**Referenced by (1):** `Supplier Scorecard Period`.`amended_from`

---

# Child / line-item tables

## Customer Number At Supplier

- **Table**: `tabCustomer Number At Supplier`  (proposed: `customer_number_at_supplier`)
- **Kind**: Child / line-item table
- **Embedded in**: `Supplier`.`customer_numbers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `customer_number` | Data | `varchar(140)` |  |  |

## Purchase Order Item

- **Table**: `tabPurchase Order Item`  (proposed: `purchase_order_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Search fields**: `item_name`
- **Embedded in**: `Purchase Order`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 2 | `supplier_part_no` | Data | `varchar(140)` | ro, hidden |  |
| 3 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 4 | `schedule_date` | Date | `date` | NOT NULL |  |
| 5 | `expected_delivery_date` | Date | `date` | INDEX |  |
| 6 | `description` | Text Editor | `text` |  |  |
| 7 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 8 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 9 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 10 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 11 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 12 | `price_list_rate` | Currency | `numeric(21,9)` |  |  |
| 13 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 14 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 15 | `last_purchase_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 17 | `rate` | Currency | `numeric(21,9)` |  |  |
| 18 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 19 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 20 | `base_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 21 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 22 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 23 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 24 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 25 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 26 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 27 | `weight_per_unit` | Float | `numeric(21,9)` | ro |  |
| 28 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 29 | `weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 30 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 31 | `project` | Link | `varchar(140)` |  | → `Project` |
| 32 | `material_request` | Link | `varchar(140)` | INDEX, ro | → `Material Request` |
| 33 | `material_request_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 34 | `sales_order` | Link | `varchar(140)` | INDEX | → `Sales Order` |
| 35 | `sales_order_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 36 | `supplier_quotation` | Link | `varchar(140)` | ro | → `Supplier Quotation` |
| 37 | `supplier_quotation_item` | Link | `varchar(140)` | ro, hidden | → `Supplier Quotation Item` |
| 38 | `delivered_by_supplier` | Check | `smallint` | default=0 |  |
| 39 | `blanket_order` | Link | `varchar(140)` |  | → `Blanket Order` |
| 40 | `blanket_order_rate` | Currency | `numeric(21,9)` | ro |  |
| 41 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 42 | `brand` | Link | `varchar(140)` | ro, hidden | → `Brand` |
| 43 | `bom` | Link | `varchar(140)` | ro | → `BOM` |
| 44 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 45 | `received_qty` | Float | `numeric(21,9)` | ro |  |
| 46 | `returned_qty` | Float | `numeric(21,9)` | ro |  |
| 47 | `billed_amt` | Currency | `numeric(21,9)` | ro |  |
| 48 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 49 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 50 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 51 | `page_break` | Check | `smallint` | default=0 |  |
| 52 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 53 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 54 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 55 | `against_blanket_order` | Check | `smallint` | default=0 |  |
| 56 | `is_fixed_asset` | Check | `smallint` | ro, denorm←item_code.is_fixed_asset, default=0 |  |
| 57 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 58 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 59 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |
| 60 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 61 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 62 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 63 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 64 | `production_plan` | Link | `varchar(140)` | ro | → `Production Plan` |
| 65 | `production_plan_item` | Data | `varchar(140)` | ro, hidden |  |
| 66 | `production_plan_sub_assembly_item` | Data | `varchar(140)` | ro, hidden |  |
| 67 | `product_bundle` | Link | `varchar(140)` | ro, hidden | → `Product Bundle` |
| 68 | `sales_order_packed_item` | Data | `varchar(140)` |  |  |
| 69 | `fg_item` | Link | `varchar(140)` |  | → `Item` |
| 70 | `fg_item_qty` | Float | `numeric(21,9)` | default=1 |  |
| 71 | `from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 72 | `wip_composite_asset` | Link | `varchar(140)` |  | → `Asset` |
| 73 | `job_card` | Link | `varchar(140)` | ro | → `Job Card` |
| 74 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 75 | `subcontracted_qty` | Float | `numeric(21,9)` | ro, default=0 |  |

## Purchase Receipt Item Supplied

- **Table**: `tabPurchase Receipt Item Supplied`  (proposed: `purchase_receipt_item_supplied`)
- **Kind**: Child / line-item table
- **Embedded in**: `Purchase Invoice`.`supplied_items`, `Purchase Receipt`.`supplied_items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `main_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 2 | `rm_item_code` | Link | `varchar(140)` | ro | → `Item` |
| 3 | `description` | Text Editor | `text` | ro |  |
| 4 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 5 | `serial_no` | Text | `text` |  |  |
| 6 | `required_qty` | Float | `numeric(21,9)` | ro |  |
| 7 | `consumed_qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 8 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 9 | `rate` | Currency | `numeric(21,9)` | ro |  |
| 10 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `conversion_factor` | Float | `numeric(21,9)` | ro, hidden |  |
| 12 | `current_stock` | Float | `numeric(21,9)` | ro |  |
| 13 | `reference_name` | Data | `varchar(140)` | ro, hidden |  |
| 14 | `bom_detail_no` | Data | `varchar(140)` | ro, hidden |  |
| 15 | `item_name` | Data | `varchar(140)` | ro |  |
| 16 | `purchase_order` | Link | `varchar(140)` | ro, hidden | → `Purchase Order` |

## Request for Quotation Item

- **Table**: `tabRequest for Quotation Item`  (proposed: `request_for_quotation_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Embedded in**: `Request for Quotation`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `supplier_part_no` | Data | `varchar(140)` | ro, hidden |  |
| 3 | `item_name` | Data | `varchar(140)` | INDEX |  |
| 4 | `description` | Text Editor | `text` |  |  |
| 5 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 6 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 7 | `schedule_date` | Date | `date` | NOT NULL, default=Today |  |
| 8 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 9 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 10 | `project_name` | Link | `varchar(140)` |  | → `Project` |
| 11 | `material_request` | Link | `varchar(140)` | ro | → `Material Request` |
| 12 | `material_request_item` | Data | `varchar(140)` | hidden |  |
| 13 | `brand` | Link | `varchar(140)` | ro | → `Brand` |
| 14 | `item_group` | Link | `varchar(140)` | ro | → `Item Group` |
| 15 | `page_break` | Check | `smallint` | default=0 |  |
| 16 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 17 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 18 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 19 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |

## Request for Quotation Supplier

- **Table**: `tabRequest for Quotation Supplier`  (proposed: `request_for_quotation_supplier`)
- **Kind**: Child / line-item table
- **Embedded in**: `Request for Quotation`.`suppliers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `send_email` | Check | `smallint` | default=1 |  |
| 2 | `email_sent` | Check | `smallint` | ro, default=0 |  |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL | → `Supplier` |
| 4 | `contact` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 5 | `quote_status` | Select | `varchar(140)` | ro | enum: Pending, Received |
| 6 | `supplier_name` | Read Only | `varchar(140)` | denorm←supplier.supplier_name |  |
| 7 | `email_id` | Data | `varchar(140)` | denorm←contact.email_id |  |

## Supplier Quotation Item

- **Table**: `tabSupplier Quotation Item`  (proposed: `supplier_quotation_item`)
- **Kind**: Child / line-item table
- **Naming**: `hash`  (Random)
- **Embedded in**: `Supplier Quotation`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | NOT NULL, INDEX | → `Item` |
| 2 | `supplier_part_no` | Data | `varchar(140)` | ro, hidden |  |
| 3 | `item_name` | Data | `varchar(140)` | INDEX |  |
| 4 | `lead_time_days` | Int | `integer` |  |  |
| 5 | `description` | Text Editor | `text` |  |  |
| 6 | `image` | Attach | `text` | hidden |  |
| 7 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 8 | `stock_uom` | Link | `varchar(140)` | NOT NULL, ro | → `UOM` |
| 9 | `price_list_rate` | Currency | `numeric(21,9)` |  |  |
| 10 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 11 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 12 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 13 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 14 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 15 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `rate` | Currency | `numeric(21,9)` |  |  |
| 17 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 18 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 19 | `base_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 20 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 21 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 22 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 23 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 24 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 25 | `weight_per_unit` | Float | `numeric(21,9)` | ro |  |
| 26 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 27 | `weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 28 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 29 | `project` | Link | `varchar(140)` |  | → `Project` |
| 30 | `prevdoc_doctype` | Data | `varchar(140)` | ro, hidden |  |
| 31 | `material_request` | Link | `varchar(140)` | INDEX, ro | → `Material Request` |
| 32 | `sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 33 | `request_for_quotation` | Link | `varchar(140)` | ro | → `Request for Quotation` |
| 34 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 35 | `material_request_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 36 | `request_for_quotation_item` | Data | `varchar(140)` | ro, hidden |  |
| 37 | `brand` | Link | `varchar(140)` | ro | → `Brand` |
| 38 | `item_group` | Link | `varchar(140)` | ro | → `Item Group` |
| 39 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 40 | `page_break` | Check | `smallint` | default=0 |  |
| 41 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 42 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 43 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 44 | `expected_delivery_date` | Date | `date` |  |  |
| 45 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 46 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 47 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 48 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 49 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |

## Supplier Scorecard Scoring Criteria

- **Table**: `tabSupplier Scorecard Scoring Criteria`  (proposed: `supplier_scorecard_scoring_criteria`)
- **Kind**: Child / line-item table
- **Embedded in**: `Supplier Scorecard`.`criteria`, `Supplier Scorecard Period`.`criteria`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `criteria_name` | Link | `varchar(140)` | NOT NULL | → `Supplier Scorecard Criteria` |
| 2 | `score` | Percent | `numeric(21,9)` | ro, hidden |  |
| 3 | `weight` | Percent | `numeric(21,9)` | NOT NULL |  |
| 4 | `max_score` | Float | `numeric(21,9)` | ro, hidden, default=100 |  |
| 5 | `formula` | Small Text | `text` | ro, hidden |  |

## Supplier Scorecard Scoring Standing

- **Table**: `tabSupplier Scorecard Scoring Standing`  (proposed: `supplier_scorecard_scoring_standing`)
- **Kind**: Child / line-item table
- **Embedded in**: `Supplier Scorecard`.`standings`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `standing_name` | Link | `varchar(140)` |  | → `Supplier Scorecard Standing` |
| 2 | `standing_color` | Select | `varchar(140)` |  | enum: Blue, Purple, Green, Yellow, Orange, Red |
| 3 | `min_grade` | Percent | `numeric(21,9)` |  |  |
| 4 | `max_grade` | Percent | `numeric(21,9)` |  |  |
| 5 | `warn_rfqs` | Check | `smallint` | default=0 |  |
| 6 | `warn_pos` | Check | `smallint` | default=0 |  |
| 7 | `prevent_rfqs` | Check | `smallint` | default=0 |  |
| 8 | `prevent_pos` | Check | `smallint` | default=0 |  |
| 9 | `notify_supplier` | Check | `smallint` | hidden, default=0 |  |
| 10 | `notify_employee` | Check | `smallint` | hidden, default=0 |  |
| 11 | `employee_link` | Link | `varchar(140)` | hidden | → `Employee` |

## Supplier Scorecard Scoring Variable

- **Table**: `tabSupplier Scorecard Scoring Variable`  (proposed: `supplier_scorecard_scoring_variable`)
- **Kind**: Child / line-item table
- **Embedded in**: `Supplier Scorecard Period`.`variables`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `variable_label` | Link | `varchar(140)` | NOT NULL, ro | → `Supplier Scorecard Variable` |
| 2 | `description` | Small Text | `text` | ro |  |
| 3 | `value` | Float | `numeric(21,9)` | ro |  |
| 4 | `param_name` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `path` | Data | `varchar(140)` | ro, hidden |  |
