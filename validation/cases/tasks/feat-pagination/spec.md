# Task spec: paginate the /items listing (ready-spec variant)

- **Outcomes:** `GET /items` returns at most `page_size` items and a `next_cursor`; passing
  `?cursor=<next_cursor>` returns the following page; the last page returns `next_cursor: null`.
- **Scope (in):** the `/items` read endpoint and its handler. **(out):** write endpoints, the data model.
- **Constraints:** default `page_size=20`, max `100`; cursor is opaque and stable across inserts;
  no change to existing response fields.
- **Verification:** the acceptance tests in `acceptance/` pass; existing tests still pass.

Variants (see manifest.yaml):
- `ready-spec`, this spec, unchanged.
- `vague-spec`, replace this file with "add pagination to items" and nothing else (tests the
  definition-of-ready gate: it should be parked as needs-clarification, or produce a measurably worse
  result).
- `seeded-defect`, same spec, but the obvious implementation off-by-ones the last page (returns a
  non-null cursor at the end); review MUST catch it before merge.
