# Spec: robust review-JSON extraction from real model output

## Problem

The review runtime (`.github/asdd/runtime/generic.sh` via `openai-compat.sh`) asks the model for a bare
JSON object and then requires the raw response to parse as that object. A reasoning-capable model rarely
complies exactly: it returns a paragraph of analysis before the object, wraps the object in a
` ```json ` fence, or adds trailing commentary. That analysis usually contains its own braces (`def f()
{ ... }`, `{x: 1}`), so the previous "strip fences, else slice from the first `{` to the last `}`"
recovery captured a span that was not valid JSON. The adapter then treated a perfectly good review as
unparseable, retried, and finally fell back to a `live` placeholder: "The review runtime returned invalid
output; a human should review manually." The agent had reviewed; its verdict was thrown away.

Observed on this repo: the connected reviewer model (a reasoning model served over an OpenAI-compatible
endpoint) failed every attempt on both the main and adversarial passes, and the review degraded to the
placeholder even though the model, endpoint, key, and cost guard were all working.

## Requirements

1. The runtime MUST recover the model's review object when the response contains a valid JSON object,
   whether it is bare, fenced, preceded by reasoning prose, followed by commentary, or accompanied by
   unrelated braces in that prose.
2. The runtime MUST still emit nothing (fail closed to human review) when the response holds no decodable
   object, so the gate never sees a false pass.
3. Extraction MUST use a real JSON parser, not a brace count, so braces inside strings and nested objects
   are handled correctly.
4. When the model has multiple candidate objects, the runtime SHOULD prefer the one that looks like a
   review (has `schema`/`lenses`/`summary`/`recommendation`/`verdict`), then the largest.
5. The adapter MUST read the answer across the response shapes providers actually use: `content` as a
   string, `content` as an array of parts, a legacy top-level `text`, AND `message.reasoning_content`. A
   reasoning model often leaves `content` empty and emits the JSON inside `reasoning_content`, so the
   extractor is fed both and picks the object that most looks like a review.
6. On a persistent failure the adapter MUST log a key-safe, redacted diagnostic (HTTP status, response
   and content sizes, a short head/tail of the content) so the cause is distinguishable (missing key vs
   HTTP error vs empty content vs prose-with-no-JSON) without another blind run. The API key is only in
   the request header, never the response, so logging response content is key-safe.
7. No new runtime dependency: extraction runs on `python3` (already required by the review job) with the
   existing `jq`/`awk` path retained as a fallback when `python3` is absent.

## Acceptance criteria

- `.github/asdd/runtime/extract-json.test.sh` passes: bare, fenced, reasoning-prose-then-object, and
  prose-with-braces-then-object-then-trailing-text all recover the review object; a truncated object and
  prose-with-no-object are both rejected.
- The extractor is wired into `validation/run-base.py` and the base suite stays green.
- `generic.sh` is unchanged in contract: it still validates the merged object and fails closed to the
  human-review comment when extraction yields nothing.

## Scope

The fix is at the shared chokepoint (`openai-compat.sh`), so it covers every role that runs through the
OpenAI-compatible adapter: the review lenses AND the operator-run fixed-prompt agents that call it via
`cli/run-agent.sh` (triage, support, review-contributor, review-merge), which write the adapter's output
without re-parsing it. The Goose-run operate agents (documentation, test-author, test-runner, interaction)
are a separate path - Goose parses the model itself and the agent writes its result file - so they do not
depend on this extraction.
