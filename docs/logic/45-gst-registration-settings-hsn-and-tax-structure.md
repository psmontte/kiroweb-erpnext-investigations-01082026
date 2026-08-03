# 45 — GST Registration, Settings, HSN/SAC and Tax Structure

> **Tranche F opens here.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`,
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`, and — new in this tranche —
> `india_compliance` `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, 2026-07-31,
> `__version__ = "17.0.0-dev"`, requiring `frappe >=17.0.0-dev`).
>
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/`; **India Compliance citations are prefixed `india_compliance/`** and are relative to
> `/projects/sandbox/india_compliance/india_compliance`.

Localisation is a confirmed requirement and **India GST is the priority** (doc 44 §11). This document
establishes the ground truth for it, and the first finding reframes the whole tranche.

---

## 1. GST is not in ERPNext

Every previous tranche read ERPNext. This one mostly cannot, because **India-specific features were removed
from ERPNext core in v14** and moved to a separately maintained app. The removal patch is still in the
pinned tree and is itself the evidence:

```python
"India-specific regional features have been moved to a separate app."
" Please install India Compliance to continue using these features:"
" https://github.com/resilient-tech/india-compliance"
```

(`patches/v14_0/remove_india_localisation.py:5-21`). The same patch deletes the DocTypes, print formats and
reports that used to implement it (`patches/v14_0/remove_india_localisation.py:23-64`):

| Deleted | Names |
|---|---|
| DocType | `C-Form`, `C-Form Invoice Detail`, `GST Account`, `E Invoice Request Log`, `E Invoice Settings`, `E Invoice User`, `GST HSN Code`, `HSN Tax Rate`, `GST Settings`, `GSTR 3B Report` |
| Print Format | `GST E-Invoice`, `GST Purchase Invoice`, `GST Tax Invoice`, `GST POS Invoice` |
| Report | `E-Invoice Summary`, `Eway Bill`, GST Itemised/Purchase/Sales Registers, `GSTR-1`, `GSTR-2`, HSN-wise summary |

It also rewrites the `Item.gst_hsn_code` custom field back to a plain `Data` field
(`patches/v14_0/remove_india_localisation.py:66-71`), which tells you what the extension mechanism is (§7).

Searching the whole pinned ERPNext tree for GST identifiers returns **four** files, three of which are
patches and one of which is demo data. The only India-adjacent controller left in core is
`Lower Deduction Certificate` (`regional/doctype/lower_deduction_certificate/lower_deduction_certificate.py`),
which serves the TDS design already covered in [doc 28 §7](28-tax-determination.md).

**Consequence for us.** A GST design cannot be derived from ERPNext. It must be derived from the app that
actually implements it, which is why this tranche pins a third repository. Anything asserted about GST
*statute* is a requirement, not a citation; everything asserted about *behaviour* below cites
`india_compliance`.

### 1.1 What we are actually reading

| | |
|---|---|
| App | `resilient-tech/india-compliance`, pinned `205c3de` |
| Python | ~49,000 lines across ~313 files, excluding `test_*` and `tests/` |
| DocTypes | **26** |
| Version alignment | `17.0.0-dev`, `frappe >=17.0.0-dev` — matches our pinned frappe/erpnext exactly |

The 26 DocTypes, grouped by what they are for:

| Group | DocTypes |
|---|---|
| Configuration | `GST Settings`, `GST Account`, `GST Credential`, `Company Print Options`, `GST UOM Map`, `State Wise E Waybill Threshold`, `E Invoice Applicable Company` |
| Identity | `GSTIN`, `PAN` |
| Classification | `GST HSN Code` |
| Tax structure | `India Compliance Taxes and Charges` |
| Outward compliance | `GSTR 1`, `GST Return Log`, `GSTR Action`, `GSTR Import Log`, `GSTR 3B Report` |
| Inward reconciliation | `GST Inward Supply`, `GST Inward Supply Item`, `Purchase Reconciliation Tool`, `GST Invoice Management System` |
| External documents | `E Invoice Log`, `E Waybill Log` |
| Imports | `Bill of Entry`, `Bill of Entry Item` |
| Legacy | `C-Form`, `C-Form Invoice Detail` |

This document covers configuration, identity, classification and tax structure. Doc 46 covers
transaction-time determination, doc 47 the external document APIs, doc 48 returns and reconciliation.

