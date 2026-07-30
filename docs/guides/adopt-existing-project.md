# Adopting ASDD into an existing project

Most projects that could adopt ASDD already exist. They have a spec layout, a changelog format, an impact
log, a house style and a review culture, plus thousands of commits that predate every rule. This guide is
the brownfield path. For a project starting from zero, see [operate-goose](operate-goose.md).

Two ideas make adoption work on a mature repository.

**ASDD maps to your project, not the other way round.** Where you already keep an artefact, ASDD points at
it. Adoption never creates a second changelog or a second impact log beside the one you maintain.

**Gates judge the change, not the tree.** Your existing violations are inherited as a baseline. House
style is checked on added lines only, so a repository with thousands of pre-existing issues can adopt
today and tighten from there.

## The problem this solves

Run a stock documentation agent against a mature repository and it writes plausible prose in the wrong
place. It does not know you keep `docs/SYSTEM_IMPACT_LOG.md`, that a change adds a fragment under
`changelog.d/` rather than editing `CHANGELOG.md`, or that your CI rejects certain characters. A human
then redoes the work, which costs more than not running the agent.

The fix is to declare how you ship, once, in version control.

## 1. Declare your conventions

Add a `conventions:` block to `.asdd.yml`. Every field is optional, and an undeclared field is never
checked, so declare only what you actually have:

```yaml
conventions:
  spec_dir: "docs/specs"              # a change is specified here before it is implemented
  exempt_lanes: [chore]               # lanes exempt from the spec and changelog requirements
  changelog:
    mode: fragment                    # fragment | direct | none
    fragment_glob: "changelog.d/*.md"
    fragment_pattern: "changelog.d/<id>.<category>.md"
    categories: [added, changed, fixed, removed, security, docs]
    assembled_file: "CHANGELOG.md"    # with mode: fragment, agents must not edit this directly
  impact_log: "docs/SYSTEM_IMPACT_LOG.md"
  docs:                               # ship the docs with the change
    "cli/*.py":
      require: ["cli/README.md"]
      why: "a command is not shipped until the reference describes it"
    "docs/guides/*.md":
      on: added                     # only a NEW guide needs an index entry
      require: ["docs/README.md"]
      why: "a guide the index does not list cannot be found"
  style:
    spelling: british
    banned_chars: ["–", "—"]
  preflight: "ruff check . && ruff format --check . && mypy pkg && pytest -n 4"
  exemplars:
    - "https://github.com/OWNER/REPO/pull/641"
```

`exemplars` earns its place: pointing an agent at two or three merged changes that show your house style
is cheaper and more accurate than prose describing it.

`docs` takes `on: changed` (the default, firing on any touch) or `on: added`, which fires only when the
change creates a matching file. Use `added` where only new files need the update: a new guide needs an
index entry, editing an existing one does not. Detecting an addition needs the change as a diff, so an
`on: added` rule checked with `--changed` alone reports itself as unevaluated rather than passing quietly.

`docs` is the rule that keeps documentation from drifting behind the code. Declare, per path pattern,
which documents a change to it must also touch. A change that adds a command but leaves the reference
alone then fails, instead of merging and going unnoticed until someone looks the command up and finds
nothing. ASDD declares this rule on itself for exactly that reason.

Check the block points at real files:

```bash
asdd conventions-check --validate
```

`asdd doctor` reports the same thing as part of the operate-path preflight.

## 2. The agents now conform instead of guessing

The declared block is a binding output contract, not advice. An agent reads it before it starts:

```bash
asdd conventions-check --print-contract
```

The operate recipes call the `conventions_check` gate for exactly this, and call it again on the paths
they changed before proposing anything. An agent that drifts fails its own check and corrects itself
rather than opening a change you have to redo.

## 3. Hold changes to it

The same gate runs over a change:

```bash
asdd conventions-check --changed src/a.py docs/specs/a.md changelog.d/7.fixed.md --lane feature
asdd conventions-check --diff change.patch --lane feature      # adds added-line style checking

# the usual form: judge the whole pull request, not a single commit
asdd conventions-check --changed "$(git diff --name-only origin/main...HEAD)" --lane feature
```

Pass the pull request's full diff. The unit ASDD governs is the PR, and one commit may legitimately
change code while the matching documentation lands in another commit on the same branch.

It reports each declared convention as ok or a failure, and exits non-zero when a change violates one.
A malformed block exits `2` instead, so a misconfiguration is never read as "your change is fine".

Wire it wherever you gate changes. Because it only ever judges the change, adding it to a mature
repository is safe on the first day.

## 4. Climb the ladder

Adoption is staged rather than all-or-nothing:

| Stage | What runs | What blocks |
| --- | --- | --- |
| observe | agents run, output recorded | nothing |
| advise | agents post their findings | nothing |
| gate | checks are required | violations block the merge |

The kit already behaves this way: the review dry-runs until you wire a model, stays advisory after that,
and only binds once branch protection requires the checks. See
[adopt-govern](adopt-govern.md) for the step that turns advisory into enforced.

Start at observe, watch what the agents produce against your real changes, and advance when the output is
worth blocking on.

## What your history is worth

An existing project arrives with something a new one does not have: years of commits, merged changes,
review comments and closed issues. That is a richer source than a file tree, and it is where the knowledge
layer pays off most. It is also the natural cold start for the audit ledger, which otherwise begins empty
on your first day.

One boundary matters. Knowledge seeded from history is recorded as history-derived, and it is never
written into the audit ledger. An audit record asserts that an agent took an action; reconstructing one
from history would assert an action that never happened.

## Un-adopting

Framework files stay in known paths, so removing ASDD is a deletion rather than an excavation, and your
own spec, changelog and impact-log artefacts are untouched by it.
