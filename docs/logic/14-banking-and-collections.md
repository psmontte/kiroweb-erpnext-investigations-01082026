# 14 — Banking, Reconciliation, and Collections

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Covers `Bank Transaction`, the Bank Reconciliation Tool, `Bank Clearance`, `Payment Request`,
`Dunning`, `Invoice Discounting`, and `Process Statement of Accounts`. The unifying theme: the
bank statement is treated as a **document that reconciles against the ledger but never enters
it**, and clearance status is stored as a scalar column on the payment rather than as a fact
about the bank line.

---

## 1. `Bank Transaction` — a statement line that posts nothing

`accounts/doctype/bank_transaction/bank_transaction.py:13`.

Columns of interest: `date`, `withdrawal`, `deposit`, `currency`, `bank_account`,
`reference_number`, `description`, `party_type`, `party`, `allocated_amount`,
`unallocated_amount`, `status`, plus the `Bank Transaction Payments` child table
(`payment_document`, `payment_entry`, `allocated_amount`, `reconciliation_type`).

**A submitted `Bank Transaction` writes no GL entries.** There is no `make_gl_entries` anywhere
in the file. Cash in the ledger comes exclusively from Payment Entries / Journal Entries; the
statement line is metadata used to *match* them. Consequences:

- The bank balance per the ledger and per the statement are two unconnected numbers. There is no
  bank reconciliation *statement* object holding "book balance + in-transit − outstanding =
  statement balance". `get_account_balance`
  (`accounts/doctype/bank_reconciliation_tool/bank_reconciliation_tool.py:93`) computes a GL
  balance to a date; comparison to the statement is left to the user's eyes.
- Bank charges included in a statement line need special handling:
  `validate_included_fee` (`accounts/doctype/bank_transaction/bank_transaction.py:329`) and
  `handle_excluded_fee` (`:339`).
- An unreconciled statement line represents real money that appears nowhere in the accounts.

### 1.1 Status and allocation arithmetic

`set_status` (`:84`):

```python
if docstatus == 2:                       db_set("status", "Cancelled")
elif docstatus == 1:
    if unallocated_amount > 0:           db_set("status", "Unreconciled")
    elif unallocated_amount <= 0:        db_set("status", "Reconciled")
```

`unallocated_amount <= 0` → `Reconciled`. **A negatively-unallocated (over-allocated)
transaction is reported as Reconciled.** The over-allocation check exists elsewhere
(`allocate_payment_entries`, `:211`) but this branch does not distinguish the states.

`update_allocated_amount` (`:109`):

```python
allocated_amount   = sum(p.allocated_amount for p in self.payment_entries)
unallocated_amount = abs(flt(self.withdrawal) - flt(self.deposit)) - allocated_amount
```

`abs(withdrawal - deposit)` — the transaction's magnitude is derived from **two separate
columns** with the sign discarded. A statement line with both `withdrawal` and `deposit`
populated (which nothing prevents) silently nets. There is no `CHECK` that exactly one is
non-zero.

`validate_duplicate_references` (`:93`) prevents the same `(payment_document, payment_entry)`
appearing twice **within one transaction** — by iterating a Python `set`. Nothing prevents the
same voucher being allocated across *two different* bank transactions beyond the running
`get_total_allocated_amount` check (§1.2).

### 1.2 `allocate_payment_entries` — the allocation algorithm

`accounts/doctype/bank_transaction/bank_transaction.py:174`. The docstring states the intent:

```
Get the bank transaction amount (b) and remove as we allocate
For each payment_entry if allocated_amount == 0:
- get the amount already allocated against all transactions (t), need latest date
- get the voucher amount (from gl) (v)
- allocate (a = v - t)
    - a = 0: should already be cleared, so clear & remove payment_entry
    - 0 < a <= u: allocate a & clear
    - 0 < a, a > u: allocate u
    - 0 > a: Error: already over-allocated
- clear means: set the latest transaction date as clearance date
```

Implementation:

```python
remaining_amount   = self.unallocated_amount
pe_bt_allocations  = get_total_allocated_amount(payment_entry_docs)     # :517
gl_entries         = get_related_bank_gl_entries(payment_entry_docs)    # :482
gl_bank_account    = frappe.db.get_value("Bank Account", self.bank_account, "account")

for payment_entry in list(self.payment_entries):
    if payment_entry.allocated_amount != 0: continue
    allocable_amount, should_clear, clearance_date = get_clearance_details(...)   # :421
    if allocable_amount < 0: frappe.throw("Voucher {0} is over-allocated by {1}")
    if remaining_amount <= 0: self.remove(payment_entry); continue
    if allocable_amount == 0:
        if should_clear: self.clear_linked_payment_entry(payment_entry, clearance_date)
        self.remove(payment_entry); continue
    should_clear = should_clear and allocable_amount <= remaining_amount
    payment_entry.allocated_amount = min(allocable_amount, remaining_amount)
    remaining_amount = flt(remaining_amount - payment_entry.allocated_amount, precision)
    if payment_entry.payment_document == "Bank Transaction":
        self.update_linked_bank_transaction(payment_entry.payment_entry, payment_entry.allocated_amount)
    elif should_clear:
        self.clear_linked_payment_entry(payment_entry, clearance_date=clearance_date)
self.update_allocated_amount()
```

Notes:

- `frappe.throw(_("Voucher {0} is over-allocated by {1}").format(allocable_amount))` (`:212`) —
  **two format placeholders, one argument.** This raises `IndexError` instead of the intended
  message. The over-allocation guard is broken in v17.
- Rows are **silently removed from the child table** when they cannot be allocated
  (`:216`, `:222`). The user's stated intent to match voucher X disappears with no message.
- `should_clear = should_clear and allocable_amount <= remaining_amount` (`:224`) — a partially
  allocated voucher is not cleared. So `clearance_date` means "fully cleared by this
  statement line", but the column lives on the *voucher*, not on the link.
- `payment_document == "Bank Transaction"` (`:229`) — a bank transaction can be allocated to
  another bank transaction. That is how internal transfers are modelled
  (`search_for_transfer_transaction`,
  `accounts/doctype/bank_reconciliation_tool/bank_reconciliation_tool.py:901`;
  `create_internal_transfer`, `:504`; `create_bulk_internal_transfer`, `:460`). The child table
  is therefore polymorphic across a set defined by
  `get_doctypes_for_bank_reconciliation` (`accounts/doctype/bank_transaction/bank_transaction.py:365`).

### 1.3 Clearance is a scalar on the voucher

`clear_linked_payment_entry` (`accounts/doctype/bank_transaction/bank_transaction.py:256`):

```python
if doctype not in get_doctypes_for_bank_reconciliation(): return
if doctype == "Sales Invoice":
    frappe.db.set_value("Sales Invoice Payment",
        dict(parenttype=doctype, parent=docname), "clearance_date", clearance_date)
    return
frappe.db.set_value(doctype, docname, "clearance_date", clearance_date)
```

So:

- **`clearance_date` is a single nullable date on the payment document.** A payment split across
  two statement lines (partial clearing on different days) cannot be represented. The last write
  wins.
- For Sales Invoice the date goes on **every** `Sales Invoice Payment` child row of that invoice
  (the filter has no row selector), so a POS invoice with cash + card payments has both marked
  cleared when one clears.
- Unclearing is `clearance_date = None` (`delink_payment_entry`, `:250`). No history.
- `AccountsController.clear_clearance_date_on_amend`
  (`controllers/accounts_controller.py:120`) wipes it on amend, because it is a column on the
  document rather than a fact about the bank line.

`on_cancel` (`:145`) sets `self.ignore_linked_doctypes = ["GL Entry"]` then delinks every
payment entry — disabling the back-link guard (doc 09 §1.4).

`before_update_after_submit` (`:138`) runs
`validate_duplicate_references` → `update_allocated_amount` → `delink_old_payment_entries` →
`allocate_payment_entries` → `set_status`. So a submitted Bank Transaction is **routinely
edited**, with `delink_old_payment_entries` (`:118`) diffing against `get_doc_before_save()` to
find removed rows. Update-after-submit as a core workflow.

`remove_from_bank_transaction` (`:572`) is what `AccountsController.on_cancel` calls
(doc 09 §3.2) to strip a cancelled voucher out of every bank transaction.

