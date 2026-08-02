# 56 — Consolidation and Group Reporting

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

Docs [53](53-multi-company-intercompany-and-transfer-pricing.md)–[55](55-multi-location-branch-and-segment.md)
assembled the axes: a company tree, inter-company crossings, currency layers and dimensions. This document
answers what a group asks of them: **what did the group as a whole earn and own?**

ERPNext answers that question with **two real reports**, and they are better than I initially credited — my
first pass at doc 53 claimed consolidation did not exist, which was wrong and is now corrected there. What the
reports do is aggregate a company subtree; what they do not do is any of the three things that make aggregation
into consolidation: **eliminate**, **weight by ownership**, and **separate what belongs to outside owners**.

Invariants continue from doc 55 at **T27**.

---

## 1. What exists

| Report | Lines | Shape |
|---|---:|---|
| `Consolidated Financial Statement` | 821 | Balance Sheet, P&L or Cash Flow with **one column per company** |
| `Consolidated Trial Balance` | 460 | **one merged** trial balance across companies |

They differ in intent. The first is a *side-by-side* statement — `get_company_columns` builds a column per
company (`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:294-339`), so it
presents the group as a set of columns a reader adds up mentally. The second genuinely *merges*, producing a
single set of balances (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:313-322`).

**Company selection is the tree.** `get_subsidiary_companies` reads the nested set and returns the whole subtree
(`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:519-529`):

```python
lft, rgt = frappe.get_cached_value("Company", company, ["lft", "rgt"])
return frappe.get_all("Company", filters={"lft": [">=", lft], "rgt": ["<=", rgt]}, pluck="name",
                      order_by="lft, rgt")
```

The Consolidated Trial Balance goes further and **validates** the selection: every chosen company must share a
root company, or it refuses
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:51-76`):

> Consolidated Trial Balance can be generated for Companies having same root Company.

That refusal is right, and it is the only structural group rule in the codebase. Companies are then sorted by
`lft` so parents precede children
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:77-83`).

Both reports handle the currency question (doc 54 §1): `get_reporting_currency` uses the shared default currency
when every company agrees and falls back to the root company's `reporting_currency` when they do not
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:323-336`), with conversion applied per
row (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:370-383`).

So: subtree selection, root validation, deterministic ordering, currency fallback, and a merged trial balance.
That is a real foundation.

---

## 2. Merging by account name

`consolidate_gle_data` decides whether two companies' rows are the same line
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:337-369`):

```python
for gle in data:
    if gle and gle["account_name"] == entry["account_name"]:
```

The join key is **the account's name string**. Two consequences follow, in opposite directions:

- two companies whose charts name the same concept differently — "Trade Receivables" and "Accounts Receivable" —
  produce **two separate consolidated lines** that a reader must know to add; and
- two companies whose charts reuse a name for different meanings **merge into one line** that means neither.

The Consolidated Financial Statement has the same shape at a different level: `update_parent_account_names`
normalises parent names across companies
(`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:480-505`), and
`get_account_heads` collects heads per root type across the company set
(`consolidated_financial_statement.py:467-479`) — again by name.

This is the difference between a **group chart of accounts** and a naming coincidence. A group that consolidates
seriously maintains a mapping from each company's local account to a group account; ERPNext infers it from
labels.

> **Invariant T27 — consolidation runs over a mapped group chart.** Every local account maps to exactly one
> group account for a given period, through an explicit effective-dated mapping. Consolidation aggregates on the
> **group account identity**, never on a name string. An unmapped local account with a non-zero balance blocks
> the run rather than appearing as its own line.

---

## 3. What is missing, and what each omission costs

Searching both reports for the relevant terms returns nothing: no `elimin`, no `minority`, no `intercompany`, no
`ownership`, no `unrealiz`.

### 3.1 No eliminations

Doc 53 established that a crossing produces two independent documents in two companies. Neither report knows
they are related, so on consolidation:

- an intra-group sale appears as **revenue in the seller and cost in the buyer**, inflating group revenue and
  group cost by the same amount;
