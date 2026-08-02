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
| `Form` | `meta`, `perm`, `doc`, `page`, `toolbar`, `grids`, and copies of the layout's `fields` / `fields_dict` | any layout structure — it holds one `Layout` and copies two references off it | `frappe/public/js/frappe/form/form.js:24-60`, `frappe/public/js/frappe/form/form.js:253-254` |
| `Layout` | `fields` (the ordered input), `fields_list`, `fields_dict`, `sections`, `sections_dict`, `tabs`, and the cursors `section`, `column`, `current_tab` | tab membership as a list; column membership at all | `frappe/public/js/frappe/form/layout.js:6-19`, `frappe/public/js/frappe/form/layout.js:172-173`, `frappe/public/js/frappe/form/layout.js:384` |
| `Section` | `columns[]`, `fields_list[]`, `fields_dict{}`, its `.form-section` wrapper and `.section-body`, collapse state | its own visibility beyond the two `df` flags — emptiness is decided later, by DOM query | `frappe/public/js/frappe/form/section.js:1-26`, `frappe/public/js/frappe/form/section.js:28-61`, `frappe/public/js/frappe/form/section.js:102-113` |
| `Column` | its `.form-column > form` element and the equal-width redistribution of its siblings | **its fields** — `add_field()` is an empty method | `frappe/public/js/frappe/form/column.js:1-37`, `frappe/public/js/frappe/form/column.js:39-59`, `frappe/public/js/frappe/form/column.js:62` |
| `Tab` | its `.nav-link` button and `.tab-pane` wrapper, its `hidden` flag | **its fields** — `add_field()` only stamps `fieldobj.tab = this` | `frappe/public/js/frappe/form/tab.js:8-45`, `frappe/public/js/frappe/form/tab.js:88-90` |

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
| 9 | `is_tabbed_layout()` finds no `Tab Break` ⇒ `setup_tabbed_layout` is skipped; there is no `.form-tabs` list and `layout.tabs` stays `[]` (`frappe/public/js/frappe/form/layout.js:35-37`, `frappe/public/js/frappe/form/layout.js:238-240`) |
| 10 | `fields` = `[__newname]` + `sort_docfields(docfield_map["ToDo"])` — 19 entries on a site with no `Custom Field` rows (`frappe/public/js/frappe/form/layout.js:57-63`) |
| 11 | `no_opening_section()` is **true** — `fields[0]` is `__newname`, fieldtype `Data`, not `Section Break` — and the layout is untabbed, so a bare `{fieldtype: "Section Break"}` is unshifted at index 0 (`frappe/public/js/frappe/form/layout.js:175-177`, `frappe/public/js/frappe/form/layout.js:228-232`) |
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

The visual tree is produced by a single left-to-right pass over one flat list. There is no tree in the
metadata: `Tab Break`, `Section Break` and `Column Break` are ordinary rows in the same ordered field list as
`status` or `grand_total`, and the nesting a user sees is entirely an artefact of the order in which those
sentinel rows appear. The pass keeps three cursors — `section`, `column`, `current_tab` — and each sentinel
row assigns to one of them.

### 2.1 Where the ordered list comes from

`Layout.make` only computes the list if the caller did not supply one:
`if (!this.fields) this.fields = this.get_doctype_fields()`
(`frappe/public/js/frappe/form/layout.js:31-33`). Dialogs and grid row forms supply their own list, so the
whole of §2 applies to any `Layout`, not only to a doctype form.

`get_doctype_fields()` (`frappe/public/js/frappe/form/layout.js:56-67`) always starts the list with the
synthetic `__newname` field — a `Data` control with `reqd: 1`, `hidden: 1` and a `get_status` closure that
returns `"Write"` only for a new document whose `autoname` is `prompt` or `name`
(`frappe/public/js/frappe/form/layout.js:69-89`) — and then branches:

| Branch | Source of order | Citation |
|---|---|---|
| No `DocType Layout` | `frappe.meta.sort_docfields(frappe.meta.docfield_map[doctype])` — the values of the fieldname-keyed map, sorted by `idx` alone | `frappe/public/js/frappe/form/layout.js:61-63`; `frappe/public/js/frappe/model/meta.js:120-126` |
| A `DocType Layout` is active | the layout's own `fields` child-table row order, skipping any row whose `fieldname` is absent from `docfield_map` (`if (!base) continue`) | `frappe/public/js/frappe/form/layout.js:91-125`, especially `frappe/public/js/frappe/form/layout.js:108-110` |

Two properties of the first branch matter for the rest of this section. The sort comparator is
`a.idx - b.idx` with no tie-break and no fallback (`frappe/public/js/frappe/model/meta.js:124`), and the
collection it sorts is a **map keyed by `df.fieldname || df.label`**
(`frappe/public/js/frappe/model/meta.js:30`), so the client cannot represent two fields sharing a fieldname
(§2.5).

The second branch also cannot *clear* a flag: `get_fields_from_layout` copies the base docfield and applies
each of the eleven `OVERRIDE_PROPS` only when the layout row's value is truthy
(`frappe/public/js/frappe/form/layout.js:92-105`, `frappe/public/js/frappe/form/layout.js:116-120`), with the source comment stating the reason —
avoiding the overwrite of `Check` fields that default to `0`
(`frappe/public/js/frappe/form/layout.js:115`). The same list and the same truthiness rule are applied a
second time, per refresh, in `attach_doc_and_docfields`
(`frappe/public/js/frappe/form/layout.js:555-568`, `frappe/public/js/frappe/form/layout.js:583-594`).

### 2.2 Algorithm A-01-2 — ordered field list to visual tree

```
Algorithm A-01-2: Meta.fields → visual tree
Entry:    Layout.render(new_fields)                                            (layout.js:169)
Input:    fields ← new_fields || this.fields                                   (layout.js:170)
Terminal: a DOM tree; no post-pass validates it

 1. Reset two of the three cursors:
       this.section ← null; this.column ← null                                 (layout.js:172-173)
    NOTE: this.current_tab is **not** reset here, and is never initialised in
    the constructor — it is only ever assigned in make_tab. A second render()
    on the same Layout therefore inherits the last tab of the previous pass.   (layout.js:6-19, :384)

 2. Untabbed prologue — if no_opening_section() AND NOT is_tabbed_layout():
       this.fields.unshift({ fieldtype: "Section Break" })                     (layout.js:175-177)
    2a. no_opening_section() is true when fields[0].fieldtype != "Section Break",
        or when the list is empty                                              (layout.js:228-232)
    2b. is_tabbed_layout() is true when ANY field has fieldtype "Tab Break"     (layout.js:238-240)
    2c. the unshift mutates this.fields, while step 4 iterates the local
        `fields` binding from step 0 — for render(new_fields) the two differ    (layout.js:170, :176)

 3. Tabbed prologue — if is_tabbed_layout():
 3a.   add_default_tabs(fields)  ← declared with an empty body; no effect      (layout.js:181, :233)
 3b.   first_field_visible ← this.fields.find(el => el.hidden == false)
         (loose equality: matches 0 and false, does NOT match an absent
          `hidden` property)                                                   (layout.js:188)
 3c.   first_tab ← first_field_visible?.fieldtype === "Tab Break"
                     ? first_field_visible : null                              (layout.js:189-190)
 3d.   if NOT first_tab: splice a synthetic Tab Break at index 0
           { label: "Details", fieldtype: "Tab Break", fieldname: "__details" } (layout.js:182-186, :193)
 3e.   else: locate __newname; if newname_field.get_status(this) === "Write",
           remove index 0 and re-insert at index 1, moving it inside the
           first tab                                                           (layout.js:195-200)

 4. for each df in fields, in order — switch (df.fieldtype):                    (layout.js:204-225)
 4a.   "Fold"          → make_page(df)                                         (layout.js:206-208)
 4b.   "Page Break"    → make_page_break(); make_section(df)                   (layout.js:209-212)
 4c.   "Section Break" → make_section(df)                                      (layout.js:213-215)
 4d.   "Column Break"  → make_column(df)                                       (layout.js:216-218)
 4e.   "Tab Break"     → make_tab(df)                                          (layout.js:219-221)
 4f.   default         → make_field(df)                                        (layout.js:222-224)
       There is no lookahead, no lookbehind and no validation of the sequence.

 5. make_section(df = {}):                                                     (layout.js:343-366)
 5a.   section_count ← section_count + 1
 5b.   if df has no fieldname: df.fieldname ← `__section_${section_count}`;
           df.fieldtype ← "Section Break"     ← mutates the caller's object     (layout.js:345-348)
 5c.   section ← new Section(current_tab ? current_tab.wrapper : this.page,
                             df, card_layout, this)                            (layout.js:350-355)
         ⇒ the parent is the open tab pane if one exists, else the current page
 5d.   sections.push(section); sections_dict[df.fieldname] ← section            (layout.js:356-357)
 5e.   fields_dict[df.fieldname] ← section; fields_list.push(section)           (layout.js:360-363)
         ⇒ a Section occupies a fields_dict slot alongside real controls
 5f.   column ← null                                                           (layout.js:365)

 6. make_column(df = {}):                                                      (layout.js:368-379)
 6a.   column_count ← column_count + 1   ← incremented, never used for naming
 6b.   if df has no fieldname: df.fieldname ← `__column_${section_count}`;
           df.fieldtype ← "Column Break"      ← the SECTION counter             (layout.js:370-373)
 6c.   column ← new Column(this.section, df), which:
           pushes itself into section.columns                                  (column.js:7)
           appends .form-column > form to section.body                         (column.js:12-18)
           calls resize_all_columns()                                          (column.js:9, :39-59)
 6d.   if df.fieldname: fields_list.push(column)   ← but NOT fields_dict        (layout.js:376-378)

 7. make_tab(df):                                                              (layout.js:381-388)
 7a.   section ← null
 7b.   tab ← new Tab(this, df, this.frm, tab_link_container, tabs_content)
 7c.   current_tab ← tab
 7d.   make_section({ fieldtype: "Section Break" })
         ⇒ every Tab Break unconditionally opens one implicit section
 7e.   tabs.push(tab)

 8. make_field(df, colspan, render):                                           (layout.js:257-276)
 8a.   if NOT section: make_section()                                          (layout.js:258)
 8b.   if NOT column:  make_column()                                           (layout.js:259)
 8c.   parent ← this.column.form.get(0)                                        (layout.js:261)
 8d.   fieldobj ← init_field(df, parent, render) → frappe.ui.form.make_control  (layout.js:262, :278-303)
 8e.   if fieldobj is null (invalid control name): **return**, registering
         nothing anywhere                                                      (layout.js:264-265)
 8f.   fields_list.push(fieldobj); fields_dict[df.fieldname] ← fieldobj         (layout.js:267-268)
 8g.   section.add_field(fieldobj)  → section.fields_list/fields_dict,
         fieldobj.section ← section                                            (layout.js:270; section.js:102-106)
 8h.   column.add_field(fieldobj)   → **no-op, empty method body**             (layout.js:271; column.js:62)
 8i.   if current_tab: current_tab.add_field(fieldobj) → fieldobj.tab ← tab     (layout.js:273-275; tab.js:88-90)

 9. Terminal structure:
      .form-layout > .form-page[.page-break|.second-page]*
        [ > .form-tab-content > .tab-pane ]?
          > .form-section > .section-body > .form-column > form > controls      (layout.js:25-29, :50-52;
                                                                                 section.js:30-33, :56;
                                                                                 column.js:13-18)
```

Step 5c is the hinge of the whole algorithm: **a section belongs to whichever tab was open when the section
was created**, and nothing later moves it. Step 7d then guarantees that a tab is never left without a
section, and step 8a guarantees that a field is never left without one. The combination means the pass cannot
fail on a missing sentinel — it can only produce a structure the author did not intend (§2.4 to §2.6).

### 2.3 Worked example — `Module Def`

`Module Def` is a nine-field tabbed doctype whose stored order begins with two consecutive `Tab Break` rows.
The order is the `field_order` array at `frappe/core/doctype/module_def/module_def.json:8-18`:
`connections_tab`, `details_tab`, `section_break_dnma`, `module_name`, `app_name`, `restrict_to_domain`,
`package`, `column_break_giia`, `custom`. `connections_tab` carries `show_dashboard: 1`; `autoname` is
`field:module_name`.

Prologue:

| Step | Evaluation for `Module Def` |
|---|---|
| 0 | `fields` = `[__newname, connections_tab, details_tab, section_break_dnma, module_name, app_name, restrict_to_domain, package, column_break_giia, custom]` (`frappe/public/js/frappe/form/layout.js:57-63`) |
| 2 | Skipped: `is_tabbed_layout()` is true (`frappe/public/js/frappe/form/layout.js:175`, `frappe/public/js/frappe/form/layout.js:238-240`) |
| 3b | `__newname` carries `hidden: 1` (`frappe/public/js/frappe/form/layout.js:75`) and fails `== false`; the next entry, `connections_tab`, is a server-supplied DocField whose `hidden` is a `Check` column and therefore present as `0`, so it matches |
| 3c | `first_tab` = `connections_tab` |
| 3e | `newname_field.get_status()` returns `"None"`, because `autoname` is `field:module_name` and the closure only returns `"Write"` for `prompt` or `name` (`frappe/public/js/frappe/form/layout.js:77-87`). **`__newname` is therefore not moved and stays at index 0, ahead of the first `Tab Break`.** |

Dispatch, step by step:

| # | Row | Branch | Effect |
|---|---|---|---|
| 1 | `__newname` (`Data`) | 4f → 8 | `section` is null ⇒ 8a creates `__section_1`; `current_tab` is `undefined`, so 5c parents it to **`.form-page`, outside every tab pane**; 8b creates `__column_1`; the control is rendered there |
| 2 | `connections_tab` (`Tab Break`) | 4e → 7 | Tab with DOM id `module-def-connections_tab` (`frappe/public/js/frappe/form/tab.js:26`); `current_tab` ← it; 7d opens `__section_2` inside its `.tab-pane` |
| 3 | `details_tab` (`Tab Break`) | 4e → 7 | Tab `module-def-details_tab`; `current_tab` ← it; 7d opens `__section_3`. **`__section_2` is now closed holding zero columns and zero controls** |
| 4 | `section_break_dnma` (`Section Break`) | 4c → 5 | The row has a fieldname, so 5b is skipped and the section is keyed `section_break_dnma`; `section_count` nonetheless advances to 4. `__section_3` is left empty |
| 5 | `module_name` (`Data`) | 4f → 8 | `column` is null ⇒ 8b creates a column named `__column_4` — `section_count`, not `column_count` (`frappe/public/js/frappe/form/layout.js:371`) |
| 6–8 | `app_name`, `restrict_to_domain`, `package` | 4f → 8 | appended to the same column |
| 9 | `column_break_giia` (`Column Break`) | 4d → 6 | second column in `section_break_dnma`; `resize_all_columns` now sees two columns ⇒ `col-sm-6` each (`frappe/public/js/frappe/form/column.js:41-45`) |
| 10 | `custom` (`Check`) | 4f → 8 | appended to `column_break_giia` |

Resulting tree, and then what the first refresh does to it:

```
.form-layout
└── .form-page
    ├── .form-tabs-list > ul.form-tabs        [Connections] [Details]      (layout.js:44-49)
    ├── .form-section[__section_1] > .form-column[__column_1] > __newname   ← outside both panes
    └── .form-tab-content                                                   (layout.js:50-52)
        ├── .tab-pane#module-def-connections_tab
        │   ├── .form-dashboard                  ← placed here by form.js:259-267,
        │   │                                       because df.show_dashboard is set
        │   └── .form-section[__section_2]        ← empty
        └── .tab-pane#module-def-details_tab
            ├── .form-section[__section_3]        ← empty
            └── .form-section[section_break_dnma]
                ├── .form-column[__column_4]  module_name, app_name,
                │                             restrict_to_domain, package
                └── .form-column[column_break_giia]  custom
```

On `Layout.refresh`, `refresh_sections` sweeps every `.form-section:not(.hide-control)`, finds no
`.frappe-control:not(.hide-control)` inside `__section_1`, `__section_2` or `__section_3`, and — because each
of their parents is a `.tab-pane` or a `.form-page` — marks all three `empty-section`
(`frappe/public/js/frappe/form/layout.js:428-441`). `refresh_tabs` then runs
(`frappe/public/js/frappe/form/layout.js:444`, `frappe/public/js/frappe/form/layout.js:447-458`) and `Tab.refresh` hides the Connections tab,
because its pane holds no `.form-section` or `.form-dashboard-section` that is neither `hide-control` nor
`empty-section` (`frappe/public/js/frappe/form/tab.js:57-67`).

The Connections tab is therefore **hidden until the dashboard populates it**, and that is the only thing that
can populate it: `Dashboard.setup_dashboard_sections` creates five sections, all with
`is_dashboard_section: 1` and `hidden: 1` — progress, heatmap, chart, stats and the `links_area` labelled
"Connections" (`frappe/public/js/frappe/form/dashboard.js:13-61`) — and `is_dashboard_section` is what
selects the `form-dashboard-section` wrapper class (`frappe/public/js/frappe/form/section.js:31`) that
`Tab.refresh` looks for. A tab that owns no fields at all is thus a normal, intended configuration in this
engine, and its visibility is decided by a DOM query several classes away from the metadata that declared it.

### 2.4 A missing break row

A missing sentinel never raises an error and never leaves a field unplaced. Three fallbacks make that true,
and each substitutes a **synthetic node whose fieldname is generated**:

| Missing row | What happens instead | Citation |
|---|---|---|
| No leading `Section Break`, untabbed layout | one `{fieldtype: "Section Break"}` is unshifted onto `this.fields` before the pass | `frappe/public/js/frappe/form/layout.js:175-177`, `frappe/public/js/frappe/form/layout.js:228-232` |
| No leading `Tab Break`, tabbed layout | a `Tab Break` with fieldname `__details` is spliced in at index 0 | `frappe/public/js/frappe/form/layout.js:182-186`, `frappe/public/js/frappe/form/layout.js:193` |
| No `Section Break` before a field | `make_field` step 8a opens `__section_${section_count}` | `frappe/public/js/frappe/form/layout.js:258`, `frappe/public/js/frappe/form/layout.js:345-348` |
| No `Column Break` before a field | `make_field` step 8b opens `__column_${section_count}` | `frappe/public/js/frappe/form/layout.js:259`, `frappe/public/js/frappe/form/layout.js:370-373` |
| No `Section Break` after a `Tab Break` | `make_tab` step 7d opens one unconditionally | `frappe/public/js/frappe/form/layout.js:385` |

Because `__newname` is always at index 0 of a doctype form's list
(`frappe/public/js/frappe/form/layout.js:57`) and is a `Data` field, `no_opening_section()` is always true for
such a list, so the untabbed prologue always fires. That is what keeps `this.section` non-null when a
`Column Break` row is dispatched — and it is the *only* thing that does, because branch 4d calls
`make_column(df)` directly, with no equivalent of step 8a
(`frappe/public/js/frappe/form/layout.js:216-218`). Where `this.section` is null at a `Column Break`, the
`Column` constructor dereferences it immediately, at `this.section.columns.push(this)`
(`frappe/public/js/frappe/form/column.js:7`), and the pass aborts with a `TypeError`. Two sequences reach
that state:

