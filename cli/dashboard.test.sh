#!/bin/sh
# Self-test for dashboard.py: renders a fixture snapshot offline and checks the governance buckets.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="$HERE/testdata/dashboard-fixture.json"
D="python3 $HERE/dashboard.py"

fail() { echo "FAIL: $1" >&2; exit 1; }

# The computed model buckets each PR correctly.
model="$($D --from "$FIX" --json)"
echo "$model" | grep -q '"awaiting-review": 1' || fail "awaiting-review count wrong"
echo "$model" | grep -q '"in-progress": 1'    || fail "in-progress count wrong"
echo "$model" | grep -q '"changes-requested": 2' || fail "changes-requested count wrong (review failure should bucket here)"
echo "$model" | grep -q '"merged": 1'         || fail "merged count wrong"
echo "$model" | grep -q '"open": 4'           || fail "open total wrong"

# The HTML is self-contained and shows the sections + a release.
htmlout="$($D --from "$FIX")"
printf '%s' "$htmlout" | grep -q '<!doctype html>' || fail "not a full HTML doc"
printf '%s' "$htmlout" | grep -q 'Awaiting review' || fail "missing Awaiting review section"
printf '%s' "$htmlout" | grep -q 'Changes requested' || fail "missing Changes requested section"
printf '%s' "$htmlout" | grep -q 'Add rate limiter' || fail "missing a PR title"
printf '%s' "$htmlout" | grep -q 'v0.1.0' || fail "missing release"
printf '%s' "$htmlout" | grep -q 'http' && ! printf '%s' "$htmlout" | grep -q '<script src' || fail "should have no external scripts"

# Release grouping: each PR shows its target version, and the suggested next release groups by version.
echo "$model" | grep -q '"next_release"' || fail "model missing next_release"
python3 - "$FIX" <<'PY' || fail "next_release grouping wrong"
import json, subprocess, sys, os
here = os.path.dirname(os.path.abspath(sys.argv[1]))
m = json.loads(subprocess.check_output(["python3", os.path.join(os.path.dirname(here), "dashboard.py"),
                                        "--from", sys.argv[1], "--json"]))
nr = m["next_release"]
vs = {g["version"]: [p["number"] for p in g["prs"]] for g in nr["versions"]}
assert vs.get("v0.2.0") == [10, 11], vs                     # two PRs group under one version
assert [p["number"] for p in nr["needs_version"]] == [12], nr["needs_version"]  # normative, no version
PY
printf '%s' "$htmlout" | grep -q 'Suggested next release' || fail "missing the suggested next release section"
printf '%s' "$htmlout" | grep -q 'v0.2.0' || fail "target version not rendered"
printf '%s' "$htmlout" | grep -q 'review and confirm' || fail "section should be labelled a suggestion"
printf '%s' "$htmlout" | grep -q 'needs version' || fail "a normative PR with no version should be flagged"
printf '%s' "$htmlout" | grep -q '<th>Target</th>' || fail "PR tables should show a Target column"
# A version left only in an HTML comment must not count as a real target (matches impact_scan).
if printf '%s' "$htmlout" | grep -q 'v9.9.9'; then fail "a comment-only version leaked as a target"; fi

# Declaration check: a PR declared non-normative that changes normative text is flagged as a mismatch;
# a PR declared normative that changes normative text is not.
python3 - "$FIX" <<'PY' || fail "declaration-check discrepancies wrong"
import json, subprocess, sys, os
here = os.path.dirname(os.path.abspath(sys.argv[1]))
m = json.loads(subprocess.check_output(["python3", os.path.join(os.path.dirname(here), "dashboard.py"),
                                        "--from", sys.argv[1], "--json"]))
disc = [d["number"] for d in m["discrepancies"]]
assert disc == [15], disc                                   # #15: non-normative but edits standards/
rows = {r["number"]: r for st in m["stages"].values() for r in st}
assert rows[15]["scope_check"] == "mismatch", rows[15]
assert rows[12]["scope_check"] == "ok", rows[12]            # normative + edits normative text -> consistent
assert rows[11]["scope_check"] == "ok", rows[11]            # normative + no normative text touched -> fine
PY
printf '%s' "$htmlout" | grep -q 'Declaration check' || fail "missing the Declaration check section"

# Audit ledger: per-role activity renders, and a BROKEN chain is surfaced rather than shown as fact.
LED="$(mktemp -d)/audit.jsonl"
python3 "$HERE/audit.py" append --ledger "$LED" --role merge --action merge.review.verdict \
  --verdict human-approve --action-taken block --reasoning "protected path" >/dev/null 2>&1
