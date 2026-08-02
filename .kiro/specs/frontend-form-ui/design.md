# Design Document

## 1. Purpose and scope

This design describes **how the Frontend_Investigation is produced and verified**. It is not an application
design. There is no component tree, no runtime code, and no build configuration here, because the work
product of this specification is a set of Markdown documents (Requirement 1.1).

The design therefore covers five things:

| Design area | Section |
|---|---|
| Which documents exist, in what order, with what internal shape | §4, §5 |
| Which document owns which fact (UI-SPEC vs FORM-LAYOUT) | §6 |
| How a behavioural claim is established from pinned source | §7 |
| How citations, links and whitespace are mechanically verified | §8 |
| What the target contract in doc 05 / UI-SPEC / FORM-LAYOUT will *state* | §10 |

**Standing rule for this design.** Wherever this document describes a target-platform capability, it is
describing *text that a document must contain*, never software to be built. Requirement 1.3 is enforced by
construction: the only file types the implementation may create are `.md` under Owned_Paths.

Code examples use **SQL DDL sketches** (matching the notation already used by `docs/design/FINAL-SCHEMA.md`),
**EBNF** for the expression grammar, **structured pseudocode** for reconstructed algorithms, and **shell**
for the verification pipeline. No frontend language is used, because no frontend code is produced.

---

## 2. Preconditions and gates

The investigation is gated. Each gate is a hard stop: if it fails, the implementation records the failure and
does not proceed past it.

| Gate | Condition | On failure |
|---|---|---|
| **G0 — sources present** | `/projects/sandbox/frappe/frappe` and `/projects/sandbox/erpnext/erpnext` exist and are directories | Stop. Record in Notes_Register. No UI_Doc may be written, because no Citation can be read (Requirement 5.4). |
| **G1 — commits match** | `git -C /projects/sandbox/frappe rev-parse HEAD` = `5da68e856ca7f036b20d2583167b9d00c4a8db56`; `git -C /projects/sandbox/erpnext rev-parse HEAD` = `ceefd4add77715d2762c19db337fb83e28a477de` | Stop. A different commit invalidates every line number. Record the observed hashes in Notes_Register. |
| **G2 — branch** | current branch is `kiro/spec-planning` | Stop (Requirement 18.1). |
| **G3 — upstream docs present** | `docs/logic/18-metadata-and-runtime-ddl.md`, `docs/logic/19-permissions-and-access-control.md`, `docs/logic/24-reporting-framework.md`, `docs/logic/25-our-platform-spec.md`, `docs/design/FINAL-SCHEMA.md` all exist | Stop; cross-references cannot resolve (Requirement 17.8, 17.9). |
| **G4 — acceptance** | §8 pipeline reports 0 problems, `git diff --check` empty, all relative links resolve | Iterate until satisfied (Requirement 17.2). |

### 2.1 G0/G1 state at design time — a live blocker

**Both pinned source trees are absent from the workspace.** Observed:

```
$ ls -d /projects/sandbox/frappe/frappe /projects/sandbox/erpnext/erpnext
ls: cannot access '/projects/sandbox/frappe/frappe': No such file or directory
ls: cannot access '/projects/sandbox/erpnext/erpnext': No such file or directory
$ ls /projects/sandbox/
.kiro  kiroweb-erpnext-investigations-01082026
```

`docs/ui/` does not exist either and must be created. `docs/agents/NOTES-frontend.md` does not exist and must
be created (Requirement 2.7); `docs/agents/` already exists and holds only `PROMPT-frontend-form-ui.md`.

Consequence for the plan: G0 is currently **failing**, so the source-analysis documents (01–04) cannot be
started. This is a sequencing fact, not a defect in this specification. It is recorded in §13 R1 with its
mitigation, and it is the first entry the implementation must place in the Notes_Register.

---

## 3. Architecture of the work

```
                 pinned sources (read-only)
        frappe @5da68e8...            erpnext @ceefd4a...
                 │                           │
                 └──────────┬────────────────┘
                            │  read → record path:line → write claim  (§7)
             ┌──────────────┴───────────────┐
             │        source analysis       │
             │  ui/01 form+layout engine    │
             │  ui/02 child-table grid      │
             │  ui/04 list views + bulk     │
             └──────────┬───────────────────┘
                        │ 01 establishes the field/meta model
                        ▼
                ui/03 customisation + overrides
                        │
                        ▼   consolidation (01+02+03+04)
                ui/05 our frontend and form spec
                        │
                        │ normative extraction (§6)
             ┌──────────┴──────────┐
             ▼                     ▼
   design/FORM-LAYOUT.md    design/UI-SPEC.md
   (layout model, tree,     (presentation contract,
    grammar, validation,     controls, grid, formatting,
    precedence)              localisation, a11y, B/B/D)

   cross-referenced, never restated:
   logic/18 (metadata cache)  logic/19 (permissions)
   logic/24 (reports)         logic/25 (layering, B/B/D format)
   design/FINAL-SCHEMA.md (read-only storage binding)
```

---

## 4. Document architecture

### 4.1 The deliverable set

Eight files. No others (Requirement 2.8).

| # | Path | Kind | Depends on | Purpose |
|---|---|---|---|---|
| 01 | `docs/ui/01-form-rendering-and-layout-engine.md` | source analysis | sources | Runtime form construction, break→tree algorithm, `*_depends_on`, field-type→control map, precision resolution, dirty state |
| 02 | `docs/ui/02-child-table-grid-engine.md` | source analysis | sources | Grid modules, visible-column selection, `idx` maintenance, expanded row/bulk edit/paste/template, pagination vs unsaved rows, validation order, complexity at 500 rows |
| 03 | `docs/ui/03-form-customisation-and-layout-overrides.md` | source analysis | **01**, logic/18 | Customize Form writes, seven override mechanisms, precedence and merge order, scope and upgrade survival, data-not-code hazard |
| 04 | `docs/ui/04-list-view-filters-and-bulk-actions.md` | source analysis | sources, logic/19 | List settings/sidebar/group-by/saved filters, filter construction and transmission, seven alternate views, bulk failure model, `listview_settings` indicators |
| 05 | `docs/ui/05-our-frontend-and-form-spec.md` | consolidation | 01–04, logic/25, FINAL-SCHEMA | Target design narrative + build/buy/drop decisions + the UI-invariant register |
| — | `docs/design/FORM-LAYOUT.md` | normative | 05 | Layout data model, typed tree, expression grammar/AST, publish validation, precedence |
| — | `docs/design/UI-SPEC.md` | normative | 05 | Presentation contract: controls, grid, formatting/localisation, list/bulk, accessibility, B/B/D matrix |
| — | `docs/agents/NOTES-frontend.md` | register | all | Open questions; `## Requests for the backend agent` |

### 4.2 Dependency rules

1. **01, 02 and 04 are independent of each other** and may be written in any order once G0/G1 pass. 04 has the
   weakest coupling to the rest and is the natural parallel/first target if grid work stalls.
2. **03 depends on 01.** Precedence between customisation mechanisms is only expressible once 01 has fixed the
   field-definition model that those mechanisms mutate.
3. **05 depends on 01–04.** It may not introduce a target decision about a capability that no upstream document
   has analysed; each decision in 05 §build/buy/drop cites the doc that established the behaviour.
4. **UI-SPEC and FORM-LAYOUT depend on 05.** They contain no analysis and no new decisions — they are the
   normative, tabular restatement of what 05 decided. If a fact appears in UI-SPEC or FORM-LAYOUT that 05 does
   not decide, that is a defect in the extraction.
5. **Writing order is analysis → consolidation → extraction.** Extraction last means the normative documents
   never drift ahead of the evidence.

---

## 5. Fixed internal section template

Every UI_Doc uses the same skeleton (Requirement 3.1–3.8), in this order. `UI-SPEC.md` and `FORM-LAYOUT.md`
use the same skeleton minus the defect inventory (they state a target, not an analysis).

| Slot | Content | Requirement |
|---|---|---|
| **T1 Title** | `# NN — <Title>` | 3.2 |
| **T2 Pinned-source header** | blockquote naming both trees and **both commit hashes**, plus the citation-root convention | 3.1 |
| **T3 Framing paragraph** | what the document covers and what it deliberately defers to a cross-referenced doc | 8.4, 9.3 |
| **T4 Numbered sections** | `## 1.`, `## 2.`, … with `### N.M` subsections | 3.2 |
| **T5 Exact algorithms** | ordered steps and branch conditions in structured pseudocode, not prose summary | 3.3 |
| **T6 Worked examples** | ≥ 1 per mechanism section, with concrete input and resulting rendered structure | 3.4 |
| **T7 Evidence vs projection** | table separating values read from storage from values derived at render time, wherever stored state is involved | 3.5 |
| **T8 Defect and race inventory** | numbered table; **every row carries ≥ 1 Citation** | 3.6, 5.1 |
| **T9 Invariants** | `UI*` rules, one testable rule each | 4.1, 4.4, 4.6 |
| **T10 Adopt / Change / Reject matrix** | one row per analysed capability with the target decision | 3.7 |
| **T11 Cross-reference footer** | every related document by relative path | 3.8, 17.8 |

### 5.1 T2 — the exact header form

Matches the form already used by `docs/logic/18-metadata-and-runtime-ddl.md`:

```markdown
> **Presentation layer — form rendering.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.
```

### 5.2 T7 — evidence-versus-projection table form

The distinction the table must make is between a value that exists in storage and a value that exists only
because a render pass computed it. Columns are fixed:

