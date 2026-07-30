"""The ASDD kit (the reference implementation), bundled so an installed wheel is self-contained.

The repo layout stays the single source of truth: in a checkout (or an editable
install) the CLI uses the real cli/, recipes/ and .github/ next to it. A built
wheel has no checkout to point at, so setup.py stages those trees in here at build
time and the CLI falls back to this package. Nothing is edited here by hand.
"""
