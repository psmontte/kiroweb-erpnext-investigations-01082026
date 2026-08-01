"""
Settles the "how many tables does ERPNext have?" question precisely.

The answer depends on what you count, and the difference matters when we size our own
schema. A bench with the standard app set defines ~1,000 DocTypes; not all of them
become tables.
"""

from __future__ import annotations

from frappe_schema import Registry

# Framework-managed tables that exist in every site but are not defined as DocTypes.
NON_DOCTYPE_TABLES = [
    ("tabSingles", "key/value store holding every `issingle` DocType's fields"),
    ("tabSeries", "naming-series counters (`current` per prefix)"),
    ("tabDefaultValue", "per-user / per-parent default values"),
    ("tabSessions", "active sessions"),
    ("__Auth", "password and secret hashes, kept out of the doctype tables"),
    ("__global_search", "full-text search index across doctypes"),
    ("__UserSettings", "per-user list view / filter state"),
]


def render(reg: Registry) -> str:
    total = len(reg.doctypes)
    singles = sum(1 for d in reg.doctypes if d.issingle)
    virtual = sum(1 for d in reg.doctypes if d.is_virtual)
    # a DocType can be both single and virtual, so count the complement directly
    physical = sum(1 for d in reg.doctypes if not d.issingle and not d.is_virtual)
    child = sum(1 for d in reg.doctypes if d.istable)
    submittable = sum(1 for d in reg.doctypes if d.is_submittable)
    trees = sum(1 for d in reg.doctypes if d.is_tree)
    cols = sum(len(d.columns) for d in reg.doctypes)

    L = [
        "# How many tables? Reconciling the count",
        "",
        "Counting only the `erpnext` app gives 532 DocTypes. A working ERPNext site is",
        "`frappe` + `erpnext` + the apps that ship with it, and that is where the ~1,000",
        "figure comes from. Both numbers are correct; they answer different questions.",
        "",
        "## Per app",
        "",
        "| App | Role | DocTypes | Physical tables | Child tables | Singles (no table) | Virtual (no table) | Columns |",
        "|---|---|--:|--:|--:|--:|--:|--:|",
    ]
    roles = {
        "frappe": "the framework itself: users, roles, files, comments, workflow, print, email, Address/Contact/Currency masters",
        "erpnext": "accounting, trade, inventory, manufacturing, assets, projects, support",
        "payments": "payment gateway integrations",
        "hrms": "HR and payroll (separate app since v14)",
        "webshop": "storefront (split out of erpnext in v15)",
    }
    for a in reg.apps():
        ds = [d for d in reg.doctypes if d.app == a]
        L.append(
            "| `{}` | {} | {} | {} | {} | {} | {} | {} |".format(
                a,
                roles.get(a, ""),
                len(ds),
                sum(1 for d in ds if not d.issingle and not d.is_virtual),
                sum(1 for d in ds if d.istable),
                sum(1 for d in ds if d.issingle),
                sum(1 for d in ds if d.is_virtual),
                sum(len(d.columns) for d in ds),
            )
        )
    L += [
        "| **TOTAL** | | **{}** | **{}** | **{}** | **{}** | **{}** | **{}** |".format(
            total, physical, child, singles, virtual, cols
        ),
        "",
        "## So which number is 'the' number?",
        "",
        f"- **{total} DocTypes** are defined across the standard app set. This is the ~1,000 count.",
        f"- **{physical} of them get a physical `tab<Name>` table**. The rest are:",
        f"  - **{singles} singles** — stored as rows in the shared `tabSingles` key/value table,",
        f"  - **{virtual} virtual** — backed by code or an external service, no storage at all",
        f"    ({singles + virtual - (total - physical)} DocTypes are both single and virtual, hence"
        f" {total} - {physical} = {total - physical}, not {singles + virtual}).",
        f"- **{child} of the {physical} tables are child tables** — they only ever hold line items",
        "  belonging to a parent document. They are real tables, but they are not entities.",
        f"- So the *entity* count is roughly **{physical - child}**, and that is the number that",
        "  matters when we design our own model.",
        "",
        "Add the framework tables that are not DocTypes at all:",
        "",
        "| Table | Purpose |",
        "|---|---|",
    ]
    for t, why in NON_DOCTYPE_TABLES:
        L.append(f"| `{t}` | {why} |")
    L += [
        "",
        f"A freshly installed bench with these five apps therefore lands at roughly",
        f"**{physical + len(NON_DOCTYPE_TABLES)} tables**, before any custom DocType, and every",
        "`Custom Field` a user adds widens an existing table rather than creating a new one.",
        "",
        "## Shape of the whole thing",
        "",
        "| Metric | Count |",
        "|---|--:|",
        f"| DocTypes | {total} |",
        f"| Physical tables | {physical} |",
        f"| Entity tables (excluding child tables) | {physical - child} |",
        f"| Child (line-item) tables | {child} |",
        f"| Submittable documents (draft/submit/cancel lifecycle) | {submittable} |",
        f"| Tree masters (nested set) | {trees} |",
        f"| Total columns defined | {cols} |",
        f"| Link (FK-by-name) columns | {sum(len(d.links) for d in reg.doctypes)} |",
        f"| Child-table relations | {sum(len(d.child_tables) for d in reg.doctypes)} |",
        f"| Polymorphic (Dynamic Link) columns | {sum(len(d.dynamic_links) for d in reg.doctypes)} |",
        "",
        "## What this means for our build",
        "",
        "We are not competing with 1,000 tables. Stripping out HR, payroll, webshop, the",
        "framework's own plumbing (users, files, comments, workflow, print formats, email),",
        "and the modules outside our scope, the accounting + trade + inventory core we studied",
        "is what actually matters — and even that is only worth building in the phases listed in",
        "`06-findings-and-target-schema.md`. Phase 0 to 2 is under 30 tables and covers the",
        "general ledger and inventory valuation, which is the part that is genuinely hard.",
        "",
    ]
    return "\n".join(L)
