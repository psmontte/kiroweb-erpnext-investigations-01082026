# 57 — Tranche G Closure and Our Security, Tenancy and Group Specification

> **Tranche G deliverable.** This closes the security, tenancy and group-reporting investigation and
> consolidates docs [50](50-authentication-session-and-tenant-context.md)–[56](56-consolidation-and-group-reporting.md)
> into the backend/database contract we will build.
>
> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55`.
> ERPNext citations are relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are prefixed
> `frappe/`; India Compliance citations are prefixed `india_compliance/`.

This is a specification, not an implementation report. **Application implementation has not started.** The
security and group design extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) with new sections after §28;
it does not supersede the accounting, stock, trade, production, quality, asset or localisation guarantees
already fixed there and in [doc 25](25-our-platform-spec.md),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md),
[doc 44](44-tranche-c-closure-and-our-asset-spec.md) and
[doc 49](49-tranche-f-closure-and-our-localisation-spec.md).

---

## 1. What this tranche measured

Every tranche before this one asserted the same four words about every table it specified: `company_id`,
`ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, and a policy bound to authenticated tenant context.
Twenty-three schema sections were written on that assumption. **None of them tested it, and none of them said
where the tenant context comes from.**

Tranche G is the tranche that closes the assumption. Its subject is not a functional module; it is the
foundation the other twenty-three sections stand on, plus the three group-level capabilities that turn a
multi-company database into group financial statements.

| | |
|---|---|
| Subject | authentication, sessions, tenant context, authorisation, isolation under attack, multi-company, multi-currency, multi-location, consolidation |
| Documents | 50 (identity and context), 51 (authorisation end to end), 52 (isolation under attack), 53 (group structure and crossings), 54 (currency layering), 55 (dimensions of place), 56 (consolidation) |
| Primary tree | `frappe/` for docs 50–52; `erpnext` for docs 53–56; `india_compliance/` for the statutory place seam (doc 55 §5) |
| Invariants | **T1–T30** |
| Defects catalogued | **84** across the seven documents |
| Scenario | [S13](../scenarios/S13-cross-company-consolidation-and-isolation.md) |

The measured result of the tranche is a single sentence, and it is the reason the tranche exists:

> **There is no tenant isolation mechanism in the pinned tree.** No row-level security, no tenant context
> function, no scope on the session record. The only occurrence of `current_setting` in either repository is
> in a query-builder test (`frappe/tests/test_query_builder.py:368`). Company is a data dimension that the
> application is expected to filter on, and there are **892** places where the filtering is switched off
> (`ignore_permissions=True`: 524 in Frappe, 368 in ERPNext).

ERPNext's DocType coverage matrix is unchanged and remains closed: **203 parents, 178 cited, zero uncited
submittable, zero uncited configuration, 25 recorded exclusions** ([`COVERAGE.md`](../COVERAGE.md)). Tranche G
adds no new ERPNext parents — docs 50–52 read Frappe framework modules, and docs 53–56 read controllers and
reports under parents already counted.

### 1.1 Why the boundary had to be closed before implementation, not after

Two of the tranche's findings are not defects that can be patched later; they are properties of the shape of
the system, and retrofitting either one is a rewrite.

- **Scope enforcement lives at L3/L4 and fails open.** `get_user_permissions` returning no rows means
  *unrestricted*, not *nothing* (`frappe/permissions.py:351-380`). A blank link value skips the check unless
  strict mode is on, and strict mode is off by default and switched off again for local (unsaved) documents —
  precisely when `company` is being set (`frappe/permissions.py:413-476`,
  `frappe/permissions.py:351-395`). A boundary whose default outcome is *allow* cannot be made safe by adding
  rules; the polarity has to be inverted, which means moving it to L2.
- **There is no execution context for anything that is not an interactive request.** Background jobs default
  to `Administrator` (`frappe/utils/background_jobs.py:245-266`, `frappe/__init__.py:410-421`), which is total
  authorisation acquired by omission. Every projection, every scheduled revaluation, every submission retry
  and every consolidation run in our design is background work. If the execution context is not part of the
  durable work row from the first migration, half the system runs outside the boundary.

Everything in §4 follows from replacing those two with one idea: **the boundary is a database policy over a
non-forgeable context, and nothing runs without one.**

---

## 2. Governing security and group model

