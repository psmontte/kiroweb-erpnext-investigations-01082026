# S13 — Cross-Company, Cross-Currency Crossing → Translation → Consolidation → Isolation Under Attack

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`,
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`, or prefixed `frappe/` /
> `india_compliance/`.
>
> Continues **[S12](S12-gst-invoice-e-invoice-and-gstr1.md)** — same seller, AlphaCo, now a subsidiary in a
> three-company group, selling to a fellow subsidiary in another currency from its *second* GST registration.
> Subsystem detail is in **[docs 50–57](../logic/50-authentication-session-and-tenant-context.md)**.
>
> This is an investigation document. It shows what is written, in what order, and where the design does and
> does not hold. It is also the only scenario in this repository with a second half: after the accounting, it
> walks the same flow as an **attacker**, because a group that consolidates correctly and leaks across
> companies has not solved the problem it appears to have solved.

---

## 1. The worked example

A three-company group closes March and produces consolidated statements in EUR. One inter-company sale
crosses a currency boundary and a national boundary, and 60% of the goods are still on hand at period end.

### 1.1 The group

| Company | Functional currency | Ownership | Places |
|---|---|---|---|
| **HoldCo** | EUR | parent | Amsterdam (segment *Corporate*) |
| **AlphaCo** | INR | 100% held by HoldCo, since incorporation | Mumbai — GSTIN `27AACCA1234A1Z5` (segment *India-West*); Bengaluru — GSTIN `29AACCA1234A2Z2` (segment *India-South*) |
| **BetaCo** | GBP | **60%** held by HoldCo, since incorporation | London (segment *UK*) |

Presentation currency for the run is **EUR**. Both subsidiaries were acquired at incorporation at par, so
there is no goodwill and no pre-acquisition reserve — declared, not assumed, so the arithmetic below is
checkable. Minority interest is therefore **40% of BetaCo**.

### 1.2 The crossing

| Fact | Value |
|---|---|
| Seller | AlphaCo, shipped from **Bengaluru** — so the Karnataka registration `29AACCA1234A2Z2`, not Mumbai's |
| Buyer | BetaCo, London |
| Goods | 100 × `WIDGET-1` |
| AlphaCo's cost | INR 5,000 each → **INR 500,000** |
| Transfer price | INR 6,000 each → **INR 600,000** (margin INR 100,000) |
| Invoice currency | **INR** — so BetaCo carries an INR-denominated payable |
| Crossing date | 20 March, rate 1 GBP = 100 INR → BetaCo records **GBP 6,000** |
| Onward sale | BetaCo sells **40** units externally for GBP 100 each = GBP 4,000; **60 units remain on hand** |
| Settlement | unpaid at 31 March |
| GST | export of goods from the Karnataka registration — zero-rated, place of supply outside India |

### 1.3 Rates

| Purpose | Pair | Rate |
|---|---|---|
| Transaction, 20 March | GBP/INR | 1 GBP = 100 INR |
| Closing, 31 March | EUR/INR | 1 EUR = 90 INR |
| Closing, 31 March | EUR/GBP | 1 EUR = 0.85 GBP |
| Average, March | EUR/INR | 1 EUR = 88 INR |
| Average, March | EUR/GBP | 1 EUR = 0.86 GBP |
| Historical (equity, at incorporation) | EUR/INR | 1 EUR = 80 INR |
| Historical (equity, at incorporation) | EUR/GBP | 1 EUR = 0.80 GBP |

Derived closing GBP/INR = 90 / 0.85 = **105.882353 INR per GBP**. That number matters twice: it is what
BetaCo's payable must be revalued at, and it is the only reason the intra-group balance eliminates to zero.

### 1.4 Local trial balances at 31 March, before any group work

**AlphaCo (INR)**

| Account | Dr | Cr |
|---|---|---|
| Cash | 200,000 | |
| Receivable — BetaCo | 600,000 | |
| Inventory | 300,000 | |
| Cost of sales | 500,000 | |
| Share capital | | 800,000 |
| Retained earnings, opening | | 200,000 |
| Revenue — intra-group | | 600,000 |
| **Total** | **1,600,000** | **1,600,000** |

**BetaCo (GBP)** — after the closing revaluation of its INR payable from GBP 6,000 to
600,000 ÷ 105.882353 = **GBP 5,666.67**, recognising an FX gain of GBP 333.33

| Account | Dr | Cr |
|---|---|---|
| Cash | 6,600.00 | |
| Inventory (60 × GBP 60) | 3,600.00 | |
| Cost of sales (40 × GBP 60) | 2,400.00 | |
| Payable — AlphaCo | | 5,666.67 |
| Share capital | | 2,000.00 |
| Retained earnings, opening | | 600.00 |
| Revenue — external | | 4,000.00 |
| FX gain on revaluation | | 333.33 |
| **Total** | **12,600.00** | **12,600.00** |

**HoldCo (EUR)**

| Account | Dr | Cr |
|---|---|---|
| Investment in AlphaCo | 10,000 | |
| Investment in BetaCo | 1,500 | |
| Cash | 2,800 | |
| Admin expense | 200 | |
| Share capital | | 14,000 |
| Retained earnings, opening | | 500 |
| **Total** | **14,500** | **14,500** |

---

## 2. Stage 1 — establishing who is acting, and in which company

Every stage after this one depends on the answer, so it is worth asking first. In the pinned tree there are
four candidate places for it, and none of them holds it.

**Probe 1 — the database.** Is there a tenant context that a policy could read?

```text
$ grep -rn "current_setting" frappe/ erpnext/ --include=*.py
frappe/tests/test_query_builder.py:368
```

One occurrence, in a query-builder test. There is no row-level security, no policy, no tenant context
function. Company is a data dimension, and confinement to it is the application's job.

**Probe 2 — the session.** `Session.insert_session_record` writes the session document
(`frappe/sessions.py:256-310`). It carries `user`, `sid`, `device`, `session_data`, `ip_address`,
`session_country` — and no company. There is nowhere for group scope to live even if something wanted to
enforce it.

