# Guide: share and run the recipes by name

Once the operate kit is installed, the ASDD recipes are just files. Goose gives three ways to run and
share them, and it resolves a recipe name in a fixed order: the current directory, then each directory in
`GOOSE_RECIPE_PATH`, then the repo in `GOOSE_RECIPE_GITHUB_REPO`
([Goose docs](https://block.github.io/goose/docs/guides/recipes/storing-recipes/)). Two of the three
work from a local checkout; the third fetches from the public GitHub repository.

## Run by name from a checkout (works now)

By default you pass a recipe's full path (`--recipe recipes/test-runner.yaml`), as the
[quickstart](operate-goose.md) does. Point `GOOSE_RECIPE_PATH` at the `recipes/` directory and you can
use the bare name instead:

```bash
export GOOSE_RECIPE_PATH="$(pwd)/recipes"
goose recipe list                    # lists test-author, test-runner, documentation, interaction, developer
goose run --recipe test-runner --model <test-runner-model> --params pr=<PR>
```

This is what an adopter has right after `asdd init --goose`: the recipes are in their repo, so exporting
the path makes every agent runnable by name.

## Share one recipe as a deeplink (works now)

A deeplink packs a whole recipe (instructions, extensions, parameters) into a single link, so it does not
depend on repo access:

```bash
goose recipe deeplink recipes/test-runner.yaml
# -> goose://recipe?config=<base64>
goose recipe deeplink recipes/test-runner.yaml --param pr=123    # bake in a default
```

Anyone opens the link with `goose recipe open '<link>'` or in Goose Desktop. Use it to hand someone a
single agent without asking them to clone anything. The link encodes the recipe as it was at generation
time, so regenerate it when the recipe changes.

## Fetch by name from GitHub

`GOOSE_RECIPE_GITHUB_REPO` lets Goose pull a recipe straight from a GitHub repo:

```bash
GOOSE_RECIPE_GITHUB_REPO=OneHillAI/ASDD goose run --recipe test-runner --model <m> --params pr=<PR>
```

Goose fetches `<name>/recipe.yaml` at the repo root from a **public** repo
([Goose docs](https://block.github.io/goose/docs/guides/recipes/storing-recipes/)). That layout is in
place: the deployment recipes (`test-author`, `test-runner`, `documentation`, `interaction`) are published as root
`<name>/recipe.yaml` copies, generated from the canonical `recipes/<name>.yaml` by
[`cli/gen-recipe-dist.py`](https://github.com/OneHillAI/ASDD/blob/main/cli/gen-recipe-dist.py) and kept in sync by a `run-base` check. The
developer recipe is bring-your-own, so it is not distributed.

It requires the repository to be public, since Goose reads the raw
file over HTTP. Once the repo is public the command above works. Until then, use a checkout (the path
method) or a deeplink, both of which work now and do not need the repo to be public.

If you edit a recipe, regenerate the copies with `python3 cli/gen-recipe-dist.py`; `run-base` fails if
they drift.
