# S09 — Quality-Gated Production and Receipt: Inspection → Release → Posting

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Continues **[S03](S03-procure-to-pay.md)** at Purchase Receipt and
> **[S07](S07-make-to-order-manufacturing.md)** at Job Card and Manufacture Stock Entry. The complete
> subsystem trace and target model are **[doc 39](../logic/39-quality-inspection-templates-readings-and-gates.md)**.
>
> This is an investigation document. It distinguishes inspection evidence, release decisions, stock
> evidence, accounting evidence and mutable projections; an Accepted label is not itself a stock move.

---

## 1. One worked flow, with strict and warned replays

AlphaCo receives three inspection-controlled raw materials from supplier **Metals Ltd** against
submitted **PO-QA-0001**, then consumes part of two of them to make **5 EA FG-QA**. Perpetual inventory
and moving-average valuation are enabled; `Accounts Settings.book_stock_expense_gl_entries=0`, so
there is no optional Expenses Added to Stock memorandum pair. There are no taxes, landed costs,
serial/batch bundles, rejected-warehouse quantities, rounding adjustments or standard-cost variances.
Raw, WIP and Finished Goods use distinct inventory accounts.

**PR-QA-0001** is deliberately multi-row:

| PR row | Item | Accepted quantity | Rate | Stock value | Incoming requirement |
|---:|---|---:|---:|---:|---|
| 1 | RM-QA-A | 10 kg | 4.00 | **40.00** | Item requires inspection before purchase |
| 2 | RM-QA-B | 5 kg | 6.00 | **30.00** | Item requires inspection before purchase |
| 3 | RM-QA-C | 2 kg | 10.00 | **20.00** | Item requires inspection before purchase |
| **Total** | | **17 kg** | | **90.00** | |

The manufacturing continuation uses 5 kg RM-QA-A and all 5 kg RM-QA-B:

| Kind | Item / operation | Quantity | Value |
|---|---|---:|---:|
| WIP input | RM-QA-A | 5 kg × 4.00 | 20.00 |
| WIP input | RM-QA-B | 5 kg × 6.00 | 30.00 |
| Operation | Finish | 5 EA | 10.00 added cost |
| Output | FG-QA | 5 EA | **60.00**, or 12.00/EA |

The route has one Job Card **JC-QA-0001** for 5. Both `BOM.inspection_required=1` and its exact Work
Order Operation `quality_inspection_required=1`. The later **STE-QA-MFG-0001** has purpose Manufacture,
`inspection_required=1`, two source rows and one `is_finished_item=1` target row. Those two switches
activate **different gates**.

The same documents are replayed under these controlled states:

| Replay | Receipt row QIs | Job Card QI | Manufacture FG-row QI | Result |
|---|---|---|---|---|
| **Accepted** | all submitted Accepted | submitted Accepted | submitted Accepted | ordinary PR, operation and Manufacture posting |
| **Stop** | row 2 draft or row 3 submitted Rejected | draft or Rejected | Rejected | the affected submit throws; its transaction writes nothing |
| **Warn** | row 1 Accepted; row 2 draft; row 3 submitted Rejected | linked draft | submitted Rejected | warnings, but ordinary operation/stock/SLE/GL writes still occur |
| **Missing** | a required row has no QI and allow-after is off | no QI | no QI | always blocked on submit; Stop/Warn does not govern absence |
| **Allow after** | first required row has no QI; later rows are draft/Rejected | not applicable | not applicable | Purchase Receipt gate returns from the whole loop and posts; QIs may be created later as drafts |

These are policy replays, not five cumulative receipts. The Accepted and Warn ledgers below therefore
show alternative outcomes for the same quantities, not double stock.

---

## 2. Criteria, observations and disposition before any gate

### 2.1 Which template is selected

AlphaCo approves two conceptual criterion sets:

- **QIT-RM-QA-01** is the Item template for all three receipt Items.
- **QIT-FG-QA-01** is the released BOM template for FG-QA; the Item also has a fallback template.

Ordinary QI validation uses an explicitly selected template or `Item.quality_inspection_template`, then
clears and copies ordered criteria into `Quality Inspection Reading`, initially setting each row to
Accepted (`stock/doctype/quality_inspection/quality_inspection.py:158-176`). The separate BOM/UI helper
tries `BOM[bom_no].quality_inspection_template`; if blank it anomalously queries **BOM whose name equals
`item_code`**, then invokes the Item fallback (`stock/doctype/quality_inspection/quality_inspection.py:178-187`).
The BOM mapper calls that helper after copying BOM/item/quantity into a new QI
(`stock/doctype/quality_inspection/quality_inspection.py:492-509`). Changing the template in Desk clears
and rebuilds readings, so an ordinary helper call can destroy observations
(`stock/doctype/quality_inspection/quality_inspection.js:69-88`).

