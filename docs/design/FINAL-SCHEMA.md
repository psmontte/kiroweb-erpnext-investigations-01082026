# Final schema: tables, data flow, business rules

The authoritative table design for our ERP. Every table here is justified by an investigation in
`docs/logic/`; every rule cites the ERPNext behaviour it copies, rejects or replaces.

Conventions
- `id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY` on every table.
- `company_id bigint NOT NULL REFERENCES company(id)` on every business table, and **every** unique
  constraint / natural key is scoped by it. RLS policy on every table keyed on the session GUC
  `app.company_id`.
- Money `numeric(19,4)`. Quantity `numeric(21,9)`. Unit rate `numeric(21,9)`. Percent `numeric(9,6)`.
- Audit quartet on every table: `created_at timestamptz NOT NULL DEFAULT now()`, `created_by bigint`,
  `updated_at`, `updated_by`. Ledger tables have no `updated_*` (they are append-only).
- `doc_no varchar(64) NOT NULL` on every document, `UNIQUE (company_id, doc_type, doc_no)`.
- Enumerations are Postgres `ENUM` types unless the set is user-extensible, in which case a lookup table.

---

## 1. Layer map and data flow

```
                    ┌──────────── MASTERS (mutable, versioned where dated) ────────────┐
                    │ company fiscal_year accounting_period currency exchange_rate     │
                    │ party customer supplier account cost_center dimension            │
                    │ item item_variant uom uom_conversion warehouse batch serial      │
                    │ price_list item_price pricing_rule tax_template payment_terms     │
                    └──────────────────────────────┬──────────────────────────────────┘
                                                   │ read at document time, snapshotted per line
                    ┌──────────────────────────────▼──────────────────────────────────┐
                    │ DOCUMENTS  (state: draft → posted → cancelled ; append-only once posted) │
                    │  sales_quote → sales_order → delivery → sales_invoice            │
                    │  purchase_request → purchase_order → goods_receipt → purchase_invoice │
                    │  stock_transfer  stock_count  payment  journal                   │
                    │  + *_line child tables, + doc_tax, + doc_tax_line_alloc          │
                    └───────┬───────────────────────┬───────────────────────┬──────────┘
       fulfilment links      │        stock events   │       accounting      │  settlement
                            ▼                       ▼                       ▼
        ┌───────────────────────────┐  ┌───────────────────────┐  ┌────────────────────────┐
        │ doc_link                  │  │ stock_move (IMMUTABLE)│  │ voucher + gl_entry     │
        │ (predecessor → successor, │  │ stock_move_dependency │  │ (IMMUTABLE, balanced)  │
        │  qty/amount carried)      │  │ stock_move_serial     │  │ gl_entry_dimension     │
        └───────────┬───────────────┘  │ stock_move_batch      │  └───────────┬────────────┘
                    │                  └──────────┬────────────┘              │
                    │ recompute                   │ recompute                 │ derive
                    ▼                             ▼                           ▼
        ┌───────────────────────────┐  ┌───────────────────────┐  ┌────────────────────────┐
        │ PROJECTIONS (derived)     │  │ stock_valuation_state │  │ ar_ap_entry            │
        │ fulfilment_line (view)    │  │ stock_balance (cache) │  │ account_period_balance │
        │ doc_status (view)         │  │ batch_valuation_state │  │ settlement             │
        └───────────────────────────┘  └───────────────────────┘  └────────────────────────┘
```

**The three-layer rule.** Masters are mutable. Documents are mutable while draft, immutable once posted.
Ledgers (`gl_entry`, `stock_move`, `ar_ap_entry`) are append-only forever. Everything else is a
**projection** that can be dropped and recomputed from the ledgers. No number is ever incremented in
place; every derived value is a full recompute of a pure function. That single rule is what makes
cancellation, amendment, backdating, partial fulfilment and out-of-order documents correct by
construction — it is ERPNext's best idea (see `docs/logic/06` §6.2, `docs/logic/02` §2.8) and we keep it.

---

## 2. Foundation (Phase 0)

