# S10 — Customer-Owned Subcontracting Inward: Custody → Manufacture → Return

> **Scenario walkthrough.** Source pinned at `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de`
> (v17.0.0-dev), `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56`.
> Citations are `path:line` relative to `/projects/sandbox/erpnext/erpnext` (or `frappe/`).
>
> Continues **[S01](S01-order-to-cash.md)** on a Sales Order that sells conversion service rather than
> finished stock, and mirrors **[S08](S08-supplier-subcontracting.md)** with legal ownership reversed.
> The complete supplier/inward subsystem trace is **[doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md)**.
>
> This is an investigation document. It describes pinned ERPNext behavior and the owner-aware target
> design; it does not prescribe an operational workaround or change application code.

---

## 1. The worked example and posting assumptions

Company **AlphaCo** converts customer **BetaCo** material into **10 EA FG-CUST**. BetaCo owns the main
input throughout AlphaCo's custody. AlphaCo supplies a smaller raw material, performs one operation,
delivers all ten finished units in two lots, and receives two units back.

The submitted Sales Order buys a non-stock service. The physical finished good and both kinds of raw
material live on the downstream Subcontracting Inward Order (SCIO), Work Order and Stock Entries:

| Kind | Item / operation | Per FG | Quantity | Commercial / valuation basis |
|---|---|---:|---:|---:|
| Non-stock service | SVC-INWARD | 1 service unit | 10 | sell 15.00 = **150.00** |
| Customer-owned RM | RM-CUST | 2 kg | required 20 kg | customer memo cost 4.00/kg = **80.00**, company value **0** |
| Company-owned RM | RM-ALPHA | 0.5 kg | required/consumed 5 kg | company value 6.00/kg = **30.00**; sell 8.00/kg = **40.00** |
| Operation | Convert | 10 min | 100 min | capitalised operation cost **20.00** |
| Finished output | FG-CUST | — | produced 10 | company-book value **50.00**, or 5.00/EA |

Execution deliberately exposes ownership, custody, gross/net fulfilment and billing:

1. submit a Sales Order for 10 SVC-INWARD against 10 FG-CUST;
2. map and submit one SCIO with customer warehouse `Beta Custody - A` and output warehouse
   `Inward Delivery - A`;
3. receive 22 kg RM-CUST at customer-declared memo cost 4.00, but force company valuation to zero;
4. return the 2 kg surplus before it is allocated to production;
5. submit one Work Order for 10, one Convert Job Card, and transfer RM-CUST 20 plus RM-ALPHA 5 to WIP;
6. manufacture 10 FG from customer RM value 0, company RM value 30 and operation cost 20;
7. deliver 6 FG, receive 2 FG back, then deliver the remaining gross order quantity 4;
8. invoice service 150 plus AlphaCo-owned material 40, with no stock update.

All values are company currency. Perpetual inventory and moving-average valuation are enabled; negative
stock, overproduction, taxes, currency conversion, scrap and secondary output are excluded. Raw,
Customer Custody, WIP, Inward Delivery and Delivery Expense use the accounts named below. The worked
Manufacture carries operation cost 20 as an Additional Cost. `book_stock_expense_gl_entries` is off so
the optional Expenses Added to Stock memorandum pair does not add rows. The FG return is explicitly
entered at the original 5.00 outgoing layer into the same Inward Delivery warehouse; ERPNext does not
itself enforce that valuation link.

These assumptions make every stock and GL number deterministic. Standard Cost would add a Manufacturing
Variance branch; a zero-rate FG return would produce quantity with no value and is a materially
different case.

---

## 2. Stage 1 — the Sales Order sells service, not customer material

### 2.1 Commercial/physical conversion

The active Subcontracting BOM maps one SVC-INWARD service unit to one FG-CUST. The Sales Order row is:

```text
item_code     = SVC-INWARD       (non-stock)
qty/stock_qty = 10
rate/amount   = 15 / 150
fg_item       = FG-CUST
fg_item_qty   = 10
bom           = BOM-FG-CUST-001
```

As in supplier subcontracting, the conversion factor is service units per FG. The SCIO mapper first
checks whether every Sales Order Item `qty` equals its mutable `subcontracted_qty`; it maps each unequal
row as a service child and then calls `populate_items_table()`
(`selling/doctype/sales_order/mapper.py:1055-1122`). If exactly one enabled, non-rejected Warehouse is
tagged to BetaCo it is defaulted, but that lookup is not company-scoped
(`selling/doctype/sales_order/mapper.py:1071-1090`).

Submitting **SO-IN-0001** writes commercial demand only:

| Table | Rows | Worked values |
|---|---:|---|
| `tabSales Order` | 1 | BetaCo, AlphaCo, `is_subcontracted=1` |
| `tabSales Order Item` | 1 | SVC-INWARD 10 @ 15, FG-CUST 10, `subcontracted_qty=0` |
| `tabStock Ledger Entry` | 0 | no stock is received or produced |
| `tabGL Entry` | 0 | service is not yet invoiced |

The Sales Order does not sell RM-CUST back to BetaCo: BetaCo already owns it. RM-ALPHA is not on the
Sales Order service line either; it is appended later to the Sales Invoice from SCIO consumption.

### 2.2 The first unlocked residual

For each service child SCIO population calculates:

```text
available service stock qty = SO Item.stock_qty - SO Item.subcontracted_qty = 10
service per FG               = SO Item.stock_qty / SO Item.fg_item_qty = 1
SCIO FG qty                  = available / service per FG = 10
```

It selects the active Subcontracting BOM or Item default BOM
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:165-218`). SCIO
submit later loads each Sales Order Item, increments `subcontracted_qty`, and saves it; cancel subtracts
it (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:133-142`). There
is no source-row lock joining the read, allocation and update. Two SCIOs can therefore preview the same
remaining ten service units.

---

## 3. Stage 2 — SCIO authorisation and the owner/custody gap

### 3.1 BOM expansion

Shared subcontracting expansion copies direct or exploded BOM requirements. An Item currently marked
`is_customer_provided_item` is sourced from the SCIO customer warehouse; a company Item keeps its BOM or
default source warehouse (`controllers/subcontracting_controller.py:560-622`). SCIO requires at least
one customer-provided material per FG and validates only that `Warehouse.customer == SCIO.customer`
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:143-151`,
`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:220-234`).

**SCIO-IN-0001** persists:

| Child table | Item | Qty | Warehouse / role |
|---|---|---:|---|
| Service Item | SVC-INWARD | 10 | SO commercial allocation, amount 150 |
| Item | FG-CUST | 10 | `Inward Delivery - A` |
| Received Item | RM-CUST | required 20 | `Beta Custody - A`, customer-provided |
| Received Item | RM-ALPHA | required 5 | company material, source `Raw - A` |

Submit changes the SO Item projection to `subcontracted_qty=10`. No material has arrived, so SCIO
percentages are zero and status is Open. There is no SLE or GL.

### 3.2 Warehouse is custody, not legal ownership

ERPNext has no owner column on Stock Ledger Entry. Customer ownership is inferred from three mutable or
indirect facts:

1. Item `RM-CUST` is globally marked customer-provided;
2. Warehouse `Beta Custody - A` is tagged to BetaCo; and
3. receipt valuation is forced to zero.

That is not an ownership ledger. The same Item cannot naturally be customer-owned in one lot and
AlphaCo-owned in another, changing the Item flag changes future policy, and the customer Warehouse can
be selected across companies because SCIO only checks its customer tag. Most visibly, the later
Material Transfer moves RM-CUST into an ordinary WIP warehouse with no customer tag at all. Its legal
owner then survives only in SCIO/Work Order links and reservation lineage, not in the stock balance key.

This is doc 38's central inward-flow finding and its **Invariant M52**: custody Warehouse is not
ownership, and zero value is an accounting policy rather than legal provenance
([doc 38 §13.1](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md#131-sales-order--scio)).

---

## 4. Stage 3 — receive 22 kg customer RM at zero company value

### 4.1 Builder and validation

`make_rm_stock_entry_inward` creates purpose **Receive from Customer**, target-only, and normally
proposes:

```text
required - received + returned + BOM qty × recorded process loss
= 20 - 0 + 0 + 0 = 20
```

(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:326-382`). We
explicitly receive 22 because BetaCo sent a 2 kg handling surplus. Server validation requires a
customer-provided Item, preserves the linked SCIO material identity, requires an FG reference for any
additional row, rejects duplicate additional `(Item, FG)` pairs, and forces the target customer
warehouse (`controllers/subcontracting_inward_controller.py:61-110`,
`controllers/subcontracting_inward_controller.py:386-418`).

Before stock posting ERPNext overwrites:

```text
valuation_rate = 0
customer_provided_item_cost
  = basic_rate + additional_cost / transfer_qty
  = 4 + 0 / 22 = 4
```

(`controllers/subcontracting_inward_controller.py:573-594`). **STE-IN-RCV-0001** therefore produces:

| SLE order | Item / warehouse | Qty | Incoming rate | SVD |
|---:|---|---:|---:|---:|
| 1 | RM-CUST / Beta Custody | **+22** | **0.00** | **0.00** |

There is no source SLE and no GL row. The company has custody of 22 kg but has acquired no asset and
incurred no liability. BetaCo's declared 88.00 is memorandum information only.

### 4.2 Memo cost and reservation are separate projections

After stock and GL processing, the inward callback updates the linked SCIO child. The weighted memo
rate is computed over on-hand balance:

```text
balance before receipt = received - returned - consumed = 0
new memo rate          = (old rate × old balance + 4 × 22) / 22 = 4
```

The update is an unlocked read/calculate/absolute-write
(`controllers/subcontracting_inward_controller.py:706-797`). It does not change the SLE's zero value.

The same callback submits a Stock Reservation Entry for 22 kg, keyed by the SCIO material child and
warehouse. If the receipt has a Serial and Batch Bundle, its exact entries are copied to the reservation
(`controllers/subcontracting_inward_controller.py:1033-1065`). The reservation is stronger allocation
evidence than the SCIO counters, but still has no legal owner dimension.

| Representation after receipt | Quantity / value | Meaning |
|---|---:|---|
| Customer-warehouse stock | 22 kg / **0 company value** | custody stock projection |
| SCIO `received_qty` | 22 | mutable receipt projection |
| SCIO memo `rate` | 4.00 | customer-cost observation, not valuation |
| SRE | 22 | allocation/serial-batch lineage |
| `per_raw_material_received` | **110%** | gross received / required |
| SCIO status | Ongoing | some customer RM has arrived |

