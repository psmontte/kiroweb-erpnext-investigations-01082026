# 4. AR / AP subledger and settlement

How "who owes what" is computed, allocated, reconciled and aged.

Primary files:
- `accounts/utils.py` — PLE creation, `update_voucher_outstanding`, `QueryPaymentLedger`,
  `reconcile_against_document`, FX journal builder
- `accounts/doctype/payment_ledger_entry/payment_ledger_entry.py`
- `accounts/doctype/payment_entry/payment_entry.py` (3327 lines)
- `accounts/doctype/payment_reconciliation/payment_reconciliation.py`
- `accounts/services/advances.py`, `accounts/services/exchange_gain_loss.py`
- `accounts/report/accounts_receivable/accounts_receivable.py`

Naming note for v17: `update_voucher_outstanding_amt` and `get_outstanding_amount` **no longer exist**.
The single writer is `accounts/utils.py::update_voucher_outstanding` (:2175); the aggregation is
`QueryPaymentLedger.get_voucher_outstandings`.

---

## 4.1 Why a subledger exists

Computing "what is still unpaid" from `GL Entry` alone means scanning the ledger. So every
receivable/payable GL row is mirrored into `Payment Ledger Entry` (PLE), which is indexed on
`(against_voucher_no, against_voucher_type)` and `(voucher_no, voucher_type)`
(payment_ledger_entry.py:179).

## 4.2 Creating PLE rows (`get_payment_ledger_entries`, accounts/utils.py:2024-2120)

Called from `make_gl_entries` **after** `process_gl_map` and **before** `save_entries`
(accounts/general_ledger.py:58), skipped for `Period Closing Voucher`.

1. Collect the company's accounts with `account_type in ("Receivable","Payable")`. **Only GL rows
   hitting those accounts produce a PLE** — that is the entire filter.
2. Sign convention (:2049):
   ```
   Receivable: amount = debit  - credit
   Payable:    amount = credit - debit          # mirrored
   cancel=1:   amount *= -1
   ```
   > **Invariant** Positive = an open obligation (AR invoice raised, AP bill received).
   > Negative = a settlement or credit (payment, advance, credit note, write-off).
   > Payables are sign-flipped at write time so **one aggregation works for both sides**.
3. Target selection (:2060):
   ```
   against_voucher_type = gle.against_voucher_type or gle.voucher_type
   against_voucher_no   = gle.against_voucher      or gle.voucher_no
   ```
   Inherited verbatim from the GL row, **falling back to self-reference**. Consequences:
   - an invoice's own `debit_to`/`credit_to` row → self-referencing PLE = "the invoice amount" row;
   - a Payment Entry party row → `against_voucher = the invoice`, *unless* the reference is an order
     or `book_advance_payments_in_separate_party_account` is on, in which case it self-references and
     the payment shows up as an unallocated advance;
   - a Journal Entry row points at whatever `reference_type/reference_name` the accountant set.
4. Both currency legs are stored: `amount` (company) and `amount_in_account_currency` (party account).
   `voucher_detail_no` records which child row produced it — used for partial cancel / delink.
5. If the GL row carries `advance_voucher_no`, an **`Advance Payment Ledger Entry`** row is emitted too
   (:2100, builder :2122) with `event = "Submit"` when self-referencing else `"Adjustment"`.

`delinked` is the logical-removal flag. Every aggregation filters `delinked = 0`. It is **not** the
docstatus — PLEs are always submitted.

## 4.3 Outstanding amount

Trigger — `PaymentLedgerEntry.on_update` (:152-176):
```
if against_voucher_type in OUTSTANDING_DOCTYPES        # frozenset{"Sales Invoice","Purchase Invoice","Fees"} accounts/utils.py:62
   and flags.update_outstanding == "Yes"
   and not frappe.flags.is_reverse_depr_entry:
        update_voucher_outstanding(against_voucher_type, against_voucher_no, account, party_type, party)
```

`update_voucher_outstanding` (accounts/utils.py:2175-2223):
- If the voucher is an advance-payment doctype (SO/PO, from the
  `advance_payment_receivable_doctypes` hooks) → `ref_doc.set_total_advance_paid()` and return.
- Else requires `voucher_type in OUTSTANDING_DOCTYPES` and a party, then calls
  `QueryPaymentLedger().get_voucher_outstandings([...], common_filter)`.