```sql
company(id, code, name, base_currency_id, reporting_currency_id,
        opening_period_id, accounts_frozen_till date, frozen_override_role_id,
        enable_perpetual_inventory bool, valuation_method valuation_method_enum,
        default_inventory_account_id, stock_received_not_billed_account_id,
        stock_delivered_not_billed_account_id, stock_adjustment_account_id,
        cogs_account_id, round_off_account_id, round_off_cost_center_id,
        round_off_for_opening_account_id, exchange_gain_loss_account_id,
        unrealized_exchange_gain_loss_account_id, temporary_opening_account_id,
        retained_earnings_account_id, unrealized_profit_loss_account_id)
        -- every *_account_id is NOT NULL DEFERRABLE: a company is not usable until mapped

currency(id, code UNIQUE, name, minor_unit_digits smallint, smallest_fraction numeric(19,4))

exchange_rate(id, from_currency_id, to_currency_id, valid_on date, rate numeric(21,9),
              purpose rate_purpose_enum /*general|buying|selling*/, source text)
   UNIQUE (from_currency_id, to_currency_id, valid_on, purpose)
   -- lookup = latest valid_on <= date, purpose match then general. Staleness is a policy
   -- setting (max_age_days) that RAISES, never silently returns 0 (ERPNext returns 0.0 and
   -- lets the caller throw — docs/logic/05 §5.11).

fiscal_year(id, company_id, code, start_date, end_date, is_short_year bool, state fy_state_enum)
   EXCLUDE USING gist (company_id WITH =, daterange(start_date, end_date, '[]') WITH &&)
accounting_period(id, company_id, fiscal_year_id, code, start_date, end_date, state period_state_enum)
   EXCLUDE USING gist (company_id WITH =, daterange(start_date, end_date, '[]') WITH &&)
period_document_block(accounting_period_id, doc_type)   -- ERPNext's Closed Document child

uom(id, code, name, category, must_be_whole_number bool)
uom_conversion(id, from_uom_id, to_uom_id, factor numeric(21,9))  UNIQUE (from_uom_id, to_uom_id)

party(id, company_id, kind party_kind_enum, code, name, primary_currency_id,
      tax_id, is_internal bool, represents_company_id)
   UNIQUE (company_id, kind, code)
customer(party_id PK REFERENCES party, credit_limit numeric(19,4), credit_override_role_id,
         price_list_id, payment_terms_id, customer_group_id, territory_id,
         bypass_credit_limit_at_order bool)
supplier(party_id PK REFERENCES party, payment_terms_id, supplier_group_id, hold_type, hold_until)
party_ledger_currency(company_id, party_id, currency_id)  PRIMARY KEY (company_id, party_id)
   -- enforces ERPNext's rule: a party transacts in exactly one currency per company (docs/logic/01 §1.6)

doc_sequence(id, company_id, doc_type, prefix, period_key, next_value bigint)
   UNIQUE (company_id, doc_type, prefix, period_key)
app_user(id, ...) ; role(id, code) ; user_role(user_id, role_id)
```

**Business rules**
1. A posting date resolves to exactly one `fiscal_year` per company (the `EXCLUDE` constraint
   guarantees it). ERPNext allows overlapping years and silently takes the newest —
   `docs/logic/07` §7.6. We reject that at write time.
2. `exchange_rate` is never invented. A missing rate is an error naming the pair and the date.
3. `uom_conversion.factor` is global; per-item overrides live on `item_uom` (§4) and are **not**
   silently overwritten by the global table (ERPNext does overwrite — `docs/logic/17` §3).

---

## 3. Accounting (Phase 1)

