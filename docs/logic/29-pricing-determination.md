# 29 — Pricing and Eligibility Determination

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Doc 05 §5.8 covered how a discovered `Pricing Rule` is *applied* — margins, `rate_or_discount`, free
items, transaction-level rules. Doc 17 §4 covered `Item Price` and its missing overlap detection.
Doc 28 did the same job for tax. This document covers what is left, and it is the larger half:

> Which **price list**, which **rule**, and in what **order** — and separately, which items is this
> party even allowed to buy?

The chain, in the order it actually executes:

```
1. price list          Selling/Buying Settings default -> POS Profile -> party -> Blanket Order
2. Price List master   currency, enabled, uom-dependence          (§2)
3. Item Price          rate for (item, price_list, uom, qty, date) (doc 17 §4)
4. Pricing Rule        discovery -> filtering -> precedence        (§4, §5)
     └─ Promotional Scheme generates these as documents            (§6)
     └─ Coupon Code gates one of them                              (§7)
5. Shipping Rule       freight, as a tax row                       (§8)
```

and two eligibility mechanisms that are not pricing at all but live in the same masters:

```
Party Specific Item   which items a party may transact  (§9) — enforced only in link-field search
Item Alternative      which items may substitute        (§10)
```

Closes the `docs/COVERAGE.md` gaps for `Price List`, `Pricing Rule`, `Promotional Scheme`,
`Coupon Code`, `Shipping Rule`, `Party Specific Item`, and `Item Alternative`.

---

## 1. The shape of the problem

Pricing determination has the same structure as tax determination, and repeats most of the same
mistakes, but it adds one that tax does not have: **the answer is written back into the masters.**
`Promotional Scheme` *creates and deletes* `Pricing Rule` documents (§6); `Price List` *rewrites*
`Item Price` rows (§2.2); `insert_item_price` can *create* `Item Price` rows from a transaction
(doc 05 §5.9). Configuration and data are not separated here, so the audit question "what price was
this order entitled to on the day it was placed" is unanswerable in general — the rule may no longer
exist.

---

## 2. `Price List`

`PriceList` (`stock/doctype/price_list/price_list.py:11`). Fields: `price_list_name`, `currency`,
`enabled`, `buying`, `selling`, `price_not_uom_dependent`, and a `countries` child table.

`validate` (`:31`) is one line: it must be applicable for buying or selling.

### 2.1 Saving a price list mutates global settings

```python
def on_update(self):                          # :35
    self.set_default_if_missing()
    self.update_item_price()
    self.delete_price_list_details_key()

def set_default_if_missing(self):             # :40
    if cint(self.selling):
        if not frappe.get_single_value("Selling Settings", "selling_price_list"):
            frappe.set_value("Selling Settings", "Selling Settings", "selling_price_list", self.name)
    elif cint(self.buying):
        if not frappe.db.get_single_value("Buying Settings", "buying_price_list"):
            frappe.set_value("Buying Settings", "Buying Settings", "buying_price_list", self.name)
```

Creating a price list can silently become the **company-wide default**. Note the `elif`: a list
flagged both buying and selling can only ever fill the *selling* default, so a fresh site whose first
price list is both never acquires a buying default.

`on_trash` (`:60`) nulls the settings field again, saving `Selling Settings` / `Buying Settings` with
`ignore_permissions = True`.

### 2.2 Renaming the currency reinterprets every stored price

```python
def update_item_price(self):                  # :49
    frappe.qb.update(item_price)
        .set(item_price.currency, self.currency)
        .set(item_price.buying,  cint(self.buying))
        .set(item_price.selling, cint(self.selling))
        .set(item_price.modified, now())
        .where(item_price.price_list == self.name).run()
```

⚠️ `Item Price.currency` is a **denormalised copy** of the price list's currency, and every save
pushes the parent's value down. Change a price list from `USD` to `EUR` and every stored
`price_list_rate` is re-labelled without being converted — `100 USD` silently becomes `100 EUR`. There
is no guard, no confirmation, and no conversion. The same `UPDATE` also rewrites `buying`/`selling`
on every child row, so those are duplicated state too.

> **Ours** `item_price` has no `currency`, `buying` or `selling` column at all — they are properties
> of `price_list`, read by join. Currency is immutable after the first `item_price` row exists,
> enforced by a trigger; changing it means creating a new price list and an explicit, audited
> conversion run. Denormalising a currency code next to an amount is the single most dangerous
> duplication in an ERP schema, because the copy is what makes the number meaningful.

### 2.3 The `enabled` check lives behind a cache

```python
def get_price_list_details(price_list):                        # :79
    price_list_details = frappe.cache().hget("price_list_details", price_list)
    if not price_list_details:
        price_list_details = frappe.get_cached_value(
            "Price List", price_list, ["currency", "price_not_uom_dependent", "enabled"], as_dict=1)
        if not price_list_details or not price_list_details.get("enabled"):
            throw(_("Price List {0} is disabled or does not exist"))
        frappe.cache().hset("price_list_details", price_list, price_list_details)
    return price_list_details or {}
```

The `enabled` test runs **only on a cache miss**. The cache is invalidated by
`delete_price_list_details_key` (`:75`) from `on_update` and `on_trash`, so the ORM path is safe — but
any `frappe.db.set_value("Price List", …, "enabled", 0)` that bypasses `on_update` leaves a disabled
price list usable until the Redis key expires. This is the app-level cache-invalidation pattern doc
18 §6 and doc 22 §5 catalogue; here it gates whether a price list may be sold from.

### 2.4 `price_not_uom_dependent` is broken in both directions

The flag is stored as `price_not_uom_dependent` (a **negative**) and consumed as
`price_list_uom_dependant` (a **positive**). Two separate defects follow.

**It never arrives.** `get_price_list_currency_and_exchange_rate`
(`stock/get_item_details.py:1663`) does:

```python
price_list_details      = get_price_list_details(ctx.price_list)   # returns price_not_uom_dependent
price_list_uom_dependant = price_list_details.get("price_list_uom_dependant")   # :1674  -> always None
```

⚠️ The key it asks for is not a key `get_price_list_details` returns, so `price_list_uom_dependant` is
**always `None`** on this path. Downstream, `get_item_price_rate`
(`stock/get_item_details.py:1324`) reads:

```python
if item_price_data[0].uom == ctx.get("uom"):    return price_list_rate
elif not ctx.get("price_list_uom_dependant"):   return flt(price_list_rate * conversion_factor)
else:                                           return price_list_rate
```

so the UOM conversion branch is taken unconditionally. A price list configured as "prices are not UOM
dependent" behaves as if it were, unless a caller supplies the key itself.

**Where a caller does supply it, the polarity is inverted.** `MaterialRequest.update_item_rates`
(`stock/doctype/material_request/material_request.py:209`):

```python
price_not_uom_dependent = frappe.get_value("Price List", self.buying_price_list, "price_not_uom_dependent")
...
"price_list_uom_dependant": price_not_uom_dependent,          # :222
```

⚠️ A value meaning "*not* UOM dependent" is passed as "*is* UOM dependent". On a Material Request the
flag is therefore honoured **backwards**, and everywhere else it is ignored.

> **Ours** One field, named positively, with no negation anywhere: `price_list.rate_is_per_uom
> boolean NOT NULL DEFAULT true`. It is read by join at resolve time, never copied into a context
> dict, so there is no boundary at which a rename or a negation can be introduced. A boolean whose
> name contains "not" is a defect waiting for a second reader.

### 2.5 `Price List.countries` is dead

The `countries` child table (`Price List Country`) is referenced only in the auto-generated type block
(`:20`). No Python reads it — the only `.countries` consumers in the app are on `Shipping Rule`
(`accounts/doctype/shipping_rule/shipping_rule.py:129`, `:135`). Country-scoped price lists look
configurable and are not, which is the same class of finding as `Tax Category.disabled` in doc 28 §1.

---

## 3. `Item Price`

Covered in doc 17 §4: `item_code`, `price_list`, `uom`, `min_qty`, `valid_from`, `valid_upto`,
`price_list_rate`, `currency`, with duplicate detection that only catches an *identical* validity pair
(`stock/doctype/item_price/item_price.py:87`–`:141`) and therefore permits overlapping ranges.

Two additions relevant to determination:

- The `currency`, `buying` and `selling` columns are **not independent** — §2.2 overwrites them from
  the parent on every price-list save.
- Transactions can create `Item Price` rows. Under `Stock Settings.update_existing_price_list_rate`,
  `insert_item_price` writes a rate back from a submitted document (doc 05 §5.9), so the master is
  partly a by-product of transactions rather than an input to them.

---

## 4. `Pricing Rule` — the master's own rules

`PricingRule` (`accounts/doctype/pricing_rule/pricing_rule.py:20`) has 60-odd fields and thirteen
validations (`validate`, `:130`). Doc 05 covered application; these are the constraints on the rule
itself.

### 4.1 `priority` is a string

```python
priority: DF.Literal["", "1", "2", "3", ..., "20"]
```

⚠️ **`priority` is a `Select` of strings, not an integer.** Consequences show up in §5.2: the SQL
`ORDER BY` sorts it lexicographically, so `'9' > '20' > '2' > '10'`. Python code that compares it
mostly wraps it in `cint(...)`, so the two disagree with each other.

`validate_mandatory` (`:177`) also couples `priority` to a checkbox:

```python
if self.has_priority and not self.priority:  throw("Priority is mandatory")
if self.priority and not self.has_priority:  self.has_priority = 1
```

— a flag that duplicates "the field is non-empty", kept in sync by validation rather than being
derived. And `apply_discount_on_rate` (discount-on-discounted-rate) **requires** `priority` and
requires it to be `> 1`, because compounding depends on evaluation order (`:194`–`:218`).

### 4.2 The interesting validations

- `validate_duplicate_apply_on` (`:148`) rejects the same item/group/brand twice in one rule, then
  `validate_template_with_variant` (`:162`) rejects a template **and** one of its variants coexisting
  in the same rule — a genuinely thoughtful check, because the variant would match twice.
- `validate_applicable_for_selling_or_buying` (`:220`) cross-checks direction against
  `applicable_for`: `Customer`/`Customer Group`/`Territory`/`Sales Partner`/`Campaign` require
  `selling`; `Supplier`/`Supplier Group` require `buying`.
- `cleanup_fields_value` (`:260`) walks the `Select` options of `apply_on`, `applicable_for` and
  `rate_or_discount` and **nulls every field belonging to a non-selected option**. So the table is
  wide, sparse, and kept consistent by a loop over field metadata — the same "one table, many
  documents" pattern as `Journal Entry` (doc 26 §4) and `Tax Rule` (doc 28 §3.1), but here the
  cleanup is metadata-driven, which means adding a `Select` option silently changes which columns get
  wiped.
- `validate_max_discount` (`:305`) compares `discount_percentage` against `Item.max_discount` — but
  only when `rate_or_discount == "Discount Percentage"` **and** the rule lists explicit items. An
  item-group or brand rule bypasses the per-item ceiling entirely.
- `validate_price_list_with_currency` (`:312`) requires `currency == Price List.currency`.
- `validate_dates` (`:318`) requires both dates when `is_cumulative`, then the standard
  from/to check. There is **no overlap detection between rules** at all — conflicts are discovered at
  transaction time and raised as `MultiplePricingRuleConflict` (§5.3).
- `validate_recursion` (`:248`) guards the recursive free-item feature: `min_qty` must exceed
  `apply_recursion_over`, which must be ≥ 0.
- `validate_mixed_with_recursion` (`:332`) rejects `mixed_conditions` + `is_recursive` outright —
  an unimplemented combination declared in data.