For the worked QIs the selected template and copied criterion snapshot are fixed **before** sampling:

| Criterion | Mode | Rule | Required worked observations |
|---|---|---|---|
| Diameter | numeric | inclusive 9.50–10.50 mm | 10 readings |
| Hardness | numeric formula | `mean >= 50 and reading_1 <= 55` | 10 readings |
| Grade | exact text | `A` | one `reading_value` |
| Surface | manual row | inspector disposition | signed reason in target design |

ERPNext stores ten Data fields, `reading_1` through `reading_10`, plus numeric/formula/manual flags and a
row status (`stock/doctype/quality_inspection_reading/quality_inspection_reading.json:14-218`). It does
not store a criterion-revision identity or bind `sample_size` to the number of observations.

### 2.2 A complete Accepted sample, including locale text

Assume default number format `#.###,##`. QI-RM-A-0001 records:

| Criterion | `reading_1` … `reading_10` / value | Evaluation |
|---|---|---|
| Diameter | `9,80`; `10,00`; `10,10`; `9,90`; `10,20`; `10,00`; `9,70`; `10,30`; `10,10`; `9,90` | every nonempty value is within 9.50–10.50 → Accepted |
| Hardness | `50`; `51`; `52`; `50`; `53`; `51`; `54`; `52`; `50`; `51` | mean 51.4 and first 50 ≤ 55 → Accepted |
| Grade | `A` | exact match → Accepted |
| Surface | manual `Accepted` | ERPNext trusts the row scalar; target also requires actor, authority and reason |

For ordinary numeric criteria ERPNext loops positions 1–10, ignores blanks, and requires **every
nonempty** parsed reading to lie within inclusive min/max. It fails immediately on an out-of-range value
and returns false if all ten are empty (`stock/doctype/quality_inspection/quality_inspection.py:302-309`).
Thus one `10,51` rejects Diameter, while nine valid values plus one blank pass even if `sample_size=10`.
An entirely empty ordinary numeric set is correctly Rejected, but it is not reported as an evidence-
completeness error.

`parse_float` reads the default number format, swaps comma-decimal/dot-grouping punctuation and then
calls `flt` (`stock/doctype/quality_inspection/quality_inspection.py:512-527`). The default API here uses
parent `__default`, not a durable observation locale (`frappe/database/database.py:1162-1180`). `flt`
removes commas and returns zero when conversion fails (`frappe/utils/data.py:1108-1145`). Consequently
original text can be reinterpreted after a default-format change, and malformed text can become 0.0
rather than an explicit parse-error fact.

### 2.3 Formula, empty set and manual disposition

Formula criteria build variables `reading_1` … `reading_10`, substitute 0.0 only for `None`, calculate
`mean` over nonempty readings and call `frappe.safe_eval`
(`stock/doctype/quality_inspection/quality_inspection.py:311-365`). Frappe normalises the expression,
blocks assignment expressions/lambdas, supplies empty builtins plus whitelisted globals and evaluates a
restricted expression (`frappe/utils/safe_exec.py:125-154`). This is safer than arbitrary Python, but
the formula text, AST/hash and evaluator version are not immutable evidence.

Formula mode has no ordinary `has_reading` guard. Ten absent numeric readings expose zero variables and
`mean=0`; therefore `mean == 0` can accept an **empty** sample even though the same empty set fails an
ordinary min/max row. The target rejects both as incomplete before evaluation.

For each non-manual child, ERPNext recalculates status from formula or value; unless parent manual mode
is set, the parent becomes Accepted unless any child says Rejected. Manual child or parent mode
suppresses those calculations, and submission requires only nonblank child statuses
(`stock/doctype/quality_inspection/quality_inspection.py:265-301`,
`stock/doctype/quality_inspection/quality_inspection.py:212-215`). A human can therefore type Accepted
without a reason, verifier signature or independent authority. In our design the automatic evaluation
is immutable evidence; a manual override is a separate signed disposition, never an edit of that result.

### 2.4 QI writes and reference timing

Saving each QI writes, in order at the domain level:

| Order | Persisted representation | Worked content | Classification |
|---:|---|---|---|
| 1 | `tabQuality Inspection` | draft parent, reference, item, sample size, inspector, template, current status | mutable attempt/projection |
| 2 | `tabQuality Inspection Reading` | four criterion snapshots and observations | intended evidence, but mutable and unversioned |
| 3 | source child `quality_inspection` | QI name, timing controlled by Stock Settings | mutable projection |
| 4 | submitted QI parent/children | `docstatus=1`, Accepted or Rejected | strongest current inspection evidence |

