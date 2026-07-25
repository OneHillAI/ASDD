# Bring your own developer

ASDD does not ship a developer. The agent that writes the code is always the contributor's own: their
coding assistant, or their hands. A deployment never runs a standing developer against your repository,
because the point of the pipeline is to govern what any developer produces, not to be one.

That leaves a practical question: how does a contributor's assistant learn the rules of this repository?
The answer is that the rules live in the repository as files, so the assistant reads them the same way it
reads the code.

## Your assistant reads the constitution automatically

`asdd init` writes [AGENTS.md](../../AGENTS.md), the contribution constitution, and a thin pointer for the
common assistants so each one loads it without any manual setup:

| Assistant | Reads | Written by `init` |
|-----------|-------|-------------------|
| Claude Code, Claude in the app | `CLAUDE.md` | pointer to `AGENTS.md` |
| Cursor | `.cursor/rules/asdd.mdc` | pointer to `AGENTS.md` |
| Codex, and any assistant following the AGENTS.md convention | `AGENTS.md` | the constitution itself |

Each pointer is a few lines that hand the assistant the five rules that shape a change (disclose the
agent, one lane per pull request, spec first, tests on a different model, a human merges) and send it to
`AGENTS.md` for the rest. `init` never overwrites one you already have, so an existing `CLAUDE.md` or
Cursor rule set is left alone; delete the pointer if you do not want it.

You do not have to use one of these assistants. The rules are files and CI, so a contributor on a tool
nobody has heard of is governed exactly the same way. The pointers are a convenience for the common case,
not a requirement.

## Starting from an idea, not a spec

A change begins with a spec, but you do not have to write one first. Talk the idea through with the spec
agent (`/asdd:spec`, or the `spec` recipe on the operate kit) and it drafts the spec with you: the
outcome, the scope, the constraints, and how "done" is checked. It parks an idea that is not ready yet
instead of forcing a half-formed one through. This is the path that lets a non-engineer bring a real,
reviewable change: describe what you want in plain language, and the spec agent turns it into the artefact
the pipeline needs.

## The agents that come with it are free to run

The developer is yours, but the operate agents (test author, test runner, documentation, interaction) are
provided, and they run on [Goose](https://block.github.io/goose/), which is open source and free. You
bring an API key for a model; you do not buy the harness. The [Goose quickstart](operate-goose.md) includes
a no-keys "prove it runs" check so you can see the loop work before wiring a model.

## What a contributor actually does

1. Point your assistant at the repository. It reads `AGENTS.md` through the pointer for your tool.
2. Turn the idea into a spec with the spec agent, or reference an existing one.
3. Build the change and open a pull request: disclose the agent, sign the commits off, one lane label.
4. Intake, then review, run on the pull request. Fix what they flag.
5. A human merges.

See also: [the constitution](../../AGENTS.md), [slash commands](slash-commands.md), and
[using ASDD solo](using-asdd-solo.md) for giving your agents their own GitHub identity so they open pull
requests you approve.
