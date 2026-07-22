#!/usr/bin/env bash
# Self-test for the audit export guards. These are the checks that stop the trail being published:
# the sink is never the governed repo, never public, never unverified, and the default exports nothing.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EX="$HERE/audit-export.sh"
fail=0

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
L="$TMP/ledger.jsonl"
python3 "$ROOT/cli/audit.py" append --ledger "$L" --role review --action review.lens.completed \
  --verdict ok --reasoning t >/dev/null 2>&1

# Run the exporter against a throwaway repo root carrying the given audit config.
run_with_cfg() { # run_with_cfg <yaml-audit-block> [env...]
  local d="$TMP/repo"; rm -rf "$d"; mkdir -p "$d/.github/asdd" "$d/cli"
  cp "$EX" "$d/.github/asdd/audit-export.sh"
  cp "$ROOT/cli/audit.py" "$d/cli/audit.py"
  printf '%s\n' "$1" > "$d/.asdd.yml"
  shift
  env "$@" bash "$d/.github/asdd/audit-export.sh" "$L" 2>&1
}

# 1. Default (no audit block) exports nothing and succeeds: opting in is required.
out="$(run_with_cfg 'runtime: generic')"
echo "$out" | grep -q "nothing exported" && echo "ok: default sink 'none' exports nothing" \
  || { echo "FAIL: default should be inert (got: $out)"; fail=1; }

# 2. The governed repo as sink is refused.
out="$(run_with_cfg 'audit:
  sink: repo
  sink_repo: acme/project' GITHUB_REPOSITORY=acme/project)"
echo "$out" | grep -q "repository being governed" && echo "ok: refuses the governed repo as sink" \
  || { echo "FAIL: should refuse the governed repo (got: $out)"; fail=1; }

# 3. Unverifiable visibility fails closed (no token -> cannot prove it is private).
out="$(run_with_cfg 'audit:
  sink: repo
  sink_repo: acme/ledger' GITHUB_REPOSITORY=acme/project)"
echo "$out" | grep -qE "could not verify|Failing closed" && echo "ok: unverified visibility fails closed" \
  || { echo "FAIL: should fail closed when privacy is unproven (got: $out)"; fail=1; }

# 4. sink: repo with no sink_repo is refused.
out="$(run_with_cfg 'audit:
  sink: repo')"
echo "$out" | grep -q "sink_repo is not set" && echo "ok: refuses sink 'repo' without sink_repo" \
  || { echo "FAIL: should refuse missing sink_repo (got: $out)"; fail=1; }

# 5. An unknown sink is refused rather than silently ignored.
out="$(run_with_cfg 'audit:
  sink: dropbox')"
echo "$out" | grep -q "unknown audit.sink" && echo "ok: refuses an unknown sink" \
  || { echo "FAIL: should refuse an unknown sink (got: $out)"; fail=1; }

# 6. Bring-your-own command sink receives the ledger and runs.
MARK="$TMP/handed.txt"
out="$(run_with_cfg "audit:
  sink: command
  sink_command: \"cp \$1 $MARK\"")"
[ -f "$MARK" ] && echo "ok: byo sink_command received the ledger" \
  || { echo "FAIL: sink_command did not run (got: $out)"; fail=1; }

# 7. A broken chain is not shipped.
BAD="$TMP/bad.jsonl"; sed 's/"verdict":"ok"/"verdict":"tampered"/' "$L" > "$BAD"
d="$TMP/repo2"; mkdir -p "$d/.github/asdd" "$d/cli"
cp "$EX" "$d/.github/asdd/audit-export.sh"; cp "$ROOT/cli/audit.py" "$d/cli/audit.py"
printf 'audit:\n  sink: command\n  sink_command: "true"\n' > "$d/.asdd.yml"
out="$(bash "$d/.github/asdd/audit-export.sh" "$BAD" 2>&1)"
echo "$out" | grep -q "hash chain does not verify" && echo "ok: refuses to ship a broken chain" \
  || { echo "FAIL: should refuse a broken chain (got: $out)"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "audit-export self-test: PASS" || echo "audit-export self-test: FAIL"
exit "$fail"
