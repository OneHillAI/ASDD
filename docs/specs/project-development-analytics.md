# Spec: project development analytics on the dashboard

Builtin-format mirror of the OpenSpec change
[`project-development-analytics`](../../openspec/changes/project-development-analytics/). The change's
`proposal.md` and `specs/project-analytics/spec.md` carry the full requirements and scenarios; this file
satisfies the repo's builtin spec gate and states the problem, requirements, and acceptance in brief.

## Problem

The governance dashboard shows the pipeline (PRs bucketed by stage) but not whether the project is getting
healthier, what the work is about against the project's goal and invariants, or whether the agent review is
actually keeping defects out. A project can merge steadily and still drift: all features and no tests, all
code and no docs, velocity up and correctness down. There is no single view of where the project sits today
and where it heads if the open work merges, and no quantifiable read on building bug-free software.

## Requirements

1. A two-state summary: submitted PRs as the to-be state, merged PRs as the current-state.
2. A read of what the work is about (leading topics per state) against the declared project goal and
   invariants.
3. A six-dimension radar balance map (0 centre to 5 point) overlaying current-state (merged) and to-be
   (merged plus on-track open PRs); a changes-requested PR is not projected as if it will merge unchanged.
4. Six dimensions: Correctness, Verification, Documentation, Spec conformance, Governance integrity, Flow,
   each scored 0 to 5, with non-applicable PRs excluded from a dimension's denominator.
5. Governance KPI ratios (spec-fit, review pass/fail, tests, docs, review categories, MUST-invariant
   conform/violate, core-change attempts, malicious), each as total, percentage, and failing count.
6. The escaped-defect KPI framed as the review agent's false-negative rate, linked by an `Escaped-from: #N`
   trailer on a bug-lane PR or a bug-labelled issue, feeding Correctness.
7. A temporal trend (per-window series) for the headline signals, and submitted-versus-merged throughput.
8. Minimum-signal handling: below a metric's threshold the dashboard shows a short "still filling in" note,
   not a misleading value; an existing repo scores from its history; a metric reveals itself as signal
   accrues. "Not enough signal" wins over a maximum score at low counts.
9. Provenance and privacy unchanged: only facts already on GitHub, private stays behind auth, `--public`
   stays the explicit opt-in.

Two producer changes this depends on: intake exposes the spec result (`spec_ok`) as its own signal so the
spec-conformance metric is not read from the rolled-up intake verdict; and the review emits a
machine-readable per-lens result so categories, malicious, and impact-core are queryable without scraping
the rendered comment.

## Acceptance criteria

- Both states render, including an empty to-be state, without error.
- Each dimension has a current-state and a to-be score in [0, 5] or a "not enough signal" state; Correctness
  does not read 5 on a project with too few green merges.
- Every ratio and dimension is computed over an explicit, stated window whose denominator covers the whole
  window (paginated), never an unstated recent slice.
- The escaped-defect count links from a bug PR or issue, feeds Correctness, and is presented as the review
  false-negative rate.
- A below-threshold metric shows a note rather than a number, and `--public` adds no new disclosure.
- A worked HTML example ships at
  [`openspec/changes/project-development-analytics/design/analytics-example.html`](../../openspec/changes/project-development-analytics/design/analytics-example.html).
