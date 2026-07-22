#!/usr/bin/env sh
# Self-test for spec-check.py: the definition-of-ready gate + the independent
# ready-claim check. Exit 0 iff all behave correctly.
DIR=$(dirname "$0")
run() { python3 "$DIR/spec-check.py" "$DIR/testdata/$1" >/dev/null 2>&1; echo $?; }
fail=0
[ "$(run spec-ready.json)" = "0" ]     || { echo "FAIL: ready spec should pass (exit 0)"; fail=1; }
[ "$(run spec-vague.json)" = "1" ]     || { echo "FAIL: vague spec should be not-ready (exit 1)"; fail=1; }
[ "$(run spec-injection.json)" = "2" ] || { echo "FAIL: forced ready=true should be blocked (exit 2)"; fail=1; }
[ "$fail" = "0" ] && { echo "spec-check self-test: PASS"; exit 0; } || { echo "spec-check self-test: FAIL"; exit 1; }
