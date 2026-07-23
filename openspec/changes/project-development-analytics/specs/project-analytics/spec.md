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
- **THEN** the dashboard reports the topics and states that no goal or invariants are declared to judge
  them against

### Requirement: Balance map across six fixed dimensions
The dashboard MUST render a radar (spider) chart with exactly **six fixed dimensions**, each on a scale
from `0` at the centre to `5` at the outer point, drawn as **two overlaid polygons**: the current-state
scored from merged PRs, and the to-be state scored from merged plus open PRs with each open PR projected as
if merged. The chart MUST make an unbalanced project visually obvious (a spike on one axis, a collapse on
another) the way an attribute chart does for equipment or a game character.

#### Scenario: Two polygons on one chart
- **WHEN** the dashboard renders analytics for a repository
- **THEN** the radar shows a current-state polygon and a to-be polygon over the same six labelled axes,
  each axis scaled 0 at centre to 5 at the point

#### Scenario: To-be projects the open work
- **WHEN** open PRs exist
- **THEN** the to-be polygon is computed as if those open PRs were merged, so the gap between the two
  polygons shows the direction the open work moves the project

#### Scenario: A missing dimension does not break the chart
- **WHEN** a dimension has no signal to score (no relevant PRs yet)
- **THEN** that axis renders at 0 with a "not enough signal" note, and the rest of the chart still renders

### Requirement: Definition of the six balance dimensions
The six dimensions MUST be the principles of a healthy software project below, each scored `0` to `5` from
PR-derived signals. Each dimension MUST be scored for the current-state (over merged PRs) and the to-be
state (over merged plus projected-open PRs) by the same rule, so the two are comparable.

1. **Correctness** - the share of green-merged PRs (passed review, passed tests) that did NOT later produce
   a reported escaped defect. `5` means no escaped defects.
2. **Verification** - the share of code-changing PRs that added or extended tests AND passed the test gate.
   `5` means every code change is test-backed and green.
3. **Documentation** - the share of user-facing PRs that updated docs or the impact log. `5` means every
   user-facing change is documented.
4. **Spec conformance** - the share of PRs that met the spec / OpenSpec readiness standard at intake. `5`
   means every change was spec-driven.
5. **Governance integrity** - the share of merges that passed the agent and human review with no override
   and no MUST-invariant violation, reduced by any malicious or against-invariant attempts. `5` means a
   clean review record.
6. **Flow** - submitted-to-merged conversion and the absence of long-stuck PRs. `5` means work converts
   healthily without a growing backlog.

#### Scenario: Each dimension is scored for both states by one rule
- **WHEN** the analytics model runs
- **THEN** each of the six dimensions has a current-state score and a to-be score in `[0, 5]` produced by
  the same scoring rule over the respective PR set

### Requirement: Governance KPI ratios
The dashboard MUST render the following as totals and percentages, with the count that fails or violates
always shown alongside the percentage:

- incoming PRs that fit the spec / OpenSpec standard versus that do not;
- PRs that pass review versus that do not (the failing count called out explicitly);
- tests created, tests passing, and doc updates from merged PRs, each with an up or down trend against the
  prior window;
- the review categories that findings fall into (for example security, spec, quality, impact), with counts;
- PRs that conform to versus violate a MUST invariant;
- PRs that attempted to change the core business logic of the code;
- PRs flagged as malicious.

#### Scenario: Ratios show total, percentage, and the failing count
- **WHEN** the dashboard renders the KPI ratios
- **THEN** each ratio shows a total, a percentage, and the absolute number of the failing or violating side

#### Scenario: A KPI with no signal reads as unavailable
- **WHEN** a KPI's input signal is not present (for example no invariant markers are declared)
- **THEN** that KPI reads "not enough signal" and is not counted as `0%`, so an absent signal is never
  shown as a real result

### Requirement: Escaped-defect KPI
The dashboard MUST count **escaped defects**: a defect reported against a PR that had passed review green
and passed its tests, yet still shipped the defect. The link from a defect report to the PR that introduced
it MUST come from a declared convention (a bug-lane PR that names the introducing PR via a trailer, for
example `Escaped-from: #<number>`). This count MUST be presented as the headline bug-free-software signal
and MUST feed the Correctness dimension.

#### Scenario: A green-then-buggy PR is counted as an escaped defect
- **WHEN** a merged PR that passed review and tests is later named by a bug report through the declared
  link convention
- **THEN** that PR is counted as an escaped defect and lowers the Correctness dimension

#### Scenario: No escaped defects reads as the best case
- **WHEN** no merged PR is named by any bug report
- **THEN** the escaped-defect count is `0` and Correctness is at its maximum, distinct from "not enough
  signal"

### Requirement: Submitted-versus-merged throughput
The dashboard MUST show how many PRs were submitted and how many were merged over the window, as the
top-line throughput pair, and MUST feed this into the Flow dimension.

#### Scenario: Throughput pair is shown
- **WHEN** the dashboard renders
- **THEN** it shows the submitted count and the merged count for the window as a labelled pair

### Requirement: Provenance and privacy unchanged
The analytics section MUST render only facts already visible on GitHub for the repository, MUST keep a
private deployment behind authentication, and MUST require the existing `--public` opt-in before any of it
is rendered for publication. It MUST NOT introduce any new external data source or any new disclosure
beyond what the dashboard already publishes.

#### Scenario: Public render adds no new disclosure
- **WHEN** the dashboard is rendered with `--public`
- **THEN** every analytics fact shown is one already readable on GitHub by anyone, and no new field is
  disclosed that the dashboard did not already publish
