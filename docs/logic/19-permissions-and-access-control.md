# 19 — Permissions and Access Control

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Frappe's permission system is genuinely sophisticated — six independent mechanisms composed at
runtime — and it is entirely **application-level**. Nothing is enforced by the database. For an
ERP holding multiple companies' books, that is the central problem: a single missing
`ignore_permissions=False` or a raw `frappe.db.sql` bypasses the whole model.

---

## 1. The six mechanisms

| # | Mechanism | Storage | Granularity |
|---|---|---|---|
| 1 | **Role permissions** | `tabDocPerm` / `tabCustom DocPerm` | (doctype, role, permlevel) × 14 rights |
| 2 | **`if_owner`** | `DocPerm.if_owner` flag | restricts to `owner = session.user` |
| 3 | **User permissions** | `tabUser Permission` | (user, doctype, docname, applicable_for) |
| 4 | **Document sharing** | `tabDocShare` | (user, doctype, docname) × read/write/submit/share |
| 5 | **Controller `has_permission`** | Python method / `hooks.py` | arbitrary code |
| 6 | **`permission_query_conditions`** | `hooks.py` / `Server Script` | raw SQL fragment injected into `WHERE` |

Plus field-level: `DocField.permlevel` + `DocPerm` rows at that permlevel, and masked fields.

### 1.1 The fourteen rights

`frappe/permissions.py:13` (`std_rights`):

```
select, read, write, create, delete, submit, cancel, amend,
print, email, report, import, export, share
```

Extended per-doctype by `Permission Type` rows (`get_doctype_ptype_map`, imported at
`frappe/permissions.py:9`, used in `false_if_not_shared`, `frappe/permissions.py:179`).

Four automatic roles (`frappe/permissions.py:32`–`:40`): `Guest`, `All`, `Desk User`,
`Administrator`, assigned by user type.

**`Administrator` short-circuits everything** — `has_permission` (`frappe/permissions.py:106`),
`get_role_permissions` (`frappe/permissions.py:305`) both return "allow everything" immediately.
`allow_everything` is at `frappe/permissions.py:774`.

---

## 2. `has_permission` — the composition order

`frappe/permissions.py:80`. The order matters, so here it is in sequence:

```python
if user == "Administrator":                                  return True          # :105
if ptype == "share" and disable_document_sharing:            return False         # :109
if not doc and hasattr(doctype, "doctype"):  doc, doctype = doctype, doctype.doctype   # :117
if frappe.is_table(doctype):                 return has_child_permission(...)     # :121
meta = frappe.get_meta(doctype)
if not doc and meta.issingle:                doc = meta.name                      # :134
if doc:
    perm = get_doc_permissions(doc, user=user, ptype=ptype).get(ptype)            # :140
else:
    if ptype == "submit" and not meta.is_submittable:  return False               # :153
    if ptype == "import" and not meta.allow_import:    return False               # :157
    perm = get_role_permissions(meta, user=user).get(ptype)                       # :161
if not perm and not ignore_share_permissions:
    perm = false_if_not_shared()                                                  # :207
if not perm and ptype == "select":
    perm = has_permission(doctype, ptype="read", ...)                             # :211
return bool(perm)
```

Notes:

- `select` is **implied by `read`** (`:210`–`:221`) — a recursive re-entry.
- Sharing is an **OR** on top of roles (`:205`–`:208`), and only for a subset of rights:
  `false_if_not_shared` (`frappe/permissions.py:177`) allows
  `["read","write","share","submit","email","print"]` plus doctype-specific custom rights
  (`:179`), and maps `email`/`print` to `read` (`:183`).
- The whole function is wrapped by `print_has_permission_check_logs`
  (`frappe/permissions.py:43`), which collects `_debug_log` (`frappe/permissions.py:66`) and
  `push_perm_check_log` (`frappe/permissions.py:798`) entries and `msgprint`s them **only when
  access was denied and the user is checking their own permission** (`:52`–`:58`). Permission
  denials are explained to the user in the UI — good UX, and a mild information-disclosure
  surface.

