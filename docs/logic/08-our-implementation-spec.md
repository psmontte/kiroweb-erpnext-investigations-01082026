# 8. Our implementation spec

What we build, derived from docs 01-07. This is the document that turns study into code.

---

## 8.1 Decisions taken

| # | Decision | Consequence |
|---|---|---|
| 1 | **Money is a decimal: `numeric(19,4)`.** Quantities `numeric(21,9)`, unit rates `numeric(21,9)`, percentages `numeric(9,6)`. | One `round_money()` helper; no minor-unit conversions at every boundary. See the caveat below. |
| 2 | **Multi-tenancy: all of it.** `company_id` on every business row (never nullable), *and* Postgres RLS policies keyed on a session GUC, *and* every unique constraint/FK scoped by company. Single schema, single database. | No cross-company leak is possible even from a buggy query; RLS is the backstop, `company_id` is the model. |
| 3 | **Eight concrete trade document tables**, not one polymorphic table: `sales_quote`, `sales_order`, `delivery`, `sales_invoice`, `purchase_request`, `purchase_order`, `goods_receipt`, `purchase_invoice` (+ one `_line` table each). | Real FKs, real NOT NULLs, readable SQL. Shared behaviour lives in code (a `TradeDoc` protocol + shared services), not in one table with nullable columns. |
| 4 | **Clean room.** ERPNext is read as a reference for *behaviour*, not copied. No schema compatibility target, no migration path from an ERPNext database. | We are free to fix the modelling; we lose "import an existing ERPNext site" as a feature. |

**Caveat on #1 that I need you to confirm:** I have read this as *decimal money* (`numeric(19,4)`).
If you meant the PostgreSQL **`money` type**, we should not use it: it is locale-dependent (output and
input depend on `lc_monetary`), fixed at 2 decimal places regardless of currency, has no currency
attached, and behaves badly under `SET lc_monetary`. Same practical goal, `numeric(19,4)` gets there
safely. Say the word if you intended something else.

