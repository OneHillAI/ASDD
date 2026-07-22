#!/usr/bin/env sh
# Test for kit-check.py: the shipped map matches reality, and a roster rename in the
# config is caught (the map going stale is the failure this exists to prevent).
# Exit 0 iff all expectations hold.
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. The map as shipped matches the template's roster.
python3 "$DIR/kit-check.py" >/dev/null 2>&1 || { echo "FAIL: shipped asdd-kit.yml does not match the roster"; fail=1; }

# 2. A renamed role in the config must be caught both ways (missing + extra).
sed 's/^  test_author:/  tester:/' "$ROOT/.asdd.example.yml" > "$TMP/renamed.yml"
out=$(python3 "$DIR/kit-check.py" "$TMP/renamed.yml" 2>&1)
if [ "$?" = "0" ]; then
  echo "FAIL: a renamed role was not caught"; fail=1
fi
echo "$out" | grep -q "tester" || { echo "FAIL: did not report the new role name"; fail=1; }
echo "$out" | grep -q "test_author" || { echo "FAIL: did not report the dropped role name"; fail=1; }

# 3. An added role in the config must be caught.
{ sed '/^models:/a\
  auditor: ""
' "$ROOT/.asdd.example.yml"; } > "$TMP/added.yml" 2>/dev/null
if python3 "$DIR/kit-check.py" "$TMP/added.yml" >/dev/null 2>&1; then
  echo "FAIL: a role added to the config was not caught"; fail=1
fi

[ "$fail" = "0" ] && { echo "kit-check self-test: PASS"; exit 0; } || { echo "kit-check self-test: FAIL"; exit 1; }
