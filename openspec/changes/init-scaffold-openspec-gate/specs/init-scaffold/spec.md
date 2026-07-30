## ADDED Requirements

### Requirement: The Goose scaffold ships the OpenSpec gate
`asdd init --goose` SHALL copy `openspec-gate.py` and its helper `_openspec_locate.py` into the adopter's
`cli/` directory, unconditionally, so a `spec_tool: openspec` adopter's MCP `openspec_gate` tool has a file
to call. The two SHALL travel together with `asdd-mcp.py`, since the tool shells to `openspec-gate.py`,
which imports `_openspec_locate.py`.

#### Scenario: A Goose-scaffolded repo has the openspec gate and its helper
- **WHEN** `asdd init --goose` scaffolds a repository
- **THEN** `cli/openspec-gate.py` and `cli/_openspec_locate.py` are present alongside `cli/asdd-mcp.py`

#### Scenario: Copied regardless of the spec tool
- **WHEN** a repository is scaffolded with `--goose` while `spec_tool` is builtin
- **THEN** the openspec gate and its helper are still copied, so a later switch to `spec_tool: openspec`
  works without re-scaffolding
