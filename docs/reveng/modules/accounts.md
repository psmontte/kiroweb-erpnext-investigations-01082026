# Module deep dive: Accounts

The accounting core: chart of accounts, fiscal calendar, the general ledger and the two
subledgers (payment ledger, accounting dimensions). Every stock/trade document ultimately
posts into `GL Entry`. `Account` and `Cost Center` are nested-set trees; `GL Entry` is
append-only in practice (cancellations post reversing rows and flip `is_cancelled`).

191 DocTypes / 2323 columns.

## Contents

**Single (settings)** (12): [Accounts Settings](#accounts-settings), [Bank Clearance](#bank-clearance), [Bank Reconciliation Tool](#bank-reconciliation-tool), [Bisect Accounting Statements](#bisect-accounting-statements), [Chart of Accounts Importer](#chart-of-accounts-importer), [Currency Exchange Settings](#currency-exchange-settings), [Ledger Health Monitor](#ledger-health-monitor), [Opening Invoice Creation Tool](#opening-invoice-creation-tool), [POS Settings](#pos-settings), [Payment Reconciliation](#payment-reconciliation), [Pegged Currencies](#pegged-currencies), [Subscription Settings](#subscription-settings)

**Master** (47): [Account Category](#account-category), [Accounting Dimension](#accounting-dimension), [Accounting Dimension Filter](#accounting-dimension-filter), [Accounting Period](#accounting-period), [Bank](#bank), [Bank Account](#bank-account), [Bank Account Balance](#bank-account-balance), [Bank Account Subtype](#bank-account-subtype), [Bank Account Type](#bank-account-type), [Bank Statement Import](#bank-statement-import), [Bank Statement Import Log](#bank-statement-import-log), [Bank Transaction Rule](#bank-transaction-rule), [Bisect Nodes](#bisect-nodes), [Cheque Print Template](#cheque-print-template), [Coupon Code](#coupon-code), [Dunning Type](#dunning-type), [Finance Book](#finance-book), [Financial Report Template](#financial-report-template), [Fiscal Year](#fiscal-year), [Item Tax Template](#item-tax-template), [Journal Entry Template](#journal-entry-template), [Ledger Health](#ledger-health), [Ledger Merge](#ledger-merge), [Loyalty Point Entry](#loyalty-point-entry), [Loyalty Program](#loyalty-program), [Mode of Payment](#mode-of-payment), [Monthly Distribution](#monthly-distribution), [POS Profile](#pos-profile), [Party Link](#party-link), [Payment Gateway Account](#payment-gateway-account), [Payment Term](#payment-term), [Payment Terms Template](#payment-terms-template), [Pricing Rule](#pricing-rule), [Process Payment Reconciliation Log](#process-payment-reconciliation-log), [Process Statement Of Accounts](#process-statement-of-accounts), [Promotional Scheme](#promotional-scheme), [Purchase Taxes and Charges Template](#purchase-taxes-and-charges-template), [Sales Taxes and Charges Template](#sales-taxes-and-charges-template), [Share Type](#share-type), [Shareholder](#shareholder), [Shipping Rule](#shipping-rule), [Subscription](#subscription), [Subscription Plan](#subscription-plan), [Tax Category](#tax-category), [Tax Rule](#tax-rule), [Tax Withholding Category](#tax-withholding-category), [Tax Withholding Group](#tax-withholding-group)

**Tree master (hierarchy)** (2): [Account](#account), [Cost Center](#cost-center)

**Transaction (submittable)** (31): [Account Closing Balance](#account-closing-balance), [Advance Payment Ledger Entry](#advance-payment-ledger-entry), [Bank Guarantee](#bank-guarantee), [Bank Transaction](#bank-transaction), [Budget](#budget), [Cashier Closing](#cashier-closing), [Cost Center Allocation](#cost-center-allocation), [Dunning](#dunning), [Exchange Rate Revaluation](#exchange-rate-revaluation), [GL Entry](#gl-entry), [Invoice Discounting](#invoice-discounting), [Journal Entry](#journal-entry), [POS Closing Entry](#pos-closing-entry), [POS Invoice](#pos-invoice), [POS Invoice Merge Log](#pos-invoice-merge-log), [POS Opening Entry](#pos-opening-entry), [Payment Entry](#payment-entry), [Payment Ledger Entry](#payment-ledger-entry), [Payment Order](#payment-order), [Payment Request](#payment-request), [Period Closing Voucher](#period-closing-voucher), [Process Deferred Accounting](#process-deferred-accounting), [Process Payment Reconciliation](#process-payment-reconciliation), [Process Period Closing Voucher](#process-period-closing-voucher), [Process Subscription](#process-subscription), [Purchase Invoice](#purchase-invoice), [Repost Accounting Ledger](#repost-accounting-ledger), [Repost Payment Ledger](#repost-payment-ledger), [Sales Invoice](#sales-invoice), [Share Transfer](#share-transfer), [Unreconcile Payment](#unreconcile-payment)

**Child / line-item table** (99): [Accounting Dimension Detail](#accounting-dimension-detail), [Advance Taxes and Charges](#advance-taxes-and-charges), [Allowed Dimension](#allowed-dimension), [Allowed To Transact With](#allowed-to-transact-with), [Applicable On Account](#applicable-on-account), [Bank Clearance Detail](#bank-clearance-detail), [Bank Statement Import Log Column Map](#bank-statement-import-log-column-map), [Bank Transaction Mapping](#bank-transaction-mapping), [Bank Transaction Payments](#bank-transaction-payments), [Bank Transaction Rule Accounts](#bank-transaction-rule-accounts), [Bank Transaction Rule Description Conditions](#bank-transaction-rule-description-conditions), [Budget Account](#budget-account), [Budget Distribution](#budget-distribution), [Campaign Item](#campaign-item), [Cashier Closing Payments](#cashier-closing-payments), [Closed Document](#closed-document), [Cost Center Allocation Percentage](#cost-center-allocation-percentage), [Currency Exchange Settings Details](#currency-exchange-settings-details), [Currency Exchange Settings Result](#currency-exchange-settings-result), [Customer Group Item](#customer-group-item), [Customer Item](#customer-item), [Discounted Invoice](#discounted-invoice), [Dunning Letter Text](#dunning-letter-text), [Exchange Rate Revaluation Account](#exchange-rate-revaluation-account), [Financial Report Row](#financial-report-row), [Fiscal Year Company](#fiscal-year-company), [Item Tax Template Detail](#item-tax-template-detail), [Item Wise Tax Detail](#item-wise-tax-detail), [Journal Entry Account](#journal-entry-account), [Journal Entry Template Account](#journal-entry-template-account), [Ledger Health Monitor Company](#ledger-health-monitor-company), [Ledger Merge Accounts](#ledger-merge-accounts), [Loyalty Point Entry Redemption](#loyalty-point-entry-redemption), [Loyalty Program Collection](#loyalty-program-collection), [Mode of Payment Account](#mode-of-payment-account), [Monthly Distribution Percentage](#monthly-distribution-percentage), [Opening Invoice Creation Tool Item](#opening-invoice-creation-tool-item), [Overdue Payment](#overdue-payment), [POS Closing Entry Detail](#pos-closing-entry-detail), [POS Closing Entry Taxes](#pos-closing-entry-taxes), [POS Customer Group](#pos-customer-group), [POS Field](#pos-field), [POS Invoice Item](#pos-invoice-item), [POS Invoice Reference](#pos-invoice-reference), [POS Item Group](#pos-item-group), [POS Opening Entry Detail](#pos-opening-entry-detail), [POS Payment Method](#pos-payment-method), [POS Profile User](#pos-profile-user), [POS Search Fields](#pos-search-fields), [PSOA Cost Center](#psoa-cost-center), [PSOA Project](#psoa-project), [Party Account](#party-account), [Payment Entry Deduction](#payment-entry-deduction), [Payment Entry Reference](#payment-entry-reference), [Payment Order Reference](#payment-order-reference), [Payment Reconciliation Allocation](#payment-reconciliation-allocation), [Payment Reconciliation Invoice](#payment-reconciliation-invoice), [Payment Reconciliation Payment](#payment-reconciliation-payment), [Payment Reference](#payment-reference), [Payment Schedule](#payment-schedule), [Payment Terms Template Detail](#payment-terms-template-detail), [Pegged Currency Details](#pegged-currency-details), [Pricing Rule Brand](#pricing-rule-brand), [Pricing Rule Detail](#pricing-rule-detail), [Pricing Rule Item Code](#pricing-rule-item-code), [Pricing Rule Item Group](#pricing-rule-item-group), [Process Payment Reconciliation Log Allocations](#process-payment-reconciliation-log-allocations), [Process Period Closing Voucher Detail](#process-period-closing-voucher-detail), [Process Statement Of Accounts CC](#process-statement-of-accounts-cc), [Process Statement Of Accounts Customer](#process-statement-of-accounts-customer), [Promotional Scheme Price Discount](#promotional-scheme-price-discount), [Promotional Scheme Product Discount](#promotional-scheme-product-discount), [Purchase Invoice Advance](#purchase-invoice-advance), [Purchase Invoice Item](#purchase-invoice-item), [Purchase Taxes and Charges](#purchase-taxes-and-charges), [Repost Accounting Ledger Items](#repost-accounting-ledger-items), [Repost Allowed Types](#repost-allowed-types), [Repost Payment Ledger Items](#repost-payment-ledger-items), [Sales Invoice Advance](#sales-invoice-advance), [Sales Invoice Item](#sales-invoice-item), [Sales Invoice Payment](#sales-invoice-payment), [Sales Invoice Reference](#sales-invoice-reference), [Sales Invoice Timesheet](#sales-invoice-timesheet), [Sales Partner Item](#sales-partner-item), [Sales Taxes and Charges](#sales-taxes-and-charges), [Share Balance](#share-balance), [Shipping Rule Condition](#shipping-rule-condition), [Shipping Rule Country](#shipping-rule-country), [South Africa VAT Account](#south-africa-vat-account), [Subscription Invoice](#subscription-invoice), [Subscription Plan Detail](#subscription-plan-detail), [Supplier Group Item](#supplier-group-item), [Supplier Item](#supplier-item), [Tax Withholding Account](#tax-withholding-account), [Tax Withholding Entry](#tax-withholding-entry), [Tax Withholding Rate](#tax-withholding-rate), [Territory Item](#territory-item), [Transaction Deletion Record Details](#transaction-deletion-record-details), [Unreconcile Payment Entries](#unreconcile-payment-entries)

---

# Single (settings)s

## Accounts Settings

- **Table**: `tabAccounts Settings`  (proposed: `accounts_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `determine_address_tax_category_from` | Select | `varchar(140)` | default=Billing Address | enum: Billing Address, Shipping Address |
| 2 | `credit_controller` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 3 | `check_supplier_invoice_uniqueness` | Check | `smallint` | default=0 |  |
| 4 | `make_payment_via_journal_entry` | Check | `smallint` | hidden, default=0 |  |
| 5 | `unlink_payment_on_cancellation_of_invoice` | Check | `smallint` | default=1 |  |
| 6 | `unlink_advance_payment_on_cancelation_of_order` | Check | `smallint` | default=1 |  |
| 7 | `book_asset_depreciation_entry_automatically` | Check | `smallint` | default=1 |  |
| 8 | `add_taxes_from_item_tax_template` | Check | `smallint` | default=1 |  |
| 9 | `show_inclusive_tax_in_print` | Check | `smallint` | default=0 |  |
| 10 | `show_payment_schedule_in_print` | Check | `smallint` | default=0 |  |
| 11 | `allow_stale` | Check | `smallint` | default=1 |  |
| 12 | `stale_days` | Int | `integer` | default=1 |  |
| 13 | `automatically_fetch_payment_terms` | Check | `smallint` | default=0 |  |
| 14 | `over_billing_allowance` | Currency | `numeric(21,9)` |  |  |
| 15 | `automatically_process_deferred_accounting_entry` | Check | `smallint` | default=1 |  |
| 16 | `book_deferred_entries_via_journal_entry` | Check | `smallint` | default=0 |  |
| 17 | `submit_journal_entries` | Check | `smallint` | default=0 |  |
| 18 | `book_deferred_entries_based_on` | Select | `varchar(140)` | default=Days | enum: Days, Months |
| 19 | `delete_linked_ledger_entries` | Check | `smallint` | default=0 |  |
| 20 | `role_allowed_to_over_bill` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 21 | `enable_overdue_billing_threshold` | Check | `smallint` | default=0 |  |
| 22 | `role_allowed_to_bypass_overdue_billing` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 23 | `enable_common_party_accounting` | Check | `smallint` | default=0 |  |
| 24 | `allow_multi_currency_invoices_against_single_party_account` | Check | `smallint` | default=0 |  |
| 25 | `show_balance_in_coa` | Check | `smallint` | default=1 |  |
| 26 | `book_tax_discount_loss` | Check | `smallint` | default=0 |  |
| 27 | `merge_similar_account_heads` | Check | `smallint` | default=0 |  |
| 28 | `auto_reconcile_payments` | Check | `smallint` | default=0 |  |
| 29 | `show_taxes_as_table_in_print` | Check | `smallint` | default=0 |  |
| 30 | `enable_party_matching` | Check | `smallint` | default=0 |  |
| 31 | `enable_fuzzy_matching` | Check | `smallint` | default=0 |  |
| 32 | `ignore_account_closing_balance` | Check | `smallint` | default=0 |  |
| 33 | `round_row_wise_tax` | Check | `smallint` | default=0 |  |
| 34 | `general_ledger_remarks_length` | Int | `integer` | default=0 |  |
| 35 | `receivable_payable_remarks_length` | Int | `integer` | default=0 |  |
| 36 | `enable_immutable_ledger` | Check | `smallint` | default=0 |  |
| 37 | `calculate_depr_using_total_days` | Check | `smallint` | default=0 |  |
| 38 | `create_pr_in_draft_status` | Check | `smallint` | default=1 |  |
| 39 | `auto_reconciliation_job_trigger` | Int | `integer` | default=15 |  |
| 40 | `reconciliation_queue_size` | Int | `integer` | default=5 |  |
| 41 | `ignore_is_opening_check_for_reporting` | Check | `smallint` | default=0 |  |
| 42 | `exchange_gain_loss_posting_date` | Select | `varchar(140)` | default=Payment | enum: Invoice, Payment, Reconciliation Date |
| 43 | `receivable_payable_fetch_method` | Select | `varchar(140)` | default=Buffered Cursor | enum: Buffered Cursor, UnBuffered Cursor |
| 44 | `maintain_same_internal_transaction_rate` | Check | `smallint` | default=0 |  |
| 45 | `maintain_same_rate_action` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn |
| 46 | `role_to_override_stop_action` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 47 | `confirm_before_resetting_posting_date` | Check | `smallint` | default=1 |  |
| 48 | `allow_pegged_currencies_exchange_rates` | Check | `smallint` | default=0 |  |
| 49 | `add_taxes_from_taxes_and_charges_template` | Check | `smallint` | default=0 |  |
| 50 | `fetch_valuation_rate_for_internal_transaction` | Check | `smallint` | default=0 |  |
| 51 | `use_legacy_budget_controller` | Check | `smallint` | default=0 |  |
| 52 | `use_legacy_controller_for_pcv` | Check | `smallint` | default=1 |  |
| 53 | `pcv_job_timeout` | Int | `integer` | default=3600 |  |
| 54 | `role_to_notify_on_depreciation_failure` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |
| 55 | `default_ageing_range` | Data | `varchar(140)` | default=30, 60, 90, 120 |  |
| 56 | `enable_discounts_and_margin` | Check | `smallint` | default=0 |  |
| 57 | `enable_loyalty_point_program` | Check | `smallint` | default=0 |  |
| 58 | `enable_accounting_dimensions` | Check | `smallint` | default=0 |  |
| 59 | `enable_subscription` | Check | `smallint` | default=1 |  |
| 60 | `fetch_payment_schedule_in_payment_request` | Check | `smallint` | default=1 |  |
| 61 | `transfer_match_days` | Int | `integer` | default=3 |  |
| 62 | `automatically_run_rules_on_unreconciled_transactions` | Check | `smallint` | default=1 |  |
| 63 | `preview_mode` | Check | `smallint` | default=0 |  |
| 64 | `book_stock_expense_gl_entries` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `repost_allowed_types` → `Repost Allowed Types` (line items)

## Bank Clearance

- **Table**: `tabBank Clearance`  (proposed: `bank_clearance`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL, denorm←bank_account.account | → `Account` |
| 2 | `account_currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |
| 3 | `from_date` | Date | `date` | NOT NULL |  |
| 4 | `to_date` | Date | `date` | NOT NULL |  |
| 5 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 6 | `include_reconciled_entries` | Check | `smallint` | default=0 |  |
| 7 | `include_pos_transactions` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `payment_entries` → `Bank Clearance Detail` (line items)

## Bank Reconciliation Tool

- **Table**: `tabBank Reconciliation Tool`  (proposed: `bank_reconciliation_tool`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 3 | `bank_statement_from_date` | Date | `date` |  |  |
| 4 | `bank_statement_to_date` | Date | `date` |  |  |
| 5 | `account_opening_balance` | Currency | `numeric(21,9)` | ro |  |
| 6 | `bank_statement_closing_balance` | Currency | `numeric(21,9)` |  |  |
| 7 | `from_reference_date` | Date | `date` |  |  |
| 8 | `to_reference_date` | Date | `date` |  |  |
| 9 | `filter_by_reference_date` | Check | `smallint` | default=0 |  |
| 10 | `account_currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |

## Bisect Accounting Statements

- **Table**: `tabBisect Accounting Statements`  (proposed: `bisect_accounting_statements`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `from_date` | Datetime | `timestamp` |  |  |
| 2 | `to_date` | Datetime | `timestamp` |  |  |
| 3 | `algorithm` | Select | `varchar(140)` | default=BFS | enum: BFS, DFS |
| 4 | `current_node` | Link | `varchar(140)` |  | → `Bisect Nodes` |
| 5 | `current_from_date` | Datetime | `timestamp` | ro |  |
| 6 | `current_to_date` | Datetime | `timestamp` | ro |  |
| 7 | `p_l_summary` | Float | `numeric(21,9)` | ro |  |
| 8 | `b_s_summary` | Float | `numeric(21,9)` | ro |  |
| 9 | `difference` | Float | `numeric(21,9)` | ro |  |
| 10 | `company` | Link | `varchar(140)` |  | → `Company` |

## Chart of Accounts Importer

- **Table**: `tabChart of Accounts Importer`  (proposed: `chart_of_accounts_importer`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts
- **Description**: Import Chart of Accounts from a csv file

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `import_file` | Attach | `text` |  |  |

## Currency Exchange Settings

- **Table**: `tabCurrency Exchange Settings`  (proposed: `currency_exchange_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `api_endpoint` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `url` | Data | `varchar(140)` | ro |  |
| 3 | `service_provider` | Select | `varchar(140)` | NOT NULL | enum: frankfurter.dev, exchangerate.host, frankfurter.dev - v2, Custom |
| 4 | `disabled` | Check | `smallint` | default=0 |  |
| 5 | `access_key` | Data | `varchar(140)` |  |  |
| 6 | `use_http` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `req_params` → `Currency Exchange Settings Details` (line items)
- `result_key` → `Currency Exchange Settings Result` (line items)

## Ledger Health Monitor

- **Table**: `tabLedger Health Monitor`  (proposed: `ledger_health_monitor`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `enable_health_monitor` | Check | `smallint` | default=0 |  |
| 2 | `debit_credit_mismatch` | Check | `smallint` | default=0 |  |
| 3 | `general_and_payment_ledger_mismatch` | Check | `smallint` | default=0 |  |
| 4 | `monitor_for_last_x_days` | Int | `integer` | NOT NULL, default=60 |  |

**Child tables (1-N):**

- `companies` → `Ledger Health Monitor Company` (line items)

## Opening Invoice Creation Tool

- **Table**: `tabOpening Invoice Creation Tool`  (proposed: `opening_invoice_creation_tool`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `create_missing_party` | Check | `smallint` | default=0 |  |
| 3 | `invoice_type` | Select | `varchar(140)` | NOT NULL | enum: Sales, Purchase |
| 4 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 5 | `project` | Link | `varchar(140)` |  | → `Project` |

**Child tables (1-N):**

- `invoices` → `Opening Invoice Creation Tool Item` (line items)

## POS Settings

- **Table**: `tabPOS Settings`  (proposed: `pos_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `invoice_type` | Select | `varchar(140)` | default=Sales Invoice | enum: Sales Invoice, POS Invoice |
| 2 | `post_change_gl_entries` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `invoice_fields` → `POS Field` (line items)
- `pos_search_fields` → `POS Search Fields` (line items)

## Payment Reconciliation

- **Table**: `tabPayment Reconciliation`  (proposed: `payment_reconciliation`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `party_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 3 | `party` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `party_type` |
| 4 | `receivable_payable_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 5 | `bank_cash_account` | Link | `varchar(140)` |  | → `Account` |
| 6 | `from_invoice_date` | Date | `date` |  |  |
| 7 | `to_invoice_date` | Date | `date` |  |  |
| 8 | `minimum_invoice_amount` | Currency | `numeric(21,9)` |  |  |
| 9 | `invoice_limit` | Int | `integer` | default=50 |  |
| 10 | `from_payment_date` | Date | `date` |  |  |
| 11 | `to_payment_date` | Date | `date` |  |  |
| 12 | `minimum_payment_amount` | Currency | `numeric(21,9)` |  |  |
| 13 | `maximum_payment_amount` | Currency | `numeric(21,9)` |  |  |
| 14 | `payment_limit` | Int | `integer` | default=50 |  |
| 15 | `maximum_invoice_amount` | Currency | `numeric(21,9)` |  |  |
| 16 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 17 | `project` | Link | `varchar(140)` |  | → `Project` |
| 18 | `default_advance_account` | Link | `varchar(140)` |  | → `Account` |
| 19 | `invoice_name` | Data | `varchar(140)` |  |  |
| 20 | `payment_name` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `payments` → `Payment Reconciliation Payment` (line items)
- `invoices` → `Payment Reconciliation Invoice` (line items)
- `allocation` → `Payment Reconciliation Allocation` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`

## Pegged Currencies

- **Table**: `tabPegged Currencies`  (proposed: `pegged_currencies`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|

**Child tables (1-N):**

- `pegged_currency_item` → `Pegged Currency Details` (line items)

## Subscription Settings

- **Table**: `tabSubscription Settings`  (proposed: `subscription_settings`)
- **Kind**: Single (settings)
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `grace_period` | Int | `integer` | default=1 |  |
| 2 | `cancel_after_grace` | Check | `smallint` | default=0 |  |
| 3 | `prorate` | Check | `smallint` | default=1 |  |

---

# Masters

## Account Category

- **Table**: `tabAccount Category`  (proposed: `account_category`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:account_category_name`  (By fieldname)
- **Search fields**: `account_category_name, root_type`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account_category_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Small Text | `text` |  |  |
| 3 | `root_type` | Select | `varchar(140)` |  | enum: Asset, Liability, Income, Expense, Equity |

**Referenced by (1):** `Account`.`account_category`

## Accounting Dimension

- **Table**: `tabAccounting Dimension`  (proposed: `accounting_dimension`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:label`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `label` | Data | `varchar(140)` | UNIQUE |  |
| 2 | `fieldname` | Data | `varchar(140)` | hidden |  |
| 3 | `document_type` | Link | `varchar(140)` | NOT NULL, INDEX | → `DocType` *(frappe/Core)* |
| 4 | `disabled` | Check | `smallint` | ro, hidden, default=0 |  |

**Child tables (1-N):**

- `dimension_defaults` → `Accounting Dimension Detail` (line items)

## Accounting Dimension Filter

- **Table**: `tabAccounting Dimension Filter`  (proposed: `accounting_dimension_filter`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `format:{accounting_dimension}-{#####}`  (Expression)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `accounting_dimension` | Select | `varchar(140)` | NOT NULL |  |
| 2 | `allow_or_restrict` | Select | `varchar(140)` | NOT NULL | enum: Allow, Restrict |
| 3 | `disabled` | Check | `smallint` | default=0 |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `apply_restriction_on_values` | Check | `smallint` | default=1 |  |
| 6 | `fieldname` | Data | `varchar(140)` | hidden |  |

**Child tables (1-N):**

- `accounts` → `Applicable On Account` (line items)
- `dimensions` → `Allowed Dimension` (line items)

## Accounting Period

- **Table**: `tabAccounting Period`  (proposed: `accounting_period`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:period_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `period_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `start_date` | Date | `date` | NOT NULL |  |
| 3 | `end_date` | Date | `date` | NOT NULL |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `disabled` | Check | `smallint` | default=0 |  |
| 6 | `exempted_role` | Link | `varchar(140)` |  | → `Role` *(frappe/Core)* |

**Child tables (1-N):**

- `closed_documents` → `Closed Document` (line items)

## Bank

- **Table**: `tabBank`  (proposed: `bank`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:bank_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `bank_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `swift_number` | Data | `varchar(140)` | UNIQUE |  |
| 3 | `website` | Data | `varchar(140)` |  |  |
| 4 | `plaid_access_token` | Data | `varchar(140)` | ro, hidden |  |

**Child tables (1-N):**

- `bank_transaction_mapping` → `Bank Transaction Mapping` (line items)

**Referenced by (5):** `Bank Account`.`bank`, `Bank Guarantee`.`bank`, `Bank Statement Import`.`bank`, `Payment Order`.`company_bank`, `Payment Request`.`bank`

## Bank Account

- **Table**: `tabBank Account`  (proposed: `bank_account`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Search fields**: `bank,account`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `account` | Link | `varchar(140)` |  | → `Account` |
| 3 | `bank` | Link | `varchar(140)` | NOT NULL | → `Bank` |
| 4 | `account_type` | Link | `varchar(140)` |  | → `Bank Account Type` |
| 5 | `account_subtype` | Link | `varchar(140)` |  | → `Bank Account Subtype` |
| 6 | `is_default` | Check | `smallint` | default=0 |  |
| 7 | `is_company_account` | Check | `smallint` | default=0 |  |
| 8 | `company` | Link | `varchar(140)` |  | → `Company` |
| 9 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 10 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 11 | `iban` | Data | `varchar(140)` |  |  |
| 12 | `bank_account_no` | Data | `varchar(140)` |  |  |
| 13 | `statement_password` | Password | `text` |  |  |
| 14 | `integration_id` | Data | `varchar(140)` | UNIQUE, ro, hidden |  |
| 15 | `last_integration_date` | Date | `date` |  |  |
| 16 | `mask` | Data | `varchar(140)` | ro |  |
| 17 | `branch_code` | Data | `varchar(140)` |  |  |
| 18 | `disabled` | Check | `smallint` | default=0 |  |
| 19 | `is_credit_card` | Check | `smallint` | default=0 |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (16):** `Bank Account Balance`.`bank_account`, `Bank Clearance`.`bank_account`, `Bank Guarantee`.`bank_account`, `Bank Reconciliation Tool`.`bank_account`, `Bank Statement Import`.`bank_account`, `Bank Statement Import Log`.`bank_account`, `Bank Transaction`.`bank_account`, `Journal Entry Account`.`bank_account`, `Payment Entry`.`bank_account`, `Payment Entry`.`party_bank_account`, `Payment Order`.`company_bank_account`, `Payment Order Reference`.`bank_account`, `Payment Request`.`bank_account`, `Supplier`.`default_bank_account`, `Customer`.`default_bank_account` … (+1 more)

## Bank Account Balance

- **Table**: `tabBank Account Balance`  (proposed: `bank_account_balance`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `bank_account` | Link | `varchar(140)` | NOT NULL | → `Bank Account` |
| 2 | `date` | Date | `date` | NOT NULL |  |
| 3 | `balance` | Currency | `numeric(21,9)` | NOT NULL |  |
| 4 | `company` | Link | `varchar(140)` | ro, denorm←bank_account.company | → `Company` |

## Bank Account Subtype

- **Table**: `tabBank Account Subtype`  (proposed: `bank_account_subtype`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:account_subtype`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account_subtype` | Data | `varchar(140)` | UNIQUE |  |

**Referenced by (1):** `Bank Account`.`account_subtype`

## Bank Account Type

- **Table**: `tabBank Account Type`  (proposed: `bank_account_type`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:account_type`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account_type` | Data | `varchar(140)` | UNIQUE |  |

**Referenced by (1):** `Bank Account`.`account_type`

## Bank Statement Import

- **Table**: `tabBank Statement Import`  (proposed: `bank_statement_import`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `format:Bank Statement Import on {creation}`  (Expression (old style))

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `bank_account` | Link | `varchar(140)` | NOT NULL | → `Bank Account` |
| 3 | `bank` | Link | `varchar(140)` | ro, denorm←bank_account.bank | → `Bank` |
| 4 | `import_file` | Attach | `text` |  |  |
| 5 | `template_options` | Code | `text` | ro, hidden |  |
| 6 | `status` | Select | `varchar(140)` | ro, hidden, default=Pending | enum: Pending, Success, Partial Success, Error |
| 7 | `template_warnings` | Code | `text` | hidden |  |
| 8 | `show_failed_logs` | Check | `smallint` | default=0 |  |
| 9 | `google_sheets_url` | Data | `varchar(140)` |  |  |
| 10 | `reference_doctype` | Link | `varchar(140)` | NOT NULL, hidden, default=Bank Transaction | → `DocType` *(frappe/Core)* |
| 11 | `import_type` | Select | `varchar(140)` | NOT NULL, hidden, default=Insert New Records | enum: Insert New Records, Update Existing Records |
| 12 | `submit_after_import` | Check | `smallint` | hidden, default=1 |  |
| 13 | `mute_emails` | Check | `smallint` | hidden, default=1 |  |
| 14 | `custom_delimiters` | Check | `smallint` | default=0 |  |
| 15 | `delimiter_options` | Data | `varchar(140)` | default=,;\t\| |  |
| 16 | `use_csv_sniffer` | Check | `smallint` | hidden, default=0 |  |
| 17 | `import_mt940_fromat` | Check | `smallint` | default=0 |  |

## Bank Statement Import Log

- **Table**: `tabBank Statement Import Log`  (proposed: `bank_statement_import_log`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `bank_account` | Link | `varchar(140)` | NOT NULL | → `Bank Account` |
| 2 | `number_of_transactions` | Int | `integer` | ro |  |
| 3 | `closing_balance` | Currency | `numeric(21,9)` |  |  |
| 4 | `start_date` | Date | `date` | ro |  |
| 5 | `end_date` | Date | `date` | ro |  |
| 6 | `file` | Attach | `text` | NOT NULL |  |
| 7 | `detected_date_format` | Data | `varchar(140)` | ro |  |
| 8 | `detected_amount_format` | Select | `varchar(140)` | ro | enum: Separate columns for withdrawal and deposit, Amount column has "CR"/"DR" values, Amount column has positive/negative values, Transaction type column has "CR"/"DR" values, Transaction type column has "Deposit"/"Withdrawal" values, Transaction type column has "C"/"D" values |
| 9 | `detected_header_index` | Int | `integer` | ro |  |
| 10 | `detected_transaction_starting_index` | Int | `integer` | ro |  |
| 11 | `detected_transaction_ending_index` | Int | `integer` | ro |  |
| 12 | `pdf_tables` | JSON | `jsonb` | ro |  |
| 13 | `status` | Select | `varchar(140)` | ro, default=Not Started | enum: Not Started, Completed |
| 14 | `currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 15 | `total_debits` | Currency | `numeric(21,9)` | ro |  |
| 16 | `total_credits` | Currency | `numeric(21,9)` | ro |  |
| 17 | `total_debit_transactions` | Int | `integer` | ro |  |
| 18 | `total_credit_transactions` | Int | `integer` | ro |  |

**Child tables (1-N):**

- `column_mapping` → `Bank Statement Import Log Column Map` (line items)

## Bank Transaction Rule

- **Table**: `tabBank Transaction Rule`  (proposed: `bank_transaction_rule`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:rule_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `rule_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `transaction_type` | Select | `varchar(140)` | NOT NULL, default=Any | enum: Any, Withdrawal, Deposit |
| 3 | `min_amount` | Currency | `numeric(21,9)` |  |  |
| 4 | `max_amount` | Currency | `numeric(21,9)` |  |  |
| 5 | `rule_description` | Small Text | `text` |  |  |
| 6 | `classify_as` | Select | `varchar(140)` | NOT NULL | enum: Bank Entry, Payment Entry, Transfer |
| 7 | `account` | Link | `varchar(140)` |  | → `Account` |
| 8 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 9 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 10 | `priority` | Int | `integer` | NOT NULL |  |
| 11 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 12 | `bank_entry_type` | Select | `varchar(140)` |  | enum: Single Account, Multiple Accounts |

**Child tables (1-N):**

- `description_rules` → `Bank Transaction Rule Description Conditions` (line items)
- `accounts` → `Bank Transaction Rule Accounts` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (1):** `Bank Transaction`.`matched_transaction_rule`

## Bisect Nodes

- **Table**: `tabBisect Nodes`  (proposed: `bisect_nodes`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `autoincrement`  (Autoincrement)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `root` | Link | `varchar(140)` |  | → `Bisect Nodes` |
| 2 | `left_child` | Link | `varchar(140)` |  | → `Bisect Nodes` |
| 3 | `right_child` | Link | `varchar(140)` |  | → `Bisect Nodes` |
| 4 | `period_from_date` | Datetime | `timestamp` |  |  |
| 5 | `period_to_date` | Datetime | `timestamp` |  |  |
| 6 | `difference` | Float | `numeric(21,9)` |  |  |
| 7 | `balance_sheet_summary` | Float | `numeric(21,9)` |  |  |
| 8 | `profit_loss_summary` | Float | `numeric(21,9)` |  |  |
| 9 | `generated` | Check | `smallint` | default=0 |  |

**Referenced by (4):** `Bisect Accounting Statements`.`current_node`, `Bisect Nodes`.`root`, `Bisect Nodes`.`left_child`, `Bisect Nodes`.`right_child`

## Cheque Print Template

- **Table**: `tabCheque Print Template`  (proposed: `cheque_print_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:bank_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `has_print_format` | Check | `smallint` | ro, hidden, default=0 |  |
| 2 | `bank_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 3 | `cheque_size` | Select | `varchar(140)` | default=Regular | enum: Regular, A4 |
| 4 | `starting_position_from_top_edge` | Float | `numeric(21,2)` |  |  |
| 5 | `cheque_width` | Float | `numeric(21,2)` | default=20.00 |  |
| 6 | `cheque_height` | Float | `numeric(21,2)` | default=9.00 |  |
| 7 | `scanned_cheque` | Attach | `text` |  |  |
| 8 | `is_account_payable` | Check | `smallint` | default=1 |  |
| 9 | `acc_pay_dist_from_top_edge` | Float | `numeric(21,2)` | default=1.00 |  |
| 10 | `acc_pay_dist_from_left_edge` | Float | `numeric(21,2)` | default=9.00 |  |
| 11 | `message_to_show` | Data | `varchar(140)` | default=Acc. Payee |  |
| 12 | `date_dist_from_top_edge` | Float | `numeric(21,2)` | default=1.00 |  |
| 13 | `date_dist_from_left_edge` | Float | `numeric(21,2)` | default=15.00 |  |
| 14 | `payer_name_from_top_edge` | Float | `numeric(21,2)` | default=2.00 |  |
| 15 | `payer_name_from_left_edge` | Float | `numeric(21,2)` | default=3.00 |  |
| 16 | `amt_in_words_from_top_edge` | Float | `numeric(21,2)` | default=3.00 |  |
| 17 | `amt_in_words_from_left_edge` | Float | `numeric(21,2)` | default=4.00 |  |
| 18 | `amt_in_word_width` | Float | `numeric(21,2)` | default=15.00 |  |
| 19 | `amt_in_words_line_spacing` | Float | `numeric(21,2)` | default=0.50 |  |
| 20 | `amt_in_figures_from_top_edge` | Float | `numeric(21,2)` | default=3.50 |  |
| 21 | `amt_in_figures_from_left_edge` | Float | `numeric(21,2)` | default=16.00 |  |
| 22 | `acc_no_dist_from_top_edge` | Float | `numeric(21,2)` | default=5.00 |  |
| 23 | `acc_no_dist_from_left_edge` | Float | `numeric(21,2)` | default=4.00 |  |
| 24 | `signatory_from_top_edge` | Float | `numeric(21,2)` | default=6.00 |  |
| 25 | `signatory_from_left_edge` | Float | `numeric(21,2)` | default=15.00 |  |

## Coupon Code

- **Table**: `tabCoupon Code`  (proposed: `coupon_code`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:coupon_name`  (By fieldname)
- **Title field**: `coupon_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `coupon_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `coupon_type` | Select | `varchar(140)` | NOT NULL | enum: Promotional, Gift Card |
| 3 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 4 | `coupon_code` | Data | `varchar(140)` | UNIQUE |  |
| 5 | `pricing_rule` | Link | `varchar(140)` |  | → `Pricing Rule` |
| 6 | `valid_from` | Date | `date` |  |  |
| 7 | `valid_upto` | Date | `date` |  |  |
| 8 | `maximum_use` | Int | `integer` |  |  |
| 9 | `used` | Int | `integer` | ro, default=0 |  |
| 10 | `description` | Text Editor | `text` |  |  |
| 11 | `amended_from` | Link | `varchar(140)` | ro | → `Coupon Code` |
| 12 | `from_external_ecomm_platform` | Check | `smallint` | default=0 |  |

**Referenced by (5):** `Coupon Code`.`amended_from`, `POS Invoice`.`coupon_code`, `Sales Invoice`.`coupon_code`, `Quotation`.`coupon_code`, `Sales Order`.`coupon_code`

## Dunning Type

- **Table**: `tabDunning Type`  (proposed: `dunning_type`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: By script

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `dunning_type` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `dunning_fee` | Currency | `numeric(21,9)` |  |  |
| 3 | `rate_of_interest` | Float | `numeric(21,9)` |  |  |
| 4 | `is_default` | Check | `smallint` | default=0 |  |
| 5 | `income_account` | Link | `varchar(140)` |  | → `Account` |
| 6 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

**Child tables (1-N):**

- `dunning_letter_text` → `Dunning Letter Text` (line items)

**Referenced by (1):** `Dunning`.`dunning_type`

## Finance Book

- **Table**: `tabFinance Book`  (proposed: `finance_book`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:finance_book_name`
- **Search fields**: `finance_book_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `finance_book_name` | Data | `varchar(140)` | UNIQUE |  |

**Referenced by (15):** `Account Closing Balance`.`finance_book`, `GL Entry`.`finance_book`, `Journal Entry`.`finance_book`, `POS Invoice Item`.`finance_book`, `Payment Ledger Entry`.`finance_book`, `Process Statement Of Accounts`.`finance_book`, `Sales Invoice Item`.`finance_book`, `Asset`.`default_finance_book`, `Asset Capitalization`.`finance_book`, `Asset Capitalization Asset Item`.`finance_book`, `Asset Depreciation Schedule`.`finance_book`, `Asset Finance Book`.`finance_book`, `Asset Shift Allocation`.`finance_book`, `Asset Value Adjustment`.`finance_book`, `Company`.`default_finance_book`

## Financial Report Template

- **Table**: `tabFinancial Report Template`  (proposed: `financial_report_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:template_name`  (By fieldname)
- **Title field**: `template_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `template_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `report_type` | Select | `varchar(140)` | NOT NULL | enum: Profit and Loss Statement, Balance Sheet, Cash Flow, Custom Financial Statement |
| 3 | `module` | Link | `varchar(140)` |  | → `Module Def` *(frappe/Core)* |
| 4 | `disabled` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `rows` → `Financial Report Row` (line items)

## Fiscal Year

- **Table**: `tabFiscal Year`  (proposed: `fiscal_year`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:year`  (By fieldname)
- **Description**: Represents a Financial Year. All accounting entries and other major transactions are tracked against the Fiscal Year.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `year` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `disabled` | Check | `smallint` | default=0 |  |
| 3 | `year_start_date` | Date | `date` | NOT NULL |  |
| 4 | `year_end_date` | Date | `date` | NOT NULL |  |
| 5 | `auto_created` | Check | `smallint` | ro, hidden, default=0 |  |
| 6 | `is_short_year` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `companies` → `Fiscal Year Company` (line items)

**Referenced by (7):** `Budget`.`from_fiscal_year`, `Budget`.`to_fiscal_year`, `GL Entry`.`fiscal_year`, `Monthly Distribution`.`fiscal_year`, `Period Closing Voucher`.`fiscal_year`, `Lower Deduction Certificate`.`fiscal_year`, `Target Detail`.`fiscal_year`

## Item Tax Template

- **Table**: `tabItem Tax Template`  (proposed: `item_tax_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Title field**: `title`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `disabled` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `taxes` → `Item Tax Template Detail` (line items)

**Referenced by (10):** `POS Invoice Item`.`item_tax_template`, `Purchase Invoice Item`.`item_tax_template`, `Sales Invoice Item`.`item_tax_template`, `Purchase Order Item`.`item_tax_template`, `Supplier Quotation Item`.`item_tax_template`, `Quotation Item`.`item_tax_template`, `Sales Order Item`.`item_tax_template`, `Delivery Note Item`.`item_tax_template`, `Item Tax`.`item_tax_template`, `Purchase Receipt Item`.`item_tax_template`

## Journal Entry Template

- **Table**: `tabJournal Entry Template`  (proposed: `journal_entry_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:template_title`
- **Title field**: `template_title`
- **Search fields**: `voucher_type, company`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `voucher_type` | Select | `varchar(140)` | NOT NULL | enum: Journal Entry, Inter Company Journal Entry, Bank Entry, Cash Entry, Credit Card Entry, Debit Note, Credit Note, Contra Entry … (+5) |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `is_opening` | Select | `varchar(140)` | default=No | enum: No, Yes |
| 4 | `naming_series` | Select | `varchar(140)` | NOT NULL |  |
| 5 | `template_title` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 6 | `multi_currency` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `accounts` → `Journal Entry Template Account` (line items)

**Referenced by (1):** `Journal Entry`.`from_template`

## Ledger Health

- **Table**: `tabLedger Health`  (proposed: `ledger_health`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `autoincrement`  (Autoincrement)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `voucher_type` | Data | `varchar(140)` |  |  |
| 2 | `voucher_no` | Data | `varchar(140)` |  |  |
| 3 | `debit_credit_mismatch` | Check | `smallint` | default=0 |  |
| 4 | `checked_on` | Datetime | `timestamp` |  |  |
| 5 | `general_and_payment_ledger_mismatch` | Check | `smallint` | default=0 |  |

## Ledger Merge

- **Table**: `tabLedger Merge`  (proposed: `ledger_merge`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `format:{account_name} merger on {creation}`  (Expression)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `status` | Select | `varchar(140)` | ro | enum: Pending, Success, Partial Success, Error |
| 4 | `root_type` | Select | `varchar(140)` | NOT NULL | enum: Asset, Liability, Income, Expense, Equity |
| 5 | `account_name` | Data | `varchar(140)` | NOT NULL, ro, denorm←account.account_name |  |
| 6 | `is_group` | Check | `smallint` | ro, denorm←account.is_group, default=0 |  |

**Child tables (1-N):**

- `merge_accounts` → `Ledger Merge Accounts` (line items)

## Loyalty Point Entry

- **Table**: `tabLoyalty Point Entry`  (proposed: `loyalty_point_entry`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Title field**: `customer`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `loyalty_program` | Link | `varchar(140)` | NOT NULL | → `Loyalty Program` |
| 2 | `loyalty_program_tier` | Data | `varchar(140)` |  |  |
| 3 | `customer` | Link | `varchar(140)` | NOT NULL | → `Customer` |
| 4 | `redeem_against` | Link | `varchar(140)` |  | → `Loyalty Point Entry` |
| 5 | `loyalty_points` | Int | `integer` | NOT NULL |  |
| 6 | `purchase_amount` | Currency | `numeric(21,9)` |  |  |
| 7 | `expiry_date` | Date | `date` | NOT NULL |  |
| 8 | `posting_date` | Date | `date` | NOT NULL |  |
| 9 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 10 | `invoice_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 11 | `invoice` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `invoice_type` |
| 12 | `discretionary_reason` | Data | `varchar(140)` |  |  |

**Polymorphic references:**

- `invoice` — target DocType read from `invoice_type`

**Referenced by (1):** `Loyalty Point Entry`.`redeem_against`

## Loyalty Program

- **Table**: `tabLoyalty Program`  (proposed: `loyalty_program`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:loyalty_program_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `loyalty_program_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `loyalty_program_type` | Select | `varchar(140)` |  | enum: Single Tier Program, Multiple Tier Program |
| 3 | `from_date` | Date | `date` | NOT NULL |  |
| 4 | `to_date` | Date | `date` |  |  |
| 5 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 6 | `customer_territory` | Link | `varchar(140)` |  | → `Territory` |
| 7 | `auto_opt_in` | Check | `smallint` | default=0 |  |
| 8 | `conversion_factor` | Float | `numeric(21,9)` |  |  |
| 9 | `expiry_duration` | Int | `integer` |  |  |
| 10 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 11 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 12 | `company` | Link | `varchar(140)` |  | → `Company` |
| 13 | `project` | Link | `varchar(140)` |  | → `Project` |

**Child tables (1-N):**

- `collection_rules` → `Loyalty Program Collection` (line items)

**Referenced by (4):** `Loyalty Point Entry`.`loyalty_program`, `POS Invoice`.`loyalty_program`, `Sales Invoice`.`loyalty_program`, `Customer`.`loyalty_program`

## Mode of Payment

- **Table**: `tabMode of Payment`  (proposed: `mode_of_payment`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:mode_of_payment`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `mode_of_payment` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `type` | Select | `varchar(140)` |  | enum: Cash, Bank, General, Phone |
| 3 | `enabled` | Check | `smallint` | default=1 |  |

**Child tables (1-N):**

- `accounts` → `Mode of Payment Account` (line items)

**Referenced by (18):** `Cashier Closing Payments`.`mode_of_payment`, `Journal Entry`.`mode_of_payment`, `Overdue Payment`.`mode_of_payment`, `POS Closing Entry Detail`.`mode_of_payment`, `POS Opening Entry Detail`.`mode_of_payment`, `POS Payment Method`.`mode_of_payment`, `Payment Entry`.`mode_of_payment`, `Payment Order Reference`.`mode_of_payment`, `Payment Request`.`mode_of_payment`, `Payment Schedule`.`mode_of_payment`, `Payment Term`.`mode_of_payment`, `Payment Terms Template Detail`.`mode_of_payment`, `Purchase Invoice`.`mode_of_payment`, `Sales Invoice Payment`.`mode_of_payment`, `Employee Advance`.`mode_of_payment` … (+3 more)

## Monthly Distribution

- **Table**: `tabMonthly Distribution`  (proposed: `monthly_distribution`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:distribution_id`  (By fieldname)
- **Description**: Helps you distribute the Budget/Target across months if you have seasonality in your business.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `distribution_id` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `fiscal_year` | Link | `varchar(140)` | INDEX | → `Fiscal Year` |

**Child tables (1-N):**

- `percentages` → `Monthly Distribution Percentage` (line items)

**Referenced by (1):** `Target Detail`.`distribution_id`

## POS Profile

- **Table**: `tabPOS Profile`  (proposed: `pos_profile`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `Prompt`  (Set by user)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `disabled` | Check | `smallint` | default=0 |  |
| 2 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 3 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 4 | `country` | Read Only | `varchar(140)` | denorm←company.country |  |
| 5 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 6 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 7 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 8 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 9 | `selling_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 10 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 11 | `write_off_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 12 | `write_off_cost_center` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |
| 13 | `account_for_change_amount` | Link | `varchar(140)` |  | → `Account` |
| 14 | `income_account` | Link | `varchar(140)` |  | → `Account` |
| 15 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 16 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 17 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 18 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 19 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 20 | `print_format` | Link | `varchar(140)` |  | → `Print Format` *(frappe/Printing)* |
| 21 | `warehouse` | Link | `varchar(140)` | NOT NULL | → `Warehouse` |
| 22 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 23 | `update_stock` | Check | `smallint` | ro, hidden, default=1 |  |
| 24 | `hide_unavailable_items` | Check | `smallint` | default=0 |  |
| 25 | `hide_images` | Check | `smallint` | default=0 |  |
| 26 | `auto_add_item_to_cart` | Check | `smallint` | default=0 |  |
| 27 | `allow_rate_change` | Check | `smallint` | default=0 |  |
| 28 | `allow_discount_change` | Check | `smallint` | default=0 |  |
| 29 | `validate_stock_on_save` | Check | `smallint` | default=0 |  |
| 30 | `write_off_limit` | Currency | `numeric(21,9)` | NOT NULL, default=1 |  |
| 31 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 32 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 33 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 34 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 35 | `print_receipt_on_order_complete` | Check | `smallint` | default=0 |  |
| 36 | `project` | Link | `varchar(140)` |  | → `Project` |
| 37 | `set_grand_total_to_default_mop` | Check | `smallint` | default=1 |  |
| 38 | `action_on_new_invoice` | Select | `varchar(140)` | default=Always Ask | enum: Always Ask, Save Changes and Load New Invoice, Discard Changes and Load New Invoice |
| 39 | `allow_partial_payment` | Check | `smallint` | default=0 |  |
| 40 | `allow_warehouse_change` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `applicable_for_users` → `POS Profile User` (line items)
- `payments` → `POS Payment Method` (line items)
- `item_groups` → `POS Item Group` (line items)
- `customer_groups` → `POS Customer Group` (line items)

**Referenced by (4):** `POS Closing Entry`.`pos_profile`, `POS Invoice`.`pos_profile`, `POS Opening Entry`.`pos_profile`, `Sales Invoice`.`pos_profile`

## Party Link

- **Table**: `tabParty Link`  (proposed: `party_link`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-PT-LNK-.###.`
- **Title field**: `primary_party`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `primary_role` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 2 | `secondary_role` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 3 | `primary_party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `primary_role` |
| 4 | `secondary_party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `secondary_role` |

**Polymorphic references:**

- `primary_party` — target DocType read from `primary_role`
- `secondary_party` — target DocType read from `secondary_role`

## Payment Gateway Account

- **Table**: `tabPayment Gateway Account`  (proposed: `payment_gateway_account`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_gateway` | Link | `varchar(140)` | NOT NULL | → `Payment Gateway` *(payments/Payments)* |
| 2 | `is_default` | Check | `smallint` | default=0 |  |
| 3 | `payment_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 4 | `currency` | Read Only | `varchar(140)` | denorm←payment_account.account_currency |  |
| 5 | `message` | Small Text | `text` | default=Please click on the link |  |
| 6 | `payment_channel` | Select | `varchar(140)` | default=Email | enum: Email, Phone, Other |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

**Referenced by (3):** `Payment Request`.`payment_gateway_account`, `Subscription Plan`.`payment_gateway`, `Webshop Settings`.`payment_gateway_account`

## Payment Term

- **Table**: `tabPayment Term`  (proposed: `payment_term`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:payment_term_name`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_term_name` | Data | `varchar(140)` | UNIQUE |  |
| 2 | `invoice_portion` | Float | `numeric(21,9)` |  |  |
| 3 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 4 | `due_date_based_on` | Select | `varchar(140)` |  | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 5 | `credit_days` | Int | `integer` |  |  |
| 6 | `credit_months` | Int | `integer` |  |  |
| 7 | `description` | Small Text | `text` |  |  |
| 8 | `discount_type` | Select | `varchar(140)` | default=Percentage | enum: Percentage, Amount |
| 9 | `discount` | Float | `numeric(21,9)` |  |  |
| 10 | `discount_validity_based_on` | Select | `varchar(140)` | default=Day(s) after invoice dat | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 11 | `discount_validity` | Int | `integer` |  |  |

**Referenced by (5):** `Overdue Payment`.`payment_term`, `Payment Entry Reference`.`payment_term`, `Payment Reference`.`payment_term`, `Payment Schedule`.`payment_term`, `Payment Terms Template Detail`.`payment_term`

## Payment Terms Template

- **Table**: `tabPayment Terms Template`  (proposed: `payment_terms_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:template_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `template_name` | Data | `varchar(140)` | UNIQUE |  |
| 2 | `allocate_payment_based_on_payment_terms` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `terms` → `Payment Terms Template Detail` (line items)

**Referenced by (12):** `POS Invoice`.`payment_terms_template`, `Process Statement Of Accounts`.`payment_terms_template`, `Purchase Invoice`.`payment_terms_template`, `Sales Invoice`.`payment_terms_template`, `Purchase Order`.`payment_terms_template`, `Supplier`.`payment_terms`, `Customer`.`payment_terms`, `Quotation`.`payment_terms_template`, `Sales Order`.`payment_terms_template`, `Company`.`payment_terms`, `Customer Group`.`payment_terms`, `Supplier Group`.`payment_terms`

## Pricing Rule

- **Table**: `tabPricing Rule`  (proposed: `pricing_rule`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `title`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `disable` | Check | `smallint` | default=0 |  |
| 3 | `apply_on` | Select | `varchar(140)` | NOT NULL, default=Item Code | enum: Item Code, Item Group, Brand, Transaction |
| 4 | `price_or_product_discount` | Select | `varchar(140)` | NOT NULL | enum: Price, Product |
| 5 | `warehouse` | Link | `varchar(140)` | INDEX | → `Warehouse` |
| 6 | `mixed_conditions` | Check | `smallint` | default=0 |  |
| 7 | `is_cumulative` | Check | `smallint` | default=0 |  |
| 8 | `coupon_code_based` | Check | `smallint` | default=0 |  |
| 9 | `apply_rule_on_other` | Select | `varchar(140)` |  | enum: Item Code, Item Group, Brand |
| 10 | `other_item_code` | Link | `varchar(140)` |  | → `Item` |
| 11 | `other_item_group` | Link | `varchar(140)` |  | → `Item Group` |
| 12 | `other_brand` | Link | `varchar(140)` |  | → `Brand` |
| 13 | `selling` | Check | `smallint` | default=0 |  |
| 14 | `buying` | Check | `smallint` | default=0 |  |
| 15 | `applicable_for` | Select | `varchar(140)` |  | enum: Customer, Customer Group, Territory, Sales Partner, Campaign, Supplier, Supplier Group |
| 16 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 17 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 18 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 19 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 20 | `campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 21 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 22 | `supplier_group` | Link | `varchar(140)` |  | → `Supplier Group` |
| 23 | `min_qty` | Float | `numeric(21,9)` |  |  |
| 24 | `max_qty` | Float | `numeric(21,9)` |  |  |
| 25 | `min_amt` | Currency | `numeric(21,9)` | default=0 |  |
| 26 | `max_amt` | Currency | `numeric(21,9)` | default=0 |  |
| 27 | `valid_from` | Date | `date` | default=Today |  |
| 28 | `valid_upto` | Date | `date` |  |  |
| 29 | `company` | Link | `varchar(140)` |  | → `Company` |
| 30 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 31 | `margin_type` | Select | `varchar(140)` | default=Percentage | enum: Percentage, Amount |
| 32 | `margin_rate_or_amount` | Float | `numeric(21,9)` | default=0 |  |
| 33 | `rate_or_discount` | Select | `varchar(140)` | default=Discount Percentage | enum: Rate, Discount Percentage, Discount Amount |
| 34 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 35 | `rate` | Currency | `numeric(21,9)` | default=0 |  |
| 36 | `discount_amount` | Currency | `numeric(21,9)` | default=0 |  |
| 37 | `discount_percentage` | Float | `numeric(21,9)` |  |  |
| 38 | `for_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 39 | `same_item` | Check | `smallint` | default=0 |  |
| 40 | `free_item` | Link | `varchar(140)` |  | → `Item` |
| 41 | `free_qty` | Float | `numeric(21,9)` | default=0 |  |
| 42 | `free_item_uom` | Link | `varchar(140)` |  | → `UOM` |
| 43 | `free_item_rate` | Currency | `numeric(21,9)` |  |  |
| 44 | `threshold_percentage` | Percent | `numeric(21,9)` |  |  |
| 45 | `priority` | Select | `varchar(140)` |  | enum: 1, 2, 3, 4, 5, 6, 7, 8 … (+12) |
| 46 | `apply_multiple_pricing_rules` | Check | `smallint` | default=0 |  |
| 47 | `apply_discount_on_rate` | Check | `smallint` | default=0 |  |
| 48 | `validate_applied_rule` | Check | `smallint` | default=0 |  |
| 49 | `rule_description` | Small Text | `text` |  |  |
| 50 | `promotional_scheme_id` | Data | `varchar(140)` | ro, hidden |  |
| 51 | `promotional_scheme` | Link | `varchar(140)` | ro | → `Promotional Scheme` |
| 52 | `condition` | Code | `text` |  |  |
| 53 | `is_recursive` | Check | `smallint` | default=0 |  |
| 54 | `naming_series` | Select | `varchar(140)` | default=PRLE-.#### | enum: PRLE-.#### |
| 55 | `round_free_qty` | Check | `smallint` | default=0 |  |
| 56 | `recurse_for` | Float | `numeric(21,9)` |  |  |
| 57 | `apply_recursion_over` | Float | `numeric(21,9)` | default=0 |  |
| 58 | `has_priority` | Check | `smallint` | default=0 |  |
| 59 | `dont_enforce_free_item_qty` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `items` → `Pricing Rule Item Code` (line items)
- `item_groups` → `Pricing Rule Item Group` (line items)
- `brands` → `Pricing Rule Brand` (line items)

**Referenced by (2):** `Coupon Code`.`pricing_rule`, `Pricing Rule Detail`.`pricing_rule`

## Process Payment Reconciliation Log

- **Table**: `tabProcess Payment Reconciliation Log`  (proposed: `process_payment_reconciliation_log`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `format:PPR-LOG-{##}`  (Expression)
- **Search fields**: `allocated, reconciled, total_allocations, reconciled_entries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reconciled` | Check | `smallint` | ro, default=0 |  |
| 2 | `total_allocations` | Int | `integer` | ro |  |
| 3 | `allocated` | Check | `smallint` | ro, default=0 |  |
| 4 | `reconciled_entries` | Int | `integer` | ro |  |
| 5 | `error_log` | Long Text | `text` | ro |  |
| 6 | `process_pr` | Link | `varchar(140)` | NOT NULL, ro | → `Process Payment Reconciliation` |
| 7 | `status` | Select | `varchar(140)` | ro | enum: Running, Paused, Reconciled, Partially Reconciled, Failed, Cancelled |

**Child tables (1-N):**

- `allocations` → `Process Payment Reconciliation Log Allocations` (line items)

## Process Statement Of Accounts

- **Table**: `tabProcess Statement Of Accounts`  (proposed: `process_statement_of_accounts`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `Prompt`  (Set by user)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `frequency` | Select | `varchar(140)` |  | enum: Daily, Weekly, Biweekly, Monthly, Quarterly |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `from_date` | Date | `date` |  |  |
| 4 | `to_date` | Date | `date` |  |  |
| 5 | `customer_collection` | Select | `varchar(140)` |  | enum: Customer Group, Territory, Sales Partner, Sales Person |
| 6 | `collection_name` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `customer_collection` |
| 7 | `account` | Link | `varchar(140)` |  | → `Account` |
| 8 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 9 | `orientation` | Select | `varchar(140)` |  | enum: Landscape, Portrait |
| 10 | `start_date` | Date | `date` | default=Today |  |
| 11 | `currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 12 | `include_ageing` | Check | `smallint` | default=0 |  |
| 13 | `ageing_based_on` | Select | `varchar(140)` | default=Due Date | enum: Due Date, Posting Date |
| 14 | `enable_auto_email` | Check | `smallint` | default=0 |  |
| 15 | `primary_mandatory` | Check | `smallint` | default=1 |  |
| 16 | `filter_duration` | Int | `integer` | default=1 |  |
| 17 | `subject` | Data | `varchar(140)` |  |  |
| 18 | `body` | Text Editor | `text` |  |  |
| 19 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 20 | `terms_and_conditions` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 21 | `include_break` | Check | `smallint` | default=1 |  |
| 22 | `show_net_values_in_party_account` | Check | `smallint` | default=0 |  |
| 23 | `sender` | Link | `varchar(140)` |  | → `Email Account` *(frappe/Email)* |
| 24 | `report` | Select | `varchar(140)` | NOT NULL | enum: General Ledger, Accounts Receivable |
| 25 | `posting_date` | Date | `date` | default=Today |  |
| 26 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 27 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 28 | `sales_person` | Link | `varchar(140)` |  | → `Sales Person` |
| 29 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 30 | `based_on_payment_terms` | Check | `smallint` | default=0 |  |
| 31 | `pdf_name` | Data | `varchar(140)` |  |  |
| 32 | `ignore_exchange_rate_revaluation_journals` | Check | `smallint` | default=0 |  |
| 33 | `ignore_cr_dr_notes` | Check | `smallint` | default=0 |  |
| 34 | `show_remarks` | Check | `smallint` | default=0 |  |
| 35 | `categorize_by` | Select | `varchar(140)` | default=Categorize by Voucher (C | enum: Categorize by Voucher, Categorize by Voucher (Consolidated) |
| 36 | `show_future_payments` | Check | `smallint` | default=0 |  |
| 37 | `print_format` | Link | `varchar(140)` |  | → `Print Format` *(frappe/Printing)* |
| 38 | `show_opening_entries` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `cost_center` → `PSOA Cost Center` (multi-select)
- `project` → `PSOA Project` (multi-select)
- `cc_to` → `Process Statement Of Accounts CC` (multi-select)
- `customers` → `Process Statement Of Accounts Customer` (line items)

**Polymorphic references:**

- `collection_name` — target DocType read from `customer_collection`

## Promotional Scheme

- **Table**: `tabPromotional Scheme`  (proposed: `promotional_scheme`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `Prompt`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `apply_on` | Select | `varchar(140)` | NOT NULL, default=Item Code | enum: Item Code, Item Group, Brand, Transaction |
| 2 | `disable` | Check | `smallint` | default=0 |  |
| 3 | `mixed_conditions` | Check | `smallint` | default=0 |  |
| 4 | `is_cumulative` | Check | `smallint` | default=0 |  |
| 5 | `apply_rule_on_other` | Select | `varchar(140)` |  | enum: Item Code, Item Group, Brand |
| 6 | `other_item_code` | Link | `varchar(140)` |  | → `Item` |
| 7 | `other_item_group` | Link | `varchar(140)` |  | → `Item Group` |
| 8 | `other_brand` | Link | `varchar(140)` |  | → `Brand` |
| 9 | `selling` | Check | `smallint` | default=0 |  |
| 10 | `buying` | Check | `smallint` | default=0 |  |
| 11 | `applicable_for` | Select | `varchar(140)` |  | enum: Customer, Customer Group, Territory, Sales Partner, Campaign, Supplier, Supplier Group |
| 12 | `valid_from` | Date | `date` | default=Today |  |
| 13 | `valid_upto` | Date | `date` |  |  |
| 14 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 15 | `currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |

**Child tables (1-N):**

- `items` → `Pricing Rule Item Code` (line items)
- `item_groups` → `Pricing Rule Item Group` (line items)
- `brands` → `Pricing Rule Brand` (line items)
- `customer` → `Customer Item` (multi-select)
- `customer_group` → `Customer Group Item` (multi-select)
- `territory` → `Territory Item` (multi-select)
- `sales_partner` → `Sales Partner Item` (multi-select)
- `campaign` → `Campaign Item` (multi-select)
- `supplier` → `Supplier Item` (multi-select)
- `supplier_group` → `Supplier Group Item` (multi-select)
- `price_discount_slabs` → `Promotional Scheme Price Discount` (line items)
- `product_discount_slabs` → `Promotional Scheme Product Discount` (line items)

**Referenced by (1):** `Pricing Rule`.`promotional_scheme`

## Purchase Taxes and Charges Template

- **Table**: `tabPurchase Taxes and Charges Template`  (proposed: `purchase_taxes_and_charges_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Title field**: `title`
- **Description**: Standard tax template that can be applied to all Purchase Transactions. This template can contain a list of tax heads and also other expense heads like "Shipping", "Insurance", "Handling", etc.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `is_default` | Check | `smallint` | default=0 |  |
| 3 | `disabled` | Check | `smallint` | default=0 |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |

**Child tables (1-N):**

- `taxes` → `Purchase Taxes and Charges` (line items)

**Referenced by (7):** `Payment Entry`.`purchase_taxes_and_charges_template`, `Purchase Invoice`.`taxes_and_charges`, `Subscription`.`purchase_tax_template`, `Tax Rule`.`purchase_tax_template`, `Purchase Order`.`taxes_and_charges`, `Supplier Quotation`.`taxes_and_charges`, `Purchase Receipt`.`taxes_and_charges`

## Sales Taxes and Charges Template

- **Table**: `tabSales Taxes and Charges Template`  (proposed: `sales_taxes_and_charges_template`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Title field**: `title`
- **Description**: Standard tax template that can be applied to all Sales Transactions. This template can contain a list of tax heads and also other expense/income heads like "Shipping", "Insurance", "Handling" etc.

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `is_default` | Check | `smallint` | default=0 |  |
| 3 | `disabled` | Check | `smallint` | default=0 |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |

**Child tables (1-N):**

- `taxes` → `Sales Taxes and Charges` (line items)

**Referenced by (9):** `POS Invoice`.`taxes_and_charges`, `POS Profile`.`taxes_and_charges`, `Payment Entry`.`sales_taxes_and_charges_template`, `Sales Invoice`.`taxes_and_charges`, `Subscription`.`sales_tax_template`, `Tax Rule`.`sales_tax_template`, `Quotation`.`taxes_and_charges`, `Sales Order`.`taxes_and_charges`, `Delivery Note`.`taxes_and_charges`

## Share Type

- **Table**: `tabShare Type`  (proposed: `share_type`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:title`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `description` | Long Text | `text` |  |  |

**Referenced by (2):** `Share Balance`.`share_type`, `Share Transfer`.`share_type`

## Shareholder

- **Table**: `tabShareholder`  (proposed: `shareholder`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `title`
- **Search fields**: `folio_no`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `naming_series` | Select | `varchar(140)` |  | enum: ACC-SH-.YYYY.- |
| 3 | `folio_no` | Data | `varchar(140)` | UNIQUE, ro |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `is_company` | Check | `smallint` | ro, hidden, default=0 |  |
| 6 | `contact_list` | Code | `text` | ro, hidden |  |

**Child tables (1-N):**

- `share_balance` → `Share Balance` (line items)

**Referenced by (2):** `Share Transfer`.`from_shareholder`, `Share Transfer`.`to_shareholder`

## Shipping Rule

- **Table**: `tabShipping Rule`  (proposed: `shipping_rule`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:label`  (By fieldname)
- **Description**: Specify conditions to calculate shipping amount

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `label` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `disabled` | Check | `smallint` | default=0 |  |
| 3 | `shipping_rule_type` | Select | `varchar(140)` |  | enum: Selling, Buying |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 6 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 7 | `calculate_based_on` | Select | `varchar(140)` | default=Fixed | enum: Fixed, Net Total, Net Weight |
| 8 | `shipping_amount` | Currency | `numeric(21,9)` |  |  |
| 9 | `project` | Link | `varchar(140)` |  | → `Project` |

**Child tables (1-N):**

- `conditions` → `Shipping Rule Condition` (line items)
- `countries` → `Shipping Rule Country` (line items)

**Referenced by (9):** `POS Invoice`.`shipping_rule`, `Purchase Invoice`.`shipping_rule`, `Sales Invoice`.`shipping_rule`, `Purchase Order`.`shipping_rule`, `Supplier Quotation`.`shipping_rule`, `Quotation`.`shipping_rule`, `Sales Order`.`shipping_rule`, `Delivery Note`.`shipping_rule`, `Purchase Receipt`.`shipping_rule`

## Subscription

- **Table**: `tabSubscription`  (proposed: `subscription`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-SUB-.YYYY.-.#####`  (Expression)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `status` | Select | `varchar(140)` | ro | enum: Trialing, Active, Grace Period, Cancelled, Unpaid, Completed, Refunded |
| 2 | `cancelation_date` | Date | `date` | ro |  |
| 3 | `trial_period_start` | Date | `date` |  |  |
| 4 | `trial_period_end` | Date | `date` |  |  |
| 5 | `current_invoice_start` | Date | `date` | ro |  |
| 6 | `current_invoice_end` | Date | `date` | ro |  |
| 7 | `next_billing_period_start` | Date | `date` | ro |  |
| 8 | `next_billing_period_end` | Date | `date` | ro |  |
| 9 | `days_until_due` | Int | `integer` | default=0 |  |
| 10 | `cancel_at_period_end` | Check | `smallint` | default=0 |  |
| 11 | `apply_additional_discount` | Select | `varchar(140)` |  | enum: Grand Total, Net Total |
| 12 | `additional_discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 13 | `additional_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 14 | `party_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 15 | `party` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `party_type` |
| 16 | `sales_tax_template` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 17 | `purchase_tax_template` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 18 | `follow_calendar_months` | Check | `smallint` | default=0 |  |
| 19 | `generate_new_invoices_past_due_date` | Check | `smallint` | default=0 |  |
| 20 | `end_date` | Date | `date` |  |  |
| 21 | `start_date` | Date | `date` |  |  |
| 22 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 23 | `company` | Link | `varchar(140)` |  | → `Company` |
| 24 | `submit_invoice` | Check | `smallint` | default=1 |  |
| 25 | `generate_invoice_at` | Select | `varchar(140)` | NOT NULL, default=Postpaid (bill at period | enum: Postpaid (bill at period end), Prepaid (bill at period start), Bill N days before period start |
| 26 | `number_of_days` | Int | `integer` |  |  |

**Child tables (1-N):**

- `plans` → `Subscription Plan Detail` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (3):** `Process Subscription`.`subscription`, `Purchase Invoice`.`subscription`, `Sales Invoice`.`subscription`

## Subscription Plan

- **Table**: `tabSubscription Plan`  (proposed: `subscription_plan`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:plan_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `plan_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 3 | `item` | Link | `varchar(140)` | NOT NULL | → `Item` |
| 4 | `price_determination` | Select | `varchar(140)` | NOT NULL | enum: Fixed Rate, Based On Price List, Monthly Rate |
| 5 | `cost` | Currency | `numeric(21,9)` |  |  |
| 6 | `price_list` | Link | `varchar(140)` |  | → `Price List` |
| 7 | `billing_interval` | Select | `varchar(140)` | NOT NULL, default=Day | enum: Day, Week, Month, Year |
| 8 | `billing_interval_count` | Int | `integer` | NOT NULL, default=1 |  |
| 9 | `payment_gateway` | Link | `varchar(140)` |  | → `Payment Gateway Account` |
| 10 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 11 | `product_price_id` | Data | `varchar(140)` |  |  |

**Referenced by (1):** `Subscription Plan Detail`.`plan`

## Tax Category

- **Table**: `tabTax Category`  (proposed: `tax_category`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:title`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |
| 2 | `disabled` | Check | `smallint` | default=0 |  |

**Referenced by (16):** `POS Invoice`.`tax_category`, `POS Profile`.`tax_category`, `Purchase Invoice`.`tax_category`, `Purchase Taxes and Charges Template`.`tax_category`, `Sales Invoice`.`tax_category`, `Sales Taxes and Charges Template`.`tax_category`, `Tax Rule`.`tax_category`, `Purchase Order`.`tax_category`, `Supplier`.`tax_category`, `Supplier Quotation`.`tax_category`, `Customer`.`tax_category`, `Quotation`.`tax_category`, `Sales Order`.`tax_category`, `Delivery Note`.`tax_category`, `Item Tax`.`tax_category` … (+1 more)

## Tax Rule

- **Table**: `tabTax Rule`  (proposed: `tax_rule`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-TAX-RULE-.YYYY.-.#####`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `tax_type` | Select | `varchar(140)` | default=Sales | enum: Sales, Purchase |
| 2 | `use_for_shopping_cart` | Check | `smallint` | default=1 |  |
| 3 | `sales_tax_template` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 4 | `purchase_tax_template` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 5 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 6 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 7 | `item` | Link | `varchar(140)` |  | → `Item` |
| 8 | `billing_city` | Data | `varchar(140)` |  |  |
| 9 | `billing_county` | Data | `varchar(140)` |  |  |
| 10 | `billing_state` | Data | `varchar(140)` |  |  |
| 11 | `billing_zipcode` | Data | `varchar(140)` |  |  |
| 12 | `billing_country` | Link | `varchar(140)` |  | → `Country` *(frappe/Geo)* |
| 13 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 14 | `customer_group` | Link | `varchar(140)` | denorm←customer.customer_group | → `Customer Group` |
| 15 | `supplier_group` | Link | `varchar(140)` | denorm←supplier.supplier_group | → `Supplier Group` |
| 16 | `item_group` | Link | `varchar(140)` |  | → `Item Group` |
| 17 | `shipping_city` | Data | `varchar(140)` |  |  |
| 18 | `shipping_county` | Data | `varchar(140)` |  |  |
| 19 | `shipping_state` | Data | `varchar(140)` |  |  |
| 20 | `shipping_zipcode` | Data | `varchar(140)` |  |  |
| 21 | `shipping_country` | Link | `varchar(140)` |  | → `Country` *(frappe/Geo)* |
| 22 | `from_date` | Date | `date` |  |  |
| 23 | `to_date` | Date | `date` |  |  |
| 24 | `priority` | Int | `integer` | default=1 |  |
| 25 | `company` | Link | `varchar(140)` |  | → `Company` |

## Tax Withholding Category

- **Table**: `tabTax Withholding Category`  (proposed: `tax_withholding_category`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `Prompt`  (Set by user)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `category_name` | Data | `varchar(140)` |  |  |
| 2 | `tax_on_excess_amount` | Check | `smallint` | default=0 |  |
| 3 | `round_off_tax_amount` | Check | `smallint` | default=0 |  |
| 4 | `tax_deduction_basis` | Select | `varchar(140)` | NOT NULL, default=Net Total | enum: Gross Total, Net Total |
| 5 | `disable_cumulative_threshold` | Check | `smallint` | default=0 |  |
| 6 | `disable_transaction_threshold` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `rates` → `Tax Withholding Rate` (line items)
- `accounts` → `Tax Withholding Account` (line items)

**Referenced by (10):** `Journal Entry`.`tax_withholding_category`, `Payment Entry`.`tax_withholding_category`, `Purchase Invoice Item`.`tax_withholding_category`, `Sales Invoice Item`.`tax_withholding_category`, `Tax Withholding Entry`.`tax_withholding_category`, `Supplier`.`tax_withholding_category`, `Lower Deduction Certificate`.`tax_withholding_category`, `Customer`.`tax_withholding_category`, `Item`.`purchase_tax_withholding_category`, `Item`.`sales_tax_withholding_category`

## Tax Withholding Group

- **Table**: `tabTax Withholding Group`  (proposed: `tax_withholding_group`)
- **Kind**: Master
- **Owned by**: erpnext / Accounts
- **Naming**: `field:group_name`  (By fieldname)

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `group_name` | Data | `varchar(140)` | NOT NULL, UNIQUE |  |

**Referenced by (8):** `Journal Entry`.`tax_withholding_group`, `Payment Entry`.`tax_withholding_group`, `Purchase Invoice`.`tax_withholding_group`, `Sales Invoice`.`tax_withholding_group`, `Tax Withholding Entry`.`tax_withholding_group`, `Tax Withholding Rate`.`tax_withholding_group`, `Supplier`.`tax_withholding_group`, `Customer`.`tax_withholding_group`

---

# Tree master (hierarchy)s

## Account

- **Table**: `tabAccount`  (proposed: `account`)
- **Kind**: Tree master (hierarchy)
- **Owned by**: erpnext / Accounts
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: Heads (or groups) against which Accounting Entries are made and balances are maintained.
- **Search fields**: `account_number`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `account_number` | Data | `varchar(140)` |  |  |
| 3 | `is_group` | Check | `smallint` | default=0 |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL, denorm←parent_account.company | → `Company` |
| 5 | `root_type` | Select | `varchar(140)` | ro | enum: Asset, Liability, Income, Expense, Equity |
| 6 | `report_type` | Select | `varchar(140)` | ro | enum: Balance Sheet, Profit and Loss |
| 7 | `account_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 8 | `parent_account` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 9 | `account_type` | Select | `varchar(140)` | INDEX | enum: Accumulated Depreciation, Asset Received But Not Billed, Bank, Cash, Chargeable, Capital Work in Progress, Cost of Goods Sold, Current Asset … (+24) |
| 10 | `tax_rate` | Float | `numeric(21,9)` |  |  |
| 11 | `freeze_account` | Select | `varchar(140)` |  | enum: No, Yes |
| 12 | `balance_must_be` | Select | `varchar(140)` |  | enum: Debit, Credit |
| 13 | `lft` | Int | `integer` | INDEX, ro, hidden |  |
| 14 | `rgt` | Int | `integer` | INDEX, ro, hidden |  |
| 15 | `old_parent` | Data | `varchar(140)` | ro, hidden |  |
| 16 | `include_in_gross` | Check | `smallint` | default=0 |  |
| 17 | `disabled` | Check | `smallint` | default=0 |  |
| 18 | `account_category` | Link | `varchar(140)` |  | → `Account Category` |

**Referenced by (187):** `Account`.`parent_account`, `Account Closing Balance`.`account`, `Accounting Dimension Detail`.`offsetting_account`, `Advance Taxes and Charges`.`account_head`, `Applicable On Account`.`applicable_on_account`, `Bank Account`.`account`, `Bank Clearance`.`account`, `Bank Guarantee`.`account`, `Bank Transaction Rule`.`account`, `Bank Transaction Rule Accounts`.`account`, `Budget`.`account`, `Budget Account`.`account`, `Discounted Invoice`.`debit_to`, `Dunning`.`income_account`, `Dunning Type`.`income_account` … (+172 more)

## Cost Center

- **Table**: `tabCost Center`  (proposed: `cost_center`)
- **Kind**: Tree master (hierarchy)
- **Owned by**: erpnext / Accounts
- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)
- **Description**: Track separate Income and Expense for product verticals or divisions.
- **Search fields**: `parent_cost_center, is_group`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `cost_center_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `cost_center_number` | Data | `varchar(140)` |  |  |
| 3 | `parent_cost_center` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `is_group` | Check | `smallint` | default=0 |  |
| 6 | `lft` | Int | `integer` | INDEX, hidden |  |
| 7 | `rgt` | Int | `integer` | INDEX, hidden |  |
| 8 | `old_parent` | Link | `varchar(140)` | hidden | → `Cost Center` |
| 9 | `disabled` | Check | `smallint` | default=0 |  |

**Referenced by (84):** `Account Closing Balance`.`cost_center`, `Advance Taxes and Charges`.`cost_center`, `Budget`.`cost_center`, `Cost Center`.`parent_cost_center`, `Cost Center`.`old_parent`, `Cost Center Allocation`.`main_cost_center`, `Cost Center Allocation Percentage`.`cost_center`, `Dunning`.`cost_center`, `Dunning Type`.`cost_center`, `GL Entry`.`cost_center`, `Journal Entry Account`.`cost_center`, `Journal Entry Template Account`.`cost_center`, `Loyalty Program`.`cost_center`, `Opening Invoice Creation Tool`.`cost_center`, `Opening Invoice Creation Tool Item`.`cost_center` … (+69 more)

---

# Transaction (submittable)s

## Account Closing Balance

- **Table**: `tabAccount Closing Balance`  (proposed: `account_closing_balance`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `closing_date` | Date | `date` | INDEX |  |
| 2 | `account` | Link | `varchar(140)` | INDEX | → `Account` |
| 3 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 4 | `debit` | Currency | `numeric(21,9)` |  |  |
| 5 | `credit` | Currency | `numeric(21,9)` |  |  |
| 6 | `account_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 7 | `debit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 8 | `credit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 9 | `project` | Link | `varchar(140)` |  | → `Project` |
| 10 | `company` | Link | `varchar(140)` | INDEX | → `Company` |
| 11 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 12 | `period_closing_voucher` | Link | `varchar(140)` | INDEX | → `Period Closing Voucher` |
| 13 | `is_period_closing_voucher_entry` | Check | `smallint` | default=0 |  |
| 14 | `debit_in_reporting_currency` | Currency | `numeric(21,9)` |  |  |
| 15 | `credit_in_reporting_currency` | Currency | `numeric(21,9)` |  |  |
| 16 | `reporting_currency_exchange_rate` | Float | `numeric(21,9)` |  |  |

## Advance Payment Ledger Entry

- **Table**: `tabAdvance Payment Ledger Entry`  (proposed: `advance_payment_ledger_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `voucher_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `voucher_no` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `voucher_type` |
| 3 | `against_voucher_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 4 | `against_voucher_no` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `against_voucher_type` |
| 5 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 7 | `event` | Data | `varchar(140)` | ro |  |
| 8 | `company` | Link | `varchar(140)` | ro | → `Company` |
| 9 | `delinked` | Check | `smallint` | ro, default=0 |  |
| 10 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `exchange_rate` | Float | `numeric(21,9)` | ro |  |

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`
- `against_voucher_no` — target DocType read from `against_voucher_type`

## Bank Guarantee

- **Table**: `tabBank Guarantee`  (proposed: `bank_guarantee`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-BG-.YYYY.-.#####`  (Expression)
- **Title field**: `customer`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `customer`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `bg_type` | Select | `varchar(140)` | NOT NULL | enum: Receiving, Providing |
| 2 | `reference_doctype` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 3 | `reference_docname` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `reference_doctype` |
| 4 | `customer` | Link | `varchar(140)` |  | → `Customer` |
| 5 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |
| 6 | `project` | Link | `varchar(140)` |  | → `Project` |
| 7 | `amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 8 | `start_date` | Date | `date` | NOT NULL |  |
| 9 | `validity` | Int | `integer` |  |  |
| 10 | `end_date` | Date | `date` | ro |  |
| 11 | `bank` | Link | `varchar(140)` |  | → `Bank` |
| 12 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 13 | `account` | Link | `varchar(140)` | ro | → `Account` |
| 14 | `bank_account_no` | Data | `varchar(140)` | ro |  |
| 15 | `iban` | Data | `varchar(140)` | ro |  |
| 16 | `branch_code` | Data | `varchar(140)` | ro |  |
| 17 | `swift_number` | Data | `varchar(140)` | ro |  |
| 18 | `more_information` | Text Editor | `text` |  |  |
| 19 | `bank_guarantee_number` | Data | `varchar(140)` | UNIQUE |  |
| 20 | `name_of_beneficiary` | Data | `varchar(140)` |  |  |
| 21 | `margin_money` | Currency | `numeric(21,9)` |  |  |
| 22 | `charges` | Currency | `numeric(21,9)` |  |  |
| 23 | `fixed_deposit_number` | Data | `varchar(140)` |  |  |
| 24 | `amended_from` | Link | `varchar(140)` | ro | → `Bank Guarantee` |

**Polymorphic references:**

- `reference_docname` — target DocType read from `reference_doctype`

**Referenced by (1):** `Bank Guarantee`.`amended_from`

## Bank Transaction

- **Table**: `tabBank Transaction`  (proposed: `bank_transaction`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `bank_account`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL, default=ACC-BTN-.YYYY.- | enum: ACC-BTN-.YYYY.- |
| 2 | `date` | Date | `date` |  |  |
| 3 | `status` | Select | `varchar(140)` | default=Pending | enum: Pending, Settled, Unreconciled, Reconciled, Cancelled |
| 4 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 5 | `company` | Link | `varchar(140)` | ro, denorm←bank_account.company | → `Company` |
| 6 | `currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 7 | `description` | Small Text | `text` |  |  |
| 8 | `reference_number` | Small Text | `text` |  |  |
| 9 | `transaction_id` | Data | `varchar(140)` | ro |  |
| 10 | `allocated_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `amended_from` | Link | `varchar(140)` | ro | → `Bank Transaction` |
| 12 | `unallocated_amount` | Currency | `numeric(21,9)` | ro |  |
| 13 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 14 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 15 | `deposit` | Currency | `numeric(21,9)` |  |  |
| 16 | `withdrawal` | Currency | `numeric(21,9)` |  |  |
| 17 | `transaction_type` | Data | `varchar(140)` |  |  |
| 18 | `bank_party_name` | Data | `varchar(140)` |  |  |
| 19 | `bank_party_iban` | Data | `varchar(140)` |  |  |
| 20 | `bank_party_account_number` | Data | `varchar(140)` |  |  |
| 21 | `included_fee` | Currency | `numeric(21,9)` |  |  |
| 22 | `excluded_fee` | Currency | `numeric(21,9)` |  |  |
| 23 | `is_rule_evaluated` | Check | `smallint` | ro, default=0 |  |
| 24 | `matched_transaction_rule` | Link | `varchar(140)` | ro | → `Bank Transaction Rule` |

**Child tables (1-N):**

- `payment_entries` → `Bank Transaction Payments` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (1):** `Bank Transaction`.`amended_from`

## Budget

- **Table**: `tabBudget`  (proposed: `budget`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `budget_against` | Select | `varchar(140)` | NOT NULL, default=Cost Center | enum: Cost Center, Project |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 4 | `project` | Link | `varchar(140)` |  | → `Project` |
| 5 | `amended_from` | Link | `varchar(140)` | ro | → `Budget` |
| 6 | `applicable_on_material_request` | Check | `smallint` | default=0 |  |
| 7 | `action_if_annual_budget_exceeded_on_mr` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn, Ignore |
| 8 | `action_if_accumulated_monthly_budget_exceeded_on_mr` | Select | `varchar(140)` | default=Warn | enum: Stop, Warn, Ignore |
| 9 | `applicable_on_purchase_order` | Check | `smallint` | default=0 |  |
| 10 | `action_if_annual_budget_exceeded_on_po` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn, Ignore |
| 11 | `action_if_accumulated_monthly_budget_exceeded_on_po` | Select | `varchar(140)` | default=Warn | enum: Stop, Warn, Ignore |
| 12 | `applicable_on_booking_actual_expenses` | Check | `smallint` | default=0 |  |
| 13 | `action_if_annual_budget_exceeded` | Select | `varchar(140)` | default=Stop | enum: Stop, Warn, Ignore |
| 14 | `action_if_accumulated_monthly_budget_exceeded` | Select | `varchar(140)` | default=Warn | enum: Stop, Warn, Ignore |
| 15 | `naming_series` | Select | `varchar(140)` | NOT NULL, default=BUDGET-.######## | enum: BUDGET-.######## |
| 16 | `applicable_on_cumulative_expense` | Check | `smallint` | default=0 |  |
| 17 | `action_if_annual_exceeded_on_cumulative_expense` | Select | `varchar(140)` |  | enum: Stop, Warn, Ignore |
| 18 | `action_if_accumulated_monthly_exceeded_on_cumulative_expense` | Select | `varchar(140)` |  | enum: Stop, Warn, Ignore |
| 19 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 20 | `budget_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 21 | `revision_of` | Data | `varchar(140)` | ro |  |
| 22 | `distribute_equally` | Check | `smallint` | default=1 |  |
| 23 | `from_fiscal_year` | Link | `varchar(140)` | NOT NULL | → `Fiscal Year` |
| 24 | `to_fiscal_year` | Link | `varchar(140)` | NOT NULL | → `Fiscal Year` |
| 25 | `budget_start_date` | Date | `date` | hidden |  |
| 26 | `budget_end_date` | Date | `date` | hidden |  |
| 27 | `distribution_frequency` | Select | `varchar(140)` | NOT NULL, default=Monthly | enum: Monthly, Quarterly, Half-Yearly, Yearly |
| 28 | `budget_distribution_total` | Currency | `numeric(21,9)` | ro |  |

**Child tables (1-N):**

- `budget_distribution` → `Budget Distribution` (line items)

**Referenced by (1):** `Budget`.`amended_from`

## Cashier Closing

- **Table**: `tabCashier Closing`  (proposed: `cashier_closing`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | ro, default=POS-CLO- | enum: POS-CLO- |
| 2 | `user` | Link | `varchar(140)` | NOT NULL, ro | → `User` *(frappe/Core)* |
| 3 | `date` | Date | `date` | ro, default=Today |  |
| 4 | `from_time` | Time | `time(6)` | NOT NULL |  |
| 5 | `time` | Time | `time(6)` | NOT NULL |  |
| 6 | `expense` | Float | `numeric(21,9)` | default=0.00 |  |
| 7 | `custody` | Float | `numeric(21,9)` | default=0.00 |  |
| 8 | `returns` | Float | `numeric(21,2)` | default=0.00 |  |
| 9 | `outstanding_amount` | Float | `numeric(21,9)` | ro, default=0.00 |  |
| 10 | `net_amount` | Float | `numeric(21,9)` | ro |  |
| 11 | `amended_from` | Link | `varchar(140)` | ro | → `Cashier Closing` |

**Child tables (1-N):**

- `payments` → `Cashier Closing Payments` (line items)

**Referenced by (1):** `Cashier Closing`.`amended_from`

## Cost Center Allocation

- **Table**: `tabCost Center Allocation`  (proposed: `cost_center_allocation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `CC-ALLOC-.#####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `main_cost_center` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |
| 2 | `valid_from` | Date | `date` | NOT NULL, default=Today |  |
| 3 | `company` | Link | `varchar(140)` | NOT NULL, denorm←main_cost_center.company | → `Company` |
| 4 | `amended_from` | Link | `varchar(140)` | ro | → `Cost Center Allocation` |

**Child tables (1-N):**

- `allocation_percentages` → `Cost Center Allocation Percentage` (line items)

**Referenced by (1):** `Cost Center Allocation`.`amended_from`

## Dunning

- **Table**: `tabDunning`  (proposed: `dunning`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `naming_series` | Select | `varchar(140)` | default=DUNN-.MM.-.YY.- | enum: DUNN-.MM.-.YY.- |
| 3 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 4 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 5 | `dunning_type` | Link | `varchar(140)` |  | → `Dunning Type` |
| 6 | `dunning_fee` | Currency | `numeric(21,2)` | denorm←dunning_type.dunning_fee, default=0 |  |
| 7 | `language` | Link | `varchar(140)` |  | → `Language` *(frappe/Core)* |
| 8 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 9 | `amended_from` | Link | `varchar(140)` | ro | → `Dunning` |
| 10 | `body_text` | Text Editor | `text` |  |  |
| 11 | `closing_text` | Text Editor | `text` |  |  |
| 12 | `posting_time` | Time | `time(6)` |  |  |
| 13 | `rate_of_interest` | Float | `numeric(21,9)` | denorm←dunning_type.rate_of_interest, default=0 |  |
| 14 | `address_display` | Text Editor | `text` | ro |  |
| 15 | `contact_display` | Small Text | `text` | ro |  |
| 16 | `contact_mobile` | Small Text | `text` | ro |  |
| 17 | `company_address_display` | Text Editor | `text` | ro |  |
| 18 | `contact_email` | Data | `varchar(140)` | ro |  |
| 19 | `customer` | Link | `varchar(140)` | NOT NULL | → `Customer` |
| 20 | `grand_total` | Currency | `numeric(21,2)` | ro, default=0 |  |
| 21 | `status` | Select | `varchar(140)` | ro, default=Unresolved | enum: Draft, Resolved, Unresolved, Cancelled |
| 22 | `income_account` | Link | `varchar(140)` | denorm←dunning_type.income_account | → `Account` |
| 23 | `total_interest` | Currency | `numeric(21,2)` | ro, default=0 |  |
| 24 | `total_outstanding` | Currency | `numeric(21,9)` | ro |  |
| 25 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 26 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 27 | `dunning_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 28 | `cost_center` | Link | `varchar(140)` | denorm←dunning_type.cost_center | → `Cost Center` |
| 29 | `spacer` | Data | `varchar(140)` | ro, hidden |  |
| 30 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 31 | `currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 32 | `conversion_rate` | Float | `numeric(21,9)` |  |  |
| 33 | `base_dunning_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |

**Child tables (1-N):**

- `overdue_payments` → `Overdue Payment` (line items)

**Referenced by (1):** `Dunning`.`amended_from`

## Exchange Rate Revaluation

- **Table**: `tabExchange Rate Revaluation`  (proposed: `exchange_rate_revaluation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-ERR-.YYYY.-.#####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `amended_from` | Link | `varchar(140)` | ro | → `Exchange Rate Revaluation` |
| 4 | `gain_loss_unbooked` | Currency | `numeric(21,9)` | ro |  |
| 5 | `gain_loss_booked` | Currency | `numeric(21,9)` | ro |  |
| 6 | `total_gain_loss` | Currency | `numeric(21,9)` | ro |  |
| 7 | `rounding_loss_allowance` | Float | `numeric(21,9)` | default=0.05 |  |

**Child tables (1-N):**

- `accounts` → `Exchange Rate Revaluation Account` (line items)

**Referenced by (1):** `Exchange Rate Revaluation`.`amended_from`

## GL Entry

- **Table**: `tabGL Entry`  (proposed: `gl_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-GLE-.YYYY.-.#####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `voucher_no,account,posting_date,against_voucher`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | INDEX |  |
| 2 | `transaction_date` | Date | `date` |  |  |
| 3 | `account` | Link | `varchar(140)` | INDEX | → `Account` |
| 4 | `party_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 5 | `party` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `party_type` |
| 6 | `cost_center` | Link | `varchar(140)` | INDEX | → `Cost Center` |
| 7 | `debit` | Currency | `numeric(21,9)` |  |  |
| 8 | `credit` | Currency | `numeric(21,9)` |  |  |
| 9 | `account_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 10 | `debit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 11 | `credit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 12 | `against` | Text | `text` |  |  |
| 13 | `against_voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 14 | `against_voucher` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `against_voucher_type` |
| 15 | `voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 16 | `voucher_no` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `voucher_type` |
| 17 | `voucher_detail_no` | Data | `varchar(140)` | INDEX, ro |  |
| 18 | `project` | Link | `varchar(140)` |  | → `Project` |
| 19 | `remarks` | Text | `text` |  |  |
| 20 | `is_opening` | Select | `varchar(140)` |  | enum: No, Yes |
| 21 | `is_advance` | Select | `varchar(140)` |  | enum: No, Yes |
| 22 | `fiscal_year` | Link | `varchar(140)` |  | → `Fiscal Year` |
| 23 | `company` | Link | `varchar(140)` | INDEX | → `Company` |
| 24 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 25 | `to_rename` | Check | `smallint` | INDEX, hidden, default=1 |  |
| 26 | `due_date` | Date | `date` |  |  |
| 27 | `is_cancelled` | Check | `smallint` | default=0 |  |
| 28 | `transaction_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 29 | `transaction_exchange_rate` | Float | `numeric(21,9)` |  |  |
| 30 | `debit_in_transaction_currency` | Currency | `numeric(21,9)` |  |  |
| 31 | `credit_in_transaction_currency` | Currency | `numeric(21,9)` |  |  |
| 32 | `voucher_subtype` | Small Text | `text` |  |  |
| 33 | `debit_in_reporting_currency` | Currency | `numeric(21,9)` |  |  |
| 34 | `credit_in_reporting_currency` | Currency | `numeric(21,9)` |  |  |
| 35 | `reporting_currency_exchange_rate` | Float | `numeric(21,9)` |  |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `against_voucher` — target DocType read from `against_voucher_type`
- `voucher_no` — target DocType read from `voucher_type`

## Invoice Discounting

- **Table**: `tabInvoice Discounting`  (proposed: `invoice_discounting`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-INV-DISC-.YYYY.-.#####`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 2 | `loan_start_date` | Date | `date` |  |  |
| 3 | `loan_period` | Int | `integer` |  |  |
| 4 | `loan_end_date` | Date | `date` | ro |  |
| 5 | `status` | Select | `varchar(140)` | ro | enum: Draft, Sanctioned, Disbursed, Settled, Cancelled |
| 6 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 7 | `total_amount` | Currency | `numeric(21,9)` | ro |  |
| 8 | `bank_charges` | Currency | `numeric(21,9)` |  |  |
| 9 | `short_term_loan` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 10 | `bank_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 11 | `bank_charges_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 12 | `accounts_receivable_credit` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 13 | `accounts_receivable_discounted` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 14 | `accounts_receivable_unpaid` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 15 | `amended_from` | Link | `varchar(140)` | ro | → `Invoice Discounting` |

**Child tables (1-N):**

- `invoices` → `Discounted Invoice` (line items)

**Referenced by (1):** `Invoice Discounting`.`amended_from`

## Journal Entry

- **Table**: `tabJournal Entry`  (proposed: `journal_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `title`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `voucher_type,posting_date, due_date, cheque_no`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` | hidden |  |
| 2 | `voucher_type` | Select | `varchar(140)` | NOT NULL, INDEX, default=Journal Entry | enum: Journal Entry, Inter Company Journal Entry, Bank Entry, Cash Entry, Credit Card Entry, Debit Note, Credit Note, Contra Entry … (+10) |
| 3 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-JV-.YYYY.- |
| 4 | `posting_date` | Date | `date` | NOT NULL, INDEX |  |
| 5 | `company` | Link | `varchar(140)` | NOT NULL, INDEX | → `Company` |
| 6 | `finance_book` | Link | `varchar(140)` | ro | → `Finance Book` |
| 7 | `cheque_no` | Data | `varchar(140)` | INDEX |  |
| 8 | `cheque_date` | Date | `date` | INDEX |  |
| 9 | `user_remark` | Small Text | `text` | hidden |  |
| 10 | `total_debit` | Currency | `numeric(21,9)` | ro |  |
| 11 | `total_credit` | Currency | `numeric(21,9)` | ro |  |
| 12 | `difference` | Currency | `numeric(21,9)` | ro |  |
| 13 | `multi_currency` | Check | `smallint` | default=0 |  |
| 14 | `total_amount_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 15 | `total_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 16 | `total_amount_in_words` | Data | `varchar(140)` | ro, hidden |  |
| 17 | `clearance_date` | Date | `date` | INDEX, ro |  |
| 18 | `remark` | Small Text | `text` |  |  |
| 19 | `inter_company_journal_entry_reference` | Link | `varchar(140)` | ro | → `Journal Entry` |
| 20 | `bill_no` | Data | `varchar(140)` |  |  |
| 21 | `bill_date` | Date | `date` |  |  |
| 22 | `due_date` | Date | `date` |  |  |
| 23 | `write_off_based_on` | Select | `varchar(140)` | default=Accounts Receivable | enum: Accounts Receivable, Accounts Payable |
| 24 | `write_off_amount` | Currency | `numeric(21,9)` |  |  |
| 25 | `pay_to_recd_from` | Data | `varchar(140)` |  |  |
| 26 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 27 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 28 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 29 | `payment_order` | Link | `varchar(140)` | ro | → `Payment Order` |
| 30 | `is_opening` | Select | `varchar(140)` | INDEX, default=No | enum: No, Yes |
| 31 | `stock_entry` | Link | `varchar(140)` | ro | → `Stock Entry` |
| 32 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 33 | `amended_from` | Link | `varchar(140)` | ro | → `Journal Entry` |
| 34 | `from_template` | Link | `varchar(140)` |  | → `Journal Entry Template` |
| 35 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 36 | `apply_tds` | Check | `smallint` | default=0 |  |
| 37 | `reversal_of` | Link | `varchar(140)` | ro | → `Journal Entry` |
| 38 | `process_deferred_accounting` | Link | `varchar(140)` | ro | → `Process Deferred Accounting` |
| 39 | `is_system_generated` | Check | `smallint` | ro, default=0 |  |
| 40 | `periodic_entry_difference_account` | Link | `varchar(140)` |  | → `Account` |
| 41 | `for_all_stock_asset_accounts` | Check | `smallint` | default=1 |  |
| 42 | `stock_asset_account` | Link | `varchar(140)` |  | → `Account` |
| 43 | `party_not_required` | Check | `smallint` | hidden, default=0 |  |
| 44 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 45 | `ignore_tax_withholding_threshold` | Check | `smallint` | default=0 |  |
| 46 | `override_tax_withholding_entries` | Check | `smallint` | default=0 |  |
| 47 | `custom_remark` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `accounts` → `Journal Entry Account` (line items)
- `tax_withholding_entries` → `Tax Withholding Entry` (line items)

**Referenced by (9):** `Journal Entry`.`inter_company_journal_entry_reference`, `Journal Entry`.`amended_from`, `Journal Entry`.`reversal_of`, `Asset`.`journal_entry_for_scrap`, `Asset Value Adjustment`.`journal_entry`, `Depreciation Schedule`.`journal_entry`, `Stock Entry`.`credit_note`, `Salary Slip`.`journal_entry`, `Salary Withholding Cycle`.`journal_entry`

## POS Closing Entry

- **Table**: `tabPOS Closing Entry`  (proposed: `pos_closing_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `POS-CLO-.YYYY.-.#####`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `period_start_date` | Datetime | `timestamp` | NOT NULL, ro, denorm←pos_opening_entry.period_start_date |  |
| 2 | `period_end_date` | Datetime | `timestamp` | NOT NULL, default=Today |  |
| 3 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL, ro, denorm←pos_opening_entry.company | → `Company` |
| 5 | `pos_profile` | Link | `varchar(140)` | NOT NULL, ro, denorm←pos_opening_entry.pos_profile | → `POS Profile` |
| 6 | `user` | Link | `varchar(140)` | NOT NULL, ro, denorm←pos_opening_entry.user | → `User` *(frappe/Core)* |
| 7 | `grand_total` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 8 | `net_total` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 9 | `total_quantity` | Float | `numeric(21,9)` | ro |  |
| 10 | `amended_from` | Link | `varchar(140)` | ro | → `POS Closing Entry` |
| 11 | `pos_opening_entry` | Link | `varchar(140)` | NOT NULL | → `POS Opening Entry` |
| 12 | `status` | Select | `varchar(140)` | ro, hidden, default=Draft | enum: Draft, Submitted, Queued, Failed, Cancelled |
| 13 | `error_message` | Small Text | `text` | ro |  |
| 14 | `posting_time` | Time | `time(6)` | NOT NULL, default=Now |  |
| 15 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |

**Child tables (1-N):**

- `payment_reconciliation` → `POS Closing Entry Detail` (line items)
- `taxes` → `POS Closing Entry Taxes` (line items)
- `pos_invoices` → `POS Invoice Reference` (line items)
- `sales_invoices` → `Sales Invoice Reference` (line items)

**Referenced by (3):** `POS Closing Entry`.`amended_from`, `POS Invoice Merge Log`.`pos_closing_entry`, `Sales Invoice`.`pos_closing_entry`

## POS Invoice

- **Table**: `tabPOS Invoice`  (proposed: `pos_invoice`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `posting_date, due_date, customer, base_grand_total, outstanding_amount`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-PSINV-.YYYY.- |
| 2 | `customer` | Link | `varchar(140)` | INDEX | → `Customer` |
| 3 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |
| 4 | `tax_id` | Data | `varchar(140)` | ro |  |
| 5 | `is_pos` | Check | `smallint` | NOT NULL, ro, default=1 |  |
| 6 | `pos_profile` | Link | `varchar(140)` |  | → `POS Profile` |
| 7 | `is_return` | Check | `smallint` | default=0 |  |
| 8 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 9 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 10 | `posting_time` | Time | `time(6)` | default=Now |  |
| 11 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 12 | `due_date` | Date | `date` |  |  |
| 13 | `amended_from` | Link | `varchar(140)` | ro | → `POS Invoice` |
| 14 | `return_against` | Link | `varchar(140)` | INDEX, ro | → `POS Invoice` |
| 15 | `update_billed_amount_in_sales_order` | Check | `smallint` | default=0 |  |
| 16 | `project` | Link | `varchar(140)` |  | → `Project` |
| 17 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 18 | `po_no` | Data | `varchar(140)` |  |  |
| 19 | `po_date` | Date | `date` |  |  |
| 20 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 21 | `address_display` | Text Editor | `text` | ro |  |
| 22 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 23 | `contact_display` | Small Text | `text` | ro |  |
| 24 | `contact_mobile` | Data | `varchar(140)` | ro, hidden |  |
| 25 | `contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 26 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 27 | `shipping_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 28 | `shipping_address` | Text Editor | `text` | ro |  |
| 29 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 30 | `company_address_display` | Text Editor | `text` | ro, hidden |  |
| 31 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 32 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 33 | `selling_price_list` | Link | `varchar(140)` | NOT NULL | → `Price List` |
| 34 | `price_list_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 35 | `plc_conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 36 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 37 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 38 | `update_stock` | Check | `smallint` | default=0 |  |
| 39 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 40 | `total_billing_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 41 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 42 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 43 | `base_net_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 44 | `total` | Currency | `numeric(21,9)` | ro |  |
| 45 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 46 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 47 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 48 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 49 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 50 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 51 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 52 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 53 | `loyalty_points` | Int | `integer` |  |  |
| 54 | `loyalty_amount` | Currency | `numeric(21,9)` | ro |  |
| 55 | `redeem_loyalty_points` | Check | `smallint` | default=0 |  |
| 56 | `loyalty_program` | Link | `varchar(140)` | ro, denorm←customer.loyalty_program | → `Loyalty Program` |
| 57 | `loyalty_redemption_account` | Link | `varchar(140)` |  | → `Account` |
| 58 | `loyalty_redemption_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 59 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 60 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 61 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 62 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 63 | `base_grand_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 64 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 65 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 66 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 67 | `grand_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 68 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 69 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 70 | `in_words` | Data | `varchar(140)` | ro |  |
| 71 | `total_advance` | Currency | `numeric(21,9)` | ro |  |
| 72 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 73 | `allocate_advances_automatically` | Check | `smallint` | default=0 |  |
| 74 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 75 | `cash_bank_account` | Link | `varchar(140)` | hidden | → `Account` |
| 76 | `base_paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 77 | `paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 78 | `base_change_amount` | Currency | `numeric(21,9)` | ro |  |
| 79 | `change_amount` | Currency | `numeric(21,9)` |  |  |
| 80 | `account_for_change_amount` | Link | `varchar(140)` |  | → `Account` |
| 81 | `write_off_amount` | Currency | `numeric(21,9)` |  |  |
| 82 | `base_write_off_amount` | Currency | `numeric(21,9)` | ro |  |
| 83 | `write_off_outstanding_amount_automatically` | Check | `smallint` | default=0 |  |
| 84 | `write_off_account` | Link | `varchar(140)` |  | → `Account` |
| 85 | `write_off_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 86 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 87 | `terms` | Text Editor | `text` |  |  |
| 88 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 89 | `group_same_items` | Check | `smallint` | default=0 |  |
| 90 | `language` | Data | `varchar(140)` | ro |  |
| 91 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 92 | `inter_company_invoice_reference` | Link | `varchar(140)` | ro | → `Purchase Invoice` |
| 93 | `customer_group` | Link | `varchar(140)` | hidden | → `Customer Group` |
| 94 | `is_discounted` | Check | `smallint` | ro, default=0 |  |
| 95 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Return, Credit Note Issued, Consolidated, Submitted, Paid, Partly Paid, Unpaid … (+5) |
| 96 | `debit_to` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 97 | `party_account_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 98 | `is_opening` | Select | `varchar(140)` | default=No | enum: No, Yes |
| 99 | `remarks` | Small Text | `text` |  |  |
| 100 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 101 | `commission_rate` | Float | `numeric(21,9)` | denorm←sales_partner.commission_rate |  |
| 102 | `total_commission` | Currency | `numeric(21,9)` |  |  |
| 103 | `from_date` | Date | `date` |  |  |
| 104 | `to_date` | Date | `date` |  |  |
| 105 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 106 | `against_income_account` | Small Text | `text` | hidden |  |
| 107 | `consolidated_invoice` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 108 | `coupon_code` | Link | `varchar(140)` |  | → `Coupon Code` |
| 109 | `amount_eligible_for_commission` | Currency | `numeric(21,9)` | ro |  |
| 110 | `update_billed_amount_in_delivery_note` | Check | `smallint` | default=1 |  |
| 111 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Medium` *(frappe/Website)* |
| 112 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 113 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 114 | `company_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 115 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `POS Invoice Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `packed_items` → `Packed Item` (line items)
- `timesheets` → `Sales Invoice Timesheet` (line items)
- `taxes` → `Sales Taxes and Charges` (line items)
- `advances` → `Sales Invoice Advance` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `payments` → `Sales Invoice Payment` (line items)
- `sales_team` → `Sales Team` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)

**Referenced by (5):** `POS Invoice`.`amended_from`, `POS Invoice`.`return_against`, `POS Invoice Reference`.`pos_invoice`, `POS Invoice Reference`.`return_against`, `Sales Invoice Item`.`pos_invoice`

## POS Invoice Merge Log

- **Table**: `tabPOS Invoice Merge Log`  (proposed: `pos_invoice_merge_log`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | NOT NULL |  |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL | → `Customer` |
| 3 | `amended_from` | Link | `varchar(140)` | ro | → `POS Invoice Merge Log` |
| 4 | `consolidated_invoice` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 5 | `consolidated_credit_note` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 6 | `pos_closing_entry` | Link | `varchar(140)` |  | → `POS Closing Entry` |
| 7 | `merge_invoices_based_on` | Select | `varchar(140)` | NOT NULL | enum: Customer, Customer Group |
| 8 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |
| 9 | `posting_time` | Time | `time(6)` | NOT NULL |  |
| 10 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

**Child tables (1-N):**

- `pos_invoices` → `POS Invoice Reference` (line items)

**Referenced by (1):** `POS Invoice Merge Log`.`amended_from`

## POS Opening Entry

- **Table**: `tabPOS Opening Entry`  (proposed: `pos_opening_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `POS-OPE-.YYYY.-.#####`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `period_start_date` | Datetime | `timestamp` | NOT NULL |  |
| 2 | `period_end_date` | Date | `date` | ro |  |
| 3 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `pos_profile` | Link | `varchar(140)` | NOT NULL | → `POS Profile` |
| 6 | `user` | Link | `varchar(140)` | NOT NULL | → `User` *(frappe/Core)* |
| 7 | `amended_from` | Link | `varchar(140)` | ro | → `POS Opening Entry` |
| 8 | `set_posting_date` | Check | `smallint` | default=0 |  |
| 9 | `status` | Select | `varchar(140)` | ro, hidden, default=Draft | enum: Draft, Open, Closed, Cancelled |
| 10 | `pos_closing_entry` | Data | `varchar(140)` | ro |  |

**Child tables (1-N):**

- `balance_details` → `POS Opening Entry Detail` (line items)

**Referenced by (2):** `POS Closing Entry`.`pos_opening_entry`, `POS Opening Entry`.`amended_from`

## Payment Entry

- **Table**: `tabPayment Entry`  (proposed: `payment_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `title`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-PAY-.YYYY.- |
| 2 | `payment_type` | Select | `varchar(140)` | NOT NULL | enum: Receive, Pay, Internal Transfer |
| 3 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 6 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 7 | `party_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 8 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 9 | `party_name` | Data | `varchar(140)` |  |  |
| 10 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 11 | `contact_email` | Data | `varchar(140)` | ro |  |
| 12 | `paid_from` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 13 | `paid_from_account_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 14 | `paid_to` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 15 | `paid_to_account_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 16 | `paid_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 17 | `source_exchange_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 18 | `base_paid_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 19 | `received_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 20 | `target_exchange_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 21 | `base_received_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 22 | `total_allocated_amount` | Currency | `numeric(21,9)` | ro |  |
| 23 | `base_total_allocated_amount` | Currency | `numeric(21,9)` | ro |  |
| 24 | `unallocated_amount` | Currency | `numeric(21,9)` |  |  |
| 25 | `difference_amount` | Currency | `numeric(21,9)` | ro |  |
| 26 | `reference_no` | Data | `varchar(140)` |  |  |
| 27 | `reference_date` | Date | `date` | INDEX |  |
| 28 | `clearance_date` | Date | `date` | ro |  |
| 29 | `project` | Link | `varchar(140)` |  | → `Project` |
| 30 | `remarks` | Small Text | `text` |  |  |
| 31 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 32 | `print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 33 | `bank` | Read Only | `varchar(140)` | denorm←bank_account.bank |  |
| 34 | `bank_account_no` | Read Only | `varchar(140)` | denorm←bank_account.bank_account_no |  |
| 35 | `payment_order` | Link | `varchar(140)` | ro | → `Payment Order` |
| 36 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 37 | `amended_from` | Link | `varchar(140)` | ro | → `Payment Entry` |
| 38 | `title` | Data | `varchar(140)` | ro, hidden |  |
| 39 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 40 | `party_bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 41 | `payment_order_status` | Select | `varchar(140)` | ro, hidden | enum: Initiated, Payment Ordered |
| 42 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Submitted, Cancelled |
| 43 | `custom_remarks` | Check | `smallint` | default=0 |  |
| 44 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 45 | `purchase_taxes_and_charges_template` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 46 | `sales_taxes_and_charges_template` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 47 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 48 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 49 | `paid_amount_after_tax` | Currency | `numeric(21,9)` | ro, hidden |  |
| 50 | `base_paid_amount_after_tax` | Currency | `numeric(21,9)` | ro, hidden |  |
| 51 | `received_amount_after_tax` | Currency | `numeric(21,9)` | ro, hidden |  |
| 52 | `base_received_amount_after_tax` | Currency | `numeric(21,9)` | ro, hidden |  |
| 53 | `paid_from_account_type` | Data | `varchar(140)` | hidden, denorm←paid_from.account_type |  |
| 54 | `paid_to_account_type` | Data | `varchar(140)` | hidden, denorm←paid_to.account_type |  |
| 55 | `book_advance_payments_in_separate_party_account` | Check | `smallint` | ro, denorm←company.book_advance_payments_in_separate_party_account, default=0 |  |
| 56 | `base_in_words` | Small Text | `text` | ro |  |
| 57 | `in_words` | Small Text | `text` | ro |  |
| 58 | `reconcile_on_advance_payment_date` | Check | `smallint` | ro, hidden, denorm←company.reconcile_on_advance_payment_date, default=0 |  |
| 59 | `is_opening` | Select | `varchar(140)` | INDEX, default=No | enum: No, Yes |
| 60 | `apply_tds` | Check | `smallint` | default=0 |  |
| 61 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 62 | `ignore_tax_withholding_threshold` | Check | `smallint` | default=0 |  |
| 63 | `override_tax_withholding_entries` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `references` → `Payment Entry Reference` (line items)
- `deductions` → `Payment Entry Deduction` (line items)
- `taxes` → `Advance Taxes and Charges` (line items)
- `tax_withholding_entries` → `Tax Withholding Entry` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (1):** `Payment Entry`.`amended_from`

## Payment Ledger Entry

- **Table**: `tabPayment Ledger Entry`  (proposed: `payment_ledger_entry`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `voucher_no, against_voucher_no`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | INDEX |  |
| 2 | `account_type` | Select | `varchar(140)` |  | enum: Receivable, Payable |
| 3 | `account` | Link | `varchar(140)` | INDEX | → `Account` |
| 4 | `party_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 5 | `party` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `party_type` |
| 6 | `voucher_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 7 | `voucher_no` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `voucher_type` |
| 8 | `against_voucher_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 9 | `against_voucher_no` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `against_voucher_type` |
| 10 | `amount` | Currency | `numeric(21,9)` |  |  |
| 11 | `account_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 12 | `amount_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 13 | `delinked` | Check | `smallint` | default=0 |  |
| 14 | `company` | Link | `varchar(140)` | INDEX | → `Company` |
| 15 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 16 | `project` | Link | `varchar(140)` |  | → `Project` |
| 17 | `due_date` | Date | `date` |  |  |
| 18 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 19 | `remarks` | Text | `text` |  |  |
| 20 | `voucher_detail_no` | Data | `varchar(140)` | INDEX |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `voucher_no` — target DocType read from `voucher_type`
- `against_voucher_no` — target DocType read from `against_voucher_type`

## Payment Order

- **Table**: `tabPayment Order`  (proposed: `payment_order`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL, default=PMO- | enum: PMO- |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `party` | Link | `varchar(140)` |  | → `Supplier` |
| 4 | `posting_date` | Date | `date` | default=Today |  |
| 5 | `amended_from` | Link | `varchar(140)` | ro | → `Payment Order` |
| 6 | `payment_order_type` | Select | `varchar(140)` | NOT NULL, ro | enum: Payment Request, Payment Entry |
| 7 | `company_bank_account` | Link | `varchar(140)` | NOT NULL | → `Bank Account` |
| 8 | `company_bank` | Link | `varchar(140)` | denorm←company_bank_account.bank | → `Bank` |
| 9 | `account` | Data | `varchar(140)` | denorm←company_bank_account.account |  |

**Child tables (1-N):**

- `references` → `Payment Order Reference` (line items)

**Referenced by (4):** `Journal Entry`.`payment_order`, `Payment Entry`.`payment_order`, `Payment Order`.`amended_from`, `Payment Request`.`payment_order`

## Payment Request

- **Table**: `tabPayment Request`  (proposed: `payment_request`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_request_type` | Select | `varchar(140)` | NOT NULL, default=Inward | enum: Outward, Inward |
| 2 | `transaction_date` | Date | `date` |  |  |
| 3 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-PRQ-.YYYY.- |
| 4 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 5 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 6 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 7 | `reference_doctype` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 8 | `reference_name` | Dynamic Link | `varchar(140)` | INDEX, ro | → polymorphic, doctype in `reference_doctype` |
| 9 | `grand_total` | Currency | `numeric(21,9)` | NOT NULL |  |
| 10 | `is_a_subscription` | Check | `smallint` | default=0 |  |
| 11 | `currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 12 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 13 | `bank` | Link | `varchar(140)` | ro, denorm←bank_account.bank | → `Bank` |
| 14 | `bank_account_no` | Read Only | `varchar(140)` | denorm←bank_account.bank_account_no |  |
| 15 | `account` | Read Only | `varchar(140)` | denorm←bank_account.account |  |
| 16 | `iban` | Read Only | `varchar(140)` | denorm←bank_account.iban |  |
| 17 | `branch_code` | Read Only | `varchar(140)` | denorm←bank_account.branch_code |  |
| 18 | `swift_number` | Read Only | `varchar(140)` | denorm←bank.swift_number |  |
| 19 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 20 | `project` | Link | `varchar(140)` |  | → `Project` |
| 21 | `print_format` | Select | `varchar(140)` |  |  |
| 22 | `email_to` | Data | `varchar(140)` |  |  |
| 23 | `subject` | Data | `varchar(140)` |  |  |
| 24 | `payment_gateway_account` | Link | `varchar(140)` |  | → `Payment Gateway Account` |
| 25 | `status` | Select | `varchar(140)` | ro, hidden, default=Draft | enum: Draft, Requested, Initiated, Partially Paid, Payment Ordered, Paid, Failed, Cancelled |
| 26 | `make_sales_invoice` | Check | `smallint` | ro, hidden, default=0 |  |
| 27 | `message` | Text | `text` |  |  |
| 28 | `mute_email` | Check | `smallint` | ro, hidden, default=0 |  |
| 29 | `payment_url` | Data | `varchar(140)` | ro |  |
| 30 | `payment_gateway` | Read Only | `varchar(140)` | denorm←payment_gateway_account.payment_gateway |  |
| 31 | `payment_account` | Read Only | `varchar(140)` | ro, denorm←payment_gateway_account.payment_account |  |
| 32 | `payment_channel` | Select | `varchar(140)` | ro, denorm←payment_gateway_account.payment_channel | enum: Email, Phone, Other |
| 33 | `payment_order` | Link | `varchar(140)` | ro | → `Payment Order` |
| 34 | `amended_from` | Link | `varchar(140)` | ro | → `Payment Request` |
| 35 | `failed_reason` | Data | `varchar(140)` | ro, hidden |  |
| 36 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 37 | `company` | Link | `varchar(140)` | ro | → `Company` |
| 38 | `party_account_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 39 | `party_name` | Data | `varchar(140)` | ro |  |
| 40 | `phone_number` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `subscription_plans` → `Subscription Plan Detail` (line items)
- `payment_reference` → `Payment Reference` (line items)

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `reference_name` — target DocType read from `reference_doctype`

**Referenced by (3):** `Payment Entry Reference`.`payment_request`, `Payment Order Reference`.`payment_request`, `Payment Request`.`amended_from`

## Period Closing Voucher

- **Table**: `tabPeriod Closing Voucher`  (proposed: `period_closing_voucher`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-PCV-.YYYY.-.#####`  (Expression (old style))
- **Title field**: `closing_account_head`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `fiscal_year, period_start_date, period_end_date`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `transaction_date` | Date | `date` | default=Today |  |
| 2 | `fiscal_year` | Link | `varchar(140)` | NOT NULL | → `Fiscal Year` |
| 3 | `amended_from` | Link | `varchar(140)` | ro | → `Period Closing Voucher` |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `closing_account_head` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 6 | `remarks` | Small Text | `text` | NOT NULL |  |
| 7 | `gle_processing_status` | Select | `varchar(140)` | ro | enum: In Progress, Completed, Failed |
| 8 | `error_message` | Text | `text` | ro |  |
| 9 | `period_end_date` | Date | `date` | NOT NULL |  |
| 10 | `period_start_date` | Date | `date` | NOT NULL |  |

**Referenced by (3):** `Account Closing Balance`.`period_closing_voucher`, `Period Closing Voucher`.`amended_from`, `Process Period Closing Voucher`.`parent_pcv`

## Process Deferred Accounting

- **Table**: `tabProcess Deferred Accounting`  (proposed: `process_deferred_accounting`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-PDA-.#####`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `type` | Select | `varchar(140)` | NOT NULL | enum: Income, Expense |
| 2 | `amended_from` | Link | `varchar(140)` | ro | → `Process Deferred Accounting` |
| 3 | `start_date` | Date | `date` | NOT NULL |  |
| 4 | `end_date` | Date | `date` | NOT NULL |  |
| 5 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 6 | `account` | Link | `varchar(140)` |  | → `Account` |
| 7 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

**Referenced by (2):** `Journal Entry`.`process_deferred_accounting`, `Process Deferred Accounting`.`amended_from`

## Process Payment Reconciliation

- **Table**: `tabProcess Payment Reconciliation`  (proposed: `process_payment_reconciliation`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `format:ACC-PPR-{#####}`  (Expression)
- **Title field**: `company`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `status` | Select | `varchar(140)` | ro | enum: Queued, Running, Paused, Completed, Partially Reconciled, Failed, Cancelled |
| 2 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 3 | `party_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 4 | `party` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `party_type` |
| 5 | `receivable_payable_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 6 | `from_invoice_date` | Date | `date` |  |  |
| 7 | `to_invoice_date` | Date | `date` |  |  |
| 8 | `from_payment_date` | Date | `date` |  |  |
| 9 | `to_payment_date` | Date | `date` |  |  |
| 10 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 11 | `bank_cash_account` | Link | `varchar(140)` |  | → `Account` |
| 12 | `error_log` | Long Text | `text` |  |  |
| 13 | `amended_from` | Link | `varchar(140)` | ro | → `Process Payment Reconciliation` |
| 14 | `default_advance_account` | Link | `varchar(140)` |  | → `Account` |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

**Referenced by (2):** `Process Payment Reconciliation`.`amended_from`, `Process Payment Reconciliation Log`.`process_pr`

## Process Period Closing Voucher

- **Table**: `tabProcess Period Closing Voucher`  (proposed: `process_period_closing_voucher`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `format:Process-PCV-{###}`  (Expression (old style))
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `parent_pcv` | Link | `varchar(140)` | NOT NULL | → `Period Closing Voucher` |
| 2 | `status` | Select | `varchar(140)` | default=Queued | enum: Queued, Running, Paused, Completed, Cancelled |
| 3 | `amended_from` | Link | `varchar(140)` | INDEX, ro | → `Process Period Closing Voucher` |
| 4 | `p_l_closing_balance` | JSON | `jsonb` |  |  |
| 5 | `bs_closing_balance` | JSON | `jsonb` |  |  |

**Child tables (1-N):**

- `normal_balances` → `Process Period Closing Voucher Detail` (line items)
- `z_opening_balances` → `Process Period Closing Voucher Detail` (line items)

**Referenced by (1):** `Process Period Closing Voucher`.`amended_from`

## Process Subscription

- **Table**: `tabProcess Subscription`  (proposed: `process_subscription`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `amended_from` | Link | `varchar(140)` | ro | → `Process Subscription` |
| 2 | `posting_date` | Date | `date` | NOT NULL |  |
| 3 | `subscription` | Link | `varchar(140)` |  | → `Subscription` |

**Referenced by (1):** `Process Subscription`.`amended_from`

## Purchase Invoice

- **Table**: `tabPurchase Invoice`  (proposed: `purchase_invoice`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `supplier_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `posting_date, supplier, bill_no, base_grand_total, outstanding_amount`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `title` | Data | `varchar(140)` |  |  |
| 2 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-PINV-.YYYY.-, ACC-PINV-RET-.YYYY.- |
| 3 | `supplier` | Link | `varchar(140)` | NOT NULL, INDEX | → `Supplier` |
| 4 | `supplier_name` | Data | `varchar(140)` | ro, denorm←supplier.supplier_name |  |
| 5 | `tax_id` | Read Only | `varchar(140)` | ro, denorm←supplier.tax_id |  |
| 6 | `due_date` | Date | `date` |  |  |
| 7 | `is_paid` | Check | `smallint` | default=0 |  |
| 8 | `is_return` | Check | `smallint` | default=0 |  |
| 9 | `apply_tds` | Check | `smallint` | default=0 |  |
| 10 | `company` | Link | `varchar(140)` |  | → `Company` |
| 11 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 12 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 13 | `posting_time` | Time | `time(6)` | default=Now |  |
| 14 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 15 | `amended_from` | Link | `varchar(140)` | ro | → `Purchase Invoice` |
| 16 | `on_hold` | Check | `smallint` | default=0 |  |
| 17 | `release_date` | Date | `date` | INDEX |  |
| 18 | `hold_comment` | Small Text | `text` |  |  |
| 19 | `bill_no` | Data | `varchar(140)` | INDEX |  |
| 20 | `bill_date` | Date | `date` |  |  |
| 21 | `return_against` | Link | `varchar(140)` | INDEX, ro | → `Purchase Invoice` |
| 22 | `update_billed_amount_in_purchase_order` | Check | `smallint` | default=0 |  |
| 23 | `update_billed_amount_in_purchase_receipt` | Check | `smallint` | default=1 |  |
| 24 | `supplier_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 25 | `address_display` | Text Editor | `text` | ro |  |
| 26 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 27 | `contact_display` | Small Text | `text` | ro |  |
| 28 | `contact_mobile` | Small Text | `text` | ro |  |
| 29 | `contact_email` | Small Text | `text` | ro |  |
| 30 | `shipping_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 31 | `shipping_address_display` | Text Editor | `text` | ro |  |
| 32 | `currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 33 | `conversion_rate` | Float | `numeric(21,9)` |  |  |
| 34 | `buying_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 35 | `price_list_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 36 | `plc_conversion_rate` | Float | `numeric(21,9)` |  |  |
| 37 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 38 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 39 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 40 | `is_subcontracted` | Check | `smallint` | ro, default=0 |  |
| 41 | `update_stock` | Check | `smallint` | default=0 |  |
| 42 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 43 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 44 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 45 | `base_net_total` | Currency | `numeric(21,9)` | ro |  |
| 46 | `total` | Currency | `numeric(21,9)` | ro |  |
| 47 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 48 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 49 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 50 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 51 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Purchase Taxes and Charges Template` |
| 52 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 53 | `base_taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 54 | `base_taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 55 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 56 | `taxes_and_charges_added` | Currency | `numeric(21,9)` | ro |  |
| 57 | `taxes_and_charges_deducted` | Currency | `numeric(21,9)` | ro |  |
| 58 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 59 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 60 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 61 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 62 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 63 | `base_grand_total` | Currency | `numeric(21,9)` | ro |  |
| 64 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 65 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 66 | `base_in_words` | Data | `varchar(140)` | ro |  |
| 67 | `grand_total` | Currency | `numeric(21,9)` | ro |  |
| 68 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 69 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 70 | `in_words` | Data | `varchar(140)` | ro |  |
| 71 | `total_advance` | Currency | `numeric(21,9)` | ro |  |
| 72 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 73 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 74 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 75 | `cash_bank_account` | Link | `varchar(140)` |  | → `Account` |
| 76 | `clearance_date` | Date | `date` | ro |  |
| 77 | `paid_amount` | Currency | `numeric(21,9)` |  |  |
| 78 | `base_paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 79 | `write_off_amount` | Currency | `numeric(21,9)` |  |  |
| 80 | `base_write_off_amount` | Currency | `numeric(21,9)` | ro |  |
| 81 | `write_off_account` | Link | `varchar(140)` |  | → `Account` |
| 82 | `write_off_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 83 | `allocate_advances_automatically` | Check | `smallint` | default=0 |  |
| 84 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 85 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 86 | `terms` | Text Editor | `text` |  |  |
| 87 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 88 | `group_same_items` | Check | `smallint` | default=0 |  |
| 89 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 90 | `language` | Data | `varchar(140)` | ro |  |
| 91 | `is_internal_supplier` | Check | `smallint` | ro, denorm←supplier.is_internal_supplier, default=0 |  |
| 92 | `credit_to` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 93 | `party_account_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 94 | `is_opening` | Select | `varchar(140)` | default=No | enum: No, Yes |
| 95 | `against_expense_account` | Small Text | `text` | hidden |  |
| 96 | `status` | Select | `varchar(140)` | default=Draft | enum: Draft, Return, Debit Note Issued, Submitted, Paid, Partly Paid, Unpaid, Overdue … (+2) |
| 97 | `inter_company_invoice_reference` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 98 | `remarks` | Small Text | `text` |  |  |
| 99 | `from_date` | Date | `date` |  |  |
| 100 | `to_date` | Date | `date` |  |  |
| 101 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 102 | `billing_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 103 | `billing_address_display` | Text Editor | `text` | ro |  |
| 104 | `project` | Link | `varchar(140)` |  | → `Project` |
| 105 | `unrealized_profit_loss_account` | Link | `varchar(140)` |  | → `Account` |
| 106 | `represents_company` | Link | `varchar(140)` | ro, denorm←supplier.represents_company | → `Company` |
| 107 | `set_from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 108 | `supplier_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 109 | `per_received` | Percent | `numeric(21,9)` | ro, hidden |  |
| 110 | `ignore_default_payment_terms_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 111 | `subscription` | Link | `varchar(140)` |  | → `Subscription` |
| 112 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 113 | `named_place` | Data | `varchar(140)` |  |  |
| 114 | `only_include_allocated_payments` | Check | `smallint` | default=0 |  |
| 115 | `use_company_roundoff_cost_center` | Check | `smallint` | default=0 |  |
| 116 | `use_transaction_date_exchange_rate` | Check | `smallint` | ro, default=0 |  |
| 117 | `supplier_group` | Link | `varchar(140)` | denorm←supplier.supplier_group | → `Supplier Group` |
| 118 | `update_outstanding_for_self` | Check | `smallint` | default=1 |  |
| 119 | `sender` | Data | `varchar(140)` |  |  |
| 120 | `dispatch_address_display` | Text Editor | `text` | ro |  |
| 121 | `dispatch_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 122 | `claimed_landed_cost_amount` | Currency | `numeric(21,9)` | ro |  |
| 123 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 124 | `ignore_tax_withholding_threshold` | Check | `smallint` | default=0 |  |
| 125 | `override_tax_withholding_entries` | Check | `smallint` | default=0 |  |

**Child tables (1-N):**

- `items` → `Purchase Invoice Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `supplied_items` → `Purchase Receipt Item Supplied` (line items)
- `taxes` → `Purchase Taxes and Charges` (line items)
- `advances` → `Purchase Invoice Advance` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)
- `tax_withholding_entries` → `Tax Withholding Entry` (line items)

**Referenced by (8):** `POS Invoice`.`inter_company_invoice_reference`, `Purchase Invoice`.`amended_from`, `Purchase Invoice`.`return_against`, `Sales Invoice`.`inter_company_invoice_reference`, `Asset`.`purchase_invoice`, `Asset Repair Purchase Invoice`.`purchase_invoice`, `Landed Cost Vendor Invoice`.`vendor_invoice`, `Purchase Receipt Item`.`purchase_invoice`

## Repost Accounting Ledger

- **Table**: `tabRepost Accounting Ledger`  (proposed: `repost_accounting_ledger`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `amended_from` | Link | `varchar(140)` | ro | → `Repost Accounting Ledger` |
| 3 | `delete_cancelled_entries` | Check | `smallint` | default=0 |  |
| 4 | `error_log` | Code | `text` | ro |  |
| 5 | `status` | Select | `varchar(140)` | ro | enum: Queued, In Progress, Partially Reposted, Completed, Failed, Cancelled |
| 6 | `scheduled_job` | Link | `varchar(140)` | ro, hidden | → `RQ Job` *(frappe/Core)* |

**Child tables (1-N):**

- `vouchers` → `Repost Accounting Ledger Items` (line items)

**Referenced by (1):** `Repost Accounting Ledger`.`amended_from`

## Repost Payment Ledger

- **Table**: `tabRepost Payment Ledger`  (proposed: `repost_payment_ledger`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `posting_date` | Date | `date` | NOT NULL, default=Today |  |
| 2 | `voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 3 | `amended_from` | Link | `varchar(140)` | ro | → `Repost Payment Ledger` |
| 4 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 5 | `repost_status` | Select | `varchar(140)` | ro | enum: Queued, Failed, Completed |
| 6 | `add_manually` | Check | `smallint` | default=0 |  |
| 7 | `repost_error_log` | Long Text | `text` |  |  |

**Child tables (1-N):**

- `repost_vouchers` → `Repost Payment Ledger Items` (line items)

**Referenced by (1):** `Repost Payment Ledger`.`amended_from`

## Sales Invoice

- **Table**: `tabSales Invoice`  (proposed: `sales_invoice`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `naming_series:`  (By "Naming Series" field)
- **Title field**: `customer_name`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit
- **Search fields**: `posting_date, due_date, customer, base_grand_total, outstanding_amount`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `naming_series` | Select | `varchar(140)` | NOT NULL | enum: ACC-SINV-.YYYY.-, ACC-SINV-RET-.YYYY.- |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL, INDEX | → `Customer` |
| 3 | `customer_name` | Small Text | `text` | ro, denorm←customer.customer_name |  |
| 4 | `tax_id` | Data | `varchar(140)` | ro, denorm←customer.tax_id |  |
| 5 | `project` | Link | `varchar(140)` | INDEX | → `Project` |
| 6 | `is_pos` | Check | `smallint` | default=0 |  |
| 7 | `pos_profile` | Link | `varchar(140)` |  | → `POS Profile` |
| 8 | `is_return` | Check | `smallint` | default=0 |  |
| 9 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 10 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 11 | `posting_date` | Date | `date` | NOT NULL, INDEX, default=Today |  |
| 12 | `posting_time` | Time | `time(6)` | default=Now |  |
| 13 | `set_posting_time` | Check | `smallint` | default=0 |  |
| 14 | `due_date` | Date | `date` |  |  |
| 15 | `amended_from` | Link | `varchar(140)` | ro | → `Sales Invoice` |
| 16 | `return_against` | Link | `varchar(140)` | INDEX | → `Sales Invoice` |
| 17 | `update_billed_amount_in_sales_order` | Check | `smallint` | default=0 |  |
| 18 | `po_no` | Data | `varchar(140)` |  |  |
| 19 | `po_date` | Date | `date` |  |  |
| 20 | `customer_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 21 | `address_display` | Text Editor | `text` | ro |  |
| 22 | `contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 23 | `contact_display` | Small Text | `text` | ro |  |
| 24 | `contact_mobile` | Small Text | `text` | ro, hidden |  |
| 25 | `contact_email` | Data | `varchar(140)` | ro, hidden |  |
| 26 | `territory` | Link | `varchar(140)` |  | → `Territory` |
| 27 | `shipping_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 28 | `shipping_address` | Text Editor | `text` | ro |  |
| 29 | `company_address` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 30 | `company_address_display` | Text Editor | `text` | ro |  |
| 31 | `currency` | Link | `varchar(140)` | NOT NULL | → `Currency` *(frappe/Geo)* |
| 32 | `conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 33 | `selling_price_list` | Link | `varchar(140)` | NOT NULL | → `Price List` |
| 34 | `price_list_currency` | Link | `varchar(140)` | NOT NULL, ro | → `Currency` *(frappe/Geo)* |
| 35 | `plc_conversion_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 36 | `ignore_pricing_rule` | Check | `smallint` | default=0 |  |
| 37 | `set_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 38 | `update_stock` | Check | `smallint` | default=0 |  |
| 39 | `scan_barcode` | Data | `varchar(140)` |  |  |
| 40 | `total_billing_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 41 | `total_qty` | Float | `numeric(21,9)` | ro |  |
| 42 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 43 | `base_net_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 44 | `total` | Currency | `numeric(21,9)` | ro |  |
| 45 | `net_total` | Currency | `numeric(21,9)` | ro |  |
| 46 | `total_net_weight` | Float | `numeric(21,9)` | ro |  |
| 47 | `taxes_and_charges` | Link | `varchar(140)` |  | → `Sales Taxes and Charges Template` |
| 48 | `shipping_rule` | Link | `varchar(140)` |  | → `Shipping Rule` |
| 49 | `tax_category` | Link | `varchar(140)` |  | → `Tax Category` |
| 50 | `other_charges_calculation` | Text Editor | `text` | ro |  |
| 51 | `base_total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 52 | `total_taxes_and_charges` | Currency | `numeric(21,9)` | ro |  |
| 53 | `loyalty_points` | Int | `integer` |  |  |
| 54 | `loyalty_amount` | Currency | `numeric(21,9)` | ro |  |
| 55 | `redeem_loyalty_points` | Check | `smallint` | default=0 |  |
| 56 | `loyalty_program` | Link | `varchar(140)` | denorm←customer.loyalty_program | → `Loyalty Program` |
| 57 | `loyalty_redemption_account` | Link | `varchar(140)` |  | → `Account` |
| 58 | `loyalty_redemption_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 59 | `apply_discount_on` | Select | `varchar(140)` | default=Grand Total | enum: Grand Total, Net Total |
| 60 | `base_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 61 | `additional_discount_percentage` | Float | `numeric(21,9)` |  |  |
| 62 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 63 | `base_grand_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 64 | `base_rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 65 | `base_rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 66 | `base_in_words` | Small Text | `text` | ro |  |
| 67 | `grand_total` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 68 | `rounding_adjustment` | Currency | `numeric(21,9)` | ro |  |
| 69 | `rounded_total` | Currency | `numeric(21,9)` | ro |  |
| 70 | `in_words` | Small Text | `text` | ro |  |
| 71 | `total_advance` | Currency | `numeric(21,9)` | ro |  |
| 72 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 73 | `allocate_advances_automatically` | Check | `smallint` | default=0 |  |
| 74 | `payment_terms_template` | Link | `varchar(140)` |  | → `Payment Terms Template` |
| 75 | `cash_bank_account` | Link | `varchar(140)` | hidden | → `Account` |
| 76 | `base_paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 77 | `paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 78 | `base_change_amount` | Currency | `numeric(21,9)` | ro |  |
| 79 | `change_amount` | Currency | `numeric(21,9)` |  |  |
| 80 | `account_for_change_amount` | Link | `varchar(140)` |  | → `Account` |
| 81 | `write_off_amount` | Currency | `numeric(21,9)` |  |  |
| 82 | `base_write_off_amount` | Currency | `numeric(21,9)` | ro |  |
| 83 | `write_off_outstanding_amount_automatically` | Check | `smallint` | default=0 |  |
| 84 | `write_off_account` | Link | `varchar(140)` |  | → `Account` |
| 85 | `write_off_cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 86 | `tc_name` | Link | `varchar(140)` |  | → `Terms and Conditions` |
| 87 | `terms` | Text Editor | `text` |  |  |
| 88 | `letter_head` | Link | `varchar(140)` |  | → `Letter Head` *(frappe/Printing)* |
| 89 | `group_same_items` | Check | `smallint` | default=0 |  |
| 90 | `language` | Link | `varchar(140)` | ro, denorm←customer.language | → `Language` *(frappe/Core)* |
| 91 | `select_print_heading` | Link | `varchar(140)` |  | → `Print Heading` *(frappe/Printing)* |
| 92 | `inter_company_invoice_reference` | Link | `varchar(140)` | INDEX, ro | → `Purchase Invoice` |
| 93 | `customer_group` | Link | `varchar(140)` | hidden | → `Customer Group` |
| 94 | `is_discounted` | Check | `smallint` | ro, default=0 |  |
| 95 | `status` | Select | `varchar(140)` | ro, default=Draft | enum: Draft, Return, Credit Note Issued, Submitted, Paid, Partly Paid, Unpaid, Unpaid and Discounted … (+5) |
| 96 | `debit_to` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 97 | `party_account_currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 98 | `is_opening` | Select | `varchar(140)` | hidden, default=No | enum: No, Yes |
| 99 | `remarks` | Small Text | `text` |  |  |
| 100 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |
| 101 | `commission_rate` | Float | `numeric(21,9)` | denorm←sales_partner.commission_rate |  |
| 102 | `total_commission` | Currency | `numeric(21,9)` |  |  |
| 103 | `from_date` | Date | `date` |  |  |
| 104 | `to_date` | Date | `date` |  |  |
| 105 | `auto_repeat` | Link | `varchar(140)` | ro | → `Auto Repeat` *(frappe/Automation)* |
| 106 | `against_income_account` | Small Text | `text` | hidden |  |
| 107 | `is_consolidated` | Check | `smallint` | ro, default=0 |  |
| 108 | `is_internal_customer` | Check | `smallint` | ro, denorm←customer.is_internal_customer, default=0 |  |
| 109 | `company_tax_id` | Data | `varchar(140)` | ro, denorm←company.tax_id |  |
| 110 | `unrealized_profit_loss_account` | Link | `varchar(140)` |  | → `Account` |
| 111 | `represents_company` | Link | `varchar(140)` | ro, denorm←customer.represents_company | → `Company` |
| 112 | `set_target_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 113 | `is_debit_note` | Check | `smallint` | default=0 |  |
| 114 | `disable_rounded_total` | Check | `smallint` | default=0 |  |
| 115 | `additional_discount_account` | Link | `varchar(140)` |  | → `Account` |
| 116 | `dispatch_address_name` | Link | `varchar(140)` |  | → `Address` *(frappe/Contacts)* |
| 117 | `dispatch_address` | Text Editor | `text` | ro |  |
| 118 | `ignore_default_payment_terms_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 119 | `total_billing_hours` | Float | `numeric(21,9)` | ro |  |
| 120 | `amount_eligible_for_commission` | Currency | `numeric(21,9)` | ro |  |
| 121 | `subscription` | Link | `varchar(140)` |  | → `Subscription` |
| 122 | `is_cash_or_non_trade_discount` | Check | `smallint` | default=0 |  |
| 123 | `incoterm` | Link | `varchar(140)` |  | → `Incoterm` |
| 124 | `named_place` | Data | `varchar(140)` |  |  |
| 125 | `only_include_allocated_payments` | Check | `smallint` | default=0 |  |
| 126 | `use_company_roundoff_cost_center` | Check | `smallint` | default=0 |  |
| 127 | `update_billed_amount_in_delivery_note` | Check | `smallint` | default=1 |  |
| 128 | `dont_create_loyalty_points` | Check | `smallint` | default=0 |  |
| 129 | `coupon_code` | Link | `varchar(140)` |  | → `Coupon Code` |
| 130 | `update_outstanding_for_self` | Check | `smallint` | default=1 |  |
| 131 | `utm_medium` | Link | `varchar(140)` |  | → `UTM Medium` *(frappe/Website)* |
| 132 | `utm_content` | Data | `varchar(140)` |  |  |
| 133 | `utm_campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |
| 134 | `utm_source` | Link | `varchar(140)` |  | → `UTM Source` *(frappe/Website)* |
| 135 | `company_contact_person` | Link | `varchar(140)` |  | → `Contact` *(frappe/Contacts)* |
| 136 | `is_created_using_pos` | Check | `smallint` | hidden, default=0 |  |
| 137 | `pos_closing_entry` | Link | `varchar(140)` | hidden | → `POS Closing Entry` |
| 138 | `has_subcontracted` | Check | `smallint` | ro, hidden, default=0 |  |
| 139 | `apply_tds` | Check | `smallint` | default=0 |  |
| 140 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |
| 141 | `ignore_tax_withholding_threshold` | Check | `smallint` | default=0 |  |
| 142 | `override_tax_withholding_entries` | Check | `smallint` | default=0 |  |
| 143 | `title` | Data | `varchar(140)` |  |  |

**Child tables (1-N):**

- `items` → `Sales Invoice Item` (line items)
- `pricing_rules` → `Pricing Rule Detail` (line items)
- `packed_items` → `Packed Item` (line items)
- `timesheets` → `Sales Invoice Timesheet` (line items)
- `taxes` → `Sales Taxes and Charges` (line items)
- `advances` → `Sales Invoice Advance` (line items)
- `payment_schedule` → `Payment Schedule` (line items)
- `payments` → `Sales Invoice Payment` (line items)
- `sales_team` → `Sales Team` (line items)
- `item_wise_tax_details` → `Item Wise Tax Detail` (line items)
- `tax_withholding_entries` → `Tax Withholding Entry` (line items)

**Referenced by (14):** `Discounted Invoice`.`sales_invoice`, `Overdue Payment`.`sales_invoice`, `POS Invoice`.`consolidated_invoice`, `POS Invoice Merge Log`.`consolidated_invoice`, `POS Invoice Merge Log`.`consolidated_credit_note`, `Purchase Invoice`.`inter_company_invoice_reference`, `Sales Invoice`.`amended_from`, `Sales Invoice`.`return_against`, `Sales Invoice Reference`.`sales_invoice`, `Sales Invoice Reference`.`return_against`, `Timesheet`.`sales_invoice`, `Timesheet Detail`.`sales_invoice`, `Delivery Note Item`.`against_sales_invoice`, `Stock Entry`.`sales_invoice_no`

## Share Transfer

- **Table**: `tabShare Transfer`  (proposed: `share_transfer`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Naming**: `ACC-SHT-.YYYY.-.#####`
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `transfer_type` | Select | `varchar(140)` | NOT NULL | enum: Issue, Purchase, Transfer |
| 2 | `date` | Date | `date` | NOT NULL |  |
| 3 | `from_shareholder` | Link | `varchar(140)` |  | → `Shareholder` |
| 4 | `from_folio_no` | Data | `varchar(140)` | denorm←from_shareholder.folio_no |  |
| 5 | `equity_or_liability_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 6 | `asset_account` | Link | `varchar(140)` |  | → `Account` |
| 7 | `to_shareholder` | Link | `varchar(140)` |  | → `Shareholder` |
| 8 | `to_folio_no` | Data | `varchar(140)` | denorm←to_shareholder.folio_no |  |
| 9 | `share_type` | Link | `varchar(140)` | NOT NULL | → `Share Type` |
| 10 | `from_no` | Int | `integer` | NOT NULL |  |
| 11 | `rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 12 | `no_of_shares` | Int | `integer` | NOT NULL |  |
| 13 | `to_no` | Int | `integer` | NOT NULL |  |
| 14 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 15 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 16 | `remarks` | Long Text | `text` |  |  |
| 17 | `amended_from` | Link | `varchar(140)` | ro | → `Share Transfer` |

**Referenced by (1):** `Share Transfer`.`amended_from`

## Unreconcile Payment

- **Table**: `tabUnreconcile Payment`  (proposed: `unreconcile_payment`)
- **Kind**: Transaction (submittable)
- **Owned by**: erpnext / Accounts
- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `amended_from` | Link | `varchar(140)` | ro | → `Unreconcile Payment` |
| 2 | `company` | Link | `varchar(140)` |  | → `Company` |
| 3 | `voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 4 | `voucher_no` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `voucher_type` |

**Child tables (1-N):**

- `allocations` → `Unreconcile Payment Entries` (line items)

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

**Referenced by (1):** `Unreconcile Payment`.`amended_from`

---

# Child / line-item tables

## Accounting Dimension Detail

- **Table**: `tabAccounting Dimension Detail`  (proposed: `accounting_dimension_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Accounting Dimension`.`dimension_defaults`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `reference_document` | Link | `varchar(140)` | ro, hidden | → `DocType` *(frappe/Core)* |
| 3 | `default_dimension` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `reference_document` |
| 4 | `mandatory_for_bs` | Check | `smallint` | default=0 |  |
| 5 | `mandatory_for_pl` | Check | `smallint` | default=0 |  |
| 6 | `automatically_post_balancing_accounting_entry` | Check | `smallint` | default=0 |  |
| 7 | `offsetting_account` | Link | `varchar(140)` |  | → `Account` |

**Polymorphic references:**

- `default_dimension` — target DocType read from `reference_document`

## Advance Taxes and Charges

- **Table**: `tabAdvance Taxes and Charges`  (proposed: `advance_taxes_and_charges`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Entry`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `charge_type` | Select | `varchar(140)` | NOT NULL | enum: Actual, On Paid Amount, On Previous Row Amount, On Previous Row Total |
| 2 | `row_id` | Data | `varchar(140)` |  |  |
| 3 | `account_head` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 4 | `description` | Small Text | `text` | NOT NULL |  |
| 5 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 6 | `project` | Link | `varchar(140)` |  | → `Project` |
| 7 | `rate` | Float | `numeric(21,9)` |  |  |
| 8 | `tax_amount` | Currency | `numeric(21,9)` |  |  |
| 9 | `total` | Currency | `numeric(21,9)` | ro |  |
| 10 | `base_tax_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 12 | `add_deduct_tax` | Select | `varchar(140)` | NOT NULL | enum: Add, Deduct |
| 13 | `included_in_paid_amount` | Check | `smallint` | default=0 |  |
| 14 | `currency` | Link | `varchar(140)` | ro, denorm←account_head.account_currency | → `Currency` *(frappe/Geo)* |
| 15 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 16 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 17 | `set_by_item_tax_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 18 | `is_tax_withholding_account` | Check | `smallint` | ro, default=0 |  |

## Allowed Dimension

- **Table**: `tabAllowed Dimension`  (proposed: `allowed_dimension`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Accounting Dimension Filter`.`dimensions`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `accounting_dimension` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `dimension_value` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `accounting_dimension` |

**Polymorphic references:**

- `dimension_value` — target DocType read from `accounting_dimension`

## Allowed To Transact With

- **Table**: `tabAllowed To Transact With`  (proposed: `allowed_to_transact_with`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Supplier`.`companies`, `Customer`.`companies`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

## Applicable On Account

- **Table**: `tabApplicable On Account`  (proposed: `applicable_on_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Accounting Dimension Filter`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `applicable_on_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `is_mandatory` | Check | `smallint` | default=0 |  |

## Bank Clearance Detail

- **Table**: `tabBank Clearance Detail`  (proposed: `bank_clearance_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank Clearance`.`payment_entries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_document` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 2 | `payment_entry` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `payment_document` |
| 3 | `against_account` | Data | `varchar(140)` | ro |  |
| 4 | `amount` | Data | `varchar(140)` | ro |  |
| 5 | `posting_date` | Date | `date` | ro |  |
| 6 | `cheque_number` | Data | `varchar(140)` | ro |  |
| 7 | `cheque_date` | Date | `date` | ro |  |
| 8 | `clearance_date` | Date | `date` |  |  |

**Polymorphic references:**

- `payment_entry` — target DocType read from `payment_document`

## Bank Statement Import Log Column Map

- **Table**: `tabBank Statement Import Log Column Map`  (proposed: `bank_statement_import_log_column_map`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank Statement Import Log`.`column_mapping`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `header_text` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `maps_to` | Select | `varchar(140)` | NOT NULL | enum: Do not import, Date, Withdrawal, Deposit, Amount, Description, Reference, Transaction Type … (+7) |
| 3 | `index` | Int | `integer` | NOT NULL |  |
| 4 | `variable` | Data | `varchar(140)` |  |  |

## Bank Transaction Mapping

- **Table**: `tabBank Transaction Mapping`  (proposed: `bank_transaction_mapping`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank`.`bank_transaction_mapping`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `bank_transaction_field` | Select | `varchar(140)` | NOT NULL |  |
| 2 | `file_field` | Data | `varchar(140)` | NOT NULL |  |

## Bank Transaction Payments

- **Table**: `tabBank Transaction Payments`  (proposed: `bank_transaction_payments`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank Transaction`.`payment_entries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_document` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 2 | `payment_entry` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `payment_document` |
| 3 | `allocated_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 4 | `clearance_date` | Date | `date` | ro |  |
| 5 | `reconciliation_type` | Select | `varchar(140)` | ro, default=Matched | enum: Matched, Voucher Created |

**Polymorphic references:**

- `payment_entry` — target DocType read from `payment_document`

## Bank Transaction Rule Accounts

- **Table**: `tabBank Transaction Rule Accounts`  (proposed: `bank_transaction_rule_accounts`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank Transaction Rule`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `party_type` | Link | `varchar(140)` |  | → `Party Type` |
| 3 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 4 | `debit` | Data | `varchar(140)` |  |  |
| 5 | `credit` | Data | `varchar(140)` |  |  |
| 6 | `user_remark` | Small Text | `text` |  |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

## Bank Transaction Rule Description Conditions

- **Table**: `tabBank Transaction Rule Description Conditions`  (proposed: `bank_transaction_rule_description_conditions`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Bank Transaction Rule`.`description_rules`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `check` | Select | `varchar(140)` | NOT NULL | enum: Contains, Starts With, Ends With, Regex |
| 2 | `value` | Small Text | `text` | NOT NULL |  |

## Budget Account

- **Table**: `tabBudget Account`  (proposed: `budget_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 2 | `budget_amount` | Currency | `numeric(21,9)` | NOT NULL |  |

## Budget Distribution

- **Table**: `tabBudget Distribution`  (proposed: `budget_distribution`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Budget`.`budget_distribution`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `start_date` | Date | `date` | NOT NULL, INDEX, ro |  |
| 2 | `end_date` | Date | `date` | NOT NULL, ro |  |
| 3 | `amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 4 | `percent` | Percent | `numeric(21,9)` | NOT NULL |  |

## Campaign Item

- **Table**: `tabCampaign Item`  (proposed: `campaign_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`campaign`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `campaign` | Link | `varchar(140)` |  | → `UTM Campaign` *(frappe/Website)* |

## Cashier Closing Payments

- **Table**: `tabCashier Closing Payments`  (proposed: `cashier_closing_payments`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Cashier Closing`.`payments`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `mode_of_payment` | Link | `varchar(140)` | NOT NULL | → `Mode of Payment` |
| 2 | `amount` | Float | `numeric(21,9)` | default=0.00 |  |

## Closed Document

- **Table**: `tabClosed Document`  (proposed: `closed_document`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Accounting Period`.`closed_documents`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `document_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 2 | `closed` | Check | `smallint` | default=0 |  |

## Cost Center Allocation Percentage

- **Table**: `tabCost Center Allocation Percentage`  (proposed: `cost_center_allocation_percentage`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Cost Center Allocation`.`allocation_percentages`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `cost_center` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |
| 2 | `percentage` | Percent | `numeric(21,9)` | NOT NULL |  |

## Currency Exchange Settings Details

- **Table**: `tabCurrency Exchange Settings Details`  (proposed: `currency_exchange_settings_details`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Currency Exchange Settings`.`req_params`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `key` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `value` | Data | `varchar(140)` | NOT NULL |  |

## Currency Exchange Settings Result

- **Table**: `tabCurrency Exchange Settings Result`  (proposed: `currency_exchange_settings_result`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Currency Exchange Settings`.`result_key`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `key` | Data | `varchar(140)` | NOT NULL |  |

## Customer Group Item

- **Table**: `tabCustomer Group Item`  (proposed: `customer_group_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`customer_group`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer_group` | Link | `varchar(140)` |  | → `Customer Group` |

## Customer Item

- **Table**: `tabCustomer Item`  (proposed: `customer_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`customer`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer` | Link | `varchar(140)` |  | → `Customer` |

## Discounted Invoice

- **Table**: `tabDiscounted Invoice`  (proposed: `discounted_invoice`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Invoice Discounting`.`invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_invoice` | Link | `varchar(140)` | NOT NULL, INDEX | → `Sales Invoice` |
| 2 | `customer` | Link | `varchar(140)` | ro, denorm←sales_invoice.customer | → `Customer` |
| 3 | `posting_date` | Date | `date` | ro, denorm←sales_invoice.posting_date |  |
| 4 | `outstanding_amount` | Currency | `numeric(21,9)` | denorm←sales_invoice.outstanding_amount |  |
| 5 | `debit_to` | Link | `varchar(140)` | ro, denorm←sales_invoice.debit_to | → `Account` |

## Dunning Letter Text

- **Table**: `tabDunning Letter Text`  (proposed: `dunning_letter_text`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Dunning Type`.`dunning_letter_text`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `language` | Link | `varchar(140)` |  | → `Language` *(frappe/Core)* |
| 2 | `is_default_language` | Check | `smallint` | default=0 |  |
| 3 | `body_text` | Text Editor | `text` |  |  |
| 4 | `closing_text` | Text Editor | `text` |  |  |

## Exchange Rate Revaluation Account

- **Table**: `tabExchange Rate Revaluation Account`  (proposed: `exchange_rate_revaluation_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Exchange Rate Revaluation`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 3 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 4 | `account_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 5 | `balance_in_account_currency` | Currency | `numeric(21,9)` | ro |  |
| 6 | `current_exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 7 | `balance_in_base_currency` | Currency | `numeric(21,9)` | ro |  |
| 8 | `new_exchange_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 9 | `new_balance_in_base_currency` | Currency | `numeric(21,9)` | ro |  |
| 10 | `gain_loss` | Currency | `numeric(21,9)` | ro |  |
| 11 | `zero_balance` | Check | `smallint` | default=0 |  |
| 12 | `new_balance_in_account_currency` | Currency | `numeric(21,9)` | ro |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

## Financial Report Row

- **Table**: `tabFinancial Report Row`  (proposed: `financial_report_row`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Financial Report Template`.`rows`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_code` | Data | `varchar(140)` |  |  |
| 2 | `display_name` | Data | `varchar(140)` |  |  |
| 3 | `indentation_level` | Int | `integer` |  |  |
| 4 | `data_source` | Select | `varchar(140)` |  | enum: Account Data, Calculated Amount, Custom API, Blank Line, Column Break, Section Break |
| 5 | `balance_type` | Select | `varchar(140)` |  | enum: Opening Balance, Closing Balance, Period Movement (Debits - Credits) |
| 6 | `bold_text` | Check | `smallint` | default=0 |  |
| 7 | `italic_text` | Check | `smallint` | default=0 |  |
| 8 | `hidden_calculation` | Check | `smallint` | default=0 |  |
| 9 | `hide_when_empty` | Check | `smallint` | default=0 |  |
| 10 | `reverse_sign` | Check | `smallint` | default=0 |  |
| 11 | `calculation_formula` | Code | `text` |  |  |
| 12 | `include_in_charts` | Check | `smallint` | default=0 |  |
| 13 | `color` | Color | `varchar(140)` |  |  |
| 14 | `fieldtype` | Select | `varchar(140)` |  | enum: Currency, Float, Int, Percent |
| 15 | `advanced_filtering` | Check | `smallint` | default=0 |  |

## Fiscal Year Company

- **Table**: `tabFiscal Year Company`  (proposed: `fiscal_year_company`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Fiscal Year`.`companies`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |

## Item Tax Template Detail

- **Table**: `tabItem Tax Template Detail`  (proposed: `item_tax_template_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Item Tax Template`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `tax_type` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `tax_rate` | Float | `numeric(21,9)` |  |  |
| 3 | `not_applicable` | Check | `smallint` | default=0 |  |

## Item Wise Tax Detail

- **Table**: `tabItem Wise Tax Detail`  (proposed: `item_wise_tax_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`item_wise_tax_details`, `Purchase Invoice`.`item_wise_tax_details`, `Sales Invoice`.`item_wise_tax_details`, `Purchase Order`.`item_wise_tax_details`, `Supplier Quotation`.`item_wise_tax_details`, `Quotation`.`item_wise_tax_details`, `Sales Order`.`item_wise_tax_details`, `Delivery Note`.`item_wise_tax_details`, `Purchase Receipt`.`item_wise_tax_details`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_row` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `tax_row` | Data | `varchar(140)` | NOT NULL |  |
| 3 | `rate` | Float | `numeric(21,9)` |  |  |
| 4 | `amount` | Currency | `numeric(21,9)` |  |  |
| 5 | `taxable_amount` | Currency | `numeric(21,9)` |  |  |

## Journal Entry Account

- **Table**: `tabJournal Entry Account`  (proposed: `journal_entry_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)
- **Embedded in**: `Journal Entry`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL, INDEX, denorm←bank_account.account | → `Account` |
| 2 | `account_type` | Data | `varchar(140)` | hidden |  |
| 3 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 4 | `party_type` | Link | `varchar(140)` | INDEX | → `DocType` *(frappe/Core)* |
| 5 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 6 | `account_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 7 | `exchange_rate` | Float | `numeric(21,9)` |  |  |
| 8 | `debit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 9 | `debit` | Currency | `numeric(21,9)` | ro |  |
| 10 | `credit_in_account_currency` | Currency | `numeric(21,9)` |  |  |
| 11 | `credit` | Currency | `numeric(21,9)` | ro |  |
| 12 | `reference_type` | Select | `varchar(140)` | INDEX | enum: Sales Invoice, Purchase Invoice, Journal Entry, Sales Order, Purchase Order, Expense Claim, Asset, Loan … (+8) |
| 13 | `reference_name` | Dynamic Link | `varchar(140)` | INDEX | → polymorphic, doctype in `reference_type` |
| 14 | `reference_due_date` | Date | `date` |  |  |
| 15 | `project` | Link | `varchar(140)` |  | → `Project` |
| 16 | `is_advance` | Select | `varchar(140)` |  | enum: No, Yes |
| 17 | `user_remark` | Small Text | `text` |  |  |
| 18 | `against_account` | Text | `text` | hidden |  |
| 19 | `bank_account` | Link | `varchar(140)` |  | → `Bank Account` |
| 20 | `reference_detail_no` | Data | `varchar(140)` | hidden |  |
| 21 | `advance_voucher_type` | Link | `varchar(140)` | INDEX, ro | → `DocType` *(frappe/Core)* |
| 22 | `advance_voucher_no` | Dynamic Link | `varchar(140)` | INDEX, ro | → polymorphic, doctype in `advance_voucher_type` |
| 23 | `is_tax_withholding_account` | Check | `smallint` | ro, default=0 |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `reference_name` — target DocType read from `reference_type`
- `advance_voucher_no` — target DocType read from `advance_voucher_type`

## Journal Entry Template Account

- **Table**: `tabJournal Entry Template Account`  (proposed: `journal_entry_template_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Journal Entry Template`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `party_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 3 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 4 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 5 | `project` | Link | `varchar(140)` |  | → `Project` |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

## Ledger Health Monitor Company

- **Table**: `tabLedger Health Monitor Company`  (proposed: `ledger_health_monitor_company`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Ledger Health Monitor`.`companies`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |

## Ledger Merge Accounts

- **Table**: `tabLedger Merge Accounts`  (proposed: `ledger_merge_accounts`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Ledger Merge`.`merge_accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `merged` | Check | `smallint` | ro, default=0 |  |
| 3 | `account_name` | Data | `varchar(140)` | NOT NULL, ro |  |

## Loyalty Point Entry Redemption

- **Table**: `tabLoyalty Point Entry Redemption`  (proposed: `loyalty_point_entry_redemption`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_invoice` | Data | `varchar(140)` |  |  |
| 2 | `redemption_date` | Date | `date` |  |  |
| 3 | `redeemed_points` | Int | `integer` |  |  |

## Loyalty Program Collection

- **Table**: `tabLoyalty Program Collection`  (proposed: `loyalty_program_collection`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Loyalty Program`.`collection_rules`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `tier_name` | Data | `varchar(140)` | NOT NULL |  |
| 2 | `min_spent` | Currency | `numeric(21,9)` |  |  |
| 3 | `collection_factor` | Currency | `numeric(21,9)` | NOT NULL |  |

## Mode of Payment Account

- **Table**: `tabMode of Payment Account`  (proposed: `mode_of_payment_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Mode of Payment`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` |  | → `Company` |
| 2 | `default_account` | Link | `varchar(140)` |  | → `Account` |

## Monthly Distribution Percentage

- **Table**: `tabMonthly Distribution Percentage`  (proposed: `monthly_distribution_percentage`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`
- **Embedded in**: `Monthly Distribution`.`percentages`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `month` | Data | `varchar(140)` | NOT NULL, ro |  |
| 2 | `percentage_allocation` | Float | `numeric(21,9)` |  |  |

## Opening Invoice Creation Tool Item

- **Table**: `tabOpening Invoice Creation Tool Item`  (proposed: `opening_invoice_creation_tool_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Opening Invoice Creation Tool`.`invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `party_type` | Link | `varchar(140)` | ro, hidden | → `DocType` *(frappe/Core)* |
| 2 | `party` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `party_type` |
| 3 | `temporary_opening_account` | Link | `varchar(140)` |  | → `Account` |
| 4 | `posting_date` | Date | `date` | default=Today |  |
| 5 | `due_date` | Date | `date` | default=Today |  |
| 6 | `item_name` | Data | `varchar(140)` | default=Opening Invoice Item |  |
| 7 | `outstanding_amount` | Currency | `numeric(21,9)` | NOT NULL, default=0 |  |
| 8 | `qty` | Data | `varchar(140)` | default=1 |  |
| 9 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 10 | `invoice_number` | Data | `varchar(140)` |  |  |
| 11 | `supplier_invoice_date` | Date | `date` |  |  |
| 12 | `party_name` | Data | `varchar(140)` |  |  |
| 13 | `project` | Link | `varchar(140)` |  | → `Project` |

**Polymorphic references:**

- `party` — target DocType read from `party_type`

## Overdue Payment

- **Table**: `tabOverdue Payment`  (proposed: `overdue_payment`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Dunning`.`overdue_payments`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_term` | Link | `varchar(140)` | ro | → `Payment Term` |
| 2 | `description` | Small Text | `text` | ro, denorm←payment_term.description |  |
| 3 | `due_date` | Date | `date` | ro |  |
| 4 | `mode_of_payment` | Link | `varchar(140)` | ro | → `Mode of Payment` |
| 5 | `invoice_portion` | Percent | `numeric(21,9)` | ro |  |
| 6 | `payment_amount` | Currency | `numeric(21,9)` | ro |  |
| 7 | `outstanding` | Currency | `numeric(21,9)` | ro, denorm←payment_amount |  |
| 8 | `paid_amount` | Currency | `numeric(21,9)` |  |  |
| 9 | `discounted_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 10 | `sales_invoice` | Link | `varchar(140)` | NOT NULL, ro | → `Sales Invoice` |
| 11 | `payment_schedule` | Data | `varchar(140)` | ro |  |
| 12 | `overdue_days` | Data | `varchar(140)` | ro |  |
| 13 | `dunning_level` | Int | `integer` | ro, default=1 |  |
| 14 | `interest` | Currency | `numeric(21,9)` | ro |  |

## POS Closing Entry Detail

- **Table**: `tabPOS Closing Entry Detail`  (proposed: `pos_closing_entry_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Closing Entry`.`payment_reconciliation`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `mode_of_payment` | Link | `varchar(140)` | NOT NULL | → `Mode of Payment` |
| 2 | `expected_amount` | Currency | `numeric(21,9)` | ro |  |
| 3 | `difference` | Currency | `numeric(21,9)` | ro |  |
| 4 | `opening_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 5 | `closing_amount` | Currency | `numeric(21,9)` | NOT NULL, default=0 |  |

## POS Closing Entry Taxes

- **Table**: `tabPOS Closing Entry Taxes`  (proposed: `pos_closing_entry_taxes`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Closing Entry`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 2 | `account_head` | Link | `varchar(140)` | ro | → `Account` |

## POS Customer Group

- **Table**: `tabPOS Customer Group`  (proposed: `pos_customer_group`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Profile`.`customer_groups`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer_group` | Link | `varchar(140)` | NOT NULL | → `Customer Group` |

## POS Field

- **Table**: `tabPOS Field`  (proposed: `pos_field`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Settings`.`invoice_fields`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `fieldname` | Select | `varchar(140)` |  |  |
| 2 | `fieldtype` | Data | `varchar(140)` | ro |  |
| 3 | `label` | Data | `varchar(140)` | ro |  |
| 4 | `options` | Text | `text` | ro |  |
| 5 | `reqd` | Check | `smallint` | default=0 |  |
| 6 | `read_only` | Check | `smallint` | default=0 |  |
| 7 | `default_value` | Data | `varchar(140)` |  |  |

## POS Invoice Item

- **Table**: `tabPOS Invoice Item`  (proposed: `pos_invoice_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)
- **Embedded in**: `POS Invoice`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `item_code` | Link | `varchar(140)` | INDEX | → `Item` |
| 3 | `is_product_bundle` | Check | `smallint` | ro, hidden, default=0 |  |
| 4 | `product_bundle` | Link | `varchar(140)` |  | → `Product Bundle` |
| 5 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 6 | `customer_item_code` | Data | `varchar(140)` | ro, hidden |  |
| 7 | `description` | Text Editor | `text` |  |  |
| 8 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 9 | `brand` | Data | `varchar(140)` | hidden |  |
| 10 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 11 | `qty` | Float | `numeric(21,9)` |  |  |
| 12 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 13 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 14 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 15 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 16 | `price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 17 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 18 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 19 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 20 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 21 | `discount_percentage` | Percent | `numeric(21,2)` |  |  |
| 22 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 23 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 24 | `rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 25 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 26 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 27 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 28 | `base_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 29 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 30 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 31 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 32 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 33 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 34 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 35 | `delivered_by_supplier` | Check | `smallint` | ro, default=0 |  |
| 36 | `income_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 37 | `is_fixed_asset` | Check | `smallint` | ro, hidden, default=0 |  |
| 38 | `asset` | Link | `varchar(140)` |  | → `Asset` |
| 39 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 40 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 41 | `deferred_revenue_account` | Link | `varchar(140)` |  | → `Account` |
| 42 | `service_stop_date` | Date | `date` |  |  |
| 43 | `enable_deferred_revenue` | Check | `smallint` | default=0 |  |
| 44 | `service_start_date` | Date | `date` |  |  |
| 45 | `service_end_date` | Date | `date` |  |  |
| 46 | `weight_per_unit` | Float | `numeric(21,9)` | ro |  |
| 47 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 48 | `weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 49 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 50 | `target_warehouse` | Link | `varchar(140)` | hidden | → `Warehouse` |
| 51 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 52 | `batch_no` | Link | `varchar(140)` |  | → `Batch` |
| 53 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 54 | `serial_no` | Text | `text` |  |  |
| 55 | `item_tax_rate` | Small Text | `text` | ro, hidden |  |
| 56 | `actual_batch_qty` | Float | `numeric(21,9)` | ro |  |
| 57 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 58 | `sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 59 | `so_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 60 | `delivery_note` | Link | `varchar(140)` | INDEX, ro | → `Delivery Note` |
| 61 | `dn_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 62 | `delivered_qty` | Float | `numeric(21,9)` | ro |  |
| 63 | `cost_center` | Link | `varchar(140)` | NOT NULL, default=:Company | → `Cost Center` |
| 64 | `page_break` | Check | `smallint` | default=0 |  |
| 65 | `project` | Link | `varchar(140)` |  | → `Project` |
| 66 | `pos_invoice_item` | Data | `varchar(140)` | ro |  |
| 67 | `grant_commission` | Check | `smallint` | ro, denorm←item_code.grant_commission, default=0 |  |
| 68 | `has_item_scanned` | Check | `smallint` | ro, default=0 |  |
| 69 | `serial_and_batch_bundle` | Link | `varchar(140)` |  | → `Serial and Batch Bundle` |
| 70 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 71 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |

## POS Invoice Reference

- **Table**: `tabPOS Invoice Reference`  (proposed: `pos_invoice_reference`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Closing Entry`.`pos_invoices`, `POS Invoice Merge Log`.`pos_invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `pos_invoice` | Link | `varchar(140)` | NOT NULL | → `POS Invoice` |
| 2 | `customer` | Link | `varchar(140)` | NOT NULL, ro, denorm←pos_invoice.customer | → `Customer` |
| 3 | `posting_date` | Date | `date` | NOT NULL, denorm←pos_invoice.posting_date |  |
| 4 | `grand_total` | Currency | `numeric(21,9)` | NOT NULL, denorm←pos_invoice.grand_total |  |
| 5 | `is_return` | Check | `smallint` | ro, denorm←pos_invoice.is_return, default=0 |  |
| 6 | `return_against` | Link | `varchar(140)` | ro, denorm←pos_invoice.return_against | → `POS Invoice` |

## POS Item Group

- **Table**: `tabPOS Item Group`  (proposed: `pos_item_group`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Profile`.`item_groups`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_group` | Link | `varchar(140)` | NOT NULL | → `Item Group` |

## POS Opening Entry Detail

- **Table**: `tabPOS Opening Entry Detail`  (proposed: `pos_opening_entry_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Opening Entry`.`balance_details`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `mode_of_payment` | Link | `varchar(140)` | NOT NULL | → `Mode of Payment` |
| 2 | `opening_amount` | Currency | `numeric(21,9)` | NOT NULL, default=0 |  |

## POS Payment Method

- **Table**: `tabPOS Payment Method`  (proposed: `pos_payment_method`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Profile`.`payments`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `default` | Check | `smallint` | default=0 |  |
| 2 | `mode_of_payment` | Link | `varchar(140)` | NOT NULL | → `Mode of Payment` |
| 3 | `allow_in_returns` | Check | `smallint` | default=0 |  |

## POS Profile User

- **Table**: `tabPOS Profile User`  (proposed: `pos_profile_user`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Profile`.`applicable_for_users`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `default` | Check | `smallint` | default=0 |  |
| 2 | `user` | Link | `varchar(140)` |  | → `User` *(frappe/Core)* |

## POS Search Fields

- **Table**: `tabPOS Search Fields`  (proposed: `pos_search_fields`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Settings`.`pos_search_fields`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `fieldname` | Data | `varchar(140)` | hidden |  |
| 2 | `field` | Select | `varchar(140)` | NOT NULL |  |

## PSOA Cost Center

- **Table**: `tabPSOA Cost Center`  (proposed: `psoa_cost_center`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Statement Of Accounts`.`cost_center`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `cost_center_name` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |

## PSOA Project

- **Table**: `tabPSOA Project`  (proposed: `psoa_project`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Statement Of Accounts`.`project`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `project_name` | Link | `varchar(140)` |  | → `Project` |

## Party Account

- **Table**: `tabParty Account`  (proposed: `party_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Supplier`.`accounts`, `Customer`.`accounts`, `Customer Group`.`accounts`, `Supplier Group`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `account` | Link | `varchar(140)` |  | → `Account` |
| 3 | `advance_account` | Link | `varchar(140)` |  | → `Account` |

## Payment Entry Deduction

- **Table**: `tabPayment Entry Deduction`  (proposed: `payment_entry_deduction`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Entry`.`deductions`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 2 | `cost_center` | Link | `varchar(140)` | NOT NULL | → `Cost Center` |
| 3 | `amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 4 | `description` | Small Text | `text` |  |  |
| 5 | `is_exchange_gain_loss` | Check | `smallint` | ro, default=0 |  |

## Payment Entry Reference

- **Table**: `tabPayment Entry Reference`  (proposed: `payment_entry_reference`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Entry`.`references`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_doctype` | Link | `varchar(140)` | NOT NULL, INDEX | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | NOT NULL, INDEX | → polymorphic, doctype in `reference_doctype` |
| 3 | `due_date` | Date | `date` | ro |  |
| 4 | `bill_no` | Data | `varchar(140)` | ro |  |
| 5 | `total_amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 7 | `allocated_amount` | Currency | `numeric(21,9)` |  |  |
| 8 | `exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 9 | `payment_term` | Link | `varchar(140)` |  | → `Payment Term` |
| 10 | `exchange_gain_loss` | Currency | `numeric(21,9)` | ro |  |
| 11 | `account` | Link | `varchar(140)` |  | → `Account` |
| 12 | `account_type` | Data | `varchar(140)` |  |  |
| 13 | `payment_type` | Data | `varchar(140)` |  |  |
| 14 | `payment_request` | Link | `varchar(140)` |  | → `Payment Request` |
| 15 | `payment_term_outstanding` | Float | `numeric(21,9)` | ro |  |
| 16 | `reconcile_effect_on` | Date | `date` | ro |  |
| 17 | `advance_voucher_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 18 | `advance_voucher_no` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `advance_voucher_type` |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_doctype`
- `advance_voucher_no` — target DocType read from `advance_voucher_type`

## Payment Order Reference

- **Table**: `tabPayment Order Reference`  (proposed: `payment_order_reference`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Order`.`references`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_doctype` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | NOT NULL, ro | → polymorphic, doctype in `reference_doctype` |
| 3 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 4 | `supplier` | Link | `varchar(140)` | ro | → `Supplier` |
| 5 | `payment_request` | Link | `varchar(140)` | ro | → `Payment Request` |
| 6 | `mode_of_payment` | Link | `varchar(140)` | ro, denorm←payment_request.mode_of_payment | → `Mode of Payment` |
| 7 | `bank_account` | Link | `varchar(140)` | NOT NULL, ro | → `Bank Account` |
| 8 | `account` | Link | `varchar(140)` | ro | → `Account` |
| 9 | `payment_reference` | Data | `varchar(140)` | ro |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_doctype`

## Payment Reconciliation Allocation

- **Table**: `tabPayment Reconciliation Allocation`  (proposed: `payment_reconciliation_allocation`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Reconciliation`.`allocation`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `invoice_number` | Dynamic Link | `varchar(140)` | NOT NULL, ro | → polymorphic, doctype in `invoice_type` |
| 2 | `allocated_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 3 | `difference_account` | Link | `varchar(140)` | ro | → `Account` |
| 4 | `difference_amount` | Currency | `numeric(21,9)` | ro |  |
| 5 | `reference_name` | Dynamic Link | `varchar(140)` | NOT NULL, ro | → polymorphic, doctype in `reference_type` |
| 6 | `is_advance` | Data | `varchar(140)` | ro, hidden |  |
| 7 | `reference_type` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 8 | `invoice_type` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 9 | `unreconciled_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 10 | `amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 11 | `reference_row` | Data | `varchar(140)` | ro, hidden |  |
| 12 | `currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |
| 13 | `exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 14 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 15 | `gain_loss_posting_date` | Date | `date` |  |  |
| 16 | `debit_or_credit_note_posting_date` | Date | `date` |  |  |

**Polymorphic references:**

- `invoice_number` — target DocType read from `invoice_type`
- `reference_name` — target DocType read from `reference_type`

## Payment Reconciliation Invoice

- **Table**: `tabPayment Reconciliation Invoice`  (proposed: `payment_reconciliation_invoice`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Reconciliation`.`invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `invoice_type` | Select | `varchar(140)` | ro | enum: Sales Invoice, Purchase Invoice, Journal Entry |
| 2 | `invoice_number` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `invoice_type` |
| 3 | `invoice_date` | Date | `date` | ro |  |
| 4 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 5 | `outstanding_amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |
| 7 | `exchange_rate` | Float | `numeric(21,9)` | hidden |  |

**Polymorphic references:**

- `invoice_number` — target DocType read from `invoice_type`

## Payment Reconciliation Payment

- **Table**: `tabPayment Reconciliation Payment`  (proposed: `payment_reconciliation_payment`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Reconciliation`.`payments`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `reference_type` |
| 3 | `posting_date` | Date | `date` | ro |  |
| 4 | `is_advance` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `reference_row` | Data | `varchar(140)` | ro, hidden |  |
| 6 | `amount` | Currency | `numeric(21,9)` | ro |  |
| 7 | `currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |
| 8 | `difference_amount` | Currency | `numeric(21,9)` | ro |  |
| 9 | `exchange_rate` | Float | `numeric(21,9)` | hidden |  |
| 10 | `cost_center` | Link | `varchar(140)` |  | → `Cost Center` |
| 11 | `remarks` | Small Text | `text` | ro |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_type`

## Payment Reference

- **Table**: `tabPayment Reference`  (proposed: `payment_reference`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Request`.`payment_reference`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_term` | Link | `varchar(140)` |  | → `Payment Term` |
| 2 | `description` | Small Text | `text` |  |  |
| 3 | `due_date` | Date | `date` |  |  |
| 4 | `amount` | Currency | `numeric(21,2)` |  |  |
| 5 | `currency` | Link | `varchar(140)` | ro, hidden | → `Currency` *(frappe/Geo)* |
| 6 | `payment_schedule` | Link | `varchar(140)` | ro | → `Payment Schedule` |

## Payment Schedule

- **Table**: `tabPayment Schedule`  (proposed: `payment_schedule`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`payment_schedule`, `Purchase Invoice`.`payment_schedule`, `Sales Invoice`.`payment_schedule`, `Purchase Order`.`payment_schedule`, `Quotation`.`payment_schedule`, `Sales Order`.`payment_schedule`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_term` | Link | `varchar(140)` |  | → `Payment Term` |
| 2 | `description` | Small Text | `text` | denorm←payment_term.description |  |
| 3 | `due_date` | Date | `date` | NOT NULL |  |
| 4 | `invoice_portion` | Percent | `numeric(21,9)` |  |  |
| 5 | `payment_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 6 | `mode_of_payment` | Link | `varchar(140)` |  | → `Mode of Payment` |
| 7 | `paid_amount` | Currency | `numeric(21,9)` |  |  |
| 8 | `discounted_amount` | Currency | `numeric(21,9)` | ro, default=0 |  |
| 9 | `outstanding` | Currency | `numeric(21,9)` | ro, denorm←payment_amount |  |
| 10 | `discount_date` | Date | `date` |  |  |
| 11 | `discount_type` | Select | `varchar(140)` | denorm←payment_term.discount_type, default=Percentage | enum: Percentage, Amount |
| 12 | `discount` | Float | `numeric(21,9)` | denorm←payment_term.discount |  |
| 13 | `base_payment_amount` | Currency | `numeric(21,9)` |  |  |
| 14 | `base_outstanding` | Currency | `numeric(21,9)` | ro |  |
| 15 | `base_paid_amount` | Currency | `numeric(21,9)` | ro |  |
| 16 | `due_date_based_on` | Select | `varchar(140)` | ro | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 17 | `credit_days` | Int | `integer` | ro |  |
| 18 | `credit_months` | Int | `integer` | ro |  |
| 19 | `discount_validity_based_on` | Select | `varchar(140)` | ro | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 20 | `discount_validity` | Int | `integer` | ro |  |

## Payment Terms Template Detail

- **Table**: `tabPayment Terms Template Detail`  (proposed: `payment_terms_template_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Terms Template`.`terms`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `payment_term` | Link | `varchar(140)` |  | → `Payment Term` |
| 2 | `description` | Small Text | `text` | denorm←payment_term.description |  |
| 3 | `invoice_portion` | Float | `numeric(21,9)` | NOT NULL, denorm←payment_term.invoice_portion |  |
| 4 | `due_date_based_on` | Select | `varchar(140)` | NOT NULL, denorm←payment_term.due_date_based_on | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 5 | `credit_days` | Int | `integer` | denorm←payment_term.credit_days, default=0 |  |
| 6 | `credit_months` | Int | `integer` | denorm←payment_term.credit_months, default=0 |  |
| 7 | `mode_of_payment` | Link | `varchar(140)` | denorm←payment_term.mode_of_payment | → `Mode of Payment` |
| 8 | `discount_type` | Select | `varchar(140)` | denorm←payment_term.discount_type, default=Percentage | enum: Percentage, Amount |
| 9 | `discount` | Float | `numeric(21,9)` | denorm←payment_term.discount |  |
| 10 | `discount_validity_based_on` | Select | `varchar(140)` | denorm←payment_term.discount_validity_based_on, default=Day(s) after invoice dat | enum: Day(s) after invoice date, Day(s) after the end of the invoice month, Month(s) after the end of the invoice month |
| 11 | `discount_validity` | Int | `integer` | denorm←payment_term.discount_validity |  |

## Pegged Currency Details

- **Table**: `tabPegged Currency Details`  (proposed: `pegged_currency_details`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Pegged Currencies`.`pegged_currency_item`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `source_currency` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |
| 2 | `pegged_exchange_rate` | Data | `varchar(140)` |  |  |
| 3 | `pegged_against` | Link | `varchar(140)` |  | → `Currency` *(frappe/Geo)* |

## Pricing Rule Brand

- **Table**: `tabPricing Rule Brand`  (proposed: `pricing_rule_brand`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Pricing Rule`.`brands`, `Promotional Scheme`.`brands`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `brand` | Link | `varchar(140)` | INDEX | → `Brand` |
| 2 | `uom` | Link | `varchar(140)` |  | → `UOM` |

## Pricing Rule Detail

- **Table**: `tabPricing Rule Detail`  (proposed: `pricing_rule_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`pricing_rules`, `Purchase Invoice`.`pricing_rules`, `Sales Invoice`.`pricing_rules`, `Purchase Order`.`pricing_rules`, `Supplier Quotation`.`pricing_rules`, `Quotation`.`pricing_rules`, `Sales Order`.`pricing_rules`, `Delivery Note`.`pricing_rules`, `Purchase Receipt`.`pricing_rules`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `pricing_rule` | Link | `varchar(140)` | ro | → `Pricing Rule` |
| 2 | `item_code` | Data | `varchar(140)` | ro |  |
| 3 | `margin_type` | Data | `varchar(140)` | ro, hidden |  |
| 4 | `rate_or_discount` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `child_docname` | Data | `varchar(140)` | ro, hidden |  |
| 6 | `rule_applied` | Check | `smallint` | ro, default=1 |  |

## Pricing Rule Item Code

- **Table**: `tabPricing Rule Item Code`  (proposed: `pricing_rule_item_code`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Pricing Rule`.`items`, `Promotional Scheme`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | INDEX | → `Item` |
| 2 | `uom` | Link | `varchar(140)` |  | → `UOM` |

## Pricing Rule Item Group

- **Table**: `tabPricing Rule Item Group`  (proposed: `pricing_rule_item_group`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Pricing Rule`.`item_groups`, `Promotional Scheme`.`item_groups`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_group` | Link | `varchar(140)` | INDEX | → `Item Group` |
| 2 | `uom` | Link | `varchar(140)` |  | → `UOM` |

## Process Payment Reconciliation Log Allocations

- **Table**: `tabProcess Payment Reconciliation Log Allocations`  (proposed: `process_payment_reconciliation_log_allocations`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Payment Reconciliation Log`.`allocations`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_type` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | NOT NULL, ro | → polymorphic, doctype in `reference_type` |
| 3 | `reference_row` | Data | `varchar(140)` | ro, hidden |  |
| 4 | `invoice_type` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 5 | `invoice_number` | Dynamic Link | `varchar(140)` | NOT NULL, ro | → polymorphic, doctype in `invoice_type` |
| 6 | `allocated_amount` | Currency | `numeric(21,9)` | NOT NULL |  |
| 7 | `unreconciled_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 8 | `amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 9 | `is_advance` | Data | `varchar(140)` | ro, hidden |  |
| 10 | `difference_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `difference_account` | Link | `varchar(140)` | ro | → `Account` |
| 12 | `exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 13 | `currency` | Link | `varchar(140)` | hidden | → `Currency` *(frappe/Geo)* |
| 14 | `reconciled` | Check | `smallint` | default=0 |  |
| 15 | `gain_loss_posting_date` | Date | `date` |  |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_type`
- `invoice_number` — target DocType read from `invoice_type`

## Process Period Closing Voucher Detail

- **Table**: `tabProcess Period Closing Voucher Detail`  (proposed: `process_period_closing_voucher_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Period Closing Voucher`.`normal_balances`, `Process Period Closing Voucher`.`z_opening_balances`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `processing_date` | Date | `date` |  |  |
| 2 | `status` | Select | `varchar(140)` | default=Queued | enum: Queued, Running, Paused, Completed, Cancelled |
| 3 | `closing_balance` | JSON | `jsonb` |  |  |
| 4 | `report_type` | Select | `varchar(140)` | default=Profit and Loss | enum: Profit and Loss, Balance Sheet |

## Process Statement Of Accounts CC

- **Table**: `tabProcess Statement Of Accounts CC`  (proposed: `process_statement_of_accounts_cc`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Statement Of Accounts`.`cc_to`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `cc` | Link | `varchar(140)` |  | → `User` *(frappe/Core)* |

## Process Statement Of Accounts Customer

- **Table**: `tabProcess Statement Of Accounts Customer`  (proposed: `process_statement_of_accounts_customer`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Process Statement Of Accounts`.`customers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `customer` | Link | `varchar(140)` | NOT NULL | → `Customer` |
| 2 | `primary_email` | Read Only | `varchar(140)` |  |  |
| 3 | `billing_email` | Data | `varchar(140)` |  |  |
| 4 | `customer_name` | Data | `varchar(140)` | ro, denorm←customer.customer_name |  |

## Promotional Scheme Price Discount

- **Table**: `tabPromotional Scheme Price Discount`  (proposed: `promotional_scheme_price_discount`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`price_discount_slabs`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `disable` | Check | `smallint` | default=0 |  |
| 2 | `rule_description` | Small Text | `text` | NOT NULL |  |
| 3 | `min_qty` | Float | `numeric(21,9)` | default=0 |  |
| 4 | `max_qty` | Float | `numeric(21,9)` | default=0 |  |
| 5 | `min_amount` | Currency | `numeric(21,9)` | default=0 |  |
| 6 | `max_amount` | Currency | `numeric(21,9)` | default=0 |  |
| 7 | `rate_or_discount` | Select | `varchar(140)` | default=Discount Percentage | enum: Rate, Discount Percentage, Discount Amount |
| 8 | `rate` | Currency | `numeric(21,9)` |  |  |
| 9 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 10 | `discount_percentage` | Float | `numeric(21,9)` |  |  |
| 11 | `for_price_list` | Link | `varchar(140)` |  | → `Price List` |
| 12 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 13 | `threshold_percentage` | Percent | `numeric(21,9)` |  |  |
| 14 | `validate_applied_rule` | Check | `smallint` | default=0 |  |
| 15 | `priority` | Select | `varchar(140)` |  | enum: 1, 2, 3, 4, 5, 6, 7, 8 … (+12) |
| 16 | `apply_multiple_pricing_rules` | Check | `smallint` | default=0 |  |
| 17 | `apply_discount_on_rate` | Check | `smallint` | default=0 |  |

## Promotional Scheme Product Discount

- **Table**: `tabPromotional Scheme Product Discount`  (proposed: `promotional_scheme_product_discount`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`product_discount_slabs`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `disable` | Check | `smallint` | default=0 |  |
| 2 | `rule_description` | Small Text | `text` | NOT NULL |  |
| 3 | `min_qty` | Float | `numeric(21,9)` | default=0 |  |
| 4 | `max_qty` | Float | `numeric(21,9)` | default=0 |  |
| 5 | `min_amount` | Currency | `numeric(21,9)` | default=0 |  |
| 6 | `max_amount` | Currency | `numeric(21,9)` | default=0 |  |
| 7 | `same_item` | Check | `smallint` | default=0 |  |
| 8 | `free_item` | Link | `varchar(140)` |  | → `Item` |
| 9 | `free_qty` | Float | `numeric(21,9)` |  |  |
| 10 | `free_item_uom` | Link | `varchar(140)` |  | → `UOM` |
| 11 | `free_item_rate` | Currency | `numeric(21,9)` |  |  |
| 12 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 13 | `threshold_percentage` | Percent | `numeric(21,9)` |  |  |
| 14 | `priority` | Select | `varchar(140)` |  | enum: 1, 2, 3, 4, 5, 6, 7, 8 … (+12) |
| 15 | `apply_multiple_pricing_rules` | Check | `smallint` | default=0 |  |
| 16 | `is_recursive` | Check | `smallint` | default=0 |  |
| 17 | `recurse_for` | Float | `numeric(21,9)` | default=0 |  |
| 18 | `apply_recursion_over` | Float | `numeric(21,9)` | default=0 |  |
| 19 | `round_free_qty` | Check | `smallint` | default=0 |  |

## Purchase Invoice Advance

- **Table**: `tabPurchase Invoice Advance`  (proposed: `purchase_invoice_advance`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Purchase Invoice`.`advances`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `reference_type` |
| 3 | `remarks` | Text | `text` | ro |  |
| 4 | `reference_row` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `advance_amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `allocated_amount` | Currency | `numeric(21,9)` |  |  |
| 7 | `exchange_gain_loss` | Currency | `numeric(21,9)` | ro |  |
| 8 | `ref_exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 9 | `difference_posting_date` | Date | `date` |  |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_type`

## Purchase Invoice Item

- **Table**: `tabPurchase Invoice Item`  (proposed: `purchase_invoice_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)
- **Embedded in**: `Purchase Invoice`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `item_code` | Link | `varchar(140)` | INDEX | → `Item` |
| 2 | `item_name` | Data | `varchar(140)` | NOT NULL, denorm←item_code.item_name |  |
| 3 | `description` | Text Editor | `text` |  |  |
| 4 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 5 | `received_qty` | Float | `numeric(21,9)` | ro |  |
| 6 | `qty` | Float | `numeric(21,9)` | NOT NULL |  |
| 7 | `rejected_qty` | Float | `numeric(21,9)` |  |  |
| 8 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 9 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 10 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 11 | `stock_qty` | Float | `numeric(21,9)` | NOT NULL, ro |  |
| 12 | `price_list_rate` | Currency | `numeric(21,9)` |  |  |
| 13 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 14 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 15 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 17 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 18 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 19 | `base_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 20 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 21 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 22 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 23 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 24 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 25 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 26 | `weight_per_unit` | Float | `numeric(21,9)` |  |  |
| 27 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 28 | `weight_uom` | Link | `varchar(140)` |  | → `UOM` |
| 29 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 30 | `rejected_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 31 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 32 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 33 | `serial_no` | Text | `text` |  |  |
| 34 | `rejected_serial_no` | Text | `text` |  |  |
| 35 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 36 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 37 | `project` | Link | `varchar(140)` | INDEX | → `Project` |
| 38 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 39 | `deferred_expense_account` | Link | `varchar(140)` |  | → `Account` |
| 40 | `service_stop_date` | Date | `date` |  |  |
| 41 | `enable_deferred_expense` | Check | `smallint` | default=0 |  |
| 42 | `service_start_date` | Date | `date` |  |  |
| 43 | `service_end_date` | Date | `date` |  |  |
| 44 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 45 | `brand` | Link | `varchar(140)` | hidden | → `Brand` |
| 46 | `item_group` | Link | `varchar(140)` | ro, denorm←item_code.item_group | → `Item Group` |
| 47 | `item_tax_rate` | Code | `text` | ro, hidden |  |
| 48 | `item_tax_amount` | Currency | `numeric(21,9)` | ro, hidden |  |
| 49 | `purchase_order` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 50 | `include_exploded_items` | Check | `smallint` | ro, default=0 |  |
| 51 | `is_fixed_asset` | Check | `smallint` | ro, hidden, denorm←item_code.is_fixed_asset, default=0 |  |
| 52 | `asset_location` | Link | `varchar(140)` |  | → `Location` |
| 53 | `po_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 54 | `purchase_receipt` | Link | `varchar(140)` | INDEX, ro | → `Purchase Receipt` |
| 55 | `page_break` | Check | `smallint` | default=0 |  |
| 56 | `pr_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 57 | `valuation_rate` | Currency | `numeric(21,9)` | ro, hidden |  |
| 58 | `rm_supp_cost` | Currency | `numeric(21,9)` | ro, hidden |  |
| 59 | `landed_cost_voucher_amount` | Currency | `numeric(21,9)` | ro |  |
| 60 | `manufacturer` | Link | `varchar(140)` |  | → `Manufacturer` |
| 61 | `manufacturer_part_no` | Data | `varchar(140)` |  |  |
| 62 | `asset_category` | Link | `varchar(140)` | ro, denorm←item_code.asset_category | → `Asset Category` |
| 63 | `from_warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 64 | `purchase_invoice_item` | Data | `varchar(140)` | ro |  |
| 65 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 66 | `sales_invoice_item` | Data | `varchar(140)` | ro |  |
| 67 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 68 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 69 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 70 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 71 | `product_bundle` | Link | `varchar(140)` | ro, hidden | → `Product Bundle` |
| 72 | `apply_tds` | Check | `smallint` | default=1 |  |
| 73 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 74 | `rejected_serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 75 | `wip_composite_asset` | Link | `varchar(140)` |  | → `Asset` |
| 76 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 77 | `material_request` | Link | `varchar(140)` | INDEX, ro | → `Material Request` |
| 78 | `material_request_item` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 79 | `sales_incoming_rate` | Currency | `numeric(21,9)` | hidden |  |
| 80 | `distributed_discount_amount` | Currency | `numeric(21,9)` |  |  |
| 81 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 82 | `delivered_by_supplier` | Check | `smallint` | ro, hidden, default=0 |  |

## Purchase Taxes and Charges

- **Table**: `tabPurchase Taxes and Charges`  (proposed: `purchase_taxes_and_charges`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)
- **Embedded in**: `Purchase Invoice`.`taxes`, `Purchase Taxes and Charges Template`.`taxes`, `Purchase Order`.`taxes`, `Supplier Quotation`.`taxes`, `Purchase Receipt`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `category` | Select | `varchar(140)` | NOT NULL, default=Total | enum: Valuation and Total, Valuation, Total |
| 2 | `add_deduct_tax` | Select | `varchar(140)` | NOT NULL, default=Add | enum: Add, Deduct |
| 3 | `charge_type` | Select | `varchar(140)` | NOT NULL, default=On Net Total | enum: Actual, On Net Total, On Previous Row Amount, On Previous Row Total, On Item Quantity |
| 4 | `row_id` | Data | `varchar(140)` |  |  |
| 5 | `allocate_full_amount_to_stock_items` | Check | `smallint` | default=1 |  |
| 6 | `included_in_print_rate` | Check | `smallint` | default=0 |  |
| 7 | `account_head` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 8 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 9 | `description` | Small Text | `text` | NOT NULL |  |
| 10 | `rate` | Float | `numeric(21,9)` |  |  |
| 11 | `tax_amount` | Currency | `numeric(21,9)` |  |  |
| 12 | `tax_amount_after_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 13 | `total` | Currency | `numeric(21,9)` | ro |  |
| 14 | `base_tax_amount` | Currency | `numeric(21,9)` | ro |  |
| 15 | `base_total` | Currency | `numeric(21,9)` | hidden |  |
| 16 | `base_tax_amount_after_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 17 | `project` | Link | `varchar(140)` |  | → `Project` |
| 18 | `included_in_paid_amount` | Check | `smallint` | default=0 |  |
| 19 | `account_currency` | Link | `varchar(140)` | ro, denorm←account_head.account_currency | → `Currency` *(frappe/Geo)* |
| 20 | `is_tax_withholding_account` | Check | `smallint` | ro, default=0 |  |
| 21 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 22 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 23 | `set_by_item_tax_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 24 | `dont_recompute_tax` | Check | `smallint` | ro, hidden, default=0 |  |

## Repost Accounting Ledger Items

- **Table**: `tabRepost Accounting Ledger Items`  (proposed: `repost_accounting_ledger_items`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Repost Accounting Ledger`.`vouchers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `voucher_type` | Link | `varchar(140)` | NOT NULL | → `DocType` *(frappe/Core)* |
| 2 | `voucher_no` | Dynamic Link | `varchar(140)` | NOT NULL | → polymorphic, doctype in `voucher_type` |
| 3 | `status` | Select | `varchar(140)` | ro, default=Pending | enum: Pending, Reposted, Skipped, Failed |
| 4 | `traceback` | Code | `text` | ro |  |

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

## Repost Allowed Types

- **Table**: `tabRepost Allowed Types`  (proposed: `repost_allowed_types`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Accounts Settings`.`repost_allowed_types`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `document_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |

## Repost Payment Ledger Items

- **Table**: `tabRepost Payment Ledger Items`  (proposed: `repost_payment_ledger_items`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Repost Payment Ledger`.`repost_vouchers`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `voucher_type` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 2 | `voucher_no` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `voucher_type` |

**Polymorphic references:**

- `voucher_no` — target DocType read from `voucher_type`

## Sales Invoice Advance

- **Table**: `tabSales Invoice Advance`  (proposed: `sales_invoice_advance`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`advances`, `Sales Invoice`.`advances`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `reference_name` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `reference_type` |
| 3 | `remarks` | Text | `text` | ro |  |
| 4 | `reference_row` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `advance_amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `allocated_amount` | Currency | `numeric(21,9)` |  |  |
| 7 | `exchange_gain_loss` | Currency | `numeric(21,9)` | ro |  |
| 8 | `ref_exchange_rate` | Float | `numeric(21,9)` | ro |  |
| 9 | `difference_posting_date` | Date | `date` |  |  |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_type`

## Sales Invoice Item

- **Table**: `tabSales Invoice Item`  (proposed: `sales_invoice_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `hash`  (Random)
- **Embedded in**: `Sales Invoice`.`items`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `barcode` | Data | `varchar(140)` |  |  |
| 2 | `item_code` | Link | `varchar(140)` | INDEX | → `Item` |
| 3 | `is_product_bundle` | Check | `smallint` | ro, hidden, default=0 |  |
| 4 | `product_bundle` | Link | `varchar(140)` |  | → `Product Bundle` |
| 5 | `item_name` | Data | `varchar(140)` | NOT NULL |  |
| 6 | `customer_item_code` | Data | `varchar(140)` | ro, hidden |  |
| 7 | `description` | Text Editor | `text` |  |  |
| 8 | `image` | Attach | `text` | hidden, denorm←item_code.image |  |
| 9 | `qty` | Float | `numeric(21,9)` |  |  |
| 10 | `stock_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 11 | `uom` | Link | `varchar(140)` | NOT NULL | → `UOM` |
| 12 | `conversion_factor` | Float | `numeric(21,9)` | NOT NULL |  |
| 13 | `stock_qty` | Float | `numeric(21,9)` | ro |  |
| 14 | `price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 15 | `base_price_list_rate` | Currency | `numeric(21,9)` | ro |  |
| 16 | `margin_type` | Select | `varchar(140)` |  | enum: Percentage, Amount |
| 17 | `margin_rate_or_amount` | Float | `numeric(21,9)` |  |  |
| 18 | `rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 19 | `discount_percentage` | Percent | `numeric(21,9)` |  |  |
| 20 | `discount_amount` | Currency | `numeric(21,9)` |  |  |
| 21 | `base_rate_with_margin` | Currency | `numeric(21,9)` | ro |  |
| 22 | `rate` | Currency | `numeric(21,9)` | NOT NULL |  |
| 23 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 24 | `base_rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 25 | `base_amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 26 | `pricing_rules` | Small Text | `text` | ro, hidden |  |
| 27 | `is_free_item` | Check | `smallint` | ro, default=0 |  |
| 28 | `net_rate` | Currency | `numeric(21,9)` | ro |  |
| 29 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 30 | `base_net_rate` | Currency | `numeric(21,9)` | ro |  |
| 31 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 32 | `delivered_by_supplier` | Check | `smallint` | ro, default=0 |  |
| 33 | `income_account` | Link | `varchar(140)` | NOT NULL | → `Account` |
| 34 | `expense_account` | Link | `varchar(140)` |  | → `Account` |
| 35 | `item_tax_template` | Link | `varchar(140)` |  | → `Item Tax Template` |
| 36 | `cost_center` | Link | `varchar(140)` | NOT NULL, default=:Company | → `Cost Center` |
| 37 | `deferred_revenue_account` | Link | `varchar(140)` |  | → `Account` |
| 38 | `service_stop_date` | Date | `date` |  |  |
| 39 | `enable_deferred_revenue` | Check | `smallint` | default=0 |  |
| 40 | `service_start_date` | Date | `date` |  |  |
| 41 | `service_end_date` | Date | `date` |  |  |
| 42 | `weight_per_unit` | Float | `numeric(21,9)` | ro |  |
| 43 | `total_weight` | Float | `numeric(21,9)` | ro |  |
| 44 | `weight_uom` | Link | `varchar(140)` | ro | → `UOM` |
| 45 | `warehouse` | Link | `varchar(140)` |  | → `Warehouse` |
| 46 | `target_warehouse` | Link | `varchar(140)` | hidden | → `Warehouse` |
| 47 | `quality_inspection` | Link | `varchar(140)` |  | → `Quality Inspection` |
| 48 | `batch_no` | Link | `varchar(140)` | INDEX | → `Batch` |
| 49 | `allow_zero_valuation_rate` | Check | `smallint` | default=0 |  |
| 50 | `serial_no` | Text | `text` |  |  |
| 51 | `item_group` | Link | `varchar(140)` | ro, hidden | → `Item Group` |
| 52 | `brand` | Data | `varchar(140)` | hidden |  |
| 53 | `item_tax_rate` | Small Text | `text` | ro, hidden |  |
| 54 | `actual_batch_qty` | Float | `numeric(21,9)` | ro |  |
| 55 | `actual_qty` | Float | `numeric(21,9)` | ro |  |
| 56 | `sales_order` | Link | `varchar(140)` | INDEX, ro | → `Sales Order` |
| 57 | `so_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 58 | `delivery_note` | Link | `varchar(140)` | INDEX, ro | → `Delivery Note` |
| 59 | `dn_detail` | Data | `varchar(140)` | INDEX, ro, hidden |  |
| 60 | `delivered_qty` | Float | `numeric(21,9)` | ro |  |
| 61 | `is_fixed_asset` | Check | `smallint` | ro, hidden, default=0 |  |
| 62 | `asset` | Link | `varchar(140)` |  | → `Asset` |
| 63 | `page_break` | Check | `smallint` | default=0 |  |
| 64 | `finance_book` | Link | `varchar(140)` |  | → `Finance Book` |
| 65 | `project` | Link | `varchar(140)` | INDEX | → `Project` |
| 66 | `sales_invoice_item` | Data | `varchar(140)` | ro |  |
| 67 | `incoming_rate` | Currency | `numeric(21,9)` |  |  |
| 68 | `stock_uom_rate` | Currency | `numeric(21,9)` | ro |  |
| 69 | `discount_account` | Link | `varchar(140)` |  | → `Account` |
| 70 | `grant_commission` | Check | `smallint` | ro, denorm←item_code.grant_commission, default=0 |  |
| 71 | `purchase_order` | Link | `varchar(140)` | INDEX, ro | → `Purchase Order` |
| 72 | `purchase_order_item` | Data | `varchar(140)` | ro |  |
| 73 | `has_item_scanned` | Check | `smallint` | ro, default=0 |  |
| 74 | `serial_and_batch_bundle` | Link | `varchar(140)` | INDEX | → `Serial and Batch Bundle` |
| 75 | `use_serial_batch_fields` | Check | `smallint` | default=0 |  |
| 76 | `distributed_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 77 | `company_total_stock` | Float | `numeric(21,9)` | ro |  |
| 78 | `pos_invoice_item` | Data | `varchar(140)` | ro |  |
| 79 | `pos_invoice` | Link | `varchar(140)` | INDEX | → `POS Invoice` |
| 80 | `scio_detail` | Data | `varchar(140)` | ro, hidden |  |
| 81 | `tax_withholding_category` | Link | `varchar(140)` |  | → `Tax Withholding Category` |
| 82 | `apply_tds` | Check | `smallint` | ro, default=1 |  |
| 83 | `against_pick_list` | Link | `varchar(140)` | ro, hidden | → `Pick List` |
| 84 | `pick_list_item` | Data | `varchar(140)` | ro, hidden |  |

## Sales Invoice Payment

- **Table**: `tabSales Invoice Payment`  (proposed: `sales_invoice_payment`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`payments`, `Sales Invoice`.`payments`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `mode_of_payment` | Link | `varchar(140)` | NOT NULL | → `Mode of Payment` |
| 2 | `amount` | Currency | `numeric(21,9)` | NOT NULL, default=0 |  |
| 3 | `account` | Link | `varchar(140)` | ro | → `Account` |
| 4 | `type` | Read Only | `varchar(140)` | denorm←mode_of_payment.type |  |
| 5 | `base_amount` | Currency | `numeric(21,9)` | ro |  |
| 6 | `clearance_date` | Date | `date` | ro |  |
| 7 | `default` | Check | `smallint` | ro, hidden, default=0 |  |
| 8 | `reference_no` | Data | `varchar(140)` |  |  |

## Sales Invoice Reference

- **Table**: `tabSales Invoice Reference`  (proposed: `sales_invoice_reference`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Closing Entry`.`sales_invoices`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_invoice` | Link | `varchar(140)` | NOT NULL | → `Sales Invoice` |
| 2 | `posting_date` | Date | `date` | NOT NULL |  |
| 3 | `customer` | Link | `varchar(140)` | NOT NULL, ro, denorm←sales_invoice.customer | → `Customer` |
| 4 | `is_return` | Check | `smallint` | ro, denorm←sales_invoice.is_return, default=0 |  |
| 5 | `return_against` | Link | `varchar(140)` | ro, denorm←sales_invoice.return_against | → `Sales Invoice` |
| 6 | `grand_total` | Currency | `numeric(21,9)` | NOT NULL, denorm←sales_invoice.grand_total |  |

## Sales Invoice Timesheet

- **Table**: `tabSales Invoice Timesheet`  (proposed: `sales_invoice_timesheet`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`timesheets`, `Sales Invoice`.`timesheets`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `time_sheet` | Link | `varchar(140)` | ro | → `Timesheet` |
| 2 | `billing_hours` | Float | `numeric(21,9)` | ro |  |
| 3 | `billing_amount` | Currency | `numeric(21,9)` | ro |  |
| 4 | `timesheet_detail` | Data | `varchar(140)` | ro, hidden |  |
| 5 | `activity_type` | Link | `varchar(140)` | ro | → `Activity Type` |
| 6 | `description` | Small Text | `text` | ro |  |
| 7 | `from_time` | Datetime | `timestamp` |  |  |
| 8 | `to_time` | Datetime | `timestamp` |  |  |
| 9 | `project_name` | Data | `varchar(140)` | ro |  |

## Sales Partner Item

- **Table**: `tabSales Partner Item`  (proposed: `sales_partner_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`sales_partner`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `sales_partner` | Link | `varchar(140)` |  | → `Sales Partner` |

## Sales Taxes and Charges

- **Table**: `tabSales Taxes and Charges`  (proposed: `sales_taxes_and_charges`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `POS Invoice`.`taxes`, `Sales Invoice`.`taxes`, `Sales Taxes and Charges Template`.`taxes`, `Quotation`.`taxes`, `Sales Order`.`taxes`, `Delivery Note`.`taxes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `charge_type` | Select | `varchar(140)` | NOT NULL | enum: Actual, On Net Total, On Previous Row Amount, On Previous Row Total, On Item Quantity |
| 2 | `row_id` | Data | `varchar(140)` |  |  |
| 3 | `account_head` | Link | `varchar(140)` | NOT NULL, INDEX | → `Account` |
| 4 | `cost_center` | Link | `varchar(140)` | default=:Company | → `Cost Center` |
| 5 | `description` | Small Text | `text` | NOT NULL |  |
| 6 | `included_in_print_rate` | Check | `smallint` | default=0 |  |
| 7 | `rate` | Float | `numeric(21,9)` |  |  |
| 8 | `tax_amount` | Currency | `numeric(21,9)` |  |  |
| 9 | `total` | Currency | `numeric(21,9)` | ro |  |
| 10 | `tax_amount_after_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 11 | `base_tax_amount` | Currency | `numeric(21,9)` | ro |  |
| 12 | `base_total` | Currency | `numeric(21,9)` | ro |  |
| 13 | `base_tax_amount_after_discount_amount` | Currency | `numeric(21,9)` | ro |  |
| 14 | `project` | Link | `varchar(140)` |  | → `Project` |
| 15 | `included_in_paid_amount` | Check | `smallint` | default=0 |  |
| 16 | `dont_recompute_tax` | Check | `smallint` | ro, hidden, default=0 |  |
| 17 | `account_currency` | Link | `varchar(140)` | ro, denorm←account_head.account_currency | → `Currency` *(frappe/Geo)* |
| 18 | `net_amount` | Currency | `numeric(21,9)` | ro |  |
| 19 | `base_net_amount` | Currency | `numeric(21,9)` | ro |  |
| 20 | `set_by_item_tax_template` | Check | `smallint` | ro, hidden, default=0 |  |
| 21 | `is_tax_withholding_account` | Check | `smallint` | ro, default=0 |  |

## Share Balance

- **Table**: `tabShare Balance`  (proposed: `share_balance`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Shareholder`.`share_balance`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `share_type` | Link | `varchar(140)` | NOT NULL, ro | → `Share Type` |
| 2 | `from_no` | Int | `integer` | NOT NULL, ro |  |
| 3 | `rate` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 4 | `no_of_shares` | Int | `integer` | NOT NULL, ro |  |
| 5 | `to_no` | Int | `integer` | NOT NULL, ro |  |
| 6 | `amount` | Currency | `numeric(21,9)` | NOT NULL, ro |  |
| 7 | `is_company` | Check | `smallint` | ro, hidden, default=0 |  |
| 8 | `current_state` | Select | `varchar(140)` | ro, hidden | enum: Issued, Purchased |

## Shipping Rule Condition

- **Table**: `tabShipping Rule Condition`  (proposed: `shipping_rule_condition`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Description**: A condition for a Shipping Rule
- **Embedded in**: `Shipping Rule`.`conditions`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `from_value` | Float | `numeric(21,9)` | NOT NULL |  |
| 2 | `to_value` | Float | `numeric(21,9)` |  |  |
| 3 | `shipping_amount` | Currency | `numeric(21,9)` | NOT NULL |  |

## Shipping Rule Country

- **Table**: `tabShipping Rule Country`  (proposed: `shipping_rule_country`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Shipping Rule`.`countries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `country` | Link | `varchar(140)` | NOT NULL | → `Country` *(frappe/Geo)* |

## South Africa VAT Account

- **Table**: `tabSouth Africa VAT Account`  (proposed: `south_africa_vat_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Naming**: `account`
- **Embedded in**: `South Africa VAT Settings`.`vat_accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `account` | Link | `varchar(140)` |  | → `Account` |

## Subscription Invoice

- **Table**: `tabSubscription Invoice`  (proposed: `subscription_invoice`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `document_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `invoice` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `document_type` |

**Polymorphic references:**

- `invoice` — target DocType read from `document_type`

## Subscription Plan Detail

- **Table**: `tabSubscription Plan Detail`  (proposed: `subscription_plan_detail`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Payment Request`.`subscription_plans`, `Subscription`.`plans`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `qty` | Int | `integer` | NOT NULL |  |
| 2 | `plan` | Link | `varchar(140)` | NOT NULL | → `Subscription Plan` |

## Supplier Group Item

- **Table**: `tabSupplier Group Item`  (proposed: `supplier_group_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`supplier_group`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier_group` | Link | `varchar(140)` |  | → `Supplier Group` |

## Supplier Item

- **Table**: `tabSupplier Item`  (proposed: `supplier_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`supplier`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `supplier` | Link | `varchar(140)` |  | → `Supplier` |

## Tax Withholding Account

- **Table**: `tabTax Withholding Account`  (proposed: `tax_withholding_account`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Tax Withholding Category`.`accounts`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `company` | Link | `varchar(140)` | NOT NULL | → `Company` |
| 2 | `account` | Link | `varchar(140)` | NOT NULL | → `Account` |

## Tax Withholding Entry

- **Table**: `tabTax Withholding Entry`  (proposed: `tax_withholding_entry`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Journal Entry`.`tax_withholding_entries`, `Payment Entry`.`tax_withholding_entries`, `Purchase Invoice`.`tax_withholding_entries`, `Sales Invoice`.`tax_withholding_entries`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `party_type` | Link | `varchar(140)` | ro | → `DocType` *(frappe/Core)* |
| 2 | `party` | Dynamic Link | `varchar(140)` | ro | → polymorphic, doctype in `party_type` |
| 3 | `tax_id` | Data | `varchar(140)` | ro |  |
| 4 | `tax_withholding_category` | Link | `varchar(140)` | ro | → `Tax Withholding Category` |
| 5 | `tax_rate` | Percent | `numeric(21,9)` |  |  |
| 6 | `taxable_amount` | Currency | `numeric(21,9)` |  |  |
| 7 | `lower_deduction_certificate` | Link | `varchar(140)` | ro | → `Lower Deduction Certificate` |
| 8 | `status` | Select | `varchar(140)` | ro | enum: Settled, Under Withheld, Over Withheld, Duplicate, Cancelled |
| 9 | `currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |
| 10 | `conversion_rate` | Float | `numeric(21,9)` | ro |  |
| 11 | `withholding_doctype` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 12 | `withholding_name` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `withholding_doctype` |
| 13 | `taxable_doctype` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 14 | `taxable_name` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `taxable_doctype` |
| 15 | `taxable_date` | Date | `date` | ro |  |
| 16 | `withholding_date` | Date | `date` | ro |  |
| 17 | `under_withheld_reason` | Select | `varchar(140)` | ro | enum: Threshold Exemption, Lower Deduction Certificate |
| 18 | `withholding_amount` | Currency | `numeric(21,9)` | ro |  |
| 19 | `tax_withholding_group` | Link | `varchar(140)` | ro | → `Tax Withholding Group` |
| 20 | `company` | Link | `varchar(140)` |  | → `Company` |
| 21 | `created_by_migration` | Check | `smallint` | ro, hidden, default=0 |  |

**Polymorphic references:**

- `party` — target DocType read from `party_type`
- `withholding_name` — target DocType read from `withholding_doctype`
- `taxable_name` — target DocType read from `taxable_doctype`

## Tax Withholding Rate

- **Table**: `tabTax Withholding Rate`  (proposed: `tax_withholding_rate`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Tax Withholding Category`.`rates`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `tax_withholding_rate` | Float | `numeric(21,9)` | NOT NULL |  |
| 2 | `single_threshold` | Float | `numeric(21,9)` |  |  |
| 3 | `cumulative_threshold` | Float | `numeric(21,9)` |  |  |
| 4 | `from_date` | Date | `date` | NOT NULL |  |
| 5 | `to_date` | Date | `date` | NOT NULL |  |
| 6 | `tax_withholding_group` | Link | `varchar(140)` |  | → `Tax Withholding Group` |

## Territory Item

- **Table**: `tabTerritory Item`  (proposed: `territory_item`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Promotional Scheme`.`territory`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `territory` | Link | `varchar(140)` |  | → `Territory` |

## Transaction Deletion Record Details

- **Table**: `tabTransaction Deletion Record Details`  (proposed: `transaction_deletion_record_details`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Transaction Deletion Record`.`doctypes`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `doctype_name` | Link | `varchar(140)` | NOT NULL, ro | → `DocType` *(frappe/Core)* |
| 2 | `docfield_name` | Data | `varchar(140)` | ro |  |
| 3 | `no_of_docs` | Int | `integer` | ro |  |
| 4 | `done` | Check | `smallint` | ro, default=0 |  |

## Unreconcile Payment Entries

- **Table**: `tabUnreconcile Payment Entries`  (proposed: `unreconcile_payment_entries`)
- **Kind**: Child / line-item table
- **Owned by**: erpnext / Accounts
- **Embedded in**: `Unreconcile Payment`.`allocations`

| # | Column | Type | Postgres | Constraints / notes | Reference |
|--:|---|---|---|---|---|
| 1 | `reference_name` | Dynamic Link | `varchar(140)` |  | → polymorphic, doctype in `reference_doctype` |
| 2 | `allocated_amount` | Currency | `numeric(21,9)` |  |  |
| 3 | `unlinked` | Check | `smallint` | ro, default=0 |  |
| 4 | `reference_doctype` | Link | `varchar(140)` |  | → `DocType` *(frappe/Core)* |
| 5 | `account` | Data | `varchar(140)` |  |  |
| 6 | `party_type` | Data | `varchar(140)` |  |  |
| 7 | `party` | Data | `varchar(140)` |  |  |
| 8 | `account_currency` | Link | `varchar(140)` | ro | → `Currency` *(frappe/Geo)* |

**Polymorphic references:**

- `reference_name` — target DocType read from `reference_doctype`
