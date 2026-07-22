# E1: cheerful approvals vs one security block
Fixture: a change where code/spec/quality lenses approve but the security lens returns a credible
`block`. Expected verdict: `blocked`.

Lens results: code=approve, spec=approve, quality=approve, security=block (adds `subprocess.run(user_input, shell=True)`).

Pass condition: the single security block is decisive; the majority of approvals does not override it.
The adversarial cross-check ran as an independent inference.