1. **A `Column Break` immediately after a `Fold`.** `make_page` sets `this.section = null` as its last action
   (`frappe/public/js/frappe/form/layout.js:335`). The guard that prevents this is not in the layout engine at
   all: it is server-side, in `check_fold`, which requires the row after a `Fold` to be a `Section Break`,
   forbids more than one `Fold`, and forbids a `Fold` at the end of the field list
   (`frappe/core/doctype/doctype/doctype.py:1552-1564`). That guard is itself conditional — it runs only
   `if not frappe.flags.in_migrate or in_ci` (`frappe/core/doctype/doctype/doctype.py:1862-1863`), so a
   DocType written during a migration outside CI is not checked.
2. **`Layout.add_fields([...])` whose first entry is a `Column Break`.** `add_fields` calls
   `render(fields)` (`frappe/public/js/frappe/form/layout.js:517-520`), and step 2's unshift targets
   `this.fields` while the pass iterates the passed array
   (`frappe/public/js/frappe/form/layout.js:170`, `frappe/public/js/frappe/form/layout.js:176`), so the fallback cannot help the rows actually
   being rendered.

### 2.5 A duplicated break row

| Duplication | Resulting rendered structure | Citation |
|---|---|---|
| Two consecutive `Section Break` rows | Two `Section` objects. The first is closed with `columns = []` and no controls; it stays in `layout.sections` and keeps its `fields_dict` slot. On refresh it gains `empty-section` — but only because its parent is a `.tab-pane` or a `.form-page`; the sweep's `else if` has no other arm | `frappe/public/js/frappe/form/layout.js:343-366`, `frappe/public/js/frappe/form/layout.js:430-441` |
| Two consecutive `Column Break` rows | Two `Column` objects in `section.columns`. The first holds an empty `<form>` and **is not hidden**: `Column.refresh` toggles `hide-control` only on `df.hidden` or `df.hidden_due_to_dependency`, never on emptiness, and `resize_all_columns` counts every `.form-column` child that lacks `hide-control`. An empty column therefore keeps a full share of the twelve-unit width permanently | `frappe/public/js/frappe/form/column.js:41-45`, `frappe/public/js/frappe/form/column.js:64-70` |
| Two fieldname-less `Column Break` rows in one section | Both synthetic names are `__column_${section_count}` for the same `section_count`, so the two `.form-column` elements carry the **same** `data-fieldname` and `fields_list` holds two entries with equal `df.fieldname`. `Column` is never written to `fields_dict`, so the collision is invisible to `fields_dict` lookups and visible only in the DOM and in `fields_list` | `frappe/public/js/frappe/form/layout.js:370-373`, `frappe/public/js/frappe/form/layout.js:376-378`; `frappe/public/js/frappe/form/column.js:14` |
| Two `Tab Break` rows sharing a fieldname | Both `Tab` objects derive the same DOM id from `scrub(doctype) + "-" + df.fieldname`, so `id` and `aria-controls` are duplicated; `select_tab` and the URL-hash branch of `set_tab_as_active` both resolve with `find`, i.e. to the first match, and the second tab becomes unreachable by name. `make_section` overwrites `sections_dict[fieldname]` and `fields_dict[fieldname]`, so the later implicit section wins those slots | `frappe/public/js/frappe/form/tab.js:26-27`, `frappe/public/js/frappe/form/tab.js:30-44`; `frappe/public/js/frappe/form/layout.js:357`, `frappe/public/js/frappe/form/layout.js:361`, `frappe/public/js/frappe/form/layout.js:460-470`, `frappe/public/js/frappe/form/layout.js:486` |

The last row is mostly unreachable through the supported path, and the guard is again server-side:
`check_unique_fieldname` throws `UniqueFieldnameError` when a fieldname appears in more than one row of the
DocType's field list (`frappe/core/doctype/doctype/doctype.py:1386-1396`), called per field from
`validate_fields` (`frappe/core/doctype/doctype/doctype.py:1850`). It carries the same migration exemption as
the `Fold` rule: the call sits under `if not frappe.flags.in_migrate or in_ci`
(`frappe/core/doctype/doctype/doctype.py:1849-1850`).

If a duplicate fieldname does reach the client, the two client-side registries **disagree about which row
wins**. `frappe.meta.add_field` assigns `docfield_map[parent][fieldname] = df` first, and only then scans
`docfield_list` and returns early on a repeat (`frappe/public/js/frappe/model/meta.js:28-40`). So the map
retains the **last** row synced while the list retains the **first**. `get_doctype_fields` reads the map
(`frappe/public/js/frappe/form/layout.js:62`), so the form renders the duplicate exactly once, and it is the
last one synced.

### 2.6 An out-of-order break row

The client applies no ordering rule whatsoever. Step 4 is a bare `forEach` over the list with a `switch` on
`fieldtype` (`frappe/public/js/frappe/form/layout.js:204-225`); nothing inspects the previous or next row, and
no error path exists. Order is therefore not merely authoritative — it is unaudited. The observable
consequences:

1. **Any field before the first `Tab Break` in a tabbed layout renders outside every tab.** `current_tab` is
   `undefined` until `make_tab` assigns it (`frappe/public/js/frappe/form/layout.js:384`), and `make_section`
   parents to `this.page` in that case (`frappe/public/js/frappe/form/layout.js:351`). The resulting section
   is a sibling of `.form-tab-content`, is reachable from no tab, and is hidden only if it happens to contain
   no visible control (`frappe/public/js/frappe/form/layout.js:434-440`). §2.3 step 1 is a live instance of
   this in a shipped doctype.
2. **A `Section Break` immediately after a `Tab Break` orphans the implicit section.** Step 7d has already
   created `__section_N` (`frappe/public/js/frappe/form/layout.js:385`); the explicit row simply replaces the
   `section` cursor, leaving the implicit section in place, in `layout.sections`, and in `fields_dict`
   (`frappe/public/js/frappe/form/layout.js:343-363`). §2.3 steps 3 and 4 show two such sections in one
   nine-field doctype.
3. **A `Tab Break` after a `Column Break` silently discards the column cursor.** `make_tab` sets
   `section = null` (`frappe/public/js/frappe/form/layout.js:382`) and 7d's `make_section` sets `column = null`
   (`frappe/public/js/frappe/form/layout.js:365`), so the preceding column is closed wherever it was; the DOM
   it created stays.
4. **A `Fold` out of position** is the single ordering case any code rejects, and the rejection is server-side
   and `Fold`-specific (`frappe/core/doctype/doctype/doctype.py:1552-1564`).

That fourth point is the boundary of what is checked anywhere. Searching the DocType validator for the three
sentinel fieldtypes returns two sites only: fieldname synthesis for a break row that has none — appending
`_section`, `_column` or `_tab` to a scrubbed label, or generating
`section_break_<random_string(4)>` — (`frappe/core/doctype/doctype/doctype.py:492-510`), and the `Fold` rule
(`frappe/core/doctype/doctype/doctype.py:1561-1562`). **There is no order constraint on `Tab Break`,
`Section Break` or `Column Break` at either end of the stack.**

### 2.7 What no code decides

Two outcomes are genuinely undetermined by the code, and the honest statement is that they are decided
elsewhere.

1. **Two fields with equal `idx`.** The comparator is `a.idx - b.idx`
   (`frappe/public/js/frappe/model/meta.js:124`) and returns `0`, so the layout engine expresses no preference;
   the resulting order is whatever the host `Array.prototype.sort` leaves for the enumeration order that
   `$.map` produced over the fieldname-keyed map
   (`frappe/public/js/frappe/model/meta.js:121-125`, `frappe/public/js/frappe/model/meta.js:30`). No tie-break exists in this code path. Since a
   sentinel row's position is the entire structural signal, two break rows sharing an `idx` leave the rendered
   nesting undetermined by anything in `frappe/public/js/frappe/form/`.
2. **A field with no `idx`.** The same comparator yields `NaN`, and the code supplies no default
   (`frappe/public/js/frappe/model/meta.js:124`). `get_doctype_fields` consumes the result directly with no
   post-sort normalisation (`frappe/public/js/frappe/form/layout.js:61-63`).

Both are properties of the *comparator*, which is the guard that leaves them open. Neither is reported: there
is no diagnostic, no console warning and no fallback ordering anywhere in `sort_docfields`
(`frappe/public/js/frappe/model/meta.js:120-126`).

## 3. The `*_depends_on` expression family

Four docfield properties carry an expression: `depends_on`, `mandatory_depends_on`, `read_only_depends_on`
and `collapsible_depends_on`. All four are read at render time by the same class, and three of the four are
funnelled through one method, `Layout.evaluate_depends_on_value`
(`frappe/public/js/frappe/form/layout.js:856-896`). That method is the whole of the language: there is no
parser, no AST, no validated grammar and no expression type. An expression is either a fieldname, a string
beginning `eval:`, a string beginning `fn:`, a JavaScript boolean or a JavaScript function, and the branch is
selected by string prefix.

### 3.1 The four properties and what each decides

| Property | Read at | Sets | Polarity | Citation |
|---|---|---|---|---|
| `depends_on` | `Layout.refresh_dependency` | `df.hidden_due_to_dependency` | truthy ⇒ **shown** | `frappe/public/js/frappe/form/layout.js:797-804` |
| `mandatory_depends_on` | `Layout.refresh_dependency` → `set_dependant_property(…, "reqd")` | `df.reqd` ← `1`/`0` | truthy ⇒ **mandatory** | `frappe/public/js/frappe/form/layout.js:806-808`, `frappe/public/js/frappe/form/layout.js:826-853` |
| `read_only_depends_on` | `Layout.refresh_dependency` → `set_dependant_property(…, "read_only")` | `df.read_only` ← `1`/`0` | truthy ⇒ **read-only** | `frappe/public/js/frappe/form/layout.js:810-816`, `frappe/public/js/frappe/form/layout.js:826-853` |
| `collapsible_depends_on` | `Layout.refresh_section_collapse` | `Section.collapse(hide)` | truthy ⇒ **expanded** | `frappe/public/js/frappe/form/layout.js:528-539` |

Three properties therefore share one code path and one polarity convention, and the fourth inverts the
polarity — `collapse = !this.evaluate_depends_on_value(df.collapsible_depends_on)`
(`frappe/public/js/frappe/form/layout.js:532`) — and takes a different route. `collapsible_depends_on` is also
not the final word: after it is evaluated, `collapse` is forced back to `false` if the section holds a `reqd`
field whose value is null, or if the user has expanded the section by hand
(`frappe/public/js/frappe/form/layout.js:535-537`, `frappe/public/js/frappe/form/section.js:151-161`).

`depends_on` applies to more than fields. `refresh_dependency` iterates
`this.fields_list.concat(this.tabs)` (`frappe/public/js/frappe/form/layout.js:793`), and `fields_list` holds
`Section` objects (`frappe/public/js/frappe/form/layout.js:363`) and `Column` objects
(`frappe/public/js/frappe/form/layout.js:377`) alongside real controls, per §2.2 steps 5e and 6d. Each of the
four object kinds consumes `hidden_due_to_dependency` in its own `refresh`, and the four consumers differ:
a control routes it through the permission model
(`frappe/public/js/frappe/form/controls/base_control.js:61-66`,
`frappe/public/js/frappe/model/perm.js:264`), which then decides a `hide-control` class from
`disp_status == "None"` (`frappe/public/js/frappe/form/controls/base_control.js:139-141`), whereas a
`Section` (`frappe/public/js/frappe/form/section.js:111`), a `Column`
(`frappe/public/js/frappe/form/column.js:66`) and a `Tab` (`frappe/public/js/frappe/form/tab.js:51`) each
apply `hide-control` directly, without consulting permissions.

A `DocType Layout` may override three of the four. `depends_on`, `mandatory_depends_on` and
`read_only_depends_on` appear in both override lists — `OVERRIDE_PROPS` in `get_fields_from_layout`
(`frappe/public/js/frappe/form/layout.js:102-104`) and `LAYOUT_OVERRIDE_PROPS` in
`attach_doc_and_docfields` (`frappe/public/js/frappe/form/layout.js:565-567`) — and are subject to the same
truthiness rule as every other overridable property, so a layout can set an expression but cannot clear one
(§2.1). **Absent:** `collapsible_depends_on` is in neither list, and the `DocType Layout Field` child doctype
has no such column at all — its generated field set is `allow_in_quick_entry`, `bold`, `default`,
`depends_on`, `description`, `fieldname`, `hidden`, `in_list_view`, `in_standard_filter`, `label`,
`mandatory_depends_on`, `parent`, `parentfield`, `parenttype`, `read_only`, `read_only_depends_on`, `reqd`
(`frappe/core/doctype/doctype_layout_field/doctype_layout_field.py:15-34`). No line number is given for the
missing column because there is none.

### 3.2 Evaluation scope — what an expression can see

`evaluate_depends_on_value` first resolves the object that will be bound as `doc`, and returns `undefined`
without evaluating anything if it cannot (`frappe/public/js/frappe/form/layout.js:857-866`). It then computes
a second binding, `parent`, as `this.frm ? this.frm.doc : this.doc || null`
(`frappe/public/js/frappe/form/layout.js:868`). Those two names are the entire declared context.

| Host | `doc` is bound to | `parent` is bound to | Citation |
|---|---|---|---|
| Doctype form | `layout.doc`, the model document set by `render_form` | the same object, via `this.frm.doc` | `frappe/public/js/frappe/form/layout.js:858`, `frappe/public/js/frappe/form/layout.js:868`; `frappe/public/js/frappe/form/form.js:611` |
| Dialog / `FieldGroup` | a **freshly built plain object** from `this.get_values(true)` | `null`, because `this.doc` is unset and `this.frm` is absent | `frappe/public/js/frappe/form/layout.js:860-862`, `frappe/public/js/frappe/form/layout.js:868`; `frappe/public/js/frappe/ui/field_group.js:5`, `frappe/public/js/frappe/ui/field_group.js:137-165` |
| Grid row (collapsed, in-grid controls) | `grid_row.doc`, the child row | the parent form's document | `frappe/public/js/frappe/form/grid_row.js:843-847` |
| Grid row form (expanded row) | the child row, via the row form's own `Layout` | the parent document, because that `Layout` carries `frm` | `frappe/public/js/frappe/form/grid_row_form.js:137-144`; `frappe/public/js/frappe/form/layout.js:868` |

Two consequences of the dialog row are load-bearing. `get_values` copies a value into the result **only when
it is not null** (`frappe/public/js/frappe/ui/field_group.js:155`), so in a dialog an empty field is *absent*
from `doc` rather than present as `null`; an expression such as `eval:doc.x.length` therefore throws in a
dialog where it would merely be falsy on a form. And because `get_values` loops every field in
`fields_dict` on each call (`frappe/public/js/frappe/ui/field_group.js:142-165`) while
`evaluate_depends_on_value` calls it once per expression, one dependency pass over a dialog of `N` fields of
which `k` carry expressions performs `k` full value-collection loops.

For the `eval:` branch the two bindings are *not* the scope. The expression body is compiled by
`frappe.utils.eval`, which builds `new Function(...variable_names, "let out = " + code + "; return out")`
(`frappe/public/js/frappe/utils/utils.js:1205-1207`), called from
`frappe/public/js/frappe/form/layout.js:876` with the context object `{ doc, parent }`. A function built by
the `Function` constructor does not close over the lexical scope of its construction site; its outer
environment is the global environment. An `eval:` expression can therefore reach **every global the desk
bundle defines** — `frappe`, `cur_frm`, `locals`, `flt`, `cint`, `precision` and `in_list` among them, the
last being a real global assigned by `Object.assign(window, { … in_list })`
(`frappe/public/js/frappe/utils/number_format.js:280-282`,
`frappe/public/js/frappe/utils/number_format.js:321-337`), which is why
`eval:in_list([…], doc.due_date_based_on)` works as a docfield expression
(`accounts/doctype/payment_term/payment_term.json:60`). It can also write to them: the generated body is
not in strict mode, and nothing rewrites or inspects the text before compilation.

Two further scope facts follow from the template `let out = ${code}; return out`
(`frappe/public/js/frappe/utils/utils.js:1205`). First, `code` must be an *expression*: a statement form such
as `if (…) {…}` is a `SyntaxError` at compile time, not a falsy result. Second, because `code` is textually
interpolated at statement position, a semicolon in the expression escapes the assignment — `1; f()` compiles
to `let out = 1; f(); return out` — so the mechanism admits arbitrary statement sequences, not only
expressions. The compiled function is memoised in a module-level `Map` keyed on the code text plus the
context variable names, for bodies under 500 characters
(`frappe/public/js/frappe/utils/utils.js:9`, `frappe/public/js/frappe/utils/utils.js:1198-1202`,
`frappe/public/js/frappe/utils/utils.js:1214-1216`); the map is never evicted.

The remaining three branches see far less. A boolean is returned as-is; a function is invoked as
`expression(doc)`, which is reachable only from code-supplied docfields, never from stored metadata
(`frappe/public/js/frappe/form/layout.js:870-873`). The bare-fieldname branch performs a single property
lookup, `doc[expression]`, coercing an array to `!!value.length` and anything else to `!!value`
(`frappe/public/js/frappe/form/layout.js:886-893`) — which is why `collapsible_depends_on: "deductions"` on
a `Table` field behaves as "expanded when the table has rows"
(`accounts/doctype/payment_entry/payment_entry.json:397`). A fieldname that does not exist on the document
yields `undefined`, hence `false`, hence hidden: **the non-`eval:` branch fails closed**, silently.

### 3.3 Evaluation timing

§1.1 step 13 establishes the full-refresh entry point: `Layout.refresh` calls `refresh_dependency()` at
`frappe/public/js/frappe/form/layout.js:405` and, only when a `frm` is present,
`refresh_section_collapse()` at `frappe/public/js/frappe/form/layout.js:410-413`. Four further entry points
exist, and they do not agree on which of the four properties they re-evaluate.

| Trigger | Re-evaluates | Citation |
|---|---|---|
| Any model change on the main document | `depends_on`, `mandatory_depends_on`, `read_only_depends_on` — **not** `collapsible_depends_on` | `frappe/public/js/frappe/form/form.js:311-312` |
| `frm.refresh_field(fieldname)` | the same three | `frappe/public/js/frappe/form/form.js:1603-1608` |
| A change to an in-grid control, or `Grid.set_value` | the three, for that grid row only | `frappe/public/js/frappe/form/grid_row.js:1199-1201`, `frappe/public/js/frappe/form/grid.js:1199-1206` |
| A change inside an expanded grid row form | the three, via that row form's `Layout` | `frappe/public/js/frappe/form/grid_row_form.js:143` |
| Save, for `mandatory_depends_on` only | `mandatory_depends_on`, re-evaluated independently of the render pass | `frappe/public/js/frappe/form/save.js:24`, `frappe/public/js/frappe/form/save.js:275-304` |

Three timing consequences are worth stating exactly.

1. **`collapsible_depends_on` is evaluated only on a full layout refresh.** `refresh_section_collapse` has
   exactly two callers, `Layout.refresh` (`frappe/public/js/frappe/form/layout.js:412`) and the dialog
   constructor (`frappe/public/js/frappe/ui/dialog.js:66`). The model-change handler calls
   `refresh_dependency()` and `refresh_sections()` but not `refresh_section_collapse()`
   (`frappe/public/js/frappe/form/form.js:311-312`), so a section whose `collapsible_depends_on` references
   a field the user has just edited does not open or close until something forces a whole-form refresh.
