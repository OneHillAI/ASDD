#!/usr/bin/env python3
"""OpenSpec readiness gate for the ASDD spec-driven profile.

ASDD is spec-tool-agnostic: it requires that a spec exists and that the change is checked against it,
not that a particular tool produced it. When a project adopts OpenSpec (Fission-AI/openspec) as its spec
tool, this is the bridge - the OpenSpec analogue of cli/spec-check.py. It delegates "is this change's
spec ready" to OpenSpec's own validator rather than reimplementing OpenSpec's format, so OpenSpec's
notion of a valid spec becomes ASDD's.

  SECURITY-CRITICAL, pinned against openspec 1.6.0 (do not "simplify" to an exit-code check):
  `openspec validate <change> --strict --json` EXITS 0 WHETHER THE SPEC PASSES OR FAILS. A change with a
  hard [ERROR] and "failed": 1 in its JSON summary still returns exit code 0. So readiness is read from
  the JSON summary (summary.totals.failed == 0 AND at least one item passed), NEVER from $?. Keying on
  the exit code would pass every malformed spec straight through the airlock - the exact failure the
  gate exists to prevent. A zero-item result (e.g. a mistyped change id) is treated as NOT ready: the
  gate fails closed.

Zero-dependency (stdlib). Exit codes:
  0 = ready (OpenSpec reports the change valid)
  1 = not ready (OpenSpec reports at least one failure, or a zero-item / unparseable result)
  3 = OpenSpec unusable (binary missing, or an unexpected schema version) - a setup problem, distinct
      from a bad spec so CI can tell "install/inspect the tool" from "fix the spec".

Usage:
  openspec-gate.py <change-id> [--root DIR] [--bin openspec]
  openspec-gate.py --from-json FILE     # parse a recorded `openspec validate --json` result (for tests
                                        # and for a pipeline that already captured the output)
"""
import argparse
import json
import subprocess
import sys

try:
    from _openspec_locate import locate
except ImportError:
    # A stray copy of this gate without its sibling helper must still work: fall back to PATH-only
    # resolution (the pre-existing behaviour). The helper only ADDS off-PATH discovery.
    import shutil

    def locate(binary):
        p = shutil.which(binary)
        return (p, True) if p else (None, False)

# The JSON envelope version this gate was pinned against. OpenSpec is a moving CLI; if the schema
# changes shape, fail loudly (exit 3) rather than silently misread it as a pass.
PINNED_SCHEMA = "1.0"


def read_verdict(doc):
    """Return (ready: bool, reason: str) from a parsed `openspec validate --json` document.

    Fails closed: anything we cannot positively read as a pass is not ready.
    """
    if not isinstance(doc, dict):
        return False, "validator output was not a JSON object"
    summary = doc.get("summary") or {}
    totals = summary.get("totals") or {}
    passed = totals.get("passed")
    failed = totals.get("failed")
    items = totals.get("items")
    if not isinstance(passed, int) or not isinstance(failed, int) or not isinstance(items, int):
        return False, "validator summary missing integer totals (passed/failed/items)"
    if items == 0:
        return False, "validator checked zero items (wrong change id or empty change) - failing closed"
    if failed > 0:
        return False, f"OpenSpec reports {failed} failing item(s) of {items}"
    if passed < 1:
        return False, "no item passed"
    return True, f"OpenSpec reports {passed}/{items} valid"


def schema_ok(doc):
    v = doc.get("version") if isinstance(doc, dict) else None
    return v == PINNED_SCHEMA, v


def run_openspec(change, root, binary):
    """Invoke the real validator and return its parsed JSON, or raise for an unusable tool."""
    # Resolve beyond PATH: `npm install -g` puts openspec in npm's global bin, which is often not on a
    # non-login shell's PATH. Searching those locations too means an installed-but-off-PATH openspec
    # WORKS here instead of failing as if absent (the "install it" message below is then only shown when
    # it is genuinely missing, where it is correct). `asdd doctor` reports the off-PATH case to the user.
    exe, _on_path = locate(binary)
    if exe is None:
        raise FileNotFoundError(
            f"'{binary}' was not found on PATH or in npm's global bin. This project uses OpenSpec as its "
            "spec tool; install it with `npm install -g @fission-ai/openspec` (or set spec_tool back to "
            "builtin in .asdd.yml)."
        )
    argv = [exe, "validate", change, "--type", "change", "--strict", "--json", "--no-interactive"]
    # --root is the project DIRECTORY that holds openspec/. openspec discovers the nearest openspec/ from
    # its working directory, so we run it there. It is NOT openspec's `--store`, which takes a registered
    # store id, not a path: passing a path to --store makes openspec emit no versioned JSON and the gate
    # reads it as a drifted schema. Default (root=None) runs in the caller's cwd.
    # We do NOT check the return code: it is 0 regardless of the verdict (see module docstring). We read
    # stdout as data. The validator only reads markdown; it is not handed any capability to execute PR
    # content, which keeps this callable from the read-only intake job.
    proc = subprocess.run(argv, capture_output=True, text=True, cwd=(root or None))
    out = proc.stdout.strip()
    if not out:
        raise ValueError(
            "openspec validate produced no JSON on stdout"
            + (f"; stderr: {proc.stderr.strip()}" if proc.stderr.strip() else "")
        )
    return json.loads(out)


def main():
    ap = argparse.ArgumentParser(description="ASDD OpenSpec readiness gate")
    ap.add_argument("change", nargs="?", help="the OpenSpec change id to validate")
    ap.add_argument("--root", metavar="DIR",
                    help="the project directory that holds openspec/ (openspec runs there); "
                         "default: the current directory")
    ap.add_argument("--bin", default="openspec", help="the openspec executable (default: openspec)")
    ap.add_argument("--from-json", metavar="FILE",
                    help="parse an already-captured `openspec validate --json` result instead of "
                         "invoking the CLI")
    a = ap.parse_args()

    try:
        if a.from_json:
            with open(a.from_json) as fh:
                doc = json.load(fh)
        else:
            if not a.change:
                ap.error("a change id is required unless --from-json is given")
            doc = run_openspec(a.change, a.root, a.bin)
    except FileNotFoundError as e:
        sys.stderr.write(f"openspec-gate: {e}\n")
        return 3
    except (ValueError, json.JSONDecodeError) as e:
        sys.stderr.write(f"openspec-gate: could not read the validator output: {e}\n")
        return 3

    ok_schema, seen = schema_ok(doc)
    if not ok_schema:
        sys.stderr.write(
            f"openspec-gate: unexpected validator schema version {seen!r} (pinned {PINNED_SCHEMA!r}). "
            "The OpenSpec output format may have changed; re-pin the gate before trusting it.\n")
        return 3

    ready, reason = read_verdict(doc)
    print(f"openspec readiness = {ready}   ({reason})")
    if not ready:
        print("RESULT: NOT READY - fix the change so `openspec validate --strict` reports it valid.")
        return 1
    print("RESULT: READY")
    return 0


if __name__ == "__main__":
    sys.exit(main())
