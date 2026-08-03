# Handoff — ERPNext/Frappe investigation

**State at handoff:** the investigation is **complete and fully reviewed**. All planned tranches are closed,
both deliberately-open localisation seams are closed, the last unreviewed document has been reviewed and its
tables transcribed, and **application implementation has not started**.

- Repo: `D:\uni-projects\uni-apps\erpnext-research`, branch **`main`**, remote
  `github.com/psmontte/kiroweb-erpnext-investigations-01082026`.
- Verified on this machine, 3 Aug 2026: **6,087 citations, 0 problems**; coverage 203 parents / 178 cited /
  0 gaps / 25 exclusions; `docs/COVERAGE.md` not stale.
- **This repository is the sole design authority.** The prior project at
  `D:\uni-projects\uni-apps\unibizapp` — its decision register D01–D151+ included — is read-only reference
  material, not binding (owner ruling, 3 Aug 2026). See
  [`docs/design/SALVAGE-FROM-UNIBIZAPP.md`](design/SALVAGE-FROM-UNIBIZAPP.md).

---

## 1. What exists

| Tranche | Scope | Deliverables |
|---|---|---|
| A | accounting, stock, trade core | docs 01–17, 26–32; S01–S06 |
| B | production, subcontracting, quality | docs 33–40; S07–S10 |
| C | assets and depreciation | docs 41–44; S11 |
| D | CRM, projects, support | **dropped by decision** — not investigated, not built |
| E | platform mechanics | docs 18–25 |
| F | localisation, India GST | docs 45–49; S12 |
| G | security, tenancy, multi-company/currency/location, consolidation | docs 50–57; S13 |
| — | the two seams doc 49 left open | doc 58 |

**Target design:** `docs/design/FINAL-SCHEMA.md` — §1–§18 core/production, §19–§23 assets, §24–§28 localisation,
**§29–§37 security/tenancy/group**, §38 what remains open, **§39 statutory numbering and withholding
derivation** (belongs with §24–§28; appended rather than renumbering ten sections).

**Invariant registers:** `L/S/D/P` and `F/T/R/V/U` (A/E), `M1–M69` (B), `A1–A26` (C), **`G1–G41`** (F + doc 58),
**`T1–T30`** (G). `U` is reserved for the frontend agent.

**Verification, all green at HEAD:**

```bash
cd /projects/sandbox/erp
python3 tools/verify_refs.py --docs docs/logic \
  --app erpnext=/projects/sandbox/erpnext/erpnext \
  --app frappe=/projects/sandbox/frappe/frappe \
  --app india_compliance=/projects/sandbox/india_compliance/india_compliance --quiet-ok
# repeat for --docs docs/scenarios and --docs docs/design
python3 tools/coverage_audit.py
PYTHONPATH=tools python3 tools/update_coverage_doc.py --check
git diff --check
```

Current: **6,075 citations, 0 problems** (5,163 logic + 824 scenarios + 88 design). Coverage **203 parents / 178
cited / 0 gaps / 25 exclusions**. 0 broken intra-repo links.

---

## 2. ~~The one outstanding task~~ — closed 3 Aug 2026

**Doc 58 was reviewed and its tables are transcribed.** `FINAL-SCHEMA` **§39** now carries them, §28 points
forward to it, and §38 no longer names an outstanding schema task. **The investigation is complete with
nothing left open that a session can close on its own.**

It was not mechanical. The review
([`semantic-review/2026-08-03-doc-58-review.md`](../semantic-review/2026-08-03-doc-58-review.md)) returned
**19 findings, two of them blocking**: doc 58 §5 referenced a document-number **format rule** and a
**statutory year** that existed in neither `FINAL-SCHEMA` nor anywhere else, so there was nothing to
transcribe them against. Five more were substantive design defects — a hard-coded Indian regex in a
`CHECK` on a jurisdiction-agnostic table (`@allow_regional` in schema form, which §24 rejects), an
allocation uniqueness that forbade a lawful two-registration state, a series that could be declared unable
to produce a lawful number, a `bigint[]` of foreign keys with no referential integrity, and an unscoped
table that would have failed §31's `rls_conformance` build gate. Six were citations that resolve and are
in range but point at the wrong branch of the right function — invisible to `tools/verify_refs.py`.

§39 therefore carries **eight** tables, not five: `statutory_format_revision`, `statutory_year`,
`statutory_series`, `statutory_number_allocation`, `withholding_regime`, `withholding_section_revision`,
`withholding_section_component`, `withholding_base`. The localisation register runs **G1–G41**.

---

## 3. Blocked on you — three answers

These are not investigation gaps. They are decisions only you can make, and each changes the schema.

1. **Scale targets** — rows/day on the ledgers, number of companies, concurrent users. Decides:
   (a) materialised vs computed balances (doc 01 §1.9), (b) whether the valuation projection needs
   partitioning, (c) whether `access_decision` retains sampled allows at all.
2. **Audit retention** for `principal_auth_event` and `access_decision` — the highest-volume tables in the
   design and the ones an audit most wants intact. `retention_class` exists; the policy that reads it does not.
