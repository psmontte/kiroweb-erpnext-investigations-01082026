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
