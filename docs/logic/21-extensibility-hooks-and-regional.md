# 21 — Extensibility: Hooks, Overrides, and the Regional Overlay

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

This is the document that decides how much framework we write ourselves. Frappe's extensibility
model is the reason ERPNext can be extended by `payments`, `hrms`, `webshop`, and a dozen
regional packs without forking — and it is also the reason nothing about the system's behaviour
can be determined by reading one file.

`erpnext/hooks.py` is **754 lines**. Every one of them changes behaviour somewhere else.

---

## 1. How hooks resolve

`_load_app_hooks` (`frappe/__init__.py:1008`):

```python
hooks = {}
apps = [app_name] if app_name else get_installed_apps(_ensure_on_bench=True)
for app in apps:
    app_hooks = get_module(f"{app}.hooks")
    def _is_valid_hook(obj):
        return not isinstance(obj, types.ModuleType | types.FunctionType | type)
    for key, value in inspect.getmembers(app_hooks, predicate=_is_valid_hook):
        if not key.startswith("_"):
            append_hook(hooks, key, value)
return hooks
```

So a hook is **any module-level name in `<app>/hooks.py` that is not a module, function, class,
or underscore-prefixed**. There is no registry of valid hook names, no schema, and no validation:
a typo produces a hook nobody reads, silently.

`append_hook` (`frappe/__init__.py:1067`) defines the merge semantics:

```python
if isinstance(value, dict):
    target.setdefault(key, {})
    for inkey in value: append_hook(target[key], inkey, value[inkey])
else:
    target.setdefault(key, [])
    if not isinstance(value, list): value = [value]
    target[key].extend(value)
```

**Everything becomes a list, recursively.** Scalars are listified; dicts are merged key-by-key.
Consequences:

- **App install order determines execution order.** `get_installed_apps` returns the install
  sequence, so `hooks["doc_events"]["Sales Invoice"]["on_submit"]` is a list whose order depends
  on which app was installed first.
- A hook that is semantically a *single value* (`app_logo_url`, `website_route_rules`) still
  arrives as a list, and readers take `[0]` or `[-1]` by convention.
- **"Last installed app wins"** is the override convention — stated explicitly in
  `allow_regional` (§3): `frappe.get_attr(overrides[function_path][-1])`.

Caching (`get_hooks`, `frappe/__init__.py:1041`): request-cached when filtered by app,
site-cached in developer mode, otherwise `client_cache.get_value("app_hooks")`. So the hook map is
a cached dict built by importing every app's `hooks.py` and introspecting its namespace.

`get_doc_hooks` (`frappe/__init__.py:991`) resolves `doc_events` for a doctype;
`frappe.call` (`frappe/__init__.py:1136`) and `frappe.get_attr` do the dynamic dispatch —
**string-to-callable resolution at runtime**, so a renamed function breaks a hook with an
`AttributeError` at the moment the hook fires, not at import.

---

## 2. `doc_events` — the main extension point

`erpnext/hooks.py:368`. Structure: `{doctype_or_tuple: {event: [method_path, ...]}}`.
Called from `Document.run_trigger` (`frappe/model/document.py:1704`) via
`run_method` (`frappe/model/document.py:1681`) and the `hook` composer
(`frappe/model/document.py:2050`, with `compose`/`runner`/`composer` at `:2069`, `:2070`, `:2087`).

The interesting entries:

### 2.1 The wildcard

```python
"*": {
    "validate": [
        "erpnext.support.doctype.service_level_agreement.service_level_agreement.apply",
        "erpnext.setup.doctype.transaction_deletion_record.transaction_deletion_record.check_for_running_deletion_job",
        "erpnext.stock.doctype.company_restriction.company_restriction.validate_transaction_company",
    ],
},
```

(`erpnext/hooks.py:369`–`:376`)

**Three functions run on `validate` of every document in the system** — including `DocType`,
`Custom Field`, `Version`, and every log row. `check_for_running_deletion_job`
(`setup/doctype/transaction_deletion_record/transaction_deletion_record.py:1118`) is the
global "is a company deletion in progress" guard (doc 09 §5.1), and
`validate_transaction_company` is company restriction. So the multi-company guard that doc 19 §2.2
found on only three doctypes via `has_permission` is *also* applied here as a validation on
everything — two different mechanisms, different coverage, no single place to read the rule.

### 2.2 Tuple keys computed from module-level lists