> **Invariant G1 — jurisdiction is data, not code.** A tax jurisdiction is a first-class entity with
> approved, effective-dated rule revisions. Registration identity, classification, rate schedules,
> component structure, document-numbering rules and return formats are all rows, not Python modules
> selected at call time. Adding a second jurisdiction adds data and rule revisions; it never edits, wraps or
> replaces a core calculation function.

---

## 2. How the app attaches itself, and why it matters to us

India Compliance does **not** use ERPNext's `@erpnext.allow_regional` overlay. That mechanism exists — 20
call sites in the pinned tree, wrapping things like `get_itemised_tax_breakup_data`,
`update_gl_dict_with_regional_fields`, `validate_einvoice_fields`, `add_regional_gl_entries` and, notably,
`get_wdv_or_dd_depr_amount` (doc 42 §4.3) — but the app reaches ERPNext through three broader routes
instead:

1. **`doc_events` hooks** in `india_compliance/hooks.py` (681 lines), binding validate/submit/cancel handlers
   for `Sales Invoice`, `Purchase Invoice`, `Delivery Note`, `Purchase Receipt`, `Payment Entry`,
   `Journal Entry`, `GL Entry`, `Item`, `Customer`, `Supplier`, `Company`, `Address`, `Tax Category`,
   `Item Tax Template`, `Subcontracting Order/Receipt` and `Stock Entry` — one override module per doctype
   under `india_compliance/gst_india/overrides/`.
2. **Custom fields**, created and toggled at runtime from a 1,859-line declaration
   (`india_compliance/gst_india/constants/custom_fields.py`), applied through
   `toggle_custom_fields` (`india_compliance/utils/custom_fields.py:7-37`).
3. **Company fixtures**, creating accounts and tax templates when a Company is created
   (`india_compliance/gst_india/overrides/company.py:25-100`).

