# 51 — The Permission Model End to End

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

[Doc 50](50-authentication-session-and-tenant-context.md) established that there is no tenant context: company
is a data dimension, and the mechanism that narrows it is `User Permission`. [Doc 19](19-permissions-and-sharing.md)
catalogued the permission machinery. This document does the thing neither did — traces the **decision path** for
a single access check and asks, at each branch, *what happens when the rule is absent*.

The answer is the most consequential finding in the tranche: **the permission system fails open.** Absence of
a restriction is not "deny"; it is "allow everything". For company scoping specifically, a user with no
`User Permission` rows sees **every company in the database**.

Invariants continue from doc 50 at **T6**.

---

## 1. The decision path

`has_permission` is the entry point (`frappe/permissions.py:80-226`). In order:

```text
1  user defaults to frappe.session.user
2  if user == "Administrator":                    → return True          (total bypass)
3  if ptype == "share" and sharing disabled       → return False
4  if doctype is a child table                    → has_child_permission(...)
5  if a doc was supplied  → get_doc_permissions(doc)[ptype]
   otherwise              → get_role_permissions(meta)[ptype]
        + refuse "submit" on a non-submittable doctype
        + refuse "import" on a non-importable doctype
6  if still no permission → false_if_not_shared()  (sharing can GRANT)
7  if still none and ptype == "select" → recurse with ptype="read"
8  return bool(perm)
```

Step 2 is unconditional and first: **`Administrator` is allowed everything, everywhere, before any rule is
consulted.** Combined with doc 50 §7 finding 10 — `Administrator` is exempt from the `enabled` check — the
account is exempt from both authentication state and authorisation.

Step 6 is the second structural surprise. Sharing does not merely narrow; it **grants** a permission the role
system denied (`frappe/permissions.py:80-226`). The share rights are `read, write, share, submit, email, print`
plus any custom rights, and for a doctype-level check the existence of **at least one** shared document returns
`True` for the whole doctype — used deliberately by the query layer to decide doctype access.

Step 7 makes `select` a strictly weaker alias for `read`.

`get_doc_permissions` (`frappe/permissions.py:227-281`) combines role permissions, user permissions, owner
rules and controller hooks; `get_role_permissions` (`frappe/permissions.py:282-344`) resolves the role matrix
including `if_owner`.

> **Invariant T6 — authorisation is deny-by-default and total.** Every access decision starts from *deny* and
> requires an affirmative grant that names the principal, the company, the object class and the operation.
> No principal is exempt from evaluation, there is no identity for which the check short-circuits, and the
> absence of a rule is a denial rather than a grant.

---

## 2. Where it fails open

### 2.1 No rules means unrestricted

`has_user_permission` opens with (`frappe/permissions.py:351-380`):

```python
user_permissions = get_user_permissions(user)

if not user_permissions:
    # no user permission rules specified for this doctype
    return True
```

This is the mechanism ERPNext relies on for company separation. A user with **no `User Permission` rows at all
sees every company**, because the restriction list is empty and an empty restriction list means *unrestricted*.

The same shape recurs one level down. Within a doctype, `allowed_docs` is computed and then:

```python
if allowed_docs:
    ...   # only check when the list is non-empty
```

(`frappe/permissions.py:351-412`). An empty `allowed_docs` — the comment says "there is no applicable
permission under the current doctype" — skips the check entirely.

So company scoping is an **opt-in deny-list**, applied per user, and every gap in its configuration is a grant.
That is the opposite polarity from the boundary our schema assumes.

### 2.2 An empty field evades the check

Link-field checking has an explicit escape (`frappe/permissions.py:413-476`):

```python
for field in meta.get_link_fields():
    if field.ignore_user_permissions:
        continue
    if not d.get(field.fieldname) and not apply_strict_user_permissions:
        continue
```

Two independent bypasses in four lines:

1. **`ignore_user_permissions`** is a per-field flag on the DocField, so a field can be declared exempt from
   user permissions permanently; and
2. **an empty value skips the check** unless strict mode is on — so a document whose `company` is blank is not
   tested against the user's allowed companies at all.

### 2.3 Strict mode is off by default, and is switched off again for new documents

`apply_strict_user_permissions` is a System Setting, read per check, and forced to `False` for single doctypes
(`frappe/permissions.py:351-380`):

