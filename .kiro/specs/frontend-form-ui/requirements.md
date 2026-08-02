# Requirements Document

## Introduction

This feature is an **investigation and specification deliverable**, not an application. It produces a
verified, citation-backed analysis of the Frappe/ERPNext presentation layer (form rendering, the child-table
grid, form customisation mechanisms, and list views) and, from that analysis, a concrete target contract for
the presentation layer of our replacement platform.

The work product is Markdown documents in a fixed, owned set of paths. No application code, package
installation, or scaffolding is produced. A second (backend) agent owns the business-logic, schema and
tooling documents concurrently on a different branch, so file ownership is a hard constraint rather than a
convention.

The analysis binds to an already-decided backend design: the target schema in `docs/design/FINAL-SCHEMA.md`,
the four-layer enforcement rule and build/buy/drop decision format in `docs/logic/25-our-platform-spec.md`,
and the metadata engine described in `docs/logic/18-metadata-and-runtime-ddl.md`, which is the direct
upstream dependency because form layout is driven by metadata.

## Glossary

- **Frontend_Investigation**: The complete body of work defined by this specification, comprising all
  deliverable documents and their verification.
- **UI_Doc**: Any one of the five investigation documents `docs/ui/01-form-rendering-and-layout-engine.md`,
  `docs/ui/02-child-table-grid-engine.md`, `docs/ui/03-form-customisation-and-layout-overrides.md`,
  `docs/ui/04-list-view-filters-and-bulk-actions.md`, `docs/ui/05-our-frontend-and-form-spec.md`.
- **Target_UI_Contract**: The consolidated target specification recorded in `docs/design/UI-SPEC.md` and
  `docs/design/FORM-LAYOUT.md`.
- **Notes_Register**: The file `docs/agents/NOTES-frontend.md`, holding open questions and requests directed
  at the backend agent.
- **Pinned_Sources**: The two read-only upstream trees at the fixed commits — `frappe` at
  `/projects/sandbox/frappe/frappe`, commit `5da68e856ca7f036b20d2583167b9d00c4a8db56`, and `erpnext` at
  `/projects/sandbox/erpnext/erpnext`, commit `ceefd4add77715d2762c19db337fb83e28a477de`.
- **Citation**: A reference of the form `path:line` identifying an exact line in Pinned_Sources; `erpnext`
  citations are relative to `/projects/sandbox/erpnext/erpnext`, and `frappe` citations are prefixed
  `frappe/` and relative to `/projects/sandbox/frappe/frappe`.
- **Citation_Verifier**: The existing tool invoked as
  `python3 tools/verify_refs.py --docs docs/ui --app erpnext=/projects/sandbox/erpnext/erpnext --app frappe=/projects/sandbox/frappe/frappe --strict-names`.
- **Behavioural_Claim**: Any statement in a UI_Doc asserting what upstream Frappe or ERPNext code does.
- **Invariant**: A numbered, testable rule stated in a UI_Doc, identified with the prefix `UI` and numbered
  from `UI1` upward.
- **Owned_Path**: Any path in `docs/ui/**`, `docs/design/UI-SPEC.md`, `docs/design/FORM-LAYOUT.md`,
  `.kiro/specs/frontend-*/**`, or `docs/agents/NOTES-frontend.md`.
- **Restricted_Path**: Any path in `docs/logic/**`, `docs/scenarios/**`, `docs/reveng/**`,
  `docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`, `docs/INVESTIGATION-PLAN.md`, `README.md`, `tools/**`,
  `schema/**`, or `semantic-review/**`.
- **Layout_Revision**: A versioned, approved, immutable form-layout record in the target design, scoped by
  doctype, role and company, carrying an effective range, and stored in the presentation-metadata table
  `layout_revision` specified by `docs/design/FORM-LAYOUT.md`.
- **Layout_Tree**: The typed hierarchy tab → section → column → field that a Layout_Revision contains, stored
  in the presentation-metadata table `layout_node` specified by `docs/design/FORM-LAYOUT.md`.
- **Expression_Language**: The constrained declarative language specified by the Target_UI_Contract for
  visibility, mandatory, read-only and collapsible conditions.
- **Grid_Contract**: The section of the Target_UI_Contract governing child-table data entry.
- **Formatting_Contract**: The section of the Target_UI_Contract governing display formatting and
  localisation of values.
- **Tax_Regime**: A jurisdiction-scoped set of tax rules and associated field sets, held as data.

