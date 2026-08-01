-- ============================================================
-- Accounts - AS-IS DDL (PostgreSQL) generated from DocType JSON
-- Mirrors the ERPNext physical layout: business-key PK, no FK constraints.
-- ============================================================

-- Account (tree-master)
CREATE TABLE "tabAccount" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account_name varchar(140),
  account_number varchar(140),
  is_group smallint,
  company varchar(140),
  root_type varchar(140),
  report_type varchar(140),
  account_currency varchar(140),
  parent_account varchar(140),
  account_type varchar(140),
  tax_rate numeric(21,9),
  freeze_account varchar(140),
  balance_must_be varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140),
  include_in_gross smallint,
  disabled smallint,
  account_category varchar(140)
);
CREATE INDEX ix_account_parent_account ON "tabAccount" (parent_account);
CREATE INDEX ix_account_account_type ON "tabAccount" (account_type);
CREATE INDEX ix_account_lft ON "tabAccount" (lft);
CREATE INDEX ix_account_rgt ON "tabAccount" (rgt);

-- Account Category (master)
CREATE TABLE "tabAccount Category" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account_category_name varchar(140),
  description text,
  root_type varchar(140)
);

-- Account Closing Balance (transaction)
CREATE TABLE "tabAccount Closing Balance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  closing_date date,
  account varchar(140),
  cost_center varchar(140),
  debit numeric(21,9),
  credit numeric(21,9),
  account_currency varchar(140),
  debit_in_account_currency numeric(21,9),
  credit_in_account_currency numeric(21,9),
  project varchar(140),
  company varchar(140),
  finance_book varchar(140),
  period_closing_voucher varchar(140),
  is_period_closing_voucher_entry smallint,
  debit_in_reporting_currency numeric(21,9),
  credit_in_reporting_currency numeric(21,9),
  reporting_currency_exchange_rate numeric(21,9)
);
CREATE INDEX ix_account_closing_balance_closing_date ON "tabAccount Closing Balance" (closing_date);
CREATE INDEX ix_account_closing_balance_account ON "tabAccount Closing Balance" (account);
CREATE INDEX ix_account_closing_balance_company ON "tabAccount Closing Balance" (company);
CREATE INDEX ix_account_closing_balance_period_closing_voucher ON "tabAccount Closing Balance" (period_closing_voucher);

-- Accounting Dimension (master)
CREATE TABLE "tabAccounting Dimension" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  label varchar(140),
  fieldname varchar(140),
  document_type varchar(140),
  disabled smallint
);
CREATE INDEX ix_accounting_dimension_document_type ON "tabAccounting Dimension" (document_type);

-- Accounting Dimension Detail (child)
CREATE TABLE "tabAccounting Dimension Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  reference_document varchar(140),
  default_dimension varchar(140),
  mandatory_for_bs smallint,
  mandatory_for_pl smallint,
  automatically_post_balancing_accounting_entry smallint,
  offsetting_account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_accounting_dimension_detail_parent ON "tabAccounting Dimension Detail" (parent);

-- Accounting Dimension Filter (master)
CREATE TABLE "tabAccounting Dimension Filter" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  accounting_dimension varchar(140),
  allow_or_restrict varchar(140),
  disabled smallint,
  company varchar(140),
  apply_restriction_on_values smallint,
  fieldname varchar(140)
);

-- Accounting Period (master)
CREATE TABLE "tabAccounting Period" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  period_name varchar(140),
  start_date date,
  end_date date,
  company varchar(140),
  disabled smallint,
  exempted_role varchar(140)
);

-- Advance Payment Ledger Entry (transaction)
CREATE TABLE "tabAdvance Payment Ledger Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  voucher_type varchar(140),
  voucher_no varchar(140),
  against_voucher_type varchar(140),
  against_voucher_no varchar(140),
  amount numeric(21,9),
  currency varchar(140),
  event varchar(140),
  company varchar(140),
  delinked smallint,
  base_amount numeric(21,9),
  exchange_rate numeric(21,9)
);

-- Advance Taxes and Charges (child)
CREATE TABLE "tabAdvance Taxes and Charges" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  charge_type varchar(140),
  row_id varchar(140),
  account_head varchar(140),
  description text,
  cost_center varchar(140),
  project varchar(140),
  rate numeric(21,9),
  tax_amount numeric(21,9),
  total numeric(21,9),
  base_tax_amount numeric(21,9),
  base_total numeric(21,9),
  add_deduct_tax varchar(140),
  included_in_paid_amount smallint,
  currency varchar(140),
  net_amount numeric(21,9),
  base_net_amount numeric(21,9),
  set_by_item_tax_template smallint,
  is_tax_withholding_account smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_advance_taxes_and_charges_account_head ON "tabAdvance Taxes and Charges" (account_head);
CREATE INDEX ix_advance_taxes_and_charges_parent ON "tabAdvance Taxes and Charges" (parent);

-- Allowed Dimension (child)
CREATE TABLE "tabAllowed Dimension" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  accounting_dimension varchar(140),
  dimension_value varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_allowed_dimension_parent ON "tabAllowed Dimension" (parent);

-- Allowed To Transact With (child)
CREATE TABLE "tabAllowed To Transact With" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_allowed_to_transact_with_parent ON "tabAllowed To Transact With" (parent);

-- Applicable On Account (child)
CREATE TABLE "tabApplicable On Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  applicable_on_account varchar(140),
  is_mandatory smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_applicable_on_account_parent ON "tabApplicable On Account" (parent);

-- Bank (master)
CREATE TABLE "tabBank" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  bank_name varchar(140),
  swift_number varchar(140),
  website varchar(140),
  plaid_access_token varchar(140)
);

-- Bank Account (master)
CREATE TABLE "tabBank Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account_name varchar(140),
  account varchar(140),
  bank varchar(140),
  account_type varchar(140),
  account_subtype varchar(140),
  is_default smallint,
  is_company_account smallint,
  company varchar(140),
  party_type varchar(140),
  party varchar(140),
  iban varchar(140),
  bank_account_no varchar(140),
  statement_password text,
  integration_id varchar(140),
  last_integration_date date,
  mask varchar(140),
  branch_code varchar(140),
  disabled smallint,
  is_credit_card smallint
);

-- Bank Account Balance (master)
CREATE TABLE "tabBank Account Balance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  bank_account varchar(140),
  date date,
  balance numeric(21,9),
  company varchar(140)
);

-- Bank Account Subtype (master)
CREATE TABLE "tabBank Account Subtype" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account_subtype varchar(140)
);

-- Bank Account Type (master)
CREATE TABLE "tabBank Account Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account_type varchar(140)
);

-- Bank Clearance Detail (child)
CREATE TABLE "tabBank Clearance Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_document varchar(140),
  payment_entry varchar(140),
  against_account varchar(140),
  amount varchar(140),
  posting_date date,
  cheque_number varchar(140),
  cheque_date date,
  clearance_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_clearance_detail_parent ON "tabBank Clearance Detail" (parent);

-- Bank Guarantee (transaction)
CREATE TABLE "tabBank Guarantee" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  bg_type varchar(140),
  reference_doctype varchar(140),
  reference_docname varchar(140),
  customer varchar(140),
  supplier varchar(140),
  project varchar(140),
  amount numeric(21,9),
  start_date date,
  validity integer,
  end_date date,
  bank varchar(140),
  bank_account varchar(140),
  account varchar(140),
  bank_account_no varchar(140),
  iban varchar(140),
  branch_code varchar(140),
  swift_number varchar(140),
  more_information text,
  bank_guarantee_number varchar(140),
  name_of_beneficiary varchar(140),
  margin_money numeric(21,9),
  charges numeric(21,9),
  fixed_deposit_number varchar(140),
  amended_from varchar(140)
);

-- Bank Statement Import (master)
CREATE TABLE "tabBank Statement Import" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  bank_account varchar(140),
  bank varchar(140),
  import_file text,
  template_options text,
  status varchar(140),
  template_warnings text,
  show_failed_logs smallint,
  google_sheets_url varchar(140),
  reference_doctype varchar(140),
  import_type varchar(140),
  submit_after_import smallint,
  mute_emails smallint,
  custom_delimiters smallint,
  delimiter_options varchar(140),
  use_csv_sniffer smallint,
  import_mt940_fromat smallint
);

-- Bank Statement Import Log (master)
CREATE TABLE "tabBank Statement Import Log" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  bank_account varchar(140),
  number_of_transactions integer,
  closing_balance numeric(21,9),
  start_date date,
  end_date date,
  file text,
  detected_date_format varchar(140),
  detected_amount_format varchar(140),
  detected_header_index integer,
  detected_transaction_starting_index integer,
  detected_transaction_ending_index integer,
  pdf_tables jsonb,
  status varchar(140),
  currency varchar(140),
  total_debits numeric(21,9),
  total_credits numeric(21,9),
  total_debit_transactions integer,
  total_credit_transactions integer
);

-- Bank Statement Import Log Column Map (child)
CREATE TABLE "tabBank Statement Import Log Column Map" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  header_text varchar(140),
  maps_to varchar(140),
  index integer,
  variable varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_statement_import_log_column_map_parent ON "tabBank Statement Import Log Column Map" (parent);

-- Bank Transaction (transaction)
CREATE TABLE "tabBank Transaction" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  date date,
  status varchar(140),
  bank_account varchar(140),
  company varchar(140),
  currency varchar(140),
  description text,
  reference_number text,
  transaction_id varchar(140),
  allocated_amount numeric(21,9),
  amended_from varchar(140),
  unallocated_amount numeric(21,9),
  party_type varchar(140),
  party varchar(140),
  deposit numeric(21,9),
  withdrawal numeric(21,9),
  transaction_type varchar(140),
  bank_party_name varchar(140),
  bank_party_iban varchar(140),
  bank_party_account_number varchar(140),
  included_fee numeric(21,9),
  excluded_fee numeric(21,9),
  is_rule_evaluated smallint,
  matched_transaction_rule varchar(140)
);

-- Bank Transaction Mapping (child)
CREATE TABLE "tabBank Transaction Mapping" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  bank_transaction_field varchar(140),
  file_field varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_transaction_mapping_parent ON "tabBank Transaction Mapping" (parent);

-- Bank Transaction Payments (child)
CREATE TABLE "tabBank Transaction Payments" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_document varchar(140),
  payment_entry varchar(140),
  allocated_amount numeric(21,9),
  clearance_date date,
  reconciliation_type varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_transaction_payments_parent ON "tabBank Transaction Payments" (parent);

-- Bank Transaction Rule (master)
CREATE TABLE "tabBank Transaction Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  rule_name varchar(140),
  transaction_type varchar(140),
  min_amount numeric(21,9),
  max_amount numeric(21,9),
  rule_description text,
  classify_as varchar(140),
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  priority integer,
  company varchar(140),
  bank_entry_type varchar(140)
);

-- Bank Transaction Rule Accounts (child)
CREATE TABLE "tabBank Transaction Rule Accounts" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  debit varchar(140),
  credit varchar(140),
  user_remark text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_transaction_rule_accounts_parent ON "tabBank Transaction Rule Accounts" (parent);

-- Bank Transaction Rule Description Conditions (child)
CREATE TABLE "tabBank Transaction Rule Description Conditions" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  "check" varchar(140),
  value text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_bank_transaction_rule_description_conditions_parent ON "tabBank Transaction Rule Description Conditions" (parent);

-- Bisect Nodes (master)
CREATE TABLE "tabBisect Nodes" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  root varchar(140),
  left_child varchar(140),
  right_child varchar(140),
  period_from_date timestamp,
  period_to_date timestamp,
  difference numeric(21,9),
  balance_sheet_summary numeric(21,9),
  profit_loss_summary numeric(21,9),
  generated smallint
);

-- Budget (transaction)
CREATE TABLE "tabBudget" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  budget_against varchar(140),
  company varchar(140),
  cost_center varchar(140),
  project varchar(140),
  amended_from varchar(140),
  applicable_on_material_request smallint,
  action_if_annual_budget_exceeded_on_mr varchar(140),
  action_if_accumulated_monthly_budget_exceeded_on_mr varchar(140),
  applicable_on_purchase_order smallint,
  action_if_annual_budget_exceeded_on_po varchar(140),
  action_if_accumulated_monthly_budget_exceeded_on_po varchar(140),
  applicable_on_booking_actual_expenses smallint,
  action_if_annual_budget_exceeded varchar(140),
  action_if_accumulated_monthly_budget_exceeded varchar(140),
  naming_series varchar(140),
  applicable_on_cumulative_expense smallint,
  action_if_annual_exceeded_on_cumulative_expense varchar(140),
  action_if_accumulated_monthly_exceeded_on_cumulative_expense varchar(140),
  account varchar(140),
  budget_amount numeric(21,9),
  revision_of varchar(140),
  distribute_equally smallint,
  from_fiscal_year varchar(140),
  to_fiscal_year varchar(140),
  budget_start_date date,
  budget_end_date date,
  distribution_frequency varchar(140),
  budget_distribution_total numeric(21,9)
);

