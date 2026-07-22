# How ASDD works

This is the mental model. For the exact requirements see [STANDARD.md](https://github.com/OneHillAI/ASDD/blob/main/STANDARD.md); for the
step-by-step setup see the [guides](../guides/deploy.md). The point here is why the pieces are shaped the way they
are.

## The airlock

Every contribution crosses an **airlock**: two agent-held membranes between an untrusted public side (PR
bodies, diffs, issue text, fork contents) and the trusted development side (the code, the wiki, the
model). Only two things ever cross inward, a validated spec object or a review-ready change. Raw
untrusted content, including submitted code, never crosses as an instruction.

![The contribution airlock](../diagrams/airlock.svg)

The project treats what arrives from outside as data to be examined, never as commands to be followed.
That stance defeats prompt injection in a PR body and a Trojan-Source trick in a diff at the same time.

## The five steps

A contribution moves through five steps. The first is an optional on-ramp; the rest are what every PR
goes through.

1. **Spec.** Develop a ready spec for the change: outcomes, scope, constraints, and how "done" is
   checked. The spec agent can guide anyone through this in conversation, including a non-engineer, and
   parks an incomplete idea as `needs-clarification` until it is ready. This is an on-ramp, not a gate:
   a contributor who already has a spec can skip the conversation.
2. **Build.** Implement the spec as code and open a PR. The developer is always the contributor's own
   (their agent, or their hands); a deployment never runs a standing developer. A self-directed
   contributor enters the lifecycle *here* - but the spec still has to exist, authored into the PR or
   referenced, or step 3 stops it.
3. **Intake.** The PR is admitted. Deterministic, no model, read-only, first: disclosure is present,
   every commit is DCO signed-off, exactly one lane tag, and (for a non-`chore` lane) a spec is present.
   A plain program that cannot be talked out of its verdict by anything in the PR. If it fails, the PR
   stops here with the specific fixes listed, and nothing downstream runs.
4. **Review.** The code is judged against the spec and the gates. This runs **only when intake passed**,
   so a PR that fails admission never reaches a model (failed intake spends nothing), and it runs in the
   base context so a **fork PR gets the same real review** as an in-repo one. The analysis holds
   `contents: read` only and makes two independent model inferences: the code, security, and spec lenses
   together, and the quality lens in a **separate context** so it cannot see and rubber-stamp the others.
   Untrusted content is data; nothing here holds write scope.
5. **Merge.** A separate, write-scoped job reads only the review result (never the PR content), routes
   each action through a **policy decision point** that allow-lists a comment and a label while denying
   merge, push, and branch-protection changes, posts one advisory comment, and sets the `asdd/review`
   status. Then a **human merges**. Nothing merges automatically.

Steps 3 to 5 are three separate workflows chained by completion (intake, then review, then publish).
Untrusted content only ever touches the jobs with no write access, and the write-scoped job only ever
sees the structured result. That split is the security invariant.

## The security lens

Inside the read-only analysis job, three layers stack: deterministic rules over the added diff lines
(committed keys, disabled TLS, dangerous sinks, bidi and zero-width Unicode, injection markers), a SAST
pass over changed Python, and a model lens on top when a runtime is wired. Code under review is always
data. The scanner reads bytes and runs static checks; it never imports, evaluates, or shell-executes what
it is reviewing. A block finding flips `asdd/review` to request-changes, so the gate bites even in
dry-run before any model is connected.

## Who is allowed to merge what

Merges are tiered by change class, and the default is strict: humans merge everything. Auto-merge is
*earned* (only after a track record), *narrow* (a positively-declared class of trivial, fully-green
changes), and never reaches a protected path. Those stay human-approved permanently, enforced by branch
protection and `CODEOWNERS`, not by convention.

![Merge authority tiers](../diagrams/merge-authority.svg)

The deterministic [`merge-eligibility`](https://github.com/OneHillAI/ASDD/blob/main/cli/merge-eligibility.py) gate computes this routing, and a
protected path always wins: even a misconfigured auto-merge class can never carry a protected file into
an autonomous merge.

## The operate layer

The steps above are the *govern* layer. The agents that do the work (the listener, the spec agent, the
review lenses, the test agents, and documentation) are the *operate* layer, and ASDD mandates
no runtime for them. A
deployment satisfies the contract in [agents/runtime.md](https://github.com/OneHillAI/ASDD/blob/main/agents/runtime.md) on whatever it runs:
its own harness ([guides/operate-other](../guides/operate-other.md)) or unmodified Goose
([guides/operate-goose](../guides/operate-goose.md)). The developer that builds a change is always
brought by the contributor; the deployment runs only governance and support agents, on models it
chooses, with the test agents kept distinct from the developer.

The full roster, grouped by the stage each agent works in, and which of them you set a model for:

![The ASDD agent roster: every agent grouped by pipeline stage - listen, define the spec, build, review, merge, after - showing which you set a model for.](../diagrams/agents.svg)

## How the agents stay coordinated: the kit map

An agent asked to set something up or change something should not have to read the whole repo to work
out the shape of it. Three files answer that, and every agent reads them **in this order** before it
proposes anything:

1. **`AGENTS.md`** - the constitution: the rules every agent obeys. Not optional.
2. **`.asdd.yml`** - this deployment: the roster, protected paths, merge posture, lanes, spec context.
3. **`asdd-kit.yml`** - the map: what exists, which recipe realises each role, which config key holds
   that role's model, and where it actually runs.

That last one matters because the roles are not hosted uniformly: the review lenses run in CI without
Goose (an HTTPS call to your model endpoint), the recipe agents run through `goose run`, and the
developer is the contributor's own session. The map states it instead of making you grep the pipeline.

A map is only useful if it is true, so [`cli/kit-check.py`](https://github.com/OneHillAI/ASDD/blob/main/cli/kit-check.py)
fails the build when it drifts: every role in the map must exist in the config's `models:` block and
vice versa, every recipe it names must exist, and every `read_first` file must exist. A rename breaks
the build rather than quietly turning the map into a lie an agent then acts on.

The [setup agent](https://github.com/OneHillAI/ASDD/blob/main/recipes/setup.yaml) is the same idea from
the other side: it reads the map, works out what is configured and what is missing, explains the choices
in plain language, and makes the safe changes. Deeper steering it proposes as a governed pull request,
never a silent edit. See [operate with Goose](../guides/operate-goose.md).

Next: [prior art](../prior-art.md), [adopt the govern layer](../guides/adopt-govern.md)
