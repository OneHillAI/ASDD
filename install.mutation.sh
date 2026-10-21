#!/usr/bin/env bash
# Mutation check for install.sh: every safety check in the installer is tagged `# guard:NAME` on its own line.
# For each tag this makes a copy of the installer with that one line replaced by `:` and runs install.test.sh
# against it. The test must FAIL. A mutant that still passes means a safety check nothing actually tests.
#
# SAFETY. The mutants are installers with a safety check removed, so they are the dangerous ones. They only run
# through install.test.sh, which confines them (temp root, fake HOME, rm shim) and, because this script sets
# ASDD_REQUIRE_OS_SANDBOX=1, refuses to run at all unless the OS sandbox is active. This script itself deletes
# nothing recursively: it removes the mutant files it wrote, one by name, and then the empty directory.
#
# Exit 0 iff every non-exempt guard was caught. Exit 2 if it cannot run safely.
set -u
DIR=$(cd "$(dirname "$0")" && pwd -P)
SRC=$DIR/install.sh
TEST=$DIR/install.test.sh

# Guards that cannot be reached from a test, with the reason. Anything not listed here must be caught.
EXEMPT="post-smoke"
exempt_reason() { case "$1" in post-smoke) echo "defence in depth: unreachable once version-smoke has passed on the same archive" ;; esac; }

[ -f "$SRC" ] && [ -f "$TEST" ] || { echo "install.mutation.sh: install.sh or install.test.sh is missing"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "install.mutation.sh: python3 is required"; exit 2; }
if [ "$(uname -s)" != Darwin ] || ! command -v sandbox-exec >/dev/null 2>&1; then
  if [ "${ASDD_MUTATION_ISOLATED:-0}" != 1 ]; then
    echo "install.mutation.sh: no OS sandbox here. Run this only inside a throwaway container or VM and set ASDD_MUTATION_ISOLATED=1."
    exit 2
  fi
fi

M=$(mktemp -d "${TMPDIR:-/tmp}/asdd-install-mutants.XXXXXX") || { echo "install.mutation.sh: cannot create a temp dir"; exit 2; }
[ -n "$M" ] && [ -d "$M" ] && [ ! -L "$M" ] || { echo "install.mutation.sh: temp dir is not usable"; exit 2; }

guards=$(grep -o '# guard:[a-z-]*' "$SRC" | sed 's/# guard://' | sort -u)
[ -n "$guards" ] || { echo "install.mutation.sh: no '# guard:' tags found in install.sh"; exit 2; }

echo "mutating $(echo "$guards" | wc -l | tr -d ' ') guards in install.sh (each run is sandboxed)"
status=0
for g in $guards; do
  mutant="$M/install.$g.sh"
  count=$(python3 -I - "$SRC" "$mutant" "$g" <<'PY'
import re, sys
src, out, g = sys.argv[1:4]
n = 0; lines = []
for line in open(src).read().split("\n"):
    if line.rstrip().endswith("# guard:" + g):
        indent = re.match(r"\s*", line).group(0)
        lines.append(indent + ":   # mutated: guard " + g); n += 1
    else:
        lines.append(line)
open(out, "w").write("\n".join(lines))
print(n)
PY
)
  if [ "${count:-0}" -lt 1 ]; then echo "  ERROR  $g: no line was mutated"; status=2; continue; fi
  ASDD_REQUIRE_OS_SANDBOX=${ASDD_REQUIRE_OS_SANDBOX:-1} ASDD_INSTALL_SH="$mutant" bash "$TEST" >"$M/out.$g" 2>&1
  rc=$?
  if [ "$rc" = 1 ]; then
    echo "  caught       $g  ($(grep -c '^  FAIL' "$M/out.$g") failing checks)"
  elif [ "$rc" = 2 ]; then
    echo "  ERROR        $g: the test refused to run safely"; sed 's/^/           /' "$M/out.$g" | head -3; status=2
  elif case " $EXEMPT " in *" $g "*) true ;; *) false ;; esac; then
    echo "  exempt       $g  ($(exempt_reason "$g"))"
  else
    echo "  NOT CAUGHT   $g: the tests still pass with this check removed"; [ "$status" = 0 ] && status=1
  fi
  rm -f -- "$mutant" "$M/out.$g"
done
rmdir "$M" 2>/dev/null || echo "install.mutation.sh: left $M (not empty)"

case $status in 0) echo "mutation check: PASS" ;; 1) echo "mutation check: FAIL" ;; *) echo "mutation check: could not complete" ;; esac
exit "$status"
