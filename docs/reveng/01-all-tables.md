# Full table catalog — every DocType in ERPNext

997 DocTypes. `kind` legend: **single** = Single (settings), **master** = Master, **tree-master** = Tree master (hierarchy), **transaction** = Transaction (submittable), **child** = Child / line-item table

## erpnext / Accounts (191)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Accounts Settings` | `tabAccounts Settings` | single | 64 | 5 | 1 | `-` |
| `Bank Clearance` | `tabBank Clearance` | single | 7 | 3 | 1 | `-` |
| `Bank Reconciliation Tool` | `tabBank Reconciliation Tool` | single | 10 | 3 | 0 | `-` |
| `Bisect Accounting Statements` | `tabBisect Accounting Statements` | single | 10 | 2 | 0 | `-` |
| `Chart of Accounts Importer` | `tabChart of Accounts Importer` | single | 2 | 1 | 0 | `-` |
| `Currency Exchange Settings` | `tabCurrency Exchange Settings` | single | 6 | 0 | 2 | `-` |
| `Ledger Health Monitor` | `tabLedger Health Monitor` | single | 4 | 0 | 1 | `-` |
| `Opening Invoice Creation Tool` | `tabOpening Invoice Creation Tool` | single | 5 | 3 | 1 | `-` |
| `POS Settings` | `tabPOS Settings` | single | 2 | 0 | 2 | `-` |
| `Payment Reconciliation` | `tabPayment Reconciliation` | single | 20 | 7 | 3 | `-` |
| `Pegged Currencies` | `tabPegged Currencies` | single | 0 | 0 | 1 | `-` |
| `Subscription Settings` | `tabSubscription Settings` | single | 3 | 0 | 0 | `-` |
| `Account Category` | `tabAccount Category` | master | 3 | 0 | 0 | `field:account_category_name` |
| `Accounting Dimension` | `tabAccounting Dimension` | master | 4 | 1 | 1 | `field:label` |
| `Accounting Dimension Filter` | `tabAccounting Dimension Filter` | master | 6 | 1 | 2 | `format:{accounting_dimension}-{#####}` |
| `Accounting Period` | `tabAccounting Period` | master | 6 | 2 | 1 | `field:period_name` |
| `Bank` | `tabBank` | master | 4 | 0 | 1 | `field:bank_name` |
| `Bank Account` | `tabBank Account` | master | 19 | 6 | 0 | `-` |
| `Bank Account Balance` | `tabBank Account Balance` | master | 4 | 2 | 0 | `-` |
| `Bank Account Subtype` | `tabBank Account Subtype` | master | 1 | 0 | 0 | `field:account_subtype` |
| `Bank Account Type` | `tabBank Account Type` | master | 1 | 0 | 0 | `field:account_type` |
| `Bank Statement Import` | `tabBank Statement Import` | master | 17 | 4 | 0 | `format:Bank Statement Import on {creation}` |
| `Bank Statement Import Log` | `tabBank Statement Import Log` | master | 18 | 2 | 1 | `hash` |
| `Bank Transaction Rule` | `tabBank Transaction Rule` | master | 12 | 3 | 2 | `field:rule_name` |
| `Bisect Nodes` | `tabBisect Nodes` | master | 9 | 3 | 0 | `autoincrement` |
| `Cheque Print Template` | `tabCheque Print Template` | master | 25 | 0 | 0 | `field:bank_name` |
| `Coupon Code` | `tabCoupon Code` | master | 12 | 3 | 0 | `field:coupon_name` |
| `Dunning Type` | `tabDunning Type` | master | 7 | 3 | 1 | `By script` |
| `Finance Book` | `tabFinance Book` | master | 1 | 0 | 0 | `field:finance_book_name` |
| `Financial Report Template` | `tabFinancial Report Template` | master | 4 | 1 | 1 | `field:template_name` |
| `Fiscal Year` | `tabFiscal Year` | master | 6 | 0 | 1 | `field:year` |
| `Item Tax Template` | `tabItem Tax Template` | master | 3 | 1 | 1 | `-` |
| `Journal Entry Template` | `tabJournal Entry Template` | master | 6 | 1 | 1 | `field:template_title` |
| `Ledger Health` | `tabLedger Health` | master | 5 | 0 | 0 | `autoincrement` |
| `Ledger Merge` | `tabLedger Merge` | master | 6 | 2 | 1 | `format:{account_name} merger on {creation}` |
| `Loyalty Point Entry` | `tabLoyalty Point Entry` | master | 12 | 5 | 0 | `-` |
| `Loyalty Program` | `tabLoyalty Program` | master | 13 | 6 | 1 | `field:loyalty_program_name` |
| `Mode of Payment` | `tabMode of Payment` | master | 3 | 0 | 1 | `field:mode_of_payment` |
| `Monthly Distribution` | `tabMonthly Distribution` | master | 2 | 1 | 1 | `field:distribution_id` |
| `POS Profile` | `tabPOS Profile` | master | 40 | 22 | 4 | `Prompt` |
| `Party Link` | `tabParty Link` | master | 4 | 2 | 0 | `ACC-PT-LNK-.###.` |
| `Payment Gateway Account` | `tabPayment Gateway Account` | master | 7 | 3 | 0 | `-` |
| `Payment Term` | `tabPayment Term` | master | 11 | 1 | 0 | `field:payment_term_name` |
| `Payment Terms Template` | `tabPayment Terms Template` | master | 2 | 0 | 1 | `field:template_name` |
| `Pricing Rule` | `tabPricing Rule` | master | 59 | 17 | 3 | `naming_series:` |
| `Process Payment Reconciliation Log` | `tabProcess Payment Reconciliation Log` | master | 7 | 1 | 1 | `format:PPR-LOG-{##}` |
| `Process Statement Of Accounts` | `tabProcess Statement Of Accounts` | master | 38 | 12 | 4 | `Prompt` |
| `Promotional Scheme` | `tabPromotional Scheme` | master | 15 | 5 | 12 | `Prompt` |
| `Purchase Taxes and Charges Template` | `tabPurchase Taxes and Charges Template` | master | 5 | 2 | 1 | `-` |
| `Sales Taxes and Charges Template` | `tabSales Taxes and Charges Template` | master | 5 | 2 | 1 | `-` |
| `Share Type` | `tabShare Type` | master | 2 | 0 | 0 | `field:title` |
| `Shareholder` | `tabShareholder` | master | 6 | 1 | 1 | `naming_series:` |
| `Shipping Rule` | `tabShipping Rule` | master | 9 | 4 | 2 | `field:label` |
| `Subscription` | `tabSubscription` | master | 26 | 5 | 1 | `ACC-SUB-.YYYY.-.#####` |
| `Subscription Plan` | `tabSubscription Plan` | master | 11 | 5 | 0 | `field:plan_name` |
| `Tax Category` | `tabTax Category` | master | 2 | 0 | 0 | `field:title` |
| `Tax Rule` | `tabTax Rule` | master | 25 | 12 | 0 | `ACC-TAX-RULE-.YYYY.-.#####` |
| `Tax Withholding Category` | `tabTax Withholding Category` | master | 6 | 0 | 2 | `Prompt` |
| `Tax Withholding Group` | `tabTax Withholding Group` | master | 1 | 0 | 0 | `field:group_name` |
| `Account` | `tabAccount` | tree-master | 18 | 4 | 0 | `-` |
| `Cost Center` | `tabCost Center` | tree-master | 9 | 3 | 0 | `-` |
| `Account Closing Balance` | `tabAccount Closing Balance` | transaction | 16 | 7 | 0 | `-` |
| `Advance Payment Ledger Entry` | `tabAdvance Payment Ledger Entry` | transaction | 11 | 4 | 0 | `-` |
| `Bank Guarantee` | `tabBank Guarantee` | transaction | 24 | 8 | 0 | `ACC-BG-.YYYY.-.#####` |
| `Bank Transaction` | `tabBank Transaction` | transaction | 24 | 6 | 1 | `naming_series:` |
| `Budget` | `tabBudget` | transaction | 28 | 7 | 1 | `naming_series:` |
| `Cashier Closing` | `tabCashier Closing` | transaction | 11 | 2 | 1 | `naming_series:` |
| `Cost Center Allocation` | `tabCost Center Allocation` | transaction | 4 | 3 | 1 | `CC-ALLOC-.#####` |
| `Dunning` | `tabDunning` | transaction | 33 | 12 | 1 | `naming_series:` |
| `Exchange Rate Revaluation` | `tabExchange Rate Revaluation` | transaction | 7 | 2 | 1 | `ACC-ERR-.YYYY.-.#####` |
| `GL Entry` | `tabGL Entry` | transaction | 35 | 11 | 0 | `ACC-GLE-.YYYY.-.#####` |
| `Invoice Discounting` | `tabInvoice Discounting` | transaction | 15 | 8 | 1 | `ACC-INV-DISC-.YYYY.-.#####` |
| `Journal Entry` | `tabJournal Entry` | transaction | 47 | 18 | 2 | `naming_series:` |
| `POS Closing Entry` | `tabPOS Closing Entry` | transaction | 15 | 5 | 4 | `POS-CLO-.YYYY.-.#####` |
| `POS Invoice` | `tabPOS Invoice` | transaction | 115 | 42 | 10 | `naming_series:` |
| `POS Invoice Merge Log` | `tabPOS Invoice Merge Log` | transaction | 10 | 7 | 1 | `-` |
| `POS Opening Entry` | `tabPOS Opening Entry` | transaction | 10 | 4 | 1 | `POS-OPE-.YYYY.-.#####` |
| `Payment Entry` | `tabPayment Entry` | transaction | 63 | 21 | 4 | `naming_series:` |
| `Payment Ledger Entry` | `tabPayment Ledger Entry` | transaction | 20 | 9 | 0 | `-` |
| `Payment Order` | `tabPayment Order` | transaction | 9 | 5 | 1 | `naming_series:` |
| `Payment Request` | `tabPayment Request` | transaction | 40 | 13 | 2 | `naming_series:` |
| `Period Closing Voucher` | `tabPeriod Closing Voucher` | transaction | 10 | 4 | 0 | `ACC-PCV-.YYYY.-.#####` |
| `Process Deferred Accounting` | `tabProcess Deferred Accounting` | transaction | 7 | 3 | 0 | `ACC-PDA-.#####` |
| `Process Payment Reconciliation` | `tabProcess Payment Reconciliation` | transaction | 14 | 7 | 0 | `format:ACC-PPR-{#####}` |
| `Process Period Closing Voucher` | `tabProcess Period Closing Voucher` | transaction | 5 | 2 | 2 | `format:Process-PCV-{###}` |
| `Process Subscription` | `tabProcess Subscription` | transaction | 3 | 2 | 0 | `-` |
| `Purchase Invoice` | `tabPurchase Invoice` | transaction | 125 | 39 | 8 | `naming_series:` |
| `Repost Accounting Ledger` | `tabRepost Accounting Ledger` | transaction | 6 | 3 | 1 | `-` |
| `Repost Payment Ledger` | `tabRepost Payment Ledger` | transaction | 7 | 3 | 1 | `-` |
| `Sales Invoice` | `tabSales Invoice` | transaction | 143 | 51 | 11 | `naming_series:` |
| `Share Transfer` | `tabShare Transfer` | transaction | 17 | 7 | 0 | `ACC-SHT-.YYYY.-.#####` |
| `Unreconcile Payment` | `tabUnreconcile Payment` | transaction | 4 | 3 | 1 | `-` |
| `Accounting Dimension Detail` | `tabAccounting Dimension Detail` | child | 7 | 3 | 0 | `-` |
| `Advance Taxes and Charges` | `tabAdvance Taxes and Charges` | child | 18 | 4 | 0 | `-` |
| `Allowed Dimension` | `tabAllowed Dimension` | child | 2 | 1 | 0 | `-` |
| `Allowed To Transact With` | `tabAllowed To Transact With` | child | 1 | 1 | 0 | `-` |
| `Applicable On Account` | `tabApplicable On Account` | child | 2 | 1 | 0 | `-` |
| `Bank Clearance Detail` | `tabBank Clearance Detail` | child | 8 | 1 | 0 | `-` |
| `Bank Statement Import Log Column Map` | `tabBank Statement Import Log Column Map` | child | 4 | 0 | 0 | `-` |
| `Bank Transaction Mapping` | `tabBank Transaction Mapping` | child | 2 | 0 | 0 | `-` |
| `Bank Transaction Payments` | `tabBank Transaction Payments` | child | 5 | 1 | 0 | `-` |
| `Bank Transaction Rule Accounts` | `tabBank Transaction Rule Accounts` | child | 6 | 2 | 0 | `-` |
| `Bank Transaction Rule Description Conditions` | `tabBank Transaction Rule Description Conditions` | child | 2 | 0 | 0 | `-` |
| `Budget Account` | `tabBudget Account` | child | 2 | 1 | 0 | `-` |
| `Budget Distribution` | `tabBudget Distribution` | child | 4 | 0 | 0 | `-` |
| `Campaign Item` | `tabCampaign Item` | child | 1 | 1 | 0 | `-` |
| `Cashier Closing Payments` | `tabCashier Closing Payments` | child | 2 | 1 | 0 | `-` |
| `Closed Document` | `tabClosed Document` | child | 2 | 1 | 0 | `-` |
| `Cost Center Allocation Percentage` | `tabCost Center Allocation Percentage` | child | 2 | 1 | 0 | `-` |
| `Currency Exchange Settings Details` | `tabCurrency Exchange Settings Details` | child | 2 | 0 | 0 | `-` |
| `Currency Exchange Settings Result` | `tabCurrency Exchange Settings Result` | child | 1 | 0 | 0 | `-` |
| `Customer Group Item` | `tabCustomer Group Item` | child | 1 | 1 | 0 | `-` |
| `Customer Item` | `tabCustomer Item` | child | 1 | 1 | 0 | `-` |
| `Discounted Invoice` | `tabDiscounted Invoice` | child | 5 | 3 | 0 | `-` |
| `Dunning Letter Text` | `tabDunning Letter Text` | child | 4 | 1 | 0 | `-` |
| `Exchange Rate Revaluation Account` | `tabExchange Rate Revaluation Account` | child | 12 | 3 | 0 | `-` |
| `Financial Report Row` | `tabFinancial Report Row` | child | 15 | 0 | 0 | `-` |
| `Fiscal Year Company` | `tabFiscal Year Company` | child | 1 | 1 | 0 | `-` |
| `Item Tax Template Detail` | `tabItem Tax Template Detail` | child | 3 | 1 | 0 | `-` |
| `Item Wise Tax Detail` | `tabItem Wise Tax Detail` | child | 5 | 0 | 0 | `-` |
| `Journal Entry Account` | `tabJournal Entry Account` | child | 23 | 7 | 0 | `hash` |
| `Journal Entry Template Account` | `tabJournal Entry Template Account` | child | 5 | 4 | 0 | `-` |
| `Ledger Health Monitor Company` | `tabLedger Health Monitor Company` | child | 1 | 1 | 0 | `-` |
| `Ledger Merge Accounts` | `tabLedger Merge Accounts` | child | 3 | 1 | 0 | `-` |
| `Loyalty Point Entry Redemption` | `tabLoyalty Point Entry Redemption` | child | 3 | 0 | 0 | `-` |
| `Loyalty Program Collection` | `tabLoyalty Program Collection` | child | 3 | 0 | 0 | `-` |
| `Mode of Payment Account` | `tabMode of Payment Account` | child | 2 | 2 | 0 | `-` |
| `Monthly Distribution Percentage` | `tabMonthly Distribution Percentage` | child | 2 | 0 | 0 | `hash` |
| `Opening Invoice Creation Tool Item` | `tabOpening Invoice Creation Tool Item` | child | 13 | 4 | 0 | `-` |
| `Overdue Payment` | `tabOverdue Payment` | child | 14 | 3 | 0 | `-` |
| `POS Closing Entry Detail` | `tabPOS Closing Entry Detail` | child | 5 | 1 | 0 | `-` |
| `POS Closing Entry Taxes` | `tabPOS Closing Entry Taxes` | child | 2 | 1 | 0 | `-` |
| `POS Customer Group` | `tabPOS Customer Group` | child | 1 | 1 | 0 | `-` |
| `POS Field` | `tabPOS Field` | child | 7 | 0 | 0 | `-` |
| `POS Invoice Item` | `tabPOS Invoice Item` | child | 71 | 21 | 0 | `hash` |
| `POS Invoice Reference` | `tabPOS Invoice Reference` | child | 6 | 3 | 0 | `-` |
| `POS Item Group` | `tabPOS Item Group` | child | 1 | 1 | 0 | `-` |
| `POS Opening Entry Detail` | `tabPOS Opening Entry Detail` | child | 2 | 1 | 0 | `-` |
| `POS Payment Method` | `tabPOS Payment Method` | child | 3 | 1 | 0 | `-` |
| `POS Profile User` | `tabPOS Profile User` | child | 2 | 1 | 0 | `-` |
| `POS Search Fields` | `tabPOS Search Fields` | child | 2 | 0 | 0 | `-` |
| `PSOA Cost Center` | `tabPSOA Cost Center` | child | 1 | 1 | 0 | `-` |
| `PSOA Project` | `tabPSOA Project` | child | 1 | 1 | 0 | `-` |
| `Party Account` | `tabParty Account` | child | 3 | 3 | 0 | `-` |
| `Payment Entry Deduction` | `tabPayment Entry Deduction` | child | 5 | 2 | 0 | `-` |
| `Payment Entry Reference` | `tabPayment Entry Reference` | child | 18 | 5 | 0 | `-` |
| `Payment Order Reference` | `tabPayment Order Reference` | child | 9 | 6 | 0 | `-` |
| `Payment Reconciliation Allocation` | `tabPayment Reconciliation Allocation` | child | 16 | 5 | 0 | `-` |
| `Payment Reconciliation Invoice` | `tabPayment Reconciliation Invoice` | child | 7 | 1 | 0 | `-` |
| `Payment Reconciliation Payment` | `tabPayment Reconciliation Payment` | child | 11 | 3 | 0 | `-` |
| `Payment Reference` | `tabPayment Reference` | child | 6 | 3 | 0 | `-` |
| `Payment Schedule` | `tabPayment Schedule` | child | 20 | 2 | 0 | `-` |
| `Payment Terms Template Detail` | `tabPayment Terms Template Detail` | child | 11 | 2 | 0 | `-` |
| `Pegged Currency Details` | `tabPegged Currency Details` | child | 3 | 2 | 0 | `-` |
| `Pricing Rule Brand` | `tabPricing Rule Brand` | child | 2 | 2 | 0 | `-` |
| `Pricing Rule Detail` | `tabPricing Rule Detail` | child | 6 | 1 | 0 | `-` |
| `Pricing Rule Item Code` | `tabPricing Rule Item Code` | child | 2 | 2 | 0 | `-` |
| `Pricing Rule Item Group` | `tabPricing Rule Item Group` | child | 2 | 2 | 0 | `-` |
| `Process Payment Reconciliation Log Allocations` | `tabProcess Payment Reconciliation Log Allocations` | child | 15 | 4 | 0 | `-` |
| `Process Period Closing Voucher Detail` | `tabProcess Period Closing Voucher Detail` | child | 4 | 0 | 0 | `-` |
| `Process Statement Of Accounts CC` | `tabProcess Statement Of Accounts CC` | child | 1 | 1 | 0 | `-` |
| `Process Statement Of Accounts Customer` | `tabProcess Statement Of Accounts Customer` | child | 4 | 1 | 0 | `-` |
| `Promotional Scheme Price Discount` | `tabPromotional Scheme Price Discount` | child | 17 | 2 | 0 | `-` |
| `Promotional Scheme Product Discount` | `tabPromotional Scheme Product Discount` | child | 19 | 3 | 0 | `-` |
| `Purchase Invoice Advance` | `tabPurchase Invoice Advance` | child | 9 | 1 | 0 | `-` |
| `Purchase Invoice Item` | `tabPurchase Invoice Item` | child | 82 | 27 | 0 | `hash` |
| `Purchase Taxes and Charges` | `tabPurchase Taxes and Charges` | child | 24 | 4 | 0 | `hash` |
| `Repost Accounting Ledger Items` | `tabRepost Accounting Ledger Items` | child | 4 | 1 | 0 | `-` |
| `Repost Allowed Types` | `tabRepost Allowed Types` | child | 1 | 1 | 0 | `-` |
| `Repost Payment Ledger Items` | `tabRepost Payment Ledger Items` | child | 2 | 1 | 0 | `-` |
| `Sales Invoice Advance` | `tabSales Invoice Advance` | child | 9 | 1 | 0 | `-` |
| `Sales Invoice Item` | `tabSales Invoice Item` | child | 84 | 26 | 0 | `hash` |
| `Sales Invoice Payment` | `tabSales Invoice Payment` | child | 8 | 2 | 0 | `-` |
| `Sales Invoice Reference` | `tabSales Invoice Reference` | child | 6 | 3 | 0 | `-` |
| `Sales Invoice Timesheet` | `tabSales Invoice Timesheet` | child | 9 | 2 | 0 | `-` |
| `Sales Partner Item` | `tabSales Partner Item` | child | 1 | 1 | 0 | `-` |
| `Sales Taxes and Charges` | `tabSales Taxes and Charges` | child | 21 | 4 | 0 | `-` |
| `Share Balance` | `tabShare Balance` | child | 8 | 1 | 0 | `-` |
| `Shipping Rule Condition` | `tabShipping Rule Condition` | child | 3 | 0 | 0 | `-` |
| `Shipping Rule Country` | `tabShipping Rule Country` | child | 1 | 1 | 0 | `-` |
| `South Africa VAT Account` | `tabSouth Africa VAT Account` | child | 1 | 1 | 0 | `account` |
| `Subscription Invoice` | `tabSubscription Invoice` | child | 2 | 1 | 0 | `-` |
| `Subscription Plan Detail` | `tabSubscription Plan Detail` | child | 2 | 1 | 0 | `-` |
| `Supplier Group Item` | `tabSupplier Group Item` | child | 1 | 1 | 0 | `-` |
| `Supplier Item` | `tabSupplier Item` | child | 1 | 1 | 0 | `-` |
| `Tax Withholding Account` | `tabTax Withholding Account` | child | 2 | 2 | 0 | `-` |
| `Tax Withholding Entry` | `tabTax Withholding Entry` | child | 21 | 8 | 0 | `-` |
| `Tax Withholding Rate` | `tabTax Withholding Rate` | child | 6 | 1 | 0 | `-` |
| `Territory Item` | `tabTerritory Item` | child | 1 | 1 | 0 | `-` |
| `Transaction Deletion Record Details` | `tabTransaction Deletion Record Details` | child | 4 | 1 | 0 | `-` |
| `Unreconcile Payment Entries` | `tabUnreconcile Payment Entries` | child | 8 | 2 | 0 | `-` |