### 4.3 `condition` is arbitrary code, screened by a regex

```python
def validate_condition(self):                                    # :324
    if (self.condition and ("=" in self.condition)
            and re.match(r'[\w\.:_]+\s*={1}\s*[\w\.@\'"]+', self.condition)):
        frappe.throw(_("Invalid condition expression"))
```

The intent is to reject assignment while allowing comparison, and `==` does slip past the pattern as
designed. But `re.match` anchors at position 0, and `[\w\.:_]+` cannot match a space — so a condition
beginning with **whitespace** bypasses the check entirely. The real protection is `frappe.safe_eval`
at evaluation time (`accounts/doctype/pricing_rule/utils.py:89`), which is doc 21 §3's territory: user
data evaluated as Python, screened by a regex.

> **Ours** No user-authored expressions in pricing. A rule's applicability is columns and ranges
> only; anything genuinely conditional is a `rule_predicate` row with a typed operator
> (`eq`/`in`/`between`/`gt`) over a whitelisted field set, which is indexable, explainable, and cannot
> raise at evaluation time. The set of predicates is deliberately small — if a business needs more,
> that is a schema change with a migration, not an eval.

---

## 5. Rule discovery and precedence

`get_pricing_rules` (`accounts/doctype/pricing_rule/utils.py:26`) is the entry point. Doc 05 §5.8
documented the SQL and the qty/amount filters; this section is about **which rule wins**, which doc 05
did not resolve.

### 5.1 Specificity is a `break`, and the first row governs the batch

```python
for apply_on in ["Item Code", "Item Group", "Brand"]:                     # :34
    pricing_rules.extend(_get_pricing_rules(apply_on, args, values))
    if pricing_rules and pricing_rules[0].has_priority:
        continue
    if pricing_rules and not apply_multiple_pricing_rules(pricing_rules):
        break
```

Item Code beats Item Group beats Brand, implemented by stopping early. Two properties of the
**accumulated list's first element** steer the loop: `pricing_rules[0].has_priority`, and
`apply_multiple_pricing_rules` (`:179`) which returns `True` only if **every** rule has the flag.

`filter_pricing_rules` (`:276`) then repeats the pattern more consequentially:

```python
pr_doc = frappe.get_cached_doc("Pricing Rule", pricing_rules[0].name)     # :287
if pricing_rules[0].mixed_conditions and doc:  ...
elif pricing_rules[0].is_cumulative:           ...
if pricing_rules[0].apply_rule_on_other and not pricing_rules[0].mixed_conditions and doc: ...
```

⚠️ `mixed_conditions`, `is_cumulative` and `apply_rule_on_other` are read from `pricing_rules[0]` and
applied to the **whole list**. A batch containing one mixed-condition rule and one ordinary rule is
processed entirely as one or the other depending on which happens to be first — and "first" is decided
by the string-sorted SQL order in §5.2.

### 5.2 The SQL order and the Python filter disagree

`_get_pricing_rules` (`:110`) ends with:

```sql
order by coalesce(`tabPricing Rule`.priority, '') desc, ...     -- :159
```

`priority` is a `varchar`, so this is a **lexicographic** sort: priority `9` outranks `20`, and `10`
sorts below `2`. Later, Python re-does it numerically:

```python
max_priority = max(cint(p.priority) for p in pricing_rules)     # :333
if max_priority:
    pricing_rules = list(filter(lambda x: cint(x.priority) == max_priority, pricing_rules))
```

So the *final* winner is chosen numerically and is correct — but every decision that reads
`pricing_rules[0]` before this point (§5.1) uses the string order. With single-digit priorities the two
agree and the bug is invisible; the `Select` allows up to `20`.

Note also `if max_priority:` — when every candidate has a blank priority, `cint("")` is `0`, `max` is
`0`, the filter is skipped, and the conflict throw in §5.3 fires. That is intentional, and it is why
the error message says "please resolve conflict by assigning priority".

### 5.3 Tie-breaking, and the webshop's silent divergence

After the priority filter:

```python
if len(pricing_rules) > 1:                                       # :328
    filtered = [r for r in pricing_rules if r.currency == args.currency] or pricing_rules
...
if len(pricing_rules) > 1:                                       # :341
    if all rules are "Discount Percentage":
        prefer those whose for_price_list == args.price_list
if len(pricing_rules) > 1 and not args.for_shopping_cart:        # :348
    frappe.throw(MultiplePricingRuleConflict, "Multiple Price Rules exist with same criteria...")
elif pricing_rules:
    return pricing_rules[0]
```

⚠️ The desk **refuses to price** an ambiguous line; the webshop (`for_shopping_cart`) silently takes
`pricing_rules[0]` — the first row of a list ordered by *string* priority. The same configuration
therefore prices differently online and in the back office, and neither path records which rule it
picked or why.

### 5.4 A failed condition means "no discount", silently

```python
def filter_pricing_rule_based_on_condition(pricing_rules, doc=None):     # :83
    if doc:
        for pricing_rule in pricing_rules:
            if pricing_rule.condition:
                try:
                    if frappe.safe_eval(pricing_rule.condition, None, doc.as_dict()):
                        filtered_pricing_rules.append(pricing_rule)
                except Exception:
                    frappe.log_error(title=f"Pricing Rule condition failed to evaluate: {pricing_rule.name}")
            else:
                filtered_pricing_rules.append(pricing_rule)
    else:
        filtered_pricing_rules = pricing_rules
```

Two behaviours worth naming:

1. A condition that **raises** is logged and the rule is dropped. The customer is quoted the
   undiscounted price and nobody is told; the evidence is in the Error Log.
2. `if doc:` — when no document object is passed, **conditions are not evaluated at all** and every
   conditional rule passes. `apply_pricing_rule` (`pricing_rule.py:341`) is whitelisted and `doc` is
   optional, so the same rule set yields different prices depending on whether the caller had a
   document to hand.

