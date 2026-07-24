# ASDD documentation

ASDD, Agentic Spec-Driven Development, is a standard for running a software project with AI agents:
governed, disclosed, secure, and quality-gated. These docs are organised by what you came for.

## Start here

- **New to ASDD?** Read [why it exists](concepts/why-asdd.md), then [what it is](concepts/what-is-asdd.md),
  then [how it works](concepts/how-it-works.md).
- **Want to run it?** [Adopt the govern layer](guides/adopt-govern.md), then run the operate layer with
  [Goose](guides/operate-goose.md) or [your own runtime](guides/operate-other.md).
- **Comparing it to other tools?** [Prior art: how ASDD differs](prior-art.md).

## The four modes

| Mode | For | Where |
|---|---|---|
| **Explanation** | understanding why and what | [concepts/](concepts/why-asdd.md) |
| **Tutorial** | getting a governed loop running | [guides/operate-goose.md](guides/operate-goose.md) |
| **How-to guides** | a specific setup task | [guides/](guides/deploy.md) |
| **Reference** | precise lookup: the standard, the agents, the CLI | [reference/](reference/README.md) |

## Guides

- [Deploy ASDD with Goose (end to end)](guides/deploy.md): the full setup, gates + agents + knowledge + interfaces, with a "what you'll need" checklist. Start here for a full deployment.
- [Adopt the govern layer](guides/adopt-govern.md): the CI gates that make a project conformant.
- [Using ASDD as one person](guides/using-asdd-solo.md): run your agents under their own identity so you, a solo maintainer, can approve and merge their PRs.
- [Adopt into a project that already exists](guides/adopt-existing-project.md): the brownfield path.
  Declare the spec layout, changelog format, impact log and house style your project already has, so the
  agents conform to them instead of guessing. Gates judge the change, never your existing tree.
- [Operate with Goose](guides/operate-goose.md): the ready-to-run operate layer, with a free no-keys
  "prove it runs" step.
- [Operate on your own runtime](guides/operate-other.md): implement the runtime contract on any platform.
- [Share and run the recipes by name](guides/distribute.md): deeplinks, `GOOSE_RECIPE_PATH`, and fetch-from-GitHub.
- [The agent audit ledger](guides/audit-ledger.md): what every agent action records, where the ledger is
  stored, and how to see it.
- [OKGF as the knowledge layer](guides/okgf-integration.md): how ASDD emits OKGF pages and connects to an OKGF store for reviewed, reusable knowledge.
- [The governance dashboard](guides/governance-dashboard.md): a read-only view of PRs by governance stage, lanes, verdicts, and releases.
- [Run operate agents in CI](guides/operate-in-ci.md): the automation pattern and the security classification it must respect.
- [The slash commands](guides/slash-commands.md): the CLI's front door inside a coding assistant, and how to port them to any assistant.
- [Adopt OpenSpec as your spec tool](guides/adopt-openspec.md): turn on `spec_tool: openspec` and govern OpenSpec changes without converting.
- [The gates, and how to tune them](guides/gates-and-requirements.md): every requirement ASDD enforces, the floor vs the knob, and the `.asdd.yml` key that controls it.
- [Troubleshooting](guides/troubleshooting.md): common failures and fixes.

## Reference and contributing

- [Reference](reference/README.md): [STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md), the standards profiles, the agent
  roles, the CLI and gates.
- [Contributing to ASDD](contributing-to-asdd.md): how ASDD is developed under ASDD (dogfood).
