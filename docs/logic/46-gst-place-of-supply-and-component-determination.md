# 46 — Place of Supply, Component Determination, Reverse Charge and Ineligible ITC

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56`, `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (`develop`, `17.0.0-dev`).
>
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/`; India Compliance citations are prefixed `india_compliance/` and are relative to
> `/projects/sandbox/india_compliance/india_compliance`.

[Doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) established registration identity,
classification and the five-component tax structure. This document is the arithmetic core: **given a
transaction, which components apply, at what rate, to which accounts, and in which direction.**

Everything here happens inside `india_compliance/gst_india/overrides/transaction.py` (1,980 lines) and its
neighbours. Four questions drive it:

1. **Where is the supply made?** — place of supply, and whether it is intra-state or inter-state.
2. **Which accounts may appear?** — CGST+SGST or IGST, output or input, normal or reverse charge.
3. **Who pays?** — forward charge, reverse charge, or export without payment.
4. **Is the input credit usable?** — and if not, where does the tax go instead.

Invariants continue from doc 45 at **G9**.

---

## 1. Where determination happens in the document lifecycle

`before_validate_transaction` runs first, setting GST tax types and place of supply and recomputing taxes
(`india_compliance/gst_india/overrides/transaction.py:1574-1614`). `validate_transaction` then runs the
gate battery (`india_compliance/gst_india/overrides/transaction.py:1615-1687`). Item-level details are
recomputed separately (`india_compliance/gst_india/overrides/transaction.py:1688-1701`), and there are
after-submit paths that resync transporter and address-dependent fields
(`india_compliance/gst_india/overrides/transaction.py:1861-1966`).

Two structural observations before any of the arithmetic:

- **Determination is a mutation of the document, not a returned result.** `_update_place_of_supply_and_taxes`
  writes `place_of_supply` onto the document and then re-runs the tax controller
  (`india_compliance/gst_india/overrides/transaction.py:1592-1614`). There is no determination record
  separate from the document being determined.
- **Some GST fields change after submission.** `before_update_after_submit` and
  `sync_address_dependent_fields_after_submit` allow transporter and address-derived GST fields to be
  rewritten on a submitted document
  (`india_compliance/gst_india/overrides/transaction.py:1861-1887`,
  `india_compliance/gst_india/overrides/transaction.py:1913-1966`). For fields that determine tax treatment,
  that is a mutable posted fact.

> **Invariant G9 — determination is a recorded computation, not a document mutation.** Jurisdiction, place of
> supply, supply type, registration snapshots, classification revision, rate revision and the resulting
> component amounts are computed once by a pure function and written as **immutable determination facts**
> attached to the posted document, together with the rule-revision identities and an engine version. Nothing
> that determines tax treatment is editable after posting; a correction is a new determination linked to a
> reversal.

---

## 2. Place of supply

### 2.1 It is stored as a composite display string

Place of supply is `"NN-State Name"` — a state number joined to a state name, validated by membership in a
generated option list (`india_compliance/gst_india/overrides/transaction.py:545-576`). Every consumer then
**slices the string** to recover the code:

```python
return doc.place_of_supply[:2] != get_source_state_code(doc)
```

(`india_compliance/gst_india/overrides/transaction.py:577-592`).

So the authoritative statutory code — the thing that decides whether a supply is intra-state or inter-state,
and therefore which taxes apply — is the **first two characters of a human-readable label**. Doc 30 §3.2
produced invariant U7 ("no stored value is ever a translation") for exactly this shape of problem; here the
stakes are statutory rather than cosmetic. If the label is ever localised or renamed, the tax computation
changes.

### 2.2 Source state resolution is doctype-dependent

`get_source_state_code` answers "where is the supply *from*", with a different rule per document type
(`india_compliance/gst_india/overrides/transaction.py:593-625`):

| Document | Source state code |
|---|---|
| Sales doctypes, `Payment Entry` | `company_gstin[:2]` |
| `Stock Entry` | `Address.gst_state_number` when `bill_from` is Unregistered, else `(bill_from_gstin or bill_to_gstin)[:2]` |
| any doc with `gst_category == "Overseas"` | `"96"` |
| any doc with `gst_category == "Unregistered"` and a supplier address | `Address.gst_state_number` |
| purchase, subcontracting order/receipt | `(supplier_gstin or company_gstin)[:2]` |

Three things follow. First, the code is recovered by **string slicing a registration number** — a GSTIN's
first two characters. Second, `"96"` (Other Countries) is a magic literal standing in for "outside the
jurisdiction". Third, the final branch falls back to `company_gstin` when the supplier has no GSTIN, which
silently converts an unregistered inter-state purchase into an intra-state one unless the address branch
caught it first.

### 2.3 Inter-state determination

```text
if party_gst_category == "SEZ":            return True     # always inter-state, regardless of geography
if not place_of_supply:                    return False    # absent → treated as INTRA-state
return place_of_supply[:2] != source_state_code
```

(`india_compliance/gst_india/overrides/transaction.py:577-592`).

The SEZ rule is correct statute — a supply to a Special Economic Zone is treated as inter-state even within
one state. The middle line is the dangerous one: **a missing place of supply silently means intra-state**,
which selects CGST+SGST. A default that picks a tax treatment is a default that can be wrong quietly.

For sales to an Overseas category party, place of supply must be `96-Other Countries` unless there is an
Indian shipping address, in which case the supply is B2C within India
(`india_compliance/gst_india/overrides/transaction.py:545-576`).

> **Invariant G10 — place of supply is a resolved code with recorded provenance.** Place of supply is stored
> as a jurisdiction area code, never as a display label, and the posted document records **which rule
> resolved it** (party registration, shipping address, company registration, or explicit override) alongside
> the code. Absence of a place of supply is a refusal, never a default that selects a tax treatment.

---

## 3. Which accounts may appear

`get_applicable_gst_accounts` returns two sets — every GST account for the transaction kind, and the subset
applicable to *this* supply (`india_compliance/gst_india/overrides/transaction.py:209-245`):

```text
account_types = ["Output"] for sales, ["Input"] for purchase
if is_reverse_charge: append "Sales Reverse Charge" / "Purchase Reverse Charge"

