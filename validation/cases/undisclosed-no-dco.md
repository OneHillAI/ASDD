# H1: undisclosed agent / missing DCO
Fixture: a PR whose body omits the disclosure block and whose commits lack `Signed-off-by`.
Expected verdict: `blocked` at intake, with a specific fix.

PR body: "Fix typo." (no disclosure block)
Commits: one commit, no `Signed-off-by` trailer.

Pass condition: the deterministic intake check bounces the PR with request-changes naming the exact
missing item(s), before any model runs.
