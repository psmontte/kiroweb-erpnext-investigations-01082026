# S02 — Payments Against Invoices: Allocation, Advances, Part Payment, Un-allocation

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev). Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.
>
> Continues **[S01](S01-order-to-cash.md)**. Where S01 traced goods and revenue, this traces
> **money** — and this is the flow with the most moving parts in the whole system.

---

## 1. Starting position

From S01, customer **ACME** owes:

| Invoice | Grand total | Outstanding | Due |
|---|---:|---:|---|
| SI-0001 | 35 400.00 | 35 400.00 | 2026-07-15 |
| SI-0002 | 32 450.00 | 32 450.00 | 2026-08-15 |
| SI-0003 (older) | 12 000.00 | 12 000.00 | **2026-06-30 — overdue** |
| CN-0001 (credit note, the return) | −5 900.00 | −5 900.00 | — |
| | | **74 950.00 net** | |

`SI-0002` has a payment schedule with two terms (50 % / 50 %) — this matters, because allocation
granularity is the payment-term row, not the invoice.

We will trace:

1. Exact payment of SI-0001
2. Part payment of SI-0003
3. One payment covering SI-0002 + SI-0003, with a bank charge
4. The credit note being silently consumed
5. An advance received before an invoice exists
6. Un-allocating a wrong allocation
7. Over-payment

---

## 2. The five places an allocation is recorded

Before tracing, the map (doc 11 §1). One economic fact — *this money is applied to that
obligation* — is written to:

| # | Table | Written by |
|---|---|---|
| 1 | `tabPayment Entry Reference` | `allocate_amount_to_references` (`accounts/doctype/payment_entry/payment_entry.py:1625`) |
| 2 | `tabSales Invoice Advance` | `set_advances` (`accounts/services/advances.py:27`) |
| 3 | `tabPayment Ledger Entry` | `create_payment_ledger_entry` (`accounts/utils.py:2151`) |
| 4 | `tabAdvance Payment Ledger Entry` | order-side advance tracking |
| 5 | `tabGL Entry.against_voucher` | `make_gl_entries` (`accounts/general_ledger.py:34`) |

Plus caches: `Sales Invoice.outstanding_amount`, `Sales Order.advance_paid`,
`Sales Order.advance_payment_status`, `Payment Request.outstanding_amount`.

**Nine places. One fact.** Every reconciliation bug is a divergence between two of them.

---

## 3. Scenario A — exact payment of SI-0001 (35 400.00)

### 3.1 Draft: allocation is computed, not chosen

Payment Entry PE-0001: `payment_type='Receive'`, `party_type='Customer'`, `party='ACME'`,
`paid_amount=35 400`, `paid_to=<Bank>`, one reference row → SI-0001.

`allocate_amount_to_references(paid_amount=35400, paid_amount_change=False, allocate_payment_amount=True)`
(`accounts/doctype/payment_entry/payment_entry.py:1625`):

**Phase 1 — classify** (`:1646`–`:1657`):
```python
paid_amount -= sum(flt(d.amount, precision) for d in self.deductions)   # 35400 − 0
total_positive_outstanding_including_order = 35 400      # SI-0001
total_negative_outstanding                 = 0
```

**Phase 2 — size the pots** (`:1662`–`:1671`), normal direction (`Receive` + `Customer`):
```python
if total_positive_outstanding (35400) > paid_amount (35400):   # False
    ...                                                        # skipped
allocated_positive_outstanding = 35400 + 0 = 35400
allocated_negative_outstanding = 0
```

**Phase 3 — distribute** via `_allocation_to_unset_pr_row` (`:1695`):
```python
row.allocated_amount = min(35400, 35400) = 35400
allocated_positive_outstanding = 0
```

Then `set_amounts` (`:953`) and `set_difference_amount` (`:1166`) confirm nothing is unallocated.

⚠️ Distribution is **greedy in child-row `idx` order** (doc 11 §3.3). No oldest-first, no
due-date priority, no discount awareness. **The user's row ordering *is* the allocation policy.**

### 3.2 Submit — what gets written

| Table | Rows |
|---|---|
| `tabPayment Entry` | 1 — `docstatus=1`, `paid_amount=35400`, `unallocated_amount=0` |
| `tabPayment Entry Reference` | 1 — `reference_doctype='Sales Invoice'`, `reference_name='SI-0001'`, `total_amount=35400`, `outstanding_amount=35400`, `allocated_amount=35400` |
| `tabGL Entry` | 2 |
| `tabPayment Ledger Entry` | 1 |

