"""
Reference DDL emitter (PostgreSQL).

Two flavours:

  * mode="asis"  – reproduces the ERPNext physical layout one table per DocType
                   (`tab<Name>`, varchar(140) business key PK, no FK constraints).
                   Useful to load a real ERPNext dump and diff behaviour.

  * clean bundle – our starting point for a greenfield schema:
                     - snake_case table names, surrogate `bigint` identity PK
                     - the ERPNext `name` kept as `doc_no varchar(140) UNIQUE`
                     - every internal `Link` becomes a real FK column `<field>_id`
                     - child tables are bound to exactly ONE parent
                       (`<parent>_<fieldname>`) with ON DELETE CASCADE + line_no
                     - NOT NULL from `reqd`, indexes from `search_index`
                     - FKs emitted separately so load order never matters
"""

from __future__ import annotations

import hashlib

from frappe_schema import DocType, Registry, slug

RESERVED = {
    "user", "order", "group", "default", "references", "check", "table", "from", "to", "end",
    "start", "select", "where", "primary", "unique", "column", "constraint", "left", "right",
    "natural", "union", "all", "any", "current_date", "session_user", "authorization", "limit",
    "offset", "case", "when", "then", "else", "having", "in", "is", "not", "null", "true",
    "false", "and", "or", "as", "on", "using", "cast", "grant", "return", "do", "desc", "asc",
    "both", "leading", "trailing", "collate", "concurrently", "freeze", "ilike", "similar",
    "verbose", "analyse", "analyze", "array", "asymmetric", "symmetric", "variadic", "window",
    "with", "only", "returning", "localtime", "localtimestamp", "current_time",
    "current_timestamp", "current_user", "current_role", "current_catalog", "current_schema",
}

MAXLEN = 63


def _ident(name: str) -> str:
    """Postgres identifiers are capped at 63 bytes - truncate deterministically."""
    if len(name) <= MAXLEN:
        return name
    h = hashlib.sha1(name.encode()).hexdigest()[:6]
    return name[: MAXLEN - 7] + "_" + h


def q(name: str) -> str:
    name = _ident(name)
    return f'"{name}"' if name in RESERVED or not name.isidentifier() else name


# --------------------------------------------------------------------------- #
# as-is
# --------------------------------------------------------------------------- #
def asis_table(d: DocType) -> str:
    body = [
        "  name varchar(140) NOT NULL PRIMARY KEY",
        "  creation timestamp",
        "  modified timestamp",
        "  modified_by varchar(140)",
        "  owner varchar(140)",
        "  docstatus smallint NOT NULL DEFAULT 0",
        "  idx integer NOT NULL DEFAULT 0",
    ]
    seen = {"name", "creation", "modified", "modified_by", "owner", "docstatus", "idx"}
    for f in d.columns:
        if f.fieldname in seen:
            continue
        seen.add(f.fieldname)
        body.append(f"  {q(f.fieldname)} {f.sql_type('postgres')}")
    if d.istable:
        body += [
            "  parent varchar(140)",
            "  parentfield varchar(140)",
            "  parenttype varchar(140)",
        ]
    L = [f'CREATE TABLE "{d.table_name}" (', ",\n".join(body), ");"]
    for c in d.indexed_columns:
        L.append(f'CREATE INDEX {q("ix_" + slug(d.name) + "_" + slug(c))} ON "{d.table_name}" ({q(c)});')
    if d.istable:
        L.append(f'CREATE INDEX {q("ix_" + slug(d.name) + "_parent")} ON "{d.table_name}" (parent);')
    return "\n".join(L)


def emit_asis(reg: Registry, module: str) -> str:
    ds = [d for d in reg.doctypes if d.module == module and not d.issingle]
    L = [
        "-- ============================================================",
        f"-- {module} - AS-IS DDL (PostgreSQL) generated from DocType JSON",
        "-- Mirrors the ERPNext physical layout: business-key PK, no FK constraints.",
        "-- ============================================================",
        "",
    ]
    for d in sorted(ds, key=lambda x: x.name):
        L += [f"-- {d.name} ({d.kind})", asis_table(d), ""]
    return "\n".join(L)


