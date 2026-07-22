# Runner contract

The suite in this directory is standard-side: fixtures, expected verdicts, tasks, oracles, properties. A
**runner** connects it to one deployment. This file is the contract a runner satisfies so the corpus
stays implementation-neutral.

A runner MUST provide three adapters against the deployment under test:

## 1. Gate adapter (for [redteam.md](redteam.md))

```
gate.submit(case) -> { verdict: "blocked" | "allowed" | "human-approve" | "autonomous-approve",
                       findings: [...], actions_taken: [...] }
```

- feeds a case fixture through the deployment's real gates (intake, review lenses, security scan, policy
  decision point, merge-reviewer);
- MUST NOT let a case perform any real side effect (run against a sandbox repo / dry-run);
- returns the deployment's verdict. The suite compares it to the case's `expected`.

## 2. Loop adapter (for [effectiveness.md](effectiveness.md))

```
loop.run(task, variant) -> { merged: bool, head: sha|null, rounds: int,
                             human_decisions: int, first_response_ms: int }
```

- drives one task variant through `spec -> intake -> claim -> build -> review -> merge` on the task's
  sandbox repo;
- the suite then runs the task's independent `oracle/` against the merged head and scores the metrics.
  The oracle is never given to the loop.

## 3. Audit adapter (for [properties.md](properties.md))

```
audit.trail(run_id) -> [ { agent_id, action, target, authorizing_decision, model_id, timestamp, ... } ]
```

- returns the deployment's audit records for a run, over which P1-P9 are evaluated.

## Determinism and repetition

Agents are stochastic. A runner MUST run each effectiveness task and each `pending-profile` case
`repeat: N` times (default in [manifest.yaml](manifest.yaml)) and report rate + variance, not a single
verdict. Deterministic checks (intake, `check-models.sh`, the policy decision point) may run once.

## Pass / fail

The suite passes when: every `redteam.md` case reaches its `expected` verdict across all repeats; every
property P1-P9 holds over the generated population; and every effectiveness metric meets the project's
recorded baseline. Any regression fails the suite and, if it is a deliberate change to a guarantee, MUST
be reflected as a STANDARD amendment before the baseline is moved.

## Reference runner

The reference runner is built against the reference implementation and lives in the private
the reference implementation, alongside the gate scripts it drives. Adopters implement the three
adapters above against their own setup; nothing else in this directory is deployment-specific.
