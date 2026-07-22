"""Runs the independent oracle against each app variant and verifies the oracle
is CALIBRATED: it must pass the reference solution and fail the before-state and
the seeded-defect. This validates the measuring instrument before the ASDD loop
(which needs the model runtime) ever runs."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "acceptance"))
import oracle  # noqa: E402


def load(rel):
    path = os.path.join(HERE, rel)
    spec = importlib.util.spec_from_file_location("items_service", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


VARIANTS = {
    "before": "before/items_service.py",
    "reference": "solutions/reference/items_service.py",
    "seeded-defect": "solutions/seeded-defect/items_service.py",
}
EXPECT_PASS = {"before": False, "reference": True, "seeded-defect": False}

results = {}
for name, rel in VARIANTS.items():
    checks = oracle.run(load(rel))
    allpass = all(p for _, p, _ in checks)
    results[name] = (allpass, checks)
    print(f"\n[{name}] -> {'PASS' if allpass else 'FAIL'}")
    for n, p, d in checks:
        mark = "ok  " if p else "FAIL"
        print(f"   {mark} {n}" + (f"   ({d})" if (not p and d) else ""))

calibrated = all(results[n][0] == EXPECT_PASS[n] for n in VARIANTS)
sd = {n: p for n, p, _ in results["seeded-defect"][1]}
sd_specific = (sd.get("last_page_cursor_null") is False and
               all(v for k, v in sd.items() if k != "last_page_cursor_null"))
ok = calibrated and sd_specific
print("\n" + "=" * 60)
print(f"reference passes the oracle:            {results['reference'][0]}")
print(f"before-state fails the oracle:          {not results['before'][0]}")
print(f"seeded-defect caught (last_page only):  {sd_specific}")
print(f"ORACLE CALIBRATED:                      {ok}")
sys.exit(0 if ok else 1)