## Requirements

### Requirement 1

**User Story:** As the platform architect, I want the presentation-layer investigation to remain a
documents-only exercise, so that no implementation decisions are pre-empted by unreviewed code.

#### Acceptance Criteria

1. THE Frontend_Investigation SHALL produce Markdown documents as the only work product.
2. WHEN a capability of the target platform is described, THE Frontend_Investigation SHALL express the
   description as a written contract in a UI_Doc or in the Target_UI_Contract.
3. IF a task appears to require executable frontend code, application scaffolding, or installation of a
   package, THEN THE Frontend_Investigation SHALL record the requirement as text in the Target_UI_Contract
   and leave the repository free of that code, scaffolding, or package.
4. THE Frontend_Investigation SHALL leave every file with an extension other than `.md`, `.kiro`, or `.json`
   unchanged.

### Requirement 2

**User Story:** As a reviewer, I want a fixed and complete deliverable set, so that completion is decidable
without interpretation.

#### Acceptance Criteria

1. THE Frontend_Investigation SHALL create `docs/ui/01-form-rendering-and-layout-engine.md`.
2. THE Frontend_Investigation SHALL create `docs/ui/02-child-table-grid-engine.md`.
3. THE Frontend_Investigation SHALL create `docs/ui/03-form-customisation-and-layout-overrides.md`.
4. THE Frontend_Investigation SHALL create `docs/ui/04-list-view-filters-and-bulk-actions.md`.
5. THE Frontend_Investigation SHALL create `docs/ui/05-our-frontend-and-form-spec.md`.
6. THE Frontend_Investigation SHALL create `docs/design/UI-SPEC.md` and `docs/design/FORM-LAYOUT.md`.
7. THE Frontend_Investigation SHALL create `docs/agents/NOTES-frontend.md`.
8. THE Frontend_Investigation SHALL restrict created files to the seven paths named in criteria 1 to 7 and to
   `.kiro/specs/frontend-form-ui/**`.

### Requirement 3

**User Story:** As a reviewer, I want every document to follow one structural standard, so that documents are
comparable with the existing `docs/logic/` set and reviewable at a fixed depth.

#### Acceptance Criteria

1. THE UI_Doc SHALL open with a blockquote header naming the Pinned_Sources and both pinned commit hashes.
2. THE UI_Doc SHALL organise content under numbered sections.
3. WHEN a mechanism involves ordered steps, THE UI_Doc SHALL state the exact algorithm, including the order of
   operations and the branch conditions, rather than a prose summary.
4. THE UI_Doc SHALL include at least one worked example per numbered section that describes a mechanism.
5. WHERE a mechanism depends on stored state, THE UI_Doc SHALL include an evidence-versus-projection table
   distinguishing values read from storage from values derived at render time.
6. THE UI_Doc SHALL include a defect and race inventory in which every entry carries at least one Citation.
7. THE UI_Doc SHALL include an Adopt / Change / Reject matrix stating the target design decision for each
   analysed capability.
8. THE UI_Doc SHALL end with a cross-reference footer listing every related document by relative path.

### Requirement 4

**User Story:** As the owner of the invariant register, I want presentation-layer invariants in a reserved
numbering range, so that invariants from separate tranches never collide.

#### Acceptance Criteria

1. THE UI_Doc SHALL identify each Invariant with the prefix `UI` followed by an integer.
2. THE Frontend_Investigation SHALL number Invariants consecutively from `UI1` across the UI_Doc set, without
   duplicating an identifier.
3. THE Frontend_Investigation SHALL reserve the identifier ranges `M1`–`M69` for the production documents and
   `A1`–`A26` for the asset documents, SHALL reserve the prefixes `F`, `T`, `R`, and `V` for the trade
   documents, and SHALL reserve the prefix `U`, which `docs/logic/30-upstream-trade-and-parties.md` uses for
   `U1`–`U8` and `docs/design/FINAL-SCHEMA.md` section 9 uses separately for `U1`.
4. THE Frontend_Investigation SHALL use the prefix `UI` for every Invariant introduced by the
   Frontend_Investigation.
5. THE Notes_Register SHALL record the deviation from the `U` prefix stated in
   `docs/agents/PROMPT-frontend-form-ui.md`, together with the evidence that the prefix `U` is already in use
   and the collision-avoidance rationale for the prefix `UI`.
