-- ============================================================
-- Stock - AS-IS DDL (PostgreSQL) generated from DocType JSON
-- Mirrors the ERPNext physical layout: business-key PK, no FK constraints.
-- ============================================================

-- Batch (master)
CREATE TABLE "tabBatch" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  disabled smallint,
  batch_id varchar(140),
  item varchar(140),
  image text,
  parent_batch varchar(140),
  manufacturing_date date,
  expiry_date date,
  supplier varchar(140),
  reference_doctype varchar(140),
  reference_name varchar(140),
  description text,
  item_name varchar(140),
  batch_qty numeric(21,9),
  stock_uom varchar(140),
  qty_to_produce numeric(21,9),
  produced_qty numeric(21,9),
  use_batchwise_valuation smallint,
  allow_negative_stock_for_batch smallint
);

-- Bin (master)
CREATE TABLE "tabBin" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  warehouse varchar(140),
  item_code varchar(140),
  reserved_qty numeric(21,9),
  actual_qty numeric(21,9),
  ordered_qty numeric(21,9),
  indented_qty numeric(21,9),
  planned_qty numeric(21,9),
  projected_qty numeric(21,9),
  reserved_qty_for_production numeric(21,9),
  reserved_qty_for_sub_contract numeric(21,9),
  stock_uom varchar(140),
  company varchar(140),
  valuation_rate numeric(21,9),
  stock_value numeric(21,9),
  reserved_qty_for_production_plan numeric(21,9),
  reserved_stock numeric(21,9)
);
CREATE INDEX ix_bin_warehouse ON "tabBin" (warehouse);

-- Company Restriction (child)
CREATE TABLE "tabCompany Restriction" (
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
CREATE INDEX ix_company_restriction_parent ON "tabCompany Restriction" (parent);

-- Customs Tariff Number (master)
CREATE TABLE "tabCustoms Tariff Number" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  tariff_number varchar(140),
  description varchar(140)
);

-- Delivery Note (transaction)
CREATE TABLE "tabDelivery Note" (
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
  amended_from varchar(140),
  company varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  is_return smallint,
  issue_credit_note smallint,
  return_against varchar(140),
  po_no text,
  po_date date,
  shipping_address_name varchar(140),
  shipping_address text,
  contact_person varchar(140),
  contact_display text,
  contact_mobile text,
  contact_email varchar(140),
  customer_address varchar(140),
  tax_id varchar(140),
  address_display text,
  company_address varchar(140),
  company_address_display text,
  currency varchar(140),
  conversion_rate numeric(21,9),
  selling_price_list varchar(140),
  price_list_currency varchar(140),
  plc_conversion_rate numeric(21,9),
  ignore_pricing_rule smallint,
  set_warehouse varchar(140),
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
  base_total_taxes_and_charges numeric(21,9),
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
  tc_name varchar(140),
  terms text,
  transporter varchar(140),
  driver varchar(140),
  lr_no varchar(140),
  vehicle_no varchar(140),
  transporter_name varchar(140),
  driver_name varchar(140),
  lr_date date,
  project varchar(140),
  per_billed numeric(21,9),
  customer_group varchar(140),
  territory varchar(140),
  letter_head varchar(140),
  select_print_heading varchar(140),
  language varchar(140),
  print_without_amount smallint,
  group_same_items smallint,
  status varchar(140),
  per_installed numeric(21,9),
  installation_status varchar(140),
  excise_page varchar(140),
  instructions text,
  auto_repeat varchar(140),
  sales_partner varchar(140),
  commission_rate numeric(21,9),
  total_commission numeric(21,9),
  is_internal_customer smallint,
  inter_company_reference varchar(140),
  per_returned numeric(21,9),
  set_target_warehouse varchar(140),
  represents_company varchar(140),
  disable_rounded_total smallint,
  dispatch_address_name varchar(140),
  dispatch_address text,
  amount_eligible_for_commission numeric(21,9),
  cost_center varchar(140),
  incoterm varchar(140),
  named_place varchar(140),
  delivery_trip varchar(140),
  utm_medium varchar(140),
  utm_content varchar(140),
  utm_source varchar(140),
  utm_campaign varchar(140),
  company_contact_person varchar(140),
  title varchar(140)
);
CREATE INDEX ix_delivery_note_customer ON "tabDelivery Note" (customer);
CREATE INDEX ix_delivery_note_posting_date ON "tabDelivery Note" (posting_date);
CREATE INDEX ix_delivery_note_return_against ON "tabDelivery Note" (return_against);
CREATE INDEX ix_delivery_note_status ON "tabDelivery Note" (status);

-- Delivery Note Item (child)
CREATE TABLE "tabDelivery Note Item" (
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
  weight_per_unit numeric(21,9),
  total_weight numeric(21,9),
  weight_uom varchar(140),
  warehouse varchar(140),
  target_warehouse varchar(140),
  quality_inspection varchar(140),
  actual_qty numeric(21,9),
  actual_batch_qty numeric(21,9),
  item_group varchar(140),
  brand varchar(140),
  item_tax_rate text,
  expense_account varchar(140),
  item_tax_template varchar(140),
  cost_center varchar(140),
  allow_zero_valuation_rate smallint,
  against_sales_order varchar(140),
  against_sales_invoice varchar(140),
  so_detail varchar(140),
  si_detail varchar(140),
  installed_qty numeric(21,9),
  billed_amt numeric(21,9),
  page_break smallint,
  project varchar(140),
  dn_detail varchar(140),
  returned_qty numeric(21,9),
  incoming_rate numeric(21,9),
  stock_uom_rate numeric(21,9),
  grant_commission smallint,
  pick_list_item varchar(140),
  purchase_order varchar(140),
  purchase_order_item varchar(140),
  has_item_scanned smallint,
  material_request varchar(140),
  material_request_item varchar(140),
  received_qty numeric(21,9),
  packed_qty numeric(21,9),
  serial_and_batch_bundle varchar(140),
  serial_no text,
  batch_no varchar(140),
  use_serial_batch_fields smallint,
  distributed_discount_amount numeric(21,9),
  company_total_stock numeric(21,9),
  against_pick_list varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_delivery_note_item_item_code ON "tabDelivery Note Item" (item_code);
CREATE INDEX ix_delivery_note_item_against_sales_order ON "tabDelivery Note Item" (against_sales_order);
CREATE INDEX ix_delivery_note_item_against_sales_invoice ON "tabDelivery Note Item" (against_sales_invoice);
CREATE INDEX ix_delivery_note_item_so_detail ON "tabDelivery Note Item" (so_detail);
CREATE INDEX ix_delivery_note_item_si_detail ON "tabDelivery Note Item" (si_detail);
CREATE INDEX ix_delivery_note_item_dn_detail ON "tabDelivery Note Item" (dn_detail);
CREATE INDEX ix_delivery_note_item_purchase_order ON "tabDelivery Note Item" (purchase_order);
CREATE INDEX ix_delivery_note_item_serial_and_batch_bundle ON "tabDelivery Note Item" (serial_and_batch_bundle);
CREATE INDEX ix_delivery_note_item_batch_no ON "tabDelivery Note Item" (batch_no);
CREATE INDEX ix_delivery_note_item_against_pick_list ON "tabDelivery Note Item" (against_pick_list);
CREATE INDEX ix_delivery_note_item_parent ON "tabDelivery Note Item" (parent);

-- Delivery Stop (child)
CREATE TABLE "tabDelivery Stop" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer varchar(140),
  address varchar(140),
  locked smallint,
  customer_address text,
  visited smallint,
  delivery_note varchar(140),
  grand_total numeric(21,9),
  contact varchar(140),
  email_sent_to varchar(140),
  customer_contact text,
  distance numeric(21,2),
  estimated_arrival timestamp,
  lat numeric(21,9),
  uom varchar(140),
  lng numeric(21,9),
  details text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_delivery_stop_parent ON "tabDelivery Stop" (parent);

-- Delivery Trip (transaction)
CREATE TABLE "tabDelivery Trip" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  company varchar(140),
  email_notification_sent smallint,
  driver varchar(140),
  driver_name varchar(140),
  total_distance numeric(21,2),
  uom varchar(140),
  vehicle varchar(140),
  departure_time timestamp,
  status varchar(140),
  amended_from varchar(140),
  driver_address varchar(140),
  driver_email varchar(140),
  employee varchar(140)
);

