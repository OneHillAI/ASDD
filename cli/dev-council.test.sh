#!/usr/bin/env bash
# Self-test for the developer council orchestrator (cli/dev-council.py). Deterministic: it exercises the
# sizing, heterogeneity, dry-run, recording and knowledge-derivation paths without calling a model.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DC="$ROOT/cli/dev-council.py"
AUDIT="$ROOT/cli/audit.py"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

T="$(mktemp -d)"
mkdir -p "$T/.asdd-work"
cat > "$T/.asdd.yml" <<'YML'
models:
  test_author: "moonshotai:kimi@k2.6"
  test_runner: "moonshotai:kimi@k2.6"
dev_council:
  models:
    - "zai:glm@5.2"
    - "openai:gpt@4o"
    - "deepseek:deepseek@v3.2"
YML

# 1. Dry run: 3 models -> 2 proposers + 1 lead, and it exits 0.
out="$(python3 "$DC" --root "$T" --change c --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "2 proposer(s) + 1 lead" \
  && ok "dry run reports 2 proposers + 1 lead" || bad "dry run shape (rc=$rc): $out"

# 1b. FLOW-STYLE models list ([a, b, c]): the tiny YAML reader hands this back as one string; it must
#     parse as 3 real models with a real lead, never iterate the string character by character.
Tf="$(mktemp -d)"; mkdir -p "$Tf/.asdd-work"
cat > "$Tf/.asdd.yml" <<'YML'
models:
  test_author: "kimi:t"
  test_runner: "kimi:t"
dev_council:
  models: [zai:glm@5.2, openai:gpt@4o, deepseek:deepseek@v3]
YML
out="$(python3 "$DC" --root "$Tf" --change c --dry-run 2>&1)"
printf '%s' "$out" | grep -q "3 model(s) = 2 proposer(s) + 1 lead (deepseek:deepseek@v3)" \
  && ok "flow-style [a, b, c] parses as 3 models with the right lead" || bad "flow-style list mis-parsed: $out"
rm -rf "$Tf"

# 2. A dry run still emits exactly one audit record (nothing is silently lost).
ASDD_ACTIVITY_LOG="$T/rec.jsonl" python3 "$DC" --root "$T" --change c --dry-run >/dev/null 2>&1
n="$(grep -c . "$T/rec.jsonl" 2>/dev/null || echo 0)"
[ "$n" = 1 ] && ok "dry run emits one record" || bad "expected 1 record, got $n"

# 3. Sizing: 1 model is not a council (non-zero); 6 is capped to 5.
python3 "$DC" --root "$T" --models "a:x" --change c --dry-run >/dev/null 2>&1
[ $? -ne 0 ] && ok "1 model rejected" || bad "1 model should be rejected"
python3 "$DC" --root "$T" --models "a:1,b:2,c:3,d:4,e:5,f:6" --change c --dry-run 2>&1 | grep -q "exceeds the cap of 5" \
  && ok "6 models capped to 5" || bad "6 models should cap to 5"

# 4. Heterogeneity: a council model that also serves a test role FAILS.
python3 "$DC" --root "$T" --models "zai:glm@5.2,openai:gpt@4o,moonshotai:kimi@k2.6" --change c --dry-run >/dev/null 2>&1
[ $? -ne 0 ] && ok "developer == test role is rejected" || bad "council==test role should fail"

# 5. Same-family is a warning, not a failure (still exits 0).
python3 "$DC" --root "$T" --models "zai:glm@5.2,zai:glm@4.6,openai:gpt@4o" --change c --dry-run >/dev/null 2>&1
[ $? -eq 0 ] && ok "same-family warns but proceeds" || bad "same-family should warn, not fail"

# 5c. A council model that also serves as the reviewer warns (independence), but does not fail: the
#     reviewer must independently review the council's output.
Tr="$(mktemp -d)"; printf 'models:\n  reviewer: "rev:x"\ndev_council:\n  models: [rev:x, a:y, b:z]\n' > "$Tr/.asdd.yml"
out="$(python3 "$DC" --root "$Tr" --change c --dry-run 2>&1)"; rc=$?
printf '%s' "$out" | grep -q "also serves as the reviewer" && [ "$rc" -eq 0 ] \
  && ok "reviewer-in-council warns but proceeds" || bad "reviewer-in-council should warn, not fail: $out"
rm -rf "$Tr"

# 6. Knowledge derivation: a council-synthesis record becomes an OKGF exemplar, a council-rejected a
#    rejected page (proves the audit.py knowledge mapping covers the council).
K="$T/k.jsonl"
python3 "$AUDIT" append --ledger "$K" --role developer --lens council-synthesis --action dev-council.synthesis \
  --verdict pass --reasoning "derive the id from the session, not the request body" >/dev/null 2>&1
