# 31 — Batch Processes, Instruments, Recurring, and the Settings Catalogue

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This closes the last of the Accounts coverage. Four unrelated-looking groups turn out to share one
property, which is why they are documented together:

| Group | DocTypes | Shared property |
|---|---|---|
| **Batch processes** | `Process Deferred Accounting`, `Process Subscription`, `Process Payment Reconciliation` (+`Log`) | a *submitted document* whose only purpose is to start a background job |
| **Instruments** | `Payment Order`, `Bank Guarantee`, `Cashier Closing` | submittable documents that **post nothing to any ledger** |
| **Recurring** | `Subscription` (+`Plan`, `Settings`), `Loyalty Program` (+`Point Entry`) | state advanced by a scheduler, idempotency by date comparison |
| **Configuration** | `Accounts Settings`, `POS Settings`, banking config, `Financial Report Template`, `Monthly Distribution`, FX settings | saving them **changes schema, metadata, cron schedules or files on disk** |

Closes the `docs/COVERAGE.md` gaps for `Payment Order`, `Bank Guarantee`, `Cashier Closing`,
`Process Deferred Accounting`, `Process Payment Reconciliation` (+ `Log`), `Process Subscription`,
`Subscription` (+ `Plan`, `Settings`), `Loyalty Program`, `Loyalty Point Entry`, `Bank`,
`Bank Account`, `Bank Account Balance`, `Bank Transaction Rule`, `Cheque Print Template`,
`Payment Gateway Account`, `Financial Report Template`, `Monthly Distribution`, `Accounts Settings`,
`POS Settings`, `Currency Exchange Settings` and `Pegged Currencies`.

---

## 1. The batch-process pattern

ERPNext models "run this job" as a **submittable document**. That is not unreasonable — it gives the
run an identity, a docstatus and an audit row. But because the job is asynchronous and the document
is the only record of it, the result has to be written back into the document, and cancelling the
document has to undo the work. Every problem in this section follows from that.

### 1.1 `Process Deferred Accounting`

`ProcessDeferredAccounting`
(`accounts/doctype/process_deferred_accounting/process_deferred_accounting.py:18`) is the smallest
example and the clearest.

```python
def validate(self):                                          # :37
    if self.end_date < self.start_date: frappe.throw(_("End date cannot be before start date"))

def on_submit(self):                                         # :41
    conditions = build_conditions(self.type, self.account, self.company)
    if self.type == "Income": convert_deferred_revenue_to_income(self.name, self.start_date, self.end_date, conditions)
    else:                     convert_deferred_expense_to_expense(self.name, self.start_date, self.end_date, conditions)

def on_cancel(self):                                         # :48
    self.ignore_linked_doctypes = ["GL Entry"]
    gl_entries = frappe.get_all("GL Entry", fields=["*"],
        filters={"against_voucher_type": self.doctype, "against_voucher": self.name})
    make_gl_entries(gl_map=gl_entries, cancel=1)
```

⚠️ **Cancellation is "select the rows I created and feed them back into the posting engine
negated".** `fields=["*"]` reads whole GL rows as dicts and passes them to `make_gl_entries(cancel=1)`.
The correctness of the reversal depends entirely on `against_voucher` having been set on every row the
process created, and on nothing else having written rows with the same `against_voucher`. It also sets
`ignore_linked_doctypes = ["GL Entry"]` to get past the link check.

This is the ad-hoc version of the reversal problem doc 01 §1.7 handles centrally, and it is why our
decision 5 (reversal is a new voucher with `reverses_voucher_id UNIQUE`) matters: the reversal must be
addressable, not reconstructed by query.

> **Ours** A deferral run is a `posting_run` row with a `daterange` and a `state`. Every ledger row it
> writes carries `posting_run_id` as a **foreign key**, so reversal is
> `INSERT … SELECT` over `WHERE posting_run_id = ?` with `reverses_entry_id` set per row — a real
> relationship rather than an `against_voucher` string convention, and `ON DELETE RESTRICT` means the
> run cannot be deleted while its rows exist. `deferral_schedule` is stored up front (doc 12 §2), so a
> run posts a *pre-computed* schedule rather than deriving one at run time.

### 1.2 `Process Subscription`

`ProcessSubscription` (`accounts/doctype/process_subscription/process_subscription.py:11`):

```python
def on_submit(self):                                         # :26
    self.process_all_subscription()

def process_all_subscription(self):                          # :29
    filters = {"status": ("!=", "Cancelled")}
    if self.subscription: filters["name"] = self.subscription
    subscriptions = frappe.get_all("Subscription", filters, pluck="name")
    for subscription in create_batch(subscriptions, 500):
        frappe.enqueue(method="…subscription.subscription.process_all", queue="long",
                       subscription=subscription, posting_date=self.posting_date)
```

`create_batch` yields **lists**, and `process_all(subscription: list, …)`
(`accounts/doctype/subscription/subscription.py:1018`) is correctly typed to receive one. The batch
worker is where the problem is:

```python
for subscription_name in subscription:                       # :1023
    try:
        sub = frappe.get_doc("Subscription", subscription_name)
        sub.process(posting_date)
        if not frappe.in_test: frappe.db.commit()
    except frappe.ValidationError:
        frappe.db.rollback()
        sub.log_error("Subscription failed")
```

⚠️ Two defects. `sub` is assigned **inside** the `try`, so if `frappe.get_doc` itself raises a
`ValidationError` the handler references an unbound local and raises `UnboundLocalError`, aborting
the remaining 499 subscriptions in the batch. And only `frappe.ValidationError` is caught — any other
exception (a `LinkValidationError`, a timeout, an `IntegrityError`) propagates and kills the batch,
with the per-subscription `frappe.db.commit()` meaning the batch is left **half applied**.

`create_subscription_process` (`accounts/doctype/process_subscription/process_subscription.py:44`) is
called from the scheduler and **submits** the document, so every tick creates a submitted document
whose only content is a posting date.

### 1.3 `Process Payment Reconciliation` — a state machine made of two booleans and job names

`ProcessPaymentReconciliation`
(`accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py:13`) is the most
elaborate batch process in the application, and worth reading closely because it is what a long-running
job looks like when the framework offers no primitive for one.