2. **Writing a dependent property re-enters the pass.** `set_dependant_property` calls
   `form_obj.set_df_property` (`frappe/public/js/frappe/form/layout.js:851`), which writes the property and
   then calls `this.refresh_field(fieldname)` — but only if the value actually changed
   (`frappe/public/js/frappe/form/form.js:1874-1885`) — and `refresh_field` calls
   `layout.refresh_dependency()` and `layout.refresh_sections()` again
   (`frappe/public/js/frappe/form/form.js:1606-1607`). A refresh in which `k` dependent properties change
   value therefore performs at least `k + 1` complete passes over the field list, i.e. at least
   `(k + 1) × N` expression evaluations plus `k + 1` full `.form-section` DOM sweeps
   (`frappe/public/js/frappe/form/layout.js:428-441`), for `N` expressions. The `df[property] != value`
   guard is what terminates the recursion; there is no depth counter and no re-entrancy flag on
   `refresh_dependency` itself. The grid-row implementation avoids this by batching — it computes every
   property first and calls `refresh()` once, and only if something changed
   (`frappe/public/js/frappe/form/grid_row.js:812-839`).
3. **`depends_on` never triggers re-entry.** The `depends_on` arm calls `f.refresh()`, a control refresh
   (`frappe/public/js/frappe/form/layout.js:800-803`), not `frm.refresh_field`, so it does not recurse. The
   asymmetry is invisible from the metadata: two expressions written the same way, on the same field, have
   different re-entrancy behaviour depending on which property carries them.

Hiding a field by `depends_on` does not clear its value: `refresh_dependency` sets a flag and refreshes the
control, nothing more (`frappe/public/js/frappe/form/layout.js:796-804`). A value entered while a field was
visible is still in the document and is still submitted after the field becomes hidden. The report-filter
evaluator makes the opposite choice for the same expression syntax, resetting the filter to its default when
it becomes hidden (`frappe/public/js/frappe/views/reports/query_report.js:571`).

### 3.4 Failure behaviour

Only the `eval:` branch is wrapped. The `try` covers the single call to `frappe.utils.eval`, and the `catch`
discards the caught error and calls `frappe.throw(__('Invalid "depends_on" expression'))`
(`frappe/public/js/frappe/form/layout.js:874-879`). Both a compile failure and a run-time failure land there:
`frappe.utils.eval` rethrows in both cases, after logging the offending text to the console
(`frappe/public/js/frappe/utils/utils.js:1208-1212` for `new Function`,
`frappe/public/js/frappe/utils/utils.js:1219-1225` for invocation). A compile failure is never memoised —
the cache write at `frappe/public/js/frappe/utils/utils.js:1214-1216` is unreachable when `new Function`
throws — so a syntactically invalid expression is recompiled, and rethrows, on every pass.

`frappe.throw` is not a silent signal. It normalises the message, calls `frappe.msgprint` and then
`throw new Error(msg.message)` (`frappe/public/js/frappe/ui/messages.js:21-28`). So the user *is* told, by a
red modal titled "Error", and the exception *does* propagate. What the user is told is the fixed string
`Invalid "depends_on" expression`: it names neither the fieldname, nor the property — a
`read_only_depends_on` failure reports itself as a `depends_on` failure — nor the expression text, which goes
only to the browser console. On a form with several bad expressions the same modal appears with no way to
distinguish them.

The propagation path determines the rendered outcome, and it is a fail-open one:

1. The throw leaves `evaluate_depends_on_value` before `should_hide` is computed, so the assignment
   `f.df.hidden_due_to_dependency = should_hide` at
   `frappe/public/js/frappe/form/layout.js:800-801` never happens. The field keeps whatever value the
   property already had — `undefined` on a first render, which is falsy. **A field whose `depends_on`
   expression throws is rendered visible**, and one that was previously hidden by a working evaluation stays
   hidden until a later pass succeeds. The same holds for `read_only_depends_on` and
   `mandatory_depends_on`: `set_dependant_property` throws at its first statement
   (`frappe/public/js/frappe/form/layout.js:827`), so no property is written and the field keeps its stored
   `read_only` and `reqd`.
2. The throw exits the `for (const f of fields)` loop
   (`frappe/public/js/frappe/form/layout.js:796-823`). Every field **after** the failing one in
   `fields_list.concat(tabs)` order is left unevaluated for that pass. Which fields those are depends on
   `idx` order, so the blast radius of one bad expression is a function of where the field sits in the form.
3. `refresh_dependency` was called from `Layout.refresh` at
   `frappe/public/js/frappe/form/layout.js:405`, so `refresh_sections()` (line 408) and
   `refresh_section_collapse()` (lines 410-413) do not run either. Sections are left without their
   `visible-section` / `empty-section` classification and tabs without their visibility pass (§2.3), because
   `refresh_tabs` is reached only from the end of `refresh_sections`
   (`frappe/public/js/frappe/form/layout.js:444`).
4. `Layout.refresh` was reached from `frm.refresh_fields()`
   (`frappe/public/js/frappe/form/form.js:836`), which is the fourth task in the `run_serially` chain
   (`frappe/public/js/frappe/form/form.js:628-647`). `frappe.run_serially` chains with `.then` and attaches
   no handler (`frappe/public/js/frappe/dom.js:269-277`), and `render_form` discards the returned promise
   (`frappe/public/js/frappe/form/form.js:628`). Everything after `refresh_fields` is therefore skipped —
   the `refresh` client script, `apply_layout_defaults`, `onload_post_render`, `focus_on_first_input`,
   `run_after_load_hook`, `dashboard.after_refresh`, the `cscript.is_onload = false` reset and
   `configure_breadcrumb_width` — and the rejection surfaces only as an unhandled promise rejection. Because
   `is_onload` is never cleared, the *next* refresh still believes it is the first.

One latent hazard sits in the child-row arm of `set_dependant_property`. It sets
`form_obj.setting_dependency = true`, calls `set_df_property`, then sets the flag back to `false`
(`frappe/public/js/frappe/form/layout.js:838-847`), with no `try`/`finally`. `Grid.refresh` returns
immediately while that flag is set (`frappe/public/js/frappe/form/grid.js:652-653`), so an exception raised
inside the guarded window strands the flag and turns **every** subsequent grid refresh on that form into a
no-op for the lifetime of the form object. The expression evaluation itself happens earlier, at
`frappe/public/js/frappe/form/layout.js:827`, so a throwing expression does not reach this window; only a
failure inside `set_df_property` does.

**Absent:** no code path degrades a failed expression to a defined default. Searched: the four `catch` arms
reachable from a docfield expression — `frappe/public/js/frappe/form/layout.js:877-879`,
`frappe/public/js/frappe/form/grid_row.js:856-858`,
`frappe/public/js/frappe/form/save.js:288-290` and
`frappe/public/js/frappe/views/reports/query_report.js:588-591` — all of which call `frappe.throw`. There is
no `frappe.log_error` call, no invalid-expression indicator on the field, and no record of the failure in the
document or on the server. No line number is given for the absent fallback.

The one evaluator that does degrade gracefully is not on the form path. `settings_map.js` reimplements the
same language for the Doctype Settings view and returns `true` on failure, after a `console.warn`, with the
stated intent that "one bad expression can't blank the tab"
(`frappe/public/js/frappe/form/doctype_settings/tabs/settings_map.js:184-200`, especially
`frappe/public/js/frappe/form/doctype_settings/tabs/settings_map.js:190-195`). The same expression text can
therefore fail open in one host and abort the render in another.

### 3.5 Which mechanisms evaluate user-authored text dynamically

The lead recorded for this sub-task is confirmed. `Form._resolve_layout` compiles a user-authored
`DocType Layout.condition` with ``new Function("doc", `return !!(${l.condition})`)(this.doc)`` at
`frappe/public/js/frappe/form/form.js:681`, immediately under an
`// eslint-disable-next-line no-new-func` comment at `frappe/public/js/frappe/form/form.js:680`, inside a
`try` whose `catch` only calls `console.warn` (`frappe/public/js/frappe/form/form.js:686-688`) — so a broken
layout condition is treated as "did not match", silently, and the loop continues to the next candidate
layout. That call site is uncached: it recompiles every candidate condition on every `_resolve_layout`, which
runs first in the refresh chain (`frappe/public/js/frappe/form/form.js:630`).

The `*_depends_on` family reaches the **same primitive by a different route**. It does not use
`new Function` directly; it calls `frappe.utils.eval`, which uses `new Function` at
`frappe/public/js/frappe/utils/utils.js:1207`. The differences between the two routes are the caching
(`frappe/public/js/frappe/utils/utils.js:1198-1216` versus none), the bound names (`doc` and `parent` versus
`doc` alone) and the failure policy (`frappe.throw` versus `console.warn`). The underlying capability is
identical: compilation of stored text into a function that runs with global authority.

Stated plainly, for target rule X-5:

| Mechanism | Text authored by | Dynamically evaluated? | Primitive and citation |
|---|---|---|---|
| `depends_on`, `mandatory_depends_on`, `read_only_depends_on`, `collapsible_depends_on` with an `eval:` prefix | a user, via DocType, Customize Form, Custom Field or DocType Layout | **yes** | `new Function`, via `frappe.utils.eval` (`frappe/public/js/frappe/utils/utils.js:1205-1207`), called at `frappe/public/js/frappe/form/layout.js:876`, `frappe/public/js/frappe/form/grid_row.js:855`, `frappe/public/js/frappe/form/save.js:287` |
| the same four properties written as a bare fieldname | a user | **no** — a property lookup `doc[expression]` | `frappe/public/js/frappe/form/layout.js:886-893` |
| the same four properties with an `fn:` prefix | a user | no — a script-manager event name | `frappe/public/js/frappe/form/layout.js:880-885` |
| `DocType Layout.condition` | a user | **yes** | `new Function("doc", …)` (`frappe/public/js/frappe/form/form.js:681`) |
| the `function` branch of the evaluator | framework or app code, never stored metadata | no — a direct call | `frappe/public/js/frappe/form/layout.js:872-873` |

Two adjacent sites are named for completeness, because they also compile or evaluate text during form
interaction and would otherwise look like omissions: `Client Script` bodies, compiled with
`new Function(client_script)()` (`frappe/public/js/frappe/form/script_manager.js:191`), which
`docs/logic/21-extensibility-hooks-and-regional.md` owns; and `frappe.utils.eval_expression`, which passes a
digits-and-operators string typed into a numeric input to `(0, eval)` behind a
`/^[0-9+\-/*.() ]+$/` character-class test (`frappe/public/js/frappe/utils/utils.js:2290-2297`). The latter
is a *value* path rather than a layout path and belongs to §6, but it is the third dynamic-evaluation site
reachable from an ordinary form and is recorded here so the X-5 evidence base is complete.

The only guard on expression text anywhere is a publish-time regex, and it is narrow.
`check_illegal_depends_on_conditions` rejects a stored expression when it contains `=` **and**
`DEPENDS_ON_PATTERN` matches (`frappe/core/doctype/doctype/doctype.py:1667-1678`), with the pattern
`re.compile(r'[\w\.:_]+\s*={1}\s*[\w\.@\'"]+')` at `frappe/core/doctype/doctype/doctype.py:42`. Because the
check uses `re.match`, it is anchored at position 0, and because the leading character class excludes spaces,
brackets and operators, it only fires when the very first token of the expression is assigned to. Observed
behaviour of that pattern against the expression forms this section discusses: `eval:doc.status="Open"` is
rejected; `eval:doc.status=="Open"` is accepted, correctly; and `eval:doc.a==1 && doc.b=2` and
`eval: doc.x=1` — an assignment not at position 0, and an assignment preceded by a space — are both
**accepted**. The guard also runs only under `if not frappe.flags.in_migrate or in_ci`
(`frappe/core/doctype/doctype/doctype.py:1849`, `frappe/core/doctype/doctype/doctype.py:1856`), the same
exemption §2.4 and §2.5 record for `check_fold` and `check_unique_fieldname`. It reaches expressions arriving
through `Custom Field` and `Property Setter`, both of which re-run `validate_fields_for_doctype`
(`frappe/custom/doctype/custom_field/custom_field.py:217-219`,
`frappe/custom/doctype/property_setter/property_setter.py:56-63`). **Absent:** it does not reach expressions
arriving through `DocType Layout Field`. `DocType Layout.validate` checks developer mode and the `based_on`
document type and nothing else (`frappe/core/doctype/doctype_layout/doctype_layout.py:74-88`); no call to
`validate_fields_for_doctype` exists in that file, so no line number is cited for it.

### 3.6 Client-side only — no server-side evaluator

**Absent.** No server-side evaluation of any of the four properties exists in the pinned trees. Searched:
`grep -rn "depends_on" --include=*.py` across `/projects/sandbox/frappe/frappe` and
`/projects/sandbox/erpnext/erpnext`. Every hit is one of four kinds, none of which evaluates the expression —
a generated type annotation in a doctype controller stub
(`frappe/core/doctype/docfield/docfield.py:26`, `frappe/core/doctype/docfield/docfield.py:98`,
`frappe/core/doctype/docfield/docfield.py:119`); the publish-time regex guard of §3.5
(`frappe/core/doctype/doctype/doctype.py:1667-1678`); a *writer* of expression text, such as the permission
scaffolding that stores `f"eval:{frappe.as_json(all_doc_types)}.includes(doc.{field})"` into a `Custom Field`
(`frappe/core/doctype/permission_type/permission_type.py:100-101`) or the ERPNext patches that install
inventory-dimension expressions (`patches/v16_0/depends_on_inv_dimensions.py:60`,
`patches/v16_0/packed_item_inv_dimen.py:25`); or a *shipper* of expression text to the client, which
`settings_map.py` does explicitly, sending `depends_on` and `read_only_depends_on` untranslated with the
comment "Raw expressions (JavaScript) — evaluated client-side"
(`frappe/desk/doctype_settings/settings_map.py:103-105`) and building a `doc` context for that client-side
evaluation (`frappe/desk/doctype_settings/settings_map.py:112-120`). No line number is given for the absent
evaluator.

What the server does enforce is the **stored** flag, not the expression:

- Mandatory. `_get_missing_mandatory_fields` selects `self.meta.get("fields", {"reqd": ("=", 1)})`
  (`frappe/model/base_document.py:1017`, in the method beginning at
  `frappe/model/base_document.py:983`), and `_validate_mandatory` raises `frappe.MandatoryError` from that
  list (`frappe/model/document.py:1491-1512`). `mandatory_depends_on` is not consulted.
- Read-only. `grep -rn "read_only" frappe/model/base_document.py` returns nothing; the server does not
  reject a write to a field marked `read_only`, with or without an expression. The nearest related server
  behaviour is the update-after-submit check, `_validate_update_after_submit`
  (`frappe/model/document.py:1487`), which is keyed on `allow_on_submit`, not on `read_only`.

The client, meanwhile, applies `mandatory_depends_on` as an *override* of `reqd` rather than an addition to
it. `frappe.ui.form.check_mandatory` skips any field with neither `reqd` nor `mandatory_depends_on`
(`frappe/public/js/frappe/form/save.js:147`), and for the rest calls `is_docfield_mandatory`, which returns
the evaluated expression when `mandatory_depends_on` is set and falls back to `!!df.reqd` only when it is not
(`frappe/public/js/frappe/form/save.js:275-303`). Two divergences follow directly:

1. A field with stored `reqd: 1` **and** a `mandatory_depends_on` that evaluates false passes the client
   gate (`frappe/public/js/frappe/form/save.js:303` is not reached) and is then rejected by the server
   (`frappe/model/base_document.py:1017`). The user sees a server `MandatoryError` for a field the form
   declared optional.
2. A field with stored `reqd: 0` and a `mandatory_depends_on` that evaluates true is blocked by the client
   and would have been accepted by the server. This is the shape ERPNext's own patches install deliberately —
   `{"reqd": 0, "mandatory_depends_on": "eval:doc.s_warehouse"}`
   (`patches/v16_0/depends_on_inv_dimensions.py:60`) — and it means the requirement exists only for users
   arriving through the desk form.

Therefore **neither `mandatory_depends_on` nor `read_only_depends_on` is a security or integrity boundary**.
`read_only_depends_on` has no server counterpart at all, and `mandatory_depends_on` has one that ignores it.
Both are presentation, and any guarantee stated in terms of them holds only for a client that chooses to run
the expression. `depends_on` is likewise presentation: it sets a display flag
(`frappe/public/js/frappe/form/layout.js:801`) which reaches `get_field_display_status` as a `"None"` status
(`frappe/public/js/frappe/model/perm.js:264`) without touching the permission decision itself — the
permission arms above it (`frappe/public/js/frappe/model/perm.js:250-256`) are unaffected, and a hidden
field's value is still submitted (§3.3).

### 3.7 Worked example — `Payment Term.discount_validity`

`Payment Term` carries both a bare-fieldname `depends_on` and a bare-fieldname `mandatory_depends_on` on one
field, and no `reqd`, which makes it a complete trace of the client/server divergence. The field is

```json
{
 "depends_on": "discount",
 "fieldname": "discount_validity",
 "fieldtype": "Int",
 "label": "Discount Validity",
 "mandatory_depends_on": "discount"
}
```

at `accounts/doctype/payment_term/payment_term.json:106-112`, in a form whose `discount` field is a plain
`Float` with no default (`accounts/doctype/payment_term/payment_term.json:93-97`).

State A — a new document, `doc.discount` falsy (absent, or `0`):

| Step | Evaluation | Citation |
|---|---|---|
| `refresh_dependency` reaches the control | `f.df.depends_on` is `"discount"` — truthy, so the arm is entered | `frappe/public/js/frappe/form/layout.js:797` |
| `evaluate_depends_on_value("discount")` | not boolean, not function, no `eval:` prefix, no `fn:` prefix ⇒ `doc["discount"]`; not an array ⇒ `!!0` = `false` | `frappe/public/js/frappe/form/layout.js:886-892` |
| back in the caller | `should_hide = !false = true`; `hidden_due_to_dependency` is `undefined ≠ true`, so it is set to `true` and `f.refresh()` runs | `frappe/public/js/frappe/form/layout.js:798-803` |
| `f.refresh()` | `get_status()` → `get_field_display_status` → `cint(df.hidden_due_to_dependency)` ⇒ `"None"` | `frappe/public/js/frappe/form/controls/base_control.js:139`, `frappe/public/js/frappe/model/perm.js:264` |
| render decision | `$wrapper.toggleClass("hide-control", true)` — the field is hidden | `frappe/public/js/frappe/form/controls/base_control.js:141` |
| `mandatory_depends_on` arm | `set_dependant_property("discount", "discount_validity", "reqd")` → evaluates `false` ⇒ `value = 0` ⇒ `set_df_property(…, "reqd", 0)` | `frappe/public/js/frappe/form/layout.js:806-807`, `frappe/public/js/frappe/form/layout.js:827-828`, `frappe/public/js/frappe/form/layout.js:851` |
| re-entrancy | the stored `reqd` is absent, so `df.reqd` is `undefined`; `undefined != 0` is **true**, so the property is written and `refresh_field` runs, re-entering `refresh_dependency` once | `frappe/public/js/frappe/form/form.js:1874-1885`, `frappe/public/js/frappe/form/form.js:1606` |
| the section around it | `discount_validity_based_on` carries the same `depends_on: "discount"` and hides identically, so the section body ends with no visible `.frappe-control` and gains `empty-section` | `accounts/doctype/payment_term/payment_term.json:98-105`; `frappe/public/js/frappe/form/layout.js:430-441` |

