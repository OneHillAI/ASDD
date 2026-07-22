#!/usr/bin/env bash
# Self-test for the advisory comment. The comment is a PUBLIC artefact on an open repository and its
# summary text is written by a model, so it must meet the project's writing standard. The docs lint only
# covers tracked files, never comments, so this is the only thing that catches it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/post-review.sh"
command -v jq >/dev/null 2>&1 || { echo "post-review self-test: SKIP (jq required)"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0

# Stub gh: capture the body that WOULD be posted instead of posting it.
cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  case "$prev" in -f) case "$a" in body=*) printf '%s' "${a#body=}" > "$CAPTURE";; esac;; esac
  prev="$a"
done
EOF
chmod +x "$TMP/gh"

# A review whose model-written summary carries an en dash and an em dash (built from escapes so this
# test file itself stays free of them).
python3 - "$TMP/review.json" <<'PY'
import json, sys
summary = ("Two findings \u2014 one blocking \u2013 see below.")
json.dump({"schema": "asdd/review/v0.1", "pr_number": 7, "head_sha": "abc1234", "mode": "live",
           "recommendation": "request-changes", "summary": summary,
           "lenses": [{"lens": "code", "verdict": "concerns",
                       "findings": [{"severity": "warn", "message": "naming \u2014 unclear", "path": "a.py:1"}]}]},
          open(sys.argv[1], "w"))
PY

CAPTURE="$TMP/body.txt" PATH="$TMP:$PATH" REPO="o/r" GH_TOKEN=x \
  bash "$SCRIPT" "$TMP/review.json" >/dev/null 2>&1

if [ ! -s "$TMP/body.txt" ]; then
  echo "FAIL: no comment body was produced"; fail=1
else
  if python3 -c 'import sys; sys.exit(0 if any(c in open(sys.argv[1],encoding="utf-8").read() for c in ("\u2013","\u2014")) else 1)' "$TMP/body.txt"; then
    echo "FAIL: an en or em dash reached the public comment"; fail=1
  else
    echo "ok: en and em dashes are normalised out of the public comment"
  fi
  grep -q 'one blocking' "$TMP/body.txt" && echo "ok: the summary text itself survives" \
    || { echo "FAIL: normalisation destroyed the summary"; fail=1; }
  grep -q 'naming' "$TMP/body.txt" && echo "ok: lens findings survive" \
    || { echo "FAIL: lens findings lost"; fail=1; }
fi

echo
[ "$fail" -eq 0 ] && echo "post-review self-test: PASS" || echo "post-review self-test: FAIL"
exit "$fail"