```python
tuple(period_closing_doctypes): {
    "validate": "erpnext.accounts.doctype.accounting_period.accounting_period.validate_accounting_period_on_doc_save",
},
tuple(pre_submit_validation_doctypes): {
    "validate": "erpnext.accounts.utils.pre_submit_validation",
},
("Item", "Customer", "Supplier"): {
    "validate": "erpnext.stock.doctype.company_restriction.company_restriction.validate_allowed_companies",
},
```

(`erpnext/hooks.py:377`–`:385`)

`period_closing_doctypes` is a list defined earlier in the same file (just after the
`has_website_permission` block). So **which documents respect an accounting period is a Python
list in `hooks.py`** — not a property of the document, not a column, not a policy row. Adding a
new posting doctype without adding it to that list means it can post into a closed period.

Same shape for `pre_submit_validation_doctypes` → `accounts/utils.py:2774` (doc 09 §1.5(c)).

### 2.3 Regional logic wired in as document events

```python
"Sales Invoice": {
    "on_submit": ["erpnext.regional.italy.utils.sales_invoice_on_submit"],
    "on_cancel": ["erpnext.regional.italy.utils.sales_invoice_on_cancel"],
    "on_trash": "erpnext.regional.check_deletion_permission",
},
"Purchase Invoice": {
    "validate": [
        "erpnext.regional.united_arab_emirates.utils.update_grand_total_for_rcm",
        "erpnext.regional.united_arab_emirates.utils.validate_returns",
    ],
},
"Address": {"validate": ["erpnext.regional.italy.utils.set_state_code"]},
```

(`erpnext/hooks.py:409`–`:431`)

**Italian and UAE tax logic runs on every installation.** The functions themselves check the
company's country and return early — but they are always invoked, always imported, and always in
the call stack. `update_grand_total_for_rcm` *modifies `grand_total`* on a Purchase Invoice
during `validate` for UAE reverse-charge; a bug there affects the totals pipeline (doc 05)
globally.

### 2.4 Other notable hook families in `erpnext/hooks.py`

| Hook | Line | What it does |
|---|---|---|
| `override_whitelisted_methods` | `:60` | replaces a whitelisted API endpoint's implementation |
| `on_session_creation` | `:79` | `erpnext.portal.utils.create_customer_or_supplier` — **creates master data on login** |
| `advance_payment_receivable_doctypes` / `..._payable_doctypes` | `:561`, `:562` | the list that `get_advance_payment_doctypes` (`accounts/utils.py:2618`) reads — doc 11 §2.4 |
| `get_matching_queries` | `:631` | bank-reconciliation matchers (doc 14 §2) |
| `regional_overrides` | `:645` | §3 |
| `user_privacy_documents` | `:659` | GDPR field lists per doctype |
| `global_search_doctypes` | `:674` | search index membership + ordering |
| `ignore_links_on_delete` | `:718` | `["Tax Withholding Entry"]` — deliberately dangling references (doc 09 §5) |
| `additional_timeline_content` | `:722` | `{"*": [...]}` |
| `extend_bootinfo` | `:724` | payload injected into every session |
| `naming_series_variables` | `:449`–`:453` | `FY, TFY, ABBR, MM, DD, YY, YYYY, JJJ, WW` → `accounts/utils.py:1602` (doc 20 §1.2) |
| `auto_cancel_exempted_doctypes` | `:455` | see §2.5 |
| `scheduler_events` | `:468` | doc 22 |
| `permission_query_conditions`, `has_permission`, `has_website_permission` | `:312`, above it | doc 19 §2.2 |

### 2.5 `auto_cancel_exempted_doctypes` — a comment worth quoting

`erpnext/hooks.py:455`–`:466`:

```python
auto_cancel_exempted_doctypes = [
    # On cancel event Payment Entry will be exempted and all linked submittable doctype will get cancelled.
    # to maintain data integrity we exempted payment entry. it will un-link when sales invoice get cancelled.
    # if payment entry not in auto cancel exempted doctypes it will cancel payment entry.
    "Payment Entry",
    # Reverse ledger entries are created instead to ensure ledger immutability.
    "GL Entry",
    "Stock Ledger Entry",
    "Payment Ledger Entry",
    "Advance Payment Ledger Entry",
    # May be linked to Period Closing Voucher, but cancelled with custom logic in PCV.
    # This is better to avoid stale docs when cancelling PCV from backend.
    "Account Closing Balance",
]
```

Read by `get_exempted_doctypes` (`frappe/desk/form/linked_with.py:422`) and
`validate_linked_doc` (`frappe/desk/form/linked_with.py:391`), which feed
`cancel_all_linked_docs` (`frappe/desk/form/linked_with.py:371`) and
`SubmittableDocumentTree` (`frappe/desk/form/linked_with.py:56`).

