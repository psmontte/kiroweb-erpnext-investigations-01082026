# 13 — POS and Retail

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

POS is where ERPNext's accounting model meets high-frequency, low-value, offline-tolerant
transactions — and it copes by building a **parallel document type that does not post to the
general ledger**, then batch-merging it into real invoices later. That decision cascades into
about a dozen structural problems, all of which are visible in the code.

---

## 1. The architecture

```
POS Opening Entry (docstatus 1)          ← cash drawer opened, period starts
      │
      ├── POS Invoice  (docstatus 1)     ← NO GL entries, NO stock ledger entries
      ├── POS Invoice  (docstatus 1)     ← posts only: Loyalty, Serial/Batch Bundle,
      ├── POS Invoice  (docstatus 1)        coupon count, "reserved qty" via live query
      │
POS Closing Entry (docstatus 1)          ← reconcile drawer, then:
      │
      └── POS Invoice Merge Log  ──▶ Sales Invoice (consolidated)  ← GL + stock finally posted
                                └──▶ Sales Invoice (credit note)   ← for returns
```

Key tables:

| Table | Role |
|---|---|
| `POS Profile` + `POS Payment Method`, `POS Item Group`, `POS Customer Group`, `POS Field` | terminal configuration |
| `POS Settings` (Single) | `invoice_type`: "POS Invoice" or "Sales Invoice" |
| `POS Opening Entry` + `POS Opening Entry Detail` | session start, opening float per payment method |
| `POS Invoice` (extends `Sales Invoice`) + `POS Invoice Item` | the till receipt |
| `POS Closing Entry` + `POS Closing Entry Detail`, `POS Closing Entry Taxes`, `POS Invoice Reference` | session end, expected vs counted |
| `POS Invoice Merge Log` + `POS Invoice Reference` | the batch consolidation job |
| `Loyalty Program`, `Loyalty Point Entry` | points |

`POSInvoice` is a **Python subclass of `SalesInvoice`**
(`accounts/doctype/pos_invoice/pos_invoice.py:33`) but a *separate DocType with its own table*.
So the two share ~200 fields by duplication in the DocType JSON, and `POS Invoice Item` mirrors
`Sales Invoice Item`. Any field added to one must be added to the other by hand.

---

## 2. `POS Invoice.on_submit` — what it does and does not do

`accounts/doctype/pos_invoice/pos_invoice.py:243`:

```python
def on_submit(self):
    if not self.is_return and self.loyalty_program:
        LoyaltyService(self).make_loyalty_point_entry()
    elif self.is_return and self.return_against and self.loyalty_program:
        against = frappe.get_doc("POS Invoice", self.return_against)
        LoyaltyService(against).delete_loyalty_point_entry()
        LoyaltyService(against).make_loyalty_point_entry()
    if self.redeem_loyalty_points and self.loyalty_points:
        LoyaltyService(self).apply_loyalty_points()
    self.check_phone_payments()
    self.set_status(update=True)
    self.make_bundle_for_sales_purchase_return()
    for table_name in ["items", "packed_items"]:
        self.make_bundle_using_old_serial_batch_fields(table_name)
        self.submit_serial_batch_bundle(table_name)
    if self.coupon_code:
        update_coupon_code_count(self.coupon_code, "used")
    self.clear_unallocated_mode_of_payments()
    if self.is_return and self.invoice_type_in_pos == "Sales Invoice":
        self.create_and_add_consolidated_sales_invoice()
```

**No `make_gl_entries`. No `update_stock_ledger`.** A submitted POS Invoice is, from the
ledger's point of view, invisible. Consequences:

- **Revenue is unrecognised until consolidation.** Between the sale and the closing entry
  (potentially a full shift, or longer if the merge job fails), the P&L understates revenue and
  the balance sheet understates cash.
- **Inventory is not decremented.** `Bin.actual_qty` is unchanged. Stock valuation, reorder
  levels, and availability across other channels are all stale.
- **Serial/Batch Bundles *are* submitted** (`submit_serial_batch_bundle`, `:368`). So serial
  numbers are consumed while the stock ledger says the goods are still on hand. Two subsystems
  disagree by design.
