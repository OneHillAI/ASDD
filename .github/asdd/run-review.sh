#!/usr/bin/env bash
# ASDD - runtime adapter entrypoint (the pluggable seam).
#
# Reads a work directory of UNTRUSTED PR data (title.txt, body.md, author.txt, changes.diff, meta.env)
# and writes a structured review JSON. Untrusted content is handed to the runtime as FILES; it is never
# interpolated into a prompt string here, and this script never executes runtime output as a command
# (the runtime returns JSON; we validate and pass it through). See the ASDD standards/security.md.
#
# Runtime selection: .asdd.yml -> `runtime:`. If .github/asdd/runtime/<name>.sh exists and
# a runtime credential is set, it is invoked to produce the review. Otherwise this falls back to a
# clearly labelled DRY-RUN so the pipeline can be watched before a model is wired.
#
# Usage: run-review.sh <workdir> <out.json>
set -euo pipefail

WORKDIR="${1:?usage: run-review.sh <workdir> <out.json>}"
OUT="${2:?usage: run-review.sh <workdir> <out.json>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # .github/asdd -> repo root

# Read a scalar nested one level under any top-level key (e.g. review.max_diff_lines). Same
# text-scan approach as the rest of the kit, so it needs no YAML dependency.
yaml_scalar_in() {
  local key="$1" file="$ROOT/.asdd.yml"
  [ -f "$file" ] || { echo ""; return; }
  awk -v k="$key" '
    /^[A-Za-z]/ { inblk = 1 }
    inblk && $0 ~ ("^[[:space:]]+" k ":") {
      line = $0; sub(/#.*/, "", line)
      sub(("^[[:space:]]+" k ":[[:space:]]*"), "", line)
      gsub(/[[:space:]]|"|'"'"'/, "", line)
      print line; exit
    }' "$file"
}

# Read a single top-level scalar from .asdd.yml without a YAML dependency.
yaml_scalar() {
  local key="$1" file="$ROOT/.asdd.yml"
  [ -f "$file" ] || { echo ""; return; }
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -n1 | sed 's/[[:space:]]*#.*$//; s/^["'\'']//; s/["'\'']$//'
}

# shellcheck disable=SC1090
set -a; . "$WORKDIR/meta.env"; set +a   # pr_number, base_sha, head_sha

RUNTIME="$(yaml_scalar runtime)"; RUNTIME="${RUNTIME:-generic}"
ADAPTER="$ROOT/.github/asdd/runtime/${RUNTIME}.sh"

# Resolve what the REVIEWER role actually runs on, through the same lookup every other role uses
# (cli/resolve-model.sh): models.reviewer in .asdd.yml decides the model, and the per-role env pair
# (ASDD_MODEL_URL__REVIEWER / ASDD_RUNTIME_TOKEN__REVIEWER) can point this role at its own provider.
# Without this the lenses would bypass the roster: models.reviewer would be declarative only.
#
# Every step is a fallback, never an override: if the resolver is absent, or a value does not resolve,
# the shared ASDD_* env stands exactly as before, so a single-provider deployment is unaffected.
# The KEY is never printed: --token-var yields the NAME of the variable holding it and we dereference
# that here, so the secret reaches the adapter as an env var, never stdout, a log or a command line.
RESOLVER="$ROOT/cli/resolve-model.sh"
if [ -f "$RESOLVER" ]; then
  if _m="$(bash "$RESOLVER" reviewer "$ROOT/.asdd.yml" 2>/dev/null)";           then export ASDD_MODEL="$_m"; fi
  if _u="$(bash "$RESOLVER" reviewer "$ROOT/.asdd.yml" --url 2>/dev/null)";     then export ASDD_MODEL_URL="$_u"; fi
  if _tv="$(bash "$RESOLVER" reviewer "$ROOT/.asdd.yml" --token-var 2>/dev/null)"; then
    if [ -n "${!_tv:-}" ]; then export ASDD_RUNTIME_TOKEN="${!_tv}"; fi
  fi
  unset _m _u _tv 2>/dev/null || true
fi

# Cost guard. The model call is the only step here that spends money, and once the repo is public
# anyone can open a pull request. An unbounded diff is therefore a denial-of-wallet vector: one
# enormous PR drains the budget. Above the cap we refuse the model and say so, rather than pay.
# The deterministic security layer below still runs, so the gate keeps biting either way.
CAP="$(yaml_scalar_in max_diff_lines)"; CAP="${CAP:-2000}"
# Per-call model timeout (seconds). review.timeout_seconds in .asdd.yml maps to ASDD_MODEL_TIMEOUT, which
# the OpenAI-compatible adapter enforces, so a slow reasoning reviewer fails fast with a named cause
# instead of hanging. Unset here leaves the adapter default. A caller's env ASDD_MODEL_TIMEOUT still wins.
if [ -z "${ASDD_MODEL_TIMEOUT:-}" ]; then
  _to="$(yaml_scalar_in timeout_seconds)"; [ -n "$_to" ] && export ASDD_MODEL_TIMEOUT="$_to"
fi
DIFF_LINES=$(wc -l < "$WORKDIR/changes.diff" 2>/dev/null | tr -d ' '); DIFF_LINES="${DIFF_LINES:-0}"
too_big=false
if [ "$CAP" -gt 0 ] 2>/dev/null && [ "$DIFF_LINES" -gt "$CAP" ]; then too_big=true; fi

