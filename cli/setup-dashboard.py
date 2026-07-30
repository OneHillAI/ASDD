#!/usr/bin/env python3
"""setup-dashboard - a local, non-engineer front door for "ASDD with Goose".

The friendly counterpart to `asdd setup`: a small local web page to assign a model to
each agent role, see the heterogeneity rule pass or fail live, read the exact next
steps, and RUN an agent without typing a goose command. It is the operate kit's own
surface; the governance dashboard (cli/dashboard.py) stays the read-only view. It
inlines that dashboard's shared stylesheet so the two look like one product, but
shares no code with it.

It is LOCAL and interactive by nature (it writes .asdd.yml and launches agents), so:

  - it binds to 127.0.0.1 only, and every write or run is guarded by a per-run token,
    so a page on another origin cannot drive it;
  - it is NOT a command runner. It runs `goose` and nothing else, with a fixed argv
    (never a shell), on a recipe from a server-side allow-list, on a model/endpoint/key
    resolved from your config - never from the request. It gives you no capability you
    do not already have in a terminal, and whatever the agent produces is still governed:
    agents open PRs, the gates review, a human merges;
  - it writes model NAMES only. A key-shaped value is refused (.asdd.yml is
    version-controlled), and credentials are resolved from the environment per role.

    python3 cli/setup-dashboard.py                 # serve on 127.0.0.1 and open a browser
    python3 cli/setup-dashboard.py --config X --port 8765 --no-open
    python3 cli/setup-dashboard.py --render        # print the page HTML and exit (no server)

The config defaults to ./.asdd.yml (the repo you run it in), like `asdd setup`.
"""
import html
import importlib.util
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESOLVER = os.path.join(HERE, "resolve-model.sh")

# Reuse setup-goose's tested logic (single source of truth for reading/writing the
# models block, validating it, and spotting a credential). Its filename has a hyphen,
# so load it by path.
_spec = importlib.util.spec_from_file_location("setup_goose", os.path.join(HERE, "setup-goose.py"))
sg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sg)

MAX_MODEL = 200
MAX_PARAM = 300
MAX_RUNS = 8
RUN_TIMEOUT = 1800          # 30 minutes: an agent run is slow, but never unbounded
OUTPUT_TAIL = 4000          # keep the tail of a run's output, not all of it

_RUNS = []                  # newest first
_RUNS_LOCK = threading.Lock()

_CSS_FALLBACK = (
    ":root{--bg:#fff;--fg:#1a1a1a;--mut:#666;--line:#e5e5e5;--card:#f7f7f5;--accent:#b45309}"
    "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);"
    "font:16px/1.5 -apple-system,system-ui,sans-serif}"
    ".wrap{max-width:1000px;margin:0 auto;padding:2rem 1.25rem}"
)

