# 12 — Budgets, Deferred Revenue/Expense, and Cost Center Allocation

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

Three subsystems that all sit *between* a transaction and the general ledger, each rewriting or
constraining what gets posted. They are grouped here because they share one design flaw: each
recomputes state by scanning `GL Entry` at runtime instead of maintaining a model.

---

## 1. Budgets

### 1.1 Data model

| Table | Purpose |
|---|---|
| `Budget` | header: company, fiscal year range, `account`, one dimension value, `budget_amount`, six action fields |
| `Budget Account` | (legacy multi-account child rows in older versions; v17 has `account` on the header) |
| `Budget Distribution` | generated per-period rows: `start_date`, `end_date`, `amount`, `percentage` |
| `Monthly Distribution` + `Monthly Distribution Percentage` | reusable seasonality curve |

`Budget` is **submittable** (`docstatus`), and revision is by
`revise_budget` (`accounts/doctype/budget/budget.py:882`): cancel the old, `frappe.copy_doc`,
set `revision_of`, insert as draft. So budget history is an amend chain (doc 09 §4), with the
same problems.

### 1.2 The dimension is a column, and there is only one

A `Budget` row carries `account` plus **one** dimension value. Which dimension is determined by
which column happens to be non-empty. `validate_expense_against_budget`
(`accounts/doctype/budget/budget.py:377`) iterates:

```python
default_dimensions = [{"fieldname": "project",     "document_type": "Project"},
                      {"fieldname": "cost_center", "document_type": "Cost Center"}]
for dimension in default_dimensions + get_accounting_dimensions(as_list=False):
    budget_against = dimension["fieldname"]
    if params.get(budget_against) and params.account and root_type(params.account) == "Expense":
        ...
        query = query.where(getattr(b, budget_against) == params.get(budget_against))
```

(`accounts/doctype/budget/budget.py:428`–`:497`)

`getattr(b, budget_against)` — the column is selected by **string name at runtime**. This only
works because custom accounting dimensions physically `ALTER TABLE` `tabBudget` to add a column
(decision D13 rejects this; see doc 08). A budget "against Cost Center CC-1 **and** Project P-1"
cannot be expressed: two separate Budget rows would both match and both be checked
independently, which is not the same thing as a joint budget.

Tree dimensions get a rollup via nested sets:

```python
lft, rgt = frappe.get_cached_value(doctype, params.get(budget_against), ["lft", "rgt"])
query = query.where(ExistsCriterion(
    frappe.qb.from_(dim).select(dim.name)
        .where((dim.lft <= lft) & (dim.rgt >= rgt) & (dim.name == getattr(b, budget_against)))))
```

(`accounts/doctype/budget/budget.py:481`–`:489`) — find budgets on **ancestors** of the posting
dimension. Then `get_actual_expense` (`:758`) does the mirror-image scan for **descendants**
(`:781`–`:794`, `lft >= params.lft and rgt <= params.rgt`). Nested sets, with all the
maintenance cost that implies (decision D12 rejects them).

### 1.3 The check: read-then-compare, no reservation

`compare_expense_with_budget` (`accounts/doctype/budget/budget.py:540`):

```python
params.actual_expense = get_actual_expense(params)
if not amount:
    params.requested_amount = get_requested_amount(params)   # :689 — Material Request
    params.ordered_amount   = get_ordered_amount(params)     # :717 — Purchase Order
    if doctype == "Material Request" and for_material_request: amount = requested + ordered
    elif doctype == "Purchase Order" and for_purchase_order:   amount = ordered
total_expense = params.actual_expense + amount
if total_expense > budget_amount:
    ...
    if frappe.flags.exception_approver_role in frappe.get_roles(session.user): action = "Warn"
    if action == "Stop": frappe.throw(msg, BudgetError)
    else:                frappe.msgprint(msg)
```

`get_actual_expense` (`:758`) is a live aggregate:

```sql
SELECT SUM(debit) - SUM(credit) FROM `tabGL Entry`
WHERE is_cancelled = 0 AND account = ? AND posting_date BETWEEN ? AND ?
  AND company = ? AND docstatus = 1 AND <dimension rollup>
```

Problems:

1. **No reservation, no lock.** Two concurrent POs each read `actual_expense = 90` against a
   budget of 100 and each add 20. Both pass. Committed total 130. This is not a race in an
   obscure code path — it is the normal behaviour of a budget check implemented as
   `SELECT SUM(...)` followed by an unlocked write.