```python
apply_strict_user_permissions = strict and (
    False if doc.meta.issingle else frappe.get_system_settings("apply_strict_user_permissions")
)
```

Even when enabled, it is disabled again for a document that is still local — `__islocal`, `ptype` in
`("read", "write")`, and no persisted name (`frappe/permissions.py:351-395`):

```python
apply_strict_user_permissions = False
# "Strict permissions will be skipped on local document"
```

So the strictest available interpretation of company scoping is: off unless configured, off for singles, and
off while a document is being created — which is precisely when its `company` is being chosen.

### 2.4 The checks that only cover linked values

Even at its strongest, `has_user_permission` checks two things: the document's own name against the allowed
list for its doctype, and the **values of its link fields** (`frappe/permissions.py:351-476`). Child rows are
walked too (`doc.get_all_children(include_computed=True)`).

That is a genuinely thorough traversal — and it is still a check on *field values in a document the application
chose to load*. It cannot constrain a query the application built itself, which is doc 52's subject.

> **Invariant T7 — scope is proved by the row, not by the request.** A row is visible only when its
> `company_id` matches the session's company, evaluated by the database on every access. Visibility never
> depends on a link field being populated, on a per-field exemption, on a strictness setting, or on the
> application having loaded the document through a particular helper. A blank scope column is impossible
> because the column is `NOT NULL`.

---

## 3. What is genuinely well designed

Three mechanisms are better than what most systems ship, and we adopt them.

**Controllers may only deny.** `has_controller_permissions` is explicit
(`frappe/permissions.py:481-500`):

> Controllers can only deny permission, they can not explicitly grant any permission that wasn't already
> present.

It iterates `has_permission` hooks in **reverse** order and returns on the first falsy result. A monotone,
deny-only extension point is exactly the right shape for custom authorisation: it cannot be used to widen
access, so reviewing it is tractable.

**The permission decision is explainable.** `print_has_permission_check_logs`, `_debug_log`, `_pop_debug_log`
and `push_perm_check_log` (`frappe/permissions.py:43-79`, `frappe/permissions.py:798-805`) build a
human-readable trace of *why* a check failed, and the failure messages name the offending field, row index and
value (`frappe/permissions.py:413-476`). A permission system that can explain itself is a permission system
people configure correctly.

**Sharing is bounded by right type.** Only `read, write, share, submit, email, print` plus declared custom
rights are shareable, and `email`/`print` map down to `read` (`frappe/permissions.py:80-226`). Sharing cannot
manufacture an arbitrary permission — though it can grant the ones it covers, which §1 flagged.

`is_system_user` (`frappe/permissions.py:903-906`) and `check_doctype_permission`
(`frappe/permissions.py:907-923`) round out the surface; `get_allowed_docs_for_doctype` and
`filter_allowed_docs_for_doctype` (`frappe/permissions.py:779-797`) are the list helpers the query layer uses.

> **Invariant T8 — extension points may only narrow, and every decision is explainable.** Custom authorisation
> logic is monotone: it can deny an otherwise-granted operation and can never grant one. Every decision — allow
> or deny — produces a structured, storable trace naming the rule, the principal, the company, the object and
> the reason, and that trace is what an access review reads.

---

## 4. Evidence versus projection

| Representation | Classification |
|---|---|
| `DocPerm` / `Custom DocPerm` role matrix | configuration; the primary grant surface |
| `Role`, `Role Profile`, user→role links | configuration |
| `User Permission` rows | **opt-in deny-list**, absence = unrestricted |
| `apply_strict_user_permissions` | a setting that changes the polarity of §2.2 and §2.3 |
| `DocField.ignore_user_permissions` | permanent per-field exemption |
| `DocShare` rows | **grants**, not just narrowing |
| `has_permission` hooks | deny-only extension (good) |
| `if_owner` role rules | ownership-derived grant |
| permission debug log | ephemeral trace, not retained |
| `Administrator` | unconditional total bypass |
| `ignore_permissions=True` | 892 in-code bypasses (doc 50 §1) |

Note what is missing entirely: there is no record of an access **decision**. The debug trace is built for a
message and discarded, so "who was allowed to see what, and why" is not answerable after the fact.

---

## 5. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) and doc 50 §6. Grants are company-scoped; the principal
tables are global (doc 50 §6).

