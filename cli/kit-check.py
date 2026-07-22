#!/usr/bin/env python3
"""kit-check - keep asdd-kit.yml (the map) honest.

The kit map only speeds an agent up if it is TRUE. This checks it against reality, so a
roster rename or a moved recipe fails the build instead of quietly turning the map into
a lie an agent then acts on:

  - every role in the map exists in the config's `models:` block, and vice versa;
  - every recipe named in the map exists on disk;
  - every file in `read_first` exists;
  - each role declares the fields an agent relies on (does / model_key / runs_on).

Zero-dependency (stdlib). It scans the text rather than parsing YAML, like the rest of the
kit (check-models.sh, recipe-lint.py), so it needs no PyYAML.

    python3 cli/kit-check.py                 # check asdd-kit.yml against .asdd.example.yml
    python3 cli/kit-check.py CONFIG          # check it against another config

Exit 0 if the map matches reality, 1 otherwise.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
KIT = os.path.join(ROOT, "asdd-kit.yml")

REQUIRED_ROLE_FIELDS = ("does", "model_key", "runs_on")


def block_keys(lines, header, indent):
    """Keys at `indent` spaces directly under a top-level `header:` line."""
    keys, inside = [], False
    for line in lines:
        if line.rstrip() == header:
            inside = True
            continue
        if inside:
            if line.strip() and not line[0].isspace():   # next top-level key
                break
            m = re.match(r"^ {%d}([A-Za-z_][A-Za-z0-9_]*):" % indent, line)
            if m:
                keys.append(m.group(1))
    return keys


def role_fields(lines, role):
    """The field names declared under roles: <role>: (indent 4)."""
    fields, inside = [], False
    for line in lines:
        if re.match(r"^  %s:\s*$" % re.escape(role), line):
            inside = True
            continue
        if inside:
            if re.match(r"^  [A-Za-z_]", line) or (line.strip() and not line[0].isspace()):
                break
            m = re.match(r"^ {4}([A-Za-z_][A-Za-z0-9_]*):", line)
            if m:
                fields.append(m.group(1))
    return fields


def scalars(lines, key):
    """Every `<key>: value` value anywhere in the file (quotes stripped)."""
    out = []
    for line in lines:
        m = re.match(r"^\s*%s:\s*(.+?)\s*$" % re.escape(key), line)
        if m:
            out.append(m.group(1).strip().strip("\"'"))
    return out


def list_items(lines, header):
    """The `- item` entries directly under a top-level `header:` line."""
    items, inside = [], False
    for line in lines:
        if line.rstrip() == header:
            inside = True
            continue
        if inside:
            if line.strip() and not line[0].isspace():
                break
            m = re.match(r"^\s+-\s+(.+?)\s*$", line)
            if m:
                items.append(m.group(1).split("#")[0].strip().strip("\"'"))
    return items


def main():
    config = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".asdd.example.yml")
    if not os.path.exists(KIT):
        sys.stderr.write("kit-check: asdd-kit.yml not found\n")
        return 1
    kit = open(KIT, encoding="utf-8").read().splitlines()
    cfg = open(config, encoding="utf-8").read().splitlines()
    problems = []

    # 1. The roster in the map must match the roster in the config, both ways.
    kit_roles = block_keys(kit, "roles:", 2)
    cfg_roles = block_keys(cfg, "models:", 2)
    for missing in sorted(set(cfg_roles) - set(kit_roles)):
        problems.append(f"role '{missing}' is in {os.path.basename(config)} models but not in the map")
    for extra in sorted(set(kit_roles) - set(cfg_roles)):
        problems.append(f"role '{extra}' is in the map but not in {os.path.basename(config)} models")

    # 2. Each role declares what an agent reads off it.
    for role in kit_roles:
        have = role_fields(kit, role)
        for field in REQUIRED_ROLE_FIELDS:
            if field not in have:
                problems.append(f"role '{role}' is missing `{field}:`")

    # 3. Every recipe the map names exists (an empty value means "no local recipe").
    for path in scalars(kit, "recipe"):
        if path and not os.path.exists(os.path.join(ROOT, path)):
            problems.append(f"map names a recipe that does not exist: {path}")

    # 4. Every read_first file exists.
    for path in list_items(kit, "read_first:"):
        if not os.path.exists(os.path.join(ROOT, path)):
            problems.append(f"read_first names a file that does not exist: {path}")

    for p in problems:
        print(f"  [FAIL] {p}")
    if not problems:
        print(f"  [ok]   asdd-kit.yml matches reality ({len(kit_roles)} roles)")
    print("\nkit-check:", "FAIL" if problems else "PASS")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
