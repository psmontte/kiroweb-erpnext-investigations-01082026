# Salvage assessment — the suspended unibizapp backend

**Question asked:** what in `D:\uni-projects\uni-apps\unibizapp` can be reused in the new build **without
any compromise**? "Without compromise" is the whole test here: golden rule 0 says a workaround is never an
option, so a component only qualifies if it can be adopted *as it is meant to work*, not as something we
patch around.

**Assessed:** 3 August 2026, against `unibizapp` as it stands on this machine and `erpnext-research` at
`main` = `6b31cc7`. Everything below is measured, not recalled.

---

## 1. What is actually there

| Thing | Size | State |
|---|---|---|
| `apps/backend/src/backend` | **17,671 lines**, 50 Python files | the engine: orchestration compiler, validator registry, trigger compiler, expression evaluator, schema cache, runtime |
| `apps/backend/tests` | **45,055 lines**, 102 files, **526 test functions** | STATUS records 674 collected tests |
| `apps/backend/migrations` | 25 migrations up + down (head **025**) | forward-only, contiguous — the runner refuses a gap |
| `apps/backend/orchestrations` | **1 file** | `POST_UL_DOC_HEADERS_BP_V3.json` |
| `apps/backend/generated/metadata` | **1 file** | `ar_entities.json` |
| `apps/backend/vendor/src` | 403 old Python files, 399 in `services_v4/` | **0 called on any live path** — reference only |
| `apps/web` | **5** `.tsx` files | an untouched Next.js starter — `layout.tsx`, `page.tsx` and fonts |
| `knowledge/doc-implementations/001-…` | **742 files** | decision register D01–D151+, ~44 code-review rounds, build tracker, plans |

**Reach achieved:** one AR slice — Sale Invoice and Receipt Voucher, save / post / reverse — proven against
a throwaway schema rebuilt by the production migration runner.

⛔ **The metadata-driven frontend is not in unibizapp.** `apps/web` is a starter with five files. The form
engine being described — compile FE metadata from the database to JSON, author flat and nested entity
metadata, validate column coverage — lives in **`uni-app-turborepo`** (5,549 `.tsx` files, with a family of
`*-fe-metadata` skills) and in `uni-app-turborepo-fe-by-kiro.on-macbook` (1,040 `.tsx`). Any salvage of the
form engine is an assessment of *those* repos and has not been done. This document covers only what was
asked for: `001-db-backend-rewrite-07-06-26` and `apps/backend`.

---

## 2. Verdict, component by component