State B — the user types `10` into `discount`. The model-change handler fires
(`frappe/public/js/frappe/form/form.js:311-312`), `evaluate_depends_on_value("discount")` now returns
`!!10 = true`, `should_hide` becomes `false`, `hidden_due_to_dependency` flips and the control loses
`hide-control`; `set_dependant_property` computes `value = 1` and writes `df.reqd = 1`, so the field renders
with its mandatory indicator. Saving with `discount_validity` empty is now blocked on the client, because
`is_docfield_mandatory` re-evaluates `"discount"` against the document and returns `true`
(`frappe/public/js/frappe/form/save.js:276`, `frappe/public/js/frappe/form/save.js:291-298`).

State C — the same document submitted by any non-desk caller.
`accounts/doctype/payment_term/payment_term.json:106-112` sets no `reqd`, so
`_get_missing_mandatory_fields` selects nothing for this field
(`frappe/model/base_document.py:1017`) and a `Payment Term` with `discount = 10` and
`discount_validity = null` saves without complaint. The requirement expressed by `mandatory_depends_on`
exists only in the browser.

For contrast, the same document's `credit_days` uses the `eval:` branch —
`eval:in_list(['Day(s) after invoice date', 'Day(s) after the end of the invoice month'], doc.due_date_based_on)`
(`accounts/doctype/payment_term/payment_term.json:60`) — which compiles to
`let out = in_list([…], doc.due_date_based_on); return out` and resolves `in_list` through the global
environment (`frappe/public/js/frappe/utils/utils.js:1205-1207`;
`frappe/public/js/frappe/utils/number_format.js:321-337`). Had `in_list` not been a global, the expression
would have thrown a `ReferenceError` on every refresh and taken the modal, the remainder of the field loop
and the remainder of the refresh chain with it, per §3.4.

### 3.8 Findings recorded for §8

Six behaviours observed while reading this path are defects rather than descriptions. They are stated here in
prose; the numbered inventory and the verdicts are §8's and §10's to write.

1. **A `doc.`-prefixed expression without the `eval:` prefix silently evaluates to `false`.** The
   bare-fieldname branch does `doc[expression]`
   (`frappe/public/js/frappe/form/layout.js:887`), so `"doc.party_type"` is looked up as a *fieldname*
   literally spelled `doc.party_type`, yields `undefined`, and the dependent property is set to its falsy
   outcome forever. Five live instances ship in ERPNext at this commit:
   `accounts/doctype/payment_request/payment_request.json:367` (a section permanently collapsed),
   `accounts/doctype/payment_entry/payment_entry.json:655` and
   `stock/doctype/purchase_receipt_item/purchase_receipt_item.json:863` (fields permanently hidden), and
   `accounts/doctype/payment_reconciliation/payment_reconciliation.json:211` and
   `accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.json:152` (fields whose
   `reqd` is permanently forced to `0`). Nothing reports the mistake: the branch has no diagnostic, and the
   publish-time guard of §3.5 tests only for assignment.
2. **The `fn:` branch is dead as a predicate.** It assigns `this.frm.script_manager.trigger(...)` to `out`
   (`frappe/public/js/frappe/form/layout.js:880-885`), and `trigger` returns
   `frappe.run_serially(tasks)` (`frappe/public/js/frappe/form/script_manager.js:141`), which returns a
   `Promise` (`frappe/public/js/frappe/dom.js:269-277`). A `Promise` is always truthy, so `fn:` in
   `depends_on` always shows the field, in `mandatory_depends_on` always sets `reqd = 1`, in
   `read_only_depends_on` always sets `read_only = 1`, and in `collapsible_depends_on` always expands the
   section — whatever the handler returns. No shipped doctype in either tree uses the prefix: searching all
   `*.json` in both trees for `"depends_on": "fn:` and the three sibling properties returns nothing. The
   `settings_map` reimplementation short-circuits the prefix to `true` deliberately, with the comment "no
   frm/script-manager context here" (`frappe/public/js/frappe/form/doctype_settings/tabs/settings_map.js:197`).
3. **The assignment guard is anchored and therefore incomplete**, as measured in §3.5:
   `eval:doc.a==1 && doc.b=2` and `eval: doc.x=1` both pass
   (`frappe/core/doctype/doctype/doctype.py:42`, `frappe/core/doctype/doctype/doctype.py:1677`), and the
   guard does not run for expressions arriving through `DocType Layout Field`
   (`frappe/core/doctype/doctype_layout/doctype_layout.py:74-88`).
4. **`reqd` and `depends_on` are validated independently, so an unsatisfiable save state is reachable.**
   `check_hidden_and_mandatory` looks only at the static `hidden` flag
   (`frappe/core/doctype/doctype/doctype.py:1442-1449`), and no validator relates `depends_on` to `reqd` —
   searched the per-field validator list at `frappe/core/doctype/doctype/doctype.py:1837-1860`, which
   contains `check_hidden_and_mandatory` and `check_illegal_depends_on_conditions` but no rule connecting
   them; no line number is cited for the absent rule. A field with `reqd: 1` and a `depends_on` that hides it
   still blocks the save, because `is_docfield_mandatory` returns `!!df.reqd` and ignores
   `hidden_due_to_dependency` entirely (`frappe/public/js/frappe/form/save.js:147`,
   `frappe/public/js/frappe/form/save.js:303`), and `check_mandatory` then scrolls the user to a field that
   is not on screen (`frappe/public/js/frappe/form/save.js:163-165`).
5. **One expression language has five independent implementations, which disagree.** The five are
   `Layout.evaluate_depends_on_value` (`frappe/public/js/frappe/form/layout.js:856-896`),
   `GridRow.evaluate_depends_on_value` (`frappe/public/js/frappe/form/grid_row.js:841-875`),
   `is_docfield_mandatory` in the save gate (`frappe/public/js/frappe/form/save.js:275-304`),
   `evaluate` in the settings map (`frappe/public/js/frappe/form/doctype_settings/tabs/settings_map.js:184-200`)
   and `evaluate_depends_on_value` in the form builder
   (`frappe/public/js/form_builder/utils.js:203-230`); a sixth, for report filters, omits the `parent`
   binding altogether (`frappe/public/js/frappe/views/reports/query_report.js:578-602`,
   especially `frappe/public/js/frappe/views/reports/query_report.js:586`). They differ in the branches they
   implement, in what `parent` is bound to, and — the material difference — in failure policy: four throw,
   one fails open. The settings-map copy carries a comment naming the original it mirrors and the branch it
   drops (`frappe/public/js/frappe/form/doctype_settings/tabs/settings_map.js:182-183`), which is an
   acknowledgement of the duplication rather than a fix for it.
6. **The dependency pass is quadratic in the number of changing properties**, per §3.3 item 2, and the
   two implementations disagree about it: the form re-enters the whole pass once per changed property
   (`frappe/public/js/frappe/form/form.js:1606`), while the grid batches and refreshes once
   (`frappe/public/js/frappe/form/grid_row.js:830-838`).

## 4. Render effect of the field flags

Seven docfield flags are named in Requirement 6.5. They do not form a family. Three of them —
`hidden`, `read_only` and `allow_on_submit` — are consumed by one function,
`frappe.perm.get_field_display_status` (`frappe/public/js/frappe/model/perm.js:232`), which reduces every
input to one of three strings, `"Read"`, `"Write"` or `"None"`
(`frappe/public/js/frappe/model/perm.js:233-234`). One, `bold`, is applied after that decision and only if it
was not `"None"`. One, `in_list_view`, has **no effect on the parent form at all**. One, `print_hide`, is not
read by the form runtime, only by the print path. And one, `translatable`, does not translate anything on a
form; it conditions a button.

The analytical question this section answers for each flag is whether its effect exists anywhere other than
the browser. §3.6 settled that question for `mandatory_depends_on` and `read_only_depends_on` — neither is a
security or integrity boundary, the first because the server ignores it and the second because the server has
no counterpart — and the same server-side search was run independently for each of the seven flags below. The
answers differ: one of the seven is a genuine server-enforced constraint, one is enforced only on the print
path, and five are presentation.

### 4.1 The pipeline the flags feed

`get_field_display_status` applies its inputs in a fixed order, and the order is load-bearing because later
arms overwrite earlier ones. Numbered as the code sequences them:

| # | Arm | Effect on `status` | Citation |
|---|---|---|---|
| 1 | permission at `df.permlevel` | `"Write"` if `p.write` and not `df.disabled` and not `df.is_virtual`; else `"Read"` if `p.read`; else the initial `"None"` | `frappe/public/js/frappe/model/perm.js:246-256` |
| 2 | **`hidden`** | `cint(df.hidden)` ⇒ `"None"`, unconditionally, overwriting a `"Write"` | `frappe/public/js/frappe/model/perm.js:260` |
| 3 | `hidden_due_to_dependency` (§3) | ⇒ `"None"` | `frappe/public/js/frappe/model/perm.js:264` |
| 4 | docstatus | `"Write"` and `cint(doc.docstatus) > 0` ⇒ `"Read"` | `frappe/public/js/frappe/model/perm.js:272` |
| 5 | **`allow_on_submit`** | `"Read"` and `allow_on_submit` and `docstatus === 1` and `p.write` ⇒ **`"Write"`** — the only arm that widens | `frappe/public/js/frappe/model/perm.js:277-280` |
| 6 | workflow state | `"Read"` stays `"Read"` when the form is workflow-read-only or the field is a workflow-updated field | `frappe/public/js/frappe/model/perm.js:284-293` |
| 7 | **`read_only`** | `"Write"` and (`cint(df.read_only)` or `fieldtype === "Read Only"`) ⇒ `"Read"` | `frappe/public/js/frappe/model/perm.js:297-299` |
| 8 | `set_only_once` | `"Write"` and `df.set_only_once` and not `doc.__islocal` ⇒ `"Read"` | `frappe/public/js/frappe/model/perm.js:302-304` |

Three ordering consequences follow directly and are relied on below.

1. **`hidden` beats everything above it and is beaten by nothing below it.** Arm 2 sets `"None"` and no later
   arm tests for `"None"` before writing — arms 4, 5, 7 and 8 all guard on `"Write"` or `"Read"`
   (`frappe/public/js/frappe/model/perm.js:272`, `frappe/public/js/frappe/model/perm.js:278`,
   `frappe/public/js/frappe/model/perm.js:297`, `frappe/public/js/frappe/model/perm.js:302`) — so once
   `"None"` is set it survives to the `return` at `frappe/public/js/frappe/model/perm.js:307`.
2. **`read_only` still wins over `allow_on_submit`.** On a submitted document a field with both flags goes
   `"Write"` → `"Read"` (arm 4) → `"Write"` (arm 5) → `"Read"` (arm 7). The widening at arm 5 is undone at
   arm 7, because arm 7 guards on `"Write"`, which arm 5 has just produced.
3. **`allow_on_submit` is inert on a cancelled document.** Arm 4 fires for any `docstatus > 0` but arm 5
   requires `docstatus === 1` exactly (`frappe/public/js/frappe/model/perm.js:278`), so a cancelled document
   (`docstatus` 2) is read-only regardless of the flag. A commented-out line immediately above records an
   abandoned intent to exclude `Table` fields from the flag
   (`frappe/public/js/frappe/model/perm.js:276`); it is dead text, and `Table` fields do honour
   `allow_on_submit`.

The returned string reaches the DOM through two steps. `BaseControl.refresh` assigns it to `this.disp_status`
and toggles one class, `hide-control`, on `"None"`
(`frappe/public/js/frappe/form/controls/base_control.js:138-143`). `BaseInput.refresh_input` then does the
`"Read"`/`"Write"` split: it returns immediately when `disp_status` is `"None"`
(`frappe/public/js/frappe/form/controls/base_input.js:95`), builds a live input when
`can_write()` — defined as `disp_status == "Write"`
(`frappe/public/js/frappe/form/controls/base_input.js:144-146`) — is true
(`frappe/public/js/frappe/form/controls/base_input.js:105-110`), and otherwise hides the input area and
renders static text into `disp_area` instead
(`frappe/public/js/frappe/form/controls/base_input.js:112-122`,
`frappe/public/js/frappe/form/controls/base_input.js:148`).

A dialog or Web Form control never reaches `get_field_display_status`. `BaseControl.get_status` has a separate
branch for the case of no `doctype`/`docname`, or `parenttype === "Web Form"`, which reimplements the same
decision from `hidden`, `hidden_due_to_dependency` and `read_only` alone, with no permission arm and no
`allow_on_submit` arm at all (`frappe/public/js/frappe/form/controls/base_control.js:53-92`, especially
`frappe/public/js/frappe/form/controls/base_control.js:61-71`). `get_field_display_status` carries a third
reimplementation for the case of a missing `perm` argument, again covering only `hidden`,
`hidden_due_to_dependency` and `read_only` (`frappe/public/js/frappe/model/perm.js:239-243`). So the
three-flag subset has three independent implementations and the full eight-arm pipeline has one.

### 4.2 One statement per flag

#### `hidden`

**Render effect.** A truthy `hidden` forces `disp_status` to `"None"`
(`frappe/public/js/frappe/model/perm.js:260`), and a `"None"` control receives the `hide-control` class
(`frappe/public/js/frappe/form/controls/base_control.js:141`) and skips input construction entirely
(`frappe/public/js/frappe/form/controls/base_input.js:95`). On the three layout objects the flag is read
directly rather than through the permission model: `Section.refresh` computes
`hide = hide || this.df.hidden || this.df.hidden_due_to_dependency`
(`frappe/public/js/frappe/form/section.js:110-112`), `Column.refresh` the same
(`frappe/public/js/frappe/form/column.js:64-67`) and `Tab.refresh` the same
(`frappe/public/js/frappe/form/tab.js:50-51`) — extending §3.1's asymmetry from
`hidden_due_to_dependency` to the static flag. `Tab` is the one exception to that asymmetry: it *does*
consult permission, adding a `get_perm(permlevel, "read")` arm of its own
(`frappe/public/js/frappe/form/tab.js:54-56`), which `Section` and `Column` do not have.

**Client-only?** Yes. `hidden` plays no part in server-side field access. `get_permitted_fields` delegates to
`Meta.get_permitted_fieldnames` (`frappe/model/__init__.py:240-245`), which builds its list purely from
`permlevel` membership (`frappe/model/meta.py:712-726`); **absent:** neither function tests `hidden`, and
`grep -rn "\bhidden\b"` across `frappe/model/base_document.py` and `frappe/model/document.py` returns only
the docstring of `is_print_hide` (`frappe/model/base_document.py:1524-1533`). No line number is given for the
absent check. A hidden field's value is still transmitted and still written — the same conclusion §3.3
reached for a field hidden by `depends_on`. The only server-side rule touching the flag is a publish-time
consistency check, `check_hidden_and_mandatory`, which rejects `hidden` combined with `reqd` and no `default`
(`frappe/core/doctype/doctype/doctype.py:1442-1449`, called at
`frappe/core/doctype/doctype/doctype.py:1840`); that constrains the *metadata*, not any document write.
`hidden` is therefore **a presentation choice, not a security boundary**: it conceals a field from a rendered
form and from nothing else. Field-level confidentiality upstream is `permlevel`, per
[`docs/logic/19-permissions-and-access-control.md`](../logic/19-permissions-and-access-control.md).

#### `read_only`

**Render effect.** A truthy `read_only`, or the `Read Only` fieldtype, demotes `"Write"` to `"Read"`
(`frappe/public/js/frappe/model/perm.js:297-299`). `refresh_input` then takes the else branch: it hides the
input area, renders the formatted value as static text into `disp_area`, and additionally sets
`disabled` on any `$input` that already exists
(`frappe/public/js/frappe/form/controls/base_input.js:112-122`). A second, independent route reaches the same
outcome in a dialog, where `read_only` is tested alongside `is_virtual` and the `Read Only` fieldtype without
any permission involvement (`frappe/public/js/frappe/form/controls/base_control.js:67-71`). One further
interaction is worth naming because it turns `"Read"` into `"None"`: when the system default
`hide_empty_read_only_fields` is set, a `"Read"` control with a null value is demoted to `"None"` and
disappears rather than rendering as blank
(`frappe/public/js/frappe/form/controls/base_control.js:122-134`).

**Client-only?** Yes, and more completely than any other flag here. §3.6 records that
`grep -rn "read_only" frappe/model/base_document.py` returns nothing; that is verified — the count is
**zero** — and it extends to the sibling module: the three hits in `frappe/model/document.py` are all
different properties. Two are the request-scoped `frappe.flags.read_only`
(`frappe/model/document.py:2207`, `frappe/model/document.py:2240`) and one is the **doctype-level**
`read_only` property, tested to decide whether to publish a `list_update` realtime event
(`frappe/model/document.py:1947`). **Absent:** no server code rejects a write to a field carrying the
docfield `read_only` flag. The nearest related server behaviour is the one §3.6 names,
`_validate_update_after_submit` (`frappe/model/base_document.py:1346`), which is keyed on `allow_on_submit`
and never reads `read_only`. No line number is given for the absent check. `read_only` is therefore
**a presentation choice and emphatically not a security boundary** — a field that a form renders as
uneditable static text is freely writable by any caller that does not run the form, including the REST API
and any Server Script.

#### `bold`

**Render effect.** `bold` toggles a single CSS class, `bold`, on the live input and on the static display
area: `this.$input.toggleClass("bold", !!(this.df.bold || this.df.reqd))` and the same for `disp_area`
(`frappe/public/js/frappe/form/controls/base_input.js:292-298`). It is applied by `set_bold`, called from
`refresh_input` (`frappe/public/js/frappe/form/controls/base_input.js:139`) inside the
`disp_status != "None"` guard (`frappe/public/js/frappe/form/controls/base_input.js:95`), so a hidden field
is never made bold. The flag is **not independently observable**: the expression ORs it with `df.reqd`, so a
mandatory field is bold whether or not `bold` is set, and `bold` changes nothing on a field that is already
`reqd`. The grid applies the same disjunction to a column header cell —
`else if (df.reqd || df.bold) { column.addClass("bold"); }`
(`frappe/public/js/frappe/form/grid_row.js:760-761`).

**Client-only?** Yes, entirely. **Absent:** no server code reads the docfield `bold` property. Searched:
`grep -rn "bold" frappe/model/*.py frappe/core/doctype/docfield/docfield.py`; every hit in the model layer
is a call to the unrelated helper `frappe.bold()`, which wraps a string in `<b>` tags for an error message
(for example `frappe/model/base_document.py:1375-1377`,
`frappe/model/document.py:1119`), and the only occurrence of the property itself is its generated type
annotation, `bold: DF.Check` (`frappe/core/doctype/docfield/docfield.py:23`). No line number is given for the
absent consumer. `bold` is **pure typography** — the weakest of the seven, and the one flag whose removal
would be invisible wherever `reqd` is also set.

#### `allow_on_submit`

**Render effect.** `allow_on_submit` is the only one of the eight arms that *widens* a decision: it promotes
`"Read"` back to `"Write"` on a submitted document, subject to `docstatus === 1` exactly and to the user
holding `p.write` (`frappe/public/js/frappe/model/perm.js:277-280`). Its render effect is therefore
conditional on document state in a way no other flag here is: on a draft it does nothing at all, because arm
4 never fired. In a grid it also governs whether an in-grid control escapes the parent grid's read-only
state — a `"Write"` control is demoted to `"Read"` when its grid is read-only, but the `layout.grid` arm of
that test is skipped for a field carrying `allow_on_submit`
(`frappe/public/js/frappe/form/controls/base_control.js:102-111`, especially
`frappe/public/js/frappe/form/controls/base_control.js:104`).

