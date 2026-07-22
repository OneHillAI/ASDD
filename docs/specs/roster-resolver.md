# Spec: the roster resolves to the model that runs

## Problem

`.asdd.yml` declares a model per role (`models.developer`, `models.test_author`, `models.test_runner`,
`models.reviewer`, `models.documentation`, `models.interaction`), and `asdd setup` and the setup
dashboard write it. But nothing read it at runtime. The only consumers were `check-models.sh`, which
validates it, and the setup tools, which write it and print run commands.

So the roster was **declarative**. The CI documentation runner launched Goose with the single
`$ASDD_MODEL`, not `models.documentation`, and a per-role model only took effect if a human typed
`goose run --model <x>` by hand. Two consequences:

- The heterogeneity invariant (`developer != test_author, test_runner`) was enforced on the **config**
  but not on the **execution path**.
- A maintainer configures six models and CI honours one of them. For a newcomer, the setup surface
  writes a file that mostly does not do anything, which is worse than no surface at all.

## Requirements

- One lookup that turns a role into its model, used by every run path, so they cannot disagree:
  `models.<role>` from the config first, then `$ASDD_MODEL` as the fallback.
- The fallback preserves an existing single-model deployment: unset roles keep working as they did.
- An unset role with no fallback fails loudly. Never guess a model, and never silently run an agent on
  a model the maintainer did not choose.
- The CI documentation runner resolves `models.documentation` instead of using `$ASDD_MODEL` directly.
  The endpoint (`ASDD_MODEL_URL`) and the key (`ASDD_RUNTIME_TOKEN`) stay in the environment: only the
  model **name** comes from the roster, because a name is not a secret and the config is public.
- `init --goose` ships the resolver, since the operate runners depend on it.
- The kit map records how the role resolves, so it stays true.

## Acceptance criteria

- Each role resolves to its own `models.<role>`, not a shared model.
- A configured role is not overridden by `$ASDD_MODEL`.
- An unset role falls back to `$ASDD_MODEL`; with no fallback it exits non-zero.
- A missing config with a fallback still resolves (the CI-only deployment case).
- `docsync.sh` launches Goose with the resolved model, and dry-runs when no model resolves.
- Covered by `cli/resolve-model.test.sh` and run by `validation/run-base.py`.

## Out of scope

- The review lenses. They run in CI through the runtime adapter on `$ASDD_MODEL`, and that path lives in
  `.github/asdd/`, which is the govern layer rather than the operate kit. Routing them through
  `models.reviewer` is a change for that layer's owner; flagged, not taken here.
- The test roles have no CI runner yet, so their resolution is exercised by whatever launches them.
  The setup dashboard's executor will use this resolver.