## erpnext / Assets (26)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Asset Activity` | `tabAsset Activity` | master | 4 | 2 | 0 | `-` |
| `Asset Category` | `tabAsset Category` | master | 3 | 0 | 2 | `field:asset_category_name` |
| `Asset Maintenance` | `tabAsset Maintenance` | master | 8 | 3 | 1 | `field:asset_name` |
| `Asset Maintenance Team` | `tabAsset Maintenance Team` | master | 4 | 2 | 1 | `field:maintenance_team_name` |
| `Asset Shift Factor` | `tabAsset Shift Factor` | master | 3 | 0 | 0 | `field:shift_name` |
| `Location` | `tabLocation` | tree-master | 12 | 2 | 0 | `field:location_name` |
| `Asset` | `tabAsset` | transaction | 51 | 16 | 1 | `naming_series:` |
| `Asset Capitalization` | `tabAsset Capitalization` | transaction | 19 | 8 | 3 | `naming_series:` |
| `Asset Depreciation Schedule` | `tabAsset Depreciation Schedule` | transaction | 19 | 4 | 1 | `naming_series:` |
| `Asset Maintenance Log` | `tabAsset Maintenance Log` | transaction | 19 | 3 | 0 | `naming_series:` |
| `Asset Movement` | `tabAsset Movement` | transaction | 6 | 3 | 1 | `format:ACC-ASM-{YYYY}-{#####}` |
| `Asset Repair` | `tabAsset Repair` | transaction | 18 | 5 | 2 | `naming_series:` |
| `Asset Shift Allocation` | `tabAsset Shift Allocation` | transaction | 4 | 3 | 1 | `naming_series:` |
| `Asset Value Adjustment` | `tabAsset Value Adjustment` | transaction | 12 | 7 | 0 | `-` |
| `Asset Capitalization Asset Item` | `tabAsset Capitalization Asset Item` | child | 10 | 6 | 0 | `-` |
| `Asset Capitalization Service Item` | `tabAsset Capitalization Service Item` | child | 8 | 4 | 0 | `-` |
| `Asset Capitalization Stock Item` | `tabAsset Capitalization Stock Item` | child | 14 | 6 | 0 | `-` |
| `Asset Category Account` | `tabAsset Category Account` | child | 5 | 5 | 0 | `-` |
| `Asset Finance Book` | `tabAsset Finance Book` | child | 13 | 1 | 0 | `-` |
| `Asset Maintenance Task` | `tabAsset Maintenance Task` | child | 12 | 1 | 0 | `-` |
| `Asset Movement Item` | `tabAsset Movement Item` | child | 7 | 6 | 0 | `-` |
| `Asset Repair Consumed Item` | `tabAsset Repair Consumed Item` | child | 7 | 3 | 0 | `-` |
| `Asset Repair Purchase Invoice` | `tabAsset Repair Purchase Invoice` | child | 3 | 2 | 0 | `-` |
| `Depreciation Schedule` | `tabDepreciation Schedule` | child | 5 | 2 | 0 | `-` |
| `Linked Location` | `tabLinked Location` | child | 1 | 1 | 0 | `-` |
| `Maintenance Team Member` | `tabMaintenance Team Member` | child | 3 | 2 | 0 | `field:team_member` |

## erpnext / Bulk Transaction (2)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Bulk Transaction Log` | `tabBulk Transaction Log` | master | 4 | 0 | 0 | `-` |
| `Bulk Transaction Log Detail` | `tabBulk Transaction Log Detail` | master | 8 | 2 | 0 | `-` |

## erpnext / Buying (19)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Buying Settings` | `tabBuying Settings` | single | 28 | 4 | 0 | `-` |
| `Supplier` | `tabSupplier` | master | 39 | 14 | 5 | `naming_series:` |
| `Supplier Scorecard` | `tabSupplier Scorecard` | master | 13 | 2 | 2 | `field:supplier` |
| `Supplier Scorecard Criteria` | `tabSupplier Scorecard Criteria` | master | 4 | 0 | 0 | `field:criteria_name` |
| `Supplier Scorecard Standing` | `tabSupplier Scorecard Standing` | master | 11 | 1 | 0 | `field:standing_name` |
| `Supplier Scorecard Variable` | `tabSupplier Scorecard Variable` | master | 5 | 0 | 0 | `field:variable_label` |
| `Purchase Order` | `tabPurchase Order` | transaction | 97 | 34 | 5 | `naming_series:` |
| `Request for Quotation` | `tabRequest for Quotation` | transaction | 27 | 11 | 2 | `naming_series:` |
| `Supplier Quotation` | `tabSupplier Quotation` | transaction | 69 | 21 | 4 | `naming_series:` |
| `Supplier Scorecard Period` | `tabSupplier Scorecard Period` | transaction | 7 | 3 | 2 | `naming_series:` |
| `Customer Number At Supplier` | `tabCustomer Number At Supplier` | child | 2 | 1 | 0 | `-` |
| `Purchase Order Item` | `tabPurchase Order Item` | child | 75 | 24 | 0 | `hash` |
| `Purchase Receipt Item Supplied` | `tabPurchase Receipt Item Supplied` | child | 16 | 5 | 0 | `-` |
| `Request for Quotation Item` | `tabRequest for Quotation Item` | child | 19 | 9 | 0 | `hash` |
| `Request for Quotation Supplier` | `tabRequest for Quotation Supplier` | child | 7 | 2 | 0 | `-` |
| `Supplier Quotation Item` | `tabSupplier Quotation Item` | child | 49 | 14 | 0 | `hash` |
| `Supplier Scorecard Scoring Criteria` | `tabSupplier Scorecard Scoring Criteria` | child | 5 | 1 | 0 | `-` |
| `Supplier Scorecard Scoring Standing` | `tabSupplier Scorecard Scoring Standing` | child | 11 | 2 | 0 | `-` |
| `Supplier Scorecard Scoring Variable` | `tabSupplier Scorecard Scoring Variable` | child | 5 | 1 | 0 | `-` |