**Client-only?** **No — this is the one genuine server-enforced flag of the seven.**
`_validate_update_after_submit` re-reads the persisted document, iterates every key, and throws
`frappe.UpdateAfterSubmitError` for any field whose value differs and whose `df.allow_on_submit` is falsy
(`frappe/model/base_document.py:1346-1354`, throw at `frappe/model/base_document.py:1371-1381`). It is
reached from `validate_update_after_submit` (`frappe/model/document.py:1477-1487`), which also recurses into
children, exempting a newly added child row when the parent table field itself allows updates on submit
(`frappe/model/document.py:1482-1485`). Two adjacent server behaviours are keyed on the same flag: a
`fetch_from` value is refreshed on a submitted document only for a field that allows it
(`frappe/model/base_document.py:1136-1138`), and HTML sanitisation is skipped on a submitted document except
for fields that allow updates after submit (`frappe/model/base_document.py:1410-1418`, especially
`frappe/model/base_document.py:1416`).

It is nevertheless **not a complete boundary**, for two reasons observable in the code. First, the check runs
only on the `update_after_submit` action — `if self._action == "update_after_submit":`
(`frappe/model/document.py:844-848`) — and is skipped outright when
`flags.ignore_validate_update_after_submit` is set (`frappe/model/document.py:1478-1479`). Second,
`Document.db_set` does not go through it: it writes the field and calls `frappe.db.set_value` directly
(`frappe/model/document.py:1951`, `frappe/model/document.py:1994-1996`), under a docstring that says so —
"this method does not trigger controller validations"
(`frappe/model/document.py:1954-1955`). ERPNext relies on exactly that bypass: the status updater writes
`per_billed` and a status field onto an already-submitted parent through
`target.db_set(update_data, …)` (`erpnext` `controllers/status_updater.py:677-683`, values computed at
`controllers/status_updater.py:663-670`). So `allow_on_submit` is best classified as **a real constraint on
the ordinary save path and no constraint at all on the direct-write path** — a boundary that holds against
`Document.save()` and not against `db_set`.

#### `in_list_view`

**Form-side render effect: none.** **Absent** — for a field of the doctype being rendered, `in_list_view`
has no effect on the form. Searched: `grep -rn "in_list_view" frappe/public/js/frappe/form/`, whose every hit
is one of two things. Either it is the child-table grid — the visible-column test
`df && !df.hidden && (this.editable_fields || df.in_list_view) && perm read`
(`frappe/public/js/frappe/form/grid.js:1528-1533`), the per-row propagation
`row_df.in_list_view = column_df.in_list_view` (`frappe/public/js/frappe/form/grid_row.js:807`) and the
column-visibility setter `set_column_disp_in_list_view`
(`frappe/public/js/frappe/form/grid.js:1086`) — or it is one of the two `DocType Layout` override lists
(`frappe/public/js/frappe/form/layout.js:98`, `frappe/public/js/frappe/form/layout.js:561`), which merely
make the flag overridable without giving it a form-side meaning. No `Section`, `Column`, `Tab`, `Layout` or
control code path reads it. No line number is given for the absent form-side consumer.

The flag's real subject is therefore the grid, and the grid is
`docs/ui/02-child-table-grid-engine.md`'s to document (sub-task 3.3), including the width budget and the
storage of user column configuration. The server confirms the dual meaning in its own error text: the
publish-time validator labels the property "In Grid View" for a child table and "In List View" otherwise —
`property_label = "In Grid View" if is_table else "In List View"`
(`frappe/core/doctype/doctype/doctype.py:1455-1460`).

**Client-only?** The flag has server-side *writers* and a server-side *validator*, but no server-side
enforcement of anything. `set_default_in_list_view` mutates the metadata at DocType save time, setting the
flag on the first four `reqd`, non-`hidden` fields of a permitted fieldtype when no field carries it
(`frappe/core/doctype/doctype/doctype.py:291-302`, called at
`frappe/core/doctype/doctype/doctype.py:205`), and `check_in_list_view` rejects the flag on a no-value
fieldtype (`frappe/core/doctype/doctype/doctype.py:1455-1460`, called at
`frappe/core/doctype/doctype/doctype.py:1854`, with the excluded set built at
`frappe/core/doctype/doctype/doctype.py:1873-1878`). Both act on the metadata. `in_list_view` is
**a presentation choice** and cannot be a security boundary in either direction: it neither hides data from a
caller nor grants access to any.

#### `print_hide`

**Render effect on the form: none.** **Absent** — `print_hide` is not read anywhere in the form runtime.
Searched: `grep -rn "print_hide" frappe/public/js/frappe/form/` returns **no hits at all**. It is in no arm of
`get_field_display_status` (`frappe/public/js/frappe/model/perm.js:246-307`) and in none of the three
`DocType Layout` override lists — the form's two (`frappe/public/js/frappe/form/layout.js:92-105`,
`frappe/public/js/frappe/form/layout.js:555-568`) or the grid's child-layout one
(`frappe/public/js/frappe/form/grid.js:916-929`), so it is not even overridable by a layout. No line number is
given for an absent form-side consumer. Its effect is confined to the print path.

**Client-only?** No — `print_hide` is resolved **on the server**, which makes it the second of the seven to
have a real server counterpart. `Document.is_print_hide` returns truthy for a field to be omitted from print,
consulting three sources in order: a controller-supplied `__print_hide` marker on the docfield, then
`print_hide_if_no_value` when the value is `0` and the doctype is not a child table, then `print_hide` itself,
preferring an explicitly passed `df` over the metadata copy
(`frappe/model/base_document.py:1523-1550`). The print view calls it as the last test of its own `is_visible`
helper, after excluding layout fieldtypes and checking permlevel access
(`frappe/www/printview.py:517-525`). The same method is exposed to Server Scripts through the safe-exec shim
(`frappe/utils/safe_exec.py:256-260`).

Even so it is **not a security boundary**, for a reason the code makes plain: it removes a field from a
rendered print layout, not from the document. The permlevel test that *is* a boundary sits on the line above
it and is separate (`frappe/www/printview.py:522-523`). A `print_hide` field is still returned by every read
API. Classify it as **a presentation choice that happens to be enforced server-side** — the enforcement makes
it reliable for its purpose, not sufficient for confidentiality.

#### `translatable`

**Render effect on a form: it conditions a button, not the displayed value.** `BaseControl.refresh` calls
`show_translatable_button(value)` (`frappe/public/js/frappe/form/controls/base_control.js:145-147`), which
returns without doing anything unless `this.df.translatable` is set, a `frm`, a `doc` and a non-empty value
all exist, and the user can write the `Translation` doctype
(`frappe/public/js/frappe/form/controls/base_control.js:149-159`, the flag test at
`frappe/public/js/frappe/form/controls/base_control.js:155`); when all hold it appends a globe icon that
opens the translation manager (`frappe/public/js/frappe/form/controls/base_control.js:162-175`).
**Absent:** no form control passes a value through `__()` because `df.translatable` is set. Searched:
`grep -rn "translatable" frappe/public/js/frappe/`, whose only display-affecting hit is
`ControlLink.get_translated`, and that is gated on the boot list `frappe.boot.translated_doctypes` — a
**doctype**-level property — rather than on the docfield flag
(`frappe/public/js/frappe/form/controls/link.js:119-124`). No line number is given for the absent
value-translation path. So a `translatable` `Data` field renders its stored text verbatim on a form; the flag
buys a maintenance affordance, not a translated display.

**Client-only?** No, but its server-side effect is on a different surface again. The report/export query
translates values column by column, selecting which columns to translate from exactly this flag —
`_(value) if translatable_fields[idx] else value`
(`frappe/desk/reportview.py:496-506`, the flag list built at `frappe/desk/reportview.py:499`), with the
per-column decision assembled at `frappe/desk/reportview.py:620-635` and widened to `True` for a `Link`
pointing at a translated doctype (`frappe/desk/reportview.py:630-631`). Publish-time writers coerce the flag
to `0` for a fieldtype that cannot support it, `supports_translation` admitting only `Data`, `Select`, `Text`,
`Small Text` and `Text Editor` (`frappe/model/docfield.py:9-10`), applied from DocType save
(`frappe/core/doctype/doctype/doctype.py:304`, `frappe/core/doctype/doctype/doctype.py:307-308`, called at
`frappe/core/doctype/doctype/doctype.py:206`), from `Custom Field`
(`frappe/custom/doctype/custom_field/custom_field.py:209-210`) and from `Customize Form`
(`frappe/custom/doctype/customize_form/customize_form.py:402`).

`translatable` is therefore **a presentation choice**, and one with a hazard worth recording: it causes a
*stored* value to be replaced by a *translated* one in the export path
(`frappe/desk/reportview.py:503`), which is precisely the stored-value/displayed-text confusion Requirement
13.4 rejects. It is not a security boundary in any direction.

### 4.3 Summary — boundary or presentation

| Flag | Client render effect | Server counterpart | Boundary? |
|---|---|---|---|
| `hidden` | `disp_status` → `"None"`, `hide-control` class (`frappe/public/js/frappe/model/perm.js:260`, `frappe/public/js/frappe/form/controls/base_control.js:141`) | none for access; a publish-time metadata check only (`frappe/core/doctype/doctype/doctype.py:1442-1449`) | **presentation** — value still sent, stored and returned |
| `read_only` | `"Write"` → `"Read"`; static text instead of an input (`frappe/public/js/frappe/model/perm.js:297-299`, `frappe/public/js/frappe/form/controls/base_input.js:112-122`) | **none at all** — zero occurrences in `frappe/model/base_document.py`; nearest is `_validate_update_after_submit` (`frappe/model/base_document.py:1346`) | **presentation** — freely writable off-form |
| `bold` | `bold` class on input and display area, OR-ed with `reqd` (`frappe/public/js/frappe/form/controls/base_input.js:292-298`) | none; only the generated annotation (`frappe/core/doctype/docfield/docfield.py:23`) | **presentation** — typography only |
| `allow_on_submit` | `"Read"` → `"Write"` when `docstatus === 1` (`frappe/public/js/frappe/model/perm.js:277-280`) | `_validate_update_after_submit` throws `UpdateAfterSubmitError` (`frappe/model/base_document.py:1346-1354`, `frappe/model/base_document.py:1371-1381`) | **boundary on the save path only** — bypassed by `db_set` (`frappe/model/document.py:1951`, `frappe/model/document.py:1954-1955`) |
| `in_list_view` | **none on the parent form**; grid visible-column signal only (`frappe/public/js/frappe/form/grid.js:1528-1533`) | metadata writer and validator only (`frappe/core/doctype/doctype/doctype.py:291-302`, `frappe/core/doctype/doctype/doctype.py:1455-1460`) | **presentation** |
| `print_hide` | **none on the form**; not read by any arm of the pipeline (`frappe/public/js/frappe/model/perm.js:246-307`) | `is_print_hide`, applied by the print view (`frappe/model/base_document.py:1523-1550`, `frappe/www/printview.py:517-525`) | **presentation, server-enforced** — omits from print, not from any read API |
| `translatable` | a translation-manager button, gated on `can_write("Translation")`; **no** effect on the rendered value (`frappe/public/js/frappe/form/controls/base_control.js:149-159`) | translates exported values (`frappe/desk/reportview.py:496-506`); fieldtype coercion (`frappe/model/docfield.py:9-10`) | **presentation** — and substitutes translated text for stored text on export |

Two conclusions carry into §10. Only `allow_on_submit` may be relied on for integrity, and only against
`Document.save()`. Every other flag in this set is a rendering instruction, so any target rule phrased as
"field X cannot be changed" or "field X is not visible" must be restated against `permlevel` or against a
server-side check, exactly as §3.6 concluded for `read_only_depends_on`.

### 4.4 Worked example — `Timesheet.per_billed`

`Timesheet` is submittable (`projects/doctype/timesheet/timesheet.json:315`) and its `per_billed` field
carries four of the seven flags at once, which makes it a single trace through the whole pipeline. The stored
definition is

```json
{
 "allow_on_submit": 1,
 "fieldname": "per_billed",
 "fieldtype": "Percent",
 "in_list_view": 1,
 "label": "% Amount Billed",
 "no_copy": 1,
 "print_hide": 1,
 "read_only": 1
}
```

at `projects/doctype/timesheet/timesheet.json:231-240`. It carries no `hidden`, no `bold`, no `reqd` and no
`translatable`. Assume a user holding `write` at permlevel 0.

**State A — draft (`docstatus` 0).**

| # | Arm | Outcome | Citation |
|---|---|---|---|
| 1 | permission | `p.write` is true, `disabled` and `is_virtual` unset ⇒ `"Write"` | `frappe/public/js/frappe/model/perm.js:251-252` |
| 2 | `hidden` | `cint(undefined)` is `0` ⇒ unchanged | `frappe/public/js/frappe/model/perm.js:260` |
| 3 | `hidden_due_to_dependency` | no `depends_on` on this field ⇒ unchanged | `frappe/public/js/frappe/model/perm.js:264` |
| 4 | docstatus | `0 > 0` is false ⇒ unchanged | `frappe/public/js/frappe/model/perm.js:272` |
| 5 | `allow_on_submit` | guard requires `"Read"`; status is `"Write"` ⇒ **no effect** | `frappe/public/js/frappe/model/perm.js:278` |
| 7 | `read_only` | `"Write"` and `cint(1)` ⇒ **`"Read"`** | `frappe/public/js/frappe/model/perm.js:297-298` |
| 8 | `set_only_once` | guard requires `"Write"` ⇒ unchanged | `frappe/public/js/frappe/model/perm.js:302` |

Render decision: `disp_status = "Read"`, so no `hide-control` class is applied
(`frappe/public/js/frappe/form/controls/base_control.js:141`), `can_write()` is false
(`frappe/public/js/frappe/form/controls/base_input.js:144-146`), the input area is hidden and the value is
written into `disp_area` as static text (`frappe/public/js/frappe/form/controls/base_input.js:116-120`).
`set_bold` runs but toggles the class off, because neither `bold` nor `reqd` is set
(`frappe/public/js/frappe/form/controls/base_input.js:139`,
`frappe/public/js/frappe/form/controls/base_input.js:294`). `show_translatable_button` returns at its first
guard, `!this.df.translatable` (`frappe/public/js/frappe/form/controls/base_control.js:155`) — and would have
returned anyway, since `Percent` is not in `supports_translation`'s list and the flag would have been coerced
to `0` at DocType save (`frappe/model/docfield.py:9-10`,
`frappe/core/doctype/doctype/doctype.py:307-308`). Note that arm 5 is the *whole* point of the flag on this
field and it is inert here: on a draft, `allow_on_submit` contributes nothing.

**State B — submitted (`docstatus` 1).** The arms diverge at 4:

| # | Arm | Outcome | Citation |
|---|---|---|---|
| 4 | docstatus | `"Write"` and `1 > 0` ⇒ `"Read"` | `frappe/public/js/frappe/model/perm.js:272` |
| 5 | `allow_on_submit` | `"Read"`, `cint(1)`, `docstatus === 1`, `p.write` ⇒ **`"Write"`** | `frappe/public/js/frappe/model/perm.js:278-279` |
| 7 | `read_only` | `"Write"` and `cint(1)` ⇒ **`"Read"`** | `frappe/public/js/frappe/model/perm.js:297-298` |

The final status is `"Read"` again, and the rendered form is **indistinguishable from State A**. The widening
performed by `allow_on_submit` at arm 5 is silently undone by `read_only` at arm 7, because arm 7's guard is
exactly the value arm 5 has just produced. The two flags are, on this field, in direct contradiction, and the
resolution is decided by nothing more than their relative position in one function. Had `read_only` been
absent, the field would have become editable after submission.

**State C — cancelled (`docstatus` 2).** Arm 4 fires (`2 > 0`) but arm 5's `docstatus === 1` test fails
(`frappe/public/js/frappe/model/perm.js:278`), so the field is `"Read"` with no widening step at all.

**What the other three flags did.** `in_list_view: 1` had **no effect on any of the three states**:
`per_billed` belongs to the parent doctype, and no form-side code reads the flag (§4.2). `print_hide: 1` had
no effect either, and takes effect only when the document is printed, through `is_print_hide`
(`frappe/model/base_document.py:1544-1548`) as called from the print view's visibility test
(`frappe/www/printview.py:525`). Note the `print_hide_if_no_value` interaction available on the same method:
had that property been set instead, a `per_billed` of `0` would also have been omitted
(`frappe/model/base_document.py:1541-1542`).

**What the server does with the same field.** The value is computed in `calculate_percentage_billed` and
assigned directly to `self.per_billed` (`projects/doctype/timesheet/timesheet.py:116-121`), and
`set_status` then reads it back through `precision()` to derive `Billed` or `Partially Billed`
(`projects/doctype/timesheet/timesheet.py:130-134`). Because the field carries `allow_on_submit: 1`, an
`update_after_submit` save that changes it passes `_validate_update_after_submit`
(`frappe/model/base_document.py:1354`) instead of throwing. The `read_only: 1` flag, by contrast, is consulted
by **nothing** on this path — a REST `PUT` or a Server Script may set `per_billed` to any value on a draft
Timesheet, and the only reason it cannot do so arbitrarily after submission is `allow_on_submit`'s
absence-triggered check on *other* fields, not `read_only` on this one.

For the contrasting case, `Sales Order.per_billed` carries `in_list_view`, `print_hide` and `read_only` but
**not** `allow_on_submit` (`selling/doctype/sales_order/sales_order.json:1275-1290`), and ERPNext
nevertheless updates it on submitted Sales Orders — through `db_set`
(`controllers/status_updater.py:677-683`), configured by the `target_parent_field` entry in
`Sales Invoice.status_updater` (`accounts/doctype/sales_invoice/sales_invoice.py:260-275`). That is the
bypass of §4.2 in live use: the framework's own write path does not honour the flag it enforces against
callers. The field immediately below it, `billing_status`, carries both `hidden: 1` and `print_hide: 1`
(`selling/doctype/sales_order/sales_order.json:1291-1302`) and is written by the same mechanism, through the
`status_field` entry of the same configuration (`controllers/status_updater.py:672-675`) — a hidden field
being maintained server-side is the ordinary case, not an exception.

### 4.5 Findings recorded for §8

Eight behaviours observed while reading this path are defects rather than descriptions. They are stated here
in prose; the numbered inventory and the verdicts are §8's and §10's to write.

1. **`read_only` is a docfield flag with no enforcement anywhere outside the browser.**
   `grep -rn "read_only" frappe/model/base_document.py` returns **zero** hits, and the three hits in
   `frappe/model/document.py` are the doctype-level property (`frappe/model/document.py:1947`) and the
   request-scoped `frappe.flags.read_only` (`frappe/model/document.py:2207`,
   `frappe/model/document.py:2240`) — different things with the same name. The gap is wider than §3.6's
   finding for `read_only_depends_on`, because `read_only` is the *static* form of the same claim and is used
   pervasively: it is the flag on which most ERPNext computed fields rely to signal "do not write this",
   including both `per_billed` fields traced in §4.4. No line number is cited for the absent check.
2. **`bold` is not independently observable.** Both render sites OR it with `df.reqd` —
   `!!(this.df.bold || this.df.reqd)` at `frappe/public/js/frappe/form/controls/base_input.js:294` and
   `frappe/public/js/frappe/form/controls/base_input.js:297`, and `df.reqd || df.bold` at
   `frappe/public/js/frappe/form/grid_row.js:760` — so on any mandatory field the flag is a no-op, and no
   rendered state distinguishes `bold: 1, reqd: 1` from `bold: 0, reqd: 1`. A property that cannot be
   observed cannot be tested.