- the matching receivable and payable both survive, inflating both sides of the balance sheet; and
- margin on goods still held inside the group is recognised as group profit, which it is not
  (doc 53 §4's `unrealized_profit_loss_account` is per company and never reaches a consolidated report).

The group's *net* profit is right in one narrow case — where the crossing is fully realised outward within the
period — and its revenue, cost, receivables and payables are wrong in every case.

### 3.2 No ownership weighting

`get_subsidiary_companies` returns the subtree unweighted, and doc 53 §1 established that
`Company` carries no ownership percentage. So a **60%-owned subsidiary is consolidated at 100%**, and there is no
way to express proportional or equity-method treatment. A joint venture and a wholly-owned subsidiary are
indistinguishable.

### 3.3 No minority interest

Following from §3.2: nothing separates the parent's share of a subsidiary's equity and profit from the outside
owners' share. A consolidated balance sheet without a non-controlling-interest line does not balance in the
accounting sense — it attributes to the parent value the parent does not own.

### 3.4 Nothing is stored

Both reports compute on demand and return columns and rows. There is no consolidation record, so:

- the same period can produce different numbers on two runs if any underlying document changed;
- a filed group statement cannot be reproduced;
- no elimination or minority entry could be *posted* even if computed, because there is no ledger to post to.

That is the deepest gap. Consolidation in ERPNext is a **view**, and a view cannot carry the adjustments
consolidation requires.

> **Invariant T28 — a consolidation is a run with stored, reproducible output.** Each consolidation is an
> immutable run naming the group, the period, the presentation currency, the method per subsidiary, the source
> watermark and every rate revision used. Its output — translated balances, eliminations, ownership
> apportionment and minority interest — is stored as facts. Re-running a closed period reproduces it exactly, and
> a restatement is a new run that supersedes rather than an overwrite.

---

## 4. The translation reserve, and why it is a plug

Doc 54 §4 covered this; it belongs here because it is where the number surfaces.
`calculate_foreign_currency_translation_reserve` computes
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:255-292`):

```text
opening residual = total opening_debit − total opening_credit
period residual  = total debit − total credit
FCTR row         = whichever side makes each residual zero
```

then inserts the row beside Equity — or beside Liability when no Equity row is found
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:293-312`) — and adds it into the
totals.

So the reserve is defined as *the plug that makes the trial balance balance after conversion.* It therefore
absorbs, indistinguishably: genuine translation differences, a missing exchange rate (doc 54 §2 returns `0.00`
when settings are disabled), a stale rate, and an unbalanced source ledger.

Under our design the residual is a **consequence** — you apply closing rates to balance-sheet items, average to
income, historical to equity, and whatever remains is the CTA, checked against an independently computed
expectation rather than defined as the gap.

---

## 5. Evidence versus projection

| Representation | Classification |
|---|---|
| `Company` nested set (`lft`, `rgt`) | the group structure — no ownership, no method |
| same-root validation | the one structural group rule (good) |
| `lft` ordering of companies | deterministic presentation order |
| per-company columns | side-by-side presentation |
| merged trial balance rows | consolidated output, **joined on `account_name`** |
| `get_reporting_currency` result | presentation currency, chosen per run |
| per-row currency conversion | in-run computation, discarded |
| Foreign Currency Translation Reserve | **residual plug**, not posted |
| eliminations, ownership weighting, minority interest | **do not exist** |
| a consolidation run, or any stored output | **does not exist** |

Everything in this table is transient except the company tree itself.

---

## 6. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md), doc 53 §8 (group structure and crossings), doc 54 §6
(translation) and doc 55 §7 (segments). Group tables are **group-scoped**, readable only by a principal holding
a group grant (doc 52 §8); they are the one place a read legitimately spans companies.

