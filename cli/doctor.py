#!/usr/bin/env python3
"""asdd doctor - a preflight for the Goose operate path.

Most setup failures live in the gap between "configured" and "actually works": a tool is installed but
not on PATH, a spec tool is selected but its CLI is unreachable, a roster is written but violates the
one hard rule. A bare `which` reports "missing" for a tool that is merely off-PATH, and the config gates
only see the config, not the runtime around it. This command checks the environment the way an adopter
needs it checked and, crucially, distinguishes:

  - reachable            (OK)
  - installed, off PATH  (WARN, with the exact path and the line to add)  <- the trap this exists to name
  - absent               (FAIL only when the config actually requires it)

It never mutates anything (no installs, no PATH edits): it reports state and the precise next step.

Exit code: 1 if any hard requirement for THIS config is unmet (a selected spec CLI is absent, or the
roster breaks heterogeneity); otherwise 0. Warnings and info never fail, so `asdd doctor` is safe to run
anywhere, and useful in CI as a gate when you want it to be.

Zero-dependency (stdlib).
"""
import argparse
import os
import shutil
import subprocess
import sys

from _openspec_locate import locate

HERE = os.path.dirname(os.path.realpath(__file__))          # cli/ - the kit's own tools live here
PINNED_OPENSPEC = "1.6.0"                                    # the version cli/openspec-gate.py is pinned to

OK, WARN, FAIL, INFO = "OK", "WARN", "FAIL", "INFO"
_GLYPH = {OK: "OK  ", WARN: "WARN", FAIL: "FAIL", INFO: "INFO"}


class Report:
    def __init__(self):
        self.rows = []          # (status, title, detail, fix)
        self.hard_fail = False

    def add(self, status, title, detail="", fix=""):
        self.rows.append((status, title, detail, fix))
        if status == FAIL:
            self.hard_fail = True

    def render(self):
        out = ["asdd doctor - operate-path preflight", ""]
        for status, title, detail, fix in self.rows:
            out.append(f"  [{_GLYPH[status]}] {title}")
            if detail:
                out.append(f"         {detail}")
            if fix:
                out.append(f"         fix: {fix}")
        n_fail = sum(1 for r in self.rows if r[0] == FAIL)
        n_warn = sum(1 for r in self.rows if r[0] == WARN)
        out.append("")
        if n_fail:
            out.append(f"RESULT: NOT READY - {n_fail} blocking issue(s), {n_warn} warning(s).")
        elif n_warn:
            out.append(f"RESULT: READY with {n_warn} warning(s) - the operate path will run; address the warnings when you can.")
        else:
            out.append("RESULT: READY - the operate path is set up.")
        return "\n".join(out)


def _cmd_version(argv):
    """Best-effort `<tool> --version`; returns a one-line string or None."""
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=8)
    except Exception:
        return None
    text = (p.stdout or p.stderr or "").strip().splitlines()
    return text[0].strip() if text else None


def _read_scalar(config, key):
    """Read a top-level scalar from .asdd.yml without a YAML dependency (same text-scan as the kit)."""
    try:
        with open(config) as fh:
            for line in fh:
                if line.startswith(f"{key}:"):
                    v = line[len(key) + 1:]
                    v = v.split("#", 1)[0].strip().strip('"').strip("'")
                    return v
    except OSError:
        return None
    return None


def check_python(rep):
    v = sys.version_info
    s = f"{v.major}.{v.minor}.{v.micro}"
    if (v.major, v.minor) >= (3, 9):
        rep.add(OK, f"Python {s}", "the CLI and gates are stdlib-only")
    else:
        rep.add(WARN, f"Python {s}", "the kit targets 3.9+", "install a newer Python 3")


def check_goose(rep):
    exe, on_path = locate("goose")
    if exe and on_path:
        ver = _cmd_version(["goose", "--version"]) or "version unknown"
        rep.add(OK, f"Goose ({ver})", exe)
    elif exe and not on_path:
        rep.add(WARN, "Goose is installed but not on PATH", f"found at {exe}",
                f'add its directory to PATH, e.g. export PATH="{os.path.dirname(exe)}:$PATH"')
    else:
        rep.add(WARN, "Goose not found",
                "needed to RUN the operate agents (developer / test / documentation / interaction); "
                "not needed just to validate config",
                "install Goose: https://block.github.io/goose/")


def check_spec_tool(rep, config):
    tool = (_read_scalar(config, "spec_tool") or "builtin").strip() or "builtin"
    if tool != "openspec":
        rep.add(INFO, f"spec_tool: {tool}", "the built-in definition-of-ready gate; no external CLI needed")
        return
    exe, on_path = locate("openspec")
    if exe is None:
        rep.add(FAIL, "spec_tool: openspec, but the openspec CLI is absent",
                "the openspec readiness gate cannot run locally or in CI without it",
                "npm install -g @fission-ai/openspec  (or set spec_tool: builtin in .asdd.yml)")
        return
    ver = _cmd_version([exe, "--version"])
    where = f"found at {exe}"
    if not on_path:
        rep.add(WARN, "openspec is installed but not on PATH", where,
                f'add it: export PATH="{os.path.dirname(exe)}:$PATH"  '
                "(the gate resolves it anyway; other openspec commands you type will not)")
    elif ver and ver != PINNED_OPENSPEC:
        rep.add(WARN, f"openspec {ver} (the gate is pinned to {PINNED_OPENSPEC})", where,
                f"align the version: npm install -g @fission-ai/openspec@{PINNED_OPENSPEC}")
    else:
        rep.add(OK, f"openspec {ver or PINNED_OPENSPEC}", where)


