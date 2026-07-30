# Validating ASDD

How to test that ASDD actually works, and that it holds. "Does it work?" and "does it have flaws?" are
two different questions for a spec-driven *development* framework, and this suite answers both:

- **Effectiveness**: does the loop (spec -> build -> review -> merge) produce **correct software**,
  and does it converge without thrashing? See [effectiveness.md](effectiveness.md). This is the primary
  test: a framework for building software works only if software built with it works.
- **Assurance**: do ASDD's guarantees survive an attacker? The untrusted-content membrane,
  human-owned protected merges, model heterogeneity, the credential split. See [redteam.md](redteam.md)
  and [properties.md](properties.md). This is the "no flaws" test.

Neither half is optional. An assurance-only pass proves ASDD is *hard to attack* while saying nothing
about whether it *develops good software*; an effectiveness-only pass proves it ships features while
saying nothing about whether a malicious contributor can walk through the gates.

## Layout

```
validation/
  README.md            this file
  effectiveness.md     does the spec-driven loop produce correct software? (outcome tests + metrics)
  redteam.md           do the guarantees hold under attack? (the attack matrix)
  properties.md        for-all invariants asserted over the audit trail
  runner-contract.md   how a deployment plugs its loop + gates into the suite
  manifest.yaml        machine-readable index of every case (id -> file, dimension, expected, status)
  cases/               fixtures: task specs + acceptance oracles (effectiveness); attack payloads (assurance)
```

## What this is (and is not)

This is the **standard-side** suite: task corpora, attack fixtures, expected outcomes, metrics, and
audit-log properties, implementation-neutral, like the rest of ASDD. It is **not** the runner. A runner
drives a specific deployment's loop and gates and checks the results against this suite. The reference
runner lives with the reference implementation (this repository); an
adopter writes a thin runner against their own setup. The contract is in
[runner-contract.md](runner-contract.md).

## Status tags

Every case carries a `status`:

- **`runnable-base`**: exercises something that exists today (the base intake/review/merge pipeline,
  the security scan, the policy decision point, `check-models.sh`). Runs now, in dry-run/advisory.
- **`pending-profile`**: exercises the spec-driven profile (the spec-object intake gate, the
  contributor reviewer, the claim protocol). Written against the contract; goes live once the profile's
  reference implementation is built and a model runtime is wired.

So the corpus, oracles, and fixtures are buildable now; live measurement of the profile waits on the
same dependency as running it at all, the reference implementation + a fleet of at least two distinct
models.

## Run the runnable-today slice

The deterministic checks that need no model runtime are wired into one command:

```bash
python3 validation/run-base.py
```

It drives the reference tools ([cli/spec-check.py](../cli/spec-check.py),
[cli/claim-check.py](../cli/claim-check.py), [cli/merge-eligibility.py](../cli/merge-eligibility.py),
[cli/check-models.sh](../cli/check-models.sh), [audit-check.py](audit-check.py)) and the effectiveness
oracle ([cases/tasks/feat-pagination/harness.py](cases/tasks/feat-pagination/harness.py)), and reports a
single PASS/FAIL. It also prints what is **not** run here (the base-pipeline cases in the product repo,
the model-driven agents, properties P7/P8). Exit 0 iff every deterministic check passes - drop it into
CI to keep the slice green.

## The honest bar

This suite cannot prove ASDD flawless or its output always correct, no suite can. It targets a
reachable bar: **every guarantee is mechanically enforced and continuously attacked here, and every
merged change is measured against an independent oracle and an audit trail**. A regression is caught by
a case or is detectable after the fact. A discovered flaw becomes a new case *and* a governance
decision. Fixtures are synthetic, example keys, labelled injection strings, toy backdoors, never live
secrets or working exploits.