-- Inventory Dimension (master)
CREATE TABLE "tabInventory Dimension" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  reference_document varchar(140),
  dimension_name varchar(140),
  document_type varchar(140),
  istable smallint,
  condition text,
  apply_to_all_doctypes smallint,
  target_fieldname varchar(140),
  source_fieldname varchar(140),
  type_of_transaction varchar(140),
  fetch_from_parent varchar(140),
  mandatory_depends_on text,
  reqd smallint,
  validate_negative_stock smallint
);

-- Item (master)
CREATE TABLE "tabItem" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  item_code varchar(140),
  variant_of varchar(140),
  item_name varchar(140),
  item_group varchar(140),
  stock_uom varchar(140),
  disabled smallint,
  allow_alternative_item smallint,
  is_stock_item smallint,
  include_item_in_manufacturing smallint,
  opening_stock numeric(21,9),
  valuation_rate numeric(21,9),
  standard_rate numeric(21,9),
  is_fixed_asset smallint,
  asset_category varchar(140),
  asset_naming_series varchar(140),
  image text,
  brand varchar(140),
  description text,
  shelf_life_in_days integer,
  end_of_life date,
  default_material_request_type varchar(140),
  valuation_method varchar(140),
  warranty_period varchar(140),
  weight_per_unit numeric(21,9),
  weight_uom varchar(140),
  has_batch_no smallint,
  create_new_batch smallint,
  batch_number_series varchar(140),
  has_expiry_date smallint,
  retain_sample smallint,
  sample_quantity integer,
  has_serial_no smallint,
  serial_no_series varchar(140),
  has_variants smallint,
  variant_based_on varchar(140),
  is_purchase_item smallint,
  purchase_uom varchar(140),
  min_order_qty numeric(21,9),
  safety_stock numeric(21,9),
  lead_time_days integer,
  last_purchase_rate numeric(21,9),
  is_customer_provided_item smallint,
  delivered_by_supplier smallint,
  country_of_origin varchar(140),
  customs_tariff_number varchar(140),
  sales_uom varchar(140),
  is_sales_item smallint,
  max_discount numeric(21,9),
  enable_deferred_revenue smallint,
  no_of_months integer,
  enable_deferred_expense smallint,
  no_of_months_exp integer,
  inspection_required_before_purchase smallint,
  inspection_required_before_delivery smallint,
  quality_inspection_template varchar(140),
  default_bom varchar(140),
  is_sub_contracted_item smallint,
  customer_code text,
  total_projected_qty numeric(21,9),
  over_delivery_receipt_allowance numeric(21,9),
  over_billing_allowance numeric(21,9),
  auto_create_assets smallint,
  default_item_manufacturer varchar(140),
  default_manufacturer_part_no varchar(140),
  grant_commission smallint,
  is_grouped_asset smallint,
  allow_negative_stock smallint,
  production_capacity integer,
  purchase_tax_withholding_category varchar(140),
  sales_tax_withholding_category varchar(140),
  restrict_to_companies smallint
);
CREATE INDEX ix_item_variant_of ON "tabItem" (variant_of);
CREATE INDEX ix_item_item_name ON "tabItem" (item_name);
CREATE INDEX ix_item_item_group ON "tabItem" (item_group);
CREATE INDEX ix_item_disabled ON "tabItem" (disabled);

-- Item Alternative (master)
CREATE TABLE "tabItem Alternative" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  alternative_item_code varchar(140),
  two_way smallint,
  item_name varchar(140),
  alternative_item_name varchar(140)
);

-- Item Attribute (master)
CREATE TABLE "tabItem Attribute" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  attribute_name varchar(140),
  numeric_values smallint,
  from_range numeric(21,9),
  increment numeric(21,9),
  to_range numeric(21,9),
  disabled smallint
);

-- Item Attribute Value (child)
CREATE TABLE "tabItem Attribute Value" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  attribute_value varchar(140),
  abbr varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_attribute_value_abbr ON "tabItem Attribute Value" (abbr);
CREATE INDEX ix_item_attribute_value_parent ON "tabItem Attribute Value" (parent);

-- Item Barcode (child)
CREATE TABLE "tabItem Barcode" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  barcode_type varchar(140),
  uom varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_barcode_parent ON "tabItem Barcode" (parent);

-- Item Customer Detail (child)
CREATE TABLE "tabItem Customer Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  customer_name varchar(140),
  customer_group varchar(140),
  ref_code varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_customer_detail_customer_name ON "tabItem Customer Detail" (customer_name);
CREATE INDEX ix_item_customer_detail_ref_code ON "tabItem Customer Detail" (ref_code);
CREATE INDEX ix_item_customer_detail_parent ON "tabItem Customer Detail" (parent);

-- Item Default (child)
CREATE TABLE "tabItem Default" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  default_warehouse varchar(140),
  default_price_list varchar(140),
  default_discount_account varchar(140),
  default_inventory_account varchar(140),
  inventory_account_currency varchar(140),
  buying_cost_center varchar(140),
  default_supplier varchar(140),
  expense_account varchar(140),
  default_provisional_account varchar(140),
  purchase_expense_account varchar(140),
  purchase_expense_contra_account varchar(140),
  expenses_added_to_stock_account varchar(140),
  expenses_added_to_stock_contra_account varchar(140),
  purchase_price_variance_account varchar(140),
  manufacturing_variance_account varchar(140),
  selling_cost_center varchar(140),
  income_account varchar(140),
  default_cogs_account varchar(140),
  deferred_expense_account varchar(140),
  deferred_revenue_account varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_default_default_warehouse ON "tabItem Default" (default_warehouse);
CREATE INDEX ix_item_default_parent ON "tabItem Default" (parent);

-- Item Lead Time (master)
CREATE TABLE "tabItem Lead Time" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  buffer_time integer,
  no_of_shift integer,
  manufacturing_time_in_mins integer,
  total_workstation_time integer,
  daily_yield numeric(21,9),
  capacity_per_day integer,
  no_of_units_produced integer,
  purchase_time integer,
  shift_time_in_hours integer,
  no_of_workstations integer,
  stock_uom varchar(140)
);

