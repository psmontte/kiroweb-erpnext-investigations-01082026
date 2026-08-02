# 20 — Naming, Identity, and the Audit Trail

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Doc 09 §4 and §6 covered *why* string primary keys hurt (amend chains, rename cascades). This
document covers the naming machinery itself — because gapless, legally-compliant document
numbering is a genuine business requirement that we must satisfy *without* adopting Frappe's
model — plus the audit trail, which is the other half of "who did what to this record".

---

## 1. The eight naming strategies

`set_new_name` (`frappe/model/naming.py:144`) is the dispatcher. Read in order, because it is a
fall-through chain:

```python
doc.run_method("before_naming")
autoname = meta.autoname or ""
if autoname.lower() not in ("prompt", "uuid") and not frappe.flags.in_import:
    doc.name = None                                      # discard any client-supplied name

if is_autoincremented(doc.doctype, meta):                # :164
    doc.name = frappe.db.get_next_sequence_val(doc.doctype); return

if meta.autoname == "UUID":                              # :168
    ... uuid7() or validate a supplied UUID ...; return

if getattr(doc, "amended_from", None):                   # :180
    _set_amended_name(doc)
    if doc.name: return
elif meta.issingle:
    doc.name = doc.doctype                               # :186

if not doc.name: set_naming_from_document_naming_rule(doc)   # :189
if not doc.name: doc.run_method("autoname")                  # :192
if not doc.name and autoname: set_name_from_naming_options(autoname, doc)   # :195
if not doc.name: doc.name = make_autoname("hash", doc.doctype)              # :199
doc.name = validate_name(doc.doctype, doc.name)              # :201
```

| Strategy | `autoname` value | Result |
|---|---|---|
| Autoincrement | `autoincrement` | `bigint` from a real DB sequence |
| UUID | `UUID` | `uuid7()` string (`frappe/model/naming.py:171`) |
| Amended | (any, with `amended_from`) | `_set_amended_name` (`frappe/model/naming.py:569`) |
| Single | `issingle` | `name = doctype` |
| Naming Rule | — | `Document Naming Rule` rows, by priority |
| Controller | — | the doctype's own `autoname()` method |
| Field | `field:<fieldname>` | `_field_autoname` (`frappe/model/naming.py:589`) |
| Prompt | `prompt` | user-supplied (`_prompt_autoname`, `frappe/model/naming.py:598`) |
| Format | `format:<template>` | `_format_autoname` (`frappe/model/naming.py:608`) with `get_param_value_for_match` (`:627`) |
| Naming series | `naming_series:` | `set_name_by_naming_series` (`frappe/model/naming.py:278`) |
| Expression | contains `#` | braced params + series (`frappe/model/naming.py:238`–`:262`) |
| Hash | fallback | `_get_timestamp_prefix()` + random (`frappe/model/naming.py:315`, `:330`) |

Eleven code paths to produce a primary key. Each is a different set of failure modes, and the
fall-through means a misconfiguration silently lands you in `hash`.

`get_default_naming_series` (`frappe/model/naming.py:501`),
`Meta.get_naming_series_options` (`frappe/model/meta.py:396`), and
`DocType.preserve_naming_series_options_in_property_setter`
(`frappe/core/doctype/doctype/doctype.py:786`) manage the option list — note that the *list of
allowed series* is preserved as a Property Setter (doc 18 §1.1), so upgrading the app does not
lose customer series.

### 1.1 The hash strategy is a probabilistic ID

`_get_timestamp_prefix` (`frappe/model/naming.py:315`):

```python
ts = int(time.time() * 10)           # deciseconds
ts = ts % (32**4)                    # "we can't get ordering over entire lifetime, so we wrap"
ts_part = base64.b32hexencode(ts.to_bytes(length=5, byteorder="big")).decode()[-3:].lower()
request_part = (get_trace_id() or "")[-1:]
return request_part + ts_part
```

plus `_generate_random_string(7)` (`frappe/model/naming.py:330`), truncated to 10 characters
total (`frappe/model/naming.py:308`).

The comments are refreshingly honest: the timestamp **wraps**, so hash names are only locally
time-ordered; the first character comes from the request/job trace id purely to reduce collisions
between parallel workers; base32 is used instead of base64 because **MySQL is case-insensitive**
(`frappe/model/naming.py:340`–`:341`), which halves the alphabet.