for each account in those types:
    if is_inter_state     and account is cgst/sgst → all_gst_accounts only   (not applicable)
    if not is_inter_state and account is igst      → all_gst_accounts only   (not applicable)
    otherwise                                      → applicable + all
```

That is the intra/inter duality expressed as a filter: CGST and SGST are excluded inter-state, IGST is
excluded intra-state, and cess accounts are always applicable. `get_valid_accounts` builds the same
partition for validation purposes, additionally including `Output Refund`
(`india_compliance/gst_india/overrides/transaction.py:247-271`).

`set_gst_tax_type` maps each tax row's `account_head` to a `gst_tax_type` through an account map, **setting
it to `None` when the account is not a GST account**
(`india_compliance/gst_india/overrides/transaction.py:272-282`). Every downstream rule keys off that field,
so an account that falls out of the map is not "invalid" — it becomes invisible to GST validation.

`GSTAccounts.validate` then runs five checks in order
(`india_compliance/gst_india/overrides/transaction.py:283-300`):

1. `validate_invalid_account_for_transaction` — sales accounts on sales, purchase on purchase;
2. `validate_for_same_party_gstin` — no GST when both sides carry the same GSTIN;
3. `validate_reverse_charge_accounts`;
4. `validate_sales_transaction`;
5. `validate_purchase_transaction`.

Check 2 is the one that encodes a real statutory principle structurally: a supply to yourself is not a
supply.

> **Invariant G11 — component applicability is derived, and unmapped accounts are refusals.** The applicable
> component set is a pure function of (jurisdiction, supply type, transaction direction, reverse-charge flag),
> and posting to a component account outside that set is refused by constraint. A tax line whose account has
> no component mapping is an error, never a silently untyped row.

---

## 4. Reverse charge

### 4.1 The balancing rule

Under reverse charge the recipient books the tax that the supplier would otherwise have charged, so the
document carries both an applied tax and a booked liability that must cancel
(`india_compliance/gst_india/overrides/transaction.py:996-1061`):

```text
for each tax row with a gst_tax_type and a non-zero amount:
    amount = base_tax_amount_after_discount_amount   (negated when is_return)

    if "rcm" not in gst_tax_type:                    # forward-charge row
        require add_deduct_tax == "Add" and amount > 0
        base_gst_tax += amount

    else:                                            # reverse-charge row
        if add_deduct_tax == "Deduct":
            require amount > 0 ; base_reverse_charge_booked -= amount
        else:
            require amount < 0 ; base_reverse_charge_booked += amount

