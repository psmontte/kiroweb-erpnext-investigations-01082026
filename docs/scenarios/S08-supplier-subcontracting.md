# S08 — Supplier Subcontracting: Service Order → Material Custody → Receipt

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Continues **[S03](S03-procure-to-pay.md)** where the Purchase Order buys conversion service rather
> than stock, and complements **[S07](S07-make-to-order-manufacturing.md)** by moving the physical work
> to a supplier. The subsystem trace is **[doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md)**.
>
> This document covers ordinary **supplier** subcontracting only. Customer-owned inward subcontracting
> reverses ownership and is deferred to S10.

---

## 1. The worked example and the two backflush branches

Company **AlphaCo** asks supplier **MetalWorks** to convert company-owned material into **10 EA FG-SUB**.
The commercial Purchase Order buys a non-stock service; the physical finished good and raw material sit
on the downstream Subcontracting Order and stock documents.

The active subcontracting recipe is:

| Kind | Item | Per gross FG | SCO quantity 10 | Rate / value |
|---|---|---:|---:|---:|
| Commercial service | SVC-SUB | 1 service unit | 10 | 12.00 = **120.00** |
| Company raw material | RM-A | 2 kg | 20 kg | 4.00/kg = **80.00** |
| Company raw material | RM-B | 1 kg | 10 kg | 6.00/kg = **60.00** |
| Legacy secondary output | SCRAP-S | 0.1 kg | 1 kg at full order | 2.00/kg |
| Receipt additional cost | inspection/handling | — | partial receipt only | **3.00** |

The BOM quantity basis is one gross FG and its process-loss percentage is 10%. The principal FG has
100% BOM cost allocation. `SCRAP-S` is deliberately a legacy secondary row with a known 2.00 rate; the
modern percentage-allocation branch is described separately because it uses a different equation.

Execution deliberately exposes custody, return, rejection and loss:

1. submit a PO for 10 SVC-SUB against 10 FG-SUB;
2. create and submit one SCO for all 10 FG, reserving RM-A 20 and RM-B 10;
3. with 10% over-transfer allowance, send RM-A 22 and RM-B 11 to the supplier;
4. return the unused over-transfer, RM-A 2 and RM-B 1, before receipt;
5. receive a gross attempted quantity of 5: **4 accepted FG + 0.5 rejected FG + 0.5 process loss**;
6. receive 0.5 kg legacy secondary output;
7. optionally create a Purchase Receipt for the accepted/rejected non-stock service quantity.

The same post-return supplier balance is replayed through two mutually exclusive Buying Settings:

| Policy | RM-A consumed | RM-B consumed | Why |
|---|---:|---:|---|
| **BOM** | 10 | 5 | gross `received_qty=5` × BOM 2/1 |
| **Material Transferred for Subcontract** | 8 | 4 | accepted `qty=4` × available 20/10 ÷ pending FG 10 |

