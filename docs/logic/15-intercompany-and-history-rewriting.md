# 15 — Inter-Company Transactions and History Rewriting (Repost / Unreconcile / Deletion)

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Two topics that belong together because both exist to compensate for the same schema decision:
**derived state is stored, so it must be rebuilt** — across companies (inter-company mirroring)
and across time (reposting).

---

## Part A — Inter-Company Transactions

### 1. The model: two documents, cross-linked by name

There is **no inter-company transaction entity**. A sale from Company A to Company B is a
`Sales Invoice` in A and a *separately created* `Purchase Invoice` in B, linked by two scalar
columns pointing at each other:

- `inter_company_invoice_reference` (invoices)
- `inter_company_order_reference` (orders)

`update_linked_doc` (`accounts/doctype/sales_invoice/services/inter_company.py:66`):

```python
ref_field = ("inter_company_invoice_reference" if doctype in ["Sales Invoice","Purchase Invoice"]
             else "inter_company_order_reference")
if inter_company_reference:
    frappe.db.set_value(doctype, inter_company_reference, ref_field, name)
```

`unlink_inter_company_doc` (`:76`):

```python
if doctype in ["Sales Invoice", "Purchase Invoice"]:
    ref_doc   = "Purchase Invoice" if doctype == "Sales Invoice" else "Sales Invoice"
    ref_field = "inter_company_invoice_reference"
else:
    ref_doc   = "Purchase Order" if doctype == "Sales Order" else "Sales Order"
    ref_field = "inter_company_order_reference"
if inter_company_reference:
    frappe.db.set_value(doctype, name, ref_field, "")
    frappe.db.set_value(ref_doc, inter_company_reference, ref_field, "")
```

Two unguarded `db.set_value` calls, each writing a **submitted document in another company**.
Failure between them leaves a one-way link. The pairing is not a constraint; it is a convention
maintained by two writes.

Note the field name doubles as the mirror's field name — so the *same column* on the Sales
Invoice means "my Purchase Invoice" and on the Purchase Invoice means "my Sales Invoice".
Direction is inferred from `doctype`, not from data.

### 2. Internal parties

An inter-company party is a `Customer` with `is_internal_customer = 1` and
`represents_company`, or a `Supplier` with `is_internal_supplier = 1` and `represents_company`,
plus an `Allowed To Transact With` child table listing permitted counterpart companies.

`validate_inter_company_party` (`accounts/doctype/sales_invoice/services/inter_company.py:10`):

```python
config = _get_inter_company_party_config(doctype)          # :24
if inter_company_reference:
    _validate_against_reference(config, party, company, inter_company_reference)   # :40
elif frappe.db.get_value(config.partytype, {"name": party, config.internal: 1}, "name") == party:
    _validate_internal_party_company(config.partytype, party, company)            # :49
```

`_validate_against_reference` (`:40`):

```python
doc = frappe.get_doc(config.ref_doc, inter_company_reference)
ref_party = doc.supplier if config.partytype == "Customer" else doc.customer
if frappe.db.get_value(config.partytype, {"represents_company": doc.company}, "name") != party:
    frappe.throw("Invalid {0} for Inter Company Transaction.")
if frappe.get_cached_value(config.ref_partytype, ref_party, "represents_company") != company:
    frappe.throw("Invalid Company for Inter Company Transaction.")
```

`frappe.db.get_value(partytype, {"represents_company": doc.company}, "name")` returns **an
arbitrary one** of possibly several customers representing that company (no `LIMIT`/`ORDER BY`
semantics guaranteed). If a company is represented by two customer records — entirely possible,
since nothing enforces uniqueness of `represents_company` — the validation compares against
whichever row the database returns first and rejects legitimate documents non-deterministically.

`_validate_internal_party_company` (`:49`) reads `Allowed To Transact With` rows and throws if
the company is absent. Note it queries `parenttype`/`parent` directly on the child table — a
child-table scan with no index on `(parenttype, parent)` beyond the standard one.

### 3. Mirroring is a document-mapping exercise

`make_inter_company_transaction` (`accounts/doctype/sales_invoice/mapper.py:180`) and siblings:

| Source → Target | Function |
|---|---|
| Sales Invoice → Purchase Invoice | `accounts/doctype/sales_invoice/mapper.py:176` |
| Purchase Invoice → Sales Invoice | `accounts/doctype/purchase_invoice/mapper.py:41` |
| Sales Order → Purchase Order | `selling/doctype/sales_order/mapper.py:970` |
| Purchase Order → Sales Order | `buying/doctype/purchase_order/mapper.py:214` |
| Delivery Note → Purchase Receipt | `stock/doctype/delivery_note/mapper.py:409` (`make_inter_company_transaction`, `:413`) |
| Purchase Receipt → Delivery Note | `stock/doctype/purchase_receipt/mapper.py:249` |
| Journal Entry → Journal Entry | `accounts/doctype/journal_entry/mapper.py:212` |

