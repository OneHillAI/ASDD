# Assure - the integrity attestation (optional)

ASDD's three rules cover **who** wrote a change (disclosure), **who approves** it (human merge),
and **whether it is safe and correct** (the security and quality gates). The Assure layer adds a fourth,
optional question: can the change be trusted as a **signed, verifiable record** - not just reviewed, but
attested?

This matters most when the author is an agent. Disclosure says an agent wrote it; an attestation *proves*,
per change, that the agent did not smuggle in an exfiltration path, a malicious dependency, a backdoor, or
an unpermitted action - and it binds that evidence to an identity and a signature.

## What an attestation asserts

A per-change attestation is a small, signed record that binds, for one PR:

- **Provenance** - how it was built: the SLSA build level, an in-toto link, an SBOM.
- **A threat scan** - mapped to the OWASP Top 10 for Agentic Applications (see
  [compliance-map.md](compliance-map.md)): no data exfiltration, covert network, unpinned dependencies,
  dangerous sinks, secret exposure, or unpermitted actions.
- **Agent identity** - which agent identity produced it, and under whose direction.
- **Independent review** - that the reviewer and tester ran on a different model from the builder.
- **A signature** - so the whole record is verifiable, not asserted.

## How to use it

Requiring an attestation is opt-in per project. When required, an agent-authored PR carries the attestation
alongside the four-item contract; the merge gate checks it is present, well-formed, and its threat scan is
clean before the change is merge-ready. It **composes with** existing supply-chain tooling (SLSA, in-toto,
Sigstore, SBOM) rather than replacing it - it binds them into one per-change record.

## The format

The attestation format is published separately as an open, forkable specification, the AI-authored-code integrity format - so it can be adopted without the rest of ASDD. It is in
**draft**; this page is the framework's hook into it. Until it is final, treat Assure as an optional,
forward-looking layer: adopt the three rules and the pipeline first, and add attestation when the format
stabilises.
