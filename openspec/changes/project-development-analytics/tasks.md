## 1. Config and conventions
- [ ] 1.1 Add optional `project.goal` (string) and `project.invariants` (list) to `.asdd.yml`, read by the
      dashboard with a no-YAML-dependency scan like the rest of the kit.
- [ ] 1.2 Define the escaped-defect link convention: a `bug`-lane PR body carries `Escaped-from: #<number>`
      naming the merged PR that introduced the defect. Document it in the PR template and the gates docs.
- [ ] 1.3 Define the malicious and core-change markers: a PR is "malicious" when the security lens raises a
      `block` or an `injected-instruction` finding, or carries a `security-reject` label; "core-change" when
      it touches a declared `protected_path` or the impact lens classifies it normative-core.

## 2. Analytics model
- [ ] 2.1 In `cli/dashboard.py`, add an `analytics(snap)` model that partitions PRs into submitted (open =
      to-be) and merged (current-state), reusing `stage_of`, `lane_of`, `parse_impact`, `_normative_paths`.
- [ ] 2.2 Topic extraction: rank leading topics per state from lane + declared scope + changed area; map
      each topic to the declared goal and invariants, with a plain-language support-or-diverge read.
- [ ] 2.3 Score the six balance dimensions (Correctness, Verification, Documentation, Spec conformance,
      Governance integrity, Flow) in `[0, 5]` for the current-state (merged) and the to-be state (merged +
      projected-open) by one rule each; carry a per-dimension "not enough signal" flag.
- [ ] 2.4 Compute the governance KPI ratios and the escaped-defect and throughput numbers, each as
      total + percentage + failing count, with an "unavailable" state when the signal is absent.

## 3. Render
- [ ] 3.1 Render the two-state summary (to-be and current-state) with per-PR digests.
- [ ] 3.2 Render the radar/balance map as inline SVG: six labelled axes, 0 centre to 5 point, two overlaid
      polygons (current-state and to-be), a legend, and a "not enough signal" marker on any 0-by-absence
      axis. No external chart dependency (self-contained, same as the rest of the page).
- [ ] 3.3 Render the KPI ratio block and the escaped-defect headline, each showing total, percentage, and
      the failing/violating count, with trend arrows against the prior window.

## 4. Tests and docs
- [ ] 4.1 Extend `cli/dashboard.test.sh` with a fixture snapshot exercising: both states populated and
      to-be empty; each dimension scored and the missing-signal path; escaped-defect linked and absent;
      KPI ratios with and without signal. Assert the SVG has six axes and two polygons.
- [ ] 4.2 Update the dashboard docs and the setup guide with the new section, the config keys, and the
      escaped-defect trailer convention. Wire the new test into `validation/run-base.py`.
- [ ] 4.3 Confirm `--public` renders only already-public facts and adds no new disclosure.