```sql
permission_role(id, company_id, code, name, description,
    is_assignable bool NOT NULL DEFAULT true)
   UNIQUE (company_id, code)

permission_grant(id, company_id, permission_role_id,
    object_class text NOT NULL,                    -- table or logical object class
    operation permission_operation_enum /*read|create|update|submit|cancel|amend|delete|
                                         export|print|share|report*/,
    field_scope text[] NULL,                       -- NULL = all fields; otherwise the allowed set
    row_predicate_id bigint NULL,                   -- optional additional narrowing (§5.1)
    granted_at, granted_by)
   UNIQUE (company_id, permission_role_id, object_class, operation)
   -- affirmative grants ONLY. There is no deny row, because the default is deny.

principal_role_assignment(id, company_id, principal_id, permission_role_id,
    assigned_at, assigned_by, expires_at timestamptz NULL,
    revoked_at timestamptz NULL, revoked_reason text NULL)
   UNIQUE (company_id, principal_id, permission_role_id) WHERE revoked_at IS NULL
   CHECK (expires_at IS NULL OR expires_at > assigned_at)
   -- an assignment may EXPIRE; a permanent grant is an explicit choice, not the only option

permission_row_predicate(id, company_id, code, object_class text,
    predicate_ast jsonb NOT NULL, predicate_hash char(64) NOT NULL,
    evaluator_version varchar(64) NOT NULL, state revision_state_enum)
   UNIQUE (company_id, code)
   -- a validated AST compiled into an RLS predicate; never user-supplied SQL and never eval'd text

permission_delegation(id, company_id, object_class, object_id bigint,
    from_principal_id, to_principal_id, operations permission_operation_enum[],
    reason text NOT NULL, granted_at, expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL)
   CHECK (expires_at > granted_at)
   CHECK (from_principal_id <> to_principal_id)
   -- this is "sharing", made honest: object-scoped, operation-scoped, time-boxed, reasoned, audited.
   -- It grants only operations the GRANTING principal already holds (deferred trigger).

access_decision(id, company_id, principal_id, auth_session_id,
    object_class text, object_id bigint NULL, operation permission_operation_enum,
    outcome decision_outcome_enum /*allowed|denied*/,
    basis decision_basis_enum /*role_grant|delegation|ownership|predicate|default_deny*/,
    permission_grant_id NULL, permission_delegation_id NULL, row_predicate_id NULL,
    decided_at timestamptz NOT NULL, trace jsonb)
   -- append-only. Adopts Frappe's explainability and makes it DURABLE, which is what turns an access
   -- review from an interview into a query. Sampling policy is configuration; denials are always kept.
```

### 5.1 How the layers compose

```text
company scope      : RLS on company_id = auth.current_company()      ← doc 50 §6.1, always, first
object + operation : permission_grant via a live principal_role_assignment
row narrowing      : permission_row_predicate compiled into an additional RLS predicate
field scope        : permission_grant.field_scope, enforced on read projection and write validation
delegation         : permission_delegation, additive but bounded by the grantor's own grants
extension          : deny-only hooks (T8); may subtract, never add
```

Three properties follow that the current model lacks:

1. **Removing configuration removes access.** An unassigned principal has no grants and therefore sees
   nothing — the polarity inversion of §2.1.
2. **A blank column cannot evade scope**, because `company_id` is `NOT NULL` and the comparison happens in the
   database (T7).
3. **There is no `Administrator`.** Elevated work is a time-boxed `delegation_grant` (doc 50 §6) or a role
   assignment with an `expires_at`, and both are audited. Break-glass is a recorded event, not an identity.

### 5.2 Ordering

```text
1 resolve the principal and session (doc 50); the session fixes company_id immutably
2 the database applies company RLS on every statement — no application involvement
3 the service resolves grants for (principal, company, object_class, operation)
4 apply row predicates as additional RLS, then field scope on projection
5 apply deny-only extension hooks
6 append access_decision (always for denials; per policy for allows)
7 execute
```

> **Invariant T9 — grants are managed, expiring, reviewable objects.** Role assignments and delegations carry
> an actor, a reason where elevated, and an expiry where not permanent. Every grant and revocation is an
> append-only fact, and the current authorisation state of any principal is a projection over them — so
> "who could do what, when" is answerable for any past instant.

---