python3 "$AUDIT" append --ledger "$K" --role developer --lens council-rejected --action dev-council.rejected \
  --verdict changes-requested --reasoning "trusting a client-supplied id fails isolation" >/dev/null 2>&1
python3 "$AUDIT" knowledge --ledger "$K" --out "$T/kb" >/dev/null 2>&1
grep -rql 'type: "exemplar"' "$T/kb" && grep -rql 'type: "rejected"' "$T/kb" \
  && ok "council records derive exemplar + rejected OKGF pages" || bad "council knowledge pages not derived"

# 7. HONEST RESULT. A real run against a stub model server (no network): a failed lead, an unverified
#    result, a cut-off draft and a silent member must each be NAMED in the header, transcript and ledger,
#    never passed off as a clean, verified council synthesis. The stub answers by a word in the model name:
#    "cut" -> text stopped at the token cap; "empty" -> no text, stopped at the cap (a reasoning model that
#    spent its whole budget thinking); "silent" -> no text, a plain stop; anything else -> a healthy reply.
cat > "$T/stub.py" <<'PY'
import http.server, json, sys
LOG = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length") or 0)) or b"{}")
        m = body.get("model", "")
        with open(LOG, "a") as fh:
            fh.write(json.dumps({"model": m, "effort": body.get("reasoning_effort")}) + "\n")
        if "empty" in m:   text, fr = "", "length"
        elif "silent" in m: text, fr = "", "stop"
        elif "cut" in m:   text, fr = "PARTIAL DRAFT cut mid-th", "length"
        else:              text, fr = "A COMPLETE DRAFT\nRATIONALE: simplest thing that meets the criteria", "stop"
        out = json.dumps({"choices": [{"message": {"content": text}, "finish_reason": fr}]}).encode()
        self.send_response(200); self.send_header("content-type", "application/json"); self.end_headers()
        self.wfile.write(out)
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$T/stub.py" "$T/port" "$T/req.log" & STUB=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/port" ] && break; sleep 0.5; done
URL="http://127.0.0.1:$(cat "$T/port")/v1"

# council <models> [dev-council args]: every member wired by its own __COUNCIL_<i> pair, and NO shared pair,
# so the test roles stay unwired unless a --test-cmd is given (that is the "not verified" case).
council() {
  rm -f "$T/o.md" "$T/t.json" "$T/l.jsonl" "$T/req.log"
  local models="$1"; shift
  env -u ASDD_MODEL_URL -u ASDD_RUNTIME_TOKEN ASDD_ACTIVITY_LOG="$T/l.jsonl" \
    ASDD_MODEL_URL__COUNCIL_1="$URL" ASDD_RUNTIME_TOKEN__COUNCIL_1=k \
    ASDD_MODEL_URL__COUNCIL_2="$URL" ASDD_RUNTIME_TOKEN__COUNCIL_2=k \
    ASDD_MODEL_URL__COUNCIL_3="$URL" ASDD_RUNTIME_TOKEN__COUNCIL_3=k \
    python3 "$DC" --root "$T" --change c --models "$models" --out "$T/o.md" --transcript "$T/t.json" "$@" >/dev/null 2>&1
}
verdict() { grep '"action":"dev-council.run"' "$T/l.jsonl" | grep -o '"verdict":"[a-z-]*"' | head -1; }
tjson() { python3 -c "import json,sys;d=json.load(open('$T/t.json'));print(eval(sys.argv[1]))" "$1" 2>/dev/null; }

# 7a. A lead that returns nothing: named in the header and transcript, ledger says error, no exemplar,
#     and the empty length-stopped call is not retried (it would spend the same budget again).
council "ok:a,ok:b,leadempty:x" --test-cmd true
if grep -q 'LEAD FAILED' "$T/o.md" && [ "$(tjson "d['lead_failed']")" = True ] \
   && [ "$(verdict)" = '"verdict":"error"' ] && ! grep -q 'dev-council.synthesis' "$T/l.jsonl"; then
  ok "a failed lead is named (header, transcript, ledger error) and earns no exemplar"
else bad "failed lead passed off as a synthesis: $(head -3 "$T/o.md" | tr '\n' '|') $(verdict)"; fi
[ "$(grep -c '"model": "leadempty:x"' "$T/req.log")" -le 2 ] \
  && ok "an empty length-stopped lead call is not retried" || bad "empty length-stopped call was retried: $(grep -c leadempty "$T/req.log") calls"

