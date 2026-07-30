# Governance map-to - how ASDD meets the agentic-governance instruments

This maps ASDD's gates and fields to the public governance instruments for agentic AI, so an
adopter can show *which control satisfies which requirement* rather than assert conformance. It is the
concrete companion to [STANDARD.md](../STANDARD.md) §3.5 and feeds the self-cert in
[CONFORMANCE.md](../CONFORMANCE.md).

> **This is a map, not a certificate.** It records how the framework's mechanisms address each
> instrument's controls. It is **not** an accredited assessment, and it does not make a product compliant
> on its own. Verify every row against the **current published version** of the instrument - several are
> recent and still moving (see dates in Sources) - and complete any `Partial`/`Host`/`Product` row at the
> layer named.

## What this framework does and does not cover

ASDD governs **how agent-authored change enters a codebase** - the contribution pipeline and
the integrity of what it admits. That is one slice of agentic governance. It deliberately does **not**
specify:

- **Runtime sandboxing / isolation depth** - the host (the CI runner, the operator, Goose) enforces execution
  limits. The framework requires *read-only analysis* and *fail-closed*, not a particular sandbox. → `Host`
- **Model-level alignment, safety evaluation, red-teaming of the base model** - use the provider's and
  OWASP/NIST eval tooling. → out of scope.
- **Deep measurement / benchmarking** - observability is a `SHOULD`, not a metrics spec. → `Partial`
- **End-user product transparency / consent** - the deployed product's concern. → `Product`

Coverage tags below: **Gate** = a normative MUST/SHOULD in the framework; **Partial** = addressed, the
host or product completes it; **Host** = deferred to the runtime; **Product** = deferred to the deployed
application.

Framework mechanisms referenced (all defined in [STANDARD.md](../STANDARD.md) unless noted):
disclosure (§1); human accountability + protected paths (§2); untrusted-input-as-data / injection defence
(§3.1); read-only analysis, no write scope (§3.2); output-is-data, never executed (§3.3); the policy
decision point / posting gate (§3.5); rate limit `max_actions_per_run` (§3.6); dedicated supply-chain
security lens, never auto-merged (§3.7); security as a required status check (§3.8); the review lenses
(§4.4); the anti-rubber-stamp cross-check (§4.2); security decisive (§4.3); advisory merge (§5); pipeline
flow + attribution + audit log (§6); the independent merge-reviewer on a distinct model
([review-merge.md](../agents/review-merge.md)); model heterogeneity `developer_model != test_model`
([recipes](../recipes/README.md)); the **Assure** layer / integrity attestation (OACIF, its own repo); and
knowledge governance (OKGF: scope/review/tier/signature, its own repo).

---

## 1. OWASP Top 10 for Agentic Applications 2026 (ASI01-ASI10)

