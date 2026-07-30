# Guide: the slash commands (bring your own assistant)

ASDD has three ways in: the CI gates, the CLI, and the Goose operate kit. The slash commands are the
CLI's front door inside a coding assistant. They ship for Claude Code under
[`.claude/commands/asdd/`](../../.claude/commands/asdd/), but the substance is in the CLI they call, not
in the prompts, so they port to any assistant in minutes.

That is the whole point: **ASDD does not live inside your assistant.** The commands are thin wrappers
over `asdd ...`; the gates, the config, and the pipeline are files in your repo. Bring Claude Code,
Cursor, Copilot, or your own harness - the governance is identical.

## The four commands

| Command | What it does | The CLI underneath |
|---|---|---|
| `/asdd:setup` | Walks a maintainer through wiring a model to each agent role, in plain language, and refuses a `developer == tester` assignment. | `asdd setup` |
| `/asdd:spec` | Turns an idea into a spec that passes the intake gate. It fills the definition of ready (outcomes, scope, constraints, verification), writes it where `spec_paths:` says, and checks it with the same gate the pipeline runs. On an OpenSpec project it defers to `openspec`. | `asdd spec-check` (or `openspec validate`) |
| `/asdd:review` | Runs the review the way the pipeline will, before you push: the deterministic gates first, then the lenses if a model is wired. | `asdd openspec-gate` / the review lenses |
| `/asdd:status` | Shows the governance state: what the agents are doing and under what steering, from the read-only dashboard. | `asdd dashboard` |

## Why a spec that passes locally passes on the PR

`/asdd:spec` and `/asdd:review` call the **same** deterministic gates the CI pipeline calls - there is no
second implementation to drift. A spec that `asdd spec-check` accepts on your machine is accepted at
intake; a change the local review flags is the change the pipeline flags. The commands are a faster
feedback loop over the identical code, not a preview of it.

## Porting to another assistant

Each command is a short Markdown prompt whose only job is to invoke a CLI subcommand and read back its
output. To bring your assistant of choice:

1. Install the CLI: `pip install git+https://github.com/OneHillAI/ASDD` (or `pip install .` from a
   checkout; the wheel is self-contained).
2. Copy the four prompts from [`.claude/commands/asdd/`](../../.claude/commands/asdd/) into your
   assistant's command format. The bodies are plain instructions; only the file location and front
   matter are Claude-Code-specific.
3. The commands assume `asdd` is on `PATH`. That is the only dependency.

## Steering: read on the dashboard, write via the CLI and config

The commands are for **doing** (draft a spec, run a review, wire a model). To **steer** - change what the
gates require, which paths are protected, which model a role runs on - edit `.asdd.yml` and the
`recipes/`, and read the current state with `/asdd:status`. Nothing steers by chat: the config is the
source of truth, and the agents pick it up from there. See
[gates-and-requirements.md](gates-and-requirements.md) for every knob.
