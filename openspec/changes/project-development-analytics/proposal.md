## Why

The governance dashboard shows the pipeline: pull requests bucketed by stage (awaiting review, in
progress, changes requested, merged), by lane. That answers "what is moving through the gate right now."
It does not answer the questions a project owner actually asks:

- **What is the work about?** Across everything submitted and everything merged, what are the changes
  mostly doing, and does that match the project's stated goal and its invariants?
- **Is the project healthy and balanced, or lopsided?** A project can merge steadily and still drift:
  all features, no tests; all code, no docs; velocity up, correctness down. There is no single view of
  where the project sits today and where it is heading if the open work merges.
- **Are we building bug-free software?** The point of the gate is fewer escaped defects. Nothing today
  counts the failures that matter most: a change that passed review green, passed its tests, and still
  turned out to carry a bug.

GitHub already holds every raw fact (each PR, each check, each merge). The dashboard's job is not to
repeat GitHub; it is to **synthesise** those facts into a small number of quantifiable signals a human
can read at a glance, and to make the trajectory visible: current-state (what has merged) versus the
to-be state (what merges if the open PRs land).

## What Changes

Add a **project-analytics** section to the dashboard, above or beside the existing stage buckets. It is
derived entirely from PR facts the dashboard already fetches, plus a small set of declared link
conventions for the signals GitHub does not carry directly. Nothing here changes the gate; it is a
read-only view.

1. **Two-state summary.** A count and short digest of every **submitted** PR (open = the *to-be* state)
   and every **merged** PR (the *current-state*), so the two are always read side by side.

2. **What the work is about.** The most common topics across submitted PRs and across merged PRs (by
   lane, declared scope, and changed-area), and a plain-language read of what those topics mean against
   the project's **invariants** and its **stated goal** (both declared in config).

3. **A balance map (radar / spider chart).** A star-shaped chart with **6 fixed dimensions**, each scored
   `0` at the centre to `5` at the point, drawn as **two overlaid polygons**: the current-state (from
   merged PRs) and the to-be state (from merged plus open PRs, projecting the open work as if merged). The
   shape shows at a glance whether the project is balanced across the principles of a healthy software
   project or spiking in one direction, the way an attribute chart does for sports equipment or a game
   character. The six dimensions and their scoring are defined in the spec.

4. **Governance KPI ratios.** Totals and percentages that quantify how the process is going: how many
   incoming PRs fit the spec/OpenSpec standard; how many pass review versus not (with the failing count
   called out); tests created and tests passing and doc updates from merged PRs and their trend; which
   review categories findings fall into; how many PRs conform to versus violate a MUST invariant; how many
   attempted to change the core business logic of the code; and how many were flagged malicious.

5. **Bug-free-software KPIs.** The headline performance numbers: submitted versus merged, and the
   **escaped-defect count** - bugs reported against a PR that had passed review green and passed its tests
   yet still shipped a defect. This is the number the whole gate exists to drive down.

## Impact

- Affected specs: new capability `project-analytics`.
- Affected code (at build time, not in this change): `cli/dashboard.py` (a new analytics model + render
  section), its template/HTML, and `cli/dashboard.test.sh`. Reuses the existing `fetch`, `stage_of`,
  `lane_of`, `parse_impact`, and `_normative_paths` helpers.
- New declared conventions (config + PR trailers) for the signals GitHub does not carry: the project goal
  and invariants, the escaped-defect link, and the malicious/core-change markers. All are optional; every
  KPI degrades to "not enough signal" rather than a wrong number when its input is absent.
- Privacy and provenance are unchanged from the dashboard's existing stance: every rendered fact is
  already visible on GitHub, private deployments stay behind auth, and `--public` remains the explicit
  opt-in for publication.
