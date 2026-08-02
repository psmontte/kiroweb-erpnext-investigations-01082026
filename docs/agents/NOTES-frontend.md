This is the Notes_Register for the frontend form/UI investigation. It is the **only** channel through which
this investigation requests a change to a Restricted_Path; every path named in a request below is left
byte-identical by the frontend agent (Requirement 16.2).

Citation roots: `frappe/…` paths are relative to `/projects/sandbox/frappe/frappe`; unprefixed source paths
are relative to `/projects/sandbox/erpnext/erpnext`. Repository-relative paths (`docs/…`, `tools/…`) are
relative to the repository root. Both pinned trees are present as **shallow depth-1** checkouts at
`frappe` = `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
`erpnext` = `ceefd4add77715d2762c19db337fb83e28a477de`.

## Open questions

### Q1 — Invariant prefix: this investigation uses `UI`, the prompt instructs `U` (Requirement 4.5)

| Aspect | Statement |
|---|---|
| Instruction | [`PROMPT-frontend-form-ui.md`](PROMPT-frontend-form-ui.md):87 instructs the invariant prefix `U`, numbered from `U1`. |
| Deviation | Every invariant introduced by this investigation carries the prefix **`UI`**, numbered from **`UI1`**. |
| Status | Deviation taken, recorded, and resolved entirely inside Owned_Paths. No answer is required from the backend agent; the entry exists because Requirement 4.5 mandates it. |

**Evidence that `U` is already occupied, twice and independently:**

- [`docs/logic/30-upstream-trade-and-parties.md`](../logic/30-upstream-trade-and-parties.md):942-956 — the
  upstream trade and parties register defines `U1` through `U8`.
- [`docs/design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md):734 — the schema register defines a separate and
  unrelated `U1`, concerning `item_uom` and the freezing of `stock_uom_id`.

**Why the collision is substantive rather than cosmetic.** `U7` in the trade register is *"No enum column
contains a translated string"* — the very invariant the prompt instructs this investigation to preserve, and
the one the formatting contract (design rule F-3, F-4) would most want to reference. A bare `U` number in a
presentation document would therefore be genuinely ambiguous to a reader, not merely untidy.

**Rationale.** The prompt reserves `M`, `A` and `F`/`T`/`R`/`V`, but the trade document demonstrably also uses
`U`, so the prompt's reserved list is incomplete and its two instructions — *avoid the reserved prefixes* and
*use `U`* — conflict with each other. The deviation honours the rule over the literal. `U` is now itself a
reserved prefix per Requirement 4.3, and the reconciliation of `UI1..UIn` into a gap-free sequence happens
once, at the end of the investigation.

**Restricted_Path impact: none.** Nothing in `docs/logic/**` or `docs/design/FINAL-SCHEMA.md` changes; the
collision is resolved wholly within Owned_Paths.

### Q2 — Three source paths named in the prompt do not exist at the pinned commit

All three are corrected in the task plan and in every document that touches them. Recorded here so the
divergence from the prompt is visible rather than silently absorbed.

| Named in the prompt | State at the pinned commit | How the investigation proceeds |
|---|---|---|
| `FormPage` — [`PROMPT-frontend-form-ui.md`](PROMPT-frontend-form-ui.md):94, carried into Requirement 6.1 | Does not exist. `grep -rn "FormPage" frappe/public/js/frappe/form/` returns no matches. | Doc 01 records it as an **absence finding** per design §7.4: what was searched for and where, a Citation to the nearest related code, and **no line number** for the absent class. The real units are `form.js`, `layout.js`, `section.js`, `column.js`, `tab.js` and `views/formview.js`. |
| `grid_form.js` — [`PROMPT-frontend-form-ui.md`](PROMPT-frontend-form-ui.md):109, carried into Requirement 7.1 and design §7.1 | No `grid_form.js`. The file is `frappe/public/js/frappe/form/grid_row_form.js`. | Doc 02 cites `grid_row_form.js`. |
| `list_sidebar*` — design §7.1, from the prompt's sidebar item at [`PROMPT-frontend-form-ui.md`](PROMPT-frontend-form-ui.md):130 | No `list_sidebar.js`. Only `frappe/public/js/frappe/list/list_sidebar_group_by.js` and `list_sidebar_stat.html` exist. | Doc 04 cites the files that actually exist; sidebar composition is documented from `list_view.js` and `base_list.js`. |

