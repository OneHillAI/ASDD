#!/usr/bin/env sh
# Test for init.sh: --goose scaffolds the architecture lanes and copies the current
# deployment recipes (guards the recipe list against a rename); plain init keeps the
# conventional lanes. Exit 0 iff all expectations hold.
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail=0

# --goose target (a bare .git marker satisfies the git-repo check).
G=$(mktemp -d); mkdir "$G/.git"
if bash "$ROOT/cli/init.sh" --goose "$G" >/dev/null 2>&1; then
  grep -qE '^[[:space:]]*-[[:space:]]*govern\b'  "$G/.asdd.yml" || { echo "FAIL: --goose missing govern lane"; fail=1; }
  grep -qE '^[[:space:]]*-[[:space:]]*operate\b' "$G/.asdd.yml" || { echo "FAIL: --goose missing operate lane"; fail=1; }
  grep -qE '^[[:space:]]*-[[:space:]]*assure\b'  "$G/.asdd.yml" || { echo "FAIL: --goose missing assure lane"; fail=1; }
  # Every deployment recipe the kit ships must copy (would catch a stale name in the list).
  for r in test-author.yaml test-runner.yaml documentation.yaml interaction.yaml interaction-public.yaml setup.yaml; do
    [ -f "$G/recipes/$r" ] || { echo "FAIL: --goose did not copy recipes/$r"; fail=1; }
  done
  # The kit map must reach the adopter, or a setup agent has nothing to orient from.
  [ -f "$G/asdd-kit.yml" ] || { echo "FAIL: --goose did not copy asdd-kit.yml"; fail=1; }

  # Deployment-critical: a copied workflow must not reference a script that init did not copy. The publish
  # workflow calls .github/asdd/audit-export.sh, and the operate recipes need cli/operate-run.py; both were
  # missing from the manifest, so a fresh sink-configured deployment failed at runtime with nothing to
  # catch it. Assert the files a copied workflow depends on are present.
  [ -f "$G/.github/asdd/audit-export.sh" ] || { echo "FAIL: --goose copied the publish workflow but not audit-export.sh it calls"; fail=1; }
  [ -f "$G/cli/operate-run.py" ] || { echo "FAIL: --goose did not copy cli/operate-run.py (recipes emit through it)"; fail=1; }

  # The deterministic gates the operate kit calls must land. Including openspec-gate.py and its helper:
  # the MCP `openspec_gate` tool shells to the sibling openspec-gate.py, which imports _openspec_locate.py,
  # so the pair must travel with asdd-mcp.py or an openspec adopter's MCP has no file to call. Same for
  # conventions-check.py, which the MCP `conventions_check` tool shells to so the operate recipes can
  # read the host project's workflow before producing anything.
  for g in spec-check.py claim-check.py merge-eligibility.py openspec-gate.py _openspec_locate.py conventions-check.py audit.py asdd-mcp.py operate-guard.py run-agent.sh dev-council.py; do
    [ -f "$G/cli/$g" ] || { echo "FAIL: --goose did not copy cli/$g"; fail=1; }
  done

  # The developer council's runner drives cli/dev-council.py; the orchestrator is useless to an adopter if
  # the runner the docs point at never lands.
  [ -f "$G/.github/asdd/operate/dev-council.sh" ] || { echo "FAIL: --goose copied dev-council.py but not the operate/dev-council.sh runner"; fail=1; }

  # The operator-run agents (triage/support/contributor/merge) run through cli/run-agent.sh, which reads
  # their docs from the runtime agents dir. run-agent is useless if the docs it drives never land.
  for a in triage support review-contributor review-merge; do
    [ -f "$G/.github/asdd/agents/$a.md" ] || { echo "FAIL: --goose copied run-agent but not .github/asdd/agents/$a.md it drives"; fail=1; }
  done

  # The impact lens the review runtime runs (generic.sh: code security spec impact) needs its doc, or the
  # lens loads an empty prompt and silently contributes nothing.
  [ -f "$G/.github/asdd/agents/review-impact.md" ] || { echo "FAIL: --goose did not copy review-impact.md (the runtime runs the impact lens)"; fail=1; }

  # Every post-merge operate agent the kit wires must ship BOTH its workflow and its runner (a workflow
  # that calls a runner init did not copy fails at runtime). documentation and the test agent both run
  # this way; assert each pair lands.
  [ -f "$G/.github/workflows/asdd-test.yml" ] || { echo "FAIL: --goose did not copy the test workflow (asdd-test.yml)"; fail=1; }
  [ -f "$G/.github/asdd/operate/test.sh" ]    || { echo "FAIL: --goose copied the test workflow but not test.sh it calls"; fail=1; }

  # An operate agent that runs in CI must have its role's provider pair PASSED to it, not just resolvable:
  # resolving is useless if the env never carries the variables, and the per-role override would be
  # silently inert. Guard every role each runner resolves, across every operate workflow/runner pair.
  for pair in "asdd-docsync.yml:docsync.sh" "asdd-test.yml:test.sh"; do
    WF="$G/.github/workflows/${pair%%:*}"
    RUNNER="$G/.github/asdd/operate/${pair##*:}"
    [ -f "$WF" ] && [ -f "$RUNNER" ] || continue
    # The runner may call the resolver by path or through a variable; match either.
    ROLES=$(grep -oE '(resolve-model\.sh|\$RESOLVE)" +[a-z_]+' "$RUNNER" | awk '{print $NF}' | sort -u)
    # A guard that detects nothing would pass vacuously, which is worse than no guard.
    [ -n "$ROLES" ] || { echo "FAIL: could not detect which roles ${RUNNER##*/} resolves (guard broke)"; fail=1; }
    for role in $ROLES; do
      SUF=$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')
      grep -q "ASDD_RUNTIME_TOKEN__${SUF}" "$WF" || { echo "FAIL: ${WF##*/} does not pass ASDD_RUNTIME_TOKEN__${SUF} (per-role key inert in CI)"; fail=1; }
      grep -q "ASDD_MODEL_URL__${SUF}" "$WF"     || { echo "FAIL: ${WF##*/} does not pass ASDD_MODEL_URL__${SUF} (per-role endpoint inert in CI)"; fail=1; }
    done
    # The shared pair must still be passed, so a single-provider deployment keeps working.
    grep -q "ASDD_RUNTIME_TOKEN:" "$WF" || { echo "FAIL: ${WF##*/} dropped the shared token"; fail=1; }
    grep -q "ASDD_MODEL_URL:" "$WF"     || { echo "FAIL: ${WF##*/} dropped the shared endpoint"; fail=1; }
  done
