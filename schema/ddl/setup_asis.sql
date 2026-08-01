-- ============================================================
-- Setup - AS-IS DDL (PostgreSQL) generated from DocType JSON
-- Mirrors the ERPNext physical layout: business-key PK, no FK constraints.
-- ============================================================

-- Authorization Rule (master)
CREATE TABLE "tabAuthorization Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  transaction varchar(140),
  based_on varchar(140),
  customer_or_item varchar(140),
  master_name varchar(140),
  company varchar(140),
  value numeric(21,9),
  system_role varchar(140),
  to_emp varchar(140),
  system_user varchar(140),
  to_designation varchar(140),
  approving_role varchar(140),
  approving_user varchar(140)
);

-- Branch (master)
CREATE TABLE "tabBranch" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  branch varchar(140)
);

-- Brand (master)
CREATE TABLE "tabBrand" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  brand varchar(140),
  description text,
  image text
);

-- Company (tree-master)
CREATE TABLE "tabCompany" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company_name varchar(140),
  abbr varchar(140),
  is_group smallint,
  default_finance_book varchar(140),
  domain varchar(140),
  parent_company varchar(140),
  company_logo text,
  company_description text,
  sales_monthly_history text,
  transactions_annual_history text,
  monthly_sales_target numeric(21,9),
  total_monthly_sales numeric(21,9),
  default_currency varchar(140),
  default_letter_head varchar(140),
  default_holiday_list varchar(140),
  default_warehouse_for_sales_return varchar(140),
  country varchar(140),
  create_chart_of_accounts_based_on varchar(140),
  chart_of_accounts varchar(140),
  existing_company varchar(140),
  tax_id varchar(140),
  date_of_establishment date,
  default_bank_account varchar(140),
  default_cash_account varchar(140),
  default_receivable_account varchar(140),
  round_off_account varchar(140),
  round_off_cost_center varchar(140),
  write_off_account varchar(140),
  exchange_gain_loss_account varchar(140),
  unrealized_exchange_gain_loss_account varchar(140),
  allow_account_creation_against_child_company smallint,
  default_payable_account varchar(140),
  default_expense_account varchar(140),
  default_income_account varchar(140),
  default_deferred_revenue_account varchar(140),
  default_deferred_expense_account varchar(140),
  cost_center varchar(140),
  credit_limit numeric(21,9),
  payment_terms varchar(140),
  enable_perpetual_inventory smallint,
  default_inventory_account varchar(140),
  stock_adjustment_account varchar(140),
  default_purchase_price_variance_account varchar(140),
  default_manufacturing_variance_account varchar(140),
  stock_received_but_not_billed varchar(140),
  accumulated_depreciation_account varchar(140),
  depreciation_expense_account varchar(140),
  series_for_depreciation_entry varchar(140),
  disposal_account varchar(140),
  depreciation_cost_center varchar(140),
  capital_work_in_progress_account varchar(140),
  asset_received_but_not_billed varchar(140),
  exception_budget_approver_role varchar(140),
  date_of_incorporation date,
  date_of_commencement date,
  phone_no varchar(140),
  fax varchar(140),
  email varchar(140),
  website varchar(140),
  registration_details text,
  lft integer,
  rgt integer,
  old_parent varchar(140),
  default_selling_terms varchar(140),
  default_buying_terms varchar(140),
  default_in_transit_warehouse varchar(140),
  default_warehouse varchar(140),
  sample_retention_warehouse varchar(140),
  unrealized_profit_loss_account varchar(140),
  default_discount_account varchar(140),
  enable_provisional_accounting_for_non_stock_items smallint,
  default_provisional_account varchar(140),
  default_advance_received_account varchar(140),
  default_advance_paid_account varchar(140),
  book_advance_payments_in_separate_party_account smallint,
  auto_exchange_rate_revaluation smallint,
  auto_err_frequency varchar(140),
  submit_err_jv smallint,
  reconcile_on_advance_payment_date smallint,
  default_operating_cost_account varchar(140),
  round_off_for_opening varchar(140),
  reconciliation_takes_effect_on varchar(140),
  reporting_currency varchar(140),
  purchase_expense_account varchar(140),
  purchase_expense_contra_account varchar(140),
  service_expense_account varchar(140),
  expenses_added_to_stock_account varchar(140),
  expenses_added_to_stock_contra_account varchar(140),
  enable_item_wise_inventory_account smallint,
  valuation_method varchar(140),
  default_wip_warehouse varchar(140),
  default_fg_warehouse varchar(140),
  default_scrap_warehouse varchar(140),
  default_sales_contact varchar(140),
  accounts_frozen_till_date date,
  role_allowed_for_frozen_entries varchar(140),
  default_letter_head_report varchar(140),
  disable_sdbnb_in_sr smallint,
  stock_delivered_but_not_billed varchar(140),
  enable_stock_delivered_but_not_billed smallint
);
CREATE INDEX ix_company_lft ON "tabCompany" (lft);
CREATE INDEX ix_company_rgt ON "tabCompany" (rgt);