`unreconcile_transaction` (`:371`) and `unreconcile_transaction_entry` (`:401`) are the
whitelisted undo paths.

---

## 2. The matching engine

`check_matching` (`accounts/doctype/bank_reconciliation_tool/bank_reconciliation_tool.py:1130`)
builds a set of queries (`get_queries`, `:1175`; `get_matching_queries`, `:1215`) — one per
candidate doctype — and concatenates the results, sorted by `rank` descending (`:1170`).

`get_queries` is **hook-extensible**: `frappe.get_hooks("get_matching_queries")` (`:1191`), so
apps can add matchers.

The per-doctype queries:

| Function | Line | Matches |
|---|---|---|
| `get_bt_matching_query` | `:1275` | other Bank Transactions (internal transfer) |
| `get_pe_matching_query` | `:1319` | Payment Entry |
| `get_je_matching_query` | `:1381` | Journal Entry (via Journal Entry Account) |
| `get_si_matching_query` | `:1450` | Sales Invoice (POS payments) |
| `get_pi_matching_query` | `:1494` | Purchase Invoice |

### 2.1 How `rank` is computed

From `get_pe_matching_query` (`:1319`):

```python
ref_condition   = pe.reference_no == transaction.reference_number
ref_rank        = Case().when(ref_condition, 1).else_(0)
amount_equality = pe.paid_amount == transaction.unallocated_amount
amount_rank     = Case().when(amount_equality, 1).else_(0)
party_condition = (pe.party_type == transaction.party_type) & (pe.party == transaction.party) \
                  & pe.party.isnotnull()
party_rank      = Case().when(party_condition, 1).else_(0)
...
.select((ref_rank + amount_rank + party_rank + 1).as_("rank"), ...)
.where(pe.docstatus == 1)
.where(pe.payment_type.isin([payment_type, "Internal Transfer"]))
.where(pe.clearance_date.isnull())
.where(getattr(pe, account_from_to) == common_filters.bank_account)
.where(amount_condition)
.where(filter_by_date)
```

So `rank ∈ {1,2,3,4}`: **an unweighted count of three boolean predicates, plus one.**
Observations:

- **`amount_equality` is float `==` on money.** `pe.paid_amount == transaction.unallocated_amount`
  compares a `decimal(21,9)`-backed value with a computed one; near-misses (bank fee of 0.01) get
  rank 0 for amount and are not surfaced as "close".
- **Reference-number matching is exact string equality.** Bank statements mangle references
  (truncation, prefixes, case, embedded spaces). No normalisation, no fuzzy match, no
  `similarity()`.
- **Description is not used at all** in `get_pe_matching_query`. Party matching relies on
  `transaction.party` already being set — which happens in `auto_set_party` (`:306`) via
  `Bank Transaction Mapping` rules, or not at all.
- `.where(pe.clearance_date.isnull())` is the "not yet reconciled" filter — the scalar column
  again (§1.3). A partially cleared payment is invisible to matching.
- `exact_match` (a *document-type* flag, `"exact_match" in document_types`, `:1141`) switches
  `amount_condition` between `paid_amount == unallocated_amount` and `paid_amount > 0.0`.
  Passing a matching mode inside the list of doctypes to search is an API smell.
- `frappe.flags.auto_reconcile_vouchers is True` (`:1375`) adds `ref_condition` as a hard
  filter — so **automatic** reconciliation requires an exact reference-number match, while
  manual matching ranks it.

`subtract_allocations` (`:1105`) and `get_allocated_amount` (`:1120`) net off amounts already
allocated elsewhere. `get_linked_payments` (`:1076`) is the whitelisted entry point.
`get_older_unreconciled_transactions` (`:389`) surfaces backlog.

### 2.2 Auto-reconciliation

`auto_reconcile_vouchers` (`:960`), `start_auto_reconcile` (`:994`),
`get_auto_reconcile_message` (`:1039`), `reconcile_vouchers` (`:1061`).
Bulk creation helpers: `create_journal_entry_bts` (`:150`), `create_payment_entry_bts` (`:309`),
`create_bulk_bank_entry_and_reconcile` (`:581`), `create_bank_entry_and_reconcile` (`:674`),
`create_bulk_payment_entry_and_reconcile` (`:772`),
`create_payment_entry_and_reconcile` (`:868`).
`update_bank_transaction` (`:120`), `update_clearance_date` (`:422`),
`clear_clearing_date` (`:448`).