6. THE UI_Doc SHALL state each Invariant as a single testable rule whose violation is observable.

### Requirement 5

**User Story:** As a reviewer, I want every behavioural claim traceable to a read line of pinned source, so
that the analysis is verifiable rather than asserted.

#### Acceptance Criteria

1. THE UI_Doc SHALL attach at least one Citation to every Behavioural_Claim.
2. THE Frontend_Investigation SHALL express each `erpnext` Citation as a path relative to
   `/projects/sandbox/erpnext/erpnext`.
3. THE Frontend_Investigation SHALL express each `frappe` Citation with the prefix `frappe/` and as a path
   relative to `/projects/sandbox/frappe/frappe`.
4. THE Frontend_Investigation SHALL cite only lines read from Pinned_Sources during the investigation.
5. IF a required behaviour cannot be located in Pinned_Sources, THEN THE UI_Doc SHALL record the absence as a
   finding, with a Citation to the nearest related code, and SHALL omit any line number for the absent
   behaviour.
6. WHERE upstream code is unfinished or unreachable, THE UI_Doc SHALL state that condition explicitly with a
   Citation.

### Requirement 6

**User Story:** As an implementer of the future form runtime, I want the upstream form rendering and layout
engine documented exactly, so that our layout model is designed against known behaviour.

#### Acceptance Criteria

1. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the runtime construction order
   of a form across `Form`, `Layout`, `Section`, `Column`, and `Tab`, with Citations into
   `frappe/public/js/frappe/form/`, and SHALL state the point at which `frappe.views.FormFactory` constructs
   the form, with a Citation into `frappe/public/js/frappe/views/formview.js`.
2. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the algorithm that converts the
   ordered `Meta.fields` list, together with `Tab Break`, `Section Break`, and `Column Break` rows, into a
   visual tree.
3. WHEN a break row is missing, duplicated, or out of order, THE `docs/ui/01-form-rendering-and-layout-engine.md`
   document SHALL state the resulting rendered structure.
4. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the evaluation scope, evaluation
   timing, and failure behaviour of `depends_on`, `mandatory_depends_on`, `read_only_depends_on`, and
   `collapsible_depends_on`.
5. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the render effect of `hidden`,
   `read_only`, `bold`, `allow_on_submit`, `in_list_view`, `print_hide`, and `translatable`.
6. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL map each field type to the control
   implemented in `frappe/public/js/frappe/form/controls/`, covering `Link`, `Dynamic Link`, `Table`,
   `Table MultiSelect`, `Select`, `Currency`, `Float`, `Percent`, `Duration`, `Geolocation`, `Barcode`,
   `Signature`, `Rating`, `JSON`, `Code`, `Markdown`, and `Attach`.
7. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the precision resolution order
   from field precision, through `System Settings.float_precision`, to currency `smallest_fraction`, and
   SHALL identify each point at which a displayed value diverges from the stored value.
8. THE `docs/ui/01-form-rendering-and-layout-engine.md` document SHALL state the dirty-state model and the
   re-render cost of `refresh_field`, `set_value`, and `toggle_display`.
9. IF a class or file named in this specification is absent from Pinned_Sources, THEN THE UI_Doc SHALL record
   the absence as a finding under the convention stated in Requirement 5 criterion 5, SHALL name the absent
   class or file, and SHALL omit any line number for the absent class or file.

### Requirement 7

**User Story:** As a designer of high-volume data entry, I want the child-table grid documented in detail, so
that the target grid contract addresses the known limits of the upstream grid.

#### Acceptance Criteria

1. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the behaviour of `grid.js`, `grid_row.js`,
   `grid_row_form.js`, and `grid_pagination.js`, with Citations.
2. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the algorithm that selects visible
   columns from `in_list_view` and `columns` width units, including the total-width budget and the storage
   location of user column configuration.
3. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the effect of row addition, removal, and
   reordering on `idx`, including the `idx` values remaining after a row is deleted.
4. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the behaviour of the expanded row form,
   bulk edit, paste-from-spreadsheet input, and grid template download and upload.
5. WHILE unsaved rows are present, THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the
   behaviour of grid pagination.
6. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the validation order from client control,
   through `validate`, to the server, and SHALL identify which row-level errors reach the user interface.
7. THE `docs/ui/02-child-table-grid-engine.md` document SHALL state the measured or code-derived complexity
   of grid operations at 500 child rows and SHALL name each operation whose cost grows as the square of the
   row count.

