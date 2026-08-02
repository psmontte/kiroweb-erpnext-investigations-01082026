# 30 — Upstream Trade Documents and Parties

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`.

S01 and S03 walked order-to-cash and procure-to-pay from the **order** onwards. This document covers
what happens *before* an order exists — the pre-commitment documents — plus the party and terms
masters they depend on.

```
selling     Opportunity ─▶ Quotation ─▶ Sales Order ─▶ (S01)
                              └─▶ Proforma Invoice (v17, from a submitted SO)
buying      Material Request ─▶ Request for Quotation ─▶ Supplier Quotation ─▶ Purchase Order ─▶ (S03)
both        Blanket Order ─▶ Sales Order / Purchase Order
special     drop-ship: Sales Order ─▶ Purchase Order ─▶ (no delivery document at all)
```

The defining property of this layer is that **nothing here posts to a ledger**. Every document is an
intention, and every quantity is a counter maintained by application code. That makes it the part of
the system where the "derived state is stored, not computed" problem (doc 10) is at its worst, and
where the most surprising side effects live: submitting a Request for Quotation **creates user
accounts**, saving a Supplier **grants roles**, and saving Selling Settings **rewrites DocType field
metadata**.

Closes the `docs/COVERAGE.md` gaps for `Quotation`, `Proforma Invoice`, `Request for Quotation`,
`Supplier Quotation`, `Blanket Order`, `Supplier`, `Payment Term`, `Payment Terms Template`,
`Mode of Payment`, `Party Link`, `Selling Settings`, and `Buying Settings`, and deepens
`Material Request`.

---

## 1. `Quotation`

`Quotation(SellingController)` (`selling/doctype/quotation/quotation.py:20`).

### 1.1 It can be addressed to four different things

`quotation_to` is a `Link` to **DocType** and `party_name` a `DynamicLink`, so a quotation may target a
`Customer`, `Lead`, `Prospect` or `CRM Deal`. `set_customer_name` (`:238`) is a four-branch chain:

```python
if   quotation_to == "Customer": customer_name = Customer.customer_name
elif quotation_to == "Lead":     customer_name = Lead.company_name or Lead.lead_name
elif quotation_to == "Prospect": customer_name = self.party_name          # the primary key
elif quotation_to == "CRM Deal": customer_name = CRM Deal.organization
```

For `Prospect` the displayed name is the **primary key itself**, which only reads correctly because
Prospect is named by its title. This is the doc 09 §3 problem — a `varchar(140)` PK doubling as a
human label — surfacing in the sales pipeline.

> **Ours** One `party` table with a `party_role` set (doc 30 §9.2), so a quotation always points at a
> `party_id` regardless of how far through the pipeline that party is. `customer_name` is not copied;
> it is a join. The pipeline stage is an attribute of the party, not a different table.

### 1.2 Alternative items are grouped by **row adjacency**

A quotation can offer alternatives: several item rows, one flagged `is_alternative`, from which the
customer picks. The grouping is not stored:

```python
def get_rows_with_alternatives(self):                       # :342
    for idx, row in enumerate(self.get("items")):
        if row.is_alternative:            continue
        if idx == (table_length - 1):     break
        if self.get("items")[idx + 1].is_alternative:
            rows_with_alternatives.append(row.name)
```

⚠️ A row "has alternatives" **iff the row immediately after it in `idx` order is flagged
`is_alternative`**. There is no group key, no parent-row reference — the relationship exists only in
the child table's ordering. Re-sorting the grid silently re-associates alternatives with a different
item, and a set is only recognised if its members are physically contiguous.

`set_has_alternative_item` (`:167`) writes the derived `has_alternative_item` flag at
`before_submit` (`:160`), so the adjacency is frozen at submit time into a boolean — but the boolean
does not record *which* rows were the alternatives.

`get_valid_items` (`:206`) then filters, when computing ordered status, to alternatives that were
actually ordered:

```python
def is_in_sales_order(row):
    return bool(frappe.db.exists("Sales Order Item",
        {"quotation_item": row.name, "item_code": row.item_code, "docstatus": 1}))
```

— one query **per row**, inside a filter, inside a status computation that runs on every save.

> **Ours** `quote_option_group_id uuid` on the line, with `UNIQUE (document_id,
> quote_option_group_id, is_selected) WHERE is_selected` so exactly one option per group can be
> selected. The relationship is data, order is irrelevant, and "which alternative was chosen" is a
> stored fact rather than an existence probe against downstream documents.

### 1.3 Zero-quantity lines are legal, by setting

```python
def before_validate(self):                                   # :139
    self.set_has_unit_price_items()
    self.flags.allow_zero_qty = self.has_unit_price_items

def set_has_unit_price_items(self):                          # :177
    if not frappe.get_single_value("Selling Settings", "allow_zero_qty_in_quotation"):
        return
    self.has_unit_price_items = any(not row.qty for row in self.get("items") if (row.item_code and not row.qty))
```

A "unit price quotation" quotes rates without committing to quantities. The same pattern appears on
`Sales Order`, `Request for Quotation` (`buying/doctype/request_for_quotation/request_for_quotation.py:86`)
and `Supplier Quotation` (`buying/doctype/supplier_quotation/supplier_quotation.py:139`), each behind
its own `Buying Settings` / `Selling Settings` checkbox — four flags for one concept.

> **Ours** `line_kind enum('quantified','unit_price_only','free','service')` on the line. A rate-only
> line is a *kind of line*, not a global permission to leave a mandatory field empty, so `qty
> numeric(21,9) NOT NULL` survives and `CHECK (line_kind <> 'quantified' OR qty > 0)` expresses the
> rule locally.

### 1.4 Status is partly a cron job

`get_ordered_status` (`:188`) derives `Open` / `Partially Ordered` / `Ordered` by comparing each row's
`stock_qty` against the summed ordered quantity. Separately, a scheduled function bulk-expires:

```python
def set_expired_status():          # selling/doctype/quotation/quotation.py:376
    UPDATE tabQuotation SET status = 'Expired'
     WHERE docstatus = 1 AND status NOT IN ('Expired','Lost')
       AND valid_till < nowdate()
       AND NOT EXISTS (submitted Sales Order Item with prevdoc_docname = quotation.name)
