# Guide: the agent audit ledger

`STANDARD.md` 1.3 requires that every agent action is recorded: the agent identity, the action, the target,
the authorizing decision, and a timestamp, retained and reviewable. The ledger is how that is satisfied, and
it is also the substrate for the knowledge base and for training a model on your own project.

It is a **record, never a gate**. Nothing in it approves, blocks, or merges.

## What a record holds

One append-only JSON record per agent action:

- **Who**: agent identity, role, lens, the model and provider it ran on, and the accountable human.
- **What**: the action, and the target (repo, pull request, commit, paths).
- **Under what authority**: the authorizing decision that permitted the action.
- **When**: a timestamp, plus the run, pull request, and commit lineage.
- **Why**: the agent's stated reasoning.
- **What it caused**: the verdict and the action it led to (a comment, a status, a block).
- **Role payload**: the lens findings, the tests written, the results, the docs touched, the labels applied,
  the merge verdict and its deciding rule.

Reviewed content is **not** copied in. A record carries `inputs_digest`, a hash of what the agent saw.

## Which roles emit

The govern layer emits automatically for the review lenses (code, security, spec, quality, impact) and the
overall review outcome. **The operate agents record through the run wrapper, `asdd operate-run`**, not by
calling a command themselves. The agent writes its outcome to `.asdd-work/operate-result.json`, and the
wrapper turns that into exactly one ledger record. This is deliberate: an agent that recorded itself as
its last step lost the action whenever a long run was interrupted (a provider timeout mid-run is common),
and the record is the one thing you cannot afford to lose. With the wrapper, even a run that produced no
result is recorded, marked incomplete, so nothing is silently dropped.

The shipped recipes are already wired: the **test author** records each test and the spec requirement it
covers, the **test runner** records what it ran and the result, the **documentation** agent records the
documents it touched and why, and the **interaction** agent records each spec readiness decision (as role
`spec`). `cli/recipe-lint.py` enforces that each writes a result, so a recipe cannot quietly stop
recording.

Two are deliberately not wired. The **public** interaction recipe never records: it is execution-free by
design, and an untrusted surface able to author records would let anyone who can send a message write
into the trail. The **merge reviewer** emits with `--role merge` where a project runs one; merge review is
not wired into CI here, so nothing emits it yet.

Your own agents call the helper the same way:

```bash
python3 cli/audit.py append --ledger .asdd-work/audit.jsonl \
  --role test-runner --action tests.run --verdict fail --action-taken block \
  --reasoning "2 tests failed in the payments suite" \
  --payload-json '{"tested":"unit","passed":10,"failed":2}'
```

## Where it is hosted

**ASDD hosts nothing.** Records are produced inside your own pipeline and exported to a sink **you own**. No
data leaves your control by default (`sink: none`).

Set the `audit:` block in `.asdd.yml`:

```yaml
audit:
  sink: repo                                  # none | repo | command
  sink_repo: "your-org/your-project-ledger"   # MUST be private
  retention_days: 0
```

- **`repo`** (reference binding): appends to a **private sibling repository**. No extra infrastructure, and
  Git supplies append-only ordering, access control, and retention. Needs an `AUDIT_SINK_TOKEN` secret with
  write access to that repo.
- **`command`**: bring your own sink. `sink_command` receives the ledger path as `$1`, so you can ship to an
  object store, a database, or your own knowledge platform.
- **`none`** (default): nothing is exported and the pipeline is unchanged.

Two refusals are hard, and both fail loudly rather than exporting:

1. The sink must **not be the repository being governed**. The ledger describes that repo; publishing it
   there would leak the trail into the thing it audits.
2. The sink must **not be public**, and unprovable visibility is treated as public. The ledger is as
   sensitive as the code it describes.

## Set up the `repo` sink, step by step

1. **Create the private ledger repository.** A separate repo, set to **private**. Give it **one commit**
   (a `README`, say): a completely empty repo has no default branch, and the export's clone-append-push
   needs one.
2. **Create a fine-grained token** scoped to only that repo. On GitHub: Settings, Developer settings,
   Fine-grained tokens, Generate. Set the resource owner to whoever owns the ledger repo, restrict
   repository access to the ledger repo alone, and grant **Repository permissions, Contents: Read and
   write** (write to push records, read to confirm the repo is private before writing). Copy the token,
   GitHub shows it once.
3. **Add the token as a secret on the governed repository** (the repo ASDD runs in), **not** on the
   ledger repo. Settings, Secrets and variables, Actions, New repository secret. Name it exactly
   `AUDIT_SINK_TOKEN`; the value is the token from step 2.
4. **Point the config at the sink.** In `.asdd.yml`, set `audit.sink: repo` and
   `audit.sink_repo: owner/your-ledger-repo`.
5. **Verify before you rely on CI.** Ship a throwaway record from your machine, then check the ledger repo
   for `ledger/<year>/<month>.jsonl`:

   ```bash
   python3 cli/audit.py append --ledger /tmp/ping.jsonl --role documentation --action sink.ping \
     --authorizing-decision "sink setup check" --reasoning "verifying the sink is reachable"
   AUDIT_SINK_TOKEN=<your token> asdd audit-ship /tmp/ping.jsonl
   ```

   A green run appends the record and reports it. A misconfiguration (wrong repo, a public destination, a
   missing or under-scoped token) refuses and says which. From then on, the CI review path ships on its
   own, and a local operate or developer run ships with `asdd audit-ship .asdd-work/audit.jsonl`.

