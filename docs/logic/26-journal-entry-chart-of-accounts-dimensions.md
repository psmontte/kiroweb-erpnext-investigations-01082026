# 26 — Journal Entry, the Chart of Accounts, and Accounting Dimensions

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Docs 01–07 documented what *happens* to the ledger. This document covers the three structures that
define *where* it happens: the **chart of accounts**, the **dimension model**, and the
**Journal Entry** — the universal posting document that can produce any GL shape and is therefore
the least constrained thing in the system.

Closes the coverage gap on `Account`, `Cost Center`, `Accounting Dimension`,
`Accounting Dimension Filter`, `Finance Book`, `Inventory Dimension`, `Journal Entry`,
`Journal Entry Template`, and `Advance Payment Ledger Entry` (`docs/COVERAGE.md`).

---

## 1. `Account` — a nested-set tree with fourteen validations

`Account(NestedSet)` (`accounts/doctype/account/account.py:25`). So the chart of accounts is
`lft`/`rgt` nested sets (decision D12 rejects these — doc 16 §4 covers the cost).

### 1.1 The classification triple

Three columns classify every account, and only one of them is authoritative:

| Column | Values | Set by |
|---|---|---|
| `root_type` | `Asset`, `Liability`, `Equity`, `Income`, `Expense` | inherited from parent |
| `report_type` | `Balance Sheet`, `Profit and Loss` | inherited, or derived from `root_type` |
| `account_type` | `Receivable`, `Payable`, `Bank`, `Cash`, `Stock`, `Fixed Asset`, `Tax`, `Round Off`, `Temporary`, `Cost of Goods Sold`, `Depreciation`, `Equity`, … | chosen |

`set_root_and_report_type` (`accounts/doctype/account/account.py:165`):

```python
if self.parent_account:
    par = frappe.get_cached_value("Account", self.parent_account, ["report_type", "root_type"], as_dict=1)
    if par.report_type: self.report_type = par.report_type
    if par.root_type:   self.root_type = par.root_type

if cint(self.is_group):
    db_value = self.get_doc_before_save()
    if db_value:
        query = frappe.qb.update(Account).where((Account.lft > self.lft) & (Account.rgt < self.rgt))
        updated = False
        if self.report_type != db_value.report_type:
            query = query.set(Account.report_type, self.report_type); updated = True
        if self.root_type != db_value.root_type:
            query = query.set(Account.root_type, self.root_type); updated = True
        if updated: query.run()

if self.root_type and not self.report_type:
    self.report_type = ("Balance Sheet" if self.root_type in ("Asset", "Liability", "Equity")
                        else "Profit and Loss")
```

Two things:

1. **Changing a group's `root_type` bulk-updates every descendant** via a nested-set range
   predicate (`lft > self.lft AND rgt < self.rgt`). That is a raw `UPDATE` across an arbitrary
   subtree — correct only if `lft`/`rgt` are current, which is the standing hazard of nested sets.
2. `report_type` is **derivable** from `root_type` (`:249`–`:252`) yet stored independently and
   inherited separately. Two columns, one fact, kept in step by assignment order.

`validate_parent_child_account_type` (`:126`) forbids a child having the same `account_type` as its
parent for six specific types (`Direct Income`, `Indirect Income`, `Current Asset`,
`Current Liability`, `Direct Expense`, `Indirect Expense`) — "Only Parent can be of type {0}".
A hard-coded list of six, with no equivalent rule for the other twenty-odd types.

### 1.2 The fourteen validations

`validate` (`accounts/doctype/account/account.py:108`):

```python
if frappe.local.flags.allow_unverified_charts: return     # ← the entire chart can skip validation
self.validate_parent()                                    # :140
self.validate_parent_child_account_type()                 # :126
self.validate_root_details()                              # :246
self.validate_account_number()                            # :383
self.validate_disabled()                                  # :294
self.validate_group_or_ledger()                           # :302
self.set_root_and_report_type()                           # :165
self.validate_mandatory()                                 # :488
self.validate_frozen_accounts_modifier()                  # :338
self.validate_balance_must_be_debit_or_credit()           # :349
self.validate_account_currency()                          # :368
self.validate_root_company_and_sync_account_to_children()  # :255
self.validate_receivable_payable_account_type()           # :198
self.validate_stock_account_type_change()                 # :216
```

Findings worth recording:

**`flags.allow_unverified_charts`** (`:109`) skips **all** of it. Used by the chart-of-accounts
importer and company setup, so an imported chart is entirely unvalidated.

**`validate_group_or_ledger`** (`:302`) — group↔ledger conversion:

```python
if self.check_gle_exists():
    throw(_("Account with existing transaction cannot be converted to ledger"))
elif cint(self.is_group):
    if self.account_type and not self.flags.exclude_account_type_check:
        throw(_("Cannot covert to Group because Account Type is selected."))
    self.validate_default_accounts_in_company()
elif self.check_if_child_exists():
    throw(_("Account with child nodes cannot be set as ledger"))
```

Note `flags.exclude_account_type_check` (`:310`) — an internal bypass for the
"a group cannot have an account_type" rule. And `convert_group_to_ledger` (`:460`) /
`convert_ledger_to_group` (`:471`) are whitelisted methods, so the conversion is a user action.

**`validate_receivable_payable_account_type`** (`:198`) — changing away from `Receivable`/`Payable`
when GL entries exist produces a **`msgprint` plus a comment on the document** (`:209`–`:212`), not
a throw:

> There are ledger entries against this account. Changing **Account Type** to non-Receivable in
> live system will cause incorrect output in 'Accounts Receivable' report

**It warns you that the reports will be wrong and lets you proceed.** Contrast
`validate_stock_account_type_change` (`:216`), added later, which *does* throw — via
`stock_ledger_entry_exists` (`:231`) resolving warehouses through
`get_warehouse_account_map`. Two adjacent rules, two severities, for the same class of change.

**`validate_account_currency`** (`:368`):

```python
self.currency_explicitly_specified = True
if not self.account_currency:
    self.account_currency = frappe.get_cached_value("Company", self.company, "default_currency")
    self.currency_explicitly_specified = False
gl_currency = frappe.db.get_value("GL Entry", {"account": self.name, "is_cancelled": 0}, "account_currency")
if gl_currency and self.account_currency != gl_currency:
    if frappe.db.get_value("GL Entry", {"account": self.name}):
        frappe.throw(_("Currency can not be changed after making entries using some other currency"))
```

Correct in outcome. Note `currency_explicitly_specified` is set as a **transient attribute on the
document object**, not persisted — it exists to tell downstream code whether the currency was
chosen or defaulted, and it is lost on reload.

