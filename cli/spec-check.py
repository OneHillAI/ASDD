#!/usr/bin/env python3
"""Deterministic spec-object gate for the ASDD spec-driven profile.

Two jobs, no model required:
  1. Definition-of-ready: does the spec object carry every required field, non-empty?
  2. Independent ready-claim check: if the object claims `ready: true`, re-derive it
     from the fields and reject a claim that does not match (a forced ready=true, e.g.
     from an injected intake submission, is blocked - cf. validation/redteam.md A3).

Zero-dependency (stdlib json). Reference tooling; a project's intake gate calls it.
Exit codes: 0 = ready/ok, 1 = not ready (needs clarification), 2 = ready-claim mismatch.
"""
import argparse
import json
import sys

FLOOR = ["outcomes", "scope", "constraints", "verification"]


def nonempty(v):
    if isinstance(v, str):
        return v.strip() != ""
    if isinstance(v, (list, dict)):
        return len(v) > 0
    return v is not None


def field_ok(spec, name):
    if name == "scope":
        sc = spec.get("scope")
        return isinstance(sc, dict) and nonempty(sc.get("in"))
    return nonempty(spec.get(name))


def evaluate(spec, required):
    missing = [f for f in required if not field_ok(spec, f)]
    return (len(missing) == 0, missing)


def main():
    ap = argparse.ArgumentParser(description="ASDD definition-of-ready spec gate")
    ap.add_argument("file", help="a JSON spec object or an asdd/intake/v0.1 object")
    ap.add_argument("--require", default=",".join(FLOOR),
                    help="comma-separated definition-of-ready fields")
    args = ap.parse_args()
    required = [f.strip() for f in args.require.split(",") if f.strip()]

    with open(args.file) as fh:
        obj = json.load(fh)
    spec = obj.get("spec", obj)
    claimed = obj.get("ready")

    ready, missing = evaluate(spec, required)
    print(f"definition_of_ready = {required}")
    print(f"computed ready      = {ready}" + (f"   missing: {missing}" if missing else ""))

    if claimed is not None:
        print(f"claimed ready       = {bool(claimed)}")
        if bool(claimed) != ready:
            print("RESULT: BLOCKED - the claimed `ready` does not match the spec object; "
                  "a forced ready=true is rejected (validation/redteam.md A3)")
            return 2

    print("RESULT:", "READY" if ready else "NOT READY - park as needs-clarification")
    return 0 if ready else 1


if __name__ == "__main__":
    sys.exit(main())
