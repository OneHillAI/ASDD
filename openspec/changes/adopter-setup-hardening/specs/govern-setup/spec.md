## ADDED Requirements

### Requirement: Intake does not false-fail before a lane label exists
The intake gate SHALL NOT report a failure on a pull request solely because a lane label has not been
applied yet on the opening event. A lane-less pull request SHALL surface as a pending required check, not a
red failure, and enforcement SHALL be preserved: a pull request that never carries exactly one lane label
SHALL NOT produce a passing intake result and SHALL remain unmergeable.

#### Scenario: A freshly opened PR shows pending, not red
- **WHEN** a pull request is opened before any lane label is applied
- **THEN** the `intake` check does not report a failure for the missing lane
- **AND** the check is pending until intake runs for real

#### Scenario: The real verdict comes from the label event
- **WHEN** the lane label is then applied to the pull request
- **THEN** intake runs and reports the actual verdict (disclosure, DCO, exactly one lane)

#### Scenario: A lane-less PR still cannot merge
- **WHEN** a pull request never receives exactly one lane label
- **THEN** intake never produces a passing result and the pull request stays blocked

### Requirement: Enforcement is a documented setup step
The govern-layer adoption guide SHALL include an explicit, numbered enforcement step that turns the gates
from advisory to enforced, naming the required checks and the Code Owner requirement, and stating that
direct pushes to the default branch are blocked.

#### Scenario: The guide names the enforcement step
- **WHEN** an adopter reads the govern-layer adoption guide
- **THEN** a numbered step directs them to require the `intake` and `asdd/review` checks and a Code Owner
  review in branch protection, and to block direct push to the default branch
- **AND** the step states that the gates are advisory until branch protection requires them