2. **Commitments are re-scanned, not accumulated.** `get_requested_amount` (`:689`) and
   `get_ordered_amount` (`:717`) scan Material Request Items and Purchase Order Items with
   `get_other_condition` (`:741`) building the dimension predicate. Every budget check on every
   line of every document runs three aggregate scans.
3. **`Stop` is downgradable at runtime.** `Company.exception_budget_approver_role`
   (`accounts/doctype/budget/budget.py:412`–`:415`, applied at `:578`–`:582`) turns a hard
   `throw` into a `msgprint` if the *current session user* holds a role. The budget was not
   approved; the check was simply not applied. Nothing is recorded.
4. **Six independent action fields.** `get_actions` (`:674`) picks from
   `action_if_annual_budget_exceeded`, `..._on_mr`, `..._on_po`, and the three
   `action_if_accumulated_monthly_budget_exceeded*` variants — a 2×3 matrix of enum columns
   rather than a policy table.

### 1.4 Monthly accumulation

`get_accumulated_monthly_budget` (`accounts/doctype/budget/budget.py:808`):

```sql
SELECT SUM(bd.amount) FROM `tabBudget Distribution` bd
JOIN `tabBudget` b ON bd.parent = b.name
WHERE b.name = ? AND bd.start_date <= ?
```

Cumulative budget up to the posting date. Then `params["month_end_date"] = get_last_day(...)`
(`:530`) narrows `get_actual_expense`'s upper bound (`:775`–`:776`). Note the query adds
`posting_date <= month_end_date` **on top of** the existing
`posting_date BETWEEN budget_start_date AND budget_end_date` range — two overlapping
predicates on the same column.

Distribution generation lives in `allocate_budget` (`:242`), guarded by
`_should_skip_allocation` (`:255`), `_should_recalculate_manual_distribution` (`:258`),
`_is_only_budget_amount_changed` (`:265`), `should_regenerate_budget_distribution` (`:281`),
`_regenerate_distribution` (`:300`), `get_budget_periods` (`:315`), `get_period_end` (`:333`),
`get_month_increment` (`:344`), `add_allocated_amount` (`:353`),
`validate_distribution_totals` (`:357`). Nine methods of change-detection heuristics to decide
whether to rebuild a child table — a symptom of derived data stored as rows.

### 1.5 Where the check is invoked

`validate_expense_against_budget` is called from
`distribute_gl_based_on_cost_center_allocation` (`accounts/general_ledger.py:179`–`:182`), i.e.
**inside GL map construction**, with `expense_amount = debit - credit`, and skipped when
`from_repost` is true (`:179`). So a repost of historical entries **does not re-check budgets**.
It is also called from Material Request and Purchase Order validation paths for commitment
checking.

### 1.6 Our design

```sql
CREATE TABLE budget (
    id                uuid PRIMARY KEY,
    company_id        uuid NOT NULL REFERENCES company(id),
    name              text NOT NULL,
    period_from       date NOT NULL,
    period_to         date NOT NULL,
    control_level     budget_control NOT NULL,   -- 'off','warn','block'
    commitment_basis  budget_commitment NOT NULL, -- 'actual','actual_plus_ordered','actual_plus_requested'
    revision_no       integer NOT NULL DEFAULT 1,
    supersedes_id     uuid REFERENCES budget(id),
    CONSTRAINT budget_period CHECK (period_from < period_to),
    UNIQUE (company_id, name, revision_no)
);

-- The dimension combination is a ROW, not a column
CREATE TABLE budget_line (
    id            uuid PRIMARY KEY,
    budget_id     uuid NOT NULL REFERENCES budget(id) ON DELETE CASCADE,
    company_id    uuid NOT NULL,
    account_id    uuid NOT NULL REFERENCES account(id),
    cost_center_id uuid REFERENCES cost_center(id),
    project_id     uuid REFERENCES project(id),
    dim1_id        uuid REFERENCES dim_value(id),   -- fixed slots, no ALTER TABLE (D13)
    dim2_id        uuid REFERENCES dim_value(id),
    amount         numeric(19,4) NOT NULL,
    UNIQUE (budget_id, account_id, cost_center_id, project_id, dim1_id, dim2_id)
);

CREATE TABLE budget_period (
    budget_line_id uuid NOT NULL REFERENCES budget_line(id) ON DELETE CASCADE,
    period_start   date NOT NULL,
    period_end     date NOT NULL,
    amount         numeric(19,4) NOT NULL,
    PRIMARY KEY (budget_line_id, period_start),
    CONSTRAINT budget_period_range CHECK (period_start <= period_end)
);
```