```

Two observations. The `EXISTS` correctly protects quotations that produced an order — but it counts
*any* submitted `Sales Order Item`, so a quotation whose only order was later **cancelled** becomes
`Expired` on the next scheduler tick even if it was `Ordered`. And the transition has no audit trail:
`status` is overwritten by a bulk `UPDATE` with no `Version` row (doc 20 §5 — `db_set` and bulk
updates are invisible to the audit trail).

`declare_enquiry_lost` (`:267`) is the opposite transition and is stranger:

```python
self.db_set("status", "Lost")
if detailed_reason: self.db_set("order_lost_reason", detailed_reason)
for reason in lost_reasons_list: ... self.append("lost_reasons", reason)
for competitor in competitors:   self.append("competitors", competitor)
self.update_opportunity("Lost"); self.update_lead(); self.save()
```

`db_set` writes for the scalars, `append` + `save()` for the child tables — on a **submitted**
document. It works only because those fields are `allow_on_submit`, and it means the same logical
transition is half-recorded in the audit trail (the `save()` part) and half-invisible (the `db_set`
part). `on_cancel` (`:308`) then *empties* `lost_reasons`, destroying the reason the deal was lost.

> **Ours** `document_state` transitions are rows in `document_state_event` (doc 06 §8): one row per
> transition with `from_state`, `to_state`, `actor`, `reason_code_id`, `occurred_at`. Expiry is a
> **view** (`valid_to < current_date AND NOT EXISTS (…)`) — a document does not need to be rewritten
> nightly to become expired, and "expired" cannot fight with "ordered" because it is derived from the
> same facts. Lost reasons are `document_reason` rows that survive cancellation, because *why* a deal
> was lost is the most valuable field on the record.

---

## 2. `Proforma Invoice`

New in v17 (`selling/doctype/proforma_invoice/proforma_invoice.py:12`, 2026 copyright). Gated by
`Selling Settings.enable_proforma_invoice` (`validate_feature_enabled`, `:233`), `in_create`, so the
only creation path is `make_proforma_invoice` (`:137`).

It is a document issued against a **submitted Sales Order** so a customer can pay before invoicing.
Its design is unusual in a way worth studying, because it is the newest code in the trade layer.

### 2.1 The totals are a side effect of rendering a PDF

```python
def on_submit(self) -> None:                                 # :51
    self.generate_and_attach_pdf()

def generate_and_attach_pdf(self) -> None:                   # :60
    if self.proforma_pdf: return
    printed = self.render_pdf()
    file = save_file(...); self.db_set("proforma_pdf", file.file_url)

def render_pdf(self) -> dict:                                # :67
    sales_order = frappe.get_doc("Sales Order", self.sales_order)
    lines = {item.so_detail: item for item in self.items}
    sales_order.items = [item for item in sales_order.items if item.name in lines]
    for item in sales_order.items:
        item.qty = lines[item.name].qty
        item.rate = lines[item.name].rate
        item.discount_amount = 0
        item.discount_percentage = 0
    sales_order.run_method("calculate_taxes_and_totals")
    ...
    self.db_set("grand_total", sales_order.grand_total)
    return frappe.attach_print("Sales Order", sales_order.name, doc=sales_order, ...)
```

The proforma has **no taxes and no totals of its own**. It builds a throwaway, mutated in-memory copy
of the Sales Order, zeroes the discounts, recomputes, and reads the answer back out. The docstring is
candid about this and explains why (reuse the tax engine and the print format).

Three consequences:

1. ⚠️ **`grand_total` is written from inside a PDF renderer.** If `proforma_pdf` is already set,
   `generate_and_attach_pdf` returns early and `grand_total` is never recomputed — so the stored
   total can be from a different render than the attached document.
2. The proforma is **not self-contained**: it has no `taxes` table, so the tax breakdown exists only
   inside the PDF bytes. Reprinting after the Sales Order's taxes change produces a different
   document under the same number.
3. Because the copy is never saved, the qty/rate substitution is invisible — but `sales_order.items`
   is *reassigned* on a live document object, and `proforma_no` / `proforma_date` / `hide_item_qty`
   are set on it. Any code that later reads that object in the same request sees a mutated Sales
   Order.

### 2.2 Nothing limits how much can be proformaed

`get_proformed_totals` (`:119`) sums issued proforma qty and amount per `Sales Order Item`, and
`get_sales_order_items` (`:99`) returns those totals to the dialog as `proformed_qty` /
`proformed_amount`. But `make_proforma_invoice` (`:137`) never consults them:

```python
if sales_order_doc.docstatus != 1:
    frappe.throw(_("A Proforma Invoice can only be created against a submitted Sales Order."))
for row in selected:
    so_item = so_items.get(row.get("so_detail"))
    line = _proforma_line(so_item, based_on, row)      # :186
```

⚠️ The over-issue check is **presentational only**. A 100-unit order can carry ten 100-unit proformas.
For a document a customer pays against, that is a duplicate-payment invitation.

`_proforma_line` (`:186`) also derives a rate by division on the `Amount` basis:

```python
if based_on == "Amount":
    qty = flt(row.get("qty")); amount = flt(row.get("amount"))
    if amount <= 0 or qty <= 0: return None
    rate = amount / qty
```

`rate` is stored unrounded, and `render_pdf` then recomputes `amount = qty × rate` through the tax
engine at field precision. The docstring claims the recomputed amount "matches whichever basis the
proforma was created on"; it matches only up to rounding, which is exactly the invariant doc 05 §5.3
shows ERPNext cannot hold elsewhere either.

### 2.3 Send history is a single overwritten field

`send_proforma_email` (`:213`) does `proforma.db_set("sent_on", now())` and
`db_set("emailed_to", recipients)`. Sending to a second recipient list overwrites the first, so "who
was this sent to, when" retains only the last answer.

> **Ours** `proforma` is a first-class document with its own `document_line` and `tax_line` rows
> produced by the same determination function as everything else (doc 28 §7.1) — no borrowed
> totals, no PDF-as-source-of-truth. Cumulative issue is constrained:
> `CHECK` via trigger that `Σ proforma_line.qty ≤ order_line.qty × (1 + over_proforma_allowance)`,
> the same shape as the fulfilment caps in doc 10 §6. `rate` is `numeric(21,9)` and the amount basis
> stores **`amount` as given** with `rate` as a generated column, so the user's number is the stored
> number. Every send is an insert into `document_dispatch (document_id, channel, recipients,
> sent_at, sent_by, artifact_id)` — an append-only log, with the rendered PDF kept as an immutable
> artifact so a reprint is a retrieval, not a re-render.

---

## 3. `Request for Quotation` — a document that provisions identities

`RequestforQuotation(BuyingController)`
(`buying/doctype/request_for_quotation/request_for_quotation.py:22`). It holds a `suppliers` child
table and an `items` child table, and its purpose is to email suppliers and collect quotes through a
portal.

### 3.1 Submitting it creates `User` records and mutates the `Supplier` master

```python
def on_submit(self):                                         # :157
    self.db_set("status", "Submitted")
    for supplier in self.suppliers:
        supplier.email_sent = 0
        supplier.quote_status = "Pending"
    self.send_to_supplier()

def send_to_supplier(self):                                  # :188
    for rfq_supplier in self.suppliers:
        if rfq_supplier.email_id is not None and rfq_supplier.send_email:
            update_password_link, contact = self.update_supplier_contact(rfq_supplier, self.get_link())
            self.update_supplier_part_no(rfq_supplier.supplier)
            self.supplier_rfq_mail(rfq_supplier, update_password_link, self.get_link())
            rfq_supplier.email_sent = 1
            if not rfq_supplier.contact: rfq_supplier.contact = contact
            rfq_supplier.save()