## Why the credential is where it is

Records are emitted by the **read-only** analysis job, which writes only to the run directory and holds no
sink credential. The **write-scoped** publish job exports them, and reads only ASDD-produced records, never
untrusted pull-request content. So a fork's input is never handled in a job holding your sink token. This is
the same split that keeps the review pipeline safe.

## Integrity

Records are chained: each carries the hash of the one before it and its own. An edit or a deletion breaks
the chain.

```bash
python3 cli/audit.py verify --ledger path/to/audit.jsonl
```

Each CI run stages a genesis-rooted batch locally, and the export re-anchors it onto the sink's current
tip (`audit.py graft`) before appending, so the accumulated sink is one continuous chain across runs,
files, and months, not a pile of genesis-rooted batches with a break at every seam. `verify` accepts the
whole sink (a directory) as well as a single file.

What the chain detects: any edit to a record, any reordering, and any deletion of a record that is not the
most recent, including of a whole month file (its successor is orphaned). What a hash chain alone cannot
detect is truncation of the tail, removing the most recent records, because nothing after them points
back. Detecting that needs an external anchor (a recorded tip and count, or a signature); it is a planned
hardening, not something this chain provides today.

The export refuses to ship a batch it cannot graft, and the dashboard shows the chain state rather than
presenting a tampered trail as fact.

## Where you see it

Point the dashboard at the ledger. It takes a single `.jsonl` file, or a **directory** of them, which is
what a synced sink looks like (`ledger/<year>/<month>.jsonl`):

```bash
# a single run's records
python3 cli/dashboard.py --repo OWNER/REPO --ledger path/to/audit.jsonl --out dashboard.html

# the accumulated ledger: sync your sink first, then point at it
git clone --depth 50 https://github.com/your-org/your-project-ledger /tmp/ledger
python3 cli/dashboard.py --repo OWNER/REPO --ledger /tmp/ledger/ledger --out dashboard.html
```

Reading a directory keeps the hash chain continuous across month and year boundaries, so a break anywhere
in the accumulated trail is still detected.

The dashboard does **not** fetch from your sink itself and holds no sink credential. It stays read-only and
credential-free, so you sync the sink with whatever you already use (a clone, a bucket sync, a mount) and
point at the result. That keeps the write credential in the one place that needs it, the export step.

It renders an **Agent activity** section: what each role did, how many actions, which lenses, the spread of
verdicts, and the most recent actions with the verdict, what it led to, and why. The dashboard is internal
by default; host it behind authentication.

**A page carrying the ledger cannot be published.** `--public` refuses when a ledger (or a local intake
queue) is loaded, because that content comes from outside the reported repository: the ledger's sink is
required to be private, so the repository being public says nothing about whether the ledger may be
published. Render the internal page with the ledger, or the public page without it. There is deliberately
no filtered middle ground yet: a public projection would need to be computed from the ledger as explicit
aggregates rather than filtered out of the rendered page, so that a field added later cannot leak by
default.

## A note on what is safe to share

The corpus and knowledge views are derived from the ledger, which is exported only to a private sink. That
private boundary is what makes them safe. A record's `reasoning` is the agent's own words and the training
signal, and for a review lens it summarises the finding, so it is dual-use: fine inside your own private
corpus, sensitive the moment anything is shared. The corpus view already drops finding text and code paths
from the payload and target for this reason. Any future shared or public projection must go further and
carry only counts and categoricals, never `reasoning` and never a finding message: a whitelist built from
the ledger, not the detailed records filtered after the fact, so a field added later cannot leak by
default.

## What it feeds

One event stream, three views. The ledger is the raw record; the other two are derived from it and read
either a single `.jsonl` or a synced sink directory.

- **Governance**: the ledger itself, the evidence for 1.3, reviewable and tamper-evident.
- **Training and tuning** (`asdd audit corpus`): a clean JSONL of your project's decisions, one example
  per record, keeping the role, reasoning, action and outcome and dropping the chain plumbing. Content
  safety is by construction: the record already holds a digest of what the agent saw rather than the
  content, and the corpus additionally reduces the payload to counts and categoricals (how many findings,
  which severities, which rules) and the target to refs, so a finding's message or a code path never
  reaches a training export. Restrict to roles with `--role`.

  ```bash
  asdd audit corpus --ledger /path/to/synced-sink/ledger > corpus.jsonl
  ```

- **The knowledge base** (`asdd audit knowledge`): curated entries in the knowledge layer's shape (an
  invariant, a rejected approach, an exemplar), selected from the records that carry durable knowledge; a
  one-off like a test run yields nothing. The entries are emitted in [OKGF](https://github.com/OneHillAI/OKGF)
  shape.

  ```bash
  asdd audit knowledge --ledger /path/to/synced-sink/ledger > knowledge.jsonl
  ```

  A note on scope: this **writes** the entries; ingesting them into a running knowledge store is the
  remaining step, and it is deliberately left to a store that has an ingest path. OKGF today is a format
  and a spec, not a deployed store, so the entries are captured in the right shape now and loaded when a
  store exists.

Next: [the governance dashboard](governance-dashboard.md) - [gates and requirements](gates-and-requirements.md)
