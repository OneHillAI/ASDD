#!/usr/bin/env python3
"""ASDD gates as a Goose / MCP extension (v0.1).

A minimal stdio MCP server that exposes the deterministic gates - spec-check,
claim-check, merge-eligibility, audit-check, plus openspec-gate for projects that
use OpenSpec as their spec tool - as MCP tools, so a Goose agent (or any MCP
client) can call them. Zero-dependency (stdlib): newline-delimited JSON-RPC 2.0
over stdio.

Wire into Goose as a stdio extension:

    extensions:
      - type: stdio
        name: asdd-gates
        cmd: python3
        args: ["cli/asdd-mcp.py"]

Validate against your installed Goose / MCP protocol version; this server echoes
the client's requested protocolVersion for maximum compatibility.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))          # cli/
ROOT = os.path.dirname(HERE)                                # repo root
SPEC = os.path.join(HERE, "spec-check.py")
CLAIM = os.path.join(HERE, "claim-check.py")
MERGE = os.path.join(HERE, "merge-eligibility.py")
AUDIT = os.path.join(ROOT, "validation", "audit-check.py")
OPENSPEC = os.path.join(HERE, "openspec-gate.py")
CONV = os.path.join(HERE, "conventions-check.py")

TOOLS = [
    {"name": "spec_check",
     "description": "Definition-of-ready gate for a spec object, plus an independent ready-claim check "
                    "that blocks a forced ready=true. Returns verdict: ready | not-ready | blocked.",
     "inputSchema": {"type": "object", "required": ["spec"], "properties": {
         "spec": {"type": "object", "description": "a spec object or an asdd/intake/v0.1 object"},
         "require": {"type": "string", "description": "comma-separated definition-of-ready fields"}}}},
    {"name": "openspec_gate",
     "description": "Readiness gate for a project whose spec_tool is OpenSpec: delegates to "
                    "`openspec validate` (via cli/openspec-gate.py) and reads the verdict from the JSON, "
                    "never the exit code (which is 0 even on failure). The OpenSpec analogue of "
                    "spec_check. Returns ready | not-ready | setup-error.",
     "inputSchema": {"type": "object", "required": ["change"], "properties": {
         "change": {"type": "string", "description": "the OpenSpec change id to validate"},
         "root": {"type": "string",
                  "description": "the project directory that holds openspec/; default = the current directory"}}}},
    {"name": "claim_check",
     "description": "Claim-protocol decision over a claims ledger: TTL auto-release, one active claim per "
                    "item, per-identity cap. Returns grant | refuse.",
     "inputSchema": {"type": "object", "required": ["ledger", "item", "identity", "now"], "properties": {
         "ledger": {"type": "array", "description": "active claims [{item,identity,created_at}]"},
         "item": {"type": "string"}, "identity": {"type": "string"},
         "now": {"type": "string", "description": "ISO 8601 timestamp"},
         "ready": {"type": "boolean", "description": "is the item's spec ready?"},
         "ttl_hours": {"type": "number"}, "max_per_identity": {"type": "integer"}}}},
    {"name": "merge_eligibility",
     "description": "Deterministic conforming-loader floor: given a change's paths and the merge policy, "
                    "returns human-approve or autonomous-eligible. Protected paths never auto-merge.",
     "inputSchema": {"type": "object", "required": ["paths"], "properties": {
         "paths": {"type": "array", "items": {"type": "string"}},
         "protected": {"type": "string", "description": "comma-separated protected globs"},
         "auto_merge_class": {"type": "string", "description": "comma-separated auto-merge globs"},
         "posture": {"type": "string", "enum": ["advisory", "earned-automerge"]}}}},
    {"name": "audit_check",
     "description": "Evaluate the audit-log properties (P1-P6, P9) over a trail. Reports each ok | FAIL.",
     "inputSchema": {"type": "object", "required": ["trail"], "properties": {
         "trail": {"type": "array", "description": "audit events"},
         "protected": {"type": "string"}, "max_actions": {"type": "integer"}}}},
    {"name": "conventions_check",
     "description": "Hold a change to the HOST project's declared conventions (the `conventions:` block "
                    "in .asdd.yml): changelog fragment vs assembled file, impact-log entry, spec present, "
                    "house style. Judges ONLY the change, never the existing tree, so it is safe on a "
                    "mature repository. Call it BEFORE proposing, to check your own output. With "
                    "contract=true it returns the contract to follow instead of checking. "
                    "Returns conforming | not-conforming.",
     "inputSchema": {"type": "object", "properties": {
         "changed": {"type": "array", "items": {"type": "string"},
                     "description": "paths this change touches"},
         "lane": {"type": "string", "description": "the change's lane label"},
         "config": {"type": "string", "description": "path to .asdd.yml (default: ./.asdd.yml)"},
         "contract": {"type": "boolean",
                      "description": "return the contract to follow instead of checking a change"}}}},
]


def _run(argv):
    p = subprocess.run([sys.executable] + argv, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def _tmp(obj):
    fh = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(obj, fh)
    fh.close()
    return fh.name


def dispatch(name, a):
    if name == "spec_check":
        f = _tmp(a["spec"])
        argv = [SPEC, f] + (["--require", a["require"]] if a.get("require") else [])
        rc, out = _run(argv)
        os.unlink(f)
        verdict = {0: "ready", 1: "not-ready", 2: "blocked"}.get(rc, f"exit {rc}")
        return f"verdict: {verdict}\n{out}"
    if name == "openspec_gate":
        argv = [OPENSPEC, str(a["change"])]
        if a.get("root"):
            argv += ["--root", str(a["root"])]
        rc, out = _run(argv)
        # 0/1/3 mirror openspec-gate.py: ready / not-ready / setup problem (missing binary, drifted
        # schema). A setup error is NOT a spec verdict, so it is surfaced distinctly rather than as a fail.
        verdict = {0: "ready", 1: "not-ready", 3: "setup-error"}.get(rc, f"exit {rc}")
        return f"verdict: {verdict}\n{out}"
    if name == "claim_check":
        f = _tmp(a["ledger"])
        argv = [CLAIM, f, "--now", a["now"], "--item", str(a["item"]), "--identity", str(a["identity"])]
        argv += ["--ready", "true" if a.get("ready", True) else "false"]
        if a.get("ttl_hours") is not None:
            argv += ["--ttl-hours", str(a["ttl_hours"])]
        if a.get("max_per_identity") is not None:
            argv += ["--max-per-identity", str(a["max_per_identity"])]
        rc, out = _run(argv)
        os.unlink(f)
        return f"decision: {'grant' if rc == 0 else 'refuse'}\n{out}"
    if name == "conventions_check":
        argv = [CONV, "--config", str(a.get("config") or os.path.join(ROOT, ".asdd.yml"))]
        if a.get("contract"):
            argv += ["--print-contract"]
            rc, out = _run(argv)
            return out
        if a.get("lane"):
            argv += ["--lane", str(a["lane"])]
        argv += ["--changed"] + [str(p) for p in (a.get("changed") or [])]
        rc, out = _run(argv)
        # 0/1 = a verdict on the change; 2 = the conventions block itself is unusable (a setup problem,
        # surfaced distinctly so an agent does not read a misconfiguration as "your change is fine").
        verdict = {0: "conforming", 1: "not-conforming", 2: "setup-error"}.get(rc, f"exit {rc}")
        return f"verdict: {verdict}\n{out}"
    if name == "merge_eligibility":
        argv = [MERGE]
        if a.get("protected"):
            argv += ["--protected", a["protected"]]
        if a.get("auto_merge_class"):
            argv += ["--auto-merge-class", a["auto_merge_class"]]
        argv += ["--posture", a.get("posture", "advisory")]
        # paths after `--` so a caller-supplied path that looks like a flag (e.g. "--auto-merge-class")
        # cannot be parsed as an option and flip the verdict. The paths come from the tool caller.
        argv += ["--"] + [str(p) for p in a["paths"]]
        rc, out = _run(argv)
        return f"verdict: {'autonomous-eligible' if rc == 3 else 'human-approve'}\n{out}"
    if name == "audit_check":
        f = _tmp(a["trail"])
        argv = [AUDIT, f]
        if a.get("protected"):
            argv += ["--protected", a["protected"]]
        if a.get("max_actions") is not None:
            argv += ["--max-actions", str(a["max_actions"])]
        rc, out = _run(argv)
        os.unlink(f)
        return f"result: {'PASS' if rc == 0 else 'FAIL'}\n{out}"
    raise ValueError(f"unknown tool: {name}")


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def error(mid, code, message):
    send({"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}})


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        method = msg.get("method")
        if method is None:
            continue  # a response to us; ignore
        mid = msg.get("id")
        try:
            if method == "initialize":
                result = {"protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                          "capabilities": {"tools": {}},
                          "serverInfo": {"name": "asdd-gates", "version": "0.1.0"}}
            elif method == "notifications/initialized":
                continue
            elif method == "ping":
                result = {}
            elif method == "tools/list":
                result = {"tools": TOOLS}
            elif method == "tools/call":
                p = msg.get("params", {})
                text = dispatch(p.get("name"), p.get("arguments") or {})
                result = {"content": [{"type": "text", "text": text}], "isError": False}
            else:
                if mid is not None:
                    error(mid, -32601, f"method not found: {method}")
                continue
        except Exception as e:  # noqa: BLE001 - surface any tool error as an MCP error
            if mid is not None:
                error(mid, -32603, str(e))
            continue
        if mid is not None:
            send({"jsonrpc": "2.0", "id": mid, "result": result})


if __name__ == "__main__":
    main()