Decisions still open (not blocking Phase 0-1):
- 4 decimals enough for unit prices in your industries, or do we need 6 on `unit_price`?
- Do we need a second reporting currency (ERPNext's `*_in_reporting_currency`) from day one?

---

## 8.2 The invariant register

These are the assertions the whole system rests on. Each becomes (a) a DB constraint where possible,
(b) an assertion in the posting service, (c) a property-based test.

### Ledger

| # | Invariant | Enforced by |
|---|---|---|
| L1 | A voucher posts **zero or ≥2** GL rows; `Σ debit == Σ credit` in base currency, **exactly** | deferred constraint trigger over `gl_entry` per `voucher_id` |
| L2 | No negative amounts in `gl_entry`; direction is the debit/credit side only | `CHECK (debit >= 0 AND credit >= 0 AND NOT (debit > 0 AND credit > 0))` |
| L3 | `gl_entry` is append-only: no `UPDATE`, no `DELETE`, ever | `CREATE RULE` / trigger raising an exception; revoke UPDATE/DELETE from the app role |
| L4 | Cancellation posts a reversing voucher dated on the cancellation date, linked by `reverses_voucher_id` | posting service; `UNIQUE (reverses_voucher_id)` |
| L5 | Every P&L row has a cost center; dimension rules per account are satisfied | `CHECK` + posting service (needs the account's `report_type`, so a trigger or a denormalised `report_type` column on the row) |
| L6 | A party transacts in exactly one currency per company | unique index on `(company_id, party_id, currency_id)` in a `party_ledger_currency` table, written on first posting |
| L7 | `account_period_balance` == `Σ gl_entry` for the same slice | maintained in the posting transaction; nightly assertion job |

### Inventory

| # | Invariant | Enforced by |
|---|---|---|
| S1 | `stock_move` rows for one (item, warehouse) are totally ordered by `(posting_at, seq)` | `seq bigint` from a sequence; unique index |
| S2 | `stock_move` is append-only (same as L3) | rule/trigger |
| S3 | `state.qty_after == prev.qty_after + move.qty_delta` for every consecutive pair | recompute function is the only writer; assertion job |
| S4 | `state.value_delta == state.value_after − prev.value_after`, and `Σ value_delta == state.value_after` | same |
| S5 | `qty_after == 0 ⇒ value_after == 0` (residue lands in `value_delta`) | recompute function |
| S6 | `unit_cost = value_after / qty_after` when `qty_after != 0`; else the previous cost carries | recompute function |
| S7 | For FIFO/LIFO: `Σ queue.qty == qty_after` and `Σ queue.qty*rate == value_after` | recompute function; assertion job (ERPNext lets these drift — we do not) |
| S8 | **`Σ gl_entry.signed_amount` on inventory accounts == `Σ stock_valuation_state.value_delta`** for the same company + warehouse-account mapping + date range | continuous reconciliation job with a hard alert |
| S9 | Negative stock only where explicitly allowed per item/warehouse | posting service; the check is on the *projected* future, not just now (ERPNext's `validate_negative_qty_in_future_sle`) |

### Documents

| # | Invariant | Enforced by |
|---|---|---|
| D1 | `per_x = Σ min(achieved_line, ordered_line) / Σ ordered_line * 100`, rounded to 6 dp, 0 when the denominator is 0 | one `fulfilment` function; derived on read |
| D2 | Fulfilment roll-ups are absolute recomputations, never deltas | same |
| D3 | A return references a **submitted** document, posts at-or-after it, uses the same exchange rate, has negative quantities, and never exceeds `reference − already_returned` per column | validation service |
| D4 | `Σ settlement.amount` against an invoice ≤ the invoice total; `outstanding = total − Σ settlement.amount` | `CHECK` via trigger + a covering index; outstanding is derived, not cached (until measurement says otherwise) |
| D5 | Amendment only from a cancelled document, at most once | `amends_id UNIQUE`, `CHECK` on the source state |
| D6 | `Σ line.net_amount == doc.net_total`; `Σ payment_schedule.amount == payable_total` (exact, not ±0.1) | calculation service; assertion in tests |
| D7 | `Σ tax_line_allocation.amount == tax_line.amount` per tax row | calculation service (ERPNext's error-diffusion trick, kept) |

### Period control

| # | Invariant | Enforced by |
|---|---|---|
| P1 | Fiscal years do not overlap within a company | `EXCLUDE USING gist (company_id WITH =, daterange(start,end) WITH &&)` |
| P2 | Period closes tile the fiscal year contiguously, no gaps, no overlaps | `EXCLUDE` constraint + a "starts where the previous ended" check |
| P3 | Closes are created in date order; cancelled LIFO | posting service |
| P4 | Nothing posts into a closed period; every override is attributed | `assert_postable()` + `posting_override_log` |
| P5 | Opening rows must fall inside the opening period (an `is_opening` flag is not a licence to ignore the date) | `CHECK` against the company's opening period |

---

## 8.3 Phase 0-2 tables

Phase 0 and 1 are ~22 tables and cover the general ledger. Phase 2 adds ~10 and covers inventory
valuation. That is the hard part of an ERP; everything after it is CRUD plus these services.

### Phase 0 — foundation (11)

```
company              (id, code, name, base_currency_id, reporting_currency_id,
                      accounts_frozen_till, opening_period_id, ...)
currency             (id, code, name, minor_unit_digits, smallest_fraction)
exchange_rate        (id, from_currency_id, to_currency_id, valid_on, rate, source,
                      for_buying, for_selling)          UNIQUE (from,to,valid_on,for_buying,for_selling)
fiscal_year          (id, company_id, code, start_date, end_date, is_short_year, state)
accounting_period    (id, company_id, fiscal_year_id, start_date, end_date, state)
uom                  (id, code, name, category)
uom_conversion       (id, from_uom_id, to_uom_id, factor)        -- factor as numeric(21,9)
party               (id, company_id, kind, code, name, primary_currency_id, ...)   -- supertype
customer            (party_id PK/FK, credit_limit, price_list_id, payment_terms_id, ...)
supplier            (party_id PK/FK, payment_terms_id, ...)
doc_sequence         (id, company_id, doc_type, prefix, period_key, next_value)    -- explicit numbering
app_user             (id, ...)   -- plus created_by/updated_by FKs everywhere
```

Numbering: `doc_no` is allocated from `doc_sequence` with `UPDATE ... RETURNING` inside the posting
transaction, and `UNIQUE (company_id, doc_type, doc_no)`. Gaps are visible and explainable, unlike
ERPNext's `tabSeries` counter.

### Phase 1 — general ledger (11)

```
account                  (id, company_id, code, name, parent_id, is_group,
                          root_type, report_type, account_type, currency_id,
                          balance_must_be, is_frozen, ...)      -- parent_id + recursive CTE, no lft/rgt
cost_center              (id, company_id, code, name, parent_id, is_group)
dimension                (id, company_id, code, name, target_table, is_required_for_pl, is_required_for_bs)
dimension_value          (id, dimension_id, code, name, parent_id)
account_dimension_rule   (id, account_id, dimension_id, mode /*require|allow|restrict*/)

voucher                  (id, company_id, doc_type, doc_no, posting_date, posting_at,
                          voucher_kind, source_doc_type, source_doc_id,
                          currency_id, exchange_rate, is_opening, state,
                          reverses_voucher_id, remarks, created_at, created_by)
gl_entry                 (id, voucher_id, company_id, account_id,
                          debit, credit, amount, currency_id, exchange_rate,   -- amount+currency is the truth
                          party_id, cost_center_id, project_id, finance_book_id,
                          source_line_type, source_line_id,                    -- line-level provenance
                          settles_voucher_id,                                  -- typed, replaces against_voucher
                          is_opening, report_type, posting_date)                -- report_type denormalised for CHECKs
gl_entry_dimension       (gl_entry_id, dimension_id, value_id)                  PRIMARY KEY (gl_entry_id, dimension_id)
account_period_balance   (company_id, account_id, accounting_period_id, dimension_key,
                          debit, credit, closing_kind)                          PRIMARY KEY (...)
period_close             (id, company_id, fiscal_year_id, period_start, period_end,
                          retained_earnings_account_id, voucher_id, closed_at, closed_by, reversed_by)
posting_override_log     (id, company_id, posting_date, doc_type, reason, actor_id, created_at)
```

Notes:
- `debit`/`credit` are the presentation of `amount` (signed) — we store both, with a `CHECK` tying them
  together, because reports want debit/credit and logic wants a signed number.
- `settles_voucher_id` is a **real FK**, replacing `against_voucher_type` + `against_voucher`.
- No `is_cancelled`. No `to_rename`. No four currency pairs.

### Phase 2 — inventory (10)

```
item                  (id, company_id, code, name, item_group_id, stock_uom_id,
                       is_stock_item, valuation_method, allow_negative_stock, ...)
item_group            (id, company_id, code, name, parent_id, is_group)
warehouse             (id, company_id, code, name, parent_id, is_group, inventory_account_id)
batch                 (id, company_id, item_id, code, expiry_date, use_batch_valuation)
serial                (id, company_id, item_id, code, state)

stock_move            (id, company_id, item_id, warehouse_id, posting_at, seq,
                       qty_delta, unit_rate, move_kind, is_opening,
                       source_doc_type, source_doc_id, source_line_id,
                       created_at, created_by)                       -- IMMUTABLE
stock_move_dependency (move_id, depends_on_move_id)                  -- replaces dependant_sle_voucher_detail_no
stock_move_serial     (move_id, serial_id, unit_rate)
stock_move_batch      (move_id, batch_id, qty, unit_rate)

stock_valuation_state (item_id, warehouse_id, seq,
                       qty_after, value_after, value_delta, unit_cost,
                       queue jsonb, computed_at, computed_from_seq)   -- DERIVED, recomputable
stock_balance         (item_id, warehouse_id, qty_on_hand, value, unit_cost,
                       qty_ordered, qty_reserved, qty_requested, qty_planned)   -- CACHE
```

`stock_valuation_state` is keyed by `(item_id, warehouse_id, seq)` so it is a 1:1 projection of
`stock_move` and can be rebuilt into a shadow table and diffed before swapping.

---

## 8.4 The posting algorithm

One function, one transaction, one order. This replaces ERPNext's per-doctype `on_submit` chains.

```
post(document, actor):
  BEGIN
  01  assert document.state == DRAFT
  02  assert_postable(company_id, posting_date, doc_type, is_opening, actor)     # doc 07 §7.5
  03  totals = calculate(document)                                              # doc 05, pure function
      assert D6, D7
  04  for (item_id, warehouse_id) in sorted(document.stock_pairs()):
          advisory_xact_lock('stock', item_id, warehouse_id)                    # doc 02 §2.12
  05  moves = build_stock_moves(document)                                       # signed deltas only
      insert moves (seq from sequence, posting_at generated)
  06  for each affected (item, warehouse):
          state = recompute_valuation(item, warehouse, from_seq = min(new seq))
          assert S3..S7
          assert_negative_stock_allowed(item, warehouse, state)                 # projected, not just now
  07  gl_rows = build_gl(document, totals, state.value_deltas)                  # doc 01 §1.5, doc 03 §3.3
      assert L1, L2, L5
  08  voucher = insert voucher ; insert gl_rows
  09  upsert account_period_balance deltas                                      # L7
  10  upsert ar_ap_entry rows from the receivable/payable gl_rows                # doc 04 §4.2
  11  apply settlements (advances / allocations) as settlement rows              # D4
  12  refresh stock_balance for the affected pairs
  13  recompute fulfilment for predecessor lines                                # D1, D2, absolute
  14  document.state = POSTED
  15  enqueue recompute_forward jobs for any (item, warehouse) with later moves  # backdating
  16  insert document_event rows for the audit trail
  COMMIT
```

Cancellation is the same shape in reverse (doc 06 §6.4), and every step is idempotent so a retry after a
crash converges.

**What is deliberately synchronous** that ERPNext defers: the valuation recompute for the *current*
instant, the GL, the subledger, the balance rollup, and the fulfilment update. Only the **forward**
recompute of later movements (step 15) is a job — and until it finishes, the affected
(item, warehouse) is flagged `recompute_pending`, which blocks period close (ERPNext's
`PendingRepostingError`, kept).

---

## 8.5 Behaviours we keep, restated as requirements

1. **Draft / Posted / Cancelled with immutable posted rows.** Only posted documents produce ledger rows;
   posted rows are never mutated.
2. **Every ledger row traces to a document line** (`source_line_id`). Non-negotiable for audit and for
   partial cancellation.
3. **Inventory GL amounts come from the valuation projection, never from document amounts.** Any
   difference between what the document says goods are worth and what the ledger says goes to a named
   variance account (`purchase_price_variance`, `manufacturing_variance`, `stock_adjustment`).
4. **Accrual accounts are explicit**: goods-received-not-billed and goods-delivered-not-billed, with a
   documented clearing leg on the invoice.
5. **Returns are valued at the original cost**, not the current cost.
6. **Fulfilment percentages are capped per line** (`Σ min(achieved, ordered)`), so over-delivery on one
   line never hides a shortfall on another.
7. **The AR/AP subledger is separate from the GL**, with payables sign-flipped so one aggregation serves
   both sides.
8. **Period close zeroes P&L per dimension tuple** and books retained earnings per tuple.
9. **Opening balances via a single contra account** that must net to zero.
10. **Reconciliation between stock and GL is a continuous constraint**, not a report.

## 8.6 Behaviours we deliberately drop

| ERPNext behaviour | Why we drop it | Replacement |
|---|---|---|
| Derived valuation state stored inside the event row | forces history rewrites on backdating | `stock_move` + `stock_valuation_state` |
| Absolute snapshot rows in the ledger (Stock Reconciliation) | special-cases every forward query | count → signed delta move + optional revaluation move |
| Landed cost by deleting and re-inserting SLEs | destroys the audit trail | allocation rows + a revaluation move |
| `is_cancelled` / `delinked` mutable flags | every query needs the filter; history mutates | reversing rows only; append-only tables |
| Four independently written currency pairs | four chances to disagree (already one bug) | `amount` + `currency_id` + `exchange_rate`, derive the rest |
| Balance tolerance of 0.5 | hides real errors | exact balance; explicit rounding line |
| Six independent rounding-drift corrections | unexplainable one-cent differences | one residual point per computation |
| Runtime DDL for accounting dimensions | migrations at business-config time | fixed FKs + `gl_entry_dimension` |
| `tabSingles` key/value settings | untyped, unconstrained | typed settings tables per company |
| Nested sets (`lft`/`rgt`) on trees | every insert rewrites the tree | `parent_id` + recursive CTE |
| Status derived from itself | cannot recompute from facts | pure `derive_status()` + separate user-set flags |
| `adv_adj` silently bypassing the freeze date | a repost can write into a frozen period | one guard, explicit attributed overrides |
| Three over-billing gates with three tolerances | inconsistent enforcement | one `allowance()` + one enforcement point |
| `delete_linked_ledger_entries` | deletes accounting history | does not exist |
| Reconciliation by cancel/split/resubmit of the payment | the reason for optimistic-lock checks and the delete-and-rebuild subledger | `settlement` rows |

## 8.7 Test plan

The invariant register **is** the test plan.

- **Property-based (hypothesis)** — generate random but valid movement/voucher sequences and assert the
  invariants after every step:
  - S3-S7 for each valuation method, including: zero crossings, negative balances, returns consuming the
    original bin, partial consumption, queue underflow, backdated inserts, and interleaved
    cross-warehouse transfers.
  - L1-L2 for randomly generated vouchers, including multi-currency and inclusive-tax documents.
  - D1 with random partial deliveries, over-deliveries within tolerance, and partial returns.
- **Golden cases** — a fixed set of worked examples with hand-computed expected numbers, per valuation
  method and per document chain (O2C and P2P end to end, plus subcontracting).
- **Reconciliation tests** — after every scenario, assert S8 (stock vs GL) and L7 (balance rollup vs
  ledger).
- **Recompute equivalence** — for any random history, `recompute_from(seq=0)` must produce byte-identical
  state to the incremental result. This is the single most valuable test in the suite; it is what makes
  backdating safe.
- **Concurrency** — two sessions posting to the same (item, warehouse) and to the same invoice; assert no
  lost updates and no deadlocks (the sorted lock order).
- **Period control** — matrix of (closed period, freeze date, closed fiscal year, pending recompute) ×
  (post, cancel, amend, reverse).

## 8.8 What I need from you to start Phase 0

1. Confirm decision #1 (`numeric(19,4)` vs the Postgres `money` type — my reading vs the literal word).
2. Migration tool preference for the schema: plain SQL files + a runner, Alembic, Atlas, or
   golang-migrate? This determines the repo layout.
3. Language for the posting services (the schema is language-agnostic; the algorithm in §8.4 is not).
   Python + SQLAlchemy Core, Go + sqlc, or TypeScript + Kysely are all fine choices — pick by what your
   team will maintain.
4. Whether Phase 0 should ship a minimal HTTP API or stay as a library + SQL for now (you said
   backend/DB only, so I have assumed library + SQL).
