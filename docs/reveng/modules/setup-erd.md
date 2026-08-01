# Setup: relationship diagrams

### Setup: entity dependency graph

Child tables are collapsed into their parent document. Rounded nodes are external
masters owned by other ERPNext modules. `[[ ]]` = submittable transaction. Links to
framework masters (`User`, `File`, `Currency`, `Address`, ...) are omitted here - see
the module reference for the full column list.

```mermaid
flowchart LR
  subgraph SETUP["Setup"]
    AUTHORIZATION_RULE["Authorization Rule"]
    BRANCH["Branch"]
    BRAND["Brand"]
    COMPANY["Company"]
    CURRENCY_EXCHANGE["Currency Exchange"]
    CUSTOMER_GROUP["Customer Group"]
    DEPARTMENT["Department"]
    DESIGNATION["Designation"]
    DRIVER["Driver"]
    EMAIL_DIGEST["Email Digest"]
    EMPLOYEE["Employee"]
    EMPLOYEE_GROUP["Employee Group"]
    HOLIDAY_LIST["Holiday List"]
    INCOTERM["Incoterm"]
    ITEM_GROUP["Item Group"]
    PARTY_TYPE["Party Type"]
    QUOTATION_LOST_REASON["Quotation Lost Reason"]
    SALES_PARTNER["Sales Partner"]
    SALES_PERSON["Sales Person"]
    SUPPLIER_GROUP["Supplier Group"]
    TERMS_AND_CONDITIONS["Terms and Conditions"]
    TERRITORY["Territory"]
    TRANSACTION_DELETION_RECORD[["Transaction Deletion Record"]]
    UOM["UOM"]
    UOM_CONVERSION_FACTOR["UOM Conversion Factor"]
    VEHICLE["Vehicle"]
  end
  ACCOUNT("Account<br/><i>Accounts</i>")
  COST_CENTER("Cost Center<br/><i>Accounts</i>")
  FINANCE_BOOK("Finance Book<br/><i>Accounts</i>")
  FISCAL_YEAR("Fiscal Year<br/><i>Accounts</i>")
  ITEM_TAX_TEMPLATE("Item Tax Template<br/><i>Accounts</i>")
  MONTHLY_DISTRIBUTION("Monthly Distribution<br/><i>Accounts</i>")
  PAYMENT_TERMS_TEMPLATE("Payment Terms Template<br/><i>Accounts</i>")
  PRICE_LIST("Price List<br/><i>Stock</i>")
  SALES_PARTNER_TYPE("Sales Partner Type<br/><i>Selling</i>")
  SUPPLIER("Supplier<br/><i>Buying</i>")
  TAX_CATEGORY("Tax Category<br/><i>Accounts</i>")
  UOM_CATEGORY("UOM Category<br/><i>Stock</i>")
  WAREHOUSE("Warehouse<br/><i>Stock</i>")
  AUTHORIZATION_RULE --> COMPANY
  AUTHORIZATION_RULE --> DESIGNATION
  AUTHORIZATION_RULE --> EMPLOYEE
  BRAND --> ACCOUNT
  BRAND --> COMPANY
  BRAND --> COST_CENTER
  BRAND --> PRICE_LIST
  BRAND --> SUPPLIER
  BRAND --> WAREHOUSE
  COMPANY --> ACCOUNT
  COMPANY --> COST_CENTER
  COMPANY --> FINANCE_BOOK
  COMPANY --> HOLIDAY_LIST
  COMPANY --> PAYMENT_TERMS_TEMPLATE
  COMPANY --> TERMS_AND_CONDITIONS
  COMPANY --> WAREHOUSE
  CUSTOMER_GROUP --> ACCOUNT
  CUSTOMER_GROUP --> COMPANY
  CUSTOMER_GROUP --> PAYMENT_TERMS_TEMPLATE
  CUSTOMER_GROUP --> PRICE_LIST
  DEPARTMENT --> COMPANY
  DRIVER --> EMPLOYEE
  DRIVER --> SUPPLIER
  EMAIL_DIGEST --> COMPANY
  EMPLOYEE --> BRANCH
  EMPLOYEE --> COMPANY
  EMPLOYEE --> DEPARTMENT
  EMPLOYEE --> DESIGNATION
  EMPLOYEE --> HOLIDAY_LIST
  EMPLOYEE_GROUP --> EMPLOYEE
  ITEM_GROUP --> ACCOUNT
  ITEM_GROUP --> COMPANY
  ITEM_GROUP --> COST_CENTER
  ITEM_GROUP --> ITEM_TAX_TEMPLATE
  ITEM_GROUP --> PRICE_LIST
  ITEM_GROUP --> SUPPLIER
  ITEM_GROUP --> TAX_CATEGORY
  ITEM_GROUP --> WAREHOUSE
  SALES_PARTNER --> FISCAL_YEAR
  SALES_PARTNER --> ITEM_GROUP
  SALES_PARTNER --> MONTHLY_DISTRIBUTION
  SALES_PARTNER --> SALES_PARTNER_TYPE
  SALES_PARTNER --> TERRITORY
  SALES_PERSON --> DEPARTMENT
  SALES_PERSON --> EMPLOYEE
  SALES_PERSON --> FISCAL_YEAR
  SALES_PERSON --> ITEM_GROUP
  SALES_PERSON --> MONTHLY_DISTRIBUTION
  SUPPLIER_GROUP --> ACCOUNT
  SUPPLIER_GROUP --> COMPANY
  SUPPLIER_GROUP --> PAYMENT_TERMS_TEMPLATE
  TERRITORY --> FISCAL_YEAR
  TERRITORY --> ITEM_GROUP
  TERRITORY --> MONTHLY_DISTRIBUTION
  TERRITORY --> SALES_PERSON
  TRANSACTION_DELETION_RECORD --> COMPANY
  UOM --> UOM_CATEGORY
  UOM_CONVERSION_FACTOR --> UOM
  UOM_CONVERSION_FACTOR --> UOM_CATEGORY
  VEHICLE --> COMPANY
  VEHICLE --> EMPLOYEE
  VEHICLE --> UOM
```
