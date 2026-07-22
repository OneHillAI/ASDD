# Disclosure standard

The rule behind §1 of [STANDARD.md](../STANDARD.md). Agents are never disguised as humans. This is the
single most important norm ASDD sets, because the failure it prevents, undisclosed agents landing
PRs at scale, is the one doing the most damage right now.

## What must be disclosed

- **Commits.** An agent-authored or agent-co-authored commit carries a disclosure trailer.
- **Pull requests.** The PR body states it is agent-authored (the template has the checkbox).
- **Issues and comments.** Agent-posted issues/comments say so, in the text.
- **Profiles.** An agent identity's account profile states it is an automated agent.

A human contributor using an AI assistant for help is a human contribution; an **agent acting on its
own under human direction** is an agent contribution. When in doubt, disclose.

## The commit trailer (canonical form)

```
<conventional commit subject>

<body>

Agent: <agent-name> (automated, instructed-by: <human-handle>)
Signed-off-by: <Name> <email>
```

- `Agent:` names the agent identity, marks it `automated`, and names the human who directed it.
- `Signed-off-by:` is the DCO line (`git commit -s`), asserting the right to contribute under the
  project's license.
- Co-authored agent + human work uses both a `Co-authored-by:` line and the `Agent:` trailer.

The reference implementation's `check-disclosure.sh` enforces the trailer on commits from the agent identities listed in
`.asdd.yml` (`agents:`). Human commits are not subject to it.

## The PR disclosure

The [pull request template](../.github/PULL_REQUEST_TEMPLATE.md) requires one of:

- Authored by a **human**, or
- Authored / co-authored by an **AI agent under human direction**, with the agent identity and the
  directing human named.

Misrepresenting agent work as human is a Code of Conduct violation, not a style nit.

## Audit trail (§1.3)

Disclosure to a reader is necessary but not sufficient. Every agent **action** is also recorded in a
retained, reviewable audit trail: the agent identity, the action, the target, the authorizing PDP
decision, and a timestamp. In the reference implementation the workflow logs plus the runtime's own
audit (for a runtime with an `audit.log`) are that trail. No action exists without a record of it.

## Visibility (§1.4, SHOULD)

Beyond per-action disclosure, a project is encouraged to show the whole pipeline publicly, humans and
agents both, so that "we run ASDD" is checkable rather than asserted. A contributor wall
and a live "how it's built" view make the adoption legible.
