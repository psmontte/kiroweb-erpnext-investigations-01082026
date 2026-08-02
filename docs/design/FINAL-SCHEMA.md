# Final schema: tables, data flow, business rules

The authoritative table design for our ERP. Every table here is justified by an investigation in
`docs/logic/`; every rule cites the ERPNext behaviour it copies, rejects or replaces.

Conventions
- `id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY` on every table except the protected,
  opaque-token `principal_auth_session.id uuid`.
- `company_id bigint NOT NULL REFERENCES company(id)` on every business table, including child,
  allocation, evidence, projection, outbox and job tables; **every** unique constraint / natural key is
  scoped by it. Every business table has `ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, and
  matching `USING` / `WITH CHECK` company policies keyed on authenticated session context. Only the
  migration role has `BYPASSRLS`.
- Money `numeric(19,4)`. Quantity `numeric(21,9)`. Unit rate and conversion factor `numeric(21,9)`.
  Percent `numeric(9,6)`.
- Audit quartet on every table: `created_at timestamptz NOT NULL DEFAULT now()`, `created_by bigint`,
  `updated_at`, `updated_by`. Ledger tables have no `updated_*` (they are append-only).
- `doc_no varchar(64) NOT NULL` on every document, `UNIQUE (company_id, doc_type, doc_no)`.
- Enumerations are Postgres `ENUM` types with stable lower-case codes unless the set is user-extensible,
  in which case a company-scoped lookup table. Stored codes are never translated display text.
- References written in shorthand as `*_id` are composite, company-scoped foreign keys
  `(company_id, *_id)` to the target business table. Every `reverses_*` / `supersedes_*` column is a
  same-table company-scoped FK, rejects self-reference, and permits at most one direct successor;
  current state is derived from the unsuperseded/unreversed chain rather than mutable flags.

Every migration that creates a business table also emits this non-optional policy shape (substitute the
real table name). The policy never trusts a caller-set custom GUC. `principal_auth_session` is written
only by the authentication-gateway role after credential verification; `principal_company_membership`
is administered outside the application role. The application role receives only `EXECUTE` on the
narrow `begin_tenant_transaction` `SECURITY DEFINER` function. That function accepts an opaque,
short-lived authentication-session token, proves its principal/company membership, records
`(pg_backend_pid(), txid_current(), principal_id, company_id)` in a protected context table, and is
`SET LOCAL`/transaction scoped. Its fixed `search_path`, owner, grants and row locking are migration-
tested. `authenticated_company_id()` reads only that protected row and raises if absent or ambiguous:

```sql
REVOKE ALL ON principal_auth_session, principal_company_membership,
              authenticated_tenant_context FROM PUBLIC, app_role;
REVOKE ALL ON FUNCTION begin_tenant_transaction(uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION begin_tenant_transaction(uuid,bigint) TO app_role;

ALTER TABLE <business_table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <business_table> FORCE ROW LEVEL SECURITY;
CREATE POLICY company_scope ON <business_table>
  USING (company_id = authenticated_company_id())
  WITH CHECK (company_id = authenticated_company_id());
REVOKE UPDATE, DELETE ON <append_only_table> FROM app_role;
```

Required application-role tests prove that `SET LOCAL app.company_id`, forged principal/session GUCs,
direct context-table writes, a token for another principal, expired/replayed tokens, and a company not
present in the authenticated principal's membership cannot change the visible/writable company. Tests
also prove context disappears on commit/rollback and pooled-connection reuse starts with no tenant.
Only the migration role has `BYPASSRLS`; table owners still encounter `FORCE RLS`.

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
        │  qty/amount carried)      │  │ stock_value_event      │  │ gl_entry_dimension     │
        └───────────┬───────────────┘  │ stock_move_serial/batch│  └───────────┬────────────┘
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
Ledgers (`gl_entry`, `stock_move`, `stock_value_event`, `ar_ap_entry`) and the append-only authority/
evidence tables named below are permanent facts. Only tables explicitly labelled **projection**, cache or
checkpoint can be dropped and recomputed. No posted fact or accounting number is incremented in place;
derived read models are full recomputations of pure functions. Backdating appends value/GL adjustments
rather than changing prior facts. That rule makes cancellation, amendment, partial fulfilment and out-of-
order documents additive and auditable while keeping valuation rebuildable (`docs/logic/06` §6.2,
`docs/logic/02` §2.8).

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
period_document_block(company_id, accounting_period_id, doc_type)
   UNIQUE (company_id, accounting_period_id, doc_type)   -- ERPNext's Closed Document child

uom(id, code, name, category, must_be_whole_number bool)
uom_conversion(id, from_uom_id, to_uom_id, factor numeric(21,9))  UNIQUE (from_uom_id, to_uom_id)

party(id, company_id, kind party_kind_enum, code, name, primary_currency_id,
      tax_id, is_internal bool, represents_company_id)
   UNIQUE (company_id, kind, code)
customer(company_id, party_id PK REFERENCES party, credit_limit numeric(19,4), credit_override_role_id,
         price_list_id, payment_terms_id, customer_group_id, territory_id,
         bypass_credit_limit_at_order bool)
supplier(company_id, party_id PK REFERENCES party, payment_terms_id, supplier_group_id, hold_type, hold_until)
party_ledger_currency(company_id, party_id, currency_id)  PRIMARY KEY (company_id, party_id)
   -- enforces ERPNext's rule: a party transacts in exactly one currency per company (docs/logic/01 §1.6)

doc_sequence(id, company_id, doc_type, prefix, period_key, next_value bigint)
   UNIQUE (company_id, doc_type, prefix, period_key)
app_user(id, ...) ; role(id, code) ; user_role(user_id, role_id)

-- Security-control tables: owned by tenant_security_owner; no app_role DML/SELECT grants.
auth_principal(id, subject_hash char(64), state auth_principal_state_enum, created_at)
   UNIQUE (subject_hash)
principal_company_membership(id, principal_id, company_id,
    valid_from timestamptz, valid_to timestamptz, granted_by, granted_at)
   UNIQUE (principal_id, company_id, valid_from)
   EXCLUDE USING gist (principal_id WITH =, company_id WITH =,
      tstzrange(valid_from,valid_to,'[)') WITH &&)
   CHECK (valid_to > valid_from)
principal_company_membership_revocation(id, membership_id, revoked_at, revoked_by, reason)
   UNIQUE (membership_id)
principal_auth_session(id uuid PRIMARY KEY, token_hash char(64) NOT NULL,
    principal_id, gateway_nonce uuid NOT NULL, state auth_session_state_enum,
    issued_at timestamptz, expires_at timestamptz,
    consumed_at timestamptz NULL, consumed_backend_pid integer NULL)
   UNIQUE (token_hash)
   UNIQUE (gateway_nonce)
   CHECK (expires_at > issued_at)
authenticated_tenant_context(backend_pid integer, transaction_id bigint,
    auth_session_id uuid, principal_id, membership_id, company_id, established_at timestamptz)
   PRIMARY KEY (backend_pid, transaction_id)
   UNIQUE (auth_session_id)
```

The authentication-gateway role alone inserts `auth_principal`/`principal_auth_session`; a separate
membership-admin role alone inserts memberships/revocations. `begin_tenant_transaction` hashes the
opaque token, locks the session, requires `state=active`, `consumed_at IS NULL`, `now()<expires_at`, an
unrevoked membership whose half-open range contains `now()`, and the requested company. It then performs
one compare-and-set session consumption and inserts exactly one context row for
`(pg_backend_pid(),txid_current())`. `authenticated_company_id()` joins that row back to the same
session, principal and membership and rechecks revocation/range. A second context, company switch or
token use in a committed transaction is rejected. Rollback removes context and consumption together,
allowing the same failed request to retry; commit makes replay impossible. Stale committed context rows
are harmless because transaction IDs never match and are deleted by a privileged cleanup job. Both
functions are `SECURITY DEFINER` with fixed `pg_catalog,<security_schema>` search path, non-login owner,
fully qualified objects and only the documented application-role `EXECUTE` grant.

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
cost_center_allocation_line(company_id, allocation_id, cost_center_id, percentage numeric(9,6))
   -- CHECK: Σ percentage = 100 per allocation ; no self reference ; no cycles

dimension(id, company_id, code, label, target_table, required_for_pl bool, required_for_bs bool)
dimension_value(id, company_id, dimension_id, code, name, parent_id)
account_dimension_rule(id, company_id, account_id, dimension_id,
                       mode dim_mode_enum /*require|allow|restrict*/)
account_dimension_rule_value(company_id, rule_id, dimension_value_id)

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
         asset_id bigint NULL,                           -- company-scoped FK to asset (§19); see CHECK below
         finance_book_id bigint NULL,
         report_type report_type_enum NOT NULL,          -- denormalised for CHECKs and reports
         is_opening bool NOT NULL DEFAULT false)
   CHECK (debit >= 0 AND credit >= 0 AND NOT (debit > 0 AND credit > 0))
   CHECK (amount = debit - credit)
   CHECK (report_type <> 'profit_and_loss' OR cost_center_id IS NOT NULL)
   -- asset accountability: every leg touching an asset-role account names the asset it belongs to,
   -- which is what makes the §20.4 and §21.4 per-asset reconciliations computable at all
   CHECK (asset_id IS NOT NULL OR account_id NOT IN (SELECT … asset-role accounts))
      -- implemented as a trigger over account.account_type IN ('fixed_asset','capital_work_in_progress',
      -- 'accumulated_depreciation','revaluation_reserve','impairment','asset_disposal')
   CHECK (finance_book_id IS NULL OR asset_id IS NOT NULL)
   INDEX (company_id, posting_date, account_id) INCLUDE (amount)
   INDEX (voucher_id) ; INDEX (settles_voucher_id) ; INDEX (party_id, account_id)
   INDEX (company_id, asset_id, account_id, finance_book_id) INCLUDE (amount) WHERE asset_id IS NOT NULL
gl_entry_dimension(company_id, gl_entry_id, dimension_id, dimension_value_id)
   PK (company_id, gl_entry_id, dimension_id)

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
budget_line(company_id, budget_id, account_id, amount numeric(19,4))
monthly_distribution(id, company_id, code) ; monthly_distribution_line(id, month smallint, percentage)

deferral_schedule(id, company_id, source_line_type, source_line_id, kind deferral_kind_enum,
                  deferral_account_id, target_account_id, total_amount numeric(19,4),
                  service_start date, service_end date, service_stop date NULL, state)
deferral_booking(id, company_id, deferral_schedule_id, period_start, period_end,
                 amount numeric(19,4), voucher_id, booked_at)
   UNIQUE (company_id, deferral_schedule_id, period_start)   -- idempotency: one booking per schedule per period
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
item_attribute_value(id, company_id, item_attribute_id, value, abbr)
   UNIQUE (company_id, item_attribute_id, value)
item_variant_attribute(company_id, item_id, item_attribute_id, item_attribute_value_id NULL,
                       numeric_value NULL)
   -- variant identity:
   UNIQUE (company_id, template_id, attribute_fingerprint)   -- generated column: sha256 of sorted (attr,value) pairs
item_uom(company_id, item_id, uom_id, factor numeric(21,9))
   PK (company_id, item_id, uom_id)
   -- CHECK: the row where uom_id = item.stock_uom_id has factor = 1
item_default(item_id, company_id, warehouse_id, income_account_id, expense_account_id,
             cost_center_id, supplier_id, price_list_id)  PK (item_id, company_id)
item_reorder(id, company_id, item_id, warehouse_id, warehouse_group_id, level numeric(21,9),
             qty numeric(21,9), request_type mr_type_enum)
   UNIQUE (company_id, item_id, warehouse_id, request_type)
item_standard_cost(id, company_id, item_id, effective_date date, rate numeric(21,9), voucher_id)
   UNIQUE (company_id, item_id, effective_date)   -- strictly increasing enforced in service

inventory_owner(id, company_id, kind inventory_owner_kind_enum /*company|customer|supplier|third_party*/,
                party_id NULL, owning_company_id NULL, code)
   UNIQUE (company_id, code)
   CHECK ((kind = 'company') = (owning_company_id IS NOT NULL))
   CHECK ((kind IN ('customer','supplier','third_party')) = (party_id IS NOT NULL))