```

`update_supplier_contact` (`:221`) → `create_user` (`:274`):

```python
user = frappe.get_doc({"doctype": "User", "send_welcome_email": 0, "email": rfq_supplier.email_id,
                       "first_name": ..., "user_type": "Website User", "redirect_url": link})
user.save(ignore_permissions=True)
update_password_link = user._reset_password()
```

⚠️ **Submitting a purchasing document creates login accounts.** It also:

- creates a `Contact` if none exists (`link_supplier_contact`, `:234`) and saves it with
  `ignore_permissions=True`;
- calls the **private** `user._reset_password()` and embeds the resulting reset link in an outbound
  email;
- appends a `Portal User` row to the **`Supplier` master** and saves it with `ignore_validate`,
  `ignore_mandatory` **and** `ignore_permissions` all set (`update_user_in_supplier`, `:257`) — so a
  document submit rewrites a master while switching off that master's own validation;
- calls `rfq_supplier.save()` on an individual **child row** inside a loop.

And `get_link` (`:204`) throws if no `Portal Menu Item` route exists for the doctype — a purchasing
document cannot be submitted because a website setting is missing.

> **Ours** Identity provisioning is never a side effect of a business document. A supplier-portal
> invitation is an explicit `portal_invitation` row with its own state machine
> (`pending → accepted → revoked`), created by an operator action that requires an explicit
> permission, and the RFQ merely references it. Documents may **read** party contact data; they may
> not create users, reset credentials, or write to a party master with validation disabled. Sending
> is an append to `document_dispatch`, so `email_sent` is a view rather than a mutable child-row
> flag.

### 3.2 `quote_status` is stored **translated**, by three writers that disagree

Three code paths write `Request for Quotation Supplier.quote_status`:

| Writer | Value written |
|---|---|
| `RequestforQuotation.on_submit` (`:157`) | `"Pending"` — a plain literal |
| `RequestforQuotation.update_rfq_supplier_status` (`:384`) | `_("Received")` / `_("Pending")` — **translated** |
| `SupplierQuotation.update_rfq_supplier_status` (`buying/doctype/supplier_quotation/supplier_quotation.py:169`) | `_("Received")` / `_("Pending")` — **translated** |

⚠️ Storing `_( )` output in a database column means the value depends on the **saving user's
language**. On a German site the column holds `Erhalten`, and the untranslated `"Pending"` written at
submit never matches the translated `"Pending"` written later. Any filter, report or `Select` option
comparing against a literal is wrong for every non-English site. This is a schema-level defect
expressed as a translation call, and it is the clearest single argument in the codebase for
**codes-not-labels**.

Both `update_rfq_supplier_status` implementations are also **O(suppliers × items) queries** — one
`COUNT` per RFQ item per supplier — and the Supplier Quotation variant issues a
`frappe.db.set_value` **inside the inner item loop** (`:169`), writing the same row up to N times per
supplier.

> **Ours** `rfq_supplier.quote_state` is an enum of codes (`invited`, `pending`, `quoted`,
> `declined`), and the displayed label comes from the UI translation layer at render time. The state
> itself is a **view** over `supplier_quotation_line`: a supplier is `quoted` when every RFQ line has
> a submitted quote line. One definition, one query, no writers to disagree.

### 3.3 The supplier email is a server-side template with acknowledged injection

```python
message_template = self.mfs_html if self.use_html else self.message_for_supplier
# nosemgrep: frappe-semgrep-rules.rules.security.frappe-ssti
rendered_message = frappe.render_template(message_template, doc_args)
#   buying/doctype/request_for_quotation/request_for_quotation.py:298
```

A user-authored template (`Code`/`TextEditor` field, or copied from an `Email Template` by
`set_data_for_supplier`, `:97`) is rendered with the whole document as context, and the SSTI lint rule
is explicitly suppressed. `doc_args` includes the full `Contact` document. `before_print` (`:164`) is
also mutating: it sets `self.vendor` and rewrites every item's `supplier_part_no`
(`update_supplier_part_no`, `:214`) so the printed copy is supplier-specific — meaning the persisted
`vendor` field ends up holding whichever supplier was processed last.

> **Ours** Outbound documents render from a **typed template** with a declared variable set
> (`template_variable` rows), compiled and validated when the template is saved, with no access to
> arbitrary document attributes and no expression evaluation. Supplier-specific values (part numbers)
> are resolved per render into a projection, never written back onto the document.

---

## 4. `Supplier Quotation`

`SupplierQuotation(BuyingController)` (`buying/doctype/supplier_quotation/supplier_quotation.py:16`).

`validate_with_previous_doc` (`:150`) links back to `Material Request` and compares `company`, and
per row `item_code` and `uom` — the standard mechanism from doc 10 §3.

`on_submit` (`:128`) / `on_cancel` (`:132`) both `db_set("status", …)` and call
`update_rfq_supplier_status(1|0)` (§3.2).

Expiry is where sales and purchase diverge:

```python
def set_expired_status():                                    # :245
    frappe.db.set_value("Supplier Quotation",
        {"docstatus": 1, "status": ["not in", ["Cancelled", "Stopped"]], "valid_till": ["<", nowdate()]},
        "status", "Expired", update_modified=True)
```

⚠️ Unlike `Quotation.set_expired_status` (§1.4), there is **no check for downstream Purchase Orders**.
A supplier quotation that has been fully ordered against is still flipped to `Expired` once its
validity passes. `get_purchased_items` (`:257`) exists to compute exactly that ordered quantity and is
not used here.

Note also `frappe.db.set_value` with a **filters dict** performs a bulk update — convenient, and
invisible to the audit trail.

> **Ours** As in §1.4: validity is a `daterange` and "expired" is a view. `Σ` ordered is a view over
> `doc_link` (doc 10 §5). Neither needs a nightly writer, and the sales and purchase sides share one
> definition instead of two functions that disagree.

---

## 5. `Blanket Order`

`BlanketOrder` (`manufacturing/doctype/blanket_order/blanket_order.py:15`) is a standing agreement:
"up to N units between `from_date` and `to_date`". One table serves both directions via
`blanket_order_type` ∈ `Selling`/`Purchasing`, with both `customer` and `supplier` columns.

`validate` (`:43`) is thin: `validate_dates` (`:49`) checks `from_date <= to_date`,
`validate_duplicate_items` (`:90`) allows one row per `item_code`, `validate_item_qty` (`:121`)
rejects negative quantities, and `set_party_item_code` (`:53`) fills the party's own item reference.

⚠️ **There is no overlap detection.** Two blanket orders for the same customer and item with
overlapping date ranges are legal, and nothing decides which one an order should consume.

### 5.1 The allowance check mixes units

```python
def update_ordered_qty(self):                                # :97
    ... Sum(trans_item.stock_qty) ...                        # stock UOM
        .where((trans_item.blanket_order == self.name) & (trans.docstatus == 1)
               & (trans.status.notin(["Stopped", "Closed"])))
        .groupby(trans_item.item_code)
    for d in self.items:
        d.db_set("ordered_qty", item_ordered_qty.get(d.item_code, 0))

