#!/usr/bin/env bash
# ASDD - intake gate. DETERMINISTIC, read-only, no model.
#
# A PR that does not (1) disclose authorship, (2) sign off every commit (DCO), and (3) carry exactly one
# lane tag fails intake. This runs in a read-only job: it only pattern-matches untrusted text as data
# (no prompt, no shell-exec), so it adds no write-scoped untrusted-input step. It filters non-conforming
# PRs without a maintainer having to read them.
#
# Usage: intake-check.sh <workdir> <out.json>
#   workdir holds: body.md (PR body, untrusted), commits.txt (NUL-delimited commit messages),
#                  labels.txt (one label per line), meta.env (pr_number, head_sha)
set -euo pipefail
WORKDIR="${1:?usage: intake-check.sh <workdir> <out.json>}"
OUT="${2:?usage: intake-check.sh <workdir> <out.json>}"
# shellcheck disable=SC1090
set -a; . "$WORKDIR/meta.env"; set +a

problems=()

# 1) Disclosure: the PR body must tick the human or agent/AI box.
disclosed=false
if grep -qiE '^[[:space:]]*-?[[:space:]]*\[[xX]\].*(human|agent|\bAI\b)' "$WORKDIR/body.md" 2>/dev/null; then
  disclosed=true
else
  problems+=("No authorship disclosure: tick the human or AI-agent box in the PR template (ASDD 1).")
fi

# 2) DCO: every commit in the range must be Signed-off-by.
total=0; signed=0
if [ -f "$WORKDIR/commits.txt" ]; then
  while IFS= read -r -d '' msg; do
    [ -n "${msg//[[:space:]]/}" ] || continue
    total=$((total+1))
    grep -qiE '^[[:space:]]*Signed-off-by:[[:space:]]+.+<.+@.+>' <<<"$msg" && signed=$((signed+1))
  done < "$WORKDIR/commits.txt"
fi
signed_off=false
if [ "$total" -gt 0 ] && [ "$signed" -eq "$total" ]; then
  signed_off=true
else
  problems+=("Missing DCO sign-off on $((total-signed))/$total commit(s): use 'git commit -s' (ASDD 6.1).")
fi

# 3) Lane tag: exactly one lane label must be present. The accepted set is read from .asdd.yml
#    (the `lanes:` list), so it is not hard-coded; it falls back to a neutral default. `chore` is the
#    trivial-change escape.
ASDD_CONFIG="${ASDD_CONFIG:-.asdd.yml}"
lanes_re="$(awk '
  /^lanes:/    { f=1; next }
  /^[A-Za-z]/  { f=0 }
  f && /^[[:space:]]*-/ {
    sub(/[[:space:]]*#.*$/, "")                     # strip an inline comment (a lane token has no #)
    gsub(/^[[:space:]]*-[[:space:]]*"?|"?[[:space:]]*$/, "")
    if ($0 != "") { printf "%s%s", sep, $0; sep="|" }
  }' "$ASDD_CONFIG" 2>/dev/null)"
[ -n "$lanes_re" ] || lanes_re='feature|fix|docs|chore'
lane_count=0
if [ -f "$WORKDIR/labels.txt" ]; then
  lane_count=$(grep -cE "^(${lanes_re})$" "$WORKDIR/labels.txt" || true)
fi
laned=false
if [ "$lane_count" -eq 1 ]; then
  laned=true
else
  problems+=("Lane tag: add exactly one of ${lanes_re//|/, } (found $lane_count). exactly one lane label is required (see .asdd.yml lanes / README Lanes).")
fi

# 4) Anti-flood: an author may not have too many PRs open at once. The workflow supplies the count and
#    the cap (network, read-only) via meta.env; this stays a pure numeric compare. Absent count or a
#    non-positive cap => skipped, so older callers and local runs are unaffected (${var:-} under set -u).
open_prs="${open_pr_count:-}"
cap="${max_open_prs:-0}"
flood_ok=true
if [ -n "$open_prs" ] && [ "$cap" -gt 0 ] && [ "$open_prs" -gt "$cap" ]; then
  flood_ok=false
  problems+=("Too many open PRs from this author ($open_prs, cap $cap). Land or close some before opening more (anti-flood, ASDD 3).")
fi

# 5) Spec-driven by default: a non-trivial PR (single lane, not `chore`) must be based on a spec - it
#    references an existing spec (a path in the body or a `Spec:` trailer) OR adds/edits one in its diff.
#    require_spec + the changed-file list arrive from the workflow; this stays a pure match. Disabled or
#    a chore lane => skipped, so trivial fixes and older callers are unaffected.
#
#    WHERE specs live is config-driven (`spec_paths:`), so a project points the gate at its own layout
#    instead of being forced onto ASDD's docs/specs. ASDD requires that a spec exists, not that a
#    particular tool produced it. $ASDD_CONFIG is the BASE checkout, so a PR cannot widen the gate it has
#    to pass by editing its own config.
spec_globs="$(awk '
  /^spec_paths:/ { f=1; next }
  /^[A-Za-z]/    { f=0 }
  f && /^[[:space:]]*-/ {
    sub(/[[:space:]]*#.*$/, "")                     # strip an inline comment (a path token has no #)
    gsub(/^[[:space:]]*-[[:space:]]*"?|"?[[:space:]]*$/, "")
    if ($0 != "") print
  }' "$ASDD_CONFIG" 2>/dev/null)"
# No explicit spec_paths => default by spec_tool. An OpenSpec project (`spec_tool: openspec`) keeps its
# specs as change deltas + living specs, so the gate targets that layout without the adopter hand-writing
# the globs. Explicit spec_paths always wins (the awk above already captured it). Anything else falls to
# ASDD's built-in docs/specs. The openspec preset points at the DELTAS (openspec/changes/*/specs/), which
# are what make a change a real spec - not a proposal filename (there is none in the scaffold; see the
# pinned contract in docs/specs/openspec-adoption.md).
if [ -z "$spec_globs" ]; then
  spec_tool="$(awk -F: '/^spec_tool:/ { gsub(/[[:space:]"]/, "", $2); print $2; exit }' \
                 "$ASDD_CONFIG" 2>/dev/null)"
  if [ "$spec_tool" = "openspec" ]; then
    spec_globs='openspec/changes/*/specs/**/*.md