else
  echo "FAIL: init --goose exited non-zero"; fail=1
fi
rm -rf "$G"

# Plain init keeps the conventional lanes.
P=$(mktemp -d); mkdir "$P/.git"
if bash "$ROOT/cli/init.sh" "$P" >/dev/null 2>&1; then
  grep -qE '^[[:space:]]*-[[:space:]]*feature\b' "$P/.asdd.yml" || { echo "FAIL: plain init missing feature lane"; fail=1; }
  grep -qE '^[[:space:]]*-[[:space:]]*govern\b'  "$P/.asdd.yml" && { echo "FAIL: plain init leaked operate lanes"; fail=1; }
  # The intake gate and its contributor-facing feedback are a pair: without asdd-intake-feedback.yml a
  # failing PR shows only a red check, with no comment saying what to fix. Both must reach the adopter.
  [ -f "$P/.github/workflows/asdd-intake.yml" ] || { echo "FAIL: plain init did not copy asdd-intake.yml"; fail=1; }
  [ -f "$P/.github/workflows/asdd-intake-feedback.yml" ] || { echo "FAIL: plain init copied intake but not asdd-intake-feedback.yml (a failing PR gets no feedback comment)"; fail=1; }
  # The review runtime is base (not --goose): every lens it assembles must land, impact included.
  for a in review-code review-security review-spec review-impact review-quality; do
    [ -f "$P/.github/asdd/agents/$a.md" ] || { echo "FAIL: plain init did not copy the $a lens doc the runtime runs"; fail=1; }
  done
else
  echo "FAIL: plain init exited non-zero"; fail=1
fi
rm -rf "$P"

[ "$fail" = "0" ] && { echo "init self-test: PASS"; exit 0; } || { echo "init self-test: FAIL"; exit 1; }
