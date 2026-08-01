# 24 — The Reporting Framework

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Reporting is where an ERP is judged, and it is the read path that must respect the access model
(doc 19). Frappe's answer is five different report types, two of which execute code stored in the
database, and a **post-hoc row filter in Python** for permissions. This document explains all of
it and specifies our replacement.

---

## 1. Five report types

`Report` doctype (`frappe/core/doctype/report/report.py:21`). `report_type` ∈:

| Type | Execution | Permission enforcement |
|---|---|---|
| **Report Builder** | `run_standard_report` (`:309`) → `DatabaseQuery` | full (query-level, doc 19 §3.2) |
| **Query Report** | `execute_query_report` (`:180`) — raw SQL stored in the `query` field | **none at query level**; post-hoc filter (§3) |
| **Script Report** | `execute_module` (`:233`) — Python module on disk | none; post-hoc filter |
| **Custom Report** | derived from another report + extra columns | inherits the parent's |
| **Server-script Report** | `execute_script` (`:237`) — Python **stored in the DB**, run through `safe_exec` | none; post-hoc filter |

Dispatch: `get_data` (`:253`), `execute_script_report` (`:193`),
`run_query_report` (`:274`), `execute_snapshot_report` (`:246`),
`get_module_method` (`:225`), `get_report_module_dotted_path` (`:519`).

Runner: `frappe/desk/query_report.py` — `run` (`:225`), `_run` (`:248`),
`get_report_doc` (`:25`), `get_report_result` (`:62`),
`generate_report_result` (`:79`), `normalize_result` (`:163`),
`get_script` (`:180`), `get_reference_report` (`:216`).

### 1.1 Query Report: stored SQL

`frappe/core/doctype/report/report.py:180`:

```python
if not self.query:
    frappe.throw(_("Must specify a Query to run"), title=_("Report Document Error"))
check_safe_sql_query(self.query)
frappe.db.begin(read_only=True)
result = [list(t) for t in frappe.db.sql(self.query, filters)]
columns = self.get_columns() or [cstr(c[0]) for c in frappe.db.get_description()]
frappe.db.rollback()
return [columns, result]
```

Good parts: the query runs in an explicit **read-only transaction** (`:186`, `:189`), and
`check_safe_sql_query` blocks obvious mutations.

The problem: **the SQL is a text column in a database row, written by a user with the
`Script Manager` role, and it is executed verbatim.** No RLS, no `permission_query_conditions`
(doc 19 §3.3), no `if_owner`, no user permissions. A Query Report is a direct window onto every
row of every table in the site, for every company. The only defence is the post-hoc Python filter
(§3), which — as shown below — cannot filter what it cannot recognise.

### 1.2 Script Report and the `safe_exec` variant

`execute_module` (`frappe/core/doctype/report/report.py:233`) resolves
`<module>.report.<report_name>.<report_name>.execute` via
`get_module_method` (`:225`), which allowlists three method names
(`execute`, `execute_snapshot_report`, `get_xlsx_styles`, `:226`–`:227`). That is the healthy
case: code on disk, in version control.

`execute_script` (`:237`) is the unhealthy one:

```python
loc = {"filters": frappe._dict(filters), "data": None, "result": None}
safe_exec(self.report_script, None, loc, script_filename=f"Report {self.name}")
if loc["data"]: return loc["data"]
else: return self.get_columns(), loc["result"]
```

`report_script` is a **`Code` field on the `Report` row**. `safe_exec` is Frappe's
RestrictedPython sandbox — better than bare `exec`, but a sandbox nonetheless, and one that
exposes `frappe.db.sql` to the script by design.

Who can create these: `validate` (`frappe/core/doctype/report/report.py:63`):

```python
if self.is_standard == "No":
    if self.report_type not in ("Report Builder", "Custom Report"):
        frappe.only_for("Script Manager", True)
    if frappe.db.get_value("Report", self.name, "is_standard") == "Yes":
        frappe.throw(_("Cannot edit a standard report. Please duplicate and create a new report"))
```