The 110% is not capped and does not net later return.

---

## 5. Stage 4 — return the 2 kg surplus before production

### 5.1 Returnable quantity

The return builder calculates:

```text
returnable = received_qty - work_order_qty - returned_qty
           = 22 - 0 - 0 = 22
```

and creates source-only purpose **Return Raw Material to Customer**
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:384-438`). We reduce
the row to the actual surplus 2. Server validation caps the transfer against that residual, and tracked
serial/batch identity must come from the SCIO reservation lineage
(`controllers/subcontracting_inward_controller.py:112-159`,
`controllers/subcontracting_inward_controller.py:420-488`).

**STE-IN-RMRET-0001** posts:

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-CUST / Beta Custody | **−2** | **0.00** |

Again there is no GL. The SRE delivered quantity advances for the returned lot. Projections become
`received=22`, `returned=2`, net custody 20, memo rate 4, and:

```text
per_raw_material_received = 22 / 20 = 110.00%
per_raw_material_returned = 2 / 22 = 9.09%
```

The builder has two defects that the worked document avoids: it iterates company-provided rows too, and
it skips zero but not negative balances. It can propose a company-owned material return or a negative
row even though server validation later supplies a ceiling. Gross receipt and return are kept as
independent projections rather than one owner-aware custody balance.

---

## 6. Stage 5 — Work Order, Job Card and allocation

### 6.1 Maximum producible quantity

For each customer RM the SCIO preview computes:

```text
producible = (received - returned - prior work_order_qty)
             / (RM required / ordered FG)
           = (22 - 2 - 0) / (20 / 10)
           = 10 FG
```

It takes the minimum across customer materials, floors whole-number UOM, and caps by ordered minus
produced (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:238-312`).
The preview creates **WO-IN-0001** for 10 with source `Beta Custody - A`, WIP `WIP - A`, FG target
`Inward Delivery - A`, stock reservation enabled, and two required rows:

| Work Order requirement | Required | Source | Ownership meaning |
|---|---:|---|---|
| RM-CUST | 20 | Beta Custody | BetaCo-owned, allocated to WO |
| RM-ALPHA | 5 | Raw | AlphaCo-owned |

Work Order validation requires its source and FG warehouse to match SCIO, requires each customer Item
from the customer Warehouse, rejects duplicate customer Item codes, and checks customer requirement
against `received - returned - prior work_order_qty`. Company material cannot source from a
customer-tagged Warehouse (`manufacturing/doctype/work_order/work_order.py:364-459`).

On submit the Work Order increments SCIO customer RM `work_order_qty` by 20, updates stock reservations,
and creates Job Cards (`manufacturing/doctype/work_order/work_order.py:614-710`). The update uses
Item-code maps; duplicate same-Item BOM roles can overwrite rather than preserve requirement identity.
No SLE or GL exists yet.

### 6.2 Job Card

The single Convert operation creates **JC-IN-0001** for 10 FG and 100 minutes. Job Card construction
copies Work Order, operation identity, quantity, warehouses, hour rate and sequence
(`manufacturing/doctype/work_order/mapper.py:375-444`). It is shop-floor execution evidence for who did
what and when, but not stock evidence. A linked submitted Manufacture later recomputes
`manufactured_qty` from its finished-item Stock Entry rows
(`manufacturing/doctype/job_card/job_card.py:204-225`).

After WO submission the SCIO customer-material residual available to another WO is zero:

```text
22 received - 2 returned - 20 work_order_qty = 0
```

The ceiling was read before the SQL update and no SCIO owner lock spans both actions. Two Work Orders can
validate against the same 20 kg residual; atomic increments alone do not make the prior allocation check
serializable.

---

## 7. Stage 6 — transfer customer and company material to WIP

**STE-IN-WIP-0001**, purpose **Material Transfer for Manufacture**, carries both requirements. Generic
Stock Entry always builds every source SLE before every target SLE
(`stock/doctype/stock_entry/stock_entry.py:977-1120`):

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-CUST / Beta Custody | **−20** | **0.00** |
| 2 | RM-ALPHA / Raw | **−5** | **−30.00** |
| 3 | RM-CUST / WIP | **+20** | **0.00** |
| 4 | RM-ALPHA / WIP | **+5** | **+30.00** |

The customer Item must source from the SCIO customer warehouse and cannot exceed the Work Order
required/reserved quantity (`controllers/subcontracting_inward_controller.py:161-227`). The company
Item uses ordinary Work Order transfer policy.

Only AlphaCo value posts to GL. After `process_gl_map` merges the target-account clearing pair:

| Account | Debit | Credit |
|---|---:|---:|
| WIP Inventory | **30.00** | |
| Raw Materials Inventory | | **30.00** |
| **Total** | **30.00** | **30.00** |

RM-CUST has physically moved, but contributes no company asset movement or GL. This is where the owner
proxy is weakest: the zero-valued 20 kg now resides in ordinary `WIP - A`, whose Bin and valuation state
are keyed only by Item and Warehouse. The SCIO/WO/SRE links remember why it is there; the stock stream
itself does not say BetaCo owns it.

---

## 8. Stage 7 — Manufacture 10 FG

### 8.1 Consumption and output SLEs

