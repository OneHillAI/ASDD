## 1. Provenance variant
- [ ] 1.1 Add the origin discriminator (agent-emitted | history-derived) to the entry contract
- [ ] 1.2 Define the source object (kind, ref, date) and the separate ingested_by / ingested_at fields
- [ ] 1.3 Make agent and lens optional when origin is history-derived

## 2. Entry kinds
- [ ] 2.1 Define the first-class kind vocabulary and make it extensible by adopters
- [ ] 2.2 Document which handling rules each kind drives (retirement horizon, privacy treatment)

## 3. Privacy
- [ ] 3.1 History-derived entries inherit the source repository's sensitivity
- [ ] 3.2 Enforce the spec_context boundary equally for history-derived code facts
- [ ] 3.3 Reference a person's words by source ref rather than reproducing them
- [ ] 3.4 Constrain negative knowledge to the approach, never a characterisation of a person
- [ ] 3.5 Make entries derived from personal content retirable when the source is redacted or removed

## 4. Staleness and retirement
- [ ] 4.1 Record the source date and treat the entry as a claim about the past
- [ ] 4.2 Require verification against current state before a history-derived claim is relied on as fact
- [ ] 4.3 Define supersession and retirement without rewriting the store
