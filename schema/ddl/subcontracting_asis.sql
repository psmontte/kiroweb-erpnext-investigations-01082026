-- ============================================================
-- Subcontracting - AS-IS DDL (PostgreSQL) generated from DocType JSON
-- Mirrors the ERPNext physical layout: business-key PK, no FK constraints.
-- ============================================================

-- Subcontracting BOM (master)
CREATE TABLE "tabSubcontracting BOM" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  is_active smallint,
  finished_good varchar(140),
  finished_good_qty numeric(21,9),
  finished_good_bom varchar(140),
  service_item varchar(140),
  service_item_qty numeric(21,9),
  service_item_uom varchar(140),
  conversion_factor numeric(21,9),
  finished_good_uom varchar(140)
);
CREATE INDEX ix_subcontracting_bom_finished_good ON "tabSubcontracting BOM" (finished_good);
CREATE INDEX ix_subcontracting_bom_finished_good_bom ON "tabSubcontracting BOM" (finished_good_bom);
CREATE INDEX ix_subcontracting_bom_service_item ON "tabSubcontracting BOM" (service_item);

-- Subcontracting Inward Order (transaction)
CREATE TABLE "tabSubcontracting Inward Order" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  naming_series varchar(140),
  sales_order varchar(140),
  customer varchar(140),
  customer_name varchar(140),
  company varchar(140),
  transaction_date date,
  amended_from varchar(140),
  status varchar(140),
  per_delivered numeric(21,9),
  per_produced numeric(21,9),
  per_process_loss numeric(21,9),
  set_delivery_warehouse varchar(140),
  customer_warehouse varchar(140),
  per_returned numeric(21,9),
  per_raw_material_returned numeric(21,9),
  per_raw_material_received numeric(21,9),
  currency varchar(140)
);
CREATE INDEX ix_subcontracting_inward_order_customer ON "tabSubcontracting Inward Order" (customer);
CREATE INDEX ix_subcontracting_inward_order_transaction_date ON "tabSubcontracting Inward Order" (transaction_date);
CREATE INDEX ix_subcontracting_inward_order_status ON "tabSubcontracting Inward Order" (status);

-- Subcontracting Inward Order Item (child)
CREATE TABLE "tabSubcontracting Inward Order Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  qty numeric(21,9),
  stock_uom varchar(140),
  conversion_factor numeric(21,9),
  bom varchar(140),
  include_exploded_items smallint,
  delivered_qty numeric(21,9),
  returned_qty numeric(21,9),
  sales_order_item varchar(140),
  subcontracting_conversion_factor numeric(21,9),
  produced_qty numeric(21,9),
  process_loss_qty numeric(21,9),
  delivery_warehouse varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_inward_order_item_item_code ON "tabSubcontracting Inward Order Item" (item_code);
CREATE INDEX ix_subcontracting_inward_order_item_sales_order_item ON "tabSubcontracting Inward Order Item" (sales_order_item);
CREATE INDEX ix_subcontracting_inward_order_item_parent ON "tabSubcontracting Inward Order Item" (parent);

-- Subcontracting Inward Order Received Item (child)
CREATE TABLE "tabSubcontracting Inward Order Received Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  main_item_code varchar(140),
  rm_item_code varchar(140),
  stock_uom varchar(140),
  bom_detail_no varchar(140),
  reference_name varchar(140),
  required_qty numeric(21,9),
  received_qty numeric(21,9),
  consumed_qty numeric(21,9),
  returned_qty numeric(21,9),
  work_order_qty numeric(21,9),
  is_customer_provided_item smallint,
  warehouse varchar(140),
  billed_qty numeric(21,9),
  is_additional_item smallint,
  rate numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_inward_order_received_item_parent ON "tabSubcontracting Inward Order Received Item" (parent);

-- Subcontracting Inward Order Secondary Item (child)
CREATE TABLE "tabSubcontracting Inward Order Secondary Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  stock_uom varchar(140),
  reference_name varchar(140),
  produced_qty numeric(21,9),
  delivered_qty numeric(21,9),
  fg_item_code varchar(140),
  warehouse varchar(140),
  secondary_item_type varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_inward_order_secondary_item_parent ON "tabSubcontracting Inward Order Secondary Item" (parent);

-- Subcontracting Inward Order Service Item (child)
CREATE TABLE "tabSubcontracting Inward Order Service Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  qty numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  fg_item varchar(140),
  fg_item_qty numeric(21,9),
  sales_order_item varchar(140),
  uom varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_inward_order_service_item_item_code ON "tabSubcontracting Inward Order Service Item" (item_code);
CREATE INDEX ix_subcontracting_inward_order_service_item_sales_order_item ON "tabSubcontracting Inward Order Service Item" (sales_order_item);
CREATE INDEX ix_subcontracting_inward_order_service_item_parent ON "tabSubcontracting Inward Order Service Item" (parent);

