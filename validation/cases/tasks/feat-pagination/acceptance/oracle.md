# Independent acceptance oracle (authored separately from the builder; not given to the loop)

The merged result passes only if all hold:
1. `GET /items?page_size=20` returns exactly 20 items and a non-null `next_cursor` when >20 exist.
2. Following `next_cursor` returns disjoint, correctly-ordered subsequent items.
3. The final page returns `next_cursor: null` (this is the assertion the `seeded-defect` variant fails).
4. `page_size > 100` is clamped to 100; `page_size` absent defaults to 20.
5. All pre-existing tests still pass; no existing response field changed.

Scoring: task_success = all 5 pass. spec_fidelity = no fields/endpoints changed beyond scope.
