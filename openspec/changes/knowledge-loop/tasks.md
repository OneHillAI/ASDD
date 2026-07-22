## 1. Contract and storage
- [ ] 1.1 Define the knowledge-entry contract (source agent and lens, subject, claim, confidence, lineage)
- [ ] 1.2 Provide the deterministic store read and write path behind the contract
- [ ] 1.3 Bind OKGF as the reference store; keep the store swappable (`knowledge.tool: none | okgf | byo`)

## 2. Onboarding
- [ ] 2.1 Add the bounded, incremental onboarding pass with a token or file budget
- [ ] 2.2 Log what the pass skipped; make a second run incremental, not a full re-sweep

## 3. The loop
- [ ] 3.1 Have the review, documentation, and test agents emit entries with full lineage
- [ ] 3.2 Have review, test-authoring, and spec runs read relevant entries as fenced untrusted grounding

## 4. Config, privacy, training
- [ ] 4.1 Add the `.asdd.yml` `knowledge:` block (`tool`, `onboarding`, `train`, store location)
- [ ] 4.2 Enforce the `spec_context` boundary so a public surface never mines internals via knowledge
- [ ] 4.3 Wire optional bring-your-own training on the corpus; keep it off by default
