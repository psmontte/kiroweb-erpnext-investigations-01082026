# 52 — Tenant Isolation Under Attack

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

[Doc 50](50-authentication-session-and-tenant-context.md) found there is no tenant context.
[Doc 51](51-permission-model-end-to-end.md) found the permission model fails open. This document asks the
adversarial question: **given a user legitimately logged into company A, by what routes can they reach company
B's rows?**

The answer is not one hole. It is that **the boundary is only ever applied at one layer, and that layer is
optional** — so the routes are better counted than listed. This document enumerates the classes, quantifies
each, and turns them into the test matrix our design has to survive.

Invariants continue from doc 51 at **T10**.

---

## 1. Where the check lives, and where it does not

There are two ways to read data in Frappe, and only one of them is guarded.

| Path | Permissions applied? |
|---|---|
| `frappe.get_doc` / `DatabaseQuery` (`frappe.get_list`, report view) | **yes** — role, user permission, share, `if_owner`, `permission_query_conditions` |
| `frappe.db.get_value` / `get_values` / `get_list` / `sql` | **no** — none, ever |

`frappe/database/database.py` exposes `sql` (`frappe/database/database.py:196-456`), `get_value`
(`frappe/database/database.py:533-610`), `get_values` (`frappe/database/database.py:611-727`) and a `get_list`
that is a thin passthrough (`frappe/database/database.py:842-850`). **None of them consults the permission
layer.** They are the ordinary way application code reads data, and they are unguarded by design — the guard
lives one layer up.

`DatabaseQuery` is the guarded path. It threads `ignore_permissions` from its constructor
(`frappe/model/db_query.py:124-200`), gates the read check on it
(`frappe/model/db_query.py:678-700`), gates filter construction on it
(`frappe/model/db_query.py:836-870`), and gates match conditions on it
(`frappe/model/db_query.py:1200-1250`). Where permissions *are* applied, the implementation is careful: it
handles `if_owner` constraints (`frappe/model/db_query.py:1659-1678`), only fetches shared documents when full
read access is absent (`frappe/model/db_query.py:1200-1250`), and checks whether any user permission exists for
a doctype at all (`frappe/model/db_query.py:1563-1573`).

So isolation in ERPNext is: *correct in one code path, absent in the other, and switchable off in the first.*

> **Invariant T10 — there is one enforcement layer, and it is the database.** Every read and write passes
> through row-level security bound to the session's company, regardless of which application helper issued it.
> A raw query, a report, a job, an export and a REST call are all subject to the same policy, because the
> policy is not in the application. No code path can opt out.

---

## 2. Attack class 1 — the in-code bypass

`ignore_permissions=True` appears **892 times**: 524 in Frappe, 368 in ERPNext. In ERPNext it concentrates where
you would least want it:

| Area | Occurrences |
|---|---:|
| `accounts/doctype/payment_request` | 21 |
| `stock/doctype/serial_and_batch_bundle` | 16 |
| `selling/doctype/sales_order` | 13 |
| `crm/doctype/appointment` | 13 |
| `stock/report/stock_ageing` | 10 |
| `setup` | 10 |
| `support/doctype/service_level_agreement` | 9 |
| `stock/doctype/stock_entry` | 9 |
| `accounts/doctype/pricing_rule` | 9 |
| `buying/doctype/purchase_order` | 8 |

Each is individually defensible — a controller writing a linked document the user cannot edit directly is a
normal pattern. Collectively they mean the permission layer is advisory: whether a given operation is checked
depends on which of 892 call sites the request happened to traverse.

`frappe.set_user` and `flags.ignore_permissions = True` add **34 more** call sites in ERPNext that change or
discard the acting identity mid-request.

**Under our design this class disappears entirely**, because there is no flag to pass. A controller that needs
to write a row the user cannot write must do so as a different *principal*, through an audited delegation
(doc 51 §5) — not by switching the check off.

---

## 3. Attack class 2 — code that runs with no user

This is the sharpest finding in the tranche.

