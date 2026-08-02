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

**Open part of this question.** Requirement 6.1 names `FormPage` in its acceptance criteria. The absence
finding discharges the criterion honestly, but the criterion's wording still names a class that does not
exist upstream. No requirement text is amended without instruction; flagged for the reviewer's judgement.

## Requests for the backend agent

| # | Restricted path | Request | Status |
|---|---|---|---|
| R1 | (workspace, not a file) | Fetch both pinned trees at the stated commits | **Closed** — satisfied |
| R2 | `tools/verify_refs.py` | Extend the citation regex beyond `.py`; gate `--strict-names` on a Python-only symbol index | **Open** — mitigated |
| R3 | `docs/logic/25-our-platform-spec.md` | None; correction applied on the frontend side | **Closed** — informational |
| R4 | `docs/design/FINAL-SCHEMA.md` | Add the presentation-metadata tables, or confirm the intended binding | **Open — blocking** |

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

### R3 — Doc 25's build/buy/drop format is in §3, not §6

| Field | Statement |
|---|---|
| Path | [`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md) — a Restricted_Path, left byte-identical. |
| Requested change | **None.** No file change is requested of the backend agent. |
| Reason for the entry | Requirement 15.1 and the design both cite "section 6" of doc 25 for the build/buy/drop decision format. On this branch that reference is stale. Recorded so the discrepancy is visible rather than silently absorbed. |

**Evidence, read from `docs/logic/25-our-platform-spec.md`:**

- line 66 — `## 3. Build / buy / drop, by capability`
- line 292 — `## 6. Cost of leaving Frappe — honest accounting`

**Correction applied on the frontend side.** Doc 05 and `docs/design/UI-SPEC.md` follow the requirement's
intent — the decision format doc 25 actually uses — and link **§3**. Neither document links §6 for this
purpose.

### R4 — `docs/design/FINAL-SCHEMA.md` has no presentation-layer tables

**This is the consequential one, and it is blocking for `docs/design/UI-SPEC.md`.**

| Field | Statement |
|---|---|
| Path | [`docs/design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) — a Restricted_Path, left byte-identical. |
| Requested change | Either (a) add the presentation-metadata tables to FINAL-SCHEMA, or (b) confirm that `layout_revision` / `layout_node`, as specified in this investigation's `docs/design/FORM-LAYOUT.md`, are the intended concrete form of doc 25's `ui_field` / `ui_layout`. |
| Reason | Design rule E-4 has nothing to bind to: the tables doc 25 promises are not in the schema. |

**Evidence that doc 25 commits to presentation metadata.** `docs/logic/25-our-platform-spec.md:79` states:

```
| Presentation metadata | **BUILD** — `ui_field` / `ui_layout`, describes rendering only; cannot affect storage | L4 |
```

and `docs/logic/25-our-platform-spec.md:259` lists `ui_field` among the settings tables the orchestration
engine must support.

**Evidence that the schema does not carry them.** Searching `docs/design/FINAL-SCHEMA.md` for `ui_field`,
`ui_layout`, `layout_revision` and `layout_node` returns **no matches**. The tables doc 25 promises are absent
from the schema register.

**Impact — why this blocks.** Requirement 15.4 and design rule E-4 require every layout field to name an
existing FINAL-SCHEMA table and column, and design property P9 checks exactly that. Until (a) or (b) is
settled, the binding table in `docs/design/UI-SPEC.md` (task 10.2) **cannot be completed and cannot be
verified**. The remainder of `UI-SPEC.md` — the control mapping, the grid contract, the formatting rules, the
localisation rules — is unaffected and proceeds.

**What the frontend agent will not do.** It will not edit `docs/design/FINAL-SCHEMA.md`, and it will not
invent a table or column name to close the binding table. If (b) is the answer, the confirmation is recorded
here and the binding table cites the FINAL-SCHEMA names as they then stand.
