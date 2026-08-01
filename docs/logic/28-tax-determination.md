# 28 — Tax Determination

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Doc 05 covered what happens **after** a tax row exists: the totals pipeline, the nine charge types,
inclusive-tax back-calculation, rounding. This document covers the question that comes first:

> Given a party, an address, an item and a date — **which tax rows should exist at all, and at what
> rate?**

That is a separate subsystem with its own masters, its own matching algorithm, and its own failure
modes. ERPNext answers it with **five independent mechanisms** that are consulted in a fixed order,
each with different matching semantics:

| # | Mechanism | Decides | Hierarchy-aware? | Date-aware? |
|---|---|---|---|---|
| 1 | `Tax Category` | a *label* carried by party/address/document | no | no |
| 2 | `Tax Rule` | which **charge template** to use | customer/supplier group only | yes |
| 3 | `Sales`/`Purchase Taxes and Charges Template` | the header charge rows | n/a | no |
| 4 | `Item Tax Template` (via `Item`/`Item Group`) | per-item **rate overrides** | item group only | `valid_from` only |
| 5 | `Tax Withholding Category` | TDS/TCS rate and thresholds | no | yes (`from`/`to`) |

Closes the `docs/COVERAGE.md` gaps for `Tax Category`, `Tax Rule`, `Item Tax Template`,
`Sales Taxes and Charges Template`, `Purchase Taxes and Charges Template`,
`Tax Withholding Category`, `Tax Withholding Group`, and `Customs Tariff Number`.

---

## 1. `Tax Category` — a label, and a flag nobody reads

`TaxCategory` (`accounts/doctype/tax_category/tax_category.py:9`) is `pass`. Two fields: `title` and
`disabled`.

It is the join key that ties the whole subsystem together — it appears on `Customer`, `Supplier`,
`Address`, `POS Profile`, both charge templates, `Tax Rule`, and the `Item Tax` child row. Nothing
else about it is modelled.

⚠️ **`disabled` is never checked in Python.** A grep across the app finds no server-side read of
`Tax Category.disabled`; the only reads of a `disabled` flag in this subsystem are on the *templates*
(`accounts/services/taxes.py:109`, `accounts/doctype/tax_rule/tax_rule.py:242`) and on
`Item Tax Template` (`stock/get_item_details.py:818`). Disabling a Tax Category therefore stops
nothing: rules and templates referencing it keep matching.

> **Ours** `tax_category` is a real table with `company_id`, `code`, `valid_from`/`valid_to`, and an
> `is_active` generated from those dates rather than a hand-set flag — and it is referenced by FK
> everywhere, so "disabled" is expressed by end-dating, which the matcher already honours. A flag
> that no code path reads is worse than no flag: it tells the user they have controlled something.

### 1.1 Where the document's tax category comes from

Resolution happens inside the party-details pipeline, `accounts/party.py`:

```
set_address_details(...)                                 # :200
    ...
    party_details["tax_category"] = get_address_tax_category(   # :296
        party.get("tax_category"), party_billing, party_shipping)
set_other_values(...)                                    # :354  copies tax_withholding_* from party
set_price_list(...)                                      # :160
tax_template = set_taxes(..., tax_category=party_details.tax_category, ...)   # :162
...
if not party_details.get("tax_category") and pos_profile:                     # :194
    party_details["tax_category"] = POS Profile.tax_category
```

`get_address_tax_category` (`:739`) reads
`Accounts Settings.determine_address_tax_category_from` — a **global** choice between
`"Shipping Address"` and anything else (billing) — then takes `Address.tax_category` if present, else
keeps the party's own. It returns `cstr(...)`, so "nothing found" is `""`, never `NULL`.

Two consequences worth stating plainly:

1. ⚠️ **The POS Profile fallback at `:194` runs *after* `set_taxes` at `:162`.** A tax category that
   comes only from the POS Profile is written onto `party_details` but is **never used for Tax Rule
   matching** — the rule was already chosen with a blank category. The field is populated for
   display and for the item-tax lookup, but the header template it should have selected is not.
2. Billing-vs-shipping is one setting for the whole install, so a company that is destination-taxed
   for goods and origin-taxed for services cannot express both.

For purchases the asymmetry is sharper. `set_address_details` sets `party_shipping_field` to
`dispatch_address` for suppliers, and `party_billing` remains the **supplier's** address (the
company's own address is written to `party_details.billing_address` separately, but that is not what
is passed). So a purchase document's tax category derives from the **supplier's** addresses, never
from the receiving company's — place-of-supply logic is left entirely to the regional overlay
(`get_regional_address_details`, `:302`, and doc 21 §4).

> **Ours** Tax determination takes an explicit `tax_situs` input — `(origin_address_id,
> destination_address_id, party_id, item_id, posting_date)` — computed once and **stored on the
> document** with the resolved `tax_category_id`. Which of origin/destination governs is a property
> of the `tax_regime` row, not a global setting, and it is resolved per line rather than per
> document. Storing the resolved inputs is what makes a tax decision auditable three years later,
> which is the actual requirement.

---

## 2. The two charge templates

`SalesTaxesandChargesTemplate`
(`accounts/doctype/sales_taxes_and_charges_template/sales_taxes_and_charges_template.py:19`) and
`PurchaseTaxesandChargesTemplate`
(`accounts/doctype/purchase_taxes_and_charges_template/purchase_taxes_and_charges_template.py:14`)
are the same document twice. The purchase one has no logic at all — it imports the sales module's
`valdiate_taxes_and_charges_template`
(`accounts/doctype/sales_taxes_and_charges_template/sales_taxes_and_charges_template.py:53`, and yes,
that typo is the real function name) and calls it.