This difference is intentional and load-bearing. BOM mode follows attempted gross output, including
rejection and loss. Transferred-material mode prorates the unlocked transfer residual by the accepted
receipt row quantity. The latter still passes the optional minimum-consumption validation here because
that check itself uses accepted `qty=4`: required RM-A 8 and RM-B 4
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:603-649`).

All values are company currency. Perpetual inventory is enabled. Raw, Supplier, FG, Rejected and Scrap
warehouses have distinct inventory accounts so movements remain visible. The receipt examples assume
that stock valuation produces an output SLE exactly **1.00 below** the document allocation amount; that
explicit assumption exists only to exercise the source-defined divisional-loss pair. It is not presented
as a rounding result ERPNext must produce for these inputs.

---

## 2. Stage 1 — the Purchase Order buys service, not FG stock

### 2.1 Commercial/physical conversion

The active Subcontracting BOM says one service unit buys one FG unit. Its stored factor is:

```text
conversion_factor = service_item_qty / finished_good_qty = 1 / 1 = 1
```

The master requires a stock, subcontracted finished good and a non-stock service item, then calculates
that factor before save
(`subcontracting/doctype/subcontracting_bom/subcontracting_bom.py:30-85`). If the buyer enters only
FG-SUB and quantity 10, Purchase Order service logic fills:

```text
PO item_code = SVC-SUB
PO qty       = 10 FG × 1 service/FG = 10
PO rate      = 12.00
PO amount    = 120.00
fg_item      = FG-SUB
fg_item_qty  = 10
bom          = BOM-FG-SUB-001
```

The PO validator requires the FG, subcontracting flag, BOM/default BOM and non-zero FG quantity; the
active conversion master can supply the service Item, quantity and UOM
(`buying/doctype/purchase_order/services/subcontracting.py:15-65`).

Submitting **PO-SUB-0001** persists one commercial authorisation. It creates no Stock Ledger Entry and
no GL Entry. `Purchase Order Item.subcontracted_qty` begins at zero. A Buying Setting can save an SCO
automatically, but does not make the PO itself physical stock evidence
(`buying/doctype/purchase_order/services/subcontracting.py:78-85`).

### 2.2 Initial writes

| Table | Rows | Worked values |
|---|---:|---|
| `tabPurchase Order` | 1 | supplier MetalWorks, `is_subcontracted=1`, supplier warehouse set |
| `tabPurchase Order Item` | 1 | SVC-SUB 10 @ 12, FG-SUB 10, BOM link, `subcontracted_qty=0` |
| `tabStock Ledger Entry` | 0 | no material or FG has moved |
| `tabGL Entry` | 0 | no service has yet been received/invoiced |

The PO row is commercial demand. Its mutable `subcontracted_qty` later summarizes allocation to SCOs;
it is not the allocation itself.

---

## 3. Stage 2 — PO → Subcontracting Order and RM reservation

### 3.1 Remaining service becomes physical FG

The mapper includes only PO rows whose service quantity differs from `subcontracted_qty`, copies them
as SCO service rows, and calls `populate_items_table()`
(`buying/doctype/purchase_order/mapper.py:221-332`). For this untouched PO:

```text
available service qty = 10 - 0 = 10
service per FG         = PO qty / PO fg_item_qty = 10 / 10 = 1
SCO FG qty             = 10 / 1 = 10
SCO service amount     = 10 × 12 = 120
```

The active Subcontracting BOM supplies the finished-good BOM; otherwise the Item default is used
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:238-298`). Validation normalizes
again to `service.qty = FG.qty × subcontracting_conversion_factor`, copies `fg_item_qty`, computes the
amount, and rejects a stock service Item
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:152-171`).

### 3.2 Raw-material expansion and planned cost

The shared controller reads direct or exploded BOM rows, excludes supplier-sourced inputs, expands
phantoms and stores BOM detail, source warehouse, UOM and rate. Required quantity is:

```text
BOM quantity per unit × SCO FG qty × FG stock-UOM conversion factor
```

(`controllers/subcontracting_controller.py:560-622`,
`controllers/subcontracting_controller.py:932-956`). The final factor here is the ordinary FG UOM
conversion factor, 1; it is not the commercial service-per-FG factor.

**SCO-SUB-0001** therefore contains:

| Child table | Item | Qty | Rate | Amount / role |
|---|---|---:|---:|---:|
| Service Item | SVC-SUB | 10 | 12.00 | 120.00 commercial conversion |
| Item | FG-SUB | 10 | 26.00 planned | 260.00 planned FG |
| Supplied Item | RM-A | required 20 | 4.00 BOM | 80.00 requirement |
| Supplied Item | RM-B | required 10 | 6.00 BOM | 60.00 requirement |

The order's planned FG rate is:

```text
planned RM/FG      = 80/10 + 60/10 = 14
planned service/FG = 120/10 = 12
planned FG rate    = 14 + 12 = 26
```

Order costing matches service to FG by `purchase_order_item`; it is a quote/planning snapshot, not the
later supplier-warehouse valuation
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:181-214`).

### 3.3 Submit order and reservations

SCO submit refreshes status, increments PO Item `subcontracted_qty` by 10, then creates reservations
when `reserve_stock=1`
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:112-123`,
`subcontracting/doctype/subcontracting_order/subcontracting_order.py:336-430`). The normal requests are:

| Voucher detail | Item / warehouse | Reserved quantity |
|---|---|---:|
| SCO supplied row A | RM-A / Raw | 20 |
| SCO supplied row B | RM-B / Raw | 10 |

The persisted shape now includes one SCO parent, one service child, one FG child, two supplied-item
children and normally two Stock Reservation Entries. Mutable projections become:

| Projection | Value |
|---|---:|
| PO Item `subcontracted_qty` | 10 service units |
| SCO status | Open |
| FG Bin `ordered_qty` | recomputed for 10 FG |
| RM-A Bin `reserved_qty_for_sub_contract` | recomputed around 20 |
| RM-B Bin `reserved_qty_for_sub_contract` | recomputed around 10 |

The explicit reservation and legacy Bin fields coexist. SCO status and Bin values are direct/recomputed
projections (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:216-237`,
`subcontracting/doctype/subcontracting_order/subcontracting_order.py:300-334`). No SLE or GL row exists
yet.

---

## 4. Stage 3 — send company material into supplier custody

### 4.1 Builder and allowance

`make_rm_stock_entry` builds purpose **Send to Subcontractor**, sources each supplied row from its
warehouse/reserve warehouse, targets the SCO supplier warehouse and normally proposes
`required_qty - total_supplied_qty`
(`controllers/subcontracting_controller.py:1344-1454`). We deliberately override the proposal to send
10% extra:

| Detail | Source | Target | Qty | Rate | Value |
|---|---|---|---:|---:|---:|
| RM-A | Raw | Supplier-MetalWorks | 22 | 4.00 | 88.00 |
| RM-B | Raw | Supplier-MetalWorks | 11 | 6.00 | 66.00 |

Under BOM policy, validation computes allowed quantity from required RM aggregated by Item and applies
`over_transfer_allowance`; prior send/return history is scoped to the SCO RM child
(`stock/doctype/stock_entry/services/subcontracting.py:36-100`). With allowance 10%:

```text
RM-A allowed = 20 × 1.10 = 22
RM-B allowed = 10 × 1.10 = 11
```

