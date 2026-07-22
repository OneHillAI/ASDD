#!/usr/bin/env bash
# ASDD operate - documentation agent runner (post-merge doc sync). TEMPLATE.
#
# Installed into an adopter's .github/asdd/operate/ by `cli/init.sh --goose`. Runs the documentation
# agent (Goose, on the roster's model) against a MERGED change and writes its proposed doc updates to
# $OUT. It runs on TRUSTED input (a human already merged the change), so unlike the reviewer it is safe
# to give the agent a shell. It still opens no PR and writes no code: the workflow posts its output for a
# human. If the model is not wired or Goose is absent, it writes a dry-run preview.
#
# Usage: docsync.sh <change_ref> <out_file>
# Env (same as the review gate): ASDD_RUNTIME_TOKEN, ASDD_MODEL_URL (full chat-completions URL), and
# optionally the per-role overrides ASDD_RUNTIME_TOKEN__DOCUMENTATION / ASDD_MODEL_URL__DOCUMENTATION
# so this role can run on its own provider. The MODEL comes from the roster (models.documentation),
# resolved via cli/resolve-model.sh. Keys stay in the environment; .asdd.yml holds names only.
set -euo pipefail

CHANGE_REF="${1:?docsync: change_ref required}"
OUT="${2:?docsync: out file required}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RECIPE="$REPO_ROOT/recipes/documentation.yaml"

# Enforce the operate-agent security classification. This runner is post-merge (trusted), but assert it
# so the rule is mechanical: a tool-using recipe is refused on untrusted input (see cli/operate-guard.py).
python3 "$REPO_ROOT/cli/operate-guard.py" "$RECIPE" --input trusted \
  || { echo "docsync: operate-guard refused this run" >&2; exit 1; }

dryrun() {
  {
    echo "## Documentation agent - dry run"
    echo
    echo "$1"
    echo
    echo "It would run the documentation agent against \`${CHANGE_REF}\` and propose the doc, impact-log,"
    echo "changelog, and knowledge-base updates the change needs. Wire the model to activate it:"
    echo "set the repo \`ASDD_MODEL_URL\` variable and the \`ASDD_RUNTIME_TOKEN\` secret (the same config"
    echo "the review gate uses), and give this role a model with \`asdd setup --set documentation=<model>\`"
    echo "(or set the \`ASDD_MODEL\` variable as the fallback for every role)."
  } > "$OUT"
}

# What this role runs on: its model from the ROSTER (models.documentation), and its endpoint
# and key from the per-role variables if set, else the shared ones. So one provider for every
# agent is the default, and this role can have its own without touching the others.
RESOLVE="$REPO_ROOT/cli/resolve-model.sh"
MODEL="$("$RESOLVE" documentation "$REPO_ROOT/.asdd.yml" 2>/dev/null || true)"
MODEL_URL="$("$RESOLVE" documentation "$REPO_ROOT/.asdd.yml" --url 2>/dev/null || true)"
# The resolver returns the NAME of the variable holding the key, never the key, so the secret
# never reaches a log or a command line. Dereference it here.
TOKEN_VAR="$("$RESOLVE" documentation "$REPO_ROOT/.asdd.yml" --token-var 2>/dev/null || true)"
TOKEN="${!TOKEN_VAR:-}"

# Not wired -> dry run (same fail-soft posture as the review gate's template).
if [ -z "$TOKEN" ] || [ -z "$MODEL_URL" ] || [ -z "$MODEL" ]; then
  dryrun "The model runtime is not wired (need an endpoint + key from ASDD_MODEL_URL / ASDD_RUNTIME_TOKEN or their __DOCUMENTATION variants, and a model from models.documentation or ASDD_MODEL)."
  exit 0
fi
if ! command -v goose >/dev/null 2>&1; then
  dryrun "Goose is not installed on the runner."
  exit 0
fi

# Live: point Goose's built-in openai provider at the OpenAI-compatible endpoint via env, derived from
# the endpoint this role resolved to. Each `goose run` is its own process, so a per-role key and
# endpoint stay scoped to this run and cannot leak into another agent's.
rest="${MODEL_URL#*://}"
export OPENAI_API_KEY="$TOKEN"
export OPENAI_HOST="${MODEL_URL%%://*}://${rest%%/*}"
export OPENAI_BASE_PATH="${rest#*/}"

report="$(goose run --recipe "$RECIPE" --provider openai --model "$MODEL" \
  --params instructed_by=asdd-docsync --params change_ref="$CHANGE_REF" 2>&1 || true)"

# Keep only the agent's proposal section if it emitted one; otherwise pass the run through as-is.
if printf '%s' "$report" | grep -q '## Proposed doc updates'; then
  printf '## Documentation agent - proposed doc updates for `%s`\n\n' "$CHANGE_REF" > "$OUT"
  printf '%s\n' "$report" | sed -n '/## Proposed doc updates/,$p' >> "$OUT"
else
  dryrun "The documentation agent did not return a proposal (runtime error or empty output); a human should sync the docs."
fi
