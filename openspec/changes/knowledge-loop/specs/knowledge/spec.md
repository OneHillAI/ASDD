## ADDED Requirements

### Requirement: Onboarding learning pass
On adoption, ASDD SHALL run a bounded, cost-capped learning pass that has the agents read the codebase and
seed the knowledge base, and the pass SHALL be re-runnable and incremental.

#### Scenario: Seed the knowledge base on adoption
- **WHEN** ASDD is first applied to a project with the knowledge layer enabled
- **THEN** a learning pass seeds the knowledge base with structure, conventions, and invariants
- **AND** the pass stays within its declared token or file budget and logs what it skipped

#### Scenario: A second run is incremental
- **WHEN** the onboarding pass is run again on the same repository
- **THEN** it updates only what changed rather than performing a full re-sweep

### Requirement: Knowledge emission loop
Every review, documentation, and test agent run SHALL emit structured knowledge as a by-product, and later
runs SHALL be able to read it as grounding.

#### Scenario: A review run emits and later reads knowledge
- **WHEN** a review agent verifies a claim or relies on an invariant during a run
- **THEN** it emits a knowledge entry for that claim
- **AND** a subsequent review, test-authoring, or spec run retrieves relevant entries as grounding

### Requirement: Provenance on every entry
Every knowledge entry SHALL carry lineage identifying its source agent and lens, and the run, pull request,
and commit it came from, so a wrong or stale claim can be found and retired.

#### Scenario: An entry is attributable
- **WHEN** any agent emits a knowledge entry
- **THEN** the entry records the emitting agent and lens and the originating run, pull request, and commit

### Requirement: Grounding is advisory only
The knowledge layer SHALL be advisory. It SHALL NOT gate a merge, set a required status, approve, or hold
write scope over the repository.

#### Scenario: Knowledge does not gate
- **WHEN** the knowledge base contains an entry that contradicts a change
- **THEN** the merge decision is unaffected and remains with the deterministic gates and a human

### Requirement: Pluggable knowledge layer
ASDD SHALL define the knowledge contract rather than hard-vendor a store, SHALL provide OKGF as the
reference binding, and SHALL default to `knowledge.tool: none`, which leaves the pipeline unchanged.

#### Scenario: Disabled by default leaves the pipeline unchanged
- **WHEN** `knowledge.tool` is `none`
- **THEN** the pipeline output is identical to a build with no knowledge layer

#### Scenario: A bring-your-own store is swappable
- **WHEN** an adopter sets `knowledge.tool: byo` with a conforming store
- **THEN** the read and write path behaves equivalently to the OKGF reference binding

### Requirement: Privacy boundary
The knowledge layer SHALL inherit the sensitivity of the code it is drawn from, and under
`spec_context: docs` the knowledge agents SHALL NOT read or expose a codebase file.

#### Scenario: A public surface cannot mine internals
- **WHEN** the project is configured `spec_context: docs` and an untrusted contributor interacts
- **THEN** no code-derived fact enters or leaves the knowledge base through that path

### Requirement: Optional bring-your-own training
ASDD SHALL NOT train models itself, and SHALL make the knowledge corpus available for an adopter to train
their own model only when `knowledge.train: byo` is set.

#### Scenario: Training stays off by default
- **WHEN** `knowledge.train` is unset or `off`
- **THEN** ASDD performs no model training and only maintains the corpus
