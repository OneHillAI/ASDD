## 1. Intake label-race
- [ ] 1.1 Drop `opened` from the intake workflow's `pull_request` trigger types
- [ ] 1.2 Update the workflow comment to explain the race and why a lane-less PR is pending, not red
- [ ] 1.3 Fix the failure-summary step to read `.asdd-work/intake.json` (not `intake.json`)

## 2. Enforcement step in the adoption guide
- [ ] 2.1 Add a numbered "Enforce it" step to `docs/guides/adopt-govern.md`
- [ ] 2.2 Name the exact required checks (`intake`, `asdd/review`) and the Code Owner review
- [ ] 2.3 State: block direct push to the default branch, and that gates are advisory until this is on
