#!/usr/bin/env python3
"""ASDD - deterministic framework-impact lens.

Runs inside the READ-ONLY analysis job, alongside security_scan.py. It treats the reviewed change as
DATA: it reads the diff's changed paths and the PR body text and applies static checks. It never
imports, evals, executes, or shell-interpolates any reviewed content. Output is JSON merged into the
`impact` lens of the review (finding shape: severity note|warn|block, message, path). A `block` finding
sets recommendation=request-changes, which set-status.sh turns into a failing `asdd/review` status, so
a normative change cannot merge without its declaration, impact analysis, and target version.

Why deterministic: the standard's normative text lives at known paths, and the "did the author declare
this and size it" question is a text check on the PR body. Doing it here means the framework is
protected even before a model runtime is wired (the model `impact` lens, agents/review-impact.md, adds
the harder behavioural case: a change that alters required behaviour on a non-normative path).

This scanner classifies by PATH and by the DECLARATION in the body. It deliberately does NOT judge
behavioural normativity (a gate/lens/agent change that alters required behaviour) - that needs
reading intent, which is the model lens's job. For those paths it emits a `warn` asking for a human or
model call, never a false-confident block.

The scanner is fail-safe: any internal error degrades to "no findings" and leaves review.json
untouched. It never raises out of main and never corrupts review.json.

Usage: impact_scan.py --review <review.json> --workdir <dir>
  <workdir>/changes.diff is the unified diff; <workdir>/body.md is the PR description (both optional).
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

# Paths whose content IS the standard. A change here is normative by definition (STANDARD.md,
# standards/**, CONFORMANCE.md) or changes the governance rules (GOVERNANCE.md, playbook/governance.md).
# Editing any of these requires the normative declaration, an impact analysis, and a target version.
NORMATIVE_TEXT = [
    "STANDARD.md",
    "standards/**",
    "CONFORMANCE.md",
    "GOVERNANCE.md",
    "playbook/governance.md",
]

# Paths that MIGHT change behaviour adopters rely on (a gate, a lens contract, an agent's fixed prompt,
# the runtime seam). A path match here is not proof of a normative change - a typo fix in a comment is
# not - so this yields a `warn` that asks the model lens or a human to judge, never a block.
BEHAVIOURAL_SURFACE = [
    "agents/**",
    ".github/asdd/**",
    "cli/**",
    "validation/**",
    "asdd_cli.py",
    ".asdd.yml",
]

# The scanner reads paths, not code, but skip its own file and the model lens contract so a wording
# change to them is not self-flagged as behavioural (they get human review as protected paths anyway).
SELF_SKIP = {
    ".github/asdd/impact_scan.py",
    ".github/asdd/impact_scan.test.sh",
}


def _changed_paths(diff_text):
    """Return the set of destination paths touched by a unified diff. Pure text parsing, no repo access."""
    paths = set()
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            p = raw[4:].strip()
            if p.startswith("b/"):
                p = p[2:]
            if p and p != "/dev/null":
                paths.add(p)
    return paths


def _matches_any(path, globs):
    return any(fnmatch.fnmatch(path, g) for g in globs)


def _classify_paths(paths):
    """Split changed paths into (normative_text, behavioural_surface)."""
    normative = sorted(p for p in paths if p not in SELF_SKIP and _matches_any(p, NORMATIVE_TEXT))
    behavioural = sorted(
        p
        for p in paths
        if p not in SELF_SKIP
        and p not in normative
        and _matches_any(p, BEHAVIOURAL_SURFACE)
    )
    return normative, behavioural


# A "Change scope" declaration in the PR body. We look for a ticked checkbox on a line that also names
# normative or non-normative. Robust to wording: any `[x]`/`[X]` box on a line mentioning the word.
_TICKED = re.compile(r"\[[xX]\]")


def _declared_scope(body):
    """Return 'normative', 'non-normative', or None from the PR body's Change scope ticks."""
    normative = non_normative = False
    for line in body.splitlines():
        if not _TICKED.search(line):
            continue
        low = line.lower()
        if "non-normative" in low or "non normative" in low:
            non_normative = True
        elif "normative" in low:
            normative = True
    if normative and not non_normative:
        return "normative"
    if non_normative and not normative:
        return "non-normative"
    if normative and non_normative:
        return "ambiguous"
    return None


# An impact analysis is present if the body has the heading and some substance under it, and names a
# target version. Kept deliberately simple: the model lens judges completeness; this checks existence.
_IMPACT_HEADING = re.compile(r"\bimpact analysis\b", re.IGNORECASE)
_TARGET_VERSION = re.compile(
    r"(?i)\btarget version\b.*?(?:\bv?\d+\.\d+(?:\.\d+)?\b|\b(?:major|minor|patch)\b)"
)


def _has_impact_analysis(body):
    if not _IMPACT_HEADING.search(body):
        return False
    # Require at least one non-placeholder line after the heading, so an empty heading does not pass.
    idx = _IMPACT_HEADING.search(body).end()
    tail = body[idx:]
    for line in tail.splitlines():
        s = line.strip().lstrip("#").strip()
        if not s:
            continue
        if s.startswith("<!--") or s.startswith("-->"):
            continue
        # A checklist stub like "- [ ] ..." with no text, or a comment, is not substance.
        stub = re.sub(r"^[-*]\s*\[[ xX]\]\s*", "", s)
        if stub and not stub.startswith("<!--"):
            return True
    return False


def _has_target_version(body):
    return bool(_TARGET_VERSION.search(body))


