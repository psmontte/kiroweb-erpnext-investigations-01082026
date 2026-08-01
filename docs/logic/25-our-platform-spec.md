# 25 — Our Platform Specification (Tranche E synthesis)

> **Tranche E deliverable.** Synthesises docs 18–24 into a decision per platform capability:
> **build / buy / drop**, and where each responsibility sits in our architecture.
>
> Frappe/ERPNext source pinned at `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`,
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).

Docs 01–17 answered *what the business logic must do*. Docs 18–24 answered *what the framework
underneath it does*. This document answers the question that opened Tranche E: **how much
framework are we writing ourselves, and where does each guarantee live?**

---

## 1. The architectural premise

Our backend is a **declarative orchestration engine**: business operations are JSON blueprints
(`SAVE_UL_DOC_HEADERS_BP_V3` and siblings) composed of typed steps — `SELECT_ONE`, `DB_INSERT`,
`INSERT_BATCH`, `UPDATE_MULTI`, `EXECUTE_SQL`, `CALL_FUNCTION`, `RUN_PYTHON`, `VALIDATE`,
`SUB_ORCHESTRATION`, `SET_VARIABLE`, `RETURN` — executed inside one transaction with a declared
timeout and tenant scope.

That is a materially different platform from Frappe's, and the difference matters for this
document:

| | Frappe | Ours |
|---|---|---|
| Unit of behaviour | a Python `Document` subclass + 15 hook sources (doc 21 §5) | one versioned JSON blueprint |
| Where the sequence lives | implicit in `run_before_save_methods` / `run_post_save_methods` + install order | explicit `sequence` numbers in one file |
| Extension mechanism | `hooks.py` namespace introspection, string-path dispatch | a step added to a blueprint, or a `SUB_ORCHESTRATION` |
| Schema | rows in `tabDocType`/`tabDocField`, `ALTER TABLE` at runtime | SQL migrations |
| Auditability of behaviour | read 8 tables + N `hooks.py` files | read one blueprint |

So we have already rejected doc 21's hook model in practice: **the pipeline is data, but it is
*declared* data with explicit ordering, not *discovered* data with install-order precedence.**
That is the single biggest structural win available, and it is banked.

The rest of this document is about the guarantees that a blueprint engine, on its own, does
**not** give you — and where we put them.

---

## 2. The layering rule

Tranche A + E produce one governing principle:

> **A guarantee belongs at the lowest layer that can enforce it without cooperation.**

Four layers, in order of strength:

| Layer | Enforces | Bypassable by |
|---|---|---|
| **L1 — Schema** (types, `NOT NULL`, `CHECK`, `UNIQUE`, `FK`, `EXCLUDE`, generated columns) | structural truth | nothing, short of DDL |
| **L2 — Triggers & RLS** | invariants spanning rows/tables; tenancy; append-only; audit | the migration role only |
| **L3 — Orchestration blueprint** | business sequence, workflow, side effects | a caller that doesn't use the blueprint |
| **L4 — Service code / SP** (`RUN_PYTHON`, `CALL_FUNCTION`) | computation, external I/O, proposals | anything calling the DB directly |

Frappe puts almost everything at L3/L4 — which is why doc 19 §6 lists eight bypass routes, and
why doc 22 §2.3 needs a scheduled job (`run_ledger_health_checks`) whose purpose is to discover
that the books don't balance.

Every "reject" verdict in docs 18–24 is an instance of one rule: **move it down a layer.**

---

## 3. Build / buy / drop, by capability

### 3.1 Schema and metadata (doc 18)