- **Loyalty points are posted immediately** — a real ledger (`Loyalty Point Entry`) written
  before the revenue that earned them.
- On return, the code **deletes and re-creates** the original invoice's loyalty entries
  (`delete_loyalty_point_entry()` then `make_loyalty_point_entry()`, `:247`–`:250`). Destructive
  recompute of a ledger.
- `clear_unallocated_mode_of_payments` (`:308`) issues a raw
  `DELETE FROM tabSales Invoice Payment WHERE parent = ? AND amount = 0` — deleting child rows of
  a *submitted* document (`:311`–`:312`).

`before_submit` is only `set_outstanding_amount()` (`:240`, `:584`).

---

## 3. Stock availability: a live query masquerading as a reservation

Because there is no stock ledger entry, ERPNext must invent an availability calculation.

`validate_stock_availablility` (`accounts/doctype/pos_invoice/pos_invoice.py:396`) — note the
misspelling, which is in the source:

```python
if self.is_return: return
if self.docstatus.is_draft() and not frappe.db.get_value("POS Profile", self.pos_profile,
                                                          "validate_stock_on_save"):
    return
for d in self.get("items"):
    if not d.serial_and_batch_bundle:
        if get_active_product_bundle(d.item_code):
            availability, is_stock_item, is_negative_stock_allowed = \
                get_product_bundle_stock_availability(d.item_code, d.warehouse, d.stock_qty)
        else:
            availability, is_stock_item, is_negative_stock_allowed = \
                get_stock_availability(d.item_code, d.warehouse)
        if is_negative_stock_allowed: continue
        ...
        if is_stock_item and flt(availability) <= 0:            throw("no stock")
        elif is_stock_item and flt(availability) < flt(d.stock_qty): throw("insufficient")
```

`get_stock_availability` (`:911`) = `get_bin_qty(...) - get_pos_reserved_qty(...)`.

`get_pos_reserved_qty` (`:971`) sums over **both** `POS Invoice Item` and `Packed Item`
(`:986`–`:988`), via `get_pos_reserved_qty_from_table` (`:991`):

```sql
SELECT SUM(p_item.<stock_qty|qty>)
FROM `tabPOS Invoice` p_inv, `tab<child_table>` p_item
WHERE p_inv.name = p_item.parent
  AND IFNULL(p_inv.consolidated_invoice, '') = ''
  AND p_item.docstatus = 1
  AND p_item.item_code = ? AND p_item.warehouse = ?
```

Note:

- The column differs by table: `qty` for `Packed Item`, `stock_qty` for `POS Invoice Item`
  (`:1009`). `Packed Item.qty` is **already in stock UOM** so this happens to work, but it is
  a naming coincidence, not a checked invariant.
- The filter is `IFNULL(consolidated_invoice,'') = ''` — reserved means "submitted and not yet
  merged". Once merged, the real stock ledger takes over. The handover is by *absence of a
  string*.
- Items **with** a `serial_and_batch_bundle` skip the availability check entirely
  (`:405`, `if not d.serial_and_batch_bundle`). Serialised items are unvalidated here.

**This is a read-then-write with no lock.** Two tills selling the last unit both compute
`availability = 1`, both pass, both submit. The oversell is discovered at consolidation, when
the merged Sales Invoice's stock ledger entry drives `Bin.actual_qty` negative — and if
`allow_negative_stock` is off, **the merge job fails**, leaving the whole session unconsolidated.
The failure surfaces hours later, in a background job, to nobody.

`get_product_bundle_stock_availability` (`:928`) and `get_bundle_availability` (`:948`) extend
the same pattern to bundles, returning a *list* of per-component shortfalls, which the caller
then formats into HTML inside the validation (`:422`–`:445`) — business logic emitting markup.

---

## 4. Consolidation: `POS Invoice Merge Log`

### 4.1 Grouping

