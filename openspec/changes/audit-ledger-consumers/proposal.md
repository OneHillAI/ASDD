## Why

The audit ledger records agent actions and exports them to a private sink, but the requirement it exists
to serve was broader: gather what every agent does, into one store, to feed a training corpus and a
knowledge base. Three gaps stopped it meeting that.

- **The developer could not be recorded at all.** The role set had no `developer`, so the one agent that
  builds the code, a bring-your-own coding session, had no way into the ledger. A trail meant to cover the
  loop was missing its first step.
- **Only the CI review path reached the store.** The review lenses export automatically, but the operate
  agents wrote records to a local file that nothing shipped, and the developer wrote nothing. "Gather every
  agent" was really "gather the review lenses".
- **Neither consumer existed.** The ledger is described as the substrate for training and knowledge, but
  there was no training export and no knowledge derivation. The two reasons for collecting the data had
  nothing built on the data.

## What Changes

- **`developer` is a recordable role.** It runs as a person's own session rather than a deployment recipe,
  so it records with one append at the end of a build. Every role the loop runs can now be recorded.
- **`asdd audit-ship`** pushes a local ledger (an operate or developer run) to the configured sink, so
  every run path reaches one store, not only CI. The review path already ships.
- **`asdd audit corpus`** emits the training view: one JSONL example per record, keeping role, reasoning,
  action and outcome, dropping the chain plumbing, and never reproducing reviewed content (a record holds
  a digest, so the corpus references what was seen without leaking it).
- **`asdd audit knowledge`** emits the knowledge view: curated entries in the knowledge layer's shape, in
  OKGF form, selected from records that carry durable knowledge.
- Both views read a single `.jsonl` or a synced sink directory (`ledger/<year>/<month>.jsonl`).

Deliberately out of scope, and stated so it is not mistaken for done: **ingesting the knowledge entries
into a running store**. OKGF today is a format and a spec, not a deployed store, so the entries are
captured in the right shape and loaded when a store with an ingest path exists.

## Capabilities

### Modified Capabilities
- `audit-ledger`: the ledger records every role including the developer, ships every run path to one sink,
  and exposes a training view and a knowledge view derived from the same event stream.

## Impact

- `cli/audit.py`: the `developer` role, `corpus` and `knowledge` subcommands, one shared reader for a file
  or a sink directory.
- `asdd_cli.py`: `audit` and `audit-ship`.
- `.asdd.yml`: the sink flipped to the project's private ledger repo.
- Docs: the CLI reference, the reference gate list, the audit ledger guide.
- Tests: `cli/audit.test.sh` covers the developer role and both views, and is now run by the suite.
- Unchanged: the record contract, the chain, the export refusals, and the CI review path.
