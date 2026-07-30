# Contribution lanes for an operated project

Every PR carries exactly one **lane** label, and the intake gate enforces it. Lanes are
config-driven: the accepted set is the `lanes:` list in your `.asdd.yml`, so you can adopt any
taxonomy you like. This guide covers the default the **operate kit** ships and why.

## Two defaults, by layer

- **Plain `asdd init`** (the govern layer on its own) scaffolds the **conventional** set:
  `feature`, `fix`, `docs`, `chore`. Good when you just want governed contributions and lane by change
  type.
- **`asdd init --goose`** (the full operate kit) scaffolds the **architecture-aligned** set, because a
  project running the whole ASDD-with-Goose stack organises its work by architectural area:

  | Lane | ASDD area | What lands here |
  |---|---|---|
  | `govern` | Govern | the gates, review lenses, merge authority, intake, CODEOWNERS |
  | `operate` | Operate | the recipes and roster, the MCP bridge, the setup wizard, the operate guard |
  | `know` | Know | knowledge grounding, wiki / OKGF integration |
  | `assure` | Assure | tests, the validation suite, model-heterogeneity checks, attestation |
  | `standard` | Standard | the standard, spec, conformance |
  | `docs` | Docs | documentation and guides |
  | `chore` | (trivial) | CI, tooling, dependencies |

The ASDD project's own repository keeps the conventional lanes for its own development; the
architecture taxonomy is what the operate kit recommends for the projects it sets up. The two are
independent on purpose.

## It is a superset default: trim it

Not every project uses every lane. A project with no knowledge layer will never lane a PR `know`; one
that is not authoring a standard will not use `standard`. That is fine: the set is a starting point,
not a mandate. Delete the lanes you do not use from your `.asdd.yml`, or replace the whole list with
your own. Keep `chore` if you want the trivial-change escape that the intake gate exempts from the
spec-driven requirement.

## Overriding

```yaml
# .asdd.yml
lanes:
  - govern
  - operate
  - assure
  - docs
  - chore
```

Whatever the list says is what the intake gate accepts. If you change it, update your repository's
lane labels to match (the `asdd init` step prints the labels to create, or re-run it).