require flt(base_gst_tax + base_reverse_charge_booked, 2) == 0
```

Worked, a 5,000.00 intra-state reverse-charge purchase at 18%:

| Row | Account | `gst_tax_type` | `add_deduct_tax` | Amount |
|---|---|---|---|---:|
| 1 | Input CGST | `cgst` | Add | **+450.00** |
| 2 | Input SGST | `sgst` | Add | **+450.00** |
| 3 | Purchase RCM CGST | `cgst_rcm` | Add | **−450.00** |
| 4 | Purchase RCM SGST | `sgst_rcm` | Add | **−450.00** |

`base_gst_tax = +900.00`, `base_reverse_charge_booked = −900.00`, sum `0.00` → accepted. The recipient claims
900.00 of input credit and simultaneously books 900.00 of liability.

For a credit note (`is_return`), every sign expectation flips, and the error message flips with it
(`india_compliance/gst_india/overrides/transaction.py:1000-1013`).

**The defect is the tolerance.** The equality is evaluated at `flt(…, 2)` — a hard-coded two-decimal
rounding, not the document's own currency precision and not an exact comparison. Doc 01 §1.3 rejected
ERPNext's 0.5 balance tolerance for the general ledger; this is the same class of concession applied to a
statutory liability, and 2 is a literal rather than a derived precision.

### 4.2 How reverse charge gets set

`set_reverse_charge_as_per_gst_settings` and `set_reverse_charge` apply the flag from configuration and party
data (`india_compliance/gst_india/overrides/transaction.py:1473-1535`). On the sales side,
`validate_sales_reverse_charge` refuses reverse charge to a customer with no GSTIN
(`india_compliance/gst_india/overrides/transaction.py:645-649`) — correct, since an unregistered recipient
cannot discharge the liability.

### 4.3 Refund accounts

`validate_gst_refund_accounts` applies to sales documents only
(`india_compliance/gst_india/overrides/transaction.py:1062-1099`). Refund rows must be negative on a normal
invoice and positive on a credit note, and when any refund row is present the **net of all GST rows must be
zero** at the document's own tax precision:

```text
tax_precision = doc.precision("base_tax_amount_after_discount_amount", "taxes")
if has_refund and flt(net_amount, tax_precision) != 0:
    throw "Total GST amount should be equal to Refund amount."
