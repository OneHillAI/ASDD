## ADDED Requirements

### Requirement: Declared conventions contract
A project SHALL be able to declare, in version control, how it already ships: where a spec lives, the
changelog form, the impact log it maintains, its house style, its preflight command, and exemplar changes.
Every field SHALL be optional, and an undeclared field SHALL NOT be checked, so a project declares only
what it actually has.

#### Scenario: A project declares its own workflow
- **WHEN** a project declares a conventions block naming its spec directory, changelog form and impact log
- **THEN** those conventions are readable by the agents and by the deterministic gate

#### Scenario: An undeclared convention is never invented
- **WHEN** a project declares no impact log
- **THEN** no impact-log requirement is applied to any change

### Requirement: Conventions are injected as a binding output contract
Every operate agent that produces a change SHALL receive the declared conventions as an output contract
rather than as advice, and SHALL produce the artefacts the contract names, in the places it names.

#### Scenario: The documentation agent follows the host's artefacts
- **WHEN** the documentation agent runs on a project declaring a fragment changelog and an impact log
- **THEN** it adds a changelog fragment and an impact-log entry in the declared locations
- **AND** it does not edit the assembled changelog directly

#### Scenario: An agent self-checks before proposing
- **WHEN** an agent has produced a change and is about to propose it
- **THEN** it can obtain a conforming or not-conforming verdict on its own output and correct it first

### Requirement: Conventions are verifiable, and a violation fails loudly
A deterministic gate SHALL check a produced change against the declared conventions and SHALL report a
violation as a failure, so a drifting agent is caught rather than quietly producing work a human must redo.
A malformed or unsatisfiable conventions block SHALL be reported as a setup error, distinct from a change
violation.

#### Scenario: A change that ignores a declared convention fails
- **WHEN** a change is checked against a project declaring a fragment changelog, and it adds no fragment
- **THEN** the gate reports the change as not conforming and names the missing artefact

#### Scenario: A misconfiguration is not reported as a passing change
- **WHEN** the conventions block declares a path that does not exist in the repository
- **THEN** the gate reports a setup error distinct from a conforming or not-conforming verdict

### Requirement: A learned convention is promoted, never assumed
A convention inferred from the project (from its tree, its history, or a learned knowledge entry) SHALL be
treated as a candidate for declaration. It SHALL acquire binding force only by being written into the
declared conventions block, and that promotion SHALL be a human decision presented as a reviewable diff.
Inference SHALL NOT be applied to the configuration automatically.

This is the mechanism side of the knowledge layer's rule that learned knowledge proposes and only a
declared contract binds. The two are orthogonal: staleness governs whether a claim is still true, and this
governs whether a claim has force. A learned convention can be perfectly current and still not bind.

#### Scenario: An inferred convention is proposed, not enforced
- **WHEN** adoption tooling infers that the project keeps an impact log
- **THEN** it proposes adding that to the declared conventions block
- **AND** agent output is not held to it until the declaration is merged

#### Scenario: Promotion is a reviewable human decision
- **WHEN** an adoption scan produces a proposed conventions block
- **THEN** it is presented as a diff for a human to confirm, amend or reject
- **AND** nothing is written to the project's configuration without that confirmation

### Requirement: Map to existing artefacts, never duplicate them
Where a project already maintains an artefact, ASDD SHALL point at it. Adoption SHALL NOT create a second
artefact of the same kind beside the one the project already keeps.

#### Scenario: An existing impact log is adopted, not shadowed
- **WHEN** a project already maintains an impact log and adopts ASDD
- **THEN** the agents write to that file
- **AND** no parallel ASDD-owned impact log is created

### Requirement: Gating is diff-scoped and ratcheted
Adoption gates SHALL judge only the change under review, never the existing tree, and content rules such
as house style SHALL be evaluated on added lines only. A repository's pre-existing violations SHALL be
inherited as a baseline rather than blocking adoption.

#### Scenario: A mature repository can adopt on day one
- **WHEN** a repository with many pre-existing style violations adopts ASDD
- **THEN** adoption is not blocked by the existing tree

#### Scenario: A pre-existing violation is inherited but a new one is refused
- **WHEN** a change leaves an existing violating line untouched in its context
- **THEN** the gate does not fail for that line
- **WHEN** the same change adds a new line carrying the same violation
- **THEN** the gate fails for the added line

### Requirement: Staged adoption ladder
Adoption SHALL support ordered stages: `observe`, in which agents run and record output without posting;
`advise`, in which agents post but nothing blocks; and `gate`, in which checks are required. Conformance
SHALL be expressed as the stage a project has reached rather than a single pass or fail.

#### Scenario: A project claims a stage honestly while climbing
- **WHEN** a project runs the agents in observe and posts nothing
- **THEN** it can claim the observe stage rather than failing conformance outright

#### Scenario: Advancing a stage is a deliberate act
- **WHEN** a project moves from advise to gate
- **THEN** the required checks begin to block, and the change of stage is recorded

### Requirement: Knowledge may be seeded from project history
The onboarding pass SHALL be able to seed the knowledge layer from the project's history (commit history,
merged changes, review comments and closed issues) in addition to the working tree, and SHALL be able to
record what was rejected, what is already shipped, known flaky or environment-dependent tests, and
exemplar changes. Seeded entries SHALL carry provenance marking them history-derived.

