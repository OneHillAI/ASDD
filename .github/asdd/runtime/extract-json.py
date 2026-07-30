#!/usr/bin/env python3
"""ASDD - pull the best JSON object out of a model's raw response.

The review runtime asks the model for a bare JSON object, but a real model (especially a
reasoning model) often wraps it: a paragraph of analysis first, code fences, or trailing
commentary, and that analysis frequently contains its own braces (`def f() { ... }`, `{x: 1}`).
A naive "slice from the first { to the last }" then captures a span that is not valid JSON, so a
perfectly good review is thrown away and the pipeline falls back to a human-review placeholder.

This reads the response on stdin and prints ONE JSON object on stdout (exit 0), or nothing
(exit 1) when the text holds no decodable object. It never executes anything and never emits
non-JSON, so the gate still fails closed when the model genuinely returned no review.

Strategy: try the whole text (fences stripped); then sweep every '{' and let the JSON decoder
consume the largest balanced object starting there (strings and nested braces handled correctly,
because it is a real parser, not a brace count). Among all decodable objects, prefer the one that
looks like a review (schema/lenses/summary/recommendation/verdict keys), then the largest.
"""
import json
import re
import sys


def _decodable_objects(text):
    dec = json.JSONDecoder()
    i, n = 0, len(text)
    while i < n:
        start = text.find("{", i)
        if start < 0:
            break
        try:
            obj, end = dec.raw_decode(text, start)
        except json.JSONDecodeError:
            i = start + 1
            continue
        if isinstance(obj, dict):
            yield obj
            i = start + end  # skip past the object we just consumed
        else:
            i = start + 1


def best_object(raw):
    candidates = []
    stripped = re.sub(r"\s*```$", "", re.sub(r"^```(?:json)?\s*", "", raw.strip()))
    for text in (stripped, raw):
        try:
            whole = json.loads(text)
        except ValueError:
            whole = None
        if isinstance(whole, dict):
            candidates.append(whole)
        candidates.extend(_decodable_objects(text))
    if not candidates:
        return None
    review_keys = {"schema", "lenses", "summary", "recommendation", "verdict"}

    def rank(obj):
        looks_like_review = len(review_keys & set(obj.keys()))
        return (looks_like_review, len(json.dumps(obj)))

    return max(candidates, key=rank)


def main():
    obj = best_object(sys.stdin.read())
    if obj is None:
        return 1
    sys.stdout.write(json.dumps(obj))
    return 0


if __name__ == "__main__":
    sys.exit(main())
