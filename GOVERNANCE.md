# Governance

This document covers how the **ASDD** repository is governed. The day-to-day roles and how the
standard changes are in [playbook/governance.md](playbook/governance.md); this is the formal layer.

## Mission and neutrality

ASDD is a standard for governed, transparent, secure, human-directed AI contribution. A
standard is only trustworthy if its governance is **vendor-neutral**: no single company can control
what "compliant" means. That neutrality is the whole reason another project can adopt it.

ASDD is owned by **OneHill** ([onehill.org](https://onehill.org)). OneHill holds the mission, the
trademark, the standard, and the neutrality; commercial work sustains the project but does not own the
standard. This mirrors the Linux Foundation / Apache / CNCF pattern. The
legal vehicle and timing are an owner/counsel decision; the direction is set here.

## Maintainers

Maintainers are the accountable humans. They:

- approve and merge protected-path changes (no agent may);
- own the scope of every agent identity operating on the repo;
- steward `STANDARD.md` and adjudicate conformance questions;
- uphold the [Code of Conduct](CODE_OF_CONDUCT.md).

Maintainers are listed in [.github/CODEOWNERS](.github/CODEOWNERS). Adding or removing a maintainer is
a maintainer decision recorded in the changelog.

## Decision-making

- **Lazy consensus** for most changes: a proposal with maintainer approval and no sustained objection
  merges.
- **Explicit governance sign-off** for normative changes to `STANDARD.md` (a new or tightened MUST),
  because they can break existing adopters' conformance claims. These are SemVer-major and announced.
- **Security changes** to the review workflows or the PDP get a dedicated security review before merge.

## Agents in this repo

ASDD dogfoods itself: agent identities may review and triage contributions here, under the same
rules the standard sets (disclosure, read-only analysis, advisory merge, the PDP). They are listed in
`.asdd.yml` and are accountable to the maintainers who scope them.

## Conformance and the mark

"ASDD compliant" is a claim a project self-certifies against [CONFORMANCE.md](CONFORMANCE.md).
The badge and the name refer to the versioned standard. Governance of the mark sits with the foundation
once established; until then, maintainers steward it. Misuse (claiming compliance without meeting the
MUSTs) is exactly the unverifiable-assertion failure ASDD rejects.

## Changing this document

Governance changes follow the same flow as a normative standard change: maintainer review plus
governance sign-off, recorded in [CHANGELOG.md](CHANGELOG.md).
