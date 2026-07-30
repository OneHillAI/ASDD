# ASDD - Agentic Spec-Driven Development: Standard v0.1 (draft)

The normative specification for running a software project with AI agents that are
**instructed by humans**: governed, transparent, secure, and quality-gated. This document is the
thing other projects conform to. It is **runtime-neutral**: it says nothing about which model or
agent platform you use. The reference implementation in this repo is one conforming implementation,
not part of the standard.

**Goal.** The goal of ASDD is bug-free software. Every MUST below exists to drive the defect
rate on AI-authored contributions toward zero: authorship is disclosed, the contribution is treated as
untrusted, it is reviewed by independent lenses and a tester on a different model, and only an
accountable human merges.

A project that meets every MUST in this document MAY describe itself as **"ASDD compliant
(v0.1)"** and self-certify against [CONFORMANCE.md](CONFORMANCE.md).

## Status and versioning

Draft, pre-1.0. The standard is versioned with [SemVer](https://semver.org): a new MUST or a
tightened MUST is a major bump; a new SHOULD or clarification is a minor bump. Conformance claims
name the version (`v0.1`).

While pre-1.0, `v0.1` is a moving draft: it accumulates changes in place, including new MUSTs, until
the number is cut at the first pinned release. A conformance claim made against the draft should
reference the commit or date it was checked against, since `v0.1-draft` is not yet a frozen bar. The
major/minor rule above starts governing version numbers once `v0.1` is cut.

## Terminology

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are used as defined in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

- **Agent**: an automated actor (LLM-driven or otherwise) that proposes changes, reviews, triages,
  or answers, under human direction.
- **Agent identity**: a named, attributable account an agent acts as. Not a shared bot account, not
  a human's account.
- **Protected path**: a file or directory where a defect is high-impact: authentication, crypto,
  CI/release config, dependency manifests, data-handling, training, and the standard/governance docs
  themselves. Each project declares its own set.
- **Untrusted input**: any content an agent did not author and a maintainer has not vouched for:
  PR titles/bodies/diffs, issue text, commit messages, review comments, external URLs, file contents
  from a fork.
- **Action**: a side-effecting operation an agent performs: posting a comment, applying a label,
  requesting changes, merging, editing a file, calling an external tool.
- **Advisory merge**: the agent recommends; a human approves and merges.
- **Policy decision point (PDP)**: the single chokepoint that authorizes (or refuses) each agent
  action before it happens.

---

## 1. Disclosure (transparency)

Agents are never disguised as humans. This is the core failure ASDD exists to prevent.

- **1.1 (MUST)** Every agent-authored pull request, commit, issue, and comment MUST be identifiable
  as agent-produced. The agent identity's profile MUST state that it is an automated agent.
- **1.2 (MUST)** Agent-authored commits MUST carry a machine-readable disclosure trailer. The
  canonical form is:
  ```
  Agent: <agent-name> (automated, instructed-by: <human-handle>)
  ```
  PRs MUST carry the same disclosure in the body. See [standards/disclosure.md](standards/disclosure.md).
- **1.3 (MUST)** Every agent **action** (1.x-5.x) MUST be recorded in an audit trail that captures:
  the agent identity, the action, the target, the authorizing decision, and a timestamp. The trail
  MUST be retained and reviewable. No action without a corresponding audit record.
- **1.4 (SHOULD)** A project SHOULD make the pipeline publicly visible, humans **and** agents both
  shown, so adoption is verifiable, not asserted.

## 2. Human direction and final accountability

- **2.1 (MUST)** Agents MUST act under named, scoped **agent identities**: never a human's identity,
  never a shared anonymous account.
- **2.2 (MUST)** Every protected-path change MUST be approved by a named human before merge,
  regardless of any agent verdict. This MUST be enforced mechanically (e.g. branch protection +
  `CODEOWNERS`), not by convention.
- **2.3 (MUST)** A human MUST be accountable for each agent's scope and for the merges that agent's
  output leads to. Accountability MUST NOT be diffused to "the bot."
- **2.4 (SHOULD)** Agent scope SHOULD be least-privilege: an agent is granted only the actions its
  role requires (see §5).

## 3. Security is a gate

Security criteria are conditions of operation, not recommendations. A pipeline that fails any §3 MUST
is not ASDD compliant even if everything else passes. Full rationale and the attack model are
in [standards/security.md](standards/security.md).

- **3.1 (MUST)** All untrusted input MUST be treated as data, never as instructions. Untrusted input
  MUST NOT be interpolated into a prompt that drives an agent action. "Content to review" MUST be
  separated from "instructions to the agent."
- **3.2 (MUST)** Agent steps that ingest untrusted input MUST run with a **read-only** default token
  and MUST NOT have write credentials or any secret beyond the single runtime credential the analysis
  itself needs. That runtime credential MUST NOT be placed into the prompt or any model-visible input,
  so injected content cannot exfiltrate it.
- **3.3 (MUST)** Model/agent output MUST NOT be executed as a shell command or otherwise used to
  select arbitrary commands. The set of actions an agent can take MUST be a fixed, audited allow-list.
- **3.4 (MUST)** Write-scoped credentials and any secret unrelated to the analysis MUST be isolated
  from every step that reads untrusted input, they live only in a separate step or job that does not
  ingest untrusted input (the runtime credential exception in §3.2 aside).
- **3.5 (MUST)** Every agent action MUST pass through a **policy decision point** that authorizes the
  specific action against the allow-list before it executes, and refuses anomalous or escalating
  sequences. See [standards/security.md](standards/security.md) and [agents/runtime.md](agents/runtime.md).
- **3.6 (MUST)** Agent-initiated actions MUST be rate-limited per window. The ecosystem is straining
  under agent-action floods; a conforming project is a good citizen.
- **3.7 (SHOULD)** Dependency and supply-chain changes SHOULD get a dedicated security review lens and
  SHOULD never auto-merge (see §6).
- **3.8 (SHOULD)** The security verdict SHOULD be exposed as a **required status check**, so a blocking
  finding mechanically blocks merge for every change, not only on protected paths, making "security is
  a gate" enforced rather than advisory.

## 4. Quality is a gate

- **4.1 (MUST)** A contribution MUST pass automated quality gates (lint, type checks where
  applicable, tests) before it is eligible to merge. Gates MUST be enforced in CI, not advisory.
- **4.2 (MUST)** Review MUST include an **anti-rubber-stamp** cross-check: at least one pass whose
  explicit job is to *refute* an "approve," not to confirm it. This pass MUST be **independent**: run
  in a separate context/inference that is not conditioned on the other lenses' conclusions, so it
  cannot inherit and confirm them. Reviewers MUST NOT converge on approval by default. See
  [playbook/review-flow.md](playbook/review-flow.md).
- **4.3 (SHOULD)** Review SHOULD apply de-slop standards that flag duplication, single-use
  abstraction, defensive bloat, and net-added complexity, the documented failure mode of agent
  contributions. See [standards/de-slop.md](standards/de-slop.md).
- **4.4 (SHOULD)** A change SHOULD be reviewed across multiple **lenses** (correctness, security,
  spec/architecture conformance, quality/tech-debt), not by a single generalist pass.

## 5. Advisory merge first; auto-merge is earned and narrow

- **5.1 (MUST)** By default, agents recommend and a human approves and merges (**advisory merge**).
  An agent MUST NOT be the sole approver of a merge in the default posture.
- **5.2 (MUST)** Auto-merge, if a project enables it at all, MUST be restricted to a narrow,
  declared class of trivial, fully-green, non-protected changes, and MUST NOT touch any protected
  path. Protected paths stay human-approved permanently.
- **5.3 (MUST)** Auto-merge MUST be off until the project has an operational track record under
  advisory merge. New adopters start in advisory mode.
- **5.4 (SHOULD)** The auto-merge class SHOULD be defined positively (an allow-list of paths/change
  types), not negatively.

---

## 6. The contribution pipeline (normative flow)

A conforming project routes every contribution through this flow. Implementations vary; the ordering
and the gates do not.

```
submit → intake → multi-lens review → cross-check (anti-rubber-stamp) → merge gate → attribution
```

- **6.1 (MUST)** Intake MUST classify the contribution and check disclosure (§1) and basic
  contribution requirements (e.g. DCO sign-off) before review begins.
- **6.2 (MUST)** Review MUST run the applicable lenses (§4.4) and post results as **recommendations**,
  not merges (§5.1).
- **6.3 (MUST)** The cross-check (§4.2) MUST run before a change is presented as merge-ready.
- **6.4 (MUST)** The merge gate MUST enforce §2.2 (human approval on protected paths) and §5
  (advisory/auto-merge posture).
- **6.5 (SHOULD)** On merge, the pipeline SHOULD attribute the contribution to its human contributor
  by name and record the contribution type.
- **6.6 (SHOULD)** First review feedback SHOULD reach the contributor in minutes, not days. Slow first
  response is the dominant cause of contributor attrition.

## 7. The standard is itself adoptable

- **7.1 (MUST)** A conforming project MUST be able to point to where its adoption lives (this template,
  a fork, or an independent implementation) so the claim is checkable.
- **7.2 (SHOULD)** A conforming *standard distribution* (like this repo) SHOULD accept contributions
  to the standard and its reference implementation, with its own governance and contribution guide.

## 8. Profiles (optional, additive)

The standard supports **profiles**: additive normative modules a project MAY adopt on top of the base
MUSTs. A profile never relaxes a base MUST; it adds contracts for a particular way of working, and
carries its own conformance rows.

- **8.1 (MAY)** A project MAY adopt the **ASDD, Agentic Spec-Driven Development** profile
  ([standards/spec-driven.md](standards/spec-driven.md)). It adds normative contracts for spec-object
  intake, the trust membrane, source-agnostic intake, two-tier contributor identity, the claim protocol,
  and the split between contributor-facing and governance review. A project claiming **"ASDD compliant
  (v0.1)"** MUST meet every base MUST in this document **and** the profile's MUSTs.

---

## Conformance

Self-check against [CONFORMANCE.md](CONFORMANCE.md). A project is **ASDD compliant (v0.1)** when
every MUST above is met. SHOULDs are strongly encouraged and tracked, but not required for the claim.

## Relationship to the reference implementation

This repository is the standard and its reference implementation (GitHub Actions workflows + scripts,
under `.github/`, `cli/`, and `recipes/`). Running it is one path to
conformance, but **not required**: any implementation that meets the MUSTs conforms. The runtime (which
model/agent platform performs review) is pluggable behind a public contract; see
[agents/runtime.md](agents/runtime.md). Keeping the standard separable from any implementation is what
lets ASDD be a standard rather than a single vendor's tool.
