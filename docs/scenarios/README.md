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

## Reading order

Read **S01 → S02 → S03**. S02 assumes S01's closing position; S03 assumes both.
**S04** onwards are independent and can be read in any order.

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
| *Which* tax applies (before doc 05 calculates it) | [doc 28](../logic/28-tax-determination.md) |
| *Which* price and rule apply | [doc 29](../logic/29-pricing-determination.md) |
| Quotation / RFQ / Blanket Order / Material Request, drop-ship, terms | [doc 30](../logic/30-upstream-trade-and-parties.md) |
| Batch processes, subscriptions, banking config, `Accounts Settings` | [doc 31](../logic/31-batch-processes-instruments-recurring.md) |
| `Stock Settings`, reposting settings, variants — and the coverage closure | [doc 32](../logic/32-stock-configuration-and-remaining-masters.md) |
| The target schema and invariant register | [FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md) |

## What is not here yet

| Scenario | Depends on |
|---|---|
| **S07** Make-to-order: SO → Production Plan → Work Order → material issue/consumption → finished goods → DN | **Tranche B (manufacturing; next)** |
| **S08** Supplier subcontracting: PO → Order → RM transfer/return → Receipt | **Tranche B (subcontracting)** |
| **S09** Quality-gated receipt and production | **Tranche B (quality)** |
| **S10** Customer-owned subcontracting inward flow | **Tranche B (subcontracting)** |
| Asset purchase → capitalisation → depreciation run → disposal | **Tranche C (assets)** — deferred; revisit before implementation |

All trade / inventory / accounts flows that cross three or more subsystems are covered by
**S01–S06**. Tranche B will add **S07–S10** in manufacturing → subcontracting → quality order.
See [../COVERAGE.md](../COVERAGE.md) for the DocType-level coverage matrix.
