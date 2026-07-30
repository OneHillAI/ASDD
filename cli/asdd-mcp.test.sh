#!/usr/bin/env sh
# Smoke test for asdd-mcp.py: drive the MCP handshake + a few tool calls over stdio and
# check the responses. Exit 0 iff all expected results appear.
DIR=$(dirname "$0")
out=$(printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
 '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"merge_eligibility","arguments":{"paths":["crypto/aes.py"],"protected":"**/crypto/**","auto_merge_class":"**/*.py","posture":"earned-automerge"}}}' \
 '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"spec_check","arguments":{"spec":{"ready":true,"spec":{"outcomes":["x"],"scope":{"in":["y"]},"constraints":["z"],"verification":["w"]}}}}}' \
 '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"spec_check","arguments":{"spec":{"ready":true,"spec":{"outcomes":["x"],"scope":{"in":[]},"constraints":[],"verification":[]}}}}}' \
 '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"openspec_gate","arguments":{"change":"no-such-change"}}}' \
 | python3 "$DIR/asdd-mcp.py")
fail=0
echo "$out" | grep -q 'asdd-gates'          || { echo "FAIL: initialize"; fail=1; }
echo "$out" | grep -q 'merge_eligibility'   || { echo "FAIL: tools/list"; fail=1; }
echo "$out" | grep -q 'openspec_gate'       || { echo "FAIL: openspec_gate not listed"; fail=1; }
echo "$out" | grep -q 'human-approve'       || { echo "FAIL: protected path not human-approve"; fail=1; }
echo "$out" | grep -q 'verdict: ready'      || { echo "FAIL: good spec not ready"; fail=1; }
echo "$out" | grep -q 'verdict: blocked'    || { echo "FAIL: forced-ready not blocked"; fail=1; }
# A bogus change proves the tool DISPATCHES, deterministically either way: with the openspec binary it
# validates to `not-ready` (the change has no deltas); without it, `setup-error` (exit 3). Neither
# spec_check call above yields either verdict, so seeing one uniquely means openspec_gate ran.
# openspec-gate.test.sh covers the JSON-verdict logic itself.
echo "$out" | grep -Eq 'verdict: (setup-error|not-ready)' || { echo "FAIL: openspec_gate did not dispatch"; fail=1; }
[ "$fail" = "0" ] && { echo "asdd-mcp self-test: PASS"; exit 0; } || { echo "asdd-mcp self-test: FAIL"; exit 1; }
