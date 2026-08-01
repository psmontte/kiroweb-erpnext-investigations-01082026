# 11 — Advance Payments and Payment Allocation

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Advances and allocation are where ERPNext's data model breaks down most visibly, because the
same economic fact — "this money is applied to that obligation" — is represented in **five
different places** with no single source of truth. This document maps all five, explains the
allocation algorithms in full, and specifies our replacement.

---

## 1. The five representations of "money applied to an obligation"

| # | Representation | Table | Written by | Semantics |
|---|---|---|---|---|
| 1 | `Payment Entry Reference` child rows | `tabPayment Entry Reference` | `allocate_amount_to_references` (`accounts/doctype/payment_entry/payment_entry.py:1625`) | Intent, editable while draft |
| 2 | `Sales Invoice Advance` / `Purchase Invoice Advance` child rows | `tabSales Invoice Advance` etc. | `set_advances` (`accounts/services/advances.py:27`) | Invoice-side view of the same allocation |
| 3 | `Payment Ledger Entry` (PLE) | `tabPayment Ledger Entry` | `create_payment_ledger_entry` (`accounts/utils.py:2151`) | The ledger of record for outstanding |
| 4 | `Advance Payment Ledger Entry` | `tabAdvance Payment Ledger Entry` | order-side advance tracking | Feeds `advance_paid` on orders |
| 5 | `GL Entry.against_voucher` | `tabGL Entry` | `make_gl_entries` (`accounts/general_ledger.py:34`) | Historical, **goes stale** (§4.3) |

Plus three derived caches: `Invoice.outstanding_amount`, `Order.advance_paid`,
`Order.advance_payment_status`.

Eight places to describe one fact. Every reconciliation bug in ERPNext is a divergence between
two of them.

---

## 2. Advances pulled onto an invoice

### 2.1 `set_advances` — greedy fill, no user control

`accounts/services/advances.py:27`:

```python
res = get_advance_entries(doc, include_unallocated=not cint(doc.only_include_allocated_payments))
doc.set("advances", [])
advance_allocated = 0
for d in res:
    if party_account_currency == company_currency:
        amount = doc.base_rounded_total or doc.base_grand_total
    else:
        amount = doc.rounded_total or doc.grand_total
    allocated_amount = min(amount - advance_allocated, d.amount)
    advance_allocated += flt(allocated_amount)
    doc.append("advances", {... "advance_amount": flt(d.amount),
                            "allocated_amount": allocated_amount, ...})
```

Properties:

- **Greedy, first-come.** The order of `res` decides who gets consumed. `get_advance_entries`
  (`:62`) returns `journal_entries + payment_entries` — JVs always before PEs
  (`:103`), and within each group the ordering comes from
  `get_advance_journal_entries` (`:317`) / `get_advance_payment_entries` (`:379`) /
  `get_common_query` (`:423`). There is **no FIFO-by-date guarantee**, no oldest-first rule,
  no user-specified priority. Change an index and the allocation changes.
- **`allocated_amount` can go negative.** If `amount - advance_allocated` is already negative
  (because a previous row over-allocated due to rounding), `min()` returns the negative value
  and it is appended anyway. Nothing clamps at zero here.
- The comparison basis flips between company-currency total and transaction-currency total
  based on `party_account_currency == company_currency` (`:36`–`:39`) — so a multi-currency
  invoice allocates against a *different number* than a single-currency one.
- `only_include_allocated_payments` toggles whether unallocated advances are pulled at all.

`validate_advance_entries` (`:107`) does not enforce anything — it `msgprint`s a *suggestion*
that a payment linked to the same order "should perhaps" be pulled as advance (`:118`–`:124`).

### 2.2 Exchange gain/loss on advances

`set_advance_gain_or_loss` (`accounts/services/advances.py:128`):

```python
if conversion_rate == 1 or not advances: return
if get_account_currency(party_account) != doc.currency: return
for d in advances:
    if d.allocated_amount and doc.conversion_rate != d.ref_exchange_rate:
        d.exchange_gain_loss = (d.ref_exchange_rate * d.allocated_amount) \
                             - (doc.conversion_rate * d.allocated_amount)
```

