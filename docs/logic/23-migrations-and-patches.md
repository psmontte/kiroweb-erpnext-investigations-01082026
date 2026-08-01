# 23 — Migrations, Patches, and Deployment

> **Tranche E — platform mechanics.** Source pinned at
> `frappe` `5da68e856ca7f036b20d2583167b9d00c4a8db56` and
> `erpnext` `ceefd4add77715d2762c19db337fb83e28a477de` (v17.0.0-dev).
> Citations are `path:line` relative to `/projects/sandbox/frappe/frappe` (prefixed `frappe/`)
> or `/projects/sandbox/erpnext/erpnext`.

Doc 18 established that in Frappe the schema is data, and DDL happens at runtime. This document
covers the consequence: **there is no schema migration in the conventional sense**. Upgrading is
"reconcile the database against the current DocType JSON files, and run a list of Python scripts".

---

## 1. `bench migrate` — the eleven-step pipeline

`SiteMigration` (`frappe/migrate.py:63`). Its own docstring (`:64`–`:75`):

> Migrate all apps to the current version, will:
> run before migrate hooks / run patches / sync doctypes (schema) / sync dashboards / sync jobs /
> sync fixtures / sync customizations / sync languages / sync web pages (from /www) /
> run after migrate hooks

`run` (`frappe/migrate.py:260`) drives `setUp` (`:84`) →
`pre_schema_updates` (`:119`) → `run_schema_updates` (`:137`) →
`post_schema_updates` (`:148`) → `tearDown` (`:98`).

### 1.1 The transaction model

`atomic` (`frappe/migrate.py:46`):

```python
def wrapper(*args, **kwargs):
    try:
        ret = method(*args, **kwargs); frappe.db.commit(); return ret
    except Exception as e:
        with contextlib.suppress(Exception):
            frappe.db.rollback()
        raise e
```

Each of the three phases is decorated `@atomic` (`:118`, `:136`, `:147`). So a migration is
**three transactions**, not one — and within `run_schema_updates`, each individual patch commits
independently (§2.2). There is therefore **no atomic upgrade**: a failure leaves the site in a
partially-migrated state, recoverable only by fixing the patch and re-running (which is why
`Patch Log` exists, §2.3).

MariaDB/MySQL DDL is not transactional anyway, so this is partly forced. PostgreSQL *does* support
transactional DDL — which is a capability our design intends to use (§5.1).

### 1.2 `setUp` / `tearDown`

`setUp` (`frappe/migrate.py:84`):

```python
frappe.flags.touched_tables = set()
self.touched_tables_file = frappe.get_site_path("touched_tables.json")
frappe.clear_cache()
if os.path.exists(self.touched_tables_file): os.remove(self.touched_tables_file)
self.lower_lock_timeout()
with contextlib.suppress(Exception): self.kill_idle_connections()
frappe.flags.in_migrate = True
```

`lower_lock_timeout` (`frappe/migrate.py:220`) and
`kill_idle_connections(idle_limit=30)` (`frappe/migrate.py:229`) exist because **migration
competes with live traffic for locks**. The migration reduces its own lock timeout and
**terminates other sessions** that have been idle more than 30 seconds. That is a pragmatic
answer to "ALTER TABLE is blocked by an idle transaction", and it is also a migration killing
user connections.

`DBQueryProgressMonitor` (`frappe/migrate.py:286`) is a background thread
(`__init__` `:289`, `run` `:298`, `stop` `:343`) that reports long-running queries during the
migration — again, because migrations are long and opaque.

`tearDown` (`frappe/migrate.py:98`) writes `touched_tables.json`, clears caches, enqueues a
search-index rebuild (`frappe/migrate.py:110`–`:112`), and publishes `version-update`.
`touched_tables` is used by backup tooling to know what changed.

`required_services_running` (`frappe/migrate.py:205`) gates the whole thing on Redis and the
database being up.

### 1.3 `pre_schema_updates`

`frappe/migrate.py:119`:

```python
for app in frappe.get_installed_apps():
    for fn in frappe.get_hooks("before_migrate", app_name=app): frappe.get_attr(fn)()
    for doctype in frappe.get_hooks("override_doctype_class", {}, app_name=app).keys():
        overrides[doctype].append(app)
for doctype, app_names in overrides.items():
    if len(app_names) > 1:
        click.secho(f"The controller for {doctype} is overridden by multiple apps: {...}", fg="yellow")
```

