# Spec: architecture-aligned contribution lanes for the operate kit

## Problem

Lanes (the one-per-PR contribution tag the intake gate enforces) are config-driven: the accepted set is
the `lanes:` list in `.asdd.yml`. The conventional default (`feature/fix/docs/chore`) fits a project
that lanes by change type, but a project running the full ASDD-with-Goose stack organises its work by
architectural area (Govern, Know, Operate, Assure), and has no built-in way to adopt lanes that mirror
that structure. The operate kit should offer an architecture-aligned default without imposing it on the
ASDD project's own repository, which keeps the conventional set.

## Requirements

- `asdd init --goose` scaffolds the operate taxonomy into the target's `.asdd.yml` `lanes:` list:
  `govern`, `operate`, `know`, `assure`, `standard`, `docs`, `chore`, and creates the matching labels.
- Plain `asdd init` (govern layer only) keeps the conventional `feature/fix/docs/chore` set unchanged.
- The taxonomy is a superset starting point: an adopter may trim or override it in `.asdd.yml`. `chore`
  stays as the spec-exempt trivial lane. This is documented.
- The change touches only the `--goose` operate path; `.asdd.example.yml` and the ASDD project's own
  `.asdd.yml` are not modified.

## Acceptance criteria

- `asdd init --goose` on a fresh repo produces a `.asdd.yml` whose lanes include `govern`, `operate` and
  `assure`; plain `asdd init` produces one whose lanes include `feature` and none of the operate lanes.
- `asdd init --goose` copies every deployment recipe the kit ships (a guard against the recipe list
  drifting out of sync with `recipes/`, which had silently broken `--goose`).
- The behaviour is covered by `cli/init.test.sh` and runs in `validation/run-base.py`.

## Out of scope

- Changing the ASDD project's own lanes or the conventional default for plain `init`.
- Any change to the intake gate, which already reads the accepted lanes from `.asdd.yml`.