Key differences:

- **A budget line names a *combination* of dimensions.** Joint budgets ("CC-1 × Project-P1")
  are expressible. Matching is `IS NULL OR =` per slot, with specificity ordering.
- **`budget_commitment` ledger** replaces re-scanning:

```sql
CREATE TABLE budget_commitment (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL,
    budget_line_id uuid NOT NULL REFERENCES budget_line(id),
    source_type    commitment_source NOT NULL,  -- 'requisition','order','actual'
    voucher_id     uuid NOT NULL REFERENCES voucher(id),
    voucher_line_id uuid,
    effective_date date NOT NULL,
    amount_base    numeric(19,4) NOT NULL,
    released_by_id uuid UNIQUE REFERENCES budget_commitment(id),
    created_at     timestamptz NOT NULL DEFAULT now()
);
```

  Append-only, same pattern as `doc_link` and `settlement`. A PO *reserves* budget by inserting
  a commitment row; a receipt *releases* it (compensating row) and the actual posting inserts a
  new one. Consumption is a view. Point-in-time budget position is a `WHERE created_at <= t`.

- **The check holds a lock.** A deferred constraint trigger on `budget_commitment` does
  `SELECT ... FROM budget_period WHERE budget_line_id = ... FOR UPDATE` before comparing, which
  serialises concurrent commitments against the same budget line. The §1.3 double-spend is
  structurally impossible.
- **Overrides are recorded.** A `block` breach can only be bypassed by inserting a
  `budget_override` row (`budget_line_id`, `granted_by`, `granted_at`, `reason`, `amount`,
  `expires_at`) that the trigger consults. No silent role-based downgrade (§1.3 point 3).
- **Reposts re-check.** There is nothing to re-check: consumption is a view over commitments,
  so a corrected posting automatically corrects consumption. The `from_repost` skip (§1.5)
  has no analogue.
- Cumulative periods come from `SUM(amount) OVER (ORDER BY period_start)` on `budget_period`,
  not a stored running total.

---

## 2. Deferred revenue and expense

### 2.1 Model

Deferral is configured **per invoice line**: `Sales Invoice Item.enable_deferred_revenue`,
`deferred_revenue_account`, `service_start_date`, `service_end_date`, `service_stop_date`
(and the `deferred_expense_*` mirror on Purchase Invoice Item). At submit, the revenue posts to
the *deferred* account instead of income. A scheduled job then moves it across, month by month.

`Process Deferred Accounting` is the driver document; `process_deferred_accounting`
(`accounts/deferred_revenue.py:487`) is the scheduled entry point,
`convert_deferred_revenue_to_income` (`:112`) and
`convert_deferred_expense_to_expense` (`:74`) the two directions,
`build_conditions` (`:56`) the filter, `book_deferred_income_or_expense` (`:373`) the per-invoice
worker with its inner `_book_deferred_revenue_or_expense` (`:378`),
`make_gl_entries` (`:519`) the poster, `book_revenue_via_journal_entry` (`:604`) the
JE-based alternative, and `send_mail` (`:594`) the failure notifier.

### 2.2 `get_booking_dates` — state inferred from the ledger

`accounts/deferred_revenue.py:149`. To decide what period to book next, it **queries the GL**:

```python
prev_gl_entry = frappe.get_all("GL Entry", filters={
    "company": doc.company, "account": item.get(deferred_account),
    "voucher_type": doc.doctype, "voucher_no": doc.name,
    "voucher_detail_no": item.name, "is_cancelled": 0},
    fields=["name","posting_date"], order_by="posting_date desc", limit=1)
```

then **also** queries Journal Entry Accounts by
`(reference_type, reference_name, reference_detail_no)` with `docstatus < 2` (`:174`–`:192`),
and takes whichever is later (`:194`–`:198`). Then:

```python
start_date = add_days(prev_gl_entry[0].posting_date, 1) if prev_gl_entry else item.service_start_date
end_date   = get_last_day(start_date)
if end_date >= item.service_end_date:  end_date = item.service_end_date; last_gl_entry = True
elif item.service_stop_date and end_date >= item.service_stop_date:
                                        end_date = item.service_stop_date; last_gl_entry = True
if end_date > posting_date: end_date = posting_date
return (start_date, end_date, last_gl_entry) if start_date <= end_date else (None, None, None)
```

