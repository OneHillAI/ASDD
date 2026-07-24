#!/usr/bin/env bash
# Self-test for the intake gate.
#
# The gate is the airlock: every downstream job trusts its verdict, and it is the one component that
# reads fully untrusted text (a PR body from a stranger). Its properties were documented in comments and
# asserted nowhere, so this pins them - especially the two that are security properties rather than
# conveniences: a `..` reference cannot resolve an unrelated file into a "spec", and a config cannot
# widen the matcher into a rubber stamp.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/intake-check.sh"
command -v jq >/dev/null 2>&1 || { echo "intake-check self-test: FAIL (jq is required by the gate itself)"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# A tree the gate reads for "does this referenced spec exist?" - run from here so relative paths resolve.
TREE="$TMP/tree"
mkdir -p "$TREE/docs/specs" "$TREE/openspec/changes/add-auth" "$TREE/openspec/specs/auth"
echo "# a spec"     > "$TREE/docs/specs/real.md"
echo "# readme"     > "$TREE/README.md"
echo "# a proposal" > "$TREE/openspec/changes/add-auth/proposal.md"
echo "# a capability" > "$TREE/openspec/specs/auth/spec.md"
# The real OpenSpec shape: the change's SPEC is its delta files, not a proposal.
mkdir -p "$TREE/openspec/changes/add-auth/specs/auth"
echo "# a delta" > "$TREE/openspec/changes/add-auth/specs/auth/spec.md"

cfg() { printf 'lanes:\n  - feature\n  - fix\n  - docs\n  - chore\nspec_paths:\n%s\n' "$1" > "$TREE/$2"; }
cfg '  - docs/specs/*.md' asdd-default.yml
cfg '  - openspec/changes/*/proposal.md
  - openspec/specs/**/spec.md' asdd-openspec.yml
# A config that buys itself a pass by smuggling ALTERNATION into a "path": `^(zzz|src/a\.py)$` matches
# the very file the PR changes, so every such PR would look spec-driven. Alternation is the exploit that
# escaping does not stop (a `.` gets escaped, a `|` does not), which is why patterns are validated.
cfg '  - zzz|src/a.py' asdd-evil.yml

# spec_tool: openspec with NO spec_paths -> the gate uses the openspec preset (deltas + living specs).
printf 'lanes:\n  - feature\n  - fix\n  - docs\n  - chore\nspec_tool: openspec\n' \
  > "$TREE/asdd-openspec-preset.yml"
# spec_tool: openspec but an EXPLICIT spec_paths -> the explicit list wins, the preset is not applied.
printf 'lanes:\n  - feature\n  - fix\n  - docs\n  - chore\nspec_tool: openspec\nspec_paths:\n  - docs/specs/*.md\n' \
  > "$TREE/asdd-openspec-explicit-wins.yml"

# A real file OUTSIDE the repo tree. A body reaching it by traversal must not count as a spec.
mkdir -p "$TMP/outside"
echo "# not a spec in this repo" > "$TMP/outside/spec.md"

# case <name> <config> <labels> <body> <changed.txt> <expect passed> <expect spec_ok>
case_run() {
  local name="$1" conf="$2" labels="$3" body="$4" changed="$5" want_pass="$6" want_spec="$7"
  local w="$TMP/w"; rm -rf "$w"; mkdir -p "$w"
  printf '%s' "$body" > "$w/body.md"
  printf '%s' "$labels" > "$w/labels.txt"
  printf 'feat: a change\n\nSigned-off-by: A Dev <a@example.com>\0' > "$w/commits.txt"
  printf '%s' "$changed" > "$w/changed.txt"
  printf 'pr_number=1\nhead_sha=abc123\nrequire_spec=true\n' > "$w/meta.env"
  ( cd "$TREE" && ASDD_CONFIG="$conf" bash "$GATE" "$w" "$w/out.json" >/dev/null 2>&1 )
  local got_pass got_spec
  got_pass="$(jq -r '.passed' "$w/out.json" 2>/dev/null)"
  got_spec="$(jq -r '.spec_ok' "$w/out.json" 2>/dev/null)"
  if [ "$got_pass" = "$want_pass" ] && [ "$got_spec" = "$want_spec" ]; then
    echo "  ok   $name"
  else
    echo "  FAIL $name (passed=$got_pass want $want_pass / spec_ok=$got_spec want $want_spec)"
    fail=1
  fi
}

DISC='- [x] Written by an AI agent'
OK_LABELS='feature'

echo "intake-check self-test"

# --- the spec gate, default layout ------------------------------------------------------------------
case_run "adding a spec satisfies the gate" \
  asdd-default.yml "$OK_LABELS" "$DISC" "$(printf 'A\tdocs/specs/new.md\n')" true true

case_run "referencing an existing spec satisfies the gate" \
  asdd-default.yml "$OK_LABELS" "$DISC
Spec: docs/specs/real.md" "$(printf 'M\tsrc/a.py\n')" true true

case_run "no spec at all fails the gate" \
  asdd-default.yml "$OK_LABELS" "$DISC" "$(printf 'M\tsrc/a.py\n')" false false

case_run "a fabricated spec reference fails (path must exist)" \
  asdd-default.yml "$OK_LABELS" "$DISC
Spec: docs/specs/imaginary.md" "$(printf 'M\tsrc/a.py\n')" false false

# A traversal reference under the default layout. Belt and braces: the anchored single-segment regex
# rejects this on its own (`*` cannot match `/`), so this pins the outcome, not the `..` guard. The case
# that actually exercises the guard is the `**` one below.
case_run "a .. traversal reference cannot pass off README as a spec" \
  asdd-default.yml "$OK_LABELS" "$DISC
Spec: docs/specs/../../README.md" "$(printf 'M\tsrc/a.py\n')" false false

# A DELETED spec matches the path but must not count, or a spec-removing PR passes the spec gate.
case_run "deleting a spec does not satisfy the gate" \
  asdd-default.yml "$OK_LABELS" "$DISC" "$(printf 'D\tdocs/specs/real.md\nM\tsrc/a.py\n')" false false

case_run "a renamed-to spec counts (R status, new path is \$NF)" \
  asdd-default.yml "$OK_LABELS" "$DISC" "$(printf 'R100\tdocs/specs/old.md\tdocs/specs/new.md\n')" true true

# --- the chore escape --------------------------------------------------------------------------------
case_run "a chore PR skips the spec requirement" \
  asdd-default.yml 'chore' "$DISC" "$(printf 'M\tsrc/a.py\n')" true true

# --- a foreign layout: OpenSpec -----------------------------------------------------------------------
case_run "OpenSpec: adding a proposal satisfies the gate" \
  asdd-openspec.yml "$OK_LABELS" "$DISC" "$(printf 'A\topenspec/changes/add-auth/proposal.md\n')" true true

case_run "OpenSpec: referencing an existing proposal satisfies the gate" \
  asdd-openspec.yml "$OK_LABELS" "$DISC
Spec: openspec/changes/add-auth/proposal.md" "$(printf 'M\tsrc/a.py\n')" true true

case_run "OpenSpec: ** matches a nested capability spec" \
  asdd-openspec.yml "$OK_LABELS" "$DISC
Spec: openspec/specs/auth/spec.md" "$(printf 'M\tsrc/a.py\n')" true true

# Under the OpenSpec config, ASDD's own layout is NOT a spec: the configured set is the whole set.
case_run "OpenSpec config: docs/specs is not a spec here" \
  asdd-openspec.yml "$OK_LABELS" "$DISC
Spec: docs/specs/real.md" "$(printf 'M\tsrc/a.py\n')" false false

# SECURITY: traversal where the `..` guard is the ONLY thing standing. Under a `**` pattern the segment
# charset spans `/` and `.`, so `openspec/specs/../../../outside/spec.md` MATCHES the regex and names a
# file that really exists (outside the repo entirely). Without the guard the gate would resolve it and
# call a stranger's arbitrary file this PR's spec.
case_run "** layout: a .. traversal to a real file outside the repo is refused" \
  asdd-openspec.yml "$OK_LABELS" "$DISC
Spec: openspec/specs/../../../outside/spec.md" "$(printf 'M\tsrc/a.py\n')" false false

# --- spec_tool: openspec preset (no explicit spec_paths) ---------------------------------------------
case_run "preset: adding a change delta satisfies the gate" \
  asdd-openspec-preset.yml "$OK_LABELS" "$DISC" \
  "$(printf 'A\topenspec/changes/add-auth/specs/auth/spec.md\n')" true true

case_run "preset: referencing an existing living spec satisfies the gate" \
  asdd-openspec-preset.yml "$OK_LABELS" "$DISC
Spec: openspec/specs/auth/spec.md" "$(printf 'M\tsrc/a.py\n')" true true

case_run "preset: a bare change dir (no delta) is not a spec" \
  asdd-openspec-preset.yml "$OK_LABELS" "$DISC" "$(printf 'A\topenspec/changes/add-auth/README.md\n')" false false

case_run "preset: ASDD's docs/specs is not a spec under the openspec preset" \
  asdd-openspec-preset.yml "$OK_LABELS" "$DISC" "$(printf 'A\tdocs/specs/real.md\n')" false false

# Explicit spec_paths overrides the preset: with spec_tool: openspec BUT spec_paths: docs/specs, the
# openspec deltas are NOT a spec and docs/specs IS - proving the explicit list wins over the tool default.
case_run "explicit spec_paths wins over the spec_tool preset (docs/specs counts)" \
  asdd-openspec-explicit-wins.yml "$OK_LABELS" "$DISC" "$(printf 'A\tdocs/specs/real.md\n')" true true

case_run "explicit spec_paths wins over the preset (openspec delta does NOT count)" \
  asdd-openspec-explicit-wins.yml "$OK_LABELS" "$DISC" \
  "$(printf 'A\topenspec/changes/add-auth/specs/auth/spec.md\n')" false false

# SECURITY: a config pattern of `.*` is regex, not a path. If it were escaped-and-honoured rather than
# rejected, every PR would match and the spec gate would be decorative.
case_run "a regex-shaped spec_path is rejected, not honoured" \
  asdd-evil.yml "$OK_LABELS" "$DISC" "$(printf 'M\tsrc/a.py\n')" false false

# When every configured pattern is rejected the matcher falls back to the default rather than to an
# empty regex. Both are safe (an empty regex matches nothing, so the gate would fail closed), but the
# fallback is the documented behaviour, so it is pinned rather than left to chance.
case_run "an all-invalid spec_paths falls back to the default, not to an empty matcher" \
  asdd-evil.yml "$OK_LABELS" "$DISC" "$(printf 'A\tdocs/specs/new.md\n')" true true

# --- the other gates still hold ----------------------------------------------------------------------
case_run "no disclosure fails" \
  asdd-default.yml "$OK_LABELS" "nothing ticked" "$(printf 'A\tdocs/specs/new.md\n')" false true

case_run "two lanes fail (exactly one required)" \
  asdd-default.yml "$(printf 'feature\nfix\n')" "$DISC" "$(printf 'A\tdocs/specs/new.md\n')" false true

case_run "zero lanes fail" \
  asdd-default.yml "" "$DISC" "$(printf 'A\tdocs/specs/new.md\n')" false true

# A documented config carries inline comments on its lanes and spec_paths. The gate must strip the
# comment from each token; before the fix the awk kept the trailing '# ...', so a bare lane label never
# matched (laned=false, every PR failed) and a commented spec glob matched nothing (spec_ok=false).
printf 'lanes:\n  - feature   # new capability\n  - chore     # trivial: CI, tooling, deps\nspec_paths:\n  - docs/specs/*.md   # the builtin specs\n' > "$TREE/asdd-commented.yml"
case_run "inline-commented lanes and spec_paths still accept a bare label + real spec" \
  asdd-commented.yml "feature" "$DISC" "$(printf 'A\tdocs/specs/new.md\n')" true true

# --- check 6: the declared-conventions gate ----------------------------------------------------------
# A project that declares a `conventions:` block has its change held to it at intake: the gate shells to
# cli/conventions-check.py against changes.diff, and a violation fails intake through the same verdict a
# missing disclosure would. A project with no block is a clean no-op, so the gate stays inert until a
# project opts in. The banned char is synthesised with printf so this source file carries no literal dash.
DASH="$(printf '\342\200\224')"          # U+2014 em dash, built as bytes so the source has none
CONVW="$TMP/convw"; mkdir -p "$CONVW"
printf '%s' "$DISC" > "$CONVW/body.md"
printf 'chore\n' > "$CONVW/labels.txt"   # chore: the spec gate is not in play, so this isolates check 6
printf 'chore: x\n\nSigned-off-by: A Dev <a@example.com>\0' > "$CONVW/commits.txt"
printf 'pr_number=1\nhead_sha=abc123\nrequire_spec=true\n' > "$CONVW/meta.env"
printf 'M\tsrc/a.py\n' > "$CONVW/changed.txt"
# A minimal block: only the style ratchet, so no other convention muddies the result.
CONVCFG="$TMP/conv.yml"
printf 'lanes:\n  - feature\n  - fix\n  - docs\n  - chore\nconventions:\n  style:\n    banned_chars: ["%s"]\n' "$DASH" > "$CONVCFG"

conv_case() { # <name> <config> <diff-added-line> <want_conv_ok> <want_passed>
  printf 'diff --git a/src/a.py b/src/a.py\n--- a/src/a.py\n+++ b/src/a.py\n@@ -0,0 +1 @@\n+%s\n' "$3" > "$CONVW/changes.diff"
  ( cd "$TREE" && ASDD_CONFIG="$2" bash "$GATE" "$CONVW" "$CONVW/out.json" >/dev/null 2>&1 )
  local gc gp; gc="$(jq -r '.conventions_ok' "$CONVW/out.json" 2>/dev/null)"; gp="$(jq -r '.passed' "$CONVW/out.json" 2>/dev/null)"
  if [ "$gc" = "$4" ] && [ "$gp" = "$5" ]; then echo "  ok   $1"; else echo "  FAIL $1 (conventions_ok=$gc want $4 / passed=$gp want $5)"; fail=1; fi
}
conv_case "a declared convention violated by the diff fails intake" "$CONVCFG" "# note ${DASH} here" false false
jq -e '.problems | map(select(startswith("Convention:"))) | length > 0' "$CONVW/out.json" >/dev/null \
  && echo "  ok   the violation is surfaced as a Convention problem" || { echo "  FAIL conventions violation not in problems[]"; fail=1; }
conv_case "a clean change passes the conventions gate" "$CONVCFG" "# a clean added line" true true
conv_case "no conventions block is inert even with the banned char present" "$TREE/asdd-default.yml" "# note ${DASH} here" true true

[ "$fail" = "0" ] && { echo "intake-check self-test: PASS"; exit 0; } || { echo "intake-check self-test: FAIL"; exit 1; }
