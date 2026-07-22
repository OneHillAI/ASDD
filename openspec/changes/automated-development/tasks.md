## 1. Trigger and claim
- [ ] 1.1 Define approved-to-build (definition of ready met AND an explicit maintainer green-light)
- [ ] 1.2 Read the signal from the base configuration so a fork or spec cannot self-approve
- [ ] 1.3 Take a claim on the work item before building (one active claim per item, a TTL)

## 2. Development-agent contract
- [ ] 2.1 Define the input (approved spec plus permitted repository context) and output (branch plus PR)
- [ ] 2.2 Ensure the opened PR already satisfies intake (disclosure, DCO, exactly one lane, a referenced spec)
- [ ] 2.3 Bring-your-own runtime behind the model seam, reusing `models.developer`

## 3. Guardrails
- [ ] 3.1 Enforce model heterogeneity (`models.developer` differs from tester and reviewer)
- [ ] 3.2 Bound with `max_concurrent_builds` and the open-PR cap; log deferrals
- [ ] 3.3 Restrict to the trusted plane (`spec_context: codebase`); never wire to the public path
- [ ] 3.4 Carry the impact analysis and target version when the approved spec is normative

## 4. Config
- [ ] 4.1 Add the `.asdd.yml` `develop:` block (`posture: off | byo`, trigger, caps, developer runtime)