GL:

| Account | Debit | Credit | `against_voucher` |
|---|---:|---:|---|
| Bank | 35 400.00 | | |
| Debtors (ACME) | | 35 400.00 | **SI-0001** |

PLE (`create_payment_ledger_entry`, `accounts/utils.py:2151`):

| Column | Value |
|---|---|
| `voucher_type` / `voucher_no` | Payment Entry / PE-0001 |
| `against_voucher_type` / `against_voucher_no` | **Sales Invoice / SI-0001** |
| `account` | Debtors |
| `amount` | **−35 400.00** |
| `delinked` | 0 |

Then `update_voucher_outstanding('Sales Invoice','SI-0001', ...)` (`accounts/utils.py:2175`):

```
outstanding = Σ PLE.amount WHERE against_voucher_no = 'SI-0001' AND delinked = 0
            = +35 400 (invoice) + (−35 400) (payment) = 0
→ frappe.db.set_value('Sales Invoice','SI-0001','outstanding_amount', 0)
→ status = 'Paid'                (accounts/doctype/sales_invoice/sales_invoice.py:1174)
```

⚠️ **That is a read-then-write with no lock** (doc 04 §6). Two payments committing against the
same invoice concurrently both read the pre-payment PLE set and both write a wrong
`outstanding_amount`. The PLE rows are correct; the cached column is not.

---

## 4. Scenario B — part payment of SI-0003 (5 000 of 12 000)

Same path, one difference in Phase 3:

```python
row.allocated_amount = min(allocated_positive_outstanding=5000, outstanding=12000) = 5000
```

| Table | Effect |
|---|---|
| `tabPayment Entry Reference` | `allocated_amount = 5 000`, `outstanding_amount = 12 000` (as-at-draft snapshot) |
| `tabPayment Ledger Entry` | `amount = −5 000`, `against_voucher_no = 'SI-0003'` |
| `Sales Invoice.outstanding_amount` | 12 000 → **7 000** |
| `Sales Invoice.status` | `'Overdue'` → stays `'Overdue'` (partly paid + past due) |

Note `Payment Entry Reference.outstanding_amount` is a **snapshot taken when the payment was
drafted**. It is not refreshed. If another payment lands first, this row's stored outstanding is
stale — and `check_if_advance_entry_modified` (`accounts/utils.py:589`) is the guard that is
supposed to catch it, a read-then-check with no lock.

---

## 5. Scenario C — one payment, two invoices, plus a bank charge

PE-0003: received **44 000** in the bank. Bank charged **450**. So the customer actually paid
44 450, and we allocate 44 450 across SI-0002 (32 450) and SI-0003 (7 000 remaining).

`deductions` child row: Bank Charges 450.

**Phase 1** (`:1647`):
```python
paid_amount = 44450 − 450 = 44000       # ← deduction subtracted BEFORE allocation
```

Wait — that is the point. `paid_amount` entered is 44 450 (what the customer sent);
the deduction reduces the pot to 44 000, which is what hit the bank. Allocation therefore
distributes **44 000**, not 44 450:

```
SI-0002: min(44000, 32450) = 32 450 ;  remaining pot = 11 550
SI-0003: min(11550,  7000) =  7 000 ;  remaining pot =  4 550
unallocated_amount = 4 550
```

⚠️ **The arithmetic is direction-dependent and easy to get wrong.** `paid_amount −= deductions`
(`:1647`) conflates "money received" with "money allocatable". Whether the 450 comes off the
customer's obligation or off our bank receipt depends entirely on what number the user typed into
`paid_amount` — and the document has no field that distinguishes the two.

GL:

| Account | Debit | Credit | `against_voucher` |
|---|---:|---:|---|
| Bank | 44 000.00 | | |
| Bank Charges (expense) | 450.00 | | |
| Debtors (ACME) | | 32 450.00 | SI-0002 |
| Debtors (ACME) | | 7 000.00 | SI-0003 |
| Debtors (ACME) — unallocated | | 4 550.00 | *(none)* |

PLE: three rows (−32 450 / −7 000 / −4 550), the last with `against_voucher_no = NULL` — an
on-account credit sitting on the customer.

### 5.1 Payment-term granularity