# Setup-specific styling, appended to the shared sheet. The shared `.banner` is the
# governance dashboard's internal-only warning, so a save result uses `.result` rather
# than fighting it.
LOCAL_CSS = """
.wrap{max-width:860px;padding-bottom:4rem}
.row{display:flex;gap:1rem;align-items:baseline;padding:.7rem 0;border-bottom:1px solid var(--line);flex-wrap:wrap}
.row label{flex:0 0 8.5rem;font-weight:600}
.row .hint{flex:1 1 14rem;color:var(--mut);font-size:.82rem;min-width:12rem}
.row input{flex:1 1 12rem;background:var(--bg);color:var(--fg);border:1px solid var(--line);border-radius:7px;padding:.45rem .6rem;font:inherit;font-size:.9rem;min-width:10rem}
button{background:var(--accent);color:#fff;border:0;border-radius:8px;padding:.55rem 1rem;font:inherit;font-weight:600;cursor:pointer}
button.sec{background:transparent;color:var(--accent);border:1px solid var(--line)}
button[disabled]{background:var(--card);color:var(--mut);cursor:not-allowed}
form.save button{margin-top:1.1rem}
.result{border-radius:9px;padding:.7rem .9rem;margin:1rem 0;font-size:.9rem;border:1px solid var(--line);background:var(--card);white-space:pre-wrap}
.result.ok{border-color:#16a34a}.result.bad{border-color:#dc2626}
pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:.7rem .9rem;overflow-x:auto;font-size:.82rem;white-space:pre-wrap}
.roster{background:#fff;border:1px solid var(--line);border-radius:10px;padding:1rem;overflow-x:auto}
.roster svg{max-width:100%;height:auto;display:block;margin:0 auto}
.agent{display:flex;gap:.75rem;align-items:center;padding:.6rem 0;border-bottom:1px solid var(--line);flex-wrap:wrap}
.agent .who{flex:0 0 8.5rem;font-weight:600}
.agent .on{flex:0 0 auto;color:var(--mut);font-size:.8rem}
.agent input{background:var(--bg);color:var(--fg);border:1px solid var(--line);border-radius:7px;padding:.35rem .5rem;font:inherit;font-size:.85rem;width:9rem}
.agent form{display:flex;gap:.5rem;align-items:center;margin-left:auto;flex-wrap:wrap}
.run{border:1px solid var(--line);border-radius:9px;padding:.6rem .8rem;margin:.5rem 0;background:var(--card)}
.run .hd{display:flex;gap:.6rem;align-items:baseline;font-size:.85rem}
.run .hd b{font-size:.9rem}
.run pre{margin:.5rem 0 0;background:var(--bg);max-height:16rem;overflow:auto}
"""


