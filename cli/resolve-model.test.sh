#!/usr/bin/env sh
# Test for resolve-model.sh: a role's roster model wins, $ASDD_MODEL is the fallback,
# and an unset role with no fallback fails loudly rather than running on a surprise model.
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/.asdd.yml"; cp "$ROOT/.asdd.example.yml" "$CFG"
python3 "$DIR/setup-goose.py" "$CFG" --set developer=dev-model --set test_author=author-model \
  --set test_runner=runner-model --set documentation=doc-model >/dev/null 2>&1

# 1. The roster wins: each role resolves to its OWN model, not a shared one.
[ "$(bash "$DIR/resolve-model.sh" documentation "$CFG")" = "doc-model" ]   || { echo "FAIL: documentation did not resolve from the roster"; fail=1; }
[ "$(bash "$DIR/resolve-model.sh" test_runner "$CFG")" = "runner-model" ]  || { echo "FAIL: test_runner did not resolve from the roster"; fail=1; }
[ "$(bash "$DIR/resolve-model.sh" test_author "$CFG")" = "author-model" ]  || { echo "FAIL: test_author did not resolve from the roster"; fail=1; }

# 2. The roster beats ASDD_MODEL (the fallback must not override a configured role).
[ "$(ASDD_MODEL=fallback bash "$DIR/resolve-model.sh" documentation "$CFG")" = "doc-model" ] \
  || { echo "FAIL: ASDD_MODEL overrode a configured role"; fail=1; }

# 3. An unset role falls back to ASDD_MODEL, so a single-model deployment keeps working.
[ "$(ASDD_MODEL=fallback bash "$DIR/resolve-model.sh" interaction "$CFG")" = "fallback" ] \
  || { echo "FAIL: unset role did not fall back to ASDD_MODEL"; fail=1; }

# 4. Unset role and no fallback = fail loudly (never guess a model).
if ASDD_MODEL= bash "$DIR/resolve-model.sh" interaction "$CFG" >/dev/null 2>&1; then
  echo "FAIL: resolved a model that was never configured"; fail=1
fi

# 5. A missing config with a fallback still resolves (the CI-only deployment case).
[ "$(ASDD_MODEL=fallback bash "$DIR/resolve-model.sh" documentation "$TMP/none.yml")" = "fallback" ] \
  || { echo "FAIL: missing config did not fall back"; fail=1; }

# --- per-role endpoint and key -------------------------------------------------------

# 6. A per-role endpoint wins over the shared one; other roles keep the shared one.
got=$(ASDD_MODEL_URL=https://shared/v1/chat/completions \
      ASDD_MODEL_URL__DOCUMENTATION=https://runware/v1/chat/completions \
      bash "$DIR/resolve-model.sh" documentation "$CFG" --url)
[ "$got" = "https://runware/v1/chat/completions" ] || { echo "FAIL: per-role endpoint did not win (got '$got')"; fail=1; }
got=$(ASDD_MODEL_URL=https://shared/v1/chat/completions \
      ASDD_MODEL_URL__DOCUMENTATION=https://runware/v1/chat/completions \
      bash "$DIR/resolve-model.sh" test_runner "$CFG" --url)
[ "$got" = "https://shared/v1/chat/completions" ] || { echo "FAIL: another role did not keep the shared endpoint (got '$got')"; fail=1; }

# 7. No endpoint at all fails rather than guessing.
if ASDD_MODEL_URL= bash "$DIR/resolve-model.sh" documentation "$CFG" --url >/dev/null 2>&1; then
  echo "FAIL: resolved an endpoint that was never set"; fail=1
fi

# 8. --token-var names the per-role variable when it is set, else the shared one.
got=$(ASDD_RUNTIME_TOKEN=shared-key ASDD_RUNTIME_TOKEN__DOCUMENTATION=role-key \
      bash "$DIR/resolve-model.sh" documentation "$CFG" --token-var)
[ "$got" = "ASDD_RUNTIME_TOKEN__DOCUMENTATION" ] || { echo "FAIL: token-var did not name the per-role variable (got '$got')"; fail=1; }
got=$(ASDD_RUNTIME_TOKEN=shared-key bash "$DIR/resolve-model.sh" documentation "$CFG" --token-var)
[ "$got" = "ASDD_RUNTIME_TOKEN" ] || { echo "FAIL: token-var did not fall back to the shared variable (got '$got')"; fail=1; }

# 9. SECURITY: the resolver must never print a key value, only the variable's name.
out=$(ASDD_RUNTIME_TOKEN=shared-SECRET ASDD_RUNTIME_TOKEN__DOCUMENTATION=role-SECRET \
      bash "$DIR/resolve-model.sh" documentation "$CFG" --token-var 2>&1)
case "$out" in *SECRET*) echo "FAIL: the resolver echoed a key value"; fail=1 ;; esac

[ "$fail" = "0" ] && { echo "resolve-model self-test: PASS"; exit 0; } || { echo "resolve-model self-test: FAIL"; exit 1; }