### Requirement 8

**User Story:** As a release manager, I want every form-customisation mechanism and its precedence
documented, so that customisation hazards are known before the target contract is fixed.

#### Acceptance Criteria

1. THE `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL state what `Customize Form`
   writes and to which tables, with Citations into `frappe/custom/doctype/customize_form/`.
2. THE `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL state the effect of
   `Custom Field`, `Property Setter`, `DocType Layout`, `Workspace`, `Form Tour`, `Client Script`, and
   `Custom HTML Block` on a rendered form.
3. WHEN more than one customisation mechanism targets a single field, THE
   `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL state the exact precedence and
   merge order producing the final field definition.
4. THE `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL cross-reference
   `docs/logic/18-metadata-and-runtime-ddl.md` for metadata cache behaviour instead of restating the
   metadata assembly algorithm.
5. THE `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL classify each customisation
   mechanism as site-global, role-scoped, or user-scoped, and SHALL state whether each mechanism survives an
   application upgrade.
6. THE `docs/ui/03-form-customisation-and-layout-overrides.md` document SHALL identify each customisation
   that is stored as data rather than as code and SHALL state the consequence for version control and review.

### Requirement 9

**User Story:** As a designer of list and bulk workflows, I want upstream list views documented, so that
filtering, permission interaction and bulk failure reporting are specified from evidence.

#### Acceptance Criteria

1. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL state the behaviour of list
   settings, the sidebar, group-by, and saved filters, with Citations into `frappe/public/js/frappe/list/`.
2. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL state the algorithm that constructs
   a filter expression and transmits the filter expression to the server.
3. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL cross-reference
   `docs/logic/19-permissions-and-access-control.md` for permission filtering and SHALL state where
   permission filtering combines with user-supplied filters.
4. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL state, for each of `Kanban`,
   `Calendar`, `Gantt`, `Tree`, `Image`, `Map`, and `Dashboard`, whether the view is driven by metadata.
5. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL state the failure reporting model of
   bulk edit, bulk submit, bulk cancel, and bulk delete, including the outcome for the remaining documents
   when one document fails.
6. THE `docs/ui/04-list-view-filters-and-bulk-actions.md` document SHALL state how `listview_settings`
   derives indicator and status text and SHALL name the source of that text.

### Requirement 10

**User Story:** As the platform architect, I want the target presentation-layer specification to treat layout
as versioned data, so that a form definition is reviewable, diffable and immutable once approved.

#### Acceptance Criteria

1. THE `docs/ui/05-our-frontend-and-form-spec.md` document SHALL specify the Layout_Revision as immutable
   once approved, scoped by doctype, role and company, and carrying an effective range.
2. THE Target_UI_Contract SHALL specify the Layout_Tree as a typed hierarchy of tab, section, column and
   field nodes, and SHALL specify validation of the Layout_Tree at publish time.
3. IF a Layout_Tree fails publish-time validation, THEN THE Target_UI_Contract SHALL specify rejection of the
   Layout_Revision with an identified validation error.
4. THE Target_UI_Contract SHALL specify derivation of structure from the typed Layout_Tree rather than from
   ordered break rows.
5. THE Target_UI_Contract SHALL specify Layout_Revision export in a diffable textual form held in version
   control, and SHALL specify the resolution procedure for an upgrade conflict between an exported
   Layout_Revision and an incoming platform version.

### Requirement 11

**User Story:** As a security reviewer, I want conditional field behaviour expressed in a constrained
language evaluated identically on both sides, so that no user-authored text is executed.

#### Acceptance Criteria

1. THE Target_UI_Contract SHALL define the Expression_Language grammar, its permitted operators, and its
   permitted operand types.
2. THE Target_UI_Contract SHALL specify parsing of every Expression_Language expression into a validated
   abstract syntax tree carrying a version hash.
3. WHEN an Expression_Language expression is evaluated, THE Target_UI_Contract SHALL specify identical
   results for client-side and server-side evaluation of the same expression, the same document values, and
   the same version hash.
4. IF an Expression_Language expression fails validation, THEN THE Target_UI_Contract SHALL specify rejection
   of the containing Layout_Revision at publish time.
5. THE Target_UI_Contract SHALL specify evaluation of Expression_Language expressions by a parser over the
   validated abstract syntax tree, and SHALL state that dynamic evaluation of user-supplied text is excluded
   from the design.
6. THE Target_UI_Contract SHALL specify server-authoritative resolution of field-level permission and
   visibility, with the client holding a cache of the server decision.

### Requirement 12

**User Story:** As a data-entry user, I want the grid contract to guarantee stable rows and bounded
performance, so that large child tables remain usable and correct.

#### Acceptance Criteria

1. THE Grid_Contract SHALL specify server-driven column sets for each child table.
2. THE Grid_Contract SHALL specify row identity as a stable identifier independent of `idx`.
3. THE Grid_Contract SHALL specify the residual rule for each computed column, stating which side owns the
   computed value and when the value is recomputed.
4. THE Grid_Contract SHALL state a numeric row-count budget and SHALL specify virtualised rendering above
   that budget.
5. THE Grid_Contract SHALL specify keyboard-only completion of row creation, field entry, row navigation and
   row deletion.
6. THE Target_UI_Contract SHALL state the accessibility requirements that apply to the grid, including
   focus order and programmatic labelling of each editable cell.

### Requirement 13

**User Story:** As the owner of the target schema, I want display formatting kept strictly separate from
storage, so that stored values remain canonical and machine-comparable.

#### Acceptance Criteria

1. THE Formatting_Contract SHALL specify display formatting as a pure function of the stored value, the
   active locale, and the field precision.
2. THE Formatting_Contract SHALL specify storage of numeric values in the canonical schema types
   `numeric(19,4)` for money, `numeric(21,9)` for quantity and rate, and `numeric(9,6)` for percent.
3. THE Formatting_Contract SHALL specify storage of enumerated values as stable lower-case codes and
   SHALL specify resolution of the display label at read time.
4. IF a proposed design writes a formatted or translated string to a stored field, THEN THE
   Target_UI_Contract SHALL reject the proposed design and SHALL record the rejection in the Adopt / Change /
   Reject matrix.
5. THE `docs/ui/05-our-frontend-and-form-spec.md` document SHALL state the separation of stored value from
   displayed text as a numbered Invariant carrying the prefix `UI`.

### Requirement 14

**User Story:** As a compliance stakeholder in India, I want GST treated as a first-class layout concern, so
that jurisdiction-specific field sets are supported without forking a doctype.

#### Acceptance Criteria

1. THE Target_UI_Contract SHALL specify layout support for HSN and SAC codes, place of supply, GSTIN,
   reverse charge indication, and the CGST, SGST, IGST and cess breakdown display.
2. THE Target_UI_Contract SHALL specify selection of a localised field set and localised labels from the
   Tax_Regime associated with the document company.
3. WHERE more than one Tax_Regime is configured, THE Target_UI_Contract SHALL specify variation of the
   Layout_Revision by jurisdiction while the underlying doctype definition remains single-sourced.
4. THE Target_UI_Contract SHALL exclude the ERPNext `@allow_regional` whole-function override mechanism from
   the target design and SHALL record that exclusion in the Adopt / Change / Reject matrix with a Citation to
   the upstream mechanism.
5. THE Target_UI_Contract SHALL specify derivation of regional behaviour from the company identifier carried
   by the document rather than from a session default.

### Requirement 15

**User Story:** As the platform architect, I want the target presentation contract to respect the existing
four-layer enforcement rule and decision format, so that the frontend specification composes with the
backend specification.

#### Acceptance Criteria

1. THE `docs/ui/05-our-frontend-and-form-spec.md` document SHALL state a build, buy, or drop decision for
   each analysed presentation capability, in the format used by `docs/logic/25-our-platform-spec.md` section 3.
2. THE Target_UI_Contract SHALL assign each specified guarantee to the lowest enforcement layer able to
   enforce that guarantee without cooperation from a caller.
3. THE Target_UI_Contract SHALL specify presentation metadata as governing rendering only, with no effect on
   stored schema.
4. THE `docs/design/FORM-LAYOUT.md` document SHALL specify the presentation-metadata tables
   `layout_revision` and `layout_node` as the concrete form of the `ui_field` and `ui_layout` capability that
   `docs/logic/25-our-platform-spec.md` section 3 commits to building.
5. WHERE a specified layout field is bound to business data, THE Target_UI_Contract SHALL name the target
   table and the target column as defined in `docs/design/FINAL-SCHEMA.md`.
6. WHERE a specified layout field is stored as presentation metadata, THE Target_UI_Contract SHALL name the
   target table and the target column as defined in `docs/design/FORM-LAYOUT.md`.
7. THE Frontend_Investigation SHALL treat `docs/design/FINAL-SCHEMA.md` as read-only and SHALL leave
   `docs/design/FINAL-SCHEMA.md` unchanged.
8. THE Notes_Register SHALL record that `docs/design/FORM-LAYOUT.md` specifies the `layout_revision` and
   `layout_node` tables pending confirmation by the backend agent, and SHALL name the divergence from
   `docs/design/FINAL-SCHEMA.md`, which defines neither table.
9. THE Target_UI_Contract SHALL specify row-level security scoping by `company_id` for every layout query
   that reads a business table.
10. THE Target_UI_Contract SHALL express its content as tables, an expression grammar, and precedence rules,
    and SHALL avoid prose as the sole statement of a rule.

### Requirement 16

**User Story:** As the backend agent working concurrently, I want the file-ownership boundary enforced, so
that two parallel workstreams never overwrite each other.

#### Acceptance Criteria

1. THE Frontend_Investigation SHALL confine every creation, edit, move, rename and deletion to Owned_Paths.
2. IF a change to a Restricted_Path appears necessary, THEN THE Frontend_Investigation SHALL record the
   request in the Notes_Register under the heading `## Requests for the backend agent` and SHALL leave the
   Restricted_Path unchanged.