### 5.5 `sorted_by_priority` drops rules

```python
def sorted_by_priority(pricing_rules, args, doc=None):                   # :63
    for pricing_rule in pricing_rules:
        pricing_rule = filter_pricing_rules(args, pricing_rule, doc)
        if pricing_rule:
            if not pricing_rule.get("priority"):
                pricing_rule["priority"] = 1
            if pricing_rule.get("apply_multiple_pricing_rules"):
                pricing_rule_dict.setdefault(cint(pricing_rule.get("priority")), []).append(pricing_rule)
    for key in sorted(pricing_rule_dict):
        pricing_rules_list.extend(pricing_rule_dict.get(key))
```

A rule without `apply_multiple_pricing_rules` is **silently discarded** — it is neither added to the
dict nor returned. This path is only reached when `apply_multiple_pricing_rules(pricing_rules)` was
`True`, which requires *every* rule to carry the flag, so today the branch is unreachable for
flagless rules. It is an invariant maintained by two functions agreeing, with no assertion between
them.

Note also the ascending `sorted(pricing_rule_dict)`: for stacked rules, **lower priority applies
first**, so `apply_discount_on_rate` compounds upward. That is the opposite of the "highest priority
wins" semantics of the single-rule path in §5.2 — one field, two meanings, depending on a checkbox.

> **Ours** Precedence is one total order, declared once:
> `ORDER BY specificity DESC, priority DESC, valid_from DESC, id` for exclusive rules, and
> `ORDER BY stack_sequence ASC, id` for stacking rules — with `stack_sequence` a **separate integer
> column** from `priority`, because "which one wins" and "in what order do these compound" are
> different questions and must not share a field. `priority` is `smallint`. Ambiguity is prevented at
> write time by an `EXCLUDE` constraint on the filter signature plus validity range (as in doc 28
> §7.2), so no read path ever has to throw `MultiplePricingRuleConflict` or guess. Every applied rule
> is recorded on the line as `(rule_id, rule_version, matched_specificity)` — the desk and the webshop
> run the same function and record the same evidence.

---

## 6. `Promotional Scheme` — a master that writes documents

`PromotionalScheme` (`accounts/doctype/promotional_scheme/promotional_scheme.py:77`) is a *generator*.
One scheme holds `price_discount_slabs` and `product_discount_slabs` plus multi-select tables for
`customer`, `customer_group`, `territory`, `sales_partner`, `campaign`, `supplier`, `supplier_group` —
and on every save it materialises the cross product into individual `Pricing Rule` **documents**:

```
Pricing Rules created = (# discount slabs) × (# values of the applicable_for table)
```

`on_update` (`:211`) → `update_pricing_rules` (`:233`) → `get_pricing_rules` (`:268`) →
`_get_pricing_rules` (`:282`) → `prepare_pricing_rule` (`:345`) → `set_args` (`:362`).

### 6.1 It is a wide, brittle field copy

Three module-level lists (`pricing_rule_fields` `:12`, `other_fields` `:36`, `price_discount_fields`
`:47`, `product_discount_fields` `:59`) enumerate by name which fields to copy, and `set_args` (`:362`)
renames two of them on the way across:

```python
if target_field in ["min_amount", "max_amount"]:
    target_field = "min_amt" if field == "min_amount" else "max_amt"
```

The scheme's child calls it `min_amount`; `Pricing Rule` calls it `min_amt`. Add a field to
`Pricing Rule` and it is silently not propagated until someone edits one of these lists — the exact
failure mode that made `price_not_uom_dependent` (§2.4) wrong.

`prepare_pricing_rule` (`:345`) sets `pr.title = doc.name` for **every** generated rule, so all N rules
share one title and are distinguishable only by `promotional_scheme_id`.

### 6.2 `update_pricing_rules` builds a dictionary that means nothing

```python
rules = {}
names = []
for rule in pricing_rules:
    names.append(rule.name)
    rules[rule.get("promotional_scheme_id")] = names        # :237
```

⚠️ `names` is **one shared list**. Every key is assigned the same object, which keeps growing, so
`rules` maps every slab id to the full accumulated list of all rule names rather than to its own. The
only consumer is a membership test on the keys (`if d.name in rules`, `:290`), so the values are never
read and the bug is currently harmless — but the data structure does not express what its name claims,
and the next person to read a value will get nonsense.

### 6.3 Changing `applicable_for` deletes Pricing Rules

```python
def validate_pricing_rules(self):                            # :163
    invalid_pricing_rule = self.get_invalid_pricing_rules()   # :190
    if frappe.db.exists("Pricing Rule Detail",
                        {"pricing_rule": ["in", invalid_pricing_rule], "docstatus": ["<", 2]}):
        raise_for_transaction_exists(self.name)
    for doc in invalid_pricing_rule:
        frappe.delete_doc("Pricing Rule", doc)
```

`get_invalid_pricing_rules` (`:190`) finds every generated rule whose `applicable_for` no longer
matches the scheme's, and they are **hard-deleted**. The guard checks `Pricing Rule Detail` — the child
table each priced document carries — but only for `docstatus < 2`.

⚠️ A **cancelled** document's `Pricing Rule Detail` rows do not protect the rule. And `on_trash`
(`:255`) deletes *every* generated rule unconditionally:

```python
def on_trash(self):
    for rule in frappe.get_all("Pricing Rule", {"promotional_scheme": self.name}):
        frappe.delete_doc("Pricing Rule", rule.name)
```

So the record of *why* a historical order was discounted is destroyed by deleting the scheme. Whether
the delete succeeds at all depends on Frappe's application-level link check — the mechanism doc 19
lists eight bypasses for — rather than on a foreign key.

`on_update` (`:211`) also calls `self.validate()` a second time, so every save validates twice and
can delete rules from inside `on_update`.

