#!/usr/bin/env python3
"""asdd operate-run - run a Goose operate agent and record it DETERMINISTICALLY.

An operate agent used to record its own action by running `audit.py append` as its final step. That is
fragile: if the model run dies partway (a provider timeout on a long multi-turn run, or the model simply
not reaching the last step), the action happens but no record is written, and the trail silently loses
it. The govern side never has this problem, because the pipeline writes the review records from the
result, not by asking the model to run a command.

This wrapper gives the operate side the same guarantee. It runs the recipe, then emits EXACTLY ONE audit
record no matter how the run ended:

  - the agent writes its outcome to a result file (.asdd-work/operate-result.json); if it is there, the
    record is rich (verdict, reasoning, payload);
  - if it is absent, because the run died early or produced nothing, the wrapper still emits a record
    naming the role, the action, and that the run did not complete, so the action is never lost.

The emission is the wrapper's job, not the model's, so a flaky provider cannot cost you the record.

Zero-dependency (stdlib). Exit code mirrors the underlying goose run, so CI can still see a failed run.

Usage:
  operate-run.py --role test-runner --recipe recipes/test-runner.yaml --param pr=42 --instructed-by me
  operate-run.py --role documentation --recipe recipes/documentation.yaml --model <M> --param change_ref=42
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
AUDIT = os.path.join(HERE, "audit.py")

# The valid audit roles, from the ledger itself, so the wrapper refuses a bad role BEFORE running a whole
# agent only to be unable to record it. A record that cannot be written is exactly the loss this exists to
# prevent, so an unknown role is a hard error, not a warning after the fact.
try:
    sys.path.insert(0, HERE)
    from audit import ROLES  # noqa: E402
except Exception:
    ROLES = ("developer", "intake", "review", "impact", "security", "test-author",
             "test-runner", "documentation", "triage", "spec", "merge")
DEFAULT_LEDGER = os.path.join(".asdd-work", "audit.jsonl")
DEFAULT_RESULT = os.path.join(".asdd-work", "operate-result.json")


def read_result(path):
    """The agent's structured outcome, or None. Never trust it blindly: it is model output, so it is used
    only to enrich a record the wrapper emits either way, and only known-safe fields are read from it."""
    try:
        with open(path, encoding="utf-8") as fh:
            obj = json.load(fh)
        return obj if isinstance(obj, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def emit(role, ledger, instructed_by, result, goose_exit):
    """Append exactly one record. Rich if the agent left a result, minimal otherwise."""
    argv = ["python3", AUDIT, "append", "--ledger", ledger, "--role", role,
            "--accountable-human", instructed_by]
    if result:
        argv += ["--action", str(result.get("action") or f"{role}.run")]
        argv += ["--authorizing-decision",
                 str(result.get("authorizing_decision") or f"operator invoked the {role} agent")]
        for flag, key in (("--verdict", "verdict"), ("--action-taken", "action_taken"),
                          ("--reasoning", "reasoning")):
            if result.get(key):
                argv += [flag, str(result[key])]
        if isinstance(result.get("payload"), (dict, list)):
            argv += ["--payload-json", json.dumps(result["payload"])]
        if isinstance(result.get("target"), dict):
            argv += ["--target-json", json.dumps(result["target"])]
        # An agent that was driven by untrusted input records it, so a membrane failure is visible in the
        # trail (P4) rather than hidden.
        if result.get("untrusted"):
            argv += ["--untrusted-as-instruction"]
    else:
        # The run produced no structured result. Record the action anyway so the trail does not silently
        # lose it; say plainly that it did not complete, and let the goose exit code carry the outcome.
        state = "incomplete" if goose_exit != 0 else "completed without a structured result"
        argv += ["--action", f"{role}.run",
                 "--authorizing-decision", f"operator invoked the {role} agent",
                 "--action-taken", state,
                 "--reasoning", (f"the {role} run left no structured result (goose exit {goose_exit}); "
                                 "recorded by the run wrapper so the action is not lost")]
    rc = subprocess.run(argv).returncode
    return rc == 0


def main():
    ap = argparse.ArgumentParser(description="Run a Goose operate agent and record it deterministically.")
    ap.add_argument("--role", required=True, help="the operate role (test-runner, documentation, ...)")
    ap.add_argument("--recipe", required=True, help="the Goose recipe to run")
    ap.add_argument("--ledger", default=DEFAULT_LEDGER)
    ap.add_argument("--result", default=DEFAULT_RESULT,
                    help="where the recipe writes its structured outcome")
    ap.add_argument("--instructed-by", default="the maintainer",
                    help="the human accountable for this run")
    ap.add_argument("--model")
    ap.add_argument("--provider")
    ap.add_argument("--param", action="append", default=[], metavar="K=V",
                    help="a recipe parameter, repeatable")
    ap.add_argument("--skip-goose", action="store_true",
                    help="do not run goose; only emit (from an existing result). For tests.")
    ap.add_argument("--goose-exit", type=int, default=0,
                    help="with --skip-goose, the simulated run outcome. For tests.")
    a = ap.parse_args()

    if a.role not in ROLES:
        sys.stderr.write(f"operate-run: unknown role {a.role!r}. The record could not be written for an "
                         f"unknown role, so this fails fast. Valid roles: {', '.join(ROLES)}.\n"
                         "The interaction recipe records as 'spec'.\n")
        return 2

    os.makedirs(os.path.dirname(a.ledger) or ".", exist_ok=True)
    # Clear any stale result so we read only THIS run's outcome.
    if not a.skip_goose:
        try:
            os.remove(a.result)
        except OSError:
            pass

    goose_exit = a.goose_exit
    if not a.skip_goose:
        gargv = ["goose", "run", "--recipe", a.recipe]
        if a.provider:
            gargv += ["--provider", a.provider]
        if a.model:
            gargv += ["--model", a.model]
        for p in a.param:
            gargv += ["--params", p]
        try:
            goose_exit = subprocess.run(gargv).returncode
        except FileNotFoundError:
            sys.stderr.write("operate-run: goose not found on PATH; cannot run the agent.\n")
            goose_exit = 127

    result = read_result(a.result)
    ok = emit(a.role, a.ledger, a.instructed_by, result, goose_exit)
    if not ok:
        sys.stderr.write("operate-run: WARNING the audit record could not be written.\n")
    kind = "rich" if result else "minimal (no structured result)"
    sys.stderr.write(f"operate-run: {a.role} recorded ({kind}); goose exit {goose_exit}.\n")
    # Surface the run's real outcome to the caller (CI, a human), not the emit's.
    return goose_exit


if __name__ == "__main__":
    sys.exit(main())