3. THE Frontend_Investigation SHALL leave `docs/COVERAGE.md` unchanged.
4. THE Notes_Register SHALL record every open question raised during the Frontend_Investigation.

### Requirement 17

**User Story:** As a reviewer, I want a mechanical acceptance gate, so that document quality is verified
rather than assumed.

#### Acceptance Criteria

1. WHEN the Citation_Verifier is executed from the repository root over `docs/ui`, THE Frontend_Investigation
   SHALL produce a report of 0 problems.
2. IF the Citation_Verifier reports one or more problems, THEN THE Frontend_Investigation SHALL correct the
   affected Citations and SHALL re-run the Citation_Verifier until the report states 0 problems.
3. THE Notes_Register SHALL record that the Citation_Verifier verifies only Citations whose path ends in
   `.py`, referencing the mandatory `.py` extension of the citation pattern at `tools/verify_refs.py:35` and
   the Python-only symbol index built at `tools/verify_refs.py:62`.
4. THE Frontend_Investigation SHALL treat a Citation_Verifier report of 0 problems as necessary and
   insufficient evidence of Citation correctness.
5. THE Frontend_Investigation SHALL re-read every Citation whose path ends in an extension other than `.py`
   at the cited line in Pinned_Sources and SHALL confirm that the cited line contains the construct named by
   the Behavioural_Claim carrying that Citation.
