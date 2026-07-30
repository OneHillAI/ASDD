# Conformance: self-check against ASDD v0.1

Work through this checklist against [STANDARD.md](STANDARD.md). Every **MUST** has to be checkable, 
by a person reading your repo, or by `scripts/conformance-check.sh` where it can be automated. When
all MUSTs pass you MAY add the badge and an entry in [adopters/](adopters/).

> A claim of conformance names the version: **"ASDD compliant (v0.1)."** SHOULDs are tracked,
> not required for the claim.

This checklist proves the docs line up. To prove the deployment actually *works and holds*, run the
[validation suite](validation/), effectiveness (does the loop produce correct software) and assurance
(do the guarantees survive an attacker), with fixtures and audit-log properties.

## How to use this

1. Copy this checklist into a tracking issue. For the parts that can be machine-verified, run the
   deterministic gates (`asdd validate`, and the checks under `cli/` and `.github/asdd/`)
   against your repo, or script the equivalent checks yourself.
2. Mark each MUST. Any unmet MUST means **not yet compliant**: fix it before claiming the badge.
3. Record the result and link it from your `adopters/` entry so the claim is checkable.

## MUST checklist

### Disclosure (§1)
- [ ] Agent identities' profiles state they are automated agents. (§1.1)
- [ ] Agent commits and PRs carry the disclosure trailer / body line. (§1.2)
- [ ] Disclosure + DCO are enforced at intake, a PR missing either is blocked, not honor-system. (§1, §6.1)
- [ ] Every agent action is written to a retained, reviewable audit trail. (§1.3)
      The kit implements this as the audit ledger (`cli/audit.py`), configured by the `audit:` block
      and exported to a private store you own. Check your trail with
      `python3 cli/audit.py trail --ledger L | python3 validation/audit-check.py /dev/stdin`.

### Human direction (§2)
- [ ] Agents act under named, scoped agent identities, never a human's or a shared anonymous one. (§2.1)
- [ ] Protected-path changes require a named human approver, enforced by branch protection + `CODEOWNERS`. (§2.2)
- [ ] A named human is accountable for each agent's scope and resulting merges. (§2.3)

### Security (§3)
- [ ] Untrusted input is handled as data and never interpolated into an action-driving prompt. (§3.1)
- [ ] Untrusted-input steps run read-only, with no write credentials or secrets. (§3.2)
- [ ] Agent output is never shell-executed; actions are a fixed allow-list. (§3.3)
- [ ] Secrets are isolated from any untrusted-input step. (§3.4)
- [ ] Every action passes a policy decision point before executing. (§3.5)
- [ ] Agent actions are rate-limited per window. (§3.6)

### Quality (§4)
- [ ] Automated quality gates (lint/types/tests) block merge in CI. (§4.1)
- [ ] An anti-rubber-stamp cross-check runs **independently** (separate inference, not conditioned on the other lenses) before a change is merge-ready. (§4.2)

### Merge posture (§5)
- [ ] Default posture is advisory: a human approves and merges; no agent is sole approver. (§5.1)
- [ ] If auto-merge exists, it is a narrow declared class and never touches a protected path. (§5.2)
- [ ] Auto-merge is off until there is an advisory-mode track record. (§5.3)

### Pipeline (§6)
- [ ] Contributions flow submit → intake → multi-lens review → cross-check → merge gate → attribution. (§6.1-6.4)

### Adoptability (§7)
- [ ] The adoption is pointed-to and checkable (template / fork / independent impl). (§7.1)

## SHOULD checklist (tracked, not required)
- [ ] Pipeline is publicly visible, humans and agents both shown. (§1.4)
- [ ] Agent scope is least-privilege per role. (§2.4)
- [ ] Dependency/supply-chain changes get a dedicated security lens and never auto-merge. (§3.7)
- [ ] The security verdict is exposed as a required status check, so a block mechanically gates merge. (§3.8)
- [ ] De-slop standards flag duplication / single-use abstraction / net-added complexity. (§4.3)
- [ ] Review runs multiple lenses, not one generalist pass. (§4.4)
- [ ] Auto-merge class is defined positively. (§5.4)
- [ ] Contribution is attributed to its human contributor on merge. (§6.5)
- [ ] First review feedback reaches the contributor in minutes. (§6.6)
- [ ] The standard distribution accepts contributions to itself. (§7.2)

## ASDD profile (optional)