-- Item Manufacturer (master)
CREATE TABLE "tabItem Manufacturer" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  item_code varchar(140),
  item_name varchar(140),
  description text,
  is_default smallint
);

-- Item Price (master)
CREATE TABLE "tabItem Price" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  uom varchar(140),
  packing_unit integer,
  item_name varchar(140),
  brand varchar(140),
  item_description text,
  price_list varchar(140),
  customer varchar(140),
  supplier varchar(140),
  buying smallint,
  selling smallint,
  currency varchar(140),
  price_list_rate numeric(21,9),
  valid_from date,
  lead_time_days integer,
  valid_upto date,
  note text,
  reference varchar(140),
  batch_no varchar(140)
);
CREATE INDEX ix_item_price_item_code ON "tabItem Price" (item_code);
CREATE INDEX ix_item_price_price_list ON "tabItem Price" (price_list);

-- Item Quality Inspection Parameter (child)
CREATE TABLE "tabItem Quality Inspection Parameter" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  specification varchar(140),
  value varchar(140),
  acceptance_formula text,
  formula_based_criteria smallint,
  min_value numeric(21,9),
  max_value numeric(21,9),
  numeric smallint,
  parameter_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_quality_inspection_parameter_parent ON "tabItem Quality Inspection Parameter" (parent);

-- Item Reorder (child)
CREATE TABLE "tabItem Reorder" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  warehouse_group varchar(140),
  warehouse varchar(140),
  warehouse_reorder_level numeric(21,9),
  warehouse_reorder_qty numeric(21,9),
  material_request_type varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_reorder_parent ON "tabItem Reorder" (parent);

-- Item Standard Cost (transaction)
CREATE TABLE "tabItem Standard Cost" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  item_code varchar(140),
  company varchar(140),
  standard_rate numeric(21,9),
  effective_date date,
  revaluation_entry varchar(140),
  amended_from varchar(140)
);
CREATE INDEX ix_item_standard_cost_item_code ON "tabItem Standard Cost" (item_code);
CREATE INDEX ix_item_standard_cost_company ON "tabItem Standard Cost" (company);
CREATE INDEX ix_item_standard_cost_amended_from ON "tabItem Standard Cost" (amended_from);

-- Item Supplier (child)
CREATE TABLE "tabItem Supplier" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  supplier varchar(140),
  supplier_part_no varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_supplier_parent ON "tabItem Supplier" (parent);

-- Item Tax (child)
CREATE TABLE "tabItem Tax" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_tax_template varchar(140),
  tax_category varchar(140),
  valid_from date,
  maximum_net_rate numeric(21,9),
  minimum_net_rate numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_tax_parent ON "tabItem Tax" (parent);

-- Item Variant (child)
CREATE TABLE "tabItem Variant" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_attribute varchar(140),
  item_attribute_value varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_variant_parent ON "tabItem Variant" (parent);

-- Item Variant Attribute (child)
CREATE TABLE "tabItem Variant Attribute" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  variant_of varchar(140),
  attribute varchar(140),
  attribute_value varchar(140),
  numeric_values smallint,
  from_range numeric(21,9),
  increment numeric(21,9),
  to_range numeric(21,9),
  disabled smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_variant_attribute_variant_of ON "tabItem Variant Attribute" (variant_of);
CREATE INDEX ix_item_variant_attribute_attribute ON "tabItem Variant Attribute" (attribute);
CREATE INDEX ix_item_variant_attribute_parent ON "tabItem Variant Attribute" (parent);

-- Item Website Specification (child)
CREATE TABLE "tabItem Website Specification" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  label varchar(140),
  description text,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_item_website_specification_parent ON "tabItem Website Specification" (parent);

-- Landed Cost Item (child)
CREATE TABLE "tabLanded Cost Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  description text,
  receipt_document_type varchar(140),
  receipt_document varchar(140),
  qty numeric(21,9),
  rate numeric(21,9),
  amount numeric(21,9),
  applicable_charges numeric(21,9),
  purchase_receipt_item varchar(140),
  cost_center varchar(140),
  is_fixed_asset smallint,
  stock_entry_item varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_landed_cost_item_parent ON "tabLanded Cost Item" (parent);

-- Landed Cost Purchase Receipt (child)
CREATE TABLE "tabLanded Cost Purchase Receipt" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  receipt_document_type varchar(140),
  receipt_document varchar(140),
  supplier varchar(140),
  posting_date date,
  grand_total numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_landed_cost_purchase_receipt_parent ON "tabLanded Cost Purchase Receipt" (parent);

-- Landed Cost Taxes and Charges (child)
CREATE TABLE "tabLanded Cost Taxes and Charges" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  description text,
  amount numeric(21,9),
  expense_account varchar(140),
  account_currency varchar(140),
  exchange_rate numeric(21,9),
  base_amount numeric(21,9),
  has_corrective_cost smallint,
  has_operating_cost smallint,
  operation_id varchar(140),
  qty numeric(21,9),
  operating_component varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_landed_cost_taxes_and_charges_parent ON "tabLanded Cost Taxes and Charges" (parent);

-- Landed Cost Vendor Invoice (child)
CREATE TABLE "tabLanded Cost Vendor Invoice" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  vendor_invoice varchar(140),
  amount numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_landed_cost_vendor_invoice_vendor_invoice ON "tabLanded Cost Vendor Invoice" (vendor_invoice);
CREATE INDEX ix_landed_cost_vendor_invoice_parent ON "tabLanded Cost Vendor Invoice" (parent);

-- Landed Cost Voucher (transaction)
CREATE TABLE "tabLanded Cost Voucher" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  company varchar(140),
  total_taxes_and_charges numeric(21,9),
  distribute_charges_based_on varchar(140),
  amended_from varchar(140),
  posting_date date,
  total_vendor_invoices_cost numeric(21,9)
);

-- Manufacturer (master)
CREATE TABLE "tabManufacturer" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  short_name varchar(140),
  full_name varchar(140),
  website varchar(140),
  country varchar(140),
  logo text,
  notes text
);

-- Material Request (transaction)
CREATE TABLE "tabMaterial Request" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  title varchar(140),
  material_request_type varchar(140),
  customer varchar(140),
  schedule_date date,
  company varchar(140),
  amended_from varchar(140),
  scan_barcode varchar(140),
  transaction_date date,
  status varchar(140),
  per_ordered numeric(21,9),
  per_received numeric(21,9),
  letter_head varchar(140),
  select_print_heading varchar(140),
  tc_name varchar(140),
  terms text,
  job_card varchar(140),
  set_warehouse varchar(140),
  set_from_warehouse varchar(140),
  transfer_status varchar(140),
  work_order varchar(140),
  buying_price_list varchar(140),
  auto_created_via_reorder smallint
);
CREATE INDEX ix_material_request_company ON "tabMaterial Request" (company);
CREATE INDEX ix_material_request_transaction_date ON "tabMaterial Request" (transaction_date);
CREATE INDEX ix_material_request_status ON "tabMaterial Request" (status);