# 7b. A healthy run is not mislabelled.
council "ok:a,ok:b,ok:lead" --test-cmd true
if grep -q 'verify passed' "$T/o.md" && ! grep -qE 'LEAD FAILED|NOT VERIFIED|NO ANSWER|Cut off' "$T/o.md" \
   && [ "$(verdict)" = '"verdict":"pass"' ] && grep -q 'dev-council.synthesis' "$T/l.jsonl"; then
  ok "a healthy verified run reads as one: verify passed, ledger pass, exemplar recorded"
else bad "healthy run mislabelled: $(head -3 "$T/o.md" | tr '\n' '|') $(verdict)"; fi

# 7c. Nothing verified the result: header says NOT VERIFIED, ledger says unverified, no exemplar.
council "ok:a,ok:b,ok:lead"
if grep -q 'NOT VERIFIED' "$T/o.md" && ! grep -q 'verify passed' "$T/o.md" \
   && [ "$(verdict)" = '"verdict":"unverified"' ] && ! grep -q 'dev-council.synthesis' "$T/l.jsonl"; then
  ok "no test runner wired -> NOT VERIFIED, ledger unverified, no exemplar"
else bad "unverified result passed off as verified: $(head -3 "$T/o.md" | tr '\n' '|') $(verdict)"; fi

# 7d. A real failed verification still reads as failed.
council "ok:a,ok:b,ok:lead" --test-cmd false
grep -q 'verify FAILED' "$T/o.md" && [ "$(verdict)" = '"verdict":"changes-requested"' ] \
  && ok "a failed verification still reads FAILED / changes-requested" || bad "failed verify misreported: $(verdict)"

# 7e. A proposal cut off at the token cap is flagged; so is a cut-off final text, which earns no exemplar.
council "cut:a,ok:b,ok:lead" --test-cmd true
grep -q 'Cut off at the token cap' "$T/o.md" && [ "$(tjson "d['proposals'][0]['truncated']")" = True ] \
  && ok "a proposal cut off at the token cap is flagged" || bad "cut-off proposal not flagged: $(head -4 "$T/o.md" | tr '\n' '|')"
council "ok:a,ok:b,leadcut:x" --test-cmd true
grep -q 'final text below was cut off' "$T/o.md" && ! grep -q 'dev-council.synthesis' "$T/l.jsonl" \
  && ok "a cut-off synthesis is flagged and is not an exemplar" || bad "cut-off synthesis passed off as complete"

# 7f. A member that gives no answer is named, not silently counted as present.
council "silent:b,ok:a,ok:lead" --test-cmd true
grep -q 'NO ANSWER FROM silent:b' "$T/o.md" \
  && ok "a member that gave no answer is named in the header" || bad "silent member not named: $(head -3 "$T/o.md" | tr '\n' '|')"

# 7g. dev_council.reasoning_effort reaches every council call when set, and is not sent by default.
Te="$(mktemp -d)"; printf 'models:\n  test_author: "kimi:t"\n  test_runner: "kimi:t"\ndev_council:\n  reasoning_effort: low\n  models: [ok:a, ok:b, ok:lead]\n' > "$Te/.asdd.yml"
rm -f "$T/req.log"
env -u ASDD_MODEL_URL -u ASDD_RUNTIME_TOKEN ASDD_ACTIVITY_LOG="$Te/l.jsonl" \
  ASDD_MODEL_URL__COUNCIL_1="$URL" ASDD_RUNTIME_TOKEN__COUNCIL_1=k ASDD_MODEL_URL__COUNCIL_2="$URL" \
  ASDD_RUNTIME_TOKEN__COUNCIL_2=k ASDD_MODEL_URL__COUNCIL_3="$URL" ASDD_RUNTIME_TOKEN__COUNCIL_3=k \
  python3 "$DC" --root "$Te" --change c --test-cmd true >/dev/null 2>&1
n_all="$(grep -c . "$T/req.log")"; n_low="$(grep -c '"effort": "low"' "$T/req.log")"
[ "$n_all" -ge 3 ] && [ "$n_all" = "$n_low" ] \
  && ok "reasoning_effort low is sent on every council call ($n_low of $n_all)" || bad "reasoning_effort not on every call ($n_low of $n_all)"
council "ok:a,ok:b,ok:lead" --test-cmd true
[ "$(grep -c . "$T/req.log")" -ge 3 ] && ! grep -q '"effort": "' "$T/req.log" \
  && ok "no reasoning_effort is sent unless configured" || bad "reasoning_effort sent by default"
rm -rf "$Te"
kill "$STUB" 2>/dev/null; wait "$STUB" 2>/dev/null

rm -rf "$T"
echo
[ "$fail" = 0 ] && echo "dev-council self-test: PASS" || echo "dev-council self-test: FAIL"
exit "$fail"
