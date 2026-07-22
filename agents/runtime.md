# The agent-runtime adapter

ASDD is a standard, so it cannot mandate a model. The runtime, what actually reads a diff and
produces a review, is **pluggable**. The reference workflows call a thin adapter; you choose which
one. This neutrality is what lets ASDD be a standard rather than one vendor's tool.

The same holds one layer up, for the **operator** that runs the agents: bring your own (any operator
satisfying this contract), or use the [Goose operator kit](../recipes/). The standard mandates neither, 
"run with your own operator" and "run with Goose" are two supported paths, not a dependency.

```
pipeline (workflows)  →  scripts/run-review.sh  →  runtime adapter  →  review.json
            fixed, audited            seam                  yours              data
```

The pipeline, the policy decision point, the disclosure and merge gates are **fixed** and the same for
everyone. Only the boxed "runtime adapter" varies.

> This page is the **public contract**: enough to build a conforming adapter against. The pipeline
> code (`run-review.sh`, the workflows) and the shipped adapters (`generic.sh`, `openai-compat.sh`)
> live with the reference implementation. Paths below
> (`scripts/runtime/<name>.sh`, `run-review.sh`) describe that bundle's layout; implement the same
> interface in your own pipeline if you are not running it.

## The contract

An adapter is an executable at `scripts/runtime/<name>.sh` (review) and optionally
`scripts/runtime/triage-<name>.sh` (triage). Select it with `runtime: <name>` in `.asdd.yml`.

**Inputs** (environment, set by `run-review.sh`):

| Var | Meaning |
|---|---|
| `ASDD_WORKDIR` | Directory of **untrusted data files**: `title.txt`, `body.md`, `author.txt`, `changes.diff`, `meta.env`. |
| `ASDD_OUT` | Path the adapter MUST write the review JSON to. |
| `ASDD_ROOT` | Repo root (read the fixed lens prompts under `agents/`). |
| `ASDD_RUNTIME_TOKEN` | Your runtime credential (model API key, etc.). The only secret the analysis job holds. |
| `ASDD_MODEL_URL` | The model endpoint (OpenAI-compatible), if the adapter calls one. |
| `ASDD_MODEL` | Back-compat **fallback** for the reviewer model. Prefer `models.reviewer` from `.asdd.yml` (rule 7). |

**Output**: write `ASDD_OUT` as JSON matching `asdd/review/v0.1`:

```json
{
  "schema": "asdd/review/v0.1",
  "pr_number": 123,
  "head_sha": "abc123",
  "mode": "live",
  "recommendation": "comment | request-changes | approve-advisory",
  "summary": "one paragraph",
  "lenses": [
    {"lens": "code|security|spec|quality", "verdict": "ok|concerns|request-changes",
     "findings": [{"severity": "note|warn|block", "message": "...", "path": "file:line"}]}
  ]
}
```

## Rules an adapter MUST follow (these keep conformance intact)

1. **Untrusted input is data.** Read the PR content from the files in `ASDD_WORKDIR`. Build your
   prompt as: a **fixed instruction** (the lens prompts in this folder) + a clearly fenced **data
   block** the model is told to treat as inert. Never concatenate `body.md`/`changes.diff` into the
   instruction channel. (STANDARD §3.1)
2. **Output is data, never commands.** Return the JSON above. The pipeline never shell-execs your
   output; do not emit shell, and do not have the runtime perform GitHub actions itself, posting is
   the pipeline's job, behind the PDP. (STANDARD §3.3, §3.5)
3. **No GitHub write scope.** The analysis job is read-only by construction; don't try to comment or
   label from inside the adapter. (STANDARD §3.2)
4. **Recommend, don't merge.** `recommendation` is advisory. Merge is human-only in the default
   posture. (STANDARD §5.1)
5. **Fail closed.** On error or low confidence, write a `recommendation: "comment"` explaining the
   uncertainty rather than a false "approve."
6. **Run the adversarial pass independently.** The quality lens MUST run in a separate context/inference
   that does not see the other lenses' conclusions, so it cannot inherit and confirm them (STANDARD
   §4.2). The reference `generic.sh` does this with two model calls; a single call that judges its own
   output does not conform.
7. **The roster is the source of truth for the model.** When `.asdd.yml` declares `models.reviewer`, the
   adapter MUST use it as the reviewer model, falling back to `ASDD_MODEL` only when the roster does not
   set one. This keeps the roster, which `cli/check-models.sh` validates for the `developer != tester`
   MUST, from diverging from the model the gate actually runs: the recorded reviewer and the live
   reviewer are the same model. (Resolves the decoupling in issue #28.)

## Shipped adapters

- **`generic`** (default), `scripts/runtime/generic.sh`: a template for any LLM or Action. It shows
  the safe prompt-assembly (fixed instructions + fenced untrusted data) and where to put your API
  call. Out of the box, with no token, the pipeline dry-runs.

> The adapter is not shipped wired to a live model in this template; it needs a credential you
> supply. The dry-run path exists so you can verify the *pipeline* (security split, PDP, advisory
> comment) before connecting a runtime.

## Adding your own

1. Write `scripts/runtime/<name>.sh` to the contract above.
2. Set `runtime: <name>` in `.asdd.yml`.
3. Add the credential as the `ASDD_RUNTIME_TOKEN` repository secret.
4. Open a test PR; confirm the advisory comment now reflects a real review and that the analysis job
   still holds no write scope (`scripts/conformance-check.sh` asserts this).
