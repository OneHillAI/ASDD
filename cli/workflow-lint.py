#!/usr/bin/env python3
"""Parse every GitHub Actions workflow YAML, and fail on any that does not parse.

A workflow that does not parse runs nothing, so a broken one merges invisibly and silently disables the
automation it was meant to provide. Intake, review and de-slop validate prose and shell, not workflow
YAML, so this closes that gap. Uses PyYAML (the CI runners provide it); it skips where PyYAML is absent,
since the CI run is the authoritative gate.

    python3 cli/workflow-lint.py [DIR]
"""
import glob
import os
import sys

try:
    import yaml
except ImportError:
    print("workflow-lint: PyYAML not available; skipping (the CI run is the authoritative gate).")
    sys.exit(0)

root = sys.argv[1] if len(sys.argv) > 1 else "."
# Lint the live workflows AND the operate-agent workflow templates the kit ships (cli/templates/**).
# A template with a YAML error would otherwise ship silently and only fail once an adopter runs `init`
# and the workflow refuses to load.
patterns = (".github/workflows/*.yml", ".github/workflows/*.yaml",
            "cli/templates/**/*.yml", "cli/templates/**/*.yaml")
files = sorted({f for p in patterns for f in glob.glob(os.path.join(root, p), recursive=True)})
if not files:
    print("workflow-lint: no workflows found.")
    sys.exit(0)

bad = []
for f in files:
    try:
        with open(f, encoding="utf-8") as fh:
            yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        bad.append((f, (str(exc).splitlines() or [exc.__class__.__name__])[0]))

for f, err in bad:
    print(f"  FAIL {os.path.relpath(f, root)}: {err}")
print(f"workflow-lint: {len(files)} workflow(s) checked; "
      + ("all parse" if not bad else f"{len(bad)} do not parse"))
sys.exit(1 if bad else 0)