There is **no deferral schedule table**. The recognition state of a €120 000 annual contract is
"whatever the latest GL posting date against that account and voucher detail happens to be".
Consequences:

- Note `docstatus < 2` on the JE branch (`:189`) — **cancelled** journal entries are included
  when computing the last booked date, so a cancelled recognition JE still advances the cursor
  and that month is silently skipped.
- The GL branch filters `is_cancelled = 0` but the JE branch filters `docstatus < 2`. Two
  different notions of "not cancelled" in the same function.
- Any manual JE touching the deferred account with a matching
  `reference_detail_no` shifts the schedule.
- There is no way to see the *future* schedule. You cannot report "deferred revenue to be
  recognised in Q3" without simulating the algorithm.

### 2.3 Amount calculation — two algorithms, both lossy

`calculate_amount` (`accounts/deferred_revenue.py:280`) — straight-line by **days**:

```python
base_amount = flt(item.base_net_amount * total_booking_days / total_days, precision)
```

`calculate_monthly_amount` (`accounts/deferred_revenue.py:225`) — by **months**, with a
prorate factor:

```python
total_months = (end.year - start.year)*12 + (end.month - start.month) + 1
prorate_factor = date_diff(service_end, service_start) /
                 date_diff(get_last_day(service_end), get_first_day(service_start))
actual_months = rounded(total_months * prorate_factor, 1)
base_amount = flt(item.base_net_amount / actual_months, precision)
if base_amount + already_booked > item.base_net_amount:
    base_amount = item.base_net_amount - already_booked
if partial period:
    partial_month = date_diff(end_date, start_date) / date_diff(get_last_day(end_date), get_first_day(start_date))
    base_amount = rounded(partial_month, 1) * base_amount
```

`rounded(x, 1)` — **one decimal place** on a proration multiplier. A 17-day partial month gives
`17/30 = 0.5666… → 0.6`, a 5.9 % error on that month's recognition, silently absorbed by the
final-period plug.

Both algorithms end with the same plug: when `last_gl_entry` is true,
`base_amount = item.base_net_amount - already_booked_amount`
(`:264`–`:265`, `:295`–`:296`). So all accumulated rounding error lands in the final month.
`get_already_booked_amount` (`:306`) recomputes it by, again, aggregating GL Entry
(`SUM(debit)`/`SUM(credit)` per `voucher_detail_no`).

`date_diff` returns an *exclusive* day count, so `total_days` and `total_booking_days` are both
short by one; the ratio is close but not exact, and the discrepancy varies by month length.

`validate_service_stop_date` (`accounts/deferred_revenue.py:25`) enforces the date ordering.

### 2.4 Our design

```sql
CREATE TABLE deferral_schedule (
    id                 uuid PRIMARY KEY,
    company_id         uuid NOT NULL REFERENCES company(id),
    source_voucher_id  uuid NOT NULL REFERENCES voucher(id),
    source_line_id     uuid NOT NULL,
    kind               deferral_kind NOT NULL,       -- 'revenue','expense'
    deferral_account_id uuid NOT NULL REFERENCES account(id),
    target_account_id   uuid NOT NULL REFERENCES account(id),
    method             deferral_method NOT NULL,      -- 'straight_line_days','straight_line_months',
                                                      -- 'monthly_equal','milestone','usage'
    total_amount_base  numeric(19,4) NOT NULL,
    service_from       date NOT NULL,
    service_to         date NOT NULL,
    stopped_on         date,
    UNIQUE (source_line_id, kind)
);

CREATE TABLE deferral_period (
    id                 uuid PRIMARY KEY,
    schedule_id        uuid NOT NULL REFERENCES deferral_schedule(id) ON DELETE CASCADE,
    period_start       date NOT NULL,
    period_end         date NOT NULL,
    planned_amount_base numeric(19,4) NOT NULL,
    recognised_voucher_id uuid REFERENCES voucher(id),   -- NULL until recognised
    recognised_at      timestamptz,
    UNIQUE (schedule_id, period_start),
    CONSTRAINT deferral_recognised CHECK ((recognised_voucher_id IS NULL) = (recognised_at IS NULL))
);
```

