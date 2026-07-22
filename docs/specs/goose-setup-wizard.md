# Spec: guided per-role model setup for Goose

## Problem

Installing "ASDD with Goose" spreads setup across three surfaces: `.asdd.yml` (which model plays which
role), `goose configure` (provider credentials), and GitHub Actions secrets (the CI review runtime).
`init --goose` scaffolds the files and prints guidance, but the most important and most error-prone
step, assigning a distinct model to each agent role so the developer never tests or reviews its own
code (the heterogeneity invariant), is left as a manual hand-edit. A new adopter discovers the surfaces
themselves and can silently break the invariant.

## Requirements

- Provide `asdd setup`, a guided wizard that assigns a model to each agent role and writes the `models:`
  block of `.asdd.yml`, preserving the file's comments and structure.
- Read the roles from the config's own `models:` block, using each role's inline comment as the prompt
  hint, so a renamed or added role (the roster evolves) needs no change to the wizard.
- Validate the result by delegating to `cli/check-models.sh`, the single source of truth for the
  heterogeneity rule, rather than re-implementing it.
- After writing, print the exact next steps: `goose configure`, the CI review-runtime secrets, and the
  per-recipe `goose run` commands for the models chosen.
- Support a non-interactive mode (`--set role=model`, repeatable) for scripting and CI, a read-only
  `--show`, and expose the tool through the unified `asdd` CLI. Zero runtime dependencies (stdlib).

## Acceptance criteria

- An assignment where a test model equals the developer exits non-zero (rule broken); a distinct roster
  exits zero and is written back to `.asdd.yml`.
- `--show` prints the current assignments and next steps without modifying the file.
- An unknown role name is rejected with a usage error.
- The behaviour is covered by `cli/setup-goose.test.sh` and runs in `validation/run-base.py`.

## Out of scope

- The optional local setup dashboard (a separate operate-kit surface, tracked separately).
- Entering provider credentials or CI secrets; `goose configure` and GitHub own those. The wizard only
  names the models and points at those steps.