Under transferred-material policy, the server requires FG/reference linkage but applies no quantity
ceiling (`stock/doctype/stock_entry/services/subcontracting.py:102-112`). The same 22/11 document is
therefore valid in either replay, but for materially different reasons.

### 4.2 Source-before-target stock evidence

Generic Stock Entry constructs every source SLE before every target SLE; cancellation reverses the
complete list (`stock/doctype/stock_entry/stock_entry.py:977-1120`):

| SLE order | Item / warehouse | `actual_qty` | `stock_value_difference` |
|---:|---|---:|---:|
| 1 | RM-A / Raw | −22 | **−88.00** |
| 2 | RM-B / Raw | −11 | **−66.00** |
| 3 | RM-A / Supplier-MetalWorks | +22 | **+88.00** |
| 4 | RM-B / Supplier-MetalWorks | +11 | **+66.00** |

The balanced merged GL, when the warehouses use different accounts, is:

| Account | Debit | Credit |
|---|---:|---:|
| Supplier-held Inventory | 154.00 | |
| Raw Materials Inventory | | 154.00 |

This is not a purchase by MetalWorks. Quantity and value remain AlphaCo inventory; only custody/location
changes. Serial/batch packages, if present, are re-created at the target while retaining detail
provenance (`stock/doctype/stock_entry/stock_entry.py:1010-1109`).

### 4.3 Projection and reservation effects

After submit, the subcontracting purpose service recomputes every SCO supplied child from submitted
linked Stock Entry rows:

```text
supplied_qty       = Σ non-return transfer_qty
returned_qty       = Σ return transfer_qty
total_supplied_qty = supplied_qty - returned_qty
```

(`stock/doctype/stock_entry/services/subcontracting.py:166-249`). The immediate projections are A
`22/0/22` and B `11/0/11`; SCO status becomes Material Transferred because status compares gross
`supplied_qty` with required quantity. The query is purpose-blind after the SCO link and classifies by
`is_return`, so these counters are not independent evidence.

If SCO stock reservation is enabled, the send entry transfers reservation provenance to the supplier
warehouse, including bundle references, and releases relevant production reservations
(`stock/doctype/stock_entry/stock_entry.py:1152-1180`). The submitted Stock Entry, details, paired SLEs
and tracked-unit packages are evidence. SCO supplied counters, status, Bin and reservation progress are
mutable allocation projections.

---

## 5. Stage 4 — return the unused over-transfer

### 5.1 Availability and return builder

Before any SCR, available supplier material is exactly the submitted send balance. The return builder
folds sends, earlier transfer returns and submitted SCR consumption, then creates purpose **Material
Transfer**, `is_return=1`, from supplier warehouse back to the original reserve/source warehouse
(`controllers/subcontracting_controller.py:285-557`,
`controllers/subcontracting_controller.py:1456-1557`). **STE-SUB-RET-0001** returns:

| Detail | Source | Target | Qty | Rate | Value |
|---|---|---|---:|---:|---:|
| RM-A | Supplier-MetalWorks | Raw | 2 | 4.00 | 8.00 |
| RM-B | Supplier-MetalWorks | Raw | 1 | 6.00 | 6.00 |

Its source-before-target SLEs are:

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-A / Supplier-MetalWorks | −2 | −8.00 |
| 2 | RM-B / Supplier-MetalWorks | −1 | −6.00 |
| 3 | RM-A / Raw | +2 | +8.00 |
| 4 | RM-B / Raw | +1 | +6.00 |

The merged GL is `Dr Raw Materials Inventory 14 / Cr Supplier-held Inventory 14`. Exact batch balances
become separate return rows and available serials are carried back; the builder retains the SCO RM child
link (`controllers/subcontracting_controller.py:1456-1534`).

### 5.2 The common branch point

Both receipt-policy replays now begin from the same facts:

| RM | Required | Gross sent | Returned | Net at supplier | Supplier value |
|---|---:|---:|---:|---:|---:|
| RM-A | 20 | 22 | 2 | **20** | **80.00** |
| RM-B | 10 | 11 | 1 | **10** | **60.00** |
| **Total** | | | | | **140.00** |

SCO child projections read A `supplied=22, returned=2, total=20` and B `11,1,10`. Status nevertheless
uses gross `supplied_qty`, not net `total_supplied_qty`, and remains Material Transferred
(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:300-334`).

---

## 6. Stage 5 — SCO → partial Subcontracting Receipt

### 6.1 Gross, accepted, rejected and loss

The mapper starts from `SCO qty - received_qty`. For a requested gross partial quantity 5, BOM process
loss 10% initially produces:

```text
mapped received_qty = 5
process_loss_qty    = 5 × 10% = 0.5
initial accepted qty = 5 - 0.5 = 4.5
```

(`subcontracting/doctype/subcontracting_order/subcontracting_order.py:441-493`). We classify 0.5 as
rejected, reducing accepted quantity to 4 while preserving:

```text
accepted 4 + rejected 0.5 + process loss 0.5 = gross received 5
```

Accepted FG goes to Finished Goods, rejected FG to Rejected, and loss has no stock row. Every BOM
secondary row becomes a linked SCR Item. Our legacy `SCRAP-S` row receives 0.5 kg at 2.00/kg; modern
secondary output instead calculates gross/net quantity and percentage allocation from a reconstructed
FG pool (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:377-435`).