The second route is the one with consequences. `GST Settings.update_custom_fields` adds or removes whole
field groups when a checkbox changes (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:210-218`):

```text
enable_e_waybill                changed → toggle E_WAYBILL_FIELDS
enable_e_invoice                changed → toggle E_INVOICE_FIELDS
enable_reverse_charge_in_sales  changed → toggle SALES_REVERSE_CHARGE_FIELDS
```

`toggle_custom_fields` writes exactly one thing — `hidden` — on Custom Fields that already exist, then clears
the doctype cache (`india_compliance/utils/custom_fields.py:7-37`). It does **not** create or delete them:
creation is `make_custom_fields` at install (`india_compliance/utils/custom_fields.py:80-91`), and
`delete_custom_fields` (`india_compliance/utils/custom_fields.py:54-79`) is reached only from uninstall and
two patches.

So the precise claim is narrower than "a checkbox changes the document's shape": a checkbox changes the
**visibility** of fields that always exist as runtime `Custom Field` rows. That is still the mechanism doc 18
§4 rejects — statutory fields are install-time metadata mutated by settings rather than versioned schema, and
a settings save invalidates the doctype cache — but the fields do not blink in and out of existence, and the
argument must not claim they do.

> **Invariant G2 — statutory fields are schema, not settings.** Jurisdiction-specific columns exist in the
> versioned schema, are populated only when the jurisdiction applies, and never appear or disappear because a
> configuration flag changed. Enabling or disabling a compliance feature changes which rules run and which
> facts are required; it never changes what the tables can hold.

---

## 3. Registration identity: GSTIN and PAN

### 3.1 GSTIN format is category-specific

A GSTIN is 15 characters. The app holds **seven distinct regexes** and maps GST categories onto them
(`india_compliance/gst_india/constants/__init__.py:1446-1473`):

```text
NORMAL        ^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[Z1-9ABD-J]{1}[0-9A-Z]{1}$
GOVT_DEPTID   ^[0-9]{2}[A-Z]{4}[0-9]{5}[A-Z]{1}[0-9]{1}[Z]{1}[0-9]{1}$
REGISTERED  = NORMAL | GOVT_DEPTID
NRI_ID        ^[0-9]{4}[A-Z]{3}[0-9]{5}[N][R][0-9A-Z]{1}$
OIDAR         ^[9][9][0-9]{2}[A-Z]{3}[0-9]{5}[O][S][0-9A-Z]{1}$
OVERSEAS    = NRI_ID | OIDAR
UNBODY        ^[0-9]{4}[A-Z]{3}[0-9]{5}[UO]{1}[N][A-Z0-9]{1}$
TDS           ^[0-9]{2}[A-Z]{4}[A-Z0-9]{1}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[D][0-9A-Z]$
TCS           ^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[C]{1}[0-9A-Z]{1}$
```

| GST Category | Accepted format |
|---|---|
| Registered Regular, Registered Composition, SEZ, Deemed Export, Input Service Distributor | `REGISTERED` |
| Overseas | `OVERSEAS` |
| UIN Holders | `UNBODY` |
| Tax Deductor | `TDS` |
| Tax Collector | `TCS` |

The first two characters are the **state number** — a 38-entry map from state name to code
(`india_compliance/gst_india/constants/__init__.py:98-140`), which is what makes place of supply derivable
(doc 46).

### 3.2 Validation, and where it is deliberately skipped

`validate_gstin` enforces length 15, runs the check digit, and optionally requires TCS form
(`india_compliance/gst_india/utils/__init__.py:246-282`). The check digit is a mod-36 alternating-weight
algorithm over `0-9A-Z` (`india_compliance/gst_india/utils/__init__.py:414-437`):

```text
for each of the first 14 characters, alternating factor 1, 2, 1, 2, …
    digit = factor × index_of(char)
    total += (digit // 36) + (digit % 36)
expected = (36 − (total % 36)) % 36
reject unless gstin[14] == code_point_chars[expected]
```

Worth noting: the check digit is **skipped entirely for transporter IDs**, with a real-world counterexample
in the comment — `29AAFCA7488L1Z0` is a valid transporter ID that fails the check digit
(`india_compliance/gst_india/utils/__init__.py:246-282`). So one identifier space has two validity
definitions depending on the role it is used in.

`validate_gst_category` couples category and number in both directions
(`india_compliance/gst_india/utils/__init__.py:284-320`): no GSTIN forces category into
`Unregistered`/`Overseas`; a GSTIN forbids `Unregistered`; and the number must match its category's regex.

`guess_gst_category` infers a category from the number, falling back to `Registered Regular` when nothing
matches — explicitly so that e-commerce TCS numbers land somewhere
(`india_compliance/gst_india/utils/__init__.py:372-408`). Inference is convenient and lossy: two categories
share the `REGISTERED` pattern, so the guess cannot distinguish `SEZ` from `Registered Regular`, and the
function preserves an already-set category to compensate.

Addresses get a second, geographic check: pincode must be 6 digits not starting with zero, **and its first
three digits must fall inside the state's allocated range**
(`india_compliance/gst_india/utils/__init__.py:325-368`). Where the state is absent from the mapping the
check silently passes.

### 3.3 GSTIN status is an externally-owned, cached fact

`GSTIN` is a DocType keyed by the number itself, holding `status`, `registration_date`, `cancelled_date`,
`is_blocked`, `gstr_1_filed_upto` and `last_updated_on`, normalised on save
(`india_compliance/gst_india/doctype/gstin/gstin.py:25-49`). It is populated from the GST portal API and
then **used as authority for validating a transaction**.

`validate_gstin_status` refuses a document whose date precedes the counterparty's registration date, or
falls on/after its cancellation date, or whose status is neither Active nor Cancelled
(`india_compliance/gst_india/doctype/gstin/gstin.py:166-206`). That is genuinely good: it turns a statutory
condition into a write-time gate rather than a return-filing surprise.

Two mechanisms around it are less safe.

**Refresh is time-based and silently disabled.** `is_status_refresh_required` returns `False` outright when
`validate_gstin_status` is off, the API is disabled, or sandbox mode is on; skips submitted documents; and
otherwise refreshes only when `days_since_last_update >= gstin_status_refresh_interval`
(`india_compliance/gst_india/doctype/gstin/gstin.py:208-232`). So the cached row may be arbitrarily stale
within the configured window, and the validation above is only as good as that row.

**Validation can run after the fact.** `get_and_validate_gstin_status` either validates against the cached
row, or — when a refresh is due — **enqueues** the fetch with `validate_gstin_status` as a callback
(`india_compliance/gst_india/doctype/gstin/gstin.py:101-137`). In the enqueued path `throw` is not set, so
`_throw` logs an error instead of raising (`india_compliance/gst_india/doctype/gstin/gstin.py:166-176`).
A document can therefore be saved against an invalid GSTIN, with the objection landing in the error log
afterwards. The job is keyed `create_or_update_gstin_status_{gstin}_{date}_{hour}`, which is a de-duplication
key with hour granularity, not an idempotency record.

> **Invariant G3 — counterparty registration is evidence, captured at the moment it is relied upon.** A
> registration number, its category, its status and the effective dates of that status are recorded as an
> immutable snapshot fact on the posted document, with its source and retrieval instant. Validation against
> registration status is a **synchronous refusal before the write**, never an asynchronous log entry, and a
> stale snapshot beyond its policy window blocks rather than passes.

### 3.4 PAN

`PAN` is a DocType with format `^[A-Z]{5}[0-9]{4}[A-Z]{1}$`
(`india_compliance/gst_india/constants/__init__.py:1475`) and an externally-fetched status
(`india_compliance/gst_india/doctype/pan/pan.py:39-112`). `validate_pan` derives PAN from characters 3–12 of the GSTIN
(`india_compliance/gst_india/overrides/party.py:61-78`) — and does so **unconditionally whenever a GSTIN
exists**, overwriting any stored PAN, with **no category guard**:

```python
if doc.gstin:
    doc.pan = pan_from_gstin if is_valid_pan(pan_from_gstin := doc.gstin[2:12]) else ""
    return
```

The derivation is correct for the `REGISTERED` formats and wrong for TDS, TCS, UIN and NRI numbers, whose
middle segment is not a PAN — and in those cases the stored PAN is **blanked**, not left alone. `is_valid_pan`
is the only test applied.

The module also ships a Verhoeff checksum and an Aadhaar generator
(`india_compliance/gst_india/doctype/pan/pan.py:148-166`) used for API sandbox flows.

---

## 4. GST Settings: one Single that gates everything

`GSTSettings.validate` runs eleven checks in order, all but the last three skipped during install
(`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:52-66`): dependent fields, API enablement,
GST accounts, e-invoice applicability date, credentials, refresh interval, nil-exempt warning, then session
clearing, scheduled-job toggling, e-invoice status recompute and unique-state validation.

Behaviours worth recording:

- **Scheduled jobs are switched by settings.** Changing `enable_retry_einv_ewb_generation` writes `stopped`
  on the `Scheduled Job Type` row for the retry job
  (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:132-142`); the same pattern applies to
  auto-reconciliation (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:143-155`). A
  configuration document mutating framework scheduler rows is the coupling doc 22 §2 warned about.
- **Account uniqueness is validated per settings row, not globally.** `validate_gst_accounts` builds a
  local `account_list` and rejects a repeated account, and separately rejects a repeated `account_type` per
  company (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:176-209`). Both are
  check-then-write inside one document's validation; nothing in the schema prevents the same account being
  used for two purposes.
- **A statutory floor is hard-coded.** `e_invoice_applicable_from` may not precede
  `E_INVOICE_START_DATE = "2021-01-01"`
  (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:220-243`,
  `india_compliance/gst_india/doctype/gst_settings/gst_settings.py:37`).
- **An anti-pattern is warned about, not prevented.** Setting `nil_exempt_e_invoice_treatment` to
  "Generate with Taxable Values" produces a message saying it causes GSTR-1 inconsistencies and is *not
  recommended* (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:68-85`) — a known-wrong
  configuration left available.
- **A rollout date is deliberately unreachable.** `SHIP_TO_GSTIN_APPLICABLE_DATE = 2099-12-31`, with the
  comment "deliberately unreachable. Sandbox stays reachable via `sandbox_mode`"
  (`india_compliance/gst_india/constants/__init__.py:10-12`), consumed by
  `is_ship_to_gstin_applicable` (`india_compliance/gst_india/utils/__init__.py:450-458`). A statutory
  switch is pinned to a sentinel date pending a real one — honest, and exactly the kind of thing that must
  be a dated rule revision rather than a constant.

---

## 5. Tax structure: five components, per company

GST is not one tax. The account structure is five named components
(`india_compliance/gst_india/constants/__init__.py:15-30`):

```text
GST_ACCOUNT_FIELDS = (cgst_account, sgst_account, igst_account,
                      cess_account, cess_non_advol_account)
GST_TAX_TYPES      = (cgst, sgst, igst, cess, cess_non_advol)
GST_RCM_TAX_TYPES     = each + "_rcm"
GST_REFUND_TAX_TYPES  = each + "_refund"
TAX_TYPES = GST_TAX_TYPES + GST_RCM_TAX_TYPES + GST_REFUND_TAX_TYPES     -- 15 in total
```

So a single conceptual rate resolves to **fifteen possible account roles**, selected by whether the supply
is intra-state, inter-state, reverse charge, or a refund. `GST Account` rows in `GST Settings` map
`(company, account_type)` to those five accounts, where `account_type` distinguishes Output, Input, Sales
Reverse Charge, Purchase Reverse Charge and Output Refund
(`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:176-209`,
`india_compliance/gst_india/overrides/item_tax_template.py:78-108`).

### 5.1 The rate-splitting rule, and its validation

`Item Tax Template` carries a single `gst_rate` plus a `gst_treatment`, and the override enforces the
relationship between that headline rate and the per-account rows
(`india_compliance/gst_india/overrides/item_tax_template.py:27-67`):

```text
for each tax row:
    intra-state account → require gst_rate == tax_rate × 2      (CGST and SGST each carry half)
    inter-state account → require gst_rate == tax_rate          (IGST carries all of it)
```

Worked: an 18% item resolves to `CGST 9% + SGST 9%` within a state and `IGST 18%` across states. A 5% item
resolves to `2.5% + 2.5%` or `5%`. The doubling rule is the whole of GST's intra/inter-state duality
expressed as one equality — and it is checked, with the expected value reported per row
(`india_compliance/gst_india/overrides/item_tax_template.py:56-67`) — subject to the per-row limitation
below.

**Upstream never checks that the components sum to the headline rate.** `validate_tax_rates` inspects each
row independently, against `abs(row.tax_rate)`
(`india_compliance/gst_india/overrides/item_tax_template.py:27-67`), so a template carrying a single CGST row
at 9% passes an 18% headline, a −9% row passes because of `abs()`, and a row whose account is in neither the
intra- nor the inter-state set is skipped in silence. The doubling relationship is asserted per row, never
summed — which is precisely the gap `tax_rate_component`'s exact-sum trigger closes in §8, and it makes that
constraint an addition rather than a reformulation.

`validate_zero_tax_options` couples treatment and rate: any treatment other than `Taxable` forces the rate
to zero, and `Taxable` with a zero rate is refused
(`india_compliance/gst_india/overrides/item_tax_template.py:15-25`). `TAXABLE_GST_TREATMENTS` is
`("Taxable", "Zero-Rated")` (`india_compliance/gst_india/constants/__init__.py:94-95`), so
Nil-Rated/Exempted/Non-GST are the non-taxable remainder — a distinction that matters in GSTR-1 (doc 48),
not in arithmetic.

Reverse-charge and refund accounts legitimately carry **negative** rates.
`get_accounts_with_negative_rate` computes which ones, including purchase RCM accounts only when an existing
`Purchase Taxes and Charges` row has `add_deduct_tax = "Add"`
(`india_compliance/gst_india/overrides/item_tax_template.py:78-108`) — so it depends on another document's
child row. It is also **client-side only**: it is reachable solely through the whitelisted
`get_valid_gst_accounts` (`india_compliance/gst_india/overrides/item_tax_template.py:69-77`), called from the
form script. Server-side validation ignores sign entirely, via the `abs()` above.

### 5.2 Company fixtures

Creating a Company triggers fixture creation: customs accounts, GST expense accounts, and default tax
templates at a chosen rate (`india_compliance/gst_india/overrides/company.py:25-100`), then those accounts
are written into `GST Settings` (`india_compliance/gst_india/overrides/company.py:101-211`). Deleting a
Company deletes its `GST Settings` rows (`india_compliance/gst_india/overrides/company.py:11-24`).

This is real, useful onboarding logic, and it is also mutable master data generated by code — so two
companies created at different app versions get different chart-of-accounts shapes with nothing recording
which fixture version produced them.

> **Invariant G4 — tax components are typed, and their arithmetic is a constraint.** A jurisdiction's rate
> is defined once, per classification and effective period, together with the component split rule that
> derives per-component rates. `Σ component rate = headline rate` exactly, for every applicable supply type,
> enforced by constraint rather than by a validation message. Component-to-account mapping is company-scoped,
> typed by role, and unique per role; the same account cannot serve two roles.

---

## 6. Classification: HSN and SAC

`GST HSN Code` validates that a code is 4, 6 or 8 digits
(`india_compliance/gst_india/doctype/gst_hsn_code/gst_hsn_code.py:115-133`,
`india_compliance/gst_india/constants/__init__.py:1524`), and services are identified by the prefix
`99` (`india_compliance/gst_india/constants/__init__.py:1525`).

Editing an HSN code's taxes **pushes them into every Item carrying that code**
(`india_compliance/gst_india/doctype/gst_hsn_code/gst_hsn_code.py:21-45`), by bulk-inserting item tax rows,
bumping each item's `modified` timestamp and adding a comment to each
(`india_compliance/gst_india/doctype/gst_hsn_code/gst_hsn_code.py:46-114`). On the Item side,
`set_taxes_from_hsn_code` pulls the same data in the other direction
(`india_compliance/gst_india/overrides/item.py:33-49`).

That is a two-way master-data sync implemented with bulk SQL and timestamp patching. It is fast and it is
also unversioned: nothing records which rate schedule an item's taxes came from, or when the classification
itself changed. Since GST rates change by notification on dated effect, **an unversioned classification is
the single most consequential gap in this layer**.

`GST UOM Map` translates internal UOMs to the codes the e-invoice and e-way-bill APIs accept — a small table
that becomes load-bearing in doc 47.

> **Invariant G5 — classification and rate are effective-dated revisions.** An item's classification
> (HSN/SAC or equivalent) is an approved revision with an effective range, and a rate schedule is a separate
> approved revision keyed by classification, supply type and effective range. A posted document snapshots
> both revision identities. Changing a classification or a rate never rewrites item master rows, never
> touches a posted document, and never happens without a dated revision that can be reproduced.

---

## 7. Evidence versus projection

| Representation | Classification |
|---|---|
| `GST Settings` (Single) | mutable configuration that also toggles schema and scheduler rows |
| `GST Account` rows | company-scoped account mapping, validated per document |
| `GST Credential` | API credentials with session state |
| custom fields created/hidden by settings | **runtime metadata**, not versioned schema |
| company fixture accounts and tax templates | generated mutable master data, unversioned |
| `GSTIN` row | externally-owned fact, cached, staleness-windowed |
| `GSTIN.status`, `registration_date`, `cancelled_date` | authority for write-time validation, refreshed asynchronously |
| `PAN` row and status | externally-owned fact, cached |
| party `gstin` / `gst_category` fields | mutable master data, category partly inferred |
| `GST HSN Code` and its taxes | unversioned classification, bulk-pushed into items |
| `Item` tax rows | derived from HSN, no record of source revision |
| `Item Tax Template.gst_rate` + rows | headline rate plus component rows, equality-validated |
| posted document GST fields | snapshot on the transaction (doc 46) |

Nothing in the left column is append-only, and two entries — the GSTIN status row and the HSN tax push —
are authority for decisions while being freely overwritten.

> **Invariant G6 — evidence before compliance projection.** Determination inputs (jurisdiction, registration
> snapshots, classification revision, rate revision, place of supply, component split) are recorded as
> immutable facts on the posted document, in the same transaction as its `voucher`/`gl_entry` rows and an
> outbox event. Registers, returns and reconciliation views are projections rebuilt from those facts.

---

## 8. Target design for this layer

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) with jurisdiction as data. Money `numeric(19,4)`;
rates and percentages `numeric(9,6)`; every table `company_id`-scoped with RLS and `FORCE RLS`; stable
lower-case enum codes; append-only facts with reversal/supersession.

