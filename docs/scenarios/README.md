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

## Reading order

Read **S01 → S02 → S03**. S02 assumes S01's closing position; S03 assumes both.

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
| The target schema and invariant register | [FINAL-SCHEMA.md](../design/FINAL-SCHEMA.md) |

## What is not here yet

| Scenario | Depends on |
|---|---|
| Stock transfer between warehouses, in-transit | — could be written now |
| Period close and opening balances, walked through | [doc 07](../logic/07-period-close-and-opening-balances.md) — could be written now |
| Multi-currency invoice → payment → FX revaluation | — could be written now |
| Make-to-order: SO → Work Order → material issue → finished goods → DN | **Tranche B (manufacturing)** |
| Subcontracting: PO → RM transfer → Subcontracting Receipt | **Tranche B** |
| Quality inspection gating a receipt | **Tranche B (quality)** |
| Asset purchase → capitalisation → depreciation run → disposal | **Tranche C (assets)** |