6. IF the re-reading required by criterion 5 does not confirm that the cited line contains the construct
   named by the Behavioural_Claim, THEN THE Frontend_Investigation SHALL correct or remove that Citation
   before the acceptance gate passes.
7. WHEN `git diff --check` is executed, THE Frontend_Investigation SHALL produce no whitespace or conflict
   marker output.
8. THE Frontend_Investigation SHALL ensure that every relative Markdown link in a UI_Doc, in the
   Target_UI_Contract, and in the Notes_Register resolves to an existing file in the repository.
9. THE Frontend_Investigation SHALL reference the upstream documents by the filenames present on the branch,
   specifically `docs/logic/18-metadata-and-runtime-ddl.md`,
   `docs/logic/19-permissions-and-access-control.md`, and `docs/logic/24-reporting-framework.md`.

### Requirement 18

**User Story:** As the repository maintainer, I want a constrained version-control workflow, so that the
concurrent branches remain independent and auditable.

#### Acceptance Criteria

1. THE Frontend_Investigation SHALL commit only to the branch `kiro/spec-planning`.
2. THE Frontend_Investigation SHALL group commits into logical units and SHALL write each commit message in
   the imperative mood.
3. THE Frontend_Investigation SHALL stage only Owned_Paths in each commit.
4. WHEN the branch is published, THE Frontend_Investigation SHALL use the provided push tooling and SHALL
   publish only `kiro/spec-planning`.
5. THE Frontend_Investigation SHALL leave the branch `docs/business-logic` unmerged, unrebased, and
   unmodified.
6. THE Frontend_Investigation SHALL exclude force-push and history rewriting from every version-control
   operation performed.