-- Subcontracting Order (transaction)
CREATE TABLE "tabSubcontracting Order" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  title varchar(140),
  naming_series varchar(140),
  purchase_order varchar(140),
  supplier varchar(140),
  supplier_name varchar(140),
  supplier_warehouse varchar(140),
  company varchar(140),
  transaction_date date,
  schedule_date date,
  amended_from varchar(140),
  supplier_address varchar(140),
  address_display text,
  contact_person varchar(140),
  contact_display text,
  contact_mobile text,
  contact_email text,
  shipping_address varchar(140),
  shipping_address_display text,
  billing_address varchar(140),
  billing_address_display text,
  set_warehouse varchar(140),
  total_qty numeric(21,9),
  total numeric(21,9),
  set_reserve_warehouse varchar(140),
  total_additional_costs numeric(21,9),
  status varchar(140),
  per_received numeric(21,9),
  select_print_heading varchar(140),
  letter_head varchar(140),
  distribute_additional_costs_based_on varchar(140),
  cost_center varchar(140),
  project varchar(140),
  supplier_currency varchar(140),
  reserve_stock smallint,
  production_plan varchar(140)
);
CREATE INDEX ix_subcontracting_order_supplier ON "tabSubcontracting Order" (supplier);
CREATE INDEX ix_subcontracting_order_transaction_date ON "tabSubcontracting Order" (transaction_date);
CREATE INDEX ix_subcontracting_order_status ON "tabSubcontracting Order" (status);

-- Subcontracting Order Item (child)
CREATE TABLE "tabSubcontracting Order Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  schedule_date date,
  expected_delivery_date date,
  description text,
  image text,
  qty numeric(21,9),
  stock_uom varchar(140),
  conversion_factor numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  warehouse varchar(140),
  expense_account varchar(140),
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  bom varchar(140),
  include_exploded_items smallint,
  service_cost_per_qty numeric(21,9),
  additional_cost_per_qty numeric(21,9),
  rm_cost_per_qty numeric(21,9),
  page_break smallint,
  received_qty numeric(21,9),
  returned_qty numeric(21,9),
  cost_center varchar(140),
  project varchar(140),
  material_request varchar(140),
  material_request_item varchar(140),
  purchase_order_item varchar(140),
  job_card varchar(140),
  subcontracting_conversion_factor numeric(21,9),
  production_plan_sub_assembly_item varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_order_item_item_code ON "tabSubcontracting Order Item" (item_code);
CREATE INDEX ix_subcontracting_order_item_expected_delivery_date ON "tabSubcontracting Order Item" (expected_delivery_date);
CREATE INDEX ix_subcontracting_order_item_material_request ON "tabSubcontracting Order Item" (material_request);
CREATE INDEX ix_subcontracting_order_item_material_request_item ON "tabSubcontracting Order Item" (material_request_item);
CREATE INDEX ix_subcontracting_order_item_purchase_order_item ON "tabSubcontracting Order Item" (purchase_order_item);
CREATE INDEX ix_subcontracting_order_item_parent ON "tabSubcontracting Order Item" (parent);

-- Subcontracting Order Service Item (child)
CREATE TABLE "tabSubcontracting Order Service Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  qty numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  fg_item varchar(140),
  fg_item_qty numeric(21,9),
  purchase_order_item varchar(140),
  material_request varchar(140),
  material_request_item varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_order_service_item_item_code ON "tabSubcontracting Order Service Item" (item_code);
CREATE INDEX ix_subcontracting_order_service_item_purchase_order_item ON "tabSubcontracting Order Service Item" (purchase_order_item);
CREATE INDEX ix_subcontracting_order_service_item_parent ON "tabSubcontracting Order Service Item" (parent);

-- Subcontracting Order Supplied Item (child)
CREATE TABLE "tabSubcontracting Order Supplied Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  main_item_code varchar(140),
  rm_item_code varchar(140),
  stock_uom varchar(140),
  conversion_factor numeric(21,9),
  reserve_warehouse varchar(140),
  bom_detail_no varchar(140),
  reference_name varchar(140),
  rate numeric(21,9),
  amount numeric(21,9),
  required_qty numeric(21,9),
  supplied_qty numeric(21,9),
  consumed_qty numeric(21,9),
  returned_qty numeric(21,9),
  total_supplied_qty numeric(21,9),
  stock_reserved_qty numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_order_supplied_item_parent ON "tabSubcontracting Order Supplied Item" (parent);