- **The schedule is generated once, at posting time, and stored.** Future recognition is
  queryable (`SELECT ... WHERE recognised_at IS NULL`), auditable, and adjustable.
- **`Σ deferral_period.planned_amount_base = deferral_schedule.total_amount_base`** is a
  deferred constraint trigger. The rounding plug is applied deterministically **when the
  schedule is generated** (largest-remainder distribution across periods), not accumulated into
  the last month by accident.
- Recognition is idempotent: `recognised_voucher_id IS NULL` is the work queue, and the
  `UNIQUE (schedule_id, period_start)` plus the NOT-NULL transition means a period cannot be
  recognised twice even if the job runs concurrently (`UPDATE ... WHERE recognised_at IS NULL`
  returning 0 rows means someone else took it).
- Reversal of the source invoice reverses the *unrecognised* periods and posts a compensating
  voucher for the recognised ones. No GL scanning, no ambiguity about `docstatus < 2`.
- `method = 'milestone'` and `'usage'` are expressible — ERPNext has neither.
- Proration multipliers are `numeric`, not `rounded(x, 1)`.

---

## 3. Cost Center Allocation

### 3.1 What it does

A `Cost Center Allocation` document says: postings to `main_cost_center` on or after
`valid_from` should be **split** across `Cost Center Allocation Percentage` child rows.

`distribute_gl_based_on_cost_center_allocation` (`accounts/general_ledger.py:156`), called from
`process_gl_map` (`accounts/general_ledger.py:146`):

```python
for d in gl_map:
    cost_center_allocation = get_cost_center_allocation_data(company, posting_date, d.cost_center)
    if not cost_center_allocation: new_gl_map.append(d); continue
    if not from_repost:
        validate_expense_against_budget(d, expense_amount=flt(d.debit, precision) - flt(d.credit, precision))
    if d.account == round_off_account:
        d.cost_center = cost_center_allocation[0][0]     # first child, arbitrarily
        new_gl_map.append(d); continue
    for sub_cost_center, percentage in cost_center_allocation:
        gle = copy.deepcopy(d)
        gle.cost_center = sub_cost_center
        for field in ("debit","credit","debit_in_account_currency","credit_in_account_currency"):
            gle[field] = flt(flt(d.get(field)) * percentage / 100, precision)
        new_gl_map.append(gle)
```

`get_cost_center_allocation_data` (`accounts/general_ledger.py:200`) picks the allocation with
the **latest `valid_from <= posting_date`** — a `@request_cache`d lookup.

### 3.2 Defects

1. **Rounding is not conserved.** Each split line is `flt(amount * pct/100, precision)`
   independently. `100.00` split 33.33/33.33/33.34 is fine, but 1/3–1/3–1/3 at 2dp gives
   `33.33 × 3 = 99.99`. The lost cent is not redistributed here; it is left for
   `process_debit_credit_difference` (`accounts/general_ledger.py:397`) /
   `make_round_off_gle` (`:475`) to absorb into the round-off account. The allocation itself
   does not balance.
2. **The round-off line is dumped on `cost_center_allocation[0][0]`** (`:186`) — the *first
   child row in arbitrary order*. Cost centre reporting is therefore skewed by a
   non-deterministic amount.
3. **No nesting.** `validate_main_cost_center` (`accounts/doctype/cost_center_allocation/cost_center_allocation.py:119`)
   forbids a main cost centre that appears as a child anywhere (`:130`–`:141`), and
   `validate_child_cost_centers` (`:142`) forbids a child that is a main anywhere (`:144`–`:157`).
   Both are implemented by **scanning all submitted allocations** — `frappe.get_all("Cost Center
   Allocation", {"docstatus": 1}, "main_cost_center")` with no company filter (`:146`).
   Cross-company leakage: an allocation in Company A can block one in Company B.
4. **`valid_from` must be after the last GL entry on the main cost centre**
   (`validate_from_date_based_on_existing_gle`, `:68`) — but the check reads the *global*
   latest posting date for that cost centre with no company filter (`:74`–`:79`), and can be
   skipped entirely via `self._skip_from_date_validation` (`:56`).
5. **Overlapping validity is only a warning.** `validate_backdated_allocation` (`:88`)
   `msgprint`s that a later allocation exists and this one is therefore effective only up to
   `valid_from - 1` (`:106`–`:117`). There is no `valid_to` column and no exclusion constraint;
   the effective range is implied by "the next row's `valid_from`", resolved at query time by
   `ORDER BY valid_from DESC LIMIT 1`.
