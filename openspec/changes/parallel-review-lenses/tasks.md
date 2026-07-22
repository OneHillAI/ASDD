## 1. Configuration
- [ ] 1.1 Read `review.lens_fanout` (bool, default false) in `run-review.sh` via the existing
      `yaml_scalar_in` helper; no new YAML dependency.
- [ ] 1.2 Define the per-lens override convention (`ASDD_MODEL__<LENS>` / `ASDD_MODEL_URL__<LENS>` /
      `ASDD_RUNTIME_TOKEN__<LENS>`, mirroring the per-role resolver) and document it.

## 2. Dispatch
- [ ] 2.1 Add a lens parameter to the runtime adapters (`runtime/openai-compat.sh`, `runtime/generic.sh`)
      so a call can request one lens with a lens-specific prompt instead of all five.
- [ ] 2.2 In `run-review.sh`, factor the single adapter call into a per-lens dispatch function that
      resolves that lens's model (override then `models.reviewer`) and writes its result to a temp path.
- [ ] 2.3 Run the per-lens calls concurrently (background jobs + `wait`, or `xargs -P`), bounded so a
      malformed config cannot fork unboundedly.

## 3. Merge
- [ ] 3.1 Merge the per-lens JSON files into one `asdd/review/v0.1` `review.json` (`lenses[]` union;
      `recommendation` = strongest across lenses; a `block` from any lens blocks).
- [ ] 3.2 Fault isolation: a lens whose call fails or returns non-JSON becomes an error/skipped verdict
      and never aborts the merge.

## 4. Safety
- [ ] 4.1 Apply the diff-size cap per lens call; leave the upstream intake spend gate unchanged.
- [ ] 4.2 Run `security_scan.py` and `impact_scan.py` exactly once over the merged review.

## 5. Tests and docs
- [ ] 5.1 Regression test: fanout off produces behaviour identical to today (existing `run-review` tests
      stay green unchanged).
- [ ] 5.2 Fanout test: concurrent calls, merged schema valid, deterministic layers run once, a per-lens
      override is honoured, and one deliberately failed lens is isolated.
- [ ] 5.3 Docs: `adopt-govern.md` (opt-in, higher spend, per-lens model) and a `troubleshooting.md`
      entry.