`execute_job` initialises the site, connects, and then sets the user **only if one was passed**
(`frappe/utils/background_jobs.py:245-266`):

```python
if is_async:
    frappe.init(site, force=True, is_job=True)
    frappe.connect()
    ...
if user:
    frappe.set_user(user)
```

`frappe.connect()` ends with (`frappe/__init__.py:410-421`):

```python
if set_admin_as_user:
    set_user("Administrator")
```

So a job enqueued without an explicit user **runs as `Administrator`** — and doc 51 §1 established that
`has_permission` returns `True` for `Administrator` before any rule is evaluated. Every scheduled job, every
background task, and every enqueued handler that does not thread a user through is executing with total
authorisation over every company in the database.

The enqueue side does capture the caller: `frappe.session.user` is stored in the job kwargs
(`frappe/utils/background_jobs.py:180-190`). Whether it is *used* depends on each call site passing it on.

Doc 22 §2 documented job execution semantics; this is the security consequence. Everything Tranches A–F
specified as background work — BOM cost refresh, depreciation posting, e-invoice retry, GSTR-1 download,
projection rebuilds — sits in this class.

> **Invariant T11 — there is no unauthenticated execution context.** Every unit of work, interactive or
> background, executes as a named principal in a named company, resolved from a durable record. A job carries
> the principal and company that authorised it; a job that cannot resolve them fails and is recorded as failed.
> No execution path acquires elevated authority by omission, and there is no super-identity to fall back to.

---

## 4. Attack class 3 — reports and exports

`query_report.run` checks `frappe.has_permission(report.ref_doctype, "report")`
(`frappe/desk/query_report.py:248-300`), and `get_report_doc` checks the same
(`frappe/desk/query_report.py:25-60`). That is a **doctype-level** capability check. What follows is a Query
Report's own SQL, or a Script Report's Python — neither of which is subject to row-level filtering.

So a user who holds the `report` capability on a doctype can read every row of it, in every company, if the
report's SQL does not filter — and the report author, not the permission system, decides that. Doc 24 §5
documented the post-hoc filtering model; the isolation consequence is that reports are a parallel read path with
its own, weaker rules.

`Prepared Report` adds a second dimension: results are computed once and stored, then read back with
`frappe.has_permission("Prepared Report", "read", dn, throw=True)`
(`frappe/desk/query_report.py:275-300`). The stored result was computed under **some** user's scope and is
subsequently gated by permission on the *report artefact*, not by re-deriving row visibility.

The export path (`frappe/desk/reportview.py:388-540`) and the background export job
(`frappe/desk/reportview.py:421-427`) inherit whatever the query produced.

---

## 5. Attack class 4 — the whitelisted API surface

`frappe/client.py` is the REST surface, and it is thin. `get_list` (`frappe/client.py:26-77`), `get`
(`frappe/client.py:94-119`), `get_value` (`frappe/client.py:120-174`), `get_single_value`
(`frappe/client.py:175-182`), `set_value` (`frappe/client.py:183-228`), `insert`
(`frappe/client.py:229-238`), `insert_many` (`frappe/client.py:239-251`), `save`
(`frappe/client.py:252-264`), `submit` (`frappe/client.py:276-288`), `cancel`
(`frappe/client.py:289-300`), `delete` (`frappe/client.py:301-309`), `bulk_update`
(`frappe/client.py:310-328`), `rename_doc` (`frappe/client.py:265-275`).

These route through the guarded path, and the surface also *exposes the permission system itself* —
`has_permission` (`frappe/client.py:329-339`) and `get_doc_permissions`
(`frappe/client.py:340-350`) are whitelisted, which is useful for a client and also an efficient probe for an
attacker mapping what they can reach.

`get_password` is whitelisted (`frappe/client.py:351-367`), and `validate_link_and_fetch`
(`frappe/client.py:431-531`) is the endpoint that resolves link fields — a classic place for an
enumeration oracle, since it answers "does this name exist" for a doctype.