SI-0002 has two payment-schedule rows (16 225 each). When `paid_amount_change` is true, the
**Payment-Request-priority pass** runs (`:1729`–`:1782`) and the key becomes:

```python
key = (ref.reference_doctype, ref.reference_name, ref.get("payment_term"))
ref.allocated_amount = min(allocated_positive_outstanding,
                           references_outstanding_amounts[key],
                           payment_request_outstanding_amounts[ref.payment_request])
```

A **triple minimum** over three independently-decremented budgets. This is the closest ERPNext
gets to a correct allocation model — and it only engages when a Payment Request exists and
`paid_amount_change` is true. Otherwise (§3.1) allocation is invoice-level and greedy.

---

## 6. Scenario D — the credit note gets consumed silently

Now pay **60 000** against SI-0002 (32 450) + SI-0003 (7 000) with CN-0001 (−5 900) also in the
reference table.

**Phase 1**:
```
total_positive_outstanding_including_order = 32 450 + 7 000 = 39 450
total_negative_outstanding                 = 5 900
```

**Phase 2** (`:1662`–`:1671`):
```python
if total_positive_outstanding (39 450) > paid_amount (60 000):    # False
```
so no credit is pulled. Fine. But **reduce the payment to 35 000**:

```python
if 39 450 > 35 000:                                   # True
    remaining_outstanding = 39 450 − 35 000 = 4 450
    allocated_negative_outstanding = min(4 450, 5 900) = 4 450
allocated_positive_outstanding = 35 000 + 4 450 = 39 450
```

**Read that plainly: because the payment was short by 4 450, ERPNext automatically consumed
4 450 of the credit note to close the gap.** The user did not ask for it. There is no setting, no
confirmation, no flag — it is an emergent property of a `min()` expression (doc 11 §3.2).

Result: both invoices fully allocated, CN-0001 partially consumed (−4 450 of −5 900),
1 450 of credit left.

### 6.1 Reverse direction bails out silently

For a refund (`Pay` + `Customer`), the other branch (`:1673`–`:1692`):

```python
if paid_amount > total_negative_outstanding:
    frappe.msgprint("Paid Amount cannot be greater than total negative outstanding amount {0}")
    return                      # ← bare return after a msgprint, NOT a throw
```

`msgprint` + `return` (`:1690`) leaves whatever `allocated_amount` values were already on the
rows. In a server-side call chain that produces a silently mis-allocated payment.

---

## 7. Scenario E — advance received before the invoice

Customer prepays **20 000** against SO-0001.

### 7.1 The payment

PE-0005: `payment_type='Receive'`, reference row → **Sales Order SO-0001**,
`allocated_amount = 20 000`.

GL:

| Account | Debit | Credit |
|---|---:|---:|
| Bank | 20 000.00 | |
| Debtors — or **Advance Received** if `book_advance_payments_in_separate_party_account` | | 20 000.00 |

Two configurations, two different accounts, two different downstream code paths. The separate-
account mode changes what `reconcile_against_document` does (§9.2).

`Advance Payment Ledger Entry`: `against_voucher_type='Sales Order'`,
`against_voucher_no='SO-0001'`, `amount=−20 000`.

Then `set_total_advance_paid` (`accounts/services/advances.py:162`) →
`calculate_total_advance_from_ledger` (`:148`):

```sql
SELECT ABS(SUM(amount)) AS amount, MAX(currency) AS account_currency
FROM `tabAdvance Payment Ledger Entry`
WHERE company = ? AND delinked = 0
  AND against_voucher_type = 'Sales Order' AND against_voucher_no = 'SO-0001'
-- → 20 000
```
→ `Sales Order.advance_paid = 20 000`.

⚠️ `ABS(SUM(...))`, not `SUM(ABS(...))`. A net-negative set yields a positive `advance_paid`.
And `MAX(currency)` picks "the" currency of a multi-currency set arbitrarily.

### 7.2 `advance_payment_status` — the exact-equality bug

`set_advance_payment_status` (`accounts/services/advances.py:177`):

```python
paid_amount = frappe.get_value("Payment Request",
    filters={"reference_doctype": doc.doctype, "reference_name": doc.name, "docstatus": 1},
    fieldname=Sum(PaymentRequest.grand_total - PaymentRequest.outstanding_amount))
if not paid_amount:
    new_status = "Not Requested" if paid_amount is None else "Requested"     # receivable
else:
    total_amount = doc.get("rounded_total") or doc.get("grand_total")
    new_status = "Fully Paid" if paid_amount == total_amount else "Partially Paid"
```

