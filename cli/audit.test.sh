#!/usr/bin/env bash
# Self-test for the audit ledger. The properties that make a trail evidence rather than a log file:
# every record carries identity/action/target/authorisation/timestamp (STANDARD 1.3), the chain links,
# an edit or a deletion is DETECTABLE, and reviewed content is never copied into the record.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
A="python3 $HERE/audit.py"
command -v python3 >/dev/null 2>&1 || { echo "audit self-test: SKIP (python3 required)"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
L="$TMP/ledger.jsonl"
fail=0
ck() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', want '$3')"; fail=1; fi; }

# --- append records from three different roles -----------------------------
$A append --ledger "$L" --role review --lens code --action review.lens.completed \
  --identity review-bot --model m1 --verdict ok --action-taken comment \
  --reasoning "no correctness issues found" \
  --authorizing-decision "merge_posture=advisory" --accountable-human maintainer \
  --target-json '{"repo":"o/r","pr":7,"commit":"abc1234"}' \
  --payload-json '{"findings":[]}' >/dev/null 2>&1
$A append --ledger "$L" --role merge --action merge.review.verdict \
  --identity merge-bot --verdict human-approve --action-taken block \
  --reasoning "protected path touched" \
  --authorizing-decision "STANDARD 2.2: protected path is always human-approved" \
  --payload-json '{"protected_paths_touched":["cli/x.py"],"deciding_rule":"STANDARD 2.2"}' >/dev/null 2>&1
$A append --ledger "$L" --role test-runner --action tests.run \
  --verdict fail --action-taken block --reasoning "2 tests failed" \
  --authorizing-decision "operate posture: the test runner reports, it does not merge" \
  --payload-json '{"tested":"unit","passed":10,"failed":2}' >/dev/null 2>&1

ck "three records appended" "$(wc -l < "$L" | tr -d ' ')" "3"

# 1.3 envelope present on every record.
miss="$(python3 - "$L" <<'PY'
import json,sys
need=("schema","ts","agent","action","target","authorizing_decision","accountable_human","hash","prev","event_id")
bad=0
for line in open(sys.argv[1]):
    r=json.loads(line)
    if any(k not in r for k in need): bad+=1
    if "role" not in r.get("agent",{}): bad+=1
print(bad)
PY
)"
ck "every record carries the 1.3 envelope" "$miss" "0"

# Role-specific payloads survive intact.
ck "merge payload kept the deciding rule" \
  "$(python3 -c "import json,sys;print([json.loads(l) for l in open(sys.argv[1]) if json.loads(l)['agent']['role']=='merge'][0]['payload']['deciding_rule'])" "$L")" \
  "STANDARD 2.2"

# --- chain verifies --------------------------------------------------------
$A verify --ledger "$L" >/dev/null 2>&1 && echo "ok: chain verifies" || { echo "FAIL: chain should verify"; fail=1; }

# --- reviewed content is digested, never stored ----------------------------
SEC="$TMP/secret.txt"; printf 'TOP SECRET SOURCE LINE\n' > "$SEC"
L2="$TMP/l2.jsonl"
$A append --ledger "$L2" --role review --lens security --action review.lens.completed \
  --verdict ok --inputs-file "$SEC" --reasoning "clean" >/dev/null 2>&1
if grep -q 'TOP SECRET SOURCE LINE' "$L2"; then echo "FAIL: reviewed content leaked into the ledger"; fail=1;
else echo "ok: inputs are digested, content never stored"; fi
python3 -c "import json,sys;d=json.loads(open(sys.argv[1]).readline());sys.exit(0 if d.get('inputs_digest','').startswith('sha256:') else 1)" "$L2" \
  && echo "ok: inputs_digest recorded" || { echo "FAIL: no inputs_digest"; fail=1; }

# --- tamper detection: edit a record --------------------------------------
LT="$TMP/tamper.jsonl"; cp "$L" "$LT"
python3 - "$LT" <<'PY'
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1])]
lines[1]["outcome"]["verdict"]="autonomous-approve"   # quietly upgrade a merge verdict
open(sys.argv[1],"w").write("\n".join(json.dumps(r,sort_keys=True,separators=(",",":")) for r in lines)+"\n")
PY
$A verify --ledger "$LT" >/dev/null 2>&1 && { echo "FAIL: an altered record verified"; fail=1; } || echo "ok: an altered record is detected"