-- Material Request Item (child)
CREATE TABLE "tabMaterial Request Item" (
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
  qty numeric(21,9),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_uom varchar(140),
  warehouse varchar(140),
  schedule_date date,
  rate numeric(21,9),
  amount numeric(21,9),
  stock_qty numeric(21,9),
  item_group varchar(140),
  brand varchar(140),
  lead_time_date date,
  sales_order varchar(140),
  sales_order_item varchar(140),
  project varchar(140),
  production_plan varchar(140),
  material_request_plan_item varchar(140),
  min_order_qty numeric(21,9),
  projected_qty numeric(21,9),
  actual_qty numeric(21,9),
  ordered_qty numeric(21,9),
  expense_account varchar(140),
  cost_center varchar(140),
  page_break smallint,
  received_qty numeric(21,9),
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  from_warehouse varchar(140),
  bom_no varchar(140),
  job_card_item varchar(140),
  wip_composite_asset varchar(140),
  price_list_rate numeric(21,9),
  reorder_level numeric(21,9),
  reorder_qty numeric(21,9),
  projected_on_hand numeric(21,9),
  picked_qty numeric(21,9),
  packed_item varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_material_request_item_item_code ON "tabMaterial Request Item" (item_code);
CREATE INDEX ix_material_request_item_item_name ON "tabMaterial Request Item" (item_name);
CREATE INDEX ix_material_request_item_item_group ON "tabMaterial Request Item" (item_group);
CREATE INDEX ix_material_request_item_sales_order_item ON "tabMaterial Request Item" (sales_order_item);
CREATE INDEX ix_material_request_item_packed_item ON "tabMaterial Request Item" (packed_item);
CREATE INDEX ix_material_request_item_parent ON "tabMaterial Request Item" (parent);

-- Packed Item (child)
CREATE TABLE "tabPacked Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  parent_item varchar(140),
  item_code varchar(140),
  product_bundle varchar(140),
  item_name varchar(140),
  description text,
  warehouse varchar(140),
  target_warehouse varchar(140),
  qty numeric(21,9),
  serial_no text,
  batch_no varchar(140),
  actual_qty numeric(21,9),
  projected_qty numeric(21,9),
  uom varchar(140),
  page_break smallint,
  prevdoc_doctype varchar(140),
  parent_detail_docname varchar(140),
  actual_batch_qty numeric(21,9),
  incoming_rate numeric(21,9),
  conversion_factor numeric(21,9),
  rate numeric(21,9),
  ordered_qty numeric(21,9),
  picked_qty numeric(21,9),
  packed_qty numeric(21,9),
  serial_and_batch_bundle varchar(140),
  use_serial_batch_fields smallint,
  delivered_by_supplier smallint,
  requested_qty numeric(21,9),
  reserve_stock smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_packed_item_parent_detail_docname ON "tabPacked Item" (parent_detail_docname);
CREATE INDEX ix_packed_item_parent ON "tabPacked Item" (parent);

-- Packing Slip (transaction)
CREATE TABLE "tabPacking Slip" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  delivery_note varchar(140),
  naming_series varchar(140),
  from_case_no integer,
  to_case_no integer,
  net_weight_pkg numeric(21,9),
  net_weight_uom varchar(140),
  gross_weight_pkg numeric(21,9),
  gross_weight_uom varchar(140),
  letter_head varchar(140),
  amended_from varchar(140)
);

-- Packing Slip Item (child)
CREATE TABLE "tabPacking Slip Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  batch_no varchar(140),
  description text,
  qty numeric(21,9),
  net_weight numeric(21,9),
  stock_uom varchar(140),
  weight_uom varchar(140),
  page_break smallint,
  dn_detail varchar(140),
  pi_detail varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_packing_slip_item_parent ON "tabPacking Slip Item" (parent);

-- Pick List (transaction)
CREATE TABLE "tabPick List" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  parent_warehouse varchar(140),
  customer varchar(140),
  work_order varchar(140),
  for_qty numeric(21,9),
  amended_from varchar(140),
  purpose varchar(140),
  material_request varchar(140),
  naming_series varchar(140),
  group_same_items smallint,
  scan_barcode varchar(140),
  scan_mode smallint,
  prompt_qty smallint,
  customer_name varchar(140),
  status varchar(140),
  consider_rejected_warehouses smallint,
  pick_manually smallint,
  ignore_pricing_rule smallint,
  delivery_status varchar(140),
  per_delivered numeric(21,9)
);
CREATE INDEX ix_pick_list_status ON "tabPick List" (status);

-- Pick List Item (child)
CREATE TABLE "tabPick List Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  qty numeric(21,9),
  picked_qty numeric(21,9),
  warehouse varchar(140),
  item_name varchar(140),
  description text,
  serial_no text,
  batch_no varchar(140),
  stock_uom varchar(140),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_qty numeric(21,9),
  item_code varchar(140),
  sales_order varchar(140),
  sales_order_item varchar(140),
  material_request varchar(140),
  material_request_item varchar(140),
  item_group varchar(140),
  product_bundle_item varchar(140),
  serial_and_batch_bundle varchar(140),
  stock_reserved_qty numeric(21,9),
  use_serial_batch_fields smallint,
  delivered_qty numeric(21,9),
  transferred_qty numeric(21,9),
  actual_qty numeric(21,9),
  company_total_stock numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_pick_list_item_batch_no ON "tabPick List Item" (batch_no);
CREATE INDEX ix_pick_list_item_item_code ON "tabPick List Item" (item_code);
CREATE INDEX ix_pick_list_item_material_request ON "tabPick List Item" (material_request);
CREATE INDEX ix_pick_list_item_serial_and_batch_bundle ON "tabPick List Item" (serial_and_batch_bundle);
CREATE INDEX ix_pick_list_item_parent ON "tabPick List Item" (parent);

-- Price List (master)
CREATE TABLE "tabPrice List" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  enabled smallint,
  price_list_name varchar(140),
  currency varchar(140),
  buying smallint,
  selling smallint,
  price_not_uom_dependent smallint
);