```sql
account(id, company_id, code, name, parent_id, is_group bool,
        root_type root_type_enum,        -- asset|liability|income|expense|equity
        report_type report_type_enum,    -- balance_sheet|profit_and_loss  (derived from root_type, stored)
        account_type account_type_enum,  -- receivable|payable|bank|cash|stock|fixed_asset|temporary|...
        currency_id, balance_must_be side_enum NULL, is_frozen bool, is_disabled bool)
   UNIQUE (company_id, code) ; INDEX (company_id, parent_id)
cost_center(id, company_id, code, name, parent_id, is_group bool)
cost_center_allocation(id, company_id, main_cost_center_id, valid_from date, state)
cost_center_allocation_line(allocation_id, cost_center_id, percentage numeric(9,6))
   -- CHECK: Σ percentage = 100 per allocation ; no self reference ; no cycles

dimension(id, company_id, code, label, target_table, required_for_pl bool, required_for_bs bool)
dimension_value(id, dimension_id, code, name, parent_id)
account_dimension_rule(id, account_id, dimension_id, mode dim_mode_enum /*require|allow|restrict*/)
account_dimension_rule_value(rule_id, dimension_value_id)

voucher(id, company_id, doc_type, doc_no, posting_date date, posting_at timestamptz,
        voucher_kind voucher_kind_enum, currency_id, exchange_rate numeric(21,9),
        is_opening bool, source_doc_type text, source_doc_id bigint,
        reverses_voucher_id bigint UNIQUE REFERENCES voucher(id),
        period_close_id bigint, remarks text, posted_at, posted_by)
   UNIQUE (company_id, doc_type, doc_no) ; INDEX (company_id, posting_date)

gl_entry(id, voucher_id, company_id, account_id, posting_date date,
         amount numeric(19,4) NOT NULL,          -- SIGNED, base currency. the truth.
         debit numeric(19,4) NOT NULL DEFAULT 0, -- presentation, CHECK-tied to amount
         credit numeric(19,4) NOT NULL DEFAULT 0,
         currency_id, exchange_rate numeric(21,9),
         amount_in_account_currency numeric(19,4), account_currency_id,
         party_id, cost_center_id, project_id, finance_book_id,
         source_line_type text, source_line_id bigint,   -- line-level provenance, mandatory for trade docs
         settles_voucher_id bigint REFERENCES voucher(id),  -- typed; replaces against_voucher_*
         report_type report_type_enum NOT NULL,          -- denormalised for CHECKs and reports
         is_opening bool NOT NULL DEFAULT false)
   CHECK (debit >= 0 AND credit >= 0 AND NOT (debit > 0 AND credit > 0))
   CHECK (amount = debit - credit)
   CHECK (report_type <> 'profit_and_loss' OR cost_center_id IS NOT NULL)
   INDEX (company_id, posting_date, account_id) INCLUDE (amount)
   INDEX (voucher_id) ; INDEX (settles_voucher_id) ; INDEX (party_id, account_id)
gl_entry_dimension(gl_entry_id, dimension_id, dimension_value_id) PK (gl_entry_id, dimension_id)

account_period_balance(company_id, account_id, accounting_period_id, dimension_key text,
                       debit numeric(19,4), credit numeric(19,4), closing_kind closing_kind_enum)
   PRIMARY KEY (company_id, account_id, accounting_period_id, dimension_key, closing_kind)

period_close(id, company_id, fiscal_year_id, period_start, period_end,
             retained_earnings_account_id, voucher_id, closed_at, closed_by, reversed_by_id)
   EXCLUDE USING gist (company_id WITH =, daterange(period_start, period_end, '[]') WITH &&)
posting_override_log(id, company_id, posting_date, doc_type, doc_id, reason, actor_id, created_at)

budget(id, company_id, fiscal_year_id, applies_to budget_target_enum /*cost_center|project|dimension*/,
       target_id, monthly_distribution_id,
       action_on_annual_exceed budget_action_enum, action_on_cumulative_exceed budget_action_enum,
       applicable_on_actual bool, applicable_on_committed bool, applicable_on_ordered bool)
budget_line(budget_id, account_id, amount numeric(19,4))
monthly_distribution(id, company_id, code) ; monthly_distribution_line(id, month smallint, percentage)

deferral_schedule(id, company_id, source_line_type, source_line_id, kind deferral_kind_enum,
                  deferral_account_id, target_account_id, total_amount numeric(19,4),
                  service_start date, service_end date, service_stop date NULL, state)
deferral_booking(id, deferral_schedule_id, period_start, period_end, amount numeric(19,4),
                 voucher_id, booked_at)
   UNIQUE (deferral_schedule_id, period_start)   -- idempotency: one booking per schedule per period
```

