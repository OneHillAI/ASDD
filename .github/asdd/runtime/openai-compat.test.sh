#!/usr/bin/env bash
# Test: openai-compat.sh (1) normalizes a base ASDD_MODEL_URL to the full chat-completions endpoint,
# (2) tolerantly extracts a JSON object from prose/fenced output, (3) retries until a call parses, and
# (4) prints nothing when every attempt fails (so generic.sh fails closed). Stubs curl; no network.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/openai-compat.sh"
command -v jq >/dev/null 2>&1 || { echo "openai-compat.test.sh: SKIP (jq required)"; exit 0; }

STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

# curl stub. Behaviour is chosen by $MODE (via env), so one stub drives every case. It echoes a
# chat-completions envelope whose message.content is set per mode. For normalization it reports the URL
# it was asked to POST to, wrapped in valid JSON so tolerant extraction returns it.
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
url=""; for a in "$@"; do case "$a" in http*) url="$a";; esac; done
envelope() { printf '{"choices":[{"message":{"content":%s}}]}' "$(jq -Rs . <<<"$1")"; }
case "${MODE:-url}" in
  url)    envelope "{\"url\":\"$url\"}" ;;                              # valid JSON object naming the URL
  prose)  envelope 'Here is the review: {"schema":"asdd/review/v0.1","lenses":[]} thanks!' ;;
  fenced) printf '{"choices":[{"message":{"content":"```json\\n{\\"schema\\":\\"asdd/review/v0.1\\"}\\n```"}}]}' ;;
  bad)    envelope 'sorry, I cannot comply' ;;                         # never valid JSON
  flaky)  # garbage on the first call, a valid object afterwards (proves retry)
          n=$(cat "$COUNTER" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNTER"
          if [ "$n" -le 1 ]; then envelope 'nope'; else envelope '{"schema":"asdd/review/v0.1","lenses":[]}'; fi ;;
  rf)     # a provider that rejects response_format: the call carrying it yields no usable content, the
          # retry without it succeeds (proves the response_format fallback)
          has_rf=0; for a in "$@"; do case "$a" in *response_format*) has_rf=1;; esac; done
          if [ "$has_rf" = 1 ]; then printf '%s\n500' "$(envelope 'provider rejected response_format')"
          else printf '%s\n200' "$(envelope '{"schema":"asdd/review/v0.1","lenses":[]}')"; fi ;;
esac
EOF
chmod +x "$STUB/curl"

run() { PATH="$STUB:$PATH" ASDD_RUNTIME_TOKEN=x ASDD_MODEL=m ASDD_MODEL_RETRY_SLEEP=0 \
        ASDD_MODEL_URL="$1" bash "$SCRIPT" </dev/null 2>"$STUB/err"; }

# 1. base URL -> appended + a notice on stderr; output is the JSON object naming the full endpoint.
got="$(MODE=url run 'https://x.test/v1')"
[ "$(printf '%s' "$got" | jq -r .url)" = "https://x.test/v1/chat/completions" ] || fail "base URL not normalized (got '$got')"
grep -q 'not a chat-completions endpoint' "$STUB/err" || fail "no notice emitted for a base URL"

# base with trailing slash -> same
got="$(MODE=url run 'https://x.test/v1/')"
[ "$(printf '%s' "$got" | jq -r .url)" = "https://x.test/v1/chat/completions" ] || fail "trailing-slash base not normalized"

# already-full URL -> unchanged, no notice
got="$(MODE=url run 'https://x.test/v1/chat/completions')"
[ "$(printf '%s' "$got" | jq -r .url)" = "https://x.test/v1/chat/completions" ] || fail "full URL changed"
grep -q 'not a chat-completions endpoint' "$STUB/err" && fail "notice wrongly emitted for a full URL" || true

# 2. tolerant extraction: JSON wrapped in prose is sliced out and returned as a valid object.
got="$(MODE=prose run 'https://x.test/v1/chat/completions')"
[ "$(printf '%s' "$got" | jq -r .schema)" = "asdd/review/v0.1" ] || fail "prose-wrapped JSON not extracted (got '$got')"

# 3. tolerant extraction: a code-fenced object is unwrapped.
got="$(MODE=fenced run 'https://x.test/v1/chat/completions')"
[ "$(printf '%s' "$got" | jq -r .schema)" = "asdd/review/v0.1" ] || fail "fenced JSON not extracted (got '$got')"

# 4. retry: first call unparseable, second good -> a valid object comes back (one flaky call absorbed).
export COUNTER="$STUB/count"; : > "$COUNTER"
got="$(MODE=flaky ASDD_MODEL_RETRIES=3 PATH="$STUB:$PATH" ASDD_RUNTIME_TOKEN=x ASDD_MODEL=m \
      ASDD_MODEL_RETRY_SLEEP=0 ASDD_MODEL_URL='https://x.test/v1/chat/completions' bash "$SCRIPT" </dev/null 2>/dev/null)"
[ "$(printf '%s' "$got" | jq -r .schema)" = "asdd/review/v0.1" ] || fail "retry did not recover a valid review (got '$got')"
[ "$(cat "$COUNTER")" = "2" ] || fail "expected exactly 2 attempts, got $(cat "$COUNTER")"
unset COUNTER

# 5. all attempts unparseable -> empty output (generic.sh then fails closed). No false JSON invented.
got="$(MODE=bad ASDD_MODEL_RETRIES=2 PATH="$STUB:$PATH" ASDD_RUNTIME_TOKEN=x ASDD_MODEL=m \
      ASDD_MODEL_RETRY_SLEEP=0 ASDD_MODEL_URL='https://x.test/v1/chat/completions' bash "$SCRIPT" </dev/null 2>/dev/null)"
[ -z "$got" ] || fail "all-bad responses should yield empty output, got '$got'"

# 6. response_format fallback: a provider that 500s on response_format still gets a review, because the
#    retry drops the parameter and the prompt + extractor carry it.
got="$(MODE=rf ASDD_MODEL_RETRIES=3 PATH="$STUB:$PATH" ASDD_RUNTIME_TOKEN=x ASDD_MODEL=m \
      ASDD_MODEL_RETRY_SLEEP=0 ASDD_MODEL_URL='https://x.test/v1/chat/completions' bash "$SCRIPT" </dev/null 2>"$STUB/err")"
[ "$(printf '%s' "$got" | jq -r .schema)" = "asdd/review/v0.1" ] || fail "response_format fallback did not recover a review (got '$got')"
grep -q 'retrying without response_format' "$STUB/err" || fail "fallback did not drop response_format on the retry"

echo "openai-compat.test.sh: PASS"