# --- tamper detection: delete a record ------------------------------------
LD="$TMP/del.jsonl"; sed '2d' "$L" > "$LD"
$A verify --ledger "$LD" >/dev/null 2>&1 && { echo "FAIL: a deleted record verified"; fail=1; } || echo "ok: a deleted record is detected"

# --- the framework's own property checker must be able to evaluate this ledger ---
# The trail properties (P1-P6, P9) are asserted by validation/audit-check.py. If the ledger and the
# checker are two different shapes, the standard's audit requirement has an implementation nothing
# validates. These two assertions are what keep them one shape.
TR="$TMP/trail.json"
$A trail --ledger "$L" > "$TR" 2>/dev/null
props="$(python3 "$HERE/../validation/audit-check.py" "$TR" --max-actions 100 2>/dev/null)" || true
if printf '%s' "$props" | grep -q "RESULT: PASS"; then
  echo "ok: the ledger satisfies the trail properties (P1-P6, P9)"
else
  echo "FAIL: the ledger does not satisfy the trail property checker"; fail=1
fi
# P3 is the sharp one: an action with no authorising decision must be caught, not tolerated.
P3="$TMP/p3.jsonl"
$A append --ledger "$P3" --role triage --action triage.labelled --reasoning "no authorisation" >/dev/null 2>&1
$A trail --ledger "$P3" > "$TMP/p3.json" 2>/dev/null
p3out="$(python3 "$HERE/../validation/audit-check.py" "$TMP/p3.json" 2>/dev/null)" || true
if printf '%s' "$p3out" | grep -q "P3"; then
  echo "ok: an action without a policy decision trips P3"
else
  echo "FAIL: P3 did not catch a missing authorising decision"; fail=1
fi

# --- append is safe on a fresh path ---------------------------------------
$A append --ledger "$TMP/nested/new.jsonl" --role triage --action triage.labelled \
  --reasoning "bug report" --payload-json '{"labels":["bug"]}' >/dev/null 2>&1
[ -f "$TMP/nested/new.jsonl" ] && echo "ok: creates the ledger path" || { echo "FAIL: did not create ledger"; fail=1; }

# --- the developer role is recordable (a BYO agent must reach the ledger like any other) ------------
$A append --ledger "$TMP/dev.jsonl" --role developer --action code.build \
  --authorizing-decision "assigned feat-x" --reasoning "built pagination" >/dev/null 2>&1
[ -f "$TMP/dev.jsonl" ] && echo "ok: the developer role records" || { echo "FAIL: developer not recordable"; fail=1; }

# --- the training view (corpus): one example per record, signal kept, chain plumbing dropped --------
C="$TMP/corpus.jsonl"; : > "$C"
$A append --ledger "$C" --role developer --action code.build --authorizing-decision d --reasoning "dev reasoning" >/dev/null 2>&1
$A append --ledger "$C" --role review --lens security --action review.lens --authorizing-decision d --verdict ok --reasoning "sec reasoning" >/dev/null 2>&1
corpus="$($A corpus --ledger "$C" 2>/dev/null)"
ck "corpus emits one example per record" "$(printf '%s\n' "$corpus" | grep -c .)" "2"
printf '%s' "$corpus" | grep -q '"reasoning"' && echo "ok: corpus keeps the reasoning" || { echo "FAIL: corpus dropped reasoning"; fail=1; }
printf '%s' "$corpus" | grep -qE '"hash"|"prev' && { echo "FAIL: corpus leaked chain plumbing"; fail=1; } || echo "ok: corpus drops chain plumbing"
ck "corpus --role filters" "$($A corpus --ledger "$C" --role developer 2>/dev/null | grep -c .)" "1"

