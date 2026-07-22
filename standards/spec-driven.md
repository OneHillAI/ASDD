# ASDD: Spec-Driven Contribution (normative module)

**Agentic Spec-Driven Development (ASDD)** is the spec-driven profile of this standard: the code is a
build output, the **spec is the artifact**, and agents author under human governance. This module is
normative. It extends [STANDARD.md](../STANDARD.md), §3 (security), §4 (quality), and §6 (the
contribution pipeline), with the contracts that make concurrent, multi-contributor development safe:
a spec-object intake gate, the trust membrane, two-tier contributor identity, the claim protocol, and
the split between contributor-facing and governance review.

Like the rest of the standard it is **runtime-neutral** (no model or agent platform),
**channel-neutral** (no submission surface), and **identity-provider-neutral** (no specific login).
Anything that names a channel, a login provider, or a listing surface is an implementation choice, not
part of ASDD. A project that meets every MUST here and in STANDARD.md MAY describe itself as
**"ASDD compliant (v0.1)"**.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## Terminology (extends STANDARD.md §Terminology)

- **Spec object**: a structured, schema-valid record of a unit of work: its outcomes, scope
  boundaries, constraints, prior decisions, task breakdown, and verification criteria, plus a category
  and a priority. It is the *only* artifact that crosses the trust membrane inward (M.1).
- **Definition of ready**: the declared set of spec-object fields that MUST be present and non-empty
  before a work item may be built. Each project declares its own set; ASDD mandates a floor (SD.2).
- **Trust membrane** (the *intake boundary*), the boundary between the untrusted contribution side
  and the trusted development side (the codebase, the knowledge base, the model runtime). It realizes
  STANDARD §3.1 as an architecture: untrusted content stays out; a validated spec object crosses.
- **Authoring identity**: an identity capable of certifying the DCO (a real human). Required to have
  code merged (ID.1).
- **Proposing identity**: any attributable identity. Sufficient to submit a spec, optionally with
  reference code (ID.2).
- **Reference code**: code supplied by a contributor as part of a proposal. It is untrusted input
  (STANDARD §Terminology) and is treated as data, never as an authored diff (M.2).
- **Contributor reviewer**: the advisory review role that suggests changes *to the contributor* to
  bring a change to "ready" (§RR). Distinct from the governance/merge reviewer.
- **Governance reviewer**: the gating review role (the merge-reviewer and the review lenses,
  STANDARD §4, §6). Recommends to a human; it is the inner barrier of the membrane.

---

## SD. Spec-driven intake (the SDD core)

- **SD.1 (MUST)** Before any code is built for a contribution, intake MUST produce a **spec object**
  that meets the project's declared **definition of ready**. A contribution without a ready spec is not
  eligible to be built or claimed; it stays in a `needs-clarification` state.
- **SD.2 (MUST)** The definition of ready MUST require, at a floor: **outcomes**, **scope boundaries**,
  **constraints/prior decisions**, and **verification criteria**. A project MAY require more; it MUST
  NOT drop below this floor.
- **SD.3 (MUST)** Intake MUST **categorize** and **prioritize** each contribution. The category and
  priority are fields of the spec object.
- **SD.4 (MUST)** The completeness check MUST be explicit: a spec object either meets the definition of
  ready or it does not, and the deciding state MUST be recorded (auditable, STANDARD §1.3).
- **SD.5 (SHOULD)** Where the contribution arrives underspecified, the spec agent SHOULD converse
  with the contributor (human or agent) to fill the gaps, cross-checking the project's own public
  documentation, until the spec meets the definition of ready. See [../agents/intake.md](../agents/intake.md).

## M. The trust membrane (the airlock)