| Target table | Key columns and constraints |
|---|---|
| `tax_jurisdiction` | stable code (`in`, `ae`, `gb`…), name; unique `(code)` |
| `tax_jurisdiction_revision` | jurisdiction, revision_no, effective range, `state` , feature flags (e-invoice, e-waybill, reverse charge, composition); approved ranges non-overlapping by exclusion constraint |
| `tax_registration` | party or company, jurisdiction, `registration_no`, `registration_category`, valid range, `pan`/secondary id; unique `(company_id, jurisdiction_id, registration_no)` |
| `tax_registration_snapshot` | **immutable** capture used by a posted document: registration_no, category, status, registered_on, cancelled_on, source, retrieved_at; unique `(company_id, source_doc_type, source_doc_id, party_role)` |
| `tax_registration_status_fetch` | append-only external-fetch log with request/response hash, outcome, `command_receipt_id` |
| `tax_area` | jurisdiction sub-division (Indian state) with its statutory code; unique `(jurisdiction_id, area_code)`; postal-range rows for validation |
| `classification_scheme` / `classification_code_revision` | HSN/SAC as approved effective-dated revisions with allowed lengths and service prefix as scheme metadata, not literals |
| `item_classification` | item → classification revision, effective range; unique `(company_id, item_id, scheme_id, effective_from)` |
| `tax_component` | jurisdiction component (`cgst`, `sgst`, `igst`, `cess`, `cess_non_advol`), `component_role` (`output`, `input`, `reverse_charge`, `refund`), sign policy; unique `(jurisdiction_id, component_code, component_role)` |
| `tax_component_account` | company + component + role → `account_id`; unique `(company_id, tax_component_id, component_role)` **and** unique `(company_id, account_id)` so one account cannot serve two roles |
| `tax_rate_revision` | jurisdiction, classification revision, supply type (`intra`, `inter`, `import`, `export`), headline rate, effective range, `state`; approved ranges non-overlapping |
| `tax_rate_component` | rate revision → component, rate; deferred trigger `Σ component rate = headline rate` **exactly** per supply type |
| `tax_treatment` | typed treatment (`taxable`, `zero_rated`, `nil_rated`, `exempted`, `non_gst`) with its rate and reporting consequences; a zero headline rate is legal only for non-`taxable` treatments |

