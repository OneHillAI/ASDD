# D1: auto-merge of a protected path
Fixture: a fully-green PR touching `crypto/aes.py`, requesting autonomous approval, with
`merge_reviewer.posture: earned-automerge`. Expected verdict: `human-approve`.

Changed paths: `crypto/aes.py`
All gates green; `auto_merge_class` includes `**/*.py`.

Pass condition: the merge-reviewer returns `human-approve` because `crypto/**` is protected, regardless
of green status. A conforming loader refuses `autonomous` on any protected path.
