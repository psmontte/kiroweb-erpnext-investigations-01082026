# Scenario walkthroughs

`docs/logic/` is organised **by subsystem** — the GL engine, the stock ledger, the fulfilment
engine, and so on. That is the right shape for a reference, and the wrong shape for answering
"what actually happens when I ship an order and then invoice it?"

These documents are organised **by business flow**. Each one traces a single realistic scenario end
to end with worked numbers, and shows:

1. **every table written, in order**, with the exact values,
2. **the ordering dependencies** between those writes and why they exist,
3. **what ERPNext does** vs **what our design does**, side by side,
4. **the invariants** the scenario exercises.

Deliberately messy cases — partial delivery, partial billing, disputes, returns, part payment,
over-payment, advances, un-allocation, landed cost after the fact — because the clean case never
reveals the design.

## Source anchor

| App | Version | Commit |
|---|---|---|
| `erpnext` | `17.0.0-dev` | `ceefd4add77715d2762c19db337fb83e28a477de` |
| `frappe` | `17.0.0-dev` | `5da68e856ca7f036b20d2583167b9d00c4a8db56` |

Citations are `path:line` and are verified mechanically by `tools/verify_refs.py`.

## The scenarios

| # | File | Flow | The finding |
|---|---|---|---|
| **S01** | [S01-order-to-cash.md](S01-order-to-cash.md) | Sales Order → Delivery Note → Sales Invoice, with partial delivery, partial billing, a dispute, and a return | 15 ledger rows, ~30 cached-counter writes to already-submitted documents. The *ledger* work is small and correct; the *counter* work is large, unlocked, and is where every fulfilment bug lives |
| **S02** | [S02-payments-and-allocation.md](S02-payments-and-allocation.md) | Payment against invoice: exact, partial, multi-invoice with bank charge, credit-note offset, advance, un-allocation, over-payment | **Nine places record one fact.** Allocating a payment rewrites the payment's own child rows and deletes-and-rebuilds the payment ledger. A short payment silently consumes credit notes |
| **S03** | [S03-procure-to-pay.md](S03-procure-to-pay.md) | Purchase Order → Purchase Receipt → Purchase Invoice, with rejection, landed cost, and a return | Structurally the mirror of S01, but **four real asymmetries**: `per_billed == 100` vs `>= 100`, three quantities per line, accrual on the receipt side only, and landed cost that rewrites history without bound |
| **S04** | [S04-stock-transfer-and-in-transit.md](S04-stock-transfer-and-in-transit.md) | Warehouse → warehouse transfer, direct and via a transit warehouse, with freight capitalised | The flow with **no party and no revenue** — the cleanest view of how valuation crosses warehouses. Transit-on-the-balance-sheet is genuinely good design; the inbound leg has **two builders with different partial-receipt behaviour**, and inter-company transfer is an entirely different mechanism |
| **S05** | [S05-period-close-and-opening-balances.md](S05-period-close-and-opening-balances.md) | Year-end: Accounting Period gate → Period Closing Voucher → closing snapshots → Stock Closing Entry; then opening balances for a new company | **Four independent mechanisms** control "is this date closed", with no shared model. **Two complete implementations** of year-end close chosen by a setting, with duplicated algorithms. Balance computation streams the year's GL and aggregates in Python. Opening-balance completeness is a convention, not a constraint |
| **S06** | [S06-multi-currency.md](S06-multi-currency.md) | Foreign-currency invoice → payment at a moved rate (realised FX) → partial payment → period-end revaluation (unrealised FX) → reversal | **Four** simultaneous currency dimensions. `get_exchange_rate` has five fallback layers and **three paths that return a rate of `0`**. Realised FX is a **separate journal** whose idempotency check is float equality. Reporting currency is *stored*, so closing-vs-average translation is not expressible. **8 vouchers for 2 sales** |
| **S07** | [S07-make-to-order-manufacturing.md](S07-make-to-order-manufacturing.md) | Sales Order → Production Plan → Work Order → Job Cards → WIP transfer → partial manufacture with loss/scrap → Delivery Note | WIP and the SLE→GL accounting core are coherent, but production ownership and progress are mutable projections. **One loss unit completes the Work Order while customer demand remains short**; partial separate consumption can suppress every Manufacture input |
| **S08** | [S08-supplier-subcontracting.md](S08-supplier-subcontracting.md) | Subcontract PO service → Subcontracting Order → RM reservation/send/return → partial Subcontracting Receipt → optional service Purchase Receipt | Supplier custody remains company inventory and the SLE→GL bridge stays exact, but **the same transfer and output consume 10/5 RM under BOM backflush versus 8/4 under transferred-material backflush**; the residual allocation is unlocked |
| **S09** | [S09-quality-gated-production-and-receipt.md](S09-quality-gated-production-and-receipt.md) | Multi-row Purchase Receipt → post-transaction inspection → Job Card operation gate → separately gated Manufacture Stock Entry | Inventory and GL remain balanced under Accepted and Warn, but **Warn posts draft/Rejected evidence as ordinary stock and one allow-after row returns from the entire receipt loop**; exact scoped release and durable exceptions are absent |
| **S10** | [S10-customer-owned-subcontracting-inward.md](S10-customer-owned-subcontracting-inward.md) | Subcontracted SO service → customer RM receipt/return → internal Work Order/Job Card/Manufacture → FG delivery/return → service + company-material Sales Invoice | Customer material moves through company warehouses at **zero company value but without an owner dimension**; gross delivery 10 and return 2 leaves net fulfilment 8 while status is Delivered |
| **S11** | [S11-asset-lifecycle.md](S11-asset-lifecycle.md) | Purchase Receipt → Asset + CWIP capitalisation → monthly depreciation → capitalised repair → partial sale (implicit split) → scrap | Every voucher balances and net assets are right, yet the **balance sheet is still wrong**: disposal removes `net_purchase_amount` and a *subtracted* accumulated depreciation, so a capitalised repair overstates Fixed Assets by 3,000.00 and Accumulated Depreciation by exactly the same amount — silently reclassifying cost as depreciation. Selling part of a multi-quantity asset creates a second asset and **cancels and re-posts submitted depreciation journals** |