The Manufacture entry consumes transferred Work Order residuals. SCIO-specific validation checks
customer consumption against Work Order transferred minus consumed quantity when transfer is enabled;
with `skip_transfer` it instead checks SCIO received minus returned and forces the customer Warehouse as
source (`controllers/subcontracting_inward_controller.py:228-383`).

**STE-IN-MFG-0001** consumes RM-CUST 20 and RM-ALPHA 5, completes JC-IN-0001 for 10, capitalises operation
cost 20, and receives 10 FG-CUST:

```text
customer material company value = 20 × 0 = 0
company material value          = 5 × 6 = 30
operation cost                  = 20
FG incoming value               = 50, or 5 per FG
```

Exact source-before-target SLEs are:

| SLE order | Item / warehouse | Qty | SVD |
|---:|---|---:|---:|
| 1 | RM-CUST / WIP | **−20** | **0.00** |
| 2 | RM-ALPHA / WIP | **−5** | **−30.00** |
| 3 | FG-CUST / Inward Delivery | **+10** | **+50.00** |

The customer memo value 80 is deliberately absent. Adding it would recognise an AlphaCo asset and cost
for property AlphaCo never owned.

### 8.2 Exact GL proof

The common stock composer posts every non-zero SLE to its inventory account and the opposite clearing
account (`stock/services/base_stock_gl_composer.py:27-102`). Stock Entry then adds the operation-cost
source pair (`stock/doctype/stock_entry/services/gl_composer.py:13-53`,
`stock/doctype/stock_entry/services/gl_composer.py:189-274`). Before account merging, the worked rows are:

| Leg | Account | Debit | Credit |
|---|---|---:|---:|
| Company RM issue | WIP/Manufacturing Clearing | 30.00 | |
| Company RM issue | WIP Inventory | | 30.00 |
| FG receipt | FG Inventory | 50.00 | |
| FG receipt | WIP/Manufacturing Clearing | | 50.00 |
| Operation allocation | WIP/Manufacturing Clearing | 20.00 | |
| Operation source | Conversion Labour/Machine | | 20.00 |
| **Total** | | **100.00** | **100.00** |

The three clearing rows net to zero, leaving the economic journal:

| Account | Debit | Credit |
|---|---:|---:|
| FG Inventory | **50.00** | |
| WIP Inventory | | **30.00** |
| Conversion Labour/Machine | | **20.00** |
| **Total** | **50.00** | **50.00** |

Thus inventory GL equals stock value delta exactly: FG debit 50 equals output SLE SVD +50; WIP credit
30 equals AlphaCo RM issue SVD −30. RM-CUST SVD and GL are both zero. Standard Cost would keep the same
SLE→inventory authority but add actual-versus-standard Manufacturing Variance.

### 8.3 Projection updates

After stock/GL posting the inward callback updates SCIO material consumption, creates child rows for any
extra company material, updates secondary-output projections, recomputes FG production from submitted
Work Orders and refreshes status (`controllers/subcontracting_inward_controller.py:798-1017`,
`subcontracting/doctype/subcontracting_inward_order_item/subcontracting_inward_order_item.py:39-52`).
Here:

| SCIO projection | Value |
|---|---:|
| RM-CUST consumed | 20 |
| RM-ALPHA consumed | 5 |
| FG produced | 10 |
| FG process loss | 0 |
| `per_produced` | 100% |
| status | Produced |

The Manufacture Stock Entry/detail, its SLE identities and value deltas, and its GL are evidence. These
SCIO quantities are mutable summaries over that evidence.

---

## 9. Stage 8 — gross delivery, customer FG return and second delivery

### 9.1 First delivery: 6 FG

There is no Delivery Note. `make_subcontracting_delivery` builds a source-only Stock Entry from the SCIO
output warehouse. Normally its proposal is:

```text
min(ordered 10, produced 10) - delivered 0 = 10
```

We submit 6. If overproduced delivery is enabled, the builder incorrectly proposes cumulative
`produced_qty` rather than produced minus delivered; server validation independently recalculates the
maximum (`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:440-499`,
`controllers/subcontracting_inward_controller.py:490-572`).

**STE-IN-DEL-0001** posts:

| Evidence | Qty / value |
|---|---:|
| FG SLE, Inward Delivery | **−6 / −30.00** |
| Delivery Expense debit | **30.00** |
| FG Inventory credit | **30.00** |

The GL balances 30/30 and inventory GL equals SLE SVD. SCIO `delivered_qty` becomes 6; it is gross and
will not be reduced by a return.

### 9.2 BetaCo returns 2 FG

