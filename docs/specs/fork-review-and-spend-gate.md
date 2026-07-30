# Spec: fork PRs get real review, and a failed intake spends nothing

Lane: fix. Rewire the review trigger so the pipeline is correct for fork PRs and cheap for failing ones.

## Outcomes
- A **fork PR** gets the same real model review as a same-repo PR, instead of a silent dry-run.
- The **model call** (the only step that costs money) runs only after the deterministic intake gate has
  passed. A PR that fails intake (no disclosure, no DCO, no spec) spends nothing on a model.
- The change preserves the existing security invariant and adds no new way for untrusted input to reach
  a write-scoped action.

## Scope

In:
- `pr-review.yml` triggers on `workflow_run` of "ASDD intake" (types: completed), not on `pull_request`.
  It runs only when intake concluded success (`if: workflow_run.conclusion == 'success'`), with a
  belt-and-braces guard that reads the intake verdict from the artifact and no-ops if it is absent
  (draft/skip) or not passing.
- `asdd-intake.yml` produces the full PR data the review needs (title, body, author, the unified diff)
  plus the intake verdict, and uploads it as the `asdd-intake` artifact.
- The review job consumes that artifact as data and fetches the head ref only for SAST file reads
  (`git show`); it never checks out or executes fork code.
- Docs: the README pipeline description and `standards/security.md` (the "why the split" model and the
  hardening checklist) updated to the three-stage chain.

Out:
- NOT folding the publish job into the review workflow. The chain stays three separate workflows
  (intake -> review -> publish), which is exactly at GitHub's documented three-level `workflow_run`
  ceiling. Folding to two levels is a possible future hardening if the chain proves flaky; it is a
  bigger change and is deliberately deferred.
- NOT changing the review lenses, the runtime adapter, or the publish workflow.
- NOT using `pull_request_target` (the token-leak hole).

## Constraints
- Security invariant preserved: the analysis job holds the runtime credential but **no write scope** and
  **never executes fork code** (base context is safe only under both conditions); the publish job holds
  write scope but no secrets and reads only `review.json`. See `standards/security.md`.
- The spend gate rests on intake's verdict step exiting non-zero when the gate fails, so the intake
  workflow concludes failure and `workflow_run.conclusion == 'success'` is false. This behaviour must
  not regress.
- Config (`spec_paths`, `require_spec`, etc.) is still read from the BASE checkout, so a fork PR cannot
  weaken the gate it must pass.
- The three-level `workflow_run` chain is at GitHub's documented ceiling and is known to be occasionally
  flaky. This is accepted for now and flagged for live verification (see Verification).

## Verification
- YAML validity of all three workflows (local, done).
- `run-review.sh` produces a valid `review.json` from an intake-shaped `.asdd-work` artifact, with SAST
  degrading gracefully when the head ref is absent (local, done).
- LIVE (cannot be done locally, requires a real PR): on this PR, confirm the chain runs end to end -
  intake passes, the review workflow triggers from it and posts the advisory comment via publish. Then,
  on a PR that deliberately fails intake, confirm the review workflow does NOT run (no model spend). A
  fork PR confirms the fork path, but the same-repo path exercises the whole rewiring.
