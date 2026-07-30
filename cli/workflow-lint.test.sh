#!/usr/bin/env bash
# The workflow-lint must FAIL on a workflow that does not parse: the exact hole that let a broken
# docs-deploy.yml merge and take the docs site down, since nothing validated workflow YAML.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
python3 -c "import yaml" 2>/dev/null || { echo "workflow-lint self-test: SKIP (PyYAML absent)"; exit 0; }
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 "$ROOT/cli/workflow-lint.py" "$ROOT" >/dev/null 2>&1 \
  && echo "ok: every workflow in the repo parses" || { echo "FAIL: a repo workflow does not parse"; fail=1; }
mkdir -p "$TMP/.github/workflows"
printf 'name: x\non:\n  push:\njobs:\n  a:\n    steps:\n      - run: |\n          echo one\n        bad: value: here\n' > "$TMP/.github/workflows/broken.yml"
python3 "$ROOT/cli/workflow-lint.py" "$TMP" >/dev/null 2>&1 \
  && { echo "FAIL: a non-parsing workflow was accepted"; fail=1; } || echo "ok: a non-parsing workflow is rejected"
echo
[ "$fail" -eq 0 ] && echo "workflow-lint self-test: PASS" || echo "workflow-lint self-test: FAIL"
exit "$fail"