-- Budget Account (child)
CREATE TABLE "tabBudget Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  budget_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_budget_account_account ON "tabBudget Account" (account);
CREATE INDEX ix_budget_account_parent ON "tabBudget Account" (parent);

-- Budget Distribution (child)
CREATE TABLE "tabBudget Distribution" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  start_date date,
  end_date date,
  amount numeric(21,9),
  percent numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_budget_distribution_start_date ON "tabBudget Distribution" (start_date);
CREATE INDEX ix_budget_distribution_parent ON "tabBudget Distribution" (parent);

-- Campaign Item (child)
CREATE TABLE "tabCampaign Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  campaign varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_campaign_item_parent ON "tabCampaign Item" (parent);

-- Cashier Closing (transaction)
CREATE TABLE "tabCashier Closing" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  "user" varchar(140),
  date date,
  from_time time(6),
  time time(6),
  expense numeric(21,9),
  custody numeric(21,9),
  returns numeric(21,2),
  outstanding_amount numeric(21,9),
  net_amount numeric(21,9),
  amended_from varchar(140)
);

-- Cashier Closing Payments (child)
CREATE TABLE "tabCashier Closing Payments" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  mode_of_payment varchar(140),
  amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_cashier_closing_payments_parent ON "tabCashier Closing Payments" (parent);

-- Cheque Print Template (master)
CREATE TABLE "tabCheque Print Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  has_print_format smallint,
  bank_name varchar(140),
  cheque_size varchar(140),
  starting_position_from_top_edge numeric(21,2),
  cheque_width numeric(21,2),
  cheque_height numeric(21,2),
  scanned_cheque text,
  is_account_payable smallint,
  acc_pay_dist_from_top_edge numeric(21,2),
  acc_pay_dist_from_left_edge numeric(21,2),
  message_to_show varchar(140),
  date_dist_from_top_edge numeric(21,2),
  date_dist_from_left_edge numeric(21,2),
  payer_name_from_top_edge numeric(21,2),
  payer_name_from_left_edge numeric(21,2),
  amt_in_words_from_top_edge numeric(21,2),
  amt_in_words_from_left_edge numeric(21,2),
  amt_in_word_width numeric(21,2),
  amt_in_words_line_spacing numeric(21,2),
  amt_in_figures_from_top_edge numeric(21,2),
  amt_in_figures_from_left_edge numeric(21,2),
  acc_no_dist_from_top_edge numeric(21,2),
  acc_no_dist_from_left_edge numeric(21,2),
  signatory_from_top_edge numeric(21,2),
  signatory_from_left_edge numeric(21,2)
);

-- Closed Document (child)
CREATE TABLE "tabClosed Document" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  document_type varchar(140),
  closed smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_closed_document_parent ON "tabClosed Document" (parent);

-- Cost Center (tree-master)
CREATE TABLE "tabCost Center" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  cost_center_name varchar(140),
  cost_center_number varchar(140),
  parent_cost_center varchar(140),
  company varchar(140),
  is_group smallint,
  lft integer,
  rgt integer,
  old_parent varchar(140),
  disabled smallint
);
CREATE INDEX ix_cost_center_lft ON "tabCost Center" (lft);
CREATE INDEX ix_cost_center_rgt ON "tabCost Center" (rgt);

-- Cost Center Allocation (transaction)
CREATE TABLE "tabCost Center Allocation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  main_cost_center varchar(140),
  valid_from date,
  company varchar(140),
  amended_from varchar(140)
);

-- Cost Center Allocation Percentage (child)
CREATE TABLE "tabCost Center Allocation Percentage" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  cost_center varchar(140),
  percentage numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_cost_center_allocation_percentage_parent ON "tabCost Center Allocation Percentage" (parent);

-- Coupon Code (master)
CREATE TABLE "tabCoupon Code" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  coupon_name varchar(140),
  coupon_type varchar(140),
  customer varchar(140),
  coupon_code varchar(140),
  pricing_rule varchar(140),
  valid_from date,
  valid_upto date,
  maximum_use integer,
  used integer,
  description text,
  amended_from varchar(140),
  from_external_ecomm_platform smallint
);

-- Currency Exchange Settings Details (child)
CREATE TABLE "tabCurrency Exchange Settings Details" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  key varchar(140),
  value varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_currency_exchange_settings_details_parent ON "tabCurrency Exchange Settings Details" (parent);

-- Currency Exchange Settings Result (child)
CREATE TABLE "tabCurrency Exchange Settings Result" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  key varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_currency_exchange_settings_result_parent ON "tabCurrency Exchange Settings Result" (parent);

-- Customer Group Item (child)
CREATE TABLE "tabCustomer Group Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_customer_group_item_parent ON "tabCustomer Group Item" (parent);

-- Customer Item (child)
CREATE TABLE "tabCustomer Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_customer_item_parent ON "tabCustomer Item" (parent);

-- Discounted Invoice (child)
CREATE TABLE "tabDiscounted Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  sales_invoice varchar(140),
  customer varchar(140),
  posting_date date,
  outstanding_amount numeric(21,9),
  debit_to varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_discounted_invoice_sales_invoice ON "tabDiscounted Invoice" (sales_invoice);
CREATE INDEX ix_discounted_invoice_parent ON "tabDiscounted Invoice" (parent);

-- Dunning (transaction)
CREATE TABLE "tabDunning" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  naming_series varchar(140),
  customer_name varchar(140),
  posting_date date,
  dunning_type varchar(140),
  dunning_fee numeric(21,2),
  language varchar(140),
  letter_head varchar(140),
  amended_from varchar(140),
  body_text text,
  closing_text text,
  posting_time time(6),
  rate_of_interest numeric(21,9),
  address_display text,
  contact_display text,
  contact_mobile text,
  company_address_display text,
  contact_email varchar(140),
  customer varchar(140),
  grand_total numeric(21,2),
  status varchar(140),
  income_account varchar(140),
  total_interest numeric(21,2),
  total_outstanding numeric(21,9),
  customer_address varchar(140),
  contact_person varchar(140),
  dunning_amount numeric(21,9),
  cost_center varchar(140),
  spacer varchar(140),
  company_address varchar(140),
  currency varchar(140),
  conversion_rate numeric(21,9),
  base_dunning_amount numeric(21,9)
);

-- Dunning Letter Text (child)
CREATE TABLE "tabDunning Letter Text" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  language varchar(140),
  is_default_language smallint,
  body_text text,
  closing_text text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_dunning_letter_text_parent ON "tabDunning Letter Text" (parent);

-- Dunning Type (master)
CREATE TABLE "tabDunning Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  dunning_type varchar(140),
  dunning_fee numeric(21,9),
  rate_of_interest numeric(21,9),
  is_default smallint,
  income_account varchar(140),
  cost_center varchar(140),
  company varchar(140)
);

-- Exchange Rate Revaluation (transaction)
CREATE TABLE "tabExchange Rate Revaluation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  company varchar(140),
  amended_from varchar(140),
  gain_loss_unbooked numeric(21,9),
  gain_loss_booked numeric(21,9),
  total_gain_loss numeric(21,9),
  rounding_loss_allowance numeric(21,9)
);

-- Exchange Rate Revaluation Account (child)
CREATE TABLE "tabExchange Rate Revaluation Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  account_currency varchar(140),
  balance_in_account_currency numeric(21,9),
  current_exchange_rate numeric(21,9),
  balance_in_base_currency numeric(21,9),
  new_exchange_rate numeric(21,9),
  new_balance_in_base_currency numeric(21,9),
  gain_loss numeric(21,9),
  zero_balance smallint,
  new_balance_in_account_currency numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_exchange_rate_revaluation_account_parent ON "tabExchange Rate Revaluation Account" (parent);

-- Finance Book (master)
CREATE TABLE "tabFinance Book" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  finance_book_name varchar(140)
);

-- Financial Report Row (child)
CREATE TABLE "tabFinancial Report Row" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_code varchar(140),
  display_name varchar(140),
  indentation_level integer,
  data_source varchar(140),
  balance_type varchar(140),
  bold_text smallint,
  italic_text smallint,
  hidden_calculation smallint,
  hide_when_empty smallint,
  reverse_sign smallint,
  calculation_formula text,
  include_in_charts smallint,
  color varchar(140),
  fieldtype varchar(140),
  advanced_filtering smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_financial_report_row_parent ON "tabFinancial Report Row" (parent);

-- Financial Report Template (master)
CREATE TABLE "tabFinancial Report Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  template_name varchar(140),
  report_type varchar(140),
  module varchar(140),
  disabled smallint
);

-- Fiscal Year (master)
CREATE TABLE "tabFiscal Year" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  year varchar(140),
  disabled smallint,
  year_start_date date,
  year_end_date date,
  auto_created smallint,
  is_short_year smallint
);

-- Fiscal Year Company (child)
CREATE TABLE "tabFiscal Year Company" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_fiscal_year_company_parent ON "tabFiscal Year Company" (parent);

-- GL Entry (transaction)
CREATE TABLE "tabGL Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  transaction_date date,
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  cost_center varchar(140),
  debit numeric(21,9),
  credit numeric(21,9),
  account_currency varchar(140),
  debit_in_account_currency numeric(21,9),
  credit_in_account_currency numeric(21,9),
  against text,
  against_voucher_type varchar(140),
  against_voucher varchar(140),
  voucher_type varchar(140),
  voucher_no varchar(140),
  voucher_detail_no varchar(140),
  project varchar(140),
  remarks text,
  is_opening varchar(140),
  is_advance varchar(140),
  fiscal_year varchar(140),
  company varchar(140),
  finance_book varchar(140),
  to_rename smallint,
  due_date date,
  is_cancelled smallint,
  transaction_currency varchar(140),
  transaction_exchange_rate numeric(21,9),
  debit_in_transaction_currency numeric(21,9),
  credit_in_transaction_currency numeric(21,9),
  voucher_subtype text,
  debit_in_reporting_currency numeric(21,9),
  credit_in_reporting_currency numeric(21,9),
  reporting_currency_exchange_rate numeric(21,9)
);
CREATE INDEX ix_gl_entry_posting_date ON "tabGL Entry" (posting_date);
CREATE INDEX ix_gl_entry_account ON "tabGL Entry" (account);
CREATE INDEX ix_gl_entry_party_type ON "tabGL Entry" (party_type);
CREATE INDEX ix_gl_entry_party ON "tabGL Entry" (party);
CREATE INDEX ix_gl_entry_cost_center ON "tabGL Entry" (cost_center);
CREATE INDEX ix_gl_entry_against_voucher ON "tabGL Entry" (against_voucher);
CREATE INDEX ix_gl_entry_voucher_no ON "tabGL Entry" (voucher_no);
CREATE INDEX ix_gl_entry_voucher_detail_no ON "tabGL Entry" (voucher_detail_no);
CREATE INDEX ix_gl_entry_company ON "tabGL Entry" (company);
CREATE INDEX ix_gl_entry_to_rename ON "tabGL Entry" (to_rename);

-- Invoice Discounting (transaction)
CREATE TABLE "tabInvoice Discounting" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  loan_start_date date,
  loan_period integer,
  loan_end_date date,
  status varchar(140),
  company varchar(140),
  total_amount numeric(21,9),
  bank_charges numeric(21,9),
  short_term_loan varchar(140),
  bank_account varchar(140),
  bank_charges_account varchar(140),
  accounts_receivable_credit varchar(140),
  accounts_receivable_discounted varchar(140),
  accounts_receivable_unpaid varchar(140),
  amended_from varchar(140)
);

-- Item Tax Template (master)
CREATE TABLE "tabItem Tax Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  company varchar(140),
  disabled smallint
);

-- Item Tax Template Detail (child)
CREATE TABLE "tabItem Tax Template Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  tax_type varchar(140),
  tax_rate numeric(21,9),
  not_applicable smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_tax_template_detail_parent ON "tabItem Tax Template Detail" (parent);

-- Item Wise Tax Detail (child)
CREATE TABLE "tabItem Wise Tax Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_row varchar(140),
  tax_row varchar(140),
  rate numeric(21,9),
  amount numeric(21,9),
  taxable_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_wise_tax_detail_parent ON "tabItem Wise Tax Detail" (parent);