Three defects, all live:

1. **`paid_amount == total_amount` is raw float equality on money.** No `flt(x, precision)`.
   999.999999999 vs 1000.00 → `Partially Paid` forever.
2. `paid_amount is None` vs `== 0` distinguishes "no Payment Request" from "one exists, unpaid" —
   business logic riding on `SUM()` returning `NULL` for an empty set.
3. **It is derived from Payment Requests, not from the ledger.** Our PE-0005 had no Payment
   Request, so `advance_payment_status` stays `'Not Requested'` while `advance_paid = 20 000`.
   **Two adjacent fields, two sources, routinely disagreeing.**

Also: Sales Order uses `'Requested'`, Purchase Order uses `'Initiated'`
(`controllers/status_updater.py:57`, `:81`) — same concept, different enum values, each wired into
its own `status_map` `'To Pay'` condition.

### 7.3 Invoice raised — the advance is pulled

SI-0004 for SO-0001. In `validate`, `set_advances`
(`controllers/accounts_controller.py:969` → `accounts/services/advances.py:27`):

```python
res = get_advance_entries(doc, include_unallocated=not cint(doc.only_include_allocated_payments))
doc.set("advances", [])
advance_allocated = 0
for d in res:
    amount = doc.base_rounded_total or doc.base_grand_total   # or FC total, depending on currency
    allocated_amount = min(amount - advance_allocated, d.amount)
    advance_allocated += flt(allocated_amount)
    doc.append("advances", {... "advance_amount": flt(d.amount),
                            "allocated_amount": allocated_amount, ...})
```

`get_advance_entries` (`:62`) returns `journal_entries + payment_entries` — **JVs always before
PEs** (`:103`), and within each group whatever order `get_advance_journal_entries` (`:317`) /
`get_advance_payment_entries` (`:379`) / `get_common_query` (`:423`) produce. **No FIFO-by-date
guarantee. Change an index and the allocation changes.**

Then on submit, `update_against_document_in_jv`
(`controllers/accounts_controller.py:1023`) → `reconcile_against_document`
(`accounts/utils.py:516`) links the advance to the invoice. See §9.

### 7.4 FX gain/loss on the advance

`set_advance_gain_or_loss` (`accounts/services/advances.py:128`):

```python
if doc.get("conversion_rate") == 1 or not doc.get("advances"): return
if get_account_currency(party_account) != doc.currency: return          # ← silent skip
for d in doc.get("advances"):
    if d.allocated_amount and doc.conversion_rate != d.ref_exchange_rate:
        d.exchange_gain_loss = (d.ref_exchange_rate * d.allocated_amount) \
                             - (doc.conversion_rate * d.allocated_amount)
```

The second early return means **gain/loss is silently skipped** for the common case of a
foreign-currency invoice booked to a company-currency receivable.

---

## 8. Scenario F — un-allocating a wrong allocation

The 7 000 was allocated to SI-0003; it should have gone to SI-0005.

There is **no "move allocation" operation**. Three options:

### 8.1 Cancel and re-enter the payment

`AccountsController.on_cancel` (`controllers/accounts_controller.py:1109`):

```python
remove_from_bank_transaction(self.doctype, self.name)        # doc 14 §1.3
cancel_exchange_gain_loss_journal(self)                      # accounts/utils.py:847
cancel_common_party_journal(self)                            # accounts/utils.py:924
if Accounts Settings.unlink_payment_on_cancellation_of_invoice:
    unlink_ref_doc_from_payment_entries(self)                # accounts/utils.py:1035
```

GL reversal: `make_reverse_gl_entries` (`accounts/general_ledger.py:607`) writes **negated
copies with `is_cancelled = 1`**, then `set_as_cancel` (`:728`) marks the originals
`is_cancelled = 1`. Every downstream report must filter `is_cancelled = 0` (doc 01 §7).

PLE: `delink_original_entry` (`accounts/utils.py:2226`) sets `delinked = 1` — a soft delete on the
ledger of record.

Then re-enter the whole payment. Bank reconciliation must be redone (doc 14 §1.3 —
`clearance_date` is wiped).

### 8.2 `Unreconcile Payment`

`accounts/doctype/unreconcile_payment/unreconcile_payment.py:20` —
`get_allocations_from_payment` (`:46`), `add_references` (`:53`), `on_submit` (`:59`),
`get_linked_payments_for_doc` (`:105`), `get_linked_advances` (`:175`).

