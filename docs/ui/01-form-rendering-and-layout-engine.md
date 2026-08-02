# 01 — Form Rendering and Layout Engine

> **Presentation layer — form rendering.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

This document covers the **client-side form runtime**: how a route resolves to a form, the order in which
`frappe.ui.form.Form`, `frappe.ui.form.Layout`, `frappe.ui.form.Section`, `frappe.ui.form.Column` and
`frappe.ui.form.Tab` are constructed, the algorithm that turns the flat ordered `Meta.fields` list into a
visual tree of tabs, sections and columns, how the `*_depends_on` expression family is evaluated, what each
field flag does at render time, which control class serves each field type, how display precision is
resolved, and what a re-render actually costs.

It deliberately **does not** re-derive how `Meta` is assembled or cached. That is the subject of
[`docs/logic/18-metadata-and-runtime-ddl.md`](../logic/18-metadata-and-runtime-ddl.md) §1.1, which documents
the five-source layering (`DocType` + `DocField` rows, `Custom Field`, `Property Setter`, custom links and
actions, then field sort order) that produces the field list this document consumes. The only statement made
here about that process is its **consequence for layout**: the form runtime receives an already-merged,
already-ordered field list and treats its order as authoritative. Permission evaluation is likewise deferred
to [`docs/logic/19-permissions-and-access-control.md`](../logic/19-permissions-and-access-control.md); this
document states only where the form runtime consults a permission decision, never how that decision is
reached.

---

## 1. Runtime form construction order

Five classes cooperate: `frappe.ui.form.Form` (`frappe/public/js/frappe/form/form.js:24`),
`frappe.ui.form.Layout` (`frappe/public/js/frappe/form/layout.js:5`), and the three default-exported classes
`Section` (`frappe/public/js/frappe/form/section.js:1`), `Column`
(`frappe/public/js/frappe/form/column.js:1`) and `Tab` (`frappe/public/js/frappe/form/tab.js:7`). The route
that reaches them is owned by `frappe.views.FormFactory`
(`frappe/public/js/frappe/views/formview.js:6`). A sixth class named in Requirement 6.1 — `FormPage` — does
not exist; see §1.5.

Two facts govern everything below. First, **the `Form` constructor builds no DOM**: it stores options and
loads metadata (`frappe/public/js/frappe/form/form.js:25-60`), and the entire widget tree is built later, by
`setup()`, on the first `refresh()` that carries a `docname`
(`frappe/public/js/frappe/form/form.js:453-455`). Second, **the field list is consumed in the order it
arrives** — the layout engine performs no structural validation of that order, which is the subject of §2.

### 1.1 Algorithm A-01-1 — route to rendered form

Each step carries the citation for the code that performs it. Branch conditions are stated as the code states
them.

