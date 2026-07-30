## Why

`STANDARD.md` §1.3 is a **MUST**: every agent action must be recorded in an audit trail capturing the agent
identity, the action, the target, the authorizing decision, and a timestamp, and that trail "MUST be
retained and reviewable. No action without a corresponding audit record."

ASDD does not implement it. Today an adopter has:

- `insights.activity_log: .asdd-work/activity.jsonl` declared in `.asdd.yml`, but **nothing writes it** and
  **nothing reads it**. `cli/dashboard.py` mentions it in a docstring and renders only whether `insights` is
  enabled; there is no reader and no writer anywhere in the kit.
- `.asdd-work/` is the **ephemeral CI working directory**. Even once written, the file would not survive the
  run, so the configured path cannot satisfy "retained".
- The only durable-ish record is the `asdd-intake` CI artifact at **retention-days: 7**, holding the PR data
  and `intake.json`; `review.json` flows through it to the publish job. After seven days it is gone.
- What actually persists is the advisory PR comment (human prose) and the `asdd/review` commit status
  (pass or fail). Nothing structured, nothing queryable, nothing accumulating.
- Nothing at all is recorded for the test-author, test-runner, documentation, triage, spec, or
  merge-review roles.

So the normative audit requirement rests on a prose comment trail, and an adopter has no database. That
also means there is no substrate for the two things the record is worth keeping for: **model training and
tuning**, and the **knowledge base**.

## What Changes

- A defined **audit record contract**: one append-only record per agent action, with a common envelope that
  satisfies §1.3 (identity, action, target, authorizing decision, timestamp, accountable human) plus a
  role-specific payload and the agent's stated reasoning.
- **Every agent role emits**: the review lenses (code, security, spec, quality, impact), the test author,
  the test runner, the documentation agent, the triage/listener agent, the spec/interaction agent, and the
  merge reviewer, each recording its decision, why, and the action that followed.
- A **durable, private sink**. The ledger is exported out of the ephemeral CI directory to a private store
  the adopter configures. ASDD defines the sink contract, not the database (bring your own), and **never
  writes the ledger into the repository it governs**.
- **Security and integrity**: the ledger is as sensitive as the code it describes, is access-controlled,
  append-only, and tamper-evident, with an adopter-set retention policy.
- **Consumers**: the dashboard renders it (today it only claims to), the knowledge loop derives curated
  entries from it, and it is the corpus for optional model training.

## Where it is hosted

ASDD hosts nothing. It is a standard and a set of CI gates that run in the adopter's own pipeline, so there
is no ASDD server, no central store, and no data leaving the adopter's control by default. Records are
produced inside the adopter's run and exported to a sink the adopter owns:

- **Reference binding: a private sibling repository** (for example `<project>-ledger`, private). Zero extra
  infrastructure for a project already on a Git host, and Git supplies exactly what the trail needs:
  append-only history, access control, and retention. Suitable for pull-request-rate volumes.
- **A private object store** (S3, R2, GCS) when volume outgrows a repository.
- **A database or service endpoint** the adopter runs.
- **The adopter's own knowledge platform**, where the ledger becomes the wiki and knowledge base and the
  corpus for training on their own compute. This is the path that closes the loop with the knowledge layer.

The governance dashboard is then generated from that sink and hosted privately, which is already the
dashboard's posture (internal by default; it refuses `--public` unless the repository is verifiably public).

For OneHill itself: the public `OneHillAI/ASDD` repository stays the standard and the reference
implementation, while the ledger, the derived knowledge, and the training corpus live in OneHill's own
private environment. The framework carries the method; the data stays the Foundation's.

## Impact

- Affected specs: audit-ledger
- Affected code (reference implementation): an emit helper the agents and gates call; export from the
  intake/review workflows to the configured sink; `.asdd.yml` (an `audit:` block, and correcting the
  ephemeral `insights.activity_log` default); `cli/dashboard.py` (a real reader).
- Relationship to the knowledge loop (`openspec/changes/knowledge-loop`): the ledger is the **raw record of
  what happened**; the knowledge base is the **curated derived understanding**. The ledger feeds it; the two
  are not duplicates and neither replaces the other.
- The build will be **normative** (it makes §1.3 mechanically real and adds sink and retention
  requirements), so it will carry its own impact analysis and target version.