`get_all_unconsolidated_invoices` (`accounts/doctype/pos_invoice_merge_log/pos_invoice_merge_log.py:435`),
`get_invoice_customer_map` (`:457`), and
`split_invoices_by_accounting_dimension` (`:471`) group unconsolidated invoices by customer and
then by dimension combination. `split_invoices` (`:519`) further splits so that
**returns are separated from sales** and each merge log stays under a size limit.
`distinguish_return_pos_invoices` (`:188`) separates them again inside processing.

`create_merge_logs` (`:574`) with inner `merge_and_close` (`:575`) and
`cancel_merge_logs` (`:619`) with `merge_cancel_and_close` (`:620`) run the work,
`enqueue_job` (`:654`) queues it, `check_scheduler_status` (`:679`) refuses to proceed if the
scheduler is disabled, `get_error_message` (`:684`) formats failures.

### 4.2 The merge itself

`merge_pos_invoice_into` (`:207`) is the interesting function. Per source POS Invoice:

**Header:** `map_doc(doc, invoice, table_map={"doctype": invoice.doctype})` (`:221`), then
**`invoice.posting_date = getdate(doc.posting_date)`** (`:224`–`:226`) — so the consolidated
invoice's posting date is that of the **last** source invoice in iteration order. Sales from
different dates in one merge log all post on one date.

**Items** (`:232`–`:249`):

```python
item.rate            = item.net_rate
item.amount          = item.net_amount
item.base_amount     = item.base_net_amount
item.price_list_rate = 0
si_item = map_child_doc(item, invoice, {"doctype": "Sales Invoice Item"})
si_item.pos_invoice      = doc.name
si_item.pos_invoice_item = item.name
```

The discount is **baked into the rate** and `price_list_rate` is **zeroed**. The consolidated
invoice therefore loses all discount information: you cannot report on discounts given at POS
from the Sales Invoice. `net_rate` is a *post-tax-exclusion* figure (doc 05), so the
consolidated invoice's `rate` is not the till's displayed price either.

**Taxes** (`:250`–`:268`):

```python
for t in taxes:
    if t.account_head == tax.account_head and t.cost_center == tax.cost_center:
        t.tax_amount      += flt(tax.tax_amount_after_discount_amount)
        t.base_tax_amount += flt(tax.base_tax_amount_after_discount_amount)
        found = True
if not found:
    tax.charge_type = "Actual"; tax.row_id = None
    tax.included_in_print_rate = 0
    tax.tax_amount = tax.tax_amount_after_discount_amount
    tax.dont_recompute_tax = 1
```

Every tax row becomes `charge_type = "Actual"` with `dont_recompute_tax = 1` and
`row_id = None`. The tax *computation* — rate, base, cascading (doc 05) — is discarded and
replaced by a frozen amount. The consolidated invoice cannot be recalculated; taxes on it are
opaque numbers. `included_in_print_rate = 0` means the inclusive/exclusive distinction is lost.

The dedup key is `(account_head, cost_center)` only — two tax rows with the same account and
cost centre but *different rates* (e.g. 5 % and 12 % VAT posting to one account) merge into one
row, permanently destroying the rate breakdown. `item_wise_tax_details` is remapped via
`old_new_item_map` / `old_new_tax_map` (`:285`–`:290`) to partially compensate.

**Payments** (`:271`–`:278`): deduped by `(account, mode_of_payment)`, amounts summed. Individual
payment identity is lost — you cannot trace a specific card settlement to a specific receipt
from the consolidated invoice.

**Rounding** (`:280`–`:283`): `rounding_adjustment`, `rounded_total`, `base_*` are **summed
across invoices**. So the consolidated invoice's `rounded_total` is the sum of individually
rounded totals, which is not the rounding of the sum. The `grand_total` is recomputed from
items+taxes, so `rounded_total - grand_total` is an arbitrary residue that must be absorbed as
`rounding_adjustment`. For 200 receipts at ±0.005 each, that residue can be a euro or more,
posted to the round-off account with no explanation.

### 4.3 Merge lifecycle

