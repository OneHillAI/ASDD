# De-slop standard

The quality bar behind §4.3 of [STANDARD.md](../STANDARD.md). The documented failure of agent
contributions is that they add **redundancy and tech-debt** while reviewers feel *better* approving
them. This standard names the tells so the review lenses and CI can catch them. The goal is
human-grade quality and consistency, not fooling a detector, the tells below are real defects, and
most fixes are **deletion**.

> This is a vendor-neutral restatement of an internal code-and-docs standard. Adopters
> with their own house style should link it here instead; what matters is that *a* de-slop bar exists
> and the quality lens applies it.

## Prime directive: match the surrounding code

The strongest machine fingerprint is a file that is internally fine but stylistically alien to its
neighbours. Before writing, read 2-3 nearby modules and copy their idioms: naming, error handling,
comment density, import style, test shape. Consistency beats personal preference beats novelty.

## Code tells (tell → fix)

| Tell | Fix |
|---|---|
| `except Exception: pass` / blind catches | Catch the specific exception; let unexpected ones surface; log if swallowing is deliberate |
| Comments that restate code (`# increment i`, `# First, we...`) | Delete. Comment *why*, never *what* |
| Decorative section banners | At most one per real section |
| Over-abstraction: an interface/config/wrapper with one caller or one value | Inline it. Add the abstraction when the *second* case appears |
| Defensive bloat: redundant validation, re-checking invariants | Validate once, at the boundary; trust your own code paths |
| Docstring essays on trivial functions | One line, or none if the name says it |
| "Production-ready" theater: unused hooks, premature retries/caching | Delete until needed |
| Emoji / over-formatting in library code | Plain text; reserve emoji for deliberate CLI UX |

**Not tells (keep these):** type hints, real docstrings on non-trivial APIs, tests, meaningful error
messages. Do not strip good practice in the name of looking human.

## Doc tells

| Tell | Fix |
|---|---|
| Fluff adjectives / hedging | Cut; state the fact |
| "In this section we will..." meta-narration | Delete; say the thing |
| Exhaustive flat bullet lists | Prose + one tight list; cut the obvious |
| No examples | Add a real, runnable one |
| Uniform heading scaffolding everywhere | Vary by what the doc needs |

**Banned fluff words** (the clearest doc tells): comprehensive, robust, seamless, powerful,
cutting-edge, state-of-the-art, leverage, utilize, delve, "in order to" (→ "to"), "it's important to
note", "simply"/"just"/"easily". Lead with a concrete example before prose. (This repo's CI hard-fails
on the unambiguous subset, see [.github/workflows/docs-lint.yml](../.github/workflows/docs-lint.yml).)

## How it's enforced

1. **Automated.** Linters (ruff/eslint/etc.), type checks, tests, the §4.1 CI gates.
2. **Grep gates** for tells linters miss: leftover `TODO/FIXME/XXX`, blind catches, emoji in library
   code, comment-density outliers.
3. **The adversarial pass**: the [quality lens](../agents/review-quality.md), whose explicit job is to
   find net-added complexity and argue against the merge. This is the §4.2 cross-check.

A change is done only when the automated gates pass, the adversarial pass finds nothing blocking, and
it reads like the rest of the codebase. Net lines should ideally go **down**, not up.

## References

Choose exemplars by quality reputation, not star count. Code: CPython, Django, Flask/Requests,
FastAPI, ripgrep, SQLite; Ousterhout's *A Philosophy of Software Design* (the best antidote to
over-abstraction). Docs: [Diátaxis](https://diataxis.fr), Stripe, Twilio, the Google developer style
guide.