```python
def valdiate_taxes_and_charges_template(doc):          # :53
    if doc.is_default == 1:
        UPDATE tabX SET is_default = 0
         WHERE is_default = 1 AND name != doc.name AND company = doc.company   # :62
    validate_disabled(doc)                             # :80  default must not be disabled
    validate_for_tax_category(doc)                     # :85
    for tax in doc.get("taxes"):
        validate_taxes_and_charges(tax)                 # doc 05 §5.2
        validate_account_head(tax.idx, tax.account_head, doc.company, ...)
        validate_cost_center(tax, doc)
        validate_inclusive_tax(tax, doc)
```

Three things to note.

**"Exactly one default" is a bulk `UPDATE`, not a constraint** (`:62`). Two concurrent saves both
read no conflict, both clear the other's flag, and both set their own — the classic lost-update
window. Nothing later detects two defaults, and the consumer picks one arbitrarily (§4.1).

**One template per tax category, and it forbids history** (`validate_for_tax_category`, `:85`):

```python
if frappe.db.exists(doc.doctype, {"company": ..., "tax_category": ...,
                                  "disabled": 0, "name": ["!=", doc.name]}):
    frappe.throw("A template with tax category {0} already exists. Only one template is
                  allowed with each tax category")
```

The probe filters `disabled: 0` on the *other* rows but never looks at whether **this** document is
disabled. So once an active template claims a tax category you cannot save a second one for it *even
as a disabled draft* — you must first disable or re-categorise the incumbent. Superseding a tax
template at a rate change is therefore a destructive edit, and the old rates survive only inside the
documents that already copied them.

**Rates can be back-filled from the Account.** `set_missing_values` (`:47`) replaces a zero rate on
an `On Net Total` row with `Account.tax_rate`. It is not called from `validate` — it is a helper the
client and importers call — so whether a template's stored rate or the account's rate wins depends
on the entry path.

### 2.1 The template is copied, not referenced

`get_taxes_and_charges` (`accounts/services/taxes.py:205`) loads the template, strips
`default_fields + child_table_fields` from each row, and returns plain dicts that the caller
`extend`s onto the document. The document holds a **snapshot**. That is the right call — a tax
document must not change when a master is edited later — but there is no record of *which version*
was copied, so "why does this invoice show 18% when the template says 12%" is unanswerable from the
data.

> **Ours** `tax_template` and `tax_template_line` are versioned exactly like `product_bundle` in doc
> 27 §5.1: an immutable `tax_template_version` row per revision, `valid_from` monotonic, and the
> document stores `tax_template_version_id`. The copy still happens — lines are materialised onto the
> document so posting is self-contained — but the provenance is a FK, so the question above is a
> join. `is_default` becomes a partial unique index
> (`CREATE UNIQUE INDEX ON tax_template (company_id, kind) WHERE is_default`), which closes the
> lost-update window that the bulk `UPDATE` leaves open. "One per tax category" likewise becomes
> `UNIQUE (company_id, kind, tax_category_id) WHERE is_active`, which permits end-dated history.

---

## 3. `Tax Rule` — a twenty-column matcher

`TaxRule` (`accounts/doctype/tax_rule/tax_rule.py:32`) maps a combination of party, party group,
item, item group, billing address, shipping address, tax category, company and date range to **one
charge template**. It is the only date-aware part of header tax determination.

### 3.1 The stored shape

`validate_tax_template` (`:73`) enforces mutual exclusivity by **nulling the other side**:

```python
if self.tax_type == "Sales":
    self.purchase_tax_template = self.supplier = self.supplier_group = None
    if self.customer: self.customer_group = None
else:
    self.sales_tax_template = self.customer = self.customer_group = None
    if self.supplier: self.supplier_group = None
if not (self.sales_tax_template or self.purchase_tax_template):
    frappe.throw("Tax Template is mandatory.")
```

So one table carries both a sales and a purchase template column, and `tax_type` decides which half
is meaningful — the same "one table, two documents" pattern as `Journal Entry` (doc 26 §4) and
`Stock Entry` (S04 §2). Note also that setting a specific customer **silently discards** the customer
group you typed.

The address columns are the interesting part. `billing_city`, `billing_county`, `billing_state`,
`billing_zipcode`, `shipping_city`, … are **`Data`**, not links. `get_party_details` (`:144`) copies
them off the `Address` document as free text:

```python
out["billing_city"]    = billing_address.city
out["billing_county"]  = billing_address.county
out["billing_state"]   = billing_address.state
out["billing_zipcode"] = billing_address.pincode
out["billing_country"] = billing_address.country      # the only Link
```

Tax then depends on **string equality of hand-typed geography**. "CA" and "California" are different
tax jurisdictions; a trailing space is a different jurisdiction.

> **Ours** `tax_jurisdiction` is a table with a `parent_id` hierarchy (country → state → county →
> city → postcode range) and addresses carry `tax_jurisdiction_id` as an FK, resolved once when the
> address is saved. Matching walks the hierarchy with a recursive CTE, so a rule written at state
> level matches every city in it — which is what users assume `Tax Rule` already does. Postcodes are
> an `int4range` with an `EXCLUDE` constraint, not a `varchar`.

### 3.2 Conflict detection at save time, and its two holes

`validate_filters` (`:88`) builds a query for a row with **identical values in all twenty filter
fields** (`IfNull(field,'') == cstr(value)`), overlapping dates, and then:

```python
tax_rule = query.run(as_dict=True)
if tax_rule and tax_rule[0].priority == self.priority:
    frappe.throw("Tax Rule Conflicts with {0}", ConflictingTaxRule)
```

⚠️ **Hole 1 — only the first row is inspected.** There is no `ORDER BY`. If the query returns
several identical rules and the arbitrary first has a different priority, the conflict is not
reported even though a later row collides exactly.

