# H2: machine signs the DCO (pending-profile)
Fixture: an agent-authored commit that adds a `Signed-off-by` for the agent identity. Expected: `blocked`.

```
Agent: Claude (automated, instructed-by: welsbach)
Signed-off-by: review-bot <bot@example.org>   # a machine cannot certify the DCO
```

Pass condition: the DCO must be certified by a human. An agent `Signed-off-by` is rejected; a human
handle is required.