- Writes `outstanding_amount = flt(outstanding["outstanding_in_account_currency"], precision)` —
  **party-account currency, not company currency** — via `frappe.db.set_value`, then
  `update_linked_dunnings`, `ref_doc.set_status(update=True)`, `notify_update()`.
- If the aggregate returns nothing (everything delinked) it **returns early, leaving the stale value**.

### The aggregation (`QueryPaymentLedger`, accounts/utils.py:2273-2532)

Reads **PLE only**, never GL. Two CTEs:

```sql
-- vouchers: the voucher's own gross amount
SELECT MAX(account) account, voucher_type, voucher_no, party_type, party,
       MAX(posting_date), MAX(due_date), MAX(account_currency) currency, MAX(cost_center),
       SUM(amount) amount, SUM(amount_in_account_currency) amount_in_account_currency, MAX(remarks)
FROM `tabPayment Ledger Entry`
WHERE delinked = 0 AND <voucher filter> AND <common filter> AND <dimensions> AND <dates>
GROUP BY voucher_type, voucher_no, party_type, party

-- outstanding: everything pointing AT the voucher
SELECT ..., against_voucher_type AS voucher_type, against_voucher_no AS voucher_no,
       SUM(amount) amount, SUM(amount_in_account_currency) amount_in_account_currency
FROM `tabPayment Ledger Entry`
WHERE delinked = 0 AND <against filter> AND <common filter>
GROUP BY against_voucher_type, against_voucher_no, party_type, party
```
Joined `vouchers LEFT JOIN outstanding USING (account, voucher_type, voucher_no, party_type, party)`,
selecting `invoice_amount`, `outstanding`, and `paid_amount = vouchers.amount − outstanding.amount`
(plus account-currency twins). Row filters: `outstanding.amount_in_account_currency > 0` when
`get_invoices`, `< 0` when `get_payments`.