`make_subcontracting_return` proposes `delivered_qty - returned_qty`, creates a target-only
**Subcontracting Return**, and leaves the warehouse for the user
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:501-559`). It does
not link the new incoming layer to the original delivery SLE or force the original rate.

For a true worked reversal we select `Inward Delivery - A` and explicitly use 5.00:

| Evidence | Qty / value |
|---|---:|
| FG SLE, Inward Delivery | **+2 / +10.00** |
| FG Inventory debit | **10.00** |
| Delivery Expense credit | **10.00** |

The GL balances 10/10. At zero valuation ERPNext would instead receive two FG with SVD 0 and no GL,
leaving quantity and value asymmetrical. The controller explicitly allows a zero valuation rate for
FG output/return rows (`controllers/subcontracting_inward_controller.py:349-365`).

After the return:

```text
gross delivered = 6
returned         = 2
net with customer = 4
per_delivered    = 6 / 10 = 60%
per_returned     = 2 / 6 = 33.33%
status           = Produced        (production is 100%; delivery is not)
```

### 9.3 Second delivery: the remaining gross 4

The normal builder ignores the return and proposes:

```text
min(ordered 10, produced 10) - gross delivered 6 = 4
```

**STE-IN-DEL-0002** posts FG `−4 / −20`, `Dr Delivery Expense 20 / Cr FG Inventory 20`. Final physical
and accounting position is:

| Measure | Value |
|---|---:|
| produced | 10 FG / 50.00 |
| gross delivered | 10 FG / 50.00 outgoing |
| customer FG returned | 2 FG / 10.00 incoming |
| **net with BetaCo** | **8 FG / 40.00** |
| AlphaCo custody after return | 2 FG / 10.00 |
| SCIO status | **Delivered** |

Across both deliveries and the return, debits and credits are each 60.00; after netting, `Dr Delivery
Expense 40 / Cr FG Inventory 40`. Combined with manufacture, AlphaCo still holds the returned FG asset
10. There is no customer-facing fulfilment document saying BetaCo net-accepted eight units.

---

## 10. Stage 9 — Sales Invoice for service and AlphaCo material

### 10.1 Mapper and billable material

The normal Sales Order mapper carries SVC-INWARD. For a subcontracted Sales Order it additionally queries
submitted SCIO received-item children where `is_customer_provided_item=0` and computes:

```text
billable RM-ALPHA = max(required_qty 5, consumed_qty 5) - billed_qty 0 = 5
```

It appends RM-ALPHA and runs ordinary Item selection/pricing
(`selling/doctype/sales_order/mapper.py:516-555`). RM-CUST is correctly excluded. Its memo cost 80 is
neither revenue nor company COGS.

**SI-IN-0001** contains:

| Invoice row | Qty × selling rate | Amount | Link |
|---|---:|---:|---|
| SVC-INWARD | 10 × 15 | **150.00** | Sales Order Item |
| RM-ALPHA | 5 × 8 | **40.00** | SCIO received-item child |
| **Total** | | **190.00** | |

The Sales Invoice validates each company-material row against the same
`max(required, consumed) - billed` ceiling (`accounts/doctype/sales_invoice/sales_invoice.py:917-959`).
A subcontracted invoice forces `update_stock=0`, so it cannot issue the already-consumed RM-ALPHA a
second time (`accounts/doctype/sales_invoice/sales_invoice.py:1178-1197`).

With no tax, discount or currency difference its exact economic GL is:

| Account | Debit | Credit |
|---|---:|---:|
| Accounts Receivable — BetaCo | **190.00** | |
| Inward Conversion Service Revenue | | **150.00** |
| Company Material Revenue | | **40.00** |
| **Total** | **190.00** | **190.00** |

There is no SLE and no new COGS: the company material cost entered FG at Manufacture and left through
Subcontracting Delivery. Invoice submit increments SCIO RM-ALPHA `billed_qty` by 5; cancellation
subtracts it (`accounts/doctype/sales_invoice/sales_invoice.py:1134-1153`). A Sales Invoice return exits
that method immediately, so a credit note does **not** release SCIO `billed_qty`; cancelling the original
invoice does.

### 10.2 Commercial/physical mismatch remains visible

ERPNext can invoice all ten service units even though two FG were returned and net customer fulfilment is
eight. That may be contractually correct—service could be earned on attempted conversion—or it may
require a credit. The system stores no explicit acceptance/return allocation joining commercial service,
company-material sale and net FG obligation. Those meanings are inferred from separate mutable
counters.

---

## 11. Exact percentage and status edge cases

SCIO separately `db_set`s six ratios
(`subcontracting/doctype/subcontracting_inward_order/subcontracting_inward_order.py:80-131`):

```text
RM received % = customer received / customer required
RM returned % = customer returned / customer received
produced %    = accepted FG produced / ordered FG
process loss % = process loss / accepted FG produced
 delivered %  = gross FG delivered / ordered FG