if [ "$too_big" = "true" ]; then
  echo "asdd: diff is ${DIFF_LINES} lines, over the ${CAP}-line review cap; refusing the model call"
  cat > "$OUT" <<JSON
{
  "schema": "asdd/review/v0.1",
  "pr_number": ${pr_number},
  "head_sha": "${head_sha}",
  "mode": "skipped-too-large",
  "recommendation": "comment",
  "summary": "This change is ${DIFF_LINES} lines, over the ${CAP}-line review cap, so the model lenses did not run. That cap exists because a model call costs money and an unbounded diff would let one pull request drain the budget. Split it into reviewable pieces, or raise review.max_diff_lines if the project wants to pay for changes this size. The deterministic security checks below still ran.",
  "lenses": [
    {"lens": "code",     "verdict": "skipped", "findings": []},
    {"lens": "security", "verdict": "skipped", "findings": []},
    {"lens": "spec",     "verdict": "skipped", "findings": []},
    {"lens": "quality",  "verdict": "skipped", "findings": []},
    {"lens": "impact",   "verdict": "skipped", "findings": []}
  ],
  "stats": {"diff_added_lines": 0, "diff_removed_lines": 0, "diff_total_lines": ${DIFF_LINES}, "max_diff_lines": ${CAP}}
}
JSON
elif [ -n "${ASDD_RUNTIME_TOKEN:-}" ] && [ -x "$ADAPTER" ]; then
  echo "asdd: running '$RUNTIME' runtime adapter"
  ASDD_WORKDIR="$WORKDIR" ASDD_OUT="$OUT" ASDD_ROOT="$ROOT" bash "$ADAPTER"
else
  reason="dry-run"
  [ -z "${ASDD_RUNTIME_TOKEN:-}" ] && reason="no runtime key (set ASDD_RUNTIME_TOKEN, or ASDD_RUNTIME_TOKEN__REVIEWER for this role)"
  [ -x "$ADAPTER" ] || reason="$reason; no adapter at .github/asdd/runtime/${RUNTIME}.sh"
  echo "asdd: DRY-RUN ($reason)"
  # grep -c prints the count (0 on no match) and exits 1 when 0; `|| true` keeps that "0" without
  # `|| echo 0` appending a SECOND 0 (which produced malformed review JSON when a side had 0 lines).
  added="$(grep -c '^+' "$WORKDIR/changes.diff" 2>/dev/null || true)"; added="${added:-0}"
  removed="$(grep -c '^-' "$WORKDIR/changes.diff" 2>/dev/null || true)"; removed="${removed:-0}"
  cat > "$OUT" <<JSON
{
  "schema": "asdd/review/v0.1",
  "pr_number": ${pr_number},
  "head_sha": "${head_sha}",
  "mode": "dry-run",
  "recommendation": "comment",
  "summary": "Dry-run: the ASDD review pipeline ran but no agent runtime is wired ($reason). Diff stats only.",
  "lenses": [
    {"lens": "code",     "verdict": "skipped", "findings": []},
    {"lens": "security", "verdict": "skipped", "findings": []},
    {"lens": "spec",     "verdict": "skipped", "findings": []},
    {"lens": "quality",  "verdict": "skipped", "findings": []},
    {"lens": "impact",   "verdict": "skipped", "findings": []}
  ],
  "stats": {"diff_added_lines": ${added}, "diff_removed_lines": ${removed}}
}
JSON
fi

[ -s "$OUT" ] || { echo "asdd: ERROR runtime produced no review at $OUT" >&2; exit 1; }

# Security lens, layers 1+2: deterministic rules + SAST over the diff, merged into the `security` lens
# of $OUT. Runs regardless of whether a model runtime is wired (so the gate works even in dry-run), and
# is fail-safe (it never corrupts $OUT or breaks the pipeline). A `block` finding it adds is what
# set-status.sh turns into a failing asdd/review status. Reviewed code is data, never executed.
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/.github/asdd/security_scan.py" \
    --review "$OUT" --workdir "$WORKDIR" --head-ref refs/asdd-pr-head || \
    echo "asdd: security scan returned non-zero (ignored; gate degrades to model lens only)" >&2
else
  echo "asdd: python3 not available; skipping the deterministic/SAST security layers" >&2
fi

# Impact lens, deterministic layer: classify the change by its effect on the framework (normative text
# by path, and whether a normative PR carries its declaration, impact analysis, and target version).
# Runs regardless of whether a model runtime is wired, so the framework is protected in dry-run too. It
# reads the diff and body.md as data, never executes them, and is fail-safe (never corrupts $OUT). A
# `block` it merges sets recommendation=request-changes, which set-status.sh turns into a red
# asdd/review. The model `impact` lens (in the runtime) adds the behavioural case when wired.
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/.github/asdd/impact_scan.py" --review "$OUT" --workdir "$WORKDIR" || \
    echo "asdd: impact scan returned non-zero (ignored; classification degrades to model lens only)" >&2
else
  echo "asdd: python3 not available; skipping the deterministic impact layer" >&2
fi

# Audit ledger (STANDARD 1.3): one append-only record per lens outcome plus one for the overall review,
# written NEXT TO the review so it travels in the same artifact. This job is read-only and holds no sink
# credential: it only writes records to the run directory. The write-scoped publish job exports them to
# the adopter's private sink (.github/asdd/audit-export.sh). Fail-safe: never breaks the review.
LEDGER="$(dirname "$OUT")/audit.jsonl"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/cli/audit.py" from-review --review "$OUT" --workdir "$WORKDIR" --ledger "$LEDGER" || \
    echo "asdd: audit ledger emission returned non-zero (ignored; the review stands)" >&2
else
  echo "asdd: python3 not available; skipping the audit ledger" >&2
fi

echo "asdd: review written to $OUT"
