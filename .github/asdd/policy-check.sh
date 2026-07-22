#!/usr/bin/env bash
# ASDD - policy decision point (PDP).
#
# Authorizes a single agent ACTION before it executes. Fails closed: an action not on the allow-list, or
# one that violates the merge ban or the rate limit, is refused with a non-zero exit. Every decision is
# logged to stdout (the workflow log is the audit trail).
#
# Usage: policy-check.sh <action> <review.json>
set -euo pipefail

ACTION="${1:?usage: policy-check.sh <action> <review.json>}"
REVIEW="${2:?usage: policy-check.sh <action> <review.json>}"
PHASE="${ASDD_PHASE:-advisory}"

# Fixed allow-list of high-level actions an agent may take. NOT shell commands.
ALLOWED="comment label request-changes welcome triage-label set-status"
# Actions an agent may NEVER take. Merge is human-only.
DENIED_ALWAYS="merge push force-push close-without-comment delete-branch edit-protected"

MAX_ACTIONS_PER_RUN="${ASDD_MAX_ACTIONS:-5}"

deny() { echo "PDP DENY action=$ACTION phase=$PHASE reason=$1"; exit 1; }
allow() { echo "PDP ALLOW action=$ACTION phase=$PHASE"; exit 0; }

case " $DENIED_ALWAYS " in *" $ACTION "*) deny "action is permanently denied for agents" ;; esac

case " $ALLOWED " in
  *" $ACTION "*) : ;;
  *) deny "action not on the allow-list" ;;
esac

[ -s "$REVIEW" ] || deny "review artifact missing/empty"
# Fail CLOSED if jq is unavailable: without it the PDP cannot validate the artifact's schema or
# enforce the rate limit, so authorizing the action would be trusting an unchecked artifact.
command -v jq >/dev/null 2>&1 || deny "jq unavailable: cannot validate the review artifact"
jq -e '.schema and .pr_number' "$REVIEW" >/dev/null 2>&1 || deny "review artifact failed schema sanity check"
n="$(jq -r '([.recommendation] + ((.lenses // []) | map(select(.verdict=="request-changes")))) | length' "$REVIEW" 2>/dev/null || echo 1)"
[ "${n:-1}" -le "$MAX_ACTIONS_PER_RUN" ] || deny "rate limit: $n actions > $MAX_ACTIONS_PER_RUN per run"

allow
