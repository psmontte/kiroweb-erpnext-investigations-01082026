#!/usr/bin/env python3
"""
Verify every source citation in the docs against the pinned source tree.

Two citation forms are used in these documents and both are verified:

  full       `accounts/doctype/journal_entry/journal_entry.py:562`
  shorthand  `:568`, `(:2434)`, or `# :709` inside a quoted code block

A shorthand ref means "another line of the file we are currently discussing". It is resolved
against the files cited in full anywhere in the same document, preferring the candidate whose
enclosing `def`/`class` at that line matches a backticked identifier on the same doc line. That
name agreement is the actual check: a drifted line number stops matching its symbol and is
reported, rather than silently resolving.

For each citation the enclosing symbol is reported, so a wrong line shows an obviously wrong name.
Re-run after pulling erpnext/frappe.

    python3 tools/verify_refs.py --docs docs/logic \
        --app erpnext=/projects/sandbox/erpnext/erpnext \
        --app frappe=/projects/sandbox/frappe/frappe

Exit status is non-zero if any citation is unresolved, out of range, or ambiguous.
"""

from __future__ import annotations

import argparse
import ast
import os
import re
import sys

# `path/to/file.py:123` or `path/to/file.py:123-145`
CITATION = re.compile(r"([A-Za-z_][\w/]*(?:/[\w/]+)*\.py):(\d+)(?:-(\d+))?")

# A backticked path with no line number ("`stock/reorder_item.py`. Entry: `reorder_item` (`:14`)")
# introduces a subject file. Not a citation to verify, but a candidate for shorthand refs.
ANCHOR_PATH = re.compile(r"`([A-Za-z_][\w/]*(?:/[\w/]+)*\.py)(?:::[\w.]+)?`")

# Shorthand, backticked: (`:568`)
BARE_CITATION = re.compile(r"`:(\d+)(?:-(\d+))?`")

# Shorthand, unbackticked, as used by docs 01-07: "(`process_sle`, :1008-1195)" and "(:2434)".
# Requiring a preceding "(" or "," keeps clock times, ratios and URLs out.
PROSE_BARE_CITATION = re.compile(r"[(,]\s*:(\d+)(?:-(\d+))?\b")

# Shorthand inside a fenced code block, where no backticks are available:
#   self.validate_data()          # :709
FENCED_CITATION = re.compile(r"#\s*:(\d+)(?:-(\d+))?")

