#!/usr/bin/env python3
"""ASDD conventions gate - hold agent output to the HOST project's own workflow.

An existing project already has a way of shipping: where a spec lives, whether the changelog is written
as per-change fragments or edited directly, an impact log it maintains, a house style its CI enforces.
A stock agent knows none of it, so it produces plausible output in the wrong place and a human redoes the
work - which costs more than not running the agent at all.

This is the deterministic half of the fix. `conventions:` in .asdd.yml DECLARES the contract; the agents
READ it (so they emit the right artefacts); this gate CHECKS a produced change against it (so a drifting
agent fails loudly instead of quietly creating rework).

Two rules keep it usable on a mature repository:

  DIFF-SCOPED. Only the change is judged, never the tree. A brownfield repo has thousands of pre-existing
  violations; gating the tree would make adoption impossible on day one. Style is checked on ADDED lines
  only, so the baseline is inherited and the ratchet only tightens.

  DECLARED-ONLY. An unset field is not checked. A project declares what it actually has, and ASDD MAPS to
  it - it never invents a second artefact beside one the project already maintains.

Zero-dependency (stdlib). Exit codes:
  0 = the change conforms to every declared convention
  1 = at least one declared convention is violated
  2 = usage or configuration error (a malformed block, or a declared path that does not exist)

Usage:
  conventions-check.py --config .asdd.yml --validate
  conventions-check.py --config .asdd.yml --changed a.py changelog.d/12.fixed.md --lane feature
  conventions-check.py --config .asdd.yml --diff change.patch --lane feature
  conventions-check.py --config .asdd.yml --print-contract      # the contract as agent-readable text
"""
import argparse
import fnmatch
import os
import re
import sys

# --------------------------------------------------------------------------------------------------
# A minimal YAML subset reader. The kit is zero-dependency by constraint, and the rest of it text-scans
# flat keys; `conventions:` is nested, so we need real (if small) structure. Deliberately restricted to
# what the schema uses - nested maps, scalars, block lists and inline [a, b] lists - and it fails loudly
# rather than guessing, so a malformed block is a configuration error (exit 2), never a silent pass.
# --------------------------------------------------------------------------------------------------


def _scalar(text):
    t = text.strip()
    if not t:
        return ""
    if t.startswith("[") and t.endswith("]"):
        inner = t[1:-1].strip()
        return [_scalar(p) for p in inner.split(",")] if inner else []
    if len(t) >= 2 and t[0] == t[-1] and t[0] in "\"'":
        t = t[1:-1]
        # Only the escapes the schema needs (banned_chars are written as \uXXXX).
        return t.encode("utf-8").decode("unicode_escape") if "\\u" in t else t
    low = t.lower()
    if low in ("true", "false"):
        return low == "true"
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    return t


def _strip_comment(line):
    """Drop a trailing comment, respecting quotes so a '#' inside a string survives."""
    out, quote = [], None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out).rstrip()


def parse_yaml_subset(text):
    """Parse the supported YAML subset into nested dicts/lists. Raises ValueError on anything else."""
    root = {}
    # stack of (indent, container). A container is a dict, or a list for block sequences.
    stack = [(-1, root)]
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        body = line.strip()
        while stack and indent <= stack[-1][0]:
            stack.pop()
        if not stack:
            raise ValueError("inconsistent indentation")
        parent = stack[-1][1]
        if body.startswith("- "):
            item = _scalar(body[2:])
            if not isinstance(parent, list):
                raise ValueError(f"list item outside a list: {body!r}")
            parent.append(item)
            continue
        if ":" not in body:
            raise ValueError(f"not a key: {body!r}")
        key, _, rest = body.partition(":")
        key = key.strip()
        if len(key) >= 2 and key[0] == key[-1] and key[0] in "\"'":
            key = key[1:-1]          # a quoted key, e.g. a glob pattern used as a mapping key
        if not isinstance(parent, dict):
            raise ValueError(f"mapping key inside a list: {body!r}")
        if rest.strip() == "":
            child = {}          # a nested map, or a block list - decided by the next line
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = _scalar(rest)
    _promote_block_lists(root)
    return root


def _promote_block_lists(node):
    """A `key:` followed by `- item` lines parses as an empty dict; turn those into lists."""
    if isinstance(node, dict):
        for k, v in list(node.items()):
            if isinstance(v, dict):
                _promote_block_lists(v)
    return node


def load_conventions(config_path):
    """Return (conventions dict, lanes list). Raises ValueError for a malformed file."""
    with open(config_path) as fh:
        text = fh.read()
    # Re-parse with block-list support: pre-pass rewrites `key:\n  - a` into `key: [a, b]`.
    text = _inline_block_lists(text)
    doc = parse_yaml_subset(text)
    conv = doc.get("conventions") or {}
    if conv and not isinstance(conv, dict):
        raise ValueError("`conventions:` must be a block, not a scalar")
    return conv, doc


