## ADDED Requirements

### Requirement: Two-state PR summary
The dashboard MUST render a summary of every submitted (open) pull request and every merged pull request,
labelled so the two are read as distinct states: **submitted = the to-be state** (what the project becomes
if the open work merges) and **merged = the current-state** (what the project is now). Each state MUST show
a total count and a short per-PR digest (number, title, lane, declared scope).

#### Scenario: Both states are shown side by side
- **WHEN** the dashboard renders for a repository with open and merged PRs
- **THEN** it shows a submitted (to-be) group and a merged (current-state) group, each with its total and a
  per-PR digest
- **AND** a repository with no open PRs still shows the merged (current-state) group and an empty to-be
  group, not an error

### Requirement: Analytics window and merged-PR signals
The analytics MUST score the current-state from merged PRs, which means it MUST read each merged PR's check
statuses and changed files, not only open PRs. Every ratio and dimension MUST be computed over an explicit,
stated **window** (for example a PR count, a date range, or all history), and MUST NOT silently measure over
only the most-recently-updated page of PRs. When the repository has more PRs than one fetch page, the
analytics MUST paginate to cover the declared window rather than report a partial denominator as if it were
the whole.

#### Scenario: Current-state reads merged-PR signals
- **WHEN** the analytics scores the current-state
- **THEN** it uses the check statuses and changed files of merged PRs, not only open PRs

#### Scenario: The measured window is explicit and complete
- **WHEN** the dashboard renders a ratio or dimension
- **THEN** the window it was computed over is stated on the page
- **AND** the denominator covers that whole window, paginating when the repository exceeds one fetch page,
  so a large repository is never scored over an unstated recent slice

### Requirement: What the work is about, against goal and invariants
The dashboard MUST report the most common topics across submitted PRs and, separately, across merged PRs,
derived from each PR's lane, declared scope, and changed areas. It MUST present those topics against the
project's declared **goal** and **invariants** (read from config), stating in plain language whether the
weight of the work supports the goal or diverges from it. When no goal or invariants are declared, it MUST
say so rather than invent a judgement.

#### Scenario: Topics summarised for each state
- **WHEN** submitted and merged PRs carry lanes, declared scopes, and changed paths
- **THEN** the dashboard lists the leading topics for the to-be state and for the current-state separately

#### Scenario: Topics read against the declared goal
- **WHEN** a project goal and invariants are declared in config
- **THEN** the dashboard states whether the leading topics support or diverge from that goal and names any
  topic that touches an invariant
- **WHEN** no goal or invariants are declared
- **THEN** the dashboard reports the topics and states that none are declared to judge them against

### Requirement: Balance map across six fixed dimensions
The dashboard MUST render a radar (spider) chart with exactly **six fixed dimensions**, each on a scale from
`0` at the centre to `5` at the outer point, drawn as **two overlaid polygons**: the current-state scored
from merged PRs, and the to-be state scored from merged plus open PRs. An open PR whose review is requesting
changes MUST NOT be projected into the to-be state as if it will merge unchanged; the to-be projection MUST
exclude or down-weight a changes-requested PR, so it reflects the work that is actually on track to land.

#### Scenario: Two polygons on one chart
- **WHEN** the dashboard renders analytics for a repository
- **THEN** the radar shows a current-state polygon and a to-be polygon over the same six labelled axes, each
  axis scaled 0 at centre to 5 at the point

#### Scenario: To-be excludes work the review is blocking
- **WHEN** an open PR's review recommendation is request-changes
- **THEN** that PR is excluded or down-weighted in the to-be projection, so the to-be polygon is not inflated
  by work that is not on track to merge

#### Scenario: A missing dimension does not break the chart
- **WHEN** a dimension has no signal to score
- **THEN** that axis renders with a "not enough signal" marker rather than a misleading value, and the rest of
  the chart still renders

