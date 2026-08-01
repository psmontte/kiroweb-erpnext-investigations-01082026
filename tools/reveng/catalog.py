"""Emit the full machine-readable catalog of every DocType/table in the app."""

from __future__ import annotations

import csv
import json
import os

from frappe_schema import (
    CHILD_COLUMNS,
    DEFAULT_COLUMNS,
    DocType,
    Registry,
)


def doctype_to_dict(d: DocType, reg: Registry) -> dict:
    return {
        "name": d.name,
        "app": d.app,
        "module": d.module,
        "kind": d.kind,
        "frappe_table": d.table_name,
        "proposed_table": d.sql_table,
        "istable": d.istable,
        "issingle": d.issingle,
        "is_submittable": d.is_submittable,
        "is_tree": d.is_tree,
        "autoname": d.autoname,
        "naming_rule": d.naming_rule,
        "title_field": d.title_field,
        "sort": f"{d.sort_field} {d.sort_order}",
        "search_fields": d.search_fields,
        "description": d.description,
        "source": d.path,
        "counts": {
            "fields": len(d.fields),
            "columns": len(d.columns),
            "links": len(d.links),
            "dynamic_links": len(d.dynamic_links),
            "child_tables": len(d.child_tables),
            "indexes": len(d.indexed_columns),
        },
        "columns": [
            {
                "fieldname": f.fieldname,
                "label": f.label,
                "fieldtype": f.fieldtype,
                "pg_type": f.sql_type("postgres"),
                "mariadb_type": f.sql_type("mariadb"),
                "options": f.options,
                "reqd": f.reqd,
                "unique": f.unique,
                "index": f.search_index,
                "read_only": f.read_only,
                "hidden": f.hidden,
                "default": f.default,
                "fetch_from": f.fetch_from,
                "depends_on": f.depends_on,
                "description": f.description,
            }
            for f in d.columns
        ],
        "child_tables": [
            {"fieldname": fn, "child_doctype": ch, "fieldtype": ft, "internal": reg.is_internal(ch)}
            for fn, ch, ft in d.child_tables
        ],
        "links": [
            {"fieldname": fn, "target": t, "internal": reg.is_internal(t), "target_origin": reg.origin(t)}
            for fn, t in d.links
        ],
        "dynamic_links": [
            {"fieldname": fn, "doctype_selector": sel} for fn, sel in d.dynamic_links
        ],
        "unique_constraints": d.unique_constraints,
        "parents": [{"doctype": p, "fieldname": f} for p, f in reg.parents_of(d.name)]
        if d.istable
        else [],
    }


def write_json(reg: Registry, out_dir: str) -> str:
    payload = {
        "source_apps": reg.apps(),
        "standard_columns": {
            "all_tables": list(DEFAULT_COLUMNS),
            "child_tables_extra": list(CHILD_COLUMNS),
        },
        "doctype_count": len(reg.doctypes),
        "physical_table_count": sum(
            1 for d in reg.doctypes if not d.issingle and not d.is_virtual
        ),
        "counts_by_app": {
            a: {
                "doctypes": sum(1 for d in reg.doctypes if d.app == a),
                "physical_tables": sum(
                    1 for d in reg.doctypes if d.app == a and not d.issingle and not d.is_virtual
                ),
                "child_tables": sum(1 for d in reg.doctypes if d.app == a and d.istable),
                "singles": sum(1 for d in reg.doctypes if d.app == a and d.issingle),
                "virtual": sum(1 for d in reg.doctypes if d.app == a and d.is_virtual),
            }
            for a in reg.apps()
        },
        "modules": {m: sum(1 for d in reg.doctypes if d.module == m) for m in reg.modules()},
        "doctypes": [doctype_to_dict(d, reg) for d in reg.doctypes],
    }
    path = os.path.join(out_dir, "bench_doctypes.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=1)
    return path


def write_csvs(reg: Registry, out_dir: str) -> list[str]:
    paths = []

    p = os.path.join(out_dir, "catalog_tables.csv")
    with open(p, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(
            [
                "app",
                "module",
                "doctype",
                "kind",
                "frappe_table",
                "proposed_table",
                "columns",
                "links",
                "child_tables",
                "indexes",
                "submittable",
                "tree",
                "single",
                "autoname",
            ]
        )
        for d in reg.doctypes:
            w.writerow(
                [
                    d.app,
                    d.module,
                    d.name,
                    d.kind,
                    d.table_name,
                    d.sql_table,
                    len(d.columns),
                    len(d.links),
                    len(d.child_tables),
                    len(d.indexed_columns),
                    int(d.is_submittable),
                    int(d.is_tree),
                    int(d.issingle),
                    d.autoname,
                ]
            )
    paths.append(p)

    p = os.path.join(out_dir, "catalog_columns.csv")
    with open(p, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(
            [
                "app",
                "module",
                "doctype",
                "fieldname",
                "label",
                "fieldtype",
                "pg_type",
                "options",
                "reqd",
                "unique",
                "index",
                "read_only",
                "default",
                "fetch_from",
            ]
        )
        for d in reg.doctypes:
            for f in d.columns:
                w.writerow(
                    [
                        d.app,
                        d.module,
                        d.name,
                        f.fieldname,
                        f.label,
                        f.fieldtype,
                        f.sql_type("postgres"),
                        f.options.replace("\n", "|"),
                        int(f.reqd),
                        int(f.unique),
                        int(f.search_index),
                        int(f.read_only),
                        f.default,
                        f.fetch_from,
                    ]
                )
    paths.append(p)

    p = os.path.join(out_dir, "catalog_relations.csv")
    with open(p, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(
            ["app", "module", "from_doctype", "fieldname", "relation", "to_doctype", "to_origin"]
        )
        for d in reg.doctypes:
            for fn, t in d.links:
                w.writerow([d.app, d.module, d.name, fn, "link", t, reg.origin(t)])
            for fn, ch, ft in d.child_tables:
                w.writerow(
                    [
                        d.app,
                        d.module,
                        d.name,
                        fn,
                        "child_table" if ft == "Table" else "multiselect",
                        ch,
                        reg.origin(ch),
                    ]
                )
            for fn, sel in d.dynamic_links:
                w.writerow([d.app, d.module, d.name, fn, "dynamic_link", f"<{sel}>", "polymorphic"])
    paths.append(p)
    return paths