**Resolved.** All three paths above remain absent from the pinned trees, and the table is retained because the
originating prompt still names them. The requirement text has since been amended in three places, so that no
acceptance criterion names an absent unit any longer: Requirement 6.1 names `Tab` and
`frappe.views.FormFactory` in place of `FormPage`, Requirement 7.1 names `grid_row_form.js` in place of
`grid_form.js`, and Requirement 6.6 names the canonical fieldtype `Markdown Editor` in place of `Markdown`;
`grep -c FormPage` against [`requirements.md`](../../.kiro/specs/frontend-form-ui/requirements.md) returns
**0**. Requirement 6.9 generalises the handling convention rather than leaving it to this register: an absent
**class, file or fieldtype** named anywhere in the specification is recorded as an absence finding, named
explicitly, with no line number. The `Markdown` case then ended differently from the other three — because the
requirement itself was corrected, doc 01 records no absence for it at all, §5.3's matrix being seventeen rows
closing seventeen mandated types with every one resolving to a control class that exists. What survives is
recorded instead as an upstream **naming hazard** at doc 01 §5.10 finding 2
([`docs/ui/01-form-rendering-and-layout-engine.md`](../ui/01-form-rendering-and-layout-engine.md)):
`make_control` derives its class name by string concatenation, so a near-miss spelling of a canonical
fieldtype resolves silently to a class that was never declared.
Doc 01 §1.5 still carries the `FormPage` absence finding, the one instance that remains an absence finding,
because that upstream class genuinely does not exist whatever the requirement says. The distinction is the
lesson worth keeping: a name absent from **upstream** is an absence finding in the deliverable, whereas a name
absent from upstream that the **specification itself** wrongly mandated is a specification defect, and the fix
is to correct the specification, not to document the absence.

### Q3 — `layout_revision` and `layout_node` are specified here, pending backend confirmation (Requirement 15.8)

| Aspect | Statement |
|---|---|
| What this investigation specifies | `docs/design/FORM-LAYOUT.md` specifies the presentation-metadata tables **`layout_revision`** and **`layout_node`** as the concrete form of the `ui_field` / `ui_layout` capability that doc 25 §3 (subsection 3.1) commits to **BUILD**ing. |
| Status | **Pending confirmation by the backend agent.** The specification stands and is used; it is not held open awaiting an answer. |
| Named divergence | [`docs/design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) **defines neither table**. Searching it for `ui_field`, `ui_layout`, `layout_revision` and `layout_node` returns no matches. |
| Restricted_Path impact | None. `docs/design/FINAL-SCHEMA.md` is left byte-identical (Requirement 15.7). Both tables are defined wholly inside an Owned_Path. |

**Evidence that doc 25 commits to the capability.**
[`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md):79 states:

```
| Presentation metadata | **BUILD** — `ui_field` / `ui_layout`, describes rendering only; cannot affect storage | L4 |
```

and [`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md):259 lists `ui_field` again among
the settings tables the orchestration engine must support. The heading at
[`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md):66 is
`## 3. Build / buy / drop, by capability`, and line 79 falls inside its subsection
`### 3.1 Schema and metadata (doc 18)`.

**Why this is a note rather than a blocking request.** The divergence is registered, not hidden. Because
`FORM-LAYOUT.md` owns both table definitions, the design §10.5 binding table resolves every presentation-metadata
row without FINAL-SCHEMA, so nothing in this investigation waits on the answer. A **differing** backend answer
— different table or column names for the same capability — triggers reconciliation of the §10.5 binding table
and the FORM-LAYOUT DDL in a single commit (design risk R11). The corresponding confirmation request to the
backend agent is R4 below.

### Q4 — Citation_Verifier scope: only Citations ending in `.py` are checked (Requirement 17.3)

This is a **standing scope note** about what the acceptance gate proves. It is not a request; the request to
extend the tool is R2 below, and this note holds whether or not that request is ever actioned.

| Aspect | Statement |
|---|---|
| Scope of the gate | The Citation_Verifier checks **only** Citations whose path ends in `.py`. Citations to any other extension are not matched, not counted and not reported. |
| Consequence | A report of `0 problems` is **necessary and insufficient** evidence of Citation correctness (Requirement 17.4). It is not treated as proof that the non-`.py` Citations are correct. |
| What covers the remainder | The V4 read-back: every Citation whose path ends in an extension other than `.py` is re-read at its cited line in Pinned_Sources and confirmed to contain the construct the claim names (Requirement 17.5); any that does not confirm is corrected or removed before the gate passes (Requirement 17.6). |