| Component | Verdict | Why |
|---|---|---|
| **`db/trigger_compiler/`** (917 + 175 lines) | **Salvage the design, port the code** | A *pure planner* — declarative table policy rows in, PostgreSQL trigger DDL out, no database dependency, deterministic and unit-testable. This is precisely the pattern the new design needs (§3 below) and it is the best-built thing in the repository. Its frozen slot contracts and its refusal to let a versioned business table be exempted are exactly right. |
| **`db/migrations/runner.py`** (477 lines) | **Salvage** | Forward-only, contiguous-version enforcement, a ledger table, up/down pairs. Generic infrastructure with no ERP opinion in it. |
| **`db/throwaway_ownership.py`** (1,332 lines) + the `migrated_db` fixture | **Salvage the practice, port the code** | Never verifying against a live database, always rebuilding a throwaway schema from `migrations/` with the production runner, is the discipline that makes a test result mean something. Adopt it before the first migration, not after. |
| **The migration *shape*** — every object re-owned to an owner role, the runtime role owning nothing | **Salvage** | Matches doc 57 §8 step 1 exactly. The runtime role holding no ownership is the same conclusion Tranche G reached independently. |
| **`compiler/validators.py`** (2,756 lines) | **Salvage ~10%** | It is a linter for the JSON orchestration DSL. If the DSL goes, most of it goes with it. The ERP-semantic ones — `_validate_gl_balance` and its neighbours — encode real accounting knowledge and should be re-expressed as database constraints, which is where `FINAL-SCHEMA` already puts them. |
| **`runtime/expressions.py`** (1,373 lines) | **Reject** | An evaluator for `{"$or": [{"$eq": [...]}]}`. It exists only to interpret the JSON DSL. |
| **`compiler/orchestration.py`** + the JSON orchestrations | **Reject** — see §3 | |
| **`runtime/ar_save.py` / `ar_post.py` / `ac_save.py`** (3,064 lines) | **Reject as code, mine for cases** | Written against the old `ul_*` table shapes, which `FINAL-SCHEMA` replaces wholesale. The *worked cases* inside them are worth reading beside `docs/scenarios/S01`–`S03`. |
| **`vendor/src/services_v4/`** (399 files) | **Reject** | Already dead in unibizapp — 0 calls on any live path. |
| **Migration `002_tenant_context_rls.sql`** | ⛔ **Reject — see §4** | |
| **`001-…/docs/decisions/`** (D01–D151+) | **Read, do not inherit** | Decided in this session: `FINAL-SCHEMA.md` is the sole authority; the old register is reference material. Several rulings are still worth mining — the "measuring stick, never a proof source" rule for the legacy database (D149/D150/D151) is good discipline and costs nothing to keep. |
| **The 44 code-review rounds** | **Read once, then archive** | They are the record of how the last attempt went wrong. The recurring failure — a green gate that enforced the wrong accounting rule while everyone read it as proof — is worth internalising before writing the first gate here. |

---

## 3. The flexibility question, answered

The requirement is a hugely flexible system where a new complex form is stood up in an hour. Three
mechanisms could deliver that, and they are not equally good.

**ERPNext's answer: runtime DDL.** A Custom Field row creates a real column while the system is running.
This is already **rejected** (`docs/logic/18`, `docs/logic/21`, `FINAL-SCHEMA` §24). It is how a production
schema becomes something nobody can reason about.

**unibizapp's answer: business logic as interpreted JSON.** The evidence is worth stating plainly, because
it is the strongest argument available and it comes from your own project, not from opinion:

- One document save is **128 JSON steps** with `$or` / `$eq` / `$.input.header…` operators. That is a
  programming language expressed in JSON — no type checking, no debugger, no stack trace, no meaningful
  code-review diff.
- Supporting it cost **1,373 lines of expression evaluator** and **2,756 lines of linter** whose entire job
  is to catch the mistakes a compiler would have caught for free.
- After all of it, **exactly one orchestration exists** and **one entity is generated**. The mechanism built
  to make new documents cheap produced one document type.

That last line is the finding. The promise was flexibility; the measured output was one AR slice.

**The answer that actually gives you the hour: metadata drives *shape*, code and constraints drive
*correctness*, and the schema is generated at migration time.**

| Layer | Metadata-driven? | Why |
|---|---|---|
| Form layout, fields, labels, visibility, grids, list views, filters | **Yes, fully** | This is where the hour comes from, it is what ERPNext genuinely does well, and it is already specified — `docs/ui/01-form-rendering-and-layout-engine.md` and `docs/agents/PROMPT-frontend-form-ui.md`. A new form here is data. |
| Table definitions, columns, foreign keys, `CHECK`s, RLS policies, triggers | **Declared as metadata, applied as a reviewed migration** | You declare the entity; a generator emits the DDL; a human reads the diff; it lands as a numbered migration. You get the speed of declaration and keep 2,051 real foreign keys. This is exactly what unibizapp's trigger compiler already does for triggers — extend the same idea to tables. **Never at runtime.** |
| Posting rules, valuation, tax determination, settlement, consolidation | **No** | Typed code plus database constraints. An unbalanced journal entry must be impossible, not merely unconfigured. This is what `FINAL-SCHEMA`'s invariant registers are — `L/S/D/P`, `M1–M69`, `A1–A26`, `G1–G41`, `T1–T30`. |

