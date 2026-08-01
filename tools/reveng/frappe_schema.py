"""
Frappe/ERPNext DocType -> relational schema reverse-engineering model.

A Frappe "DocType" is a JSON schema file that the framework materialises into a
single physical table named `tab<DocType Name>`. This module parses those JSON
files into plain dataclasses so the rest of the toolkit (catalog, docs, ERD, DDL)
can work with a normalised, framework-free representation.

Type maps and standard-column definitions below are transcribed from frappe core:
  frappe/database/mariadb/database.py  (type_map)
  frappe/database/postgres/database.py (type_map)
  frappe/database/mariadb/schema.py    (create table skeleton)
  frappe/model/__init__.py             (default_fields, no_value_fields, ...)
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from functools import cached_property

VARCHAR_LEN = 140

# Fieldtypes that never produce a physical column.
NO_VALUE_FIELDTYPES = {
    "Section Break",
    "Column Break",
    "Tab Break",
    "Attachment Gallery",
    "HTML",
    "Table",
    "Table MultiSelect",
    "Button",
    "Image",
    "Fold",
    "Heading",
}

# Layout-only fieldtypes (subset of the above) - pure presentation, no relation either.
LAYOUT_FIELDTYPES = {
    "Section Break",
    "Column Break",
    "Tab Break",
    "Attachment Gallery",
    "HTML",
    "Button",
    "Image",
    "Fold",
    "Heading",
}

# Fieldtypes that embed a one-to-many child table.
TABLE_FIELDTYPES = {"Table", "Table MultiSelect"}

NUMERIC_FIELDTYPES = {"Currency", "Int", "Long Int", "Float", "Percent", "Check"}

# Columns frappe adds to every table.
DEFAULT_COLUMNS = ("name", "creation", "modified", "modified_by", "owner", "docstatus", "idx")
# Extra columns added only to child tables.
CHILD_COLUMNS = ("parent", "parentfield", "parenttype")
# Columns that may be added lazily by the framework.
OPTIONAL_COLUMNS = ("_user_tags", "_comments", "_assign", "_liked_by", "_seen")

MARIADB_TYPE_MAP = {
    "Currency": "decimal(21,9)",
    "Int": "int(11)",
    "Long Int": "bigint(20)",
    "Float": "decimal(21,9)",
    "Percent": "decimal(21,9)",
    "Check": "tinyint(4)",
    "Small Text": "text",
    "Long Text": "longtext",
    "Code": "longtext",
    "Text Editor": "longtext",
    "Markdown Editor": "longtext",
    "HTML Editor": "longtext",
    "Date": "date",
    "Datetime": "datetime(6)",
    "Time": "time(6)",
    "Text": "text",
    "Data": f"varchar({VARCHAR_LEN})",
    "Link": f"varchar({VARCHAR_LEN})",
    "Dynamic Link": f"varchar({VARCHAR_LEN})",
    "Password": "text",
    "Select": f"varchar({VARCHAR_LEN})",
    "Rating": "decimal(3,2)",
    "Read Only": f"varchar({VARCHAR_LEN})",
    "Attach": "text",
    "Attach Image": "text",
    "Signature": "longtext",
    "Color": f"varchar({VARCHAR_LEN})",
    "Barcode": "longtext",
    "Geolocation": "longtext",
    "Duration": "decimal(21,9)",
    "Icon": f"varchar({VARCHAR_LEN})",
    "Phone": f"varchar({VARCHAR_LEN})",
    "Autocomplete": f"varchar({VARCHAR_LEN})",
    "JSON": "json",
}

POSTGRES_TYPE_MAP = {
    "Currency": "numeric(21,9)",
    "Int": "integer",
    "Long Int": "bigint",
    "Float": "numeric(21,9)",
    "Percent": "numeric(21,9)",
    "Check": "smallint",
    "Small Text": "text",
    "Long Text": "text",
    "Code": "text",
    "Text Editor": "text",
    "Markdown Editor": "text",
    "HTML Editor": "text",
    "Date": "date",
    "Datetime": "timestamp",
    "Time": "time(6)",
    "Text": "text",
    "Data": f"varchar({VARCHAR_LEN})",
    "Link": f"varchar({VARCHAR_LEN})",
    "Dynamic Link": f"varchar({VARCHAR_LEN})",
    "Password": "text",
    "Select": f"varchar({VARCHAR_LEN})",
    "Rating": "numeric(3,2)",
    "Read Only": f"varchar({VARCHAR_LEN})",
    "Attach": "text",
    "Attach Image": "text",
    "Signature": "text",
    "Color": f"varchar({VARCHAR_LEN})",
    "Barcode": "text",
    "Geolocation": "text",
    "Duration": "numeric(21,9)",
    "Icon": f"varchar({VARCHAR_LEN})",
    "Phone": f"varchar({VARCHAR_LEN})",
    "Autocomplete": f"varchar({VARCHAR_LEN})",
    "JSON": "jsonb",
}

DOCSTATUS = {0: "Draft", 1: "Submitted", 2: "Cancelled"}


@dataclass
class Field:
    fieldname: str
    fieldtype: str
    label: str = ""
    options: str = ""
    reqd: bool = False
    unique: bool = False
    search_index: bool = False
    in_list_view: bool = False
    read_only: bool = False
    hidden: bool = False
    no_copy: bool = False
    allow_on_submit: bool = False
    is_virtual: bool = False
    set_only_once: bool = False
    precision: str = ""
    default: str = ""
    fetch_from: str = ""
    depends_on: str = ""
    description: str = ""
    non_negative: bool = False

    @classmethod
    def from_json(cls, d: dict) -> "Field":
        return cls(
            fieldname=d.get("fieldname") or "",
            fieldtype=d.get("fieldtype") or "",
            label=d.get("label") or "",
            options=(d.get("options") or "").strip(),
            reqd=bool(d.get("reqd")),
            unique=bool(d.get("unique")),
            search_index=bool(d.get("search_index")),
            in_list_view=bool(d.get("in_list_view")),
            read_only=bool(d.get("read_only")),
            hidden=bool(d.get("hidden")),
            no_copy=bool(d.get("no_copy")),
            allow_on_submit=bool(d.get("allow_on_submit")),
            is_virtual=bool(d.get("is_virtual")),
            set_only_once=bool(d.get("set_only_once")),
            precision=str(d.get("precision") or ""),
            default=str(d.get("default") if d.get("default") is not None else ""),
            fetch_from=d.get("fetch_from") or "",
            depends_on=d.get("depends_on") or "",
            description=(d.get("description") or "").strip(),
            non_negative=bool(d.get("non_negative")),
        )

    # -- classification helpers ------------------------------------------------
    @property
    def is_layout(self) -> bool:
        return self.fieldtype in LAYOUT_FIELDTYPES

    @property
    def is_child_table(self) -> bool:
        return self.fieldtype in TABLE_FIELDTYPES

    @property
    def has_column(self) -> bool:
        return (
            self.fieldtype not in NO_VALUE_FIELDTYPES
            and not self.is_virtual
            and bool(self.fieldname)
        )

    @property
    def is_link(self) -> bool:
        return self.fieldtype == "Link" and bool(self.options)

    @property
    def is_dynamic_link(self) -> bool:
        return self.fieldtype == "Dynamic Link"

    @property
    def select_options(self) -> list[str]:
        if self.fieldtype != "Select" or not self.options:
            return []
        return [o for o in (x.strip() for x in self.options.split("\n")) if o]

    def sql_type(self, dialect: str = "postgres") -> str:
        tmap = POSTGRES_TYPE_MAP if dialect == "postgres" else MARIADB_TYPE_MAP
        base = tmap.get(self.fieldtype)
        if base is None:
            return tmap["Data"]
        # honour custom precision on decimals
        if self.precision and self.fieldtype in ("Currency", "Float", "Percent"):
            try:
                p = int(self.precision)
                if 0 < p <= 9:
                    return f"numeric(21,{p})" if dialect == "postgres" else f"decimal(21,{p})"
            except ValueError:
                pass
        return base


@dataclass
class DocType:
    name: str
    module: str
    path: str
    app: str = ""
    istable: bool = False
    issingle: bool = False
    is_submittable: bool = False
    is_tree: bool = False
    is_virtual: bool = False
    autoname: str = ""
    naming_rule: str = ""
    title_field: str = ""
    sort_field: str = "creation"
    sort_order: str = "DESC"
    engine: str = "InnoDB"
    document_type: str = ""
    description: str = ""
    track_changes: bool = False
    allow_rename: bool = False
    search_fields: str = ""
    unique_constraints: list[list[str]] = field(default_factory=list)
    fields: list[Field] = field(default_factory=list)
    doctype_links: list[dict] = field(default_factory=list)
    field_order: list[str] = field(default_factory=list)

    # -- derived ---------------------------------------------------------------
    @property
    def table_name(self) -> str:
        return f"tab{self.name}"

    @property
    def sql_table(self) -> str:
        """snake_case physical table name for our own schema."""
        return slug(self.name)

    @cached_property
    def columns(self) -> list[Field]:
        return [f for f in self.fields if f.has_column]

    @cached_property
    def child_tables(self) -> list[tuple[str, str, str]]:
        """(fieldname, child_doctype, fieldtype) for each embedded table."""
        return [
            (f.fieldname, f.options, f.fieldtype)
            for f in self.fields
            if f.is_child_table and f.options
        ]

    @cached_property
    def links(self) -> list[tuple[str, str]]:
        """(fieldname, target_doctype) for each Link field."""
        return [(f.fieldname, f.options) for f in self.fields if f.is_link]

    @cached_property
    def dynamic_links(self) -> list[tuple[str, str]]:
        """(fieldname, doctype_selector_fieldname)."""
        return [(f.fieldname, f.options) for f in self.fields if f.is_dynamic_link]

    @cached_property
    def indexed_columns(self) -> list[str]:
        return [f.fieldname for f in self.columns if f.search_index]

    @cached_property
    def unique_columns(self) -> list[str]:
        return [f.fieldname for f in self.columns if f.unique]

    @cached_property
    def mandatory_columns(self) -> list[str]:
        return [f.fieldname for f in self.columns if f.reqd]

    @property
    def kind(self) -> str:
        if self.issingle:
            return "single"          # settings row, stored in tabSingles (key/value)
        if self.istable:
            return "child"           # embedded line-item table
        if self.is_submittable:
            return "transaction"     # has docstatus lifecycle draft/submitted/cancelled
        if self.is_tree:
            return "tree-master"     # nested set (lft/rgt) hierarchy
        return "master"

    @classmethod
    def from_json(cls, path: str, raw: dict, app: str = "") -> "DocType":
        return cls(
            name=raw.get("name") or "",
            module=raw.get("module") or "",
            path=path,
            app=app,
            istable=bool(raw.get("istable")),
            issingle=bool(raw.get("issingle")),
            is_submittable=bool(raw.get("is_submittable")),
            is_tree=bool(raw.get("is_tree")),
            is_virtual=bool(raw.get("is_virtual")),
            autoname=raw.get("autoname") or "",
            naming_rule=raw.get("naming_rule") or "",
            title_field=raw.get("title_field") or "",
            sort_field=raw.get("sort_field") or "creation",
            sort_order=raw.get("sort_order") or "DESC",
            engine=raw.get("engine") or "InnoDB",
            document_type=raw.get("document_type") or "",
            description=(raw.get("description") or "").strip(),
            track_changes=bool(raw.get("track_changes")),
            allow_rename=bool(raw.get("allow_rename")),
            search_fields=raw.get("search_fields") or "",
            unique_constraints=[
                c.get("fields", []) for c in (raw.get("unique_constraints") or [])
            ],
            fields=[Field.from_json(f) for f in (raw.get("fields") or [])],
            doctype_links=list(raw.get("links") or []),
            field_order=list(raw.get("field_order") or []),
        )


class Registry:
    """All DocTypes discovered in an app, indexed by name."""

    def __init__(self, doctypes: list[DocType]):
        self.doctypes = sorted(doctypes, key=lambda d: (d.app, d.module, d.name))
        self.by_name = {d.name: d for d in self.doctypes}

    # -- discovery -------------------------------------------------------------
    @classmethod
    def from_apps(cls, apps: dict[str, str]) -> "Registry":
        """apps = {app_name: path_to_python_package_root}"""
        found: list[DocType] = []
        for app_name, root in apps.items():
            found.extend(cls._scan(root, app_name))
        return cls(found)

    @classmethod
    def from_app(cls, app_root: str, app_name: str = "") -> "Registry":
        return cls(cls._scan(app_root, app_name or os.path.basename(app_root)))

    @staticmethod
    def _scan(app_root: str, app_name: str) -> list[DocType]:
        found: list[DocType] = []
        for dirpath, _dirnames, filenames in os.walk(app_root):
            if os.path.basename(os.path.dirname(dirpath)) != "doctype":
                continue
            folder = os.path.basename(dirpath)
            candidate = os.path.join(dirpath, f"{folder}.json")
            if not os.path.exists(candidate):
                continue
            try:
                with open(candidate, encoding="utf-8") as fh:
                    raw = json.load(fh)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(raw, dict) or raw.get("doctype") != "DocType":
                continue
            found.append(
                DocType.from_json(
                    os.path.join(app_name, os.path.relpath(candidate, app_root)), raw, app_name
                )
            )
        return found

    # -- queries ---------------------------------------------------------------
    def apps(self) -> list[str]:
        return sorted({d.app for d in self.doctypes})

    def app_of(self, name: str) -> str:
        d = self.by_name.get(name)
        return d.app if d else ""

    def origin(self, name: str) -> str:
        """Human label for where a doctype comes from, e.g. 'erpnext/Stock'."""
        d = self.by_name.get(name)
        return f"{d.app}/{d.module}" if d else "unknown"

    def modules(self) -> list[str]:
        return sorted({d.module for d in self.doctypes})

    def in_modules(self, modules: list[str]) -> list[DocType]:
        want = set(modules)
        return [d for d in self.doctypes if d.module in want]

    def get(self, name: str) -> DocType | None:
        return self.by_name.get(name)

    def is_internal(self, doctype_name: str) -> bool:
        """True when the referenced DocType lives in this app (not frappe core)."""
        return doctype_name in self.by_name

    def parents_of(self, child_name: str) -> list[tuple[str, str]]:
        """(parent_doctype, fieldname) references pointing at a child table."""
        out = []
        for d in self.doctypes:
            for fieldname, child, _ft in d.child_tables:
                if child == child_name:
                    out.append((d.name, fieldname))
        return out

    def inbound_links(self, target: str) -> list[tuple[str, str]]:
        """(source_doctype, fieldname) Link fields pointing at `target`."""
        out = []
        for d in self.doctypes:
            for fieldname, opt in d.links:
                if opt == target:
                    out.append((d.name, fieldname))
        return out


def slug(name: str) -> str:
    out = []
    for ch in name:
        if ch.isalnum():
            out.append(ch.lower())
        else:
            out.append("_")
    s = "".join(out)
    while "__" in s:
        s = s.replace("__", "_")
    return s.strip("_")