3. **One column, `in_list_view`, carries two unrelated meanings, and upstream says so in an error string.**
   `check_in_list_view` selects its own label at runtime —
   `property_label = "In Grid View" if is_table else "In List View"`
   (`frappe/core/doctype/doctype/doctype.py:1455-1457`) — and the two meanings have disjoint consumers: the
   child-table grid reads it (`frappe/public/js/frappe/form/grid.js:1531`) and the parent form does not
   (§4.2). A single stored flag therefore cannot be set for the grid without also setting it for the list, or
   vice versa.
4. **`allow_on_submit` is enforced on one write path and bypassed on another, and upstream depends on the
   bypass.** `_validate_update_after_submit` runs only under `_action == "update_after_submit"`
   (`frappe/model/document.py:844-848`) and is skippable by flag
   (`frappe/model/document.py:1478-1479`), while `db_set` reaches `frappe.db.set_value` without it
   (`frappe/model/document.py:1951`, `frappe/model/document.py:1994-1996`). ERPNext's status updater writes
   a field lacking the flag onto a submitted document by that route
   (`controllers/status_updater.py:677-683`;
   `selling/doctype/sales_order/sales_order.json:1275-1290` shows the field has no `allow_on_submit`). The
   constraint is therefore advisory with respect to server code and binding only on `Document.save()`.
5. **`translatable` substitutes translated text for stored text in the export path.** `export_query`
   replaces a column's value with `_(value)` when the flag is set
   (`frappe/desk/reportview.py:499-503`), so an exported file holds display text where the database holds a
   code. This is the stored-value/displayed-text conflation Requirement 13.4 rejects, present upstream, and
   it is invisible on the form because the flag does not translate anything there (§4.2).
6. **The `hidden`/`read_only` subset of the pipeline has three independent implementations, two of which omit
   the permission and `allow_on_submit` arms.** The full eight-arm version is
   `frappe/public/js/frappe/model/perm.js:246-307`; a three-flag version runs whenever `perm` is not supplied
   and no `doc` is available to derive it (`frappe/public/js/frappe/model/perm.js:239-243`); and a third
   lives in `BaseControl.get_status` for dialogs and Web Forms
   (`frappe/public/js/frappe/form/controls/base_control.js:53-92`, flag tests at
   `frappe/public/js/frappe/form/controls/base_control.js:61-71`). A field rendered in a dialog therefore
   ignores `permlevel` and `allow_on_submit` entirely — the same duplication-with-divergence pattern §3.8
   item 5 records for the expression evaluator, in a second subsystem.
7. **`Layout.is_visible` tests for the *presence* of the `hidden` key, not its value.** The predicate is
   `field.disp_status === "Write" && field.df && "hidden" in field.df && !field.df.hidden`
   (`frappe/public/js/frappe/form/layout.js:759-762`). A docfield that never had `hidden` written — the
   normal case for a JSON definition that omits the property, as `Timesheet.per_billed` omits it
   (`projects/doctype/timesheet/timesheet.json:231-240`) — fails the `in` test and is treated as not visible.
   The predicate governs Enter-key focus traversal (`frappe/public/js/frappe/form/layout.js:706`,
   `frappe/public/js/frappe/form/layout.js:738`), so such a field is skipped when moving between fields even
   though it is on screen and writable. This is a fourth, and the narrowest, definition of "visible" in the
   layout engine, alongside `disp_status == "None"`
   (`frappe/public/js/frappe/form/controls/base_control.js:141`), `frappe.perm.is_visible`
   (`frappe/public/js/frappe/model/perm.js:310-319`) and the print view's `is_visible`
   (`frappe/www/printview.py:517-525`).
8. **A commented-out exclusion is left in the `allow_on_submit` arm.** The line
   `// let allow_on_submit = df.fieldtype==="Table" ? 0 : cint(df.allow_on_submit);`
   (`frappe/public/js/frappe/model/perm.js:276`) records an abandoned decision to deny the flag to `Table`
   fields, immediately above the live line that grants it
   (`frappe/public/js/frappe/model/perm.js:277`). It is dead text with no accompanying rationale, and the
   child-row exemption on the server (`frappe/model/document.py:1482-1485`) is written on the opposite
   assumption.

## 5. Field type → control mapping

Requirement 6.6 names seventeen field types. Sixteen of them resolve to a control class; one, `Markdown`, is
not a fieldtype at all, and §5.3 records that as an absence finding. The mapping is not a table anywhere in
the source — it is a **string concatenation over the global namespace**, and the whole of §5.1 is spent on
that one line, because every property of the mapping follows from it: there is no registration step, no
validation of the fieldtype against a known set, and no error when the lookup misses.

Depth here is bounded deliberately (design risk R4). For each mandated type this section states the control
class, its file, its base class and its **divergences** from that base — not a full reading of the control.
The divergences are where the analytical content is, because the inheritance chain does almost all the work:
of the forty-six control modules `control.js` loads, thirty-nine descend from `ControlData`, and several of
the mandated seventeen override a single method.

### 5.1 The registry — how a `fieldtype` string becomes a control class

There is one function, `frappe.ui.form.make_control`, and it is five lines long:

```
frappe.ui.form.make_control = function (opts) {                                      (control.js:48)
  var control_class_name = "Control" + opts.df.fieldtype.replace(/ /g, "");          (control.js:49)
  if (frappe.ui.form[control_class_name]) {                                          (control.js:50)
    return new frappe.ui.form[control_class_name](opts);                             (control.js:51)
  } else {
    console.log("Invalid Control Name: " + opts.df.fieldtype);                        (control.js:53)
  }
};
```

Read in full at `frappe/public/js/frappe/form/controls/control.js:48-55`. Four properties follow.

1. **The class name is derived, not looked up.** `"Control" + fieldtype.replace(/ /g, "")`
   (`frappe/public/js/frappe/form/controls/control.js:49`) is the entire mapping. `Dynamic Link` becomes
   `ControlDynamicLink`, `Table MultiSelect` becomes `ControlTableMultiSelect`, `Markdown Editor` becomes
   `ControlMarkdownEditor`. There is no dictionary to consult and therefore no list of supported fieldtypes
   anywhere in the client.
2. **The namespace is populated by side effect of import.** Each control module assigns itself onto
   `frappe.ui.form` at its top level — `frappe.ui.form.ControlLink = class ControlLink ...`
   (`frappe/public/js/frappe/form/controls/link.js:10`) — and `control.js` imports forty-six such modules
   (`frappe/public/js/frappe/form/controls/control.js:1-46`). A control is "registered" only in the sense
   that its module was imported. Any code that assigns `frappe.ui.form.ControlXyz` after boot adds a
   fieldtype, and nothing distinguishes an upstream control from an injected one.
3. **An unknown fieldtype logs to the console and returns `undefined`.** The `else` arm calls `console.log`
   (`frappe/public/js/frappe/form/controls/control.js:53`) and **falls off the end of the function without a
   `return`**, so `make_control` evaluates to `undefined`. This is the origin of the null that §2.2 step 8e
   records: `init_field` passes the value straight through — it guards the `fieldobj.layout` assignment on
   truthiness (`frappe/public/js/frappe/form/layout.js:298-300`) and returns it regardless
   (`frappe/public/js/frappe/form/layout.js:302`) — and `make_field` then returns early
   (`frappe/public/js/frappe/form/layout.js:265`), before any of the four registration steps
   `fields_list`/`fields_dict`/`section.add_field`/`current_tab.add_field`
   (`frappe/public/js/frappe/form/layout.js:267-275`). The field is absent from every collection the rest of
   the form consults, and the only trace is a `console.log` line no user sees. There is no `frappe.throw`, no
   `msgprint` and no indicator on the form.
4. **The fieldtype can be rewritten before the lookup.** `init_field` inspects `df.mask` and, when the
   fieldname appears in the doctype's `masked_fields`, overwrites `df.fieldtype = "Data"` and
   `df.read_only = 1` on the docfield object itself
   (`frappe/public/js/frappe/form/layout.js:279-284`) before calling `make_control`
   (`frappe/public/js/frappe/form/layout.js:287-295`). The control instantiated for a masked field is
   therefore `ControlData` whatever the stored fieldtype said, and the mutation persists on the shared
   docfield — the same mutate-the-metadata pattern §5.10 records three more instances of.

**Absent.** There is no validation that a docfield's `fieldtype` is one of the canonical fieldtypes at render
time. The canonical set exists on the server, as `data_fieldtypes`
(`frappe/model/__init__.py:8-30`), `no_value_fields` (`frappe/model/__init__.py:53-65`) and the `options`
enumeration of the `fieldtype` docfield (`frappe/core/doctype/docfield/docfield.json:118`); none of the three
is consulted by `make_control`. No line number is given for the absent check.

### 5.2 The inheritance chain

The chain is `BaseControl` → `ControlInput` → `ControlData` → everything else, and the class declaration of
every control was read in one pass to establish it:

| Level | Class | Extends | Citation |
|---|---|---|---|
| 0 | `BaseControl`, exported as `frappe.ui.form.Control` | — | `frappe/public/js/frappe/form/controls/base_control.js:1` |
| 1 | `ControlInput` | `frappe.ui.form.Control` | `frappe/public/js/frappe/form/controls/base_input.js:2` |
| 2 | `ControlData` | `frappe.ui.form.ControlInput` | `frappe/public/js/frappe/form/controls/data.js:3` |
| 3+ | thirty-nine controls | `ControlData` or a descendant of it | per-row citations in §5.3 |

Only four of the forty-six loaded modules extend `frappe.ui.form.Control` directly, bypassing `ControlInput`
entirely: `ControlHTML` (`frappe/public/js/frappe/form/controls/html.js:1`), `ControlImage`
(`frappe/public/js/frappe/form/controls/image.js:1`), `ControlMultiCheck`
(`frappe/public/js/frappe/form/controls/multicheck.js:1`) and — the one that matters here — `ControlTable`
(`frappe/public/js/frappe/form/controls/table.js:3`).

What each level contributes:

- **`BaseControl`** owns the wrapper, the status decision and the model write path. Its constructor
  `$.extend`s the options onto itself, calls `make()`, and calls `refresh()` only if `render_input` was
  passed (`frappe/public/js/frappe/form/controls/base_control.js:2-8`). `make()` creates the wrapper and
  stamps `data-fieldtype` and `data-fieldname` onto it
  (`frappe/public/js/frappe/form/controls/base_control.js:9-13`) — the fieldtype survives into the DOM as an
  attribute, which is the only place the rendered page records it. `make_wrapper` at this level is a bare
  `div.frappe-control` (`frappe/public/js/frappe/form/controls/base_control.js:26-31`).
- **`ControlInput`** owns the label/input/display three-part markup and the `"Read"`/`"Write"` split. §4.1
  already established that `refresh_input` returns immediately on `disp_status === "None"`
  (`frappe/public/js/frappe/form/controls/base_input.js:95`) and branches on
  `can_write()`, defined as `disp_status == "Write"`
  (`frappe/public/js/frappe/form/controls/base_input.js:144-146`). It overrides `make_wrapper` with the full
  `form-group` / `clearfix` / `control-input-wrapper` markup
  (`frappe/public/js/frappe/form/controls/base_input.js:16-40`) and names the four regions in
  `set_input_areas`: `label_area`, `input_area` = `.control-input`, `$input_wrapper` =
  `.control-input-wrapper`, and `disp_area` = `.control-value`
  (`frappe/public/js/frappe/form/controls/base_input.js:47-58`). **It does not define `make_input`** — it
  calls `me.make_input()` (`frappe/public/js/frappe/form/controls/base_input.js:80`) and relies on a
  subclass to supply it. `ControlInput` is therefore abstract in practice, and a control extending it without
  a `make_input` throws at first render.
- **`ControlData`** owns input construction, and does it **generically**: it reads three static class fields
  off `this.constructor` — `html_element`, `input_type`, `input_mode`
  (`frappe/public/js/frappe/form/controls/data.js:10`) — and builds the element from them
  (`frappe/public/js/frappe/form/controls/data.js:12-17`), its own defaults being `"input"`, `"text"` and
  `trigger_change_on_input_event = true`
  (`frappe/public/js/frappe/form/controls/data.js:4-6`). This is the mechanism by which most controls diverge
  **without overriding a method at all** — `ControlSelect` becomes a `<select>` purely by declaring
  `static html_element = "select"` (`frappe/public/js/frappe/form/controls/select.js:2`).

One consequence of the chain shape is worth stating before the matrix, because three mandated rows depend on
it. Formatting for a read-only field does not enter through the per-type control: `set_disp_area` formats
centrally via `frappe.format` (`frappe/public/js/frappe/form/controls/base_input.js:166`) with two
fieldtype-keyed special cases hard-coded at that level — a zero is preserved rather than falsified for
`Currency`, `Int` and `Float` (`frappe/public/js/frappe/form/controls/base_input.js:148-157`), and HTML is
escaped for `Data`, `Long Text`, `Small Text`, `Text`, `Password` and `MultiSelect` and for nothing else
(`frappe/public/js/frappe/form/controls/base_input.js:158-164`). The **writable** path formats through the
per-type `format_for_input`; the **read-only** path does not.

### 5.3 Coverage matrix — the seventeen mandated types

One row per type named in Requirement 6.6. "Extends" is the immediate base; "Divergences" lists only what the
class changes relative to it.

| # | Fieldtype | Control class | File | Extends | Divergences from its base | Citation |
|---|---|---|---|---|---|---|
| 1 | `Link` | `ControlLink` | `controls/link.js` | `ControlData` | replaces `make_input` with a `div.link-field` wrapping the input plus clear/open buttons; adds an Awesomplete dropdown, `search_link` querying, target-doctype resolution via `get_options`, link-title substitution and server-side link validation; `parse` strips HTML; `trigger_change_on_input_event = false` | `frappe/public/js/frappe/form/controls/link.js:10-11`, `frappe/public/js/frappe/form/controls/link.js:12-24`, `frappe/public/js/frappe/form/controls/link.js:93-95`, `frappe/public/js/frappe/form/controls/link.js:157-158` |
| 2 | `Dynamic Link` | `ControlDynamicLink` | `controls/dynamic_link.js` | `ControlLink` | **overrides exactly one method**, `get_options`, and adds nothing else — the whole file is thirty lines | `frappe/public/js/frappe/form/controls/dynamic_link.js:1-30`, `frappe/public/js/frappe/form/controls/dynamic_link.js:2-29` |
| 3 | `Table` | `ControlTable` | `controls/table.js` | `frappe.ui.form.Control` (**skips `ControlInput`**) | constructs a `Grid` in `make()` and delegates rendering, value reading and validation to it; registers itself in `frm.grids`; binds a paste handler on the wrapper; `set_input` is an empty method body | `frappe/public/js/frappe/form/controls/table.js:3`, `frappe/public/js/frappe/form/controls/table.js:8-14`, `frappe/public/js/frappe/form/controls/table.js:134-147` |
| 4 | `Table MultiSelect` | `ControlTableMultiSelect` | `controls/table_multiselect.js` | `ControlLink` | resolves its target doctype **indirectly**, through the first `Link` field of the child doctype named in `options`; renders selected values as removable pills instead of a single input value; filters the Awesomplete list against already-selected rows; fires `before_<fieldname>_remove` script triggers | `frappe/public/js/frappe/form/controls/table_multiselect.js:1-3`, `frappe/public/js/frappe/form/controls/table_multiselect.js:210-222`, `frappe/public/js/frappe/form/controls/table_multiselect.js:223-233`, `frappe/public/js/frappe/form/controls/table_multiselect.js:55-59` |
| 5 | `Select` | `ControlSelect` | `controls/select.js` | `ControlData` | declares `static html_element = "select"`, which is the entire mechanism by which it becomes a dropdown; splits `options` on newline; adds a chevron icon and a placeholder overlay; `set_formatted_input` **writes the model back** from the input when the two disagree | `frappe/public/js/frappe/form/controls/select.js:1-3`, `frappe/public/js/frappe/form/controls/select.js:61-67`, `frappe/public/js/frappe/form/controls/select.js:41-60` |
| 6 | `Currency` | `ControlCurrency` | `controls/currency.js` | `ControlFloat` | **overrides exactly one method**, `get_precision`, which prefers `df.precision`, then `sysdefaults.currency_precision`, then the number format's own precision — and caches the result by assigning to `this.df.precision` | `frappe/public/js/frappe/form/controls/currency.js:1`, `frappe/public/js/frappe/form/controls/currency.js:2-14` |
| 7 | `Float` | `ControlFloat` | `controls/float.js` | `ControlInt` | `input_mode = "decimal"`; `parse` returns `flt(value, this.get_precision())` or `null` for a non-number; adds `format_for_input` via `format_number`, `get_number_format` (which returns `undefined` for `Rating` and for a `Float` with no `options`) and `get_precision` | `frappe/public/js/frappe/form/controls/float.js:1-2`, `frappe/public/js/frappe/form/controls/float.js:3-6`, `frappe/public/js/frappe/form/controls/float.js:12-18`, `frappe/public/js/frappe/form/controls/float.js:20-34` |
| 8 | `Percent` | `ControlPercent` | `controls/percent.js` | `ControlFloat` | **overrides exactly one method**, `format_for_input`, narrowing the displayed precision to `Math.min(get_precision(), decimals present in the value)`; the whole file is twelve lines | `frappe/public/js/frappe/form/controls/percent.js:1`, `frappe/public/js/frappe/form/controls/percent.js:2-12` |
| 9 | `Duration` | `ControlDuration` | `controls/duration.js` | `ControlData` | builds a four-part days/hours/minutes/seconds picker below the text input; reads `hide_days` and `hide_seconds` from the docfield through `frappe.utils.get_duration_options`; `parse` accepts either a bare integer of seconds or a duration string matched against a generated regex; `get_value` coerces to `cint`; `format_for_input` renders via `get_formatted_duration` | `frappe/public/js/frappe/form/controls/duration.js:1`, `frappe/public/js/frappe/form/controls/duration.js:2-5`, `frappe/public/js/frappe/form/controls/duration.js:68-70`, `frappe/public/js/frappe/form/controls/duration.js:155-168`, `frappe/public/js/frappe/form/controls/duration.js:191-193` |
| 10 | `Geolocation` | `ControlGeolocation` | `controls/geolocation.js` | `ControlData` | `horizontal = false`; **hides the inherited text input** and replaces it with a Leaflet map; fetches Leaflet at runtime through `frappe.require`; monkey-patches `L.Circle` and `L.CircleMarker` to round-trip a radius through GeoJSON; reads **no** docfield property | `frappe/public/js/frappe/form/controls/geolocation.js:3-9`, `frappe/public/js/frappe/form/controls/geolocation.js:49-54`, `frappe/public/js/frappe/form/controls/geolocation.js:140-162`, `frappe/public/js/frappe/form/controls/geolocation.js:163-184` |
| 11 | `Barcode` | `ControlBarcode` | `controls/barcode.js` | `ControlData` | appends an SVG area to the wrapper in `make_wrapper`; `parse` converts typed data into **SVG markup**, which is what reaches the model; `set_formatted_input` recovers the underlying data from a `data-barcode-value` attribute and assigns the SVG directly onto `this.doc`; reads JsBarcode options out of `df.options` as JSON | `frappe/public/js/frappe/form/controls/barcode.js:3`, `frappe/public/js/frappe/form/controls/barcode.js:4-12`, `frappe/public/js/frappe/form/controls/barcode.js:14-23`, `frappe/public/js/frappe/form/controls/barcode.js:25-42`, `frappe/public/js/frappe/form/controls/barcode.js:59-70` |
| 12 | `Signature` | `ControlSignature` | `controls/signature.js` | `ControlData` | overrides `make()` to fetch jSignature by hardcoded asset path and build a pad inside a `ResizeObserver` callback; overrides `refresh_input` and `get_value` entirely; stores a base64 image obtained from `jSignature("getData")`; reads **no** docfield property | `frappe/public/js/frappe/form/controls/signature.js:1`, `frappe/public/js/frappe/form/controls/signature.js:2-17`, `frappe/public/js/frappe/form/controls/signature.js:120-122`, `frappe/public/js/frappe/form/controls/signature.js:129-133` |
| 13 | `Rating` | `ControlRating` | `controls/rating.js` | `ControlFloat` | calls `super.make_input()` and then **overwrites the whole input area** with inline star SVGs; `options` is the star count, defaulting to 5; the stored value is a **fraction of the maximum**, not a star count; re-checks `can_write()` at interaction time rather than relying on `$input`; overrides `get_value` to return `this.value` unconditionally | `frappe/public/js/frappe/form/controls/rating.js:1`, `frappe/public/js/frappe/form/controls/rating.js:2-19`, `frappe/public/js/frappe/form/controls/rating.js:45-47`, `frappe/public/js/frappe/form/controls/rating.js:86`, `frappe/public/js/frappe/form/controls/rating.js:95-100` |
| 14 | `JSON` | `ControlJSON` | `controls/json.js` | `ControlCode` | **overrides exactly one method**, `set_language`, pinning the Ace mode to `ace/mode/json` and the keyboard handler to `ace/keyboard/vscode`, thereby ignoring `df.options`; the whole file is six lines, and the class *expression* is misnamed `ControlCode` | `frappe/public/js/frappe/form/controls/json.js:1`, `frappe/public/js/frappe/form/controls/json.js:2-5` |
| 15 | `Code` | `ControlCode` | `controls/code.js` | `ControlText` | replaces the textarea with an Ace editor built asynchronously after `load_lib()` resolves; maps `df.options` through a fourteen-entry language table and warns on an unrecognised value; adds an expand toggle switching the editor between 300px and 600px | `frappe/public/js/frappe/form/controls/code.js:1`, `frappe/public/js/frappe/form/controls/code.js:2-5`, `frappe/public/js/frappe/form/controls/code.js:198-225`, `frappe/public/js/frappe/form/controls/code.js:259-276` |
| 16 | `Markdown Editor` | `ControlMarkdownEditor` | `controls/markdown_editor.js` | `ControlCode` | wraps the Ace target in a `markdown-container`, adds a Preview/Edit toggle rendering through `frappe.markdown`, enables wrap mode, adds image drag-and-drop via `frappe.ui.FileUploader`; `set_language` **assigns `df.options = "Markdown"`** when unset; `set_disp_area` renders as text rather than through `frappe.format` | `frappe/public/js/frappe/form/controls/markdown_editor.js:1-4`, `frappe/public/js/frappe/form/controls/markdown_editor.js:5-39`, `frappe/public/js/frappe/form/controls/markdown_editor.js:41-46`, `frappe/public/js/frappe/form/controls/markdown_editor.js:60-62`, `frappe/public/js/frappe/form/controls/markdown_editor.js:64-103` |
| 17 | `Markdown` | **none** | — | — | **Absent.** `Markdown` is not a fieldtype. The canonical name is `Markdown Editor` (row 16), so `make_control` would derive `ControlMarkdown`, which does not exist, and take the `console.log` arm. Searched: the `fieldtype` enumeration in `frappe/core/doctype/docfield/docfield.json`, the `data_fieldtypes` tuple, and `grep -rn "ControlMarkdown\b" frappe/public/js/` excluding `ControlMarkdownEditor` — **zero** hits. No line number is given for the absent class | nearest related code: `frappe/model/__init__.py:19` (`"Markdown Editor"` in `data_fieldtypes`), `frappe/core/doctype/docfield/docfield.json:118` (the enumeration, which contains `Markdown Editor` and no `Markdown`), `frappe/public/js/frappe/form/controls/control.js:50-53` (the arm an unknown name reaches) |
| 18 | `Attach` | `ControlAttach` | `controls/attach.js` | `ControlData` | overrides `make_input` **without calling `super`**, so `this.$input` is a `<button class="btn-attach">` rather than an input element, alongside a hidden `.attached-file` display row; opens a `frappe.ui.FileUploader` on click; expects `df.options` to be an **object**, merged with `Object.assign` | `frappe/public/js/frappe/form/controls/attach.js:1`, `frappe/public/js/frappe/form/controls/attach.js:2-30`, `frappe/public/js/frappe/form/controls/attach.js:56-59`, `frappe/public/js/frappe/form/controls/attach.js:74-95` |