-- Price List Country (child)
CREATE TABLE "tabPrice List Country" (
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
CREATE INDEX ix_price_list_country_parent ON "tabPrice List Country" (parent);

-- Purchase Receipt (transaction)
CREATE TABLE "tabPurchase Receipt" (
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
  supplier_delivery_note varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  company varchar(140),
  is_return smallint,
  return_against varchar(140),
  supplier_address varchar(140),
  contact_person varchar(140),
  address_display text,
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
  supplier_warehouse varchar(140),
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
  base_in_words varchar(140),
  base_rounded_total numeric(21,9),
  grand_total numeric(21,9),
  rounding_adjustment numeric(21,9),
  rounded_total numeric(21,9),
  in_words varchar(140),
  disable_rounded_total smallint,
  tc_name varchar(140),
  terms text,
  status varchar(140),
  amended_from varchar(140),
  range varchar(140),
  project varchar(140),
  per_billed numeric(21,9),
  auto_repeat varchar(140),
  letter_head varchar(140),
  select_print_heading varchar(140),
  language varchar(140),
  group_same_items smallint,
  instructions text,
  remarks text,
  transporter_name varchar(140),
  lr_no varchar(140),
  lr_date date,
  is_internal_supplier smallint,
  inter_company_reference varchar(140),
  scan_barcode varchar(140),
  billing_address varchar(140),
  billing_address_display text,
  apply_putaway_rule smallint,
  per_returned numeric(21,9),
  set_from_warehouse varchar(140),
  represents_company varchar(140),
  cost_center varchar(140),
  incoterm varchar(140),
  named_place varchar(140),
  subcontracting_receipt varchar(140),
  dispatch_address varchar(140),
  dispatch_address_display text
);
CREATE INDEX ix_purchase_receipt_supplier ON "tabPurchase Receipt" (supplier);
CREATE INDEX ix_purchase_receipt_posting_date ON "tabPurchase Receipt" (posting_date);
CREATE INDEX ix_purchase_receipt_return_against ON "tabPurchase Receipt" (return_against);
CREATE INDEX ix_purchase_receipt_status ON "tabPurchase Receipt" (status);
CREATE INDEX ix_purchase_receipt_inter_company_reference ON "tabPurchase Receipt" (inter_company_reference);
CREATE INDEX ix_purchase_receipt_subcontracting_receipt ON "tabPurchase Receipt" (subcontracting_receipt);

-- Purchase Receipt Item (child)
CREATE TABLE "tabPurchase Receipt Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  item_code varchar(140),
  supplier_part_no varchar(140),
  item_name varchar(140),
  description text,
  image text,
  received_qty numeric(21,9),
  qty numeric(21,9),
  rejected_qty numeric(21,9),
  uom varchar(140),
  stock_uom varchar(140),
  conversion_factor numeric(21,9),
  retain_sample smallint,
  sample_quantity integer,
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
  is_fixed_asset smallint,
  purchase_order varchar(140),
  schedule_date date,
  stock_qty numeric(21,9),
  item_tax_template varchar(140),
  project varchar(140),
  cost_center varchar(140),
  purchase_order_item varchar(140),
  allow_zero_valuation_rate smallint,
  billed_amt numeric(21,9),
  landed_cost_voucher_amount numeric(21,9),
  brand varchar(140),
  item_group varchar(140),
  rm_supp_cost numeric(21,9),
  item_tax_amount numeric(21,9),
  valuation_rate numeric(21,9),
  item_tax_rate text,
  page_break smallint,
  material_request varchar(140),
  material_request_item varchar(140),
  expense_account varchar(140),
  manufacturer varchar(140),
  manufacturer_part_no varchar(140),
  asset_location varchar(140),
  asset_category varchar(140),
  from_warehouse varchar(140),
  purchase_receipt_item varchar(140),
  putaway_rule varchar(140),
  returned_qty numeric(21,9),
  received_stock_qty numeric(21,9),
  stock_uom_rate numeric(21,9),
  delivery_note_item varchar(140),
  margin_type varchar(140),
  margin_rate_or_amount numeric(21,9),
  rate_with_margin numeric(21,9),
  base_rate_with_margin numeric(21,9),
  purchase_invoice varchar(140),
  purchase_invoice_item varchar(140),
  product_bundle varchar(140),
  provisional_expense_account varchar(140),
  has_item_scanned smallint,
  serial_and_batch_bundle varchar(140),
  serial_no text,
  rejected_serial_no text,
  batch_no varchar(140),
  rejected_serial_and_batch_bundle varchar(140),
  wip_composite_asset varchar(140),
  sales_order varchar(140),
  sales_order_item varchar(140),
  subcontracting_receipt_item varchar(140),
  use_serial_batch_fields smallint,
  return_qty_from_rejected_warehouse smallint,
  sales_incoming_rate numeric(21,9),
  distributed_discount_amount numeric(21,9),
  amount_difference_with_purchase_invoice numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_purchase_receipt_item_item_code ON "tabPurchase Receipt Item" (item_code);
CREATE INDEX ix_purchase_receipt_item_purchase_order ON "tabPurchase Receipt Item" (purchase_order);
CREATE INDEX ix_purchase_receipt_item_purchase_order_item ON "tabPurchase Receipt Item" (purchase_order_item);
CREATE INDEX ix_purchase_receipt_item_material_request_item ON "tabPurchase Receipt Item" (material_request_item);
CREATE INDEX ix_purchase_receipt_item_purchase_receipt_item ON "tabPurchase Receipt Item" (purchase_receipt_item);
CREATE INDEX ix_purchase_receipt_item_delivery_note_item ON "tabPurchase Receipt Item" (delivery_note_item);
CREATE INDEX ix_purchase_receipt_item_purchase_invoice_item ON "tabPurchase Receipt Item" (purchase_invoice_item);
CREATE INDEX ix_purchase_receipt_item_serial_and_batch_bundle ON "tabPurchase Receipt Item" (serial_and_batch_bundle);
CREATE INDEX ix_purchase_receipt_item_batch_no ON "tabPurchase Receipt Item" (batch_no);
CREATE INDEX ix_purchase_receipt_item_rejected_serial_and_batch_bundle ON "tabPurchase Receipt Item" (rejected_serial_and_batch_bundle);
CREATE INDEX ix_purchase_receipt_item_sales_order ON "tabPurchase Receipt Item" (sales_order);
CREATE INDEX ix_purchase_receipt_item_sales_order_item ON "tabPurchase Receipt Item" (sales_order_item);
CREATE INDEX ix_purchase_receipt_item_subcontracting_receipt_item ON "tabPurchase Receipt Item" (subcontracting_receipt_item);
CREATE INDEX ix_purchase_receipt_item_parent ON "tabPurchase Receipt Item" (parent);

-- Putaway Rule (master)
CREATE TABLE "tabPutaway Rule" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  item_name varchar(140),
  warehouse varchar(140),
  capacity numeric(21,9),
  stock_uom varchar(140),
  priority integer,
  company varchar(140),
  disable smallint,
  uom varchar(140),
  stock_capacity numeric(21,9),
  conversion_factor numeric(21,9)
);

-- Quality Inspection (transaction)
CREATE TABLE "tabQuality Inspection" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  report_date date,
  inspection_type varchar(140),
  reference_type varchar(140),
  reference_name varchar(140),
  item_code varchar(140),
  item_serial_no varchar(140),
  batch_no varchar(140),
  sample_size numeric(21,9),
  item_name varchar(140),
  description text,
  inspected_by varchar(140),
  verified_by varchar(140),
  bom_no varchar(140),
  remarks text,
  amended_from varchar(140),
  quality_inspection_template varchar(140),
  status varchar(140),
  manual_inspection smallint,
  child_row_reference varchar(140),
  company varchar(140),
  letter_head varchar(140)
);
CREATE INDEX ix_quality_inspection_report_date ON "tabQuality Inspection" (report_date);
CREATE INDEX ix_quality_inspection_item_code ON "tabQuality Inspection" (item_code);

-- Quality Inspection Parameter (master)
CREATE TABLE "tabQuality Inspection Parameter" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  parameter varchar(140),
  description text,
  parameter_group varchar(140)
);

-- Quality Inspection Parameter Group (master)
CREATE TABLE "tabQuality Inspection Parameter Group" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  group_name varchar(140)
);

