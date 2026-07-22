#!/usr/bin/env sh
# Self-test for merge-eligibility.py. Exit 0 iff all rules hold.
DIR=$(dirname "$0"); ME="$DIR/merge-eligibility.py"; fail=0
code() { python3 "$ME" "$@" >/dev/null 2>&1; echo $?; }
# 1. protected wins even when it is in the auto_merge_class
[ "$(code crypto/aes.py --protected '**/crypto/**' --auto-merge-class '**/*.py' --posture earned-automerge)" = "0" ] \
  || { echo "FAIL: protected path must be human-approve"; fail=1; }
# 2. clean docs change, earned-automerge -> autonomous-eligible
[ "$(code docs/x.md --protected '.github/**,**/crypto/**' --auto-merge-class 'docs/**' --posture earned-automerge)" = "3" ] \
  || { echo "FAIL: eligible change should be autonomous-eligible"; fail=1; }
# 3. same change, advisory posture -> human-approve
[ "$(code docs/x.md --protected '.github/**' --auto-merge-class 'docs/**' --posture advisory)" = "0" ] \
  || { echo "FAIL: advisory posture must be human-approve"; fail=1; }
# 4. one path outside the class -> human-approve
[ "$(code docs/x.md src/app.py --auto-merge-class 'docs/**' --posture earned-automerge)" = "0" ] \
  || { echo "FAIL: path outside class must be human-approve"; fail=1; }
# 5. MISCONFIGURED class includes a protected path -> still human-approve
[ "$(code .github/workflows/ci.yml --protected '.github/**' --auto-merge-class 'docs/**,.github/**' --posture earned-automerge)" = "0" ] \
  || { echo "FAIL: misconfigured overlap must not auto-merge a protected path"; fail=1; }
[ "$fail" = "0" ] && { echo "merge-eligibility self-test: PASS"; exit 0; } || { echo "merge-eligibility self-test: FAIL"; exit 1; }