Auto-reconciliation creates and submits Payment Entries from statement lines. Since the
matching is exact-reference-only in auto mode, in practice it handles the subset of banks that
echo the payment reference cleanly.

---

## 3. `Bank Clearance` — the cheque-clearing tool

`accounts/doctype/bank_clearance/bank_clearance.py:19`.
`get_payment_entries` (`:43`), `update_clearance_date` (`:93`) with inner
`validate_entry` (`:99`), and `get_payment_entries_for_bank_clearance` (`:183`).

`Bank Clearance Detail` is a child table holding candidate rows. Its `amount` field is a
**pre-formatted string** — the value is built with currency formatting before being written to
the row, so it is display text, not a number. Any arithmetic or comparison against it is
impossible without reparsing, and it is locale-dependent. This is the clearest example in the
codebase of a presentation concern leaking into a stored column.

`Bank Clearance` and the Bank Reconciliation Tool are two overlapping mechanisms that both write
the same `clearance_date` scalar, with different candidate queries and different validation.

---

## 4. `Payment Request` — the collection intent

`accounts/doctype/payment_request/payment_request.py:61`. This is the document that makes an
order "To Pay" (doc 10 §1.2) and drives `advance_payment_status` (doc 11 §2.4).

Lifecycle: `validate` (`:132`) → `validate_against_payment_reference` (`:141`),
`validate_reference_document` (`:159`), `validate_payment_request_amount` (`:163`),
`validate_currency` (`:193`), `validate_subscription_details` (`:200`);
`before_submit` (`:225`); `on_submit` (`:269`) → `_process_v2_gateway` (`:272`);
`on_cancel` (`:441`).

Payment side: `create_payment_entry` (`:516`), `set_as_paid` (`:505`),
`check_if_payment_entry_exists` (`:651`), `make_payment_entry` (`:1134`),
`get_existing_payment_entry` (`:973`),
`update_payment_requests_as_per_pe_references` (`:1140`),
`_allocate_payment_request_to_pe_references` (`:685`),
`apply_payment_references` (`:945`), `set_payment_references` (`:954`).

Amount logic: `get_request_amount` (`:424`), `get_amount` (`:991`),
`get_existing_payment_request_amount` (`:1078`),
`validate_and_calculate_grand_total` (`:828`, nested in `make_payment_request`, `:743`),
`cancel_old_payment_requests` (`:1053`).

Gateway: `payment_gateway_validation` (`:454`), `get_gateway_details` (`:1105`),
`get_payment_gateway_account` (`:1113`), `set_payment_request_url` (`:469`),
`get_payment_url` (`:473`), `request_phone_payment` (`:406`), `get_tx_data` (`:303`),
`create_subscription` (`:673`), `get_irequest_status` (`:1038`),
`_get_payment_gateway_controller` (`:33`), `_is_v2_gateway` (`:40`).

Key structural points:

- **`Payment Request` carries its own `outstanding_amount`**, and
  `set_advance_payment_status` (doc 11 §2.4) derives an order's payment status from
  `SUM(grand_total - outstanding_amount)` over Payment Requests — a *second, parallel*
  outstanding ledger beside `Payment Ledger Entry`. Two sources of truth for "how much has been
  paid".
- `_allocate_payment_request_to_pe_references` (`:685`) writes `payment_request` onto
  `Payment Entry Reference` rows, which then gives those rows priority in
  `allocate_amount_to_references` (doc 11 §3.4). Allocation priority is thus a function of
  which rows happen to carry a Payment Request link.
- `cancel_old_payment_requests` (`:1053`) cancels prior requests when a new one is made —
  destructive, rather than superseding.
- `update_reference_advance_payment_status` (`:680`) pushes status back to the order.

---

## 5. Collections: `Dunning` and statements

`accounts/doctype/dunning/dunning.py:25`, an `AccountsController` (so it posts GL —
dunning *fees* and interest are real revenue).