### 6.2 Shared output rows

Before raw-material policy diverges, **SCR-SUB-0001** has:

| SCR row | Gross received | Accepted / stock qty | Rejected | Process loss | Warehouse |
|---|---:|---:|---:|---:|---|
| FG-SUB principal | 5 | 4 | 0.5 | 0.5 | Finished Goods / Rejected |
| SCRAP-S legacy secondary | — | 0.5 | 0 | 0 | Scrap |

Additional cost is 3.00 distributed by quantity over the one eligible principal item:

```text
additional_cost_per_qty = 3 / accepted qty 4 = 0.75
```

The secondary row is excluded from that distribution
(`controllers/subcontracting_controller.py:1243-1284`).

---

## 7. Branch A — BOM backflush

### 7.1 Exact raw-material consumption

BOM mode rebuilds supplied rows from gross `received_qty` when it exists:

```text
RM-A = 2 × 5 × 1 = 10
RM-B = 1 × 5 × 1 = 5
```

(`controllers/subcontracting_controller.py:932-956`). Realised supplier-warehouse rates are read at the
SCR posting timestamp, with exact serial/batch bundle where applicable; each supplied amount is
`consumed_qty × realised rate`
(`controllers/subcontracting_controller.py:77-107`).

| Supplied row | Consumed | Realised rate | Amount | Supplier residual |
|---|---:|---:|---:|---:|
| RM-A | 10 | 4.00 | 40.00 | 20 − 10 = 10 |
| RM-B | 5 | 6.00 | 30.00 | 10 − 5 = 5 |
| **Total** | | | **70.00** | |

### 7.2 Receipt valuation

The principal row derives:

```text
rm_cost_per_gross unit = 70 / received_qty 5 = 14.00
service_cost_per unit  = 12.00
additional per accepted qty = 0.75
pre-allocation rate    = 26.75
document amount        = gross 5 × 26.75 × 100% = 133.75
stored accepted rate   = 133.75 / accepted 4 = 33.4375
```