- `validate_pos_invoice_status` (`:78`) refuses invoices already consolidated or cancelled.
- `validate_duplicate_pos_invoices` (`:51`), `validate_customer` (`:66`).
- `on_submit` (`:116`) → `process_merging_into_sales_invoice` (`:143`) and/or
  `process_merging_into_credit_notes` (`:162`); `get_new_sales_invoice` (`:361`);
  `update_pos_invoices` (`:370`) writes `consolidated_invoice` back onto each source.
- `serial_and_batch_bundle_reference_for_pos_invoice` (`:383`),
  `delink_serial_and_batch_bundle` (`:389`), `get_serial_and_batch_bundles` (`:403`) move
  bundle ownership from the POS Invoice to the Sales Invoice.
- `on_cancel` (`:135`) → `cancel_linked_invoices` (`:421`).
- `unconsolidate_pos_invoices` (`:507`) reverses the whole thing.

### 4.4 The cancellation lock

`POSInvoice.before_cancel` (`accounts/doctype/pos_invoice/pos_invoice.py:269`):

```python
if self.consolidated_invoice and docstatus(Sales Invoice, self.consolidated_invoice) == 1:
    pos_closing_entry = frappe.get_all("POS Invoice Reference",
        filters={"pos_invoice": self.name}, pluck="parent", limit=1)
    frappe.throw("You need to cancel POS Closing Entry {0} ...")
```

So voiding one €4 receipt requires cancelling the **entire shift's closing entry**, which
cancels the consolidated Sales Invoice, which reverses the GL and stock for every sale in that
shift, then re-consolidating. In a retail chain this is operationally unusable, so in practice
POS voids are handled as returns — which is fine, but the schema does not make that the
supported path; it makes it the only *survivable* path.

Also `on_cancel` (`:288`) sets `self.ignore_linked_doctypes = ["Payment Ledger Entry", "Serial
and Batch Bundle"]` (`:289`) — explicitly disabling the back-link check
(doc 09 §1.4) for two ledgers, and then `db_set("status", "Cancelled")` (`:300`).

---

## 5. Session control: Opening and Closing Entry

**`POS Opening Entry`** (`accounts/doctype/pos_opening_entry/pos_opening_entry.py:12`, a
`StatusUpdater` subclass):
`validate_pos_profile_and_cashier` (`:45`), `check_open_pos_exists` (`:64`),
`check_user_already_assigned` (`:73`), `validate_payment_method_account` (`:80`),
`check_poe_is_cancellable` (`:113`).

`check_open_pos_exists` prevents two open sessions for the same profile+user — by **querying for
existing open entries**, again unlocked. Two simultaneous logins can both pass.

**`POS Closing Entry`** (`accounts/doctype/pos_closing_entry/pos_closing_entry.py:21`):
`validate_pos_opening_entry` (`:77`), `validate_invoice_mode` (`:81`),
`validate_duplicate_pos_invoices` (`:93`), `validate_pos_invoices` (`:108`),
`validate_duplicate_sales_invoices` (`:146`), `validate_sales_invoices` (`:161`),
`on_submit` (`:211`), `retry` (`:231`), `update_opening_entry` (`:234`),
`update_sales_invoices_closing_entry` (`:240`), `check_pce_is_cancellable` (`:246`).
Helpers: `get_invoices` (`:264`), `get_payments` (`:283`), `get_taxes` (`:317`),
`make_closing_entry_from_opening` (`:341`), `build_invoice_query` (`:407`).

The **existence of `retry` (`:231`)** is the tell: consolidation is a background job that
routinely fails, and the recovery is a manual button. There is no idempotency key; the retry
re-derives the invoice set from `build_invoice_query` and hopes.

Two parallel validation paths (`validate_pos_invoices` vs `validate_sales_invoices`,
`validate_duplicate_pos_invoices` vs `validate_duplicate_sales_invoices`) exist because
`POS Settings.invoice_type` (read in `validate_is_pos_using_sales_invoice`,
`accounts/doctype/pos_invoice/pos_invoice.py:469`) can make POS write **`Sales Invoice`
directly**, skipping the whole POS Invoice/merge machinery. So there are two entirely different
retail data paths in one codebase, with duplicated validation. Reports must handle both.