With blank/Warn `action_if_quality_inspection_is_not_submitted`, draft `on_update` writes the source
reference. With Stop, writeback waits until QI `on_submit`. QI cancel clears the reference; trash forces
it clear; draft discard also clears it and writes QI status Cancelled
(`stock/doctype/quality_inspection/quality_inspection.py:189-275`,
`stock/doctype/quality_inspection/quality_inspection.py:69-71`). If `child_row_reference` is absent, the
direct query can update **every same-item row** on the parent. Those child writes bypass child save hooks.

---

## 3. Purchase Receipt gate: four QI states are not equivalent

### 3.1 Invocation and exact decisions

`StockController.validate` invokes quality validation for non-return stock documents
(`controllers/stock_controller.py:40-56`, `controllers/stock_controller.py:331-334`). Purchase Receipt
uses Item flag `inspection_required_before_purchase`; the service iterates rows and then checks presence,
submission and rejection (`stock/services/quality_inspection_service.py:19-29`,
`stock/services/quality_inspection_service.py:67-149`).

For one required row:

| Link state at PR submit | Setting consulted | ERPNext result |
|---|---|---|
| **missing QI** | neither Stop/Warn field | `QualityInspectionRequiredError`; blocked |
| **linked draft QI** | `action_if_quality_inspection_is_not_submitted` | Stop throws; Warn displays orange warning and continues |
| **submitted Accepted QI** | both checks pass | continues |
| **submitted Rejected QI** | `action_if_quality_inspection_is_rejected` | Stop throws; Warn displays orange warning and continues |

The two settings default to Stop and offer Stop/Warn
(`stock/doctype/stock_settings/stock_settings.json:130-135`,
`stock/doctype/stock_settings/stock_settings.json:268-273`). A cancelled QI also has `docstatus != 1`, so
it follows the unsubmitted policy before any Rejected check. Missing is unconditionally fatal at submit
unless the separate allow-after bypass is active.

Purchase Receipt adds a narrower check: every linked QI must name this PR and the row's Item
(`stock/doctype/purchase_receipt/purchase_receipt.py:288-318`). That blocks a wholly foreign parent/item
on PR, but it still does not prove exact child row, quantity, lot/serial, direction, criterion revision
or sample. Two same-Item rows can still consume a same-parent/name-level decision incorrectly. Generic
Stock Entry has no equivalent parent/item check, and the service itself fetches only linked QI
`docstatus` and `status` (`stock/services/quality_inspection_service.py:110-149`).

### 3.2 Stop means this transaction writes nothing

First set both actions to Stop and disable allow-after. The document may already exist as a draft, but
its **submit attempt** is the unit considered here.

- Row 1 QI submitted Accepted: passes.
- Row 2 QI draft: throws before receipt `on_submit`.
- If row 2 is submitted Accepted, row 3 submitted Rejected throws instead.
- If any row has no QI, presence throws before either policy is consulted.

The failed submit transaction adds **zero** submitted Purchase Receipt state, SLE, GL, Bin quantity,
Purchase Order receipt counter, reservation movement or repost request. Existing draft PR/QI rows remain
drafts; ordinary request rollback prevents the later submit callbacks. This is the essential boundary:
Blocked submission writes no stock/accounting evidence, not a “held” stock layer.

### 3.3 Accepted replay: exact stock and GL

With QI-A/QI-B/QI-C all submitted Accepted, PR submit executes:

1. persist the submitted PR and three child rows;
2. validate authority and update Purchase Order received/status projections;
3. update PR billing/status projection;
4. create serial/batch bundles if configured (none here);
5. post stock ledger and Bin projections;
6. post GL;
7. request future repost if needed;
8. update subcontract/stock-reservation/production-plan projections when applicable (none here).

The source order is explicit in `PurchaseReceipt.on_submit`
(`stock/doctype/purchase_receipt/purchase_receipt.py:340-447`). The quality checks ran during validation,
before this sequence.

The three receipt SLEs are:

| SLE order | Item / warehouse | Actual qty | Incoming rate | `stock_value_difference` |
|---:|---|---:|---:|---:|
| 1 | RM-QA-A / Raw | +10 | 4.00 | **+40.00** |
| 2 | RM-QA-B / Raw | +5 | 6.00 | **+30.00** |
| 3 | RM-QA-C / Raw | +2 | 10.00 | **+20.00** |
| **Total** | | **+17** | | **+90.00** |

