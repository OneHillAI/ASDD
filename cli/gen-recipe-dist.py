#!/usr/bin/env python3
"""Generate the GOOSE_RECIPE_GITHUB_REPO distribution layout.

Goose fetches a recipe by name from a GitHub repo at `<name>/recipe.yaml` at the
repo root. Our canonical recipes live flat in `recipes/<name>.yaml`. This writes
the root `<name>/recipe.yaml` dist copies from those sources, so that once the
repo is public `GOOSE_RECIPE_GITHUB_REPO=OneHillAI/ASDD goose run --recipe test-runner`
resolves. `recipes/` stays the single source of truth; the root copies are
generated, and `--check` fails if they drift (wired into validation/run-base.py).

    python3 cli/gen-recipe-dist.py            # (re)generate the dist copies
    python3 cli/gen-recipe-dist.py --check    # exit nonzero if a copy is missing or stale
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# The deployment recipes a project fetches by name. The developer is
# bring-your-own (spec-driven OP.1), so it is not distributed. interaction-public
# is the execution-free variant a public surface fetches instead of interaction.
RECIPES = ["test-author", "test-runner", "documentation", "interaction", "interaction-public"]


def src(name):
    return os.path.join(ROOT, "recipes", f"{name}.yaml")


def dst(name):
    return os.path.join(ROOT, name, "recipe.yaml")


def main():
    check = "--check" in sys.argv[1:]
    drift = []
    for name in RECIPES:
        want = open(src(name), encoding="utf-8").read()
        path = dst(name)
        have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if have == want:
            continue
        if check:
            drift.append(name)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8").write(want)
            print(f"wrote {name}/recipe.yaml")
    if check:
        if drift:
            sys.stderr.write("recipe dist stale or missing (run cli/gen-recipe-dist.py): "
                             + ", ".join(drift) + "\n")
            return 1
        print("recipe dist in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