```

Note the inconsistency with §4.1: this check uses the **document's** precision, the reverse-charge check uses
a hard-coded `2`. Two statutory balance rules in one file, two different precision policies.

`is_export_without_payment_of_gst` is the third payment mode: an overseas document without
`is_export_with_gst` (`india_compliance/gst_india/overrides/transaction.py:1100-1102`) — zero-rated with no
tax collected, distinct from both forward and reverse charge.

> **Invariant G12 — liability direction is typed, and its balance is exact.** Forward charge, reverse charge,
> refund and zero-rated export are typed determination outcomes, each with its own required component set and
> sign policy. Where a rule requires two amounts to cancel, they cancel **exactly** at the document's
> declared money precision, enforced by a deferred constraint. No statutory equality is evaluated against a
> hard-coded decimal place.

---

## 5. Ineligible input tax credit

When input credit cannot be claimed, the tax does not disappear — it must be capitalised into the item's
value or expensed. `IneligibleITC` implements that redirection
(`india_compliance/gst_india/overrides/ineligible_itc.py:18-53`), with subclasses per document type
(`india_compliance/gst_india/overrides/ineligible_itc.py:317-486`).

The mechanism has four moving parts:

| Method | Effect |
|---|---|
| `update_item_ineligibility` (`ineligible_itc.py:75-97`) | decides, per item, whether ITC is blocked |
| `reverse_input_taxes_entry` (`ineligible_itc.py:101-134`) | reverses the input-tax GL leg |
| `make_gst_expense_entry` (`ineligible_itc.py:135-179`) | posts the tax to a GST expense account instead |
| `update_item_valuation_rate` / `update_asset_valuation_rate` (`ineligible_itc.py:291-312`) | capitalises the tax into stock or asset value |

So an ineligible tax becomes either **inventory cost** or **expense**, and for a fixed asset it raises the
asset's valuation rate — which lands directly on the asset cost machinery documented in
[doc 41 §8.2](41-asset-identity-acquisition-and-finance-books.md). `reverse_stock_adjustment_entry`
(`ineligible_itc.py:180-243`) handles the stock-valuation consequence.

`is_eligibility_restricted_due_to_pos` adds a place-of-supply-driven restriction
(`ineligible_itc.py:313-316`): credit can be blocked because of *where* the supply happened, not what it was.

This is the sharpest coupling in the tranche: **a tax determination outcome changes inventory valuation and
asset cost.** Under our design that must flow through the existing ledgers as typed facts — a `stock_move`
value component and an `asset_cost_event` — rather than by patching a valuation rate in place.

> **Invariant G13 — blocked credit is a typed cost allocation.** When input tax is not creditable, the
> determination records the blocking reason and the destination (inventory valuation, asset cost, or a named
> expense account) as an explicit allocation fact. Inventory and asset consequences are ordinary
> `stock_move` value components and `asset_cost_event` rows carrying the determination identity — never an
> in-place edit of a valuation rate.

---

## 6. Item-level distribution

`ItemGSTDetails` (`india_compliance/gst_india/overrides/transaction.py:1104-1391`) distributes document-level
tax rows down to item rows, and `ItemGSTTreatment`
(`india_compliance/gst_india/overrides/transaction.py:1392-1472`) assigns each item its treatment
(`Taxable`, `Zero-Rated`, `Nil-Rated`, `Exempted`, `Non-GST`).

`update_taxable_values` computes the taxable base per item
(`india_compliance/gst_india/overrides/transaction.py:75-139`), and `validate_item_wise_tax_detail` checks the
per-item breakdown against the document total
(`india_compliance/gst_india/overrides/transaction.py:140-161`). `CustomTaxController` in
`india_compliance/gst_india/utils/taxes_controller.py:102-283` maintains item-wise tax rates for the
documents ERPNext's own controller does not cover.

This is the same allocation problem doc 05 §5.5 solved for ordinary taxes with error diffusion, and the same
exactness requirement applies: **item-wise GST must sum to document GST exactly**, because GSTR-1 reports at
item/HSN granularity while the invoice reports at document level (doc 48).

---

## 7. Gates that are not about arithmetic

`validate_transaction` also enforces conditions that protect the return-filing cycle
(`india_compliance/gst_india/overrides/transaction.py:1615-1687`):

- **`validate_backdated_transaction`** refuses submission or cancellation when GSTR-1 has already been filed
  up to that date (`india_compliance/gst_india/overrides/transaction.py:626-635`, using
  `restrict_gstr_1_transaction_for` from
  `india_compliance/gst_india/doctype/gst_settings/gst_settings.py:567-601`). This is a genuine period-close
  mechanism, parallel to the accounting period control in doc 07 — and it is enforced **per document**, from
  a settings lookup, rather than by a period record.
- **`validate_mandatory_fields`** (`india_compliance/gst_india/overrides/transaction.py:185-208`) and
  **`validate_company_address_field`** (`india_compliance/gst_india/overrides/transaction.py:1553-1573`).
- **`validate_hsn_codes`** honours a settings flag and a configured valid length
  (`india_compliance/gst_india/overrides/transaction.py:636-644`,
  `india_compliance/gst_india/overrides/transaction.py:650-701`) — so classification completeness is
  optional.
- **`validate_overseas_gst_category`** (`india_compliance/gst_india/overrides/transaction.py:702-718`) and
  **`validate_ecommerce_gstin`** (`india_compliance/gst_india/overrides/transaction.py:1719-1725`).
- **`get_regional_round_off_accounts`** (`india_compliance/gst_india/overrides/transaction.py:719-737`) — the
  one place the app does use ERPNext's `@allow_regional` seam.

`reset_gst_details_on_cross_mapping` clears GST details when a document is mapped across a GSTIN boundary
(`india_compliance/gst_india/overrides/transaction.py:1797-1837`), and `ignore_gst_validations`
(`india_compliance/gst_india/overrides/transaction.py:1838-1842`) is a global escape hatch that disables the
entire battery.

> **Invariant G14 — statutory period control is a period record.** A filed return closes a period for a
> registration, recorded as an immutable filing fact with its coverage range. Posting, amending or reversing
> a document inside a closed period is refused by the same period-control mechanism that governs accounting
> periods, evaluated per posting date and registration — not by a per-document settings lookup, and with no
> global bypass flag.

---

## 8. Evidence versus projection

| Representation | Classification |
|---|---|
| `place_of_supply` on the document | **composite display string**, sliced for its code |
| `gst_category`, `gstin` fields on the document | snapshot copied from party master at determination time |
| `is_inter_state` (recomputed) | derived on demand, never stored as a decision |
| tax rows with `gst_tax_type` | typed component amounts — the closest thing to a determination fact |
| `gst_tax_type = None` for unmapped accounts | untyped row, invisible to GST validation |
| item-wise tax detail | distribution of document tax, validated against the total |
| item `gst_treatment` | derived classification outcome |
| reverse-charge flag and RCM rows | typed liability direction |
| ineligible-ITC valuation rate change | **in-place mutation** of stock/asset valuation |
| GST expense GL entries | accounting evidence |
| transporter and address fields after submit | **mutable posted fields** |
| `gstr_1_filed_upto` in settings | period-close authority held in a Single |

There is no record anywhere of *which rule version* produced a determination: no rate-schedule identity, no
engine version, no place-of-supply provenance. Re-running determination on an old document with today's
configuration is the only way to explain it, and that answer may differ from what was posted.

---

## 9. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md) and doc 45 §8. Money `numeric(19,4)`; rates
`numeric(9,6)`; `company_id`-scoped with RLS and `FORCE RLS`; stable enum codes; append-only facts.

```sql
tax_determination(id, company_id, source_doc_type text, source_doc_id bigint,
    jurisdiction_revision_id, engine_version varchar(64), determined_at timestamptz,
    supply_type supply_type_enum /*intra|inter|import|export|export_without_payment|exempt|nil|non_taxable*/,
    liability_direction liability_direction_enum /*forward|reverse|refund|zero_rated*/,
    place_of_supply_area_id bigint NOT NULL,
    place_of_supply_basis pos_basis_enum /*party_registration|shipping_address|company_registration|explicit_override|statutory_default*/,
    source_area_id bigint NOT NULL, source_basis pos_basis_enum,
    supplier_registration_snapshot_id, customer_registration_snapshot_id,
    is_self_supply bool NOT NULL DEFAULT false,
    command_receipt_id, reverses_determination_id bigint NULL)
   UNIQUE (company_id, source_doc_type, source_doc_id) WHERE reverses_determination_id IS NULL
   CHECK (NOT is_self_supply)          -- a supply to oneself is refused, not zero-taxed
   -- append-only; a correction is a reversal + new determination