Under the stated no-tax/no-variance assumptions, the merged economic GL is:

| Account | Debit | Credit |
|---|---:|---:|
| Raw Materials Inventory | **90.00** | |
| Stock Received But Not Billed | | **90.00** |
| **Total** | **90.00** | **90.00** |

The PR composer reads each receipt SLE value, creates stock-asset and received-not-billed legs, then
processes tax/purchase-expense/regional rows
(`stock/doctype/purchase_receipt/services/gl_composer.py:13-119`). Inspection contributes **no SLE and
no GL row**. QI proves or claims inspection; PR/SLE proves receipt; GL proves the accounting recognition.

### 3.4 Warn replay: bad evidence, ordinary posting

Now link row 1 to submitted Accepted QI-A, row 2 to draft QI-B and row 3 to submitted Rejected QI-C; set
both actions to Warn. The service displays one unsubmitted warning and one rejection warning, then PR
submission performs the same ordinary sequence.

The resulting SLEs are still `+10/+40`, `+5/+30`, `+2/+20`; the GL is still `Dr Raw Inventory 90 / Cr
Stock Received But Not Billed 90`. Purchase Order received quantities and Bin actual/value projections
advance normally. No durable gate-consumption or exception row records who authorised the warnings.
The ledger is balanced, but it is **stock/accounting evidence of a warned receipt**, not inspection
evidence that rows 2 and 3 passed.

### 3.5 Allow-after is a whole-row-loop early return

The third Stock Setting defaults off
(`stock/doctype/stock_settings/stock_settings.json:479-483`). Turn it on and order PR rows as:

1. RM-QA-A, required, **no QI**;
2. RM-QA-B, required, linked draft QI;
3. RM-QA-C, required, linked submitted Rejected QI.

At row 1 the service executes `return`, not `continue`. It exits the complete validation method before
presence is checked and never visits rows 2 or 3
(`stock/services/quality_inspection_service.py:84-109`). There is no missing, draft or rejected warning.
PR posts the same 90.00 stock/GL even if both action settings are Stop. Row order is therefore policy.
Subcontracting Receipt and Stock Entry do not enter this bypass.

“Allow after” does not create or submit inspections automatically. After a submitted PR loads, the
buying controller exposes an onload flag (`controllers/buying_controller.py:79-85`). The client asks for
eligible rows and calls `make_quality_inspections`
(`public/js/controllers/transaction.js:2945-3081`). With allow-after and submitted status, the server
returns the supplied rows; creation checks only `sample_size <= accepted qty`, builds one QI per
selected row and saves each as a **draft** with company, parent, item, sample size, first serial, batch
and child-row reference (`controllers/stock_controller.py:627-692`).

Thus post-transaction chronology is:

| Order | Write | What it proves |
|---:|---|---|
| 1 | submitted PR + SLE + GL | goods/accounting already posted |
| 2 | draft QI parent/readings | an inspection attempt was later opened |
| 3 | PR child QI-name writeback under Warn/blank | mutable reference only |
| 4 | later QI submit | later inspection/disposition evidence; it did not precede stock release |

A later Rejected result does not automatically reverse or quarantine the posted stock.

---

## 4. Operation release: Job Card is its own gate

### 4.1 Activation and scope

Job Card checks QI only when **both** BOM inspection and the exact Work Order Operation quality flag are
true. It then requires `Job Card.quality_inspection`, reads that QI's status/docstatus and applies the
same two Stock Settings (`manufacturing/doctype/job_card/job_card.py:832-890`). It does not call the
stock service and does not prove QI reference, operation, Work Order, item, BOM revision, company,
quantity or sample.

QI-side automatic writeback narrows Job Card by parent name and production item, but a manually/API-
assigned QI name bypasses that path (`stock/doctype/quality_inspection/quality_inspection.py:217-231`).
So the exact weakness is stronger than PR: any named submitted Accepted QI can satisfy the gate even if
its inspection scope is unrelated.

### 4.2 Stop versus Warn and operation projections

JC-QA-0001 has `for_quantity=5`, one valid time log, `total_completed_qty=5`, loss 0 and pending 0.

With a linked **draft** QI and unsubmitted action Stop, `on_submit` calls quality validation first and
throws. The card remains draft; no submitted Job Card/time-log state is added and these Work Order
Operation projections remain unchanged:

| Projection | Before blocked submit | After blocked submit |
|---|---:|---:|
| completed qty | 0 | 0 |
| process loss | 0 | 0 |
| actual operation time/cost | 0 / 0 | 0 / 0 |
| status/dates | prior values | prior values |