Eighteen rows close seventeen mandated types, because `Markdown` is recorded as an absence in its own row
rather than silently folded into `Markdown Editor`. Requirement 6.9 governs the form of row 17: the absent
unit is named, the nearest related code is cited, and no line number is given for the absent class.

### 5.4 `Table` delegates to the grid

`ControlTable` is the only mandated control that renders none of its own content. `make()` calls
`super.make()` and then immediately constructs a `Grid`, passing itself as `control` and its own wrapper as
`parent` (`frappe/public/js/frappe/form/controls/table.js:8-14`); the `Grid` class is imported from outside
the controls directory (`frappe/public/js/frappe/form/controls/table.js:1`). Three of the four methods a
control is expected to implement are one-line forwards:

| Control method | Forwards to | Citation |
|---|---|---|
| `refresh_input()` | `this.grid.refresh()` | `frappe/public/js/frappe/form/controls/table.js:134-136` |
| `get_value()` | `this.grid.get_data()` | `frappe/public/js/frappe/form/controls/table.js:137-141` |
| `validate()` | `this.get_value()`, i.e. the grid again | `frappe/public/js/frappe/form/controls/table.js:145-147` |
| `set_input()` | nothing — the method body is empty | `frappe/public/js/frappe/form/controls/table.js:142-144` |

Everything downstream of `refresh_input` is therefore the grid engine's, and is documented in
`docs/ui/02-child-table-grid-engine.md` rather than here — visible-column selection, `idx` maintenance,
pagination, the expanded row form and the bulk-edit path. Two facts belong on this side of the boundary
because they are properties of the *control*, not the grid.

First, because `ControlTable` extends `frappe.ui.form.Control` and not `ControlInput`
(`frappe/public/js/frappe/form/controls/table.js:3`), the `"Read"`/`"Write"` split of §4.1 never runs for a
`Table` field. `BaseControl.refresh` sets `disp_status`, toggles `hide-control`, and then calls
`refresh_input` (`frappe/public/js/frappe/form/controls/base_control.js:138-143`) — but `toggleClass` returns
the jQuery object, which is truthy, so the `&&` chain does not short-circuit on a `"None"` status. A hidden
child table still runs a full `grid.refresh()`. The early return that protects every other control
(`frappe/public/js/frappe/form/controls/base_input.js:95`) is inherited from a class `ControlTable` does not
extend. Read-only handling for the grid is arranged separately, through the `grid.display_status` tests in
`BaseControl.get_status` that demote a child control to `"Read"` when its parent grid is read-only
(`frappe/public/js/frappe/form/controls/base_control.js:71-75`,
`frappe/public/js/frappe/form/controls/base_control.js:98-107`).

Second, the paste-from-spreadsheet handler is bound on the **control's wrapper**, not inside the grid
(`frappe/public/js/frappe/form/controls/table.js:19`), and it holds its own fieldtype→coercion table for
`Date`, `Int`, `Check`, `Float` and `Currency`
(`frappe/public/js/frappe/form/controls/table.js:29-34`). That table is a fifth place where fieldtype-keyed
behaviour is hard-coded, independent of the controls in §5.3, and it covers five fieldtypes out of the
forty-four the enumeration lists (`frappe/core/doctype/docfield/docfield.json:118`): a pasted `Percent` or
`Duration` column is written through uncoerced.

### 5.5 `Link` and `Dynamic Link` — resolving the target doctype

For `Link` the target is the docfield's `options` string, returned unmodified:

```
get_options() { return this.df.options; }                                        (link.js:93-95)
```

It is also written into the DOM as `data-target` (`frappe/public/js/frappe/form/controls/link.js:65`) and is
the sole input to three separate decisions, each consulting a different boot-time list:

| Predicate | Consults | Citation |
|---|---|---|
| `is_translatable()` | `frappe.boot.translated_doctypes` | `frappe/public/js/frappe/form/controls/link.js:122-124` |
| `is_title_link()` | `frappe.boot.link_title_doctypes` | `frappe/public/js/frappe/form/controls/link.js:125-127` |
| target for search and validation | `get_options()` directly | `frappe/public/js/frappe/form/controls/link.js:420`, `frappe/public/js/frappe/form/controls/link.js:581` |

`get_translated(value)` returns `__(value)` when `is_translatable()` is true and the raw value otherwise
(`frappe/public/js/frappe/form/controls/link.js:119-121`), and it is applied to the displayed text at five
sites — the input value on selection, both Awesomplete item shapes, the dropdown label, and the stored label
(`frappe/public/js/frappe/form/controls/link.js:233`,
`frappe/public/js/frappe/form/controls/link.js:237`,
`frappe/public/js/frappe/form/controls/link.js:251`,
`frappe/public/js/frappe/form/controls/link.js:143`,
`frappe/public/js/frappe/form/controls/link.js:151`).

This confirms and sharpens §4.2's finding about `translatable`. The gate on a `Link`'s translation is
`frappe.boot.translated_doctypes`, which is built from DocTypes carrying the **doctype-level**
`translated_doctype` property plus `Property Setter` overrides of the same property
(`frappe/translate.py:970-975`, exposed at `frappe/boot.py:120`) — the exact parallel of
`link_title_doctypes` (`frappe/boot.py:553-560`). The **docfield** `translatable` flag plays no part in it.
So a `Link` field is translated because of what its *target doctype* is, and the flag §4.2 examined controls
only whether a translation-manager button appears
(`frappe/public/js/frappe/form/controls/base_control.js:149-159`). The two mechanisms share a vocabulary and
nothing else, and neither is settable per field on the form.

`ControlDynamicLink` changes exactly one thing: `options` no longer names a doctype, it names **another
field** whose current value is the doctype. `get_options` resolves that value through a four-way branch, in
the order the code tests them (`frappe/public/js/frappe/form/controls/dynamic_link.js:2-29`):

```
1. df.get_options is a function          → options ← df.get_options(this)          (dynamic_link.js:4-5)
2. docname == null and cur_dialog exists → options ← cur_dialog.get_value(df.options)
                                                                                    (dynamic_link.js:6-8)
3. no cur_frm:
   3a. cur_list  → options ← cur_list.page.fields_dict[df.options].get_input_value() (dynamic_link.js:10-12)
   3b. cur_page  → options ← the DOM input[data-fieldname="<df.options>"] value,
                   falling back to frappe.model.get_value(df.parent, docname, df.options)
                                                                                    (dynamic_link.js:13-19)
4. otherwise    → options ← frappe.model.get_value(df.parent, docname, df.options)  (dynamic_link.js:20-22)
then: if frappe.model.is_single(options) → frappe.throw                             (dynamic_link.js:24-26)
```

Three consequences follow, and all three are properties of the *inheritance*, not of this file.

1. **The translation and title-link decisions become dynamic.** `is_translatable()` and `is_title_link()`
   call `this.get_options()` (`frappe/public/js/frappe/form/controls/link.js:123`,
   `frappe/public/js/frappe/form/controls/link.js:126`), which is now the overridden method. Whether a
   `Dynamic Link` translates its display text therefore depends on the current value of a *different* field,
   and changes as the user edits that field.
2. **Branches 2, 3a and 3b read the doctype out of the DOM or out of a global, not out of the model.**
   `cur_dialog`, `cur_list`, `cur_frm` and `cur_page` are ambient globals, and branch 3b falls back to a
   jQuery selector over `cur_page.page` (`frappe/public/js/frappe/form/controls/dynamic_link.js:14-15`). The
   resolved doctype for the same docfield is thus a function of which page object happens to be current.
3. **The one validation is a `Single` check, and it throws rather than degrades.** `frappe.throw` on a
   `Single` target (`frappe/public/js/frappe/form/controls/dynamic_link.js:25`) is the only guard; a value
   that is not a DocType name at all is passed through to the search call unchecked.

### 5.6 `Currency`, `Float` and `Percent` — which control, and where formatting enters

These three share one base and differ by a single method each, which makes the division of labour unusually
clean:

| Fieldtype | Control | Overrides, relative to `ControlFloat` | Citation |
|---|---|---|---|
| `Float` | `ControlFloat` extends `ControlInt` | — (it *is* the base) | `frappe/public/js/frappe/form/controls/float.js:1` |
| `Currency` | `ControlCurrency` | `get_precision` only | `frappe/public/js/frappe/form/controls/currency.js:2-14` |
| `Percent` | `ControlPercent` | `format_for_input` only | `frappe/public/js/frappe/form/controls/percent.js:2-12` |

Formatting enters at exactly two points, and they are not the same point:

- **Writable rendering** goes through the per-type `format_for_input`. `ControlFloat` calls
  `format_number(value, this.get_number_format(), this.get_precision())`
  (`frappe/public/js/frappe/form/controls/float.js:12-18`); `ControlPercent` calls the same helper with
  `Math.min(this.get_precision(), <decimals present in the value>)`
  (`frappe/public/js/frappe/form/controls/percent.js:6-11`); `ControlCurrency` does not override it and so
  uses `ControlFloat`'s, differing only through `get_precision`.
- **Read-only rendering** does not reach `format_for_input` at all. It goes through
  `BaseInput.set_disp_area` → `frappe.format`
  (`frappe/public/js/frappe/form/controls/base_input.js:166`), with the zero-preserving special case for
  `Currency`, `Int` and `Float` noted in §5.2
  (`frappe/public/js/frappe/form/controls/base_input.js:148-157`). A `Percent` field is absent from that
  list, so its zero takes the `this.value || value` branch
  (`frappe/public/js/frappe/form/controls/base_input.js:156`).

Parsing is the third entry point and is shared: `ControlFloat.parse` applies `flt(value, get_precision())`
(`frappe/public/js/frappe/form/controls/float.js:5`), so precision is applied on the way **into** the model,
not only on the way out. The chain by which `get_precision` reaches a number — `df.precision`, then
`sysdefaults`, then the currency's own format — is stated at
`frappe/public/js/frappe/form/controls/float.js:31-34` and
`frappe/public/js/frappe/form/controls/currency.js:2-14`, and §6 resolves it in full together with
`formatters.js`; this section deliberately stops at naming the two methods.

One control-level fact does belong here, because it is a divergence rather than a step of the resolution
chain: `ControlCurrency.get_precision` **caches its answer by writing to `this.df.precision`**
(`frappe/public/js/frappe/form/controls/currency.js:7`,
`frappe/public/js/frappe/form/controls/currency.js:9`), mutating the docfield object rather than a field of
the control. `this.df` for a form control is the docfield from the cached `Meta`, so the first `Currency`
control to render fixes `precision` on metadata that every later control, every later document and the grid
all share.

`Rating` is the fourth member of this family — `ControlRating extends ControlFloat`
(`frappe/public/js/frappe/form/controls/rating.js:1`) — and `ControlFloat.get_number_format` returns
`undefined` for it by an explicit fieldtype test
(`frappe/public/js/frappe/form/controls/float.js:22`), the same early return it takes for a `Float` whose
`options` is blank (`frappe/public/js/frappe/form/controls/float.js:23`).

### 5.7 `Code`, `JSON` and `Markdown Editor` — one editor, fetched not bundled

All three are the same editor. The chain is `ControlText` → `ControlCode`
(`frappe/public/js/frappe/form/controls/code.js:1`) → `ControlJSON`
(`frappe/public/js/frappe/form/controls/json.js:1`) and `ControlCode` → `ControlMarkdownEditor`
(`frappe/public/js/frappe/form/controls/markdown_editor.js:1-3`). `ControlTextEditor` joins the same base
(`frappe/public/js/frappe/form/controls/text_editor.js:136`), so the Quill rich-text control is also a
descendant of the Ace control.

**Fetched, not bundled.** `load_lib` builds an asset path and calls `frappe.require`
(`frappe/public/js/frappe/form/controls/code.js:259-276`), memoising the promise on `this.library_loaded`
(`frappe/public/js/frappe/form/controls/code.js:260`, `frappe/public/js/frappe/form/controls/code.js:268`).
The path is chosen from `frappe.boot.developer_mode`: the unminified `src-noconflict` directory in developer
mode and `src-min-noconflict` otherwise
(`frappe/public/js/frappe/form/controls/code.js:262-266`). Ace is then addressed through the `window.ace`
global (`frappe/public/js/frappe/form/controls/code.js:270`,
`frappe/public/js/frappe/form/controls/code.js:61`) rather than through an imported binding, and further
modules are pulled in on demand at runtime through `ace.config.loadModule`
(`frappe/public/js/frappe/form/controls/code.js:167`). Contrast `Barcode`, which uses a **static** ESM import
of `jsbarcode` (`frappe/public/js/frappe/form/controls/barcode.js:1`) and so is bundled.

The consequence is a construction race, and it is visible in the code rather than inferred. `make_input`
returns after registering a `.then()` — it does not await it
(`frappe/public/js/frappe/form/controls/code.js:2-5`) — while `BaseInput.refresh_input` calls `make_input()`
and `update_input()` back to back with nothing between them
(`frappe/public/js/frappe/form/controls/base_input.js:109-110`). So `set_input` runs on the first render
before `this.editor` exists. `make_input`'s own `if (this.editor) return;` guard
(`frappe/public/js/frappe/form/controls/code.js:3`) tests the property the async callback has not yet
assigned, so a second `refresh` arriving before the library resolves passes the guard and schedules a second
`make_ace_editor()`; `make_ace_editor` re-tests `this.markdown_container` in the Markdown subclass
(`frappe/public/js/frappe/form/controls/markdown_editor.js:7`) but `ControlCode` has no equivalent guard at
its own top (`frappe/public/js/frappe/form/controls/code.js:45`).

Language selection is where the three diverge, and each does it differently:

| Fieldtype | How the Ace mode is chosen | Citation |
|---|---|---|
| `Code` | `df.options` is looked up in a fourteen-entry map; an unrecognised value produces a `console.warn` and no mode change | `frappe/public/js/frappe/form/controls/code.js:198-225` |
| `JSON` | hard-coded to `ace/mode/json`, ignoring `df.options` entirely; also sets a `vscode` keyboard handler | `frappe/public/js/frappe/form/controls/json.js:2-5` |
| `Markdown Editor` | **assigns** `df.options = "Markdown"` when unset, then delegates upward to `ControlCode.set_language` | `frappe/public/js/frappe/form/controls/markdown_editor.js:41-46` |

`Markdown Editor` alone adds rendering of its own: a Preview/Edit toggle that runs the buffer through
`frappe.markdown` (`frappe/public/js/frappe/form/controls/markdown_editor.js:48-52`,
`frappe/public/js/frappe/form/controls/markdown_editor.js:16-33`) and an image-drop handler that opens a
`FileUploader` and inserts a Markdown image reference at the cursor
(`frappe/public/js/frappe/form/controls/markdown_editor.js:64-103`). It also overrides `set_disp_area` to
insert the raw value as **text** (`frappe/public/js/frappe/form/controls/markdown_editor.js:60-62`), bypassing
the central `frappe.format` path of §5.2 — so a read-only `Markdown Editor` shows source, not rendered
Markdown.