## erpnext / CRM (28)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Appointment Booking Settings` | `tabAppointment Booking Settings` | single | 10 | 1 | 2 | `-` |
| `CRM Settings` | `tabCRM Settings` | single | 9 | 0 | 1 | `-` |
| `Appointment` | `tabAppointment` | master | 13 | 2 | 0 | `format:APMT-{customer_name}-{####}` |
| `Campaign` | `tabCampaign` | master | 3 | 0 | 1 | `naming_series:` |
| `Competitor` | `tabCompetitor` | master | 2 | 0 | 0 | `field:competitor_name` |
| `Contract Template` | `tabContract Template` | master | 3 | 0 | 1 | `field:title` |
| `Email Campaign` | `tabEmail Campaign` | master | 7 | 2 | 0 | `format:MAIL-CAMP-{YYYY}-{#####}` |
| `Lead` | `tabLead` | master | 43 | 14 | 1 | `naming_series:` |
| `Market Segment` | `tabMarket Segment` | master | 1 | 0 | 0 | `field:market_segment` |
| `Opportunity` | `tabOpportunity` | master | 47 | 18 | 4 | `naming_series:` |
| `Opportunity Lost Reason` | `tabOpportunity Lost Reason` | master | 1 | 0 | 0 | `field:lost_reason` |
| `Opportunity Type` | `tabOpportunity Type` | master | 1 | 0 | 0 | `Prompt` |
| `Prospect` | `tabProspect` | master | 11 | 6 | 3 | `field:company_name` |
| `Sales Stage` | `tabSales Stage` | master | 1 | 0 | 0 | `field:stage_name` |
| `Contract` | `tabContract` | transaction | 21 | 4 | 1 | `CON-.YYYY.-.#####` |
| `Appointment Booking Slots` | `tabAppointment Booking Slots` | child | 3 | 0 | 0 | `-` |
| `Availability Of Slots` | `tabAvailability Of Slots` | child | 3 | 0 | 0 | `-` |
| `CRM Note` | `tabCRM Note` | child | 3 | 1 | 0 | `autoincrement` |
| `Campaign Email Schedule` | `tabCampaign Email Schedule` | child | 2 | 1 | 0 | `-` |
| `Competitor Detail` | `tabCompetitor Detail` | child | 1 | 1 | 0 | `-` |
| `Contract Fulfilment Checklist` | `tabContract Fulfilment Checklist` | child | 4 | 1 | 0 | `-` |
| `Contract Template Fulfilment Terms` | `tabContract Template Fulfilment Terms` | child | 1 | 0 | 0 | `-` |
| `Frappe CRM Allowed User` | `tabFrappe CRM Allowed User` | child | 1 | 1 | 0 | `-` |
| `Lost Reason Detail` | `tabLost Reason Detail` | child | 1 | 1 | 0 | `-` |
| `Opportunity Item` | `tabOpportunity Item` | child | 12 | 4 | 0 | `-` |
| `Opportunity Lost Reason Detail` | `tabOpportunity Lost Reason Detail` | child | 1 | 1 | 0 | `-` |
| `Prospect Lead` | `tabProspect Lead` | child | 6 | 1 | 0 | `-` |
| `Prospect Opportunity` | `tabProspect Opportunity` | child | 8 | 3 | 0 | `autoincrement` |

## erpnext / Communication (2)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Communication Medium` | `tabCommunication Medium` | master | 5 | 2 | 1 | `Prompt` |
| `Communication Medium Timeslot` | `tabCommunication Medium Timeslot` | child | 4 | 1 | 0 | `-` |

## erpnext / EDI (2)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Code List` | `tabCode List` | master | 8 | 1 | 0 | `prompt` |
| `Common Code` | `tabCommon Code` | master | 6 | 1 | 1 | `hash` |

## erpnext / ERPNext Integrations (1)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Plaid Settings` | `tabPlaid Settings` | single | 6 | 0 | 0 | `-` |

## erpnext / Maintenance (5)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Maintenance Schedule` | `tabMaintenance Schedule` | transaction | 15 | 7 | 2 | `naming_series:` |
| `Maintenance Visit` | `tabMaintenance Visit` | transaction | 21 | 9 | 1 | `naming_series:` |
| `Maintenance Schedule Detail` | `tabMaintenance Schedule Detail` | child | 8 | 3 | 0 | `hash` |
| `Maintenance Schedule Item` | `tabMaintenance Schedule Item` | child | 11 | 4 | 0 | `hash` |
| `Maintenance Visit Purpose` | `tabMaintenance Visit Purpose` | child | 9 | 4 | 0 | `hash` |

## erpnext / Manufacturing (48)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `BOM Update Tool` | `tabBOM Update Tool` | single | 2 | 2 | 0 | `-` |
| `Manufacturing Settings` | `tabManufacturing Settings` | single | 19 | 0 | 0 | `-` |
| `Downtime Entry` | `tabDowntime Entry` | master | 8 | 2 | 0 | `naming_series:` |
| `Master Production Schedule` | `tabMaster Production Schedule` | master | 8 | 4 | 4 | `naming_series:` |
| `Operation` | `tabOperation` | master | 8 | 2 | 1 | `Prompt` |
| `Plant Floor` | `tabPlant Floor` | master | 3 | 2 | 0 | `field:floor_name` |
| `Routing` | `tabRouting` | master | 2 | 0 | 1 | `field:routing_name` |
| `Workstation` | `tabWorkstation` | master | 13 | 4 | 2 | `field:workstation_name` |
| `Workstation Operating Component` | `tabWorkstation Operating Component` | master | 1 | 0 | 1 | `field:component_name` |
| `Workstation Type` | `tabWorkstation Type` | master | 3 | 0 | 1 | `field:workstation_type` |
| `BOM` | `tabBOM` | transaction | 53 | 13 | 4 | `-` |
| `BOM Creator` | `tabBOM Creator` | transaction | 22 | 11 | 1 | `prompt` |
| `BOM Update Log` | `tabBOM Update Log` | transaction | 8 | 4 | 1 | `BOM-UPDT-LOG-.#####` |
| `Blanket Order` | `tabBlanket Order` | transaction | 14 | 5 | 1 | `naming_series:` |
| `Job Card` | `tabJob Card` | transaction | 50 | 20 | 6 | `naming_series:` |
| `Production Plan` | `tabProduction Plan` | transaction | 29 | 9 | 7 | `naming_series:` |
| `Sales Forecast` | `tabSales Forecast` | transaction | 9 | 3 | 2 | `naming_series:` |
| `Work Order` | `tabWork Order` | transaction | 55 | 16 | 4 | `naming_series:` |
| `BOM Creator Item` | `tabBOM Creator Item` | child | 24 | 6 | 0 | `-` |
| `BOM Explosion Item` | `tabBOM Explosion Item` | child | 14 | 4 | 0 | `hash` |
| `BOM Item` | `tabBOM Item` | child | 27 | 7 | 0 | `-` |
| `BOM Operation` | `tabBOM Operation` | child | 27 | 8 | 0 | `-` |
| `BOM Secondary Item` | `tabBOM Secondary Item` | child | 17 | 3 | 0 | `-` |
| `BOM Update Batch` | `tabBOM Update Batch` | child | 4 | 0 | 0 | `hash` |
| `BOM Website Item` | `tabBOM Website Item` | child | 5 | 1 | 0 | `-` |
| `BOM Website Operation` | `tabBOM Website Operation` | child | 5 | 2 | 0 | `-` |
| `Blanket Order Item` | `tabBlanket Order Item` | child | 7 | 1 | 0 | `-` |
| `Job Card Item` | `tabJob Card Item` | child | 11 | 5 | 0 | `-` |
| `Job Card Operation` | `tabJob Card Operation` | child | 4 | 1 | 0 | `-` |
| `Job Card Scheduled Time` | `tabJob Card Scheduled Time` | child | 3 | 0 | 0 | `-` |
| `Job Card Secondary Item` | `tabJob Card Secondary Item` | child | 7 | 2 | 0 | `-` |
| `Job Card Time Log` | `tabJob Card Time Log` | child | 6 | 2 | 0 | `-` |
| `Master Production Schedule Item` | `tabMaster Production Schedule Item` | child | 9 | 4 | 0 | `-` |
| `Material Request Plan Item` | `tabMaterial Request Plan Item` | child | 23 | 7 | 0 | `-` |
| `Production Plan Item` | `tabProduction Plan Item` | child | 18 | 7 | 0 | `hash` |
| `Production Plan Item Reference` | `tabProduction Plan Item Reference` | child | 4 | 1 | 0 | `-` |
| `Production Plan Material Request` | `tabProduction Plan Material Request` | child | 2 | 1 | 0 | `hash` |
| `Production Plan Material Request Warehouse` | `tabProduction Plan Material Request Warehouse` | child | 1 | 1 | 0 | `-` |
| `Production Plan Sales Order` | `tabProduction Plan Sales Order` | child | 5 | 2 | 0 | `hash` |
| `Production Plan Sub Assembly Item` | `tabProduction Plan Sub Assembly Item` | child | 25 | 9 | 0 | `-` |
| `Sales Forecast Item` | `tabSales Forecast Item` | child | 6 | 3 | 0 | `-` |
| `Sub Operation` | `tabSub Operation` | child | 3 | 1 | 0 | `-` |
| `Work Order Additional Item` | `tabWork Order Additional Item` | child | 6 | 2 | 0 | `-` |
| `Work Order Item` | `tabWork Order Item` | child | 21 | 4 | 0 | `-` |
| `Work Order Operation` | `tabWork Order Operation` | child | 29 | 9 | 0 | `-` |
| `Workstation Cost` | `tabWorkstation Cost` | child | 2 | 1 | 0 | `-` |
| `Workstation Operating Component Account` | `tabWorkstation Operating Component Account` | child | 2 | 2 | 0 | `-` |
| `Workstation Working Hour` | `tabWorkstation Working Hour` | child | 4 | 0 | 0 | `-` |

## erpnext / Portal (2)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Website Attribute` | `tabWebsite Attribute` | child | 1 | 1 | 0 | `-` |
| `Website Filter Field` | `tabWebsite Filter Field` | child | 1 | 0 | 0 | `-` |

## erpnext / Projects (15)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Projects Settings` | `tabProjects Settings` | single | 4 | 0 | 0 | `-` |
| `Activity Cost` | `tabActivity Cost` | master | 7 | 3 | 0 | `PROJ-ACC-.#####` |
| `Activity Type` | `tabActivity Type` | master | 4 | 0 | 0 | `field:activity_type` |
| `Project` | `tabProject` | master | 42 | 8 | 1 | `naming_series:` |
| `Project Template` | `tabProject Template` | master | 2 | 1 | 1 | `Prompt` |
| `Project Type` | `tabProject Type` | master | 2 | 0 | 0 | `field:project_type` |
| `Task Type` | `tabTask Type` | master | 2 | 0 | 0 | `Prompt` |
| `Task` | `tabTask` | tree-master | 35 | 7 | 1 | `TASK-.YYYY.-.#####` |
| `Project Update` | `tabProject Update` | transaction | 6 | 2 | 1 | `naming_series:` |
| `Timesheet` | `tabTimesheet` | transaction | 27 | 9 | 1 | `naming_series:` |
| `Dependent Task` | `tabDependent Task` | child | 1 | 1 | 0 | `-` |
| `Project Template Task` | `tabProject Template Task` | child | 2 | 1 | 0 | `-` |
| `Project User` | `tabProject User` | child | 8 | 1 | 0 | `-` |
| `Task Depends On` | `tabTask Depends On` | child | 3 | 1 | 0 | `-` |
| `Timesheet Detail` | `tabTimesheet Detail` | child | 21 | 4 | 0 | `-` |

## erpnext / Quality Management (16)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Non Conformance` | `tabNon Conformance` | master | 8 | 1 | 0 | `format:QA-NC-{#####}` |
| `Quality Action` | `tabQuality Action` | master | 7 | 4 | 1 | `format:QA-ACT-{#####}` |
| `Quality Feedback` | `tabQuality Feedback` | master | 3 | 1 | 1 | `format:QA-FB-{#####}` |
| `Quality Feedback Template` | `tabQuality Feedback Template` | master | 1 | 0 | 1 | `field:template` |
| `Quality Goal` | `tabQuality Goal` | master | 5 | 1 | 1 | `field:goal` |
| `Quality Meeting` | `tabQuality Meeting` | master | 1 | 0 | 2 | `format:QA-MEET-{YY}-{MM}-{DD}` |
| `Quality Review` | `tabQuality Review` | master | 5 | 2 | 1 | `format:QA-REV-{#####}` |
| `Quality Procedure` | `tabQuality Procedure` | tree-master | 8 | 2 | 1 | `field:quality_procedure_name` |
| `Quality Action Resolution` | `tabQuality Action Resolution` | child | 5 | 1 | 0 | `-` |
| `Quality Feedback Parameter` | `tabQuality Feedback Parameter` | child | 3 | 0 | 0 | `-` |
| `Quality Feedback Template Parameter` | `tabQuality Feedback Template Parameter` | child | 1 | 0 | 0 | `-` |
| `Quality Goal Objective` | `tabQuality Goal Objective` | child | 3 | 1 | 0 | `format:{####}` |
| `Quality Meeting Agenda` | `tabQuality Meeting Agenda` | child | 1 | 0 | 0 | `-` |
| `Quality Meeting Minutes` | `tabQuality Meeting Minutes` | child | 3 | 0 | 0 | `-` |
| `Quality Procedure Process` | `tabQuality Procedure Process` | child | 2 | 1 | 0 | `-` |
| `Quality Review Objective` | `tabQuality Review Objective` | child | 5 | 1 | 0 | `-` |

## erpnext / Regional (5)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Import Supplier Invoice` | `tabImport Supplier Invoice` | master | 8 | 5 | 0 | `-` |
| `Lower Deduction Certificate` | `tabLower Deduction Certificate` | master | 10 | 4 | 0 | `field:certificate_no` |
| `South Africa VAT Settings` | `tabSouth Africa VAT Settings` | master | 1 | 1 | 1 | `field:company` |
| `UAE VAT Settings` | `tabUAE VAT Settings` | master | 1 | 1 | 1 | `field:company` |
| `UAE VAT Account` | `tabUAE VAT Account` | child | 1 | 1 | 0 | `account` |

