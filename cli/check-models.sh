#!/usr/bin/env bash
# ASDD - check-models: enforce the model-heterogeneity invariant.
#   developer MUST differ from every test model (test_author, test_runner); reviewer SHOULD differ (warn).
# A model cannot meaningfully test or review its own code, so the developer and tester run different
# models (different families preferred). Reads the `models:` block of a config file.
#
# Usage: bash cli/check-models.sh [--strict] [CONFIG]
#   CONFIG defaults to .asdd.yml. Unset values pass (a template / dry-run state) unless
#   --strict, which additionally requires developer and tester to be set and reviewer to differ.
set -euo pipefail

STRICT=0; CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict)  STRICT=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*)        echo "unknown option: $1" >&2; exit 2 ;;
    *)         CONFIG="$1" ;;
  esac
  shift
done
CONFIG="${CONFIG:-.asdd.yml}"
[ -f "$CONFIG" ] || { echo "error: config not found: $CONFIG" >&2; exit 2; }

# Read a key from the `models:` block: `  <key>: "value"` (comment + quotes stripped).
model() {
  awk -v k="$1" '
    /^models:/    { inblk=1; next }
    /^[A-Za-z]/   { inblk=0 }
    inblk {
      line=$0
      sub(/#.*/, "", line)
      if (line ~ ("^[[:space:]]+" k ":")) {
        sub(("^[[:space:]]+" k ":[[:space:]]*"), "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }' "$CONFIG"
}
strip() { local v="$1"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; printf '%s' "$v"; }

DEV="$(strip "$(model developer)")"
TA="$(strip "$(model test_author)")"
TR="$(strip "$(model test_runner)")"
LEGACY="$(strip "$(model tester)")"
REV="$(strip "$(model reviewer)")"
fail=0

check_test() {  # label value: a set test model MUST differ from the developer
  [ -z "$2" ] && return 0
  if [ "$2" = "$DEV" ]; then
    echo "FAIL: $1 and developer use the same model ('$DEV'). They MUST differ (heterogeneity invariant)." >&2
    fail=1
  else
    echo "ok: developer ('$DEV') != $1 ('$2')."
  fi
}

if [ -z "$DEV" ]; then
  if [ "$STRICT" -eq 1 ]; then
    echo "FAIL: developer model must be set (--strict)." >&2
    fail=1
  else
    echo "models: developer not configured in $CONFIG - skipping (pass --strict to require)."
  fi
else
  if [ "$STRICT" -eq 1 ] && [ -z "$TA" ] && [ -z "$TR" ] && [ -z "$LEGACY" ]; then
    echo "FAIL: at least one test model (test_author / test_runner) must be set (--strict)." >&2
    fail=1
  fi
  check_test "test_author" "$TA"
  check_test "test_runner" "$TR"
  check_test "tester" "$LEGACY"
fi

if [ -n "$REV" ] && [ -n "$DEV" ] && [ "$REV" = "$DEV" ]; then
  echo "warning: reviewer uses the same model as developer ('$DEV'); it SHOULD differ." >&2
  [ "$STRICT" -eq 1 ] && fail=1
fi

exit "$fail"
