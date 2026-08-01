# 18 — Metadata, Runtime DDL, and Customisation

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Tranche A documented *what the business logic does*. Tranche E documents *the platform that
business logic runs on* — the parts we do not get for free once we leave Frappe, and which we
must therefore either rebuild, replace with an off-the-shelf equivalent, or deliberately drop.

This first document covers the foundation: **the schema is data**. In Frappe, a table's structure
is a row in another table, and changing a business configuration issues `ALTER TABLE` against a
live production database. Every design decision in this document follows from rejecting that.

---

## 1. The meta-schema

Three tables define every other table:

| Table | Role |
|---|---|
| `tabDocType` | one row per table: `name`, `module`, `istable`, `issingle`, `is_virtual`, `is_submittable`, `autoname`, `naming_rule`, `is_tree`, `track_changes`, `track_seen`, `allow_rename`, `custom`, … |
| `tabDocField` | one row per column: `parent` (the DocType), `fieldname`, `fieldtype`, `options`, `length`, `precision`, `reqd`, `unique`, `search_index`, `not_nullable`, `default`, `idx`, `permlevel`, `read_only`, `allow_on_submit`, `fetch_from`, `is_virtual`, … |
| `tabDocPerm` | one row per (DocType, role, permlevel) permission set — see doc 19 |

Plus the customisation overlay: `tabCustom Field`, `tabProperty Setter`, `tabCustom DocPerm`,
`tabDocType Layout`, `tabDocType Link`, `tabDocType Action`, `tabDocType State`.

### 1.1 `Meta` — the runtime assembly

`frappe/model/meta.py:130` (`class Meta`), constructed via `get_meta` (`frappe/model/meta.py:72`).

`Meta.process` (`frappe/model/meta.py:166`) assembles the effective definition at runtime by
layering:

1. the standard DocType + DocField rows (or a JSON file — `load_doctype_from_file`,
   `frappe/model/meta.py:112`),
2. `add_custom_fields` (`frappe/model/meta.py:405`) — appends every `Custom Field` row for the
   doctype, ordered by `idx`, tagged `is_custom_field = 1`,
3. `apply_property_setters` (`frappe/model/meta.py:423`) — overwrites individual properties,
4. `add_custom_links_and_actions` (`frappe/model/meta.py:465`),
5. `set_custom_permissions` (`frappe/model/meta.py:636`),
6. `sort_fields` (`frappe/model/meta.py:544`) +
   `_update_fields_based_on_order` (`frappe/model/meta.py:625`) +
   `_update_field_order_based_on_insert_after` (`frappe/model/meta.py:1015`).

`apply_property_setters` is worth reading in full (`frappe/model/meta.py:437`–`:481`):

```python
for ps in property_setters:
    if ps.doctype_or_field == "DocType":
        self.set(ps.property, cast(ps.property_type, ps.value))
    elif ps.doctype_or_field == "DocField":
        for d in self.fields:
            if d.fieldname == ps.field_name:
                d.set(ps.property, cast(ps.property_type, ps.value)); break
    elif ps.doctype_or_field == "DocType Link":   ...
    elif ps.doctype_or_field == "DocType Action": ...
    elif ps.doctype_or_field == "DocType State":  ...
```

So **any property of any field can be overridden by a row in a generic key-value table**, with the
value stored as text and cast at read time by `property_type`. `Property Setter.name` is
`autoname`d (`frappe/custom/doctype/property_setter/property_setter.py:36`) and there is no
uniqueness constraint on `(doc_type, doctype_or_field, field_name, property)` — two setters for the
same property both apply, and the winner is whichever the unordered
`frappe.db.get_values` returns last.

Consequences of "meta is assembled at runtime from five sources":

- **The effective schema is not knowable from the database schema.** Which columns are
  mandatory, unique, or read-only depends on rows in `tabProperty Setter`.
