# Guide: run operate agents automatically in CI

The operate agents (tester, documentation, interaction) can run by hand
([operate-goose](operate-goose.md)) or automatically in CI. Automating them is safe only under one rule,
so read the classification first.

## The security classification (read this before automating anything)

Whether an operate agent may run automatically depends on two things: what it can do, and what it runs on.

- **Input is trusted or untrusted.** Post-merge content (a human already reviewed and merged it) is
  trusted. Pre-merge content from a pull request, especially a fork, is untrusted, the same membrane as
  the review lenses.
- **The agent is tool-using or execution-free.** A tool-using agent has a shell (the Goose `developer`
  builtin): it can run commands and reach the network. An execution-free agent has no shell, only
  read-only knowledge and the `spec_check` gate (for example [`recipes/interaction-public.yaml`](https://github.com/OneHillAI/ASDD/blob/main/recipes/interaction-public.yaml)).

The rule: **a tool-using agent must not run automatically on untrusted input.** A prompt injection in
that input could use the shell to exfiltrate the model credential. A tool-using agent runs automatically
only on trusted input (post-merge), or, on untrusted input, only if it is execution-free or sandboxed
with no network egress.

This is not left to a comment. [`cli/operate-guard.py`](https://github.com/OneHillAI/ASDD/blob/main/cli/operate-guard.py) enforces it, and every
operate runner calls it:

```bash
python3 cli/operate-guard.py recipes/documentation.yaml --input trusted     # ok (tool-using, trusted)
python3 cli/operate-guard.py recipes/documentation.yaml --input untrusted   # REFUSED (exit 1)
python3 cli/operate-guard.py recipes/interaction-public.yaml --input untrusted  # ok (execution-free)
```

## The shipped pattern: post-merge doc sync

`init.sh --goose` installs one worked example: the documentation agent, run **post-merge** (`on: push:
main`, so trusted input), which posts its proposed doc updates as an advisory comment on the merged PR.
It proposes only; it never merges and never edits code, and it dry-runs until a model is wired.

- Workflow: `.github/workflows/asdd-docsync.yml`
- Runner: `.github/asdd/operate/docsync.sh` (calls the guard, then the documentation recipe)

Because the trigger is post-merge, the tool-using documentation agent is allowed. The runner still asserts
it through the guard, so the classification holds even if someone changes the trigger later.

## Adding another agent

Copy the pattern and keep the rule:

- A **tool-using** agent (tester, documentation) automates only on a **trusted** trigger (post-merge).
  The tester on an open PR needs the sandboxed path (no network egress, isolated secrets), not this
  single-workflow shape.
- An **execution-free** agent (the public interaction agent) may automate on an **untrusted** trigger,
  because it has no shell to exfiltrate through.

Wire a live model by setting the repo `ASDD_MODEL_URL` + `ASDD_MODEL` variables and the
`ASDD_RUNTIME_TOKEN` secret (the same config the review gate uses); until then the runner dry-runs.

Next: [operate with Goose](operate-goose.md) · [the interaction contract](https://github.com/OneHillAI/ASDD/blob/main/agents/interaction.md)