## erpnext / Selling (20)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `SMS Center` | `tabSMS Center` | single | 10 | 5 | 0 | `-` |
| `Selling Settings` | `tabSelling Settings` | single | 33 | 5 | 0 | `-` |
| `Customer` | `tabCustomer` | master | 44 | 22 | 7 | `naming_series:` |
| `Delivery Schedule Item` | `tabDelivery Schedule Item` | master | 10 | 5 | 0 | `-` |
| `Industry Type` | `tabIndustry Type` | master | 1 | 0 | 0 | `field:industry` |
| `Party Specific Item` | `tabParty Specific Item` | master | 4 | 0 | 0 | `-` |
| `Sales Partner Type` | `tabSales Partner Type` | master | 1 | 0 | 0 | `field:sales_partner_type` |
| `Installation Note` | `tabInstallation Note` | transaction | 18 | 8 | 1 | `naming_series:` |
| `Product Bundle` | `tabProduct Bundle` | transaction | 5 | 2 | 1 | `-` |
| `Proforma Invoice` | `tabProforma Invoice` | transaction | 18 | 7 | 1 | `naming_series:` |
| `Quotation` | `tabQuotation` | transaction | 77 | 30 | 8 | `naming_series:` |
| `Sales Order` | `tabSales Order` | transaction | 104 | 35 | 7 | `naming_series:` |
| `Customer Credit Limit` | `tabCustomer Credit Limit` | child | 4 | 1 | 0 | `-` |
| `Installation Note Item` | `tabInstallation Note Item` | child | 8 | 2 | 0 | `hash` |
| `Product Bundle Item` | `tabProduct Bundle Item` | child | 5 | 2 | 0 | `-` |
| `Proforma Invoice Item` | `tabProforma Invoice Item` | child | 7 | 2 | 0 | `-` |
| `Quotation Item` | `tabQuotation Item` | child | 55 | 11 | 0 | `-` |
| `Sales Order Item` | `tabSales Order Item` | child | 82 | 19 | 0 | `hash` |
| `Sales Team` | `tabSales Team` | child | 6 | 1 | 0 | `-` |
| `Supplier Number At Customer` | `tabSupplier Number At Customer` | child | 2 | 1 | 0 | `-` |

## erpnext / Setup (40)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Authorization Control` | `tabAuthorization Control` | single | 0 | 0 | 0 | `-` |
| `Global Defaults` | `tabGlobal Defaults` | single | 9 | 5 | 0 | `-` |
| `Authorization Rule` | `tabAuthorization Rule` | master | 12 | 7 | 0 | `HR-ARU-.#####` |
| `Branch` | `tabBranch` | master | 1 | 0 | 0 | `field:branch` |
| `Brand` | `tabBrand` | master | 3 | 0 | 1 | `field:brand` |
| `Currency Exchange` | `tabCurrency Exchange` | master | 6 | 2 | 0 | `-` |
| `Designation` | `tabDesignation` | master | 2 | 0 | 0 | `field:designation_name` |
| `Driver` | `tabDriver` | master | 11 | 4 | 1 | `naming_series:` |
| `Email Digest` | `tabEmail Digest` | master | 29 | 1 | 1 | `Prompt` |
| `Employee Group` | `tabEmployee Group` | master | 1 | 0 | 1 | `field:employee_group_name` |
| `Holiday List` | `tabHoliday List` | master | 9 | 0 | 1 | `field:holiday_list_name` |
| `Incoterm` | `tabIncoterm` | master | 3 | 0 | 0 | `field:code` |
| `Party Type` | `tabParty Type` | master | 2 | 1 | 0 | `field:party_type` |
| `Quotation Lost Reason` | `tabQuotation Lost Reason` | master | 1 | 0 | 0 | `field:order_lost_reason` |
| `Sales Partner` | `tabSales Partner` | master | 11 | 2 | 1 | `field:partner_name` |
| `Terms and Conditions` | `tabTerms and Conditions` | master | 6 | 0 | 0 | `field:title` |
| `UOM` | `tabUOM` | master | 7 | 1 | 0 | `field:uom_name` |
| `UOM Conversion Factor` | `tabUOM Conversion Factor` | master | 4 | 3 | 0 | `MAT-UOM-CNV-.#####` |
| `Vehicle` | `tabVehicle` | master | 21 | 4 | 0 | `field:license_plate` |
| `Company` | `tabCompany` | tree-master | 100 | 60 | 0 | `field:company_name` |
| `Customer Group` | `tabCustomer Group` | tree-master | 8 | 4 | 2 | `field:customer_group_name` |
| `Department` | `tabDepartment` | tree-master | 8 | 2 | 0 | `-` |
| `Employee` | `tabEmployee` | tree-master | 67 | 10 | 3 | `naming_series:` |
| `Item Group` | `tabItem Group` | tree-master | 7 | 2 | 2 | `field:item_group_name` |
| `Sales Person` | `tabSales Person` | tree-master | 10 | 3 | 1 | `field:sales_person_name` |
| `Supplier Group` | `tabSupplier Group` | tree-master | 7 | 3 | 1 | `field:supplier_group_name` |
| `Territory` | `tabTerritory` | tree-master | 7 | 3 | 1 | `field:territory_name` |
| `Transaction Deletion Record` | `tabTransaction Deletion Record` | transaction | 11 | 2 | 3 | `TDL.####` |
| `Driving License Category` | `tabDriving License Category` | child | 4 | 0 | 0 | `-` |
| `Email Digest Recipient` | `tabEmail Digest Recipient` | child | 1 | 1 | 0 | `-` |
| `Employee Education` | `tabEmployee Education` | child | 6 | 0 | 0 | `-` |
| `Employee External Work History` | `tabEmployee External Work History` | child | 6 | 0 | 0 | `-` |
| `Employee Group Table` | `tabEmployee Group Table` | child | 3 | 1 | 0 | `-` |
| `Employee Internal Work History` | `tabEmployee Internal Work History` | child | 5 | 3 | 0 | `-` |
| `Holiday` | `tabHoliday` | child | 4 | 0 | 0 | `-` |
| `Quotation Lost Reason Detail` | `tabQuotation Lost Reason Detail` | child | 1 | 1 | 0 | `-` |
| `Target Detail` | `tabTarget Detail` | child | 5 | 3 | 0 | `-` |
| `Transaction Deletion Record Item` | `tabTransaction Deletion Record Item` | child | 1 | 1 | 0 | `-` |
| `Transaction Deletion Record To Delete` | `tabTransaction Deletion Record To Delete` | child | 5 | 1 | 0 | `-` |
| `Website Item Group` | `tabWebsite Item Group` | child | 1 | 1 | 0 | `-` |

## erpnext / Stock (77)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Delivery Settings` | `tabDelivery Settings` | single | 4 | 2 | 0 | `-` |
| `Item Variant Settings` | `tabItem Variant Settings` | single | 3 | 0 | 1 | `-` |
| `Quick Stock Balance` | `tabQuick Stock Balance` | single | 8 | 2 | 0 | `-` |
| `Stock Reposting Settings` | `tabStock Reposting Settings` | single | 11 | 1 | 0 | `-` |
| `Stock Settings` | `tabStock Settings` | single | 47 | 5 | 0 | `-` |
| `Batch` | `tabBatch` | master | 18 | 5 | 0 | `field:batch_id` |
| `Bin` | `tabBin` | master | 16 | 4 | 0 | `hash` |
| `Customs Tariff Number` | `tabCustoms Tariff Number` | master | 2 | 0 | 0 | `field:tariff_number` |
| `Inventory Dimension` | `tabInventory Dimension` | master | 13 | 2 | 0 | `field:dimension_name` |
| `Item` | `tabItem` | master | 72 | 15 | 9 | `field:item_code` |
| `Item Alternative` | `tabItem Alternative` | master | 5 | 2 | 0 | `-` |
| `Item Attribute` | `tabItem Attribute` | master | 6 | 0 | 1 | `field:attribute_name` |
| `Item Lead Time` | `tabItem Lead Time` | master | 13 | 2 | 0 | `field:item_code` |
| `Item Manufacturer` | `tabItem Manufacturer` | master | 6 | 2 | 0 | `-` |
| `Item Price` | `tabItem Price` | master | 19 | 8 | 0 | `hash` |
| `Manufacturer` | `tabManufacturer` | master | 6 | 1 | 0 | `field:short_name` |
| `Price List` | `tabPrice List` | master | 6 | 1 | 1 | `field:price_list_name` |
| `Putaway Rule` | `tabPutaway Rule` | master | 11 | 5 | 0 | `PUT-.####` |
| `Quality Inspection Parameter` | `tabQuality Inspection Parameter` | master | 3 | 1 | 0 | `field:parameter` |
| `Quality Inspection Parameter Group` | `tabQuality Inspection Parameter Group` | master | 1 | 0 | 0 | `field:group_name` |
| `Quality Inspection Template` | `tabQuality Inspection Template` | master | 1 | 0 | 1 | `field:quality_inspection_template_name` |
| `Serial No` | `tabSerial No` | master | 24 | 12 | 0 | `field:serial_no` |
| `Shipment Parcel Template` | `tabShipment Parcel Template` | master | 5 | 0 | 0 | `field:parcel_template_name` |
| `Stock Closing Balance` | `tabStock Closing Balance` | master | 17 | 7 | 0 | `-` |
| `Stock Entry Type` | `tabStock Entry Type` | master | 3 | 0 | 0 | `Prompt` |
| `UOM Category` | `tabUOM Category` | master | 1 | 0 | 0 | `field:category_name` |
| `Warehouse Type` | `tabWarehouse Type` | master | 1 | 0 | 0 | `Prompt` |
| `Warehouse` | `tabWarehouse` | tree-master | 21 | 7 | 0 | `-` |
| `Delivery Note` | `tabDelivery Note` | transaction | 102 | 37 | 6 | `naming_series:` |
| `Delivery Trip` | `tabDelivery Trip` | transaction | 14 | 7 | 1 | `naming_series:` |
| `Item Standard Cost` | `tabItem Standard Cost` | transaction | 7 | 4 | 0 | `naming_series:` |
| `Landed Cost Voucher` | `tabLanded Cost Voucher` | transaction | 7 | 2 | 4 | `naming_series:` |
| `Material Request` | `tabMaterial Request` | transaction | 23 | 11 | 1 | `naming_series:` |
| `Packing Slip` | `tabPacking Slip` | transaction | 10 | 5 | 1 | `MAT-PAC-.YYYY.-.#####` |
| `Pick List` | `tabPick List` | transaction | 20 | 6 | 1 | `naming_series:` |
| `Purchase Receipt` | `tabPurchase Receipt` | transaction | 90 | 29 | 5 | `naming_series:` |
| `Quality Inspection` | `tabQuality Inspection` | transaction | 22 | 9 | 1 | `naming_series:` |
| `Repost Item Valuation` | `tabRepost Item Valuation` | transaction | 25 | 5 | 0 | `hash` |
| `Serial and Batch Bundle` | `tabSerial and Batch Bundle` | transaction | 21 | 6 | 1 | `hash` |
| `Shipment` | `tabShipment` | transaction | 43 | 14 | 2 | `SHIPMENT-.#####` |
| `Stock Closing Entry` | `tabStock Closing Entry` | transaction | 6 | 2 | 0 | `naming_series:` |
| `Stock Entry` | `tabStock Entry` | transaction | 55 | 27 | 2 | `naming_series:` |
| `Stock Ledger Entry` | `tabStock Ledger Entry` | transaction | 31 | 7 | 0 | `MAT-SLE-.YYYY.-.#####` |
| `Stock Reconciliation` | `tabStock Reconciliation` | transaction | 13 | 5 | 1 | `naming_series:` |
| `Stock Reservation Entry` | `tabStock Reservation Entry` | transaction | 22 | 6 | 1 | `MAT-SRE-.YYYY.-.#####` |
| `Company Restriction` | `tabCompany Restriction` | child | 1 | 1 | 0 | `-` |
| `Delivery Note Item` | `tabDelivery Note Item` | child | 74 | 21 | 0 | `hash` |
| `Delivery Stop` | `tabDelivery Stop` | child | 16 | 5 | 0 | `-` |
| `Item Attribute Value` | `tabItem Attribute Value` | child | 2 | 0 | 0 | `-` |
| `Item Barcode` | `tabItem Barcode` | child | 3 | 1 | 0 | `hash` |
| `Item Customer Detail` | `tabItem Customer Detail` | child | 3 | 2 | 0 | `hash` |
| `Item Default` | `tabItem Default` | child | 21 | 21 | 0 | `-` |
| `Item Quality Inspection Parameter` | `tabItem Quality Inspection Parameter` | child | 8 | 2 | 0 | `hash` |
| `Item Reorder` | `tabItem Reorder` | child | 5 | 2 | 0 | `hash` |
| `Item Supplier` | `tabItem Supplier` | child | 2 | 1 | 0 | `-` |
| `Item Tax` | `tabItem Tax` | child | 5 | 2 | 0 | `-` |
| `Item Variant` | `tabItem Variant` | child | 2 | 1 | 0 | `-` |
| `Item Variant Attribute` | `tabItem Variant Attribute` | child | 8 | 2 | 0 | `-` |
| `Item Website Specification` | `tabItem Website Specification` | child | 2 | 0 | 0 | `-` |
| `Landed Cost Item` | `tabLanded Cost Item` | child | 12 | 2 | 0 | `-` |
| `Landed Cost Purchase Receipt` | `tabLanded Cost Purchase Receipt` | child | 5 | 1 | 0 | `-` |
| `Landed Cost Taxes and Charges` | `tabLanded Cost Taxes and Charges` | child | 11 | 2 | 0 | `-` |
| `Landed Cost Vendor Invoice` | `tabLanded Cost Vendor Invoice` | child | 2 | 1 | 0 | `-` |
| `Material Request Item` | `tabMaterial Request Item` | child | 41 | 15 | 0 | `hash` |
| `Packed Item` | `tabPacked Item` | child | 28 | 8 | 0 | `-` |
| `Packing Slip Item` | `tabPacking Slip Item` | child | 11 | 4 | 0 | `hash` |
| `Pick List Item` | `tabPick List Item` | child | 25 | 8 | 0 | `-` |
| `Price List Country` | `tabPrice List Country` | child | 1 | 1 | 0 | `-` |
| `Purchase Receipt Item` | `tabPurchase Receipt Item` | child | 89 | 28 | 0 | `hash` |
| `Quality Inspection Reading` | `tabQuality Inspection Reading` | child | 21 | 2 | 0 | `hash` |
| `Serial and Batch Entry` | `tabSerial and Batch Entry` | child | 18 | 4 | 0 | `-` |
| `Shipment Delivery Note` | `tabShipment Delivery Note` | child | 2 | 1 | 0 | `-` |
| `Shipment Parcel` | `tabShipment Parcel` | child | 5 | 0 | 0 | `-` |
| `Stock Entry Detail` | `tabStock Entry Detail` | child | 55 | 21 | 0 | `hash` |
| `Stock Reconciliation Item` | `tabStock Reconciliation Item` | child | 23 | 7 | 0 | `-` |
| `UOM Conversion Detail` | `tabUOM Conversion Detail` | child | 2 | 1 | 0 | `hash` |
| `Variant Field` | `tabVariant Field` | child | 1 | 0 | 0 | `-` |

