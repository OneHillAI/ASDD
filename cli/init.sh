#!/usr/bin/env bash
# ASDD - init: scaffold the governance files into a target repo.
# Thin and auditable by design: it copies this repo's template files, writes a
# config, a PR template, a CODEOWNERS, the gates (the intake + review pipeline) and the dashboard,
# ensures the lane labels, and prints the secrets to set. It never pushes, merges, or deletes.
#
# Usage: bash cli/init.sh [--force] [--dry-run] [--goose] [TARGET_DIR]
#   Run from a checkout of ASDD. TARGET_DIR defaults to the current dir
#   and must be a git repository. Existing files are skipped unless --force.
#   --goose also installs the Goose operator kit (recipes + gates + the MCP extension).
set -euo pipefail

FORCE=0; DRYRUN=0; GOOSE=0; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1 ;;
    --dry-run) DRYRUN=1 ;;
    --goose)   GOOSE=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*)        echo "unknown option: $1" >&2; exit 2 ;;
    *)         TARGET="$1" ;;
  esac
  shift
done

# The ASDD checkout this script lives in = the source of the templates.
SELF="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${TARGET:-$PWD}"; TARGET="$(cd "$TARGET" && pwd)"

[ -f "$SELF/AGENTS.md" ] || { echo "error: run this from a checkout of ASDD (AGENTS.md not found)" >&2; exit 1; }
[ -e "$TARGET/.git" ]    || { echo "error: $TARGET is not a git repository" >&2; exit 1; }  # dir, or a file for a worktree/submodule

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
rel()  { printf '%s' "${1#"$TARGET"/}"; }

# write DEST  (content on stdin). Always consumes stdin (pipefail-safe).
write() {
  local dest="$1" content; content="$(cat)"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then say "skip (exists): $(rel "$dest")   [--force to overwrite]"; return 0; fi
  if [ "$DRYRUN" -eq 1 ]; then say "would write: $(rel "$dest")"; return 0; fi
  mkdir -p "$(dirname "$dest")"; printf '%s\n' "$content" >"$dest"; say "wrote: $(rel "$dest")"
}

# copy SRC DEST
copy() {
  local src="$1" dest="$2"
  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then say "skip (exists): $(rel "$dest")   [--force to overwrite]"; return 0; fi
  if [ "$DRYRUN" -eq 1 ]; then say "would copy: $(rel "$dest")"; return 0; fi
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; say "copied: $(rel "$dest")"
}

# goose_lanes: with --goose, swap the conventional lanes for the operate taxonomy that
# mirrors the ASDD architecture (Govern/Know/Operate/Assure + standard + docs + chore).
# A plain govern-only init keeps the conventional set. See docs/guides/operate-lanes.md.
goose_lanes() {
  if [ "$GOOSE" -eq 0 ]; then cat; return; fi
  awk '
    inlanes==1 { if ($0 ~ /^[[:space:]]*-/) next; inlanes=0 }
    /^lanes:/ {
      print "lanes:"
      print "  - govern     # governance layer: gates, review lenses, merge authority, intake"
      print "  - operate    # operate layer: recipes, roster, MCP bridge, setup, guard"
      print "  - know       # knowledge layer: grounding, wiki / OKGF"
      print "  - assure     # assurance: tests, validation, model heterogeneity, attestation"
      print "  - standard   # the standard / spec / conformance"
      print "  - docs       # documentation"
      print "  - chore      # trivial: CI, tooling, deps (spec-exempt)"
      inlanes=1; next
    }
    { print }
  '
}

echo "ASDD - scaffolding governance into: $TARGET"
[ "$DRYRUN" -eq 1 ] && echo "(dry run - no files will be written)"

step "1. Constitution (AGENTS.md)"
copy "$SELF/AGENTS.md" "$TARGET/AGENTS.md"
say "edit the sections marked (adapt); keep the (fixed) ones."

step "2. Config (.asdd.yml)"
# Rewrite the example's 3-line header so the generated config reads as this repo's
# own config (and carries no em-dash from the example header).
{
  echo "# ASDD - adoption config for this repo. Edit it; keep it under version control."
  echo "# Schema and docs: https://github.com/OneHillAI/ASDD"
  tail -n +4 "$SELF/.asdd.example.yml"
} | goose_lanes | write "$TARGET/.asdd.yml"
say "review protected_paths and the merge posture for your repo."
[ "$GOOSE" -eq 1 ] && say "lanes use the operate taxonomy (govern/operate/know/assure/standard/docs/chore); trim or override in .asdd.yml (see docs/guides/operate-lanes.md)."
# Ship the model-heterogeneity check so CI can enforce developer != tester once the models are set.
copy "$SELF/cli/check-models.sh" "$TARGET/scripts/check-models.sh"
{ [ "$DRYRUN" -eq 0 ] && bash "$SELF/cli/check-models.sh" "$TARGET/.asdd.yml"; } || true
say "set models.developer / models.test_author / models.test_runner (the test models MUST differ from developer); enforce with scripts/check-models.sh --strict in CI."

