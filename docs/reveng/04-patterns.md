# Cross-cutting schema patterns (auto-derived)

Scope: Accounts, Selling, Buying, Stock, Subcontracting, Setup.

## 1. Child tables shared by several parents

ERPNext reuses one physical child table across many parent DocTypes and tells them
apart with `parenttype`. This is why the framework cannot use real foreign keys.
42 child tables have more than one parent.

| Child table | Parents | Used by |
|---|--:|---|
| `Item Wise Tax Detail` | 9 | `POS Invoice`.`item_wise_tax_details`, `Purchase Invoice`.`item_wise_tax_details`, `Sales Invoice`.`item_wise_tax_details`, `Purchase Order`.`item_wise_tax_details`, `Supplier Quotation`.`item_wise_tax_details`, `Quotation`.`item_wise_tax_details`, `Sales Order`.`item_wise_tax_details`, `Delivery Note`.`item_wise_tax_details` … (+1) |
| `Pricing Rule Detail` | 9 | `POS Invoice`.`pricing_rules`, `Purchase Invoice`.`pricing_rules`, `Sales Invoice`.`pricing_rules`, `Purchase Order`.`pricing_rules`, `Supplier Quotation`.`pricing_rules`, `Quotation`.`pricing_rules`, `Sales Order`.`pricing_rules`, `Delivery Note`.`pricing_rules` … (+1) |
| `Payment Schedule` | 6 | `POS Invoice`.`payment_schedule`, `Purchase Invoice`.`payment_schedule`, `Sales Invoice`.`payment_schedule`, `Purchase Order`.`payment_schedule`, `Quotation`.`payment_schedule`, `Sales Order`.`payment_schedule` |
| `Sales Taxes and Charges` | 6 | `POS Invoice`.`taxes`, `Sales Invoice`.`taxes`, `Sales Taxes and Charges Template`.`taxes`, `Quotation`.`taxes`, `Sales Order`.`taxes`, `Delivery Note`.`taxes` |
| `Purchase Taxes and Charges` | 5 | `Purchase Invoice`.`taxes`, `Purchase Taxes and Charges Template`.`taxes`, `Purchase Order`.`taxes`, `Supplier Quotation`.`taxes`, `Purchase Receipt`.`taxes` |
| `Sales Team` | 5 | `POS Invoice`.`sales_team`, `Sales Invoice`.`sales_team`, `Customer`.`sales_team`, `Sales Order`.`sales_team`, `Delivery Note`.`sales_team` |
| `Packed Item` | 5 | `POS Invoice`.`packed_items`, `Sales Invoice`.`packed_items`, `Quotation`.`packed_items`, `Sales Order`.`packed_items`, `Delivery Note`.`packed_items` |
| `Party Account` | 4 | `Supplier`.`accounts`, `Customer`.`accounts`, `Customer Group`.`accounts`, `Supplier Group`.`accounts` |
| `Tax Withholding Entry` | 4 | `Journal Entry`.`tax_withholding_entries`, `Payment Entry`.`tax_withholding_entries`, `Purchase Invoice`.`tax_withholding_entries`, `Sales Invoice`.`tax_withholding_entries` |
| `Landed Cost Taxes and Charges` | 4 | `Landed Cost Voucher`.`taxes`, `Stock Entry`.`additional_costs`, `Subcontracting Order`.`additional_costs`, `Subcontracting Receipt`.`additional_costs` |
| `CRM Note` | 3 | `Lead`.`notes`, `Opportunity`.`notes`, `Prospect`.`notes` |
| `Target Detail` | 3 | `Sales Partner`.`targets`, `Sales Person`.`targets`, `Territory`.`targets` |
| `Company Restriction` | 3 | `Supplier`.`allowed_companies`, `Customer`.`allowed_companies`, `Item`.`allowed_companies` |
| `Item Default` | 3 | `Brand`.`brand_defaults`, `Item Group`.`item_group_defaults`, `Item`.`item_defaults` |
| `Allowed To Transact With` | 2 | `Supplier`.`companies`, `Customer`.`companies` |
| `POS Invoice Reference` | 2 | `POS Closing Entry`.`pos_invoices`, `POS Invoice Merge Log`.`pos_invoices` |
| `Pricing Rule Brand` | 2 | `Pricing Rule`.`brands`, `Promotional Scheme`.`brands` |
| `Pricing Rule Item Code` | 2 | `Pricing Rule`.`items`, `Promotional Scheme`.`items` |
| `Pricing Rule Item Group` | 2 | `Pricing Rule`.`item_groups`, `Promotional Scheme`.`item_groups` |
| `Process Period Closing Voucher Detail` | 2 | `Process Period Closing Voucher`.`normal_balances`, `Process Period Closing Voucher`.`z_opening_balances` |
| `Sales Invoice Advance` | 2 | `POS Invoice`.`advances`, `Sales Invoice`.`advances` |
| `Sales Invoice Payment` | 2 | `POS Invoice`.`payments`, `Sales Invoice`.`payments` |
| `Sales Invoice Timesheet` | 2 | `POS Invoice`.`timesheets`, `Sales Invoice`.`timesheets` |
| `Subscription Plan Detail` | 2 | `Payment Request`.`subscription_plans`, `Subscription`.`plans` |
| `Asset Finance Book` | 2 | `Asset`.`finance_books`, `Asset Category`.`finance_books` |
| `Depreciation Schedule` | 2 | `Asset Depreciation Schedule`.`depreciation_schedule`, `Asset Shift Allocation`.`depreciation_schedule` |
| `Purchase Receipt Item Supplied` | 2 | `Purchase Invoice`.`supplied_items`, `Purchase Receipt`.`supplied_items` |
| `Supplier Scorecard Scoring Criteria` | 2 | `Supplier Scorecard`.`criteria`, `Supplier Scorecard Period`.`criteria` |
| `Competitor Detail` | 2 | `Opportunity`.`competitors`, `Quotation`.`competitors` |
| `BOM Operation` | 2 | `BOM`.`operations`, `Routing`.`operations` |
| `Job Card Time Log` | 2 | `Job Card`.`time_logs`, `Job Card`.`employee` |
| `Master Production Schedule Item` | 2 | `Master Production Schedule`.`items`, `Master Production Schedule`.`select_items` |
| `Production Plan Material Request` | 2 | `Master Production Schedule`.`material_requests`, `Production Plan`.`material_requests` |
| `Production Plan Sales Order` | 2 | `Master Production Schedule`.`sales_orders`, `Production Plan`.`sales_orders` |
| `Sales Forecast Item` | 2 | `Sales Forecast`.`selected_items`, `Sales Forecast`.`items` |
| `Work Order Additional Item` | 2 | `Work Order`.`non_stock_items`, `Work Order`.`secondary_items` |
| `Workstation Cost` | 2 | `Workstation`.`workstation_costs`, `Workstation Type`.`workstation_costs` |
| `Project User` | 2 | `Project`.`users`, `Project Update`.`users` |
| `Customer Credit Limit` | 2 | `Customer`.`credit_limits`, `Customer Group`.`credit_limits` |
| `Item Tax` | 2 | `Item Group`.`taxes`, `Item`.`taxes` |