### Requirement: Definition of the six balance dimensions
The six dimensions MUST be the principles below, each scored `0` to `5` from PR-derived signals, for the
current-state (over merged PRs) and the to-be state (over merged plus on-track open PRs) by the same rule.

1. **Correctness** - the share of green-merged PRs (passed review, passed tests) that did NOT later produce a
   reported escaped defect.
2. **Verification** - among **code-changing** PRs only, the share that added or extended tests AND passed the
   test gate. A docs-only or non-code PR MUST be excluded from this denominator, not scored zero.
3. **Documentation** - among **user-facing** PRs only, the share that updated docs or the impact log.
4. **Spec conformance** - the share of PRs that met the spec / OpenSpec readiness standard at intake, counting
   only the spec signal (see the spec-conformance requirement), over lanes that are not spec-exempt.
5. **Governance integrity** - the share of merges that passed the agent and human review with no override and
   no MUST-invariant violation, reduced by any malicious or against-invariant attempts.
6. **Flow** - submitted-to-merged conversion and the absence of long-stuck PRs.

A dimension MUST NOT report a confident score below its minimum-signal threshold (see the minimum-signal
requirement). In particular Correctness MUST NOT default to `5` on a project with too few green merges to
judge: "not enough signal" MUST win over the maximum score at low counts, so an unproven project never reads
as flawless.

#### Scenario: Each dimension is scored for both states by one rule
- **WHEN** the analytics model runs
- **THEN** each of the six dimensions has a current-state score and a to-be score in `[0, 5]` produced by the
  same scoring rule over the respective PR set, or a "not enough signal" state

#### Scenario: Non-applicable PRs leave a denominator
- **WHEN** the Verification or Documentation dimension is scored
- **THEN** PRs the dimension does not apply to (a docs-only PR for Verification, a non-user-facing PR for
  Documentation) are excluded from the denominator rather than counted as failures

### Requirement: Spec conformance uses its own signal, not the intake verdict
The spec-conformance metric MUST NOT be read from the single intake pass/fail, because intake rolls the spec
check together with disclosure, DCO, and lane, and a spec-exempt lane (chore) passes intake with no spec. The
intake gate MUST expose the spec result as its own signal, and the metric MUST exclude spec-exempt lanes from
its denominator, so "passed intake" is never miscounted as "spec-conformant."

#### Scenario: A chore PR is not counted as spec-conformant
- **WHEN** a chore-lane PR passes intake without a spec (spec-exempt)
- **THEN** it is excluded from the spec-conformance denominator, not counted as a conforming spec

### Requirement: Machine-readable per-lens review output
So the dashboard can report review categories, malicious flags, and impact-core findings structurally rather
than by scraping a rendered comment, the review MUST emit a machine-readable per-lens result (a per-lens
status context, or a structured block the dashboard parses), carrying each lens name, its verdict, and its
findings. The human-facing comment is unchanged; this is an additional structured emission.

#### Scenario: Per-lens results are queryable
- **WHEN** a review completes
- **THEN** the dashboard can read each lens (code, security, spec, quality, impact) with its verdict and
  findings from a structured source, without parsing the prose comment

### Requirement: Governance KPI ratios
The dashboard MUST render the following as totals and percentages, with the count that fails or violates
always shown alongside the percentage: incoming PRs that fit the spec standard versus not; PRs that pass
review versus not (the failing count called out); tests created, tests passing, and doc updates from merged
PRs, each with an up or down trend; the review categories findings fall into, with counts; PRs that conform
to versus violate a MUST invariant; PRs that attempted to change the core business logic; and PRs flagged as
malicious. A PR is **malicious** when the security lens returns a blocking or injected-instruction verdict
(derived from the per-lens output, not from a label that nothing applies). A PR is a **core-change** when it
touches a declared `protected_path` or the impact lens marks it normative-core. A MUST-invariant
conform/violate count MUST come from an explicit review-emitted invariant check; until a producer emits that,
this KPI MUST read "not enough signal" rather than imply a derived number.

