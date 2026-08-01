"""Markdown renderers: global overview, full table catalog, per-module deep dives."""

from __future__ import annotations

import collections
import os

from frappe_schema import (
    CHILD_COLUMNS,
    DEFAULT_COLUMNS,
    DocType,
    Registry,
)

KIND_ORDER = ["single", "master", "tree-master", "transaction", "child"]
KIND_LABEL = {
    "master": "Master",
    "tree-master": "Tree master (hierarchy)",
    "transaction": "Transaction (submittable)",
    "child": "Child / line-item table",
    "single": "Single (settings)",
}


def _esc(s: str) -> str:
    return (s or "").replace("|", "\\|").replace("\n", " ")


def _flags(f) -> str:
    out = []
    if f.reqd:
        out.append("NOT NULL")
    if f.unique:
        out.append("UNIQUE")
    if f.search_index:
        out.append("INDEX")
    if f.read_only:
        out.append("ro")
    if f.hidden:
        out.append("hidden")
    if f.fetch_from:
        out.append(f"denorm←{f.fetch_from}")
    if f.default:
        out.append(f"default={_esc(f.default)[:24]}")
    return ", ".join(out)


def _target(f, reg: Registry) -> str:
    if f.is_link:
        origin = reg.origin(f.options)
        mark = "" if origin.startswith("erpnext/") else f" *({origin})*"
        return f"→ `{f.options}`{mark}"
    if f.is_dynamic_link:
        return f"→ polymorphic, doctype in `{f.options}`"
    if f.fieldtype == "Select":
        opts = f.select_options
        if opts:
            shown = ", ".join(opts[:8])
            more = f" … (+{len(opts) - 8})" if len(opts) > 8 else ""
            return f"enum: {_esc(shown)}{more}"
    return ""


