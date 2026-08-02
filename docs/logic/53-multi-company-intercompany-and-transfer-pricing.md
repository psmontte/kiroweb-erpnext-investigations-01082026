# 53 — Multi-Company, Inter-Company Documents and Transfer Pricing

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` and `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/` and relative to `/projects/sandbox/frappe/frappe`.

Docs [50](50-authentication-session-and-tenant-context.md)–[52](52-tenant-isolation-and-rls-under-attack.md)
established that company is a data dimension with no enforced boundary. This document asks the complementary
question: **when a transaction legitimately crosses companies, what does the system actually record?**

That is a different problem from isolation. Isolation says "A must not see B". Inter-company says "A sold to B,
and the group as a whole sold nothing" — which requires the crossing to be a *recognised, paired, eliminable
fact*. Doc 15 §1 traced the mechanics of inter-company documents; this document evaluates them as a
**group-accounting** model and finds the pairing is real but the eliminability is not.

Invariants continue from doc 52 at **T14**.

---

## 1. The company hierarchy exists but carries no group semantics

`Company` is a tree — `parent_company`, `is_group`, and a nested-set children API
(`setup/doctype/company/company.py:1044-1069`). So a group structure is expressible.

What the tree does **not** carry is anything a consolidation needs: no ownership percentage, no acquisition
date, no consolidation method, no functional currency distinct from the reporting currency, and no
"eliminate against" relationship. It is an organisational label.

The confirming search: **`consolidat` appears nowhere in an accounting sense.** Every match in the pinned tree
is POS invoice consolidation — `consolidate_pos_invoices`, `is_consolidated`, `consolidated_invoice`
(`accounts/doctype/pos_closing_entry/pos_closing_entry.py:110-230`) — which merges many POS invoices into one
Sales Invoice within a single company. There is **no group consolidation, no elimination engine, no minority
interest and no group report** in ERPNext.

Company-level accounting configuration is per company and includes exactly one group-aware account:
`unrealized_profit_loss_account` (`accounts/doctype/account/account.py:725-740`). That single field is the whole
of ERPNext's group-profit machinery, and §4 shows what it is used for.

> **Invariant T14 — a group is a modelled structure, not a naming convention.** Companies form an explicit
> ownership graph with, per edge and per effective period, the ownership percentage, the consolidation method
> and the elimination policy. A company records its functional currency separately from any presentation
> currency. Group membership is effective-dated, because acquisitions and disposals change it and prior periods
> must remain reproducible.

---

## 2. Inter-company identity: parties that represent companies

The crossing is modelled by making each company a **party** in the other's books
(`accounts/doctype/sales_invoice/mapper.py:88-124`):

```text
selling side  → find Supplier where is_internal_supplier=1, represents_company=doc.company, disabled=0
                and the counterparty company = Customer.represents_company
buying side   → the mirror: Customer where is_internal_customer=1, represents_company=doc.company
```

`Allowed To Transact With` then restricts which companies an internal party may face
(`accounts/doctype/sales_invoice/services/inter_company.py:50-64`), and `_validate_against_reference` checks
both directions of the pairing when a reference exists
(`accounts/doctype/sales_invoice/services/inter_company.py:40-49`):

```python
if frappe.db.get_value(config.partytype, {"represents_company": doc.company}, "name") != party:
    throw "Invalid {partytype} for Inter Company Transaction"
if frappe.get_cached_value(config.ref_partytype, ref_party, "represents_company") != company:
    throw "Invalid Company for Inter Company Transaction"
```

That is a genuine bidirectional consistency check, and it is the strongest part of the design.

**Where it degrades is ambiguity.** `get_internal_party` handles multiple candidate parties by guessing
(`accounts/doctype/sales_invoice/mapper.py:126-148`):

```text
if exactly one party            → use it
else if an address is present   → resolve via Dynamic Link on that address
                                  if that yields nothing → parties[0]