**Business rules**
1. **Balance, exactly.** Per `voucher_id`: `SUM(amount) = 0`, enforced by a deferred constraint
   trigger. No 0.5 tolerance (ERPNext's, `docs/logic/01` §1.3). Rounding residue is computed by the
   calculation layer and posted as an explicit line on `round_off_account_id`.
2. **Append-only.** `UPDATE`/`DELETE` on `gl_entry`, `stock_move`, `ar_ap_entry` raise. There is no
   `is_cancelled` column, so no query needs the filter.
3. **Reversal = new voucher** dated on the cancellation date, `reverses_voucher_id` set, `UNIQUE` so a
   voucher can be reversed once. ERPNext supports both in-place flagging and reversal; we implement
   only the immutable variant (`docs/logic/01` §1.7).
4. **Cost centre allocation** scales *every* amount column consistently. ERPNext misses
   `debit_in_transaction_currency` (`docs/logic/12` §C) — impossible here, because we store one signed
   `amount` and derive the rest.
5. `account_period_balance` is maintained in the posting transaction and asserted against `gl_entry`
   nightly. Reports never scan the ledger for period aggregates.
6. Budget checks and deferral bookings are separate services reading the same ledger; neither may
   write `gl_entry` outside the standard posting funnel.

---

## 4. Items and inventory (Phase 2)

```sql
item(id, company_id, code, name, item_group_id, brand_id, stock_uom_id,
     is_stock_item bool, is_fixed_asset bool, has_batch bool, has_serial bool,
     has_expiry bool, shelf_life_days int, valuation_method valuation_method_enum NULL,
     allow_negative_stock bool, allow_zero_valuation bool, is_customer_provided bool,
     template_id bigint REFERENCES item(id),      -- one level only
     end_of_life date, is_disabled bool)
   UNIQUE (company_id, code)
item_attribute(id, company_id, code, is_numeric bool, from_value, to_value, increment)
item_attribute_value(id, item_attribute_id, value, abbr)  UNIQUE (item_attribute_id, value)
item_variant_attribute(item_id, item_attribute_id, item_attribute_value_id NULL, numeric_value NULL)
   -- variant identity:
   UNIQUE (template_id, attribute_fingerprint)   -- generated column: sha256 of sorted (attr,value) pairs
item_uom(item_id, uom_id, factor numeric(21,9))  PK (item_id, uom_id)
   -- CHECK: the row where uom_id = item.stock_uom_id has factor = 1
item_default(item_id, company_id, warehouse_id, income_account_id, expense_account_id,
             cost_center_id, supplier_id, price_list_id)  PK (item_id, company_id)
item_reorder(id, item_id, warehouse_id, warehouse_group_id, level numeric(21,9),
             qty numeric(21,9), request_type mr_type_enum)
   UNIQUE (item_id, warehouse_id, request_type)
item_standard_cost(id, company_id, item_id, effective_date date, rate numeric(21,9), voucher_id)
   UNIQUE (company_id, item_id, effective_date)   -- strictly increasing enforced in service

warehouse(id, company_id, code, name, parent_id, is_group bool,
          inventory_account_id, is_rejected bool, capacity_uom_id, is_disabled bool)
putaway_rule(id, company_id, item_id, warehouse_id, priority int,
             capacity numeric(21,9), uom_id, is_disabled bool)
batch(id, company_id, item_id, code, manufacturing_date, expiry_date,
      use_batch_valuation bool, is_disabled bool)  UNIQUE (company_id, item_id, code)
serial(id, company_id, item_id, code, warehouse_id, batch_id,
       state serial_state_enum, warranty_expiry, amc_expiry)  UNIQUE (company_id, item_id, code)

stock_move(id, company_id, item_id, warehouse_id,
           posting_at timestamptz NOT NULL,           -- GENERATED from (posting_date, posting_time)
           seq bigint NOT NULL,                       -- from a sequence; total order tie-break
           qty_delta numeric(21,9) NOT NULL,          -- SIGNED. no absolute rows, ever.
           unit_rate numeric(21,9),
           move_kind move_kind_enum, is_opening bool,
           source_doc_type text NOT NULL, source_doc_id bigint NOT NULL, source_line_id bigint,
           created_at, created_by)
   UNIQUE (item_id, warehouse_id, seq) ; INDEX (item_id, warehouse_id, posting_at, seq)
   INDEX (source_doc_type, source_doc_id)
stock_move_dependency(move_id, depends_on_move_id)  PK (move_id, depends_on_move_id)
stock_move_serial(move_id, serial_id, unit_rate)    PK (move_id, serial_id)
stock_move_batch(move_id, batch_id, qty numeric(21,9), unit_rate)  PK (move_id, batch_id)

stock_valuation_state(item_id, warehouse_id, seq,
                      qty_after numeric(21,9), value_after numeric(19,4),
                      value_delta numeric(19,4), unit_cost numeric(21,9),
                      queue jsonb, computed_at, computed_from_seq)
   PRIMARY KEY (item_id, warehouse_id, seq)
batch_valuation_state(item_id, warehouse_id, batch_id, seq, qty_after, value_after, unit_cost)
stock_balance(item_id, warehouse_id, qty_on_hand, value, unit_cost,
              qty_ordered, qty_requested, qty_planned, qty_reserved, qty_reserved_production)
   PRIMARY KEY (item_id, warehouse_id)
stock_recompute_job(id, item_id, warehouse_id, from_seq, state, leased_by, leased_until,
                    checkpoint_seq, error, created_at)
   UNIQUE (item_id, warehouse_id) WHERE state IN ('queued','running')

stock_reservation(id, company_id, item_id, warehouse_id,
                  source_doc_type, source_doc_id, source_line_id,
                  qty numeric(21,9), qty_delivered numeric(21,9),
                  batch_id NULL, serial_id NULL, state reservation_state_enum, reserved_at)
   INDEX (item_id, warehouse_id) WHERE state = 'active'
pick(id, company_id, purpose pick_purpose_enum, state) ; pick_line(pick_id, ...)
```

**Business rules**
1. **`stock_move` is the event; `stock_valuation_state` is the projection.** A stock count produces a
   signed delta (`counted − qty_at(posting_at)`), never an absolute snapshot row; a revaluation
   produces `qty_delta = 0` with a value change. This removes ERPNext's entire
   "stop propagating at the next reconciliation" special case (`docs/logic/02` §2.11).
2. Total order per (item, warehouse) is `(posting_at, seq)`. `seq` comes from a sequence, so ties are
   deterministic and survive imports. ERPNext orders on `creation` (`docs/logic/02` §2.1).
3. `Σ stock_valuation_state.value_delta` for a company's warehouses **must equal**
   `Σ gl_entry.amount` on the corresponding inventory accounts. Continuous constraint, not a report
   (`docs/logic/03` §3.8).
4. `stock_balance` is a cache. Demand columns are defined as queries over open order lines with a
   nightly diff-and-alert. No business rule reads it, and no accounting number comes from it.
5. Reservation is its own table, never a mutable counter on `stock_balance`. Availability is
   `qty_on_hand − Σ active reservation.qty (net of delivered)`, and the negative-stock check runs
   against the **projected forward** series, not just the current balance (`docs/logic/16`).
6. FEFO/FIFO/LIFO picking order is a **policy parameter** of one allocation function, not three
   near-duplicate SQL queries (`docs/logic/17` §4).
7. Item immutability: `has_batch`, `has_serial`, `is_stock_item`, `valuation_method` and `stock_uom_id`
   are frozen once a `stock_move` exists for the item. `valuation_method` FIFO→moving-average is the
   one permitted transition (ERPNext allows exactly this — `docs/logic/17` §1.10).

---

## 5. Trade documents (Phase 3) — eight concrete tables

Decision #3: eight concrete pairs, not one polymorphic table.

```
sales_quote / sales_quote_line          purchase_request / purchase_request_line
sales_order / sales_order_line          purchase_order  / purchase_order_line
delivery    / delivery_line             goods_receipt   / goods_receipt_line
sales_invoice / sales_invoice_line      purchase_invoice/ purchase_invoice_line
```

Every header carries the same **column contract** (enforced by a shared migration macro and a
`trade_doc` view over all eight):

```sql
<doc>(id, company_id, doc_no, doc_date date, posting_at timestamptz,
      party_id, party_address_id, party_contact_id,
      currency_id, exchange_rate numeric(21,9), price_list_id, price_list_exchange_rate,
      net_total, tax_total, grand_total, rounded_total, rounding_adjustment,
      discount_basis discount_basis_enum, discount_amount, discount_percent,
      payment_terms_id, due_date,
      state doc_state_enum,              -- draft | posted | cancelled
      hold_state hold_state_enum,        -- open | on_hold | closed     (user-set, separate from derived status)
      is_return bool, returns_id bigint REFERENCES <doc>(id),
      amends_id bigint UNIQUE REFERENCES <doc>(id),
      is_internal_transfer bool, counterparty_doc_type, counterparty_doc_id,
      posted_voucher_id bigint REFERENCES voucher(id),
      approval_state approval_state_enum, approved_by, approved_at,
      created_at, created_by, updated_at, updated_by, version integer NOT NULL DEFAULT 0)
```

```sql
<doc>_line(id, <doc>_id, line_no int, item_id, description,
      qty numeric(21,9), uom_id, conversion_factor numeric(21,9),
      stock_qty numeric(21,9) GENERATED ALWAYS AS (qty * conversion_factor) STORED,
      warehouse_id, batch_id, serial_ids bigint[],
      price_list_rate, margin_kind, margin_value, discount_percent, discount_amount,
      unit_rate numeric(21,9), net_unit_rate, line_amount, net_amount,
      distributed_discount numeric(19,4),
      tax_template_id, item_tax_rates jsonb,        -- snapshot, per account
      income_account_id / expense_account_id, cost_center_id, project_id,
      -- fulfilment: predecessor pointers, never counters
      from_line_type text, from_line_id bigint,
      UNIQUE (<doc>_id, line_no))

doc_tax(id, <doc>_type, <doc>_id, line_no, charge_type charge_type_enum, account_id,
        rate numeric(9,6), amount numeric(19,4), amount_after_discount numeric(19,4),
        base_amount numeric(19,4), category tax_category_enum, add_or_deduct side_enum,
        is_inclusive bool, row_ref int, is_withholding bool, do_not_recompute bool,
        running_total numeric(19,4))
doc_tax_line_alloc(doc_tax_id, line_id, taxable_amount, amount)   -- the item-wise breakup
   -- INVARIANT: Σ doc_tax_line_alloc.amount = doc_tax.base_amount_after_discount (exact, by
   -- error-diffusion — ERPNext's trick, docs/logic/05 §5.5)

payment_schedule(id, <doc>_type, <doc>_id, line_no, payment_term_id, due_date,
                 invoice_portion numeric(9,6), amount numeric(19,4), discount_date, discount_amount)
   -- INVARIANT: Σ amount = payable_total, EXACTLY (ERPNext tolerates ±0.1 — docs/logic/05 §5.9)

doc_link(id, company_id, from_doc_type, from_doc_id, from_line_id,
         to_doc_type, to_doc_id, to_line_id,
         qty numeric(21,9), amount numeric(19,4), link_kind link_kind_enum)
   -- the fulfilment graph, one row per (predecessor line, successor line)
   INDEX (from_line_type, from_line_id) ; INDEX (to_doc_type, to_doc_id)
```

**Business rules**
1. A line's price, tax rates, address and payment terms are **snapshots** taken at posting; later
   master edits never change a posted document. Snapshot fields are explicitly enumerated (ERPNext
   snapshots 239 fields via `fetch_from` with no policy — `docs/reveng/04` §3).
2. `stock_qty` is generated, so `qty * conversion_factor` can never drift.
3. Returns carry **negative quantities**, must reference a posted document, post at-or-after it, use
   the same exchange rate, and may not exceed `reference − already_returned` per quantity column. No
   tolerance (`docs/logic/06` §6.6).
4. `amends_id UNIQUE` makes double amendment structurally impossible (ERPNext has no such constraint).
5. `hold_state` is user-set and separate from the derived status, so status remains a pure function.

---

## 6. Fulfilment — flexible by construction

There are **no** `delivered_qty` / `billed_amt` / `per_delivered` columns. Fulfilment is a view over
`doc_link`:

```sql
CREATE VIEW fulfilment_line AS
SELECT l.id AS line_id, 'sales_order_line' AS line_type, l.stock_qty AS ordered_qty, l.net_amount AS ordered_amount,
       COALESCE(SUM(k.qty)    FILTER (WHERE k.link_kind = 'deliver'), 0) AS delivered_qty,
       COALESCE(SUM(k.qty)    FILTER (WHERE k.link_kind = 'return'),  0) AS returned_qty,
       COALESCE(SUM(k.amount) FILTER (WHERE k.link_kind = 'bill'),    0) AS billed_amount
FROM sales_order_line l
LEFT JOIN doc_link k ON k.from_line_type = 'sales_order_line' AND k.from_line_id = l.id
GROUP BY l.id;

CREATE VIEW fulfilment_doc AS
SELECT doc_id,
       round(SUM(LEAST(abs(delivered_qty), abs(ordered_qty))) / NULLIF(SUM(abs(ordered_qty)),0) * 100, 6) AS per_delivered,
       round(SUM(LEAST(abs(billed_amount), abs(ordered_amount))) / NULLIF(SUM(abs(ordered_amount)),0) * 100, 6) AS per_billed
FROM fulfilment_line GROUP BY doc_id;
```

This is ERPNext's capped formula `Σ min(achieved, ordered) / Σ ordered` (`docs/logic/06` §6.2) —
kept verbatim, because the per-row `LEAST` is what stops over-delivery on one line hiding a shortfall
on another. What changes is that it is a **view**, so it is always correct, never needs a roll-up job,
and cancellation/amendment/out-of-order documents need no bookkeeping at all.

Materialise only if measurement demands it, and then as a `MATERIALIZED VIEW` refreshed in the posting
transaction — never as hand-maintained counters.

**Flexibility this buys** (all of it required by the brief):
- one order → many deliveries and many invoices, in any order, any granularity;
- one delivery serving lines from several orders (`doc_link` is many-to-many at line level);
- invoice-before-delivery, delivery-without-order, direct invoice — all just absent links;
- partial and over fulfilment, with tolerance enforced at submit by one function
  `allowance(item_id, kind) -> pct` (item override → company setting), and any override written to
  `posting_override_log`;
- **no** silent exemption for internal parties (ERPNext returns without error — `docs/logic/06` §6.3).

Derived status is a pure function, in one place:

```sql
CREATE VIEW sales_order_status AS
SELECT o.id, CASE
  WHEN o.state = 'cancelled'            THEN 'cancelled'
  WHEN o.hold_state = 'closed'          THEN 'closed'
  WHEN o.hold_state = 'on_hold'         THEN 'on_hold'
  WHEN o.state = 'draft'                THEN 'draft'
  WHEN f.per_delivered >= 100 AND f.per_billed >= 100 THEN 'completed'
  WHEN f.per_delivered >= 100           THEN 'to_bill'
  WHEN f.per_billed    >= 100           THEN 'to_deliver'
  ELSE 'to_deliver_and_bill' END AS status
FROM sales_order o JOIN fulfilment_doc f ON f.doc_id = o.id;
```
Note `>= 100` consistently — ERPNext mixes `== 100` and `>= 100` across doctypes, which can strand a
delivery note in *Partially Billed* forever (`docs/logic/06` §6.1).

---

## 7. Settlement, advances and payment allocation

```sql
payment(id, company_id, doc_no, posting_date, direction pay_direction_enum /*in|out|internal*/,
        party_id, party_account_id, bank_account_id,
        currency_id, exchange_rate, paid_amount, received_amount,
        state doc_state_enum, posted_voucher_id, version integer)
payment_deduction(payment_id, line_no, account_id, cost_center_id, amount, is_exchange_gain_loss bool)
payment_tax(payment_id, line_no, account_id, rate, amount, is_inclusive_in_paid bool)

settlement(id, company_id, party_id,
           source_type settle_source_enum,   -- payment | credit_note | debit_note | journal | advance
           source_id bigint, source_line_id bigint,
           target_type settle_target_enum,   -- sales_invoice | purchase_invoice | sales_order | purchase_order
           target_id bigint, target_schedule_id bigint NULL,   -- allocation at payment-term granularity
           amount numeric(19,4) NOT NULL,               -- in target currency
           amount_base numeric(19,4) NOT NULL,
           exchange_rate numeric(21,9), fx_gain_loss numeric(19,4),
           voucher_id bigint REFERENCES voucher(id),    -- the GL rows that realised it
           reverses_id bigint UNIQUE REFERENCES settlement(id),
           settled_on date, created_at, created_by)
   INDEX (target_type, target_id) ; INDEX (source_type, source_id)
   -- CHECK via trigger: Σ amount per (target) <= target.payable_total
   -- CHECK via trigger: Σ amount per (target_schedule_id) <= payment_schedule.amount

ar_ap_entry(id, company_id, voucher_id, gl_entry_id, side ar_ap_side_enum /*receivable|payable*/,
            account_id, party_id, posting_date, due_date,
            amount numeric(19,4) NOT NULL,        -- SIGNED: + increases the obligation
            amount_in_account_currency numeric(19,4), account_currency_id,
            settles_voucher_id bigint, source_line_type, source_line_id)
   INDEX (company_id, party_id, account_id, posting_date) INCLUDE (amount)
   INDEX (settles_voucher_id)

advance(id, company_id, party_id, payment_id, order_type, order_id,
        amount numeric(19,4), amount_applied numeric(19,4), state advance_state_enum,
        separate_account_id bigint NULL)      -- the "book advances in a separate account" option
```

**Outstanding is derived, not stored:**
```sql
CREATE VIEW invoice_outstanding AS
SELECT 'sales_invoice' AS doc_type, i.id AS doc_id, i.payable_total,
       i.payable_total - COALESCE(SUM(s.amount), 0) AS outstanding
FROM sales_invoice i
LEFT JOIN settlement s ON s.target_type = 'sales_invoice' AND s.target_id = i.id AND s.reverses_id IS NULL
WHERE i.state = 'posted' GROUP BY i.id;
```

**Business rules**
1. **Allocation is an insert, never a document rewrite.** ERPNext cancels, splits and resubmits the
   payment to record an allocation, which is the root cause of its optimistic-lock checks, its
   delete-and-rebuild subledger, and the case where the GL keeps a stale `against_voucher`
   (`docs/logic/11` §3). A `settlement` row replaces all of it.
2. **Un-allocation is a compensating row** (`reverses_id`), never a delete or a re-point.
3. Allocation granularity is the **payment schedule line** (`target_schedule_id`), which is what makes
   instalment-level and payment-request-level allocation natural — ERPNext bolts this on via
   `split_refdocs_based_on_payment_terms` (`docs/logic/11` §2.2).
4. Allocation is bounded simultaneously by: the payment's unallocated pool, the target's outstanding,
   and (when linked) the payment request's outstanding — the triple minimum ERPNext computes in
   `allocate_amount_to_references`. We keep the rule, enforced by constraint rather than by arithmetic
   in application code.
5. Advances: an unallocated payment is simply a `payment` with no `settlement` rows. `advance` exists
   only to model the *separate advance account* option and the order→advance link. `advance_paid` on an
   order is a view over `settlement` where `target_type` is an order.
6. FX gain/loss on settlement is stored on the `settlement` row **and** posted as a base-currency-only
   voucher. We never emit a leg that claims to be an account-currency movement of zero, which is why
   ERPNext must exempt those journals from its own balance check (`docs/logic/04` §4.7).
7. `outstanding` is a view. If profiling forces materialisation, it is maintained in the same statement
   that inserts the `settlement` row, under `SELECT … FOR UPDATE` on the invoice. ERPNext recomputes
   with an unlocked read-then-write (`docs/logic/04` §4.10).

---

## 8. Document lifecycle — one state machine, one posting funnel

```
                 ┌──────────────── approval_state (optional, policy-driven) ─────────────┐
                 │  not_required → pending → approved / rejected                          │
                 └────────────────────────────────┬───────────────────────────────────────┘
    ┌────────┐  save    ┌────────┐  submit (post) ▼   ┌────────┐  cancel   ┌───────────┐
    │ (new)  │ ───────▶ │ draft  │ ──────────────────▶│ posted │ ────────▶ │ cancelled │
    └────────┘          └────────┘                    └────────┘           └─────┬─────┘
                            │  ▲                          │                      │ amend
                            │  └──── edit (version++) ─────┘ (ledger rows exist)  ▼
                            │                                                ┌────────┐
                            └── discard ──────────────────────────────────▶  │ draft' │ (amends_id)
                                                                             └────────┘
```

- **save** — validate + calculate. No ledger effect. Optimistic concurrency on `version`
  (`UPDATE … WHERE id = :id AND version = :v`), not a `modified` timestamp string.
- **approval** — a real column (`approval_state`), driven by a policy table
  (`approval_policy(company_id, doc_type, min_amount, role_id)`). ERPNext has **no approval state**:
  it is either `Authorization Control` inside `on_submit` or a Frappe Workflow overlay
  (`docs/logic/09` §1). We make it explicit and auditable.
- **post (submit)** — the single funnel in `docs/logic/08` §8.4, in one transaction: guard period →
  calculate → lock stock streams → insert `stock_move` → recompute valuation → build and insert
  `voucher` + `gl_entry` → upsert balances → derive `ar_ap_entry` → insert `settlement` rows →
  refresh `stock_balance` → insert `doc_link` rows → set state → enqueue forward recompute.
- **cancel** — a declared, ordered, idempotent pipeline; every step logged to `document_event`.
  Successor existence is checked by explicit query **before** any write (ERPNext checks after
  `on_cancel` has already run, via a per-doctype opt-out list — `docs/logic/09` §3).
- **amend** — new draft with `amends_id`; fulfilment counters do not need resetting because there are
  none.
- **delete** — only `draft` and only when no links exist. There is no configuration that deletes
  ledger rows (ERPNext has `delete_linked_ledger_entries` — `docs/logic/09` §4).

```sql
document_event(id, company_id, doc_type, doc_id, event event_enum, actor_id, at timestamptz,
               detail jsonb)      -- append-only audit of every lifecycle transition
```

---

## 9. Invariant register (the test suite)

Beyond L1-L7 / S1-S9 / D1-D7 / P1-P5 in `docs/logic/08` §8.2, Tranche A adds:

| # | Invariant |
|---|---|
| F1 | `per_x = Σ LEAST(achieved, ordered) / Σ ordered × 100`, capped per line, 0 when denominator 0 |
| F2 | `Σ doc_link.qty` per predecessor line ≤ `ordered_qty × (1 + allowance)`; overrides logged |
| F3 | Status is a pure function of state + hold_state + fulfilment; no status feeds itself |
| T1 | `Σ settlement.amount` per target ≤ target payable total; per schedule line ≤ line amount |
| T2 | `outstanding = payable_total − Σ settlement.amount` (no cached divergence) |
| T3 | Every `settlement` has a `voucher_id`, and that voucher balances |
| T4 | Un-allocation is a compensating row; no settlement row is ever updated or deleted |
| A1 | `advance_paid(order) = Σ settlement.amount WHERE target = order` |
| B1 | Budget check reads committed + actual from the ledger only; never from a cached counter |
| B2 | `Σ deferral_booking.amount ≤ deferral_schedule.total_amount`; one booking per period |
| R1 | Reservation: `Σ active reservation.qty ≤ qty_on_hand` per (item, warehouse) at all times |
| R2 | A reservation is released exactly once (delivered, cancelled or expired) |
| V1 | Variant identity: `UNIQUE (template_id, attribute_fingerprint)` |
| U1 | `item_uom` contains the stock UOM with factor 1; `stock_uom_id` frozen once moves exist |

---

## 10. What remains open

- Manufacturing (Tranche B) will add `bom`, `bom_line`, `work_order`, `job_card`, `operation`,
  `routing`, `workstation` and a WIP account mapping. It does **not** change anything above; work
  orders consume and produce `stock_move` rows like every other document.
- Assets (Tranche C) will add a second scheduled posting engine (depreciation) which reuses `voucher`
  + `gl_entry` unchanged.
- Platform mechanics (Tranche E) decide permissions, numbering edge cases, the regional/tax overlay,
  the job runner and the reporting layer. None of them alter these tables.
