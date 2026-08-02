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