The implementation folds supplied cost by principal reference, resets
`received_qty = accepted + rejected + process_loss`, applies BOM cost allocation and divides the amount
by accepted (or rejected) quantity
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:496-562`). The 0.5 rejected
and 0.5 lost units therefore concentrate document value into four accepted units.

### 7.3 Exact SLEs

For the divisional-loss demonstration, assume the accepted output SLE settles at **132.75**, one below
the document amount 133.75. The secondary output settles at its deterministic 1.00 value.

| SLE order | Item / warehouse | Qty | Incoming policy | SVD |
|---:|---|---:|---|---:|
| 1 | FG-SUB / Finished Goods | +4 | stored rate, recalculated | **+132.75** |
| 2 | FG-SUB / Rejected | +0.5 | zero incoming rate | **0.00** |
| 3 | SCRAP-S / Scrap | +0.5 | 2.00 | **+1.00** |
| 4 | RM-A / Supplier-MetalWorks | −10 | outgoing valuation | **−40.00** |
| 5 | RM-B / Supplier-MetalWorks | −5 | outgoing valuation | **−30.00** |

The shared SCR ledger builder creates accepted/secondary outputs, rejected output at zero, then supplier
material issues. Material rows depend into the principal FG detail for repost ordering
(`controllers/subcontracting_controller.py:1146-1230`). There is no SLE for service, additional cost or
process loss.

### 7.4 Unmerged GL composer rows and proof of balance

The dedicated composer reads the accepted output's exact SLE SVD. Service GL uses **accepted qty**, so
`12 × 4 = 48`, while the document amount above capitalized service across gross attempted quantity.
The source-defined rows are
(`subcontracting/doctype/subcontracting_receipt/services/gl_composer.py:33-214`):

| Leg | Account | Debit | Credit |
|---|---|---:|---:|
| Principal output | FG Inventory | 132.75 | |
| Principal base clearing | FG Expense/Clearing | | `132.75 − 48 = 84.75` |
| Service source | Subcontract Service Expense | | 48.00 |
| RM-A issue | Supplier-held Inventory | | 40.00 |
| RM-A clearing | RM Expense/Clearing | 40.00 | |
| RM-B issue | Supplier-held Inventory | | 30.00 |
| RM-B clearing | RM Expense/Clearing | 30.00 | |
| Additional allocation offset | FG Expense/Clearing | 3.00 | |
| Additional source | Inspection/Handling Expense | | 3.00 |
| Divisional offset | FG Expense/Clearing | 1.00 | |
| Divisional loss | Stock Adjustment | | `133.75 − 132.75 = 1.00` |
| Secondary output | Scrap Inventory | 1.00 | |
| Secondary clearing | Scrap Expense/Clearing | | 1.00 |
| **Total** | | **207.75** | **207.75** |

The apparent clearing residue is real composer behavior, not an arithmetic omission: accepted-quantity
service/additional legs coexist with a gross-quantity document valuation that includes rejection/loss.
`process_gl_map` may merge rows that share account and dimensions, but cannot change the balanced total.
Most importantly:

```text
FG inventory GL 132.75 = FG output SLE SVD 132.75
Scrap inventory GL 1.00 = Scrap output SLE SVD 1.00
Supplier inventory credit 70 = realised RM issues 70
```

The divisional pair never forces inventory to 133.75. It names the 1.00 document-vs-SLE difference in
Stock Adjustment against clearing.

### 7.5 Position after submit

| Fact / projection | RM-A | RM-B | FG / status |
|---|---:|---:|---|
| Gross sent | 22 | 11 | |
| Returned | 2 | 1 | |
| Net supplied | 20 | 10 | |
| Consumed by submitted SCR | **10** | **5** | |
| Supplier residual | **10** | **5** | |
| SCO Item `received_qty` | | | gross **5** |
| SCO `per_received` / status | | | **50% / Partially Received** |
| Accepted / rejected / loss | | | **4 / 0.5 / 0.5** |

`available_qty_for_consumption` becomes net supplied minus consumed, 10 and 5. The SCO consumed fields
are recomputed from submitted receipts and capped by gross `supplied_qty`, not net supplied
(`controllers/subcontracting_controller.py:1110-1144`).

---

## 8. Branch B — transferred-material backflush

This branch restarts from the common post-return position: supplier RM-A 20 and RM-B 10, SCO pending FG
10, with no submitted SCR.

### 8.1 Proportional allocation

Transferred-material policy folds submitted sends minus returns and prior receipt consumption, keyed by
`(raw material, finished good, subcontract order)`. For a partial receipt it computes:

```text
allocated RM = receipt accepted qty × available transferred RM / pending FG qty
```

Whole-number UOM and serial quantities round up; if the receipt equals all pending FG, it takes the
entire balance (`controllers/subcontracting_controller.py:911-983`). Here:

```text
RM-A = 4 accepted × 20 available / 10 pending = 8
RM-B = 4 accepted × 10 available / 10 pending = 4
```

| Supplied row | Consumed | Realised rate | Amount | Supplier residual |
|---|---:|---:|---:|---:|
| RM-A | 8 | 4.00 | 32.00 | 12 |
| RM-B | 4 | 6.00 | 24.00 | 6 |
| **Total** | | | **56.00** | |

This allocation is selected from an in-memory availability fold without an SCO/SCO-item/SCO-RM owner
lock. For tracked Items, ERPNext validates that chosen serial/batch identity was actually transferred,
but selection still precedes the final stock conflict
(`controllers/subcontracting_controller.py:623-713`,
`controllers/subcontracting_controller.py:1045-1101`).

### 8.2 Receipt valuation

```text
rm_cost_per_gross unit = 56 / received_qty 5 = 11.20
service_cost_per unit  = 12.00
additional per accepted qty = 0.75
pre-allocation rate    = 23.95
document amount        = gross 5 × 23.95 = 119.75
stored accepted rate   = 119.75 / 4 = 29.9375
```

Again assume output SLE valuation settles 1.00 lower, at 118.75. The secondary output remains 1.00.

### 8.3 Exact SLEs

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | FG-SUB / Finished Goods | +4 | **+118.75** |
| 2 | FG-SUB / Rejected | +0.5 | **0.00** |
| 3 | SCRAP-S / Scrap | +0.5 | **+1.00** |
| 4 | RM-A / Supplier-MetalWorks | −8 | **−32.00** |
| 5 | RM-B / Supplier-MetalWorks | −4 | **−24.00** |

### 8.4 Exact GL rows and proof of balance

| Leg | Account | Debit | Credit |
|---|---|---:|---:|
| Principal output | FG Inventory | 118.75 | |
| Principal base clearing | FG Expense/Clearing | | `118.75 − 48 = 70.75` |
| Service source | Subcontract Service Expense | | 48.00 |
| RM-A issue | Supplier-held Inventory | | 32.00 |
| RM-A clearing | RM Expense/Clearing | 32.00 | |
| RM-B issue | Supplier-held Inventory | | 24.00 |
| RM-B clearing | RM Expense/Clearing | 24.00 | |
| Additional allocation offset | FG Expense/Clearing | 3.00 | |
| Additional source | Inspection/Handling Expense | | 3.00 |
| Divisional offset | FG Expense/Clearing | 1.00 | |
| Divisional loss | Stock Adjustment | | `119.75 − 118.75 = 1.00` |
| Secondary output | Scrap Inventory | 1.00 | |
| Secondary clearing | Scrap Expense/Clearing | | 1.00 |
| **Total** | | **179.75** | **179.75** |

The same composer code generates both branches; only realised supplied-material amount and resulting
output valuation differ. Inventory GL again equals SLE value exactly.

### 8.5 Position and direct comparison

| Measure after the same gross receipt | BOM | Transferred material |
|---|---:|---:|
| RM-A consumed / residual | 10 / 10 | **8 / 12** |
| RM-B consumed / residual | 5 / 5 | **4 / 6** |
| Realised RM cost | 70.00 | **56.00** |
| SCR principal document amount | 133.75 | **119.75** |
| Principal output SVD / inventory GL | 132.75 | **118.75** |
| Divisional loss | 1.00 | **1.00** |
| Accepted/rejected/loss | 4 / 0.5 / 0.5 | **same** |
| SCO gross received / status | 5 / Partially Received | **same** |

The output and fulfilment projections are identical even though custody consumption and inventory value
are not. Policy is therefore part of conversion meaning, not a display preference.

---

## 9. Optional Purchase Receipt — commercial service only

After SCR stock, GL and repost processing, Buying Settings may call `make_purchase_receipt(save=True)`;
the automatic document is saved as a **draft**, not submitted
(`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:706-712`). The mapper goes
back to the original PO service row and computes:

```text
service per FG       = PO service qty / PO fg_item_qty = 10 / 10 = 1
accepted service qty = 1 × SCR accepted FG 4 = 4
rejected service qty = 1 × SCR rejected FG 0.5 = 0.5
```

It copies the SCR posting time, supplier warehouse and exact SCR Item link, and marks the PR
subcontracted (`subcontracting/doctype/subcontracting_receipt/mapper.py:26-129`). Process loss 0.5 does
not become service receipt quantity in this mapper.

| PR row | Item | Accepted qty | Rejected qty | Stock effect |
|---|---|---:|---:|---|
| 1 | SVC-SUB | 4 | 0.5 | none; non-stock service |

The PR can complete the PO's commercial service-receipt, accrual and later invoice path. It must not
receive FG-SUB again: the SCR is the only physical conversion and the only source of FG/material SLEs.
The draft auto-PR is not yet accounting evidence; if a user submits it, its commercial lifecycle becomes
a downstream dependency of the SCR/PO chain.

---

## 10. Complete write trace

Counts exclude optional taxes, Version rows, serial/batch bundles, reservation internals and repost
requests. SCR GL counts are the unmerged composer rows shown above; account merging can reduce physical
`tabGL Entry` rows.

| Stage | Primary document/children | SLE | GL | Important mutable projections |
|---|---|---:|---:|---|
| PO submit | PO 1 + Item 1 | 0 | 0 | PO status |
| SCO submit | SCO 1 + Service 1 + Item 1 + Supplied 2 (+ SRE 2) | 0 | 0 | PO subcontracted 10, Bin/SRE reservations, SCO status |
| Send 22/11 | SE 1 + Detail 2 | **4** | **2** | supplied 22/11, reservation transfer, SCO status |
| Return 2/1 | SE 1 + Detail 2 | **4** | **2** | returned 2/1, net supplied 20/10 |
| SCR, either branch | SCR 1 + Item 2 + Supplied 2 + Additional Cost 1 | **5** | **13 unmerged** | SCO received/consumed/status, reservations/Bins |
| Optional auto-PR | draft PR 1 + service Item 1 | 0 | 0 until submit | PO service receipt projection after submit |
| **Posted through SCR** | | **13 SLE** | **17 unmerged GL** | many direct aggregate writes |

The send and return GL each merge to two economic rows. SCR includes 11 principal/material/cost rows and
two secondary inventory/clearing rows. If FG/RM clearing accounts coincide, `process_gl_map` merges
several of those physical rows without changing the debit/credit proof.

### 10.1 Evidence versus projection

| Representation | Classification |
|---|---|
| Submitted PO | commercial service authorisation; not stock evidence |
| Submitted SCO and requirement children | supplier conversion/material authorisation; persisted but mutable projections surround it |
| PO Item `subcontracted_qty` | mutable allocation projection |
| Stock Reservation Entry / serial-batch lineage | explicit allocation evidence with mutable consumed/delivered progress |
| Bin reserved/ordered/actual/value fields | planning or stock projections |
| Submitted Send/Return Stock Entry + Detail | custody command evidence |
| Send/Return SLE item, warehouse, qty, voucher/detail and bundle | custody stock evidence |
| Submitted SCR + Item/Supplied Item/Additional Cost | strongest conversion and cost-allocation command evidence |
| SCR output/material SLE quantity and identity | physical conversion evidence |
| SLE running value/rate/queue/SVD | valuation projection stored on and rewritable with SLE |
| GL Entry | accounting evidence in meaning; repost can delete/recreate physical rows |
| SCO supplied/returned/net/consumed/received/status | mutable projections over stock and receipt documents |
| Draft auto-created service PR | commercial proposal only; submitted PR is commercial receipt evidence |

The strongest audit chain is:

```text
PO service Item → SCO service/FG/requirement identities
  → send/return Stock Entry Detail → custody SLE / serial-batch package
  → SCR FG and supplied detail → output/input SLE → dedicated GL composer rows
  → optional PR service Item → later Purchase Invoice
