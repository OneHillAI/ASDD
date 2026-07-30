#!/usr/bin/env python3
"""operate-guard - enforce the ASDD operate-agent security classification.

An operate agent that runs automatically in CI must respect one rule, learned
from the reference dogfood: a TOOL-USING agent (a Goose recipe with the
`developer` shell builtin) must not run automatically on UNTRUSTED input, because
a prompt injection in that input could exfiltrate the model credential through the
shell or network. It may run on TRUSTED input (post-merge, human-approved), or on
untrusted input only if it is execution-free (no shell) or in a sandbox with no
network egress.

This guard refuses a tool-using recipe on untrusted input. An operate CI step
calls it before running the agent, so the classification is mechanical, not a
comment. It classifies a recipe as tool-using when it declares the Goose
`developer` builtin (the shell surface); a recipe that adds other tool- or
network-granting extensions must be classified by the adopter.

    python3 cli/operate-guard.py recipes/documentation.yaml --input trusted
    python3 cli/operate-guard.py recipes/interaction-public.yaml --input untrusted   # ok, execution-free

Exit 0 allowed, exit 1 refused.
"""
import argparse
import sys


def is_tool_using(recipe_path):
    # Tool-using = declares the Goose `developer` builtin (shell + file write).
    # Execution-free recipes (only asdd-gates, or a read-only knowledge reader) do not.
    return "name: developer" in open(recipe_path, encoding="utf-8").read()


def main():
    ap = argparse.ArgumentParser(description="ASDD operate-agent security-classification guard")
    ap.add_argument("recipe", help="path to the operate recipe")
    ap.add_argument("--input", choices=["trusted", "untrusted"], required=True,
                    help="trust level of the input the agent runs on")
    a = ap.parse_args()
    tool = is_tool_using(a.recipe)
    if tool and a.input == "untrusted":
        sys.stderr.write(
            f"operate-guard: REFUSED. {a.recipe} is tool-using (declares the `developer` shell builtin) "
            "and the input is untrusted. A prompt injection could exfiltrate the model credential. Use an "
            "execution-free recipe (no shell, e.g. recipes/interaction-public.yaml), a sandbox with no "
            "network egress, or a trusted (post-merge, human-approved) trigger.\n")
        return 1
    print(f"operate-guard: allowed ({'tool-using' if tool else 'execution-free'} recipe on {a.input} input)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
