# Spec: a role can run on its own provider and key

## Problem

The roster resolver gave each role its own model **name**, but every governance agent still shared one
endpoint (`ASDD_MODEL_URL`) and one credential (`ASDD_RUNTIME_TOKEN`). So a deployment could vary the
model per role only within a single provider.

Real deployments do not look like that. A team embedding ASDD wants the cheap, high-volume roles (the
test agents) on one endpoint and the judgement-heavy ones (the reviewer) on a frontier model, which is
often a different provider entirely, with a different key and a different bill. Today that is
impossible without editing the runner.

The heterogeneity invariant already pushes roles onto different models; providers are the natural next
axis, because "a different model family" and "a different provider" are usually the same decision.

## Requirements

- Per role, resolve the endpoint and the key as well as the model, in the same single lookup, so no run
  path can disagree:
  - endpoint: `$ASDD_MODEL_URL__<ROLE>`, else `$ASDD_MODEL_URL`
  - key: `$ASDD_RUNTIME_TOKEN__<ROLE>`, else `$ASDD_RUNTIME_TOKEN`
- One provider stays the default: setting only the shared variables must behave exactly as before, so an
  existing deployment is unaffected.
- Credentials stay in the environment as secrets. They are never written to `.asdd.yml`, which is
  version-controlled, and never printed: the resolver returns the **name** of the variable holding the
  key and the caller dereferences it, so a secret cannot reach stdout, a log or a command line.
- Nothing resolves, nothing runs: a missing endpoint or model fails rather than guessing.
- The CI documentation runner uses the resolved endpoint and key, so a per-role provider works end to
  end. Each `goose run` is its own process, so a per-role key stays scoped to that run.

## Acceptance criteria

- A per-role endpoint overrides the shared one; a role without an override keeps the shared one.
- `--token-var` names the per-role variable when set, and the shared variable otherwise.
- The resolver never emits a key value, even when both key variables are set.
- No endpoint at all exits non-zero.
- `docsync.sh` launches Goose with the role's resolved model, endpoint and key, and dry-runs when any
  of the three is missing.
- Covered by `cli/resolve-model.test.sh` and run by `validation/run-base.py`.

## Out of scope

- The review lenses, which reach their model through the runtime adapter in `.github/asdd/`. That is the
  govern layer; per-role providers there are a change for its owner.
- Declaring providers in `.asdd.yml`. An endpoint is not a secret, but keeping the config to model names
  alone preserves one simple rule ("the config holds names, the environment holds credentials") and the
  guard that enforces it.