**`validate_balance_must_be_debit_or_credit`** (`:349`) calls `get_balance_on(self.name)`
(`accounts/utils.py:204`) — **a full balance computation during account validation**, on every save
of an account with `balance_must_be` set.

**`validate_frozen_accounts_modifier`** (`:338`) gates the `freeze_account` field on
`Company.role_allowed_for_frozen_entries`. A per-account freeze, separate from
`Accounts Settings.acc_frozen_upto` (date-based) and `Accounting Period` (S05 §1) — a **fifth**
freezing mechanism.

**`validate_account_number`** (`:383`) enforces uniqueness of `account_number` within a company by
**scan** (`frappe.db.get_value` with `name != self.name`). No unique index.

### 1.3 Multi-company chart synchronisation

`validate_root_company_and_sync_account_to_children` (`:255`),
`create_account_for_child_company` (`:399`), `get_root_company` (`:663`),
`sync_update_account_number_in_child` (`:669`).

A parent company's chart is **copied into child companies**, and edits to the parent propagate.
`update_account_number` (`:559`) renames across the group; `_ensure_idle_system` (`:683`) guards it.
`merge_account` (`:624`) folds two accounts together, raising
`InvalidAccountMergeError` (`:21`) when incompatible.

So an account exists **once per company**, with a naming convention
(`get_account_autoname`, `:546` → `account_number - account_name - company_abbr`) that puts the
company abbreviation in the primary key — the same pattern as `Warehouse` (doc 16 §4) and
`Accounting Period` (S05 §4).

`get_account_currency` (`:525`) with its inner `generator` (`:530`) is the cached accessor used
everywhere; `on_doctype_update` (`:542`) declares the indexes.

---

## 2. `Cost Center` — the same shape, fewer rules

`CostCenter(NestedSet)` (`accounts/doctype/cost_center/cost_center.py:12`).

`validate` (`:39`) → `validate_mandatory` (`:43`), `validate_parent_cost_center` (`:49`).
`convert_group_to_ledger` (`:59`) / `convert_ledger_to_group` (`:70`) with
`check_gle_exists` (`:83`) and `check_if_child_exists` (`:86`).

Two cost-centre-specific guards, both added for Cost Center Allocation (doc 12 §3):

```python
def if_allocation_exists_against_cost_center(self):        # :93
def check_if_part_of_cost_center_allocation(self):         # :98
```

`before_rename` (`:103`) / `after_rename` (`:116`) handle the string-PK cascade, and
`get_name_with_number` (`:149`) mirrors the account-number convention.

`Cost Center` is a **first-class dimension with its own column** on `GL Entry`, unlike custom
dimensions (§3). So does `Project` and `Finance Book`. Three privileged dimensions plus N
runtime-added ones.

**`Finance Book`** (`accounts/doctype/finance_book/finance_book.py:8`) is a bare `Document` — no
validation at all. It exists so that the same asset can be depreciated differently for statutory vs
tax books, and it appears as a `GL Entry` column. Its emptiness is the point: it is a label.

---

## 3. `Accounting Dimension` — the runtime-DDL mechanism

This is the concrete implementation of decision **D13**'s target, and doc 18 §2.4 / doc 12 §1.2
referenced it. Here is the actual code.

### 3.1 Creating a dimension issues `ALTER TABLE` across the system

`AccountingDimension.on_update`
(`accounts/doctype/accounting_dimension/accounting_dimension.py:107`):

```python
if frappe.in_test:
    make_dimension_in_accounting_doctypes(doc=self)
else:
    frappe.enqueue(make_dimension_in_accounting_doctypes, doc=self,
                   queue="long", enqueue_after_commit=True)
```

`make_dimension_in_accounting_doctypes` (`:129`):

```python
if not doclist: doclist = get_doctypes_with_dimensions()          # :246
doc_count = len(get_accounting_dimensions())
repostable_doctypes = get_allowed_types_from_settings(child_doc=True)

for doctype in doclist:
    if (doc_count + 1) % 2 == 0: insert_after_field = "dimension_col_break"
    else:                        insert_after_field = "accounting_dimensions_section"
    df = {"fieldname": doc.fieldname, "label": doc.label, "fieldtype": "Link",
          "options": doc.document_type, "insert_after": insert_after_field,
          "owner": "Administrator",
          "allow_on_submit": 1 if doctype in repostable_doctypes else 0}
    meta = frappe.get_meta(doctype, cached=False)
    fieldnames = [d.fieldname for d in meta.get("fields")]
    if df["fieldname"] not in fieldnames:
        if doctype == "Budget": add_dimension_to_budget_doctype(df.copy(), doc)     # :166
        else:                   create_custom_field(doctype, df, ignore_validate=True)
    count += 1
    frappe.publish_progress(count * 100 / len(doclist), title=_("Creating Dimensions..."))
    frappe.clear_cache(doctype=doctype)
```

Each `create_custom_field` triggers `CustomField.on_update` → `frappe.db.updatedb(self.dt)` →
`ALTER TABLE ... ADD COLUMN` (doc 18 §2.4). `get_doctypes_with_dimensions` (`:246`) returns
**every accounting doctype**, so one dimension adds a column to `tabGL Entry`,
`tabSales Invoice`, `tabSales Invoice Item`, `tabPurchase Invoice`, `tabJournal Entry Account`,
`tabPayment Entry`, `tabStock Ledger Entry`, `tabBudget`, and dozens more — **in a background job**,
with a progress bar.

Three consequences:

1. **The DDL is asynchronous and non-transactional.** `enqueue_after_commit=True` means the columns
   appear *after* the `Accounting Dimension` row is committed. Between commit and job completion,
   the dimension exists in configuration but not in the schema. If the job fails partway, some
   tables have the column and some do not.
2. **`insert_after_field` alternates on parity** (`(doc_count + 1) % 2`, `:135`–`:138`) purely to
   lay fields out in two UI columns. Presentation logic determining a schema mutation's parameters.
3. **`allow_on_submit` depends on repost settings** (`:149`), so whether a dimension can be edited
   after submit is decided per doctype from `Repost Accounting Settings`.

`add_dimension_to_budget_doctype` (`:166`) is worse: it adds the custom field **and then mutates a
`Property Setter`** to extend `Budget.budget_against`'s option list by string concatenation:

```python
property_setter_doc.value = property_setter_doc.value + "\n" + doc.document_type
```

or creates it with `"\nCost Center\nProject\n" + doc.document_type`. A newline-delimited string of
option values, appended to. Deleting a dimension (`delete_accounting_dimension`, `:198`) must
parse and rewrite it.

### 3.2 What a dimension may be

`validate_doctype` (`:49`):

