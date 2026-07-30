## Why

The advisory PR review runs all five model lenses (code, security, spec, quality, impact) in a
**single** runtime call: `.github/asdd/run-review.sh` invokes the runtime adapter once, and the
adapter returns one `asdd/review/v0.1` JSON carrying every lens. That has two costs that grow with
the change:

- **One prompt, five concerns.** A single model divides its attention across five distinct review
  jobs in one pass. Each lens gets less focus than it would alone, and there is no way to give a
  high-stakes lens (security) a stronger model than the rest.
- **Serial latency.** The review is one round-trip whose wall-clock scales with the diff. On a large
  PR the reviewer is the slowest step in the gate, and the lenses cannot overlap because they share
  the call.

The lenses are independent by construction (a security finding does not depend on the quality
verdict), so they are a natural fan-out. Today the pipeline cannot exploit that.

## What Changes

Add an **opt-in** `review.lens_fanout` mode. Default behaviour is unchanged: one adapter call, all
lenses, cheapest path.

- **Concurrent per-lens dispatch.** With fanout on, `run-review.sh` dispatches each model lens as its
  own adapter call with a lens-specific prompt, and the calls run concurrently.
- **Same output schema.** The per-lens results merge back into one `asdd/review/v0.1` review JSON,
  identical in shape to the single-call output, so `set-status.sh` and the publish workflow need no
  change.
- **Per-lens model override.** A lens may run on its own model/provider through the existing per-role
  resolver convention, falling back to `models.reviewer` when unset (e.g. the security lens on a
  frontier model, the rest on the roster model).
- **Untouched safety.** The deterministic `security_scan.py` and `impact_scan.py` layers still run
  once over the merged review. The diff-size cap applies per call, and the upstream intake spend gate
  is unchanged. Because fanout multiplies the number of model calls, it is documented as the
  higher-spend option and stays off by default.

This trades cost for latency and per-lens focus, and lets an adopter who cares about review turnaround
(or wants a stronger model on one lens) opt in without changing the default one-call economics.

## Capabilities

### New Capabilities
- `review-lens-fanout`: an opt-in mode that dispatches the model review lenses as independent,
  concurrent runtime calls and merges their verdicts into the unchanged review schema, with optional
  per-lens model selection and preserved spend/diff-cap safety.

### Modified Capabilities
<!-- None: the single-call path and the review schema are unchanged; this adds an alternative mode. -->

## Impact

- `.github/asdd/run-review.sh` - config read, per-lens dispatch, concurrency, merge, fault isolation.
- `.github/asdd/runtime/openai-compat.sh` and `runtime/generic.sh` - accept an optional single-lens
  request (a lens id + its prompt) instead of always producing all five.
- `.asdd.yml` - `review.lens_fanout` flag and optional per-lens model/url/token override keys.
- Docs: `docs/guides/adopt-govern.md` (opt-in, higher spend, per-lens model) and a
  `docs/guides/troubleshooting.md` entry.
- Tests: `run-review` regression (fanout off = identical) plus a fanout case.
- No change to the `asdd/review/v0.1` schema, the deterministic security/impact layers, the intake
  spend gate, or the publish workflow.
