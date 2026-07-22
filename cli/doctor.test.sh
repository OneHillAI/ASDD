#!/usr/bin/env bash
# Self-test for `asdd doctor` (cli/doctor.py): the preflight names the three states an adopter confuses
# - reachable / installed-but-off-PATH / absent - and only fails on a hard requirement of THIS config.
# The load-bearing case is #4: an openspec that is installed but NOT on PATH must read as a warning with
# the path, NOT as "absent" (the trap the whole change exists to remove). Hermetic: a fake openspec and a
# scrubbed env, so it runs with or without a real openspec installed.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
DOC="$DIR/doctor.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }

echo "doctor self-test"

# A fake openspec that is a real executable but lives OUTSIDE PATH; the search hook points doctor at it.
mkdir -p "$TMP/fakebin" "$TMP/home" "$TMP/empty"
printf '#!/bin/sh\necho 1.6.0\n' > "$TMP/fakebin/openspec"; chmod +x "$TMP/fakebin/openspec"

# An openspec-selecting config off the valid template roster (so only the spec-tool state varies).
sed 's/^spec_tool:.*/spec_tool: openspec/' "$ROOT/.asdd.example.yml" > "$TMP/os.yml"
grep -q '^spec_tool: openspec' "$TMP/os.yml" || printf '\nspec_tool: openspec\n' >> "$TMP/os.yml"

# 1. Healthy builtin config (the repo template, in-repo so recipes/ resolves) -> READY, exit 0, no FAIL.
out="$(python3 "$DOC" "$ROOT/.asdd.example.yml" 2>&1)"; rc=$?
[ "$rc" = "0" ] && ! grep -q '\[FAIL\]' <<<"$out" && grep -q 'RESULT: READY' <<<"$out" \
  && ok "healthy builtin config is READY (exit 0)" || bad "healthy builtin config (exit $rc)"

# 2. A developer==tester roster is a HARD failure (exit 1), naming the broken rule.
out="$(python3 "$DOC" "$ROOT/validation/cases/dev-equals-tester.yml" 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q '\[FAIL\]' <<<"$out" && grep -qi 'hard rule' <<<"$out" \
  && ok "developer==tester fails closed (exit 1)" || bad "developer==tester roster (exit $rc)"

# 3. spec_tool: openspec with the CLI genuinely absent -> HARD failure (exit 1). Scrubbed env so neither
#    PATH, npm, nor the home-dir defaults can surface a real openspec; the search hook is an empty dir.
out="$(env -i HOME="$TMP/home" PATH="/usr/bin:/bin" ASDD_OPENSPEC_SEARCH="$TMP/empty" \
       python3 "$DOC" "$TMP/os.yml" 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q 'openspec CLI is absent' <<<"$out" \
  && ok "openspec selected but absent fails closed (exit 1)" || bad "openspec-absent case (exit $rc)"

# 4. THE case: openspec installed but OFF PATH -> warning with the path, NOT absent, and NOT a hard fail.
out="$(env -i HOME="$TMP/home" PATH="/usr/bin:/bin" ASDD_OPENSPEC_SEARCH="$TMP/fakebin" \
       python3 "$DOC" "$TMP/os.yml" 2>&1)"; rc=$?
[ "$rc" = "0" ] \
  && grep -q 'openspec is installed but not on PATH' <<<"$out" \
  && grep -q "$TMP/fakebin/openspec" <<<"$out" \
  && ! grep -q 'openspec CLI is absent' <<<"$out" \
  && ok "openspec off-PATH is a warning with the path (exit 0), not 'absent'" \
  || bad "openspec off-PATH case (exit $rc)"

# 5. A missing config is a clear hard failure, not a crash.
out="$(python3 "$DOC" "$TMP/nope.yml" 2>&1)"; rc=$?
[ "$rc" = "1" ] && grep -q 'config not found' <<<"$out" \
  && ok "missing config fails cleanly (exit 1)" || bad "missing-config case (exit $rc)"

[ "$fail" = "0" ] && { echo "doctor self-test: PASS"; exit 0; } || { echo "doctor self-test: FAIL"; exit 1; }
