# Reference

The normative specification and the machinery. This is the *Reference* quadrant: precise, for looking
things up. For the narrative, start with [concepts](../concepts/why-asdd.md); for setup, the
[guides](../guides/deploy.md).

## The standard

- [STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md): the normative specification (RFC 2119 MUST/SHOULD). The thing a
  project conforms to.
- [CONFORMANCE.md](https://github.com/OneHillAI/ASDD/blob/main/CONFORMANCE.md): the self-certification checklist for "ASDD compliant (v0.1)".

## Standards profiles and quality bars

- [standards/spec-driven.md](https://github.com/OneHillAI/ASDD/blob/main/standards/spec-driven.md): the spec-driven profile (spec-object
  intake, the trust membrane, the claim protocol, two-tier contributor identity).
- [standards/assure.md](https://github.com/OneHillAI/ASDD/blob/main/standards/assure.md): the optional integrity-attestation profile.
- [standards/disclosure.md](https://github.com/OneHillAI/ASDD/blob/main/standards/disclosure.md): the disclosure trailer and PR block.
- [standards/security.md](https://github.com/OneHillAI/ASDD/blob/main/standards/security.md): the security-lens requirements.
- [standards/de-slop.md](https://github.com/OneHillAI/ASDD/blob/main/standards/de-slop.md): the quality bar (§4.3) and the banned tells.
- [standards/compliance-map.md](https://github.com/OneHillAI/ASDD/blob/main/standards/compliance-map.md): how ASDD maps to OWASP-agentic, NIST,
  the EU AI Act, ISO 42001.

## Agents

The role definitions the operate layer runs. See [agents/](https://github.com/OneHillAI/ASDD/blob/main/agents):
[runtime](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md) (the runtime contract), [intake](https://github.com/OneHillAI/ASDD/blob/main/agents/intake.md),
[interaction](https://github.com/OneHillAI/ASDD/blob/main/agents/interaction.md), [triage](https://github.com/OneHillAI/ASDD/blob/main/agents/triage.md),
[support](https://github.com/OneHillAI/ASDD/blob/main/agents/support.md), and the review lenses:
[code](https://github.com/OneHillAI/ASDD/blob/main/agents/review-code.md), [security](https://github.com/OneHillAI/ASDD/blob/main/agents/review-security.md),
[spec](https://github.com/OneHillAI/ASDD/blob/main/agents/review-spec.md), [quality](https://github.com/OneHillAI/ASDD/blob/main/agents/review-quality.md),
[merge](https://github.com/OneHillAI/ASDD/blob/main/agents/review-merge.md), [contributor](https://github.com/OneHillAI/ASDD/blob/main/agents/review-contributor.md).

## The CLI and gates

- [cli/README.md](https://github.com/OneHillAI/ASDD/blob/main/cli/README.md): the `asdd` unified CLI and every deterministic gate
  (`spec-check`, `openspec-gate`, `claim-check`, `merge-eligibility`, `check-models`, `audit` (append /
  verify / tip / graft / trail / corpus / knowledge as OKGF pages), `audit-ship`, `operate-run`, `run-agent`, `dev-council`, `audit-check`, `conventions-check`, `doctor`, `workflow-lint`,
  `asdd-mcp`).
