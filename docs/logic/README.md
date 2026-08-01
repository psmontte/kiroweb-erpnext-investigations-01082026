# Business logic of the accounting + trade/inventory engine

What the code actually does, function by function, so we can reimplement it deliberately.

> **Looking for a flow rather than a subsystem?** See
> **[../scenarios/](../scenarios/README.md)** — Sales Order → Delivery Note → Sales Invoice,
> payments against invoices, and Purchase Order → Receipt → Invoice, each traced end to end with
> worked numbers and every table write in order.

## Source anchor

Everything here was read from source at these exact commits. **Line numbers only mean anything
against these commits** — re-verify after a pull.

| App | Version | Commit | Date |
|---|---|---|---|
| `erpnext` | `17.0.0-dev` | `ceefd4add77715d2762c19db337fb83e28a477de` | 2026-08-01 |
| `frappe` | `17.0.0-dev` | `5da68e856ca7f036b20d2583167b9d00c4a8db56` | 2026-07-31 |

**Important:** v17 is mid-refactor. Logic that older ERPNext tutorials place in
`controllers/accounts_controller.py` has been extracted into service modules:

```
erpnext/accounts/services/   base_gl_composer.py  gl_validator.py  taxes.py  advances.py
                             exchange_gain_loss.py  payment_schedule.py  billing_validation.py
                             internal_transfer.py  deferred_accounting.py  party_validation.py
erpnext/stock/services/      base_stock_gl_composer.py  stock_ledger_service.py
                             serial_batch_bundle_service.py  internal_transfer.py
<doctype>/services/          gl_composer.py, status.py, billing_status.py, ...
```

Notably: `AccountsController` has **no** `make_gl_entries` any more (each voucher defines its own,
delegating to a composer), and per-voucher GL rules live in `<doctype>/services/gl_composer.py`.

## Reading order

| Read | File | Covers |
|---|---|---|
| 1 | [01-gl-posting-engine.md](01-gl-posting-engine.md) | how a document becomes balanced GL rows: gl_map pipeline, merge, sign normalisation, round-off, validation gates, reversal, balance reads |
| 2 | [02-stock-ledger-and-valuation.md](02-stock-ledger-and-valuation.md) | the hardest part: SLE ordering, FIFO/LIFO/moving-average/standard-cost, `stock_value_difference`, backdating and the repost engine, negative stock, batch/serial valuation, Bin |
| 3 | [03-stock-gl-bridge.md](03-stock-gl-bridge.md) | how inventory valuation and the ledger stay reconciled; per-document debit/credit tables; landed cost; drift detection |
| 4 | [04-ar-ap-and-settlement.md](04-ar-ap-and-settlement.md) | payment subledger, outstanding computation, allocation, advances, reconciliation, FX gain/loss, ageing, credit limit |
| 5 | [05-taxes-totals-and-pricing.md](05-taxes-totals-and-pricing.md) | the totals pipeline, all charge types, inclusive-tax back-calculation, discounts, rounding, pricing rules, payment schedule, withholding |
| 6 | [06-lifecycle-status-and-returns.md](06-lifecycle-status-and-returns.md) | draft/submit/cancel, fulfilment roll-ups and `per_*`, tolerances, returns, amendment, closed/hold, locking |
| 7 | [07-period-close-and-opening-balances.md](07-period-close-and-opening-balances.md) | period closing voucher, closing-balance snapshots, freeze/period gates, fiscal years, opening balances (AR/AP/stock), FX revaluation, report reads |
| 8 | [08-our-implementation-spec.md](08-our-implementation-spec.md) | **the deliverable**: invariants to enforce, what we keep/change, decisions taken, and the provisional build spec (parked — see [../INVESTIGATION-PLAN.md](../INVESTIGATION-PLAN.md)) |
| 26 | [26-journal-entry-chart-of-accounts-dimensions.md](26-journal-entry-chart-of-accounts-dimensions.md) | the structures that define *where* posting happens: `Account` as a nested set with 14 validations, `Cost Center`, the **runtime-DDL dimension mechanism** (`Accounting Dimension` / `Inventory Dimension`), and `Journal Entry` — 16 voucher types in one table, with a **documented balancing exemption** |

### Tranche A — deep dives (accounts + trade/inventory remainder)