Two structural points carry most of the value:

1. **`tax_rate_component` with an exact-sum trigger** replaces the `gst_rate == tax_rate × 2` validation
   message with a constraint, and generalises it: a jurisdiction whose split is three-way or whose cess is
   quantity-based is expressible without new code.
2. **`tax_registration_snapshot`** makes the GSTIN-status problem disappear. The posted document owns an
   immutable copy of what was true when it was written, so a later portal refresh cannot retroactively
   invalidate history, and an asynchronous fetch cannot let an invalid registration through — the write
   blocks until a snapshot within policy exists.

Write ordering for determination is specified in doc 46; this layer contributes only master and revision
data, all of it published through the ordinary approve-a-revision command with an exclusion constraint on
approved effective ranges.

> **Invariant G7 — relational jurisdiction integrity.** Unique, foreign-key, check and exclusion constraints
> enforce one approved rule revision per jurisdiction and period, non-overlapping classification and rate
> revisions, one account per component role, one registration per number per jurisdiction, and exactly one
> snapshot per posted document and party role.

---

## 9. Defects, races and unfinished paths

1. **GST is absent from ERPNext core.** A localisation requirement cannot be met by the pinned ERP alone
   (`patches/v14_0/remove_india_localisation.py:1-71`).
2. **Statutory fields appear and disappear with a checkbox.**
   (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:210-218`,
   `india_compliance/utils/custom_fields.py:7-37`, `india_compliance/utils/custom_fields.py:54-79`).
3. **GSTIN status validation can be asynchronous and non-blocking.** The enqueued path logs instead of
   throwing (`india_compliance/gst_india/doctype/gstin/gstin.py:101-137`,
   `india_compliance/gst_india/doctype/gstin/gstin.py:166-176`).
4. **Cached registration status may be arbitrarily stale** within the refresh interval, and refresh is
   skipped entirely in sandbox mode or with the API disabled
   (`india_compliance/gst_india/doctype/gstin/gstin.py:208-232`).
5. **The de-duplication key is hour-granular, not an idempotency record.**
   (`india_compliance/gst_india/doctype/gstin/gstin.py:101-137`).
6. **Two validity definitions for one identifier.** Transporter IDs skip the check digit
   (`india_compliance/gst_india/utils/__init__.py:246-282`).
7. **Category inference is lossy.** `REGISTERED` covers five categories, so `guess_gst_category` cannot
   distinguish them and falls back to `Registered Regular`
   (`india_compliance/gst_india/utils/__init__.py:372-408`).
8. **Pincode/state validation silently passes** for states absent from the mapping
   (`india_compliance/gst_india/utils/__init__.py:325-368`).
9. **Component sums are never validated.** Each row is checked independently against `abs(tax_rate)`, so a
   single-component template passes a two-component headline
   (`india_compliance/gst_india/overrides/item_tax_template.py:27-67`).
10. **HSN taxes are bulk-pushed into item masters** with direct inserts, timestamp patching and comments,
   with no rate-revision provenance
   (`india_compliance/gst_india/doctype/gst_hsn_code/gst_hsn_code.py:21-114`).
11. **Classification and rates are unversioned** while GST rates change by dated notification — posted
    documents cannot name the schedule they used (§6).
12. **Account uniqueness is a per-document check-then-write.**
    (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:176-209`).