**Decision for our schema:** one table per (parent, field) with a real FK, or a single
table plus a discriminator only where the rows are genuinely interchangeable.

## 2. Polymorphic (`Dynamic Link`) column pairs

A `Dynamic Link` column holds the target row's key while a sibling column holds the
target *table* name. This is how ERPNext models 'a party is a Customer or a Supplier'
and 'this ledger row came from some voucher'.

| Discriminator column | Value column | Occurrences | Example tables |
|---|---|--:|---|
| `party_type` | `party` | 17 | `Bank Account`, `Bank Transaction`, `Bank Transaction Rule`, `Bank Transaction Rule Accounts`, `Exchange Rate Revaluation Account` |
| `voucher_type` | `voucher_no` | 10 | `Advance Payment Ledger Entry`, `GL Entry`, `Payment Ledger Entry`, `Repost Accounting Ledger Items`, `Repost Item Valuation` |
| `reference_type` | `reference_name` | 7 | `Journal Entry Account`, `Payment Reconciliation Allocation`, `Payment Reconciliation Payment`, `Process Payment Reconciliation Log Allocations`, `Purchase Invoice Advance` |
| `reference_doctype` | `reference_name` | 7 | `Asset Movement`, `Batch`, `Payment Entry Reference`, `Payment Order Reference`, `Payment Request` |
| `invoice_type` | `invoice_number` | 3 | `Payment Reconciliation Allocation`, `Payment Reconciliation Invoice`, `Process Payment Reconciliation Log Allocations` |
| `document_type` | `document_name` | 3 | `Contract`, `Quality Feedback`, `Quality Meeting Minutes` |
| `against_voucher_type` | `against_voucher_no` | 2 | `Advance Payment Ledger Entry`, `Payment Ledger Entry` |
| `payment_document` | `payment_entry` | 2 | `Bank Clearance Detail`, `Bank Transaction Payments` |
| `advance_voucher_type` | `advance_voucher_no` | 2 | `Journal Entry Account`, `Payment Entry Reference` |
| `prevdoc_doctype` | `prevdoc_docname` | 2 | `Maintenance Visit Purpose`, `Quotation Item` |
| `receipt_document_type` | `receipt_document` | 2 | `Landed Cost Item`, `Landed Cost Purchase Receipt` |
| `reference_document` | `default_dimension` | 1 | `Accounting Dimension Detail` |
| `accounting_dimension` | `dimension_value` | 1 | `Allowed Dimension` |
| `reference_doctype` | `reference_docname` | 1 | `Bank Guarantee` |
| `against_voucher_type` | `against_voucher` | 1 | `GL Entry` |
| `invoice_type` | `invoice` | 1 | `Loyalty Point Entry` |
| `primary_role` | `primary_party` | 1 | `Party Link` |
| `secondary_role` | `secondary_party` | 1 | `Party Link` |
| `customer_collection` | `collection_name` | 1 | `Process Statement Of Accounts` |
| `document_type` | `invoice` | 1 | `Subscription Invoice` |
| `withholding_doctype` | `withholding_name` | 1 | `Tax Withholding Entry` |
| `taxable_doctype` | `taxable_name` | 1 | `Tax Withholding Entry` |
| `from_doctype` | `transaction_name` | 1 | `Bulk Transaction Log Detail` |
| `appointment_with` | `party` | 1 | `Appointment` |
| `party_type` | `party_name` | 1 | `Contract` |
| `email_campaign_for` | `recipient` | 1 | `Email Campaign` |
| `opportunity_from` | `party_name` | 1 | `Opportunity` |
| `restrict_based_on` | `based_on_value` | 1 | `Party Specific Item` |
| `quotation_to` | `party_name` | 1 | `Quotation` |
| `customer_or_item` | `master_name` | 1 | `Authorization Rule` |

