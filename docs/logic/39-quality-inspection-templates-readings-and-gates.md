# 39 — Quality Inspection Templates, Readings and Gates

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev)
> and `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe
> citations are prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

Docs 33–38 followed production from BOM definition through internal and subcontracted execution. This
last operational-quality pass asks a narrower but consequential question: **what evidence releases a
receipt, delivery, stock move or operation when inspection is required?** ERPNext has two nearby but
separate answers. The eight **Quality Management** parents model procedures, goals, reviews, feedback,
meetings, non-conformances and actions. The four operational inspection parents live under **Stock**;
only `Quality Inspection` is submittable, carries readings and writes transaction references. There is
no controller bridge that makes the QM workflow the approval authority for operational stock or Job
Card gates.

The central findings are:

1. operational QI is Stock-owned and separate from Quality Management; QM records may link to one
   another, but transaction release reads only a row's `quality_inspection` and that QI's status/docstatus;
2. a template copies mutable criteria into QI child rows, after which numeric readings 1–10 or one value
   reading are evaluated; every nonempty numeric reading must fit the inclusive range and an empty set
   fails the ordinary min/max test;
3. formulas execute through `frappe.safe_eval` with `reading_1` … `reading_10`, `mean`, or
   `reading_value`; Data entered in a user's display format is parsed using the configured default
   `number_format`;
4. receipt/delivery/Stock Entry gates are one StockController service, while Job Card has a distinct
   manufacturing gate with different activation conditions; both trust a linked QI name without proving
   that it belongs to the gated row/document;
5. reference assignment and scheduler creation are check-then-write processes without uniqueness or
   owner locks, so duplicate claims/reviews and cross-reference release are possible; and
6. quality decisions should become immutable, criterion-revision-bound evidence; transaction links,
   status, dashboards and scheduled-work state should be rebuildable projections.

---

## 1. Twelve parents, two bounded subsystems

All requested parent controllers are source-covered. Their module ownership matters more than their
shared word “Quality”:

| Parent | Controller | Observed role |
|---|---|---|
| Non Conformance | `NonConformance(Document)` (`quality_management/doctype/non_conformance/non_conformance.py:9-28`) | schema-only record of a procedure issue and corrective/preventive prose |
| Quality Action | `QualityAction(Document)` (`quality_management/doctype/quality_action/quality_action.py:7-32`) | action container whose status rolls up from resolution rows |
| Quality Feedback | `QualityFeedback(Document)` (`quality_management/doctype/quality_feedback/quality_feedback.py:9-38`) | User/Customer feedback with template-copied ratings |
| Quality Feedback Template | `QualityFeedbackTemplate(Document)` (`quality_management/doctype/quality_feedback_template/quality_feedback_template.py:9-26`) | named feedback-question master |
| Quality Goal | `QualityGoal(Document)` (`quality_management/doctype/quality_goal/quality_goal.py:7-61`) | named objective set and monitoring frequency |
| Quality Meeting | `QualityMeeting(Document)` (`quality_management/doctype/quality_meeting/quality_meeting.py:7-29`) | agenda/minutes container with editable Open/Closed status |
| Quality Procedure | `QualityProcedure(NestedSet)` (`quality_management/doctype/quality_procedure/quality_procedure.py:9-54`) | nested-set procedure/process hierarchy |
| Quality Review | `QualityReview(Document)` (`quality_management/doctype/quality_review/quality_review.py:9-45`) | dated goal-objective snapshot with Open/Passed/Failed roll-up |
| Quality Inspection | `QualityInspection(Document)` (`stock/doctype/quality_inspection/quality_inspection.py:22-71`) | submittable operational inspection, readings, decision and reference writeback |
| Quality Inspection Template | `QualityInspectionTemplate(Document)` (`stock/doctype/quality_inspection_template/quality_inspection_template.py:8-27`) | ordered inspection-criterion master |
| Quality Inspection Parameter | `QualityInspectionParameter(Document)` (`stock/doctype/quality_inspection_parameter/quality_inspection_parameter.py:9-23`) | named parameter with optional group and description |
| Quality Inspection Parameter Group | `QualityInspectionParameterGroup(Document)` (`stock/doctype/quality_inspection_parameter_group/quality_inspection_parameter_group.py:9-21`) | named grouping master |

The first eight are under `quality_management`; the operational four and their reading child are under
`stock`. The operational reference types are Purchase Receipt, Purchase Invoice, Subcontracting Receipt,
Delivery Note, Sales Invoice, Stock Entry and Job Card
(`stock/doctype/quality_inspection/quality_inspection.json:43-72`). None of the QM parents appears in
that list. Conversely, Quality Action links Review/Feedback/Goal/Procedure, Quality Meeting minutes link
Review/Action/Feedback, and Procedure links the QM records, but those schemas contain no operational QI
foreign key (`quality_management/doctype/quality_action/quality_action.json:17-84`,
`quality_management/doctype/quality_meeting_minutes/quality_meeting_minutes.json:14-43`,
`quality_management/doctype/quality_procedure/quality_procedure.json:16-115`).

> **Invariant M56 — bounded quality authority.** An operational release decision has one typed authority
> and scope: criterion revision, inspected item/lot or operation, sample, source transaction line,
> inspector and decision. QM improvement records may cite that evidence, but cannot silently become or
> replace stock/production release authority merely because they share a module label.

---

## 2. Schema and lifecycle

### 2.1 Operational Quality Inspection

`Quality Inspection` is the only one of the twelve parents with `is_submittable`. Its required command
fields are series, report date, inspection type, reference type/name, item, sample size, inspector and
status. It can additionally carry company, serial, batch, BOM, template, parent manual-inspection mode,
verifier, remarks and hidden `child_row_reference`
(`stock/doctype/quality_inspection/quality_inspection.json:1-254`). Status defaults to Accepted and offers
Accepted, Rejected and Cancelled; `amended_from` gives the standard amendment lineage
(`stock/doctype/quality_inspection/quality_inspection.json:176-239`).

Its `Quality Inspection Reading` children contain:

- required `specification` linking a Quality Inspection Parameter and fetched `parameter_group`;
- one of exact `value`/`reading_value`, numeric `min_value`/`max_value`, or a formula;
- row-level `numeric`, `formula_based_criteria` and `manual_inspection` switches;
- row `status`; and
- ten Data fields, `reading_1` through `reading_10`, deliberately capable of carrying formatted numeric
  text (`stock/doctype/quality_inspection_reading/quality_inspection_reading.json:14-218`).

The three other Stock parents are editable masters, not evidence. Template is renameable, named by a
unique required field and requires an `Item Quality Inspection Parameter` table
(`stock/doctype/quality_inspection_template/quality_inspection_template.json:13-31`). Parameter is a
renameable unique name with optional group/description; Parameter Group is just a unique name
(`stock/doctype/quality_inspection_parameter/quality_inspection_parameter.json:13-35`,
`stock/doctype/quality_inspection_parameter_group/quality_inspection_parameter_group.json:13-22`). Their
controllers are otherwise `pass`; correctness resides in QI copying/evaluation, not in a template
approval lifecycle.

### 2.2 Quality Management parents and children

The QM schemas are all change-tracked but none is submittable. Their statuses therefore do **not** mean
Frappe docstatus transitions:

| Parent | Schema/children | Controller lifecycle |
|---|---|---|
| Non Conformance | required subject/procedure; fetched owner; details, corrective/preventive action; editable Open/Resolved/Cancelled (`quality_management/doctype/non_conformance/non_conformance.json:20-75`) | no methods; “Cancelled” is ordinary field text, not cancellation |
| Quality Action | optional Review/Feedback/Goal/Procedure; `Quality Action Resolution` rows (`quality_management/doctype/quality_action/quality_action.json:17-84`) | every validate sets Open iff any child is exactly Open, else Completed (`quality_management/doctype/quality_action/quality_action.py:31-32`) |
| Quality Feedback | required template and dynamic User/Customer identity; parameter/rating rows (`quality_management/doctype/quality_feedback/quality_feedback.json:16-61`) | defaults absent identity to session User; copies template rows only while the table is empty (`quality_management/doctype/quality_feedback/quality_feedback.py:29-38`) |
| Quality Feedback Template | unique name and required parameter table (`quality_management/doctype/quality_feedback_template/quality_feedback_template.json:13-32`) | no controller behavior; child parameter itself is optional free Data (`quality_management/doctype/quality_feedback_template_parameter/quality_feedback_template_parameter.json:10-20`) |
| Quality Goal | optional procedure, None/Daily/Weekly/Monthly/Quarterly frequency, weekday/date, objective/target/UOM children (`quality_management/doctype/quality_goal/quality_goal.json:19-68`) | `validate` is a no-op (`quality_management/doctype/quality_goal/quality_goal.py:60-61`) |
| Quality Meeting | editable Open/Closed, Agenda and Minutes tables (`quality_management/doctype/quality_meeting/quality_meeting.json:17-44`) | no controller behavior |
| Quality Procedure | tree identity/owner, parent, read-only `is_group`, `lft/rgt`, process/sub-procedure children (`quality_management/doctype/quality_procedure/quality_procedure.json:16-88`) | nested-set and reciprocal parent/child synchronization |
| Quality Review | required Goal, fetched Procedure, date, status and review-objective children (`quality_management/doctype/quality_review/quality_review.json:17-76`) | initial objective copy plus Open/Failed/Passed roll-up (`quality_management/doctype/quality_review/quality_review.py:30-45`) |

Resolution children have problem, resolution, responsible User, completion date and optional
Open/Completed status (`quality_management/doctype/quality_action_resolution/quality_action_resolution.json:14-47`).
An empty Quality Action or one whose rows have blank statuses is therefore Completed. Feedback parameters
hold read-only parameter, required 1–5 rating and prose
(`quality_management/doctype/quality_feedback_parameter/quality_feedback_parameter.json:14-44`). Goal
objectives require objective but target/UOM are optional
(`quality_management/doctype/quality_goal_objective/quality_goal_objective.json:14-40`). Review children
copy those fields read-only, add review prose and default Open/Passed/Failed status
(`quality_management/doctype/quality_review_objective/quality_review_objective.json:17-66`).

Meeting Agenda is one prose field. Minutes require a document type constrained to Quality Review,
Quality Action or Quality Feedback, but the Dynamic Link document name is not required
(`quality_management/doctype/quality_meeting_agenda/quality_meeting_agenda.json:10-18`,
`quality_management/doctype/quality_meeting_minutes/quality_meeting_minutes.json:14-43`). These are useful
coordination records, not release controls.

> **Invariant M57 — explicit quality lifecycle.** Draft criteria, sampled observations, calculated
> result, human disposition, operational release, non-conformance, corrective action and closure are
> distinct states/events. A display status such as Cancelled, Completed or Passed cannot substitute for
> a typed submit/reverse/approve transition with actor, time and reason.

---

## 3. Template construction and fallback

### 3.1 Template rows

An `Item Quality Inspection Parameter` template row stores parameter, fetched parameter group, numeric
mode, exact accepted value, min/max, formula mode and formula
(`stock/doctype/item_quality_inspection_parameter/item_quality_inspection_parameter.json:14-89`).
`get_template_details` returns rows by `idx` with specification, value, formula, numeric/formula flags and
min/max. It does not return the fetched group
(`stock/doctype/quality_inspection_template/quality_inspection_template.py:29-43`).

`get_item_specification_details` implements the actual copy:

1. if QI has no selected template, fetch `Item.quality_inspection_template`;
2. if still absent, return without readings;
3. clear the complete reading table;
4. copy ordered criterion values into new rows;
5. initialise every row status to Accepted; and
6. independently fetch each parameter's group
   (`stock/doctype/quality_inspection/quality_inspection.py:158-176`).

Validation calls this only when readings are empty and item exists
(`stock/doctype/quality_inspection/quality_inspection.py:73-76`). Server-side validation therefore leaves
populated rows as they are. Desk behavior is more destructive: changing Item invokes the BOM/Item helper
when no template is selected, and changing the selected template automatically invokes
`get_item_specification_details`, clearing and rebuilding readings
(`stock/doctype/quality_inspection/quality_inspection.js:69-88`). Existing observations can therefore be
erased by an ordinary form template change or explicit helper call. The QI child rows are a mutable
snapshot, not an immutable reference to a versioned criterion set.

### 3.2 BOM and Item fallback

`get_quality_inspection_template` is a separate UI/BOM-mapper helper. It first reads
`BOM.quality_inspection_template` using `bom_no`. If that is empty it appears to query **BOM by
`self.item_code` as the BOM document name**, not Item by item code. It unconditionally assigns that
result to the QI, then invokes `get_item_specification_details`, whose fallback reads the Item template
when the assigned value is blank (`stock/doctype/quality_inspection/quality_inspection.py:178-187`):

```text
ordinary validation:
    existing QI template, else Item[item_code].quality_inspection_template