else                            → parties[0]
```

So with two internal suppliers representing the same company and no address, the counterparty is **the first
row the database returned** — an unordered query. The first check in `_validate_against_reference` has the same
shape: `get_value(partytype, {"represents_company": doc.company})` takes *one* row for a filter that may match
several.

> **Invariant T15 — the counterparty of a crossing is identified, never inferred.** An inter-company
> relationship is a first-class row naming both companies, the two party identities that represent them, and
> the effective period. Resolution is a lookup with exactly one answer, enforced by a unique constraint; where
> more than one candidate could exist, the transaction names which one it used. No crossing is resolved by
> taking the first row of an unordered query.

---

## 3. Transfer pricing: three rules, all optional

### 3.1 Currency must match

`validate_inter_company_transaction` requires the two companies' `default_currency` to be equal
(`accounts/doctype/sales_invoice/mapper.py:149-175`):

```python
if default_currency != doc.currency:
    throw "Company currencies of both the companies should match for Inter Company Transactions."
```

So ERPNext's inter-company support **does not handle a cross-currency crossing at all** — the case that
matters most in a real group, and the one doc 54 has to solve.

It also requires the price list to be both buying and selling — unless the document is an internal transfer
(`accounts/doctype/sales_invoice/mapper.py:149-175`).

### 3.2 Pricing rules are switched off

For an internal transfer, `disable_pricing_rule` sets `ignore_pricing_rule = 1` and tells the user
(`accounts/services/internal_transfer.py:120-135`), and `disable_tax_included_prices` follows. This is correct
intent — a transfer price should not be discovered by a promotional rule — implemented as a document-field
override rather than as a policy.

### 3.3 Rate consistency is opt-in

`validate_transaction` returns immediately unless the `maintain_same_internal_transaction_rate` setting is on
(`accounts/services/internal_transfer.py:104-119`):

```python
if not cint(frappe.get_single_value("Accounts Settings", "maintain_same_internal_transaction_rate")):
    return
```

So by default **the two sides of a crossing may carry different rates**. The selling company can invoice 100
and the buying company book 90, and nothing objects. For a group, that difference is unrecognised profit
sitting in inventory.

`is_internal_transfer` is the predicate that gates all of this
(`accounts/services/internal_transfer.py:19-29`):

```python
return bool(doc.get(internal_party_field) and doc.represents_company == doc.company)
```

Note what it compares: `represents_company == company` — the party represents *the same company as the
document*. That identifies a transfer **within** one company's own books via an internal party, which is a
different relation from "these two documents are the two halves of a crossing".

> **Invariant T16 — transfer price is a policy, and both sides agree exactly.** An inter-company transfer
> resolves its price from an approved, effective-dated transfer-pricing policy for the company pair, item class
> and period — never from a promotional or discount rule. Both legs of a crossing carry the **same** transfer
> price and quantity by deferred constraint, with any difference recognised explicitly as unrealised group
> profit rather than absorbed silently.

---

## 4. The unrealised profit account

`set_account` resolves `unrealized_profit_loss_account` from the company when the document is an internal
transfer, and refuses to proceed without one
(`accounts/services/internal_transfer.py:37-53`):

```python
if not self.is_internal_transfer() or self.doc.unrealized_profit_loss_account:
    return
