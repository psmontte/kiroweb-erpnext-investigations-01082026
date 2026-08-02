# 50 — Authentication, Session Identity and Tenant Context

> **Tranche G opens here.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

Every tranche so far ended its schema with the same three lines: `company_id NOT NULL` on every business
table, `ENABLE ROW LEVEL SECURITY` plus `FORCE ROW LEVEL SECURITY`, and policies bound to an authenticated
tenant-context function. That boundary was **asserted eight times and never tested**. Tranche G tests it.

This document answers the first question it depends on: **how does a request acquire an identity, and what
scope does that identity carry?**

The answer reframes the whole tranche.

---

## 1. There is no tenant context

A search of the entire pinned Frappe tree for row-level security returns **nothing**:

```text
ROW LEVEL SECURITY   → 0 occurrences
current_setting(     → 1 occurrence, in a query-builder test asserting timezone SQL
                       (frappe/tests/test_query_builder.py:368)
```

Frappe has no row-level security, no tenant-context function, and no session-scoped database setting. This is
not an oversight — it is a different architecture:

| | Frappe's model | What we assumed |
|---|---|---|
| Tenant boundary | **one site = one database** | one database, many companies, RLS-enforced |
| Company | a **data dimension** filtered by `User Permission` | a tenant boundary enforced by the database |
| Enforcement point | the application, when it builds a query | the database, on every row access |
| Bypass | `ignore_permissions=True`, raw SQL | migration role only |

So multi-company in ERPNext is **multi-dimensional data in one trust domain**, not multi-tenancy. Two
companies in one site share every table, and separation depends entirely on the application remembering to
filter.

That has a measurable size. `ignore_permissions=True` — the flag that skips the permission layer entirely —
appears **524 times in Frappe and 368 times in ERPNext**: 892 call sites where the only enforcement mechanism
is deliberately switched off. Doc 52 turns that number into a test matrix.

> **Invariant T1 — the tenant boundary is in the database, not the application.** Company scope is enforced by
> row-level security policies that the application role cannot disable, evaluated against a tenant context the
> application role cannot forge. A missing or unresolvable tenant context denies access; it never widens it.
> No application code path, background job, report, raw query or administrative helper may bypass the policy,
> and there is no in-code flag that does.

---

## 2. How a request becomes a user

### 2.1 Two entry paths, one object

`LoginManager.__init__` branches on the request path (`frappe/auth.py:123-148`):

```text
if request.path == "/api/method/login":   → self.login()   ; resume = False
otherwise                                 → make_session(resume=True), get_user_info(), set_user_info()
    on AttributeError or DoesNotExistError → fall back to user "Guest"
```

Two properties of that fallback matter. First, an exception while resuming a session does not fail the
request — it **downgrades the caller to `Guest`** and proceeds. Second, the branch is chosen by comparing a
URL string, so the login flow is identified by its route rather than by an explicit intent.

`login()` refuses when `disable_user_pass_login` is set, clears the user's cache, authenticates, optionally
forces a password reset, runs 2FA when required, pops the password out of `form_dict`, then `post_login()`
(`frappe/auth.py:149-174`). `post_login` runs the `on_login` trigger, validates IP and hour, loads user info,
creates the session, builds boot caches and sets cookies (`frappe/auth.py:175-183`).

### 2.2 Credential verification

`authenticate` requires both user and password, rejects passwords over `MAX_PASSWORD_SIZE`, and delegates to
`User.find_by_credentials` (`frappe/auth.py:265-300`). Failure paths increment **two** independent trackers —
one keyed by request IP, one keyed by username — before failing with a deliberately generic
`"Invalid login credentials"` (`frappe/auth.py:265-300`, `frappe/auth.py:517-542`,
`frappe/auth.py:543-641`).

That is good practice: a uniform failure message, and per-IP as well as per-account lockout. Note one
deliberate subtlety — during an OTP check the **account** tracker is skipped so a successful 2FA does not
erase the tracker history, while the IP tracker still counts (`frappe/auth.py:265-300`).

`Administrator` is exempt from the `enabled` check (`frappe/auth.py:265-300`), so a disabled Administrator can
still authenticate.

### 2.3 Non-interactive authentication

`validate_auth` runs on every request (`frappe/auth.py:642-658`):

```text
header = Authorization.split(" ")
if len(header) == 2:
    validate_oauth(header)                 # bearer
    validate_auth_via_api_keys(header)      # basic or token
validate_auth_via_hooks()                   # app-supplied
if len(header) == 2 and session.user in ("", "Guest"):
    raise AuthenticationError
```