```
Algorithm A-01-1: route → rendered form

 1. FormFactory.make(route):
      doctype        ← route[1]
      doctype_layout ← frappe.router.doctype_layout || doctype                  (formview.js:7-9)
 1a. if frappe.views.formview[doctype_layout] is unset:
        frappe.model.with_doctype(doctype, …) → container.add_page(doctype_layout)
        → cache the page under doctype_layout → make_and_show(doctype, route)   (formview.js:11-16)
 1b. else: skip construction entirely → show_doc(route)                          (formview.js:17-19)
     ⇒ at most one Form object per doctype_layout per session.

 2. make_and_show:
 2a. if frappe.router.doctype_layout is set: with_doc("DocType Layout", name),
       then pre-load every layout.child_tables[].child_layout in parallel
       (Promise.all) before make_form, so grids can apply them synchronously    (formview.js:25-49)
 2b. else: make_form(doctype) immediately, then show_doc(route)                 (formview.js:50-53)

 3. make_form: new frappe.ui.form.Form(doctype, this.page, true,
      frappe.router.doctype_layout)                                            (formview.js:56-63)

 4. Form constructor — no DOM:
      docname ← ""; sections ← []; grids ← []                                   (form.js:26, 36-37)
      cscript ← new frappe.ui.form.Controller({frm: this})                      (form.js:38)
      doctype_layout ← frappe.get_doc("DocType Layout", name) **only if**
        layout.document_type === doctype, else null                             (form.js:44-49)
      undo_manager ← new UndoManager                                            (form.js:50)
      setup_meta()                                                              (form.js:51)

 5. setup_meta():
      meta ← frappe.get_meta(doctype)          ← merged field list, see doc 18  (form.js:63)
      if meta.istable: meta.in_dialog ← 1                                       (form.js:65-67)
      perm ← frappe.perm.get_perm(doctype)                                      (form.js:69)

 6. refresh(docname) — the driver:
 6a. switched ← Boolean(docname)                                                (form.js:407)
 6b. if docname: switch_doc(docname) → for every grid, visible_columns ← null
       and grid_pagination.go_to_page(1, true); then every section's
       expanded_by_user ← false; close any open grid form                       (form.js:411-413, 542-554)
 6c. cur_frm ← this; undo_manager.erase_history()                               (form.js:415-417)
 6d. if not this.docname: **stop** — nothing below runs                         (form.js:419, 482)
 6e. doc ← frappe.get_doc(doctype, docname)                                     (form.js:423)
 6f. fetch_permissions(); if not has_read_permission():
       show_not_permitted and **return before any layout exists**               (form.js:426-430)
 6g. for each grid: grid.refresh()                                              (form.js:433-435)
 6h. read_only ← frappe.workflow.is_read_only(...); if read_only: set_read_only  (form.js:438-441)
 6i. if docname not in opendocs: check_doctype_conflict(docname)
       else if check_reload(): **return** (debounced reload_doc)                (form.js:444-450, 556-566)
 6j. if not setup_done: setup()               ← the one and only DOM build      (form.js:453-455)
 6k. trigger_onload(switched)                                                   (form.js:458)
 6l. status classes on $wrapper from doc.docstatus (0/1/2)                      (form.js:468-472)
 6m. conflict message, submission-queue banner, mask fields read-only           (form.js:474-477)
 6n. if frappe.boot.read_only: disable_form()                                   (form.js:479-481)

 7. setup() — fixed order, once:                                               (form.js:82-145)
      fields ← []; fields_dict ← {}; state_fieldname ← workflow state field     (form.js:83-85)
      is_single_column ← (doctype === "DocType") ? true : meta.hide_toolbar     (form.js:91)
      frappe.ui.make_app_page({single_column, sidebar_position: "Right"})       (form.js:93-97)
      layout_main ← page.main.get(0)                                            (form.js:99)
      new Toolbar → new FormViewers → add_form_keyboard_shortcuts()             (form.js:105-116)
      **setup_std_layout()**                                                    (form.js:119)
      new ScriptManager + script_manager.setup()  ← after the layout, because
        there is no fields_dict before it (comment in source)                   (form.js:121-125)
      watch_model_updates()                                                     (form.js:126)
      if not meta.hide_toolbar and frappe.boot.desk_settings.timeline:
        new Footer, body[data-sidebar] ← 1                                      (form.js:128-139)
      setup_file_drop(); setup_doctype_actions(); setup_notify_on_rename()      (form.js:140-142)
      setup_done ← true                                                         (form.js:144)

 8. setup_std_layout():                                                        (form.js:234-285)
      form_wrapper ← <div> in layout_main; body ← .std-form-layout              (form.js:235-236)
      meta.section_style ← "Simple"   (unconditional overwrite)                 (form.js:239)
      layout ← new Layout({parent: body, doctype, doctype_layout, frm,
                           with_dashboard: true, card_layout: true})            (form.js:242-249)
      layout.make()                                                             (form.js:251)
      frm.fields_dict ← layout.fields_dict; frm.fields ← layout.fields_list     (form.js:253-254)
      dashboard placement:
        if layout.tabs.length: first tab with df.show_dashboard, else tabs[0]    (form.js:259-270)
        else: prepend into .form-page                                           (form.js:272)
      new Dashboard → new FormTour → new States                                 (form.js:275-284)

 9. Layout.make():                                                             (layout.js:21-41)
      wrapper ← .form-layout; message ← .form-message-container.hidden;
      page ← .form-page                                                         (layout.js:25-29)
      if this.fields is unset: fields ← get_doctype_fields()                     (layout.js:31-33)
      if is_tabbed_layout(): setup_tabbed_layout()  → .form-tabs list +
        .form-tab-content + scroll/click handlers                                (layout.js:35-37, 43-54)
      if this.frm: setup_tooltip_events()                                        (layout.js:39)
      render()                                                                   (layout.js:40)

10. get_doctype_fields():                                                       (layout.js:56-67)
      fields ← [ get_new_name_field() ]                                          (layout.js:57, 69-89)
      if doctype_layout: concat get_fields_from_layout()                          (layout.js:58-59)
      else:            concat frappe.meta.sort_docfields(
                                frappe.meta.docfield_map[doctype])                (layout.js:61-63)

11. render() → Algorithm A-01-2 (§2).                                          (layout.js:169-226)

12. When the document is available, render_form():                             (form.js:609-659)
12a. if meta.istable: only refresh_header(switched) runs — child-table layouts
       are rendered by the grid, not here                                        (form.js:648-650)
12b. layout.doc ← doc; layout.attach_doc_and_docfields()                         (form.js:611-612)
12c. if frappe.boot.desk_settings.form_sidebar: new Sidebar + make(),
       else page.sidebar.hide()                                                  (form.js:614-623)
12d. frappe.run_serially([ _resolve_layout, refresh_header,
       trigger "form-refresh", refresh_fields, script "refresh",
       apply_layout_defaults, (if is_onload) onload_post_render,
       (if is_onload and is_new) focus_on_first_input, run_after_load_hook,
       dashboard.after_refresh, is_onload ← false, configure_breadcrumb_width ]) (form.js:628-647)

13. refresh_fields() → layout.refresh(doc):                                     (form.js:831-841)
      attach_doc_and_docfields(true)                                             (layout.js:398)
      refresh_dependency()                                                       (layout.js:405)
      refresh_sections()                                                         (layout.js:408)
      if this.frm: refresh_section_collapse()                                    (layout.js:410-413)
```

