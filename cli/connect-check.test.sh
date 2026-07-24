#!/usr/bin/env bash
# Self-test for connect-check (cli/connect-check.py). Deterministic and network-free: it uses --no-ping,
# so it exercises the per-role config-completeness classification and the loud "not connected" summary
# without calling a model.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="$HERE/connect-check.py"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

T="$(mktemp -d)"
cat > "$T/.asdd.yml" <<'YML'
models:
  developer: ""
  reviewer: "r:1"
  test_author: "t:1"
  test_runner: "t:1"
  documentation: "d:1"
  interaction: "i:1"
YML

# 1. No runtime connected -> every role DRY, non-zero, and the loud unmissable summary.
out="$(env -u ASDD_MODEL_URL -u ASDD_RUNTIME_TOKEN python3 "$CC" "$T/.asdd.yml" --no-ping 2>&1)"; rc=$?
printf '%s' "$out" | grep -q "DRY" && [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "DRY-RUN and do no real work" \
  && ok "no runtime -> loud dry-run report, non-zero" || bad "dry-run report (rc=$rc): $out"

# 2. Runtime present -> roles READY (config complete), exit zero.
out="$(ASDD_MODEL_URL=https://x/v1/chat/completions ASDD_RUNTIME_TOKEN=y python3 "$CC" "$T/.asdd.yml" --no-ping 2>&1)"; rc=$?
printf '%s' "$out" | grep -q "READY" && [ "$rc" -eq 0 ] \
  && ok "runtime present -> ready, zero" || bad "ready path (rc=$rc): $out"

# 3. No model in the roster at all -> guidance, non-zero.
printf 'models:\n  developer: ""\n' > "$T/empty.yml"
out="$(python3 "$CC" "$T/empty.yml" --no-ping 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "No role has a model" \
  && ok "no models -> guidance, non-zero" || bad "no-models path (rc=$rc)"

# 4. The developer council's members are checked too when configured.
printf '\ndev_council:\n  models: [a:1, b:2, c:3]\n' >> "$T/.asdd.yml"
out="$(ASDD_MODEL_URL=https://x/v1 ASDD_RUNTIME_TOKEN=y python3 "$CC" "$T/.asdd.yml" --no-ping 2>&1)"
printf '%s' "$out" | grep -q "council\[1\]" \
  && ok "council members are checked when configured" || bad "council not checked: $out"

# 5. Reasoning-model parameter fallback (mocked, no network): a 400 naming max_completion_tokens must
#    retry the ping with the renamed parameter and succeed; a normal model still uses max_tokens, no retry.
if python3 - "$CC" <<'PY'
import importlib.util, urllib.request, urllib.error, io, sys
spec = importlib.util.spec_from_file_location("cc", sys.argv[1])
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
class Resp:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *a): return False
    def read(self): return b'{"choices":[{"message":{"content":"ok"}}]}'
def err():
    b = b'{"error":{"message":"Unsupported parameter: max_tokens is not supported with this model. Use max_completion_tokens instead."}}'
    return urllib.error.HTTPError("u", 400, "bad request", {}, io.BytesIO(b))
calls = []
def fake(req, timeout=None):
    p = req.data.decode(); calls.append(p)
    if '"max_tokens"' in p:
        raise err()
    return Resp()
urllib.request.urlopen = fake
ok, why = cc.ping("m", "https://x/v1/chat/completions", "t")
assert ok, ("reasoning model reported dead", why)
assert any('"max_completion_tokens"' in c for c in calls), "did not retry with the renamed parameter"
calls.clear()
urllib.request.urlopen = lambda req, timeout=None: (calls.append(req.data.decode()) or Resp())
ok, why = cc.ping("m", "https://x/v1/chat/completions", "t")
assert ok and len(calls) == 1 and 'max_completion_tokens' not in calls[0], "normal model path changed"
PY
then ok "reasoning-model max_completion_tokens fallback (mocked)"; else bad "reasoning-model max_completion_tokens fallback"; fi

rm -rf "$T"
echo
[ "$fail" = 0 ] && echo "connect-check self-test: PASS" || echo "connect-check self-test: FAIL"
exit "$fail"
