# Governance

Who decides what, and how the standard itself changes. The throughput is automated; **judgement and
accountability are human**.

## Roles

- **Maintainers (human).** Own the standard, approve merges that matter, and are accountable for the
  agents operating on the repo. Named in `CODEOWNERS`. Every protected-path merge needs one.
- **Agent identities.** Named, scoped, attributable accounts that run review/triage/support/interaction.
  They
  recommend and perform a fixed allow-list of low-risk actions (comment, label, welcome). They never
  merge in the default posture, and a named human is accountable for each agent's scope (STANDARD §2.3).
- **Contributors.** Anyone opening a PR or issue, human or agent-assisted. Required to disclose and
  sign off.

## Accountability is not diffused to "the bot"

Every agent action is attributable to an identity, and each identity maps to an accountable human
maintainer. "An agent did it" is never an answer. The audit trail (STANDARD §1.3) records who, what,
the authorizing decision, and when, for every action.

## Changing the standard

`STANDARD.md` is normative and versioned ([SemVer](https://semver.org)):

- A **new or tightened MUST** is a **major** change. It requires a maintainer review plus an explicit
  governance sign-off, because it can break existing adopters' conformance claims.
- A **new SHOULD or a clarification** is a **minor** change.
- Editorial fixes are patch-level.

Every PR is measured against this. A change is **normative** if it edits the normative text
(`STANDARD.md`, `standards/`, `CONFORMANCE.md`) or the governance rules, or if it changes behaviour an
adopter relies on for conformance (a gate's verdict, a lens's contract, an agent's fixed prompt, the
meaning of a MUST). A normative PR MUST:

- declare its scope in the PR template (a fix that quietly changes the nature is caught, not waved
  through),
- carry an **impact analysis**, what else must adjust to stay consistent (other MUSTs, gates, lenses,
  `CONFORMANCE.md` items, docs, and reference-implementation pieces), and
- name a **target version** at the SemVer level above.

The [`impact` lens](../agents/review-impact.md) classifies every PR and blocks a normative change that is
undeclared or missing its impact analysis or target version; a deterministic pass enforces this even
before a model runtime is wired. Normative changes are **grouped into a versioned release** rather than
merged on their own, get the explicit governance sign-off, are reviewed by humans, and are recorded in
[CHANGELOG.md](../CHANGELOG.md). The reference implementation can change more freely, as long as it still
satisfies the standard.

## Ownership and neutrality

ASDD is owned by **OneHill** (onehill.org) and is **vendor-neutral**. A standard is only trustworthy if
its governance is not controlled by a single vendor, that neutrality is precisely what lets other
projects adopt it. The reference implementation defaults to a hosted reference runtime, but the standard
mandates no runtime and the adapter interface keeps any vendor swappable. See [../GOVERNANCE.md](../GOVERNANCE.md)
for the repository's formal governance and the foundation framing.

## Decisions humans keep, always

- Merges on protected paths.
- Enabling or scoping auto-merge.
- Any change to `STANDARD.md`.
- Granting or widening an agent identity's scope.
- Security-sensitive judgement calls flagged by the security lens.