The dividing line is one question: **if this is configured wrong, does money end up in the wrong place?**
If yes, it is code and a constraint. If no, it is metadata.

---

## 4. The one thing that must not be salvaged

⛔ **`migrations/002_tenant_context_rls.sql` — the mechanism that stops one company reading another
company's data — is built on the exact design `erpnext-research` rejected twice and recorded as
"don't reintroduce it".**

unibizapp's isolation predicate is:

```sql
SELECT row_tenant_id = ... current_setting('app.tenant_id', true)::uuid ...
```

Its own comment calls this "the trusted per-transaction GUC … that the M1-T1 context shell sets with
`SET LOCAL` (never a browser header)".

**`SET LOCAL` is a statement the application role is allowed to execute.** The runtime issues SQL; anything
that can issue SQL can issue `SET LOCAL app.tenant_id = '<some other company>'` and then read that
company's rows. The word "trusted" in that comment is the assumption, and it is the assumption Tranche G
disproved. `docs/HANDOFF.md` §5 records it: *"`current_setting('auth.company_id', true)` reads correctly
and is forgeable… **This was caught twice — don't reintroduce it.**"*

Everything else about that migration is right and worth copying: fail-closed on absent, empty **and**
malformed context (no `tenant_id IS NULL` escape branch); `ENABLE` **and** `FORCE ROW LEVEL SECURITY`; one
reusable applier that every table-creating migration calls; the predicate on **both** `USING` and
`WITH CHECK`; and a build gate asserting it. Those are genuinely good and were reached independently.

**The fix is not a patch, it is the substitution `FINAL-SCHEMA` already specifies:** the context lives in a
protected table `authenticated_tenant_context` that the application role has no privileges on, written only
by `begin_tenant_transaction()` (`SECURITY DEFINER`, which verifies membership against
`principal_company_membership` before writing), and read only by `authenticated_company_id()`. Same
fail-closed behaviour, same applier, same gate — an unforgeable source.

**No live exposure.** `unidb` is recorded as a pre-reset build and not a valid oracle; STATUS forbids
verifying against it. This is a design defect in suspended code, not an open door.

---

## 5. What this means for the build

1. **Nothing blocks starting.** The salvage list is infrastructure — migration runner, throwaway-schema
   fixture, trigger compiler, migration shape. None of it touches accounting, so none of it can smuggle in
   a wrong rule.
2. **Step 0 is unchanged and is now better evidenced.** doc 57 §8 step 1 is roles and context, and
   unibizapp is the worked example of what happens when that step looks finished and is not.
3. **The form engine is a separate assessment.** `uni-app-turborepo` holds the metadata-driven frontend and
   has not been audited. It should be, against `docs/ui/01-form-rendering-and-layout-engine.md`, before any
   frontend decision is made.
4. **`unibizapp` becomes read-only reference**, on the same footing its own D149/D150/D151 gave the legacy
   `uni_app` database: a measuring stick, never a source, never deleted.

---

## 6. Recorded, not fixed

Per golden rule 10 — issues found are written down with the step that closes them, never dropped.

| Issue | Where it closes |
|---|---|
| `uni-app-turborepo`'s form engine is unassessed, and it is the thing the flexibility requirement rests on | a dedicated audit against `docs/ui/01` |
| The `002` GUC defect exists in a repository that is suspended, not deleted; a future session could salvage it in good faith | this document, plus `HANDOFF.md` §5 |
| unibizapp's `db-migration-author` skill contradicts its own migration runner about whether version gaps are allowed (the runner refuses gaps; the skill says they are fine) | drop the skill with the repository, or correct it if the skill is carried forward |
| Several unibizapp decisions (D149–D151 legacy-database discipline, the throwaway-schema rule) are worth keeping but currently live only in a register we have declared non-binding | fold them into this repository's conventions when the build starts |