-- Quality Inspection Reading (child)
CREATE TABLE "tabQuality Inspection Reading" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  specification varchar(140),
  value varchar(140),
  reading_1 varchar(140),
  reading_2 varchar(140),
  reading_3 varchar(140),
  reading_4 varchar(140),
  reading_5 varchar(140),
  reading_6 varchar(140),
  reading_7 varchar(140),
  reading_8 varchar(140),
  reading_9 varchar(140),
  reading_10 varchar(140),
  status varchar(140),
  acceptance_formula text,
  formula_based_criteria smallint,
  min_value numeric(21,9),
  max_value numeric(21,9),
  reading_value varchar(140),
  manual_inspection smallint,
  numeric smallint,
  parameter_group varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_quality_inspection_reading_parent ON "tabQuality Inspection Reading" (parent);

-- Quality Inspection Template (master)
CREATE TABLE "tabQuality Inspection Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  quality_inspection_template_name varchar(140)
);

-- Repost Item Valuation (transaction)
CREATE TABLE "tabRepost Item Valuation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  warehouse varchar(140),
  posting_date date,
  posting_time time(6),
  status varchar(140),
  amended_from varchar(140),
  error_log text,
  company varchar(140),
  voucher_type varchar(140),
  voucher_no varchar(140),
  based_on varchar(140),
  allow_negative_stock smallint,
  via_landed_cost_voucher smallint,
  allow_zero_rate smallint,
  items_to_be_repost text,
  current_index integer,
  gl_reposting_index integer,
  total_reposting_count integer,
  recreate_stock_ledgers smallint,
  reposting_reference varchar(140),
  repost_only_accounting_ledgers smallint,
  total_vouchers integer,
  vouchers_posted integer,
  reposting_data_file text,
  recalculate_valuation_rate smallint
);
CREATE INDEX ix_repost_item_valuation_reposting_reference ON "tabRepost Item Valuation" (reposting_reference);

-- Serial No (master)
CREATE TABLE "tabSerial No" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  serial_no varchar(140),
  item_code varchar(140),
  item_name varchar(140),
  description text,
  item_group varchar(140),
  brand varchar(140),
  asset varchar(140),
  asset_status varchar(140),
  location varchar(140),
  employee varchar(140),
  maintenance_status varchar(140),
  warranty_period integer,
  warranty_expiry_date date,
  amc_expiry_date date,
  company varchar(140),
  work_order varchar(140),
  warehouse varchar(140),
  batch_no varchar(140),
  purchase_rate numeric(21,9),
  status varchar(140),
  customer varchar(140),
  reference_doctype varchar(140),
  reference_name varchar(140),
  posting_date date
);
CREATE INDEX ix_serial_no_maintenance_status ON "tabSerial No" (maintenance_status);
CREATE INDEX ix_serial_no_company ON "tabSerial No" (company);

-- Serial and Batch Bundle (transaction)
CREATE TABLE "tabSerial and Batch Bundle" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  company varchar(140),
  item_group varchar(140),
  has_serial_no smallint,
  item_code varchar(140),
  item_name varchar(140),
  has_batch_no smallint,
  voucher_type varchar(140),
  voucher_no varchar(140),
  is_cancelled smallint,
  amended_from varchar(140),
  avg_rate numeric(21,9),
  total_amount numeric(21,9),
  total_qty numeric(21,9),
  warehouse varchar(140),
  type_of_transaction varchar(140),
  is_rejected smallint,
  voucher_detail_no varchar(140),
  returned_against varchar(140),
  naming_series varchar(140),
  is_packed smallint,
  posting_datetime timestamp
);
CREATE INDEX ix_serial_and_batch_bundle_voucher_type ON "tabSerial and Batch Bundle" (voucher_type);
CREATE INDEX ix_serial_and_batch_bundle_voucher_detail_no ON "tabSerial and Batch Bundle" (voucher_detail_no);

-- Serial and Batch Entry (child)
CREATE TABLE "tabSerial and Batch Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  serial_no varchar(140),
  batch_no varchar(140),
  qty numeric(21,9),
  warehouse varchar(140),
  incoming_rate numeric(21,9),
  outgoing_rate numeric(21,9),
  stock_value_difference numeric(21,9),
  is_outward smallint,
  stock_queue text,
  delivered_qty numeric(21,9),
  reference_for_reservation varchar(140),
  posting_datetime timestamp,
  voucher_type varchar(140),
  voucher_no varchar(140),
  voucher_detail_no varchar(140),
  type_of_transaction varchar(140),
  is_cancelled smallint,
  item_code varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_serial_and_batch_entry_batch_no ON "tabSerial and Batch Entry" (batch_no);
CREATE INDEX ix_serial_and_batch_entry_voucher_detail_no ON "tabSerial and Batch Entry" (voucher_detail_no);
CREATE INDEX ix_serial_and_batch_entry_parent ON "tabSerial and Batch Entry" (parent);

-- Shipment (transaction)
CREATE TABLE "tabShipment" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  pickup_from_type varchar(140),
  pickup_company varchar(140),
  pickup_customer varchar(140),
  pickup_supplier varchar(140),
  pickup varchar(140),
  pickup_address_name varchar(140),
  pickup_address text,
  pickup_contact_name varchar(140),
  pickup_contact_email varchar(140),
  pickup_contact text,
  delivery_to_type varchar(140),
  delivery_company varchar(140),
  delivery_customer varchar(140),
  delivery_supplier varchar(140),
  delivery_to varchar(140),
  delivery_address_name varchar(140),
  delivery_address text,
  delivery_contact_name varchar(140),
  delivery_contact_email varchar(140),
  delivery_contact text,
  parcel_template varchar(140),
  pallets varchar(140),
  value_of_goods numeric(21,2),
  pickup_date date,
  pickup_from time(6),
  pickup_to time(6),
  shipment_type varchar(140),
  pickup_type varchar(140),
  description_of_content text,
  service_provider varchar(140),
  shipment_id varchar(140),
  shipment_amount numeric(21,2),
  status varchar(140),
  tracking_url text,
  carrier varchar(140),
  carrier_service varchar(140),
  awb_number varchar(140),
  tracking_status varchar(140),
  tracking_status_info varchar(140),
  amended_from varchar(140),
  incoterm varchar(140),
  pickup_contact_person varchar(140),
  total_weight numeric(21,9)
);

-- Shipment Delivery Note (child)
CREATE TABLE "tabShipment Delivery Note" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  delivery_note varchar(140),
  grand_total numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_shipment_delivery_note_parent ON "tabShipment Delivery Note" (parent);

-- Shipment Parcel (child)
CREATE TABLE "tabShipment Parcel" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  length numeric(21,9),
  width numeric(21,9),
  height numeric(21,9),
  weight numeric(21,1),
  count integer,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_shipment_parcel_parent ON "tabShipment Parcel" (parent);

-- Shipment Parcel Template (master)
CREATE TABLE "tabShipment Parcel Template" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  length numeric(21,9),
  width numeric(21,9),
  height numeric(21,9),
  weight numeric(21,1),
  parcel_template_name varchar(140)
);

