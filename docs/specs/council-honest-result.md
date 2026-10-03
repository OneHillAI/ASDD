# Spec: the council's result says what actually happened

Lane: fix. The developer council returned a result that read as a clean, verified synthesis when it was
not, and recorded it that way in the ledger the corpus and knowledge base are built from. Two live runs
(opus-4-8 and gemini-3-1-pro proposing, gpt-5.6 leading, through one runtime) showed it.

## Outcomes
- A lead that returns nothing is named. A reasoning model can spend its whole token budget on hidden
  reasoning and return no text (finish reason `length`). The orchestrator fell back to the first proposal
  without saying so, so the "synthesis" was byte-identical to proposal 1. The header and transcript now say
  the lead failed and which proposal stands in, and the ledger records `error`.
- A result nothing verified is named. With no test runner wired, verification returned a pass, and the
  header ("verify passed"), the ledger (`pass`) and the knowledge view (an `exemplar`) all treated it as
  checked. It is now reported as NOT VERIFIED and recorded as `unverified`.
- A member that gives no answer, and any proposal or synthesis cut off at the token cap, are named in the
  header and transcript instead of vanishing or being passed on as a complete draft.
- Nothing that is a fallback, unverified or cut off is recorded as a `council-synthesis` exemplar, so the
  knowledge base does not learn from a result that was never a verified synthesis.
- A model that stopped at the token cap with no text is not retried: the same call would spend the same
  budget again.
- An operator can lower a reasoning model's spend with an optional `dev_council.reasoning_effort`, sent on
  every council call. Unset, nothing is sent and behaviour is unchanged.

## Scope

In:
- **`cli/dev-council.py`**: a reply type that carries whether the call was cut off and why it failed; the
  result header; the ledger verdict (`error`, `unverified`, `pass`, `changes-requested`); the exemplar
  guard; no retry of an empty length-stopped call; `reasoning_effort`.
- **Tests** in `cli/dev-council.test.sh`, driven by a stub model server, and the docs: `cli/README.md`, the
  operate guide, and the developer-council spec.

Out:
- Changing which models the council uses, the round limits, or how the lead is chosen.
- Retrying a lead that failed, or promoting a different proposal to lead.

## Constraints
- Zero-dependency (stdlib only), as the orchestrator already is, and no change to any network call beyond
  the optional `reasoning_effort` field.
- A run is still always one result and still exits 0: the council produces a draft for a human to review,
  and the honesty is in what the result says about itself, not in refusing to return one.
- The ledger stays content-safe (counts, verdicts and digests, never the drafted code). The two new verdict
  values, `error` and `unverified`, are free-form strings in the ledger's verdict field.
- Slop gate clean (no em/en dashes). British spelling in prose.

## Verification
- `cli/dev-council.test.sh` (already registered in `validation/run-base.py`) runs the real orchestrator
  against a stub model server: a failed lead is named in the header and transcript, recorded `error`, earns
  no exemplar, and is not retried; a healthy verified run is not mislabelled; no test runner wired reads
  NOT VERIFIED and is recorded `unverified`; a failed verification still reads FAILED; a cut-off proposal
  and a cut-off synthesis are flagged; a silent member is named; `reasoning_effort` reaches every council
  call when set and is absent otherwise. Run against the unpatched orchestrator these cases fail, and the
  unpatched output reads "verify passed" for a failed lead and for an unverified result.
- Full deterministic suite stays green.
