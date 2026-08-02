# 54 — Multi-Currency Layering

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

[Doc 53 §3.1](53-multi-company-intercompany-and-transfer-pricing.md) found that inter-company transactions are
**refused outright** when the two companies' currencies differ. That is the gap this document has to close, and
closing it requires being precise about something ERPNext leaves implicit: **how many currencies a number can be
expressed in, and which of them is authoritative.**

Accounting practice distinguishes three:

| Layer | Meaning |
|---|---|
| **Transaction** | the currency the deal was struck in |
| **Functional** | the currency the entity operates in — the one its books are kept in |
| **Presentation** | the currency the reader wants to see, including a group's reporting currency |

Docs 05 and 07 covered rate application and FX revaluation mechanically. This document evaluates the **layering**
and finds that ERPNext has two layers where three are needed, and that the boundary between translation and
revaluation is not drawn.

Invariants continue from doc 53 at **T19**.

---

## 1. Two currency fields, one of them undefined

`Company` carries **`default_currency`** and **`reporting_currency`**
(`setup/doctype/company/company.json:14-30`, `setup/doctype/company/company.json:960-970`).

`default_currency` is the functional currency in all but name: every `gl_entry` amount is expressed in it, the
inter-company check compares it (doc 53 §3.1), and party ledger currency is validated against it (doc 01 §1.6).

`reporting_currency` **is** used, but only by the consolidation reports, and only as a fallback.
`get_reporting_currency` decides (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:323-336`):

```text
if every selected company shares one default_currency → use that, ignore reporting_currency
if they differ                                        → use the ROOT company's reporting_currency
```

So a presentation currency is selected **only when the group is genuinely multi-currency**, and it comes from
one company's field rather than from the group. There is no stored, reproducible statement of a subsidiary's
balances in that currency — the conversion happens inside a report run
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:370-383`) and is discarded with it.

So the layering is: transaction currency on the document, functional currency on the ledger, and presentation
currency as a **report parameter**. The middle layer is never named, which is what makes the next two sections
possible.

> **Invariant T19 — three currency layers, each named and each recorded.** Every monetary fact stores its
> transaction currency and amount, the functional currency of the owning company and the amount in it, and the
> rate and rate-source used to convert between them. Presentation currency is **derived** — never stored on the
> fact — and a company's functional currency is immutable once any posted fact exists in it.

---

## 2. Rate resolution, and the four ways it can fail quietly

`get_exchange_rate` is the single entry point (`setup/utils.py:62-160`). Its resolution order:

```text
1  either currency missing            → bare `return`  (None)
2  from == to                          → 1
3  no date                             → today
4  Currency Exchange table, date <= transaction_date, ordered date desc, limit 1
       (filtered further by for_buying / for_selling when args says so)
       (window narrowed to `stale_days` unless `allow_stale`)
5  Currency Exchange Settings disabled → return 0.00
6  pegged-currency derivation, if enabled
7  external HTTP API, cached 6 hours
8  on any exception → log_error + msgprint, fall through
```

Four of these are silent failures with different values.

**Step 1 returns `None`, and the author says so.** The code carries its own open question
(`setup/utils.py:62-75`):

```python
if not (from_currency and to_currency):
    # manqala 19/09/2016: Should this be an empty return or should it throw and exception?
    return
```

A comment questioning whether a missing currency should raise, unresolved since 2016, on the function every
monetary conversion in the system calls.

**Step 5 returns `0.00`.** A disabled settings record makes the rate *zero*, not unavailable
(`setup/utils.py:100-108`). Doc 05 §5.11 already recorded this pattern; here it is at the source. A zero rate
does not fail — it produces zero-valued base amounts, which post and balance.

**Step 8 logs and continues.** The HTTP path wraps everything in `except Exception`, logs, shows a message, and
falls through (`setup/utils.py:112-160`). The caller receives whatever the function returns after that.

**Step 4 silently prefers the newest row within a window.** `order_by="date desc, name desc"` with `limit 1`
means two rates entered for the same date are disambiguated by **name** — a series counter. And staleness is a
*setting*: `allow_stale` permits an arbitrarily old rate, and when it is off the window is `stale_days` before
the transaction date (`setup/utils.py:76-99`). Neither branch records **which rate was used** on the resulting
document beyond the numeric value.