The gain/loss is computed **per advance row** and posted via
`make_exchange_gain_loss_journal` (`controllers/accounts_controller.py:1011`), deduplicated by
`gain_loss_journal_already_booked` (`:1002`). The early return when
`get_account_currency(party_account) != doc.currency` means **gain/loss is silently skipped**
for the common case of a foreign-currency invoice booked to a company-currency receivable.

### 2.3 Order-side advance tracking

`calculate_total_advance_from_ledger` (`accounts/services/advances.py:148`):

```sql
SELECT ABS(SUM(amount)) AS amount, MAX(currency) AS account_currency
FROM `tabAdvance Payment Ledger Entry`
WHERE company = %s AND delinked = 0
  AND against_voucher_type = %s AND against_voucher_no = %s
```

`ABS(SUM(...))` — not `SUM(ABS(...))`. Mixed-sign rows (an advance and its reversal) net to
zero and then get `ABS`'d to zero, which is right; but a *net negative* set produces a positive
`advance_paid`. And `MAX(currency)` as a way to pick "the" currency of a multi-currency set is
arbitrary.

`set_total_advance_paid` (`:162`) writes `advance_paid` with `doc.db_set` and — note —
side-effects `party_account_currency` on the document with `frappe.db.set_value` (`:172`).
A read function that mutates two columns.

### 2.4 `advance_payment_status` — exact-equality bug

`set_advance_payment_status` (`accounts/services/advances.py:177`):

```python
paid_amount = frappe.get_value("Payment Request",
    filters={"reference_doctype": doc.doctype, "reference_name": doc.name, "docstatus": 1},
    fieldname=Sum(PaymentRequest.grand_total - PaymentRequest.outstanding_amount))

if not paid_amount:
    if receivable: new_status = "Not Requested" if paid_amount is None else "Requested"
    elif payable:  new_status = "Not Initiated" if paid_amount is None else "Initiated"
else:
    total_amount = doc.rounded_total or doc.grand_total
    new_status = "Fully Paid" if paid_amount == total_amount else "Partially Paid"
```

Three defects:

1. **`paid_amount == total_amount` is exact float equality on money.** `flt(...)` /
   `precision` is not applied. A payment of `999.999999999` against `1000.00` is
   `Partially Paid` forever. Every other comparison in ERPNext's money code goes through
   `flt(x, precision)`; this one does not.
2. `paid_amount is None` vs `paid_amount == 0` distinguishes "no Payment Request exists" from
   "a Payment Request exists but nothing paid". This depends on `Sum()` returning `NULL` for an
   empty set — a SQL-dialect detail encoded as business logic.
3. The status is derived **from Payment Requests, not from the ledger**. So an advance received
   by direct Payment Entry (no Payment Request) leaves the order at `Not Requested` even though
   `advance_paid` is non-zero. Two adjacent fields, computed from two different sources,
   routinely disagree.

Also: `Sales Order` uses `Requested`, `Purchase Order` uses `Initiated`
(`controllers/status_updater.py:57`, `:81`) — different enum values for the same state, which
then feed the `To Pay` status condition in each doctype's `status_map`.

`db_set(..., update_modified=False)` (`:203`) then `set_status(update=True)` and
`notify_update()` — three writes to a submitted document outside the lock.

### 2.5 Delinking advances

`delink_advance_entries` (`accounts/services/advances.py:209`) **hard-deletes** the
`* Advance` child rows matching the linked document and recomputes `total_advance` as a running
sum of the survivors, written with `update_modified=False` (`:223`). The record that an advance
*was* allocated is destroyed.

---

## 3. `allocate_amount_to_references` — the allocation algorithm in full

`accounts/doctype/payment_entry/payment_entry.py:1625`. This is the most intricate piece of
money logic in ERPNext. Reading it carefully is worth the effort because it is the behaviour we
must match or beat.

### 3.1 Phase 1 — classify outstanding