`validate` (`:72`) → `validate_same_currency` (`:79`), `validate_overdue_payments` (`:99`),
`validate_totals` (`:106`), `set_party_details` (`:113`), `set_dunning_level` (`:138`);
`on_cancel` (`:150`); `get_dunning_letter_text` (`:167`);
`update_linked_dunnings` (`:207`), `get_linked_dunnings_as_per_state` (`:269`).

The child table is `Overdue Payment`, and this is where it goes wrong:

- **`Overdue Payment.payment_schedule` is a `Data` field, not a `Link`.** It holds the name of a
  `Payment Schedule` row as free text. No FK, no validation, no cascade. Renaming or
  regenerating the schedule (which happens on any invoice edit that recomputes payment terms)
  orphans it silently.
- **`Overdue Payment.overdue_days` is a `Data` field, not `Int`.** Aging in days stored as a
  string. Sorting is lexicographic ("9" > "10"), arithmetic requires casting.
- `Dunning Type` + `Dunning Letter Text` hold the escalation levels; `set_dunning_level` (`:138`)
  computes the level by counting prior dunnings, not by a state machine on the receivable.

`update_linked_dunnings(doc, previous_outstanding_amount)` (`:207`) is called when an invoice's
outstanding changes, to resolve dunnings whose underlying debt was paid — a push-based cache
invalidation across documents.

`Process Statement of Accounts`
(`accounts/doctype/process_statement_of_accounts/process_statement_of_accounts.py:25`) is the
customer-statement mailer: `get_report_pdf` (`:172`), `get_statement_dict` (`:186`),
`set_ageing` (`:229`), `get_gl_filters` (`:263`), `get_ar_filters` (`:281`),
`get_html` (`:302`), customer selection by territory/group/sales-person (`:345`, `:367`,
`:423`), email resolution (`:396`, `:463`), `send_emails` (`:521`), `send_auto_email` (`:579`).
It renders **reports** to PDF — so the statement a customer receives is generated from report
code, not from a stored statement object. Reissuing last month's statement exactly is not
possible after any backdated posting.

---

## 6. `Invoice Discounting` — factoring

`accounts/doctype/invoice_discounting/invoice_discounting.py:19`, an `AccountsController`.
`validate` (`:48`), `set_end_date` (`:55`), `validate_mandatory` (`:59`),
`validate_invoices` (`:63`), `calculate_total_amount` (`:89`), `on_submit` (`:92`),
`on_cancel` (`:96`), `set_status` (`:101`), `update_sales_invoice` (`:119`),
`make_gl_entries` (`:130`), `create_disbursement_entry` (`:193`), `close_loan` (`:258`),
`get_invoices` (`:320`), `get_party_account_based_on_invoice_discounting` (`:353`).

**Defect:** `Invoice Discounting.bank_account` is a `Link` whose `options` is **`Account`**, not
`Bank Account`. Every other document in the banking area uses `bank_account → Bank Account`
(which itself links to an `Account`). So the same field name means two different things
depending on the doctype, and any generic code that resolves `doc.bank_account` as a
`Bank Account` breaks here.

The accounting flow moves receivables to an "Invoice Discounting" asset account, books the
short-term loan, and later `close_loan` (`:258`) settles it — a two-sided arrangement modelled
with per-invoice status writes (`update_sales_invoice`, `:119`) rather than a link table.

---

## 7. Our design

### 7.1 The bank statement is a ledger

```sql
CREATE TABLE bank_statement (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES company(id),
    bank_account_id uuid NOT NULL REFERENCES bank_account(id),
    statement_no   text NOT NULL,
    period_start   date NOT NULL,
    period_end     date NOT NULL,
    opening_balance numeric(19,4) NOT NULL,
    closing_balance numeric(19,4) NOT NULL,
    imported_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bank_account_id, statement_no)
);

CREATE TABLE bank_statement_line (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL,
    statement_id   uuid NOT NULL REFERENCES bank_statement(id),
    bank_account_id uuid NOT NULL REFERENCES bank_account(id),
    value_date     date NOT NULL,
    booking_date   date NOT NULL,
    amount         numeric(19,4) NOT NULL,        -- ONE signed column
    currency_code  char(3) NOT NULL,
    bank_reference text,                          -- as supplied
    bank_reference_norm text GENERATED ALWAYS AS (upper(regexp_replace(bank_reference,'[^A-Za-z0-9]','','g'))) STORED,
    counterparty_name text,
    counterparty_iban text,
    description    text,
    external_id    text NOT NULL,                 -- bank's own unique id
    CONSTRAINT bsl_amount_nonzero CHECK (amount <> 0),
    UNIQUE (bank_account_id, external_id)          -- idempotent import
);
CREATE INDEX bsl_ref_norm ON bank_statement_line (bank_account_id, bank_reference_norm);
CREATE INDEX bsl_trgm ON bank_statement_line USING gin (description gin_trgm_ops);
```