# --------------------------------------------------------------------------- #
# clean bundle
# --------------------------------------------------------------------------- #
class CleanPlan:
    """Decides the physical table for every doctype / (parent, field) pair.

    `modules` are modelled in full. Anything they reference that lives outside that
    set (another module, or the frappe framework) is emitted as a *stub* table so the
    foreign keys still resolve and the boundary of our scope is explicit.
    """

    def __init__(self, reg: Registry, modules: list[str], app: str = "erpnext"):
        self.reg = reg
        self.modules = set(modules)
        self.parents: list[DocType] = [
            d
            for d in reg.doctypes
            if d.module in self.modules
            and d.app == app
            and not d.istable
            and not d.issingle
        ]
        self.parent_names = {d.name for d in self.parents}
        # child doctype -> [(parent_doctype, fieldname)] limited to in-scope parents
        self.child_bindings: dict[str, list[tuple[DocType, str]]] = {}
        for p in self.parents:
            for fn, ch, _ft in p.child_tables:
                if reg.get(ch):
                    self.child_bindings.setdefault(ch, []).append((p, fn))
        self.tables: dict[str, tuple[DocType, DocType | None, str]] = {}
        for d in self.parents:
            self.tables[d.sql_table] = (d, None, "")
        for ch, binds in self.child_bindings.items():
            cd = self.reg.get(ch)
            for p, fn in binds:
                self.tables[self.child_table_name(p, fn)] = (cd, p, fn)

        # one-hop closure: external doctypes referenced by anything in scope
        self.stubs: dict[str, DocType] = {}
        for _t, (d, _p, _f) in list(self.tables.items()):
            for _fn, target in d.links:
                td = reg.get(target)
                if td is None or td.issingle or td.istable:
                    continue
                if td.name in self.parent_names or td.sql_table in self.tables:
                    continue
                self.stubs[td.sql_table] = td

    def child_table_name(self, parent: DocType, fieldname: str) -> str:
        base = f"{parent.sql_table}_{slug(fieldname)}"
        return _ident(base)

    def table_for_link(self, target: str) -> str | None:
        """Physical table a Link should point at, or None when unresolvable."""
        t = self.reg.get(target)
        if t is None or t.issingle:
            return None
        if not t.istable:
            if target in self.parent_names or t.sql_table in self.stubs:
                return t.sql_table
            return None
        binds = self.child_bindings.get(target, [])
        if len(binds) == 1:  # unambiguous child table
            p, fn = binds[0]
            return self.child_table_name(p, fn)
        return None


def clean_table(plan: CleanPlan, table: str, d: DocType, parent: DocType | None, parentfield: str):
    reg = plan.reg
    L = [f"CREATE TABLE {q(table)} ("]
    cols: list[tuple[str, str]] = [("  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY", "")]
    fks: list[str] = []
    idx: list[str] = []

    if not d.istable:
        cols.append(("  doc_no varchar(140) NOT NULL UNIQUE", "ERPNext `name` business key"))
    if parent is not None:
        pcol = _ident(f"{parent.sql_table}_id")
        cols.append((f"  {q(pcol)} bigint NOT NULL", f"parent -> {parent.name}"))
        cols.append(("  line_no integer NOT NULL", "was ERPNext `idx`"))
        fks.append(
            f"ALTER TABLE {q(table)} ADD CONSTRAINT {q('fk_' + table + '_parent')} "
            f"FOREIGN KEY ({q(pcol)}) REFERENCES {q(parent.sql_table)} (id) ON DELETE CASCADE;"
        )
        idx.append(
            f"CREATE UNIQUE INDEX {q('ux_' + table + '_line')} ON {q(table)} ({q(pcol)}, line_no);"
        )
    if d.is_submittable:
        cols.append(("  docstatus smallint NOT NULL DEFAULT 0", "0 draft, 1 submitted, 2 cancelled"))

    seen: set[str] = set()
    fkcols: dict[str, str] = {}  # fieldname -> physical column
    # every physical column name already taken (fixed columns + fields seen so far)
    phys_used: set[str] = {defn.strip().split()[0].strip('"') for defn, _c in cols}
    phys_used |= {f.fieldname for f in d.columns}
    for f in d.columns:
        if f.fieldname in ("name", "idx", "docstatus", "parent", "parenttype", "parentfield"):
            continue
        if f.fieldname in seen:
            continue
        seen.add(f.fieldname)

        if f.is_link:
            tgt_table = plan.table_for_link(f.options)
            colname = _ident(f"{slug(f.fieldname)}_id")
            if colname in phys_used and colname != f.fieldname:
                colname = _ident(f"{slug(f.fieldname)}_fk")
            phys_used.add(colname)
            if tgt_table:
                null = " NOT NULL" if f.reqd else ""
                cols.append((f"  {q(colname)} bigint{null}", f"-> {f.options}"))
                fks.append(
                    f"ALTER TABLE {q(table)} ADD CONSTRAINT "
                    f"{q('fk_' + table + '_' + slug(f.fieldname))} FOREIGN KEY ({q(colname)}) "
                    f"REFERENCES {q(tgt_table)} (id);"
                )
                fkcols[f.fieldname] = colname
                continue
            # unresolvable: frappe core doctype, out-of-scope module, or ambiguous child
            td = reg.get(f.options)
            if td is None:
                why = "unknown doctype"
            elif td.issingle:
                why = "settings singleton"
            elif td.istable:
                why = "child table with multiple parents"
            else:
                why = f"out of scope: {reg.origin(f.options)}"
            null = " NOT NULL" if f.reqd else ""
            cols.append(
                (f"  {q(f.fieldname)} varchar(140){null}", f"-> {f.options} (no FK: {why})")
            )
            continue

        null = " NOT NULL" if f.reqd else ""
        default = ""
        if f.fieldtype == "Check":
            default = f" DEFAULT {1 if str(f.default) == '1' else 0}"
            null = " NOT NULL"
        elif f.fieldtype in ("Currency", "Float", "Percent", "Int", "Long Int", "Duration"):
            default = " DEFAULT 0"
        comment = ""
        if f.is_dynamic_link:
            comment = f"polymorphic: target doctype in {f.options}"
        elif f.fieldtype == "Select" and f.select_options:
            comment = "enum: " + " | ".join(o for o in f.select_options[:6] if o)
        elif f.fetch_from:
            comment = f"denormalised from {f.fetch_from}"
        cols.append((f"  {q(f.fieldname)} {f.sql_type('postgres')}{null}{default}", comment))

    cols += [
        ("  created_at timestamptz NOT NULL DEFAULT now()", ""),
        ("  updated_at timestamptz NOT NULL DEFAULT now()", ""),
        ("  created_by bigint", ""),
        ("  updated_by bigint", ""),
    ]
    rendered = []
    for i, (defn, comment) in enumerate(cols):
        sep = "," if i < len(cols) - 1 else ""
        rendered.append(f"{defn}{sep}" + (f"   -- {comment}" if comment else ""))
    L.append("\n".join(rendered))
    L.append(");")
    colnames = {defn.strip().split()[0].strip('"') for defn, _c in cols}

    for c in d.indexed_columns:
        phys = fkcols.get(c, c)
        if phys not in colnames:
            continue
        idx.append(f"CREATE INDEX {q('ix_' + table + '_' + slug(c))} ON {q(table)} ({q(phys)});")
    for uc in d.unique_constraints:
        phys = [fkcols.get(c, c) for c in uc]
        idx.append(
            f"CREATE UNIQUE INDEX {q('ux_' + table + '_' + '_'.join(slug(c) for c in uc))} "
            f"ON {q(table)} ({', '.join(q(c) for c in phys)});"
        )
    return "\n".join(L), fks, idx