```python
paid_amount -= sum(flt(d.amount, precision) for d in self.deductions)   # :1647

for ref in self.references:
    if ref.outstanding_amount > 0: total_positive_outstanding_including_order += abs(...)
    else:                          total_negative_outstanding += abs(...)
```

`deductions` (bank charges, TDS, write-off) are subtracted from the pot **before** allocation,
so a deduction reduces what reaches invoices.

Positive outstanding = invoices/orders awaiting payment. Negative outstanding = credit notes,
overpayments, advances sitting the wrong way.

### 3.2 Phase 2 — size the two pots

Normal direction (`Receive`+`Customer`, or `Pay`+`Supplier`/`Employee`) (`:1662`–`:1671`):

```python
if total_positive_outstanding_including_order > paid_amount:
    remaining = flt(total_positive_outstanding_including_order - paid_amount, precision)
    allocated_negative_outstanding = min(remaining, total_negative_outstanding)
allocated_positive_outstanding = paid_amount + allocated_negative_outstanding
```

Reading this plainly: when the payment is **insufficient** to cover all positive outstanding,
ERPNext *pulls in credit notes* to bridge the gap — up to the size of the shortfall. The
positive pot becomes `paid + credits_applied`. So a €1 000 payment against €1 200 of invoices
and €300 of credit notes allocates €1 200 positive and €200 negative. Credit notes are
consumed **automatically and silently** as a side effect of a short payment.

Reverse direction (refund: `Pay`+`Customer`, `Receive`+`Supplier`) (`:1673`–`:1692`):

```python
if paid_amount > total_negative_outstanding:
    msgprint(...); return              # ← bails out, leaving allocations untouched
else:
    allocated_positive_outstanding = flt(total_negative_outstanding - paid_amount, precision)
    allocated_negative_outstanding = paid_amount + min(total_positive_outstanding_including_order,
                                                      allocated_positive_outstanding)
```

Note the **bare `return` after a `msgprint`** (`:1690`). Not a `throw`. The function exits with
whatever `allocated_amount` values were already on the rows. In a server-side call chain this
silently produces an unallocated or stale-allocated payment.

Also note `allocated_positive_outstanding` here is set to the *residual credit*, not to
anything "paid" — the variable is reused with an inverted meaning between the two branches.

### 3.3 Phase 3 — distribute (no Payment Request)

`_allocation_to_unset_pr_row` (`:1695`):

```python
if outstanding > 0 and allocated_positive_outstanding >= 0:
    row.allocated_amount = min(allocated_positive_outstanding, outstanding)
    allocated_positive_outstanding -= row.allocated_amount
elif outstanding < 0 and allocated_negative_outstanding:
    row.allocated_amount = min(allocated_negative_outstanding, abs(outstanding)) * -1
    allocated_negative_outstanding -= abs(row.allocated_amount)
```

Pure greedy in **child-row `idx` order**. No due-date priority, no discount-date awareness, no
oldest-first. The user's row ordering *is* the allocation policy.

When `paid_amount_change` is false, this runs for every reference and then
`allocate_open_payment_requests_to_references(...)` (`:1720`) attaches Payment Requests
afterwards.

### 3.4 Phase 4 — distribute with Payment Request priority

When `paid_amount_change` is true (`:1722` onward), there are **two passes**:

**Pass A — rows that already have `payment_request` set** (`:1729`–`:1782`). For each, the
allocation is a **triple minimum**:

```python
key = (ref.reference_doctype, ref.reference_name, ref.payment_term)
ref.allocated_amount = min(allocated_positive_outstanding,
                           references_outstanding_amounts[key],
                           payment_request_outstanding_amounts[ref.payment_request])
```

Three running budgets decremented in lockstep: the payment pot, the *payment-term-level*
outstanding, and the Payment Request's own outstanding. This is the closest ERPNext gets to a
proper allocation model — note the key includes `payment_term`, i.e. **allocation granularity
is the payment-schedule row, not the invoice**.

**Pass B — rows without a Payment Request** (`:1784`–`:1797`) get the leftovers via
`_allocation_to_unset_pr_row`, reading `remaining_references_allocated_amounts[key]` so they see
what Pass A consumed.

