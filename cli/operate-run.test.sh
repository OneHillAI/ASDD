#!/usr/bin/env bash
# Self-test for the operate-run wrapper. The load-bearing property is that a record is emitted EVEN WHEN
# THE RUN PRODUCED NOTHING: an operate agent used to record itself as its last step, so a provider
# timeout mid-run lost the action silently. The wrapper makes emission the wrapper's job, so the record
# survives an interrupted run. `--skip-goose` exercises the emit logic without a live model.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OR="$DIR/operate-run.py"
AUD="$DIR/audit.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

echo "operate-run self-test"

# 1. THE property: run 'failed', no result file -> a record is STILL emitted, marked incomplete.
L="$TMP/a.jsonl"
python3 "$OR" --role test-runner --recipe /dev/null --ledger "$L" --skip-goose --goose-exit 1 >/dev/null 2>&1
if [ -s "$L" ]; then
  got="$(python3 -c "import json;r=json.load(open('$L'));print(r['agent']['role'],r['action'],r['outcome'].get('action_taken'))")"
  [ "$got" = "test-runner test-runner.run incomplete" ] \
    && ok "an interrupted run with no result still emits a record (marked incomplete)" \
    || bad "minimal record shape wrong: $got"
else
  bad "NO record emitted for an interrupted run (the whole point)"
fi

# 2. Even the minimal record carries an authorising decision, so it passes P3.
python3 "$AUD" trail --ledger "$L" | python3 "$DIR/../validation/audit-check.py" /dev/stdin 2>/dev/null | grep -q "RESULT: PASS" \
  && ok "the minimal record satisfies the trail properties (P3 authorising decision present)" \
  || bad "minimal record fails the property checker"

# 3. With a result file, the record is rich (verdict + payload from the agent).
L2="$TMP/b.jsonl"; RES="$TMP/res.json"
cat > "$RES" <<'JSON'
{"action":"tests.run","verdict":"pass","action_taken":"reported pass","reasoning":"5 passed","payload":{"passed":5,"failed":0}}
JSON
python3 "$OR" --role test-runner --recipe /dev/null --ledger "$L2" --result "$RES" --skip-goose --goose-exit 0 >/dev/null 2>&1
rich="$(python3 -c "import json;r=json.load(open('$L2'));print(r['outcome'].get('verdict'), r['payload'].get('passed'))")"
[ "$rich" = "pass 5" ] && ok "a result file makes the record rich (verdict + payload)" || bad "rich record wrong: $rich"

# 4. Exactly one record per run (no double-emit).
[ "$(grep -c . "$L2")" = "1" ] && ok "exactly one record per run" || bad "expected one record"

# 5. An untrusted-driven result is flagged (P4 visible, not hidden).
L3="$TMP/c.jsonl"; RES3="$TMP/res3.json"
echo '{"action":"spec.readiness","verdict":"not-ready","reasoning":"x","untrusted":true}' > "$RES3"
python3 "$OR" --role spec --recipe /dev/null --ledger "$L3" --result "$RES3" --skip-goose >/dev/null 2>&1
python3 -c "import json;import sys;sys.exit(0 if json.load(open('$L3')).get('untrusted_as_instruction') else 1)" \
  && ok "an untrusted-driven result records untrusted_as_instruction" || bad "untrusted flag not recorded"

# 6. The exit code mirrors the run, not the emit (CI must still see a failed run).
python3 "$OR" --role test-runner --recipe /dev/null --ledger "$TMP/d.jsonl" --skip-goose --goose-exit 2 >/dev/null 2>&1
[ "$?" = "2" ] && ok "exit code mirrors the goose run outcome" || bad "exit code not propagated"

# 7. An unknown role fails fast (a record that cannot be written must not pass silently).
python3 "$OR" --role not-a-role --recipe /dev/null --ledger "$TMP/e.jsonl" --skip-goose >/dev/null 2>&1
[ "$?" = "2" ] && ok "an unknown role is rejected up front" || bad "unknown role not rejected"

[ "$fail" = "0" ] && { echo "operate-run self-test: PASS"; exit 0; } || { echo "operate-run self-test: FAIL"; exit 1; }