-- Stock Closing Balance (master)
CREATE TABLE "tabStock Closing Balance" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  warehouse varchar(140),
  posting_date date,
  posting_time time(6),
  posting_datetime timestamp,
  actual_qty numeric(21,9),
  valuation_rate numeric(21,9),
  stock_value numeric(21,9),
  company varchar(140),
  stock_uom varchar(140),
  stock_value_difference numeric(21,9),
  item_name varchar(140),
  item_group varchar(140),
  stock_closing_entry varchar(140),
  inventory_dimension_key text,
  batch_no varchar(140),
  fifo_queue text
);
CREATE INDEX ix_stock_closing_balance_item_code ON "tabStock Closing Balance" (item_code);
CREATE INDEX ix_stock_closing_balance_warehouse ON "tabStock Closing Balance" (warehouse);
CREATE INDEX ix_stock_closing_balance_posting_date ON "tabStock Closing Balance" (posting_date);
CREATE INDEX ix_stock_closing_balance_posting_datetime ON "tabStock Closing Balance" (posting_datetime);
CREATE INDEX ix_stock_closing_balance_company ON "tabStock Closing Balance" (company);
CREATE INDEX ix_stock_closing_balance_stock_closing_entry ON "tabStock Closing Balance" (stock_closing_entry);
CREATE INDEX ix_stock_closing_balance_batch_no ON "tabStock Closing Balance" (batch_no);

-- Stock Closing Entry (transaction)
CREATE TABLE "tabStock Closing Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  company varchar(140),
  status varchar(140),
  from_date date,
  to_date date,
  amended_from varchar(140)
);
CREATE INDEX ix_stock_closing_entry_company ON "tabStock Closing Entry" (company);
CREATE INDEX ix_stock_closing_entry_amended_from ON "tabStock Closing Entry" (amended_from);

-- Stock Entry (transaction)
CREATE TABLE "tabStock Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  stock_entry_type varchar(140),
  outgoing_stock_entry varchar(140),
  source_stock_entry varchar(140),
  purpose varchar(140),
  company varchar(140),
  work_order varchar(140),
  purchase_order varchar(140),
  subcontracting_order varchar(140),
  delivery_note_no varchar(140),
  sales_invoice_no varchar(140),
  purchase_receipt_no varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  inspection_required smallint,
  from_bom smallint,
  bom_no varchar(140),
  fg_completed_qty numeric(21,9),
  use_multi_level_bom smallint,
  from_warehouse varchar(140),
  source_warehouse_address varchar(140),
  source_address_display text,
  to_warehouse varchar(140),
  target_warehouse_address varchar(140),
  target_address_display text,
  scan_barcode varchar(140),
  total_incoming_value numeric(21,9),
  total_outgoing_value numeric(21,9),
  value_difference numeric(21,9),
  total_additional_costs numeric(21,9),
  supplier varchar(140),
  supplier_name varchar(140),
  supplier_address varchar(140),
  address_display text,
  select_print_heading varchar(140),
  letter_head varchar(140),
  is_opening varchar(140),
  project varchar(140),
  remarks text,
  per_transferred numeric(21,9),
  total_amount numeric(21,9),
  job_card varchar(140),
  amended_from varchar(140),
  credit_note varchar(140),
  pick_list varchar(140),
  add_to_transit smallint,
  apply_putaway_rule smallint,
  is_return smallint,
  process_loss_qty numeric(21,9),
  process_loss_percentage numeric(21,9),
  asset_repair varchar(140),
  is_additional_transfer_entry smallint,
  subcontracting_inward_order varchar(140),
  cost_center varchar(140)
);
CREATE INDEX ix_stock_entry_stock_entry_type ON "tabStock Entry" (stock_entry_type);
CREATE INDEX ix_stock_entry_purpose ON "tabStock Entry" (purpose);
CREATE INDEX ix_stock_entry_work_order ON "tabStock Entry" (work_order);
CREATE INDEX ix_stock_entry_delivery_note_no ON "tabStock Entry" (delivery_note_no);
CREATE INDEX ix_stock_entry_purchase_receipt_no ON "tabStock Entry" (purchase_receipt_no);
CREATE INDEX ix_stock_entry_posting_date ON "tabStock Entry" (posting_date);
CREATE INDEX ix_stock_entry_job_card ON "tabStock Entry" (job_card);
CREATE INDEX ix_stock_entry_pick_list ON "tabStock Entry" (pick_list);

-- Stock Entry Detail (child)
CREATE TABLE "tabStock Entry Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  s_warehouse varchar(140),
  t_warehouse varchar(140),
  item_code varchar(140),
  item_name varchar(140),
  description text,
  image text,
  qty numeric(21,9),
  basic_rate numeric(21,9),
  basic_amount numeric(21,9),
  additional_cost numeric(21,9),
  amount numeric(21,9),
  valuation_rate numeric(21,9),
  uom varchar(140),
  conversion_factor numeric(21,9),
  stock_uom varchar(140),
  transfer_qty numeric(21,9),
  retain_sample smallint,
  sample_quantity integer,
  serial_no text,
  batch_no varchar(140),
  quality_inspection varchar(140),
  expense_account varchar(140),
  cost_center varchar(140),
  allow_zero_valuation_rate smallint,
  actual_qty numeric(21,9),
  bom_no varchar(140),
  allow_alternative_item smallint,
  material_request varchar(140),
  material_request_item varchar(140),
  pick_list_item varchar(140),
  original_item varchar(140),
  subcontracted_item varchar(140),
  against_stock_entry varchar(140),
  ste_detail varchar(140),
  transferred_qty numeric(21,9),
  item_group varchar(140),
  reference_purchase_receipt varchar(140),
  project varchar(140),
  po_detail varchar(140),
  sco_rm_detail varchar(140),
  set_basic_rate_manually smallint,
  putaway_rule varchar(140),
  is_finished_item smallint,
  job_card_item varchar(140),
  has_item_scanned smallint,
  serial_and_batch_bundle varchar(140),
  use_serial_batch_fields smallint,
  landed_cost_voucher_amount numeric(21,9),
  customer_provided_item_cost numeric(21,9),
  scio_detail varchar(140),
  against_fg varchar(140),
  secondary_item_type varchar(140),
  bom_secondary_item varchar(140),
  is_legacy_scrap_item smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_stock_entry_detail_item_code ON "tabStock Entry Detail" (item_code);
CREATE INDEX ix_stock_entry_detail_actual_qty ON "tabStock Entry Detail" (actual_qty);
CREATE INDEX ix_stock_entry_detail_material_request ON "tabStock Entry Detail" (material_request);
CREATE INDEX ix_stock_entry_detail_against_stock_entry ON "tabStock Entry Detail" (against_stock_entry);
CREATE INDEX ix_stock_entry_detail_ste_detail ON "tabStock Entry Detail" (ste_detail);
CREATE INDEX ix_stock_entry_detail_reference_purchase_receipt ON "tabStock Entry Detail" (reference_purchase_receipt);
CREATE INDEX ix_stock_entry_detail_job_card_item ON "tabStock Entry Detail" (job_card_item);
CREATE INDEX ix_stock_entry_detail_serial_and_batch_bundle ON "tabStock Entry Detail" (serial_and_batch_bundle);
CREATE INDEX ix_stock_entry_detail_scio_detail ON "tabStock Entry Detail" (scio_detail);
CREATE INDEX ix_stock_entry_detail_parent ON "tabStock Entry Detail" (parent);

