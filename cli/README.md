# cli/ - ASDD tooling

## asdd (the unified CLI)

One command for the whole toolkit, so you don't call the scripts by path. It dispatches to the
tools below (which stay the single source of truth). Put it on your PATH by symlinking the launcher
(`ln -s "$PWD/asdd_cli.py" ~/.local/bin/asdd`; it resolves the symlink to find the tools) or, with a
recent pip, `pip install -e .`. Or run it straight from a checkout: `python3 asdd_cli.py <command>`.
See the [Goose quickstart](../docs/guides/operate-goose.md) for the end-to-end setup.

```bash
asdd init --goose /path/to/repo     # scaffold ASDD + the Goose operate kit
asdd spec-check spec.json           # the definition-of-ready gate
asdd merge-eligibility PATHS ...     # the conforming-loader merge floor
asdd claim-check / check-models / audit-check ...
asdd mcp                            # run the gates as an MCP server
asdd validate                       # the runnable-today validation slice
asdd --help
```

Each subcommand forwards its arguments to the underlying tool, so `asdd merge-eligibility --help` shows
that tool's options. For a Goose extension you can use `cmd: asdd, args: ["mcp"]` once `asdd` is on the
PATH (or `cmd: python3, args: ["cli/asdd-mcp.py"]` from a checkout).

## init

`init.sh` scaffolds ASDD governance files into a target repo. It is thin and auditable, and it
never pushes, merges, or deletes.

```bash
# run from a checkout of ASDD, against your repo:
bash cli/init.sh /path/to/your-repo
bash cli/init.sh --dry-run     # preview only (current dir)
bash cli/init.sh --force       # overwrite existing files
bash cli/init.sh --goose       # also install the Goose operator kit ("ASDD with Goose")
```

It:

1. copies `AGENTS.md` (the constitution) into the target,
2. writes `.asdd.yml` from the schema,
3. writes `.github/PULL_REQUEST_TEMPLATE.md` (the disclosure block),
4. writes `.github/CODEOWNERS` from the config's `protected_paths` (edit the owner),
5. ensures the lane labels (via `gh`, or prints the commands), and
6. prints the three model secrets to set.