So `Script Manager` is effectively **database-superuser-equivalent** in a Frappe site. Note also
`:70`–`:73`: a report saved by `Administrator` in developer mode is silently promoted to
`is_standard = "Yes"`, which then routes it through `validate_standard_report` (`:448`) and
`export_doc` (`:166`) / `create_report_py` (`:175`) — writing files to disk.

### 1.3 Prepared Reports — the timeout escape hatch

`execute_script_report` (`frappe/core/doctype/report/report.py:193`):

```python
threshold = 15
start_time = datetime.datetime.now()
if not self.prepared_report and not self.disable_prepared_report_automation:
    prepared_report_watcher = threading.Timer(
        interval=threshold,
        function=enable_prepared_report,
        kwargs={"report": self.name, "site": frappe.local.site})
    prepared_report_watcher.start()
try:
    ... execute ...
finally:
    prepared_report_watcher and prepared_report_watcher.cancel()
execution_time = (datetime.datetime.now() - start_time).total_seconds()
frappe.cache.hset("report_execution_time", self.name, execution_time)
```

**A `threading.Timer` fires after 15 seconds and permanently flips the report to "prepared"**
(`enable_prepared_report`, `frappe/core/doctype/report/report.py:550`), meaning all future runs
go to a background job and the user gets a `Prepared Report` document with a stored result file.
`is_prepared_report_enabled` (`:515`), `get_prepared_report_result`
(`frappe/desk/query_report.py:338`) with `get_report_data` (`:341`).

Self-modifying configuration based on a wall-clock threshold. It works, and it tells you that
report performance is a chronic problem — which is unsurprising when the underlying data model
stores derived values in unlocked columns and reports must recompute aggregates (Tranche A,
passim).

`frappe.cache.hset("report_execution_time", ...)` and `update_report_cache`
(`frappe/core/doctype/report/report.py:123`), `clear_cache` (`:119`) manage the rest.

### 1.4 Report Builder

`run_standard_report` (`frappe/core/doctype/report/report.py:309`) with
`_format` (`:341`), `get_standard_report_columns` (`:345`),
`get_standard_report_filters` (`:362`), `get_standard_report_order_by` (`:374`),
`build_standard_report_columns` (`:400`), `build_data_dict` (`:434`),
`get_group_by_field` (`:531`), `get_group_by_column_field` (`:541`),
`update_report_json` (`:162`).

This is the *safe* type: the report definition is JSON describing columns, filters, and group-by,
and it is executed through `DatabaseQuery` — so it gets user permissions, `if_owner`, share
conditions, hook conditions, and field-level read permissions (doc 19). It is also the least
capable: single doctype plus child tables, no joins beyond link fields, no window functions, no
CTEs. Every real financial report in ERPNext is therefore a Script Report.

---

## 2. ERPNext's financial reports

The reports that matter are Python modules, documented in doc 07:
`accounts/report/financial_statements.py` — `get_period_list` (`:200`),
`get_data` (`:338`), `set_gl_entries_by_account` (`:406`),
`get_columns` (`:617`), `get_accounts` (`:688`), `filter_out_zero_value_rows` (`:797`).

Plus General Ledger, Trial Balance, Accounts Receivable/Payable (built on
`QueryPaymentLedger`, `accounts/utils.py:2273`), Stock Balance, Stock Ledger, Stock Projected Qty,
Item-wise Sales/Purchase Register, Gross Profit, Sales/Purchase Analytics.

Two structural observations from Tranche A that land here:

- **Every ledger report must filter `is_cancelled = 0`** (doc 01 §7). That is a per-report
  convention, not a schema property. `get_actual_expense` in the budget controller
  (`accounts/doctype/budget/budget.py:758`, doc 12 §1.3) remembers; other places forget.