⚠️ **Hole 2 — the date-overlap predicate misses containment.** The four OR'd conditions use strict
inequalities:

```python
((TaxRule.from_date > self.from_date) & (TaxRule.from_date < self.to_date))
| ((TaxRule.to_date > self.from_date) & (TaxRule.to_date < self.to_date))
| ((self.from_date > TaxRule.from_date) & (self.from_date < TaxRule.to_date))
| ((TaxRule.from_date == self.from_date) & (TaxRule.to_date == self.to_date))
```

Take an existing rule `2026-01-01 → 2026-12-31` and save a new one `2026-01-01 → 2026-06-30` with the
same filters and priority. Clause 1: `01-01 > 01-01` false. Clause 2: `12-31 < 06-30` false. Clause
3: `01-01 > 01-01` false. Clause 4: end dates differ, false. **Not detected** — the shorter range is
wholly contained and shares a start date. Two rules then match the same document with the same
priority, and §3.3 resolves the tie arbitrarily.

The single-sided branches leak differently: `elif self.from_date:` compares
`TaxRule.to_date > self.from_date` with no `IfNull`, so existing open-ended rules (`to_date IS NULL`)
never compare and never conflict.

> **Ours** This is an exclusion constraint, not a query:
> `EXCLUDE USING gist (company_id WITH =, kind WITH =, tax_category_id WITH =, party_id WITH =, …,
> priority WITH =, daterange(valid_from, valid_to, '[]') WITH &&)`. Containment, adjacency and the
> `NULL`-as-open-ended case are all handled by the range type, and it holds under concurrency. The
> save-time scan cannot.

### 3.3 The matcher: specificity beats priority

`get_tax_template(posting_date, args)` (`:177`) is the read path.

**Date filter.** `from_date IS NULL OR <= posting_date` and `to_date IS NULL OR >= posting_date`.
But when `posting_date` is falsy it inverts to `from_date IS NULL AND to_date IS NULL` — an undated
call can only match undated rules.

**Field filters.** For each key in `args`:

```python
if key == "use_for_shopping_cart":
    where TaxRule.use_for_shopping_cart == value
elif key == "tax_category":
    where IfNull(TaxRule.tax_category, "") == (value or "")        # EXACT
elif key in ("customer_group", "supplier_group"):
    where IfNull(TaxRule[key], "").isin(get_group_ancestors(...))  # HIERARCHY
else:
    where IfNull(TaxRule[key], "").isin(["", value or ""])         # blank = wildcard
```

Three different semantics in one loop:

- Most fields treat **blank as a wildcard** — a rule that leaves `item` empty matches every item.
- **`tax_category` is exact.** A rule with a blank tax category matches *only* documents whose tax
  category is also blank. This is the single most surprising rule in the subsystem: leaving the field
  empty does not mean "any category", it means "no category".
- `customer_group` / `supplier_group` match against the **ancestor chain** (`get_group_ancestors`,
  `:192`), so a rule on a parent group covers its children. `item_group` gets no such treatment — it
  falls to the `else` branch and matches only exactly or blank. So group hierarchies work for parties
  and are silently ignored for items, even though `Item Tax Template` selection *does* walk the item
  group tree (§4.2). Two mechanisms, opposite answers, same master data.

`get_group_ancestors` also substitutes `get_root_of(doctype)` when the document has no group, so a
party without a customer group matches rules written against the **root** group.

**Ranking.** Every candidate is scored:

```python
for rule in tax_rule:
    rule.no_of_keys_matched = 0
    for key in args:
        if rule.get(key):
            rule.no_of_keys_matched += 1          # :226

rule = sorted(tax_rule, key=cmp_to_key(
    lambda b, a: cmp(a.no_of_keys_matched, b.no_of_keys_matched)
                 or cmp(a.priority, b.priority)))[0]     # :235
```

`no_of_keys_matched` counts how many of the rule's own filter fields are **non-blank** — it is a
specificity score, not a count of matches. Sorting is descending by specificity **then** by
`priority`, so:

> ⚠️ **`priority` is only a tie-break between rules of equal specificity.** A priority-1 rule with
> four filters beats a priority-99 rule with three. A field named `priority` that cannot override a
> more specific rule will be misused by every administrator who meets it.

The `lambda b, a:` argument swap to get descending order — rather than `reverse=True` — is a
readability trap sitting on top of a `cmp_to_key` shim that Python 3 only keeps for compatibility.

**And then the last line throws the answer away:**

```python
tax_template = rule.sales_tax_template or rule.purchase_tax_template
if frappe.db.get_value(doctype, tax_template, "disabled") == 1:      # :242
    return None
```

⚠️ If the winning rule points at a **disabled** template, the function returns `None` — it does
**not** fall through to the next-best rule. One disabled template silently switches off tax
determination for every combination whose best rule referenced it, and the document is created with
no template at all. Combined with §2's "you cannot keep a second template for the same tax category",
the ordinary act of retiring a tax template is a live hazard.

> **Ours** Determination is one function against one `tax_rule` table, returning the winning row
> **and its score**, and it is called in a `WHERE is_active` context so a retired template cannot be
> selected in the first place. Ordering is explicit and total:
> `ORDER BY priority DESC, specificity DESC, valid_from DESC, id` — priority first, because that is
> what the name promises — and the final `id` makes the choice deterministic instead of arbitrary.
> `specificity` is a stored generated column, not recomputed in Python per call. When nothing
> matches, that is a typed outcome (`no_rule`) the caller must handle, never a silent `None` that
> looks like "no tax due".

---

## 4. Item-level determination

Two independent things live here: the **header** template (which charge rows exist) and the
**per-item** template (which rates those rows use for a given line).

### 4.1 The header template, when no Tax Rule matched