> **Invariant T20 — a rate is a dated, sourced, non-zero fact, and its absence is a refusal.** Conversion
> resolves exactly one `exchange_rate` row by (currency pair, purpose, effective date) under a declared staleness
> policy, and the posted fact records the **rate row's identity**, not merely its value. A missing, zero,
> stale-beyond-policy or unresolvable rate refuses the write. No conversion path returns zero, `NULL` or a
> logged warning in place of a rate.

---

## 3. Pegged currencies: correct arithmetic, undeclared authority

`get_pegged_currencies` loads a map of `source_currency → (pegged_against, ratio)`
(`setup/utils.py:13-28`), and `get_pegged_rate` handles four cases
(`setup/utils.py:30-60`):

```text
both pegged, same base      → (1 / from.ratio) * to.ratio
both pegged, different base → (1 / from.ratio) * rate(base_from → base_to) * to.ratio
from pegged to to           → from.ratio
to pegged to from           → 1 / to.ratio
otherwise                   → None
```

The arithmetic is right, including the cross-peg case that recurses into `get_exchange_rate` for the base pair.
This is a genuinely good piece of design and we adopt the model.

Two things are missing around it. The peg is **not effective-dated** — `Pegged Currency Details` is a child
table of a single `Pegged Currencies` document, so a peg that changed (as pegs do) has no history, and a
backdated document is converted at today's peg. And the whole mechanism is **opt-in**
(`allow_pegged_currencies_exchange_rates`), so the same currency pair resolves differently depending on a
setting.

The interaction with the API path is subtler. When fetching externally, pegged currencies are **substituted for
their base** in the request, and the returned value is then multiplied and divided by the ratios
(`setup/utils.py:112-160`):

```python
value *= pegged_currencies[to_currency]["ratio"]     # if to_currency is pegged
value /= pegged_currencies[from_currency]["ratio"]   # if from_currency is pegged
```

Correct, and dependent on the cache key — which is built from the **original** currency codes while the request
used the substituted ones (`setup/utils.py:112-160`). Two different logical rates can therefore share cache
semantics that were derived from a different pair.

---

## 4. Translation versus revaluation: the line is not drawn

These are different operations, and conflating them is the classic multi-currency error:

| | Revaluation | Translation |
|---|---|---|
| What | restates **monetary balances** at a closing rate | restates a whole **set of books** into another currency |
| Result | realised/unrealised FX gain or loss in P&L | a cumulative translation adjustment in equity |
| Scope | per account and party | per company, per period |

ERPNext implements the first and not the second.

`Exchange Rate Revaluation` computes per-row `gain_loss` and splits it into **booked** and **unbooked** totals
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:51-73`), with a
`rounding_loss_allowance` validated separately
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:43-50`) and accounts without a
gain/loss removed (`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:74-80`).

The booked/unbooked split is thoughtful — it distinguishes FX already recognised in the ledger from FX arising
only from restatement. That distinction is exactly what a translation adjustment needs, and it is not used for
one.

`calculate_exchange_rate_using_last_gle` derives an account's implied rate from its last GL entry
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:649-697`). Deriving a rate from
posted balances rather than from a rate table is a reasonable fallback and a poor authority: it means the
revaluation's starting point depends on posting order.

A translation residual **is** computed, in one place: `calculate_foreign_currency_translation_reserve` in the
Consolidated Trial Balance (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:255-292`).
Its method is worth quoting, because it defines what kind of number it is:

```python
opening_dr_cr_diff = total_row["opening_debit"] - total_row["opening_credit"]
dr_cr_diff         = total_row["debit"] - total_row["credit"]
fctr_row = {... "debit": abs(dr_cr_diff) if dr_cr_diff < 0 else 0.0, ...}
```

The reserve is **the amount required to make the consolidated trial balance balance** — a residual read off the
debit/credit difference after conversion, inserted next to Equity (or Liability when no Equity row is found,
`:293-312`) and added into the total row.

As a practical device in a report, that is defensible and it is honest about what it is. As a translation
adjustment it is not one: a CTA under the standard is derived from applying **prescribed rates by item class** —
closing for balance-sheet items, average for income, historical for equity — and the residual is the
*consequence*, not the definition. Here the residual is the definition, so nothing distinguishes translation
difference from a conversion error, a missing rate, or an unbalanced source ledger.

There is also **no CTA account on `Company`** (`setup/doctype/company/company.json:14-30`) and no stored
per-period translated balance: the reserve exists for the duration of a report run and is never posted.