-- Stock Entry Type (master)
CREATE TABLE "tabStock Entry Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  purpose varchar(140),
  add_to_transit smallint,
  is_standard smallint
);

-- Stock Ledger Entry (transaction)
CREATE TABLE "tabStock Ledger Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  serial_no text,
  batch_no varchar(140),
  warehouse varchar(140),
  posting_date date,
  posting_time time(6),
  voucher_type varchar(140),
  voucher_no varchar(140),
  voucher_detail_no varchar(140),
  actual_qty numeric(21,9),
  incoming_rate numeric(21,9),
  outgoing_rate numeric(21,9),
  stock_uom varchar(140),
  qty_after_transaction numeric(21,9),
  valuation_rate numeric(21,9),
  stock_value numeric(21,9),
  stock_value_difference numeric(21,9),
  stock_queue text,
  project varchar(140),
  company varchar(140),
  fiscal_year varchar(140),
  is_cancelled smallint,
  to_rename smallint,
  dependant_sle_voucher_detail_no varchar(140),
  recalculate_rate smallint,
  serial_and_batch_bundle varchar(140),
  has_batch_no smallint,
  has_serial_no smallint,
  is_adjustment_entry smallint,
  auto_created_serial_and_batch_bundle smallint,
  posting_datetime timestamp
);
CREATE INDEX ix_stock_ledger_entry_batch_no ON "tabStock Ledger Entry" (batch_no);
CREATE INDEX ix_stock_ledger_entry_voucher_type ON "tabStock Ledger Entry" (voucher_type);
CREATE INDEX ix_stock_ledger_entry_voucher_detail_no ON "tabStock Ledger Entry" (voucher_detail_no);
CREATE INDEX ix_stock_ledger_entry_to_rename ON "tabStock Ledger Entry" (to_rename);
CREATE INDEX ix_stock_ledger_entry_serial_and_batch_bundle ON "tabStock Ledger Entry" (serial_and_batch_bundle);

-- Stock Reconciliation (transaction)
CREATE TABLE "tabStock Reconciliation" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  naming_series varchar(140),
  company varchar(140),
  purpose varchar(140),
  posting_date date,
  posting_time time(6),
  set_posting_time smallint,
  expense_account varchar(140),
  cost_center varchar(140),
  difference_amount numeric(21,9),
  amended_from varchar(140),
  scan_barcode varchar(140),
  scan_mode smallint,
  set_warehouse varchar(140)
);

-- Stock Reconciliation Item (child)
CREATE TABLE "tabStock Reconciliation Item" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  barcode varchar(140),
  item_code varchar(140),
  item_name varchar(140),
  warehouse varchar(140),
  qty numeric(21,9),
  stock_uom varchar(140),
  valuation_rate numeric(21,9),
  amount numeric(21,9),
  serial_no text,
  current_qty numeric(21,9),
  current_serial_no text,
  current_valuation_rate numeric(21,9),
  current_amount numeric(21,9),
  quantity_difference varchar(140),
  amount_difference numeric(21,9),
  batch_no varchar(140),
  allow_zero_valuation_rate smallint,
  has_item_scanned varchar(140),
  serial_and_batch_bundle varchar(140),
  current_serial_and_batch_bundle varchar(140),
  item_group varchar(140),
  use_serial_batch_fields smallint,
  reconcile_all_serial_batch smallint,
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_stock_reconciliation_item_batch_no ON "tabStock Reconciliation Item" (batch_no);
CREATE INDEX ix_stock_reconciliation_item_serial_and_batch_bundle ON "tabStock Reconciliation Item" (serial_and_batch_bundle);
CREATE INDEX ix_stock_reconciliation_item_parent ON "tabStock Reconciliation Item" (parent);

-- Stock Reservation Entry (transaction)
CREATE TABLE "tabStock Reservation Entry" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  item_code varchar(140),
  warehouse varchar(140),
  voucher_type varchar(140),
  voucher_no varchar(140),
  voucher_detail_no varchar(140),
  stock_uom varchar(140),
  project varchar(140),
  company varchar(140),
  reserved_qty numeric(21,9),
  status varchar(140),
  delivered_qty numeric(21,9),
  amended_from varchar(140),
  available_qty numeric(21,9),
  voucher_qty numeric(21,9),
  has_serial_no smallint,
  has_batch_no smallint,
  reservation_based_on varchar(140),
  from_voucher_type varchar(140),
  from_voucher_detail_no varchar(140),
  from_voucher_no varchar(140),
  consumed_qty numeric(21,9),
  transferred_qty numeric(21,9)
);
CREATE INDEX ix_stock_reservation_entry_item_code ON "tabStock Reservation Entry" (item_code);
CREATE INDEX ix_stock_reservation_entry_warehouse ON "tabStock Reservation Entry" (warehouse);
CREATE INDEX ix_stock_reservation_entry_voucher_no ON "tabStock Reservation Entry" (voucher_no);
CREATE INDEX ix_stock_reservation_entry_voucher_detail_no ON "tabStock Reservation Entry" (voucher_detail_no);
CREATE INDEX ix_stock_reservation_entry_project ON "tabStock Reservation Entry" (project);
CREATE INDEX ix_stock_reservation_entry_company ON "tabStock Reservation Entry" (company);
CREATE INDEX ix_stock_reservation_entry_from_voucher_no ON "tabStock Reservation Entry" (from_voucher_no);

-- UOM Category (master)
CREATE TABLE "tabUOM Category" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  category_name varchar(140)
);

-- UOM Conversion Detail (child)
CREATE TABLE "tabUOM Conversion Detail" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  uom varchar(140),
  conversion_factor numeric(21,9),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_uom_conversion_detail_parent ON "tabUOM Conversion Detail" (parent);

-- Variant Field (child)
CREATE TABLE "tabVariant Field" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  field_name varchar(140),
  parent varchar(140),
  parentfield varchar(140),
  parenttype varchar(140)
);
CREATE INDEX ix_variant_field_parent ON "tabVariant Field" (parent);

-- Warehouse (tree-master)
CREATE TABLE "tabWarehouse" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  warehouse_name varchar(140),
  is_group smallint,
  company varchar(140),
  disabled smallint,
  account varchar(140),
  email_id varchar(140),
  phone_no varchar(140),
  mobile_no varchar(140),
  address_line_1 varchar(140),
  address_line_2 varchar(140),
  city varchar(140),
  state varchar(140),
  pin varchar(140),
  parent_warehouse varchar(140),
  lft integer,
  rgt integer,
  old_parent varchar(140),
  warehouse_type varchar(140),
  default_in_transit_warehouse varchar(140),
  is_rejected_warehouse smallint,
  customer varchar(140)
);
CREATE INDEX ix_warehouse_company ON "tabWarehouse" (company);
CREATE INDEX ix_warehouse_parent_warehouse ON "tabWarehouse" (parent_warehouse);

-- Warehouse Type (master)
CREATE TABLE "tabWarehouse Type" (
  name varchar(140) NOT NULL PRIMARY KEY,
  creation timestamp,
  modified timestamp,
  modified_by varchar(140),
  owner varchar(140),
  docstatus smallint NOT NULL DEFAULT 0,
  idx integer NOT NULL DEFAULT 0,
  description text
);