def evaluate(diff_text, body):
    """Deterministic findings for the impact lens. Pure; the unit test targets this."""
    findings = []
    # Strip HTML comments so the PR template's own placeholder examples (all inside <!-- -->) do not
    # count as author content. Only real, author-written text satisfies the impact-analysis and
    # target-version checks, so keeping an unfilled template does not buy a pass.
    body = re.sub(r"<!--.*?-->", " ", body, flags=re.DOTALL)
    paths = _changed_paths(diff_text)
    normative_paths, behavioural_paths = _classify_paths(paths)
    scope = _declared_scope(body)
    has_impact = _has_impact_analysis(body)
    has_version = _has_target_version(body)

    normative = bool(normative_paths) or scope == "normative"

    if normative:
        where = ", ".join(normative_paths) if normative_paths else "declared normative by the author"
        if not normative_paths and scope == "normative":
            where = "declared normative"
        # Undeclared normative-by-path change: the core "nothing changes the nature unseen" gate.
        if normative_paths and scope in (None, "non-normative"):
            findings.append(
                {
                    "severity": "block",
                    "rule": "normative-undeclared",
                    "message": (
                        f"This PR changes the standard's normative text ({where}) but Change scope is "
                        f"not declared normative. Tick Normative in the PR body, and add an Impact "
                        f"analysis (what else must adjust) and a target version."
                    ),
                    "path": normative_paths[0],
                }
            )
        if scope == "ambiguous":
            findings.append(
                {
                    "severity": "block",
                    "rule": "scope-ambiguous",
                    "message": "Change scope ticks both normative and non-normative. Tick exactly one.",
                    "path": "PR body",
                }
            )
        if not has_impact:
            findings.append(
                {
                    "severity": "block",
                    "rule": "impact-analysis-missing",
                    "message": (
                        "A normative change must carry an Impact analysis stating what else must adjust "
                        "(other MUSTs, gates, lenses, CONFORMANCE items, docs). None found in the PR body."
                    ),
                    "path": "PR body",
                }
            )
        if not has_version:
            findings.append(
                {
                    "severity": "block",
                    "rule": "target-version-missing",
                    "message": (
                        "A normative change must name a target version and its SemVer level (major for a "
                        "new or tightened MUST, minor for a new SHOULD or clarification, patch for "
                        "editorial); see playbook/governance.md. None found in the PR body."
                    ),
                    "path": "PR body",
                }
            )
        if not findings:
            findings.append(
                {
                    "severity": "note",
                    "rule": "normative-declared",
                    "message": (
                        f"Normative change ({where}); declaration, impact analysis, and target version "
                        f"present. A maintainer gives the governance sign-off before merge."
                    ),
                    "path": normative_paths[0] if normative_paths else "PR body",
                }
            )
    elif behavioural_paths:
        # Not normative text, but touches a gate/lens/agent/runtime surface. Ask the model lens or a
        # human whether required behaviour changed. Never a confident block from paths alone.
        findings.append(
            {
                "severity": "warn",
                "rule": "behaviour-surface-touched",
                "message": (
                    "This change touches a behavioural surface (a gate, lens, agent prompt, or the "
                    f"runtime seam: {', '.join(behavioural_paths[:5])}). If it changes behaviour "
                    "adopters rely on for conformance, it is normative: declare it and add an impact "
                    "analysis and target version. If it preserves behaviour, no action."
                ),
                "path": behavioural_paths[0],
            }
        )
    else:
        findings.append(
            {
                "severity": "note",
                "rule": "non-normative",
                "message": "No normative text or behavioural surface touched; classified non-normative.",
                "path": "(scope)",
            }
        )
    return findings


def merge_into_review(review, findings):
    """Fold findings into the review's `impact` lens and recompute the gate fields."""
    lenses = review.setdefault("lenses", [])
    imp = next((entry for entry in lenses if entry.get("lens") == "impact"), None)
    if imp is None:
        imp = {"lens": "impact", "verdict": "ok", "findings": []}
        lenses.append(imp)
    imp.setdefault("findings", [])
    imp["findings"].extend(findings)

    has_block = any(f.get("severity") == "block" for f in imp["findings"])
    has_warn = any(f.get("severity") == "warn" for f in imp["findings"])
    imp["verdict"] = "request-changes" if has_block else ("concerns" if has_warn else "ok")
    if has_block:
        review["recommendation"] = "request-changes"

    blocks = sum(1 for f in findings if f.get("severity") == "block")
    note = f" Impact scan: {len(findings)} finding(s), {blocks} block."
    review["summary"] = (review.get("summary", "") + note).strip()
    return review


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--review", required=True)
    parser.add_argument("--workdir", required=True)
    args = parser.parse_args(argv)
    try:
        review_path = Path(args.review)
        review = json.loads(review_path.read_text())
        workdir = Path(args.workdir)
        diff_text = ""
        body = ""
        try:
            diff_text = (workdir / "changes.diff").read_text(errors="replace")
        except OSError:
            pass
        try:
            body = (workdir / "body.md").read_text(errors="replace")
        except OSError:
            pass
        findings = evaluate(diff_text, body)
        merge_into_review(review, findings)
        review_path.write_text(json.dumps(review, indent=2) + "\n")
        blocks = sum(1 for f in findings if f["severity"] == "block")
        print(
            f"asdd: impact scan merged {len(findings)} finding(s) ({blocks} block) into the impact lens",
            file=sys.stderr,
        )
    except Exception as exc:  # fail safe: never break the pipeline or corrupt review.json
        print(
            f"asdd: impact scan skipped (non-fatal): {exc.__class__.__name__}: {exc}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