The negative branch of Pass A contains:

```python
remaining_references_allocated_amounts[key] += allocated_amount  # negative amount
```

with the comment admitting the sign convention is confusing (`:1776`). `+=` here where the
positive branch uses `flt(x - amount, precision)` — asymmetric and unrounded.

### 3.5 Supporting amount computation

- `set_amounts` (`accounts/doctype/payment_entry/payment_entry.py:953`) derives
  `paid_amount`/`received_amount`/`base_*` from the exchange rate and the references.
- `set_difference_amount` (`:1166`) computes the unallocated residue, which must be zero or
  land in `deductions`/`unallocated_amount`.

---

## 4. Reconciliation: cancel, split, resubmit

`reconcile_against_document` (`accounts/utils.py:516`). The docstring is the design:

> `Cancel PE or JV, Update against document, split if required and resubmit`

### 4.1 The flow

```python
for (voucher_type, voucher_no), entries in grouped:
    doc = frappe.get_doc(voucher_type, voucher_no)
    frappe.flags.ignore_party_validation = True
    for entry in entries:
        check_if_advance_entry_modified(entry)          # accounts/utils.py:589
        validate_allocated_amount(entry)                # accounts/utils.py:661
        if voucher_type == "Journal Entry":
            referenced_row = update_reference_in_journal_entry(entry, doc, do_not_save=False)
            doc.make_exchange_gain_loss_journal([entry], dimensions_dict)
        else:
            referenced_row = update_reference_in_payment_entry(entry, doc, do_not_save=True, ...)
            if referenced_row.outstanding_amount and entry.outstanding_amount is None:
                referenced_row.outstanding_amount -= flt(entry.allocated_amount)
            reposting_rows.append(referenced_row)

    doc.save(ignore_permissions=True)

    if voucher_type == "Payment Entry" and doc.book_advance_payments_in_separate_party_account:
        for row in reposting_rows: doc.make_advance_gl_entries(entry=row)
    else:
        _delete_pl_entries(voucher_type, voucher_no)      # accounts/utils.py:1719
        _delete_adv_pl_entries(voucher_type, voucher_no)  # accounts/utils.py:1724
        gl_map = doc.build_gl_map()
        process_debit_credit_difference(gl_map)           # accounts/general_ledger.py:397
        create_payment_ledger_entry(gl_map, update_outstanding="No", cancel=0, adv_adj=1)

    for entry in entries:
        update_voucher_outstanding(entry.against_voucher_type, entry.against_voucher,
                                   entry.account, entry.party_type, entry.party)
    frappe.flags.ignore_party_validation = False
```

### 4.2 What each step really does

**`update_reference_in_journal_entry`** (`accounts/utils.py:669`) — this is the "split":

- If `unadjusted_amount - allocated_amount != 0`, the existing `Journal Entry Account` row is
  **reduced in place** to the residual (`:684`–`:692`).
- Otherwise the row is **removed from the document** (`:694`–`:696`).
- Then a **new child row is appended** (`:699`), field-by-field copied from the old one using
  `get_fieldnames_with_value()` (`:702`–`:705`), carrying `reference_type`/`reference_name`
  pointing at the settled invoice, and `docstatus = 1` set manually (`:723`).
- `flags.ignore_validate_update_after_submit = True` (`:730`) and
  `flags.ignore_reposting_on_reconciliation = True` (`:732`).
- If the original row referenced an advance-payment doctype, the new row inherits
  `advance_voucher_type`/`advance_voucher_no` (`:725`–`:727`).
- Sign handling: if the row has an amount in the *reverse* dr/cr field, the direction and both
  amounts are negated (`:675`–`:682`).

So **allocating a payment rewrites the payment's own child rows on a submitted document**,
changing row identities. Any external reference to `Journal Entry Account.name` — including
`Payment Ledger Entry.voucher_detail_no` — is invalidated. Which is exactly why the next step
deletes and rebuilds the PLE.

**`_delete_pl_entries` / `_delete_adv_pl_entries`** — physical `DELETE` of the payment ledger
rows for the voucher (`accounts/utils.py:1719`, `:1724`). The ledger of record for outstanding
balances is **destroyed and re-derived** on every reconciliation.