Two things:

1. **Cancelling a document can cascade-cancel every submitted document that links to it**, walked
   as a tree (`get_all_children`, `frappe/desk/form/linked_with.py:76`;
   `get_next_level_children`, `:109`). The exemption list is the only brake.
2. The comment *"Reverse ledger entries are created instead to ensure ledger immutability"*
   confirms our reading in doc 09 §3.1: immutability is an intention expressed in a hook list, not
   an invariant. And the same file's `Accounts Settings.delete_linked_ledger_entries` path
   (`controllers/accounts_controller.py:433`–`:447`) deletes those very rows.

---

## 3. The regional overlay

`erpnext/__init__.py:133`:

```python
def allow_regional(fn):
    """Decorator to make a function regionally overridable"""
    @functools.wraps(fn)
    def caller(*args, **kwargs):
        overrides = frappe.get_hooks("regional_overrides", {}).get(get_region())
        function_path = f"{inspect.getmodule(fn).__name__}.{fn.__name__}"
        if not overrides or function_path not in overrides:
            return fn(*args, **kwargs)
        # Priority given to last installed app
        return frappe.get_attr(overrides[function_path][-1])(*args, **kwargs)
    return caller
```

with `get_region(company=None)` (`erpnext/__init__.py:118`) resolving the country from the
company (or a session default).

And the map, `erpnext/hooks.py:645`:

```python
regional_overrides = {
    "France": {"erpnext.tests.test_regional.test_method": "erpnext.regional.france.utils.test_method"},
    "United Arab Emirates": {
        "erpnext.controllers.taxes_and_totals.update_itemised_tax_data":
            "erpnext.regional.united_arab_emirates.utils.update_itemised_tax_data",
        "erpnext.accounts.doctype.purchase_invoice.purchase_invoice.make_regional_gl_entries":
            "erpnext.regional.united_arab_emirates.utils.make_regional_gl_entries",
    },
    "Saudi Arabia": {
        "erpnext.controllers.taxes_and_totals.update_itemised_tax_data":
            "erpnext.regional.united_arab_emirates.utils.update_itemised_tax_data"
    },
    "Italy": {
        "erpnext.controllers.taxes_and_totals.update_itemised_tax_data":
            "erpnext.regional.italy.utils.update_itemised_tax_data",
        "erpnext.controllers.accounts_controller.validate_regional":
            "erpnext.regional.italy.utils.sales_invoice_validate",
    },
}
```

### 3.1 Assessment

**What works.** The decorator is clean, the dispatch is cheap, and it lets a regional pack replace
a single function — including `make_regional_gl_entries`, i.e. **country-specific GL posting** —
without touching core code.

**What does not.**

1. **`get_region()` is evaluated with no arguments inside `caller`** (`erpnext/__init__.py:143`),
   so the region comes from a *session/default* company, **not from the document being
   processed**. In a multi-company installation spanning two countries, a function overridden for
   Italy can be applied to a UAE company's document (or not applied to an Italian one), depending
   on whose default company the session carries. For a tax calculation, that is a wrong-numbers
   bug, not a cosmetic one. Note `get_region` *accepts* a `company` argument — the decorator just
   does not pass it.
2. **Override granularity is whole-function replacement.** `update_itemised_tax_data` is replaced
   entirely for four countries. Two countries needing *different* additions to the same function
   cannot compose; the last-installed app wins.
3. **Only four countries and five functions** are in the map — the rest of the world's
   localisation lives in separate apps (`india_compliance`, etc.) that hook in via `doc_events`,
   `permission_query_conditions`, and `override_doctype_class` instead. So there is no single
   localisation mechanism; there are five.
4. **The override key is a fully-qualified Python path string.** Refactoring core (which v17 is
   doing extensively — see `docs/logic/README.md` on the `services/` extraction) breaks every
   regional pack silently, at call time.
5. The map is keyed by **country name as free text** (`"United Arab Emirates"`), matched against
   `Company.country`. A typo yields no override, no warning.

### 3.2 The regional field-injection path

Regional packs also add fields, via `create_custom_fields`
(`frappe/custom/doctype/custom_field/custom_field.py:328`) called from an installer hook — i.e.
**`ALTER TABLE` at app-install time** (doc 18 §2.4). `erpnext/regional/` and the various
`*_compliance` apps ship dictionaries of `Custom Field` definitions.