Note the second half: **two apps overriding the same controller produces a yellow warning**, not
an error (doc 21 §4). The resolution remains "last installed app wins", and the operator is
expected to notice a console message during a migration.

### 1.4 `run_schema_updates` — the core

`frappe/migrate.py:137`:

```python
frappe.modules.patch_handler.run_all(skip_failing=self.skip_failing, patch_type=PatchType.pre_model_sync)
frappe.model.sync.sync_all()
frappe.modules.patch_handler.run_all(skip_failing=self.skip_failing, patch_type=PatchType.post_model_sync)
```

Three steps: **data fixes that must run before the schema changes**, then the schema
reconciliation, then **data fixes that need the new schema**. The pre/post split (`PatchType`,
`frappe/modules/patch_handler.py:49`) is the mechanism for ordering data migration against schema
migration — and it is only two buckets. A change requiring
`pre → schema → data → schema → data` cannot be expressed; it must be split across two releases.

### 1.5 `post_schema_updates`

`frappe/migrate.py:148`. Its docstring lists nine sync steps; the body runs:

`sync_jobs()` (doc 22 §2), `create_missing_sequences()` (`frappe/migrate.py:166`–`:170`
— **sequences can go missing** and are recreated on migrate), `sync_fixtures()`,
`sync_standard_items()`, `sync_dashboards()`, `sync_customizations()`, `sync_languages()`,
`flush_deferred_inserts()`, `remove_orphan_doctypes()`, `remove_orphan_entities()`,
`delete_duplicate_icons()`, `Portal Settings.sync_menu()`,
`Installed Applications.update_versions()`, then `after_migrate` hooks.

`frappe/model/sync.py` provides `sync_all` (`:47`), `sync_for` (`:57`),
`get_doc_files` (`:145`), `remove_orphan_doctypes` (`:170`),
`remove_orphan_entities` (`:198`), `create_entity_file_map` (`:267`),
`check_if_record_exists` (`:291`) with `build_path` (`:297`),
`delete_duplicate_icons` (`:309`).

Two names worth pausing on:

- **`remove_orphan_doctypes` / `remove_orphan_entities`** — DocType *rows* that no longer have a
  corresponding JSON file are deleted. So "the schema" is reconciled by scanning the filesystem
  and deleting database rows that no file claims. Note this removes the *DocType row*, but
  **not the physical table** (doc 18 §2.5) — hence 908 tables for 997 DocTypes.
- **`delete_duplicate_icons`** — a cleanup for a specific historical defect, permanently part of
  every migration.

`sync_all` calls `import_file` (`frappe/modules/import_file.py`) per JSON, which inserts/updates
the `DocType`/`DocField` rows and thereby triggers `DocType.on_update`
(`frappe/core/doctype/doctype/doctype.py:533`) → `frappe.db.updatedb` → `ALTER TABLE`
(doc 18 §2.4). **The schema change is a side effect of importing a JSON file into a table.**

---

## 2. Patches

### 2.1 `patches.txt`

`get_patches_from_app` (`frappe/modules/patch_handler.py:95`) — the docstring:

> patches.txt can be:
> 1. ini like file with section for different patch_type
> 2. plain text file with each line representing a patch.

`parse_as_configfile` (`frappe/modules/patch_handler.py:115`) parses it with
`configparser(allow_no_value=True, delimiters="\n")` and `optionxform = str` to preserve case,
falling back to `frappe.get_file_items` on `MissingSectionHeaderError` for the legacy format
(`:105`–`:112`).

So the ordered list of data migrations is an **INI file whose keys are Python module paths**, with
two sections, parsed with a config parser configured to not treat `:` or `=` as delimiters —
because patch lines can be `execute:frappe.db.sql("...")`.

### 2.2 Execution

`run_all` (`frappe/modules/patch_handler.py:54`):

```python
executed = set(frappe.get_all("Patch Log", filters={"skipped": 0}, fields="patch", pluck="patch"))
frappe.flags.final_patches = []
def run_patch(patch):
    try:
        if not run_single(patchmodule=patch): print(patch + ": failed: STOPPED"); raise PatchError(patch)
    except Exception:
        if not skip_failing: raise
        print("Failed to execute patch")
        update_patch_log(patch, skipped=True)
patches = get_all_patches(patch_type=patch_type)
for patch in patches:
    if patch and (patch not in executed): run_patch(patch)
for patch in frappe.flags.final_patches:
    patch = patch.replace("finally:", "")
    run_patch(patch)
```

