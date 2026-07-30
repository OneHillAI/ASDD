## 1. The record contract
- [ ] 1.1 Define the common envelope (identity, role, model, action, target, authorizing decision, accountable human, timestamp, run/PR/commit lineage, duration, outcome)
- [ ] 1.2 Define the reasoning field and an inputs digest (hash of what the agent saw, not the raw content)
- [ ] 1.3 Define the role-specific payloads for each emitting role

## 2. Emission
- [ ] 2.1 Provide an append helper the gates and agents call, safe to call from a read-only job
- [ ] 2.2 Emit from the review lenses (code, security, spec, quality, impact) with verdict, findings, reasoning, and the action taken
- [ ] 2.3 Emit from the test author (tests written, the requirement each covers, reasoning)
- [ ] 2.4 Emit from the test runner (what was tested, results, coverage, action thereof)
- [ ] 2.5 Emit from the documentation agent (docs created or updated, and why)
- [ ] 2.6 Emit from the triage/listener agent (item, labels applied from the allow-list, why)
- [ ] 2.7 Emit from the spec/interaction agent (spec drafted or validated, readiness verdict, why)
- [ ] 2.8 Emit from the merge reviewer (verdict, the deciding rule, protected paths touched, resulting action)

## 3. The sink
- [ ] 3.1 Define the sink contract (append a batch of records; idempotent by event id)
- [ ] 3.2 Reference binding: export the run's records to the configured private sink
- [ ] 3.3 Refuse to write the ledger into the governed repository; fail loudly on a public target
- [ ] 3.4 Add the `.asdd.yml` `audit:` block (sink, credentials reference, retention); correct the ephemeral `insights.activity_log` default
- [ ] 3.5 Ship the reference sink binding: a private sibling repository (no extra infrastructure)
- [ ] 3.6 Keep emission in the read-only job and export in a separate write-scoped step; never expose the sink credential to a job handling untrusted content

## 4. Integrity, security, retention
- [ ] 4.1 Append-only with a tamper-evident chain (each record carries the previous record's hash)
- [ ] 4.2 Access-controlled and private by default; document the sensitivity posture
- [ ] 4.3 Adopter-set retention that satisfies "retained and reviewable"

## 5. Consumers
- [ ] 5.1 Dashboard reads the ledger and renders per-role agent activity
- [ ] 5.2 Document how the knowledge loop derives curated entries from the ledger
- [ ] 5.3 Document the export shape for model training and tuning