**Evidence, read directly from the tool:**

- [`tools/verify_refs.py`](../../tools/verify_refs.py):35 — the citation pattern **requires the `.py`
  extension**: `CITATION = re.compile(r"([A-Za-z_][\w/]*(?:/[\w/]+)*\.py):(\d+)(?:-(\d+))?")`.
- [`tools/verify_refs.py`](../../tools/verify_refs.py):62 — the symbol index behind `--strict-names` is built
  with Python `ast` (`tree = ast.parse(...)`), which is structurally Python-only.

**Relationship to R2.** R2 asks for the tool to be extended and sets out the full consequence for this
deliverable, whose citations are almost entirely `frappe/public/js/**`. That request remains **open and
non-blocking**. This entry records the scope limit as a permanent property of the gate, so the strength of a
`0 problems` report is never overstated even after R2 is closed.

## Requests for the backend agent

| # | Restricted path | Request | Status |
|---|---|---|---|
| R1 | (workspace, not a file) | Fetch both pinned trees at the stated commits | **Closed** — satisfied |
| R2 | `tools/verify_refs.py` | Extend the citation regex beyond `.py`; gate `--strict-names` on a Python-only symbol index | **Open, non-blocking** — mitigated |
| R3 | `docs/logic/25-our-platform-spec.md` | None; withdrawn — Requirement 15.1 now cites section 3 | **Withdrawn** |
| R4 | `docs/design/FINAL-SCHEMA.md` | Confirm `layout_revision` / `layout_node` as the intended binding | **Confirmation requested, not blocking** |

### R1 — Pinned source trees: request closed

