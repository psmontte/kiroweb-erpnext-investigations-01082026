#!/usr/bin/env python3
"""
Verify every `file.py:NNN` citation in docs/logic/*.md against the source tree.

For each citation it reports the enclosing `def`/`class` at that line, so a drifted
line number shows up as an obviously wrong symbol name. Re-run after pulling erpnext.

    python3 tools/verify_refs.py --docs docs/logic \
        --app erpnext=/projects/sandbox/erpnext/erpnext \
        --app frappe=/projects/sandbox/frappe/frappe
"""

from __future__ import annotations

import argparse
import ast
import os
import re
import sys

CITATION = re.compile(r"([A-Za-z_][\w/]*(?:/[\w/]+)*\.py):(\d+)(?:-(\d+))?")


def build_symbol_index(path: str) -> list[tuple[int, int, str]]:
    """[(start_line, end_line, qualified_name)] for every def/class, innermost last."""
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


def symbol_at(index: list[tuple[int, int, str]], line: int) -> str:
    best = None
    for start, end, name in index:
        if start <= line <= end:
            if best is None or (end - start) < (best[1] - best[0]):
                best = (start, end, name)
    if best:
        return f"{best[2]} (def at {best[0]})"
    return "<module level>"


_SUFFIX_INDEX: dict[str, list[str]] = {}


def _build_suffix_index(apps: dict[str, str]) -> None:
    if _SUFFIX_INDEX:
        return
    for root in apps.values():
        for dirpath, _dn, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith(".py"):
                    full = os.path.join(dirpath, fn)
                    _SUFFIX_INDEX.setdefault(fn, []).append(full)


def resolve(rel: str, apps: dict[str, str]) -> str | None:
    """Resolve a citation path.

    Accepts a full path relative to the app package root, an app-prefixed path, or a
    bare/partial path (e.g. `gl_entry.py`, `services/taxes.py`) resolved by unique suffix.
    """
    for app, root in apps.items():
        for candidate in (
            os.path.join(root, rel),
            os.path.join(root, rel[len(app) + 1 :]) if rel.startswith(app + "/") else None,
        ):
            if candidate and os.path.isfile(candidate):
                return candidate

    _build_suffix_index(apps)
    matches = [
        full
        for full in _SUFFIX_INDEX.get(os.path.basename(rel), [])
        if full.endswith("/" + rel) or full.endswith(os.sep + rel)
    ]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        # prefer accounts/ or stock/ over regional or test copies
        preferred = [m for m in matches if "/test" not in m and "/regional/" not in m]
        if len(preferred) == 1:
            return preferred[0]
        return None
    return None


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

    index_cache: dict[str, list] = {}
    total = unresolved = out_of_range = name_mismatch = 0
    ident_re = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)`")

    for fname in sorted(os.listdir(args.docs)):
        if not fname.endswith(".md"):
            continue
        doc_path = os.path.join(args.docs, fname)
        with open(doc_path, encoding="utf-8") as fh:
            lines = fh.readlines()

        printed_header = False
        for doc_lineno, text in enumerate(lines, 1):
            for m in CITATION.finditer(text):
                rel, start, end = m.group(1), int(m.group(2)), m.group(3)
                total += 1
                src = resolve(rel, apps)
                if not src:
                    unresolved += 1
                    if not printed_header:
                        print(f"\n## {fname}")
                        printed_header = True
                    print(f"  L{doc_lineno}: UNRESOLVED PATH {rel}")
                    continue
                if src not in index_cache:
                    index_cache[src] = build_symbol_index(src)
                    with open(src, encoding="utf-8") as sf:
                        index_cache[src + "::len"] = sum(1 for _ in sf)
                nlines = index_cache[src + "::len"]
                if start > nlines or (end and int(end) > nlines):
                    out_of_range += 1
                    if not printed_header:
                        print(f"\n## {fname}")
                        printed_header = True
                    print(f"  L{doc_lineno}: OUT OF RANGE {rel}:{start} (file has {nlines} lines)")
                    continue
                symbol = symbol_at(index_cache[src], start)

                if args.strict_names:
                    known = {name.split(".")[-1] for _s, _e, name in index_cache[src]}
                    idents = ident_re.findall(text)
                    # Only compare against identifiers that are real symbols in the cited
                    # file; prose mentioning column names must not trigger a mismatch.
                    candidates = [i.split(".")[-1] for i in idents if i.split(".")[-1] in known]
                    if candidates:
                        sym_leaf = symbol.split(" ")[0].split(".")[-1]
                        if sym_leaf != "<module" and not any(c == sym_leaf for c in candidates):
                            name_mismatch += 1
                            if not printed_header:
                                print(f"\n## {fname}")
                                printed_header = True
                            print(
                                f"  L{doc_lineno}: NAME NOTE {rel}:{start} is in {symbol};"
                                f" line mentions {sorted(set(candidates))[:6]}"
                            )
                            continue

                if not args.quiet_ok:
                    if not printed_header:
                        print(f"\n## {fname}")
                        printed_header = True
                    print(f"  {rel}:{start} -> {symbol}")

    print(
        f"\n{total} citations, {unresolved} unresolved paths, "
        f"{out_of_range} out of range, {name_mismatch} name notes"
    )
    if name_mismatch:
        print(
            "  (NAME NOTEs are advisory: the doc line may legitimately name a symbol defined "
            "elsewhere in the same file. Review, do not assume breakage.)"
        )
    return 1 if (unresolved or out_of_range) else 0


if __name__ == "__main__":
    sys.exit(main())
