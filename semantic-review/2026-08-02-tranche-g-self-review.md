# Tranche G security/tenancy/group investigation, target schema §29–§37, and S13's consolidation arithmetic

Docs 50–57, S13 and `FINAL-SCHEMA.md` §29–§37 close the boundary that the previous twenty-three schema sections asserted and never tested. The upstream behavioural claims hold up under spot-check better than in Tranche C or F — I verified the load-bearing ones against the pinned trees line by line and every one was accurate, including the two that carry the tranche's thesis. The invariant register is exact: T1–T30 are each introduced once, and all thirty names in doc 57 §3 match their source blockquotes character-for-character. What needed fixing was concentrated in the *target design* rather than the investigation: one construct that would have shipped a forgeable boundary, one foreign key PostgreSQL would have rejected outright, two undefined objects, one policy circularity, and a one-cent arithmetic cascade in S13.

**Watch for:** doc 57 §5 and S13 §7.1 specified the tenant-context function as a **custom GUC** read with `current_setting('auth.company_id', true)` (**confirmed, blocking**) — forgeable by `SET LOCAL`, which the application role may execute, and the exact defect the Tranche B review had already caught in this file's original policy shape. `principal_auth_session`'s foreign key targeted a **partial** unique index (**confirmed, blocking**) — not declarable in PostgreSQL. §29's and §31's claim that the scope-exemption allow-list is "six identity tables plus §24 reference data" was contradicted by eight further exemptions the same file declares (**confirmed**). S13's BetaCo FX gain translated an unrounded intermediate (**confirmed**), shifting seven downstream figures by a cent.

**Verdict**: FIXED — all findings below are resolved in `68799c0..b5a749a`.

## High-level view

The tranche's measured result is unusually strong and it checks out. `ignore_permissions=True` is exactly **892** occurrences (524 Frappe + 368 ERPNext). The "34 identity switches" figure is exactly right and more precisely sourced than the doc implied: 31 non-test `flags.ignore_permissions = True` plus 3 `frappe.set_user` in ERPNext. The **84 defects** claim is exactly right — I counted the numbered items in all seven `Defects and risks` sections (14+12+12+12+15+9+10, where doc 54 includes a `12a`). The fail-open finding is verbatim accurate: `frappe/permissions.py:351-380` really is `if not user_permissions: return True`, and the adjacent comment really does read `Strict permissions will be skipped on local document`. `setup/utils.py:62-75` really does carry the author's unresolved 2016 comment above a bare `return`, and `:100-108` really does `return 0.00`. `validate_auth`'s terminal check really is guarded by `if len(authorization_header) == 2`, so a missing header proceeds. `connect(set_admin_as_user=True)` is the default, so a job with `user=None` genuinely runs as Administrator. Cross-currency inter-company really is `frappe.throw`. Consolidation really does compare `gle["account_name"] == entry["account_name"]`.

One claim was **not reproducible as written** and is the only investigation-side finding. Every document said the only occurrence of `current_setting` in either repository was in a query-builder test, and S13 §2 printed a grep returning a single line. The bare string actually matches ~25 lines — a `get_current_setting` helper in two log-retention patches and several Python locals named `current_settings`. The *substance* is correct and in fact stronger than claimed: Postgres's `current_setting(` appears 6 times in exactly 1 file, all `current_setting('timezone')`, so no call site in either application reads a session-scoped database setting. The probe now shows the real command, the real output and why the `grep -v` is necessary.

The GUC finding is the one that mattered. Doc 57 §5 presents "three constructs" that make the fail-open mode structurally unavailable, and construct 3 was `SELECT nullif(current_setting('auth.company_id', true), '')::bigint`. That reads correctly — absent yields `NULL`, `company_id = NULL` is unknown, the policy denies — and it is still wrong, because the application role can execute `SET LOCAL auth.company_id`, and the function would faithfully report whatever the attacker chose. Notably doc 50 §6.1 had it **right** (a lookup against the durable session table with an explicit note that the app role cannot set the token), and `FINAL-SCHEMA`'s conventions header had it right too and says in terms that the policy "never trusts a caller-set custom GUC". So the tranche contained the correct answer and the closure document reintroduced the wrong one. §5 is now four constructs, names the GUC version as REJECTED, and explains that a policy is only as strong as the least-privileged thing that can influence its inputs.

The foreign key was a hard PostgreSQL error rather than a design opinion. `principal_auth_session` declared `FOREIGN KEY (principal_id, company_id) REFERENCES principal_company_membership (principal_id, company_id)` while membership's uniqueness was `UNIQUE (principal_id, company_id) WHERE revoked_at IS NULL`. A partial unique index cannot be an FK target, so this would not have created. Dropping the FK was the wrong repair because it puts the entire scope bound in application-reachable code; the fix makes membership's uniqueness total — one row per pair for all time, `revoked_at` as current state, grant/revoke history in `principal_auth_event` — which restores the two-layer split the design wants: L1 proves the pair was *ever* granted, L2 proves it is *live now*.

