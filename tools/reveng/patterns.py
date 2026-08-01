"""
Cross-cutting design patterns extracted from the schema.

Every section here is derived from the DocType JSON, so it tells us what ERPNext
*actually* does rather than what its docs claim. These are the patterns we must
consciously accept or replace in our own schema.
"""

from __future__ import annotations

import collections

from frappe_schema import Registry


def render(reg: Registry, modules: list[str]) -> str:
    inscope = [d for d in reg.doctypes if d.module in set(modules)]
    L = ["# Cross-cutting schema patterns (auto-derived)", "", f"Scope: {', '.join(modules)}.", ""]

    # ---------------------------------------------------------------- 1. shared child tables
    shared = []
    for d in reg.doctypes:
        if not d.istable:
            continue
        parents = reg.parents_of(d.name)
        if len(parents) > 1:
            shared.append((d.name, parents))
    shared.sort(key=lambda x: -len(x[1]))
    L += [
        "## 1. Child tables shared by several parents",
        "",
        "ERPNext reuses one physical child table across many parent DocTypes and tells them",
        "apart with `parenttype`. This is why the framework cannot use real foreign keys.",
        f"{len(shared)} child tables have more than one parent.",
        "",
        "| Child table | Parents | Used by |",
        "|---|--:|---|",
    ]
    for name, parents in shared[:40]:
        used = ", ".join(f"`{p}`.`{f}`" for p, f in parents[:8])
        if len(parents) > 8:
            used += f" … (+{len(parents) - 8})"
        L.append(f"| `{name}` | {len(parents)} | {used} |")
    L += [
        "",
        "**Decision for our schema:** one table per (parent, field) with a real FK, or a single",
        "table plus a discriminator only where the rows are genuinely interchangeable.",
        "",
    ]

    # ---------------------------------------------------------------- 2. polymorphic pairs
    pairs = collections.Counter()
    examples: dict[tuple[str, str], list[str]] = collections.defaultdict(list)
    for d in reg.doctypes:
        for fn, sel in d.dynamic_links:
            pairs[(sel, fn)] += 1
            examples[(sel, fn)].append(d.name)
    L += [
        "## 2. Polymorphic (`Dynamic Link`) column pairs",
        "",
        "A `Dynamic Link` column holds the target row's key while a sibling column holds the",
        "target *table* name. This is how ERPNext models 'a party is a Customer or a Supplier'",
        "and 'this ledger row came from some voucher'.",
        "",
        "| Discriminator column | Value column | Occurrences | Example tables |",
        "|---|---|--:|---|",
    ]
    for (sel, fn), n in pairs.most_common(30):
        ex = ", ".join(f"`{x}`" for x in sorted(examples[(sel, fn)])[:5])
        L.append(f"| `{sel}` | `{fn}` | {n} | {ex} |")
    L += [
        "",
        "**Decision for our schema:** the `party_type`/`party` pair is a genuine supertype",
        "(introduce a `party` table that `customer` and `supplier` extend). The",
        "`voucher_type`/`voucher_no` pair on ledger rows is an audit back-pointer; keep it as a",
        "(table_name, row_id) pair but *also* store a typed FK to the specific document type.",
        "",
    ]

    # ---------------------------------------------------------------- 3. denormalisation
    denorm = sorted(
        ((d.name, [f.fieldname for f in d.columns if f.fetch_from]) for d in inscope),
        key=lambda x: -len(x[1]),
    )
    total = sum(len(v) for _n, v in denorm)
    L += [
        "## 3. Denormalised (`fetch_from`) columns",
        "",
        f"{total} columns in scope are copies of a value owned by another table, snapshotted at",
        "save time. Some are deliberate history (a price at the time of sale); many are pure",
        "read convenience.",
        "",
        "| Table | Copied columns | Examples |",
        "|---|--:|---|",
    ]
    for name, cols in denorm[:25]:
        if not cols:
            continue
        L.append(f"| `{name}` | {len(cols)} | " + ", ".join(f"`{c}`" for c in cols[:8]) + " |")
    L += [
        "",
        "**Decision for our schema:** keep the snapshot only where the value must survive later",
        "master edits (rates, tax %, addresses printed on a document). Everything else becomes a",
        "join or a view.",
        "",
    ]

    # ---------------------------------------------------------------- 4. naming
    L += [
        "## 4. Identifier / naming strategies in use",
        "",
        "| Strategy | Tables | Example |",
        "|---|--:|---|",
    ]
    buckets: dict[str, list[str]] = collections.defaultdict(list)
    for d in inscope:
        if d.istable:
            buckets["child table (framework hash)"].append(d.name)
        elif d.autoname.startswith("naming_series"):
            buckets["naming series column"].append(d.name)
        elif d.autoname.startswith("field:"):
            buckets["value of one field"].append(d.name)
        elif d.autoname.startswith("format:"):
            buckets["format string"].append(d.name)
        elif d.autoname == "hash":
            buckets["random hash"].append(d.name)
        elif d.autoname == "autoincrement":
            buckets["autoincrement"].append(d.name)
        elif d.autoname == "Prompt":
            buckets["user supplied"].append(d.name)
        elif d.autoname:
            buckets["inline series expression"].append(d.name)
        else:
            buckets["set by controller code"].append(d.name)
    for k, v in sorted(buckets.items(), key=lambda x: -len(x[1])):
        L.append(f"| {k} | {len(v)} | " + ", ".join(f"`{x}`" for x in sorted(v)[:6]) + " |")
    L += [
        "",
        "Series expressions found (these encode fiscal period into the key, so the key is not",
        "stable across companies or years):",
        "",
    ]
    series = sorted({d.autoname for d in inscope if d.autoname and "." in d.autoname})
    for s in series[:40]:
        L.append(f"- `{s}`")
    L += [
        "",
        "**Decision for our schema:** surrogate `bigint` PK everywhere; the human document number",
        "becomes `doc_no` with a `UNIQUE (company_id, doc_type, doc_no)` constraint and a proper",
        "sequence table so numbering gaps and concurrency are explicit.",
        "",
    ]

    # ---------------------------------------------------------------- 5. money columns
    money = collections.Counter()
    for d in inscope:
        for f in d.columns:
            if f.fieldtype == "Currency":
                money[d.name] += 1
    L += [
        "## 5. Multi-currency column triplets",
        "",
        "ERPNext stores most amounts three times: transaction currency, company base currency",
        "(`base_*`) and sometimes account currency. `numeric(21,9)` throughout.",
        "",
        "| Table | Currency columns | of which `base_*` |",
        "|---|--:|--:|",
    ]
    for name, n in money.most_common(20):
        d = reg.get(name)
        nb = sum(1 for f in d.columns if f.fieldtype == "Currency" and f.fieldname.startswith("base_"))
        L.append(f"| `{name}` | {n} | {nb} |")
    L += [
        "",
        "**Decision for our schema:** store amount + currency + the exchange rate used, and derive",
        "base amounts in generated columns or views so the two can never drift.",
        "",
    ]

    # ---------------------------------------------------------------- 6. tree masters
    trees = [d for d in reg.doctypes if d.is_tree]
    L += [
        "## 6. Hierarchies (nested sets)",
        "",
        f"{len(trees)} tree masters app-wide, each carrying `lft`, `rgt`, `old_parent` plus a",
        "self-referencing `parent_*` link and an `is_group` flag.",
        "",
        "| Table | Module | Parent column |",
        "|---|---|---|",
    ]
    for d in sorted(trees, key=lambda x: (x.module, x.name)):
        pcol = next((fn for fn, t in d.links if t == d.name), "?")
        L.append(f"| `{d.name}` | {d.module} | `{pcol}` |")
    L += [
        "",
        "**Decision for our schema:** `parent_id` FK + recursive CTEs (or a closure table for",
        "read-heavy reporting). Nested sets make every insert lock the whole tree.",
        "",
    ]
    return "\n".join(L)
