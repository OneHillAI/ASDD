#!/usr/bin/env python3
"""asdd dashboard - a thin, read-only governance view for an ASDD project.

Curates the ASDD-specific governance state that GitHub's raw PR list does not:
pull requests bucketed by governance stage (awaiting review, in progress,
changes requested, merged), by lane; the `asdd/intake` and `asdd/review`
verdicts where the token can read them; the intake queue; contributors; and
releases. Renders one self-contained static HTML page (no external assets), so a
deployment regenerates it on a schedule. Read-only: it never writes to the repo. Zero-dependency (stdlib).

THE PAGE IS AS SENSITIVE AS THE REPO IT REPORTS ON, and it defaults to the careful reading.

INTERNAL by default. It lists project activity (PR titles, authors, verdicts, contributors) and the
active configuration. For a PRIVATE repo that is private activity: host it behind authentication, on an
internal host or as a private CI artifact, and never publish it.

PUBLIC repos are the narrow exception: every fact the page renders is already readable on GitHub by
anyone, so publishing adds no disclosure. Pass --public to render it for publication. That flag is
VERIFIED, not trusted: with --repo it asks the API and refuses if the repo is private, so the exception
cannot be taken by mistake. It drops the internal banner and lets the page be indexed.

With an activity log (the `insights.activity_log` the agents append to, see .asdd.yml), it also
surfaces agent activity and development insights: what each agent did, verdicts, and test/coverage
trends, so a developer can see what the agent system is doing and how the software is progressing.

It also snapshots the ACTIVE CONFIG (.asdd.yml): the steering that was in effect when the page was
generated, so a reviewer can see the conditions a change was reviewed under. Credential-shaped values
are redacted as a second line of defence, because a config should never carry one anyway.

    GITHUB_TOKEN=... python3 cli/dashboard.py --repo OWNER/REPO --out dashboard.html
    python3 cli/dashboard.py --from snapshot.json --out dashboard.html   # offline, from a saved snapshot
    python3 cli/dashboard.py --repo OWNER/REPO --json                    # the computed model, no HTML

A snapshot ({"repo","pulls","releases","statuses"}) is the raw GitHub shape, so
--from renders exactly what --repo would, without network access (used by the test).
"""
import argparse
import fnmatch
import hashlib
import html
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

API = "https://api.github.com"
LANES = ("feature", "fix", "docs", "chore")

# Paths whose content IS the standard: a change here is normative by definition. This mirrors the
# NORMATIVE_TEXT list the impact gate uses (.github/asdd/impact_scan.py), so the dashboard's declaration
# check agrees with the gate. Kept in sync deliberately; the two live in different runtimes (a stdlib,
# self-contained dashboard cannot import the CI script).
NORMATIVE_TEXT = ("STANDARD.md", "standards/**", "CONFORMANCE.md", "GOVERNANCE.md", "playbook/governance.md")


def _normative_paths(files):
    """The changed paths that are normative text, or None when the changed files are unknown."""
    if files is None:
        return None
    return sorted(f for f in files if any(fnmatch.fnmatch(f, g) for g in NORMATIVE_TEXT))


def _get(url, token):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "asdd-dashboard"}
    if token:
        headers["Authorization"] = f"token {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return json.load(r)


def fetch(repo, token, max_pulls=100):
    """Fetch the raw snapshot from the GitHub API. Degrades if a call is not permitted."""
    pulls = _get(f"{API}/repos/{repo}/pulls?state=all&per_page={max_pulls}&sort=updated&direction=desc", token)
    releases = []
    try:
        releases = _get(f"{API}/repos/{repo}/releases?per_page=20", token)
    except Exception:
        pass
    statuses = {}
    files = {}
    for p in pulls:
        if p.get("state") == "open" and not p.get("draft"):
            try:
                s = _get(f"{API}/repos/{repo}/commits/{p['head']['sha']}/status", token)
                statuses[str(p["number"])] = {c["context"]: c["state"] for c in s.get("statuses", [])}
            except Exception:
                pass  # the fine-grained token may not read statuses; the view degrades, it does not fail
        if p.get("state") == "open":
            try:
                # Changed paths, read-only, for the declaration check (declared scope vs paths touched).
                fl = _get(f"{API}/repos/{repo}/pulls/{p['number']}/files?per_page=100", token)
                files[str(p["number"])] = [f.get("filename", "") for f in fl]
            except Exception:
                pass  # unreadable files just skip the check for that PR; the rest of the view stands
    # Record visibility: --public is checked against this, so publication cannot be
    # asserted for a private repo. Unknown (None) is treated as private.
    private = None
    try:
        private = bool(_get(f"{API}/repos/{repo}", token).get("private"))
    except Exception:
        pass  # unreadable visibility stays unknown, which --public refuses
    return {"repo": repo, "pulls": pulls, "releases": releases, "statuses": statuses,
            "files": files, "private": private}


