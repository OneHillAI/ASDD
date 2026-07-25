## 1. Config and boundary
- [ ] 1.1 Add the `capture:` block to `.asdd.yml` (enable, path, roles, redaction, retention), off by
      default, read with the kit's no-YAML-dependency scan.
- [ ] 1.2 Reuse the ledger export's refusals for the capture store: never a public destination, never the
      governed repo. Fail closed on an unverifiable destination.

## 2. Capture
- [ ] 2.1 On each agent call, when capture is enabled, write a full-fidelity record (role, model,
      model_class, input, output, change context, content hash, outcome label) to the capture store,
      distinct from the ledger, which keeps its digest-only record.
- [ ] 2.2 Resolve `model_class` (frontier|open) for the record so an export can separate freely-trainable
      rows from vendor-restricted ones.

## 3. Outcome labelling
- [ ] 3.1 Start each record `pending`; relabel `positive` on a clean merge of its change and `negative`
      when a defect names the change via `Escaped-from: #N`. Never label from an absent signal.

## 4. Derived views
- [ ] 4.1 `asdd audit knowledge` reads the capture store (extending synthesis-to-exemplar,
      rejected-to-rejected) for pages backed by the full record.
- [ ] 4.2 `asdd audit corpus` emits labelled input-output pairs grouped by role and model_class, as
      exportable training records, from the same store.

## 5. Docs and tests
- [ ] 5.1 Document the `capture:` block, the sink separation from the ledger, the outcome-label rules, and
      state plainly that the corpus accrues only from when capture is enabled.
- [ ] 5.2 Tests: disabled is inert; an enabled capture writes the full record with model_class; the label
      transitions pending -> positive -> negative on the real signals and never fabricates; the corpus and
      knowledge views read the same store; the store refuses a public or same-repo destination.