def stub_table(table: str, d: DocType, reg: Registry) -> str:
    return "\n".join(
        [
            f"-- STUB: {d.name} is owned by {reg.origin(d.name)} (outside the modelled scope).",
            f"--       Referenced by in-scope tables, so it exists here as an FK target only.",
            f"CREATE TABLE {q(table)} (",
            "  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,",
            "  doc_no varchar(140) NOT NULL UNIQUE,",
            "  created_at timestamptz NOT NULL DEFAULT now()",
            ");",
        ]
    )


def emit_clean_bundle(reg: Registry, modules: list[str]) -> tuple[str, str, dict]:
    plan = CleanPlan(reg, modules)
    tables_sql = [
        "-- ============================================================",
        f"-- CLEAN reference schema (PostgreSQL) for: {', '.join(modules)}",
        "-- Surrogate bigint PKs, real FKs, one child table per parent field.",
        "-- Tables referenced from outside this scope are emitted as stubs at the end.",
        "-- Load this file first, then clean_02_constraints.sql.",
        "-- ============================================================",
        "",
    ]
    all_fks: list[str] = []
    all_idx: list[str] = []
    for table in sorted(plan.tables):
        d, parent, parentfield = plan.tables[table]
        head = (
            f"-- {d.name} ({d.kind})"
            if parent is None
            else f"-- {parent.name}.{parentfield} line items -> {d.name}"
        )
        body, fks, idx = clean_table(plan, table, d, parent, parentfield)
        tables_sql += [head, body, ""]
        all_fks += fks
        all_idx += idx

    if plan.stubs:
        tables_sql += [
            "-- ============================================================",
            f"-- {len(plan.stubs)} out-of-scope FK targets, emitted as stubs",
            "-- ============================================================",
            "",
        ]
        for table in sorted(plan.stubs):
            tables_sql += [stub_table(table, plan.stubs[table], reg), ""]

    fk_sql = [
        "-- ============================================================",
        "-- Foreign keys + indexes for the clean reference schema.",
        "-- Emitted separately so table creation order is irrelevant.",
        "-- ============================================================",
        "",
        "-- indexes",
        *all_idx,
        "",
        "-- foreign keys",
        *all_fks,
        "",
    ]
    stats = {
        "tables": len(plan.tables) + len(plan.stubs),
        "modelled_tables": len(plan.tables),
        "stub_tables": len(plan.stubs),
        "foreign_keys": len(all_fks),
        "indexes": len(all_idx),
    }
    return "\n".join(tables_sql), "\n".join(fk_sql), stats
