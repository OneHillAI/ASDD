## ADDED Requirements

### Requirement: Trigger on approval
A build SHALL be triggered only when a spec is approved-to-build, meaning it meets the definition of ready
AND a maintainer has explicitly green-lit it. Readiness alone or a green-light alone SHALL NOT trigger a
build, and the signal SHALL be read from the base configuration.

#### Scenario: Ready and green-lit triggers exactly one build
- **WHEN** a spec meets the definition of ready and a maintainer green-lights it
- **THEN** exactly one build is triggered, on a claim

#### Scenario: Ready but not green-lit does not build
- **WHEN** a spec meets the definition of ready but has no maintainer green-light
- **THEN** no build is triggered

#### Scenario: Green-lit but not ready does not build
- **WHEN** a spec is green-lit but does not meet the definition of ready
- **THEN** no build is triggered

### Requirement: Build then a normal PR, never a merge
The development agent SHALL implement the approved spec on a branch and open a pull request into the normal
gate, and SHALL NOT merge, approve, set a required status, or bypass a protected path's human approval.

#### Scenario: The opened PR is gated and human-merged
- **WHEN** the development agent opens a pull request for an approved spec
- **THEN** the PR runs intake, review, and the cross-check
- **AND** the merge still requires a human, and a protected path still requires a named human owner

#### Scenario: The agent never merges
- **WHEN** the PR opened by the development agent is fully green
- **THEN** it is not auto-merged by the agent

### Requirement: Bring-your-own development runtime
ASDD SHALL define the trigger, claim, disclosure, and PR contract, not the builder, and SHALL default to
`develop.posture: off`, which changes nothing.

#### Scenario: Disabled by default
- **WHEN** `develop.posture` is `off`
- **THEN** no build is ever triggered and the pipeline is unchanged

### Requirement: Model heterogeneity
The developer model SHALL differ from the tester and reviewer models, and a live fleet SHALL fail closed if
they match, so an automated build cannot be reviewed by its own model.

#### Scenario: Matching models fail closed
- **WHEN** `models.developer` equals the tester or reviewer model in a live fleet
- **THEN** the model check fails and the automation does not run

### Requirement: Disclosure and claim
The development agent's commits SHALL carry the `Agent:` trailer and a DCO sign-off, the PR SHALL disclose AI
authorship and attribute the spec's human author, and the agent SHALL claim the work item before building.

#### Scenario: An undisclosed automated build is stopped at intake
- **WHEN** an automated build opens a PR without disclosure or DCO sign-off
- **THEN** intake fails the PR

#### Scenario: A claim prevents collision
- **WHEN** the development agent begins building an approved spec
- **THEN** it holds an active claim on the work item so a human or another agent does not build it in parallel

### Requirement: Bounded automation
Automated development SHALL be bounded by `max_concurrent_builds` and the open-PR cap, and SHALL report what
it defers.

#### Scenario: The concurrency cap holds
- **WHEN** the number of in-flight automated builds reaches `max_concurrent_builds`
- **THEN** the next build is deferred and the deferral is logged

### Requirement: Trusted plane only
Automated development SHALL run only where the contributor is trusted and the agent may read the codebase
(`spec_context: codebase`), and SHALL NOT be wired to an anonymous public contributor path.

#### Scenario: The public surface never triggers a build
- **WHEN** the project is configured `spec_context: docs` for a public contribution surface
- **THEN** automated development is not available on that path

### Requirement: Impact governance still applies
When an approved spec is normative, the pull request the development agent opens SHALL carry the change-scope
declaration, the impact analysis, and a target version, and SHALL be gated by the impact lens.

#### Scenario: A normative approved spec produces an impact-carrying PR
- **WHEN** the approved spec is a normative change
- **THEN** the opened PR declares normative scope with an impact analysis and a target version
- **AND** the impact lens gates it like any other normative change