## erpnext / Subcontracting (13)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Subcontracting BOM` | `tabSubcontracting BOM` | master | 9 | 5 | 0 | `format:SB-{####}` |
| `Subcontracting Inward Order` | `tabSubcontracting Inward Order` | transaction | 18 | 7 | 4 | `naming_series:` |
| `Subcontracting Order` | `tabSubcontracting Order` | transaction | 35 | 16 | 4 | `naming_series:` |
| `Subcontracting Receipt` | `tabSubcontracting Receipt` | transaction | 47 | 17 | 3 | `naming_series:` |
| `Subcontracting Inward Order Item` | `tabSubcontracting Inward Order Item` | child | 14 | 4 | 0 | `hash` |
| `Subcontracting Inward Order Received Item` | `tabSubcontracting Inward Order Received Item` | child | 15 | 4 | 0 | `-` |
| `Subcontracting Inward Order Secondary Item` | `tabSubcontracting Inward Order Secondary Item` | child | 8 | 4 | 0 | `-` |
| `Subcontracting Inward Order Service Item` | `tabSubcontracting Inward Order Service Item` | child | 9 | 3 | 0 | `hash` |
| `Subcontracting Order Item` | `tabSubcontracting Order Item` | child | 31 | 10 | 0 | `hash` |
| `Subcontracting Order Service Item` | `tabSubcontracting Order Service Item` | child | 10 | 3 | 0 | `hash` |
| `Subcontracting Order Supplied Item` | `tabSubcontracting Order Supplied Item` | child | 15 | 4 | 0 | `-` |
| `Subcontracting Receipt Item` | `tabSubcontracting Receipt Item` | child | 48 | 18 | 0 | `hash` |
| `Subcontracting Receipt Supplied Item` | `tabSubcontracting Receipt Supplied Item` | child | 21 | 8 | 0 | `Autoincrement` |

## erpnext / Support (11)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Support Settings` | `tabSupport Settings` | single | 14 | 0 | 1 | `-` |
| `Issue` | `tabIssue` | master | 34 | 10 | 0 | `naming_series:` |
| `Issue Priority` | `tabIssue Priority` | master | 1 | 0 | 0 | `Prompt` |
| `Issue Type` | `tabIssue Type` | master | 1 | 0 | 0 | `Prompt` |
| `Service Level Agreement` | `tabService Level Agreement` | master | 12 | 3 | 4 | `format:SLA-{document_type}-{service_level}` |
| `Warranty Claim` | `tabWarranty Claim` | master | 29 | 10 | 0 | `naming_series:` |
| `Pause SLA On Status` | `tabPause SLA On Status` | child | 1 | 0 | 0 | `-` |
| `SLA Fulfilled On Status` | `tabSLA Fulfilled On Status` | child | 1 | 0 | 0 | `-` |
| `Service Day` | `tabService Day` | child | 3 | 0 | 0 | `-` |
| `Service Level Priority` | `tabService Level Priority` | child | 4 | 1 | 0 | `-` |
| `Support Search Source` | `tabSupport Search Source` | child | 14 | 1 | 0 | `-` |

## erpnext / Telephony (5)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Call Log` | `tabCall Log` | master | 15 | 4 | 1 | `field:id` |
| `Incoming Call Settings` | `tabIncoming Call Settings` | master | 4 | 0 | 1 | `Prompt` |
| `Voice Call Settings` | `tabVoice Call Settings` | master | 5 | 1 | 0 | `field:user` |
| `Telephony Call Type` | `tabTelephony Call Type` | transaction | 2 | 1 | 0 | `field:call_type` |
| `Incoming Call Handling Schedule` | `tabIncoming Call Handling Schedule` | child | 4 | 1 | 0 | `-` |

## erpnext / Utilities (4)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Rename Tool` | `tabRename Tool` | single | 2 | 1 | 0 | `-` |
| `Video Settings` | `tabVideo Settings` | single | 3 | 0 | 0 | `-` |
| `Video` | `tabVideo` | master | 12 | 0 | 0 | `field:title` |
| `Portal User` | `tabPortal User` | child | 1 | 1 | 0 | `-` |

## frappe / Automation (9)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Assignment Rule` | `tabAssignment Rule` | master | 12 | 2 | 3 | `Prompt` |
| `Auto Repeat` | `tabAuto Repeat` | master | 18 | 3 | 2 | `format:AUT-AR-{#####}` |
| `Milestone` | `tabMilestone` | master | 5 | 2 | 0 | `-` |
| `Milestone Tracker` | `tabMilestone Tracker` | master | 3 | 1 | 0 | `format:{document_type}-{track_field}` |
| `Reminder` | `tabReminder` | master | 6 | 2 | 0 | `hash` |
| `Assignment Rule Day` | `tabAssignment Rule Day` | child | 1 | 0 | 0 | `-` |
| `Assignment Rule User` | `tabAssignment Rule User` | child | 2 | 1 | 0 | `-` |
| `Auto Repeat Day` | `tabAuto Repeat Day` | child | 1 | 0 | 0 | `-` |
| `Auto Repeat User` | `tabAuto Repeat User` | child | 1 | 1 | 0 | `-` |

## frappe / Contacts (7)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Address` | `tabAddress` | master | 15 | 1 | 1 | `-` |
| `Address Template` | `tabAddress Template` | master | 3 | 1 | 0 | `field:country` |
| `Contact` | `tabContact` | master | 22 | 5 | 3 | `By script` |
| `Gender` | `tabGender` | master | 1 | 0 | 0 | `field:gender` |
| `Salutation` | `tabSalutation` | master | 1 | 0 | 0 | `field:salutation` |
| `Contact Email` | `tabContact Email` | child | 2 | 0 | 0 | `-` |
| `Contact Phone` | `tabContact Phone` | child | 3 | 0 | 0 | `-` |

## frappe / Core (108)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Audit Trail` | `tabAudit Trail` | single | 4 | 1 | 0 | `-` |
| `Data Export` | `tabData Export` | single | 3 | 1 | 0 | `-` |
| `Document Naming Settings` | `tabDocument Naming Settings` | single | 8 | 0 | 1 | `-` |
| `Domain Settings` | `tabDomain Settings` | single | 0 | 0 | 1 | `-` |
| `Installed Applications` | `tabInstalled Applications` | single | 0 | 0 | 1 | `-` |
| `Log Settings` | `tabLog Settings` | single | 0 | 0 | 1 | `-` |
| `Navbar Settings` | `tabNavbar Settings` | single | 4 | 0 | 2 | `-` |
| `Permission Inspector` | `tabPermission Inspector` | single | 5 | 2 | 0 | `-` |
| `Role Permission for Page and Report` | `tabRole Permission for Page and Report` | single | 4 | 2 | 1 | `-` |
| `SMS Settings` | `tabSMS Settings` | single | 4 | 0 | 1 | `-` |
| `Security Settings` | `tabSecurity Settings` | single | 2 | 0 | 2 | `-` |
| `Session Default Settings` | `tabSession Default Settings` | single | 0 | 0 | 1 | `-` |
| `System Settings` | `tabSystem Settings` | single | 79 | 5 | 0 | `-` |
| `API Request Log` | `tabAPI Request Log` | master | 3 | 1 | 0 | `-` |
| `Access Log` | `tabAccess Log` | master | 10 | 1 | 0 | `hash` |
| `Activity Log` | `tabActivity Log` | master | 15 | 4 | 0 | `-` |
| `Background Task` | `tabBackground Task` | master | 21 | 2 | 0 | `field:task_id` |
| `Comment` | `tabComment` | master | 11 | 1 | 0 | `-` |
| `Communication` | `tabCommunication` | master | 34 | 5 | 1 | `-` |
| `Custom DocPerm` | `tabCustom DocPerm` | master | 19 | 1 | 0 | `hash` |
| `Custom Role` | `tabCustom Role` | master | 3 | 2 | 1 | `hash` |
| `Data Import` | `tabData Import` | master | 14 | 1 | 2 | `format:{reference_doctype} Import on {creation}` |
| `Data Import Log` | `tabData Import Log` | master | 8 | 1 | 0 | `-` |
| `Deleted Document` | `tabDeleted Document` | master | 5 | 0 | 0 | `-` |
| `DocShare` | `tabDocShare` | master | 9 | 2 | 0 | `hash` |
| `DocType` | `tabDocType` | master | 66 | 3 | 5 | `Prompt` |
| `DocType Layout` | `tabDocType Layout` | master | 9 | 5 | 2 | `field:title` |
| `DocType Settings Map` | `tabDocType Settings Map` | master | 4 | 2 | 1 | `-` |
| `Document Naming Rule` | `tabDocument Naming Rule` | master | 6 | 1 | 1 | `-` |
| `Document Share Key` | `tabDocument Share Key` | master | 4 | 1 | 0 | `hash` |
| `Domain` | `tabDomain` | master | 1 | 0 | 0 | `field:domain` |
| `Error Log` | `tabError Log` | master | 8 | 1 | 0 | `-` |
| `File` | `tabFile` | master | 17 | 2 | 0 | `-` |
| `Language` | `tabLanguage` | master | 9 | 1 | 0 | `field:language_code` |
| `Module Def` | `tabModule Def` | master | 5 | 2 | 0 | `field:module_name` |
| `Module Profile` | `tabModule Profile` | master | 1 | 0 | 1 | `field:module_profile_name` |
| `Package` | `tabPackage` | master | 4 | 0 | 0 | `Prompt` |
| `Package Import` | `tabPackage Import` | master | 4 | 0 | 0 | `format:Package Import at {creation}` |
| `Package Release` | `tabPackage Release` | master | 7 | 1 | 0 | `By script` |
| `Page` | `tabPage` | master | 7 | 2 | 1 | `field:page_name` |
| `Patch Log` | `tabPatch Log` | master | 3 | 0 | 0 | `hash` |
| `Permission Log` | `tabPermission Log` | master | 7 | 3 | 0 | `hash` |
| `Permission Type` | `tabPermission Type` | master | 2 | 1 | 0 | `-` |
| `Prepared Report` | `tabPrepared Report` | master | 7 | 0 | 0 | `hash` |
| `RQ Job` | `tabRQ Job` | master | 10 | 0 | 0 | `field:job_id` |
| `RQ Worker` | `tabRQ Worker` | master | 12 | 1 | 0 | `-` |
| `Recorder` | `tabRecorder` | master | 11 | 0 | 2 | `-` |
| `Report` | `tabReport` | master | 21 | 4 | 4 | `field:report_name` |
| `Role` | `tabRole` | master | 7 | 1 | 0 | `field:role_name` |
| `Role Profile` | `tabRole Profile` | master | 1 | 0 | 1 | `role_profile` |
| `SMS Log` | `tabSMS Log` | master | 7 | 0 | 0 | `SYS-SMS-.#####` |
| `Scheduled Job Log` | `tabScheduled Job Log` | master | 4 | 1 | 0 | `-` |
| `Scheduled Job Type` | `tabScheduled Job Type` | master | 8 | 2 | 0 | `-` |
| `Scheduler Event` | `tabScheduler Event` | master | 2 | 1 | 0 | `-` |
| `Server Script` | `tabServer Script` | master | 13 | 2 | 0 | `Prompt` |
| `Submission Queue` | `tabSubmission Queue` | master | 6 | 2 | 0 | `hash` |
| `Success Action` | `tabSuccess Action` | master | 5 | 1 | 0 | `field:ref_doctype` |
| `Translation` | `tabTranslation` | master | 7 | 1 | 0 | `hash` |
| `User` | `tabUser` | master | 67 | 6 | 8 | `-` |
| `User Group` | `tabUser Group` | master | 0 | 0 | 1 | `Prompt` |
| `User Invitation` | `tabUser Invitation` | master | 9 | 2 | 1 | `-` |
| `User Permission` | `tabUser Permission` | master | 7 | 3 | 0 | `-` |
| `User Type` | `tabUser Type` | master | 4 | 2 | 4 | `Prompt` |
| `Version` | `tabVersion` | master | 3 | 1 | 0 | `hash` |
| `View Log` | `tabView Log` | master | 3 | 1 | 0 | `-` |
| `DuckDB Sync` | `tabDuckDB Sync` | transaction | 3 | 2 | 1 | `-` |
| `Amended Document Naming Settings` | `tabAmended Document Naming Settings` | child | 2 | 1 | 0 | `-` |
| `Block Module` | `tabBlock Module` | child | 1 | 0 | 0 | `-` |
| `Communication Link` | `tabCommunication Link` | child | 4 | 1 | 0 | `-` |
| `Data Import Skipped Row` | `tabData Import Skipped Row` | child | 2 | 0 | 0 | `-` |
| `Data Import Value Mapping` | `tabData Import Value Mapping` | child | 11 | 1 | 0 | `-` |
| `DefaultValue` | `tabDefaultValue` | child | 2 | 0 | 0 | `hash` |
| `DocField` | `tabDocField` | child | 66 | 0 | 0 | `hash` |
| `DocPerm` | `tabDocPerm` | child | 18 | 1 | 0 | `hash` |
| `DocType Action` | `tabDocType Action` | child | 6 | 0 | 0 | `-` |
| `DocType Layout Child Table` | `tabDocType Layout Child Table` | child | 2 | 1 | 0 | `-` |
| `DocType Layout Field` | `tabDocType Layout Field` | child | 14 | 0 | 0 | `-` |
| `DocType Link` | `tabDocType Link` | child | 8 | 2 | 0 | `-` |
| `DocType Settings Map Item` | `tabDocType Settings Map Item` | child | 2 | 1 | 0 | `-` |
| `DocType State` | `tabDocType State` | child | 3 | 0 | 0 | `-` |
| `Doctype To Sync` | `tabDoctype To Sync` | child | 1 | 1 | 0 | `-` |
| `Document Naming Rule Condition` | `tabDocument Naming Rule Condition` | child | 3 | 0 | 0 | `-` |
| `DuckDB Sync Item` | `tabDuckDB Sync Item` | child | 2 | 0 | 0 | `-` |
| `Dynamic Link` | `tabDynamic Link` | child | 3 | 1 | 0 | `-` |
| `Has Domain` | `tabHas Domain` | child | 1 | 1 | 0 | `-` |
| `Has Role` | `tabHas Role` | child | 1 | 1 | 0 | `hash` |
| `Installed Application` | `tabInstalled Application` | child | 5 | 0 | 0 | `-` |
| `Log Setting User` | `tabLog Setting User` | child | 1 | 1 | 0 | `field:user` |
| `Logs To Clear` | `tabLogs To Clear` | child | 2 | 1 | 0 | `hash` |
| `Navbar Item` | `tabNavbar Item` | child | 8 | 0 | 0 | `-` |
| `Recorder Query` | `tabRecorder Query` | child | 8 | 0 | 0 | `-` |
| `Recorder Suggested Index` | `tabRecorder Suggested Index` | child | 2 | 0 | 0 | `-` |
| `Report Column` | `tabReport Column` | child | 5 | 0 | 0 | `-` |
| `Report Filter` | `tabReport Filter` | child | 7 | 0 | 0 | `-` |
| `SMS Parameter` | `tabSMS Parameter` | child | 3 | 0 | 0 | `-` |
| `Security Settings Contact` | `tabSecurity Settings Contact` | child | 2 | 0 | 0 | `-` |
| `Security Settings Language` | `tabSecurity Settings Language` | child | 1 | 1 | 0 | `-` |
| `Session Default` | `tabSession Default` | child | 1 | 1 | 0 | `-` |
| `User Document Type` | `tabUser Document Type` | child | 12 | 1 | 0 | `-` |
| `User Email` | `tabUser Email` | child | 5 | 1 | 0 | `-` |
| `User Group Member` | `tabUser Group Member` | child | 1 | 1 | 0 | `-` |
| `User Role` | `tabUser Role` | child | 1 | 1 | 0 | `-` |
| `User Role Profile` | `tabUser Role Profile` | child | 1 | 1 | 0 | `-` |
| `User Select Document Type` | `tabUser Select Document Type` | child | 1 | 1 | 0 | `-` |
| `User Session Display` | `tabUser Session Display` | child | 6 | 0 | 0 | `-` |
| `User Social Login` | `tabUser Social Login` | child | 3 | 0 | 0 | `-` |
| `User Type Module` | `tabUser Type Module` | child | 1 | 1 | 0 | `-` |
| `User Workspaces` | `tabUser Workspaces` | child | 1 | 1 | 0 | `-` |