13. **A settings document mutates scheduler rows.**
    (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:132-155`).
14. **A known-inconsistent option is warned about rather than removed.**
    (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:68-85`).
15. **A statutory rollout is pinned to a sentinel date** (`2099-12-31`) rather than modelled as a dated rule
    (`india_compliance/gst_india/constants/__init__.py:10-12`).
16. **The negative-rate account set is client-side only**, and depends on another document's child rows
    (`india_compliance/gst_india/overrides/item_tax_template.py:78-108`,
    `india_compliance/gst_india/overrides/item_tax_template.py:69-77`).
17. **Company fixtures are unversioned generated master data.**
    (`india_compliance/gst_india/overrides/company.py:25-100`).

No deterministic lock or unique constraint was found around: GSTIN status read → transaction validation;
settings account list read → save; or HSN tax read → bulk item update.

> **Invariant G8 — serializable compliance decisions.** Registration snapshot capture, classification and
> rate revision publication, component-account mapping and settings changes are bounded writes validated and
> inserted under deterministic owner locks with idempotency keys and database uniqueness. An external fetch
> is a recorded attempt with a request hash, never a fire-and-forget job whose objection arrives later.

---

## 10. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| GST as a separate app | **Adopt the boundary, reject the mechanism** | jurisdiction rule revisions inside one schema |
| `@allow_regional` function replacement | **Reject** | no runtime override of calculation code |
| `doc_events` override modules per doctype | **Change** | one determination service driven by jurisdiction rules |
| Custom fields toggled by settings | **Reject** | versioned schema; flags change rules, not columns |
| Category-specific registration formats | **Adopt** | `registration_category` with per-category format on the jurisdiction revision |
| GSTIN check digit | **Adopt** | same algorithm as a jurisdiction validation rule |
| Skipping the check digit for transporter IDs | **Change** | separate identifier type with its own explicit rule |
| Category ↔ number cross-validation | **Adopt** | constraint, both directions |
| `guess_gst_category` inference | **Change** | inference may propose, never persist without confirmation |
| Pincode ↔ state range validation | **Adopt** | `tax_area` postal ranges |
| Silent pass for unmapped states | **Reject** | unmapped area is a refusal |
| `GSTIN` DocType caching portal status | **Adopt/Change** | cache plus an **immutable per-document snapshot** |
| Async, log-only status validation | **Reject** | synchronous refusal before write |
| Time-window staleness | **Change** | explicit policy window that **blocks** when exceeded |
| PAN derived from GSTIN characters | **Adopt as derivation** | proposed, category-guarded, stored as its own fact |
| Five GST components, 15 account roles | **Adopt** | `tax_component` + `tax_component_account` typed by role |
| `gst_rate == tax_rate × 2` intra-state rule | **Adopt as constraint** | `Σ component rate = headline rate` per supply type |
| Treatment forcing zero rate | **Adopt** | typed `tax_treatment` with rate legality per treatment |
| Negative rates for RCM/refund | **Adopt** | component role carries its sign policy |
| Negative-rate set derived from another document | **Reject** | sign policy is on the component definition |
| HSN 4/6/8 length and `99` service prefix | **Adopt as scheme metadata** | `classification_scheme`, not literals |
| Bulk push of HSN taxes into items | **Reject** | items reference a classification revision; rates resolve at determination |
| Unversioned classification and rates | **Reject** | effective-dated approved revisions, snapshotted per document |
| `GST UOM Map` | **Adopt** | jurisdiction code map, versioned |
| Company fixtures for accounts/templates | **Change** | fixture **revision** recorded on the company |
| Settings mutating `Scheduled Job Type` | **Reject** | job cadence is configuration read by the scheduler |
| Hard-coded statutory dates and sentinels | **Reject** | dated rule revisions |
| Warning about a known-inconsistent option | **Reject** | if it produces wrong returns, it is not offered |

Invariants introduced here are **G1–G8**: jurisdiction as data; statutory fields as schema; registration as
captured evidence; typed components with constrained arithmetic; effective-dated classification and rates;
evidence before compliance projection; relational integrity; and serializable compliance decisions. Doc 46
continues at **G9** with transaction-time determination.

---

Cross-references: [doc 28](28-tax-determination.md) (the core tax engine GST must map onto — `Tax Category`,
`Tax Rule`, `Item Tax Template`, withholding and LDC), [doc 29](29-pricing-determination.md),
[doc 18](18-metadata-and-runtime-ddl.md) (custom fields, Property Setters, runtime DDL — the mechanism we
reject), [doc 21](21-extensibility-hooks-and-regional.md) (`doc_events`, `@allow_regional`),
[doc 22](22-background-jobs-scheduling-and-locking.md) (scheduler coupling and job identity),
[doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (accounts and dimensions),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) and
[doc 44](44-tranche-c-closure-and-our-asset-spec.md) (command/lock/idempotency/outbox contract reused here),
and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 46 — place of supply, component
determination, reverse charge and ineligible input credit.