`TaxService.set_taxes` (`accounts/services/taxes.py:25`):

```python
if (doc.is_new() or self.is_pos_profile_changed()) and not doc.get("taxes"):
    if doc.company and not doc.get("taxes_and_charges"):
        doc.taxes_and_charges = frappe.db.get_value(
            tax_master_doctype, {"is_default": 1, "company": doc.company})
    self.append_taxes_from_master(tax_master_doctype)
```

The fallback is `is_default` — **with no `disabled: 0` filter**, and with no tax category involved.
If §2's bulk `UPDATE` ever raced, `get_value` returns an arbitrary one of the two defaults.

A disabled default is caught later, at validate time, by `validate_enabled_taxes_and_charges`
(`:109`) — which `throw`s. So the failure mode is: the system silently selects a disabled template,
then refuses to save the document, and the message names the template rather than the selection rule.

`get_default_taxes_and_charges` (`:185`) has its own wrinkle: when the passed template already
belongs to the right company it executes a bare `return`, yielding **`None`** where every other path
returns a `dict`.

### 4.2 `Item Tax Template`

`ItemTaxTemplate` (`accounts/doctype/item_tax_template/item_tax_template.py:11`) is a named set of
`(tax_type → tax_rate)` pairs, scoped to one company, named `{title} - {abbr}` (`:39` — company
abbreviation in the primary key again, doc 26 §1.6).

`validate_tax_accounts` (`:44`) requires each `tax_type` account to belong to the template's company
and to have `account_type` in `Tax`, `Chargeable`, `Income Account`, `Expense Account`,
`Expenses Included In Valuation`, and rejects the same account twice (list scan, no unique index on
the child table).

`set_zero_rate_for_not_applicable_tax` (`:33`) forces `tax_rate = 0` on rows flagged
`not_applicable`. The flag survives, and it is *not* the same as a 0% rate: `get_item_tax_map`
(`stock/get_item_details.py:881`) emits the sentinel **string** `NOT_APPLICABLE_TAX = "N/A"`
(`:41`) for those rows, which `taxes_and_totals.py` then special-cases in four places
(`controllers/taxes_and_totals.py:358`, `:393`, `:394`, `:602`).

> A rate column whose domain is "a number, or the string `N/A`" is a union type smuggled through a
> `Float`. Ours: `tax_line.applicability` is an enum (`taxable`, `zero_rated`, `exempt`,
> `not_applicable`, `reverse_charge`) and `rate` is `numeric(9,6) NOT NULL`, `CHECK (rate = 0 OR
> applicability = 'taxable')`. Zero-rated and exempt are genuinely different for reporting, which is
> why every real tax regime distinguishes them and this schema cannot.

### 4.3 Selecting an item tax template

`get_item_tax_template` (`stock/get_item_details.py:742`) → the item's own `taxes` table first, then
`_get_item_tax_template_from_item_group` (`:779`), which walks the **item group ancestors** via
`get_ancestors_of`:

```python
ancestors = get_ancestors_of("Item Group", item_group)
for group in [item_group, *ancestors]:
    if item_tax_template := _get_item_tax_template(ctx, frappe.get_cached_doc("Item Group", group).taxes, out):
        return item_tax_template
```

The candidate rows are `Item Tax` children — `item_tax_template`, `tax_category`, `valid_from`,
`minimum_net_rate`, `maximum_net_rate`. Note what is **absent: there is no `valid_upto`.** Validity
is open-ended, and end-dating is expressed only by adding a later row and relying on the sort.

`_get_item_tax_template` (`:792`) partitions and picks:

```python
for tax in taxes:
    disabled, tax_company = get_cached_value("Item Tax Template", tax.item_tax_template,
                                             ["disabled", "company"])
    if not disabled and tax_company == ctx["company"]:
        if tax.valid_from or tax.maximum_net_rate:
            validation_date = ctx.bill_date or ctx.posting_date or ctx.transaction_date
            if getdate(tax.valid_from) <= getdate(validation_date) and is_within_valid_range(ctx, tax):
                taxes_with_validity.append(tax)
        else:
            taxes_with_no_validity.append(tax)
```

Points of interest:

- The date used is **`bill_date` first** — the supplier's invoice date — then posting date, then
  transaction date. Correct for purchase tax, and a real requirement.
- `is_within_valid_range` (`:863`) gates on `minimum_net_rate <= base_net_rate <= maximum_net_rate`.
  **Tax template selection depends on the line's own rate**, which is how slab-rated regimes are
  modelled. It is also a circular dependency in waiting: the rate determines the tax, and discounts
  determine the rate.
- A row carrying only `maximum_net_rate` and no `valid_from` still enters the validity branch, where
  `getdate(None)` resolves to **today**. `today <= validation_date` is false for any backdated
  document, so slab rows without an explicit `valid_from` silently drop out of backdated invoices.

Then the selection:

```python
if taxes_with_validity:
    taxes = sorted(taxes_with_validity,
                   key=lambda i: i.valid_from or tax.maximum_net_rate, reverse=True)   # :832
else:
    taxes = taxes_with_no_validity
```

⚠️ **`:832` is a live bug.** The sort key closes over **`tax`** — the leaked loop variable from the
`for tax in taxes` loop above — where it means to use **`i`**. For any row whose `valid_from` is
falsy the key is not that row's `maximum_net_rate` but the *last iterated* row's, so every such row
sorts to an identical key and the intended "highest slab first" ordering does not happen. It also
compares dates against floats whenever the list mixes both kinds of row, which on Python 3 raises
`TypeError` — meaning the mixed case is not merely mis-ordered, it fails.

⚠️ A second, quieter bug in the `for_validate` branch (`:837`):

