#!/bin/sh
# Self-test for operate-guard.py: the security classification holds.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
G="python3 $HERE/operate-guard.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

# tool-using recipe (has the developer builtin) on UNTRUSTED input -> refuse (exit 1)
if $G "$ROOT/recipes/documentation.yaml" --input untrusted >/dev/null 2>&1; then
  fail "tool-using recipe allowed on untrusted input"
fi

# tool-using recipe on TRUSTED input -> allow (exit 0)
$G "$ROOT/recipes/documentation.yaml" --input trusted >/dev/null 2>&1 \
  || fail "tool-using recipe refused on trusted input"

# execution-free recipe (no shell) on UNTRUSTED input -> allow (exit 0)
$G "$ROOT/recipes/interaction-public.yaml" --input untrusted >/dev/null 2>&1 \
  || fail "execution-free recipe refused on untrusted input"

echo "operate-guard.test.sh: PASS"
