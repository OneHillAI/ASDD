#!/usr/bin/env bash
# Self-test for the conventions gate (cli/conventions-check.py).
#
# The load-bearing property is THE RATCHET: a banned character already present in a context line must
# pass, while the same character on an ADDED line must fail. Without that, no mature repository could
# ever adopt, because its existing tree would fail on day one. The other cases pin the contract itself:
# declared-only checking, map-never-duplicate (an assembled changelog is not edited when the project
# ships fragments), exempt lanes, and a malformed block reporting as a SETUP error (exit 2) rather than
# as a change violation (exit 1) - an agent must not read a misconfiguration as "your change is fine".
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CHK="$DIR/conventions-check.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

mkdir -p "$TMP/docs/specs" "$TMP/changelog.d"; : > "$TMP/docs/SYSTEM_IMPACT_LOG.md"
CFG="$TMP/.asdd.yml"
cat > "$CFG" <<'YML'
conventions:
  spec_dir: "docs/specs"
  exempt_lanes: [chore]
  changelog:
    mode: fragment
    fragment_glob: "changelog.d/*.md"
    categories: [added, fixed]
    assembled_file: "CHANGELOG.md"
  impact_log: "docs/SYSTEM_IMPACT_LOG.md"
  style:
    banned_chars: ["–", "—"]
YML

echo "conventions gate self-test"

# 1. The block parses and its declared paths exist.
out="$(python3 "$CHK" --config "$CFG" --validate 2>&1)"; rc=$?
[ "$rc" = "0" ] && grep -q "VALID" <<<"$out" && ok "a valid block validates" || bad "valid block (exit $rc)"

# 2. The contract renders the declared fields for an agent prompt.
out="$(python3 "$CHK" --config "$CFG" --print-contract 2>&1)"
grep -q "changelog.d/\*.md" <<<"$out" && grep -qi "do not edit CHANGELOG.md" <<<"$out" \
  && ok "contract names the fragment form and forbids editing the assembled file" \
  || bad "contract rendering"

# 3. A conforming change passes.
out="$(python3 "$CHK" --config "$CFG" --lane feature \
        --changed src/a.py docs/specs/a.md changelog.d/7.fixed.md docs/SYSTEM_IMPACT_LOG.md 2>&1)"; rc=$?
[ "$rc" = "0" ] && grep -q "RESULT: CONFORMING" <<<"$out" && ok "a conforming change passes" \
  || bad "conforming change (exit $rc)"

# 4. Each declared convention is enforced when the change ignores it.
out="$(python3 "$CHK" --config "$CFG" --lane feature --changed src/a.py CHANGELOG.md 2>&1)"; rc=$?
[ "$rc" = "1" ] \
  && grep -q "assembled file edited directly" <<<"$out" \
  && grep -q "no fragment" <<<"$out" \
  && grep -q "impact log not updated" <<<"$out" \
  && grep -q "no spec for the change" <<<"$out" \
  && ok "missing fragment / impact log / spec and a direct assembled-file edit all fail" \
  || bad "violation case (exit $rc)"

# 5. An exempt lane skips the spec and changelog requirements.
out="$(python3 "$CHK" --config "$CFG" --lane chore --changed src/a.py 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "an exempt lane skips spec and changelog" || bad "exempt lane (exit $rc)"

# 6. A fragment outside the declared categories fails.
out="$(python3 "$CHK" --config "$CFG" --lane feature \
        --changed changelog.d/8.nope.md docs/specs/a.md docs/SYSTEM_IMPACT_LOG.md 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q "bad fragment category" <<<"$out" && ok "an unknown fragment category fails" \
  || bad "fragment category (exit $rc)"

# 7. THE RATCHET, both directions. Same banned character, different side of the diff.
printf '%s\n' '--- a/docs/x.md' '+++ b/docs/x.md' '@@ -1,2 +1,3 @@' \
  ' pre-existing line with an em dash '$'—'' left alone' '+a newly added clean line' > "$TMP/inherit.patch"
out="$(python3 "$CHK" --config "$CFG" --lane chore --diff "$TMP/inherit.patch" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "RATCHET: a pre-existing violation in context is inherited, not failed" \
  || bad "ratchet inherit (exit $rc): $out"

printf '%s\n' '--- a/docs/x.md' '+++ b/docs/x.md' '@@ -1,2 +1,3 @@' \
  ' a clean pre-existing line' '+a newly added line with an em dash '$'—'' in it' > "$TMP/introduce.patch"
out="$(python3 "$CHK" --config "$CFG" --lane chore --diff "$TMP/introduce.patch" 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q "banned character in an added line" <<<"$out" \
  && ok "RATCHET: a newly introduced violation fails" || bad "ratchet introduce (exit $rc)"

# 7b. Docs rule: shipping code without updating the reference that describes it fails. This is the
#     rule that would have caught a command merging undocumented.
cat > "$TMP/docs.yml" <<'YML'
conventions:
  exempt_lanes: [chore]
  docs:
    "cli/*.py":
      require: ["cli/README.md", "docs/reference/README.md"]
      why: "a command is not shipped until the CLI reference describes it"
    "docs/guides/*.md":
      require: ["docs/README.md"]
