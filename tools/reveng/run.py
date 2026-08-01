#!/usr/bin/env python3
"""
Reverse-engineer ERPNext into a schema catalog + study docs.

Usage:
    python3 run.py --app /projects/sandbox/erpnext/erpnext --out /projects/sandbox/erp
"""

from __future__ import annotations

import argparse
import os

import catalog
import ddl
import erd
import flows
import patterns
import render
from frappe_schema import Registry

DEEP_DIVE_MODULES = ["Accounts", "Selling", "Buying", "Stock", "Subcontracting", "Setup"]
FLOW_MODULES = ["Accounts", "Selling", "Buying", "Stock", "Subcontracting", "Manufacturing", "Assets"]

MODULE_NOTES = {
    "Accounts": (
        "The accounting core: chart of accounts, fiscal calendar, the general ledger and the two\n"
        "subledgers (payment ledger, accounting dimensions). Every stock/trade document ultimately\n"
        "posts into `GL Entry`. `Account` and `Cost Center` are nested-set trees; `GL Entry` is\n"
        "append-only in practice (cancellations post reversing rows and flip `is_cancelled`)."
    ),
    "Selling": (
        "Order-to-cash masters and documents: `Customer`, `Quotation`, `Sales Order` plus pricing,\n"
        "partner/territory and target structures. Line items live in child tables shared with\n"
        "Stock/Accounts documents (e.g. `Sales Taxes and Charges`, `Packed Item`)."
    ),
    "Buying": (
        "Procure-to-pay masters and documents: `Supplier`, `Request for Quotation`,\n"
        "`Supplier Quotation`, `Purchase Order`. Mirrors Selling almost field for field — a strong\n"
        "hint that our own design should share one abstraction for both trade directions."
    ),
    "Stock": (
        "Inventory truth: `Item` and its variants/UOMs, `Warehouse` (tree), `Bin` (per item+warehouse\n"
        "running balances), `Stock Ledger Entry` (append-only movement log with moving-average /\n"
        "FIFO valuation state), plus `Batch`/`Serial No` traceability and the documents that move\n"
        "stock (`Stock Entry`, `Delivery Note`, `Purchase Receipt`, `Stock Reconciliation`)."
    ),
    "Subcontracting": (
        "Toll/contract manufacturing: `Subcontracting Order` and `Subcontracting Receipt` move raw\n"
        "material to a supplier warehouse and receive finished goods, consuming the supplied items\n"
        "and rolling their value into the finished item cost."
    ),
    "Setup": (
        "Shared masters that the trade and accounting modules depend on but do not own:\n"
        "`Company` (the tenant/legal entity boundary of the whole ledger), `UOM` +\n"
        "`UOM Conversion Factor`, the classification trees (`Item Group`, `Customer Group`,\n"
        "`Supplier Group`, `Territory`, `Sales Person`), `Currency Exchange`, `Incoterm`,\n"
        "`Terms and Conditions` and `Party Type`. Included here because no trade table can be\n"
        "designed without them."
    ),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, help="path to the erpnext python package root")
    ap.add_argument("--out", required=True, help="output repo root")
    args = ap.parse_args()

    schema_dir = os.path.join(args.out, "schema")
    docs_dir = os.path.join(args.out, "docs", "reveng")
    mod_dir = os.path.join(docs_dir, "modules")
    ddl_dir = os.path.join(args.out, "schema", "ddl")
    for p in (schema_dir, docs_dir, mod_dir, ddl_dir):
        os.makedirs(p, exist_ok=True)

    reg = Registry.from_app(args.app)
    print(f"parsed {len(reg.doctypes)} doctypes across {len(reg.modules())} modules")

    # 1. machine readable catalog
    jp = catalog.write_json(reg, schema_dir)
    cps = catalog.write_csvs(reg, schema_dir)
    print("wrote", jp, *cps, sep="\n  ")

    # 2. narrative catalog
    _w(os.path.join(docs_dir, "00-overview.md"), render.overview(reg))
    _w(os.path.join(docs_dir, "01-all-tables.md"), render.full_catalog(reg))

    # 3. deep dives + per module ERD
    for m in DEEP_DIVE_MODULES:
        body = render.module_deep_dive(reg, m, MODULE_NOTES)
        _w(os.path.join(mod_dir, f"{m.lower()}.md"), body)
        _w(os.path.join(mod_dir, f"{m.lower()}-erd.md"),
           f"# {m}: relationship diagrams\n\n" + erd.module_relationship_graph(reg, m))

    # 4. cross-module core ERD
    core = ["# Core entity graph (accounts + trade + inventory)", ""]
    core.append(erd.mermaid_er(reg, erd.CORE_MASTERS, "Core masters", include_child_tables=False))
    core.append(
        erd.mermaid_er(
            reg,
            ["Sales Order", "Sales Invoice", "Delivery Note", "Customer", "Item", "Warehouse"],
            "Order to cash",
        )
    )
    core.append(
        erd.mermaid_er(
            reg,
            ["Purchase Order", "Purchase Receipt", "Purchase Invoice", "Supplier", "Item", "Warehouse"],
            "Procure to pay",
        )
    )
    core.append(
        erd.mermaid_er(
            reg,
            ["Stock Entry", "Stock Ledger Entry", "Bin", "Batch", "Serial No", "Item", "Warehouse"],
            "Inventory movement + balances",
        )
    )
    core.append(
        erd.mermaid_er(
            reg,
            ["Journal Entry", "GL Entry", "Payment Entry", "Payment Ledger Entry", "Account", "Cost Center"],
            "Ledgers",
        )
    )
    _w(os.path.join(docs_dir, "02-core-erd.md"), "\n".join(core))

    # 4b. auto-derived document flow graph
    _w(os.path.join(docs_dir, "03-document-flows.md"), flows.render(reg, FLOW_MODULES))

    # 4c. cross-cutting patterns
    _w(os.path.join(docs_dir, "04-patterns.md"), patterns.render(reg, DEEP_DIVE_MODULES))

    # 5. DDL
    for m in DEEP_DIVE_MODULES:
        _w(os.path.join(ddl_dir, f"{m.lower()}_asis.sql"), ddl.emit_asis(reg, m))
    tables_sql, fk_sql, stats = ddl.emit_clean_bundle(reg, DEEP_DIVE_MODULES)
    _w(os.path.join(ddl_dir, "clean_01_tables.sql"), tables_sql)
    _w(os.path.join(ddl_dir, "clean_02_constraints.sql"), fk_sql)
    print("clean bundle stats:", stats)

    print("done")


def _w(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text if text.endswith("\n") else text + "\n")
    print("  wrote", path, f"({len(text.splitlines())} lines)")


if __name__ == "__main__":
    main()