> **Invariant T21 — revaluation and translation are distinct, both are dated facts.** Revaluation restates
> monetary balances at a dated closing rate and posts realised or unrealised FX to named accounts. Translation
> restates a company's period balances into a presentation currency using the method's prescribed rates —
> closing for balance-sheet items, average or transaction-date for income items, historical for equity — and
> the residual is posted to a cumulative translation adjustment. Neither is derived from posted balances, and
> both are reproducible for any past period from stored rates.

---

## 5. Evidence versus projection

| Representation | Classification |
|---|---|
| `Currency Exchange` row | the rate fact — dated, purpose-scoped |
| `allow_stale` / `stale_days` | policy that changes which fact is eligible |
| rate value copied onto a document | **the value, not the identity** of the rate used |
| `Company.default_currency` | functional currency in all but name |
| `Company.reporting_currency` | a label with no translation mechanism |
| `Pegged Currencies` child rows | peg ratios, **not effective-dated** |
| externally fetched rate | cached 6 hours under a key built from unsubstituted codes |
| `gl_entry.amount` | functional-currency amount — authoritative |
| `amount_in_account_currency` | transaction/account-currency amount |
| `Exchange Rate Revaluation` + its journal | revaluation evidence, booked/unbooked split |
| rate derived from last GL entry | posting-order-dependent inference |
| cumulative translation adjustment | **does not exist** |
| translated period balances | **do not exist** |

The gap that matters for doc 56: there is no stored, reproducible statement of what a subsidiary's balances are
worth in the group's currency for a closed period.

---

## 6. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) §2's `currency` and `exchange_rate`, doc 52 §8 and
doc 53 §8. Rates and pegs are **global reference data** (doc 50 §6 precedent); translation results are
company-scoped.

```sql
-- §2's exchange_rate gains identity, source and a staleness policy anchor
exchange_rate(id, from_currency_id, to_currency_id, valid_on date, rate numeric(21,9),
    purpose rate_purpose_enum /*general|buying|selling|closing|average|historical*/,
    rate_source_id bigint NOT NULL, retrieved_at timestamptz NOT NULL,
    supersedes_rate_id bigint NULL)                                          -- [GLOBAL]
   UNIQUE (from_currency_id, to_currency_id, valid_on, purpose, rate_source_id)
   CHECK (rate > 0)                       -- a zero rate is unrepresentable
   -- append-only; a correction supersedes rather than overwrites

rate_source(id, code, name, kind rate_source_kind_enum /*manual|feed|peg|central_bank|
                                                        contractual|group_policy*/,
    trust_rank smallint NOT NULL)  UNIQUE (code)                             -- [GLOBAL]
   -- resolution prefers the lowest trust_rank; ties are impossible by the unique above

currency_peg_revision(id, source_currency_id, pegged_against_currency_id,
    ratio numeric(21,9) NOT NULL, effective_from date NOT NULL, effective_to date NULL,
    state revision_state_enum)                                               -- [GLOBAL]
   UNIQUE (source_currency_id, effective_from)
   EXCLUDE USING gist (source_currency_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
   CHECK (ratio > 0 AND source_currency_id <> pegged_against_currency_id)
   -- pegs CHANGE; effective dating is what makes a backdated document reproducible

rate_policy_revision(id, company_id, purpose rate_purpose_enum,
    max_age_days integer NOT NULL, allow_peg_derivation bool NOT NULL,
    on_missing missing_rate_action_enum /*refuse*/ NOT NULL DEFAULT 'refuse',
    effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, purpose, effective_from)
   CHECK (max_age_days >= 0)
   -- `refuse` is the only permitted action: there is no configuration that yields zero or NULL

-- every monetary fact carries the rate's IDENTITY, not just its value
-- (applied to gl_entry, stock_move value events, settlement, determination components, …)
--   transaction_currency_id, transaction_amount numeric(19,4)
--   functional_currency_id,  functional_amount  numeric(19,4)
--   exchange_rate_id bigint NOT NULL, rate_applied numeric(21,9) NOT NULL
--   deferred: functional_amount = round(transaction_amount * rate_applied, functional precision)

company_functional_currency(id, company_id, currency_id,
    effective_from date NOT NULL, effective_to date NULL)
   UNIQUE (company_id, effective_from)
   -- L2 trigger: immutable once any posted fact exists for that company in that period.
   -- A functional-currency change is a modelled event, not a field edit.

translation_run(id, company_id, company_group_id, presentation_currency_id,
    period_start date, period_end date, method translation_method_enum /*current_rate|
                                                                        temporal|monetary_nonmonetary*/,
    closing_rate_id bigint NOT NULL, average_rate_id bigint NOT NULL,
    source_watermark bigint NOT NULL, result_hash char(64) NOT NULL,
    state translation_state_enum, command_receipt_id)
   UNIQUE (company_id, company_group_id, presentation_currency_id, period_start)
   UNIQUE (company_id, command_receipt_id)

translated_balance(id, company_id, translation_run_id, account_id, dimension_key text,
    functional_amount numeric(19,4), rate_applied numeric(21,9),
    rate_class rate_class_enum /*closing|average|historical*/,
    presentation_amount numeric(19,4))
   UNIQUE (company_id, translation_run_id, account_id, dimension_key)
   -- deferred: Σ presentation_amount over the run = 0 + the CTA residual, exactly

translation_adjustment(id, company_id, translation_run_id,
    cta_account_id bigint NOT NULL, amount numeric(19,4) NOT NULL,
    voucher_id bigint NULL REFERENCES voucher(id))
   UNIQUE (company_id, translation_run_id)
   -- the residual that makes a translated trial balance balance. It is a FACT, per run.
```