Set the action to Warn and retry the **same linked draft QI**. Job Card submission continues through
material-transfer checks, card validation, Work Order update and transferred-quantity update
(`manufacturing/doctype/job_card/job_card.py:832-841`). Submitted sibling cards are aggregated and the
Work Order Operation/parent projections are rewritten. The worked result is completed 5, loss 0,
operation cost 10 and Completed operation status. There is still **no SLE and no GL**: operation
projection writes are not inventory receipt.

A submitted Accepted QI passes without warning; a submitted Rejected QI is Stop/Warn-controlled in the
same way. A missing link always throws before those settings. Cancelling the Job Card recomputes Work
Order/transferred projections but does not cancel its QI (`manufacturing/doctype/job_card/job_card.py:832-890`).

---

## 5. Inventory release: Manufacture Stock Entry is separately activated

### 5.1 The Job Card result does not activate or satisfy this gate

Stock Entry enters the quality service only when header `inspection_required=1`. For Manufacture, only
the `is_finished_item` target row is eligible; raw source rows are not inspected by this gate
(`stock/services/quality_inspection_service.py:31-82`). Therefore all four combinations exist:

| Job Card gate | Manufacture header gate | Result |
|---|---|---|
| off | off | neither operation nor output is gated |
| on | off | operation gated; FG receipt not gated |
| off | on | FG receipt gated; operation not gated |
| **on** | **on** | two decisions are required, as in this scenario |

The Job Card QI link is not reused by rule. STE-QA-MFG-0001's finished row needs its own QI name. Generic
Stock Entry checks only that name's docstatus/status, not reference parent/item/row/company/batch/serial/
quantity/criterion revision (`stock/services/quality_inspection_service.py:110-149`).

### 5.2 Stop: validation leaves no manufacture evidence

Link the FG row to submitted Rejected QI-FG-0001 and set rejected action Stop. Stock Entry validation
calls the inspection service before `on_submit` (`stock/doctype/stock_entry/stock_entry.py:309-312`). The
throw means this submit attempt writes no submitted Stock Entry, SLE, GL, FG Bin quantity, Work Order
produced/consumed counter, reservation progress, QI reference update or repost request. The already
submitted Job Card and its operation projections remain; operation completion is not inventory receipt.

### 5.3 Warn: ordinary manufacture stock and GL still post

Set rejected action Warn and retry. The warning is transient; Stock Entry proceeds. Purpose-specific
callbacks run first, then bundle/reservation updates, SLE, WIP/FG reservations, related status
projections, GL, repost/project updates and finally QI reference maintenance
(`stock/doctype/stock_entry/stock_entry.py:331-381`). Stock Entry builds all source SLEs before all
target SLEs and reverses the list on cancellation
(`stock/doctype/stock_entry/stock_entry.py:977-1120`).

Exact Warned SLEs are:

| SLE order | Item / warehouse | Qty | Incoming rate | `stock_value_difference` |
|---:|---|---:|---:|---:|
| 1 | RM-QA-A / WIP | **−5** | 0 | **−20.00** |
| 2 | RM-QA-B / WIP | **−5** | 0 | **−30.00** |
| 3 | FG-QA / Finished Goods | **+5** | 12.00 | **+60.00** |

The base composer turns each SLE value into warehouse/expense pairs; Manufacture adds the operation-cost
source (`stock/services/base_stock_gl_composer.py:27-102`,
`stock/doctype/stock_entry/services/gl_composer.py:13-48`). After clearing-account merging:

| Account | Debit | Credit |
|---|---:|---:|
| Finished Goods Inventory | **60.00** | |
| WIP Inventory | | **50.00** |
| Operation Cost source | | **10.00** |
| **Total** | **60.00** | **60.00** |

Work Order produced quantity becomes 5, consumed RM becomes 5/5, reservations/Bins refresh and the
Work Order can become Completed. These are ordinary projections over submitted stock/card evidence.
Nothing in SLE or GL says “Rejected QI was warned.” The same quantities and balances arise in the
Accepted replay; only inspection evidence differs.

### 5.4 Accepted replay and evidence separation

Replace QI-FG-0001 with an exactly scoped submitted Accepted QI. SLE and GL are numerically identical:
FG +5/+60; WIP issues −20/−30; `Dr FG 60 / Cr WIP 50 / Cr Operation 10`.

