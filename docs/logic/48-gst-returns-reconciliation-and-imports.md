# 48 — GST Returns, Reconciliation and Imports

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, `17.0.0-dev`).
>
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/`; India Compliance citations are prefixed `india_compliance/` and are relative to
> `/projects/sandbox/india_compliance/india_compliance`.

Doc [45](45-gst-registration-settings-hsn-and-tax-structure.md) covered configuration,
[46](46-gst-place-of-supply-and-component-determination.md) determination, and
[47](47-e-invoice-and-e-waybill-external-state-machines.md) the two endpoints that mint legal artefacts. This
document covers the **periodic** obligations: what we declare outward (GSTR-1), what we claim inward
(GSTR-3B and its ITC), how our books are reconciled against what the government believes (GSTR-2A/2B), and
how imports enter through a Bill of Entry.

The defining property of this layer is that **the government holds a competing copy of our data**. Everywhere
else, our ledger is the truth. Here, two independent records exist and the difference between them is itself
a business fact with money attached — unclaimed input credit, or a mismatch that triggers a notice.

This is the largest body of code in the tranche: `gstr_1_json_map.py` (2,702 lines),
`gstr_1_export.py` (2,323), `purchase_reconciliation_tool` (1,437 + 1,413), `generate_gstr_1.py` (1,133),
`gstr_1_data.py` (1,106), `gstr_3b_report.py` (602), `bill_of_entry.py` (802).

Invariants continue from doc 47 at **G24**.

---

## 1. GSTR-1: the outward declaration

### 1.1 A fixed statutory taxonomy

GSTR-1 is not a report over our data — it is a **prescribed classification** of it, into categories and
subcategories defined by the return format (`india_compliance/gst_india/utils/gstr_1/__init__.py:6-28`,
`india_compliance/gst_india/utils/gstr_1/__init__.py:29-162`), with the government's own field names held
separately (`india_compliance/gst_india/utils/gstr_1/__init__.py:163-260`).

`GSTReturnLog` composes three behaviours plus persistence
(`india_compliance/gst_india/doctype/gst_return_log/gst_return_log.py:28-40`):

```python
class GSTReturnLog(GenerateGSTR1, FileGSTR1, Document)
```

and `GenerateGSTR1` itself composes summarising, reconciling and aggregating
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:544-570`). So one document is
simultaneously the working set, the reconciliation result, the summary and the filing state machine.

### 1.2 Filing state

`filing_status` moves through `Not Filed` → `Uploaded` → `Ready to File` → `Filed`, written by `db_set` at
seven separate points (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:805-1010`).
Once `Filed`, two things change: reconciliation stops updating books-side match status
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-290`), and — as doc 46 §7
established — documents in that period can no longer be posted or cancelled.

`is_latest_data` is the cache-validity flag: when set, previously computed JSON is returned instead of being
recomputed (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-282`,
`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:686-745`). A statutory working set is
therefore a **memoised blob** whose validity is a boolean, and the data it summarises can change underneath
it whenever that boolean is not cleared.

### 1.3 Reconciling books against the portal

`get_reconcile_gstr1_data` walks every subcategory and compares both directions
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:263-351`):

```text
for each GSTR1_SubCategory:
    books vs gov:  per key, compute a reconciled row
        no gov value      → upload_status = "Not Uploaded"
        differences       → upload_status = "Mismatch"
        identical         → upload_status = "Uploaded"
    gov but not in books: → upload_status = "Missing in Books", synthesise an empty books row
```

`get_reconciled_row` computes the difference field by field
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:363-440`):

```text
match_status = "Matched"
if no gov row   → "Missing in GSTR-1"
if no books row → "Missing in Books"

for each numeric field not in IGNORED_FIELDS:
    reconcile_row[key] = flt(books − gov, 2)
    differs if != 0
for customer_gstin and place_of_supply:
    differs if books != gov

