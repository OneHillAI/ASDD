# Guide: run the operate layer on your own runtime

ASDD mandates no runtime. If you do not want to run [Goose](operate-goose.md), you implement the operate
agents on whatever you already run (your own harness, another agent platform) as long as it satisfies the
contract. This guide is the contract and the checklist.

## The contract

[agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md) is the normative runtime contract. An operator conforms when:

1. It runs the governance and support agents (reviewer, tester, documentation, interaction), each defined
   in [agents/](https://github.com/OneHillAI/ASDD/blob/main/agents). The developer is bring-your-own: a contributor connects their own coding
   agent to build a change; the deployment never runs a standing developer.
2. Each agent runs as a named, attributable agent identity (STANDARD §2.1), with disclosure on every
   action (§1) and least-privilege scope (§5).
3. The reviewer model is resolved from the roster (`.asdd.yml` `models.reviewer`, falling back to
   `ASDD_MODEL`), so the model `check-models` validates and the model the gate actually runs cannot
   diverge (agents/runtime.md rule 7).
4. The tester's model differs from the developer's (`developer != tester`). This is the one hard
   cross-runtime rule; a model cannot meaningfully test its own code.

## Wire the gates

The deterministic gates are runtime-independent. Call them directly, or expose them to your agents over
MCP. Both use the same tested scripts as the single source of truth:

```bash
asdd spec-check spec.json              # definition-of-ready gate
asdd claim-check claims.json ...       # claim-protocol decision
asdd merge-eligibility PATHS ...       # the conforming-loader merge floor
asdd check-models --strict             # fails if developer == tester
asdd mcp                               # serve all gates over MCP (stdio, JSON-RPC 2.0)
```

Any MCP client, not only Goose, can consume `asdd mcp`. That is how an agent on your runtime consults the
gates without shelling out.

## Enforce the invariants in your CI

Whatever runtime you run, the govern layer ([adopt-govern](adopt-govern.md)) is the same, and these must
hold: the intake gate runs on every PR, the analysis job stays `contents: read`, publish actions go
through the policy decision point, and `check-models --strict` runs once your fleet's models are set. A
runtime choice never relaxes a MUST in [STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md).

Next: [the runtime contract](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md), [conformance](https://github.com/OneHillAI/ASDD/blob/main/CONFORMANCE.md)
