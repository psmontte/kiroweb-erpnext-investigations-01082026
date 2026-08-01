"""Mermaid ER / relationship diagram generation."""

from __future__ import annotations

from frappe_schema import Registry, slug

# Entities that matter for the core trade + accounting graph.
CORE_MASTERS = [
    "Company",
    "Account",
    "Cost Center",
    "Fiscal Year",
    "Currency Exchange",
    "Customer",
    "Supplier",
    "Item",
    "Item Group",
    "UOM Conversion Detail",
    "Warehouse",
    "Batch",
    "Serial No",
    "Price List",
    "Item Price",
    "Payment Terms Template",
    "Tax Category",
    "Sales Taxes and Charges Template",
    "Purchase Taxes and Charges Template",
]

CORE_TRANSACTIONS = [
    "Quotation",
    "Sales Order",
    "Delivery Note",
    "Sales Invoice",
    "Supplier Quotation",
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
    "Material Request",
    "Stock Entry",
    "Stock Reconciliation",
    "Journal Entry",
    "Payment Entry",
    "Subcontracting Order",
    "Subcontracting Receipt",
]

LEDGERS = ["GL Entry", "Stock Ledger Entry", "Payment Ledger Entry", "Serial and Batch Bundle"]


def _node(name: str) -> str:
    return slug(name).upper()


def mermaid_er(reg: Registry, doctypes: list[str], title: str, include_child_tables: bool = True) -> str:
    """Mermaid erDiagram with key attributes for the chosen doctypes."""
    want = [n for n in doctypes if reg.get(n)]
    wantset = set(want)
    children: set[str] = set()
    if include_child_tables:
        for n in want:
            d = reg.get(n)
            for _fn, ch, _ft in d.child_tables:
                if reg.is_internal(ch):
                    children.add(ch)
    universe = wantset | children

    L = [f"### {title}", "", "```mermaid", "erDiagram"]
    for n in sorted(universe):
        d = reg.get(n)
        L.append(f"  {_node(n)} {{")
        L.append("    varchar name PK")
        shown = 0
        for f in d.columns:
            if shown >= 10:
                break
            if not (f.reqd or f.is_link or f.in_list_view):
                continue
            t = f.sql_type("postgres").split("(")[0]
            tag = " FK" if f.is_link else ""
            L.append(f"    {t} {f.fieldname}{tag}")
            shown += 1
        L.append("  }")
    for n in sorted(universe):
        d = reg.get(n)
        for fn, ch, _ft in d.child_tables:
            if ch in universe:
                L.append(f"  {_node(n)} ||--o{{ {_node(ch)} : {slug(fn)}")
        for fn, target in d.links:
            if target in universe and target != n:
                L.append(f"  {_node(target)} ||--o{{ {_node(n)} : {slug(fn)}")
    L += ["```", ""]
    return "\n".join(L)


def mermaid_flow(reg: Registry, title: str, edges: list[tuple[str, str, str]]) -> str:
    L = [f"### {title}", "", "```mermaid", "flowchart LR"]
    seen = set()
    for a, b, _lbl in edges:
        for n in (a, b):
            if n not in seen:
                seen.add(n)
                L.append(f'  {_node(n)}["{n}"]')
    for a, b, lbl in edges:
        L.append(f"  {_node(a)} -->|{lbl}| {_node(b)}")
    L += ["```", ""]
    return "\n".join(L)


def module_relationship_graph(reg: Registry, module: str, max_nodes: int = 45, hops: bool = True) -> str:
    """Link graph of a module's entities, plus the external masters they depend on.

    Child tables are collapsed into their parent so the diagram shows business
    entities rather than storage tables; edges from a child table are attributed to
    the parent document.
    """
    own = [d for d in reg.doctypes if d.module == module and not d.istable and not d.issingle]
    scored = sorted(own, key=lambda d: -(len(reg.inbound_links(d.name)) + len(d.links)))
    keep = [d.name for d in scored[:max_nodes]]
    keepset = set(keep)

    # collapse child tables onto their parent, then collect edges
    edges: set[tuple[str, str]] = set()
    external: set[str] = set()

    def add_links(source_name: str, d) -> None:
        for _fn, t in d.links:
            if t == source_name or not reg.is_internal(t):
                continue
            tgt = reg.get(t)
            if tgt.istable:
                continue
            if t in keepset:
                edges.add((source_name, t))
            elif hops:
                external.add(t)
                edges.add((source_name, t))

    for name in keep:
        d = reg.get(name)
        add_links(name, d)
        for _fn, ch, _ft in d.child_tables:
            cd = reg.get(ch)
            if cd:
                add_links(name, cd)

    L = [
        f"### {module}: entity dependency graph",
        "",
        "Child tables are collapsed into their parent document. Rounded nodes are external",
        "masters owned by other modules. `[[ ]]` = submittable transaction.",
        "",
        "```mermaid",
        "flowchart LR",
        f'  subgraph {slug(module).upper()}["{module}"]',
    ]
    for n in sorted(keepset):
        d = reg.get(n)
        L.append(f'    {_node(n)}[["{n}"]]' if d.is_submittable else f'    {_node(n)}["{n}"]')
    L.append("  end")
    for n in sorted(external):
        d = reg.get(n)
        L.append(f'  {_node(n)}("{n}<br/><i>{d.module}</i>")')
    for a, b in sorted(edges):
        L.append(f"  {_node(a)} --> {_node(b)}")
    L += ["```", ""]
    return "\n".join(L)
