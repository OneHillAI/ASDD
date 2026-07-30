# Troubleshooting

Common failures when setting up ASDD, and the fix. For Goose's own install issues, see the
[Goose docs](https://block.github.io/goose/); this page covers only the ASDD overlay.

## The intake gate fails a PR

The gate reports the specific check that failed. The three, and their fixes:

- **Authorship disclosure missing.** The PR body must contain the disclosure block from the PR template.
  Copy it in and mark whether an agent contributed.
- **A commit is not signed off.** Every commit needs a `Signed-off-by` trailer. Re-commit with
  `git commit -s` (or `git rebase --signoff` for existing commits).
- **Not exactly one lane tag.** Add one, and only one, lane label (one of the lanes in `.asdd.yml`, e.g. `feature`, `fix`, `docs`, `chore`). No lane means
  no stated purpose; two means the PR is doing two things.

## `goose recipe validate` rejects a recipe

Two schema mistakes account for most of it: a stdio extension with a commented-out or missing `cmd`
(give it a real command), and a declared parameter that is never referenced (every `parameters` entry
must appear as `{{ param }}` in the instructions). The shipped recipes pass validation as a reference.

## A Goose run fails with "Stream decode error" on an OpenAI-compatible provider

Some OpenAI-compatible endpoints end a streamed response with an empty `delta` array (`"delta": []`)
where Goose expects a delta object, so the run errors after the content has already arrived. Turn
streaming off for that provider: in the desktop app, edit the provider and untick "Provider supports
streaming responses"; from the config, set `"supports_streaming": false` in the provider's file under
`~/.config/goose/custom_providers/`. Agents do not rely on token streaming, so nothing is lost.

## A Goose run fails with `400 Invalid value for 'tools'` on an OpenAI-compatible provider

Some providers reject a tool whose schema has empty `properties` (a no-argument tool), returning
`Function schema properties must be a non-empty object`. Goose's builtin tools include no-argument ones,
so a model reached through a strict provider refuses the whole request even though the model itself is
fine. The same tools work on a more lenient provider. If a role's model hits this, run that role on a
provider or model that accepts them; a bring-your-own developer can use the model's native provider,
where the tools are translated correctly.

## The review pipeline posts nothing, or says "dry-run"

That is expected until a model is wired. The deterministic gates and the security lens still run and
still block; the model lenses stay off until you set the runtime inputs (see
[adopt-govern](adopt-govern.md#wire-a-live-model-optional)). To try the operate layer for free first, use
a local model. [operate-goose](operate-goose.md) walks the no-keys path with Ollama.

## `check-models` fails

`asdd check-models --strict` exits non-zero when `models.developer == models.tester`, or when the
reviewer is not distinct. That is the invariant doing its job: set distinct models in `.asdd.yml`. Run it
without `--strict` while your roster is still a template, since unset models pass in that mode.

## A protected-path change is stuck on human approval

That is by design and cannot be overridden by any agent verdict. `merge-eligibility` routes any change
touching a protected path to `human-approve` unconditionally. A named human in `CODEOWNERS` approves it.

## `openspec: command not found`, but you installed it

`npm install -g @fission-ai/openspec` puts the binary in npm's global bin directory, which is very often
not on a non-login shell's PATH (a common default is `~/.npm-global/bin`). So `which openspec` finds
nothing and it looks uninstalled when it is not. Two things to know: the ASDD openspec gate now resolves
the binary in npm's global locations even when it is off PATH, so CI and the gate keep working either
way; and `asdd doctor` reports the exact case, printing the path it found and the line to add. To use
`openspec` yourself, add its directory to PATH, e.g. `export PATH="$HOME/.npm-global/bin:$PATH"` (put it
in your shell profile). If it is genuinely absent, `asdd doctor` says so and `spec_tool: openspec`
projects should install it or set `spec_tool: builtin`.

## A backgrounded `goose run` writes an empty log

Goose buffers its output when stdout is a file or pipe rather than a terminal, so a run launched with
`nohup goose ... > run.log &` shows nothing in `run.log` until it exits. This is standard TTY buffering,
not a Goose or ASDD fault. Run the agent in the foreground to watch it live, or, if you must script it,
attach a pseudo-terminal (`script -q /dev/null goose ...`, or `unbuffer goose ...` from `expect`). If you
only need the result, read the log after the process finishes; the content is all there.

## `Concurrent request limit reached` from an OpenAI-compatible provider

Some providers (Runware among them) reserve concurrency against your account balance, so firing several
agent runs at once trips a concurrent-request limit. Space the runs out, or raise the balance to lift the
limit. Note that the operate loop for a single change is a dependency chain anyway (the tester needs the
developer's output, docs need the merge), so the agents within one change run in sequence regardless;
concurrency only buys you running independent changes in parallel.

## `asdd: command not found`

The launcher needs to be on your PATH or run from a checkout. Symlink it
(`ln -s "$PWD/asdd_cli.py" ~/.local/bin/asdd`; it resolves the symlink to find its tools) or run
`python3 asdd_cli.py <command>` straight from the repo. See [operate-goose](operate-goose.md#1-get-the-cli-on-your-path).