def lane_of(pr):
    labels = {l["name"] for l in pr.get("labels", [])}
    return next((lane for lane in LANES if lane in labels), None)


# The Change scope declaration and the target version, read from the PR body. Same rules as the
# reference impact lens (.github/asdd/impact_scan.py): HTML comments are stripped first so the PR
# template's own placeholder examples do not read as a real declaration or version. Best-effort and
# never raises: a body it cannot parse simply yields (None, None).
_TICKED = re.compile(r"\[[xX]\]")
_TARGET_VERSION = re.compile(r"(?i)\btarget version\b[^\n]*?\b(v?\d+\.\d+(?:\.\d+)?)\b")


def parse_impact(body):
    """Return (scope, version) from a PR body. scope in {normative, non-normative, ambiguous, None};
    version is a string like 'v0.2.0' or None."""
    try:
        text = re.sub(r"<!--.*?-->", " ", body or "", flags=re.DOTALL)
    except Exception:
        return None, None
    normative = non_normative = False
    for line in text.splitlines():
        if not _TICKED.search(line):
            continue
        low = line.lower()
        if "non-normative" in low or "non normative" in low:
            non_normative = True
        elif "normative" in low:
            normative = True
    if normative and non_normative:
        scope = "ambiguous"
    elif normative:
        scope = "normative"
    elif non_normative:
        scope = "non-normative"
    else:
        scope = None
    m = _TARGET_VERSION.search(text)
    version = m.group(1) if m else None
    return scope, version


def stage_of(pr, statuses):
    """The ASDD governance stage of a PR."""
    if pr.get("merged_at"):
        return "merged"
    if pr.get("state") == "closed":
        return "closed"
    if pr.get("draft"):
        return "in-progress"
    st = statuses.get(str(pr["number"]), {})
    intake, review = st.get("asdd/intake"), st.get("asdd/review")
    if intake in ("failure", "error") or review in ("failure", "error"):
        return "changes-requested"
    return "awaiting-review"


def _version_key(v):
    """Sort key for a 'vX.Y.Z' string; unparseable versions sort last."""
    nums = re.findall(r"\d+", v or "")
    return tuple(int(n) for n in nums) if nums else (9999,)


def next_release(open_rows):
    """Group the open PRs that declare a target version, by version, as a SUGGESTION for the maintainer
    to review and confirm. Read-only: this proposes a grouping, it does not assign one. PRs that declare
    a normative change with no target version are listed separately as needing one."""
    buckets = {}
    needs_version = []
    for r in open_rows:
        if r.get("version"):
            buckets.setdefault(r["version"], []).append(r)
        elif r.get("scope") == "normative":
            needs_version.append(r)
    versions = [
        {"version": v, "prs": sorted(buckets[v], key=lambda r: r["number"])}
        for v in sorted(buckets, key=_version_key)
    ]
    return {"versions": versions, "needs_version": sorted(needs_version, key=lambda r: r["number"])}


def model(snap):
    """Compute the governance model from a raw snapshot."""
    stages = {k: [] for k in ("awaiting-review", "in-progress", "changes-requested", "merged", "closed")}
    contributors = {}
    for pr in snap["pulls"]:
        stage = stage_of(pr, snap.get("statuses", {}))
        st = snap.get("statuses", {}).get(str(pr["number"]), {})
        scope, version = parse_impact(pr.get("body"))
        norm_paths = _normative_paths(snap.get("files", {}).get(str(pr["number"])))
        # Declaration check: does the declared scope match the paths the PR changes? A PR declared
        # non-normative that edits the standard's normative text is the mismatch the impact gate blocks;
        # surfacing it here mirrors the gate's own normative-path rule. Unknown files -> no check.
        if norm_paths is None or scope is None:
            scope_check = None
        elif scope == "non-normative" and norm_paths:
            scope_check = "mismatch"
        else:
            scope_check = "ok"
        row = {
            "number": pr["number"], "title": pr["title"], "author": (pr.get("user") or {}).get("login", "?"),
            "lane": lane_of(pr), "stage": stage, "draft": bool(pr.get("draft")),
            "url": pr.get("html_url", ""), "updated": pr.get("updated_at", ""),
            "intake": st.get("asdd/intake"), "review": st.get("asdd/review"),
            "scope": scope, "version": version,
            "scope_check": scope_check, "normative_paths": norm_paths or [],
        }
        stages[stage].append(row)
        author = row["author"]
        contributors[author] = contributors.get(author, 0) + 1
    open_rows = stages["awaiting-review"] + stages["changes-requested"] + stages["in-progress"]
    discrepancies = sorted((r for r in open_rows if r.get("scope_check") == "mismatch"),
                           key=lambda r: r["number"])
    return {
        "repo": snap["repo"],
        "stages": stages,
        "counts": {k: len(v) for k, v in stages.items()},
        "open": len(stages["awaiting-review"]) + len(stages["in-progress"]) + len(stages["changes-requested"]),
        "next_release": next_release(open_rows),
        "discrepancies": discrepancies,
        "contributors": sorted(contributors.items(), key=lambda kv: -kv[1]),
        "releases": [{"tag": r.get("tag_name", ""), "name": r.get("name", ""), "url": r.get("html_url", ""),
                      "at": r.get("published_at", "")} for r in snap.get("releases", [])],
        "intake_queue": snap.get("intake_queue", []),
        "ledger": snap.get("ledger") or {},
        "config": snap.get("config") or {},
        # None = unknown, which --public refuses. Only an explicit False permits publication.
        "private": snap.get("private"),
    }