if differs and status has no "Missing" → "Mismatch", record the field name
return nothing when status is still "Matched"
```

Three observations.

**The difference is the payload.** Rather than flagging a mismatch, the row *becomes* the arithmetic
difference per field, with `books` and `gov` retained alongside. That is the right shape for a
reconciliation record and worth adopting directly.

**Comparison is at a hard-coded two decimals.** `flt(books − gov, 2)` — the same literal precision doc 46 §4
found in the reverse-charge balance rule. For a return whose values are rupees, 2 is plausible; as a
*policy* it is undeclared and unconfigurable.

**`TAX_RATE` and `DOC_VALUE` are deliberately ignored** (`IGNORED_FIELDS`,
`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:252-262`). So two rows can reconcile as
`Matched` while disagreeing on the tax rate — defensible, since rate is derivable from the amounts, but it
means "Matched" is narrower than it reads.

`sanitize_books_data` deletes synthesised `Missing in Books` rows before recomputing
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:352-362`) — a necessary step precisely
because the previous pass wrote synthetic rows into the books-side structure. Reconciliation output is being
written back into one of its own inputs.

`AggregateInvoices` collapses invoice lists to totals for comparison
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:471-543`), so a list-valued
subcategory is compared in aggregate: ten invoices summing correctly match ten different invoices summing
identically.

> **Invariant G24 — a return period is an immutable working set plus append-only reconciliation facts.** A
> return working set is materialised once per (registration, return type, period) from posted determination
> facts, with a content hash and the source watermark it was built from. Reconciliation against authority data
> is an append-only comparison fact — per key, per field, with both sides and the signed difference retained —
> and never writes into the books-side data it compares. Its comparison precision is a declared policy, not a
> literal.

### 1.4 Summarising

`SummarizeGSTR1` builds an overall summary and per-subcategory rows
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:40-59`,
`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:60-123`,
`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:124-205`), with document-issue counts
and unique counting handled separately
(`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:233-251`).

---

## 2. GSTR-3B: the summary return and its ITC claim

`GSTR3BReport` is a submittable document that generates a JSON payload
(`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:40-119`). Its structure is two halves:

| Half | Method |
|---|---|
| outward supplies and inter-state accumulation | `_process_outward_itc` (`gstr_3b_report.py:154-161`), `update_outward_json` (`:162-187`), `_accumulate_inter_state_supply` (`:188-208`) |
| inward supplies and eligible ITC | `_process_inward_itc` (`gstr_3b_report.py:209-217`), `update_inward_json` (`:218-232`), `_update_eligible_itc_section` (`:233-247`), `_update_inward_nil_exempt_section` (`:248-260`) |

Two details matter for us.

**The payload is built from a template file.** `get_json(template)` loads a JSON skeleton
(`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:261-266`) which is then populated. The
statutory shape lives on disk as a fixture rather than as a versioned schema definition — so a format change
is a file swap with no record of which version a filed return used.

**Values are formatted to a fixed precision on the way out.** `format_values(data, precision=2)`
(`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:267-283`). A third appearance of `2` as
a literal, this time applied to the numbers actually declared to the authority.

`filing_status` is a property (`gstr_3b_report.py:42-56`) and `notify_generation_complete` runs after commit
(`gstr_3b_report.py:135-142`), which is the correct ordering for a notification.

> **Invariant G25 — a filed return is an immutable artefact with a declared format version.** The generated
> payload, its format/schema revision, the working-set hash it was built from, its output precision policy and
> the authority's acknowledgement are stored together as one immutable filing fact. Regeneration produces a new
> version; it never overwrites what was filed.

---

## 3. Purchase reconciliation: a declared match ladder

This is the strongest piece of design in the tranche, and it is worth describing precisely.

Inward supplies downloaded from the portal (GSTR-2A/2B) land in `GST Inward Supply`, and the
`Purchase Reconciliation Tool` matches them against our Purchase Invoices and Bills of Entry. The matching
logic is **declarative**: a tuple of rules, each mapping a set of fields to a comparison mode, evaluated in
order (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:79-190`).

The vocabulary (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:29-61`):

| Comparison `Rule` | Meaning |
|---|---|
| `EXACT_MATCH` | equal |
| `FUZZY_MATCH` | approximate string match (bill numbers) |
| `ROUNDING_DIFFERENCE` | equal within a rounding tolerance |
| `MISMATCH` | explicitly allowed to differ |

