#!/usr/bin/env python3
"""asdd connect-check - is each agent's model actually connected, or dry-running?

Every ASDD agent (the review lenses, test-author, test-runner, documentation, interaction, and the
optional developer council) DRY-RUNS until its model runtime is connected. A deployment can look set up
while no agent does real work: a pull request's review comes back a placeholder, not a real review the
human can judge. This makes that impossible to miss. For each role it resolves the model, endpoint and key
the gates actually use (cli/resolve-model.sh) and sends one tiny request, then reports LIVE or NOT
CONNECTED per role with a summary. It exits non-zero if any configured role is not connected, so
`asdd setup` and CI can gate on it.

Usage:
    connect-check.py [CONFIG]                 # ping every roster role (+ the council if configured)
    connect-check.py --no-ping                # report config completeness only (no model call)
    connect-check.py --role reviewer          # one role
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RESOLVER = os.path.join(HERE, "resolve-model.sh")

# Roles that run on an ASDD-resolved model. The developer is bring-your-own (its own Goose session), so it
# is not connected through the ASDD runtime and is not checked here.
ROSTER_ROLES = ["reviewer", "test_author", "test_runner", "documentation", "interaction"]


def _sh(*argv):
    try:
        return subprocess.run(["bash", *argv], capture_output=True, text=True, timeout=15).stdout.strip()
    except Exception:
        return ""


def resolve_role(role, config):
    """Model, endpoint and key for a roster role, resolved exactly as the gates resolve them."""
    model = _sh(RESOLVER, role, config)
    url = _sh(RESOLVER, role, config, "--url")
    tvar = _sh(RESOLVER, role, config, "--token-var")
    token = os.environ.get(tvar, "") if tvar else ""
    return model, url, token


def council_members(config):
    """The developer council members (dev_council.models) with the per-member or shared endpoint/key. []
    if the council is not configured. Tolerates block- and flow-style lists."""
    models = []
    inblk = False
    try:
        for raw in open(config, encoding="utf-8"):
            line = raw.split("#", 1)[0].rstrip()
            if line.strip() == "dev_council:":
                inblk = True
                continue
            if inblk:
                if line and not line[0].isspace():
                    break
                s = line.strip()
                if s.startswith("models:"):
                    rest = s[len("models:"):].strip()
                    if rest.startswith("[") and rest.endswith("]"):
                        models = [p.strip().strip("\"'") for p in rest[1:-1].split(",") if p.strip()]
                elif s.startswith("- "):
                    models.append(s[2:].strip().strip("\"'"))
    except OSError:
        return []
    out = []
    for i, m in enumerate(models, 1):
        url = os.environ.get(f"ASDD_MODEL_URL__COUNCIL_{i}") or os.environ.get("ASDD_MODEL_URL", "")
        token = os.environ.get(f"ASDD_RUNTIME_TOKEN__COUNCIL_{i}") or os.environ.get("ASDD_RUNTIME_TOKEN", "")
        out.append((f"council[{i}]", m, url, token))
    return out


def ping(model, url, token, timeout=30):
    endpoint = url.rstrip("/")
    if not endpoint.endswith("/chat/completions"):
        endpoint += "/chat/completions"
    # max_tokens 64 (not 1): a 1-token cap makes some reasoning models 500 on the ping even though they
    # answer fine with a real budget, which would false-fail a reachable model. 64 is small but enough.
    def once(tok_param):
        body = json.dumps({"model": model, "messages": [{"role": "user", "content": "ping"}],
                           tok_param: 64}).encode("utf-8")
        req = urllib.request.Request(endpoint, data=body, headers={
            "Authorization": "Bearer " + token, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return (200 <= resp.status < 300), f"HTTP {resp.status}"
    try:
        return once("max_tokens")
    except urllib.error.HTTPError as e:
        # A newer OpenAI reasoning model rejects max_tokens with a 400 naming max_completion_tokens.
        # Retry once with the renamed parameter; every other model keeps working on max_tokens.
        detail = ""
        try:
            detail = e.read().decode("utf-8", "replace")
        except Exception:
            pass
        if e.code == 400 and "max_completion_tokens" in detail:
            try:
                return once("max_completion_tokens")
            except urllib.error.HTTPError as e2:
                return False, f"HTTP {e2.code}"
            except Exception as e2:
                return False, type(e2).__name__
        return False, f"HTTP {e.code}"
    except Exception as e:
        return False, type(e).__name__


def classify(role, model, url, token, do_ping):
    if not model:
        return "no-model", "no model in the roster"
    missing = [n for n, v in (("endpoint", url), ("key", token)) if not v]
    if missing:
        return "dry-run", "model set, but " + " and ".join(missing) + " not connected"
    if not do_ping:
        return "ready", f"{model}: model + endpoint + key present"
    ok, why = ping(model, url, token)
    return ("live", f"{model}: {why}") if ok else ("error", f"{model}: {why}")


def main():
    ap = argparse.ArgumentParser(prog="asdd connect-check", description="Is each agent's model connected?")
    ap.add_argument("config", nargs="?", default=".asdd.yml")
    ap.add_argument("--role", action="append", default=[], help="check only these roster roles")
    ap.add_argument("--no-ping", action="store_true", help="report config completeness only; no model call")
    a = ap.parse_args()
    if not os.path.isfile(a.config):
        sys.stderr.write(f"connect-check: no config at {a.config} (run `asdd init --goose` first).\n")
        return 2

    checks = []
    for role in (a.role or ROSTER_ROLES):
        model, url, token = resolve_role(role, a.config)
        checks.append((role, model, url, token))
    if not a.role:
        checks += [(name, m, u, t) for name, m, u, t in council_members(a.config)]

    print("asdd connect-check - are the agents connected, or dry-running?\n")
    connected = configured = 0
    for name, model, url, token in checks:
        if not model and name.startswith("council"):
            continue
        configured += 1 if model else 0
        state, detail = classify(name, model, url, token, not a.no_ping)
        mark = {"live": "LIVE ", "ready": "READY", "dry-run": "DRY  ", "error": "ERR  ",
                "no-model": "-    "}[state]
        if state in ("live", "ready"):
            connected += 1
        print(f"  [{mark}] {name:<14} {detail}")

    live, total = connected, configured
    print()
    if total == 0:
        print("No role has a model in the roster. Run `asdd setup` to assign models, then connect a runtime.")
        return 1
    if live == total:
        print(f"All {total} configured agent(s) connected. The fleet will do real work.")
        return 0
    print(f"{live}/{total} agent(s) connected. The rest DRY-RUN and do no real work (a review comes back a")
    print("placeholder, not a real review). Connect a model runtime: set ASDD_MODEL_URL (variable) and")
    print("ASDD_RUNTIME_TOKEN (secret), or the per-role/__COUNCIL_<i> variants, then re-run this check.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
