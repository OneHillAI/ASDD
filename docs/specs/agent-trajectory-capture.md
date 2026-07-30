# Spec: agent trajectory capture (the data-generation layer)

Builtin-format mirror of the OpenSpec change
[`agent-trajectory-capture`](../../openspec/changes/agent-trajectory-capture/). The change's `proposal.md`
and `specs/trajectory-capture/spec.md` carry the full requirements and scenarios; this file satisfies the
repo's builtin spec gate and states the problem, requirements, and acceptance in brief.

## Problem

Every governed change runs agents that read an input and produce an output, but only a content-safe digest
reaches the ledger, so the full labelled trajectories, the highest-value artefact an agentic organisation
produces, are discarded. An organisation pursuing software-development sovereignty should own that data: a
knowledge base of how the project builds, and, when it chooses, the training data to tune its own open
models. Value compounds, so capturing from day one is strictly better than deciding later.

## Requirements

1. An opt-in capture store, separate from the ledger, holding the full input and output of each agent call;
   deployment-owned, never public (reusing the ledger export's public/same-repo refusals); the ledger keeps
   its digest-only content-safety; disabled means no behaviour change.
2. A per-record schema: role, model, `model_class` (frontier|open), input, output, change context (id, PR,
   lane, spec), content hash, outcome label.
3. Outcome labelling from governance signals: start `pending`, `positive` on a clean merge, `negative` when
   a defect names the change via `Escaped-from: #N`, never a false label from an absent signal.
4. Two derived views from the one store: knowledge (wiki/OKGF pages) and corpus (labelled input-output
   pairs grouped by role and `model_class`, exportable as training records).
5. Opt-in via a `.asdd.yml` `capture:` block, off by default, within the deployment's privacy boundary,
   capturing regardless of provider or host; the docs state the corpus accrues only from when enabled.

Non-goals: no training or tuning in this change (capture, label, export only); no change to the ledger's
content-safety; no mandated storage backend (a path by default).

## Acceptance criteria

- Disabled is inert; an enabled capture writes the full record with `model_class`.
- The label transitions `pending` to `positive` to `negative` on the real signals and never fabricates one.
- Knowledge and corpus both derive from the same capture store.
- The capture store refuses a public or same-repo destination.
- An export can select only `model_class: open` rows without hand-filtering.