So: 10 characters, mixed deterministic/random, case-insensitive alphabet, wrapping clock. It is a
reasonable engineering compromise given a `varchar` PK — and it is strictly worse than a UUIDv7,
which Frappe now also supports (`autoname = "UUID"`, using `uuid7()`).

`_handle_hash_conflict` (`frappe/model/base_document.py:762`) exists to retry on collision.

### 1.2 Naming series: a counter row with a read-modify-write

`NamingSeries` (`frappe/model/naming.py:47`): `validate` (`:60`),
`generate_next_name` (`:83`), `get_prefix` (`:90`) with `fake_counter_backend` (`:98`),
`get_preview` (`:114`) with `fake_counter` (`:119`), `update_counter` (`:128`),
`get_current_value` (`:139`). Template parsing: `parse_naming_series`
(`frappe/model/naming.py:346`), `has_custom_parser` (`:410`),
`determine_consecutive_week_number` (`:415`).

The counter itself, `getseries` (`frappe/model/naming.py:428`):

```python
series = DocType("Series")
current = (frappe.qb.from_(series).where(series.name == key).for_update().select("current")).run()
if current and current[0][0] is not None:
    current = current[0][0]
    frappe.db.sql("UPDATE `tabSeries` SET `current` = `current` + 1 WHERE `name`=%s", (key,))
    current = cint(current) + 1
else:
    frappe.db.sql("INSERT INTO `tabSeries` (`name`, `current`) VALUES (%s, 1)", (key,))
    current = 1
return ("%0" + str(digits) + "d") % current
```

Assessment:

- The `SELECT ... FOR UPDATE` **does** lock the row, so concurrent increments on an *existing*
  series serialise correctly. Credit where due.
- The `INSERT` branch is **not** protected: two transactions creating the *first* number of a new
  series both find no row and both `INSERT`, producing a duplicate-key error on one (recoverable)
  or, on engines without the PK enforcing it, two rows.
- Crucially, **the number is allocated inside the document's transaction**. If the transaction
  rolls back, the counter increment rolls back with it — which is what makes the series gapless,
  and which also means **the `Series` row is a serialisation point for every insert of that
  doctype**. All invoices in a company contend on one row for the duration of the enclosing
  transaction, which for an ERPNext invoice includes GL posting, stock posting, and status
  updates. This is a real throughput ceiling, and it is the reason POS needed a separate
  document type with deferred posting (doc 13).

### 1.3 Counter reversion on delete

`revert_series_if_last` (`frappe/model/naming.py:446`). The docstring documents three template
shapes and the parsing gymnastics needed to recover `(prefix, count)` from a *formatted name*.
The interesting part is the comment at `:487`–`:492`:

> Prefix has placeholders (e.g. date parts .YYYY./.MM./.DD.). Resolving them against the current
> date breaks reverts when a document is deleted on a different day than it was created. The
> resolved prefix length is date-independent (YYYY is always 4 chars, MM 2, etc.), so resolve only
> to learn the length, then slice the prefix and counter from the document's own name.

```python
boundary = len(parse_naming_series(prefix.split("."), doc=doc))
count = cint(name[boundary:])
prefix = name[:boundary]
...
current = (frappe.qb.from_(series).where(series.name == prefix).for_update().select("current")).run()
if current and current[0][0] == count:
    frappe.db.sql("UPDATE `tabSeries` SET `current` = `current` - 1 WHERE `name`=%s", prefix)
```

So deleting the *most recently issued* document decrements the counter, and deleting any other
leaves a gap. Reconstructing the counter from a formatted string by **character offset** is
inherently brittle: it depends on every placeholder having a fixed rendered width, which the
comment asserts but nothing enforces (a custom parser, `has_custom_parser`,
`frappe/model/naming.py:410`, can render anything).

This is called from `delete_doc` (`frappe/model/delete_doc.py:238`,
`update_naming_series`) and from `TransactionDeletionRecord.update_naming_series`
(`setup/doctype/transaction_deletion_record/transaction_deletion_record.py:956`) with its own
`get_naming_series_prefix` (`:930`).

### 1.4 Amended names

`_set_amended_name` (`frappe/model/naming.py:569`), governed by
`Amended Document Naming Settings`
(`frappe/core/doctype/amended_document_naming_settings/amended_document_naming_settings.py:8`),
which chooses between suffixing (`INV-0001-1`, `-2`, …) and issuing a fresh series number.