Fixes: one signed `amount` (no `abs(withdrawal - deposit)`, §1.1); `UNIQUE (bank_account_id,
external_id)` makes statement import **idempotent** (re-importing an overlapping file is a
no-op); a stored **normalised** reference column plus a trigram index makes fuzzy matching a
database operation rather than exact string equality (§2.1); `bank_statement.opening_balance` /
`closing_balance` give a real reconciliation identity to check.

### 7.2 Clearance is a link, not a column

```sql
CREATE TABLE bank_match (
    id                 uuid PRIMARY KEY,
    company_id         uuid NOT NULL,
    statement_line_id  uuid NOT NULL REFERENCES bank_statement_line(id),
    voucher_id         uuid NOT NULL REFERENCES voucher(id),
    matched_amount     numeric(19,4) NOT NULL,
    match_source       match_source NOT NULL,   -- 'auto','rule','manual','created'
    match_score        numeric(5,4),            -- 0..1, explainable
    matched_by         uuid REFERENCES app_user(id),
    matched_at         timestamptz NOT NULL DEFAULT now(),
    reverses_match_id  uuid UNIQUE REFERENCES bank_match(id),
    CONSTRAINT bank_match_nonzero CHECK (matched_amount <> 0)
);
```

- **Many-to-many.** One statement line to several vouchers, one voucher to several statement
  lines (partial clearing across days) — impossible in ERPNext (§1.3).
- `clearance_date` becomes a **view**: `MAX(bsl.value_date)` over the matches of a voucher, only
  once `Σ matched_amount = voucher amount`. Nothing to wipe on amend
  (`clear_clearance_date_on_amend`, §1.3).
- **Append-only with `reverses_match_id`** (D5), so un-matching leaves a trail. ERPNext's
  un-match is `clearance_date = NULL` (§1.3).
- Deferred constraint trigger: `Σ |matched_amount|` per statement line ≤ `|amount|`, and per
  voucher ≤ the voucher's bank-account amount, with `FOR UPDATE` on the statement line — the
  broken over-allocation guard (§1.2, the `IndexError`) becomes a database invariant.
- `match_score` is stored, so "why did the system match these?" is answerable. ERPNext's `rank`
  is a transient `1 + three booleans` (§2.1) that is never persisted.

### 7.3 Matching as an explainable, weighted model

```sql
CREATE TABLE bank_match_rule (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL,
    bank_account_id uuid,
    priority        integer NOT NULL,
    signal          match_signal NOT NULL,  -- 'reference_exact','reference_norm','reference_contains',
                                            -- 'amount_exact','amount_within_tolerance',
                                            -- 'party_iban','party_name_trgm','description_regex','date_window'
    weight          numeric(5,4) NOT NULL,
    tolerance       numeric(19,4),
    pattern         text,
    UNIQUE (company_id, bank_account_id, priority)
);
```

Score = Σ (weight × signal strength), normalised to 0..1. Signals include
`amount_within_tolerance` (so a bank fee of 0.01 still scores highly — impossible with
`==`, §2.1) and `party_name_trgm` using `similarity()` on the trigram index. Auto-match applies
above a configurable threshold and records `match_score` and the contributing signals in
`bank_match_signal` rows. Everything is inspectable and tunable per bank account.

### 7.4 Unmatched statement lines are visible in the accounts

Because a statement line represents real money movement, we post it to a **bank suspense
account** on import, and matching moves it from suspense to the matched voucher's bank line:

```
On import:   Dr Bank  / Cr Bank Suspense       (or the reverse for withdrawals)
On match:    Dr Bank Suspense / Cr <voucher's bank clearing>   -- nets to zero
```