| Value | Evidence (stored) | Projection (render-time) | Divergence risk |
|---|---|---|---|
| e.g. field precision | column type in FINAL-SCHEMA | resolved precision chain | displayed ≠ stored |

### 5.3 T10 — Adopt / Change / Reject matrix form

Three verdicts only, so the matrix is decidable. Column order is fixed:

| Upstream mechanism | Verdict | Our replacement | Citation |
|---|---|---|---|
| … | **Adopt** / **Change** / **Reject** | … | `path:line` |

In doc 05 the same rows additionally carry the **build / buy / drop** decision and the enforcement layer, in
the format of `docs/logic/25-our-platform-spec.md` (§9.1).

---

## 6. Division of labour: UI-SPEC.md vs FORM-LAYOUT.md

### 6.1 The boundary rule

> **Single-source rule.** Every normative fact lives in exactly one of `FORM-LAYOUT.md` or `UI-SPEC.md`. The
> other document references it by relative link and section number, and never restates it. A fact stated in
> both is a defect, resolved by deleting the copy in the non-owning document.

Allocation principle: **FORM-LAYOUT owns the *structure and its validation*; UI-SPEC owns *everything rendered
and everything displayed*.** If a rule can be checked at publish time against a layout revision alone, it
belongs to FORM-LAYOUT. If it needs a value, a locale, a user or a viewport, it belongs to UI-SPEC.

### 6.2 Allocation table

| Fact | Owner | Cross-referenced from | Requirement |
|---|---|---|---|
| Layout_Revision entity, scope keys (doctype, role, company), effective range, immutability | **FORM-LAYOUT** | UI-SPEC | 10.1 |
| Layout_Tree typed node schema (tab → section → column → field) | **FORM-LAYOUT** | UI-SPEC | 10.2 |
| Publish-time validation rules and rejection errors | **FORM-LAYOUT** | UI-SPEC | 10.2, 10.3 |
| Structure derived from typed tree, not break rows | **FORM-LAYOUT** | 05 | 10.4 |
| Diffable export format; upgrade-conflict resolution procedure | **FORM-LAYOUT** | UI-SPEC | 10.5 |
| Expression_Language grammar, operators, operand types | **FORM-LAYOUT** | UI-SPEC | 11.1 |
| AST representation, validation, version hash | **FORM-LAYOUT** | UI-SPEC | 11.2, 11.4 |
| Client/server evaluation-agreement requirement | **FORM-LAYOUT** | UI-SPEC | 11.3, 11.5 |
| Precedence / merge order producing a final field definition | **FORM-LAYOUT** | 03, UI-SPEC | 8.3 |
| Field-type → control mapping | **UI-SPEC** | 01 | 6.6 |
| Grid_Contract: server-driven columns, stable row identity, residual rules, row budget, virtualisation | **UI-SPEC** | FORM-LAYOUT | 12.1–12.4 |
| Keyboard-first entry; accessibility (focus order, programmatic labelling) | **UI-SPEC** | — | 12.5, 12.6 |
| Formatting_Contract: purity, canonical numeric types, enum codes and label resolution | **UI-SPEC** | FINAL-SCHEMA (read-only) | 13.1–13.3 |
| Server-authoritative field permission; client as cache | **UI-SPEC** | logic/19 | 11.6 |
| List, filter and bulk-action target behaviour | **UI-SPEC** | 04 | 9.x |
| Tax_Regime localised field sets; GST layout concerns; jurisdiction variation | **UI-SPEC** | FORM-LAYOUT | 14.1–14.3, 14.5 |
| `@allow_regional` exclusion | **UI-SPEC** (B/B/D matrix) | 05 | 14.4 |
| Enforcement-layer assignment per guarantee | **UI-SPEC** | logic/25 §2 | 15.2 |
| `layout_revision` / `layout_node` table definitions (presentation-metadata storage) | **FORM-LAYOUT** | UI-SPEC, 05 | 15.4 |
| Storage binding table, **business-data** rows (layout field → FINAL-SCHEMA table.column) | **UI-SPEC** | FORM-LAYOUT | 15.5 |
| Storage binding table, **presentation-metadata** rows (layout field → FORM-LAYOUT table.column) | **UI-SPEC** | FORM-LAYOUT | 15.6 |
| RLS `company_id` scoping of layout queries | **UI-SPEC** | logic/19 | 15.9 |
| Build / buy / drop matrix | **UI-SPEC** | 05 | 15.1 |

Boundary cases decided explicitly, so they are not re-litigated:

- **Expression grammar vs expression *semantics of a control*.** Grammar and AST → FORM-LAYOUT. What a
  `read_only` result does to a rendered control → UI-SPEC.
- **Grid column *set* vs grid column *layout node*.** A child-table field's position in the tree →
  FORM-LAYOUT. Which columns the server exposes and their widths → UI-SPEC.
- **Precision.** The canonical storage type → UI-SPEC Formatting_Contract (with the binding to FINAL-SCHEMA).
  A field node's declared display precision → FORM-LAYOUT node schema, referencing UI-SPEC for resolution.
- **Table *definition* vs binding *row*.** The DDL for `layout_revision` and `layout_node` → FORM-LAYOUT
  (Requirement 15.4). The single binding table that maps each layout field to a table and column — whichever
  document defines that table — → UI-SPEC (Requirements 15.5, 15.6, §10.5). FORM-LAYOUT therefore owns the
  definitions and UI-SPEC owns the bindings, which keeps the single-source rule intact for both kinds.

---

## 7. Investigation method

### 7.1 Reading order through the pinned sources

Reading is breadth-first per document, deepest on the modules that own an algorithm.

| Doc | Read order |
|---|---|
| 01 | `frappe/public/js/frappe/views/formview.js` (`frappe.views.FormFactory`, the construction entry point) → `frappe/public/js/frappe/form/form.js` → `layout.js` → `section.js`, `column.js`, `tab.js` → `controls/base_control.js` → `controls/` per field type → `frappe/model/meta.js` and the `Meta` shape established by logic/18 → precision/format helpers |
| 02 | `frappe/public/js/frappe/form/grid.js` → `grid_row.js` → `grid_row_form.js` → `grid_pagination.js` → paste/template handlers → child-row validation path into `frappe/model/` |
| 03 | `frappe/custom/doctype/customize_form/` → `custom_field/`, `property_setter/` → `doctype_layout/`, `workspace/`, `form_tour/`, `client_script/`, `custom_html_block/` → merge points in metadata assembly (**cross-reference logic/18, do not re-derive**) |
| 04 | `frappe/public/js/frappe/list/` (`list_view.js`, `list_sidebar*`, `list_settings`, filter area) → `frappe/public/js/frappe/views/` for Kanban/Calendar/Gantt/Tree/Image/Map/Dashboard → bulk action handlers → `listview_settings` consumers in erpnext |
| 05 | no source reading; reads 01–04, logic/25 §2–§3, FINAL-SCHEMA |

Where an ERPNext-side behaviour is involved (regional field sets, `listview_settings` overrides), erpnext is
read second and cited without the `frappe/` prefix.

Every unit name is checked against the pinned tree **before** it enters a reading order, because a name that
does not exist upstream would otherwise have to be recorded as an absence finding (Requirement 6.9). The two
names this design previously carried were wrong and are corrected above:

| Named unit | Status at the pinned commits | Evidence |
|---|---|---|
| `frappe.views.FormFactory` | present; the point at which the form is constructed (Requirement 6.1) | `frappe/public/js/frappe/views/formview.js:6` |
| `frappe/public/js/frappe/form/tab.js` | present; the `Tab` unit named by Requirement 6.1 | file present at the pinned commit |
| `form_page` | **absent** — no `form_page*` module exists under `frappe/public/js/frappe/`; `tab.js` is the unit | no line number, per Requirement 5.5 |
| `grid_form.js` | **absent** — the expanded-row module is `grid_row_form.js` (Requirement 7.1) | no line number, per Requirement 5.5 |

### 7.2 Claim protocol

A Behavioural_Claim is produced by this sequence, and only this sequence:

```
1. Locate the construct in the pinned tree.
2. Read the enclosing block; note the file path relative to the app root
   and the 1-based line number(s) of the lines actually read.
3. Write the claim as a statement of what the code does.
4. Attach the citation to the claim in the same sentence or table row.
5. If step 2 produced no line, go to §7.4 (absence), not to a claim.
```

Rules:

- **No claim without a read line** (Requirement 5.4). A claim whose citation was inferred from a document,
  a memory, or a search-result summary is not admissible.
- **Line numbers are recorded at read time**, in the same working pass that writes the claim. Recording a
  number and re-reading later at a different commit is the citation-drift risk in §13 R2.
- **One claim, one mechanism.** Compound claims are split so each half carries its own citation.

### 7.3 Algorithm reconstruction

Requirement 3.3 requires the exact algorithm rather than a summary. Method:

1. Identify the entry function and the terminal state.
2. Transcribe the control flow into numbered steps, preserving **order of operations** and **branch
   conditions** verbatim in meaning.
3. Annotate each step with a shorthand citation (`:NNN`) resolving against the file cited in full earlier in
   the section — the form `verify_refs.py` recognises (§8.3).
4. Add a worked example that runs concrete input through the numbered steps.

Template:

```
Algorithm A-01-2: Meta.fields → visual tree
  1. state: current_tab ← implicit tab 0; current_section ← implicit; current_column ← implicit   (:NNN)
  2. for each field in Meta.fields, in stored order:                                             (:NNN)
     2a. if fieldtype = 'Tab Break'    → close section/column, open tab                          (:NNN)
     2b. if fieldtype = 'Section Break'→ close column, open section                              (:NNN)
     2c. if fieldtype = 'Column Break' → open column in current section                          (:NNN)
     2d. otherwise                     → append control to current column                        (:NNN)
  3. malformed input: <exact observed structure, per Requirement 6.3>                             (:NNN)
```