The existence of `Permission Inspector` as a core doctype
(`frappe/core/doctype/permission_inspector/`) is the tell: the composition is complex enough to
need a debugger.

### 2.1 `get_role_permissions` and the `if_owner` collapse

`frappe/permissions.py:282`. Per right:

```python
def is_perm_applicable(perm): return perm.role in roles and cint(perm.permlevel) == 0
applicable_permissions   = list(filter(is_perm_applicable, doctype_meta.permissions))
has_if_owner_enabled     = any(p.get("if_owner", 0) for p in applicable_permissions)

for ptype in get_rights(doctype_meta.name):
    pvalue = any(p.get(ptype, 0) for p in applicable_permissions)
    perms[ptype] = cint(pvalue)
    if (pvalue and has_if_owner_enabled
            and not has_permission_without_if_owner_enabled(ptype)
            and ptype != "create"):
        perms["if_owner"][ptype] = cint(pvalue and is_owner)
        perms[ptype] = 1 if ptype in ("select", "read") else 0
```

Three things to understand:

1. **Rights are OR-ed across roles.** A user with two roles gets the union. There is no `DENY`.
   You cannot express "Sales User may read invoices, except the ones for Company B" through roles
   — that is what User Permissions are for (§3).
2. **`permlevel == 0` only.** Role permissions at higher permlevels do *not* grant document
   access; they only unlock fields (§5).
3. **The `if_owner` collapse** (`:326`–`:335`): when a right is granted *only* via `if_owner`
   rows, the doctype-level `perms[ptype]` is forced to `0` **except** `select`/`read`, which are
   set to `1` so the list view still works — and then the *query* is constrained by
   `owner = user`. The comment says exactly that (`:333`–`:335`).

   So the doctype-level answer is deliberately a lie, corrected later at query level by
   `requires_owner_constraint` (`frappe/model/db_query.py:1659`) → a
   `` `tabX`.`owner` = <user> `` condition (`frappe/model/db_query.py:1233`–`:1236`).
   **If a code path reads rows without going through `DatabaseQuery`, the `if_owner`
   restriction silently does not apply.**

Caching: `frappe.local.role_permissions[cache_key]` where
`cache_key = (doctype, user, bool(is_owner))` (`frappe/permissions.py:302`) — request-local,
so it is recomputed per request.

`get_roles` (`frappe/permissions.py:535`) with inner `get` (`:543`);
`get_perms_for` (`:578`); `get_all_perms` (`:523`); `get_valid_perms` (`:505`);
`get_doctypes_with_read` (`:501`); `get_doctype_roles` (`:572`);
`get_doctypes_with_custom_docperms` (`:584`).

Customisation of permissions mirrors §18's overlay model: `setup_custom_perms` (`:684`),
`copy_perms` (`:731`), `reset_perms` (`:739`), `add_permission` (`:691`),
`update_permission_property` (`:657`) — `Custom DocPerm` rows replace `DocPerm` rows wholesale
for a doctype once customised.

### 2.2 `get_doc_permissions` — the per-document layer

`frappe/permissions.py:227`, with inner `is_user_owner` (`:234`). It calls
`get_role_permissions`, then `has_user_permission` (§3), then
`has_controller_permissions` (`frappe/permissions.py:481`), which dispatches to the
`has_permission` hook and the doctype controller's own `has_permission` method.

ERPNext uses this for company scoping. `erpnext/hooks.py`:

```python
has_permission = {
    "Item":     "erpnext.stock.doctype.company_restriction.company_restriction.has_permission",
    "Customer": "erpnext.stock.doctype.company_restriction.company_restriction.has_permission",
    "Supplier": "erpnext.stock.doctype.company_restriction.company_restriction.has_permission",
}
permission_query_conditions = {
    "Item":     "erpnext...company_restriction.get_permission_query_conditions",
    "Customer": "erpnext...company_restriction.get_permission_query_conditions",
    "Supplier": "erpnext...company_restriction.get_permission_query_conditions",
}
```

(`erpnext/hooks.py:312`–`:315` for the query conditions; the `has_permission` map immediately
above it.)