# --------------------------------------------------------------------------- #
# 1. global overview
# --------------------------------------------------------------------------- #
def overview(reg: Registry) -> str:
    L = ["# ERPNext schema reverse engineering — overview", ""]
    L += [
        "Generated from the ERPNext DocType JSON definitions. Every non-single DocType maps to",
        "exactly one physical table named `tab<DocType Name>`; child tables are the physical",
        "storage for repeating line items and are always referenced from a parent through a",
        "`Table` field.",
        "",
        f"**Total DocTypes parsed: {len(reg.doctypes)}** across {len(reg.modules())} modules.",
        "",
        "## Framework conventions you must decide to keep or drop",
        "",
        "| Convention | How ERPNext does it | Notes for our build |",
        "|---|---|---|",
        "| Primary key | `name varchar(140)` — a *business* key (naming series like `ACC-SINV-.YYYY.-.#####`), not an integer | Human-readable but expensive as FK; consider surrogate `bigint`/`uuid` PK + separate `doc_no` |",
        "| Foreign keys | Plain `varchar(140)` columns, **no DB-level FK constraints**; integrity enforced in Python | We can enforce real FKs |",
        "| Lifecycle | `docstatus tinyint`: 0 Draft, 1 Submitted, 2 Cancelled. Submitted rows are immutable | Core accounting invariant — keep the concept |",
        "| Line items | Separate child table per parent field with `parent`, `parenttype`, `parentfield`, `idx` | `parenttype` makes a child table shareable across parents; real FKs need one table per parent |",
        "| Polymorphism | `Dynamic Link`: value column + a sibling column naming the target DocType (e.g. `party_type`/`party`) | Blocks FK constraints; consider explicit nullable FKs or a party supertype table |",
        "| Denormalisation | `fetch_from` copies values from linked docs into the row at save time | Heavy read-optimisation; decide per field vs. views |",
        "| Settings | `issingle` DocTypes are stored as key/value rows in `tabSingles`, not their own table | Prefer a real typed settings table |",
        "| Hierarchies | `is_tree` uses nested sets (`lft`, `rgt`, `old_parent`) | Alternative: `ltree`/recursive CTE with `parent_id` |",
        "| Audit | `owner`, `creation`, `modified`, `modified_by` on every table + a `tabVersion` diff log | Keep; consider proper temporal tables |",
        "",
        "## Standard columns present on every table",
        "",
        "| Column | Type (Postgres) | Meaning |",
        "|---|---|---|",
        "| `name` | `varchar(140)` PK | business identifier / naming-series value |",
        "| `creation` | `timestamp` | insert time |",
        "| `modified` | `timestamp` | last update time (used for optimistic locking) |",
        "| `modified_by` | `varchar(140)` | user id |",
        "| `owner` | `varchar(140)` | creating user id |",
        "| `docstatus` | `smallint` | 0 draft / 1 submitted / 2 cancelled |",
        "| `idx` | `integer` | row order (position inside parent for child tables) |",
        "",
        "Child tables additionally carry: " + ", ".join(f"`{c}`" for c in CHILD_COLUMNS) + ".",
        "",
    ]

    # module table
    L += ["| Module | DocTypes | Masters | Trees | Transactions | Child tables | Singles | Columns |", "|---|--:|--:|--:|--:|--:|--:|--:|"]
    L += ["| App | Module | DocTypes | Masters | Trees | Transactions | Child tables | Singles | Columns |",
          "|---|---|--:|--:|--:|--:|--:|--:|--:|"]
    for a, m in sorted({(d.app, d.module) for d in reg.doctypes}):
        ds = [d for d in reg.doctypes if d.module == m and d.app == a]
        L.append(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                a,
                m,
                len(ds),
                sum(1 for d in ds if d.kind == "master"),
                sum(1 for d in ds if d.kind == "tree-master"),
                sum(1 for d in ds if d.kind == "transaction"),
                sum(1 for d in ds if d.kind == "child"),
                sum(1 for d in ds if d.kind == "single"),
                sum(len(d.columns) for d in ds),
            )
        )
    L += [
        "| | **TOTAL** | **{}** | | | | | | **{}** |".format(
            len(reg.doctypes), sum(len(d.columns) for d in reg.doctypes)
        ),
        "",
    ]

    # fieldtype histogram
    ft = collections.Counter(f.fieldtype for d in reg.doctypes for f in d.fields)
    L += ["## Fieldtype usage (drives our type mapping)", "", "| Fieldtype | Count | Postgres type |", "|---|--:|---|"]
    from frappe_schema import LAYOUT_FIELDTYPES, POSTGRES_TYPE_MAP, TABLE_FIELDTYPES

    for name, n in ft.most_common():
        if name in LAYOUT_FIELDTYPES:
            pg = "*layout only — no column*"
        elif name in TABLE_FIELDTYPES:
            pg = "*child table relation — no column*"
        else:
            pg = f"`{POSTGRES_TYPE_MAP.get(name, 'varchar(140)')}`"
        L.append(f"| {name} | {n} | {pg} |")
    L.append("")

    # hottest link targets
    inbound = collections.Counter()
    for d in reg.doctypes:
        for _fn, t in d.links:
            inbound[t] += 1
    L += [
        "## Most referenced entities (inbound Link count) — the true core of the model",
        "",
        "| Target DocType | Inbound links | Owned by (app/module) |",
        "|---|--:|---|",
    ]
    for t, n in inbound.most_common(40):
        L.append(f"| `{t}` | {n} | {reg.origin(t)} |")
    L.append("")

    # biggest tables
    L += [
        "## Widest tables (column count) — candidates for normalisation in our design",
        "",
        "| DocType | Module | Kind | Columns |",
        "|---|---|---|--:|",
    ]
    for d in sorted(reg.doctypes, key=lambda x: -len(x.columns))[:30]:
        L.append(f"| `{d.name}` | {d.module} | {d.kind} | {len(d.columns)} |")
    L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------- #
# 2. full catalog of all tables
# --------------------------------------------------------------------------- #
def full_catalog(reg: Registry) -> str:
    L = [
        "# Full table catalog — every DocType in ERPNext",
        "",
        f"{len(reg.doctypes)} DocTypes. `kind` legend: "
        + ", ".join(f"**{k}** = {KIND_LABEL[k]}" for k in KIND_ORDER),
        "",
    ]
    for a, m in sorted({(d.app, d.module) for d in reg.doctypes}):
        ds = [d for d in reg.doctypes if d.module == m and d.app == a]
        L += [f"## {a} / {m} ({len(ds)})", "", "| DocType | Physical table | Kind | Cols | Links | Child tables | Naming |", "|---|---|---|--:|--:|--:|---|"]
        for d in sorted(ds, key=lambda x: (KIND_ORDER.index(x.kind), x.name)):
            naming = d.autoname or d.naming_rule or "-"
            L.append(
                f"| `{d.name}` | `{d.table_name}` | {d.kind} | {len(d.columns)} | "
                f"{len(d.links)} | {len(d.child_tables)} | `{_esc(naming)}` |"
            )
        L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------- #