### 7.4 Absence, dead code and unreachable code

These are findings, not gaps (Requirement 5.5, 5.6). Fixed recording form, in the defect inventory:

| Finding kind | Recorded as | Line number |
|---|---|---|
| Behaviour expected but not present | `**Absent.** <what was searched for and where>` + Citation to the **nearest related code** | **omitted** for the absent behaviour |
| Code present but unreachable | `**Unreachable.** <why>` + Citation to the guard that excludes it | present, cites the guard |
| Code present but unfinished (stub, TODO, always-false branch) | `**Unfinished.** <observed state>` + Citation | present |

No UI_Doc may contain a fabricated line number for an absent behaviour. This is the one rule that the
verifier cannot catch for `.js` files (§8.4), so it is also a review instruction.

### 7.5 Cross-reference instead of restatement

| Topic | Owning document | Permitted in a UI_Doc |
|---|---|---|
| Metadata assembly, `Meta` cache behaviour, runtime DDL | `docs/logic/18-metadata-and-runtime-ddl.md` | a one-sentence statement of the *consequence* for layout, plus a link (Requirement 8.4) |
| Permission and sharing evaluation | `docs/logic/19-permissions-and-access-control.md` | the **join point** where permission filtering combines with user filters (Requirement 9.3) |
| Report views, dashboards, print | `docs/logic/24-reporting-framework.md` | link only |
| Layering rule, build/buy/drop format | `docs/logic/25-our-platform-spec.md` §2, §3 | link + reuse of the format |
| Target storage | `docs/design/FINAL-SCHEMA.md` | **read-only**; cite table and column names, never propose edits |

---

## 8. Citation and verification pipeline

### 8.1 Citation conventions

| Tree | Citation root | Written form | Example |
|---|---|---|---|
| frappe | `/projects/sandbox/frappe/frappe` | prefixed `frappe/` | `frappe/public/js/frappe/form/grid.js:412` |
| erpnext | `/projects/sandbox/erpnext/erpnext` | no prefix | `accounts/doctype/sales_invoice/sales_invoice.py:562` |

Requirements 5.2, 5.3. A range is written `path:start-end`.

### 8.2 The verification command

Run from the repository root:

```bash
python3 tools/verify_refs.py --docs docs/ui \
  --app erpnext=/projects/sandbox/erpnext/erpnext \
  --app frappe=/projects/sandbox/frappe/frappe --strict-names
```

Acceptance is the literal line `0 problems` in the summary (Requirement 17.1).

### 8.3 What the tool actually validates

Read from `tools/verify_refs.py`. Stating this precisely matters, because citations must be written in a form
the tool recognises.

| Aspect | Behaviour |
|---|---|
| Citation regex | `([A-Za-z_][\w/]*(?:/[\w/]+)*\.py):(\d+)(?:-(\d+))?` — **`.py` only** |
| Shorthand forms accepted | backticked `` `:568` ``; prose `(:2434)` or `, :1008-1195` (must follow `(` or `,`); inside a fenced block, `# :709` |
| Anchor retargeting | a backticked path with no line number (`` `stock/reorder_item.py` ``) resets which file later shorthand refs resolve against |
| Shorthand resolution | against files the *same document* cites; prefers the candidate whose enclosing `def`/`class` matches a backticked identifier on the same or previous doc line (`name`), else nearest cited file (`anchor`), else sole in-range candidate (`only`); otherwise reported `AMBIGUOUS` |
| Path resolution | app root join, app-prefix strip, or unique basename suffix match (test/regional paths de-preferred) |
| Range check | line ≤ file length, else `OUT OF RANGE` |
| `--strict-names` | for **full** citations only: if the doc line backticks an identifier that exists in the file, the symbol enclosing the cited line must match, else `NAME NOTE` |
| Symbol index | built with Python `ast` — inherently Python-only |
| Exit status | non-zero if any unresolved / out-of-range / ambiguous citation |

### 8.4 Finding: the tool cannot verify `.js` citations

This investigation cites `frappe/public/js/frappe/form/**` and `frappe/public/js/frappe/list/**` — almost
entirely JavaScript. The citation regex requires `.py`, so **`.js` citations are not seen by the tool at all**.
Confirmed empirically against a scratch fixture:

```
docs line: cites `…/form/grid.js:2`     → not counted
docs line: cites `…/form/grid.js:9999`  → not counted, not reported
docs line: cites `api.py:2`             → counted, symbol resolved
docs line: cites `api.py:500`           → OUT OF RANGE
summary:   2 citations verified … 1 problems
```

Consequence: Requirement 17.1 is satisfiable **vacuously** for the majority of this investigation's citations.
Requirement 17.4 now states that conclusion normatively — a `0 problems` report is **necessary and
insufficient** evidence of Citation correctness — so what follows is a requirement-mandated obligation, not a
design mitigation the implementation may weigh against cost. Requirement 17.3 additionally requires the
`.py`-only scope to be recorded in the Notes_Register, citing the mandatory `.py` extension of the citation
pattern at `tools/verify_refs.py:35` and the Python-only symbol index built with `ast.parse` at
`tools/verify_refs.py:62`.

Design response — three parts, none of which touches `tools/**` (a Restricted_Path):

1. **Run the tool anyway, with `--strict-names`.** It fully verifies every `.py` citation (customise-form
   doctypes, erpnext `listview_settings` consumers, controllers) and must report `0 problems`.
2. **Perform the read-back check for non-`.py` citations** (V4 below) — **mandated by Requirements 17.5 and
   17.6.** Every `.js`/`.json`/`.vue` citation is re-read from the pinned tree at its cited line and confirmed
   to contain the construct the claim names (17.5); a Citation the re-read does not confirm is corrected or
   removed **before the acceptance gate passes** (17.6). This uses read-only shell commands only and creates
   no files.
3. **Record the scope, and request the tool extension, in the Notes_Register.** The `.py`-only scope note
   required by Requirement 17.3, with both citations (`tools/verify_refs.py:35`, `:62`); and, under
   `## Requests for the backend agent`, extend `CITATION` to non-Python extensions and gate `--strict-names`
   on a Python-only symbol index. The frontend agent does not edit `tools/**` (Requirement 16.2), so the
   read-back check in part 2 is the standing substitute rather than something the request unblocks.

### 8.5 The acceptance loop

```
V1  python3 tools/verify_refs.py --docs docs/ui --app … --strict-names   → "0 problems"
V2  git diff --check                                                     → no output
V3  every relative markdown link in docs/ui/**, docs/design/UI-SPEC.md,
    docs/design/FORM-LAYOUT.md, docs/agents/NOTES-frontend.md resolves    → all resolve
V4  every non-.py citation re-read at its cited line in the pinned tree   → construct present
V5  git diff --name-only ⊆ Owned_Paths                                    → true
V6  UI-invariant identifier set == {UI1..UIn}, no gaps, no duplicates      → true
```

Loop rule (Requirement 17.2): on any failure, correct the affected Citations or links and **re-run from V1**.
The loop terminates only when V1–V6 all pass. Partial acceptance is not recognised.

Each check is mandated by a requirement; none is optional, and V4 in particular is normative rather than a
mitigation of the §8.4 finding:

| Check | Mandated by |
|---|---|
| V1, re-run until the report states `0 problems` | 17.1, 17.2 |
| V2 | 17.7 |
| V3 | 17.8, 17.9 |
| V4, including correction or removal of any unconfirmed Citation | 17.4, 17.5, 17.6 |
| V5 | 16.1, 18.3 |
| V6 | 4.2 |

V3 target set for Requirement 17.9 — reference these exact filenames, which exist on this branch:

| Reference | Status |
|---|---|
| `docs/logic/18-metadata-and-runtime-ddl.md` | exists |
| `docs/logic/19-permissions-and-access-control.md` | exists |
| `docs/logic/24-reporting-framework.md` | exists |
| `docs/logic/25-our-platform-spec.md` | exists |
| `docs/design/FINAL-SCHEMA.md` | exists (read-only) |

The names used in `docs/agents/PROMPT-frontend-form-ui.md` for the first three
(`18-metadata-and-doctype-engine.md`, `19-permissions-and-sharing.md`,
`24-reports-dashboards-and-print.md`) are **stale and must not be linked**.

---

## 9. Invariant register design

### 9.1 Namespace

Requirement 4.1–4.4: prefix **`UI`** followed by an integer, consecutive from **`UI1`**, no duplicates within
the UI_Doc set, and no reuse of any reserved identifier or prefix:

| Reserved | Owner | Why it is unavailable |
|---|---|---|
| `M1`–`M69` | production documents | Requirement 4.3 |
| `A1`–`A26` | asset documents | Requirement 4.3 |
| `F`, `T`, `R`, `V` | trade documents | Requirement 4.3 |
| **`U`** | trade register and the schema register | Requirement 4.3; already occupied twice — see §9.2 |

`UI` is used for **every** Invariant the Frontend_Investigation introduces (Requirement 4.4); no UI invariant
carries a bare `U` number.

Allocation is by **block, assigned before writing**, so two documents cannot claim the same number:

| Document | Block | Rule |
|---|---|---|
| 01 form rendering and layout | `UI1` – `UI9` | allocate upward from `UI1`; unused numbers in a block are **left unused, not reclaimed** |
| 02 child-table grid | `UI10` – `UI19` | |
| 03 customisation and overrides | `UI20` – `UI27` | |
| 04 list views and bulk actions | `UI28` – `UI34` | |
| 05 target spec (new invariants only) | `UI35` – `UI44` | 05 restates 01–04 invariants by reference, never renumbers them |

