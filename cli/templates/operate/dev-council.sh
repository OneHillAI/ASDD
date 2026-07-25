#!/usr/bin/env bash
# ASDD - developer council runner (operate). The concrete, no-plumbing way an adopter invokes the OPTIONAL
# multi-model produce-loop developer (cli/dev-council.py): 2 to 5 diverse models propose an implementation
# of an OpenSpec change, cross-critique against its acceptance criteria, a lead synthesises one result, and
# the test agents verify it. Runs in the operator's OWN produce session, so the input (the operator's own
# OpenSpec change) is trusted; it records the council's process to the ledger like every other agent.
#
# Wire the models the same way as the rest of the fleet: a shared ASDD_MODEL_URL + ASDD_RUNTIME_TOKEN with
# the model NAMES in dev_council.models, or the per-member ASDD_MODEL_URL__COUNCIL_<i> /
# ASDD_RUNTIME_TOKEN__COUNCIL_<i>. Not wired => a labelled dry run (the prompts still assemble).
#
# Usage: dev-council.sh <openspec-change-id> [extra dev-council args, e.g. --transcript FILE --test-cmd CMD]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"   # .github/asdd/operate/ -> repo root
CHANGE="${1:-}"
[ -n "$CHANGE" ] || { echo "usage: dev-council.sh <openspec-change-id> [args...]" >&2; exit 2; }
shift || true
python3 "$ROOT/cli/dev-council.py" --change "$CHANGE" --root "$ROOT" "$@"
rc=$?
# The council records its trail (dev-council.py: role developer, action dev-council.*). Ship it to the
# adopter's sink if one is wired, like every other agent - host-run, trusted context, so holding the sink
# credential here is safe (audit-export no-ops on sink:none and refuses a public or same-repo sink). Same
# ledger expression the council writes to, and the council's own exit code is preserved.
LEDGER="${ASDD_ACTIVITY_LOG:-.asdd-work/audit.jsonl}"
[ -n "${AUDIT_SINK_TOKEN:-}" ] && [ -x "$ROOT/.github/asdd/audit-export.sh" ] \
  && bash "$ROOT/.github/asdd/audit-export.sh" "$LEDGER" >/dev/null 2>&1 || true
exit "$rc"