inventory_owner_policy_revision(id, company_id, inventory_owner_id, revision_no integer,
                valuation_policy owner_valuation_enum, inventory_account_id NULL,
                effective_from timestamptz, effective_to timestamptz NULL,
                state revision_state_enum, approved_at NULL, approved_by NULL)
   UNIQUE (company_id, inventory_owner_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, inventory_owner_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
inventory_custodian(id, company_id, kind custodian_kind_enum /*company|customer|supplier|third_party*/,
                    party_id NULL, custodial_company_id NULL, code)
   UNIQUE (company_id, code)
   CHECK ((kind = 'company') = (custodial_company_id IS NOT NULL))
   CHECK ((kind IN ('customer','supplier','third_party')) = (party_id IS NOT NULL))
   -- deferred type trigger proves party.company_id and party.kind match owner/custodian.kind;
   -- owning/custodial companies must be the row company or an authorised intercompany party

warehouse(id, company_id, code, name, parent_id, is_group bool,
          inventory_account_id, is_rejected bool, capacity_uom_id, default_custodian_id,
          is_disabled bool)
   UNIQUE (company_id, code)
putaway_rule(id, company_id, item_id, warehouse_id, priority int,
             capacity numeric(21,9), uom_id, is_disabled bool)
batch(id, company_id, item_id, code, manufacturing_date, expiry_date,
      use_batch_valuation bool, is_disabled bool)  UNIQUE (company_id, item_id, code)
serial(id, company_id, item_id, code, warehouse_id, batch_id, owner_id, custodian_id,
       state serial_state_enum, warranty_expiry, amc_expiry)  UNIQUE (company_id, item_id, code)

stock_move(id, company_id, item_id, warehouse_id, owner_id, custodian_id,
           owner_policy_revision_id,
           posting_at timestamptz NOT NULL,           -- GENERATED from (posting_date, posting_time)
           seq bigint NOT NULL,                       -- from a sequence; total order tie-break
           qty_delta numeric(21,9) NOT NULL,          -- SIGNED. no absolute rows, ever.
           unit_rate numeric(21,9),
           move_kind move_kind_enum, is_opening bool,
           source_doc_type text NOT NULL, source_doc_id bigint NOT NULL, source_line_id bigint,
           created_at, created_by)
   UNIQUE (company_id, item_id, warehouse_id, owner_id, custodian_id, seq)
   INDEX (company_id, item_id, warehouse_id, owner_id, custodian_id, posting_at, seq)
   INDEX (company_id, source_doc_type, source_doc_id)
   -- owner/custodian/policy revision are immutable snapshots; title transfer is paired evidence
stock_move_dependency(company_id, move_id, depends_on_move_id)  PK (company_id, move_id, depends_on_move_id)
stock_move_serial(company_id, move_id, serial_id, unit_rate)    PK (company_id, move_id, serial_id)
stock_move_batch(company_id, move_id, batch_id, qty numeric(21,9), unit_rate)
   PK (company_id, move_id, batch_id)

stock_value_event(id, company_id, stock_move_id,
    event_kind stock_value_event_enum /*initial|backdate_adjustment|manual_revaluation|reversal*/,
    value_delta numeric(19,4) NOT NULL, valuation_method valuation_method_enum,
    basis_from_seq bigint, basis_through_seq bigint, basis_hash char(64),
    adjusts_value_event_id bigint NULL, reverses_value_event_id bigint NULL,
    command_receipt_id, created_at, created_by)
   UNIQUE (company_id, stock_move_id) WHERE event_kind = 'initial'
   UNIQUE (company_id, adjusts_value_event_id, basis_hash)
      WHERE adjusts_value_event_id IS NOT NULL
   UNIQUE (company_id, reverses_value_event_id) WHERE reverses_value_event_id IS NOT NULL
   -- append-only authority: zero-quantity revaluation is an event against a stock_move, never mutation
stock_value_gl_allocation(id, company_id, stock_value_event_id, voucher_id, gl_entry_id,
    allocated_amount numeric(19,4), command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, stock_value_event_id, gl_entry_id)
   UNIQUE (company_id, gl_entry_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   -- gl_entry.voucher_id must equal voucher_id and be an inventory leg with event source provenance
   -- company-valued events require allocations; non-company policy requires none and value_delta=0
valuation_stream_watermark(id, company_id, item_id, warehouse_id, owner_id, custodian_id,
    recomputed_through_seq bigint, closed_through_posting_at timestamptz NULL,
    source_event_hash char(64), row_version bigint, updated_at)
   UNIQUE (company_id, item_id, warehouse_id, owner_id, custodian_id)

stock_valuation_state(company_id, item_id, warehouse_id, owner_id, custodian_id, seq,
                      qty_after numeric(21,9), value_after numeric(19,4),
                      candidate_value_delta numeric(19,4), authoritative_value_delta numeric(19,4),
                      unit_cost numeric(21,9), queue jsonb, computed_at, computed_from_seq)
   PRIMARY KEY (company_id, item_id, warehouse_id, owner_id, custodian_id, seq)
batch_valuation_state(company_id, item_id, warehouse_id, owner_id, custodian_id, batch_id, seq,
                      qty_after, value_after, unit_cost)
   PRIMARY KEY (company_id, item_id, warehouse_id, owner_id, custodian_id, batch_id, seq)
stock_balance(company_id, item_id, warehouse_id, owner_id, custodian_id,
              qty_on_hand, value, unit_cost,
              qty_ordered, qty_requested, qty_planned, qty_reserved, qty_reserved_production)
   PRIMARY KEY (company_id, item_id, warehouse_id, owner_id, custodian_id)
stock_recompute_job(id, company_id, item_id, warehouse_id, owner_id, custodian_id,
                    from_seq, state, leased_by, leased_until, checkpoint_seq, error, created_at)
   UNIQUE (company_id, item_id, warehouse_id, owner_id, custodian_id)
      WHERE state IN ('queued','running')

stock_reservation(id, company_id, item_id, warehouse_id, owner_id, custodian_id,
                  source_doc_type, source_doc_id, source_line_id,
                  qty numeric(21,9), qty_delivered numeric(21,9),
                  batch_id NULL, serial_id NULL, state reservation_state_enum, reserved_at)
   INDEX (company_id, item_id, warehouse_id, owner_id, custodian_id) WHERE state = 'active'
pick(id, company_id, purpose pick_purpose_enum, state)
pick_line(id, company_id, pick_id, item_id, warehouse_id, owner_id, custodian_id,
          batch_id, serial_id, qty numeric(21,9))
```

**Business rules**
1. **Quantity and value authority are both append-only.** `stock_move` is immutable quantity evidence.
   `stock_value_event` is immutable signed company-value evidence: every valued move gets one `initial`
   event, and backdated replay appends the net difference as one or more `backdate_adjustment` events
   plus linked adjustment vouchers. A stock count is a signed quantity delta; a zero-quantity
   revaluation is a `stock_value_event` and linked voucher, not a mutation. `stock_valuation_state` is
   the rebuildable candidate/projection and may discover differences, but never rewrites move,
   conversion, value-event or GL facts.
2. Total order per `(company,item,warehouse,owner,custodian)` is `(posting_at, seq)`. `seq` comes from a
   sequence, so ties are deterministic and survive imports. Replay locks the stream watermark. It may
   insert behind the watermark, but before publishing a new watermark it must append every required
   value adjustment and voucher in the same deferred-constraint transaction. A closed accounting
   period blocks backdating unless the ordinary period-override policy authorises a current-period
   adjustment; closed facts are never reopened. ERPNext orders on `creation` (`docs/logic/02` §2.1).
3. For each company-valued stream/account and watermark, the signed sum of **all**
   `stock_value_event.value_delta` kinds—initial, backdate adjustment, manual revaluation and reversal—
   equals the signed sum of their exact `stock_value_gl_allocation.allocated_amount`; reversal is a
   negative event and never removes the original from the sum. Deferred triggers require allocations
   for each event to sum to that event's delta, each inventory `gl_entry` to be allocated exactly once
   for its full amount, each allocation's voucher to equal `gl_entry.voucher_id`, and each voucher to
   balance independently. A voucher may serve multiple events without double counting because links are
   to unique GL entries, not repeated voucher totals. The projection bridge additionally requires
   `Σ authoritative_value_delta = Σ all signed stock_value_event.value_delta` through the watermark.
   Non-company policy revisions require zero value and no inventory GL allocation. This is the M37/M50
   authority; no business rule or conversion equation reads mutable `candidate_value_delta`
   (`docs/logic/03` §3.8).
4. `stock_balance` is a cache. Demand columns are defined as queries over open order lines with a
   nightly diff-and-alert. No business rule reads it, and no accounting number comes from it.
5. Reservation is its own table, never a mutable counter on `stock_balance`. Availability is scoped by
   exact `(company,item,warehouse,owner,custodian,tracked lot)` and equals
   `qty_on_hand − Σ active reservation.qty (net of delivered)`; the negative-stock check runs
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
<doc>_line(id, company_id, <doc>_id, line_no int, item_id, description,
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
      UNIQUE (company_id, <doc>_id, line_no))

doc_tax(id, company_id, <doc>_type, <doc>_id, line_no, charge_type charge_type_enum, account_id,
        rate numeric(9,6), amount numeric(19,4), amount_after_discount numeric(19,4),
        base_amount numeric(19,4), category tax_category_enum, add_or_deduct side_enum,
        is_inclusive bool, row_ref int, is_withholding bool, do_not_recompute bool,
        running_total numeric(19,4))
doc_tax_line_alloc(company_id, doc_tax_id, line_id, taxable_amount, amount)
   -- INVARIANT: Σ doc_tax_line_alloc.amount = doc_tax.base_amount_after_discount (exact, by
   -- error-diffusion — ERPNext's trick, docs/logic/05 §5.5)

payment_schedule(id, company_id, <doc>_type, <doc>_id, line_no, payment_term_id, due_date,
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
payment_deduction(company_id, payment_id, line_no, account_id, cost_center_id, amount,
                  is_exchange_gain_loss bool)
payment_tax(company_id, payment_id, line_no, account_id, rate, amount, is_inclusive_in_paid bool)

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
| R1 | Reservation: `Σ active reservation.qty ≤ qty_on_hand` per (company, item, warehouse, owner, custodian) at all times |
| R2 | A reservation is released exactly once (delivered, cancelled or expired) |
| V1 | Variant identity: `UNIQUE (company_id, template_id, attribute_fingerprint)` |
| U1 | `item_uom` contains the stock UOM with factor 1; `stock_uom_id` frozen once moves exist |

---

## 10. Production-wide command, event and projection infrastructure

Tranche B uses the existing `stock_move`, `voucher`, `gl_entry`, `stock_reservation` and projection
structures; it does **not** define parallel ledgers. Production-specific records reference those
existing rows. Every table below carries `company_id`, company-scoped FKs/uniqueness, RLS and
`FORCE RLS` under the conventions at the top of this document.

```sql
command_receipt(id, company_id, command_kind command_kind_enum, idempotency_key varchar(128),
                request_hash char(64), actor_id,
                state command_state_enum /*in_progress|succeeded|terminal_failed|retryable_failed*/,
                lease_owner text NULL, lease_until timestamptz NULL, attempt_no integer,
                business_commit_token uuid NOT NULL, result_hash char(64) NULL,
                error_code text NULL, error_detail jsonb NULL, next_retry_at timestamptz NULL,
                created_at, last_started_at, completed_at NULL)
   UNIQUE (company_id, command_kind, idempotency_key)
   UNIQUE (company_id, business_commit_token)
   UNIQUE (company_id, id, business_commit_token)
command_result_child(id, company_id, command_receipt_id, child_ordinal integer,
                     result_scope_hash char(64), result_type text, result_id bigint)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, command_receipt_id, result_scope_hash)
   -- one external receipt can name any number of stable child results
command_business_commit(id, company_id, command_receipt_id, business_commit_token uuid,
                        result_manifest jsonb, result_set_hash char(64),
                        authoritative_root_count integer, event_set_hash char(64), committed_at timestamptz)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, business_commit_token)
   UNIQUE (company_id, id)
   FOREIGN KEY (company_id,command_receipt_id,business_commit_token)
      REFERENCES command_receipt(company_id,id,business_commit_token)
   CHECK (authoritative_root_count > 0)
   -- append-only marker inserted in the fact transaction; deferred trigger recomputes both hashes/count

domain_aggregate_owner(id, company_id, aggregate_type domain_aggregate_enum,
                       aggregate_id bigint, next_event_position bigint NOT NULL, row_version bigint)
   UNIQUE (company_id, aggregate_type, aggregate_id)
   -- domain_aggregate_enum covers production aggregates AND asset aggregates
   -- (asset, asset_finance_book, asset_location, maintenance_task, asset_service, asset_transformation)
domain_event(id, company_id, aggregate_owner_id, event_position bigint,
                 event_type domain_event_enum, command_receipt_id, child_ordinal integer,
                 business_commit_id, reverses_event_id bigint NULL,
                 occurred_at timestamptz, actor_id, payload jsonb)
   UNIQUE (company_id, aggregate_owner_id, event_position)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_event_id) WHERE reverses_event_id IS NOT NULL
   FOREIGN KEY (company_id,business_commit_id)
      REFERENCES command_business_commit(company_id,id) DEFERRABLE INITIALLY DEFERRED
   -- append-only; aggregate_type/id are obtained from aggregate_owner, never duplicated

transactional_outbox(id, company_id, event_id bigint NOT NULL,
                     state outbox_state_enum, lease_owner text NULL, lease_until timestamptz NULL,
                     attempts integer NOT NULL DEFAULT 0, available_at timestamptz, published_at NULL)
   UNIQUE (company_id, event_id)
   FOREIGN KEY (company_id,event_id) REFERENCES domain_event(company_id,id)
   -- event type, aggregate, position and payload are always joined/derived from domain_event

projection_checkpoint(id, company_id, projector_code varchar(64),
                      aggregate_owner_id, last_event_position bigint,
                      computed_at timestamptz, row_version bigint)
   UNIQUE (company_id, projector_code, aggregate_owner_id)