**Status lives in two places, synchronised by hand.** The document has a `status` (`""`, `Queued`,
`Running`, `Paused`, `Completed`, `Partially Reconciled`, `Failed`, `Cancelled`) and so does
`Process Payment Reconciliation Log`
(`accounts/doctype/process_payment_reconciliation_log/process_payment_reconciliation_log.py:9`, which
is `pass`). Both are written by `db_set` / `frappe.db.set_value` from `on_submit`
(`accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py:69`), `on_cancel` (`:73`),
`on_discard` (`:40`), `pause_job_for_doc` (`:134`) and `trigger_job_for_doc` (`:144`) — five
writers, two columns, no transition table.

**Progress is a hand-rolled resumable loop.** `reconcile_based_on_filters` (`:245`) is re-entered by
each job and decides what to do next from two booleans on the Log (`allocated`, `reconciled`):

```
no log yet          -> create Log, enqueue fetch_and_allocate
log, not allocated  -> enqueue fetch_and_allocate
log, not reconciled -> enqueue reconcile (one allocation group at a time)
reconciled          -> set status = Completed
```

Idempotency is attempted by naming the RQ job deterministically and checking whether it is already
running:

```python
# accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py
def is_job_running(job_name: str) -> bool:                   # :125
    jobs = frappe.db.get_all("RQ Job", filters={"status": ["in", ["started", "queued"]]})
    for x in jobs:
        if x.job_name == job_name:
            return True
    return False
```

⚠️ This fetches **every started/queued job on the site** and filters in Python, and check-then-enqueue
is racy: two triggers can both observe "not running" and both enqueue.

⚠️ And the job names do not match. The first-run path uses
`f"process_{doc}_fetch_and_allocate"` (`accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py:257`);
the resume path uses `f"process__{doc}_fetch_and_allocate"` (`:278`) — **two underscores**. So the
guard on one path cannot
see the job started by the other, and the allocation phase can run twice concurrently.

**The queue is deduplicated by filter tuple, and the losers never run.**

```python
# accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py
def trigger_reconciliation_for_queued_docs():                # :196
    queue_size = frappe.get_single_value("Accounts Settings", "reconciliation_queue_size") or 5
    fields = ["company", "party_type", "party", "receivable_payable_account", "default_advance_account"]
    for x in all_queued:
        filters = tuple(doc.get(f) or "" for f in fields)
        if filters not in unique_filters:
            unique_filters.add(filters); docs_to_trigger.append(doc.name)
        if len(docs_to_trigger) == queue_size: break
```

Two submitted documents with identical filters: only one is triggered, and the other stays `Queued`
indefinitely with no explanation recorded. Note also `frappe.msgprint`
(`accounts/doctype/process_payment_reconciliation/process_payment_reconciliation.py:198`) called from a **cron job** — a message with no session to receive it, a pattern doc 22 §4 catalogues.

**One idiom worth flagging as fragile rather than broken.** `fetch_and_allocate` (`:339`) builds the
allocation rows like this:

```python
reconcile_log.append("allocations",
    x.as_dict().update({"parenttype": …, "parent": …, "name": None, "reconciled": False}))
```