| Capability | Decision | Where |
|---|---|---|
| Schema definition | **BUILD** — numbered SQL migrations | L1 |
| Runtime `ALTER TABLE` from config | **DROP** | — |
| Dimension extensibility | **BUILD** — fixed `dim1..dim4` FK slots + `gl_entry_dimension` (D13) | L1 |
| Per-tenant descriptive fields | **BUILD** — `ext_field` / `ext_value`, typed, one-value `CHECK` | L1 |
| Opaque payloads | **BUILD** — `jsonb` + GIN, never a source of truth | L1 |
| Settings | **BUILD** — `setting_def` / `setting_value`: typed, **company-scoped**, effective-dated, `EXCLUDE`-guarded, audited | L1 |
| Precision | **DROP** metadata-resolved precision → `numeric(19,4)` money, `numeric(21,9)` qty/rate (D1) | L1 |
| Presentation metadata | **BUILD** — `ui_field` / `ui_layout`, describes rendering only; cannot affect storage | L4 |
| Auto-generated CRUD UI | **DROP** | — |
| Auto-generated API per entity | **BUILD** — generated at build time from the migrated schema (introspection → OpenAPI), not at runtime | build step |

The extension-table architecture already in the blueprint (`*_ext_dev`, `*_ext_partner`,
`*_ext_regional`, `*_ext_custom`, `*_export`, `*_ext_order`, …) is the right shape: **real
columns in real tables, one table per concern, joined by `doc_id`/`line_id`.** It is
`Custom Field` without the `ALTER TABLE`. Keep it.

Two things it still needs from L1/L2, currently handled at L3:
- extension-table presence/absence per subtype is validated by `sp_validate_payload_completeness`
  and `sp_reconcile_extension_tables` **after** the write. A partial `FK`/`CHECK`-based
  formulation (e.g. `is_export` implying a row in `*_export`) moves it to L1.
- `version_no` on extension rows is written as a literal `1` on insert; either make it a trigger
  (L2) or drop the column.

### 3.2 Access control (doc 19)

| Capability | Decision | Where |
|---|---|---|
| Tenancy | **BUILD** — `company_id NOT NULL` + RLS + `FORCE ROW LEVEL SECURITY` + `WITH CHECK` (D2) | **L2** |
| Company-scoped uniqueness | **BUILD** — `UNIQUE (company_id, …)` | L1 |
| Rights model | **BUILD** — `app_role` / `role_grant` / `user_role`, with `effect = allow|deny`, enum `resource`/`action`, per-company + effective-dated grants | L1 + L2 |
| `approve` / `post` / `reverse` as rights | **BUILD** | L1 |
| Row scoping (`own`, `company`, `cost_center`, `team`) | **BUILD** — RLS policy predicates over `STABLE` grant functions | **L2** |
| Sharing | **BUILD** — `doc_share` with `expires_at` | L1 + L2 |
| Field-level access | **BUILD** — column privileges + restricted views (`field_set`) | L1 |
| Masked fields with read-then-restore | **DROP** | — |
| Permlevels | **DROP** | — |
| `permission_query_conditions` (SQL from hooks/DB rows) | **DROP** | — |
| Approval authority | **BUILD** — `approval_policy` / `approval_policy_rule` / `approval_event` (D10) | L1 + L2 |

**This is the largest single change from current practice.** Today the blueprint passes
`tenant_id` as an explicit parameter into every `WHERE` and every `data_template` — roughly 40
occurrences in one save blueprint. That is correct-by-diligence, which doc 19 §6 shows is not a
strategy that survives contact with a growing codebase. With RLS the predicate is applied by the
database whether or not the step remembered it, and `tenant_id` in a step becomes redundant
belt-and-braces rather than the only defence.

Mechanically: the connection pool sets `app.company_ids` / `app.user_id` per request from the
authenticated session; the migration role is the only `BYPASSRLS` principal; `SECURITY DEFINER`
functions are enumerated in a registry with explicit `search_path`.

### 3.3 Identity, numbering, audit (doc 20)