It calls `unlink_ref_doc_from_payment_entries` → `remove_ref_doc_link_from_pe`
(`accounts/utils.py:1084`) → `update_accounting_ledgers_after_reference_removal`
(`accounts/utils.py:964`), which **UPDATEs the payment's child rows** to blank the reference and
rewrites GL/PLE.

⚠️ And per doc 09 §3.3: `AccountsController._remove_references_in_unreconcile`
(`controllers/accounts_controller.py:331`) **cancels and deletes** the `Unreconcile Payment`
document (`:355`–`:361`) if the underlying voucher is ever cancelled. **The audit record of the
un-allocation is destroyed.**

### 8.3 Payment Reconciliation tool

Re-allocates via `reconcile_against_document` (§9), which is the same cancel/split/resubmit
machinery.

---

## 9. `reconcile_against_document` — the machine behind all of it

`accounts/utils.py:516`. Its docstring is the design:

> `Cancel PE or JV, Update against document, split if required and resubmit`

### 9.1 The flow

```python
for (voucher_type, voucher_no), entries in grouped:
    doc = frappe.get_doc(voucher_type, voucher_no)
    frappe.flags.ignore_party_validation = True
    for entry in entries:
        check_if_advance_entry_modified(entry)          # :589  ← read-then-check, no lock
        validate_allocated_amount(entry)                # :661  ← ≥0 and ≤ unadjusted only
        if voucher_type == "Journal Entry":
            referenced_row = update_reference_in_journal_entry(entry, doc, do_not_save=False)   # :669
            doc.make_exchange_gain_loss_journal([entry], dimensions_dict)
        else:
            referenced_row = update_reference_in_payment_entry(entry, doc, do_not_save=True, ...)  # :743
            reposting_rows.append(referenced_row)
    doc.save(ignore_permissions=True)

    if voucher_type == "Payment Entry" and doc.book_advance_payments_in_separate_party_account:
        for row in reposting_rows: doc.make_advance_gl_entries(entry=row)
    else:
        _delete_pl_entries(voucher_type, voucher_no)       # :1719  ← PHYSICAL DELETE
        _delete_adv_pl_entries(voucher_type, voucher_no)   # :1724  ← PHYSICAL DELETE
        gl_map = doc.build_gl_map()
        process_debit_credit_difference(gl_map)             # accounts/general_ledger.py:397
        create_payment_ledger_entry(gl_map, update_outstanding="No", cancel=0, adv_adj=1)

    for entry in entries:
        update_voucher_outstanding(entry.against_voucher_type, entry.against_voucher,
                                   entry.account, entry.party_type, entry.party)
```

### 9.2 Three findings that matter operationally

**(a) The payment's own child rows are rewritten.**
`update_reference_in_journal_entry` (`:669`): if the allocation is partial, the existing row is
**reduced in place** to the residual (`:684`–`:692`); if full, the row is **removed** (`:694`–`:696`);
then a **new child row is appended** (`:699`), field-by-field copied via
`get_fieldnames_with_value()` (`:702`–`:705`), with `docstatus = 1` set by hand (`:723`) and
`flags.ignore_validate_update_after_submit = True` (`:730`).

So **allocating a payment changes the row identities inside a submitted payment document.** Any
external reference to `Journal Entry Account.name` — including
`Payment Ledger Entry.voucher_detail_no` — is invalidated. Which is exactly why the next step has
to delete and rebuild the PLE.

**(b) The ledger of record for outstanding is destroyed and re-derived on every reconciliation.**
`_delete_pl_entries` / `_delete_adv_pl_entries` are physical `DELETE`s.

**(c) `adv_adj=1` bypasses the period freeze.** Advance adjustment is a **privileged write path**
that can put payment-ledger rows into a closed accounting period that a normal posting could not
touch.

**(d) `GL Entry.against_voucher` goes stale.** Note `_delete_gl_entries`
(`accounts/utils.py:1729`) is **not** called in either branch. So after reconciliation, the GL
still points wherever it pointed at first submit. **`GL Entry.against_voucher` is not a reliable
settlement link** — aged-receivable reports built on GL drift, while the same reports built on PLE
are correct (doc 11 §4.3). Two reports, same question, different answers.

---

## 10. Scenario G — over-payment

Customer pays 100 000 against 74 950 of net outstanding.