Both authenticators are attempted in sequence and **neither raises on non-match** — `validate_oauth` returns
early unless the scheme is `bearer` (`frappe/auth.py:660-708`) and `validate_auth_via_api_keys` swallows
`AttributeError`, `TypeError` and `ValueError` (`frappe/auth.py:709-734`). The final guard is what converts
"nobody authenticated you" into a failure, and it fires **only when an `Authorization` header was present**.
A request with no header simply proceeds as whatever the session says — usually `Guest`.

`validate_api_key_secret` compares the secret with `hmac.compare_digest` against a decrypted stored value, and
resolves the user from the key (`frappe/auth.py:735-763`). Three things are worth recording:

1. the API-key lookup filters on `enabled: True`, so a disabled user's key fails — but the comparison is
   `frappe.local.login_manager.user in ("", "Guest")` before `set_user`, so **an already-authenticated session
   silently wins over a supplied key** rather than the two being reconciled;
2. `Frappe-Authorization-Source` lets a **caller-supplied header choose the DocType** the key is looked up in
   (`frappe/auth.py:709-734`, `frappe/auth.py:735-763`) — the requester influences which table authenticates
   them; and
3. `validate_auth_via_hooks` executes every `auth_hooks` entry with no contract about what they may do
   (`frappe/auth.py:764-768`).

`validate_oauth` verifies scopes through the OAuth server and refuses a disabled user
(`frappe/auth.py:660-708`), but wraps the whole body in `except AttributeError: pass` — so an internal
attribute error during token verification is indistinguishable from "not an OAuth request".

> **Invariant T2 — authentication is explicit, total and fail-closed.** Every request resolves to exactly one
> authenticated principal through exactly one mechanism, chosen by server configuration and never by a
> caller-supplied header. A failure in any authenticator is a denial, never a silent downgrade to an anonymous
> principal and never a fall-through to a different mechanism. Anonymous access is an explicit, separately
> authorised principal, not the default outcome of an exception.

---

## 3. What a session is

### 3.1 Creation

`Session.__init__` takes the session id from `form_dict` or the `sid` cookie, defaulting to the literal
`"Guest"` (`frappe/sessions.py:210-245`). `start()` generates `frappe.generate_hash()` for a real user and the
constant `"Guest"` otherwise, then records user, IP, user agent, timestamps, expiry, full name and user type
(`frappe/sessions.py:256-310`).

Session data is written to the `Sessions` table **and** to the cache, then `frappe.db.commit()` is called
immediately (`frappe/sessions.py:311-330`).

**The session payload contains no company.** It carries `user`, `session_ip`, `user_agent`, `last_updated`,
`creation`, `session_expiry`, `full_name`, `user_type` and optionally `session_end` and `audit_user`
(`frappe/sessions.py:256-310`). There is no field in which a tenant scope could be stored, which is the
mechanical reason §1's conclusion holds: **there is nowhere for a tenant context to live.**

### 3.2 Resumption

`resume()` loads the record, updates local session data and re-validates the IP
(`frappe/sessions.py:331-345`). `get_session_record` falls back to `Guest` and clears cookies when no record
is found (`frappe/sessions.py:346-360`) — the same silent downgrade as §2.1, now on the session path.

`get_session_data_from_cache` computes elapsed time against `last_updated`, compares it to the expiry, also
honours an absolute `session_end`, and deletes the session when either is exceeded
(`frappe/sessions.py:371-395`). `get_session_data_from_db` reads `Sessions` filtered on
`lastupdate > get_expired_threshold()` (`frappe/sessions.py:396-420`).

So expiry is enforced in **two places with two mechanisms** — a computed difference in the cache path and a
SQL predicate in the database path — and the cache is consulted first.

### 3.3 Concurrency and CSRF

`clear_active_sessions` terminates a user's other sessions **only** when `deny_multiple_sessions` is set, and
forces the clear for everyone except `Administrator` (`frappe/auth.py:249-264`). By default concurrent
sessions are unlimited.

CSRF tokens are generated per session and exposed through `get_csrf_token` / `generate_csrf_token`
(`frappe/sessions.py:197-209`).

Expiry configuration resolves through `get_expiry_period_for_query`, `get_expiry_in_seconds`,
`get_expired_threshold` and `get_expiry_period` (`frappe/sessions.py:499-530`).

> **Invariant T3 — a session is a scoped, bounded, revocable capability.** A session record binds the
> principal, the tenant scope it may act in, its issue and absolute expiry instants, and its binding evidence
> (address and agent). Scope is fixed at issue: a session cannot widen it, and a change of scope is a new
> session. Expiry is evaluated by one rule in one place, with the cache as a strict subset of the durable
> record, and revocation is immediate and total across both.