Two branches of A-01-1 replace the whole widget tree after it has been built, and both are worth naming
because they invalidate any handle held on the old objects:

- **Conditional `DocType Layout`.** `_resolve_layout()` runs first in the `run_serially` chain
  (`frappe/public/js/frappe/form/form.js:630`). It filters `frappe.boot.doctype_layouts` to those matching the
  doctype and carrying a `condition` (`frappe/public/js/frappe/form/form.js:672-675`), evaluates each
  condition, and if the winner differs from the rendered one calls `_rebuild_layout()`
  (`frappe/public/js/frappe/form/form.js:701-721`). `_rebuild_layout()` constructs a **second** `Layout`,
  resets `frm.grids` to `[]`, moves the detached dashboard, removes the old wrapper, and re-points
  `fields_dict` / `fields` (`frappe/public/js/frappe/form/form.js:723-763`). Every `Section`, `Column`, `Tab`
  and control object from the first pass is discarded.
- **Field replacement.** `Layout.replace_field()` swaps one control in place, splices `fields_list`, updates
  `fields_dict`, and asks every section and the field's tab to re-point their own references
  (`frappe/public/js/frappe/form/layout.js:242-255`).

### 1.2 What each class owns, and what it does not

| Class | Owns | Does **not** own | Citation |
|---|---|---|---|
| `Form` | `meta`, `perm`, `doc`, `page`, `toolbar`, `grids`, and copies of the layout's `fields` / `fields_dict` | any layout structure — it holds one `Layout` and copies two references off it | `frappe/public/js/frappe/form/form.js:24-60`, `:253-254` |
| `Layout` | `fields` (the ordered input), `fields_list`, `fields_dict`, `sections`, `sections_dict`, `tabs`, and the cursors `section`, `column`, `current_tab` | tab membership as a list; column membership at all | `frappe/public/js/frappe/form/layout.js:6-19`, `:172-173`, `:384` |
| `Section` | `columns[]`, `fields_list[]`, `fields_dict{}`, its `.form-section` wrapper and `.section-body`, collapse state | its own visibility beyond the two `df` flags — emptiness is decided later, by DOM query | `frappe/public/js/frappe/form/section.js:1-26`, `:28-61`, `:102-113` |
| `Column` | its `.form-column > form` element and the equal-width redistribution of its siblings | **its fields** — `add_field()` is an empty method | `frappe/public/js/frappe/form/column.js:1-37`, `:39-59`, `:62` |
| `Tab` | its `.nav-link` button and `.tab-pane` wrapper, its `hidden` flag | **its fields** — `add_field()` only stamps `fieldobj.tab = this` | `frappe/public/js/frappe/form/tab.js:8-45`, `:88-90` |

