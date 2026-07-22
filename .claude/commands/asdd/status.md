---
description: What are the agents doing, and under what steering
---
Show this project's governance state.

Run `GITHUB_TOKEN=$GITHUB_TOKEN asdd dashboard --repo <owner/repo> --out dashboard.html` if a token is
available, otherwise `--json` and summarise.

Report: pull requests by governance stage, the intake and review verdicts, and the active configuration
(model per role, merge posture, spec context, lanes). Say plainly which agents are actually wired to a
model and which are dry-running, because a pipeline that reviews nothing looks identical to one that
passes everything.

The page is internal unless the repo is public. Do not publish it.