6. **Percentages must total exactly 100** (`validate_total_allocation_percentage`, `:62`) using
   `total_percentage != 100` on floats — `33.33 + 33.33 + 33.34` in float arithmetic is
   `99.99999999999999`, which fails. Users must enter values that happen to sum cleanly in
   binary floating point.

### 3.3 Our design

```sql
CREATE TABLE cost_allocation_rule (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES company(id),
    source_cost_center_id uuid NOT NULL REFERENCES cost_center(id),
    valid_from     date NOT NULL,
    valid_to       date,                       -- explicit, not implied
    rounding_target_index integer NOT NULL DEFAULT 0,  -- deterministic residual target
    EXCLUDE USING gist (
        company_id WITH =, source_cost_center_id WITH =,
        daterange(valid_from, COALESCE(valid_to, 'infinity'::date), '[)') WITH &&
    )
);

CREATE TABLE cost_allocation_target (
    rule_id        uuid NOT NULL REFERENCES cost_allocation_rule(id) ON DELETE CASCADE,
    seq            integer NOT NULL,
    cost_center_id uuid NOT NULL REFERENCES cost_center(id),
    ratio_num      bigint NOT NULL,      -- exact rational, not a float percent
    ratio_den      bigint NOT NULL,
    PRIMARY KEY (rule_id, seq),
    CONSTRAINT ratio_positive CHECK (ratio_num > 0 AND ratio_den > 0)
);
```

- **`EXCLUDE USING gist` on the validity range** makes overlapping rules impossible
  (§3.2 point 5), enforced by the database, per company (fixing the cross-company scan of
  point 3).
- **Ratios are exact rationals**, so "one third each" is `1/3, 1/3, 1/3` and the sum check is
  integer arithmetic, not float (`!= 100` on floats, point 6).
- **Splitting uses largest-remainder distribution** with the residual assigned to
  `rounding_target_index`: `Σ split = original` is guaranteed by construction, so the
  allocation balances on its own and never leans on the round-off account (point 1) and the
  residual lands somewhere deterministic (point 2).
- **Nesting is allowed and terminates**, because the rule graph is validated as a DAG with a
  recursive CTE at insert time (bounded depth), rather than forbidden by two mutually
  contradictory global scans.
- The rule is applied at posting time and the applied rule is recorded on each split
  `gl_entry` (`allocation_rule_id`, `allocation_seq`), so an entry's provenance is
  reconstructible. ERPNext leaves no trace of which allocation produced a line.

---

## 4. Cross-cutting position

All three subsystems demonstrate the same anti-pattern and the same fix:

| Anti-pattern | Instances | Our fix |
|---|---|---|
| Derive current state by aggregating `GL Entry` at runtime | `get_actual_expense` (§1.3), `get_booking_dates` (§2.2), `get_already_booked_amount` (§2.3) | Explicit model tables (`budget_commitment`, `deferral_period`) that are the source of truth |
| Check-then-write without a lock | budget check (§1.3), allocation validity (§3.2) | Deferred constraint triggers with `FOR UPDATE` on the controlling row |
| Validity ranges implied by "the next row's start date" | Cost Center Allocation (§3.2 pt 5), Item Price (doc 17 §4) | `valid_from`/`valid_to` + `EXCLUDE USING gist` |
| Float equality on percentages/money | `total_percentage != 100` (§3.2 pt 6), `paid_amount == total_amount` (doc 11 §2.4) | `numeric`, exact rationals, explicit rounding to minor units |
| Rounding residue absorbed by the round-off account | CC allocation (§3.2 pt 1), deferral final period (§2.3) | Largest-remainder distribution; `Σ parts = whole` as a constraint |
| Silent role-based downgrade of a hard control | `exception_budget_approver_role` (§1.3 pt 3), over-delivery bypass roles (doc 10 §1.3) | Explicit, dated, reasoned override rows |
| Runtime `getattr(table, column_name)` on dimension columns | budget matching (§1.2) | Fixed dimension slots + `gl_entry_dimension` (D13) |

Cross-references: doc 01 (GL posting, `process_gl_map`), doc 07 (period close),
doc 08 (implementation spec), doc 10 (allowance policy — same `EXCLUDE` pattern),
`docs/design/FINAL-SCHEMA.md`.