Cash reconciliation: `POS Closing Entry Detail` holds `opening_amount`, `expected_amount`,
`closing_amount`, `difference` per mode of payment. The difference is **recorded but not
posted** — there is no automatic GL entry for a till discrepancy. Cash-over/short must be
journalised manually.

---

## 6. `POS Profile` configuration

`accounts/doctype/pos_profile/pos_profile.py:16`. Validations:
`validate_accounting_dimensions` (`:86`), `validate_disabled` (`:104`),
`validate_default_profile` (`:119`), `validate_all_link_fields` (`:152`),
`validate_duplicate_groups` (`:166`), `validate_payment_methods` (`:181`),
`set_defaults` (`:216`). Item-group scoping via `get_item_groups` (`:235`),
`get_permitted_nodes` (`:260`), `get_child_nodes` (`:276`).

`validate_default_profile` (`:119`) enforces "one default per company+user" by scanning. Same
unlocked-uniqueness pattern.

`item_query` (`accounts/doctype/pos_invoice/pos_invoice.py:1084`) and
`get_item_group` (`:1106`) implement the POS item search, filtered by the profile's item groups.
`add_return_modes` (`:1064`) injects return-capable payment modes.

---

## 7. Our design

### 7.1 POS sales are ordinary sales

**There is no separate POS document type.** A till sale is a `sales_invoice` with
`channel = 'pos'`, `terminal_id`, and `pos_session_id`. It posts GL and stock at submit, like
everything else. Reasons this is now feasible where it was not for ERPNext:

- Our `outstanding` is a view (D9), so there is no `outstanding_amount` counter to contend on.
- Our stock decrement is an append-only `stock_move` insert (D6) with valuation in a separate
  projection, so a till sale is a single INSERT plus a deferred availability check — not a
  read-modify-write of `Bin`.
- Fulfilment is `doc_link` inserts (D7), not counter updates.

So the throughput objection that motivated deferred posting largely evaporates.

### 7.2 Session model

```sql
CREATE TABLE pos_session (
    id                uuid PRIMARY KEY,
    company_id        uuid NOT NULL REFERENCES company(id),
    terminal_id       uuid NOT NULL REFERENCES pos_terminal(id),
    cashier_user_id   uuid NOT NULL REFERENCES app_user(id),
    opened_at         timestamptz NOT NULL,
    closed_at         timestamptz,
    state             pos_session_state NOT NULL,   -- 'open','counting','closed','reconciled'
    CONSTRAINT pos_session_closed CHECK ((closed_at IS NULL) = (state = 'open'))
);
-- one open session per terminal, enforced by the DATABASE, not by a scan
CREATE UNIQUE INDEX pos_session_one_open ON pos_session (terminal_id) WHERE state <> 'closed';

CREATE TABLE pos_session_float (
    session_id        uuid NOT NULL REFERENCES pos_session(id) ON DELETE CASCADE,
    payment_method_id uuid NOT NULL REFERENCES payment_method(id),
    opening_amount    numeric(19,4) NOT NULL DEFAULT 0,
    counted_amount    numeric(19,4),
    PRIMARY KEY (session_id, payment_method_id)
);
```

`expected_amount` is a **view** over the session's postings, not a stored column, so it cannot
drift from the invoices. `difference = counted - expected` is computed, and closing the session
**posts the difference to a cash-over/short account automatically** as part of the same
transaction that sets `state = 'reconciled'` — with `pos_session_id` on the voucher for
traceability. ERPNext records the difference and posts nothing (§5).

### 7.3 Availability without overselling

Two mechanisms, both database-enforced:

1. **Optional reservation.** A till may insert a `stock_reservation` row (doc 16) with a short
   TTL. `EXCLUDE`/trigger checks make the sum of reservations plus on-hand consistent.
2. **Negative-stock policy at the constraint level.** `stock_valuation_state.qty_after` is
   maintained by a trigger that holds the row lock for `(item_id, warehouse_id)`; if the policy
   forbids negative stock, the trigger raises **at insert time**, in the transaction, at the
   till — not hours later in a merge job (§3).

The point-of-sale gets a synchronous, correct answer. Overselling is impossible rather than
detected late.

