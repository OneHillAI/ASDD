# Spec: the kit map and the setup agent

## Problem

Setting up or adjusting an ASDD-with-Goose installation currently requires working the kit out from its
source. An agent asked to help must read the recipes, the gates, the workflows and the config before it
can say anything useful, and a newcomer has to do the same by hand. Nothing states, in one place, which
agents exist, which recipe realises each, which config key holds its model, or where each actually runs.

That last point is the sharp edge: the roles are not hosted uniformly. The review lenses run in CI
without Goose (an HTTPS call to `ASDD_MODEL_URL`), the recipe agents run through `goose run`, and the
developer is the maintainer's own Goose session. Nobody should have to grep the pipeline to learn that.

The project's target audience is junior developers, product developers and near-non-engineers. A kit
that can only be understood by reading all of it does not serve them.

## Requirements

- Ship a machine-readable map, `asdd-kit.yml`, at the repo root, stating: the roles (what each does,
  its recipe, its `models:` key, where it runs), the invariants and what enforces them, the commands,
  the setup order, and where each kind of steering change is made.
- The map complements `AGENTS.md`, it does not duplicate it: the constitution holds the rules, the map
  holds the layout.
- Ship `recipes/setup.yaml`, a Goose recipe for a maintainer that reads the map first, works out what is
  configured and what is missing, and guides the next step. It makes safe changes through the tools
  (`asdd setup`, `asdd check-models`) and proposes deeper steering changes as a governed PR.
- `init --goose` copies both, so an adopter's repo has them.
- The map must be kept honest mechanically: a check fails the build if the roles drift from the config's
  `models:` block, if a recipe it names is missing, or if a `read_first` file does not exist.

## Acceptance criteria

- `asdd kit-check` passes on the shipped map, and fails when a role is renamed, added or removed in the
  config, naming both the dropped and the new role.
- `asdd init --goose` copies `asdd-kit.yml` and `recipes/setup.yaml` into the target repo.
- `recipes/setup.yaml` satisfies the operate-recipe invariants (`cli/recipe-lint.py`): it wires the
  gates, declares the shell builtin, and keeps the membrane line.
- Covered by `cli/kit-check.test.sh` and run by `validation/run-base.py`.

## Out of scope

- Making the roster actually route at runtime (`models.<role>` is still only read by the setup tools and
  the heterogeneity check). Tracked separately as the roster resolver.
- Launching agents from the dashboard.
