## ADDED Requirements

### Requirement: History-derived entries carry a distinct provenance
A knowledge entry SHALL declare its origin as either agent-emitted or history-derived. A history-derived
entry SHALL carry the source kind (commit, merged pull request, review comment, or closed issue), the
source ref, and the **source date**, and SHALL record the ingesting agent and ingestion time **separately**
from the claim. The emitting agent and lens fields SHALL be absent for a history-derived entry, because no
agent judged it: it was extracted from an existing record.

#### Scenario: A reconstructed claim is not presented as an agent's judgement
- **WHEN** an entry is produced by reading a merged pull request
- **THEN** its origin is history-derived, it names the source kind, ref and date, and it records which agent
  ingested it
- **AND** it does not name an emitting agent or lens, so extraction is attributable without asserting that
  an agent decided the claim

#### Scenario: Origin is queryable
- **WHEN** a consumer reads the knowledge base
- **THEN** it can distinguish history-derived entries from agent-emitted ones without inspecting free text

### Requirement: Entry kinds are first-class
An entry SHALL carry a kind from a defined vocabulary, at minimum `rejected` (an approach that was
considered and turned down), `shipped` (work already implemented), `flake` (an unreliable test or
environment), `exemplar` (a change worth imitating), `convention` (an observed practice the project appears to
follow) and `invariant` (a property the system appears to hold). The vocabulary SHALL be
extensible by the adopter. The kind SHALL drive handling, not merely label the entry: retirement horizon and
privacy treatment follow from it.

#### Scenario: The costly failures are directly queryable
- **WHEN** an agent is about to propose an approach or report work as missing
- **THEN** it can query `rejected` and `shipped` entries specifically, rather than searching free text

#### Scenario: Kind drives handling
- **WHEN** entries of different kinds are retained
- **THEN** each is subject to the retirement horizon and privacy treatment defined for its kind

### Requirement: Learned knowledge proposes, only a declared contract binds
A knowledge entry SHALL NOT constrain agent output on its own authority, whatever its kind. Where the
project declares a binding contract (the declared `conventions:` block established by the
brownfield-adoption change), only that declaration SHALL bind. A `convention` entry SHALL be treated as a
**candidate for declaration**, never as a substitute for one: an agent MAY surface it as a proposal ("this
project appears to do X, consider declaring it") and SHALL NOT enforce it. Promotion from a learned
candidate to a declared contract SHALL be a human decision. The same holds for `invariant`: a learned
invariant informs, it does not bind.

This is a separate axis from staleness. Staleness governs whether a claim is still **true**; this governs
whether a claim has **force**. A learned convention can be both current and non-binding.

#### Scenario: A learned convention is surfaced, not enforced
- **WHEN** an agent retrieves a `convention` entry that the project has not declared
- **THEN** it may propose the convention for declaration
- **AND** it does not require the change under review to conform to it

#### Scenario: A declaration keeps its binding force
- **WHEN** a declared convention and a learned `convention` entry both exist
- **THEN** the declared contract binds agent output
- **AND** the learned entry does not weaken, override, or stand in for it

#### Scenario: Promotion is a human decision
- **WHEN** a learned convention is promoted to the declared contract
- **THEN** a human confirms the change before it binds

### Requirement: History-derived entries inherit the source's sensitivity
A history-derived entry SHALL inherit the sensitivity of the repository it was drawn from, and the
`spec_context` boundary SHALL apply to it exactly as to a live observation. Ingestion SHALL NOT become a
path by which a private code fact becomes reachable on a public surface merely because it arrived via
history.

#### Scenario: History is not a laundering path
- **WHEN** a project is configured `spec_context: docs` for a public contribution surface
- **THEN** a code fact derived from commit history or a private review thread is no more reachable than the
  same fact observed live

### Requirement: A person's words are referenced, not reproduced
History is what people wrote. An entry derived from a review comment, commit message, or issue thread SHALL
capture the claim and cite the source ref as its attribution, and SHALL NOT reproduce the person's words
into any surface where the source itself is not accessible to the reader. An entry SHALL NOT become a
durable characterisation of a named individual.

#### Scenario: The claim travels, the person's words do not
- **WHEN** an entry is derived from a review comment
- **THEN** it records the claim and the source ref
- **AND** it does not carry the comment text into a surface where a reader could not already read the
  comment

### Requirement: Negative knowledge is about the approach, never the person
A `rejected` entry SHALL record the approach, the decision, and the rationale **as it was recorded**,
attributed to its source ref. It SHALL NOT editorialise about the author, infer competence or intent, or
attribute the rejection to a person rather than to the decision.

#### Scenario: A rejection is stated as a decision, not a judgement of someone
- **WHEN** an entry records that an approach was turned down
- **THEN** it describes the approach and the recorded rationale
- **AND** it contains no assessment of the person who proposed it

### Requirement: Entries derived from personal content are retirable
Where an entry derives from content a person authored, it SHALL be retirable, and retirement SHALL be
possible when the source is redacted, deleted, or withdrawn upstream.

#### Scenario: An upstream redaction can be honoured
- **WHEN** the source comment or issue is deleted or redacted
- **THEN** the derived entry can be retired without rewriting or invalidating the rest of the store

### Requirement: A history-derived claim is verified before it is relied on as fact
A history-derived entry is a claim about the past and SHALL be treated as such. Before an agent relies on
one as current fact, it SHALL verify the claim against current state. This obligation is strongest for
`rejected` and `shipped`: an approach rejected under old constraints may now be correct, and shipped work
may since have been reverted.

#### Scenario: A stale rejection does not silently block a good idea
- **WHEN** an agent retrieves a `rejected` entry whose source predates the current constraints
- **THEN** it verifies whether the rejection still holds before treating the approach as closed
- **AND** it surfaces the entry as historical context rather than as a current decision

#### Scenario: A shipped claim is checked against the tree
- **WHEN** an agent retrieves a `shipped` entry
- **THEN** it confirms the work is still present before reporting it as implemented

### Requirement: Supersession and retirement without rewriting the store
An entry SHALL be retirable and supersedable. A newer entry or a live observation SHALL be able to supersede
an older history-derived one, and retirement SHALL be recorded rather than performed by deleting history, so
provenance survives.

#### Scenario: A live observation supersedes an old claim
- **WHEN** current observation contradicts a history-derived entry
- **THEN** the older entry is marked superseded and is no longer served as current
- **AND** it remains inspectable, with its provenance intact
