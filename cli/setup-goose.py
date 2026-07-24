#!/usr/bin/env python3
"""setup-goose - guided per-role model wiring for "ASDD with Goose".

`init --goose` scaffolds the files; this walks you through the one part that is
easy to get wrong: assigning a model to each agent role, keeping the developer
distinct from the test models (the heterogeneity invariant). It writes the
`models:` block of `.asdd.yml`, validates the result with cli/check-models.sh
(the single source of truth for the rule, so this stays correct as the roster
evolves), then prints the exact next steps: `goose configure`, the CI secrets,
and the per-recipe run commands with your chosen models.

It reads the roles from the config's own `models:` block and uses each role's
inline comment as the prompt hint, so a new or renamed role needs no change here.

    python3 cli/setup-goose.py                         # interactive (models + spec tool)
    python3 cli/setup-goose.py --spec-tool openspec    # set the spec tool non-interactively
    python3 cli/setup-goose.py --set test_author=gpt-x --set test_runner=llama-y
    python3 cli/setup-goose.py --show                  # print the current assignments + steps only

Zero-dependency (stdlib). Exit 0 on success (config valid), 1 if the resulting
assignment breaks the heterogeneity rule, 2 on a usage / config error.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # cli/
ROOT = os.path.dirname(HERE)                                # repo root
CHECK_MODELS = os.path.join(HERE, "check-models.sh")

ROLE_LINE = re.compile(r"^(?P<indent>\s+)(?P<key>[A-Za-z_][A-Za-z0-9_]*):"
                       r"(?P<gap>[ \t]*)(?P<val>\"[^\"]*\"|'[^']*'|[^#\n]*?)"
                       r"(?P<pad>[ \t]*)(?P<comment>#.*)?$")

# The published template. It is not a deployment's config, so we never write it.
EXAMPLE_BASENAME = ".asdd.example.yml"

# .asdd.yml is version-controlled: a credential written here lands in git history,
# where deleting it does not undo the exposure. This block holds MODEL NAMES only.
# Keys belong in Goose's own config/keyring (`goose configure`) locally, or in the
# CI secret ASDD_RUNTIME_TOKEN. These prefixes are the common credential shapes;
# matching is deliberately high-precision so a real model id is never refused.
KEY_PREFIXES = ("sk-", "sk_", "ghp_", "gho_", "ghs_", "github_pat_", "xoxb-", "xoxp-",
                "xoxa-", "xoxs-", "aiza", "akia", "ya29.", "eyj", "hf_", "gsk_", "r8_",
                "bearer ", "glpat-", "dop_v1_")


def looks_like_credential(value):
    """True if value has the shape of an API key/token rather than a model id.

    Model ids are short, or use `/`, `.` or `:` separators (org/model, family:size).
    A long separator-free run mixing case and digits is a token, not a model."""
    s = (value or "").strip()
    if not s:
        return False
    if any(s.lower().startswith(p) for p in KEY_PREFIXES):
        return True
    if (len(s) >= 40 and re.fullmatch(r"[A-Za-z0-9_-]+", s)
            and any(c.isupper() for c in s) and any(c.islower() for c in s)
            and any(c.isdigit() for c in s)):
        return True
    return False


CREDENTIAL_HELP = (
    "Refusing to write it: {path} is version-controlled, so a key committed here stays in git history "
    "even if you delete it later. The models block takes MODEL NAMES only.\n"
    "Put the credential where it belongs instead:\n"
    "  locally   goose configure          (Goose keeps it in its own config/keyring)\n"
    "  in CI     ASDD_RUNTIME_TOKEN       (a repository secret, with ASDD_MODEL_URL / ASDD_MODEL)\n"
)


def read_lines(path):
    if not os.path.exists(path):
        sys.stderr.write(f"setup-goose: config not found: {path}\n"
                         "Run `asdd init --goose <repo>` first to scaffold it.\n")
        sys.exit(2)
    with open(path, encoding="utf-8") as fh:
        return fh.read().splitlines()


def models_region(lines):
    """Return (start, end) line indices of the `models:` block body, exclusive of
    the header and stopping at the next top-level key."""
    start = None
    for i, line in enumerate(lines):
        if line.rstrip() == "models:":
            start = i + 1
            break
    if start is None:
        sys.stderr.write("setup-goose: no `models:` block in the config.\n")
        sys.exit(2)
    end = len(lines)
    for i in range(start, len(lines)):
        if lines[i] and not lines[i][0].isspace():   # next top-level key
            end = i
            break
    return start, end


def parse_roles(lines, start, end):
    """List of {key, value, hint, idx} for each role line in the models block."""
    roles = []
    for i in range(start, end):
        m = ROLE_LINE.match(lines[i])
        if not m:
            continue
        raw = m.group("val").strip().strip("\"'")
        comment = (m.group("comment") or "").lstrip("#").strip()
        roles.append({"key": m.group("key"), "value": raw, "hint": comment, "idx": i})
    return roles


def set_value(line, new_value):
    """Rewrite one role line with new_value, preserving indent, key and comment."""
    m = ROLE_LINE.match(line)
    indent, key, gap, comment = m.group("indent"), m.group("key"), m.group("gap"), m.group("comment")
    body = f'{indent}{key}:{gap or " "}"{new_value}"'
    if comment:
        return f"{body}  {comment}"
    return body


SPEC_TOOLS = ("builtin", "openspec")


def current_spec_tool(lines):
    """The spec_tool value in the config, or None if the key is absent (defaults to builtin)."""
    for line in lines:
        m = re.match(r"^spec_tool:\s*(\S+)", line)
        if m:
            return m.group(1)
    return None


def set_spec_tool(lines, value):
    """Set spec_tool to value: update the existing line, or insert one before spec_paths (or after
    the models block) if the key is absent. Returns the modified lines list."""
    for i, line in enumerate(lines):
        if re.match(r"^spec_tool:\s*", line):
            lines[i] = f"spec_tool: {value}"
            return lines
    # Absent: insert. Prefer just before spec_paths so the two spec settings sit together.
    for i, line in enumerate(lines):
        if re.match(r"^spec_paths:\s*", line):
            lines[i:i] = ["# Spec tool: builtin (ASDD definition of ready) or openspec (openspec validate).",
                          f"spec_tool: {value}", ""]
            return lines
    lines.append(f"spec_tool: {value}")
    return lines


def prompt_spec_tool(current):
    cur = current or "builtin"
    print("\nSpec tool: which validator decides a change's spec is ready?")
    print("  builtin  - ASDD's definition of ready (outcomes / scope / constraints / verification)")
    print("  openspec - delegate to OpenSpec's `openspec validate` (Fission-AI/openspec)")
    try:
        ans = input(f"  spec tool [{cur}]> ").strip().lower()
    except EOFError:
        ans = ""
    return ans or cur


def run_check(path, strict):
    argv = ["bash", CHECK_MODELS] + (["--strict"] if strict else []) + [path]
    p = subprocess.run(argv, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def deployment_run_commands(roles_by_key, recipe_dir):
    """One `goose run` line per deployment recipe whose role has a model set.
    Recipe <name>.yaml maps to role <name with - as _> (test-runner -> test_runner)."""
    out = []
    if not os.path.isdir(recipe_dir):
        return out
    for fn in sorted(os.listdir(recipe_dir)):
        if not fn.endswith(".yaml") or fn == "developer.yaml":
            continue
        role = fn[:-5].replace("-", "_")
        model = roles_by_key.get(role, "")
        if not model:
            continue
        out.append(f"  goose run --recipe recipes/{fn} --model {model}")
    return out


def print_steps(roles, recipe_dir):
    by_key = {r["key"]: r["value"] for r in roles}
    print("\nNext steps")
    print("  1. Connect the providers for the models you named:")
    print("       goose configure")
    reviewer = by_key.get("reviewer", "")
    print("  2. Wire the CI review runtime (Settings > Secrets and variables > Actions):")
    print("       ASDD_RUNTIME_TOKEN   (secret)    your model API key")
    print("       ASDD_MODEL_URL       (variable)  full .../v1/chat/completions URL")
    print(f"       ASDD_MODEL           (variable)  the reviewer model"
          f"{' (' + reviewer + ')' if reviewer else ''}")
    print("  3. Give your agents their own GitHub identity, so they open PRs you approve:")
    print("       a bot account with a fine-grained token (simplest for one person),")
    print("       or a GitHub App (scoped, revocable). You cannot approve your own PRs,")
    print("       so your agents must not open them as you, or the merge gate is unsatisfiable.")
    print("       The token is a host env var for produce-loop agents, a repo secret for CI agents.")
    print("       Walk-through: docs/guides/using-asdd-solo.md")
    runs = deployment_run_commands(by_key, recipe_dir)
    if runs:
        print("  4. Run each deployment agent with its model:")
        for r in runs:
            print(r)
    else:
        print("  4. Set the deployment role models above to get ready-to-run commands.")
    print("  5. Prove the gates run with no keys:")
    print("       sh cli/asdd-mcp.test.sh")


def prompt_roles(roles):
    print("Assign a model to each agent role. Enter keeps the current value.")
    print("The developer is bring-your-own; the test roles MUST use a different model.\n")
    for r in roles:
        hint = f"  ({r['hint']})" if r["hint"] else ""
        cur = f" [{r['value']}]" if r["value"] else " [unset]"
        try:
            ans = input(f"  {r['key']}{cur}{hint}\n    model> ").strip()
        except EOFError:
            ans = ""
        if ans:
            r["value"] = ans
    return roles


def apply_sets(roles, sets):
    by_key = {r["key"]: r for r in roles}
    for pair in sets:
        if "=" not in pair:
            sys.stderr.write(f"setup-goose: --set expects role=model, got '{pair}'\n")
            sys.exit(2)
        key, val = pair.split("=", 1)
        key = key.strip()
        if key not in by_key:
            sys.stderr.write(f"setup-goose: unknown role '{key}'. Roles: {', '.join(by_key)}\n")
            sys.exit(2)
        by_key[key]["value"] = val.strip()
    return roles


def prompt_dev_council(lines):
    """Optional, opt-in: offer to configure the developer council and append a dev_council block if the
    operator wants it and none exists. The single-model developer stays the default. Returns True if it
    changed `lines`."""
    if any(l.rstrip() == "dev_council:" for l in lines):
        print("\nDeveloper council: already configured (dev_council in .asdd.yml); edit it there to change.")
        return False
    print("\nDeveloper council (optional): 2 to 5 diverse models propose, cross-critique, synthesise and")
    print("verify one implementation of an OpenSpec change. The single-model developer stays the default.")
    try:
        if input("  configure it now? [y/N]> ").strip().lower() not in ("y", "yes"):
            return False
        raw = input("  council models, comma-separated (2 to 5; the LAST is the lead synthesiser)\n    models> ").strip()
    except EOFError:
        return False
    models = [m.strip() for m in raw.split(",") if m.strip()]
    if not (2 <= len(models) <= 5):
        print("  need 2 to 5 models; leaving the council unconfigured (set dev_council in .asdd.yml later).")
        return False
    lines.extend(["",
                  "# Developer council (optional; `asdd dev-council`). 2 to 5 diverse models; the LAST is the lead.",
                  "dev_council:", "  models:"]
                 + [f'    - "{m}"' for m in models]
                 + ["  max_critique_rounds: 1", "  max_refine_rounds: 1"])
    print(f"  added a dev_council block with {len(models)} models.")
    return True


def main():
    args = sys.argv[1:]
    sets = []
    spec_tool_arg = None
    show = "--show" in args
    no_validate = "--no-validate" in args
    rest = []
    it = iter(args)
    for a in it:
        if a == "--set":
            sets.append(next(it, ""))
        elif a.startswith("--set="):
            sets.append(a[len("--set="):])
        elif a == "--spec-tool":
            spec_tool_arg = next(it, "")
        elif a.startswith("--spec-tool="):
            spec_tool_arg = a[len("--spec-tool="):]
        elif a in ("--show", "--no-validate"):
            continue
        elif a in ("-h", "--help"):
            sys.stdout.write(__doc__)
            return 0
        elif a.startswith("-"):
            sys.stderr.write(f"setup-goose: unknown option {a}\n")
            return 2
        else:
            rest.append(a)
    # Default to the .asdd.yml of the repo you are in, not the ASDD checkout that
    # ships this tool, so an installed `asdd setup` configures the current project.
    config = rest[0] if rest else os.path.join(os.getcwd(), ".asdd.yml")
    # Recipes live in the configured repo (init --goose copies them there); fall
    # back to the ASDD checkout's own recipes when the target has none.
    repo_recipes = os.path.join(os.path.dirname(os.path.abspath(config)), "recipes")
    recipe_dir = repo_recipes if os.path.isdir(repo_recipes) else os.path.join(ROOT, "recipes")

    # The example is the published template, not a deployment's config.
    if os.path.basename(config) == EXAMPLE_BASENAME:
        sys.stderr.write(f"setup-goose: {EXAMPLE_BASENAME} is the published template, not your config.\n"
                         "Point at your repo's .asdd.yml (run `asdd init --goose <repo>` if it has none).\n")
        return 2

    lines = read_lines(config)
    start, end = models_region(lines)
    roles = parse_roles(lines, start, end)
    if not roles:
        sys.stderr.write("setup-goose: the models block has no role entries.\n")
        return 2

    changed = False
    spec_tool_new = None
    if show:
        print(f"Current model assignments in {config}:")
        for r in roles:
            print(f"  {r['key']:<14} {r['value'] or '(unset)'}")
        print(f"  {'spec_tool':<14} {current_spec_tool(lines) or 'builtin (default)'}")
    elif sets:
        apply_sets(roles, sets)
        changed = True
    elif sys.stdin.isatty():
        prompt_roles(roles)
        spec_tool_new = prompt_spec_tool(current_spec_tool(lines))
        prompt_dev_council(lines)   # opt-in; appends a dev_council block if wanted
        changed = True
    else:
        print(f"Current model assignments in {config} (no tty; pass --set to change):")
        for r in roles:
            print(f"  {r['key']:<14} {r['value'] or '(unset)'}")

    # --spec-tool sets it non-interactively and overrides an interactive answer.
    if spec_tool_arg is not None:
        spec_tool_new = spec_tool_arg.strip().lower()
    if spec_tool_new is not None and spec_tool_new not in SPEC_TOOLS:
        sys.stderr.write(f"setup-goose: spec_tool must be one of {', '.join(SPEC_TOOLS)}.\n")
        return 2
    apply_spec_tool = spec_tool_new is not None and spec_tool_new != (current_spec_tool(lines) or "builtin")
    if apply_spec_tool:
        changed = True

    if changed:
        # Never let a credential reach a version-controlled file. Covers --set and the
        # interactive prompt in one place, and refuses BEFORE anything is written.
        leaked = [r["key"] for r in roles if looks_like_credential(r["value"])]
        if leaked:
            sys.stderr.write(f"setup-goose: that looks like an API key, not a model name "
                             f"({', '.join(leaked)}).\n" + CREDENTIAL_HELP.format(path=config))
            return 2
        for r in roles:
            lines[r["idx"]] = set_value(lines[r["idx"]], r["value"])
        if apply_spec_tool:
            set_spec_tool(lines, spec_tool_new)
        with open(config, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"Wrote model assignments to {config}.")
        if apply_spec_tool:
            print(f"Set spec_tool to {spec_tool_new}.")
            if spec_tool_new == "openspec":
                print("  OpenSpec chosen: install it where the gate runs "
                      "-> npm install -g @fission-ai/openspec")

    print_steps(roles, recipe_dir)

    # WARN if the reviewer got a heavy reasoning model: it can exceed a hosted inference window on a real
    # code diff and time out with no lenses, while trivial diffs pass. Canonical check: cli/doctor.py
    # check_reviewer_reasoning. Advisory; setup still succeeds.
    reasoning_hints = ("glm", "deepseek-r1", "deepseek_r1", "deepseek-reasoner", "reasoner", "qwq",
                       "-thinking", "thinking-", "magistral", "o1-", "o1@", "o3-", "o3@", "o4-", "minimax-m1")
    rev = next((r["value"] for r in roles if r["key"] == "reviewer"), "")
    if rev and any(h in rev.lower() for h in reasoning_hints):
        print(f"\nWARNING: models.reviewer ({rev}) looks like a reasoning model. A reasoning model can "
              "exceed a hosted inference window on a real code diff and time out with no lenses, while "
              "trivial diffs still pass. Prefer a faster non-reasoning reviewer.")

    rc = 0
    if not no_validate:
        code, out = run_check(config, strict=changed)
        print("\nHeterogeneity check (cli/check-models.sh):")
        for line in out.splitlines():
            print(f"  {line}")
        if code != 0:
            rc = 1
        # The unmissable step: a roster names the models, but every agent DRY-RUNS until a model runtime
        # is connected. A deployment can look set up while no agent does real work (a review comes back a
        # placeholder, not a real review). Surface the connection status here, at the end of setup.
        cc = subprocess.run(["python3", os.path.join(HERE, "connect-check.py"), config, "--no-ping"],
                            capture_output=True, text=True)
        print("\n" + cc.stdout.strip())
        if cc.returncode != 0:
            print("\nNext: connect a model runtime so the agents run live, then verify with `asdd "
                  "connect-check`:\n  ASDD_MODEL_URL (variable) = your provider's .../v1/chat/completions"
                  "\n  ASDD_RUNTIME_TOKEN (secret) = your API key   (or the per-role / __COUNCIL_<i> variants)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