## 6. Defects and risks

1. **Absence of `User Permission` rows means unrestricted access** — the company-scoping mechanism fails open
   (`frappe/permissions.py:351-380`).
2. **An empty `allowed_docs` list skips the check** (`frappe/permissions.py:351-412`).
3. **An empty link value skips the check** unless strict mode is on
   (`frappe/permissions.py:413-476`).
4. **`ignore_user_permissions` is a permanent per-field exemption**
   (`frappe/permissions.py:413-476`).
5. **`apply_strict_user_permissions` is off by default**, forced off for singles
   (`frappe/permissions.py:351-380`).
6. **Strict mode is switched off again for local documents** — exactly when `company` is being set
   (`frappe/permissions.py:351-395`).
7. **`Administrator` bypasses everything, first and unconditionally**
   (`frappe/permissions.py:80-226`).
8. **Sharing grants permissions the role system denied**, and one shared document grants doctype-level access
   (`frappe/permissions.py:80-226`).
9. **No access decision is recorded.** The explanatory trace is built for a message and discarded
   (`frappe/permissions.py:43-79`, `frappe/permissions.py:798-805`).
10. **Role assignments have no expiry** — nothing in the model retires a grant.
11. **892 in-code bypasses** (`ignore_permissions=True`), quantified in doc 50 §1.
12. **`select` silently aliases `read`**, so an interface that only needs selection receives read
    (`frappe/permissions.py:80-226`).

---

## 7. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Role → doctype → operation matrix | **Adopt** | `permission_role` + `permission_grant` |
| Permission levels (`permlevel`) for fields | **Change** | `field_scope` on the grant |
| `if_owner` rules | **Adopt** | ownership as a `basis`, expressed as a row predicate |
| `User Permission` as a deny-list | **Reject** | affirmative grants; absence denies |
| Empty rule list = unrestricted | **Reject** | empty = no access |
| Empty link value skips the check | **Reject** | `company_id NOT NULL` + database enforcement |
| `ignore_user_permissions` per field | **Reject** | no field is exempt from scope |
| `apply_strict_user_permissions` setting | **Reject** | strictness is not configurable |
| Strict mode skipped for new documents | **Reject** | scope is checked at creation, on the row |
| Child-row link traversal | **Adopt the thoroughness** | unnecessary once RLS applies to child tables too |
| `Administrator` total bypass | **Reject** | no exempt identity; break-glass is a time-boxed audited grant |
| Sharing that grants | **Change** | `permission_delegation`: object-scoped, operation-scoped, expiring, bounded by the grantor |
| One shared doc → doctype access | **Reject** | delegation is per object |
| Share rights bounded by type | **Adopt** | `operations[]` on the delegation |
| `disable_document_sharing` switch | **Adopt as policy** | delegation may be disabled per company |
| Controllers may only deny | **Adopt wholesale** | deny-only extension hooks (T8) |
| Reverse-order hook evaluation, first falsy wins | **Adopt** | same monotone semantics |
| Explainable permission failures | **Adopt and strengthen** | durable `access_decision` with a trace |
| Ephemeral debug trace | **Change** | denials always persisted; allows sampled by policy |
| `select` implied by `read` | **Change** | distinct operations; a selector grant does not confer read |
| `submit`/`import` capability checks | **Adopt** | object-class capability flags |
| `is_system_user` distinction | **Adopt** | `principal.kind` |
| Permanent role assignments | **Change** | optional `expires_at`, always revocable, always audited |

Invariants introduced here are **T6–T9**. Doc 52 continues at **T10** and turns T1, T7 and the 892 bypasses
into an adversarial test matrix.

---

Cross-references: [doc 19](19-permissions-and-sharing.md) (the machinery catalogue this traces),
[doc 50](50-authentication-session-and-tenant-context.md) (principals, sessions and the tenant-context
function these grants sit on top of), [doc 22](22-background-jobs-scheduling-and-locking.md) (jobs with no
session and therefore no principal), [doc 24](24-reports-dashboards-and-print.md) (post-hoc filtering in
reports — the same failure polarity at the query layer),
[doc 18](18-metadata-and-runtime-ddl.md) (`DocField.ignore_user_permissions` as metadata),
[doc 25](25-our-platform-spec.md) (four-layer rule), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 52 — tenant isolation under attack.
