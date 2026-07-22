## What & why
<!-- What does this change and why? Link any related issue. -->

## How
<!-- Key implementation notes for reviewers. -->

## Disclosure (required: ASDD §1)
<!-- Tick the one that applies. Misrepresenting agent work as human is a conduct violation. -->
- [ ] Authored by a **human**.
- [ ] Authored or co-authored by an **AI agent under human direction**. The agent identity is named
      below and each agent commit carries the `Agent:` trailer.

> Agent identity (if any): `____` · Instructed by (human handle): `____`

## Change scope (required: ASDD framework-impact lens)
<!-- Tick exactly one. The `impact` lens checks this against what the change actually does; a change
     that alters the standard or required behaviour but is declared non-normative is blocked. -->
- [ ] **Non-normative**: a fix, docs, chore, or reference-implementation change that does NOT change the
      standard's text or any behaviour adopters rely on for conformance.
- [ ] **Normative**: changes the standard's text (`STANDARD.md`, `standards/`, `CONFORMANCE.md`), the
      governance rules, or behaviour adopters rely on (a gate, a lens, an agent contract, the meaning of
      a MUST). Fill in the Impact analysis below.

## Impact analysis (required if normative; delete if non-normative)
- **What else must adjust**: <!-- which other MUSTs, gates, lenses, CONFORMANCE items, docs, and
  reference-implementation pieces must change to stay consistent -->
- **Target version**: <!-- name it, e.g. v0.2.0 --> (level: <!-- major = new or tightened MUST; minor =
  new SHOULD or clarification; patch = editorial. See playbook/governance.md -->)
- **Governance sign-off**: a maintainer signs off before merge, and the change is grouped into a
  versioned release rather than merged on its own (GOVERNANCE.md).

## Checklist
- [ ] Commits are signed off (DCO): `Signed-off-by: Name <email>` (use `git commit -s`).
- [ ] Conventional Commit message(s).
- [ ] Change scope declared above; if normative, the impact analysis and target version are filled in.
- [ ] Quality gates pass locally (lint / types / tests as applicable).
- [ ] If this touches a **protected path**, a named human owner is requested for review.
- [ ] Docs shipped with the change: anything added or altered here appears in the documentation that
      describes it (the reference, the guide, the config keys). See `conventions.docs`.

---
<sub>This project follows [ASDD](https://github.com/OneHillAI/ASDD): agents disclose,
humans approve merges, security and quality are gates.</sub>
