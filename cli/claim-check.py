#!/usr/bin/env python3
"""Deterministic claim-protocol enforcer for the ASDD spec-driven profile
(standards/spec-driven.md CL). No model required. Serializes work at the spec,
before code exists, so concurrent contributors do not collide.

Given a claims ledger and a claim request, it:
  - CL.3 auto-releases claims older than the TTL,
  - CL.1 refuses a claim on an item with no ready spec,
  - CL.2 refuses a second active claim on an item held by another identity,
  - CL.2 refuses a claim past a per-identity active-claim cap,
  - grants otherwise (idempotent if the identity already holds the item).

`--now` is explicit (ISO 8601) so runs are reproducible/testable. Zero-dependency.
Exit codes: 0 = grant, 1 = refuse.
"""
import argparse
import json
import sys
from datetime import datetime, timedelta


def parse(ts):
    return datetime.fromisoformat(ts)


def main():
    ap = argparse.ArgumentParser(description="ASDD claim-protocol enforcer (CL)")
    ap.add_argument("ledger", help="JSON array of active claims [{item,identity,created_at}]")
    ap.add_argument("--now", required=True, help="ISO 8601 timestamp (reproducible)")
    ap.add_argument("--item")
    ap.add_argument("--identity")
    ap.add_argument("--ready", default="true", help="is the item's spec ready? (CL.1)")
    ap.add_argument("--ttl-hours", type=float, default=168)
    ap.add_argument("--max-per-identity", type=int, default=1)
    ap.add_argument("--sweep", action="store_true", help="only auto-release expired claims and report")
    a = ap.parse_args()

    now = parse(a.now)
    with open(a.ledger) as fh:
        ledger = json.load(fh)
    active = [c for c in ledger if (now - parse(c["created_at"])) < timedelta(hours=a.ttl_hours)]
    for c in ledger:
        if c not in active:
            print(f"auto-released (ttl {a.ttl_hours}h): item={c['item']} identity={c['identity']}")

    if a.sweep:
        print(f"active claims: {len(active)}")
        return 0

    if a.ready.lower() != "true":
        print(f"REFUSE: item {a.item} has no ready spec - not claimable (CL.1)")
        return 1

    on_item = [c for c in active if c["item"] == a.item]
    holder = on_item[0]["identity"] if on_item else None
    if holder and holder != a.identity:
        print(f"REFUSE: item {a.item} already claimed by {holder} (CL.2, one active per item)")
        return 1
    if holder == a.identity:
        print(f"GRANT: item {a.item} already held by {a.identity} (idempotent)")
        return 0
    mine = [c for c in active if c["identity"] == a.identity]
    if len(mine) >= a.max_per_identity:
        print(f"REFUSE: {a.identity} holds {len(mine)} active claim(s), cap={a.max_per_identity} (CL.2)")
        return 1

    print(f"GRANT: item {a.item} to {a.identity}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
