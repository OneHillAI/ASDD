## ADDED Requirements

### Requirement: A full-fidelity capture sink distinct from the ledger
The system MUST support an opt-in capture store, separate from the governed audit ledger, that holds the
full input and output of each agent call. It MUST be deployment-owned and never published: it MUST refuse
a public destination and MUST NOT be written to the governed repository, reusing the ledger export's
refusals. The governed ledger MUST keep its digest-only content-safety unchanged; capture is a separate
store with its own boundary. When capture is disabled there MUST be no behaviour change.

#### Scenario: Capture is separate from and does not weaken the ledger
- **WHEN** capture is enabled
- **THEN** the full input and output are written to the capture store, and the ledger still receives only
  its digest and rationale
- **AND** the capture store refuses a public or same-repo destination the way the ledger export does

#### Scenario: Disabled is inert
- **WHEN** no `capture:` block is configured, or it is disabled
- **THEN** no capture record is written and behaviour is exactly as before

### Requirement: Per-record capture schema with model class
Each capture record MUST carry: the agent role, the model, a `model_class` of `frontier` or `open`, the
input, the output, the change context (change id, PR number, lane, spec reference where available), a
content hash, and an outcome label. `model_class` MUST let an export separate the freely-trainable OPEN
rows from the FRONTIER rows whose provider terms may restrict reuse.

#### Scenario: A record carries the fields a corpus export needs
- **WHEN** an agent call is captured
- **THEN** its record has role, model, `model_class`, input, output, change context, content hash, and an
  outcome label
- **AND** an export can select only `model_class: open` rows for training without hand-filtering

### Requirement: Outcome labelling from governance signals
The outcome label MUST be derived from signals governance already produces, not new human labelling. A
record MUST start `pending`; it MUST become `positive` when its change merges clean; and it MUST become
`negative` when a later defect names its change through the escaped-defect convention (`Escaped-from: #N`).
A record MUST NOT be given a false label from an absent signal: with no merge and no defect link it stays
`pending`.

#### Scenario: The label follows the change's real outcome
- **WHEN** a captured change merges with no later escaped-defect link
- **THEN** its capture records are labelled `positive`
- **WHEN** a later defect names the change via `Escaped-from: #N`
- **THEN** its records are relabelled `negative`
- **WHEN** neither signal has occurred yet
- **THEN** the records stay `pending`, never a fabricated label

### Requirement: Two derived views from one capture
From the one capture store the system MUST derive two views: a **knowledge** view (wiki / OKGF pages,
extending the existing synthesis-to-exemplar and rejected-to-rejected derivation, now backed by the full
record) and a **corpus** view (labelled input-output pairs grouped by role and `model_class`, exportable as
training records). Both MUST read the same capture store; neither view is a second source of truth.

#### Scenario: Knowledge and corpus both derive from the capture
- **WHEN** the capture store holds labelled records
- **THEN** the knowledge view emits pages and the corpus view emits labelled input-output pairs grouped by
  role and `model_class`, both from that one store

### Requirement: Opt-in, off by default, within the privacy boundary
Capture MUST be opt-in through a `capture:` block in `.asdd.yml` (enable, path, roles, redaction,
retention), off by default. It MUST write only within the deployment's privacy boundary, and MUST capture
the input-output pair regardless of where the model runs (provider- and host-agnostic). The documentation
MUST state plainly that the corpus only accrues from when capture is enabled, so an adopter turns it on at
adoption rather than expecting retroactive history.

#### Scenario: Off by default, and honest about accrual
- **WHEN** an adopter has not configured `capture:`
- **THEN** nothing is captured
- **WHEN** an adopter enables it
- **THEN** capture begins from that point, the docs having stated the corpus does not include prior runs
