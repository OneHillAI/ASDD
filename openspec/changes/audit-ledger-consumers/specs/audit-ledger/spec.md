## ADDED Requirements

### Requirement: Every role the loop runs is recordable
The recordable role set SHALL include every role the system runs, the developer among them. The developer
runs as a bring-your-own coding session rather than a deployment recipe, so it SHALL record with a single
append rather than emit automatically, and the ledger SHALL NOT be limited to the roles that run in CI.

#### Scenario: The developer records
- **WHEN** a developer completes a build and appends a record with its role
- **THEN** the record is accepted and chained like any other

#### Scenario: The trail covers the loop, not only CI
- **WHEN** the ledger is read
- **THEN** it can contain records from the developer and the operate agents, not only the CI review lenses

### Requirement: Every run path reaches one sink
A record produced outside CI (an operate agent or a developer run, writing to a local ledger) SHALL be
shippable to the same configured sink the CI review path uses, so the store is one place rather than
several. Shipping SHALL apply the same refusals as the CI export (never the governed repository, never a
public destination, never a broken chain).

#### Scenario: A local run ships to the sink
- **WHEN** an operator ships a local ledger with the sink configured
- **THEN** its records are appended to the same sink the CI review path writes to

#### Scenario: Shipping fails closed
- **WHEN** the configured sink is the governed repository, is public, or its visibility cannot be verified
- **THEN** the ship refuses rather than export, exactly as the CI export does

### Requirement: A training view of the event stream
The ledger SHALL be readable as a training corpus: one example per record, carrying the role, the
reasoning, the action and the outcome, without the chain fields. The corpus SHALL NOT reproduce reviewed
content; where a record holds a digest of what the agent saw, the example SHALL carry the digest, not the
content. The view SHALL be restrictable by role and SHALL read a single file or a synced sink directory.

#### Scenario: The corpus keeps the signal and drops the plumbing
- **WHEN** the corpus view is produced from a ledger
- **THEN** each example carries the role, reasoning, action and outcome
- **AND** it contains no chain hashes and no reviewed content

#### Scenario: A finding's message and code path never reach the corpus
- **WHEN** a corpus example is produced from a review-lens record whose payload holds findings with
  messages and `path:line` locations, and whose target holds the changed paths
- **THEN** the example carries the finding shape (counts, severities, rules) and the refs (repo, pr,
  commit), and it carries neither a finding message nor a code path
- **AND** a field added to a payload later is excluded by default rather than passed through

#### Scenario: The corpus can be restricted to roles
- **WHEN** the corpus view is produced for a named role
- **THEN** only that role's records become examples

### Requirement: A knowledge view of the event stream
The ledger SHALL be readable as knowledge entries in the knowledge layer's shape, carrying origin, kind
and provenance. The view SHALL be selective: a record that carries durable knowledge (an invariant, a
rejected approach, an exemplar) becomes an entry, and a one-off event does not. Producing the entries
SHALL be distinct from ingesting them into a store, and the absence of a running store SHALL NOT block
producing them.

#### Scenario: A durable record becomes a knowledge entry, a one-off does not
- **WHEN** the knowledge view is produced from a ledger holding a review invariant and a test run
- **THEN** the invariant yields an entry carrying its provenance
- **AND** the test run yields no entry

#### Scenario: Entries are produced without a running store
- **WHEN** no knowledge store is deployed
- **THEN** the knowledge view still produces the entries in the defined shape, and ingestion is a separate
  later step