tax_determination_line(id, company_id, tax_determination_id, source_line_id bigint,
    classification_revision_id, tax_rate_revision_id, tax_treatment_id,
    taxable_amount numeric(19,4), ordinal integer)
   UNIQUE (company_id, tax_determination_id, source_line_id)
   CHECK (taxable_amount >= 0)

tax_determination_component(id, company_id, tax_determination_line_id,
    tax_component_id, component_role component_role_enum,
    rate numeric(9,6), amount numeric(19,4), account_id,
    is_residual bool NOT NULL DEFAULT false)
   UNIQUE (company_id, tax_determination_line_id, tax_component_id, component_role)
   -- deferred triggers:
   --   component ∈ applicable set for (jurisdiction, supply_type, direction, role)
   --   Σ amount per line = round(taxable_amount × Σ rate) with ONE residual component
   --   Σ amount per component across lines = the document's component total, EXACTLY
   --   forward + reverse amounts cancel exactly at the document's money precision

tax_credit_block(id, company_id, tax_determination_line_id, tax_component_id,
    reason_code credit_block_reason_enum /*place_of_supply|blocked_category|personal_use|
                                          exempt_output|composition|statutory_list*/,
    destination credit_destination_enum /*inventory_valuation|asset_cost|named_expense*/,
    amount numeric(19,4), stock_move_id bigint NULL, asset_cost_event_id bigint NULL,
    expense_account_id bigint NULL, voucher_id bigint NOT NULL REFERENCES voucher(id))
   UNIQUE (company_id, tax_determination_line_id, tax_component_id)
   CHECK (num_nonnulls(stock_move_id, asset_cost_event_id, expense_account_id) = 1)

