#!/usr/bin/env bash
# ASDD - OpenAI-compatible model command. Reads a prompt on stdin, calls a chat-completions
# endpoint, and prints the model's review JSON on stdout. Used by runtime/generic.sh.
#
# Config (env): ASDD_RUNTIME_TOKEN (the API key, the repo secret), ASDD_MODEL_URL (the full
# chat-completions URL, e.g. https://<provider>/v1/chat/completions), ASDD_MODEL (the model name).
# Optional: ASDD_MODEL_RETRIES (default 3), ASDD_MODEL_RETRY_SLEEP seconds between tries (default 1).
# This holds NO GitHub write scope. It prints data; it never executes anything.
#
# Robustness: a model that honours response_format:json_object only intermittently can return
# prose-wrapped, fenced, or truncated output on any single call. So one flaky response does not drop the
# whole model review, this (1) sends an explicit system instruction to emit JSON only, (2) tolerantly
# extracts the JSON object from a response with surrounding prose or code fences, and (3) retries until
# it gets a valid JSON object. It prints one valid JSON object, or nothing if every attempt failed, in
# which case generic.sh fails closed to a human-review comment (the gate never sees a false pass).
set -euo pipefail

: "${ASDD_RUNTIME_TOKEN:?openai-compat: ASDD_RUNTIME_TOKEN (API key) not set}"
: "${ASDD_MODEL_URL:?openai-compat: ASDD_MODEL_URL not set}"
: "${ASDD_MODEL:?openai-compat: ASDD_MODEL not set}"

prompt="$(cat)"

# Normalize the endpoint. The classic misconfiguration is setting ASDD_MODEL_URL to the base
# (e.g. https://provider/v1) instead of the full chat-completions URL. We POST to it verbatim, so a
# base URL returns a non-review body and the gate fails closed with no surfaced cause. Append the path
# and say we did it, rather than fail silently.
endpoint="${ASDD_MODEL_URL%/}"
case "$endpoint" in
  */chat/completions) ;;
  *) echo "openai-compat: ASDD_MODEL_URL ('$ASDD_MODEL_URL') is not a chat-completions endpoint; using '$endpoint/chat/completions'. Set the full URL to silence this notice." >&2
     endpoint="$endpoint/chat/completions" ;;
esac

# An explicit system instruction. response_format:json_object is sent too, but some providers honour it
# unevenly; the instruction is a second, stronger nudge to return only the object.
sys="You are a JSON API. Return ONLY a single JSON object that satisfies the schema described in the user message. No prose, no explanation, no markdown, and no code fences."

# Print a valid JSON OBJECT found in the model's text, or nothing (exit 1). First try the text as-is with
# code fences stripped; if that is not an object, slice from the first { to the last } and try that (a
# model sometimes wraps the JSON in a sentence). Validation is jq's, so only real JSON is ever emitted.
extract_json() {
  local raw="$1" stripped sliced
  stripped="$(printf '%s' "$raw" | sed -e 's/^```json[[:space:]]*//' -e 's/^```[[:space:]]*//' -e 's/[[:space:]]*```$//')"
  if printf '%s' "$stripped" | jq -e 'type=="object"' >/dev/null 2>&1; then
    printf '%s' "$stripped"; return 0
  fi
  sliced="$(printf '%s' "$stripped" | awk '{b=b $0 ORS} END{
      f=index(b,"{"); if(!f) exit;
      l=0; for(i=length(b); i>0; i--) if(substr(b,i,1)=="}"){ l=i; break }
      if(l>f) printf "%s", substr(b, f, l-f+1) }')"
  if [ -n "$sliced" ] && printf '%s' "$sliced" | jq -e 'type=="object"' >/dev/null 2>&1; then
    printf '%s' "$sliced"; return 0
  fi
  return 1
}

payload="$(jq -n --arg m "$ASDD_MODEL" --arg s "$sys" --arg p "$prompt" \
  '{model:$m, temperature:0,
    messages:[{role:"system", content:$s},{role:"user", content:$p}],
    response_format:{type:"json_object"}}')"

attempts="${ASDD_MODEL_RETRIES:-3}"
case "$attempts" in ''|*[!0-9]*) attempts=3 ;; esac
[ "$attempts" -ge 1 ] || attempts=1
nap="${ASDD_MODEL_RETRY_SLEEP:-1}"

result=""
for i in $(seq 1 "$attempts"); do
  resp="$(curl -sS --max-time 180 -X POST "$endpoint" \
    -H "Authorization: Bearer $ASDD_RUNTIME_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"
  content="$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)"
  if cand="$(extract_json "$content")"; then
    result="$cand"; break
  fi
  if [ "$i" -lt "$attempts" ]; then
    echo "openai-compat: attempt $i returned unparseable output; retrying" >&2
    sleep "$nap" 2>/dev/null || true
  fi
done

# One valid JSON object, or empty. Empty makes generic.sh fail closed to a human-review comment.
printf '%s' "$result"
