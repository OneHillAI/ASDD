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
   **escaped-defect count** framed as the **review agent's false-negative rate** - a defect reported
   against a PR that had passed review green and passed its tests yet still shipped. Green-then-buggy means
   the review missed it, so for a project that runs the agent review this is the sharpest read of whether
   the agent fleet is actually catching bugs. It is the number the whole gate exists to drive down.

6. **A temporal trend.** The radar answers current-vs-to-be; alongside it, a per-window series (a small
   trend line) for the headline signals, so an owner sees whether escaped defects, throughput, and spec-fit
   are rising or falling, not only their latest value.

A worked HTML example of the whole view (radar, KPIs, escaped-defect hero, sparklines, and the
still-filling-in note) ships with this change under `design/analytics-example.html` as a design reference.

## What this depends on

Two of the KPIs cannot come from what the pipeline emits today, so this change carries the small producer
changes they need:

- **Spec conformance is its own signal.** Intake rolls the spec check together with disclosure, DCO, and
  lane, and a chore lane is spec-exempt, so "passed intake" is not "spec-conformant." Intake must expose
  the spec result separately.
- **The review emits a machine-readable per-lens result.** Review categories, malicious flags, and
  impact-core findings already exist inside the review, but only the rendered comment is queryable. A
  structured per-lens emission (a status per lens, or a parseable block) unlocks all three at once, instead
  of the dashboard scraping a comment. The MUST-invariant KPI stays "not enough signal" until a review
  emits an explicit invariant check; the spec marks it blocked on that producer rather than implying it is
  derivable.

## Impact

- Affected specs: new capability `project-analytics`.
- Affected code (at build time, not in this change): `cli/dashboard.py` (a new analytics model + render
  section, plus extending `fetch` to read merged-PR statuses and files and to paginate the declared
  window), its HTML, and `cli/dashboard.test.sh`; `.github/asdd/intake-check.sh` (expose `spec_ok`
  separately); the review path (`post-review.sh` or a per-lens status) for the machine-readable emission.
- New declared conventions (config + trailers) for the signals GitHub does not carry: the project goal and
  invariants, and the escaped-defect link (`Escaped-from: #N` on a bug-lane PR or a bug-labelled issue).
  Every KPI degrades to "not enough signal" rather than a wrong number when its input is absent, and each
  metric declares a minimum signal so a new project shows a note while an existing repo scores from history.
- Privacy and provenance are unchanged from the dashboard's existing stance: every rendered fact is already
  visible on GitHub, private deployments stay behind auth, and `--public` remains the explicit opt-in for
  publication.
