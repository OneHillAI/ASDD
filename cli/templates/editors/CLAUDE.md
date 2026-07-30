# Contributing to this repository with a coding agent

This repository is governed by ASDD (Agentic Spec-Driven Development). Before you write code here,
read [AGENTS.md](AGENTS.md): it is the contribution constitution, and it binds every assistant, this
one included. This file is a pointer to it, not a second set of rules.

The rules that shape a change:

- **Disclose the agent.** Say in the pull request and the commit trailer that an AI agent helped, and
  sign every commit off with `git commit -s`.
- **One lane per pull request.** Tag the change with exactly one lane label (the set is in `.asdd.yml`).
- **Spec first.** A feature or fix points to a spec that says what "done" is; open or reference one
  before building. The `chore` lane is the only spec-exempt lane.
- **Tests run on a different model.** You are the developer. The test agents run on a model that must
  differ from yours, so your own tests are not the check that decides the change.
- **A human merges.** Agents review and recommend; a named human approves and merges. You do not merge
  your own work.

Turn an idea into a spec by talking it through with the spec agent (`/asdd:spec`), and run `asdd status`
to see where a change stands. Full guide: [bring your own developer](docs/guides/bring-your-own-developer.md).
