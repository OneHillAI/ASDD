#!/usr/bin/env bash
# Self-test for extract-json.py: the review runtime must recover the model's JSON object out of the
# messy shapes a real (reasoning) model returns, and must still reject genuine non-JSON so the gate
# fails closed. Deterministic, network-free.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
EX="$HERE/extract-json.py"
fail=0
J='{"schema":"asdd/review/v0.1","mode":"live","recommendation":"comment","summary":"ok","lenses":[{"lens":"code","verdict":"ok","findings":[]}]}'

want_ok() { # name input
  out="$(printf '%s' "$2" | python3 "$EX")"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c 'import sys,json; o=json.load(sys.stdin); raise SystemExit(0 if o.get("lenses") is not None else 1)' 2>/dev/null; then
    echo "ok   $1"; else echo "FAIL $1 (rc=$rc) got: ${out:0:80}"; fail=1; fi
}
want_reject() { # name input
  printf '%s' "$2" | python3 "$EX" >/dev/null 2>&1 && { echo "FAIL $1 (should reject)"; fail=1; } || echo "ok   $1 (rejected)"
}

want_ok     "bare object"                 "$J"
want_ok     "fenced object"               "\`\`\`json
$J
\`\`\`"
want_ok     "reasoning prose then object" "Let me review. The diff edits setup-goose.py and adds connect-check. Looks safe.
$J"
want_ok     "prose with braces, then object, then trailing text" \
            "The snippet {x: 1} is unrelated. $J
That is my review, thanks!"
want_reject "truncated object"            "${J:0:60}"
want_reject "prose, no object"            "Looks fine to me, no concerns."

echo
[ "$fail" = 0 ] && echo "extract-json self-test: PASS" || echo "extract-json self-test: FAIL"
exit "$fail"