Three consequences follow directly, and each is load-bearing for the rest of this document.

1. **Column membership is DOM-only.** `Layout.make_field` calls `this.column.add_field(fieldobj)`
   (`frappe/public/js/frappe/form/layout.js:271`), but `Column.add_field` is the empty body
   `add_field() {}` (`frappe/public/js/frappe/form/column.js:62`). No object graph records which fields are in
   which column. Anything that needs that answer must query the DOM — which is exactly what
   `resize_all_columns` does, counting `.form-column` children of the section body
   (`frappe/public/js/frappe/form/column.js:41-43`).
2. **Tab membership is a back-pointer, not a list.** `Tab.add_field` assigns `fieldobj.tab = this` and keeps
   no collection (`frappe/public/js/frappe/form/tab.js:88-90`). Consequently `Tab.refresh` decides visibility
   by searching its own `.tab-pane` for a `.form-section` or `.form-dashboard-section` that is neither
   `.hide-control` nor `.empty-section` (`frappe/public/js/frappe/form/tab.js:57-67`) — a tab is visible
   because of what the DOM currently contains, and `.empty-section` is itself assigned by a separate DOM sweep
   in `Layout.refresh_sections` (`frappe/public/js/frappe/form/layout.js:428-445`). The ordering dependency
   between those two sweeps is real: `refresh_sections` classifies sections first, then calls `refresh_tabs`
   at its end (`frappe/public/js/frappe/form/layout.js:444`).
3. **A `Column` cannot exist without a `Section`.** The `Column` constructor's second statement is
   `this.section.columns.push(this)` (`frappe/public/js/frappe/form/column.js:7`), and `make()` appends into
   `this.section.body` (`frappe/public/js/frappe/form/column.js:18`). A null section is not guarded; §2.4
   states which code path guarantees one exists.

### 1.3 Section, Column and Tab construction detail

`Section` (`frappe/public/js/frappe/form/section.js:2-26`) runs `make()` before restoring collapse state and
before its first `refresh()`. `make()` chooses the wrapper class by `df.is_dashboard_section`
(`form-dashboard-section` versus `form-section`), adds `card-section` when the layout passed `card_layout`,
and stamps `data-fieldname` from the df (`frappe/public/js/frappe/form/section.js:30-33`). A head element is
created only when `df.label` is set and `df.hide_label` is not
(`frappe/public/js/frappe/form/section.js:36-38`), and `make_head` attaches the collapse handler, the
`tabindex="0"` attributes and the chevron indicator only when `df.collapsible`
(`frappe/public/js/frappe/form/section.js:75-89`). Collapse state persists in `localStorage` under
`df.css_class + "-closed"`, both on read (`frappe/public/js/frappe/form/section.js:13-19`) and on write
(`frappe/public/js/frappe/form/section.js:134-135`) — so it is keyed on a **CSS class**, not on the section's
fieldname, and a section with no `css_class` never persists.

`Column.resize_all_columns` recomputes `colspan = cint(12 / columns)` over the section's direct
`.form-column` children, preferring the count of non-hidden columns and falling back to the total
(`frappe/public/js/frappe/form/column.js:41-45`), with a special case setting `colspan = 20` at exactly five
columns (`frappe/public/js/frappe/form/column.js:46-48`) — `col-sm-20` is a real rule, defined at
`frappe/public/scss/desk/form.scss:615-628`. Every column's class list is then rebuilt from scratch,
re-adding `hide-control` afterwards if it was present (`frappe/public/js/frappe/form/column.js:50-59`).

`Tab.make` derives its DOM id as `${frappe.scrub(this.doctype, "-")}-${this.df.fieldname}`
(`frappe/public/js/frappe/form/tab.js:26-27`) and uses it for both `aria-controls` on the button and `id` on
the pane (`frappe/public/js/frappe/form/tab.js:30-44`), so the id is a function of the tab's fieldname alone.
`Tab.refresh` applies three tests in order — explicit `df.hidden` or `df.hidden_due_to_dependency`, then
`!frm.get_perm(df.permlevel || 0, "read")`, then the DOM emptiness test
(`frappe/public/js/frappe/form/tab.js:47-70`).

### 1.4 Worked example — `ToDo` from route to rendered structure

