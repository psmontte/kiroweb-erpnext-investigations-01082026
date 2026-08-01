# Selling: relationship diagrams

### Selling: entity dependency graph

Child tables are collapsed into their parent document. Rounded nodes are external
masters owned by other ERPNext modules. `[[ ]]` = submittable transaction. Links to
framework masters (`User`, `File`, `Currency`, `Address`, ...) are omitted here - see
the module reference for the full column list.

```mermaid
flowchart LR
  subgraph SELLING["Selling"]
    CUSTOMER["Customer"]
    DELIVERY_SCHEDULE_ITEM["Delivery Schedule Item"]
    INDUSTRY_TYPE["Industry Type"]
    INSTALLATION_NOTE[["Installation Note"]]
    PARTY_SPECIFIC_ITEM["Party Specific Item"]
    PRODUCT_BUNDLE[["Product Bundle"]]
    PROFORMA_INVOICE[["Proforma Invoice"]]
    QUOTATION[["Quotation"]]
    SALES_ORDER[["Sales Order"]]
    SALES_PARTNER_TYPE["Sales Partner Type"]
  end
  ACCOUNT("Account<br/><i>Accounts</i>")
  BOM("BOM<br/><i>Manufacturing</i>")
  BANK_ACCOUNT("Bank Account<br/><i>Accounts</i>")
  BATCH("Batch<br/><i>Stock</i>")
  BLANKET_ORDER("Blanket Order<br/><i>Manufacturing</i>")
  BRAND("Brand<br/><i>Setup</i>")
  COMPANY("Company<br/><i>Setup</i>")
  COMPETITOR("Competitor<br/><i>CRM</i>")
  COST_CENTER("Cost Center<br/><i>Accounts</i>")
  COUPON_CODE("Coupon Code<br/><i>Accounts</i>")
  CUSTOMER_GROUP("Customer Group<br/><i>Setup</i>")
  INCOTERM("Incoterm<br/><i>Setup</i>")
  ITEM("Item<br/><i>Stock</i>")
  ITEM_GROUP("Item Group<br/><i>Setup</i>")
  ITEM_TAX_TEMPLATE("Item Tax Template<br/><i>Accounts</i>")
  LEAD("Lead<br/><i>CRM</i>")
  LOYALTY_PROGRAM("Loyalty Program<br/><i>Accounts</i>")
  MARKET_SEGMENT("Market Segment<br/><i>CRM</i>")
  MATERIAL_REQUEST("Material Request<br/><i>Stock</i>")
  MODE_OF_PAYMENT("Mode of Payment<br/><i>Accounts</i>")
  OPPORTUNITY("Opportunity<br/><i>CRM</i>")
  PAYMENT_TERM("Payment Term<br/><i>Accounts</i>")
  PAYMENT_TERMS_TEMPLATE("Payment Terms Template<br/><i>Accounts</i>")
  PRICE_LIST("Price List<br/><i>Stock</i>")
  PRICING_RULE("Pricing Rule<br/><i>Accounts</i>")
  PROJECT("Project<br/><i>Projects</i>")
  PROSPECT("Prospect<br/><i>CRM</i>")
  PURCHASE_ORDER("Purchase Order<br/><i>Buying</i>")
  QUOTATION_LOST_REASON("Quotation Lost Reason<br/><i>Setup</i>")
  SALES_PARTNER("Sales Partner<br/><i>Setup</i>")
  SALES_PERSON("Sales Person<br/><i>Setup</i>")
  SALES_TAXES_AND_CHARGES_TEMPLATE("Sales Taxes and Charges Template<br/><i>Accounts</i>")
  SERIAL_AND_BATCH_BUNDLE("Serial and Batch Bundle<br/><i>Stock</i>")
  SHIPPING_RULE("Shipping Rule<br/><i>Accounts</i>")
  SUPPLIER("Supplier<br/><i>Buying</i>")
  SUPPLIER_QUOTATION("Supplier Quotation<br/><i>Buying</i>")
  TAX_CATEGORY("Tax Category<br/><i>Accounts</i>")
  TAX_WITHHOLDING_CATEGORY("Tax Withholding Category<br/><i>Accounts</i>")
  TAX_WITHHOLDING_GROUP("Tax Withholding Group<br/><i>Accounts</i>")
  TERMS_AND_CONDITIONS("Terms and Conditions<br/><i>Setup</i>")
  TERRITORY("Territory<br/><i>Setup</i>")
  UOM("UOM<br/><i>Setup</i>")
  WAREHOUSE("Warehouse<br/><i>Stock</i>")
  CUSTOMER --> ACCOUNT
  CUSTOMER --> BANK_ACCOUNT
  CUSTOMER --> COMPANY
  CUSTOMER --> CUSTOMER_GROUP
  CUSTOMER --> INDUSTRY_TYPE
  CUSTOMER --> LEAD
  CUSTOMER --> LOYALTY_PROGRAM
  CUSTOMER --> MARKET_SEGMENT
  CUSTOMER --> OPPORTUNITY
  CUSTOMER --> PAYMENT_TERMS_TEMPLATE
  CUSTOMER --> PRICE_LIST
  CUSTOMER --> PROSPECT
  CUSTOMER --> SALES_PARTNER
  CUSTOMER --> SALES_PERSON
  CUSTOMER --> TAX_CATEGORY
  CUSTOMER --> TAX_WITHHOLDING_CATEGORY
  CUSTOMER --> TAX_WITHHOLDING_GROUP
  CUSTOMER --> TERRITORY
  DELIVERY_SCHEDULE_ITEM --> ITEM
  DELIVERY_SCHEDULE_ITEM --> SALES_ORDER
  DELIVERY_SCHEDULE_ITEM --> UOM
  DELIVERY_SCHEDULE_ITEM --> WAREHOUSE
  INSTALLATION_NOTE --> COMPANY
  INSTALLATION_NOTE --> CUSTOMER
  INSTALLATION_NOTE --> CUSTOMER_GROUP
  INSTALLATION_NOTE --> ITEM
  INSTALLATION_NOTE --> PROJECT
  INSTALLATION_NOTE --> SERIAL_AND_BATCH_BUNDLE
  INSTALLATION_NOTE --> TERRITORY
  PRODUCT_BUNDLE --> ITEM
  PRODUCT_BUNDLE --> UOM
  PROFORMA_INVOICE --> COMPANY
  PROFORMA_INVOICE --> CUSTOMER
  PROFORMA_INVOICE --> ITEM
  PROFORMA_INVOICE --> SALES_ORDER
  PROFORMA_INVOICE --> UOM
  QUOTATION --> ACCOUNT
  QUOTATION --> BATCH
  QUOTATION --> BLANKET_ORDER
  QUOTATION --> BRAND
  QUOTATION --> COMPANY
  QUOTATION --> COMPETITOR
  QUOTATION --> COST_CENTER
  QUOTATION --> COUPON_CODE
  QUOTATION --> CUSTOMER_GROUP
  QUOTATION --> INCOTERM
  QUOTATION --> ITEM
  QUOTATION --> ITEM_GROUP
  QUOTATION --> ITEM_TAX_TEMPLATE
  QUOTATION --> MODE_OF_PAYMENT
  QUOTATION --> OPPORTUNITY
  QUOTATION --> PAYMENT_TERM
  QUOTATION --> PAYMENT_TERMS_TEMPLATE
  QUOTATION --> PRICE_LIST
  QUOTATION --> PRICING_RULE
  QUOTATION --> PRODUCT_BUNDLE
  QUOTATION --> PROJECT
  QUOTATION --> QUOTATION_LOST_REASON
  QUOTATION --> SALES_PARTNER
  QUOTATION --> SALES_TAXES_AND_CHARGES_TEMPLATE
  QUOTATION --> SERIAL_AND_BATCH_BUNDLE
  QUOTATION --> SHIPPING_RULE
  QUOTATION --> SUPPLIER_QUOTATION
  QUOTATION --> TAX_CATEGORY
  QUOTATION --> TERMS_AND_CONDITIONS
  QUOTATION --> TERRITORY
  QUOTATION --> UOM
  QUOTATION --> WAREHOUSE
  SALES_ORDER --> ACCOUNT
  SALES_ORDER --> BOM
  SALES_ORDER --> BATCH
  SALES_ORDER --> BLANKET_ORDER
  SALES_ORDER --> BRAND
  SALES_ORDER --> COMPANY
  SALES_ORDER --> COST_CENTER
  SALES_ORDER --> COUPON_CODE
  SALES_ORDER --> CUSTOMER
  SALES_ORDER --> CUSTOMER_GROUP
  SALES_ORDER --> INCOTERM
  SALES_ORDER --> ITEM
  SALES_ORDER --> ITEM_GROUP
  SALES_ORDER --> ITEM_TAX_TEMPLATE
  SALES_ORDER --> MATERIAL_REQUEST
  SALES_ORDER --> MODE_OF_PAYMENT
  SALES_ORDER --> PAYMENT_TERM
  SALES_ORDER --> PAYMENT_TERMS_TEMPLATE
  SALES_ORDER --> PRICE_LIST
  SALES_ORDER --> PRICING_RULE
  SALES_ORDER --> PRODUCT_BUNDLE
  SALES_ORDER --> PROJECT
  SALES_ORDER --> PURCHASE_ORDER
  SALES_ORDER --> QUOTATION
  SALES_ORDER --> SALES_PARTNER
  SALES_ORDER --> SALES_PERSON
  SALES_ORDER --> SALES_TAXES_AND_CHARGES_TEMPLATE
  SALES_ORDER --> SERIAL_AND_BATCH_BUNDLE
  SALES_ORDER --> SHIPPING_RULE
  SALES_ORDER --> SUPPLIER
  SALES_ORDER --> TAX_CATEGORY
  SALES_ORDER --> TERMS_AND_CONDITIONS
  SALES_ORDER --> TERRITORY
  SALES_ORDER --> UOM
  SALES_ORDER --> WAREHOUSE
```