returned %    = FG returned / gross FG delivered
```

For the worked order:

| Stage | RM received | RM returned | Produced | Delivered | FG returned | Status |
|---|---:|---:|---:|---:|---:|---|
| SCIO submit | 0% | 0% | 0% | 0% | 0% | Open |
| receive 22 | **110%** | 0% | 0% | 0% | 0% | Ongoing |
| return RM 2 | **110%** | **9.09%** | 0% | 0% | 0% | Ongoing |
| manufacture 10 | 110% | 9.09% | **100%** | 0% | 0% | Produced |
| deliver 6, return 2 FG | 110% | 9.09% | 100% | **60%** | **33.33%** | Produced |
| deliver remaining 4 | 110% | 9.09% | 100% | **100%** | **20%** | **Delivered** |

The final status is Delivered because `per_delivered == 100`, even though net delivery is eight. Status
priority creates a sharper edge case:

```text
ordered 10; deliver 1; return that 1
per_delivered = 10%; per_returned = 100%
status = Returned
```

The whole order becomes terminal Returned while nine units were never delivered. Conversely, delivering
all ten and receiving two back remains Delivered because returned is only 20% and gross delivery stays
100%.

A Work Order can complete with nine accepted FG plus one process-loss unit. SCIO then reports
`per_produced=90%` and `per_process_loss=1/9=11.11%`, not loss/gross attempt 10%, so production and SCIO
completion answer different questions. Imported/malformed zero required or ordered quantities can also
divide by zero because raw-received, produced and delivered denominators are unguarded.

Doc 38's **Invariant M53** replaces these independent gross ratios with material custody, attempted
production, accepted yield, loss, gross delivery, customer return, net delivery and billing as separate
measures; terminal status derives from net obligations
([doc 38 §13.6](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md#136-percentages-and-status)).

---

## 12. Complete write and balance trace

Counts omit Version rows, serial/batch bundles, repost requests, Job Card time-log details, generic
Payment Ledger rows and reservation internals. GL counts are post-merge economic rows under the stated
account setup.

| Stage | Primary document/children | SLE | GL | Important projections |
|---|---|---:|---:|---|
| SO submit | SO 1 + Item 1 | 0 | 0 | SO status |
| SCIO submit | SCIO 1 + Service 1 + FG 1 + Received Item 2 | 0 | 0 | SO subcontracted 10, SCIO Open |
| Receive customer RM 22 | SE 1 + Detail 1 + SRE 1 | **1** | **0** | received 22, memo rate 4, Ongoing |
| Return surplus RM 2 | SE 1 + Detail 1 | **1** | **0** | returned 2, reservation delivered 2 |
| WO + Job Card | WO 1 + Required 2 + Operation 1 + JC 1 | 0 | 0 | work-order allocation 20, reservations |
| WIP transfer | SE 1 + Detail 2 | **4** | **2** | transferred/consumed reservation progress |
| Manufacture 10 | SE 1 + Detail 3 + Additional Cost 1 | **3** | **3 economic / 6 unmerged** | consumed, produced, JC manufactured, Produced |
| Delivery 6 | SE 1 + Detail 1 | **1** | **2** | gross delivered 6 |
| FG return 2 | SE 1 + Detail 1 | **1** | **2** | returned 2; gross delivered unchanged |
| Delivery 4 | SE 1 + Detail 1 | **1** | **2** | gross delivered 10; status Delivered |
| Sales Invoice | SI 1 + Item 2 | 0 | **3** | RM-ALPHA billed 5, receivable 190 |
| **Posted total** | | **12 SLE** | **14 economic GL** | many direct aggregate writes |

The stock/GL proof across value-bearing stock stages is:

```text
WIP transfer:       Dr WIP 30                  / Cr Raw Inventory 30
Manufacture:        Dr FG Inventory 50         / Cr WIP 30 + Cr Operation 20
Delivery/return net: Dr Delivery Expense 40    / Cr FG Inventory 40
Ending position:    Dr FG Inventory 10 + Dr Delivery Expense 40
                    = Cr Raw Inventory 30 + Cr Operation source 20
```

Customer RM quantity moves `+22 -2 -20 +20 -20 = 0` across receipt, return, WIP transfer and consumption,
and every one of those SVDs is zero. Its 80 memo cost never enters the company balance proof.

### 12.1 Evidence versus projection

| Representation | Classification |
|---|---|
| Submitted Sales Order | commercial service authorisation |
| SO Item `subcontracted_qty` | mutable SCIO-allocation projection |
| Submitted SCIO and requirement children | service/production authorisation; ownership still inferred |
| Receive/return Stock Entry + Detail | customer-custody command evidence |
| SLE Item, warehouse, quantity, voucher/detail, bundle | physical custody evidence; **no owner field** |
| Customer receipt SLE value 0 | company valuation policy, not proof of BetaCo title |
| `customer_provided_item_cost` / SCIO RM rate | mutable memorandum projection |
| Stock Reservation Entry and serial/batch lineage | tracked allocation evidence; owner still absent |
| Submitted Work Order / Job Card | production authorisation and execution evidence |
| Transfer/Manufacture/Delivery/Return Stock Entry + Detail | production/custody command evidence |
| Manufacture input/output SLE identity and quantity | physical conversion evidence |
| SLE running rate, queue and SVD | mutable valuation projection rewritten by repost |
| GL Entry | accounting evidence in meaning; physical rows can be replaced by repost |
| SCIO received/work-order/consumed/produced/delivered/returned/billed fields | mutable projections |
| SCIO percentages/status | mutable presentation projections with gross/net defects |
| Sales Invoice | commercial service/material claim and receivable evidence |

The strongest audit path is:

```text
SO service Item → SCIO service/FG/BOM requirement
  → customer receipt Detail → zero-valued custody SLE → SRE lot lineage
  → Work Order requirement → Job Card → WIP transfer Detail/SLE
  → Manufacture input/output Detail/SLE → stock GL
  → Subcontracting Delivery/Return Detail/SLE → stock GL
  → Sales Invoice service + AlphaCo RM line → revenue/receivable GL
