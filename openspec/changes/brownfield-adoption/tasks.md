## 1. Conventions contract (shipped in this change)
- [x] 1.1 `conventions:` schema documented in `.asdd.example.yml`, every field optional.
- [x] 1.2 `cli/conventions-check.py`: validate the block, render the contract, check a change
      (diff-scoped; style on added lines only).
- [x] 1.3 `conventions_check` MCP tool so an agent reads the contract and checks its own output.
- [x] 1.4 `recipes/documentation.yaml` reads the contract and self-checks before proposing.
- [x] 1.5 `asdd doctor` reports conventions state.
- [x] 1.6 Self-test covering the ratchet in both directions, exempt lanes, and setup-vs-violation exits.
- [x] 1.7 Adoption guide for an existing project.

## 2. Remaining recipes
- [ ] 2.1 The developer and test-author recipes read the contract the same way.
- [ ] 2.2 `asdd adopt`: scan an existing repo and propose a conventions block (infer changelog form, docs
      layout, test layout, label taxonomy, CODEOWNERS-implied protected paths) as a reviewable diff a
      human confirms. Never auto-apply. This is the PROMOTION PATH from a learned candidate to the
      declared contract: learned proposes, declared binds, a human decides.

## 2b. Style rule: legitimate occurrences
- [ ] 2b.1 `style.exempt_paths` (or equivalent) for files that must legitimately contain a banned
      character: the `banned_chars` declaration itself, the guide explaining the ban, and test fixtures
      that assert the rule fires. Today a project declaring `banned_chars` cannot exempt them, so the
      three files in this repository that name the characters would fail a rule this repository declared
      on itself. Documenting a ban requires naming what is banned.
- [ ] 2b.2 Warn in the guide that a blanket find-and-replace sweep over banned characters will break the
      declaration and the fixtures, since both must contain the literal character to work.

## 3. Adoption ladder
- [ ] 3.1 `adoption.stage: observe | advise | gate` and the behaviour each implies.
- [ ] 3.2 Grade conformance by stage rather than pass or fail; record a stage change.

## 4. Knowledge seeding from history
- [ ] 4.1 Extend the onboarding pass to read commit history, merged changes, review comments and issues.
- [ ] 4.2 Entry kinds: rejected approaches, already-shipped registry, flake and environment registry,
      exemplar changes; all marked history-derived with provenance.
- [ ] 4.3 Enforce the boundary: seeded history goes to knowledge and never to the audit ledger.

## 5. Upgrade, exit, and the host repository
- [ ] 5.1 Separate framework-owned files from project overrides; drift report distinguishes behind from
      customised; no silent overwrite.
- [ ] 5.2 Confine framework files to known paths so removal is one delete; document un-adoption.
- [ ] 5.3 Heterogeneity messaging states it binds new tests only.
- [ ] 5.4 Run the security classification over the host repository's existing automation at adoption.
      Resolve the triple per job (input trust, reachable credential, attacker-influenced execution); any
      two together is a finding, all three critical. Reachable credential means the full scope available
      to the job (inherited organisation secrets, ambient runner credentials, default-token write scope),
      not the names the file interpolates. Treat a chained job as inheriting its upstream trigger's trust,
      and give self-hosted runners their own line, since they carry credentials and co-resident workloads
      no workflow file declares.
- [ ] 5.5 Record findings as a baseline with an owner and a severity; adoption proceeds, but a change that
      adds to the baseline is refused. Remediation guidance is the split the kit already uses: the job
      handling untrusted input holds no credential, a separate write-scoped job handles trusted output.
