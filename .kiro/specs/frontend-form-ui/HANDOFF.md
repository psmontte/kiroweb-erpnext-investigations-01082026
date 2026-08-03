# Handoff — `frontend-form-ui`

Resumption record for a session that has never seen this work. Read
[`requirements.md`](requirements.md), [`design.md`](design.md) and [`tasks.md`](tasks.md) first; this file
records only what those documents do not say — the environment, the rules learned the hard way, the findings
already established, and the open items.

## 1. State snapshot

| Item | Value |
|---|---|
| Branch | `kiro/spec-planning` |
| HEAD | `547874f` (`547874fc56de334d73393dd02294d8a5e9fc65fa`) |
| Base | `main` = `e01d1df94f2d7f283dc5d626ded400410dc3b1b7`, 24 commits behind HEAD |
| Working tree | clean; everything pushed |
| Backend work | `main` is already merged and carries the backend agent's Tranches A/B/C/E output (`docs/logic/01`–`44`, `docs/design/FINAL-SCHEMA.md`) |

The branch is a superset of merged `main`, so no rebase or catch-up merge is pending.

## 2. Progress

**9 of 56 leaf sub-tasks complete:** 1.1, 1.2, 2.1–2.6, and 11.3 (executed early, out of sequence, to bring
the Notes_Register into line with requirement edits made during task 2).

| Deliverable | State |
|---|---|
| [`docs/ui/01-form-rendering-and-layout-engine.md`](../../../docs/ui/01-form-rendering-and-layout-engine.md) | 2214 lines. §1–§5 written. §6, §7, §8, §10 are empty headings; §9 has its reservation prose and a table of nine `_reserved_` rows |
| [`docs/agents/NOTES-frontend.md`](../../../docs/agents/NOTES-frontend.md) | 240 lines. Q1–Q4, R1–R4 |
| `docs/ui/02-child-table-grid-engine.md` | not started |
| `docs/ui/03-form-customisation-and-layout-overrides.md` | not started |
| `docs/ui/04-list-view-filters-and-bulk-actions.md` | not started |
| `docs/ui/05-our-frontend-and-form-spec.md` | not started |
| `docs/design/UI-SPEC.md` | not started |
| `docs/design/FORM-LAYOUT.md` | not started |

Remaining in doc 01: §6 precision (sub-task 2.7), §7 dirty state and re-render cost (2.8), and §8 defect
inventory, §9 invariants and §10 Adopt/Change/Reject (2.9). `UI1`–`UI9` are **still entirely unallocated** —
every row of the §9 table reads `_reserved_`. The §8 inventory is not, however, unresearched: §3.8 (six
findings), §4.5 (eight findings) and §5.10 (nine findings) already hold the cited prose that §8 must
number and §10 must judge.

**Next action is sub-task 2.7.**

## 3. Environment reconstruction

The sandbox is unreliable and **has already lost both pinned source trees once mid-session** — they were
fetched, disappeared, and had to be re-fetched (design risk R1). If `/projects/sandbox/frappe/frappe` or
`/projects/sandbox/erpnext/erpnext` is missing, re-create it with a shallow depth-1 fetch of the **exact
pinned commit**, never a branch tip:

```
cd /projects/sandbox
mkdir -p frappe && git init -q frappe
git -C frappe remote add origin https://github.com/frappe/frappe.git
git -C frappe fetch --depth 1 origin 5da68e856ca7f036b20d2583167b9d00c4a8db56
git -C frappe checkout -q FETCH_HEAD
```

```
cd /projects/sandbox
mkdir -p erpnext && git init -q erpnext
git -C erpnext remote add origin https://github.com/frappe/erpnext.git
git -C erpnext fetch --depth 1 origin ceefd4add77715d2762c19db337fb83e28a477de
git -C erpnext checkout -q FETCH_HEAD
```

Run these from `/projects/sandbox` in the **foreground**. Background execution (`run_in_background`)
silently vanished in this sandbox: it reported success while creating nothing.

