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

rm -rf "$T"
echo
[ "$fail" = 0 ] && echo "connect-check self-test: PASS" || echo "connect-check self-test: FAIL"
exit "$fail"