`execute_patch` (`frappe/modules/patch_handler.py:157`):

```python
_patch_mode(True)
if patchmodule.startswith("execute:"):
    has_patch_file = False; patch = patchmodule.split("execute:")[1]; docstring = ""
else:
    has_patch_file = True
    patch = f"{patchmodule.split(maxsplit=1)[0]}.execute"
    _patch = frappe.get_attr(patch); docstring = _patch.__doc__ or ""
...
frappe.db.commit()
frappe.db.auto_commit_on_many_writes = 0
try:
    if patchmodule:
        if patchmodule.startswith("finally:"):
            frappe.flags.final_patches.append(patchmodule)
        else:
            if has_patch_file: _patch()
            else: exec(patch, globals())
            update_patch_log(patchmodule)
    elif method: method(**methodargs)
except Exception:
    frappe.db.rollback(); raise
else:
    frappe.db.commit(); end_time = time.monotonic(); _patch_mode(False)
```

Findings:

1. **`exec(patch, globals())`** (`:186`) — an `execute:`-prefixed patch line is arbitrary Python
   `exec`'d with the patch handler's globals. This is by design and heavily used
   (`execute:frappe.db.sql(...)`, `execute:frappe.reload_doc(...)`).
2. **Three magic prefixes**: `execute:` (inline code), `finally:` (defer to the end,
   `:180`–`:182`, and stripped before logging, `:227`–`:229`), and the implicit default
   (a module with an `execute()` function).
3. **Each patch is its own transaction** — `commit()` before (`:174`) and after (`:198`).
   So the migration is N+3 transactions, and a failure at patch 40 of 60 leaves 39 applied.
4. **`skip_failing` marks a patch as `skipped = 1` and continues** (`:66`–`:71`). A skipped patch
   is *not* in the `executed` set (`:56` filters `skipped: 0`), so it will be retried on the next
   migrate — but the migration reported success. The traceback is stored on the `Patch Log` row.
5. **`frappe.db.auto_commit_on_many_writes = 0`** (`:175`) — there is a mode in which many writes
   auto-commit, and patches disable it. That mode existing at all means some code paths commit
   implicitly.
6. `_patch_mode` (`frappe/modules/patch_handler.py:231`) sets `flags.in_patch` and commits —
   and `flags.in_patch` is read in `Document.save_version`
   (`frappe/model/document.py:2032`) to *skip version tracking*, so **patch-applied data changes
   are not in the audit trail** (doc 20 §2.1).
7. `run_single` (`:145`) sets `conf.developer_mode = 0` to prevent patches from writing JSON files.
8. `reload_doc` (`:139`) lets a patch re-import a DocType definition mid-patch — i.e. a patch can
   trigger DDL.

### 2.3 `Patch Log`

`update_patch_log` (`frappe/modules/patch_handler.py:209`), `executed` (`:223`).
One row per applied patch, with `skipped` and `traceback`. Identity is the **patch string**, so
renaming a patch module re-runs it, and `finally:`-prefixed patches are stored without the prefix
(`:225`–`:229`).

There is no checksum. A patch's *content* can change between releases with the same module path,
and it will not re-run. Conversely there is no way to declare "this patch must run again".

---

## 3. Installation and app lifecycle

`frappe/installer.py` handles `bench new-site` / `install-app` / `uninstall-app`, driven by
`before_install` / `after_install` / `before_uninstall` / `after_uninstall` hooks
plus `after_sync`, `before_tests`. `erpnext/setup/install.py` and the various
`setup_wizard` steps seed the chart of accounts, UOMs, item groups, and so on.

Two structural notes:

- **App install order is persisted** (`Installed Applications`,
  `Installed Application` rows) and determines hook precedence (doc 21 §1). Reinstalling apps in
  a different order changes behaviour.
- `Package` / `Package Import` / `Package Release` exist for shipping DocType bundles between
  sites — a parallel distribution mechanism to apps.

---

## 4. What breaks, in practice

Collecting the failure modes visible in the code:

| Failure mode | Evidence |
|---|---|
| Partially applied migration | three `@atomic` phases (§1.1), per-patch commits (§2.2 pt 3) |
| Silent skip reported as success | `skip_failing` (§2.2 pt 4) |
| DDL blocked by live traffic; sessions killed | `lower_lock_timeout`, `kill_idle_connections` (§1.2) |
| Long unexplained DDL | `DBQueryProgressMonitor` (§1.2) |
| Truncation on shortening a column, silently reverted | `DBTable.validate` (doc 18 §2.6) |
| Blank strings coerced to `0` on type change | `PostgresTable.alter` (doc 18 §2.2) |
| Orphaned physical columns | `trim_tables` is separate and manual (doc 18 §2.5) |
| Orphaned DocType rows | `remove_orphan_doctypes` (§1.5) |
| Missing sequences | `create_missing_sequences` (§1.5) |
| Customisation lost or conflicting | `sync_customizations`, Property Setter precedence (doc 18 §1.1) |
| Two apps overriding one controller | warning only (§1.3) |
| Patch data changes invisible to audit | `flags.in_patch` skips `save_version` (§2.2 pt 6) |
| Patch identity by module path, no checksum | §2.3 |
| No downgrade path | there is none — patches are forward-only with no `down()` |

The last one is worth stating plainly: **Frappe has no rollback story.** The only recovery from a
bad migration is restore-from-backup, which is why `touched_tables.json` (§1.2) exists.

---

## 5. Our design

### 5.1 Versioned, transactional, reversible migrations

```
migrations/
  0001_initial_schema.up.sql        0001_initial_schema.down.sql
  0002_company_rls.up.sql           0002_company_rls.down.sql
  0003_gl_entry_append_only.up.sql  0003_gl_entry_append_only.down.sql
  ...
```

Rules:

- **One file, one transaction.** PostgreSQL DDL is transactional, so
  `BEGIN; <ddl + data>; COMMIT;` per migration. A failure leaves *nothing* applied from that
  migration. Contrast §1.1/§2.2.
- **Applied migrations are recorded with a checksum**:

```sql
CREATE TABLE schema_migration (
    version        bigint PRIMARY KEY,
    name           text NOT NULL,
    checksum       bytea NOT NULL,
    applied_at     timestamptz NOT NULL DEFAULT now(),
    applied_by     text NOT NULL,
    execution_ms   integer NOT NULL,
    is_reversible  boolean NOT NULL
);
```

  Startup verifies that every applied migration's checksum still matches the file. A changed
  historical migration is a **hard failure**, not a silent no-op (§2.3).

- **`down.sql` is mandatory for reversible migrations** and its absence must be declared
  explicitly (`is_reversible = false`) with a reason. Irreversible migrations (dropping a column
  with data) are flagged in review.
- **No `skip_failing`.** A migration either applies or the deployment stops. There is no
  "succeeded with 3 skipped".
- **No `exec` of strings.** Data migrations are SQL, or — where genuinely procedural — a
  compiled, reviewed, version-pinned program invoked by the migration runner with its own
  `schema_migration` row.

### 5.2 Advisory-locked, concurrency-safe application

The migration runner takes `pg_advisory_lock` on a fixed key for the duration, so two deploys
cannot race. It does **not** kill user sessions (§1.2). Instead:

- `SET lock_timeout = '3s'; SET statement_timeout = '...'` per migration, so a blocked DDL
  **fails fast and the deploy aborts** rather than queueing behind traffic and blocking everything
  behind it (the classic Postgres `ALTER TABLE` lock-queue pileup).
- Long/blocking operations are written in the online-safe idiom:
  `CREATE INDEX CONCURRENTLY` (in its own non-transactional migration, explicitly marked),
  `ADD COLUMN` with no default or with a non-volatile default,
  `NOT VALID` constraints followed by `VALIDATE CONSTRAINT` in a later migration,
  and multi-step column type changes (add new → backfill in batches → swap → drop) as separate
  numbered migrations.

This is the standard playbook; the point is that it is *possible* because the schema is under our
control, and *impossible* in Frappe because DDL is emitted by `DbColumn.build_for_alter_table`
from a metadata diff (doc 18 §2.1).

### 5.3 Data migrations are first-class and audited

Frappe's `flags.in_patch` suppresses version tracking (§2.2 pt 6). Ours does the opposite:

- A data migration runs as a **named actor** (`migration:0042`), so `field_change` and
  `lifecycle_event` rows (doc 20 §3.3) record it. The audit trail shows exactly which upgrade
  changed which values.
- Row counts are recorded: each data migration reports affected rows into
  `schema_migration.execution_ms` plus a `migration_effect (version, table_name, rows_affected)`
  table. "What did release 3.4 change?" is a query.
