#!/usr/bin/env bash
# ASDD - export the run's audit records to the adopter's own private sink.
#
# ASDD hosts nothing. Records are produced in the adopter's pipeline (read-only, into the run directory)
# and this step ships them to a sink the ADOPTER owns. It runs in the WRITE-SCOPED publish context and
# reads only ASDD-produced records, never untrusted pull-request content, so the sink credential is never
# present in a job that processes a fork's input. That is the same split as intake/publish.
#
# Two refusals are hard, because getting them wrong publishes the trail:
#   1. The sink must not be the repository being governed.
#   2. The sink must not be public.
# Either one fails loudly rather than exporting.
#
# Config (.asdd.yml, `audit:`):
#   sink: none | repo | command      (none = default, no-op: nothing is exported)
#   sink_repo: owner/name            (sink: repo - a PRIVATE sibling repository)
#   sink_command: "..."              (sink: command - bring your own; receives the ledger path as $1)
#
# Env: AUDIT_SINK_TOKEN (write credential for the sink), GITHUB_REPOSITORY (the governed repo).
# Usage: audit-export.sh <ledger.jsonl> [--check-only]
set -uo pipefail

LEDGER="${1:-}"
MODE="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ -n "$LEDGER" ] || { echo "audit-export: usage: audit-export.sh <ledger.jsonl> [--check-only]" >&2; exit 2; }

# Read a scalar nested one level under a top-level key, same text-scan approach as the rest of the kit.
yaml_in() {
  local key="$1" file="$ROOT/.asdd.yml"
  [ -f "$file" ] || { echo ""; return; }
  awk -v k="$key" '
    /^[A-Za-z]/ { inblk = ($0 ~ /^audit:/) }
    inblk && $0 ~ ("^[[:space:]]+" k ":") {
      line=$0; sub(/#.*/,"",line); sub(("^[[:space:]]+" k ":[[:space:]]*"),"",line)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",line); gsub(/^"|"$/,"",line); gsub(/^'"'"'|'"'"'$/,"",line)
      print line; exit }' "$file"
}

SINK="$(yaml_in sink)"; SINK="${SINK:-none}"
SINK_REPO="$(yaml_in sink_repo)"
SINK_CMD="$(yaml_in sink_command)"

# Inert by default: an adopter who has not opted in sees no change at all.
if [ "$SINK" = "none" ] || [ -z "$SINK" ]; then
  echo "audit-export: sink is 'none'; nothing exported (set audit.sink to enable)."
  exit 0
fi

if [ ! -s "$LEDGER" ]; then
  echo "audit-export: no records to export ($LEDGER absent or empty)."
  exit 0
fi

# --- the two hard refusals -------------------------------------------------
refuse() { echo "audit-export: REFUSING to export. $1" >&2; exit 1; }

if [ "$SINK" = "repo" ]; then
  [ -n "$SINK_REPO" ] || refuse "audit.sink is 'repo' but audit.sink_repo is not set."
  # 1. Never the governed repository: the ledger describes this repo and must not be published into it.
  if [ -n "${GITHUB_REPOSITORY:-}" ] && [ "$SINK_REPO" = "$GITHUB_REPOSITORY" ]; then
    refuse "audit.sink_repo ('$SINK_REPO') is the repository being governed. The ledger must live in a separate private repo."
  fi
  # 2. Never a public destination. Unknown visibility is treated as public (fail closed), because the
  #    cost of guessing wrong is publishing the trail.
  if [ "$MODE" != "--check-only" ]; then
    # Ask the GitHub API whether the sink is private. curl is universal; gh is not, and requiring it
    # blocked shipping on any machine without it. A bad or unscoped token returns no `private` field, so
    # visibility stays unknown and the export fails closed, which is the safe outcome. gh is still used
    # if present, as an equivalent path.
    vis="unknown"
    if [ -n "${AUDIT_SINK_TOKEN:-}" ]; then
      if command -v curl >/dev/null 2>&1; then
        vis="$(curl -fsS -H "Authorization: token $AUDIT_SINK_TOKEN" -H "Accept: application/vnd.github+json" \
                 "https://api.github.com/repos/$SINK_REPO" 2>/dev/null \
               | python3 -c "import sys,json;print(str(json.load(sys.stdin).get('private')).lower())" 2>/dev/null || echo unknown)"
      elif command -v gh >/dev/null 2>&1; then
        vis="$(GH_TOKEN="$AUDIT_SINK_TOKEN" gh api "repos/$SINK_REPO" --jq '.private' 2>/dev/null || echo unknown)"
      fi
    fi
    case "$vis" in
      true)  : ;;  # private, proceed
      false) refuse "audit.sink_repo ('$SINK_REPO') is PUBLIC. The ledger is as sensitive as the code it describes." ;;
      *)     refuse "could not verify that audit.sink_repo ('$SINK_REPO') is private (needs AUDIT_SINK_TOKEN with read access). Failing closed." ;;
    esac
  fi
