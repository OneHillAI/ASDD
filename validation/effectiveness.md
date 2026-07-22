# Effectiveness: does ASDD produce correct software?

The core claim of a spec-driven development framework is: *give the loop a good spec, and it builds
software that is correct and matches intent.* This dimension tests that claim empirically. It is the
primary "does it work" test, the gates in [redteam.md](redteam.md) are worthless if the loop cannot
ship a working feature in the first place.

The method is a **controlled trial**: run a corpus of real development tasks through the full loop, and
judge the merged output against an **independent oracle**: an acceptance test authored separately from
whatever built the change. Because agents are stochastic, every task runs N times and the suite reports
**rates and variance**, not single runs.

## The task corpus

A set of representative development tasks (see [cases/](cases/) for the schema and worked examples).
Each task is:

```yaml
id: feat-pagination
kind: feature | bugfix | refactor | docs | migration
spec: cases/tasks/feat-pagination/spec.md        # the input to the loop (a definition-of-ready spec)
oracle: cases/tasks/feat-pagination/acceptance/   # independent tests the merged result MUST pass
repo_state: cases/tasks/feat-pagination/before/   # the starting tree (a sandbox repo)
variants:
  - name: ready-spec        # the spec meets the definition of ready
  - name: vague-spec        # deliberately underspecified (tests the intake gate, see below)
  - name: seeded-defect     # a correct-looking spec whose obvious implementation hides a bug the review must catch
```

The oracle MUST be independent of the developer agent, different author, ideally checked by the tester
role (the `developer != tester` heterogeneity is what makes the acceptance signal trustworthy).

## What gets measured

Run each task variant through `spec -> intake -> claim -> build -> review -> merge` on its sandbox repo,
then score:

| Metric | What it asks | Signal |
|---|---|---|
| **Task success rate** | Does the merged result pass the independent oracle? | the headline: does ASDD ship correct software |
| **Spec fidelity** | Does it implement the spec, no more, no less? (scope drift, missing requirements) | the SDD premise: output tracks the spec |
| **Seeded-defect catch rate** | Of `seeded-defect` variants, how many does review block before merge? | do the gates actually catch bugs (vs rubber-stamp), meets [redteam.md](redteam.md) E1 |
| **Escaped-defect rate** | Of merged changes, how many later fail (downstream tests, the runtime cross-check verifier)? | how much slips through |
| **Convergence** | Does the loop reach a terminal state (merged or rejected) within K review rounds? | agents don't thrash; specs are buildable |
| **Rework churn** | Lines/commits changed after a change was called "ready" | wasted motion in the loop |
| **First-response time** | Time from submit to first review signal | contributor experience (STANDARD §6.6) |
| **Human-gate load** | Human decisions per merged change; human override rate on agent recommendations | the gate paces without becoming a bottleneck, and is not a rubber stamp |

Thresholds are project-set, not fixed by the standard, a project records a **baseline** and treats a
regression against it as a failure. The one non-negotiable: the seeded-defect catch rate and the
escaped-defect rate together are the honesty check on whether "quality is a gate" is real or decorative.

## The spec-quality sensitivity test (validates the whole premise)

Run each task in both the `ready-spec` and `vague-spec` variants. ASDD's core bet is that output quality
tracks spec quality. Two acceptable outcomes, one failure:

- the `vague-spec` variant is **caught by the definition-of-ready gate** (parked as `needs-clarification`
  rather than built), the intake gate earns its keep; **or**
- it is built but scores measurably worse than `ready-spec` on the oracle, the premise holds.

A **failure** is a `vague-spec` that sails through and scores as well as `ready-spec`: that means the
spec is not actually driving the build, and ASDD is spec-driven in name only.

## The human-gate honesty check

Two failure modes, opposite directions, both measured:

- **Rubber-stamp**: humans approve nearly everything, including the `seeded-defect` variants. The gate
  is theatre.
- **Bottleneck**: humans must rewrite most agent output, or first-response time balloons. The loop
  isn't carrying its weight.

A healthy result: humans mostly agree with the agent recommendation on clean tasks, *and* reliably stop
the seeded-defect tasks.

## The dogfood integral (the real-world proof)

The corpus is a controlled proxy. The real evidence is the reference implementation running its own backlog through ASDD over
time: shipped, working releases are the integral of every task above. If it builds and ships itself this way and the
product works, ASDD works, that claim is checkable, not asserted.

## Status

- The **task corpus, oracles, variants, and metrics** are buildable now (portable, no runtime needed).
- **Retrospective measurement** on the base pipeline is possible today: score ASDD-gated merges already
  in the reference implementation against escaped-defect and human-override rates.
- **Live forward measurement** of the profile loop waits on the profile's reference implementation plus
  a fleet of at least two distinct models, the same dependency as running ASDD for real.
