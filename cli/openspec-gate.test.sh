#!/usr/bin/env bash
# Self-test for the OpenSpec readiness gate.
#
# The load-bearing property: OpenSpec's own `validate` exits 0 even when a spec FAILS, so the gate must
# read the verdict from the JSON, not from $?. These cases pin that - a "failed" result must make the
# gate exit non-zero - using recorded fixtures shaped exactly like real `openspec validate --json`
# output (openspec 1.6.0), so the suite runs with or without openspec installed. If openspec IS on PATH,
# a live smoke test at the end validates a real scaffolded change end to end.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/openspec-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0

run_json() {  # <fixture-json> -> prints exit code
  printf '%s' "$1" > "$TMP/v.json"
  python3 "$GATE" --from-json "$TMP/v.json" >/dev/null 2>&1
  echo $?
}
expect() {  # <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (exit $2, want $3)"; fail=1; fi
}

echo "openspec-gate self-test"

# A valid change: passed:1 failed:0 -> READY (exit 0).
expect "valid change is ready" \
  "$(run_json '{"version":"1.0","summary":{"totals":{"items":1,"passed":1,"failed":0}}}')" 0

# THE security case: a failing change. Real `openspec validate` exits 0 here; the gate must exit 1.
expect "failing change is NOT ready (does not inherit openspec exit 0)" \
  "$(run_json '{"version":"1.0","summary":{"totals":{"items":1,"passed":0,"failed":1}}}')" 1

# Mixed batch with any failure -> not ready.
expect "any failure in a batch is not ready" \
  "$(run_json '{"version":"1.0","summary":{"totals":{"items":3,"passed":2,"failed":1}}}')" 1

# Zero items (mistyped change id / empty change) must fail closed, not pass by absence of failures.
expect "zero items fails closed" \
  "$(run_json '{"version":"1.0","summary":{"totals":{"items":0,"passed":0,"failed":0}}}')" 1

# Malformed summary (no integer totals) fails closed.
expect "missing totals fails closed" \
  "$(run_json '{"version":"1.0","summary":{}}')" 1

# A drifted schema version is a setup problem (exit 3), not a silent pass.
expect "unexpected schema version is a setup error, not a pass" \
  "$(run_json '{"version":"9.9","summary":{"totals":{"items":1,"passed":1,"failed":0}}}')" 3

# A wrong binary is a setup error (exit 3), distinct from a bad spec.
python3 "$GATE" some-change --bin openspec-does-not-exist >/dev/null 2>&1
expect "missing openspec binary is a setup error (exit 3)" "$?" 3

# --- live smoke test, only if openspec is actually installed --------------------------------------
if command -v openspec >/dev/null 2>&1; then
  P="$TMP/proj"; mkdir -p "$P"
  ( cd "$P"
    openspec init . --tools none --force >/dev/null 2>&1
    openspec new change add-theme --description "theme" >/dev/null 2>&1
  )
  # Incomplete change (no deltas): real openspec exits 0, gate must say NOT ready.
  ( cd "$P" && python3 "$GATE" add-theme >/dev/null 2>&1 )
  expect "live: incomplete change is not ready" "$?" 1
  # Add a valid delta, then it is ready.
  mkdir -p "$P/openspec/changes/add-theme/specs/ui"
  cat > "$P/openspec/changes/add-theme/specs/ui/spec.md" <<'DELTA'
## ADDED Requirements

### Requirement: Theme Selection
The system SHALL let a user choose a light or dark theme.

#### Scenario: User picks dark theme
- **WHEN** the user selects "dark"
- **THEN** the interface renders in dark colours
DELTA
  ( cd "$P" && python3 "$GATE" add-theme >/dev/null 2>&1 )
  expect "live: completed change is ready" "$?" 0
  # --root is a DIRECTORY: the same change must validate when the gate is run from ELSEWHERE and pointed
  # at the project with --root (regression: --root was mapped to openspec's --store, which wants a store
  # id, not a path, so this returned a false setup-error).
  ( cd / && python3 "$GATE" add-theme --root "$P" >/dev/null 2>&1 )
  expect "live: --root DIR from another cwd is ready" "$?" 0
else
  echo "  skip live smoke test (openspec not installed)"
fi

[ "$fail" = "0" ] && { echo "openspec-gate self-test: PASS"; exit 0; } || { echo "openspec-gate self-test: FAIL"; exit 1; }