With **`--goose`** it also installs the operate layer: the recipes
([`recipes/`](../recipes/) - the deployment-run tester / documentation / interaction agents, and the
optional bring-your-own developer reference), the deterministic gates, and the
[`asdd-mcp`](#asdd-mcp-goose--mcp-extension) extension so a Goose agent can call them. That is the whole
"ASDD with Goose" setup in one command, ready for `goose configure`.

Existing files are skipped unless `--force`. The review **pipeline** itself (the workflows and scripts)
comes from ASDD reference implementation; `init` sets up the configuration and governance files
that live in this repo, then tells you what to wire next. It also copies `check-models.sh` (below) into
the target's `scripts/`.

## setup

`setup-goose.py` is the **guided per-role model wizard**. `init --goose` scaffolds the files; `setup`
walks the one part that is easy to get wrong: giving each agent role a model while keeping the developer
distinct from the test models (the heterogeneity invariant). It reads the roles from the config's own
`models:` block (using each role's inline comment as the prompt hint, so a renamed or added role needs no
change here), writes the block, validates the result by calling `check-models.sh` (the single source of
truth for the rule), and prints the exact next steps: `goose configure`, the CI secrets, and the
per-recipe run commands with the models you chose.

By default it targets the `.asdd.yml` of the repo you run it in (not the ASDD checkout that ships the
tool), so an installed `asdd setup` configures the current project; pass a path to target another.

```bash
python3 cli/setup-goose.py                         # interactive; edits ./.asdd.yml (current repo)
python3 cli/setup-goose.py --set test_author=A --set test_runner=B --set developer=C
python3 cli/setup-goose.py /path/to/other/.asdd.yml --show   # inspect another repo, change nothing
sh cli/setup-goose.test.sh                          # self-test
```

Exit codes: `0` the resulting assignment is valid, `1` it breaks the heterogeneity rule (e.g. a test
model equals the developer), `2` usage / config error. Run it through the unified CLI as `asdd setup`.

**It never writes a credential.** `.asdd.yml` is version-controlled, so a key committed there stays in
git history even if you delete it later. The `models:` block takes **model names only**; if a value has
the shape of an API key the write is refused and you are pointed at where the key belongs: `goose
configure` locally (Goose keeps it in its own config/keyring), or the `ASDD_RUNTIME_TOKEN` secret with
`ASDD_MODEL_URL` / `ASDD_MODEL` for CI. The check is high-precision, so real model ids (including long
ones like `accounts/fireworks/models/...`) are never refused. `.asdd.example.yml`, the published
template, is never written either. The setup dashboard reuses this same guard.

## setup-dashboard

`setup-dashboard.py` is the same wizard as a **local web page** - the non-engineer front door. It shows a
form of the agent roles, the heterogeneity rule passing or failing live, and the exact next steps, and
writes the `models:` block on save. It reuses the governance dashboard's styling so the two read as one
product, but shares no code with it: `cli/dashboard.py` stays the read-only governance view.

It is local and interactive by nature, so it **binds to 127.0.0.1 only** and guards every write with a
per-run token (a page on another origin cannot POST to it). It **never runs Goose or any agent** - it
writes config, validates it, and shows you the commands to run yourself.

```bash
python3 cli/setup-dashboard.py                 # serve on 127.0.0.1 and open a browser
python3 cli/setup-dashboard.py --port 8787 --no-open --config /path/to/.asdd.yml
python3 cli/setup-dashboard.py --render         # print the page HTML and exit (no server)
sh cli/setup-dashboard.test.sh                  # self-test
```

The config defaults to `./.asdd.yml`, like `asdd setup`. Run it through the unified CLI as
`asdd setup-dashboard`. It reuses `setup-goose.py`'s tested read/write/validate logic, so the CLI wizard
and the dashboard can never disagree.

## resolve-model

`resolve-model.sh` turns a **role** into what it actually runs on - its **model, endpoint and key** - in
one place, so every run path agrees and *what you configure is what runs*. Per role (ROLE upper-cased,
`documentation` -> `DOCUMENTATION`):

| | resolves to | fallback |
|---|---|---|
| model | `models.<role>` in `.asdd.yml` | `$ASDD_MODEL` |
| endpoint | `$ASDD_MODEL_URL__<ROLE>` | `$ASDD_MODEL_URL` |
| key | `$ASDD_RUNTIME_TOKEN__<ROLE>` | `$ASDD_RUNTIME_TOKEN` |

So **one provider is the default**: set the two shared variables and every governance agent runs on it,
each on its own model. A role that needs **its own provider** gets one by setting the per-role variables,
without touching the others - the test roles on a cheap endpoint, the reviewer on a frontier model. If
nothing resolves it **fails loudly** rather than running an agent on a surprise model.

This is the seam that makes the roster real. Before it, `models.<role>` was declarative: the
heterogeneity rule was enforced on the config while CI ran everything on one `ASDD_MODEL`.

**It never prints a key.** `--token-var` returns the **name** of the variable holding it and the caller
dereferences it, so a secret cannot reach a log or a command line. Model names and endpoints are not
secrets and are printed directly. Keys never belong in `.asdd.yml`: it is version-controlled.

```bash
bash cli/resolve-model.sh documentation                    # the model
bash cli/resolve-model.sh documentation --url              # the endpoint
bash cli/resolve-model.sh documentation --token-var        # the VARIABLE NAME holding the key
asdd resolve-model documentation                            # via the unified CLI
sh cli/resolve-model.test.sh                                # self-test
```

Exit codes: `0` resolved (value on stdout), `1` nothing resolved for that role, `2` usage / config
error. The operate runners call it (see `cli/templates/operate/docsync.sh`), and `init --goose` ships it
alongside the gates because they depend on it.

> Who holds which key: each contributor's **developer** model is their own Goose session and their own
> key, in their own keyring, **never in the repo**. The **governance agents** run on the admin's key,
> held as repo secrets. Different people, different keys, by construction.

## kit-check

`kit-check.py` keeps [`asdd-kit.yml`](../asdd-kit.yml) - **the kit map** - honest. The map is what an
agent (or a person) reads to orient: the roles, which recipe realises each, which `.asdd.yml` key holds
its model, **where each actually runs**, the invariants and what enforces them, the commands, and the
setup order. It exists so a setup or developer agent does not have to read the whole kit to work it out,
and `recipes/setup.yaml` reads it first.

A map only helps if it is true, so this fails the build when it drifts: a role renamed in the `models:`
block, a recipe that no longer exists, a missing `read_first` file. No model required, zero-dependency.

```bash
python3 cli/kit-check.py                 # check the map against .asdd.example.yml
python3 cli/kit-check.py path/to/.asdd.yml
sh cli/kit-check.test.sh                  # self-test
```

Exit codes: `0` the map matches reality, `1` it drifted. Run it through the unified CLI as
`asdd kit-check`; `validation/run-base.py` runs it.

## check-models

`check-models.sh` enforces the **model-heterogeneity invariant**: the developer and the tester MUST run
different models (a model cannot meaningfully test its own code; different families are preferred), and the
reviewer SHOULD differ from the developer. It reads the `models:` block of `.asdd.yml`.

```bash
bash cli/check-models.sh                 # check .asdd.yml (unset models pass - a template state)
bash cli/check-models.sh --strict        # require developer+tester set and reviewer distinct (for a live fleet's CI)
bash cli/check-models.sh path/to/.asdd.yml
```

It exits non-zero (fails the build) when `models.developer == models.tester`. Run it in CI - `--strict` -
once your fleet's models are configured, so a config that violates the invariant can never merge.

## spec-check

`spec-check.py` is the deterministic **spec-object gate** of the spec-driven profile
([standards/spec-driven.md](../standards/spec-driven.md) §SD). No model required. It does two things:

1. **Definition of ready** - checks the spec object carries every required field, non-empty
   (floor: `outcomes`, `scope.in`, `constraints`, `verification`; override with `--require`).
2. **Independent ready-claim check** - if the object claims `ready: true`, it re-derives readiness from
   the fields and **rejects a claim that does not match**, so a forced `ready=true` (e.g. from an
   injected intake submission) is blocked rather than trusted (see [validation/redteam.md](../validation/redteam.md) A3).

```bash
python3 cli/spec-check.py path/to/spec.json          # a spec object or an asdd/intake/v0.1 object
python3 cli/spec-check.py spec.json --require outcomes,scope,constraints,verification,category
sh cli/spec-check.test.sh                             # self-test against cli/testdata/
```

Exit codes: `0` ready, `1` not ready (park as needs-clarification), `2` ready-claim mismatch (blocked).
A project's intake gate calls this before a contribution is built or claimed; the model-driven half of
intake (drafting the spec by conversing with the contributor) sits on top of this deterministic floor.

## openspec-gate

`openspec-gate.py` is the **OpenSpec readiness gate**, the alternative to `spec-check` for a project that
authors specs with [OpenSpec](https://github.com/Fission-AI/OpenSpec) (`spec_tool: openspec`). It delegates
to the real `openspec validate --strict --json` and reads the verdict out of the JSON, because that command
exits 0 whether the change passes or fails, so its exit code cannot be trusted.

It fails closed rather than guessing. A missing `openspec` binary, a drifted JSON schema, or zero validated
items is reported as a **setup error**, distinct from a spec that is genuinely not ready, so CI can tell
"install the tool" apart from "fix the spec".

```bash
python3 cli/openspec-gate.py <change-id>               # validate one OpenSpec change
python3 cli/openspec-gate.py --from-json result.json   # parse a captured `openspec validate --json`
sh cli/openspec-gate.test.sh
```

Exit codes: `0` ready, `1` not ready, `3` setup error. See
[adopt OpenSpec as your spec tool](../docs/guides/adopt-openspec.md).

## claim-check

`claim-check.py` is the deterministic **claim-protocol enforcer**
([standards/spec-driven.md](../standards/spec-driven.md) §CL). No model required. It serializes work at
the spec, before code exists, so concurrent contributors do not collide. Given a claims ledger and a
request it:

- **CL.3** auto-releases claims older than `--ttl-hours` (default 168), so a stale claim never blocks the
  work (see [validation/redteam.md](../validation/redteam.md) I1),
- **CL.1** refuses a claim on an item with no ready spec (`--ready false`),
- **CL.2** refuses a second active claim on an item held by another identity, and refuses past a
  per-identity cap (`--max-per-identity`),
- grants otherwise (idempotent if the identity already holds the item).

```bash
python3 cli/claim-check.py claims.json --now 2026-07-13T10:00:00 --item 42 --identity alice
python3 cli/claim-check.py claims.json --now <ISO> --sweep      # only auto-release expired claims
sh cli/claim-check.test.sh                                      # self-test
```

`--now` is an explicit ISO 8601 timestamp so runs are reproducible. Exit codes: `0` grant, `1` refuse.
The ledger is the project's claim store (e.g. issue assignees + a timestamp); this tool is the decision
function a claim workflow calls.

## merge-eligibility

`merge-eligibility.py` is the deterministic **"conforming loader" floor** for the merge gate
(STANDARD §2.2 / §5.2, [validation/redteam.md](../validation/redteam.md) D1). No model required. Given a
change's paths and the merge policy it returns the routing the merge-reviewer's verdict must respect:

- any changed path matches a **protected** path -> `human-approve` (always),
- posture is **earned-automerge** AND every path is in the **auto_merge_class** AND none is protected ->
  `autonomous-eligible`,
- otherwise -> `human-approve` (the default).

Protected wins unconditionally: even if `auto_merge_class` is **misconfigured** to include a protected
path, that path can never be autonomously merged. Globs are gitignore-ish (`**` crosses directories,
`*` does not).

```bash
python3 cli/merge-eligibility.py crypto/aes.py --protected '**/crypto/**' \
        --auto-merge-class '**/*.py' --posture earned-automerge      # -> human-approve
sh cli/merge-eligibility.test.sh                                     # self-test
```

Exit codes: `0` human-approve, `3` autonomous-eligible. The model-driven merge-reviewer
([agents/review-merge.md](../agents/review-merge.md)) adjudicates the evidence on top of this floor; it
may never return autonomous on a path this tool routes to a human.

## audit

`audit.py` is the **agent audit ledger** ([STANDARD](../STANDARD.md) 1.3). Every agent action gets one
append-only record: who acted, what they did, to what, under whose authorisation, when, why, and what the
action caused. Records are chained, each carrying the digest of the one before it, so an edited or deleted
record is detectable.

Reviewed content is never stored. A record carries a digest of what the agent saw, not a copy of it.

```bash
python3 cli/audit.py append --ledger .asdd-work/audit.jsonl \
  --role test-runner --action tests.run --verdict fail --action-taken block \
  --reasoning "two tests failed in the payments suite" \
  --payload-json '{"tested":"unit","passed":10,"failed":2}'
python3 cli/audit.py from-review --review review.json --workdir .asdd-work --ledger audit.jsonl
python3 cli/audit.py verify --ledger audit.jsonl        # walk the chain (a file or a synced-sink dir)
python3 cli/audit.py tip    --ledger /path/to/sink/ledger   # the sink's current chain head
python3 cli/audit.py graft  --from batch.jsonl --onto <tip> # re-chain a batch onto the sink tip
python3 cli/dashboard.py --ledger /path/to/synced-sink/ledger   # a file, or a directory of them
bash cli/audit.test.sh
```

Every role records, `developer` included. The developer is a bring-your-own coding agent that runs as a
person's own session rather than a deployment recipe, so it records with one `append` at the end of a
build. That is what makes the ledger cover the whole loop, not only the roles that run in CI.

The ledger is one event stream with two derived **views**:

```bash
python3 cli/audit.py corpus --ledger LEDGER            # the TRAINING view: clean JSONL per record
python3 cli/audit.py corpus --ledger LEDGER --role developer   # one or more roles
python3 cli/audit.py knowledge --ledger LEDGER --out DIR   # the KNOWLEDGE view: real OKGF pages (.md) an OKGF store ingests directly
```

`corpus` keeps the signal (role, reasoning, action, outcome) and drops the chain plumbing, for training or
tuning. It never reproduces reviewed content: the record holds a digest, so a training set references what
was seen without leaking it. `knowledge` is selective, emitting curated entries (an invariant, a rejected
approach, an exemplar) as **real OKGF pages** (OKGF is the knowledge standard ASDD adopts): each is an OKGF
page (`type`, `x-okgf-scope`, `x-okgf-review: draft`, provenance in `x-okgf-sources`) an OKGF store ingests
with no translation, so `--out DIR` writes one page per entry straight into a bundle. A one-off like a test
run produces no entry. Both
read a single `.jsonl` or a synced sink **directory** (`ledger/<year>/<month>.jsonl`).

The review pipeline emits records for its lenses automatically. **Operate agents record through the run
wrapper**, `asdd operate-run` (below), which writes the record deterministically from the agent's result,
so a run interrupted mid-way does not lose the action. Ship a local ledger (an operate or developer run)
to the private sink with `asdd audit-ship LEDGER`, which calls `.github/asdd/audit-export.sh`; the CI
review path ships on its own. The sink is configured by the `audit:` block and refuses a public
destination. See [the audit ledger guide](../docs/guides/audit-ledger.md).

## operate-run

`asdd operate-run --role R --recipe recipes/<r>.yaml [--param k=v ...]` runs a Goose operate agent and
records it in the audit ledger **deterministically**. An operate agent used to record itself by running a
command as its last step, so if a long multi-turn run died (a provider timeout is common), the action
happened but no record was written. The wrapper moves emission off the model: the agent writes its outcome
to `.asdd-work/operate-result.json`, and the wrapper turns that into exactly one record. If the run
produced no result, the wrapper still records the action as incomplete, so it is never silently lost.

```bash
asdd operate-run --role test-runner --recipe recipes/test-runner.yaml --param pr=42 --model <M>
asdd operate-run --role spec        --recipe recipes/interaction.yaml --param platform=web   # interaction records as spec
```

Pass the audit role (the interaction recipe records as `spec`); an unknown role is refused up front,
because a record that cannot be written must not pass silently. The exit code mirrors the underlying run,
so CI still sees a failed agent.

## run-agent

`asdd run-agent <agent> <input-file> [--role R] [--out FILE]` runs one **fixed-prompt** agent on demand
and records it. It is the operator-run counterpart to the CI review runtime, for the agents that are not
part of the automatic PR gate: `triage`, `support`, `review-contributor`, and `review-merge`. Each is an
`agents/<name>.md` doc (a fixed instruction prompt plus a JSON output schema), the same family as the
review lenses.

```bash
asdd run-agent triage new-issue.txt                       # labels + welcome per agents/triage.md
asdd run-agent review-contributor change.diff             # suggestions to the contributor
asdd run-agent review-merge merge-evidence.txt            # the independent final merge check
asdd run-agent support question.txt --out answer.md       # answer from project knowledge
```

It is **safe by construction**, exactly like the review runtime: the agent's fixed instructions are
trusted; the input is assembled into the prompt as a fenced, inert **untrusted** data block (a randomised
fence, so the content cannot break out and inject instructions); output is captured as data, never
executed. It records **one** audit action (STANDARD 1.3) whatever the outcome, so an operator-run agent
leaves the same trail a CI agent does. The model comes from the roster (`models.<role>`) resolved the same
way the gate resolves the reviewer; with no model wired it prints a labelled dry run (the prompt is still
assembled safely). The role defaults per agent (`triage`->triage, `review-contributor`->review,
`review-merge`->merge, `support`->spec); pass `--role` to override.

## doctor

`asdd doctor [CONFIG]` preflights the operate path before you rely on it. It checks Python, Goose, the
selected spec CLI, the roster's heterogeneity rule, the runtime key, the declared conventions and the
recipes, reporting each as OK, a warning, or a blocking issue with the exact next step.

The part worth knowing: it tells **"not installed"** apart from **"installed but not on your PATH"**. A
plain `which` reports the second as the first, which sends people reinstalling a tool they already have.
When a tool is off PATH, doctor prints where it found it and the line to add.

```bash
asdd doctor                      # ./.asdd.yml
asdd doctor path/to/.asdd.yml
```

It changes nothing. It exits non-zero only when a hard requirement of that config is unmet: the selected
spec CLI is genuinely absent, or the roster breaks the developer-differs-from-test rule. Warnings and
information never fail it, so it is safe to run anywhere and usable as a CI step.

## conventions-check

`asdd conventions-check` holds agent output to the conventions the host project declares in `.asdd.yml`.
It exists because adopting into a project that already exists is the normal case: that project already
has a spec layout, a changelog format, an impact log and a house style, and an agent that does not know
them produces work in the wrong place.

```bash
asdd conventions-check --validate                            # the declared block points at real files
asdd conventions-check --print-contract                      # the contract, for an agent prompt
asdd conventions-check --changed a.py docs/specs/a.md --lane feature
asdd conventions-check --diff change.patch --lane feature    # adds added-line style checking
```

Two properties make it usable on a mature repository. It is **diff-scoped**: only the change is judged,
never the existing tree. And it **ratchets**: house style is checked on added lines only, so a repository
inherits its existing violations as a baseline and tightens from there.

It also carries the rule that ships docs with the change. Declare, per path pattern, the documentation a
change to it must also touch:

```yaml
conventions:
  docs:
    "cli/*.py":
      require: ["cli/README.md", "docs/reference/README.md"]
      why: "a command or gate is not shipped until the reference describes it"
    "docs/guides/*.md":
      on: added        # default is `changed` (any touch); `added` fires only for a NEW file
      require: ["docs/README.md"]
```

When a change touches the pattern and none of the required documents, the gate fails and says why. This
repository declares exactly the rule above, because `asdd doctor` shipped and sat undocumented through a
whole merged pull request: nothing checked that the reference had kept up.

Give it **the whole change**, not one commit. The unit ASDD governs is the pull request, so the paths to
pass are the PR's diff against its base. A single commit may legitimately touch code while the matching
documentation arrived in another commit on the same branch:

```bash
asdd conventions-check --changed "$(git diff --name-only origin/main...HEAD)" --lane feature
```

A newline-joined argument like that is split into separate paths. That matters: unsplit it would match
no pattern, every rule would sit silent, and the gate would pass a change it never judged.

Exit codes: `0` conforming, `1` a declared convention is violated, `2` the block itself is unusable. The
last is deliberately distinct, so a misconfiguration is never read as "your change is fine". Every field
is optional and an undeclared field is never checked. See
[adopt an existing project](../docs/guides/adopt-existing-project.md) for the block and the workflow.

**It runs automatically at intake.** The intake gate shells to this same check against the PR's diff, so a
declared convention is enforced on every PR (a violation fails intake, and shows in the intake feedback
comment) without wiring anything. A project that declares no `conventions:` block is a clean no-op. Running
it yourself with the commands above is for local iteration before you push.

## asdd-mcp (Goose / MCP extension)

`asdd-mcp.py` exposes the four deterministic gates above (`spec-check`, `claim-check`,
`merge-eligibility`, `audit-check`) as **MCP tools**, so a [Goose](https://block.github.io/goose/) agent -
or any MCP client - can call them. It is a minimal stdio MCP server, zero-dependency (stdlib), speaking
newline-delimited JSON-RPC 2.0. This is how the Operate layer ("ASDD with Goose") lets an agent consult
the gates.

Wire it into a Goose recipe as a stdio extension:

```yaml
extensions:
  - type: stdio
    name: asdd-gates
    cmd: python3
    args: ["cli/asdd-mcp.py"]
```

Tools: `spec_check` (ready / not-ready / blocked), `openspec_gate` (ready / not-ready / setup error),
`claim_check` (grant / refuse),
`merge_eligibility` (human-approve / autonomous-eligible), `audit_check` (PASS / FAIL),
`conventions_check` (conforming / not-conforming; with `contract: true` it returns the host project's
conventions for the agent to follow instead of checking a change). Each returns the
gate's verdict as text; the server echoes the client's requested `protocolVersion` for compatibility.

```bash
sh cli/asdd-mcp.test.sh    # smoke-tests the handshake + tool calls over stdio
```

It shells out to the sibling gate scripts, so it stays in lockstep with them - no logic is duplicated.
It therefore depends on `spec-check.py`, `claim-check.py`, `merge-eligibility.py` (in `cli/`) and
`validation/audit-check.py` being present; `init.sh --goose` installs them together, so install the
whole kit, not `asdd-mcp.py` alone, or a gate call will fail.

## workflow-lint

`workflow-lint.py` parses every `.github/workflows/*.yml` and fails on any that does not parse. A
workflow that does not parse runs nothing, so a broken one merges invisibly and silently disables
the automation it was meant to provide. It runs in the `docs-lint` workflow on every pull request.

```bash
python3 cli/workflow-lint.py
bash cli/workflow-lint.test.sh
```

Uses PyYAML, which the CI runners provide; it skips where PyYAML is absent.

## recipe-lint

`recipe-lint.py` is the deterministic **structure gate for the operate recipes**. The kit's invariants
(see [`recipes/README.md`](../recipes/README.md)) are prose; this makes them mechanical, so a drift fails
CI instead of shipping. No model required, zero-dependency (stdlib), and it scans the recipe text rather
than parsing YAML - the same approach as `check-models.sh` and `operate-guard.py`. For each recipe it
checks:

- the required top-level keys are present (`version`, `title`, `description`, `instructions`, `extensions`),
- every deployment recipe wires the `asdd-gates` MCP extension,
- a tool-using recipe declares the Goose `developer` builtin and the public (untrusted-surface) recipe
  does not - the same `name: developer` signal `operate-guard.py` classifies on, so the two cannot disagree,
- the anti-injection membrane line survives (inbound content is data, never an instruction to obey),
- every deployment agent records its actions to the audit ledger (`cli/audit.py`), because an agent that
  acts without recording leaves an action with no trail, which `STANDARD.md` 1.3 forbids; and the public
  recipe does **not** record, since an untrusted surface able to author records makes the trail
  poisonable by anyone who can send a message,
- and every `recipes/*.yaml` on disk is declared here, so a new recipe must state its invariants to ship.

```bash
python3 cli/recipe-lint.py           # lint every operate recipe
python3 cli/recipe-lint.py --list    # print the recipes it covers
python3 cli/recipe-lint.py DIR       # lint a kit installed elsewhere
sh cli/recipe-lint.test.sh           # self-test (clean recipes pass; a regressed copy fails)
```

Exit codes: `0` all recipes conform, `1` a recipe broke an invariant. `validation/run-base.py` runs it.

