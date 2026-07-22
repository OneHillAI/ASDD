# Spec: adopter preflight - `asdd doctor` and reachability that tells the truth

Lane: feature. Closes the gap between "configured" and "actually works" for the Goose operate path,
which is where adopter setup fails silently today.

## Outcomes
- An adopter can run one command, `asdd doctor`, and learn whether the operate path will actually run:
  the tools are reachable, the selected spec CLI is present, the roster obeys the one hard rule, and the
  recipes are in place. It reports each item as OK, a warning, or a blocking issue, with the exact next
  step, and never changes anything.
- The kit stops confusing **"not installed"** with **"installed but not on PATH."** A tool put on disk by
  `npm install -g` (openspec) or by a user-local install (Goose) but absent from a non-login shell's PATH
  is reported as reachable-with-a-fix, not as missing. This removes a whole class of dead-ends where a
  person reinstalls a tool they already have.
- The openspec readiness gate keeps working when openspec is installed off PATH, instead of failing as if
  the tool were absent. The "install it" message is shown only when openspec is genuinely missing.
- A documented **known-good roster** turns provider/model trial-and-error into a copy-paste starting
  point, and the two real provider traps (tool-schema rejection, streaming decode) are discoverable from
  troubleshooting and from `doctor`.

## Scope

In:
- **`asdd doctor` (`cli/doctor.py`).** A read-only preflight over `.asdd.yml` (default `./.asdd.yml`).
  Checks: Python version; Goose reachable (+version); `spec_tool` and, when `openspec`, the openspec CLI
  resolved beyond PATH with its version against the pinned one; roster heterogeneity (delegates to
  `check-models.sh`); runtime-key presence (informational); recipes present. Exit 1 only when a hard
  requirement of THIS config is unmet (a selected spec CLI absent, or a broken roster); warnings and info
  never fail, so it is safe to run anywhere and usable as a CI gate.
- **Reachability beyond PATH (`cli/_openspec_locate.py`).** A shared `locate(binary)` returning
  `(path, on_path)`: PATH first, then npm's reported global bin and the common global-bin locations. Lets
  callers tell reachable / off-PATH / absent apart.
- **Gate uses it (`cli/openspec-gate.py`).** `run_openspec` resolves through `locate`, so an off-PATH
  openspec is used rather than rejected. The import is defensive: a stray copy without the helper falls
  back to the old PATH-only behaviour, so the gate can never break on the helper's absence.
- **Docs.** `operate-goose.md`: a preflight step and the known-good roster with the tool-tolerant-provider
  rule. `troubleshooting.md`: openspec-off-PATH, the backgrounded-run buffering gotcha, and provider
  concurrency.

Out:
- **No live model probe.** `doctor` does not spend a token to confirm a model answers or accepts Goose's
  tools. That is a follow-up (`asdd doctor --probe`), deliberately deferred because it needs a key and
  costs money. `doctor` catches the config-and-reachability class; the runtime-compatibility class stays
  documented (troubleshooting) until the probe lands.
- **No installs, no PATH edits.** `doctor` reports and advises; it never mutates the environment, a shell
  profile, or the repo.
- **No new scaffolding.** `doctor`, `openspec-gate.py`, and the helper run from the ASDD checkout via the
  `asdd` launcher, like `setup`; `init --goose` is unchanged. (Separately flagged to the framework
  session: `openspec-gate.py` is not scaffolded into adopter repos at all, so an openspec adopter's MCP
  `openspec_gate` tool has no file to call - a pre-existing gap, their `init` list to decide.)

## Constraints
- Zero-dependency (stdlib + the existing kit scripts). `doctor` shells out to `check-models.sh` for the
  roster so heterogeneity has one implementation.
- The gate's pinned contract is untouched: `openspec validate` is read from its JSON verdict, never the
  exit code; a genuinely missing binary is still a setup error (exit 3); a drifted schema still fails
  loudly. Only the resolution step (where the binary is found) changed.
- Slop gate clean (no em/en dashes). British spelling in prose.

## Verification
- `cli/doctor.test.sh` (registered in `validation/run-base.py`): a healthy builtin config is READY
  (exit 0); a developer==tester roster fails closed (exit 1); `spec_tool: openspec` with the CLI absent
  fails closed (exit 1); **openspec installed but off PATH is a warning naming the path, not "absent"
  (exit 0)** - the load-bearing case; a missing config fails cleanly. Hermetic via a fake binary and a
  scrubbed env.
- `cli/openspec-gate.test.sh` stays green, including the missing-binary exit-3 case and the live smoke.
- Full deterministic suite stays green.

## Sequencing
- Self-contained. No dependency on the parallel `parallel-review-lenses` change. The `--probe` follow-up
  and the framework-side items (branch-protection guidance, the first-PR label-race) are separate.