| Question | Authoritative representation in current ERPNext |
|---|---|
| What was observed? | QI reading fields, subject to mutable snapshot/locale limitations |
| What did the current QI say? | child statuses and QI Accepted/Rejected projection |
| Was the Job Card allowed? | transient validation; no durable operation-release event |
| Did the operation complete? | submitted Job Card/time log; Work Order fields are projections |
| Was FG stock received? | submitted Stock Entry Detail and FG SLE |
| What inventory value posted? | SLE `stock_value_difference`; GL mirrors it |
| Was rejection overridden? | only transient warning; no durable exception/actor/reason |

Balanced stock/GL proves accounting consistency. It cannot prove criterion completeness, exact QI scope
or authorised quality release.

---

## 6. Complete write trace, in physical business order

Counts exclude optional Version rows, serial/batch bundles, stock reservations, repost requests and
notification/cache internals. “GL” means merged economic rows under the stated accounts.

| Order | Stage | Parent/child table writes | SLE | GL | Direct/recomputed projections |
|---:|---|---|---:|---:|---|
| 1 | Save five worked QIs | 5 `tabQuality Inspection` + 20 `tabQuality Inspection Reading` | 0 | 0 | PR/JC/SE QI-name links depending on Stop/Warn timing |
| 2 | Submit Accepted/rejected QIs | the same QI parents/children become submitted | 0 | 0 | source link writes under Stop; QI current status |
| 3A | PR Stop attempt | no new submitted write | **0** | **0** | none from failed submit |
| 3B | PR Accepted or Warn | 1 `tabPurchase Receipt` + 3 `tabPurchase Receipt Item` | **3 `tabStock Ledger Entry`** | **2 `tabGL Entry`** | `tabPurchase Order Item`/PO status, PR billing/status and 3 `tabBin` rows |
| 3C | optional post-PR QIs | 1 draft `tabQuality Inspection` + 4 copied reading rows per selected line in this example | 0 | 0 | `tabPurchase Receipt Item.quality_inspection`; stock already exists |
| 4 | WIP transfer from received Raw | 1 `tabStock Entry` + 2 `tabStock Entry Detail` | **4 `tabStock Ledger Entry`** | **2 `tabGL Entry`** | transfer/reservation, Raw/WIP `tabBin` and Work Order material projections |
| 5A | Job Card Stop attempt | no new submitted write | 0 | 0 | Work Order Operation unchanged |
| 5B | Job Card Accepted or Warn | 1 `tabJob Card` + 1+ `tabJob Card Time Log` submitted | 0 | 0 | `tabWork Order Operation`/Work Order completed qty, time, cost, dates and status |
| 6A | Manufacture Stop attempt | no new submitted write | **0** | **0** | produced/consumed/Bin/QI links unchanged |
| 6B | Manufacture Accepted or Warn | 1 `tabStock Entry` + 3 `tabStock Entry Detail` + 1 `tabLanded Cost Taxes and Charges` additional-cost row | **3 `tabStock Ledger Entry`** | **3 `tabGL Entry`** | WO produced/consumed/status, reservations, WIP/FG `tabBin`, project and QI reference |

For completeness, the WIP transfer between receipt and manufacture posts source-before-target:

| SLE | Qty / SVD |
|---|---:|
| RM-QA-A / Raw | −5 / −20.00 |
| RM-QA-B / Raw | −5 / −30.00 |
| RM-QA-A / WIP | +5 / +20.00 |
| RM-QA-B / WIP | +5 / +30.00 |

Its merged GL is `Dr WIP Inventory 50 / Cr Raw Materials Inventory 50`. Across receipt, transfer and
manufacture, the economic journal is:

```text
receipt:     Dr Raw 90 / Cr Received But Not Billed 90
WIP move:    Dr WIP 50 / Cr Raw 50
manufacture: Dr FG 60 / Cr WIP 50 / Cr Operation Cost 10
ending:      Raw 40 + FG 60 = receipt liability 90 + operation source 10
```

Every debit equals every credit. RM-QA-C remains 2 kg/20 in Raw; RM-QA-A leaves 5 kg/20 there. Again,
this proof is identical under Accepted and Warn.

---

## 7. Cancellation, correction and races

### 7.1 Cancellation does not form one quality reversal

Purchase Receipt cancellation updates Purchase Order/billing projections first, reverses stock, reverses
GL, reposts and then updates downstream projections
(`stock/doctype/purchase_receipt/purchase_receipt.py:419-456`). It does not cancel its QIs. Cancelling a
QI instead clears current row references but does not reverse the receipt SLE/GL. Cancelling the PR and
cancelling the QI are independent commands.