UI/BOM helper (overwrites an existing QI selection):
    BOM[bom_no].quality_inspection_template
    or anomalous BOM[name = item_code].quality_inspection_template
    or Item[item_code].quality_inspection_template
```

The BOM mapper sets `bom_no` and item, then calls the helper in post-processing
(`stock/doctype/quality_inspection/quality_inspection.py:492-509`). The anomalous second BOM query is
usually masked by the Item fallback, but could select an unrelated BOM if a BOM's document name happens
to equal the Item code.

### 3.3 In-process overwrite

Validation has a separate Job Card rule. For inspection type In Process and reference type Job Card, it
loads the **Item** template, then for every existing reading replaces matching specification fields and
forces that child status Accepted
(`stock/doctype/quality_inspection/quality_inspection.py:77-86`). This occurs after an empty table may
have been filled from QI/BOM/Item selection. Matching Item criteria can therefore overwrite criteria
copied from a BOM or explicitly selected template, while unmatched rows remain. It is not a full template
version switch and does not record which source won per criterion.

> **Invariant M58 — criterion revision identity.** Every inspection snapshots one approved, immutable
> criterion revision. Each criterion records source, parameter, unit, numeric/value/formula mode, bounds
> or expression, sample rule and evaluation-engine version. BOM/Item fallback resolves once before
> sampling; later master edits or helper calls cannot rewrite observed evidence.

---

## 4. Readings 1–10, locale parsing and ordinary criteria

For a non-manual row without formula criteria, non-numeric comparison is exact string equality between
`reading_value` and configured `value`; missing values become empty strings. Numeric comparison delegates
to `min_max_criteria_passed` (`stock/doctype/quality_inspection/quality_inspection.py:292-301`).

The numeric algorithm is precise:

```text
has_reading = false
for reading_1 ... reading_10:
    if value is not None and value.strip() is nonempty:
        has_reading = true
        require min_value <= parse_float(value) <= max_value
        fail immediately on the first out-of-range value