```

Legal ownership never leaves AlphaCo during send/return. ERPNext represents that by ordinary stock in a
supplier warehouse; there is no owner dimension on the SLE.

---

## 11. Submit ordering, races and cancellation blockers

### 11.1 Receipt submit order

SCR submit performs, in source order:

1. reject a closed/held SCO and validate BOM consumption;
2. update SCO Item `received_qty` and parent `per_received`;
3. refresh SCO status and recompute consumed RM;
4. create/convert serial-batch bundles and adjust reservations;
5. post SLEs, then GL;
6. repost future valuation and set SCR status;
7. save the optional draft service PR;
8. refresh linked Job Card manufactured quantity.

The order is explicit at
`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:168-187`. Upstream projections
therefore move before the stock evidence they summarize. Ordinary transaction rollback normally makes
an exception atomic, but correctness still depends on callback order and the absence of an unlocked
concurrent allocator.

No SCO owner lock serializes transfer residual, supplier availability or receipt allocation. Two SCRs
can preview the same transferred-material balance. Stock/serial checks catch some conflicts later, but
the business allocation has already passed. Other source defects exposed by this scenario are:

- BOM transfer validation compares whole-SCO requirement by Item with detail-scoped send/return history;
- transferred-material send validation has no quantity ceiling;
- sent/return projection recomputation is purpose-blind after the SCO link;
- consumed projection is capped by gross sent, not net sent;
- the receipt status helper references `self.__get_subcontract_orders` without calling it
  (`controllers/subcontracting_controller.py:1110-1144`,
  `controllers/subcontracting_controller.py:1232-1241`).

### 11.2 Safe operational reversal

Reverse the worked chain in this order:

1. **Optional Purchase Receipt.** If still draft, delete/unlink it; if submitted, cancel downstream
   invoices first, then cancel the PR. It represents the commercial service receipt.
2. **Subcontracting Receipt.** Reopen the SCO first if manually Closed: SCR cancellation explicitly
   rejects closed/held orders. Cancellation reverses upstream receipt/consumption projections, stock,
   reservations and GL, then reposts future valuation
   (`subcontracting/doctype/subcontracting_receipt/subcontracting_receipt.py:192-213`).
3. **Supplier return Stock Entry.** Cancel the 2/1 return, reversing Raw→Supplier custody and recomputing
   returned/net projections.
4. **Send to Subcontractor Stock Entry.** Cancel the 22/11 send only after its return and consumption
   are gone. Otherwise linked stock, serial/batch identity or negative-stock consequences can block a
   valid reversal. Stock Entry cancellation reverses target-before-source because it reverses the SLE
   list (`stock/doctype/stock_entry/stock_entry.py:977-993`).
5. **Subcontracting Order.** Cancel only after linked stock/receipt dependencies are gone; this reverses
   PO `subcontracted_qty` and status/Bin projections. The displayed `on_cancel` does not directly call
   the separate reservation-cancellation method
   (`subcontracting/doctype/subcontracting_order/subcontracting_order.py:121-123`,
   `subcontracting/doctype/subcontracting_order/subcontracting_order.py:432-438`).
6. **Purchase Order.** Cancel after its SCO and any submitted service PR/invoice chain is reversed.

Closing the PO propagates Closed to the SCO, and a Closed SCO also blocks Stock Entry/SCR cancellation
until reopened (`buying/doctype/purchase_order/services/subcontracting.py:87-97`). Generic submitted-link,
negative-stock and tracked-unit checks can add blockers beyond these explicit controller checks.

---

## 12. The same scenario in our design

### 12.1 Immutable commercial and material allocations

The PO service line and physical quantity are joined by one versioned conversion allocation:

```text
PO service line SVC-SUB 10
  └─ subcontract authorisation FG-SUB gross 10, service factor 1/1
       ├─ requirement RM-A 20 from exact BOM revision
       └─ requirement RM-B 10 from exact BOM revision