## frappe / Custom (5)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Customize Form` | `tabCustomize Form` | single | 40 | 3 | 4 | `DL.####` |
| `Client Script` | `tabClient Script` | master | 5 | 2 | 0 | `Prompt` |
| `Custom Field` | `tabCustom Field` | master | 58 | 2 | 0 | `-` |
| `Property Setter` | `tabProperty Setter` | master | 10 | 2 | 0 | `-` |
| `Customize Form Field` | `tabCustomize Form Field` | child | 58 | 0 | 0 | `hash` |

## frappe / Desk (59)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Bulk Update` | `tabBulk Update` | single | 5 | 1 | 0 | `-` |
| `Desktop Settings` | `tabDesktop Settings` | single | 2 | 0 | 0 | `-` |
| `Global Search Settings` | `tabGlobal Search Settings` | single | 0 | 0 | 1 | `-` |
| `System Console` | `tabSystem Console` | single | 5 | 0 | 0 | `-` |
| `System Health Report` | `tabSystem Health Report` | single | 29 | 1 | 5 | `-` |
| `Calendar View` | `tabCalendar View` | master | 5 | 1 | 0 | `Prompt` |
| `Console Log` | `tabConsole Log` | master | 3 | 0 | 0 | `format:Log on {timestamp}` |
| `Custom HTML Block` | `tabCustom HTML Block` | master | 4 | 0 | 1 | `prompt` |
| `Dashboard` | `tabDashboard` | master | 5 | 1 | 2 | `field:dashboard_name` |
| `Dashboard Chart` | `tabDashboard Chart` | master | 31 | 6 | 2 | `field:chart_name` |
| `Dashboard Chart Source` | `tabDashboard Chart Source` | master | 3 | 1 | 0 | `field:source_name` |
| `Dashboard Settings` | `tabDashboard Settings` | master | 2 | 1 | 0 | `Prompt` |
| `Desktop Icon` | `tabDesktop Icon` | master | 16 | 2 | 1 | `field:label` |
| `Desktop Layout` | `tabDesktop Layout` | master | 2 | 1 | 0 | `field:user` |
| `Document Template` | `tabDocument Template` | master | 5 | 1 | 0 | `hash` |
| `Event` | `tabEvent` | master | 32 | 2 | 3 | `EV.#####` |
| `Form Tour` | `tabForm Tour` | master | 17 | 6 | 1 | `field:title` |
| `Kanban Board` | `tabKanban Board` | master | 7 | 1 | 1 | `field:kanban_board_name` |
| `List Filter` | `tabList Filter` | master | 8 | 2 | 0 | `-` |
| `List View Settings` | `tabList View Settings` | master | 9 | 0 | 0 | `Prompt` |
| `Module Onboarding` | `tabModule Onboarding` | master | 3 | 1 | 2 | `Prompt` |
| `Note` | `tabNote` | master | 6 | 0 | 1 | `hash` |
| `Notification Log` | `tabNotification Log` | master | 14 | 4 | 0 | `-` |
| `Notification Settings` | `tabNotification Settings` | master | 9 | 1 | 2 | `Prompt` |
| `Notification Type` | `tabNotification Type` | master | 2 | 0 | 0 | `field:type_name` |
| `Number Card` | `tabNumber Card` | master | 22 | 5 | 0 | `-` |
| `Onboarding Step` | `tabOnboarding Step` | master | 24 | 3 | 0 | `prompt` |
| `Route History` | `tabRoute History` | master | 2 | 1 | 0 | `-` |
| `Tag` | `tabTag` | master | 1 | 0 | 0 | `Prompt` |
| `Tag Link` | `tabTag Link` | master | 4 | 2 | 0 | `-` |
| `ToDo` | `tabToDo` | master | 13 | 5 | 0 | `hash` |
| `Workspace` | `tabWorkspace` | master | 20 | 4 | 8 | `field:label` |
| `Workspace Customization` | `tabWorkspace Customization` | master | 8 | 1 | 2 | `field:workspace` |
| `Workspace Sidebar` | `tabWorkspace Sidebar` | master | 7 | 2 | 1 | `field:title` |
| `Dashboard Chart Field` | `tabDashboard Chart Field` | child | 2 | 0 | 0 | `-` |
| `Dashboard Chart Link` | `tabDashboard Chart Link` | child | 2 | 1 | 0 | `-` |
| `Event Notifications` | `tabEvent Notifications` | child | 4 | 0 | 0 | `-` |
| `Event Participants` | `tabEvent Participants` | child | 4 | 1 | 0 | `-` |
| `Form Tour Step` | `tabForm Tour Step` | child | 22 | 1 | 0 | `-` |
| `Global Search DocType` | `tabGlobal Search DocType` | child | 1 | 1 | 0 | `-` |
| `Kanban Board Column` | `tabKanban Board Column` | child | 4 | 0 | 0 | `-` |
| `Note Seen By` | `tabNote Seen By` | child | 1 | 1 | 0 | `-` |
| `Notification Subscribed Document` | `tabNotification Subscribed Document` | child | 1 | 1 | 0 | `-` |
| `Notification Type Preference` | `tabNotification Type Preference` | child | 1 | 1 | 0 | `-` |
| `Number Card Link` | `tabNumber Card Link` | child | 1 | 1 | 0 | `-` |
| `Onboarding Permission` | `tabOnboarding Permission` | child | 1 | 1 | 0 | `-` |
| `Onboarding Step Map` | `tabOnboarding Step Map` | child | 1 | 1 | 0 | `-` |
| `System Health Report Errors` | `tabSystem Health Report Errors` | child | 2 | 0 | 0 | `-` |
| `System Health Report Failing Jobs` | `tabSystem Health Report Failing Jobs` | child | 2 | 1 | 0 | `-` |
| `System Health Report Queue` | `tabSystem Health Report Queue` | child | 2 | 0 | 0 | `-` |
| `System Health Report Tables` | `tabSystem Health Report Tables` | child | 2 | 0 | 0 | `-` |
| `System Health Report Workers` | `tabSystem Health Report Workers` | child | 4 | 0 | 0 | `-` |
| `Workspace Chart` | `tabWorkspace Chart` | child | 2 | 1 | 0 | `-` |
| `Workspace Custom Block` | `tabWorkspace Custom Block` | child | 2 | 1 | 0 | `-` |
| `Workspace Link` | `tabWorkspace Link` | child | 14 | 3 | 0 | `-` |
| `Workspace Number Card` | `tabWorkspace Number Card` | child | 2 | 1 | 0 | `-` |
| `Workspace Quick List` | `tabWorkspace Quick List` | child | 3 | 1 | 0 | `-` |
| `Workspace Shortcut` | `tabWorkspace Shortcut` | child | 12 | 3 | 0 | `-` |
| `Workspace Sidebar Item` | `tabWorkspace Sidebar Item` | child | 16 | 0 | 0 | `hash` |

## frappe / Email (17)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Auto Email Report` | `tabAuto Email Report` | master | 20 | 3 | 0 | `-` |
| `Document Follow` | `tabDocument Follow` | master | 3 | 2 | 0 | `-` |
| `Email Account` | `tabEmail Account` | master | 60 | 4 | 2 | `field:email_account_name` |
| `Email Domain` | `tabEmail Domain` | master | 15 | 0 | 0 | `field:domain_name` |
| `Email Flag Queue` | `tabEmail Flag Queue` | master | 5 | 0 | 0 | `-` |
| `Email Group` | `tabEmail Group` | master | 6 | 2 | 0 | `field:title` |
| `Email Group Member` | `tabEmail Group Member` | master | 3 | 1 | 0 | `hash` |
| `Email Queue` | `tabEmail Queue` | master | 20 | 3 | 1 | `hash` |
| `Email Rule` | `tabEmail Rule` | master | 2 | 0 | 0 | `field:email_id` |
| `Email Template` | `tabEmail Template` | master | 5 | 1 | 0 | `Prompt` |
| `Email Unsubscribe` | `tabEmail Unsubscribe` | master | 4 | 1 | 0 | `-` |
| `Notification` | `tabNotification` | master | 33 | 6 | 1 | `Prompt` |
| `Unhandled Email` | `tabUnhandled Email` | master | 5 | 1 | 0 | `-` |
| `Email Queue Recipient` | `tabEmail Queue Recipient` | child | 3 | 0 | 0 | `-` |
| `IMAP Folder` | `tabIMAP Folder` | child | 4 | 1 | 0 | `-` |
| `Notification Recipient` | `tabNotification Recipient` | child | 5 | 1 | 0 | `-` |
| `Reply To Address` | `tabReply To Address` | child | 2 | 0 | 0 | `-` |

## frappe / Geo (2)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Country` | `tabCountry` | master | 5 | 0 | 0 | `field:country_name` |
| `Currency` | `tabCurrency` | master | 8 | 0 | 0 | `field:currency_name` |

## frappe / Integrations (24)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Geolocation Settings` | `tabGeolocation Settings` | single | 4 | 0 | 0 | `-` |
| `Google Settings` | `tabGoogle Settings` | single | 6 | 0 | 0 | `-` |
| `LDAP Settings` | `tabLDAP Settings` | single | 27 | 2 | 1 | `-` |
| `OAuth Provider Settings` | `tabOAuth Provider Settings` | single | 1 | 0 | 0 | `-` |
| `OAuth Settings` | `tabOAuth Settings` | single | 11 | 0 | 0 | `-` |
| `Push Notification Settings` | `tabPush Notification Settings` | single | 3 | 0 | 0 | `-` |
| `Connected App` | `tabConnected App` | master | 10 | 0 | 2 | `-` |
| `Google Calendar` | `tabGoogle Calendar` | master | 10 | 1 | 0 | `field:calendar_name` |
| `Google Contacts` | `tabGoogle Contacts` | master | 8 | 0 | 0 | `format:GC-{email_id}` |
| `Integration Request` | `tabIntegration Request` | master | 13 | 1 | 0 | `-` |
| `OAuth Authorization Code` | `tabOAuth Authorization Code` | master | 10 | 2 | 0 | `field:authorization_code` |
| `OAuth Bearer Token` | `tabOAuth Bearer Token` | master | 8 | 2 | 0 | `hash` |
| `OAuth Client` | `tabOAuth Client` | master | 19 | 1 | 1 | `-` |
| `Slack Webhook URL` | `tabSlack Webhook URL` | master | 3 | 0 | 0 | `field:webhook_name` |
| `Social Login Key` | `tabSocial Login Key` | master | 17 | 0 | 0 | `-` |
| `Token Cache` | `tabToken Cache` | master | 9 | 2 | 1 | `format:{connected_app}-{user}` |
| `Webhook` | `tabWebhook` | master | 14 | 1 | 2 | `prompt` |
| `Webhook Request Log` | `tabWebhook Request Log` | master | 12 | 2 | 0 | `hash` |
| `LDAP Group Mapping` | `tabLDAP Group Mapping` | child | 2 | 1 | 0 | `-` |
| `OAuth Client Role` | `tabOAuth Client Role` | child | 1 | 1 | 0 | `-` |
| `OAuth Scope` | `tabOAuth Scope` | child | 1 | 0 | 0 | `-` |
| `Query Parameters` | `tabQuery Parameters` | child | 2 | 0 | 0 | `-` |
| `Webhook Data` | `tabWebhook Data` | child | 2 | 0 | 0 | `-` |
| `Webhook Header` | `tabWebhook Header` | child | 2 | 0 | 0 | `-` |