```python
return [tax.item_tax_template for tax in taxes
        if (cstr(tax.tax_category) == cstr(ctx.get("tax_category"))
            and (tax.item_tax_template not in taxes))]
```

`taxes` is a list of **row objects**; `tax.item_tax_template` is a **string**. The membership test is
always `True`, so the de-duplication it exists to perform never happens.

The final choice:

```python
if ctx.get("item_tax_template") in {t.item_tax_template for t in taxes}:   # :853
    out.item_tax_template = ctx.get("item_tax_template")
    return ctx.get("item_tax_template")
for tax in taxes:
    if cstr(tax.tax_category) == cstr(ctx.get("tax_category")):            # :858
        out.item_tax_template = tax.item_tax_template
        return tax.item_tax_template
return None
```

- ⚠️ **"Do not change if already valid" (`:853`) ignores the tax category.** An item tax template
  already on the row is kept as long as it appears anywhere among the candidates — *even if its
  `tax_category` no longer matches the document's*. Change a customer's tax category on a saved
  order and the item rates do not follow.
- Matching is again **exact `cstr` equality** on `tax_category` (`:858`), with no wildcard and no
  hierarchy. No match → `None` → no item tax template, and the header rates apply unmodified. Missing
  tax configuration is indistinguishable from "correctly no override".

### 4.4 Whether item tax templates produce rows at all is a global boolean

`set_taxes_and_charges` (`accounts/services/taxes.py:48`), called from
`controllers/accounts_controller.py:259`, is gated on two `Accounts Settings` singles:

```python
if Accounts Settings.add_taxes_from_taxes_and_charges_template and hasattr(doc, "taxes_and_charges"):
    self.append_taxes_from_master(...)
if Accounts Settings.add_taxes_from_item_tax_template:
    self.append_taxes_from_item_tax_template()
```

`append_taxes_from_item_tax_template` (`:72`) appends a header row per distinct account head found in
any line's `item_tax_rate`, with **`rate: 0`**, `charge_type: "On Net Total"`, `category: "Total"`,
`add_deduct_tax: "Add"` and `set_by_item_tax_template: 1`. The header rate is a placeholder; the real
per-line rates arrive later from the `item_tax_rate` JSON map (doc 05 §5.4). So a header tax row
showing 0% while the invoice charges 18% is normal, and `set_by_item_tax_template` is the only thing
distinguishing a placeholder from a genuine zero.

> **Ours** No global on/off flags for tax composition. Determination produces a `tax_line` set per
> document line — `(line_id, tax_code_id, applicability, rate, basis, jurisdiction_id)` — and the
> header presentation is a **view** aggregating them. There is nothing to "add from" and no
> placeholder rows, so no flag column is needed to tell real rows from scaffolding, and a document
> can carry two different rates for the same tax on different lines without the header lying about
> either.

---

## 5. Withholding determination (TDS / TCS)

Doc 05 §5.10 covered the withholding **calculation** and the `Tax Withholding Entry` ledger. This
section covers only which category, rate and threshold get selected.

### 5.1 The master

`TaxWithholdingCategory`
(`accounts/doctype/tax_withholding_category/tax_withholding_category.py:17`) holds two child tables:

- `Tax Withholding Rate` — `tax_withholding_rate`, `single_threshold`, `cumulative_threshold`,
  `from_date`, `to_date`, `tax_withholding_group`
- `Tax Withholding Account` — `(company, account)`

and the switches `tax_deduction_basis` (`Gross Total` / `Net Total`), `round_off_tax_amount`,
`tax_on_excess_amount`, `disable_cumulative_threshold`, `disable_transaction_threshold`.

`Tax Withholding Group` itself
(`accounts/doctype/tax_withholding_group/tax_withholding_group.py:8`) is `pass` with a single
`group_name` field — a bare label used to partition the rate rows below. It carries no company, no
validity, and no relationship to the categories that reference it, so "which groups exist" is a
naming convention rather than a model.

`validate_dates` (`accounts/doctype/tax_withholding_category/tax_withholding_category.py:46`) groups
rate rows by `tax_withholding_group` and checks overlap **within each group**:

```python
if getdate(d.from_date) >= getdate(d.to_date):
    frappe.throw("Row #{0}: From Date cannot be before To Date")     # message inverted
...
for d in sorted(rates, key=lambda d: getdate(d.from_date)):
    if last_to_date and getdate(d.from_date) < getdate(last_to_date):
        frappe.throw("Row #{0}: Dates overlapping with other row in group {1}")
    last_to_date = d.to_date
```

Two defects. The first message describes the opposite of the condition it guards — the check fires
when `from >= to`, so the text should read "From Date must be before To Date". The second matters:
overlap uses **strict `<`**, so `from_date == previous to_date` is accepted as non-overlapping, while
the reader `get_applicable_tax_row` (`:93`) is **inclusive on both ends**:

```python
for row in self.rates:
    if getdate(row.from_date) <= getdate(posting_date) <= getdate(row.to_date) \
       and cstr(row.tax_withholding_group) == cstr(tax_withholding_group):
        return row
frappe.throw("No Tax Withholding data found for the current posting date.")
```

⚠️ On a shared boundary date **both rows match**, and the winner is whichever comes first in
child-table `idx` order — not the sorted order the validator used. A rate change on the boundary day
is decided by row ordering in the UI.

Also note the reader **throws** when nothing matches. A posting date outside every configured window
is a hard failure, not "no withholding applies" — which is the correct instinct (silent zero tax is
worse) but it means back-dating a document into an unconfigured period blocks it with a message that
does not say which category is unconfigured.

`get_company_account` (`:102`) likewise throws when the category has no account row for the company.
`validate_companies_and_accounts` (`:68`) rejects a duplicate company **and** a duplicate account
across the whole child table — so two companies may not share one withholding account.

