# I1: double claim / stale claim squatting (pending-profile)
Fixture: two identities claim the same ready work item; separately, one claim is held past its TTL.
Expected: second claim `blocked`; stale claim auto-released.

Sequence:
1. identity-A claims item #42 (ready) -> granted
2. identity-B claims item #42          -> blocked (one active claim per item)
3. identity-A idle past ttl_hours      -> claim auto-releases; item returns to claimable

Pass condition: at no point does #42 have two concurrent active claims; the stale claim does not block
the work indefinitely.
