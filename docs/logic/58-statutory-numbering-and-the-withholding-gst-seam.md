# 58 — Statutory Document Numbering, and the Withholding ↔ GST Seam

> **Closes the two items [doc 49 §7.2](49-tranche-f-closure-and-our-localisation-spec.md#72-what-remains-open-in-localisation)
> left deliberately open.** Both were named in the original scope, both were deferred with a reason, and both
> interact with designs already fixed — numbering with [doc 20](20-naming-identity-and-audit-trail.md), and
> withholding with [doc 28 §5](28-tax-determination.md) and [doc 05 §5.10](05-taxes-totals-and-pricing.md).
>
> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55`.
> ERPNext citations are relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are prefixed
> `frappe/`; India Compliance citations are prefixed `india_compliance/`.

This is a specification, not an implementation report. **Application implementation has not started.**
Invariants continue the localisation register from doc 49 at **G30**.

---

## 1. What was left open, and why it could not stay open

Doc 49 closed Tranche F with two named exceptions. Re-reading them now, both are worse than the deferral
implied, and neither is a detail.

| Deferred item | Why it was deferred | What reading it actually found |
|---|---|---|
| **Statutory document-numbering rules** | "specified the container, not the content"; interacts with doc 20's naming design | The statutory invoice number **is the row's primary key**, so it inherits every naming-series and amendment behaviour — including one that silently rewrites it. A non-compliant number is a hard error on exactly one document class and a dismissible warning on the rest, and the return that reports issued documents **reconstructs series by string-comparing adjacent primary keys** |
| **TDS/TCS ↔ GST seam** | "specified by doc 28 §7, not duplicated here" | Whether GST enters the withholding base is a **two-option dropdown with a default**, not a consequence of the statutory section. And "TDS/TCS" names *two unrelated tax systems* that share an acronym; only one of them exists in either codebase |

Neither can be closed by an implementer making a reasonable choice, which is the test doc 49 §7.2 should have
applied: in both cases the reasonable-looking choice is wrong, and wrong in a direction that produces a
statutory filing defect rather than a bug report.

---

## Part A — Statutory document numbering

## 2. The rule, and where it lives

India's Rule 46(b) requires a tax invoice to carry a consecutive serial number, unique for a financial year,
not exceeding sixteen characters, made of alphanumerics, hyphens and slashes. India Compliance encodes exactly
that:

```python
# Maximum length must be 16 characters. First character must be alphanumeric.
# Subsequent characters can be alphanumeric, hyphens or slashes.
GST_INVOICE_NUMBER_FORMAT = re.compile(r"^[^\W_][A-Za-z0-9\-\/]{0,15}$")
```

(`india_compliance/gst_india/constants/__init__.py:1478-1480`). The regex is correct and is the only place in
the tranche where a statutory *format* is expressed as a format rather than as prose.

What it is applied to is the problem.

### 2.1 The statutory number is the primary key

Frappe names a document by setting `doc.name`, which becomes the row's identity
(`frappe/model/naming.py:180-200`). `validate_invoice_number` therefore validates `doc.name`
(`india_compliance/gst_india/utils/__init__.py:1030-1034`):

```python
is_valid_length = len(doc.name) <= 16
is_valid_format = GST_INVOICE_NUMBER_FORMAT.match(doc.name)
```

So the statutory serial number, the row's identity, the URL, every foreign key and every audit reference are
**one string**. Three consequences follow immediately, and none of them is a design choice anyone made:

- the number cannot be corrected without renaming the row, which rewrites every reference to it;
- the number cannot be allocated before the row exists, so allocation and insertion cannot be separated; and
- anything that changes the identity changes the statutory number. §2.3 is that.

This is doc 20's finding — identity conflated with a human-facing sequence — arriving where the consequence is
a return filing rather than a broken link.

### 2.2 One throw, three warnings

The validation is called from four places, and its severity depends on the *document class* rather than on
whether the number is lawful (`india_compliance/gst_india/utils/__init__.py:1046-1056`):

```python
if doc.doctype == "Sales Invoice":
    frappe.throw(message, title=title)

frappe.msgprint(message, title=title)
```

| Call site | Effect of a non-compliant number |
|---|---|
| `india_compliance/gst_india/overrides/sales_invoice.py:71` | **refusal** |
| `india_compliance/gst_india/overrides/purchase_invoice.py:70` | a dismissible message; the document posts |
| `india_compliance/gst_india/overrides/subcontracting_transaction.py:290` | a dismissible message; the document posts |
| `india_compliance/gst_india/utils/transaction_data.py:260` | refusal, but only at e-invoice/e-way bill generation — long after posting |

A self-invoice for a reverse-charge inward supply from an unregistered person is a Purchase Invoice, and it is
a document *we* issue and *we* must number lawfully. It gets the warning. A delivery challan for job work is a
Subcontracting Receipt or Stock Entry, also ours, also warned.

### 2.3 Amendment rewrites the statutory number

`_set_amended_name` runs before any other naming path when `amended_from` is set
(`frappe/model/naming.py:576-586`):

```python
am_id = 1
am_prefix = doc.amended_from
if frappe.db.get_value(doc.doctype, doc.amended_from, "amended_from"):
    am_id = cint(doc.amended_from.split("-")[-1]) + 1
    am_prefix = "-".join(doc.amended_from.split("-")[:-1])
doc.name = am_prefix + "-" + str(am_id)
```

Cancel and amend `INV/2026/00042` and the replacement is `INV/2026/00042-1`. The statutory serial number of the
amended invoice is now a different string from the one on the document the customer holds, and it was produced
by string concatenation rather than by allocation from a series. Amend twice and it is `-2`, by splitting on the
**last hyphen** — so a number that legitimately contains hyphens, which Rule 46(b) explicitly permits, is
parsed as though its final hyphen were a version delimiter.

Two further effects:

- **The 16-character limit is silently consumed.** `INV/2026/00042` is 14 characters; `-1` makes 16; a second
  amendment makes 17 and the number becomes unlawful — caught for a Sales Invoice, warned for the rest.
- **It is only reached when `amend_naming_rule != "Default Naming"`** (`frappe/model/naming.py:574-577`), so
  whether amendment mutates the statutory number at all depends on a naming-rule setting.

### 2.4 The issued-documents return reconstructs series from strings

GSTR-1 Table 13 requires, per series of documents issued in the period, the from and to serial numbers and
counts of issued and cancelled. Upstream builds it by walking the document list and asking whether each
adjacent **pair of names** belongs to the same series
(`india_compliance/gst_india/utils/gstr_1/gstr_1_data.py:847-882`), then slicing at every boundary:

```python
for i in range(1, len(data)):
    if self.is_same_naming_series(data[i - 1].name, data[i].name):
        continue
    slice_indices.append(i)
```

`is_same_naming_series` strips letters and digits into two buckets, removes a common numeric suffix, and
returns (`gstr_1_data.py:883-934`):

```python
return cint(n_1) - cint(n_0) == 1
```

Two documents are in the same series **only if their numbers are consecutive**. The docstring documents two
false positives itself — a difference that is a multiple of ten, and identical serials in different months —
and the consecutiveness test adds the complementary false negative: **any gap splits one series into two
reported series**. A deleted draft, a number consumed by a rolled-back transaction, or documents that sort in
an order other than their issue order all produce a spurious series boundary.

The statutory report wants a declared series and a contiguous range. It is given a heuristic over primary keys,
whose failure modes are known, documented and unfixable in that shape — because the information it needs (which
series a document was issued from) was never recorded.

### 2.5 The signature finding: an unlawful number is silently dropped from the return

`validate_invoice_number` has a non-throwing mode, and GSTR-1 uses it to classify documents
(`india_compliance/gst_india/utils/gstr_1/gstr_1_data.py:948-950`):

```python
for doc in data:
    if not validate_invoice_number(doc, throw=False):
        nature_of_document["Excluded from Report (Invalid Invoice Number)"].append(doc)
```

Compose that with §2.2 and §2.3 and the failure is complete:

1. A Purchase Invoice for a reverse-charge self-invoice gets a 20-character name. Validation **warns**; the
   user dismisses it; the invoice posts and its GL entries are real.
2. Or a Sales Invoice is amended twice, reaching 17 characters. Amendment naming produced this, not the user.
3. At filing, the document is routed to `Excluded from Report (Invalid Invoice Number)`.

The tax was determined, posted and paid, and the document is **omitted from the return** on the strength of a
warning somebody clicked through weeks earlier. The exclusion bucket is at least named and visible, which is
better than a silent drop — but the document is already posted, so by the time the return is built the only
remedies are cancelling a posted invoice or filing an incomplete return.

The polarity is the recurring Tranche F defect (doc 49 §4.4) in its purest form: a validation that should be a
refusal at issue is a warning at save and an exclusion at filing.

---

## Part B — The withholding ↔ GST seam

## 3. Two unrelated systems, one acronym

Before the seam can be specified, the ambiguity has to be removed, because "TDS/TCS" names two different taxes
under two different statutes with different bases, rates, returns and counterparties:

| | Income-tax TDS/TCS | GST TDS/TCS |
|---|---|---|
| Statute | Income Tax Act, Chapter XVII-B / XVII-BB | CGST Act s.51 (TDS) and s.52 (TCS) |
| Who | any specified payer; e-commerce collectors under 206C | government deductors; e-commerce operators |
| Identity | PAN | a **separate GSTIN** with its own registration category |
| Base | payment or credit, section-dependent | value of taxable supply, excluding tax |
| Return | 24Q/26Q/27EQ | GSTR-7 / GSTR-8 |
| In the pinned trees | `Tax Withholding Category` + `Tax Withholding Entry`, plus `india_compliance/income_tax_india/` | **absent** |

India Compliance knows GST TDS/TCS registrations exist — they have their own GSTIN formats
(`india_compliance/gst_india/constants/__init__.py:1468-1471`):

```python
TDS = re.compile(r"^[0-9]{2}[A-Z]{4}[A-Z0-9]{1}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[D][0-9A-Z]$")
TCS = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[C]{1}[0-9A-Z]{1}$")
```

— note the positional `D` and `C` where a normal GSTIN carries `Z` — and `GSTIN_FORMATS` maps the registration
categories `"Tax Deductor"` and `"Tax Collector"` onto them
(`india_compliance/gst_india/constants/__init__.py:1461-1473`). But nothing *computes* GST TDS or TCS. The only
other appearance is reading what a counterparty deducted from us, via GSTR-2A's deductor fields
`gstin_deductor`, `deductor_name` and `amt_ded`
(`india_compliance/gst_india/utils/gstr_2/gstr_2a.py:285-292`).

Meanwhile `india_compliance/income_tax_india/` handles the income-tax side, and its entire contribution to the
seam is a PAN lookup (`india_compliance/income_tax_india/overrides/tax_withholding_category.py:15-20`):

```python
def get_tax_id_for_party(party_type, party):
    # PAN field is only available for Customer and Supplier.
    if party_type in ("Customer", "Supplier"):
        return frappe.db.get_value(party_type, party, "pan")
    return ""
```

That is the correct identity for income-tax withholding — and it is *not* the GSTIN, which is the point.
Withholding aggregates on PAN; GST aggregates on GSTIN; a PAN maps to many GSTINs. Doc 49 §7.2's phrasing
("the seam between withholding and GST components") assumed one seam. There are two systems and three
identities.

## 4. Where the base is decided, and by what

The withholding controller computes the taxable amount per item
(`accounts/doctype/tax_withholding_entry/tax_withholding_entry.py:531-551`):

```python
if category.tax_deduction_basis != "Gross Total":
    taxable_amount = item.base_net_amount
else:
    taxable_amount = item.base_net_amount + item._item_total_tax_amount
```

So GST is in the withholding base if and only if the category says `Gross Total`. That single string is the
entire seam.

### 4.1 The basis is a dropdown with a default

`tax_deduction_basis` is a two-option `Select`, required, defaulting to `Net Total`
(`accounts/doctype/tax_withholding_category/tax_withholding_category.json:79-84`), quoted in file order:

```json
"default": "Net Total",
"fieldname": "tax_deduction_basis",
"fieldtype": "Select",
"label": "Deduct Tax On Basis",
"options": "\nGross Total\nNet Total",
"reqd": 1
```

Under Indian law this is not a preference. CBDT Circular 23/2017 directs that TDS on services applies to the
amount **excluding** GST where GST is shown separately; TCS on sale of goods under s.206C(1H) is charged on the
**gross** consideration *including* GST. Both regimes coexist in one company, on one supplier, in one period.

> **These two sentences are legal assertions, not upstream-observable facts, and they are the only such
> claims in this document.** Everything else here is evidenced by a cited line in a pinned tree; these are
> not, and nothing upstream states them. The design conclusion does not depend on them — a base rule that
> cannot be dated and attributed is wrong whatever the correct bases turn out to be.
>
> **Resolved by design, 4 Aug 2026 — no ruling needed.** We ship **zero** `withholding_section_revision`
> rows. `authority` is `NOT NULL`, and withholding computation **refuses** when no approved section
> revision covers the posting date, rather than falling back to a default. So the system cannot deduct the
> wrong tax on this document's say-so: it deducts nothing and stops. The first row is written by whoever
> is accountable for it — a tax professional, at the point the company actually runs Indian withholding —
> and the `authority` column records who. This is the same fail-closed shape as G11's unmapped-account
> refusal, and it converts an open legal question into an ordinary empty table.
>
> Recorded in `semantic-review/2026-08-03-doc-58-review.md`.
The basis is therefore a property of the **statutory section**, and here it is a property of a
user-maintained category with a default that is right for one regime and wrong for the other — with nothing
recording which section the category represents, and nothing preventing one category from being reused across
sections that disagree.

Doc 28 §5.1 noted `tax_deduction_basis` as one of several "switches" on the master. This is what the switch
decides.

### 4.2 Every non-withholding tax enters the "gross" base

`_item_total_tax_amount` is built by summing the item's tax rows
(`accounts/doctype/tax_withholding_entry/tax_withholding_entry.py:552-566`):

```python
for row in self.doc.get("_item_wise_tax_details", []):
    ...
    if row.tax.is_tax_withholding_account:
        continue
    item._item_total_tax_amount = flt(item._item_total_tax_amount + row.amount, precision)
```

The only exclusion is withholding accounts themselves. So "Gross Total" means *net amount plus every other
charge row* — CGST, SGST, IGST and cess, but equally a freight charge, a customs duty, a municipal levy, or a
line somebody added by hand. There is no component typing, because there are no typed components: this is doc
45 §5's finding (a tax account's meaning is inferred from a mapping that may be absent, giving
`gst_tax_type = None`) reappearing where the consequence is the base of a *different* tax.

Two amounts that must be distinguished are therefore indistinguishable. A withholding base of
"consideration including GST" and one of "consideration including GST and freight" are the same number in this
model, and only one of them is lawful.

### 4.3 Ordering is correct, and is the one thing that does not need changing

India Compliance determines GST in `before_validate`
(`india_compliance/gst_india/overrides/transaction.py:1574-1614`, wired at
`india_compliance/hooks.py:188-199` — the Purchase Invoice block, where `before_validate`, `validate`,
`before_save` and `before_submit` are all declared together), and the withholding controller runs in `validate`
(`accounts/doctype/purchase_invoice/purchase_invoice.py:306`):

```python
PurchaseTaxWithholding(self).on_validate()
```

So the GST rows exist before the withholding base reads them. Worth stating explicitly because it is the
obvious thing to suspect and it is not the defect — and because our design must preserve the ordering rather
than discover it (§6, G41).

One real ordering hazard remains downstream: `update_valuation_rate` runs at `before_save` and `before_submit`,
after `validate` (`india_compliance/hooks.py:198-199`), and ineligible-ITC handling patches valuation rates in place
(`india_compliance/gst_india/overrides/ineligible_itc.py:291-312`, rejected in doc 49 §4.5). Blocked GST that
becomes cost after the withholding base was computed cannot change it, which happens to be correct — but it is
correct by accident of hook order, not by rule.

### 4.4 Thresholds are stateful, and the authority for the rule is a forum post

Threshold evaluation reads previously submitted withholding entries
(`accounts/doctype/tax_withholding_entry/tax_withholding_entry.py:600-620`):

```python
# NOTE: Once deducted, always deducted. Not checking cumulative threshold again purposefully.
# conservative approach to avoid tax disputes as it can have conflicting views
# https://www.taxtmi.com/forum/issue?id=118627
if result.get("Settled", 0) > 0:
    return True
```

The rule is defensible and we adopt it: once withholding has begun for a party and category, it continues
regardless of later recomputation. What is not acceptable is that the **authority is a link to a discussion
forum in a code comment**, that the rule is unversioned, and that it is not effective-dated — so a change in
position cannot be applied from a date, and a past period cannot be reproduced under the rule that was in force
when it was filed. This is doc 45 §1's "jurisdiction is data" applied to a rule that decides whether tax is
withheld at all.

Two adjacent behaviours compound it: a `cumulative_threshold` of `0` means *always withhold* rather than *no
cumulative threshold* (`tax_withholding_entry.py:591-592`), so an unset field and a deliberate zero are the
same value; and `ignore_tax_withholding_threshold` on the document forces the threshold crossed
(`tax_withholding_entry.py:583-584`) with no reason recorded — the first branch of
`_is_threshold_crossed_for_category`, before any threshold is read.

---

## 5. Target design

### 5.1 Numbering: allocation is a fact, identity is not the number

The row's identity and the statutory number separate completely. `id` remains a surrogate key; `doc_no` remains
the internal document number from doc 20; and the statutory number becomes a **third** attribute, allocated
from a declared series and immutable once allocated.

Two supporting tables have to exist first, and neither did. `FINAL-SCHEMA` §24 has no document-number format
rule and no statutory year — the first draft of this section referenced both as though they were already
there. They are defined in `FINAL-SCHEMA` §39 and summarised here:

```sql
statutory_format_revision(id, company_id, tax_jurisdiction_id, document_class statutory_doc_class_enum NULL,
    revision_no integer NOT NULL, pattern text NOT NULL, max_length smallint NOT NULL,
    effective_from date NOT NULL, effective_to date NULL,
    authority text NOT NULL, state revision_state_enum NOT NULL)
   -- Rule 46(b) becomes a SEED ROW, not a CHECK. `document_class NULL` means "every class in this
   -- jurisdiction", which is what India needs; a jurisdiction that formats credit notes differently
   -- adds a narrower row rather than an ALTER TABLE. This is the difference between jurisdiction as
   -- data (G1/G2) and @allow_regional, which §24 rejects.

statutory_year(id, company_id, tax_jurisdiction_id, code varchar(9),   -- e.g. '2026-27'
    starts_on date NOT NULL, ends_on date NOT NULL, state revision_state_enum NOT NULL)
   -- The STATUTORY year, which is not the company's fiscal calendar: India's GST year runs
   -- 1 April - 31 March whatever year-end the company chose, and G31 keys the series on it.
```

```sql
statutory_series(id, company_id, tax_registration_id NOT NULL,
    document_class statutory_doc_class_enum
      /*tax_invoice|credit_note|debit_note|delivery_challan|self_invoice|
        payment_voucher|receipt_voucher|refund_voucher|bill_of_supply*/,
    statutory_year_id NOT NULL,              -- FK to statutory_year
    prefix varchar(8) NOT NULL, suffix varchar(8) NOT NULL DEFAULT '',
    width smallint NOT NULL, next_value bigint NOT NULL,
    statutory_format_revision_id NOT NULL,   -- the jurisdiction's format rule
    state series_state_enum /*active|closed*/ NOT NULL)
   UNIQUE (company_id, tax_registration_id, document_class, statutory_year_id, prefix)
   CHECK (width BETWEEN 1 AND 12)
   -- Per REGISTRATION and per STATUTORY YEAR, because Rule 46(b)'s "unique for a financial year" is
   -- per registration (T25) — a company with two GSTINs runs two independent series, and doc 55 §5
   -- is why that is expressible at all.
   -- L2 trigger: length(prefix) + width + length(suffix) <= the format revision's max_length. A series
   -- that can only ever produce an unlawful number is refused AT DECLARATION, not months later at the
   -- moment someone tries to issue an invoice from it. Same reasoning as G34, one level up.

statutory_number_allocation(id, company_id, statutory_series_id,
    serial_value bigint NOT NULL, statutory_number varchar(32) NOT NULL,
    allocated_at timestamptz NOT NULL, allocated_to_doc_type text, allocated_to_doc_id bigint,
    state allocation_state_enum /*allocated|issued|cancelled|void*/ NOT NULL,
    void_reason text NULL, supersedes_allocation_id bigint NULL)
   UNIQUE (company_id, statutory_series_id, serial_value)
   UNIQUE (company_id, statutory_series_id, statutory_number)
   CHECK ((state = 'void') = (void_reason IS NOT NULL))
   -- IMMUTABLE in statutory_number and serial_value.
   -- Uniqueness is keyed on the SERIES, which already pins registration, class and year — a
   -- company-wide unique would forbid two GSTINs of one company each issuing 'INV/001', which is
   -- lawful and is the exact case G31 exists for.
   -- The FORMAT is not a CHECK here. A literal regex on this table would be Rule 46(b) compiled into
   -- the schema, so UAE would need an ALTER TABLE — @allow_regional in another costume. Instead an
   -- L2 trigger matches statutory_number against the pattern and max_length on the series' format
   -- revision. varchar(32) is a storage bound, not the statutory one.
   -- `void` exists because a gap must be EXPLICABLE, not impossible.
```

Five properties, each negating a specific §2 finding:

- **Allocation precedes insertion and is a separate fact, committed separately.** The number is drawn and
  committed, then the document is written against it. The separate commit is the whole mechanism, not an
  implementation detail: if the draw shared the document's transaction, a rollback would erase the
  allocation along with the document and there would be no `void` row to explain the gap — the state this
  design claims over upstream's heuristic would never occur. So a rolled-back document leaves an allocation
  moved to `void` with a `void_reason`, and Table 13 can report it.
- **The number is never the identity**, so correcting one does not rewrite references, and renaming a row
  cannot change a statutory number.
- **Amendment allocates a new number and cites the old one.** There is no `-1` suffix and no string splitting
  on the last hyphen; the amended document's statutory number is a first-class allocation whose predecessor is
  recorded — which is also what a credit-note-against-invoice reference needs.
- **Format compliance is a refusal at allocation, applied identically to every `document_class`.** The
  self-invoice and the delivery challan get the same refusal as the tax invoice. The rule itself is a
  `statutory_format_revision` row rather than a literal in the schema, so India's Rule 46(b) and a future
  jurisdiction's rule are two rows, not two code paths.
- **Table 13 is a projection**, not a reconstruction: `GROUP BY statutory_series_id` over allocations gives the
  series, `min`/`max(serial_value)` give the range, and the counts come from `state`. `is_same_naming_series`
  and its documented false positives have no analogue, because the series is recorded rather than inferred.

### 5.2 Withholding: the base is derived from the section

```sql
withholding_regime(id, company_id, tax_jurisdiction_id NOT NULL, code varchar(24), name text,
    statute withholding_statute_enum /*income_tax|gst|other*/,
    identity_kind party_identity_kind_enum /*pan|gstin|tin|other*/ NOT NULL,
    return_form varchar(16))
   UNIQUE (company_id, tax_jurisdiction_id, code)
   -- The table that removes the acronym collision. `income_tax` aggregates on PAN, `gst` on GSTIN, and
   -- a design cannot silently use one identity for the other. GST TDS/TCS (s.51/s.52) is a regime with
   -- no implementation upstream; here it is a row, and §7 records that we have not walked it.
   -- COMPANY-SCOPED like every other localisation revision table. §24's global exception list is
   -- exactly three tables (tax_jurisdiction, tax_area, tax_area_postal_range) and is closed; an
   -- unscoped table would also fail §31's generated rls_conformance gate, which is step 6 of the
   -- build order.
   -- tax_jurisdiction_id is NOT NULL because a regime is inherently jurisdictional: `statute` names
   -- Indian statutes and `return_form` holds '24Q' and 'GSTR-7'. Without it UAE has nowhere to hang
   -- its regimes, and the design stops being jurisdiction-agnostic (G1/G2).

withholding_section_revision(id, company_id, withholding_regime_id, section_code varchar(16),
    base_rule withholding_base_enum /*net_of_tax|gross_including_tax|gross_including_named_components*/,
    on_payment_or_credit trigger_basis_enum /*earlier_of|payment_only|credit_only*/,
    once_deducted_continues bool NOT NULL,
    cumulative_threshold numeric(19,4) NULL,          -- NULL = no cumulative threshold; 0 = always
    revision_no integer NOT NULL, effective_from date NOT NULL, effective_to date NULL,
    authority text NOT NULL, state revision_state_enum NOT NULL)
   UNIQUE (company_id, withholding_regime_id, section_code, revision_no)
   EXCLUDE USING gist (company_id WITH =, withholding_regime_id WITH =, section_code WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
   -- requires the btree_gist extension, as every EXCLUDE in §24 does
   -- `base_rule` lives on the SECTION, effective-dated, with `authority` NOT NULL — so CBDT Circular
   -- 23/2017 and s.206C(1H) are two rows with two bases, not one dropdown with a default. A category
   -- cannot be reused across sections that disagree, because the base is not on the category.

withholding_section_component(id, company_id, withholding_section_revision_id, tax_component_id)
   UNIQUE (company_id, withholding_section_revision_id, tax_component_id)
   -- `gross_including_named_components` is the third option upstream lacks: it names the §24 tax
   -- components that enter the base, so "including GST" and "including GST and freight" are
   -- different, checkable values.
   -- A JUNCTION TABLE, not a bigint[] on the revision. An array of foreign keys carries no
   -- referential integrity, so superseding a tax_component would leave a silent stale id inside a
   -- statutory tax base — in a schema that has 2,051 FKs and 0 dangling targets precisely because
   -- that is refused. It also makes G38's sum constraint an ordinary join instead of `= ANY(array)`.
   -- L2 trigger: rows exist here if and only if the revision's base_rule is
   -- 'gross_including_named_components'.
```

The base becomes a derivation rather than a lookup, and it records what it read:

```sql
withholding_base(id, company_id, source_doc_type text, source_doc_id bigint, source_line_id bigint,
    withholding_section_revision_id NOT NULL,
    net_amount numeric(19,4) NOT NULL,
    included_component_amount numeric(19,4) NOT NULL,
    base_amount numeric(19,4) NOT NULL,
    party_identity_kind party_identity_kind_enum NOT NULL, party_identity_value varchar(32) NOT NULL)
   UNIQUE (company_id, source_doc_type, source_doc_id, source_line_id,
           withholding_section_revision_id)
   -- deferred: base_amount = net_amount + included_component_amount, exactly.
   -- deferred: included_component_amount = Σ tax_determination_component.amount joined through
   --   withholding_section_component — exactly the components the section revision names, and no
   --   others. An untyped or unmapped charge cannot enter a withholding base by default. Doc 45 §5's
   --   unmapped-account refusal (G11) is what makes this expressible.
   -- The identity is captured, not joined: withholding aggregates on PAN and GST on GSTIN, and a
   -- posted base records which identity it used (§3).
```

Threshold state and relief keep doc 28 §7.5's shape with two additions, both now columns on
`withholding_section_revision` above. `once_deducted_continues` is a **dated field on the section revision**
rather than a comment citing a forum, so the position is attributable and a past period reproduces under the
rule then in force. `cumulative_threshold` is **nullable**, so *unset* and *deliberately zero* are different
values — upstream conflates them, and a `0` there silently means "always withhold"
(`tax_withholding_entry.py:591-592`). Forcing a threshold requires a reason, on the same footing as every
other override in the design.

---

## 6. G30–G41

Continuing doc 49's register.

> **Invariant G30 — the statutory number is an attribute, never an identity.** A document's surrogate key,
> its internal document number and its statutory number are three separate columns. Nothing that changes a
> row's identity can change its statutory number, and correcting a statutory number never rewrites a
> reference.

> **Invariant G31 — a statutory series is declared, per registration and per statutory year.** A series
> names its registration, document class, statutory year, format revision and shape. It is not inferred from
> a prefix, and it is never reconstructed by comparing document names. A company with several registrations
> runs several independent series, because the statutory uniqueness requirement is per registration.

> **Invariant G32 — allocation is a fact that precedes the document, and a gap is explicable.** A statutory
> number is drawn from its series before the document is written, and every drawn number is `allocated`,
> `issued`, `cancelled` or `void` with a reason. The issued-documents return is a projection over
> allocations, so its ranges and counts are derived rather than heuristic.

> **Invariant G33 — an amendment allocates, it never mutates.** An amended document receives a new
> allocation citing its predecessor. No statutory number is produced by concatenating a version suffix, and
> no statutory number is parsed to discover one.

> **Invariant G34 — statutory format is an approved dated rule, enforced as a refusal at allocation, for
> every document class.** Length and character rules live in an approved `statutory_format_revision` with a
> named authority, and no number that violates the rule its series points at can be stored. There is no
> document class for which a format failure is a dismissible message, and no code path where a format
> failure is deferred to filing time and answered by exclusion. The rule is **data**: a second jurisdiction
> is a second row, never a second `CHECK` and never a code path selected at runtime.

> **Invariant G35 — withholding regimes are distinct systems with distinct identities.** Income-tax
> withholding and GST withholding are separate regimes, each naming the party identity it aggregates on. No
> computation uses one regime's identity for the other, and a regime that is modelled but not implemented is
> recorded as such rather than implied by an acronym.

> **Invariant G36 — the withholding base is derived from the statutory section, never chosen.** Whether tax
> forms part of the base is a property of an approved, effective-dated section revision with a named
> authority. It is not a setting on a category, it has no default, and a category cannot be shared across
> sections whose bases differ.

> **Invariant G37 — a gross base names the components it includes.** When a section's base includes tax, it
> enumerates which typed components enter it. Summing every charge that is not a withholding account is not
> a base; an untyped or unmapped charge is a refusal, not an inclusion.

> **Invariant G38 — every withholding base is a stored, reconcilable fact.** The net amount, the included
> component amount, the resulting base, the section revision applied and the party identity used are stored
> per source line. The base equals net plus included components exactly, and the included amount equals the
> sum of the named components exactly, both by deferred constraint.

> **Invariant G39 — threshold continuation is a dated rule, not a comment.** "Once withheld, always
> withheld" is a field on the section revision with an effective date and an authority. An unset threshold
> and a zero threshold are different values. Forcing a threshold crossing records a reason.

> **Invariant G40 — relief instruments are effective-dated certificates with consumption tracked.**
> A reduced or nil rate applies only through a certificate with a validity range, a ceiling and recorded
> consumption, keyed on the regime's party identity. Exhausting or expiring a certificate returns the
> section's own rate rather than continuing at the relieved one.

> **Invariant G41 — determination order is declared, and each step records what it read.** Tax determination
> produces components before any withholding base reads them, and the withholding base records the
> determination it consumed. A later adjustment to tax — blocked credit becoming cost, a valuation
> restatement — never silently changes a base that was already computed; it produces an explicit
> recomputation or a refusal.

---

## 7. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| `GST_INVOICE_NUMBER_FORMAT` regex | **Adopt wholesale** | the same expression, as the `pattern` on a seeded `statutory_format_revision` row — not a `CHECK`, which would compile one jurisdiction into the schema (G34) |
| A series whose prefix, width and suffix cannot fit the statutory length | **Reject** | refused at series declaration against the format revision's `max_length` |
| Statutory number as the row's primary key | **Reject** | three separate columns (G30) |
| Severity by document class — throw for Sales Invoice, message for the rest | **Reject** | one refusal for every class (G34) |
| `validate_invoice_number(doc, throw=False)` as a filing-time classifier | **Reject** | unrepresentable; the constraint fires at allocation |
| `Excluded from Report (Invalid Invoice Number)` bucket | **Adopt the visibility, reject the need** | exclusion buckets remain for genuine statutory exclusions; an invalid number is not one |
| Amendment suffix `-1` via `_set_amended_name` | **Reject** | a new allocation citing its predecessor (G33) |
| Amendment naming governed by a naming-rule setting | **Reject** | one rule; statutory numbers are never derived from another number |
| `is_same_naming_series` string heuristic | **Reject** | `statutory_series_id` on the allocation (G31) |
| Table 13 from/to serial and counts | **Adopt the output shape** | a projection over allocations (G32) |
| Series per financial year | **Adopt and sharpen** | per registration **and** statutory year |
| Separate GSTIN formats for Tax Deductor / Tax Collector | **Adopt as evidence** | `withholding_regime` with `identity_kind` (G35) |
| PAN as the withholding identity | **Adopt** | `identity_kind = 'pan'` on the income-tax regime |
| `tax_deduction_basis` as a category dropdown with a default | **Reject** | `base_rule` on a dated section revision (G36) |
| "Gross" = net + every non-withholding tax row | **Reject** | named components only (G37) |
| GST determined before the withholding base is read | **Adopt and require** | declared ordering (G41) |
| Valuation patched after the base is computed | **Reject** | explicit recomputation or refusal (G41) |
| "Once deducted, always deducted" | **Adopt the position, reject the authority** | a dated field with a named authority (G39) |
| A forum URL as the authority for a tax-base rule | **Reject** | `authority` is `NOT NULL` on the revision |
| `cumulative_threshold = 0` meaning "always" | **Reject** | nullable; unset ≠ zero |
| `ignore_tax_withholding_threshold` with no reason | **Change** | override requires a recorded reason |
| Lower Deduction Certificates | **Adopt** | effective-dated with consumption tracked (G40) |
| GST TDS/TCS (s.51/s.52) computation | **Absent upstream** | modelled as a regime; **not walked** — see §8 |

---

## 8. What this closes, and what it does not

**Closed.** Both items doc 49 §7.2 left open are now specified. Statutory document numbering has a schema, a
build position and six invariants; the withholding ↔ GST seam has a schema, an ordering rule and six
invariants. Neither depends on an unanswered question, so neither blocks implementation any longer.

`FINAL-SCHEMA` gains eight tables in a new **§39**: `statutory_format_revision`, `statutory_year`,
`statutory_series`, `statutory_number_allocation`, `withholding_regime`, `withholding_section_revision`,
`withholding_section_component` and `withholding_base`. The allocation step joins the posting funnel
immediately before registration-snapshot capture — a number must be lawful before the document that carries
it can be validated against a counterparty.

> **Review record.** This document was reviewed on 3 Aug 2026 against the pinned trees; the findings and
> their disposition are in [`semantic-review/2026-08-03-doc-58-review.md`](../../semantic-review/2026-08-03-doc-58-review.md).
> Nineteen findings, two of them blocking: the first draft referenced a document-number format rule and a
> statutory year that existed in neither `FINAL-SCHEMA` nor anywhere else, which is why §5.1 now defines
> both. The analysis in §2–§4 survived the review unchanged; every defect was in §5's target design or in a
> citation's precision.

**Not closed, and now explicitly scoped rather than implied.**

- **GST TDS (s.51) and GST TCS (s.52) are not implemented upstream and are not specified here.** They are
  modelled as a `withholding_regime` row with a GSTIN identity and GSTR-7/GSTR-8 return forms, and that is
  all. A company that is a government deductor or an e-commerce operator needs a further exercise; one that
  is neither does not. This is a genuine scope boundary, not a deferral, and it is stated because doc 49
  §7.2's phrasing implied a single TDS/TCS system that was already handled.
- **Section catalogues are data, not transcribed.** `withholding_section_revision` is the container; the
  actual Indian section list — and the 2025 Income Tax Act renumbering that upstream carries a patch for
  (`india_compliance/patches/v14/migrate_and_update_tds_section_as_per_income_tax_act_2025.py`) — is a
  seeding exercise. The renumbering patch is itself evidence for G36: sections change, so the rule that
  depends on them must be effective-dated.
- **Numbering rules for jurisdictions other than India** remain unread, consistent with doc 49 §7.2 and doc
  57 §8.2. The design is jurisdiction-agnostic — `format_revision_id` points at a jurisdiction rule — but
  only Rule 46(b) has been read.

With this document the localisation register runs **G1–G41**, and the two items that were to be "closed before
implementation" are closed.

---

Cross-references: [doc 49](49-tranche-f-closure-and-our-localisation-spec.md) (Tranche F closure and the open
items this closes), [doc 20](20-naming-identity-and-audit-trail.md) (naming series, identity and the
rename problem this inherits), [doc 28](28-tax-determination.md) (§5 withholding masters, §7.5 our
withholding design this extends), [doc 05](05-taxes-totals-and-pricing.md) (§5.10 the withholding
calculation), [doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) (typed components and the
unmapped-account refusal G37 depends on),
[doc 48](48-gst-returns-reconciliation-and-imports.md) (GSTR-1 and the return working set Table 13 sits in),
[doc 55](55-multi-location-branch-and-segment.md) (§5 registration as a dimension of place, which is why a
series can be per registration), [doc 57](57-tranche-g-closure-and-our-security-spec.md) (§8.2, which carried
these two items forward),
[S12](../scenarios/S12-gst-invoice-e-invoice-and-gstr1.md) (the GST cycle these two seams sit inside), and
`docs/design/FINAL-SCHEMA.md` §24–§28.