**Probe 3 — the request.** `HTTPRequest.connect` / `validate_auth` resolve a user
(`frappe/auth.py:123-148`). Resumption failure does not deny; it downgrades to `Guest`
(`frappe/sessions.py:346-360`). The fail-closed guard for API authentication only fires when an
`Authorization` header was actually present (`frappe/auth.py:642-658`), and which DocType authenticates the
caller is selected by a caller-supplied `Frappe-Authorization-Source` header
(`frappe/auth.py:709-734`).

**Probe 4 — the scoping mechanism.** `get_user_permissions` is what confines a user to AlphaCo:

```python
# frappe/permissions.py:351-380
if not user_permissions:
    return          # ← no rules found: no restriction
```

Absence of rules means unrestricted. And the strict path that would catch a *blank* company on a document is
off by default and switched off again for local (unsaved) documents
(`frappe/permissions.py:413-476`, `frappe/permissions.py:351-395`) — which is precisely the moment
`company` is being assigned.

**Result of Stage 1.** There is no answer to "which company is this session acting in" that anything below
the application can rely on. Every number in the rest of this scenario is produced by code that could have
read any company's rows, and in **892** places explicitly does
(`ignore_permissions=True` — 524 in Frappe, 368 in ERPNext), plus 34 identity switches in ERPNext via
`frappe.set_user` or `flags.ignore_permissions`.

---

## 3. Stage 2 — the crossing, upstream

### 3.1 The counterparty is guessed

AlphaCo raises the Sales Invoice; the mirror Purchase Invoice in BetaCo is derived by
`make_inter_company_transaction`. Resolving *which* internal party represents the buyer:

```text
find the internal party whose address matches      → if none,
take parties[0]                                    → whatever the child table returns first
```

(`accounts/doctype/sales_invoice/mapper.py:126-148`). With one internal customer per company this happens to
be right. With two — a genuine case, because a group with a service company and a trading company has two —
the crossing is resolved by row order. Reference validation later re-derives the same thing with a
`get_value` on a multi-match filter (`accounts/doctype/sales_invoice/services/inter_company.py:40-49`),
picking one row again, possibly a different one.

### 3.2 The currency is refused outright

This is where S13 stops being a walkthrough of ERPNext and becomes a walkthrough of its absence:

```text
AlphaCo functional currency : INR
BetaCo  functional currency : GBP
→ inter-company mapping refuses
```

(`accounts/doctype/sales_invoice/mapper.py:149-175`). The legs must share a currency. A group whose
subsidiaries are in different countries cannot record an inter-company sale at all. **Everything from §3.3
onward is therefore hypothetical in the pinned tree** — it is what would happen if the two companies happened
to share a currency, which is the only configuration upstream supports.

### 3.3 The transfer price is not a policy

Three rules exist and each is optional or misdirected:

- **Price list must be both buying and selling** — a role check on a price list, not an approval of a price
  (`accounts/services/internal_transfer.py:120-135`).
- **`ignore_pricing_rule`** is set on the document, suppressing promotional rules. The intent is right — a
  transfer price is not a discount — but it is a field on one document rather than a policy for the company
  pair (`accounts/services/internal_transfer.py:120-135`).
- **`maintain_same_internal_transaction_rate`** makes the two legs agree — and it is **opt-in and off by
  default** (`accounts/services/internal_transfer.py:104-119`). With it off, AlphaCo can invoice INR 600,000
  and BetaCo can record INR 590,000, and nothing objects. Nothing else in the model constrains quantity, date
  or amount between legs at all.

### 3.4 The pairing is two mutable scalars

The two documents reference each other through `inter_company_invoice_reference` on each side
(`accounts/doctype/sales_invoice/services/inter_company.py:66-86`). Validation is bidirectional and correct
as far as it goes (`accounts/doctype/sales_invoice/services/inter_company.py:40-49`), and
`Allowed To Transact With` is a real permission list
(`accounts/doctype/sales_invoice/services/inter_company.py:50-64`). But the link is a field, and
`unlink_inter_company_doc` clears it — **after posting**. Two submitted, posted, GL-affecting documents can
be silently divorced, after which nothing in the database records that a crossing ever happened.

### 3.5 The unrealised margin is parked

`update_gl_entries_for_internal_transfer` diverts the margin to
`Company.unrealized_profit_loss_account` (`accounts/services/internal_transfer.py:37-53`). Three things are
wrong and one is subtle:

1. It is **per company**, so INR 100,000 arrives in an account with no reference to the transaction, the
   items or the quantity that produced it.
2. There is **no realisation mechanism**. When BetaCo sells 40 of the 100 units onward, nothing reduces the
   parked amount. Realisation is a manual journal somebody has to remember, and to size correctly.
3. `is_internal_transfer()` tests `represents_company == company`
   (`accounts/services/internal_transfer.py:19-29`) — a *same-company* relation — so the path does not
   even cover every crossing.

The subtle one: the concept is right. Upstream knows intra-group margin is not profit. It just has nowhere
durable to record it, so it records it in a place that cannot be reconciled.

---

## 4. Stage 3 — period end, upstream: revaluation and translation

### 4.1 The revaluation that makes elimination possible

BetaCo's payable is denominated in INR. At 31 March it must be restated to GBP 5,666.67 at the closing
GBP/INR rate, or the intra-group balance will not eliminate. `Exchange Rate Revaluation` does this and its
core design is good — the **booked versus unbooked** gain/loss split is a real distinction
(`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:51-73`), accounts with no
difference are dropped (`exchange_rate_revaluation.py:74-80`), and `rounding_loss_allowance` is an explicit
tolerance on the revaluation rather than a fudge in the ledger (`exchange_rate_revaluation.py:43-50`).

One defect undoes the reproducibility: the rate can be derived from the **last GL entry** rather than from a
rate table (`accounts/doctype/exchange_rate_revaluation/exchange_rate_revaluation.py:649-697`), so the result
depends on posting order. Re-run the same revaluation after a backdated entry and you get a different number
with nothing recording why.