**Decision for our schema:** the `party_type`/`party` pair is a genuine supertype
(introduce a `party` table that `customer` and `supplier` extend). The
`voucher_type`/`voucher_no` pair on ledger rows is an audit back-pointer; keep it as a
(table_name, row_id) pair but *also* store a typed FK to the specific document type.

## 3. Denormalised (`fetch_from`) columns

239 columns in scope are copies of a value owned by another table, snapshotted at
save time. Some are deliberate history (a price at the time of sale); many are pure
read convenience.

| Table | Copied columns | Examples |
|---|--:|---|
| `Payment Terms Template Detail` | 10 | `description`, `invoice_portion`, `due_date_based_on`, `credit_days`, `credit_months`, `mode_of_payment`, `discount_type`, `discount` |
| `Payment Request` | 9 | `bank`, `bank_account_no`, `account`, `iban`, `branch_code`, `swift_number`, `payment_gateway`, `payment_account` |
| `Sales Invoice` | 8 | `customer_name`, `tax_id`, `loyalty_program`, `language`, `commission_rate`, `is_internal_customer`, `company_tax_id`, `represents_company` |
| `Delivery Note` | 7 | `customer_name`, `transporter_name`, `driver_name`, `language`, `commission_rate`, `is_internal_customer`, `represents_company` |
| `Payment Entry` | 6 | `bank`, `bank_account_no`, `paid_from_account_type`, `paid_to_account_type`, `book_advance_payments_in_separate_party_account`, `reconcile_on_advance_payment_date` |
| `Sales Order` | 6 | `customer_name`, `tax_id`, `language`, `commission_rate`, `is_internal_customer`, `represents_company` |
| `Purchase Receipt Item` | 6 | `image`, `retain_sample`, `sample_quantity`, `brand`, `item_group`, `asset_category` |
| `Subcontracting Order` | 6 | `supplier_name`, `transaction_date`, `schedule_date`, `supplier_address`, `contact_person`, `supplier_currency` |
| `Dunning` | 5 | `customer_name`, `dunning_fee`, `rate_of_interest`, `income_account`, `cost_center` |
| `POS Invoice Reference` | 5 | `customer`, `posting_date`, `grand_total`, `is_return`, `return_against` |
| `Purchase Invoice` | 5 | `supplier_name`, `tax_id`, `is_internal_supplier`, `represents_company`, `supplier_group` |
| `Purchase Invoice Item` | 5 | `item_name`, `image`, `item_group`, `is_fixed_asset`, `asset_category` |
| `Subcontracting Order Item` | 5 | `item_name`, `description`, `image`, `rate`, `bom` |
| `Subcontracting Receipt Item` | 5 | `item_name`, `description`, `image`, `stock_uom`, `brand` |
| `Discounted Invoice` | 4 | `customer`, `posting_date`, `outstanding_amount`, `debit_to` |
| `POS Closing Entry` | 4 | `period_start_date`, `company`, `pos_profile`, `user` |
| `Payment Schedule` | 4 | `description`, `outstanding`, `discount_type`, `discount` |
| `Sales Invoice Reference` | 4 | `customer`, `is_return`, `return_against`, `grand_total` |
| `Customer` | 4 | `mobile_no`, `email_id`, `first_name`, `last_name` |
| `Proforma Invoice` | 4 | `customer`, `customer_name`, `company`, `currency` |
| `Serial and Batch Bundle` | 4 | `item_group`, `has_serial_no`, `item_name`, `has_batch_no` |
| `POS Invoice` | 3 | `customer_name`, `loyalty_program`, `commission_rate` |
| `Purchase Order` | 3 | `supplier_name`, `is_internal_supplier`, `represents_company` |
| `Sales Order Item` | 3 | `image`, `grant_commission`, `is_stock_item` |
| `Delivery Trip` | 3 | `driver_name`, `driver_address`, `employee` |