#### Scenario: Ratios show total, percentage, and the failing count
- **WHEN** the dashboard renders the KPI ratios
- **THEN** each ratio shows a total, a percentage, and the absolute number of the failing or violating side

#### Scenario: Malicious is derived from the security lens, not a label
- **WHEN** the security lens returns a blocking or injected-instruction verdict on a PR
- **THEN** that PR is counted as malicious, without depending on any label that the pipeline does not apply

#### Scenario: An invariant KPI with no producer reads as unavailable
- **WHEN** no review-emitted invariant check exists
- **THEN** the MUST-invariant conform/violate KPI reads "not enough signal", not a fabricated `100%`

### Requirement: Escaped-defect KPI as the review false-negative signal
The dashboard MUST count **escaped defects**: a defect reported against a PR that had passed review green and
passed its tests, yet still shipped the defect. The link MUST come from a declared convention: a bug-lane PR
**or a bug-labelled issue** naming the introducing PR via a trailer (for example `Escaped-from: #<number>`);
the issue form is required so a defect that is reported but not yet fixed still counts, rather than staying
invisible until a fix lands. This count MUST be presented as the headline signal and framed as the **review
agent's false-negative rate** (green-then-buggy means the review missed it), and it MUST state that it is only
as complete as the human attribution of the introducing PR. It MUST feed the Correctness dimension.

#### Scenario: A green-then-buggy PR is counted as an escaped defect
- **WHEN** a merged PR that passed review and tests is later named by a bug report (PR or issue) through the
  declared link convention
- **THEN** that PR is counted as an escaped defect, lowers Correctness, and raises the reported review
  false-negative rate

#### Scenario: No escaped defects is distinct from no signal
- **WHEN** enough green merges exist to judge and none is named by a bug report
- **THEN** the escaped-defect count is `0` and Correctness is at its maximum, distinct from the low-signal
  "not enough signal" state

### Requirement: Temporal trend
Beyond the current-vs-to-be radar, the dashboard MUST show how the headline signals move over time: a
per-window series (a small trend line or sparkline) for at least the escaped-defect rate, throughput, and
spec-fit, so an owner can see whether a signal is rising or falling, not only its latest value. Each KPI's
trend indicator MUST be backed by this series.

#### Scenario: Headline signals carry a trend over windows
- **WHEN** the dashboard renders
- **THEN** the escaped-defect rate, throughput, and spec-fit each show a per-window series, and a KPI's
  up/down trend indicator reflects that series

### Requirement: Minimum signal and progressive reveal
Every metric MUST declare a minimum amount of signal (for example a minimum number of qualifying merged PRs)
below which it does not show a number and instead shows a short note that it is still filling in. A new
project starts mostly in this state; an existing repository that adopts ASDD draws on its historical PR data
and will already clear the bar for most metrics. As signal accrues past a metric's threshold, that metric
starts rendering on its own, with nothing hidden and no misleading value shown in the meantime.

#### Scenario: A below-threshold metric shows a note, not a number
- **WHEN** a metric has fewer than its minimum qualifying PRs
- **THEN** it shows a short "still filling in" note instead of a value, and begins rendering once the history
  reaches the threshold

#### Scenario: An existing repo clears the bar from history
- **WHEN** a repository with substantial merged-PR history adopts the dashboard
- **THEN** the metrics that its history satisfies render immediately, without waiting for new PRs

### Requirement: Provenance and privacy unchanged
The analytics section MUST render only facts already visible on GitHub for the repository, MUST keep a private
deployment behind authentication, and MUST require the existing `--public` opt-in before any of it is rendered
for publication. It MUST NOT introduce any new external data source or any new disclosure beyond what the
dashboard already publishes.

#### Scenario: Public render adds no new disclosure
- **WHEN** the dashboard is rendered with `--public`
- **THEN** every analytics fact shown is one already readable on GitHub by anyone, and no new field is
  disclosed that the dashboard did not already publish