### 7.4 Nothing is destroyed at consolidation

There is no consolidation. But retail *does* need summarised journals for high volume, so we
provide **optional GL summarisation** as a separate, additive concern:

```sql
CREATE TABLE gl_summary_batch (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL,
    session_id    uuid REFERENCES pos_session(id),
    posting_date  date NOT NULL,
    summary_voucher_id uuid NOT NULL REFERENCES voucher(id),
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE gl_summary_member (
    batch_id      uuid NOT NULL REFERENCES gl_summary_batch(id) ON DELETE CASCADE,
    voucher_id    uuid NOT NULL REFERENCES voucher(id),
    PRIMARY KEY (batch_id, voucher_id)
);
```

The individual invoices keep their own detail *and* their own GL entries; the summary is a
reporting aggregate with explicit membership, not a replacement that discards
`price_list_rate`, tax rates, payment identity, and posting dates (§4.2). Voiding one receipt
touches one receipt (§4.4).

### 7.5 Point fixes carried into our model

| ERPNext behaviour | Our rule |
|---|---|
| POS Invoice posts no GL/stock (§2) | every posted document posts to every applicable ledger, in one transaction |
| Serial/Batch bundle submitted without stock move (§2) | serial/batch consumption is *part of* the `stock_move` row set; no separate submit |
| Loyalty entries deleted and recreated on return (§2) | `loyalty_entry` is append-only; a return inserts a negating row |
| `DELETE FROM Sales Invoice Payment WHERE amount = 0` on a submitted doc (§2) | zero-amount payment lines rejected by a `CHECK (amount <> 0)` at insert |
| Availability = `Bin.actual_qty - Σ open POS lines`, unlocked (§3) | trigger-enforced `qty_after` with row lock, plus optional reservations |
| Serialised items skip the availability check (§3) | serial availability is a `UNIQUE` on `(serial_no, status='in_stock')`; double-sale is impossible |
| Consolidated invoice zeroes `price_list_rate`, bakes discounts (§4.2) | no rewriting; discounts remain first-class columns |
| Tax rows collapsed to `charge_type='Actual'`, deduped by `(account, cost_center)` (§4.2) | tax lines keep `rate`, `basis`, `inclusive` flag; summaries reference them, never replace them |
| `rounded_total` summed across invoices (§4.2) | rounding is per document; a summary voucher carries the exact sum of the underlying GL, so no residue exists |
| Posting date = last source invoice's date (§4.2) | each invoice keeps its own date; summaries are per date |
| Voiding one receipt requires cancelling the shift (§4.4) | reverse one voucher (D5) |
| `ignore_linked_doctypes` disabling back-link checks (§4.4) | FKs with `RESTRICT`; no bypass flag exists |
| One open session enforced by scan (§5) | partial `UNIQUE INDEX` (§7.2) |
| Consolidation `retry` button (§5) | nothing to retry; posting is synchronous |
| Two retail paths (`POS Settings.invoice_type`) (§5) | one path |
| Till difference recorded but not posted (§5) | posted automatically at session close (§7.2) |
| `POS Invoice`/`POS Invoice Item` duplicating `Sales Invoice`/`Item` (§1) | one table, `channel` column |

---

## 8. Offline operation

ERPNext's POS has an offline mode in the client, but the *server* model gives it no help: a
POS Invoice created offline must be inserted with a server-generated `name` from a naming series
(a global counter, doc 09 §6), so offline receipt numbers collide.

Our model: the till generates the `uuid` PK client-side, and `doc_no` is assigned from a
**per-terminal** numbering series (`numbering_series.scope = 'terminal'`), so offline receipts
have globally unique ids and locally unique, gapless numbers. Sync is an idempotent upsert on
the client-generated `uuid` — replaying a batch is safe. That property is unavailable to any
design with server-assigned string PKs.

---

Cross-references: doc 02 (stock ledger), doc 04 (AR), doc 05 (taxes/totals — the computation
that consolidation discards), doc 09 (lifecycle), doc 16 (reservation),
`docs/design/FINAL-SCHEMA.md`.
