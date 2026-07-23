# Quickstart: ASDD with Goose

> **Status: alpha.** This operate layer is usable and dogfooded, but its recipes and interfaces may
> still change before a stable release. The standard is a separate v0.1 draft.

Zero to a governed agentic-dev loop. You need Python 3.9+ and [Goose](https://block.github.io/goose/).
**No paid model account is required to try it** - a local model via Ollama works for free.

> **Adopting into a project that already exists?** Read
> [adopt-existing-project](adopt-existing-project.md) alongside this. A mature repository already has a
> spec layout, a changelog format and a house style, and the agents must be told about them or they
> produce work in the wrong place.

> ASDD's operate layer runs two ways: **your own operator** (any runtime satisfying
> [`agents/runtime.md`](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md)) or **Goose** (this guide). The standard mandates neither.

## 1. Get the CLI on your PATH

Clone ASDD, then either symlink the launcher (pip-free) or install it:

```bash
ln -s "$PWD/asdd_cli.py" ~/.local/bin/asdd      # pip-free; or, with a recent pip:  pip install -e .
```

No install needed either - `python3 asdd_cli.py <command>` and `bash cli/init.sh` work straight from the
checkout. `asdd --help` lists the commands.

## 2. Install into your repo

```bash
asdd init --goose /path/to/your-repo
```

`--goose` scaffolds the govern config **and** the operate kit: the recipes, the four deterministic gates,
and the `asdd-mcp` MCP extension. Existing files are skipped unless `--force`, so it won't clobber a
customised repo. It also sets the project's contribution lanes to the architecture-aligned operate
taxonomy (`govern/operate/know/assure/standard/docs/chore`); see
[contribution lanes for an operated project](operate-lanes.md) to trim or override them.

## 3. Configure a model

```bash
goose configure
```

Pick any provider Goose supports - Anthropic, OpenAI, Google, any OpenAI-compatible endpoint, or a local
model. The recipes are **provider-neutral**; you set the model per run. For a free local try:

```bash
ollama pull qwen3:8b
```

Then assign a model to each agent role. Do not hand-edit `.asdd.yml` blind - the wizard prompts for each
role, keeps the developer distinct from the test models (the one hard rule), and prints the run commands
and CI secrets for the models you picked:

```bash
asdd setup            # interactive; or --set test_author=A --set test_runner=B --set developer=C
```

Prefer a page to a prompt? `asdd setup-dashboard` opens the same thing as a local (127.0.0.1) web form.

### A known-good roster to start from

The recipes are provider-neutral, but not every model works behind every provider, so trial and error
costs you an afternoon. This roster is proven end to end and is a safe starting point:

| Role | Model | Where | Why |
| --- | --- | --- | --- |
| developer | your own (e.g. Opus 4.8) | its **native** provider (bring your own) | builds the code; native provider translates the tools correctly |
| reviewer | GLM-5.2 | Runware (OpenAI-compatible) | strong open-weight; tolerant of Goose's tool schemas |
| test_author / test_runner | Kimi K2.6 | Runware | a different family from the developer (the heterogeneity rule) |
| documentation / interaction | GLM-5.2 or Kimi K2.6 | Runware | either works; just keep them off a model that rejects tools |

The rule behind it: **a tool-using role needs a tool-tolerant provider.** Some OpenAI-compatible
providers reject a no-argument tool's empty schema (a `400` on `tools`), so a capable model can still
fail behind a strict provider even though the model itself is fine. GLM-5.2 and Kimi K2.6 accept them; a
bring-your-own developer should run on its model's **native** provider, where the tools translate
correctly. For Runware specifically, set `supports_streaming: false` on the provider (see
[Troubleshooting](troubleshooting.md)). Both traps have troubleshooting entries if you hit them on a
different provider.

**Or let an agent walk you through it.** The setup recipe reads [`asdd-kit.yml`](../../asdd-kit.yml) -
the kit map: every role, its recipe, its model key, where it runs, and the invariants - so it starts
oriented instead of reading the kit to work it out. It tells you what is configured, what is missing,
and does the safe parts for you:

```bash
goose run --recipe recipes/setup.yaml --model <your model>
```

That model is also your **developer**: the developer is bring-your-own, so your own Goose session is it.

## 4. Check the kit is valid

Run the preflight first. It checks the things that fail silently otherwise: whether Goose and (if you
chose `spec_tool: openspec`) the openspec CLI are actually reachable, whether your roster obeys the one
hard rule, and whether the recipes are in place. Crucially it tells apart "not installed" from
"installed but not on your PATH" - the latter reads as "missing" to a bare `which` and sends people
reinstalling a tool they already have.

```bash
asdd doctor              # or: asdd doctor path/to/.asdd.yml
```

It never changes anything; it reports each item as OK, a warning, or a blocking issue, with the exact
next step. Then confirm the recipes validate against your installed Goose:

```bash
goose recipe validate recipes/test-runner.yaml
goose recipe validate recipes/interaction.yaml
# -> "recipe file is valid" for each
```

## 5. Prove it runs (free, no keys)

Confirm a Goose agent actually loads the gates and calls one, against a local model:

```bash
goose run --provider ollama --model qwen3:8b \
  --with-extension "python3 cli/asdd-mcp.py" \
  -t 'Call the merge_eligibility tool with paths=["crypto/aes.py"], protected="**/crypto/**", posture="earned-automerge". Report only the verdict.'
```

The agent loads the `asdd-gates` extension, calls the gate, and reports **`human-approve`** - a protected
path never auto-merges. If you see that, the operate layer works end to end.

