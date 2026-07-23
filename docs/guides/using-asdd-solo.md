# Guide: using ASDD as one person

ASDD's merge rule is "agents propose, a human approves and merges." That reads like it needs a team. It
does not. But there is one setup detail a solo maintainer has to get right, or you hit a wall: **you cannot
approve your own pull requests.** GitHub blocks self-approval by design, so if your agents open PRs under
*your* account, nothing you build can ever be approved, and the only way to merge is to bypass your own
gate. This guide fixes that.

## Where the safety comes from when you are alone

The independent review that catches bugs does not come from a second person. It comes from **different
models checking each other**, which works the same whether you are 1 person or 50:

- Your agent builds the change.
- The review lenses review it on a **different model** than your developer.
- The test agents test it on **different models** again.
- The gates enforce disclosure, security, and the spec.
- Then **you** read the result and merge. An agent never merges on its own.

So solo you still get genuine, independent, multi-model review. The human approval is the last step: a
human, not an agent, decides to merge.

## The fix: run your agents under their own identity

Give your agents a GitHub identity that is **not you**. Then a PR belongs to the agent, and you approve and
merge it as the code owner. This is the intended ASDD flow, and it is what makes the human-approval gate
satisfiable for a solo maintainer.

### Lowest friction for a solo maintainer: a bot account

Create a separate GitHub account (a machine user), add it to your repo as a collaborator with write access,
and give it a **fine-grained personal access token** scoped to that repo (Contents, Pull requests, Issues
read and write). The token is long-lived, so there is no minting step: point your agents at it, and PRs are
authored by the bot while you approve them. This is the recommended solo setup because it is the least
moving parts: no private key, no hourly token, nothing to rotate.

### Scoped and revocable: a GitHub App

A GitHub App is the least-privilege, revocable option, which suits a team or a security-conscious setup. It
is more machinery than a bot account, so reach for it when that trade is worth it.

1. **Create it under your org**, not your personal account, or it cannot install on your org's repos:
   `https://github.com/organizations/<ORG>/settings/apps/new`.
2. In the form: turn the **Webhook "Active" checkbox OFF** (no webhook URL needed); the homepage URL is
   arbitrary (your repo URL is fine).
3. **Repository permissions:** Contents read and write, Pull requests read and write, Issues read and write
   (for labels). Add Workflows read only if the agent edits files under `.github/workflows`. Leave the rest
   at No access. Metadata read is automatic.
4. Choose **"Only on this account"** and create it.
5. **Install it** (a separate step after creation): the app's Install App tab, install on your org, and
   select the repo.
6. Generate a **private key** on the app's page. Your agent runtime signs a short-lived installation token
   from it (App ID plus the private key) via the GitHub API; app tokens expire hourly, so the runtime mints
   a fresh one each run and keeps the private key where it can read it. That per-run minting is the friction
   the bot account avoids.

### Where the token lives

Put the token where the agent that opens the PR actually reads it, which depends on where that agent runs:

- **Produce-loop agents run on your host** (your developer, and the developer council). They call the GitHub
  API from your machine, so the identity token is a **host environment variable** the agent reads before it
  opens a PR.
- **CI agents run in Actions** (the review and post-merge agents). For anything they open, the token is a
  **repository secret**.

A solo setup usually needs the host one first, because that is where the produce loop runs.

Either way, the rule is: **the identity that opens the PR must not be the identity that approves it.** Your
own token can still push the branch; it is the identity that opens the pull request that has to differ.

## The minimal fallback: your merge is the approval

If you do not want a second identity at all, you can drop the "requires an approving review" rule and rely
on the required status checks plus your own merge. Nothing merges without you clicking merge, and the gates
(`intake`, `asdd/review`) still block anything that fails. This is weaker than the identity approach, but it
is honest for a solo maintainer: **your deliberate merge is the human approval**, and the independent
multi-model review still ran before it.

Set your default branch to require the `intake` and `asdd/review` checks (and up-to-date branches), require
a pull request, and set required approvals to `0`. You still merge every change by hand.

## When you grow

The day a second maintainer joins, turn "require review from code owners" back on for your protected paths.
Now the approving-review gate is satisfiable by a real second human, and ASDD's protected-path rule (a named
human other than the author signs off on high-risk changes) is fully enforced. Nothing else changes: the
agents were already proposing under their own identity, so the only difference is who clicks approve.

Next: [adopt the govern layer](adopt-govern.md) or [run the operate layer with Goose](operate-goose.md).