Combined with `regional_overrides`, this means a country pack = custom fields + function
replacements + doc_events + permission conditions + fixtures. Five mechanisms, applied globally,
gated by a country string.

---

## 4. Other override mechanisms

| Mechanism | Where | Scope |
|---|---|---|
| `override_doctype_class` | `hooks.py` | replaces the controller class for a doctype — `get_controller` (`frappe/model/base_document.py:116`), `import_controller` (`:131`), `_get_extended_class` (`:213`), `_create_extended_class` (`:248`) |
| `override_whitelisted_methods` | `erpnext/hooks.py:60` | replaces an HTTP endpoint's implementation |
| `Server Script` | database rows | Python (`DocType Event`, `API`, `Scheduler Event`, `Permission Query`) stored in the DB and `exec`'d |
| `Client Script` | database rows | JS injected into the form |
| `Notification` | database rows | condition-evaluated alerts, run from `run_notifications` (`frappe/model/document.py:1707`) with `_get_notifications` (`:1722`) and `_evaluate_alert` (`:1738`) |
| `Workflow` | database rows | overlays a state field (doc 09 §1.5(b)) |
| `Property Setter` / `Custom Field` | database rows | schema + metadata (doc 18 §4) |
| `Custom DocPerm` / `Custom Role` | database rows | permissions (doc 19 §2.1) |
| `jenv` | `hooks.py` | Jinja globals/filters for print formats and web pages |
| `fixtures` | `hooks.py` | rows exported/imported with the app |
| `extend_bootinfo` | `erpnext/hooks.py:724` | session payload |

`_get_extended_class` / `_create_extended_class`
(`frappe/model/base_document.py:213`, `:248`) implement **dynamic class construction**: the
controller's MRO is assembled at runtime from the base class plus every app's override. With
`_reduce_extended_instance` / `_reconstruct_extended_instance`
(`frappe/model/base_document.py:101`, `:110`) to make those runtime classes picklable for
background jobs.

That is genuinely clever engineering. It also means **`type(doc)` is not a class you can find in
any source file**, which makes static analysis, type checking, and IDE navigation
approximations — and it is why the codebase leans so heavily on string paths.

---

## 5. What this costs, measured

For a single `Sales Invoice.submit()`, the behaviour is determined by:

1. the `SalesInvoice` controller — plus any `override_doctype_class` in the MRO,
2. `AccountsController` / `SellingController` / `StatusUpdater` / `TransactionBase` /
   `Document` / `BaseDocument`,
3. `<doctype>/services/*.py` composers (v17 extraction),
4. `doc_events["*"]["validate"]` — 3 functions,
5. `doc_events[tuple(period_closing_doctypes)]["validate"]`,
6. `doc_events[tuple(pre_submit_validation_doctypes)]["validate"]`,
7. `doc_events["Sales Invoice"]["on_submit"]` — Italian regional,
8. `regional_overrides[get_region()]` for any `@allow_regional` function reached,
9. `Server Script` rows for `DocType Event` on Sales Invoice,
10. `Notification` rows,
11. `Workflow` state transitions,
12. `Property Setter` rows changing `reqd` / `read_only` / `allow_on_submit`,
13. `Custom Field` rows adding validated fields,
14. `Authorization Rule` rows (doc 09 §1.5(a)),
15. `Accounts Settings` / `Selling Settings` / `Stock Settings` singles (doc 18 §3.1).

Fifteen inputs, spread across Python files, `hooks.py` module namespaces, and eight database
tables, in an order partly determined by app install sequence. **This is the real reason ERPNext
is hard to reason about** — not any individual algorithm.

---

## 6. Our design

We need extensibility. We do not need *this* extensibility. Four mechanisms, each with a narrow,
declared contract.

### 6.1 Domain events, typed and ordered

```sql
CREATE TABLE domain_event (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id    uuid NOT NULL,
    event_type    event_type NOT NULL,        -- enum: 'sales_order.posted','invoice.reversed', ...
    resource      resource_kind NOT NULL,
    resource_id   uuid NOT NULL,
    payload       jsonb NOT NULL,
    occurred_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    request_id    uuid
);
CREATE TABLE event_subscription (
    id           uuid PRIMARY KEY,
    event_type   event_type NOT NULL,
    handler_key  text NOT NULL,          -- resolved from a compile-time registry, not a path string
    priority     smallint NOT NULL,
    company_id   uuid,                   -- NULL = all companies
    is_enabled   boolean NOT NULL DEFAULT true,
    UNIQUE (event_type, handler_key, coalesce(company_id,'00000000-0000-0000-0000-000000000000'))
);
```

