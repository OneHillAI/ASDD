# Changelog

Notable changes to ASDD. The format follows [Keep a Changelog](https://keepachangelog.com); the standard
is versioned with [Semantic Versioning](https://semver.org). While pre-1.0 the standard is a moving
draft, so pin a conformance claim to a commit or date.

## [Unreleased]

### Fixed
- **Review runtime recovers the model's JSON.** A reasoning model wraps its review object in analysis
  prose (with its own braces), code fences, or trailing commentary, or emits it in a separate
  `reasoning_content` field; the old first-brace-to-last-brace recovery then captured an invalid span and
  the review degraded to a "human should review manually" placeholder even though the model had reviewed.
  Extraction now uses a real JSON parser ([extract-json.py](.github/asdd/runtime/extract-json.py)) that
  recovers the review object and still fails closed on genuine non-JSON, and the adapter logs a key-safe
  redacted diagnostic on a persistent failure. Spec:
  [review-json-recovery.md](docs/specs/review-json-recovery.md).

## [0.1.0] - 2026-07-22

Initial public release.

### The standard and the govern layer
- **The standard** ([STANDARD.md](STANDARD.md)), self-certifiable against [CONFORMANCE.md](CONFORMANCE.md):
  every change disclosed, gated by hard checks, reviewed against its spec, and merged by a named human.
- **The govern layer**: the intake to review to publish pipeline on GitHub Actions. Review is triggered
  by intake completing, so a failed intake never reaches a model and a fork PR gets the same real review;
  a write-scoped publish job posts the advisory and sets the `asdd/review` status, and never merges.
- **The impact lens**: every change is classified for its effect on the framework, so a normative change
  cannot merge undeclared or without an impact analysis and a target version.
- **Deterministic gates** and the `asdd` CLI: `spec-check`, `openspec-gate`, `claim-check`,
  `merge-eligibility`, `conventions-check`, `audit`, `run-agent`, `audit-check`, `doctor`, `workflow-lint`,
  plus `init`, `setup`, and a read-only governance dashboard. The declared `conventions:` block is enforced
  at intake on every pull request, not only runnable by hand.

### The agent audit ledger (STANDARD 1.3)
- Every agent action is recorded as an append-only, hash-chained entry: identity, action, target,
  authorizing decision, timestamp, reasoning, and the action it caused. Reviewed content is never stored,
  only a digest. Records export to a private sink the adopter owns; the export refuses the governed repo
  and any public destination, and keeps the chain continuous across batches. Two derived views: a training
  corpus (aggregates and reasoning, no finding text or paths) and curated knowledge emitted as real
  **OKGF pages** (OKGF is the knowledge standard ASDD adopts), validated against OKGF's own conformance so
  an OKGF store ingests them with no translation.

### Adopting into an existing project
- Declare how a project already ships in a `conventions:` block, and `conventions-check` holds agent output
  to it. Every field is optional and the gate judges only the change, so a mature repository adopts on
  day one. Knowledge may be seeded from project history, kept distinct from the audit trail.

### Bring your own
- **Spec tool**: the built-in definition of ready, or OpenSpec, chosen at setup. The framework mandates a
  spec exists and is checked, not which tool wrote it.
- **Runtime**: any OpenAI-compatible model behind a pluggable adapter, with a retry and tolerant parser.
- **The Goose operate kit** (alpha): ready-to-run recipes on unmodified Goose, plus the slash commands.
  Every agent has a run path: intake and the review lenses in CI; documentation and a post-merge test run
  as trusted post-merge workflows; triage, support, contributor review, merge review and interaction run
  on demand (the fixed-prompt agents through `run-agent`, which fences untrusted input the way the review
  runtime does and records each run). The tester never runs automatically on an untrusted open PR.
- Optional profiles: **Assure** (integrity attestation) and the **spec-driven** profile.

[0.1.0]: https://github.com/OneHillAI/ASDD/releases/tag/v0.1.0