step "3. PR template (.github/PULL_REQUEST_TEMPLATE.md)"
write "$TARGET/.github/PULL_REQUEST_TEMPLATE.md" <<'TPL'
## Summary

<what and why>

## Disclosure (required - ASDD)

- [ ] Entirely human-authored
- [ ] Authored or co-authored by an AI agent under human direction

Agent identity (if any): <name>
Instructed by (human handle): <handle>

## Checklist

- [ ] Exactly one lane label
- [ ] Signed off (`git commit -s`)
- [ ] A test for new behaviour
TPL

step "4. CODEOWNERS (.github/CODEOWNERS)"
OWNER="@your-org/maintainers"
{
  echo "# Protected paths - a named human owner is required on these, permanently (STANDARD 2.2, 5.2)."
  echo "# Generated by ASDD init from .asdd.yml protected_paths. Set a real owner below."
  awk '/^protected_paths:/{f=1;next} /^[a-zA-Z]/{f=0} f && /^[[:space:]]*-/{gsub(/^[[:space:]]*-[[:space:]]*"?|"?[[:space:]]*$/,""); print $0" '"$OWNER"'"}' "$SELF/.asdd.example.yml"
} | write "$TARGET/.github/CODEOWNERS"
say "replace $OWNER with a real team or handle."

step "5. The gates (intake + review pipeline) + the dashboard"
# This IS the reference implementation. It lives in this repo's own .github/, so an adopter gets exactly
# what ASDD runs on itself: the deterministic intake gate, and the model review pipeline (dry-run until a
# model is wired). Read-only analysis is split from the write-scoped publish job (the security invariant).
for w in asdd-intake.yml asdd-intake-feedback.yml pr-review.yml pr-review-publish.yml; do
  copy "$SELF/.github/workflows/$w" "$TARGET/.github/workflows/$w"
done
for s in intake-check.sh owner-override.sh run-review.sh post-review.sh policy-check.sh set-status.sh security_scan.py audit-export.sh; do
  copy "$SELF/.github/asdd/$s" "$TARGET/.github/asdd/$s"
done
for r in generic.sh openai-compat.sh; do
  copy "$SELF/.github/asdd/runtime/$r" "$TARGET/.github/asdd/runtime/$r"
done
# The review lenses the runtime assembles (generic.sh runs code/security/spec/impact as the main pass and
# quality as the independent adversarial pass). review-impact MUST be here or the impact lens loads an
# empty prompt at an adopter and silently contributes nothing.
for a in review-code.md review-security.md review-spec.md review-impact.md review-quality.md; do
  copy "$SELF/.github/asdd/agents/$a" "$TARGET/.github/asdd/agents/$a"
done
# The read-only governance dashboard (curates PRs by stage, lanes, verdicts, releases).
# The role -> model/endpoint/key lookup. run-review.sh (govern) resolves the reviewer through it,
# so it installs with the BASE, not only with --goose. One copy, so the gate and the runners agree.
copy "$SELF/cli/resolve-model.sh" "$TARGET/cli/resolve-model.sh"
copy "$SELF/cli/dashboard.py" "$TARGET/cli/dashboard.py"
copy "$SELF/cli/dashboard.css" "$TARGET/cli/dashboard.css"   # shared stylesheet; the setup dashboard reuses it
say "the intake gate runs on every PR now (disclosure + DCO + one lane); the review pipeline dry-runs until a model is wired."
say "governance view:  python3 cli/dashboard.py --repo OWNER/REPO --out dashboard.html"
say "the dashboard is INTERNAL: serve it behind auth, never from a public URL (docs/guides/governance-dashboard.md)."

step "6. Lane labels"
if [ "$GOOSE" -eq 1 ]; then
  LABELS="govern operate know assure standard docs chore"   # operate taxonomy; matches --goose .asdd.yml lanes
else
  LABELS="feature fix docs chore"                            # conventional default; adapt to match .asdd.yml `lanes:`
fi
if command -v gh >/dev/null 2>&1; then
  for l in $LABELS; do
    if [ "$DRYRUN" -eq 1 ]; then say "would ensure label: $l"
    elif gh label create "$l" --force >/dev/null 2>&1; then say "label: $l"
    else say "label exists or skipped: $l"; fi
  done
else
  say "gh not found - create the lane labels manually:"
  for l in $LABELS; do echo "    gh label create \"$l\""; done
fi
say "adapt this set to your project if needed (keep 'exactly one per PR')."