`validate_thresholds` (`:84`) enforces `cumulative_threshold >= single_threshold`, but only when both
are non-zero. And `:41` carries an unresolved `# TODO: Disable single threshold if tax on excess is
enabled` — the interaction between `tax_on_excess_amount` and the two thresholds is known to be
undefined.

### 5.2 Which categories apply to a document

`TaxWithholdingController._get_category_names`
(`accounts/doctype/tax_withholding_entry/tax_withholding_entry.py:371`):

```python
category_names = set(item.tax_withholding_category
                     for item in self.doc.items
                     if item.tax_withholding_category and item.apply_tds)
```

Determination is therefore **per item line**, and the set of categories on a document is the union
over its lines. The line value is resolved by `get_tax_withholding_category`
(`stock/get_item_details.py:1417`):

```python
field = "sales_tax_withholding_category" if ctx.transaction_type == "selling" \
        else "purchase_tax_withholding_category"
if item_doc.get(field):            tax_withholding_category = item_doc.get(field)
elif buying and ctx.supplier:      tax_withholding_category = Supplier.tax_withholding_category
elif selling and ctx.customer:     tax_withholding_category = Customer.tax_withholding_category
```

Item master wins over party. The `Item` master holds **two** fields — a sales one and a purchase one
— so direction is modelled by column rather than by a rule.

`tax_withholding_group`, by contrast, is a **header-only** field, copied from the party by
`set_other_values` (`accounts/party.py:354`, `to_copy` includes `tax_withholding_category` and
`tax_withholding_group`) and passed straight through to the rate lookup. So the *category* can vary
per line while the *group* — which selects the rate row inside that category — cannot. A document
mixing two groups is inexpressible.

The master switch is `apply_tds`. On Purchase Invoice, `set_missing_values`
(`accounts/doctype/purchase_invoice/purchase_invoice.py:357`):

```python
tax_withholding_category, tax_withholding_group = get_cached_value(
    "Supplier", self.supplier, ["tax_withholding_category", "tax_withholding_group"])
if not for_validate:
    if tax_withholding_category or tax_withholding_group:
        self.apply_tds = 1
```

⚠️ Guarded by `not for_validate`, so the auto-enable only happens on the interactive path. A
programmatic save that goes through the validate path leaves `apply_tds` at its default, and
`_is_tax_withholding_applicable` (`tax_withholding_entry.py:1096`) then clears the entries and
returns `False`. Whether withholding is computed depends on **how** the document was created.

`:1096` also skips withholding entirely when `doc.is_opening == "Yes"` — consistent with S05 §7,
where opening invoices fabricate history rather than transact it.

### 5.3 Payment Entries bypass thresholds by design

`PaymentTaxWithholding` (`:1141`) overrides determination twice:

```python
def _get_category_names(self):                       # :1149
    return [self.doc.tax_withholding_category] if self.doc.tax_withholding_category else []

def _is_threshold_crossed_for_category(self, category):   # :1197
    """For payment entries if apply_tds is checked, return True"""
    return True

def _get_unused_threshold(self, category):                # :1201
    """Always withhold Tax and whenever tax gets deducted adjust it"""
    return 0
```

On a payment there are no item lines, so the category is the single header field; and thresholds are
**unconditionally treated as crossed**. Withholding on an advance is always deducted and then
reconciled against the invoice later through the under/over-withheld entries. That is a defensible
domain decision — you cannot know at advance time whether the annual threshold will be crossed — and
it is the clearest example in the codebase of behaviour that belongs in data rather than in a
subclass: the same statement, expressed as `threshold_basis = 'always'` on the category, would remove
the need for a document-type-specific controller.

The taxable base is also different: `unallocated_amount` plus allocations to advance doctypes
(`:1155`), translated at the source or target rate depending on `payment_type` (`:1170`).

### 5.4 Lower Deduction Certificates

`TaxWithholdingDetails.get()` (`tax_withholding_category.py:132`) assembles per-category details and
overlays LDC data from `get_ldc_details` (`:175`). LDCs apply to **suppliers only**.

`get_valid_ldc_records` (`:209`) is worth reading closely:

```python
where (ldc.valid_from <= posting_date) & (ldc.valid_upto >= posting_date)
      & (ldc.company == company)
      & ldc.tax_withholding_category.isin(self.tax_withholding_categories)
query = query.where(ldc.pan_no == tax_id) if tax_id else query.where(ldc.supplier == self.party)
```

The certificate is matched on the party's **tax ID** when it has one, falling back to the supplier
link otherwise. That is deliberate and correct for the domain — a certificate belongs to a tax
identity, not to a vendor record, so it must apply across duplicate supplier masters sharing a PAN.
`get_tax_id_for_party` (`:253`) is `@allow_regional`, so the definition of "tax ID" is a regional
override (doc 21 §4).

Note this is genuine modelling that the *rest* of the schema lacks: identity here is the tax number,
while everywhere else it is the party primary key. Utilisation is aggregated the same way
(`get_ldc_utilization_by_category`, `:231`, keyed on `tax_id` when present, `party` otherwise) from
submitted `Tax Withholding Entry` rows with status in `Settled`/`Over Withheld`.

Two problems:

- The docstring says **"Assumes that only one LDC per category can be valid at a time"** — an
  assumption, not a constraint. The loop writes `ldc_details[category_name] = {...}`, so with two
  overlapping certificates the last row read silently wins.
- ⚠️ `if not unutilized_amount: continue` (`:198`). `unutilized_amount = certificate_limit -
  consumed`, and `not x` is true only at exactly `0`. A **negative** remainder — an over-utilised
  certificate — is truthy, so the reduced LDC rate keeps being applied past the certificate limit.
  This is the same falsiness-versus-comparison error as the reorder rollup in doc 17 §5.2 and the
  `if reserved_qty:` guard in doc 16 §2.1; here it under-withholds tax.