**Remote access.** `git fetch` and `git ls-remote` against this repository's own `origin` **fail** here with
`Missing header field, please provide AuthToken`. To inspect remote state use the GitHub API
(`https://api.github.com/repos/psmontte/kiroweb-erpnext-investigations-01082026/branches`); to push, use
`kiro_powers` → power `github`, server `github`, tool `push_to_remote`, with `path`
`/projects/sandbox/kiroweb-erpnext-investigations-01082026`, `owner` `psmontte`, `repository_name`
`kiroweb-erpnext-investigations-01082026`, `remote_branch_name` `kiro/spec-planning`. Never `git push` via
bash.

### Gates — re-assert all four at the start of every session

| Gate | Check | Observed at handoff |
|---|---|---|
| G0 | `/projects/sandbox/frappe/frappe` and `/projects/sandbox/erpnext/erpnext` exist | pass |
| G1 | `git -C /projects/sandbox/frappe rev-parse HEAD` = `5da68e856ca7f036b20d2583167b9d00c4a8db56`; `git -C /projects/sandbox/erpnext rev-parse HEAD` = `ceefd4add77715d2762c19db337fb83e28a477de` | pass, both exact |
| G2 | current branch is `kiro/spec-planning` | pass |
| G3 | `docs/logic/18-metadata-and-runtime-ddl.md`, `docs/logic/19-permissions-and-access-control.md`, `docs/logic/24-reporting-framework.md`, `docs/logic/25-our-platform-spec.md`, `docs/design/FINAL-SCHEMA.md` all exist | pass, all five |

A gate failure **stops the work**; it does not license an uncited claim. Citations already written stay valid
because they were recorded against the pinned commits. G0/G1 must also be re-asserted immediately before the
final acceptance run.

## 4. Non-negotiable rules

| Rule | Why |
|---|---|
| **Never `git pull`, `git fetch` or `git checkout` inside either pinned tree** | Every recorded line number is against those two commits. A moved line silently falsifies a claim that still reads as verified |
| **Push after every increment** | Never leave completed work in a local-only commit; the sandbox can lose state |
| **Stage by explicit path** — `git add docs/ui/01-...md`, never `git add -A` | Restricted_Paths must not be swept in |
| **Invariant prefix is `UI`, from `UI1`** | Bare `U` is taken twice: `docs/logic/30-upstream-trade-and-parties.md:942-957` uses `U1`–`U8`, and `docs/design/FINAL-SCHEMA.md:734` uses an unrelated `U1`. The deviation from the prompt's `U` is registered as Q1 |
| **Claim protocol** — read the code, record the 1-based line number in the same pass, attach the citation | Never cite an unread line. An absence is a finding with **no** line number |
| **Prefer full `path:line` over `` `:NNN` `` shorthand** | Shorthand resolves against `.py` anchors only (`design.md`:379, risk R3) |

### Ownership boundary

**Owned** — `docs/ui/**`, `docs/design/UI-SPEC.md`, `docs/design/FORM-LAYOUT.md`,
`.kiro/specs/frontend-*/**`, `docs/agents/NOTES-frontend.md`.

**Restricted** — `docs/logic/**`, `docs/scenarios/**`, `docs/reveng/**`, `docs/design/FINAL-SCHEMA.md`,
`docs/COVERAGE.md`, `docs/INVESTIGATION-PLAN.md`, `README.md`, `tools/**`, `schema/**`,
`semantic-review/**`. A needed change to any of these becomes an entry under
`## Requests for the backend agent` in the Notes_Register; the path stays byte-identical.

## 5. The verifier trap

`tools/verify_refs.py`:35 requires the `.py` extension in its `CITATION` regex, and `:62` builds the
`--strict-names` symbol index with `ast.parse`. Doc 01's citations are overwhelmingly
`frappe/public/js/**`, so a `0 problems` report is **vacuous** for most of them. Run at handoff, the tool
reported `128 citations verified: 128 full, 0 shorthand … 0 problems, 0 name notes` — 128 out of many
hundreds, all of them Python.

Requirements 17.4–17.6 therefore make the V4 read-back — re-reading every non-`.py` citation at its cited
line and confirming the named construct is there — a normative gate condition, discharged by task 12.3.
`tools/**` is Restricted, so the tool cannot be fixed here; that is backend request R2.

## 6. Findings already established — do not re-derive