**Three doctypes.** Company restriction — the thing that matters most in a multi-company ERP —
is applied to `Item`, `Customer`, and `Supplier`, via a hook, and to nothing else. Every
transaction table relies on User Permissions on the `company` link field instead (§3), which is
opt-in per user and enforced only through `DatabaseQuery`.

Also note `has_website_permission` in the same hooks block, mapping seven trade doctypes to
`erpnext.controllers.website_list_for_contact.has_website_permission` — the customer-portal
access path, a *separate* permission system for web users.

---

## 3. User Permissions

`tabUser Permission`: `(user, allow /* doctype */, for_value /* docname */, applicable_for,
is_default, hide_descendants)`.

Semantics: "user U may only see documents whose link field pointing at doctype D has one of
these values". This is how per-company, per-territory, per-warehouse restriction is actually
done.

### 3.1 Document-level check

`has_user_permission` (`frappe/permissions.py:351`). Two steps:

**Step 1 — the document itself** (`:378`–`:409`). If the doctype is itself restricted
(e.g. a User Permission on `Company` and you are reading a `Company`), `docname` must be in
`get_allowed_docs_for_doctype` (`frappe/permissions.py:779`, →
`filter_allowed_docs_for_doctype`, `:784`). Tree doctypes get an ancestor walk
(`:388`–`:395`) using `_get_parent_and_ancestors` (`frappe/permissions.py:943`) and honouring
`hide_descendants`.

**Step 2 — every `Link` field** (`check_user_permission_on_link_fields`,
`frappe/permissions.py:416`), for the parent **and every child row**
(`:475`–`:477`):

```python
for field in meta.get_link_fields():
    if field.ignore_user_permissions: continue
    if not d.get(field.fieldname) and not apply_strict_user_permissions: continue
    if field.options not in user_permissions: continue
    allowed_docs = get_allowed_docs_for_doctype(user_permissions[field.options], doctype)
    if allowed_docs and str(d.get(field.fieldname)) not in allowed_docs:
        push_perm_check_log(msg); return False
```

Observations:

- **Cost is O(link fields × child rows).** A Sales Invoice with 200 lines, each with 8 link
  fields, is 1 600 membership tests per permission check, plus meta lookups per child doctype
  (`:422`).
- **`ignore_user_permissions` on a field disables the check entirely** for that field. It is a
  `DocField` property, therefore overridable by a `Property Setter` (doc 18 §1.1) — a security
  control that a business user can switch off through Customize Form.
- **Empty values pass by default.** `if not d.get(field.fieldname) and not
  apply_strict_user_permissions: continue` (`:428`–`:429`). So a document with `company = NULL`
  is visible to everyone unless `System Settings.apply_strict_user_permissions` is on — a
  **global** switch (doc 18 §3.1).
- Strict mode is further disabled for unsaved documents (`:369`–`:376`) and for Singles
  (`:363`–`:365`).
- The failure messages (`:436`–`:465`) name the offending field, row index, and value — precise,
  and again mildly disclosive.

`add_user_permission` (`frappe/permissions.py:591`),
`remove_user_permission` (`:619`), `clear_user_permissions_for_doctype` (`:628`),
`get_linked_doctypes` (`:748`), `has_any_user_permission_for_doctype`
(`frappe/model/db_query.py:1563`).

### 3.2 Query-level check

`add_user_permissions` (`frappe/model/db_query.py:1273`). For each link field (plus a synthetic
`name` field for the doctype itself, `:1277`–`:1283`):

```python
if apply_strict_user_permissions: condition = ""
else: condition = f"ifnull(`tabX`.`{fieldname}`, '')='' or "
...
condition += f"`tabX`.`{fieldname}` in ({values})"
match_conditions.append(f"({condition})")
...
self.match_conditions.append(" and ".join(match_conditions))
```

and in `build_match_conditions` (`frappe/model/db_query.py:1200`):

```python
conditions = "((" + ") or (".join(self.match_conditions) + "))"          # :1250
doctype_conditions = self.get_permission_query_conditions()
if doctype_conditions: conditions += " and " + doctype_conditions        # :1252-:1254
if not only_if_shared and self.shared and conditions:
    conditions = f"(({conditions}) or ({self.get_share_condition()}))"   # :1257-:1258
```