## frappe / Printing (8)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Print Settings` | `tabPrint Settings` | single | 16 | 1 | 0 | `-` |
| `Letter Head` | `tabLetter Head` | master | 21 | 1 | 0 | `field:letter_head_name` |
| `Network Printer Settings` | `tabNetwork Printer Settings` | master | 3 | 0 | 0 | `Prompt` |
| `Print Format` | `tabPrint Format` | master | 33 | 4 | 0 | `Prompt` |
| `Print Format Field Template` | `tabPrint Format Field Template` | master | 6 | 2 | 0 | `Prompt` |
| `Print Format Snippet` | `tabPrint Format Snippet` | master | 5 | 2 | 0 | `Prompt` |
| `Print Heading` | `tabPrint Heading` | master | 2 | 0 | 0 | `field:print_heading` |
| `Print Style` | `tabPrint Style` | master | 5 | 0 | 0 | `field:print_style_name` |

## frappe / Website (39)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `About Us Settings` | `tabAbout Us Settings` | single | 7 | 0 | 2 | `-` |
| `Contact Us Settings` | `tabContact Us Settings` | single | 15 | 0 | 0 | `-` |
| `Portal Settings` | `tabPortal Settings` | single | 3 | 1 | 2 | `-` |
| `Website Script` | `tabWebsite Script` | single | 1 | 0 | 0 | `-` |
| `Website Settings` | `tabWebsite Settings` | single | 38 | 3 | 3 | `-` |
| `Color` | `tabColor` | master | 1 | 0 | 0 | `Prompt` |
| `Discussion Reply` | `tabDiscussion Reply` | master | 2 | 1 | 0 | `REPLY.####` |
| `Discussion Topic` | `tabDiscussion Topic` | master | 3 | 1 | 0 | `TOPIC.####` |
| `Help Article` | `tabHelp Article` | master | 10 | 1 | 0 | `-` |
| `Help Category` | `tabHelp Category` | master | 5 | 0 | 0 | `-` |
| `Personal Data Deletion Request` | `tabPersonal Data Deletion Request` | master | 3 | 0 | 1 | `-` |
| `Personal Data Download Request` | `tabPersonal Data Download Request` | master | 3 | 2 | 0 | `-` |
| `UTM Campaign` | `tabUTM Campaign` | master | 2 | 0 | 0 | `prompt` |
| `UTM Medium` | `tabUTM Medium` | master | 2 | 0 | 0 | `prompt` |
| `UTM Source` | `tabUTM Source` | master | 2 | 0 | 0 | `prompt` |
| `Web Form` | `tabWeb Form` | master | 40 | 4 | 2 | `-` |
| `Web Form Request` | `tabWeb Form Request` | master | 6 | 1 | 1 | `hash` |
| `Web Page` | `tabWeb Page` | master | 29 | 3 | 1 | `-` |
| `Web Page View` | `tabWeb Page View` | master | 12 | 0 | 0 | `-` |
| `Web Template` | `tabWeb Template` | master | 4 | 1 | 1 | `Prompt` |
| `Website Route Meta` | `tabWebsite Route Meta` | master | 0 | 0 | 1 | `Prompt` |
| `Website Sidebar` | `tabWebsite Sidebar` | master | 1 | 0 | 1 | `field:title` |
| `Website Slideshow` | `tabWebsite Slideshow` | master | 2 | 0 | 1 | `field:slideshow_name` |
| `Website Theme` | `tabWebsite Theme` | master | 19 | 6 | 1 | `field:theme` |
| `About Us Team Member` | `tabAbout Us Team Member` | child | 3 | 0 | 0 | `-` |
| `Company History` | `tabCompany History` | child | 2 | 0 | 0 | `-` |
| `Personal Data Deletion Step` | `tabPersonal Data Deletion Step` | child | 5 | 0 | 0 | `-` |
| `Portal Menu Item` | `tabPortal Menu Item` | child | 6 | 2 | 0 | `-` |
| `Social Link Settings` | `tabSocial Link Settings` | child | 3 | 0 | 0 | `-` |
| `Top Bar Item` | `tabTop Bar Item` | child | 5 | 0 | 0 | `-` |
| `Web Form Field` | `tabWeb Form Field` | child | 18 | 0 | 0 | `-` |
| `Web Form List Column` | `tabWeb Form List Column` | child | 4 | 0 | 0 | `autoincrement` |
| `Web Page Block` | `tabWeb Page Block` | child | 13 | 1 | 0 | `-` |
| `Web Template Field` | `tabWeb Template Field` | child | 6 | 0 | 0 | `-` |
| `Website Meta Tag` | `tabWebsite Meta Tag` | child | 2 | 0 | 0 | `-` |
| `Website Route Redirect` | `tabWebsite Route Redirect` | child | 4 | 0 | 0 | `-` |
| `Website Sidebar Item` | `tabWebsite Sidebar Item` | child | 3 | 0 | 0 | `-` |
| `Website Slideshow Item` | `tabWebsite Slideshow Item` | child | 4 | 0 | 0 | `-` |
| `Website Theme Ignore App` | `tabWebsite Theme Ignore App` | child | 1 | 0 | 0 | `-` |

## frappe / Workflow (9)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Workflow` | `tabWorkflow` | master | 8 | 1 | 2 | `field:workflow_name` |
| `Workflow Action` | `tabWorkflow Action` | master | 7 | 4 | 1 | `-` |
| `Workflow Action Master` | `tabWorkflow Action Master` | master | 1 | 0 | 0 | `field:workflow_action_name` |
| `Workflow State` | `tabWorkflow State` | master | 3 | 0 | 0 | `field:workflow_state_name` |
| `Workflow Transition Tasks` | `tabWorkflow Transition Tasks` | master | 0 | 0 | 1 | `prompt` |
| `Workflow Action Permitted Role` | `tabWorkflow Action Permitted Role` | child | 1 | 1 | 0 | `hash` |
| `Workflow Document State` | `tabWorkflow Document State` | child | 12 | 3 | 0 | `-` |
| `Workflow Transition` | `tabWorkflow Transition` | child | 9 | 5 | 0 | `-` |
| `Workflow Transition Task` | `tabWorkflow Transition Task` | child | 4 | 0 | 0 | `-` |

## hrms / HR (116)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Employee Attendance Tool` | `tabEmployee Attendance Tool` | single | 13 | 7 | 0 | `-` |
| `HR Settings` | `tabHR Settings` | single | 34 | 9 | 0 | `-` |
| `Leave Control Panel` | `tabLeave Control Panel` | single | 15 | 9 | 0 | `-` |
| `Shift Assignment Tool` | `tabShift Assignment Tool` | single | 17 | 11 | 0 | `-` |
| `Appointment Letter` | `tabAppointment Letter` | master | 7 | 3 | 1 | `HR-APP-LETTER-.#####` |
| `Appointment Letter Template` | `tabAppointment Letter Template` | master | 3 | 0 | 1 | `field:template_name` |
| `Appraisal Cycle` | `tabAppraisal Cycle` | master | 12 | 4 | 1 | `field:cycle_name` |
| `Appraisal Template` | `tabAppraisal Template` | master | 2 | 0 | 2 | `field:template_title` |
| `Daily Work Summary` | `tabDaily Work Summary` | master | 3 | 1 | 0 | `-` |
| `Daily Work Summary Group` | `tabDaily Work Summary Group` | master | 5 | 1 | 1 | `Prompt` |
| `Employee Checkin` | `tabEmployee Checkin` | master | 17 | 4 | 0 | `EMP-CKIN-.MM.-.YYYY.-.######` |
| `Employee Feedback Criteria` | `tabEmployee Feedback Criteria` | master | 1 | 0 | 0 | `field:criteria` |
| `Employee Grade` | `tabEmployee Grade` | master | 3 | 2 | 0 | `Prompt` |
| `Employee Health Insurance` | `tabEmployee Health Insurance` | master | 1 | 0 | 0 | `field:health_insurance_name` |
| `Employee Onboarding Template` | `tabEmployee Onboarding Template` | master | 5 | 4 | 1 | `HR-EMP-ONT-.#####` |
| `Employee Separation Template` | `tabEmployee Separation Template` | master | 5 | 4 | 1 | `HR-EMP-STP-.#####` |
| `Employee Skill Map` | `tabEmployee Skill Map` | master | 3 | 1 | 2 | `field:employee` |
| `Employment Type` | `tabEmployment Type` | master | 1 | 0 | 0 | `field:employee_type_name` |
| `Expense Claim Type` | `tabExpense Claim Type` | master | 3 | 0 | 1 | `field:expense_type` |
| `Grievance Type` | `tabGrievance Type` | master | 1 | 0 | 0 | `Prompt` |
| `Identification Document Type` | `tabIdentification Document Type` | master | 1 | 0 | 0 | `field:identification_document_type` |
| `Interest` | `tabInterest` | master | 1 | 0 | 0 | `field:interest` |
| `Interview Type` | `tabInterview Type` | master | 4 | 1 | 2 | `field:interview_type_name` |
| `Job Applicant` | `tabJob Applicant` | master | 18 | 7 | 0 | `HR-APP-.YYYY.-.#####` |
| `Job Applicant Source` | `tabJob Applicant Source` | master | 2 | 0 | 0 | `field:source_name` |
| `Job Offer Term Template` | `tabJob Offer Term Template` | master | 1 | 0 | 1 | `field:title` |
| `Job Opening` | `tabJob Opening` | master | 26 | 9 | 0 | `HR-OPN-.YYYY.-.####` |
| `Job Opening Template` | `tabJob Opening Template` | master | 11 | 5 | 0 | `field:template_title` |
| `Job Requisition` | `tabJob Requisition` | master | 17 | 6 | 0 | `naming_series:` |
| `KRA` | `tabKRA` | master | 2 | 0 | 0 | `field:title` |
| `Leave Block List` | `tabLeave Block List` | master | 4 | 2 | 2 | `field:leave_block_list_name` |
| `Leave Period` | `tabLeave Period` | master | 5 | 2 | 0 | `HR-LPR-.YYYY.-.#####` |
| `Leave Type` | `tabLeave Type` | master | 23 | 1 | 0 | `field:leave_type_name` |
| `Offer Term` | `tabOffer Term` | master | 1 | 0 | 0 | `field:offer_term` |
| `Overtime Type` | `tabOvertime Type` | master | 9 | 1 | 1 | `Prompt` |
| `PWA Notification` | `tabPWA Notification` | master | 6 | 3 | 0 | `autoincrement` |
| `Purpose of Travel` | `tabPurpose of Travel` | master | 1 | 0 | 0 | `field:purpose_of_travel` |
| `Shift Location` | `tabShift Location` | master | 5 | 0 | 0 | `field:location_name` |
| `Shift Schedule Assignment` | `tabShift Schedule Assignment` | master | 8 | 4 | 0 | `HR-SHSA-.YY.-.MM.-.#####` |
| `Shift Type` | `tabShift Type` | master | 21 | 2 | 0 | `prompt` |
| `Skill` | `tabSkill` | master | 2 | 0 | 0 | `field:skill_name` |
| `Training Program` | `tabTraining Program` | master | 9 | 3 | 0 | `field:training_program` |
| `Vehicle Service Item` | `tabVehicle Service Item` | master | 1 | 0 | 0 | `field:service_item` |
| `Goal` | `tabGoal` | tree-master | 17 | 6 | 0 | `format:HR-GOAL-{YYYY}-{####}` |
| `Appraisal` | `tabAppraisal` | transaction | 20 | 7 | 3 | `naming_series:` |
| `Attendance` | `tabAttendance` | transaction | 22 | 9 | 0 | `naming_series:` |
| `Attendance Request` | `tabAttendance Request` | transaction | 13 | 5 | 0 | `HR-ARQ-.YY.-.MM.-.#####` |
| `Compensatory Leave Request` | `tabCompensatory Leave Request` | transaction | 11 | 5 | 0 | `HR-CMP-.YY.-.MM.-.#####` |
| `Employee Advance` | `tabEmployee Advance` | transaction | 19 | 7 | 0 | `naming_series:` |
| `Employee Grievance` | `tabEmployee Grievance` | transaction | 19 | 9 | 0 | `HR-GRIEV-.YYYY.-.#####` |
| `Employee Onboarding` | `tabEmployee Onboarding` | transaction | 16 | 11 | 1 | `HR-EMP-ONB-.YYYY.-.#####` |
| `Employee Performance Feedback` | `tabEmployee Performance Feedback` | transaction | 15 | 10 | 1 | `format:HR-PF-{YYYY}-{#####}` |
| `Employee Promotion` | `tabEmployee Promotion` | transaction | 9 | 5 | 1 | `HR-EMP-PRO-.YYYY.-.#####` |
| `Employee Referral` | `tabEmployee Referral` | transaction | 20 | 4 | 0 | `format:HR-REF-{####}` |
| `Employee Separation` | `tabEmployee Separation` | transaction | 14 | 8 | 1 | `HR-EMP-SEP-.YYYY.-.#####` |
| `Employee Transfer` | `tabEmployee Transfer` | transaction | 10 | 6 | 1 | `HR-EMP-TRN-.YYYY.-.#####` |
| `Exit Interview` | `tabExit Interview` | transaction | 18 | 7 | 1 | `naming_series:` |
| `Expense Claim` | `tabExpense Claim` | transaction | 36 | 15 | 3 | `naming_series:` |
| `Full and Final Statement` | `tabFull and Final Statement` | transaction | 13 | 5 | 3 | `HR-FNF-.YYYY.-.#####` |
| `Holiday List Assignment` | `tabHoliday List Assignment` | transaction | 8 | 3 | 0 | `naming_series:` |
| `Interview` | `tabInterview` | transaction | 14 | 5 | 1 | `HR-INT-.YYYY.-.####` |
| `Interview Feedback` | `tabInterview Feedback` | transaction | 8 | 5 | 1 | `HR-INT-FEED-.####` |
| `Job Offer` | `tabJob Offer` | transaction | 13 | 8 | 1 | `HR-OFF-.YYYY.-.#####` |
| `Leave Adjustment` | `tabLeave Adjustment` | transaction | 14 | 4 | 0 | `naming_series:` |
| `Leave Allocation` | `tabLeave Allocation` | transaction | 21 | 9 | 1 | `naming_series:` |
| `Leave Application` | `tabLeave Application` | transaction | 22 | 8 | 0 | `naming_series:` |
| `Leave Encashment` | `tabLeave Encashment` | transaction | 22 | 12 | 0 | `HR-ENC-.YYYY.-.#####` |
| `Leave Ledger Entry` | `tabLeave Ledger Entry` | transaction | 14 | 6 | 0 | `-` |
| `Leave Policy` | `tabLeave Policy` | transaction | 2 | 1 | 1 | `HR-LPOL-.YYYY.-.#####` |
| `Leave Policy Assignment` | `tabLeave Policy Assignment` | transaction | 11 | 5 | 0 | `HR-LPOL-ASSGN-.#####` |
| `Overtime Slip` | `tabOvertime Slip` | transaction | 12 | 6 | 1 | `HR-OT-SLIP-.#####` |
| `Shift Assignment` | `tabShift Assignment` | transaction | 13 | 9 | 0 | `HR-SHA-.YY.-.MM.-.#####` |
| `Shift Request` | `tabShift Request` | transaction | 10 | 6 | 0 | `HR-SHR-.YY.-.MM.-.#####` |
| `Shift Schedule` | `tabShift Schedule` | transaction | 3 | 2 | 1 | `prompt` |
| `Staffing Plan` | `tabStaffing Plan` | transaction | 6 | 3 | 1 | `prompt` |
| `Training Event` | `tabTraining Event` | transaction | 18 | 4 | 1 | `field:event_name` |
| `Training Feedback` | `tabTraining Feedback` | transaction | 9 | 4 | 0 | `HR-TRF-.YYYY.-.#####` |
| `Training Result` | `tabTraining Result` | transaction | 3 | 2 | 1 | `HR-TRR-.YYYY.-.#####` |
| `Travel Request` | `tabTravel Request` | transaction | 20 | 6 | 2 | `HR-TRQ-.YYYY.-.#####` |
| `Vehicle Log` | `tabVehicle Log` | transaction | 13 | 4 | 1 | `naming_series:` |
| `Appointment Letter content` | `tabAppointment Letter content` | child | 2 | 0 | 0 | `-` |
| `Appraisal Goal` | `tabAppraisal Goal` | child | 4 | 0 | 0 | `hash` |
| `Appraisal KRA` | `tabAppraisal KRA` | child | 4 | 1 | 0 | `hash` |
| `Appraisal Template Goal` | `tabAppraisal Template Goal` | child | 2 | 1 | 0 | `hash` |
| `Appraisee` | `tabAppraisee` | child | 6 | 4 | 0 | `-` |
| `Daily Work Summary Group User` | `tabDaily Work Summary Group User` | child | 2 | 1 | 0 | `-` |
| `Department Approver` | `tabDepartment Approver` | child | 1 | 1 | 0 | `hash` |
| `Designation Skill` | `tabDesignation Skill` | child | 1 | 1 | 0 | `-` |
| `Earned Leave Schedule` | `tabEarned Leave Schedule` | child | 7 | 0 | 0 | `-` |
| `Employee Boarding Activity` | `tabEmployee Boarding Activity` | child | 9 | 3 | 0 | `-` |
| `Employee Feedback Rating` | `tabEmployee Feedback Rating` | child | 3 | 1 | 0 | `hash` |
| `Employee Property History` | `tabEmployee Property History` | child | 4 | 0 | 0 | `-` |
| `Employee Skill` | `tabEmployee Skill` | child | 3 | 1 | 0 | `-` |
| `Employee Training` | `tabEmployee Training` | child | 2 | 1 | 0 | `-` |
| `Expected Skill Set` | `tabExpected Skill Set` | child | 2 | 1 | 0 | `-` |
| `Expense Claim Account` | `tabExpense Claim Account` | child | 2 | 2 | 0 | `-` |
| `Expense Claim Advance` | `tabExpense Claim Advance` | child | 15 | 2 | 0 | `-` |
| `Expense Claim Detail` | `tabExpense Claim Detail` | child | 10 | 4 | 0 | `-` |
| `Expense Taxes and Charges` | `tabExpense Taxes and Charges` | child | 9 | 3 | 0 | `hash` |
| `Full and Final Asset` | `tabFull and Final Asset` | child | 9 | 2 | 0 | `-` |
| `Full and Final Outstanding Statement` | `tabFull and Final Outstanding Statement` | child | 8 | 2 | 0 | `-` |
| `Interview Detail` | `tabInterview Detail` | child | 1 | 1 | 0 | `-` |
| `Interviewer` | `tabInterviewer` | child | 1 | 1 | 0 | `-` |
| `Job Offer Term` | `tabJob Offer Term` | child | 2 | 1 | 0 | `-` |
| `Leave Block List Allow` | `tabLeave Block List Allow` | child | 1 | 1 | 0 | `-` |
| `Leave Block List Date` | `tabLeave Block List Date` | child | 2 | 0 | 0 | `-` |
| `Leave Policy Detail` | `tabLeave Policy Detail` | child | 2 | 1 | 0 | `-` |
| `Overtime Details` | `tabOvertime Details` | child | 6 | 2 | 0 | `-` |
| `Overtime Salary Component` | `tabOvertime Salary Component` | child | 1 | 1 | 0 | `-` |
| `Skill Assessment` | `tabSkill Assessment` | child | 2 | 1 | 0 | `-` |
| `Staffing Plan Detail` | `tabStaffing Plan Detail` | child | 7 | 1 | 0 | `-` |
| `Training Event Employee` | `tabTraining Event Employee` | child | 6 | 2 | 0 | `-` |
| `Training Result Employee` | `tabTraining Result Employee` | child | 6 | 2 | 0 | `-` |
| `Travel Itinerary` | `tabTravel Itinerary` | child | 13 | 0 | 0 | `-` |
| `Travel Request Costing` | `tabTravel Request Costing` | child | 5 | 1 | 0 | `-` |
| `Vehicle Service` | `tabVehicle Service` | child | 4 | 1 | 0 | `-` |