- **`event_type` is an enum**, so a typo is a constraint violation, not a silent no-op (§1).
- **`priority` is explicit**, so ordering does not depend on install sequence (§1).
- **`handler_key` resolves through a compile-time registry** — a `match` over known keys — so a
  renamed function is a *compile error*, not a runtime `AttributeError` (§1).
- **Handlers are subscribers to committed events, not participants in the transaction.** The
  posting transaction writes `domain_event` rows; handlers run afterwards, idempotently, keyed by
  `domain_event.id`. This is the single biggest structural difference: an extension **cannot
  break posting**, cannot mutate `grand_total` mid-validate (§2.3), and cannot hold a lock.
- Anything that genuinely must run *inside* the transaction (a hard validation) is a
  **database constraint or a trigger**, written in a migration and reviewed — not a hook.

There is no `"*"` wildcard (§2.1). Cross-cutting concerns (tenancy, period control) are
constraints and policies, not per-document validations.

### 6.2 Policy rows instead of Python lists

Every `hooks.py` list that encodes a business rule becomes a table:

| ERPNext hook | Our table |
|---|---|
| `period_closing_doctypes` (§2.2) | `doc_type_config.respects_accounting_period boolean` |
| `pre_submit_validation_doctypes` (§2.2) | `approval_policy` rows (doc 19 §7.5) |
| `advance_payment_receivable_doctypes` / `..._payable` | `doc_type_config.advance_direction` |
| `auto_cancel_exempted_doctypes` (§2.5) | irrelevant — no cascade cancel; FK `RESTRICT` + explicit reversal (D5) |
| `ignore_links_on_delete` (§2.4) | irrelevant — FKs are enforced; nothing may dangle |
| `global_search_doctypes` | `search_config` rows |
| `naming_series_variables` | `numbering_rule.template` placeholders, a fixed documented set (doc 20 §3.2) |
| `user_privacy_documents` | `pii_column` registry, joined to `retention_policy` (doc 20 §3.4) |

`doc_type_config` is a small, fully-populated table describing each document type's structural
properties (submittable, posts GL, posts stock, respects period, advance direction). It is
migration-managed data, not free-form Python, and it is *queryable* — "which document types can
post to the GL?" is a `SELECT`.

### 6.3 Localisation: composable, per company, and data-driven

The regional problem is the most important one to get right, because it is where ERPNext's model
is weakest (§3.1). Our approach has three layers:

**Layer 1 — tax as data, not code.** Doc 05 established the totals pipeline. Our tax engine is
driven by:

```sql
CREATE TABLE tax_regime (
    id            uuid PRIMARY KEY,
    country_code  char(2) NOT NULL,           -- ISO 3166-1, not free text (§3.1 pt 5)
    code          text NOT NULL,
    valid_from    date NOT NULL,
    valid_to      date NOT NULL DEFAULT 'infinity',
    UNIQUE (country_code, code, valid_from)
);
CREATE TABLE tax_rule (
    id             uuid PRIMARY KEY,
    regime_id      uuid NOT NULL REFERENCES tax_regime(id),
    sequence       smallint NOT NULL,          -- explicit computation order
    basis          tax_basis NOT NULL,         -- 'net','net_plus_previous','previous_total','actual','quantity'
    applies_to     jsonb NOT NULL,             -- item category / party category / place-of-supply predicate
    rate           numeric(9,6),
    is_inclusive   boolean NOT NULL DEFAULT false,
    is_reverse_charge boolean NOT NULL DEFAULT false,
    account_id     uuid NOT NULL REFERENCES account(id),
    UNIQUE (regime_id, sequence)
);
```

`is_reverse_charge` as a **rule flag** replaces UAE's
`update_grand_total_for_rcm` monkey-patching `grand_total` in a global `validate` hook (§2.3).
Italy's itemised tax breakdown becomes a `tax_report_layout` row, not a replaced function.

**Layer 2 — company-scoped extension points.** Where code genuinely differs by jurisdiction
(e-invoicing formats, digital signatures, statutory report layouts), the extension is registered
**per company**:

```sql
CREATE TABLE company_extension (
    company_id    uuid NOT NULL REFERENCES company(id),
    extension_key text NOT NULL,          -- 'einvoice.it.sdi', 'einvoice.in.irn'
    config        jsonb NOT NULL,
    is_enabled    boolean NOT NULL DEFAULT true,
    PRIMARY KEY (company_id, extension_key)
);
```

