#!/usr/bin/env python3
"""ASDD - deterministic + SAST security lens (Platform F2).

Runs inside the READ-ONLY analysis job. It treats the reviewed change as DATA: it reads diff text and
file bytes and applies static checks. It never imports, evals, executes, or shell-interpolates any
reviewed content, so a hostile contribution cannot run here. Output is JSON merged into the `security`
lens of the review (finding shape: severity note|warn|block, message, path). A `block` finding makes
set-status.sh fail the `asdd/review` status, so this is the mechanical half of the security gate.

Layers:
  1. Deterministic rules over the ADDED diff lines (secrets, disabled TLS verification, dangerous
     sinks, Trojan-Source bidi/zero-width Unicode, injected-instruction markers). Always runs, no deps.
  2. OSS SAST: bandit over the changed Python files at head, filtered to the added lines. Best-effort:
     if bandit or the head ref is unavailable, layer 1 still stands.
  3. The model `security` lens (separate, in the runtime) merges in when a runtime is wired.

The scanner is fail-safe: any internal error degrades to "no scanner findings" and leaves the existing
review JSON untouched. It never raises out of main and never corrupts review.json.

Usage: security_scan.py --review <review.json> --workdir <dir> [--head-ref <ref>]
  <workdir>/changes.diff is the unified diff (the only required input).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# Unicode that enables Trojan-Source style attacks: bidirectional overrides/isolates and zero-width
# characters that hide or reorder code from a human reader while the compiler sees something else.
# Built from code points so this source file holds no actual invisible characters.
_BIDI_CODEPOINTS = [
    0x202A,
    0x202B,
    0x202C,
    0x202D,
    0x202E,  # LRE RLE PDF LRO RLO (bidi embeddings/overrides)
    0x2066,
    0x2067,
    0x2068,
    0x2069,  # LRI RLI FSI PDI (bidi isolates)
    0x200B,
    0x200C,
    0x200D,
    0x200E,
    0x200F,  # ZWSP ZWNJ ZWJ LRM RLM
    0xFEFF,  # zero-width no-break space / BOM
]
_BIDI_RE = re.compile("[" + "".join(chr(c) for c in _BIDI_CODEPOINTS) + "]")

# The scanner's rule table necessarily contains the very patterns it detects, so scanning these files
# would yield only self-matches. They live under .github/ (a protected path) and get human review on
# every change regardless, so skipping the automated self-scan costs no safety.
SELF_SKIP = {
    ".github/asdd/security_scan.py",
    "tests/test_reference_security.py",
}

# Values that look like a secret literal but are placeholders, not real secrets. Keep the noise down.
_PLACEHOLDER = re.compile(
    r"(?i)(example|changeme|placeholder|your[_-]?|dummy|redact|xxxx|\*\*\*|<[^>]+>|\$\{|os\.environ|"
    r"getenv|process\.env|fake|test[_-]?(key|token|secret)|sample|n/?a)"
)

# A line carrying one of these is an explicit, reviewed suppression (bandit's `nosec` convention, plus
# an ASDD form). It silences `warn`/`note` findings only - a `block` (merge-holding, high-precision:
# secrets, dangerous exec, injection) fires regardless, so a PR can't `asdd: ignore` its way past a
# critical. Use sparingly; suppressions are visible in the diff.
_SUPPRESS = re.compile(r"(?:#\s*nosec|asdd:\s*ignore)\b", re.IGNORECASE)

# Deterministic rules. Each: (id, severity, compiled regex, human message). Regexes run on the ADDED
# line content (the leading '+' stripped). block = high-precision, merge-holding; warn = needs a human.
_RULES = [
    (
        "secret-private-key",
        "block",
        re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"),
        "Private key material committed in the diff.",
    ),
    (
        "secret-aws-akia",
        "block",
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "Hardcoded AWS access key id.",
    ),
    (
        "secret-aws-secret",
        "block",
        re.compile(r"(?i)aws_secret_access_key\s*[:=]\s*['\"][A-Za-z0-9/+=]{40}['\"]"),
        "Hardcoded AWS secret access key.",
    ),
    (
        "tls-verify-disabled",
        "block",
        re.compile(r"(?i)\bverify\s*=\s*False\b"),
        "TLS certificate verification disabled (verify=False).",
    ),
    (
        "tls-unverified-context",
        "block",
        re.compile(r"_create_unverified_context|ssl\.CERT_NONE"),
        "TLS verification disabled via an unverified SSL context.",
    ),
    (
        "remote-pipe-to-shell",
        "block",
        re.compile(r"(?i)\b(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:bash|sh|zsh)\b"),
        "Piping a downloaded script straight into a shell (remote code execution).",
    ),
    (
        "secret-generic-assign",
        "warn",
        re.compile(
            r"(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?key|auth[_-]?token|"
            r"client[_-]?secret)\b\s*[:=]\s*['\"][^'\"]{8,}['\"]"
        ),
        "Possible hardcoded credential; load secrets from the environment or a vault.",
    ),
    (
        "dangerous-eval-exec",
        "warn",
        re.compile(r"\b(?:eval|exec)\s*\("),
        "Use of eval/exec; avoid executing dynamic strings, especially from external input.",
    ),
    (
        "insecure-deserialization",
        "warn",
        re.compile(r"\b(?:cPickle|pickle)\.loads?\s*\(|yaml\.load\s*\((?![^)]*Safe)"),
        "Insecure deserialization (pickle, or yaml.load without SafeLoader).",
    ),
    (
        "shell-injection-risk",
        "warn",
        re.compile(
            r"(?i)subprocess\.(?:run|call|Popen|check_output|check_call)\s*\([^)]*shell\s*=\s*True|"
            r"\bos\.system\s*\("
        ),
        "Command executed through a shell; build argv lists instead of shell strings.",
    ),
    (
        "curl-insecure-flag",
        "warn",
        re.compile(r"(?i)\b(?:curl|wget)\b.*\s(?:-k|--insecure|--no-check-certificate)\b"),
        "Download with certificate checking disabled.",
    ),
    (
        "injected-instruction",
        "warn",
        re.compile(
            r"(?i)\b(?:ignore|disregard)\b[\s\w,']{0,30}\b(?:previous|prior|above|all|your|the)?"
            r"[\s\w,']{0,10}\binstructions\b|\byou are now\b|\bsystem prompt\b"
        ),
        "Text resembling a prompt-injection instruction in the contribution.",
    ),
]


def _iter_added_lines(diff_text):
    """Yield (path, new_line_number, content) for every ADDED line in a unified diff.

    Pure text parsing - no repo access. Tracks the destination path from `+++ b/<path>` and the new-file
    line counter from each `@@ ... +start,len @@` hunk header so findings can cite file:line.
    """
    path = None
    new_no = 0
    hunk = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            p = raw[4:].strip()
            if p.startswith("b/"):
                p = p[2:]
            path = None if p == "/dev/null" else p
            continue
        if raw.startswith("---") or raw.startswith("diff "):
            continue
        m = hunk.match(raw)
        if m:
            new_no = int(m.group(1))
            continue
        if raw.startswith("+"):
            yield path, new_no, raw[1:]
            new_no += 1
        elif raw.startswith("-"):
            continue  # removed line: does not advance the new-file counter
        else:
            new_no += 1  # context line advances the new-file counter


def scan_diff(diff_text):
    """Deterministic layer: list of findings over the added lines. Pure; the unit tests target this."""
    findings = []
    for path, line_no, content in _iter_added_lines(diff_text):
        if path in SELF_SKIP:
            continue
        loc = f"{path or '(unknown)'}:{line_no}"
        if _BIDI_RE.search(content):
            findings.append(
                {
                    "severity": "block",
                    "rule": "trojan-source-unicode",
                    "tool": "deterministic",
                    "message": "Bidirectional or zero-width Unicode that can hide or reorder code "
                    "(Trojan Source).",
                    "path": loc,
                }
            )
        suppressed = bool(_SUPPRESS.search(content))
        for rule_id, severity, regex, message in _RULES:
            if not regex.search(content):
                continue
            if rule_id == "secret-generic-assign" and _PLACEHOLDER.search(content):
                continue  # obvious placeholder, not a real secret
            if suppressed and severity != "block":
                continue  # a reviewed suppression silences warnings, but NEVER a merge-holding block
            findings.append(
                {
                    "severity": severity,
                    "rule": rule_id,
                    "tool": "deterministic",
                    "message": message,
                    "path": loc,
                }
            )
    return findings


def _changed_python(diff_text):
    """Map each changed .py path -> set of added new-file line numbers (for filtering SAST hits)."""
    by_file = {}
    for path, line_no, _content in _iter_added_lines(diff_text):
        if path and path.endswith(".py") and path not in SELF_SKIP:
            by_file.setdefault(path, set()).add(line_no)
    return by_file


def run_sast(diff_text, head_ref):
    """SAST layer (bandit) over the changed Python files at head, filtered to added lines.

    Best-effort and fully sandboxed from the working tree: it reconstructs each changed file's head
    content with `git show <ref>:<path>` into a temp dir and runs bandit there. Reviewed code is data -
    bandit parses it, nothing here executes it. Returns (findings, note) where note explains a skip.
    """
    by_file = _changed_python(diff_text)
    if not by_file:
        return [], None
    if subprocess.run(["bash", "-c", "command -v bandit"], capture_output=True).returncode != 0:
        return [], "SAST (bandit) not installed; deterministic checks only."

    sev_map = {
        ("HIGH", "HIGH"): "block",
        ("HIGH", "MEDIUM"): "warn",
        ("HIGH", "LOW"): "warn",
        ("MEDIUM", "HIGH"): "warn",
        ("MEDIUM", "MEDIUM"): "warn",
    }
    findings = []
    try:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            written = {}
            for path in by_file:
                blob = subprocess.run(
                    ["git", "show", f"{head_ref}:{path}"], capture_output=True, text=True
                )
                if blob.returncode != 0:
                    continue
                dest = tmp_root / path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(blob.stdout)
                written[str(dest)] = path
            if not written:
                return [], "SAST: no changed Python files were readable at head."
            proc = subprocess.run(
                ["bandit", "-q", "-f", "json", "-r", str(tmp_root)], capture_output=True, text=True
            )
            data = json.loads(proc.stdout or "{}")
            for r in data.get("results", []):
                repo_path = written.get(r.get("filename", ""))
                line = r.get("line_number", 0)
                if not repo_path or line not in by_file.get(repo_path, set()):
                    continue  # pre-existing issue on an unchanged line; only gate new code
                sev = sev_map.get(
                    (r.get("issue_severity", ""), r.get("issue_confidence", "")), "note"
                )
                findings.append(
                    {
                        "severity": sev,
                        "rule": r.get("test_id", "bandit"),
                        "tool": "bandit",
                        "message": f"{r.get('issue_text', 'bandit finding')} "
                        f"(severity {r.get('issue_severity')}, confidence "
                        f"{r.get('issue_confidence')}).",
                        "path": f"{repo_path}:{line}",
                    }
                )
    except Exception as exc:  # bandit/json/git hiccup must never break the gate
        return [], f"SAST skipped after an error: {exc.__class__.__name__}."
    return findings, None


def merge_into_review(review, findings, sast_note):
    """Fold scanner findings into the review's `security` lens and recompute the gate fields."""
    lenses = review.setdefault("lenses", [])
    sec = next((entry for entry in lenses if entry.get("lens") == "security"), None)
    if sec is None:
        sec = {"lens": "security", "verdict": "ok", "findings": []}
        lenses.append(sec)
    sec.setdefault("findings", [])
    sec["findings"].extend(findings)

    has_block = any(f.get("severity") == "block" for f in sec["findings"])
    has_warn = any(f.get("severity") == "warn" for f in sec["findings"])
    sec["verdict"] = "request-changes" if has_block else ("concerns" if has_warn else "ok")
    if has_block:
        review["recommendation"] = "request-changes"

    counts = f"{len(findings)} finding(s)" if findings else "no new issues"
    note = f" Security scan (deterministic + SAST): {counts}."
    if sast_note:
        note += f" {sast_note}"
    review["summary"] = (review.get("summary", "") + note).strip()
    return review


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--review", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--head-ref", default="refs/asdd-pr-head")
    args = parser.parse_args(argv)
    try:
        review_path = Path(args.review)
        review = json.loads(review_path.read_text())
        diff_text = (Path(args.workdir) / "changes.diff").read_text(errors="replace")
        findings = scan_diff(diff_text)
        sast_findings, sast_note = run_sast(diff_text, args.head_ref)
        findings.extend(sast_findings)
        merge_into_review(review, findings, sast_note)
        review_path.write_text(json.dumps(review, indent=2) + "\n")
        blocks = sum(1 for f in findings if f["severity"] == "block")
        print(
            f"asdd: security scan merged {len(findings)} finding(s) ({blocks} block) "
            f"into the security lens",
            file=sys.stderr,
        )
    except Exception as exc:  # fail safe: never break the pipeline or corrupt review.json
        print(
            f"asdd: security scan skipped (non-fatal): {exc.__class__.__name__}: {exc}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
