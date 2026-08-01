# Module deep dive: Setup

Shared masters that the trade and accounting modules depend on but do not own:
`Company` (the tenant/legal entity boundary of the whole ledger), `UOM` +
`UOM Conversion Factor`, the classification trees (`Item Group`, `Customer Group`,
`Supplier Group`, `Territory`, `Sales Person`), `Currency Exchange`, `Incoterm`,
`Terms and Conditions` and `Party Type`. Included here because no trade table can be
designed without them.

40 DocTypes / 405 columns.

## Contents

**Single (settings)** (2): [Authorization Control](#authorization-control), [Global Defaults](#global-defaults)

**Master** (17): [Authorization Rule](#authorization-rule), [Branch](#branch), [Brand](#brand), [Currency Exchange](#currency-exchange), [Designation](#designation), [Driver](#driver), [Email Digest](#email-digest), [Employee Group](#employee-group), [Holiday List](#holiday-list), [Incoterm](#incoterm), [Party Type](#party-type), [Quotation Lost Reason](#quotation-lost-reason), [Sales Partner](#sales-partner), [Terms and Conditions](#terms-and-conditions), [UOM](#uom), [UOM Conversion Factor](#uom-conversion-factor), [Vehicle](#vehicle)

**Tree master (hierarchy)** (8): [Company](#company), [Customer Group](#customer-group), [Department](#department), [Employee](#employee), [Item Group](#item-group), [Sales Person](#sales-person), [Supplier Group](#supplier-group), [Territory](#territory)

**Transaction (submittable)** (1): [Transaction Deletion Record](#transaction-deletion-record)

**Child / line-item table** (12): [Driving License Category](#driving-license-category), [Email Digest Recipient](#email-digest-recipient), [Employee Education](#employee-education), [Employee External Work History](#employee-external-work-history), [Employee Group Table](#employee-group-table), [Employee Internal Work History](#employee-internal-work-history), [Holiday](#holiday), [Quotation Lost Reason Detail](#quotation-lost-reason-detail), [Target Detail](#target-detail), [Transaction Deletion Record Item](#transaction-deletion-record-item), [Transaction Deletion Record To Delete](#transaction-deletion-record-to-delete), [Website Item Group](#website-item-group)

---

# Single (settings)s

## Authorization Control

- **Table**: `tabAuthorization Control`  (proposed: `authorization_control`)
- **Kind**: Single (settings)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|

## Global Defaults

- **Table**: `tabGlobal Defaults`  (proposed: `global_defaults`)
- **Kind**: Single (settings)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `default_company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `country` | Link | `varchar(140)` |  | → `Country` *(frappe core)* |
| 3 | `default_distance_unit` | Link | `varchar(140)` |  | → `UOM` |
| 4 | `default_currency` | Link | `varchar(140)` | NOT NULL, default=INR | → `Currency` *(frappe core)* |
| 5 | `hide_currency_symbol` | Check | `smallint` | default=0 |  |
| 6 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 7 | `disable_in_words` | Check | `smallint` | default=0 |  |
| 8 | `demo_company` | Link | `varchar(140)` | ro, hidden | → `Company` |
| 9 | `use_posting_datetime_for_naming_documents` | Check | `smallint` | default=1 |  |

---

# Masters

## Authorization Rule

- **Table**: `tabAuthorization Rule`  (proposed: `authorization_rule`)
- **Kind**: Master
- **Naming**: `HR-ARU-.#####`  (Expression (old style))
- **Search fields**: `transaction,based_on,system_user,system_role,approving_user,approving_role`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `transaction` | Select | `varchar(140)` | NOT NULL | enum: Sales Order, Purchase Order, Quotation, Delivery Note, Sales Invoice, Purchase Invoice, Purchase Receipt |
| 2 | `based_on` | Select | `varchar(140)` | NOT NULL | enum: Grand Total, Average Discount, Customerwise Discount, Itemwise Discount, Item Group wise Discount, Not Applicable |
| 3 | `customer_or_item` | Select | `varchar(140)` | ro, hidden | enum: Customer, Item, Item Group |
| 4 | `master_name` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `customer_or_item` |
| 5 | `company` | Link | `varchar(140)` |  | → `Company` |
| 6 | `value` | Float | `numeric(21,9)` |  |  |
| 7 | `system_role` | Link | `varchar(140)` |  | → `Role` *(frappe core)* |
| 8 | `to_emp` | Link | `varchar(140)` |  | → `Employee` |
| 9 | `system_user` | Link | `varchar(140)` |  | → `User` *(frappe core)* |
| 10 | `to_designation` | Link | `varchar(140)` |  | → `Designation` |
| 11 | `approving_role` | Link | `varchar(140)` |  | → `Role` *(frappe core)* |
| 12 | `approving_user` | Link | `varchar(140)` |  | → `User` *(frappe core)* |

**Polymorphic references:**

- `master_name` — target DocType read from `customer_or_item`

## Branch

- **Table**: `tabBranch`  (proposed: `branch`)
- **Kind**: Master
- **Naming**: `field:branch`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `branch` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (3):** `SMS Center`.`branch`, `Employee`.`branch`, `Employee Internal Work History`.`branch`

## Brand

- **Table**: `tabBrand`  (proposed: `brand`)
- **Kind**: Master
- **Naming**: `field:brand`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `brand` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Text | `text` |  |  |
| 3 | `image` | Attach Image | `text` | hidden |  |

**Child tables (1-N):**

- `brand_defaults` → `Item Default` (line items)

**Referenced by (17):** `Pricing Rule`.`other_brand`, `Pricing Rule Brand`.`brand`, `Promotional Scheme`.`other_brand`, `Purchase Invoice Item`.`brand`, `Purchase Order Item`.`brand`, `Request for Quotation Item`.`brand`, `Supplier Quotation Item`.`brand`, `Opportunity Item`.`brand`, `Quotation Item`.`brand`, `Sales Order Item`.`brand`, `Delivery Note Item`.`brand`, `Item`.`brand`, `Item Price`.`brand`, `Material Request Item`.`brand`, `Purchase Receipt Item`.`brand` … (+2 more)

## Currency Exchange

- **Table**: `tabCurrency Exchange`  (proposed: `currency_exchange`)
- **Kind**: Master
- **Description**: Specify Exchange Rate to convert one currency into another

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `date` | Date | `date` | NOT NULL |  |
| 2 | `from_currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe core)* |
| 3 | `to_currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe core)* |
| 4 | `exchange_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 5 | `for_buying` | Check | `smallint` | default=1 |  |
| 6 | `for_selling` | Check | `smallint` | default=1 |  |

## Designation

- **Table**: `tabDesignation`  (proposed: `designation`)
- **Kind**: Master
- **Naming**: `field:designation_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `designation_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Text | `text` |  |  |

**Referenced by (3):** `Authorization Rule`.`to_designation`, `Employee`.`designation`, `Employee Internal Work History`.`designation`

## Driver

- **Table**: `tabDriver`  (proposed: `driver`)
- **Kind**: Master
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `full_name`
- **Search fields**: `full_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` |  | enum: HR-DRI-.YYYY.- |
| 2 | `full_name` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `status` | Select | `varchar(140)` | NOT NULL | enum: Active, Suspended, Left |
| 4 | `transporter` | Link | `varchar(140)` |  | → `Supplier` |
| 5 | `employee` | Link | `varchar(140)` |  | → `Employee` |
| 6 | `cell_number` | Data | `varchar(140)` |  |  |
| 7 | `license_number` | Data | `varchar(140)` |  |  |
| 8 | `issuing_date` | Date | `date` |  |  |
| 9 | `expiry_date` | Date | `date` |  |  |
| 10 | `address` | Link | `varchar(140)` |  | → `Address` *(frappe core)* |
| 11 | `user` | Link | `varchar(140)` |  | → `User` *(frappe core)* |

**Child tables (1-N):**

- `driving_license_category` → `Driving License Category` (line items)

**Referenced by (2):** `Delivery Note`.`driver`, `Delivery Trip`.`driver`

## Email Digest

- **Table**: `tabEmail Digest`  (proposed: `email_digest`)
- **Kind**: Master
- **Naming**: `Prompt`
- **Description**: Send regular summary reports via Email.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `enabled` | Check | `smallint` | default=0 |  |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `frequency` | Select | `varchar(140)` | NOT NULL | enum: Daily, Weekly, Monthly |
| 4 | `next_send` | Data | `varchar(140)` | ro |  |
| 5 | `income` | Check | `smallint` | default=0 |  |
| 6 | `expenses_booked` | Check | `smallint` | default=0 |  |
| 7 | `income_year_to_date` | Check | `smallint` | default=0 |  |
| 8 | `expense_year_to_date` | Check | `smallint` | default=0 |  |
| 9 | `bank_balance` | Check | `smallint` | default=0 |  |
| 10 | `credit_balance` | Check | `smallint` | default=0 |  |
| 11 | `invoiced_amount` | Check | `smallint` | default=0 |  |
| 12 | `payables` | Check | `smallint` | default=0 |  |
| 13 | `sales_orders_to_bill` | Check | `smallint` | default=0 |  |
| 14 | `purchase_orders_to_bill` | Check | `smallint` | default=0 |  |
| 15 | `sales_order` | Check | `smallint` | default=0 |  |
| 16 | `purchase_order` | Check | `smallint` | default=0 |  |
| 17 | `sales_orders_to_deliver` | Check | `smallint` | default=0 |  |
| 18 | `purchase_orders_to_receive` | Check | `smallint` | default=0 |  |
| 19 | `sales_invoice` | Check | `smallint` | default=0 |  |
| 20 | `purchase_invoice` | Check | `smallint` | default=0 |  |
| 21 | `new_quotations` | Check | `smallint` | default=0 |  |
| 22 | `pending_quotations` | Check | `smallint` | default=0 |  |
| 23 | `issue` | Check | `smallint` | default=0 |  |
| 24 | `project` | Check | `smallint` | default=0 |  |
| 25 | `purchase_orders_items_overdue` | Check | `smallint` | default=0 |  |
| 26 | `calendar_events` | Check | `smallint` | default=0 |  |
| 27 | `todo_list` | Check | `smallint` | default=0 |  |
| 28 | `notifications` | Check | `smallint` | default=0 |  |
| 29 | `add_quote` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `recipients` → `Email Digest Recipient` (multi-select)

## Employee Group

- **Table**: `tabEmployee Group`  (proposed: `employee_group`)
- **Kind**: Master
- **Naming**: `field:employee_group_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `employee_group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Child tables (1-N):**

- `employee_list` → `Employee Group Table` (line items)

**Referenced by (3):** `Communication Medium`.`catch_all`, `Communication Medium Timeslot`.`employee_group`, `Incoming Call Handling Schedule`.`agent_group`

## Holiday List

- **Table**: `tabHoliday List`  (proposed: `holiday_list`)
- **Kind**: Master
- **Naming**: `field:holiday_list_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `holiday_list_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `from_date` | Date | `date` | NOT NULL |  |
| 3 | `to_date` | Date | `date` | NOT NULL |  |
| 4 | `total_holidays` | Int | `integer` | ro |  |
| 5 | `weekly_off` | Select | `varchar(140)` |  | enum: Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday |
| 6 | `color` | Color | `varchar(140)` |  |  |
| 7 | `country` | Autocomplete | `varchar(140)` |  |  |
| 8 | `subdivision` | Autocomplete | `varchar(140)` |  |  |
| 9 | `is_half_day` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `holidays` → `Holiday` (line items)

**Referenced by (6):** `Appointment Booking Settings`.`holiday_list`, `Workstation`.`holiday_list`, `Project`.`holiday_list`, `Company`.`default_holiday_list`, `Employee`.`holiday_list`, `Service Level Agreement`.`holiday_list`

## Incoterm

- **Table**: `tabIncoterm`  (proposed: `incoterm`)
- **Kind**: Master
- **Naming**: `field:code`  (By fieldname)
- **Title field**: `title`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `code` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `description` | Long Text | `text` |  |  |

**Referenced by (10):** `Purchase Invoice`.`incoterm`, `Sales Invoice`.`incoterm`, `Purchase Order`.`incoterm`, `Request for Quotation`.`incoterm`, `Supplier Quotation`.`incoterm`, `Quotation`.`incoterm`, `Sales Order`.`incoterm`, `Delivery Note`.`incoterm`, `Purchase Receipt`.`incoterm`, `Shipment`.`incoterm`

## Party Type

- **Table**: `tabParty Type`  (proposed: `party_type`)
- **Kind**: Master
- **Naming**: `field:party_type`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `party_type` | Link | `varchar(140)` | NOT NULL, UNIQUE | → `DocType` *(frappe core)* |
| 2 | `account_type` | Select | `varchar(140)` | NOT NULL | enum: Payable, Receivable |

**Referenced by (1):** `Bank Transaction Rule Accounts`.`party_type`

## Quotation Lost Reason

- **Table**: `tabQuotation Lost Reason`  (proposed: `quotation_lost_reason`)
- **Kind**: Master
- **Naming**: `field:order_lost_reason`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `order_lost_reason` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (1):** `Quotation Lost Reason Detail`.`lost_reason`

## Sales Partner

- **Table**: `tabSales Partner`  (proposed: `sales_partner`)
- **Kind**: Master
- **Naming**: `field:partner_name`
- **Description**: A third party distributor / dealer / commission agent / affiliate / reseller who sells the companies products for a commission.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `partner_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `partner_type` | Link | `varchar(140)` |  | → `Sales Partner Type` |
| 3 | `territory` | Link | `varchar(140)` | NOT NULL | → `Territory` |
| 4 | `commission_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 5 | `show_in_website` | Check | `smallint` | default=0 |  |
| 6 | `referral_code` | Data | `varchar(140)` | UNIQUE |  |
| 7 | `route` | Data | `varchar(140)` | UNIQUE |  |
| 8 | `logo` | Attach | `text` |  |  |
| 9 | `partner_website` | Data | `varchar(140)` |  |  |
| 10 | `introduction` | Text | `text` |  |  |
| 11 | `description` | Text Editor | `text` |  |  |

**Child tables (1-N):**

- `targets` → `Target Detail` (line items)

**Referenced by (10):** `POS Invoice`.`sales_partner`, `Pricing Rule`.`sales_partner`, `Process Statement Of Accounts`.`sales_partner`, `Sales Invoice`.`sales_partner`, `Sales Partner Item`.`sales_partner`, `Customer`.`default_sales_partner`, `Quotation`.`referral_sales_partner`, `SMS Center`.`sales_partner`, `Sales Order`.`sales_partner`, `Delivery Note`.`sales_partner`

## Terms and Conditions

- **Table**: `tabTerms and Conditions`  (proposed: `terms_and_conditions`)
- **Kind**: Master
- **Naming**: `field:title`  (By fieldname)
- **Description**: Standard Terms and Conditions that can be added to Sales and Purchases. Examples: Validity of the offer, Payment Terms, Safety and Usage, etc.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `disabled` | Check | `smallint` | default=0 |  |
| 3 | `terms` | Text Editor | `text` |  |  |
| 4 | `selling` | Check | `smallint` | default=1 |  |
| 5 | `buying` | Check | `smallint` | default=1 |  |
| 6 | `copy_attachments_to_transaction` | Check | `smallint` | default=0 |  |

**Referenced by (16):** `POS Invoice`.`tc_name`, `POS Profile`.`tc_name`, `Process Statement Of Accounts`.`terms_and_conditions`, `Purchase Invoice`.`tc_name`, `Sales Invoice`.`tc_name`, `Purchase Order`.`tc_name`, `Request for Quotation`.`tc_name`, `Supplier Quotation`.`tc_name`, `Blanket Order`.`tc_name`, `Quotation`.`tc_name`, `Sales Order`.`tc_name`, `Company`.`default_selling_terms`, `Company`.`default_buying_terms`, `Delivery Note`.`tc_name`, `Material Request`.`tc_name` … (+1 more)

## UOM

- **Table**: `tabUOM`  (proposed: `uom`)
- **Kind**: Master
- **Naming**: `field:uom_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `uom_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `must_be_whole_number` | Check | `smallint` | default=0 |  |
| 3 | `enabled` | Check | `smallint` | default=1 |  |
| 4 | `symbol` | Data | `varchar(140)` |  |  |
| 5 | `common_code` | Data | `varchar(140)` |  |  |
| 6 | `description` | Small Text | `text` |  |  |
| 7 | `category` | Link | `varchar(140)` |  | → `UOM Category` |

**Referenced by (110):** `POS Invoice Item`.`stock_uom`, `POS Invoice Item`.`uom`, `POS Invoice Item`.`weight_uom`, `Pricing Rule`.`free_item_uom`, `Pricing Rule Brand`.`uom`, `Pricing Rule Item Code`.`uom`, `Pricing Rule Item Group`.`uom`, `Promotional Scheme Product Discount`.`free_item_uom`, `Purchase Invoice Item`.`stock_uom`, `Purchase Invoice Item`.`uom`, `Purchase Invoice Item`.`weight_uom`, `Sales Invoice Item`.`stock_uom`, `Sales Invoice Item`.`uom`, `Sales Invoice Item`.`weight_uom`, `Asset Capitalization Service Item`.`uom` … (+95 more)

## UOM Conversion Factor

- **Table**: `tabUOM Conversion Factor`  (proposed: `uom_conversion_factor`)
- **Kind**: Master
- **Naming**: `MAT-UOM-CNV-.#####`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `category` | Link | `varchar(140)` | NOT NULL | → `UOM Category` |
| 2 | `from_uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 3 | `to_uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 4 | `value` | Float | `numeric(21,9)` | NOT NULL |  |

## Vehicle

- **Table**: `tabVehicle`  (proposed: `vehicle`)
- **Kind**: Master
- **Naming**: `field:license_plate`  (By fieldname)
- **Search fields**: `license_plate,location,model`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `license_plate` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `make` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `model` | Data | `varchar(140)` | NOT NULL |  |
| 4 | `last_odometer` | Int | `integer` | NOT NULL |  |
| 5 | `acquisition_date` | Date | `date` |  |  |
| 6 | `location` | Data | `varchar(140)` |  |  |
| 7 | `chassis_no` | Data | `varchar(140)` |  |  |
| 8 | `vehicle_value` | Currency | `numeric(21,9)` |  |  |
| 9 | `employee` | Link | `varchar(140)` |  | → `Employee` |
| 10 | `insurance_company` | Data | `varchar(140)` |  |  |
| 11 | `policy_no` | Data | `varchar(140)` |  |  |
| 12 | `start_date` | Date | `date` |  |  |
| 13 | `end_date` | Date | `date` |  |  |
| 14 | `fuel_type` | Select | `varchar(140)` | NOT NULL | enum: Petrol, Diesel, Natural Gas, Electric |
| 15 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 16 | `carbon_check_date` | Date | `date` |  |  |
| 17 | `color` | Data | `varchar(140)` |  |  |
| 18 | `wheels` | Int | `integer` |  |  |
| 19 | `doors` | Int | `integer` |  |  |
| 20 | `amended_from` | Link | `varchar(140)` | ro | → `Vehicle` |
| 21 | `company` | Link | `varchar(140)` |  | → `Company` |

**Referenced by (2):** `Vehicle`.`amended_from`, `Delivery Trip`.`vehicle`

---

# Tree master (hierarchy)s

## Company

- **Table**: `tabCompany`  (proposed: `company`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:company_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: Legal Entity / Subsidiary with a separate Chart of Accounts belonging to the Organization.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `abbr` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `default_finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 5 | `domain` | Data | `varchar(140)` |  |  |
| 6 | `parent_company` | Link | `varchar(140)` |  | → `Company` |
| 7 | `company_logo` | Attach Image | `text` | hidden |  |
| 8 | `company_description` | Text Editor | `text` |  |  |
| 9 | `sales_monthly_history` | Small Text | `text` | ro, hidden |  |
| 10 | `transactions_annual_history` | Code | `text` | ro, hidden |  |
| 11 | `monthly_sales_target` | Currency | `numeric(21,9)` |  |  |
| 12 | `total_monthly_sales` | Currency | `numeric(21,9)` | ro |  |
| 13 | `default_currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe core)* |
| 14 | `default_letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 15 | `default_holiday_list` | Link | `varchar(140)` |  | → `Holiday List` |
| 16 | `default_warehouse_for_sales_return` | Link | `varchar(140)` |  | → `Warehouse` |
| 17 | `country` | Link | `varchar(140)` | NOT NULL | → `Country` *(frappe core)* |
| 18 | `create_chart_of_accounts_based_on` | Select | `varchar(140)` |  | enum: Standard Template, Existing Company |
| 19 | `chart_of_accounts` | Select | `varchar(140)` |  |  |
| 20 | `existing_company` | Link | `varchar(140)` |  | → `Company` |
| 21 | `tax_id` | Data | `varchar(140)` |  |  |
| 22 | `date_of_establishment` | Date | `date` |  |  |
| 23 | `default_bank_account` | Link | `varchar(140)` |  | → `Account` |
| 24 | `default_cash_account` | Link | `varchar(140)` |  | → `Account` |
| 25 | `default_receivable_account` | Link | `varchar(140)` |  | → `Account` |
| 26 | `round_off_account` | Link | `varchar(140)` |  | → `Account` |
| 27 | `round_off_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 28 | `write_off_account` | Link | `varchar(140)` |  | → `Account` |
| 29 | `exchange_gain_loss_account` | Link | `varchar(140)` |  | → `Account` |
| 30 | `unrealized_exchange_gain_loss_account` | Link | `varchar(140)` |  | → `Account` |
| 31 | `allow_account_creation_against_child_company` | Check | `smallint` | default=0 |  |
| 32 | `default_payable_account` | Link | `varchar(140)` |  | → `Account` |
| 33 | `default_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 34 | `default_income_account` | Link | `varchar(140)` |  | → `Account` |
| 35 | `default_deferred_revenue_account` | Link | `varchar(140)` |  | → `Account` |
| 36 | `default_deferred_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 37 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 38 | `credit_limit` | Currency | `numeric(21,9)` |  |  |
| 39 | `payment_terms` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 40 | `enable_perpetual_inventory` | Check | `smallint` | default=1 |  |
| 41 | `default_inventory_account` | Link | `varchar(140)` |  | → `Account` |
| 42 | `stock_adjustment_account` | Link | `varchar(140)` |  | → `Account` |
| 43 | `default_purchase_price_variance_account` | Link | `varchar(140)` |  | → `Account` |
| 44 | `default_manufacturing_variance_account` | Link | `varchar(140)` |  | → `Account` |
| 45 | `stock_received_but_not_billed` | Link | `varchar(140)` |  | → `Account` |
| 46 | `accumulated_depreciation_account` | Link | `varchar(140)` |  | → `Account` |
| 47 | `depreciation_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 48 | `series_for_depreciation_entry` | Data | `varchar(140)` |  |  |
| 49 | `disposal_account` | Link | `varchar(140)` |  | → `Account` |
| 50 | `depreciation_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 51 | `capital_work_in_progress_account` | Link | `varchar(140)` |  | → `Account` |
| 52 | `asset_received_but_not_billed` | Link | `varchar(140)` |  | → `Account` |
| 53 | `exception_budget_approver_role` | Link | `varchar(140)` |  | → `Role` *(frappe core)* |
| 54 | `date_of_incorporation` | Date | `date` |  |  |
| 55 | `date_of_commencement` | Date | `date` |  |  |
| 56 | `phone_no` | Data | `varchar(140)` |  |  |
| 57 | `fax` | Data | `varchar(140)` |  |  |
| 58 | `email` | Data | `varchar(140)` |  |  |
| 59 | `website` | Data | `varchar(140)` |  |  |
| 60 | `registration_details` | Code | `text` |  |  |
| 61 | `lft` | Int | `integer` | INDEX, ro, hidden |  |
| 62 | `rgt` | Int | `integer` | INDEX, ro, hidden |  |
| 63 | `old_parent` | Data | `varchar(140)` | ro, hidden |  |
| 64 | `default_selling_terms` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 65 | `default_buying_terms` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 66 | `default_in_transit_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 67 | `default_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 68 | `sample_retention_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 69 | `unrealized_profit_loss_account` | Link | `varchar(140)` |  | → `Account` |
| 70 | `default_discount_account` | Link | `varchar(140)` |  | → `Account` |
| 71 | `enable_provisional_accounting_for_non_stock_items` | Check | `smallint` | default=0 |  |
| 72 | `default_provisional_account` | Link | `varchar(140)` |  | → `Account` |
| 73 | `default_advance_received_account` | Link | `varchar(140)` |  | → `Account` |
| 74 | `default_advance_paid_account` | Link | `varchar(140)` |  | → `Account` |
| 75 | `book_advance_payments_in_separate_party_account` | Check | `smallint` | default=0 |  |
| 76 | `auto_exchange_rate_revaluation` | Check | `smallint` | default=0 |  |
| 77 | `auto_err_frequency` | Select | `varchar(140)` |  | enum: Daily, Weekly, Monthly |
| 78 | `submit_err_jv` | Check | `smallint` | default=0 |  |
| 79 | `reconcile_on_advance_payment_date` | Check | `smallint` | hidden, default=0 |  |
| 80 | `default_operating_cost_account` | Link | `varchar(140)` |  | → `Account` |
| 81 | `round_off_for_opening` | Link | `varchar(140)` |  | → `Account` |
| 82 | `reconciliation_takes_effect_on` | Select | `varchar(140)` | default=Oldest Of Invoice Or Adv | enum: Advance Payment Date, Oldest Of Invoice Or Advance, Reconciliation Date |
| 83 | `reporting_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe core)* |
| 84 | `purchase_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 85 | `purchase_expense_contra_account` | Link | `varchar(140)` |  | → `Account` |
| 86 | `service_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 87 | `expenses_added_to_stock_account` | Link | `varchar(140)` |  | → `Account` |
| 88 | `expenses_added_to_stock_contra_account` | Link | `varchar(140)` |  | → `Account` |
| 89 | `enable_item_wise_inventory_account` | Check | `smallint` | default=0 |  |
| 90 | `valuation_method` | Select | `varchar(140)` | NOT NULL, default=FIFO | enum: FIFO, Moving Average, LIFO |
| 91 | `default_wip_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 92 | `default_fg_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 93 | `default_scrap_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 94 | `default_sales_contact` | Link | `varchar(140)` |  | → `Contact` *(frappe core)* |
| 95 | `accounts_frozen_till_date` | Date | `date` |  |  |
| 96 | `role_allowed_for_frozen_entries` | Link | `varchar(140)` |  | → `Role` *(frappe core)* |
| 97 | `default_letter_head_report` | Link | `varchar(140)` |  | → `Letter Head` *(frappe core)* |
| 98 | `disable_sdbnb_in_sr` | Check | `smallint` | default=0 |  |
| 99 | `stock_delivered_but_not_billed` | Link | `varchar(140)` |  | → `Account` |
| 100 | `enable_stock_delivered_but_not_billed` | Check | `smallint` | default=0 |  |

**Referenced by (156):** `Account`.`company`, `Account Closing Balance`.`company`, `Accounting Dimension Detail`.`company`, `Accounting Dimension Filter`.`company`, `Accounting Period`.`company`, `Advance Payment Ledger Entry`.`company`, `Allowed To Transact With`.`company`, `Bank Account`.`company`, `Bank Account Balance`.`company`, `Bank Reconciliation Tool`.`company`, `Bank Statement Import`.`company`, `Bank Transaction`.`company`, `Bank Transaction Rule`.`company`, `Bisect Accounting Statements`.`company`, `Budget`.`company` … (+141 more)

## Customer Group

- **Table**: `tabCustomer Group`  (proposed: `customer_group`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:customer_group_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Search fields**: `parent_customer_group`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer_group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `parent_customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `default_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 5 | `payment_terms` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 6 | `lft` | Int | `integer` | INDEX, hidden |  |
| 7 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 8 | `old_parent` | Link | `varchar(140)` | hidden | → `Customer Group` |

**Child tables (1-N):**

- `accounts` → `Party Account` (line items)
- `credit_limits` → `Customer Credit Limit` (line items)

**Referenced by (22):** `Customer Group Item`.`customer_group`, `Loyalty Program`.`customer_group`, `POS Customer Group`.`customer_group`, `POS Invoice`.`customer_group`, `POS Invoice Merge Log`.`customer_group`, `Pricing Rule`.`customer_group`, `Sales Invoice`.`customer_group`, `Tax Rule`.`customer_group`, `Opportunity`.`customer_group`, `Prospect`.`customer_group`, `Maintenance Schedule`.`customer_group`, `Maintenance Visit`.`customer_group`, `Customer`.`customer_group`, `Installation Note`.`customer_group`, `Quotation`.`customer_group` … (+7 more)

## Department

- **Table**: `tabDepartment`  (proposed: `department`)
- **Kind**: Tree master (hierarchy)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `department_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `parent_department` | Link | `varchar(140)` |  | → `Department` |
| 3 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 4 | `is_group` | Check | `smallint` | default=0 |  |
| 5 | `disabled` | Check | `smallint` | default=0 |  |
| 6 | `lft` | Int | `integer` | ro, hidden |  |
| 7 | `rgt` | Int | `integer` | ro, hidden |  |
| 8 | `old_parent` | Data | `varchar(140)` | hidden |  |

**Referenced by (10):** `Asset`.`department`, `Activity Cost`.`department`, `Project`.`department`, `Task`.`department`, `Timesheet`.`department`, `SMS Center`.`department`, `Department`.`parent_department`, `Employee`.`department`, `Employee Internal Work History`.`department`, `Sales Person`.`department`

## Employee

- **Table**: `tabEmployee`  (proposed: `employee`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `employee_name`
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Search fields**: `employee_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `employee` | Data | `varchar(140)` | hidden |  |
| 2 | `naming_series` | Select | `varchar(140)` |  | enum: HR-EMP- |
| 3 | `salutation` | Link | `varchar(140)` |  | → `Salutation` *(frappe core)* |
| 4 | `first_name` | Data | `varchar(140)` | NOT NULL |  |
| 5 | `middle_name` | Data | `varchar(140)` |  |  |
| 6 | `last_name` | Data | `varchar(140)` |  |  |
| 7 | `employee_name` | Data | `varchar(140)` | ro |  |
| 8 | `image` | Attach Image | `text` | hidden |  |
| 9 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 10 | `status` | Select | `varchar(140)` | NOT NULL, INDEX, default=Active | enum: Active, Inactive, Suspended, Left |
| 11 | `employee_number` | Data | `varchar(140)` |  |  |
| 12 | `gender` | Link | `varchar(140)` | NOT NULL | → `Gender` *(frappe core)* |
| 13 | `date_of_birth` | Date | `date` | NOT NULL |  |
| 14 | `date_of_joining` | Date | `date` | NOT NULL |  |
| 15 | `emergency_phone_number` | Data | `varchar(140)` |  |  |
| 16 | `person_to_be_contacted` | Data | `varchar(140)` |  |  |
| 17 | `relation` | Data | `varchar(140)` |  |  |
| 18 | `user_id` | Link | `varchar(140)` |  | → `User` *(frappe core)* |
| 19 | `create_user_permission` | Check | `smallint` | default=1 |  |
| 20 | `create_user_automatically` | Check | `smallint` | default=0 |  |
| 21 | `scheduled_confirmation_date` | Date | `date` |  |  |
| 22 | `final_confirmation_date` | Date | `date` |  |  |
| 23 | `contract_end_date` | Date | `date` |  |  |
| 24 | `notice_number_of_days` | Int | `integer` |  |  |
| 25 | `date_of_retirement` | Date | `date` |  |  |
| 26 | `department` | Link | `varchar(140)` |  | → `Department` |
| 27 | `designation` | Link | `varchar(140)` | INDEX | → `Designation` |
| 28 | `reports_to` | Link | `varchar(140)` |  | → `Employee` |
| 29 | `branch` | Link | `varchar(140)` |  | → `Branch` |
| 30 | `holiday_list` | Link | `varchar(140)` |  | → `Holiday List` |
| 31 | `salary_mode` | Select | `varchar(140)` |  | enum: Bank, Cash, Cheque |
| 32 | `bank_name` | Data | `varchar(140)` |  |  |
| 33 | `bank_ac_no` | Data | `varchar(140)` |  |  |
| 34 | `cell_number` | Data | `varchar(140)` |  |  |
| 35 | `prefered_contact_email` | Select | `varchar(140)` |  | enum: Company Email, Personal Email, User ID |
| 36 | `prefered_email` | Data | `varchar(140)` | ro |  |
| 37 | `company_email` | Data | `varchar(140)` |  |  |
| 38 | `personal_email` | Data | `varchar(140)` |  |  |
| 39 | `unsubscribed` | Check | `smallint` | default=0 |  |
| 40 | `permanent_accommodation_type` | Select | `varchar(140)` |  | enum: Rented, Owned |
| 41 | `permanent_address` | Small Text | `text` |  |  |
| 42 | `current_accommodation_type` | Select | `varchar(140)` |  | enum: Rented, Owned |
| 43 | `current_address` | Small Text | `text` |  |  |
| 44 | `bio` | Text Editor | `text` |  |  |
| 45 | `passport_number` | Data | `varchar(140)` |  |  |
| 46 | `date_of_issue` | Date | `date` |  |  |
| 47 | `valid_upto` | Date | `date` |  |  |
| 48 | `place_of_issue` | Data | `varchar(140)` |  |  |
| 49 | `marital_status` | Select | `varchar(140)` |  | enum: Single, Married, Divorced, Widowed |
| 50 | `blood_group` | Select | `varchar(140)` |  | enum: A+, A-, B+, B-, AB+, AB-, O+, O- |
| 51 | `family_background` | Small Text | `text` |  |  |
| 52 | `health_details` | Small Text | `text` |  |  |
| 53 | `resignation_letter_date` | Date | `date` |  |  |
| 54 | `relieving_date` | Date | `date` |  |  |
| 55 | `reason_for_leaving` | Small Text | `text` |  |  |
| 56 | `leave_encashed` | Select | `varchar(140)` |  | enum: Yes, No |
| 57 | `encashment_date` | Date | `date` |  |  |
| 58 | `held_on` | Date | `date` |  |  |
| 59 | `new_workplace` | Data | `varchar(140)` |  |  |
| 60 | `feedback` | Small Text | `text` |  |  |
| 61 | `lft` | Int | `integer` | ro, hidden |  |
| 62 | `rgt` | Int | `integer` | ro, hidden |  |
| 63 | `old_parent` | Data | `varchar(140)` | hidden |  |
| 64 | `attendance_device_id` | Data | `varchar(140)` | UNIQUE |  |
| 65 | `salary_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe core)* |
| 66 | `ctc` | Currency | `numeric(21,9)` |  |  |
| 67 | `iban` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `education` → `Employee Education` (line items)
- `external_work_history` → `Employee External Work History` (line items)
- `internal_work_history` → `Employee Internal Work History` (line items)

**Referenced by (19):** `Asset`.`custodian`, `Asset Movement Item`.`from_employee`, `Asset Movement Item`.`to_employee`, `Supplier Scorecard`.`employee`, `Supplier Scorecard Scoring Standing`.`employee_link`, `Supplier Scorecard Standing`.`employee_link`, `Downtime Entry`.`operator`, `Job Card Time Log`.`employee`, `Activity Cost`.`employee`, `Timesheet`.`employee`, `Authorization Rule`.`to_emp`, `Driver`.`employee`, `Employee`.`reports_to`, `Employee Group Table`.`employee`, `Sales Person`.`employee` … (+4 more)

## Item Group

- **Table**: `tabItem Group`  (proposed: `item_group`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:item_group_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: An Item Group is a way to classify items based on types.
- **Search fields**: `parent_item_group`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `parent_item_group` | Link | `varchar(140)` |  | → `Item Group` |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `image` | Attach Image | `text` | hidden |  |
| 5 | `lft` | Int | `integer` | INDEX, hidden |  |
| 6 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 7 | `old_parent` | Link | `varchar(140)` | hidden | → `Item Group` |

**Child tables (1-N):**

- `item_group_defaults` → `Item Default` (line items)
- `taxes` → `Item Tax` (line items)

**Referenced by (30):** `POS Invoice Item`.`item_group`, `POS Item Group`.`item_group`, `Pricing Rule`.`other_item_group`, `Pricing Rule Item Group`.`item_group`, `Promotional Scheme`.`other_item_group`, `Purchase Invoice Item`.`item_group`, `Sales Invoice Item`.`item_group`, `Tax Rule`.`item_group`, `Purchase Order Item`.`item_group`, `Request for Quotation Item`.`item_group`, `Supplier Quotation Item`.`item_group`, `Opportunity Item`.`item_group`, `BOM Creator`.`item_group`, `BOM Creator Item`.`item_group`, `Job Card Item`.`item_group` … (+15 more)

## Sales Person

- **Table**: `tabSales Person`  (proposed: `sales_person`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:sales_person_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: All Sales Transactions can be tagged against multiple Sales Persons so that you can set and monitor targets.
- **Search fields**: `parent_sales_person`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_person_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `parent_sales_person` | Link | `varchar(140)` |  | → `Sales Person` |
| 3 | `commission_rate` | Percent | `numeric(21,9)` |  |  |
| 4 | `is_group` | Check | `smallint` | NOT NULL, default=0 |  |
| 5 | `enabled` | Check | `smallint` | default=1 |  |
| 6 | `employee` | Link | `varchar(140)` |  | → `Employee` |
| 7 | `department` | Link | `varchar(140)` | ro, denorm←employee.department | → `Department` |
| 8 | `lft` | Int | `integer` | INDEX, hidden |  |
| 9 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 10 | `old_parent` | Data | `varchar(140)` | hidden |  |

**Child tables (1-N):**

- `targets` → `Target Detail` (line items)

**Referenced by (7):** `Process Statement Of Accounts`.`sales_person`, `Maintenance Schedule Detail`.`sales_person`, `Maintenance Schedule Item`.`sales_person`, `Maintenance Visit Purpose`.`service_person`, `Sales Team`.`sales_person`, `Sales Person`.`parent_sales_person`, `Territory`.`territory_manager`

## Supplier Group

- **Table**: `tabSupplier Group`  (proposed: `supplier_group`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:supplier_group_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier_group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `parent_supplier_group` | Link | `varchar(140)` |  | → `Supplier Group` |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `payment_terms` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 5 | `lft` | Int | `integer` | INDEX, hidden |  |
| 6 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 7 | `old_parent` | Link | `varchar(140)` | hidden | → `Supplier Group` |

**Child tables (1-N):**

- `accounts` → `Party Account` (line items)

**Referenced by (10):** `Pricing Rule`.`supplier_group`, `Purchase Invoice`.`supplier_group`, `Supplier Group Item`.`supplier_group`, `Tax Rule`.`supplier_group`, `Buying Settings`.`supplier_group`, `Purchase Order`.`supplier_group`, `Supplier`.`supplier_group`, `Import Supplier Invoice`.`supplier_group`, `Supplier Group`.`parent_supplier_group`, `Supplier Group`.`old_parent`

## Territory

- **Table**: `tabTerritory`  (proposed: `territory`)
- **Kind**: Tree master (hierarchy)
- **Naming**: `field:territory_name`  (By fieldname)
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: Classification of Customers by region
- **Search fields**: `parent_territory,territory_manager`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `territory_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `parent_territory` | Link | `varchar(140)` |  | → `Territory` |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `territory_manager` | Link | `varchar(140)` | INDEX | → `Sales Person` |
| 5 | `lft` | Int | `integer` | INDEX, hidden |  |
| 6 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 7 | `old_parent` | Link | `varchar(140)` | hidden | → `Territory` |

**Child tables (1-N):**

- `targets` → `Target Detail` (line items)

**Referenced by (21):** `Loyalty Program`.`customer_territory`, `POS Invoice`.`territory`, `Pricing Rule`.`territory`, `Process Statement Of Accounts`.`territory`, `Sales Invoice`.`territory`, `Territory Item`.`territory`, `Lead`.`territory`, `Opportunity`.`territory`, `Prospect`.`territory`, `Maintenance Schedule`.`territory`, `Maintenance Visit`.`territory`, `Customer`.`territory`, `Installation Note`.`territory`, `Quotation`.`territory`, `Sales Order`.`territory` … (+6 more)

---

# Transaction (submittable)s

## Transaction Deletion Record

- **Table**: `tabTransaction Deletion Record`  (proposed: `transaction_deletion_record`)
- **Kind**: Transaction (submittable)
- **Naming**: `TDL.####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `amended_from` | Link | `varchar(140)` | ro | → `Transaction Deletion Record` |
| 3 | `status` | Select | `varchar(140)` | ro | enum: Queued, Running, Failed, Completed, Cancelled |
| 4 | `delete_bin_data_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 5 | `delete_leads_and_addresses_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 6 | `reset_company_default_values_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 7 | `clear_notifications_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 8 | `initialize_doctypes_table_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 9 | `delete_transactions_status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Completed, Skipped |
| 10 | `error_log` | Long Text | `text` |  |  |
| 11 | `process_in_single_transaction` | Check | `smallint` | ro, hidden, default=0 |  |

**Child tables (1-N):**

- `doctypes` → `Transaction Deletion Record Details` (line items)
- `doctypes_to_delete` → `Transaction Deletion Record To Delete` (line items)
- `doctypes_to_be_ignored` → `Transaction Deletion Record Item` (line items)

**Referenced by (1):** `Transaction Deletion Record`.`amended_from`

---

# Child / line-item tables

## Driving License Category

- **Table**: `tabDriving License Category`  (proposed: `driving_license_category`)
- **Kind**: Child / line-item table
- **Embedded in**: `Driver`.`driving_license_category`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `class` | Data | `varchar(140)` |  |  |
| 2 | `description` | Data | `varchar(140)` |  |  |
| 3 | `issuing_date` | Date | `date` |  |  |
| 4 | `expiry_date` | Date | `date` |  |  |

## Email Digest Recipient

- **Table**: `tabEmail Digest Recipient`  (proposed: `email_digest_recipient`)
- **Kind**: Child / line-item table
- **Embedded in**: `Email Digest`.`recipients`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `recipient` | Link | `varchar(140)` | NOT NULL | → `User` *(frappe core)* |

## Employee Education

- **Table**: `tabEmployee Education`  (proposed: `employee_education`)
- **Kind**: Child / line-item table
- **Embedded in**: `Employee`.`education`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `school_univ` | Small Text | `text` |  |  |
| 2 | `qualification` | Data | `varchar(140)` |  |  |
| 3 | `level` | Select | `varchar(140)` |  | enum: Graduate, Post Graduate, Under Graduate |
| 4 | `year_of_passing` | Int | `integer` |  |  |
| 5 | `class_per` | Data | `varchar(140)` |  |  |
| 6 | `maj_opt_subj` | Text | `text` |  |  |

## Employee External Work History

- **Table**: `tabEmployee External Work History`  (proposed: `employee_external_work_history`)
- **Kind**: Child / line-item table
- **Embedded in**: `Employee`.`external_work_history`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company_name` | Data | `varchar(140)` |  |  |
| 2 | `designation` | Data | `varchar(140)` |  |  |
| 3 | `salary` | Currency | `numeric(21,9)` |  |  |
| 4 | `address` | Small Text | `text` |  |  |
| 5 | `contact` | Data | `varchar(140)` |  |  |
| 6 | `total_experience` | Data | `varchar(140)` |  |  |

## Employee Group Table

- **Table**: `tabEmployee Group Table`  (proposed: `employee_group_table`)
- **Kind**: Child / line-item table
- **Embedded in**: `Employee Group`.`employee_list`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `employee` | Link | `varchar(140)` |  | → `Employee` |
| 2 | `employee_name` | Data | `varchar(140)` | denorm←employee.first_name |  |
| 3 | `user_id` | Data | `varchar(140)` | ro, denorm←employee.user_id |  |

## Employee Internal Work History

- **Table**: `tabEmployee Internal Work History`  (proposed: `employee_internal_work_history`)
- **Kind**: Child / line-item table
- **Embedded in**: `Employee`.`internal_work_history`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `branch` | Link | `varchar(140)` |  | → `Branch` |
| 2 | `department` | Link | `varchar(140)` |  | → `Department` |
| 3 | `designation` | Link | `varchar(140)` |  | → `Designation` |
| 4 | `from_date` | Date | `date` |  |  |
| 5 | `to_date` | Date | `date` |  |  |

## Holiday

- **Table**: `tabHoliday`  (proposed: `holiday`)
- **Kind**: Child / line-item table
- **Embedded in**: `Holiday List`.`holidays`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `holiday_date` | Date | `date` | NOT NULL |  |
| 2 | `description` | Text Editor | `text` | NOT NULL |  |
| 3 | `weekly_off` | Check | `smallint` | default=0 |  |
| 4 | `is_half_day` | Check | `smallint` | default=0 |  |

## Quotation Lost Reason Detail

- **Table**: `tabQuotation Lost Reason Detail`  (proposed: `quotation_lost_reason_detail`)
- **Kind**: Child / line-item table
- **Embedded in**: `Quotation`.`lost_reasons`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `lost_reason` | Link | `varchar(140)` |  | → `Quotation Lost Reason` |

## Target Detail

- **Table**: `tabTarget Detail`  (proposed: `target_detail`)
- **Kind**: Child / line-item table
- **Embedded in**: `Sales Partner`.`targets`, `Sales Person`.`targets`, `Territory`.`targets`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_group` | Link | `varchar(140)` | INDEX | → `Item Group` |
| 2 | `fiscal_year` | Link | `varchar(140)` | NOT NULL, INDEX | → `Fiscal Year` |
| 3 | `target_qty` | Float | `numeric(21,9)` |  |  |
| 4 | `target_amount` | Float | `numeric(21,9)` | INDEX |  |
| 5 | `distribution_id` | Link | `varchar(140)` | NOT NULL | → `Monthly Distribution` |

## Transaction Deletion Record Item

- **Table**: `tabTransaction Deletion Record Item`  (proposed: `transaction_deletion_record_item`)
- **Kind**: Child / line-item table
- **Embedded in**: `Transaction Deletion Record`.`doctypes_to_be_ignored`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `doctype_name` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe core)* |

## Transaction Deletion Record To Delete

- **Table**: `tabTransaction Deletion Record To Delete`  (proposed: `transaction_deletion_record_to_delete`)
- **Kind**: Child / line-item table
- **Embedded in**: `Transaction Deletion Record`.`doctypes_to_delete`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `doctype_name` | Link | `varchar(140)` |  | → `DocType` *(frappe core)* |
| 2 | `company_field` | Data | `varchar(140)` |  |  |
| 3 | `document_count` | Int | `integer` | ro |  |
| 4 | `child_doctypes` | Small Text | `text` | ro |  |
| 5 | `deleted` | Check | `smallint` | ro, default=0 |  |

## Website Item Group

- **Table**: `tabWebsite Item Group`  (proposed: `website_item_group`)
- **Kind**: Child / line-item table
- **Description**: Cross Listing of Item in multiple groups

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_group` | Link | `varchar(140)` | NOT NULL | → `Item Group` |