The count endpoints (`frappe/client.py:78-93`, `frappe/desk/reportview.py:58-101`) leak cardinality even when
rows are filtered, which is the standard blind-oracle shape.

---

## 6. Attack class 5 — the query layer's own edges

`DatabaseQuery` validates fields and filters against metadata
(`frappe/desk/reportview.py:129-161`, `frappe/desk/reportview.py:162-191`), parses SQL fragments
(`frappe/model/db_query.py:43-73`), and has explicit helpers for what counts as a plain field, a function call,
or an alias (`frappe/model/db_query.py:1685-1702`, `frappe/model/db_query.py:1692-1698`,
`frappe/model/db_query.py:1699-1703`). `group by` is set up separately
(`frappe/desk/reportview.py:192-208`), and child-table field references are resolved through
`get_parenttype_and_fieldname` (`frappe/desk/reportview.py:281-299`).

That is a real validation effort — and it is *parser-based validation of caller-supplied field expressions*,
which is a much harder problem than checking a row's company column. The reason it is hard is the same reason
our design does not need it: if the boundary is enforced on rows by the database, a caller cannot express a
field selection that escapes it.

---

## 7. The test matrix

This is the deliverable of the document. Every row must be *executed* against our implementation, not reviewed.

### 7.1 Read isolation

| # | Attempt | Required outcome |
|---:|---|---|
| R1 | `SELECT` a company-B row by primary key from a session scoped to A | 0 rows |
| R2 | Same, via every read helper the codebase offers | 0 rows, identically |
| R3 | Raw parameterised SQL naming the table directly | 0 rows |
| R4 | `COUNT(*)`, `MAX(id)`, `EXISTS` on company-B rows | no cardinality signal |
| R5 | Join from an A-visible row to a B-only row | join yields nothing |
| R6 | Child table read whose parent is in B | 0 rows |
| R7 | Read a B row through a link-field resolver | not found |
| R8 | Aggregate report over all companies | A-only totals |
| R9 | Stored/prepared report generated under B, read as A | denied |
| R10 | Export, print format and email rendering of a B row | denied |
| R11 | Read with a `NULL`/absent company on the row | impossible — column is `NOT NULL` |
| R12 | Attempt to set the tenant GUC directly as the application role | permission denied |
| R13 | Read after the session is revoked mid-transaction | 0 rows on next statement |
| R14 | Read with an expired session | denied |

### 7.2 Write isolation

| # | Attempt | Required outcome |
|---:|---|---|
| W1 | `INSERT` a row with `company_id = B` from an A session | refused by `WITH CHECK` |
| W2 | `UPDATE` an A row to set `company_id = B` | refused |
| W3 | `UPDATE`/`DELETE` a B row by key | 0 rows affected, and audited as a denial |
| W4 | Insert a child row under a B parent | refused |
| W5 | Post a voucher whose GL lines name B accounts | refused |
| W6 | Create a document that links to a B master | refused at FK + policy |
| W7 | Bulk operation mixing A and B rows | wholly refused, not partially applied |
| W8 | Cross-company transfer through the sanctioned path | permitted, and recorded as two scoped events (doc 53) |

### 7.3 Execution-context isolation

| # | Attempt | Required outcome |
|---:|---|---|
| X1 | Enqueue a job and inspect its acting principal | the enqueuing principal, never a super-identity |
| X2 | Run a scheduled job with no principal configured | job fails and is recorded as failed |
| X3 | Job reads rows | only the recorded company's rows |
| X4 | Retry after the enqueuing principal is revoked | refused |
| X5 | Projector/outbox worker | scoped per company; cannot span |
| X6 | Migration role | may span, and every use is an `auth_event` |
| X7 | Restore/import path | company-scoped, or explicitly authorised and audited |
| X8 | Webhook, integration and external callback | named service principal with a company |

### 7.4 Authorisation edges

