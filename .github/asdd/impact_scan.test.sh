#!/usr/bin/env bash
# Self-test for the deterministic framework-impact lens (impact_scan.py).
#
# Pins the properties the governance mechanism rests on: a change to normative text that is not declared
# normative is blocked; a normative change missing its impact analysis or target version is blocked; a
# behavioural surface gets a warn (not a false block); a plain docs change is classified non-normative;
# and the scan never corrupts review.json.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN="$DIR/impact_scan.py"
command -v python3 >/dev/null 2>&1 || { echo "impact self-test: SKIP (python3 not available)"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Run the scan over a (diff, body) pair and print the resulting review.json.
run() {  # run <name> <diff-file> <body-file>
  local wd="$TMP/$1"; mkdir -p "$wd"
  cp "$2" "$wd/changes.diff"; cp "$3" "$wd/body.md"
  cat > "$wd/review.json" <<'JSON'
{"schema":"asdd/review/v0.1","pr_number":1,"head_sha":"abc1234","mode":"dry-run","recommendation":"comment","summary":"seed","lenses":[]}
JSON
  python3 "$SCAN" --review "$wd/review.json" --workdir "$wd" 2>/dev/null
  cat "$wd/review.json"
}

check() {  # check <desc> <json> <jq-filter> <expected>
  local got; got="$(printf '%s' "$2" | jq -r "$3" 2>/dev/null)"
  if [ "$got" = "$4" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$got', want '$4')"; fail=1; fi
}

# --- fixtures -------------------------------------------------------------
diff_standard="$TMP/d_std.diff"
cat > "$diff_standard" <<'DIFF'
diff --git a/STANDARD.md b/STANDARD.md
--- a/STANDARD.md
+++ b/STANDARD.md
@@ -1,1 +1,2 @@
 # Standard
+A new MUST: every agent MUST disclose.
DIFF

diff_lens="$TMP/d_lens.diff"
cat > "$diff_lens" <<'DIFF'
diff --git a/.github/asdd/set-status.sh b/.github/asdd/set-status.sh
--- a/.github/asdd/set-status.sh
+++ b/.github/asdd/set-status.sh
@@ -1,1 +1,1 @@
-state="success"
+state="failure"
DIFF

diff_docs="$TMP/d_docs.diff"
cat > "$diff_docs" <<'DIFF'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1,1 +1,1 @@
-teh
+the
DIFF

body_nonnorm="$TMP/b_nonnorm.md"
printf '## Change scope\n- [x] Non-normative: docs only.\n' > "$body_nonnorm"

body_norm_full="$TMP/b_full.md"
cat > "$body_norm_full" <<'MD'
## Change scope
- [x] Normative: adds a MUST.

## Impact analysis
This tightens STANDARD section 1. CONFORMANCE.md item 1 must gain a check; the intake gate must enforce it.
Target version: v0.2.0 (major, a new MUST).
MD

body_norm_bare="$TMP/b_bare.md"
printf '## Change scope\n- [x] Normative: adds a MUST.\n' > "$body_norm_bare"

# --- assertions -----------------------------------------------------------
# 1. Normative text, declared non-normative -> block (the core "unseen change" gate).
out="$(run undeclared "$diff_standard" "$body_nonnorm")"
check "normative-by-path + non-normative decl -> request-changes" "$out" '.recommendation' 'request-changes'
check "block rule is normative-undeclared" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="normative-undeclared")]|length' '1'

# 2. Declared normative but no impact analysis / version -> block on both.
out="$(run bare "$diff_standard" "$body_norm_bare")"
check "normative, bare body -> request-changes" "$out" '.recommendation' 'request-changes'
check "missing impact analysis flagged" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="impact-analysis-missing")]|length' '1'
check "missing target version flagged" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="target-version-missing")]|length' '1'

# 3. Normative, fully declared -> no block, a single note, sign-off reminder.
out="$(run full "$diff_standard" "$body_norm_full")"
check "normative, complete -> not request-changes" "$out" '.recommendation' 'comment'
check "records normative-declared note" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="normative-declared")]|length' '1'

# 3b. Unfilled template (version only inside an HTML comment) must NOT pass the version check.
body_template="$TMP/b_template.md"
cat > "$body_template" <<'MD'
## Change scope
- [x] Normative: adds a MUST.

## Impact analysis
- **What else must adjust**: <!-- list the MUSTs, gates, docs -->
- **Target version**: <!-- e.g. v0.2.0 -->, level <!-- major | minor | patch -->
MD
out="$(run template "$diff_standard" "$body_template")"
check "unfilled template -> still blocked (no real version)" "$out" '.recommendation' 'request-changes'
check "unfilled template -> target-version-missing" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="target-version-missing")]|length' '1'

# 4. Behavioural surface (a gate script), declared non-normative -> warn, never block.
out="$(run behaviour "$diff_lens" "$body_nonnorm")"
check "behavioural surface -> not blocked" "$out" '.recommendation' 'comment'
check "behavioural surface -> warn" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="behaviour-surface-touched")]|length' '1'

# 5. Plain docs typo -> non-normative note, no block.
out="$(run docs "$diff_docs" "$body_nonnorm")"
check "docs typo -> not blocked" "$out" '.recommendation' 'comment'
check "docs typo -> non-normative note" "$out" \
  '[.lenses[]|select(.lens=="impact").findings[]|select(.rule=="non-normative")]|length' '1'

# 6. Fail-safe: a missing diff/body must not crash or corrupt review.json.
wd="$TMP/empty"; mkdir -p "$wd"
echo '{"schema":"asdd/review/v0.1","head_sha":"abc","lenses":[]}' > "$wd/review.json"
python3 "$SCAN" --review "$wd/review.json" --workdir "$wd" 2>/dev/null
jq -e . "$wd/review.json" >/dev/null 2>&1 && echo "ok: empty workdir leaves valid json" || { echo "FAIL: empty workdir corrupted json"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "impact self-test: PASS" || echo "impact self-test: FAIL"
exit "$fail"
