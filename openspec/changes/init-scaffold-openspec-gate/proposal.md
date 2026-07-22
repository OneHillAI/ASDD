## Why

`asdd init --goose` scaffolds the operate kit into an adopter repo, including the deterministic gates and
the MCP extension (`asdd-mcp.py`). But the `--goose` copy list omits `openspec-gate.py` and its helper
`_openspec_locate.py`. The MCP `openspec_gate` tool shells to the sibling `openspec-gate.py`, which imports
`_openspec_locate.py`, so for a `spec_tool: openspec` adopter the tool has no file to call. The pair must
travel with `asdd-mcp.py`.

## What Changes

- Add `openspec-gate.py` and `_openspec_locate.py` to the `init --goose` copy list, unconditionally (not
  gated on `spec_tool: openspec`, since a repo can flip to OpenSpec after init).
- Add a scaffold-test assertion that both files land.

## Impact

- Affected specs: init-scaffold
- Affected code: `cli/init.sh` (the `--goose` copy loop), `cli/init.test.sh`.
- Depends on #12 (merged): `cli/_openspec_locate.py` now exists on main and `openspec-gate.py` imports it.