```

A unique source-line key and owner lock bound the allocation. `subcontracted_qty`, required, reserved,
sent, returned, consumed and received are views over allocation edges, never independent writable
counters.

### 12.2 Custody is paired stock evidence

Send and return remain ordinary paired moves because that part of ERPNext is sound:

```text
send:   RM-A Raw −22 / Supplier +22, RM-B Raw −11 / Supplier +11
return: RM-A Supplier −2 / Raw +2, RM-B Supplier −1 / Raw +1
```

Each pair carries company owner, supplier custodian, requirement ID, transfer ID and exact lot/serial
identity. Warehouse is custody, not ownership. Net quantity/value across the pair is zero.

### 12.3 Policy-versioned conversion

The receipt is one immutable conversion containing:

- accepted FG 4, rejected FG 0.5 and explicit process-loss event 0.5;
- secondary output 0.5;
- exact RM allocation IDs: 10/5 under BOM-v1 or 8/4 under transfer-proration-v1;
- realised material layers, service allocation 48, additional-cost source 3 and output value deltas;
- balanced stock moves and GL journal generated atomically.

The policy choice is snapshotted. BOM mode cannot silently become transferred-material mode on replay,
and transferred mode allocates under the SCO owner lock. A receipt cannot commit until every input and
tracked unit is exclusively allocated.

Process loss and rejection are typed facts even if accounting policy capitalizes their value into
accepted FG. A deterministic coproduct policy allocates the input pool across principal, rejected,
secondary and loss/variance exactly once; there is no separate modern/legacy equation.

### 12.4 Evidence before projection

Stock moves, lot allocations, cost-source allocations and balanced GL commit first under one event
position. Idempotent projectors then rebuild PO/SCO/Bin/reservation/status views. Optional service receipt
has a unique one-to-one allocation to the physical SCR and cannot duplicate FG stock.

For the transferred branch, the projection may still display accepted 4, rejected 0.5, loss 0.5 and
supplier residual 12/6—but those values are reproducible from immutable edges rather than callbacks.

---

## 13. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| PO service ↔ FG | non-stock service plus mutable copied FG fields | immutable rational conversion allocation |
| Active recipe | application-level active lookup | versioned revision with DB-enforced active uniqueness |
| PO residual | read then update `subcontracted_qty` without owner lock | unique bounded allocation under source-line lock |
| BOM requirements | child rows can be rebuilt before submit | exact recipe revision and requirement identities |
| Reservation | SRE plus parallel Bin counters | one allocation ledger; Bin is a view |
| Supplier stock | ordinary company stock, correctly valued | same, plus explicit company owner/supplier custodian |
| Send/return | paired source/target SLEs | paired immutable stock moves with exact requirement/lot edge |
| BOM send ceiling | aggregate/detail key mismatch | ceiling per requirement identity under one lock |
| Transferred-mode send | no server quantity ceiling | bounded transfer allocation |
| Supplier availability | unlocked in-memory fold | locked residual over transfer allocations |
| BOM backflush | gross attempted quantity | named, versioned gross policy |
| Transferred backflush | accepted qty × aggregate residual / pending FG | exact transfer residual allocation under lock |
| Rejected output | zero-valued incoming stock row | typed output with explicit valuation policy |
| Process loss | scalar; no stock/allocation/GL identity | typed loss event with reason and account policy |
| Secondary output | modern and legacy equations | one deterministic coproduct allocation equation |
| Actual RM cost | supplier-warehouse valuation at receipt time | exact consumed stock layers; same principle |
| Inventory amount | exact output SLE SVD | immutable move value delta; same accounting principle |
| Service/additional cost | explicit composer legs | immutable cost-source allocations |
| Divisional loss | Stock Adjustment pair, inventory not forced | named variance pair, inventory still authoritative |
| Optional PR | maps non-stock service; auto-save draft | idempotent commercial receipt linked one-to-one |
| Progress/status | mutable callbacks before/around posting | post-evidence idempotent projections |
| Cancellation | distributed blockers and document order | declared dependency graph and linked reversal events |

---

## 14. Findings and invariants exercised

1. **Supplier custody is still company inventory.** Send and return conserve AlphaCo quantity and value;
   the supplier warehouse is an ordinary valued stock location.
2. **The two backflush policies do not answer the same question.** With identical transfers and output,
   BOM consumes for gross attempt 5 while transferred-material mode prorates by accepted 4.
3. **Rejected and lost output affect valuation without symmetric physical evidence.** Rejected stock is
   zero-valued; process loss has no SLE; their gross cost can concentrate in accepted FG.
4. **SLE value remains the accounting authority.** In both branches, output inventory GL equals output
   SVD and the assumed 1.00 document difference goes to Stock Adjustment.
5. **Service, material and additional cost are distinct GL sources.** The SCR does not hide those
   sources inside a single inventory balancing line.
6. **The optional Purchase Receipt is commercial, not physical.** It receives 4 accepted and 0.5
   rejected service units and never duplicates FG stock.
7. **The weak boundary is allocation concurrency.** PO residual, transfer ceilings, supplier balance and
   receipt consumption are read-check-write paths without one owner lock.
8. **Most progress fields are projections.** Submitted stock and receipt details are the command chain;
   SCO/PO/Bin counters and percentages can be rebuilt and can drift.

This scenario exercises doc 38 invariants **M41–M51** and **M54–M55**: command identity,
commercial/physical conservation, actual-cost authority, supplier allocation, custody conservation,
consumption completeness, tracked-unit continuity, yield/cost allocation, stock projection, stock/GL
bridge, evidence-before-projection, immutable posting and serializable allocation. It also reuses **F1**
(balanced vouchers) and **F2** (inventory GL equals stock value delta) from S04.

---

Cross-references: **[S03](S03-procure-to-pay.md)** (PO, PR, PI and landed-cost commercial mechanics),
**[S04](S04-stock-transfer-and-in-transit.md)** (paired warehouse movement and valuation),
**[S07](S07-make-to-order-manufacturing.md)** (in-house conversion, WIP, loss and production GL);
**[doc 02](../logic/02-stock-ledger-and-valuation.md)** (valuation/repost),
**[doc 03](../logic/03-stock-gl-bridge.md)** (stock→GL),
**[doc 16](../logic/16-stock-reservation-picking-warehouse.md)** (reservation/Warehouse/Bin),
**[doc 17](../logic/17-item-uom-variants-batch-reorder.md)** (tracked units),
**[doc 30](../logic/30-upstream-trade-and-parties.md)** (PO and parties),
**[doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md)** (complete supplier
and inward source trace), and `docs/design/FINAL-SCHEMA.md` (target allocation, ownership, stock and GL
model).
