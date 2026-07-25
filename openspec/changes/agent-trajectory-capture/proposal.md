## Why

Every governed change already runs agents that each read an input and produce an output: a review, a test,
a doc, a synthesis. The audit ledger records that these happened, but only a content-safe digest reaches
it, so the full labelled trajectories, the input paired with the output and the outcome, are discarded at
run end. That trajectory set is the highest-value artefact an agentic software organisation produces.

An organisation pursuing software-development sovereignty should own it. Kept, it is a knowledge base of
how the project actually builds, and, when the organisation chooses, the training data to tune its own
open models and reduce dependence on frontier vendors. The value compounds: every change from day one is a
labelled example, so capturing earlier is strictly better than deciding to capture later. Capture now,
decide training later.

This is the natural companion to the completed audit-trail work: that made the content-safe DIGEST reach
the sink from every agent; this captures the FULL input and output, into a separate, deployment-owned,
never-published store, so the training corpus is possible without weakening the ledger's content-safety.

## What Changes

Add an opt-in **capture** layer, distinct from the governed ledger and off by default.

1. **A capture sink separate from the ledger.** The ledger stays thin (digest plus rationale, shareable);
   the capture sink holds the full input and output per agent call, on a deployment-owned path, never
   published. The two are separate stores with separate rules.
2. **A per-record schema:** role, model, `model_class` (frontier or open), input, output, the change
   context (change id, PR, lane, spec), a content hash, and an outcome label.
3. **Outcome labelling from signals governance already produces.** A record starts `pending`; it becomes
   `positive` when its change merges clean, and `negative` when a later defect names its change through the
   escaped-defect convention (`Escaped-from: #N`). No new human labelling.
4. **Two derived views from the one capture:** a **knowledge** view (wiki / OKGF pages, extending the
   existing synthesis-to-exemplar and rejected-to-rejected derivation, now backed by the full record) and
   a **corpus** view (labelled input-output pairs grouped by role and `model_class`, exportable as training
   records).
5. **Config:** a `capture:` block in `.asdd.yml` (enable, path, roles, redaction, retention), off by
   default. The docs state plainly that the corpus only accrues from when it is enabled, so an adopter
   turns it on at adoption rather than later.
6. **Provider- and host-agnostic, and sovereign.** Capture happens on the ASDD side regardless of where
   the model runs, and `model_class` separates the freely-trainable OPEN rows from the FRONTIER rows a
   vendor's terms may restrict (distilling closed-frontier outputs into open models is a vendor-terms grey
   area; open-to-open is clean).

## Non-Goals

- **No training or tuning in this change.** Capture, label, and export only. Whether and how to train is a
  separate, later decision the captured corpus makes possible.
- **No change to the ledger's content-safety.** The ledger keeps its digest-only rule; capture is a
  separate, private store with its own boundary.
- **No mandated storage backend.** A filesystem path by default; a deployment may point capture elsewhere.

## Impact

- Affected specs: new capability `trajectory-capture`.
- Affected code (later implementation, not this change): the record path (`cli/audit.py` / the runners) to
  also write a full-fidelity capture record when `capture:` is enabled; `cli/audit.py corpus` and
  `knowledge` to read the capture store for the two views; `.asdd.yml` schema for the `capture:` block.
- New config: the `capture:` block; reuses the existing `Escaped-from: #N` outcome signal.
- Privacy: the capture store is deployment-owned and never published; disabled means no behaviour change.