```python
if self.document_type in (*core_doctypes_list, "Accounting Dimension", "Project", "Cost Center",
                          "Accounting Dimension Detail", "Company", "Account", "Finance Book"):
    frappe.throw(_("Not allowed to create accounting dimension for {0}"))
exists = frappe.db.get_value("Accounting Dimension", {"document_type": self.document_type}, ["name"])
if exists and self.is_new():
    frappe.throw(_("Document Type already used as a dimension"))
if not self.is_new(): self.validate_document_type_change()      # :71
```

So `Cost Center`, `Project`, `Finance Book`, `Account`, and `Company` are **excluded because they
are already privileged dimensions** — confirming the two-tier model. And
`validate_document_type_change` (`:71`) forbids changing the target doctype: *"Cannot change
Reference Document Type. Please create a new Accounting Dimension if required."*

`validate_fieldname_conflict` (`:78`) is the most revealing:

```python
conflicting_doctypes = []
for doctype in get_doctypes_with_dimensions():
    meta = frappe.get_meta(doctype, cached=False)
    if any(f.fieldname == self.fieldname for f in meta.get("fields")):
        conflicting_doctypes.append(doctype)
if conflicting_doctypes:
    frappe.msgprint(_("Fieldname {0} already exists in the following doctypes: {1}. "
                      "A separate dimension field will not be added to these doctypes. "
                      "GL Entries will use the value of the existing field as the dimension value."),
                    title=_("Fieldname Conflict"), indicator="orange")
```

⚠️ **If the fieldname already exists on a doctype, the dimension silently reuses that field's
value.** A dimension called `territory` on a doctype that already has a `territory` column takes
its value from there. That is deliberate and documented in the message — and it means the dimension's
semantics differ per doctype, decided by name collision. `validate_column_name`
(`frappe/database/schema.py:398`) is also called (`:46`) because the fieldname becomes a SQL
identifier.

`validate_dimension_defaults` (`:99`) rejects duplicate companies in the `dimension_defaults` child
table — the per-company default value.

### 3.3 Reading dimensions back

`get_accounting_dimensions` (`:250`) returns the fieldname list (cached);
`get_dimensions` (`:301`) returns `(dimension_filters, default_dimensions_map)`;
`get_dimension_with_children` (`:286`) expands tree dimensions;
`get_checks_for_pl_and_bs_accounts` (`:263`) reads `Accounting Dimension Filter` — the rows that
**restrict which accounts a dimension value may be used with**, a mandatory/allowed matrix per
(dimension value, account).

`get_dimension_fieldname` (`:364`) handles the `Cost Center`/`Project` special case:

```python
if dim_doctype in ("Cost Center", "Project"):
    return frappe.scrub(dim_doctype)
```

`create_accounting_dimensions_for_doctype` (`:337`) back-fills dimensions onto a **newly created**
doctype — so a new posting doctype must be told to acquire the existing dimension columns.

`disable_dimension` (`:219`) / `toggle_disabling` (`:226`) enable/disable without dropping columns;
`on_trash` (`:115`) enqueues `delete_accounting_dimension` (`:198`), which removes the custom
fields — i.e. `DROP COLUMN`, asynchronously.

### 3.4 `Accounting Dimension Filter` — the allowed/mandatory matrix

`AccountingDimensionFilter`
(`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:10`). Two child
tables: `Applicable On Account` (which accounts the rule covers, with `is_mandatory` per account)
and `Allowed Dimension` (which dimension *values* are permitted).

```python
def before_save(self):                                          # :32
    if not self.apply_restriction_on_values:
        self.allow_or_restrict = "Restrict"
        self.set("dimensions", [])                              # ← silently discards the value list

def validate(self):                                             # :38
    self.fieldname = frappe.db.get_value("Accounting Dimension",
        {"document_type": self.accounting_dimension}, "fieldname") \
        or frappe.scrub(self.accounting_dimension)   # scrub to handle default accounting dimension
    self.validate_applicable_accounts()                         # :45
```

`validate_applicable_accounts` (`:45`) enforces that an account appears in **at most one** filter
per dimension — by querying every other filter's `Applicable On Account` rows and throwing on
overlap (`:61`–`:69`). Correct intent, implemented as a scan with no constraint.

`get_dimension_filter_map` (`:72`) builds the runtime lookup, keyed `(fieldname, account)`:

```python
map_object.setdefault((dimension, account),
    {"allowed_dimensions": [], "is_mandatory": is_mandatory, "allow_or_restrict": allow_or_restrict})
if filter_value:
    map_object[(dimension, account)]["allowed_dimensions"].append(filter_value)
```

(`build_map`, `:108`)

Two observations:

- **`allow_or_restrict` is a per-filter enum (`"Allow"` / `"Restrict"`) applied to a *value list*.**
  With `apply_restriction_on_values` off, `before_save` forces `"Restrict"` **and empties the list**
  — which means "restrict to nothing", i.e. the rule degenerates to mandatory-account-only. The
  semantics of an empty `allowed_dimensions` under `"Restrict"` are load-bearing and undocumented.
- The map is keyed by **fieldname string**, resolved with a `frappe.scrub` fallback (`:39`–`:41`) for
  the privileged dimensions. Same string-keyed identity as §3.2.

### 3.5 `Inventory Dimension` — the stock-side equivalent, with a live bug

`InventoryDimension` (`stock/doctype/inventory_dimension/inventory_dimension.py:25`) is
**445 lines** — substantially more machinery than `Accounting Dimension`, because stock movements
have direction and a source/target pair.

```python
def validate(self):        self.validate_reference_document()          # :129
def before_save(self):     self.do_not_update_document()              # :74
                           self.reset_value()                         # :120
                           self.set_source_and_target_fieldname()     # :138
                           self.set_type_of_transaction()             # :70
def on_update(self):       self.add_custom_fields()                   # :222
def on_trash(self):        self.delete_custom_fields()                # :98
```

**`validate_reference_document`** (`:129`) blocks child tables (`CanNotBeChildDoc`, `:17`) and
hard-codes four forbidden references (`CanNotBeDefaultDimension`, `:21`):

```python
if self.reference_document in ["Batch", "Serial No", "Warehouse", "Item"]:
```

— the same two-tier model as §3.2: the built-in stock dimensions cannot be redefined as custom ones.

**`do_not_update_document`** (`:74`) is the immutability guard, and it is *stricter* than anything on
the accounting side:

```python
if self.is_new() or not self.has_stock_ledger(): return
old_doc = self._doc_before_save
allow_to_edit_fields = ["fetch_from_parent", "type_of_transaction", "condition", "validate_negative_stock"]
for field in frappe.get_meta("Inventory Dimension").fields:
    if field.fieldname not in allow_to_edit_fields and old_doc.get(field.fieldname) != self.get(field.fieldname):
        frappe.throw(_("The user can not change value of the field {0} because stock transactions "
                       "exists against the dimension {1}."), DoNotChangeError)
```