def read_intake(directory):
    """Optional: the local intake queue (*.json spec/intake objects the pipeline wrote)."""
    if not directory or not os.path.isdir(directory):
        return []
    out = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".json"):
            try:
                obj = json.load(open(os.path.join(directory, name), encoding="utf-8"))
                out.append({"id": name[:-5], "title": obj.get("title") or obj.get("summary") or name,
                            "ready": obj.get("ready")})
            except Exception:
                out.append({"id": name[:-5], "title": name, "ready": None})
    return out


def read_ledger(path, limit=25):
    """Optional: the agent audit ledger (append-only JSONL, STANDARD 1.3).

    Aggregates what each agent role did, and verifies the hash chain so a tampered or truncated trail is
    visible rather than silently rendered as fact. Records hold digests, not reviewed content, so nothing
    sensitive is introduced by rendering them."""
    if not path or not os.path.exists(path):
        return {}
    # The export writes the sink as ledger/<year>/<month>.jsonl, so an accumulated ledger is a DIRECTORY
    # of monthly files, not one file. Accept either. Sorted order keeps the hash chain continuous across
    # months and years, because the paths are zero-padded.
    if os.path.isdir(path):
        files = sorted(os.path.join(r, f) for r, _d, fs in os.walk(path)
                       for f in fs if f.endswith(".jsonl"))
    else:
        files = [path]
    if not files:
        return {"total": 0, "chain_intact": True, "roles": [], "recent": [], "sources": 0, "empty": True}
    roles, recent, total = {}, [], 0
    prev, intact = "sha256:genesis", True
    try:
        for _f in files:
          with open(_f, encoding="utf-8") as fh:
              for line in fh:
                  line = line.strip()
                  if not line:
                      continue
                  try:
                      rec = json.loads(line)
                  except json.JSONDecodeError:
                      intact = False
                      continue
                  # Chain check, mirroring cli/audit.py: the link must match AND the record's own hash must
                  # still match its content, or an edit to a single (or the last) record would go unseen.
                  if rec.get("prev") != prev:
                      intact = False
                  body = {k: v for k, v in rec.items() if k not in ("hash", "event_id")}
                  canon = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                  if rec.get("hash") != "sha256:" + hashlib.sha256(canon.encode("utf-8", "replace")).hexdigest():
                      intact = False
                  prev = rec.get("hash") or prev
                  total += 1
                  agent = rec.get("agent") or {}
                  role = agent.get("role") or "unknown"
                  r = roles.setdefault(role, {"role": role, "count": 0, "verdicts": {}, "lenses": set()})
                  r["count"] += 1
                  if agent.get("lens"):
                      r["lenses"].add(agent["lens"])
                  v = (rec.get("outcome") or {}).get("verdict")
                  if v:
                      r["verdicts"][v] = r["verdicts"].get(v, 0) + 1
                  recent.append({
                      "ts": rec.get("ts", ""), "role": role, "lens": agent.get("lens"),
                      "action": rec.get("action", ""),
                      "verdict": v, "action_taken": (rec.get("outcome") or {}).get("action_taken"),
                      "reasoning": rec.get("reasoning", ""),
                  })
    except OSError:
        return {}
    for r in roles.values():
        r["lenses"] = sorted(r["lenses"])
    return {"total": total, "chain_intact": intact, "sources": len(files),
            "empty": total == 0,
            "roles": sorted(roles.values(), key=lambda r: -r["count"]),
            "recent": list(reversed(recent))[:limit]}


# --- active config ---------------------------------------------------------

_SECRET_KEY = ("key", "token", "secret", "password", "credential")
_SECRET_VAL = ("sk-", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_", "xoxb-", "xoxp-",
               "xoxa-", "xoxr-", "xoxs-", "AKIA", "glpat-")


def _redact(key, value):
    """Never render a credential, even if one was misfiled into .asdd.yml (model NAMES
    belong there; keys do not). Defence in depth: the page is internal, but a leaked
    key would outlive the page."""
    if not isinstance(value, str) or not value:
        return value
    if any(t in key.lower() for t in _SECRET_KEY):
        return "[redacted]"
    if any(value.startswith(p) for p in _SECRET_VAL):
        return "[redacted]"
    return value