| Capability | Decision | Where |
|---|---|---|
| Primary keys | **BUILD** — `uuid` everywhere, immutable, client-generatable | L1 |
| Human document numbers | **BUILD** — `numbering_rule` (scoped, `EXCLUDE`-guarded) + `numbering_counter`, allocated **at posting** | L1 + L3 |
| Gapless mode | **BUILD** — `UPDATE … RETURNING` on a scoped counter; `SEQUENCE` when gaps are legal | L1 |
| Fabricated fallback numbers | **DROP** — absence of a rule is a hard failure, never `DRAFT-<uuid>` | L3 |
| Counter reversion on delete | **DROP** — numbers are issued at posting; posted rows are never deleted | — |
| Amend chains in the identifier | **DROP** — `reverses_voucher_id` + stable `line_id` (D5) | L1 |
| Lifecycle audit | **BUILD** — `lifecycle_event`, written by trigger | **L2** |
| Field-level audit | **BUILD** — `field_change`, written by trigger from an `audited_column` registry, partitioned by time | **L2** |
| Diff-based audit in app code | **DROP** | — |
| Retention | **BUILD** — `retention_policy` per company + resource; `DETACH PARTITION` | L1 + L3 |

**Why the audit triggers matter here specifically.** Doc 20 §2.1 found that Frappe's `Version`
misses every `db_set` write. Our blueprint has the same exposure from a different direction: the
`old_values` fed to `audit_service.log_action` are whatever the preceding `SELECT_ONE` happened to
project, and steps like `reconcile_header_tax_totals`, `refresh_header_cache`, and
`update_line_tax_counts` write columns without going through the audit step at all. A trigger on
the table cannot be forgotten by a step, and does not care which step wrote the row.

### 3.4 Extensibility (doc 21)

| Capability | Decision | Where |
|---|---|---|
| Operation pipeline | **KEEP** — declarative blueprints with explicit `sequence` | L3 |
| `hooks.py` namespace introspection | **DROP** | — |
| Install-order precedence | **DROP** — `priority` is explicit | L3 |
| String-path dynamic dispatch | **DROP** — compile-time handler registry | L4 |
| `doc_events["*"]` | **DROP** — cross-cutting rules are constraints/RLS | L1/L2 |
| Business rules as code lists | **DROP** — `doc_type_config` + policy tables | L1 |
| Post-commit extension | **BUILD** — `domain_event` + `event_subscription`, typed `event_type` enum | L1 + L4 |
| Extensions inside the posting transaction | **DROP** — additive stages only; hard rules are constraints | — |
| Localisation | **BUILD** — `tax_regime` / `tax_rule` as data + `company_extension` adapters selected by the **document's** company | L1 + L4 |
| Whole-function regional override | **DROP** | — |
| Country as free text | **DROP** — ISO 3166-1 `char(2)` | L1 |
| Code stored in the database (`Server Script`, `Client Script`) | **DROP** | — |
| Notification conditions | **BUILD** — restricted expression AST, parsed and validated on save | L1 + L4 |
| Runtime-constructed controller classes | **DROP** | — |
| Template helpers (`jenv` equivalent) | **BUILD** — fixed registry | L4 |

The blueprint model already gives us doc 21's headline fix. What it still needs is the
**subscriber boundary**: today `RUN_PYTHON` service calls (`tax_engine`, `stock_engine`,
`fulfillment_engine`, `uom_conversion_service`) run *inside* the save transaction, which is
correct for them — they compute values the write depends on. Genuinely optional reactions
(notifications, integrations, downstream proposals) should be `domain_event` rows consumed after
commit, so an extension can never fail a save.

The India-GST fields already sit in `*_ext_regional` rather than in a globally-applied
`doc_events` hook — that is doc 21 §6.3 layer 2, done right. The remaining step is making the
*selection* of regional behaviour a function of `header.company_id` → `company_extension`, never
of a session default (doc 21 §3.1 point 1).

### 3.5 Jobs and scheduling (doc 22)