Doc 09 §4 covered the consequence: the identifier encodes revision history as a string, and
child-row identities are regenerated, breaking every fulfilment link that pointed at them.

### 1.5 Uniqueness by search

`validate_name` (`frappe/model/naming.py:512`) and
`append_number_if_name_exists` (`frappe/model/naming.py:542`) — the latter probes for
`value`, `value-1`, `value-2`, … until one is free. A loop of `EXISTS` queries as a uniqueness
strategy.

`DocType.validate_name` (`frappe/core/doctype/doctype/doctype.py:1086`),
`validate_series` (`:1163`), `validate_empty_name` (`:1214`),
`validate_autoincrement_autoname` (`:1228`) with `get_autoname_before_save` (`:1231`),
`change_name_column_type` (`:1269`), and `patch_old_naming_expressions` (`:455`) round out the
validation surface. `DocType.make_amendable` (`:955`) and `make_repeatable` (`:976`) inject the
`amended_from` / `auto_repeat` fields.

---

## 2. The audit trail

Three overlapping mechanisms.

### 2.1 `Version` — field-level diffs

`frappe/core/doctype/version/version.py:15`. Written by
`Document.save_version` (`frappe/model/document.py:2024`):

```python
if (not getattr(self.meta, "track_changes", False)
        or self.doctype == "Version"
        or self.flags.ignore_version
        or frappe.flags.in_install
        or (not self._doc_before_save and frappe.flags.in_patch)):
    return
doc_to_compare = self._doc_before_save
if not doc_to_compare and (amended_from := self.get("amended_from")):
    doc_to_compare = frappe.get_doc(self.doctype, amended_from)
version = frappe.new_doc("Version")
if not doc_to_compare and not self.flags.updater_reference: return
if version.update_version_info(doc_to_compare, self):
    version.insert(ignore_permissions=True)
```

`update_version_info` (`frappe/core/doctype/version/version.py:31`), `set_diff` (`:49`),
`for_insert` (`:61`), `get_diff` (`:104`), `set_impersonator` (`:40`),
`_generate_html_diff` (`:234`), `_should_generate_html_diff` (`:251`),
`_as_string` (`:258`), `on_doctype_update` (`:230`).

Four problems:

1. **It is opt-in per doctype** (`meta.track_changes`), and a `Property Setter` can turn it off
   (doc 18 §1.1). Audit is a configurable feature, not a property of the system.
2. **`flags.ignore_version` skips it**, and internal code sets that flag.
3. **`db_set` does not write a Version.** `Document.db_set`
   (`frappe/model/document.py:1951`) writes the column directly. Every cached-counter update
   documented in Tranche A — `per_delivered_qty`, `outstanding_amount`, `advance_paid`,
   `status`, `clearance_date` — is therefore **invisible in the audit trail**. The fields that
   change most often on posted documents are the ones least audited.
4. The diff is stored as a **JSON blob** in `Version.data`, so "show me every change to
   `grand_total` on invoices last quarter" is a JSON scan, not a query.

`set_impersonator` (`:40`) is a nice touch: it records when an administrator acted as another
user.

### 2.2 `Audit Trail` — a comparison tool, not a log

`frappe/core/doctype/audit_trail/audit_trail.py:13`. Despite the name, this is a **report-style
doctype** that compares a document against its amendment chain:
`validate_fields` (`:36`), `validate_document` (`:45`), `compare_document` (`:54`),
`get_amended_documents` (`:75`), `get_diff_grid` (`:92`),
`get_rows_added_removed_grid` (`:104`), `get_rows_updated_grid` (`:112`),
`get_field_label` (`:129`), `filter_fields_for_gridview` (`:143`).

It reads `Version` rows and the amend chain and renders a grid. It stores nothing. So the
"audit trail" for a financial document is: *derive it, on demand, from opt-in field diffs plus
the amend chain* — with the counter updates missing (§2.1 point 3) and the pre-repost ledger state
gone (doc 15 §6.2).

### 2.3 The other trails

- `Deleted Document` — a JSON snapshot on delete (`frappe/model/delete_doc.py:226`), the only
  trace of a removed record (doc 09 §5).
- `Activity Log`, `Access Log`, `Error Log`, `Permission Log`,
  `Scheduled Job Log`, `API Request Log`, `Log Setting` / `Logs To Clear` — a family of log
  doctypes with a retention cleaner (`frappe/core/doctype/log_settings/`).
