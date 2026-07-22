# Spec: OpenSpec adoption - govern any spec, run OpenSpec's lifecycle

Lane: feature. Spec for the PR that follows #92 (configurable `spec_paths:`).

## Outcomes
- ASDD stays spec-tool-agnostic: a project brings Spec Kit, OpenSpec, or plain files, and ASDD governs
  any of them. This is the headline adopter promise.
- OpenSpec is adopted as a first-class, opt-in **lifecycle**, not just a tolerated file layout: for an
  OpenSpec project, ASDD's readiness bar becomes OpenSpec's own validator, and the spec agent drives
  OpenSpec's propose/delta/validate/archive loop instead of writing a competing flat spec.
- A project that opts in gains an accumulating source of truth (OpenSpec's living specs), which ASDD's
  flat `docs/specs/<slug>.md` model never had.

## Scope

In:
- **Gate.** A `spec_tool:` switch in `.asdd.yml` (`builtin` default | `openspec`), or auto-detect an
  `openspec/` directory. When `openspec`: `spec-check` delegates readiness to the real CLI
  (`openspec validate <change> --strict --json`) instead of the built-in four-field definition-of-ready.
  When `builtin`: unchanged.
- **Location.** For an OpenSpec project, `spec_paths:` covers `openspec/changes/*/specs/**/*.md` (the
  deltas) and `openspec/specs/**/*.md` (the living specs). (The matcher already supports this after #92;
  this just documents the preset. NB: the deltas, not a proposal filename - see the pinned contract.)
- **Spec agent / `/asdd:spec`.** For an OpenSpec project, drive `openspec new change` / the propose flow
  rather than writing `docs/specs/<slug>.md`.
- **Review lens.** `review-spec` reads the `specs/` deltas as the
  spec-of-record for an OpenSpec change. Mostly a prompt change.
- **Archive.** Map ASDD's post-merge documentation agent onto `openspec archive` (fold the delta into
  living specs) for opt-in projects.
- **Adopter docs.** "Bring Spec Kit, OpenSpec, or plain files - ASDD governs any."

Out:
- We do NOT reimplement OpenSpec's format or validator. We shell out to the real CLI; their notion of a
  valid spec becomes ours.
- We do NOT require OpenSpec. `builtin` (the four-field DoR) stays the default for a project that brings
  no spec tool.
- Spec Kit gets **interop** (govern its output via `spec_paths:`), not lifecycle adoption - it has no
  change/delta/archive lifecycle to adopt.
- OpenSpec's in-assistant authoring UX (its own slash commands) stays theirs; we don't wrap it.

## Constraints

Pinned contract (Fission-AI/OpenSpec docs, verified 2026-07-17):
- install: `npm install -g @fission-ai/openspec`
- validate: `openspec validate [item-name] [--strict] [--json] [--all|--changes|--specs] [--no-interactive]`
- archive: `openspec archive [change-name] [-y] [--skip-specs] [--no-validate]`
- layout: `openspec/changes/<name>/{README.md,.openspec.yaml,specs/}` (1.6.0; the docs mention a proposal.md/tasks.md, but the scaffold does not create them); archive under
  `openspec/changes/archive/`; living specs `openspec/specs/<capability>/spec.md`
- deltas: `ADDED`/`MODIFIED`/`REMOVED`/`RENAMED` requirement sections with scenarios
- machine-readable: `--json` on `validate`, `show`, `context`

RESOLVED (real CLI run, openspec 1.6.0, 2026-07-17) - the delegation contract, pinned:
- `openspec validate <change> --type change --strict --json --no-interactive` EXITS 0 WHETHER THE SPEC
  PASSES OR FAILS. Confirmed both ways: a valid change -> `summary.totals {passed:1, failed:0}`, item
  `valid:true`; a broken change (no deltas) -> `summary.totals {passed:0, failed:1}` with a hard
  `[ERROR]`, item `valid:false`. Exit code 0 in BOTH.
- THEREFORE the gate parses the JSON and passes iff `summary.totals.failed == 0` (equivalently the
  item's `valid == true`). It MUST NOT key on `$?`. Keying on the exit code would pass every malformed
  spec through the airlock - the exact failure the built-in gate exists to prevent.
- Layout is `openspec/changes/<name>/{README.md, .openspec.yaml, specs/<capability>/spec.md}` in 1.6.0.
  The substance is the deltas under `specs/` (`## ADDED|MODIFIED|REMOVED|RENAMED Requirements` ->
  `### Requirement:` -> `#### Scenario:`). There is NO proposal.md in the current scaffold; the change's
  prose lives in README.md.
- spec_paths preset (corrected): `openspec/changes/*/specs/**/*.md` (the deltas are what make a change a
  real spec) plus the living specs `openspec/specs/**/*.md`. NOT a `proposal.md` (the scaffold has none).
- Pin the openspec version in CI (it is a moving CLI): the JSON `version` field is "1.0" (schema) at
  openspec 1.6.0. Assert the schema version and fail loudly if it drifts, so a silent format change
  cannot quietly break the gate.

Security (this is the load-bearing constraint):
- `openspec validate` runs over UNTRUSTED PR content inside the read-only intake job. It must run as
  data only: read-only, no network beyond the pinned install, and it must not execute anything the PR
  supplies. Confirm the validator only reads markdown and honours no PR-supplied hooks/plugins before
  wiring it. This preserves the read-only-analysis / write-scoped-publish invariant.
- No secrets: validation is deterministic and model-free.
- The Node CLI is a CI dependency ONLY for opt-in OpenSpec projects; ASDD's own deterministic gates stay
  dependency-free. The bridge fires only when `spec_tool: openspec` (or `openspec/` detected).

No regression:
- All 20 base checks stay green. The built-in path (`spec-check` DoR + `intake-check` spec gate) is
  unchanged and still tested.

## Verification
- A fixture OpenSpec project: a valid change passes the gate; a seeded-invalid change fails. The
  exit-code/JSON behaviour is pinned by a real `openspec validate` run and asserted in a test.
- `spec_paths:` at the OpenSpec preset recognises a change delta as "spec present" (add
  a case to `intake-check.test.sh`).
- Built-in path unchanged (regression over the existing suite).
- The `review-spec` lens, given an OpenSpec change, cites the delta and does not ask for
  `docs/specs/...`.
- Adopter docs carry the "bring any" line; slop gate clean.

## Sequencing
- Builds on #92 (shared files: `intake-check.sh`, `.asdd.yml`, `spec.md`, `review-spec.md`). #92 merges
  first, then this is ONE PR off fresh `main`. Do not stack it on the un-merged branch.
