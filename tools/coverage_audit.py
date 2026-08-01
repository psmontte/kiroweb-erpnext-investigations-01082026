#!/usr/bin/env python3
"""Coverage audit: which ERPNext DocTypes have actually been read and cited in docs/.

The honest test of "did we investigate this DocType" is not "is its name mentioned"
(names like Account, Item and Budget appear everywhere) but "is its controller file
cited with a line number". This script measures that, per module, and classifies the
gaps so 'fully covered' is a verifiable claim rather than an assertion.

Usage:
    python3 tools/coverage_audit.py                      # summary + gaps
    python3 tools/coverage_audit.py --module Accounts    # one module
    python3 tools/coverage_audit.py --json               # machine readable
    python3 tools/coverage_audit.py --markdown           # emit docs/COVERAGE.md body

Exit code is 0 always; this is a reporting tool, not a gate.
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import re
import sys
from collections import defaultdict

CATALOG = "schema/catalog_tables.csv"
DOC_GLOBS = ("docs/**/*.md",)

# Modules that constitute "trade + inventory + accounts"
CORE_MODULES = ("Accounts", "Stock", "Selling", "Buying", "Subcontracting")

# DocTypes deliberately excluded from the investigation, with the reason.
# Keeping this explicit means an uncovered DocType is either a gap or a decision,
# never an oversight.
EXCLUDED: dict[str, str] = {
    # Equity / cap table — not ERP core
    "Share Transfer": "equity/cap-table, out of scope",
    "Share Type": "equity/cap-table, out of scope",
    "Shareholder": "equity/cap-table, out of scope",
    "Share Balance": "equity/cap-table, out of scope",
    # Vendor rating — no posting, no ledger impact
    "Supplier Scorecard": "vendor rating, no ledger impact",
    "Supplier Scorecard Period": "vendor rating, no ledger impact",
    "Supplier Scorecard Criteria": "vendor rating, no ledger impact",
    "Supplier Scorecard Standing": "vendor rating, no ledger impact",
    "Supplier Scorecard Variable": "vendor rating, no ledger impact",
    # Messaging / misc
    "SMS Center": "messaging utility",
    "Industry Type": "trivial lookup",
    "Sales Partner Type": "trivial lookup",
    "UOM Category": "trivial lookup",
    "Warehouse Type": "trivial lookup",
    "Bank Account Type": "trivial lookup",
    "Bank Account Subtype": "trivial lookup",
    "Account Category": "trivial lookup",
    "Dunning Type": "config for Dunning (doc 14)",
    "Quality Inspection Parameter": "deferred to Tranche B (quality)",
    "Quality Inspection Parameter Group": "deferred to Tranche B (quality)",
    "Quality Inspection Template": "deferred to Tranche B (quality)",
    "Quality Inspection": "deferred to Tranche B (quality)",
    # Debug/maintenance tooling
    "Bisect Accounting Statements": "debug tool",
    "Bisect Nodes": "debug tool",
    "Ledger Health": "diagnostic output of a scheduled job (doc 22)",
    "Ledger Health Monitor": "diagnostic config (doc 22)",
    "Quick Stock Balance": "read-only UI helper",
    "Chart of Accounts Importer": "import tool",
    "Bank Statement Import": "import tool",
    "Bank Statement Import Log": "import tool",
    "Data Import": "import tool",
}


def scrub(s: str) -> str:
    """Frappe's scrub(): 'Sales Invoice' -> 'sales_invoice'."""
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def load_catalog(path: str = CATALOG) -> list[dict]:
    if not os.path.exists(path):
        sys.exit(f"catalog not found at {path} — run tools/reveng/run.py first")
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_corpus() -> str:
    parts = []
    for pattern in DOC_GLOBS:
        for p in glob.glob(pattern, recursive=True):
            with open(p, encoding="utf-8") as fh:
                parts.append(fh.read())
    return "\n".join(parts)