**`create_payment_ledger_entry(..., adv_adj=1)`** — rebuilds it. The `adv_adj` flag is
significant: it **bypasses `check_freezing_date`**, so reconciliation can write payment-ledger
rows into a *closed accounting period* that a normal posting could not touch. Advance
adjustment is a privileged write path.

**`check_if_advance_entry_modified`** (`accounts/utils.py:589`) is the concurrency guard: it
re-reads the voucher and verifies the reference and amount still match, throwing
`PaymentEntryUnlinkError` (`accounts/utils.py:57`) otherwise. It is a read-then-check with no
lock — two concurrent reconciliations of the same payment can both pass it.

**`validate_allocated_amount`** (`accounts/utils.py:661`) is only two rules: not negative, and
not greater than `unadjusted_amount`, both at `System Settings.currency_precision`.

### 4.3 The GL goes stale

Critically, in the `Payment Entry` + `book_advance_payments_in_separate_party_account` branch,
only `make_advance_gl_entries` runs — **the GL Entry rows are not rebuilt**. And in the other
branch only PLE/APLE are deleted and rebuilt; `_delete_gl_entries`
(`accounts/utils.py:1729`) is *not* called.

So after reconciliation, `GL Entry.against_voucher` still points at whatever it pointed at when
the payment was first submitted. **`GL Entry.against_voucher` is not a reliable settlement
link.** Reports that join on it (aged receivables built on GL rather than PLE) drift.

This is the single strongest argument for our decision D8: settlement must be its *own* table,
not a column on the ledger.

---

## 5. Payment Reconciliation and Unreconcile

- **Payment Reconciliation** (a Single-ish tool doctype) gathers candidate invoices and
  payments, lets the user set `allocation` rows, and calls `reconcile_against_document`.
  It leans on `QueryPaymentLedger` (`accounts/utils.py:2273`) and `get_outstanding_invoices`
  (`accounts/utils.py:1251`), and honours `get_held_invoices` (`accounts/utils.py:1234`).
- **Unreconcile Payment** is the inverse. It exists precisely because un-allocation cannot be
  expressed as a compensating row: the only way back is to cancel/split/resubmit again.
  As shown in doc 09 §3.3, `_remove_references_in_unreconcile`
  (`controllers/accounts_controller.py:331`) **cancels and deletes** the `Unreconcile Payment`
  document when the underlying voucher is cancelled — destroying the audit trail of the
  un-allocation.
- `remove_ref_from_advance_section` (`accounts/utils.py:1018`),
  `remove_ref_doc_link_from_jv` (`:1042`), `remove_ref_doc_link_from_pe` (`:1084`), and
  `update_accounting_ledgers_after_reference_removal` (`:964`) implement the unlinking.
- `delink_original_entry` (`accounts/utils.py:2226`) flips `PLE.delinked = 1` — a soft delete
  on the ledger of record, with `partial_cancel` semantics.

---

## 6. Our model

### 6.1 One table for allocation (D8)

```sql
CREATE TABLE settlement (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              uuid NOT NULL REFERENCES company(id),

    -- the money side
    payment_voucher_id      uuid NOT NULL REFERENCES voucher(id),
    payment_ar_ap_entry_id  uuid NOT NULL REFERENCES ar_ap_entry(id),

    -- the obligation side, at payment-schedule granularity
    obligation_voucher_id   uuid NOT NULL REFERENCES voucher(id),
    obligation_schedule_id  uuid NOT NULL REFERENCES payment_schedule(id),

    party_type              party_type NOT NULL,
    party_id                uuid NOT NULL,
    account_id              uuid NOT NULL REFERENCES account(id),

    allocated_amount        numeric(19,4) NOT NULL,   -- account currency, signed
    allocated_amount_base   numeric(19,4) NOT NULL,   -- company currency, signed
    exchange_rate           numeric(21,9) NOT NULL,
    fx_gain_loss_base       numeric(19,4) NOT NULL DEFAULT 0,

    effective_date          date NOT NULL,            -- when the settlement is effective
    posted_at               timestamptz NOT NULL DEFAULT now(),
    reverses_settlement_id  uuid UNIQUE REFERENCES settlement(id),
    reason_code             text,
    created_by              uuid NOT NULL REFERENCES app_user(id),

    CONSTRAINT settlement_nonzero CHECK (allocated_amount <> 0),
    CONSTRAINT settlement_reversal_sign CHECK (
        reverses_settlement_id IS NULL OR TRUE   -- sign checked by trigger against target
    )
);
```

