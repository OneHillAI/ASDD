# Spec: every agent has a run path, and OKGF is the knowledge standard

Lane: feature. Closes two gaps between what the kit *defines* and what an adopter can actually *run*:
several agents had a doc but no run path, and the knowledge export claimed to be OKGF but was an
approximation. An adopter takes the kit and sets it up; nothing it ships should be a dead reference.

## Outcomes

- **Every agent the kit defines is runnable through the kit.** intake, the review lenses, documentation
  and setup already run. This adds the rest: the tester runs post-merge in CI and in the produce loop;
  triage, support, contributor review and merge review run on demand; interaction runs on demand. None is
  left as a doc with no way to invoke it.
- **The test agent runs only where it is safe.** It runs in the produce loop (the coder's own workspace)
  and post-merge (trusted input). It never runs automatically on an open pull request, because executing
  untrusted contributor code needs an egress-free sandbox the kit does not ship. `operate-guard` enforces
  this mechanically; the boundary is documented, not left to discipline.
- **The operator-run agents are safe by construction.** triage, support, contributor review and merge
  review are fixed-prompt agents run by one runner that assembles the agent's trusted instructions and
  fences the untrusted input as inert data, exactly as the CI review runtime does. Each run records one
  audit action, so an operator-run agent leaves the same trail a CI agent does.
- **OKGF is adopted, not approximated.** The knowledge view emits real OKGF pages (the OKGF frontmatter,
  the review lifecycle state `draft`, provenance as `x-okgf-sources`), so an OKGF store ingests them with
  no translation. There is no adapter.
- **The declared conventions are enforced on every pull request**, not only runnable by hand: a project
  that declares a `conventions:` block has its change held to it at intake.

## Scope

- Non-normative: this is reference-implementation and kit wiring. It does not change `STANDARD.md`,
  `standards/`, `CONFORMANCE.md`, or the required behaviour of a conformant project.

## Acceptance criteria

- `asdd run-agent <agent> <input>` runs each of triage, support, review-contributor, review-merge,
  fences the input as untrusted data, records one audit action, and dry-runs when no model is wired.
- `init --goose` installs the runner and every agent doc it drives, and `init` installs every review lens
  the runtime assembles (impact included). The completeness is asserted by the init self-test.
- `asdd audit knowledge --out DIR` writes OKGF pages that pass OKGF's own conformance validator.
- The conventions gate runs inside intake and fails a pull request that violates a declared convention,
  and is a clean no-op when no `conventions:` block is declared.
- The post-merge test workflow ships, dry-runs until a model is wired, and refuses untrusted input.