| Capability | Decision | Where |
|---|---|---|
| Job queue | **BUILD** — `job` table, `FOR UPDATE SKIP LOCKED` | L1 |
| Idempotency | **BUILD** — `UNIQUE (kind, idempotency_key)` | L1 |
| Dead letters | **BUILD** — durable `state = 'dead'` with payload + error | L1 |
| Transactional enqueue | **BUILD** — a job row is inserted in the business transaction | L1 + L3 |
| Redis/RQ for transactional work | **DROP** | — |
| Redis fast path for pure I/O (email, gateway, PDF) | **BUY/OPTIONAL** — only for category-4 work | infra |
| Scheduling | **BUILD** — `schedule` with per-company IANA timezone, applied jitter, `UPDATE … WHERE next_fire_at <= now()` claim | L1 |
| Dormancy skipping | **DROP** | — |
| Jobs running as `Administrator` | **DROP** — explicit actor; RLS applies | L2 |
| File locks | **DROP** | — |
| Row locks on the invariant-owning row | **BUILD** — in triggers, not per-call-site | **L2** |
| Advisory locks | **BUILD** — enumerated key registry, documented ordering | L2 |
| Optimistic concurrency | **BUILD** — `version integer` + `WHERE version = :expected`, **and the engine must abort on 0 rows affected** | L1 + L3 |
| Correctness-restoring jobs (repost, health check) | **DROP** — nothing to restore | — |

Two engine-level requirements fall out of this, and they are the most important items in this
document for the orchestration runtime:

1. **A `DB_UPDATE` / `UPDATE_MULTI` step whose optimistic-lock predicate matches zero rows must
   abort the transaction.** Silent zero-row updates turn an optimistic lock into a no-op and let
   the losing writer proceed through the rest of the blueprint.
2. **An optimistic-lock check must not be satisfiable by omitting the token.** `version_no == null
   → pass` is the same hole as `db_set(update_modified=False)` (doc 09 §1.3).

### 3.6 Migrations and deployment (doc 23)

| Capability | Decision | Where |
|---|---|---|
| Versioned SQL migrations, one transaction each | **BUILD** | tooling |
| Checksums verified at startup | **BUILD** | tooling |
| Mandatory `down.sql` or declared irreversibility | **BUILD** | tooling |
| `skip_failing` semantics | **DROP** — a failed migration fails the deploy | — |
| `exec`'d patch strings | **DROP** | — |
| Killing user connections during migration | **DROP** — `lock_timeout` + online-safe DDL idioms | tooling |
| Migrations as an audited actor | **BUILD** — `migration:NNNN` appears in `field_change` / `lifecycle_event` | L2 |
| Migrations rewriting ledger rows | **DROP** — corrections are reversal vouchers with `reason_code` | L2 |
| Seed / reference data | **BUILD** — seed migrations, `ON CONFLICT DO UPDATE` | tooling |
| Schema-drift CI gate | **BUILD** — extend `tools/verify_ddl.sh`: apply all migrations from empty **and** against a production-shaped dump, diff against snapshot | CI |
| Invariant tests | **BUILD** — every register entry (F1–U1, H1–H4, L1–L6, S1–S7) has a test that attempts violation and asserts refusal | CI |
| Migration runner | **BUY** — `sqlx` / `Flyway` / `Atlas`-class tool; do not write one | **open question Q7** |

Blueprints are themselves versioned artefacts and need the same discipline: a blueprint version
(`"version": 13`) should be recorded against the deployment, and a blueprint change that depends
on a schema change must declare the minimum migration version it requires.

### 3.7 Reporting (doc 24)

