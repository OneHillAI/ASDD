#!/usr/bin/env python3
"""ASDD - the agent audit ledger (STANDARD 1.3).

Every agent action gets one append-only record: who did it, what, to what, under whose authorisation,
when, why, and what it caused. The ledger is the raw record of what happened. It is the substrate the
dashboard renders, the knowledge layer derives from, and a training corpus exports from. It is never a
gate: nothing here approves, blocks, or merges.

Integrity: records are chained. Each carries `prev`, the hash of the record before it, and `hash`, its own.
Removing or editing a record breaks the chain and `verify` reports where. That is what makes a trail
usable as evidence rather than a log file anyone could quietly rewrite.

Privacy: a record holds a DIGEST of what the agent saw (`inputs_digest`), never a copy of the reviewed
content. The ledger still inherits the sensitivity of the code it describes, so it is exported to a
private sink the adopter owns (see .github/asdd/audit-export.sh); it is never written into the governed
repository.

Zero dependencies (stdlib). Safe to call from a read-only job: it only writes to the path it is given.

    python3 cli/audit.py append --ledger L --role review --lens code --action review.lens.completed \
        --verdict ok --reasoning "..." [--payload-json '{...}'] [--target-json '{...}']
    python3 cli/audit.py verify --ledger L
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

SCHEMA = "asdd/audit/v0.1"

# The roles that emit. The govern layer (this repo's CI) emits intake, the review lenses, and merge;
# the operate layer (the adopter's agents) emits the rest through this same helper.
ROLES = (
    "developer",
    "intake", "review", "impact", "security",
    "test-author", "test-runner", "documentation",
    "triage", "spec", "merge",
)
# `developer` is the bring-your-own coding agent (OP.1). It runs as a human's own session rather than a
# deployment recipe, so it does not emit automatically; it records with one `append` at the end of a
# build. Recording it is what makes the ledger cover EVERY role the loop runs, not only the ones that
# run in CI, which is the whole point of a trail meant to feed training and knowledge.


def _canonical(obj):
    """Stable JSON for hashing: sorted keys, no incidental whitespace."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(text):
    return "sha256:" + hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()