Once `has_stock_ledger()` (`:53`) is true, **every field except four is frozen** — enumerated by
iterating the meta rather than by a whitelist of frozen names. Good outcome, and note it depends on
`Meta` (doc 18 §1.1), so a `Property Setter` adding a field automatically makes it frozen too.

**`add_custom_fields`** (`:222`) is the DDL path, and it does more than the accounting version:

```python
if self.apply_to_all_doctypes:
    for doctype in get_inventory_documents():                       # :325
        dimension_fields = self.get_dimension_fields(doctype[0])     # :158
        self.add_transfer_field(doctype[0], dimension_fields)        # :271
        custom_fields.setdefault(doctype[0], dimension_fields)
else:
    dimension_fields = self.get_dimension_fields()
    self.add_transfer_field(self.document_type, dimension_fields)
    custom_fields.setdefault(self.document_type, dimension_fields)

for dt in ["Stock Ledger Entry", "Stock Closing Balance"]:
    if dimension_fields and not frappe.db.get_value("Custom Field", {"dt": dt, "fieldname": self.target_fieldname}) \
            and not field_exists(dt, self.target_fieldname):        # :320
        dimension_field = dimension_fields[1]                        # ← index 1, positionally
        dimension_field["mandatory_depends_on"] = ""
        dimension_field["reqd"] = 0
        dimension_field["fieldname"] = self.target_fieldname
        custom_fields[dt] = dimension_field

ignore_doctypes = ["Serial and Batch Bundle", "Serial and Batch Entry", "Pick List Item",
                   "Maintenance Visit Purpose"]
...
create_custom_fields(filter_custom_fields)
```

Note `dimension_fields[1]` (`:249`) — the second element of a list built by
`get_dimension_fields` (`:158`) is mutated in place and reused for `Stock Ledger Entry` and
`Stock Closing Balance`. Positional coupling between two functions, and the **same dict object** is
assigned to both doctypes' entries in `custom_fields`.

**`add_transfer_field`** (`:271`) is where S04 §4.1's `to_`/`from_` convention originates:

```python
if doctype not in ["Stock Entry Detail", "Sales Invoice Item", "Delivery Note Item",
                   "Purchase Invoice Item", "Purchase Receipt Item"]: return
fieldname_start_with = "to";   label_start_with = "Target";  display_depends_on = ""
if doctype in ["Purchase Invoice Item", "Purchase Receipt Item"]:
    fieldname_start_with = "from"; label_start_with = "Source"
    display_depends_on = "eval:parent.is_internal_supplier == 1"
elif doctype != "Stock Entry Detail":
    display_depends_on = "eval:parent.is_internal_customer == 1"
elif doctype == "Stock Entry Detail":
    display_depends_on = "eval:doc.t_warehouse"
fieldname = f"{fieldname_start_with}_{self.source_fieldname}"
```

So the second (target) dimension column exists **only on five specific child doctypes**, is named by
string concatenation, and is shown/required by `eval:` expressions stored as field properties.
`delete_custom_fields` (`:98`) removes four naming variants:
`source_fieldname`, `to_*`, `from_*`, `rejected_*`.

**The live bug** — `get_evaluated_inventory_dimension`
(`stock/doctype/inventory_dimension/inventory_dimension.py:354`):

```python
for row in dimensions:
    if row.type_of_transaction and row.type_of_transaction != "Both":
        if (row.type_of_transaction == "Inward" if doc.docstatus == 1
            else row.type_of_transaction != "Inward") and sl_dict.actual_qty < 0:
            continue
        elif (row.type_of_transaction == "Outward" if doc.docstatus == 1
              else row.type_of_transaction != "Outward") and sl_dict.actual_qty > 0:
            continue
    evals = {"doc": doc}
    if parent_doc: evals["parent"] = parent_doc
    if row.condition and frappe.safe_eval(row.condition, evals):
        filter_dimensions.append(row)
    else:
        filter_dimensions.append(row)          # ← IDENTICAL to the if-branch
```

⚠️ **Both branches of the `condition` check append the row.** `Inventory Dimension.condition` — a
user-authored expression intended to decide whether the dimension applies to a given movement — is
evaluated via `frappe.safe_eval` and then **its result is discarded**. The condition has no effect
whatsoever, while still incurring the cost and the risk of evaluating user-supplied code on every
stock movement.

The direction filter above it (`type_of_transaction` with the inverted-on-cancel ternaries) *does*
work, and is genuinely subtle: on cancellation (`docstatus != 1`) the comparison is negated so the
dimension applies to the reversing movement.

`get_document_wise_inventory_dimensions` (`:385`) is `@request_cache`d;
`get_inventory_dimensions` (`:402`) is the whitelisted accessor;
`get_parent_fields` (`:424`) supports `fetch_from_parent`; `delete_dimension` (`:418`) is the
whitelisted teardown; `get_insert_after_fieldname` (`:149`) picks the last `DocField` by `idx`.

---

## 4. `Journal Entry` — the universal posting document

`JournalEntry(AccountsController)` (`accounts/doctype/journal_entry/journal_entry.py:47`).

### 4.1 Voucher types

`voucher_type` selects behaviour: `Journal Entry`, `Opening Entry`, `Bank Entry`, `Cash Entry`,
`Credit Card Entry`, `Debit Note`, `Credit Note`, `Contra Entry`, `Excise Entry`,
`Write Off Entry`, `Depreciation Entry`, `Exchange Rate Revaluation`,
**`Exchange Gain Or Loss`** (S06 §4.2), `Inter Company Journal Entry`,
`Periodic Accounting Entry`, `Reverse Journal Entry`.

Sixteen behaviours, one table, dispatched by `if voucher_type == ...` throughout — **not** by
strategy classes as `Stock Entry` now does (S04 §2). The v17 service extraction reached
`journal_entry/services/asset_service.py` and `reference_validator.py` but not the voucher-type
branching.

### 4.2 `validate` — twenty steps

`validate` (`accounts/doctype/journal_entry/journal_entry.py:140`):