- **Aged receivables built on `GL Entry.against_voucher` drift**, because reconciliation does not
  rebuild GL rows (doc 11 §4.3). The Payment-Ledger-based reports are correct; the GL-based ones
  are not. Two reports, same question, different answers.

---

## 3. Permissions in reports: the post-hoc filter

This is the most important section of this document.

`get_filtered_data` (`frappe/desk/query_report.py:901`):

```python
linked_doctypes = get_linked_doctypes(columns, data)                 # :1050
match_filters_per_doctype = get_user_match_filters(linked_doctypes, user=user)   # :1128
shared = frappe.share.get_shared(ref_doctype, user)
columns_dict = get_columns_dict(columns)                             # :1087
ref_doctype_meta = frappe.get_meta(ref_doctype)
role_permissions = get_role_permissions(ref_doctype_meta, user)
if_owner = role_permissions.get("if_owner", {}).get("report")

if ref_doctype_meta.get_masked_fields():
    from frappe.model.db_query import mask_field_value
    for field in ref_doctype_meta.get_masked_fields():
        for row in data:
            row[field.fieldname] = mask_field_value(field, row.get(field.fieldname))

if match_filters_per_doctype:
    for row in data:
        if linked_doctypes.get(ref_doctype) and shared and row.get(linked_doctypes[ref_doctype]) in shared:
            result.append(row)
        elif has_match(row, linked_doctypes, match_filters_per_doctype, ref_doctype, if_owner, columns_dict, user):
            result.append(row)
else:
    result = list(data)
return result
```

Read that last `else` carefully: **if the user has no User Permissions, `result = list(data)` —
every row is returned.** Which is correct *only if* the query itself was already scoped. For a
Query Report or Script Report, it was not (§1.1, §1.2).

And when there *are* User Permissions, filtering is done by:

- `get_linked_doctypes(columns, data)` (`:1050`) — **inferring which column corresponds to which
  doctype from the column metadata**. `get_columns_dict` (`:1087`) /
  `get_column_as_dict` (`:1102`) parse column definitions like `"Company:Link/Company:120"`.
  If a report's column is a computed expression, an alias, or a plain `Data` column holding a
  company name, **it is not recognised as a link and is not filtered**.
- `has_match` (`:948`) — per-row evaluation of owner match and user-permission match across every
  recognised linked doctype.
- `has_unrestricted_read_access` (`:1025`) — a `DocPerm`/`Custom DocPerm` existence check.
- `get_data_for_custom_field` (`:819`), `get_data_for_custom_report` (`:832`),
  `add_custom_column_data` (`frappe/desk/query_report.py:305`) for Custom Reports.

Consequences:

1. **Row filtering is O(rows × linked doctypes) in Python**, after the database has already
   returned every row. A report over 500 000 GL entries materialises all of them, then filters.
2. **Aggregates are computed before filtering.** A Script Report that returns
   `SUM(debit) GROUP BY account` produces totals over *all* companies; the post-hoc filter can
   only drop whole rows, and the row's total already includes data the user may not see. **This
   is a silent, structural information leak in any aggregated Script Report.**
3. **Masking is applied to the result set** (`:915`–`:922`), not to the query — so the value was
   read from the database, travelled through Python, and is redacted on the way out.
4. `get_permission_query_conditions` and `has_permission` for the `Report` doctype itself
   (`frappe/core/doctype/report/report.py:558`, `:568`), `is_permitted` (`:145`),
   `set_doctype_roles` (`:138`), and `Role Permission for Page and Report` rows control *who may
   run which report* — a separate, coarser layer.
5. `validate_filters_permissions` (`frappe/desk/query_report.py:1139`) checks that the user may
   read the *filter values* they supplied (`Link` filters only, `:1157`–`:1163`). So you cannot
   run a report filtered to a company you cannot see — but you can run it **unfiltered** and get
   that company's rows, subject only to §3's post-hoc filter.

