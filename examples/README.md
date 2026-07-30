# Examples

A worked example of adopting ASDD, so you can copy rather than start cold.

## A worked adoption

The minimal, copy-ready configuration below is the fastest way to adopt ASDD. The reference
implementation runs this same pipeline on its own pull requests, governing its own development.

## Two ways to adopt

The standard is runtime-neutral, so you adopt it one of two ways:

1. **Run a conforming implementation.** Deploy the reference implementation (this repository) into your repo's root, or run another implementation that
   meets the MUSTs.
2. **Implement the contract yourself.** Build your own pipeline against [the runtime
   contract](../agents/runtime.md) and the agent [lens specs](../agents/). As long as it upholds the
   MUSTs in [../STANDARD.md](../STANDARD.md), it conforms.

Either way, the configuration below is the same.

## Minimal adoption config (copy this)

After choosing an implementation, the smallest conformant setup is:

1. **`.asdd.yml`** (see [../.asdd.example.yml](../.asdd.example.yml)), set your
   protected paths and keep advisory posture:
   ```yaml
   standard_version: "0.1"
   runtime: generic
   merge_posture: advisory
   max_actions_per_run: 5
   protected_paths:
     - ".github/**"
     - "**/auth/**"
     - "**/*requirements*.txt"
   agents: []
   triage_labels: ["bug", "enhancement", "documentation", "security", "needs-triage"]
   ```

2. **`.github/CODEOWNERS`** ([../.github/CODEOWNERS](../.github/CODEOWNERS)), require a human owner on
   your protected paths.

3. **Branch protection** on your default branch: require a PR, require review from Code Owners, **and
   require the `asdd/review` status check**: so a security block or a missing disclosure/DCO
   mechanically blocks merge.

4. **Runtime credential** (optional to start): leave it unset to watch the pipeline dry-run, then add
   the `ASDD_RUNTIME_TOKEN` secret and point `runtime:` at your adapter
   ([../agents/runtime.md](../agents/runtime.md)).

## Verifying you conform

Walk [../CONFORMANCE.md](../CONFORMANCE.md) and confirm each MUST. If you run the reference
implementation, its `conformance-check.sh` asserts the security defaults statically (read-only analysis
token, isolated write scope, no `pull_request_target`, the PDP merge-ban, the intake and status gates,
SHA-pinned actions). A green run plus the human walk-through is your evidence for the
[adopters/](../adopters/) entry and the badge.