-- Journal Entry (transaction)
CREATE TABLE "tabJournal Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  voucher_type varchar(140),
  naming_series varchar(140),
  posting_date date,
  company varchar(140),
  finance_book varchar(140),
  cheque_no varchar(140),
  cheque_date date,
  user_remark text,
  total_debit numeric(21,9),
  total_credit numeric(21,9),
  difference numeric(21,9),
  multi_currency smallint,
  total_amount_currency varchar(140),
  total_amount numeric(21,9),
  total_amount_in_words varchar(140),
  clearance_date date,
  remark text,
  inter_company_journal_entry_reference varchar(140),
  bill_no varchar(140),
  bill_date date,
  due_date date,
  write_off_based_on varchar(140),
  write_off_amount numeric(21,9),
  pay_to_recd_from varchar(140),
  letter_head varchar(140),
  select_print_heading varchar(140),
  mode_of_payment varchar(140),
  payment_order varchar(140),
  is_opening varchar(140),
  stock_entry varchar(140),
  auto_repeat varchar(140),
  amended_from varchar(140),
  from_template varchar(140),
  tax_withholding_category varchar(140),
  apply_tds smallint,
  reversal_of varchar(140),
  process_deferred_accounting varchar(140),
  is_system_generated smallint,
  periodic_entry_difference_account varchar(140),
  for_all_stock_asset_accounts smallint,
  stock_asset_account varchar(140),
  party_not_required smallint,
  tax_withholding_group varchar(140),
  ignore_tax_withholding_threshold smallint,
  override_tax_withholding_entries smallint,
  custom_remark smallint
);
CREATE INDEX ix_journal_entry_voucher_type ON "tabJournal Entry" (voucher_type);
CREATE INDEX ix_journal_entry_posting_date ON "tabJournal Entry" (posting_date);
CREATE INDEX ix_journal_entry_company ON "tabJournal Entry" (company);
CREATE INDEX ix_journal_entry_cheque_no ON "tabJournal Entry" (cheque_no);
CREATE INDEX ix_journal_entry_cheque_date ON "tabJournal Entry" (cheque_date);
CREATE INDEX ix_journal_entry_clearance_date ON "tabJournal Entry" (clearance_date);
CREATE INDEX ix_journal_entry_is_opening ON "tabJournal Entry" (is_opening);

-- Journal Entry Account (child)
CREATE TABLE "tabJournal Entry Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  account_type varchar(140),
  cost_center varchar(140),
  party_type varchar(140),
  party varchar(140),
  account_currency varchar(140),
  exchange_rate numeric(21,9),
  debit_in_account_currency numeric(21,9),
  debit numeric(21,9),
  credit_in_account_currency numeric(21,9),
  credit numeric(21,9),
  reference_type varchar(140),
  reference_name varchar(140),
  reference_due_date date,
  project varchar(140),
  is_advance varchar(140),
  user_remark text,
  against_account text,
  bank_account varchar(140),
  reference_detail_no varchar(140),
  advance_voucher_type varchar(140),
  advance_voucher_no varchar(140),
  is_tax_withholding_account smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_journal_entry_account_account ON "tabJournal Entry Account" (account);
CREATE INDEX ix_journal_entry_account_party_type ON "tabJournal Entry Account" (party_type);
CREATE INDEX ix_journal_entry_account_reference_type ON "tabJournal Entry Account" (reference_type);
CREATE INDEX ix_journal_entry_account_reference_name ON "tabJournal Entry Account" (reference_name);
CREATE INDEX ix_journal_entry_account_advance_voucher_type ON "tabJournal Entry Account" (advance_voucher_type);
CREATE INDEX ix_journal_entry_account_advance_voucher_no ON "tabJournal Entry Account" (advance_voucher_no);
CREATE INDEX ix_journal_entry_account_parent ON "tabJournal Entry Account" (parent);

-- Journal Entry Template (master)
CREATE TABLE "tabJournal Entry Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  voucher_type varchar(140),
  company varchar(140),
  is_opening varchar(140),
  naming_series varchar(140),
  template_title varchar(140),
  multi_currency smallint
);

-- Journal Entry Template Account (child)
CREATE TABLE "tabJournal Entry Template Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  cost_center varchar(140),
  project varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_journal_entry_template_account_parent ON "tabJournal Entry Template Account" (parent);

-- Ledger Health (master)
CREATE TABLE "tabLedger Health" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  voucher_type varchar(140),
  voucher_no varchar(140),
  debit_credit_mismatch smallint,
  checked_on timestamp,
  general_and_payment_ledger_mismatch smallint
);

-- Ledger Health Monitor Company (child)
CREATE TABLE "tabLedger Health Monitor Company" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_ledger_health_monitor_company_parent ON "tabLedger Health Monitor Company" (parent);

-- Ledger Merge (master)
CREATE TABLE "tabLedger Merge" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  company varchar(140),
  status varchar(140),
  root_type varchar(140),
  account_name varchar(140),
  is_group smallint
);

-- Ledger Merge Accounts (child)
CREATE TABLE "tabLedger Merge Accounts" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  merged smallint,
  account_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_ledger_merge_accounts_parent ON "tabLedger Merge Accounts" (parent);

-- Loyalty Point Entry (master)
CREATE TABLE "tabLoyalty Point Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  loyalty_program varchar(140),
  loyalty_program_tier varchar(140),
  customer varchar(140),
  redeem_against varchar(140),
  loyalty_points integer,
  purchase_amount numeric(21,9),
  expiry_date date,
  posting_date date,
  company varchar(140),
  invoice_type varchar(140),
  invoice varchar(140),
  discretionary_reason varchar(140)
);

-- Loyalty Point Entry Redemption (child)
CREATE TABLE "tabLoyalty Point Entry Redemption" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  sales_invoice varchar(140),
  redemption_date date,
  redeemed_points integer,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_loyalty_point_entry_redemption_parent ON "tabLoyalty Point Entry Redemption" (parent);

-- Loyalty Program (master)
CREATE TABLE "tabLoyalty Program" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  loyalty_program_name varchar(140),
  loyalty_program_type varchar(140),
  from_date date,
  to_date date,
  customer_group varchar(140),
  customer_territory varchar(140),
  auto_opt_in smallint,
  conversion_factor numeric(21,9),
  expiry_duration integer,
  expense_account varchar(140),
  cost_center varchar(140),
  company varchar(140),
  project varchar(140)
);

-- Loyalty Program Collection (child)
CREATE TABLE "tabLoyalty Program Collection" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  tier_name varchar(140),
  min_spent numeric(21,9),
  collection_factor numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_loyalty_program_collection_parent ON "tabLoyalty Program Collection" (parent);

-- Mode of Payment (master)
CREATE TABLE "tabMode of Payment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  mode_of_payment varchar(140),
  type varchar(140),
  enabled smallint
);

-- Mode of Payment Account (child)
CREATE TABLE "tabMode of Payment Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  default_account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_mode_of_payment_account_parent ON "tabMode of Payment Account" (parent);

-- Monthly Distribution (master)
CREATE TABLE "tabMonthly Distribution" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  distribution_id varchar(140),
  fiscal_year varchar(140)
);
CREATE INDEX ix_monthly_distribution_fiscal_year ON "tabMonthly Distribution" (fiscal_year);

-- Monthly Distribution Percentage (child)
CREATE TABLE "tabMonthly Distribution Percentage" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  month varchar(140),
  percentage_allocation numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_monthly_distribution_percentage_parent ON "tabMonthly Distribution Percentage" (parent);

-- Opening Invoice Creation Tool Item (child)
CREATE TABLE "tabOpening Invoice Creation Tool Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  party_type varchar(140),
  party varchar(140),
  temporary_opening_account varchar(140),
  posting_date date,
  due_date date,
  item_name varchar(140),
  outstanding_amount numeric(21,9),
  qty varchar(140),
  cost_center varchar(140),
  invoice_number varchar(140),
  supplier_invoice_date date,
  party_name varchar(140),
  project varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_opening_invoice_creation_tool_item_parent ON "tabOpening Invoice Creation Tool Item" (parent);

-- Overdue Payment (child)
CREATE TABLE "tabOverdue Payment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_term varchar(140),
  description text,
  due_date date,
  mode_of_payment varchar(140),
  invoice_portion numeric(21,9),
  payment_amount numeric(21,9),
  outstanding numeric(21,9),
  paid_amount numeric(21,9),
  discounted_amount numeric(21,9),
  sales_invoice varchar(140),
  payment_schedule varchar(140),
  overdue_days varchar(140),
  dunning_level integer,
  interest numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_overdue_payment_parent ON "tabOverdue Payment" (parent);

-- POS Closing Entry (transaction)
CREATE TABLE "tabPOS Closing Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  period_start_date timestamp,
  period_end_date timestamp,
  posting_date date,
  company varchar(140),
  pos_profile varchar(140),
  "user" varchar(140),
  grand_total numeric(21,9),
  net_total numeric(21,9),
  total_quantity numeric(21,9),
  amended_from varchar(140),
  pos_opening_entry varchar(140),
  status varchar(140),
  error_message text,
  posting_time time(6),
  total_taxes_and_charges numeric(21,9)
);

-- POS Closing Entry Detail (child)
CREATE TABLE "tabPOS Closing Entry Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  mode_of_payment varchar(140),
  expected_amount numeric(21,9),
  difference numeric(21,9),
  opening_amount numeric(21,9),
  closing_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_closing_entry_detail_parent ON "tabPOS Closing Entry Detail" (parent);

-- POS Closing Entry Taxes (child)
CREATE TABLE "tabPOS Closing Entry Taxes" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  amount numeric(21,9),
  account_head varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_closing_entry_taxes_parent ON "tabPOS Closing Entry Taxes" (parent);

-- POS Customer Group (child)
CREATE TABLE "tabPOS Customer Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_customer_group_parent ON "tabPOS Customer Group" (parent);

-- POS Field (child)
CREATE TABLE "tabPOS Field" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  fieldname varchar(140),
  fieldtype varchar(140),
  label varchar(140),
  options text,
  reqd smallint,
  read_only smallint,
  default_value varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_field_parent ON "tabPOS Field" (parent);

-- POS Invoice (transaction)
CREATE TABLE "tabPOS Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  customer varchar(140),
  customer_name varchar(140),
  tax_id varchar(140),
  is_pos smallint,
  pos_profile varchar(140),
  is_return smallint,
  company varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  due_date date,
  amended_from varchar(140),
  return_against varchar(140),
  update_billed_amount_in_sales_order smallint,
  project varchar(140),
  cost_center varchar(140),
  po_no varchar(140),
  po_date date,
  customer_address varchar(140),
  address_display text,
  contact_person varchar(140),
  contact_display text,
  contact_mobile varchar(140),
  contact_email varchar(140),
  territory varchar(140),
  shipping_address_name varchar(140),
  shipping_address text,
  company_address varchar(140),
  company_address_display text,
  currency varchar(140),
  conversion_rate numeric(21,9),
  selling_price_list varchar(140),
  price_list_currency varchar(140),
  plc_conversion_rate numeric(21,9),
  ignore_pricing_rule smallint,
  set_warehouse varchar(140),
  update_stock smallint,
  scan_barcode varchar(140),
  total_billing_amount numeric(21,9),
  total_qty numeric(21,9),
  base_total numeric(21,9),
  base_net_total numeric(21,9),
  total numeric(21,9),
  net_total numeric(21,9),
  total_net_weight numeric(21,9),
  taxes_and_charges varchar(140),
  shipping_rule varchar(140),
  tax_category varchar(140),
  other_charges_calculation text,
  base_total_taxes_and_charges numeric(21,9),
  total_taxes_and_charges numeric(21,9),
  loyalty_points integer,
  loyalty_amount numeric(21,9),
  redeem_loyalty_points smallint,
  loyalty_program varchar(140),
  loyalty_redemption_account varchar(140),
  loyalty_redemption_cost_center varchar(140),
  apply_discount_on varchar(140),
  base_discount_amount numeric(21,9),
  additional_discount_percentage numeric(21,9),
  discount_amount numeric(21,9),
  base_grand_total numeric(21,9),
  base_rounding_adjustment numeric(21,9),
  base_rounded_total numeric(21,9),
  base_in_words varchar(140),
  grand_total numeric(21,9),
  rounding_adjustment numeric(21,9),
  rounded_total numeric(21,9),
  in_words varchar(140),
  total_advance numeric(21,9),
  outstanding_amount numeric(21,9),
  allocate_advances_automatically smallint,
  payment_terms_template varchar(140),
  cash_bank_account varchar(140),
  base_paid_amount numeric(21,9),
  paid_amount numeric(21,9),
  base_change_amount numeric(21,9),
  change_amount numeric(21,9),
  account_for_change_amount varchar(140),
  write_off_amount numeric(21,9),
  base_write_off_amount numeric(21,9),
  write_off_outstanding_amount_automatically smallint,
  write_off_account varchar(140),
  write_off_cost_center varchar(140),
  tc_name varchar(140),
  terms text,
  letter_head varchar(140),
  group_same_items smallint,
  language varchar(140),
  select_print_heading varchar(140),
  inter_company_invoice_reference varchar(140),
  customer_group varchar(140),
  is_discounted smallint,
  status varchar(140),
  debit_to varchar(140),
  party_account_currency varchar(140),
  is_opening varchar(140),
  remarks text,
  sales_partner varchar(140),
  commission_rate numeric(21,9),
  total_commission numeric(21,9),
  from_date date,
  to_date date,
  auto_repeat varchar(140),
  against_income_account text,
  consolidated_invoice varchar(140),
  coupon_code varchar(140),
  amount_eligible_for_commission numeric(21,9),
  update_billed_amount_in_delivery_note smallint,
  utm_medium varchar(140),
  utm_campaign varchar(140),
  utm_source varchar(140),
  company_contact_person varchar(140),
  title varchar(140)
);
CREATE INDEX ix_pos_invoice_customer ON "tabPOS Invoice" (customer);
CREATE INDEX ix_pos_invoice_posting_date ON "tabPOS Invoice" (posting_date);
CREATE INDEX ix_pos_invoice_return_against ON "tabPOS Invoice" (return_against);
CREATE INDEX ix_pos_invoice_debit_to ON "tabPOS Invoice" (debit_to);