| Risk | How the framework addresses it | Coverage |
|---|---|---|
| **ASI01 Agent Goal Hijack** | §3.1: PR/issue/diff is fed as a fenced, inert **data** block, never into the instruction channel; a hijack attempt becomes a finding, not a command. The security lens tests for it. | Gate |
| **ASI02 Tool Misuse and Exploitation** | §3.2 read-only analysis + §3.3 output-is-data (never shell-exec'd) + §3.5 every action through the PDP + §3.6 bounded actions. The agent cannot invoke tools directly. | Gate |
| **ASI03 Identity and Privilege Abuse** | Named agent identity with least-privilege, scoped, revocable tokens (§2.4); analysis job holds no write scope (§3.2); protected paths stay human-only (§2.2). | Gate / Partial |
| **ASI04 Agentic Supply Chain Vulnerabilities** | §3.7 dedicated dependency/supply-chain security lens that never auto-merges; the Assure layer binds provenance (SLSA level, SBOM) and forbids `unpinned_dependencies`. | Gate |
| **ASI05 Unexpected Code Execution** | §3.3 the agent's output is data, never piped to a shell or used to choose a command - the core anti-RCE property; the Assure layer forbids `dangerous_sinks`. | Gate |
| **ASI06 Memory and Context Poisoning** | OKGF: knowledge is scoped, reviewed, and only **approved** pages are authoritative; promotions can be signature-verified, so poisoned content cannot silently become the source of truth. | Partial |
| **ASI07 Insecure Inter-Agent Communication** | Agents do not free-talk; each agent's I/O is data mediated through the pipeline and the PDP, and the knowledge brain is reached only over MCP-scoped tokens. | Partial |
| **ASI08 Cascading Failures** | §3.6 rate limit caps actions per run; fail-closed on error/low-confidence; advisory merge (§5) puts a human between the agent and the trunk; the cross-check catches propagated errors. | Partial |
| **ASI09 Human-Agent Trust Exploitation** | §1 disclosure (agents identify as agents); §4.2 the anti-rubber-stamp cross-check directly targets over-trust of agent output; §5 a human approves. | Gate |
| **ASI10 Rogue Agents** | Named identity + full audit log (detect + attribute); §3.6 bounded actions; the independent merge-reviewer runs on a **different model**, so a compromised builder-model does not also own its verification; protected paths human-only. | Gate / Partial |

## 2. OWASP Top 10 for LLM Applications (2025)

| Risk | How the framework addresses it | Coverage |
|---|---|---|
| **LLM01 Prompt Injection** | §3.1 untrusted-input-as-data. | Gate |
| **LLM02 Sensitive Information Disclosure** | §3.2 the analysis job holds no secrets beyond one runtime token; the Assure layer forbids `secret_exposure`. | Partial |
| **LLM03 Supply Chain** | §3.7 + Assure-layer provenance/SBOM. | Gate |
| **LLM04 Data and Model Poisoning** | OKGF tiers/approval gate the training set (export `gold` only); the host trains. | Partial / Host |
| **LLM05 Improper Output Handling** | §3.3 output-is-data. | Gate |
| **LLM06 Excessive Agency** | §2 human accountability + §3.6 rate limit + the PDP + protected paths. | Gate |
| **LLM07 System Prompt Leakage** | The lens instruction prompts are public and versioned (not secret) and carry no credentials - nothing to leak. | By design |
| **LLM08 Vector and Embedding Weaknesses** | OKGF governs the retrieved knowledge base (see ASI06). | Partial |
| **LLM09 Misinformation** | The spec lens + the cross-check + human merge. | Partial |
| **LLM10 Unbounded Consumption** | §3.6 `max_actions_per_run`. | Partial |

## 3. NIST AI RMF 1.0 + UC Berkeley CLTC Agentic AI Risk-Management Profile

| RMF function | How the framework addresses it | Coverage |
|---|---|---|
| **Govern** | The governance spine: disclosure (§1), human accountability + protected paths (§2), roles and GOVERNANCE.md, the whole normative pipeline. | Gate |
| **Map** | This map-to + the STANDARD threat model + the Assure-layer `threat_scan` per change. | Gate |
| **Measure** | Audit log + recorded review verdicts; `SHOULD` AgentOps-style observability. The framework is light here - see gaps. | Partial |
| **Manage** | The merge gate + rate limit + advisory merge = a human can always intervene, escalate, or stop; fail-closed. | Gate |
| **CLTC: human intervention / escalation / shutdown** | §5 advisory merge + §2 human direction - no agent is the sole approver in the default posture. | Gate |
| **CLTC: multi-agent risk / continuous monitoring / treat capable agents as untrusted** | ASI07/ASI08 controls; audit log = continuous record; §3 treats every agent's input **and** output as untrusted. | Partial |

## 4. NIST CAISI Agent standards + NCCoE agent identity properties

| Property | How the framework addresses it | Coverage |
|---|---|---|
| **Identification** | Named agent identity + the `Agent:` disclosure trailer on every agent commit (§1.2). | Gate |
| **Authorization** | Least-privilege, scoped, revocable tokens; read-only analysis job; protected paths human-only. | Gate |
| **Auditing** | Every agent action is logged through the pipeline's audit log (§6). | Gate |
| **Non-repudiation** | `Agent:` trailer + DCO sign-off; optional Assure-layer Ed25519 attestation signature; OKGF page signatures. | Gate |
| **Prompt-injection resistance** | §3.1 untrusted-input-as-data. | Gate |

## 5. Singapore IMDA Model AI Governance Framework for Agentic AI (Jan 2026)

| Dimension | How the framework addresses it | Coverage |
|---|---|---|
| **1. Assess and bound risks upfront** | Intake classifies each change; lane charters carry invariants; protected paths and §3.6 bound autonomy before any agent runs. | Gate |
| **2. Make humans meaningfully accountable** | §2 human direction + §5 advisory merge (a human approves and merges) + §1 disclosure + §6 attribution. | Gate |
| **3. Technical controls and processes** | The whole pipeline (§3-§6) + the Assure-layer attestation + the audit log. | Gate |
| **4. Enable end-user responsibility** | §1 transparency/disclosure of AI-authored change; end-user-facing consent lives in the deployed product. | Partial / Product |

## 6. ISO/IEC 42001 (AI management system) + ISO/IEC 23894 (AI risk management)

| Requirement area | How the framework addresses it | Coverage |
|---|---|---|
| **42001 - documented, auditable management of the AI lifecycle** | GOVERNANCE.md + STANDARD + this framework are a documented, versioned, auditable control system for agent-authored change, with roles, and continual improvement via CHANGELOG + CONFORMANCE. Covers the development-lifecycle slice of an org-wide AIMS. | Partial |
| **42001 controls - accountability, transparency, lifecycle, data governance** | §2 accountability; §1 transparency; §6 lifecycle + attribution; OKGF data governance. | Partial |
| **23894 - risk identification and treatment** | The STANDARD threat model + this map + the Assure-layer `threat_scan`. | Partial |

## 7. EU AI Act

| Provision | How the framework addresses it | Coverage |
|---|---|---|
| **Human oversight (Art. 14)** | §2 human accountability + advisory merge + protected paths - for the development process. | Gate |
| **Transparency (Art. 13 / 50)** | §1 disclosure: AI-authored change is labelled as such, in commits and PRs. | Gate |
| **Record-keeping / logging (Art. 12)** | Audit log + §6 attribution + OKGF `log.md` + optional Assure-layer attestation. | Gate |
| **Risk management system (Art. 9)** | STANDARD threat model + this map + the Assure layer. | Partial |

> **Scope note.** ASDD is a control over the **development process**, not a conformity
> assessment of a high-risk AI **system**. An adopter placing a product on the EU market maps the product
> itself against the Act separately; this framework is evidence for the process-governance parts.

## Related work (complementary, not mapped as controls)

- **Microsoft Agent Governance Toolkit** (MIT) - a runtime governance **engine**, not a portable format.
  Complementary: it can enforce at execution time what this framework governs at contribution time.
- **SLSA / in-toto / Sigstore / SBOM (SPDX, CycloneDX)** - build and artifact provenance. The framework
  does not re-specify them; the **Assure** layer (OACIF) *binds* them into a per-change attestation.
- **SPIFFE / SPIRE** - workload identity, referenced by the Assure layer for agent identity.

## Honest gaps (out of scope, by layer)

- **Runtime sandboxing, resource limits, network egress control at execution time** → `Host`. The
  framework requires read-only analysis and fail-closed; it does not specify the sandbox.
- **Base-model alignment, safety evaluation, and red-teaming** → out of scope; use the model provider's
  and OWASP/NIST tooling.
- **Formal measurement, metrics, and benchmarking** (RMF Measure depth) → `Partial`; observability is a
  `SHOULD`, not a metrics standard.
- **Incident response and post-incident review** → not specified.
- **End-user product transparency and consent** → `Product`.

Nothing here is a substitute for the host's runtime controls or the product's own conformity work; the map
shows where the contribution-and-integrity layer ends and those begin.

## Sources (verify against the current published version)

- OWASP Top 10 for Agentic Applications 2026 (published 2025-12-09): <https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/>
- OWASP Top 10 for LLM Applications (2025): <https://genai.owasp.org/>
- NIST AI Risk Management Framework (AI RMF 1.0): <https://www.nist.gov/itl/ai-risk-management-framework>
- UC Berkeley CLTC, Agentic AI Risk-Management Standards Profile (2026)
- NIST CAISI AI Agent standards work + NIST NCCoE agent identity/authorization project (2026)
- Singapore IMDA, Model AI Governance Framework for Agentic AI (launched 2026-01-22; updated 2026): <https://www.imda.gov.sg/resources/press-releases-factsheets-and-speeches/press-releases/2026/new-model-ai-governance-framework-for-agentic-ai>
- ISO/IEC 42001:2023; ISO/IEC 23894:2023
- Regulation (EU) 2024/1689 (EU AI Act)

*v0.1, 2026-07-10. A self-assessment map; not an accredited certification.*
