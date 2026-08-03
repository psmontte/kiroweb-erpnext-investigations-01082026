# 55 — Multi-Location, Branch and Segment Dimensions

> Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`, `frappe`
> `5da68e856ca7f036b20d2583167b9d00c4a8db56` and `india_compliance`
> `205c3de939bd99cc1df1e0d1cb76cff2e76eee55` (v17.0.0-dev).
> ERPNext citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext`; Frappe citations are
> prefixed `frappe/`; India Compliance citations are prefixed `india_compliance/`.

Doc [53](53-multi-company-intercompany-and-transfer-pricing.md) covered the company axis and
[54](54-multi-currency-layering.md) the currency axis. This document covers every **other** axis a real
deployment slices by: warehouse, branch, department, territory, project, cost centre and whatever the customer
invents.

The question that matters for Tranche G is narrow: **are these dimensions a reporting convenience, or can they
be a boundary?** Because a business that says "the Mumbai branch manager sees only Mumbai" is asking for the
second, and doc 52 established that only `company_id` is even a candidate.

There is a second question this document has to answer, inherited from Tranche F: **a GST registration is
per-state, not per-company** — so a company operating in three states files three returns. Doc 45's
`tax_registration` assumed that; this is where the dimension it hangs off gets defined.

Invariants continue from doc 54 at **T23**.

---

## 1. Two dimension systems, deliberately separate

ERPNext has **two** extensible dimension mechanisms, and they are not the same thing.

| | `Accounting Dimension` | `Inventory Dimension` |
|---|---|---|
| Applies to | GL-posting doctypes | stock-moving doctypes |
| Reaches | `GL Entry`, budgets, accounting documents | `Stock Ledger Entry`, stock documents |
| Mechanism | adds a Custom Field to every accounting doctype (`accounts/doctype/accounting_dimension/accounting_dimension.py:129-165`) | adds fields conditionally, with validation about where it may live (`stock/doctype/inventory_dimension/inventory_dimension.py:25-319`) |
| Extras | budget integration (`accounting_dimension.py:166-197`), mandatory-for-P&L/BS flags (`accounting_dimension.py:263-285`) | evaluated expressions per document (`inventory_dimension.py:354-384`) |

Both are **runtime DDL** — they create Custom Fields across doctypes when a dimension is defined. Doc 18 §4
established why that is unacceptable as our extension mechanism; doc 26 §4 traced the accounting side in detail.
What is new here is the *split*: a dimension that matters to both stock and accounting must be defined twice, in
two systems, with no constraint that the two definitions agree.

`Inventory Dimension` is the more carefully guarded of the two. It ships three named exceptions —
`DoNotChangeError`, `CanNotBeChildDoc`, `CanNotBeDefaultDimension`
(`stock/doctype/inventory_dimension/inventory_dimension.py:13-24`) — which is a good sign: the author enumerated
the ways a dimension can be wrong. It also supports **evaluated dimensions**, where the applicable value is
computed per document from an expression
(`stock/doctype/inventory_dimension/inventory_dimension.py:354-384`), and it can be deleted
(`stock/doctype/inventory_dimension/inventory_dimension.py:418-423`) — which raises the question of what happens
to the `Stock Ledger Entry` rows that carried it.

`get_dimension_with_children` resolves a dimension value's descendants
(`accounts/doctype/accounting_dimension/accounting_dimension.py:286-300`), so tree-shaped dimensions aggregate.
`disable_dimension` and `toggle_disabling`
(`accounts/doctype/accounting_dimension/accounting_dimension.py:219-245`) turn one off — again, without
addressing history.

> **Invariant T23 — a dimension is one definition, applied everywhere it is relevant.** A dimension is declared
> once as data, with its value domain, hierarchy, applicable object classes and effective period, and is applied
> identically to accounting, stock, production and quality facts. No dimension is defined twice in two
> subsystems, no dimension creates or destroys columns at runtime, and a dimension that has been used on a
> posted fact can be closed but never deleted or retrospectively disabled.

---

## 2. Dimension filters: allow, restrict, mandatory

