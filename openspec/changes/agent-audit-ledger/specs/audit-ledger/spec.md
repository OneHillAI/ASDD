## ADDED Requirements

### Requirement: Every agent action produces an audit record
Every agent action SHALL append exactly one append-only audit record. The record SHALL carry the agent
identity, the role and lens, the model and provider it ran on, the action, the target, the authorizing
decision that permitted it, the accountable human the identity maps to, a timestamp, the run, pull request
and commit lineage, the duration, and the outcome. No agent action SHALL occur without a corresponding
record (`STANDARD.md` 1.3).

#### Scenario: An action without a record is a conformance failure
- **WHEN** an agent takes any action covered by the standard
- **THEN** a record exists carrying identity, action, target, authorizing decision, and timestamp
- **AND** the record names the accountable human for that agent identity

### Requirement: Reasoning and the resulting action are recorded
Each record SHALL capture the agent's stated reasoning for its decision and the action that followed from
it, so the trail answers what was decided, why, and what it caused. Raw reviewed content SHALL NOT be
copied wholesale into the record; an inputs digest SHALL identify what the agent saw.

#### Scenario: A verdict is traceable to its reasoning and effect
- **WHEN** a lens returns a verdict that causes a status to be set or a comment to be posted
- **THEN** the record holds the verdict, the reasoning, and the resulting action
- **AND** it holds a digest of the inputs rather than a copy of the reviewed content

### Requirement: Every emitting role is covered
The review lenses (code, security, spec, quality, impact), the test author, the test runner, the
documentation agent, the triage or listener agent, the spec and interaction agent, and the merge reviewer
SHALL each emit records for their work.

#### Scenario: Review lenses record findings and the action taken
- **WHEN** a review lens completes
- **THEN** its record holds the verdict, each finding with severity, rule, path and message, the reasoning,
  and whether it caused a comment, a status, or a block

#### Scenario: The test author records what it wrote and why
- **WHEN** the test author produces or extends tests
- **THEN** its record names the tests written, the spec requirement each one covers, and the reasoning

#### Scenario: The test runner records what was tested and the result
- **WHEN** the test runner executes a suite
- **THEN** its record names what was tested, the pass and fail results, coverage where available, and the
  action taken on the outcome

#### Scenario: The documentation agent records what changed and why
- **WHEN** the documentation agent creates or updates documentation
- **THEN** its record names the documents touched, a summary of the change, and why it was made

#### Scenario: The triage agent records the labels it applied
- **WHEN** the triage or listener agent acts on an item
- **THEN** its record names the item, the labels applied from the allow-list, and the reasoning

#### Scenario: The spec agent records readiness decisions
- **WHEN** the spec or interaction agent drafts or validates a spec
- **THEN** its record names the spec, the readiness verdict, and why

#### Scenario: The merge reviewer records the decision and what it caused
- **WHEN** the merge reviewer returns a verdict
- **THEN** its record holds the verdict, the deciding rule, any protected paths touched, and the action the
  verdict led to

### Requirement: The ledger is durable and private
Records SHALL be exported from the ephemeral run directory to a durable sink that the adopter configures.
The ledger SHALL NOT be written into the repository it governs, and an implementation SHALL refuse and fail
loudly if the configured sink is a public destination. Retention SHALL be adopter-set and SHALL satisfy
"retained and reviewable".

#### Scenario: Records survive the run
- **WHEN** a run that emitted records completes
- **THEN** the records are present in the configured durable sink, not only in the run's working directory

#### Scenario: Writing to the governed or a public repository is refused
- **WHEN** the configured sink resolves to the governed repository or a public destination
- **THEN** the export refuses and reports the misconfiguration rather than publishing the ledger

### Requirement: The adopter owns and hosts the sink
ASDD SHALL operate no service and host no data. Records SHALL be produced inside the adopter's own pipeline
and exported to a sink the adopter owns and controls. The reference binding SHALL be a private sibling
repository, and the contract SHALL equally admit a private object store, a database or service endpoint, or
the adopter's own knowledge platform.

#### Scenario: No data leaves the adopter's control by default
- **WHEN** an adopter enables the ledger
- **THEN** records go only to the sink the adopter configured
- **AND** no ASDD-operated service receives them

#### Scenario: The reference sink needs no extra infrastructure
- **WHEN** an adopter chooses the reference binding
- **THEN** the ledger is appended to a private sibling repository, using its history for append-only
  ordering, its permissions for access control, and its retention for retention

### Requirement: Emission is read-only, export is write-scoped
Records SHALL be emitted in the read-only analysis context, writing only to the run's working directory, and
the export to the sink SHALL run as a separate write-scoped step that reads only ASDD-produced records and
never ingests untrusted content. The sink credential SHALL NOT be exposed to any job that processes
untrusted pull-request content, and SHOULD be scoped to append-only.

#### Scenario: A fork pull request never exposes the sink credential
- **WHEN** a pull request from a fork is analysed
- **THEN** the analysing job holds no sink credential and only writes records to its working directory
- **AND** the export step, which holds the credential, reads only the ASDD-produced records

### Requirement: Integrity and access control
The ledger SHALL be append-only and tamper-evident, with each record carrying the digest of the previous
record so a removal or edit is detectable. It SHALL be access-controlled and treated as being as sensitive
as the code it describes.

#### Scenario: A removed or altered record is detectable
- **WHEN** a record is altered or removed from the ledger
- **THEN** the digest chain no longer verifies and the break is reportable

### Requirement: Pluggable sink, inert by default
ASDD SHALL define the record contract and the sink interface rather than mandate a database, and SHALL
default to no sink, leaving current behaviour unchanged until an adopter opts in.

#### Scenario: Disabled by default changes nothing
- **WHEN** no audit sink is configured
- **THEN** the pipeline behaves exactly as it does today

#### Scenario: A bring-your-own sink satisfies the contract
- **WHEN** an adopter configures their own conforming sink
- **THEN** records are appended to it with the same contract as the reference binding

### Requirement: The ledger is the substrate for the dashboard, knowledge, and training
The ledger SHALL be readable by the governance dashboard, SHALL be the source the knowledge loop derives
curated entries from, and SHALL be exportable as a corpus for optional model training and tuning. It
SHALL remain a record, never a gate: nothing in the ledger approves, blocks, or merges.

#### Scenario: The dashboard renders per-role activity from the ledger
- **WHEN** a ledger is configured and the dashboard is generated
- **THEN** it renders what each agent role did, with verdicts and outcomes

#### Scenario: The ledger never gates a merge
- **WHEN** the ledger contains an adverse record
- **THEN** the merge decision is unaffected and remains with the gates and a human
