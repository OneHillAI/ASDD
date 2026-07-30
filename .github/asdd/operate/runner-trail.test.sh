#!/usr/bin/env bash
# The operate runners (test.sh, docsync.sh) leave an audit trail on EVERY exit path, and their export half
# is INERT without a sink credential: record locally, do NOT attempt a push, and do NOT fail the run. A stub
# audit-export.sh here proves invocation vs non-invocation directly, so a regression that drops the
# AUDIT_SINK_TOKEN guard (turning "record on every exit" into "try to export on every exit") is caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # .github/asdd/operate
ROOT="$(cd "$HERE/../../.." && pwd)"
fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# A throwaway repo so the runner resolves a STUB audit-export.sh and the real deps it needs.
D="$T/repo"; mkdir -p "$D/cli" "$D/.github/asdd/operate" "$D/recipes"
cp "$ROOT/cli/audit.py" "$ROOT/cli/operate-guard.py" "$D/cli/"
cp "$ROOT/recipes/test-runner.yaml" "$D/recipes/" 2>/dev/null || true
printf '#!/usr/bin/env bash\necho called >> "%s/exp.log"\n' "$T" > "$D/.github/asdd/audit-export.sh"
chmod +x "$D/.github/asdd/audit-export.sh"

for pair in "test.sh:test-runner" "docsync.sh:documentation"; do
  runner="${pair%%:*}"; role="${pair##*:}"
  cp "$ROOT/cli/templates/operate/$runner" "$D/.github/asdd/operate/$runner"
  [ "$runner" = "docsync.sh" ] && cp "$ROOT/recipes/documentation.yaml" "$D/recipes/" 2>/dev/null || true
  rm -f "$T/exp.log"

  # 1. No sink credential: must record locally, exit 0, and NOT invoke the exporter.
  env -u ASDD_MODEL_URL -u ASDD_RUNTIME_TOKEN -u AUDIT_SINK_TOKEN ASDD_ACTIVITY_LOG="$T/a.jsonl" \
    bash "$D/.github/asdd/operate/$runner" cx "$T/o.md" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 0 ] && [ -s "$T/a.jsonl" ] && grep -q "\"role\":\"$role\"" "$T/a.jsonl" && [ ! -f "$T/exp.log" ]; then
    echo "  ok   $runner: no-token run records locally, no export, no failure"
  else
    echo "  FAIL $runner: no-token path (rc=$rc record=$([ -s "$T/a.jsonl" ] && echo y) export=$([ -f "$T/exp.log" ] && echo attempted))"; fail=1
  fi

  # 2. With a sink credential (trusted post-merge context): the export half fires.
  rm -f "$T/exp.log" "$T/b.jsonl"
  env -u ASDD_MODEL_URL -u ASDD_RUNTIME_TOKEN AUDIT_SINK_TOKEN=x ASDD_ACTIVITY_LOG="$T/b.jsonl" \
    bash "$D/.github/asdd/operate/$runner" cx "$T/o2.md" >/dev/null 2>&1
  [ -f "$T/exp.log" ] && echo "  ok   $runner: a sink credential triggers the export" \
    || { echo "  FAIL $runner: export not attempted with a token"; fail=1; }
done

echo
[ "$fail" = 0 ] && echo "runner-trail self-test: PASS" || echo "runner-trail self-test: FAIL"
exit "$fail"