- `Comment` (`Document.add_comment`, `frappe/model/document.py:2179`), `_seen`
  (`add_seen`, `:2202`), `_liked_by`, `add_viewed` (`:2219`).
- `Document.reset_seen` (`frappe/model/document.py:1918`).

Log retention is a *global* Log Settings configuration, not a per-jurisdiction data-retention
policy — which matters where statute requires 7 or 10 years.

---

## 3. Our design

### 3.1 Identity: `uuid` PK, always

Decision D3/D5 restated with the numbering detail:

```sql
-- every business table
id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- v7 where ordering matters
doc_no  text,                                          -- human-facing, NULL until posted
UNIQUE (company_id, doc_type, doc_no)
```

- `id` is generated **client- or server-side, before any database round trip**, so offline
  capture (doc 13 §8) and idempotent retry work.
- `id` never changes. There is no `rename_doc` cascade (doc 09 §6), no
  `alter_primary_key` (doc 18 §2.3), no `append_number_if_name_exists` probe loop (§1.5).
- `doc_no` is a plain mutable column. Correcting a number is a one-row `UPDATE`.
- There are **two** naming strategies, not eleven (§1): `id` (always) and `doc_no` (assigned by a
  numbering rule at posting time).

### 3.2 Numbering: assigned at posting, from a scoped register

Gapless legal numbering is a real requirement, and it conflicts with holding a lock for a long
transaction (§1.2). We resolve it by **decoupling the number from the record's creation**:

```sql
CREATE TABLE numbering_rule (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES company(id),
    doc_type      doc_type NOT NULL,
    scope         numbering_scope NOT NULL,   -- 'company','company_year','company_month',
                                              -- 'warehouse','terminal','series'
    scope_ref_id  uuid,
    template      text NOT NULL,              -- 'INV-{YYYY}-{SEQ:5}'
    gapless       boolean NOT NULL DEFAULT true,
    valid_from    date NOT NULL DEFAULT '-infinity',
    valid_to      date NOT NULL DEFAULT 'infinity',
    EXCLUDE USING gist (
        company_id WITH =, doc_type WITH =, scope WITH =,
        coalesce(scope_ref_id,'00000000-0000-0000-0000-000000000000') WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&
    )
);

CREATE TABLE numbering_counter (
    rule_id     uuid NOT NULL REFERENCES numbering_rule(id),
    period_key  text NOT NULL,        -- '2026', '2026-08', '' — derived from scope
    next_value  bigint NOT NULL,
    PRIMARY KEY (rule_id, period_key)
);
```

Two modes, chosen per rule:

**`gapless = true`** — `UPDATE numbering_counter SET next_value = next_value + 1 ... RETURNING`
inside the posting transaction. Same serialisation as Frappe (§1.2), but:
- the lock is held only for the **posting** transaction, which in our design is a set of INSERTs
  into append-only tables plus one projection update — not GL + stock + status-counter recompute;
- the counter row is scoped (`company`, `year`, `terminal`, …), so contention is partitioned
  rather than global;
- the `INSERT`-first-number race (§1.2) is eliminated by seeding the counter row when the rule is
  created, and by `INSERT ... ON CONFLICT DO UPDATE` otherwise.

**`gapless = false`** — a PostgreSQL `SEQUENCE` per (rule, period), so allocation does not
serialise at all. Used where the law does not demand contiguity.

**No counter reversion.** `revert_series_if_last` (§1.3) exists because ERPNext allocates the
number at *insert* and lets drafts be deleted. We allocate at **posting**, and posted documents
are never deleted (doc 09 §7, invariant H1/H4). A draft that is abandoned never consumed a
number, so there is no gap to close and no character-offset parsing to get wrong.

`doc_no` for an amendment does not exist: corrections are reversal + new document (D5), and the
new document gets the next number in sequence, with `reverses_voucher_id` linking them. The
string-suffix amend chain (§1.4) is gone.

### 3.3 Audit: mandatory, structured, queryable

Three layers, none optional.

**Layer 1 — lifecycle events** (already specified, doc 09 §8 L5):

```sql
CREATE TABLE lifecycle_event (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id   uuid NOT NULL,
    resource     resource_kind NOT NULL,
    resource_id  uuid NOT NULL,
    from_state   lifecycle_state,
    to_state     lifecycle_state NOT NULL,
    actor_user_id uuid NOT NULL REFERENCES app_user(id),
    impersonated_by uuid REFERENCES app_user(id),
    at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    reason       text,
    request_id   uuid
);
```