- **Meta must be cached aggressively** (`clear_meta_cache`, `frappe/model/meta.py:96`;
  `init_field_caches`, `frappe/model/meta.py:537`; the `_fields`/`_valid_columns`/
  `_table_fields` cached properties at `:512`, `:263`, `:516`). Every customisation change must
  invalidate that cache across every worker process. `frappe.clear_cache(doctype=...)` is called
  from `DocType.on_update` (`frappe/core/doctype/doctype/doctype.py:591`),
  `CustomField.on_update` (`frappe/custom/doctype/custom_field/custom_field.py:222`),
  `CustomField.on_trash` (`:248`), and `PropertySetter.on_update`
  (`frappe/custom/doctype/property_setter/property_setter.py:56`). A missed invalidation is a
  stale-schema bug.
- `check_if_large_table` (`frappe/model/meta.py:492`) exists because meta assembly itself is
  expensive enough to need a size heuristic.

### 1.2 Precision and currency are resolved from metadata at read time

`get_field_precision` (`frappe/model/meta.py:924`), `get_field_currency`
(`frappe/model/meta.py:872`), `get_precision_from_currency_format`
(`frappe/model/meta.py:940`).

**Money precision is not a column property.** A `Currency` field is stored as
`decimal(21,9)` and *rounded for display and for comparison* according to
`System Settings.currency_precision`, the `Currency` doctype's `smallest_currency_fraction_value`,
or a per-field `precision` override. That is why every arithmetic comparison in ERPNext goes
through `flt(x, precision)` — and why the places that forget (doc 11 §2.4, doc 12 §3.2) are bugs.

Our decision (D1) — money is `numeric(19,4)` **in the column** — removes this entire layer.
Precision is a property of the type, enforced by the database, not a metadata lookup applied by
convention.

---

## 2. Runtime DDL

### 2.1 The sync path

`frappe.db.updatedb(doctype, meta)` → `DBTable.sync` (`frappe/database/schema.py:44`):

```python
def sync(self):
    if self.meta.get("is_virtual"):
        return                       # no schema to sync for virtual doctypes
    if self.is_new():
        self.create()
    else:
        frappe.client_cache.delete_value(f"table_columns::{self.table_name}")
        self.alter()
```

`is_new()` is `self.table_name not in frappe.db.get_tables()`
(`frappe/database/schema.py:170`) — a **catalogue lookup, cached**, to decide between `CREATE`
and `ALTER`.

`get_columns_from_docfields` (`frappe/database/schema.py:80`) builds the desired column set from
`meta.get_fieldnames_with_value(with_field_meta=True)` — i.e. **from the assembled meta**,
including custom fields — skipping `is_virtual` fields, and adding
`frappe.db.OPTIONAL_COLUMNS` plus `_seen` when `track_seen` is set (`:87`–`:92`).

`DbColumn.build_for_alter_table` (`frappe/database/schema.py:266`) diffs desired against actual
and populates nine mutation lists declared in `__init__` (`frappe/database/schema.py:31`–`:40`):
`add_column`, `change_type`, `change_name`, `change_nullability`, `add_unique`, `add_index`,
`drop_unique`, `drop_index`, `set_default`.

`PostgresTable.alter` (`frappe/database/postgres/schema.py:96`) then emits the SQL.

### 2.2 What the type-change SQL actually does

`frappe/database/postgres/schema.py:100`–`:145`. Because Frappe stores many logical types as
`varchar`/`text` and changes them later, every type change needs an explicit `USING` cast:

```python
if col.fieldtype == "Datetime":
    using = f"USING NULLIF(`{col.fieldname}`::text, '')::timestamp without time zone"
elif col.fieldtype == "Date":
    using = f"USING NULLIF(`{col.fieldname}`::text, '')::date"
elif col.fieldtype == "Check":
    using = f"USING COALESCE(NULLIF(`{col.fieldname}`::text, ''), '0')::smallint"
elif col.fieldtype in ("Currency", "Float", "Percent"):
    using = f"USING COALESCE(NULLIF(`{col.fieldname}`::text, ''), '0')::numeric"
elif col.fieldtype == "Int":
    int_type = get_definition(col.fieldtype, length=col.length)
    using = f"USING COALESCE(NULLIF(`{col.fieldname}`::text, ''), '0')::numeric::{int_type}"
...
if using:
    query.append(f"ALTER COLUMN `{col.fieldname}` DROP DEFAULT")
    if col not in self.set_default: self.set_default.append(col)
query.append("ALTER COLUMN `{}` TYPE {} {}".format(col.fieldname, get_definition(...), using))
```

Read what this means operationally:

- **`COALESCE(NULLIF(x,''),'0')` silently converts blanks to zero** when a text column becomes
  `Currency`, `Float`, `Percent`, `Check`, or `Int`. Empty means zero, by fiat, with no audit.
- The existing `DEFAULT` is dropped and re-applied (`:139`–`:143`) because a string default cannot
  be cast — so the default is briefly absent mid-migration.
- The comment at `:126`–`:128` documents that `Int` with `length > 11` maps to `bigint`
  ("Long Int"), so a plain `::int` would overflow. Integer width is a **metadata length field**,
  not a chosen type.
- `ALTER COLUMN ... TYPE` on PostgreSQL rewrites the whole table and takes an
  `ACCESS EXCLUSIVE` lock. This is triggered by a user saving a DocType or a Custom Field
  (§2.4) — i.e. **a business-configuration action takes an exclusive lock on a production
  table**.

Error handling (`frappe/database/postgres/schema.py:302`–`:324`) converts three database errors
into user messages: duplicate fieldname, "cannot be set as unique … non-unique existing values",
and "some existing values cannot be converted to the new type". Those are the failure modes of
doing DDL from a form.

### 2.3 The primary key can change type

`alter_primary_key` (`frappe/database/postgres/schema.py:325`):

```python
if autoname == "UUID" and frappe.db.get_column_type(self.doctype, "name") != "uuid":
    if not frappe.db.get_value(self.doctype, {}, order_by=None):
        return "alter column `name` TYPE uuid USING name::uuid"
    else:
        frappe.throw("Primary key of doctype {0} can not be changed as there are existing values.")
if autoname != "UUID" and frappe.db.get_column_type(self.doctype, "name") == "uuid":
    return f"alter column `name` TYPE varchar({frappe.db.VARCHAR_LEN})"
```

and `setup_autoincrement_and_sequence` (`frappe/core/doctype/doctype/doctype.py:614`):

```python
name_type = f"varchar({frappe.db.VARCHAR_LEN})"
if self.autoname == "autoincrement":
    name_type = "bigint"
    frappe.db.create_sequence(self.name, check_not_exists=True)
change_name_column_type(self.name, name_type)
```

So the PK type is `varchar(140)` by default, `bigint` for autoincrement, and `uuid` if you set
`autoname = "UUID"` **and the table is empty**. Note the emptiness check is
`frappe.db.get_value(self.doctype, {}, order_by=None)` — one row probe, no lock. Also note the
reverse direction (`uuid → varchar`) is allowed **with data present**.

Frappe *does* now support UUID PKs. But because `Link` columns are `varchar(140)` regardless
(`get_definition`, `frappe/database/schema.py:415`), a UUID-named doctype is referenced by
varchar columns — the FK types do not match, and there are no actual FK constraints to notice
(doc 09 §5).

### 2.4 The trigger for all of this is a form save

`DocType.on_update` (`frappe/core/doctype/doctype/doctype.py:533`) is the whole pipeline:

```python
if self.get("can_change_name_type"): self.setup_autoincrement_and_sequence()
try:
    frappe.db.updatedb(self.name, Meta(self))          # ← DDL
except Exception as e:
    print(f"\n\nThere was an issue while migrating the DocType: {self.name}\n"); raise
self.change_modified_of_parent()
make_module_and_roles(self)
self.update_fields_to_fetch()
... export_doc(), make_controller_template(), set_base_class_for_controller(),
    export_types_to_controller()                       # ← writes .json / .py FILES
... run_module_method("on_doctype_update"), run_module_method("after_doctype_insert")
self.sync_doctype_layouts()
frappe.clear_cache(doctype=self.name); clear_user_cache(...); clear_linked_doctype_cache()
frappe.publish_realtime("doctype_update", {"doctype": self.name}, after_commit=True)
```

Three things happen in one document save: **DDL against the live database**, **source-file
writes to disk** (when `developer_mode`), and **cache invalidation broadcast to other
processes**. The file writes are deferred to `request.after_response` (`:578`–`:580`) so the
client sees the saved doc first — a comment at `:577` says exactly that. If the DDL commits and
the deferred export then fails, database and code are out of step.

`CustomField.on_update` (`frappe/custom/doctype/custom_field/custom_field.py:214`) does the same,
smaller:

```python
if not self.flags.ignore_validate:
    validate_fields_for_doctype(self.dt)
if not frappe.flags.in_create_custom_fields:
    frappe.clear_cache(doctype=self.dt)
    frappe.db.updatedb(self.dt)          # ← ALTER TABLE
```

**A business user adding a custom field runs `ALTER TABLE ... ADD COLUMN` on a production
table.** This is the mechanism ERPNext's accounting dimensions use (doc 12 §1.2, decision D13),
and it is why `getattr(budget_table, dimension_fieldname)` works at all.

### 2.5 Dropped fields leave columns behind

`trim_tables` (`frappe/model/meta.py:966`) / `trim_table` (`frappe/model/meta.py:995`):

```python
columns = frappe.db.get_table_columns(doctype)
fields  = frappe.get_meta(doctype, cached=False).get_fieldnames_with_value()
columns_to_remove = [f for f in set(columns) - set(fields) if is_internal(f)]
if columns_to_remove and not dry_run:
    frappe.db.sql_ddl(f"ALTER TABLE `tab{doctype}` {', '.join(f'DROP `{c}`' for c in columns_to_remove)}")
```

The docstring admits it: *"removing a field in a DocType doesn't automatically delete the db
field."* So the physical schema accumulates orphaned columns until an administrator runs
`bench trim-tables` — a **destructive bulk `DROP COLUMN`** driven by a set difference, with a
`dry_run` flag because it is dangerous. `get_orphaned_columns`
(`frappe/custom/doctype/customize_form/customize_form.py:686`) surfaces them in the UI.

This is why our catalog run found **908 physical tables for 997 DocTypes** and why the as-is DDL
(`schema/ddl/*_asis.sql`) has columns that no DocField describes.

### 2.6 Validation of the meta-schema

Because the schema is data, its constraints are Python. `validate_fields`
(`frappe/core/doctype/doctype/doctype.py:1343`) contains **twenty-two** nested checks:

`check_illegal_characters` (`:1362`), `check_invalid_fieldnames` (`:1365`),
`check_unique_fieldname` (`:1386`), `check_fieldname_length` (`:1398`),
`check_illegal_mandatory` (`:1401`), `check_link_table_options` (`:1408`),
`check_hidden_and_mandatory` (`:1442`), `check_width` (`:1451`),
`check_in_list_view` (`:1455`), `check_in_global_search` (`:1462`),
`check_dynamic_link_options` (`:1468`), `check_illegal_default` (`:1482`),
`check_precision` (`:1508`), `check_unique_and_text` (`:1516`), `check_fold` (`:1552`),
`check_search_fields` (`:1566`), `check_title_field` (`:1583`) with
`_validate_title_field_pattern` (`:1591`), `check_image_field` (`:1613`),
`check_is_published_field` (`:1624`), `check_website_search_field` (`:1631`),
`check_timeline_field` (`:1643`).

