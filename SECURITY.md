# Security Policy

ASDD's reference implementation runs AI agents against untrusted pull-request and issue
content in CI. That is exactly the surface the 2026 attacks target, so we take reports seriously and
the review workflow is the highest-scrutiny file in the repo.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.** Report it privately:

- Use GitHub's **[Report a vulnerability](https://github.com/OneHillAI/ASDD/security/advisories/new)**
  (Security → Advisories), **or**
- Email **security@onehill.org**.

Please include a description and impact, steps to reproduce (a proof-of-concept if you have one), and
the affected commit. We will acknowledge the report, keep you updated, and credit you when a fix ships
unless you prefer to stay anonymous. Please allow reasonable time to fix before public disclosure.

## In scope (especially welcome)

The review pipeline's threat model is documented in [standards/security.md](standards/security.md).
Reports of any path that breaks these defenses are high priority:

- A way for **untrusted PR/issue content to reach an action-driving prompt** (prompt-injection to action).
- Any path where **model output is executed** as a command, or selects an arbitrary command.
- The **read-only analysis job gaining write scope or secret access**, or the write-scoped publish job
  ingesting untrusted input.
- Bypassing the **policy decision point** (`scripts/policy-check.sh`), getting an agent to merge, push,
  or take a non-allow-listed action.
- A way around the **protected-path human gate** (`CODEOWNERS` + branch protection).
- A supply-chain weakness in the workflows (unpinned action, a poisoned dependency path).

> The script/workflow names above (`policy-check.sh`, the review workflows) refer to the reference
> implementation in this repository. This document defines the
> required properties; the implementation realizes them.

## Adopter responsibility

If you adopt the reference implementation, **review the two review workflows and the PDP before making
your repo public**, and run its `conformance-check.sh`. The defaults are safe, but you own your
repository's configuration: branch protection, the `CODEOWNERS` owners, your `protected_paths`, and any
runtime credential you add. A misconfigured adopter repo is the adopter's responsibility; a flaw in the
shipped defaults is ours, report it.