| # | Attempt | Required outcome |
|---:|---|---|
| A1 | Principal with no role assignments | sees nothing (doc 51 §2.1 inverted) |
| A2 | Grant expires mid-session | next decision denies |
| A3 | Delegation used beyond the grantor's own rights | refused |
| A4 | Delegation after expiry | refused |
| A5 | Extension hook attempting to *grant* | structurally impossible (T8) |
| A6 | Field outside `field_scope` on read and on write | omitted on read, refused on write |
| A7 | Every denial | present in `access_decision` |

### 7.5 The property to state plainly

> **Invariant T12 — isolation is a tested property, not a reviewed one.** The matrix above is executed in CI
> against a two-company fixture for **every** business table, including child, ledger, projection, outbox, job
> and audit tables. A new table is not deployable until it appears in the matrix. Coverage is measured by
> enumerating tables from the catalogue and asserting each is exercised — the same generated-audit discipline
> `tools/coverage_audit.py` applies to documentation.

---

## 8. Target design additions

Docs 50 §6 and 51 §5 carry the identity and grant model. Isolation adds three things.

```sql
-- 1. Every business table, without exception, from the migration macro (§ top of FINAL-SCHEMA)
ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <t> FORCE ROW LEVEL SECURITY;
CREATE POLICY company_scope ON <t>
  USING      (company_id = auth.current_company())
  WITH CHECK (company_id = auth.current_company());
REVOKE UPDATE, DELETE ON <append_only_table> FROM app_role;

-- 2. A generated conformance check, so "every table" is verifiable rather than aspirational
CREATE VIEW rls_conformance AS
SELECT c.relname,
       c.relrowsecurity  AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid) AS has_policy,
       EXISTS (SELECT 1 FROM information_schema.columns col
               WHERE col.table_name = c.relname AND col.column_name = 'company_id'
                 AND col.is_nullable = 'NO')                        AS company_not_null
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r';
-- CI asserts: zero rows where NOT (rls_enabled AND rls_forced AND has_policy AND company_not_null),
-- excluding an explicit, reviewed allow-list of global reference tables (doc 50 §6, FINAL-SCHEMA §24).

-- 3. Denials are facts
isolation_denial(id, company_id NULL, principal_id NULL, auth_session_id NULL,
    attempted_object text, attempted_operation text, attempted_company_id bigint NULL,
    denied_at timestamptz NOT NULL, source denial_source_enum /*policy|grant|predicate|field_scope|
                                                               session_expired|no_context*/,
    detail jsonb)
   -- append-only; feeds alerting. A policy denial is a security event, not a 404 to be swallowed.
```

**Execution contexts** get explicit principals:

| Context | Principal |
|---|---|
| interactive request | the human principal, company from the session |
| API call | the service principal owning the credential |
| enqueued job | the enqueuing principal and company, recorded on the work row |
| scheduled job | a named service principal **per company**, configured, never implicit |
| projector / outbox worker | a service principal scoped to one company |
| migration | the migration role — the only one exempt, and every use audited |

> **Invariant T13 — the boundary is verifiable by construction.** A generated conformance check proves that
> every business table has a non-nullable scope column, row-level security enabled **and** forced, and a policy
> — with exceptions confined to a reviewed allow-list of global reference tables. Failing the check fails the
> build. Denials are recorded, aggregated and alerted on.

---

## 9. Defects and risks

1. **No tenant boundary exists** (doc 50 §1); isolation depends on the application filtering correctly.
2. **The database layer applies no permissions.** `sql`, `get_value`, `get_values`, `get_list` are unguarded
   (`frappe/database/database.py:196-456`, `frappe/database/database.py:533-610`,
   `frappe/database/database.py:611-727`, `frappe/database/database.py:842-850`).
3. **Background jobs default to `Administrator`** — total authorisation by omission
   (`frappe/utils/background_jobs.py:245-266`, `frappe/__init__.py:410-421`, doc 51 §1).