Consecutiveness (Requirement 4.2) is reconciled at the end of the investigation: after all five documents are
written, the register in doc 05 renumbers **once** into a gap-free `UI1..UIn` sequence and every reference is
updated in the same commit. V6 in §8.5 is the check. Renumbering before doc 05 is written is forbidden,
because it invalidates already-written cross-references.

The authoritative register is a single table in `docs/ui/05-our-frontend-and-form-spec.md`, mirrored (by
reference, not by copy) from `docs/design/UI-SPEC.md`:

| # | Invariant | Enforcement layer | Established in |
|---|---|---|---|
| UI1 | … | L1 / L2 / L3 / L4 (per logic/25 §2) | `01` §N |

### 9.2 Resolved finding: `U` was already taken, so `U` is now reserved

The prefix `U` is occupied on this branch, twice and independently:

| Existing use | Citation | Range |
|---|---|---|
| Upstream trade and parties invariants | `docs/logic/30-upstream-trade-and-parties.md:942-956` (§11.5) | `U1` – `U8` |
| UOM invariant in the schema register | `docs/design/FINAL-SCHEMA.md:734` (§9) | `U1` |

`U7` in the trade register is the "no enum column contains a translated string" invariant — the one this
investigation's own formatting work would otherwise want to reference — so a bare `U` number in a UI_Doc
would be genuinely ambiguous, not merely untidy.

**This was fixed at source, not worked around.** Requirement 4 now mandates the prefix `UI` and reserves `U`
alongside `M`, `A`, `F`, `T`, `R` and `V`. Because the namespaces no longer overlap, the containment
machinery an overlapping namespace would have required — qualifying every invariant on first use, a request
to the backend agent to split the `U` range — is unnecessary and is not part of this design. **Nothing
changes** in `docs/logic/**` or in `docs/design/FINAL-SCHEMA.md`, which is the point: the collision is
resolved entirely inside Owned_Paths, with no edit to a Restricted_Path (Requirement 16.2).

The originating prompt, `docs/agents/PROMPT-frontend-form-ui.md`, still instructs a `U` prefix starting at
`U1`. That is a deviation, and Requirement 4.5 requires it to be recorded: the Notes_Register carries an entry
under `## Open questions` stating the prompt's instruction, the two citations above as evidence that `U` is
already in use, and the collision-avoidance rationale for `UI`. It is a note in an Owned file, not a request
against a Restricted_Path (§11.2).

### 9.3 Invariant form

One testable rule per invariant, violation observable (Requirement 4.6). Accepted shapes: an equality, an
inequality, a uniqueness statement, a totality statement ("every X has exactly one Y"), or a
purity/determinism statement. Rejected shapes: aspirations ("layouts should be maintainable"), and any rule
whose violation cannot be observed from data or from a rendered result.

Requirement 13.5 is discharged by a numbered invariant in doc 05 of the form: *stored value and displayed text
are distinct; no stored field ever holds formatted or translated text.*

---

## 10. Target contract shape

This section fixes the **structures** that doc 05, `FORM-LAYOUT.md` and `UI-SPEC.md` will state. The notation
is SQL-DDL sketch and EBNF, matching FINAL-SCHEMA's style. Nothing here is built; all of it is written.

### 10.1 Layout revisions (FORM-LAYOUT)

```
layout_revision(
  id                uuid PK,
  doctype_key       text NOT NULL,           -- logical entity, not a tabDocType row
  role_id           uuid NULL,               -- NULL = all roles
  company_id        uuid NULL,               -- NULL = all companies; RLS-scoped when set
  jurisdiction_code text NULL,               -- Tax_Regime scope (§10.6)
  revision_no       integer NOT NULL,
  status            layout_status_enum,      -- draft | approved | superseded
  effective_from    date NOT NULL,
  effective_to      date NULL,               -- exclusive; NULL = open
  tree_hash         text NOT NULL,           -- content hash of the typed tree
  expr_version_hash text NOT NULL,           -- §10.3
  approved_at       timestamptz NULL,
  approved_by       uuid NULL,
  UNIQUE (doctype_key, role_id, company_id, jurisdiction_code, revision_no)
)
```

**Lineage of this table (Requirement 15.4).** `layout_revision` — and `layout_node` in §10.2 — is the concrete
form of the `ui_field` / `ui_layout` capability that `docs/logic/25-our-platform-spec.md` §3.1 records as
**BUILD**, "describes rendering only; cannot affect storage" (`docs/logic/25-our-platform-spec.md:79`; the same
capability is listed again among the permitted admin surfaces at `:259`).

| Fact | Evidence | Consequence |
|---|---|---|
| Doc 25 commits to building `ui_field` / `ui_layout` at L4 | `docs/logic/25-our-platform-spec.md:79` | the capability is decided; only its concrete shape is open |
| `docs/design/FINAL-SCHEMA.md` defines no `ui_field`, `ui_layout`, `layout_revision` or `layout_node` | search of that file for all four names returns no match | the specification of both tables **originates in `FORM-LAYOUT.md`** |
| FINAL-SCHEMA is read-only for this investigation | Requirement 15.7, §11.1 | the tables are specified, never added to FINAL-SCHEMA |
| The divergence is registered, not hidden | Requirement 15.8, §11.2 | the Notes_Register names it, pending backend confirmation |

Stated rules:

| Rule | Statement | Requirement |
|---|---|---|
| L-1 | `status = 'approved'` ⇒ the row and its tree are immutable; a change is a **new revision** | 10.1 |
| L-2 | Scope is (doctype, role, company); jurisdiction is an additional scope key | 10.1, 14.3 |
| L-3 | Effective ranges for one scope tuple do not overlap | 10.1 |
| L-4 | Resolution for a document picks the single revision whose scope matches most specifically and whose range contains the document date; ties are a publish-time error, not a runtime tiebreak | 10.1 |
| L-5 | The doctype definition is single-sourced; jurisdiction variation is a *revision*, never a forked doctype | 14.3 |

### 10.2 Typed layout tree (FORM-LAYOUT)

```
layout_node(
  id            uuid PK,
  revision_id   uuid NOT NULL REFERENCES layout_revision,
  parent_id     uuid NULL REFERENCES layout_node,
  node_kind     layout_node_kind_enum,   -- tab | section | column | field
  ordinal       integer NOT NULL,
  field_key     text NULL,               -- required iff node_kind = 'field'
  label_key     text NULL,               -- translation key, never translated text
  display_precision smallint NULL,
  visible_expr_id   uuid NULL REFERENCES layout_expression,
  mandatory_expr_id uuid NULL,
  readonly_expr_id  uuid NULL,
  collapsible_expr_id uuid NULL,
  UNIQUE (revision_id, parent_id, ordinal)
)
```

`layout_node` carries the same lineage as `layout_revision` (§10.1): it is the `ui_layout` half of doc 25
§3.1's **BUILD** decision (`docs/logic/25-our-platform-spec.md:79`), specified in `FORM-LAYOUT.md` because
`docs/design/FINAL-SCHEMA.md` defines no such table (Requirement 15.4), with the divergence recorded under
Requirement 15.8. It is presentation metadata only and has no effect on stored business schema
(Requirement 15.3, rule E-3 in §10.7).

Publish-time validation (Requirement 10.2, 10.3). Every rule below yields an **identified error code** and
rejects the whole revision:

| Code | Rule |
|---|---|
| `LT-KIND` | Parent/child kinds satisfy tab→section→section→column→column→field; no other pairing |
| `LT-ROOT` | Exactly one root per revision, `node_kind = 'tab'` |
| `LT-ACYCLIC` | The parent relation is acyclic |
| `LT-ORDINAL` | Ordinals within a parent are gap-free from 0 |
| `LT-FIELD` | `field_key` present iff `node_kind = 'field'`, and resolves to a known field for the doctype |
| `LT-DUP` | A `field_key` appears at most once per revision |
| `LT-BIND-BUS` | Every `field_key` bound to **business data** names an existing `docs/design/FINAL-SCHEMA.md` table and column (§10.5, Requirement 15.5) |
| `LT-BIND-META` | Every `field_key` stored as **presentation metadata** names an existing `layout_revision` or `layout_node` column as defined in `FORM-LAYOUT.md` (§10.1, §10.2, §10.5, Requirement 15.6) |
| `LT-EXPR` | Every referenced expression validates (§10.3) |
| `LT-LABEL` | `label_key` is a key, not display text |

**Structure is derived from the typed tree, never from ordered break rows** (Requirement 10.4). Upstream's
`Tab Break` / `Section Break` / `Column Break` sentinel rows are analysed in doc 01 and appear in the
Adopt/Change/Reject matrix as **Reject**, because a malformed break sequence is unrepresentable in this model
rather than merely discouraged.

Export (Requirement 10.5): a canonically-ordered textual serialisation (one node per line, stable key order),
held in version control, with `tree_hash` over the canonical form. Upgrade conflict between an exported
revision and an incoming platform version is resolved by a stated procedure — the incoming version's field
set is authoritative, removed fields are reported as rejections against the exported revision, and the
revision is re-approved as a new `revision_no` rather than edited in place.

### 10.3 Expression language (FORM-LAYOUT)

```
layout_expression(
  id uuid PK, source text NOT NULL, ast jsonb NOT NULL,
  grammar_version text NOT NULL, version_hash text NOT NULL
)
```