def validate_against_blanket_order(order_doc):               # :168
    for item in order_doc.get("items"):
        if item.against_blanket_order and item.blanket_order:
            order_data[item.blanket_order][item.item_code] += item.qty     # transaction UOM
    ...
    remaining_qty = item.qty - item.ordered_qty
    allowed_qty = remaining_qty + (remaining_qty * (allowance / 100))
    if item.qty and allowed_qty < item_data[item.item_code]:
        frappe.throw("Item {0} cannot be ordered more than {1} against Blanket Order {2}.")
```

⚠️ `ordered_qty` is accumulated from `stock_qty` (**stock UOM**) while the incoming order is summed
from `item.qty` (**transaction UOM**). For any order line using a non-stock UOM the two sides of the
inequality are in different units, so a blanket order priced per box and ordered per piece is
policed against a meaningless number. This is the same UOM-conflation class as doc 17 §2 and
`Bin.stock_uom`.

Three more properties of the same check:

- `if item.qty and …` — a blanket row with `qty = 0` means **unlimited**, silently.
- `item.ordered_qty` is read from the row as last written by `update_ordered_qty`, with no lock. Two
  concurrent orders both read the same remaining quantity and both pass — the lost-update shape from
  doc 12 §1.2 and S04 §4.
- The allowance comes from `Selling Settings.blanket_order_allowance` or
  `Buying Settings.blanket_order_allowance`, so the tolerance is global rather than per agreement.

### 5.2 `make_order` takes its target doctype from a request global

```python
@frappe.whitelist()
def make_order(source_name: str):                            # :128
    doctype = frappe.flags.args.doctype
```

⚠️ A whitelisted entry point whose **output type** comes from `frappe.flags.args` rather than a
declared parameter. `update_item` then forces `target.uom = item.get("stock_uom")`, discarding the
blanket order row's own UOM — which is how §5.1's unit mismatch gets created in the first place.

> **Ours** `agreement` + `agreement_line` with
> `EXCLUDE USING gist (company_id WITH =, party_id WITH =, item_id WITH =, daterange(valid_from,
> valid_to) WITH &&)` so overlapping agreements cannot exist and "which agreement applies" has one
> answer. `agreement_line.qty_agreed numeric(21,9) NOT NULL` is **always in stock UOM**, and
> consumption is a view over `doc_link`:
> `Σ order_line.qty_stock` — one unit, computed, never stored. The allowance is
> `over_commit_allowance` **on the agreement line**, and the cap is a deferred constraint evaluated
> under the order's row lock, so concurrency cannot over-commit. `qty_agreed = NULL` means unlimited,
> explicitly, rather than `0` meaning unlimited by accident.

---

## 6. `Material Request`, in depth

`MaterialRequest(BuyingController)` (`stock/doctype/material_request/material_request.py:88`). Doc 10
§2 cited it once for its `status_updater` configuration; this is the rest.

### 6.1 One status column, four state machines

`validate` (`:155`) permits ten statuses:

```
Draft, Submitted, Stopped, Cancelled, Pending, Partially Ordered, Ordered, Issued, Transferred, Received
```

but which of them are reachable depends on `material_request_type` (`Purchase`, `Material Issue`,
`Material Transfer`, `Manufacture`, `Customer Provided`). `Issued` only applies to Material Issue,
`Transferred` to Material Transfer, `Ordered` to Purchase and Manufacture. One column, four disjoint
vocabularies, validated as a flat list.

`status_can_change` (`:290`) is the only transition guard, and it covers **two** cases:

```python
if self.status == "Cancelled":  # cannot change at all
elif self.status == "Draft":    # can only go to "Pending"
```

Every other transition is unguarded — `Received` back to `Pending`, `Ordered` to `Issued`, anything.

`check_modified_date` (`:277`) hand-rolls optimistic concurrency by comparing `modified`, but only on
the `update_status` path (`:283`); the ordinary save path relies on Frappe's own check.

### 6.2 `ordered_qty` means four different things

```python
def get_mr_items_ordered_qty(self, mr_items):                # :325
    if self.material_request_type in ("Material Issue", "Material Transfer", "Customer Provided"):
        doctype = "Stock Entry Detail"; qty_field = transfer_qty
    elif self.material_request_type == "Manufacture":
        doctype = "Work Order";        qty_field = qty
    ...
def update_completed_qty(self, ...):                         # :352
    if self.material_request_type == "Purchase":
        return
```

So `Material Request Item.ordered_qty` is filled from `Stock Entry Detail.transfer_qty`, or from
`Work Order.qty`, or — for `Purchase` — not by this method at all, but by the generic
`StatusUpdater` path (`update_prevdoc_status`, called from `on_submit` `:265`) writing from
`Purchase Order Item`. **Two entirely different fulfilment mechanisms behind one column**, chosen by a
type field, which is exactly the fragmentation doc 10 §7 catalogues.

`update_completed_qty` also enforces the over-issue cap from `Stock Settings.mr_qty_allowance`, then
writes each row individually:

```python
frappe.db.set_value(d.doctype, d.name, "ordered_qty", d.ordered_qty)
```

— an `UPDATE` per row inside a loop, followed by `_update_percent_field` for `per_ordered`.

### 6.3 A validation that was switched off, and left in place

```python
validate_for_items(self)
self.set_title()
# self.validate_qty_against_so()
# NOTE: Since Item BOM and FG quantities are combined, using current data, it cannot be validated
# Though the creation of Material Request from a Production Plan can be rethought to fix this
```

⚠️ `validate_qty_against_so` (`:115`) — 40 lines that prevent requesting more material than the Sales
Order it references — is **commented out at the call site** (`:190`) with a note explaining that
Production Plan roll-ups made it unworkable. So a Material Request may exceed its Sales Order without
limit, and the check remains in the file as dead code.

This is worth recording precisely because the reason is honest: the data model conflates BOM
component quantities with finished-good quantities on the same rows, so the constraint could not be
expressed. A modelling defect disabled a business rule.

### 6.4 Two silent field rewrites

```python
if self.buying_price_list and not frappe.get_value("Price List", self.buying_price_list, "buying"):
    self.buying_price_list = None                             # :196
if not self.buying_price_list:
    buying_price_list = frappe.defaults.get_defaults().buying_price_list
    if frappe.has_permission("Price List", "read", buying_price_list):
        self.buying_price_list = buying_price_list             # :200
