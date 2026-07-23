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
    - "anthropic:claude@opus-4.8"
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
  models: [zai:glm@5.2, openai:gpt@4o, anthropic:claude@opus]
YML
out="$(python3 "$DC" --root "$Tf" --change c --dry-run 2>&1)"
printf '%s' "$out" | grep -q "3 model(s) = 2 proposer(s) + 1 lead (anthropic:claude@opus)" \
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

rm -rf "$T"
echo
[ "$fail" = 0 ] && echo "dev-council self-test: PASS" || echo "dev-council self-test: FAIL"
exit "$fail"