Stock Entry cancellation runs purpose callbacks/status changes, reverses SLE, reverses GL, reposts,
updates project and then updates QI references and reservations
(`stock/doctype/stock_entry/stock_entry.py:357-393`). Job Card cancellation recomputes Work Order
projections but leaves QI alone. A submitted QI cancellation clears links that still point to it; QI
schema status is not explicitly made Cancelled by `on_cancel`, unlike draft discard.

The audit consequences are:

- cancelling/deleting a QI can erase the transaction-link projection that explained a prior release;
- cancelling stock does not reverse a typed quality-release consumption because none exists;
- a replacement/amended QI may claim the row again; and
- Warn has no durable exception to reverse at all.

### 7.2 Claim and gate races

When `child_row_reference` is absent, QI validation selects the first live same-item child with no joined
QI. There is no row lock or unique constraint
(`stock/doctype/quality_inspection/quality_inspection.py:99-128`). Two QIs can claim the same row, and
missing child identity can broaden writeback to all same-item rows.

There is likewise no owner lock spanning:

```text
read QI docstatus/status
→ decide Stop/Warn/pass
→ submit Job Card, Purchase Receipt or Stock Entry
→ write projection/SLE/GL
```

A QI can be changed/cancelled around a gate read, two attempts can preview one unclaimed row, and the
allow-after early return makes validation depend on row order. Application rollback handles an ordinary
single-request exception, but it does not serialize these cross-document decisions.

---

## 8. ERPNext versus the target owner/requirement/release/exception design

### 8.1 Target identities

The target does not put one mutable QI name on every consumer. It creates:

| Target record | Worked identity / rule |
|---|---|
| `quality_owner` | aggregate lock owner: AlphaCo + exact PR line, Work Order Operation/Job Card, or Manufacture FG detail; includes inventory owner when custody differs |
| `inspection_requirement` | owner, item, 10/5/2 kg or operation/output 5 EA, direction, lot/serial scope, approved criterion revision and required sample plan |
| `inspection_attempt` | immutable attempt number under one requirement; exactly selected sample units |
| `inspection_observation` | canonical decimal/text + original `10,20`, locale/unit, actor/time and required position |
| `inspection_evaluation` | criterion revision/hash, engine version, pass/fail/error and trace |
| `inspection_disposition` | automatic result or separately signed manual override with authority and reason |
| `quality_release` | exact Accepted release/hold for one requirement revision |
| `quality_exception` | separately authorised Warn decision: policy, actor, reason, expiry/conditions; never labelled Accepted |
| `quality_gate_consumption` | release/exception + exact PR line, Job Card operation or FG Stock Entry detail + command id |

Unique constraints permit many attempts but at most one current disposition/release per requirement
revision and one consumption per gate/source revision. The aggregate owner and requirement rows are
locked in deterministic order. Exact relational checks compare company, owner, parent/child line, item,
quantity, lot/serial, direction and criterion revision. A foreign or wrong-row Accepted QI cannot pass.

### 8.2 Target write ordering

For the Accepted receipt row, one transaction performs:

1. lock quality owner, requirement and source row;
2. verify approved immutable criterion revision and complete canonical observations;
3. append deterministic evaluations and signed disposition;
4. append exact `quality_release` and gate consumption;
5. submit PR command and append stock movement evidence;
6. append accounting evidence from stock value;
7. enqueue projectors/outbox;
8. rebuild PR link, PO counters, Bins and dashboards as projections.

For Warn, steps 2–4 do **not** fabricate acceptance. An authorised user appends a
`quality_exception`; gate consumption cites it, then the same ordinary stock/accounting steps run. A
missing exception blocks before stock writes. Cancellation appends gate/release and stock/accounting
reversals; it never deletes the evidence that once allowed posting.

For production, operation and inventory owners are separate:

```text
operation requirement → disposition → operation release/exception
  → Job Card completion evidence → Work Order operation projection

output-stock requirement → disposition → stock release/exception
  → Manufacture Detail/SLE → GL → Work Order/Bin projection
```

Observations may be reused only through an explicit compatible requirement relationship. Sharing a QI
name is not compatibility.

### 8.3 Side-by-side result

| Concern | Pinned ERPNext | Target design |
|---|---|---|
| Criterion source | mutable template; BOM helper has anomalous fallback | approved immutable revision resolved once |
| Sample | ten optional Data slots; sample size not reconciled | explicit units/positions and exact required count |
| Locale | parsed from mutable default; malformed may become zero | canonical decimal + original text/locale + parse result |
| Formula | restricted `safe_eval`, no durable AST/engine trace | constrained versioned expression and immutable trace |
| Manual result | mutable status, no required reason/authority | signed separate disposition/override |
| Missing QI | submit blocks, except allow-after return | missing release or authorised exception always blocks |
| Draft/Rejected Warn | ordinary posting, transient message | durable authorised exception, never Accepted |
| Receipt scope | PR checks parent/item, not exact full scope | FK/check constraints for exact requirement and line |
| Job Card/Stock Entry scope | name plus status/docstatus | exact operation/output gate consumption |
| Two production gates | separately activated but unconnected | separate bounded owners with explicit compatibility |
| Cancellation | mutable unlink plus independent stock reversal | append-only supersession/reversal chain |
| Concurrency | unlocked claim/check/write | owner locks, uniqueness and idempotent command IDs |