## 6. Stand up the rest of the roster

The reviewer and the gate call are proven above. The test, documentation, and interaction agents are
not done until each has run against something real. Do not read the commands below as "set up"; read them
as "run it, then confirm it did the thing." Each runs with its own model (keep the test agents distinct
from whatever builds the code, `developer != test_author, test_runner`), and the recipe's own
instructions are the prompt, so you pass `--param`, not `-t`.

Run each agent with `asdd operate-run`, not `goose run` directly. The wrapper runs the recipe and then
records the action in the audit ledger **deterministically**: the agent writes its outcome to a result
file and the wrapper turns that into a record, so a provider timeout part way through a long run cannot
silently lose the action. It records the role, so the interaction agent runs as `--role spec` (the role
it records under).

**Test agents.** Authoring the tests and executing them are two jobs, and ASDD splits them:
`test-author.yaml` writes the coverage the change needs from the spec, and `test-runner.yaml` runs the
suite and reports pass or fail. Both run on models distinct from the developer's, so their blind spots
do not line up with the code's. Before running the runner, decide who actually *executes* the suite and
where: the agent itself, CI, or the Goose `developer` builtin shell. The recipe drives the check; you
point it at the executor you chose.

```bash
asdd operate-run --role test-runner --recipe recipes/test-runner.yaml --model <test-runner-model> --param pr=<PR>
```

Proven when it reports a real pass or fail on a real PR, not a template run.

**Documentation.**

```bash
asdd operate-run --role documentation --recipe recipes/documentation.yaml --model <doc-model> --instructed-by you --param change_ref=<PR>
```

Proven when it writes a correct doc or knowledge update for an actual change.

**Interaction.** `platform=web` below is a placeholder. The real work is the platform binding (Slack,
Discord) and proving the agent answers from project knowledge and routes an idea into the spec pipeline via the spec_check gate.

```bash
asdd operate-run --role spec --recipe recipes/interaction.yaml --model <public-model> --param platform=web
```

Proven when it answers one real question from project knowledge and routes one real idea in as a
validated spec. Interaction is **on-demand**: you run it (or bind it to a surface) when you want it; it
does not fire on its own. On an untrusted public surface use `recipes/interaction-public.yaml`, which is
execution-free.

**Operator-run agents (triage, support, contributor & merge review).** These four are fixed-prompt agents,
not recipes, and they are not part of the automatic PR gate: you run them on demand with `asdd run-agent`,
which drives the agent through the model and records the action, safely (the input is fenced as untrusted
data, exactly as the review gate does).

```bash
asdd run-agent triage new-issue.txt                 # propose labels + a welcome (allow-list enforced by policy-check)
asdd run-agent review-contributor change.diff       # suggestions to bring a change to ready
asdd run-agent review-merge merge-evidence.txt      # the independent final check before a human merges
asdd run-agent support question.txt                 # answer from the project's own knowledge
```

Proven when each returns its structured output on a real input. With no model wired it prints a labelled
dry run. See [cli/README.md](../../cli/README.md) (`run-agent`).

**Automated on trusted input.** Two agents also run themselves *after* a human merges, where the input is
trusted: the `asdd-docsync` workflow (documentation) and the `asdd-test` workflow (a post-merge regression
run of the test agent). Both are installed by `init --goose`, both dry-run until a model is wired, and both
refuse to run on untrusted pre-merge input. The tester is deliberately **not** run automatically on an open
PR: executing a stranger's code needs an egress-free sandbox this kit does not ship (see
[operate-in-ci.md](operate-in-ci.md)); author and run tests in the produce loop instead.

The **developer is bring-your-own** and is exempt: a contributor connects their own coding agent to build
a change. "Set up" means every agent above has run against a real artifact, not that the reviewer works
and the rest are listed.

## How it fits together

- A contributor (or your own agent) builds a change and opens a PR.
- The **test author** extends the suite from the spec, and the **test runner** (both on models distinct from the developer's) runs it.
- The **CI review gates** (the govern layer, `.github/asdd/`) review it; a human merges.
- The **interaction** agent brings public ideas in as validated specs (via the intake gate).

The gates are callable directly too: `asdd merge-eligibility ...`, `asdd spec-check ...`, `asdd validate`.

## Enforce the one hard rule

```bash
asdd check-models --strict     # fails if a test model == developer
```

## Optional: the developer council

The single-model developer is the default, and it is bring-your-own. If you want more than one model on a
change, the **developer council** is an optional produce-loop developer: 2 to 5 diverse models propose,
cross-critique, synthesise and verify one implementation of an OpenSpec change. `init --goose` copies its
runner, and `asdd setup` offers to configure it. Turn it on by naming the models in `.asdd.yml`:

```yaml
dev_council:
  models: ["provider:a", "provider:b", "provider:c"]   # 2 to 5; the LAST is the lead synthesiser
```

Run it in your produce session:

```bash
asdd dev-council --change my-change --transcript council.json
# or the shipped runner:  bash .github/asdd/operate/dev-council.sh my-change
```

Wire the models like the rest of the fleet (shared `ASDD_MODEL_URL` + `ASDD_RUNTIME_TOKEN`, or per-member
`__COUNCIL_<i>` variants). It records its process to the ledger, so the corpus and knowledge base learn
from it. Full detail: [cli/README.md](https://github.com/OneHillAI/ASDD/blob/main/cli/README.md) and the
contract in [agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md).

## Share the recipes

To run the agents by bare name instead of a full path, or hand someone a single recipe as a link, see
[share and run the recipes by name](distribute.md).