Properties, contrasted with ERPNext:

| Property | ERPNext | Ours |
|---|---|---|
| Where allocation lives | 5 tables + 3 caches | 1 table |
| Granularity | invoice, *sometimes* payment-term | always `payment_schedule` row |
| Un-allocate | cancel/split/resubmit the payment | insert compensating row |
| Row identity stability | rewritten on every reconcile | never mutated |
| Audit of who/why | none (destroyed on cancel) | `created_by`, `reason_code`, `posted_at` |
| Point-in-time state | impossible | `WHERE posted_at <= t` |
| Closed-period bypass | `adv_adj=1` silently bypasses freeze | `effective_date` validated against period; a closed period requires an explicit `period_reopen` grant recorded in `period_override` |
| GL link freshness | `against_voucher` goes stale | no ledger column to go stale |
| Double-allocation race | read-then-check, no lock | see §6.3 |

### 6.2 Outstanding as a view (D9)

```sql
CREATE VIEW schedule_outstanding AS
SELECT
    ps.id                                    AS payment_schedule_id,
    ps.voucher_id,
    ps.company_id,
    ps.party_type, ps.party_id, ps.account_id,
    ps.due_date,
    ps.discount_date, ps.discount_amount,
    ps.amount                                AS scheduled_amount,
    COALESCE(s.allocated, 0)                 AS allocated_amount,
    ps.amount - COALESCE(s.allocated, 0)     AS outstanding_amount
FROM payment_schedule ps
LEFT JOIN (
    SELECT obligation_schedule_id, SUM(allocated_amount) AS allocated
    FROM settlement GROUP BY obligation_schedule_id
) s ON s.obligation_schedule_id = ps.id;
```

`voucher_outstanding` aggregates that per voucher. Aged analysis is a `date_trunc`/bucket over
the same view. There is no `update_voucher_outstanding` (`accounts/utils.py:2175`) equivalent,
no repost queue, no `delinked` flag, and no lost-update race (doc 04 §6).

### 6.3 Over-allocation, enforced by the database

A **deferred constraint trigger** on `settlement`:

```
for each touched obligation_schedule_id:
    scheduled  := (SELECT amount FROM payment_schedule WHERE id = ...)
    allocated  := (SELECT COALESCE(SUM(allocated_amount),0) FROM settlement
                   WHERE obligation_schedule_id = ... FOR UPDATE of payment_schedule row)
    IF sign(scheduled) * allocated > abs(scheduled) + 0.00005 THEN RAISE
for each touched payment_ar_ap_entry_id:
    same check against the payment's own amount
```

The trigger takes `SELECT ... FOR UPDATE` on the `payment_schedule` row, which serialises
concurrent allocations against the same obligation. `DEFERRABLE INITIALLY DEFERRED` means a
transaction that temporarily over-allocates while re-shuffling is fine, but the committed
state never is. ERPNext's `validate_allocated_amount` (`accounts/utils.py:661`) can be passed
concurrently by two sessions.

### 6.4 Advance is not a special case

An advance is a `settlement` row whose `obligation_schedule_id` points at a **schedule row on
the order**, not the invoice. Orders get `payment_schedule` rows too (down-payment terms).
When the invoice is raised, the advance is *transferred* by two settlement rows:
one negating the order allocation, one allocating to the invoice schedule — both in the same
transaction, both carrying `reason_code = 'advance_transfer'` and a shared
`transfer_group_id`. Nothing is deleted, nothing is rewritten, and the history reads
correctly at every point in time.