```sql
group_account(id, company_group_id, code, name, root_type root_type_enum,
    report_type report_type_enum, parent_id bigint NULL,
    effective_from date, effective_to date NULL)                       -- [GROUP-SCOPED]
   UNIQUE (company_group_id, code)
   CHECK (parent_id IS NULL OR parent_id <> id)

group_account_map(id, company_group_id, company_id, account_id, group_account_id,
    effective_from date NOT NULL, effective_to date NULL)
   UNIQUE (company_group_id, company_id, account_id, effective_from)
   EXCLUDE USING gist (company_group_id WITH =, company_id WITH =, account_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&)
   -- T27: aggregation joins on group_account_id. An unmapped account with a balance BLOCKS the run.

consolidation_run(id, company_group_id, period_start date, period_end date,
    presentation_currency_id, source_watermark bigint NOT NULL,
    result_hash char(64) NOT NULL, state consolidation_state_enum /*building|complete|superseded*/,
    supersedes_run_id bigint NULL, command_receipt_id, built_at timestamptz)
   UNIQUE (company_group_id, period_start, period_end, presentation_currency_id, result_hash)
   UNIQUE (company_group_id, command_receipt_id)
   -- one unsuperseded complete run per group and period, by deferred trigger

consolidation_member(id, company_group_id, consolidation_run_id, company_id,
    consolidation_method consolidation_method_enum /*full|proportional|equity|none*/,
    ownership_pct numeric(9,6) NOT NULL,
    translation_run_id bigint NULL,          -- doc 54 §6, when functional <> presentation
    company_group_edge_id bigint NOT NULL)   -- the ownership fact this was read from
   UNIQUE (company_group_id, consolidation_run_id, company_id)
   CHECK (ownership_pct > 0 AND ownership_pct <= 100)
   -- §3.2's gap: method and percentage are recorded PER RUN, sourced from the dated edge

consolidation_line(id, company_group_id, consolidation_run_id, group_account_id,
    dimension_key text, reporting_segment_id bigint NULL,
    contributed_amount numeric(19,4),        -- Σ members after translation and weighting
    eliminated_amount  numeric(19,4) NOT NULL DEFAULT 0,
    minority_amount    numeric(19,4) NOT NULL DEFAULT 0,
    group_amount numeric(19,4) NOT NULL)
   UNIQUE (company_group_id, consolidation_run_id, group_account_id, dimension_key,
           reporting_segment_id) NULLS NOT DISTINCT
   -- deferred: group_amount = contributed_amount − eliminated_amount − minority_amount, EXACTLY
   -- deferred: Σ group_amount over the run = 0 (the consolidated trial balance balances)

consolidation_member_contribution(id, company_group_id, consolidation_run_id, company_id,
    group_account_id, functional_amount numeric(19,4), rate_applied numeric(21,9),
    presentation_amount numeric(19,4), weighted_amount numeric(19,4))
   UNIQUE (company_group_id, consolidation_run_id, company_id, group_account_id)
   -- full audit trail: local → translated → weighted, per company and group account

consolidation_elimination(id, company_group_id, consolidation_run_id,
    elimination_kind elimination_kind_enum /*intercompany_revenue_cost|intercompany_balance|
                                            unrealised_margin|investment_in_subsidiary|
                                            intragroup_dividend|intragroup_loan*/,
    intercompany_transaction_id bigint NULL,   -- doc 53 §8: the crossing being eliminated
    unrealised_margin_id bigint NULL,          -- doc 53 §8: margin not yet realised outward
    debit_group_account_id, credit_group_account_id, amount numeric(19,4) NOT NULL,
    basis text NOT NULL)
   UNIQUE (company_group_id, consolidation_run_id, elimination_kind,
           intercompany_transaction_id, unrealised_margin_id) NULLS NOT DISTINCT
   CHECK (amount > 0 AND debit_group_account_id <> credit_group_account_id)
   -- §3.1's gap, closed by construction: every crossing recorded in doc 53 produces its elimination

minority_interest(id, company_group_id, consolidation_run_id, company_id,
    equity_share numeric(19,4), profit_share numeric(19,4),
    ownership_pct numeric(9,6) NOT NULL, nci_account_id bigint NOT NULL)
   UNIQUE (company_group_id, consolidation_run_id, company_id)
   -- §3.3's gap: the outside owners' share is a line, not an omission

fiscal_calendar_alignment(id, company_group_id, company_id,
    company_period_start date, company_period_end date,
    group_period_start date, group_period_end date,
    alignment_method alignment_enum /*coterminous|stub_period|interim_close|proportional*/)
   UNIQUE (company_group_id, company_id, group_period_start)
   -- subsidiaries with different year-ends: how each was aligned is RECORDED, not assumed
```

### 6.1 Ordering

```text
1  claim idempotency ; resolve the group and period
2  resolve members from company_group_edge effective at period end — method and ownership_pct per member
3  for each member whose functional currency <> presentation currency: require a complete
   translation_run (doc 54 §6); refuse if absent
4  align fiscal calendars; record the alignment method per member
5  map every local account with a balance to a group account; REFUSE on an unmapped non-zero account
6  insert consolidation_member_contribution: functional → translated → weighted by ownership_pct
7  insert consolidation_elimination for every intercompany_transaction and unrealised_margin in scope
8  compute minority_interest per member from ownership_pct
9  insert consolidation_line; run deferred checks:
      group_amount = contributed − eliminated − minority, exactly
      Σ group_amount = 0
      Σ segment amounts = entity amount per group account   (doc 55 §7 T26)
10 mark the run complete ; domain_event + outbox ; commit
```

Step 7 is the payoff of doc 53's design decision. Because a crossing is **one fact with two legs** rather than
two documents joined by mutable scalars, its elimination is derivable rather than reconstructed — and because
`unrealised_margin` tracks realisation (doc 53 §8), margin on goods still inside the group is eliminated and
released automatically as they are sold outward.

> **Invariant T29 — every intra-group effect is eliminated from an identified fact.** Each elimination cites the
> `intercompany_transaction` or `unrealised_margin` it derives from, so eliminations are complete by construction
> and reconcilable: for any period, Σ eliminations equals Σ crossings in scope. No elimination is a manual
> journal, and no crossing lacks one.