YML
out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane feature --changed cli/doctor.py 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q "docs not updated for cli/\*.py" <<<"$out" \
  && ok "shipping a command without the reference fails" || bad "docs rule violation (exit $rc)"

out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane feature --changed cli/doctor.py cli/README.md 2>&1)"; rc=$?
[ "$rc" = "0" ] && grep -q "docs updated for cli/\*.py" <<<"$out" \
  && ok "any one of the required docs satisfies the rule" || bad "docs rule satisfied (exit $rc)"

out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane feature --changed docs/guides/new.md 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q "docs not updated for docs/guides/\*.md" <<<"$out" \
  && ok "a new guide missing from the index fails" || bad "guide index rule (exit $rc)"

out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane feature --changed src/unrelated.py 2>&1)"; rc=$?
[ "$rc" = "0" ] && ! grep -q "docs not updated" <<<"$out" \
  && ok "an untriggered docs rule stays silent" || bad "docs rule should not fire (exit $rc)"

out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane chore --changed cli/doctor.py 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "an exempt lane skips the docs rule" || bad "docs rule exempt lane (exit $rc)"

# 7b2. `on: added` distinguishes a NEW file from an edited one. Firing on every edit would cry wolf, and
#      a gate that cries wolf gets bypassed rather than obeyed.
cat > "$TMP/added.yml" <<'YML'
conventions:
  exempt_lanes: [chore]
  docs:
    "docs/guides/*.md":
      on: added
      require: ["docs/README.md"]
YML
printf '%s\n' '--- a/docs/guides/existing.md' '+++ b/docs/guides/existing.md' '@@ -1 +1,2 @@' ' x' '+y' > "$TMP/edit.patch"
python3 "$CHK" --config "$TMP/added.yml" --lane feature --diff "$TMP/edit.patch" >/dev/null 2>&1
[ "$?" = "0" ] && ok "on:added ignores an edit to an existing file" || bad "on:added fired on an edit"

printf '%s\n' '--- /dev/null' '+++ b/docs/guides/new.md' '@@ -0,0 +1 @@' '+new' > "$TMP/add.patch"
out="$(python3 "$CHK" --config "$TMP/added.yml" --lane feature --diff "$TMP/add.patch" 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q "docs not updated" <<<"$out" \
  && ok "on:added fires for a newly added file" || bad "on:added missed a new file (exit $rc)"

# Without a diff the rule CANNOT be evaluated. It must say so, not pass silently: an unevaluated rule
# that looks identical to a satisfied one is the fail-open shape this gate exists to avoid.
out="$(python3 "$CHK" --config "$TMP/added.yml" --lane feature --changed docs/guides/new.md 2>&1)"
grep -q "not evaluated" <<<"$out" \
  && ok "an on:added rule without a diff reports itself as unevaluated" \
  || bad "on:added without a diff was silently skipped"

# 7c. FAIL-OPEN GUARD. `--changed "$(git diff --name-only)"` arrives as ONE newline-joined argument in
#     some shells. Unsplit it matches no pattern, every rule sits silent and the gate PASSES a change it
#     never judged. It must behave exactly as if the paths were passed separately.
joined="$(printf 'cli/doctor.py\ndocs/guides/new.md\nsrc/x.py')"
out="$(python3 "$CHK" --config "$TMP/docs.yml" --lane feature --changed "$joined" 2>&1)"; rc=$?
[ "$rc" = "1" ] \
  && grep -q "docs not updated for cli/\*.py" <<<"$out" \
  && grep -q "docs not updated for docs/guides/\*.md" <<<"$out" \
  && ok "a newline-joined path list is split, not silently passed" \
  || bad "FAIL-OPEN: newline-joined --changed was not judged (exit $rc)"

# 8. A config declaring nothing is a pass, not a failure: adoption must not require the block.
echo "runtime: generic" > "$TMP/bare.yml"
out="$(python3 "$CHK" --config "$TMP/bare.yml" --changed src/a.py 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "no declared conventions is a pass, not a failure" || bad "bare config (exit $rc)"

# 9. A declared path that does not exist is a SETUP error (2), not a change violation (1).
cat > "$TMP/wrong.yml" <<'YML'
conventions:
  impact_log: "docs/DOES_NOT_EXIST.md"
YML
out="$(python3 "$CHK" --config "$TMP/wrong.yml" --changed src/a.py 2>&1)"; rc=$?
[ "$rc" = "2" ] && ok "a declared path that does not exist is a setup error (exit 2)" \
  || bad "misconfiguration should be exit 2, got $rc"

# 10. A missing config is a setup error too, never a silent pass.
python3 "$CHK" --config "$TMP/nope.yml" --changed a.py >/dev/null 2>&1
[ "$?" = "2" ] && ok "a missing config is a setup error (exit 2)" || bad "missing config"

[ "$fail" = "0" ] && { echo "conventions gate self-test: PASS"; exit 0; } || { echo "conventions gate self-test: FAIL"; exit 1; }