The membrane is the architecture that realizes STANDARD §3.1 ("untrusted input is data, never
instructions"). Two named agent roles hold it: the **spec agent** (outer barrier) and the
**governance reviewer** (inner barrier).

- **M.1 (MUST)** The **only** artifact that crosses the membrane inward is a schema-valid spec object
  (and, downstream, a change that has passed governance review). Raw, free-form contribution content
  (issue/PR/chat text, comments, external URLs, submitted files) MUST NOT cross the membrane as
  instructions to any agent that holds write capability or reaches the knowledge base.
- **M.2 (MUST)** **Submitted code is reference data, never an authored diff.** A developer agent MAY
  read reference code as a hint but MUST re-derive the implementation from the spec object. Reference
  code MUST NOT be committed or merged as an authored change without passing the full pipeline:
  developer (re-authoring) → tester → governance review → merge gate (STANDARD §6). This closes the
  obvious attack, a contributor submitting subtly harmful "helpful" code hoping it is merged verbatim.
- **M.3 (MUST)** The knowledge base (wiki/spec store) and the model runtime sit **inside** the
  membrane. The untrusted side MUST reach them only through a governed, read-only, scoped consumer that
  exposes a sanitized view, never the internal store directly.
- **M.4 (SHOULD)** A project SHOULD name the two barrier roles explicitly in its agent roster so the
  boundary is auditable, not implicit.

## SA. Source-agnostic intake

- **SA.1 (MUST)** A contribution MAY enter from **any** channel. The spec-object contract (SD) and the
  membrane (M) apply identically regardless of how the contribution arrived.
- **SA.2 (MUST NOT)** ASDD MUST NOT mandate a specific submission channel, listing surface, or
  contributor-facing product. Those are implementation choices (an adopter MAY expose a web form, a
  chat, an issue tracker, or nothing beyond pull requests, and still conform).

## ID. Two-tier contributor identity

- **ID.1 (MUST)** An **authoring identity** (DCO-capable, i.e. a real human who can sign off) is
  REQUIRED for a change to be **merged** as code. A machine MUST NOT certify the DCO.
- **ID.2 (MAY)** A **proposing identity** (any attributable identity) is sufficient to **submit a
  spec**, optionally with reference code.
- **ID.3 (MUST)** The absence of an authoring identity MUST NOT block a *proposal* from progressing.
  The pipeline MAY carry a ready spec forward via agent authoring; the resulting change is attributed
  to the proposer and a human certifies the DCO at merge (ID.1).
- **ID.4 (MUST)** Attribution to the originating contributor MUST be preserved end-to-end (STANDARD
  §6.5), AI involvement MUST be disclosed (STANDARD §1), and a human MUST certify the DCO before merge.
- **ID.5 (MUST NOT)** ASDD MUST NOT mandate a specific identity provider. "DCO-capable" and
  "attributable" are the requirements; which provider satisfies them is an implementation choice.

## OP. Operating roles (the developer is bring-your-own)

The runtime counterpart of the two-tier identity: whoever brings the change brings the build capability.

- **OP.1 (MUST)** The **developer**: the agent that authors a change, is **supplied by the
  contributor**, not by the deployment. An external contributor connects their own coding agent, or the
  maintainer connects theirs; a deployment does not run a standing developer agent.
- **OP.2 (MUST)** A deployment provisions and operates the **governance and support** agents, intake
  and interaction ([../agents/intake.md](../agents/intake.md), [../agents/interaction.md](../agents/interaction.md)),
  the review lenses and the merge-reviewer (the gate), the **tester**, and the documentation agent, 
  not the developer.
- **OP.3 (MUST)** `developer != tester` (RR.3) is satisfied by the **deployment's tester** running a
  model distinct from whatever the contributor used to build the change: the project independently
  tests rather than trusting a self-test.
- **OP.4 (SHOULD)** A deployment SHOULD document that the developer is bring-your-own and name the
  governance/support models it operates, so a contributor knows what the project runs versus what they
  bring.
- **OP.5 (MUST)** "Operates" in OP.2 is not met by wiring alone. Before a deployment claims readiness,
  each provisioned governance/support agent MUST be demonstrated performing its role on a real artifact:
  the merge-reviewer on a real PR, the tester reporting a real pass or fail (whichever executor runs the
  tests), the documentation agent producing a correct update for an actual change, and the interaction
  agent answering from project knowledge and routing one idea through intake. Readiness is the whole
  provisioned roster proven, not the reviewer alone. The developer is exempt (OP.1).

## CL. Assignment and the claim protocol

The claim protocol is how concurrent contributors avoid duplicate and colliding work. It operates on
the spec, before code exists.

- **CL.1 (MUST)** A work item with a ready spec (SD.1) is **claimable**. An item without a ready spec
  MUST NOT be claimable.
- **CL.2 (MUST)** A claim is **identity-bound** and there is **at most one active claim per work item**.
  A project MAY limit the number of concurrent claims per identity.
- **CL.3 (MUST)** Claims are **time-boxed** and MUST auto-release on expiry, returning the item to the
  claimable pool. Stale claims MUST NOT block the work indefinitely.
- **CL.4 (SHOULD)** Claiming SHOULD require the item to be both ready and unclaimed, and SHOULD be
  recorded in the audit trail (STANDARD §1.3).

## RR. Two review roles (contributor-facing vs governance)

STANDARD §4 and §6 define the governance review (the gate). ASDD adds a *second, distinct* review role
that faces the contributor.

- **RR.1 (MUST)** A contribution passes through two **distinct** review roles: a **contributor
  reviewer** (advisory, it proposes changes that the *contributor* accepts or rejects to bring the
  change to "ready") and the **governance reviewer** (the gate, STANDARD §4, §6).
- **RR.2 (MUST)** The contributor reviewer MUST NOT be the merge gate. Reaching "ready" is **not**
  approval; a ready change still passes governance review and the merge gate (STANDARD §6.4).
- **RR.3 (MUST)** The governance reviewer and the tester MUST run on models **distinct from the
  developer** (the heterogeneity invariant; this promotes STANDARD §4.2's independence requirement to
  an explicit model-distinctness MUST). A different model family is preferred. Enforced at config time
  by `cli/check-models.sh`.
- **RR.4 (SHOULD)** Contributor-reviewer suggestions SHOULD be posted where the submitter resolves them
  (e.g. review comments), and the resolution SHOULD be recorded. See
  [../agents/review-contributor.md](../agents/review-contributor.md).

---

## The spec-driven pipeline (extends STANDARD.md §6)

STANDARD §6 is `submit → intake → multi-lens review → cross-check → merge gate → attribution`. ASDD
inserts the spec-object gate and the claim step, and names the two review roles:

```
submit (any channel) → intake → SPEC (definition of ready) → claim
  → build (re-derive from spec) → contributor review → governance review → cross-check
  → merge gate → attribution
```

The ordering and the gates are normative; the runtime, the channel, and the identity provider are not.

## Conformance additions

A project claiming **ASDD compliant (v0.1)** meets every MUST in STANDARD.md **and**: SD.1-SD.4, M.1-M.3,
SA.1-SA.2, ID.1, ID.3-ID.5, OP.1-OP.3, OP.5, CL.1-CL.3, RR.1-RR.3. The SHOULDs (SD.5, M.4, OP.4, CL.4, RR.4,
ID.2) are strongly encouraged and tracked. Add these rows to [../CONFORMANCE.md](../CONFORMANCE.md).

## Relationship to STANDARD.md

This module is additive and normative. It does not relax any STANDARD MUST; it tightens two (§3.1
becomes an architecture via M; §4.2's independence becomes an explicit model-distinctness MUST via
RR.3) and adds the spec-object, identity, claim, and two-review-role contracts. Adopting the ASDD
profile makes these part of the conformance target. A project MAY conform to STANDARD.md without the
ASDD profile; it MAY NOT claim "ASDD compliant" without both.
