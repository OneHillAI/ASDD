## ADDED Requirements

### Requirement: Opt-in concurrent lens dispatch
The review runner MUST support an opt-in mode in which each model review lens is dispatched as an
independent runtime call and those calls execute concurrently. The mode is off by default, and with it
off the review MUST make a single adapter call producing all lenses, byte-for-byte as before.

#### Scenario: Fanout disabled keeps the single-call path
- **WHEN** `review.lens_fanout` is unset or false
- **THEN** `run-review.sh` invokes the runtime adapter exactly once and the resulting review is
  identical to the current single-call behaviour

#### Scenario: Fanout enabled dispatches lenses concurrently
- **WHEN** `review.lens_fanout` is true and a runtime key is set
- **THEN** each model lens is dispatched as its own adapter call and the calls run concurrently rather
  than as one serial request

### Requirement: Verdicts merge into the unchanged review schema
The fanned-out lens results MUST merge into a single `asdd/review/v0.1` review JSON identical in shape
to the single-call output, so that `set-status.sh` and the publish workflow consume it without change.

#### Scenario: Merged review carries every lens and the strongest recommendation
- **WHEN** the concurrent lens calls complete
- **THEN** their findings merge into one `review.json` whose `lenses[]` array contains every lens
- **AND** the overall `recommendation` is the strongest across lenses, so a `block` from any single
  lens blocks the merged review

### Requirement: Deterministic layers run once over the merged review
The deterministic security scan and impact scan MUST run exactly once, over the merged review,
regardless of whether fanout is enabled. Fanout MUST NOT duplicate or skip either layer.

#### Scenario: Security and impact scans run once under fanout
- **WHEN** fanout is enabled and the per-lens calls have merged
- **THEN** `security_scan.py` and `impact_scan.py` each run exactly once against the merged
  `review.json`, exactly as in single-call mode

### Requirement: Per-lens model override
In fanout mode a lens MAY run on its own model and provider through the existing per-role resolver
convention, and MUST fall back to the `models.reviewer` roster model and the shared runtime endpoint
when no per-lens override is set.

#### Scenario: A lens with an override uses it
- **WHEN** a per-lens override for the security lens is set
- **THEN** the security lens call uses that model and provider while the other lenses use the reviewer
  roster model

#### Scenario: A lens without an override uses the reviewer roster model
- **WHEN** no override is set for a lens
- **THEN** that lens call uses `models.reviewer` and the shared runtime endpoint

### Requirement: Spend and diff-cap safety preserved
The diff-size cap and the intake spend gate MUST still hold in fanout mode. Because fanout multiplies
the number of model calls, the diff cap MUST apply per call and the mode MUST be documented as the
higher-spend option.

#### Scenario: An over-cap diff makes no lens call
- **WHEN** the diff exceeds `review.max_diff_lines`
- **THEN** no lens call is made and every lens is recorded as skipped, exactly as single-call mode
  refuses the model

#### Scenario: A failed intake still spends nothing
- **WHEN** intake did not conclude success
- **THEN** the review does not run and no lens call is made, because the upstream spend gate is
  unchanged by this feature

### Requirement: Fault isolation across lenses
A single lens call that fails or returns unparseable output MUST NOT fail the whole review. The failed
lens degrades to an error or skipped verdict and the remaining lenses still merge into a valid review.

#### Scenario: One failed lens does not abort the review
- **WHEN** one lens call errors or returns non-JSON output
- **THEN** that lens is recorded as errored or skipped in the merged review
- **AND** the remaining lenses' verdicts still produce a valid `asdd/review/v0.1` `review.json`
