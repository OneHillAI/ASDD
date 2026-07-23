#!/usr/bin/env python3
"""Run the runnable-today (deterministic) slice of the ASDD validation suite as
one command. Drives the reference tools + the effectiveness oracle and reports a
single PASS/FAIL. Everything model-driven, or needing the base pipeline in the
product repo, is listed as not-run-here. Zero-dependency (stdlib).

    python3 validation/run-base.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root (parent of validation/)

# (name, argv, expect: "zero" | "nonzero", covers)
CHECKS = [
    ("workflow YAML parses",                    ["bash", "cli/workflow-lint.test.sh"],
     "zero", "a broken workflow runs nothing and merges invisibly; the hole that took docs down"),
    ("intake gate (1/3/6.1/SD, redteam A3)",    ["bash", ".github/asdd/intake-check.test.sh"],
     "zero", "the airlock: disclosure/DCO/one-lane, spec_paths honoured per project, and a `..` "
             "reference or a regex-shaped pattern cannot buy a pass"),
    ("spec-check gate (SD, redteam A3)",        ["sh", "cli/spec-check.test.sh"],
     "zero", "spec-object definition-of-ready + independent forced-ready block"),
    ("openspec readiness gate (SD, agnostic)",  ["bash", "cli/openspec-gate.test.sh"],
     "zero", "OpenSpec delegation reads pass/fail from the JSON, never the exit code (which is 0 on "
             "failure); fails closed on zero-items / drifted schema / missing binary"),
    ("claim-check protocol (CL, redteam I1)",   ["sh", "cli/claim-check.test.sh"],
     "zero", "one-active-per-item, TTL auto-release, per-identity cap"),
    ("merge-eligibility (2.2/5.2, redteam D1)", ["sh", "cli/merge-eligibility.test.sh"],
     "zero", "protected paths never auto-merge, even if misconfigured"),
    ("public comment hygiene",                  ["bash", ".github/asdd/post-review.test.sh"],
     "zero", "the advisory comment is a public artefact and must meet the writing standard"),
    ("audit-log properties (P1-P6, P9)",        ["sh", "validation/audit-check.test.sh"],
     "zero", "for-all invariants over the audit trail"),
    ("operate-run deterministic emission",      ["bash", "cli/operate-run.test.sh"],
     "zero", "the run wrapper emits exactly one record even when the agent run produced nothing, so a "
             "provider timeout mid-run cannot silently lose the action"),
    ("developer council orchestrator",          ["bash", "cli/dev-council.test.sh"],
     "zero", "the optional multi-model developer: sizing (2 to 5), heterogeneity (developer != testers), "
             "dry-run, one record per run, and the council's learnings deriving exemplar/rejected OKGF pages"),
    ("connect-check: agents connected or dry",  ["bash", "cli/connect-check.test.sh"],
     "zero", "every agent dry-runs until its model runtime is connected; connect-check reports LIVE or NOT "
             "CONNECTED per role so a fresh setup cannot silently do no real work"),
    ("audit ledger: record, corpus, knowledge", ["bash", "cli/audit.test.sh"],
     "zero", "every role records (developer included), the chain detects tamper, and the training and "
             "knowledge views read the trail without leaking chain plumbing or reviewed content"),
    ("heterogeneity accepts a valid config",    ["bash", "cli/check-models.sh", ".asdd.example.yml"],
     "zero", "template / distinct models pass"),
    ("heterogeneity rejects dev==tester (G1)",  ["bash", "cli/check-models.sh", "validation/cases/dev-equals-tester.yml"],
     "nonzero", "a config with developer==tester is rejected"),
    ("effectiveness oracle calibration",        ["python3", "validation/cases/tasks/feat-pagination/harness.py"],
     "zero", "oracle passes the correct solution, fails the seeded defect"),
    ("gates MCP extension (Goose)",             ["sh", "cli/asdd-mcp.test.sh"],
     "zero", "the deterministic gates are callable as MCP tools over stdio"),
    ("asdd unified CLI",                        ["sh", "asdd_cli.test.sh"],
     "zero", "one command routes to init / the gates / mcp / validate"),
    ("recipe dist layout in sync",              ["python3", "cli/gen-recipe-dist.py", "--check"],
     "zero", "root <name>/recipe.yaml copies match recipes/ for GOOSE_RECIPE_GITHUB_REPO fetch-by-name"),
    ("operate recipe structure lint",           ["sh", "cli/recipe-lint.test.sh"],
     "zero", "each operate recipe keeps its invariants: gates wired, public stays execution-free, membrane intact"),
    ("review lenses resolve via the roster",    ["sh", "cli/run-review-resolve.test.sh"],
     "zero", "run-review resolves the reviewer role's model/endpoint/key and never prints the key"),
    ("review runtime recovers model JSON",       ["bash", ".github/asdd/runtime/extract-json.test.sh"],
     "zero", "a reasoning model wraps its JSON in prose/fences/braces; the runtime recovers the review "
             "object instead of losing it to a human-review placeholder, and still rejects genuine non-JSON"),
    ("roster resolves to a role's model",       ["sh", "cli/resolve-model.test.sh"],
     "zero", "a role runs on models.<role> from the roster, ASDD_MODEL is only the fallback, unset fails loudly"),
    ("kit map matches reality",                 ["sh", "cli/kit-check.test.sh"],
     "zero", "asdd-kit.yml's roles/recipes match the config and disk, so an agent's map is never a lie"),
    ("guided model setup wizard",               ["sh", "cli/setup-goose.test.sh"],
     "zero", "per-role model wiring writes .asdd.yml and refuses a developer==test assignment"),
    ("init scaffolds lanes + recipes",          ["sh", "cli/init.test.sh"],
     "zero", "init --goose writes the operate-taxonomy lanes and copies the current deployment recipes"),
    ("setup dashboard renders + writes",        ["sh", "cli/setup-dashboard.test.sh"],
     "zero", "the local setup page renders the roles/form and its write path validates heterogeneity"),
    ("governance dashboard renders",            ["sh", "cli/dashboard.test.sh"],
     "zero", "PRs bucketed by governance stage + releases + contributors into a self-contained HTML page"),
    ("operate-agent security guard",            ["sh", "cli/operate-guard.test.sh"],
     "zero", "a tool-using recipe is refused on untrusted input; execution-free is allowed"),
    ("host conventions gate (brownfield)",      ["bash", "cli/conventions-check.test.sh"],
     "zero", "agent output is held to the host project's DECLARED conventions, judging only the change "
             "and checking style on added lines only, so a mature repo can adopt and ratchet"),
    ("operate-path preflight (doctor)",         ["bash", "cli/doctor.test.sh"],
     "zero", "doctor names reachable / installed-off-PATH / absent apart, and only fails on a hard "
             "requirement of the config (a selected spec CLI absent, or a broken roster)"),
]

NOT_RUN_HERE = [
    "redteam A1/A2/E1/F1/H1/J1 end-to-end - need the base pipeline (security_scan, policy-check) wired in a product repo. The intake gate's own properties now run here.",
    "the model-driven spec agent, contributor-review, and the review lenses - need the model runtime",
    "properties P7/P8 (membrane + claim state) - need the profile's live implementation",
]


def run(argv):
    return subprocess.run(argv, cwd=ROOT, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode


def main():
    print("ASDD validation - runnable-today (deterministic) slice\n")
    results = []
    for name, argv, expect, covers in CHECKS:
        rc = run(argv)
        ok = (rc == 0) if expect == "zero" else (rc != 0)
        results.append(ok)
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
        print(f"         {covers}")
    npass, n = sum(results), len(results)
    print(f"\n{npass}/{n} checks passed\n")
    print("Not run here (by design):")
    for line in NOT_RUN_HERE:
        print(f"  - {line}")
    print("\nRESULT:", "PASS" if npass == n else "FAIL")
    return 0 if npass == n else 1


if __name__ == "__main__":
    sys.exit(main())