`advance_paid` on an order becomes:

```sql
CREATE VIEW order_advance AS
SELECT ps.voucher_id, SUM(s.allocated_amount_base) AS advance_paid_base
FROM settlement s JOIN payment_schedule ps ON ps.id = s.obligation_schedule_id
WHERE ps.is_advance_term
GROUP BY ps.voucher_id;
```

and `advance_payment_status` becomes a derived expression comparing that view to the order
total **with explicit rounding to the currency's minor unit**, not float equality (§2.4 defect 1).
It is derived from the *same* source as `advance_paid`, so the two can never disagree
(§2.4 defect 3). One enum, shared by sales and purchase (§2.4 defect: `Requested` vs
`Initiated`), with direction taken from `party_type`.

### 6.5 Allocation policy as data, not row order

ERPNext's policy is "child-row `idx` order, with Payment-Request rows first". Ours:

```sql
CREATE TABLE allocation_policy (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    party_type    party_type,
    party_id      uuid,
    strategy      allocation_strategy NOT NULL,  -- 'oldest_due_first','discount_first',
                                                 -- 'largest_first','proportional','manual'
    honour_discount_date  boolean NOT NULL DEFAULT true,
    allow_credit_note_offset boolean NOT NULL DEFAULT false,
    max_underpay_writeoff numeric(19,4) NOT NULL DEFAULT 0,
    priority      integer NOT NULL,
    UNIQUE (company_id, party_type, party_id, priority)
);
```

The allocation *engine* is deterministic given (policy, open schedules, amount) and produces
a proposed set of `settlement` rows that the user may override before posting. Two consequences:

- **Reproducible.** Same inputs → same allocation, independent of index order or row shuffling.
- `allow_credit_note_offset` makes ERPNext's silent credit-note consumption (§3.2) an
  **explicit, per-party opt-in** rather than an emergent property of a `min()` expression.
- `proportional` and `discount_first` strategies are expressible; ERPNext has neither.

### 6.6 Deductions are separate

`paid_amount -= sum(deductions)` (`accounts/doctype/payment_entry/payment_entry.py:1647`)
conflates "money I received" with "money I allocated". We split them:
`payment_voucher.received_amount` is what hit the bank; `payment_deduction` rows
(bank charge, withholding, write-off) each post their own GL line and carry their own
`account_id` and `reason_code`; `Σ settlement + Σ deduction = received_amount` is a
constraint-trigger invariant (S2 in the register). No arithmetic happens implicitly inside
an allocation routine.

---

## 7. Invariants we enforce

- **S1.** `Σ settlement.allocated_amount` per `obligation_schedule_id` never exceeds the
  schedule amount in absolute value, and never flips its sign. (Deferred trigger, row-locked.)
- **S2.** `Σ settlement.allocated_amount` per `payment_ar_ap_entry_id` + `Σ payment_deduction`
  = the payment's `amount`. (Deferred trigger.)
- **S3.** `reverses_settlement_id` is `UNIQUE`; the reversal's `allocated_amount` equals the
  negation of the target's, same `obligation_schedule_id`, same `account_id`. (Trigger.)
- **S4.** `settlement.company_id` equals the `company_id` of both referenced vouchers and the
  schedule. (Composite FK on `(id, company_id)`.)
- **S5.** `settlement.effective_date` falls in an open `accounting_period` unless an active
  `period_override` grant covers it, recorded with `granted_by`/`granted_at`.
- **S6.** `payment_schedule` amounts sum to the voucher's `grand_total` (doc 04); therefore
  `Σ settlement` per voucher can never exceed the voucher total either — S1 composes upward
  without a second check.
- **S7.** `settlement` is append-only: `REVOKE UPDATE, DELETE`, plus a trigger that raises.

---

Cross-references: doc 04 (AR/AP and settlement as ERPNext models it), doc 09 (lifecycle,
cancellation side effects), doc 10 (fulfilment links — the same "one fact, one table" argument
applied to quantities), doc 14 (banking, Payment Requests, collections),
`docs/design/FINAL-SCHEMA.md` §Settlement model.