This fixes §3.1 point 1 directly: **the extension is selected by the document's company**, never
by a session default. A group with an Italian and a UAE subsidiary gets correct behaviour for
both, in the same request, from the same worker.

**Layer 3 — additive, not replacing.** Extension points are *pipeline stages* with declared
inputs and outputs, so two jurisdictions' requirements compose (§3.1 point 2). An extension may
append a tax line, add a document attachment, or emit a statutory record; it may not replace the
totals algorithm.

### 6.4 No runtime code storage

`Server Script`, `Client Script`, and `Notification` conditions are `exec`'d/`eval`'d strings in
the database (§4). We do not reproduce this:

- **Server Script → removed.** Anything needing code goes through the event subscription
  registry (§6.1) and is deployed.
- **Notification conditions → a restricted expression language**, parsed into an AST and
  evaluated by an interpreter with no I/O, no attribute access, and a fixed function set. Stored
  as the parsed form, validated on save.
- **Client Script → removed.** UI behaviour is in the front end, deployed.

This is a deliberate reduction in flexibility, taken for one reason: user-authored code in a
database that holds financial records is a security and auditability problem we are not willing
to own (see doc 19 §3.3 for the permission-query variant of the same issue).

### 6.5 Controller composition

`override_doctype_class` and the dynamically constructed MRO (§4) are replaced by ordinary
composition: each document type has one concrete implementation; shared behaviour is a function
or a trait/interface, resolved at compile time. `type(doc)` is a class you can open in an editor.

---

## 7. Migration path for the four apps we parsed

Worth recording, since the catalog covers them:

| App | What it hooks into | Our equivalent |
|---|---|---|
| `payments` | `Payment Gateway` doctypes, `override_whitelisted_methods`, `Integration Request` | `payment_provider` + `payment_intent` tables; providers are deployed adapters selected by `company_extension` |
| `hrms` | `doc_events` on `Employee`/`Journal Entry`, its own module tree, `Salary Slip` → GL | a separate service publishing `domain_event` rows that the ledger consumes; no shared transaction |
| `webshop` | website hooks, `has_website_permission`, portal templates | separate front end over the API; RLS-scoped read models (doc 19 §7.1) |
| regional packs | `regional_overrides` + `create_custom_fields` + `doc_events` | `tax_regime`/`tax_rule` data + `company_extension` adapters (§6.3) |

---

## 8. Summary

| Frappe/ERPNext mechanism | Verdict | Our replacement |
|---|---|---|
| Hooks = any module-level name, no schema, no validation | **Reject** | typed `event_type` enum + compile-time handler registry (§6.1) |
| Order determined by app install sequence | **Reject** | explicit `priority` |
| String-path dynamic dispatch | **Reject** | compile-time resolution |
| `doc_events["*"]` running on every save | **Reject** | constraints and RLS for cross-cutting rules |
| Business rules as Python lists in `hooks.py` | **Reject** | `doc_type_config` and policy tables (§6.2) |
| Extensions running inside the posting transaction | **Reject** | post-commit subscribers to `domain_event` (§6.1) |
| Extensions able to mutate totals mid-`validate` | **Reject** | additive pipeline stages only (§6.3 layer 3) |
| `@allow_regional` with region from the *session* company | **Reject** | extension selected by the **document's** company (§6.3 layer 2) |
| Whole-function regional replacement | **Reject** | composable stages |
| Country as free-text key | **Reject** | ISO 3166-1 `char(2)` |
| Regional packs issuing `ALTER TABLE` at install | **Reject** | dimension slots + `ext_field` (doc 18 §5.2) |
| `Server Script` / `Client Script` (code in the DB) | **Reject** | deployed handlers; restricted expression AST for conditions (§6.4) |
| Runtime-constructed controller classes | **Reject** | compile-time composition (§6.5) |
| `auto_cancel_exempted_doctypes` cascade cancellation | **Reject** | no cascade; reversal is explicit (D5) |
| `Notification` alerts | **Keep, constrained** | condition AST + `domain_event` subscription |
| `fixtures` (app-shipped rows) | **Keep** | seed data in migrations |
| `jenv` (template globals) | **Keep** | template helper registry, compile-time |

---

Cross-references: doc 05 (taxes and totals — what regional overrides replace), doc 09 §1.5
(approval, `pre_submit_validation`), doc 18 (custom fields, settings),
doc 19 (permission hooks), doc 22 (scheduler events), doc 25 (platform spec),
`docs/design/FINAL-SCHEMA.md`.