| Capability | Decision | Where |
|---|---|---|
| Reports read named views | **BUILD** — `report_source` allowlist | L1 |
| Report definitions as data | **BUILD** — `report_def` / `report_column` / `report_filter`, closed operator enums, identifiers validated against `information_schema` | L1 |
| Query generator + runner + export | **BUILD** — small | L4 |
| ~25 core financial/inventory report views | **BUILD** — the real work of this tranche | L1 |
| User-supplied SQL / stored report code | **DROP** | — |
| Post-hoc Python row filtering | **DROP** — RLS on base tables, inherited by views | L2 |
| Materialised roll-ups | **BUILD** — `REFRESH … CONCURRENTLY`; each either aggregated to a universally-safe grain or wrapped by a policy-bearing view | L1 |
| Read replica | **BUY** — infra, same roles + policies | infra |
| Async export | **BUILD** — a `job` row producing a stored artefact | L1 |
| Timer-triggered "prepared report" mutation | **DROP** | — |
| Charts / number cards | **BUILD** — same definition model over views | L1 |
| Print templates | **BUILD** — engine + fixed helper registry, no arbitrary expressions | L4 |
| Analytics offload (DuckDB/column store) | **DEFER** — only if measurements demand it | infra |

The permission consequence is worth restating because it is the one that cannot be retrofitted:
**aggregation must happen after row filtering.** With RLS on `gl_entry`, a `SUM` over
`rpt_general_ledger` sums only visible rows. Without it, any aggregate is computed over
everything and then row-filtered — which cannot un-leak a total.

---

## 4. What we are explicitly not building

Recording these so the scope question does not reopen:

1. **A metadata-driven form/CRUD generator.** Presentation metadata describes rendering; it never
   defines storage.
2. **A user-facing SQL console or stored-code facility.** No `Server Script`, no `Client Script`,
   no Query Reports. (doc 19 §3.3, doc 24 §1.1–§1.2)
3. **A `Customize Form` equivalent that alters schema.** Admin UI over `ext_field`,
   `setting_value`, `numbering_rule`, `approval_policy`, `ui_field` only.
4. **A migration engine.** Buy it.
5. **A general workflow designer.** Approval is `approval_policy`; document lifecycle is the
   state machine in doc 09 §8. No arbitrary state graphs over arbitrary fields.
6. **Cascade cancellation.** Reversal is explicit, one voucher at a time (D5).
7. **Repost/rebuild subsystems.** Projections are recomputable, ledgers are immutable (D6, H1–H4).
8. **A downgrade path for data migrations.** Schema `down.sql` yes; data corrections are forward-
   only reversal vouchers.

---

## 5. Requirements this places on the orchestration engine

Consolidated, because these are engine features rather than schema:

| # | Requirement | Why (doc) |
|---|---|---|
| E1 | Abort when an optimistic-lock predicate matches 0 rows | 22 §5.4 |
| E2 | Reject a lock check that passes on a null token | 09 §1.3 |
| E3 | Blueprint version recorded per deployment, with a minimum migration version | 23 §5.1 |
| E4 | Session context (`app.company_ids`, `app.user_id`) set before step 1, from the authenticated session | 19 §7.1 |
| E5 | Step-level provenance: which step wrote which row, available to `field_change` via a transaction-local setting | 20 §3.3 |
| E6 | `domain_event` emission as a first-class step type, consumed after commit | 21 §6.1 |
| E7 | Deterministic step ordering with no implicit precedence | 21 §1 |
| E8 | Child-collection semantics declared per array: *replace* vs *merge* vs *delete-marked-only* — never "delete all if absent" | 18 §4, and the child-table pattern generally |
| E9 | A single resolved-config read per operation, not N repeated lookups of the same key | 18 §1.1 (meta caching) |
| E10 | Timeout budget proportional to declared step count, with per-step timing recorded | 23 §1.2 |

E8 is the one with teeth: whether a missing array means "no change" or "delete everything" must be
a declared property of the collection, checked by the engine, not a per-blueprint convention.

---

## 6. Cost of leaving Frappe — honest accounting