| Field | Statement |
|---|---|
| Path | Workspace state, not a repository file. |
| Requested change | None outstanding. |
| Reason it existed | Design §2.1 recorded gate G0 as **failing**: neither `/projects/sandbox/frappe/frappe` nor `/projects/sandbox/erpnext/erpnext` was present, so no Citation could be read and docs 01–04 were blocked. |
| Resolution | Both trees are now present at the exact pinned commits — `frappe` = `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `erpnext` = `ceefd4add77715d2762c19db337fb83e28a477de`. Gates G0 and G1 pass. Docs 01–04 are unblocked. |

**Constraint that now attaches to both trees.** They are **shallow depth-1** checkouts. Neither tree may be
pulled, fetched or checked out for the remainder of the investigation: doing so silently invalidates every
line number this investigation records (design risk R2). `git log` history is unavailable by design; every
file is nonetheless present at the pinned commit, which is all a Citation needs.

### R2 — `tools/verify_refs.py` cannot verify non-Python citations

| Field | Statement |
|---|---|
| Path | [`tools/verify_refs.py`](../../tools/verify_refs.py) — a Restricted_Path, left byte-identical. |
| Requested change | (a) Extend the `CITATION` regex beyond the `.py` extension so `.js`, `.json`, `.vue` and `.html` citations are matched and range-checked. (b) Gate `--strict-names` on a Python-only symbol index, so non-Python citations are **range-checked but not name-checked** rather than being skipped entirely. |
| Reason | Without (a), the majority of this investigation's citations are invisible to the tool. |

**Evidence, read directly from the tool:**

- `tools/verify_refs.py:35` — the citation pattern is
  `CITATION = re.compile(r"([A-Za-z_][\w/]*(?:/[\w/]+)*\.py):(\d+)(?:-(\d+))?")`. The `.py` extension is
  mandatory in the pattern, so a citation to any other extension is not matched at all.
- `tools/verify_refs.py:62` — the symbol index backing `--strict-names` is built with `ast.parse`, which is
  structurally Python-only and cannot index a JavaScript file.

**Consequence, stated plainly.** This investigation cites `frappe/public/js/frappe/form/**` and
`frappe/public/js/frappe/list/**` almost entirely. Those citations are neither counted nor reported — an
out-of-range JavaScript line number passes silently. Requirement 17.1's `0 problems` is therefore satisfiable
**vacuously** for most of this deliverable. A passing verifier run is **necessary but not sufficient**
evidence of citation correctness.

**Mitigation already in the plan, pending the change.** The tool is still run with `--strict-names` and must
report `0 problems`, which fully verifies every `.py` citation. Task 12.3 (design §8.4 V4) adds a manual
read-back check: every non-`.py` citation is re-read at its cited line in the pinned tree and confirmed to
contain the construct the claim names. `tools/**` is a Restricted_Path, so the frontend agent does not make
this change itself.

### R3 — Doc 25's build/buy/drop format is in §3, not §6 — **withdrawn**

**This request is withdrawn.** It is retained for the audit trail, not for action. Requirement 15.1 now cites
**section 3** of doc 25 directly, so the requirement and the branch agree: **no change is needed** to anything
under `docs/logic/**`. No answer and no file change is requested of the backend agent.

| Field | Statement |
|---|---|
| Path | [`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md) — a Restricted_Path, left byte-identical. |
| Requested change | **None.** Withdrawn; the requirement text was corrected instead. |
| Why it was raised | An earlier revision of Requirement 15.1 cited "section 6" of doc 25 for the build/buy/drop decision format. On this branch that reference was stale, and the discrepancy was recorded here rather than silently absorbed. |
| Why it is withdrawn | Requirement 15.1 cites section 3, which is where the format actually lives. The mismatch that motivated the entry no longer exists. |

**Evidence, read from `docs/logic/25-our-platform-spec.md` — retained because it is what closed the question:**

- line 66 — `## 3. Build / buy / drop, by capability`
- line 292 — `## 6. Cost of leaving Frappe — honest accounting`

**Position on the frontend side.** Doc 05 and `docs/design/UI-SPEC.md` link **§3** for the decision format,
matching Requirement 15.1. Neither document links §6 for this purpose.

### R4 — `docs/design/FINAL-SCHEMA.md` has no presentation-layer tables

**Confirmation requested, not blocking.** This entry was originally recorded as blocking
`docs/design/UI-SPEC.md`. It no longer is: `docs/design/FORM-LAYOUT.md` specifies `layout_revision` and
`layout_node` itself under Requirement 15.4, so task 10.2 and the design §10.5 binding table are
**unblocked**. What remains is a confirmation, tracked as an open question under Q3 below (Requirement 15.8).

| Field | Statement |
|---|---|
| Path | [`docs/design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) — a Restricted_Path, left byte-identical. |
| Requested change | Confirm that `layout_revision` / `layout_node`, as specified in this investigation's `docs/design/FORM-LAYOUT.md`, are the intended concrete form of doc 25's `ui_field` / `ui_layout`. Adding the tables to FINAL-SCHEMA is at the backend agent's discretion and is not required for this investigation to complete. |
| Reason | The tables doc 25 promises are not in the schema register, so the binding rule needed a home for presentation-metadata fields. |

**Evidence that doc 25 commits to presentation metadata.** `docs/logic/25-our-platform-spec.md:79` states:

```
| Presentation metadata | **BUILD** — `ui_field` / `ui_layout`, describes rendering only; cannot affect storage | L4 |
```

and `docs/logic/25-our-platform-spec.md:259` lists `ui_field` among the settings tables the orchestration
engine must support.

**Evidence that the schema does not carry them.** Searching `docs/design/FINAL-SCHEMA.md` for `ui_field`,
`ui_layout`, `layout_revision` and `layout_node` returns **no matches**. The tables doc 25 promises are absent
from the schema register.

**Impact — why this no longer blocks.** The binding rule originally required every layout field to name an
existing FINAL-SCHEMA table and column, which was unsatisfiable for presentation-metadata fields and did block
task 10.2. Requirement 15.4 now has `docs/design/FORM-LAYOUT.md` specify `layout_revision` and `layout_node`,
and the design §10.5 binding table splits its rows by kind: business-data fields resolve against
`docs/design/FINAL-SCHEMA.md` (Requirement 15.5), presentation-metadata fields resolve against
`docs/design/FORM-LAYOUT.md` (Requirement 15.6). Every row therefore has a resolvable target, design property
P9 is checkable, and **task 10.2 and the §10.5 binding table are unblocked**. `docs/design/FINAL-SCHEMA.md` is
left unchanged (Requirement 15.7).

**What a differing answer triggers.** If the backend agent later specifies `ui_field` / `ui_layout` with
different table or column names, the §10.5 binding table and the FORM-LAYOUT DDL are reconciled **in a single
commit**, so the two never disagree on the branch. This is design risk R11, and the divergence is registered
under Q3 (Requirement 15.8) so the reconciliation is triggered by a known open item rather than discovered
later.

**What the frontend agent will not do.** It will not edit `docs/design/FINAL-SCHEMA.md`, and it will not
invent a FINAL-SCHEMA table or column name to close the binding table.
