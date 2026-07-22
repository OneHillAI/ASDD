#!/usr/bin/env sh
# Self-test for claim-check.py against the CL rules. Exit 0 iff all pass.
DIR=$(dirname "$0"); D="$DIR/testdata/claims"; NOW="2026-07-13T10:00:00"
run() { python3 "$DIR/claim-check.py" "$1" --now "$NOW" "$@" >/dev/null 2>&1; echo $?; }
fail=0
r=$(python3 "$DIR/claim-check.py" "$D/empty.json"         --now "$NOW" --item 42 --identity bob   >/dev/null 2>&1; echo $?)
[ "$r" = "0" ] || { echo "FAIL: fresh claim should GRANT"; fail=1; }
r=$(python3 "$DIR/claim-check.py" "$D/alice-holds-42.json" --now "$NOW" --item 42 --identity bob   >/dev/null 2>&1; echo $?)
[ "$r" = "1" ] || { echo "FAIL: double-claim should REFUSE"; fail=1; }
r=$(python3 "$DIR/claim-check.py" "$D/empty.json"         --now "$NOW" --item 42 --identity bob --ready false >/dev/null 2>&1; echo $?)
[ "$r" = "1" ] || { echo "FAIL: not-ready item should REFUSE"; fail=1; }
r=$(python3 "$DIR/claim-check.py" "$D/alice-stale-42.json" --now "$NOW" --item 42 --identity bob   >/dev/null 2>&1; echo $?)
[ "$r" = "0" ] || { echo "FAIL: stale claim should auto-release then GRANT"; fail=1; }
r=$(python3 "$DIR/claim-check.py" "$D/alice-at-cap.json"  --now "$NOW" --item 42 --identity alice --max-per-identity 1 >/dev/null 2>&1; echo $?)
[ "$r" = "1" ] || { echo "FAIL: at-cap identity should REFUSE"; fail=1; }
r=$(python3 "$DIR/claim-check.py" "$D/alice-holds-42.json" --now "$NOW" --item 42 --identity alice >/dev/null 2>&1; echo $?)
[ "$r" = "0" ] || { echo "FAIL: idempotent re-claim should GRANT"; fail=1; }
[ "$fail" = "0" ] && { echo "claim-check self-test: PASS"; exit 0; } || { echo "claim-check self-test: FAIL"; exit 1; }