-- POS Invoice Item (child)
CREATE TABLE "tabPOS Invoice Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  item_code varchar(140),
  is_product_bundle smallint,
  product_bundle varchar(140),
  item_name varchar(140),
  customer_item_code varchar(140),
  description text,
  item_group varchar(140),
  brand varchar(140),
  image text,
  qty numeric(21,9),
  stock_uom varchar(140),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_qty numeric(21,9),
  price_list_rate numeric(21,9),
  base_price_list_rate numeric(21,9),
  margin_type varchar(140),
  margin_rate_or_amount numeric(21,9),
  rate_with_margin numeric(21,9),
  discount_percentage numeric(21,2),
  discount_amount numeric(21,9),
  base_rate_with_margin numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  item_tax_template varchar(140),
  base_rate numeric(21,9),
  base_amount numeric(21,9),
  pricing_rules text,
  is_free_item smallint,
  net_rate numeric(21,9),
  net_amount numeric(21,9),
  base_net_rate numeric(21,9),
  base_net_amount numeric(21,9),
  delivered_by_supplier smallint,
  income_account varchar(140),
  is_fixed_asset smallint,
  asset varchar(140),
  finance_book varchar(140),
  expense_account varchar(140),
  deferred_revenue_account varchar(140),
  service_stop_date date,
  enable_deferred_revenue smallint,
  service_start_date date,
  service_end_date date,
  weight_per_unit numeric(21,9),
  total_weight numeric(21,9),
  weight_uom varchar(140),
  warehouse varchar(140),
  target_warehouse varchar(140),
  quality_inspection varchar(140),
  batch_no varchar(140),
  allow_zero_valuation_rate smallint,
  serial_no text,
  item_tax_rate text,
  actual_batch_qty numeric(21,9),
  actual_qty numeric(21,9),
  sales_order varchar(140),
  so_detail varchar(140),
  delivery_note varchar(140),
  dn_detail varchar(140),
  delivered_qty numeric(21,9),
  cost_center varchar(140),
  page_break smallint,
  project varchar(140),
  pos_invoice_item varchar(140),
  grant_commission smallint,
  has_item_scanned smallint,
  serial_and_batch_bundle varchar(140),
  use_serial_batch_fields smallint,
  distributed_discount_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_invoice_item_item_code ON "tabPOS Invoice Item" (item_code);
CREATE INDEX ix_pos_invoice_item_sales_order ON "tabPOS Invoice Item" (sales_order);
CREATE INDEX ix_pos_invoice_item_so_detail ON "tabPOS Invoice Item" (so_detail);
CREATE INDEX ix_pos_invoice_item_delivery_note ON "tabPOS Invoice Item" (delivery_note);
CREATE INDEX ix_pos_invoice_item_dn_detail ON "tabPOS Invoice Item" (dn_detail);
CREATE INDEX ix_pos_invoice_item_parent ON "tabPOS Invoice Item" (parent);

-- POS Invoice Merge Log (transaction)
CREATE TABLE "tabPOS Invoice Merge Log" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  customer varchar(140),
  amended_from varchar(140),
  consolidated_invoice varchar(140),
  consolidated_credit_note varchar(140),
  pos_closing_entry varchar(140),
  merge_invoices_based_on varchar(140),
  customer_group varchar(140),
  posting_time time(6),
  company varchar(140)
);

-- POS Invoice Reference (child)
CREATE TABLE "tabPOS Invoice Reference" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  pos_invoice varchar(140),
  customer varchar(140),
  posting_date date,
  grand_total numeric(21,9),
  is_return smallint,
  return_against varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_invoice_reference_parent ON "tabPOS Invoice Reference" (parent);

-- POS Item Group (child)
CREATE TABLE "tabPOS Item Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_item_group_parent ON "tabPOS Item Group" (parent);

-- POS Opening Entry (transaction)
CREATE TABLE "tabPOS Opening Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  period_start_date timestamp,
  period_end_date date,
  posting_date date,
  company varchar(140),
  pos_profile varchar(140),
  "user" varchar(140),
  amended_from varchar(140),
  set_posting_date smallint,
  status varchar(140),
  pos_closing_entry varchar(140)
);

-- POS Opening Entry Detail (child)
CREATE TABLE "tabPOS Opening Entry Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  mode_of_payment varchar(140),
  opening_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_opening_entry_detail_parent ON "tabPOS Opening Entry Detail" (parent);

-- POS Payment Method (child)
CREATE TABLE "tabPOS Payment Method" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  "default" smallint,
  mode_of_payment varchar(140),
  allow_in_returns smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_payment_method_parent ON "tabPOS Payment Method" (parent);

-- POS Profile (master)
CREATE TABLE "tabPOS Profile" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  disabled smallint,
  customer varchar(140),
  company varchar(140),
  country varchar(140),
  company_address varchar(140),
  letter_head varchar(140),
  tc_name varchar(140),
  select_print_heading varchar(140),
  selling_price_list varchar(140),
  currency varchar(140),
  write_off_account varchar(140),
  write_off_cost_center varchar(140),
  account_for_change_amount varchar(140),
  income_account varchar(140),
  expense_account varchar(140),
  cost_center varchar(140),
  taxes_and_charges varchar(140),
  apply_discount_on varchar(140),
  tax_category varchar(140),
  print_format varchar(140),
  warehouse varchar(140),
  ignore_pricing_rule smallint,
  update_stock smallint,
  hide_unavailable_items smallint,
  hide_images smallint,
  auto_add_item_to_cart smallint,
  allow_rate_change smallint,
  allow_discount_change smallint,
  validate_stock_on_save smallint,
  write_off_limit numeric(21,9),
  disable_rounded_total smallint,
  utm_campaign varchar(140),
  utm_source varchar(140),
  utm_medium varchar(140),
  print_receipt_on_order_complete smallint,
  project varchar(140),
  set_grand_total_to_default_mop smallint,
  action_on_new_invoice varchar(140),
  allow_partial_payment smallint,
  allow_warehouse_change smallint
);

-- POS Profile User (child)
CREATE TABLE "tabPOS Profile User" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  "default" smallint,
  "user" varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_profile_user_parent ON "tabPOS Profile User" (parent);

-- POS Search Fields (child)
CREATE TABLE "tabPOS Search Fields" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  fieldname varchar(140),
  field varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pos_search_fields_parent ON "tabPOS Search Fields" (parent);

-- PSOA Cost Center (child)
CREATE TABLE "tabPSOA Cost Center" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  cost_center_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_psoa_cost_center_parent ON "tabPSOA Cost Center" (parent);

-- PSOA Project (child)
CREATE TABLE "tabPSOA Project" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  project_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_psoa_project_parent ON "tabPSOA Project" (parent);

-- Party Account (child)
CREATE TABLE "tabParty Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  account varchar(140),
  advance_account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_party_account_parent ON "tabParty Account" (parent);

-- Party Link (master)
CREATE TABLE "tabParty Link" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  primary_role varchar(140),
  secondary_role varchar(140),
  primary_party varchar(140),
  secondary_party varchar(140)
);

-- Payment Entry (transaction)
CREATE TABLE "tabPayment Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  payment_type varchar(140),
  posting_date date,
  company varchar(140),
  cost_center varchar(140),
  mode_of_payment varchar(140),
  party_type varchar(140),
  party varchar(140),
  party_name varchar(140),
  contact_person varchar(140),
  contact_email varchar(140),
  paid_from varchar(140),
  paid_from_account_currency varchar(140),
  paid_to varchar(140),
  paid_to_account_currency varchar(140),
  paid_amount numeric(21,9),
  source_exchange_rate numeric(21,9),
  base_paid_amount numeric(21,9),
  received_amount numeric(21,9),
  target_exchange_rate numeric(21,9),
  base_received_amount numeric(21,9),
  total_allocated_amount numeric(21,9),
  base_total_allocated_amount numeric(21,9),
  unallocated_amount numeric(21,9),
  difference_amount numeric(21,9),
  reference_no varchar(140),
  reference_date date,
  clearance_date date,
  project varchar(140),
  remarks text,
  letter_head varchar(140),
  print_heading varchar(140),
  bank varchar(140),
  bank_account_no varchar(140),
  payment_order varchar(140),
  auto_repeat varchar(140),
  amended_from varchar(140),
  title varchar(140),
  bank_account varchar(140),
  party_bank_account varchar(140),
  payment_order_status varchar(140),
  status varchar(140),
  custom_remarks smallint,
  tax_withholding_category varchar(140),
  purchase_taxes_and_charges_template varchar(140),
  sales_taxes_and_charges_template varchar(140),
  base_total_taxes_and_charges numeric(21,9),
  total_taxes_and_charges numeric(21,9),
  paid_amount_after_tax numeric(21,9),
  base_paid_amount_after_tax numeric(21,9),
  received_amount_after_tax numeric(21,9),
  base_received_amount_after_tax numeric(21,9),
  paid_from_account_type varchar(140),
  paid_to_account_type varchar(140),
  book_advance_payments_in_separate_party_account smallint,
  base_in_words text,
  in_words text,
  reconcile_on_advance_payment_date smallint,
  is_opening varchar(140),
  apply_tds smallint,
  tax_withholding_group varchar(140),
  ignore_tax_withholding_threshold smallint,
  override_tax_withholding_entries smallint
);
CREATE INDEX ix_payment_entry_party_type ON "tabPayment Entry" (party_type);
CREATE INDEX ix_payment_entry_reference_date ON "tabPayment Entry" (reference_date);
CREATE INDEX ix_payment_entry_is_opening ON "tabPayment Entry" (is_opening);

-- Payment Entry Deduction (child)
CREATE TABLE "tabPayment Entry Deduction" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  cost_center varchar(140),
  amount numeric(21,9),
  description text,
  is_exchange_gain_loss smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_entry_deduction_parent ON "tabPayment Entry Deduction" (parent);

-- Payment Entry Reference (child)
CREATE TABLE "tabPayment Entry Reference" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_doctype varchar(140),
  reference_name varchar(140),
  due_date date,
  bill_no varchar(140),
  total_amount numeric(21,9),
  outstanding_amount numeric(21,9),
  allocated_amount numeric(21,9),
  exchange_rate numeric(21,9),
  payment_term varchar(140),
  exchange_gain_loss numeric(21,9),
  account varchar(140),
  account_type varchar(140),
  payment_type varchar(140),
  payment_request varchar(140),
  payment_term_outstanding numeric(21,9),
  reconcile_effect_on date,
  advance_voucher_type varchar(140),
  advance_voucher_no varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_entry_reference_reference_doctype ON "tabPayment Entry Reference" (reference_doctype);
CREATE INDEX ix_payment_entry_reference_reference_name ON "tabPayment Entry Reference" (reference_name);
CREATE INDEX ix_payment_entry_reference_parent ON "tabPayment Entry Reference" (parent);