- Ledger tables are append-only (H1), so a data migration **cannot** rewrite history. A
  correction to posted data is a set of reversal + replacement vouchers, generated by the
  migration and visible as ordinary business documents with `reason_code = 'migration:0042'`.
  This is the single most important difference: ERPNext patches routinely `UPDATE` and `DELETE`
  GL rows (`accounts/utils.py:1729`, `:1734`); ours cannot.

### 5.4 Ordering beyond two buckets

The pre/post split (§1.4) is replaced by simple numbering: migrations apply in `version` order,
and a schema change and its dependent backfill are just two adjacent numbers. Any
`schema → data → schema → data` sequence is expressible without waiting for a release boundary.

### 5.5 Environment parity and verification

Already partly built in this repo, and it becomes the deployment gate:

- `tools/verify_ddl.sh` loads the generated DDL into a throwaway PostgreSQL and reports errors.
  Extended for our own schema, it becomes: apply **every** migration from empty on every CI run,
  then apply them against a restored production-shaped dump, and diff the resulting schema against
  the expected snapshot. A drift is a build failure.
- The reverse check: apply `down.sql` for the release's migrations and confirm the schema returns
  to the previous snapshot.
- Invariant tests run against the migrated database: every constraint in the register
  (F1–U1, plus H1–H4, L1–L6, S1–S7) has a test that attempts to violate it and asserts the
  database refuses.

### 5.6 Seed and reference data

`sync_fixtures` / `sync_standard_items` / `sync_languages` (§1.5) become **seed migrations**:
`INSERT ... ON CONFLICT DO UPDATE` on reference tables (countries, currencies, UOMs, chart-of-
accounts templates, tax regimes), versioned like everything else. There is no filesystem scan, no
`remove_orphan_entities`, and no "delete rows no file claims" step.

Customer-specific configuration (`setting_value`, `ext_field`, `numbering_rule`,
`approval_policy`) is **customer data**, never touched by migrations except by an explicit,
reviewed data migration.

---

## 6. Summary

| Frappe mechanism | Verdict | Our replacement |
|---|---|---|
| Schema reconciled from DocType JSON at migrate time | **Reject** | numbered SQL migrations (§5.1) |
| DDL as a side effect of importing a JSON row | **Reject** | explicit DDL in a migration |
| Three `@atomic` phases; per-patch commits | **Reject** | one transaction per migration |
| `patches.txt` INI of Python module paths | **Reject** | numbered files with checksums |
| `execute:` prefix `exec`ing arbitrary Python | **Reject** | SQL, or reviewed compiled programs |
| `finally:` prefix for deferred patches | **Reject** | explicit ordering by version |
| `skip_failing` reporting success | **Reject** | deploy fails |
| Patch identity by module path, no checksum | **Reject** | checksum verified at startup |
| No `down()` / no rollback | **Reject** | mandatory `down.sql` or declared irreversibility |
| `kill_idle_connections` during migration | **Reject** | `lock_timeout` + online-safe DDL idioms (§5.2) |
| `flags.in_patch` suppressing audit | **Reject** | migrations run as an audited actor (§5.3) |
| Patches `UPDATE`/`DELETE` ledger rows | **Reject** | append-only ledgers; corrections are vouchers (§5.3) |
| `remove_orphan_doctypes` / `remove_orphan_entities` | **Reject** | nothing is derived from a filesystem scan |
| `create_missing_sequences` | **Reject** | sequences are created by migrations and never go missing |
| `trim_tables` as a separate manual step | **Reject** | column drops are migrations |
| Two-app controller override = warning | **Reject** | one implementation per document type (doc 21 §6.5) |
| App install order affecting behaviour | **Reject** | explicit `priority` (doc 21 §6.1) |
| `touched_tables.json` for backup tooling | **Keep the idea** | `migration_effect` rows (§5.3) |
| `before_migrate` / `after_migrate` hooks | **Keep, narrowed** | pre/post-deploy steps in the pipeline, not app hooks |
| Fixtures / standard data sync | **Keep** | seed migrations with `ON CONFLICT DO UPDATE` (§5.6) |
| `DBQueryProgressMonitor` | **Keep the idea** | migration timing + `pg_stat_activity` reporting in the runner |

---

Cross-references: doc 18 (metadata and runtime DDL — the cause of all of this),
doc 20 §2 (audit trail and `flags.in_patch`), doc 21 (hooks, install order),
doc 22 (jobs enqueued by migrate), doc 25 (platform spec),
`tools/verify_ddl.sh`, `docs/design/FINAL-SCHEMA.md`.