Export follows the same path: `export_query` (`:376`),
`run_export_query_job` (`:412`), `_export_query` (`:421`),
`build_xlsx_data` (`:562`), `get_xlsx_styles` (`:720`), `add_total_row` (`:737`),
`format_fields` (`:528`), `format_filter_value` (`:558`),
`translate_report_data` (`:1171`), `valid_report_name` (`:522`),
`save_report` (`:860`).

`add_total_row` (`:737`) computes the total **from the filtered rows**, which is the one place the
ordering works in the user's favour.

---

## 4. Dashboards, cards, and print

- `Dashboard`, `Dashboard Chart`, `Dashboard Chart Source`, `Dashboard Chart Field`,
  `Number Card`, `Number Card Link` — chart definitions with their own aggregation
  (`Dashboard Chart` supports `Count`/`Sum`/`Average` over a doctype, or a custom source).
- `Dashboard Settings`, `Workspace` + `Workspace Chart`/`Workspace Number Card`/
  `Workspace Shortcut`/`Workspace Link`.
- `Print Format` (with `Print Format Field`), `Letter Head`, `Print Settings`,
  `Print Style`, and Jinja rendering via `jenv` hooks (doc 21 §4).
  `Report.validate_default_print_format` (`frappe/core/doctype/report/report.py:455`),
  `validate_default_letter_head` (`:472`), `get_xlsx_styles_from_module` (`:502`).
- `Auto Email Report` for scheduled delivery, and `Prepared Report` for stored results.
- `DuckDB Sync` / `DuckDB Sync Item` (v17, in `frappe/core/doctype/`) — an analytics offload,
  which is the framework's own acknowledgement that OLTP tables are the wrong place to run
  analytics.

Number Cards and Dashboard Charts aggregate through `DatabaseQuery`, so they *are* permission-
scoped — but they are limited to single-doctype aggregation for the same reason Report Builder is.

---

## 5. Our design

### 5.1 Reporting reads views, and views obey RLS

The foundational decision: **every report reads from a named, versioned SQL view (or a function
returning a table), never from raw ad-hoc SQL supplied at runtime.**

```sql
CREATE VIEW rpt_general_ledger AS
SELECT g.company_id, g.posting_date, g.account_id, a.code AS account_code, a.name AS account_name,
       g.party_type, g.party_id, g.voucher_id, v.doc_type, v.doc_no, v.posting_date AS voucher_date,
       g.debit_base, g.credit_base, g.debit_base - g.credit_base AS net_base,
       g.cost_center_id, g.project_id, g.dim1_id, g.dim2_id
FROM gl_entry g
JOIN account a ON a.id = g.account_id
JOIN voucher v ON v.id = g.voucher_id;
```

Because `gl_entry` has RLS enabled and `FORCE ROW LEVEL SECURITY` (doc 19 §7.1), and the view is
**not** `SECURITY DEFINER`, the policy applies to anyone selecting from the view. Therefore:

- **Aggregation happens inside the database, after row filtering.** `SUM(net_base) GROUP BY
  account_id` over `rpt_general_ledger` sums only rows the user may see. The §3.2 leak — totals
  computed over data the user cannot access — is **structurally impossible**.
- No `is_cancelled = 0` filter to forget (§2), because there is no `is_cancelled`; reversals are
  separate rows and the view exposes both the movement and its reversal explicitly (D5).
- Field-level restriction is column privileges on the view (doc 19 §7.4), so a user without
  cost-price access simply cannot select that column — no read-then-mask (§3.3).
- One definition of "outstanding", "delivered", "on hand" — the views from
  doc 10 §5.2, doc 11 §6.2, doc 16 §5.1. Two reports cannot disagree (§2, aged-receivables case),
  because both read the same view.

### 5.2 Report definitions are data; report *logic* is not