`Accounting Dimension Filter` is the closest thing ERPNext has to dimension-based access control, and it is
worth being precise about what it does. `get_dimension_filter_map` builds a map keyed by
`(dimension_value, account)` (`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:72-108`),
and `build_map` records `allow_or_restrict` and `is_mandatory` per entry
(`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:109-115`).

So the semantics are:

- **allow / restrict**: this dimension value may or may not be used with this account;
- **mandatory**: a dimension value is required for this account.

That is a **validation** rule on what may be *written*, not a visibility rule on what may be *read*. It
constrains combinations at posting time. It does not stop the Mumbai branch manager from reading Delhi's rows —
nothing does, because reads are governed by §1 of doc 52.

`get_checks_for_pl_and_bs_accounts` supplies the mandatory-for-P&L and mandatory-for-balance-sheet flags
(`accounts/doctype/accounting_dimension/accounting_dimension.py:263-285`), which doc 41 §2 already showed being
consumed when depreciation journals copy dimensions from the asset.

> **Invariant T24 — dimensions constrain writes and may narrow reads, but never widen them.** Dimension rules
> are of two explicit kinds: a **write constraint** (a value is required, permitted or forbidden in combination
> with an account or object class) and a **read narrowing** applied *in addition to* company scope. A read
> narrowing may only subtract from what company scope already allows, and its absence narrows nothing —
> the company boundary is never reached through a dimension.

---

## 3. Warehouse: a tree that already carries a company

`Warehouse` is a nested set (`parent_warehouse`, `is_group`) that carries `company`
(`stock/doctype/warehouse/warehouse.py:30-60`), suffixes its name with the company abbreviation
(`stock/doctype/warehouse/warehouse.py:56-64`), and reads the company's `enable_perpetual_inventory` to decide
account behaviour (`stock/doctype/warehouse/warehouse.py:65-75`).

Two observations.

**The company is already on the location.** So the tenant boundary and the location dimension are not
independent — a warehouse belongs to exactly one company, which means location-scoped access is *expressible*
as a narrowing within a company rather than as a competing axis. That is the shape T24 formalises.

**`is_group` is inferred, not declared.** The controller flips it based on whether children exist
(`stock/doctype/warehouse/warehouse.py:138-161`):

```text
if children exist   → is_group = 1
if none             → is_group = 0
```

A structural property derived from current data rather than declared means a leaf silently becomes a group the
moment a child is added, and stock postings are only valid against leaves. Doc 16 §4 covered warehouse structure;
the isolation-relevant part is that the *shape* of the tree is mutable state.

`Branch`, `Department` and `Territory` exist as thin masters
(`setup/doctype/branch/branch.py`, `setup/doctype/department/department.py`,
`setup/doctype/territory/territory.py`) and become dimensions through §1's mechanism.

---

## 4. Segment reporting does not exist

A search for segment reporting returns nothing in an accounting sense. The matches are CRM's `Market Segment`
(`crm/doctype/market_segment/market_segment.py`) — a lead-qualification label in a module that is out of scope
(doc 15, Tranche D) — and `financial_report_engine.py`, where the word appears incidentally.

So: no operating segments, no segment disclosure, no reconciliation of segment totals to the entity total. A
group that must report by segment builds it in the report layer, per report, with no constraint that two reports
agree.

This is the sharpest of the three reporting-entity gaps. Consolidation *does* exist as reports (doc 53 §1) and a
translation residual *is* computed (doc 54 §4) — both incompletely. Segments have nothing at all. The pattern
across all three: **ERPNext models the transaction layer thoroughly, and the reporting-entity layer as report
output rather than as facts.**

---

## 5. The statutory seam: registration is per place, not per company

This is the finding that connects Tranche G back to Tranche F.

A GST registration is issued **per state**, and its first two characters *are* the state code (doc 45 §3.1). A
company operating in three states holds three GSTINs and files three sets of returns. In India Compliance, the
GSTIN therefore lives on the **`Address`**, not on the Company —
`update_party_gstin_and_gst_category` reacts to an address's `gstin` changing, derives the PAN from characters
3–12, and propagates to the party
(`india_compliance/gst_india/overrides/address.py:13-50`).

So the statutory registration axis is **the address**, which is neither an accounting dimension nor an inventory
dimension nor the company. Three consequences:

1. `place_of_supply` and the source state code are derived from addresses and GSTINs (doc 46 §2), so the
   determination axis is the address too;
2. doc 48's `return_period` is keyed by `tax_registration_id` — i.e. **per registration, not per company** —
   which is correct, and only makes sense if registration is a modelled dimension; and
3. a company's return obligations are *plural*, so "close the period" is per registration.

Doc 45 §8's `tax_registration` already carries `tax_area_id`. What this document adds is the requirement that
**the registration is resolvable from the location dimension of the transaction**, not guessed from a party
address at posting time.

> **Invariant T25 — statutory registration is a dimension of place, resolved not inferred.** Each registration
> is bound to a jurisdiction area and to the operating locations it covers. A transaction resolves its
> registration deterministically from its location dimension (establishment, warehouse or branch), records
> which registration it resolved and by which rule, and period control applies **per registration**. A company
> with several registrations has several independent statutory periods.

---

## 6. Evidence versus projection

| Representation | Classification |
|---|---|
| `Accounting Dimension` definition | configuration that performs **runtime DDL** |
| `Inventory Dimension` definition | the same, for stock, with better guards |
| the Custom Fields both create | runtime metadata (doc 18 §4) |
| dimension value on `GL Entry` / `Stock Ledger Entry` | the dimension fact — durable |
| `Accounting Dimension Filter` map | **write** constraint: allow / restrict / mandatory |
| mandatory-for-P&L / BS flags | write constraint per account class |
| `Warehouse.company` | the tenant link, already present on the location |
| `Warehouse.is_group` | **inferred** from whether children exist |
| `Branch`, `Department`, `Territory` | thin masters promoted to dimensions |
| evaluated inventory dimension | expression computed per document |
| `disable_dimension` / `delete_dimension` | configuration change with no stated effect on history |
| GSTIN on `Address` | the statutory registration axis |
| operating segments, segment disclosure | **do not exist** |

Nothing in the left column is a read boundary. Every dimension is either a write constraint or a label on a
fact.

---

## 7. Target design

