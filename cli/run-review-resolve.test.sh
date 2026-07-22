#!/usr/bin/env sh
# Test: the review lenses resolve through the roster, like every other role.
#
# Before this, run-review.sh reached the model through the single ASDD_MODEL / ASDD_RUNTIME_TOKEN,
# so `models.reviewer` was declarative for the lenses and a per-role provider could not reach them.
# These assert the two properties that matter:
#   1. the reviewer's model/endpoint/key come from the roster + the per-role env pair;
#   2. the key NEVER reaches stdout (the resolver yields the variable NAME; the caller dereferences).
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail() { echo "FAIL: $1" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# A fake, obviously-not-real value. The scanner's placeholder rule recognises "fake", so this
# fixture does not raise a spurious hardcoded-credential finding on its own test.
SECRET="sk-fake-per-role-token-should-never-print"

# A repo with the govern layer, a roster naming the reviewer's model, and a fake adapter that
# records exactly what the model command was handed.
mkdir -p "$TMP/.github/asdd/runtime" "$TMP/cli" "$TMP/work"
cp "$ROOT/.github/asdd/run-review.sh" "$TMP/.github/asdd/run-review.sh"
cp "$ROOT/cli/resolve-model.sh"       "$TMP/cli/resolve-model.sh"
chmod +x "$TMP/cli/resolve-model.sh"
cat > "$TMP/.asdd.yml" <<'YAML'
standard_version: "0.1"
runtime: generic
models:
  developer: "dev-model"
  reviewer: "roster-reviewer-model"
YAML
# The fake adapter stands in for runtime/generic.sh: it reports the resolved env it received.
cat > "$TMP/.github/asdd/runtime/generic.sh" <<'SH'
#!/usr/bin/env bash
{
  echo "MODEL=${ASDD_MODEL:-}"
  echo "URL=${ASDD_MODEL_URL:-}"
  echo "TOKEN=${ASDD_RUNTIME_TOKEN:-}"
} > "$ASDD_ROOT/adapter-saw.txt"
printf '{"schema":"asdd/review/v0.1","pr_number":1,"head_sha":"abc","mode":"live","recommendation":"comment","summary":"x","lenses":[]}' > "$ASDD_OUT"
SH
chmod +x "$TMP/.github/asdd/runtime/generic.sh"
printf 'pr_number=1\nbase_sha=aaa\nhead_sha=bbb\n' > "$TMP/work/meta.env"
: > "$TMP/work/changes.diff"

# Run with a PER-ROLE endpoint and key set, plus different shared ones, so precedence is visible.
out="$(cd "$TMP" && env \
  ASDD_MODEL="shared-model" \
  ASDD_MODEL_URL="https://shared.example/v1/chat/completions" \
  ASDD_RUNTIME_TOKEN="sk-fake-shared-token" \
  ASDD_MODEL_URL__REVIEWER="https://reviewer.example/v1/chat/completions" \
  ASDD_RUNTIME_TOKEN__REVIEWER="$SECRET" \
  bash .github/asdd/run-review.sh work review.json 2>&1)" || fail "run-review.sh exited non-zero: $out"

saw="$TMP/adapter-saw.txt"
[ -f "$saw" ] || fail "the adapter never ran (so nothing resolved)"

# 1. The roster decides the model: models.reviewer beats the shared $ASDD_MODEL.
grep -q '^MODEL=roster-reviewer-model$' "$saw" || fail "reviewer model did not come from the roster: $(grep '^MODEL=' "$saw")"

# 2. The per-role endpoint wins over the shared one.
grep -q '^URL=https://reviewer.example/v1/chat/completions$' "$saw" || fail "per-role endpoint did not win: $(grep '^URL=' "$saw")"

# 3. The per-role key reaches the adapter (dereferenced from the variable NAME).
grep -q "^TOKEN=$SECRET$" "$saw" || fail "per-role key did not reach the adapter"

# 4. The key NEVER appears in what run-review printed.
case "$out" in *"$SECRET"*) fail "the runtime key leaked into stdout/stderr" ;; esac
case "$out" in *"sk-fake-shared-token"*) fail "the shared key leaked into stdout/stderr" ;; esac

# 5. Fallback: with no per-role pair, the shared env stands (a single-provider deployment is unaffected).
rm -f "$saw"
out2="$(cd "$TMP" && env \
  ASDD_MODEL="shared-model" \
  ASDD_MODEL_URL="https://shared.example/v1/chat/completions" \
  ASDD_RUNTIME_TOKEN="sk-fake-shared-token" \
  bash .github/asdd/run-review.sh work review.json 2>&1)" || fail "fallback run failed: $out2"
grep -q '^URL=https://shared.example/v1/chat/completions$' "$saw" || fail "shared endpoint should stand with no per-role pair"
grep -q '^TOKEN=sk-fake-shared-token$' "$saw" || fail "shared key should stand with no per-role pair"
# the roster still decides the model even in the shared case
grep -q '^MODEL=roster-reviewer-model$' "$saw" || fail "roster model should still win in the shared case"

# 6. No resolver present (a stale install): the shared env still works, nothing breaks.
rm -f "$TMP/cli/resolve-model.sh" "$saw"
out3="$(cd "$TMP" && env \
  ASDD_MODEL="shared-model" \
  ASDD_MODEL_URL="https://shared.example/v1/chat/completions" \
  ASDD_RUNTIME_TOKEN="sk-fake-shared-token" \
  bash .github/asdd/run-review.sh work review.json 2>&1)" || fail "run without the resolver failed: $out3"
grep -q '^MODEL=shared-model$' "$saw" || fail "without the resolver the shared model should be used"

echo "run-review-resolve.test.sh: PASS"