4. **892 in-code bypasses**, concentrated in payment, stock and order controllers (§2).
5. **34 identity switches** via `frappe.set_user` / `flags.ignore_permissions` in ERPNext.
6. **Reports are a parallel read path** gated by a doctype-level capability, with row filtering left to the
   report author (`frappe/desk/query_report.py:248-300`).
7. **Prepared Reports store results computed under one scope** and gate re-reads on the artefact
   (`frappe/desk/query_report.py:275-300`).
8. **Count endpoints leak cardinality** (`frappe/client.py:78-93`,
   `frappe/desk/reportview.py:58-101`).
9. **Link validation is an existence oracle** (`frappe/client.py:431-531`).
10. **The permission system is queryable through the API**, easing reconnaissance
    (`frappe/client.py:329-339`, `frappe/client.py:340-350`).
11. **Caller-supplied field expressions must be parsed and validated** — a hard problem the row-level boundary
    makes unnecessary (`frappe/model/db_query.py:43-73`,
    `frappe/desk/reportview.py:129-161`).
12. **`ignore_permissions` is threaded through the query layer as a parameter**, so any caller can disable the
    guard (`frappe/model/db_query.py:124-200`).

Genuinely good, and adopted: the `if_owner` constraint handling
(`frappe/model/db_query.py:1659-1678`), fetching shared documents only when full read access is absent
(`frappe/model/db_query.py:1200-1250`), field and filter validation against metadata
(`frappe/desk/reportview.py:129-191`), and the fact that the enqueuing user *is* captured in job kwargs
(`frappe/utils/background_jobs.py:180-190`) — the information needed to fix §3 is already there.

---

## 10. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Isolation by separate site/database | **Reject as our model** | one database, RLS-enforced companies |
| Permissions applied in `DatabaseQuery` only | **Reject** | database-enforced on every statement |
| Unguarded `db.get_value` / `sql` | **Reject** | no unguarded path exists |
| `ignore_permissions` parameter and flag | **Reject** | removed; elevated writes use an audited delegation |
| Jobs defaulting to `Administrator` | **Reject** | job carries its enqueuing principal and company, or fails |
| Capturing the enqueuing user in job kwargs | **Adopt and require** | recorded on the durable work row and enforced |
| Report capability at doctype level | **Adopt as a capability** | plus RLS, so report SQL cannot escape scope |
| Row filtering left to report authors | **Reject** | policy applies to report queries identically |
| Prepared Report result caching | **Change** | cached under a company; re-read re-derives scope |
| Count endpoints | **Change** | counts are scoped; no cardinality signal across companies |
| Link existence validation | **Change** | scoped resolution; no cross-company oracle |
| Whitelisted `has_permission` probe | **Change** | answers only within the caller's scope |
| Caller-supplied field expression parsing | **Adopt the validation** | kept as defence in depth, not as the boundary |
| `if_owner` query constraint | **Adopt** | a row predicate (doc 51 §5) |
| Shared-document fetch only without full read | **Adopt** | same optimisation over delegations |
| Field/filter validation against metadata | **Adopt** | same |
| No record of access decisions | **Reject** | `access_decision` + `isolation_denial` |
| No conformance test for scoping | **Reject** | generated `rls_conformance` check gates the build |

Invariants introduced here are **T10–T13**. Doc 53 continues at **T14** with multi-company, inter-company
documents and transfer pricing.

---

Cross-references: [doc 50](50-authentication-session-and-tenant-context.md) (why there is no context to bind
to), [doc 51](51-permission-model-end-to-end.md) (the fail-open polarity this exploits),
[doc 19](19-permissions-and-sharing.md) (`permission_query_conditions` and sharing),
[doc 22](22-background-jobs-scheduling-and-locking.md) (job execution semantics — §3 is its security
consequence), [doc 24](24-reports-dashboards-and-print.md) (report framework and post-hoc filtering),
[doc 15](15-intercompany-and-history-rewriting.md) (reposting, which runs as background work),
[doc 25](25-our-platform-spec.md) (four-layer rule), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 53 — multi-company, inter-company
documents and transfer pricing.