-- Payment Gateway Account (master)
CREATE TABLE "tabPayment Gateway Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_gateway varchar(140),
  is_default smallint,
  payment_account varchar(140),
  currency varchar(140),
  message text,
  payment_channel varchar(140),
  company varchar(140)
);

-- Payment Ledger Entry (transaction)
CREATE TABLE "tabPayment Ledger Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  account_type varchar(140),
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  voucher_type varchar(140),
  voucher_no varchar(140),
  against_voucher_type varchar(140),
  against_voucher_no varchar(140),
  amount numeric(21,9),
  account_currency varchar(140),
  amount_in_account_currency numeric(21,9),
  delinked smallint,
  company varchar(140),
  cost_center varchar(140),
  project varchar(140),
  due_date date,
  finance_book varchar(140),
  remarks text,
  voucher_detail_no varchar(140)
);
CREATE INDEX ix_payment_ledger_entry_posting_date ON "tabPayment Ledger Entry" (posting_date);
CREATE INDEX ix_payment_ledger_entry_account ON "tabPayment Ledger Entry" (account);
CREATE INDEX ix_payment_ledger_entry_party_type ON "tabPayment Ledger Entry" (party_type);
CREATE INDEX ix_payment_ledger_entry_party ON "tabPayment Ledger Entry" (party);
CREATE INDEX ix_payment_ledger_entry_voucher_type ON "tabPayment Ledger Entry" (voucher_type);
CREATE INDEX ix_payment_ledger_entry_voucher_no ON "tabPayment Ledger Entry" (voucher_no);
CREATE INDEX ix_payment_ledger_entry_against_voucher_type ON "tabPayment Ledger Entry" (against_voucher_type);
CREATE INDEX ix_payment_ledger_entry_against_voucher_no ON "tabPayment Ledger Entry" (against_voucher_no);
CREATE INDEX ix_payment_ledger_entry_company ON "tabPayment Ledger Entry" (company);
CREATE INDEX ix_payment_ledger_entry_voucher_detail_no ON "tabPayment Ledger Entry" (voucher_detail_no);

-- Payment Order (transaction)
CREATE TABLE "tabPayment Order" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  company varchar(140),
  party varchar(140),
  posting_date date,
  amended_from varchar(140),
  payment_order_type varchar(140),
  company_bank_account varchar(140),
  company_bank varchar(140),
  account varchar(140)
);

-- Payment Order Reference (child)
CREATE TABLE "tabPayment Order Reference" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_doctype varchar(140),
  reference_name varchar(140),
  amount numeric(21,9),
  supplier varchar(140),
  payment_request varchar(140),
  mode_of_payment varchar(140),
  bank_account varchar(140),
  account varchar(140),
  payment_reference varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_order_reference_parent ON "tabPayment Order Reference" (parent);

-- Payment Reconciliation Allocation (child)
CREATE TABLE "tabPayment Reconciliation Allocation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  invoice_number varchar(140),
  allocated_amount numeric(21,9),
  difference_account varchar(140),
  difference_amount numeric(21,9),
  reference_name varchar(140),
  is_advance varchar(140),
  reference_type varchar(140),
  invoice_type varchar(140),
  unreconciled_amount numeric(21,9),
  amount numeric(21,9),
  reference_row varchar(140),
  currency varchar(140),
  exchange_rate numeric(21,9),
  cost_center varchar(140),
  gain_loss_posting_date date,
  debit_or_credit_note_posting_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_reconciliation_allocation_parent ON "tabPayment Reconciliation Allocation" (parent);

-- Payment Reconciliation Invoice (child)
CREATE TABLE "tabPayment Reconciliation Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  invoice_type varchar(140),
  invoice_number varchar(140),
  invoice_date date,
  amount numeric(21,9),
  outstanding_amount numeric(21,9),
  currency varchar(140),
  exchange_rate numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_reconciliation_invoice_parent ON "tabPayment Reconciliation Invoice" (parent);

-- Payment Reconciliation Payment (child)
CREATE TABLE "tabPayment Reconciliation Payment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_type varchar(140),
  reference_name varchar(140),
  posting_date date,
  is_advance varchar(140),
  reference_row varchar(140),
  amount numeric(21,9),
  currency varchar(140),
  difference_amount numeric(21,9),
  exchange_rate numeric(21,9),
  cost_center varchar(140),
  remarks text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_reconciliation_payment_parent ON "tabPayment Reconciliation Payment" (parent);

-- Payment Reference (child)
CREATE TABLE "tabPayment Reference" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_term varchar(140),
  description text,
  due_date date,
  amount numeric(21,2),
  currency varchar(140),
  payment_schedule varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_reference_parent ON "tabPayment Reference" (parent);

-- Payment Request (transaction)
CREATE TABLE "tabPayment Request" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_request_type varchar(140),
  transaction_date date,
  naming_series varchar(140),
  mode_of_payment varchar(140),
  party_type varchar(140),
  party varchar(140),
  reference_doctype varchar(140),
  reference_name varchar(140),
  grand_total numeric(21,9),
  is_a_subscription smallint,
  currency varchar(140),
  bank_account varchar(140),
  bank varchar(140),
  bank_account_no varchar(140),
  account varchar(140),
  iban varchar(140),
  branch_code varchar(140),
  swift_number varchar(140),
  cost_center varchar(140),
  project varchar(140),
  print_format varchar(140),
  email_to varchar(140),
  subject varchar(140),
  payment_gateway_account varchar(140),
  status varchar(140),
  make_sales_invoice smallint,
  message text,
  mute_email smallint,
  payment_url varchar(140),
  payment_gateway varchar(140),
  payment_account varchar(140),
  payment_channel varchar(140),
  payment_order varchar(140),
  amended_from varchar(140),
  failed_reason varchar(140),
  outstanding_amount numeric(21,9),
  company varchar(140),
  party_account_currency varchar(140),
  party_name varchar(140),
  phone_number varchar(140)
);
CREATE INDEX ix_payment_request_reference_name ON "tabPayment Request" (reference_name);

-- Payment Schedule (child)
CREATE TABLE "tabPayment Schedule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_term varchar(140),
  description text,
  due_date date,
  invoice_portion numeric(21,9),
  payment_amount numeric(21,9),
  mode_of_payment varchar(140),
  paid_amount numeric(21,9),
  discounted_amount numeric(21,9),
  outstanding numeric(21,9),
  discount_date date,
  discount_type varchar(140),
  discount numeric(21,9),
  base_payment_amount numeric(21,9),
  base_outstanding numeric(21,9),
  base_paid_amount numeric(21,9),
  due_date_based_on varchar(140),
  credit_days integer,
  credit_months integer,
  discount_validity_based_on varchar(140),
  discount_validity integer,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_schedule_parent ON "tabPayment Schedule" (parent);

-- Payment Term (master)
CREATE TABLE "tabPayment Term" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_term_name varchar(140),
  invoice_portion numeric(21,9),
  mode_of_payment varchar(140),
  due_date_based_on varchar(140),
  credit_days integer,
  credit_months integer,
  description text,
  discount_type varchar(140),
  discount numeric(21,9),
  discount_validity_based_on varchar(140),
  discount_validity integer
);

-- Payment Terms Template (master)
CREATE TABLE "tabPayment Terms Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  template_name varchar(140),
  allocate_payment_based_on_payment_terms smallint
);

-- Payment Terms Template Detail (child)
CREATE TABLE "tabPayment Terms Template Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  payment_term varchar(140),
  description text,
  invoice_portion numeric(21,9),
  due_date_based_on varchar(140),
  credit_days integer,
  credit_months integer,
  mode_of_payment varchar(140),
  discount_type varchar(140),
  discount numeric(21,9),
  discount_validity_based_on varchar(140),
  discount_validity integer,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_payment_terms_template_detail_parent ON "tabPayment Terms Template Detail" (parent);

-- Pegged Currency Details (child)
CREATE TABLE "tabPegged Currency Details" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  source_currency varchar(140),
  pegged_exchange_rate varchar(140),
  pegged_against varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pegged_currency_details_parent ON "tabPegged Currency Details" (parent);

-- Period Closing Voucher (transaction)
CREATE TABLE "tabPeriod Closing Voucher" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  transaction_date date,
  fiscal_year varchar(140),
  amended_from varchar(140),
  company varchar(140),
  closing_account_head varchar(140),
  remarks text,
  gle_processing_status varchar(140),
  error_message text,
  period_end_date date,
  period_start_date date
);

-- Pricing Rule (master)
CREATE TABLE "tabPricing Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  disable smallint,
  apply_on varchar(140),
  price_or_product_discount varchar(140),
  warehouse varchar(140),
  mixed_conditions smallint,
  is_cumulative smallint,
  coupon_code_based smallint,
  apply_rule_on_other varchar(140),
  other_item_code varchar(140),
  other_item_group varchar(140),
  other_brand varchar(140),
  selling smallint,
  buying smallint,
  applicable_for varchar(140),
  customer varchar(140),
  customer_group varchar(140),
  territory varchar(140),
  sales_partner varchar(140),
  campaign varchar(140),
  supplier varchar(140),
  supplier_group varchar(140),
  min_qty numeric(21,9),
  max_qty numeric(21,9),
  min_amt numeric(21,9),
  max_amt numeric(21,9),
  valid_from date,
  valid_upto date,
  company varchar(140),
  currency varchar(140),
  margin_type varchar(140),
  margin_rate_or_amount numeric(21,9),
  rate_or_discount varchar(140),
  apply_discount_on varchar(140),
  rate numeric(21,9),
  discount_amount numeric(21,9),
  discount_percentage numeric(21,9),
  for_price_list varchar(140),
  same_item smallint,
  free_item varchar(140),
  free_qty numeric(21,9),
  free_item_uom varchar(140),
  free_item_rate numeric(21,9),
  threshold_percentage numeric(21,9),
  priority varchar(140),
  apply_multiple_pricing_rules smallint,
  apply_discount_on_rate smallint,
  validate_applied_rule smallint,
  rule_description text,
  promotional_scheme_id varchar(140),
  promotional_scheme varchar(140),
  condition text,
  is_recursive smallint,
  naming_series varchar(140),
  round_free_qty smallint,
  recurse_for numeric(21,9),
  apply_recursion_over numeric(21,9),
  has_priority smallint,
  dont_enforce_free_item_qty smallint
);
CREATE INDEX ix_pricing_rule_warehouse ON "tabPricing Rule" (warehouse);

-- Pricing Rule Brand (child)
CREATE TABLE "tabPricing Rule Brand" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  brand varchar(140),
  uom varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pricing_rule_brand_brand ON "tabPricing Rule Brand" (brand);
CREATE INDEX ix_pricing_rule_brand_parent ON "tabPricing Rule Brand" (parent);

-- Pricing Rule Detail (child)
CREATE TABLE "tabPricing Rule Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  pricing_rule varchar(140),
  item_code varchar(140),
  margin_type varchar(140),
  rate_or_discount varchar(140),
  child_docname varchar(140),
  rule_applied smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pricing_rule_detail_parent ON "tabPricing Rule Detail" (parent);

-- Pricing Rule Item Code (child)
CREATE TABLE "tabPricing Rule Item Code" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  uom varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pricing_rule_item_code_item_code ON "tabPricing Rule Item Code" (item_code);
CREATE INDEX ix_pricing_rule_item_code_parent ON "tabPricing Rule Item Code" (parent);

-- Pricing Rule Item Group (child)
CREATE TABLE "tabPricing Rule Item Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_group varchar(140),
  uom varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pricing_rule_item_group_item_group ON "tabPricing Rule Item Group" (item_group);
CREATE INDEX ix_pricing_rule_item_group_parent ON "tabPricing Rule Item Group" (parent);

-- Process Deferred Accounting (transaction)
CREATE TABLE "tabProcess Deferred Accounting" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  type varchar(140),
  amended_from varchar(140),
  start_date date,
  end_date date,
  posting_date date,
  account varchar(140),
  company varchar(140)
);

-- Process Payment Reconciliation (transaction)
CREATE TABLE "tabProcess Payment Reconciliation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  status varchar(140),
  company varchar(140),
  party_type varchar(140),
  party varchar(140),
  receivable_payable_account varchar(140),
  from_invoice_date date,
  to_invoice_date date,
  from_payment_date date,
  to_payment_date date,
  cost_center varchar(140),
  bank_cash_account varchar(140),
  error_log text,
  amended_from varchar(140),
  default_advance_account varchar(140)
);

