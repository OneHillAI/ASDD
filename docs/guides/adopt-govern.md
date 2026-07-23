# Guide: adopt the govern layer

The govern layer is the CI gates: the deterministic intake gate and the split review/publish pipeline.
This is the part that makes a project ASDD-conformant. The operate layer (the agents) sits on top and is
covered by [operate-goose](operate-goose.md) and [operate-other](operate-other.md).

## Scaffold it

Install the CLI, then scaffold your repo:

```bash
pip install git+https://github.com/OneHillAI/ASDD
asdd init /path/to/your-repo
```

Or run `bash cli/init.sh /path/to/your-repo` from a checkout.

It writes [`AGENTS.md`](https://github.com/OneHillAI/ASDD/blob/main/AGENTS.md) (the constitution), `.asdd.yml` (config), the PR template (the
disclosure block), and `CODEOWNERS` from your protected paths, and ensures the lane labels. Add `--goose`
to also install the operate kit. Preview with `--dry-run`; overwrite with `--force`. Existing files are
skipped unless forced, so it will not clobber a customised repo.

To do it by hand instead:

1. Copy `.github/asdd/` and the workflows (`asdd-intake.yml`, `pr-review.yml`, `pr-review-publish.yml`)
   into your repo.
2. Set up your lane labels, or adapt the defaults in `.asdd.yml`.
3. Add `CODEOWNERS` entries for your protected paths.
4. The intake gate runs immediately on the next PR. The review pipeline runs in dry-run until a model is
   wired (below).

## Declare your protected paths

Protected paths are where a defect is high-impact: auth, crypto, CI/release config, dependency
manifests, data-handling, and the governance docs themselves. A change touching one is always
human-approved, and the [`merge-eligibility`](https://github.com/OneHillAI/ASDD/blob/main/cli/merge-eligibility.py) gate enforces that a
protected path can never reach an autonomous merge even if the auto-merge class is misconfigured. Set
them in `.asdd.yml` and mirror them in `CODEOWNERS`.

## Enforce it (the switch from advisory to enforced)

This is the last-mile step, and it is easy to miss. On a fresh repository branch protection is off, so the
gates are **advisory**: intake, `asdd/review`, and a Code Owner review all report, but a green check does
not block a merge and nothing stops a direct push to the default branch. The gates only **enforce** once
branch protection requires them. Until you do this, an adopter or their agent can merge past a red gate.

On your default branch (Settings, Branches, add a branch protection rule), turn on:

1. **Require status checks to pass before merging**, and select both required checks by name:
   - `intake` (the deterministic intake gate)
   - `asdd/review` (the commit status the publish job sets from the review; a security block or a
     request-changes turns it red)
2. **Require a pull request before merging**, and **require review from Code Owners**, so a change to a
   protected path needs a named human owner (this is what makes `CODEOWNERS` bite).
3. **Block direct pushes** to the default branch (the pull-request requirement does this) and do not allow
   bypassing the above, so the gates apply to everyone, maintainers included.

Because a protected-path change needs a named human **other than the author**, and GitHub blocks
self-approval, your agents must open PRs under **their own identity** (a bot account or a GitHub App), not
your account. Otherwise you cannot approve your own agents' PRs and the merge gate is unsatisfiable,
especially as one person. See [using ASDD as one person](using-asdd-solo.md) for the identity setup.

Optionally require branches to be up to date before merging. It is stricter but means an out-of-date PR
must be rebased before it can merge; leave it off if you prefer fewer rebases.

Until these are on, treat every green check as information, not a gate.

## Wire a live model (optional)

Until a runtime is connected the review pipeline runs in dry-run: the deterministic gates and the
security lens still bite, but the model lenses stay off. To turn them on, set the runtime inputs your
adapter reads (a token, an OpenAI-compatible URL, and a model name; see the reference adapter and
[agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md)). Any OpenAI-compatible provider works, and the adapter is
pluggable via `runtime/<name>.sh`.

Set the URL to the full chat-completions endpoint (for example `.../v1/chat/completions`), not the base
(`.../v1`). The reference adapter POSTs to the URL verbatim, so a base URL sends the request to the wrong
path, the review comes back empty, and the gate fails closed to "a human should review" with no surfaced
cause. Failing closed is correct; the silent part is what costs a debugging cycle, so get the full path
right at the point you set the value.

The analysis job holds `contents: read` only, at all times. The write scope stays in the publish job,
which never reads untrusted PR content. **Do not merge the two jobs**, since that split is the security
invariant.

## Verify it conforms

Check yourself against [CONFORMANCE.md](https://github.com/OneHillAI/ASDD/blob/main/CONFORMANCE.md). A conformant project runs the intake gate
on every PR (maintainers included), requires disclosure, keeps the write scope isolated in the publish
job, routes publish actions through a policy decision point that denies merge, and never suppresses a
security finding without a visible comment.

Next: [run the agents with Goose](operate-goose.md), [run them on your own runtime](operate-other.md)
