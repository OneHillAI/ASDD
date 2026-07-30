# The contribution pipeline

Every contribution, code, docs, an example, a skill, an MCP-server config, runs the same flow. The
ordering and the gates are normative ([STANDARD.md](../STANDARD.md) §6); the runtime that performs the
review is pluggable ([agents/runtime.md](../agents/runtime.md)).

> Workflow/script names below (`pr-review.yml`, `intake-check.sh`, `set-status.sh`, …) name the
> reference implementation in this repository. The flow and gates are
> what conformance requires; the filenames are one way to realize them.

```
submit → intake → multi-lens review → cross-check → merge gate → attribution
```

## 1. Submit
A contributor opens a PR. The template requires a **disclosure** (human vs agent-authored) and a
**DCO sign-off**. Agent-authored commits carry the `Agent:` trailer
([standards/disclosure.md](../standards/disclosure.md)).

## 2. Intake
Cheap checks first, and **mechanically enforced**: not an honor-system checkbox. `intake-check.sh`
runs in its own read-only intake workflow (deterministic, no model) and fails a PR that does not attest
authorship (§1) or sign off every commit (DCO). A failed intake posts the specific fixes as a PR
comment and fails the `ASDD intake` check, and nothing downstream runs. The contributor self-corrects
without a maintainer reading the PR, this is how the bulk of the "1 in 10" noise is filtered, and how
an inbound *undisclosed* agent is stopped rather than waved through.

## 3. Multi-lens review (after intake, advisory)
The `pr-review.yml` workflow runs **read-only** and produces a review artifact. It is triggered by the
intake workflow completing (`workflow_run`) and runs only when intake passed, so a failed intake never
reaches a model and a fork PR still gets a real review. The runtime applies each lens as a named agent
identity:

- **[code](../agents/review-code.md)**: correctness + de-slop.
- **[security](../agents/review-security.md)**: vulnerabilities + supply chain. This lens *gates*.
- **[spec](../agents/review-spec.md)**: matches the spec/issue and the architecture.
- **[quality](../agents/review-quality.md)**: net complexity + the adversarial pass (below).
- **[impact](../agents/review-impact.md)**: does this change the nature of the framework, does it ripple,
  is it version-worthy or a small fix. It classifies every PR and *gates* a normative change that is
  undeclared or missing its impact analysis or target version. A deterministic pass (the reference
  `impact_scan.py`) runs even in dry-run, so the framework is protected before a model is wired.

Each lens returns findings as data. No lens posts to GitHub or merges, the write-scoped
`pr-review-publish.yml` posts a single advisory comment, behind the PDP. Why the split is structured
this way: [standards/security.md](../standards/security.md).

## 4. Cross-check (anti-rubber-stamp)
The documented failure is reviewers converging on "approve", more so for agent code, which *feels*
safer to wave through. ASDD counters it structurally:

- The **quality lens is adversarial by mandate** and runs **independently**: a separate inference that
  does not see the code/security/spec lenses' conclusions, so it cannot inherit and confirm them (the
  reference adapter makes two separate model calls). Its job is to state the strongest case *against*
  merging, or to explicitly record that it found none. That explicit "I tried to refute this and could
  not" is what makes a downstream approval trustworthy.
- A **security `block`** is a hold, independent of the other lenses' verdicts. A majority of cheerful
  approvals does not override one credible security block.
- The merge gate is **majority-skeptic, not majority-rubber-stamp**: agreement is not approval;
  unrefuted scrutiny is.

A change is not presented as merge-ready until the cross-check has run.

## 4b. The record

Each lens outcome, and the review as a whole, is appended to the audit ledger: the agent identity, the
action, the target, the authorizing decision, a timestamp, the reasoning, and what the verdict caused
(STANDARD 1.3). Records are chained so an edit or a deletion is detectable, and are exported to a
private store the project owns; they are never written into the repository being governed. The record
is evidence, never a gate. See [the audit ledger guide](../docs/guides/audit-ledger.md).

## Ship the docs with the change

A change that adds or alters something a person has to find later ships with the documentation that
describes it. A command that merges but appears in no reference is not finished, it is invisible: nobody
learns it exists by reading the source, and the omission stays silent because nothing fails.

Declare the pairs in `conventions.docs`: when a change touches one path pattern, it must also touch one of
the documents that describe it. The conventions gate checks that on every change, and it is diff-scoped
like the rest of that gate, so it asks what THIS change did and never whether the repository's docs are
complete. A project with years of undocumented history can adopt on day one and improve from there.

Nothing is checked until a project declares it, and that is deliberate.

**Why this is not a MUST in [STANDARD.md](../STANDARD.md).** The standard's requirements are governance and
safety properties: disclosure, sign-off, the gates, a human merge, the audit trail. Those are the things
that make agent-produced work trustworthy, and they can be stated the same way for every project. Which
documentation surfaces a project keeps cannot. Some keep a reference site, some a wiki, some only
docstrings. A generic "update the docs" requirement would be unenforceable where it is vague and an
imposition where it is specific, and every new MUST is a conformance burden on existing adopters. So the
framework supplies the mechanism and checks what you declare; the project decides what its documentation
surfaces are.

## 5. Merge gate
- **Default (advisory).** Agents recommend; a **human approves and merges**. No agent is the sole
  approver (STANDARD §5.1).
- **Protected paths.** `CODEOWNERS` + branch protection require a named human owner on auth, crypto,
  CI/release, dependencies, data paths, and the standard/governance docs, regardless of any agent
  verdict, permanently (STANDARD §2.2).
- **Security as a hard gate.** Make `asdd/review` (set by the publish job) a required status
  check. A blocking security finding or a failed intake then mechanically blocks merge for every
  change, not only on protected paths (STANDARD §3.8).
- **Earned auto-merge (later, narrow).** Only after a track record, and only for a positively-declared
  class of trivial, fully-green, non-protected changes (a docs typo, a lint fix). Never on a protected
  path. See [lifecycle.md](lifecycle.md).
- **The merge-reviewer.** The final check is performed by an independent agent on a **different model**
  that never saw the build ([../agents/review-merge.md](../agents/review-merge.md)) - the same
  heterogeneity that separates the tester from the developer. Its default verdict is `human-approve`; it
  may return `autonomous-approve` only for the declared non-protected `auto_merge_class` under
  `posture: earned-automerge`. Protected paths always return `human-approve`; graduating one to
  autonomous is a STANDARD amendment, not a config flag.

## 6. Attribution
On merge, the contribution is attributed to its **human contributor** by name and the contribution
type is recorded (the reference implementation's attribution workflow). The
pipeline is meant to be visible, humans **and** agents, so adoption is verifiable, not asserted.

## Fast feedback
First review should land in minutes, not days; slow first response is the dominant cause of
contributor attrition. The review runs as soon as intake passes and posts when the analysis completes.