> **Ours** A promotional scheme is **not** a generator. `pricing_rule` gets `scheme_id` and the
> applicability tables are joined at match time, so N×M rows never exist and there is nothing to
> regenerate, reconcile, or delete. Rules are **never deleted**: `valid_to` is set, and
> `ON DELETE RESTRICT` from `document_line_pricing` makes destroying priced history impossible at the
> storage layer rather than at the ORM layer. Changing who a scheme applies to end-dates the old
> applicability and inserts new rows — the old one stays readable forever, which is the entire point.

---

## 7. `Coupon Code`

`CouponCode` (`accounts/doctype/coupon_code/coupon_code.py:11`).

```python
def autoname(self):                                          # :34
    self.coupon_name = strip(self.coupon_name)
    self.name = self.coupon_name
    if not self.coupon_code:
        if self.coupon_type == "Promotional":
            self.coupon_code = "".join(i for i in self.coupon_name if not i.isdigit())[0:8].upper()
        elif self.coupon_type == "Gift Card":
            self.coupon_code = frappe.generate_hash()[:10].upper()
```

⚠️ The **primary key is `coupon_name`, not `coupon_code`.** A generated promotional code is the
coupon's name with digits stripped, truncated to eight characters and upper-cased — so
`Summer 2026 Sale` yields `SUMMER S` (spaces included), and `Summer 2027 Sale` yields the **same
code**. Nothing anywhere enforces uniqueness on `coupon_code`, and `validate_coupon_code`
(`accounts/doctype/pricing_rule/utils.py:751`) is called with the coupon's *name*, so the code a
customer types must be resolved to a name elsewhere. Two coupons sharing a code is a supported state.

`validate` (`:44`) forces `maximum_use = 1` for gift cards and requires a customer. `valid_from` and
`valid_upto` are **not** validated against each other.

### 7.1 `used` is an unlocked read-modify-write

```python
# accounts/doctype/pricing_rule/utils.py
def validate_coupon_code(coupon_name):                       # :751
    coupon = frappe.get_doc("Coupon Code", coupon_name)
    if coupon.valid_from and coupon.valid_from > getdate(today()):  throw("validity has not started")
    elif coupon.valid_upto and coupon.valid_upto < getdate(today()): throw("validity has expired")
    elif coupon.maximum_use and coupon.used >= coupon.maximum_use:  throw("no longer valid")

def update_coupon_code_count(coupon_name, transaction_type):  # :761
    coupon = frappe.get_doc("Coupon Code", coupon_name)
    if transaction_type == "used":
        if coupon.maximum_use and coupon.used >= coupon.maximum_use:
            frappe.throw("Allowed quantity is exhausted")
        coupon.used = coupon.used + 1
        coupon.save(ignore_permissions=True)
    elif transaction_type == "cancelled":
        if coupon.used > 0:
            coupon.used = coupon.used - 1
            coupon.save(ignore_permissions=True)
```

⚠️ Read, increment in Python, write — with no lock and no `SELECT … FOR UPDATE`. Two concurrent orders
both read `used = 4` and both write `5`. **`maximum_use` is not enforceable under concurrency**, which
for a single-use gift card means it can be redeemed twice. This is the same lost-update shape as
`per_transferred` in S04 and the budget check in doc 12 §1.2, but here the resource being
double-spent is money.

Called from `Sales Order` (`selling/doctype/sales_order/sales_order.py:239`, `:468`, `:503`),
`Sales Invoice` (`accounts/doctype/sales_invoice/sales_invoice.py:320`, `:483`, `:549`) and
`POS Invoice` (`accounts/doctype/pos_invoice/pos_invoice.py:238`, `:263`, `:304`). Because both an
order and its invoice increment, a coupon used on an order that is then invoiced consumes **two** uses
unless the flow happens to skip one.

> **Ours** `coupon_redemption` is an **insert-only** table: `(coupon_id, document_type, document_id,
> redeemed_at, reversed_by)`, with `UNIQUE (coupon_id, document_id)` and a partial unique index
> `UNIQUE (coupon_id) WHERE reversed_by IS NULL` for single-use coupons. `used` becomes a view
> (`COUNT(*) WHERE reversed_by IS NULL`); the limit is a deferred constraint, not a Python
> comparison. Un-redemption is a compensating row, exactly as with `settlement` in doc 11 §5. The
> order-then-invoice double count disappears because redemption attaches to the **fulfilment chain**
> (doc 10 §5), not to each document. `code` is `citext UNIQUE` and is the primary key users type;
> `name` is descriptive text with no uniqueness requirement.

---

## 8. `Shipping Rule`

`ShippingRule` (`accounts/doctype/shipping_rule/shipping_rule.py:27`): `calculate_based_on` ∈
`Fixed` / `Net Total` / `Net Weight`, a `conditions` child table of `(from_value, to_value,
shipping_amount)` slabs, a `countries` table, an `account`, and `shipping_rule_type` ∈
`Selling`/`Buying`.

`disabled` exists as a field and — like `Tax Category.disabled` in doc 28 §1 — **is never read in
Python**. `apply_shipping_rule` (`controllers/accounts_controller.py:948`) and
`calculate_shipping_charges` (`controllers/taxes_and_totals.py:418`) load the rule by name and apply
it whenever `doc.shipping_rule` is set.

### 8.1 The sort that does not sort

```python
def sort_shipping_rule_conditions(self):                     # :173
    """Sort Shipping Rule Conditions based on increasing From Value"""
    self.shipping_rules_conditions = sorted(self.conditions, key=lambda d: flt(d.from_value))
    for i, d in enumerate(self.conditions):
        d.idx = i + 1
```

⚠️ The sorted list is assigned to **`shipping_rules_conditions`** — a different, non-existent
attribute — and then `self.conditions` is renumbered **in its original order**. The sort result is
discarded. The docstring states the intent; the code does not do it.

This matters because of how slabs are read:

```python
def get_shipping_amount_from_rules(self, value):             # :120
    for condition in self.get("conditions"):
        if not condition.to_value or (flt(condition.from_value) <= flt(value) <= flt(condition.to_value)):
            return condition.shipping_amount
    return 0.0
```