def _inline_block_lists(text):
    """Rewrite block sequences into inline lists so the subset parser sees one shape."""
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        stripped = _strip_comment(line)
        if stripped.endswith(":") and not stripped.strip().startswith("- "):
            indent = len(stripped) - len(stripped.lstrip(" "))
            items, j = [], i + 1
            while j < len(lines):
                nxt = _strip_comment(lines[j])
                if not nxt.strip():
                    j += 1
                    continue
                nind = len(nxt) - len(nxt.lstrip(" "))
                if nxt.strip().startswith("- ") and nind > indent:
                    items.append(nxt.strip()[2:].strip())
                    j += 1
                else:
                    break
            if items:
                out.append(f"{stripped} [{', '.join(items)}]")
                i = j
                continue
        out.append(line)
        i += 1
    return "\n".join(out)


# --------------------------------------------------------------------------------------------------
# The checks. Each returns (ok, label, detail). Only DECLARED fields produce a check.
# --------------------------------------------------------------------------------------------------


def _as_list(v):
    if v is None or v == "":
        return []
    return v if isinstance(v, list) else [v]


def normalise_paths(items):
    """Split any newline-joined argument into separate paths.

    A caller naturally writes `--changed "$(git diff --name-only)"`, and in some shells that arrives as
    ONE argument containing newlines. Left alone it matches no pattern, every rule sits silent, and the
    gate PASSES a change it never actually judged. Splitting here is the difference between judging the
    change and accidentally approving it, so this is fail-closed behaviour, not convenience.
    """
    out, seen = [], set()
    for item in items or []:
        for part in str(item).splitlines():
            part = part.strip()
            if part and part not in seen:
                seen.add(part)
                out.append(part)
    return out


def changed_paths_from_diff(diff_text):
    """Paths touched by a unified diff (the +++ side; /dev/null for a deletion is skipped)."""
    paths = []
    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            p = line[4:].strip()
            if p == "/dev/null":
                continue
            if p.startswith(("b/", "a/")):
                p = p[2:]
            paths.append(p)
    return paths


def added_files_from_diff(diff_text):
    """Files this diff CREATES (old side is /dev/null), as opposed to files it merely edits.

    The distinction matters for a rule like "a new guide must be listed in the index": editing an
    existing guide needs no index change, so firing on every touch would cry wolf, and a gate that cries
    wolf gets bypassed rather than obeyed.
    """
    added, pending_new = [], False
    for line in diff_text.splitlines():
        if line.startswith("--- "):
            pending_new = line[4:].strip() == "/dev/null"
        elif line.startswith("+++ "):
            p = line[4:].strip()
            if pending_new and p != "/dev/null":
                added.append(p[2:] if p.startswith(("b/", "a/")) else p)
            pending_new = False
    return added


def added_lines_from_diff(diff_text):
    """(path, line) for every ADDED line. The ratchet: pre-existing content is never judged."""
    out, current = [], None
    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            p = line[4:].strip()
            current = p[2:] if p.startswith(("b/", "a/")) else p
        elif line.startswith("+") and not line.startswith("+++"):
            if current and current != "/dev/null":
                out.append((current, line[1:]))
    return out


def check_changelog(conv, changed, lane, exempt):
    cl = conv.get("changelog")
    if not isinstance(cl, dict):
        return []
    mode = cl.get("mode")
    if mode != "fragment":
        return []
    results = []
    assembled = cl.get("assembled_file")
    if assembled and assembled in changed:
        results.append((False, "changelog: assembled file edited directly",
                        f"{assembled} is assembled at a release cut from fragments; a change must add a "
                        f"fragment instead of editing it"))
    if lane in exempt:
        return results
    glob = cl.get("fragment_glob")
    if not glob:
        return results
    frags = [p for p in changed if fnmatch.fnmatch(p, glob)]
    if not frags:
        results.append((False, "changelog: no fragment",
                        f"this change adds no changelog fragment matching {glob} "
                        f"(pattern: {cl.get('fragment_pattern') or glob})"))
        return results
    cats = _as_list(cl.get("categories"))
    if cats:
        for f in frags:
            parts = os.path.basename(f).split(".")
            cat = parts[1] if len(parts) >= 3 else None
            if cat not in cats:
                results.append((False, "changelog: bad fragment category",
                                f"{f} has category {cat!r}; allowed: {', '.join(cats)}"))
    if not results:
        results.append((True, "changelog fragment", ", ".join(frags)))
    return results


