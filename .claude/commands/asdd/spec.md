---
description: Turn an idea into a spec object that passes the intake gate
---
Turn the request below into a spec object for this project.

$ARGUMENTS

Fill every field ASDD's definition of ready requires: `outcomes`, `scope` (in and out), `constraints`
(including prior decisions), and `verification` (how "done" is checked). If you cannot fill one, say so
and ask the specific question rather than inventing it.

Write it where this project keeps specs. Read `spec_paths:` in `.asdd.yml` and follow it: that list is
what the intake gate matches against, so a spec written anywhere else fails the gate however good it is.
The default is `docs/specs/<slug>.md`.

Then check it with `asdd spec-check <path>`. That is the same gate the pipeline runs, so a spec that
passes here passes on the PR.

If the project already uses a spec tool (OpenSpec, Spec Kit), use its output rather than writing a
second spec beside it: run that tool, then make sure `spec_paths:` covers where it writes (for OpenSpec,
`openspec/changes/*/specs/**/*.md`). ASDD requires that a spec exists and that the change is checked
against it, not that a particular tool produced it.