-- Currency Exchange (master)
CREATE TABLE "tabCurrency Exchange" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  date date,
  from_currency varchar(140),
  to_currency varchar(140),
  exchange_rate numeric(21,9),
  for_buying smallint,
  for_selling smallint
);

-- Customer Group (tree-master)
CREATE TABLE "tabCustomer Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer_group_name varchar(140),
  parent_customer_group varchar(140),
  is_group smallint,
  default_price_list varchar(140),
  payment_terms varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140)
);
CREATE INDEX ix_customer_group_lft ON "tabCustomer Group" (lft);
CREATE INDEX ix_customer_group_rgt ON "tabCustomer Group" (rgt);

-- Department (tree-master)
CREATE TABLE "tabDepartment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  department_name varchar(140),
  parent_department varchar(140),
  company varchar(140),
  is_group smallint,
  disabled smallint,
  lft integer,
  rgt integer,
  old_parent varchar(140)
);

-- Designation (master)
CREATE TABLE "tabDesignation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  designation_name varchar(140),
  description text
);

-- Driver (master)
CREATE TABLE "tabDriver" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  full_name varchar(140),
  status varchar(140),
  transporter varchar(140),
  employee varchar(140),
  cell_number varchar(140),
  license_number varchar(140),
  issuing_date date,
  expiry_date date,
  address varchar(140),
  "user" varchar(140)
);

-- Driving License Category (child)
CREATE TABLE "tabDriving License Category" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  class varchar(140),
  description varchar(140),
  issuing_date date,
  expiry_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_driving_license_category_parent ON "tabDriving License Category" (parent);

-- Email Digest (master)
CREATE TABLE "tabEmail Digest" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  enabled smallint,
  company varchar(140),
  frequency varchar(140),
  next_send varchar(140),
  income smallint,
  expenses_booked smallint,
  income_year_to_date smallint,
  expense_year_to_date smallint,
  bank_balance smallint,
  credit_balance smallint,
  invoiced_amount smallint,
  payables smallint,
  sales_orders_to_bill smallint,
  purchase_orders_to_bill smallint,
  sales_order smallint,
  purchase_order smallint,
  sales_orders_to_deliver smallint,
  purchase_orders_to_receive smallint,
  sales_invoice smallint,
  purchase_invoice smallint,
  new_quotations smallint,
  pending_quotations smallint,
  issue smallint,
  project smallint,
  purchase_orders_items_overdue smallint,
  calendar_events smallint,
  todo_list smallint,
  notifications smallint,
  add_quote smallint
);

-- Email Digest Recipient (child)
CREATE TABLE "tabEmail Digest Recipient" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  recipient varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_email_digest_recipient_parent ON "tabEmail Digest Recipient" (parent);