The result: the bank account in the ledger always ties to the statement, and
**`Bank Suspense` is exactly the unreconciled backlog** — a number a controller can see on the
balance sheet. ERPNext's unmatched statement lines are invisible to the accounts entirely (§1).

### 7.5 Collections

- `dunning_run` / `dunning_line` with **`payment_schedule_id uuid REFERENCES payment_schedule(id)`**
  and **`overdue_days integer GENERATED ALWAYS AS (...) STORED`** — fixing the `Data`-typed
  FK and the string-typed integer (§5).
- Escalation is a `dunning_policy` + `dunning_stage` model keyed off the *receivable's* state
  (`schedule_outstanding` view, doc 11 §6.2), with `stage_reached_at` recorded, not a count of
  prior dunning documents.
- `customer_statement` is a **stored, immutable snapshot** (`statement_id`, `as_of`,
  `opening`, `closing`, plus `statement_line` rows) generated once and mailed. Reissuing is
  re-sending the same rows, not re-running a report against mutated data (§5).
- Factoring (`invoice_discounting`) uses a proper `financing_arrangement` +
  `financed_receivable` link table, and its bank field is `bank_account_id REFERENCES
  bank_account(id)` — not `Account` (§6).
- `Payment Request` becomes `collection_request` whose fulfilment is measured through the
  **same `settlement` table** as everything else (doc 11 §6.1), eliminating the parallel
  `outstanding_amount` ledger (§4).

---

## 8. Defect summary carried forward

| Finding | Location | Our fix |
|---|---|---|
| Bank Transaction posts no GL | `bank_transaction.py` (no `make_gl_entries`) | bank suspense posting on import (§7.4) |
| `unallocated_amount <= 0 → Reconciled` conflates over-allocation | `bank_transaction.py:88`–`:90` | signed `amount` + trigger-enforced allocation cap |
| `abs(withdrawal - deposit)` as magnitude | `bank_transaction.py:113` | one signed `amount` column with `CHECK (amount <> 0)` |
| `frappe.throw` with 2 placeholders, 1 arg | `bank_transaction.py:212` | database constraint, no message-formatting bug possible |
| Unallocatable rows silently removed | `bank_transaction.py:216`, `:222` | rows persist with `matched_amount`; rejection is explicit |
| `clearance_date` scalar on the voucher | `bank_transaction.py:256`–`:273` | `bank_match` link table (§7.2) |
| Sales Invoice clearance set on all payment rows | `bank_transaction.py:263`–`:270` | per-match rows |
| `ignore_linked_doctypes = ["GL Entry"]` | `bank_transaction.py:146` | FK RESTRICT, no bypass |
| Rank = 1 + three booleans, never stored | `bank_reconciliation_tool.py:1354` | weighted, persisted `match_score` (§7.3) |
| Float `==` on amounts for matching | `bank_reconciliation_tool.py:1339` | tolerance-based signal |
| Exact string reference matching only | `bank_reconciliation_tool.py:1336` | normalised column + trigram (§7.1) |
| Auto-reconcile requires exact reference | `bank_reconciliation_tool.py:1375`–`:1376` | threshold on composite score |
| `Bank Clearance Detail.amount` is a formatted string | Bank Clearance child DocType | `numeric(19,4)` |
| Two overlapping clearing tools | `bank_clearance.py` + `bank_reconciliation_tool.py` | one `bank_match` path |
| `Overdue Payment.payment_schedule` is `Data` | Dunning child DocType | real FK |
| `Overdue Payment.overdue_days` is `Data` | Dunning child DocType | generated `integer` |
| `Invoice Discounting.bank_account → Account` | Invoice Discounting DocType | `→ bank_account` |
| Statements rendered from reports, not stored | `process_statement_of_accounts.py:172` | immutable `customer_statement` snapshot |
| Payment Request keeps a parallel `outstanding_amount` | `payment_request.py` | one `settlement` table (doc 11) |

Cross-references: doc 04 (AR/AP), doc 11 (advances and allocation), doc 09 (lifecycle and
`on_cancel` side effects), `docs/design/FINAL-SCHEMA.md`.