Written by a `BEFORE UPDATE` trigger on the state column, so **it cannot be bypassed by a direct
`UPDATE`** — unlike `save_version`, which `db_set` skips entirely (§2.1 point 3).

**Layer 2 — field-level change log**:

```sql
CREATE TABLE field_change (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id   uuid NOT NULL,
    resource     resource_kind NOT NULL,
    resource_id  uuid NOT NULL,
    column_name  text NOT NULL,
    old_value    text,
    new_value    text,
    actor_user_id uuid NOT NULL,
    at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    request_id   uuid
) PARTITION BY RANGE (at);
```

Written by a generic `AFTER UPDATE` trigger generated per audited table from a
`audited_column` registry. Differences from `Version`:

- **Trigger-based, so `db_set`-equivalents are captured.** There is no application path that can
  write a column without producing a row.
- **One row per changed column**, not a JSON blob — so "every change to `grand_total` last
  quarter" is an indexed query (§2.1 point 4).
- **Partitioned by time**, so retention is `DETACH PARTITION`, not a delete job.
- Audit is on for every financial table by construction; it is not a `track_changes` flag
  (§2.1 point 1) and there is no `ignore_version` escape (point 2).

**Layer 3 — the ledgers themselves.** Because `gl_entry`, `stock_move`, `ar_ap_entry`,
`settlement`, `doc_link`, `bank_match`, and `budget_commitment` are append-only with
`reverses_*_id` (invariant H1/H2), the financial history *is* the audit trail. Nothing needs to be
reconstructed by diffing (§2.2), and the pre-correction state is still present — unlike a repost,
which deletes it (doc 15 §6.2).

### 3.4 Retention as policy, per jurisdiction

```sql
CREATE TABLE retention_policy (
    id            uuid PRIMARY KEY,
    company_id    uuid REFERENCES company(id),
    resource      resource_kind NOT NULL,
    retain_years  smallint NOT NULL,
    legal_basis   text NOT NULL,
    UNIQUE (company_id, resource)
);
```

Enforced by a scheduled task that detaches partitions older than the *maximum* applicable
retention, and refuses to remove anything a policy still covers. Contrast `Log Settings`, which is
one global row per log type (§2.3).

---

## 4. Summary

| ERPNext / Frappe mechanism | Verdict | Our replacement |
|---|---|---|
| Eleven naming strategies with fall-through to hash | **Reject** | `uuid` PK + one numbering-rule model (§3.1, §3.2) |
| 10-char hash PK with wrapping clock, base32 for MySQL case-insensitivity | **Reject** | `uuid` v7 |
| PK type mutable (`varchar`↔`bigint`↔`uuid`) | **Reject** | `uuid`, immutable |
| `Series` counter row locked for the whole posting transaction | **Partly keep** | scoped counters, allocated at posting only, or `SEQUENCE` when gaps are legal (§3.2) |
| Unprotected `INSERT` for a series' first number | **Reject** | pre-seeded counter + `ON CONFLICT DO UPDATE` |
| `revert_series_if_last` recovering a counter by character offset | **Reject** | number allocated at posting; nothing to revert (§3.2) |
| `append_number_if_name_exists` probe loop | **Reject** | `UNIQUE (company_id, doc_type, doc_no)` |
| Amend chain encoded in the identifier | **Reject** | `reverses_voucher_id` + stable `id`/`line_id` (doc 09 §4) |
| `Version` diffs, opt-in, JSON, skipped by `db_set` | **Reject** | trigger-written `field_change` rows (§3.3 layer 2) |
| `Audit Trail` as an on-demand comparison tool | **Reject** | append-only ledgers *are* the trail (§3.3 layer 3) |
| `Deleted Document` JSON snapshot | **Reject** | posted rows are never deleted (H4); drafts are soft-closed |
| Global `Log Settings` retention | **Reject** | `retention_policy` per company + resource (§3.4) |
| `set_impersonator` on Version | **Keep** | `lifecycle_event.impersonated_by`, `field_change` via the same request context |

---

Cross-references: doc 09 §4 and §6 (amend, rename), doc 13 §8 (offline numbering),
doc 18 (metadata, `alter_primary_key`), doc 19 (who may act), doc 15 (what reposting destroys),
doc 25 (platform spec), `docs/design/FINAL-SCHEMA.md`.