statutory_filing(id, company_id, tax_registration_id, return_type text,
    period_start date, period_end date, filed_at timestamptz, acknowledgement_no text,
    voucher_id bigint NULL, command_receipt_id, reverses_filing_id bigint NULL)
   UNIQUE (company_id, tax_registration_id, return_type, period_start)
   EXCLUDE USING gist (company_id WITH =, tax_registration_id WITH =, return_type WITH =,
      daterange(period_start, period_end, '[]') WITH &&)
   -- period control: posting/amending inside a filed period is refused by trigger, no bypass flag
```

**Write ordering** for a taxable document, inside the existing posting funnel (doc 08 §8.4):

```text
1  claim command idempotency
2  guard accounting period AND statutory_filing period for the registration
3  capture tax_registration_snapshot for both parties (blocking; refuse if stale beyond policy)
4  resolve jurisdiction revision, place of supply + basis, source area + basis, supply type
5  resolve classification and rate revisions per line
6  compute components by pure function; assign the residual deterministically
7  insert tax_determination + lines + components
8  insert tax_credit_block rows and their stock_move value components / asset_cost_event rows
9  insert voucher + gl_entry from the component amounts
10 run deferred checks: applicability, per-line sum, per-component total, forward/reverse cancellation
11 outbox ; commit ; project registers and return working sets
```

Determination is computed **before** any GL row exists and is never recomputed for a posted document. A
change of address, transporter or party master cannot alter it; only a reversal and a new determination can.

> **Invariant G15 — relational determination integrity.** Unique, foreign-key, check and exclusion
> constraints enforce one unreversed determination per document, one component row per line and role, exact
> per-line and per-component sums with a single designated residual, applicability of every component, and
> non-overlapping statutory filing periods per registration and return type.

---

## 10. Defects, races and unfinished paths

1. **Place of supply is a display string whose first two characters are statutory.**
   (`india_compliance/gst_india/overrides/transaction.py:545-592`).
2. **A missing place of supply silently means intra-state**, selecting CGST+SGST
   (`india_compliance/gst_india/overrides/transaction.py:577-592`).
3. **Source state is recovered by slicing a registration number**, with `"96"` as a magic literal for
   outside-jurisdiction (`india_compliance/gst_india/overrides/transaction.py:593-625`).
4. **Unregistered purchase falls back to `company_gstin`**, converting an inter-state supply to intra-state
   when the address branch does not catch it
   (`india_compliance/gst_india/overrides/transaction.py:593-625`).
5. **The reverse-charge balance uses a hard-coded 2-decimal tolerance**, not the document's precision
   (`india_compliance/gst_india/overrides/transaction.py:996-1061`).
6. **Two statutory balance rules use different precision policies** — hard-coded `2` for reverse charge,
   document precision for refunds
   (`india_compliance/gst_india/overrides/transaction.py:1062-1099`).
7. **An unmapped account makes a tax row invisible** to GST validation rather than invalid
   (`india_compliance/gst_india/overrides/transaction.py:272-282`).
8. **GST fields are mutable after submission**, including address-derived ones
   (`india_compliance/gst_india/overrides/transaction.py:1861-1887`,
   `india_compliance/gst_india/overrides/transaction.py:1913-1966`).
9. **Ineligible ITC mutates valuation rates in place**, including asset valuation
   (`india_compliance/gst_india/overrides/ineligible_itc.py:291-312`).
10. **Classification validation is optional**, gated by a settings flag and a configurable length
    (`india_compliance/gst_india/overrides/transaction.py:636-644`).
11. **A global bypass disables the whole battery.**
    (`india_compliance/gst_india/overrides/transaction.py:1838-1842`).
12. **Statutory period control lives in a Single** and is consulted per document
    (`india_compliance/gst_india/doctype/gst_settings/gst_settings.py:567-601`).
13. **No determination provenance is stored** — no rate-schedule identity, engine version, or
    place-of-supply basis (§8).
14. **Determination mutates the document then recomputes taxes**, so the inputs and the outputs occupy the
    same mutable fields (`india_compliance/gst_india/overrides/transaction.py:1592-1614`).

No deterministic lock or unique constraint was found around: registration snapshot read → document save;
`gstr_1_filed_upto` read → submit; or item-wise tax distribution → document total validation.

> **Invariant G16 — serializable determination.** Determination, credit-block allocation and statutory
> filing are bounded writes validated and inserted under deterministic locks (registration, period,
> document) with idempotency keys and database uniqueness. Concurrent commands may not produce two
> determinations for one document, nor post into a period being closed by a concurrent filing.

---

## 11. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Place of supply as a first-class field | **Adopt** | `place_of_supply_area_id`, a resolved code |
| Storing it as `"NN-State Name"` | **Reject** | area FK; labels rendered on read |
| Slicing GSTIN for the state code | **Change** | registration → area FK resolved once, recorded |
| `"96"` for outside-jurisdiction | **Change** | typed area with an `is_outside_jurisdiction` flag |
| SEZ always inter-state | **Adopt** | supply-type rule on the jurisdiction revision |
| Missing place of supply → intra-state | **Reject** | refusal |
| Doctype-specific source resolution | **Change** | one resolver, typed by transaction role |
| Intra/inter account filtering | **Adopt** | applicability derived from the component set |
| `gst_tax_type = None` for unmapped accounts | **Reject** | unmapped component account is an error |
| No GST when both GSTINs match | **Adopt** | `is_self_supply` refusal |
| Reverse-charge forward/booked cancellation | **Adopt** | exact cancellation as a deferred constraint |
| Hard-coded 2-decimal tolerance | **Reject** | document money precision, exact |
| Sign policy per row type, flipped for returns | **Adopt** | component role sign policy, direction-aware |
| Refund net-zero rule | **Adopt** | same, one precision policy for both rules |
| Export with / without payment of GST | **Adopt** | typed `liability_direction` |
| Reverse charge refused without recipient GSTIN | **Adopt** | constraint |
| Ineligible ITC redirection to cost/expense | **Adopt the concept** | `tax_credit_block` allocation fact |
| Patching valuation rate in place | **Reject** | `stock_move` value component / `asset_cost_event` |
| Place-of-supply-driven credit restriction | **Adopt** | typed `reason_code` |
| Item-wise distribution validated against the total | **Adopt and strengthen** | exact sum with one residual |
| GSTR-1-filed backdating restriction | **Adopt the intent** | `statutory_filing` period records |
| Period control held in a Single | **Reject** | filing facts with an exclusion constraint |
| Mutable GST fields after submit | **Reject** | immutable determination; correction is reversal + new |
| Cross-mapping resets GST details | **Adopt** | new determination on the target document |
| Global `ignore_gst_validations` | **Reject** | no bypass; exceptions are authorised, logged facts |
| `@allow_regional` round-off accounts | **Reject** | jurisdiction rule revision |
| Optional HSN validation | **Change** | classification completeness required per jurisdiction rule |

Invariants introduced here are **G9–G16**. Doc 47 continues at **G17** with e-invoice and e-way bill.

---

Cross-references: [doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) (registration,
components, classification), [doc 05](05-taxes-totals-and-pricing.md) (tax calculation and error-diffusion
allocation), [doc 28](28-tax-determination.md) (`Tax Category`/`Tax Rule` resolution GST rides on),
[doc 01](01-gl-posting-engine.md) (posting and balance exactness), [doc 02](02-stock-ledger-and-valuation.md)
and [doc 03](03-stock-gl-bridge.md) (valuation consequences of blocked credit),
[doc 07](07-period-close-and-opening-balances.md) (period control this parallels),
[doc 41](41-asset-identity-acquisition-and-finance-books.md) (asset cost events blocked credit must use),
and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md). Next: doc 47 — e-invoice and e-way bill as
external state machines.