---

## 4. Where company scope actually comes from

Since the session has no company, ERPNext resolves it per request from three weaker sources:

| Source | Mechanism |
|---|---|
| **User Permission** rows | filter `company` values a user may see, applied when a query is built (`frappe/permissions.py:345-360`) |
| **Global/session defaults** | a default company written per user, read as a form default |
| **The document itself** | whatever `company` the caller submitted |

Doc 19 covered the permission machinery; what matters here is the **enforcement point**. `User Permission`
narrows queries the framework constructs. It does not constrain a raw `frappe.db.sql`, and it is skipped
wholesale by `ignore_permissions=True`. `apply_strict_user_permissions` exists as a System Setting to make the
check stricter (`frappe/permissions.py:361-375`), which is itself an admission that the default is permissive.

`get_logged_user` is the canonical accessor for identity (`frappe/auth.py:464-467`); there is no equivalent
`get_current_company` at the framework layer, because company is not a framework concept.

**Consequence for our design.** We cannot adopt this model and then claim tenant isolation. Two changes are
structural rather than incremental:

1. the tenant scope must be **part of the authenticated principal's session**, established at authentication
   and immutable thereafter; and
2. enforcement must move into the **database**, so that a query nobody remembered to filter returns nothing
   rather than everything.

---

## 5. Evidence versus projection

| Representation | Classification |
|---|---|
| `User` record and its password hash | credential authority |
| `Sessions` row | durable session record — **no tenant scope** |
| session cache entry | authoritative-in-practice copy, consulted first |
| `sid` cookie | bearer capability, no scope binding |
| API key / secret on `User` | long-lived credential, no scope, no expiry |
| OAuth bearer token + scopes | scoped capability — the only scoped mechanism present |
| `Frappe-Authorization-Source` header | **caller-supplied** selection of the authenticating table |
| `User Permission` rows | query-narrowing filter, not a boundary |
| `apply_strict_user_permissions` | a setting that changes how strict the filter is |
| `ignore_permissions=True` | in-code bypass, 892 call sites |
| login attempt trackers | rate-limit state, per IP and per account |
| `Activity Log` / `Access Log` | audit projections (doc 51, doc 52) |

Nothing here binds an identity to a tenant, and the one genuinely scoped mechanism — OAuth scopes — is about
API surface, not data.

---

## 6. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Every table is `company_id`-scoped with RLS and
`FORCE RLS` **except** the principal/identity tables themselves, which are global and are the roots the
policies read from.

```sql
principal(id, kind principal_kind_enum /*human|service|integration*/, code, name,
    state principal_state_enum /*active|suspended|retired*/, created_at, created_by)
   UNIQUE (code)                                                          -- [GLOBAL]

principal_credential(id, principal_id, credential_kind credential_kind_enum
        /*password|totp|webauthn|api_key|oauth_client*/,
    secret_ref text NOT NULL,            -- reference into the secret store; never the secret
    algorithm text, params jsonb,
    issued_at timestamptz, expires_at timestamptz NULL, rotated_from_id bigint NULL,
    revoked_at timestamptz NULL, revoked_reason text NULL)
   UNIQUE (principal_id, credential_kind, issued_at)
   CHECK (expires_at IS NULL OR expires_at > issued_at)
   -- API keys are credentials with an EXPIRY and a rotation chain, not permanent fields on a user

principal_company_membership(id, principal_id, company_id,
    granted_at timestamptz, granted_by, revoked_at timestamptz NULL, revoked_reason text NULL)
   UNIQUE (principal_id, company_id) WHERE revoked_at IS NULL
   -- THE tenancy fact. RLS policies resolve through this table and nothing else.

auth_session(id, principal_id, company_id NOT NULL,
    session_token_hash char(64) NOT NULL, issued_at timestamptz NOT NULL,
    absolute_expires_at timestamptz NOT NULL, idle_expires_at timestamptz NOT NULL,
    bound_address inet, bound_agent_hash char(64),
    auth_method auth_method_enum /*password|password_totp|webauthn|api_key|oauth|delegated*/,
    assurance_level smallint NOT NULL,
    revoked_at timestamptz NULL, revoked_reason text NULL)
   UNIQUE (session_token_hash)
   CHECK (absolute_expires_at > issued_at AND idle_expires_at <= absolute_expires_at)
   -- company_id is NOT NULL and IMMUTABLE: a session acts in exactly one company. Switching company
   -- issues a NEW session, so no request can widen its own scope.
   -- L2 trigger: (principal_id, company_id) must have a live principal_company_membership at issue.

auth_event(id, principal_id NULL, company_id NULL, event_code auth_event_enum
        /*login_success|login_failure|lockout|logout|session_expired|session_revoked|
          credential_rotated|scope_denied|impersonation_started|impersonation_ended*/,
    occurred_at timestamptz NOT NULL, address inet, agent_hash char(64),
    auth_method auth_method_enum NULL, detail jsonb)
   -- append-only; the audit spine doc 52 reconciles isolation tests against

auth_throttle(id, subject_kind throttle_subject_enum /*address|principal|credential*/,
    subject_key text, window_start timestamptz, failures integer,
    locked_until timestamptz NULL)
   UNIQUE (subject_kind, subject_key, window_start)
   -- keeps Frappe's genuinely good two-axis lockout (per IP and per account)

delegation_grant(id, company_id, from_principal_id, to_principal_id,
    reason text NOT NULL, granted_by, granted_at, expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL)
   CHECK (expires_at > granted_at)
   CHECK (from_principal_id <> to_principal_id)
   -- support impersonation is an authorised, time-boxed, audited grant — never a session swap
```