#### Scenario: An existing project starts warm rather than cold
- **WHEN** the onboarding pass runs on a repository with substantial history
- **THEN** it seeds knowledge entries derived from that history, each marked history-derived

#### Scenario: A rejected approach is not re-proposed
- **WHEN** the history records that an approach was considered and rejected
- **THEN** that rejection is retrievable as grounding

#### Scenario: Shipped work is not re-flagged as missing
- **WHEN** the history records a capability as already delivered
- **THEN** an agent retrieving grounding does not report it as unbuilt

### Requirement: Seeded history is never written to the audit ledger
Reconstructed history SHALL be written only to the knowledge layer. It SHALL NOT be written to the audit
ledger, because an audit record asserts that an agent action occurred and a reconstructed record would
assert an action that never took place.

#### Scenario: Seeding does not forge audit records
- **WHEN** the onboarding pass seeds knowledge from a project's history
- **THEN** no audit-ledger record is created for any historical event
- **AND** the ledger continues to contain only records of actions agents actually took

### Requirement: Upgrade preserves project customisation
Framework-owned files SHALL be distinguishable from project overrides, and an upgrade SHALL report drift
in a way that separates "this project is behind the current kit" from "this project deliberately
customised this file". An upgrade SHALL NOT silently overwrite a customised file.

#### Scenario: A customised file is not clobbered by an upgrade
- **WHEN** a project has customised a kit file and a newer kit is available
- **THEN** the drift report distinguishes the customisation from being behind
- **AND** the upgrade does not overwrite it silently

### Requirement: Adoption is reversible
Framework-owned files SHALL live in known paths so that removing ASDD is a deletion rather than an
archaeological exercise, and removal SHALL leave the project's own artefacts intact.

#### Scenario: A project can un-adopt cleanly
- **WHEN** a project removes ASDD
- **THEN** deleting the known framework paths removes it
- **AND** the project's own spec, changelog and impact-log artefacts are untouched

### Requirement: Heterogeneity binds new work only
The requirement that the developer model differ from the test-author and test-runner models SHALL apply to
tests authored after adoption. A suite that predates adoption SHALL NOT be treated as violating it, and
tooling messages SHALL say so.

#### Scenario: A pre-existing suite does not fail adoption
- **WHEN** a project with an existing test suite adopts ASDD
- **THEN** the existing suite is not reported as violating the heterogeneity invariant

### Requirement: The host repository is classified at adoption
The security classification SHALL be applied at adoption to the automation the host repository ALREADY has,
not only to what ASDD adds. On a new project the only jobs are the ones this kit adds, so classifying the
file is the same as classifying the risk. On an existing repository it is not: the repository arrives with
its own jobs, its own credentials, and its own established paths between the two, none of which adoption
created and all of which adoption inherits.

For each job, existing and added, the classification SHALL resolve three things, treating any two together
as a finding and all three as critical:

- **Input trust**: whether an untrusted party can influence the job's input, including a job chained off a
  workflow that ran against untrusted input.
- **Reachable credential**: not the credentials the job interpolates but everything it could read, which
  includes inherited organisation-level secrets the repository's own files never name, ambient credentials
  on the runner, and the effective write scope of the default token.
- **Attacker-influenced execution**: whether the job runs content the untrusted party controls, which
  includes a build, a test suite, a dependency install and a checked-out script, not only an agent.

#### Scenario: A chained job inherits the untrusted trigger
- **WHEN** a job is triggered by the completion of a workflow that ran against untrusted input
- **THEN** it is classified as handling untrusted input, rather than judged by its own trigger alone

#### Scenario: Reach is classified, not the names in the file
- **WHEN** a job interpolates no credential but runs where organisation-level secrets or ambient runner
  credentials are available to it
- **THEN** the classification records what the job could reach, not only what its file mentions

#### Scenario: A self-hosted runner widens the blast radius
- **WHEN** a job handling untrusted input runs on a self-hosted runner
- **THEN** the classification records that the exposure includes credentials and co-resident workloads on
  that host which no workflow file declares

#### Scenario: An existing test run against untrusted input is surfaced
- **WHEN** a repository already runs its own test suite against a fork's content with credentials in scope
- **THEN** adoption reports it, because that is the exposure the rule exists to prevent and it was present
  before ASDD was installed

### Requirement: Pre-existing exposure is a recorded baseline, not a blocker
Adoption SHALL record exposure that predates it as a baseline carrying a named owner and a severity, and
SHALL NOT require the repository to be clean before it can adopt. A change that ADDS to the baseline SHALL
be refused. Blocking adoption on full remediation means the classification is never run at all, which
leaves the exposure both present and unrecorded.

#### Scenario: A finding closed by design is recorded as mitigated, not left open
- **WHEN** a job scores two of the three and the missing leg is absent by deliberate design, for example
  it holds a credential and handles untrusted input but never executes that input, handling it as data
- **THEN** the finding is recorded as mitigated, naming the property that closes it and how that property
  is enforced, rather than remaining permanently open
- **AND** the mitigation is re-examined if the job later gains the missing leg

#### Scenario: Adoption proceeds with the exposure written down
- **WHEN** the classification finds exposure that predates adoption
- **THEN** it is recorded as a baseline entry with an owner and a severity and adoption proceeds
- **AND** a later change that adds new exposure is refused

#### Scenario: The remedy is the split the kit already uses
- **WHEN** a finding is remediated
- **THEN** the job handling untrusted input holds no credential, and a separate write-scoped job handles
  only content produced by the trusted side