```

**Concurrent command protocol.** Before any business lock or side effect, the command performs
insert-or-select on the receipt key in a short durable control transaction. A hash mismatch is terminal.
A matching `succeeded` or `terminal_failed` receipt replays the stored result/error without side effects.
A matching live `in_progress` receipt waits for notification/row change and then reselects; an expired
lease may be taken over with compare-and-swap on `(attempt_no,lease_until)`. A retryable failure records
its error and retry time durably. The business transaction reserves one commit-marker ID, writes its
complete authoritative root graph under `command_receipt_id`, writes all event/outbox rows referencing
that deferred marker, and finally inserts `command_business_commit` with recomputed root count and
result/event-set hashes plus the immutable result manifest. A deferred trigger rejects a marker unless
every authoritative root is linked, the manifest resolves to that complete graph and both hashes/count
match. The marker's company-scoped token and receipt are one-to-one. Takeover uses this marker as the **only** commit-discovery signal: if present, it publishes
`command_result_child` rows and marks the receipt succeeded instead of reposting; if absent, the whole
business transaction rolled back. Success/result publication occurs only after the business commit;
a crash between them is recovered by discovery. Terminal failure is recorded in a separate control
transaction after business rollback, and is retained. Thus the receipt survives rollback, while no
partial business facts do. Same-key/same-hash replay is deterministic in every state.

**Event/outbox protocol.** The fact transaction locks one `domain_aggregate_owner`, takes exactly
`next_event_position`, inserts the event and its one outbox row, then advances the owner by one. All three
changes commit or roll back together, so aborted transactions consume no position and committed streams
are contiguous. Deferred triggers reject an event without exactly one outbox row, an outbox without its
event, or a position other than the locked next position. A projector may advance only to the next
contiguous event under checkpoint lock/row version and may update only projections. Publication uses
`FOR UPDATE SKIP LOCKED`; projectors/outbox workers never create authority, stock value or GL evidence.
Planning, reservation, allocation, execution and quality scope always carries owner and custodian when
inventory is involved.

---

## 11. Product, process, calendar and policy revisions

```sql
production_policy(id, company_id, code, name) UNIQUE (company_id, code)
production_policy_revision(id, company_id, production_policy_id, revision_no integer,
    effective_from timestamptz, effective_to timestamptz NULL, state revision_state_enum,
    explosion_policy explosion_policy_enum, backflush_policy backflush_policy_enum,
    loss_policy loss_policy_enum, coproduct_policy coproduct_policy_enum,
    costing_policy production_costing_enum, quality_template_revision_id bigint NULL,
    overproduction_pct numeric(9,6), approved_at NULL, approved_by NULL,
    supersedes_revision_id bigint NULL)
   UNIQUE (company_id, production_policy_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, production_policy_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
   CHECK (overproduction_pct >= 0)

bom(id, company_id, code, output_item_id, state definition_state_enum)
   UNIQUE (company_id, code)
bom_revision(id, company_id, bom_id, revision_no integer,
    output_qty numeric(21,9), output_uom_id, effective_from timestamptz,
    effective_to timestamptz NULL, state revision_state_enum,
    production_policy_revision_id, source_currency_id, approved_at NULL, approved_by NULL,
    supersedes_revision_id bigint NULL, structure_hash char(64))
   UNIQUE (company_id, bom_id, revision_no)
   CHECK (output_qty > 0)
   CHECK (effective_to IS NULL OR effective_to > effective_from)
bom_default_revision(id, company_id, output_item_id, bom_revision_id,
    effective_from timestamptz, effective_to timestamptz NULL, decision_event_id)
   UNIQUE (company_id, bom_revision_id)
   EXCLUDE USING gist (company_id WITH =, output_item_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&)
   CHECK (effective_to IS NULL OR effective_to > effective_from)

bom_component(id, company_id, bom_revision_id, stable_line_key uuid, item_id,
    qty numeric(21,9), uom_id, conversion_factor numeric(21,9), stock_qty numeric(21,9),
    component_bom_revision_id NULL, source_warehouse_id NULL, operation_key uuid NULL,
    owner_policy owner_policy_enum, is_phantom bool, scrap_pct numeric(9,6))
   UNIQUE (company_id, bom_revision_id, stable_line_key)
   CHECK (qty > 0 AND conversion_factor > 0 AND stock_qty = qty * conversion_factor)
   CHECK (scrap_pct >= 0 AND scrap_pct <= 100)
   -- component_bom_revision must produce item_id (or an explicitly allowed coproduct)

bom_output(id, company_id, bom_revision_id, stable_line_key uuid, item_id,
    output_role output_role_enum /*principal|semi_finished|byproduct|scrap*/,
    qty numeric(21,9), uom_id, allocation_weight numeric(21,9), operation_key uuid NULL)
   UNIQUE (company_id, bom_revision_id, stable_line_key)
   CHECK (qty >= 0 AND allocation_weight >= 0)

bom_revision_edge(id, company_id, parent_bom_revision_id, component_line_id,
                  child_bom_revision_id, edge_kind bom_edge_enum)
   UNIQUE (company_id, parent_bom_revision_id, component_line_id)
   CHECK (parent_bom_revision_id <> child_bom_revision_id)
   -- publish trigger rejects cycles and stores the complete path in the error

bom_explosion_projection(id, company_id, bom_revision_id, explosion_policy,
    source_fingerprint char(64), material_key char(64), item_id, operation_key uuid NULL,
    warehouse_id NULL, owner_policy, qty_per_output numeric(21,9), computed_at, event_position)
   UNIQUE (company_id, bom_revision_id, explosion_policy, material_key)

bom_cost_snapshot(id, company_id, bom_revision_id, output_qty numeric(21,9),
    currency_id, material_cost numeric(19,4), operation_cost numeric(19,4),
    secondary_credit numeric(19,4), total_cost numeric(19,4), unit_cost numeric(21,9),
    calculator_version varchar(64), source_fingerprint char(64), effective_at, created_at)
   UNIQUE (company_id, bom_revision_id, source_fingerprint, calculator_version)
bom_cost_source(id, company_id, bom_cost_snapshot_id, source_kind cost_source_kind_enum,
    source_record_id bigint, source_effective_at timestamptz, source_currency_id,
    exchange_rate numeric(21,9), qty numeric(21,9), unit_rate numeric(21,9),
    amount numeric(19,4))
   UNIQUE (company_id, bom_cost_snapshot_id, source_kind, source_record_id)

operation_definition(id, company_id, code, name) UNIQUE (company_id, code)
operation_revision(id, company_id, operation_definition_id, revision_no integer,
    state revision_state_enum, duration_minutes numeric(21,9), batch_size numeric(21,9),
    work_instruction text, required_capability_id, quality_template_revision_id NULL,
    effective_from timestamptz, effective_to timestamptz NULL)
   UNIQUE (company_id, operation_definition_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, operation_definition_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (duration_minutes > 0 AND batch_size > 0)
   CHECK (effective_to IS NULL OR effective_to > effective_from)

route(id, company_id, code, name) UNIQUE (company_id, code)
route_revision(id, company_id, route_id, revision_no integer, state revision_state_enum,
    effective_from timestamptz, effective_to timestamptz NULL, approved_at, approved_by)
   UNIQUE (company_id, route_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, route_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
route_operation(id, company_id, route_revision_id, stable_node_key uuid,
    operation_revision_id, ordinal integer, default_resource_id NULL,
    duration_minutes numeric(21,9), batch_size numeric(21,9), quality_template_revision_id NULL)
   UNIQUE (company_id, route_revision_id, stable_node_key)
   UNIQUE (company_id, route_revision_id, ordinal, stable_node_key)
   CHECK (duration_minutes > 0 AND batch_size > 0)
route_edge(id, company_id, route_revision_id, predecessor_node_id, successor_node_id)
   UNIQUE (company_id, route_revision_id, predecessor_node_id, successor_node_id)
   CHECK (predecessor_node_id <> successor_node_id)
   -- publish trigger rejects cycles; parallel nodes are nodes with no edge between them

resource(id, company_id, code, name, capability_id, timezone_name text,
         state resource_state_enum, warehouse_id NULL)
   UNIQUE (company_id, code)
resource_capacity_revision(id, company_id, resource_id, revision_no integer,
    effective_from timestamptz, effective_to timestamptz NULL,
    capacity_units numeric(21,9), state revision_state_enum)
   UNIQUE (company_id, resource_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, resource_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
   CHECK (capacity_units > 0)
resource_rate_revision(id, company_id, resource_id, revision_no, effective_from,
    effective_to NULL, currency_id, machine_rate numeric(21,9), labour_rate numeric(21,9),
    overhead_rate numeric(21,9), state revision_state_enum)
   UNIQUE (company_id, resource_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, resource_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
   CHECK (machine_rate >= 0 AND labour_rate >= 0 AND overhead_rate >= 0)
resource_calendar_revision(id, company_id, resource_id, revision_no, timezone_name text,
    effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, resource_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, resource_id WITH =,
      daterange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
resource_calendar_interval(id, company_id, calendar_revision_id, interval_no integer,
    local_start time, local_end time, weekday smallint, capacity_units numeric(21,9))
   UNIQUE (company_id, calendar_revision_id, interval_no)
   CHECK (weekday BETWEEN 1 AND 7 AND local_end > local_start AND capacity_units > 0)
   -- exclusion trigger prevents overlap within a weekday/revision
calendar_exception(id, company_id, calendar_revision_id, starts_at, ends_at,
    exception_kind calendar_exception_enum, capacity_units numeric(21,9))
   CHECK (ends_at > starts_at AND capacity_units >= 0)
```

Approved revisions and their children reject `UPDATE`/`DELETE`. Every date-resolved approved
operation, route, capacity, rate, calendar, policy and template revision has a positive half-open range
and stable-identity non-overlap exclusion. Supersession appends a new revision plus an immutable
withdrawal/default-range event; it never edits the old row. Released/posted records retain exact old
FKs. All money/quantity equations use the fixed types above and one named deterministic residual line.

---

## 12. Planning, MPS, netting and release

```sql
planning_run(id, company_id, run_no, run_kind planning_kind_enum /*production_plan|mps|mrp*/,
    as_of_at timestamptz, horizon_start date, horizon_end date, source_watermark bigint,
    revision_set_hash char(64), result_hash char(64) NULL, state planning_state_enum,
    command_receipt_id, approved_at NULL, approved_by NULL)
   UNIQUE (company_id, run_no)
   UNIQUE (company_id, command_receipt_id)
   CHECK (horizon_end >= horizon_start)

planning_input_revision(id, company_id, planning_run_id, input_kind planning_input_enum,
    source_id bigint, revision_id bigint, source_hash char(64))
   UNIQUE (company_id, planning_run_id, input_kind, source_id)
planning_demand(id, company_id, planning_run_id, item_id, warehouse_id, owner_id, custodian_id,
    required_on date, demand_class demand_class_enum, source_doc_type, source_doc_id,
    source_line_id, qty numeric(21,9), uom_id, stock_qty numeric(21,9))
   UNIQUE (company_id, planning_run_id, source_doc_type, source_line_id, required_on, demand_class)
   CHECK (qty > 0 AND stock_qty > 0)
planning_requirement(id, company_id, planning_run_id, demand_id, bom_revision_id,
    component_line_id, explosion_path ltree, item_id, warehouse_id, owner_id, custodian_id,
    required_on date, gross_qty numeric(21,9), safety_qty numeric(21,9),
    net_qty numeric(21,9), stock_uom_id)
   UNIQUE (company_id, planning_run_id, demand_id, component_line_id, explosion_path)
   CHECK (gross_qty >= 0 AND safety_qty >= 0 AND net_qty >= 0)
planning_supply_allocation(id, company_id, planning_run_id, requirement_id,
    supply_kind planning_supply_enum, supply_id bigint, supply_date date,
    qty numeric(21,9), allocation_ordinal integer, reverses_allocation_id bigint NULL)
   UNIQUE (company_id, requirement_id, supply_kind, supply_id, allocation_ordinal)
   CHECK (qty > 0)
   -- deferred trigger: allocated qty cannot exceed requirement or dated supply residual
planning_exception(id, company_id, planning_run_id, requirement_id NULL,
    code planning_exception_code_enum, severity exception_severity_enum, detail jsonb)
planning_proposal(id, company_id, planning_run_id, requirement_id, proposal_kind supply_kind_enum,
    item_id, warehouse_id, owner_id, custodian_id, release_on date, due_on date,
    qty numeric(21,9), state proposal_state_enum, proposal_hash char(64))
   UNIQUE (company_id, planning_run_id, proposal_hash)
   CHECK (qty > 0 AND due_on >= release_on)
proposal_release(id, company_id, planning_proposal_id, release_kind supply_kind_enum,
    idempotency_key varchar(128), released_doc_type text, released_doc_id bigint,
    released_at, reverses_release_id bigint NULL)
   UNIQUE (company_id, planning_proposal_id, release_kind)
   UNIQUE (company_id, release_kind, idempotency_key)
```

Planning rows are immutable after run approval. Release is separate, revalidates under source-owner
locks and must use ordinary document validators. There is no controller hook that promises a missing
`make_mrp`; the durable `planning_run` and its job are the MRP product.

---

## 13. Capacity, Work Orders and actual work

```sql
resource_day_capacity(id, company_id, resource_id, local_date date,
    capacity_revision_id, calendar_revision_id, timezone_name text,
    available_units numeric(21,9), source_hash char(64), row_version bigint)
   UNIQUE (company_id, resource_id, local_date, capacity_revision_id)
   CHECK (available_units >= 0)
resource_capacity_commitment(id, company_id, resource_day_capacity_id,
    commitment_kind capacity_commitment_enum /*reservation|downtime*/,
    source_type text, source_id bigint, slice_ordinal integer,
    starts_at timestamptz, ends_at timestamptz, capacity_units numeric(21,9),
    command_receipt_id, child_ordinal integer, reverses_commitment_id bigint NULL)
   UNIQUE (company_id, source_type, source_id, slice_ordinal)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_commitment_id) WHERE reverses_commitment_id IS NOT NULL
   CHECK (ends_at > starts_at AND capacity_units > 0)
capacity_reservation(id, company_id, resource_id, route_operation_id,
    work_order_operation_id, execution_lot_id NULL, starts_at timestamptz, ends_at timestamptz,
    capacity_revision_id, calendar_revision_id, capacity_units numeric(21,9),
    command_receipt_id, child_ordinal integer, reverses_reservation_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   CHECK (ends_at > starts_at AND capacity_units > 0)
downtime_event(id, company_id, resource_id, starts_at, ends_at,
    capacity_revision_id, calendar_revision_id, capacity_units numeric(21,9),
    reason_code downtime_reason_enum, actor_id, command_receipt_id, child_ordinal integer,
    reverses_downtime_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   CHECK (ends_at > starts_at AND capacity_units > 0)
```

Reservation and downtime commands resolve the one approved capacity/calendar revisions at each local
instant, snapshot those FKs, expand every interval into one half-open commitment slice per affected
resource local day, and lock all `resource_day_capacity` rows in `(company,resource,local_date)` order.
One deferred trigger covers **both** kinds and rejects, for every instant/slice,
`SUM(unreversed commitment.capacity_units) > resource_day_capacity.available_units`; unit and parallel
resources use this same summed surface, not a parent-column exclusion. The source/detail interval must
equal the contiguous union of its slices and every slice must cite the same snapshotted revisions.
Downtime therefore either fits residual capacity or the same transaction appends reversals for all
conflicting reservations and replacement slices under the same locks; no mutable “rescheduled” state is
accepted. Multi-day reversal locks and compensates the identical day set.

```sql
work_order(id, company_id, doc_no, output_item_id, output_qty numeric(21,9), output_uom_id,
    inventory_owner_id, inventory_custodian_id, bom_revision_id, route_revision_id,
    production_policy_revision_id,
    source_warehouse_id, wip_warehouse_id, target_warehouse_id,
    demand_allocation_id, state work_order_state_enum,
    command_receipt_id, created_at, created_by)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, command_receipt_id)
   CHECK (output_qty > 0)
work_order_material(id, company_id, work_order_id, stable_line_key uuid,
    bom_component_id, item_id, required_qty numeric(21,9), stock_uom_id,
    source_warehouse_id, owner_id, custodian_id, operation_node_id NULL)
   UNIQUE (company_id, work_order_id, stable_line_key)
   CHECK (required_qty > 0)
work_order_operation(id, company_id, work_order_id, stable_node_key uuid,
    route_operation_id, ordinal integer, authorised_qty numeric(21,9),
    predecessor_fingerprint char(64), quality_template_revision_id NULL)
   UNIQUE (company_id, work_order_id, stable_node_key)
   CHECK (authorised_qty > 0)

production_allocation(id, company_id, allocation_kind production_allocation_enum,
    source_type production_owner_type_enum, source_id bigint, target_type production_owner_type_enum,
    target_id bigint, item_id NULL, owner_id NULL, custodian_id NULL, qty numeric(21,9),
    ordinal integer, command_receipt_id, reverses_allocation_id bigint NULL)
   UNIQUE (company_id, source_type, source_id, target_type, target_id, ordinal)
   UNIQUE (company_id, command_receipt_id, allocation_kind, ordinal)
   CHECK (qty > 0)
   -- deferred/locked check: sum of unreversed allocations <= source authorisation

execution_lot(id, company_id, work_order_operation_id, ordinal integer,
    allocated_output_qty numeric(21,9), serial_scope_hash char(64) NULL,
    command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, work_order_operation_id, ordinal)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   CHECK (allocated_output_qty > 0)
execution_lot_serial(id, company_id, execution_lot_id, serial_id,
    allocation_event_id, command_receipt_id, child_ordinal integer,
    reverses_lot_serial_id bigint NULL)
   UNIQUE (company_id, execution_lot_id, serial_id, allocation_event_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_lot_serial_id) WHERE reverses_lot_serial_id IS NOT NULL
   -- one open allocation per serial is a deferred check over unreversed chains, never a flag
work_order_lifecycle_event(id, company_id, work_order_id, event_no bigint,
    event_type work_order_lifecycle_enum /*release|close|reverse*/,
    command_receipt_id, child_ordinal integer, reverses_event_id bigint NULL,
    occurred_at, actor_id, reason text NULL)
   UNIQUE (company_id, work_order_id, event_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_event_id) WHERE reverses_event_id IS NOT NULL

work_event(id, company_id, execution_lot_id, event_no bigint,
    event_type work_event_enum /*start|pause|resume|stop|output|loss|employee_join|employee_leave*/,
    occurred_at timestamptz, qty numeric(21,9) NULL, employee_id NULL, resource_id NULL,
    actor_id, command_receipt_id, reverses_event_id bigint NULL)
   UNIQUE (company_id, execution_lot_id, event_no)
   UNIQUE (company_id, command_receipt_id, event_type, event_no)
   CHECK (qty IS NULL OR qty >= 0)
resource_usage_cost(id, company_id, execution_lot_id, resource_id, rate_revision_id,
    starts_at, ends_at, currency_id, exchange_rate numeric(21,9),
    unit_rate numeric(21,9), amount numeric(19,4), command_receipt_id,
    reverses_usage_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, resource_id, starts_at, ends_at)
   CHECK (ends_at > starts_at AND unit_rate >= 0)
```

A Work Order header's `state` is mutable draft authority only until the `release` lifecycle event;
release freezes its revision/source/warehouse/owner fields and child snapshots. Thereafter release,
close and reverse are append-only `work_order_lifecycle_event` facts and current state is a projection
of their unreversed chain. `inspection_attempt.state` and similar in-progress workflow fields are also
mutable only before their named submission/completion event; posting, allocation, capacity, quality and
ledger records have no mutable lifecycle state. Conversion, quality, capacity and allocation facts form
the dependency graph. Close/reverse is refused while unreversed dependants exist.

---

## 14. Production conversion, WIP, costing and existing ledgers

```sql
production_conversion(id, company_id, doc_no, work_order_id NULL, execution_lot_id NULL,
    conversion_kind conversion_kind_enum /*manufacture|repack|disassemble|rework|subcontract*/,
    production_policy_revision_id, posting_at timestamptz, inventory_owner_id, custodian_id,
    owner_policy_revision_id, command_receipt_id,
    exact_reversal_of_id bigint NULL, recovery_policy_code text NULL, created_at, created_by)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, exact_reversal_of_id) WHERE exact_reversal_of_id IS NOT NULL
   CHECK ((exact_reversal_of_id IS NULL) OR (recovery_policy_code IS NULL))

production_input(id, company_id, production_conversion_id, line_no integer,
    work_order_material_id NULL, item_id, owner_id, custodian_id, owner_policy_revision_id,
    warehouse_id, qty numeric(21,9), stock_uom_id, source_allocation_id NULL,
    batch_id NULL, serial_scope_hash NULL, reverses_input_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, line_no)
   UNIQUE (company_id, reverses_input_id) WHERE reverses_input_id IS NOT NULL
   CHECK (qty > 0)
production_output(id, company_id, production_conversion_id, line_no integer,
    bom_output_id NULL, item_id, output_role output_role_enum,
    owner_id, custodian_id, owner_policy_revision_id, warehouse_id,
    qty numeric(21,9), stock_uom_id, allocation_weight numeric(21,9),
    batch_id NULL, serial_scope_hash NULL, reverses_output_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, line_no)
   UNIQUE (company_id, reverses_output_id) WHERE reverses_output_id IS NOT NULL
   CHECK (qty >= 0 AND allocation_weight >= 0)
production_loss(id, company_id, production_conversion_id, line_no integer,
    operation_id NULL, loss_kind production_loss_enum /*normal|abnormal*/,
    reason_code text, item_id NULL, qty numeric(21,9), stock_uom_id NULL,
    abnormal_expense_account_id NULL, reverses_loss_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, line_no)
   CHECK (qty >= 0)
   CHECK ((loss_kind = 'normal') = (abnormal_expense_account_id IS NULL))
production_loss_value(id, company_id, production_loss_id,
    source_value_event_id NULL, source_cost_allocation_id NULL,
    abnormal_expense_delta numeric(19,4), command_receipt_id, child_ordinal integer,
    reverses_loss_value_id bigint NULL)
   UNIQUE (company_id, production_loss_id, source_value_event_id, source_cost_allocation_id)
      NULLS NOT DISTINCT
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_loss_value_id) WHERE reverses_loss_value_id IS NOT NULL
   CHECK (num_nonnulls(source_value_event_id,source_cost_allocation_id) = 1)
   -- normal-loss rows have no production_loss_value; abnormal expense uses signed additive deltas

production_input_stock_link(id, company_id, production_input_id, stock_move_id,
    command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, production_input_id, stock_move_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
production_input_value(id, company_id, production_input_id, stock_value_event_id,
    realised_value_delta numeric(19,4), command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, production_input_id, stock_value_event_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
production_output_stock_link(id, company_id, production_output_id, stock_move_id,
    command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, production_output_id, stock_move_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
production_output_value(id, company_id, production_output_id, stock_value_event_id,
    stock_value_delta numeric(19,4), normal_loss_absorption_delta numeric(19,4),
    command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, production_output_id, stock_value_event_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   -- signed deltas permit immutable backdate adjustments; initial-event totals must be nonnegative
production_conversion_voucher(id, company_id, production_conversion_id, voucher_id,
    command_receipt_id, child_ordinal integer, reverses_link_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, voucher_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_link_id) WHERE reverses_link_id IS NOT NULL

conversion_cost_allocation(id, company_id, production_conversion_id, output_id NULL,
    source_kind conversion_cost_source_enum, source_id bigint, source_voucher_id bigint NULL,
    basis_num numeric(21,9), basis_den numeric(21,9), amount numeric(19,4),
    variance_kind production_variance_enum NULL, variance_account_id NULL,
    reverses_allocation_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, output_id, source_kind, source_id)
   CHECK (basis_num >= 0 AND basis_den > 0)
   CHECK ((variance_kind IS NULL) = (variance_account_id IS NULL))

resource_usage_output_allocation(id, company_id, resource_usage_cost_id, production_output_id,
    amount numeric(19,4), reverses_allocation_id bigint NULL)
   UNIQUE (company_id, resource_usage_cost_id, production_output_id)
```

`production_conversion`, `production_input`, `production_output` and `production_loss` are immutable
**authorisation/quantity** facts and are complete when inserted; they contain no future move, value or
voucher columns. Their stable IDs are used in `stock_move.source_line_id`. After the moves exist, the
transaction inserts the append-only stock links; after authoritative `stock_value_event` rows exist, it
inserts input/output value facts; after all amounts are known, it inserts the existing `voucher` and
`gl_entry` rows plus `production_conversion_voucher`. Every association is complete on insert. No row is
“assigned”, marked, or updated after posting, and no production GL table is introduced.

Deferred constraint triggers enforce:

1. complete input quantity/stock/value allocation before any principal/semi-finished output is postable;
2. paired WIP transfer has `SUM(qty_delta)=0` per item/owner and
   `SUM(stock_value_event.value_delta)=0`;
3. the one exact equation
   `Σ output stock_value_delta (principal + semi-finished + by-product + valued scrap, each once and
   including Σ normal_loss_absorption_delta allocated once into surviving outputs) +
   Σ production_loss_value.abnormal_expense_delta + Σ explicit variance =
   Σ input realised_value_delta + Σ resource/service/landed cost` at `numeric(19,4)`.
   Normal physical loss has zero separate expense/value and is absorbed only through the named output
   component; abnormal loss appears only as signed `production_loss_value` deltas and the named
   expense/variance GL leg; scrap value appears only
   as its `production_output(output_role='scrap')`, never again on `production_loss`;
4. every input/output value delta is a one-to-one allocation of its linked authoritative initial or
   adjustment `stock_value_event`; the conversion equation sums all unreversed deltas through the
   valuation watermark, so backdating appends signed value/cost-allocation deltas and a linked adjustment
   voucher without changing an earlier fact; every conversion/inventory account's signed GL amount equals those authoritative events, never rebuildable candidate valuation;
5. Standard Cost output uses the exact effective `item_standard_cost`; actual-minus-standard is one
   explicit named variance allocation/GL leg and cannot also be abnormal-loss expense;
6. serials have one open unreversed stage allocation; batch quantities balance by
   owner/custodian/policy revision/lot; and
7. reversal rows reference exact original quantity, stock-link, value-event, voucher-link, cost and
   tracked-unit facts.

Backdating/replay may append `stock_value_event` adjustments and linked balanced adjustment vouchers;
it never changes conversion facts. Source stock streams reach their authoritative watermark before
dependent outputs. Corrections append a linked reversal conversion, links, value events and voucher; no
production, stock, valuation or GL evidence is updated/deleted.

---

## 15. Subcontracting and explicit inventory ownership

```sql
subcontract_authorisation(id, company_id, doc_no,
    direction subcontract_direction_enum /*supplier_outward|customer_inward*/,
    party_id, commercial_source_type text, commercial_source_id bigint,
    commercial_source_line_id bigint, service_item_id, finished_item_id,
    service_per_fg numeric(21,9), authorised_fg_qty numeric(21,9),
    bom_revision_id, production_policy_revision_id, inventory_owner_id, custodian_id,
    state authorisation_state_enum, command_receipt_id, reverses_authorisation_id bigint NULL)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, commercial_source_type, commercial_source_line_id, direction,
           reverses_authorisation_id) NULLS NOT DISTINCT
   CHECK (service_per_fg > 0 AND authorised_fg_qty > 0)

subcontract_service_allocation(id, company_id, subcontract_authorisation_id,
    source_line_id, allocated_fg_qty numeric(21,9), allocated_service_qty numeric(21,9),
    command_receipt_id, reverses_allocation_id bigint NULL)
   UNIQUE (company_id, subcontract_authorisation_id, source_line_id, command_receipt_id)
   CHECK (allocated_fg_qty > 0 AND allocated_service_qty > 0)
   -- deferred exact equation: service = FG * snapshotted service_per_fg

subcontract_material_allocation(id, company_id, subcontract_authorisation_id,
    bom_component_id, item_id, owner_id, custodian_id, source_warehouse_id,
    custody_warehouse_id, required_qty numeric(21,9), allocation_no integer,
    batch_id NULL, serial_scope_hash NULL)
   UNIQUE (company_id, subcontract_authorisation_id, bom_component_id, allocation_no)
   CHECK (required_qty > 0)

custody_transfer(id, company_id, subcontract_material_allocation_id,
    transfer_kind custody_transfer_enum /*send|return|customer_receipt|customer_return|title_transfer*/,
    qty numeric(21,9), from_owner_id, to_owner_id, from_custodian_id, to_custodian_id,
    from_owner_policy_revision_id, to_owner_policy_revision_id,
    title_authority_kind title_authority_enum, title_authority_type text, title_authority_id bigint,
    source_stock_move_id, target_stock_move_id, source_value_event_id, target_value_event_id,
    voucher_id NULL, tracked_scope_hash char(64), command_receipt_id, child_ordinal integer,
    reverses_transfer_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL
   CHECK (qty > 0 AND source_stock_move_id <> target_stock_move_id)
   CHECK ((transfer_kind = 'title_transfer') = (from_owner_id <> to_owner_id))
   CHECK ((transfer_kind <> 'title_transfer') OR title_authority_id IS NOT NULL)

subcontract_consumption(id, company_id, subcontract_material_allocation_id,
    production_conversion_id, production_input_id, backflush_policy backflush_policy_enum,
    qty numeric(21,9), command_receipt_id, reverses_consumption_id bigint NULL)
   UNIQUE (company_id, production_conversion_id, production_input_id)
   UNIQUE (company_id, command_receipt_id, subcontract_material_allocation_id)
   CHECK (qty > 0)

subcontract_commercial_receipt(id, company_id, production_conversion_id,
    purchase_receipt_id bigint, service_allocation_id, command_receipt_id,
    reverses_receipt_id bigint NULL)
   UNIQUE (company_id, production_conversion_id)
   UNIQUE (company_id, purchase_receipt_id)

subcontract_fulfilment_fact(id, company_id, subcontract_authorisation_id,
    fact_kind subcontract_fulfilment_enum /*custody|attempted|accepted|loss|gross_delivery|return|billing*/,
    source_type text, source_id bigint, qty numeric(21,9), amount numeric(19,4) NULL,
    command_receipt_id, reverses_fact_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, fact_kind, source_type, source_id)
```

Supplier custody retains the company owner; customer inward material retains the customer owner and
company/third-party custodian. `inventory_owner_policy_revision` is approved, immutable once referenced,
and snapshotted on every move, conversion and transfer; zero company value is policy, not provenance.
Owner/custodian type triggers prove matching party kind and company. Generic transfers require identical
from/to owner and may change only custodian; only `title_transfer` may change owner and it requires an
explicit typed authority plus before/after policy revisions.

One deferred paired-transfer trigger proves source and target move company/item/UOM/quantity are exact
opposites, tracked serial sets are identical (or batch sums exact), stored from/to owner/custodian match
the two moves, and the transfer's `tracked_scope_hash` matches both. It also proves authoritative source
and target value events conserve value for custody-only movement; title transfer either conserves value
or has one linked balanced voucher whose inventory/consideration/variance legs equal the policy change.
No side may exist alone at commit. Every stock/valuation/reservation key includes owner and custodian.

BOM and transferred-material backflush are stable policy codes. Both consume exact material-allocation
residuals while the authorisation/material owners are locked. Received output cannot post with an
incomplete material set unless a typed authorised exception is present.

---

## 16. Quality criteria, samples, evaluation, disposition and release

```sql
quality_template(id, company_id, code, name) UNIQUE (company_id, code)
quality_template_revision(id, company_id, quality_template_id, revision_no integer,
    effective_from timestamptz, effective_to timestamptz NULL, state revision_state_enum,
    approved_at NULL, approved_by NULL, supersedes_revision_id bigint NULL)
   UNIQUE (company_id, quality_template_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, quality_template_id WITH =,
      tstzrange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
   CHECK (effective_to IS NULL OR effective_to > effective_from)
quality_criterion_revision(id, company_id, quality_template_revision_id, stable_criterion_key uuid,
    ordinal integer, parameter_code text, parameter_group_code text NULL,
    criterion_mode criterion_mode_enum /*numeric|value|formula*/,
    canonical_uom_id NULL, min_value numeric(21,9) NULL, max_value numeric(21,9) NULL,
    expected_value text NULL, expression_ast jsonb NULL, expression_hash char(64) NULL,
    evaluator_version varchar(64) NULL, required_observations integer, sampling_plan_code text)
   UNIQUE (company_id, quality_template_revision_id, stable_criterion_key)
   UNIQUE (company_id, quality_template_revision_id, ordinal)
   CHECK (required_observations > 0)
   CHECK (min_value IS NULL OR max_value IS NULL OR min_value <= max_value)
   CHECK (
     (criterion_mode = 'numeric' AND canonical_uom_id IS NOT NULL
        AND num_nonnulls(min_value,max_value) >= 1
        AND expected_value IS NULL AND expression_ast IS NULL AND expression_hash IS NULL)
     OR
     (criterion_mode = 'value' AND canonical_uom_id IS NULL
        AND min_value IS NULL AND max_value IS NULL AND expected_value IS NOT NULL
        AND btrim(expected_value) <> '' AND expression_ast IS NULL AND expression_hash IS NULL)
     OR
     (criterion_mode = 'formula' AND expected_value IS NULL
        AND min_value IS NULL AND max_value IS NULL AND expression_ast IS NOT NULL
        AND expression_hash IS NOT NULL AND evaluator_version IS NOT NULL))
   -- formula publish validates constrained AST, stores canonical AST hash and freezes evaluator version

quality_owner(id, company_id, owner_kind quality_owner_enum,
    source_type text, source_id bigint, source_line_id bigint NULL,
    inventory_owner_id NULL, inventory_custodian_id NULL, row_version bigint)
   UNIQUE (company_id, owner_kind, source_type, source_id, source_line_id) NULLS NOT DISTINCT
inspection_requirement(id, company_id, quality_owner_id, requirement_revision_no integer,
    subject_kind quality_subject_enum /*stock_line|operation|output*/,
    item_id NULL, qty numeric(21,9) NULL, uom_id NULL, batch_id NULL,
    serial_scope_hash NULL, direction quality_direction_enum NULL,
    quality_template_revision_id, sample_population integer,
    state requirement_state_enum, supersedes_requirement_id bigint NULL,
    frozen_criterion_count integer, frozen_criterion_hash char(64))
   UNIQUE (company_id, quality_owner_id, requirement_revision_no)
   CHECK (sample_population > 0 AND frozen_criterion_count > 0)
inspection_requirement_criterion(id, company_id, inspection_requirement_id,
    criterion_revision_id, ordinal integer, required_observations integer,
    canonical_uom_id NULL, criterion_hash char(64))
   UNIQUE (company_id, inspection_requirement_id, criterion_revision_id)
   UNIQUE (company_id, inspection_requirement_id, ordinal)
   CHECK (required_observations > 0)
   -- freeze trigger requires exact full approved template set/count/hash; no later membership edits

inspection_attempt(id, company_id, inspection_requirement_id, attempt_no integer,
    state inspection_attempt_state_enum, inspector_id, started_at, completed_at NULL,
    command_receipt_id, child_ordinal integer, supersedes_attempt_id bigint NULL)
   UNIQUE (company_id, inspection_requirement_id, attempt_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
inspection_observation(id, company_id, inspection_attempt_id, requirement_criterion_id,
    sample_position integer, canonical_numeric numeric(21,9) NULL, canonical_text text NULL,
    canonical_uom_id NULL, original_text text, input_locale text, observed_at, observer_id,
    reverses_observation_id bigint NULL)
   UNIQUE (company_id, inspection_attempt_id, requirement_criterion_id, sample_position)
   CHECK (sample_position > 0)
   CHECK (num_nonnulls(canonical_numeric, canonical_text) = 1)
inspection_evaluation(id, company_id, inspection_attempt_id, requirement_criterion_id,
    result evaluation_result_enum /*pass|fail|error*/, evaluator_version varchar(64),
    expression_hash char(64) NULL, trace jsonb, evaluated_at,
    command_receipt_id, child_ordinal integer, supersedes_evaluation_id bigint NULL)
   UNIQUE (company_id, inspection_attempt_id, requirement_criterion_id, evaluator_version)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
inspection_disposition(id, company_id, inspection_attempt_id,
    disposition quality_disposition_enum /*accepted|rejected|hold*/,
    basis disposition_basis_enum /*automatic|manual_override*/,
    reason_code text NULL, reason text NULL, signed_by, signed_at,
    criterion_coverage_hash char(64), command_receipt_id, child_ordinal integer,
    supersedes_disposition_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, supersedes_disposition_id) WHERE supersedes_disposition_id IS NOT NULL
   CHECK ((basis = 'manual_override') = (reason IS NOT NULL))

quality_release(id, company_id, inspection_requirement_id, disposition_id,
    decision quality_release_enum /*release|hold*/, released_qty numeric(21,9) NOT NULL,
    criterion_coverage_hash char(64), released_at, command_receipt_id, child_ordinal integer,
    reverses_release_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_release_id) WHERE reverses_release_id IS NOT NULL
   CHECK (released_qty > 0)
quality_exception(id, company_id, inspection_requirement_id,
    exception_policy_id, reason_code text, reason text, authorised_by, authorised_at,
    expires_at NULL, authorised_qty numeric(21,9) NOT NULL,
    command_receipt_id, child_ordinal integer, reverses_exception_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, reverses_exception_id) WHERE reverses_exception_id IS NOT NULL
   CHECK (authorised_qty > 0 AND (expires_at IS NULL OR expires_at > authorised_at))
quality_gate_consumption(id, company_id, inspection_requirement_id,
    quality_release_id NULL, quality_exception_id NULL,
    consumer_kind quality_consumer_enum /*stock_move|operation_completion*/,
    consumer_type text, consumer_id bigint, consumer_line_id bigint NULL,
    consumed_qty numeric(21,9) NOT NULL, command_receipt_id, child_ordinal integer,
    consumer_scope_hash char(64), reverses_consumption_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   UNIQUE (company_id, command_receipt_id, consumer_scope_hash)
   UNIQUE (company_id, reverses_consumption_id) WHERE reverses_consumption_id IS NOT NULL
   CHECK (consumed_qty > 0 AND num_nonnulls(quality_release_id, quality_exception_id) = 1)
   -- deferred trigger permits at most one open consumption per exact consumer scope

quality_feedback_template_revision(id, company_id, template_code, revision_no integer,
    state revision_state_enum, effective_from date, effective_to date NULL, source_hash char(64))
   UNIQUE (company_id, template_code, revision_no)
   EXCLUDE USING gist (company_id WITH =, template_code WITH =,
      daterange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
quality_feedback_question_revision(id, company_id, feedback_template_revision_id,
    stable_question_key uuid, ordinal integer, response_mode feedback_response_enum,
    prompt text, required bool, scale_min numeric(21,9) NULL, scale_max numeric(21,9) NULL)
   UNIQUE (company_id, feedback_template_revision_id, stable_question_key)
quality_feedback_response(id, company_id, feedback_template_revision_id,
    question_revision_id, respondent_party_id NULL, source_type text, source_id bigint,
    canonical_numeric numeric(21,9) NULL, canonical_text text NULL,
    submitted_at, command_receipt_id, child_ordinal integer, supersedes_response_id bigint NULL)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
   CHECK (num_nonnulls(canonical_numeric,canonical_text) = 1)

quality_goal_revision(id, company_id, goal_code, revision_no, state revision_state_enum,
    effective_from date, effective_to date NULL, schedule_rule jsonb, source_hash char(64))
   UNIQUE (company_id, goal_code, revision_no)
   EXCLUDE USING gist (company_id WITH =, goal_code WITH =,
      daterange(effective_from,effective_to,'[)') WITH &&) WHERE (state = 'approved')
quality_goal_objective_revision(id, company_id, quality_goal_revision_id,
    stable_objective_key uuid, ordinal integer, metric_code text, target_value numeric(21,9),
    canonical_uom_id NULL, weight numeric(9,6))
   UNIQUE (company_id, quality_goal_revision_id, stable_objective_key)
quality_review_occurrence(id, company_id, quality_goal_revision_id, due_date date,
    occurrence_no integer, command_receipt_id, child_ordinal integer,
    reverses_occurrence_id bigint NULL)
   UNIQUE (company_id, quality_goal_revision_id, due_date, occurrence_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
quality_review_result(id, company_id, quality_review_occurrence_id,
    goal_objective_revision_id, actual_value numeric(21,9), canonical_uom_id NULL,
    result quality_review_result_enum, evidence_set_hash char(64),
    command_receipt_id, child_ordinal integer, supersedes_result_id bigint NULL)
   UNIQUE (company_id, quality_review_occurrence_id, goal_objective_revision_id)
   UNIQUE (company_id, command_receipt_id, child_ordinal)

quality_procedure_revision(id, company_id, procedure_code, revision_no, state revision_state_enum,
    source_hash char(64)) UNIQUE (company_id, procedure_code, revision_no)
quality_procedure_edge(id, company_id, procedure_revision_id, parent_node_key uuid,
    child_node_key uuid, ordinal integer)
   UNIQUE (company_id, procedure_revision_id, parent_node_key, child_node_key)
   CHECK (parent_node_key <> child_node_key)
quality_non_conformance(id, company_id, doc_no, source_type text, source_id bigint,
    procedure_revision_id, severity quality_severity_enum, detected_at, detected_by,
    command_receipt_id, child_ordinal integer, supersedes_non_conformance_id bigint NULL)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
quality_action(id, company_id, non_conformance_id NULL, review_result_id NULL,
    procedure_revision_id, action_kind quality_action_kind_enum, title text,
    owner_user_id, due_at, command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
quality_action_task(id, company_id, quality_action_id, task_ordinal integer,
    description text, owner_user_id, due_at)
   UNIQUE (company_id, quality_action_id, task_ordinal)
quality_action_event(id, company_id, quality_action_id,
    event_no integer, event_type quality_action_enum, occurred_at, actor_id, reason text,
    command_receipt_id, child_ordinal integer, reverses_event_id bigint NULL)
   UNIQUE (company_id, quality_action_id, event_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
quality_meeting(id, company_id, meeting_no, procedure_revision_id NULL,
    scheduled_at, occurred_at NULL, chair_user_id, command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, meeting_no)
   UNIQUE (company_id, command_receipt_id, child_ordinal)
quality_meeting_item(id, company_id, quality_meeting_id, item_ordinal integer,
    item_kind quality_meeting_item_enum, subject_type text, subject_id bigint,
    decision text NULL, action_id NULL)
   UNIQUE (company_id, quality_meeting_id, item_ordinal)
quality_evidence_link(id, company_id, evidence_owner_type quality_evidence_owner_enum,
    evidence_owner_id bigint, evidence_kind quality_evidence_kind_enum,
    source_revision_type quality_source_revision_enum, source_revision_id bigint,
    source_record_type text NULL, source_record_id bigint NULL, content_hash char(64), ordinal integer)
   UNIQUE (company_id, evidence_owner_type, evidence_owner_id, evidence_kind, ordinal)
   -- typed trigger maps every source_revision_type to its concrete immutable revision table
```

Approved criteria/templates and all submitted quality/QM evidence are append-only. Correction uses
supersession/reversal; current state is derived from chains, never `is_current`. Requirement freeze
copies the **complete** approved template criterion set, count, order, UOMs and hash. A deferred attempt
trigger proves every observation's requirement-criterion belongs to the attempt's requirement, its
position is in exactly `1..required_observations`, every position exists once before evaluation, numeric
observations use the criterion canonical UOM (with one snapshotted conversion from subject UOM), value
observations are canonical text, and formula evaluation uses the frozen AST/hash/evaluator. Any missing,
extra, duplicate, wrong-criterion, wrong-unit, blank or mode-incompatible sample produces error/hold.

A release is aggregate authority for one frozen requirement, not one criterion. Under the locked
`quality_owner`, a deferred trigger permits exactly one current unreversed disposition and one current
unreversed release/hold per requirement revision; Accepted/release requires passing current evaluations
for every frozen criterion and equality of disposition/release `criterion_coverage_hash` to the frozen
set. `released_qty` is mandatory and bounded by requirement quantity/population. For a release or
exception, `SUM(unreversed quality_gate_consumption.consumed_qty) <= released/authorised_qty`; the
residual is derived from that sum. Every stock/operation consumer must match the full company, owner,
custodian, source, item, UOM, lot/serial, direction and quantity scope and cite the aggregate coverage
before any dependent evidence is inserted. Warn consumes only an authorised unexpired exception.
Plural gates use receipt child ordinals/scope hashes. Scheduled reviews retain unique occurrence
identity; all QM review/feedback/action/meeting evidence has a typed FK to a concrete immutable source
revision through `quality_evidence_link`.

---

## 17. Canonical production command, lock, post and reversal state machine

This is the single normative state machine for production, subcontracting and quality; doc 40 §5–§6
references it and may not define another order.

1. **Authenticate, then claim/replay before business side effects:** establish the §Conventions verified,
   transaction-local tenant context (this writes no business row), then run the §10 insert-or-select
   protocol. Return retained success
   or terminal failure; wait/take over only as specified; perform business-commit discovery before any
   repost. Hash mismatch is rejected.
2. **Guard:** in the business transaction lock/check company, accounting period and draft/released lifecycle. A rejected guard records the retained terminal or
   retryable receipt result after rollback.
3. **Lock once in this order**, taking only needed keys sorted within class:
   period/company policy → commercial/demand source → definition/effective-range owner → Work Order,
   material, operation, subcontract and allocation owner → quality owner/requirement → resource-day
   capacity owner → stock stream `(item,warehouse,owner,custodian,tracked scope)` → account-balance
   owner. No later phase may acquire an earlier class.
4. **Validate under those locks:** exact residuals, frozen revisions/policies, capacity, complete quality
   coverage, tracked units, loss/output entitlement and all reversal dependencies.
5. **Insert immutable authority/quantity facts:** authorisations, conversion/input/output/loss lines and,
   when required, aggregate quality gate consumptions. All are complete on insert.
6. **Insert quantity/tracked evidence:** source before dependent target `stock_move` rows and tracked
   edges, then append their link facts.
7. **Insert value authority:** compute to the locked valuation watermark; insert initial and any
   backdate-adjustment `stock_value_event` rows, then complete conversion value associations.
8. **Insert accounting:** allocate normal-loss absorption, valued scrap, abnormal-loss expense and
   explicit variance exactly once; insert existing voucher/GL rows, exact value-to-GL allocations and
   conversion-voucher links. Deferred checks enforce quantity/value/cost/GL/quality/capacity equations.
9. **Insert event/outbox and commit marker:** allocate each contiguous position under aggregate-owner lock,
   insert its unique outbox row, then insert the one deferred `command_business_commit` marker with
   validated manifest/count/hashes. Commit business facts; publish receipt success/results; only then
   project.

**Exact reversal is one deferred-constraint transaction using steps 1–4 and the same locks.** It first
inserts reversals of every affected `quality_gate_consumption` (so authority is no longer consumed),
then reverses dependent operation/work/resource/capacity evidence, then target-before-source tracked and
quantity stock facts, then value events and the balanced reversing/adjustment voucher, then conversion,
cost, custody and allocation links, and finally lifecycle/release/demand authorisation events. Deferred
checks are defined to accept the temporarily disconnected rows inside that transaction but require the
complete compensating set at commit. Downstream delivery/billing must already be reversed or be included
first under the same locks. Definition supersession is allowed only after no open authorisation depends
on it. No row is marked reversed or updated; every successor cites the exact original. Each external
reversal command has one receipt and stable child ordinals.

This ordering implements M38/M51/M67: evidence commits before projections. Projection failure can be
retried from the event/outbox position without repeating production, stock, quality, value or GL facts.

---

## 18. Production invariant register

The exact M1–M69 names and their primary enforcement layers are consolidated in
[`docs/logic/40`](../logic/40-tranche-b-coverage-closure-and-our-production-spec.md#3-m1m69-exact-register-and-enforcement-owner).
They extend—not replace—the accounting/trade register in §9. In particular:

- M32 and M46 intentionally share **consumption completeness** at internal and subcontract boundaries;
- M38 and M51 intentionally share **evidence before projection** at those boundaries;
- M37/M50 require exact `stock_value_event`/linked-GL equality using the existing
  `stock_move`/`voucher`/`gl_entry`, including immutable replay adjustments;
- M52 is enforced structurally by typed owner/custodian dimensions and frozen owner-policy revisions in
  every stock/value/conversion key; and
- M62/M63 require complete aggregate quality coverage and quantity-bounded release/exception consumption
  before stock/operation evidence.

Every M invariant requires a schema refusal test; allocation/locking/idempotency invariants additionally
require concurrent interleaving and retry tests. S07–S10 are the end-to-end acceptance fixtures.

---

## 19. Asset identity, acquisition and recognition

Tranche C ([docs 41–43](../logic/41-asset-identity-acquisition-and-finance-books.md), scenario
[S11](../scenarios/S11-asset-lifecycle.md)) adds long-lived objects whose value changes because **time
passed**, not because a document was submitted. Assets reuse the existing `voucher`/`gl_entry` boundary and
the §10 command/event/projection infrastructure; they add **no** parallel ledger. All conventions at the top
of this document apply: `company_id` everywhere, RLS + `FORCE RLS`, money `numeric(19,4)`, quantity/rate
`numeric(21,9)`, percent `numeric(9,6)`, stable lower-case enum codes, append-only facts with
reversal/supersession, projections rebuildable.

Upstream derives cost, accumulated depreciation and state by subtracting mutable scalars. In S11 §8 that
leaves 3,000.00 in Fixed Assets and an offsetting 3,000.01 in Accumulated Depreciation: net book value and
gain/loss are right, but both balance-sheet accounts are overstated by the capitalised addition, which is
silently reclassified as depreciation. Every structure below exists to make that reclassification
unrepresentable — each amount is read from its own ledger, and every asset-role `gl_entry` leg carries
`asset_id` so the reconciliation is a real query.

```sql
asset(id, company_id, asset_no varchar(64), asset_name text, item_id, asset_category_id,
      acquisition_kind asset_acquisition_enum /*purchase|existing_opening|capitalisation|split|merge|transfer_in*/,
      cost_center_id, default_location_id, default_custodian_id,
      is_composite_component bool NOT NULL DEFAULT false,
      parent_asset_id bigint NULL,          -- component of a composite asset
      insurance_policy_no text NULL, insured_value numeric(19,4) NULL,
      created_at, created_by, updated_at, updated_by)
   UNIQUE (company_id, asset_no)
   CHECK (parent_asset_id IS NULL OR parent_asset_id <> id)
   -- exactly one identified unit per row: there is no asset_quantity column
   -- state, cost, book value, location and custodian are NOT columns here; see §19.4/§21.4/§22.1

asset_category(id, company_id, code, name, is_depreciable bool NOT NULL,
               enable_construction_in_progress bool NOT NULL DEFAULT true)
   UNIQUE (company_id, code)
asset_category_account(id, company_id, asset_category_id, target_company_id,
      fixed_asset_account_id, construction_in_progress_account_id,
      accumulated_depreciation_account_id, depreciation_expense_account_id,
      revaluation_reserve_account_id, impairment_expense_account_id,
      disposal_gain_loss_account_id, capital_reserve_account_id)
   UNIQUE (company_id, asset_category_id, target_company_id)
   -- L2 trigger proves each account's account_type and that its currency is the target company's
   -- default; resolution order (category row → company default) is recorded on the posted event,
   -- never re-derived at read time

asset_component(id, company_id, parent_asset_id, member_asset_id, added_at, removed_at NULL)
   UNIQUE (company_id, parent_asset_id, member_asset_id, added_at)
   CHECK (parent_asset_id <> member_asset_id)
   CHECK (removed_at IS NULL OR removed_at > added_at)
   -- deferred: a parent cannot be disposed while any member has removed_at IS NULL; a member's
   -- component_absorption disposal sets removed_at in the same transaction
```

### 19.1 Acquisition and bounded source allocation

```sql
asset_acquisition(id, company_id, asset_id, acquisition_no integer,
      acquisition_kind asset_acquisition_enum, acquired_on date,
      source_doc_type text NULL, source_doc_id bigint NULL, source_line_id bigint NULL,
      currency_id, exchange_rate numeric(21,9), amount numeric(19,4),
      command_receipt_id, reverses_acquisition_id bigint NULL, created_at, created_by)
   UNIQUE (company_id, asset_id, acquisition_no)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, reverses_acquisition_id) WHERE reverses_acquisition_id IS NOT NULL
   CHECK (amount >= 0)
   -- deferred trigger under the asset lock: exactly one unreversed acquisition_no = 1 row

asset_source_allocation(id, company_id, asset_id,
      source_kind asset_source_enum /*purchase_line|consumed_stock_move|consumed_asset|service_claim|opening*/,
      source_type text, source_id bigint, source_line_id bigint NULL,
      qty numeric(21,9) NULL, amount numeric(19,4) NOT NULL, ordinal integer,
      asset_acquisition_id bigint NULL, asset_service_event_id bigint NULL,
      command_receipt_id, reverses_allocation_id bigint NULL)
   UNIQUE (company_id, source_kind, source_type, source_id, source_line_id, asset_id, ordinal)
      NULLS NOT DISTINCT
   UNIQUE (company_id, reverses_allocation_id) WHERE reverses_allocation_id IS NOT NULL
   CHECK (amount >= 0 AND (qty IS NULL OR qty > 0))
   CHECK (source_kind <> 'purchase_line' OR qty IS NOT NULL)
   CHECK (num_nonnulls(asset_acquisition_id, asset_service_event_id) = 1)
   -- L2 trigger: the source line's item_id MUST equal asset.item_id for purchase_line and
   -- consumed_stock_move kinds. This is what structurally closes doc 41 §9 defect 1 (ERPNext never
   -- compares item code when resolving the link).
   -- deferred trigger, evaluated while the SOURCE line owner is locked:
   --   Σ unreversed qty    <= source line received/issued quantity
   --   Σ unreversed amount <= source line net amount (or GL residual for a service claim)
```

This replaces the entire ERPNext identity story: no matching on `base_net_amount`, no
quantity-only fallback, no unlocked `SUM(asset_quantity)` ceiling (doc 41 §3.1, S11 §3.1). Two concurrent
acquisitions against one purchase line serialise on that line's owner and the second is refused by the
residual constraint.

### 19.2 Cost as an event stream

```sql
asset_cost_event(id, company_id, asset_id, event_no integer,
      cost_kind asset_cost_enum /*acquisition|addition|improvement|landed_cost|repair_capitalisation|
                                 revaluation_up|revaluation_down|impairment|transformation_in|
                                 transformation_out|backdate_adjustment*/,
      effective_on date, amount numeric(19,4) NOT NULL,   -- SIGNED
      finance_book_id bigint NULL,                        -- NULL = applies to all books by policy
      asset_acquisition_id NULL, asset_service_event_id NULL, asset_revaluation_id NULL,
      asset_transformation_id NULL, voucher_id bigint NULL REFERENCES voucher(id),
      command_receipt_id, reverses_event_id bigint NULL, created_at, created_by)
   UNIQUE (company_id, asset_id, event_no)
   UNIQUE (company_id, reverses_event_id) WHERE reverses_event_id IS NOT NULL
   CHECK (amount <> 0)
   -- append-only: UPDATE/DELETE denied. Gross cost = Σ unreversed amount by kind class.

asset_recognition(id, company_id, asset_id, recognition_no integer,
      effective_on date, amount numeric(19,4) NOT NULL,
      construction_in_progress_account_id, fixed_asset_account_id,
      voucher_id bigint NOT NULL REFERENCES voucher(id),
      command_receipt_id, reverses_recognition_id bigint NULL)
   UNIQUE (company_id, asset_id, recognition_no)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, reverses_recognition_id) WHERE reverses_recognition_id IS NOT NULL
   CHECK (amount > 0)
   -- "at most one UNREVERSED recognition" is a deferred constraint trigger evaluated while the asset
   -- owner is locked, counting rows not referenced by any reverses_recognition_id. A partial unique
   -- index on `WHERE reverses_recognition_id IS NULL` would mean "one non-reversing row" and would
   -- permanently forbid re-recognition after a reversal.
```

`asset_recognition` replaces `booked_fixed_asset`, the four `frappe.db.exists` GL probes and the
`available_for_use_date = nowdate()` daily filter (doc 41 §3.2–§3.4). The recognition service selects
**`effective_on <= as_of AND no unreversed recognition`**, so a missed run self-heals and the partial
unique index makes a double run a no-op. Construction-in-progress residual is the view

```sql
CREATE VIEW asset_cip_residual AS
SELECT c.company_id, c.asset_id,
       SUM(c.amount) FILTER (WHERE c.reverses_event_id IS NULL) AS cost_incurred,
       COALESCE(r.recognised, 0) AS recognised,
       SUM(c.amount) FILTER (WHERE c.reverses_event_id IS NULL) - COALESCE(r.recognised, 0) AS residual
FROM asset_cost_event c
LEFT JOIN (SELECT company_id, asset_id, SUM(amount) AS recognised FROM asset_recognition
           WHERE reverses_recognition_id IS NULL GROUP BY 1,2) r USING (company_id, asset_id)
GROUP BY c.company_id, c.asset_id, r.recognised;
```

reconciled continuously against the construction-in-progress account rather than by a nightly repair.

### 19.3 Capitalisation of stock, assets and services

```sql
asset_capitalisation(id, company_id, doc_no, target_asset_id, posting_at timestamptz,
      target_account_id, total_value numeric(19,4), state doc_state_enum,
      voucher_id bigint REFERENCES voucher(id), command_receipt_id,
      reverses_capitalisation_id bigint NULL)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, command_receipt_id)
   CHECK (total_value >= 0)
asset_capitalisation_stock(id, company_id, asset_capitalisation_id, line_no integer,
      item_id, warehouse_id, owner_id, custodian_id, qty numeric(21,9),
      stock_move_id bigint NOT NULL)
   UNIQUE (company_id, asset_capitalisation_id, line_no)
   CHECK (qty > 0)
asset_capitalisation_stock_value(id, company_id, asset_capitalisation_stock_id,
      stock_value_event_id bigint NOT NULL, realised_value_delta numeric(19,4) NOT NULL,
      asset_cost_event_id bigint NOT NULL, command_receipt_id, child_ordinal integer)
   UNIQUE (company_id, asset_capitalisation_stock_id, stock_value_event_id)
   -- mirrors production_input_value (§14): consumed value is a one-to-one allocation of an authoritative
   -- stock_value_event, and deltas are SIGNED so a backdated replay appends an adjustment instead of
   -- mutating a frozen scalar. asset_cost_enum carries a `backdate_adjustment` member for the matching
   -- cost event and its linked adjustment voucher.
asset_capitalisation_asset(id, company_id, asset_capitalisation_id, line_no integer,
      consumed_asset_id, asset_disposal_id bigint NOT NULL, carrying_value numeric(19,4))
   UNIQUE (company_id, asset_capitalisation_id, line_no)
   UNIQUE (company_id, consumed_asset_id, asset_capitalisation_id)
asset_capitalisation_service(id, company_id, asset_capitalisation_id, line_no integer,
      item_id, source_type text NULL, source_line_id bigint NULL,
      expense_account_id, qty numeric(21,9), unit_rate numeric(21,9), amount numeric(19,4))
   UNIQUE (company_id, asset_capitalisation_id, line_no)
   CHECK (qty > 0 AND unit_rate >= 0 AND amount >= 0)
```

Consumed stock **must** carry a `stock_move_id` and a realised value: a missing valuation is an error, never
the silent zero of `raise_error_if_no_rate=False` (doc 41 §4.2). Consuming an asset requires a real
`asset_disposal` row (§22.4), so one exit path covers scrap, sale and capitalisation. The target's cost rises
only through `asset_cost_event`; there is no read-modify-write of `net_purchase_amount`
(doc 41 §4.4).

Deferred constraint:

```text
asset_capitalisation.total_value
  = Σ unreversed asset_capitalisation_stock_value.realised_value_delta
  + Σ consumed asset carrying_value
  + Σ service amount
  = Σ unreversed asset_cost_event.amount for this capitalisation
        (exact at numeric(19,4), evaluated through the valuation watermark so a backdated
         stock_value_event adjustment appends matching delta and cost-event rows)
```

### 19.4 Asset state is projected

```sql
-- Asset lifecycle and custody events are rows in the SHARED domain_event stream (§10), not a parallel
-- one: the fact transaction locks the asset's domain_aggregate_owner, takes next_event_position, inserts one
-- domain_event and exactly one transactional_outbox row referencing it, and projectors advance
-- projection_checkpoint(company_id, projector_code, aggregate_owner_id) contiguously. The tables below are
-- typed detail keyed 1:1 to that event, so nothing duplicates aggregate, position or payload.
-- domain_aggregate_enum, domain_event_enum, command_kind_enum and voucher_kind_enum all gain asset members:
-- recognition, depreciation, revaluation, capitalisation, transformation, disposal, custody, service.

asset_lifecycle_event(id, company_id, asset_id, domain_event_id bigint NOT NULL,
      event_code asset_lifecycle_enum /*created|recognised|in_service|under_maintenance|out_of_order|
                                       impaired|transformed|disposed|restored|cancelled*/,
      source_type text NULL, source_id bigint NULL, reason_code text NULL)
   UNIQUE (company_id, domain_event_id)
   FOREIGN KEY (company_id, domain_event_id) REFERENCES domain_event(company_id, id)
   -- append-only. Human-readable text is RENDERED from event_code + payload at read time;
   -- no translated sentence is ever stored as the event's identity (doc 41 §6).
```

`asset_state_projection(company_id, asset_id, state, as_of_event_id, computed_at, row_version)` is the only
place a current state lives, and only a projector writes it. No scheduled scan, repair document or
maintenance log may set it, which removes the defect where a saved draft repair suspends depreciation
(doc 43 §4.1, S11 §5.1).

---

## 20. Asset depreciation: policy, plans and postings

### 20.1 Policy revisions

```sql
asset_policy_revision(id, company_id, asset_id, finance_book_id, revision_no integer,
      method depreciation_method_enum /*straight_line|declining_balance|double_declining|
                                       units_of_production|manual*/,
      total_periods integer, frequency_months integer,
      salvage_value numeric(19,4), salvage_pct numeric(9,6) NULL,
      day_basis day_basis_enum /*period_count|actual_days_fiscal_year|actual_days_total*/,
      rate_pct numeric(9,6) NULL,                -- full precision, never rounded to 2
      shift_based bool NOT NULL DEFAULT false,
      in_service_on date, first_period_end date, life_extension_months integer NOT NULL DEFAULT 0,
      opening_accumulated numeric(19,4) NOT NULL DEFAULT 0,
      opening_periods_booked integer NOT NULL DEFAULT 0,
      effective_from date, effective_to date NULL, state revision_state_enum,
      approved_at NULL, approved_by NULL, supersedes_revision_id bigint NULL)
   UNIQUE (company_id, asset_id, finance_book_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, asset_id WITH =, finance_book_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
   CHECK (total_periods > 0 AND frequency_months > 0)
   CHECK (salvage_value >= 0 AND opening_accumulated >= 0)
   CHECK (opening_periods_booked >= 0 AND opening_periods_booked < total_periods)
   CHECK (rate_pct IS NULL OR (rate_pct > 0 AND rate_pct <= 100))
   CHECK (method <> 'declining_balance' AND method <> 'double_declining' OR rate_pct IS NOT NULL)
   CHECK (first_period_end >= in_service_on)
   CHECK (effective_to IS NULL OR effective_to > effective_from)
   -- L2 trigger: salvage_value < gross cost at approval; asset_category.is_depreciable is true

asset_shift_factor(id, company_id, shift_code varchar(32), name text) UNIQUE (company_id, shift_code)
asset_shift_factor_revision(id, company_id, asset_shift_factor_id, revision_no integer,
      factor numeric(21,9), effective_from date, effective_to date NULL, is_default bool,
      state revision_state_enum)
   UNIQUE (company_id, asset_shift_factor_id, revision_no)
   UNIQUE (company_id, is_default) WHERE is_default AND state = 'approved'
   CHECK (factor > 0)
```

Policy lives in an approved revision, not in editable `Asset Finance Book` columns (doc 41 §5.2). One
**default** shift factor is a partial unique index rather than a check-then-write probe (doc 42 §1), and
factors are identified by `shift_code` so no map is ever inverted by value (doc 43 §9, defect 23).

### 20.2 Plans

```sql
depreciation_plan(id, company_id, asset_id, finance_book_id, plan_version integer,
      asset_policy_revision_id, generated_at timestamptz, generator_version varchar(64),
      input_hash char(64), opening_book_value numeric(19,4), depreciable_base numeric(19,4),
      final_period_end date, state plan_state_enum /*draft|active|superseded|closed*/,
      supersedes_plan_id bigint NULL, note text NULL, command_receipt_id)
   UNIQUE (company_id, asset_id, finance_book_id, plan_version)
   UNIQUE (company_id, asset_id, finance_book_id) WHERE state = 'active'
   UNIQUE (company_id, command_receipt_id)
   CHECK (depreciable_base >= 0)

depreciation_plan_period(id, company_id, depreciation_plan_id, period_no integer,
      period_start date, period_end date, basis_days integer NULL,
      shift_code varchar(32) NULL, shift_factor_revision_id bigint NULL,
      planned_amount numeric(19,4) NOT NULL, planned_accumulated numeric(19,4) NOT NULL,
      is_residual_period bool NOT NULL DEFAULT false,
      zero_reason zero_amount_reason_enum NULL
         /*fully_depreciated|salvage_reached|shift_idle|suspended_by_policy|rounding*/)
   UNIQUE (company_id, depreciation_plan_id, period_no)
   UNIQUE (company_id, depreciation_plan_id, period_end)
   EXCLUDE USING gist (depreciation_plan_id WITH =,
      daterange(period_start, period_end, '[]') WITH &&)
   CHECK (period_end >= period_start)
   CHECK (planned_amount >= 0 AND planned_accumulated >= 0)
   CHECK (planned_amount > 0 OR zero_reason IS NOT NULL)
   CHECK (shift_code IS NULL OR shift_factor_revision_id IS NOT NULL)
```

Plan periods carry **no journal link**. A zero amount must state a reason and does **not** truncate the
plan (doc 42 §12, defects 4 and 10). The exclusion constraint makes overlapping periods impossible, and
`period_end` uniqueness makes the "one row per period" claim structural.

Deferred constraints per plan version:

```text
Σ planned_amount = depreciable_base                                        (exact, at generation)
max(planned_accumulated) + salvage_value = opening_book_value              (at generation)
exactly one period has is_residual_period = true when a residual exists
```

Both equalities are evaluated **at generation**, against the values frozen on the plan row. A later cost
event does not invalidate an existing plan version; by §22 it generates version `N+1`. Stating the second
equality against "future cost events" would be unevaluable, because a deferred constraint is checked at
commit and those events do not exist yet.

### 20.3 Periods, postings and attempts

```sql
depreciation_period(id, company_id, asset_id, finance_book_id,
      period_start date, period_end date, is_partial_to_disposal bool NOT NULL DEFAULT false)
   UNIQUE (company_id, asset_id, finance_book_id, period_end)
   EXCLUDE USING gist (company_id WITH =, asset_id WITH =, finance_book_id WITH =,
      daterange(period_start, period_end, '[]') WITH &&)
   CHECK (period_end >= period_start)
   -- the exclusion is what stops a partial-to-disposal period overlapping a full period

depreciation_posting(id, company_id, depreciation_period_id,
      satisfies_plan_id bigint NOT NULL, satisfies_period_no integer NOT NULL,
      amount numeric(19,4) NOT NULL, posting_date date NOT NULL,
      accumulated_depreciation_account_id, depreciation_expense_account_id,
      voucher_id bigint NOT NULL REFERENCES voucher(id),
      command_receipt_id, reverses_posting_id bigint NULL,
      reversal_dating reversal_dating_enum NULL /*original_period|reversal_date*/)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, reverses_posting_id) WHERE reverses_posting_id IS NOT NULL
   CHECK (amount > 0)
   CHECK ((reverses_posting_id IS NULL) = (reversal_dating IS NULL))
   -- A12's "at most one UNREVERSED posting per period" is a deferred constraint trigger evaluated
   -- while the (asset, finance_book) owner is locked, counting rows not referenced by any
   -- reverses_posting_id. It must NOT be a partial unique index on `WHERE reverses_posting_id IS NULL`:
   -- that reads as "one non-reversing row" and would make reverse-then-repost impossible.

depreciation_posting_attempt(id, company_id, depreciation_period_id, attempt_no integer,
      outcome depreciation_attempt_enum /*posted|failed|skipped_period_closed|skipped_not_due*/,
      error_code text NULL, error_detail jsonb NULL, occurred_at timestamptz, actor_id)
   UNIQUE (company_id, depreciation_period_id, attempt_no)
```

`UNIQUE … WHERE reverses_posting_id IS NULL` is the idempotency guarantee upstream lacks: a retried run
cannot double-post, and correction is a reversal row rather than clearing `journal_entry` on a submitted
child row with `update_modified=False` (doc 42 §9, §12 defect 20). `depreciation_posting_attempt` replaces
the single per-asset `depr_entry_posting_status` scalar (doc 42 §12, defect 18), and posting selection reads
**only** plan state, period dates and unposted state — never `asset_state_projection`.

### 20.4 Revaluation, impairment and book value

```sql
asset_revaluation(id, company_id, asset_id, finance_book_id NULL,
      revaluation_kind revaluation_enum /*revaluation_up|revaluation_down|impairment|reversal_of_impairment*/,
      effective_on date, previous_book_value numeric(19,4), new_book_value numeric(19,4),
      difference numeric(19,4) NOT NULL, adjust_salvage bool NOT NULL DEFAULT false,
      reserve_account_id NULL, expense_account_id NULL, reason_code text, reason text,
      authorised_by, voucher_id bigint NOT NULL REFERENCES voucher(id),
      command_receipt_id, reverses_revaluation_id bigint NULL)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, reverses_revaluation_id) WHERE reverses_revaluation_id IS NOT NULL
   CHECK (difference <> 0)
   CHECK (new_book_value >= 0 AND previous_book_value >= 0)
   CHECK (num_nonnulls(reserve_account_id, expense_account_id) >= 1)
```

Revaluation posts to **its own** reserve or impairment account, never to the fixed-asset account, so
accumulated depreciation is never inflated by a revaluation and disposal cannot silently reclassify it
(doc 42 §8, S11 §6.3). A zero difference is rejected by a check constraint instead of raising
`UnboundLocalError` (doc 42 §12, defect 26).

```sql
asset_book_value_projection(company_id, asset_id, finance_book_id, as_of_date,
      gross_cost numeric(19,4), accumulated_depreciation numeric(19,4),
      revaluation_reserve numeric(19,4), impairment numeric(19,4),
      net_book_value numeric(19,4), periods_posted integer, periods_remaining integer,
      active_plan_id bigint, computed_at, last_event_position bigint)
      -- last_event_position is a position in the SHARED domain_event stream for this asset's
      -- aggregate owner, so a rebuild replays exactly the same sequence
   PRIMARY KEY (company_id, asset_id, finance_book_id, as_of_date)
```

**The multi-book GL model, stated once.** Cost is debited to the fixed-asset account **once** and is
book-agnostic: `asset_cost_event.finance_book_id` is `NULL` for an ordinary addition, and each book's
depreciable base changes through the next `depreciation_plan` version, not through a per-book cost row.
Depreciation, by contrast, posts **per finance book**, so accumulated-depreciation legs always carry
`finance_book_id` and any balance-sheet read that does not filter on it is wrong for a multi-book asset.
This is the upstream behaviour recorded in doc 42 §5.2 (one journal per book, `finance_book` on the
journal); we keep it and make the book explicit on every leg.

Continuous deferred checks:

1. **per asset and book** — `Σ depreciation_posting.amount + Σ depreciation_attribution.amount`
   (unreversed) **=** accumulated depreciation in `gl_entry` for that category's accumulated-depreciation
   account, filtered on `asset_id` and `finance_book_id`;
2. **per asset** — `Σ asset_cost_event` cost-class amounts **=** `gl_entry` movement on the fixed-asset
   account for that `asset_id`, unfiltered by book;
3. `Σ asset_revaluation` **=** `gl_entry` movement on the reserve/impairment accounts;
4. `net_book_value >= salvage_value` for any asset with an unreversed active plan;
5. no `depreciation_posting` exists for a period beyond the active plan's `final_period_end`; and
6. `net_book_value = gross_cost − accumulated_depreciation + revaluation_reserve − impairment`, each term
   read from its **own** facts and never by subtraction from a mutable scalar; and
7. **no fact may be dated at or before an unreversed disposal's `effective_on`.** A deferred trigger under
   the asset lock refuses backdated `asset_cost_event`, `depreciation_posting`, `asset_revaluation` and
   `asset_custody_event` rows while an unreversed disposal exists, so a correction must reverse the disposal
   first — the order §22 already prescribes. Without this rule the zero-balance assertion in §21.4 can be
   broken after the fact by an insert nothing else forbids.

---

## 21. Asset custody, service, transformation and disposal

### 21.1 Custody and place

```sql
asset_location(id, company_id, code, name, parent_id bigint NULL, is_group bool)
   UNIQUE (company_id, code)
asset_location_geometry_revision(id, company_id, asset_location_id, revision_no integer,
      geometry jsonb, computed_area numeric(21,9), state revision_state_enum, created_at)
   UNIQUE (company_id, asset_location_id, revision_no)
   -- hierarchy is parent_id + recursive CTE; aggregate area is a PROJECTION recomputed from
   -- immutable geometry revisions, never an incrementally patched scalar (doc 41 §6)

asset_custody_event(id, company_id, asset_id, domain_event_id bigint NOT NULL,
      event_kind custody_event_enum /*receipt|issue|transfer|return|transfer_out*/,
      effective_at timestamptz,
      from_location_id NULL, to_location_id NULL,
      from_custodian_id NULL, to_custodian_id NULL,
      reason_code text NULL, source_type text NULL, source_id bigint NULL,
      authorised_by, command_receipt_id, reverses_event_id bigint NULL)
   UNIQUE (company_id, domain_event_id)
   UNIQUE (company_id, command_receipt_id)
   FOREIGN KEY (company_id, domain_event_id) REFERENCES domain_event(company_id, id)
   CHECK (num_nonnulls(to_location_id, to_custodian_id) > 0)
   CHECK (to_location_id IS NULL OR from_location_id IS NULL OR to_location_id <> from_location_id)
   CHECK (to_custodian_id IS NULL OR from_custodian_id IS NULL OR to_custodian_id <> from_custodian_id)
   -- L2 trigger while the asset is locked: from_* must equal the to_* of the latest UNREVERSED
   -- asset_custody_event (chain continuity), and effective_at must not precede it. Continuity is checked
   -- against the event chain, never against asset_custody_projection -- a projection cannot authorise
   -- (doc 44 §7). An event must CHANGE at least one dimension, not merely mention one.
```

Source dimensions are **stored**, not inferred from the asset's current values, so a custody chain is
verifiable end to end. `asset_custody_projection(company_id, asset_id, location_id, custodian_id,
as_of_event_id, computed_at)` is projector-only; a movement that omits a dimension leaves that dimension
explicitly unchanged rather than accidentally stale (doc 43 §9, defect 2).

### 21.2 Maintenance

```sql
maintenance_plan_revision(id, company_id, asset_id, revision_no integer,
      team_id NULL, effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, asset_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, asset_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
maintenance_task_revision(id, company_id, maintenance_plan_revision_id, task_key uuid,
      description text, maintenance_kind maintenance_kind_enum /*preventive|corrective|calibration|inspection*/,
      recurrence_rule jsonb, assignee_role_id NULL, requires_certificate bool)
   UNIQUE (company_id, maintenance_plan_revision_id, task_key)
maintenance_occurrence(id, company_id, maintenance_task_revision_id, occurrence_no integer,
      due_date date, state occurrence_state_enum /*planned|completed|cancelled*/,
      completed_on date NULL, actor_id NULL, evidence_ref text NULL,
      command_receipt_id, reverses_occurrence_id bigint NULL)
   UNIQUE (company_id, maintenance_task_revision_id, occurrence_no)
   UNIQUE (company_id, maintenance_task_revision_id, due_date)
      WHERE state <> 'cancelled' AND reverses_occurrence_id IS NULL
   CHECK ((state = 'completed') = (completed_on IS NOT NULL))
   -- the partial predicate lets a cancelled occurrence be re-planned for the same due date
```

`overdue` is a **view** (`due_date < current_date AND state = 'planned'`), not a stored value maintained by a
daily bulk `UPDATE` (doc 43 §9, defect 11). Completing an occurrence inserts the next one under
`(task_revision, occurrence_no)`, so retries are idempotent; an occurrence never saves its plan, which
breaks the log⇄plan write cycle (doc 43 §3.3). Recurrence terminates on **dates only**, fixing
`calculate_next_due_date` returning empty for every task with an end date (doc 43 §9, defect 6).

### 21.3 Repair and improvement

```sql
asset_service_event(id, company_id, asset_id, service_no integer,
      service_kind service_kind_enum /*repair|improvement|inspection|calibration*/,
      failed_at timestamptz NULL, completed_at timestamptz NULL,
      downtime_minutes integer NULL, actions text, capitalise bool NOT NULL DEFAULT false,
      state service_state_enum /*pending|in_progress|completed|cancelled*/,
      command_receipt_id, reverses_service_id bigint NULL)
   UNIQUE (company_id, asset_id, service_no)
   UNIQUE (company_id, command_receipt_id)
   CHECK (completed_at IS NULL OR failed_at IS NULL OR completed_at >= failed_at)
   CHECK (downtime_minutes IS NULL OR downtime_minutes >= 0)

asset_service_cost_allocation(id, company_id, asset_service_event_id,
      source_kind service_cost_source_enum /*purchase_invoice_line|stock_issue_move|internal_labour*/,
      source_type text, source_id bigint, expense_account_id,
      amount numeric(19,4) NOT NULL, is_capitalised bool NOT NULL, ordinal integer,
      command_receipt_id, reverses_allocation_id bigint NULL)
   UNIQUE (company_id, source_kind, source_type, source_id, asset_service_event_id, ordinal)
   CHECK (amount > 0)
   -- deferred trigger while the SOURCE owner is locked:
   --   Σ unreversed amount across ALL service events <= source residual
   --   (GL movement on that account for that invoice, or the issued move's realised value)

asset_service_book_effect(id, company_id, asset_service_cost_allocation_id,
      finance_book_id, depreciable_base_delta numeric(19,4) NOT NULL,
      resulting_plan_id bigint NOT NULL)
   UNIQUE (company_id, asset_service_cost_allocation_id, finance_book_id)
   -- NOT a split of the cost. One book-agnostic asset_cost_event carries the whole addition and GL is
   -- debited once; each book's depreciable base rises by the FULL amount, because each book is an
   -- independent measurement of the same asset. Splitting 3,000 into 1,500 + 1,500 would make both books
   -- understate cost and future depreciation.

asset_life_extension(id, company_id, asset_service_event_id, finance_book_id,
      months_added integer NOT NULL, resulting_policy_revision_id bigint NOT NULL)
   UNIQUE (company_id, asset_service_event_id, finance_book_id)
   CHECK (months_added <> 0)
```

The residual check is upstream's one good idea (doc 43 §4.1) — kept, but enforced under a source lock.
`asset_service_book_apportionment` is what stops the same repair cost being added in full to **every**
finance book (doc 43 §9, defects 16–17), and life extension produces a **new policy revision** instead of
incrementing a mutable counter. Reversing a service event reverses every fact it created, **including the
inventory issue**, or is refused — closing the gap where cancelling a repair left consumed spares issued
(doc 43 §9, defect 19).

### 21.4 Transformation and disposal

```sql
asset_transformation(id, company_id, transformation_no integer,
      transformation_kind transformation_enum /*split|merge*/,
      effective_on date, reason_code text, authorised_by,
      command_receipt_id, reverses_transformation_id bigint NULL)
   UNIQUE (company_id, transformation_no)
   UNIQUE (company_id, command_receipt_id)
asset_transformation_part(id, company_id, asset_transformation_id,
      part_role transformation_role_enum /*source|target*/, asset_id,
      finance_book_id NULL, apportioned_cost numeric(19,4),
      apportioned_accumulated numeric(19,4), apportioned_revaluation numeric(19,4),
      apportioned_remaining_periods integer NULL, is_residual_part bool NOT NULL DEFAULT false)
   UNIQUE (company_id, asset_transformation_id, part_role, asset_id, finance_book_id)
      NULLS NOT DISTINCT
   CHECK (apportioned_cost >= 0 AND apportioned_accumulated >= 0)
   -- deferred, per finance book, BOTH directions:
   --   Σ source apportioned_cost        = Σ target apportioned_cost
   --   Σ source apportioned_accumulated = Σ target apportioned_accumulated
   --   Σ source apportioned_revaluation = Σ target apportioned_revaluation
   --   exactly one target part carries is_residual_part when a rounding residual exists
   -- AND source-side agreement with the source asset's actual facts as of effective_on:
   --   Σ source apportioned_cost        = Σ asset_cost_event(source, cost classes)
   --   Σ source apportioned_accumulated = Σ depreciation_posting(source) + Σ depreciation_attribution
   --   Σ source apportioned_revaluation = Σ asset_revaluation(source)
   -- Internal conservation alone would let a transformation apportion the wrong total and still pass.

asset_disposal(id, company_id, asset_id, disposal_no integer,
      disposal_kind disposal_enum /*scrap|sale|capitalisation|transfer_out|write_off|component_absorption*/,
      effective_on date, proceeds numeric(19,4) NOT NULL DEFAULT 0,
      source_doc_type text NULL, source_doc_id bigint NULL, source_line_id bigint NULL,
      cost_removed numeric(19,4) NOT NULL, accumulated_removed numeric(19,4) NOT NULL,
      revaluation_released numeric(19,4) NOT NULL DEFAULT 0,
      gain_loss numeric(19,4) NOT NULL, disposal_account_id,
      voucher_id bigint NOT NULL REFERENCES voucher(id),
      command_receipt_id, reverses_disposal_id bigint NULL)
   UNIQUE (company_id, asset_id, disposal_no)
   UNIQUE (company_id, command_receipt_id)
   UNIQUE (company_id, reverses_disposal_id) WHERE reverses_disposal_id IS NOT NULL
   CHECK (proceeds >= 0 AND cost_removed >= 0 AND accumulated_removed >= 0)
   CHECK (voucher_id IS NOT NULL OR disposal_kind = 'component_absorption')
   -- A23's "exactly one unreversed disposal" is a deferred trigger under the asset lock counting rows
   -- not referenced by any reverses_disposal_id -- NOT a partial unique index, which would forbid
   -- re-disposal after a reversed sale (the flow S11 §9 step 2 walks through).

asset_disposal_book(id, company_id, asset_disposal_id, finance_book_id,
      accumulated_removed numeric(19,4) NOT NULL, revaluation_released numeric(19,4) NOT NULL DEFAULT 0,
      transformation_attributed numeric(19,4) NOT NULL DEFAULT 0,
      gain_loss numeric(19,4) NOT NULL)
   UNIQUE (company_id, asset_disposal_id, finance_book_id)
   -- deferred: per book, accumulated_removed = Σ depreciation_posting + Σ depreciation_attribution,
   -- revaluation_released = Σ asset_revaluation, and the parent's totals = Σ over books

depreciation_attribution(id, company_id, asset_transformation_part_id, asset_id, finance_book_id,
      amount numeric(19,4) NOT NULL,      -- SIGNED: negative on the source, positive on the target
      voucher_id bigint NOT NULL REFERENCES voucher(id),
      command_receipt_id, reverses_attribution_id bigint NULL)
   UNIQUE (company_id, asset_transformation_part_id, finance_book_id)
   CHECK (amount <> 0)
   -- Without this, a split target's Σ depreciation_posting is zero while GL holds its share of
   -- accumulated depreciation, and its disposal cannot zero the account. ERPNext does conserve this
   -- (doc 43 §5: adjust_account_balance reduces the source leg by what add_new_entries adds), so
   -- omitting it would be a regression, not a simplification.
```

`accumulated_removed` at disposal is therefore
`Σ depreciation_posting + Σ depreciation_attribution` per book, and §20.4 check 1 compares that same sum to
GL. Every asset-role GL leg carries `asset_id` and, where book-scoped, `finance_book_id` (§3), which is what
makes both sides of the comparison expressible.

Splitting is an authorised transformation with **stored apportionment**, so no posted depreciation journal
is ever amended (doc 43 §5, S11 §6.1) and float scaling with no residual rule is impossible.
`UNIQUE (company_id, asset_id) WHERE reverses_disposal_id IS NULL` gives the single-disposal guarantee
upstream lacks entirely (doc 43 §9, defect 31).

The disposal voucher is built from facts, which is the fix for S11's stranded balances:

```text
cost_removed        = Σ asset_cost_event cost-class amounts (unreversed)
accumulated_removed = Σ depreciation_posting.amount         (unreversed)
revaluation_released= Σ asset_revaluation                   (unreversed)
gain_loss           = proceeds − (cost_removed − accumulated_removed + revaluation_released)
```

Deferred trigger: the disposal voucher's inventory/fixed-asset and accumulated-depreciation legs must equal
those four sums exactly, and the fixed-asset and accumulated-depreciation balances for that asset must reach
**zero** after the disposal commits.

---

## 22. Asset write and reversal order

**Acquisition:** claim idempotency → guard company/period/asset lifecycle → lock source purchase line,
consumed stock streams and consumed asset owners in sorted order → validate residual quantity and amount →
insert asset identity (first acquisition only) and immutable `asset_acquisition` → insert
`asset_source_allocation` and `asset_cost_event` rows → insert consumed `stock_move` rows and project
valuation → insert `voucher` + `gl_entry` → insert `asset_lifecycle_event` and outbox → commit → project
register and construction-in-progress residual.

**Recognition:** claim idempotency → lock asset → verify unrecognised cost from `asset_cip_residual` →
insert `asset_recognition` + balanced voucher → event/outbox → commit → project.

**Depreciation run,** per due period: select `plan.state = 'active' AND period_end <= as_of AND no
unreversed posting` → claim idempotency `(asset, book, period_start)` → lock the asset/book owner →
re-evaluate period control **for that posting date** → insert `depreciation_posting` + balanced voucher →
insert attempt outcome → outbox → commit. A failure inserts a `failed` attempt in its own transaction and
the run continues.

**Replanning** (revaluation, service cost, life change, shift change, transformation, disposal): claim
idempotency → lock the asset/book owner → insert the triggering fact and its voucher → generate plan
version `N+1` from the approved policy revision and current book value → mark version `N` `superseded` →
insert `N+1` as `active` → outbox → commit → project. **Posted periods are never copied into the new plan**;
they are facts the new plan simply does not re-plan, which removes cancel-and-copy entirely.

**Custody:** claim idempotency → lock asset → validate chain continuity and dates → insert
`asset_custody_event` → outbox → commit → project location and custodian.

**Disposal:** claim idempotency → lock asset → require no unreversed disposal → post the final partial
period as an ordinary `depreciation_period` fact → insert `asset_disposal` → insert voucher from the four
fact sums → mark the active plan `closed` → outbox → commit → project state and register.

**Reversal**, in strict dependency order: disposal → transformation targets before source → capitalised
service cost before its inventory issue → depreciation postings (dating policy recorded on the reversal) →
recognition → acquisition. Each step appends a compensating fact with its own idempotency key; nothing is
updated, deleted, unlinked or amended.

---

## 23. Asset invariant register

The exact **A1–A26** names and their primary enforcement layers are consolidated in
[`docs/logic/44`](../logic/44-tranche-c-closure-and-our-asset-spec.md#3-a1a26-exact-register-and-enforcement-owner).
They extend the registers in §9 and §18. Structurally:

- **A1/A8** — identity conservation is `asset_source_allocation` bounded by a deferred residual trigger
  under a source-line lock; there is no `asset_quantity` and no amount matching;
- **A2/A7/A24** — every state answer is a projection over `asset_lifecycle_event`,
  `asset_cost_event`, `depreciation_posting`, `asset_custody_event` and `asset_disposal`;
- **A3** — recognition is one unique unreversed row selected by `effective_on <= as_of`, so it is
  self-healing and retry-safe;
- **A4/A21** — additions are `asset_cost_event` rows with per-book apportionment, never scalar rewrites;
- **A5/A11** — policy is an approved non-overlapping revision and plans are immutable versions whose
  periods sum exactly to the depreciable base;
- **A12** — a deferred unreversed-count trigger on `depreciation_period`, evaluated under the asset/book
  lock, is the one-posting-per-period guarantee, with durable per-period attempt outcomes;
- **A13** — shift plans are `shift_code` + factor revisions, conserved by the plan-total constraint;
- **A14/A25** — revaluation, impairment, cost and accumulated depreciation each reconcile to their **own**
  GL accounts, so disposal never reclassifies one as another;
- **A19** — custody events store `from_*` and `to_*` and are chain-continuity checked;
- **A22** — splitting is `asset_transformation` with exact stored apportionment plus a
  `depreciation_attribution` fact per part, so GL attribution follows the apportionment and posted journals
  stay immutable;
- **A23** — a deferred unreversed-count trigger per asset is the single-disposal guarantee; the disposal
  voucher is derived from the fact sums including `depreciation_attribution`, per finance book; and
- **A26** — acquisition, recognition, posting, service allocation, transformation and disposal are all
  bounded writes under deterministic asset (and source) locks with idempotency keys.

Every A invariant requires a schema refusal test; allocation, locking and idempotency invariants
additionally require concurrent interleaving and retry tests.
[S11](../scenarios/S11-asset-lifecycle.md) is the end-to-end acceptance fixture, and its acceptance
criterion is explicit: **after disposal the fixed-asset, per-book accumulated-depreciation and
revaluation-reserve balances for that asset are exactly zero** — so the equal-and-opposite overstatement
upstream leaves behind is unrepresentable, and so is the split-rounding cent.

---

## 24. Jurisdiction, registration and classification

Tranche F ([docs 45–48](../logic/45-gst-registration-settings-hsn-and-tax-structure.md)) adds localisation.
The driving constraint: **India GST is not in ERPNext** — it was removed in v14
(`patches/v14_0/remove_india_localisation.py:5-21`) and lives in a separate app that attaches itself through
`doc_events` overrides and **custom fields toggled by settings checkboxes**. We reject that mechanism and
ERPNext's `@allow_regional` function replacement (doc 21 §4, doc 42 §4.3) in favour of jurisdiction as data.

All conventions at the top of this document apply. Money `numeric(19,4)`; rates and percentages
`numeric(9,6)`; `company_id` everywhere with RLS and `FORCE RLS`; stable lower-case enum codes; append-only
facts with reversal/supersession.

```sql
tax_jurisdiction(id, code varchar(8), name text)  UNIQUE (code)   -- 'in', 'ae', 'gb'
tax_jurisdiction_revision(id, company_id, tax_jurisdiction_id, revision_no integer,
    effective_from date, effective_to date NULL, state revision_state_enum,
    requires_e_invoice bool, requires_e_waybill bool, supports_reverse_charge bool,
    supports_composition bool, classification_scheme_id bigint,
    approved_at NULL, approved_by NULL, supersedes_revision_id bigint NULL)
   UNIQUE (company_id, tax_jurisdiction_id, revision_no)
   EXCLUDE USING gist (company_id WITH =, tax_jurisdiction_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')

tax_area(id, company_id, tax_jurisdiction_id, area_code varchar(8), name text,
    is_outside_jurisdiction bool NOT NULL DEFAULT false)
   UNIQUE (company_id, tax_jurisdiction_id, area_code)
   -- Indian states by GST state number; '96' becomes is_outside_jurisdiction, not a magic literal
tax_area_postal_range(id, company_id, tax_area_id, range_start integer, range_end integer)
   CHECK (range_end >= range_start)
   -- an unmapped area is a REFUSAL, never a silent pass (doc 45 §3.2)

tax_registration(id, company_id, party_id NULL, owning_company_id NULL,
    tax_jurisdiction_id, registration_no varchar(32),
    registration_category registration_category_enum, tax_area_id,
    secondary_id varchar(32) NULL,            -- PAN or equivalent
    valid_from date, valid_to date NULL)
   UNIQUE (company_id, tax_jurisdiction_id, registration_no)
   CHECK (num_nonnulls(party_id, owning_company_id) = 1)
   -- L2 trigger: registration_no matches the format for its category on the jurisdiction revision,
   -- and its check digit validates; a transporter-style identifier is a separate typed row, not an
   -- exemption inside this one (doc 45 §3.2)

tax_registration_snapshot(id, company_id, source_doc_type text, source_doc_id bigint,
    party_role party_role_enum /*supplier|customer|company|transporter*/,
    registration_no varchar(32), registration_category registration_category_enum,
    tax_area_id, status registration_status_enum, registered_on date NULL,
    cancelled_on date NULL, source snapshot_source_enum /*api|manual|derived*/,
    retrieved_at timestamptz NOT NULL, fetch_attempt_id bigint NULL)
   UNIQUE (company_id, source_doc_type, source_doc_id, party_role)
   -- IMMUTABLE. This is what makes doc 45 §3.3's async, log-only validation impossible: the write
   -- blocks until a snapshot within the policy window exists, and a later portal refresh cannot
   -- retroactively invalidate a posted document.

classification_scheme(id, company_id, code, name, allowed_lengths integer[],
    service_prefix varchar(4) NULL)
   UNIQUE (company_id, code)          -- HSN lengths {4,6,8} and prefix '99' are DATA (doc 45 §6)
classification_code_revision(id, company_id, classification_scheme_id, code varchar(16),
    revision_no integer, description text, effective_from date, effective_to date NULL,
    state revision_state_enum)
   UNIQUE (company_id, classification_scheme_id, code, revision_no)
item_classification(id, company_id, item_id, classification_code_revision_id,
    effective_from date, effective_to date NULL)
   UNIQUE (company_id, item_id, classification_scheme_id, effective_from)
   -- items REFERENCE a classification revision; rates are never bulk-pushed into item masters

tax_component(id, company_id, tax_jurisdiction_id, component_code varchar(24),
    component_role component_role_enum /*output|input|reverse_charge|refund*/,
    sign_policy sign_policy_enum /*positive|negative*/, is_quantity_based bool)
   UNIQUE (company_id, tax_jurisdiction_id, component_code, component_role)
tax_component_account(id, company_id, tax_component_id, account_id)
   UNIQUE (company_id, tax_component_id)
   UNIQUE (company_id, account_id)     -- one account cannot serve two component roles (doc 45 §5)

tax_treatment(id, company_id, tax_jurisdiction_id, code treatment_enum
    /*taxable|zero_rated|nil_rated|exempted|non_gst*/, allows_nonzero_rate bool,
    reporting_category text)
   UNIQUE (company_id, tax_jurisdiction_id, code)
tax_rate_revision(id, company_id, tax_jurisdiction_id, classification_code_revision_id,
    supply_type supply_type_enum, headline_rate numeric(9,6), tax_treatment_id,
    revision_no integer, effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, classification_code_revision_id, supply_type, revision_no)
   EXCLUDE USING gist (company_id WITH =, classification_code_revision_id WITH =,
      supply_type WITH =, daterange(effective_from, effective_to, '[)') WITH &&)
      WHERE (state = 'approved')
   CHECK (headline_rate >= 0)
tax_rate_component(id, company_id, tax_rate_revision_id, tax_component_id,
    rate numeric(9,6) NOT NULL)
   UNIQUE (company_id, tax_rate_revision_id, tax_component_id)
   -- deferred: Σ rate = headline_rate EXACTLY per supply type. This generalises the
   -- `gst_rate == tax_rate × 2` intra-state rule (doc 45 §5.1) from a validation message to a
   -- constraint, and supports three-way or quantity-based splits without new code.
```

---

## 25. Determination and blocked credit

```sql
tax_determination(id, company_id, source_doc_type text, source_doc_id bigint,
    tax_jurisdiction_revision_id, engine_version varchar(64), determined_at timestamptz,
    supply_type supply_type_enum,
    liability_direction liability_direction_enum /*forward|reverse|refund|zero_rated*/,
    place_of_supply_area_id bigint NOT NULL,
    place_of_supply_basis pos_basis_enum /*party_registration|shipping_address|
                                          company_registration|explicit_override|statutory_default*/,
    source_area_id bigint NOT NULL, source_basis pos_basis_enum,
    supplier_registration_snapshot_id, customer_registration_snapshot_id,
    money_precision smallint NOT NULL,
    command_receipt_id, reverses_determination_id bigint NULL)
   UNIQUE (company_id, source_doc_type, source_doc_id) WHERE reverses_determination_id IS NULL
   -- place of supply is an AREA FK, never a "NN-State Name" label whose first two characters are
   -- statutory (doc 46 §2.1). Absence of a place of supply is a refusal, not intra-state.

tax_determination_line(id, company_id, tax_determination_id, source_line_id bigint,
    classification_code_revision_id, tax_rate_revision_id, tax_treatment_id,
    taxable_amount numeric(19,4), ordinal integer)
   UNIQUE (company_id, tax_determination_id, source_line_id)
   CHECK (taxable_amount >= 0)

tax_determination_component(id, company_id, tax_determination_line_id, tax_component_id,
    component_role component_role_enum, rate numeric(9,6), amount numeric(19,4),
    account_id, is_residual bool NOT NULL DEFAULT false)
   UNIQUE (company_id, tax_determination_line_id, tax_component_id, component_role)
   -- deferred triggers:
   --   the component is in the applicable set for (jurisdiction, supply_type, direction, role)
   --   Σ amount per line = round(taxable_amount × Σ rate) with exactly ONE residual component
   --   Σ amount per component across lines = the document's component total, EXACTLY
   --   forward and reverse amounts cancel EXACTLY at determination.money_precision
   --      (never at a hard-coded 2 — doc 46 §4.1)

tax_credit_block(id, company_id, tax_determination_line_id, tax_component_id,
    reason_code credit_block_reason_enum /*place_of_supply|blocked_category|personal_use|
                                          exempt_output|composition|statutory_list*/,
    destination credit_destination_enum /*inventory_valuation|asset_cost|named_expense*/,
    amount numeric(19,4), stock_move_id NULL, asset_cost_event_id NULL,
    expense_account_id NULL, voucher_id bigint NOT NULL REFERENCES voucher(id))
   UNIQUE (company_id, tax_determination_line_id, tax_component_id)
   CHECK (num_nonnulls(stock_move_id, asset_cost_event_id, expense_account_id) = 1)
   -- blocked credit reaches inventory and asset cost through ordinary stock_move value components
   -- and asset_cost_event rows (§19.2) — never by patching a valuation rate in place (doc 46 §5)
```

`gl_entry` already carries `asset_id`/`finance_book_id` (§3); determination adds no columns to it. Component
amounts post through the existing `voucher`/`gl_entry` boundary with `source_line_type`/`source_line_id`
pointing at `tax_determination_component`.

---

## 26. Statutory artefacts and external submission

```sql
statutory_artefact(id, company_id, artefact_type statutory_artefact_enum
        /*e_invoice|e_waybill|e_invoice_cancellation|import_declaration|return_filing*/,
    tax_jurisdiction_revision_id, tax_registration_id,
    source_doc_type text, source_doc_id bigint, tax_determination_id bigint NULL,
    generation_no integer NOT NULL DEFAULT 1, obligation_basis text NOT NULL,
    authority_identifier varchar(128) NULL, issued_at timestamptz NULL,
    valid_until timestamptz NULL,
    evidence_class evidence_class_enum /*authority_confirmed|manually_asserted*/,
    signed_payload text NULL, signature_verified bool NULL, signing_cert_id bigint NULL,
    state artefact_state_enum /*required|pending|issued|cancelled|expired|not_applicable|failed*/,
    command_receipt_id)
   UNIQUE (company_id, artefact_type, authority_identifier)
      WHERE authority_identifier IS NOT NULL
   UNIQUE (company_id, artefact_type, source_doc_type, source_doc_id, generation_no)
   CHECK ((state = 'issued') = (authority_identifier IS NOT NULL))
   CHECK (evidence_class <> 'authority_confirmed' OR signature_verified IS TRUE)
   -- authority_identifier is NEVER blanked (doc 47 §4.2); regeneration inserts generation_no + 1.
   -- The signature check makes jwt.decode(..., verify_signature=False) structurally unavailable.

statutory_artefact_event(id, company_id, statutory_artefact_id, event_no integer,
    event_type artefact_event_enum /*requested|issued|vehicle_updated|transporter_updated|
                                    validity_extended|cancelled|expired|rejected*/,
    authority_timestamp timestamptz NULL, local_timestamp timestamptz NOT NULL,
    timestamp_source timestamp_source_enum /*authority|local_fallback*/,
    reason_code text NULL, payload jsonb, domain_event_id bigint NOT NULL)
   UNIQUE (company_id, statutory_artefact_id, event_no)
   CHECK ((timestamp_source = 'authority') = (authority_timestamp IS NOT NULL))

statutory_submission_attempt(id, company_id, statutory_artefact_id, attempt_no integer,
    endpoint text, request_hash char(64), request_payload jsonb,
    response_code text NULL, response_payload jsonb NULL,
    outcome attempt_outcome_enum /*issued|duplicate_reconciled|rejected|transport_error|
                                  timeout_unknown|refused_locally*/,
    started_at timestamptz, completed_at timestamptz NULL,
    idempotency_key varchar(128) NOT NULL, command_receipt_id)
   UNIQUE (company_id, statutory_artefact_id, attempt_no)
   UNIQUE (company_id, idempotency_key)
   -- inserted BEFORE the call. `timeout_unknown` is first-class: the next action is RECONCILE,
   -- never blind resubmission.

statutory_submission_work(id, company_id, statutory_artefact_id,
    state work_state_enum /*queued|running|retryable|failed|completed|cancelled*/,
    attempts integer NOT NULL DEFAULT 0, next_attempt_at timestamptz,
    lease_owner text NULL, lease_until timestamptz NULL, terminal_reason text NULL)
   UNIQUE (company_id, statutory_artefact_id) WHERE state IN ('queued','running','retryable')
   -- replaces an `Auto-Retry` status string as the queue, and a Single flag cleared before the work

statutory_cancellation_window(id, company_id, tax_jurisdiction_revision_id, artefact_type,
    window_hours integer NOT NULL, basis window_basis_enum /*authority_issue_time|posting_date*/)
   UNIQUE (company_id, tax_jurisdiction_revision_id, artefact_type)
   -- the 24-hour IRN rule is a jurisdiction rule evaluated against the stored authority issued_at,
   -- never a literal `days=1` read from an onload cache (doc 47 §4.1)
```

---

## 27. Return periods, reconciliation and imports

```sql
return_period(id, company_id, tax_registration_id, return_type text,
    period_start date, period_end date, frequency return_frequency_enum, due_on date,
    state return_period_state_enum /*open|working|ready|filed|revised*/)
   UNIQUE (company_id, tax_registration_id, return_type, period_start)
   EXCLUDE USING gist (company_id WITH =, tax_registration_id WITH =, return_type WITH =,
      daterange(period_start, period_end, '[]') WITH &&)
   -- posting, amending or reversing inside a `filed` period is refused by the SAME period-control
   -- trigger family as accounting periods (§2), evaluated per posting date and registration

return_format_revision(id, company_id, return_type, revision_no integer,
    schema_definition jsonb NOT NULL, output_precision smallint NOT NULL,
    effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, return_type, revision_no)
   -- the statutory shape is a versioned row, not a JSON file on disk (doc 48 §2)

return_working_set(id, company_id, return_period_id, version integer,
    source_watermark bigint NOT NULL, content_hash char(64) NOT NULL,
    return_format_revision_id bigint NOT NULL, built_at timestamptz,
    generator_version varchar(64), command_receipt_id)
   UNIQUE (company_id, return_period_id, version)
   -- immutable; rebuilding appends a version. Staleness is detected by comparing the watermark,
   -- never asserted by an `is_latest_data` boolean (doc 48 §1.2)
return_working_set_line(id, company_id, return_working_set_id,
    statutory_category text, statutory_subcategory text, natural_key text,
    source_doc_type text, source_doc_id bigint, tax_determination_id bigint,
    taxable_value numeric(19,4), component_amounts jsonb)
   UNIQUE (company_id, return_working_set_id, statutory_subcategory, natural_key)

authority_dataset(id, company_id, tax_registration_id, dataset_type text,
    period_start date, period_end date, retrieved_at timestamptz,
    payload_hash char(64), source authority_source_enum /*api|upload*/,
    statutory_submission_attempt_id bigint NOT NULL)
   UNIQUE (company_id, tax_registration_id, dataset_type, period_start, payload_hash)

match_policy_revision(id, company_id, tax_jurisdiction_revision_id, dataset_type text,
    revision_no integer, effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, tax_jurisdiction_revision_id, dataset_type, revision_no)
match_policy_tier(id, company_id, match_policy_revision_id, tier_no integer,
    resulting_finding finding_enum)
   UNIQUE (company_id, match_policy_revision_id, tier_no)
match_policy_field(id, company_id, match_policy_tier_id, field_code text,
    comparison comparison_mode_enum /*exact|fuzzy|rounding|ignored*/,
    tolerance numeric(19,4) NULL, fuzzy_threshold numeric(9,6) NULL)
   UNIQUE (company_id, match_policy_tier_id, field_code)
   -- promotes doc 48 §3's declarative rule ladder from a Python tuple to versioned data, so a filed
   -- reconciliation can name the policy that produced it and tolerance changes need no deploy

reconciliation_run(id, company_id, return_period_id, return_working_set_id,
    authority_dataset_id, match_policy_revision_id, comparison_precision smallint NOT NULL,
    run_at timestamptz, command_receipt_id)
   UNIQUE (company_id, command_receipt_id)
reconciliation_finding(id, company_id, reconciliation_run_id,
    statutory_subcategory text, natural_key text,
    finding finding_enum /*matched|mismatch|missing_in_books|missing_at_authority|
                          suggested|residual|manual*/,
    match_tier integer NULL, differing_fields text[] NULL,
    books_payload jsonb, authority_payload jsonb, signed_difference jsonb,
    books_source_doc_type text NULL, books_source_doc_id bigint NULL,
    authority_row_id bigint NULL)
   UNIQUE (company_id, reconciliation_run_id, statutory_subcategory, natural_key)
   -- keeps upstream's best idea (the difference IS the payload, both sides retained) while never
   -- writing back into the working set it compares (doc 48 §1.3)
reconciliation_decision(id, company_id, reconciliation_finding_id,
    decision decision_enum /*accept_match|reject_match|link|unlink|defer|write_off|dispute*/,
    actor_id, decided_at timestamptz, reason_code text, reason text,
    match_policy_revision_id bigint NOT NULL, reverses_decision_id bigint NULL,
    command_receipt_id)
   UNIQUE (company_id, command_receipt_id)
   -- append-only; current linkage is a projection over unreversed decisions

return_filing(id, company_id, return_period_id, return_working_set_id,
    payload jsonb NOT NULL, payload_hash char(64) NOT NULL,
    acknowledgement_no text, filed_at timestamptz, authority_timestamp timestamptz,
    evidence_class evidence_class_enum, statutory_artefact_id bigint NULL,
    supersedes_filing_id bigint NULL, command_receipt_id)
   UNIQUE (company_id, return_period_id, payload_hash)
   -- one unreversed current filing per period by deferred trigger under the period lock

customs_assessment(id, company_id, doc_no, import_declaration_no text, assessed_on date,
    supplier_id, currency_id, exchange_rate numeric(21,9),
    assessable_value numeric(19,4), voucher_id bigint NOT NULL REFERENCES voucher(id),
    state posting_state_enum, command_receipt_id, reverses_assessment_id bigint NULL)
   UNIQUE (company_id, doc_no)
   UNIQUE (company_id, import_declaration_no)
customs_assessment_allocation(id, company_id, customs_assessment_id,
    source_line_type text, source_line_id bigint, tax_component_id NULL, duty_code text NULL,
    amount numeric(19,4), destination credit_destination_enum,
    stock_move_id NULL, asset_cost_event_id NULL, expense_account_id NULL, ordinal integer)
   UNIQUE (company_id, customs_assessment_id, source_line_id, tax_component_id, duty_code, ordinal)
      NULLS NOT DISTINCT
   CHECK (num_nonnulls(stock_move_id, asset_cost_event_id, expense_account_id) <= 1)
   -- deferred: Σ allocation per source line ≤ that line's assessed residual, under a source-line lock.
   -- Coverage between the commercial invoice and the assessment is a doc_link graph with a derived
   -- residual — never a `pending_boe_qty` counter (doc 48 §4).
```

### 27.1 Localisation write ordering

```text
determination (inside the §8 posting funnel)
1 claim idempotency ; 2 guard accounting period AND return_period state for the registration
3 capture tax_registration_snapshot for both parties — BLOCKING, refuse if stale beyond policy
4 resolve jurisdiction revision, place of supply + basis, source area + basis, supply type
5 resolve classification and rate revisions per line
6 compute components purely; assign the residual deterministically
7 insert determination + lines + components ; insert tax_credit_block rows and their
  stock_move value components / asset_cost_event rows
8 insert voucher + gl_entry ; run deferred applicability, per-line, per-component and
  forward/reverse cancellation checks
9 outbox ; commit ; project registers

external artefact
1 obligation from the dated jurisdiction rule → statutory_artefact(state=required)
2 claim statutory_submission_work FOR UPDATE SKIP LOCKED ; set lease
3 insert statutory_submission_attempt BEFORE the call
4 call ; then: issued → event with the authority timestamp ; duplicate → fetch, VERIFY signature,
  compare full identifying content, attach only on exact match ; rejected → terminal ;
  transport/timeout → retryable with backoff, never blind resubmit
5 release the lease ; outbox ; commit

return period
1 build return_working_set version N from determination facts up to a watermark
2 fetch authority_dataset via a submission attempt
3 reconciliation_run pins working set, dataset, match policy and comparison precision
4 insert reconciliation_finding rows — pure, no writes to either input
5 append reconciliation_decision rows ; linkage is projected
6 insert return_filing ; record the acknowledgement and authority timestamp
7 return_period.state = filed → the posting guard now refuses that period
```

---

## 28. Localisation invariant register

The exact **G1–G29** names and their primary enforcement layers are consolidated in
[`docs/logic/49`](../logic/49-tranche-f-closure-and-our-localisation-spec.md#3-g1g29-exact-register-and-enforcement-owner).
They extend the registers in §9, §18 and §23. Structurally:

- **G1/G2** — jurisdiction, rates, formats and match policies are approved revisions; statutory columns live
  in versioned schema and never appear or disappear with a settings checkbox;
- **G3** — `tax_registration_snapshot` is immutable and captured synchronously, so registration validation
  cannot arrive after the write;
- **G4/G5** — `tax_rate_component`'s exact-sum trigger generalises the intra-state doubling rule, and
  classification and rates are effective-dated revisions items merely reference;
- **G10/G11** — place of supply is an area FK with a recorded basis, and an unmapped component account is a
  refusal;
- **G12** — forward and reverse amounts cancel exactly at the document's declared precision;
- **G13** — blocked credit is a typed allocation into `stock_move` value components and `asset_cost_event`
  rows, never an in-place valuation edit;
- **G14/G24/G25** — `return_period` and `return_filing` are the statutory period-control and filing facts;
  working sets are versioned and hashed;
- **G18/G19** — every submission is an attempt record committed before the call, and an authority identifier
  is append-only with `signature_verified` gating `authority_confirmed`;
- **G26** — match tiers are versioned data and every match decision is an append-only fact; and
- **G27** — customs assessment is a posting document with typed allocations and a link-graph residual.

Every G invariant requires a schema refusal test; submission, reconciliation and filing invariants
additionally require concurrency, retry and duplicate-response tests. **S12** is the end-to-end acceptance
fixture.

---

## 29. What remains open

- **Application implementation has not started.** This file is the target schema contract produced by
  investigation.
- **Localisation, including India GST, is a required capability and is not yet specified here.** It will
  add jurisdiction-scoped tax determination, HSN/SAC classification, place-of-supply resolution,
  CGST/SGST/IGST/cess component splitting, reverse charge, TDS/TCS, document-numbering rules and statutory
  reporting extracts. It must reuse the existing `doc_tax` / `doc_tax_line_alloc` / `gl_entry` boundary and
  **must not** be layered as an ERPNext-style `@allow_regional` runtime override
  (doc 21 §4, doc 28). Because more than one regime is in scope, the regional-overlay replacement is the
  next design priority.
- Tranches A, B, C and E are complete: accounting/trade, production/ownership/quality, assets, and
  permissions/RLS, numbering, jobs, migrations, reporting and orchestration — the last specified in doc 25
  and represented here by the company/RLS, idempotency and outbox contracts.
- Presentation-layer contracts (form layout, grid, customisation) are being specified separately; see
  `docs/agents/PROMPT-frontend-form-ui.md`.
