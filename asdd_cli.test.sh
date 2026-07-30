#!/usr/bin/env sh
# Self-test for the asdd dispatcher: it routes to the right tool and handles errors.
DIR=$(dirname "$0"); A="python3 $DIR/asdd_cli.py"; fail=0
$A --help >/dev/null 2>&1 || { echo "FAIL: help"; fail=1; }
$A merge-eligibility crypto/x.py --protected '**/crypto/**' --posture earned-automerge >/dev/null 2>&1 || { echo "FAIL: merge-eligibility routes"; fail=1; }
$A spec-check "$DIR/cli/testdata/spec-ready.json" >/dev/null 2>&1 || { echo "FAIL: spec-check routes"; fail=1; }
$A bogus >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL: unknown command should exit 2"; fail=1; }
[ "$fail" = 0 ] && { echo "asdd-cli self-test: PASS"; exit 0; } || { echo "asdd-cli self-test: FAIL"; exit 1; }