```sql
CREATE TABLE report_def (
    id             uuid PRIMARY KEY,
    code           text NOT NULL UNIQUE,
    label          text NOT NULL,
    source_view    text NOT NULL,            -- must exist in report_source registry
    default_grouping text[],
    is_enabled     boolean NOT NULL DEFAULT true
);
CREATE TABLE report_source (            -- the allowlist of readable views
    view_name      text PRIMARY KEY,
    description    text NOT NULL,
    is_rls_enforced boolean NOT NULL DEFAULT true
);
CREATE TABLE report_column (
    report_id      uuid NOT NULL REFERENCES report_def(id) ON DELETE CASCADE,
    seq            smallint NOT NULL,
    source_column  text NOT NULL,
    label          text NOT NULL,
    agg            agg_kind,                  -- NULL | 'sum','count','avg','min','max'
    format         column_format NOT NULL,    -- 'text','int','money','qty','date','percent','link'
    PRIMARY KEY (report_id, seq)
);
CREATE TABLE report_filter (
    report_id      uuid NOT NULL REFERENCES report_def(id) ON DELETE CASCADE,
    seq            smallint NOT NULL,
    source_column  text NOT NULL,
    operator       filter_op NOT NULL,        -- enum: 'eq','in','between','gte','lte','like'
    is_required    boolean NOT NULL DEFAULT false,
    PRIMARY KEY (report_id, seq)
);
```

The query is **generated** from these rows against the named view, with:

- columns validated against `information_schema.columns` for that view — so a column name is
  either real or the report fails to save;
- operators from a closed enum, values always bound as parameters;
- `source_view` constrained to the `report_source` allowlist.

**There is no user-supplied SQL and no user-supplied code** (§1.1, §1.2). Reports needing genuine
computation (financial statements with period columns, ageing buckets, valuation roll-forward) are
**views or set-returning functions written in migrations** — reviewed, version-controlled,
tested, and named in `report_source`.

This is a real capability reduction versus Script Reports, taken deliberately: a `Script Manager`
role that can read every row of every company's ledger is not compatible with the tenancy model
we committed to in D2.

### 5.3 Performance: materialised views and a read replica

Frappe's answer to slow reports is Prepared Reports triggered by a 15-second timer (§1.3). Ours:

1. **Indexes designed for the report views**, not incidentally.
2. **`MATERIALIZED VIEW` for expensive roll-ups** (trial balance by period, stock balance by
   warehouse/period), refreshed `CONCURRENTLY` on a schedule and after period close. Because the
   source is append-only, a refresh is always correct — no repost, no invalidation logic
   (doc 15 §10).
   Note: materialised views do **not** inherit RLS, so each is either (a) pre-aggregated to a
   grain that is safe for all readers and joined to a policy-bearing table, or (b) exposed only
   through a wrapping view that re-applies the company predicate. This is called out explicitly
   because it is the one place the RLS guarantee needs care.
3. **A streaming read replica** for heavy analytics, with the same roles and the same RLS
   policies. Long reports do not compete with posting for locks — which is what
   `kill_idle_connections` (doc 23 §1.2) and `in_configured_timeslot` (doc 22 §2.3) are working
   around.
4. **An explicit async path** for genuinely long exports: a `job` row (doc 22 §5.2) producing a
   stored artefact, requested by the user rather than triggered by a wall-clock timer that
   permanently mutates the report's configuration (§1.3).

### 5.4 Point-in-time reporting comes free

This is worth stating as a capability, not just a fix. Because our ledgers, `doc_link`,
`settlement`, `bank_match`, and `budget_commitment` are append-only with timestamps:

- "What was the order book on 30 June?" → `WHERE created_at < '2026-07-01'` on `doc_link`
  (doc 10 §6).
- "What did the trial balance look like as filed, before the audit adjustments?" →
  `WHERE posted_at <= <filing timestamp>`.
- "What was this customer's outstanding on the statement date?" → `settlement` filtered by
  `posted_at`.

ERPNext cannot answer any of these from its own data, because the figures are current-value
columns; it needs `Account Closing Balance` snapshots (doc 07) and nightly jobs. Ours needs
neither, and the stored `customer_statement` snapshot (doc 14 §7.5) becomes a convenience rather
than a necessity.