Plus, on the DocType itself: `validate_field_name_conflicts` (`:236`),
`validate_document_type` (`:409`), `validate_virtual_doctype_methods` (`:428`),
`validate_series` (`:1163`), `validate_empty_name` (`:1214`),
`validate_autoincrement_autoname` (`:1228`), `validate_links_table_fieldnames` (`:1281`),
`validate_nestedset` (`:995`), `validate_child_table` (`:1065`), `validate_name` (`:1086`).

And column-name legality is checked twice: `validate_column_name`
(`frappe/database/schema.py:398`) and `validate_column_length`
(`frappe/database/schema.py:410`) — because the fieldname becomes a SQL identifier.
`DBTable.validate` (`frappe/database/schema.py:112`) additionally runs
`SELECT MAX(CHAR_LENGTH(col))` before shortening a `varchar`, and **silently reverts the length**
with a `msgprint` if truncation would occur (`:157`–`:165`).

Thirty-plus validators reimplementing, in Python, what a DDL parser and the database's own
constraint system do for free.

---

## 3. Special doctype kinds

| Kind | Flag | Physical form |
|---|---|---|
| Normal | — | `tab<Name>` table |
| Child table | `istable = 1` | `tab<Name>` with `parent`, `parenttype`, `parentfield`, `idx` |
| Single | `issingle = 1` | **no table** — rows in `tabSingles` as `(doctype, field, value)` |
| Virtual | `is_virtual = 1` | **no table** — controller implements `db_insert`/`load_from_db`/`db_update` |
| Tree | `is_tree = 1` | adds `lft`, `rgt`, `old_parent` (`add_nestedset_fields`, `frappe/core/doctype/doctype/doctype.py:1009`) |

### 3.1 Singles: settings as EAV

Every `*Settings` doctype (`Accounts Settings`, `Stock Settings`, `Selling Settings`,
`Buying Settings`, `POS Settings`, `System Settings`, …) is a **Single**, stored as
key/value text rows in `tabSingles`. `Document.update_single` (`frappe/model/document.py:1030`)
writes them.

Consequences, all of which we met in Tranche A:

- **Settings are untyped strings.** `frappe.get_single_value("Accounts Settings",
  "delete_linked_ledger_entries")` returns text coerced by the reading code.
- **Settings are global, not per company.** `Stock Settings.over_delivery_receipt_allowance`
  (doc 10 §1.3), `Accounts Settings.role_allowed_to_over_bill`,
  `Accounts Settings.unlink_payment_on_cancellation_of_invoice` (doc 09 §3.2),
  `Stock Settings.enable_stock_reservation` (doc 16) — every one of these is a *single global
  switch* that changes accounting semantics for **all** companies in the installation.
- There is no history of who changed a setting or when (beyond generic Version rows), and no way
  to make a setting effective-dated.

This is the single most consequential platform finding for a multi-company ERP: **behaviour that
must vary by company and by date is stored as one untyped global string.**

### 3.2 Virtual doctypes

`is_virtual = 1` means the controller must implement `db_insert`, `load_from_db`, `db_update`,
`get_list`, `get_count`, `get_stats`, `delete`. `validate_virtual_doctype_methods`
(`frappe/core/doctype/doctype/doctype.py:428`) checks they exist; `DBTable.sync`
(`frappe/database/schema.py:44`) skips them. They are the escape hatch for
"a DocType backed by something that is not a table" — an API, a view, a file.

Useful pattern, and one we adopt in a different form: our read models are **database views**,
which need no controller at all.

---

## 4. Customisation: the overlay model

Three mechanisms, all rows in tables, all applied at meta-assembly time:

**`Custom Field`** (`frappe/custom/doctype/custom_field/custom_field.py:16`).
`autoname` is `dt + "-" + fieldname` (`:132`). `set_fieldname` (`:136`) derives a fieldname from
the label by stripping non-alphanumerics, lowercasing, and prefixing `custom_` (`:158`–`:164`);
a fieldname colliding with a reserved word gets a `1` appended (`:168`–`:169`). Reserved list at
`:137`–`:147`.

