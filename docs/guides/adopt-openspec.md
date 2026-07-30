# Guide: adopt OpenSpec as your spec tool

ASDD is spec-tool-agnostic: it requires that a spec exists and that the change is checked against it, not
that a particular tool produced it. If your project already authors specs with
[OpenSpec](https://github.com/Fission-AI/OpenSpec), turn this on and ASDD governs your OpenSpec changes
without you converting anything. If you do not, the built-in definition of ready stays the default and
nothing here applies.

OpenSpec is the spec *lifecycle* ASDD adopts rather than reinvents: a change is a reviewed delta against
living specs that accumulate as the source of truth. ASDD governs the boundary around that lifecycle.

## Turn it on

In `.asdd.yml`:

```yaml
spec_tool: openspec
```

That one line does two things:

1. **Readiness delegation.** "Is this change's spec ready?" is answered by OpenSpec's own
   `openspec validate --strict`, not by ASDD's four-field definition of ready. ASDD reads the verdict
   from the validator's JSON (a change with a hard error still exits 0, so the exit code is not trusted).
2. **Layout recognition.** The intake gate treats an OpenSpec change as spec-driven automatically - its
   deltas under `openspec/changes/*/specs/**/*.md` and the living specs under `openspec/specs/**/*.md` -
   with no hand-written `spec_paths`. Set `spec_paths` explicitly only if your layout differs; an
   explicit list always wins over the preset.

## Install the CLI where the gate runs

The delegation shells out to the real `openspec`, so it must be on `PATH` in the environment that runs
the gate:

- **CI:** add a step that installs it before the review job, e.g. `npm install -g @fission-ai/openspec`.
- **Locally / Goose:** install it once (`npm install -g @fission-ai/openspec`); `asdd openspec-gate
  <change>` and the `openspec_gate` MCP tool call it.

If the binary is missing, the gate reports a **setup error** (distinct from a failing spec) so CI tells
"install the tool" apart from "fix the spec".

## What each stage does with OpenSpec

- **Authoring.** `/asdd:spec` (or the interaction agent) defers to OpenSpec: run `openspec new change`,
  write the spec deltas (`## ADDED/MODIFIED/REMOVED Requirements` with `#### Scenario:`
  blocks), and validate. Only a change OpenSpec calls valid is ready.
- **Intake.** A PR that adds or edits an OpenSpec change is recognised as spec-driven; one that changes
  code with no delta is not (unless the lane is `chore`).
- **Review.** The `review-spec` lens reads the change's spec deltas as the spec of record and
  checks the code against them.
- **After merge.** `openspec archive` folds the delta into the living specs. ASDD leaves this to your
  project (it is OpenSpec's lifecycle step); the documentation agent can run it.

## Pin the version

OpenSpec is a moving CLI. The gate is pinned to its JSON schema version and fails loudly (a setup error)
if the shape drifts, so a silent format change cannot quietly turn the gate into a rubber stamp. Pin the
`openspec` version you install in CI, and re-check the gate when you bump it.

## Turning it back off

Remove the `spec_tool` line (or set `spec_tool: builtin`). The built-in definition of ready takes over
and the OpenSpec CLI is no longer required. Nothing else changes.