The four-layer rule from [doc 25 §2](25-our-platform-spec.md#2-the-layering-rule) applies unchanged. Tranche G
adds six consequences.

1. **The tenant boundary is L2, and the application role cannot lift it.** Every business table carries
   `company_id NOT NULL`, has row-level security **enabled and forced**, and has a policy evaluated against
   `auth.current_company()`. The application role holds neither `BYPASSRLS` nor table ownership. There is no
   `ignore_permissions` equivalent anywhere in the design, because there is nothing for it to switch off.
2. **The context is set from a durable record, never from the request.** `auth.current_company()` reads a
   session-local setting written only by the connection-establishment routine after resolving an `auth_session`
   row. An unresolvable context returns no company and every policy denies. A caller-supplied header can
   influence nothing.
3. **Authorisation is a second, additive layer that also starts at deny.** RLS answers *which rows*;
   `permission_grant` answers *which operations on which object classes*. Both must say yes. Neither has an
   exempt identity: there is no `Administrator`, and break-glass is a time-boxed `delegation_grant` with a
   recorded reason, an actor, an expiry and an audit trail on both the grant and each use.
4. **Every decision is a fact.** `auth_event` records authentication, scope and delegation outcomes;
   `access_decision` records authorisation outcomes with a structured trace; `isolation_denial` records policy
   refusals for aggregation and alerting. All three are append-only. This is what makes doc 52's matrix
   checkable rather than aspirational, and what makes "who could do what, at 14:03 last Tuesday" answerable.
5. **A group is modelled structure, and crossing it is one fact.** `company_group_edge` carries ownership
   percentage, consolidation method, elimination policy and effective period per edge. An inter-company
   transaction is one immutable `intercompany_transaction` with two legs that agree exactly by deferred
   constraint. Reading across companies is not an ordinary report permission; it is an explicit group-scoped
   grant.
6. **Currency has three named layers and only two of them are stored.** Transaction currency and amount,
   functional currency and amount, and the **identity** of the rate row used to convert between them, are on
   every monetary fact. Presentation currency is derived by a stored `translation_run`; it is never a column
   on a fact, and a company's functional currency is frozen once any posted fact exists in it.

All Tranche G tables follow the established conventions: money `numeric(19,4)`, rates and percentages
`numeric(9,6)`, quantities `numeric(21,9)`, persisted codes as stable lower-case enum codes rather than
display text. Two categories are deliberately exempt from company scope and appear on the reviewed allow-list
that T13's conformance check reads: global reference data (currencies, countries, jurisdiction areas) and the
`principal` table itself, which is group-wide by definition and scoped through `principal_company_membership`.

---

## 3. T1–T30: exact register and enforcement owner

Names are preserved exactly from docs 50–56.

| ID | Exact invariant name | Primary enforcement |
|---|---|---|
| T1 | the tenant boundary is in the database, not the application | L2 forced RLS on every business table, bound to `auth.current_company()`; L1 `company_id NOT NULL` |
| T2 | authentication is explicit, total and fail-closed | L4 one server-configured authenticator, denial on any error; L1 `principal` + `principal_credential` |
| T3 | a session is a scoped, bounded, revocable capability | L1 `auth_session` with scope, `issued_at`, `absolute_expiry_at`, binding evidence; L2 one expiry rule, immediate revocation |
| T4 | credentials are managed objects | L1 `principal_credential` with issue/expiry/rotation chain/revocation + `delegation_grant`; secrets referenced, never inline |
| T5 | authentication and scope decisions are append-only facts | L1 `auth_event` + L2 immutability trigger |
| T6 | authorisation is deny-by-default and total | L1 affirmative `permission_grant` rows; L4 evaluator with no exempt identity and no short circuit |
| T7 | scope is proved by the row, not by the request | L1 `company_id NOT NULL`; L2 RLS policy on every access |
| T8 | extension points may only narrow, and every decision is explainable | L4 monotone deny-only hooks; L1 `access_decision` with a structured trace |
| T9 | grants are managed, expiring, reviewable objects | L1 `permission_assignment` / `permission_delegation` with `expires_at`, actor, reason; append-only revocation |
| T10 | there is one enforcement layer, and it is the database | L2 `FORCE ROW LEVEL SECURITY`; application role without `BYPASSRLS` or ownership |
| T11 | there is no unauthenticated execution context | L1 durable work rows with `principal_id` and `company_id` both `NOT NULL`; L3 claim sets context or fails the job |
| T12 | isolation is a tested property, not a reviewed one | CI matrix generated from the table catalogue; a table absent from the matrix is not deployable |
| T13 | the boundary is verifiable by construction | L1/L2 generated `rls_conformance` view + build gate; `isolation_denial` aggregation and alerting |
| T14 | a group is a modelled structure, not a naming convention | L1 `company_group` + `company_group_edge` with per-edge period exclusion constraints |
| T15 | the counterparty of a crossing is identified, never inferred | L1 `intercompany_relationship` unique per ordered company pair and period |
| T16 | transfer price is a policy, and both sides agree exactly | L1 `transfer_price_policy_revision` with approved-range exclusion; L2 deferred leg-agreement constraint |
| T17 | a crossing is one fact with two legs | L1 immutable `intercompany_transaction`; L2 deferred two-leg agreement on quantity, price, currency and date |
| T18 | intra-group margin is tracked to realisation | L1 `unrealised_margin` + `unrealised_margin_realisation` events; group profit derived, never parked |
| T19 | three currency layers, each named and each recorded | L1 currency/amount/rate-identity columns on every monetary fact; L2 trigger freezing functional currency once posted |
| T20 | a rate is a dated, sourced, non-zero fact, and its absence is a refusal | L1 `exchange_rate` `CHECK (rate > 0)` + FK to `rate_source`; L2 resolution function refuses on absence or staleness |
| T21 | revaluation and translation are distinct, both are dated facts | L1 `translation_run` / `translated_balance` / `translation_adjustment` alongside revaluation rows |
| T22 | conversion is reproducible for any past instant | L1 append-only superseding rate rows, effective-dated pegs, rate-identity FK on every converted fact |
| T23 | a dimension is one definition, applied everywhere it is relevant | L1 `dimension` + `dimension_value` + `applies_to[]`; `fact_dimension` rows, no runtime DDL |
| T24 | dimensions constrain writes and may narrow reads, but never widen them | L2 `dimension_write_rule` triggers; `dimension_read_narrowing` composed strictly after company RLS |
| T25 | statutory registration is a dimension of place, resolved not inferred | L1 `operating_location` + `location_registration`; determination records the registration and the resolving rule |
| T26 | segment reporting reconciles to the entity by construction | L1 partitioning `segment_mapping` with exclusion constraints + explicit unallocated segment |
| T27 | consolidation runs over a mapped group chart | L1 `group_account_map` unique per (local account, period); L2 run guard refusing unmapped non-zero balances |
| T28 | a consolidation is a run with stored, reproducible output | L1 immutable `consolidation_run` with method per member, source watermark, rate revisions and result hash |
| T29 | every intra-group effect is eliminated from an identified fact | L1 `consolidation_elimination` FK to `intercompany_transaction` or `unrealised_margin`; L2 completeness reconciliation |
| T30 | group results reconcile in three directions | L2 deferred constraints on the run: trial balance, per-account decomposition, segment sum |

Every invariant gets at least one refusal test at its primary layer, and one concurrency test where L2/L3
participates. Four invariants carry additional mandatory test classes, because their failure mode is silent:

- **T1, T7, T10** require the full doc 52 §7 matrix — read, write, execution-context and authorisation-edge
  isolation — executed against a two-company fixture for **every** business table, including child, ledger,
  projection, outbox, job and audit tables.
- **T11** requires a test that a durable work row with an unresolvable principal or company **fails and is
  recorded as failed**, rather than proceeding.
- **T13** requires the conformance check itself to be tested: a deliberately non-conforming table added in a
  migration must fail the build.
- **T30** requires a reconciliation test per direction, on a group containing at least one partially-owned
  subsidiary, one cross-currency member and one crossing, so all three directions are non-trivial.

---

## 4. What we adopt, and what we refuse

Docs 50–56 each carry a full Adopt/Change/Reject matrix. Consolidated, the tranche's decisions cluster into
five themes. The proportion of *adopt* verdicts is higher here than in any other tranche — Frappe's
authentication primitives are largely correct, and its permission *vocabulary* is good. What is wrong is
almost entirely the **polarity of the defaults** and the **layer** the checks sit at.

### 4.1 Adopt wholesale — upstream got these right

| Mechanism | Why |
|---|---|
| **Two-axis lockout** (IP **and** account) with a uniform failure message and a password-size bound (`frappe/auth.py:249-264`) | Correct on all three counts; the uniform message closes the account-enumeration oracle that the rest of the API leaves open. |
| **Constant-time secret comparison** (`hmac.compare_digest`) | Right primitive, used in the right place. |
| **Absolute `session_end` alongside idle expiry**, and IP validation on both login *and* resume (`frappe/sessions.py:371-395`) | Two independent bounds and binding evidence — the shape T3 keeps. |
| **Per-session CSRF tokens** | Adopted unchanged. |
| **Controllers may only deny** — `has_permission` hooks are monotone, evaluated in reverse order, first falsy wins (`frappe/permissions.py:80-226`) | The single best design decision in the permission system, and the direct source of T8. Adopted including the evaluation semantics. |
| **The explanatory permission trace** (`frappe/permissions.py:43-79`) | The right information, assembled correctly — and then discarded (§4.5). We keep the trace and persist it. |
| **`if_owner` as a query constraint** rather than a post-filter (`frappe/model/db_query.py:1659-1678`) | Ownership pushed into the query is exactly the right instinct; it becomes a row predicate. |
| **Fetching shared documents only when full read access is absent** (`frappe/model/db_query.py:1200-1250`) | A correct optimisation that survives the move to delegations. |
| **Field and filter validation against metadata** (`frappe/desk/reportview.py:129-191`) | Kept as defence in depth — no longer load-bearing, because the boundary is below it. |
| **The enqueuing user *is* captured in job kwargs** (`frappe/utils/background_jobs.py:180-190`) | The information needed to fix the `Administrator` default is already present and simply unused. We require it and enforce it. |
| **Parties that represent companies** (`accounts/doctype/sales_invoice/services/inter_company.py:50-64`) | Modelling a crossing as a real party relationship, with `Allowed To Transact With` as the permission, is conceptually right. |
| **Bidirectional reference validation** and `Party Link`'s non-chaining rules (`accounts/doctype/party_link/party_link.py:24-68`) | Correct constraints, expressed as procedural probes; we keep the constraints and drop the probes. |
| **Directional warehouse swap and the deliberate exclusion of accounts and cost centres from the mapping** (`accounts/doctype/sales_invoice/mapper.py:176-260`) | Each company's chart is its own. Exactly right. |
| **Four-case peg arithmetic including cross-peg recursion** (`setup/utils.py:30-60`) | The most careful arithmetic in the currency layer. Adopted whole, over effective-dated pegs. |
| **Purpose-scoped rates** (`for_buying` / `for_selling`, `setup/utils.py:76-99`) | Extended with closing, average and historical purposes for translation. |
| **The booked versus unbooked FX split** and the explicit `rounding_loss_allowance` (`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:51-73`, `exchange_rate_revaluation.py:43-50`) | A real distinction, and a tolerance declared on the revaluation rather than smuggled into the ledger. |
| **`Inventory Dimension`'s three named refusals** and its explicit rules about where a dimension may live (`stock/doctype/inventory_dimension/inventory_dimension.py:13-24`) | `DoNotChangeError`, `CanNotBeChildDoc`, `CanNotBeDefaultDimension` — the right refusals, promoted to constraints. |
| **allow / restrict / mandatory filter vocabulary** and mandatory-for-P&L/BS flags (`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:109-115`, `accounts/doctype/accounting_dimension/accounting_dimension.py:263-285`) | Good vocabulary; becomes typed `require`/`permit`/`forbid` write rules. |
| **`Warehouse` already carries its company** (`stock/doctype/warehouse/warehouse.py:30-60`) | This is what makes location a *narrowing* of the boundary rather than a competing axis. |
| **Same-root validation on consolidation** (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:51-76`) | The only structural group rule in the codebase — and it is correct. |
| **Deterministic `lft` member ordering** and per-company opening-balance handling for unclosed years (`consolidated_trial_balance.py:77-83`, `consolidated_financial_statement.py:127-169`) | Reproducibility details that are easy to omit and were not. |
| **Surfacing the translation residual as a named line** (`consolidated_trial_balance.py:293-312`) | Visible rather than silently absorbed. We keep the visibility and fix what produces it (§4.4). |

### 4.2 Reject — fail-open defaults

This is the tranche's dominant theme, and the reason its polarity is inverted at L2 rather than tuned at L3.

| Upstream | Ours |
|---|---|
| no `User Permission` rows → **unrestricted** (`frappe/permissions.py:351-380`) | absence of a grant is a denial |
| empty `allowed_docs` list → check skipped (`frappe/permissions.py:351-412`) | empty means no access |
| empty link value → check skipped (`frappe/permissions.py:413-476`) | `company_id NOT NULL`; the row cannot be unscoped |
| `apply_strict_user_permissions` off by default, forced off for singles and **for local documents** (`frappe/permissions.py:351-395`) | strictness is not configurable and applies at creation, on the row |
| session resumption failure → `Guest` (`frappe/auth.py:123-148`, `frappe/sessions.py:346-360`) | failure denies |
| missing `Authorization` header → proceed; the fail-closed guard only fires when a header *was* present (`frappe/auth.py:642-658`) | every request resolves a principal; anonymous is an explicitly authorised one |
| authenticators swallow exceptions, so an internal error is indistinguishable from a non-match (`frappe/auth.py:660-708`) | an error denies and is recorded in `auth_event` |
| a supplied API key ignored when a session exists (`frappe/auth.py:735-763`) | one mechanism per request, reconciled or refused |
| missing currency → `None`, with the author's own unresolved comment asking whether it should throw (`setup/utils.py:62-75`) | refuse |
| disabled currency settings → rate `0.00` (`setup/utils.py:100-108`) | `CHECK (rate > 0)`; absence refuses |
| rate-fetch failure → log and fall through (`setup/utils.py:112-160`) | refuse and record |
| `allow_stale` permitting arbitrarily old rates (`setup/utils.py:76-99`) | `max_age_days` per company and purpose |
| unmapped local account appears as its own consolidation line (`consolidated_trial_balance.py:337-369`) | blocks the run |

### 4.3 Reject — exempt identities, in-code bypasses and unowned execution

| Upstream | Ours |
|---|---|
| `ignore_permissions=True` — **892 sites**, threaded through the query layer as a parameter any caller can set (`frappe/model/db_query.py:124-200`) | no bypass exists; elevated writes use an audited `delegation_grant`; only the migration role is exempt |
| `Administrator` bypasses authorisation first and unconditionally (`frappe/permissions.py:80-226`), and bypasses the `enabled` check (`frappe/auth.py:265-300`), and is exempt from forced session clearing (`frappe/auth.py:249-264`) | no super-identity; every principal is evaluated |
| background jobs default to `Administrator` (`frappe/utils/background_jobs.py:245-266`, `frappe/__init__.py:410-421`) | the work row carries its enqueuing principal and company, or the job fails |
| **34 identity switches** via `frappe.set_user` / `flags.ignore_permissions` in ERPNext | impersonation is a `delegation_grant`, time-boxed, reasoned and audited on grant *and* use |
| impersonation by session swap | same |
| `auth_hooks` running arbitrary app code inside authentication (`frappe/auth.py:764-768`) | no arbitrary code inside authentication |
| the authenticating DocType chosen by a caller-supplied `Frappe-Authorization-Source` header (`frappe/auth.py:709-734`) | mechanism chosen by server configuration only |
| permissions applied in `DatabaseQuery` only, with `sql`, `get_value`, `get_values` and `get_list` unguarded (`frappe/database/database.py:196-456`, `frappe/database/database.py:533-610`) | enforced by the database on every statement; there is no unguarded path |
| reports as a parallel read path gated at doctype level, row filtering left to the report author (`frappe/desk/query_report.py:248-300`) | the policy applies to report SQL identically; report capability is an additional grant |
| Prepared Report results computed under one scope, re-reads gated on the artefact (`frappe/desk/query_report.py:275-300`) | cached under a company; re-read re-derives scope |
| count endpoints and link-existence validation as cross-company oracles (`frappe/client.py:78-93`, `frappe/client.py:431-531`) | scoped resolution; no cardinality or existence signal crosses the boundary |
| the permission system queryable through the API (`frappe/client.py:329-339`) | answers only within the caller's scope |
| API keys as permanent fields on `User`, no expiry, no rotation (`frappe/auth.py:735-763`) | `principal_credential` with expiry, rotation chain and revocation |
| unlimited concurrent sessions by default (`frappe/auth.py:249-264`) | policy-bounded per principal kind, revocable, enumerable |
| cross-company consolidation as an ordinary report permission | an explicit group-scoped grant |

### 4.4 Reject — identity by string, and results by inference

| Upstream | Ours |
|---|---|
| consolidation aggregates on `account_name` (`consolidated_trial_balance.py:337-369`, `consolidated_financial_statement.py:480-505`) | `group_account_map` on account **identity** |
| counterparty guessed by address, else `parties[0]` (`accounts/doctype/sales_invoice/mapper.py:126-148`) | unique relationship per ordered pair and date |
| `get_value` on a multi-match filter picks one row (`accounts/doctype/sales_invoice/services/inter_company.py:40-49`) | a unique constraint makes it single-valued |
| same-date rates disambiguated by `name`, a series counter (`setup/utils.py:76-99`) | `rate_source.trust_rank` |
| revaluation rate derived from the last GL entry, making the result posting-order dependent (`exchange_rate_revaluation.py:649-697`) | rates come from `exchange_rate` |
| the translation reserve derived from the post-conversion debit/credit difference, absorbing missing rates indistinguishably from real translation differences (`consolidated_trial_balance.py:255-292`) | rates prescribed per item class; the residual is a **consequence**, posted to a declared `cta_account_id` |
| the FCTR row landing beside Liability when no Equity row exists (`consolidated_trial_balance.py:293-312`) | a declared account, never a positional guess |
| `Warehouse.is_group` inferred from whether children exist (`stock/doctype/warehouse/warehouse.py:138-161`) | `is_postable` declared |
| `select` silently aliasing `read` (`frappe/permissions.py:80-226`) | distinct operations; a selector grant confers no read |
| a 60%-owned subsidiary consolidated at 100% (`consolidated_financial_statement.py:519-529`) | `ownership_pct` per member per run, and a `minority_interest` line |
| evaluated inventory dimensions computing a value per document from an expression (`stock/doctype/inventory_dimension/inventory_dimension.py:354-384`) | resolved by a validated rule, with the **result** stored on the fact |
| cross-currency crossings refused outright (`accounts/doctype/sales_invoice/mapper.py:149-175`) | legs in different functional currencies, one agreed transaction amount |

### 4.5 Reject — decisions and results that are not stored

| Upstream | Ours |
|---|---|
| no access decision is recorded; the trace is built for a message and discarded (`frappe/permissions.py:798-805`) | `access_decision` durable — denials always, allows sampled by policy |
| no conformance test for scoping | generated `rls_conformance` check gates the build; `isolation_denial` aggregated and alerted |
| role assignments have no expiry | optional `expires_at`, always revocable, always audited |
| expiry enforced twice by two mechanisms, cache-first (`frappe/sessions.py:371-395`, `frappe/sessions.py:396-420`) | one rule in one place; cache is a strict subset of the durable record |
| the session record carries no scope (`frappe/sessions.py:256-310`) | scope fixed at issue on `auth_session`; a change of scope is a new session |
| the pairing of a crossing is two mutable scalars, unlinkable after posting (`accounts/doctype/sales_invoice/services/inter_company.py:66-86`) | one immutable `intercompany_transaction`; a pair is reversed, never unlinked |
| leg agreement is opt-in and off by default (`accounts/services/internal_transfer.py:104-119`) | deferred constraints; legs agree exactly, always |
| unrealised profit parked per company with no realisation mechanism (`accounts/services/internal_transfer.py:37-53`) | `unrealised_margin` per transaction and item, realised by an event |
| translation performed inside a report run, with no CTA account and no stored translated balances (`setup/doctype/company/company.json:14-30`) | `translation_run` + `translated_balance`, stored and reproducible |
| functional currency mutable on `Company` with nothing freezing it once posted facts exist (`setup/doctype/company/company.json:14-30`) | immutable once any posted fact exists |
| pegs not effective-dated — a changed peg rewrites history (`setup/utils.py:13-28`) | `currency_peg_revision` with an exclusion constraint |
| dimension deletion and disabling with no stated effect on posted history (`accounts/doctype/accounting_dimension/accounting_dimension.py:198-245`) | `closed` state; a used value is never deleted |
| no consolidation stored, so a group statement is not reproducible and adjustments cannot be posted | immutable `consolidation_run` with result hash and source watermark |
| a synchronous HTTP rate fetch inside whatever transaction is posting (`setup/utils.py:112-160`) | feeds write `exchange_rate` rows out of band |

---

## 5. The signature finding

Every tranche has produced one defect that states the whole tranche's thesis. Tranche F's was a discarded
cryptographic signature. Tranche G's is smaller, and worse, because it is three lines and it is the security
model:

```python
# frappe/permissions.py:351-380 — get_allowed_docs_for_doctype / get_user_permissions
if not user_permissions:
    return  # no restriction
```

An empty result set from the scoping lookup means *unrestricted*. The mechanism that confines a user to their
company treats "I found no rules" and "there are no limits" as the same answer. Combined with the two
adjacent defaults — strictness off, and strictness switched off again for unsaved documents, which is exactly
when `company` is being assigned — the practical position is that **the tenant boundary's default state is
open**, and 892 call sites can open it explicitly in any case.

Our schema makes the failure mode structurally unavailable, and it takes three separate constructs to do it,
because a single one would leave a path:

```sql
-- 1. the row cannot be unscoped
ALTER TABLE gl_entry ALTER COLUMN company_id SET NOT NULL;

-- 2. the policy cannot be skipped, and the owner cannot skip it either
ALTER TABLE gl_entry ENABLE  ROW LEVEL SECURITY;
ALTER TABLE gl_entry FORCE   ROW LEVEL SECURITY;
CREATE POLICY gl_entry_tenant ON gl_entry
    USING      (company_id = auth.current_company())
    WITH CHECK (company_id = auth.current_company());

-- 3. an unresolvable context yields no company, and every policy above denies
CREATE FUNCTION auth.current_company() RETURNS bigint
LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('auth.company_id', true), '')::bigint
$$;
```

`nullif(..., true)` returning `NULL` makes `company_id = NULL` unknown, so the policy denies every row. There
is no value of the setting — absent, empty, or garbage — that widens access. The application role is granted
neither `BYPASSRLS` nor ownership of any business table, which is what `FORCE` alone would not achieve.

The corresponding refusal is T13's: a generated conformance check proves that every table in the catalogue has
all three constructs, with exceptions confined to a reviewed allow-list, and **failing the check fails the
build**. That is the difference between asserting the boundary in twenty-three schema sections and having one.

---

## 6. Threat model

Doc 52 §7 gives the executable matrix. Stated as capabilities, this is what the design is required to
withstand — and what it deliberately does not.

| Attacker capability | What stops it | Invariant |
|---|---|---|
| Authenticated in company A, requests a row belonging to company B by primary key | RLS policy on the target table; the row does not exist for this connection | T1, T7 |
| Same, via a raw SQL report, an export, a REST list, a link-title fetch or a count endpoint | the policy is below all of them; there is no read path that is not a statement | T10 |
| Writes a row with company B's `company_id` | policy `WITH CHECK` on insert and update | T7 |
| Supplies a header naming a different tenant or authentication source | context comes from the resolved `auth_session` row; headers influence nothing | T2, T3 |
| Reuses a revoked or expired session token | one expiry rule over the durable record; cache is a strict subset | T3 |
| Presents a stolen API key | credential has an expiry and a revocation record; use is recorded in `auth_event` | T4, T5 |
| Enqueues background work hoping it runs unscoped | the work row requires principal and company, both `NOT NULL`; the claim sets context or fails the job | T11 |
| Finds any code path that sets a bypass flag | no such flag exists in the design; the application role cannot lift the policy | T1, T10 |
| Calls a permission-introspection endpoint to enumerate the estate | answers are scoped; failures are uniform; enumeration produces no signal | T6, T8 |
| Adds a custom rule intended to widen access | extension points are monotone: deny-only, and non-monotone results are rejected | T8 |
| Uses a dimension or segment rule to reach across companies | `dimension_read_narrowing` may only subtract, and is composed strictly after company RLS | T24 |
| Requests a consolidated report to read companies they cannot read individually | consolidation requires an explicit group-scoped grant, and the run records who obtained it | T28, and doc 52 §8 |
| Escalates by having a role granted to them permanently and quietly | grants carry actor, reason and expiry, and are append-only; the current state is a projection over facts | T9 |
| Deploys a new table without a policy | the `rls_conformance` gate fails the build; a table absent from the isolation matrix is not deployable | T12, T13 |

Explicitly **out of scope** for this design, and recorded as such rather than left implied: an attacker with
the migration role, an attacker with filesystem or backup access, an attacker with `superuser` on the database
cluster, and side channels arising from shared physical resources. The migration role can lift every policy in
this document by design — that is what makes it the migration role — so its use is a deployment-gated,
audited, non-interactive path, and it is never the credential the application holds.

---

## 7. Concrete records and ordering

`FINAL-SCHEMA.md` §29 onward holds the complete contract. Six groups, in build order:

| Group | Content |
|---|---|
| Identity and context | `principal`, `principal_credential`, `principal_company_membership`, `auth_session`, `auth_event`, `auth_throttle`, `delegation_grant`, and `auth.current_company()` |
| Authorisation | `permission_role`, `permission_grant`, `permission_assignment`, `permission_delegation`, `permission_row_predicate`, `access_decision` |
| Boundary conformance | `isolation_denial`, the generated `rls_conformance` view, and the allow-list of global reference tables |
| Group structure | `company_group`, `company_group_edge`, `intercompany_relationship`, `transfer_price_policy_revision`, `intercompany_transaction`, `unrealised_margin`, `unrealised_margin_realisation` |
| Currency | `rate_source`, `exchange_rate`, `currency_peg_revision`, `translation_run`, `translated_balance`, `translation_adjustment` |
| Place, dimension and segment | `dimension`, `dimension_value`, `fact_dimension`, `dimension_write_rule`, `dimension_read_narrowing`, `operating_location`, `location_registration`, `reporting_segment`, `segment_mapping` |
| Consolidation | `group_account_map`, `consolidation_run`, `consolidation_member`, `consolidation_member_contribution`, `consolidation_line`, `consolidation_elimination`, `minority_interest`, `fiscal_calendar_alignment` |

Three orderings carry the most weight:

- **Context is established at connection acquisition, before any statement.** Resolve the `auth_session` row,
  set `auth.company_id`, then hand the connection to the unit of work. A connection that reaches business
  code without a resolved context is a bug that manifests as *no rows*, never as *all rows*.
- **The scope is fixed at session issue, not per request.** Selecting a company is an act of session creation.
  This is what removes the entire class of "request switched tenant mid-transaction" reasoning, and it is why
  T3 states that a change of scope is a new session.
- **Eliminations are derived from crossings before the run's constraints are checked, not after.** T29's
  completeness reconciliation (Σ eliminations = Σ crossings in scope) and T30's three-way balance are deferred
  constraints on the same transaction that writes the run, so a consolidation that would not reconcile cannot
  be committed and then explained in a footnote.

---

## 8. Build sequence and boundary

No application implementation has started. **Tranche G is step 0 — it precedes everything in
[doc 40 §10](40-tranche-b-coverage-closure-and-our-production-spec.md#10-build-sequence-and-boundary).** The
first eight steps below must land before the first business table is created, because retrofitting `NOT NULL`
scope columns, policies and an execution-context contract onto populated tables is the rewrite §1.1 describes.

1. **Roles and context:** the migration role, the application role without `BYPASSRLS` or table ownership,
   `auth.current_company()`, and the connection-acquisition routine that sets the setting.
2. **Identity:** `principal`, `principal_credential` with expiry and rotation, `principal_company_membership`,
   `auth_throttle` with both subject kinds, `auth_event` as append-only.
3. **Sessions:** `auth_session` with scope, both expiry bounds and binding evidence; one expiry rule; total
   revocation; the cache as a strict subset.
4. **Delegation:** `delegation_grant` with actor, reason, expiry, and audit on grant and on use — built here,
   because it is the *only* elevated path and every later step depends on there being one.
5. **Authorisation:** `permission_role`, `permission_grant`, `permission_assignment`,
   `permission_row_predicate`, deny-only extension points, and `access_decision` with its trace.
6. **The boundary:** the policy template, the DDL convention every later migration follows, `isolation_denial`,
   and the generated `rls_conformance` view wired into the build as a gate.
7. **Execution context:** the durable work contract — `principal_id` and `company_id` both `NOT NULL` on every
   work row, claim-sets-context-or-fails, and the projection-runner equivalent.
8. **The isolation matrix:** doc 52 §7 executed in CI against a two-company fixture, with coverage enumerated
   from the table catalogue, so that steps 9 onward cannot add an unscoped table.
9. **Group structure:** `company_group`, dated `company_group_edge` with ownership, method and elimination
   policy, `intercompany_relationship` with its uniqueness constraint.
10. **Currency:** `rate_source` with trust ranking, `exchange_rate` append-only and superseding,
    `currency_peg_revision`, the resolution function that refuses, and the functional-currency freeze.
11. **Dimensions and place:** `dimension` as data, `fact_dimension`, typed write rules, additive-only read
    narrowing, `operating_location` with `is_postable`, `location_registration` wired to Tranche F's
    per-registration return periods.
12. **Crossings:** `intercompany_transaction` immutable with deferred leg agreement,
    `transfer_price_policy_revision`, `unrealised_margin` and its realisation events.
13. **Segments:** `reporting_segment` and partitioning `segment_mapping` with the unallocated segment.
14. **Translation:** `translation_run`, `translated_balance`, `translation_adjustment`, and the CTA account
    declared per company.
15. **Consolidation:** `group_account_map`, the run with method per member and source watermark, member
    contributions, eliminations derived from crossings, ownership apportionment, minority interest, and the
    three-way reconciliation as deferred constraints.
16. **Acceptance:** reproduce **S13** end to end, then run the full isolation matrix, a job-without-principal
    refusal test, a conformance-gate test, a rate-absence refusal test, a leg-disagreement refusal test, an
    unmapped-account refusal test, and a three-direction reconciliation on a group with a partially-owned,
    cross-currency member.

### 8.1 Where Tranche G touches what we already built

This tranche is beneath every other one rather than beside them, so the seams are different in kind: earlier
tranches consume its guarantees rather than integrating with its tables.

| Seam | Consequence |
|---|---|
| every table in `FINAL-SCHEMA` §2–§28 | `company_id NOT NULL` + policy is now a *tested* property, not an assertion; §29's conformance view enumerates them |
| `voucher` / `gl_entry` (§3) | the three currency layers and the rate identity are columns on the posting boundary, not report-time conversions |
| `stock_move` (§4) and `asset_cost_event` (§19.2) | dimensions arrive as `fact_dimension` rows on the same facts, with no runtime DDL |
| accounting period control (§2) and `return_period` (§27) | period guards are per company *and*, for statutory periods, per registration (T25) |
| `command_receipt` / durable work / `projection_checkpoint` (§10) | every work row now carries principal and company; a projection runner has an execution context |
| `domain_event` and the outbox (§10) | events are scoped facts; a projector reads within a company or is explicitly group-scoped |
| `tax_determination` (§25) and `location_registration` | doc 55 §5's finding: the statutory axis was `Address`; it becomes a modelled place dimension |
| `doc_link` (§5) | crossings are not links — `intercompany_transaction` is a fact, and the link graph is unchanged |
| `unrealised_margin` ↔ `consolidation_elimination` | the only place where a Tranche G table is the *source* for another Tranche G table across documents (T29) |

### 8.2 What remains open

- **Scale targets are still unanswered, and they now block a schema decision twice over.** Materialised versus
  computed balances (doc 01 §1.9) is one; the second is whether `access_decision` retains sampled allows at
  all, which is a volume question. Both need a number.
- **`auth_event` and `access_decision` retention** is unspecified. These are the highest-volume tables in the
  design and the ones an audit most wants intact; a retention and archival policy is required before §29 is
  final.
- **Cryptographic details are deliberately not specified**: the password hash function and parameters, secret
  storage backend, TOTP window, and token format. Doc 50 fixes the *contract* (secrets referenced not stored,
  constant-time comparison, credentials as managed objects with rotation); the primitives are an
  implementation-time decision with its own review.
- **Consolidation methods beyond full and equity.** `company_group_edge.consolidation_method` is an enum with
  room for proportionate consolidation and joint arrangements; only full consolidation and minority interest
  are specified end to end. Equity-method mechanics are named, not walked.
- **Fiscal-calendar alignment records the method but does not prescribe one.** A subsidiary with a different
  year-end is a real accounting problem, and `fiscal_calendar_alignment` currently stores *how* it was handled
  rather than constraining the choice.
- **Statutory document-numbering rules** and the **TDS/TCS ↔ GST seam** remain open from
  [doc 49 §7.2](49-tranche-f-closure-and-our-localisation-spec.md#72-what-remains-open-in-localisation),
  unchanged by this tranche.
- **Jurisdictions beyond India** are still unread at controller depth. UAE VAT, South Africa VAT and Italy
  exist in ERPNext's `regional/` tree; each is a rule-revision mapping exercise, not new code.
- **Frontend, form layout and grid behaviour** are assigned to a separate agent
  ([`PROMPT-frontend-form-ui.md`](../agents/PROMPT-frontend-form-ui.md)) on its own branch, with the `U`
  invariant prefix reserved for it. The seam between `field_scope` on a grant (T8) and field-level display
  rules is that document's to close, not this one's.

---

## 9. Investigation status after Tranche G

| Tranche | Scope | Status |
|---|---|---|
| A | accounting, stock, trade core | complete — docs 01–17, 26–32, S01–S06 |
| B | production, subcontracting, quality | complete — docs 33–40, S07–S10 |
| C | assets and depreciation | complete — docs 41–44, S11 |
| D | CRM, projects, support | **out of scope** by decision |
| E | platform mechanics | complete — docs 18–25 |
| F | localisation, India GST | complete — docs 45–49, S12 |
| **G** | **security, tenancy, multi-company/currency/location, consolidation** | **complete — docs 50–57, S13** |

ERPNext coverage remains **203 parents / 178 cited / 0 uncited submittable / 0 uncited configuration / 25
exclusions**, plus 26 India Compliance DocTypes read at controller depth. Invariant registers: `L/S/D/P`,
`F/T/R/V/U` (Tranche A/E), `M1–M69`, `A1–A26`, `G1–G29`, **`T1–T30`**. Scenarios **S01–S13**.

**Application implementation has not started.** With this tranche the investigation reaches the state it was
scoped for: the functional gaps are closed, and the foundation the functional design assumed is now specified
and testable rather than asserted. What remains before building is not another tranche. It is three answers —
scale targets, retention policy, and which jurisdictions beyond India — and the two open localisation seams in
[doc 49 §7.2](49-tranche-f-closure-and-our-localisation-spec.md#72-what-remains-open-in-localisation). The
build sequence in §8 is the plan, and its step 0 is the reason this tranche was not deferred.

---

Cross-references: [FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md) (§29 onward),
[doc 50](50-authentication-session-and-tenant-context.md),
[doc 51](51-permission-model-end-to-end.md),
[doc 52](52-tenant-isolation-and-rls-under-attack.md),
[doc 53](53-multi-company-intercompany-and-transfer-pricing.md),
[doc 54](54-multi-currency-layering.md),
[doc 55](55-multi-location-branch-and-segment.md),
[doc 56](56-consolidation-and-group-reporting.md),
[S13](../scenarios/S13-cross-company-consolidation-and-isolation.md),
[doc 19](19-permissions-and-access-control.md) (the permission machinery catalogue),
[doc 22](22-background-jobs-scheduling-and-locking.md) (jobs without a session),
[doc 24](24-reporting-framework.md) (post-hoc filtering at the query layer),
[doc 25](25-our-platform-spec.md) (the four-layer rule),
[doc 15](15-intercompany-and-history-rewriting.md) (crossing mechanics),
[doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (the dimension mechanism),
[doc 40](40-tranche-b-coverage-closure-and-our-production-spec.md) (build sequence this precedes),
[doc 44](44-tranche-c-closure-and-our-asset-spec.md),
[doc 49](49-tranche-f-closure-and-our-localisation-spec.md),
[INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md) and [COVERAGE.md](../COVERAGE.md).