**Decision for our schema:** keep the snapshot only where the value must survive later
master edits (rates, tax %, addresses printed on a document). Everything else becomes a
join or a view.

## 4. Identifier / naming strategies in use

| Strategy | Tables | Example |
|---|--:|---|
| child table (framework hash) | 169 | `Accounting Dimension Detail`, `Advance Taxes and Charges`, `Allowed Dimension`, `Allowed To Transact With`, `Applicable On Account`, `Bank Clearance Detail` |
| value of one field | 61 | `Account Category`, `Accounting Dimension`, `Accounting Period`, `Bank`, `Bank Account Subtype`, `Bank Account Type` |
| set by controller code | 49 | `Account`, `Account Closing Balance`, `Accounts Settings`, `Advance Payment Ledger Entry`, `Authorization Control`, `Bank Account` |
| naming series column | 39 | `Bank Transaction`, `Budget`, `Cashier Closing`, `Customer`, `Delivery Note`, `Delivery Trip` |
| inline series expression | 21 | `Authorization Rule`, `Bank Guarantee`, `Cost Center Allocation`, `Exchange Rate Revaluation`, `GL Entry`, `Invoice Discounting` |
| format string | 7 | `Accounting Dimension Filter`, `Bank Statement Import`, `Ledger Merge`, `Process Payment Reconciliation`, `Process Payment Reconciliation Log`, `Process Period Closing Voucher` |
| user supplied | 7 | `Email Digest`, `POS Profile`, `Process Statement Of Accounts`, `Promotional Scheme`, `Stock Entry Type`, `Tax Withholding Category` |
| random hash | 5 | `Bank Statement Import Log`, `Bin`, `Item Price`, `Repost Item Valuation`, `Serial and Batch Bundle` |
| autoincrement | 2 | `Bisect Nodes`, `Ledger Health` |