## hrms / Payroll (43)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Bulk Salary Structure Assignment` | `tabBulk Salary Structure Assignment` | single | 11 | 10 | 0 | `-` |
| `Payroll Settings` | `tabPayroll Settings` | single | 18 | 3 | 0 | `-` |
| `Employee Benefit Ledger` | `tabEmployee Benefit Ledger` | master | 14 | 5 | 0 | `-` |
| `Employee Tax Exemption Category` | `tabEmployee Tax Exemption Category` | master | 3 | 0 | 0 | `Prompt` |
| `Employee Tax Exemption Sub Category` | `tabEmployee Tax Exemption Sub Category` | master | 4 | 1 | 0 | `Prompt` |
| `Gratuity Rule` | `tabGratuity Rule` | master | 5 | 0 | 2 | `Prompt` |
| `Payroll Period` | `tabPayroll Period` | master | 3 | 1 | 1 | `Prompt` |
| `Salary Component` | `tabSalary Component` | master | 26 | 0 | 1 | `field:salary_component` |
| `Additional Salary` | `tabAdditional Salary` | transaction | 19 | 7 | 0 | `naming_series:` |
| `Arrear` | `tabArrear` | transaction | 9 | 6 | 3 | `format:{Arrear}/{employee}/{#####}` |
| `Employee Benefit Application` | `tabEmployee Benefit Application` | transaction | 11 | 6 | 1 | `HR-BEN-APP-.YY.-.MM.-.#####` |
| `Employee Benefit Claim` | `tabEmployee Benefit Claim` | transaction | 12 | 6 | 0 | `HR-BEN-CLM-.YY.-.MM.-.#####` |
| `Employee Incentive` | `tabEmployee Incentive` | transaction | 9 | 6 | 0 | `HR-EINV-.YY.-.MM.-.#####` |
| `Employee Other Income` | `tabEmployee Other Income` | transaction | 7 | 4 | 0 | `HR-INCOME-.######` |
| `Employee Tax Exemption Declaration` | `tabEmployee Tax Exemption Declaration` | transaction | 9 | 6 | 1 | `HR-TAX-DEC-.YYYY.-.#####` |
| `Employee Tax Exemption Proof Submission` | `tabEmployee Tax Exemption Proof Submission` | transaction | 11 | 6 | 1 | `HR-TAX-PRF-.YYYY.-.#####` |
| `Gratuity` | `tabGratuity` | transaction | 19 | 10 | 0 | `HR-GRA-PAY-.#####` |
| `Income Tax Slab` | `tabIncome Tax Slab` | transaction | 8 | 3 | 2 | `Prompt` |
| `Payroll Correction` | `tabPayroll Correction` | transaction | 13 | 6 | 3 | `format:PAYCORR-{payroll_period}-{#####}` |
| `Payroll Entry` | `tabPayroll Entry` | transaction | 26 | 12 | 1 | `HR-PRUN-.YYYY.-.#####` |
| `Retention Bonus` | `tabRetention Bonus` | transaction | 10 | 6 | 0 | `HR-RTB-.YYYY.-.#####` |
| `Salary Slip` | `tabSalary Slip` | transaction | 62 | 13 | 5 | `-` |
| `Salary Structure` | `tabSalary Structure` | transaction | 17 | 7 | 4 | `Prompt` |
| `Salary Structure Assignment` | `tabSalary Structure Assignment` | transaction | 20 | 10 | 2 | `HR-SSA-.YY.-.MM.-.#####` |
| `Salary Withholding` | `tabSalary Withholding` | transaction | 13 | 3 | 1 | `format:SAL-WTH-{#####}` |
| `Employee Benefit Application Detail` | `tabEmployee Benefit Application Detail` | child | 3 | 1 | 0 | `-` |
| `Employee Benefit Detail` | `tabEmployee Benefit Detail` | child | 2 | 1 | 0 | `-` |
| `Employee Cost Center` | `tabEmployee Cost Center` | child | 2 | 1 | 0 | `-` |
| `Employee Tax Exemption Declaration Category` | `tabEmployee Tax Exemption Declaration Category` | child | 4 | 2 | 0 | `-` |
| `Employee Tax Exemption Proof Submission Detail` | `tabEmployee Tax Exemption Proof Submission Detail` | child | 6 | 1 | 0 | `-` |
| `Gratuity Applicable Component` | `tabGratuity Applicable Component` | child | 1 | 1 | 0 | `-` |
| `Gratuity Rule Slab` | `tabGratuity Rule Slab` | child | 3 | 0 | 0 | `-` |
| `Income Tax Slab Other Charges` | `tabIncome Tax Slab Other Charges` | child | 4 | 0 | 0 | `-` |
| `Payroll Correction Child` | `tabPayroll Correction Child` | child | 2 | 1 | 0 | `-` |
| `Payroll Employee Detail` | `tabPayroll Employee Detail` | child | 5 | 2 | 0 | `-` |
| `Payroll Period Date` | `tabPayroll Period Date` | child | 2 | 0 | 0 | `-` |
| `Salary Component Account` | `tabSalary Component Account` | child | 2 | 2 | 0 | `-` |
| `Salary Detail` | `tabSalary Detail` | child | 23 | 2 | 0 | `-` |
| `Salary Slip Leave` | `tabSalary Slip Leave` | child | 6 | 1 | 0 | `-` |
| `Salary Slip Loan` | `tabSalary Slip Loan` | child | 8 | 5 | 0 | `-` |
| `Salary Slip Timesheet` | `tabSalary Slip Timesheet` | child | 2 | 1 | 0 | `-` |
| `Salary Withholding Cycle` | `tabSalary Withholding Cycle` | child | 4 | 1 | 0 | `-` |
| `Taxable Salary Slab` | `tabTaxable Salary Slab` | child | 4 | 0 | 0 | `-` |

## payments / Payment Gateways (9)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `PayPal Settings` | `tabPayPal Settings` | single | 5 | 0 | 0 | `-` |
| `Paymob Settings` | `tabPaymob Settings` | single | 9 | 0 | 0 | `-` |
| `Paytm Settings` | `tabPaytm Settings` | single | 5 | 0 | 0 | `-` |
| `Razorpay Settings` | `tabRazorpay Settings` | single | 3 | 0 | 0 | `-` |
| `Braintree Settings` | `tabBraintree Settings` | master | 6 | 0 | 0 | `field:gateway_name` |
| `GoCardless Mandate` | `tabGoCardless Mandate` | master | 3 | 0 | 0 | `field:mandate` |
| `GoCardless Settings` | `tabGoCardless Settings` | master | 5 | 0 | 0 | `field:gateway_name` |
| `Mpesa Settings` | `tabMpesa Settings` | master | 11 | 0 | 0 | `field:payment_gateway_name` |
| `Stripe Settings` | `tabStripe Settings` | master | 5 | 0 | 0 | `field:gateway_name` |

## payments / Payments (1)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Payment Gateway` | `tabPayment Gateway` | master | 3 | 1 | 0 | `field:gateway` |

## webshop / Webshop (9)

| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |
|---|---|---|--:|--:|--:|---|
| `Webshop Settings` | `tabWebshop Settings` | single | 33 | 5 | 2 | `-` |
| `Item Review` | `tabItem Review` | master | 8 | 4 | 0 | `-` |
| `Website Item` | `tabWebsite Item` | master | 23 | 7 | 5 | `naming_series` |
| `Wishlist` | `tabWishlist` | master | 1 | 1 | 1 | `field:user` |
| `Homepage Featured Product` | `tabHomepage Featured Product` | child | 6 | 1 | 0 | `-` |
| `Recommended Items` | `tabRecommended Items` | child | 6 | 1 | 0 | `-` |
| `Website Item Tabbed Section` | `tabWebsite Item Tabbed Section` | child | 2 | 0 | 0 | `-` |
| `Website Offer` | `tabWebsite Offer` | child | 3 | 0 | 0 | `-` |
| `Wishlist Item` | `tabWishlist Item` | child | 9 | 4 | 0 | `-` |