def check_roster(rep, config):
    checker = os.path.join(HERE, "check-models.sh")
    if not os.path.isfile(checker):
        rep.add(INFO, "roster heterogeneity", "check-models.sh not present; skipped")
        return
    p = subprocess.run(["bash", checker, config], capture_output=True, text=True)
    if p.returncode == 0:
        rep.add(OK, "roster heterogeneity", "developer differs from the test models (or is unset / BYO)")
    else:
        detail = (p.stdout + p.stderr).strip().splitlines()
        why = detail[-1] if detail else "developer must differ from test_author and test_runner"
        rep.add(FAIL, "roster breaks the one hard rule", why,
                "run `asdd setup` and give the test roles a model distinct from the developer")


def check_conventions(rep, config):
    """Brownfield: are the host project's conventions declared, and do they point at real artefacts?"""
    checker = os.path.join(HERE, "conventions-check.py")
    if not os.path.isfile(checker):
        return
    p = subprocess.run(["python3", checker, "--config", config, "--validate"],
                       capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip()
    if "none declared" in out:
        rep.add(INFO, "no conventions declared",
                "the operate agents will follow the patterns they can see; on an EXISTING project, "
                "declaring them stops the agents guessing and producing rework",
                "add a `conventions:` block (see .asdd.example.yml) naming your spec dir, changelog "
                "form, impact log and house style")
    elif p.returncode == 0:
        rep.add(OK, "conventions declared and valid",
                "the operate agents are held to this project's own workflow")
    else:
        detail = "; ".join(line.strip(" []").replace("FAIL ", "")
                           for line in out.splitlines() if "FAIL" in line) or out
        rep.add(FAIL, "conventions block is invalid", detail,
                "fix the declared paths, or remove the field: an unset field is simply not checked")


def check_runtime_key(rep):
    role_keys = [k for k in os.environ if k.startswith("ASDD_RUNTIME_TOKEN")]
    if role_keys:
        rep.add(INFO, "runtime key present in this environment",
                "the CI review lenses can call a model (in CI this is a repo secret, not your shell)")
    else:
        rep.add(INFO, "no runtime key in this environment",
                "expected locally: the CI review lenses dry-run until ASDD_RUNTIME_TOKEN is set as a repo secret")


def check_recipes(rep, config):
    repo = os.path.dirname(os.path.abspath(config)) or "."
    rdir = os.path.join(repo, "recipes")
    if not os.path.isdir(rdir):
        rep.add(INFO, "no recipes/ directory here",
                "govern-only install, or run `asdd init --goose` to add the operate recipes")
        return
    found = sorted(f for f in os.listdir(rdir) if f.endswith(".yaml"))
    if found:
        rep.add(OK, f"{len(found)} operate recipe(s) present", ", ".join(found))
    else:
        rep.add(WARN, "recipes/ is empty", "no operate recipes to run",
                "re-run `asdd init --goose` to scaffold them")


# Model-name fragments for families that reason at length. A reasoning reviewer can exceed a hosted
# inference window on a substantive diff (observed live: a GLM reviewer returns HTTP 500 "inference timed
# out" on a real code diff, while trivial or docs-only diffs pass and look fine), so the review silently
# produces no lenses. Heuristic name match, WARN not FAIL, and it is a property of the MODEL, not the host.
_REASONING_HINTS = ("glm", "deepseek-r1", "deepseek_r1", "deepseek-reasoner", "reasoner", "qwq",
                    "-thinking", "thinking-", "magistral", "o1-", "o1@", "o3-", "o3@", "o4-", "minimax-m1")


def _model_of(config, role):
    """The model for a roster role (models.<role>), read without a YAML dependency (kit text-scan)."""
    inblk = False
    try:
        with open(config) as fh:
            for line in fh:
                s = line.split("#", 1)[0].rstrip()
                if s.strip() == "models:":
                    inblk = True
                    continue
                if inblk:
                    if s and not s[0].isspace():
                        break
                    t = s.strip()
                    if t.startswith(f"{role}:"):
                        return t[len(role) + 1:].strip().strip('"').strip("'")
    except OSError:
        return None
    return None


def check_reviewer_reasoning(rep, config):
    """WARN when the reviewer is a heavy reasoning model, which times out reviewing a real diff."""
    model = _model_of(config, "reviewer")
    if not model:
        return
    if any(h in model.lower() for h in _REASONING_HINTS):
        rep.add(WARN, f"the reviewer looks like a reasoning model ({model})",
                "a reasoning model reasons at length and can exceed a hosted inference window on a real "
                "code diff, so the review times out and posts no lenses while trivial diffs still pass",
                "set models.reviewer to a faster non-reasoning model, or split the review per lens; the "
                "per-call timeout will otherwise fail fast and name this cause")


def main():
    ap = argparse.ArgumentParser(description="Preflight the ASDD Goose operate path.")
    ap.add_argument("config", nargs="?", default=".asdd.yml",
                    help="the .asdd.yml to check (default: ./.asdd.yml)")
    a = ap.parse_args()

    rep = Report()
    if not os.path.isfile(a.config):
        rep.add(FAIL, f"config not found: {a.config}",
                "run this from a repo with an ASDD config",
                "asdd init --goose .   (scaffolds .asdd.yml and the operate kit)")
        print(rep.render())
        return 1

    check_python(rep)
    check_goose(rep)
    check_spec_tool(rep, a.config)
    check_roster(rep, a.config)
    check_reviewer_reasoning(rep, a.config)
    check_conventions(rep, a.config)
    check_runtime_key(rep)
    check_recipes(rep, a.config)

    print(rep.render())
    return 1 if rep.hard_fail else 0


if __name__ == "__main__":
    sys.exit(main())
