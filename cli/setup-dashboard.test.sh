#!/usr/bin/env sh
# Test for setup-dashboard.py: --render produces the page (roles + form + token),
# the write path validates the heterogeneity rule, and model input is sanitised.
# The live server + CSRF token are exercised by a manual smoke, not here (no ports
# in CI). Exit 0 iff all deterministic checks hold.
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/.asdd.yml"; cp "$ROOT/.asdd.example.yml" "$CFG"

# 1. --render shows the roles, the form and the CSRF token field.
out=$(python3 "$DIR/setup-dashboard.py" --render --config "$CFG" 2>/dev/null)
echo "$out" | grep -q 'name="model_developer"'   || { echo "FAIL: render missing developer field"; fail=1; }
echo "$out" | grep -q 'name="model_test_author"' || { echo "FAIL: render missing test_author field"; fail=1; }
echo "$out" | grep -q 'name="token"'             || { echo "FAIL: render missing token field"; fail=1; }
echo "$out" | grep -q 'ASDD setup'               || { echo "FAIL: render missing title"; fail=1; }
# Combobox (datalist), not a fixed dropdown, and the roster diagram is embedded.
echo "$out" | grep -q '<datalist id="models-in-use"' || { echo "FAIL: render missing model datalist"; fail=1; }
echo "$out" | grep -q 'list="models-in-use"'         || { echo "FAIL: inputs not wired to the datalist"; fail=1; }
echo "$out" | grep -q 'The agent roster'             || { echo "FAIL: render missing roster section"; fail=1; }
echo "$out" | grep -q '<svg'                         || { echo "FAIL: roster diagram not embedded"; fail=1; }

# 2. The write path: distinct models validate; a test model equal to the developer fails.
python3 - "$DIR" "$CFG" <<'PY' || fail=1
import importlib.util, sys
d, cfg = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("sd", d + "/setup-dashboard.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

st, _ = m.apply_assignments(cfg, {"developer": "A", "test_author": "B", "test_runner": "C"})
assert st == "saved", f"distinct roster should save, got {st}"
st, _ = m.apply_assignments(cfg, {"test_author": "A"})    # now equals developer 'A'
assert st == "invalid", f"developer == test_author should be invalid, got {st}"
assert m.clean_model('a"b\nc') == "abc", "model input not sanitised"

# A credential must be REFUSED and must not reach the version-controlled file.
st, msg = m.apply_assignments(cfg, {"documentation": "sk-ant-api03-SECRETVALUE"})
assert st == "refused", f"a key should be refused, got {st}"
assert "SECRETVALUE" not in open(cfg).read(), "a refused key was written to the config"
assert "goose configure" in msg, "refusal should point at where the key belongs"
print("write-path ok")
PY

# 3. The written config kept the distinct-then-conflicting values (round-trips through .asdd.yml).
grep -q 'developer: "A"' "$CFG" || { echo "FAIL: assignment not persisted"; fail=1; }

# 4. The executor: allow-list, fixed argv, server-side resolution.
python3 - "$DIR" "$CFG" <<'PY' || fail=1
import importlib.util, sys, os
d, cfg = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("sd", d + "/setup-dashboard.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

# The allow-list is derived from disk + the roster, never from a request.
roles = [r for r, _ in m.launchable(cfg)]
assert "documentation" in roles, f"documentation should be launchable, got {roles}"
assert "developer" not in roles, "the developer is bring-your-own and must not be launchable"
assert "setup" not in roles, "the setup agent is a conversation, not a job"
assert "interaction_public" not in roles, "the public recipe has no roster key of its own"

# A role that is not on the allow-list is refused, including a traversal attempt.
for hostile in ["../../etc/passwd", "developer", "nonsense", "", "documentation; rm -rf /"]:
    ok, msg = m.start_run(hostile, cfg, {})
    assert not ok, f"start_run accepted a non-allow-listed role: {hostile!r}"

# The argv is a LIST (never a shell string), and a hostile param cannot become a command.
argv = m.build_run_argv("/repo/recipes/documentation.yaml", "opus-4-8", {"change_ref": "PR 1; rm -rf /"})
assert isinstance(argv, list) and argv[0] == "goose" and argv[1] == "run", argv
assert "--recipe" in argv and "/repo/recipes/documentation.yaml" in argv, argv
assert "--params" in argv and "change_ref=PR 1; rm -rf /" in argv, argv
assert not any(";" in a for a in argv[:6]), "the fixed part of the argv must not carry a payload"

# Params are allow-listed to what the recipe declares.
keys = m.recipe_params(os.path.join(m.recipe_dir_for(cfg), "documentation.yaml"))
assert "change_ref" in keys and "instructed_by" in keys, keys

# The endpoint/key mapping splits a URL the way Goose's openai provider expects.
env = m.run_env("https://runware.ai/v1/chat/completions", "NOPE_UNSET")
assert env["OPENAI_HOST"] == "https://runware.ai", env["OPENAI_HOST"]
assert env["OPENAI_BASE_PATH"] == "v1/chat/completions", env["OPENAI_BASE_PATH"]
print("executor ok")
PY

# 5. The page offers the run surface and inlines the SHARED stylesheet (not its own copy).
out=$(python3 "$DIR/setup-dashboard.py" --render --config "$CFG" 2>/dev/null)
echo "$out" | grep -q 'Run an agent'        || { echo "FAIL: render missing the run surface"; fail=1; }
echo "$out" | grep -q 'action="/run"'       || { echo "FAIL: render missing the run form"; fail=1; }
marker=$(head -2 "$ROOT/cli/dashboard.css" | grep -o 'ASDD dashboard stylesheet' | head -1)
echo "$out" | grep -q "$marker"             || { echo "FAIL: page does not inline the shared stylesheet"; fail=1; }

[ "$fail" = "0" ] && { echo "setup-dashboard self-test: PASS"; exit 0; } || { echo "setup-dashboard self-test: FAIL"; exit 1; }