⚠️ The open-ended slab (`to_value` blank — `validate_from_to_values` `:59` permits exactly one) matches
**any** value, because `not condition.to_value` short-circuits before `from_value` is even considered.
Iteration is in child-table order. So a rule whose open-ended row sits first charges that row's amount
for every shipment, including a 1 kg parcel against a "500 kg and above" slab. The sort at `:173` was
what should have prevented it.

### 8.2 Overlap detection has three gaps

```python
def overlap_exists_between(num_range1, num_range2):          # :180
    (x1, x2), (y1, y2) = num_range1, num_range2
    separate = (x1 <= x2 <= y1 <= y2) or (y1 <= y2 <= x1 <= x2)
    return not separate
...
if d1.as_dict() != d2.as_dict():                             # :188
    range_a = (d1.from_value, d1.to_value or d1.from_value)
    range_b = (d2.from_value, d2.to_value or d2.from_value)
```

1. The junction uses `<=`, so `(100, 300)` and `(300, 400)` are "separate" — while
   `get_shipping_amount_from_rules` matches `300` inclusively in **both**. Same boundary ambiguity as
   doc 28 §5.1.
2. `if d1.as_dict() != d2.as_dict()` skips comparison when two rows are *identical*, so exact
   duplicate slabs are permitted.
3. The open-ended row is compared as the degenerate point `(from, from)`, so it never conflicts with
   anything — including a bounded slab that contains it.

### 8.3 Application details

`apply` (`:89`) computes the amount, then:

```python
if doc.currency != doc.company_currency:
    shipping_amount = flt(shipping_amount / doc.conversion_rate, 2)      # :112
```

⚠️ Precision **hard-coded to 2**, regardless of the currency's actual precision or the
`Currency Precision` system setting — for a 3-decimal currency (KWD, BHD) freight is silently
truncated.

`add_shipping_rule_to_tax_table` (`:142`) appends an `Actual` charge row, and on the buying side sets:

```python
shipping_charge["category"] = "Valuation and Total" if doc.get_stock_items() or doc.get_asset_items() else "Total"
```

so **whether freight is capitalised into inventory depends on whether any line is a stock item** —
which is the landed-cost decision from doc 03 §3.4 and S04 §5, made here as a side effect of a tax-row
default. If a matching row already exists, `existing_shipping_charge[-1].tax_amount = shipping_amount`
takes "the last record found" and overwrites it, silently, rather than reporting the duplicate.

`remove_shipping_charge` (`controllers/selling_controller.py:180`) has a latent defect:
`frappe.get_last_doc("Shipping Rule", self.shipping_rule)` passes a **docname** where
`get_last_doc` (`frappe/model/document.py:2806`) expects `filters` — a string there is handed to
`frappe.get_all` as a raw condition, so this does not fetch the named rule. The method has no callers,
so it is dead rather than broken.

> **Ours** `shipping_rule_slab` uses `numrange(from_value, to_value)` with
> `EXCLUDE USING gist (rule_id WITH =, band WITH &&)`, so overlaps, duplicates and the open-ended row
> are all handled by one constraint and the lookup is `WHERE value <@ band` — at most one row, no
> ordering, no short-circuit. `is_active` is derived from validity dates rather than a flag no code
> reads. Freight is a `document_charge` row with an explicit
> `capitalise boolean` set by determination from the **regime**, not inferred from whether a stock
> item happens to be present. Rounding uses the currency's own scale from `currency.minor_unit_scale`.

---

## 9. `Party Specific Item` — an eligibility rule enforced only in the UI

`PartySpecificItem` (`selling/doctype/party_specific_item/party_specific_item.py:9`) restricts which
items a party may transact: `party_type` ∈ `Customer`/`Customer Group`/`Supplier`/`Supplier Group`,
`restrict_based_on` ∈ `Item`/`Item Group`/`Brand`, and a `based_on_value`.

Its only validation (`:24`) is an exact-duplicate check.

⚠️ **It is enforced in exactly one place: the link-field search.** `item_query`
(`controllers/queries.py:226`, `:232`) loads the rules and narrows the item list offered in the UI.
Nothing in any controller's `validate` re-checks it, so the REST API, Data Import, a script, or simply
typing a full item code that skips the search dropdown all bypass the restriction completely. This is
precisely the class of gap doc 19 catalogues: a business rule living in a query helper rather than in
the data model.

Two secondary observations:

- The query loads **every** `Party Specific Item` row for the party type with no party filter, then
  partitions in Python (`restricted_items` / `allowed_items` defaultdicts) — a full-table read on each
  keystroke in an item field.
- Group rules are matched against the party's own group only (`current_party_group`, `:238`); the
  group **hierarchy** is not walked, so a rule on a parent customer group does not restrict its
  children — the same inconsistency doc 28 §3.3 found between `customer_group` and `item_group`.

> **Ours** Eligibility is a database predicate, not a search filter. `party_item_eligibility` with
> `(party_scope_type, party_scope_id, item_scope_type, item_scope_id, mode enum('allow','deny'))`,
> resolved by the same recursive CTE as everything else so hierarchies work, and enforced by a
> **`CHECK` via trigger on `document_line`** so no entry path can skip it. The link-field search calls
> the *same* function, so what the UI offers and what the database accepts cannot diverge.

---

## 10. `Item Alternative`

`ItemAlternative` (`stock/doctype/item_alternative/item_alternative.py:13`) records that
`alternative_item_code` may substitute for `item_code`, optionally `two_way`.

`has_alternative_item` (`:34`) requires `Item.allow_alternative_item` on the primary; `two_way`
requires it on both (`:71`).

`validate_alternative_item` (`:38`) compares five fields between the two items:

```python
fields = ["is_stock_item", "include_item_in_manufacturing", "has_serial_no", "has_batch_no",
          "allow_alternative_item"]
for field in fields:
    if item_data.get(field) != alternative_item_data.get(field):
        raise_exception, alert = [1, False] if field == "is_stock_item" else [0, True]
        frappe.msgprint(..., alert=alert, raise_exception=raise_exception)
```

⚠️ Only `is_stock_item` **throws**. A mismatch in `has_serial_no` or `has_batch_no` is an *alert* that
the user can dismiss — so a batch-tracked item may be substituted for an untracked one. Since the
serial/batch bundle is mandatory exactly when the item is tracked (doc 27 §6.4), the substitution
produces a document that fails validation later, at submit, in a different module.

`validate_duplicate` (`:75`) enforces uniqueness on the ordered pair `(item_code,
alternative_item_code)`. ⚠️ With `two_way`, the **reverse** pair is not checked: `A→B two_way` and
`B→A` can both exist, describing the same relationship twice. `get_alternative_items` (`:89`) then
unions both legs and de-duplicates with `dict.fromkeys`, and its own comment — "each leg has distinct
values (validate_duplicate), so start+page_len rows per leg suffice" — assumes the legs are disjoint,
which `two_way` makes untrue. The result is a short page, not a wrong one.

> **Ours** `item_substitution (item_id, substitute_item_id, is_bidirectional, valid_from, valid_to)`
> with `CHECK (item_id <> substitute_item_id)` and, for bidirectional rows, a canonical ordering
> `CHECK (NOT is_bidirectional OR item_id < substitute_item_id)` plus
> `UNIQUE (item_id, substitute_item_id)` — so a relationship has exactly one representation and the
> reverse duplicate is unrepresentable. Tracking compatibility (`is_stock_item`, serial/batch
> requirement) is a `CHECK` against both items' generated `tracking_mode` column: incompatible
> substitutions are rejected at write time, not warned about and then failed at submit.

---

## 11. Our design

### 11.1 Price resolution is a pure function with recorded evidence

```
resolve_price(company_id, kind, party_id, price_list_id, item_id, uom_id,
              qty_stock, posting_date) -> (rate, currency_id, source)
```

`source` is a typed value — `item_price`, `price_list_default`, `blanket_order`, `last_purchase`,
`manual` — and it is **stored on the line** alongside `item_price_id` and `price_list_id`. Doc 05 §5.9
showed ERPNext derives `price_list_rate`, `rate_with_margin`, `discount_amount` and `rate` from each
other in a loop that cannot be inverted; storing the source and the identity of the winning row makes
the derivation one-directional and auditable.

### 11.2 Every master in this subsystem gets range constraints

The same treatment as doc 28 §7.3, because these are the same shapes:

| Table | Key | Constraint |
|---|---|---|
| `item_price` | `(price_list_id, item_id, uom_id)` | `EXCLUDE` on `numrange(min_qty,max_qty)` **and** `daterange(valid_from,valid_to)` |
| `pricing_rule` | filter signature + `priority` | `EXCLUDE` on `daterange` |
| `shipping_rule_slab` | `rule_id` | `EXCLUDE` on `numrange(from_value,to_value)` |
| `coupon` | `code` | `citext UNIQUE`; single-use via partial unique on redemption |
| `item_substitution` | `(item_id, substitute_item_id)` | `UNIQUE` + canonical ordering `CHECK` |
| `party_item_eligibility` | scope tuple | `UNIQUE` |

No `disabled` checkboxes: §2.5, §8 and doc 28 §1 between them found three flags that no code reads.
Active-ness is `valid_from`/`valid_to` and a generated `is_active`, which the matcher already honours.

### 11.3 Determination is one ordering, and stacking is a separate field

- `priority smallint` — "which rule wins", used only for exclusive rules.
- `stack_sequence smallint` — "in what order do these compound", used only when
  `is_stackable = true`.

ERPNext overloads one string `Select` for both (§5.2, §5.5), sorts it lexicographically in SQL and
numerically in Python, and reverses its direction depending on a checkbox. Two integer columns with
one documented meaning each remove the entire class of problem.

Applied rules are recorded per line in `document_line_pricing (document_line_id, rule_id,
rule_version, stack_sequence, rate_before, rate_after)` — an ordered, replayable audit of how the
final rate was reached, with `ON DELETE RESTRICT` back to `pricing_rule` so §6.3's deletions are
impossible.

### 11.4 Invariants

- **P1** Every priced line references an `item_price` row (or a typed non-`item_price` source) whose
  validity contains the line's `price_date`. FK + `CHECK`.
- **P2** No two `item_price` rows overlap in both qty band and validity for the same
  `(price_list, item, uom)` — `EXCLUDE USING gist`. (Doc 17 §4 showed ERPNext detects only identical
  pairs.)
- **P3** `Σ document_line_pricing.rate_after` of the last stack step equals `document_line.rate`.
  A line's rate is reconstructible from its recorded rule applications.
- **P4** A coupon's live redemption count never exceeds `maximum_use` — deferred constraint over
  `coupon_redemption`, not a Python comparison (§7.1).
- **P5** A `pricing_rule` referenced by any `document_line_pricing` row can never be deleted, only
  end-dated — `ON DELETE RESTRICT` (§6.3).
- **P6** For any `(value, shipping_rule)` at most one slab matches — guaranteed by the `EXCLUDE`
  constraint rather than by loop order (§8.1).
- **P7** A line's item is eligible for its party under `party_item_eligibility`, enforced by trigger
  on every write path (§9).

---

