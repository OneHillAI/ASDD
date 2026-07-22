#!/usr/bin/env sh
# Test for setup-goose.py: a heterogeneity-violating assignment fails, a valid one
# passes and is written back, and --show reads without changing. Exit 0 iff all hold.
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
fail=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/.asdd.yml"
cp "$ROOT/.asdd.example.yml" "$CFG"

# 1. developer == test_author must fail (exit 1).
if python3 "$DIR/setup-goose.py" "$CFG" --set developer=m1 --set test_author=m1 --set test_runner=m2 --no-validate >/dev/null 2>&1; then
  : # --no-validate skips the check, so this run should succeed; use a validating run instead
fi
if python3 "$DIR/setup-goose.py" "$CFG" --set developer=m1 --set test_author=m1 --set test_runner=m2 >/dev/null 2>&1; then
  echo "FAIL: developer == test_author was accepted"; fail=1
fi

# 2. A valid, distinct roster passes (exit 0) and is written back.
if python3 "$DIR/setup-goose.py" "$CFG" --set developer=m1 --set test_author=m2 --set test_runner=m3 >/dev/null 2>&1; then
  grep -q 'test_author: "m2"' "$CFG" || { echo "FAIL: assignment not written"; fail=1; }
else
  echo "FAIL: a valid roster was rejected"; fail=1
fi

# 3. --show reads without error and does not alter the file.
before=$(cat "$CFG")
python3 "$DIR/setup-goose.py" "$CFG" --show >/dev/null 2>&1 || { echo "FAIL: --show errored"; fail=1; }
[ "$before" = "$(cat "$CFG")" ] || { echo "FAIL: --show changed the file"; fail=1; }

# 4. An unknown role is rejected (exit 2).
python3 "$DIR/setup-goose.py" "$CFG" --set nonsense=x >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL: unknown role not rejected"; fail=1; }

# 5. With no path arg, it targets the CURRENT directory's .asdd.yml (adopter's repo),
#    not the ASDD checkout that ships the tool.
ADOPT=$(mktemp -d); cp "$ROOT/.asdd.example.yml" "$ADOPT/.asdd.yml"
( cd "$ADOPT" && python3 "$DIR/setup-goose.py" --set developer=x --set test_runner=y >/dev/null 2>&1 )
grep -q 'test_runner: "y"' "$ADOPT/.asdd.yml" || { echo "FAIL: default did not target the current repo"; fail=1; }
rm -rf "$ADOPT"

# 6. A credential is refused (exit 2) and never written: .asdd.yml is version-controlled.
python3 "$DIR/setup-goose.py" "$CFG" --set documentation=sk-ant-api03-SECRETVALUE >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL: an API key was not refused"; fail=1; }
grep -q 'SECRETVALUE' "$CFG" && { echo "FAIL: a refused key was written to the config"; fail=1; }

# 7. The published template is never written.
python3 "$DIR/setup-goose.py" "$ROOT/.asdd.example.yml" --set developer=x >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL: .asdd.example.yml was not refused"; fail=1; }

# 8. High precision: real model ids must never be mistaken for credentials.
python3 - "$DIR" <<'PY' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sg", sys.argv[1] + "/setup-goose.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for good in ["claude-opus-4-8", "gpt-4o", "qwen3:8b", "llama-3.3-70b", "mistral-large",
             "meta-llama/Meta-Llama-3.1-70B-Instruct",
             "accounts/fireworks/models/llama-v3p1-70b-instruct", "gpt-oss-120b", ""]:
    assert not m.looks_like_credential(good), f"false positive on model id: {good}"
for bad in ["sk-ant-api03-abc123", "ghp_16C7e42F292c6912E7710c838347Ae178B4a",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "AIzaSyD-aBcDeFgHiJkLmNoPqRsTuVwXyZ12345",
            "xoxb-123-456-abcdef", "hf_AbCdEfGhIjKlMnOpQrStUvWxYz1234567890"]:
    assert m.looks_like_credential(bad), f"missed a credential shape: {bad}"
print("credential-shape ok")
PY

# 7. --spec-tool writes spec_tool; an invalid value is refused (exit 2); --show reflects it.
python3 "$DIR/setup-goose.py" "$CFG" --spec-tool openspec --no-validate >/dev/null 2>&1
grep -q '^spec_tool: openspec' "$CFG" || { echo "FAIL: --spec-tool openspec not written"; fail=1; }
python3 "$DIR/setup-goose.py" "$CFG" --spec-tool bogus --no-validate >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL: invalid spec_tool not refused"; fail=1; }
python3 "$DIR/setup-goose.py" "$CFG" --show 2>/dev/null | grep -qi 'spec_tool.*openspec' || { echo "FAIL: --show omits spec_tool"; fail=1; }
# It inserts the key when absent (a hand-written config without spec_tool).
NOSPEC=$(mktemp -d); grep -v '^spec_tool:' "$ROOT/.asdd.example.yml" > "$NOSPEC/.asdd.yml"
python3 "$DIR/setup-goose.py" "$NOSPEC/.asdd.yml" --spec-tool openspec --no-validate >/dev/null 2>&1
grep -q '^spec_tool: openspec' "$NOSPEC/.asdd.yml" || { echo "FAIL: spec_tool not inserted when absent"; fail=1; }
python3 -c "import yaml,sys; yaml.safe_load(open('$NOSPEC/.asdd.yml'))" || { echo "FAIL: insert produced invalid YAML"; fail=1; }
rm -rf "$NOSPEC"

[ "$fail" = "0" ] && { echo "setup-goose self-test: PASS"; exit 0; } || { echo "setup-goose self-test: FAIL"; exit 1; }
