# What ASDD is

ASDD, Agentic Spec-Driven Development, is a standard for running a software project with AI agents,
plus a reference implementation of that standard. It is runtime-neutral: it says nothing about which
model or agent platform you use, and a project conforms to it by meeting the MUSTs in
[STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md), not by adopting any particular tool.

## The three rules

Everything in ASDD reduces to three commitments a conforming project makes:

1. **Disclose agents.** If an AI agent helped write a change, the PR and the commit trailer say so.
   Every change stays attributable; there is no hidden AI involvement.
2. **Humans own the merges.** Agents review and recommend. A human approves and merges. Nothing merges
   automatically by default, and protected paths are human-approved permanently.
3. **Quality and security are gates.** Not advisory on the things that matter. The intake gate fails
   hard; the security lens blocks on real findings.

## The layers

ASDD is built in layers so a project can adopt as much as it needs:

| Layer | What it is | Where it lives |
|---|---|---|
| **The standard** | The normative contract (RFC 2119 MUST/SHOULD) a project conforms to | [STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md), [standards/](https://github.com/OneHillAI/ASDD/blob/main/standards) |
| **Govern** | The CI gates: a deterministic intake gate, then a split read-only review and write-scoped publish | `.github/` reference workflows, [guides/adopt-govern](../guides/adopt-govern.md) |
| **Operate** | The agents that do the work (the listener, intake, the review lenses, the test agents, documentation) on a runtime you choose | [agents/](https://github.com/OneHillAI/ASDD/blob/main/agents), [guides/operate-goose](../guides/operate-goose.md), [guides/operate-other](../guides/operate-other.md) |
| **Profiles** (optional) | Add-ons: the spec-driven intake membrane, and an integrity attestation | [standards/spec-driven.md](https://github.com/OneHillAI/ASDD/blob/main/standards/spec-driven.md), [standards/assure.md](https://github.com/OneHillAI/ASDD/blob/main/standards/assure.md) |

The developer agent is always **bring-your-own**. A contributor connects their own coding agent to build
a change, and a deployment runs only the governance and support agents. The one hard rule across
runtimes: the test agents run a different model from whatever wrote the code
(`developer != test_author, test_runner`), so their blind spots do not line up.

## What it builds on

ASDD is deliberately not a new stack. It adopts open pieces that already exist and adds only the
governance they leave out:

| It adopts | ASDD uses it for |
|---|---|
| [AGENTS.md](https://agents.md) | The constitution format every agent reads. ASDD ships one and stays agent-agnostic. |
| [Spec Kit](https://github.github.com/spec-kit/) and spec-driven development | The spec is the artifact and code is a build output. ASDD extends it to the contribution boundary. |
| [MCP](https://modelcontextprotocol.io) | How an agent reaches the deterministic gates (the `asdd-gates` extension) and any other tool. |
| [Goose](https://block.github.io/goose/) | A ready-to-run operate runtime, unmodified and un-forked. Optional: any runtime meeting [agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md) works. |
| [OKGF](https://github.com/OneHillAI/OKGF) | The knowledge format the knowledge lane builds on. |
| DCO sign-off | Provenance on every commit, checked by the intake gate. |

## Its relationship to spec-driven development

ASDD adopts **spec-driven development**, the approach GitHub's [Spec
Kit](https://github.github.com/spec-kit/) popularised, where the specification is the artifact and code
is a build output validated against it. ASDD's spec-driven profile
([standards/spec-driven.md](https://github.com/OneHillAI/ASDD/blob/main/standards/spec-driven.md)) takes that idea and adds what a
multi-contributor project needs on top: a trust membrane where an untrusted submission crosses only as a
validated spec object (submitted code is reference, never an authored diff), a claim protocol so
concurrent contributors do not collide, and a contributor-facing reviewer distinct from the merge gate.
See [prior-art](../prior-art.md) for how ASDD relates to Spec Kit and the rest of the landscape.

## What it is not

ASDD does not auto-merge anything. It does not replace human code review. It does not catch everything
the security lens misses, and it does not remove the need for human judgement on architecture or product
direction. It gives humans better information before they merge, produced under conditions the project
can defend.

Next: [how it works](how-it-works.md), [prior art](../prior-art.md)