```python
if self.voucher_type == "Opening Entry": self.is_opening = "Yes"
if not self.is_opening: self.is_opening = "No"
if self.is_opening == "Yes": validate_opening_entry_against_pcv(self.company)
self.clearance_date = None                            # ← always cleared on save
self.validate_party()                                 # :467
self.validate_entries_for_advance()                   # :531
self.validate_multi_currency()                        # :684
self.set_amounts_in_company_currency()                # :706
self.validate_debit_credit_amount()                   # :656
self.set_total_debit_credit()                         # :671
if not frappe.flags.is_reverse_depr_entry:
    self.validate_against_jv()                        # :562
    self.validate_stock_accounts()                    # :380
JournalEntryReferenceValidator(self).validate()
if self.docstatus == 0: self.set_against_account()    # :633
self.create_remarks()                                 # :757
self.set_print_format_fields()                        # :813
self.validate_credit_debit_note()                     # :994
self.validate_empty_accounts_table()                  # :1008
self.validate_inter_company_accounts()                # :362
AssetService(self).validate_depr_account_and_depr_entry_voucher_type()
self.validate_company_in_accounting_dimension()
self.validate_advance_accounts()                      # :186
JournalTaxWithholding(self).on_validate()
if self.is_new() or not self.title: self.title = self.get_title()   # :359
```

Note `self.clearance_date = None` at `:156` — **every save wipes the bank clearance date**, which
is why `Bank Clearance` is exempt from the Accounting Period gate (S05 §4.2) and why
`clear_clearance_date_on_amend` exists (doc 14 §1.3).

### 4.3 Balancing — and the deliberate exception

`set_total_debit_credit` (`:671`):

```python
for d in self.get("accounts"):
    if d.debit and d.credit:
        frappe.throw(_("You cannot credit and debit same account at the same time"))
    self.total_debit  = flt(self.total_debit)  + flt(d.debit,  d.precision("debit"))
    self.total_credit = flt(self.total_credit) + flt(d.credit, d.precision("credit"))
self.difference = flt(self.total_debit, self.precision("total_debit")) \
                - flt(self.total_credit, self.precision("total_credit"))
```

`validate_total_debit_and_credit` (`:662`):

```python
if not (self.voucher_type == "Exchange Gain Or Loss" and self.multi_currency):
    if self.difference:
        frappe.throw(_("Total Debit must be equal to Total Credit. The difference is {0}"))
```

⚠️ **An `Exchange Gain Or Loss` journal in multi-currency mode is exempt from balancing.** The same
exemption appears in `validate_debit_credit_amount` (`:656`) — zero-value rows are allowed — and in
`set_amounts_in_company_currency` (`:706`), which skips the base-currency recomputation entirely.

The reasoning is that an FX journal's *account-currency* amounts are legitimately zero while its
*base* amounts are not (S06 §8.4 shows the shape). But the effect is that **one voucher type can
post an unbalanced GL entry**, and `process_debit_credit_difference`
(`accounts/general_ledger.py:397`) is left to absorb it. Invariant F1 has a documented exception.

`get_balance` (`accounts/doctype/journal_entry/journal_entry.py:890`) /
`_apply_difference_to_blank_row` (`:904`) is the "auto-balance" helper:

```python
blank_row = None
for row in self.get("accounts"):
    if not row.credit_in_account_currency and not row.debit_in_account_currency:
        blank_row = row                                # ← the LAST amountless row wins
if not blank_row:
    blank_row = self.append("accounts", {"account": difference_account,
                                         "cost_center": erpnext.get_default_cost_center(self.company)})
blank_row.exchange_rate = 1                            # ← forced to 1
if diff > 0:   blank_row.credit_in_account_currency = diff; blank_row.credit = diff
elif diff < 0: blank_row.debit_in_account_currency = abs(diff); blank_row.debit = abs(diff)
```

`blank_row.exchange_rate = 1` unconditionally — so auto-balancing a multi-currency journal puts the
plug on a row whose rate is forced to 1, meaning `debit == debit_in_account_currency` even if the
chosen `difference_account` is a foreign-currency account.

### 4.4 Multi-currency

`validate_multi_currency` (`:684`) fetches each row's `account_currency` and `account_type` from
the account, defaults to company currency, collects the set of alternates, and throws if any
alternate exists while `multi_currency` is unchecked. Then calls `set_exchange_rate` (`:719`):

```python
for row in self.get("accounts"):
    self._set_row_exchange_rate(row)
    if not row.exchange_rate:
        frappe.throw(_("Row {0}: Exchange Rate is mandatory").format(row.idx))
```

`_set_row_exchange_rate` (`:726`):

```python
if row.account_currency == self.company_currency:
    row.exchange_rate = 1; return
needs_refresh = (not row.exchange_rate or row.exchange_rate == 1
                 or (row.reference_type in ("Sales Invoice", "Purchase Invoice")
                     and row.reference_name and self.posting_date))
if not needs_refresh or self.flags.get("ignore_exchange_rate"): return
row.exchange_rate = get_exchange_rate(self.posting_date, row.account, row.account_currency,
                                      self.company, row.reference_type, row.reference_name,
                                      row.debit, row.credit, row.exchange_rate)
```

⚠️ **`row.exchange_rate == 1` is treated as "unset"** (`:735`). A genuinely-1.0 rate between two
different currencies (a pegged 1:1 pair) is silently refetched every save. And note this
`get_exchange_rate` (`accounts/doctype/journal_entry/journal_entry.py:1266`) is a **different
function** from `setup/utils.py:62` (S06 §2) — a nine-argument JE-specific variant that can derive
the rate from a referenced invoice.

`set_amounts_in_company_currency` (`accounts/doctype/journal_entry/journal_entry.py:706`) then computes
`debit = debit_in_account_currency × exchange_rate`, rounded to the field precision — the
relationship S06 §8.1 makes a `CHECK` constraint.

### 4.5 Referencing other documents

`validate_against_jv` (`accounts/doctype/journal_entry/journal_entry.py:562`)
with `_validate_jv_reference` (`:568`),
`_validate_jv_reference_direction` (`:595`), `_get_against_jv_entries` (`:614`);
`get_against_jv` (`:1069`), `get_outstanding` (`:1108`),
`_get_journal_entry_outstanding` (`:1143`), `_get_invoice_outstanding` (`:1164`).

A `Journal Entry Account` row can reference a Sales Invoice, Purchase Invoice, Journal Entry,
Sales Order, Purchase Order, Employee Advance, Expense Claim, or Asset — via
`reference_type`/`reference_name`/`reference_detail_no`. This is the mechanism
`reconcile_against_document` (`accounts/utils.py:516`) rewrites when allocating (S02 §9.2).

`set_against_account` (`:633`) builds the denormalised `against` string — the human-readable
"contra account" summary, computed only while `docstatus == 0` (`:172`).

`get_outstanding_invoices` (`:929`) / `_append_outstanding_invoice_row` (`:945`) implement the
"write off outstanding" helper, and `validate_credit_debit_note` (`:994`) guards credit/debit-note
JEs.

