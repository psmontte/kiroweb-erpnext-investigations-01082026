# Implementation Plan: Frontend Form UI Investigation

## Overview

The deliverable is **eight Markdown documents**, not application code. Every task below reads pinned upstream
source, records `path:line` Citations at read time, and writes a named section of a named document. No task
creates a `.ts`, `.js`, `.py`, `.json` or any other non-Markdown file (Requirement 1.1, 1.3, 1.4).

**Gate status at plan time.** G0–G3 all pass. Both pinned trees are present at the exact commits
(`frappe` = `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `erpnext` = `ceefd4add77715d2762c19db337fb83e28a477de`),
the branch is `kiro/spec-planning`, and all five upstream cross-reference documents exist. Design §2.1 records
G0 as failing; that blocker is resolved and docs 01–04 are unblocked. Both checkouts are **shallow (depth 1)**,
so `git log` history is unavailable but every file is present at the pinned commit. **Never pull, fetch or
checkout in either tree** — doing so silently invalidates every recorded line number (design risk R2).

**Path corrections applied throughout.** Three paths named in `docs/agents/PROMPT-frontend-form-ui.md` and in
design §7.1 do not exist at this commit and are corrected here:

| Named in prompt / design | Actual at pinned commit | Consequence |
|---|---|---|
| `frappe/public/js/frappe/form/grid_form.js` | `frappe/public/js/frappe/form/grid_row_form.js` | cite the real file |
| `FormPage` class | does not exist; `grep -rn "FormPage" form/` is empty | record as an **absence** finding per design §7.4; the real units are `form.js`, `layout.js`, `section.js`, `column.js`, `tab.js`, `views/formview.js` |
| `frappe/public/js/frappe/list/list_sidebar*` | no `list_sidebar.js`; only `list_sidebar_group_by.js` and `list_sidebar_stat.html` | cite the real files; sidebar composition lives in `list_view.js` / `base_list.js` |

Two upstream findings the plan exploits deliberately:

- **`frappe/public/js/frappe/list/list_view_virtualization.js` exists.** Design rule G-4 proposes virtualised
  rendering as *our* change. Docs 02 and 04 must establish what upstream already virtualises (list views)
  versus what it does not (the child-table grid), so the Adopt/Change/Reject verdict rests on evidence rather
  than on an assumed absence.
- **`frappe/public/js/frappe/list/bulk_operations.js`** is the single site for the bulk edit / submit / cancel /
  delete failure-reporting model (Requirement 9.5).

**Writing order** follows design §4.2: docs 01, 02 and 04 are mutually independent; 03 depends on 01; 05
consolidates 01–04; `FORM-LAYOUT.md` and `UI-SPEC.md` are the normative extraction from 05 and come last; the
Notes_Register is created first and appended throughout.

**No test-code tasks exist in this plan.** Design §15.1 restricts checking to the artefact properties (P1–P9,
P19), which are verified by read-only shell commands and review passes in task 12, and defers the contract
properties (P10–P18) to a future implementation. Writing a property-test harness now would require frontend
code and breach Requirement 1.3.

**Commit discipline** applies to every task: commit only on `kiro/spec-planning`, stage named Owned_Paths
explicitly (never `git add -A`), imperative-mood messages, no force-push, and no operation against the
`docs/business-logic` branch (Requirements 18.1–18.6).

## Tasks

- [ ] 1. Establish gates and the Notes_Register
  - [ ] 1.1 Verify gates G0–G3 and record the observed state
    - Confirm `/projects/sandbox/frappe/frappe` and `/projects/sandbox/erpnext/erpnext` exist as directories
    - Confirm `git -C /projects/sandbox/frappe rev-parse HEAD` = `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
      `git -C /projects/sandbox/erpnext rev-parse HEAD` = `ceefd4add77715d2762c19db337fb83e28a477de`
    - Confirm the working branch is `kiro/spec-planning`
    - Confirm `docs/logic/18-metadata-and-runtime-ddl.md`, `docs/logic/19-permissions-and-access-control.md`,
      `docs/logic/24-reporting-framework.md`, `docs/logic/25-our-platform-spec.md` and
      `docs/design/FINAL-SCHEMA.md` all exist
    - Create the `docs/ui/` directory; do not create any file outside Owned_Paths
    - Read-only commands only; if any gate fails, stop and record the failure rather than proceeding
    - _Requirements: 5.4, 17.5, 18.1_

  - [ ] 1.2 Create `docs/agents/NOTES-frontend.md` with its fixed headings and seeded entries
    - Create the file with exactly two top-level headings, `## Open questions` and
      `## Requests for the backend agent`
    - Seed under `## Requests for the backend agent`: extend `tools/verify_refs.py` citation regex beyond
      `.py` and gate `--strict-names` on a Python-only symbol index (design §8.4); note that doc 25's
      build/buy/drop format is §3, not §6 as Requirement 15.1 states (design §10.7); confirm the
      presentation-metadata binding (`ui_field` / `ui_layout`, doc 25 §3.1) against `layout_revision` /
      `layout_node` in `docs/design/FINAL-SCHEMA.md` (design §10.5); record that both pinned trees are now
      present at the stated commits as shallow checkouts, closing the earlier fetch request
    - Seed under `## Open questions` the Requirement 4.5 invariant-prefix deviation entry: the prompt
      instructs prefix `U` from `U1`; this investigation uses `UI` from `UI1`; evidence
      `docs/logic/30-upstream-trade-and-parties.md:942-956` (`U1`–`U8`) and
      `docs/design/FINAL-SCHEMA.md:734` (`U1`, `item_uom`); rationale is collision avoidance, `U` being a
      reserved prefix
    - Leave every Restricted_Path byte-identical; this file is the only channel for requesting a change to one
    - _Requirements: 2.7, 4.5, 16.2, 16.4_

- [ ] 2. Write `docs/ui/01-form-rendering-and-layout-engine.md`
  - [ ] 2.1 Create doc 01 and its section skeleton
    - Write T1 title `# 01 — Form Rendering and Layout Engine`, T2 pinned-source blockquote naming both trees
      and both commit hashes in the exact form of design §5.1, T3 framing paragraph stating what is deferred
      to a cross-referenced document, T4 numbered section headings, and the T11 cross-reference footer
    - Pre-allocate the invariant block `UI1`–`UI9` in a placeholder register table; allocate upward from `UI1`
    - _Requirements: 3.1, 3.2, 3.8, 4.1, 4.4_

  - [ ] 2.2 Establish the runtime form construction order, and record the `FormPage` absence
    - Read `frappe/public/js/frappe/form/form.js` → `layout.js` → `section.js`, `column.js`, `tab.js`, and
      `frappe/public/js/frappe/views/formview.js`; record path and 1-based line numbers in the same pass
    - State the construction order as numbered steps with branch conditions, not a prose summary, with a
      worked example tracing one doctype from instantiation to rendered structure
    - Record `FormPage` as an **absence** finding: state what was searched for and where, cite the nearest
      related code, and omit any line number for the absent class
    - _Requirements: 3.3, 3.4, 5.1, 5.3, 5.5, 6.1_

  - [ ] 2.3 Establish the `Meta.fields` → visual tree algorithm and its malformed-input behaviour
    - Transcribe the algorithm converting the ordered field list plus `Tab Break`, `Section Break` and
      `Column Break` rows into the visual tree, in the numbered form of design §7.3 (Algorithm A-01-2), each
      step carrying a shorthand citation resolving against a fully cited file
    - State the resulting rendered structure when a break row is missing, duplicated or out of order, as
      observed in code rather than inferred
    - Add a worked example running a concrete field list through the numbered steps
    - _Requirements: 3.3, 3.4, 5.1, 6.2, 6.3_

  - [ ] 2.4 Establish the evaluation of the `*_depends_on` family
    - State evaluation scope, evaluation timing and failure behaviour for `depends_on`,
      `mandatory_depends_on`, `read_only_depends_on` and `collapsible_depends_on`, including what happens when
      an expression throws
    - Cite the evaluation site; note whether user-authored text reaches a dynamic evaluation path, since this
      is the evidence base for target rule X-5
    - _Requirements: 5.1, 6.4_

  - [ ] 2.5 Establish the render effect of the field flags
    - State the render effect of `hidden`, `read_only`, `bold`, `allow_on_submit`, `in_list_view`,
      `print_hide` and `translatable`, one cited statement per flag
    - Note for each flag whether the effect is client-only, and therefore whether it is a security boundary or
      merely a presentation choice
    - _Requirements: 5.1, 6.5_

  - [ ] 2.6 Map each field type to its control implementation
    - Read `frappe/public/js/frappe/form/controls/base_control.js` then the per-type controls under
      `frappe/public/js/frappe/form/controls/`
    - Produce a coverage matrix with one cited row per mandated type: `Link`, `Dynamic Link`, `Table`,
      `Table MultiSelect`, `Select`, `Currency`, `Float`, `Percent`, `Duration`, `Geolocation`, `Barcode`,
      `Signature`, `Rating`, `JSON`, `Code`, `Markdown`, `Attach`
    - Bound the depth per design risk R4: state the control and its divergences from the base control, not a
      full reading of every control
    - _Requirements: 5.1, 6.6_

  - [ ] 2.7 Establish precision resolution and the evidence-versus-projection table
    - State the resolution order from field precision, through `System Settings.float_precision`, to currency
      `smallest_fraction`, citing `formatters.js` and the resolution helpers
    - Identify each point at which a displayed value diverges from the stored value
    - Add the T7 evidence-versus-projection table in the fixed column form of design §5.2
    - _Requirements: 3.5, 5.1, 6.7_

  - [ ] 2.8 Establish the dirty-state model and re-render cost
    - State the dirty-state model and the re-render cost of `refresh_field`, `set_value` and `toggle_display`,
      deriving cost from the code path rather than asserting it
    - _Requirements: 5.1, 6.8_

  - [ ] 2.9 Complete doc 01 with its inventory, invariants and Adopt/Change/Reject matrix
    - Write the T8 defect and race inventory as a numbered table in which **every row carries at least one
      Citation**; record any unreachable or unfinished code explicitly in the fixed form of design §7.4
    - Write the T9 invariants within the `UI1`–`UI9` block, one testable rule each whose violation is
      observable; leave unused numbers in the block unused
    - Write the T10 Adopt/Change/Reject matrix in the fixed column order of design §5.3, entering the ordered
      break-row model as **Reject** and the precision-resolution chain as **Reject**
    - Close the cross-reference footer with every related document by relative path
    - _Requirements: 3.6, 3.7, 3.8, 4.6, 5.5, 5.6_

- [ ] 3. Write `docs/ui/02-child-table-grid-engine.md`
  - [ ] 3.1 Create doc 02 and its section skeleton
    - Write T1–T4 and the T11 footer per design §5, with the T2 blockquote naming both trees and both hashes
    - Pre-allocate the invariant block `UI10`–`UI19`
    - _Requirements: 3.1, 3.2, 3.8, 4.1_

  - [ ] 3.2 Establish the behaviour of the four grid modules
    - Read `frappe/public/js/frappe/form/grid.js` → `grid_row.js` → `grid_row_form.js` → `grid_pagination.js`
      in that order, recording line numbers at read time
    - State each module's responsibility and entry points with Citations; use `grid_row_form.js`, not the
      non-existent `grid_form.js`
    - Add a worked example rendering one child table end to end
    - _Requirements: 3.4, 5.1, 5.3, 7.1_

  - [ ] 3.3 Establish visible-column selection
    - State the algorithm selecting visible columns from `in_list_view` and `columns` width units, including
      the total-width budget and the storage location of user column configuration
    - Add a worked example with a concrete child doctype and the resulting column set
    - _Requirements: 3.4, 5.1, 7.2_

  - [ ] 3.4 Establish `idx` maintenance under addition, removal and reordering
    - State the effect of row addition, removal and reordering on `idx`, including the exact `idx` values
      remaining after an interior row is deleted
    - Add the evidence-versus-projection table distinguishing stored `idx` from render-time row position
    - This is the evidence base for target rule G-2; state precisely what a reference to `idx` can and cannot
      survive
    - _Requirements: 3.5, 5.1, 7.3_

  - [ ] 3.5 Establish expanded-row, bulk-edit, paste and template behaviour
    - State the behaviour of the expanded row form, bulk edit, paste-from-spreadsheet input, and grid template
      download and upload, with Citations into the paste and template handlers
    - _Requirements: 5.1, 7.4_

  - [ ] 3.6 Establish grid pagination behaviour while unsaved rows are present
    - State what `grid_pagination.js` does when the child table holds unsaved rows, including whether an
      unsaved row can leave the rendered page and what happens to it
    - _Requirements: 5.1, 7.5_

  - [ ] 3.7 Establish the child-row validation order
    - State the validation order from client control, through `validate`, to the server, tracing the child-row
      path into `frappe/model/`
    - Identify which row-level errors reach the user interface and which are silently absorbed
    - _Requirements: 5.1, 7.6_

  - [ ] 3.8 Establish grid complexity at 500 rows against upstream virtualisation
    - State the code-derived complexity of grid operations at 500 child rows and name each operation whose
      cost grows as the square of the row count
    - Establish, with Citations, that `frappe/public/js/frappe/list/list_view_virtualization.js` virtualises
      **list** rendering while the child-table grid does not, so the G-4 verdict rests on observed asymmetry
      rather than on an assumed absence
    - _Requirements: 5.1, 7.7_

  - [ ] 3.9 Complete doc 02 with its inventory, invariants and Adopt/Change/Reject matrix
    - Write the defect and race inventory with a Citation on every row
    - Write invariants within `UI10`–`UI19`, one testable rule each
    - Write the Adopt/Change/Reject matrix, entering `idx`-as-identity as **Reject** and unvirtualised grid
      rendering as **Change**, each with a Citation
    - Close the cross-reference footer
    - _Requirements: 3.6, 3.7, 3.8, 4.6, 5.6_

- [ ] 4. Write `docs/ui/04-list-view-filters-and-bulk-actions.md`
  - [ ] 4.1 Create doc 04 and its section skeleton
    - Write T1–T4 and the T11 footer per design §5
    - Pre-allocate the invariant block `UI28`–`UI34`
    - _Requirements: 3.1, 3.2, 3.8, 4.1_

  - [ ] 4.2 Establish list settings, sidebar, group-by and saved filters
    - Read `frappe/public/js/frappe/list/base_list.js` → `list_view.js` → `list_settings.js` →
      `list_sidebar_group_by.js` → `list_filter.js` and `list_filter/`
    - State the behaviour of list settings, the sidebar, group-by and saved filters, with Citations; record
      that no `list_sidebar.js` exists at this commit and cite the files that actually compose the sidebar
    - Add a worked example for one doctype's list configuration
    - _Requirements: 3.4, 5.1, 5.3, 9.1_

  - [ ] 4.3 Establish filter construction and transmission
    - State the algorithm that builds a filter expression and transmits it to the server, as numbered steps
      with branch conditions
    - Add the evidence-versus-projection table separating persisted filter state from per-request filter
      construction
    - _Requirements: 3.3, 3.5, 5.1, 9.2_

  - [ ] 4.4 Establish the permission-filtering join point
    - State where permission filtering combines with user-supplied filters, citing the join site
    - Cross-reference `docs/logic/19-permissions-and-access-control.md` for permission evaluation itself;
      state only the consequence for list construction, and do not restate the permission algorithm
    - _Requirements: 5.1, 9.3_

  - [ ] 4.5 Classify each alternate view as metadata-driven or not
    - Read `frappe/public/js/frappe/views/kanban/`, `calendar/`, `gantt/`, `treeview.js`, `image/`, `map/`,
      `dashboard/`
    - Produce a coverage matrix with one cited row per mandated view — `Kanban`, `Calendar`, `Gantt`, `Tree`,
      `Image`, `Map`, `Dashboard` — stating whether the view is driven by metadata and what supplies its
      configuration when it is not
    - Cross-reference `docs/logic/24-reporting-framework.md` by link only for report views and dashboards
    - _Requirements: 5.1, 9.4_

  - [ ] 4.6 Establish the bulk-action failure model
    - Read `frappe/public/js/frappe/list/bulk_operations.js` and the server handlers it calls
    - State the failure reporting model of bulk edit, bulk submit, bulk cancel and bulk delete, including the
      outcome for the remaining documents when one document fails, and whether partial success is reported
    - Add a worked example of a mixed success/failure batch
    - _Requirements: 3.4, 5.1, 9.5_

  - [ ] 4.7 Establish `listview_settings` indicator derivation
    - State how `listview_settings` derives indicator and status text, and name the source of that text
    - Cite at least one ERPNext-side consumer without the `frappe/` prefix, as a path relative to
      `/projects/sandbox/erpnext/erpnext`
    - _Requirements: 5.1, 5.2, 9.6_

  - [ ] 4.8 Complete doc 04 with its inventory, invariants and Adopt/Change/Reject matrix
    - Write the defect and race inventory with a Citation on every row, including the bulk partial-failure
      findings
    - Write invariants within `UI28`–`UI34`, one testable rule each
    - Write the Adopt/Change/Reject matrix; enter list virtualisation as **Adopt** with its Citation
    - Close the cross-reference footer
    - _Requirements: 3.6, 3.7, 3.8, 4.6_

- [ ] 5. Checkpoint — source-analysis docs 01, 02 and 04
  - Run `python3 tools/verify_refs.py --docs docs/ui --app erpnext=/projects/sandbox/erpnext/erpnext --app frappe=/projects/sandbox/frappe/frappe --strict-names` and confirm `0 problems`
  - Run `git diff --check` and confirm no output
  - Re-assert G1: both pinned commits still match, and neither tree has been pulled
  - Ensure all checks pass, ask the user if questions arise.

- [ ] 6. Write `docs/ui/03-form-customisation-and-layout-overrides.md`
  - [ ] 6.1 Create doc 03 and its section skeleton
    - Write T1–T4 and the T11 footer per design §5
    - Pre-allocate the invariant block `UI20`–`UI27`
    - Depends on doc 01: the framing must reference the field-definition model doc 01 fixed, since these
      mechanisms mutate it
    - _Requirements: 3.1, 3.2, 3.8, 4.1_

  - [ ] 6.2 Establish what `Customize Form` writes, and to which tables
    - Read `frappe/frappe/custom/doctype/customize_form/` and `customize_form_field/`
    - State what the mechanism writes and to which tables, with Citations; these are `.py` paths and therefore
      fully verifiable by the Citation_Verifier, so prefer full `path:line` form
    - Add a worked example of one customisation from user action to stored row
    - _Requirements: 3.4, 5.1, 5.3, 8.1_

  - [ ] 6.3 Establish the render effect of each customisation mechanism
    - Read `frappe/frappe/custom/doctype/custom_field/`, `property_setter/`, `client_script/`, and the
      `doctype_layout`, `workspace`, `form_tour` and `custom_html_block` doctypes
    - Produce a coverage matrix with one cited row per mandated mechanism: `Custom Field`, `Property Setter`,
      `DocType Layout`, `Workspace`, `Form Tour`, `Client Script`, `Custom HTML Block`
    - _Requirements: 5.1, 8.2_

  - [ ] 6.4 Establish precedence and merge order for a single field
    - State the exact precedence and merge order producing the final field definition when more than one
      mechanism targets one field, as numbered steps with branch conditions
    - Add a worked example in which three mechanisms contend over one field and the winner is derived
    - This is the evidence base for the FORM-LAYOUT precedence rules
    - _Requirements: 3.3, 3.4, 5.1, 8.3_

  - [ ] 6.5 Cross-reference the metadata cache instead of restating it
    - Cross-reference `docs/logic/18-metadata-and-runtime-ddl.md` for metadata cache behaviour, in the
      permitted form of design §7.5: a one-sentence statement of the consequence for layout, plus a link
    - Verify by review that doc 03 contains no re-derivation of `Meta` assembly order and no algorithm already
      numbered in doc 18 (design risk R5)
    - _Requirements: 8.4, 17.4_

  - [ ] 6.6 Classify scope and upgrade survival per mechanism
    - Classify each mechanism as site-global, role-scoped or user-scoped, and state whether it survives an
      application upgrade, with a Citation per row
    - _Requirements: 5.1, 8.5_

  - [ ] 6.7 Establish the data-not-code hazard
    - Identify each customisation stored as data rather than as code, and state the consequence for version
      control and review
    - Add the evidence-versus-projection table separating stored customisation rows from the merged definition
      computed at render time
    - _Requirements: 3.5, 5.1, 8.6_

  - [ ] 6.8 Complete doc 03 with its inventory, invariants and Adopt/Change/Reject matrix
    - Write the defect and race inventory with a Citation on every row
    - Write invariants within `UI20`–`UI27`, one testable rule each
    - Write the Adopt/Change/Reject matrix, entering the data-not-code customisation model with its verdict
    - Close the cross-reference footer
    - _Requirements: 3.6, 3.7, 3.8, 4.6_

- [ ] 7. Checkpoint — all four source-analysis documents complete
  - Confirm the verifier reports `0 problems` and `git diff --check` is silent
  - Confirm every mandated topic in Requirements 6 to 9 maps to a section and at least one Citation, using the
    per-document coverage matrices (design property P8); no matrix row may be closed without a Citation
  - Confirm no fabricated line number accompanies any absence finding (design §7.4)
  - Ensure all checks pass, ask the user if questions arise.

- [ ] 8. Write `docs/ui/05-our-frontend-and-form-spec.md`
  - [ ] 8.1 Create doc 05 and consolidate the upstream evidence
    - Write T1–T4 and the T11 footer; this document reads no source, only docs 01–04,
      `docs/logic/25-our-platform-spec.md` §2–§3 and `docs/design/FINAL-SCHEMA.md`
    - Summarise the established behaviour per capability, each entry citing the doc and section that
      established it; introduce no target decision about a capability no upstream document analysed
    - Pre-allocate the invariant block `UI35`–`UI44` for new invariants only
    - _Requirements: 3.1, 3.2, 3.8, 4.1_

  - [ ] 8.2 State the Layout_Revision target narrative
    - Specify the Layout_Revision as immutable once approved, scoped by doctype, role and company, and
      carrying an effective range
    - State rules L-1 to L-5 of design §10.1 as a rule table, with the jurisdiction scope key included
    - _Requirements: 10.1, 15.6_

  - [ ] 8.3 State the stored-value-versus-displayed-text invariant
    - State the separation of stored value from displayed text as a numbered Invariant carrying the `UI`
      prefix, within the `UI35`–`UI44` block
    - Record the rejection of any design that writes formatted or translated text to a stored field, in the
      Adopt/Change/Reject matrix
    - _Requirements: 13.4, 13.5, 4.6_

  - [ ] 8.4 State the build / buy / drop matrix and enforcement-layer assignment
    - State a build, buy or drop decision for each analysed presentation capability, in the column order used
      by `docs/logic/25-our-platform-spec.md` §3
    - Link §3, and note in the document that Requirement 15.1's reference to "section 6" is stale on this
      branch; the corresponding Notes_Register request from task 1.2 already records this
    - Assign each guarantee to the lowest enforcement layer able to enforce it without cooperation from a
      caller (L1 schema, L2 triggers/RLS, L3 orchestration, L4 service code)
    - Enter the `@allow_regional` whole-function override as **excluded**, with a Citation to the upstream
      decorator read directly from the erpnext tree rather than taken from another document
    - _Requirements: 14.4, 15.1, 15.2, 15.6_

  - [ ] 8.5 Write the authoritative UI-invariant register
    - Write the single register table holding every invariant from docs 01–04 plus doc 05's new ones, with
      columns for identifier, invariant, enforcement layer and establishing document and section
    - Restate docs 01–04 invariants **by reference**; do not renumber them here — renumbering happens once, in
      task 11.2
    - _Requirements: 4.2, 4.4, 15.2_

- [ ] 9. Write `docs/design/FORM-LAYOUT.md`
  - [ ] 9.1 State the layout revision model
    - Write the T1–T3 opening and the numbered section skeleton; this document contains no analysis and no new
      decisions, only the normative restatement of what doc 05 decided
    - State the `layout_revision` structure as a SQL DDL sketch matching `docs/design/FINAL-SCHEMA.md`'s
      notation, with scope keys, effective range, immutability and content hashes
    - _Requirements: 10.1, 15.6_

  - [ ] 9.2 State the typed layout tree and its publish-time validation
    - State the `layout_node` structure as a DDL sketch with the tab → section → column → field kinds
    - State every publish-time validation rule with its identified error code — `LT-KIND`, `LT-ROOT`,
      `LT-ACYCLIC`, `LT-ORDINAL`, `LT-FIELD`, `LT-DUP`, `LT-BIND`, `LT-EXPR`, `LT-LABEL` — and state that a
      failing tree rejects the whole containing revision
    - State that structure derives from the typed tree, never from ordered break rows, referencing doc 01's
      **Reject** verdict on the break-row model
    - _Requirements: 10.2, 10.3, 10.4, 15.6_

  - [ ] 9.3 State the expression language grammar and AST rules
    - State the full grammar in EBNF, following the skeleton of design §10.3, with permitted operators and
      operand types
    - State rules X-1 to X-6: AST validation with a version hash, client/server evaluation agreement,
      publish-time rejection on validation failure, evaluation by a parser over the validated AST with dynamic
      evaluation of user-supplied text excluded, and server-authoritative field permission with the client as
      a cache that never widens the decision
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

  - [ ] 9.4 State precedence, export and the upgrade-conflict procedure
    - State the precedence and merge order producing a final field definition, as the target replacement for
      doc 03's findings
    - State the canonically-ordered diffable export format, the content hash over the canonical form, and the
      resolution procedure for an upgrade conflict between an exported revision and an incoming platform
      version
    - Close the cross-reference footer; reference `UI-SPEC.md` for every fact UI-SPEC owns rather than
      restating it
    - _Requirements: 8.3, 10.5, 15.6, 17.4_

- [ ] 10. Write `docs/design/UI-SPEC.md`
  - [ ] 10.1 State the control mapping and the grid contract
    - Write the T1–T3 opening and numbered section skeleton
    - State the field-type → control mapping as the target contract, referencing doc 01 for the upstream
      evidence
    - State grid rules G-1 to G-6: server-driven column sets, stable row identity independent of `idx` with a
      separate ordering column, a residual rule per computed column, a stated numeric row-count budget with
      virtualised rendering above it, keyboard-only completion of row creation, entry, navigation and
      deletion, and accessibility requirements covering focus order and programmatic labelling of every
      editable cell
    - _Requirements: 6.6, 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

  - [ ] 10.2 State the formatting contract and the storage binding table
    - State rules F-1 to F-5: display formatting as a pure function of stored value, locale and precision;
      canonical types `numeric(19,4)` for money, `numeric(21,9)` for quantity and rate, `numeric(9,6)` for
      percent; enumerations stored as stable lower-case codes with labels resolved at read time; rejection of
      any design writing formatted or translated text to storage
    - State the binding table naming, for each layout field, the `docs/design/FINAL-SCHEMA.md` table and
      column; verify each named table and column exists; treat FINAL-SCHEMA as strictly read-only and propose
      no edit to it
    - State that presentation metadata governs rendering only and cannot affect stored schema, and that every
      layout query reading a business table is RLS-scoped by `company_id`
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 15.3, 15.4, 15.5_

  - [ ] 10.3 State the localisation and GST contract
    - State rules J-1 to J-5: layout support for HSN and SAC codes, place of supply, GSTIN, reverse-charge
      indication and the CGST/SGST/IGST/cess breakdown display; selection of the localised field set and
      labels from the Tax_Regime associated with the document company; revision-level variation by
      jurisdiction with the doctype definition single-sourced; exclusion of `@allow_regional`; derivation of
      regional behaviour from the document's company identifier rather than a session default
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

  - [ ] 10.4 State the list, bulk and layering contract, then close the document
    - State the target list, filter and bulk-action behaviour, including the bulk failure model that replaces
      doc 04's findings
    - State rules E-1 to E-6 and the build/buy/drop matrix in doc 25 §3's column order, with each guarantee
      assigned to its enforcement layer
    - Express content as tables, the expression grammar and precedence rules; never leave prose as the sole
      statement of a rule
    - Close the cross-reference footer; reference `FORM-LAYOUT.md` for every fact it owns
    - _Requirements: 9.5, 15.1, 15.2, 15.6, 17.4_

- [ ] 11. Reconcile the normative boundary and the invariant numbering
  - [ ] 11.1 Enforce the single-source rule between UI-SPEC and FORM-LAYOUT
    - Walk the allocation table of design §6.2; for every normative fact, confirm it appears in exactly one of
      the two documents
    - Where a fact appears in both, **delete the copy in the non-owning document** and replace it with a
      relative link and section number; do not attempt to reconcile two wordings
    - Confirm no fact appears in UI-SPEC or FORM-LAYOUT that doc 05 does not decide
    - _Requirements: 15.6, 17.4_

  - [ ] 11.2 Renumber the UI invariants into a gap-free `UI1..UIn` sequence
    - Renumber once, after doc 05 exists, updating the register and every reference to an invariant in the
      same commit
    - Confirm the extracted identifier set equals `{UI1, …, UIn}` with no gaps and no duplicates, and that no
      identifier uses a reserved prefix — `M`, `A`, `F`, `T`, `R`, `V`, or a bare `U` not followed by `I`
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 12. Run the acceptance loop V1–V6
  - [ ] 12.1 Run V1 and V2 — citation verifier and whitespace
    - Run `python3 tools/verify_refs.py --docs docs/ui --app erpnext=/projects/sandbox/erpnext/erpnext --app frappe=/projects/sandbox/frappe/frappe --strict-names` from the repository root and require the literal `0 problems`
    - Replace any citation reported `AMBIGUOUS` with the full `path:line` form; treat `NAME NOTE` as advisory
      and resolve each one explicitly
    - Run `git diff --check` and require no output
    - _Requirements: 17.1, 17.2, 17.3_

  - [ ] 12.2 Run V3 — resolve every relative link
    - Confirm every relative Markdown link in `docs/ui/**`, `docs/design/UI-SPEC.md`,
      `docs/design/FORM-LAYOUT.md` and `docs/agents/NOTES-frontend.md` resolves to an existing file
    - Confirm the upstream documents are referenced by the filenames present on this branch —
      `docs/logic/18-metadata-and-runtime-ddl.md`, `docs/logic/19-permissions-and-access-control.md`,
      `docs/logic/24-reporting-framework.md` — and that the stale names used in
      `docs/agents/PROMPT-frontend-form-ui.md` appear in no link
    - _Requirements: 17.4, 17.5_

  - [ ] 12.3 Run V4 — read back every non-`.py` citation
    - The verifier's citation regex matches `.py` only, so `.js`, `.json`, `.vue` and `.html` citations are
      invisible to it and `0 problems` alone is not sufficient evidence
    - Re-read each non-`.py` citation at its cited line in the pinned tree and confirm the line exists and
      contains the construct the claim names; use read-only commands and create no files
    - Confirm every absence finding carries a Citation to the nearest related code and **no** line number for
      the absent behaviour
    - _Requirements: 5.4, 5.5, 17.1, 17.2_

  - [ ] 12.4 Run V5 and V6 — path containment and invariant set
    - Confirm `git diff --name-only` is a subset of Owned_Paths, that no Restricted_Path appears in any commit,
      and that `docs/COVERAGE.md` is unchanged
    - Confirm every changed file has a `.md`, `.json` or `.kiro` extension and that no file of any other
      extension was created, modified or deleted
    - Re-confirm the `UI1..UIn` set equality from task 11.2, and that the Notes_Register holds the Requirement
      4.5 prefix-deviation entry with both citations and the rationale
    - On any failure in V1–V6, correct the affected citations, links or paths and **re-run the loop from V1**;
      partial acceptance is not recognised
    - _Requirements: 1.1, 1.4, 2.8, 4.2, 4.5, 16.1, 16.3, 17.2, 18.3_

- [ ] 13. Final checkpoint — publish the branch
  - Confirm V1–V6 all pass in a single uninterrupted run
  - Confirm the eight deliverable files exist and no ninth file was created outside `.kiro/specs/frontend-form-ui/**`
  - Confirm commits are logical units with imperative-mood messages, staged by explicit path, on
    `kiro/spec-planning` only, with no force-push and no history rewrite, and with `docs/business-logic`
    untouched
  - Publish `kiro/spec-planning` with the provided push tooling
  - Ensure all checks pass, ask the user if questions arise.

## Notes

- The deliverable is Markdown only. No task writes, scaffolds or installs code, and no task creates a file
  outside Owned_Paths (Requirements 1.1, 1.3, 1.4, 2.8, 16.1).
- **No property-test tasks appear here, deliberately.** Design §15.1 confines checking to the artefact
  properties P1–P9 and P19, which task 12 discharges with read-only commands and review passes; the contract
  properties P10–P18 are the executable specification a future implementation inherits, and building harnesses
  for them now would require frontend code.
- Traceability from task 12 to the design's properties: 12.1 and 12.3 discharge P3 and P4; 12.2 discharges P7;
  12.4 discharges P1, P2 and P6; the coverage matrices in tasks 2.6, 4.5 and 6.3 and checkpoint 7 discharge
  P8; task 10.2's binding check discharges P9; checkpoint 13 discharges P19.
- Gates G0–G3 pass at plan time. Tasks 1.1, 5 and 13 re-assert G1, because a pull or fetch in either pinned
  tree would silently invalidate every recorded line number (design risk R2). Never pull either tree.
- Three prompt paths are corrected in every task that touches them: `grid_row_form.js` not `grid_form.js`,
  `FormPage` recorded as an absence, and the real `list/` filenames in place of `list_sidebar*`.
- Invariant blocks are pre-allocated before any document is written — 01 gets `UI1`–`UI9`, 02 gets
  `UI10`–`UI19`, 03 gets `UI20`–`UI27`, 04 gets `UI28`–`UI34`, 05 gets `UI35`–`UI44` — so two documents cannot
  claim one number. Consecutiveness is reconciled once, in task 11.2.
- Docs 01, 02 and 04 are independent and parallelisable; 03 requires 01; 05 requires all four; the two
  normative documents require 05 and are parallel with each other, reconciled in task 11.1.
- Any needed change to a Restricted_Path becomes an entry under `## Requests for the backend agent` in
  `docs/agents/NOTES-frontend.md`, and the path is left byte-identical (Requirement 16.2).

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["2.1", "3.1", "4.1"] },
    { "id": 3, "tasks": ["2.2", "3.2", "4.2"] },
    { "id": 4, "tasks": ["2.3", "3.3", "4.3"] },
    { "id": 5, "tasks": ["2.4", "3.4", "4.4"] },
    { "id": 6, "tasks": ["2.5", "3.5", "4.5"] },
    { "id": 7, "tasks": ["2.6", "3.6", "4.6"] },
    { "id": 8, "tasks": ["2.7", "3.7", "4.7"] },
    { "id": 9, "tasks": ["2.8", "3.8", "4.8"] },
    { "id": 10, "tasks": ["2.9", "3.9"] },
    { "id": 11, "tasks": ["6.1"] },
    { "id": 12, "tasks": ["6.2"] },
    { "id": 13, "tasks": ["6.3"] },
    { "id": 14, "tasks": ["6.4"] },
    { "id": 15, "tasks": ["6.5"] },
    { "id": 16, "tasks": ["6.6"] },
    { "id": 17, "tasks": ["6.7"] },
    { "id": 18, "tasks": ["6.8"] },
    { "id": 19, "tasks": ["8.1"] },
    { "id": 20, "tasks": ["8.2"] },
    { "id": 21, "tasks": ["8.3"] },
    { "id": 22, "tasks": ["8.4"] },
    { "id": 23, "tasks": ["8.5"] },
    { "id": 24, "tasks": ["9.1", "10.1"] },
    { "id": 25, "tasks": ["9.2", "10.2"] },
    { "id": 26, "tasks": ["9.3", "10.3"] },
    { "id": 27, "tasks": ["9.4", "10.4"] },
    { "id": 28, "tasks": ["11.1"] },
    { "id": 29, "tasks": ["11.2"] },
    { "id": 30, "tasks": ["12.1"] },
    { "id": 31, "tasks": ["12.2"] },
    { "id": 32, "tasks": ["12.3"] },
    { "id": 33, "tasks": ["12.4"] }
  ]
}
```