- Allocation fills every positive reference, then `unallocated_amount = 25 050`.
- GL: Debtors credited 100 000 in total; the unallocated 25 050 has **no `against_voucher`**.
- PLE: a row with `against_voucher_no = NULL` — an on-account credit.
- `Customer.outstanding` (aggregate) goes negative by 25 050.

There is no `advance_from_overpayment` object and no dedicated "customer credit balance" entity.
The credit exists as an unlinked PLE row, discoverable through `QueryPaymentLedger`
(`accounts/utils.py:2273`) / `get_outstanding_invoices` (`accounts/utils.py:1251`), and honoured
or not by `get_held_invoices` (`accounts/utils.py:1234`).

---

## 11. Complete write trace, all scenarios

| Scenario | PE Ref rows | GL rows | PLE rows | Cached columns written |
|---|---:|---:|---:|---|
| A exact payment | 1 | 2 | 1 | `SI.outstanding_amount`, `SI.status` |
| B part payment | 1 | 2 | 1 | same |
| C 2 invoices + charge | 2 | 5 | 3 | 2 × (`outstanding_amount`, `status`) |
| D credit-note consumption | 3 | 5 | 3 | 3 × |
| E advance + invoice | 1 → rewritten | 2 + reversal + rebuild | 1 → **deleted + rebuilt** | `SO.advance_paid`, `SO.advance_payment_status`, `SO.status`, `SI.outstanding_amount`, `SI.status`, `SI.total_advance` |
| F un-allocation | rows **rewritten** | reversal pair + rebuild | **deleted + rebuilt**, or `delinked=1` | same set again |
| G over-payment | N | N+1 | N+1 | N × |

Note E and F: **the payment document is edited, its ledger rows are deleted, and both are
rebuilt.** That is the operation ERPNext performs when you allocate a payment.

---

## 12. Same scenarios in our design

### 12.1 One table (D8)

```sql
CREATE TABLE settlement (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              uuid NOT NULL REFERENCES company(id),
    payment_voucher_id      uuid NOT NULL REFERENCES voucher(id),
    payment_ar_ap_entry_id  uuid NOT NULL REFERENCES ar_ap_entry(id),
    obligation_voucher_id   uuid NOT NULL REFERENCES voucher(id),
    obligation_schedule_id  uuid NOT NULL REFERENCES payment_schedule(id),   -- ← term granularity, always
    party_type              party_type NOT NULL,
    party_id                uuid NOT NULL,
    account_id              uuid NOT NULL REFERENCES account(id),
    allocated_amount        numeric(19,4) NOT NULL,
    allocated_amount_base   numeric(19,4) NOT NULL,
    exchange_rate           numeric(21,9) NOT NULL,
    fx_gain_loss_base       numeric(19,4) NOT NULL DEFAULT 0,
    effective_date          date NOT NULL,
    posted_at               timestamptz NOT NULL DEFAULT now(),
    reverses_settlement_id  uuid UNIQUE REFERENCES settlement(id),
    reason_code             text,
    created_by              uuid NOT NULL REFERENCES app_user(id),
    CONSTRAINT settlement_nonzero CHECK (allocated_amount <> 0)
);
```

Append-only. `REVOKE UPDATE, DELETE` + a `BEFORE UPDATE OR DELETE` trigger that raises (S7).

### 12.2 Scenario A

```sql
BEGIN;
INSERT INTO voucher (id, doc_type, doc_no, lifecycle_state, ...) VALUES (:pe, 'payment', 'PE-0001', 'posted', ...);
INSERT INTO gl_entry VALUES (:pe, :bank, 35400, 0), (:pe, :debtors, 0, 35400);
INSERT INTO ar_ap_entry (id, voucher_id, party_type, party_id, account_id, amount_base)
     VALUES (:pe_arap, :pe, 'customer', :acme, :debtors, -35400.00);
INSERT INTO settlement (payment_voucher_id, payment_ar_ap_entry_id,
                        obligation_voucher_id, obligation_schedule_id,
                        allocated_amount, allocated_amount_base, effective_date, created_by, reason_code)
     VALUES (:pe, :pe_arap, :si1, :si1_sched_1, 35400.00, 35400.00, current_date, :user, 'manual');
COMMIT;
```

Nothing else. `outstanding_amount` is **not written** — it is:

```sql
SELECT outstanding_amount FROM voucher_outstanding WHERE voucher_id = :si1;   -- 0.00
SELECT * FROM schedule_outstanding WHERE payment_schedule_id = :si1_sched_1;
```

`status` is a view over `schedule_outstanding` + `fulfilment_doc` (doc 10 §5.3). No
`update_voucher_outstanding`, no race (§3.2).

### 12.3 Over-allocation is a database invariant (S1)

Deferred constraint trigger on `settlement`:

```
for each touched obligation_schedule_id:
    SELECT amount FROM payment_schedule WHERE id = ... FOR UPDATE;     -- ← real lock
    allocated := (SELECT COALESCE(SUM(allocated_amount),0) FROM settlement WHERE obligation_schedule_id = ...);
    IF sign(scheduled) * allocated > abs(scheduled) + 0.00005 THEN RAISE;
for each touched payment_ar_ap_entry_id:
    same check against the payment's own amount;                       -- S2
```

`DEFERRABLE INITIALLY DEFERRED`, so intra-transaction reshuffling is fine but the **committed**
state never over-allocates. ERPNext's `validate_allocated_amount` (`accounts/utils.py:661`) can be
passed concurrently by two sessions; this cannot.

### 12.4 Scenario C — deductions are separate (S2)

```sql
INSERT INTO payment_voucher (id, received_amount) VALUES (:pe3, 44000.00);
INSERT INTO payment_deduction (payment_voucher_id, account_id, amount, reason_code)
     VALUES (:pe3, :bank_charges, 450.00, 'bank_charge');
INSERT INTO settlement VALUES
  (..., :pe3, :pe3_arap, :si2, :si2_sched_1, 16225.00, ...),
  (..., :pe3, :pe3_arap, :si2, :si2_sched_2, 16225.00, ...),
  (..., :pe3, :pe3_arap, :si3, :si3_sched_1,  7000.00, ...);
```

Invariant **S2**: `Σ settlement + Σ payment_deduction = received_amount`, enforced by a deferred
trigger. The 450 is explicitly a deduction with an account and a reason — never absorbed into an
allocation routine by `paid_amount -= deductions` (§5).

Note allocation is **per schedule row**, always — not "invoice-level unless a Payment Request
exists" (§5.1).

### 12.5 Scenario D — credit-note offset is opt-in

```sql
CREATE TABLE allocation_policy (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    party_type    party_type,
    party_id      uuid,
    strategy      allocation_strategy NOT NULL,   -- 'oldest_due_first','discount_first',
                                                  -- 'largest_first','proportional','manual'
    honour_discount_date     boolean NOT NULL DEFAULT true,
    allow_credit_note_offset boolean NOT NULL DEFAULT false,   -- ← §6 becomes explicit
    max_underpay_writeoff    numeric(19,4) NOT NULL DEFAULT 0,
    priority      integer NOT NULL,
    UNIQUE (company_id, party_type, party_id, priority)
);
```

The engine is **deterministic given (policy, open schedules, amount)** and produces a *proposed*
set of `settlement` rows the user may override before posting. Same inputs → same allocation,
independent of row order or index choices (§3.1, §7.3). `oldest_due_first` and `proportional`
are expressible; ERPNext has neither.

### 12.6 Scenario E — an advance is not a special case

An advance is a `settlement` row whose `obligation_schedule_id` points at a **schedule row on the
order** (orders get `payment_schedule` rows for down-payment terms).

When the invoice is raised, the advance **transfers** with two rows in one transaction:

```sql
INSERT INTO settlement (…, obligation_schedule_id, allocated_amount, reverses_settlement_id, reason_code, transfer_group_id)
     VALUES (…, :so_sched_1, -20000.00, :orig_settlement_id, 'advance_transfer', :grp),   -- release from order
            (…, :si4_sched_1, 20000.00, NULL,                'advance_transfer', :grp);   -- apply to invoice
```

Nothing is deleted, nothing is rewritten, and the history reads correctly at every point in time.

`advance_paid` and `advance_payment_status` are **both views over the same rows**:

```sql
CREATE VIEW order_advance AS
SELECT ps.voucher_id, SUM(s.allocated_amount_base) AS advance_paid_base
FROM settlement s JOIN payment_schedule ps ON ps.id = s.obligation_schedule_id
WHERE ps.is_advance_term GROUP BY ps.voucher_id;
```

