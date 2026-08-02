# Handoff — ERPNext/Frappe investigation

**State at handoff:** the investigation is **complete**. All planned tranches are closed, both deliberately-open
localisation seams are closed, and **application implementation has not started**. Everything is committed and
pushed; nothing exists only in the sandbox.

- Repo: `/projects/sandbox/erp`, branch **`docs/localisation-india-gst`**, HEAD `e27ad90`, clean, 0 unpushed.
- Open PR: **https://github.com/psmontte/kiroweb-erpnext-investigations-01082026/pull/2** (Tranche G; doc 58 and
  the closure edits landed on the same branch after it was opened, so the PR now covers both).

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
**§29–§37 security/tenancy/group**, §38 what remains open.

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

## 2. The one outstanding task

**Transcribe doc 58 §5's five tables into `FINAL-SCHEMA.md`.** Doc 58 specifies them completely — DDL,
constraints and rationale — but they are not yet in the schema file. `FINAL-SCHEMA` §38 says so explicitly.

- `statutory_series`, `statutory_number_allocation` → a new section after §28
- `withholding_regime`, `withholding_section_revision`, `withholding_base` → same section
- Add the allocation step to the posting funnel **immediately before** registration-snapshot capture (a number
  must be lawful before the document carrying it is validated against a counterparty)
- Extend §28's register to **G30–G41**

This is mechanical: the design decisions are made and reviewed. Roughly one session.

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

- **Pinned sources:** `erpnext@ceefd4add77715d2762c19db337fb83e28a477de`,
  `frappe@5da68e856ca7f036b20d2583167b9d00c4a8db56`,
  `india_compliance@205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (cloned at `/projects/sandbox/india_compliance`,
  26 DocTypes). All three trees are present in the sandbox.
- **`git push` and `git fetch` do not work** — both fail with
  `remote: Missing header field, please provide AuthToken` … `error: 400`. Push **only** via the `github` power:
  `action=use`, `serverName=github`, `toolName=push_to_remote`, args
  `{owner:"psmontte", path:"/projects/sandbox/erp", remote_branch_name:"docs/localisation-india-gst",
  repository_name:"kiroweb-erpnext-investigations-01082026"}`. Because fetch fails, the local `origin/main` ref
  is **stale** — don't trust `git log origin/main..HEAD` counts.
- **`fs_write` to `/tmp` is not visible to bash.** Write scratch files under `/projects/sandbox/`.
- **`tools/verify_refs.py` was patched**: unprefixed citations resolve against the **first** `--app` when
  ambiguous across apps. Always pass all three `--app` roots or you get ~60 false failures.
- **Commit style:** imperative subject, no body needed.
  `git -c user.email=kiro@example.com -c user.name=Kiro commit -q -m "..."`
- **Filenames I have gotten wrong before:** `19-permissions-and-access-control.md`,
  `24-reporting-framework.md`, `18-metadata-and-runtime-ddl.md`, `14-banking-and-collections.md`,
  `16-stock-reservation-picking-warehouse.md`, `S06-multi-currency.md`.
- **Branch name is stale** — it says `docs/localisation-india-gst` but carries Tranche G and doc 58. Rename or
  re-cut if that matters for the merge.

---

## 7. Review discipline that has paid off

Every tranche closure has been followed by a semantic review, and each found real defects:
**32** in Tranche C, **39** in Tranche F, **8** in Tranche G (`semantic-review/`). The Tranche G review found
two *blocking* issues — the forgeable GUC, and a foreign key onto a partial unique index that PostgreSQL would
have rejected — plus a one-cent arithmetic cascade in S13.

**Doc 58 has not been reviewed.** That is the first thing to do next session, before or alongside the
transcription in §2. The pattern says to expect findings, and to check specifically: the five tables' DDL, the
G30–G41 wording against the body text, and whether the claims about Indian statute (Rule 46(b), CBDT Circular
23/2017, s.206C(1H), s.51/s.52) are stated as *upstream-observable facts* versus *legal assertions* — the
codebase evidence is verified, but the statutory characterisation is mine and is the weakest link in that
document.

---

## 8. Where to pick up

1. Review doc 58 (`semantic_reviewer`), fix findings, push.
2. Transcribe doc 58 §5 into `FINAL-SCHEMA` (§2 above), extend §28's register to G41, push.
3. Ask me the three questions in §3 if they are still unanswered — 1 and 2 gate the first migration.
4. Then implementation can start, and the build order is fixed:
   [doc 57 §8](logic/57-tranche-g-closure-and-our-security-spec.md#8-build-sequence-and-boundary), whose
   **step 0** is the boundary — because retrofitting scope columns and an execution-context contract onto
   populated tables is a rewrite, not a migration.
