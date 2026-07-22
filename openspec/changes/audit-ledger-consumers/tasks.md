## 1. Record every role
- [x] 1.1 Add `developer` to the recordable roles.
- [x] 1.2 The developer records with one append at the end of a build (documented in the guide).

## 2. Ship every path to one sink
- [x] 2.1 `asdd audit-ship LEDGER` pushes a local ledger to the configured sink via the CI export script.
- [x] 2.2 Flip `.asdd.yml` to the project's private ledger repo.

## 3. The two views
- [x] 3.1 `asdd audit corpus` (training): one example per record, signal kept, chain plumbing and reviewed
      content excluded; `--role` filter; reads a file or a sink directory.
- [x] 3.2 `asdd audit knowledge` (knowledge): OKGF-shaped entries, selective, with provenance.

## 4. Prove and document
- [x] 4.1 `cli/audit.test.sh` covers the developer role and both views, and is registered in the suite.
- [x] 4.2 CLI reference, reference gate list, and the audit ledger guide updated.

## 5. Follow-up (not built here)
- [ ] 5.1 Ingest the knowledge entries into a running store (a deployed OKGF, or the Anthill wiki via its
      scoped MCP access) once one with an ingest path exists.
- [ ] 5.2 Generalise `audit-ship` so it resolves an adopter repo's own `.asdd.yml`, not only the kit
      checkout's, when run from an installed CLI.