```

⚠️ A **permission check decides what gets stored**: two users saving the same document get different
`buying_price_list` values depending on their read access. Permission should filter what is *shown*,
never what is *written* — otherwise the record depends on who touched it last.

`validate_material_request_type` (`:255`) silently nulls `customer` unless the type is
`Customer Provided`, and `on_update` (`:203`) re-prices every line whenever `buying_price_list`
changes — through `update_item_rates` (`:206`), which is where doc 29 §2.4's inverted
`price_not_uom_dependent` lands.

> **Ours** `request_kind` is a typed column and each kind has its own **state set** in
> `document_state_transition` (doc 06 §8) — the transitions that exist for a transfer request are not
> even representable for a purchase request. Progress is one view over `doc_link` regardless of kind
> (doc 10 §5), in stock UOM, so there is no `ordered_qty` column to fill from four sources. The
> Sales-Order cap that had to be abandoned becomes expressible because component demand and
> finished-good demand are **different tables** (`demand_line` vs `production_demand`), so the
> constraint has a well-defined left-hand side. Defaults are resolved from configuration, never from
> the saving user's permissions.

---

## 7. Drop-ship: a delivery with no document

A `Sales Order` line marked `delivered_by_supplier` is fulfilled by the supplier shipping directly to
the customer. There is therefore **no Delivery Note and no stock movement** — and consequently no
document recording that the delivery happened.

`DropShipService` (`buying/doctype/purchase_order/services/drop_ship.py:11`) fills the gap with a
manual counter edit:

```python
def update_dropship_received_qty(self, data: list[dict]) -> None:      # :15
    for d in data:
        item = next((item for item in doc.items if item.name == d.get("name")), None)
        if not item.delivered_by_supplier: throw(...)
        if not item.has_permlevel_access_to("received_qty", permission_type="write"): throw(...)
        if d["qty_change"] < 0 and abs(d["qty_change"]) > item.received_qty: throw(...)
        if d["qty_change"] > 0 and item.received_qty + d["qty_change"] > item.qty: throw(...)
        qty_change = item.received_qty + d.get("qty_change")
        item.db_set("received_qty", qty_change, update_modified=True)
        doc.add_comment("Label", _("updated delivered quantity for item {0} to {1}") ...)
    doc.update_receiving_percentage(); doc.set_status(update=True)
    self.update_delivered_qty_in_sales_order()               # :74
```

Observations:

- ⚠️ **The only audit trail is a comment.** The delivery event — date, quantity, who reported it — is
  a free-text `Comment` row plus a mutated counter. There is no document to cancel, amend or report
  on, and `received_qty` on a submitted Purchase Order Item is edited in place.
- Access control is a **field-level permlevel** check (`has_permlevel_access_to`), which is doc 19
  §3's mechanism — application-level, bypassed by any direct write.
- `qty_change` is a delta applied as read-then-write with no lock; two users reporting deliveries
  concurrently lose one of the updates.
- `update_delivered_qty_in_sales_order` (`:74`) then reaches into each linked Sales Order and calls
  `update_delivery_status()`, `set_status(update=True)` and `notify_update()` — a purchasing action
  rewriting selling documents, which is the cross-document mutation pattern doc 10 §7 lists as the
  source of the fulfilment engine's concurrency bugs.
- `set_received_qty_to_zero_for_drop_ship_items` (`:87`) resets the counter, so the value is not
  derived from anything and can be zeroed independently of the Sales Order's delivered quantity.

Drop-ship also changes address validation: `party_validation.py:160` and `_is_drop_ship` (`:222`)
relax the dispatch/shipping address rules when any line is drop-shipped.

> **Ours** A drop-ship delivery is a **document**: `fulfilment_event` with
> `kind = 'supplier_direct'`, its own date, quantity, reporter, and optional supplier reference, and
> **no** stock movement rows (that is precisely what distinguishes it from a shipment). Progress on
> both the order and the purchase order is a view over `doc_link` reading those events, so one
> insert updates both sides with no cross-document writes, no counters, and a full history of
> corrections as compensating events (doc 11 §5). "Who told us this shipped, and when" is a column,
> not a comment.

---

## 8. Party masters

### 8.1 `Supplier`

`Supplier(TransactionBase)` (`buying/doctype/supplier/supplier.py:27`).

**Its primary key is a site-wide configuration choice.** `autoname` (`:106`):

```python
supp_master_name = frappe.defaults.get_global_default("supp_master_name")
if   supp_master_name == "Supplier Name":  self.name = self.supplier_name
elif supp_master_name == "Naming Series":  set_name_by_naming_series(self)
else:                                      set_name_from_naming_options(...)
```

and `after_rename` (`:217`) writes `supplier_name = newdn` when naming by name — so under one setting
the PK *is* the display name, and renaming a supplier rewrites the identifier that every historical
document references (Frappe cascades the rename; doc 09 §2 covers the cost). `Customer` has the
identical mechanism under `cust_master_name`.

**Saving it grants roles.** `validate` (`:139`) calls `add_role_for_user` (`:118`) →
`_add_supplier_role`:

```python
if "System Manager" not in frappe.get_roles():
    frappe.msgprint(_("Please add 'Supplier' role to user {0}."), alert=True); return