return has_reading
```

(`stock/doctype/quality_inspection/quality_inspection.py:302-309`). Thus:

- **all** nonempty `reading_1` … `reading_10` must fit inclusive limits;
- blank slots are ignored rather than treated as failures;
- there is no requirement that populated count equal `sample_size`;
- `sample_size` can exceed ten even though the row exposes only ten slots; and
- an entirely empty numeric set returns false and is Rejected.

The fields are Data because users may enter locale-formatted numbers. `parse_float` reads the configured
`number_format` through `frappe.db.get_default`; without an explicit parent that API reads the
`__default` namespace, not the current user (`stock/doctype/quality_inspection/quality_inspection.py:512-527`,
`frappe/database/database.py:1162-1180`). For comma decimal plus dot grouping it temporarily swaps
punctuation, then calls `flt`; other formats pass directly to `flt`. This is default-format parsing at
validation time, not a stored canonical observation. A later default-format change can alter how the
same text is interpreted on another save.

The bulk creator enforces only `sample_size <= accepted quantity`, creates one draft QI per selected
transaction row and copies company/reference/item/description/sample size/first serial/batch/child row
(`controllers/stock_controller.py:659-692`). It does not populate one observation per sampled unit,
prevent duplicate serial sampling, submit the QI or reconcile sample size to the count of child-reading
values.

> **Invariant M59 — complete canonical sample.** An inspection sample has an explicit population,
> sampling plan and exact observation count. Each numeric observation is stored once in canonical unit
> and decimal representation plus original display text/locale. Every required observation must exist;
> every observation must satisfy the criterion for an automatic pass, and no fixed ten-column ceiling
> may truncate evidence.

---

## 5. Formula evaluation and Accepted/Rejected calculation

### 5.1 Formula environment

Formula rows require a nonempty expression and evaluate it with `frappe.safe_eval(condition, None, data)`
(`stock/doctype/quality_inspection/quality_inspection.py:311-320`). Their data is:

- non-numeric: `reading_value` only;
- numeric: `reading_1` … `reading_10`, converting only `None` to `0.0`, plus `mean` over nonempty values
  (`stock/doctype/quality_inspection/quality_inspection.py:338-351`).

Mean reuses locale parsing and is zero for no populated readings
(`stock/doctype/quality_inspection/quality_inspection.py:353-365`). Missing formula raises a row-specific
error. A `NameError` becomes “not a valid reading field”; every other exception becomes “formula is
incorrect” (`stock/doctype/quality_inspection/quality_inspection.py:311-336`). The expression returns any
truthy/falsy Python result; no Boolean type or formula revision is persisted.

Unlike ordinary min/max, formula mode has no blanket `has_reading` check. Empty numeric samples expose
zero/default values and `mean = 0`, so a formula such as `mean == 0` can accept no observations. Empty
strings are not the same as `None`: a present empty string reaches `parse_float`, which `flt` may coerce.
Formula behavior is therefore both expression-specific and input-shape-sensitive.

### 5.2 Child and parent status

For each reading, row-level `manual_inspection` suppresses automatic recalculation. Otherwise formula or
ordinary criteria set the child to Accepted/Rejected
(`stock/doctype/quality_inspection/quality_inspection.py:277-301`). Parent-level `manual_inspection`
suppresses only the parent roll-up. Without it, parent status starts Accepted and becomes Rejected on the
first Rejected child (`stock/doctype/quality_inspection/quality_inspection.py:285-290`). Before submit,
every child must have a nonblank status (`stock/doctype/quality_inspection/quality_inspection.py:212-215`).

Consequences:

- no readings means no automatic parent recalculation; the schema default Accepted survives;
- manual child status is accepted as authority without a separate disposition actor/reason;
- parent manual mode permits a status inconsistent with child rows;
- there is no verifier requirement even though `verified_by` exists; and
- Accepted means “no child currently says Rejected,” not “the declared sample is complete.”

> **Invariant M60 — deterministic evaluation and disposition.** Automatic evaluation is a pure,
> versioned function of canonical observations and immutable criteria; it returns pass/fail/error with a
> trace. Human override is a separate signed disposition with reason and authority. Parent release is
> Accepted only when the required sample is complete and every required criterion has an accepted result
> or authorised override.

---

## 6. Reference claiming, writeback and QI lifecycle

Before claiming a row, validation normalises `company`: when reference type/name exist, `set_company`
fetches the referenced parent's company and overwrites a differing QI value
(`stock/doctype/quality_inspection/quality_inspection.py:88-97`). This improves ordinary saved QIs, but
the downstream gates still do not compare the linked QI's company or reference scope; a manually/API-
assigned foreign QI name remains sufficient.

### 6.1 Claiming a source row

When `child_row_reference` is blank, QI validation derives the child DocType, joins it to Quality
Inspection on child name, and chooses the first same-item live child under the referenced parent for
which no QI joins (`stock/doctype/quality_inspection/quality_inspection.py:99-128`). Stock Entry uses
`Stock Entry Detail`; other references use `<Reference Type> Item`.

This is a preview claim only. There is no row lock and no database unique constraint on
`child_row_reference`; two concurrent QIs can both observe and claim the same first child. Because it
joins all QIs without filtering cancelled/deleted state, a surviving cancelled QI can also keep a row
from automatic selection even after its transaction link is cleared.

### 6.2 When references are written

The timing depends on Stock Settings:

- blank/Warn `action_if_quality_inspection_is_not_submitted`: draft `on_update` writes the reference;
- Stop: draft stays unlinked and `on_submit` writes it;
- cancel clears the reference and ignores Serial and Batch Bundle linkage; and
- trash forcibly removes the reference
  (`stock/doctype/quality_inspection/quality_inspection.py:189-210`).

For Job Card, update is restricted to matching Job Card name and `production_item == item_code`. For
transactions, QI updates matching parent/item children, additionally narrowing by batch for a live QI,
by current QI name on cancellation, and by child reference when present. If child reference is absent,
**every same-item row can be updated**. The parent `modified` timestamp is then written directly
(`stock/doctype/quality_inspection/quality_inspection.py:217-275`). These query updates bypass child save
hooks and versions.

Draft discard is separate from submitted cancellation. Frappe sets draft docstatus directly to 2 and
then calls `on_discard` (`frappe/model/document.py:1793-1809`); QI clears its reference and writes status
Cancelled (`stock/doctype/quality_inspection/quality_inspection.py:69-71`). Submitted cancel sets
docstatus 2 through save and dispatches `on_cancel` (`frappe/model/document.py:1768-1790`,
`frappe/model/document.py:1823-1893`). QI's schema status is not explicitly set to Cancelled in
`on_cancel`; standard UI/status behavior and its manual field can therefore diverge.

### 6.3 Creation permission switch

`validate_inspection_required` normally rejects creation of a purchase QI when the Item purchase flag is
off, and a delivery QI when the Item delivery flag is off. The global
`allow_to_make_quality_inspection_after_purchase_or_delivery` returns before those checks
(`stock/doctype/quality_inspection/quality_inspection.py:130-152`). This QI-side method does not apply
Item-flag creation checks to Subcontracting Receipt, Stock Entry or Job Card.

> **Invariant M61 — one inspection claim.** A transaction/operation line may have many inspection
> attempts but at most one current release decision per requirement revision. Claim, sample evidence,
> decision and release-link update commit under one owner lock and unique constraints; cancellation adds
> a reversal/supersession rather than broad mutable unlinking.

---

## 7. Receipt, delivery and Stock Entry gates

### 7.1 Invocation and applicability

`StockController.validate` invokes the inspection service for non-return documents
(`controllers/stock_controller.py:40-56`); the delegation itself is only
`QualityInspectionService(self).validate_inspection()` (`controllers/stock_controller.py:331-334`).
Thus returns bypass this generic gate.

The service maps:

| Parent | Item requirement flag |
|---|---|
| Purchase Receipt, Purchase Invoice, Subcontracting Receipt | `inspection_required_before_purchase` |
| Delivery Note, Sales Invoice | `inspection_required_before_delivery` |

(`stock/services/quality_inspection_service.py:19-29`). Purchase/Sales Invoice participates only when
`update_stock`; unsupported document types return. Stock Entry participates only when its document-level
`inspection_required` is true (`stock/services/quality_inspection_service.py:70-82`).

For Stock Entry, row eligibility is purpose- and direction-specific:

- Manufacture: finished-item row;
- Material Receipt, Repack, Receive from Customer, Subcontracting Return: row with target warehouse;
- Material Issue, Material Transfer, Material Transfer for Manufacture, Send to Subcontractor,
  Subcontracting Delivery, Disassemble: row with source warehouse different from target; and
- secondary and legacy scrap rows are excluded
  (`stock/services/quality_inspection_service.py:31-64`).

A required row without a QI warns on draft save and throws on submit. On submit, an unsubmitted QI obeys
`action_if_quality_inspection_is_not_submitted`; a Rejected QI independently obeys
`action_if_quality_inspection_is_rejected` (`stock/services/quality_inspection_service.py:110-149`). Both
settings default Stop and offer Stop/Warn
(`stock/doctype/stock_settings/stock_settings.json:130-135`,
`stock/doctype/stock_settings/stock_settings.json:268-273`). Warn therefore allows a submitted stock
transaction despite draft/cancelled or explicitly Rejected inspection evidence.

### 7.2 The allow-after early return

For Purchase Receipt, Purchase Invoice, Sales Invoice and Delivery Note, if the current row requires QI
and `allow_to_make_quality_inspection_after_purchase_or_delivery` is enabled, the method executes
`return` **from the entire row loop and entire validation method**, not `continue` for that row
(`stock/services/quality_inspection_service.py:84-109`). Any later rows — including potentially different
items — are not inspected by this call. Subcontracting Receipt and Stock Entry do not enter that bypass.
The setting itself defaults off (`stock/doctype/stock_settings/stock_settings.json:479-483`).

The helper used by the UI has related but not identical semantics. For a submitted document with the
allow-after setting it returns all supplied rows; Stock Entry returns all rows for later purpose-based
filtering; other transactions return only Item masters carrying the mapped requirement flag
(`controllers/stock_controller.py:627-656`). `make_quality_inspections` then saves drafts only
(`controllers/stock_controller.py:659-692`).

### 7.3 What the gate does not prove

Presence reads the row link. Submission reads only QI `docstatus`; rejection reads only QI `status`
(`stock/services/quality_inspection_service.py:110-149`). It does **not** prove that the QI's:

- `item_code` equals the row item;
- reference type/name equals this transaction;
- `child_row_reference` equals this row;
- inspection type matches incoming/outgoing/in-process purpose;
- company, batch or serial matches; or
- criterion revision/sample covers this quantity.

A user/API that writes the name of any submitted Accepted QI can therefore satisfy the gate. The
QI-side writeback usually creates a plausible link, but gate correctness cannot depend on all writers
using that helper.

> **Invariant M62 — stock release gate.** Receipt, delivery and stock-move submission requires an
> Accepted current decision whose immutable scope exactly matches company, transaction line, item,
> quantity/lot/serial, direction, requirement and criterion revision. Warn may record an authorised
> exception but never masquerade as a successful inspection; one row's bypass cannot skip another row.

---

## 8. Job Card is a separate gate

Job Card does not call `QualityInspectionService`. Its submit sequence validates inspection first, then
material transfer and the remaining Job Card rules; cancel updates Work Order/transferred projections
without cancelling the QI (`manufacturing/doctype/job_card/job_card.py:833-841`).

The gate activates only when **both** conditions are true:

```text
BOM.inspection_required
AND Work Order Operation.quality_inspection_required
```

(`manufacturing/doctype/job_card/job_card.py:843-849`). If active it requires `Job Card.quality_inspection`,
reads only that QI's status/docstatus and applies the same two Stock Settings Stop/Warn policies
(`manufacturing/doctype/job_card/job_card.py:850-890`). It does not prove reference type/name, production
item, operation, BOM, criterion revision, sample or company. QI-side Job Card writeback does require
matching production item (`stock/doctype/quality_inspection/quality_inspection.py:220-231`), but a manual
or API link bypasses that protection.

This is not the Stock Entry manufacture gate:

- Job Card gate controls completion of operation evidence and is conjunctively configured by BOM plus
  operation;
- Stock Entry gate controls selected stock rows when the Stock Entry's `inspection_required` is set; and
- a process can encounter neither, one, or both gates depending on configuration.

After QI, Job Card independently checks transferred quantity and then stopped Work Order, hold, time log
and completion conditions (`manufacturing/doctype/job_card/job_card.py:891-916`). A Warned/released Job
Card is still not stock receipt evidence; a later Manufacture Stock Entry is separate.

> **Invariant M63 — operation release gate.** Job/operation completion and inventory receipt are
> separate bounded releases. An in-process decision must match the exact Job Card, Work Order operation,
> item, routing/BOM criterion revision and completed quantity. A later stock receipt decision may reuse
> observations only through an explicit compatible requirement, never by sharing an unverified QI name.

---

## 9. Quality Management behavior in detail

### 9.1 Feedback and Review snapshots

Quality Feedback defaults a missing respondent to the session User and copies template parameters at
rating 1 only when no rows exist (`quality_management/doctype/quality_feedback/quality_feedback.py:29-38`).
Changing the selected template after rows exist leaves old parameters untouched. The copied child does
not retain a template-row revision ID.

Quality Review behaves similarly: only an empty review table is populated from the current Goal's
objective/target/UOM, then parent status is Open for no rows or any Open row, Failed if any remaining row
is Failed, otherwise Passed (`quality_management/doctype/quality_review/quality_review.py:30-45`).
Changing Goal/master objectives does not reconcile existing review rows. The snapshot intent is useful,
but provenance/version is absent.

### 9.2 Scheduled Quality Reviews

The daily-maintenance hook registers `quality_review.review`
(`hooks.py:496-526`). That function iterates every Quality Goal and creates a review when:

- Daily: every run;
- Weekly: configured weekday equals `strftime("%A")`;
- Monthly: configured date string equals day-of-month; or
- Quarterly: day is 1 and `strftime("%B")` is January, April, July or October
  (`quality_management/doctype/quality_review/quality_review.py:48-79`).

The schema and quarter list use English names, while `strftime` can be process-locale-sensitive; a
non-English runtime locale can therefore prevent weekly or quarterly matches.

Creation inserts with `ignore_permissions=True` and has no existence/idempotency check
(`quality_management/doctype/quality_review/quality_review.py:67-72`). Retry, overlapping scheduler
workers or manual invocation can therefore create duplicate reviews for one Goal/date. Goal schema
offers weekdays Monday–Saturday only and dates 1–30; Quarterly displays the date field but scheduler
ignores it (`quality_management/doctype/quality_goal/quality_goal.json:19-53`). “None” creates nothing,
but combinations are not server-validated because Goal `validate` is empty.

### 9.3 Procedure hierarchy

Quality Procedure is the one substantial QM master controller. Before save it rejects a linked child
already owned by another parent and sets `is_group = 1`
(`quality_management/doctype/quality_procedure/quality_procedure.py:56-72`). Update runs NestedSet,
sets missing child parents, clears removed child parents, appends itself to a new parent's process table
and removes itself from the old parent; insert performs the initial parent synchronization
(`quality_management/doctype/quality_procedure/quality_procedure.py:34-49`,
`quality_management/doctype/quality_procedure/quality_procedure.py:74-126`). Deletion blanks process-row
links to this procedure before nested-set trash (`quality_management/doctype/quality_procedure/quality_procedure.py:50-54`).
Tree APIs read process-child order or roots and permit POST node insertion
(`quality_management/doctype/quality_procedure/quality_procedure.py:129-161`).

`is_group` is sticky: removing all linked child procedures never resets it. Reciprocal synchronization
performs several reads, direct writes and parent saves without a hierarchy owner lock, so concurrent
parent/process edits can lose or duplicate relationships.

> **Invariant M64 — versioned QM snapshots.** Feedback questions, goal objectives, review targets and
> procedure revisions are immutable once used. A feedback/review stores exact source-row revision IDs;
> changing a master creates a new revision. Status is projected from typed child states, with empty or
> blank children treated as incomplete rather than successful.

> **Invariant M65 — idempotent scheduled review.** A schedule occurrence has one durable identity such
> as `(goal_revision, due_date, frequency_occurrence)`. Scheduler retry inserts-or-gets that occurrence
> under a unique constraint; calendar rules are validated server-side and cannot silently omit Sunday,
> day 31 or a configured quarterly day.

---

## 10. Cancellation, deletion and correction

Only operational QI follows submit/cancel/amend. On cancel it unlinks transaction rows that still point
to itself; on trash it unlinks regardless of docstatus via `remove_reference=True`
(`stock/doctype/quality_inspection/quality_inspection.py:204-210`,
`stock/doctype/quality_inspection/quality_inspection.py:217-275`). Generic deletion rejects submitted
documents and locks/checks before deletion; `on_trash` runs before parent/child removal and after the
initial permission/docstatus checks (`frappe/model/delete_doc.py:24-78`,
`frappe/model/delete_doc.py:137-185`). A submitted QI must therefore be cancelled before normal delete,
while draft QI deletion can clear transaction links.

The QM parents are draft-style mutable records. Their “Cancelled” or “Closed” labels do not invoke QI's
unlink or Frappe cancellation behavior. Quality Procedure alone has custom trash cleanup. Deleting
masters can still be prevented by generic static/dynamic links, but there is no immutable review/action
history contract in these controllers.

Correction consequences in the current model:

- editing a draft QI recalculates mutable child and parent status in place;
- cancelling/deleting QI erases the transaction projection rather than preserving a release reversal on
  the transaction line;
- a replacement/amended QI can claim/write the line again;
- QM feedback/review/action rows are ordinary mutable documents; and
- direct query writeback can change references without child Version evidence.

> **Invariant M66 — append-only quality correction.** Submitted observations, evaluation traces,
> dispositions, operational releases, review occurrences and action closures are immutable facts.
> Correction adds reversal/supersession events linked to the prior fact. Deletion is limited to unused
> drafts; it never erases the evidence that allowed or blocked a posted operation or stock transaction.

---

## 11. Evidence versus projection

| Representation | Classification |
|---|---|
| Quality Inspection Template / Parameter / Group | mutable master configuration, not evidence and not revisioned |
| QI copied reading criterion fields | intended criterion snapshot, but mutable draft/submitted-child storage without source revision |
| QI `reading_value`, `reading_1..10` | observation evidence in intent; mutable locale-formatted text in implementation |
| automatic child status | calculated projection over observations/criteria |
| manual child status | disposition-like scalar without actor/reason lineage |
| QI parent Accepted/Rejected | release-decision projection; can also be manually set/suppressed |
| submitted QI identity/docstatus | strongest current operational inspection evidence |
| transaction/Job Card `quality_inspection` | mutable reference projection written directly |
| receipt/delivery/Stock Entry gate outcome | transient validation decision; no durable per-gate release event |
| Job Card gate outcome | separate transient operation validation decision |
| Quality Procedure/Goal/Template | mutable QM definitions |
| Quality Feedback/Review child copies | weak snapshots without source revision identity |
| Non Conformance/Action/Meeting | mutable improvement/coordination records |
| Quality Action/Review/Meeting status | mutable roll-up/presentation projection |
| scheduler-created Quality Review | durable record, but occurrence identity and idempotency absent |

The evidence boundary should be stronger. Sampling facts and signed disposition should exist before an
operational release is attached. A stock or Job Card submission should consume one exact release event
under the same transaction/lock, then the row link and parent status should project that fact. QM
records can open from a rejected decision or trend, but they remain improvement workflow, not the
stock/production posting itself.

> **Invariant M67 — evidence before quality projection.** Canonical observations, deterministic
> evaluation, signed disposition and exact scoped release/hold commit atomically before transaction,
> Job Card, QM roll-up or dashboard projections advance. Rebuilding those projections from the event
> log produces the same current decision and history.

---

## 12. Target backend and database model

The replacement should not reproduce DocType-shaped mutable child tables. It should separate definition,
sampling, evaluation, disposition, gate consumption and improvement workflow.

### 12.1 Definition and revision tables

| Target table | Key columns and constraints |
|---|---|
| `quality_parameter` | UUID; stable code/name; canonical data type and default unit; optional group; unique tenant/company code |
| `quality_parameter_group` | UUID; stable code/name; hierarchy only if actually required |
| `inspection_template` | stable template identity and ownership scope |
| `inspection_template_revision` | template FK, revision, effective interval, status draft/approved/retired; unique `(template_id, revision)`; approved rows immutable |
| `inspection_criterion` | revision FK, ordinal, parameter FK, mode, unit, min/max/value/formula, required observation count, rounding and null policy; unique `(revision_id, ordinal)` |
| `criterion_expression_revision` | parsed/validated expression AST or constrained DSL, engine version, hash and allowed variables; no runtime arbitrary Python surface |

BOM/Item/routing configuration should reference an approved template revision, not a mutable name.
Resolution precedence is explicit policy: operation override, BOM revision, Item revision, or none. The
resolved revision is snapshotted into the requirement before observations begin.

### 12.2 Operational evidence tables

| Target table | Key columns and constraints |
|---|---|
| `inspection_requirement` | typed source scope: company, transaction/operation line, item, lot/serial/quantity, direction, criterion revision; idempotency key and current-state version |
| `inspection_attempt` | requirement FK, attempt number, sampler/inspector, started/completed timestamps, sampling-plan revision; unique `(requirement_id, attempt_no)` |
| `inspection_sample_unit` | attempt FK, sequence, selected lot/serial/unit identity; unique selected identity where sampling without replacement applies |
| `inspection_observation` | sample unit/criterion FK, canonical decimal/text value, original text, locale/unit, observed time/actor; unique required observation position |
| `inspection_evaluation` | attempt/criterion FK, evaluator version, result pass/fail/error, trace/hash; immutable |
| `inspection_disposition` | attempt FK, accepted/rejected/conditional, actor, authority role, reason, signature/time; immutable and one current via supersession |
| `quality_release` | exact requirement/disposition scope and release/hold/exception type; unique active release per requirement revision |
| `quality_gate_consumption` | release FK plus transaction/Job Card line and posted command ID; unique `(gate_type, source_line_id, source_revision)` |

Database constraints enforce bounds and identity. A deferred constraint/transactional service must prove
observation completeness, criterion coverage and disposition authority before creating `quality_release`.
Stock/Job Card submission locks the source line and requirement in deterministic order, validates exact
scope, inserts gate consumption, then posts business evidence. A Warn policy becomes an explicit
`quality_exception` signed by an authorised role, never a missing/rejected QI treated as accepted.

### 12.3 QM workflow tables

| Target table | Role |
|---|---|
| `quality_procedure` / `quality_procedure_revision` | immutable procedure graph revision; DB-enforced acyclic parent edges |
| `quality_goal` / `quality_goal_revision` | effective-dated objective and schedule revision |
| `quality_review_occurrence` | unique scheduled/manual occurrence by goal revision/date |
| `quality_review_result` | objective result and evidence links; status projected |
| `quality_feedback_template_revision` / `quality_feedback_response` | immutable question revision and respondent answers |
| `non_conformance` | typed source evidence, severity, owner and lifecycle events |
| `quality_action` / `quality_action_task` | corrective/preventive task evidence, due dates and completion events |
| `quality_meeting` / `quality_meeting_item` | coordination record linking typed QM evidence |

Rejections may idempotently open a Non Conformance according to policy, but operational hold/release does
not wait on editable meeting/action status unless an explicit requirement says so. Projectors derive
current inspection status, transaction link, review/action status, due work and dashboards.

> **Invariant M68 — relational quality integrity.** Unique, foreign-key and check constraints enforce
> criterion revision, observation position, attempt identity, one current disposition/release, exact gate
> scope and scheduled occurrence. Application helpers may improve messages; they are not the only barrier
> against duplicate claims, mismatched releases or incomplete samples.

---

## 13. Defects and race inventory

### 13.1 Operational QI defects

1. **BOM fallback appears to use Item code as BOM name.** The second lookup is
   `BOM[self.item_code]` before Item fallback (`stock/doctype/quality_inspection/quality_inspection.py:178-187`).
2. **Template reload destroys observations.** The loader clears all reading rows before copying criteria
   (`stock/doctype/quality_inspection/quality_inspection.py:158-176`).
3. **In-process overwrite mixes sources.** Matching Item criteria overwrite existing rows and force
   Accepted; unmatched BOM/template rows remain (`stock/doctype/quality_inspection/quality_inspection.py:77-86`).
4. **Sample size is not sample completeness.** It is not tied to populated reading count, and ten fixed
   slots cap representation (`stock/doctype/quality_inspection_reading/quality_inspection_reading.json:14-218`).
5. **Formula can accept an empty sample.** Missing numeric fields/mean become zero
   (`stock/doctype/quality_inspection/quality_inspection.py:338-365`).
6. **No-reading parent can retain Accepted.** Evaluation runs only when readings exist and status defaults
   Accepted (`stock/doctype/quality_inspection/quality_inspection.py:73-91`,
   `stock/doctype/quality_inspection/quality_inspection.json:232-239`).
7. **Locale-dependent reparsing.** Stored Data text is interpreted using current default number format
   (`stock/doctype/quality_inspection/quality_inspection.py:512-527`).
8. **Child-row claim races.** First-free lookup has no row lock/unique constraint
   (`stock/doctype/quality_inspection/quality_inspection.py:99-128`).
9. **Broad direct writeback.** Missing child reference updates every same-item line and bypasses child
   controller/version logic (`stock/doctype/quality_inspection/quality_inspection.py:217-275`).
10. **Gate accepts foreign QI.** Service validates only linked QI docstatus/status
    (`stock/services/quality_inspection_service.py:110-149`).
11. **Allow-after exits the full loop.** One qualifying row bypasses all later rows
    (`stock/services/quality_inspection_service.py:84-109`).
12. **Stop/Warn conflates exception with release.** Warn allows submit with unsubmitted or Rejected QI
    (`stock/services/quality_inspection_service.py:121-149`).
13. **Job Card repeats foreign-link weakness.** It reads only QI status/docstatus
    (`manufacturing/doctype/job_card/job_card.py:843-890`).
14. **Job Card and transaction gates can diverge.** They are separately activated and consume no shared
    requirement identity.

### 13.2 Quality Management defects

1. **Empty Quality Action becomes Completed.** Blank child status also does not count Open
   (`quality_management/doctype/quality_action/quality_action.py:31-32`).
2. **Non Conformance Cancelled is not cancellation.** Its controller is empty and schema status is
   ordinary required text (`quality_management/doctype/non_conformance/non_conformance.py:9-28`,
   `quality_management/doctype/non_conformance/non_conformance.json:37-43`).
3. **Feedback/Review snapshots lack revision provenance.** Existing children never refresh when the
   source master changes (`quality_management/doctype/quality_feedback/quality_feedback.py:29-38`,
   `quality_management/doctype/quality_review/quality_review.py:30-36`).
4. **Goal schedule combinations are not validated.** Sunday/day 31 are impossible in schema; Quarterly
   ignores selected date, and locale-sensitive weekday/month strings are compared with English values
   (`quality_management/doctype/quality_goal/quality_goal.json:19-53`,
   `quality_management/doctype/quality_review/quality_review.py:48-79`).
5. **Review scheduler duplicates.** Insert has neither existence check nor unique occurrence identity
   (`quality_management/doctype/quality_review/quality_review.py:67-72`).
6. **Procedure `is_group` is sticky.** Child removal does not reset it
   (`quality_management/doctype/quality_procedure/quality_procedure.py:56-105`).
7. **Procedure synchronization races.** Reciprocal parent/child changes are several unlocked reads and
   writes (`quality_management/doctype/quality_procedure/quality_procedure.py:74-126`).
8. **Meeting minute target is optional.** A required document type can be saved without document name
   (`quality_management/doctype/quality_meeting_minutes/quality_meeting_minutes.json:14-43`).

### 13.3 Shared race pattern

No deterministic owner lock or database uniqueness was found around:

- source child “unclaimed” check → QI insert/writeback;
- draft QI status calculation → transaction submit using its link;
- linked QI status/docstatus read → stock or Job Card commit;
- Goal due check → Quality Review insert; or
- Quality Procedure child-parent check → reciprocal hierarchy writes.

Two QIs can claim one line; a QI can change/cancel between gate read and surrounding commit if not covered
by the same database lock semantics; two schedulers can create the same review; two procedure edits can
both observe no parent. Even where the request transaction rolls back on error, read-check-write without
an owner/unique constraint does not serialize the business invariant.

> **Invariant M69 — serializable quality decisions.** Requirement claim, observations, disposition,
> operational gate consumption, scheduled review occurrence and procedure-parent allocation are bounded
> writes. Validate and insert under deterministic locks with idempotency keys and database uniqueness;
> concurrent individually valid commands may not jointly exceed one current claim/release/occurrence.

---

## 14. Target decisions

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Stock-owned operational QI separate from QM | **Adopt boundary** | operational evidence/release service; QM consumes links/events but does not own stock posting |
| Parameter and Parameter Group masters | **Adopt concept** | stable IDs, typed canonical units and tenant/company uniqueness |
| Mutable Quality Inspection Template | **Change** | approved immutable template revisions with effective dates |
| Ordered template criteria | **Adopt** | criterion ordinal plus stable criterion ID and source revision |
| BOM then Item template fallback | **Change** | explicit deterministic precedence resolved once; remove Item-code-as-BOM lookup |
| Clearing/copying criteria into QI | **Reject mutation** | snapshot immutable criterion revision IDs; observations are separate append-only rows |
| Fixed `reading_1..10` Data columns | **Reject** | unbounded observation rows in canonical numeric/text form with original locale text |
| Inclusive min/max applied to every nonempty reading | **Adopt rule** | versioned criterion evaluator, plus mandatory sample completeness |
| Empty numeric set fails min/max | **Adopt** | generalise: incomplete required sample is evaluation error/hold, never Accepted |
| Exact value comparison | **Adopt when configured** | typed/collation-explicit value criterion |
| User-number-format parsing | **Change** | parse once at input boundary; retain locale/original text and store canonical decimal |
| `frappe.safe_eval` formula | **Reject runtime shape** | constrained versioned expression DSL/AST with explicit types, variables and engine hash |
| Automatic child and parent status roll-up | **Adopt intent** | deterministic criterion results and projected attempt decision |
| Manual child/parent inspection switches | **Change** | signed override/disposition event with reason and authority |
| QI submittable/amendable lifecycle | **Adopt intent** | immutable attempt/disposition; correction by supersession/reversal |
| Draft/submit reference timing selected by Stop/Warn | **Reject** | exact release link only after accepted disposition or authorised exception |
| First unclaimed child-row lookup | **Reject** | explicit source-line requirement plus unique active claim under lock |
| Direct reference writeback | **Projection only** | projector from `quality_gate_consumption`; never business authority |
| Purchase/delivery allow-after switch | **Change** | explicit post-receipt quarantine workflow; no whole-loop early return |
| StockController transaction gate | **Adopt concept** | exact-scope release consumption in transaction posting unit of work |
| Purpose/direction-specific Stock Entry rows | **Adopt policy** | typed requirement generator per stock-move role, revisioned and tested |
| Missing QI on a required row/Job Card | **Adopt Stop** | hard hold until an Accepted release or separately authorised exception exists |
| Stop on linked but unsubmitted/rejected QI | **Adopt default** | hard hold until Accepted release |
| Warn on linked but unsubmitted/rejected QI | **Change** | signed exception event with role, reason, expiry and audit; never Accepted |
| Gate reading only QI docstatus/status | **Reject** | FK-bound requirement/release scope validation at database/service boundary |
| Separate Job Card operation gate | **Adopt separately** | exact operation release distinct from stock receipt release |
| Job Card gate requiring BOM AND operation flags | **Change** | explicit generated requirement; configuration precedence is visible and testable |
| Feedback template one-time child copy | **Adopt snapshot intent** | immutable feedback-template revision references |
| Goal review objective one-time copy | **Adopt snapshot intent** | immutable goal-revision occurrence and objective-result rows |
| Scheduler-created Quality Reviews | **Adopt** | one unique occurrence per goal revision/date with retry-safe insert |
| Quality Procedure nested set plus process links | **Change** | one canonical acyclic graph/tree representation; no reciprocal mutable duplicates |
| Editable QM statuses | **Projection only** | event-derived state from tasks/results/closure decisions |
| QI/QM deletion after use | **Reject** | drafts deletable; used evidence reversible/supersedable only |
| Unlocked check-then-write claims and schedules | **Reject** | owner locks, unique constraints, idempotency keys and transactional outbox/projectors |

The fourteen invariants added here are **M56–M69**: bounded quality authority; explicit quality lifecycle;
criterion revision identity; complete canonical sample; deterministic evaluation and disposition; one
inspection claim; stock release gate; operation release gate; versioned QM snapshots; idempotent
scheduled review; append-only quality correction; evidence before projection; relational quality
integrity; and serializable quality decisions. Together with M41–M55 from doc 38 they complete the
production execution boundary: material may be internally manufactured or subcontracted, but no
operation or stock movement is quality-released without exact, immutable, criterion-bound evidence and
a serializable gate consumption.

---

Cross-references: doc 06 (submit/cancel/status), doc 09 (lifecycle/deletion), doc 20 (identity/audit),
doc 22 (schedulers/locking), doc 32 (Stock Settings), docs 33–35 (BOM/operations/Job Cards), doc 37
(manufacturing stock evidence), doc 38 (subcontract receipt/production),
[S09](../scenarios/S09-quality-gated-production-and-receipt.md) (quality scenario),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (Tranche B closure and production
specification), and `docs/design/FINAL-SCHEMA.md` (target evidence, allocation and projection model).
