# 10 — The Fulfilment Engine (orders → deliveries → invoices)

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

This is the mechanism that answers "how much of this order is still open?" — the single most
frequently asked question in an ERP, and the one ERPNext answers least reliably. It deserves the
most careful redesign of anything in the system.

---

## 1. What ERPNext actually built

There is one generic engine, `StatusUpdater` (`controllers/status_updater.py:182`), driven by a
**declarative config list** that each document class assigns to `self.status_updater` in its
`__init__`. Sixteen doctypes do this:

| Document | Config at |
|---|---|
| Sales Order | `selling/doctype/sales_order/sales_order.py:187` |
| Purchase Order | `buying/doctype/purchase_order/purchase_order.py:167` |
| Delivery Note | `stock/doctype/delivery_note/delivery_note.py:157` |
| Purchase Receipt | `stock/doctype/purchase_receipt/purchase_receipt.py:153` |
| Sales Invoice | `accounts/doctype/sales_invoice/sales_invoice.py:260` |
| Purchase Invoice | `accounts/doctype/purchase_invoice/purchase_invoice.py:224` |
| Material Request | `stock/doctype/material_request/material_request.py:90` |
| Stock Entry | `stock/doctype/stock_entry/stock_entry.py:167` |
| Pick List | `stock/doctype/pick_list/pick_list.py:82` |
| Packing Slip | `stock/doctype/packing_slip/packing_slip.py:39` |
| Installation Note | `selling/doctype/installation_note/installation_note.py:49` |
| Subcontracting Receipt | `subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:103` |

A config block is a dict describing a single **upstream aggregation edge**:

```python
{
  "source_dt":            "Delivery Note Item",   # child rows of THIS document
  "target_dt":            "Sales Order Item",     # rows to be updated
  "join_field":           "so_detail",            # source column holding target row's name
  "target_field":         "delivered_qty",        # cached counter on the target row
  "target_ref_field":     "qty",                  # the ordered quantity
  "source_field":         "qty",                  # what to sum
  "target_parent_dt":     "Sales Order",
  "target_parent_field":  "per_delivered",        # cached percentage on the target header
  "percent_join_field":   "against_sales_order",
  "status_field":         "delivery_status",
  "keyword":              "Delivered",
  "overflow_type":        "delivery",
  # optional second aggregation source, merged into the same counter:
  "second_source_dt":     "Sales Invoice Item",
  "second_source_field":  "qty",
  "second_join_field":    "so_detail",
  "second_source_extra_cond": "... and update_stock = 1",
}
```

(verbatim structure from `stock/doctype/delivery_note/delivery_note.py:157`–`:187`)

Delivery Note declares **three** such edges: SO Item, Sales Invoice Item (`no_allowance: 1`),
and Pick List Item.

### 1.1 The three-step algorithm

`update_prevdoc_status` (`controllers/status_updater.py:194`) → `update_qty`
(`controllers/status_updater.py:533`), for each config block:

**Step 1 — set the inclusion condition** (`:539`–`:543`):

```python
if self.docstatus == 1:  args["cond"] = " or parent=%s" % escape(self.name)
else:                    args["cond"] = " and parent!=%s" % escape(self.name)
```