3. **Which jurisdictions besides India** — UAE VAT, South Africa VAT and Italy exist in ERPNext's `regional/`
   tree and were not read at controller depth. Each is a rule-revision mapping exercise over §24–§28, not new
   code. Also decides whether numbering rules beyond Rule 46(b) matter.

Two older questions are still formally open but no longer block anything: **upstream delta tracking** (periodic
report against a newer commit, or is the pinned snapshot fine?) and **document format** (Markdown-in-git, or
does this need to become a spec site / PDF for readers outside the repo?).

---

## 4. Deliberately out of scope — recorded, not forgotten

- **GST TDS/TCS (s.51/s.52)** — absent from both upstream trees. Modelled as a `withholding_regime` row with a
  GSTIN identity and GSTR-7/8 return forms; **not walked**. Only needed if the company is a government
  deductor or an e-commerce operator (doc 58 §8).
- **Cryptographic primitives** — password hash function and parameters, secret-store backend, TOTP window,
  token format. Doc 50 fixes the *contract* (secrets referenced not stored, constant-time comparison,
  credentials as managed objects with rotation); the primitives are an implementation-time decision with its
  own review.
- **Consolidation methods beyond full** — `consolidation_method` admits `proportional` and `equity`; only full
  consolidation with minority interest is specified end to end.
- **`fiscal_calendar_alignment` records a method without prescribing one** — a subsidiary with a different
  year-end is a real accounting problem; the table stores *how* it was handled and requires a justification,
  but does not constrain the choice.
- **Statutory section catalogues and GSTR-1/3B field maps** are seeding exercises. The containers exist
  (`withholding_section_revision`, `return_format_revision`); the 2,702-line `gstr_1_json_map.py` is not
  transcribed.
- **Frontend / form layout / grid / customisation** — assigned to a separate agent,
  `docs/agents/PROMPT-frontend-form-ui.md`, on the `kiro/spec-planning` branch. Invariant prefix `U` reserved.
  The seam between `permission_grant.field_scope` (§30) and field-level display rules belongs to that document.
- **Audit trail and income-tax/VAT-India modules** in `india_compliance` beyond the withholding seam.

---

## 5. Design decisions that must not be silently reversed

These were argued and are load-bearing. If a future session wants to change one, it should say so explicitly.

- **The tenant boundary is a database policy, not application code.** `company_id NOT NULL` + RLS **enabled and
  forced** + a policy over `authenticated_company_id()`. Rejected: Frappe's one-site-per-tenant model, and
  `User Permission` filtering (which **fails open** — no rows means unrestricted).
- **The context is a protected row, never a GUC.** `current_setting('auth.company_id', true)` reads correctly
  and is forgeable, because `SET LOCAL` is a statement the application role may execute. Use
  `begin_tenant_transaction` (SECURITY DEFINER, verifies membership) writing `authenticated_tenant_context`,
  which `app_role` holds no privileges on. **This was caught twice — don't reintroduce it.**
- **No `ignore_permissions` flag exists in our design** (892 upstream sites) and **no `Administrator`**.
  Break-glass is a time-boxed, audited `delegation_grant`. Jobs carry their enqueuing principal and company or
  **fail**.
- **Group-scoped tables get a policy, not an exemption** — `company_group_id` + `authenticated_group_ids()`,
  which must be SECURITY DEFINER or the group boundary collapses into the company boundary (§31.1).
- **Dimensions:** one `dimension` definition as data. Rejected the two-system split and runtime Custom Field
  DDL. `dimension_read_narrowing` may only subtract.
- **Crossings:** one immutable `intercompany_transaction` with two legs agreeing by deferred constraint.
  Rejected two mutable scalars that can be unlinked post-posting. `unrealised_margin` is tracked to realisation,
  not parked in an account.
- **Currency:** three named layers; the **rate row's identity** on every fact; presentation currency derived by
  a stored `translation_run`. `CHECK (rate > 0)` makes a `0.00` rate unrepresentable. Rejected FCTR-as-plug.
- **Translation converts posted amounts, never unrounded intermediates** — this moves a cent and is stated in
  §33.2 and S13 §7.4.
- **Consolidation aggregates on `group_account_map` identity**, never on `account_name`.
- **Statutory numbers are attributes, never identities** (doc 58 G30) — and jurisdiction is **data**, not a
  code path selected at runtime (`@allow_regional` rejected).

---

## 6. Environment notes for the next session

**The work moved off the Kiro sandbox onto a Windows machine on 3 Aug 2026.** Everything below that
mentioned `/projects/sandbox` no longer applies; the repository now lives at
`D:\uni-projects\uni-apps\erpnext-research` on branch `main`.

