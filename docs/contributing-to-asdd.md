# Contributing to ASDD (and how ASDD develops itself)

ASDD is developed under ASDD. This repo carries its own gates: the intake gate and the review pipeline
run on ASDD's own pull requests, the same way they would on any project that adopts it. That is the
dogfood, and it is the strongest claim the project can make. ASDD's own contributions are governed by
ASDD.

For the step-by-step submission mechanics, follow [CONTRIBUTING.md](https://github.com/OneHillAI/ASDD/blob/main/CONTRIBUTING.md). This page is the
model behind them.

## How a change lands

1. **You bring the developer.** The developer agent is always yours: connect your own coding agent (or
   write the change by hand) to build it. The deployment never runs a standing developer.
2. **You disclose and sign off.** Fill the disclosure block in the PR template; sign every commit
   (`git commit -s`); carry exactly one lane tag. The deterministic intake gate checks all three before
   anything else runs, and no model can talk it out of its verdict.
3. **The operate agents review.** The reviewer and tester (a model distinct from whatever wrote the
   change) run against the PR; the security and quality lenses run in the read-only analysis job; the
   publish job posts one advisory comment and sets `asdd/review`.
4. **A human merges.** Nothing merges automatically by default, and anything touching a protected path,
   including the standard and governance docs themselves, is human-approved permanently.

## Who can contribute

Anyone, through the same airlock any adopter uses. The spec-driven profile's two-tier identity means you
need a DCO-capable identity to *merge*, but any attributable identity to *propose* an idea, which the
interaction agent brings in as a validated spec.

## Running ASDD's own operate layer

The operate layer for developing ASDD is ASDD-with-Goose (or any conforming runtime) pointed at this
repo. Until a model is wired the review pipeline runs in dry-run; wiring a live model is a maintainer
action (a runtime token in repo secrets), exactly as it is for any adopter. See
[adopt-govern](guides/adopt-govern.md#wire-a-live-model-optional).

A maintainer's ASDD deployment is independent of any other. Running ASDD-with-Goose on this repo does not
conflict with a separate Goose deployment already governing another project (for example an adopter's own
instance): they are distinct deployments with their own repos and rosters, and a maintainer can reuse a
provider configuration across them or keep them separate. The framework is the shared part; the
deployment is not.


## The quality bar

Changes are held to [standards/de-slop.md](https://github.com/OneHillAI/ASDD/blob/main/standards/de-slop.md): match the surrounding style, delete
more than you add where you can, and expect the quality lens to argue against net-added complexity. CI
hard-fails on the banned fluff words. Docs changes carry the `chore` lane.