Helpers: `create_custom_field` (`:307`), `create_custom_fields` (`:328`) with
`process_field_update` (`:333`), `create_custom_field_if_values_exist` (`:299`),
`get_existing_custom_fields` (`:397`), `rename_fieldname` (`:411`) with
`_update_fieldname_references` (`:442`), `delete_custom_fields` (`:459`).

Note `rename_fieldname` + `_update_fieldname_references`: renaming a custom field must rewrite
references in reports, print formats, notifications, and workflows — string references, found by
search.

**`Property Setter`** (`frappe/custom/doctype/property_setter/property_setter.py:11`) —
covered in §1.1. `make_property_setter` (`:76`), `delete_property_setter` (`:105`),
`bulk_delete_property_setters` (`:119`), `_delete_property_setters` (`:168`),
`validate_fieldtype_change` (`:52`).

**`Customize Form`** (`frappe/custom/doctype/customize_form/customize_form.py:30`) — the UI that
writes the other two. `fetch_to_customize` (`:104`), `load_properties` (`:137`),
`save_customization` (`:231`), `set_property_setters` (`:273`),
`set_property_setter_for_field_order` (`:290`), `set_property_setters_for_doctype` (`:316`),
`set_property_setters_for_docfield` (`:325`), `allow_property_change` (`:333`),
`set_property_setters_for_actions_and_links` (`:415`), `update_order_property_setter` (`:448`),
`clear_removed_items` (`:462`), `update_custom_fields` (`:471`), `add_custom_field` (`:484`),
`update_in_custom_field` (`:502`), `delete_custom_fields` (`:534`),
`validate_fieldtype_change` (`:583`), `validate_fieldtype_length` (`:607`),
`reset_to_defaults` (`:635`), `reset_layout` (`:643`), `trim_table` (`:661`),
`allow_fieldtype_change` (`:674`), `reset_customization` (`:692`),
`is_standard_or_system_generated_field` (`:717`).

`allow_fieldtype_change` (`:674`) with `in_field_group` (`:679`) defines which type changes are
permitted — a hard-coded compatibility matrix of field-type groups, which is the application-level
stand-in for "can this column be safely `ALTER`ed".

The design is coherent on its own terms: standard definitions ship in files, customer changes
live in separate tables, and `bench migrate` can therefore replace the standard rows without
losing customisations. The price is that **the effective schema is a five-way merge computed at
runtime**, and that customisation is DDL.

---

## 5. What we do instead

### 5.1 Migrations, not metadata

Our schema lives in **versioned SQL migration files** under source control, applied by a
migration runner (`sqlx`/`Flyway`/`Atlas`-class tool — selection is a Tranche-E open question,
see doc 25). Properties of that choice:

- The schema is knowable from the schema. There is no overlay to assemble, no cache to
  invalidate, no `Property Setter` precedence question (§1.1).
- Type changes are reviewed, tested against a copy, and applied in a maintenance window by an
  operator — not triggered by a user pressing Save (§2.4).
- No `COALESCE(NULLIF(x,''),'0')` silent data coercion (§2.2). A migration that needs to convert
  data does it in an explicit, reviewed `UPDATE` with a recorded row count.
- No orphaned columns (§2.5): dropping a column is a migration, so it is intentional and
  reviewed, and `bench trim-tables` has no analogue.
- No `varchar` primary keys and therefore no `alter_primary_key` (§2.3). `uuid` from day one.

### 5.2 Extension without DDL (decision D13)

Business users still need to add fields. Three tiers, none of which touch DDL:

**Tier 1 — fixed dimension slots.** Analytical dimensions (cost centre, project, and *n*
generic slots) are real, indexed FK columns present from the start:

```sql
-- on gl_entry, stock_move, and every posting line
cost_center_id uuid REFERENCES cost_center(id),
project_id     uuid REFERENCES project(id),
dim1_id        uuid REFERENCES dim_value(id),
dim2_id        uuid REFERENCES dim_value(id),
dim3_id        uuid REFERENCES dim_value(id),
dim4_id        uuid REFERENCES dim_value(id)
```

