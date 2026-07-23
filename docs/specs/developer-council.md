# Spec: the developer council - 2 to 5 heterogeneous models on one OpenSpec change

Lane: feature. An optional produce-loop developer that implements an OpenSpec change with several diverse
models that propose, cross-critique, synthesize and verify, and always return one result. Opt-in; the
single-model developer stays the default. Runtime-neutral, so it works in every operator kit.

## Outcomes

- A developer that drafts an implementation of an OpenSpec change with **2 to 5 diverse models** (default
  **3**, hard cap **5**), following a bounded **propose to cross-critique to synthesize to verify** loop,
  and always returns **one** synthesized result to the user.
- **Spec-and-test-grounded, not consensus.** Proposers draft against the OpenSpec change's acceptance
  criteria; they cross-critique against those criteria; the lead synthesizes; the change is verified by
  the existing test agents (`test-author` extends the suite from the spec, `test-runner` runs it), on
  models distinct from the council, and one refine round runs on a test failure. The council converges on
  what satisfies the spec and passes the tests, not on what the models agree on.
- **Fixed roles.** N minus 1 **proposers** (diverse families) plus **one lead synthesizer** (the strongest
  model, which produces the answer). A heterogeneity check warns on same-family clones and still enforces
  `developer != test_author, test_runner`.
- **Bring the models two ways:** per-model tokens (the existing per-role provider mechanism, extended per
  council member) or one multi-model provider (an OpenAI-compatible endpoint such as OpenRouter fronting
  several model names). Whichever the operator already has.
- **In every operator kit.** A runtime-neutral reference orchestrator (`asdd dev-council`, over any
  OpenAI-compatible endpoint, a sibling to `run-agent`) that the Goose kit invokes and that a
  bring-your-own runtime implements against the documented contract.
- **The council's process is recorded to the audit log** (STANDARD 1.3): each proposer's approach, the
  cross-critiques, the disagreements, the synthesis rationale and the verify outcome. Because that trail
  flows through `asdd audit corpus` (training) and `asdd audit knowledge` (OKGF pages), the system learns
  from the council's process over time: a rejected proposal becomes a `rejected` OKGF page, the accepted
  rationale an `exemplar` or `invariant`. Content is digested, never stored verbatim, the same as every
  other agent. The disagreements and reasoning are also available to the user on request.

## Scope

- Non-normative: an optional operate-layer capability. It does not change the standard, and it does not
  weaken the independence rules: the council is a **developer**, review and test still run independently on
  different models, and the synthesized change still passes the normal intake and review gates. The council
  never merges and never reviews its own output.

## Acceptance criteria

- Configurable 2 to 5 council models (default 3); the heterogeneity check warns on same-family models and
  fails on `developer == test_author or test_runner`.
- Both provider modes work: per-model token pairs, and a single multi-model provider with a model-name list.
- Bounded by default (1 critique round + 1 test-refine round) with hard caps on rounds and tokens; the cost
  and round count are surfaced to the operator (who brings the tokens).
- Graceful degradation: an unreachable model drops to fewer proposers rather than failing the run; if the
  council cannot reconcile, it surfaces the disagreement rather than forcing a synthesis.
- The verify stage reuses the test agents (`test-author` and `test-runner`) on models distinct from the
  council; a failing verify triggers exactly one refine round.
- Always one synthesized, test-checked result, plus an inspectable council transcript on request.
- Every run records its proposals, critiques, disagreements, synthesis rationale and verify result to the
  audit ledger, so `corpus` and `knowledge` derive from it. No untrusted-input path: the council runs in the
  operator's own produce session, so its inputs are trusted.
- With no model wired, the orchestrator prints a labelled dry run (the prompts still assemble correctly).

### Delivered in every operator kit (an explicit deliverable, not an implication)

- **The orchestrator ships.** `asdd dev-council` is a runtime-neutral reference over any OpenAI-compatible
  endpoint (a sibling to `run-agent`), with its own self-test in the base validation suite.
- **The Goose kit wires it.** The kit ships a concrete way to invoke the council (a recipe or runner) that
  `init --goose` copies, so an adopter runs it with no extra plumbing. `init` completeness is asserted (the
  orchestrator and its Goose wiring actually land at an adopter), the same guard the other agents have.
- **The bring-your-own runtime has the contract.** `agents/runtime.md` documents the council loop (roles,
  the propose to cross-critique to synthesize to verify sequence, the recording obligation) so a custom
  operator implements it conformantly, and `docs/guides/operate-other.md` points to it.
- **Docs surface it on every reference surface** it touches (`cli/README.md`, the operate guide, the
  reference index), so the council is discoverable, not only present.