| Lost | Replacement | Effort |
|---|---|---|
| Metadata-driven schema evolution | migrations + `ext_field` + dimension slots | medium, one-off |
| Auto CRUD UI | presentation metadata + front end | large, but not framework work |
| Auto REST API | build-time generation from schema | small |
| Permission engine | RLS policies + grant model | medium; **strictly stronger** |
| Naming series | `numbering_rule` | small |
| Audit (`Version`) | trigger-written `field_change` | small; **strictly stronger** |
| Hook ecosystem | blueprints + `domain_event` | already built |
| Regional packs | `tax_regime` data + `company_extension` | medium |
| Job queue + scheduler | `job` / `schedule` tables | small; **strictly stronger** |
| Report framework | generated queries over views | small engine, **large view library** |
| Print formats | template engine + helper registry | medium |
| `bench` tooling / migrate | bought migration runner + CI | small |
| 997 DocTypes of prior art | docs 01–24 | done |

Net: the framework work is **small-to-medium and mostly one-off**. The large items are (a) the
report view library, (b) the front end, (c) the localisation data. None of them are framework.

---

## 7. Investigation status

| Tranche | Scope | Status |
|---|---|---|
| Schema | 997 DocTypes, 908 tables, 10 995 columns catalogued; verified DDL | ✅ `docs/reveng/`, `schema/` |
| Core logic | GL, stock, stock↔GL, AR/AP, taxes/totals, lifecycle, period close, spec | ✅ `docs/logic/01`–`08` |
| **A** | lifecycle/approval/reversal/deletion, fulfilment, advances+allocation, budgets/deferrals/CC allocation, POS, banking, inter-company + repost, reservation/picking/warehouse, item/UOM/variants/batch/reorder | ✅ `docs/logic/09`–`17` |
| **E** | metadata + runtime DDL, permissions, naming/identity/audit, hooks + regional, jobs/scheduling/locking, migrations/patches, reporting, **this spec** | ✅ `docs/logic/18`–`25` |
| Design | finalised tables, data flow, business rules, invariant register | ✅ `docs/design/FINAL-SCHEMA.md` |
| **B** | Manufacturing (BOM, Work Order, Job Card, routing, Production Plan, WIP) — 48 DocTypes; Subcontracting deep dive — 13 | ⏳ pending scope confirmation |
| **C** | Assets + depreciation engine (a second posting engine) — 26 DocTypes | ⏳ pending scope confirmation |
| **D** | Projects, Quality, Support, Maintenance (~47); CRM (28) | ⏳ pending scope confirmation |

Open questions carried forward (unchanged from `docs/INVESTIGATION-PLAN.md` §4, now with Tranche E
context):

1. **v1 scope** — is B (manufacturing) and/or C (assets) in the first build? Biggest lever on
   remaining investigation.
2. **Inventory features** that change the core design: FEFO/expiry, reservation, multi-warehouse
   transfer, landed cost, subcontracting, consignment.
3. **Localisation** — which jurisdictions in v1? Drives how much of doc 21 §6.3 is needed on day
   one. (India GST is clearly in, from the `*_ext_regional` shape.)
4. **Scale targets** — rows/day on the ledgers, companies, concurrent users. Decides materialised
   vs computed balances and whether the ledgers need partitioning.
5. **Upstream tracking** — periodic delta report against a newer ERPNext commit, or is the pinned
   snapshot enough?
6. **Document format** — is Markdown-in-git the final form for these?
7. **Migration runner** — which tool (§3.6).

---

## 8. Reading order for the whole investigation

```
docs/reveng/README.md          schema study
docs/logic/README.md           business logic, 01-25
docs/design/FINAL-SCHEMA.md    the target schema and invariant register
docs/INVESTIGATION-PLAN.md     coverage map, remaining tranches, open questions
```

Verification: `tools/verify_refs.py` mechanically checks every `file.py:line` citation in
`docs/logic/` against the pinned source trees. `tools/verify_ddl.sh` loads the generated DDL into
a throwaway PostgreSQL. Both should be run before trusting a line number.

---

Cross-references: every document in `docs/logic/`; `docs/design/FINAL-SCHEMA.md`;
`docs/INVESTIGATION-PLAN.md`.
