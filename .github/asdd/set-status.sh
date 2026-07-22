#!/usr/bin/env bash
# ASDD - set the merge-gating commit status for the review. Turns the security/quality verdict
# into a MECHANICAL gate: make `asdd/review` a required status check in branch protection and a
# security block or a request-changes recommendation blocks merge for everyone. Runs only in the
# write-scoped publish job. Never shell-execs model output. (Intake is its own separate check.)
#
# Usage: set-status.sh <review.json>
# Env: GH_TOKEN, REPO.
set -euo pipefail
REVIEW="${1:?usage: set-status.sh <review.json>}"
: "${GH_TOKEN:?}"; : "${REPO:?}"

SHA="$(jq -r '.head_sha' "$REVIEW")"
[[ "$SHA" =~ ^[0-9a-f]{7,40}$ ]] || { echo "set-status: invalid head_sha" >&2; exit 1; }

sec_block="$(jq -r '[(.lenses // [])[] | select(.lens=="security") | (.findings // [])[] | select(.severity=="block")] | length' "$REVIEW")"
rec="$(jq -r '.recommendation // "comment"' "$REVIEW")"

state="success"; desc="Advisory review complete; a human approves and merges."
if [ "${sec_block:-0}" -gt 0 ]; then
  state="failure"; desc="Security review raised a blocking finding; needs a human resolution."
elif [ "$rec" = "request-changes" ]; then
  state="failure"; desc="Review recommends changes."
fi

# Owner override: an owner's own PR carrying the `owner-override` label does not have its merge blocked
# by the review. The review still posts (post-review.sh); this only turns the gating status green, with a
# description naming the override so the bypass is on the record. Author + labels are read live; the
# owners list is the trusted base .asdd.yml (via the shared script). `|| echo false` keeps it inert
# before the script exists in base (self-heals after merge).
if [ "$state" = "failure" ]; then
  PR="$(jq -r '.pr_number' "$REVIEW")"
  if [[ "$PR" =~ ^[0-9]+$ ]]; then
    author="$(gh pr view "$PR" --repo "$REPO" --json author -q '.author.login' 2>/dev/null || echo '')"
    lf="$(mktemp)"; gh pr view "$PR" --repo "$REPO" --json labels -q '.labels[].name' > "$lf" 2>/dev/null || true
    # The publish job checks out the base repo (never PR head), so ./.asdd.yml here is the trusted base.
    ovr="$(bash "$(dirname "$0")/owner-override.sh" "$author" "$lf" .asdd.yml 2>/dev/null || echo false)"
    rm -f "$lf"
    if [ "$ovr" = "true" ]; then
      state="success"; desc="Owner override (${author}): merged past the advisory review on the owner's judgement."
    fi
  fi
fi
desc="${desc:0:140}"   # GitHub truncates status descriptions at 140 chars.

echo "set-status: $REPO@${SHA:0:12} context=asdd/review state=$state"
gh api "repos/${REPO}/statuses/${SHA}" \
  -f state="$state" -f context="asdd/review" -f description="$desc" >/dev/null
echo "set-status: done"