### 6.1 The tenant-context function RLS actually binds to

The policy shape fixed earlier in `FINAL-SCHEMA` reads a tenant context function rather than a raw setting.
This is that function:

```sql
-- Transaction-local, set ONLY through a narrowly granted SECURITY DEFINER entry point that
-- validates the session token against auth_session and its membership. The application role has
-- no privilege to set app.session_token directly.
CREATE FUNCTION auth.current_company() RETURNS bigint
LANGUAGE sql STABLE AS $$
  SELECT s.company_id
  FROM auth_session s
  WHERE s.session_token_hash = auth.current_session_hash()
    AND s.revoked_at IS NULL
    AND now() < s.absolute_expires_at
    AND now() < s.idle_expires_at
$$;
```

Three properties are load-bearing:

- it returns **`NULL` when anything is wrong** — no session, revoked, expired — and every policy compares
  `company_id = auth.current_company()`, so `NULL` yields **zero rows** rather than all rows;
- it reads the **durable** session table, so revocation is immediate and a cache cannot outlive it; and
- the session's `company_id` is immutable, so a request cannot widen its own scope mid-transaction.

### 6.2 Authentication ordering

```text
1 resolve the mechanism from SERVER configuration and the route — never from a caller header
2 verify the credential (constant-time), consult auth_throttle for address and principal
3 on failure: append auth_event, increment throttles, DENY — never downgrade to anonymous
4 verify the principal is active and has a live membership for the requested company
5 issue auth_session with company_id, absolute and idle expiry, binding evidence, assurance level
6 append auth_event(login_success) ; return the token
7 every subsequent request: set transaction-local context via the SECURITY DEFINER entry point,
  which re-reads auth_session; RLS then applies with no application involvement
```

Anonymous access is a named principal with its own membership rows, so a public endpoint is *authorised*
rather than *unauthenticated*.

> **Invariant T4 — credentials are managed objects.** Every credential has an issue instant, an expiry, a
> rotation chain and a revocation record; none is a permanent field on a user row. Secrets are referenced, never
> stored inline. Elevation and impersonation are time-boxed authorised grants with a recorded reason, and both
> the grant and its use are audited.

> **Invariant T5 — authentication and scope decisions are append-only facts.** Every success, failure,
> lockout, expiry, revocation, scope denial and impersonation is an immutable `auth_event`. Isolation claims are
> proved by reconciling those events against attempted access, which is what makes doc 52's adversarial matrix
> checkable rather than aspirational.

---

## 7. Defects and risks

1. **No tenant isolation mechanism exists.** No RLS, no tenant context, no session scope; company is a data
   dimension (§1, `frappe/tests/test_query_builder.py:368` is the only `current_setting` in the tree).
2. **892 permission bypasses.** `ignore_permissions=True` — 524 in Frappe, 368 in ERPNext.
3. **Session resumption failure downgrades to `Guest`** rather than failing
   (`frappe/auth.py:123-148`, `frappe/sessions.py:346-360`).
4. **The authenticating DocType is chosen by a caller-supplied header**, `Frappe-Authorization-Source`
   (`frappe/auth.py:709-734`, `frappe/auth.py:735-763`).
5. **Authenticators swallow exceptions**, so an internal error is indistinguishable from a non-match
   (`frappe/auth.py:660-708`, `frappe/auth.py:709-734`).
