# Guide: deploy ASDD with Goose (end to end)

From an empty repo to a governed, agent-run project: the gates on every PR, the operate agents running,
a knowledge source they answer from, and a dashboard plus a chat surface. This ties the per-topic guides
together in order. For plain Goose (install, providers, configuration) it links
[Goose's own docs](https://block.github.io/goose/docs/) rather than repeating them.

If you only want the fast path, do [the Goose quickstart](operate-goose.md) instead; this is the full
deployment.

## What you'll need

Gather these first. The bracketed ones are decisions only you can make.

- **A GitHub repo** to govern (yours, or a fork you maintain).
- **A model.** Either a provider API key, or a local model via Ollama (free, no key). *[decision: which
  provider, or local]*
- **The roster.** ASDD runs a heterogeneous fleet: the **developer is bring-your-own** (a contributor
  connects their own coding agent); the **tester and reviewer must run a model distinct from the
  developer's** (`developer != tester` is the one hard rule). *[decision: which models]*
- **The runtime wiring** for live CI review and live agents: `ASDD_MODEL_URL` (the full
  `.../v1/chat/completions` URL) and `ASDD_MODEL` as repo **Variables**, and `ASDD_RUNTIME_TOKEN` as a
  repo **Secret**. Without them the pipeline runs in a labelled dry-run.
- **A knowledge source** the agents answer from ("the wiki"): your repo's own docs by default, or a
  read-only knowledge server. *[decision: repo docs, or a knowledge MCP]*
- **An interface**, if you want a chat surface: which platform (Slack, Discord, web) and its credentials
  (a bot token, an app + signing key). *[decision: which surface]*
- **Governance choices**: your lanes/pillars, protected paths, merge posture (start advisory). *[decision]*
- **A human** to approve merges. You plus the agents are enough to start; the agents do the review, you
  make the merge call.

## 1. Install and configure Goose

Follow [Goose's install guide](https://block.github.io/goose/docs/getting-started/installation) and then:

```bash
goose configure
```

Pick any provider Goose supports, or a local model for free:

```bash
ollama pull qwen3:8b     # free, no key, good enough to try the loop
```

The ASDD recipes are provider-neutral; you set the model per run. See
[Goose configuration](https://block.github.io/goose/docs/getting-started/providers) for provider setup.

## 2. Scaffold ASDD into your repo

Install the CLI, then scaffold your repo:

```bash
pip install git+https://github.com/OneHillAI/ASDD
asdd init --goose /path/to/your-repo
```

Or run `bash cli/init.sh --goose /path/to/your-repo` from a checkout.

This writes the constitution (`AGENTS.md`), `.asdd.yml`, the PR template and `CODEOWNERS`, the lane
labels, and the operate kit (recipes, the deterministic gates, the `asdd-gates` MCP, the operate-agent
guard, the docsync workflow). Details: [adopt the govern layer](adopt-govern.md) and
[operate with Goose](operate-goose.md).

## 3. Turn the gates on (govern)

The intake gate (disclosure + DCO + one lane) runs on every PR immediately, deterministic, no model. The
review pipeline runs in **dry-run** until you wire a model (step 4): the deterministic and SAST security
lens still bites. Then make it stick with branch protection: require the intake and review status checks
and a Code Owner review, and block direct pushes. See [adopt-govern](adopt-govern.md).

## 4. Wire the model runtime

Set the three repo values from "What you'll need" (Settings, Secrets and variables, Actions). With them
set, the review lenses go live and the operate agents can run against a real model. Get the URL right:
it is the full `/chat/completions` endpoint, not the base. See
[adopt-govern](adopt-govern.md#wire-a-live-model-optional).

## 5. Run the agents (operate)

- **Reviewer**: automatic in CI once the runtime is wired (the review pipeline from step 3).
- **Documentation**: post-merge, via the docsync workflow. See [run operate agents in CI](operate-in-ci.md)
  and its security classification (a tool-using agent runs only on trusted input).
- **Tester and interaction**: run each recipe with its model. Keep the tester's model distinct from the
  developer's:

```bash
goose run --recipe recipes/test-runner.yaml        --model <tester-model>  --params pr=<PR>
goose run --recipe recipes/interaction.yaml   --model <public-model>  --params platform=slack
```

Readiness is the whole roster proven on a real artifact, not the reviewer alone (the OP.5 bar):
`asdd check-models --strict` enforces `developer != tester`. Details: [operate-goose](operate-goose.md).

## 6. Connect a knowledge source (the wiki)

The interaction and support agents answer from your project's own knowledge and cite the source. Two
ways to provide it:

- **Repo docs (default).** The shell-enabled recipes read your repo's docs, wiki, and prior issues
  directly, so a members-only deployment needs nothing extra.
- **A read-only knowledge server.** For richer knowledge, or for the untrusted public surface (which
  must be shell-free), wire a read-only knowledge MCP as an extension and point the agent at it. Use the
  execution-free [`recipes/interaction-public.yaml`](https://github.com/OneHillAI/ASDD/blob/main/recipes/interaction-public.yaml) for public
  surfaces; do not give it the shell builtin.

## 7. Add the interfaces

- **The governance dashboard.** A read-only view of PRs by stage, lanes, verdicts, and releases.
  Regenerate on a schedule and publish where your maintainers can see it. See
  [the governance dashboard](governance-dashboard.md).
- **A chat surface (Slack, Discord, web).** The interaction agent is the outer membrane. Ship it in two
  stages: **Stage 1 members-first** (trusted identity, the shell-enabled `interaction.yaml`), then
  **Stage 2 public** (anonymous propose-only, the execution-free `interaction-public.yaml`, gated by a
  human-verification / anti-bot binding). The platform connector and the anti-bot check are pluggable
  bindings you provide, like any deployment integration. Contract:
  [agents/interaction.md](https://github.com/OneHillAI/ASDD/blob/main/agents/interaction.md).

## 8. Operate it going forward

Every contribution flows: a PR opens, the intake gate checks it, the review lenses run, a human merges.
Protected paths stay human-approved. Cut releases by dating the changelog and tagging. Keep the recipe
dist copies in sync ([distribute](distribute.md)). Watch it through the dashboard. The one hard rule
(`developer != tester`) and the operate-agent security rule (a tool-using agent never runs automatically
on untrusted input) hold throughout.

That is a full deployment: governed PRs, live agents, a knowledge source, and an interface, with a single
human on the merge line.