| Resulting `MatchStatus` | Meaning |
|---|---|
| `EXACT_MATCH` | everything agrees |
| `SUGGESTED_MATCH` | agrees modulo fuzzy bill number and/or rounding |
| `MISMATCH` | same supplier and bill, amounts differ |
| `RESIDUAL_MATCH` | everything agrees except the bill number |
| `MANUAL_MATCH` | a human linked them |

The `GSTIN_RULES` ladder descends in strictness
(`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:79-190`):

1. **Exact** — fiscal year, both GSTINs, bill number, place of supply, reverse charge, taxable value and all
   four tax components all exact.
2. **Suggested** — as above, bill number *fuzzy*.
3. **Suggested** — as above, bill number exact, all amounts within *rounding difference*.
4. **Suggested** — bill number fuzzy **and** amounts within rounding difference.
5. **Mismatch** — fiscal year, supplier GSTIN and bill number exact; everything else free to differ.
6. **Mismatch** — as above with a fuzzy bill number.
7. **Residual** — everything exact except the bill number, amounts within rounding.

`PAN_RULES` (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:191-260`) repeat the
ladder one level looser, matching on PAN when the GSTIN itself differs — which catches a supplier invoicing
from a different registration under the same legal entity.

**This is exactly the right architecture**: the matching policy is data, the tiers are named, and the
strictness ordering is explicit and auditable. It is the one place in the tranche where a complex business
rule is expressed declaratively rather than as nested conditionals, and our design should adopt the shape
directly.

What is missing around it:

- **Match outcomes are actions on mutable documents.** `link_documents`, `unlink_documents` and `apply_action`
  (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/purchase_reconciliation_tool.py:269-323`)
  mutate links rather than appending decisions, so the reconciliation history — who matched what, on what
  evidence, and what the rule said at the time — is not retained.
- **The tool is a Single-like working document.** `reconcile_and_generate_data`
  (`purchase_reconciliation_tool.py:106-121`) recomputes into the same document.
- **Downloads are period-scanned with a redownload filter.** `get_periods_to_download`
  (`purchase_reconciliation_tool.py:450-462`) and `filter_redownload_periods`
  (`purchase_reconciliation_tool.py:463-472`), with import history per period
  (`purchase_reconciliation_tool.py:473-505`) and a missing-document check
  (`purchase_reconciliation_tool.py:506-529`). Necessary, and again reconciliation tooling built to recover
  from a state machine that does not guarantee completeness.
- **A GSTR-3B status check gates reconciliation** (`purchase_reconciliation_tool.py:422-449`) — a real
  dependency between the two returns, enforced procedurally.

> **Invariant G26 — matching is a declared, versioned policy and every decision is a fact.** Match tiers are
> rows: an ordered rule set naming each field's comparison mode and tolerance, with a revision identity.
> Every match, unmatch and manual override is an append-only decision fact recording the rule revision that
> produced it, the tier reached, the fields that differed, the actor and the instant. Reconciliation state is
> a projection over those facts, never a mutable link on a document.

---

## 4. Bill of Entry: imports as a separate posting document

An import does not carry GST on the supplier invoice — customs assesses it at the border. `Bill of Entry` is
therefore a **submittable, GL-posting document** in its own right
(`india_compliance/gst_india/doctype/bill_of_entry/bill_of_entry.py:38-112`), unusual for a compliance app.

Its shape is conventional and careful:

| Concern | Method |
|---|---|
| defaults and accounts | `set_defaults` (`bill_of_entry.py:113-116`), `set_item_defaults` (`:117-122`), `set_default_accounts` (`:123-127`) |
| totals | `set_taxes_and_totals` (`:128-134`), `calculate_totals` (`:135-139`), `set_total_customs_and_taxable_values` (`:140-151`) |
| validation | `validate_purchase_invoice` (`:152-203`), `validate_taxes` (`:204-264`), `validate_item_tax_template` (`:265-303`) |
| posting | `get_gl_entries` (`:304-350`), `validate_account_currency` (`:351-356`) |
| downstream effects | `get_stock_items` (`:357-369`), `get_asset_items` (`:370-…`) |

The last row matters: a Bill of Entry knows about **stock items and asset items**, because customs duty and
ineligible IGST become part of inventory value and asset cost — the same coupling doc 46 §5 traced through
`IneligibleITC`, arriving from a different direction. `before_update_after_submit`
(`bill_of_entry.py:87-89`) again permits post-submission edits.