`ToDo` is the smallest useful trace: 18 fields, no `Tab Break`, and a stored order that begins with a
`Section Break`. The order is the `field_order` array at `frappe/desk/doctype/todo/todo.json:9-28` —
`description_and_status`, `status`, `priority`, `column_break_2`, `color`, `date`, `allocated_to`,
`description_section`, `description`, `section_break_6`, `reference_type`, `reference_name`,
`column_break_10`, `role`, `assigned_by`, `assigned_by_full_name`, `sender`, `assignment_rule`.

| A-01-1 step | What happens for `ToDo` |
|---|---|
| 1 | Route `Form/ToDo/<name>`; `doctype_layout` = `"ToDo"` because `frappe.router.doctype_layout` is unset (`frappe/public/js/frappe/views/formview.js:8-9`) |
| 2b | No layout ⇒ `make_form` immediately (`frappe/public/js/frappe/views/formview.js:50-53`) |
| 4 | `doctype_layout` resolves to `null` — the `if (!doctype_layout_name) return null` arm (`frappe/public/js/frappe/form/form.js:45`) |
| 7 | `is_single_column` = `meta.hide_toolbar` (falsy) ⇒ two-column page shell (`frappe/public/js/frappe/form/form.js:91`) |
| 9 | `is_tabbed_layout()` finds no `Tab Break` ⇒ `setup_tabbed_layout` is skipped; there is no `.form-tabs` list and `layout.tabs` stays `[]` (`frappe/public/js/frappe/form/layout.js:35-37`, `:238-240`) |
| 10 | `fields` = `[__newname]` + `sort_docfields(docfield_map["ToDo"])` — 19 entries on a site with no `Custom Field` rows (`frappe/public/js/frappe/form/layout.js:57-63`) |
| 11 | `no_opening_section()` is **true** — `fields[0]` is `__newname`, fieldtype `Data`, not `Section Break` — and the layout is untabbed, so a bare `{fieldtype: "Section Break"}` is unshifted at index 0 (`frappe/public/js/frappe/form/layout.js:175-177`, `:228-232`) |
| 8 | `layout.tabs.length` is 0 ⇒ the dashboard is prepended into `.form-page` (`frappe/public/js/frappe/form/form.js:271-273`) |

Resulting structure after `render()` — four sections, each entry naming the construct that created it:

```
.form-layout                                          (layout.js:25)
└── .form-page                                        (layout.js:29)
    ├── .form-dashboard                                (form.js:272)
    ├── .form-section[data-fieldname="__section_1"]    ← synthetic, from the unshift (layout.js:176, 343-348)
    │   └── .form-column[data-fieldname="__column_1"]  ← synthetic, from make_field's guard (layout.js:259, 368-373)
    │       └── __newname (hidden)                     (layout.js:69-89)
    ├── .form-section[data-fieldname="description_and_status"]
    │   ├── .form-column[__column_2]  status, priority       ← implicit, opened by make_field
    │   └── .form-column[column_break_2]  color, date, allocated_to
    ├── .form-section[data-fieldname="description_section"]
    │   └── .form-column[__column_3]  description
    └── .form-section[data-fieldname="section_break_6"]   (labelled "Reference")
        ├── .form-column[__column_4]  reference_type, reference_name
        └── .form-column[column_break_10]  role, assigned_by,
              assigned_by_full_name, sender (hidden), assignment_rule
```

Two details in that tree are consequences of code, not of the ToDo metadata. The synthetic column names are
`__column_${this.section_count}` — **the section counter, not the column counter**
(`frappe/public/js/frappe/form/layout.js:371`) — which is why the four implicit columns above are numbered
2, 3, 4 rather than 1, 2, 3, and why two implicit columns inside one section would receive the *same*
`data-fieldname`; §2.5 states the consequence. And `sender`, being `hidden`, still produces a control and
still counts as a member of its column for width purposes until `refresh_sections` and `resize_all_columns`
re-classify it (`frappe/public/js/frappe/form/column.js:41-43`,
`frappe/public/js/frappe/form/layout.js:430-441`).

### 1.5 Absence finding — there is no `FormPage`