## 12. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Saving a `Price List` silently sets the global default | **Reject** | defaults are explicit config, set deliberately |
| `elif` meaning a buying+selling list never fills the buying default | **Reject (bug)** | independent per-kind defaults |
| `Item Price.currency` denormalised, rewritten from the parent | **Reject** | no currency column; currency immutable once prices exist |
| Price-list currency change re-labels amounts without converting | **Reject (data loss)** | trigger-blocked; conversion is an audited run |
| `enabled` checked only on a Redis cache miss | **Reject** | `is_active` from validity dates, checked in the query |
| `price_not_uom_dependent` never reaching the pipeline | **Reject (bug)** | `rate_is_per_uom`, read by join |
| Same flag passed inverted by Material Request | **Reject (bug)** | no negated boolean anywhere |
| `Price List.countries` never read | **Reject** | scope via `tax_jurisdiction`/party scope tables |
| `Item Price` duplicate check catching only identical validity | **Reject** | `EXCLUDE` on qty band **and** date range |
| Transactions writing back `Item Price` | **Reject** | prices are input; observed prices go to a separate table |
| `priority` as a string `Select` | **Reject** | `smallint` |
| SQL ordering priority lexicographically | **Reject (bug)** | numeric column, one ordering |
| `pricing_rules[0]` governing the whole batch | **Reject (bug)** | per-rule evaluation, no batch-wide inference |
| `has_priority` flag duplicating "priority is set" | **Reject** | derived |
| `validate_max_discount` skipped for group/brand rules | **Reject** | ceiling checked against the resolved item, always |
| No overlap detection between Pricing Rules | **Reject** | `EXCLUDE USING gist` |
| `MultiplePricingRuleConflict` thrown at transaction time | **Reject** | prevented at write time |
| Webshop silently taking `pricing_rules[0]` where the desk throws | **Reject** | one function, one answer, recorded |
| Rule `condition` as `safe_eval`'d user code | **Reject** | typed `rule_predicate` rows |
| Condition regex bypassed by leading whitespace | **Reject (bug)** | no expressions to screen |
| Failed condition silently dropping the rule | **Reject** | typed evaluation, no exceptions possible |
| Conditions skipped entirely when no `doc` is passed | **Reject (bug)** | one resolver signature |
| `sorted_by_priority` discarding flagless rules | **Reject (bug)** | explicit stack set |
| `priority` ascending for stacked rules, descending for exclusive | **Reject** | separate `stack_sequence` column |
| `Promotional Scheme` generating N×M Pricing Rule documents | **Reject** | `scheme_id` + applicability joined at match time |
| Field propagation via four hand-maintained name lists | **Reject** | no propagation; one table |
| `min_amount`→`min_amt` rename at the boundary | **Reject** | one name |
| All generated rules sharing `title = scheme name` | **Reject** | no generated rules |
| `rules[...] = names` sharing one list object | **Reject (bug)** | — |
| `applicable_for` change hard-deleting Pricing Rules | **Reject** | end-dating; `ON DELETE RESTRICT` |
| Deletion guard covering only `docstatus < 2` | **Reject (bug)** | FK covers all history |
| `on_trash` deleting every generated rule | **Reject** | restricted by FK |
| `on_update` re-running `validate` | **Reject** | validation runs once |
| Coupon PK = `coupon_name`, code non-unique | **Reject** | `code citext UNIQUE` is the key |
| Promotional code = name minus digits, first 8 chars | **Reject** | explicit code, or a generated unique token |
| `valid_from`/`valid_upto` unvalidated | **Reject** | `daterange` with a `CHECK` |
| `used` as an unlocked read-modify-write counter | **Reject** | insert-only `coupon_redemption`; `used` is a view |
| Order **and** invoice each incrementing `used` | **Reject (bug)** | redemption attaches to the fulfilment chain |
| `Shipping Rule.disabled` never read | **Reject** | validity dates |
| `sort_shipping_rule_conditions` assigning to the wrong attribute | **Reject (bug)** | no ordering needed |
| Open-ended slab matching any value regardless of `from_value` | **Reject (bug)** | `numrange` containment |
| Slab overlap `<=` at the junction vs inclusive read | **Reject (bug)** | `EXCLUDE` on `numrange` |
| Identical slab rows skipped by the overlap check | **Reject (bug)** | `EXCLUDE` catches them |
| Open-ended slab compared as a point range | **Reject (bug)** | unbounded range |
| Freight rounded to a hard-coded 2 decimals | **Reject** | currency's own scale |
| Freight capitalisation inferred from "any stock item present" | **Reject** | explicit `capitalise` from the regime |
| Duplicate shipping charge rows silently overwritten (`[-1]`) | **Reject** | one row per charge, by constraint |
| `get_last_doc(doctype, docname)` misusing the `filters` argument | **Reject (bug, dead code)** | — |
| `Party Specific Item` enforced only in link-field search | **Reject** | trigger-enforced `party_item_eligibility` |
| Full-table read of eligibility rows per keystroke | **Reject** | indexed predicate |
| Party group hierarchy not walked for eligibility | **Reject** | recursive CTE, as everywhere else |
| `Item Alternative` warning (not blocking) on serial/batch mismatch | **Reject** | `CHECK` on both items' `tracking_mode` |
| Reverse duplicate permitted for `two_way` alternatives | **Reject (bug)** | canonical ordering `CHECK` |
| `is_stock_item` mismatch throwing | **Keep** | as a `CHECK` |
| Template-and-variant in one rule rejected | **Keep** | as a constraint |
| Direction cross-check (`applicable_for` vs selling/buying) | **Keep** | as a `CHECK` |

---

Cross-references: doc 05 §5.8–§5.9 (rule application, the rate/discount/margin loop, `insert_item_price`),
doc 17 §4 (`Item Price` and its overlap gap), doc 28 (tax determination — the same matching problems,
the same fixes), doc 19 (why a rule enforced in a query helper is not enforced),
doc 21 §3 (`safe_eval` on user-authored expressions), doc 03 §3.4 and
**[S04](../scenarios/S04-stock-transfer-and-in-transit.md)** §5 (landed cost, which §8.3 decides by
accident), doc 11 §5 (insert-only compensating rows, the model §7.1 reuses),
**[S01](../scenarios/S01-order-to-cash.md)** (pricing inside a real flow),
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
