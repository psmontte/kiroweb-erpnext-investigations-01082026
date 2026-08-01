"""
Derive the document flow graph (which transaction feeds which) directly from the
DocType definitions, instead of trusting the manual.

Heuristic: any Link field on a submittable DocType (or on one of its child tables)
that points at another submittable DocType is a document-flow edge. Fields named
`amended_from`, or pointing at the same doctype, are excluded.
"""

from __future__ import annotations

import collections

from frappe_schema import Registry, slug

SKIP_FIELDS = {"amended_from"}


def flow_edges(reg: Registry, modules: list[str] | None = None):
    """[(from_doctype, to_doctype, [(carrier_table, fieldname)...])] — 'from' feeds 'to'."""
    acc: dict[tuple[str, str], list[tuple[str, str]]] = collections.defaultdict(list)
    targets = {d.name for d in reg.doctypes if d.is_submittable}
    for d in reg.doctypes:
        if not d.is_submittable:
            continue
        if modules and d.module not in modules:
            continue
        carriers = [(d.name, d)] + [
            (ch, reg.get(ch)) for _fn, ch, _ft in d.child_tables if reg.get(ch)
        ]
        for carrier_name, cd in carriers:
            for fn, t in cd.links:
                if fn in SKIP_FIELDS or t == d.name or t not in targets:
                    continue
                acc[(t, d.name)].append((carrier_name, fn))
    return sorted((a, b, v) for (a, b), v in acc.items())


CORE_CHAIN = [
    "Material Request",
    "Request for Quotation",
    "Supplier Quotation",
    "Purchase Order",
    "Purchase Receipt",
    "Purchase Invoice",
    "Subcontracting Order",
    "Subcontracting Receipt",
    "Quotation",
    "Sales Order",
    "Pick List",
    "Delivery Note",
    "Sales Invoice",
    "Payment Entry",
    "Journal Entry",
    "Stock Entry",
    "Stock Reconciliation",
    "Landed Cost Voucher",
    "Work Order",
    "Production Plan",
]


def render(reg: Registry, modules: list[str]) -> str:
    edges = flow_edges(reg, modules)

    core = [e for e in edges if e[0] in CORE_CHAIN and e[1] in CORE_CHAIN]
    L = [
        "# Document flow graph (auto-derived)",
        "",
        "## The core chain",
        "",
        "Filtered to the documents that carry the business process end to end.",
        "",
        "```mermaid",
        "flowchart LR",
    ]
    for n in [x for x in CORE_CHAIN if any(x in (a, b) for a, b, _ in core)]:
        L.append(f'  {slug(n).upper()}["{n}"]')
    for a, b, carriers in core:
        L.append(f"  {slug(a).upper()} -->|{carriers[0][1]}| {slug(b).upper()}")
    L += ["```", "", "## Everything (all scanned modules)", ""]
    L += [
        "Every edge below is a real `Link` column found in the schema, not documentation.",
        "`A --> B` means B stores a reference back to its predecessor A (ERPNext pulls data",
        "forward and tracks fulfilment backwards through these columns).",
        "",
        f"Modules scanned: {', '.join(modules)}. {len(edges)} distinct document-to-document links.",
        "",
        "```mermaid",
        "flowchart LR",
    ]
    nodes = sorted({x for a, b, _ in edges for x in (a, b)})
    for n in nodes:
        d = reg.get(n)
        L.append(f'  {slug(n).upper()}["{n}<br/><i>{d.module}</i>"]')
    for a, b, carriers in edges:
        head = carriers[0][1]
        extra = f" +{len(carriers) - 1}" if len(carriers) > 1 else ""
        L.append(f"  {slug(a).upper()} -->|{head}{extra}| {slug(b).upper()}")
    L += ["```", "", "## Edge detail", "", "| Predecessor | Successor | Carried by (table.column) |", "|---|---|---|"]
    for a, b, carriers in edges:
        cols = ", ".join(f"`{c}`.`{f}`" for c, f in carriers[:6])
        if len(carriers) > 6:
            cols += f" … (+{len(carriers) - 6})"
        L.append(f"| `{a}` | `{b}` | {cols} |")
    L.append("")

    # fulfilment tracking columns: qty roll-ups that make the flow stateful
    L += [
        "## Fulfilment / roll-up columns that make the flow stateful",
        "",
        "These are the columns ERPNext updates on the *predecessor* when a successor is",
        "submitted. They are the reason document status is derived rather than stored only once.",
        "",
        "| Table | Column | Type |",
        "|---|---|---|",
    ]
    pat = ("delivered_qty", "received_qty", "billed_amt", "returned_qty", "ordered_qty", "per_delivered", "per_billed", "per_received", "per_ordered", "advance_paid", "requested_qty", "reserved_qty", "produced_qty", "transferred_qty", "consumed_qty", "outstanding_amount", "status")
    for d in reg.doctypes:
        if modules and d.module not in modules:
            continue
        for f in d.columns:
            if f.fieldname in pat:
                L.append(f"| `{d.name}` | `{f.fieldname}` | {f.fieldtype} |")
    L.append("")
    return "\n".join(L)
