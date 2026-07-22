## Why

A project adopting ASDD starts cold. Its agents cannot see the years of institutional knowledge already
sitting in its commit history, merged pull requests, review comments, and closed issues. The operate-layer
session is building that ingestion (PR #17, `openspec/changes/brownfield-adoption`), which already
establishes two boundaries we arrived at independently: history **may** seed knowledge, and seeded history
is **never** written to the audit ledger, because an audit record asserts that an agent action occurred and
a reconstructed one would forge it.

Those are settled and are not restated here. What is missing is the **contract on the knowledge side** for
what a history-derived entry actually is. The knowledge contract (`openspec/changes/knowledge-loop`) assumes
an entry has an emitting agent and lens. A historical entry has neither: no agent judged it, it was
extracted from a record. Without a defined provenance variant, kind vocabulary, privacy rule, and staleness
obligation, an ingester has to invent them, and the two layers drift into two stores.

This change specs that seam so ingestion has one contract to write against.

## What Changes

- A **history-derived provenance variant**: an origin discriminator, the source kind (commit, merged pull
  request, review comment, closed issue), its ref and date, and the ingesting agent recorded separately
  from the claim, so extraction is attributable without asserting an agent judged it.
- **First-class entry kinds**, because the kind drives handling rather than merely labelling it. `rejected`
  and `shipped` in particular: confidently re-proposing an already-rejected approach, and re-flagging
  shipped work as missing, are the two most expensive failures, and they carry the sharpest privacy and
  staleness profiles.
- **Privacy rules specific to history**, which is the load-bearing part. History is what *people wrote*.
  Ingestion must not become a laundering path that turns a private code fact into a public one because it
  arrived via history, and negative knowledge must be about the approach, not the person.
- **Staleness and retirement obligations**, because a history-derived entry can be years old at the moment
  it is created. A stale invariant confidently restated is worse than no knowledge.
- **The authority boundary**: a learned entry never binds on its own. This is a separate axis from
  staleness (whether a claim is still true) and governs whether a claim has force. It matters because
  `convention` is a knowledge kind here while the brownfield-adoption change ships a **declared**
  `conventions:` block that is binding. Without the boundary stated, the failure runs both ways: an agent
  enforces a convention the project abandoned years ago, or, worse, the declared contract is read as one
  more advisory entry and its binding force dissolves into advice. Learned proposes, declared binds, a
  human decides.

## Impact

- Affected specs: knowledge
- Composes with `openspec/changes/brownfield-adoption` (PR #17): that change owns *whether and how* history
  is read and turned into entries and the **declared** `conventions:` contract; this change owns *what an
  entry must look like* once produced and the rule that a learned entry never substitutes for a declaration.
  One store, one contract. It also makes the adopt path well-founded: promotion from learned candidate to
  declared contract, confirmed by a human.
- Extends `openspec/changes/knowledge-loop` rather than replacing it: the existing provenance, privacy
  boundary, advisory-only, and pluggable-store requirements all continue to apply to history-derived
  entries.
- No implementation here. The ingester is the operate layer's to build.