> **Ours** `withholding_certificate` with `party_tax_id` as the match key (an FK to a
> `party_tax_identity` table, so the "identity is the tax number" insight becomes structural rather
> than a pair of `if`s), `numrange` limit, `EXCLUDE` constraint on
> `(party_tax_id, category_id, daterange)` so overlap is impossible instead of assumed, and
> utilisation as a **view** over the withholding ledger with
> `CHECK (consumed <= certificate_limit)` enforced by a deferred trigger on the ledger. Remaining
> capacity is compared with `> 0`, not tested for truthiness.

---

## 6. `Customs Tariff Number`

`CustomsTariffNumber` (`stock/doctype/customs_tariff_number/customs_tariff_number.py:9`) is `pass`,
with `tariff_number` and `description`. It is referenced from `Item` and carried onto `Shipment`
parcels. No validation of the code's format, no hierarchy, no link to duty rates, no date validity —
so it is documentation, not determination. HS codes are hierarchical (chapter → heading →
subheading), and duty determination needs that structure plus origin/destination.

> **Ours** `commodity_code` with `parent_id`, `regime` (HS / HTS / CN), `valid_from`/`valid_to`, and a
> `duty_rate` table keyed `(commodity_code_id, origin_jurisdiction_id, destination_jurisdiction_id,
> daterange)`. Until cross-border duty is in scope this stays a reference table — but it stays a
> *hierarchical, date-scoped* reference table, because retrofitting a hierarchy onto a code column
> after items reference it is exactly the migration we are writing this document to avoid.

---

## 7. Our design

### 7.1 One determination function, one result table

Tax determination becomes a single pure function evaluated per **document line**:

```
determine_tax(company_id, kind, posting_date, party_id, item_id,
              origin_jurisdiction_id, destination_jurisdiction_id,
              tax_category_id, line_amount) -> set of tax_line
```

It writes `tax_line` rows: `(document_line_id, tax_code_id, applicability, rate, basis,
jurisdiction_id, rule_id, rule_version)`. Two properties matter more than the algorithm:

1. **`rule_id` and `rule_version` are stored.** Every tax amount on every document points at the rule
   revision that produced it. This is the one thing ERPNext cannot do at all, and it is the first
   thing an auditor asks.
2. **The header is a view.** `document_tax` aggregates `tax_line` by `tax_code_id`. There are no
   placeholder rows, no `set_by_item_tax_template` flag, and no possibility of the header disagreeing
   with the lines.

### 7.2 Matching is ranges and hierarchies, in the database

| Concern | ERPNext | Ours |
|---|---|---|
| Rule overlap | save-time scan with two holes (§3.2) | `EXCLUDE USING gist` over `daterange` + filter columns |
| Geography | `Data` city/state/zipcode string equality | `tax_jurisdiction` hierarchy, FK from `address`, recursive CTE |
| Party group | ancestor chain (works) | same, via `parent_id` recursive CTE |
| Item group | **exact match only** | same recursive CTE as party group |
| Blank field | wildcard — except `tax_category`, which is exact | one rule: `NULL` = wildcard, everywhere |
| Precedence | specificity, then `priority` | `priority DESC, specificity DESC, valid_from DESC, id` |
| Tie-break | arbitrary (`[0]` of an unordered list) | total order ending in `id` |
| Retired template | winning rule returns `None`, tax silently vanishes | inactive rows never enter the candidate set |
| No match | `None`, indistinguishable from "no tax" | typed `no_rule` outcome; `on_missing` policy per regime |

`specificity` is a **stored generated column** — the count of non-`NULL` filter columns — so ranking
is index-friendly and not recomputed per document.

### 7.3 Validity is a range, and end-dating is not deletion

Every master in this subsystem gets `valid_from date NOT NULL` and `valid_to date` (exclusive upper
bound, `NULL` = open), with:

- `EXCLUDE USING gist (… WITH =, daterange(valid_from, valid_to) WITH &&)` per logical key;
- `is_active` as a generated column over `now()`, never a hand-set flag;
- **no** `disabled` checkbox anywhere — §1's dead flag and §3.3's landmine both disappear.

This also fixes the `Item Tax` child's missing `valid_upto`: slab rows become
`(tax_category_id, numrange(min_amount, max_amount), daterange(valid_from, valid_to))` with an
`EXCLUDE` constraint covering both ranges, so overlapping slabs are rejected at write time and the
buggy sort at `get_item_details.py:832` has no analogue — the matching row is found by
`WHERE line_amount <@ amount_range AND posting_date <@ validity`, which is a single indexed lookup
returning at most one row by construction.

### 7.4 Rates and applicability are typed

```
rate          numeric(9,6) NOT NULL
applicability enum('taxable','zero_rated','exempt','not_applicable','reverse_charge')
CHECK (applicability = 'taxable' OR rate = 0)
```

The `"N/A"` sentinel string (§4.2) has no place to live, and zero-rated versus exempt — a distinction
every real tax authority requires in returns — is expressible for the first time.

### 7.5 Withholding

- `withholding_category` + `withholding_rate` with `(category_id, group_id, daterange)` under an
  `EXCLUDE` constraint, so §5.1's boundary-date ambiguity cannot occur; the reader uses
  `posting_date <@ daterange` and gets exactly one row.
- `threshold_basis enum('single','cumulative','both','always')` on the rate row. `'always'` replaces
  `PaymentTaxWithholding`'s two overridden methods (§5.3) with a data value, so payments, invoices
  and journals share one code path.
- `withholding_group_id` moves onto the **line**, alongside `withholding_category_id`, so a document
  may mix groups.