Grammar shape (the document states the full EBNF; this is the fixed skeleton):

```ebnf
expr        = or_expr ;
or_expr     = and_expr { "or" and_expr } ;
and_expr    = not_expr { "and" not_expr } ;
not_expr    = [ "not" ] comparison ;
comparison  = operand rel_op operand | operand "in" list | operand ;
rel_op      = "=" | "!=" | "<" | "<=" | ">" | ">=" ;
operand     = field_ref | literal ;
field_ref   = ident { "." ident } ;          (* document values only *)
literal     = number | string | boolean | null ;
list        = "[" [ literal { "," literal } ] "]" ;
```

Stated rules:

| Rule | Statement | Requirement |
|---|---|---|
| X-1 | Permitted operators and operand types are exactly those in the grammar; there is no function call, no assignment, no arithmetic on document state beyond declared operators | 11.1 |
| X-2 | Every expression parses to a validated AST carrying `version_hash` = hash(canonical AST + `grammar_version`) | 11.2 |
| X-3 | For the same AST, the same document values and the same `version_hash`, client and server evaluation return the same result | 11.3 |
| X-4 | Validation failure ⇒ the containing Layout_Revision is rejected at publish time with an identified error | 11.4 |
| X-5 | Evaluation is by a parser/interpreter over the validated AST. **Dynamic evaluation of user-supplied text is excluded from the design** — there is no `eval` path, on either side | 11.5 |
| X-6 | Field-level permission and visibility are resolved **server-authoritatively**; the client holds a cache of the server decision and never widens it | 11.6 |

Doc 01 records, with citations, how upstream `depends_on`, `mandatory_depends_on`, `read_only_depends_on` and
`collapsible_depends_on` are evaluated, in what scope, and what happens when they throw (Requirement 6.4);
X-1…X-5 are the target replacement, entered in the Adopt/Change/Reject matrix.

### 10.4 Grid contract (UI-SPEC)

| Rule | Statement | Requirement |
|---|---|---|
| G-1 | Column sets per child table are **server-driven**; the client does not choose the column set | 12.1 |
| G-2 | Row identity is a stable identifier (`line_id uuid`) **independent of `idx`**; ordering is a separate `line_no` | 12.2 |
| G-3 | Each computed column states its **residual rule**: which side owns the value, and when it is recomputed | 12.3 |
| G-4 | A numeric row-count budget is stated; **above the budget rendering is virtualised** | 12.4 |
| G-5 | Row creation, field entry, row navigation and row deletion are completable by keyboard alone | 12.5 |
| G-6 | Focus order is defined, and every editable cell is programmatically labelled | 12.6 |

G-2 is the direct answer to doc 02's `idx`-maintenance findings (Requirement 7.3): renumbering on delete
cannot invalidate a reference that never pointed at `idx`. G-4 is the answer to the 500-row and O(n²) analysis
(Requirement 7.7).

### 10.5 Formatting contract (UI-SPEC)

| Rule | Statement | Requirement |
|---|---|---|
| F-1 | `display(value, locale, precision)` is a **pure function**; identical inputs give identical output, with no dependence on session or ambient state | 13.1 |
| F-2 | Canonical storage types: money `numeric(19,4)`, quantity and rate `numeric(21,9)`, percent `numeric(9,6)` | 13.2 |
| F-3 | Enumerations are stored as **stable lower-case codes**; the display label is resolved at read time from the code | 13.3 |
| F-4 | A design that writes a formatted or translated string to a stored field is **rejected**, and the rejection is recorded in the Adopt/Change/Reject matrix | 13.4 |
| F-5 | The separation of stored value from displayed text is a numbered `UI*` invariant in doc 05 | 13.5 |

Binding table form (Requirements 15.5, 15.6) — one table in UI-SPEC carries **both** binding kinds, and every
row names the document that defines the table it binds to. `FINAL-SCHEMA.md` is read-only and only referenced
(Requirement 15.7):

| Layout field key | Binding kind | Defining document | Table | Column | Canonical type | Display precision source |
|---|---|---|---|---|---|---|
| … | **business data** | `docs/design/FINAL-SCHEMA.md` (read-only) | … | … | `numeric(19,4)` | field node / currency minor unit |
| … | **presentation metadata** | `docs/design/FORM-LAYOUT.md` (specified per §10.1, §10.2) | `layout_node` | `display_precision` | `smallint` | — |

Stated rules:

| Rule | Statement | Requirement |
|---|---|---|
| B-1 | Binding kind is one of exactly two values — business data or presentation metadata — and every bound layout field declares one | 15.5, 15.6 |
| B-2 | A **business-data** row names a table and column defined in `docs/design/FINAL-SCHEMA.md`; the name is cited, never proposed, and FINAL-SCHEMA is left unchanged | 15.5, 15.7 |
| B-3 | A **presentation-metadata** row names a `layout_revision` or `layout_node` column defined in `docs/design/FORM-LAYOUT.md` | 15.4, 15.6 |
| B-4 | A name absent from its declared defining document fails publish validation (`LT-BIND-BUS`, `LT-BIND-META` in §10.2); no row binds one field to both documents | 15.5, 15.6 |

F-1/F-2 are also the target answer to doc 01's precision-resolution chain (Requirement 6.7): the chain is
analysed upstream and **rejected** in favour of a type in the column, consistent with
`docs/logic/25-our-platform-spec.md` §3.1 (precision: DROP metadata-resolved precision).

### 10.6 Localisation and GST (UI-SPEC)

| Rule | Statement | Requirement |
|---|---|---|
| J-1 | Layout supports HSN and SAC codes, place of supply, GSTIN, reverse-charge indication, and the CGST/SGST/IGST/cess breakdown display | 14.1 |
| J-2 | The localised field set and localised labels are selected from the **Tax_Regime associated with the document company** | 14.2 |
| J-3 | With more than one Tax_Regime configured, the Layout_Revision varies by jurisdiction while the doctype definition stays single-sourced | 14.3 |
| J-4 | ERPNext's `@allow_regional` whole-function override is **excluded** from the target design, recorded in the Adopt/Change/Reject matrix with a Citation to the upstream mechanism | 14.4 |
| J-5 | Regional behaviour derives from the **company identifier carried by the document**, never from a session default | 14.5 |

J-4 aligns with the backend position already recorded in `docs/design/FINAL-SCHEMA.md` §24 and
`docs/logic/21-extensibility-hooks-and-regional.md`; the UI_Doc cites the upstream decorator itself rather
than relying on those documents for the Citation.

### 10.7 Layering and decision format (doc 05, UI-SPEC)

| Rule | Statement | Requirement |
|---|---|---|
| E-1 | Each analysed presentation capability carries a **build / buy / drop** decision in the format of `docs/logic/25-our-platform-spec.md` | 15.1 |
| E-2 | Each guarantee is assigned to the **lowest enforcement layer that can enforce it without cooperation from a caller** (L1 schema, L2 triggers/RLS, L3 orchestration, L4 service code) | 15.2 |
| E-3 | Presentation metadata governs rendering only and **cannot affect stored schema** | 15.3 |
| E-4a | Every layout field bound to **business data** states its `docs/design/FINAL-SCHEMA.md` table and column; FINAL-SCHEMA is read-only and left unchanged | 15.5, 15.7 |
| E-4b | Every layout field stored as **presentation metadata** states its `layout_revision` or `layout_node` table and column as defined in `docs/design/FORM-LAYOUT.md`, which specifies both tables as the concrete form of doc 25 §3.1's `ui_field` / `ui_layout` **BUILD** decision (`docs/logic/25-our-platform-spec.md:79`), with the divergence from FINAL-SCHEMA recorded in the Notes_Register | 15.4, 15.6, 15.8 |
| E-5 | Every layout query that reads a business table is **RLS-scoped by `company_id`** | 15.9 |
| E-6 | Content is expressed as tables, an expression grammar and precedence rules; prose is never the sole statement of a rule | 15.10 |

Decision-table column order, matching doc 25 §3:

| Capability | Decision | Where |
|---|---|---|
| … | **BUILD** / **BUY** / **DROP** | L1 / L2 / L3 / L4 / build step / — |

**Note on a resolved cross-reference.** Requirement 15.1 now cites `docs/logic/25-our-platform-spec.md`
**section 3** for the build/buy/drop format, which is where that format lives on this branch —
`## 3. Build / buy / drop, by capability` at `docs/logic/25-our-platform-spec.md:66`, with the capability
tables in §3.1–§3.7; §6, "Cost of leaving Frappe — honest accounting", is at `:292` and contains no decision
table. The earlier discrepancy (the requirement citing §6) is therefore **resolved in the requirement itself**:
no request against `docs/logic/**` remains, and the Notes_Register records the point as closed rather than
outstanding (§11.2).

E-3 aligns with doc 25 §3.1's `ui_field` / `ui_layout` entry ("describes rendering only; cannot affect
storage", `docs/logic/25-our-platform-spec.md:79`), which the target contract refines rather than contradicts:
E-4b gives that entry its concrete tables, and E-3 keeps them confined to rendering.

---

## 11. Concurrency and file ownership

### 11.1 Path lists

| Class | Paths |
|---|---|
| **Owned** (create/edit freely) | `docs/ui/**`; `docs/design/UI-SPEC.md`; `docs/design/FORM-LAYOUT.md`; `.kiro/specs/frontend-*/**`; `docs/agents/NOTES-frontend.md` |
| **Restricted** (never create, edit, move, rename, delete) | `docs/logic/**`; `docs/scenarios/**`; `docs/reveng/**`; `docs/design/FINAL-SCHEMA.md`; `docs/COVERAGE.md`; `docs/INVESTIGATION-PLAN.md`; `README.md`; `tools/**`; `schema/**`; `semantic-review/**` |

