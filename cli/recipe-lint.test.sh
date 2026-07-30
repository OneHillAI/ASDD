#!/usr/bin/env sh
# Test for recipe-lint.py: the real recipes pass; a regressed copy fails on the two
# invariants that matter most - a deployment recipe dropping the gates, and a public
# recipe growing a shell. Exit 0 iff all expectations hold.
DIR=$(dirname "$0")
ROOT=$(cd "$DIR/.." && pwd)
fail=0

# 1. The shipped recipes lint clean.
if python3 "$DIR/recipe-lint.py" >/dev/null 2>&1; then
  :
else
  echo "FAIL: recipes/ did not lint clean"; fail=1
fi

# Build a mutable fixture copy of the recipes.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT"/recipes/*.yaml "$TMP"/

# 2. A deployment recipe that drops the asdd-gates extension must fail.
grep -v 'name: asdd-gates' "$TMP/documentation.yaml" > "$TMP/documentation.yaml.tmp"
mv "$TMP/documentation.yaml.tmp" "$TMP/documentation.yaml"
if python3 "$DIR/recipe-lint.py" "$TMP" >/dev/null 2>&1; then
  echo "FAIL: a recipe without the gates was accepted"; fail=1
fi
# restore
cp "$ROOT/recipes/documentation.yaml" "$TMP/documentation.yaml"

# 3. A public recipe that grows a shell (the developer builtin) must fail.
printf '\n  - type: builtin\n    name: developer\n' >> "$TMP/interaction-public.yaml"
if python3 "$DIR/recipe-lint.py" "$TMP" >/dev/null 2>&1; then
  echo "FAIL: a public recipe with a shell was accepted"; fail=1
fi

[ "$fail" = "0" ] && { echo "recipe-lint self-test: PASS"; exit 0; } || { echo "recipe-lint self-test: FAIL"; exit 1; }