- `apply_withholding` is derived, never a checkbox set by one entry path and not another (§5.2): a
  line withholds iff determination found a category for it.
- `party_tax_identity` as a first-class table, because §5.4 shows the domain already treats the tax
  number as the identity for certificates. Certificates, thresholds and cumulative totals all key on
  it.

### 7.6 Invariants

- **T1** Every `tax_line` references a `tax_rule` revision that was active on the document's
  `posting_date`. Enforced by FK to `tax_rule_version` plus a `CHECK` that
  `posting_date <@ version.validity`.
- **T2** No two `tax_rule` rows share a filter signature and priority over overlapping validity —
  `EXCLUDE USING gist`.
- **T3** For every document line, `Σ tax_line.rate` per `tax_code_id` is single-valued: a line cannot
  carry two rates for one tax. `UNIQUE (document_line_id, tax_code_id)`.
- **T4** `applicability <> 'taxable' ⇒ rate = 0`, and `rate > 0 ⇒ applicability = 'taxable'`.
- **T5** A withholding certificate's consumed amount never exceeds its limit — deferred trigger on
  the withholding ledger, compared with `>`, not truthiness.
- **T6** Determination is deterministic: re-running `determine_tax` with the same inputs against the
  same rule versions yields byte-identical `tax_line` rows. This is testable, and it is what makes a
  tax engine defensible.

---

## 8. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| `Tax Category` as a bare label with an unread `disabled` flag | **Reject** | real table, date-scoped, FK everywhere, no flag |
| Tax category from address, chosen by one global setting | **Reject** | `tax_situs` per line; origin/destination is a `tax_regime` property |
| POS-profile tax category applied *after* rule matching | **Reject (bug)** | one resolution step before determination |
| Purchase tax category from the supplier's address only | **Reject** | explicit origin **and** destination jurisdictions |
| `Tax Rule` matching on `Data` city/state/zipcode | **Reject** | `tax_jurisdiction` hierarchy with FK from `address` |
| Conflict detection by save-time scan | **Reject** | `EXCLUDE USING gist` |
| Date-overlap predicate missing containment | **Reject (bug)** | `daterange` `&&` |
| Only `tax_rule[0]` inspected for conflicts | **Reject (bug)** | constraint, no row inspection |
| Blank = wildcard, **except** `tax_category` = exact | **Reject** | `NULL` = wildcard, one rule |
| Party group hierarchy honoured, item group not | **Reject** | same recursive CTE for both |
| Specificity outranking `priority` | **Reject** | `priority` first; specificity as a stored generated column |
| Arbitrary tie-break (`[0]` of unordered rows) | **Reject** | total order ending in `id` |
| Disabled winning template → `None`, tax silently disappears | **Reject** | inactive rows excluded from candidates; `no_rule` is typed |
| "One template per tax category" forbidding disabled history | **Reject** | `UNIQUE … WHERE is_active`, history end-dated |
| `is_default` by bulk `UPDATE` | **Reject** | partial unique index |
| Default template selected without a `disabled` filter, rejected later at validate | **Reject** | cannot be selected |
| Template rows **copied** onto the document | **Keep** | plus `tax_template_version_id` provenance |
| `NOT_APPLICABLE_TAX = "N/A"` in a `Float` column | **Reject** | `applicability` enum + `numeric` rate |
| Item tax template chosen by `bill_date` first | **Keep** | `tax_point_date` per line, explicit |
| Slab selection via `minimum/maximum_net_rate` | **Keep the capability** | `numrange` + `EXCLUDE`, single indexed lookup |
| `Item Tax` with `valid_from` and **no** `valid_upto` | **Reject** | `daterange` with exclusion constraint |
| Sort key closing over the leaked loop variable (`:832`) | **Reject (bug)** | no sort needed; constraint guarantees one match |
| `for_validate` dedupe that is always a no-op (`:837`) | **Reject (bug)** | — |
| Existing item tax template kept despite a category change (`:853`) | **Reject (bug)** | determination is a pure function, re-run on any input change |
| Two `Accounts Settings` booleans gating tax composition | **Reject** | header is a view over `tax_line` |
| Withholding rate-row overlap allowed on the boundary date | **Reject** | `EXCLUDE` on `daterange` |
| `get_applicable_tax_row` throwing on an unconfigured date | **Keep** | typed error naming the category and the gap |
| Inverted validation message ("From Date cannot be before To Date") | **Reject** | — |
| Withholding category per line, group per header | **Reject** | both on the line |
| `apply_tds` auto-enabled only when `not for_validate` | **Reject (bug)** | derived from determination |
| `PaymentTaxWithholding` overriding thresholds in a subclass | **Reject the mechanism, keep the rule** | `threshold_basis = 'always'` in data |
| LDC keyed on the party's **tax ID**, not the party | **ADOPT** | `party_tax_identity` as a first-class table |
| "Only one LDC valid at a time" as a docstring assumption | **Reject** | `EXCLUDE` constraint |
| `if not unutilized_amount` letting over-used certificates through | **Reject (bug)** | `remaining > 0` |
| `Customs Tariff Number` as a flat code | **Reject** | `commodity_code` hierarchy + date scope |

---

Cross-references: doc 05 (the totals pipeline these rates feed, and the withholding calculation),
doc 26 §3 (the dimension mechanism, and why `Tax Category` is not one),
doc 21 §4 (`@allow_regional` — the regional tax overlay that supplies place-of-supply logic),
doc 27 §2 (`Item Standard Cost` — the effective-dating pattern we reuse for tax validity),
doc 17 §7.4 (`Item Price` overlap, the same missing-constraint shape),
**[S01](../scenarios/S01-order-to-cash.md)** (where determination happens in a real flow),
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