step "7. Next steps (do these yourself)"
cat <<'NEXT'
  - The gates are installed (step 5): the intake gate is deterministic and runs first; the review
    pipeline runs in a labelled dry-run until you wire a model.
  - To wire a live model, set (Settings, Secrets and variables, Actions):
      ASDD_RUNTIME_TOKEN   your model API key            (secret)
      ASDD_MODEL_URL       the full .../v1/chat/completions URL, not the base   (variable)
      ASDD_MODEL           the model name                (variable)
  - Turn on branch protection: require the "ASDD intake" and "asdd/review" checks plus a Code Owner
    review, and block direct pushes.
  - Commit the scaffolded files on a branch and open a PR (signed off, one lane label) so the first
    change goes through the gate it just installed.
NEXT

if [ "$GOOSE" -eq 1 ]; then
  step "8. Goose operator kit (--goose)"
  # The deployment-run recipes (developer.yaml is an optional bring-your-own reference;
  # interaction-public.yaml is the execution-free variant for an untrusted public surface).
  for r in README.md test-author.yaml test-runner.yaml documentation.yaml interaction.yaml interaction-public.yaml developer.yaml setup.yaml; do
    copy "$SELF/recipes/$r" "$TARGET/recipes/$r"
  done
  # The kit map: what exists, where each agent runs, the invariants, the setup order. An
  # agent reads this to orient instead of reading the whole kit to work it out.
  copy "$SELF/asdd-kit.yml" "$TARGET/asdd-kit.yml"
  # The deterministic gates + the MCP extension (asdd-mcp.py shells out to these siblings) + the
  # operate-agent security guard (refuses a tool-using recipe on untrusted input).
  # The gates, the MCP extension, the operate-agent guard, and the roster resolver (the
  # operate runners call it to turn a role into its model, so it must ship with them).
  # audit.py ships so the OPERATE agents (test-author, test-runner, documentation, triage, spec) can
  # append audit records through the same helper the govern layer uses (STANDARD 1.3).
  # openspec-gate.py and its helper _openspec_locate.py travel with asdd-mcp.py: the MCP `openspec_gate`
  # tool shells to the sibling openspec-gate.py, which imports _openspec_locate.py. Copied unconditionally
  # (not gated on spec_tool) so a repo that flips to spec_tool: openspec after init already has the gate.
  # conventions-check.py travels for the same reason: the MCP `conventions_check` tool shells to it, and
  # the operate recipes call that tool to learn the HOST project's workflow before producing anything.
  for g in spec-check.py claim-check.py merge-eligibility.py openspec-gate.py _openspec_locate.py conventions-check.py audit.py operate-run.py asdd-mcp.py operate-guard.py run-agent.sh; do
    copy "$SELF/cli/$g" "$TARGET/cli/$g"
  done
  copy "$SELF/validation/audit-check.py" "$TARGET/validation/audit-check.py"
  # The operator-run agents (triage, support, contributor review, merge review) are fixed-prompt agents,
  # not recipes: cli/run-agent.sh drives them through the model on demand and records the action. Their
  # docs must travel to the runtime dir where run-agent reads them, alongside the review lenses.
  for a in triage.md support.md review-contributor.md review-merge.md; do
    copy "$SELF/.github/asdd/agents/$a" "$TARGET/.github/asdd/agents/$a"
  done
  # The operate-agent-in-CI templates: post-merge (trusted), advisory. documentation syncs the docs; the
  # test agent runs the suite for a post-merge regression check. Both refuse to run on untrusted pre-merge
  # input (operate-guard), so the tester never executes a stranger's code in CI.
  copy "$SELF/cli/templates/operate/asdd-docsync.yml" "$TARGET/.github/workflows/asdd-docsync.yml"
  copy "$SELF/cli/templates/operate/docsync.sh" "$TARGET/.github/asdd/operate/docsync.sh"
  copy "$SELF/cli/templates/operate/asdd-test.yml" "$TARGET/.github/workflows/asdd-test.yml"
  copy "$SELF/cli/templates/operate/test.sh" "$TARGET/.github/asdd/operate/test.sh"
  say "the developer is bring-your-own; the deployment runs test-author / test-runner / documentation / interaction (spec-driven OP)."
  say "guided setup:  goose run --recipe recipes/setup.yaml --model <your model>   (it reads asdd-kit.yml, the map)"
  say "the docsync + test workflows run the documentation and test agents post-merge (trusted); both dry-run until a model is wired."
  cat <<'GOOSE'
  - Install Goose and pick a model:  goose configure  (any provider Goose supports; provider-neutral).
  - Point each deployment recipe (test-author / test-runner / documentation / interaction) at a model; keep
    the test models distinct from whatever builds the code (developer != test_author, test_runner).
  - The recipes reach the deterministic gates through the MCP extension:
        extensions:
          - type: stdio
            name: asdd-gates
            cmd: python3
            args: ["cli/asdd-mcp.py"]
  - Fill each recipe's github / knowledge / tests / platform extensions.
GOOSE
fi

echo
echo "Done. Nothing was pushed or merged."