Series expressions found (these encode fiscal period into the key, so the key is not
stable across companies or years):

- `ACC-BG-.YYYY.-.#####`
- `ACC-ERR-.YYYY.-.#####`
- `ACC-GLE-.YYYY.-.#####`
- `ACC-INV-DISC-.YYYY.-.#####`
- `ACC-PCV-.YYYY.-.#####`
- `ACC-PDA-.#####`
- `ACC-PT-LNK-.###.`
- `ACC-SHT-.YYYY.-.#####`
- `ACC-SUB-.YYYY.-.#####`
- `ACC-TAX-RULE-.YYYY.-.#####`
- `CC-ALLOC-.#####`
- `HR-ARU-.#####`
- `MAT-PAC-.YYYY.-.#####`
- `MAT-SLE-.YYYY.-.#####`
- `MAT-SRE-.YYYY.-.#####`
- `MAT-UOM-CNV-.#####`
- `POS-CLO-.YYYY.-.#####`
- `POS-OPE-.YYYY.-.#####`
- `PUT-.####`
- `SHIPMENT-.#####`
- `TDL.####`

**Decision for our schema:** surrogate `bigint` PK everywhere; the human document number
becomes `doc_no` with a `UNIQUE (company_id, doc_type, doc_no)` constraint and a proper
sequence table so numbering gaps and concurrency are explicit.

## 5. Multi-currency column triplets

ERPNext stores most amounts three times: transaction currency, company base currency
(`base_*`) and sometimes account currency. `numeric(21,9)` throughout.

| Table | Currency columns | of which `base_*` |
|---|--:|--:|
| `POS Invoice` | 26 | 10 |
| `Sales Invoice` | 26 | 10 |
| `Purchase Invoice` | 25 | 11 |
| `Purchase Receipt Item` | 22 | 6 |
| `Purchase Invoice Item` | 20 | 6 |
| `Purchase Order` | 19 | 9 |
| `Sales Order Item` | 19 | 6 |
| `Purchase Order Item` | 18 | 6 |
| `Supplier Quotation` | 18 | 9 |
| `Quotation Item` | 18 | 6 |
| `Sales Order` | 18 | 7 |
| `Purchase Receipt` | 18 | 9 |
| `Delivery Note Item` | 17 | 6 |
| `Sales Invoice Item` | 16 | 6 |
| `Delivery Note` | 16 | 7 |
| `POS Invoice Item` | 14 | 6 |
| `Payment Entry` | 14 | 6 |
| `Quotation` | 14 | 7 |
| `Supplier Quotation Item` | 13 | 5 |
| `GL Entry` | 8 | 0 |

**Decision for our schema:** store amount + currency + the exchange rate used, and derive
base amounts in generated columns or views so the two can never drift.

## 6. Hierarchies (nested sets)

14 tree masters app-wide, each carrying `lft`, `rgt`, `old_parent` plus a
self-referencing `parent_*` link and an `is_group` flag.

| Table | Module | Parent column |
|---|---|---|
| `Account` | Accounts | `parent_account` |
| `Cost Center` | Accounts | `parent_cost_center` |
| `Location` | Assets | `parent_location` |
| `Task` | Projects | `parent_task` |
| `Quality Procedure` | Quality Management | `parent_quality_procedure` |
| `Company` | Setup | `parent_company` |
| `Customer Group` | Setup | `parent_customer_group` |
| `Department` | Setup | `parent_department` |
| `Employee` | Setup | `reports_to` |
| `Item Group` | Setup | `parent_item_group` |
| `Sales Person` | Setup | `parent_sales_person` |
| `Supplier Group` | Setup | `parent_supplier_group` |
| `Territory` | Setup | `parent_territory` |
| `Warehouse` | Stock | `parent_warehouse` |

**Decision for our schema:** `parent_id` FK + recursive CTEs (or a closure table for
read-heavy reporting). Nested sets make every insert lock the whole tree.
