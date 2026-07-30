# Prior art: where ASDD sits, and how it differs

ASDD did not invent spec-driven development, agent constitutions, or supply-chain integrity. It composes
with them. This page names the work ASDD builds on and draws the line around what ASDD adds.

## Spec-driven development, and GitHub Spec Kit

The idea that a specification is the source of truth and code is a build output validated against it is
the foundation ASDD stands on. GitHub's [Spec Kit](https://github.github.com/spec-kit/) popularised this
for AI coding: `specify init` scaffolds the flow into a repo, and slash commands (`/speckit.specify`,
`/speckit.plan`, `/speckit.implement`) drive a developer and their agent from a spec to an
implementation.

ASDD adopts that approach in its spec-driven profile
([standards/spec-driven.md](https://github.com/OneHillAI/ASDD/blob/main/standards/spec-driven.md)) and credits it as the lineage. The difference
is what each is centred on:

| | GitHub Spec Kit | ASDD |
|---|---|---|
| Serves | one developer and their agent, authoring in their own repo | a project receiving contributions from many humans and agents |
| Core loop | spec, plan, implement (authoring) | disclose, gate, review, human-merge (governance) |
| Trust boundary | none needed, it is your own repo | the airlock: untrusted submissions cross only as validated specs |
| Attribution | not its concern | disclosure and audit on every agent action |
| Merge authority | not its concern | human-owned by default; protected paths permanently |
| Security of the contribution itself | not its concern | a blocking security lens that treats the diff as adversarial |

They compose. A contributor can use Spec Kit (or any agent) to author a change, and the receiving project
uses ASDD to govern whether that change is trustworthy enough to merge. Spec Kit is the authoring loop;
ASDD is the contribution boundary.

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) is the nearest neighbour, and the overlap is real
enough to name honestly. Both put a spec before code. OpenSpec turns that into a lightweight change
workflow: a proposal in `openspec/changes/<id>/`, spec deltas against the living specs in
`openspec/specs/`, slash commands wired into some 25 coding assistants, and an archive step that folds
an implemented change back into the specs. Its authoring ergonomics, one `npm i -g` and a slash command
in whatever assistant you already run, are the bar ASDD's own CLI and slash commands aim at, and we say
so rather than pretend convergent evolution.

The difference is what happens after the spec exists. OpenSpec ends where the assistant does: it has no
opinion on who may submit, what gets machine-checked before a human looks, or who merges. ASDD begins
there, at the contribution boundary: disclosure, DCO, the deterministic intake gate, adversarial review,
a named human with merge authority. One is an authoring convention; the other is governance with teeth.

They compose, and not just in principle: the intake gate's `spec_paths:` config accepts OpenSpec's
layout (`openspec/changes/*/specs/**/*.md`), so a project can keep OpenSpec as its authoring workflow and
ASDD as its contribution boundary with no migration. ASDD requires that a spec exists and that the
change is checked against it, not that a particular tool produced it.

## Agent constitutions, AGENTS.md

The convention of a repo-root file that tells agents the project's rules, [AGENTS.md](https://github.com/OneHillAI/ASDD/blob/main/AGENTS.md), is
one ASDD adopts directly rather than reinventing. ASDD's contribution is the content: a constitution
whose governance sections (the contract, the gates, the merge rules) are fixed while the
project-specific sections are yours to adapt.

## Agent runtimes, Goose and others

ASDD is runtime-neutral by design ([STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md), [agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md)).
[Goose](https://block.github.io/goose/) (Block, under the Linux Foundation's AAIF) is one operate-layer
runtime ASDD ships a ready-to-run kit for, not a dependency. The same agents run on any runtime that
satisfies the contract. ASDD does not compete with agent runtimes; it governs the work they do.

## Supply-chain integrity: SLSA, in-toto, Sigstore, SBOM

Provenance and build-integrity frameworks answer whether an artifact was built the way it claims. ASDD's
optional Assure profile ([standards/assure.md](https://github.com/OneHillAI/ASDD/blob/main/standards/assure.md)) answers a narrower, adjacent
question, whether a change was authored and reviewed under agent-governance conditions, and is designed
to compose with SLSA, in-toto, Sigstore, and SBOM, not replace them. The attestation binds provenance, a
threat scan, agent identity, and independent review; the build-integrity layer stays whatever the
project already runs.

## Risk and compliance frameworks

ASDD maps its controls to the external frameworks a project is likely to be measured against (the OWASP
agentic risks, NIST, the EU AI Act, ISO 42001) in
[standards/compliance-map.md](https://github.com/OneHillAI/ASDD/blob/main/standards/compliance-map.md). ASDD is not a replacement for those. It is
a concrete, testable way to satisfy the parts of them that concern AI-authored contribution.

## Provenance of authorship: DCO, not a CLA

ASDD uses the [Developer Certificate of Origin](https://developercertificate.org/) sign-off, checked on
every commit by the intake gate, rather than a Contributor License Agreement. The point is attributable
provenance without asking contributors to sign away rights, the same reason disclosure, not gatekeeping,
is the first rule.

## The gap ASDD fills

Each of the above solves a real problem, and none of them governs the contribution boundary for
AI-authored changes end to end: disclosure, a gate that fails hard, review that treats the change as
untrusted, a human merge, and an optional attestation. That specific composition is ASDD.