`unlink_advance_entry_reference` (`:448`), `unlink_inter_company_jv` (`:457`),
`update_inter_company_jv` (`:400`), `validate_inter_company_accounts` (`:362`) handle the
cross-document links on cancel — doc 15 §1 and doc 09 §3.

`update_invoice_discounting` (`:409`) with `_get_next_invoice_discounting_status` (`:419`) and
`_validate_invoice_discounting_status` (`:439`) drive the factoring status machine (doc 14 §6).

### 4.6 Stock accounts and the periodic-inventory escape hatch

`validate_stock_accounts` (`:380`) throws `StockAccountInvalidTransaction` (`:43`) if a JE touches a
stock account without a corresponding stock movement — the guard that keeps the stock↔GL bridge
(doc 03) intact.

But `voucher_type = 'Periodic Accounting Entry'` deliberately breaks it.
`get_balance_for_periodic_accounting` (`:243`):

```python
self.validate_company_for_periodic_accounting()                    # :281
self.set("accounts", [])
for account in self.get_stock_accounts_for_periodic_accounting():   # :292
    account_bal, stock_bal, _warehouse_list = get_stock_and_account_balance(
        account, self.posting_date, self.company)                   # accounts/utils.py:1906
    difference_value = flt(stock_bal - account_bal, self.precision("difference"))
    if difference_value == 0:
        frappe.msgprint(_("No difference found for stock account {0}"), alert=True); continue
    self._append_periodic_difference_rows(account, difference_value)   # :262
```

and `validate_company_for_periodic_accounting` (`:281`):

```python
if erpnext.is_perpetual_inventory_enabled(self.company):
    frappe.throw(_("Periodic Accounting Entry is not allowed for company {0} with perpetual inventory enabled"))
if not self.periodic_entry_difference_account:
    frappe.throw(_("Please select Periodic Accounting Entry Difference Account"))
```

So for **non-perpetual-inventory companies**, this voucher type computes the stock-vs-ledger
difference (the drift detection of doc 03) and posts it to a difference account, rebuilding its own
`accounts` table from scratch (`self.set("accounts", [])` at `:247`). It is a manual, on-demand
reconciliation posting — and the accounts table it builds is discarded and regenerated on every
click.

### 4.7 Background submission

`submit` (`:204`) and `cancel` (`:217`) are overridden to enqueue when the entry is large:

```python
def submit(self):   """Submit inline, or queue submission in the background for large entries."""
```

with `before_submit` (`:224`), `on_submit` (`:230`), `before_cancel` (`:211`), `on_cancel` (`:324`),
`on_update_after_submit` (`:313`). `build_gl_map` (`:861`) and
`make_gl_entries` (`:866`) produce the GL. `validate_for_repost` (`:200`) and
`system_generated_gain_loss` (`:557`) round it out.

### 4.8 `Journal Entry Template`

`JournalEntryTemplate`
(`accounts/doctype/journal_entry_template/journal_entry_template.py:11`) — pre-filled account rows
plus a restricted `voucher_type` list (`:29`–`:43`, thirteen of the sixteen types; notably
**`Periodic Accounting Entry` and `Reverse Journal Entry` are absent**).

```python
def validate(self):                                    # :46
    self.validate_party()                              # :63
    self.validate_account_company()                    # :50

def validate_account_company(self):                    # :50
    for account in self.accounts:
        if account.account and frappe.get_cached_value("Account", account.account, "company") != self.company:
            frappe.throw(_("Row {0}: Account {1} does not belong to company {2}"))

def validate_party(self):                              # :63
    for account in self.accounts:
        if account.party_type:
            account_type = frappe.get_cached_value("Account", account.account, "account_type")
            if account_type not in ["Receivable", "Payable"]:
                frappe.throw(_("Check row {0} for account {1}: Party Type is only allowed for "
                               "Receivable or Payable accounts"))
        if account.party and not account.party_type:
            frappe.throw(_("Check row {0} for account {1}: Party is only allowed if Party Type is set"))
```

Worth noting because these are **the two rules a party-bearing GL line actually needs** — a party
only on a receivable/payable account, and a party type whenever a party is set — and they are
enforced *here, on the template*, while `JournalEntry.validate_party`
(`accounts/doctype/journal_entry/journal_entry.py:467`) enforces them again on the document. Two
implementations of the same invariant. In our design both collapse into:

```sql
CONSTRAINT mvl_party_pair CHECK ((party_type IS NULL) = (party_id IS NULL))
```

plus a trigger asserting `account.account_type IN ('receivable','payable')` whenever
`party_id IS NOT NULL`.

`get_naming_series` (`:85`) reads the option list off `Journal Entry`'s own field —
metadata read at runtime to populate a master (doc 18 §1.1).

### 4.9 `Advance Payment Ledger Entry`

`AdvancePaymentLedgerEntry`
(`accounts/doctype/advance_payment_ledger_entry/advance_payment_ledger_entry.py:9`). Doc 11 §2.3
traced its *use*; the controller itself is nine lines of logic:

```python
def on_update(self):                                   # :32
    if (self.against_voucher_type in get_advance_payment_doctypes()
            and self.flags.update_outstanding == "Yes"
            and not frappe.flags.is_reverse_depr_entry):
        update_voucher_outstanding(self.against_voucher_type, self.against_voucher_no, None, None, None)

def on_doctype_update():                               # :40
    frappe.db.add_index("Advance Payment Ledger Entry", ["against_voucher_type", "against_voucher_no"])
    frappe.db.add_index("Advance Payment Ledger Entry", ["voucher_type", "voucher_no"])
```

Columns: `company`, `voucher_type`/`voucher_no`, `against_voucher_type`/`against_voucher_no`
(both `DynamicLink`), `currency`, `amount`, `base_amount`, `exchange_rate`, `event`, `delinked`.

Three findings:

1. **Both reference pairs are `Dynamic Link`s** — so this ledger has no FK to anything, and
   deleting a Sales Order leaves orphan rows (doc 09 §5). The two indexes at `:40`–`:48` exist
   precisely because polymorphic lookup has no other support.
2. **`on_update` triggers a cached-counter recompute** (`update_voucher_outstanding`,
   `accounts/utils.py:2175`) from inside a ledger row's save — gated by a *flag on the document
   object* (`self.flags.update_outstanding == "Yes"`), so whether the order's `advance_paid`
   refreshes depends on how the row was constructed. Doc 11 §2.3 showed the read side
   (`ABS(SUM(amount))`); this is the write side.
3. It is **a third parallel subledger** beside `GL Entry` and `Payment Ledger Entry`, written by
   `create_advance_payment_ledger_entry`, wholesale-deleted by
   `_delete_adv_pl_entries` (`accounts/utils.py:1724`) and
   `AccountsController._remove_advance_payment_ledger_entries`
   (`controllers/accounts_controller.py:410`). In our model it does not exist: an advance is a
   `settlement` row against an order's `payment_schedule` (S02 §12.6).