**Absent.** Requirement 6.1 names `FormPage` as one of the five classes in the construction order. No such
class exists in the pinned `frappe` tree. Searched: `grep -rn "FormPage" public/js/frappe/form/` (no output,
exit status 1); `grep -rn "FormPage"` across the whole app (three hits, all `WebFormPage` in
`website/page_renderers/web_form.py` and `website/path_resolver.py`, an unrelated server-side website
renderer); and `find . -name "*form_page*"` (no output). No line number is given here, because there is no
line to cite.

The nearest related code is the **`.form-page` div**, which is what the page concept was reduced to. `Layout`
creates one unconditionally as `this.page` (`frappe/public/js/frappe/form/layout.js:29`), and two methods
replace that cursor with a further `.form-page` sibling: `make_page_break()` on a `Page Break` row
(`frappe/public/js/frappe/form/layout.js:305-307`) and `make_page(df)` on a `Fold` row, which additionally
builds the "Show more details" toggle and sets `this.section = null`
(`frappe/public/js/frappe/form/layout.js:309-337`). Sections attach to `this.page` whenever no tab is open
(`frappe/public/js/frappe/form/layout.js:351`), and `.form-page` is queried by name in three further places
(`frappe/public/js/frappe/form/form.js:272`, `frappe/public/js/frappe/form/form.js:751`,
`frappe/public/js/frappe/form/layout.js:436`).

**Unfinished.** The vestige of the removed abstraction is still declared. `Layout`'s constructor initialises
`this.pages = []` and `this.page_breaks = []` (`frappe/public/js/frappe/form/layout.js:8`,
`frappe/public/js/frappe/form/layout.js:11`), and neither array is ever pushed to or read: those two lines are
the only occurrences of the names in `frappe/public/js/frappe/form/`. `make_page` and `make_page_break`
overwrite the scalar `this.page` instead (`frappe/public/js/frappe/form/layout.js:306`,
`frappe/public/js/frappe/form/layout.js:319`), so a form containing two `Page Break` rows has no object-level
record of either page.

## 2. `Meta.fields` → visual tree

## 3. The `*_depends_on` expression family

## 4. Render effect of the field flags

## 5. Field type → control mapping

## 6. Precision resolution, and where display diverges from storage

## 7. Dirty state and re-render cost

## 8. Defect and race inventory

## 9. Invariants

The block `UI1`–`UI9` is reserved for this document. Numbers are allocated upward from `UI1`; any number left
unused at the end of the investigation stays unused rather than being reclaimed by another document.
Consecutiveness across the whole `UI` set is reconciled once, after `docs/ui/05-our-frontend-and-form-spec.md`
exists.

| # | Invariant | Enforcement layer | Established in |
|---|---|---|---|
| UI1 | _reserved_ | — | — |
| UI2 | _reserved_ | — | — |
| UI3 | _reserved_ | — | — |
| UI4 | _reserved_ | — | — |
| UI5 | _reserved_ | — | — |
| UI6 | _reserved_ | — | — |
| UI7 | _reserved_ | — | — |
| UI8 | _reserved_ | — | — |
| UI9 | _reserved_ | — | — |

## 10. Adopt / Change / Reject

---

Cross-references: [`docs/logic/18-metadata-and-runtime-ddl.md`](../logic/18-metadata-and-runtime-ddl.md)
(metadata assembly and cache — the source of the field list this document renders),
[`docs/logic/19-permissions-and-access-control.md`](../logic/19-permissions-and-access-control.md)
(permission and sharing evaluation),
[`docs/logic/21-extensibility-hooks-and-regional.md`](../logic/21-extensibility-hooks-and-regional.md)
(Client Scripts and the regional override mechanism),
[`docs/logic/24-reporting-framework.md`](../logic/24-reporting-framework.md) (report views, dashboards,
print), [`docs/logic/25-our-platform-spec.md`](../logic/25-our-platform-spec.md) (§2 layering rule, §3
build/buy/drop format), [`docs/design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) (read-only storage
contract). Not yet written, named without a link: `docs/ui/02-child-table-grid-engine.md` (the child-table
grid this document's `Table` control delegates to),
`docs/ui/03-form-customisation-and-layout-overrides.md` (which mutates the field-definition model this
document fixes), `docs/ui/04-list-view-filters-and-bulk-actions.md`,
`docs/ui/05-our-frontend-and-form-spec.md`, `docs/design/UI-SPEC.md`, `docs/design/FORM-LAYOUT.md`.