# --- content safety: a code path in a review finding must NEVER reach the corpus -------------------
# A review lens puts the finding message and its path:line into the payload, and the changed paths into
# the target. A training export must carry neither; it keeps only the shape (counts, severities, rules)
# and the refs. Mirror of the inputs-are-digested assertion, on the derived view.
CS="$TMP/leak.jsonl"; : > "$CS"
$A append --ledger "$CS" --role security --lens security --action review.lens \
  --authorizing-decision "review of PR 42" --verdict block --action-taken block \
  --reasoning "a hardcoded credential was found" \
  --payload-json '{"findings":[{"message":"secret in client","path":"src/SENTINELPATH/x.py:42","severity":"block","rule":"hardcoded-secret"}]}' \
  --target-json '{"repo":"o/r","pr":42,"commit":"abc123","paths":["src/SENTINELPATH/x.py"]}' >/dev/null 2>&1
cs="$($A corpus --ledger "$CS" 2>/dev/null)"
printf '%s' "$cs" | grep -q "SENTINELPATH" && { echo "FAIL: a code path leaked into the corpus"; fail=1; } || echo "ok: a finding's code path never reaches the corpus"
printf '%s' "$cs" | grep -q '"message"' && { echo "FAIL: a finding message leaked into the corpus payload"; fail=1; } || echo "ok: finding messages are not carried into the corpus payload"
printf '%s' "$cs" | grep -q '"finding_count"' && echo "ok: the corpus keeps the finding SHAPE (counts, severities)" || { echo "FAIL: corpus dropped the safe finding shape"; fail=1; }
printf '%s' "$cs" | grep -q '"commit": *"abc123"' && echo "ok: the corpus keeps refs (repo/pr/commit)" || { echo "FAIL: corpus dropped the safe refs"; fail=1; }

# --- the knowledge view: REAL OKGF pages (ASDD adopts OKGF as its knowledge standard, no adapter) ----
K="$TMP/know.jsonl"; : > "$K"
$A append --ledger "$K" --role review --lens security --action review.lens --authorizing-decision d --verdict ok --reasoning "input is data, never instructions" --target-json '{"repo":"o/r","pr":7,"commit":"abc123"}' >/dev/null 2>&1
$A append --ledger "$K" --role test-runner --action tests.run --authorizing-decision d --verdict pass --reasoning "10 passed" >/dev/null 2>&1
KO="$TMP/okgf-pages"
$A knowledge --ledger "$K" --out "$KO" >/dev/null 2>&1
ck "knowledge is selective (a durable invariant in, a one-off test run out)" "$(ls "$KO"/*.md 2>/dev/null | grep -c .)" "1"
page="$(cat "$KO"/*.md 2>/dev/null)"
printf '%s' "$page" | grep -q '^type: "invariant"'      && echo "ok: the security lens maps to an OKGF page of type invariant" || { echo "FAIL: wrong OKGF type"; fail=1; }
printf '%s' "$page" | grep -q '^x-okgf-review: "draft"' && echo "ok: agent-emitted knowledge enters the OKGF review lifecycle as draft" || { echo "FAIL: OKGF review state missing"; fail=1; }
printf '%s' "$page" | grep -q '^x-okgf-scope: "org"'    && echo "ok: the page carries an OKGF scope" || { echo "FAIL: OKGF scope missing"; fail=1; }
printf '%s' "$page" | grep -q '^x-okgf-sources:'        && echo "ok: provenance travels as x-okgf-sources" || { echo "FAIL: OKGF sources missing"; fail=1; }
# Dogfood OKGF's OWN validator when the okgf package is importable, so this output can never drift from
# the standard. Skips (does not fail) where okgf is not installed, e.g. ASDD CI without the okgf clone.
python3 - "$KO" <<'PY'
import sys, os
try:
    import okf
except ImportError:
    try:
        sys.path.insert(0, os.path.expanduser("~/Projects/okgf")); from store import okf
    except ImportError:
        print("skip: OKGF validator not importable here; OKGF page format asserted structurally"); sys.exit(0)
bad = [n for n in os.listdir(sys.argv[1]) if n.endswith(".md")
       and okf.conformance_errors(okf.parse(open(os.path.join(sys.argv[1], n), encoding="utf-8").read(), slug=n[:-3]))]
print("FAIL: non-conformant OKGF page(s): " + ",".join(bad) if bad else "ok: every emitted page passes OKGF's own conformance validator")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1