led="$($D --from "$FIX" --ledger "$LED")"
printf '%s' "$led" | grep -q 'Agent activity (audit ledger)' || fail "missing the audit ledger section"
printf '%s' "$led" | grep -q 'chain intact' || fail "ledger chain state not shown"
printf '%s' "$led" | grep -q 'merge' || fail "ledger did not render the role"
sed -i.bak 's/"reasoning":"protected path"/"reasoning":"tampered"/' "$LED" 2>/dev/null || true
bad="$($D --from "$FIX" --ledger "$LED")"
printf '%s' "$bad" | grep -q 'does NOT verify' || fail "a tampered ledger should be surfaced as untrustworthy"
printf '%s' "$htmlout" | grep -q 'scope mismatch' || fail "a scope mismatch should be flagged in the table"
printf '%s' "$htmlout" | grep -q 'Small tweak to the standard' || fail "the mismatched PR should be listed"

# A synced sink is a DIRECTORY of ledger/<year>/<month>.jsonl, not one file. The dashboard must read the
# whole set and keep the chain continuous across the file boundary, or an adopter who points at their sink
# sees nothing and is told nothing.
WORK="$(mktemp -d)"                      # scratch, kept OUT of the sink so it is not picked up
SINK="$(mktemp -d)/ledger"; mkdir -p "$SINK/2026"
python3 "$HERE/audit.py" append --ledger "$WORK/m1.jsonl" --role review --lens code \
  --action review.lens.completed --authorizing-decision advisory --verdict ok --reasoning m1 >/dev/null 2>&1
cp "$WORK/m1.jsonl" "$SINK/2026/06.jsonl"
cp "$WORK/m1.jsonl" "$WORK/chain.jsonl"  # month two continues the same chain, as the export does
python3 "$HERE/audit.py" append --ledger "$WORK/chain.jsonl" --role documentation --action docs.updated \
  --authorizing-decision trusted --verdict ok --reasoning m2 >/dev/null 2>&1
tail -n +2 "$WORK/chain.jsonl" > "$SINK/2026/07.jsonl"
sink="$($D --from "$FIX" --ledger "$SINK")"
printf '%s' "$sink" | grep -q '2 recorded action(s)' || fail "sink directory: both monthly files not read"
printf '%s' "$sink" | grep -q 'chain intact' || fail "sink directory: chain not continuous across files"
printf '%s' "$sink" | grep -q 'documentation' || fail "sink directory: second month's role missing"

# A chain broken ACROSS files must still be caught, not smoothed over by reading them separately.
cp "$SINK/2026/06.jsonl" "$SINK/2026/07.jsonl"
broke="$($D --from "$FIX" --ledger "$SINK")"
printf '%s' "$broke" | grep -q 'does NOT verify' || fail "a chain break across files was not detected"

# A path that exists but holds no records is a distinct condition from no ledger at all.
none="$($D --from "$FIX" --ledger "$(mktemp -d)")"
printf '%s' "$none" | grep -q 'contains no records' || fail "an empty ledger path should say so, not render nothing"

# The active config snapshot renders the steering, and a misfiled credential is redacted
# (this page gets published, so a key in .asdd.yml must never reach the HTML).
tmp="$(mktemp -d)"
cat > "$tmp/leaky.yml" <<'YAML'
standard_version: "0.1"
merge_posture: advisory
api_key: "sk-shouldNeverRender"
models:
  developer: "vendor/model-a"
  provider_token: "ghp_shouldNeverRender"
lanes:
  - feature
  - chore
YAML
cfg="$($D --from "$FIX" --config "$tmp/leaky.yml")"
printf '%s' "$cfg" | grep -q 'Active configuration' || fail "missing the Active configuration panel"
printf '%s' "$cfg" | grep -q 'vendor/model-a'       || fail "a legitimate model name should render"
printf '%s' "$cfg" | grep -q 'advisory'             || fail "merge posture should render"
printf '%s' "$cfg" | grep -q 'redacted'             || fail "a credential-shaped value should be redacted"
if printf '%s' "$cfg" | grep -q 'shouldNeverRender'; then fail "a credential leaked into the published page"; fi
rm -rf "$tmp"

# With no config present, the panel degrades to a hint rather than breaking.
nocfg="$($D --from "$FIX" --config /nonexistent/.asdd.yml)"
printf '%s' "$nocfg" | grep -q 'No .asdd.yml found' || fail "missing config should degrade gracefully"

# Internal-only hardening: the page must warn, must not be indexable, and must not leak a referrer.
printf '%s' "$htmlout" | grep -q 'noindex,nofollow,noarchive' || fail "missing robots noindex"
printf '%s' "$htmlout" | grep -q 'no-referrer'                || fail "missing referrer policy"
printf '%s' "$htmlout" | grep -q 'Do not publish it to a public URL' || fail "missing the internal banner"

