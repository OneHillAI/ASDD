# Guide: the governance dashboard

A thin, read-only view of an ASDD project's governance state. GitHub shows you a raw list of pull
requests; this curates the ASDD-specific view: PRs bucketed by governance stage (awaiting review, in
progress, changes requested, recently merged), by lane, with the `asdd/intake` and `asdd/review`
verdicts where the token can read them, plus the intake queue, contributors, and releases. Each PR also
shows its declared target version, and a suggested next-release section groups the open PRs by version.
It renders one self-contained HTML page and writes nothing back to the repo.

## Run it

```bash
GITHUB_TOKEN=<read-only token> python3 cli/dashboard.py --repo OWNER/REPO --out dashboard.html
```

The token needs read access to the repo's pull requests and releases. The page is a single file with no
external assets. Options:

- `--from snapshot.json` renders offline from a saved snapshot instead of fetching (the same shape the
  live fetch builds: `{"repo","pulls","releases","statuses"}`).
- `--intake DIR` includes a local intake queue (the `*.json` spec objects the pipeline writes).
- `--json` prints the computed model instead of HTML, for piping into your own view.

## As sensitive as the repo it reports on

Everything on the page comes from the repo it reports on, so its sensitivity follows the repo's. The
default is the careful reading.

### Private repo: internal only

This is the default, and it covers most adopters. PR titles, authors, verdicts, contributors and the
configuration are private activity. So:

- Open it locally, or serve it from an internal host **behind authentication**.
- **Never publish it to a public URL, and never commit it to a public repo.**
- Generating it in the **private repo's own CI** is fine: those artifacts reach only people who can
  already read the repo. What is not fine is moving the output somewhere wider, such as a public Pages
  site, a public repo, or a shared bucket.

The page carries a visible internal banner and `noindex,nofollow,noarchive`, so an accidental exposure is
not indexed. That is a mitigation, not a control: keeping the URL private is still on you.

### Public repo: publishable, and it is the demo

If the repo is public, every fact the page renders is **already readable on GitHub by anyone**, so
publishing it discloses nothing new. Render it for publication with `--public`:

```bash
GITHUB_TOKEN=<read-only token> python3 cli/dashboard.py --repo OWNER/REPO --public --out dashboard.html
```

That drops the internal banner and lets the page be indexed. The flag is **verified, not trusted**: with
`--repo` it asks the API and **refuses if the repo is private**, and unknown visibility counts as private.
The exception cannot be taken by mistake.

A public project running ASDD on itself is the strongest demonstration of it: every pull request carrying
a disclosure trailer, passing intake, getting a real review verdict, merged by a human. Publish it **once
the review lenses are live** (see the runtime credential below). A dry-run page advertises the gap instead
of the pipeline: the model lenses read `skipped`, which is the opposite of the point.

Credential-shaped values in the config panel are redacted, but a credential should not be in `.asdd.yml`
at all. Model names belong there; keys belong in your runtime's keyring or a CI secret.

### Publishing the audit ledger: aggregates only

The audit ledger is different from the rest of the page. It comes from a sink that **must be private**, and
its records hold per-agent reasoning. So a ledger never reaches a public page in full: `--public` with a
`--ledger` refuses. To publish it, add `--public-metrics`, which renders the ledger as **aggregate counts
only**, per-role action counts, the verdict mix, and the chain state, and never a single record's
reasoning, payload, or paths:

```bash
GITHUB_TOKEN=<read-only token> python3 cli/dashboard.py --repo OWNER/REPO \
  --ledger /path/to/synced-sink/ledger --public --public-metrics --out governance.html
```

This is whitelist-by-construction: the projection computes named aggregates, it does not filter a rendered
detail page, so a field added to a record later cannot leak into the public view. It lets a project show
its governance throughput and verdict mix publicly while the ledger content stays private.

For a project whose docs already deploy to GitHub Pages, the shipped `docs-deploy` workflow generates this
page into the site (at `/governance.html`) when `AUDIT_SINK_TOKEN` is set, on each docs change and daily.
The sink is cloned to a temp directory and never published; only the aggregate page is written into the
site.

## Keep it current

Regenerate on a schedule, on a host your admins can reach. A **private** repo can do it in CI and keep
the result as a repo-scoped artifact:

```yaml
- run: GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }} python3 cli/dashboard.py --repo ${{ github.repository }} --out dashboard.html
- uses: actions/upload-artifact@v4
  with: { name: asdd-dashboard, path: dashboard.html, retention-days: 7 }
```

On a **public** repo, run it outside public CI (a cron on an internal host) so the output never becomes
publicly downloadable.

## Declaration check

Each PR declares a change scope (normative or non-normative). The dashboard reads the paths a PR changes
and applies the same normative-path rule the impact gate uses, then flags any PR declared non-normative
that in fact edits the standard's normative text. Those show a "scope mismatch" in the Target column and
are listed under "Declaration check". The impact gate already blocks such a PR from merging; this surface
makes the misclassification visible at a glance rather than only on the PR itself. It mirrors the gate's
deterministic path rule; a behavioural mismatch that only a model surfaces is enforced at the gate, not
re-shown here.

## Suggested next release

A normative change declares a target version in its PR (the impact lens checks it). The dashboard reads
that declaration from the PR body and shows it as a Target column on each PR, then groups the open PRs
that share a version under a "Suggested next release" heading, so you can see what an upcoming release
would contain in one place. An open PR that declares a normative change but names no version is listed
under "No target version" so the gap is visible.

This is a suggestion, not an action. The tool assigns nothing, tags no release, and edits no changelog.
Grouping a release stays a human act: you review the proposed grouping and decide. The section is built
so an assistant could propose a grouping here later, but it makes no such call today.

## What it is not

It is read-only and advisory. It never merges, comments, or changes anything; it reflects the state the
gates and humans produced. The verdict columns degrade to `-` when the token cannot read commit statuses,
so the core view (PRs by stage, lanes, releases, contributors) works with a minimal token.

Next: [how it works](../concepts/how-it-works.md) · [adopt the govern layer](adopt-govern.md)
