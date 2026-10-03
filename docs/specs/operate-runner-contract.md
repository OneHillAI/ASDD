# Spec: the operate runners and their recipes agree, and a failed run says so

Lane: fix. The post-merge runners (`test.sh`, `docsync.sh`) and the recipes they run drifted apart, so a
deployment could be fully wired and still get a test or documentation run that never started, with a
report telling it to wire a model it had already wired.

## Outcomes
- The test agent receives the change it is meant to test. `test.sh` passes the parameter the test-runner
  recipe declares (`pr`), so the run starts instead of dying on a missing parameter that `|| true` hid.
- A test run that works is recognised. The test-runner recipe tells the agent to end its reply with a
  `## Test result` section, the same heading `test.sh` extracts and posts, so a real PASS or FAIL reaches
  the merged PR instead of every run falling through to the failure path.
- An endpoint written as a bare `https://host/v1` works. Goose's openai provider takes the full request
  path, so the runners and the setup dashboard now derive `v1/chat/completions` from any accepted form
  (bare, trailing slash, host only, full path, a query string), as `connect-check` already did. Before, a
  bare endpoint was requested as `POST /v1` and returned 404.
- A wired run that returns nothing is reported as that. It no longer reads "dry run" and no longer tells a
  connected deployment to "wire the model"; it says the run did not complete and points at the job log, and
  the ledger records the verdict `error` instead of `dry-run`. An unwired run is unchanged.

## Scope

In:
- **`cli/templates/operate/test.sh`**: pass `--params pr=<ref>` (drop the undeclared `change_ref` and
  `instructed_by`); normalise the endpoint path; split the failure report from the dry run.
- **`cli/templates/operate/docsync.sh`**: normalise the endpoint path; split the failure report from the
  dry run. Its parameters (`change_ref`, `instructed_by`) already match `recipes/documentation.yaml`.
- **`recipes/test-runner.yaml`**: instruct the agent to end with the `## Test result` section.
- **`cli/setup-dashboard.py`**: the same endpoint-path normalisation in `run_env`.
- **Verification**: a contract test between the runners and their recipes, registered in the suite.

Out:
- The documentation recipe opens its own pull request, while `docsync.sh` expects it to print a
  `## Proposed doc updates` section for the workflow to post. That is a design mismatch, not a typo, and
  belongs to a separate change that decides which behaviour the kit wants.
- Any change to what `connect-check` considers connected, to model resolution, or to the audit record
  format beyond the new `error` verdict value on a failed run.

## Constraints
- Zero-dependency: bash and the stdlib only, as the templates already are. The runners are installed
  standalone into an adopter's repo, so the path logic is repeated in each rather than shared.
- A change to a runner's contract with its recipe must fail the suite, not surface in production: the
  contract test reads the recipe's declared parameters rather than hard-coding them.
- Slop gate clean (no em/en dashes). British spelling in prose.

## Verification
- `.github/asdd/operate/runner-contract.test.sh` (registered in `validation/run-base.py`), driven by a
  stub `goose` that records what a runner hands it: each runner passes exactly the parameters its recipe
  declares; the heading `test.sh` extracts is printed by its recipe and a reply carrying it is posted from
  that heading on; every endpoint form yields `OPENAI_HOST=https://host` and the full chat-completions path;
  a wired run with an empty reply reports "did not complete", records `error` and gives no wiring advice,
  while an unwired run still reports a dry run with it. Run against the unfixed templates it fails on each
  of these; against the fixed ones it passes.
- `cli/setup-dashboard.test.sh` covers bare, trailing-slash, host-only and path endpoints.
- Checked against a real Goose (1.41.0) with a local server logging the request: `OPENAI_BASE_PATH=v1`
  requested `POST /v1`, and `v1/chat/completions` requested `POST /v1/chat/completions`; and
  `goose run --explain` reported `pr` as a missing parameter for the old `change_ref` call.
- Full deterministic suite stays green.