Purchase Invoice carries the other half: `set_pending_boe_qty` and `set_boe_applicability`
(`india_compliance/gst_india/overrides/purchase_invoice.py:114-137`) track how much of an import invoice is
still awaiting its Bill of Entry — a fulfilment relationship between a commercial document and a statutory
one, expressed as a **pending quantity field** rather than as links (doc 06 §6.2 rejected exactly this shape
for trade documents).

`set_itc_classification` (`india_compliance/gst_india/overrides/purchase_invoice.py:147-160`) and
`set_ineligibility_reason` (`:264-285`) classify the claim; `validate_with_inward_supply` (`:197-254`)
compares the invoice against downloaded portal data at validation time; `validate_supplier_invoice_number`
(`:161-174`) enforces the uniqueness the return depends on.

> **Invariant G27 — statutory import assessment is a first-class document with typed allocations.** Customs
> assessment is an immutable posting document referencing the commercial invoice lines it assesses, with each
> duty and tax component allocated to a named destination — creditable component, inventory value, or asset
> cost — as an explicit allocation fact. Coverage between commercial and statutory documents is a link graph
> with a derived residual, never a pending-quantity field.

---

## 5. Evidence versus projection

| Representation | Classification |
|---|---|
| posted invoices and their determination facts | the only real source (docs 46) |
| `GST Return Log` JSON blobs (`books`, `gov`, `reconcile`) | **memoised working sets** keyed by `is_latest_data` |
| `filing_status` | mutable state written by `db_set` in seven places |
| `upload_status` per books row | reconciliation output written **into** the books structure |
| synthesised `Missing in Books` rows | placeholder data inside the books working set |
| `GSTR 3B Report` payload | generated from a **JSON template file** on disk |
| declared values | formatted to a hard-coded 2 decimals |
| `GST Inward Supply` | authority's copy of our purchases — genuine external evidence |
| match status on a reconciliation row | derived from the rule ladder, stored, not versioned |
| `link_documents` / `unlink_documents` results | **mutable links**, no decision history |
| import history per period | download bookkeeping |
| `Bill of Entry` + its GL | real accounting evidence |
| `pending_boe_qty` on Purchase Invoice | mutable counter standing in for a link graph |

The government's data (`GST Inward Supply`) is the one genuinely append-only-shaped thing here, and it is the
one thing we do not own.

---

## 6. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) and docs 45–47. Money `numeric(19,4)`;
`company_id`-scoped with RLS and `FORCE RLS`; stable enum codes; append-only facts.

