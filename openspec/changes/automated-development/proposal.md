## Why

ASDD governs a contribution well once a PR exists, but getting from an approved spec to that PR is still a
human writing the code. An adopter who wants to automate the build step has no defined trigger, no contract
for what a development agent receives and produces, and no guarantee that automating the build does not
weaken the merge gate. Left undefined, "automate development" would drift into an agent that writes and
merges its own code, which is exactly what ASDD exists to prevent.

## What Changes

- An approved-to-build spec (ready AND explicitly green-lit by a maintainer) triggers a bring-your-own
  development agent that implements it and opens a pull request.
- The opened PR enters the same pipeline as any contribution: intake, review, cross-check, and a human
  merge. The development agent never merges and holds no gate authority.
- The developer model must differ from the tester and reviewer models, so the automation cannot review its
  own work.
- The agent's commits are disclosed and DCO-signed, it claims the work item before building, and caps bound
  concurrent builds and open PRs.
- Automated development runs only on the trusted plane; a normative approved spec still carries its impact
  analysis and target version and is gated by the impact lens.

## Impact

- Affected specs: development
- Affected code (reference implementation): the approved-to-build trigger, the claim path, the development
  runtime seam (bring-your-own, reusing `models.developer`), `.asdd.yml` (`develop:` block), the open-PR and
  concurrency caps.
- Mirrors the builtin-format spec `docs/specs/bring-your-own-automated-development.md`. Builds on the
  knowledge loop (`openspec/changes/knowledge-loop`) for grounding.