-- Subcontracting Receipt (transaction)
CREATE TABLE "tabSubcontracting Receipt" (
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
  posting_date date,
  posting_time time(6),
  company varchar(140),
  supplier_address varchar(140),
  contact_person varchar(140),
  address_display text,
  contact_display text,
  contact_mobile text,
  contact_email text,
  shipping_address varchar(140),
  shipping_address_display text,
  set_warehouse varchar(140),
  rejected_warehouse varchar(140),
  supplier_warehouse varchar(140),
  total_qty numeric(21,9),
  total numeric(21,9),
  in_words varchar(140),
  bill_no varchar(140),
  bill_date date,
  status varchar(140),
  amended_from varchar(140),
  range varchar(140),
  auto_repeat varchar(140),
  letter_head varchar(140),
  select_print_heading varchar(140),
  language varchar(140),
  instructions text,
  remarks text,
  transporter_name varchar(140),
  lr_no varchar(140),
  lr_date date,
  billing_address varchar(140),
  billing_address_display text,
  represents_company varchar(140),
  is_return smallint,
  return_against varchar(140),
  per_returned numeric(21,9),
  cost_center varchar(140),
  project varchar(140),
  distribute_additional_costs_based_on varchar(140),
  total_additional_costs numeric(21,9),
  set_posting_time smallint,
  supplier_delivery_note varchar(140)
);
CREATE INDEX ix_subcontracting_receipt_supplier ON "tabSubcontracting Receipt" (supplier);
CREATE INDEX ix_subcontracting_receipt_posting_date ON "tabSubcontracting Receipt" (posting_date);
CREATE INDEX ix_subcontracting_receipt_status ON "tabSubcontracting Receipt" (status);

-- Subcontracting Receipt Item (child)
CREATE TABLE "tabSubcontracting Receipt Item" (
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
  conversion_factor numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  rm_cost_per_qty numeric(21,9),
  service_cost_per_qty numeric(21,9),
  additional_cost_per_qty numeric(21,9),
  warehouse varchar(140),
  rejected_warehouse varchar(140),
  quality_inspection varchar(140),
  subcontracting_order varchar(140),
  schedule_date date,
  serial_no text,
  batch_no varchar(140),
  rejected_serial_no text,
  subcontracting_order_item varchar(140),
  bom varchar(140),
  brand varchar(140),
  rm_supp_cost numeric(21,9),
  expense_account varchar(140),
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  subcontracting_receipt_item varchar(140),
  project varchar(140),
  cost_center varchar(140),
  page_break smallint,
  returned_qty numeric(21,9),
  serial_and_batch_bundle varchar(140),
  rejected_serial_and_batch_bundle varchar(140),
  reference_name varchar(140),
  purchase_order_item varchar(140),
  purchase_order varchar(140),
  include_exploded_items smallint,
  use_serial_batch_fields smallint,
  job_card varchar(140),
  landed_cost_voucher_amount numeric(21,9),
  service_expense_account varchar(140),
  secondary_item_type varchar(140),
  secondary_items_cost_per_qty numeric(21,9),
  is_legacy_scrap_item smallint,
  process_loss_qty numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_receipt_item_item_code ON "tabSubcontracting Receipt Item" (item_code);
CREATE INDEX ix_subcontracting_receipt_item_subcontracting_order ON "tabSubcontracting Receipt Item" (subcontracting_order);
CREATE INDEX ix_subcontracting_receipt_item_subcontracting_order_item ON "tabSubcontracting Receipt Item" (subcontracting_order_item);
CREATE INDEX ix_subcontracting_receipt_item_purchase_order_item ON "tabSubcontracting Receipt Item" (purchase_order_item);
CREATE INDEX ix_subcontracting_receipt_item_purchase_order ON "tabSubcontracting Receipt Item" (purchase_order);
CREATE INDEX ix_subcontracting_receipt_item_job_card ON "tabSubcontracting Receipt Item" (job_card);
CREATE INDEX ix_subcontracting_receipt_item_parent ON "tabSubcontracting Receipt Item" (parent);

-- Subcontracting Receipt Supplied Item (child)
CREATE TABLE "tabSubcontracting Receipt Supplied Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  main_item_code varchar(140),
  rm_item_code varchar(140),
  description text,
  batch_no varchar(140),
  serial_no text,
  required_qty numeric(21,9),
  consumed_qty numeric(21,9),
  stock_uom varchar(140),
  rate numeric(21,9),
  amount numeric(21,9),
  conversion_factor numeric(21,9),
  current_stock numeric(21,9),
  reference_name varchar(140),
  bom_detail_no varchar(140),
  item_name varchar(140),
  subcontracting_order varchar(140),
  available_qty_for_consumption numeric(21,9),
  serial_and_batch_bundle varchar(140),
  use_serial_batch_fields smallint,
  expense_account varchar(140),
  cost_center varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_subcontracting_receipt_supplied_item_parent ON "tabSubcontracting Receipt Supplied Item" (parent);