### 6.1 Resolution ordering

```text
1  resolve the company's functional currency for the posting date
2  if transaction currency = functional currency → rate 1, no lookup
3  resolve rate_policy_revision for (company, purpose, date)
4  select exchange_rate by (pair, purpose, valid_on <= date, within max_age_days),
   preferring the lowest trust_rank; ONE row by construction
5  if none and allow_peg_derivation → derive through currency_peg_revision effective on that date,
   recursing for the base pair; the derivation records BOTH rate identities
6  if still none → REFUSE the write (never 0, never NULL, never a logged warning)
7  store transaction amount, functional amount, exchange_rate_id and rate_applied on the fact
8  deferred check: functional_amount = round(transaction_amount × rate_applied)
```

An external feed writes `exchange_rate` rows **out of band** — a rate fetch is never inside a posting
transaction, so §2 step 7's synchronous HTTP call inside a write disappears.

### 6.2 What this gives doc 53 and doc 56

- **The cross-currency crossing** doc 53 §3.1 refuses becomes ordinary: each leg is posted in its own functional
  currency, both reference the same `intercompany_transaction`, and the transfer price is agreed in a stated
  transaction currency. The legs agree on **transaction** amount exactly; their functional amounts differ, and
  that difference is FX, not a mismatch.
- **Consolidation** gets a stored, reproducible input: `translated_balance` per company, period and
  presentation currency, with the CTA as a fact rather than a plug.

> **Invariant T22 — conversion is reproducible for any past instant.** Re-running any conversion, revaluation or
> translation over a closed period reproduces the stored result exactly, because rate rows are append-only and
> superseded rather than overwritten, pegs are effective-dated, and every fact names the rate identity it used.
> A rate correction produces a new superseding row and an explicit restatement — never a changed historical
> number.

---

## 7. Defects and risks

1. **A missing currency returns `None`**, with the author's own unresolved comment asking whether it should
   throw (`setup/utils.py:62-75`).
2. **A disabled settings record returns a rate of `0.00`** (`setup/utils.py:100-108`).
3. **Rate-fetch failure logs and falls through** (`setup/utils.py:112-160`).
4. **Same-date rates are disambiguated by name** — a series counter — via `order_by "date desc, name desc"`
   (`setup/utils.py:76-99`).
5. **Staleness is a setting, not a policy per purpose**; `allow_stale` permits arbitrarily old rates
   (`setup/utils.py:76-99`).
6. **Documents store the rate value, not the rate's identity**, so which row was used is unrecoverable.
7. **Pegs are not effective-dated** — a single child table, so a changed peg rewrites history
   (`setup/utils.py:13-28`).
8. **Peg derivation is opt-in**, so one pair resolves differently by setting
   (`setup/utils.py:100-160`).
9. **The API cache key uses unsubstituted currency codes** while the request used substituted ones
   (`setup/utils.py:112-160`).
10. **A synchronous HTTP call sits in the conversion path** — inside whatever transaction is posting
    (`setup/utils.py:112-160`).