Everything not Owned is treated as Restricted, including paths not enumerated above.

### 11.2 The request channel

`docs/agents/NOTES-frontend.md` is created with two fixed headings:

```markdown
## Open questions
## Requests for the backend agent
```

Rule (Requirement 16.2): a needed change to a Restricted_Path becomes an entry under
`## Requests for the backend agent` — stating the path, the change, and the reason — and the path is left
byte-identical. Known entries at design time, arising from §2.1, §8.4, §10.1 and §10.7:

| Request | Restricted path | Reason | Status |
|---|---|---|---|
| Fetch both pinned trees at the stated commits | (workspace) | G0/G1 as recorded in §2.1 | **Blocking docs 01–04 whenever G0/G1 fail**; G0/G1 are re-asserted at the start of every writing session and before the final acceptance run (§13 R2) |
| Extend `verify_refs.py` citation regex beyond `.py`; gate `--strict-names` on a Python symbol index | `tools/verify_refs.py` | `.js` citations are unverified (§8.4) | **Open, non-blocking** — the V4 read-back is required by Requirements 17.4–17.6 and stands whether or not the tool is extended |
| Note that doc 25's build/buy/drop format is §3, not §6 | `docs/logic/25-…` | stale reference (§10.7) | **Withdrawn** — Requirement 15.1 now cites section 3; nothing in `docs/logic/**` needs to change |
| Confirm `layout_revision` / `layout_node` against doc 25 §3.1's `ui_field` / `ui_layout` **BUILD** decision (`docs/logic/25-our-platform-spec.md:79`) | `docs/design/FINAL-SCHEMA.md` | FINAL-SCHEMA defines neither table (§10.1) | **Confirmation requested, not blocking** — both tables are specified in `FORM-LAYOUT.md` under Requirement 15.4 and the divergence is registered under Requirement 15.8, so the §10.5 binding table and task 10.2 (`docs/design/UI-SPEC.md`) are **unblocked**; a differing backend answer triggers the reconciliation in §13 R11 |

The invariant-prefix question generates **no request**, because the `UI` prefix resolves it without touching
any Restricted_Path (§9.2). It generates a **note** instead. Required entries under `## Open questions`:

| Note | Content | Requirement |
|---|---|---|
| Invariant-prefix deviation | The originating prompt instructs prefix `U` from `U1`; this investigation uses `UI` from `UI1`. Evidence: `docs/logic/30-upstream-trade-and-parties.md:942-956` (`U1`–`U8`) and `docs/design/FINAL-SCHEMA.md:734` (`U1`, `item_uom`). Rationale: collision avoidance; `U` is a reserved prefix per Requirement 4.3. | **4.5** |
| Presentation-metadata table divergence | `docs/design/FORM-LAYOUT.md` specifies `layout_revision` and `layout_node` (§10.1, §10.2) as the concrete form of doc 25 §3.1's `ui_field` / `ui_layout` **BUILD** decision (`docs/logic/25-our-platform-spec.md:79`), **pending confirmation by the backend agent**. Named divergence: `docs/design/FINAL-SCHEMA.md` defines neither table. | **15.8** |
| Citation_Verifier scope | The verifier checks only Citations whose path ends in `.py`: the citation pattern requires the `.py` extension (`tools/verify_refs.py:35`) and the symbol index is built with Python `ast` (`tools/verify_refs.py:62`). Consequence: `0 problems` is necessary and insufficient (Requirement 17.4); V4 read-back covers the rest (§8.4, §8.5). | **17.3** |

Requirements 4.5, 15.8 and 17.3 are each discharged only when the corresponding entry exists with its stated
citations and rationale; an absence is a review failure — 4.5 checked with P6, and 15.8 and 17.3 checked in
the same review pass (§15.2).

`docs/COVERAGE.md` is never regenerated and never edited (Requirement 16.3).

### 11.3 Commit discipline

| Rule | Statement | Requirement |
|---|---|---|
| C-1 | Commit only on `kiro/spec-planning` | 18.1 |
| C-2 | Logical units; imperative-mood messages (`Add`, `Document`, `Specify`, `Correct`) | 18.2 |
| C-3 | Stage named Owned_Paths explicitly; never `git add -A` or `git add .` | 18.3 |
| C-4 | Publish with the provided push tooling, `kiro/spec-planning` only | 18.4 |
| C-5 | `docs/business-logic` is never merged, rebased, checked out or modified | 18.5 |
| C-6 | No force-push, no history rewrite, no amend after publication | 18.6 |

Suggested commit units, one per logical deliverable: `docs/ui/01` … `docs/ui/05`, then the two normative
documents, then the Notes_Register, with the final `UI`-renumbering commit (§9.1) touching the register and
its references together.

---

## 12. Error handling

"Error handling" for a documents deliverable means: what the implementation does when a check fails or a fact
cannot be established.

| Condition | Handling | Requirement |
|---|---|---|
| Pinned tree missing or at the wrong commit | Stop at G0/G1. Write no Citation. Record in Notes_Register. | 5.4 |
| Behaviour cannot be located in the sources | Record as an **absence** finding, cite nearest related code, **omit the line number** | 5.5 |
| Code unreachable or unfinished | State the condition explicitly with a Citation | 5.6 |
| Verifier reports a problem | Correct the Citation; re-run the whole loop V1–V6 | 17.2 |
| Verifier reports `NAME NOTE` | Advisory. Review the doc line: either the cited line is wrong (fix) or the line legitimately names a symbol defined elsewhere in the same file (leave, and say so) | 17.1 |
| Shorthand `:NNN` reported `AMBIGUOUS` | Replace with the full `path:line` form | 8.3 |
| A non-`.py` Citation is not confirmed by the V4 read-back at its cited line | Correct the Citation, or remove it, **before the acceptance gate passes**; a claim left without a confirmed Citation becomes an absence finding | 17.5, 17.6 |
| Relative link does not resolve | Fix the link, or create the missing Owned file; never link a Restricted path that does not exist | 17.8 |
| `git diff --check` reports whitespace | Correct the whitespace and re-run | 17.7 |
| A change is needed in a Restricted_Path | File a request; leave the path unchanged | 16.2 |
| Two documents state the same normative fact | Delete the copy in the non-owning document per §6.1 | 15.10 |
| A bound layout field names a table absent from its declared defining document | Correct the binding row, or the binding kind, until `LT-BIND-BUS` / `LT-BIND-META` pass (§10.2, §10.5); never add the name to FINAL-SCHEMA | 15.5, 15.6, 15.7 |
| A `UI` number collides or a gap appears within the UI set | Reconcile in the single renumbering commit (§9.1); re-run V6 | 4.2 |
| An invariant is written with a reserved prefix (`M`, `A`, `F`, `T`, `R`, `V`, bare `U`) | Renumber it into the document's `UI` block before the commit; V6 fails until it is | 4.1, 4.3, 4.4 |
| The Notes_Register lacks the prefix-deviation entry | Add the entry with both citations and the rationale (§11.2) before the acceptance run | 4.5 |
| A task appears to require code or a package | Record the requirement as text in the Target_UI_Contract; create no code | 1.3 |

---

## 13. Risks

