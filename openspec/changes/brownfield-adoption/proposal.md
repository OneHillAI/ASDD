## Why

ASDD reads as greenfield. `STANDARD.md` 7 only asks that a project can point at where its adoption lives,
and the `CONFORMANCE.md` MUSTs assume they can be satisfied on day one. A mature repository cannot: it
already has a changelog format, a docs layout, protected paths, CI gates, a label taxonomy, a house style,
and thousands of commits that predate every rule.

Most software that could adopt ASDD already exists. If adoption only works from zero, the addressable set
is the smallest slice of the ecosystem.

The failure is concrete, not theoretical. A live adopter running this kit needed a separate, manual
catch-up change to add impact-log entries for two already-merged changes. That is the documentation
agent's job, and the agent could not do it: it does not know that the project keeps an impact log, what
shape an entry takes, or that a changelog **fragment** rather than an edit to the assembled changelog is
the expected artefact. Run stock against a mature repo, the agent emits plausible prose in the wrong place
and a human redoes the work, which is worse than not running it.

Two further gaps follow from the same root. Gates that judged the whole tree would fail a mature repo on
day one, so adoption has to be diff-scoped and ratcheted. And the knowledge layer's cold start is worst
exactly where the cure already exists: an existing project arrives with years of history, merged changes,
review comments and closed issues, which is a far richer corpus than a file tree. The
`agent-audit-ledger` change records what agents do **from now on**; on day one of a brownfield adoption
that ledger is empty, and the project's own history is the record that was already written.

## What Changes

- **A declared conventions contract.** A `conventions:` block names how this project actually ships: spec
  location, changelog form (fragment or direct, with the fragment pattern and category set), the impact
  log it maintains, house style, preflight command, and exemplar changes. It is **declarative** (in
  version control), **injected** (agents read it as an output contract, not advice), and **verifiable**
  (a deterministic gate holds their output to it, so drift fails loudly instead of creating rework).
- **Map, never duplicate.** Where a project already keeps an artefact, ASDD points at it. Adoption never
  creates a second changelog or impact log beside the real one.
- **Diff-scoped gating and a ratchet.** Only the change is judged, never the tree; style is checked on
  added lines only. A repository inherits its existing violations as a baseline and tightens from there.
- **A staged adoption ladder.** `observe` (agents run, output to a log, nothing posted), `advise` (agents
  comment, nothing blocks), `gate` (checks required). Conformance is graded by stage rather than
  pass or fail, so a project can honestly claim a stage while climbing. This formalises what the kit
  already does: the review dry-runs until a model is wired, stays advisory, and binds only once branch
  protection requires the checks.
- **Seeding knowledge from project history.** The onboarding pass may seed from git history, merged
  changes, review comments and closed issues, not only the working tree, including **negative knowledge**
  (what was rejected), an **already-shipped registry** (so built work is not re-flagged as missing), a
  **flake and environment registry**, and **exemplar changes**. Seeded history goes to the knowledge
  layer and is marked history-derived. It is **never** written into the audit ledger: an audit record
  asserts that an agent action occurred, so reconstructing one would forge it.
- **Upgrade without clobbering, and a clean exit.** Framework-owned files are separable from project
  overrides, drift reporting distinguishes "behind" from "deliberately customised", and removal is one
  delete because framework files stay in known paths.
- **Heterogeneity binds forward.** The developer-differs-from-test-author invariant governs new tests; it
  does not retroactively invalidate a suite written before adoption.
- **Security classification at adoption.** The 3 classification runs against the host repository's
  existing workflows, not only against what ASDD adds.

This change ships the conventions contract end to end (declare, inject, verify) and specs the rest.

## Capabilities

### New Capabilities
- `brownfield-adoption`: adopting ASDD into an existing project - a declared conventions contract binding
  agent output, diff-scoped gating with a ratchet, a staged adoption ladder, knowledge seeded from project
  history under a strict boundary against the audit ledger, non-clobbering upgrade, clean exit,
  forward-binding heterogeneity, and security classification of the host repository.

## Impact

- `.asdd.yml` / `.asdd.example.yml`: the `conventions:` block.
- `cli/conventions-check.py`: validate the block, render the contract for an agent, check a change.
- `cli/asdd-mcp.py`: `conventions_check` as an MCP tool so an agent checks its own output before proposing.
- `recipes/documentation.yaml` (and later the developer and test-author recipes): read the contract.
- `cli/doctor.py`: report conventions state in the preflight.
- Docs: a guide for adopting into an existing project.
- Specified for follow-up: the adoption ladder and conformance grading, history seeding, drift reporting
  and clean exit, and the host-repository security classification.
- Interacts with, and does not duplicate: `knowledge-loop` (advisory, retirable) and `agent-audit-ledger`
  (the forward record). Conventions are binding and neither of those is.