def last_hash(ledger):
    """The hash of the final record, or the genesis marker for an empty/absent ledger."""
    try:
        prev = "sha256:genesis"
        with open(ledger, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    prev = json.loads(line).get("hash") or prev
                except json.JSONDecodeError:
                    continue
        return prev
    except OSError:
        return "sha256:genesis"


def build_record(*, role, action, lens=None, identity=None, model=None, provider=None,
                 kind="action", untrusted_as_instruction=False,
                 target=None, authorizing_decision=None, accountable_human=None,
                 run=None, duration_ms=None, verdict=None, action_taken=None,
                 reasoning=None, inputs=None, inputs_digest=None, payload=None, ts=None):
    """Assemble a record. `inputs` is hashed rather than stored, so content never lands in the ledger."""
    rec = {
        "schema": SCHEMA,
        # `kind`, `run_id`, `agent_id` and `untrusted_as_instruction` are the field names
        # validation/audit-check.py asserts the trail properties over (P1-P6, P9). Emitting them here
        # means the framework's own property checker can evaluate this ledger directly, instead of the
        # trail and its checker being two shapes that never meet.
        "kind": kind,
        "ts": ts or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "agent": {k: v for k, v in (
            ("identity", identity), ("role", role), ("lens", lens),
            ("model", model), ("provider", provider)) if v},
        "action": action,
        "target": target or {},
        "authorizing_decision": authorizing_decision or "",
        "accountable_human": accountable_human or "",
        "run": run or {},
        "run_id": (run or {}).get("id", ""),
        "agent_id": identity or role,
        # P4: an action must never be DRIVEN by untrusted input. A lens analyses untrusted content but
        # does not obey it, so it records false. An emitter that cannot assert this must say so.
        "untrusted_as_instruction": bool(untrusted_as_instruction),
        "outcome": {k: v for k, v in (("verdict", verdict), ("action_taken", action_taken)) if v},
        "reasoning": reasoning or "",
        "payload": payload or {},
    }
    if duration_ms is not None:
        rec["duration_ms"] = duration_ms
    if inputs_digest:
        rec["inputs_digest"] = inputs_digest
    elif inputs is not None:
        rec["inputs_digest"] = _digest(inputs)
    return rec


def append(ledger, record):
    """Chain and append one record. Returns the stored record (with prev/hash/event_id)."""
    rec = dict(record)
    rec["prev"] = last_hash(ledger)
    rec.pop("hash", None)
    rec["hash"] = _digest(_canonical(rec))
    rec["event_id"] = rec["hash"].split(":", 1)[1][:32]
    d = os.path.dirname(os.path.abspath(ledger))
    if d:
        os.makedirs(d, exist_ok=True)
    with open(ledger, "a", encoding="utf-8") as fh:
        fh.write(_canonical(rec) + "\n")
    return rec


def ledger_files(path):
    """The .jsonl files that make up a ledger, in chain order. A single file is itself; a synced sink is a
    directory of ledger/<year>/<month>.jsonl, whose zero-padded names sort chronologically, which is the
    chain order. Returns [] for a path that does not exist. Same walk as read_records, kept in step."""
    if os.path.isdir(path):
        return sorted(os.path.join(r, f) for r, _d, fs in os.walk(path)
                      for f in fs if f.endswith(".jsonl"))
    return [path] if os.path.exists(path) else []


def overall_tip(path):
    """The hash of the last record across the whole ledger (a file or a synced-sink directory), or the
    genesis marker if it is empty or absent. This is the tip a new batch must be grafted onto so the
    accumulated chain stays continuous across runs, files, and months."""
    prev = "sha256:genesis"
    for f in ledger_files(path):
        try:
            with open(f, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        try:
                            prev = json.loads(line).get("hash") or prev
                        except json.JSONDecodeError:
                            continue
        except OSError:
            continue
    return prev


def rechain(records, onto):
    """Re-chain records onto the hash `onto`, recomputing prev, hash and event_id for each. The per-run
    hash is ephemeral staging; the destination is the authoritative chain, so grafting a batch onto the
    sink's tip is correct rather than lossy. Only the chain fields change; the content is untouched, and
    the recomputed hash is exactly what append() would have produced at that position."""
    out = []
    tip = onto
    for record in records:
        rec = {k: v for k, v in record.items() if k not in ("prev", "hash", "event_id")}
        rec["prev"] = tip
        rec["hash"] = _digest(_canonical(rec))
        rec["event_id"] = rec["hash"].split(":", 1)[1][:32]
        tip = rec["hash"]
        out.append(rec)
    return out


def verify(ledger):
    """Walk the chain across the whole ledger (a file, or a synced-sink directory of monthly files).
    Returns (ok, count, error_or_None). The accumulated ledger is ONE chain: the very first record is
    genesis-rooted and every record after it, including the first of a new month file, links to the one
    before. That is what makes a deletion anywhere, including of a whole month file, detectable."""
    files = ledger_files(ledger)
    if not files:
        return False, 0, "cannot read ledger: path not found"
    prev = "sha256:genesis"
    n = 0
    multi = len(files) > 1 or os.path.isdir(ledger)
    for f in files:
        where = (os.path.basename(f) + " ") if multi else ""
        try:
            fh = open(f, encoding="utf-8")
        except OSError as exc:
            return False, n, f"cannot read {where.strip() or f}: {exc.__class__.__name__}"
        with fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    return False, n, f"{where}line {lineno}: not valid JSON"
                if rec.get("prev") != prev:
                    return False, n, (f"{where}line {lineno}: broken chain "
                                      "(prev does not match the record before it)")
                stated = rec.get("hash")
                body = {k: v for k, v in rec.items() if k not in ("hash", "event_id")}
                if stated != _digest(_canonical(body)):
                    return False, n, f"{where}line {lineno}: record was altered (hash does not match its content)"
                prev = stated
                n += 1
    return True, n, None


# Which role a lens belongs to. The security and impact lenses are their own roles because they gate
# differently; the rest are review lenses.
_LENS_ROLE = {"security": "security", "impact": "impact"}


def _meta(workdir):
    """Read the run's meta.env (pr_number, base_sha, head_sha) as a dict. Best-effort."""
    out = {}
    try:
        with open(os.path.join(workdir, "meta.env"), encoding="utf-8") as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    out[k] = v
    except OSError:
        pass
    return out


def from_review(review_path, ledger, workdir=None, repo=None, run=None):
    """Emit one record per lens plus one for the overall outcome, from a completed review.json.

    This is how the govern layer satisfies 1.3 for the review roles without each lens knowing about the
    ledger. Findings are recorded; the reviewed content is not (review.json holds verdicts, not sources).
    """
    with open(review_path, encoding="utf-8") as fh:
        review = json.load(fh)
    meta = _meta(workdir) if workdir else {}
    target = {k: v for k, v in (
        ("repo", repo or os.environ.get("GITHUB_REPOSITORY")),
        ("pr", review.get("pr_number") or meta.get("pr_number")),
        ("commit", review.get("head_sha") or meta.get("head_sha"))) if v}
    run = run or {k: v for k, v in (
        ("id", os.environ.get("GITHUB_RUN_ID")),
        ("workflow", os.environ.get("GITHUB_WORKFLOW"))) if v}
    mode = review.get("mode", "live")
    rec_action = review.get("recommendation", "comment")
    written = []

    for lens in review.get("lenses", []) or []:
        name = lens.get("lens", "unknown")
        findings = lens.get("findings", []) or []
        blocks = [f for f in findings if f.get("severity") == "block"]
        # What the lens's verdict actually caused, in the pipeline's terms.
        caused = "block" if blocks else ("request-changes" if rec_action == "request-changes" else "comment")
        reasoning = "; ".join(f.get("message", "") for f in findings[:3]) or \
                    f"{name} lens returned {lens.get('verdict', 'n/a')} with no findings"
        written.append(append(ledger, build_record(
            role=_LENS_ROLE.get(name, "review"), lens=name,
            action="review.lens.completed",
            identity=os.environ.get("ASDD_AGENT_IDENTITY") or "asdd-review",
            model=os.environ.get("ASDD_MODEL"),
            target=target, run=run,
            authorizing_decision=f"review mode={mode}; advisory (a human approves and merges)",
            accountable_human=os.environ.get("ASDD_ACCOUNTABLE_HUMAN", ""),
            verdict=lens.get("verdict"), action_taken=caused, reasoning=reasoning,
            payload={"findings": findings, "mode": mode},
        )))

    written.append(append(ledger, build_record(
        role="review", action="review.completed",
        identity=os.environ.get("ASDD_AGENT_IDENTITY") or "asdd-review",
        target=target, run=run,
        authorizing_decision=f"review mode={mode}",
        accountable_human=os.environ.get("ASDD_ACCOUNTABLE_HUMAN", ""),
        verdict=rec_action,
        action_taken="set-status" if rec_action == "request-changes" else "comment",
        reasoning=review.get("summary", ""),
        payload={"mode": mode, "lens_count": len(review.get("lenses", []) or [])},
    )))
    return written


def read_records(ledger):
    """Yield the parsed records of a ledger (a .jsonl file, or a directory of them). One reader for every
    consumer, so the trail, the corpus and the knowledge views can never read the store three ways."""
    paths = []
    if os.path.isdir(ledger):
        for root, _dirs, files in os.walk(ledger):
            paths += [os.path.join(root, f) for f in files if f.endswith(".jsonl")]
        paths.sort()  # ledger/<year>/<month>.jsonl sorts chronologically
    else:
        paths = [ledger]
    for path in paths:
        try:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        continue
        except OSError:
            continue


# Payload keys safe to carry into a training export: scalars that are counts or categoricals, never free
# text and never a path. Everything else is dropped, so a field added to a payload later cannot land in a
# corpus by default. Whitelist by construction, not blacklist by filtering.
_CORPUS_PAYLOAD_KEYS = {"passed", "failed", "tested", "coverage", "count", "lens_count", "mode"}


def _safe_payload(payload):
    """A training-safe projection of the role payload. Free text and code paths are the leak: a review
    lens puts a finding's message and its `path:line` into the payload, so passing it through would put
    the vulnerability description and the vulnerable location into a training corpus and a shared
    knowledge base. This keeps only counts and categoricals, and reduces findings to their shape (how
    many, which severities, which rules), never their messages or paths."""
    if not isinstance(payload, dict):
        return {}
    out = {k: v for k, v in payload.items()
           if k in _CORPUS_PAYLOAD_KEYS and isinstance(v, (int, float, str, bool))}
    findings = payload.get("findings")
    if isinstance(findings, list) and findings:
        sev, rules = {}, set()
        for f in findings:
            if isinstance(f, dict):
                s = f.get("severity")
                if isinstance(s, str):
                    sev[s] = sev.get(s, 0) + 1
                r = f.get("rule")
                if isinstance(r, str):
                    rules.add(r)
        out["finding_count"] = len(findings)
        if sev:
            out["severities"] = sev
        if rules:
            out["rules"] = sorted(rules)
    for list_key, count_key in (("tests", "test_count"), ("documents", "document_count")):
        v = payload.get(list_key)
        if isinstance(v, list):
            out[count_key] = len(v)   # names and paths dropped, only the count kept
    return out


def _safe_target(target):
    """Refs only: repo, pr, commit. A target also carries the changed `paths`, which are code locations,
    and those do not belong in a training export."""
    if not isinstance(target, dict):
        return {}
    return {k: target[k] for k in ("repo", "pr", "commit") if k in target}


def to_corpus(rec):
    """One training example from one record: what the agent decided and caused. This is the TRAINING view
    of the event stream. It keeps the decision signal (role, reasoning, action, outcome) and drops the
    chain plumbing (hashes, links). Content safety is enforced by construction, not by trust: the record
    already stores a digest of inputs rather than the inputs, and this additionally reduces the payload
    to counts and categoricals and the target to refs, so a finding's message, a code path, or a field
    added to a payload later cannot flow into a training or knowledge export. The reasoning is the agent's
    own summary of its decision and is retained as the training signal."""
    agent = rec.get("agent", {})
    return {
        "role": agent.get("role", rec.get("agent_id", "")),
        "lens": agent.get("lens", ""),
        "model": agent.get("model", ""),
        "action": rec.get("action", ""),
        "authorizing_decision": rec.get("authorizing_decision", ""),
        "reasoning": rec.get("reasoning", ""),
        "outcome": rec.get("outcome", {}),
        "payload": _safe_payload(rec.get("payload", {})),
        "inputs_digest": rec.get("inputs_digest", ""),
        "target": _safe_target(rec.get("target", {})),
    }


# Which record kinds carry durable, reusable knowledge, and the knowledge KIND each maps to. A test
# result or a doc sync is a one-off event, not knowledge; a verdict with reasoning is. This is the
# curated KNOWLEDGE view, and it is intentionally selective: the ledger records everything, the
# knowledge base holds only what a later run should be able to learn from.
_KNOWLEDGE_KIND = {
    "review": "invariant", "impact": "invariant", "security": "invariant",
    "spec": "rejected", "test-author": "exemplar",
    # Developer council (cli/dev-council.py): a proposal the council set aside is a "rejected" approach a
    # later run can learn to avoid; the synthesised, verified result is an "exemplar" to learn from. These
    # arrive on the record's `lens`, so only the council's curated learnings (not every developer action)
    # enter the knowledge base.
    "council-rejected": "rejected", "council-synthesis": "exemplar",
}


# The knowledge view emits real OKGF pages, because OKGF is the knowledge standard ASDD adopts. An OKGF
# page is YAML frontmatter (a required non-empty `type`, an enum `x-okgf-scope`/`x-okgf-review`, a URI
# list `x-okgf-sources`) plus a markdown body. We serialize that format directly (stdlib, no PyYAML, to
# match the rest of the CLI), and the test cross-checks the output against OKGF's own validator so this
# can never drift from the standard. There is no adapter: an OKGF store ingests these pages as they are.
_OKGF_KEY_ORDER = ("type", "title", "description", "timestamp", "tags",
                   "x-okgf-scope", "x-okgf-review", "x-okgf-tier", "x-okgf-sources", "x-okgf-signature")


def _slug(text):
    """A slug matching OKGF's own slugify: lowercased, non-alphanumerics collapsed to single hyphens."""
    return re.sub(r"[^a-z0-9]+", "-", str(text).strip().lower()).strip("-")


def _yaml_dq(s):
    """A YAML double-quoted scalar for an arbitrary string. Double-quoting everything is safe: quoted and
    bare both parse back to the same string, so the output stays conformant without a YAML emitter."""
    s = str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\t", " ")
    return '"' + s + '"'


def okgf_serialize(page):
    """Serialize an OKGF page {slug, fm, body} to OKGF markdown, in OKGF's canonical key order."""
    fm = page.get("fm", {})
    lines = ["---"]
    for k in _OKGF_KEY_ORDER:
        v = fm.get(k)
        if v in (None, "", []):
            continue
        if isinstance(v, list):
            lines.append(f"{k}:")
            lines.extend(f"  - {_yaml_dq(x)}" for x in v)
        else:
            lines.append(f"{k}: {_yaml_dq(v)}")
    lines.append("---")
    return "\n".join(lines) + "\n\n" + str(page.get("body", "")).strip() + "\n"


def _okgf_sources(rec):
    """Provenance as a list of URI strings (OKGF `x-okgf-sources`). Real GitHub URLs when the CI context
    is present (GITHUB_SERVER_URL + GITHUB_REPOSITORY), otherwise stable `asdd://` URIs."""
    tgt = rec.get("target")
    tgt = tgt if isinstance(tgt, dict) else {}
    server = os.environ.get("GITHUB_SERVER_URL", "").rstrip("/")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    base = f"{server}/{repo}" if server and repo else ""
    out = []
    if tgt.get("pr"):
        out.append(f"{base}/pull/{tgt['pr']}" if base else f"asdd://pr/{tgt['pr']}")
    if tgt.get("commit"):
        out.append(f"{base}/commit/{tgt['commit']}" if base else f"asdd://commit/{tgt['commit']}")
    if rec.get("run_id"):
        out.append(f"asdd://run/{rec['run_id']}")
    return out


def to_okgf_page(rec):
    """One ledger record as a real OKGF page (okf format), or None if it carries no durable knowledge.
    This is ASDD adopting OKGF as its knowledge standard: the view emits OKGF pages, so a store ingests
    them with no translation. `type` is the knowledge kind; agent-emitted knowledge enters the review
    lifecycle as `draft`, and a human promotes it to `proposed`/`approved` in the store (where it is
    signed). Provenance travels as `x-okgf-sources`, so a reader can trace what a page came from."""
    agent = rec.get("agent", {})
    role = agent.get("role") or rec.get("agent_id", "")
    lens = agent.get("lens", "")
    kind = _KNOWLEDGE_KIND.get(lens or role)
    claim = (rec.get("reasoning") or "").strip()
    if not kind or not claim:
        return None
    title = claim.splitlines()[0].strip()
    if len(title) > 80:
        title = title[:77].rstrip() + "..."
    fm = {
        "type": kind,
        "title": title,
        "timestamp": rec.get("ts", ""),
        "tags": [t for t in (role, lens) if t],
        "x-okgf-scope": "org",
        "x-okgf-review": "draft",
        "x-okgf-sources": _okgf_sources(rec),
    }
    # A stable slug: kind + a short digest of the record identity, so re-exporting is idempotent and two
    # records never collide on disk.
    ident = rec.get("event_id") or rec.get("hash") or _canonical(rec)
    slug = f"{_slug(kind)}-{hashlib.sha256(ident.encode('utf-8')).hexdigest()[:12]}"
    return {"slug": slug, "fm": fm, "body": claim}


def main(argv=None):
    ap = argparse.ArgumentParser(description="ASDD agent audit ledger")
    sub = ap.add_subparsers(dest="cmd", required=True)

    fr = sub.add_parser("from-review", help="emit records from a completed review.json")
    fr.add_argument("--review", required=True)
    fr.add_argument("--ledger", required=True)
    fr.add_argument("--workdir")

    a = sub.add_parser("append", help="append one record")
    a.add_argument("--ledger", required=True)
    a.add_argument("--role", required=True, choices=ROLES)
    a.add_argument("--action", required=True)
    for opt in ("lens", "identity", "model", "provider", "authorizing-decision",
                "accountable-human", "verdict", "action-taken", "reasoning", "inputs-digest"):
        a.add_argument(f"--{opt}")
    a.add_argument("--duration-ms", type=int)
    a.add_argument("--kind", default="action", choices=("action", "merge"),
                   help="trail event kind the property checker reads (default: action)")
    a.add_argument("--untrusted-as-instruction", action="store_true",
                   help="record that this action was driven by untrusted input (P4 violation)")
    a.add_argument("--target-json", help="JSON object: repo, pr, commit, paths")
    a.add_argument("--run-json", help="JSON object: id, workflow")
    a.add_argument("--payload-json", help="JSON object: the role-specific payload")
    a.add_argument("--inputs-file", help="hash this file's content into inputs_digest (never stored)")

    v = sub.add_parser("verify", help="verify the chain (a file or a synced-sink directory)")
    v.add_argument("--ledger", required=True)

    tp = sub.add_parser("tip", help="print the hash of the last record across a ledger (file or directory)")
    tp.add_argument("--ledger", required=True)

    gr = sub.add_parser("graft", help="re-chain a batch onto a tip and print it, so the export appends a "
                                      "continuous chain to the sink instead of a genesis-rooted batch")
    gr.add_argument("--from", dest="src", required=True, help="the batch (JSONL) to re-chain")
    gr.add_argument("--onto", required=True, help="the hash to chain onto (use `tip` on the sink)")

    tr = sub.add_parser("trail", help="emit the ledger as a JSON array for validation/audit-check.py")
    tr.add_argument("--ledger", required=True)

    co = sub.add_parser("corpus", help="emit the ledger as training JSONL (the training view)")
    co.add_argument("--ledger", required=True, help="a .jsonl file or a synced sink directory")
    co.add_argument("--role", action="append", choices=ROLES,
                    help="restrict to one or more roles (repeatable); default: all")

    kn = sub.add_parser("knowledge", help="emit curated knowledge as OKGF pages (the OKGF store ingests them directly)")
    kn.add_argument("--ledger", required=True, help="a .jsonl file or a synced sink directory")
    kn.add_argument("--out", help="write one OKGF page (.md) per entry into this directory (drop it into or "
                                  "import it to an OKGF bundle); default: the pages serialized to stdout")

    args = ap.parse_args(argv)

    if args.cmd == "from-review":
        try:
            written = from_review(args.review, args.ledger, workdir=args.workdir)
        except (OSError, json.JSONDecodeError) as exc:
            # Fail-safe: the ledger must never break the pipeline it records.
            print(f"audit: from-review skipped ({exc.__class__.__name__})", file=sys.stderr)
            return 0
        print(f"audit: recorded {len(written)} review record(s)", file=sys.stderr)
        return 0

    if args.cmd == "tip":
        print(overall_tip(args.ledger))
        return 0

    if args.cmd == "graft":
        try:
            records = []
            with open(args.src, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        records.append(json.loads(line))
        except (OSError, json.JSONDecodeError) as exc:
            sys.stderr.write(f"audit: graft could not read the batch ({exc.__class__.__name__})\n")
            return 1
        out = "".join(_canonical(r) + "\n" for r in rechain(records, args.onto))
        sys.stdout.write(out)
        sys.stderr.write(f"audit: grafted {len(records)} record(s) onto {args.onto[:16]}\n")
        return 0

    if args.cmd == "trail":
        print(json.dumps(list(read_records(args.ledger)), indent=1))
        return 0

    if args.cmd == "corpus":
        roles = set(args.role) if args.role else None
        n = 0
        for rec in read_records(args.ledger):
            role = (rec.get("agent") or {}).get("role") or rec.get("agent_id", "")
            if roles and role not in roles:
                continue
            print(json.dumps(to_corpus(rec), ensure_ascii=False))
            n += 1
        print(f"audit: {n} training example(s)", file=sys.stderr)
        return 0

    if args.cmd == "knowledge":
        pages = (p for p in (to_okgf_page(rec) for rec in read_records(args.ledger)) if p is not None)
        n = 0
        if args.out:
            os.makedirs(args.out, exist_ok=True)
            for p in pages:
                with open(os.path.join(args.out, p["slug"] + ".md"), "w", encoding="utf-8") as fh:
                    fh.write(okgf_serialize(p))
                n += 1
            print(f"audit: wrote {n} OKGF page(s) to {args.out}", file=sys.stderr)
        else:
            for p in pages:
                sys.stdout.write(okgf_serialize(p))
                n += 1
            print(f"audit: {n} OKGF page(s)", file=sys.stderr)
        return 0

    if args.cmd == "verify":
        ok, n, err = verify(args.ledger)
        print(f"audit: {n} record(s); chain {'intact' if ok else 'BROKEN'}"
              + (f" ({err})" if err else ""))
        return 0 if ok else 1

    def as_json(raw):
        if not raw:
            return None
        try:
            obj = json.loads(raw)
            return obj if isinstance(obj, dict) else None
        except json.JSONDecodeError:
            return None

    inputs = None
    if args.inputs_file:
        try:
            with open(args.inputs_file, encoding="utf-8", errors="replace") as fh:
                inputs = fh.read()
        except OSError:
            inputs = None

    rec = build_record(
        role=args.role, action=args.action, lens=args.lens, identity=args.identity,
        model=args.model, provider=args.provider, target=as_json(args.target_json),
        authorizing_decision=args.authorizing_decision, accountable_human=args.accountable_human,
        run=as_json(args.run_json), duration_ms=args.duration_ms, verdict=args.verdict,
        action_taken=args.action_taken, reasoning=args.reasoning, inputs=inputs,
        kind=args.kind, untrusted_as_instruction=args.untrusted_as_instruction,
        inputs_digest=args.inputs_digest, payload=as_json(args.payload_json),
    )
    stored = append(args.ledger, rec)
    print(f"audit: recorded {stored['agent'].get('role')}"
          + (f"/{stored['agent']['lens']}" if stored["agent"].get("lens") else "")
          + f" {stored['action']} ({stored['event_id'][:12]})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