Adopt this only if you claim **"ASDD compliant (v0.1)"**: the spec-driven profile
([standards/spec-driven.md](standards/spec-driven.md)) on top of every base MUST above. These are the
profile's MUSTs; its SHOULDs (SD.5, M.4, CL.4, RR.4, ID.2) are tracked, not required.

### Spec-driven intake (SD)
- [ ] Intake produces a spec object meeting the definition of ready before a contribution is built or claimed. (SD.1)
- [ ] The definition of ready requires at least outcomes, scope, constraints, and verification. (SD.2)
- [ ] Every contribution is categorized and prioritized. (SD.3)
- [ ] The completeness decision is explicit and recorded. (SD.4)

### Trust membrane (M)
- [ ] Only a validated spec object (and, downstream, a change that passed governance review) crosses the boundary inward. (M.1)
- [ ] Submitted code is treated as reference data; the developer re-derives from the spec and it is never merged as an authored diff without the full pipeline. (M.2)
- [ ] The knowledge base and model runtime are reachable from the untrusted side only via a governed, read-only, scoped consumer. (M.3)

### Source-agnostic intake (SA)
- [ ] Contributions may enter from any channel; the spec-object contract and membrane apply identically. (SA.1)
- [ ] No specific channel or listing surface is mandated. (SA.2)

### Two-tier identity (ID)
- [ ] Merging code requires a DCO-capable authoring identity. (ID.1)
- [ ] Absence of an authoring identity does not block a proposal from progressing via agent authoring. (ID.3)
- [ ] Attribution is preserved end-to-end, AI involvement disclosed, and a human certifies the DCO before merge. (ID.4)
- [ ] No specific identity provider is mandated. (ID.5)

### Claim protocol (CL)
- [ ] Work items with a ready spec are claimable; items without are not. (CL.1)
- [ ] At most one active, identity-bound claim per item. (CL.2)
- [ ] Claims are time-boxed and auto-release on expiry. (CL.3)

### Two review roles (RR)
- [ ] A contribution passes a contributor-facing reviewer (advisory) and a governance reviewer (the gate); they are distinct and "ready" is not approval. (RR.1, RR.2)
- [ ] The governance reviewer and the tester run on models distinct from the developer. (RR.3)

### Operating roles (OP)
- [ ] The developer is supplied by the contributor; the deployment runs no standing developer agent. (OP.1)
- [ ] The deployment provisions and operates the governance and support agents: intake, interaction, the review lenses + merge-reviewer, the tester, and the documentation agent. (OP.2)
- [ ] `developer != tester`: the deployment's tester runs a model distinct from whatever built the change. (OP.3)
- [ ] Readiness is the whole roster proven: each provisioned agent has run on a real artifact (the reviewer on a real PR, the tester a real pass/fail, the documentation agent a correct update, the interaction agent answering from knowledge and routing one idea), not the reviewer alone. (OP.5)

## Governance map-to (optional self-cert)

Conformance to ASDD is the checklist above. Separately,
[standards/compliance-map.md](standards/compliance-map.md) maps ASDD's gates to the public
agentic-governance instruments, so you can show *which control meets which requirement* for the ones your
jurisdiction or risk tier calls for. Tick the instruments you claim and cite the map row - not a bare
assertion. Verify each against its current published version.

- [ ] OWASP Top 10 for Agentic Applications 2026 (ASI01-ASI10)
- [ ] OWASP Top 10 for LLM Applications (2025)
- [ ] NIST AI RMF + UC Berkeley CLTC Agentic AI Risk-Management Profile
- [ ] NIST CAISI / NCCoE agent identity
- [ ] Singapore IMDA Model AI Governance Framework for Agentic AI
- [ ] ISO/IEC 42001 + ISO/IEC 23894
- [ ] EU AI Act (process-governance parts)

The map marks each row **Gate / Partial / Host / Product**; a `Partial`/`Host`/`Product` row is complete
only once you close it at the layer named. The map is a self-assessment, not an accredited certification.

## The badge

When every MUST passes, add to your README:

```markdown
[![ASDD compliant v0.1](https://img.shields.io/badge/ASDD-compliant%20v0.1-2da44e)](https://github.com/OneHillAI/ASDD/blob/main/CONFORMANCE.md)
```

Renders as a green "ASDD, compliant v0.1" badge linking back to this checklist. Only use it
once the MUSTs are met; an unchecked badge is exactly the kind of unverifiable claim ASDD rejects.
