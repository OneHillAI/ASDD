# Spec: local setup dashboard for "ASDD with Goose"

## Problem

`asdd setup` wires the per-role models from the command line. A non-engineer maintainer wants the same
thing as a page: see the roles, assign a model to each, watch the heterogeneity rule pass or fail, and
read the next steps, without editing YAML or reading CLI output. The governance dashboard
(`cli/dashboard.py`) is a read-only, static, publish-anywhere artifact; a setup surface is interactive
and writes config, so it must be a separate local surface, not folded into that static view.

## Requirements

- A local web page, `asdd setup-dashboard`, that lists the agent roles from the config's `models:`
  block, pre-filled, with each role's hint, and writes the block on save.
- It validates the result with the same rule as the CLI by reusing `setup-goose.py`'s read/write/validate
  logic (single source of truth), so the wizard and the dashboard can never disagree.
- It shows the live heterogeneity check output and the next steps (`goose configure`, the CI secrets,
  the per-recipe run commands).
- It reuses the governance dashboard's styling so the two read as one product, but shares no code with
  it and does not modify `cli/dashboard.py`.
- Security: it binds to `127.0.0.1` only and guards every write with a per-run token, so a page on
  another origin cannot POST to it. It never runs Goose or any agent; it writes config and shows the
  commands to run. Model input from the form is sanitised before it reaches the config.
- The config defaults to `./.asdd.yml`, like `asdd setup`. Zero runtime dependencies (stdlib).
- Model fields are a combobox, not a fixed dropdown: free-text (any model a provider serves, since ASDD
  is provider-neutral) backed by a datalist of the models already in use, so it suggests without shipping
  a catalogue that would go stale. It embeds the canonical agent-roster diagram
  (`docs/diagrams/agents.svg`) so the maintainer sees which agents they are setting a model for.

## Acceptance criteria

- `--render` produces a page containing a field per role and the CSRF token field.
- The write path persists distinct models and reports the heterogeneity check as passing; a test model
  equal to the developer reports failing.
- Model input containing quotes or newlines is stripped before it is written.
- A POST without the correct token is rejected and changes nothing (verified by a live smoke; the
  deterministic slice covers render, write and sanitisation in `cli/setup-dashboard.test.sh`).

## Out of scope

- Running Goose or the agent loop from the page (deferred; a browser-triggered command runner is a
  separate, security-sensitive step).
- Connecting provider credentials (that is `goose configure`, which owns the keyring).
- A unified local "ASDD console" (Govern / Insights / Setup tabs); standalone is the reversible step
  that a future unified shell can fold in.