fi

if [ "$MODE" = "--check-only" ]; then
  echo "audit-export: configuration check passed (sink=$SINK${SINK_REPO:+, repo=$SINK_REPO})."
  exit 0
fi

# --- integrity before shipping --------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/cli/audit.py" verify --ledger "$LEDGER" || \
    refuse "the ledger's hash chain does not verify; refusing to append a broken trail."
fi

COUNT="$(grep -c . "$LEDGER" 2>/dev/null || echo 0)"

case "$SINK" in
  repo)
    : "${AUDIT_SINK_TOKEN:?audit-export: AUDIT_SINK_TOKEN is required for sink 'repo'}"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    URL="https://x-access-token:${AUDIT_SINK_TOKEN}@github.com/${SINK_REPO}.git"
    # Clone, RE-ANCHOR the batch onto the sink's current tip, append, push. The per-run ledger is
    # genesis-rooted (each CI run starts from an empty local file), so appending it verbatim would leave a
    # genesis-rooted batch at every seam and the accumulated chain would break there, defeating the
    # tamper-evidence the ledger exists for. Grafting re-chains the batch onto the tip so the sink is one
    # continuous chain across runs and months.
    #
    # Concurrency: two runs racing both push, and the loser gets a non-fast-forward. On failure we
    # re-clone (picking up the winner's records), re-anchor onto the NEW tip, and push again. Re-anchoring
    # is what makes the retry correct rather than a blind replay.
    pushed=false
    for attempt in 1 2 3 4 5; do
      rm -rf "$WORK/sink"
      git clone --depth 1 --quiet "$URL" "$WORK/sink" 2>/dev/null \
        || refuse "could not clone the sink repo '$SINK_REPO' (check AUDIT_SINK_TOKEN and that it exists)."
      SINK_LEDGER="$WORK/sink/ledger"
      DEST="$SINK_LEDGER/$(date -u +%Y)/$(date -u +%m).jsonl"
      mkdir -p "$(dirname "$DEST")"
      TIP="$(python3 "$ROOT/cli/audit.py" tip --ledger "$SINK_LEDGER" 2>/dev/null)"; TIP="${TIP:-sha256:genesis}"
      if ! python3 "$ROOT/cli/audit.py" graft --from "$LEDGER" --onto "$TIP" >> "$DEST"; then
        refuse "could not graft the batch onto the sink tip."
      fi
      git -C "$WORK/sink" add -A
      git -C "$WORK/sink" -c user.name="asdd-audit" -c user.email="asdd-audit@users.noreply.github.com" \
        commit -q -m "audit: ${COUNT} record(s) from ${GITHUB_REPOSITORY:-unknown} run ${GITHUB_RUN_ID:-local}" \
        || { echo "audit-export: nothing new to commit."; exit 0; }
      if git -C "$WORK/sink" push -q origin HEAD 2>/dev/null; then pushed=true; break; fi
      echo "audit-export: push rejected (a concurrent run got there first); re-anchoring onto the new tip (attempt ${attempt})." >&2
      sleep "$(( attempt ))"
    done
    [ "$pushed" = "true" ] || refuse "push to '$SINK_REPO' failed after retries (persistent non-fast-forward)."
    echo "audit-export: appended ${COUNT} record(s) to ${SINK_REPO} as a continuous chain."
    ;;
  command)
    [ -n "$SINK_CMD" ] || refuse "audit.sink is 'command' but audit.sink_command is not set."
    # Bring-your-own sink. The command receives the ledger path; ASDD does not interpret its output.
    sh -c "$SINK_CMD" _ "$LEDGER" || refuse "the configured sink_command failed."
    echo "audit-export: handed ${COUNT} record(s) to the configured sink_command."
    ;;
  *)
    refuse "unknown audit.sink '$SINK' (expected none, repo, or command)."
    ;;
esac