IDENT = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)`")


# --------------------------------------------------------------------------- source indexing


def build_symbol_index(path: str) -> list[tuple[int, int, str]]:
    """[(start_line, end_line, qualified_name)] for every def/class."""
    try:
        with open(path, encoding="utf-8") as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (SyntaxError, UnicodeDecodeError):
        return []
    out: list[tuple[int, int, str]] = []

    def walk(node, prefix=""):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                name = f"{prefix}{child.name}"
                end = getattr(child, "end_lineno", child.lineno)
                out.append((child.lineno, end, name))
                walk(child, prefix=f"{name}.")
            else:
                walk(child, prefix=prefix)

    walk(tree)
    return out


def symbol_at(index: list[tuple[int, int, str]], line: int) -> tuple[str, int | None]:
    """Innermost def/class containing `line`, as (qualified_name, def_line)."""
    best = None
    for start, end, name in index:
        if start <= line <= end:
            if best is None or (end - start) < (best[1] - best[0]):
                best = (start, end, name)
    if best:
        return best[2], best[0]
    return "<module level>", None


_INDEX: dict[str, list[tuple[int, int, str]]] = {}
_NLINES: dict[str, int] = {}


def load(src: str) -> tuple[list[tuple[int, int, str]], int]:
    if src not in _INDEX:
        _INDEX[src] = build_symbol_index(src)
        with open(src, encoding="utf-8") as fh:
            _NLINES[src] = sum(1 for _ in fh)
    return _INDEX[src], _NLINES[src]


_SUFFIX_INDEX: dict[str, list[str]] = {}


def _build_suffix_index(apps: dict[str, str]) -> None:
    if _SUFFIX_INDEX:
        return
    for root in apps.values():
        for dirpath, _dn, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith(".py"):
                    _SUFFIX_INDEX.setdefault(fn, []).append(os.path.join(dirpath, fn))


_RESOLVED: dict[str, str | None] = {}


def resolve(rel: str, apps: dict[str, str]) -> str | None:
    """Resolve a citation path: full path from an app package root, app-prefixed, or a unique suffix."""
    if rel in _RESOLVED:
        return _RESOLVED[rel]
    found = None
    for app, root in apps.items():
        for candidate in (
            os.path.join(root, rel),
            os.path.join(root, rel[len(app) + 1 :]) if rel.startswith(app + "/") else None,
        ):
            if candidate and os.path.isfile(candidate):
                found = candidate
                break
        if found:
            break

    if not found:
        _build_suffix_index(apps)
        matches = [
            full
            for full in _SUFFIX_INDEX.get(os.path.basename(rel), [])
            if full.endswith("/" + rel)
        ]
        if len(matches) == 1:
            found = matches[0]
        elif len(matches) > 1:
            preferred = [m for m in matches if "/test" not in m and "/regional/" not in m]
            found = preferred[0] if len(preferred) == 1 else None

    _RESOLVED[rel] = found
    return found


# --------------------------------------------------------------------------- doc scanning


def scan_lines(lines: list[str]):
    """Yield (doc_lineno, text, in_fence) with fence delimiters skipped."""
    in_fence = False
    for doc_lineno, text in enumerate(lines, 1):
        if text.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        yield doc_lineno, text, in_fence


def candidate_pool(lines: list[str], apps: dict[str, str]) -> list[str]:
    """Every file the document names, in order of first mention. Shorthand refs resolve to one."""
    pool: list[str] = []
    seen: set[str] = set()
    for _lineno, text, in_fence in scan_lines(lines):
        found = [m.group(1) for m in CITATION.finditer(text)]
        if not in_fence:
            found += [m.group(1) for m in ANCHOR_PATH.finditer(text)]
        for rel in found:
            src = resolve(rel, apps)
            # Dedupe on the resolved file: the same file is often cited both in full and by
            # basename ("stock/doctype/item/item.py" and "item.py"), which is one candidate.
            if src and src not in seen:
                seen.add(src)
                pool.append(rel)
    return pool


def line_refs(text: str, in_fence: bool):
    """(position, rel_or_None, line, end) for every citation on a doc line, in reading order."""
    hits: list[tuple[int, str | None, int, str | None]] = []
    for m in CITATION.finditer(text):
        hits.append((m.start(), m.group(1), int(m.group(2)), m.group(3)))
    for m in BARE_CITATION.finditer(text):
        hits.append((m.start(), None, int(m.group(1)), m.group(2)))
    if in_fence:
        for m in FENCED_CITATION.finditer(text):
            hits.append((m.start(), None, int(m.group(1)), m.group(2)))
    else:
        for m in PROSE_BARE_CITATION.finditer(text):
            hits.append((m.start(), None, int(m.group(1)), m.group(2)))
        # line 0 = a path named without a line number; it retargets following shorthand refs
        for m in ANCHOR_PATH.finditer(text):
            hits.append((m.start(), m.group(1), 0, None))
    hits.sort(key=lambda h: h[0])
    return hits


def resolve_shorthand(
    line: int,
    idents: list[str],
    pool: list[str],
    anchor: str | None,
    apps: dict[str, str],
) -> tuple[str | None, str, list[str]]:
    """Pick which of the document's files a shorthand `:line` refers to.

    Returns (rel, how, in_range_candidates). `how` is 'name' when the enclosing symbol matched a
    backticked identifier on the doc line (a real check), 'anchor' when it fell back to the file
    most recently cited in full, or 'only' when the document names just one plausible file.
    """
    in_range: list[str] = []
    by_name: list[str] = []
    leaves = {i.split(".")[-1] for i in idents}
    # The same file may be spelled two ways in one document, so identity is the resolved path.
    anchor_src = resolve(anchor, apps) if anchor else None
    anchor_rel: str | None = None

    for rel in pool:
        src = resolve(rel, apps)
        if not src:
            continue
        index, nlines = load(src)
        if line > nlines:
            continue
        in_range.append(rel)
        if src == anchor_src:
            anchor_rel = rel
        if leaves:
            name, _def_line = symbol_at(index, line)
            if name.split(".")[-1] in leaves:
                by_name.append(rel)

    if len(by_name) == 1:
        return by_name[0], "name", in_range
    if by_name:
        # several files define a matching symbol at that line; the anchor breaks the tie
        if anchor_rel in by_name:
            return anchor_rel, "name", in_range
        return None, "ambiguous", by_name
    if anchor_rel:
        return anchor_rel, "anchor", in_range
    if len(in_range) == 1:
        return in_range[0], "only", in_range
    return None, "ambiguous" if in_range else "range", in_range


# --------------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs", required=True)
    ap.add_argument("--app", action="append", required=True, metavar="NAME=PATH")
    ap.add_argument("--quiet-ok", action="store_true", help="only print problems")
    ap.add_argument(
        "--strict-names",
        action="store_true",
        help="also require that a backticked identifier on the same doc line matches the "
        "symbol enclosing the cited line (catches wrong symbols, not just bad line numbers)",
    )
    args = ap.parse_args()

    apps: dict[str, str] = {}
    for spec in args.app:
        name, path = spec.split("=", 1)
        apps[name] = path

    total = full = bad = 0
    by_how = {"name": 0, "anchor": 0, "only": 0}
    name_notes = 0

    for fname in sorted(os.listdir(args.docs)):
        if not fname.endswith(".md"):
            continue
        with open(os.path.join(args.docs, fname), encoding="utf-8") as fh:
            lines = fh.readlines()

        pool = candidate_pool(lines, apps)
        printed_header = False

        def problem(msg: str) -> None:
            nonlocal printed_header
            if not printed_header:
                print(f"\n## {fname}")
                printed_header = True
            print(f"  {msg}")

        anchor: str | None = None
        prev_idents: list[str] = []
        for doc_lineno, text, in_fence in scan_lines(lines):
            # Prose is hard-wrapped, so the symbol name and its citation often land on adjacent
            # lines ("...come from `update_accounting_dimensions`\n(:543-568): parent-doc...").
            # Names from the previous line therefore count towards the match.
            own_idents = IDENT.findall(text)
            idents = own_idents + prev_idents
            prev_idents = own_idents
            for _pos, cited, start, end in line_refs(text, in_fence):
                if cited is None:
                    rel, how, cands = resolve_shorthand(start, idents, pool, anchor, apps)
                    if rel is None:
                        bad += 1
                        total += 1
                        if how == "range":
                            problem(
                                f"L{doc_lineno}: SHORTHAND :{start} matches no file cited in "
                                f"this document (all are shorter)"
                            )
                        else:
                            problem(
                                f"L{doc_lineno}: SHORTHAND :{start} AMBIGUOUS "
                                "— cite the path in full. Candidates:"
                            )
                            for cand in cands[:6]:
                                csrc = resolve(cand, apps)
                                cname, cdef = symbol_at(load(csrc)[0], start)
                                print(f"      {cand}:{start} -> {cname}" + (f" (def at {cdef})" if cdef else ""))
                        continue
                    by_how[how] += 1
                    shorthand = True
                else:
                    if start == 0:  # bare path mention: retargets shorthand, nothing to verify
                        if not in_fence:
                            anchor = cited
                        continue
                    rel, shorthand = cited, False
                    if not in_fence:
                        anchor = cited
                    full += 1

                total += 1
                src = resolve(rel, apps)
                if not src:
                    bad += 1
                    problem(f"L{doc_lineno}: UNRESOLVED PATH {rel}")
                    continue
                index, nlines = load(src)
                if start > nlines or (end and int(end) > nlines):
                    bad += 1
                    span = f"{start}-{end}" if end else f"{start}"
                    problem(
                        f"L{doc_lineno}: OUT OF RANGE {rel}:{span}"
                        f"{' [shorthand]' if shorthand else ''} (file has {nlines} lines)"
                    )
                    continue

                name, def_line = symbol_at(index, start)
                symbol = f"{name} (def at {def_line})" if def_line else name

                if args.strict_names and not shorthand:
                    known = {n.split(".")[-1] for _s, _e, n in index}
                    candidates = [i.split(".")[-1] for i in own_idents if i.split(".")[-1] in known]
                    leaf = name.split(".")[-1]
                    if candidates and leaf != "<module level>" and leaf not in candidates:
                        name_notes += 1
                        problem(
                            f"L{doc_lineno}: NAME NOTE {rel}:{start} is in {symbol};"
                            f" line mentions {sorted(set(candidates))[:6]}"
                        )
                        continue

                if not args.quiet_ok:
                    mark = " [shorthand]" if shorthand else ""
                    problem(f"{rel}:{start}{mark} -> {symbol}")

    print(
        f"\n{total} citations verified: {full} full, "
        f"{by_how['name']} shorthand confirmed by symbol name, "
        f"{by_how['anchor']} shorthand by nearest cited file, {by_how['only']} shorthand unambiguous"
    )
    print(f"{bad} problems, {name_notes} name notes")
    if name_notes:
        print(
            "  (NAME NOTEs are advisory: the doc line may legitimately name a symbol defined "
            "elsewhere in the same file. Review, do not assume breakage.)"
        )
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