with

```sql
CREATE TABLE dimension (
    id          uuid PRIMARY KEY,
    company_id  uuid NOT NULL REFERENCES company(id),
    slot        smallint NOT NULL CHECK (slot BETWEEN 1 AND 4),
    code        text NOT NULL,
    label       text NOT NULL,
    UNIQUE (company_id, slot),
    UNIQUE (company_id, code)
);
CREATE TABLE dim_value (
    id           uuid PRIMARY KEY,
    dimension_id uuid NOT NULL REFERENCES dimension(id),
    company_id   uuid NOT NULL,
    code         text NOT NULL,
    parent_id    uuid REFERENCES dim_value(id),
    UNIQUE (dimension_id, code)
);
```

A company binds slot 1 to "Region", slot 2 to "Product Line", and so on. Configuration is a row;
the column already exists, already has an FK, already has an index, and already appears in every
report. Contrast ERPNext, where creating an Accounting Dimension issues `ALTER TABLE` against
`tabGL Entry` and every voucher table.

Beyond four slots, `gl_entry_dimension (gl_entry_id, dimension_id, dim_value_id)` — a narrow,
properly-constrained side table, unbounded in width, at the cost of a join.

**Tier 2 — typed extension attributes.** For genuinely per-tenant fields on masters:

```sql
CREATE TABLE ext_field (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    entity        entity_kind NOT NULL,        -- 'item','party','sales_order', ...
    code          text NOT NULL,
    data_type     ext_type NOT NULL,           -- 'text','integer','numeric','date','boolean','enum','ref'
    is_required   boolean NOT NULL DEFAULT false,
    enum_values   text[],
    ref_entity    entity_kind,
    UNIQUE (company_id, entity, code)
);
CREATE TABLE ext_value (
    entity        entity_kind NOT NULL,
    entity_id     uuid NOT NULL,
    ext_field_id  uuid NOT NULL REFERENCES ext_field(id),
    company_id    uuid NOT NULL,
    v_text        text, v_int bigint, v_num numeric(21,9),
    v_date date,  v_bool boolean, v_ref uuid,
    PRIMARY KEY (entity, entity_id, ext_field_id),
    CONSTRAINT ext_one_value CHECK (
        (v_text IS NOT NULL)::int + (v_int IS NOT NULL)::int + (v_num IS NOT NULL)::int
      + (v_date IS NOT NULL)::int + (v_bool IS NOT NULL)::int + (v_ref IS NOT NULL)::int = 1
    )
);
```

This is EAV, and EAV is normally the wrong answer — but note what it is *not* used for: **no
posting, ledger, or fulfilment logic reads `ext_value`.** It carries descriptive attributes only.
The typed columns plus the one-value `CHECK` mean values are at least type-correct, unlike
`tabSingles` (§3.1). A per-tenant field that needs to participate in *logic* gets a migration.

**Tier 3 — JSONB for opaque payloads.** `metadata jsonb` on documents, for integration
round-tripping and UI state. Indexed with `GIN` where queried. Never a source of truth.

### 5.3 Settings that are typed, scoped, and dated

Replacing `tabSingles` (§3.1):

```sql
CREATE TABLE setting_def (
    key            text PRIMARY KEY,           -- 'accounts.unlink_payment_on_cancel'
    data_type       ext_type NOT NULL,
    scope_level     setting_scope NOT NULL,     -- 'system','company','warehouse','terminal','user'
    default_value   jsonb NOT NULL,
    description     text NOT NULL,
    affects_posting boolean NOT NULL DEFAULT false
);
CREATE TABLE setting_value (
    id           uuid PRIMARY KEY,
    key          text NOT NULL REFERENCES setting_def(key),
    company_id   uuid REFERENCES company(id),
    scope_id     uuid,
    value        jsonb NOT NULL,
    valid_from   date NOT NULL DEFAULT '-infinity',
    valid_to     date NOT NULL DEFAULT 'infinity',
    changed_by   uuid NOT NULL REFERENCES app_user(id),
    changed_at   timestamptz NOT NULL DEFAULT now(),
    reason       text,
    EXCLUDE USING gist (
        key WITH =,
        coalesce(company_id,'00000000-0000-0000-0000-000000000000') WITH =,
        coalesce(scope_id, '00000000-0000-0000-0000-000000000000') WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&
    )
);
```