---

## 9. Invariants exercised

This scenario exercises every quality invariant from doc 39:

| Invariant | Scenario consequence |
|---|---|
| **M56 — bounded quality authority** ([doc 39 §1](../logic/39-quality-inspection-templates-readings-and-gates.md#1-twelve-parents-two-bounded-subsystems)) | QI may authorise quality only; PR/SLE/GL remain separate stock/accounting evidence. |
| **M57 — explicit quality lifecycle** ([doc 39 §2](../logic/39-quality-inspection-templates-readings-and-gates.md#2-schema-and-lifecycle)) | attempt, observation, evaluation, disposition, release, exception and reversal are typed events, not one status. |
| **M58 — criterion revision identity** ([doc 39 §3](../logic/39-quality-inspection-templates-readings-and-gates.md#3-template-construction-and-fallback)) | BOM/Item precedence resolves once to QIT-RM/FG-QA-01 revision. |
| **M59 — complete canonical sample** ([doc 39 §4](../logic/39-quality-inspection-templates-readings-and-gates.md#4-readings-110-locale-parsing-and-ordinary-criteria)) | all ten required values exist canonically; blank and malformed observations cannot silently pass. |
| **M60 — deterministic evaluation and disposition** ([doc 39 §5](../logic/39-quality-inspection-templates-readings-and-gates.md#5-formula-evaluation-and-acceptedrejected-calculation)) | formula trace is versioned; manual Accepted is separately signed. |
| **M61 — one inspection claim** ([doc 39 §6](../logic/39-quality-inspection-templates-readings-and-gates.md#6-reference-claiming-writeback-and-qi-lifecycle)) | same-item rows cannot share one current requirement claim accidentally. |
| **M62 — stock release gate** ([doc 39 §7](../logic/39-quality-inspection-templates-readings-and-gates.md#7-receipt-delivery-and-stock-entry-gates)) | every PR/Manufacture row needs exact release or durable exception; no early-return skip. |
| **M63 — operation release gate** ([doc 39 §8](../logic/39-quality-inspection-templates-readings-and-gates.md#8-job-card-is-a-separate-gate)) | Job Card completion and FG receipt consume separate decisions. |
| **M64 — versioned QM snapshots** ([doc 39 §9](../logic/39-quality-inspection-templates-readings-and-gates.md#9-quality-management-behavior-in-detail)) | any downstream non-conformance/review cites immutable source revisions. |
| **M65 — idempotent scheduled review** ([doc 39 §9](../logic/39-quality-inspection-templates-readings-and-gates.md#9-quality-management-behavior-in-detail)) | exception/rejection follow-up occurrence has one durable idempotency identity. |
| **M66 — append-only quality correction** ([doc 39 §10](../logic/39-quality-inspection-templates-readings-and-gates.md#10-cancellation-deletion-and-correction)) | QI/PR/JC/SE cancellation adds supersession/reversal; prior release is retained. |
| **M67 — evidence before quality projection** ([doc 39 §11](../logic/39-quality-inspection-templates-readings-and-gates.md#11-evidence-versus-projection)) | observations/evaluation/disposition/release precede row links, counters and dashboards. |
| **M68 — relational quality integrity** ([doc 39 §12](../logic/39-quality-inspection-templates-readings-and-gates.md#12-target-backend-and-database-model)) | requirement, sample position, current release and exact gate scope are constrained in the database. |
| **M69 — serializable quality decisions** ([doc 39 §13](../logic/39-quality-inspection-templates-readings-and-gates.md#13-defects-and-race-inventory)) | owner locks and unique consumption prevent duplicate claims and gate/cancel races. |

The central finding is precise: ERPNext can keep inventory and GL perfectly balanced while allowing a
draft or Rejected inspection through Warn, or an entire multi-row receipt through one allow-after early
return. Accounting balance proves the posting; it does not prove quality release. The target preserves
that accounting core while making complete, scoped inspection evidence—or a durable authorised
exception—a serializable prerequisite to operation and stock release.