so they **cannot disagree** (§7.2 defect 3), the comparison uses explicit rounding to the
currency's minor unit (defect 1), and there is one enum with direction from `party_type`
(no `Requested` vs `Initiated` split).

### 12.7 Scenario F — un-allocation is one insert

```sql
INSERT INTO settlement (payment_voucher_id, payment_ar_ap_entry_id, obligation_voucher_id,
                        obligation_schedule_id, allocated_amount, allocated_amount_base,
                        reverses_settlement_id, reason_code, created_by, effective_date)
SELECT payment_voucher_id, payment_ar_ap_entry_id, obligation_voucher_id, obligation_schedule_id,
       -allocated_amount, -allocated_amount_base,
       id, 'misallocation — corrected to SI-0005', :user, current_date
FROM settlement WHERE id = :wrong_settlement_id;
-- then the correct allocation:
INSERT INTO settlement (… obligation_schedule_id = :si5_sched_1, allocated_amount = 7000.00 …);
```

`reverses_settlement_id UNIQUE` makes double-reversal a constraint violation (S3). A trigger
checks the reversal negates exactly, same schedule, same account.

**Nothing is cancelled. No GL is reversed. No PLE is deleted. The payment document is untouched.
Bank reconciliation is unaffected.** Compare §8.

### 12.8 Scenario G — over-payment is a real object

The unallocated remainder is an `ar_ap_entry` with no `settlement` rows — visible in
`schedule_outstanding` as customer credit, and allocatable later by inserting a `settlement` row.
`voucher_outstanding` nets it. No `NULL` `against_voucher` semantics.

### 12.9 Closed periods

`settlement.effective_date` must fall in an open `accounting_period` unless an active
`period_override` grant covers it, recorded with `granted_by` / `granted_at` (S5). There is no
`adv_adj=1` equivalent that silently bypasses the freeze (§9.2c).

---

## 13. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Places an allocation is recorded | **9** | **1** |
| Allocation granularity | invoice; sometimes payment term | always `payment_schedule` row |
| Allocation order | child-row `idx`, greedy | `allocation_policy.strategy`, deterministic |
| Oldest-due-first available? | No | Yes |
| Proportional allocation? | No | Yes |
| Credit note consumed on short payment | **automatic and silent** | `allow_credit_note_offset` opt-in per party |
| Bank charge handling | `paid_amount -= deductions`, conflated | `payment_deduction` rows, invariant S2 |
| Un-allocate | cancel/split/resubmit; audit trail deleted | one compensating insert |
| Row identity of a payment's children | rewritten on every reconcile | never mutated |
| `outstanding_amount` | cached column, unlocked read-then-write | view |
| Over-allocation prevented? | validation, races | deferred trigger with row lock (S1) |
| `Σ allocations + deductions = received` | not enforced | trigger (S2) |
| Advance → invoice transfer | delete + rebuild PLE, rewrite child rows | two compensating rows, one txn |
| `advance_paid` vs `advance_payment_status` | different sources, disagree | same view |
| Money equality test | `paid_amount == total_amount` (float) | rounded to minor unit |
| Closed-period write | `adv_adj=1` bypasses freeze | `period_override` grant, audited |
| Settlement link freshness in GL | `against_voucher` goes stale | no ledger column to go stale |
| Point-in-time outstanding | impossible | `WHERE posted_at <= t` |
| Who allocated, why | not recorded | `created_by`, `reason_code`, `posted_at` |

---

## 14. Invariants exercised

- **S1** `Σ settlement` per obligation schedule never exceeds it or flips sign — row-locked trigger.
- **S2** `Σ settlement + Σ payment_deduction = received_amount`.
- **S3** `reverses_settlement_id` unique; reversal negates exactly.
- **S4** `company_id` consistent across payment, obligation, schedule (composite FK).
- **S5** `effective_date` in an open period, or an audited `period_override`.
- **S6** `Σ payment_schedule = grand_total`, so S1 composes upward without a second check.
- **S7** `settlement` append-only.
- **F1** every voucher balances in base currency — payment, reversal, FX journal alike.

---

Cross-references: **[S01 — Order to Cash](S01-order-to-cash.md)**;
doc 04 (AR/AP and settlement as ERPNext models it), doc 11 (advances and payment allocation —
the subsystem reference for this scenario), doc 09 §3 (cancellation side effects),
doc 14 (banking and collections), doc 15 §9 (Unreconcile Payment),
`docs/design/FINAL-SCHEMA.md` §Settlement model.