-- Employee (tree-master)
CREATE TABLE "tabEmployee" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  employee varchar(140),
  naming_series varchar(140),
  salutation varchar(140),
  first_name varchar(140),
  middle_name varchar(140),
  last_name varchar(140),
  employee_name varchar(140),
  image text,
  company varchar(140),
  status varchar(140),
  employee_number varchar(140),
  gender varchar(140),
  date_of_birth date,
  date_of_joining date,
  emergency_phone_number varchar(140),
  person_to_be_contacted varchar(140),
  relation varchar(140),
  user_id varchar(140),
  create_user_permission smallint,
  create_user_automatically smallint,
  scheduled_confirmation_date date,
  final_confirmation_date date,
  contract_end_date date,
  notice_number_of_days integer,
  date_of_retirement date,
  department varchar(140),
  designation varchar(140),
  reports_to varchar(140),
  branch varchar(140),
  holiday_list varchar(140),
  salary_mode varchar(140),
  bank_name varchar(140),
  bank_ac_no varchar(140),
  cell_number varchar(140),
  prefered_contact_email varchar(140),
  prefered_email varchar(140),
  company_email varchar(140),
  personal_email varchar(140),
  unsubscribed smallint,
  permanent_accommodation_type varchar(140),
  permanent_address text,
  current_accommodation_type varchar(140),
  current_address text,
  bio text,
  passport_number varchar(140),
  date_of_issue date,
  valid_upto date,
  place_of_issue varchar(140),
  marital_status varchar(140),
  blood_group varchar(140),
  family_background text,
  health_details text,
  resignation_letter_date date,
  relieving_date date,
  reason_for_leaving text,
  leave_encashed varchar(140),
  encashment_date date,
  held_on date,
  new_workplace varchar(140),
  feedback text,
  lft integer,
  rgt integer,
  old_parent varchar(140),
  attendance_device_id varchar(140),
  salary_currency varchar(140),
  ctc numeric(21,9),
  iban varchar(140)
);
CREATE INDEX ix_employee_status ON "tabEmployee" (status);
CREATE INDEX ix_employee_designation ON "tabEmployee" (designation);

-- Employee Education (child)
CREATE TABLE "tabEmployee Education" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  school_univ text,
  qualification varchar(140),
  level varchar(140),
  year_of_passing integer,
  class_per varchar(140),
  maj_opt_subj text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_employee_education_parent ON "tabEmployee Education" (parent);

-- Employee External Work History (child)
CREATE TABLE "tabEmployee External Work History" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company_name varchar(140),
  designation varchar(140),
  salary numeric(21,9),
  address text,
  contact varchar(140),
  total_experience varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_employee_external_work_history_parent ON "tabEmployee External Work History" (parent);

-- Employee Group (master)
CREATE TABLE "tabEmployee Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  employee_group_name varchar(140)
);

-- Employee Group Table (child)
CREATE TABLE "tabEmployee Group Table" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  employee varchar(140),
  employee_name varchar(140),
  user_id varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_employee_group_table_parent ON "tabEmployee Group Table" (parent);

-- Employee Internal Work History (child)
CREATE TABLE "tabEmployee Internal Work History" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  branch varchar(140),
  department varchar(140),
  designation varchar(140),
  from_date date,
  to_date date,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_employee_internal_work_history_parent ON "tabEmployee Internal Work History" (parent);

-- Holiday (child)
CREATE TABLE "tabHoliday" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  holiday_date date,
  description text,
  weekly_off smallint,
  is_half_day smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_holiday_parent ON "tabHoliday" (parent);

-- Holiday List (master)
CREATE TABLE "tabHoliday List" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  holiday_list_name varchar(140),
  from_date date,
  to_date date,
  total_holidays integer,
  weekly_off varchar(140),
  color varchar(140),
  country varchar(140),
  subdivision varchar(140),
  is_half_day smallint
);

-- Incoterm (master)
CREATE TABLE "tabIncoterm" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  code varchar(140),
  title varchar(140),
  description text
);

-- Item Group (tree-master)
CREATE TABLE "tabItem Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_group_name varchar(140),
  parent_item_group varchar(140),
  is_group smallint,
  image text,
  lft integer,
  rgt integer,
  old_parent varchar(140)
);
CREATE INDEX ix_item_group_lft ON "tabItem Group" (lft);
CREATE INDEX ix_item_group_rgt ON "tabItem Group" (rgt);

-- Party Type (master)
CREATE TABLE "tabParty Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  party_type varchar(140),
  account_type varchar(140)
);

-- Quotation Lost Reason (master)
CREATE TABLE "tabQuotation Lost Reason" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  order_lost_reason varchar(140)
);

-- Quotation Lost Reason Detail (child)
CREATE TABLE "tabQuotation Lost Reason Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  lost_reason varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_quotation_lost_reason_detail_parent ON "tabQuotation Lost Reason Detail" (parent);

-- Sales Partner (master)
CREATE TABLE "tabSales Partner" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  partner_name varchar(140),
  partner_type varchar(140),
  territory varchar(140),
  commission_rate numeric(21,9),
  show_in_website smallint,
  referral_code varchar(140),
  route varchar(140),
  logo text,
  partner_website varchar(140),
  introduction text,
  description text
);

