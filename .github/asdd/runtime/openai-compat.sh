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

# Print a valid JSON OBJECT found in the model's text, or nothing (exit 1). A reasoning model wraps the
# object in analysis prose (which has its own braces), fences it, or trails commentary, so a first-{-to-
# last-} slice grabs an invalid span and a good review is lost. extract-json.py is a real parser: it
# sweeps every '{', lets the JSON decoder consume the largest balanced object there, and returns the one
# that most looks like a review. It only ever emits real JSON, so the gate still fails closed on genuine
# non-JSON. The jq path is a dependency-free fallback for the rare runner without python3.
HERE="$(cd "$(dirname "$0")" && pwd)"
extract_json() {
  local raw="$1" stripped sliced
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$raw" | python3 "$HERE/extract-json.py" && return 0 || return 1
  fi
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
  http=""
  resp="$(curl -sS --max-time 180 -w '\n%{http_code}' -X POST "$endpoint" \
    -H "Authorization: Bearer $ASDD_RUNTIME_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"
  http="${resp##*$'\n'}"; resp="${resp%$'\n'*}"   # split the trailing status line off the body
  # Pull the answer across the shapes providers actually use: content as a string, content as an array of
  # parts (concatenate .text), or a legacy .text field; THEN append message.reasoning_content. A reasoning
  # model (e.g. GLM served over an OpenAI-compatible endpoint) commonly leaves message.content empty and
  # emits the JSON inside reasoning_content, or reasons first and answers second. Feeding both to the
  # extractor lets it recover the review object wherever the model put it; extract-json.py prefers the
  # object that most looks like a review, so the real answer wins over any draft in the reasoning.
  content="$(printf '%s' "$resp" | jq -r '
    ((.choices[0].message.content) as $c
     | if ($c|type)=="string" then $c
       elif ($c|type)=="array" then ([$c[]? | (.text // .content // "")] | join(""))
       else (.choices[0].text // "") end) as $main
    | (($main // "") + "\n" + (.choices[0].message.reasoning_content // "")) // empty' 2>/dev/null || true)"
  if cand="$(extract_json "$content")"; then
    result="$cand"; break
  fi
  if [ "$i" -lt "$attempts" ]; then
    echo "openai-compat: attempt $i returned unparseable output; retrying" >&2
    sleep "$nap" 2>/dev/null || true
  fi
done

# One valid JSON object, or empty. Empty makes generic.sh fail closed to a human-review comment.
if [ -z "$result" ]; then
  # Redacted diagnostic so a persistent failure is never blind. The API key lives only in the request
  # header, never the response, so logging response/content sizes and a short head/tail is key-safe; the
  # body is a review of already-public PR content. This is the difference between "no runtime key" (env),
  # an HTTP error (endpoint/model/quota), empty content (wrong response shape), and prose-with-no-JSON.
  clen=${#content}; rlen=${#resp}
  head_snip="$(printf '%s' "$content" | tr '\n' ' ' | cut -c1-200)"
  tail_snip="$(printf '%s' "$content" | tr '\n' ' ' | rev | cut -c1-120 | rev)"
  {
    echo "openai-compat: all $attempts attempt(s) failed to yield JSON."
    echo "  last HTTP status: ${http:-unknown}; response bytes: ${rlen}; extracted-content chars: ${clen}"
    echo "  content head: ${head_snip}"
    echo "  content tail: ${tail_snip}"
    [ "$clen" -eq 0 ] && echo "  (content was empty across message.content, content parts, .text, and reasoning_content: check the endpoint returns OpenAI-shaped choices, the model name, and quota.)"
  } >&2
fi
printf '%s' "$result"