> **Invariant T30 — group results reconcile in three directions.** For every consolidation run: the consolidated
> trial balance balances exactly; each group account's amount equals contributions minus eliminations minus
> minority interest; and segment amounts sum to the entity amount. All three are deferred constraints, not
> report footnotes.

---

## 7. Defects and risks

1. **Aggregation joins on `account_name`**, so equivalent accounts named differently stay separate and
   differently-meaning accounts named the same merge
   (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:337-369`,
   `accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:480-505`).
2. **No eliminations**, so intra-group revenue, cost, receivables and payables are all double-counted (§3.1).
3. **No ownership weighting** — a 60%-owned subsidiary consolidates at 100%
   (`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:519-529`).
4. **No minority interest**, so value belonging to outside owners is attributed to the parent (§3.3).
5. **No consolidation is stored**, so a group statement is not reproducible and adjustments cannot be posted
   (§3.4).
6. **The translation reserve is a residual plug** that absorbs missing rates and unbalanced ledgers
   indistinguishably from real translation differences
   (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:255-292`).
7. **The FCTR row lands beside Liability when no Equity row exists**
   (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:293-312`).
8. **No fiscal-calendar alignment**: subsidiaries with different year-ends are aggregated by period filter with
   nothing recording how.
9. **Two reports with different semantics** — side-by-side columns versus a merged balance — can be read as if
   they answer the same question
   (`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:294-339`,
   `accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:313-322`).
10. **Consolidation reads across companies**, which under doc 52's boundary is exactly the operation that must
    require an explicit group-scoped grant — here it is an ordinary report permission.

Genuinely good, and adopted: the **same-root validation**
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:51-76`) — the only structural group
rule in the codebase, and correct; nested-set subtree selection
(`consolidated_financial_statement.py:519-529`); deterministic `lft` ordering
(`consolidated_trial_balance.py:77-83`); the shared-currency-else-root-reporting-currency fallback
(`consolidated_trial_balance.py:323-336`); per-company opening-balance handling for unclosed years
(`consolidated_financial_statement.py:127-169`); and the fact that a translation residual is surfaced **as a
named line** rather than silently absorbed into another account.

---

## 8. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Company nested set as the group structure | **Change** | `company_group_edge` with ownership, method and dates (doc 53 §8) |
| Subtree selection for members | **Adopt** | resolved from dated edges, recorded per run |
| Same-root validation | **Adopt** | constraint on run membership |
| `lft` ordering | **Adopt** | deterministic member ordering |
| Aggregation by `account_name` | **Reject** | `group_account_map` on account identity |
| Unmapped account appearing as its own line | **Reject** | refuses the run |
| Side-by-side per-company columns | **Adopt as a view** | a projection over `consolidation_member_contribution` |
| Merged trial balance | **Adopt** | `consolidation_line` |
| Shared-currency-else-reporting-currency | **Adopt the rule** | presentation currency explicit per run |
| Per-row conversion inside the report | **Change** | a stored `translation_run` per member (doc 54 §6) |
| FCTR as a balancing residual | **Reject** | rates prescribed per item class; residual is the consequence |
| FCTR beside Liability when Equity is absent | **Reject** | posted to a declared `cta_account_id` |
| FCTR surfaced as a named line | **Adopt** | same visibility, as a fact |
| Opening-balance handling for unclosed years | **Adopt** | explicit per member and period |
| No eliminations | **Reject** | `consolidation_elimination` derived from crossings (T29) |
| No ownership weighting | **Reject** | `ownership_pct` per member per run |
| No minority interest | **Reject** | `minority_interest` line per member |
| Nothing stored | **Reject** | `consolidation_run` with a result hash and watermark |
| No fiscal-calendar alignment | **Reject** | `fiscal_calendar_alignment` records the method |
| Cross-company read as an ordinary report permission | **Reject** | explicit group-scoped grant (doc 52 §8) |

Invariants introduced here are **T27–T30**. Doc 57 closes Tranche G and consolidates **T1–T30**.

---

Cross-references: [doc 53](53-multi-company-intercompany-and-transfer-pricing.md) (group structure, crossings and
`unrealised_margin` — the facts eliminations derive from),
[doc 54](54-multi-currency-layering.md) (translation runs and the CTA this section's plug replaces),
[doc 55](55-multi-location-branch-and-segment.md) (the reconciling segment axis),
[doc 52](52-tenant-isolation-and-rls-under-attack.md) (why a cross-company read needs a group grant),
[doc 07](07-period-close-and-opening-balances.md) (period close and opening balances),
[doc 24](24-reporting-framework.md) (the report framework both reports are built on),
[doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (chart of accounts and dimensions), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 57 — Tranche G closure and our security
specification.
