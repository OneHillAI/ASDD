#!/usr/bin/env bash
# Self-test for the deterministic preflight gate (.github/asdd/preflight.sh): it runs the adopter's own
# conventions.preflight command and its exit status IS the gate - a passing suite passes, a failing suite
# (a deliberately broken test) fails the check, and an unconfigured preflight is a no-op that passes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PF="$HERE/preflight.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

run() { ASDD_CONFIG="$1" bash "$PF" >/dev/null 2>&1; echo "$?"; }

# 1. A passing suite passes the gate.
printf 'conventions:\n  preflight: "exit 0"\n' > "$T/pass.yml"
[ "$(run "$T/pass.yml")" = 0 ] && ok "a passing preflight passes the gate" || bad "passing preflight"

# 2. A failing suite fails the gate (a regression is caught deterministically).
printf 'conventions:\n  preflight: "exit 7"\n' > "$T/fail.yml"
[ "$(run "$T/fail.yml")" != 0 ] && ok "a failing preflight fails the gate" || bad "failing preflight did not fail"

# 3. A real command: a passing then a deliberately broken python check.
printf "conventions:\n  preflight: \"python3 -c 'raise SystemExit(0)'\"\n" > "$T/realok.yml"
[ "$(run "$T/realok.yml")" = 0 ] && ok "a real passing check passes" || bad "real passing check"
printf "conventions:\n  preflight: \"python3 -c 'raise SystemExit(1)'\"\n" > "$T/realbad.yml"
[ "$(run "$T/realbad.yml")" != 0 ] && ok "a real broken check fails the gate" || bad "real broken check did not fail"

# 4. No preflight configured: a no-op that passes and says so (opt-in).
printf 'lanes:\n  - feature\n' > "$T/none.yml"
out="$(ASDD_CONFIG="$T/none.yml" bash "$PF" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "nothing to run"; then
  ok "unconfigured preflight is an opt-in no-op"
else
  bad "unconfigured preflight (rc=$rc)"
fi

echo
[ "$fail" = 0 ] && echo "preflight self-test: PASS" || echo "preflight self-test: FAIL"
exit "$fail"