def check_docs(conv, changed, lane, exempt, added_files=None, have_diff=False):
    """A change that ships something must also update the docs that describe it.

    Declared as pairs: when a change touches `when`, it must also touch one of `require`. This is the
    rule that catches a command shipping undocumented, which is otherwise invisible until someone goes
    looking for it in a reference that never mentioned it. Diff-scoped like everything else here: it
    asks what THIS change did, never whether the repo's docs are complete.
    """
    rules = conv.get("docs")
    if not isinstance(rules, dict) or not rules or lane in exempt:
        return []
    results = []
    for when, rule in rules.items():
        if not isinstance(rule, dict):
            continue
        require = _as_list(rule.get("require"))
        if not when or not require:
            continue
        # `on: added` fires only when the change CREATES a matching file. Editing an existing guide
        # needs no index entry; adding one does. Without a diff we cannot tell the two apart, so we say
        # so out loud rather than skip quietly: an unevaluated rule that looks like a pass is the
        # fail-open shape this gate exists to avoid.
        on_added = str(rule.get("on") or "changed").strip() == "added"
        if on_added and not have_diff:
            results.append((True, f"docs rule for {when} not evaluated",
                            "it applies to newly added files, which needs --diff to detect; pass the "
                            "change as a diff to enforce it"))
            continue
        pool = (added_files or []) if on_added else changed
        triggered = [p for p in pool if fnmatch.fnmatch(p, when)]
        if not triggered:
            continue
        satisfied = [p for p in changed if any(fnmatch.fnmatch(p, r) for r in require)]
        if satisfied:
            results.append((True, f"docs updated for {when}", ", ".join(satisfied)))
        else:
            why = rule.get("why") or "the documentation that describes it must change with it"
            results.append((False, f"docs not updated for {when}",
                            f"this change touches {', '.join(triggered[:3])} but updates none of "
                            f"{', '.join(require)}: {why}"))
    return results


def check_impact_log(conv, changed, lane, exempt):
    path = conv.get("impact_log")
    if not path or lane in exempt:
        return []
    if path in changed:
        return [(True, "impact log updated", path)]
    return [(False, "impact log not updated",
             f"this project records one entry per change in {path}; the change does not touch it")]


def check_spec(conv, changed, lane, exempt):
    d = conv.get("spec_dir")
    if not d or lane in exempt:
        return []
    hit = [p for p in changed if p.startswith(d.rstrip("/") + "/")]
    if hit:
        return [(True, "spec present", ", ".join(hit))]
    return [(False, "no spec for the change",
             f"this project specs a change under {d}/ before implementing it")]


def check_style(conv, added):
    style = conv.get("style")
    if not isinstance(style, dict):
        return []
    banned = _as_list(style.get("banned_chars"))
    if not banned or not added:
        return []
    bad = []
    for path, line in added:
        for ch in banned:
            if ch and ch in line:
                bad.append((path, ch, line.strip()[:70]))
    if bad:
        return [(False, "house style: banned character in an added line",
                 "; ".join(f"{p}: {c!r} in {snippet!r}" for p, c, snippet in bad[:4]))]
    return [(True, "house style", "no banned characters in added lines")]


def validate_config(conv, repo_root):
    """A declared path that does not exist is a misconfiguration, not a change violation."""
    problems = []
    for key in ("impact_log", "spec_dir"):
        val = conv.get(key)
        if val and not os.path.exists(os.path.join(repo_root, val)):
            problems.append(f"conventions.{key} points at {val!r}, which does not exist in the repo")
    cl = conv.get("changelog")
    if isinstance(cl, dict):
        mode = cl.get("mode")
        if mode not in (None, "", "fragment", "direct", "none"):
            problems.append(f"conventions.changelog.mode must be fragment|direct|none, got {mode!r}")
        if mode == "fragment" and not cl.get("fragment_glob"):
            problems.append("conventions.changelog.mode is fragment but fragment_glob is not set")
    return problems