def _yaml_lite(text):
    """A tiny reader for the .asdd.yml subset: top-level scalars, top-level lists,
    one level of nesting, and lists under a nested key. Not a general YAML parser;
    shapes it does not know are skipped rather than guessed at."""
    def strip_comment(line):
        out, q = [], None
        for ch in line:
            if q:
                out.append(ch)
                if ch == q:
                    q = None
            elif ch in "\"'":
                q = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
        return "".join(out).rstrip()

    def scalar(v):
        v = v.strip()
        if not v:
            return ""
        if len(v) > 1 and v[0] in "\"'" and v[-1] == v[0]:
            return v[1:-1]
        low = v.lower()
        if low in ("true", "false"):
            return low == "true"
        if low in ("null", "~"):
            return None
        try:
            return int(v)
        except ValueError:
            return v

    root, top, child = {}, None, None
    for raw in text.split("\n"):
        line = strip_comment(raw)
        if not line.strip():
            continue
        ind = len(line) - len(line.lstrip())
        body = line.strip()
        if ind == 0:
            child = None
            if body.endswith(":"):
                top = body[:-1].strip()
                root.setdefault(top, None)
            elif ":" in body:
                k, v = body.split(":", 1)
                root[k.strip()] = _redact(k.strip(), scalar(v))
                top = None
        elif top:
            if body.startswith("- "):
                item = scalar(body[2:])
                if child:
                    if not isinstance(root[top].get(child), list):
                        root[top][child] = []
                    root[top][child].append(item)
                else:
                    if not isinstance(root.get(top), list):
                        root[top] = []
                    root[top].append(item)
            elif ":" in body:
                k, v = body.split(":", 1)
                k, v = k.strip(), v.strip()
                if not isinstance(root.get(top), dict):
                    root[top] = {}
                if v == "":
                    child = k
                    root[top].setdefault(k, [])
                else:
                    root[top][k] = _redact(k, scalar(v))
                    child = None
    return root


def read_config(path):
    """Optional: the active .asdd.yml, the steering in effect at generation time."""
    if not path or not os.path.isfile(path):
        return {}
    try:
        return _yaml_lite(open(path, encoding="utf-8").read())
    except Exception:
        return {}


# --- rendering -------------------------------------------------------------

STAGE_LABEL = {"awaiting-review": "Awaiting review", "in-progress": "In progress",
               "changes-requested": "Changes requested", "merged": "Recently merged", "closed": "Closed"}
_CSS_FALLBACK = (
    ":root{--bg:#fff;--fg:#1a1a1a;--mut:#666;--line:#e5e5e5;--card:#f7f7f5;--accent:#b45309}"
    "body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif}"
    ".wrap{max-width:1000px;margin:0 auto;padding:2rem 1.25rem}"
    "table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:.45rem .5rem;border-bottom:1px solid var(--line)}"
    ".banner{background:#fef3c7;border:1px solid #f59e0b;color:#78350f;padding:.6rem .85rem;border-radius:8px;margin:1rem 0}"
)


