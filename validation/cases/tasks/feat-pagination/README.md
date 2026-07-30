# Sandbox task: paginate `/items`

A small, self-contained fake app used by the [effectiveness](../../../effectiveness.md) dimension of the
validation suite. It exists so ASDD can be measured in a controlled way, repeatably, against a
known-correct answer, separate from the real dogfood.

## Files

- [`spec.md`](spec.md), the task spec (the input the ASDD loop builds from).
- `before/items_service.py`, the starting tree: an items service with **no pagination**.
- `solutions/reference/items_service.py`, the known-good target (correct cursor pagination).
- `solutions/seeded-defect/items_service.py`, looks correct but off-by-ones the last page (still returns
  a cursor). Review MUST catch this.
- `acceptance/oracle.py`, the **independent** acceptance oracle. It scores any candidate `items_service`
  and is deliberately not given to the builder.
- `harness.py`, runs the oracle against each variant and checks the oracle is **calibrated**.

## What you can run today (no model runtime needed)

```
python3 validation/cases/tasks/feat-pagination/harness.py
```

This validates the **measuring instrument** before the ASDD loop is wired: the oracle must pass the
reference solution, fail the un-built starting state, and specifically catch the seeded defect. Expected:

```
reference passes the oracle:            True
before-state fails the oracle:          True
seeded-defect caught (last_page only):  True
ORACLE CALIBRATED:                      True
```

## What runs once the loop is live

When the spec-driven profile's reference implementation and a fleet of at least two distinct models are
wired, the loop builds a candidate from `before/` + `spec.md`, and the already-calibrated oracle scores
the merged result, that is the effectiveness measurement. The `seeded-defect` variant is the honesty
check on whether review actually catches bugs (it maps to red-team case E1).
