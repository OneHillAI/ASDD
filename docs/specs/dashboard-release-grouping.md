# Spec: the dashboard surfaces each PR's target version and suggests the next release

Lane: feature. Give the maintainer the input they need to group normative changes into versions, without
automating the grouping.

## Problem

The governance mechanism (`docs/specs/change-impact-governance.md`) deliberately keeps release-grouping a
human act: a normative PR declares a target version, and a maintainer assigns it to a release. But the
governance dashboard does not show that input. It buckets PRs by stage and lane, but not by what each PR
is about at a glance or what version it targets, and it has no view of what the next release would
contain. So the maintainer has the rule and no surface to apply it against.

## Outcomes

- Each PR on the dashboard shows its **target version** where the PR declared one, alongside the title
  (what it is about) that is already there.
- A **suggested next release** section groups the open PRs that declare a target version, by version, so
  the maintainer can see what each upcoming release would contain in one place.
- It is **suggestive, not automated**. The section is labelled as a proposal the maintainer reviews and
  confirms; nothing is assigned, tagged, or merged by the tool. A human does the grouping now; the same
  surface is where an LLM could suggest a grouping later.
- Open PRs that declare a normative change but name **no target version** are listed as needing a
  version, so a gap is visible rather than silently dropped.
- A **declaration check**: a PR declared non-normative that in fact edits the standard's normative text
  is flagged as a scope mismatch, mirroring the impact gate's own normative-path rule. The gate already
  blocks such a PR; the dashboard makes the misclassification visible at a glance.
- No new secret or write scope. The scope and target version are parsed from the PR body already in the
  snapshot; the declaration check adds one read-only call for each open PR's changed file paths.

## Scope

In:
- `cli/dashboard.py`: parse each PR body for the Change scope declaration and the target version (HTML
  comments stripped, so an unfilled template does not read as a real version, matching `impact_scan.py`).
  Add `scope` and `version` to each PR row, a `next_release` grouping to the model, a target column in
  the PR tables, and a "Suggested next release" section in the HTML. The `--json` model gains the same
  fields.
- `cli/dashboard.py`: a declaration check. Fetch each open PR's changed file paths (read-only) and apply
  the same normative-path rule as `impact_scan.py`; flag a PR declared non-normative that edits normative
  text as a `scope_check: mismatch`, add a `discrepancies` list to the model, a "scope mismatch" marker in
  the Target column, and a "Declaration check" section in the HTML.
- `cli/testdata/dashboard-fixture.json`: add PR bodies that declare a scope and a target version so the
  grouping is exercised.
- `cli/dashboard.test.sh`: assert the target version renders, the section groups by version, and a
  normative PR with no version is flagged.
- `docs/guides/governance-dashboard.md`: document the section and that it is a suggestion.

Out:
- NOT assigning a version, tagging a release, editing the CHANGELOG, or moving a PR. The tool stays
  read-only and advisory; grouping is the maintainer's act.
- NOT a new definition of the SemVer levels (defined once in `playbook/governance.md`).
- NOT an LLM call. The surface is built so an LLM suggestion can be added later; this change does not add
  one.
- NOT a new token or write scope. The grouping reads the PR body already in the snapshot; the
  declaration check adds one read-only files call per open PR, no more.
- NOT a replay of the CI review output. The declaration check recomputes the gate's deterministic
  normative-path rule from the changed paths, so it works before a model runtime is wired and never
  disagrees with the gate; it does not download the `asdd-review` artifact or parse the posted comment.

## Constraints

- Read-only and self-contained, as the dashboard already is: one static HTML page, stdlib only, no
  external assets, credential-shaped values redacted, the internal-by-default posture unchanged.
- Parsing is best-effort and fail-safe: a PR with no declaration or an unparseable body simply has no
  version and appears under "no target version", never an error.
- The scope/version parse follows the same rules as `impact_scan.py` (strip HTML comments; a ticked
  normative or non-normative box; a target version token near "target version") so the two agree on what
  a PR declared.

## Verification

- `cli/dashboard.test.sh` passes, including: a PR's target version appears in its row; the "Suggested
  next release" section groups two PRs under the same version; a normative PR with no version is listed
  as needing one; the existing buckets, redaction, escaping, and `--public` checks still pass.
- The rendered page stays self-contained (no external scripts or assets) and internal-by-default
  (noindex, the internal banner) unless `--public` is verified.