| # | Risk | Evidence | Mitigation |
|---|---|---|---|
| **R1** | **Pinned sources unavailable.** Both trees are absent from the workspace right now, so no Citation can be read and docs 01–04 cannot start. | §2.1 | G0/G1 gate stops the work rather than producing uncited claims; first Notes_Register request asks for both trees at the exact commits. Doc 05's target-contract sections that depend only on 01–04 conclusions remain blocked, by design — no speculative writing. |
| **R2** | **Citation drift.** A line number recorded in one pass, then the file re-read at a different commit (or after a pull), silently points at different code. | G1; `verify_refs.py` docstring warns to re-run after pulling | Record line numbers in the same pass as the claim (§7.2); assert G1 before every writing session and before the final acceptance run; never pull the pinned trees mid-investigation. |
| **R3** | **The verifier does not see `.js` citations,** which are the majority here, so `0 problems` is weak evidence. | §8.4, confirmed empirically | Read-back check V4 on every non-`.py` citation; prefer full `path:line` over shorthand in JavaScript-heavy sections, because shorthand resolution is also Python-only; request the tool extension. |
| **R4** | **Volume of upstream JavaScript.** `frappe/public/js/frappe/form/**`, `.../form/controls/**`, `.../list/**` plus seven alternate views is a large reading surface, and Requirements 6.6 and 9.4 enumerate long mandatory lists. | Requirements 6.6 (17 field types), 9.4 (7 views) | Coverage matrices as the unit of progress: one row per mandated item, each row closed by a cited statement (property P8). Depth is bounded — the control map states the control and its divergences, not a full reading of every control. |
| **R5** | **Restating doc 18 instead of cross-referencing it.** Doc 03's precedence analysis sits directly on metadata assembly, which doc 18 already owns in detail. | Requirement 8.4; doc 18 §1.1, §4 | §7.5 fixes the permitted form: consequence-for-layout plus a link. Review check: doc 03 contains no re-derivation of `Meta` assembly order and no algorithm already numbered in doc 18. |
| **R6** | **Drift *within* the `UI` namespace.** The cross-register collision is resolved (§9.2), so the residual risk is internal: five documents allocate `UI` numbers at different times, and a duplicate or a gap in the register is easy to introduce and easy to miss — especially where doc 05 restates 01–04 invariants by reference. | §9.1; Requirement 4.2 | Blocks pre-allocated before any document is written, so two documents cannot claim one number; unused numbers in a block are left unused rather than reclaimed; consecutiveness reconciled in a **single** renumbering commit after doc 05, touching the register and every reference together; check V6 asserts set equality with `UI1..UIn`, so a gap or duplicate fails acceptance rather than shipping. |
| **R7** | **Normative drift between UI-SPEC and FORM-LAYOUT.** Two documents describing one contract will duplicate and then disagree. | §6.1 | Single-source rule with an explicit allocation table; extraction happens once, after 05; duplicates are deleted, not reconciled. |
| **R8** | **Scope creep into application design.** The target contract sections invite component and code design. | Requirement 1.1, 1.3 | Deliverable is `.md` only; contract expressed as DDL sketches, EBNF and rule tables; property P1 asserts no non-document file changes. |
| **R9** | **Ownership breach under concurrency.** The backend agent is active on `docs/business-logic`. | Requirement 16.1, 18.5 | Explicit staging (C-3), V5 path-containment check before every commit, and no branch operations against `docs/business-logic`. |
| **R10** | **Vacuous coverage.** A document can satisfy the section template while saying nothing about a mandated topic. | Requirements 6–9 | Coverage matrix per document, checked by P8: every mandated topic maps to a section and at least one Citation. |
| **R11** | **No presentation-metadata binding target existed.** The binding rule originally required every layout field to name a FINAL-SCHEMA table and column, but presentation-metadata fields have no FINAL-SCHEMA home, so the rule was unsatisfiable and `docs/design/UI-SPEC.md` was blocked on it. | `docs/design/FINAL-SCHEMA.md` contains no `ui_field`, `ui_layout`, `layout_revision` or `layout_node`; doc 25 §3.1 commits to **BUILD**ing `ui_field` / `ui_layout` (`docs/logic/25-our-platform-spec.md:79`, listed again at `:259`) | **Mitigated, not open.** `FORM-LAYOUT.md` specifies `layout_revision` and `layout_node` itself (§10.1, §10.2, Requirement 15.4) and the binding table splits business-data rows, which resolve in FINAL-SCHEMA, from presentation-metadata rows, which resolve in FORM-LAYOUT (§10.5, Requirements 15.5, 15.6). FINAL-SCHEMA is untouched (Requirement 15.7). **Residual:** the backend agent may later specify `ui_field` / `ui_layout` with different table or column names, requiring the §10.5 binding table and the §10.1/§10.2 DDL to be reconciled in a single commit. The divergence is registered in the Notes_Register (Requirement 15.8, §11.2), so that reconciliation is triggered by a known open item rather than discovered later. |

---

## 14. Correctness properties

*A property is a characteristic or behaviour that should hold true across all valid executions of a system —
essentially, a formal statement about what the system should do. Properties serve as the bridge between
human-readable specifications and machine-verifiable correctness guarantees.*

Two families appear below, because this specification has two kinds of subject.

- **Artefact properties (A-family)** quantify over the documents, citations, links, paths and commits this
  investigation produces. They are checkable **now**, mechanically, against the repository.
- **Contract properties (C-family)** quantify over the target design that the Target_UI_Contract states. They
  are checkable **at implementation time**; what is checkable now is that the contract asserts them. They are
  recorded here so the future implementation inherits an executable specification rather than prose.

### Property 1: Non-document files are untouched

*For all* files in the repository whose extension is not `.md`, `.json` or `.kiro`, the file content after the
Frontend_Investigation is byte-identical to its content before, and no such file is created or deleted.

**Validates: Requirements 1.1, 1.3, 1.4**

### Property 2: Every changed path is an Owned_Path

*For any* commit produced by the Frontend_Investigation, every path in that commit's change set is an
Owned_Path, and no path in the change set is a Restricted_Path.

**Validates: Requirements 2.8, 16.1, 16.3, 18.3**

### Property 3: Every citation resolves to a real line

*For any* Citation appearing in a UI_Doc, in the Target_UI_Contract, or in the Notes_Register, the cited path
resolves under the correct pinned root — `frappe/`-prefixed paths under `/projects/sandbox/frappe/frappe`, and
unprefixed paths under `/projects/sandbox/erpnext/erpnext` — every cited line number is within that file's
line count at the pinned commit, and, where the cited path ends in an extension other than `.py`, the cited
line contains the construct named by the Behavioural_Claim carrying that Citation.

**Validates: Requirements 5.2, 5.3, 5.4, 17.1, 17.2, 17.4, 17.5, 17.6**

### Property 4: Every claim and every defect entry carries a citation

*For all* Behavioural_Claims in a UI_Doc, and *for all* rows of a defect and race inventory, at least one
Citation is attached, except where the entry is recorded as an absence finding, in which case a Citation to
the nearest related code is attached and no line number is given for the absent behaviour.

**Validates: Requirements 3.6, 5.1, 5.5, 5.6**

### Property 5: Every UI_Doc satisfies the section template

*For all* UI_Docs, the document contains: an opening blockquote naming both Pinned_Sources and both pinned
commit hashes; numbered top-level sections; at least one worked example in every section that describes a
mechanism; a defect and race inventory; at least one `UI*` invariant across the set; an Adopt / Change / Reject
matrix; and a closing cross-reference footer.

**Validates: Requirements 3.1, 3.2, 3.4, 3.7, 3.8**

### Property 6: The invariant identifier set is exactly UI1..UIn

*For all* Invariants defined by the Frontend_Investigation, the identifier matches `UI` followed by an
integer; the set of identifiers equals `{UI1, …, UIn}` for some `n` with no gaps and no duplicates; and no
identifier uses a reserved prefix — `M`, `A`, `F`, `T`, `R`, `V`, or a bare `U` not followed by `I`.

**Validates: Requirements 4.1, 4.2, 4.3, 4.4**

### Property 7: Every relative link resolves

*For any* relative Markdown link in a UI_Doc, in the Target_UI_Contract, or in the Notes_Register, the link
target exists in the repository; and every reference to an upstream logic document names a file that exists on
the branch.

**Validates: Requirements 17.8, 17.9, 3.8**

### Property 8: Mandated topic coverage is total

*For all* topics enumerated as mandatory by Requirements 6 to 9 — including each of the 17 named field types,
each of the 7 named alternate list views, and each named customisation mechanism — the owning document
contains a statement addressing that topic, carrying at least one Citation.

**Validates: Requirements 6.1–6.8, 7.1–7.7, 8.1–8.6, 9.1–9.6**

### Property 9: Every storage binding resolves in its defining document and stays canonical

*For all* layout fields bound to storage by the Target_UI_Contract, the field declares exactly one binding
kind, and: where the kind is **business data**, the named table and column exist in
`docs/design/FINAL-SCHEMA.md`; where the kind is **presentation metadata**, the named table and column exist
among the `layout_revision` and `layout_node` definitions in `docs/design/FORM-LAYOUT.md`; the declared type
for a money, quantity/rate or percent field is respectively `numeric(19,4)`, `numeric(21,9)` or
`numeric(9,6)`; every enumerated field declares a stable lower-case code with its label resolved at read time;
and no bound field is declared as holding formatted or translated text.

**Validates: Requirements 13.2, 13.3, 13.4, 15.3, 15.5, 15.6**

### Property 10: Publish-time validation is total and decisive

*For any* Layout_Tree submitted for publication, the outcome is exactly one of: acceptance, where the tree
satisfies every validation rule; or rejection of the containing Layout_Revision carrying at least one
identified validation error code. No tree is accepted with an unsatisfied rule, and no tree is rejected
without an error code.

**Validates: Requirements 10.2, 10.3, 11.4**

### Property 11: Approved layout revisions are immutable

*For any* Layout_Revision in the approved state, no subsequent operation changes its Layout_Tree, its scope
keys or its effective range; a change is expressed only as a new revision, and effective ranges for one scope
tuple never overlap.

**Validates: Requirements 10.1, 10.4**

### Property 12: Layout revision export round-trips

*For any* approved Layout_Revision, exporting to the diffable textual form and importing that form yields a
Layout_Revision with an identical Layout_Tree, identical scope keys, identical effective range and an
identical content hash.

**Validates: Requirements 10.5**

### Property 13: Expression validation is total, and hashing is deterministic

*For any* candidate Expression_Language expression, parsing either yields a validated abstract syntax tree
carrying a version hash, or fails with an identified validation error; two expressions with the same canonical
AST and the same grammar version produce the same version hash; and no accepted expression is evaluated by
dynamic evaluation of its source text.

**Validates: Requirements 11.1, 11.2, 11.5**

### Property 14: Client and server evaluation agree

*For any* validated expression AST, any set of document values and any single version hash, client-side
evaluation and server-side evaluation return the same result; and *for any* field, the client's cached
visibility or permission decision is never wider than the server's decision for the same inputs.

**Validates: Requirements 11.3, 11.6**

### Property 15: Row identity is stable under reordering and deletion

*For any* child-table row set and any sequence of row additions, deletions and reorderings, each surviving
row retains the row identifier it was created with, independently of any change to its `idx` or ordinal
position; and every column exposed by the grid comes from the server-driven column set for that child table.

**Validates: Requirements 12.1, 12.2, 12.3**

### Property 16: Display formatting is a pure function

*For any* stored value, locale and field precision, the displayed text is determined entirely by those three
inputs and by nothing else; formatting the same triple twice yields the same text; and formatting never
changes the stored value.

**Validates: Requirements 13.1, 13.5**

### Property 17: Regional behaviour follows the document's company