11. **`reporting_currency` is used only as a report fallback**, taken from the root company and only when the
    group's currencies differ
    (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:323-336`).
12. **The translation reserve is a balancing plug**, derived from the post-conversion debit/credit difference
    rather than from prescribed rates by item class, and inserted next to Equity — or Liability when no Equity
    row exists (`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:255-312`).
12a. **No CTA account and no stored translated balances**: the reserve lives only inside a report run
    (`setup/doctype/company/company.json:14-30`).
13. **Revaluation can derive its rate from the last GL entry**, making the result posting-order dependent
    (`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:649-697`).
14. **Functional currency is a mutable field** on `Company`, with nothing freezing it once posted facts exist
    (`setup/doctype/company/company.json:14-30`).

Genuinely good, and adopted: the four-case peg arithmetic including cross-peg recursion
(`setup/utils.py:30-60`), purpose-scoped rates (`for_buying` / `for_selling`,
`setup/utils.py:76-99`), the **booked versus unbooked** gain/loss split
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:51-73`), the explicit
`rounding_loss_allowance` (`exchange_rate_revaluation.py:43-50`), dropping accounts with no gain or loss
(`exchange_rate_revaluation.py:74-80`), and rate caching as a concept.

---

## 8. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| `default_currency` as the ledger currency | **Adopt, rename** | `company_functional_currency`, effective-dated and frozen once posted |
| `reporting_currency` as a report fallback | **Change** | presentation currency is a parameter of a stored `translation_run` |
| Transaction + base amounts on every row | **Adopt** | plus the rate **identity** |
| Rate value copied to the document | **Change** | `exchange_rate_id` + `rate_applied` |
| `Currency Exchange` dated rows | **Adopt** | append-only, sourced, superseding |
| Purpose-scoped rates (buying/selling) | **Adopt and extend** | plus closing, average, historical |
| Latest-on-or-before selection | **Adopt** | with an explicit `max_age_days` and trust ranking |
| Disambiguation by `name` | **Reject** | `rate_source.trust_rank` makes it deterministic |
| `allow_stale` setting | **Reject** | staleness is a policy per company and purpose |
| Missing currency → `None` | **Reject** | refuse |
| Disabled settings → `0.00` | **Reject** | `CHECK (rate > 0)`; refusal on absence |
| Exception → log and continue | **Reject** | refuse and record |
| Four-case peg arithmetic | **Adopt** | same, over effective-dated pegs |
| Cross-peg recursion via the base pair | **Adopt** | both rate identities recorded |
| Non-dated pegs | **Reject** | `currency_peg_revision` with an exclusion constraint |
| Opt-in peg derivation | **Change** | declared on the rate policy |
| Synchronous HTTP fetch in the conversion path | **Reject** | feeds write rate rows out of band |
| 6-hour rate cache | **Adopt** | keyed on the resolved pair, advisory only |
| Booked vs unbooked FX split | **Adopt** | the same split drives revaluation and CTA |
| `rounding_loss_allowance` | **Adopt** | explicit tolerance on the revaluation, not on the ledger |
| Rate derived from the last GL entry | **Reject** | rates come from `exchange_rate` |
| Translation inside a report run | **Change** | `translation_run` + `translated_balance`, stored and reproducible |
| CTA as a balancing plug | **Reject** | rates prescribed per item class; the residual is a consequence, posted to `cta_account_id` |
| Cross-currency inter-company refused | **Reject** | legs in different functional currencies, one agreed transaction amount |

Invariants introduced here are **T19–T22**. Doc 55 continues at **T23** with location, branch and segment
dimensions.

---

Cross-references: [doc 05](05-taxes-totals-and-pricing.md) (rate application in document calculation, and the
zero-rate pattern), [doc 07](07-period-close-and-opening-balances.md) (FX revaluation at period close),
[doc 01](01-gl-posting-engine.md) (`gl_entry`'s dual-currency columns and exact balance),
[doc 04](04-ar-ap-and-settlement.md) (FX gain/loss on settlement),
[doc 53](53-multi-company-intercompany-and-transfer-pricing.md) (the cross-currency crossing this closes),
[doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (accounts and dimensions the translation runs over),
[S06](../scenarios/S06-multi-currency.md) (the worked multi-currency scenario), and
[`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 55 — multi-location, branch and segment.
