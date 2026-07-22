#!/usr/bin/env python3
"""asdd - one CLI for ASDD (v0.1).

Puts the operate-kit tools under a single command: the installer, the four
deterministic gates, the gates-as-an-MCP-server, and the validation runner.
Dispatches to the scripts that live alongside it, so run it from a checkout of
ASDD (or `pip install -e .`, which links to the checkout). Zero-dependency (stdlib).

    asdd init --goose /path/to/repo
    asdd merge-eligibility crypto/aes.py --protected '**/crypto/**' --posture earned-automerge
    asdd mcp            # the Goose stdio extension: cmd=asdd, args=[mcp]
    asdd validate
"""
import os
import subprocess
import sys

__version__ = "0.1.0"  # keep in sync with pyproject.toml

HERE = os.path.dirname(os.path.realpath(__file__))  # realpath: a symlink resolves to the checkout


def _kit_root():
    """Where the kit's scripts and templates actually live.

    A checkout (or an editable install) has them right next to this file, and those stay the
    single source of truth. An installed wheel has no checkout to point at, so setup.py stages
    the same trees into the asdd_kit package at build time and we fall back to that. Checking
    for cli/ rather than guessing means a checkout always wins, even if a stale wheel is also
    importable.
    """
    if os.path.isdir(os.path.join(HERE, "cli")):
        return HERE
    try:
        import asdd_kit
        staged = os.path.dirname(os.path.realpath(asdd_kit.__file__))
        if os.path.isdir(os.path.join(staged, "cli")):
            return staged
    except Exception:
        pass
    return HERE  # nothing found: the dispatch below fails loudly rather than silently


ROOT = _kit_root()
CLI = os.path.join(ROOT, "cli")
VAL = os.path.join(ROOT, "validation")

# subcommand -> the argv it runs (the tested scripts stay the single source of truth)
COMMANDS = {
    "init":              ["bash",    os.path.join(CLI, "init.sh")],
    "spec-check":        ["python3", os.path.join(CLI, "spec-check.py")],
    "openspec-gate":     ["python3", os.path.join(CLI, "openspec-gate.py")],
    "claim-check":       ["python3", os.path.join(CLI, "claim-check.py")],
    "merge-eligibility": ["python3", os.path.join(CLI, "merge-eligibility.py")],
    "conventions-check": ["python3", os.path.join(CLI, "conventions-check.py")],
    "check-models":      ["bash",    os.path.join(CLI, "check-models.sh")],
    "resolve-model":     ["bash",    os.path.join(CLI, "resolve-model.sh")],
    "setup":             ["python3", os.path.join(CLI, "setup-goose.py")],
    "setup-dashboard":   ["python3", os.path.join(CLI, "setup-dashboard.py")],
    "doctor":            ["python3", os.path.join(CLI, "doctor.py")],
    "dashboard":         ["python3", os.path.join(CLI, "dashboard.py")],
    "recipe-lint":       ["python3", os.path.join(CLI, "recipe-lint.py")],
    "kit-check":         ["python3", os.path.join(CLI, "kit-check.py")],
    "audit":             ["python3", os.path.join(CLI, "audit.py")],
    "operate-run":       ["python3", os.path.join(CLI, "operate-run.py")],
    "audit-ship":        ["bash",    os.path.join(ROOT, ".github", "asdd", "audit-export.sh")],
    "audit-check":       ["python3", os.path.join(VAL, "audit-check.py")],
    "mcp":               ["python3", os.path.join(CLI, "asdd-mcp.py")],
    "validate":          ["python3", os.path.join(VAL, "run-base.py")],
}

HELP = """asdd - the ASDD CLI

Usage: asdd <command> [args...]

Commands:
  init [--goose] [DIR]      scaffold ASDD into a repo (add --goose for the operate kit)
  setup                     guided per-role model wiring for Goose (writes .asdd.yml)
  setup-dashboard           the same, as a local web page (non-engineer front door)
  doctor [CONFIG]           preflight the operate path (tools reachable, spec CLI, roster)
  dashboard --repo O/R      the read-only governance + insights view (internal unless --public)
  spec-check FILE           definition-of-ready gate on a spec object (built-in spec tool)
  openspec-gate CHANGE      readiness gate for an OpenSpec project (delegates to `openspec validate`)
  claim-check LEDGER ...     claim-protocol decision (grant / refuse)
  merge-eligibility PATHS    the conforming-loader merge floor
  conventions-check ...      hold a change to the host project's declared conventions (brownfield)
  check-models [FILE]        enforce developer != tester
  resolve-model ROLE         the model a role actually runs on (roster, else ASDD_MODEL)
  recipe-lint [DIR]          structure gate for the Goose operate recipes
  kit-check [CONFIG]         keep asdd-kit.yml (the kit map) matching reality
  audit SUB ...              the agent audit ledger: append / verify / trail / corpus / knowledge
  operate-run --role R ...   run a Goose operate agent and record it deterministically
  audit-ship LEDGER          push a local ledger to the configured private sink (e.g. .asdd-work/audit.jsonl)
  audit-check TRAIL ...      audit-log properties P1-P9
  mcp                        run the gates as an MCP server (Goose stdio extension)
  validate                   run the runnable-today validation slice

Run `asdd <command> --help` for a command's own options; `asdd --version` prints the version.
The tools live alongside this script; run from a checkout of ASDD.
"""


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        sys.stdout.write(HELP)
        return 0
    if sys.argv[1] in ("-V", "--version"):
        sys.stdout.write(f"asdd {__version__}\n")
        return 0
    cmd = sys.argv[1]
    target = COMMANDS.get(cmd)
    if target is None:
        sys.stderr.write(f"asdd: unknown command '{cmd}'\n\n{HELP}")
        return 2
    if not os.path.exists(target[-1]):
        sys.stderr.write(f"asdd: '{target[-1]}' not found - run from a checkout of ASDD (or `pip install -e .`).\n")
        return 1
    return subprocess.run(target + sys.argv[2:]).returncode


if __name__ == "__main__":
    sys.exit(main())
