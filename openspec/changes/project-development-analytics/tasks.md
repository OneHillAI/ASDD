## 1. Producer changes (the two signals the pipeline does not emit today)
- [ ] 1.1 `.github/asdd/intake-check.sh`: expose the spec result (`spec_ok`) as its own field, distinct from
      the rolled-up intake pass/fail, so the spec-conformance metric reads the spec signal alone and can
      exclude spec-exempt (chore) lanes.
- [ ] 1.2 The review path: emit a machine-readable per-lens result (a per-lens status context, or a parseable
      block carrying lens name + verdict + findings) in addition to the human comment, so categories,
      malicious, and impact-core are queryable without scraping the comment. Malicious derives from the
      security lens verdict (blocking or injected-instruction), not from a label the pipeline never applies.

## 2. Config and conventions
- [ ] 2.1 Add optional `project.goal` (string) and `project.invariants` (list) to `.asdd.yml`, read by the
      dashboard with a no-YAML-dependency scan like the rest of the kit.
- [ ] 2.2 Escaped-defect link convention: `Escaped-from: #<number>` on a `bug`-lane PR OR a bug-labelled
      issue, naming the merged PR that introduced the defect. The issue form counts an unfixed escape.
      Document it in the PR template and the gates docs.
- [ ] 2.3 Define the core-change marker: a PR touches a declared `protected_path` or the impact lens marks it
      normative-core. Note that the MUST-invariant conform/violate metric stays "not enough signal" until a
      review emits an explicit invariant check (blocked on a producer, not implied as derivable).

## 3. Fetch and window
- [ ] 3.1 Extend `fetch()` to read check statuses and changed files for MERGED PRs, not only open ones
      (verify merged head-SHA statuses persist after branch delete).
- [ ] 3.2 Compute every metric over an explicit declared window and paginate to cover it, so a repo larger
      than one page is never scored over an unstated recent slice. State the window on the page.

## 4. Analytics model
- [ ] 4.1 `analytics(snap)` in `cli/dashboard.py`: partition PRs into submitted (open = to-be) and merged
      (current-state), reusing `stage_of`, `lane_of`, `parse_impact`, `_normative_paths`.
- [ ] 4.2 Topic extraction: rank leading topics per state; map each to the declared goal and invariants with
      a plain-language support-or-diverge read.
- [ ] 4.3 Score the six dimensions in `[0, 5]` for current-state and to-be by one rule each. To-be excludes
      or down-weights changes-requested PRs. Verification counts only code-changing PRs, Documentation only
      user-facing PRs (non-applicable PRs leave the denominator, not scored zero).
- [ ] 4.4 Minimum-signal gate per metric: below its threshold a metric returns "not enough signal", and that
      state WINS over a max score (Correctness must not read 5 on an unproven project).
- [ ] 4.5 KPI ratios, escaped-defect rate (as the review false-negative rate), and throughput, each as
      total + percentage + failing count, plus a per-window series for the temporal trend.

## 5. Render
- [ ] 5.1 Two-state summary with per-PR digests.
- [ ] 5.2 Radar/balance map as inline SVG: six labelled axes, 0 centre to 5 point, two overlaid polygons,
      a legend, and a "not enough signal" marker on any low-signal axis. No external chart dependency.
- [ ] 5.3 KPI block + the escaped-defect hero (framed as the agent false-negative rate), each with total,
      percentage, failing count, and a trend indicator backed by the per-window series.
- [ ] 5.4 Sparklines for the headline signals (escaped-defect rate, throughput, spec-fit); the "still filling
      in" note for below-threshold metrics, following the worked HTML design example.

## 6. Tests and docs
- [ ] 6.1 Extend `cli/dashboard.test.sh`: both states populated and to-be empty; each dimension scored and
      the below-threshold path (Correctness not defaulting to 5); escaped-defect linked (PR and issue) and
      absent; KPI ratios with and without signal; the window/pagination denominator. Assert the SVG has six
      axes and two polygons.
- [ ] 6.2 Update the dashboard docs and setup guide with the new section, the config keys, and the
      escaped-defect trailer. Wire the new test into `validation/run-base.py`.
- [ ] 6.3 Confirm `--public` renders only already-public facts and adds no new disclosure.