# A crafted snapshot must not inject a javascript: href, and a hostile title must stay escaped.
evil="$(mktemp -d)/evil.json"
python3 - "$FIX" "$evil" <<'PY2'
import json,sys
s=json.load(open(sys.argv[1]))
s["pulls"][0]["html_url"]="javascript:alert(1)"
s["pulls"][0]["title"]="<img src=x onerror=alert(1)>"
json.dump(s,open(sys.argv[2],"w"))
PY2
ev="$($D --from "$evil")"
if printf '%s' "$ev" | grep -q 'javascript:alert'; then fail "a javascript: href reached the page"; fi
if printf '%s' "$ev" | grep -q '<img src=x onerror'; then fail "an unescaped title reached the page"; fi

# The shared stylesheet is what gets inlined, and a missing one degrades instead of rendering naked.
printf '%s' "$htmlout" | grep -q 'prefers-color-scheme' || fail "shared stylesheet not inlined"

# --public is a control, not a promise: it must be refused unless the repo is verifiably public,
# because the whole internal posture is worthless if a tick-box can publish private activity.
pubdir="$(mktemp -d)"
python3 - "$FIX" "$pubdir" <<'PY3'
import json,sys
s=json.load(open(sys.argv[1])); d=sys.argv[2]
s["private"]=True;  json.dump(s,open(d+"/priv.json","w"))
s["private"]=False; json.dump(s,open(d+"/pub.json","w"))
s.pop("private");   json.dump(s,open(d+"/unknown.json","w"))
PY3
if $D --from "$pubdir/priv.json" --public >/dev/null 2>&1; then fail "--public was allowed for a PRIVATE repo"; fi
if $D --from "$pubdir/unknown.json" --public >/dev/null 2>&1; then fail "--public was allowed with UNKNOWN visibility"; fi
pub="$($D --from "$pubdir/pub.json" --public)" || fail "--public refused for a verified public repo"
# A public render is only safe when every fact on the page is already public on GitHub. The repo's
# visibility says nothing about sources supplied out of band: the ledger comes from a sink required to be
# PRIVATE, and a local intake queue is not on the repo either. Publishing those under the public banner
# would make its assurance false, so the gate must refuse both.
LEDG="$(mktemp -d)/a.jsonl"
python3 "$HERE/audit.py" append --ledger "$LEDG" --role review --action review.lens.completed \
  --authorizing-decision advisory --verdict ok --reasoning "SENTINEL_PRIVATE_REASONING" >/dev/null 2>&1
if $D --from "$pubdir/pub.json" --public --ledger "$LEDG" >/dev/null 2>&1; then
  fail "--public published a page carrying the audit ledger without --public-metrics"; fi
if $D --from "$pubdir/pub.json" --public --intake "$(mktemp -d)" >/dev/null 2>&1; then
  fail "--public published a page carrying a local intake queue"; fi
# The internal page may carry the ledger, and a public page without it is still fine.
$D --from "$pubdir/pub.json" --ledger "$LEDG" >/dev/null 2>&1 || fail "the internal page should render the ledger"

# The PUBLIC aggregate projection: --public --public-metrics publishes counts only, never per-record
# reasoning. This is the whitelist-by-construction public view.
pubm="$($D --from "$pubdir/pub.json" --public --public-metrics --ledger "$LEDG")" \
  || fail "--public --public-metrics should render the aggregate ledger view"
printf '%s' "$pubm" | grep -q 'SENTINEL_PRIVATE_REASONING' \
  && fail "the public aggregate view leaked per-record reasoning"
printf '%s' "$pubm" | grep -q 'recorded action' || fail "the public aggregate view should show counts"
printf '%s' "$pubm" | grep -q 'aggregate counts only' || fail "the public aggregate banner should say so"
# --public-metrics alone (no ledger) is harmless, and an intake queue still cannot ride --public.
if $D --from "$pubdir/pub.json" --public --public-metrics --intake "$(mktemp -d)" >/dev/null 2>&1; then
  fail "--public-metrics must not unlock publishing a local intake queue"; fi
# The banner must claim only what was verified.
if printf '%s' "$pub" | grep -q 'Nothing private is disclosed'; then
  fail "the public banner claims more than the visibility check verifies"; fi
printf '%s' "$pub" | grep -q 'no out-of-band source' || fail "the public banner should state what it verified"


printf '%s' "$pub" | grep -q 'Public render' || fail "public render should identify itself as public"
if printf '%s' "$pub" | grep -q 'noindex'; then fail "a public demo must be indexable"; fi
if printf '%s' "$pub" | grep -q 'Do not publish it to a public URL'; then fail "internal banner on a public demo"; fi
# and the default is still the internal posture
printf '%s' "$htmlout" | grep -q 'Do not publish it to a public URL' || fail "default must stay internal"
rm -rf "$pubdir"

echo "dashboard.test.sh: PASS"
