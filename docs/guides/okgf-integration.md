# Guide: OKGF as the knowledge layer

ASDD governs how a change is made. **OKGF (the Open Knowledge Governance Framework) is the knowledge
standard ASDD adopts** for what an agent system learns and reuses. The two connect through one seam: ASDD
records what its agents did, and the durable, reusable part of that becomes OKGF knowledge a later run can
retrieve.

ASDD does not ship a knowledge store. It **conforms to OKGF's format** so any OKGF store ingests ASDD's
knowledge with no translation. Running a store, and pointing agents at it, is the adopter's step.

## The seam: ASDD emits OKGF pages

`asdd audit knowledge` reads the audit ledger and emits the durable entries (a review invariant, a rejected
approach, an exemplar) as **real OKGF pages**, not an ASDD-specific shape:

```bash
asdd audit knowledge --ledger /path/to/synced-sink/ledger --out ./knowledge
```

Each file in `./knowledge` is an OKGF page: a required `type`, an `x-okgf-scope`, `x-okgf-review: draft`,
the provenance in `x-okgf-sources`, and the agent's reasoning as the body. The output is validated against
OKGF's own conformance rules, so it cannot drift from the standard. There is no adapter: an OKGF store
ingests these pages directly.

A one-off event (a passing test run, a doc sync) produces no page; only what a later run should be able to
learn from is emitted. Content is never leaked: a page carries the reasoning and its provenance, never the
reviewed code or a finding's file paths.

## The lifecycle: draft to approved

Agent-emitted knowledge enters the store as `draft`. It is a claim, not yet authoritative. A human (or a
governed process in the store) moves it `draft` to `proposed` to `approved`; on approval the store signs it.
Only `approved` pages are authoritative, so an agent's unreviewed claim never reaches trusted retrieval on
its own. This mirrors ASDD's own posture: an agent proposes, a human decides.

## Ingesting into a store

The store owns ingest. With a running OKGF store, load the emitted pages into its bundle (drop the files in,
or use the store's import), then propose and approve them through its review lifecycle. See the store's own
`STORE.md` for the ingest API and the CLI (`add`, `propose`, `approve`).

A periodic job is the usual shape: export the knowledge from the synced ledger, ingest it, and let a human
approve. That job is a deployment concern (it needs the store's address and a write token), so it lives with
the deployment, not in this framework.

## Retrieval: agents read only approved knowledge

Point operate agents at the store for reviewed, attributed knowledge. The store returns only what has been
approved when asked for it:

```
GET /pages?scope=org&review=approved&tier=gold
```

Each result carries its provenance and a signed flag, so an agent consumes trusted knowledge and can trace
where it came from. Give a produce-loop agent (a coder, a spec author) the approved knowledge for its scope
so it reuses what the system has already learned instead of rediscovering it.

## What lives where

- **This framework (the kit):** the exporter (`asdd audit knowledge`) that emits conformant OKGF pages, and
  this integration note. That is ASDD's whole responsibility: produce OKGF, correctly.
- **The store (OKGF):** ingest, the review lifecycle, signing, and retrieval.
- **The deployment:** running a store, the periodic export-and-ingest job with its token, and pointing
  agents at the retrieval endpoint.

Next: [the audit ledger](audit-ledger.md) it derives from.
