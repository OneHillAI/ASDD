#!/usr/bin/env bash
# ASDD - the deterministic preflight gate. Runs the adopter's OWN test/lint/type command
# (conventions.preflight in .asdd.yml) as a real, blocking check, so a regression the model review missed
# is still caught by the actual suite. This is DISTINCT from the model test-runner agent (asdd-test.yml):
# that agent judges with a model post-merge; this runs the deterministic suite and its exit status IS the
# gate. A spec-and-test framework that never runs the tests deterministically is the gap this closes.
#
# The command is the adopter's own trusted config (not untrusted PR text), so running it in a shell is the
# intended interface (they write `ruff ... && pytest ...`). The workflow that calls this holds no secrets,
# so executing the change's tests on a PR cannot exfiltrate; a fork PR still needs the maintainer's
# fork-workflow approval before it runs at all.
#
# Usage: preflight.sh            (reads .asdd.yml, runs conventions.preflight, exits with its status)
# Env: ASDD_CONFIG overrides the config path.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="${ASDD_CONFIG:-$ROOT/.asdd.yml}"

# Read conventions.preflight (nested one level under conventions:), no YAML dependency. The value is a
# quoted scalar; a `#` inside it is part of the command, so inline-comment stripping is deliberately NOT
# applied here (unlike the lane/path list readers, whose tokens never contain #).
cmd="$(awk '
  /^conventions:/ { inc=1; next }
  inc && /^[A-Za-z]/ { inc=0 }
  inc && /^[[:space:]]+preflight:[[:space:]]*/ {
    line=$0; sub(/^[[:space:]]+preflight:[[:space:]]*/, "", line); print line; exit
  }' "$CFG" 2>/dev/null)"
# Strip ONE matching pair of outer quotes (a double-quoted value may legitimately end in a single quote,
# e.g. "python3 -c 'x'", so a blanket strip of both would eat the command's own inner quote).
case "$cmd" in
  \"*\") cmd="${cmd#\"}"; cmd="${cmd%\"}" ;;
  \'*\') cmd="${cmd#\'}"; cmd="${cmd%\'}" ;;
esac

if [ -z "$cmd" ]; then
  echo "asdd preflight: no conventions.preflight configured; nothing to run. Declare your project's own"
  echo "test/lint/type command (e.g. \"ruff check . && pytest -n 4\") under conventions: to enable the gate."
  exit 0
fi

echo "asdd preflight: running the project's own suite -> $cmd"
bash -c "$cmd"   # the command's exit status IS the gate: a non-zero here fails the check and blocks merge.