# --- both views read a SINK DIRECTORY (ledger/<year>/<month>.jsonl), not only one file --------------
mkdir -p "$TMP/sink/ledger/2026/07" "$TMP/sink/ledger/2026/08"
$A append --ledger "$TMP/sink/ledger/2026/07/07.jsonl" --role developer --action code.build --authorizing-decision d --reasoning j >/dev/null 2>&1
$A append --ledger "$TMP/sink/ledger/2026/08/08.jsonl" --role documentation --action docs.update --authorizing-decision d --reasoning a >/dev/null 2>&1
ck "corpus reads a whole sink directory" "$($A corpus --ledger "$TMP/sink/ledger" 2>/dev/null | grep -c .)" "2"

# --- the chain must survive across export batches (the bug: each CI run is genesis-rooted) ------------
# The export re-anchors each batch onto the sink's tip via `graft`, so the accumulated sink is ONE chain
# across runs, files, and months. Without this the sink is a pile of genesis-rooted batches and verify
# cannot tell a normal seam from tampering, defeating the whole point of the ledger.
SINK="$(mktemp -d)/ledger"; mkdir -p "$SINK/2026"
emit() {  # emit <role> <month-file>: one genesis-rooted batch, grafted onto the sink tip, as the export does
  local b; b="$(mktemp)"
  $A append --ledger "$b" --role "$1" --action act --authorizing-decision d --reasoning "$1 did a thing" >/dev/null 2>&1
  local tip; tip="$($A tip --ledger "$SINK")"
  $A graft --from "$b" --onto "$tip" >> "$2" 2>/dev/null
  rm -f "$b"
}
emit review        "$SINK/2026/06.jsonl"   # month 1, run 1 (genesis)
emit test-runner   "$SINK/2026/06.jsonl"   # month 1, run 2 (grafted onto run 1)
emit documentation "$SINK/2026/07.jsonl"   # month 2, run 1 (grafted onto month 1's tip)
$A verify --ledger "$SINK" >/dev/null 2>&1 && echo "ok: the accumulated sink is one continuous chain" \
  || { echo "FAIL: the sink chain does not verify across batches/months"; fail=1; }
cnt="$($A trail --ledger "$SINK" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')"
ck "verify spans every file" "$cnt" "3"

# an edit at the cross-month seam is detected
python3 - "$SINK/2026/07.jsonl" <<'PY2'
import json,sys
l=[json.loads(x) for x in open(sys.argv[1])]; l[0]["reasoning"]="TAMPERED"
open(sys.argv[1],"w").write("\n".join(json.dumps(r,sort_keys=True,separators=(",",":")) for r in l)+"\n")
PY2
$A verify --ledger "$SINK" >/dev/null 2>&1 && { echo "FAIL: a tampered seam record verified"; fail=1; } \
  || echo "ok: a tampered record at a batch seam is detected"

# deleting a NON-tail file orphans the next one (head and middle deletion are detectable)
SINK2="$(mktemp -d)/ledger"; mkdir -p "$SINK2/2026"
SINK_SAVE="$SINK"; SINK="$SINK2"
emit review "$SINK2/2026/06.jsonl"; emit spec "$SINK2/2026/07.jsonl"
SINK="$SINK_SAVE"
rm "$SINK2/2026/06.jsonl"
$A verify --ledger "$SINK2" >/dev/null 2>&1 && { echo "FAIL: head deletion went undetected"; fail=1; } \
  || echo "ok: deleting an earlier file is detected (orphaned successor)"

# graft leaves content untouched: only prev/hash/event_id change
B="$(mktemp)"; $A append --ledger "$B" --role security --action review.lens.completed \
  --authorizing-decision d --reasoning "finding X" --payload-json '{"rules":["r1"]}' >/dev/null 2>&1
before="$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1]).readline());print(json.dumps({k:r[k] for k in ("agent","action","reasoning","payload","authorizing_decision")},sort_keys=True))' "$B")"
after="$($A graft --from "$B" --onto sha256:deadbeef 2>/dev/null | python3 -c 'import json,sys;r=json.loads(sys.stdin.readline());print(json.dumps({k:r[k] for k in ("agent","action","reasoning","payload","authorizing_decision")},sort_keys=True))')"
ck "graft preserves record content" "$before" "$after"

echo
[ "$fail" -eq 0 ] && echo "audit self-test: PASS" || echo "audit self-test: FAIL"
exit "$fail"