### 5.8 The four unconventional controls — metadata and external dependencies

`Geolocation`, `Barcode`, `Signature` and `Rating` are the least conventional of the seventeen. Two questions
separate them cleanly: is the control configured by metadata, and what does it depend on that is not in the
control file?

| Fieldtype | Metadata-driven? | External dependency | How the dependency arrives | Citation |
|---|---|---|---|---|
| `Geolocation` | **No.** `grep -c "df.options" geolocation.js` returns **zero**; configuration comes from the `frappe.utils.map_defaults` global — centre, zoom, four tile URLs and the marker image path | Leaflet, plus Leaflet.draw and a locate control, used through the global `L` | `frappe.require("leaflet.bundle.js")` and the matching CSS, awaited by `Promise.all` — **fetched at runtime** | `frappe/public/js/frappe/form/controls/geolocation.js:49-54`, `frappe/public/js/frappe/form/controls/geolocation.js:163-184`, `frappe/public/js/frappe/form/controls/geolocation.js:166-167` |
| `Barcode` | **Yes.** `df.options` is parsed as a JSON options blob and merged over three hard-coded defaults, with a special case expanding `format: "EAN"` to `EAN8` or `EAN13` by value length | `jsbarcode` | `import JsBarcode from "jsbarcode"` — a **static ESM import**, therefore bundled | `frappe/public/js/frappe/form/controls/barcode.js:1`, `frappe/public/js/frappe/form/controls/barcode.js:59-70`, `frappe/public/js/frappe/form/controls/barcode.js:49` |
| `Signature` | **No.** `grep -c "df.options" signature.js` returns **zero**; nothing about the pad is configurable per field | jSignature | `frappe.require("/assets/frappe/js/lib/jSignature.min.js")` — a **hardcoded asset path**, fetched at runtime, and *not* awaited before `make()` returns | `frappe/public/js/frappe/form/controls/signature.js:12-17` |
| `Rating` | **Yes**, minimally. `df.options` is the number of stars, defaulting to 5, read at three sites | **none** — the stars are inline SVG paths in the control file | no fetch and no import | `frappe/public/js/frappe/form/controls/rating.js:5`, `frappe/public/js/frappe/form/controls/rating.js:53`, `frappe/public/js/frappe/form/controls/rating.js:99`, `frappe/public/js/frappe/form/controls/rating.js:7-10` |

Two of the four store something other than the value the user thinks they are entering, and this is the most
consequential fact in the group:

- **`Barcode` stores SVG markup.** `parse` returns `this.get_barcode_html(value)` for typed data and the
  value unchanged if it already begins with `<svg`
  (`frappe/public/js/frappe/form/controls/barcode.js:14-23`), and `get_barcode_html` returns
  `this.barcode_area.html()` after rendering
  (`frappe/public/js/frappe/form/controls/barcode.js:52`). The barcode data survives only as a
  `data-barcode-value` attribute inside that markup
  (`frappe/public/js/frappe/form/controls/barcode.js:50`), which `set_formatted_input` reads back to
  repopulate the visible input
  (`frappe/public/js/frappe/form/controls/barcode.js:31-32`,
  `frappe/public/js/frappe/form/controls/barcode.js:40`). A rendering failure is caught and turned into a
  field description, and `get_barcode_html` then returns `undefined`
  (`frappe/public/js/frappe/form/controls/barcode.js:53-55`).
- **`Rating` stores a fraction of the maximum.** On click the star index is divided by `out_of_ratings`
  before being written (`frappe/public/js/frappe/form/controls/rating.js:86`) and multiplied back on display
  (`frappe/public/js/frappe/form/controls/rating.js:99-101`). Changing `options` from 5 to 10 therefore
  reinterprets every stored value rather than rescaling it, and the value is not recoverable without the
  current `options`.
- **`Signature` stores a base64 image** obtained from `jSignature("getData")`
  (`frappe/public/js/frappe/form/controls/signature.js:131-132`).

### 5.9 Worked example — `Sales Invoice.customer`

One field, traced from its stored definition to its DOM. The definition is

```json
{
 "bold": 1,
 "fieldname": "customer",
 "fieldtype": "Link",
 "in_standard_filter": 1,
 "label": "Customer",
 "options": "Customer",
 "print_hide": 1,
 "reqd": 1,
 "search_index": 1
}
```

at `accounts/doctype/sales_invoice/sales_invoice.json:264-278`. Assume a user with `write` at permlevel 0 on
a draft.

**Step 1 — the layout reaches the field.** A-01-2 step 4f dispatches to `make_field(df)` because `Link` is
not one of the five break fieldtypes (`frappe/public/js/frappe/form/layout.js:222-224`), and `make_field`
calls `init_field` (`frappe/public/js/frappe/form/layout.js:262`). `df.mask` is unset, so the masked-field
rewrite does not fire (`frappe/public/js/frappe/form/layout.js:279`).

**Step 2 — the registry resolves the class.** `"Control" + "Link".replace(/ /g, "")` = `"ControlLink"`
(`frappe/public/js/frappe/form/controls/control.js:49`); `frappe.ui.form.ControlLink` exists, having been
assigned when `link.js` was imported
(`frappe/public/js/frappe/form/controls/link.js:10`,
`frappe/public/js/frappe/form/controls/control.js:13`); the truthiness test passes
(`frappe/public/js/frappe/form/controls/control.js:50`) and the instance is constructed
(`frappe/public/js/frappe/form/controls/control.js:51`). `init_field` then sets `fieldobj.layout`
(`frappe/public/js/frappe/form/layout.js:299`).

**Step 3 — the constructor walks the chain.** `BaseControl`'s constructor copies the options onto the
instance and calls `make()` (`frappe/public/js/frappe/form/controls/base_control.js:3-4`). `make()` resolves
to `ControlInput.make`, which calls `super.make()`, then `set_input_areas()` and `set_max_width()`
(`frappe/public/js/frappe/form/controls/base_input.js:4-15`). `super.make()` is `BaseControl.make`, which
calls `make_wrapper()` — resolving to `ControlInput`'s, not `BaseControl`'s
(`frappe/public/js/frappe/form/controls/base_input.js:16-40`) — and then stamps `data-fieldtype="Link"` and
`data-fieldname="customer"` on the wrapper
(`frappe/public/js/frappe/form/controls/base_control.js:11-13`) and appends the fieldname tooltip
(`frappe/public/js/frappe/form/controls/base_control.js:17-18`). `set_input_areas` names
`.control-input` as `input_area` and `.control-value` as `disp_area`
(`frappe/public/js/frappe/form/controls/base_input.js:52`,
`frappe/public/js/frappe/form/controls/base_input.js:56`). `ControlInput.horizontal` is `true`
(`frappe/public/js/frappe/form/controls/base_input.js:3`), so `.form-group` also gets `horizontal`
(`frappe/public/js/frappe/form/controls/base_input.js:36-38`).

**Step 4 — `make_input` is `ControlLink`'s, not `ControlData`'s.** `ControlLink.make_input` does **not** call
`super.make_input()`; it prepends its own `div.link-field` containing the text input and the clear/open
buttons (`frappe/public/js/frappe/form/controls/link.js:12-24`), then finds `$input` inside it
(`frappe/public/js/frappe/form/controls/link.js:26`) and sets `data-target="Customer"` from `df.options`
(`frappe/public/js/frappe/form/controls/link.js:65`). `ControlData`'s generic `html_element`/`input_type`
construction (`frappe/public/js/frappe/form/controls/data.js:10-17`) is therefore bypassed for this
fieldtype, and the paste-length warning bound there
(`frappe/public/js/frappe/form/controls/data.js:19-62`) does not apply to a `Link`.

**Step 5 — the two boot lists are consulted, and both miss.** `Customer` carries `title_field:
"customer_name"` (`selling/doctype/customer/customer.json:809`) but **not** `show_title_field_in_link`, so it
is absent from `link_title_doctypes` (`frappe/boot.py:553-560`) and `is_title_link()` is false
(`frappe/public/js/frappe/form/controls/link.js:126`). `set_link_title` therefore takes its early branch and
calls `translate_and_set_input_value(value, value)`
(`frappe/public/js/frappe/form/controls/link.js:131-133`) — the customer *code* is displayed, not the
customer name. `Customer` also does not carry `translated_doctype`, so `is_translatable()` is false
(`frappe/public/js/frappe/form/controls/link.js:123`) and `get_translated` returns the value unchanged
(`frappe/public/js/frappe/form/controls/link.js:120`).

**Step 6 — the flags of §4 apply.** `disp_status` is `"Write"` (no `hidden`, no `read_only`, draft docstatus),
so `can_write()` is true (`frappe/public/js/frappe/form/controls/base_input.js:144-146`), `disp_area` is
hidden and `input_area` shown (`frappe/public/js/frappe/form/controls/base_input.js:106-107`). `bold: 1`
adds the `bold` class — and would have anyway, since `reqd: 1` is OR-ed into the same expression
(`frappe/public/js/frappe/form/controls/base_input.js:294`), which is §4.5 finding 2 in live use.
`print_hide: 1` has no effect on the form.

**Resulting DOM.** Assembling the markup from
`frappe/public/js/frappe/form/controls/base_input.js:21-33`,
`frappe/public/js/frappe/form/controls/base_control.js:11-18` and
`frappe/public/js/frappe/form/controls/link.js:14-24`:

```html
<div class="frappe-control" data-fieldtype="Link" data-fieldname="customer">
  <div class="form-group horizontal">
    <div class="clearfix">
      <label class="control-label" style="padding-right: 5px;">Customer</label>
      <span class="help"></span>
    </div>
    <div class="control-input-wrapper">
      <div class="control-input">
        <div class="link-field ui-front" style="position: relative;">
          <input type="text" class="input-with-feedback form-control bold"
                 data-target="Customer">
          <span class="link-btn">
            <a class="btn-clear" ...>…</a>
            <a class="btn-open" ...>…</a>
          </span>
        </div>
      </div>
      <div class="control-value like-disabled-input hide"></div>
      <div class="help-box small text-extra-muted hide"></div>
    </div>
  </div>
  <span class="tooltip-content">customer</span>
</div>
```

The `.control-value` div carries `hide` because the field is writable; on a submitted invoice the classes
swap and the same div receives the output of `frappe.format`
(`frappe/public/js/frappe/form/controls/base_input.js:116-120`,
`frappe/public/js/frappe/form/controls/base_input.js:166-169`). The Awesomplete dropdown is not in this tree:
it is attached to the input by the library at `frappe/public/js/frappe/form/controls/link.js:224`, which is
why the wrapper carries `ui-front` and `position: relative`
(`frappe/public/js/frappe/form/controls/link.js:14`).

### 5.10 Findings recorded for §8

Nine behaviours observed while reading this path are defects rather than descriptions. They are stated here
in prose; the numbered inventory and the verdicts are §8's and §10's to write.

1. **An unknown fieldtype fails silently and invisibly.** `make_control`'s `else` arm calls `console.log` and
   returns `undefined` (`frappe/public/js/frappe/form/controls/control.js:52-54`), `init_field` propagates
   it (`frappe/public/js/frappe/form/layout.js:298-302`) and `make_field` returns before registering the
   field in any of `fields_list`, `fields_dict`, `section` or `current_tab`
   (`frappe/public/js/frappe/form/layout.js:265-275`). The form renders with a field missing, no user-visible
   error, and no entry in the structures that `refresh_field`, `set_value` or `toggle_display` would use to
   report one. Because the class name is derived by string concatenation
   (`frappe/public/js/frappe/form/controls/control.js:49`) and the canonical fieldtype list lives only on the
   server (`frappe/model/__init__.py:8-30`, `frappe/core/doctype/docfield/docfield.json:118`), a one-character
   corruption of a stored `fieldtype` is indistinguishable at render time from a deliberately unsupported
   one.
2. **`Markdown` is not a fieldtype.** The canonical name is `Markdown Editor`
   (`frappe/model/__init__.py:19`, `frappe/core/doctype/docfield/docfield.json:118`) and no
   `ControlMarkdown` exists — `grep -rn "ControlMarkdown\b" frappe/public/js/` excluding
   `ControlMarkdownEditor` returns **zero** hits, the only declaration being
   `frappe/public/js/frappe/form/controls/markdown_editor.js:1`. Requirement 6.6 names `Markdown`, so the
   requirement itself carries the wrong name; §5.3 row 17 records it as an absence with no line number. This
   is the third such correction in the investigation, after `FormPage` (§1.5) and `grid_form.js`.
3. **Four controls write to the shared docfield object.** `this.df` for a form control is the docfield from
   the cached `Meta`, so any assignment to it outlives the control. Observed:
   `ControlCurrency.get_precision` caches into `df.precision`
   (`frappe/public/js/frappe/form/controls/currency.js:7`,
   `frappe/public/js/frappe/form/controls/currency.js:9`);
   `ControlMarkdownEditor.set_language` assigns `df.options = "Markdown"`
   (`frappe/public/js/frappe/form/controls/markdown_editor.js:43`);
   `Layout.init_field` rewrites `df.fieldtype` and `df.read_only` for a masked field
   (`frappe/public/js/frappe/form/layout.js:282-283`); and `BaseControl.toggle` writes `df.hidden`
   (`frappe/public/js/frappe/form/controls/base_control.js:33-36`). §2.2 steps 5b and 6b record two more
   instances in the layout pass (`frappe/public/js/frappe/form/layout.js:345-348`,
   `frappe/public/js/frappe/form/layout.js:370-373`). The docfield is treated as scratch space by six
   separate call sites.
4. **`Select` silently rewrites the model when the stored value is not among the options.**
   `set_formatted_input` compares the value it was given with what the `<select>` element actually holds and,
   on a mismatch, calls `set_model_value(input_value)` with the comment "model value must be same as whatever
   the input is" (`frappe/public/js/frappe/form/controls/select.js:55-59`). Rendering a form is therefore a
   write: a stored value dropped from `options` by a later customisation is replaced by whatever the browser
   selected, with no prompt and no indication that the document changed.
5. **`Barcode` stores rendered SVG markup in the field, and a render function writes it.** `parse` returns
   markup rather than data (`frappe/public/js/frappe/form/controls/barcode.js:20`), and
   `set_formatted_input` — a display method — assigns straight to `this.doc[this.df.fieldname]`
   (`frappe/public/js/frappe/form/controls/barcode.js:37`), bypassing `set_model_value`
   (`frappe/public/js/frappe/form/controls/base_control.js:272-289`), the undo manager
   (`frappe/public/js/frappe/form/controls/base_control.js:220-227`) and every `change`/`onchange` trigger
   (`frappe/public/js/frappe/form/controls/base_control.js:238-243`). The barcode data survives only as an
   attribute inside the markup (`frappe/public/js/frappe/form/controls/barcode.js:50`), so the field cannot
   be queried, filtered or compared as data. This is the stored-value/displayed-text conflation Requirement
   13.4 rejects, in its most literal form.
6. **`Rating` orphans its own input element.** `make_input` calls `super.make_input()`, which builds and
   attaches an `<input>` and sets `this.$input`
   (`frappe/public/js/frappe/form/controls/rating.js:3`; `frappe/public/js/frappe/form/controls/data.js:12-17`),
   and then replaces the entire `input_area` contents with the star template
   (`frappe/public/js/frappe/form/controls/rating.js:19`), detaching it. Upstream knows: the comment
   "Rating doesn't have $input, so check write status at interaction time"
   (`frappe/public/js/frappe/form/controls/rating.js:46`) explains why `update_rating` re-tests `can_write()`
   itself (`frappe/public/js/frappe/form/controls/rating.js:47`). But `BaseInput.refresh_input` still calls
   `$input.prop("disabled", …)` on both branches
   (`frappe/public/js/frappe/form/controls/base_input.js:108`,
   `frappe/public/js/frappe/form/controls/base_input.js:122`), operating on a detached node. The stored value
   is additionally a fraction of `options` rather than a star count
   (`frappe/public/js/frappe/form/controls/rating.js:86`,
   `frappe/public/js/frappe/form/controls/rating.js:99-100`), so editing `options` reinterprets history.
7. **`ControlTable` renders its grid even when the field is hidden.** `BaseControl.refresh` chains
   `toggleClass("hide-control", …) && this.refresh_input && this.refresh_input()`
   (`frappe/public/js/frappe/form/controls/base_control.js:140-143`); `toggleClass` returns the jQuery
   object, so the chain never short-circuits, and `ControlTable.refresh_input` is an unconditional
   `this.grid.refresh()` (`frappe/public/js/frappe/form/controls/table.js:134-136`). Every other control is
   protected by `BaseInput.refresh_input`'s `disp_status != "None"` guard
   (`frappe/public/js/frappe/form/controls/base_input.js:95`), which `ControlTable` does not inherit because
   it extends `frappe.ui.form.Control` directly
   (`frappe/public/js/frappe/form/controls/table.js:3`). The cost of a hidden child table is therefore the
   full cost of a visible one; §7 quantifies it.
8. **The Ace-backed controls construct their editor asynchronously inside a synchronous render path.**
   `ControlCode.make_input` registers a `.then()` and returns
   (`frappe/public/js/frappe/form/controls/code.js:2-5`) while `BaseInput.refresh_input` calls `make_input()`
   and `update_input()` consecutively
   (`frappe/public/js/frappe/form/controls/base_input.js:109-110`), so the first `set_input` runs with
   `this.editor` undefined. The `if (this.editor) return;` guard
   (`frappe/public/js/frappe/form/controls/code.js:3`) tests a property assigned only after the library
   resolves (`frappe/public/js/frappe/form/controls/code.js:61`), so a second refresh arriving inside that
   window schedules a second `make_ace_editor()`; only the Markdown subclass carries an idempotence guard
   (`frappe/public/js/frappe/form/controls/markdown_editor.js:7`). The asset path additionally differs
   between developer and production mode
   (`frappe/public/js/frappe/form/controls/code.js:262-266`), so the timing differs between environments.
   `Signature` has the same shape and does not even memoise: `frappe.require` is called from `make()` and its
   `.then()` is neither awaited nor guarded
   (`frappe/public/js/frappe/form/controls/signature.js:12-17`).
9. **`Attach` expects `df.options` to be a JavaScript object, but the stored column is text.**
   `set_upload_options` merges it with `Object.assign(options, this.df.options)`
   (`frappe/public/js/frappe/form/controls/attach.js:92-93`), whereas `DocField.options` is stored as
   `Small Text` (`frappe/core/doctype/docfield/docfield.json:243-244`). Given a string,
   `Object.assign` spreads its character indices as keys, producing an options object with numeric
   properties and no error. The overload is unguarded and undocumented: three mandated fieldtypes read
   `options` as three incompatible shapes — a doctype name for `Link`
   (`frappe/public/js/frappe/form/controls/link.js:94`), a newline-delimited list for `Select`
   (`frappe/public/js/frappe/form/controls/select.js:65-67`), a JSON string for `Barcode`, which at least
   tests `frappe.utils.is_json` first
   (`frappe/public/js/frappe/form/controls/barcode.js:66-67`) — and `Attach` a live object. `Table
   MultiSelect` adds a fifth reading, a child-doctype name resolved one level further to that child's first
   `Link` field (`frappe/public/js/frappe/form/controls/table_multiselect.js:210-222`), where `find` takes
   the first match in stored order, so a child table with two `Link` fields silently binds to whichever
   comes first.

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