-- Process Payment Reconciliation Log (master)
CREATE TABLE "tabProcess Payment Reconciliation Log" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reconciled smallint,
  total_allocations integer,
  allocated smallint,
  reconciled_entries integer,
  error_log text,
  process_pr varchar(140),
  status varchar(140)
);

-- Process Payment Reconciliation Log Allocations (child)
CREATE TABLE "tabProcess Payment Reconciliation Log Allocations" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_type varchar(140),
  reference_name varchar(140),
  reference_row varchar(140),
  invoice_type varchar(140),
  invoice_number varchar(140),
  allocated_amount numeric(21,9),
  unreconciled_amount numeric(21,9),
  amount numeric(21,9),
  is_advance varchar(140),
  difference_amount numeric(21,9),
  difference_account varchar(140),
  exchange_rate numeric(21,9),
  currency varchar(140),
  reconciled smallint,
  gain_loss_posting_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_process_payment_reconciliation_log_allocations_parent ON "tabProcess Payment Reconciliation Log Allocations" (parent);

-- Process Period Closing Voucher (transaction)
CREATE TABLE "tabProcess Period Closing Voucher" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  parent_pcv varchar(140),
  status varchar(140),
  amended_from varchar(140),
  p_l_closing_balance jsonb,
  bs_closing_balance jsonb
);
CREATE INDEX ix_process_period_closing_voucher_amended_from ON "tabProcess Period Closing Voucher" (amended_from);

-- Process Period Closing Voucher Detail (child)
CREATE TABLE "tabProcess Period Closing Voucher Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  processing_date date,
  status varchar(140),
  closing_balance jsonb,
  report_type varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_process_period_closing_voucher_detail_parent ON "tabProcess Period Closing Voucher Detail" (parent);

-- Process Statement Of Accounts (master)
CREATE TABLE "tabProcess Statement Of Accounts" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  frequency varchar(140),
  company varchar(140),
  from_date date,
  to_date date,
  customer_collection varchar(140),
  collection_name varchar(140),
  account varchar(140),
  finance_book varchar(140),
  orientation varchar(140),
  start_date date,
  currency varchar(140),
  include_ageing smallint,
  ageing_based_on varchar(140),
  enable_auto_email smallint,
  primary_mandatory smallint,
  filter_duration integer,
  subject varchar(140),
  body text,
  letter_head varchar(140),
  terms_and_conditions varchar(140),
  include_break smallint,
  show_net_values_in_party_account smallint,
  sender varchar(140),
  report varchar(140),
  posting_date date,
  payment_terms_template varchar(140),
  sales_partner varchar(140),
  sales_person varchar(140),
  territory varchar(140),
  based_on_payment_terms smallint,
  pdf_name varchar(140),
  ignore_exchange_rate_revaluation_journals smallint,
  ignore_cr_dr_notes smallint,
  show_remarks smallint,
  categorize_by varchar(140),
  show_future_payments smallint,
  print_format varchar(140),
  show_opening_entries smallint
);

-- Process Statement Of Accounts CC (child)
CREATE TABLE "tabProcess Statement Of Accounts CC" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  cc varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_process_statement_of_accounts_cc_parent ON "tabProcess Statement Of Accounts CC" (parent);

-- Process Statement Of Accounts Customer (child)
CREATE TABLE "tabProcess Statement Of Accounts Customer" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer varchar(140),
  primary_email varchar(140),
  billing_email varchar(140),
  customer_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_process_statement_of_accounts_customer_parent ON "tabProcess Statement Of Accounts Customer" (parent);

-- Process Subscription (transaction)
CREATE TABLE "tabProcess Subscription" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  amended_from varchar(140),
  posting_date date,
  subscription varchar(140)
);

-- Promotional Scheme (master)
CREATE TABLE "tabPromotional Scheme" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  apply_on varchar(140),
  disable smallint,
  mixed_conditions smallint,
  is_cumulative smallint,
  apply_rule_on_other varchar(140),
  other_item_code varchar(140),
  other_item_group varchar(140),
  other_brand varchar(140),
  selling smallint,
  buying smallint,
  applicable_for varchar(140),
  valid_from date,
  valid_upto date,
  company varchar(140),
  currency varchar(140)
);

-- Promotional Scheme Price Discount (child)
CREATE TABLE "tabPromotional Scheme Price Discount" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  disable smallint,
  rule_description text,
  min_qty numeric(21,9),
  max_qty numeric(21,9),
  min_amount numeric(21,9),
  max_amount numeric(21,9),
  rate_or_discount varchar(140),
  rate numeric(21,9),
  discount_amount numeric(21,9),
  discount_percentage numeric(21,9),
  for_price_list varchar(140),
  warehouse varchar(140),
  threshold_percentage numeric(21,9),
  validate_applied_rule smallint,
  priority varchar(140),
  apply_multiple_pricing_rules smallint,
  apply_discount_on_rate smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_promotional_scheme_price_discount_parent ON "tabPromotional Scheme Price Discount" (parent);

-- Promotional Scheme Product Discount (child)
CREATE TABLE "tabPromotional Scheme Product Discount" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  disable smallint,
  rule_description text,
  min_qty numeric(21,9),
  max_qty numeric(21,9),
  min_amount numeric(21,9),
  max_amount numeric(21,9),
  same_item smallint,
  free_item varchar(140),
  free_qty numeric(21,9),
  free_item_uom varchar(140),
  free_item_rate numeric(21,9),
  warehouse varchar(140),
  threshold_percentage numeric(21,9),
  priority varchar(140),
  apply_multiple_pricing_rules smallint,
  is_recursive smallint,
  recurse_for numeric(21,9),
  apply_recursion_over numeric(21,9),
  round_free_qty smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_promotional_scheme_product_discount_parent ON "tabPromotional Scheme Product Discount" (parent);

-- Purchase Invoice (transaction)
CREATE TABLE "tabPurchase Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  naming_series varchar(140),
  supplier varchar(140),
  supplier_name varchar(140),
  tax_id varchar(140),
  due_date date,
  is_paid smallint,
  is_return smallint,
  apply_tds smallint,
  company varchar(140),
  cost_center varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  amended_from varchar(140),
  on_hold smallint,
  release_date date,
  hold_comment text,
  bill_no varchar(140),
  bill_date date,
  return_against varchar(140),
  update_billed_amount_in_purchase_order smallint,
  update_billed_amount_in_purchase_receipt smallint,
  supplier_address varchar(140),
  address_display text,
  contact_person varchar(140),
  contact_display text,
  contact_mobile text,
  contact_email text,
  shipping_address varchar(140),
  shipping_address_display text,
  currency varchar(140),
  conversion_rate numeric(21,9),
  buying_price_list varchar(140),
  price_list_currency varchar(140),
  plc_conversion_rate numeric(21,9),
  ignore_pricing_rule smallint,
  set_warehouse varchar(140),
  rejected_warehouse varchar(140),
  is_subcontracted smallint,
  update_stock smallint,
  scan_barcode varchar(140),
  total_qty numeric(21,9),
  base_total numeric(21,9),
  base_net_total numeric(21,9),
  total numeric(21,9),
  net_total numeric(21,9),
  total_net_weight numeric(21,9),
  tax_category varchar(140),
  shipping_rule varchar(140),
  taxes_and_charges varchar(140),
  other_charges_calculation text,
  base_taxes_and_charges_added numeric(21,9),
  base_taxes_and_charges_deducted numeric(21,9),
  base_total_taxes_and_charges numeric(21,9),
  taxes_and_charges_added numeric(21,9),
  taxes_and_charges_deducted numeric(21,9),
  total_taxes_and_charges numeric(21,9),
  apply_discount_on varchar(140),
  base_discount_amount numeric(21,9),
  additional_discount_percentage numeric(21,9),
  discount_amount numeric(21,9),
  base_grand_total numeric(21,9),
  base_rounding_adjustment numeric(21,9),
  base_rounded_total numeric(21,9),
  base_in_words varchar(140),
  grand_total numeric(21,9),
  rounding_adjustment numeric(21,9),
  rounded_total numeric(21,9),
  in_words varchar(140),
  total_advance numeric(21,9),
  outstanding_amount numeric(21,9),
  disable_rounded_total smallint,
  mode_of_payment varchar(140),
  cash_bank_account varchar(140),
  clearance_date date,
  paid_amount numeric(21,9),
  base_paid_amount numeric(21,9),
  write_off_amount numeric(21,9),
  base_write_off_amount numeric(21,9),
  write_off_account varchar(140),
  write_off_cost_center varchar(140),
  allocate_advances_automatically smallint,
  payment_terms_template varchar(140),
  tc_name varchar(140),
  terms text,
  letter_head varchar(140),
  group_same_items smallint,
  select_print_heading varchar(140),
  language varchar(140),
  is_internal_supplier smallint,
  credit_to varchar(140),
  party_account_currency varchar(140),
  is_opening varchar(140),
  against_expense_account text,
  status varchar(140),
  inter_company_invoice_reference varchar(140),
  remarks text,
  from_date date,
  to_date date,
  auto_repeat varchar(140),
  billing_address varchar(140),
  billing_address_display text,
  project varchar(140),
  unrealized_profit_loss_account varchar(140),
  represents_company varchar(140),
  set_from_warehouse varchar(140),
  supplier_warehouse varchar(140),
  per_received numeric(21,9),
  ignore_default_payment_terms_template smallint,
  subscription varchar(140),
  incoterm varchar(140),
  named_place varchar(140),
  only_include_allocated_payments smallint,
  use_company_roundoff_cost_center smallint,
  use_transaction_date_exchange_rate smallint,
  supplier_group varchar(140),
  update_outstanding_for_self smallint,
  sender varchar(140),
  dispatch_address_display text,
  dispatch_address varchar(140),
  claimed_landed_cost_amount numeric(21,9),
  tax_withholding_group varchar(140),
  ignore_tax_withholding_threshold smallint,
  override_tax_withholding_entries smallint
);
CREATE INDEX ix_purchase_invoice_supplier ON "tabPurchase Invoice" (supplier);
CREATE INDEX ix_purchase_invoice_posting_date ON "tabPurchase Invoice" (posting_date);
CREATE INDEX ix_purchase_invoice_release_date ON "tabPurchase Invoice" (release_date);
CREATE INDEX ix_purchase_invoice_bill_no ON "tabPurchase Invoice" (bill_no);
CREATE INDEX ix_purchase_invoice_return_against ON "tabPurchase Invoice" (return_against);
CREATE INDEX ix_purchase_invoice_credit_to ON "tabPurchase Invoice" (credit_to);

-- Purchase Invoice Advance (child)
CREATE TABLE "tabPurchase Invoice Advance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_type varchar(140),
  reference_name varchar(140),
  remarks text,
  reference_row varchar(140),
  advance_amount numeric(21,9),
  allocated_amount numeric(21,9),
  exchange_gain_loss numeric(21,9),
  ref_exchange_rate numeric(21,9),
  difference_posting_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_purchase_invoice_advance_parent ON "tabPurchase Invoice Advance" (parent);

-- Purchase Invoice Item (child)
CREATE TABLE "tabPurchase Invoice Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  description text,
  image text,
  received_qty numeric(21,9),
  qty numeric(21,9),
  rejected_qty numeric(21,9),
  stock_uom varchar(140),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_qty numeric(21,9),
  price_list_rate numeric(21,9),
  discount_percentage numeric(21,9),
  discount_amount numeric(21,9),
  base_price_list_rate numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  base_rate numeric(21,9),
  base_amount numeric(21,9),
  pricing_rules text,
  is_free_item smallint,
  net_rate numeric(21,9),
  net_amount numeric(21,9),
  base_net_rate numeric(21,9),
  base_net_amount numeric(21,9),
  weight_per_unit numeric(21,9),
  total_weight numeric(21,9),
  weight_uom varchar(140),
  warehouse varchar(140),
  rejected_warehouse varchar(140),
  quality_inspection varchar(140),
  batch_no varchar(140),
  serial_no text,
  rejected_serial_no text,
  expense_account varchar(140),
  item_tax_template varchar(140),
  project varchar(140),
  cost_center varchar(140),
  deferred_expense_account varchar(140),
  service_stop_date date,
  enable_deferred_expense smallint,
  service_start_date date,
  service_end_date date,
  allow_zero_valuation_rate smallint,
  brand varchar(140),
  item_group varchar(140),
  item_tax_rate text,
  item_tax_amount numeric(21,9),
  purchase_order varchar(140),
  include_exploded_items smallint,
  is_fixed_asset smallint,
  asset_location varchar(140),
  po_detail varchar(140),
  purchase_receipt varchar(140),
  page_break smallint,
  pr_detail varchar(140),
  valuation_rate numeric(21,9),
  rm_supp_cost numeric(21,9),
  landed_cost_voucher_amount numeric(21,9),
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  asset_category varchar(140),
  from_warehouse varchar(140),
  purchase_invoice_item varchar(140),
  stock_uom_rate numeric(21,9),
  sales_invoice_item varchar(140),
  margin_type varchar(140),
  margin_rate_or_amount numeric(21,9),
  rate_with_margin numeric(21,9),
  base_rate_with_margin numeric(21,9),
  product_bundle varchar(140),
  apply_tds smallint,
  serial_and_batch_bundle varchar(140),
  rejected_serial_and_batch_bundle varchar(140),
  wip_composite_asset varchar(140),
  use_serial_batch_fields smallint,
  material_request varchar(140),
  material_request_item varchar(140),
  sales_incoming_rate numeric(21,9),
  distributed_discount_amount numeric(21,9),
  tax_withholding_category varchar(140),
  delivered_by_supplier smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_purchase_invoice_item_item_code ON "tabPurchase Invoice Item" (item_code);