Two objects were referenced but never defined. `authenticated_tenant_context` is named in the conventions header and used by every policy, and had no DDL; it now has one, and its primary key `(backend_pid, txid)` is what makes the header's "raises if absent or ambiguous" true rather than aspirational — a second `begin_tenant_transaction` in the same transaction cannot install a conflicting scope. `authenticated_principal_id()` was used by §31.1's group policy and described only as "the sibling"; it is now defined.

§31.1's group policy had a circularity. `authenticated_group_ids()` reads `delegation_grant`, which is itself company-scoped, so as an INVOKER function it would be evaluated under the caller's own company policy and could not see a grant issued in a sibling company — the group boundary would have depended on the company boundary it sits beside. It is now `SECURITY DEFINER`, with the two bounds that make that safe stated explicitly: it takes no arguments (the principal comes from the protected context row, so nobody can ask about someone else's grants) and it returns only group ids, never grant rows.

S13's arithmetic was right in structure and wrong by one cent in a way worth recording. BetaCo's revaluation FX gain is a **posted** ledger amount of GBP 333.33, but the translation used the unrounded 333.3333, giving EUR 387.60 instead of 387.59. That propagated to seven figures. The headline claims all survive — the intra-group balance still eliminates to exactly zero, consolidated cost of sales is still exactly group cost of the 40 units sold, the trial balance still ties, and the independent cross-check of group profit still agrees with the elimination-derived figure. S13 now states the rule that decides it: translation converts `functional_amount` **as stored**, because a consolidated statement must be derivable from figures that exist in a ledger, and `FINAL-SCHEMA` §33.2 carries the same rule.

Everything mechanical passes: 6,050 citations resolve across `docs/logic`, `docs/scenarios` and `docs/design` with 0 problems; 0 broken intra-repo links; `coverage_audit.py` unchanged at 203 parents / 178 cited / 0 gaps / 25 exclusions; `update_coverage_doc.py --check` clean; no trailing whitespace. Every table doc 57 §7 promises exists in `FINAL-SCHEMA` §29–§35, the only apparent misses being the three shorthand names §29's naming note explicitly maps.

<details>
<summary>Issues (8)</summary>

### 1. blocking — doc 57 §5, S13 §7.1: the tenant-context function was a forgeable GUC

`SELECT nullif(current_setting('auth.company_id', true), '')::bigint`, with S13 showing `SET LOCAL auth.company_id = '<alphaco>'`. `SET LOCAL` is a statement the application role may execute, so the boundary could be moved by the caller it is meant to constrain. Doc 50 §6.1 and the conventions header both already had the correct form, and the header explicitly forbids trusting a caller-set GUC.

**Fixed:** §5 is now four constructs; construct 3 is the protected `authenticated_tenant_context` row read by a `STABLE` function, populated only by a `SECURITY DEFINER` entry point that verifies token and membership; the GUC form appears under a `-- REJECTED` marker with the reasoning. S13 §7.1 now calls `begin_tenant_transaction(...)`. `FINAL-SCHEMA` §29 gains a note explaining that doc 50 §6.1 and §29.1 are a refinement rather than a contradiction, and that the GUC is rejected in both.

### 2. blocking — `FINAL-SCHEMA` §29: foreign key onto a partial unique index

`principal_auth_session` referenced `principal_company_membership (principal_id, company_id)`, whose uniqueness was `WHERE revoked_at IS NULL`. PostgreSQL cannot use a partial unique index as an FK target; the table would not create.

**Fixed:** membership uniqueness is total, with a comment explaining why the partial form is not available and where the grant/revoke history lives instead (`principal_auth_event`, with new `membership_granted` / `membership_revoked` kinds). The two enforcement layers are now stated on the table.

### 3. substantive — `FINAL-SCHEMA` §29/§31: the exemption allow-list contradicted the file

Both sections claimed the allow-list was "the six protected identity tables, and the global reference data named in §24". The same file declares eight more exempt tables — `principal_auth_event`, `isolation_denial`, `business_table_catalogue`, `company_group`, `intercompany_transaction`, `rate_source`, `exchange_rate`, `currency_peg_revision`, `consolidation_run` — and leaves a dozen §32/§35 tables ambiguous.

**Fixed:** new §31.1 is the normative register, with three classes (global reference / protected identity and infrastructure / group-scoped). Group-scoped tables are **not** exempted from checking: they carry `company_group_id NOT NULL` and a `group_scope` policy over `authenticated_group_ids()`, and §31's gate checks them against that shape. The `[NOT COMPANY-SCOPED]` markers in §32 and §35 now read `[GROUP-SCOPED (§31.1)]`.

### 4. substantive — `FINAL-SCHEMA` §31.1: group policy depended on a company-scoped table

`authenticated_group_ids()` reads `delegation_grant`, which is company-scoped. As an INVOKER function the group boundary would collapse into the company boundary.

**Fixed:** `SECURITY DEFINER` with fixed `search_path`, `REVOKE`/`GRANT` stated, no arguments (principal from the context row), returns only group ids.

### 5. substantive — `FINAL-SCHEMA` §29: two objects used but never defined

`authenticated_tenant_context` (referenced by every policy in the file) and `authenticated_principal_id()` (used by §31.1).

**Fixed:** both defined. The context table's PK `(backend_pid, txid)` makes single-valuedness structural, `begin_tenant_transaction` is now idempotent for the same scope and raises on a conflicting one, and transaction-scoped cleanup plus the pid/txid predicate give the pooled-connection guarantee the header's tests require.

### 6. substantive — S13: translation of an unrounded intermediate, cascading to seven figures

BetaCo's posted FX gain is GBP 333.33; the doc translated 333.3333.

**Fixed:** 387.60→387.59, 14,955.43→14,955.42, CTA 164.73→164.72, aggregate 48,773.61→48,773.60, aggregate CTA 1,578.87→1,578.86, final CTA 1,796.55→1,796.54, trial balance 24,829.28→24,829.27, group profit 2,566.03→2,566.02, attributable 1,459.62→1,459.61, BetaCo attributed profit 2,766.03→2,766.02, BetaCo translated profit 2,248.06→2,248.05. Propagated to `docs/scenarios/README.md` and `FINAL-SCHEMA` §35. S13 §7.4 now states the rounding rule and `FINAL-SCHEMA` §33.2 encodes it on `translated_balance`. All three T30 reconciliation directions re-verified independently; the headline claims are unaffected.

### 7. minor — all Tranche G documents: the `current_setting` probe was not reproducible

The stated grep returns ~25 lines, not one. Substance correct and actually stronger than claimed.

**Fixed:** doc 50 §1 and S13 §2 show the real command with `grep -v get_current_setting`, the real output (6 occurrences, 1 file), and why the exclusion is necessary. Prose in doc 57, `README.md`, `INVESTIGATION-PLAN.md`, `COVERAGE.md`, `FINAL-SCHEMA` §29 and both indexes restated as "every use of Postgres's `current_setting()`".

### 8. minor — two constraint gaps

`principal_credential`'s partial unique omitted `NULLS NOT DISTINCT`, so with `subject_ref` NULL for every secret-backed kind a principal could hold unlimited simultaneous unrevoked passwords, each invisible to the others — which defeats the rotation chain. `reporting_segment`'s `UNIQUE (company_id) WHERE is_unallocated` was annotated "exactly one, and it must exist"; a unique index cannot enforce existence, and without existence T30 direction 3 fails silently the first time a dimension value is unmapped.

**Fixed:** `NULLS NOT DISTINCT` added (matching the convention used six times elsewhere in the file); the segment comment now separates *at most one* (the index) from *at least one* (a seed row plus an L2 trigger on the first `segment_mapping`).

</details>

## Things that look wrong and are not

- **`intercompany_transaction` has no `company_id`.** Deliberate — it names two companies, so a single scope column would be a lie. Its legs (`intercompany_transaction_leg_line`) are company-scoped, which is what lets each company work with its own leg without a group grant.
- **`delegation_grant` is company-scoped, not exempt.** Correct: it carries `company_id NOT NULL`, and a `group_read` grant additionally names `company_group_id`.
- **S13 §7.7 shows India-South cost of sales as exactly 0.** Correct, not a missing number: AlphaCo's cost of all 100 units is removed by E2's cost leg in the same segment, and the buyer-side restatements are attributed to UK.
- **E5 (283.57) looks like the FCTR plug the tranche rejects.** It is the opposite. It is a residual whose three constituent rate choices are each recorded on the run, versus upstream's identical-in-magnitude number arrived at by subtraction with the choices unrecorded. S13 finding 4 is the comparison.
- **Doc 54's defect list contains a `12a`.** Intentional, from an earlier correction commit; the 84-defect count includes it.
- **Tranche G adds no ERPNext DocType parents.** Correct: docs 50–52 read Frappe framework modules and docs 53–56 read controllers and reports under parents already counted, so the 203/178/25 matrix is unchanged by design.