All citations below are against the pinned commits and were verified during this handoff.

| Finding | Evidence |
|---|---|
| **No single definition of "visible" or "editable."** Doc 01 §4.5 counts four independent definitions of visible, and three implementations of the `hidden`/`read_only` decision, two of which omit the permission and `allow_on_submit` arms — a dialog-rendered field ignores `permlevel` entirely | doc 01 §4.5 findings 6 and 7; `frappe/public/js/frappe/model/perm.js:246-307`, `:239-243`, `frappe/public/js/frappe/form/controls/base_control.js:53-92` |
| **Of the seven field flags, only `allow_on_submit` is a real boundary, and only against `Document.save()`.** `db_set` bypasses it, and ERPNext's status updater depends on the bypass to write `Sales Order.per_billed`, a field carrying no `allow_on_submit`. `read_only` has **zero** occurrences in `frappe/model/base_document.py` | doc 01 §4.3, §4.5 findings 1 and 4; `frappe/model/document.py:1951` (`def db_set`), docstring warning `:1954-1955`; `controllers/status_updater.py:677-683`; `selling/doctype/sales_order/sales_order.json:1275-1290` |
| **`eval:` expressions run with full global authority.** `frappe.utils.eval` compiles via `new Function`, whose bodies do not close over the construction site; the template `let out = ${code}; return out` also admits statement injection via `;`. The only guard is an anchored regex that accepts `eval:doc.a==1 && doc.b=2` | `frappe/public/js/frappe/utils/utils.js:1205-1207`; `frappe/core/doctype/doctype/doctype.py:42` (`DEPENDS_ON_PATTERN`). Direct evidence for target rule X-5; doc 01 §3.5, §3.8 finding 3 |
| **Five independent implementations of one expression language**, disagreeing on bindings and on failure policy — four throw, one fails open. A sixth, for report filters, omits the `parent` binding | doc 01 §3.8 finding 5, with all six citations |
| **Five dead expressions ship in ERPNext** at this commit: `doc.`-prefixed but missing the `eval:` prefix, so looked up as a literal fieldname, permanently falsy, and silent | doc 01 §3.8 finding 1, with the five `.json` citations; branch at `frappe/public/js/frappe/form/layout.js:887` |
| **The control registry is one line of string concatenation** — `"Control" + opts.df.fieldtype.replace(/ /g, "")`. No registry, no validation; an unknown fieldtype hits `console.log` and returns `undefined`, and that null is why `make_field` returns before registering the field anywhere | `frappe/public/js/frappe/form/controls/control.js:49`, `:53`; `frappe/public/js/frappe/form/layout.js:265`; doc 01 §5.10 findings 1 and 2 |
| **Six call sites mutate the shared cached docfield**, including `ControlCurrency.get_precision` writing `this.df.precision` — directly relevant to sub-task 2.7 | doc 01 §5.10 finding 3; `frappe/public/js/frappe/form/controls/currency.js:7`, `:9` |
| **Upstream already virtualises list rendering but not the child-table grid.** Docs 02 and 04 must ground the G-4 verdict on that asymmetry, not on an assumed absence | `frappe/public/js/frappe/list/list_view_virtualization.js` exists at the pinned commit |

## 7. Leads left deliberately for the next sub-tasks

### 2.7 — precision

| Entry point | Citation | Note |
|---|---|---|
| `ControlFloat.get_precision` | `frappe/public/js/frappe/form/controls/float.js:31-34` | falls back to `frappe.boot.sysdefaults.float_precision`, else does not round |
| `ControlCurrency.get_precision` | `frappe/public/js/frappe/form/controls/currency.js:2-14` | **mutates `this.df.precision`** at `:7` and `:9` |
| `ControlPercent.format_for_input` | `frappe/public/js/frappe/form/controls/percent.js:2-12` | takes `Math.min(get_precision(), decimals-in-value)` |

Precision applies on the way **into** the model too, not only on display: `ControlFloat.parse` rounds with
`flt(value, this.get_precision())` (`frappe/public/js/frappe/form/controls/float.js:5`).