... resolve from Company ... else throw
```

This is the one place ERPNext acknowledges that intra-group margin is not real profit. It is:

- **per company**, not per company pair — so the counterparty relationship is not recorded on the account;
- **applied only when `is_internal_transfer()`** — i.e. only to the narrow same-company relation of §3.3, not
  to every crossing; and
- **not an elimination.** The amount lands in an account named "unrealised", and nothing later reverses it when
  the goods are sold outward, because there is no mechanism that tracks whether they were.

So the group's unrealised profit is *parked*, not *tracked*. Realisation is manual.

---

## 5. Pairing: real links, mutable both ways

`make_inter_company_transaction` maps the source document into its mirror
(`accounts/doctype/sales_invoice/mapper.py:176-260`): Sales Invoice → Purchase Invoice, Sales Order → Purchase
Order, and the reverse (`accounts/doctype/purchase_invoice/mapper.py:41-60`). Journal Entries have their own
mirror (`accounts/doctype/journal_entry/mapper.py:212-240`) with account validation
(`accounts/doctype/journal_entry/journal_entry.py:362-380`).

The mapping is careful in the ways that matter operationally:

- `received_items` subtracts what the target already received, and the row condition drops fully-received lines
  (`accounts/doctype/sales_invoice/mapper.py:176-260`) — so partial mirroring works;
- income/expense accounts, cost centre and warehouse are **explicitly not copied**
  (`field_no_map`), because they belong to the other company's chart; and
- warehouse fields are swapped directionally — `target_warehouse` becomes `from_warehouse`.

The link itself is `inter_company_invoice_reference` / `inter_company_order_reference`, written on **both**
documents by `update_linked_doc` and cleared on both by `unlink_inter_company_doc`
(`accounts/doctype/sales_invoice/services/inter_company.py:66-86`):

```python
frappe.db.set_value(doctype, name, ref_field, "")
frappe.db.set_value(ref_doc, inter_company_reference, ref_field, "")
```

Two mutable scalar fields, written with `db.set_value`, are the entire representation of "these two documents
are one economic event". There is no pairing record, so:

- the pair can be **unlinked** after both sides have posted, leaving two unrelated documents in two companies;
- nothing constrains the pair to agree on amount, quantity, date or currency beyond §3; and
- a broken pair is indistinguishable from a document that never had one.

`validate_reference` does require the reference on the *buying* side of an internal transfer, down to the row
level (`accounts/services/internal_transfer.py:76-103`) — good, and one-directional.

> **Invariant T17 — a crossing is one fact with two legs.** An inter-company transaction is a single immutable
> `intercompany_transaction` naming both companies, both documents, the transfer-price policy and the effective
> date; each leg references it. The pair cannot be unlinked, only reversed as a whole. Deferred constraints
> require the legs to agree exactly on quantity, transfer price, transaction currency and effective date, and
> the pair carries the elimination entries it implies.

---

## 6. Common party: a different problem, conflated

`Party Link` links a Customer and a Supplier that are the same legal entity
(`accounts/doctype/party_link/party_link.py:24-68`). Its validation is thorough — it refuses a duplicate pair,
refuses a secondary already linked as a primary, and refuses a primary already linked as a secondary — which
together enforce a **one-hop, non-chaining** relation.

`process_common_party_accounting` then, when `enable_common_party_accounting` is on, creates an advance and
reconciles it against the invoice (`accounts/services/internal_transfer.py:54-75`).

This is **net settlement between a customer and supplier who are one entity** — a receivable/payable offset. It
is not an inter-company crossing, and it is not consolidation. It shares a service module with internal
transfer (`accounts/services/internal_transfer.py`), which is why the two are easy to confuse; keeping them
distinct matters, because their eliminations are different: common party nets *balances*, inter-company
eliminates *transactions*.

Note the polarity again: the feature is off unless `enable_common_party_accounting` is set, and toggling it
propagates through Accounts Settings (`accounts/doctype/accounts_settings/accounts_settings.py:126-140`).

---

## 7. Evidence versus projection

| Representation | Classification |
|---|---|
| `Company` tree (`parent_company`, `is_group`) | organisational label; **no ownership, method or dates** |
| `Customer.represents_company` / `Supplier.represents_company` | the crossing's identity, on mutable master data |
| `is_internal_customer` / `is_internal_supplier` | flags on master data |
| `Allowed To Transact With` | permitted counterparties — real narrowing |
| `inter_company_invoice_reference` (both sides) | **two mutable scalars**, the whole pairing |
| the mirrored document | an independent document in the other company's books |
| `unrealized_profit_loss_account` | per company, parked amount, no realisation tracking |
| `maintain_same_internal_transaction_rate` | opt-in setting; off means the legs may disagree |
| `ignore_pricing_rule = 1` on transfers | document-field override |
| `Party Link` | one-hop customer↔supplier identity (well validated) |
| advance created by common-party accounting | settlement evidence |
| group consolidation, eliminations, minority interest | **do not exist** |

The audit path for "what did the group actually earn" does not exist: there is no record that pairs the two
legs immutably, no elimination entry, and no consolidation ledger to hold one.

---

## 8. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) and doc 52 §8. Companies remain the tenant boundary
(T1); the group structures below are **cross-company by construction** and therefore live outside the ordinary
company policy, readable only by a principal holding a group-scoped grant.

```sql
company_group(id, code, name, presentation_currency_id)  UNIQUE (code)        -- [GROUP-SCOPED]