Extends [`FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md), doc 52 §8 and doc 53 §8. Dimensions are
company-scoped; the company boundary is unaffected by them (T24).

```sql
dimension(id, company_id, code, name,
    value_domain dimension_domain_enum /*hierarchical|flat|external_reference*/,
    applies_to text[] NOT NULL,           -- object classes: gl_entry, stock_move, work_order, …
    is_required_for text[] NULL,          -- object classes where a value is mandatory
    effective_from date, effective_to date NULL, state revision_state_enum)
   UNIQUE (company_id, code)
   -- ONE definition, applied to accounting AND stock AND production, replacing the §1 split.
   -- No DDL: dimension values live in dimension_value and are referenced, not columned.

dimension_value(id, company_id, dimension_id, code, name, parent_id bigint NULL,
    effective_from date, effective_to date NULL, state dimension_value_state_enum
        /*active|closed*/)
   UNIQUE (company_id, dimension_id, code)
   CHECK (parent_id IS NULL OR parent_id <> id)
   -- `closed`, never deleted: a value used on a posted fact must remain resolvable forever

fact_dimension(id, company_id, fact_class text NOT NULL, fact_id bigint NOT NULL,
    dimension_id, dimension_value_id, ordinal integer)
   PRIMARY KEY (company_id, fact_class, fact_id, dimension_id)
   -- one narrow table instead of a Custom Field per dimension per doctype

dimension_write_rule(id, company_id, dimension_id, object_class text,
    account_id bigint NULL, rule_kind write_rule_enum /*require|permit|forbid*/,
    dimension_value_id bigint NULL, effective_from date, effective_to date NULL)
   UNIQUE (company_id, dimension_id, object_class, account_id, dimension_value_id, effective_from)
      NULLS NOT DISTINCT
   -- adopts allow / restrict / mandatory as explicit typed rules

dimension_read_narrowing(id, company_id, principal_id, dimension_id, dimension_value_id,
    includes_descendants bool NOT NULL DEFAULT true,
    granted_at, granted_by, expires_at timestamptz NULL, revoked_at timestamptz NULL)
   UNIQUE (company_id, principal_id, dimension_id, dimension_value_id) WHERE revoked_at IS NULL
   -- compiled into an ADDITIONAL RLS predicate. It can only subtract from company scope (T24).
   -- Absence narrows nothing — the OPPOSITE polarity from doc 51 §2.1's user permissions, because
   -- the company boundary is already closed underneath it.

operating_location(id, company_id, code, name, parent_id bigint NULL,
    location_kind location_kind_enum /*establishment|warehouse|branch|site|office*/,
    tax_area_id bigint NULL, address_id bigint NULL,
    is_postable bool NOT NULL,            -- DECLARED, never inferred from whether children exist
    effective_from date, effective_to date NULL)
   UNIQUE (company_id, code)
   CHECK (parent_id IS NULL OR parent_id <> id)
   -- one place hierarchy; warehouses, branches and establishments are kinds of it, not parallel trees

location_registration(id, company_id, operating_location_id, tax_registration_id,
    effective_from date NOT NULL, effective_to date NULL)
   UNIQUE (company_id, operating_location_id, tax_registration_id, effective_from)
   EXCLUDE USING gist (company_id WITH =, operating_location_id WITH =,
      daterange(effective_from, effective_to, '[)') WITH &&)
   -- T25: a transaction resolves ONE registration from its location, deterministically

reporting_segment(id, company_id_or_group, code, name,
    segment_basis segment_basis_enum /*business_line|geography|legal_entity|customer_class*/,
    effective_from date, effective_to date NULL)
segment_mapping(id, company_id, reporting_segment_id, dimension_id, dimension_value_id,
    effective_from date, effective_to date NULL)
   UNIQUE (company_id, reporting_segment_id, dimension_id, dimension_value_id, effective_from)
   -- deferred: for a given period and dimension, mappings PARTITION the value set — no value
   -- belongs to two segments, and unmapped values fall to an explicit `unallocated` segment,
   -- so segment totals reconcile to the entity total by construction (§4's gap)
```

### 7.1 How this composes with the boundary

```text
company scope        RLS: company_id = auth.current_company()          ← always, doc 50 §6.1
dimension narrowing  additional RLS from dimension_read_narrowing      ← subtracts only
write rules          dimension_write_rule: require / permit / forbid   ← at posting
registration         location_registration → tax_registration          ← per T25, drives return periods
segment              segment_mapping partitions dimension values       ← reporting only, reconciles
```

The polarity difference from doc 51 is deliberate and worth stating plainly. User permissions in ERPNext
**fail open** — no rows means unrestricted — and that is fatal because they are the *only* barrier.
`dimension_read_narrowing` also does nothing when absent, and that is *safe*, because the company boundary is
already closed underneath it. Fail-open is acceptable for a second layer and never for the first.

> **Invariant T26 — segment reporting reconciles to the entity by construction.** Segment mappings partition
> a dimension's value set for any period, with unmapped values assigned to an explicit unallocated segment, so
> the sum of segment results equals the entity result exactly. A segment is a mapping over dimensions, never a
> parallel set of numbers maintained by a report.

---

## 8. Defects and risks

1. **Two dimension systems** with no constraint that a shared dimension is defined consistently in both
   (`accounts/doctype/accounting_dimension/accounting_dimension.py:129-165`,
   `stock/doctype/inventory_dimension/inventory_dimension.py:25-319`).
2. **Both perform runtime DDL**, creating Custom Fields across doctypes (doc 18 §4).
3. **Dimension deletion and disabling have no stated effect on posted history**
   (`accounts/doctype/accounting_dimension/accounting_dimension.py:198-245`,
   `stock/doctype/inventory_dimension/inventory_dimension.py:418-423`).
4. **`Warehouse.is_group` is inferred from whether children exist**, so tree shape is mutable state
   (`stock/doctype/warehouse/warehouse.py:138-161`).
5. **Dimension filters constrain writes only** — there is no read narrowing anywhere
   (`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:72-115`).
6. **No segment reporting exists** (§4).
7. **The statutory registration axis is the `Address`**, which is not a modelled dimension
   (`india_compliance/gst_india/overrides/address.py:13-50`).
8. **Evaluated inventory dimensions compute a value per document from an expression**, so the dimension on a
   fact depends on runtime evaluation
   (`stock/doctype/inventory_dimension/inventory_dimension.py:354-384`).
9. **Location trees are parallel** — `Warehouse`, `Branch`, `Department`, `Territory` and `Address` all carry
   place-like meaning with no single hierarchy.

Genuinely good, and adopted: `Inventory Dimension`'s three named exceptions and its explicit rules about where a
dimension may live (`stock/doctype/inventory_dimension/inventory_dimension.py:13-24`), the
allow/restrict/mandatory vocabulary
(`accounts/doctype/accounting_dimension_filter/accounting_dimension_filter.py:109-115`), mandatory-for-P&L/BS
flags (`accounts/doctype/accounting_dimension/accounting_dimension.py:263-285`), descendant resolution for
hierarchical dimensions (`accounts/doctype/accounting_dimension/accounting_dimension.py:286-300`), and the fact
that `Warehouse` already carries its company
(`stock/doctype/warehouse/warehouse.py:30-60`) — which is what makes location a narrowing rather than a
competing axis.

---

## 9. Adopt / Change / Reject

| Mechanism | Decision | Ours |
|---|---|---|
| Extensible accounting dimensions | **Adopt the concept** | one `dimension` definition, data not DDL |
| Separate inventory dimensions | **Reject the split** | `applies_to[]` covers stock, accounting, production, quality |
| Runtime Custom Field creation | **Reject** | `fact_dimension` rows; no schema change to add a dimension |
| `DoNotChangeError` / `CanNotBeChildDoc` / `CanNotBeDefaultDimension` | **Adopt** | the same refusals as constraints |
| Evaluated dimension expressions | **Change** | resolved by a validated rule with the result stored on the fact |
| `disable_dimension` / `delete_dimension` | **Reject** | `closed` state; a used value is never deleted |
| Descendant resolution for trees | **Adopt** | `parent_id` + recursive CTE |
| allow / restrict / mandatory filters | **Adopt** | `dimension_write_rule` with typed `require`/`permit`/`forbid` |
| Mandatory-for-P&L / BS | **Adopt** | `is_required_for[]` per object class |
| Dimensions as read boundaries | **Change** | `dimension_read_narrowing`, additive-only, on top of company RLS |
| `Warehouse.company` | **Adopt** | `operating_location.company_id` |
| `is_group` inferred from children | **Reject** | `is_postable` declared |
| Parallel place trees | **Change** | one `operating_location` hierarchy with `location_kind` |
| GSTIN on `Address` | **Change** | `location_registration` binding registration to place |
| Registration implicitly per company | **Reject** | per registration, with its own return periods (T25) |
| No segment reporting | **Reject** | `reporting_segment` + partitioning `segment_mapping` |
| Segment numbers maintained per report | **Reject** | mappings over dimensions, reconciling by construction |

Invariants introduced here are **T23–T26**. Doc 56 continues at **T27** with consolidation and group reporting —
which now has its three missing inputs: a group structure (doc 53), translated balances (doc 54) and a
reconciling segment axis (this document).

---

Cross-references: [doc 26](26-journal-entry-chart-of-accounts-dimensions.md) (the accounting-dimension mechanism
in detail), [doc 18](18-metadata-and-runtime-ddl.md) (runtime DDL, the mechanism both systems use and we
reject), [doc 16](16-stock-reservation-picking-warehouse.md) (warehouse structure),
[doc 27](27-remaining-stock-documents.md) (inventory dimensions in stock documents),
[doc 45](45-gst-registration-settings-hsn-and-tax-structure.md) and
[doc 46](46-gst-place-of-supply-and-component-determination.md) (registration and place of supply — the seam
in §5), [doc 48](48-gst-returns-reconciliation-and-imports.md) (`return_period` per registration),
[doc 51](51-permission-model-end-to-end.md) and [doc 52](52-tenant-isolation-and-rls-under-attack.md) (why a
dimension may narrow but never widen), and [`../design/FINAL-SCHEMA.md`](../design/FINAL-SCHEMA.md).
Next: doc 56 — consolidation and group reporting.