-- Sales Person (tree-master)
CREATE TABLE "tabSales Person" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  sales_person_name varchar(140),
  parent_sales_person varchar(140),
  commission_rate numeric(21,9),
  is_group smallint,
  enabled smallint,
  employee varchar(140),
  department varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140)
);
CREATE INDEX ix_sales_person_lft ON "tabSales Person" (lft);
CREATE INDEX ix_sales_person_rgt ON "tabSales Person" (rgt);

-- Supplier Group (tree-master)
CREATE TABLE "tabSupplier Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  supplier_group_name varchar(140),
  parent_supplier_group varchar(140),
  is_group smallint,
  payment_terms varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140)
);
CREATE INDEX ix_supplier_group_lft ON "tabSupplier Group" (lft);
CREATE INDEX ix_supplier_group_rgt ON "tabSupplier Group" (rgt);

-- Target Detail (child)
CREATE TABLE "tabTarget Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_group varchar(140),
  fiscal_year varchar(140),
  target_qty numeric(21,9),
  target_amount numeric(21,9),
  distribution_id varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_target_detail_item_group ON "tabTarget Detail" (item_group);
CREATE INDEX ix_target_detail_fiscal_year ON "tabTarget Detail" (fiscal_year);
CREATE INDEX ix_target_detail_target_amount ON "tabTarget Detail" (target_amount);
CREATE INDEX ix_target_detail_parent ON "tabTarget Detail" (parent);

-- Terms and Conditions (master)
CREATE TABLE "tabTerms and Conditions" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  disabled smallint,
  terms text,
  selling smallint,
  buying smallint,
  copy_attachments_to_transaction smallint
);

-- Territory (tree-master)
CREATE TABLE "tabTerritory" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  territory_name varchar(140),
  parent_territory varchar(140),
  is_group smallint,
  territory_manager varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140)
);
CREATE INDEX ix_territory_territory_manager ON "tabTerritory" (territory_manager);
CREATE INDEX ix_territory_lft ON "tabTerritory" (lft);
CREATE INDEX ix_territory_rgt ON "tabTerritory" (rgt);

-- Transaction Deletion Record (transaction)
CREATE TABLE "tabTransaction Deletion Record" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  amended_from varchar(140),
  status varchar(140),
  delete_bin_data_status varchar(140),
  delete_leads_and_addresses_status varchar(140),
  reset_company_default_values_status varchar(140),
  clear_notifications_status varchar(140),
  initialize_doctypes_table_status varchar(140),
  delete_transactions_status varchar(140),
  error_log text,
  process_in_single_transaction smallint
);

-- Transaction Deletion Record Item (child)
CREATE TABLE "tabTransaction Deletion Record Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  doctype_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_transaction_deletion_record_item_parent ON "tabTransaction Deletion Record Item" (parent);

-- Transaction Deletion Record To Delete (child)
CREATE TABLE "tabTransaction Deletion Record To Delete" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  doctype_name varchar(140),
  company_field varchar(140),
  document_count integer,
  child_doctypes text,
  deleted smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_transaction_deletion_record_to_delete_parent ON "tabTransaction Deletion Record To Delete" (parent);

-- UOM (master)
CREATE TABLE "tabUOM" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  uom_name varchar(140),
  must_be_whole_number smallint,
  enabled smallint,
  symbol varchar(140),
  common_code varchar(140),
  description text,
  category varchar(140)
);

-- UOM Conversion Factor (master)
CREATE TABLE "tabUOM Conversion Factor" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  category varchar(140),
  from_uom varchar(140),
  to_uom varchar(140),
  value numeric(21,9)
);

-- Vehicle (master)
CREATE TABLE "tabVehicle" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  license_plate varchar(140),
  make varchar(140),
  model varchar(140),
  last_odometer integer,
  acquisition_date date,
  location varchar(140),
  chassis_no varchar(140),
  vehicle_value numeric(21,9),
  employee varchar(140),
  insurance_company varchar(140),
  policy_no varchar(140),
  start_date date,
  end_date date,
  fuel_type varchar(140),
  uom varchar(140),
  carbon_check_date date,
  color varchar(140),
  wheels integer,
  doors integer,
  amended_from varchar(140),
  company varchar(140)
);

-- Website Item Group (child)
CREATE TABLE "tabWebsite Item Group" (
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
CREATE INDEX ix_website_item_group_parent ON "tabWebsite Item Group" (parent);