*For any* document, the localised field set and localised labels selected are those of the Tax_Regime
associated with that document's company identifier, and are unchanged by any session default; and the
underlying doctype definition is identical across jurisdictions.

**Validates: Requirements 14.2, 14.3, 14.5**

### Property 18: Every business-table layout query is company-scoped

*For all* layout queries specified by the Target_UI_Contract that read a business table, the query is
row-level-security scoped by `company_id`.

**Validates: Requirements 15.9**

### Property 19: Branch history is append-only

*For any* two observations of `kiro/spec-planning` over the course of the Frontend_Investigation, every commit
present in the earlier observation is still an ancestor of the later tip; and the `docs/business-logic` ref is
identical in both observations.

**Validates: Requirements 18.5, 18.6**

### 14.1 Prework summary and reflection

Classification of the acceptance criteria, and the consolidation applied:

| Criteria | Classification | Outcome |
|---|---|---|
| 1.1, 1.3, 1.4, 2.8, 16.1, 16.3, 18.3 | PROPERTY | consolidated into P1 (file types) + P2 (path containment); the six path-scoped criteria all reduce to one containment statement |
| 1.2, 4.6, 16.4, 18.2 | not testable | judgement or process; review checklist only — "one testable rule per invariant" (4.6) is itself a judgement about a rule's shape (§9.3) |
| 2.1–2.7 | EXAMPLE | fixed 8-path existence check, not universal |
| 3.1, 3.2, 3.4, 3.7, 3.8 | PROPERTY | consolidated into P5; 3.8 also feeds P7 |
| 3.3, 3.5 | EXAMPLE | presence of an algorithm block / evidence-vs-projection table per applicable section; "applicable" is a judgement, so not a property |
| 3.6, 5.1, 5.5, 5.6 | PROPERTY + EDGE_CASE | consolidated into P4; absence and dead-code handling folded in as the exception branch rather than separate properties |
| 4.1, 4.2, 4.3, 4.4 | PROPERTY | consolidated into P6; P6 subsumes 4.1 and 4.4 because a gap-free `UI1..UIn` set implies both the prefix form and its universal use, and the reserved-prefix exclusion carries 4.3 |
| 4.5 | EXAMPLE | one Notes_Register entry, checked once for the prompt's instruction, both citations and the rationale (§11.2); not universal over any input |
| 5.2, 5.3, 5.4 | PROPERTY | consolidated into P3 |
| 6.x–9.x | PROPERTY (coverage) | consolidated into P8; per-topic criteria are rows of one coverage matrix, not 30 properties |
| 10.1, 10.4 | PROPERTY | P11 |
| 10.2, 10.3, 11.4 | PROPERTY | consolidated into P10; a totality statement subsumes the separate "invalid ⇒ rejected" criterion |
| 10.5 | PROPERTY (round-trip) | P12 |
| 11.1, 11.2, 11.5 | PROPERTY | consolidated into P13 |
| 11.3, 11.6 | PROPERTY | consolidated into P14; the cache-narrowness rule belongs with evaluation agreement |
| 12.1, 12.2, 12.3 | PROPERTY | consolidated into P15 |
| 12.4, 12.5, 12.6 | EXAMPLE | a stated numeric budget, and keyboard/labelling checks best covered by targeted accessibility tests, not randomised input |
| 13.1, 13.5 | PROPERTY | P16 |
| 13.2, 13.3, 13.4, 15.3, 15.5, 15.6 | PROPERTY | consolidated into P9; the two binding criteria are one property with a binding-kind branch, not two properties, because a field declares exactly one kind |
| 14.1 | EXAMPLE | a fixed field list, checked once |
| 14.2, 14.3, 14.5 | PROPERTY | consolidated into P17 |
| 14.4, 15.1, 15.2, 15.10 | EXAMPLE | matrix-row presence and layer assignment; judgement, verified by review |
| 15.4 | EXAMPLE | one check that `FORM-LAYOUT.md` specifies both tables (§10.1, §10.2); not universal over any input |
| 15.7 | PROPERTY | an instance of P2 — `docs/design/FINAL-SCHEMA.md` is a Restricted_Path, so path containment already forbids the edit |
| 15.8 | EXAMPLE | one Notes_Register entry, checked once for the two table names, the pending-confirmation statement and the named divergence (§11.2) |
| 15.9 | PROPERTY | P18 |
| 17.1, 17.2 | SMOKE + PROPERTY | the command is a single gate (SMOKE); its universal content is P3 |
| 17.3 | EXAMPLE | one Notes_Register entry, checked once for both `verify_refs.py` citations (§11.2) |
| 17.4, 17.5, 17.6 | PROPERTY | consolidated into P3; the read-back is the non-`.py` branch of citation resolution, and 17.4 is the reason P3 cannot be discharged by V1 alone |
| 17.7 | SMOKE | `git diff --check` |
| 17.8, 17.9 | PROPERTY | consolidated into P7 |
| 18.1, 18.4 | SMOKE | branch and push checks |
| 18.5, 18.6 | PROPERTY | consolidated into P19 |

Redundancies removed: separate properties for "the verifier reports 0 problems" (an instance of P3), for
"`docs/COVERAGE.md` unchanged" (an instance of P2), for "`idx` values after delete" (an instance of P15), for
"no `eval`" (an instance of P13), and for "invariants use the `UI` prefix" (an instance of P6).

---

## 15. Testing strategy

### 15.1 Applicability

Property-based testing applies here only to the **artefact properties**, because those are the ones whose
subject exists now. The generated input is not random data but the enumerated set of documents, citations,
links, paths and commits — a finite universe that is nonetheless large enough that exhaustive checking must be
mechanical rather than manual.

Property-based testing does **not** apply to the contract properties in this phase: there is no
implementation, and Requirement 1.3 forbids creating one. Writing PBT harnesses for P10–P18 now would require
frontend code and would breach the documents-only constraint. They are recorded as the executable
specification the implementation must satisfy later.

### 15.2 How each property is checked

| Property | Family | Check now | Check later |
|---|---|---|---|
| P1 | artefact | `git diff --name-only` filtered by extension; content hash comparison | — |
| P2 | artefact | V5: per-commit path containment against the Owned list | — |
| P3 | artefact | V1 (`verify_refs.py --strict-names`) for `.py`; **V4 read-back for `.js` and every other non-`.py` extension, required by Requirements 17.4–17.6** — a gate condition, not a workaround for the §8.4 finding, and an unconfirmed Citation is corrected or removed before the gate passes | tool extension can automate V4; it cannot remove the obligation |
| P4 | artefact | review pass per defect-inventory row + citation presence scan | — |
| P5 | artefact | template conformance scan per UI_Doc (T1–T11) | — |
| P6 | artefact | V6: extract `UI\d+`, assert set equality with `UI1..UIn`; assert no invariant identifier matches a reserved prefix, including `U` not followed by `I`; and confirm the Requirement 4.5 prefix-deviation entry exists in the Notes_Register with both citations (§11.2) | — |
| P7 | artefact | V3: resolve every relative link | — |
| P8 | artefact | coverage matrix per document; every mandated row closed with a Citation | — |
| P9 | artefact (binding) | binding table split by kind: business-data rows cross-checked against `FINAL-SCHEMA.md` table and column names, presentation-metadata rows against the `layout_revision` / `layout_node` definitions in `FORM-LAYOUT.md` (§10.5) | schema tests at implementation |
| P10–P18 | contract | assert the contract *states* the property, with a `**Validates:**` annotation | property-based tests, ≥ 100 iterations each |
| P19 | artefact | compare `git log --first-parent` between sessions; compare the `docs/business-logic` ref | — |

### 15.3 Configuration for the later contract tests

Recorded now so the implementation inherits it:

- Minimum **100 iterations** per property test.
- Each test references its design property by tag: **Feature: frontend-form-ui, Property {number}:
  {property_text}**.
- Generators must cover the edge cases this investigation identified: malformed and missing break sequences,
  duplicate `field_key`s, cyclic parent references, empty and whitespace-only label keys, expressions at the
  grammar boundary, child tables at and above the stated row budget, deletion of interior rows, and
  multi-jurisdiction company configurations.
- Unit tests carry the example-classified criteria (2.1–2.7, 3.3, 3.5, 12.4–12.6, 14.1, 15.1, 15.2, 15.4,
  15.8, 15.10, 17.3) and the smoke-classified gates (17.1, 17.2, 17.7, 18.1, 18.4). Property tests carry universal input coverage; the two
  are complementary and neither substitutes for the other.

---

## 16. Cross-references

- `.kiro/specs/frontend-form-ui/requirements.md` — the requirements this design satisfies
- `docs/agents/PROMPT-frontend-form-ui.md` — originating task and ownership boundary (note: its names for
  logic docs 18, 19 and 24 are stale; see §8.5)
- `docs/logic/18-metadata-and-runtime-ddl.md` — metadata assembly and cache; direct upstream dependency
- `docs/logic/19-permissions-and-access-control.md` — permission and sharing evaluation
- `docs/logic/24-reporting-framework.md` — report views, dashboards, print
- `docs/logic/21-extensibility-hooks-and-regional.md` — Client Scripts, regional override mechanism
- `docs/logic/25-our-platform-spec.md` — §2 layering rule, §3 build/buy/drop format
- `docs/logic/30-upstream-trade-and-parties.md` — existing `U1`–`U8` invariants; why `U` is reserved (§9.2)
- `docs/design/FINAL-SCHEMA.md` — read-only storage contract; §24 records the presentation-layer deferral
- `tools/verify_refs.py` — citation verifier; read-only for this investigation
