# Spec: every change is classified for framework impact, and normative changes are versioned

Lane: feature. Add a framework-impact classification to the pipeline so no change can alter the nature
of ASDD without being seen, sized against what else it affects, and grouped into a version.

## Problem

ASDD already stops anything normative from merging silently: the standard's text and the gates are
protected paths, they never auto-merge, and `playbook/governance.md` versions the standard with SemVer
(a new or tightened MUST is major, a new SHOULD is minor, editorial is patch) and asks that normative
changes be flagged in the PR.

What is missing is the step that makes that judgement mechanical and applies it to every PR:

- No lens or field classifies a PR by its effect on the framework. The `spec` lens checks that a change
  conforms to the existing architecture, not whether the architecture itself is being changed.
- The PR template has no change-scope field, so an author never has to state whether this is a fix or a
  change to the standard. A fix that quietly changes the nature of the framework is not specifically
  caught.
- There is no requirement to state what else a change ripples to, and no step that groups a normative
  change into a target version rather than merging it as a one-off.

The result: the rules for versioning the standard exist, but nothing forces each PR to be measured
against them. This spec closes that gap.

## Outcomes

- Every PR carries a **change-scope declaration**: non-normative (fix, docs, chore, or a reference
  implementation change that does not alter required behaviour) or **normative** (changes the standard's
  normative text, or changes behaviour adopters rely on for their conformance claim).
- A new **`impact` review lens** runs on every PR and returns a classification as data: is this
  normative, does it ripple to other parts of the framework, and is it version-worthy (major / minor /
  patch) or a small fix. Its first job is to catch the mismatch: a PR declared non-normative that in
  fact changes the nature of the framework, and a normative PR that lacks an impact analysis or a target
  version.
- A normative change **MUST** carry an impact analysis (what else must adjust to stay consistent) and a
  target version, **MUST** get an explicit governance sign-off, and is grouped into a versioned release
  rather than merged on its own. This extends the existing SemVer rule in `playbook/governance.md`; it
  does not restate or replace it.
- A bug fix stays on the fast path but is still passed through the impact lens, so a fix that changes
  required behaviour is surfaced instead of waved through.
- No change to the security invariant: the impact lens is a read-only analysis lens like the others,
  holds no write scope, and treats the PR content as untrusted data.

## Scope

In:

- **`.github/PULL_REQUEST_TEMPLATE.md`**: a "Change scope" section. The author ticks non-normative or
  normative. If normative, an "Impact analysis" block is required: what else must change (which MUSTs,
  gates, agent lenses, `CONFORMANCE.md` items, docs, and reference-implementation pieces), the target
  version and its SemVer level, and why.
- **`agents/review-impact.md`**: a new lens, `impact`. It receives the PR content and the changed paths
  as untrusted data and returns one `lenses[]` entry classifying the change (normative vs not, ripple
  set, version level) and flagging any mismatch with the declared scope or any missing impact analysis /
  target version on a normative change. Severity: `block` when a normative change is undeclared or is
  missing its required impact analysis or version; `warn` for an under-sized version level or an
  incomplete ripple set; `note` otherwise.
- A **deterministic normative-path signal** feeds the lens first, so the cheap case stays cheap: a PR
  that touches only `docs/**` or other clearly non-normative paths is classified without heavy analysis,
  and a PR touching `STANDARD.md`, `standards/**`, `CONFORMANCE.md`, or `GOVERNANCE.md` is normative by
  path regardless of what the author declared. The model judgement is reserved for the harder case, a
  change on a non-normative path that still alters behaviour adopters depend on.
- **`playbook/review-flow.md`**: list `impact` among the lenses in step 3.
- **`playbook/governance.md`**: under "Changing the standard", add that a normative PR MUST carry the
  impact analysis and a target version, that normative changes are grouped into a release rather than
  merged individually, and that the `impact` lens is where every PR is measured against this. Reference
  the existing SemVer levels already stated there; do not duplicate them.
- **`.github/PULL_REQUEST_TEMPLATE.md`** and **`playbook/governance.md`** are protected paths, so this
  PR is itself human-approved and, being a normative addition to the pipeline, gets a governance
  sign-off. This spec is that dogfood.

Out:

- NOT auto-merge of anything. This adds a classification and a gate for judgement; it never lets an
  agent decide a version or merge a normative change. Humans keep every decision they keep today
  (`playbook/governance.md`, "Decisions humans keep, always").
- NOT a new definition of the SemVer levels. Major / minor / patch stay defined once in
  `playbook/governance.md`; this spec points at them.
- NOT a change to the intake gate's lane set. Scope (normative vs not) is a separate axis from lane
  (feature / fix / docs / chore); a `fix` can be normative and a `feature` can be non-normative, which
  is exactly why the fix path must still run the lens.
- NOT a machine-enforced release-grouping tool. Grouping normative changes into a version is a
  maintainer act recorded in `CHANGELOG.md`; the mechanism here makes the input to that act explicit, it
  does not automate the release.
- NOT model-gated cost creep: the lens is one lens among the existing set, under the same
  `review.max_diff_lines` cap, and the deterministic path signal keeps the trivial case off the model.

## Constraints

- The lens is read-only and advisory as data, exactly like `code`, `security`, `spec`, and `quality`. It
  posts nothing and merges nothing; only the write-scoped publish job surfaces its finding
  (`standards/security.md`).
- A normative change is defined by two things, either of which makes it normative: it edits the
  normative text (`STANDARD.md`, `standards/**`, `CONFORMANCE.md`) or the governance rules
  (`GOVERNANCE.md`, `playbook/governance.md`), OR it changes behaviour a conforming adopter relies on
  (a gate's verdict, a lens's contract, an agent's fixed prompt). The path signal catches the first
  cheaply; the model lens is what catches the second.
- The SemVer mapping is authoritative in `playbook/governance.md` and is only referenced here: new or
  tightened MUST is major, new SHOULD or clarification is minor, editorial is patch.
- No conflict with the merge-review role: the `impact` lens classifies and sizes a change; the
  merge-reviewer still independently adjudicates whether the gates cleared. The impact classification is
  input to the merge-reviewer's evidence, not a second merge verdict.
- The change adds one Markdown lens file, one template section, and two doc edits. It introduces no new
  workflow, no new secret, and no new write scope.

## Verification

- The `impact` lens file validates against the lens contract in `agents/runtime.md` (a single
  `lenses[]` entry, `"lens": "impact"`), the same shape the other lenses use.
- The PR template renders with the new "Change scope" and "Impact analysis" sections and no broken
  Markdown.
- The slop gate passes (no em or en dashes in the new or edited files).
- LIVE (needs a real PR, cannot be done locally):
  - On a PR that edits `STANDARD.md` without declaring normative scope or a target version, the `impact`
    lens returns `block` naming the missing declaration and version. This is the core "nothing changes
    the nature unseen" check.
  - On a `fix`-lane PR that changes a gate's verdict behaviour on a non-normative path, the lens flags it
    as normative-by-behaviour despite the fix lane, the sneaky-fix case.
  - On a `docs/**` typo PR, the lens classifies non-normative and adds no model spend beyond the existing
    lenses, confirming the cheap path stays cheap.