`validate_inter_company_transaction` (`accounts/doctype/sales_invoice/mapper.py:149`) enforces:

```python
valid_price_list = frappe.db.get_value("Price List", {"name": price_list, "buying": 1, "selling": 1})
if not valid_price_list and not doc.is_internal_transfer():
    frappe.throw("Selected Price List should have buying and selling fields checked.")
...
default_currency = frappe.get_cached_value("Company", company, "default_currency")
if default_currency != doc.currency:
    frappe.throw("Company currencies of both the companies should match for Inter Company Transactions.")
```

Two hard constraints worth naming:

1. **The price list must be flagged both `buying` and `selling`.** A shared price list becomes a
   coupling point between two legal entities' pricing.
2. **Both companies must share the same currency as the document.** Cross-currency
   inter-company trade is simply not supported by this path. For a multinational group — the
   primary use case for inter-company accounting — this is disqualifying.

`update_item` (`accounts/doctype/sales_invoice/mapper.py:207`) shows the quantity logic:

```python
target.qty = flt(source.qty) - received_items.get(source.name, 0.0)
```

with `condition: lambda doc: doc.qty - received_items.get(doc.name, 0.0) > 0`
(`accounts/doctype/sales_invoice/mapper.py:239`). So partial mirroring is supported by
subtracting what was already received — computed by `get_received_items(...)`, i.e. **another
aggregate scan**, not a fulfilment link.

`field_no_map: ["income_account", "expense_account", "cost_center", "warehouse"]`
(`:232`) — accounts and cost centres are deliberately *not* copied, since they belong to the
other company's chart. But `rate` **is** copied (`field_map: {"rate": "rate"}`, `:233`–`:235`),
so transfer pricing is "whatever the seller charged", with no transfer-pricing policy object.

### 4. Elimination is not modelled

There is no consolidation or elimination structure. A group with intercompany sales must:

- run reports per company, and
- manually eliminate the mirrored revenue/COGS and the intercompany receivable/payable.

The only support is that the two documents know each other's names. There is no
`intercompany_pair` entity, no elimination account mapping, no unrealised-profit-in-inventory
tracking, and no consolidated ledger. `Journal Entry.validate_inter_company_accounts`
(`accounts/doctype/journal_entry/journal_entry.py:362`) and `unlink_inter_company_jv` (`:457`)
are the extent of it.

### 5. Our design

```sql
CREATE TABLE intercompany_relationship (
    id                uuid PRIMARY KEY,
    group_id          uuid NOT NULL REFERENCES company_group(id),
    seller_company_id uuid NOT NULL REFERENCES company(id),
    buyer_company_id  uuid NOT NULL REFERENCES company(id),
    seller_party_id   uuid NOT NULL REFERENCES party(id),   -- buyer-as-customer in seller's books
    buyer_party_id    uuid NOT NULL REFERENCES party(id),   -- seller-as-supplier in buyer's books
    transfer_pricing_policy_id uuid REFERENCES transfer_pricing_policy(id),
    elimination_profile_id uuid REFERENCES elimination_profile(id),
    CONSTRAINT ic_distinct CHECK (seller_company_id <> buyer_company_id),
    UNIQUE (seller_company_id, buyer_company_id)
);

CREATE TABLE intercompany_pair (
    id                uuid PRIMARY KEY,
    relationship_id   uuid NOT NULL REFERENCES intercompany_relationship(id),
    seller_voucher_id uuid NOT NULL REFERENCES voucher(id),
    buyer_voucher_id  uuid NOT NULL REFERENCES voucher(id),
    pair_kind         ic_pair_kind NOT NULL,   -- 'order','shipment','invoice','journal'
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (seller_voucher_id, pair_kind),
    UNIQUE (buyer_voucher_id, pair_kind)
);
```

Improvements over ERPNext:

- **The pairing is a row, not two mutually-pointing columns.** Two `UNIQUE` constraints make
  one-to-one pairing a database guarantee; a half-written link (§1) is impossible.
- **`represents_company` uniqueness is enforced** via `UNIQUE (seller_company_id,
  buyer_company_id)` on the relationship and a `UNIQUE (company_id, represents_company_id)` on
  `party`, so `_validate_against_reference`'s non-deterministic lookup (§2) has no analogue.