So the final `WHERE` fragment is a **string-concatenated** boolean expression combining
per-field `IN` lists, hook-supplied SQL, and an `IN` list of explicitly shared document names
(`get_share_condition`, `frappe/model/db_query.py:1267`).

`get_share_condition` inlines *every shared docname* into the query
(`frappe/share.py:170`, `get_shared`). For a user with thousands of shares, that is a
multi-thousand-element `IN` list appended to every list query.

If the user has neither `select` nor `read` and no user permission, the branch at
`frappe/model/db_query.py:1216`–`:1225` throws `PermissionError` unless something is shared, in
which case the query is restricted to shared names only (`only_if_shared`).

### 3.3 Hook-injected SQL

`get_permission_query_conditions` (`frappe/model/db_query.py:1332`):

```python
hooks = frappe.get_hooks("permission_query_conditions", {})
condition_methods = hooks.get(self.doctype, []) + hooks.get("*", [])
for method in condition_methods:
    if c := frappe.call(frappe.get_attr(method), self.user, doctype=self.doctype):
        if not isinstance(c, str): c = self._render_permission_criterion(c)
        conditions.append(c)
...
if permission_script_name := get_server_script_map().get("permission_query", {}).get(self.doctype):
    script = frappe.get_doc("Server Script", permission_script_name)
    if condition := script.get_permission_query_conditions(self.user, active_child_tables=...):
        conditions.append(condition)
return " and ".join(conditions)
```

Two escape hatches: a Python hook, and a **`Server Script` stored in the database** whose output
is a SQL string spliced into `WHERE`. `_render_permission_criterion`
(`frappe/model/db_query.py:1362`) handles pypika terms, and its docstring is candid about why
values are inlined with `frappe.db.escape` rather than pypika's quoting:

> …inline them with `frappe.db.escape` (the driver's escaping) rather than pypika's bare
> quote-doubling, which is unsafe on MariaDB where backslash is an escape character.

A security-critical predicate assembled by string concatenation, from user-editable database
rows, with hand-rolled escaping. This is the single largest reason we will not reproduce this
model.

---

## 4. Sharing

`frappe/share.py`. `add` (`:22`), `add_docshare` (`:49`), `remove` (`:93`),
`set_permission` (`:101`), `set_docshare_permission` (`:113`), `get_users` (`:151`),
`_get_users` (`:157`), `get_shared` (`:170`), `get_shared_doctypes` (`:204`),
`get_share_name` (`:218`), `check_share_permission` (`:231`),
`notify_assignment` (`:268`).

`DocShare` rows carry `read`, `write`, `submit`, `share`, `everyone`, `notify`. `everyone = 1`
shares with all users. Sharing composes as OR with roles (§2), and `get_shared` returns a list of
names that gets inlined into the query (§3.2).

`Document.check_no_back_links_exist` and `Document.add_seen`
(`frappe/model/document.py:2202`) / `add_viewed` (`:2219`) maintain `_seen`/`_liked_by`/
`_comments` — the `OPTIONAL_COLUMNS` that doc 18 §2.1 mentioned.

---

## 5. Field-level permissions

Two mechanisms:

**Permlevels.** `DocField.permlevel` (an integer) plus `DocPerm` rows at that permlevel.
`Meta.get_high_permlevel_fields` (`frappe/model/meta.py:678`),
`high_permlevel_fields` (`:683`), `get_permlevel_access` (`:730`),
`get_permitted_fieldnames` (`:686`), `get_fields_to_check_permissions` (`:662`).

Enforcement on write: `Document.validate_higher_perm_levels`
(`frappe/model/document.py:1312`), `get_permlevel_access` (`:1337`),
`has_permlevel_access_to` (`:1347`).

Enforcement on read: `Document.apply_fieldlevel_read_permissions`
(`frappe/model/document.py:1248`) and `DatabaseQuery.apply_fieldlevel_read_permissions`
(`frappe/model/db_query.py:850`). The latter **rewrites the select list**:

```python
permitted_fields = set(get_permitted_fields(doctype=..., parenttype=..., permission_type=..., ignore_virtual=True))
for i, field in reversed(list(enumerate(self.fields))):
    columns = extract_fieldnames(field)
    column = columns[0]
    if column == "*" and "*" in field:
        if not in_function("*", field): self.fields[i:i+1] = permitted_fields
        continue
    ...
```

It parses each requested field expression with `extract_fieldnames` and drops the ones the user
may not read (`remove_field`, `frappe/model/db_query.py:844`). Note it expands `*` into the
permitted set — so `SELECT *` returns different columns per user.

**Masked fields.** `Meta.get_masked_fields` (`frappe/model/meta.py:199`),
`Document.mask_fields` (`frappe/model/document.py:564`),
`_restore_masked_fields_from_db` (`frappe/model/document.py:1280`),
`reset_values_if_no_permlevel_access` (`frappe/model/base_document.py:1560`),
`DatabaseQuery.mask_fields` (`frappe/model/db_query.py:253`),
`get_masked_fields` (`:278`), `get_masked_joined_fields` (`:285`).

Masking replaces the value with a placeholder on read and must be **restored from the database on
write** (`_restore_masked_fields_from_db`) so that saving does not overwrite the real value with
the mask. That round-trip is the fragile part: any write path that does not restore first
persists the mask.

`Document._validate_update_after_submit` (`frappe/model/base_document.py:1346`) and
`validate_update_after_submit` (`frappe/model/document.py:1477`) enforce `allow_on_submit` —
which is how ERPNext legitimises the `db_set` writes to submitted documents documented in
Tranche A.

---

## 6. Where the model leaks

Every one of these is a real, exploited-in-practice bypass:

| Bypass | Where it appears | Effect |
|---|---|---|
| `ignore_permissions=True` on `insert`/`save`/`delete` | pervasive in ERPNext internals, e.g. `controllers/accounts_controller.py:352`, `:406`, `accounts/utils.py:562` | no role, user-permission, or share check |
| `frappe.db.sql(...)` / `frappe.qb` direct | e.g. `controllers/status_updater.py:550`–`:604`, `accounts/utils.py:1719`–`:1740` | bypasses `DatabaseQuery` entirely, so **no** `if_owner`, user permissions, share, or hook conditions |
| `frappe.db.get_value` / `get_all` with `ignore_permissions` | pervasive | same |
| `flags.ignore_permissions` on a document | `frappe/model/document.py` save path | same |
| `Property Setter` on `ignore_user_permissions` | doc 18 §1.1 + §3.1 above | disables user-permission checks on a link field |
| `Administrator` | `frappe/permissions.py:105` | everything |
| `Server Script` permission_query | §3.3 | user-editable SQL in `WHERE` |
| `flags.ignore_links` | doc 09 §5 | dangling references |

The consequence for us: **an application-level permission model cannot be trusted to protect
multi-tenant financial data**, because correctness depends on every one of thousands of call
sites remembering to route through the checked path. ERPNext's own internals routinely do not,
for good performance reasons.

---

## 7. Our design

Decision D2 said: multi-tenancy = `company_id` on every row **+ Row-Level Security +
company-scoped uniques**. This is where RLS gets specified.

### 7.1 Tenancy is enforced by the database

```sql
-- every business table
company_id uuid NOT NULL REFERENCES company(id),

ALTER TABLE gl_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE gl_entry FORCE ROW LEVEL SECURITY;   -- applies to the table owner too

CREATE POLICY gl_entry_tenant ON gl_entry
    USING      (company_id = ANY (current_company_ids()))
    WITH CHECK (company_id = ANY (current_company_ids()));
```

where `current_company_ids()` is a `STABLE` function reading a session GUC
(`app.company_ids`) set by the connection pool at request start from the authenticated
session, and validated against `user_company_access`:

```sql
CREATE TABLE user_company_access (
    user_id     uuid NOT NULL REFERENCES app_user(id),
    company_id  uuid NOT NULL REFERENCES company(id),
    granted_at  timestamptz NOT NULL DEFAULT now(),
    granted_by  uuid NOT NULL REFERENCES app_user(id),
    PRIMARY KEY (user_id, company_id)
);
```

Properties this buys that ERPNext cannot have:

- **`frappe.db.sql`-equivalent leaks are impossible.** A hand-written query, an ad-hoc report, a
  psql session opened by a support engineer using the application role — all are filtered.
  There is no "bypass the ORM" path, because the enforcement is below the ORM.
- **`FORCE ROW LEVEL SECURITY`** means even the table owner is subject to policy; only a
  separate migration role (used exclusively by the migration runner, doc 23) is `BYPASSRLS`.
- **`WITH CHECK`** prevents writing a row into another company — ERPNext has no equivalent
  concept at all.
- Company-scoped uniqueness is a plain composite index (`UNIQUE (company_id, doc_no)`), so two
  companies can both have invoice `INV-0001`. In ERPNext the string PK is global, which is why
  `Warehouse.autoname` appends the company abbreviation (doc 16 §4).

### 7.2 Rights are a closed, explicit model

```sql
CREATE TABLE app_role (
    id          uuid PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    label       text NOT NULL,
    is_system   boolean NOT NULL DEFAULT false
);
CREATE TABLE role_grant (
    id           uuid PRIMARY KEY,
    role_id      uuid NOT NULL REFERENCES app_role(id) ON DELETE CASCADE,
    resource     resource_kind NOT NULL,      -- enum of tables/aggregates, not free text
    action       action_kind NOT NULL,        -- 'read','create','update','delete','approve','post','reverse','export'
    effect       grant_effect NOT NULL,       -- 'allow','deny'   ← ERPNext has no deny
    scope        grant_scope NOT NULL,        -- 'all','own','company','warehouse','cost_center','team'
    scope_ref_id uuid,
    field_set_id uuid REFERENCES field_set(id),
    UNIQUE (role_id, resource, action, scope, coalesce(scope_ref_id,'00000000-0000-0000-0000-000000000000'))
);
CREATE TABLE user_role (
    user_id    uuid NOT NULL REFERENCES app_user(id),
    role_id    uuid NOT NULL REFERENCES app_role(id),
    company_id uuid REFERENCES company(id),   -- a role can be granted per company
    valid_from date NOT NULL DEFAULT '-infinity',
    valid_to   date NOT NULL DEFAULT 'infinity',
    PRIMARY KEY (user_id, role_id, coalesce(company_id,'00000000-0000-0000-0000-000000000000'))
);
```

Differences from `tabDocPerm` that matter:

- **`effect = 'deny'` exists.** Deny wins over allow. ERPNext's pure-OR union across roles
  (§2.1 point 1) cannot express "except", which is why User Permissions had to be invented as a
  second, differently-shaped mechanism. One mechanism, two effects, is simpler and more
  expressive.
- **`resource` and `action` are enums**, so a typo is a constraint violation rather than a
  silently-ineffective permission row.
- **`action` includes `approve`, `post`, and `reverse`** as first-class rights, matching our
  lifecycle (doc 09 §8). ERPNext has `submit`/`cancel`/`amend` and no `approve` — which is
  exactly why approval had to be bolted on three different ways (doc 09 §1.5).
- **Roles are grantable per company and effective-dated.** A user can be Accountant in Company A
  and read-only in Company B. In ERPNext roles are global and company restriction is a separate
  User Permission.
- **`scope = 'own'` replaces `if_owner`** and is applied as an RLS policy predicate, not as a
  doctype-level lie corrected at query time (§2.1 point 3). It therefore cannot be bypassed by
  a direct query.

### 7.3 Row scoping is policy, not string concatenation

Each `scope` maps to an RLS policy predicate, composed by the policy system, never by string
concatenation (§3.3):

```sql
CREATE POLICY sales_order_read ON sales_order FOR SELECT
    USING (
        company_id = ANY (current_company_ids())
        AND (
            has_grant('sales_order','read','all')
            OR (has_grant('sales_order','read','own')          AND owner_id = current_user_id())
            OR (has_grant('sales_order','read','cost_center')  AND cost_center_id = ANY (current_scope_ids('cost_center')))
            OR EXISTS (SELECT 1 FROM doc_share s
                       WHERE s.resource = 'sales_order' AND s.resource_id = sales_order.id
                         AND s.user_id = current_user_id() AND s.can_read)
        )
        AND NOT EXISTS (SELECT 1 FROM denied_grant d WHERE ...)
    );
```

`has_grant(...)` and `current_scope_ids(...)` are `STABLE` SQL functions over the session's
resolved grant set, cached per transaction. The planner sees real predicates and can use indexes;
there is no multi-thousand-element inlined `IN` list (§3.2).

Sharing becomes `doc_share (resource, resource_id, user_id, can_read, can_write, can_approve,
granted_by, granted_at, expires_at)` — with `expires_at`, which ERPNext's `DocShare` lacks.

### 7.4 Field-level access

```sql
CREATE TABLE field_set (
    id     uuid PRIMARY KEY,
    code   text NOT NULL UNIQUE,
    label  text NOT NULL
);
CREATE TABLE field_set_member (
    field_set_id uuid NOT NULL REFERENCES field_set(id) ON DELETE CASCADE,
    resource     resource_kind NOT NULL,
    column_name  text NOT NULL,
    PRIMARY KEY (field_set_id, resource, column_name)
);
```

Sensitive columns (cost prices, margins, salary) live in named field sets referenced by
`role_grant.field_set_id`. Enforcement is **column privileges plus views**:

- `GRANT SELECT (col, …) ON table TO role_x` for the simple cases — enforced by the database.
- A restricted **view** per field set for the cases needing computed masking, with the base table
  not granted at all.

This replaces permlevels (§5) and masked fields. The critical improvement: **there is no
read-mask-write round trip** (§5, `_restore_masked_fields_from_db`), because a user who cannot
read a column also cannot write it, and the column simply is not in their view. The class of bug
where a mask gets persisted as data cannot occur.

### 7.5 Approval authority is not a permission

Doc 09 §1.5 established that ERPNext expresses approval as "the approver must hold the role that
lets them submit". We separate them:

- `role_grant(action='approve')` says *who may act on an approval step*.
- `approval_policy` / `approval_policy_rule` says *which steps a document needs*, by
  document type, company, amount band, and dimension.
- `approval_event` records each act.

So a €1M invoice requires a director's `approve` event before its `post` transition is legal —
enforced by a trigger checking `approval_event` against `approval_policy_rule`, not by hoping the
director is the person who clicks the button. `Authorization Rule`'s value-band matching
(doc 09 §1.5(a)) is retained as `approval_policy_rule.amount_from`/`amount_to`, with an
`EXCLUDE` constraint preventing overlapping bands.

---

## 8. What we lose, and the residual risk

| We lose | Mitigation / residual risk |
|---|---|
| Per-doctype Python `has_permission` hooks | Business-rule access checks move into policy rows; genuinely procedural cases become explicit SQL functions in migrations, reviewed like any other code |
| `Server Script` permission queries | Deliberately removed. Runtime user-authored SQL in a security predicate is not acceptable |
| Permission changes taking effect instantly for all users | RLS predicates read the grant set through `STABLE` functions; a revoke takes effect on the next transaction. Acceptable |
| Frappe's `Permission Inspector` UX | We need an equivalent: an `explain_access(user, resource, resource_id)` function returning the matched grants and policies. Cheap to build, since grants are rows |
| Fine-grained sharing UI | `doc_share` covers it; the UI is small |
| **Residual risk: RLS is bypassed by the migration role** | The migration role is used only by the migration runner in CI/CD, never by the application or by humans; audited at the connection-pool level |
| **Residual risk: `SECURITY DEFINER` functions** | Any `SECURITY DEFINER` function is a potential bypass. Policy: they are enumerated in a registry table, reviewed, and must set `search_path` explicitly |

---

Cross-references: doc 09 §1.5 (approval), doc 18 (metadata, settings scoping),
doc 21 (hooks and overrides), doc 24 (reporting — the other big read path that must respect RLS),
doc 25 (platform spec), `docs/design/FINAL-SCHEMA.md`.
