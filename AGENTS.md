# AGENTS.md — erpnext-research

> # ⛔ THIS REPOSITORY IS ABANDONED — 4 August 2026
>
> **Do not work here. Do not edit these files. Nothing written here will be used.**
>
> Everything moved to:
>
> ```
> D:\uni-projects\uni-apps\unibizapp\knowledge\erpnext-research\
> ```
>
> That is the live copy and the only one anyone maintains. It carries every file from this repository —
> `docs/`, `schema/`, `tools/`, `semantic-review/`, and the pinned upstream source trees — plus work done
> after this repository's final commit.
>
> **Start there with `START-HERE-HANDOFF.md`.** It explains the move, what has and has not been read, the
> decisions taken, and the reading order for the next session.
>
> **Why it moved:** the ERP is being rebuilt inside `unibizapp`, so this research had to sit beside the code
> and planning documents it will be compared against — `apps/backend`, and
> `knowledge/doc-implementations/001-db-backend-rewrite-07-06-26`. Keeping it in a separate repository meant
> every cross-reference broke.
>
> This repository is kept only as the git history of the investigation. It is not deleted, and it is never
> a source. Everything below this box describes how the work is done in the **new** location.

## Rule 1 — how to write to the owner

**Ultra concise. Plain everyday English. Short sentences. Emojis that flag what needs attention.**

The owner has eye strain and runs several projects at once. They read the ⛔ and ❓ lines. Assume
everything else is unread.

**Shape, every time:**

```
## READ THIS ONLY:

⛔ <something is wrong AND only the owner can fix it — one sentence, self-contained>
❓ <a decision only the owner can make — one sentence, self-contained>

## TL;DR

| | |
|---|---|
| **Answer** | <the direct answer, one sentence, always first> |
| ✓ | <done> |
| ℹ️ | <bad news I am already handling> |
| ▪ | <next step> |
```

**Hard rules:**

- Nothing above `## READ THIS ONLY:`. No greeting, no preamble.
- If nothing is wrong and nothing is waiting on the owner, **write no ⛔ or ❓ at all** and drop that section.
- ⛔ only if **both**: something is wrong, **and** the owner must act. If the answer to "so what do I do?"
  is "nothing, you are fixing it", it is `ℹ️` instead.
- One sentence per table row. Six rows maximum.
- **Never re-explain something the owner has already pushed back on.** If they say a passage is bad, delete
  it. Do not rewrite it a third time. Repeating an explanation they rejected is the failure, not the wording.
- No jargon. Say "the saving part", not "the orchestration layer". Say "safe to run twice", not "idempotent".
- Keep every real name — file paths, table names, commands — beside the plain sentence, never instead of it.
- Questions get lettered options `a`, `b`, `c`, one recommendation marked ➡️. The owner replies `1a 2b`.
- Long write-ups go in a file. The reply links it in one line.

**Emoji meanings — these only:**

| | |
|---|---|
| ⛔ | Wrong, and the owner must act. **Always read.** |
| ❓ | A decision only the owner can make. **Always read.** |
| ➡️ | My recommended option inside a question. |
| ℹ️ | Bad news I am handling. Assume unread. |
| ✓ | Done. Assume unread. |
| ▪ | Next step. Assume unread. |

Do not use ⚠️. It reads as decoration and gets skipped. A real problem is ⛔.

## Rule 2 — decide it yourself

Use your ERP knowledge. If you can see which behaviour is correct accounting, build that one and say so in
one line. Do not hand the decision back.

Ask the owner only for: money or posting behaviour that is currently correct, a business rule you would
otherwise be guessing (a tax rate, a statutory base, a posting convention), or something hard to undo.

## Rule 3 — no workarounds

Never propose a skip, a stub, a weakened test or a narrowed acceptance bar — not even as an option.
Fix the cause, or say plainly that it is blocked, name the missing thing, and leave it red.
Time and complexity are not constraints and must never appear as a reason for doing less.

## Rule 4 — no repository wins by default; the better design wins, item by item

**Corrected 4 Aug 2026.** The earlier version of this rule said `FINAL-SCHEMA.md` was the sole authority.
That was wrong, and the reason matters: **the agent who wrote `erpnext-research` never had access to the
`unibizapp` backend or frontend code.** It designed 283 tables in ignorance of a design the owner and team
spent months on. Being newer is not being better.

- `docs/design/FINAL-SCHEMA.md` — 283 tables, every rule traced to a line of real ERPNext source.
- `unibizapp/knowledge/doc-implementations/001-…` — 171 decisions, 20 plans, 6 specs, 44 lessons,
  7 risk playbooks, a scar catalogue. Months of work, and **written by people who had the code in front of
  them**.
- ERPNext itself — **studied, never adopted as-is.** It is the thing we are trying to beat.

Where the two disagree, the disagreement is resolved **in writing, one item at a time, with the reason
recorded**. Neither side wins because of where it lives.

**Read `001` before proposing anything.** Several things that look like new design work are already solved
there, often better and with real incident history attached — `docs/playbooks/PB-04-generated-vs-handwritten.md`
answers the generator-safety question, and `docs/playbooks/001-SCAR-CATALOG.md` records what went wrong
when the rule was broken.

## Rule 5 — verify before claiming

Every claim about ERPNext cites a file and line in `upstream/`. Before saying the docs are sound, run:

```bash
python tools/verify_refs.py --docs docs/logic \
  --app erpnext=upstream/erpnext/erpnext \
  --app frappe=upstream/frappe/frappe \
  --app india_compliance=upstream/india_compliance/india_compliance --quiet-ok
# repeat for docs/scenarios and docs/design
python tools/coverage_audit.py
PYTHONPATH=tools python tools/update_coverage_doc.py --check
```

Use `python`, not `python3`. Current state: **6,087 citations, 0 problems.**