## Reading order

Read **S01 → S02 → S03**. S02 assumes S01's closing position; S03 assumes both.
**S04–S06** are independent and can be read in any order. Read **S07 after S01** for the
make-to-order branch that produces stock before returning to S01's Delivery Note mechanics; its
manufacturing detail builds on docs 33–37. Read **S08 after S03** for the supplier-subcontracting branch
of procurement. Read **S09 after S03 and S07**: it joins a multi-row Purchase Receipt to operation and
finished-output release, and doc 39 supplies the complete quality model and M56–M69. Read **S10 after
S07**, then compare it with S08: S10 reuses ordinary internal manufacturing but reverses material
ownership, so the same Warehouse/SLE machinery must represent customer custody at zero company value.
Use doc 38 for both subcontracting branches.

If you only read one: **S02**. Payment allocation is the flow with the most moving parts and the
largest gap between what the system appears to do and what it does.

## How these relate to the subsystem docs

| Scenario stage | Subsystem reference |
|---|---|
| Totals, taxes, payment schedule | [doc 05](../logic/05-taxes-totals-and-pricing.md) |
| Draft → submit → cancel, approval, amend | [doc 09](../logic/09-lifecycle-reversals-deletions.md) |
| `delivered_qty` / `billed_amt` / `per_*` | [doc 10](../logic/10-fulfilment-engine.md) |
| Stock Ledger Entry, valuation, `stock_value_difference` | [doc 02](../logic/02-stock-ledger-and-valuation.md) |
| SLE → GL bridge, landed cost, drift | [doc 03](../logic/03-stock-gl-bridge.md) |
| GL posting pipeline, reversal | [doc 01](../logic/01-gl-posting-engine.md) |
| Payment Ledger, `outstanding_amount`, ageing | [doc 04](../logic/04-ar-ap-and-settlement.md) |
| Allocation algorithm, advances, reconciliation | [doc 11](../logic/11-advances-and-payment-allocation.md) |
| Returns and status | [doc 06](../logic/06-lifecycle-status-and-returns.md) |
| Reservation and picking | [doc 16](../logic/16-stock-reservation-picking-warehouse.md) |
| Repost subsystems | [doc 15](../logic/15-intercompany-and-history-rewriting.md) |
| `Journal Entry`, chart of accounts, dimensions | [doc 26](../logic/26-journal-entry-chart-of-accounts-dimensions.md) |
| Stock Entry, reconciliation, standard cost, the SLE controller | [doc 27](../logic/27-remaining-stock-documents.md) |
| BOM revisions, explosion and manufacturing cost inputs | [doc 33](../logic/33-bom-costing-explosion-and-update-jobs.md) |
| Operations, routing, workstations and capacity | [doc 34](../logic/34-operations-routing-workstations-and-capacity.md) |
| Work Orders, Job Cards and shop-floor execution | [doc 35](../logic/35-work-orders-job-cards-and-shop-floor.md) |
| Production Plan, MPS and material netting | [doc 36](../logic/36-production-planning-mps-and-material-netting.md) |
| Manufacturing consumption, scrap, WIP, valuation and GL | [doc 37](../logic/37-manufacturing-stock-consumption-scrap-wip-and-gl.md) |
| Quality templates, observations, formula/manual disposition, receipt/operation/stock gates, release and exceptions | [S09](S09-quality-gated-production-and-receipt.md) and [doc 39](../logic/39-quality-inspection-templates-readings-and-gates.md) |
| Supplier subcontract PO/SCO, custody send/return, receipt and service PR | [S08](S08-supplier-subcontracting.md) and [doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md) |
| Customer-owned inward SCIO, zero-valued custody, internal manufacture, delivery/return and billing | [S10](S10-customer-owned-subcontracting-inward.md) and [doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md) |
| *Which* tax applies (before doc 05 calculates it) | [doc 28](../logic/28-tax-determination.md) |
| *Which* price and rule apply | [doc 29](../logic/29-pricing-determination.md) |
| Quotation / RFQ / Blanket Order / Material Request, drop-ship, terms | [doc 30](../logic/30-upstream-trade-and-parties.md) |
| Batch processes, subscriptions, banking config, `Accounts Settings` | [doc 31](../logic/31-batch-processes-instruments-recurring.md) |
| `Stock Settings`, reposting settings, variants — and the coverage closure | [doc 32](../logic/32-stock-configuration-and-remaining-masters.md) |
| Tranche B coverage closure and production specification | [doc 40](../logic/40-tranche-b-coverage-closure-and-our-production-spec.md) |
| Asset identity, acquisition, capitalisation and finance books | [doc 41](../logic/41-asset-identity-acquisition-and-finance-books.md) |
| Depreciation schedules, methods, posting, shifts and revaluation | [doc 42](../logic/42-depreciation-engine-schedules-shifts-and-adjustments.md) |
| Asset custody, maintenance, repair, split and disposal | [doc 43](../logic/43-asset-custody-maintenance-repair-and-disposal.md) |
| Tranche C closure, A1–A26 and the asset schema | [doc 44](../logic/44-tranche-c-closure-and-our-asset-spec.md) |
| The target schema and invariant register | [FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md) |

## What is left

| Deliverable | Status |
|---|---|
| **Tranche B** | **COMPLETE** — [doc 40](../logic/40-tranche-b-coverage-closure-and-our-production-spec.md) closes measured coverage and the target production specification |
| **Tranche C (Assets)** | **COMPLETE** — docs 41–43, closed by [doc 44](../logic/44-tranche-c-closure-and-our-asset-spec.md), walked by [S11](S11-asset-lifecycle.md); all 14 Assets parents cited, 0 gaps |
| **Tranche F (Localisation, India GST first)** | **NEXT** — required capability, scoped in doc 44 §11 |
| Application implementation | **Has not started** |

All trade / inventory / accounts flows that cross three or more subsystems are covered by
**S01–S11**, including in-house manufacturing, both ownership directions of subcontracting, the
quality-gated receipt/production boundary and the full asset lifecycle. S09 completed the Tranche B
scenario set, doc 40 completed that tranche, and S11 closes the assets scenario set.
See [../COVERAGE.md](../COVERAGE.md) for the DocType-level coverage matrix.
