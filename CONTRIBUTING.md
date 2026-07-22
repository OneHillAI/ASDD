# Contributing to ASDD

ASDD is a project in its own right. Contribute a better review lens, a hardened workflow, a stronger
guardrail, a new runtime adapter, a clarification to the standard, or an adopter entry. This file is
for contributing **to ASDD itself**; to adopt ASDD in your own repo, see the
[README quickstart](README.md#adopt-it-in-60-seconds).

ASDD is Apache-2.0. Contributions, forks, and adoption are all welcome.

## Before you start

- **Read** [STANDARD.md](STANDARD.md) and [playbook/](playbook/). Changes must keep the standard
  conformant, `scripts/conformance-check.sh` runs in CI and will tell you if you broke a default.
- **Small PRs.** One change per PR. The pipeline gives faster feedback on a focused diff.

## The rules (we follow our own standard)

- **Disclose.** State in the PR whether the work is human- or agent-authored. Agent commits carry the
  `Agent:` trailer ([standards/disclosure.md](standards/disclosure.md)). Misrepresenting agent work as
  human is a [Code of Conduct](CODE_OF_CONDUCT.md) violation.
- **Sign off (DCO).** `git commit -s` adds `Signed-off-by:`, asserting you have the right to contribute
  the change under Apache-2.0.
- **Conventional Commits.** `feat:`, `fix:`, `docs:`, `chore:`, etc. The changelog is built from them.
- **Quality is a gate.** Keep the docs in the [de-slop](standards/de-slop.md) voice (CI hard-fails on
  the banned fluff words). Shell scripts pass `shellcheck`; workflows pass `actionlint`.

## What kinds of change need what review

This repo holds the **standard** and its executable reference implementation (workflows + scripts).
Propose changes to either here.

| Change (in this repo) | Review |
|---|---|
| Docs, playbook, an adopter entry, an example | Normal review, advisory merge |
| A review-lens or ops-agent **spec**, or the runtime **contract** (`agents/`) | Normal review; note any new action it implies |
| Issue/PR templates or `CODEOWNERS` scaffolding (`.github/`) | Normal review |
| **A MUST/SHOULD in `STANDARD.md`** | Normative change, maintainer + governance sign-off, SemVer-major if a new/tightened MUST ([GOVERNANCE.md](GOVERNANCE.md)) |

## Running the checks locally

The public repo is docs + spec, so the checks are doc hygiene: the de-slop / voice gate in
[.github/workflows/docs-lint.yml](.github/workflows/docs-lint.yml) (the banned-word list it enforces is
in [standards/de-slop.md](standards/de-slop.md)). The security-defaults / shellcheck / actionlint
self-checks live with the reference implementation. Open a PR using the template; a human approves and
merges, nothing here merges automatically.

## Proposing a new runtime adapter

Adapters are how ASDD stays vendor-neutral, and the **contract** for them is public:
[agents/runtime.md](agents/runtime.md). Propose the contract change here; the adapter code itself
(`scripts/runtime/<name>.sh`) goes in the reference-implementation bundle. Keep the analysis read-only;
an adapter that weakens a security default fails the implementation's conformance check.