user_doc.add_roles("Supplier")
```

⚠️ A master's `validate` **grants a role to a `User`**, and whether it does so depends on the roles of
the person saving. The same save performed by two different users produces two different permission
states.

**Saving it creates other documents.** `on_update` (`:114`) → `create_primary_contact` (`:186`) and
`create_primary_address` (`:196`) create `Contact` and `Address` documents and then `db_set` their
names back onto the supplier — writes issued from inside a write, with the address creation gated on
`flags.is_new_doc` so it happens only once and never self-heals.

Other points:

- `validate_internal_supplier` (`:167`) enforces one internal supplier per `represents_company` by
  scan, and nulls `represents_company` when `is_internal_supplier` is off. This is the inter-company
  mechanism from doc 15 §3.
- `get_supplier_group_details` (`:153`) is whitelisted and **destructive**: it clears `payment_terms`
  and the entire `accounts` table before repopulating from the `Supplier Group`.
- `on_hold` / `hold_type` (`All`/`Invoices`/`Payments`) / `release_date`: `before_save` (`:96`) clears
  `release_date` when not on hold and defaults `hold_type` to `All`.
- `restrict_to_companies` + `allowed_companies` express per-company restriction on the master — the
  same problem decision 2 solves with `company_id` + RLS, here as a checkbox plus a child table
  enforced in application code.

### 8.2 `Party Link`

`PartyLink` (`accounts/doctype/party_link/party_link.py:10`) records that a Customer and a Supplier
are the same legal entity — the basis of common-party accounting
(`accounts/services/internal_transfer.py:69`).

`validate` (`accounts/doctype/party_link/party_link.py:24`) enforces
`primary_role ∈ {Customer, Supplier}` and then runs **three** existence probes:

```python
frappe.get_all("Party Link", {"primary_party": self.primary_party,  "secondary_party": self.secondary_party})
frappe.get_all("Party Link", {"primary_party": self.secondary_party})
frappe.get_all("Party Link", {"secondary_party": self.primary_party})
```

⚠️ The fourth combination — another link with the **same `secondary_party` as this one** — is not
checked. So `(Customer A → Supplier X)` and `(Customer B → Supplier X)` can both exist, and
"the same legal entity" becomes many-to-one. `secondary_role` is never validated either (only
`create_party_link`, `:70`, sets it to the opposite of `primary_role`), and both party fields are
`DynamicLink`s, so there is no referential integrity in any direction.

> **Ours** One `party` table with a `party_role` child (`customer`, `supplier`, `employee`,
> `shareholder`) — a legal entity that both buys and sells is **one row with two roles**, so there is
> nothing to link and none of §8.2's probes has an analogue. `party.id` is a `uuid`, never the name,
> so renaming is a `display_name` update that touches one row. Contacts and addresses are related
> tables created by their own explicit operations. Role grants are never a side effect of saving
> business data: `party_portal_access` is separate, audited, and requires its own permission.

---

## 9. Terms and payment-method masters

### 9.1 `Payment Term` has no validation at all

`PaymentTerm` (`accounts/doctype/payment_term/payment_term.py:9`) is `pass`. It carries
`invoice_portion`, `credit_days`, `credit_months`, `due_date_based_on`, `discount`, `discount_type`,
`discount_validity`, `discount_validity_based_on` and `mode_of_payment` — and validates **none** of
them.

So a single `Payment Term` may legally say: `invoice_portion = 250`, `credit_days = -30`,
`discount = 400` with `discount_type = "Percentage"`, and `due_date_based_on =
"Month(s) after the end of the invoice month"` with `credit_months = 0` and `credit_days = 45`
(where the days are then ignored — doc 05 §5.7 shows the computation picks the field matching the
mode). Every one of those is nonsense that reaches the payment schedule.

### 9.2 `Payment Terms Template` validates the template, not the schedule

`PaymentTermsTemplate` (`accounts/doctype/payment_terms_template/payment_terms_template.py:12`):

- `validate_invoice_portion` (`:33`) requires the portions to sum to exactly `100.00` at two
  decimals — enforced with `msgprint(..., raise_exception=1)`, i.e. a throw dressed as a message.
- `validate_terms` (`:42`) rejects duplicates keyed on
  `(payment_term, credit_days, credit_months, due_date_based_on)` with the message "The Payment Term
  at row {0} is **possibly** a duplicate" — and then raises. `invoice_portion` and `mode_of_payment`
  are not part of the key, so two rows that differ only in portion or payment method are rejected
  even though that is a legitimate split.

⚠️ Crucially, the 100% rule lives on the **template**. Doc 05 §5.7 showed the document's
`payment_schedule` can be edited after the template is applied, and nothing re-checks the total
there. A template that must sum to 100% produces a schedule that need not.

### 9.3 `Mode of Payment`

`ModeofPayment` (`accounts/doctype/mode_of_payment/mode_of_payment.py:11`) maps
`(company → default_account)` with `type ∈ Cash/Bank/General/Phone`.

`validate_accounts` (`:44`) checks each row's account belongs to its company;
`validate_repeating_companies` (`:35`) allows one row per company.

`validate_pos_mode_of_payment` (`:56`) is the interesting one — a genuine referential guard:

```python
if not self.enabled:
    pos_profiles = frappe.get_all("Sales Invoice Payment",
        filters={"parenttype": "POS Profile", "mode_of_payment": self.name}, pluck="parent")
    if pos_profiles: frappe.throw("POS Profile {0} contains Mode of Payment {1}. Please remove them ...")
```

It prevents disabling a mode still referenced by a POS Profile — but **only** POS Profiles. Disabling
a mode referenced by `Payment Entry`, `Payment Terms Template` or an open `Payment Request` is
permitted.

> **Ours** `payment_method` with `(company_id, account_id)` in a child table under
> `UNIQUE (payment_method_id, company_id)`, and `is_active` derived from `valid_from`/`valid_to`
> rather than a flag — so "disabling" is end-dating, existing references remain valid for their own
> dates, and there is no need for a hand-written guard per referencing doctype.
>
> `payment_term` becomes a checked table:
> `CHECK (portion_pct > 0 AND portion_pct <= 100)`, `CHECK (credit_days >= 0)`,
> `CHECK (discount_pct BETWEEN 0 AND 100)`, and a `due_basis` enum with
> `CHECK (due_basis <> 'days_after_invoice' OR credit_months = 0)` so the ignored-field case cannot
> be stored. The 100% rule moves to **where it matters**: a deferred constraint on
> `document.payment_schedule` requiring `Σ portion = 100` and `Σ amount = grand_total` on the
> document itself, not on the template it came from (doc 05 §7.3, invariant S2).

---

## 10. `Selling Settings` and `Buying Settings` — configuration that rewrites the schema

These two singles are the flag catalogue for everything above. `BuyingSettings`
(`buying/doctype/buying_settings/buying_settings.py:12`) holds 30 fields, `SellingSettings`
(`selling/doctype/selling_settings/selling_settings.py:25`) holds 35.

### 10.1 Saving them writes global defaults — a second source of truth

```python
def validate(self):                                          # buying_settings.py:53
    for key in ["supplier_group", "supp_master_name", "maintain_same_rate", "buying_price_list"]:
        frappe.db.set_default(key, self.get(key, ""))
```

`SellingSettings.validate` (`selling/doctype/selling_settings/selling_settings.py:73`) does the same
for six keys. So each value exists **twice** — in the Singles table and in `DefaultValue` — and
readers use whichever their author preferred (`frappe.defaults.get_global_default("supp_master_name")`
in `Supplier.autoname`, `frappe.get_single_value` elsewhere). A direct write to one leaves the other
stale.

### 10.2 Saving them changes DocType metadata

```python
set_by_naming_series("Supplier", "supplier_name",
                     self.get("supp_master_name") == "Naming Series", hide_name_field=False)
```

and, on the selling side, `on_update` (`:69`) writes **Property Setters**:

| Method | What it rewrites |
|---|---|
| `toggle_hide_tax_id` (`:118`) | `tax_id.hidden` and `tax_id.print_hide` on Sales Order, Sales Invoice, Delivery Note |
| `toggle_editable_rate_for_bundle_items` (`:130`) | `Packed Item.rate.read_only` |
| `toggle_discount_accounting_fields` (`:142`) | `Sales Invoice Item.discount_account.hidden` **and** its `mandatory_depends_on` |
| `toggle_tracking_sales_commissions_section` (`:196`) | hides `commission_section` / `sales_team_section` across selling doctypes |
| `toggle_utm_analytics_section` (`:210`) | hides `utm_analytics_section` across eight doctypes |

⚠️ And one of them stores an expression:

```python
make_property_setter("Sales Invoice Item", "discount_account", "mandatory_depends_on",
                     "eval: doc.discount_amount", "Code", validate_fields_for_doctype=False)