### 5.5 What we still must build

Being explicit, since this is the "how much framework do we write" question:

| Capability | Effort | Notes |
|---|---|---|
| Query generator from `report_def`/`report_column`/`report_filter` | small | closed enums, bound parameters, validated identifiers |
| Report runner + pagination + CSV/XLSX export | small–medium | export reuses the generated query with a cursor |
| ~25 core financial/inventory report views | **medium–large** | the real work; each is a reviewed SQL migration with tests |
| Materialised roll-ups + refresh scheduling | small | reuses `schedule`/`job` (doc 22 §5.3) |
| Chart/dashboard definitions | small | same `report_def` rows with a chart rendering hint |
| Print/document templates | medium | a template engine with a helper registry (doc 21 §8), no arbitrary code |
| Read replica + role/RLS parity | small (ops) | |

Explicitly **not** built: a user-facing SQL console, stored server scripts, stored client scripts,
a metadata-driven report builder over arbitrary doctypes.

---

## 6. Summary

| Frappe mechanism | Verdict | Our replacement |
|---|---|---|
| Query Report: raw SQL in a table row, executed verbatim | **Reject** | generated queries over allowlisted views (§5.2) |
| Server-script Report: Python in a DB row via `safe_exec` | **Reject** | views/functions in migrations |
| `Script Manager` role ≈ database superuser | **Reject** | no role can supply SQL or code |
| Post-hoc Python row filtering; `else: result = list(data)` | **Reject** | RLS on the base tables; views inherit it (§5.1) |
| Aggregates computed before permission filtering (leak) | **Reject** | aggregation happens after RLS, inside the database |
| Linked-doctype inference from column metadata strings | **Reject** | real columns on typed views |
| Masking applied to the result set | **Reject** | column privileges (doc 19 §7.4) |
| Per-report `is_cancelled = 0` convention | **Reject** | append-only ledgers; no flag exists |
| Two reports answering the same question differently | **Reject** | one view per concept (§5.1) |
| `threading.Timer` flipping a report to Prepared after 15 s | **Reject** | designed indexes, materialised roll-ups, explicit async export (§5.3) |
| Report Builder over `DatabaseQuery` | **Keep the idea** | generated queries, but over views rather than single doctypes |
| `validate_filters_permissions` | **Keep** | filter values validated; also unnecessary, since RLS covers the rows |
| `Role Permission for Page and Report` | **Keep** | `role_grant(resource='report_def', action='read')` |
| `Prepared Report` stored results | **Keep, narrowed** | user-requested async exports as `job` artefacts |
| `Auto Email Report` | **Keep** | `schedule` + `job` + stored artefact (doc 22 §5.3) |
| Dashboard Chart / Number Card | **Keep** | same definition model, over views |
| `DuckDB Sync` (analytics offload) | **Keep the idea** | read replica; column-store offload only if measurements demand it |
| Print Format + Jinja | **Keep, constrained** | template engine with a fixed helper registry, no arbitrary expressions |

---

## 7. Tranche E status

| Doc | Area | Status |
|---|---|---|
| 18 | Metadata, runtime DDL, customisation | done |
| 19 | Permissions and access control | done |
| 20 | Naming, identity, audit trail | done |
| 21 | Hooks, overrides, regional overlay | done |
| 22 | Background jobs, scheduling, locking | done |
| 23 | Migrations, patches, deployment | done |
| 24 | Reporting framework | this document |
| 25 | **Our platform specification** — synthesis of 18–24 into what we build, buy, or drop | next |

---

Cross-references: doc 01 §7 (`is_cancelled` in reports), doc 07 (financial statements),
doc 11 §4.3 (why GL-based ageing drifts), doc 18 (metadata),
doc 19 (access control — the model reports must respect), doc 22 (async execution),
doc 23 (views live in migrations), `docs/design/FINAL-SCHEMA.md`.