Four properties ERPNext's settings lack:

1. **Typed** — `data_type` + `jsonb` validated on write.
2. **Scoped** — a setting can differ per company, warehouse, or POS terminal. Resolution is a
   single ordered `SELECT` by specificity.
3. **Effective-dated**, with `EXCLUDE USING gist` so overlapping values are impossible (the same
   pattern as `item_price`, doc 17 §7.4).
4. **Audited** — `changed_by`, `changed_at`, `reason`, and full history retained.

`affects_posting = true` settings additionally require the current period to be open to change,
because changing them retroactively alters what the books would have said.

### 5.4 Everything else in this document, resolved

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Schema stored in `tabDocType`/`tabDocField` | **Reject** | versioned SQL migrations (§5.1) |
| Meta assembled at runtime from 5 sources | **Reject** | one authoritative schema |
| `Property Setter` key-value overrides, no uniqueness | **Reject** | migrations; UI-only concerns in a separate presentation config |
| Precision resolved from metadata at read time | **Reject** | `numeric(19,4)` / `numeric(21,9)` in the column (D1) |
| `ALTER TABLE` on user save | **Reject** | dimension slots + `ext_field` (§5.2) |
| Silent blank→0 coercion on type change | **Reject** | explicit, reviewed data migrations |
| Orphaned columns + `trim-tables` | **Reject** | dropping a column is a migration |
| `varchar(140)` PK, changeable to `bigint`/`uuid` | **Reject** | `uuid` PK, immutable (D3, doc 09 §6) |
| 30+ Python validators for schema legality | **Reject** | the database's own DDL validation |
| Singles as untyped global EAV | **Reject** | `setting_def` / `setting_value` (§5.3) |
| Virtual doctypes | **Keep the idea** | database views + read models |
| Child tables with `parent`/`parenttype`/`parentfield`/`idx` | **Partly keep** | real FK to the parent, `line_no smallint`; no `parenttype` (each child table belongs to exactly one parent) |
| Nested-set trees (`lft`/`rgt`) | **Reject** | `parent_id` + recursive CTE (D12) |
| `is_submittable` as a metadata flag | **Reject** | lifecycle columns + triggers per table (doc 09 §8) |

---

## 6. What this costs us

Being honest about the trade: Frappe's model buys real things that we are giving up.

| We lose | Mitigation |
|---|---|
| Users adding fields without a deployment | Tiers 1-3 (§5.2) cover the realistic cases; anything in *logic* was never safe to add without review anyway |
| Auto-generated CRUD UI from metadata | We need a presentation-metadata layer (`ui_field`, `ui_layout`) — but it describes **rendering only**, never storage, so it cannot break the database |
| Auto-generated REST API per doctype | Generate from the migration-derived schema at build time (introspection → OpenAPI), not at runtime |
| One-click "export this DocType as a fixture" | Migrations *are* the fixtures |
| `Customize Form` UX | A narrower admin UI over `ext_field` + `setting_value` + `ui_field` |

The presentation-metadata layer is the one piece of Frappe's design we genuinely need to
reimplement, and it is scoped in doc 25.

---

Cross-references: doc 09 (lifecycle, naming, deletion), doc 12 §1.2 (accounting dimensions as
`ALTER TABLE`), doc 19 (permissions), doc 23 (migrations and patches), doc 25 (platform spec),
`docs/design/FINAL-SCHEMA.md`.
