# Lifecycle: from open to merged to named

How a contribution moves through ASDD over time, the on-ramps that feed it, and the two-phase merge
posture.

## A single contribution, end to end

1. **Open.** Contributor uses the PR template, discloses human/agent authorship, signs off (DCO).
2. **Intake (minutes).** CI + disclosure/sign-off checks. Failures get fast, specific feedback.
3. **Review (minutes).** Multi-lens advisory review posts a single recommendation comment.
4. **Cross-check.** The adversarial quality lens and the security gate run before merge-ready.
5. **Human merge.** A maintainer reads the recommendation and approves + merges (advisory phase).
6. **Attribution.** The contributor is named; the contribution type is recorded.

## On-ramps (many doors, low friction)

ASDD treats these as first-class contribution types, each with a template and a worked example:

- **Code** and **docs**: the usual.
- **Examples**: a worked adoption others can copy ([../examples/](../examples/)).
- **Skills**: packaged agent capabilities.
- **MCP-server configs**: the post-connectors distribution layer (a registry of server configs), not a
  bespoke connectors directory.

Direction-led good-first-issues map published strategic directions to well-scoped tasks: a good first
issue is self-contained; if it needs context to understand, it is not one.

## Fast feedback is the retention lever

Slow first response is the dominant reason contributors leave. The review runs as soon as intake passes and posts
within minutes. A devcontainer / one-command setup keeps time-to-first-PR short.

## The two-phase merge posture

**Phase 1, advisory (every adopter starts here).** Agents review, cross-check, and recommend; a human
approves and merges. This matches GitHub's stance and earns trust. `merge_posture: advisory` in
`.asdd.yml`.

**Phase 2, earned, narrow auto-merge.** Only after an operational track record, a project may
auto-merge a **positively-declared** class of changes: trivial, fully green, non-security, non-core
(a docs typo, a lint fix, a dependency-free skill). Conditions that never relax:

- Never auto-merge a **protected path** (auth, crypto, CI/release, dependencies, data, training, the
  standard/governance docs). These stay human-approved permanently.
- Auto-merge is **off by default** and is a deliberate, reviewed change to `.asdd.yml` plus
  branch protection, not a default an adopter inherits.

The progression is one-way in spirit: you earn a *narrow* relaxation by demonstrating the gates work,
and you never trade the protected-path human gate for throughput.

## Visibility

The pipeline is meant to be public, PR in → agents review/cross-check → human approves → merged →
contributor named, with **humans and agents both shown**. Transparency is the proof of adoption and
the opposite of the undisclosed-agent failure ASDD exists to prevent.