```sql
return_period(id, company_id, tax_registration_id, return_type text,
    period_start date, period_end date, frequency return_frequency_enum /*monthly|quarterly|annual*/,
    due_on date, state return_period_state_enum /*open|working|ready|filed|revised*/)
   UNIQUE (company_id, tax_registration_id, return_type, period_start)
   EXCLUDE USING gist (company_id WITH =, tax_registration_id WITH =, return_type WITH =,
      daterange(period_start, period_end, '[]') WITH &&)

return_working_set(id, company_id, return_period_id, version integer,
    source_watermark bigint NOT NULL, content_hash char(64) NOT NULL,
    format_revision_id bigint NOT NULL, output_precision smallint NOT NULL,
    built_at timestamptz, generator_version varchar(64), command_receipt_id)
   UNIQUE (company_id, return_period_id, version)
   -- immutable once built; rebuilding appends a version. Replaces `is_latest_data` memoisation.

return_working_set_line(id, company_id, return_working_set_id,
    statutory_category text NOT NULL, statutory_subcategory text NOT NULL,
    natural_key text NOT NULL, source_doc_type text, source_doc_id bigint,
    tax_determination_id bigint, taxable_value numeric(19,4), component_amounts jsonb)
   UNIQUE (company_id, return_working_set_id, statutory_subcategory, natural_key)

authority_dataset(id, company_id, tax_registration_id, dataset_type text /*gstr1_filed|gstr2a|gstr2b*/,
    period_start date, period_end date, retrieved_at timestamptz,
    payload_hash char(64), source authority_source_enum /*api|upload*/,
    attempt_id bigint NOT NULL)      -- the statutory_submission_attempt that fetched it
   UNIQUE (company_id, tax_registration_id, dataset_type, period_start, payload_hash)

reconciliation_run(id, company_id, return_period_id, return_working_set_id,
    authority_dataset_id, match_policy_revision_id bigint NOT NULL,
    comparison_precision smallint NOT NULL, run_at timestamptz, command_receipt_id)
   UNIQUE (company_id, command_receipt_id)

reconciliation_finding(id, company_id, reconciliation_run_id,
    statutory_subcategory text, natural_key text,
    finding finding_enum /*matched|mismatch|missing_in_books|missing_at_authority|
                          suggested|residual|manual*/,
    match_tier integer NULL, differing_fields text[] NULL,
    books_payload jsonb, authority_payload jsonb, signed_difference jsonb,
    books_source_doc_type text NULL, books_source_doc_id bigint NULL,
    authority_row_id bigint NULL)
   UNIQUE (company_id, reconciliation_run_id, statutory_subcategory, natural_key)
   CHECK ((finding = 'matched') OR differing_fields IS NOT NULL OR finding LIKE 'missing%')

match_policy_revision(id, company_id, jurisdiction_revision_id, revision_no integer,
    dataset_type text, state revision_state_enum, effective_from date, effective_to date NULL)
   UNIQUE (company_id, jurisdiction_revision_id, dataset_type, revision_no)
match_policy_tier(id, company_id, match_policy_revision_id, tier_no integer,
    resulting_finding finding_enum)
   UNIQUE (company_id, match_policy_revision_id, tier_no)
match_policy_field(id, company_id, match_policy_tier_id, field_code text,
    comparison comparison_mode_enum /*exact|fuzzy|rounding|ignored*/,
    tolerance numeric(19,4) NULL, fuzzy_threshold numeric(9,6) NULL)
   UNIQUE (company_id, match_policy_tier_id, field_code)

reconciliation_decision(id, company_id, reconciliation_finding_id,
    decision decision_enum /*accept_match|reject_match|link|unlink|defer|write_off|dispute*/,
    actor_id, decided_at timestamptz, reason_code text, reason text,
    match_policy_revision_id bigint NOT NULL,
    reverses_decision_id bigint NULL, command_receipt_id)
   UNIQUE (company_id, command_receipt_id)
   -- append-only; current linkage is a projection over unreversed decisions

return_filing(id, company_id, return_period_id, return_working_set_id,
    payload jsonb NOT NULL, payload_hash char(64) NOT NULL,
    acknowledgement_no text, filed_at timestamptz, authority_timestamp timestamptz,
    evidence_class evidence_class_enum, statutory_artefact_id bigint NULL,
    supersedes_filing_id bigint NULL, command_receipt_id)
   UNIQUE (company_id, return_period_id, payload_hash)
   -- one unreversed current filing per period, enforced by a deferred trigger under the period lock

customs_assessment(id, company_id, doc_no, import_declaration_no text,
    assessed_on date, supplier_id, currency_id, exchange_rate numeric(21,9),
    assessable_value numeric(19,4), voucher_id bigint NOT NULL REFERENCES voucher(id),
    state posting_state_enum, command_receipt_id, reverses_assessment_id bigint NULL)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, import_declaration_no)
customs_assessment_allocation(id, company_id, customs_assessment_id, source_line_type text,
    source_line_id bigint, tax_component_id bigint NULL, duty_code text NULL,
    amount numeric(19,4) NOT NULL,
    destination credit_destination_enum /*creditable|inventory_valuation|asset_cost|named_expense*/,
    stock_move_id NULL, asset_cost_event_id NULL, expense_account_id NULL, ordinal integer)
   UNIQUE (company_id, customs_assessment_id, source_line_id, tax_component_id, duty_code, ordinal)
      NULLS NOT DISTINCT
   CHECK (num_nonnulls(stock_move_id, asset_cost_event_id, expense_account_id) <= 1)
   -- deferred: Σ allocation per source line ≤ that line's assessed residual, under a source-line lock
```

The decisions that carry the value:

- **`match_policy_revision` / `_tier` / `_field` promote the rule ladder from a Python tuple to versioned
  data.** The upstream design is already declarative; this makes it auditable and changeable without a
  deploy, and lets a filed reconciliation name the policy that produced it.