---

## 5. Our design

### 5.1 The chart of accounts

```sql
CREATE TABLE account (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid NOT NULL REFERENCES company(id),
    code            text NOT NULL,
    name            text NOT NULL,
    parent_id       uuid REFERENCES account(id),
    kind            account_kind NOT NULL,      -- 'group','ledger'
    root_type       root_type NOT NULL,         -- 'asset','liability','equity','income','expense'
    account_type    account_type,               -- 'receivable','payable','bank','cash','stock',...
    account_currency char(3) NOT NULL,
    balance_must_be balance_side,               -- 'debit','credit', NULL = either
    is_fx_revalued  boolean NOT NULL DEFAULT false,
    is_frozen       boolean NOT NULL DEFAULT false,
    disabled        boolean NOT NULL DEFAULT false,

    UNIQUE (company_id, code),
    CONSTRAINT acct_group_no_type   CHECK (kind = 'ledger' OR account_type IS NULL),
    CONSTRAINT acct_root_is_group   CHECK (parent_id IS NOT NULL OR kind = 'group'),
    CONSTRAINT acct_not_self_parent CHECK (parent_id <> id)
);
-- report_type is DERIVED, not stored
CREATE VIEW account_v AS
SELECT a.*, CASE WHEN a.root_type IN ('asset','liability','equity')
                 THEN 'balance_sheet' ELSE 'profit_and_loss' END AS report_type
FROM account a;
```

Differences that matter:

| ERPNext | Ours |
|---|---|
| `lft`/`rgt` nested sets | `parent_id` + recursive CTE (**D12**) |
| `report_type` stored *and* inherited | derived in a view — §1.1's two-columns-one-fact removed |
| group `root_type` change = bulk `UPDATE` over an `lft`/`rgt` range | a recursive CTE; and `root_type` is **immutable once `gl_entry` rows exist** (trigger) |
| company abbreviation in the PK | `uuid` + `UNIQUE (company_id, code)` |
| `account_number` uniqueness by scan | `UNIQUE (company_id, code)` |
| `account_type` change warns via `msgprint` | **trigger-enforced**: immutable once ledger rows exist, for *every* type, not just `Stock` |
| `flags.allow_unverified_charts` bypasses all validation | no bypass; chart import runs the same constraints |
| `currency_explicitly_specified` transient attribute | `account_currency NOT NULL`, explicit at creation |
| `balance_must_be` validated by computing a full balance on save | a deferred constraint trigger on `gl_entry` against the account's cumulative sign |
| Group↔ledger conversion allowed | `kind` immutable once `gl_entry` rows exist (trigger), matching `warehouse.kind` (doc 16 §5.4) |
| Five freezing mechanisms | one `accounting_period.state` (S05 §4.3) + `account.is_frozen` for the account-level case, both checked by the same trigger |
| Parent-child `account_type` rule for 6 hard-coded types | a `account_type_rule` table if the rule is genuinely needed; otherwise dropped |

Multi-company chart replication becomes a **template**:

```sql
CREATE TABLE coa_template (id uuid PRIMARY KEY, code text NOT NULL UNIQUE, name text NOT NULL);
CREATE TABLE coa_template_account (
    template_id uuid NOT NULL REFERENCES coa_template(id) ON DELETE CASCADE,
    code text NOT NULL, name text NOT NULL, parent_code text,
    kind account_kind NOT NULL, root_type root_type NOT NULL, account_type account_type,
    PRIMARY KEY (template_id, code)
);
```

A company is *instantiated from* a template. There is no live parent→child sync (§1.3), so editing
one company's chart cannot silently alter another's — and `update_account_number`'s cross-company
rename cascade has no analogue.

### 5.2 Dimensions — fixed slots, no DDL (D13)

Doc 18 §5.2 specified the model. The concrete mapping from ERPNext:

| ERPNext | Ours |
|---|---|
| `Cost Center` (privileged column, nested set) | `cost_center_id uuid REFERENCES cost_center(id)`, `parent_id` tree |
| `Project` (privileged column) | `project_id uuid REFERENCES project(id)` |
| `Finance Book` (privileged column, empty controller) | `finance_book_id uuid REFERENCES finance_book(id)` |
| N custom `Accounting Dimension`s → `ALTER TABLE` on every accounting doctype, asynchronously | `dim1_id … dim4_id uuid REFERENCES dim_value(id)`, present from migration 0001 |
| beyond 4 | `gl_entry_dimension (gl_entry_id, dimension_id, dim_value_id)` |
| `Inventory Dimension` → `ALTER TABLE tabStock Ledger Entry` | the same four slots on `stock_move` |
| `Accounting Dimension Filter` (allowed/mandatory account × value matrix) | `dimension_account_rule (dimension_id, account_id, requirement)` with `requirement ∈ ('allowed','mandatory','forbidden')`, enforced by a constraint trigger |
| dimension defaults per company (`dimension_defaults` child) | `dimension_default (dimension_id, company_id, dim_value_id)` with `UNIQUE (dimension_id, company_id)` — the duplicate-company check of §3.2 becomes a constraint |
| fieldname collision silently reuses an existing column | impossible: slots are named `dim1_id`…`dim4_id`, and `dimension.slot` binds meaning |
| `insert_after_field` parity for UI layout | `ui_field` presentation metadata (doc 18 §5.1), never schema |
| `Budget.budget_against` options as a newline-delimited `Property Setter` string | `budget_line` names dimension slots as columns (doc 12 §1.6) |

**No background job, no progress bar, no partial-schema window.** Binding a dimension to a slot is
one `INSERT` into `dimension`.

### 5.3 Journal Entry becomes `manual_voucher`

The universal posting document is legitimate and we keep it — with the sixteen voucher types split
into an explicit enum plus **separate tables where the shape genuinely differs**:

```sql
CREATE TABLE manual_voucher (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     uuid NOT NULL REFERENCES company(id),
    voucher_id     uuid NOT NULL UNIQUE REFERENCES voucher(id),
    kind           manual_voucher_kind NOT NULL,   -- 'general','opening','contra','write_off',
                                                   -- 'reclass','fx_revaluation','period_close'
    narration      text
);
CREATE TABLE manual_voucher_line (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    manual_voucher_id uuid NOT NULL REFERENCES manual_voucher(id) ON DELETE CASCADE,
    line_no          smallint NOT NULL,
    account_id       uuid NOT NULL REFERENCES account(id),
    amount_acct      numeric(19,4) NOT NULL,        -- signed; S06 §8.1
    account_currency char(3) NOT NULL,
    amount_base      numeric(19,4) NOT NULL,
    rate_acct_to_base numeric(21,9) NOT NULL,
    party_type       party_type,
    party_id         uuid,
    cost_center_id   uuid REFERENCES cost_center(id),
    project_id       uuid REFERENCES project(id),
    dim1_id uuid REFERENCES dim_value(id), dim2_id uuid REFERENCES dim_value(id),
    dim3_id uuid REFERENCES dim_value(id), dim4_id uuid REFERENCES dim_value(id),
    UNIQUE (manual_voucher_id, line_no),
    CONSTRAINT mvl_nonzero CHECK (amount_acct <> 0 OR amount_base <> 0),
    CONSTRAINT mvl_rate    CHECK (rate_acct_to_base > 0),
    CONSTRAINT mvl_base_consistent CHECK (
        abs(amount_base - round(amount_acct * rate_acct_to_base, 4)) <= 0.0001)
);
```

Key changes:

- **Signed `amount_acct`** removes the `debit and credit` both-set check (§4.3) — a single column
  cannot be both.
- **No balancing exception.** Invariant F1 has no carve-out: the `Exchange Gain Or Loss` case
  (§4.3) does not arise because realised FX is a *line inside the payment voucher*
  (S06 §8.4), not a separate journal. `fx_revaluation` vouchers balance normally.
- **No auto-balance plug.** A voucher that does not balance does not post. `_apply_difference_to_blank_row`'s
  forced `exchange_rate = 1` (§4.3) has no analogue; if the user wants a rounding line they add one
  explicitly, with its own account and rate.
- **`clearance_date` is not on the voucher** — bank matching is `bank_match` rows (doc 14 §7.2), so
  `self.clearance_date = None` on every save (§4.2) cannot happen, and the Accounting Period
  exemption for `Bank Clearance` (S05 §4.2) is unnecessary.
- **References are `settlement` rows**, not `reference_type`/`reference_name` on the line
  (S02 §12.1) — so allocation never rewrites a posted voucher's children (§4.5, S02 §9.2).
- **Stock accounts are protected by a constraint, not a validator**: `account.account_type = 'stock'`
  accounts may only receive `gl_entry` rows whose voucher has `stock_move` rows, enforced by a
  deferred trigger. The `Periodic Accounting Entry` escape (§4.6) becomes an explicit
  `kind = 'reclass'` voucher with a `reason_code`, permitted only for companies where
  `company.inventory_mode = 'periodic'`.

### 5.4 Drift detection becomes an assertion

`get_stock_and_account_balance` (`accounts/utils.py:1906`) and
`Periodic Accounting Entry` exist because stock and GL can diverge (doc 03). With
`warehouse.stock_account_id UNIQUE` (doc 16 §5.4) and invariant **F2**, the reconciliation is a
constraint:

```sql
-- F2, as a scheduled assertion that must return zero rows
SELECT w.stock_account_id,
       (SELECT COALESCE(SUM(amount_base),0) FROM gl_entry g WHERE g.account_id = w.stock_account_id) AS gl,
       (SELECT COALESCE(SUM(value_base),0)  FROM stock_move m WHERE m.warehouse_id = w.id)          AS stock
FROM warehouse w WHERE w.stock_account_id IS NOT NULL
HAVING gl <> stock;
```

Zero rows by construction, because both sides are written in the same transaction from the same
figure. A non-empty result is a **bug report**, not an accounting task.

---

## 6. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| `Account` as nested set | **Reject** | `parent_id` + recursive CTE (D12) |
| `report_type` stored and inherited | **Reject** | derived in `account_v` |
| Group `root_type` change bulk-updates a subtree | **Reject** | immutable once posted |
| `flags.allow_unverified_charts` | **Reject** | no validation bypass |
| `account_type` change: warn for Receivable/Payable, throw for Stock | **Reject** | uniform trigger-enforced immutability |
| Group↔ledger conversion | **Reject** | `kind` immutable once posted |
| Live parent→child chart sync across companies | **Reject** | `coa_template` instantiation |
| Company abbreviation in the account PK | **Reject** | `uuid` + `UNIQUE (company_id, code)` |
| `balance_must_be` computing a full balance on save | **Reject** | deferred trigger on `gl_entry` |
| Five freezing mechanisms | **Reject** | one period gate + `account.is_frozen`, one trigger |
| Three privileged dimensions + N runtime-added | **Reject** | four fixed slots + `gl_entry_dimension` (D13) |
| Dimension creation = async `ALTER TABLE` across dozens of tables | **Reject** | one `INSERT` |
| Fieldname collision silently reuses an existing column | **Reject** | slot-bound meaning |
| `Property Setter` option list built by string concatenation | **Reject** | FK to `dimension` |
| `Accounting Dimension Filter` | **Keep the idea** | `dimension_account_rule` with a trigger |
| Dimension defaults per company | **Keep** | `dimension_default` + `UNIQUE` |
| `Inventory Dimension` (separate mechanism for stock) | **Reject** | the same four slots on `stock_move` |
| 16 voucher types dispatched by `if` | **Reject** | `manual_voucher_kind` enum; distinct tables where shape differs |
| `debit` + `credit` column pair | **Reject** | signed `amount_acct` |
| **Balancing exemption for `Exchange Gain Or Loss`** | **Reject** | F1 has no exception |
| Auto-balance onto a blank row with forced `rate = 1` | **Reject** | an unbalanced voucher does not post |
| `clearance_date` wiped on every save | **Reject** | `bank_match` rows |
| `reference_type`/`reference_name` on journal lines | **Reject** | `settlement` rows |
| `exchange_rate == 1` treated as unset | **Reject** | `NULL` means unset |
| A second, JE-specific `get_exchange_rate` | **Reject** | one `fx_rate` lookup (S06 §8.2) |
| `Periodic Accounting Entry` rebuilding its own lines | **Reject** | explicit `reclass` voucher, gated on `inventory_mode` |
| `Advance Payment Ledger Entry` as a third subledger | **Reject** | `settlement` rows against order payment schedules (S02 §12.6) |
| `Journal Entry Template` | **Keep** | `voucher_template` + `voucher_template_line` |
| `Finance Book` | **Keep** | a real FK dimension slot |

---

Cross-references: doc 01 (GL posting pipeline), doc 03 (stock↔GL bridge and drift),
doc 07 (period control), doc 12 (dimensions in budgets, cost-centre allocation),
doc 16 §4–§5 (nested sets, warehouse `kind`), doc 18 (runtime DDL, custom fields),
**[S05](../scenarios/S05-period-close-and-opening-balances.md)** (opening entries, closing),
**[S06](../scenarios/S06-multi-currency.md)** (account currency, FX journals),
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
