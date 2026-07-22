## Why

Each ASDD agent works from a cold start. The review, test, and documentation agents see one diff and the
text handed to them, derive what they need, and discard it. Nothing accumulates, so a new adopter gets no
head start on their own codebase, quality cannot compound across runs, and there is nowhere to ground a
model in the project. There is a govern layer and an operate layer, but no know layer.

## What Changes

- On adoption, a bounded, cost-capped onboarding pass has the agents learn the codebase and seed a
  knowledge base.
- Every review, documentation, and test run emits provenance-tracked knowledge, and later runs read it as
  grounding, so quality compounds.
- The knowledge layer is pluggable: ASDD defines the contract and binds OKGF as the reference, hard-vendors
  neither it nor any store, and `knowledge.tool: none` keeps today's behaviour.
- An adopter may optionally train their own model on the corpus (bring-your-own, off by default). ASDD runs
  no training itself.
- Knowledge is advisory and privacy-bounded by `spec_context`; it never gates a merge.

## Impact

- Affected specs: knowledge
- Affected code (reference implementation): the runtime adapter seam (a knowledge binding beside the model
  runtime), the review/documentation/test agent prompts (emit and read), `.asdd.yml` (`knowledge:` block),
  the onboarding entrypoint, the insights activity log.
- Mirrors the builtin-format spec `docs/specs/codebase-learning-and-knowledge-base.md`.