Read-only rendering bypasses `format_for_input` entirely — `BaseInput.set_disp_area` routes through
`frappe.format` (`frappe/public/js/frappe/form/controls/base_input.js:166`), with a zero-preserving special
case for `Currency`, `Int` and `Float` but **not** `Percent`
(`frappe/public/js/frappe/form/controls/base_input.js:148-157`).

### Doc 02 — the grid

`ControlTable extends frappe.ui.form.Control` directly
(`frappe/public/js/frappe/form/controls/table.js:3`), so it never inherits `BaseInput`'s `disp_status !=
"None"` early return (`frappe/public/js/frappe/form/controls/base_input.js:95`) — a hidden child table still
runs a full grid render (doc 01 §5.10 finding 7). The paste handler
(`frappe/public/js/frappe/form/controls/table.js:19`) and its five-fieldtype coercion table
(`frappe/public/js/frappe/form/controls/table.js:27-33`, entries at `:28-32`) live on the **control**, not
on the grid.

## 8. Open items

| Item | State |
|---|---|
| **R2** — extend `verify_refs.py` beyond `.py` | Open, non-blocking. `tools/**` is Restricted, so it cannot be actioned here. Q4 records the scope limit as permanent regardless of R2's fate |
| **R4** — confirm `layout_revision` / `layout_node` as the intended concrete form of doc 25 §3's `ui_field` / `ui_layout` **BUILD** decision (`docs/logic/25-our-platform-spec.md:79`) | Confirmation requested, **not blocking**: `docs/design/FORM-LAYOUT.md` specifies both tables under Requirement 15.4, so task 10.2 is unblocked. A differing answer triggers a single-commit reconciliation of the §10.5 binding table and the §10.1/§10.2 DDL (design risk R11) |

### Names the spec inherited from the prompt that do not exist upstream

Four: `FormPage`, `grid_form.js`, `list_sidebar*`, `Markdown`. **All four were found by *executing* the
spec, none by reading it.** Requirements 6.1, 7.1 and 6.6 have been corrected, and 6.9 generalised to cover
an absent class, file **or fieldtype**. Notes Q2 tabulates the first three (its heading says "source paths";
`Markdown` is a fieldtype, handled in the same entry's resolution).

The distinction that emerged, and the reason this matters beyond the four cases: **a name absent from
upstream is an absence finding in the deliverable; a name absent from upstream that the specification itself
mandated is a specification defect, and the fix is to correct the spec.** `FormPage` stayed an absence
finding (doc 01 §1.5) because the upstream class genuinely does not exist whatever the requirement says;
`Markdown` did not, because the requirement was wrong and was corrected, leaving only the upstream naming
hazard at doc 01 §5.10 finding 2.

**Warn:** further such names may still be latent in Requirements 8 and 9, which have not yet been executed.

### Scale signal

Doc 01 is heading for roughly 3000 lines with 5 of its 8 content sections written. Five investigation
documents plus two normative documents (`docs/design/UI-SPEC.md`, `docs/design/FORM-LAYOUT.md`) is a
substantially larger body of work than a 56-sub-task plan implies. Plan session boundaries accordingly, and
push at every increment.

## 9. Corrections to the handoff brief

Four statements in the brief that produced this file did not survive verification. Recorded so they are not
propagated:

| Claimed | Actual |
|---|---|
| `table.js:29-34` for the paste coercion table | `frappe/public/js/frappe/form/controls/table.js:27-33`; the five map entries are `:28-32` |
| `docs/logic/30-upstream-trade-and-parties.md:942-956` for `U1`–`U8` | `:942-957` — `U8` wraps onto line 957. §11.5 heading at `:940` |
| `"Control" + fieldtype.replace(/ /g, "")` | `"Control" + opts.df.fieldtype.replace(/ /g, "")` |
| Shorthand `` `:NNN` `` "misresolved 28 times in sub-task 2.3" | **Unsupported.** Doc 01 has never contained a `` `:NNN` `` shorthand citation at any commit on this branch, and the verifier reports `0 shorthand`. The only shorthand-related commit is `8a66ae8`, a 2-line change during sub-task **2.4** expanding one bare relative path (`payment_term.json:106-112`) to its full path in §3.7. The *rule* stands on its own footing (`design.md`:379, risk R3 at `design.md`:872); the count does not |