```

Legal ownership cannot be reconstructed solely from that stock path; it also needs mutable Item and
Warehouse metadata plus the assumption that zero valuation means customer title.

---

## 13. Submit ordering, races and safe cancellation

### 13.1 Evidence/projection ordering and unlocked ceilings

Stock Entry submit performs purpose callbacks and reservation changes, writes SLE/Bin, writes GL and
reposts future valuation, then invokes the inward callback that mutates SCIO children/status.
Cancellation reverses stock/GL/reservations before the final inward projection reversal
(`stock/doctype/stock_entry/stock_entry.py:274-405`). Transaction rollback protects ordinary failures,
but it does not serialize competing allocators.

No SCIO/SO owner lock spans:

- SO service residual → SCIO allocation → `subcontracted_qty` save;
- received-minus-returned customer RM → Work Order allocation;
- Work Order transferred residual → Manufacture consumption;
- produced residual → delivery or delivered residual → return;
- company-material billable residual → Sales Invoice;
- dynamic additional RM/secondary child lookup → insert.

Delivery/return counters use SQL `field + delta`, but maximum validation happened earlier. Company-RM
billing validates first and updates later. Dynamic rows use `count + 1`; the memo weighted average is an
unlocked absolute write. These are the shared races catalogued by doc 38 §15 and **Invariant M55**.

### 13.2 Safe operational reversal

Reverse the worked chain in dependency order:

1. **Payment/allocation and Sales Invoice.** Cancel downstream payment evidence first, then SI-IN-0001.
   This releases RM-ALPHA `billed_qty`; a credit note alone does not. That ordering avoids leaving a
   billed projection after consumption is reversed, but ERPNext does not enforce it for this normal BOM
   material.
2. **FG return and deliveries.** Cancel STE-IN-RET-0001 first, then delivery entries newest first.
   Delivery cancellation rejects a state in which returned exceeds remaining gross delivered.
3. **Manufacture.** Cancel STE-IN-MFG-0001 only after all delivered output is reversed. Explicit guards
   prevent surviving produced/secondary quantity falling below delivered quantity. The billed-versus-
   consumed guard filters `is_additional_item=1`, so it protects dynamically added company material but
   not worked BOM row RM-ALPHA; cancelling Manufacture first could leave `billed_qty=5` and
   `consumed_qty=0` (`controllers/subcontracting_inward_controller.py:618-681`).
4. **Job Card and WIP transfer.** Cancel submitted Job Card execution after Manufacture, then cancel
   STE-IN-WIP-0001. Generic Stock Entry cancellation reverses target-before-source because it reverses
   the source-first SLE list (`stock/doctype/stock_entry/stock_entry.py:977-993`).
5. **Work Order.** Cancel after every linked submitted Stock Entry is gone; it reverses SCIO
   `work_order_qty` and reservation projections.
6. **Customer RM surplus return, then receipt.** Cancel STE-IN-RMRET-0001, then STE-IN-RCV-0001. Receipt
   cancellation refuses to leave `received - returned` below surviving Work Order allocation
   (`controllers/subcontracting_inward_controller.py:596-616`).
7. **SCIO.** Cancel after all stock/production/invoice links are gone; this subtracts the SO
   `subcontracted_qty` projection.
8. **Sales Order.** Cancel last.

Closed/on-hold orders must be reopened before linked stock cancellation. Generic linked-document,
negative-stock, serial/batch and future-SLE dependencies can add blockers beyond these explicit guards.

---

## 14. The same scenario in our owner-dimension design

### 14.1 Owner and custodian are first-class

Every stock lot/move/allocation carries at least:

```text
inventory_owner = BetaCo or AlphaCo
custodian        = AlphaCo
custody_location = warehouse
contract         = SCIO authorisation
requirement_id   = exact BOM requirement
valuation_policy = company_asset | owner_memorandum
```

Receiving RM-CUST creates an immutable `owner=BetaCo, custodian=AlphaCo` custody move for 22 and a
separate declared-cost observation `22 × 4 = 88`. Company inventory GL remains zero because
`valuation_policy=owner_memorandum`, not because ownership is guessed from a zero rate. Returning 2 and
moving 20 to WIP preserve the BetaCo owner automatically. A generic transfer cannot erase or change it.
An ownership change, if the contract ever requires one, is an explicit authorised event.

This owner must partition stock balances, valuation layers, serial/batch identity, reservations and
negative-stock checks. The current target schema's `stock_move`, valuation state, stock balance and
reservation keys are still Item/Warehouse based, so implementing doc 38's owner design requires adding
that dimension rather than relying on prose alone (`docs/design/FINAL-SCHEMA.md` §4).

### 14.2 One immutable conversion

Manufacture commits one conversion event:

```text
inputs:
  BetaCo RM-CUST 20, memorandum value 80, company value 0
  AlphaCo RM-ALPHA 5, realised company value 30
  AlphaCo operation-cost source 20
output:
  FG-CUST 10, company-book value 50