# 3. per-module deep dive
# --------------------------------------------------------------------------- #
def module_deep_dive(reg: Registry, module: str, notes: dict[str, str] | None = None) -> str:
    notes = notes or {}
    ds = [d for d in reg.doctypes if d.module == module and d.app == "erpnext"]
    L = [f"# Module deep dive: {module}", ""]
    if module in notes:
        L += [notes[module], ""]
    L += [f"{len(ds)} DocTypes / {sum(len(d.columns) for d in ds)} columns.", "", "## Contents", ""]
    for kind in KIND_ORDER:
        group = sorted([d for d in ds if d.kind == kind], key=lambda x: x.name)
        if not group:
            continue
        L.append(f"**{KIND_LABEL[kind]}** ({len(group)}): " + ", ".join(f"[{d.name}](#{_anchor(d.name)})" for d in group))
        L.append("")

    for kind in KIND_ORDER:
        group = sorted([d for d in ds if d.kind == kind], key=lambda x: x.name)
        if not group:
            continue
        L += [f"---", "", f"# {KIND_LABEL[kind]}s", ""]
        for d in group:
            L += _doctype_section(d, reg)
    return "\n".join(L)


def _anchor(name: str) -> str:
    return name.lower().replace(" ", "-").replace("(", "").replace(")", "")


def _doctype_section(d: DocType, reg: Registry) -> list[str]:
    L = [f"## {d.name}", ""]
    meta = [
        f"- **Table**: `{d.table_name}`  (proposed: `{d.sql_table}`)",
        f"- **Kind**: {KIND_LABEL[d.kind]}",
        f"- **Owned by**: {d.app} / {d.module}",
    ]
    if d.autoname:
        meta.append(f"- **Naming**: `{d.autoname}`" + (f"  ({d.naming_rule})" if d.naming_rule else ""))
    elif d.naming_rule:
        meta.append(f"- **Naming**: {d.naming_rule}")
    if d.title_field:
        meta.append(f"- **Title field**: `{d.title_field}`")
    if d.is_submittable:
        meta.append("- **Submittable**: yes — draft/submitted/cancelled lifecycle, immutable after submit")
    if d.is_tree:
        meta.append("- **Tree**: yes — nested set (`lft`, `rgt`, `old_parent`)")
    if d.description:
        meta.append(f"- **Description**: {_esc(d.description)}")
    if d.search_fields:
        meta.append(f"- **Search fields**: `{d.search_fields}`")
    if d.unique_constraints:
        for uc in d.unique_constraints:
            meta.append("- **Unique constraint**: (" + ", ".join(f"`{c}`" for c in uc) + ")")
    if d.istable:
        parents = reg.parents_of(d.name)
        if parents:
            meta.append(
                "- **Embedded in**: "
                + ", ".join(f"`{p}`.`{f}`" for p, f in parents[:12])
                + (f" … (+{len(parents) - 12} more)" if len(parents) > 12 else "")
            )
    L += meta + [""]

    # columns
    L += ["| # | Column | Type | Postgres | Constraints / notes | Reference |", "|--:|---|---|---|---|---|"]
    for i, f in enumerate(d.columns, 1):
        L.append(
            f"| {i} | `{f.fieldname}` | {f.fieldtype} | `{f.sql_type('postgres')}` | "
            f"{_flags(f)} | {_target(f, reg)} |"
        )
    L.append("")

    if d.child_tables:
        L += ["**Child tables (1-N):**", ""]
        for fn, ch, ft in d.child_tables:
            tag = "multi-select" if ft == "Table MultiSelect" else "line items"
            L.append(f"- `{fn}` → `{ch}` ({tag})")
        L.append("")

    if d.dynamic_links:
        L += ["**Polymorphic references:**", ""]
        for fn, sel in d.dynamic_links:
            L.append(f"- `{fn}` — target DocType read from `{sel}`")
        L.append("")

    if not d.istable:
        inb = reg.inbound_links(d.name)
        if inb:
            L += [
                f"**Referenced by ({len(inb)}):** "
                + ", ".join(f"`{s}`.`{fn}`" for s, fn in inb[:15])
                + (f" … (+{len(inb) - 15} more)" if len(inb) > 15 else ""),
                "",
            ]
    return L