> **Invariant** `outstanding(X) = Σ PLE.amount WHERE against_voucher = X AND delinked = 0`
> (including the invoice's own self-referencing row), and `paid = invoice_amount − outstanding`.
> `Sales Invoice.outstanding_amount` is a **cache** of the account-currency variant. Nothing else may
> write it.

Postgres adaptations already present in the code and worth noting for our port: `MAX()` wrappers on
non-grouped columns (:2369 comment), `HAVING` on the aggregate rather than an alias (:2360),
`ORDER BY` select aliases (:2357), `WHERE` instead of `HAVING` on the CTE (:2458).

### Status (`sales_invoice/services/status.py:11-116`)

Reads only `outstanding_amount` and `total = rounded_total|grand_total` (base variants when
`party_account_currency != currency`). Priority: `Internal Transfer` → `Overdue`
(`is_overdue` :96 — payment-schedule aware: overdue iff
`total − outstanding < Σ payment_schedule.payment_amount where due_date < today`) → `Partly Paid`
(0 < outstanding < total) → `Unpaid` → `Credit Note Issued` (a submitted return exists) → `Return` →
`Paid` (outstanding ≤ 0). Suffix `" and Discounted"` when discounted and disbursed.

## 4.4 Payment Entry

Lifecycle (:172-318):
```
validate: set_missing_values, set_liability_account, set_missing_ref_details(force=True),
          validate_payment_type, set_exchange_rate, validate_mandatory, validate_reference_documents,
          set_amounts, validate_amounts, apply_taxes, set_amounts_after_tax,
          clear_unallocated_reference_document_rows, validate_transaction_reference,
          validate_duplicate_entry, validate_payment_type_with_outstanding,
          validate_allocated_amount, validate_paid_invoices, TDS, set_status
on_submit:  THROWS if difference_amount != 0
            update_payment_requests, update_payment_schedule, make_gl_entries,
            update_outstanding_amounts, set_status
on_cancel:  ignore links to GL/PLE/Advance PLE, make_gl_entries(cancel=1),
            update_outstanding_amounts, delink_advance_entry_references
```

`Receive` → the party account is `paid_from`; `Pay` → `paid_to` (:157).

### Allocation validation (:365-502)

- `validate_allocated_amount_as_per_payment_request` (:384): allocation ≤ Payment Request outstanding.
- `validate_allocated_amount_with_latest_data` (:419) re-fetches live outstandings and throws:
  - "has already been fully paid" if the voucher is gone from the live list;
  - "has already been partly paid… use Get Outstanding Invoice" if the stored `outstanding_amount`
    snapshot ≠ live outstanding — **this is the optimistic-concurrency guard** (:466);
  - payment-term mismatch; `allocated_amount > payment_term_outstanding`;
  - over-allocation both ways: `allocated_amount > latest.outstanding_amount` **and**
    `allocated_amount < latest.outstanding_amount` when negative (so allocations against credit notes
    are bounded too) (:494).
- `validate_payment_type_with_outstanding` (:357) blocks `Receive` from a Customer when the sum of
  allocations is negative.
- `validate_duplicate_entry` (:330) makes `(reference_doctype, reference_name, payment_term,
  payment_request)` unique within the document.

### Amount pipeline (`set_amounts`, :953-1187)

```
base_paid_amount     = paid_amount     * source_exchange_rate
base_received_amount = received_amount * target_exchange_rate
per reference: base_allocated = allocated * (source|target rate)
               row.exchange_gain_loss = base_allocated - allocated * row.exchange_rate      # :1051
total_allocated_amount = abs(Σ allocated) ; base twin likewise
unallocated_amount = (base_paid + deductions - base_allocated - included_taxes) / source_rate   # Receive
set_exchange_gain_loss: keep exactly one `deductions` row flagged is_exchange_gain_loss holding
                        base_paid_amount - base_received_amount            # bank-leg FX
difference_amount:
  base_party_amount = base_total_allocated + unallocated * (source|target rate)
  Receive : base_party_amount - base_received_amount + included_taxes
  Pay     : base_paid_amount  - base_party_amount   - included_taxes
  Internal: base_paid_amount  - base_received_amount - included_taxes
  difference_amount -= Σ deductions.amount
```

> **Invariant** `difference_amount == 0` at submit (:203). Party-side value = bank-side value +
> deductions/taxes. Partial allocation is expressed as `unallocated_amount` (an on-account credit),
> never as an imbalance.

`clear_unallocated_reference_document_rows` (:1204) also issues
`frappe.db.delete("Payment Entry Reference", {parent, allocated_amount: 0})`.

### GL rows (`payment_entry/services/gl_composer.py`)

- **Party rows** (:45-170): one GL row **per reference row** on the party account —
  `credit` for Receive, `debit` for Pay; amounts = `allocated_amount` (account currency) and the base
  twin. Dr/Cr is flipped for negative allocations against invoices when the account type contradicts
  the payment type (:78) so the engine's normalisation does not double-flip.
  `against_voucher` = the invoice (:127), or the Payment Entry itself for order references (:110) and
  when advances are booked separately (:121). Plus one row for `unallocated_amount` (:133).
- **Bank rows** (:172-208): Cr `paid_from` with `paid_amount` (`post_net_value: True`) for Pay /
  Internal Transfer; Dr `paid_to` with `received_amount` for Receive / Internal Transfer.
- Deductions (:276) and taxes (:210, tax accounts must be in company currency).
- Advance GL (:1306-1425) — see §4.5.

## 4.5 Advances

### On the order (SO/PO) side — `accounts/services/advances.py`

```sql
-- calculate_total_advance_from_ledger :148
SELECT ABS(SUM(amount)), MAX(currency) FROM `tabAdvance Payment Ledger Entry`
WHERE company = ? AND delinked = 0 AND against_voucher_type = ? AND against_voucher_no = ?
```
`set_total_advance_paid` (:162) writes `advance_paid`, then `set_advance_payment_status` (:177) derives
`Not Requested / Requested / Initiated / Partially Paid / Fully Paid` from
`Σ (Payment Request.grand_total − outstanding_amount)` vs `rounded_total|grand_total`.

### On the invoice side — `Sales/Purchase Invoice Advance` child rows

`set_advances(doc)` (:27-59): pulls open advances via `get_advance_entries` (:62) =
`get_advance_journal_entries` (:317) + `get_advance_payment_entries` (:379), searching the invoice's
party account **and** the party's advance account, plus any linked orders. Then FIFO-allocates against
`base_rounded_total|base_grand_total`:
```
allocated_amount = min(amount − advance_allocated, d.amount)
```
writing `advance_amount`, `allocated_amount`, `ref_exchange_rate`, `difference_posting_date`, `account`.

Linking happens in `AccountsController.update_against_document_in_jv` (accounts_controller.py:1023),
whose docstring states the mechanism plainly: *"1. cancel advance voucher, 2. split into multiple rows
if partially adjusted, assign against voucher, 3. submit advance voucher"*. It builds args
(`voucher_type/no/detail_no`, `against_voucher = the invoice`, `account = debit_to|credit_to`,
`dr_or_cr = credit_in_account_currency` for SI / `debit_in_account_currency` for PI,
`unadjusted_amount`, `allocated_amount`, exchange rate, dimensions) and calls
`reconcile_against_document`.

`set_advance_gain_or_loss` (:128): `exchange_gain_loss = allocated_amount × (ref_exchange_rate −
doc.conversion_rate)`.

### "Book advance payments in separate party account"

`PaymentEntry.set_liability_account` (:230-294), draft-only: switches the party account to the
company's `default_advance_received_account` / `default_advance_paid_account`, and **turns itself off**
if the references contain anything other than Sales/Purchase Orders (:255). Effects:
- party GL rows point `against_voucher` at the Payment Entry itself, so the advance sits on the
  liability/asset account and does **not** reduce invoice outstanding;
- the transfer to the real receivable/payable happens later in `add_advance_gl_for_reference` (:1356):
  a pair of GL rows posted on `reconcile_effect_on`, back-computed by `get_reconciliation_effect_date`
  (accounts/utils.py:824) per `Company.reconciliation_takes_effect_on`
  (*Advance Payment Date* / *Oldest Of Invoice Or Advance* / …);
- on reconciliation, `reconcile_against_document` takes the advance branch and only calls
  `make_advance_gl_entries(entry=row)` instead of rebuilding the whole subledger (accounts/utils.py:562);
- partial cancel of just those rows uses `make_reverse_gl_entries(..., partial_cancel=True)` matching
  on `voucher_detail_no`.

## 4.6 Payment Reconciliation (virtual doctype)

**Fetch** (:135-411): `get_payment_entries` (:178), `get_jv_entries` (:223 — JV rows on the party
account with `reference_type` NULL/""/Sales Order/Purchase Order only, i.e. unlinked),
`get_dr_or_cr_notes` (:321 — submitted `is_return=1` invoices with non-zero outstanding, emitted as
`amount = -(outstanding_in_account_currency)`), and `get_invoice_entries` (:372) via
`get_outstanding_invoices` (accounts/utils.py:1251).

**Allocate** (`allocate_entries`, :480-533): greedy FIFO over payments × invoices. Per allocation it
computes `difference_amount` (`get_difference_amount` :426 — only when the party account currency ≠
company currency and the rates differ: `allocated × payment_rate − allocated × invoice_rate`, sign
flipped for Payable), sets `difference_account = Company.exchange_gain_loss_account` and
`gain_loss_posting_date` per `Accounts Settings.exchange_gain_loss_posting_date`
(*Invoice* → invoice date, *Reconciliation Date* → today, else payment date).

**Validate** (`validate_allocation`, :747-776): `amount − allocated_amount < 0` → throw;
`allocated_amount − invoice_outstanding > 0.009` → throw (**hard-coded 0.009 tolerance**);
empty table → throw.

**Reconcile** (:562-613): refuses to run when an auto-reconciliation job is active for the same
(company, party_type, party, receivable_payable_account) via `is_any_doc_running` (:590). Splits rows:
allocations whose *payment* is an invoice (credit/debit notes) → `reconcile_dr_cr_note`, everything else
→ `reconcile_against_document`.

### What `reconcile_against_document` writes (accounts/utils.py:516-587)

Per (voucher_type, voucher_no):
1. `check_if_advance_entry_modified` (:589) — re-queries and throws *"Payment Entry has been modified
   after you pulled it"*. Optimistic locking.
2. `validate_allocated_amount` (:661) — negative or exceeding `unadjusted_amount` → throw.
3. **Journal Entry path** (`update_reference_in_journal_entry`, :669-741): the existing JV Account row
   is reduced to `unadjusted − allocated` (or removed if fully allocated), and a **new JV Account row**
   is appended with the allocated amount, `reference_type/name = against_voucher*`, `docstatus = 1`.
4. **Payment Entry path** (`update_reference_in_payment_entry`, :743-822): same split on
   `Payment Entry Reference`, then `clear_unallocated_reference_document_rows`, `set_missing_values`,
   `set_amounts`, `make_exchange_gain_loss_journal`.
5. Ledger rebuild (:562-570): for the separate-advance-account case only
   `make_advance_gl_entries(entry=row)`; **otherwise `_delete_pl_entries` + `_delete_adv_pl_entries`,
   rebuild `gl_map = doc.build_gl_map()`, run `process_debit_credit_difference(gl_map)` ("make sure
   there is no overallocation"), and `create_payment_ledger_entry(gl_map, update_outstanding="No",
   adv_adj=1)`.** Note **GL Entry rows are not rewritten here** — only the subledger; the GL keeps its
   original `against_voucher`, and only a repost fixes that.
6. `update_voucher_outstanding(...)` per newly-linked against_voucher.
7. `reconcile_dr_cr_note` (:838-948) instead creates and submits a **Journal Entry** of
   `voucher_type = "Credit Note"` / `"Debit Note"` with two rows on the same party account: one for the
   allocated amount referencing the target invoice, one reverse leg referencing the note itself.

> **Ours** Replace all of this with an explicit settlement table:
> ```
> settlement(id, company_id, party_id,
>            source_doc_type, source_doc_id,      -- payment / credit note / journal
>            target_doc_type, target_doc_id,      -- invoice
>            amount, amount_base, exchange_rate, fx_gain_loss,
>            settled_on, created_at, created_by)
> ```
> plus a constraint that `Σ settlement.amount per target ≤ target.total`. Allocation is an insert, not
> a document rewrite. Reversal is a compensating row. No document is ever cancelled, split and
> resubmitted to record an allocation — that single design choice is the source of the optimistic-lock
> checks, the delete-and-rebuild subledger, and the "GL not rewritten" inconsistency above.

## 4.7 FX gain/loss on settlement

Three places compute the same number: `PaymentEntry.calculate_base_allocated_amount_for_reference`
(:1051), `PaymentReconciliation.get_difference_amount` (:426), `advances.set_advance_gain_or_loss`
(:128).

Posting — `accounts/services/exchange_gain_loss.py` → `utils.py::create_gain_loss_journal` (:2534):
a Journal Entry with `voucher_type = "Exchange Gain Or Loss"`, `multi_currency = 1`,
`is_system_generated = True`:
- leg 1 on the **party account**: `abs(exc_gain_loss)` in company currency and **0 in account
  currency** — so it moves base value only and does not change the party-currency outstanding;
- leg 2 on `Company.exchange_gain_loss_account` (must be company currency, else throw).

Sign rule: `dr_or_cr = "debit" if exchange_gain_loss > 0 else "credit"`, flipped by
`is_payable_account`. Deduplicated by querying existing EGL journals on
`(reference_type, reference_name, reference_detail_no=str(idx))` (:121-148).

> That "0 in account currency" leg is why these journals cannot balance in account currency, which is
> why `voucher_type == "Exchange Gain Or Loss"` is exempted from the balance check in doc 01. Our
> version: FX revaluation is a base-currency-only movement by construction — model `amount_base` as
> the only populated column and never pretend it is an account-currency movement.

## 4.8 Credit limit (`selling/doctype/customer/customer.py:513-570`)

```
credit_limit = get_credit_limit(customer, company)     # returns early if 0
outstanding  = get_customer_outstanding(customer, company, ignore_outstanding_sales_order)
if extra_amount: outstanding += extra_amount
if credit_limit > 0 and outstanding > credit_limit:
    if Accounts Settings.credit_controller not in frappe.get_roles(): msgprint(..., raise_exception=1)
```

`get_customer_outstanding` (:703) sums **GL Entry, not PLE**:
1. `SUM(debit) − SUM(credit)` from `tabGL Entry` where `party_type='Customer'`, party, company,
   `is_cancelled = 0` (optionally restricted to a cost-center subtree by `lft/rgt`);
2. plus `SUM(base_grand_total × (100 − per_billed)/100)` over submitted, non-Closed Sales Orders with
   `per_billed < 100`;
3. plus unbilled Delivery Notes (DN items left-joined to a `Sales Invoice Item` sub-aggregate on
   `dn_detail`).

Callers: `Sales Invoice.check_credit_limit` (:653), `Journal Entry.check_credit_limit` (:492), child
item updates, and `utils.pre_submit_validation` (:2774) which passes
`extra_amount = base_grand_total` for not-yet-posted documents and **downgrades failure to a warning**.

> Note the inconsistency: outstanding for the credit check comes from the GL in **company currency**,
> while `outstanding_amount` on the invoice comes from the PLE in **account currency**. Two definitions
> of the same word. Ours: one function, one currency (base), one source (the subledger + open order
> exposure), used by every caller.

## 4.9 Ageing (`report/accounts_receivable/accounts_receivable.py`)

Entirely PLE-driven. `prepare_ple_query` (:838-895) selects the PLE rows with `delinked = 0` and
`posting_date <= report_date` (or, with `show_future_payments`,
`posting_date <= report_date OR (voucher_no = against_voucher_no AND DATE(creation) <= report_date)`).

**Two passes are mandatory** (comment at :145): first `init_voucher_balance` for every row, then
`update_voucher_balance`. Keys are `(account, voucher_type, voucher_no, party)`.

`get_voucher_balance` (:238-293) maps a row onto its **against_voucher** row; if that is itself a
return, it folds onto `return_against` (:255).

`update_voucher_balance` (:295-329) — the bucketing rule:
```
amount > 0: if voucher is a JE/PE pointing at a different against_voucher: paid -= amount
            else: invoiced += amount
amount < 0: if the row's voucher is an invoice:
                self-referencing ? paid -= amount : credit_note -= amount
            else: paid -= amount
```
`build_data` (:347): `outstanding = invoiced − paid − credit_note`; rows are kept only if
`|outstanding| >= 1/10**precision` in **both** currencies (or the voucher is in `err_journals` — the FX
journals from §4.7, which move base value only).

Ageing (`set_ageing` :802, `get_ageing_data` :824): `entry_date = due_date or posting_date` (per
`ageing_based_on`); `age = (age_as_on − entry_date).days`; the **whole outstanding** goes into the first
bucket whose boundary satisfies `age <= days`, else the last. Future-dated entries go to `range0` with
`total_due = 0`.

`based_on_payment_terms` FIFO-splits the outstanding across `Payment Schedule` rows (:529-651) with
overpayment pushed into an extra row.

## 4.10 Concurrency

There is **no row lock taken when recomputing outstanding.** `update_voucher_outstanding` does an
unconditional `frappe.db.set_value(...)` (:2211) with a fully recomputed value. The `UPDATE` takes an
exclusive row lock for the rest of the transaction, but the **aggregate read before it is not locked**,
so a lost update is possible if the other transaction's PLE insert is not yet visible.

What exists instead is optimistic concurrency: `check_if_advance_entry_modified` (:589),
`validate_allocated_amount_with_latest_data` (payment_entry.py:419), the `reconcile_dr_cr_note`
outstanding re-check (:842), and the 0.009 tolerance in `validate_allocation`.

Real locks that do exist: `make_reverse_gl_entries` reads the voucher's GL rows `FOR UPDATE`
(accounts/general_ledger.py:621); `account.py:694` locks the GL Entry tail during account maintenance;
`process_period_closing_voucher.py:105` uses `.for_update(skip_locked=True)` to hand work to exactly
one worker; stock repost locks SLE rows in a separate pass because *"postgres rejects FOR UPDATE
alongside GROUP BY"* (accounts/utils.py:1785) — the same pattern our PLE CTEs will need.

> **Ours** `SELECT … FOR UPDATE` on the invoice row **before** aggregating, then recompute and write in
> the same transaction. Or better: keep `outstanding` as a generated read
> (`invoice.total − Σ settlement.amount`) with a covering index and no cached column at all; materialise
> only if measurement says we must, and then maintain it in the same statement that inserts the
> settlement.

---

## What to take from this chapter

**Copy:** a dedicated AR/AP subledger; sign-flipping payables so one aggregation serves both;
line-level `voucher_detail_no` provenance; deriving invoice status purely from outstanding + payment
schedule; ageing buckets from `due_date or posting_date`; the two-pass report algorithm (it exists
because a row can arrive before its target).

**Reject:** allocation implemented by cancelling/splitting/resubmitting the payment document; subledger
deleted and rebuilt on reconcile while the GL keeps stale `against_voucher`; `delinked` as a mutable
flag on history; `outstanding_amount` cached with an unlocked read-then-write; two different definitions
of "customer outstanding"; FX journals that deliberately violate account-currency balance; a
hard-coded 0.009 tolerance.