CREATE INDEX ix_purchase_invoice_item_batch_no ON "tabPurchase Invoice Item" (batch_no);
CREATE INDEX ix_purchase_invoice_item_project ON "tabPurchase Invoice Item" (project);
CREATE INDEX ix_purchase_invoice_item_purchase_order ON "tabPurchase Invoice Item" (purchase_order);
CREATE INDEX ix_purchase_invoice_item_po_detail ON "tabPurchase Invoice Item" (po_detail);
CREATE INDEX ix_purchase_invoice_item_purchase_receipt ON "tabPurchase Invoice Item" (purchase_receipt);
CREATE INDEX ix_purchase_invoice_item_pr_detail ON "tabPurchase Invoice Item" (pr_detail);
CREATE INDEX ix_purchase_invoice_item_serial_and_batch_bundle ON "tabPurchase Invoice Item" (serial_and_batch_bundle);
CREATE INDEX ix_purchase_invoice_item_rejected_serial_and_batch_bundle ON "tabPurchase Invoice Item" (rejected_serial_and_batch_bundle);
CREATE INDEX ix_purchase_invoice_item_material_request ON "tabPurchase Invoice Item" (material_request);
CREATE INDEX ix_purchase_invoice_item_material_request_item ON "tabPurchase Invoice Item" (material_request_item);
CREATE INDEX ix_purchase_invoice_item_parent ON "tabPurchase Invoice Item" (parent);

-- Purchase Taxes and Charges (child)
CREATE TABLE "tabPurchase Taxes and Charges" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  category varchar(140),
  add_deduct_tax varchar(140),
  charge_type varchar(140),
  row_id varchar(140),
  allocate_full_amount_to_stock_items smallint,
  included_in_print_rate smallint,
  account_head varchar(140),
  cost_center varchar(140),
  description text,
  rate numeric(21,9),
  tax_amount numeric(21,9),
  tax_amount_after_discount_amount numeric(21,9),
  total numeric(21,9),
  base_tax_amount numeric(21,9),
  base_total numeric(21,9),
  base_tax_amount_after_discount_amount numeric(21,9),
  project varchar(140),
  included_in_paid_amount smallint,
  account_currency varchar(140),
  is_tax_withholding_account smallint,
  net_amount numeric(21,9),
  base_net_amount numeric(21,9),
  set_by_item_tax_template smallint,
  dont_recompute_tax smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_purchase_taxes_and_charges_parent ON "tabPurchase Taxes and Charges" (parent);

-- Purchase Taxes and Charges Template (master)
CREATE TABLE "tabPurchase Taxes and Charges Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  is_default smallint,
  disabled smallint,
  company varchar(140),
  tax_category varchar(140)
);

-- Repost Accounting Ledger (transaction)
CREATE TABLE "tabRepost Accounting Ledger" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  amended_from varchar(140),
  delete_cancelled_entries smallint,
  error_log text,
  status varchar(140),
  scheduled_job varchar(140)
);

-- Repost Accounting Ledger Items (child)
CREATE TABLE "tabRepost Accounting Ledger Items" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  voucher_type varchar(140),
  voucher_no varchar(140),
  status varchar(140),
  traceback text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_repost_accounting_ledger_items_parent ON "tabRepost Accounting Ledger Items" (parent);

-- Repost Allowed Types (child)
CREATE TABLE "tabRepost Allowed Types" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  document_type varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_repost_allowed_types_parent ON "tabRepost Allowed Types" (parent);

-- Repost Payment Ledger (transaction)
CREATE TABLE "tabRepost Payment Ledger" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  posting_date date,
  voucher_type varchar(140),
  amended_from varchar(140),
  company varchar(140),
  repost_status varchar(140),
  add_manually smallint,
  repost_error_log text
);

-- Repost Payment Ledger Items (child)
CREATE TABLE "tabRepost Payment Ledger Items" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  voucher_type varchar(140),
  voucher_no varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_repost_payment_ledger_items_parent ON "tabRepost Payment Ledger Items" (parent);

-- Sales Invoice (transaction)
CREATE TABLE "tabSales Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  customer varchar(140),
  customer_name text,
  tax_id varchar(140),
  project varchar(140),
  is_pos smallint,
  pos_profile varchar(140),
  is_return smallint,
  company varchar(140),
  cost_center varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  due_date date,
  amended_from varchar(140),
  return_against varchar(140),
  update_billed_amount_in_sales_order smallint,
  po_no varchar(140),
  po_date date,
  customer_address varchar(140),
  address_display text,
  contact_person varchar(140),
  contact_display text,
  contact_mobile text,
  contact_email varchar(140),
  territory varchar(140),
  shipping_address_name varchar(140),
  shipping_address text,
  company_address varchar(140),
  company_address_display text,
  currency varchar(140),
  conversion_rate numeric(21,9),
  selling_price_list varchar(140),
  price_list_currency varchar(140),
  plc_conversion_rate numeric(21,9),
  ignore_pricing_rule smallint,
  set_warehouse varchar(140),
  update_stock smallint,
  scan_barcode varchar(140),
  total_billing_amount numeric(21,9),
  total_qty numeric(21,9),
  base_total numeric(21,9),
  base_net_total numeric(21,9),
  total numeric(21,9),
  net_total numeric(21,9),
  total_net_weight numeric(21,9),
  taxes_and_charges varchar(140),
  shipping_rule varchar(140),
  tax_category varchar(140),
  other_charges_calculation text,
  base_total_taxes_and_charges numeric(21,9),
  total_taxes_and_charges numeric(21,9),
  loyalty_points integer,
  loyalty_amount numeric(21,9),
  redeem_loyalty_points smallint,
  loyalty_program varchar(140),
  loyalty_redemption_account varchar(140),
  loyalty_redemption_cost_center varchar(140),
  apply_discount_on varchar(140),
  base_discount_amount numeric(21,9),
  additional_discount_percentage numeric(21,9),
  discount_amount numeric(21,9),
  base_grand_total numeric(21,9),
  base_rounding_adjustment numeric(21,9),
  base_rounded_total numeric(21,9),
  base_in_words text,
  grand_total numeric(21,9),
  rounding_adjustment numeric(21,9),
  rounded_total numeric(21,9),
  in_words text,
  total_advance numeric(21,9),
  outstanding_amount numeric(21,9),
  allocate_advances_automatically smallint,
  payment_terms_template varchar(140),
  cash_bank_account varchar(140),
  base_paid_amount numeric(21,9),
  paid_amount numeric(21,9),
  base_change_amount numeric(21,9),
  change_amount numeric(21,9),
  account_for_change_amount varchar(140),
  write_off_amount numeric(21,9),
  base_write_off_amount numeric(21,9),
  write_off_outstanding_amount_automatically smallint,
  write_off_account varchar(140),
  write_off_cost_center varchar(140),
  tc_name varchar(140),
  terms text,
  letter_head varchar(140),
  group_same_items smallint,
  language varchar(140),
  select_print_heading varchar(140),
  inter_company_invoice_reference varchar(140),
  customer_group varchar(140),
  is_discounted smallint,
  status varchar(140),
  debit_to varchar(140),
  party_account_currency varchar(140),
  is_opening varchar(140),
  remarks text,
  sales_partner varchar(140),
  commission_rate numeric(21,9),
  total_commission numeric(21,9),
  from_date date,
  to_date date,
  auto_repeat varchar(140),
  against_income_account text,
  is_consolidated smallint,
  is_internal_customer smallint,
  company_tax_id varchar(140),
  unrealized_profit_loss_account varchar(140),
  represents_company varchar(140),
  set_target_warehouse varchar(140),
  is_debit_note smallint,
  disable_rounded_total smallint,
  additional_discount_account varchar(140),
  dispatch_address_name varchar(140),
  dispatch_address text,
  ignore_default_payment_terms_template smallint,
  total_billing_hours numeric(21,9),
  amount_eligible_for_commission numeric(21,9),
  subscription varchar(140),
  is_cash_or_non_trade_discount smallint,
  incoterm varchar(140),
  named_place varchar(140),
  only_include_allocated_payments smallint,
  use_company_roundoff_cost_center smallint,
  update_billed_amount_in_delivery_note smallint,
  dont_create_loyalty_points smallint,
  coupon_code varchar(140),
  update_outstanding_for_self smallint,
  utm_medium varchar(140),
  utm_content varchar(140),
  utm_campaign varchar(140),
  utm_source varchar(140),
  company_contact_person varchar(140),
  is_created_using_pos smallint,
  pos_closing_entry varchar(140),
  has_subcontracted smallint,
  apply_tds smallint,
  tax_withholding_group varchar(140),
  ignore_tax_withholding_threshold smallint,
  override_tax_withholding_entries smallint,
  title varchar(140)
);
CREATE INDEX ix_sales_invoice_customer ON "tabSales Invoice" (customer);
CREATE INDEX ix_sales_invoice_project ON "tabSales Invoice" (project);
CREATE INDEX ix_sales_invoice_posting_date ON "tabSales Invoice" (posting_date);
CREATE INDEX ix_sales_invoice_return_against ON "tabSales Invoice" (return_against);
CREATE INDEX ix_sales_invoice_inter_company_invoice_reference ON "tabSales Invoice" (inter_company_invoice_reference);
CREATE INDEX ix_sales_invoice_debit_to ON "tabSales Invoice" (debit_to);

-- Sales Invoice Advance (child)
CREATE TABLE "tabSales Invoice Advance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_type varchar(140),
  reference_name varchar(140),
  remarks text,
  reference_row varchar(140),
  advance_amount numeric(21,9),
  allocated_amount numeric(21,9),
  exchange_gain_loss numeric(21,9),
  ref_exchange_rate numeric(21,9),
  difference_posting_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_invoice_advance_parent ON "tabSales Invoice Advance" (parent);

-- Sales Invoice Item (child)
CREATE TABLE "tabSales Invoice Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  item_code varchar(140),
  is_product_bundle smallint,
  product_bundle varchar(140),
  item_name varchar(140),
  customer_item_code varchar(140),
  description text,
  image text,
  qty numeric(21,9),
  stock_uom varchar(140),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_qty numeric(21,9),
  price_list_rate numeric(21,9),
  base_price_list_rate numeric(21,9),
  margin_type varchar(140),
  margin_rate_or_amount numeric(21,9),
  rate_with_margin numeric(21,9),
  discount_percentage numeric(21,9),
  discount_amount numeric(21,9),
  base_rate_with_margin numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  base_rate numeric(21,9),
  base_amount numeric(21,9),
  pricing_rules text,
  is_free_item smallint,
  net_rate numeric(21,9),
  net_amount numeric(21,9),
  base_net_rate numeric(21,9),
  base_net_amount numeric(21,9),
  delivered_by_supplier smallint,
  income_account varchar(140),
  expense_account varchar(140),
  item_tax_template varchar(140),
  cost_center varchar(140),
  deferred_revenue_account varchar(140),
  service_stop_date date,
  enable_deferred_revenue smallint,
  service_start_date date,
  service_end_date date,
  weight_per_unit numeric(21,9),
  total_weight numeric(21,9),
  weight_uom varchar(140),
  warehouse varchar(140),
  target_warehouse varchar(140),
  quality_inspection varchar(140),
  batch_no varchar(140),
  allow_zero_valuation_rate smallint,
  serial_no text,
  item_group varchar(140),
  brand varchar(140),
  item_tax_rate text,
  actual_batch_qty numeric(21,9),
  actual_qty numeric(21,9),
  sales_order varchar(140),
  so_detail varchar(140),
  delivery_note varchar(140),
  dn_detail varchar(140),
  delivered_qty numeric(21,9),
  is_fixed_asset smallint,
  asset varchar(140),
  page_break smallint,
  finance_book varchar(140),
  project varchar(140),
  sales_invoice_item varchar(140),
  incoming_rate numeric(21,9),
  stock_uom_rate numeric(21,9),
  discount_account varchar(140),
  grant_commission smallint,
  purchase_order varchar(140),
  purchase_order_item varchar(140),
  has_item_scanned smallint,
  serial_and_batch_bundle varchar(140),
  use_serial_batch_fields smallint,
  distributed_discount_amount numeric(21,9),
  company_total_stock numeric(21,9),
  pos_invoice_item varchar(140),
  pos_invoice varchar(140),
  scio_detail varchar(140),
  tax_withholding_category varchar(140),
  apply_tds smallint,
  against_pick_list varchar(140),
  pick_list_item varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_invoice_item_item_code ON "tabSales Invoice Item" (item_code);