```

Input allocations, tracked units, output lots, cost sources, stock value deltas and balanced GL commit
under one conversion ID. Contract policy explicitly says whether output title belongs to BetaCo at
completion or transfers on delivery; it is not inferred from the output warehouse. Repost may recompute
company valuation projections, never owner/allocation edges or the declared customer cost observation.

### 14.3 Customer-facing net fulfilment

Delivery is a customer fulfilment event referencing exact output lots and the ownership/acceptance
policy. The return references the original delivery layer, so its quantity, rate and owner cannot drift.
After gross delivery 10 and return 2 the obligation projection is net 8, not Delivered. Commercial
service and AlphaCo-material billing each allocate to that contract under explicit policy and unique
idempotency keys.

Evidence commits before projectors rebuild received, returned, allocated, consumed, produced, gross
delivered, net accepted and billed views. Every ceiling is checked and inserted under one deterministic
contract/requirement lock. This implements doc 38 invariants **M52–M55**: explicit ownership, net inward
fulfilment, immutable subcontract posting and serializable allocation.

---

## 15. Side-by-side

| Question | ERPNext | Ours |
|---|---|---|
| Customer ownership | inferred from Item/Warehouse and zero value | immutable owner on lot, move, reservation and allocation |
| Warehouse meaning | doubles as custody and ownership proxy | custody location only |
| Customer cost | mutable weighted SCIO memo rate | immutable owner-declared cost observation |
| Company valuation | forced zero receipt rate | explicit non-company-asset valuation policy |
| Cross-company custody | customer tag checked; company not checked at SCIO boundary | owner/custodian/company contract constraint |
| SO service residual | mutable `subcontracted_qty`, read/check/write | unique bounded service allocation under source lock |
| Customer receipt | target-only SLE plus SRE | owner-aware custody move plus exact tracked allocation |
| Surplus return | builder can include company/negative rows | positive residual for exact owner/requirement only |
| Work Order ceiling | aggregate residual by Item, no owner lock | locked requirement allocation identity |
| WIP transfer | owner disappears from stock key | owner preserved through location change |
| Manufacture value | customer quantity at zero; company RM/operation capitalised | same accounting intent, explicit ownership and cost-source allocations |
| Job Card | ordinary operation execution | same execution evidence linked to immutable conversion |
| Delivery | internal Stock Entry; no customer fulfilment document | customer-facing lot/acceptance event |
| FG return valuation | warehouse/rate selected anew | references original delivery layer and policy |
| Company RM billing | `max(required, consumed)-billed` unlocked | unique commercial allocation to consumed AlphaCo input |
| Credit note | does not reduce SCIO `billed_qty` | compensating billing allocation updates net claim |
| Status | gross ratios; 10 delivered/2 returned is Delivered | net obligation and acceptance state |
| Counters | many direct mutable child/percentage writes | idempotent projections after evidence |
| Concurrency | read-check-write ceilings, partial SQL deltas | deterministic owner lock and non-negative residual constraints |

---

## 16. Findings and invariants exercised

1. **Customer material enters quantity but not AlphaCo value.** Receipt, transfer and consumption SLEs
   move 22/20 kg while every customer-material SVD and GL amount remains zero.
2. **Memo cost is not valuation.** The declared 4.00 rate records 88 received and 80 consumed for
   reference; FG company value is only company RM 30 plus operation cost 20.
3. **Custody is not ownership.** The customer Warehouse proxy disappears when material moves to WIP,
   because SLE/Bin/valuation/reservation keys have no owner dimension.
4. **Ordinary manufacturing accounting remains coherent.** Manufacture output inventory 50 equals its
   SLE SVD and balances company RM 30 plus operation source 20.
5. **Delivery is gross, not net fulfilment.** Delivering ten and receiving two back leaves eight with the
   customer but status Delivered; returning one partially delivered unit can mark the whole order
   Returned.
6. **FG return valuation is not tied to delivery.** The worked 5.00 reversal is user-controlled; zero or
   current valuation can produce a different accounting result.
7. **Billing separates customer and company material.** SI bills service 150 and AlphaCo RM 40, never
   RM-CUST; it must not update stock.
8. **Credit and cancellation differ.** A credit note does not release SCIO company-material
   `billed_qty`, while original invoice cancellation does. Manufacture cancellation's billed-versus-
   consumed guard covers additional company rows only, so a normal billed BOM row can be left with
   `billed_qty > consumed_qty`.
9. **Most progress is projection.** Submitted stock/production/invoice details are the command chain;
   SCIO ratios and counters can drift and use incompatible gross/net meanings.
10. **The weak boundary is allocation concurrency.** SO, RM, WO, delivery/return and billing residuals
    are validated without one contract-owner lock.

This scenario exercises doc 38 invariants **M41–M43**, **M47**, **M49–M55**: command identity,
commercial/physical conservation, actual-cost authority, tracked-unit continuity, stock projection,
stock/GL bridge, evidence-before-projection, explicit ownership, inward fulfilment semantics, immutable
posting and serializable allocation. It also reuses **F1** (balanced vouchers) and **F2** (inventory GL
equals stock value delta) from S04.

---

Cross-references: **[S01](S01-order-to-cash.md)** (Sales Order, invoice and return concepts),
**[S07](S07-make-to-order-manufacturing.md)** (Work Order, Job Card, WIP, loss and manufacturing GL),
**[S08](S08-supplier-subcontracting.md)** (the opposite supplier-custody ownership direction);
**[doc 02](../logic/02-stock-ledger-and-valuation.md)** (valuation/repost),
**[doc 03](../logic/03-stock-gl-bridge.md)** (stock→GL),
**[doc 16](../logic/16-stock-reservation-picking-warehouse.md)** (reservation/Warehouse/Bin),
**[doc 17](../logic/17-item-uom-variants-batch-reorder.md)** (tracked units),
**[doc 30](../logic/30-upstream-trade-and-parties.md)** (Sales Orders and parties),
**[docs 33–37](../logic/33-bom-costing-explosion-and-update-jobs.md)** (BOM through production stock/GL),
**[doc 38](../logic/38-subcontracting-orders-transfer-consumption-receipt-and-gl.md)** (complete supplier
and inward source trace), and `docs/design/FINAL-SCHEMA.md` (target stock/allocation schema and the owner
dimension still required by M52).