def shared_css():
    """The shared stylesheet (cli/dashboard.css), inlined so the page stays self-contained
    (no external assets). Falls back to a minimal core so it never renders naked."""
    try:
        with open(os.path.join(HERE, "dashboard.css"), encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return _CSS_FALLBACK


def clean_model(v):
    """A model id from an untrusted form field: strip YAML-breaking characters and cap length."""
    for bad in ('"', "'", "\n", "\r", "\t"):
        v = v.replace(bad, "")
    return v.strip()[:MAX_MODEL]


def clean_param(v):
    """A recipe parameter from a form field. It reaches the agent as its own argv item -
    never a shell string - so this is about sanity, not shell escaping."""
    return "".join(c for c in v if c.isprintable()).strip()[:MAX_PARAM]


def load_roles(config):
    lines = sg.read_lines(config)
    start, end = sg.models_region(lines)
    return lines, sg.parse_roles(lines, start, end)


def recipe_dir_for(config):
    repo = os.path.join(os.path.dirname(os.path.abspath(config)), "recipes")
    return repo if os.path.isdir(repo) else os.path.join(ROOT, "recipes")


def repo_dir_for(config):
    return os.path.dirname(os.path.abspath(config))


def roster_svg():
    """The canonical agent-roster diagram (docs/diagrams/agents.svg), inlined. Empty if absent."""
    try:
        with open(os.path.join(ROOT, "docs", "diagrams", "agents.svg"), encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def apply_assignments(config, assignments):
    """Write the given {role: model} into the config's models block (reusing setup-goose's
    set_value), then validate. Returns (status, message) where status is:
      "saved"   written and the heterogeneity check passed
      "invalid" written but the heterogeneity check failed
      "refused" NOT written - a value looked like a credential

    The refusal matters because .asdd.yml is version-controlled: a key committed here
    would persist in git history even if deleted later."""
    lines, roles = load_roles(config)
    by_key = {r["key"]: r for r in roles}
    cleaned = {k: clean_model(v) for k, v in assignments.items() if k in by_key}
    leaked = sorted(k for k, v in cleaned.items() if sg.looks_like_credential(v))
    if leaked:
        return "refused", ("That looks like an API key, not a model name (" + ", ".join(leaked) +
                           "). " + sg.CREDENTIAL_HELP.format(path=config))
    for key, model in cleaned.items():
        idx = by_key[key]["idx"]
        lines[idx] = sg.set_value(lines[idx], model)
    with open(config, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    rc, out = sg.run_check(config, strict=False)
    return ("saved" if rc == 0 else "invalid"), out


# --- running an agent ---------------------------------------------------------------

def recipe_params(recipe_path):
    """The parameter keys a recipe declares. Scanned, like the rest of the kit reads YAML,
    and it doubles as the ALLOW-LIST: a form field for any other key is ignored."""
    keys, inside = [], False
    try:
        text = open(recipe_path, encoding="utf-8").read()
    except OSError:
        return keys
    for line in text.splitlines():
        if re.match(r"^parameters:", line):
            inside = True
            continue
        if inside:
            if line and not line[0].isspace():
                break
            m = re.match(r"^\s+-\s+key:\s*(\S+)", line)
            if m:
                keys.append(m.group(1))
    return keys


def launchable(config):
    """[(role, recipe_filename)] the dashboard may launch: a recipe on disk whose role is in
    the roster. This is the ALLOW-LIST - a role never comes from the request unchecked.

    The developer is excluded: it is bring-your-own, i.e. your own Goose session. setup is
    excluded: it is the guided conversation, not a job. interaction-public has no roster key
    of its own, so it falls out naturally."""
    out = []
    rd = recipe_dir_for(config)
    if not os.path.isdir(rd):
        return out
    try:
        _, roles = load_roles(config)
    except SystemExit:
        return out
    known = {r["key"] for r in roles}
    for fn in sorted(os.listdir(rd)):
        if not fn.endswith(".yaml") or fn in ("developer.yaml", "setup.yaml"):
            continue
        role = fn[:-5].replace("-", "_")
        if role in known:
            out.append((role, fn))
    return out


def resolve_runtime(role, config):
    """(model, url, token_var) for a role, via the tested resolver - the same lookup docsync
    and every other run path uses, so the dashboard can never disagree with CI."""
    def q(*flags):
        p = subprocess.run(["bash", RESOLVER, role, config, *flags],
                           capture_output=True, text=True)
        return p.stdout.strip() if p.returncode == 0 else ""
    return q(), q("--url"), q("--token-var")


def build_run_argv(recipe_path, model, params):
    """The exact argv for a run. A list, never a shell string, so a parameter value cannot
    become a command. The recipe path and the model are resolved server-side."""
    argv = ["goose", "run", "--recipe", recipe_path, "--provider", "openai", "--model", model]
    for key in sorted(params):
        argv += ["--params", f"{key}={params[key]}"]
    return argv


def run_env(url, token_var):
    """Point Goose's openai provider at this role's endpoint, with this role's key. Each run
    is its own process, so a per-role key stays scoped to it."""
    env = dict(os.environ)
    scheme, _, rest = url.partition("://")
    host, _, path = rest.partition("/")
    env["OPENAI_API_KEY"] = os.environ.get(token_var, "")
    env["OPENAI_HOST"] = f"{scheme}://{host}"
    env["OPENAI_BASE_PATH"] = path
    return env


def _record(role):
    run = {"role": role, "status": "running", "started": time.strftime("%H:%M:%S"),
           "output": "", "code": None}
    with _RUNS_LOCK:
        _RUNS.insert(0, run)
        del _RUNS[MAX_RUNS:]
    return run


def start_run(role, config, params):
    """Launch one agent in the background. Returns (ok, message)."""
    allowed = dict(launchable(config))
    if role not in allowed:                       # the allow-list, enforced server-side
        return False, f"Refused: '{html.escape(role)}' is not a launchable agent here."
    if not shutil.which("goose"):
        return False, "Goose is not installed or not on PATH. Install Goose, then reload."
    model, url, token_var = resolve_runtime(role, config)
    token = os.environ.get(token_var, "") if token_var else ""
    if not model or not url or not token:
        missing = []
        if not model:
            missing.append(f"a model (set models.{role} above)")
        if not url:
            missing.append("an endpoint (ASDD_MODEL_URL)")
        if not token:
            missing.append(f"a key (${token_var or 'ASDD_RUNTIME_TOKEN'})")
        return False, "Not wired yet: this run needs " + ", and ".join(missing) + "."

    recipe_path = os.path.join(recipe_dir_for(config), allowed[role])
    declared = set(recipe_params(recipe_path))
    use = {k: clean_param(v) for k, v in params.items() if k in declared and v.strip()}
    argv = build_run_argv(recipe_path, model, use)
    env = run_env(url, token_var)
    cwd = repo_dir_for(config)
    run = _record(role)

    def worker():
        try:
            p = subprocess.run(argv, env=env, cwd=cwd, capture_output=True, text=True,
                               timeout=RUN_TIMEOUT)
            out = (p.stdout + p.stderr)[-OUTPUT_TAIL:]
            with _RUNS_LOCK:
                run["output"] = out
                run["code"] = p.returncode
                run["status"] = "done" if p.returncode == 0 else "failed"
        except subprocess.TimeoutExpired:
            with _RUNS_LOCK:
                run["status"] = "failed"
                run["output"] = f"timed out after {RUN_TIMEOUT}s"
        except Exception as e:  # noqa: BLE001 - surface any launch error on the page
            with _RUNS_LOCK:
                run["status"] = "failed"
                run["output"] = str(e)

    threading.Thread(target=worker, daemon=True).start()
    return True, f"Started {role} on {model}."


# --- rendering ----------------------------------------------------------------------

def steps_html(roles, config):
    by_key = {r["key"]: r["value"] for r in roles}
    rev = by_key.get("reviewer", "")
    lines = [
        "1. Connect the providers for the models you named:",
        "     goose configure",
        "2. Wire the runtime (repo Settings > Secrets and variables > Actions):",
        "     ASDD_RUNTIME_TOKEN   (secret)    your model API key",
        "     ASDD_MODEL_URL       (variable)  full .../v1/chat/completions URL",
        f"     ASDD_MODEL           (variable)  the fallback model{(' (reviewer: ' + rev + ')') if rev else ''}",
        "   A role can have its own provider: set ASDD_MODEL_URL__<ROLE> and",
        "   ASDD_RUNTIME_TOKEN__<ROLE> (e.g. __DOCUMENTATION) to override for that role only.",
        "3. Prove the gates run with no keys:",
        "     sh cli/asdd-mcp.test.sh",
    ]
    return html.escape("\n".join(lines))


def agents_html(config, have_goose):
    rows = []
    for role, fn in launchable(config):
        model, url, token_var = resolve_runtime(role, config)
        wired = bool(model and url and os.environ.get(token_var or "", ""))
        on = html.escape(model) if model else "no model set"
        fields = "".join(
            f'<input name="p_{html.escape(k)}" placeholder="{html.escape(k)}" autocomplete="off">'
            for k in recipe_params(os.path.join(recipe_dir_for(config), fn))
        )
        dis = "" if (wired and have_goose) else " disabled"
        rows.append(
            f'<div class="agent"><span class="who">{html.escape(role)}</span>'
            f'<span class="on">{on}</span>'
            f'<form method="post" action="/run">'
            f'<input type="hidden" name="token" value="__TOKEN__">'
            f'<input type="hidden" name="role" value="{html.escape(role)}">'
            f'{fields}<button type="submit"{dis}>Run</button></form></div>'
        )
    if not rows:
        return '<p class="empty">No launchable agents: no recipes found for the roles in your roster.</p>'
    note = ("" if have_goose else
            '<p class="sub">Goose is not on PATH, so runs are disabled. Install Goose and reload.</p>')
    return note + "".join(rows)


def runs_html():
    with _RUNS_LOCK:
        runs = list(_RUNS)
    if not runs:
        return '<p class="empty">Nothing run yet from here.</p>'
    out = []
    for r in runs:
        cls = {"running": "v-none", "done": "v-ok", "failed": "v-bad"}[r["status"]]
        code = "" if r["code"] is None else f" (exit {r['code']})"
        body = f'<pre>{html.escape(r["output"])}</pre>' if r["output"] else ""
        out.append(
            f'<div class="run"><div class="hd"><b>{html.escape(r["role"])}</b>'
            f'<span class="{cls}">{r["status"]}{code}</span>'
            f'<span class="sub">started {r["started"]}</span></div>{body}</div>'
        )
    return "".join(out)


def render(config, token, banner=None):
    lines, roles = load_roles(config)
    rc, check_out = sg.run_check(config, strict=False)
    n_set = sum(1 for r in roles if r["value"])
    hetero = ('<span class="v-ok">ok</span>' if rc == 0 else '<span class="v-bad">attention</span>')
    have_goose = bool(shutil.which("goose"))

    used = sorted({r["value"] for r in roles if r["value"]})
    datalist = ('<datalist id="models-in-use">'
                + "".join(f'<option value="{html.escape(u)}">' for u in used) + "</datalist>")

    rows = []
    for r in roles:
        rows.append(
            f'<div class="row"><label for="m_{r["key"]}">{html.escape(r["key"])}</label>'
            f'<span class="hint">{html.escape(r["hint"])}</span>'
            f'<input id="m_{r["key"]}" name="model_{html.escape(r["key"])}" list="models-in-use" '
            f'value="{html.escape(r["value"])}" placeholder="model id" autocomplete="off"></div>'
        )

    svg = roster_svg()
    roster_html = ""
    if svg:
        roster_html = (
            "<h2>The agent roster</h2>"
            '<p class="sub">Every model-backed agent, by pipeline stage. Terracotta means you set the '
            "model; the developer is bring-your-own, and the developer differs from the test agents.</p>"
            f'<div class="roster">{svg}</div>'
        )

    banner_html = ""
    if banner:
        cls, msg = banner
        banner_html = f'<div class="result {cls}">{html.escape(msg)}</div>'

    with _RUNS_LOCK:
        active = any(r["status"] == "running" for r in _RUNS)
    refresh = '<meta http-equiv="refresh" content="4">' if active else ""

    return (
        "<!doctype html><html><head><meta charset=utf-8>"
        '<meta name=viewport content="width=device-width,initial-scale=1">'
        f"{refresh}"
        f"<title>ASDD setup: {html.escape(os.path.basename(repo_dir_for(config)) or config)}</title>"
        f"<style>{shared_css()}{LOCAL_CSS}</style></head><body><div class=wrap>"
        "<h1>ASDD setup</h1>"
        f'<p class="sub">Assign a model to each agent role for <code>{html.escape(config)}</code>, '
        "and run one. Local and private: this writes your config and runs Goose on your machine.</p>"
        f'<div class="tiles">'
        f'<div class="tile"><div class="n">{n_set}/{len(roles)}</div><div class="l">roles set</div></div>'
        f'<div class="tile"><div class="n">{hetero}</div><div class="l">heterogeneity</div></div>'
        "</div>"
        f"{banner_html}"
        '<form method="post" action="/save" class="save">'
        f'<input type="hidden" name="token" value="{html.escape(token)}">'
        "<h2>Agent roles</h2>"
        '<p class="sub">The developer is bring-your-own; the test roles MUST use a different model from it. '
        "Type any model your provider serves - ASDD is provider-neutral and ships no catalogue; the "
        "suggestions are the models you have already used here.</p>"
        f"{datalist}"
        + "".join(rows) +
        "<div><button type=submit>Save and validate</button></div>"
        "</form>"
        "<h2>Run an agent</h2>"
        '<p class="sub">Runs `goose run` on this machine, on the model, endpoint and key this role '
        "resolves to. It opens no PR and merges nothing: the agent proposes, the gates review, you merge.</p>"
        + agents_html(config, have_goose).replace("__TOKEN__", html.escape(token)) +
        "<h2>Recent runs</h2>"
        + runs_html() +
        "<h2>Heterogeneity check</h2>"
        f"<pre>{html.escape(check_out or 'not configured yet')}</pre>"
        "<h2>Next steps</h2>"
        f"<pre>{steps_html(roles, config)}</pre>"
        f"{roster_html}"
        "<footer>Writes the models block of your .asdd.yml, and runs Goose - nothing else. "
        "It never merges.</footer>"
        "</div></body></html>"
    )


def make_handler(config, token):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, body, code=200):
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body.encode("utf-8"))

        def _form(self):
            length = int(self.headers.get("Content-Length", 0))
            return parse_qs(self.rfile.read(length).decode("utf-8"))

        def do_GET(self):
            if self.path.rstrip("/") in ("", "/"):
                self._send(render(config, token))
            else:
                self._send("<p>not found</p>", 404)

        def do_POST(self):
            path = self.path.rstrip("/")
            if path not in ("/save", "/run"):
                self._send("<p>not found</p>", 404)
                return
            form = self._form()
            if form.get("token", [""])[0] != token:  # CSRF guard: only our own page may act
                self._send(render(config, token,
                                  ("bad", "Rejected: stale or missing form token. Reload the page.")), 403)
                return
            if path == "/save":
                assignments = {k[len("model_"):]: v[0] for k, v in form.items() if k.startswith("model_")}
                status, out = apply_assignments(config, assignments)
                banner = {
                    "saved": ("ok", "Saved. Heterogeneity check passed."),
                    "invalid": ("bad", "Saved, but the heterogeneity check failed - see below."),
                    "refused": ("bad", "Nothing was written. " + out),
                }[status]
            else:
                role = form.get("role", [""])[0]
                params = {k[len("p_"):]: v[0] for k, v in form.items() if k.startswith("p_")}
                ok, msg = start_run(role, config, params)
                banner = ("ok" if ok else "bad", msg)
            self._send(render(config, token, banner))

        def log_message(self, *_):  # keep the console quiet
            pass

    return Handler


def main():
    args = sys.argv[1:]
    config = os.path.join(os.getcwd(), ".asdd.yml")
    port = 8787
    do_render = "--render" in args
    no_open = "--no-open" in args
    it = iter(args)
    for a in it:
        if a == "--config":
            config = next(it, config)
        elif a == "--port":
            port = int(next(it, port))
        elif a in ("--render", "--no-open"):
            continue
        elif a in ("-h", "--help"):
            sys.stdout.write(__doc__)
            return 0
        elif a.startswith("-"):
            sys.stderr.write(f"setup-dashboard: unknown option {a}\n")
            return 2
        else:
            config = a

    if os.path.basename(config) == sg.EXAMPLE_BASENAME:
        sys.stderr.write(f"setup-dashboard: {sg.EXAMPLE_BASENAME} is the published template, not your "
                         "config.\nPoint at your repo's .asdd.yml (--config PATH).\n")
        return 2
    if not os.path.exists(config):
        sys.stderr.write(f"setup-dashboard: config not found: {config}\n"
                         "Run `asdd init --goose <repo>` first, or pass --config PATH.\n")
        return 2

    if do_render:
        sys.stdout.write(render(config, "render-token"))
        return 0

    token = secrets.token_urlsafe(24)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(config, token))
    url = f"http://127.0.0.1:{server.server_port}/"
    sys.stdout.write(f"ASDD setup dashboard: {url}\nConfiguring {config}. Ctrl-C to stop.\n")
    if not no_open:
        try:
            webbrowser.open(url)
        except Exception:  # noqa: BLE001 - a headless box just prints the URL
            pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stdout.write("\nstopped.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