`dict.update()` returns `None` in Python, and `Document.append(key, None)` appends an **empty child
row** (`frappe/model/base_document.py:411`). This works only because `frappe._dict.update` is
overridden to return `self` (`frappe/types/frappedict.py:39`, docstring: "update and return self --
the missing dict feature in python"). The line is correct today and silently destroys every allocation
the moment `as_dict()` returns a plain `dict`.

`get_pr_instance` (`:99`) copies twelve filter fields onto a fresh `Payment Reconciliation` document
and hard-codes `pr.invoice_limit = 1000` / `pr.payment_limit = 1000`. `get_reconciled_count` (`:81`)
is annotated `-> float` and returns a `dict`. `trigger_job_for_doc` (`:144`) has a `return` statement
after a `frappe.throw` — unreachable.

> **Ours** A long-running job is not a document. `job` and `job_step` tables (doc 22 §7) give:
> a single `state` column with a transition table; `UNIQUE (job_kind, dedupe_key) WHERE state IN
> ('queued','running')` so double-enqueue is impossible by constraint rather than by string
> comparison; `job_step` rows for resumability, each with its own state, so "which allocation group is
> next" is `WHERE state = 'pending' ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED` — which is also the
> correct answer to §1.3's whole design; and `job.blocked_by_job_id` so a run deduplicated against
> another **records why it is waiting** instead of sitting in `Queued` forever. Progress is
> `COUNT(*) FILTER (WHERE state = 'done')`, a view, not two counter columns.

---

## 2. Instruments that post nothing

### 2.1 `Payment Order`

`PaymentOrder` (`accounts/doctype/payment_order/payment_order.py:14`) batches payment instructions to
a bank. It has **no `validate`** at all.

```python
def update_payment_status(self, cancel=False):               # :44
    status = "Payment Ordered"
    if cancel: status = "Initiated"
    if self.payment_order_type == "Payment Request":
        ref_field = "status";               ref_doc_field = frappe.scrub(self.payment_order_type)
    else:
        ref_field = "payment_order_status";  ref_doc_field = "reference_name"
    for d in self.references:
        frappe.db.set_value(self.payment_order_type, d.get(ref_doc_field), ref_field, status)
```

⚠️ The **target doctype is a field value** and the **target column name** is chosen by an `if`. And
cancellation writes `"Initiated"` unconditionally — so cancelling a Payment Order can drag a Payment
Request that has since been *paid* back to `Initiated`. Status is not a state machine; it is a string
assignment from whichever code path ran last.

```python
def make_journal_entry(doc, supplier, mode_of_payment=None):  # :96
    je = frappe.new_doc("Journal Entry")
    ...
    je.append("accounts", {"account": doc.account, "credit_in_account_currency": paid_amt})
    je.flags.ignore_mandatory = True
    je.save()
```

⚠️ `Payment Order.account` is declared **`DF.Data`** (`:28`), not a `Link` — the credit account of a
generated Journal Entry comes from an unvalidated free-text field. The JE is `save()`d as a **draft**
with `ignore_mandatory`, one per (supplier, mode of payment), and amounts are summed across references
with no currency check.

### 2.2 `Bank Guarantee`

`BankGuarantee` (`accounts/doctype/bank_guarantee/bank_guarantee.py:11`) records a guarantee given or
received: `amount`, `charges`, `margin_money`, `account`, `start_date`, `validity`, `end_date`,
`bg_type` ∈ `Receiving`/`Providing`.

⚠️ **It posts nothing.** A contingent liability with an amount, a bank and an expiry is stored as a
submittable document with no GL impact whatsoever — so guarantees given are invisible in the accounts,
and the `margin_money` (typically a real cash deposit) is not recorded anywhere as an asset. `validity`
(an `Int`) and `end_date` are both stored with no consistency check between them.

Mandatory fields are enforced as three `frappe.throw`s inside `on_submit` (`:50`) rather than as
docstatus-dependent field requirements, and `get_voucher_details` (`:60`) — a whitelisted method —
guards its input with a bare `raise TypeError`, not a frappe exception.

### 2.3 `Cashier Closing`

`CashierClosing` (`accounts/doctype/cashier_closing/cashier_closing.py:13`) is the cash-drawer
reconciliation for a shift.

```python
def get_outstanding(self):                                   # :48
    Sum(si.outstanding_amount)
      WHERE si.posting_date == self.date
        AND si.posting_time >= self.from_time AND si.posting_time <= self.time
        AND si.owner == self.user

def make_calculations(self):                                 # :60
    total = Σ payments.amount
    self.net_amount = total + self.outstanding_amount + flt(self.expense) - flt(self.custody) + flt(self.returns)
```

Four problems in twelve lines:

- ⚠️ **It attributes financial data by `owner`** — the Frappe user who *created* the record — rather
  than by cashier, till or POS profile. Re-creating an invoice on someone's behalf moves it into their
  shift.
- ⚠️ **`returns` is added, not subtracted.** A shift with returns shows a higher net amount.
- ⚠️ **There is no `company` field and no currency.** Every amount is a `Float`. In a multi-company or
  multi-currency site the totals are meaningless.
- It is submittable and has **no `on_submit`** — `before_save` (`:45`) recomputes, and submitting
  records nothing. There is no link to the `POS Closing Entry` mechanism (doc 13 §4), so this is a
  parallel, unposted shift close.

> **Ours** These three become ordinary documents in the same framework as the rest (decision 3), and
> two of them post:
> - `payment_instruction` (+`_line`) with `state` from a transition table and a real FK to the
>   instructed payment; the bank leg posts to a *payments-in-transit* account on despatch and clears on
>   confirmation, so money leaving the business is visible before the bank confirms.
> - `guarantee` posts to a **contingent liability** memo ledger (`ledger_kind = 'contingent'`,
>   excluded from the balance sheet but reportable), with `margin_money` posting a real restricted-cash
>   asset. `daterange(issued_on, expires_on)` replaces the `validity`/`end_date` pair.
> - `till_session` with `company_id NOT NULL`, `currency_id`, a `cashier_party_id` that is **not** the
>   creating user, `numeric(19,4)` amounts, and `expected_cash` as a **view** over the session's
>   payments — so the variance is computed, not typed, and the sign of every term is fixed by the view
>   definition rather than by a `+` in Python.

---

## 3. Recurring: `Subscription`

`Subscription` (`accounts/doctype/subscription/subscription.py:61`) is 1,000 lines and one of the more
carefully written controllers in the app; it repays a close reading in both directions.

### 3.1 What it gets right

- `can_generate_new_invoice` (`:684`) **caps the late-fire window at one billing cycle** past the
  period end, with a comment explaining why: "so a multi-year gap doesn't retroactively bill cycle
  after cycle in one call". That is a real class of accident, handled deliberately.
- `validate_party_billing_currency` (`:377`) rejects plans whose currency differs from the party's (or
  company's) billing currency, listing every offending plan.
- `validate_to_follow_calendar_months` (`:436`) refuses calendar-month alignment unless the plan's
  interval is `Month` **and** an end date exists.
- The whole invoice build is decomposed into single-purpose private methods (`_init_invoice_doc`
  `:488`, `_set_invoice_party` `:503`, `_apply_taxes` `:528`, `_apply_payment_schedule` `:542`,
  `_apply_discounts` `:554`, `_finalize_invoice` `:568`) — a structure the older controllers lack.

### 3.2 Idempotency is a date comparison, not a key

```python
def process(self, posting_date=None) -> bool:                # :648
    if not self.is_current_invoice_generated(self.next_billing_period_start, self.next_billing_period_end) \
       and self.can_generate_new_invoice(posting_date):
        self.generate_invoice(posting_date=posting_date)
        ...

def is_current_invoice_generated(self, _current_start_date=None, _current_end_date=None) -> bool:  # :707
    if self.current_invoice and getdate(_current_start_date) <= getdate(self.current_invoice.posting_date) <= getdate(_current_end_date):
        return True
    return False

def get_current_invoice(self):                               # :730
    invoice = frappe.get_all(self.invoice_document_type,
        {"subscription": self.name, "docstatus": ("<", 2), "is_return": 0},
        limit=1, order_by="to_date desc", pluck="name")
```

⚠️ "Has this period already been billed?" is answered by checking whether **the most recent invoice's
`posting_date` falls inside the period**. There is no unique key on `(subscription, period_start,
period_end)`. Consequences:

- A **draft** invoice counts as generated (`docstatus < 2`), so an abandoned draft blocks billing.
- A **cancelled** invoice does not, so cancelling re-opens the period — which is arguably right, and
  is nowhere stated.
- If `posting_date` differs from the period (which `_invoice_posting_date` `:496` permits) or is later
  edited, the same period can be billed **twice**.

`process` is annotated `-> bool` and no path returns a value; one path (`:669`) does `self.save()` and
a bare `return` in the middle of the function, skipping the trailing status update.

`is_fully_refunded` (`:774`) returns `False` when there are no unpaid invoices at all — defensible,
but it means "fully refunded" and "nothing outstanding" are different answers to the same shape of
question.

`SubscriptionPlan` (`accounts/doctype/subscription_plan/subscription_plan.py:15`) validates only
`billing_interval_count >= 1` (`accounts/doctype/subscription_plan/subscription_plan.py:40`). `SubscriptionSettings`
(`accounts/doctype/subscription_settings/subscription_settings.py:8`) is `pass`.

> **Ours** `subscription_period` is a **table**: one row per billed period with
> `daterange(period_start, period_end)`, `EXCLUDE USING gist (subscription_id WITH =, period WITH &&)`
> so a period cannot exist twice, and `invoice_id` as a nullable FK. Generating an invoice is
> `INSERT … ON CONFLICT DO NOTHING` on that table — idempotent by construction, safe to re-run,
> and safe to run concurrently. Whether a draft blocks the next period becomes an explicit
> `period.state` value rather than a side effect of a `docstatus < 2` filter.

---

## 4. Loyalty

`LoyaltyProgram` (`accounts/doctype/loyalty_program/loyalty_program.py:13`) has exactly one
validation: `validate_lowest_tier` (`:44`) requires the lowest tier's `min_spent` to be `0`, with a
good reason given ("Customers need to be part of a tier as soon as they are enrolled"). There is no
`from_date <= to_date` check and `company` is optional.

The points model is genuinely sound: `Loyalty Point Entry`
(`accounts/doctype/loyalty_point_entry/loyalty_point_entry.py:12`) is an **append-only ledger** and
the balance is a `SUM` (`get_loyalty_details`, `:55`). That is the same shape as our `settlement` and
`coupon_redemption` designs.

Three defects around it:

- ⚠️ `get_loyalty_program_details` (`accounts/doctype/loyalty_program/loyalty_program.py:118`):
  `company = frappe.db.get_default("company") or frappe.get_all("Company")[0].name` — when no company
  is passed it falls back to **an arbitrary company** (the first row returned, unordered). Loyalty
  balances are company-scoped in the query (`accounts/doctype/loyalty_program/loyalty_program.py:78`), so this
  silently reads the wrong company's points.
- ⚠️ `validate_loyalty_points` (`accounts/doctype/loyalty_program/loyalty_program.py:159`) reads the balance, compares, and proceeds — an unlocked
  read-then-check, so concurrent invoices can each redeem the full balance. Same shape as the coupon
  counter in doc 29 §7.1.
- ⚠️ Inside it:
  ```python
  if not ref_doc.loyalty_amount and ref_doc.loyalty_amount != loyalty_amount:
      ref_doc.loyalty_amount = loyalty_amount
  ```
  The value is written **only when currently falsy**, so a recalculation never corrects an already-set
  `loyalty_amount`. A stale redemption amount survives a change of points or conversion factor.

`get_redeemption_factor` (`accounts/doctype/loyalty_program/loyalty_program.py:147`) — the spelling is in the
function name and therefore in the API.

> **Ours** Keep the ledger, fix the arithmetic around it. `loyalty_entry` is append-only with
> `company_id NOT NULL` (no default fallback exists to get wrong), balance is a view, and redemption
> is an insert guarded by a deferred `CHECK (balance >= 0)` evaluated under the party's row lock —
> exactly the mechanism from doc 29 §7.1 (P4). Tier assignment is a function of the balance view, not a
> value copied onto the customer.

---

## 5. Banking configuration

### 5.1 `Bank` and `Bank Account`

`Bank` (`accounts/doctype/bank/bank.py:13`) is a thin master — with one thing worth noting:

⚠️ `plaid_access_token: DF.Data` (`:28`). An OAuth access token for a bank data provider is stored in
a plain `Data` field, in clear text, readable by anyone with read access to the doctype — while
`BankAccount.statement_password` in the same module *is* a `DF.Password`
(`accounts/doctype/bank_account/bank_account.py:43`). The framework offers the right type and it is
not used here.

`BankAccount` (`accounts/doctype/bank_account/bank_account.py:17`):

- `autoname` (`:51`): `self.account_name + " - " + self.bank` — a primary key built from two mutable
  text fields (doc 09 §2).
- `validate_account` (`:73`): a GL account may back only one Bank Account — enforced by a scan, not a
  unique index.
- `update_default_bank_account` (`:85`): the familiar `frappe.db.set_value` with a **filters dict** to
  clear `is_default` on siblings — the same unconstrained "one default" pattern as doc 29 §2 and
  `Payment Gateway Account` below.
- ⚠️ `on_trash` (`:54`) does `frappe.db.delete("Bank Account Balance", filters={"bank_account": self.name})`
  — deleting a bank account **destroys every recorded statement closing balance** for it. Those are the
  figures a bank reconciliation is proved against.
- ⚠️ `set_closing_balance_as_per_statement` (`:191`) is a whitelisted `POST` with **no explicit
  permission check**, unlike `get_bank_account_details` (`:132`) three functions above it, which does
  check. It creates or updates a `Bank Account Balance` for any `(bank_account, date)`.

`BankAccountBalance` (`accounts/doctype/bank_account_balance/bank_account_balance.py:8`) is `pass` —
so a statement balance is a freely editable row with no docstatus, no uniqueness on
`(bank_account, date)` beyond the caller's `frappe.db.exists` check, and no audit.

### 5.2 `Bank Transaction Rule` — the well-designed one

`BankTransactionRule` (`accounts/doctype/bank_transaction_rule/bank_transaction_rule.py:55`, 2026) is
the counter-example to `Tax Rule` (doc 28 §3) and `Pricing Rule` (doc 29 §4) and deserves credit.

- `priority` is a genuine **`DF.Int`**, not a string `Select`.
- `validate` (`:100`) is thorough: `min_amount <= max_amount`; per-`classify_as` required fields; for
  multi-account bank entries, the **last row must have no amount** because it is the computed
  balancing row; every referenced account's company must match the rule's company; and every
  user-supplied regex is **compiled in a `try`** (`:135`) so an invalid pattern is rejected at save
  time rather than failing during a nightly match.
- User formulas are screened by a **token allowlist**, not by a blacklist regex:

```python
ALLOWED_FORMULA_TOKEN = re.compile(r"\s+|transaction_amount|\d+(?:\.\d+)?|[+\-*/%^()]")   # :15
PYTHON_ONLY_OPERATORS = ("**", "//")                                                      # :16

def validate_amount_formula(formula: str) -> None:            # :29
    if PLAIN_NUMBER_PATTERN.match(stripped): return
    if any(op in stripped for op in PYTHON_ONLY_OPERATORS): frappe.throw(...)
    if not _is_expr_eval_formula(stripped): frappe.throw(...)
    python_formula = stripped.replace("^", "**")
    result = frappe.safe_eval(python_formula, eval_globals=None, eval_locals={"transaction_amount": 1})
    if not isinstance(result, (int | float)): frappe.throw(...)
```

Tokenise against an allowlist, balance the parentheses, reject Python-only operators, smoke-test the
expression, and type-check the result. Compare doc 29 §4.3, where a pricing-rule condition is screened
by one regex that leading whitespace defeats.

Two residual weaknesses: the allowlist is **duplicated in two languages** — the comment says "must
stay in sync with the frontend" — and `safe_eval` is still `safe_eval`. And `before_insert` (`:88`)
assigns `priority = max + 1` by an unlocked read-then-write, so two rules created concurrently share a
priority.

> **Ours** We adopt this shape for the one place we permit user arithmetic: a
> `formula` column with a **stored, parsed AST** (`jsonb`) produced by a parser we own, validated
> against a declared variable set at write time, and evaluated by a small interpreter over that AST —
> so there is no `eval` in any language and no allowlist to keep in sync. `priority smallint` with
> `UNIQUE (company_id, priority)` and explicit renumbering, not `max + 1`. Statement balances become
> `bank_statement_balance` with `UNIQUE (bank_account_id, as_of_date)`, append-only corrections, and
> `ON DELETE RESTRICT` from the bank account — a reconciliation's evidence cannot be deleted with the
> account.

### 5.3 `Cheque Print Template` and `Payment Gateway Account`

`ChequePrintTemplate` (`accounts/doctype/cheque_print_template/cheque_print_template.py:10`) stores
millimetre offsets for cheque printing and `create_or_update_cheque_print_format` (`:50`) **generates
a `Print Format` document** from them — configuration producing metadata, the pattern §7 and doc 18 §3
cover.

`PaymentGatewayAccount` (`accounts/doctype/payment_gateway_account/payment_gateway_account.py:9`):
`autoname` (`:27`) concatenates gateway + currency + company abbreviation into the primary key;
`validate` (`:31`) **overwrites** `self.currency` from the payment account's currency;
`update_default_payment_gateway` (`:37`) clears siblings' `is_default` by filters dict; and
`set_as_default_if_not_set` (`:46`) makes the row default when no other default exists — so the first
row silently becomes the default, as in doc 29 §2.1.

---

## 6. Reporting and allocation configuration

### 6.1 `Financial Report Template` writes to the source tree

`FinancialReportTemplate`
(`accounts/doctype/financial_report_template/financial_report_template.py:14`) lets a user define a
Balance Sheet / P&L layout as rows with `data_source`, `balance_type` and `calculation_formula`.

```python
def on_update(self):                                         # :52
    self._export_template()

def on_trash(self):                                          # :55
    self._delete_template()

def _export_template(self):                                  # :58
    from frappe.modules.utils import export_module_json
    if not self.module: return
    export_module_json(self, True, self.module)
    self._export_account_categories()

def _delete_template(self):                                  # :67
    if not self.module or not frappe.conf.developer_mode: return
    dir_path = os.path.join(frappe.get_module_path(self.module), "financial_report_template", frappe.scrub(self.name))
    shutil.rmtree(dir_path, ignore_errors=True)
```

⚠️ **Saving a report template writes files into the installed application's directory**, and
`_export_account_categories` (`:76`) goes further: it reads `account_categories.json` from the module
path, merges rows fetched from the `Account Category` table into it, sorts, and rewrites the file
(`:120`-`:124`). Deleting the template calls `shutil.rmtree` on a constructed module path.

This is the sharpest illustration in the whole investigation of the boundary problem doc 18 describes:
a report definition is simultaneously a database row and a file in the codebase, kept in sync by
document hooks, with a recursive directory delete on the trash path.

`sync_financial_report_templates` (`:130`) then reads them back per app at company-creation time.

### 6.2 `Monthly Distribution`

`MonthlyDistribution` (`accounts/doctype/monthly_distribution/monthly_distribution.py:11`) spreads an
annual budget across periods. `get_months` (`:30`) is a whitelisted helper that appends twelve rows at
`100.0 / 12` each — a value that cannot sum to 100 in binary floating point, immediately followed by:

```python
def validate(self):                                          # :53
    total = sum(flt(d.percentage_allocation) for d in self.get("percentages"))
    if flt(total, 2) != 100.0:
        frappe.throw(_("Percentage Allocation should be equal to 100%") + f" ({flt(total, 2)!s}%)")
```

It passes only because the comparison is rounded to two decimals. The month names are also stored as
**English strings** in a `Select`, so the child rows are keyed by an untranslatable label rather than a
month number — the same codes-not-labels problem as doc 30 §3.2, here in a column that ordering
depends on.

> **Ours** `allocation_profile` + `allocation_profile_period (period_no smallint, share numeric(9,6))`
> with `CHECK (share >= 0)` and a deferred `CHECK (Σ share = 1.000000)` per profile — an exact
> `numeric` sum, periods identified by number, and no month names anywhere. Report layouts are rows in
> `report_template` / `report_template_row` and never touch the filesystem; export is an explicit
> operation that produces an artifact, not a save-time side effect.

---

## 7. `Accounts Settings` — seventy flags, and what saving it does

`AccountsSettings` (`accounts/doctype/accounts_settings/accounts_settings.py:41`) is the single most
consequential configuration document in ERPNext. Its `validate` (`:121`) does far more than validate.

### 7.1 Saving it rewrites metadata, flushes the cache, and reschedules a cron job

```python
def validate(self):                                          # :121
    self.validate_auto_tax_settings()
    old_doc = self.get_doc_before_save()
    clear_cache = False
    if old_doc.add_taxes_from_item_tax_template != self.add_taxes_from_item_tax_template:
        frappe.db.set_default("add_taxes_from_item_tax_template", …); clear_cache = True
    if old_doc.enable_common_party_accounting != self.enable_common_party_accounting:
        frappe.db.set_default("enable_common_party_accounting", …); clear_cache = True
    self.validate_stale_days()
    if old_doc.show_payment_schedule_in_print != self.show_payment_schedule_in_print:
        self.enable_payment_schedule_in_print()          # Property Setters on 4 doctypes
    if old_doc.enable_accounting_dimensions   != …: toggle_accounting_dimension_sections(...)
    if old_doc.enable_discounts_and_margin    != …: toggle_sales_discount_section(...)
    if old_doc.enable_loyalty_point_program   != …: toggle_loyalty_point_program_section(...)
    if old_doc.enable_subscription            != …: toggle_subscription_sections(...)
    if old_doc.enable_overdue_billing_threshold != …: toggle_overdue_billing_threshold_field(...)
    if clear_cache: frappe.clear_cache()
    self.validate_and_sync_auto_reconcile_config()
    self.update_property_for_accounting_dimension()
```

Five distinct kinds of side effect:

1. **Global defaults** — two flags are mirrored into `DefaultValue` (`frappe.db.set_default`), giving
   the same two-sources-of-truth problem as doc 30 §10.1.
2. **Property Setters** — six `toggle_*` functions (`:225`-`:255`) hide sections across
   hook-supplied doctype lists, and `enable_payment_schedule_in_print` (`:171`) rewrites
   `due_date.print_hide` and `payment_schedule.print_hide` on four doctypes.
3. **A site-wide cache flush** — `frappe.clear_cache()` on any of those changes.
4. ⚠️ **A cron schedule** — `validate_and_sync_auto_reconcile_config` (`:187`) calls
   `sync_auto_reconcile_config(self.auto_reconciliation_job_trigger)`, so a numeric field on a
   settings form rewrites a `Scheduled Job Type`'s cron expression (doc 22 §3). Bounds are enforced
   (1–59 minutes; queue size 5–100), which is more than most.
5. ⚠️ **The immutability of submitted documents** — `update_property_for_accounting_dimension`
   (`:213`) → `set_allow_on_submit_for_dimension_fields` (`:264`):

```python
for dt in doctypes:
    for dimension in get_accounting_dimensions():
        df = meta.get_field(dimension)
        if df and not df.allow_on_submit:
            frappe.db.set_value("Custom Field", dt + "-" + dimension, "allow_on_submit", 1)
```

Saving Accounts Settings makes accounting-dimension fields **editable after submit**, by a direct
`db_set` to the `Custom Field` metadata table, with the Custom Field's name built by **string
concatenation**. A configuration save therefore changes which parts of a *posted* document can still
be altered — the property doc 06 §2 treats as the definition of submission.

One thing it gets right: `validate_auto_tax_settings` (`:203`) makes
`add_taxes_from_item_tax_template` and `add_taxes_from_taxes_and_charges_template` **mutually
exclusive**, closing a question doc 28 §4.4 left open.

`validate_stale_days` (`:165`) is another `msgprint(..., raise_exception=1)` throw-as-message.

### 7.2 The flags themselves

Seventy fields. Grouped by what they actually decide:

| Concern | Flags |
|---|---|
| **Ledger mutability** | `enable_immutable_ledger` (doc 01 §1.7), `delete_linked_ledger_entries`, `submit_journal_entries` |
| **Period / close** | `ignore_account_closing_balance`, `ignore_is_opening_check_for_reporting`, `use_legacy_controller_for_pcv`, `pcv_job_timeout` |
| **Cancellation** | `unlink_payment_on_cancellation_of_invoice`, `unlink_advance_payment_on_cancelation_of_order` |
| **Tax composition** | `add_taxes_from_item_tax_template`, `add_taxes_from_taxes_and_charges_template`, `round_row_wise_tax`, `book_tax_discount_loss`, `determine_address_tax_category_from` |
| **FX** | `allow_stale`, `stale_days`, `allow_pegged_currencies_exchange_rates`, `exchange_gain_loss_posting_date`, `allow_multi_currency_invoices_against_single_party_account` |
| **Reconciliation** | `auto_reconcile_payments`, `auto_reconciliation_job_trigger`, `reconciliation_queue_size`, `enable_fuzzy_matching`, `enable_party_matching`, `transfer_match_days`, `automatically_run_rules_on_unreconciled_transactions` |
| **Deferred revenue** | `automatically_process_deferred_accounting_entry`, `book_deferred_entries_based_on`, `book_deferred_entries_via_journal_entry` |
| **Tolerance + override role** | `over_billing_allowance`, `role_allowed_to_over_bill`, `maintain_same_rate_action`, `role_to_override_stop_action`, `enable_overdue_billing_threshold`, `role_allowed_to_bypass_overdue_billing`, `credit_controller` |
| **Feature switches** | `enable_accounting_dimensions`, `enable_common_party_accounting`, `enable_discounts_and_margin`, `enable_loyalty_point_program`, `enable_subscription` |
| **Legacy switches** | `use_legacy_budget_controller`, `use_legacy_controller_for_pcv`, `preview_mode` |
| **Implementation details** | `receivable_payable_fetch_method`, `general_ledger_remarks_length`, `receivable_payable_remarks_length`, `merge_similar_account_heads`, `repost_allowed_types` |

Three deserve naming:

- ⚠️ **`receivable_payable_fetch_method: Literal["Buffered Cursor", "UnBuffered Cursor"]`** — a
  **database driver cursor mode** exposed as a business configuration option. Whether a report streams
  or buffers is a performance decision for the engine, not a checkbox for an accountant.
- ⚠️ **`delete_linked_ledger_entries`** — a setting whose effect is to permit *deleting* ledger rows.
- ⚠️ **`ignore_account_closing_balance`** and **`ignore_is_opening_check_for_reporting`** — settings
  that switch off correctness checks in financial reporting. Two sites running the same version can
  produce different Balance Sheets from identical data.

Together with `maintain_same_rate_action` + `role_to_override_stop_action` (doc 30 §10.4) and
`role_allowed_to_over_bill`, this is the pattern to take away: **the severity of a rule, whether it is
checked at all, and who may bypass it are stored configuration.** "Valid" is therefore not a property
of the data.

`POSSettings` (`accounts/doctype/pos_settings/pos_settings.py:11`) is small and, notably, gets one
thing right that most of these do not: `validate_invoice_type` (`:47`) **refuses to change the
invoice-type setting while any `POS Opening Entry` is open** (`:29` gates it on the value actually
changing) — a configuration change blocked by the existence of in-flight documents.

### 7.3 FX configuration

`CurrencyExchangeSettings`
(`accounts/doctype/currency_exchange_settings/currency_exchange_settings.py:11`) and
`PeggedCurrencies` (`accounts/doctype/pegged_currencies/pegged_currencies.py:8`, `pass`) are covered
behaviourally in **[S06](../scenarios/S06-multi-currency.md)** §2–§3: the configurable API key path
(`set_parameters_and_result` `:44`, `validate_parameters` `:81`, `validate_result` `:100`,
`get_api_endpoint` `:115`), the HTTP call during document save, and the peg arithmetic. The
configuration finding to record here is structural: **the shape of a third-party HTTP response is
stored as configuration rows** — request parameters and a result key path — and `validate`
(`accounts/doctype/currency_exchange_settings/currency_exchange_settings.py:37`) proves it by making a
live call at save time.

> **Ours** Behaviour-changing configuration lives in `policy (company_id, policy_key, value jsonb)`
> validated against a stored JSON Schema, with every change appended to `policy_history` (actor,
> timestamp, before, after) — so "why did this document validate in March and fail in April" is a
> query. Rules that exist for correctness are **not** configurable: there is no
> `delete_linked_ledger_entries`, no `ignore_account_closing_balance`, no cursor-mode setting, and no
> `*_action = Stop|Warn`. Where an exception is genuinely needed it is an audited, expiring
> `policy_override` row (decision 22). Configuration never writes metadata, never mirrors itself into a
> defaults table, never reschedules a job, never flushes a global cache, and never changes whether a
> posted document is editable. Scheduling lives in `schedule` rows (doc 22 §7) that an operator edits
> directly.

---

## 8. Our design

### 8.1 Jobs are jobs; documents are documents

The batch-process pattern disappears entirely. `job` / `job_step` (doc 22 §7) give identity, state,
resumability, deduplication and progress without a docstatus, and the ledger rows a run produces carry
`posting_run_id` as a FK so reversal is addressable (§1.1).

| ERPNext | Ours |
|---|---|
| submitted document starts a job | `job` row with `dedupe_key` |
| two `status` columns synced by hand (§1.3) | one `state` + transition table |
| RQ job-name string as a mutex | `UNIQUE (job_kind, dedupe_key) WHERE state IN ('queued','running')` |
| resumability by two booleans | `job_step` rows with `FOR UPDATE SKIP LOCKED` |
| deduplicated runs stuck in `Queued` | `blocked_by_job_id` records why |
| progress in two counter columns | `COUNT(*) FILTER (WHERE state='done')` view |
| cancel = re-derive and negate GL rows | `reverses_entry_id` per row, by FK |

### 8.2 Instruments post

Nothing submittable is allowed to be economically invisible. A payment instruction posts to
payments-in-transit; a guarantee posts to a contingent memo ledger and its margin to restricted cash; a
till session's expected cash is a view over its payments. If a document records money, it has ledger
consequences — otherwise it is a note, and notes are not submittable.

### 8.3 Periodicity is a table, not a comparison

`subscription_period` with an `EXCLUDE` constraint on `(subscription_id, period)` makes billing
idempotent by construction (§3.2). The same shape covers deferral schedules (doc 12 §2), depreciation
schedules if Tranche C is in scope, and any other "once per period" rule — one mechanism, one
constraint.

### 8.4 Invariants

- **B1** Every ledger row written by a batch run carries `posting_run_id`; reversing a run inserts one
  compensating row per original row with `reverses_entry_id` set — `UNIQUE (reverses_entry_id)` makes
  double reversal impossible (§1.1).
- **B2** At most one `job` per `(job_kind, dedupe_key)` is `queued` or `running` — partial unique
  index (§1.3).
- **B3** A `job` in a terminal state has no `job_step` in a non-terminal state — deferred `CHECK`.
- **B4** At most one `subscription_period` per `(subscription_id, period)` — `EXCLUDE USING gist`
  (§3.2).
- **B5** A party's loyalty balance is never negative — deferred `CHECK` over `loyalty_entry` under the
  party row lock (§4).
- **B6** `Σ allocation_profile_period.share = 1` exactly, in `numeric` (§6.2).
- **B7** `UNIQUE (bank_account_id, as_of_date)` on statement balances, and they cannot be deleted while
  the bank account exists (§5.1).
- **B8** No `policy` value can disable a constraint. Policies may set thresholds and defaults; they may
  not turn checks off (§7.2).

---

## 9. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| A background job modelled as a submitted document | **Reject** | `job` / `job_step` tables |
| Cancel = re-select GL rows by `against_voucher` and negate | **Reject** | `posting_run_id` FK + `reverses_entry_id` (B1) |
| `ignore_linked_doctypes` to get past the link check | **Reject** | constraints, no bypass |
| `sub` referenced unbound in the `except` handler | **Reject (bug)** | per-item transaction with typed failure rows |
| Only `frappe.ValidationError` caught; batch dies on anything else | **Reject** | per-step isolation |
| `commit()` per item leaving batches half-applied | **Reject** | step-level transactions with recorded state |
| Two `status` columns synced by five writers | **Reject** | one `state` + transition table |
| RQ job-name string as the idempotency mutex | **Reject** | partial unique index (B2) |
| `process__{doc}` vs `process_{doc}` job-name typo | **Reject (bug)** | no name-based guards |
| `is_job_running` fetching every job on the site | **Reject** | indexed query on `job` |
| Queue dedupe leaving losing runs `Queued` forever | **Reject** | `blocked_by_job_id` |
| `msgprint` from a cron job | **Reject** | structured job log |
| `x.as_dict().update({...})` relying on a non-standard `update` | **Reject (fragile)** | explicit row construction |
| Hard-coded `invoice_limit = 1000` in a helper | **Reject** | policy value |
| `-> float` returning a dict; unreachable `return` after `throw` | **Reject** | typed interfaces |
| `Payment Order` with no `validate` | **Reject** | constraints |
| `set_value(self.payment_order_type, …)` — doctype from a field | **Reject** | typed FK per relationship |
| Cancel resetting a Payment Request to `Initiated` | **Reject (bug)** | transition table forbids it |
| `Payment Order.account` as `DF.Data` | **Reject** | FK to `account` |
| Generated Journal Entry left as a draft with `ignore_mandatory` | **Reject** | posted or not created |
| `Bank Guarantee` posting nothing | **Reject** | contingent memo ledger + restricted cash |
| `validity` (Int) **and** `end_date` with no consistency check | **Reject** | one `daterange` |
| Mandatory fields as three `throw`s in `on_submit` | **Reject** | `NOT NULL` / state-conditional `CHECK` |
| Whitelisted method raising a bare `TypeError` | **Reject** | typed API errors |
| `Cashier Closing` attributing invoices by `owner` | **Reject (bug)** | `cashier_party_id` + `till_id` |
| `returns` **added** to the net amount | **Reject (bug)** | signed view |
| No `company`, no currency, `Float` amounts | **Reject** | `company_id`, `currency_id`, `numeric(19,4)` |
| Submittable with no `on_submit` | **Reject** | if it is not posted it is not submittable |
| Billing idempotency by `posting_date` inside a period | **Reject** | `subscription_period` + `EXCLUDE` (B4) |
| A draft invoice blocking the next period (`docstatus < 2`) | **Reject** | explicit `period.state` |
| `process()` annotated `-> bool`, returning nothing | **Reject** | typed returns |
| **Late-fire window capped at one billing cycle** | **ADOPT** | same rule, as a `CHECK` on period generation |
| **Plan-vs-party currency validation** | **ADOPT** | `CHECK` on `subscription_plan.currency_id` |
| **Loyalty points as an append-only ledger** | **ADOPT** | `loyalty_entry`, balance as a view |
| `get_all("Company")[0]` as a company fallback | **Reject (bug)** | `company_id NOT NULL` |
| Unlocked read-then-check before redeeming points | **Reject** | deferred `CHECK (balance >= 0)` (B5) |
| `if not ref_doc.loyalty_amount` blocking recalculation | **Reject (bug)** | derived value |
| `plaid_access_token` in a plain `Data` field | **Reject** | secret store, never a readable column |
| `Bank Account` PK from `account_name + " - " + bank` | **Reject** | `uuid` PK |
| Deleting a bank account deleting its statement balances | **Reject** | `ON DELETE RESTRICT` (B7) |
| Whitelisted `POST` writing balances with no permission check | **Reject** | authorisation on every path |
| `Bank Account Balance` as a bare editable row | **Reject** | `UNIQUE (bank_account_id, as_of_date)`, append-only corrections |
| `is_default` cleared by a filters-dict `UPDATE` (3 doctypes) | **Reject** | partial unique index |
| First row silently becoming the default | **Reject** | explicit |
| **Formula validation by token allowlist + smoke test + type check** | **ADOPT the shape** | parsed AST, no `eval`, no cross-language duplication |
| **User regex compiled at save time** | **ADOPT** | same |
| **`priority` as a real integer** | **ADOPT** | `smallint` + `UNIQUE` |
| `priority = max + 1` unlocked | **Reject** | explicit renumbering |
| `Cheque Print Template` generating a `Print Format` | **Reject** | templates are data |
| **`Financial Report Template` writing JSON into the app directory** | **Reject** | `report_template` rows; export is an explicit artifact |
| `shutil.rmtree` on a module path from `on_trash` | **Reject** | no filesystem writes from documents |
| `Monthly Distribution` seeding `100.0/12` and rounding to pass | **Reject** | `numeric` shares summing to exactly 1 (B6) |
| Month names as English `Select` strings | **Reject** | `period_no smallint` |
| Settings mirrored into `DefaultValue` | **Reject** | one source of truth |
| Settings writing Property Setters (6 toggles) | **Reject** | no runtime metadata (decision 13) |
| Settings calling `frappe.clear_cache()` site-wide | **Reject** | no global metadata cache to flush |
| **Settings rewriting a cron schedule** | **Reject** | `schedule` rows edited directly |
| **Settings making dimension fields `allow_on_submit`** | **Reject** | posted rows are not updatable, by grant |
| `Custom Field` name built by string concatenation | **Reject** | no custom fields |
| **`receivable_payable_fetch_method` = cursor mode** | **Reject** | an engine decision, not a setting |
| `delete_linked_ledger_entries` | **Reject** | ledgers are append-only (decision 5) |
| `ignore_account_closing_balance`, `ignore_is_opening_check_for_reporting` | **Reject** | correctness is not configurable (B8) |
| `role_allowed_to_over_bill` / `role_to_override_stop_action` | **Reject** | audited expiring `policy_override` |
| **Mutually exclusive auto-tax flags enforced** | **ADOPT the intent** | not expressible — one composition path |
| **`POS Settings` refusing a change while entries are open** | **ADOPT** | policy changes gated on in-flight state |
| Third-party HTTP response shape stored as configuration | **Reject** | typed provider adapters in code (S06 §8) |
| `validate` making a live HTTP call | **Reject** | connectivity tested by an explicit action |

---

Cross-references: doc 01 §1.7 (reversal and the immutable-ledger switch), doc 11 §5 (insert-only
compensating rows), doc 12 §1–§2 (budgets and the deferral schedule), doc 13 §4 (POS closing, the
posted counterpart to §2.3), doc 14 (bank reconciliation, which §5 configures),
doc 18 §3 (the schema is data — §6.1 and §7.1 are its extreme cases),
doc 19 §3 (permission checks on whitelisted methods), doc 20 §5 (`db_set` and the audit trail),
doc 21 §3 (`safe_eval`), doc 22 §3 and §7 (scheduling, locking, and our `job` tables),
doc 28 §4.4 (the auto-tax flags §7.1 makes exclusive), doc 29 §7.1 (the coupon counter, same shape as
§4), doc 30 §10 (Selling/Buying Settings — the same catalogue for trade),
**[S05](../scenarios/S05-period-close-and-opening-balances.md)** §5 (`use_legacy_controller_for_pcv`),
**[S06](../scenarios/S06-multi-currency.md)** §2–§3 (FX settings and pegs),
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