### 4.2 Translation does not exist

To consolidate in EUR, AlphaCo's INR balances and BetaCo's GBP balances must be translated. Searching for the
mechanism produces a field name and nothing behind it: `Company.default_currency` is the functional currency
in all but name, and `reporting_currency` is used in exactly one place — as a fallback inside a report, taken
from the root company, and only when the group's currencies differ
(`accounts/report/consolidated_trial_balance/consolidated_trial_balance.py:323-336`). There is no CTA account
on `Company` (`setup/doctype/company/company.json:14-30`), no translated-balance table, and no translation
run. Translation happens per row inside a report execution and is discarded when the report closes.

Four ways rate resolution then fails quietly, all of which this scenario would hit:

| Failure | Citation |
|---|---|
| missing currency returns `None`, with the author's own unresolved comment asking whether it should throw | `setup/utils.py:62-75` |
| disabled settings return a rate of **`0.00`** | `setup/utils.py:100-108` |
| fetch failure logs and falls through | `setup/utils.py:112-160` |
| same-date rates disambiguated by `name` — a series counter | `setup/utils.py:76-99` |

A `0.00` rate is the one that matters most here: it does not raise, it silently values AlphaCo's entire
balance sheet at zero and the consolidation still produces a report.

---

## 5. Stage 4 — consolidation, upstream

Two reports exist. `Consolidated Financial Statement` gives one column per company in the subtree
(`accounts/report/consolidated_financial_statement/consolidated_financial_statement.py:44-68`), and
`Consolidated Trial Balance` genuinely merges (`consolidated_trial_balance.py:32-45`). The codebase's only
structural group rule lives here and is correct: all selected companies must share a root
(`consolidated_trial_balance.py:51-76`). Member ordering is deterministic by `lft`
(`consolidated_trial_balance.py:77-83`) and per-company opening balances for unclosed years are handled
explicitly (`consolidated_financial_statement.py:127-169`).

What the merge does with our three companies:

**It joins on `account_name`.** AlphaCo's "Stock In Hand", BetaCo's "Inventory" and HoldCo's chart are matched
by string (`consolidated_trial_balance.py:337-369`,
`consolidated_financial_statement.py:480-505`). Two accounts meaning the same thing stay on separate lines;
two accounts named the same thing merge regardless of meaning.

**It eliminates nothing.** Group revenue becomes 11,469.34 instead of 4,651.16, because AlphaCo's INR 600,000
intra-group sale is counted as group turnover. The receivable and the payable both appear. The INR 60,000 of
margin sitting in BetaCo's 60 unsold units is group profit.

**It weights nothing.** BetaCo is consolidated at 100%
(`consolidated_financial_statement.py:519-529`). There is no minority interest line, so 40% of BetaCo's net
assets and 40% of its profit are presented as the parent's.

**The translation reserve is a plug.** The FCTR is computed as the post-conversion debit/credit difference
(`consolidated_trial_balance.py:255-292`) — so a missing rate, a `0.00` rate, an unbalanced source ledger and
a genuine translation difference all arrive in the same number, indistinguishable. When no Equity row exists
in the output it is inserted next to **Liability** (`consolidated_trial_balance.py:293-312`). Surfacing it as
a named line is right and we keep that; deriving it as a residual is the defect.

**Nothing is stored.** No run, no watermark, no rates used, no result. The March consolidation cannot be
reproduced in April, and a consolidation adjustment cannot be posted because there is no ledger to post it to.

---

## 6. Stage 5 — the same flow as an attacker, upstream

A BetaCo user — legitimately authenticated, holding only BetaCo `User Permission` rows — wants AlphaCo's
transfer price.

| Attempt | Result |
|---|---|
| `frappe.client.get_value` on AlphaCo's Sales Invoice | `DatabaseQuery` applies permissions, so this is filtered — the one path that works |
| a Query Report with `select … from tabSales Invoice` | report capability is checked at **doctype** level; row filtering is left to the report author (`frappe/desk/query_report.py:248-300`) |
| any server script or hook reaching `frappe.db.sql` / `get_value` / `get_values` | the database layer applies **no** permissions at all (`frappe/database/database.py:196-456`, `frappe/database/database.py:533-610`, `frappe/database/database.py:611-727`) |
| enqueue work and let it run | background jobs default to `Administrator` — total authorisation acquired by omission (`frappe/utils/background_jobs.py:245-266`, `frappe/__init__.py:410-421`) |
| `frappe.client.get_count` with a company filter | counts are computed without scope, leaking cardinality (`frappe/client.py:78-93`, `frappe/desk/reportview.py:58-101`) |
| link-title validation on AlphaCo's invoice name | an existence oracle (`frappe/client.py:431-531`) |
| a Prepared Report generated earlier under another scope | results were computed then, and re-reads gate on the artefact (`frappe/desk/query_report.py:275-300`) |
| ask the permission system what it would allow | it answers (`frappe/client.py:329-339`, `frappe/client.py:340-350`) |
| find one of 892 `ignore_permissions=True` call sites reachable from a whitelisted endpoint | the check is a **parameter** any caller can set (`frappe/model/db_query.py:124-200`) |

The load-bearing observation is that only the first row is enforced, and it is enforced in one class,
`DatabaseQuery`. Everything else is a different path to the same rows. Meanwhile the consolidation of §5 reads
all three companies — which is the operation that *most* needs an explicit cross-company authority — as an
ordinary report permission.

---

## 7. The same flow in our design

### 7.1 Context first, and the crossing is two writes in two scopes

The connection-acquisition routine resolves the `auth_session` row and sets the context before any statement
runs:

```sql
SET LOCAL auth.company_id = '<alphaco>';
-- every policy below now evaluates against auth.current_company()
```

An unresolvable session sets nothing, `auth.current_company()` returns `NULL`, `company_id = NULL` is unknown,
and every policy denies (**T1, T2, T3**). This has an immediate and non-obvious consequence for the crossing:
**AlphaCo's user cannot write BetaCo's leg.** The `WITH CHECK` clause on BetaCo's tables rejects it.