```

A settings checkbox writes a **Python expression string into field metadata**, with field validation
switched off. This is doc 18 §3 (the schema is data) and doc 21 §3 (`eval:` strings as
configuration) meeting in one function: toggling a business option mutates the definition of a
doctype, for every company on the site, with no migration record.

### 10.3 Flags that silently rewrite other flags

```python
# buying_settings.py
if not self.bill_for_rejected_quantity_in_purchase_invoice:      # :53
    self.set_valuation_rate_for_rejected_materials = 0
def check_maintain_same_rate(self):                              # :70
    if self.maintain_same_rate:
        self.set_landed_cost_based_on_purchase_invoice_rate = 0
```

Two dependent flags cleared without telling the user. And `SellingSettings`
`validate_fallback_to_default_price_list` (`:104`) knows two settings interact badly and only
**msgprints** about it:

> "You have enabled *Fallback to Default Price List* and *Auto Insert Price List Rate If Missing* in
> **Stock Settings**. This can lead to prices from the default price list being inserted into the
> transaction price list."

The system can describe the resulting data corruption and permits it anyway.

### 10.4 The catalogue itself

Grouped by what they actually control:

| Concern | Flags |
|---|---|
| Mandatory predecessor | `so_required`, `dn_required`, `po_required`, `pr_required` |
| Tolerance | `over_order_allowance`, `over_transfer_allowance`, `blanket_order_allowance`, `over_delivery_receipt_allowance` (Stock Settings) |
| Rate consistency | `maintain_same_sales_rate` / `maintain_same_rate`, `maintain_same_rate_action` (`Stop`/`Warn`), `role_to_override_stop_action` |
| Zero quantities | `allow_zero_qty_in_quotation`, `..._sales_order`, `..._purchase_order`, `..._request_for_quotation`, `..._supplier_quotation` |
| Editability | `editable_price_list_rate`, `editable_bundle_item_rates`, `allow_negative_rates_for_items`, `allow_multiple_items` |
| Naming | `cust_master_name`, `supp_master_name` |
| Roll-up frequency | `sales_update_frequency` (`Monthly`/`Each Transaction`/`Daily`), `project_update_frequency` |
| Feature switches | `enable_proforma_invoice`, `enable_discount_accounting`, `enable_utm`, `enable_tracking_sales_commissions`, `use_legacy_js_reactivity` |

⚠️ `maintain_same_rate_action` plus `role_to_override_stop_action` is the pattern to notice: **the
severity of a validation, and who may bypass it, are configuration values**. The same data is valid
or invalid depending on a checkbox and the saver's roles — so "valid" is not a property of the data.

> **Ours** Settings that change *behaviour* live in a typed `policy` table keyed by
> `(company_id, policy_key)` with a `jsonb` value validated against a stored JSON Schema, and every
> change is an insert into `policy_history` with actor and timestamp — so "why did this document
> validate in March and fail in April" is answerable. Settings never write DocType metadata, never
> write a second copy into a defaults table, and never store expressions. Where ERPNext uses
> `*_action = Stop|Warn` + an override role, we use one hard constraint plus an explicit, expiring,
> audited `policy_override` row (decision 22's mechanism, reused): the rule does not weaken, the
> exception is recorded.

---

## 11. Our design

### 11.1 Pre-commitment documents are the same shape as commitments

`quotation`, `rfq`, `supplier_quote`, `proforma`, `material_request` and `agreement` are all
`trade_document` rows with the same 8-table structure as the order/delivery/invoice documents
(decision 3): a header, `document_line`, `tax_line`, `document_charge`, and links through `doc_link`.
What differs is `document_kind` and which state machine applies — not the storage.

That single decision removes most of this chapter's findings:

| Finding | Why it disappears |
|---|---|
| Proforma borrowing totals from a Sales Order (§2.1) | it has its own `tax_line` rows |
| Four `allow_zero_qty_in_*` flags (§1.3) | `line_kind` on the line |
| `ordered_qty` filled from four sources (§6.2) | progress is one view over `doc_link` |
| Two `set_expired_status` functions that disagree (§4) | expiry is one view |
| UOM mismatch in the blanket-order cap (§5.1) | `qty_stock` everywhere (decision 7) |

### 11.2 State is events, not columns

Every status transition in this layer — quoted, replied, lost, expired, ordered, issued, transferred,
received — becomes a row in `document_state_event` (doc 06 §8). Consequences:

- **Expiry is a view**, so no nightly `UPDATE` can fight with a real transition (§1.4, §4).
- **Lost reasons survive cancellation** (§1.4), because they are events, not editable child rows.
- Transitions are validated against `document_state_transition`, a table of legal
  `(kind, from_state, to_state)` triples — so §6.1's ten-value enum with two guarded transitions
  becomes a complete, per-kind state machine that is data.

### 11.3 Codes, not labels; and never translated values

§3.2 is the strongest argument in this whole investigation for a rule we apply everywhere:

> **No stored value is ever the output of a translation function.** Enums are lowercase codes;
> display text is resolved at render time from a `label` catalogue keyed by code and locale.

The same rule kills the `_("Received")` / `"Pending"` disagreement, makes reports locale-independent,
and lets us add a language without a data migration.

### 11.4 Side effects that documents may not have

Explicit prohibitions, enforced by grants rather than convention:

| Documents may not | Enforced by |
|---|---|
| create or modify `user` / credentials (§3.1) | the application role owning `trade_document` has no grant on `user`, `portal_access` |
| grant roles (§8.1) | `role_grant` writable only by an admin role, always audited |
| write a party master with validation disabled (§3.1) | no `ignore_validate` equivalent exists; constraints are in the database |
| mutate DocType/field metadata (§10.2) | there is no runtime metadata to mutate (decision 13) |
| edit a submitted document's counters (§7) | `REVOKE UPDATE` on posted rows; corrections are compensating events |

### 11.5 Invariants

- **U1** Every pre-commitment document line links to its successor(s) only through `doc_link`; no
  document stores a quantity sourced from another document.
- **U2** `Σ proforma_line.qty` per order line ≤ `order_line.qty_stock × (1 + over_proforma_allowance)`
  — deferred constraint (§2.2).
- **U3** No two `agreement` rows overlap for the same `(company, party, item)` —
  `EXCLUDE USING gist` (§5).
- **U4** Consumption against an agreement never exceeds `qty_agreed × (1 + allowance)`, evaluated
  under the consuming document's row lock (§5.1).
- **U5** Exactly one `document_line` per `quote_option_group_id` may be `is_selected` —
  partial unique index (§1.2).
- **U6** Every state transition is representable in `document_state_transition` for that
  `document_kind`; there is no path to an unreachable state (§6.1).
- **U7** No enum column contains a translated string (§3.2) — enforced by a `CHECK` against the code
  catalogue.
- **U8** A drop-ship fulfilment is a `fulfilment_event` row with `kind = 'supplier_direct'` and zero
  `stock_move` rows; both the sales and purchase progress views read it (§7).

---

## 12. Summary

| ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| `quotation_to` as a Link-to-DocType with a DynamicLink party | **Reject** | one `party` table with roles |
| `customer_name = party_name` for Prospect | **Reject** | display name by join |
| Alternative items grouped by **row adjacency** | **Reject** | `quote_option_group_id` + partial unique on selection |
| `is_in_sales_order` probing per row in a filter | **Reject** | one view over `doc_link` |
| Four `allow_zero_qty_in_*` settings | **Reject** | `line_kind` enum on the line |
| Expiry by nightly bulk `UPDATE` | **Reject** | expiry is a view over `valid_to` |
| Expiry ignoring cancelled downstream orders | **Reject (bug)** | derived from live links |
| `Supplier Quotation` expiry ignoring Purchase Orders entirely | **Reject (bug)** | one shared definition |
| `declare_enquiry_lost` mixing `db_set` and `save()` on a submitted doc | **Reject** | one `document_state_event` insert |
| `on_cancel` emptying `lost_reasons` | **Reject** | reasons are events, retained |
| Proforma totals computed inside a PDF renderer | **Reject** | own `tax_line` rows |
| `grand_total` not recomputed when the PDF already exists | **Reject (bug)** | totals are derived, always current |
| Proforma with no `taxes` table (breakdown only in the PDF) | **Reject** | self-contained document |
| Mutating a live Sales Order object to render | **Reject** | pure projection |
| No cap on cumulative proformaed qty/amount | **Reject (bug)** | deferred constraint (U2) |
| `rate = amount / qty` stored unrounded | **Reject** | store `amount`, generate `rate` |
| `sent_on` / `emailed_to` overwritten per send | **Reject** | append-only `document_dispatch` |
| **RFQ submit creating `User` records** | **Reject** | explicit `portal_invitation` |
| `user._reset_password()` link emailed from a document submit | **Reject** | invitation flow with its own permission |
| Supplier saved with `ignore_validate` + `ignore_mandatory` + `ignore_permissions` | **Reject** | constraints in the database; no bypass exists |
| Child row `.save()` inside a loop | **Reject** | set-based writes |
| Submit failing because a Portal Menu Item is missing | **Reject** | portal config decoupled |
| `quote_status` stored as `_("Received")` | **Reject (bug)** | codes, never translated values (U7) |
| Three writers of `quote_status` with two value domains | **Reject (bug)** | one derived view |
| O(suppliers × items) COUNT queries, `set_value` in the inner loop | **Reject** | one aggregate query |
| `frappe.render_template` on user text with SSTI lint suppressed | **Reject** | typed templates with a declared variable set |
| `before_print` mutating `vendor` and item part numbers | **Reject** | render-time projection |
| No overlap detection between Blanket Orders | **Reject** | `EXCLUDE USING gist` (U3) |
| Allowance comparing stock UOM against transaction UOM | **Reject (bug)** | `qty_stock` everywhere |
| `qty = 0` meaning unlimited | **Reject** | `NULL` means unlimited, explicitly |
| `ordered_qty` read unlocked before the cap check | **Reject** | deferred constraint under row lock (U4) |
| Global `blanket_order_allowance` | **Reject** | per-agreement-line allowance |
| `make_order` taking its target doctype from `frappe.flags.args` | **Reject** | declared parameter |
| `update_item` forcing `stock_uom` and discarding the row's UOM | **Reject** | UOM carried explicitly |
| Ten statuses across four state machines in one column | **Reject** | per-kind state machine as data (U6) |
| `status_can_change` guarding only two transitions | **Reject** | complete transition table |
| Hand-rolled `modified` comparison on one path | **Reject** | database-level concurrency control |
| `ordered_qty` sourced from Stock Entry / Work Order / StatusUpdater by type | **Reject** | one view over `doc_link` |
| `frappe.db.set_value` per row in a loop | **Reject** | set-based update |
| `validate_qty_against_so` commented out at the call site | **Reject** | expressible, because demand kinds are separate tables |
| A **permission check** deciding the stored `buying_price_list` | **Reject (bug)** | defaults from configuration only |
| Drop-ship delivery recorded as a comment plus a counter | **Reject** | `fulfilment_event` row (U8) |
| `received_qty` edited in place on a submitted document | **Reject** | append-only events |
| Field-permlevel as the authorisation mechanism | **Reject** | grants + RLS (doc 19) |
| Purchasing action writing Sales Order status | **Reject** | both sides read one view |
| Party PK chosen by a site-wide setting; rename cascades | **Reject** | `uuid` PK, `display_name` column |
| Saving a Supplier granting a `User` role | **Reject** | separate audited grant |
| Role grant depending on the **saver's** roles | **Reject (bug)** | one deterministic rule |
| `on_update` creating Contact/Address and `db_set`ting back | **Reject** | explicit operations |
| `get_supplier_group_details` clearing `accounts` destructively | **Reject** | merge, with a diff shown |
| `restrict_to_companies` + `allowed_companies` in app code | **Reject** | `company_id` + RLS (decision 2) |
| `Party Link` missing the fourth uniqueness probe | **Reject (bug)** | one party, many roles — nothing to link |
| `secondary_role` never validated; DynamicLinks both sides | **Reject** | FKs |
| `Payment Term` with **no** validation | **Reject** | `CHECK`s on portion, days, discount, basis |
| 100% rule on the template but not the schedule | **Reject** | deferred constraint on the document (S2) |
| Duplicate-term key excluding `invoice_portion` | **Reject** | legitimate splits allowed |
| `msgprint(raise_exception=1)` as a throw | **Reject** | typed errors |
| Disable-guard for POS Profiles only | **Keep the intent** | end-dating + FKs, no per-doctype guards |
| Settings mirrored into `DefaultValue` | **Reject** | one source of truth |
| Settings writing Property Setters | **Reject** | no runtime metadata (decision 13) |
| A settings toggle storing `"eval: doc.discount_amount"` | **Reject** | no stored expressions |
| Flags silently clearing other flags | **Reject** | validated policy documents |
| Known-bad settings combination permitted with a msgprint | **Reject** | schema-validated policy |
| `*_action = Stop|Warn` + `role_to_override_stop_action` | **Reject** | hard constraint + audited expiring override |

---

Cross-references: **[S01](../scenarios/S01-order-to-cash.md)** and
**[S03](../scenarios/S03-procure-to-pay.md)** (where these documents lead),
doc 05 §5.7 (payment schedule computation, which §9 feeds), doc 06 §3 (submit/cancel lifecycle),
doc 09 §2–§3 (renameable string primary keys), doc 10 (the fulfilment engine and `per_*` counters),
doc 15 §3 (internal suppliers and inter-company), doc 17 §2 (UOM conflation),
doc 18 §3 (the schema is data), doc 19 §3 (permlevels and the eight bypasses),
doc 20 §5 (`db_set` invisible to the audit trail), doc 21 §3 (`eval:` and template injection),
doc 28 §1.1 (party/address tax category), doc 29 §2.4 (`price_not_uom_dependent`, which §6.4 uses),
`docs/design/FINAL-SCHEMA.md`, `docs/COVERAGE.md`.