On submit, include self (because the row may not yet be committed as `docstatus=1` in the
aggregation's view); on cancel, exclude self. This is a **string-concatenated SQL fragment**
whose polarity flips the meaning of the surrounding predicate — the source of a long tail of
subtle bugs.

**Step 2 — recompute the row counter** (`_update_children`, `:550`):

```sql
select coalesce(sum({source_field}), 0)
from `tab{source_dt}`
where `{join_field}` = %(detail_id)s
  and (docstatus = 1 {cond})
  {extra_cond}
```

plus, if configured, a second identical query against `second_source_dt` whose result is
**added** (`:594`). Then:

```sql
update `tab{target_dt}` set {target_field} = {source_dt_value} {update_modified}
where name = %(detail_id)s
```

Note this is a **full recompute per affected row per submit/cancel**, executed as raw SQL with
`.format(**args)` interpolation of identifiers. There is no `WHERE modified = ...` guard, so
this write is *outside* the optimistic-lock scheme (doc 09 §1.3).

**Step 3 — recompute the header percentage** (`_update_percent_field_in_targets`, `:641` →
`_update_percent_field`, `:658` → `_calculate_target_parent_percentage`, `:606`):

```python
sum_ref = Σ abs(row[target_ref_field])                       # Σ ordered
pct     = Σ min(abs(row[target_field]), abs(row[ref_field]))  # Σ LEAST(achieved, ordered)
          / sum_ref * 100    (rounded to 6dp)
```

The `min()` is the **cap**: over-delivering line A cannot compensate for under-delivering
line B. `sum_ref == 0` → `pct = 0`.

`_determine_status` (`:633`) then buckets it:

```
pct < 0.001        → "Not {keyword}"
pct >= 99.999999   → "Fully {keyword}"
else               → "Partly {keyword}"
```

and `_update_percent_field` (`:658`) writes header percentage + status field, re-derives the
document status via `target.get_status()` (`:672`–`:675`), and persists with
`target.db_set(update_data, update_modified=update_modified, notify=True)` (`:678`).

`db_set` writes **directly to the database, bypassing `validate`, bypassing the
timestamp lock, on a submitted document**. See §7.

### 1.2 The header status derivation

`set_status` (`controllers/status_updater.py:198`) / `get_status` (`:219`) evaluate the
`status_map` table (`controllers/status_updater.py:21`) — a list of
`[status, "eval:<python expression>"]` pairs per doctype, **first match wins in reverse
priority order**. Sales Order (`:43`):

```
Draft                 (None)
To Deliver and Bill   per_delivered < 100 and per_billed < 100 and docstatus == 1
To Bill               (per_delivered >= 100 or skip_delivery_note) and per_billed < 100 and docstatus == 1
To Deliver            per_delivered < 100 and per_billed >= 100 and docstatus == 1 and not skip_delivery_note
To Pay                advance_payment_status == 'Requested' and docstatus == 1
Completed             (per_delivered >= 100 or skip_delivery_note) and per_billed >= 100 and docstatus == 1
Cancelled             docstatus == 2
Closed                status == 'Closed' and docstatus != 2
On Hold               status == 'On Hold'
```

Observations:

- The conditions are **`eval()`'d Python strings stored in a module-level dict**. Not data, not
  SQL, not a state machine — source-code strings interpreted at runtime.
- `Closed` and `On Hold` conditions read `self.status` — the field being computed. The status is
  therefore **self-referential and sticky**: once `Closed`, it re-derives to `Closed`.
  `close_or_unclose_sales_orders` (`selling/doctype/sales_order/sales_order.py:714`) is the
  escape hatch.
- `To Pay` is wedged into the same list but keyed off `advance_payment_status`, an unrelated
  axis (doc 11). Purchase Order uses `'Initiated'`, Sales Order uses `'Requested'` — the same
  concept, different enum values (`controllers/status_updater.py:57`, `:81`).
- Purchase Order uses `per_billed == 100` (exact) where Sales Order uses `per_billed >= 100`
  (`:71` vs `:63`). Over-billing a PO therefore leaves it *not* `Completed`, forever.
  Sales Order over-billing completes normally. **Asymmetric by accident.**
- Delivery Note uses `per_billed == 0` / `== 100` (`:94`–`:96`) while Purchase Receipt uses
  `>= 100` with an extra `grand_total == 0` clause (`:109`–`:112`). Four documents, four
  different comparison conventions on the same derived number.

### 1.3 Over-delivery / over-billing allowance

`validate_qty` (`controllers/status_updater.py:266`) → `check_overflow_with_allowance` (`:419`):

```python
overflow_percent = (achieved - ordered) / ordered * 100
if overflow_percent - allowance > 0.01:
    if role not in frappe.get_roles(): limits_crossed_error(...)   # throw
    else:                              warn_about_bypassing_with_role(...)   # msgprint
```

`get_allowance_for` (`:746`) resolves the allowance with a three-level fallback:
`Item.over_delivery_receipt_allowance` → `Stock Settings.over_delivery_receipt_allowance`
(qty) or `Item.over_billing_allowance` → `Accounts Settings.over_billing_allowance` (amount).
The settings doctype/field names are themselves config keys (`global_allowance_doctype`,
`global_allowance_field`, `:425`–`:427`) so different edges consult different settings.

Bypass roles: `Stock Settings.role_allowed_to_over_deliver_receive` (qty) and
`Accounts Settings.role_allowed_to_over_bill` (amount) (`:450`–`:454`). Holding the role
downgrades a hard error to a message.

`validate_qty` also enforces sign rules (`:280`–`:287`): non-return rows must have `qty > 0`,
return rows must have `qty < 0`, and negative `rate` is blocked unless
`Selling Settings.allow_negative_rates_for_items` / `Buying Settings.…` is enabled
(`:289`–`:314`).

Pick List Item is hard-coded to **zero allowance** (`:445`–`:447`).

---

## 2. Where the fulfilment link actually lives

The link is a **column on the downstream child row** pointing at the upstream child row's
`name` (a string PK). There is no join table. Per pair:

| Downstream row | Column → upstream row | Header column |
|---|---|---|
| `Sales Order Item` | `quotation_item` → `Quotation Item` | `prevdoc_docname` |
| `Delivery Note Item` | `so_detail` → `Sales Order Item` | `against_sales_order` |
| `Delivery Note Item` | `si_detail` → `Sales Invoice Item` | `against_sales_invoice` |
| `Delivery Note Item` | `pick_list_item` → `Pick List Item` | `against_pick_list` |
| `Sales Invoice Item` | `so_detail` → `Sales Order Item` | `sales_order` |
| `Sales Invoice Item` | `dn_detail` → `Delivery Note Item` | `delivery_note` |
| `Purchase Receipt Item` | `purchase_order_item` → `Purchase Order Item` | `purchase_order` |
| `Purchase Invoice Item` | `po_detail` → `Purchase Order Item` | `purchase_order` |
| `Purchase Invoice Item` | `pr_detail` → `Purchase Receipt Item` | `purchase_receipt` |
| `Purchase Order Item` | `material_request_item` → `Material Request Item` | `material_request` |
| `Purchase Order Item` | `sales_order_item` → `Sales Order Item` | `sales_order` (drop-ship) |

Structural problems:

1. **The link is 1:1 per pair, not many-to-many.** A delivery line can name one SO line
   (`so_detail`). If a single delivery line satisfies parts of two SO lines, it cannot be
   expressed; the user must split the delivery line. Conversely one SO line satisfied by many
   delivery lines works fine (many rows point at it).
2. **Every new relationship needs new columns** on both child tables plus a new config block.
   The `n × m` growth is why `Delivery Note Item` carries `so_detail`, `si_detail`,
   `pick_list_item`, `dn_detail` (returns), `packed_items` references, and more.
3. **The counters are denormalised caches.** `Sales Order Item.delivered_qty`,
   `.billed_amt`, `.returned_qty`, `.work_order_qty`, `.picked_qty`,
   `Sales Order.per_delivered`, `.per_billed`, `.per_picked` — each is a materialised
   aggregate maintained by imperative recompute. When any recompute is missed (background job
   failure, `ignore_links`, direct SQL, bulk deletion), the cached value silently diverges from
   the truth and there is **no constraint that can detect it**.
4. **Mixed units in one counter.** The Delivery-Note→SO-Item edge sums
   `Delivery Note Item.qty` (transaction UOM) while the Pick-List edge sums
   `stock_qty` (stock UOM) into `Pick List Item.delivered_qty` against `picked_qty`
   (`stock/doctype/delivery_note/delivery_note.py:196`–`:199`). Comparing the two counters
   across edges is meaningless.
5. **Two source tables feed one counter.** `Sales Order Item.delivered_qty` is
   `Σ Delivery Note Item.qty + Σ Sales Invoice Item.qty where SI.update_stock = 1`
   (`stock/doctype/delivery_note/delivery_note.py:170`–`:176`). The `second_source_extra_cond`
   is a correlated `EXISTS` subquery embedded as a **string in a Python dict**. If a POS
   invoice's `update_stock` is later changed, the counter is wrong until something re-triggers
   the recompute.
6. **Amend destroys the link.** Child `name` values are regenerated on amend (doc 09 §4), so
   `so_detail` on an existing delivery points at a row that no longer exists.

---

## 3. Billing status for zero-amount documents

`update_billing_status_for_zero_amount_refdoc` (`controllers/status_updater.py:694`) and
`update_billing_status` (`:710`) exist because the percentage formula divides by
`Σ amount`. A zero-value order (free samples, warranty replacement) has `sum_ref = 0` → `pct = 0`
→ never `Completed`. The workaround: detect zero-amount reference documents and force
`per_billed = 100`.

This is a **structural** consequence of expressing progress as a ratio of amounts. Our design
(§5) uses a per-line `is_closed` flag plus quantity-based progress, so a zero-value line closes
on quantity, not on money.

---

## 4. Closing and holding

Three orthogonal overrides exist on top of the derived status:

- **Closed** — user says "no more against this". `close_or_unclose_sales_orders`
  (`selling/doctype/sales_order/sales_order.py:714`), `update_status`
  (`selling/doctype/sales_order/sales_order.py:780`, and the method at `:541`).
  Implemented by writing the string `"Closed"` into `status`, which then satisfies its own
  eval condition. There is no `closed_at`, no `closed_by`, no reason.
- **On Hold** — same mechanism, different string. Purchase Order adds
  `Hold Type` / `release_date` fields, checked by
  `get_supplier_block_status` (`controllers/accounts_controller.py:1556`) and
  `ensure_supplier_is_not_blocked` (`controllers/accounts_controller.py:153`).
- **`skip_delivery_note`** — a Sales Order flag that makes `per_delivered` irrelevant
  (`controllers/status_updater.py:51`, `:63`). A boolean that changes the meaning of a
  percentage.

`check_nextdoc_docstatus` (`selling/doctype/sales_order/sales_order.py:526`) blocks SO
cancellation while submitted downstream documents exist — application-level, after the fact
(doc 09 §1.4).

---

## 5. Our design: links as data, progress as a view

Decision D7. Two changes, and everything above collapses.

### 5.1 `doc_link` — the universal fulfilment edge

```sql
CREATE TABLE doc_link (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES company(id),

    -- upstream (what is being fulfilled)
    source_doc_type     doc_type NOT NULL,      -- enum, not a string
    source_doc_id       uuid NOT NULL,
    source_line_id      uuid NOT NULL,          -- stable across revisions

    -- downstream (what fulfils it)
    target_doc_type     doc_type NOT NULL,
    target_doc_id       uuid NOT NULL,
    target_line_id      uuid NOT NULL,

    link_kind           link_kind NOT NULL,     -- 'order','deliver','bill','receive','pick','return','pack','produce'
    qty_stock           numeric(21,9) NOT NULL, -- ALWAYS stock UOM
    amount_base         numeric(19,4) NOT NULL, -- ALWAYS company currency
    reverses_link_id    uuid UNIQUE REFERENCES doc_link(id),
    created_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT doc_link_pair_valid CHECK (
        (source_doc_type, target_doc_type, link_kind) IN (
            ('quotation','sales_order','order'),
            ('sales_order','delivery_note','deliver'),
            ('sales_order','sales_invoice','bill'),
            ('sales_order','pick_list','pick'),
            ('delivery_note','sales_invoice','bill'),
            ('delivery_note','delivery_note','return'),
            ('purchase_order','purchase_receipt','receive'),
            ('purchase_order','purchase_invoice','bill'),
            ('purchase_receipt','purchase_invoice','bill'),
            ('purchase_receipt','purchase_receipt','return'),
            ('material_request','purchase_order','order'),
            ('sales_order','purchase_order','order')       -- drop ship
            -- extended, not multiplied, as the model grows
        )
    )
);
CREATE INDEX doc_link_src ON doc_link (source_line_id, link_kind);
CREATE INDEX doc_link_tgt ON doc_link (target_line_id, link_kind);
CREATE UNIQUE INDEX doc_link_no_dup
    ON doc_link (source_line_id, target_line_id, link_kind)
    WHERE reverses_link_id IS NULL;
```

What this buys:

- **Many-to-many for free.** One delivery line can satisfy three order lines: three
  `doc_link` rows. One order line satisfied by ten deliveries: ten rows. No column growth, no
  line splitting forced on the user.
- **A new relationship is a new enum value + one `CHECK` tuple**, not two migrations and a
  config block.
- **Real FKs.** `source_line_id` / `target_line_id` reference the concrete `*_line` tables
  through per-type FK views is not possible directly, so we enforce it with a
  `line_registry(line_id uuid PK, doc_type doc_type, doc_id uuid, company_id uuid)` table that
  every `*_line` table inserts into via trigger, and `doc_link` FKs to `line_registry`.
  That gives us database-enforced integrity on a polymorphic edge — the one place we accept
  a registry, because the alternative (11+ nullable FK columns) is worse.
- **Units are normalised at write time.** `qty_stock` is always stock UOM, `amount_base`
  always company currency. Cross-edge comparison is meaningful.
- **Reversal is a compensating row** (`reverses_link_id UNIQUE`), never an UPDATE.
  A cancelled delivery inserts negating links; the ordered-vs-delivered view is instantly
  correct with no recompute.

### 5.2 Progress as views, not columns

```sql
CREATE VIEW fulfilment_line AS
SELECT
    l.line_id,
    l.doc_type,
    l.doc_id,
    l.company_id,
    l.qty_stock                                             AS ordered_qty,
    l.amount_base                                           AS ordered_amount,
    COALESCE(f.deliver_qty, 0)                              AS delivered_qty,
    COALESCE(f.bill_amount, 0)                              AS billed_amount,
    COALESCE(f.return_qty, 0)                               AS returned_qty,
    COALESCE(f.pick_qty, 0)                                 AS picked_qty,
    l.qty_stock - COALESCE(f.deliver_qty, 0)
                + COALESCE(f.return_qty, 0)                 AS open_qty,
    l.amount_base - COALESCE(f.bill_amount, 0)              AS unbilled_amount,
    l.is_closed
FROM line_registry_v l
LEFT JOIN (
    SELECT source_line_id,
           SUM(qty_stock)   FILTER (WHERE link_kind = 'deliver') AS deliver_qty,
           SUM(qty_stock)   FILTER (WHERE link_kind = 'receive') AS receive_qty,
           SUM(qty_stock)   FILTER (WHERE link_kind = 'pick')    AS pick_qty,
           SUM(qty_stock)   FILTER (WHERE link_kind = 'return')  AS return_qty,
           SUM(amount_base) FILTER (WHERE link_kind = 'bill')    AS bill_amount
    FROM doc_link
    GROUP BY source_line_id
) f ON f.source_line_id = l.line_id;

CREATE VIEW fulfilment_doc AS
SELECT
    doc_id, doc_type, company_id,
    SUM(ordered_qty)                                        AS ordered_qty,
    SUM(LEAST(delivered_qty, ordered_qty))                  AS credited_delivered_qty,
    CASE WHEN SUM(ordered_qty) > 0
         THEN ROUND(SUM(LEAST(delivered_qty, ordered_qty)) / SUM(ordered_qty) * 100, 6)
         ELSE 100 END                                       AS per_delivered,
    CASE WHEN SUM(ordered_amount) > 0
         THEN ROUND(SUM(LEAST(billed_amount, ordered_amount)) / SUM(ordered_amount) * 100, 6)
         ELSE 100 END                                       AS per_billed,
    bool_and(is_closed OR delivered_qty >= ordered_qty)      AS delivery_complete,
    bool_and(is_closed OR billed_amount >= ordered_amount)   AS billing_complete
FROM fulfilment_line
GROUP BY doc_id, doc_type, company_id;
```

Notes on the formula choices:

- We **keep ERPNext's capped ratio** `Σ LEAST(achieved, ordered) / Σ ordered × 100`. It is the
  right semantic: over-shipping one line does not close another. We keep the 6-dp rounding for
  presentational stability.
- We **fix the zero-value case**: `Σ ordered = 0 → 100`, not `0`. No
  `update_billing_status_for_zero_amount_refdoc` special case needed (§3).
- We add `bool_and(is_closed OR ...)` completeness flags so "done" is a boolean, not a float
  compared against `99.999999`.
- All four documents use the **same** comparison convention. No `== 100` vs `>= 100` drift (§1.2).
- Because these are views over an append-only table, **there is nothing to invalidate**. No
  repost queue, no background job, no drift. Correctness is a property of the schema.

If the view is too slow at scale, the mitigation is a `MATERIALIZED VIEW` refreshed
concurrently, or an incrementally-maintained summary table populated by a trigger on
`doc_link` — but the *source of truth stays the links*, and a full rebuild is one statement.
That is a performance decision made later against measurements, not a correctness compromise
baked into the schema.

### 5.3 Status as data

```sql
CREATE TABLE doc_status_rule (
    id            uuid PRIMARY KEY,
    doc_type      doc_type NOT NULL,
    status_code   text NOT NULL,
    priority      integer NOT NULL,      -- explicit, not list order
    predicate_sql text NOT NULL,         -- evaluated against fulfilment_doc + document row
    UNIQUE (doc_type, priority)
);
```

Status is derived in a view by `LATERAL`-joining the highest-priority satisfied rule. The
predicate is SQL over the *view*, so it cannot read the field it is computing — the
self-referential `status == 'Closed'` trick (§4) becomes impossible by construction.

`Closed` / `On Hold` become **explicit columns** with provenance:

```sql
closed_at      timestamptz,
closed_by      uuid REFERENCES app_user(id),
close_reason   text,
hold_until     date,
hold_reason    text,
CONSTRAINT closed_consistent CHECK ((closed_at IS NULL) = (closed_by IS NULL))
```

`is_closed` on the *line* (not just the header) means partial closure is expressible:
"ship what we have, cancel the rest of line 3" — a first-class operation ERPNext cannot
represent without editing a submitted document.

### 5.4 Allowance as policy rows

```sql
CREATE TABLE fulfilment_allowance (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES company(id),
    link_kind      link_kind NOT NULL,
    scope          allowance_scope NOT NULL,   -- 'global','item_group','item','customer','contract'
    scope_id       uuid,
    basis          allowance_basis NOT NULL,   -- 'qty','amount'
    percent        numeric(9,6) NOT NULL DEFAULT 0,
    absolute_max   numeric(21,9),              -- ERPNext has no absolute cap; we do
    bypass_role_id uuid REFERENCES role(id),
    valid_from     date NOT NULL,
    valid_to       date,
    EXCLUDE USING gist (
        company_id WITH =, link_kind WITH =, scope WITH =,
        coalesce(scope_id,'00000000-0000-0000-0000-000000000000') WITH =,
        basis WITH =, daterange(valid_from, valid_to, '[)') WITH &&
    )
);
```

Resolution is a single ordered `SELECT` by scope specificity, not a hard-coded
Item→Settings fallback across two different settings singletons (§1.3). The `EXCLUDE`
constraint means **overlapping allowance rules are impossible** — contrast `Item Price`,
which has no overlap detection at all (doc 17 §4).

### 5.5 Over-fulfilment enforcement

A deferred constraint trigger on `doc_link`:

```
for each affected source_line_id:
    resolve allowance (company, link_kind, item, customer, contract, date)
    achieved := Σ qty_stock over non-reversed links of this kind
    limit    := ordered_qty * (1 + percent/100)
    if absolute_max is not null: limit := LEAST(limit, ordered_qty + absolute_max)
    if achieved > limit + 1e-9 and not session has bypass role:
        RAISE
```

Deferred to end-of-transaction means a delivery that first over-ships and then corrects within
the same transaction is fine, while the *committed* state can never violate the allowance.
ERPNext's check runs mid-`validate` on in-memory values and is therefore both stricter
(intra-transaction false positives) and weaker (no guarantee about the committed state, since
another concurrent delivery can pass the same check — the classic read-check-write race).

---

## 6. Flexibility scenarios: ERPNext vs ours

| Scenario | ERPNext | Ours |
|---|---|---|
| One delivery line satisfies two order lines | Impossible; split the line | Two `doc_link` rows |
| Two order lines merged into one invoice line | Impossible | Two `doc_link` rows |
| Order line partially cancelled, rest shipped | Edit submitted SO (`update_items`) or amend | `line.is_closed = true` + `close_reason` |
| Ship 105 of 100 with buyer approval | Global/item allowance %, role bypass | Contract-scoped allowance row, absolute cap, audited bypass |
| Invoice before delivery *and* delivery before invoice on the same order | Works, but `per_billed`/`per_delivered` are independent caches that can disagree | Both are `FILTER`ed aggregates over one table; cannot disagree |
| Deliver in kg, order in bags | `stock_qty` vs `qty` mixed across edges | `qty_stock` normalised at write |
| "What was open on 30 June?" | Impossible — counters are current-value only | `WHERE created_at < '2026-07-01'` on `doc_link` |
| Zero-value order completes | Special-case code path (§3) | `Σ ordered = 0 → 100` in the view |
| Return reduces open qty | `returned_qty` counter + `per_returned`, separate recompute | `link_kind = 'return'` in the same aggregate |
| Order amended | Links dangle | `line_id` is stable; links survive |
| Audit "who closed this order and why" | Not recorded | `closed_by`, `closed_at`, `close_reason` |

The row marked "impossible → possible" for point-in-time open quantity is the one that matters
most commercially. Because `doc_link` is append-only with `created_at`, **every fulfilment
figure is reconstructible as of any timestamp**. ERPNext cannot answer "what was our order book
at month end" from its own data; it needs a nightly snapshot job.

---

## 7. The concurrency defect worth understanding

`_update_percent_field` (`controllers/status_updater.py:658`) ends with:

```python
target = frappe.get_lazy_doc(args["target_parent_dt"], args["name"])
target.update(update_data)
status = target.get_status()
...
target.db_set(update_data, update_modified=update_modified, notify=True)
```

and `_update_children` (`:550`) ends with a raw `UPDATE ... SET target_field = <literal>`.

Neither takes a lock on the target row. Neither carries a `WHERE modified = ...` guard. So:

```
T1: submit DN-1 for SO-Line-X    T2: submit DN-2 for SO-Line-X
    SELECT sum(qty) → 10                SELECT sum(qty) → 10
                                        UPDATE delivered_qty = 10
    UPDATE delivered_qty = 10
```

Both computed `sum` before either's row was visible as `docstatus = 1`, and the `or parent=<self>`
condition (§1.1 step 1) only adds *its own* rows. Final `delivered_qty = 10` when it should be
20. The order is under-delivered forever, and no constraint will ever notice.

The same shape of bug appears in `outstanding_amount` (doc 04 §6) and `Bin.actual_qty`
(doc 02). It is not an implementation slip — it is the inevitable consequence of storing a
derived aggregate in an unlocked column.

**Our position:** the aggregate does not exist as a column, so the race does not exist.
When performance forces a cache, it is a `MATERIALIZED VIEW` (atomic swap) or a
trigger-maintained table with the trigger holding the row lock the trigger's own `UPDATE`
implies — never an application-level read-then-write.

---

Cross-references: doc 06 (status/returns as ERPNext models them), doc 09 (lifecycle),
doc 11 (advances and payment allocation), doc 16 (reservation/picking),
`docs/design/FINAL-SCHEMA.md` §Fulfilment views.
