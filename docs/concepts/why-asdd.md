# Why ASDD exists

AI agents now write real contributions to software projects, not autocomplete but whole pull
requests. That is useful, and it breaks three things a project used to take for granted.

**Attribution.** When a maintainer reads a PR, they assume a person stands behind it. An agent-authored
PR that looks human erases the one signal reviewers rely on: who wrote this, and who is accountable for
it. Without disclosure, a project cannot tell which of its code was machine-generated, cannot weigh
review effort accordingly, and cannot answer that question later when it matters.

**Security.** An agent's output is untrusted input. A PR body can carry an injected instruction. A diff
can carry a Trojan-Source bidi trick or a pipe-to-shell. A refactor can disable TLS verification three
files away from the stated change. A review process built for humans reviewing humans does not treat the
contribution itself as a potential adversary. ASDD does.

**Merge authority.** The moment agents can open PRs, the pressure is to let them merge too, and an agent
approving and merging its own work is a control failure, not a convenience. Someone has to draw the line
at which changes an automated actor may ever land, and make that line mechanical rather than a matter of
trust.

## Why existing tools do not cover this

The spec-driven development tools that AI coding has produced, GitHub's [Spec
Kit](https://github.github.com/spec-kit/) foremost, solve a real and different problem: helping one
developer and their agent turn a specification into code inside their own repository. That is the
authoring loop. ASDD builds on the same spec-driven foundation (see [what-is-asdd](what-is-asdd.md)),
but its centre of gravity is the contribution boundary: what happens when work from many humans and
agents arrives at a project that has to decide whether to trust it. Nothing in the authoring toolchain
governs that boundary end to end, meaning disclosure, gated review, and a human merge. That is the gap
ASDD fills.

## What ASDD is for

ASDD makes AI-authored contribution trustworthy: every change is disclosed, every change is gated by
checks that fail hard on the things that matter, and a named human owns every merge. It does not slow a
project down to do this, since the deterministic gates are fast and the agents do the review work. It
means the information a maintainer merges on was produced under conditions the project can defend.

## The aim: bug-free software

ASDD exists for one goal: **software delivered without bugs.** Not "fewer bugs on average" - the target
is a change a project can merge trusting it is correct, secure, and does what its spec said. That is a
high bar, and no single check reaches it. ASDD stacks the gates so a defect has to pass all of them: a
spec before any code, tests written on a different model than the code so their blind spots do not line
up, a security lens that treats the diff as adversarial, and a human at the merge.

We do not claim to be there yet. ASDD is a v0.1 draft, and closing the distance to bug-free delivery is
the work. That is why it is built in the open and stewarded by the [OneHill Foundation](https://onehill.org):
we are looking for contributors - engineers who sharpen the gates and the agents, and non-engineers who
sharpen the specs and the docs - to develop ASDD toward that goal. The framework governs its own
development the same way it asks yours to be governed.

Next: [what ASDD is](what-is-asdd.md), [how it works](how-it-works.md)