- **`reconciliation_finding` keeps the signed difference**, both payloads and the differing field list —
  adopting upstream's best idea — while never writing back into the working set.
- **`return_working_set` is versioned and hashed**, so `is_latest_data` disappears: staleness is detectable
  by comparing the source watermark, not asserted by a boolean.
- **`comparison_precision` and `output_precision` are columns**, so the three separate hard-coded `2`s become
  one declared policy per period and format.
- **`reconciliation_decision` is append-only**, so "who accepted this match, under which rule version" is
  answerable — the question upstream cannot answer at all.
- **`customs_assessment_allocation.destination`** reuses doc 46's `credit_destination_enum`, so an import's
  ineligible IGST reaches inventory or asset cost through the same typed path as a domestic blocked credit.

**Write ordering** for a period:

```text
1  build working set: read posted determination facts up to a watermark → version N, content_hash
2  fetch authority dataset (via statutory_submission_attempt, doc 47) → authority_dataset
3  reconciliation_run pins (working_set, dataset, match_policy_revision, comparison_precision)
4  insert reconciliation_finding rows — pure function, no writes to either input
5  humans append reconciliation_decision rows; linkage is projected
6  file: insert return_filing with payload + hash + working_set version; on acknowledgement record
   the authority timestamp and artefact
7  close the period: return_period.state = filed → doc 46's posting guard now refuses that period
```

Amendment is a new `return_working_set` version and a `return_filing` with `supersedes_filing_id` — never an
edit of a filed payload.

> **Invariant G28 — relational return integrity.** Unique, foreign-key, check and exclusion constraints
> enforce non-overlapping return periods per registration and type, one finding per key per run, one current
> filing per period, unique authority datasets by payload hash, unique import declarations, and bounded
> customs allocation against each assessed source line.

---

## 7. Defects, races and unfinished paths

1. **The working set is a memoised blob gated by a boolean.** `is_latest_data` returns stale JSON when set
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:274-290`,
   `india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:686-745`).
2. **Reconciliation writes into its own input.** `upload_status` and synthesised `Missing in Books` rows are
   written into the books structure, then deleted on the next pass
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:263-362`).
3. **Comparison precision is a hard-coded 2.**
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:363-440`).
4. **Declared output precision is a hard-coded 2.**
   (`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:267-283`).
5. **`Matched` ignores tax rate and document value.**
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:252-262`).
6. **List subcategories are compared in aggregate**, so composition differences vanish
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:471-543`).
7. **`filing_status` is written by `db_set` at seven points** with no state-machine guard
   (`india_compliance/gst_india/doctype/gst_return_log/generate_gstr_1.py:805-1010`).
8. **The GSTR-3B statutory shape is a JSON file on disk**, with no format-version record on the filed return
   (`india_compliance/gst_india/doctype/gstr_3b_report/gstr_3b_report.py:261-266`).
9. **Match decisions are mutable link edits** with no decision history, actor or rule version
   (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/purchase_reconciliation_tool.py:269-323`).