So the crossing is:

1. AlphaCo's session writes the `intercompany_transaction` header and AlphaCo's leg.
2. A durable work row is enqueued carrying `principal_id` and `company_id = <betaco>`, both `NOT NULL`
   (**T11**).
3. The worker claims it, sets context to BetaCo, and writes BetaCo's leg. The principal is a service identity
   with membership in both companies and an explicit grant; the grant identity is recorded on the transaction
   (**T4, T9**).
4. Deferred constraints on the pair are checked at commit.

Upstream's version of step 2 is `frappe.set_user` or a job defaulting to `Administrator`. Ours is a named
principal with a recorded, expiring grant, and if it cannot be resolved the job **fails and is recorded as
failed** rather than proceeding with more authority than it was given.

### 7.2 The crossing is one immutable fact

```text
intercompany_transaction
  id, company_group_id, seller_company_id=alphaco, buyer_company_id=betaco,
  intercompany_relationship_id            → unique per ordered pair and period (T15)
  transfer_price_policy_revision_id       → approved, effective-dated (T16)
  transaction_currency=INR, transaction_amount=600,000
  effective_date=2026-03-20
  seller_leg_id, buyer_leg_id             → immutable once both present (T17)
  authorising_delegation_grant_id
```

Deferred constraints require the legs to agree exactly on quantity (100), transfer price (INR 6,000),
transaction currency (INR) and effective date. AlphaCo's leg is in INR functional; BetaCo's leg is in GBP
functional with `transaction_currency = INR`, `transaction_amount = 600,000`, `functional_amount = 6,000.00`
and `exchange_rate_id` naming the 20 March GBP/INR row (**T19, T20**). The cross-currency case that
`accounts/doctype/sales_invoice/mapper.py:149-175` refuses is the ordinary case here; what makes it safe is that both legs agree on the
**transaction** amount, and each converts it with a recorded rate identity.

There is no unlink. A crossing is reversed as a whole, by a reversing transaction that cites it.

```text
unrealised_margin
  intercompany_transaction_id, item_id=WIDGET-1,
  transferred_qty=100, margin_functional=INR 100,000, margin_currency=INR
unrealised_margin_realisation
  unrealised_margin_id, realised_qty=40, realised_at=<betaco's external sale>,
  triggering_stock_move_id
```

Group margin at any instant is transferred minus realised, derived (**T18**). At 31 March: 100 − 40 = 60 units
unrealised, **INR 60,000**. Nobody has to remember to size a journal.

### 7.3 The GST seam: which registration, and therefore which return

The crossing ships from **Bengaluru**. `operating_location` for the Bengaluru site resolves through
`location_registration` to GSTIN `29AACCA1234A2Z2`, and the determination records *which* registration it
resolved and *by which rule* (**T25**). The supply is an export of goods, so the place of supply is outside
India and the supply is zero-rated.

Two consequences that upstream's model cannot express:

- The turnover lands in **Karnataka's** GSTR-1, not Maharashtra's. AlphaCo has two independent statutory
  periods, and closing one does not close the other (**T25**, and doc 49's `return_period`).
- Upstream would resolve this by comparing `place_of_supply[:2]` — the first two characters of a display
  label — against `company_gstin[:2]`, with "outside India" carried as the literal `"96-Other Countries"`
  (`india_compliance/gst_india/overrides/transaction.py:545-576`,
  `india_compliance/gst_india/overrides/transaction.py:593-625`). The registration used is inferred from an
  `Address` (`india_compliance/gst_india/overrides/address.py:13-50`), which is not a modelled dimension at
  all.

### 7.4 Revaluation, then translation — separately, both stored

**Revaluation** (BetaCo's own books, GBP): the INR payable restated at the closing GBP/INR rate resolved from
`exchange_rate`, never from a GL entry.

```text
600,000 INR ÷ 105.882353 = GBP 5,666.67        (was GBP 6,000.00)
Dr Payable — AlphaCo   333.33
   Cr FX gain (unbooked)  333.33
```

The rate row's identity is stored on the revaluation, so re-running March in June reproduces GBP 5,666.67
exactly (**T22**).

**Translation** is a different operation with its own record. One `translation_run` per member per period,
storing the presentation currency, the method, and every rate revision used (**T21**).

**AlphaCo INR → EUR**

| Account | INR | Rate | EUR |
|---|---|---|---|
| Cash | 200,000 Dr | closing 90 | 2,222.22 Dr |
| Receivable — BetaCo | 600,000 Dr | closing 90 | 6,666.67 Dr |
| Inventory | 300,000 Dr | closing 90 | 3,333.33 Dr |
| Cost of sales | 500,000 Dr | average 88 | 5,681.82 Dr |
| Share capital | 800,000 Cr | historical 80 | 10,000.00 Cr |
| Retained earnings, opening | 200,000 Cr | historical 80 | 2,500.00 Cr |
| Revenue — intra-group | 600,000 Cr | average 88 | 6,818.18 Cr |
| | | | Dr 17,904.04 / Cr 19,318.18 |
| **`translation_adjustment` (CTA)** | | consequence | **1,414.14 Dr** |

**BetaCo GBP → EUR**

| Account | GBP | Rate | EUR |
|---|---|---|---|
| Cash | 6,600.00 Dr | closing 0.85 | 7,764.71 Dr |
| Inventory | 3,600.00 Dr | closing 0.85 | 4,235.29 Dr |
| Cost of sales | 2,400.00 Dr | average 0.86 | 2,790.70 Dr |
| Payable — AlphaCo | 5,666.67 Cr | closing 0.85 | **6,666.67 Cr** |
| Share capital | 2,000.00 Cr | historical 0.80 | 2,500.00 Cr |
| Retained earnings, opening | 600.00 Cr | historical 0.80 | 750.00 Cr |
| Revenue — external | 4,000.00 Cr | average 0.86 | 4,651.16 Cr |
| FX gain | 333.33 Cr | average 0.86 | 387.60 Cr |
| | | | Dr 14,790.70 / Cr 14,955.43 |
| **`translation_adjustment` (CTA)** | | consequence | **164.73 Dr** |

Note the bolded line. BetaCo's payable translates to EUR **6,666.67**, exactly equal to AlphaCo's receivable.
That is not a coincidence and it is not a rounding accident: it happens because §7.4's revaluation restated
the payable at the *derived* closing GBP/INR rate, which is by construction the ratio of the two EUR closing
rates. **The intra-group balance eliminates to zero only because revaluation and translation are two distinct,
dated, stored operations.** Upstream, where the revaluation rate may come from a GL entry and translation
happens inside a report, the two sides differ by whatever the rate mismatch happens to be, and the difference
lands in the FCTR plug where it is indistinguishable from a real translation difference.

Both CTAs are **consequences** of prescribed rates, posted to each company's declared `cta_account_id` — not
residuals chosen to make the columns add up.

### 7.5 The consolidation run

```text
consolidation_run
  company_group_id, period=2026-03, presentation_currency=EUR,
  members: holdco(parent), alphaco(full, 100%), betaco(full, 60%)
  translation_run_id per member, rate_revision_id[] used,
  source_watermark=<domain_event position>, result_hash, authorising_grant_id
```

**Aggregate on group account identity** (**T27**) — never on `account_name`. Every local account has exactly
one `group_account_map` row for the period; an unmapped local account with a non-zero balance **blocks the
run**.

| Group account | HoldCo | AlphaCo | BetaCo | Aggregate |
|---|---|---|---|---|
| Cash | 2,800.00 | 2,222.22 | 7,764.71 | 12,786.93 Dr |
| Inventory | | 3,333.33 | 4,235.29 | 7,568.62 Dr |
| Intra-group receivable | | 6,666.67 | | 6,666.67 Dr |
| Investments in subsidiaries | 11,500.00 | | | 11,500.00 Dr |
| Cost of sales | | 5,681.82 | 2,790.70 | 8,472.52 Dr |
| Admin expense | 200.00 | | | 200.00 Dr |
| CTA | | 1,414.14 | 164.73 | 1,578.87 Dr |
| Intra-group payable | | | 6,666.67 | 6,666.67 Cr |
| Share capital | 14,000.00 | 10,000.00 | 2,500.00 | 26,500.00 Cr |
| Retained earnings, opening | 500.00 | 2,500.00 | 750.00 | 3,750.00 Cr |
| Revenue | | 6,818.18 | 4,651.16 | 11,469.34 Cr |
| FX gain | | | 387.60 | 387.60 Cr |
| | | | **Dr** | **48,773.61** |
| | | | **Cr** | **48,773.61** |

**Eliminations.** Each cites the fact it derives from, so completeness is a constraint rather than a review
(**T29**). Each leg carries its own segment attribution, because the two halves of an intra-group trade belong
to different segments.

| # | Derives from | Entry | Segment per leg |
|---|---|---|---|
| **E1** | `intercompany_transaction` | Dr Intra-group payable 6,666.67 / Cr Intra-group receivable 6,666.67 | UK / India-South |
| **E2** | `intercompany_transaction` | Dr Revenue 6,818.18 / Cr Cost of sales 5,681.82 *(seller's cost of all 100 units)* | India-South / India-South |
| **E3** | `intercompany_transaction` | Cr Cost of sales 517.97 *(restates BetaCo's 40 sold units from transfer price 2,790.70 to group cost 2,272.73)* | UK |
| **E4** | `unrealised_margin` | Cr Inventory 901.96 *(restates BetaCo's 60 held units from transfer price 4,235.29 to group cost 3,333.33)* | UK |
| **E5** | translation of E1–E4 | Dr CTA 283.57 | India-South |

E1 balances alone. E2–E5 balance as a set: Dr 6,818.18 + 283.57 = 7,101.75; Cr 5,681.82 + 517.97 + 901.96 =
7,101.75. E5 is the arithmetic consequence of measuring the seller's cost at the **average** rate, the buyer's
inventory restatement at the **closing** rate, and the margin in the selling company's currency. It is not a
plug: it is a residual whose three constituent rate choices are each recorded on the run, so it is
explainable and reproducible. Upstream's FCTR is the same number's home, arrived at by subtraction, with the
rate choices unrecorded.

**Investment elimination and minority interest** (**T28**). Both subsidiaries were acquired at par at
incorporation, so investment eliminates exactly against translated historical capital and there is no
goodwill: AlphaCo 10,000 against 10,000 (100%), BetaCo 1,500 against 60% × 2,500 = 1,500.

| # | Entry |
|---|---|
| **E6** | Dr Share capital 12,500.00 / Cr Investments 11,500.00 / Cr Minority interest 1,000.00 |
| **E7** | Dr MI share of profit 1,106.41; Dr Retained earnings opening 300.00 / Cr CTA 65.89; Cr Minority interest 1,340.52 |

E7's inputs, each from a declared policy on the run rather than a report's implicit behaviour:

```text
BetaCo translated profit         = 4,651.16 + 387.60 − 2,790.70 = 2,248.06
+ eliminations attributed to UK on a P&L leg (E3)               =   517.97
= BetaCo attributed profit                                     = 2,766.03
MI share of profit        40% × 2,766.03                        = 1,106.41
MI share of opening RE    40% ×   750.00                        =   300.00
MI share of BetaCo CTA    40% ×   164.73                        =    65.89   (reduces MI)
```

E2, E4 and E5 are attributed to **AlphaCo**, which is wholly owned, so they carry no minority interest. That
attribution is `consolidation_elimination.attributed_company_id`, stored per elimination — the thing upstream
has no place for, and the reason a 60%-owned subsidiary cannot be consolidated correctly by a report.

### 7.6 The consolidated result

| Group account | Aggregate | Eliminations | Final |
|---|---|---|---|
| Cash | 12,786.93 Dr | | **12,786.93 Dr** |
| Inventory | 7,568.62 Dr | −901.96 (E4) | **6,666.66 Dr** |
| Intra-group receivable | 6,666.67 Dr | −6,666.67 (E1) | **0** |
| Investments in subsidiaries | 11,500.00 Dr | −11,500.00 (E6) | **0** |
| Cost of sales | 8,472.52 Dr | −5,681.82 (E2) −517.97 (E3) | **2,272.73 Dr** |
| Admin expense | 200.00 Dr | | **200.00 Dr** |
| MI share of profit | | +1,106.41 (E7) | **1,106.41 Dr** |
| CTA | 1,578.87 Dr | +283.57 (E5) −65.89 (E7) | **1,796.55 Dr** |
| Intra-group payable | 6,666.67 Cr | −6,666.67 (E1) | **0** |
| Share capital | 26,500.00 Cr | −12,500.00 (E6) | **14,000.00 Cr** |
| Retained earnings, opening | 3,750.00 Cr | −300.00 (E7) | **3,450.00 Cr** |
| Revenue | 11,469.34 Cr | −6,818.18 (E2) | **4,651.16 Cr** |
| FX gain | 387.60 Cr | | **387.60 Cr** |
| Minority interest (equity) | | +1,000.00 (E6) +1,340.52 (E7) | **2,340.52 Cr** |
| | | **Dr** | **24,829.28** |
| | | **Cr** | **24,829.28** |

Read the four lines that matter:

- **Revenue 4,651.16** — BetaCo's external sale only. AlphaCo's INR 600,000 is gone.
- **Cost of sales 2,272.73** — exactly INR 200,000 (40 units at AlphaCo's cost of INR 5,000) at the average
  rate 88. The group expensed group cost, not transfer price.
- **Inventory 6,666.66** — AlphaCo's own INR 300,000 at closing, plus BetaCo's 60 units at **group cost** INR
  300,000 at closing. The INR 60,000 of unrealised margin is not in the balance sheet.
- **Share capital 14,000.00** — HoldCo's only.

Group profit before minority interest = 4,651.16 + 387.60 − 2,272.73 − 200.00 = **2,566.03**. Cross-checked
independently: BetaCo's external gross margin at group cost (4,651.16 − 2,272.73 = 2,378.43), plus BetaCo's FX
gain (387.60), less HoldCo's admin (200.00) = 2,566.03. Attributable to the parent: 2,566.03 − 1,106.41 =
**1,459.62**.

### 7.7 Three-way reconciliation, as deferred constraints

**T30** is three constraints on the transaction that writes the run, not three footnotes.

**Direction 1 — the consolidated trial balance balances.** Dr 24,829.28 = Cr 24,829.28.

**Direction 2 — each group account equals contributions − eliminations − minority interest.**

| Group account | Σ contributions | − eliminations | − MI | = final |
|---|---|---|---|---|
| Revenue | 11,469.34 | 6,818.18 | 0 | 4,651.16 ✓ |
| Cost of sales | 8,472.52 | 6,199.79 | 0 | 2,272.73 ✓ |
| Inventory | 7,568.62 | 901.96 | 0 | 6,666.66 ✓ |
| Share capital | 26,500.00 | 12,500.00 | 0 | 14,000.00 ✓ |
| Intra-group receivable | 6,666.67 | 6,666.67 | 0 | 0 ✓ |

**Direction 3 — segment amounts sum to the entity amount.** Segments partition the location dimension for the
period; every unmapped value is assigned to an explicit *Unallocated* segment, which is why the columns close
(**T26**).

| Segment | Revenue | Cost of sales | Inventory |
|---|---|---|---|
| Corporate (HoldCo, Amsterdam) | 0 | 0 | 0 |
| India-West (AlphaCo, Mumbai) | 0 | 0 | 0 |
| India-South (AlphaCo, Bengaluru) | 6,818.18 − 6,818.18 = **0** | 5,681.82 − 5,681.82 = **0** | **3,333.33** |
| UK (BetaCo, London) | **4,651.16** | 2,790.70 − 517.97 = **2,272.73** | 4,235.29 − 901.96 = **3,333.33** |
| Unallocated | 0 | 0 | 0 |
| **Sum** | **4,651.16** ✓ | **2,272.73** ✓ | **6,666.66** ✓ |

Every column equals the entity line in §7.6. This is what "reconciles by construction" means: the segment
figures are projections over `fact_dimension` and per-leg elimination attribution, not a second set of numbers
maintained by a report.

**One completeness constraint more.** Σ eliminations citing an `intercompany_transaction` must equal Σ
crossings in scope for the period (**T29**). Here: one crossing, five eliminations citing it or the margin it
produced, and a reconciliation that names it. An unelimated crossing fails the run; an elimination with no
crossing cannot be inserted, because the FK is `NOT NULL`.

### 7.8 The same attacker, against our design

Same BetaCo user, same objective — AlphaCo's transfer price.

| Attempt | Result | Recorded | Invariant |
|---|---|---|---|
| Read AlphaCo's leg by primary key | policy `USING` fails; the row does not exist for this connection | `isolation_denial` | T1, T7 |
| Same read through a raw SQL report, an export, a REST list, a link-title fetch, a count | identical outcome — the policy is below all of them | `isolation_denial` | T10 |
| Insert a row with `company_id = <alphaco>` | policy `WITH CHECK` rejects | `isolation_denial` | T7 |
| Send a header naming AlphaCo, or a different authentication source | context comes from the resolved `auth_session`; headers influence nothing | `auth_event` (scope denial) | T2, T3 |
| Ask for a session scoped to both companies | scope is fixed at issue and bounded by `principal_company_membership`; a wider scope is a **new** session, subject to the same bound | `auth_event` | T3 |
| Enqueue work hoping it runs unscoped | `principal_id` and `company_id` are `NOT NULL` on the work row; an unresolvable pair fails the job | job failure + `auth_event` | T11 |
| Look for a bypass flag | none exists; the application role holds neither `BYPASSRLS` nor table ownership | — | T1, T10 |
| Add a custom rule intended to widen access | extension points are monotone; a non-monotone result is rejected | `access_decision` | T8 |
| Use a dimension or segment narrowing to reach India-South | narrowing may only subtract, and composes strictly **after** company RLS | `access_decision` | T24 |
| Run the March consolidation to read AlphaCo indirectly | consolidation requires an explicit group-scoped grant; the run stores `authorising_grant_id` | `access_decision` + the run | T28 |
| Get a role granted quietly and permanently | grants carry actor, reason and expiry, append-only; current state is a projection over facts | `auth_event` | T9 |
| Deploy a new table for the crossing without a policy | the generated `rls_conformance` check fails the build | build failure | T12, T13 |

The asymmetry with §6 is the point. There, nine of ten attempts succeed and the tenth is enforced in one
class. Here, every attempt fails at the same layer, for the same reason, and leaves a row saying so.

**And note what the consolidation itself needs.** The run legitimately reads all three companies. Under
**T1** that is not something a report can simply do: the run executes under a group-scoped grant, the grant is
time-boxed and audited, and the run records which grant authorised it. The most privileged read in the system
is the one most explicitly authorised — the inversion of §5, where it was an ordinary report permission.

---

## 8. Complete write trace

| # | Table | Company scope | Notes |
|---|---|---|---|
| 1 | `auth_session` | alphaco | scope fixed at issue; binding evidence recorded (**T3**) |
| 2 | `access_decision` | alphaco | allow, sampled per policy (**T8**) |
| 3 | `intercompany_transaction` | group | one immutable fact; policy revision and relationship named (**T15–T17**) |
| 4 | seller leg + lines, `doc_tax`, `tax_determination` | alphaco | registration `29AACCA1234A2Z2` and resolving rule recorded (**T25**) |
| 5 | `stock_move` (issue), `gl_entry`, `voucher` | alphaco | INR functional; rate identity on every converted amount (**T19, T20**) |
| 6 | `unrealised_margin` | group | 100 units, INR 100,000 (**T18**) |
| 7 | durable work row | betaco | `principal_id`, `company_id` both `NOT NULL` (**T11**) |
| 8 | buyer leg + lines | betaco | GBP functional, INR transaction; deferred agreement with row 4 (**T17**) |
| 9 | `stock_move` (receipt), `gl_entry` | betaco | inventory at transfer price in GBP |
| 10 | `stock_move` (external issue ×40), `gl_entry` | betaco | external sale |
| 11 | `unrealised_margin_realisation` | group | 40 units realised (**T18**) |
| 12 | revaluation + `gl_entry` | betaco | INR payable → GBP 5,666.67 at a resolved rate row (**T21, T22**) |
| 13 | `translation_run` + `translated_balance` + `translation_adjustment` × 3 | per member | stored, reproducible (**T21**) |
| 14 | `consolidation_run`, `consolidation_member` | group | method and ownership per member; watermark; grant (**T28**) |
| 15 | `consolidation_member_contribution` | group | per member per group account |
| 16 | `consolidation_elimination` × 5 | group | each citing its crossing or margin, each leg segment-attributed (**T29**) |
| 17 | `minority_interest` | group | 40% of BetaCo, from declared policy |
| 18 | `consolidation_line` | group | the §7.6 output; three deferred reconciliations checked at commit (**T30**) |

### 8.1 Evidence versus projection

Evidence: the two legs, the crossing, the margin and its realisations, the revaluation, the rate rows, the
`auth_event` / `access_decision` / `isolation_denial` streams, and the run header with its watermark.

Projection: `translated_balance`, `consolidation_member_contribution`, `consolidation_line`,
`minority_interest`, and every segment column in §7.7.

The distinction has teeth here. Because the run stores a `source_watermark`, a consolidation is a statement
about a **known prefix** of the event stream. A crossing posted after the watermark is not silently included;
it appears in the next run, or in an explicit restatement run that supersedes this one. Upstream, where
nothing is stored, "the March consolidation" is whatever the report returns today.

---

## 9. Side by side

| Question | ERPNext | Ours |
|---|---|---|
| Which company is this session acting in | nowhere — no scope on the session | `auth_session.company_id`, fixed at issue |
| What confines a read to that company | `DatabaseQuery`, when it is used | a database policy, always |
| What happens when no scoping rule is found | **unrestricted** | denied |
| What happens when the company field is blank | check skipped unless a setting is on | impossible — `NOT NULL` |
| Can code switch it off | 892 places | nothing; the role cannot lift the policy |
| Who runs a background job | `Administrator` by default | the enqueuing principal, or the job fails |
| Cross-currency inter-company sale | **refused** | ordinary; legs agree on the transaction amount |
| Which internal party is the counterparty | address match, else `parties[0]` | unique per ordered pair and period |
| Where the transfer price comes from | a price list with two role flags | an approved, effective-dated policy revision |
| Do the two legs have to agree | opt-in, off by default, rate only | deferred constraints on qty, price, currency, date |
| Can the pair be unlinked after posting | yes | no — reversed as a whole |
| Intra-group margin | parked per company, realised by hand | tracked per transaction and item, realised by an event |
| Ledger currency | `default_currency` | `company_functional_currency`, frozen once posted |
| Presentation currency | a report fallback from the root company | a parameter of a stored `translation_run` |
| Rate on a posted fact | the value | the rate **row's identity** |
| Missing / stale / zero rate | `None`, `0.00`, or log-and-continue | refusal |
| Revaluation rate source | may be the last GL entry | `exchange_rate`, by purpose and date |
| Translation | inside a report run, discarded | `translation_run` + `translated_balance`, stored |
| CTA | a balancing residual, filed next to Liability if Equity is absent | a consequence of prescribed rates, in a declared account |
| Does the intra-group balance eliminate to zero | only by luck | yes, because revaluation and translation are separate dated facts |
| Consolidation aggregates on | `account_name` | group account **identity** |
| Unmapped local account | appears as its own line | blocks the run |
| Eliminations | none | derived from an identified crossing, per-leg segment-attributed |
| Ownership weighting | none — 60% consolidates at 100% | `ownership_pct` per member per run |
| Minority interest | none | a line, from a declared attribution policy |
| Is a consolidation reproducible | no — nothing is stored | immutable run with watermark, rates and result hash |
| Segment reporting | does not exist | partitioning mappings that reconcile by construction |
| Which statutory registration a crossing used | inferred from an `Address` | resolved and recorded, with the rule |
| Who may read across companies | an ordinary report permission | an explicit, time-boxed, audited group-scoped grant |
| Is isolation tested | no | the doc 52 §7 matrix, per table, gating the build |

---

## 10. Findings and invariants exercised

1. **The scenario cannot be run upstream at all.** Cross-currency inter-company documents are refused
   (`accounts/doctype/sales_invoice/mapper.py:149-175`), so a group with subsidiaries in India, the UK and the
   Netherlands cannot record the transaction that §1.2 describes. Everything after that point in §3–§5 is an
   analysis of what *would* happen.
2. **There is no tenant context to enforce anything against.** One `current_setting` in two repositories, in a
   test; no scope on the session record; and the scoping mechanism returns *unrestricted* when it finds no
   rules.
3. **The intra-group balance eliminating to zero is a consequence of two separate dated operations.** EUR
   6,666.67 on both sides happens because revaluation used the derived closing GBP/INR rate and translation
   used the two EUR closing rates. Collapse revaluation and translation into one report-time conversion — as
   upstream does — and the difference lands in a plug that also absorbs missing rates.
4. **A rate *choice* moves EUR 283.57 between profit and the translation reserve.** Measuring the seller's
   cost at the average rate, the buyer's inventory restatement at closing, and the margin in the seller's
   currency produces a residual. Ours is E5, with all three choices recorded on the run. Upstream's is the
   FCTR, arrived at by subtraction.
5. **The two halves of an intra-group trade belong to different segments.** E2's revenue leg is India-South
   and its cost leg is India-South, but E3's and E4's legs are UK. A single-segment elimination row cannot
   express this, and segment reporting then does not reconcile — which is one reason it does not exist
   upstream.
6. **Minority interest is unanswerable without per-elimination attribution.** BetaCo's 40% share depends on
   which eliminations are attributed to BetaCo. Without `attributed_company_id` on the elimination, the number
   is a guess; with it, E7 is arithmetic.
7. **The most privileged read in the system is upstream's least protected one.** Consolidation reads every
   company in the group. Upstream it is an ordinary report permission on a doctype; ours requires an explicit,
   expiring, audited group-scoped grant whose identity is stored on the run.
8. **The crossing cannot be written by one session.** Under a real boundary, AlphaCo's user is refused by
   `WITH CHECK` when writing BetaCo's leg, so the crossing *must* be two scoped writes joined by one immutable
   fact. Upstream writes both legs in one request as the same user, which is precisely why the pairing can be
   two mutable scalars.
9. **`unrealised_margin` is the only place a Tranche G table is the source for another one.** E4 cites it,
   and T29's completeness constraint reads it. Parking the margin in an account, as upstream does, removes the
   input that makes eliminations complete by construction.
10. **892 bypasses and 34 identity switches are not a code-quality observation.** They are the reason the
    boundary has to move to L2. A guarantee enforced at L3 with an off-switch that 892 call sites use is not a
    guarantee.

This scenario exercises the whole Tranche G register: **T1–T5** (database boundary, fail-closed
authentication, scoped sessions, managed credentials, append-only auth facts), **T6–T9** (deny-by-default
authorisation, scope proved by the row, monotone extension with explainable decisions, expiring reviewable
grants), **T10–T13** (one enforcement layer, no unauthenticated execution context, isolation as a tested
property, conformance by construction), **T14–T18** (modelled group, identified counterparty, transfer price
as policy with exact leg agreement, one fact with two legs, margin tracked to realisation), **T19–T22** (three
currency layers, rate as a dated sourced non-zero fact, revaluation and translation distinct, reproducible for
any past instant), **T23–T26** (one dimension definition, write constraints and additive-only read narrowing,
registration as a dimension of place, segments reconciling by construction) and **T27–T30** (mapped group
chart, stored reproducible run, eliminations from identified facts, three-way reconciliation).

It also reuses **F1** (balanced vouchers) from S04, **G10** and **G14** from S12 — place of supply resolved
rather than inferred, and statutory period control per registration — and **U7** (no stored value is ever a
translation) from doc 30, which is what forces `group_account_map` to key on identity rather than
`account_name`.

---

Cross-references: **[S12](S12-gst-invoice-e-invoice-and-gstr1.md)** (the same seller's domestic GST cycle, and
the Maharashtra registration this crossing deliberately does not use),
**[S06](S06-multi-currency.md)** (single-company multi-currency, which this extends to three layers),
**[S05](S05-period-close-and-opening-balances.md)** (period control),
**[S04](S04-stock-transfer-and-in-transit.md)** (the stock movements each leg makes);
**[doc 50](../logic/50-authentication-session-and-tenant-context.md)** (identity, sessions, tenant context),
**[doc 51](../logic/51-permission-model-end-to-end.md)** (authorisation),
**[doc 52](../logic/52-tenant-isolation-and-rls-under-attack.md)** (the attack classes §6 and §7.8 walk),
**[doc 53](../logic/53-multi-company-intercompany-and-transfer-pricing.md)** (group structure and crossings),
**[doc 54](../logic/54-multi-currency-layering.md)** (the three currency layers and rate resolution),
**[doc 55](../logic/55-multi-location-branch-and-segment.md)** (locations, registrations and segments),
**[doc 56](../logic/56-consolidation-and-group-reporting.md)** (consolidation),
**[doc 57](../logic/57-tranche-g-closure-and-our-security-spec.md)** (closure and the T register),
**[doc 15](../logic/15-intercompany-and-history-rewriting.md)** (crossing mechanics), and
`docs/design/FINAL-SCHEMA.md` §29 onward (target security and group tables).