6. **The fail-closed guard only fires when an `Authorization` header was present**
   (`frappe/auth.py:642-658`).
7. **A supplied API key is ignored when a session already exists** rather than reconciled
   (`frappe/auth.py:735-763`).
8. **API keys have no expiry and no rotation chain** — they are fields on `User`
   (`frappe/auth.py:735-763`).
9. **`auth_hooks` run arbitrary app code inside authentication** with no contract
   (`frappe/auth.py:764-768`).
10. **`Administrator` bypasses the `enabled` check** (`frappe/auth.py:265-300`).
11. **Concurrent sessions are unlimited by default**; the limit is a setting, and forced clearing exempts
    `Administrator` (`frappe/auth.py:249-264`).
12. **Expiry is enforced twice by two mechanisms**, cache-first
    (`frappe/sessions.py:371-395`, `frappe/sessions.py:396-420`).
13. **The session record carries no scope**, so there is nowhere for tenant context to live
    (`frappe/sessions.py:256-310`).
14. **`apply_strict_user_permissions` is opt-in**, so the default filter is the permissive one
    (`frappe/permissions.py:361-375`).

Genuinely good, and adopted: the uniform failure message, the **two-axis** lockout (IP and account), the
password-size bound, constant-time secret comparison, IP validation on both login and resume, absolute
`session_end` alongside idle expiry, and per-session CSRF tokens.

---

## 8. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| One site per tenant | **Reject as our model** | one database, many companies, RLS-enforced |
| Company as a data dimension | **Change** | company is the tenant boundary; dimensions are additional |
| `User Permission` query narrowing | **Change** | RLS policies; user permissions become an additional narrowing layer |
| `ignore_permissions=True` | **Reject** | no bypass exists; the migration role alone is exempt |
| Uniform "invalid credentials" message | **Adopt** | same |
| Two-axis lockout (IP + account) | **Adopt** | `auth_throttle` with both subject kinds |
| Password size bound | **Adopt** | same |
| `hmac.compare_digest` for secrets | **Adopt** | constant-time comparison, secrets referenced not stored |
| 2FA with TOTP/SMS/email | **Adopt** | credential kinds with an assurance level on the session |
| Password-reset forcing | **Adopt** | credential expiry drives it |
| IP validation on login and resume | **Adopt** | session binding evidence |
| Route-based detection of the login flow | **Change** | explicit intent, not a URL comparison |
| Resume failure → `Guest` | **Reject** | failure denies |
| Missing `Authorization` → proceed | **Reject** | every request resolves a principal; anonymous is a named one |
| `Frappe-Authorization-Source` | **Reject** | mechanism chosen by server configuration |
| Swallowed authenticator exceptions | **Reject** | an error denies and is audited |
| Session-wins-over-key precedence | **Reject** | one mechanism per request, reconciled or refused |
| API keys as permanent user fields | **Reject** | `principal_credential` with expiry and rotation |
| OAuth scopes | **Adopt and extend** | scopes for API surface; company for data |
| `auth_hooks` | **Reject** | no arbitrary code inside authentication |
| `Administrator` exempt from `enabled` | **Reject** | no principal is exempt |
| Unlimited concurrent sessions | **Change** | policy-bounded, revocable, enumerable |
| Cache-first expiry | **Change** | one rule; cache is a strict subset of the durable record |
| Session in cache **and** table | **Adopt/Change** | durable record authoritative, cache advisory |
| Per-session CSRF token | **Adopt** | same |
| `deny_multiple_sessions` as a setting | **Adopt as policy** | per-principal-kind session policy |
| Login/logout endpoints | **Adopt** | plus explicit scope selection at issue |
| Impersonation by session swap | **Reject** | `delegation_grant`, time-boxed and audited |

Invariants introduced here are **T1–T5**. Doc 51 continues at **T6** with the permission model end to end,
and doc 52 turns T1 into an adversarial test matrix.

---

Cross-references: [doc 19](19-permissions-and-access-control.md) (roles, user permissions, sharing, field-level
permissions — the machinery this document places in context), [doc 20](20-naming-identity-and-audit-trail.md)
(audit trail and log family), [doc 22](22-background-jobs-scheduling-and-locking.md) (jobs run **without a
session** — a direct problem for T1, taken up in doc 52),
[doc 24](24-reporting-framework.md) (post-hoc permission filtering in reports),
[doc 25](25-our-platform-spec.md) (the four-layer rule and platform build/buy/drop decisions),
[doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) and
[doc 49](49-tranche-f-closure-and-our-localisation-spec.md) (GST credential storage, deferred to this tranche),
and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 51 — the permission model end to end.