- **Currency is free.** The pair records both vouchers' currencies and the rate used; there is
  no requirement that group companies share a currency (§3 constraint 2). Elimination works on
  a group presentation currency via `elimination_profile`.
- **Transfer pricing is a policy object**, so the buyer's cost is derived from a documented rule
  (cost-plus %, resale-minus %, market, seller's price) rather than being a copied `rate` (§3).
- **Elimination is first-class**: `elimination_profile` maps intercompany revenue/COGS/AR/AP
  accounts to elimination accounts, and a `consolidation_run` produces
  `consolidated_gl_entry` rows tagged with the eliminating `intercompany_pair_id`. Unrealised
  profit in inventory is tracked because `stock_move` carries `intercompany_pair_id` when the
  goods came from a group company (§4).
- **Mirroring uses `doc_link`** (doc 10 §5.1) with `link_kind = 'intercompany_mirror'`, so
  partial mirroring is a sum over links rather than a `get_received_items` scan (§3).
- Both vouchers are created **in one transaction** with the pair row, so there is no window in
  which one exists without the other.

---

## Part B — History Rewriting

Three subsystems exist solely to rebuild stored derived state. They are the operational cost of
decisions our design avoids.

### 6. `Repost Accounting Ledger`

`accounts/doctype/repost_accounting_ledger/repost_accounting_ledger.py`.

Preconditions: `validate_repost_preconditions` (`:52`),
`validate_for_deferred_accounting` (`:58`), `validate_for_closed_fiscal_year` (`:63`),
`validate_vouchers` (`:90`), `validate_no_duplicate_vouchers` (`:106`),
`validate_vouchers_are_submitted` (`:112`),
`validate_docs_for_deferred_accounting` (`:469`), `validate_docs_for_voucher_types` (`:494`),
`get_repost_allowed_types` (`:514`), `get_allowed_types_from_settings` (`:442`),
`get_child_docs` (`:459`). Preview: `get_existing_ledger_entries` (`:138`),
`generate_preview_data` (`:154`), `generate_preview` (`:174`).

#### 6.1 Locking is file-based

`_lock_vouchers` (`:267`) — the docstring in the source is unusually candid:

> Lock every voucher up front so a concurrent repost cannot touch the same GL entries.
> … These are file locks under the site directory: they serialise nothing across hosts that do
> not share it, and a worker killed outright leaves them behind until they expire.

So the concurrency control for rewriting the general ledger is **advisory file locks on a shared
filesystem**. On a multi-host deployment without shared storage, two workers can rewrite the
same voucher's GL simultaneously. A killed worker leaves a stale lock that blocks reposting until
expiry.

#### 6.2 The repost loop commits per voucher

`repost` (`:287`):

```python
frappe.flags.through_repost_accounting_ledger = True
pending = [x for x in repost_doc.vouchers if x.status not in HANDLED_VOUCHER_STATUSES]
locked_docs = _lock_vouchers(pending)
repost_doc.db_set("status", "In Progress", commit=commit)
for position, x in enumerate(pending, start=1):
    frappe.db.savepoint("reposting")
    try:
        doc = locked_docs[(x.voucher_type, x.voucher_no)]
        if doc.docstatus == 2:
            x.db_set({"status": "Skipped", "traceback": ""}); continue
        if repost_doc.delete_cancelled_entries:
            _delete_accounting_ledger_entries(doc.doctype, doc.name)
            _delete_adv_pl_entries(doc.doctype, doc.name)
        _repost_vouchers(doc, repost_doc.delete_cancelled_entries)
    except Exception:
        frappe.db.rollback(save_point="reposting")
        x.db_set({"status": "Failed", "traceback": frappe.get_traceback()})
    else:
        x.db_set({"status": "Reposted", "traceback": ""})
    finally:
        if commit: frappe.db.commit()   # nosemgrep
```

- **`frappe.db.commit()` after every voucher** (`:340`). The ledger is therefore *observably
  inconsistent mid-repost*: some vouchers rewritten, some not, and the trial balance does not
  balance in between. There is no "as-of" isolation for readers.
- `_delete_accounting_ledger_entries` (`accounts/utils.py:1734`) and `_delete_adv_pl_entries`
  (`:1724`) **physically delete** GL/APLE rows before rewriting. The pre-repost state is gone.
- `_derive_status` (`:357`) yields `Completed` / `Failed` / `Partially Reposted` — the last of
  which is a documented steady state for a general ledger.
- `_record_repost_failure` (`:369`) persists the traceback into `error_log` on the document and
  into the Error Log, then commits.
- Per-voucher dispatch: `_repost_vouchers` (`:388`) → `_repost_invoices` (`:402`),
  `_repost_purchase_receipt` (`:415`), `_repost_pe_je` (`:424`),
  `_repost_allowed_hook_doctypes` (`:430`) via `frappe.get_hooks("repost_allowed_doctypes")`.
- `_raise_error_if_reposting_in_progress` (`:209`) is the only cross-document guard.
- Job identity: `_repost_job_id` (`:242`), `_enqueue_repost` (`:247`).

Also note `validate_for_closed_fiscal_year` (`:63`) — reposting *can* be blocked by a closed
year, but `repost` rewrites history by design, so the interaction with `Period Closing Voucher`
(doc 07) is a validation, not an invariant.

### 7. `Repost Payment Ledger`

`accounts/doctype/repost_payment_ledger/repost_payment_ledger.py`.
`repost_ple_for_voucher` (`:16`), `start_payment_ledger_repost` (`:24`),
`before_validate` (`:82`), `load_vouchers_based_on_filters` (`:86`), `get_vouchers` (`:92`),
`set_status` (`:112`), `on_submit` (`:116`), `execute_repost_payment_ledger` (`:122`).

The Payment Ledger — the source of truth for outstanding balances (doc 04) — has a dedicated
rebuild tool. Its existence concedes that the PLE is derived data that goes wrong.

### 8. `Repost Item Valuation`

`stock/doctype/repost_item_valuation/repost_item_valuation.py`. The largest of the three,
because stock valuation is order-dependent (doc 02) and a backdated entry invalidates every
later entry for that item+warehouse.

Validation: `validate` (`:92`), `set_default_posting_time` (`:104`),
`reset_repost_only_accounting_ledgers` (`:111`), `validate_update_stock` (`:115`),
`validate_recreate_stock_ledgers` (`:127`), `validate_period_closing_voucher` (`:147`),
`reset_recreate_stock_ledgers` (`:180`), `get_closing_stock_balance` (`:184`),
`get_max_period_closing_date` (`:196`), `validate_accounts_freeze` (`:207`),
`reset_field_values` (`:222`).

Deduplication and coverage — an entire sub-language for "has this repost already been done":
`skipped_similar_reposts` (`:300`), `deduplicate_similar_repost` (`:322`),
`skip_reposts_covered_by_dependents` (`:354`), `repost_coverage_cache_key` (`:402`),
`get_queued_item_reposts` (`:406`), `mark_covered_item_reposts` (`:423`),
`get_queued_transaction_reposts` (`:439`), `accumulate_repost_coverage` (`:457`),
`get_repost_items_by_voucher` (`:473`), `is_transaction_repost_covered` (`:492`),
`mark_covered_transaction_reposts` (`:504`).

Execution: `repost` (`:530`), `repost_sl_entries` (`:615`), `repost_gl_entries` (`:642`),
`_get_directly_dependent_vouchers` (`:689`),
`_update_post_delivery_billed_vouchers` (`:721`), `_recalculate_valuation_rate` (`:369`),
`recreate_stock_ledger_entries` (`:378`),
`make_reposting_for_accounting_ledgers` (`:972`),
`get_existing_reposting_only_gl_entries` (`:993`).

Scheduling: `run_parallel_reposting` (`:791`), `enqueue_reposting_entry` (`:828`),
`enqueue_parallel_reposting` (`:840`), `get_entries_with_active_jobs` (`:850`),
`get_items_with_active_reposting` (`:860`), `repost_entries` (`:873`),
`execute_reposting_entry` (`:888`), `_execute_reposting_entry` (`:896`),
`get_repost_item_valuation_entries` (`:911`), `in_configured_timeslot` (`:933`),
`execute_repost_item_valuation` (`:957`), `bulk_restart_reposting` (`:390`),
`restart_reposting` (`:288`), `check_pending_repost_against_cancelled_transaction` (`:279`),
`clear_old_logs` (`:76`), `clear_attachment` (`:251`), `remove_attached_file` (`:608`),
`notify_error_to_stock_managers` (`:759`), `get_recipients` (`:777`).

Two observations:

- **`in_configured_timeslot` (`:933`)** — reposting is restricted to an off-hours window
  because it is too heavy to run during business hours. Correctness is scheduled.
- **`notify_error_to_stock_managers` (`:759`)** — repost failures are emailed to humans. The
  inventory valuation being wrong is an operational alert, not a prevented state.

### 9. `Unreconcile Payment`

`accounts/doctype/unreconcile_payment/unreconcile_payment.py:20`.
`validate` (`:40`), `get_allocations_from_payment` (`:46`), `add_references` (`:53`),
`on_submit` (`:59`), `doc_has_references` (`:79`),
`get_linked_payments_for_doc` (`:105`), `get_linked_advances` (`:175`),
`create_unreconcile_doc_for_selection` (`:204`).

`on_submit` calls into `unlink_ref_doc_from_payment_entries` /
`update_accounting_ledgers_after_reference_removal` (doc 11 §4). As established in doc 09 §3.3,
the `Unreconcile Payment` document is **cancelled and deleted** by
`AccountsController._remove_references_in_unreconcile`
(`controllers/accounts_controller.py:331`, deletion at `:355`–`:361`) when the underlying voucher
is cancelled — so the audit record of an un-allocation does not survive.

### 10. Why our design has none of this

| Repost subsystem | Exists because | Our replacement |
|---|---|---|
| `Repost Accounting Ledger` | GL rows embed derived values (party, against_voucher, dimensions, exchange rates) that change when the source document changes | GL is append-only; a correction is a reversal + new voucher (D5). Nothing to rewrite. |
| `Repost Payment Ledger` | `outstanding_amount` and PLE are caches | `outstanding` is a view over `settlement` (D9, doc 11 §6.2). Nothing to rebuild. |
| `Repost Item Valuation` | `Stock Ledger Entry` stores `qty_after_transaction`, `valuation_rate`, `stock_value` — derived state inside the event row, so a backdated entry rewrites history | `stock_move` (immutable event) is split from `stock_valuation_state` (recomputable projection) (D6). A backdated move recomputes the *projection* forward from that point; the event log is never touched. |
| `Unreconcile Payment` | un-allocation cannot be expressed as a compensating record | compensating `settlement` row (D8) |
| Coverage/dedup machinery (`:300`–`:526`) | reposts are queued jobs that may overlap | projection rebuild is idempotent and range-scoped: `REFRESH` from `(item_id, warehouse_id, posted_at >= t)`; running it twice is harmless |
| `in_configured_timeslot` | reposts are too heavy for business hours | projection recompute is bounded by the number of moves after `t` for one item+warehouse, and runs in the posting transaction |
| File locks (`:267`) | no database-level serialisation of ledger rewrites | `SELECT ... FOR UPDATE` on the `stock_valuation_state` row for `(item_id, warehouse_id)` — real, cross-host, released on transaction end |
| Per-voucher `commit()` (`:340`) | long-running rewrite must checkpoint | no long-running rewrite exists |
| `Partially Reposted` status | partial success is a steady state | atomic: either the projection is consistent or the transaction rolled back |
| `notify_error_to_stock_managers` | valuation errors are discovered after the fact | valuation is computed synchronously; an inconsistency cannot be committed |

### 11. Deletion, restated

Doc 09 §5 covers `frappe.delete_doc` and `Transaction Deletion Record`. The point relevant here:
`AccountsController.on_trash` (`controllers/accounts_controller.py:419`) can **physically delete
GL Entry, Stock Ledger Entry, Payment Ledger Entry, and Advance Payment Ledger Entry rows**
(`:433`–`:447`) when `Accounts Settings.delete_linked_ledger_entries` is on, and
`_remove_references_in_repost_doctypes` (`:362`) / `_remove_references_in_unreconcile` (`:331`)
strip references from *submitted* repost and unreconcile documents with
`flags.ignore_validate_update_after_submit` and `flags.ignore_links`.

So the three history-rewriting subsystems are themselves rewritten by deletion. There is no
layer at which the audit trail is guaranteed.

**Our invariants (from `docs/design/FINAL-SCHEMA.md`):**

- **H1.** `gl_entry`, `stock_move`, `ar_ap_entry`, `settlement`, `doc_link`,
  `budget_commitment`, `bank_match`, `loyalty_entry` are append-only.
  `REVOKE UPDATE, DELETE` from the application role, plus a `BEFORE UPDATE OR DELETE` trigger
  that raises unconditionally.
- **H2.** Every correction is a new row with `reverses_*_id UNIQUE`, so double-reversal is a
  constraint violation, not a flag check.
- **H3.** Projections (`stock_valuation_state`, materialised views) are declared as such, carry
  `rebuilt_from` / `rebuilt_at`, and are reproducible from the event log by a single deterministic
  function. A projection may be dropped and rebuilt at any time; a ledger may not.
- **H4.** No configuration setting can enable physical deletion of a ledger row. The capability
  does not exist in the schema grants.

---

Cross-references: doc 01 (GL posting), doc 02 (stock ledger and valuation — the source of
repost pain), doc 04 (AR/AP), doc 07 (period close), doc 09 (lifecycle and deletion),
doc 11 (advances and allocation), `docs/design/FINAL-SCHEMA.md` §Invariant register.
