---
description: Wire a model to each ASDD agent role, guided
---
Set up ASDD's agents for this repo.

Run `asdd setup` and walk the maintainer through it in plain language. It reads the roles from
`.asdd.yml`, writes the chosen model names back, and asks which **spec tool** validates readiness -
`builtin` (ASDD's definition of ready) or `openspec` (delegate to `openspec validate`). If they pick
OpenSpec, remind them to install it where the gate runs (`npm install -g @fission-ai/openspec`).

Hold these rules; do not let a convenient answer break them:
- Model NAMES go in `.asdd.yml`. A key never does: that file is version-controlled. Credentials belong
  in Goose's own config (`goose configure`) or a CI secret (`ASDD_RUNTIME_TOKEN`).
- `developer` is bring-your-own: the contributor's own agent, not something the deployment runs.
- The test models MUST differ from the developer's, or their blind spots line up and the tests
  cheerfully confirm the bug. `asdd check-models --strict` enforces it.

Finish by showing what is set and what is still unset.
