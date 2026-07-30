## Why

Two adopter-visible setup dead-ends, found dogfooding a fresh public repo:

1. **First-PR label-race.** The intake gate triggers on the `opened` event, before a lane label can be
   applied (you cannot label a PR that does not exist yet). So a brand-new PR fails `intake` on `opened`
   (no lane), then passes on the `labeled` re-run. The adopter sees a red X, or a cancelled run, next to a
   green one and concludes the gate rejected them.
2. **Enforcement reads like a footnote.** On a fresh repo, branch protection is off, so every gate (intake,
   `asdd/review`, Code Owner review) is advisory: green checks that do not block a merge. The adopter's
   mental model is "the gates enforce"; they only enforce once branch protection requires those checks and
   blocks direct push. The adoption guide does not call this out as the step that turns advisory into
   enforced.

## What Changes

- Intake no longer runs on the bare `opened` event. It first runs when the lane label is applied
  (`labeled`) or on a push (`synchronize`), so a lane-less PR shows a pending, not a red, `intake` check.
  Enforcement is preserved: a PR that never gets a lane never produces a passing intake, so it stays
  blocked.
- The adoption guide gains a loud, numbered enforcement step that names the exact required checks and the
  Code Owner requirement, and positions branch protection as the switch from advisory to enforced.

## Impact

- Affected specs: govern-setup
- Affected code: `.github/workflows/asdd-intake.yml` (trigger types; a stale failure-summary path), and
  `docs/guides/adopt-govern.md` (the enforcement step).
- Not in this change (dependency): scaffolding `cli/openspec-gate.py` into the `init --goose` copy list
  needs `cli/_openspec_locate.py` from the operate-kit PR (#12) to exist first; it follows once #12 lands.
