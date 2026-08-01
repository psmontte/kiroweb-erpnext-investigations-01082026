# Business logic of the accounting + trade/inventory engine

What the code actually does, function by function, so we can reimplement it deliberately.

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
| 8 | [08-our-implementation-spec.md](08-our-implementation-spec.md) | **the deliverable**: invariants to enforce, what we keep/change, decisions taken, and the Phase 0-2 build spec |

## Verifying the citations

Line numbers drift with every upstream commit. `tools/verify_refs.py` extracts every
`file.py:NNN` citation from these docs, resolves it against the source tree, and reports the
enclosing `def`/`class`:

```bash
python3 tools/verify_refs.py --docs docs/logic \
  --app erpnext=/path/to/erpnext/erpnext \
  --app frappe=/path/to/frappe/frappe --strict-names
```

Last run against the anchor commits: **126 citations, 0 unresolved paths, 0 out of range**
(5 advisory name notes, each reviewed — those lines mention a symbol defined elsewhere in the
same file, which is intentional).

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