openspec/specs/**/*.md'
  else
    spec_globs='docs/specs/*.md'
  fi
fi

# glob -> regex. A pattern is VALIDATED, not escaped: anything outside a plain path charset is dropped
# rather than regex-escaped, so a config cannot smuggle regex metacharacters (`.*`, alternation) into the
# matcher and turn the gate into a rubber stamp. `**` crosses path segments, `*` stays inside one.
spec_re=""
while IFS= read -r g; do
  [ -n "$g" ] || continue
  case "$g" in *..*) continue ;; esac
  [[ "$g" =~ ^[A-Za-z0-9._/*-]+$ ]] || continue
  r="${g//./\\.}"                    # literal dots stay literal
  r="${r//\*\*/[A-Za-z0-9._/-]+}"    # ** = any depth
  r="${r//\*/[A-Za-z0-9._-]+}"       # *  = one segment
  spec_re="${spec_re:+$spec_re|}$r"
done <<EOF
$spec_globs
EOF
# Every configured pattern was rejected => fall back to the default rather than to an empty regex, which
# would match everything and silently pass every PR.
[ -n "$spec_re" ] || spec_re='docs/specs/[A-Za-z0-9._-]+\.md'

spec_ok=true
is_chore=false
grep -qxE 'chore' "$WORKDIR/labels.txt" 2>/dev/null && is_chore=true
if [ "${require_spec:-false}" = "true" ] && [ "$laned" = "true" ] && [ "$is_chore" = "false" ]; then
  has_spec=false
  # (a) a spec ADDED, MODIFIED or RENAMED-to in THIS PR is a spec by definition. changed.txt is
  #     `git diff --name-status`, so a DELETED spec (status D) does not count (its path would otherwise
  #     match and let a spec-deleting PR pass). $NF is the (new) path; the status column is $1. The regex
  #     travels via the environment, not -v: awk processes escapes in a -v assignment, which would turn
  #     the `\.` into an any-character `.`.
  if [ -f "$WORKDIR/changed.txt" ] && SPEC_RE="^(${spec_re})$" awk -F'\t' \
      'BEGIN{re=ENVIRON["SPEC_RE"]} $1 ~ /^[AMR]/ && $NF ~ re {f=1} END{exit f?0:1}' \
      "$WORKDIR/changed.txt"; then
    has_spec=true
  fi
  # (b) a REFERENCED existing spec: the body must name a path that matches a configured pattern AND
  #     actually EXISTS in the tree (base checkout). A fabricated or misspelled path does not satisfy the
  #     gate. `..` is rejected outright, so a traversal reference like `docs/specs/../../README.md` cannot
  #     resolve an unrelated existing file into a "spec" - the segment charset alone would not stop that,
  #     because `..` is made of charset characters.
  if [ "$has_spec" = "false" ]; then
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      case "$ref" in *..*) continue ;; esac
      [[ "$ref" =~ ^(${spec_re})$ ]] || continue
      [ -f "$ref" ] && { has_spec=true; break; }
    done < <(grep -oE '[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+' "$WORKDIR/body.md" 2>/dev/null)
  fi
  if [ "$has_spec" = "false" ]; then
    spec_ok=false
    spec_hint="$(printf '%s' "$spec_globs" | paste -sd, - | sed 's/,/, /g')"
    problems+=("Not based on a spec (ASDD is spec-driven). Either reference an existing spec in the description or a 'Spec:' line, OR add one in this PR - problem, requirements, acceptance criteria - that this change implements. This project keeps specs at: ${spec_hint} (see .asdd.yml spec_paths). The review agent checks the change against it.")
  fi
fi

# 6) Declared conventions: hold the change to the docs/style conventions the project DECLARES in .asdd.yml
#    (the `conventions:` block). Deterministic, no model, no network: it shells to the same
#    cli/conventions-check.py the operate agents use, judging only the change. A project that declares no
#    block is a clean no-op, so this stays inert until a project opts in. Uses the BASE config
#    ($ASDD_CONFIG, the base checkout) like the spec gate, so a PR cannot loosen the conventions it must
#    meet by editing its own config. The detected lane selects lane-specific rules; changes.diff is the
#    change whose added-line style and doc-pairing are checked. Guards on both files so a local caller or
#    an older layout (no diff, no script) is unaffected.
conv_ok=true
conv_script="$(dirname "$0")/../../cli/conventions-check.py"
if [ -f "$conv_script" ] && [ -f "$WORKDIR/changes.diff" ]; then
  conv_lane=""
  [ "$laned" = "true" ] && conv_lane="$(grep -E "^(${lanes_re})$" "$WORKDIR/labels.txt" | head -1 || true)"
  set +e
  conv_out="$(python3 "$conv_script" --config "$ASDD_CONFIG" --diff "$WORKDIR/changes.diff" ${conv_lane:+--lane "$conv_lane"} 2>&1)"
  conv_rc=$?
  set -e
  if [ "$conv_rc" -eq 1 ]; then
    conv_ok=false
    while IFS= read -r cline; do
      [ -n "$cline" ] && problems+=("Convention: $cline")
    done <<CONV
$conv_out
CONV
  elif [ "$conv_rc" -eq 2 ]; then
    conv_ok=false
    problems+=("The conventions block in .asdd.yml is misconfigured (a malformed block, or a declared path that does not exist): ${conv_out}. Fix the block (see .asdd.yml conventions).")
  fi
fi

# Owner override: an owner's own PR carrying the `owner-override` label passes intake even with unmet
# requirements. The problems are RETAINED in the output (advisory, on the record) - the override stops
# intake blocking, it does not hide what was skipped. `override` comes from the workflow (meta.env).
overridden="${override:-false}"
if [ "$overridden" = "true" ] && [ "${#problems[@]}" -gt 0 ]; then
  problems+=("Owner override in effect: the above are advisory only for this PR (owner-override label).")
fi

# Emit intake JSON.
if [ "${#problems[@]}" -gt 0 ]; then
  probs_json="$(printf '%s\n' "${problems[@]}" | jq -R . | jq -s 'map(select(length>0))')"
else
  probs_json='[]'
fi
jq -n \
  --argjson pr "${pr_number}" --arg head "${head_sha}" \
  --argjson disc "$disclosed" --argjson sign "$signed_off" --argjson lane "$laned" \
  --argjson flood "$flood_ok" --argjson spec "$spec_ok" --argjson conv "$conv_ok" --argjson ovr "$overridden" --argjson probs "$probs_json" \
  '{schema:"asdd/intake/v0.1", pr_number:$pr, head_sha:$head,
    disclosed:$disc, signed_off:$sign, laned:$lane, flood_ok:$flood, spec_ok:$spec, conventions_ok:$conv, override:$ovr,
    passed:($ovr or ($disc and $sign and $lane and $flood and $spec and $conv)),
    problems:$probs}' > "$OUT"

echo "intake: disclosed=$disclosed signed_off=$signed_off ($signed/$total signed) laned=$laned flood_ok=$flood_ok spec_ok=$spec_ok conventions_ok=$conv_ok override=$overridden"
[ -s "$OUT" ] || { echo "intake-check: no output" >&2; exit 1; }