- **Pinned sources are cloned into the repository at `upstream/`** and git-ignored. Recreate with a
  depth-1 fetch of the **exact commit**, never a branch tip:

  ```bash
  cd erpnext-research && mkdir -p upstream/frappe && git init -q upstream/frappe
  git -C upstream/frappe remote add origin https://github.com/frappe/frappe.git
  git -C upstream/frappe fetch -q --depth 1 origin 5da68e856ca7f036b20d2583167b9d00c4a8db56
  git -C upstream/frappe checkout -q FETCH_HEAD
  ```

  Same shape for `erpnext` (`https://github.com/frappe/erpnext.git`, `ceefd4add77715d2762c19db337fb83e28a477de`)
  and `india_compliance` (`https://github.com/resilient-tech/india-compliance.git`,
  `205c3de939bd99cc1df1e0d1cb76cff2e76eee55`, 26 DocTypes).
- **Run the tools with `python`, not `python3`** — `python3` is not on `PATH` on this machine.
- **`tools/verify_refs.py` was patched twice.** (a) Unprefixed citations resolve against the **first**
  `--app` when ambiguous across apps — always pass all three `--app` roots or you get ~60 false failures.
  (b) **Windows path separators**: the file index was built with `os.path.join` (`\`) and matched with
  `endswith("/" + rel)`, and resolved paths mixed both separators so one file looked like two candidates.
  That produced **376 false failures** and 28 false "ambiguous shorthand" reports. Both are fixed by
  normalising to `/`; do not reintroduce `os.sep` into either path.
- **The DDL in `schema/ddl/` has not been loaded on this machine.** PostgreSQL 16.2 is installed but
  `psql` prompts for a password that is not recorded. `tools/verify_ddl.sh` is written for a Linux sandbox
  (it installs PostgreSQL and runs `initdb`) and will need a Windows equivalent or a connection string.
  The last recorded run was clean: 429 tables, 2,051 FKs, 0 dangling FK targets.
- **Commit style:** imperative subject, no body needed.
  `git -c user.email=kiro@example.com -c user.name=Kiro commit -q -m "..."`
- **Filenames I have gotten wrong before:** `19-permissions-and-access-control.md`,
  `24-reporting-framework.md`, `18-metadata-and-runtime-ddl.md`, `14-banking-and-collections.md`,
  `16-stock-reservation-picking-warehouse.md`, `S06-multi-currency.md`.
- ~~**Branch name is stale**~~ — the Tranche G and doc 58 branches are merged; work is on `main`.

---

## 7. Review discipline that has paid off

Every tranche closure has been followed by a semantic review, and each found real defects:
**32** in Tranche C, **39** in Tranche F, **8** in Tranche G (`semantic-review/`). The Tranche G review found
two *blocking* issues — the forgeable GUC, and a foreign key onto a partial unique index that PostgreSQL would
have rejected — plus a one-cent arithmetic cascade in S13.

~~**Doc 58 has not been reviewed.**~~ **Reviewed 3 Aug 2026 — 19 findings**, keeping the pattern intact
(32 / 39 / 8 / 19). The prediction in this section was right on both counts: the tables' DDL held most of
the defects, and the statutory characterisation was the weakest link. **Rule 46(b)** is stated as law and
then *evidenced* by `GST_INVOICE_NUMBER_FORMAT`, which encodes it exactly — sound. **CBDT Circular 23/2017**
and **s.206C(1H)** are bare legal assertions with no citation of any kind, and the whole G36 argument rests
on them. The design conclusion survives (a base rule that cannot be dated and attributed is wrong whatever
the correct bases are), but doc 58 now carries a block saying the specific bases **must not be seeded on its
authority** — golden rule 9, and the reason `authority` is `NOT NULL` on `withholding_section_revision`.

**Nothing in this repository is now unreviewed.**

---

## 8. Where to pick up

~~1. Review doc 58.~~ ~~2. Transcribe doc 58 §5 into `FINAL-SCHEMA`.~~ Both done, 3 Aug 2026.

1. **Audit the metadata-driven form engine in `D:\uni-projects\uni-apps\uni-app-turborepo`** (5,549 `.tsx`
   files, plus a `*-fe-metadata` skill family) against
   [`docs/ui/01-form-rendering-and-layout-engine.md`](ui/01-form-rendering-and-layout-engine.md). This is
   the largest unassessed asset and the flexibility requirement rests on it. It is **not** in `unibizapp`,
   whose `apps/web` is an untouched Next.js starter — see
   [`docs/design/SALVAGE-FROM-UNIBIZAPP.md`](design/SALVAGE-FROM-UNIBIZAPP.md) §1.
2. **Finish `docs/ui/01`** — §6–§8 and §10 are empty headings and `UI1`–`UI9` are entirely unallocated
   (9 of 56 sub-tasks done). It is the only deliverable in the repository that is genuinely incomplete.
3. **Answer §3's three questions.** Scale and audit retention gate the first migration; jurisdictions gates
   how much of §24–§28 needs seeding.
4. **Then implementation starts**, and the build order is fixed:
   [doc 57 §8](logic/57-tranche-g-closure-and-our-security-spec.md#8-build-sequence-and-boundary), whose
   **step 0** is the boundary — because retrofitting scope columns and an execution-context contract onto
   populated tables is a rewrite, not a migration. `unibizapp` is the worked example of that step looking
   finished when it was not (`SALVAGE-FROM-UNIBIZAPP.md` §4).
