#!/usr/bin/env bash
# ASDD - owner review override. DETERMINISTIC, read-only, no model, no network.
#
# Prints "true" iff a PR is owner-overridden: its AUTHOR is one of `review_override_owners` in the
# (trusted, base) .asdd.yml AND the `owner-override` label is present. Author-binding is the security -
# a label alone never bypasses (anyone with triage can label), and the override only frees the owner's
# OWN PRs. Both intake and the review status call this so they agree. Empty owners list => never.
#
# Usage: owner-override.sh <author-login> <labels-file> <trusted-config>
#   labels-file: one label per line. trusted-config: a config path the CALLER guarantees is from the
#   trusted base (never a PR-controlled working tree) - the security boundary is enforced there, not by
#   this script's CWD. The intake workflow passes `git show <base-sha>:.asdd.yml`; the publish job passes
#   its base-only checkout. Owners are read ONLY from this file, so a PR cannot self-authorize.
set -euo pipefail

AUTHOR="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
LABELS_FILE="${2:-}"
CONFIG="${3:?usage: owner-override.sh <author> <labels-file> <trusted-config>}"

# No author, missing/unreadable inputs, or the override label absent -> not overridden.
[ -n "$AUTHOR" ] || { echo "false"; exit 0; }
[ -f "$CONFIG" ] || { echo "false"; exit 0; }
[ -f "$LABELS_FILE" ] && grep -qxF "owner-override" "$LABELS_FILE" || { echo "false"; exit 0; }

# Extract the `- item` lines under `review_override_owners:` up to the next top-level key, strip the
# list marker and quotes (but never internal hyphens - logins may contain them), and match the author.
if awk -v a="$AUTHOR" '
    /^review_override_owners:/ {f=1; next}
    f && /^[^[:space:]#-]/ {f=0}
    f {
      line=$0
      sub(/#.*$/, "", line)
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      gsub(/["'"'"' ]/, "", line)   # drop double/single quotes and spaces, keep hyphens
      if (line != "" && tolower(line) == a) { print "hit"; exit }
    }
  ' "$CONFIG" 2>/dev/null | grep -q hit; then
  echo "true"
else
  echo "false"
fi
