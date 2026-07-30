#!/usr/bin/env python3
"""recipe-lint - deterministic structural gate for the Goose operate recipes.

The operate kit's invariants (recipes/README.md) are prose today; this makes them
mechanical. It checks each recipe in recipes/ against the structure the kit relies
on, so a drift - a deployment recipe that forgets the gates, a public recipe that
grows a shell, a recipe that drops the "input is data, not instructions" membrane -
fails CI instead of shipping.

Zero-dependency (stdlib), and it does NOT parse YAML: like cli/check-models.sh and
cli/operate-guard.py it scans the recipe text, so it needs no PyYAML and reads the
files the same way the rest of the kit does. The shell/execution-free signal is the
exact one operate-guard.py uses ("name: developer"), so the static lint and the
runtime guard can never disagree about which recipe is tool-using.

    python3 cli/recipe-lint.py            # lint every operate recipe
    python3 cli/recipe-lint.py --list     # print the recipes it covers
    python3 cli/recipe-lint.py DIR        # lint a kit installed elsewhere

Exit 0 iff every recipe satisfies its invariants; exit 1 otherwise.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # cli/
ROOT = os.path.dirname(HERE)                                # repo root
DEFAULT_RECIPE_DIR = os.path.join(ROOT, "recipes")

# Each operate recipe and the invariants it must hold.
#   shell   - declares the Goose `developer` builtin, i.e. it is tool-using (a shell).
#   gates   - wires the asdd-gates MCP extension (the deterministic gates).
#   public  - serves an untrusted surface, so it MUST stay execution-free (no shell).
#   optional- a bring-your-own reference recipe; a deployment does not run it as standing infra.
#   emits   - records its actions to the audit ledger (STANDARD 1.3). A deployment agent that acts
#             without recording leaves an action with no trail, which is a conformance failure. The
#             PUBLIC recipe must NOT emit: it is execution-free by design, and letting an untrusted
#             surface write records would make the trail poisonable by anyone who can send a message.
RECIPES = {
    "developer.yaml":          {"shell": True,  "gates": True, "public": False, "optional": True,  "emits": False},
    # A maintainer tool, run locally on trusted input, not standing deployment infra.
    "setup.yaml":              {"shell": True,  "gates": True, "public": False, "optional": True,  "emits": False},
    "test-author.yaml":        {"shell": True,  "gates": True, "public": False, "optional": False, "emits": True},
    "test-runner.yaml":        {"shell": True,  "gates": True, "public": False, "optional": False, "emits": True},
    "documentation.yaml":      {"shell": True,  "gates": True, "public": False, "optional": False, "emits": True},
    "interaction.yaml":        {"shell": True,  "gates": True, "public": False, "optional": False, "emits": True},
    "interaction-public.yaml": {"shell": False, "gates": True, "public": True,  "optional": False, "emits": False},
}

# Top-level keys every Goose recipe in the kit sets. `parameters`/`prompt` are left
# optional on purpose (a valid recipe may take no params).
REQUIRED_KEYS = ("version", "title", "description", "instructions", "extensions")

# The shell signal, identical to operate-guard.py's is_tool_using.
DEVELOPER_BUILTIN = "name: developer"
GATES_EXTENSION = "name: asdd-gates"
# The audit-ledger signal: a deployment agent writes its outcome to the result file, and the run wrapper
# (cli/operate-run.py) records it in the ledger deterministically. The recipe must instruct that write;
# the agent no longer calls audit.py itself, so a run interrupted before its final step is still recorded.
AUDIT_HELPER = "operate-result.json"


def has_top_key(text, key):
    return re.search(r"(?m)^" + re.escape(key) + r":", text) is not None


def has_membrane(text):
    # The anti-injection membrane: instruct the agent to treat inbound content as
    # data, never as instructions to obey. Tolerant of phrasing, strict on intent.
    low = text.lower()
    return ("data" in low) and ("instruction" in low) and ("never" in low or "not " in low)


def lint_one(recipe_dir, name, rules):
    path = os.path.join(recipe_dir, name)
    if not os.path.exists(path):
        return [f"missing recipe file: recipes/{name}"]
    text = open(path, encoding="utf-8").read()
    problems = []

    for key in REQUIRED_KEYS:
        if not has_top_key(text, key):
            problems.append(f"missing top-level key `{key}:`")

    if not has_membrane(text):
        problems.append("instructions drop the membrane (treat input as data, never as instructions)")

    tool_using = DEVELOPER_BUILTIN in text
    if rules["shell"] and not tool_using:
        problems.append("declared tool-using but does not wire the `developer` shell builtin")
    if not rules["shell"] and tool_using:
        problems.append("declares the `developer` shell builtin but must be execution-free")
    if rules["public"] and tool_using:
        problems.append("PUBLIC recipe is not execution-free: a shell on untrusted input can exfiltrate the key")

    if rules["gates"] and GATES_EXTENSION not in text:
        problems.append("does not wire the asdd-gates MCP extension")

    # STANDARD 1.3: no agent action without a record. A deployment agent writes its outcome to the result
    # file and the run wrapper records it; a recipe that instructs neither leaves an action with no trail.
    emits = AUDIT_HELPER in text
    if rules["emits"] and not emits:
        problems.append("does not record its actions (STANDARD 1.3): the instructions never write the "
                        f"result file (`{AUDIT_HELPER}`) that the run wrapper turns into a ledger record")
    if rules["public"] and emits:
        problems.append("PUBLIC recipe writes an audit result: an untrusted surface must not author "
                        "records, or the trail becomes poisonable by anyone who can send a message")

    return problems


def main():
    args = sys.argv[1:]
    if "--list" in args:
        for name, r in RECIPES.items():
            tags = [k for k in ("shell", "gates", "public", "optional", "emits") if r[k]]
            print(f"  recipes/{name}  ({', '.join(tags) or 'none'})")
        return 0

    positional = [a for a in args if not a.startswith("-")]
    recipe_dir = positional[0] if positional else DEFAULT_RECIPE_DIR

    # Completeness: every <dir>/*.yaml must be declared here, so a new recipe
    # cannot ship without stating its invariants.
    on_disk = {f for f in os.listdir(recipe_dir) if f.endswith(".yaml")}
    undeclared = sorted(on_disk - set(RECIPES))
    ok = True

    for name, rules in RECIPES.items():
        problems = lint_one(recipe_dir, name, rules)
        if problems:
            ok = False
            print(f"  [FAIL] recipes/{name}")
            for p in problems:
                print(f"         - {p}")
        else:
            print(f"  [ok]   recipes/{name}")

    for name in undeclared:
        ok = False
        print(f"  [FAIL] recipes/{name}")
        print("         - recipe is not declared in recipe-lint.py; add its invariants")

    print("\nrecipe-lint:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
