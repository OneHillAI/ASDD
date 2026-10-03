#!/usr/bin/env bash
# The operate runners (test.sh, docsync.sh) and the recipes they run must agree, or a "wired" agent never
# really runs and nothing says so. A stub `goose` on PATH records exactly what a runner hands it, so the
# contract is checked at the seam where it used to break:
#   1. every --params key a runner passes is a parameter its recipe declares (test.sh once passed
#      change_ref to a recipe that takes pr, so the run died on a missing parameter, hidden by `|| true`);
#   2. the result heading test.sh extracts is one the test-runner recipe tells the agent to print;
#   3. Goose gets the FULL request path (a bare https://host/v1 endpoint was requested as POST /v1, a 404);
#   4. a wired run that returns nothing says it did not complete (and records error), instead of telling a
#      connected deployment to wire its model; an unwired run still gets the wiring advice.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # .github/asdd/operate
ROOT="$(cd "$HERE/../../.." && pwd)"
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# A throwaway repo holding the real runners, recipes and resolver, and a stub goose that logs its call.
D="$T/repo"; mkdir -p "$D/cli" "$D/.github/asdd/operate" "$D/recipes" "$T/bin"
cp "$ROOT/cli/audit.py" "$ROOT/cli/operate-guard.py" "$ROOT/cli/resolve-model.sh" "$D/cli/"
cp "$ROOT/recipes/test-runner.yaml" "$ROOT/recipes/documentation.yaml" "$D/recipes/"
cp "$ROOT/cli/templates/operate/test.sh" "$ROOT/cli/templates/operate/docsync.sh" "$D/.github/asdd/operate/"
printf 'models:\n  test_runner: "m-test"\n  documentation: "m-doc"\n' > "$D/.asdd.yml"
cat > "$T/bin/goose" <<'STUB'
#!/usr/bin/env bash
{ echo "ARGS $*"; echo "BASE $OPENAI_BASE_PATH"; echo "HOST $OPENAI_HOST"; } > "$GOOSE_LOG"
printf '%s' "${STUB_REPLY:-}"
STUB
chmod +x "$T/bin/goose"

# run <runner> <endpoint-url, or "" for unwired> <stub reply>. Output lands in $T/out.md.
run() {
  rm -f "$T/out.md" "$T/goose.log" "$T/led.jsonl"
  if [ -n "$2" ]; then export ASDD_MODEL_URL="$2" ASDD_RUNTIME_TOKEN=k; else unset ASDD_MODEL_URL ASDD_RUNTIME_TOKEN; fi
  PATH="$T/bin:$PATH" GOOSE_LOG="$T/goose.log" STUB_REPLY="$3" ASDD_ACTIVITY_LOG="$T/led.jsonl" AUDIT_SINK_TOKEN= \
    bash "$D/.github/asdd/operate/$1" abc123 "$T/out.md" >/dev/null 2>&1
}

# 1. Parameters: what each runner passes is exactly what its recipe declares.
for pair in "test.sh:test-runner.yaml" "docsync.sh:documentation.yaml"; do
  runner="${pair%%:*}"; recipe="${pair##*:}"
  run "$runner" "https://h.example/v1" ""
  passed="$(grep -o -- '--params [A-Za-z_]*' "$T/goose.log" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  declared="$(sed -n 's/^  - key: *//p' "$ROOT/recipes/$recipe" | tr -d '"' | sort -u | tr '\n' ' ')"
  if [ -n "$passed" ] && [ "$passed" = "$declared" ]; then
    ok "$runner passes exactly the parameters $recipe declares ($declared)"
  else
    bad "$runner passes [$passed] but $recipe declares [$declared]"
  fi
done

# 2. Heading: the section test.sh extracts is one the recipe asks the agent to print.
heading="## Test result"
if grep -qF "$heading" "$ROOT/recipes/test-runner.yaml" && grep -qF "$heading" "$ROOT/cli/templates/operate/test.sh"; then
  ok "test.sh extracts '$heading', which test-runner.yaml tells the agent to print"
else
  bad "test.sh extracts '$heading' but test-runner.yaml never asks for it, so every run falls to the failure path"
fi
run test.sh "https://h.example/v1" $'chatter\n## Test result\nPASS 12 passed 0 failed'
if grep -q 'result for' "$T/out.md" && grep -q 'PASS 12 passed' "$T/out.md" && ! grep -q 'chatter' "$T/out.md"; then
  ok "test.sh posts the agent's result section and drops the chatter before it"
else
  bad "test.sh did not extract the result section: $(tr '\n' '|' < "$T/out.md")"
fi

# 3. Base path: Goose is handed the full request path whichever form the endpoint was written in.
for case_ in "https://h.example/v1|v1/chat/completions" "https://h.example/v1/|v1/chat/completions" \
             "https://h.example/v1/chat/completions|v1/chat/completions" "https://h.example|v1/chat/completions" \
             "https://h.example/api/v2|api/v2/chat/completions" "https://h.example/v1?x=1|v1/chat/completions"; do
  url="${case_%%|*}"; want="${case_##*|}"
  for runner in test.sh docsync.sh; do
    run "$runner" "$url" ""
    got="$(sed -n 's/^BASE //p' "$T/goose.log")"; host="$(sed -n 's/^HOST //p' "$T/goose.log")"
    if [ "$got" = "$want" ] && [ "$host" = "https://h.example" ]; then
      ok "$runner: $url -> $host/$got"
    else
      bad "$runner: $url -> host '$host' path '$got' (want path $want)"
    fi
  done
done

# 4. Honest wording: a wired run with no usable result is a failure, not a request to wire the model.
for runner in test.sh docsync.sh; do
  run "$runner" "https://h.example/v1" ""
  if grep -qi 'did not complete' "$T/out.md" && ! grep -qi 'wire the model' "$T/out.md" \
     && grep -q '"verdict":"error"' "$T/led.jsonl"; then
    ok "$runner: a wired run that returns nothing says it did not complete, records error, gives no wiring advice"
  else
    bad "$runner: wired-but-empty run misreported: $(head -3 "$T/out.md" | tr '\n' '|') $(grep -o '"verdict":"[a-z-]*"' "$T/led.jsonl")"
  fi
  run "$runner" "" ""
  if grep -qi 'dry run' "$T/out.md" && grep -qi 'wire the model' "$T/out.md" && grep -q '"verdict":"dry-run"' "$T/led.jsonl"; then
    ok "$runner: an unwired run is still a dry run with the wiring advice"
  else
    bad "$runner: unwired run lost its dry-run report"
  fi
done

echo
[ "$fail" = 0 ] && echo "runner-contract self-test: PASS" || echo "runner-contract self-test: FAIL"
exit "$fail"