CREATE INDEX ix_sales_invoice_item_batch_no ON "tabSales Invoice Item" (batch_no);
CREATE INDEX ix_sales_invoice_item_sales_order ON "tabSales Invoice Item" (sales_order);
CREATE INDEX ix_sales_invoice_item_so_detail ON "tabSales Invoice Item" (so_detail);
CREATE INDEX ix_sales_invoice_item_delivery_note ON "tabSales Invoice Item" (delivery_note);
CREATE INDEX ix_sales_invoice_item_dn_detail ON "tabSales Invoice Item" (dn_detail);
CREATE INDEX ix_sales_invoice_item_project ON "tabSales Invoice Item" (project);
CREATE INDEX ix_sales_invoice_item_purchase_order ON "tabSales Invoice Item" (purchase_order);
CREATE INDEX ix_sales_invoice_item_serial_and_batch_bundle ON "tabSales Invoice Item" (serial_and_batch_bundle);
CREATE INDEX ix_sales_invoice_item_pos_invoice ON "tabSales Invoice Item" (pos_invoice);
CREATE INDEX ix_sales_invoice_item_parent ON "tabSales Invoice Item" (parent);

-- Sales Invoice Payment (child)
CREATE TABLE "tabSales Invoice Payment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  mode_of_payment varchar(140),
  amount numeric(21,9),
  account varchar(140),
  type varchar(140),
  base_amount numeric(21,9),
  clearance_date date,
  "default" smallint,
  reference_no varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_invoice_payment_parent ON "tabSales Invoice Payment" (parent);

-- Sales Invoice Reference (child)
CREATE TABLE "tabSales Invoice Reference" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  sales_invoice varchar(140),
  posting_date date,
  customer varchar(140),
  is_return smallint,
  return_against varchar(140),
  grand_total numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_invoice_reference_parent ON "tabSales Invoice Reference" (parent);

-- Sales Invoice Timesheet (child)
CREATE TABLE "tabSales Invoice Timesheet" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  time_sheet varchar(140),
  billing_hours numeric(21,9),
  billing_amount numeric(21,9),
  timesheet_detail varchar(140),
  activity_type varchar(140),
  description text,
  from_time timestamp,
  to_time timestamp,
  project_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_invoice_timesheet_parent ON "tabSales Invoice Timesheet" (parent);

-- Sales Partner Item (child)
CREATE TABLE "tabSales Partner Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  sales_partner varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_partner_item_parent ON "tabSales Partner Item" (parent);

-- Sales Taxes and Charges (child)
CREATE TABLE "tabSales Taxes and Charges" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  charge_type varchar(140),
  row_id varchar(140),
  account_head varchar(140),
  cost_center varchar(140),
  description text,
  included_in_print_rate smallint,
  rate numeric(21,9),
  tax_amount numeric(21,9),
  total numeric(21,9),
  tax_amount_after_discount_amount numeric(21,9),
  base_tax_amount numeric(21,9),
  base_total numeric(21,9),
  base_tax_amount_after_discount_amount numeric(21,9),
  project varchar(140),
  included_in_paid_amount smallint,
  dont_recompute_tax smallint,
  account_currency varchar(140),
  net_amount numeric(21,9),
  base_net_amount numeric(21,9),
  set_by_item_tax_template smallint,
  is_tax_withholding_account smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_sales_taxes_and_charges_account_head ON "tabSales Taxes and Charges" (account_head);
CREATE INDEX ix_sales_taxes_and_charges_parent ON "tabSales Taxes and Charges" (parent);

-- Sales Taxes and Charges Template (master)
CREATE TABLE "tabSales Taxes and Charges Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  is_default smallint,
  disabled smallint,
  company varchar(140),
  tax_category varchar(140)
);

-- Share Balance (child)
CREATE TABLE "tabShare Balance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  share_type varchar(140),
  from_no integer,
  rate numeric(21,9),
  no_of_shares integer,
  to_no integer,
  amount numeric(21,9),
  is_company smallint,
  current_state varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_share_balance_parent ON "tabShare Balance" (parent);

-- Share Transfer (transaction)
CREATE TABLE "tabShare Transfer" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  transfer_type varchar(140),
  date date,
  from_shareholder varchar(140),
  from_folio_no varchar(140),
  equity_or_liability_account varchar(140),
  asset_account varchar(140),
  to_shareholder varchar(140),
  to_folio_no varchar(140),
  share_type varchar(140),
  from_no integer,
  rate numeric(21,9),
  no_of_shares integer,
  to_no integer,
  amount numeric(21,9),
  company varchar(140),
  remarks text,
  amended_from varchar(140)
);

-- Share Type (master)
CREATE TABLE "tabShare Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  description text
);

-- Shareholder (master)
CREATE TABLE "tabShareholder" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  naming_series varchar(140),
  folio_no varchar(140),
  company varchar(140),
  is_company smallint,
  contact_list text
);

-- Shipping Rule (master)
CREATE TABLE "tabShipping Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  label varchar(140),
  disabled smallint,
  shipping_rule_type varchar(140),
  company varchar(140),
  account varchar(140),
  cost_center varchar(140),
  calculate_based_on varchar(140),
  shipping_amount numeric(21,9),
  project varchar(140)
);

-- Shipping Rule Condition (child)
CREATE TABLE "tabShipping Rule Condition" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  from_value numeric(21,9),
  to_value numeric(21,9),
  shipping_amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_shipping_rule_condition_parent ON "tabShipping Rule Condition" (parent);

-- Shipping Rule Country (child)
CREATE TABLE "tabShipping Rule Country" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  country varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_shipping_rule_country_parent ON "tabShipping Rule Country" (parent);

-- South Africa VAT Account (child)
CREATE TABLE "tabSouth Africa VAT Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_south_africa_vat_account_parent ON "tabSouth Africa VAT Account" (parent);

-- Subscription (master)
CREATE TABLE "tabSubscription" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  status varchar(140),
  cancelation_date date,
  trial_period_start date,
  trial_period_end date,
  current_invoice_start date,
  current_invoice_end date,
  next_billing_period_start date,
  next_billing_period_end date,
  days_until_due integer,
  cancel_at_period_end smallint,
  apply_additional_discount varchar(140),
  additional_discount_percentage numeric(21,9),
  additional_discount_amount numeric(21,9),
  party_type varchar(140),
  party varchar(140),
  sales_tax_template varchar(140),
  purchase_tax_template varchar(140),
  follow_calendar_months smallint,
  generate_new_invoices_past_due_date smallint,
  end_date date,
  start_date date,
  cost_center varchar(140),
  company varchar(140),
  submit_invoice smallint,
  generate_invoice_at varchar(140),
  number_of_days integer
);

-- Subscription Invoice (child)
CREATE TABLE "tabSubscription Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  document_type varchar(140),
  invoice varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subscription_invoice_parent ON "tabSubscription Invoice" (parent);

-- Subscription Plan (master)
CREATE TABLE "tabSubscription Plan" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  plan_name varchar(140),
  currency varchar(140),
  item varchar(140),
  price_determination varchar(140),
  cost numeric(21,9),
  price_list varchar(140),
  billing_interval varchar(140),
  billing_interval_count integer,
  payment_gateway varchar(140),
  cost_center varchar(140),
  product_price_id varchar(140)
);

-- Subscription Plan Detail (child)
CREATE TABLE "tabSubscription Plan Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  qty integer,
  plan varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subscription_plan_detail_parent ON "tabSubscription Plan Detail" (parent);

-- Supplier Group Item (child)
CREATE TABLE "tabSupplier Group Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  supplier_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_supplier_group_item_parent ON "tabSupplier Group Item" (parent);

-- Supplier Item (child)
CREATE TABLE "tabSupplier Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  supplier varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_supplier_item_parent ON "tabSupplier Item" (parent);

-- Tax Category (master)
CREATE TABLE "tabTax Category" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  disabled smallint
);

-- Tax Rule (master)
CREATE TABLE "tabTax Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  tax_type varchar(140),
  use_for_shopping_cart smallint,
  sales_tax_template varchar(140),
  purchase_tax_template varchar(140),
  customer varchar(140),
  supplier varchar(140),
  item varchar(140),
  billing_city varchar(140),
  billing_county varchar(140),
  billing_state varchar(140),
  billing_zipcode varchar(140),
  billing_country varchar(140),
  tax_category varchar(140),
  customer_group varchar(140),
  supplier_group varchar(140),
  item_group varchar(140),
  shipping_city varchar(140),
  shipping_county varchar(140),
  shipping_state varchar(140),
  shipping_zipcode varchar(140),
  shipping_country varchar(140),
  from_date date,
  to_date date,
  priority integer,
  company varchar(140)
);

-- Tax Withholding Account (child)
CREATE TABLE "tabTax Withholding Account" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_tax_withholding_account_parent ON "tabTax Withholding Account" (parent);

-- Tax Withholding Category (master)
CREATE TABLE "tabTax Withholding Category" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  category_name varchar(140),
  tax_on_excess_amount smallint,
  round_off_tax_amount smallint,
  tax_deduction_basis varchar(140),
  disable_cumulative_threshold smallint,
  disable_transaction_threshold smallint
);

-- Tax Withholding Entry (child)
CREATE TABLE "tabTax Withholding Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  party_type varchar(140),
  party varchar(140),
  tax_id varchar(140),
  tax_withholding_category varchar(140),
  tax_rate numeric(21,9),
  taxable_amount numeric(21,9),
  lower_deduction_certificate varchar(140),
  status varchar(140),
  currency varchar(140),
  conversion_rate numeric(21,9),
  withholding_doctype varchar(140),
  withholding_name varchar(140),
  taxable_doctype varchar(140),
  taxable_name varchar(140),
  taxable_date date,
  withholding_date date,
  under_withheld_reason varchar(140),
  withholding_amount numeric(21,9),
  tax_withholding_group varchar(140),
  company varchar(140),
  created_by_migration smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_tax_withholding_entry_parent ON "tabTax Withholding Entry" (parent);

-- Tax Withholding Group (master)
CREATE TABLE "tabTax Withholding Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  group_name varchar(140)
);

-- Tax Withholding Rate (child)
CREATE TABLE "tabTax Withholding Rate" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  tax_withholding_rate numeric(21,9),
  single_threshold numeric(21,9),
  cumulative_threshold numeric(21,9),
  from_date date,
  to_date date,
  tax_withholding_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_tax_withholding_rate_parent ON "tabTax Withholding Rate" (parent);

-- Territory Item (child)
CREATE TABLE "tabTerritory Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  territory varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_territory_item_parent ON "tabTerritory Item" (parent);

-- Transaction Deletion Record Details (child)
CREATE TABLE "tabTransaction Deletion Record Details" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  doctype_name varchar(140),
  docfield_name varchar(140),
  no_of_docs integer,
  done smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_transaction_deletion_record_details_parent ON "tabTransaction Deletion Record Details" (parent);

-- Unreconcile Payment (transaction)
CREATE TABLE "tabUnreconcile Payment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  amended_from varchar(140),
  company varchar(140),
  voucher_type varchar(140),
  voucher_no varchar(140)
);

-- Unreconcile Payment Entries (child)
CREATE TABLE "tabUnreconcile Payment Entries" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_name varchar(140),
  allocated_amount numeric(21,9),
  unlinked smallint,
  reference_doctype varchar(140),
  account varchar(140),
  party_type varchar(140),
  party varchar(140),
  account_currency varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_unreconcile_payment_entries_parent ON "tabUnreconcile Payment Entries" (parent);
