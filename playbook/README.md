# ASDD: playbook

The human-readable companion to [STANDARD.md](../STANDARD.md). The standard says *what* must hold; the
playbook explains *why* and *how to run it*. Read this to understand the model; use the standard to
check conformance.

## Why this exists

In 2026, agent-run contribution is mainstream and mostly ungoverned. The well-documented failures:

- **Undisclosed agents at scale.** One agent landed 103 PRs across 95 repos in two weeks, undisclosed,
  merged into major projects, with maintainers unaware they were dealing with an agent.
- **Signal collapse.** A prominent maintainer reports "1 in 10 AI PRs is legitimate"; the rest is noise.
- **Prompt injection in CI.** PR body → prompt → shell, with a write-scoped token: a live supply-chain
  attack class.
- **Automation complacency.** Agent code adds redundancy and tech-debt *while reviewers feel better
  approving it.*

ASDD is the governed version of the same activity: agents do the throughput, humans hold
direction and the merges that matter, and security and quality are gates rather than hopes. The model
is not novel, agents reviewing PRs is everywhere, the **governance** is the point.

## The five non-negotiables (and where each lives)

| Principle | Standard | How it's enforced |
|---|---|---|
| Disclosure always | §1 | PR/issue templates, commit trailer, `check-disclosure.sh`, audit log |
| Human direction + accountability | §2 | agent identities, `CODEOWNERS`, branch protection |
| Security is a gate | §3 | the two-workflow review split, the PDP, `standards/security.md` |
| Quality is a gate | §4 | CI gates + the anti-rubber-stamp lens (`agents/review-quality.md`) |
| Advisory merge first | §5 | workflows post recommendations; humans merge; `.asdd.yml` posture |

## How to read the rest

- **[governance.md](governance.md)**: who decides what; the human roles; how the standard itself changes.
- **[review-flow.md](review-flow.md)**: the contribution pipeline step by step, including the
  anti-rubber-stamp cross-check and the merge gate.
- **[lifecycle.md](lifecycle.md)**: a contribution from open to merge to attribution; the two phases
  (advisory, then earned narrow auto-merge); on-ramps and fast feedback.

The throughput is automated; the **trust layer is not**. Real-time community (Discord, office hours,
calls, roadmap cadence) is a deliberately separate, human-led workstream and is out of scope here.