def load_css():
    """The shared stylesheet (cli/dashboard.css), inlined so the page stays self-contained.
    The operate kit's setup dashboard reads the same file, so both surfaces match."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dashboard.css")
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return _CSS_FALLBACK  # never render naked if the stylesheet is missing




def _verdict(v):
    if v is None:
        return '<span class="v-none">-</span>'
    ok = v in ("success",)
    cls = "v-ok" if ok else ("v-bad" if v in ("failure", "error") else "v-none")
    return f'<span class="{cls}">{html.escape(v)}</span>'


def _safe_url(u):
    """Only ever emit an http(s) link: a crafted snapshot must not inject a javascript: href."""
    u = (u or "").strip()
    return u if u.lower().startswith(("https://", "http://")) else ""


def _target_cell(r):
    """The release-target cell: the declared version, a scope mismatch, or a normative PR needing one."""
    ver, scope = r.get("version"), r.get("scope")
    if r.get("scope_check") == "mismatch":
        return '<span class="v-bad">scope mismatch</span>'
    if ver:
        cell = html.escape(ver)
        if scope == "normative":
            cell += ' <span class="tag">normative</span>'
        return cell
    if scope == "normative":
        return '<span class="v-bad">needs version</span>'
    return '<span class="v-none">-</span>'


def _ledger_html(led):
    """Per-role agent activity from the audit ledger, plus the chain state."""
    if not led:
        return ('<p class="empty">No audit ledger loaded. Pass --ledger PATH: a .jsonl file, or a directory '
                'of them if you have synced the sink (see the <code>audit:</code> block in .asdd.yml).</p>')
    if led.get("empty"):
        # A path that exists but yields nothing is a real condition, not "no ledger". Saying so beats
        # rendering an empty table that reads as "the agents did nothing".
        return ('<div class="banner">The ledger path was read but contains no records. If you pointed at a '
                'synced sink, check that it holds <code>*.jsonl</code> files and that the export has run.'
                '</div>')
    warn = ""
    if not led.get("chain_intact", True):
        warn = ('<div class="banner">The ledger hash chain does NOT verify: a record was altered, removed, '
                'or is unreadable. Treat the trail below as untrustworthy until reconciled.</div>')
    rows = ""
    for r in led.get("roles", []):
        verdicts = ", ".join(f"{html.escape(k)} {v}" for k, v in sorted(r["verdicts"].items())) or "-"
        lenses = ", ".join(html.escape(x) for x in r.get("lenses", [])) or "-"
        rows += (f'<tr><td>{html.escape(r["role"])}</td><td>{r["count"]}</td>'
                 f'<td>{lenses}</td><td>{verdicts}</td></tr>')
    table = ('<div class="overflow"><table><tr><th>role</th><th>actions</th><th>lenses</th>'
             f'<th>verdicts</th></tr>{rows}</table></div>')
    recent = ""
    for e in led.get("recent", []):
        who = html.escape(e["role"]) + (f'/{html.escape(e["lens"])}' if e.get("lens") else "")
        why = html.escape((e.get("reasoning") or "")[:160])
        recent += (f'<tr><td>{html.escape(e["ts"][:19])}</td><td>{who}</td>'
                   f'<td>{html.escape(e["action"])}</td><td>{html.escape(e.get("verdict") or "-")}</td>'
                   f'<td>{html.escape(e.get("action_taken") or "-")}</td><td>{why}</td></tr>')
    recent_tbl = ('<h3 style="font-size:1rem;margin:1.1rem 0 .3rem">Most recent</h3>'
                  '<div class="overflow"><table><tr><th>when</th><th>agent</th><th>action</th>'
                  f'<th>verdict</th><th>led to</th><th>why</th></tr>{recent}</table></div>') if recent else ""
    return (warn + f'<p class="sub">{led.get("total", 0)} recorded action(s); chain '
            + ("intact" if led.get("chain_intact", True) else "BROKEN") + ".</p>" + table + recent_tbl)


def _discrepancies_html(disc):
    """Open PRs whose declared scope does not match the paths they change. The impact gate blocks these;
    this lists them so a reviewer sees the misclassification at a glance."""
    if not disc:
        return ('<p class="empty">None. Every open PR that changes the standard\'s normative text is '
                'declared normative.</p>')
    body = ""
    for r in disc:
        safe = _safe_url(r["url"])
        title = (f'<a href="{html.escape(safe)}">{html.escape(r["title"])}</a>' if safe
                 else html.escape(r["title"]))
        paths = ", ".join(html.escape(p) for p in r.get("normative_paths", [])) or "normative text"
        body += (f'<tr><td>{html.escape(str(r["number"]))}</td><td>{title}</td>'
                 f'<td><span class="v-bad">non-normative</span></td><td>{paths}</td></tr>')
    return ('<p class="sub">These open PRs are declared non-normative but change the standard\'s '
            'normative text. The impact gate blocks them until the declaration is fixed; they are listed '
            'here so the misclassification is visible.</p>'
            '<div class="overflow"><table><tr><th>#</th><th>Title</th><th>declared</th>'
            f'<th>changes normative text</th></tr>{body}</table></div>')


def _pr_table(rows):
    if not rows:
        return '<p class="empty">None.</p>'
    head = ("<tr><th>#</th><th>Title</th><th>Lane</th><th>Target</th><th>Author</th>"
            "<th>intake</th><th>review</th></tr>")
    body = ""
    for r in rows:
        lane = f'<span class="tag">{html.escape(r["lane"])}</span>' if r["lane"] else '<span class="v-none">-</span>'
        safe = _safe_url(r["url"])
        title = (f'<a href="{html.escape(safe)}">{html.escape(r["title"])}</a>' if safe
                 else html.escape(r["title"]))
        body += (f'<tr><td>{html.escape(str(r["number"]))}</td><td>{title}</td><td>{lane}</td>'
                 f'<td>{_target_cell(r)}</td>'
                 f'<td>{html.escape(r["author"])}</td><td>{_verdict(r["intake"])}</td>'
                 f'<td>{_verdict(r["review"])}</td></tr>')
    return f'<div class="overflow"><table>{head}{body}</table></div>'


def _release_group_table(rows):
    """A compact PR list inside a suggested-release bucket: number, title, scope, lane."""
    body = ""
    for r in rows:
        safe = _safe_url(r["url"])
        title = (f'<a href="{html.escape(safe)}">{html.escape(r["title"])}</a>' if safe
                 else html.escape(r["title"]))
        scope = html.escape(r.get("scope") or "-")
        lane = html.escape(r.get("lane") or "-")
        body += (f'<tr><td>{html.escape(str(r["number"]))}</td><td>{title}</td>'
                 f'<td>{scope}</td><td>{lane}</td></tr>')
    return ('<div class="overflow"><table><tr><th>#</th><th>Title</th><th>scope</th><th>lane</th></tr>'
            f'{body}</table></div>')


def _next_release_html(nr):
    """The suggested next-release grouping: a proposal the maintainer reviews and confirms."""
    versions, needs = nr.get("versions", []), nr.get("needs_version", [])
    if not versions and not needs:
        return '<p class="empty">No open pull request declares a target version yet.</p>'
    parts = ['<p class="sub">A suggested grouping for a maintainer to review and confirm. Advisory: '
             'nothing here assigns a version, tags a release, edits the changelog, or merges. Grouping a '
             'release is a human act (a maintainer now; an assistant may suggest one later).</p>']
    for grp in versions:
        parts.append(f'<h3 style="font-size:1rem;margin:1.1rem 0 .3rem">{html.escape(grp["version"])} '
                     f'<span class="sub">{len(grp["prs"])} PR(s)</span></h3>')
        parts.append(_release_group_table(grp["prs"]))
    if needs:
        parts.append('<h3 style="font-size:1rem;margin:1.1rem 0 .3rem">No target version</h3>')
        parts.append('<p class="sub">These open PRs declare a normative change but name no target '
                     'version. They need one before they can be grouped into a release.</p>')
        parts.append(_release_group_table(needs))
    return "".join(parts)


def _public_ledger_html(led):
    """The PUBLIC projection of the ledger: aggregate counts only, whitelisted BY CONSTRUCTION. It reads
    only the per-role counts, the verdict distribution and the lens names, plus the totals and chain
    state. It never reads the per-record reasoning, payload, target, or any free text, so a field added
    to a record later cannot leak here: this renders named aggregates, not filtered records. This is what
    makes the ledger publishable, showing throughput and verdict mix without disclosing what any single
    record said."""
    if not led or led.get("empty"):
        return '<p class="empty">No agent activity recorded yet.</p>'
    warn = ""
    if not led.get("chain_intact", True):
        warn = ('<div class="banner">The ledger hash chain does not verify; these counts may be '
                'incomplete.</div>')
    rows = ""
    for r in led.get("roles", []):
        verdicts = ", ".join(f"{html.escape(k)} {v}" for k, v in sorted(r["verdicts"].items())) or "-"
        lenses = ", ".join(html.escape(x) for x in r.get("lenses", [])) or "-"
        rows += (f'<tr><td>{html.escape(r["role"])}</td><td>{r["count"]}</td>'
                 f'<td>{lenses}</td><td>{verdicts}</td></tr>')
    table = ('<div class="overflow"><table><tr><th>role</th><th>actions</th><th>lenses</th>'
             f'<th>verdicts</th></tr>{rows}</table></div>')
    return (warn + f'<p class="sub">{led.get("total", 0)} recorded action(s) across '
            f'{len(led.get("roles", []))} role(s); chain '
            + ("intact" if led.get("chain_intact", True) else "BROKEN")
            + '. Aggregate counts only: no per-record reasoning, content, or paths are shown.</p>' + table)


def render(m, generated_at, public=False, public_metrics=False):
    c = m["counts"]
    tiles = [("Open", m["open"]), ("Awaiting review", c["awaiting-review"]),
             ("Changes requested", c["changes-requested"]), ("In progress", c["in-progress"]),
             ("Merged (recent)", c["merged"])]
    parts = [f'<div class="wrap"><h1>ASDD governance: {html.escape(m["repo"])}</h1>',
             '<p class="sub">Read-only. Curated from the GitHub API and ASDD artifacts. Advisory: nothing here merges or acts.</p>',
             (('<div class="banner">Public render. The reported repository is verified public, so the pull '
               'requests, verdicts and releases shown here are already readable on GitHub. The agent '
               'activity below is shown as aggregate counts only, no per-record content.</div>'
               if public_metrics else
               '<div class="banner">Public render. The reported repository is verified public, so the pull '
               'requests, verdicts and releases shown here are already readable on GitHub. Rendered with no '
               'out-of-band source: no audit ledger and no local intake queue.</div>') if public else
              '<div class="banner">Internal. This page lists private project activity and the active '
              'configuration. Host it behind authentication. Do not publish it to a public URL or commit '
              'it to a public repo.</div>'),
             '<div class="tiles">']
    for label, n in tiles:
        parts.append(f'<div class="tile"><div class="n">{n}</div><div class="l">{label}</div></div>')
    parts.append("</div>")
    for stage in ("awaiting-review", "changes-requested", "in-progress"):
        parts.append(f'<h2>{STAGE_LABEL[stage]}</h2>{_pr_table(m["stages"][stage])}')
    merged = m["stages"]["merged"]
    note = f' <span class="sub">showing 12 of {len(merged)}</span>' if len(merged) > 12 else ""
    parts.append(f'<h2>{STAGE_LABEL["merged"]}{note}</h2>{_pr_table(merged[:12])}')
    # intake queue
    parts.append("<h2>Intake queue</h2>")
    if m["intake_queue"]:
        rows = "".join(f'<tr><td>{html.escape(str(i["id"]))}</td><td>{html.escape(str(i["title"]))}</td>'
                       f'<td>{_verdict("success" if i.get("ready") else None) if i.get("ready") is not None else "-"}</td></tr>'
                       for i in m["intake_queue"])
        parts.append(f'<div class="overflow"><table><tr><th>id</th><th>title</th><th>ready</th></tr>{rows}</table></div>')
    else:
        parts.append('<p class="empty">No local intake queue (pass --intake DIR if the pipeline writes one).</p>')
    # active config: the steering in effect when this was generated
    parts.append("<h2>Active configuration</h2>")
    cfg = m.get("config") or {}
    if cfg:
        parts.append('<p class="sub">The steering in effect when this page was generated, read from '
                     '<code>.asdd.yml</code>. Change it through the CLI or a coding agent, as a pull request; '
                     'this view is read-only. Credential-shaped values are redacted.</p>')
        facts = [("standard", cfg.get("standard_version")), ("runtime", cfg.get("runtime")),
                 ("merge posture", cfg.get("merge_posture")),
                 ("spec context", (cfg.get("intake") or {}).get("spec_context")),
                 ("lanes", ", ".join(cfg["lanes"]) if isinstance(cfg.get("lanes"), list) else None),
                 ("protected paths", len(cfg["protected_paths"]) if isinstance(cfg.get("protected_paths"), list) else None),
                 ("merge reviewer", (cfg.get("merge_reviewer") or {}).get("enabled")),
                 ("insights", (cfg.get("insights") or {}).get("enabled"))]
        def fmt(v):
            return ("enabled" if v else "disabled") if isinstance(v, bool) else str(v)
        rows = "".join(f'<tr><td>{html.escape(k)}</td><td>{html.escape(fmt(v))}</td></tr>'
                       for k, v in facts if v is not None and v != "")
        parts.append(f'<div class="overflow"><table><tr><th>setting</th><th>value</th></tr>{rows}</table></div>')
        models = cfg.get("models") if isinstance(cfg.get("models"), dict) else {}
        if models:
            notset = '<span class="v-none">not set</span>'
            mrows = "".join("<tr><td>" + html.escape(r) + "</td><td>"
                            + (html.escape(str(v)) if v else notset) + "</td></tr>"
                            for r, v in models.items())
            parts.append('<h2 style="font-size:.95rem;border:0;margin:1rem 0 .3rem">Model per role</h2>'
                         f'<div class="overflow"><table><tr><th>role</th><th>model</th></tr>{mrows}</table></div>')
    else:
        parts.append('<p class="empty">No .asdd.yml found (pass --config PATH to snapshot the active steering).</p>')
    # contributors + releases
    parts.append("<h2>Contributors</h2>")
    if m["contributors"]:
        parts.append('<p>' + ", ".join(f'{html.escape(a)} <span class="tag">{n}</span>' for a, n in m["contributors"]) + '</p>')
    else:
        parts.append('<p class="empty">None.</p>')
    parts.append("<h2>Agent activity (audit ledger)</h2>")
    # A public page shows only the whitelisted aggregate projection; the internal page shows the full
    # detail (which includes per-record reasoning). The choice is by page kind, not by filtering.
    parts.append(_public_ledger_html(m.get("ledger") or {}) if (public and public_metrics)
                 else _ledger_html(m.get("ledger") or {}))
    parts.append("<h2>Declaration check</h2>")
    parts.append(_discrepancies_html(m.get("discrepancies") or []))
    parts.append("<h2>Suggested next release</h2>")
    parts.append(_next_release_html(m.get("next_release") or {"versions": [], "needs_version": []}))
    parts.append("<h2>Releases</h2>")
    if m["releases"]:
        rows = "".join(f'<tr><td><a href="{html.escape(r["url"])}">{html.escape(r["tag"])}</a></td>'
                       f'<td>{html.escape(r["name"] or "")}</td><td>{html.escape((r["at"] or "")[:10])}</td></tr>'
                       for r in m["releases"])
        parts.append(f'<div class="overflow"><table><tr><th>tag</th><th>name</th><th>date</th></tr>{rows}</table></div>')
    else:
        parts.append('<p class="empty">None.</p>')
    foot = ('Regenerate on a schedule. This reports a public repository, so the page is publishable.'
            if public else
            'Regenerate on a schedule. Internal: serve it behind authentication, never from a public URL.')
    parts.append(f'<footer>Generated {html.escape(generated_at)} by <code>asdd dashboard</code>. '
                 f'{foot}</footer></div>')
    # An internal page must not be indexed if it is ever exposed by accident. A public demo is meant
    # to be found, so suppressing it there would defeat the point.
    robots = ("" if public else
              '<meta name="robots" content="noindex,nofollow,noarchive">'
              '<meta name="referrer" content="no-referrer">')
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'{robots}'
            f'<title>ASDD governance: {html.escape(m["repo"])}</title><style>{load_css()}</style></head>'
            f'<body>{"".join(parts)}</body></html>')


def main():
    ap = argparse.ArgumentParser(description="ASDD read-only governance dashboard")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--repo", help="OWNER/REPO to fetch live (uses GITHUB_TOKEN)")
    src.add_argument("--from", dest="snapshot", help="a saved snapshot JSON to render offline")
    ap.add_argument("--out", help="write HTML here (default stdout)")
    ap.add_argument("--intake", help="a local intake-queue directory (*.json) to include")
    ap.add_argument("--ledger", help="the agent audit ledger to summarise: a .jsonl file, or a directory of them (a synced sink)")
    ap.add_argument("--config", default=".asdd.yml",
                    help="the .asdd.yml to snapshot as the active steering (default: .asdd.yml)")
    ap.add_argument("--json", action="store_true", help="print the computed model as JSON, no HTML")
    ap.add_argument("--public", action="store_true",
                    help="render for publication (a PUBLIC repo only: drops the internal banner and "
                         "allows indexing). Verified against the repo's visibility; refused otherwise.")
    ap.add_argument("--public-metrics", action="store_true",
                    help="with --public and a ledger, publish the ledger as AGGREGATE COUNTS ONLY (per-role "
                         "counts, verdict mix, chain state). Never per-record reasoning, content, or paths. "
                         "This is the only way a ledger reaches a public page, and it is opt-in on purpose.")
    a = ap.parse_args()

    if a.repo:
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("ASDD_DASHBOARD_TOKEN") or ""
        snap = fetch(a.repo, token)
    else:
        snap = json.load(open(a.snapshot, encoding="utf-8"))
    if a.intake:
        snap["intake_queue"] = read_intake(a.intake)
    if a.ledger:
        snap["ledger"] = read_ledger(a.ledger)
    if "config" not in snap:
        snap["config"] = read_config(a.config)

    m = model(snap)

    # --public is a control, not a promise. The whole point of the internal posture is that a tired
    # admin should not be able to publish private activity by ticking a box, so this refuses unless the
    # repo is verifiably public. Unknown visibility (an unreadable API, or a snapshot that predates
    # this) is treated as private.
    # A public render is only safe when EVERY fact on the page is already public on GitHub. The repo's
    # visibility says nothing about sources supplied out of band: the audit ledger comes from a sink that
    # is REQUIRED to be private (the export refuses a public destination), and a local intake queue is not
    # on the repo either. Their sensitivity is independent of the reported repo's, so the visibility check
    # cannot speak for them. Refuse rather than publish, at the flag, so an empty source cannot unlock it.
    # A local intake queue has no public projection, so it always refuses under --public.
    if a.public and a.intake:
        sys.stderr.write(
            "dashboard: refusing --public because a local intake queue is loaded.\n"
            "It is not on the reported repository, so the repository being public says nothing about "
            "whether it may be published. Render the internal page, or drop --intake.\n")
        return 2
    # A ledger reaches a public page ONLY as the opt-in aggregate projection. Without --public-metrics it
    # refuses, so the full detail (which includes per-record reasoning) can never be published by mistake.
    if a.public and a.ledger and not a.public_metrics:
        sys.stderr.write(
            "dashboard: refusing --public with a ledger unless --public-metrics is set.\n"
            "The full ledger view includes per-record reasoning and must stay internal. Add "
            "--public-metrics to publish AGGREGATE COUNTS ONLY (per-role counts and verdict mix, no "
            "per-record content), or drop --ledger.\n")
        return 2

    if a.public and m.get("private") is not False:
        why = ("the repo is private" if m.get("private") else
               "its visibility could not be verified (fetch with --repo, or use a snapshot that records it)")
        sys.stderr.write(
            f"dashboard: refusing --public for {m['repo']}: {why}.\n"
            "A public render drops the internal banner and allows indexing, so it is only safe when "
            "every fact on the page is already public on GitHub. Render without --public for the "
            "internal page.\n")
        return 2

    if a.json:
        sys.stdout.write(json.dumps(m, indent=2) + "\n")
        return 0
    out_html = render(m, datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
                      public=a.public, public_metrics=a.public_metrics)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(out_html)
        sys.stderr.write(f"wrote {a.out} ({m['open']} open, {m['counts']['merged']} recently merged)\n")
    else:
        sys.stdout.write(out_html)
    return 0


if __name__ == "__main__":
    sys.exit(main())
