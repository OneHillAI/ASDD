#!/usr/bin/env bash
# ASDD - resolve-model: what a role ACTUALLY runs on - its model, its endpoint, its key.
#
# The roster in .asdd.yml declares a model per role, but a runner has to turn the role
# ("documentation") into a concrete model, endpoint and credential at the moment it
# launches the agent. This is that lookup, in ONE place, so every run path resolves a
# role the same way and what you configured is what actually runs.
#
# Resolution, per role (ROLE upper-cased, e.g. documentation -> DOCUMENTATION):
#   model     models.<role> in the config      -> else $ASDD_MODEL
#   endpoint  $ASDD_MODEL_URL__<ROLE>          -> else $ASDD_MODEL_URL
#   key       $ASDD_RUNTIME_TOKEN__<ROLE>      -> else $ASDD_RUNTIME_TOKEN
#
# So one provider for every governance agent is the default (set the shared vars and
# nothing else), and a role that needs its own provider gets one by setting the
# per-role variables - e.g. the test roles on a cheap endpoint and the reviewer on a
# frontier model, each with its own key.
#
# CREDENTIALS: this NEVER prints a key. `--token-var` prints the NAME of the variable
# holding it, and the caller dereferences it, so a key cannot land in a log or a
# command line. Model names and endpoints are not secrets and are printed directly.
# Keys never belong in .asdd.yml: it is version-controlled.
#
# Usage: resolve-model.sh <role> [CONFIG] [--url | --token-var]
#   CONFIG defaults to .asdd.yml. Default output is the model name.
# Exit: 0 resolved, 1 nothing resolved for that role, 2 usage / config error.
set -euo pipefail

ROLE=""; CONFIG=""; WHAT="model"
while [ $# -gt 0 ]; do
  case "$1" in
    --url)       WHAT="url" ;;
    --token-var) WHAT="token-var" ;;
    -h|--help)   sed -n '2,27p' "$0"; exit 0 ;;
    -*)          echo "resolve-model: unknown option: $1" >&2; exit 2 ;;
    *)           if [ -z "$ROLE" ]; then ROLE="$1"; else CONFIG="$1"; fi ;;
  esac
  shift
done
[ -n "$ROLE" ] || { sed -n '2,27p' "$0"; exit 2; }
CONFIG="${CONFIG:-.asdd.yml}"

# documentation -> DOCUMENTATION, test_runner -> TEST_RUNNER (the per-role var suffix).
SUFFIX="$(printf '%s' "$ROLE" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_')"

# Read a key from the `models:` block: `  <key>: "value"` (comment + quotes stripped).
# Same reader as cli/check-models.sh, so the gate and the runner agree on the roster.
model_of() {
  [ -f "$CONFIG" ] || return 0
  awk -v k="$1" '
    /^models:/    { inblk=1; next }
    /^[A-Za-z]/   { inblk=0 }
    inblk {
      line=$0
      sub(/#.*/, "", line)
      if (line ~ ("^[[:space:]]+" k ":")) {
        sub(("^[[:space:]]+" k ":[[:space:]]*"), "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }' "$CONFIG"
}
strip() { local v="$1"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; printf '%s' "$v"; }

case "$WHAT" in
  model)
    MODEL="$(strip "$(model_of "$ROLE")")"
    [ -n "$MODEL" ] || MODEL="${ASDD_MODEL:-}"
    if [ -z "$MODEL" ]; then
      echo "resolve-model: no model for role '$ROLE' (set models.$ROLE in $CONFIG with \`asdd setup\`, or set ASDD_MODEL)." >&2
      exit 1
    fi
    printf '%s\n' "$MODEL"
    ;;
  url)
    # The per-role endpoint wins; the shared one is the fallback. Not a secret.
    var="ASDD_MODEL_URL__${SUFFIX}"
    URL="${!var:-}"
    [ -n "$URL" ] || URL="${ASDD_MODEL_URL:-}"
    if [ -z "$URL" ]; then
      echo "resolve-model: no endpoint for role '$ROLE' (set $var or ASDD_MODEL_URL)." >&2
      exit 1
    fi
    printf '%s\n' "$URL"
    ;;
  token-var)
    # Print the NAME of the variable holding the key, never the key itself. The caller
    # dereferences it (bash: "${!var}"), so the secret never reaches stdout or a log.
    var="ASDD_RUNTIME_TOKEN__${SUFFIX}"
    if [ -n "${!var:-}" ]; then
      printf '%s\n' "$var"
    else
      printf '%s\n' "ASDD_RUNTIME_TOKEN"
    fi
    ;;
esac
