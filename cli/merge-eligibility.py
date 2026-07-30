#!/usr/bin/env python3
"""Deterministic merge-eligibility gate for ASDD - the "conforming loader" floor
(STANDARD 2.2 / 5.2, validation/redteam.md D1). No model required.

Given a change's paths and the merge policy, it returns the routing floor the
merge-reviewer's verdict must respect:
  - any changed path matches a protected path        -> human-approve (always)
  - posture is earned-automerge AND every path is in
    the auto_merge_class AND none is protected        -> autonomous-eligible
  - otherwise                                          -> human-approve (default)

Protected wins unconditionally: even if auto_merge_class is MISCONFIGURED to
include a protected path, that path can never be autonomously merged.

Globs use gitignore-ish semantics (`**` crosses directories, `*` does not).
Zero-dependency (stdlib). Exit codes: 0 = human-approve, 3 = autonomous-eligible.
"""
import argparse
import re
import sys


def _to_regex(pat):
    i, out = 0, ["^"]
    while i < len(pat):
        if pat[i:i + 3] == "**/":
            out.append("(?:.*/)?"); i += 3; continue
        if pat[i:i + 2] == "**":
            out.append(".*"); i += 2; continue
        c = pat[i]
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def matches(path, patterns):
    return any(_to_regex(p).match(path) for p in patterns)


def main():
    ap = argparse.ArgumentParser(description="ASDD deterministic merge-eligibility (conforming loader floor)")
    ap.add_argument("paths", nargs="+", help="changed paths")
    ap.add_argument("--protected", default="", help="comma-separated protected globs")
    ap.add_argument("--auto-merge-class", default="", help="comma-separated auto-merge globs")
    ap.add_argument("--posture", default="advisory", choices=["advisory", "earned-automerge"])
    a = ap.parse_args()
    protected = [p for p in a.protected.split(",") if p]
    amc = [p for p in a.auto_merge_class.split(",") if p]

    hit = [p for p in a.paths if matches(p, protected)]
    if hit:
        print(f"verdict: human-approve  (protected paths: {hit})")
        return 0
    if a.posture == "earned-automerge" and amc and all(matches(p, amc) for p in a.paths):
        print("verdict: autonomous-eligible  (all paths in auto_merge_class, none protected)")
        return 3
    print("verdict: human-approve  (advisory default, or not every path is in auto_merge_class)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