10. **The match policy is a Python tuple**, so changing tolerance requires a deploy and a filed
    reconciliation cannot name its policy
    (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/__init__.py:79-260`).
11. **Import coverage is a pending-quantity field** rather than a link graph
    (`india_compliance/gst_india/overrides/purchase_invoice.py:114-137`).
12. **Bill of Entry permits post-submission edits.**
    (`india_compliance/gst_india/doctype/bill_of_entry/bill_of_entry.py:87-89`).
13. **Reconciliation depends on a GSTR-3B status probe**, enforced procedurally
    (`india_compliance/gst_india/doctype/purchase_reconciliation_tool/purchase_reconciliation_tool.py:422-449`).
14. **Download completeness is recovered by scanning**, not guaranteed
    (`purchase_reconciliation_tool.py:450-472`,
    `purchase_reconciliation_tool.py:506-529`).
15. **One document is working set, reconciliation, summary and filing state machine**
    (`india_compliance/gst_india/doctype/gst_return_log/gst_return_log.py:28-40`).

No lock or unique constraint was found around: working-set read → recompute; `filing_status` read → write;
link creation → residual check; or period download → import-history update.

> **Invariant G29 — serializable return operations.** Working-set materialisation, reconciliation runs,
> match decisions, filing and period closure are bounded writes under deterministic locks on
> (registration, return type, period) with idempotency keys and database uniqueness. A period cannot be filed
> twice, and a filing cannot race a posting into the same period.

---

## 8. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Statutory category/subcategory taxonomy | **Adopt** | `statutory_category`/`_subcategory` on working-set lines, per format revision |
| Government field names held separately | **Adopt** | format revision owns the wire mapping |
| Return log per registration and period | **Adopt** | `return_period` + versioned `return_working_set` |
| `is_latest_data` memoisation | **Reject** | versioned working set with watermark and content hash |
| Books vs gov bidirectional comparison | **Adopt** | `reconciliation_finding` both directions |
| Difference as the payload, with both sides retained | **Adopt** | `signed_difference`, `books_payload`, `authority_payload` |
| Writing `upload_status` into books data | **Reject** | findings never mutate their inputs |
| Synthesised placeholder rows | **Reject** | `missing_in_books` is a finding, not a row |
| Hard-coded 2-decimal comparison | **Change** | `comparison_precision` per run |
| Hard-coded 2-decimal output | **Change** | `output_precision` per format revision |
| Ignoring rate and doc value when matching | **Adopt as policy** | `comparison = ignored` on those fields, declared |
| Aggregate comparison of list subcategories | **Change** | aggregate **and** composition compared, with tiers |
| Filing status progression | **Adopt the states** | guarded transitions on `return_period` |
| Seven scattered `db_set` writes | **Reject** | one state machine |
| GSTR-3B from a JSON template | **Change** | versioned `format_revision`, recorded on the filing |
| Notification after commit | **Adopt** | outbox event |
| **Declarative match rule ladder** | **Adopt wholesale** | `match_policy_revision` / `_tier` / `_field` as data |
| Exact / fuzzy / rounding / mismatch vocabulary | **Adopt** | `comparison_mode_enum` with tolerance columns |
| Named tiers (exact/suggested/mismatch/residual/manual) | **Adopt** | `finding_enum` + `match_tier` |
| PAN-level fallback ladder | **Adopt** | a second policy revision keyed to the same dataset |
| Rules as a Python tuple | **Change** | versioned rows, no deploy to change tolerance |
| `link_documents` / `unlink_documents` | **Reject** | append-only `reconciliation_decision` |
| Import history and redownload filtering | **Adopt** | `authority_dataset` keyed by payload hash |
| Missing-document scan | **Change** | completeness derived from dataset coverage |
| GSTR-3B status gate before reconciliation | **Adopt** | dependency between `return_period` states |
| Bill of Entry as a posting document | **Adopt** | `customs_assessment` with its own voucher |
| Duty/tax into inventory and asset value | **Adopt** | typed `customs_assessment_allocation.destination` |
| `pending_boe_qty` counter | **Reject** | link graph with a derived residual (doc 06 §6) |
| Post-submission edits on Bill of Entry | **Reject** | immutable once posted; correction is reversal |
| `validate_with_inward_supply` at validate time | **Change** | a reconciliation finding, not a save-time gate |
| Supplier invoice number uniqueness | **Adopt** | unique constraint per supplier and fiscal year |

Invariants introduced here are **G24–G29**. Doc 49 closes the tranche and consolidates **G1–G29**.

---

Cross-references: [doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) (registration, settings),
[doc 46](46-gst-place-of-supply-and-component-determination.md) (determination facts the working set is built
from, and the period guard this layer closes), [doc 47](47-e-invoice-and-e-waybill-external-state-machines.md)
(submission attempts that fetch authority datasets),
[doc 04](04-ar-ap-and-settlement.md) (subledger reconciliation patterns),
[doc 06](06-lifecycle-status-and-returns.md) (link graph versus counters, and credit notes as the post-window
remedy), [doc 07](07-period-close-and-opening-balances.md) (period close this parallels),
[doc 14](14-banking-and-collections.md) (the other matching engine in the system — compare its rule
model with §3), [doc 15](15-intercompany-and-history-rewriting.md) (reposting and history),
[doc 41](41-asset-identity-acquisition-and-finance-books.md) (asset cost events imports must use), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 49 — Tranche F closure and our
localisation specification.
