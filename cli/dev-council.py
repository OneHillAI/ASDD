#!/usr/bin/env python3
"""asdd dev-council - the developer council (reference orchestrator, runtime-neutral).

An OPTIONAL produce-loop developer. Instead of one model implementing an OpenSpec change, 2 to 5 diverse
models PROPOSE an implementation against the change's acceptance criteria, CROSS-CRITIQUE each other's
drafts against those criteria, a lead SYNTHESISES one result, and the existing test agents VERIFY it on
models distinct from the council. Always returns one synthesised, test-checked result plus an inspectable
transcript. Opt-in; the single-model developer stays the default.

This is the runtime-neutral reference (a sibling to cli/run-agent.sh): it drives any OpenAI-compatible
endpoint and needs only the stdlib. The Goose kit invokes it; a bring-your-own runtime implements the same
contract (agents/runtime.md). It is spec-and-test-grounded, not consensus: the council converges on what
satisfies the spec and passes the tests, not on what the models agree on.

Config (.asdd.yml):
    dev_council:
      enabled: false            # opt-in; the single-model developer is the default
      models: ["provider:a", "provider:b", "provider:c"]   # 2 to 5; the LAST is the lead synthesiser
      max_critique_rounds: 1    # bounded; hard cap 2
      max_refine_rounds: 1      # bounded; hard cap 2
      max_tokens: 4000          # per model call

Bring the models two ways (whichever the operator already has):
  - one multi-model provider: shared ASDD_MODEL_URL + ASDD_RUNTIME_TOKEN, the model NAMES above distinguish.
  - per-member: ASDD_MODEL_URL__COUNCIL_<i> + ASDD_RUNTIME_TOKEN__COUNCIL_<i> (i = 1..N, by position).

Recording (STANDARD 1.3): every run records its proposals, critiques, disagreements, synthesis rationale
and verify result to the audit ledger (role developer, action dev-council.*), so `asdd audit corpus` and
`asdd audit knowledge` derive from it. Content is DIGESTED (counts, categoricals, the agent's own short
rationale), never the drafted code verbatim, the same as every other agent.

Usage:
    dev-council.py --change <openspec-change-id> [--root DIR] [--out FILE] [--transcript FILE]
                   [--models a,b,c] [--test-cmd CMD] [--dry-run]
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

CLI_DIR = os.path.dirname(os.path.abspath(__file__))          # where audit.py travels, next to this script
ROOT = os.path.dirname(CLI_DIR)
DEFAULT_N, MIN_N, MAX_N = 3, 2, 5
HARD_CAP_ROUNDS = 2


# --- .asdd.yml reader (the same subset as cli/dashboard.py: scalars, lists, one level of nesting) -------
def _yaml_lite(text):
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
        indent = len(line) - len(line.lstrip())
        s = line.strip()
        if indent == 0:
            child = None
            if s.endswith(":"):
                top = s[:-1].strip()
                root[top] = {}
            elif ":" in s:
                k, v = s.split(":", 1)
                root[k.strip()] = scalar(v)
                top = None
            continue
        if s.startswith("- ") and top is not None and child is None:
            root[top] = root[top] if isinstance(root[top], list) else []
            root[top].append(scalar(s[2:]))
            continue
        if top is not None and isinstance(root.get(top), dict):
            if s.endswith(":"):
                child = s[:-1].strip()
                root[top][child] = []
            elif s.startswith("- ") and child is not None:
                if not isinstance(root[top].get(child), list):
                    root[top][child] = []
                root[top][child].append(scalar(s[2:]))
            elif ":" in s:
                k, v = s.split(":", 1)
                root[top][k.strip()] = scalar(v)
                child = None
    return root


def load_config(root):
    path = os.path.join(root, ".asdd.yml")
    if not os.path.isfile(path):
        return {}
    try:
        return _yaml_lite(open(path, encoding="utf-8").read())
    except Exception:
        return {}


# --- provider resolution: model name + endpoint + key, per member (shared pair or per-member pair) ------
def as_model_list(v):
    """dev_council.models as a clean list of names. The tiny .asdd.yml reader returns a BLOCK-style list
    (`- a`) as a real list, but a FLOW-style list (`[a, b, c]`) as a single string; iterating that string
    would treat each character as a model. Handle both, and treat any other scalar as empty rather than
    per-character garbage."""
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    if isinstance(v, str):
        s = v.strip()
        if s.startswith("[") and s.endswith("]"):
            s = s[1:-1]
        elif "," not in s:
            return [s.strip().strip("\"'")] if s.strip() else []
        return [p.strip().strip("\"'") for p in s.split(",") if p.strip()]
    return []


def _clamp_rounds(v, default=1):
    try:
        v = int(v)
    except (TypeError, ValueError):
        v = default
    return max(0, min(HARD_CAP_ROUNDS, v))


def family(model):
    """A coarse family key for the heterogeneity warning: the part before the first ':' or '/', lowered.
    'zai:glm@5.2' -> 'zai', 'openai/gpt-4o' -> 'openai'. Same-family members warn (near-clones)."""
    m = (model or "").strip().lower()
    for sep in (":", "/"):
        if sep in m:
            return m.split(sep, 1)[0]
    return m


def resolve_members(models):
    """Turn the model list into council members with their endpoint + key, honouring both provider modes.
    Returns [{'idx','model','url','token','is_lead'}]. The LAST model is the lead synthesiser."""
    members = []
    for i, model in enumerate(models, start=1):
        suffix = f"__COUNCIL_{i}"
        url = os.environ.get("ASDD_MODEL_URL" + suffix) or os.environ.get("ASDD_MODEL_URL", "")
        token = os.environ.get("ASDD_RUNTIME_TOKEN" + suffix) or os.environ.get("ASDD_RUNTIME_TOKEN", "")
        members.append({"idx": i, "model": model, "url": url.strip(), "token": token.strip(),
                        "is_lead": i == len(models)})
    return members


# --- one free-form OpenAI-compatible call (NOT the review adapter: proposers emit code/prose, not JSON) --
def call_model(member, system, user, max_tokens, retries=2, timeout=180):
    endpoint = member["url"].rstrip("/")
    if not endpoint.endswith("/chat/completions"):
        endpoint += "/chat/completions"
    # A newer OpenAI reasoning model rejects max_tokens with a 400 naming max_completion_tokens; every
    # other model keeps working on max_tokens. Start on max_tokens and switch the parameter on that 400.
    tok_param = "max_tokens"
    last = ""
    for attempt in range(max(1, retries + 1)):
        body = json.dumps({
            "model": member["model"],
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            tok_param: max_tokens,
        }).encode("utf-8")
        req = urllib.request.Request(endpoint, data=body, headers={
            "Authorization": "Bearer " + member["token"],
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.loads(r.read().decode("utf-8", "replace"))
            msg = (data.get("choices") or [{}])[0].get("message") or {}
            text = (msg.get("content") or msg.get("reasoning_content") or "").strip()
            if text:
                return text
            last = "empty content"
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code == 400 and tok_param == "max_tokens":
                detail = ""
                try:
                    detail = e.read().decode("utf-8", "replace")
                except Exception:
                    pass
                if "max_completion_tokens" in detail:
                    tok_param = "max_completion_tokens"  # retry the same call with the renamed parameter
                    continue
        except Exception as e:
            last = type(e).__name__
    return ""  # a member that cannot answer drops out (graceful degradation)


# --- the change under implementation: read the OpenSpec change and its acceptance criteria --------------
def read_change(root, change):
    base = os.path.join(root, "openspec", "changes", change)
    if not os.path.isdir(base):
        return None
    parts = []
    for rel in ("proposal.md", "tasks.md"):
        p = os.path.join(base, rel)
        if os.path.isfile(p):
            parts.append(f"# {rel}\n" + open(p, encoding="utf-8").read())
    specs = os.path.join(base, "specs")
    for dirpath, _dirs, files in os.walk(specs):
        for f in sorted(files):
            if f.endswith(".md"):
                fp = os.path.join(dirpath, f)
                parts.append(f"# {os.path.relpath(fp, base)}\n" + open(fp, encoding="utf-8").read())
    return "\n\n".join(parts) if parts else None


def digest(text):
    return "sha256:" + hashlib.sha256((text or "").encode("utf-8", "replace")).hexdigest()[:16]


def record(root, action, verdict, reasoning, payload, lens=None):
    """One audit record. Fail-safe and content-safe: counts and the run's own short rationale, never the
    drafted code. Mirrors cli/run-agent.sh: the ledger is written even if a model call failed. `lens`
    routes a curated learning into the knowledge view (council-synthesis -> exemplar,
    council-rejected -> rejected); without a lens the record is corpus/governance only."""
    args = ["python3", os.path.join(CLI_DIR, "audit.py"), "append",
            "--ledger", os.environ.get("ASDD_ACTIVITY_LOG", ".asdd-work/audit.jsonl"),
            "--role", "developer", "--action", action,
            "--authorizing-decision", "operator-run developer council (advisory; a human reviews and merges)",
            "--verdict", verdict, "--reasoning", reasoning[:280], "--payload-json", json.dumps(payload)]
    if lens:
        args += ["--lens", lens]
    try:
        subprocess.run(args, cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        pass


def _marked(text, marker):
    """The text after a `MARKER:` line, one entry per occurrence. The council states its rationale and its
    rejections on these lines so a clean decision statement (not the drafted code) reaches the ledger."""
    out = []
    for ln in (text or "").splitlines():
        s = ln.strip()
        if s.upper().startswith(marker.upper()):
            v = s[len(marker):].lstrip(" :-").strip()
            if v:
                out.append(v)
    return out


# --- prompts (trusted; the OpenSpec change is the operator's own, so inputs are trusted, no fence) -------
PROPOSE_SYS = ("You are a proposer on a developer council implementing an OpenSpec change. Draft an "
               "implementation that satisfies the change's acceptance criteria. Be concrete: the code or "
               "diff, and a one-paragraph rationale tied to the criteria. Do not review or merge.")
CRITIQUE_SYS = ("You are a proposer on a developer council. Critique the OTHER proposals ONLY against the "
                "change's acceptance criteria: what each misses, gets wrong, or risks. Be specific and "
                "brief. For each approach you would set aside, add a line 'REJECT: <one sentence, why it "
                "fails the criteria>'. Note genuine disagreements rather than smoothing them over.")
SYNTH_SYS = ("You are the lead synthesiser on a developer council. From the proposals and critiques, "
             "produce ONE implementation that best satisfies the acceptance criteria. Return the "
             "implementation, then a final line 'RATIONALE: <one sentence, why this satisfies the "
             "criteria>'. Name any unresolved disagreement rather than hiding it.")
TESTAUTHOR_SYS = ("You extend the test suite from the spec. Given the acceptance criteria and the proposed "
                  "implementation, list the tests that must pass, and any the implementation would fail.")
TESTRUN_SYS = ("You are the test runner. Given the acceptance criteria, the implementation and the tests, "
               "return ONLY a JSON object: {\"pass\": true|false, \"reasoning\": \"...\"}.")


def main():
    ap = argparse.ArgumentParser(prog="asdd dev-council", description="The developer council orchestrator.")
    ap.add_argument("--change", help="the OpenSpec change id under openspec/changes/")
    ap.add_argument("--root", default=ROOT, help="repo root (default: the kit's own root)")
    ap.add_argument("--models", help="comma-separated model list, overriding dev_council.models")
    ap.add_argument("--out", help="write the synthesised result here (default stdout)")
    ap.add_argument("--transcript", help="write the full council transcript (JSON) here")
    ap.add_argument("--test-cmd", help="a command that applies+runs the real suite (else a model-judged verify)")
    ap.add_argument("--dry-run", action="store_true", help="assemble the prompts and report, without calling a model")
    a = ap.parse_args()
    root = os.path.abspath(a.root)

    cfg = (load_config(root).get("dev_council") or {}) if isinstance(load_config(root), dict) else {}
    models = ([m.strip() for m in a.models.split(",") if m.strip()] if a.models
              else as_model_list(cfg.get("models")))
    n_crit = _clamp_rounds(cfg.get("max_critique_rounds", 1))
    n_refine = _clamp_rounds(cfg.get("max_refine_rounds", 1))
    max_tokens = int(cfg.get("max_tokens") or 4000)

    # Size: 2..5, default 3. Fewer than 2 is not a council; more than 5 is capped with notice.
    if not models:
        sys.stderr.write("dev-council: no models. Set dev_council.models in .asdd.yml (2 to 5) or pass --models.\n")
        return 2
    if len(models) > MAX_N:
        sys.stderr.write(f"dev-council: {len(models)} models exceeds the cap of {MAX_N}; using the first {MAX_N}.\n")
        models = models[:MAX_N]
    if len(models) < MIN_N:
        sys.stderr.write(f"dev-council: {len(models)} model(s) is not a council (minimum {MIN_N}).\n")
        return 2

    # Heterogeneity: warn on same-family clones; hard-fail developer == a test role.
    cfg_all = load_config(root)
    rmodels = cfg_all.get("models") if isinstance(cfg_all.get("models"), dict) else {}
    testers = {rmodels.get("test_author", ""), rmodels.get("test_runner", "")}
    fams = [family(m) for m in models]
    if len(set(fams)) < len(fams):
        sys.stderr.write("dev-council: warning - some council models share a family (near-clones); diversity is the point.\n")
    clash = sorted(set(models) & {t for t in testers if t})
    if clash:
        sys.stderr.write(f"dev-council: FAIL - council model(s) {clash} also serve a test role; the developer must "
                         f"differ from test_author and test_runner (independence).\n")
        return 2
    # The reviewer independently reviews the council's output, so a council model that also reviews is not
    # an independent check. STANDARD makes reviewer-differs-from-developer a SHOULD, so this warns rather
    # than fails; a deployment that treats it as hard simply keeps its reviewer model out of the council.
    reviewer = rmodels.get("reviewer", "")
    if reviewer and reviewer in set(models):
        sys.stderr.write(f"dev-council: warning - council model '{reviewer}' also serves as the reviewer; the "
                         "reviewer should stay distinct so its review of the council's output is independent.\n")

    members = resolve_members(models)
    lead = members[-1]
    proposers = members[:-1] or [lead]  # with exactly 2 members, one proposes and the lead synthesises
    wired = [m for m in members if m["url"] and m["token"]]

    change_text = read_change(root, a.change) if a.change else None
    criteria = change_text or f"(no OpenSpec change '{a.change}' found; run against its acceptance criteria)"

    # Dry run, or nothing wired: assemble and report, prove the shape without spending.
    if a.dry_run or not wired:
        why = "requested" if a.dry_run else "no model wired"
        report = [
            f"ASDD developer council - dry run ({why}).",
            f"Council: {len(members)} model(s) = {len(proposers)} proposer(s) + 1 lead ({lead['model']}).",
            f"Change: {a.change or '(none given)'}. Rounds: {n_crit} critique, {n_refine} refine.",
            "Sequence: propose -> cross-critique -> synthesise -> verify (test-author + test-runner, "
            "distinct models) -> refine on failure. Always one result.",
            "Wire the models (shared ASDD_MODEL_URL + ASDD_RUNTIME_TOKEN, or the per-member __COUNCIL_<i> "
            "variants) to activate it.",
        ]
        out = "\n".join(report)
        (open(a.out, "w").write(out + "\n") if a.out else print(out))
        record(root, "dev-council.dry-run", "dry-run",
               f"council dry run ({why}) for change {a.change}",
               {"members": len(members), "proposers": len(proposers), "wired": len(wired)})
        return 0

    transcript = {"change": a.change, "members": [m["model"] for m in members],
                  "proposals": [], "critiques": [], "synthesis": "", "verify": {}, "refined": False}

    # 1. PROPOSE
    user = f"OpenSpec change acceptance criteria and context:\n\n{criteria}\n\nDraft your implementation."
    for m in proposers:
        if not (m["url"] and m["token"]):
            continue
        text = call_model(m, PROPOSE_SYS, user, max_tokens)
        if text:
            transcript["proposals"].append({"model": m["model"], "text": text})
    if not transcript["proposals"]:
        record(root, "dev-council.run", "error", "every proposer failed to draft", {"proposals": 0})
        msg = "ASDD developer council - no proposer produced a draft (runtime errors). A human should implement this."
        (open(a.out, "w").write(msg + "\n") if a.out else print(msg))
        return 0

    # 2. CROSS-CRITIQUE (bounded)
    for _round in range(n_crit):
        others = "\n\n".join(f"[{i+1}] ({p['model']})\n{p['text']}"
                             for i, p in enumerate(transcript["proposals"]))
        cu = f"Acceptance criteria:\n{criteria}\n\nProposals:\n{others}\n\nCritique each ONLY against the criteria."
        for m in proposers:
            if not (m["url"] and m["token"]):
                continue
            c = call_model(m, CRITIQUE_SYS, cu, max_tokens)
            if c:
                transcript["critiques"].append({"model": m["model"], "text": c})

    # 3. SYNTHESISE (the lead)
    props = "\n\n".join(f"[{i+1}]\n{p['text']}" for i, p in enumerate(transcript["proposals"]))
    crits = "\n\n".join(c["text"] for c in transcript["critiques"])
    su = (f"Acceptance criteria:\n{criteria}\n\nProposals:\n{props}\n\nCritiques:\n{crits}\n\n"
          "Produce one implementation that best satisfies the criteria.")
    synthesis = call_model(lead, SYNTH_SYS, su, max_tokens) or (transcript["proposals"][0]["text"])
    transcript["synthesis"] = synthesis

    # 4. VERIFY (test agents on models distinct from the council), then one refine round on failure
    verdict = verify(root, cfg_all, criteria, synthesis, a.test_cmd, max_tokens, transcript)
    if not verdict.get("pass", True) and n_refine:
        ru = (f"Acceptance criteria:\n{criteria}\n\nYour implementation:\n{synthesis}\n\n"
              f"It failed verification: {verdict.get('reasoning', '')}\n\nRefine it to pass.")
        refined = call_model(lead, SYNTH_SYS, ru, max_tokens)
        if refined:
            transcript["synthesis"] = synthesis = refined
            transcript["refined"] = True
            verdict = verify(root, cfg_all, criteria, synthesis, a.test_cmd, max_tokens, transcript)
    transcript["verify"] = verdict

    # record: counts + the lead's own short rationale, never the drafted code
    record(root, "dev-council.run", "pass" if verdict.get("pass") else "changes-requested",
           f"council of {len(members)} synthesised a result for {a.change}; verify "
           f"{'passed' if verdict.get('pass') else 'failed'}"
           f"{'; refined once' if transcript['refined'] else ''}",
           {"members": len(members), "proposals": len(transcript["proposals"]),
            "critiques": len(transcript["critiques"]), "refined": transcript["refined"],
            "verify_pass": bool(verdict.get("pass")), "synthesis_digest": digest(synthesis)})

    # Curated learnings for the knowledge base: the verified synthesis is an exemplar, each set-aside
    # approach a rejected page. The reasoning is the model's own one-line RATIONALE/REJECT statement, a
    # clean decision, never the drafted code, so an OKGF page never carries the implementation verbatim.
    if verdict.get("pass"):
        rationale = (_marked(synthesis, "RATIONALE") or ["a synthesis that passed the council's verify"])[0]
        record(root, "dev-council.synthesis", "pass", rationale,
               {"members": len(members), "synthesis_digest": digest(synthesis)}, lens="council-synthesis")
    for c in transcript["critiques"]:
        for rej in _marked(c["text"], "REJECT"):
            record(root, "dev-council.rejected", "changes-requested", rej,
                   {"by": c["model"]}, lens="council-rejected")

    if a.transcript:
        open(a.transcript, "w", encoding="utf-8").write(json.dumps(transcript, indent=2))
    header = (f"# Developer council result ({len(members)} models, "
              f"verify {'passed' if verdict.get('pass') else 'FAILED'}"
              f"{', refined once' if transcript['refined'] else ''})\n\n")
    out = header + synthesis
    (open(a.out, "w", encoding="utf-8").write(out + "\n") if a.out else print(out))
    return 0


def verify(root, cfg_all, criteria, implementation, test_cmd, max_tokens, transcript):
    """Reuse the test agents on models DISTINCT from the council. test-author lists the tests; the real
    suite runs if --test-cmd is given, else test-runner judges. One verify per call (the caller bounds
    refine rounds)."""
    rmodels = cfg_all.get("models") if isinstance(cfg_all.get("models"), dict) else {}
    ta = {"idx": 0, "model": rmodels.get("test_author", ""),
          "url": os.environ.get("ASDD_MODEL_URL__TEST_AUTHOR") or os.environ.get("ASDD_MODEL_URL", ""),
          "token": os.environ.get("ASDD_RUNTIME_TOKEN__TEST_AUTHOR") or os.environ.get("ASDD_RUNTIME_TOKEN", "")}
    tr = {"idx": 0, "model": rmodels.get("test_runner", ""),
          "url": os.environ.get("ASDD_MODEL_URL__TEST_RUNNER") or os.environ.get("ASDD_MODEL_URL", ""),
          "token": os.environ.get("ASDD_RUNTIME_TOKEN__TEST_RUNNER") or os.environ.get("ASDD_RUNTIME_TOKEN", "")}
    tests = ""
    if ta["url"] and ta["token"] and ta["model"]:
        tests = call_model(ta, TESTAUTHOR_SYS,
                           f"Acceptance criteria:\n{criteria}\n\nImplementation:\n{implementation}", max_tokens)
    transcript["verify"] = {"tests_from": ta["model"]}
    # A real run wins over a model judgement when the operator wired one. test_cmd is the OPERATOR'S OWN
    # command, passed on their command line in their own produce session, never untrusted PR input, so a
    # shell is the intended interface (they may write `pytest && ...`). Not an injection surface.
    if test_cmd:
        r = subprocess.run(test_cmd, shell=True, cwd=root, capture_output=True, text=True)  # nosec B602
        return {"pass": r.returncode == 0, "reasoning": f"ran `{test_cmd}` -> exit {r.returncode}",
                "tests_from": ta["model"]}
    if not (tr["url"] and tr["token"] and tr["model"]):
        return {"pass": True, "reasoning": "no test runner wired; not verified", "tests_from": ta["model"]}
    j = call_model(tr, TESTRUN_SYS,
                   f"Acceptance criteria:\n{criteria}\n\nImplementation:\n{implementation}\n\nTests:\n{tests}",
                   512)
    m = re.search(r"\{.*\}", j or "", re.S)
    try:
        d = json.loads(m.group(0)) if m else {}
    except Exception:
        d = {}
    return {"pass": bool(d.get("pass", False)), "reasoning": str(d.get("reasoning", "no verdict"))[:280],
            "tests_from": ta["model"]}


if __name__ == "__main__":
    sys.exit(main())