def render_contract(conv):
    """The contract as text an agent can be handed. Prose, because it goes into a prompt."""
    if not conv:
        return "This project declares no ASDD conventions; use the repository's existing patterns."
    out = ["This project's OWN workflow. Treat it as a binding output contract, not advice.",
           "Produce these artefacts in these places. Do NOT invent a parallel artefact.", ""]
    d = conv.get("spec_dir")
    if d:
        out.append(f"- Spec: a change is specified under {d}/ before it is implemented.")
    cl = conv.get("changelog")
    if isinstance(cl, dict) and cl.get("mode") == "fragment":
        out.append(f"- Changelog: add ONE fragment matching {cl.get('fragment_pattern') or cl.get('fragment_glob')}. "
                   f"Categories: {', '.join(_as_list(cl.get('categories'))) or 'any'}. "
                   f"Do NOT edit {cl.get('assembled_file') or 'the assembled changelog'} directly - it is "
                   f"assembled at a release cut.")
    elif isinstance(cl, dict) and cl.get("mode") == "direct":
        out.append(f"- Changelog: edit {cl.get('assembled_file') or 'CHANGELOG.md'} directly.")
    if conv.get("impact_log"):
        out.append(f"- Impact log: add one entry per change to {conv['impact_log']}.")
    docs_rules = conv.get("docs")
    if isinstance(docs_rules, dict):
        for when, rule in docs_rules.items():
            if isinstance(rule, dict) and rule.get("require"):
                out.append(f"- Docs: if you change {when}, you must also update "
                           f"{', '.join(_as_list(rule['require']))}"
                           + (f" ({rule['why']})." if rule.get("why") else "."))
    style = conv.get("style")
    if isinstance(style, dict):
        if style.get("spelling"):
            out.append(f"- Spelling: {style['spelling']}.")
        if _as_list(style.get("banned_chars")):
            out.append("- Never emit these characters: " +
                       ", ".join(repr(c) for c in _as_list(style["banned_chars"])) +
                       " (the project's CI rejects them).")
    if conv.get("preflight"):
        out.append(f"- Before proposing a change, this must pass: {conv['preflight']}")
    for ex in _as_list(conv.get("exemplars")):
        out.append(f"- Exemplar of house style: {ex}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description="Check a change against the host project's declared conventions.")
    ap.add_argument("--config", default=".asdd.yml", help="the ASDD config holding the conventions block")
    ap.add_argument("--changed", nargs="*", default=None, help="paths the change touches")
    ap.add_argument("--diff", help="a unified diff of the change (adds added-line style checking)")
    ap.add_argument("--lane", default="", help="the change's lane label (exempt lanes skip spec/changelog)")
    ap.add_argument("--validate", action="store_true", help="only validate the conventions block itself")
    ap.add_argument("--print-contract", action="store_true", help="print the contract for an agent prompt")
    a = ap.parse_args()

    try:
        conv, _doc = load_conventions(a.config)
    except FileNotFoundError:
        sys.stderr.write(f"conventions-check: config not found: {a.config}\n")
        return 2
    except ValueError as e:
        sys.stderr.write(f"conventions-check: malformed config: {e}\n")
        return 2

    if a.print_contract:
        print(render_contract(conv))
        return 0

    repo_root = os.path.dirname(os.path.abspath(a.config)) or "."
    problems = validate_config(conv, repo_root)
    if a.validate:
        if not conv:
            print("conventions: none declared (nothing to check)")
            return 0
        for p in problems:
            print(f"  [FAIL] {p}")
        print("RESULT:", "INVALID" if problems else "VALID")
        return 1 if problems else 0
    if problems:
        for p in problems:
            sys.stderr.write(f"conventions-check: {p}\n")
        return 2

    if not conv:
        print("conventions: none declared; nothing to check.")
        return 0

    changed = normalise_paths(a.changed)
    added, added_files, have_diff = [], [], False
    if a.diff:
        try:
            with open(a.diff) as fh:
                diff_text = fh.read()
        except OSError as e:
            sys.stderr.write(f"conventions-check: cannot read diff: {e}\n")
            return 2
        changed += [p for p in changed_paths_from_diff(diff_text) if p not in changed]
        added = added_lines_from_diff(diff_text)
        added_files = added_files_from_diff(diff_text)
        have_diff = True
    if not changed and not added:
        sys.stderr.write("conventions-check: give --changed and/or --diff (nothing to judge)\n")
        return 2

    exempt = set(_as_list(conv.get("exempt_lanes")) or ["chore"])
    results = []
    results += check_changelog(conv, changed, a.lane, exempt)
    results += check_docs(conv, changed, a.lane, exempt, added_files, have_diff)
    results += check_impact_log(conv, changed, a.lane, exempt)
    results += check_spec(conv, changed, a.lane, exempt)
    results += check_style(conv, added)

    print("conventions check (the change only; the existing tree is never judged)\n")
    for ok, label, detail in results:
        print(f"  [{'ok  ' if ok else 'FAIL'}] {label}")
        if detail:
            print(f"         {detail}")
    fails = [r for r in results if not r[0]]
    print()
    if fails:
        print(f"RESULT: NOT CONFORMING - {len(fails)} declared convention(s) violated.")
        return 1
    print("RESULT: CONFORMING" + ("" if results else " (no declared convention applies to this change)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
