# Guide: the gates, and how to tune them

Every requirement ASDD enforces is configured in `.asdd.yml` in your repo. This page lists what each
gate checks, whether it is a **floor** (an invariant with a minimum you configure within but cannot
remove and still call yourself ASDD-conformant) or a **knob** (fully your discretion), and the key that
controls it. The config is read from the base branch, so a pull request can never weaken the gate it has
to pass by editing its own `.asdd.yml`.

Two kinds of check run over every PR: **deterministic gates** (no model, structural, always run) and the
**review lenses** (model-driven, judgment). The gates below are the deterministic floor; the lenses are
the qualitative layer on top.

## The floors (conformance invariants)

These are the checks that make ASDD ASDD. You configure them, but a conformant project keeps them on.

| Requirement | What it checks | Key(s) in `.asdd.yml` |
|---|---|---|
| **Disclosure** | The PR attests human or AI-agent authorship. | enforced by intake; identities in `agents:` |
| **DCO sign-off** | Every commit is `Signed-off-by`. | enforced by intake |
| **Exactly one lane** | The PR carries one lane label. | `lanes:` (you choose the set) |
| **Spec-driven** | A non-trivial PR references or adds a spec. `chore` is exempt. | `require_spec`, `spec_paths`, `spec_tool` |
| **Declared conventions** | If the project declares a `conventions:` block, the change is held to it. No block means no check. | `conventions:`; enforced by intake, runnable locally with `asdd conventions-check` |
| **Different models for dev and test** | The developer and the test agents run different models, so their blind spots do not line up. | `models:` (`developer` != `test_author`, `test_runner`); enforced by `cli/check-models.sh` |
| **Protected paths never auto-merge** | High-impact paths stay human-approved forever. | `protected_paths:` (you expand it) |
| **Human owns the merge** | Nothing merges automatically by default. | `merge_posture: advisory` |
| **Security findings block** | A blocking security finding fails the `asdd/review` status. | make `asdd/review` a required check in branch protection |
| **The PDP denies merge for agents** | Every agent action passes a policy decision point; `merge` is always denied. | fixed |

You can make the floors *stricter* (more protected paths, `require_spec: true`, a longer definition of
ready). Going *below* them is where you stop being conformant.

## The knobs (your discretion)

Tune these to your project with no conformance cost.

### Specs
- `spec_tool:` - `builtin` (the four-field definition of ready) or `openspec` (delegate to
  `openspec validate`). See [adopt-openspec.md](adopt-openspec.md).
- `spec_paths:` - where your specs live. Unset uses a default that follows `spec_tool`.
- `intake.definition_of_ready:` - the fields a built-in spec must carry. The **floor** is
  outcomes + scope + constraints + verification; you may add project-specific fields, not remove these.
- `intake.spec_context:` - `docs` (documentation only; use for **public** untrusted contribution
  surfaces) or `codebase` (the full repo; **private, in-org** trusted use only). This decides what the
  spec agent may read.

### Your project's own conventions (brownfield)
- `conventions:` - how your project already ships: `spec_dir`, `changelog` (fragment or direct, with the
  fragment pattern and category set), `impact_log`, `style`, `preflight`, `exemplars`. Declaring them
  holds agent output to your workflow instead of letting an agent guess, which is what produces work in
  the wrong place. **Enforced by intake** on every PR (a violation fails the intake gate the same way a
  missing disclosure does), and runnable locally with `asdd conventions-check`.
- `conventions.docs:` - **ship the docs with the change.** Per path pattern, the documents a change
  touching it must also touch (`require`, with a `why` the gate quotes back). A change that adds a
  command but leaves the reference alone fails instead of merging unnoticed. ASDD declares this on
  itself, because a command did exactly that.
- Every field is optional and an undeclared field is never checked, so declare only what you have.
- The gate judges **only the change**, never the existing tree, and checks style on **added lines only**.
  A mature repository inherits its existing violations as a baseline and tightens from there.
- ASDD maps to an artefact you already keep; it never creates a second changelog or impact log beside it.
- See [adopt-existing-project.md](adopt-existing-project.md).

### Lanes and triage
- `lanes:` - the contribution lanes (default `feature`, `fix`, `docs`, `chore`). Exactly one per PR;
  `chore` skips the spec requirement.
- `conventions.exempt_lanes:` - lanes exempt from the declared spec and changelog requirements.
- `triage_labels:` - the only labels the triage agent may apply.

### Merge posture
- `merge_posture:` - `advisory` (default; humans approve and merge) or `earned-automerge`. New adopters
  **must** start advisory; auto-merge, if ever enabled, never touches a `protected_path`.
- `merge_reviewer:` - an independent merge-reviewer on a different model. `enabled`, `posture`
  (`review-only` or `earned-automerge`), and `auto_merge_class` (the positive allow-list of paths it may
  autonomously approve - it must never overlap `protected_paths`).

### Cost and rate
- `review.max_diff_lines:` - above this many changed lines the lenses refuse rather than spend, the
  deterministic gates still run, and a human is told to split the change. `0` disables the cap (only
  sensible on a private repo where you trust every opener).
- `max_actions_per_run:` - cap on agent actions per workflow run.
- `max_open_prs_per_author:` - anti-flood cap on concurrent PRs per contributor.

### Identity and claims
- `identity:` - `authoring` (DCO-capable to merge) and `proposing` (any attributable identity to
  submit); `provider` is your implementation choice, ASDD mandates none.
- `claim:` - `one_active_per_item`, `max_active_per_identity`, `ttl_hours` for the claim protocol that
  serialises work at the spec, before code exists.

### Agents and insights
- `models:` - the model each role runs on (`developer`, `test_author`, `test_runner`, `reviewer`,
  `documentation`, `interaction`). Keep the dev/test rule.
- `contributor_review:` - the advisory contributor-facing reviewer (`enabled`, `posture`). It suggests
  fixes; it is not the merge gate.
- `insights:` - the agent-activity log the dashboard reads (`enabled`, `activity_log`).
- `audit:` - the agent audit ledger ([STANDARD](../../STANDARD.md) 1.3), which records every agent action.
  `sink` is `none` (default; nothing is exported and the pipeline is unchanged), `repo` (append to a
  **private** sibling repository named by `sink_repo`, using the `AUDIT_SINK_TOKEN` secret) or `command`
  (your own exporter, given the ledger path). `retention_days` sets how long records are kept. The export
  refuses a sink that is the repository being governed, or that is public, or whose visibility cannot be
  proven. See [the audit ledger guide](audit-ledger.md).

## Turning a gate up or down

Every change here is itself a governed change: `.asdd.yml` is a protected path, so tuning a gate is a PR
that a human approves. That is deliberate - the rules of the project change under the same scrutiny as
the code. Read the current settings any time with `/asdd:status`.