def controller_cited(doctype: str, corpus: str) -> bool:
    """True if the doctype's controller file appears in the docs.

    Frappe lays controllers out as <module>/doctype/<scrubbed>/<scrubbed>.py, and we
    cite them either fully qualified or by basename, so match on the tail.
    """
    f = scrub(doctype)
    return f"/{f}.py" in corpus or f"{f}.py:" in corpus


def audit(modules: tuple[str, ...] = CORE_MODULES) -> dict:
    rows = load_catalog()
    corpus = load_corpus()

    parents = [
        r
        for r in rows
        if r["app"] == "erpnext" and r["module"] in modules and r["kind"] != "child"
    ]

    result: dict[str, dict] = {}
    for m in modules:
        result[m] = {"cited": [], "uncited_submittable": [], "uncited_other": [], "excluded": []}

    for r in parents:
        dt, m = r["doctype"], r["module"]
        submittable = r["submittable"] == "1"
        if dt in EXCLUDED:
            result[m]["excluded"].append({"doctype": dt, "reason": EXCLUDED[dt]})
        elif controller_cited(dt, corpus):
            result[m]["cited"].append({"doctype": dt, "submittable": submittable})
        elif submittable:
            result[m]["uncited_submittable"].append({"doctype": dt})
        else:
            result[m]["uncited_other"].append({"doctype": dt})

    totals = {
        k: sum(len(result[m][k]) for m in result)
        for k in ("cited", "uncited_submittable", "uncited_other", "excluded")
    }
    totals["parents"] = len(parents)
    return {"modules": result, "totals": totals}


def print_report(data: dict) -> None:
    t = data["totals"]
    print(f"Parent DocTypes in {', '.join(CORE_MODULES)}: {t['parents']}")
    print(f"  controller cited in docs/     : {t['cited']}")
    print(f"  uncited, submittable (GAPS)   : {t['uncited_submittable']}")
    print(f"  uncited, masters/config       : {t['uncited_other']}")
    print(f"  deliberately excluded         : {t['excluded']}")
    print()
    for m, d in data["modules"].items():
        gaps = d["uncited_submittable"]
        others = d["uncited_other"]
        if not gaps and not others:
            continue
        print(f"--- {m} ---")
        if gaps:
            print("  UNCITED SUBMITTABLE (posting documents):")
            for x in sorted(gaps, key=lambda r: r["doctype"]):
                print(f"    * {x['doctype']}")
        if others:
            print("  uncited masters/config:")
            for x in sorted(others, key=lambda r: r["doctype"]):
                print(f"      {x['doctype']}")
        print()


def print_markdown(data: dict) -> None:
    t = data["totals"]
    print("| Module | DocTypes | Controller cited | Uncited (submittable) | Uncited (config) | Excluded |")
    print("|---|---:|---:|---:|---:|---:|")
    for m, d in data["modules"].items():
        n = len(d["cited"]) + len(d["uncited_submittable"]) + len(d["uncited_other"]) + len(d["excluded"])
        if not n:
            continue
        print(
            f"| {m} | {n} | {len(d['cited'])} | {len(d['uncited_submittable'])} "
            f"| {len(d['uncited_other'])} | {len(d['excluded'])} |"
        )
    print(
        f"| **Total** | **{t['parents']}** | **{t['cited']}** | **{t['uncited_submittable']}** "
        f"| **{t['uncited_other']}** | **{t['excluded']}** |"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--module", action="append", help="restrict to a module (repeatable)")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--markdown", action="store_true", help="emit a markdown coverage table")
    args = ap.parse_args()

    modules = tuple(args.module) if args.module else CORE_MODULES
    data = audit(modules)

    if args.json:
        print(json.dumps(data, indent=2, sort_keys=True))
    elif args.markdown:
        print_markdown(data)
    else:
        print_report(data)


if __name__ == "__main__":
    main()
