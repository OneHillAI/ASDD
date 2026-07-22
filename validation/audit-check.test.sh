#!/usr/bin/env sh
# Self-test for audit-check.py. clean trail -> PASS (0); violating trail -> FAIL (1).
DIR=$(dirname "$0"); AC="$DIR/audit-check.py"; C="$DIR/cases/audit"; fail=0
r=$(python3 "$AC" "$C/clean.json"     --protected '**/crypto/**' --max-actions 5 >/dev/null 2>&1; echo $?)
[ "$r" = "0" ] || { echo "FAIL: clean trail should PASS"; fail=1; }
r=$(python3 "$AC" "$C/violating.json" --protected '**/crypto/**' --max-actions 5 >/dev/null 2>&1; echo $?)
[ "$r" = "1" ] || { echo "FAIL: violating trail should FAIL"; fail=1; }
[ "$fail" = "0" ] && { echo "audit-check self-test: PASS"; exit 0; } || { echo "audit-check self-test: FAIL"; exit 1; }