company_group_edge(id, company_group_id, parent_company_id, child_company_id,
    ownership_pct numeric(9,6) NOT NULL,
    consolidation_method consolidation_method_enum /*full|proportional|equity|none*/,
    effective_from date NOT NULL, effective_to date NULL,
    acquired_on date NULL, disposed_on date NULL)
   UNIQUE (company_group_id, parent_company_id, child_company_id, effective_from)
   EXCLUDE USING gist (company_group_id WITH =, parent_company_id WITH =, child_company_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&)
   CHECK (parent_company_id <> child_company_id)
   CHECK (ownership_pct > 0 AND ownership_pct <= 100)
   -- publish trigger rejects cycles and reports the full path

intercompany_relationship(id, company_group_id,
    company_a_id, company_b_id,
    party_in_a_id bigint NOT NULL,      -- the party in A's books that represents B
    party_in_b_id bigint NOT NULL,      -- the party in B's books that represents A
    effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_group_id, company_a_id, company_b_id, effective_from)
   EXCLUDE USING gist (company_a_id WITH =, company_b_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
   CHECK (company_a_id <> company_b_id)
   -- ONE answer per ordered pair per date: §2's parties[0] guess becomes impossible

transfer_price_policy_revision(id, company_group_id, intercompany_relationship_id,
    item_class text NULL, revision_no integer,
    basis transfer_price_basis_enum /*cost|cost_plus_markup|resale_minus|
                                     comparable_uncontrolled|standard_cost|negotiated*/,
    markup_pct numeric(9,6) NULL, price_list_id bigint NULL,
    effective_from date, effective_to date NULL, state revision_state_enum,
    approved_at, approved_by)
   UNIQUE (company_group_id, intercompany_relationship_id, item_class, revision_no) NULLS NOT DISTINCT
   EXCLUDE USING gist (intercompany_relationship_id WITH =, item_class WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&) WHERE (state = 'approved')
   CHECK ((basis = 'cost_plus_markup') = (markup_pct IS NOT NULL))

intercompany_transaction(id, company_group_id, intercompany_relationship_id,
    transaction_kind ic_kind_enum /*sale|service|stock_transfer|loan|recharge|dividend|
                                   asset_transfer*/,
    transfer_price_policy_revision_id bigint NOT NULL,
    effective_on date NOT NULL,
    seller_company_id, buyer_company_id,
    seller_doc_type text, seller_doc_id bigint,
    buyer_doc_type  text, buyer_doc_id  bigint,
    transaction_currency_id, transfer_amount numeric(19,4) NOT NULL,
    command_receipt_id, reverses_transaction_id bigint NULL)
   UNIQUE (company_group_id, seller_doc_type, seller_doc_id)
   UNIQUE (company_group_id, buyer_doc_type,  buyer_doc_id)
   UNIQUE (company_group_id, command_receipt_id)
   CHECK (seller_company_id <> buyer_company_id)
   -- ONE fact, TWO legs. It cannot be unlinked; correction is a reversal of the whole pair.
   -- deferred: both legs exist, and agree on quantity, transfer_amount, transaction currency and
   --           effective_on; and the policy revision is approved and effective on that date.

intercompany_leg_line(id, company_group_id, intercompany_transaction_id,
    side ic_side_enum /*seller|buyer*/, source_line_type text, source_line_id bigint,
    item_id, qty numeric(21,9), unit_transfer_price numeric(21,9), amount numeric(19,4))
   UNIQUE (company_group_id, intercompany_transaction_id, side, source_line_id)
   -- deferred: per item, Σ seller qty = Σ buyer qty and Σ seller amount = Σ buyer amount, EXACTLY

unrealised_margin(id, company_group_id, intercompany_transaction_id,
    item_id, qty_transferred numeric(21,9), margin_per_unit numeric(21,9),
    margin_total numeric(19,4),
    qty_realised numeric(21,9) NOT NULL DEFAULT 0,
    margin_realised numeric(19,4) NOT NULL DEFAULT 0)
   UNIQUE (company_group_id, intercompany_transaction_id, item_id)
   CHECK (qty_realised <= qty_transferred)
   -- the thing §4 lacks: margin is TRACKED, not parked. Realisation is an event, not a manual journal.

unrealised_margin_realisation(id, company_group_id, unrealised_margin_id,
    realising_event_type text, realising_event_id bigint,   -- outward sale, consumption, write-off
    qty numeric(21,9), amount numeric(19,4), realised_on date,
    command_receipt_id, reverses_realisation_id bigint NULL)
   UNIQUE (company_group_id, command_receipt_id)
   -- deferred: Σ unreversed qty per margin <= qty_transferred

common_party_link(id, company_id, primary_party_id, secondary_party_id,
    effective_from date, effective_to date NULL)
   UNIQUE (company_id, primary_party_id, secondary_party_id)
   UNIQUE (company_id, secondary_party_id)      -- one-hop; a secondary cannot also be a primary
   CHECK (primary_party_id <> secondary_party_id)
   -- keeps Party Link's genuinely good non-chaining rule as constraints instead of three probes
```

### 8.1 Ordering

```text
crossing
1  claim idempotency ; resolve intercompany_relationship for (A, B) on the effective date — exactly one
2  resolve the approved transfer_price_policy_revision for the relationship, item class and date
3  compute the transfer price from the policy; promotional and discount rules are NOT consulted
4  insert intercompany_transaction (state pending) with the policy revision and effective date
5  post the seller leg in A under A's scope; post the buyer leg in B under B's scope
      — two scoped writes, each under its own company policy (doc 52 §7.2 W8)
6  insert intercompany_leg_line rows for both sides
7  insert unrealised_margin where the transfer price exceeds originating cost
8  run deferred checks: legs exist, quantities and amounts agree exactly, currency and date agree
9  insert the elimination entries the pair implies (doc 56)
10 domain_event + outbox ; commit

realisation
1  an outward sale, consumption or write-off of transferred stock resolves its unrealised_margin
2  insert unrealised_margin_realisation for the realised quantity
3  reverse the corresponding elimination ; commit
```

Step 5 is the important one: a crossing is **two writes in two scopes**, not one write that spans them. Nothing
in the design lets a session act in two companies at once (T3), so the crossing is orchestrated by a
group-scoped principal that holds a grant in both — and that grant is auditable.

> **Invariant T18 — intra-group margin is tracked to realisation.** Margin arising on a crossing is recorded
> per transaction and item with its transferred quantity, and is realised only by an event that takes the goods
> or service outside the group. Group profit at any instant is transferred margin minus realised margin,
> derived from facts. No amount is parked in an account and left for a manual journal.

---

## 9. Defects and risks

1. **No consolidation exists.** `consolidat` matches only POS invoice merging
   (`accounts/doctype/pos_closing_entry/pos_closing_entry.py:110-230`); there is no group report, elimination
   engine or minority interest.
2. **The company tree carries no group semantics** — no ownership percentage, method, acquisition date or
   functional currency (`setup/doctype/company/company.py:1044-1069`).
3. **Cross-currency crossings are refused outright**
   (`accounts/doctype/sales_invoice/mapper.py:149-175`).
4. **The counterparty is guessed** when several internal parties exist: address lookup, else `parties[0]`
   (`accounts/doctype/sales_invoice/mapper.py:126-148`).
5. **`get_value` on a multi-match filter** picks one row in reference validation
   (`accounts/doctype/sales_invoice/services/inter_company.py:40-49`).
6. **Rate agreement between legs is opt-in** — off by default
   (`accounts/services/internal_transfer.py:104-119`).
7. **The pairing is two mutable scalars**, and can be unlinked after posting
   (`accounts/doctype/sales_invoice/services/inter_company.py:66-86`).
8. **Nothing constrains the legs to agree** on amount, quantity or date beyond the optional rate check.
9. **Unrealised profit is parked, not tracked** — per company, no realisation mechanism
   (`accounts/services/internal_transfer.py:37-53`).
10. **`is_internal_transfer()` tests `represents_company == company`**, a same-company relation, so the
    unrealised-profit path does not cover every crossing
    (`accounts/services/internal_transfer.py:19-29`).
11. **Common-party accounting is opt-in** and shares a module with internal transfer, conflating balance
    netting with transaction elimination
    (`accounts/services/internal_transfer.py:54-75`,
    `accounts/doctype/accounts_settings/accounts_settings.py:126-140`).
12. **Pricing suppression is a document-field override** rather than a policy
    (`accounts/services/internal_transfer.py:120-135`).

Genuinely good, and adopted: the bidirectional reference validation
(`accounts/doctype/sales_invoice/services/inter_company.py:40-49`), `Allowed To Transact With`
(`accounts/doctype/sales_invoice/services/inter_company.py:50-64`), `Party Link`'s non-chaining rules
(`accounts/doctype/party_link/party_link.py:24-68`), partial mirroring via `received_items`, the deliberate
exclusion of accounts and cost centres from the mapping, directional warehouse swapping
(`accounts/doctype/sales_invoice/mapper.py:176-260`), row-level reference enforcement on the buying side
(`accounts/services/internal_transfer.py:76-103`), and the recognition — however incompletely implemented —
that intra-group margin is not profit.

---

## 10. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| `Company` tree with `parent_company` | **Change** | `company_group_edge` with ownership, method and dates |
| Parties representing companies | **Adopt the concept** | `intercompany_relationship` naming both parties |
| `is_internal_customer` / `is_internal_supplier` flags | **Change** | membership of a relationship, not master-data flags |
| `Allowed To Transact With` | **Adopt** | the relationship row *is* the permission |
| Bidirectional reference validation | **Adopt and strengthen** | deferred constraints on one paired fact |
| `parties[0]` fallback | **Reject** | unique relationship per ordered pair and date |
| `get_value` on a multi-match filter | **Reject** | unique constraint makes it single-valued |
| Same-currency requirement | **Reject** | cross-currency crossings are the normal case (doc 54) |
| Price list must be buying and selling | **Change** | transfer price comes from a policy, not a price list role |
| `ignore_pricing_rule` on transfers | **Adopt the intent** | policy-derived price; promotional rules never consulted |
| `maintain_same_internal_transaction_rate` opt-in | **Reject** | legs agree exactly, always, by constraint |
| Mirrored document creation | **Adopt** | both legs, each posted in its own scope |
| `field_no_map` for accounts and cost centres | **Adopt** | each company's chart is its own |
| Directional warehouse swap | **Adopt** | explicit on the leg |
| `received_items` partial mirroring | **Adopt** | leg lines carry quantities; residual is derived |
| `inter_company_*_reference` scalars | **Reject** | `intercompany_transaction` as one immutable fact |
| `unlink_inter_company_doc` | **Reject** | a pair is reversed, never unlinked |
| Row-level reference enforcement on buying | **Adopt** | leg-line agreement covers both sides |
| `unrealized_profit_loss_account` per company | **Change** | `unrealised_margin` per transaction and item |
| Manual realisation of unrealised profit | **Reject** | `unrealised_margin_realisation` events |
| `Party Link` non-chaining validation | **Adopt as constraints** | two unique indexes replace three probes |
| Common-party advance creation | **Adopt** | balance netting, kept distinct from elimination |
| `enable_common_party_accounting` opt-in | **Adopt as policy** | per company-group policy |
| Inter-company Journal Entry mirror | **Adopt** | a crossing kind, same paired fact |
| No consolidation | **Reject** | doc 56 |

Invariants introduced here are **T14–T18**. Doc 54 continues at **T19** with the currency layering that §3.1
refuses to attempt.

---

Cross-references: [doc 15](15-intercompany-and-history-rewriting.md) (the mechanics this evaluates as a group
model), [doc 50](50-authentication-session-and-tenant-context.md)–[doc 52](52-tenant-isolation-and-rls-under-attack.md)
(why a crossing is two scoped writes rather than one), [doc 01](01-gl-posting-engine.md) (posting and balance
exactness), [doc 04](04-ar-ap-and-settlement.md) (the settlement model common-party netting rides on),
[doc 05](05-taxes-totals-and-pricing.md) and [doc 29](29-pricing-determination.md) (the pricing engine a
transfer price must *not* consult), [doc 02](02-stock-ledger-and-valuation.md) (transferred stock carries the
margin §8 tracks), [doc 41](41-asset-identity-acquisition-and-finance-books.md) (asset transfers as a crossing
kind), and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 54 — multi-currency layering.