| Read | File | Covers |
|---|---|---|
| 9 | [09-lifecycle-reversals-deletions.md](09-lifecycle-reversals-deletions.md) | the canonical `docstatus` state machine, hook ordering, **why ERPNext has no approval state**, submit/cancel/amend/delete/rename, and our `draft → pending_approval → approved → posted → reversed` model |
| 10 | [10-fulfilment-engine.md](10-fulfilment-engine.md) | `StatusUpdater` config-driven counters, `Σ LEAST(achieved, ordered)/Σ ordered`, over-delivery allowance, the lost-update race — and our `doc_link` + `fulfilment_line`/`fulfilment_doc` views |
| 11 | [11-advances-and-payment-allocation.md](11-advances-and-payment-allocation.md) | the **five** representations of "money applied to an obligation", `allocate_amount_to_references` in full, `reconcile_against_document`'s cancel/split/resubmit, and our insert-only `settlement` table |
| 12 | [12-budgets-deferrals-cost-center-allocation.md](12-budgets-deferrals-cost-center-allocation.md) | budget check as an unlocked `SUM`, deferred revenue state inferred from GL postings, cost-centre split rounding — and our commitment ledger + stored deferral schedule + exact-rational allocation |
| 13 | [13-pos-and-retail.md](13-pos-and-retail.md) | POS Invoice posting **no** GL/stock, availability as a live query, what consolidation destroys, session control — and our "POS sales are ordinary sales" model |
| 14 | [14-banking-and-collections.md](14-banking-and-collections.md) | `Bank Transaction` never posting GL, `clearance_date` as a scalar, `rank = 1 + three booleans`, dunning's `Data`-typed FKs — and our `bank_statement_line`/`bank_match` + suspense-account model |
| 15 | [15-intercompany-and-history-rewriting.md](15-intercompany-and-history-rewriting.md) | inter-company mirroring by two cross-pointing columns, and the three repost subsystems + unreconcile that exist only because derived state is stored |
| 16 | [16-stock-reservation-picking-warehouse.md](16-stock-reservation-picking-warehouse.md) | reservation correctness that **depends on the database engine** (with the source's own comments), pick allocation locking, `Bin`'s twelve caches, nested-set warehouses |
| 17 | [17-item-uom-variants-batch-reorder.md](17-item-uom-variants-batch-reorder.md) | item identity, `Bin.stock_uom` rewriting, variants with no uniqueness constraint, `Item Price` with no overlap detection, the reorder rollup bug, FEFO |

### Tranche E — platform mechanics (what we must build ourselves)

| Read | File | Covers |
|---|---|---|
| 18 | [18-metadata-and-runtime-ddl.md](18-metadata-and-runtime-ddl.md) | **the schema is data**: `DocType`/`DocField`/`Meta` assembly, `ALTER TABLE` on user save, silent blank→0 coercion, orphaned columns, Singles as untyped global settings — and our migrations + dimension slots + `setting_def` |
| 19 | [19-permissions-and-access-control.md](19-permissions-and-access-control.md) | six composed mechanisms, all application-level; the `if_owner` collapse; SQL from hooks and DB rows spliced into `WHERE`; eight bypass routes — and our RLS + grant model |
| 20 | [20-naming-identity-and-audit-trail.md](20-naming-identity-and-audit-trail.md) | eleven naming strategies, the `Series` counter, counter reversion by character offset, `Version` diffs that miss every `db_set` — and our `uuid` + `numbering_rule` + trigger-written audit |
| 21 | [21-extensibility-hooks-and-regional.md](21-extensibility-hooks-and-regional.md) | hooks as module-namespace introspection, install-order precedence, `doc_events["*"]`, `@allow_regional` taking the region from the **session** — and our typed `domain_event` + `tax_regime` data + `company_extension` |
| 22 | [22-background-jobs-scheduling-and-locking.md](22-background-jobs-scheduling-and-locking.md) | RQ without idempotency, a live scheduler bug (`maintenance_offset` computed then discarded), "weak" file locks used for GL rewrites — and our `job`/`schedule` tables + row locks in triggers |
| 23 | [23-migrations-and-patches.md](23-migrations-and-patches.md) | no schema migration at all: JSON reconciliation + `exec`'d patch strings, `skip_failing` reporting success, no rollback — and our checksummed transactional migrations |
| 24 | [24-reporting-framework.md](24-reporting-framework.md) | SQL and Python stored in table rows, post-hoc Python row filtering, **aggregates computed before permission filtering** — and our generated queries over RLS-bearing views |
| 25 | [25-our-platform-spec.md](25-our-platform-spec.md) | **the Tranche E deliverable**: build/buy/drop per capability, the four-layer rule, ten requirements on the orchestration engine, honest cost of leaving Frappe |

Consolidated target schema: **[../design/FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md)** —
finalised tables, data flow, business rules, lifecycle state machine, fulfilment views,
settlement model, and the invariant register (F1–U1).

## Verifying the citations

Line numbers drift with every upstream commit. `tools/verify_refs.py` extracts every
`file.py:NNN` citation from these docs, resolves it against the source tree, and reports the
enclosing `def`/`class`:

```bash
python3 tools/verify_refs.py --docs docs/logic \
  --app erpnext=/path/to/erpnext/erpnext \
  --app frappe=/path/to/frappe/frappe --strict-names
```

Last run against the anchor commits: **~600 citations, 0 unresolved paths, 0 out of range**
(advisory name notes only — those lines mention a symbol defined elsewhere in the same file,
which is intentional). Frappe-side citations are prefixed `frappe/`.

## Conventions used in these docs

- `accounts/general_ledger.py:120-140` — path relative to `erpnext/` (or `frappe/` where stated) at the anchor commit.
- **Invariant** blocks are things the system depends on; break one and the books stop balancing.
- **Ours** blocks state what we do instead, and why.
- Amounts: "base" = company currency, "account currency" = the ledger account's own currency,
  "transaction currency" = the document's currency.

## One-paragraph summary of the whole engine

A user edits a **document**. On save, a calculation pipeline derives every monetary field
(`taxes_and_totals.py`) and a payment schedule. On **submit**, the document produces two kinds of
immutable rows: **stock ledger entries** (quantity + valuation state per item+warehouse) and
**GL entries** (balanced double-entry rows). Stock rows are produced first, because the GL amount
for inventory is read back *from* the stock rows (`stock_value_difference`) — that single
back-reference is what keeps inventory and accounting reconciled. Receivable/payable GL rows are
mirrored into a **payment subledger** so "what is still unpaid" is one indexed aggregate rather than
a ledger scan. Everything downstream (status, fulfilment percentages, ageing, balances) is *derived*
from those rows, and every derivation is a full recompute rather than an incremental delta — which
is what makes reposting, cancellation and reconciliation idempotent.
