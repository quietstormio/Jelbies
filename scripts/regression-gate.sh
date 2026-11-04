#!/bin/zsh
# Regression gate: builds the last user-approved commit (.approved-build) and HEAD in throwaway worktrees, runs the behaviour-count suite
# (BobV1Tests/RoomSFXCountTests: per-kind idle / antic / social counts, vocal chatter, contact + jump SFX, room-cue haptic sink calls; HapticSinkRegressionTests: touch /
# cuddle haptics at the sink) with fixed seeds on both, and FAILS if any pre-existing kind drops below 90 % of the approved build, the touch haptics reach the sink less
# than on the approved build, a move lacks a haptic pattern (HapticCueTests), or EmoteFeetTests / GroupEmote*Tests / LineupTests fail.
# MANDATORY before installing any build on the user's phone (docs/HANDOFF.md). ~25 min (first run builds twice; derived data is reused: $ROOT/.claude/worktrees/dd_gate_*).
#   scripts/regression-gate.sh            run the gate on committed HEAD
#   scripts/regression-gate.sh --clean    also delete the derived data afterwards
set -u
ROOT=${0:A:h:h}
WT=$ROOT/.claude/worktrees
APPROVED=$(tr -d ' \n' < $ROOT/.approved-build)
HEADC=$(git -C $ROOT rev-parse --short HEAD)
OUT=$(mktemp -d /tmp/gate.XXXXXX)
# persistent copy of the logs and tables (OUT is removed by the exit trap): ~/BobV1_backups/gate_logs/<head>_<timestamp>/
KEEP=$HOME/BobV1_backups/gate_logs/${HEADC}_$(date +%Y%m%d_%H%M%S)
mkdir -p $KEEP
SIM=""
# copies whatever logs / count files exist so far (the build log of a failed build, test.log of each run, the per-kind count files) and prints where they are
keep_logs() {
  cp -f $OUT/*.log $OUT/*.txt $KEEP/ 2>/dev/null
  echo "gate logs kept in: $KEEP"
}
cleanup() {
  [[ -n "$SIM" ]] && { xcrun simctl shutdown $SIM 2>/dev/null; xcrun simctl delete $SIM 2>/dev/null; }
  git -C $ROOT worktree remove --force $WT/gate_approved 2>/dev/null
  git -C $ROOT worktree remove --force $WT/gate_head 2>/dev/null
  [[ "${1:-}" == "--clean" ]] && rm -rf $WT/dd_gate_approved $WT/dd_gate_head
  keep_logs
  rm -rf $OUT
}
trap 'cleanup ${CLEAN:-}' EXIT
[[ "${1:-}" == "--clean" ]] && CLEAN=--clean
[[ -n "$(git -C $ROOT status --porcelain --untracked-files=no | grep -v xcuserdata)" ]] && echo "note: uncommitted changes are NOT gated (HEAD $HEADC is)"
echo "gate: approved $APPROVED vs HEAD $HEADC"
git -C $ROOT worktree remove --force $WT/gate_approved 2>/dev/null; git -C $ROOT worktree remove --force $WT/gate_head 2>/dev/null
git -C $ROOT worktree add --detach $WT/gate_approved $APPROVED >/dev/null || exit 2
git -C $ROOT worktree add --detach $WT/gate_head $HEADC >/dev/null || exit 2
# the approved build gets HEAD's portable test files (the counts are the same code path; lines marked NEWONLY use APIs the approved build lacks)
cp $WT/gate_head/BobV1Tests/HapticSinkRegressionTests.swift $WT/gate_approved/BobV1Tests/
sed -e 's/lab.tick(); simNow += 1.0 \/ 60.*/lab.tick()/' -e '/NEWONLY-BEGIN/,/NEWONLY-END/d' -e '/NEWONLY/d' $WT/gate_head/BobV1Tests/RoomSFXCountTests.swift > $WT/gate_approved/BobV1Tests/RoomSFXCountTests.swift
# newest available iOS runtime that offers an iPhone 17-class device type (plain iPhone 17 first, then Pro / 16 / any iPhone)
PICK=$(xcrun simctl list -j runtimes | python3 -I -c '
import json, sys
def key(r): return ([int(x) for x in r["version"].split(".")], r.get("buildversion", ""))
want = ["iPhone-17", "iPhone-17-Pro", "iPhone-16", "iPhone-16-Pro"]
for r in sorted((r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform", "iOS") == "iOS"), key=key, reverse=True):
    ids = [d["identifier"] for d in r.get("supportedDeviceTypes", [])]
    for w in want:
        t = "com.apple.CoreSimulator.SimDeviceType." + w
        if t in ids: print(t, r["identifier"]); sys.exit(0)
') || exit 2
[[ -n "$PICK" ]] || { echo "GATE FAIL: no iOS runtime with an iPhone 17-class device type"; exit 2; }
echo "gate sim: $PICK"
SIM=$(xcrun simctl create gate-sim ${=PICK}) || exit 2
xcrun simctl boot $SIM
run() {  # tree, derived data, env prefix args..., tests...
  local tree=$1 dd=$2; shift 2
  ( cd $tree && xcodebuild build-for-testing -scheme BobV1 -configuration Release ENABLE_TESTABILITY=YES -destination "id=$SIM" -derivedDataPath $dd -parallel-testing-enabled NO >$OUT/build.log 2>&1 ) || { cp -f $OUT/build.log $KEEP/build_${tree:t}.log 2>/dev/null; grep -E "error:" $OUT/build.log | sort -u | head -20; tail -5 $OUT/build.log; echo "GATE FAIL: build of $tree"; return 1; }
  ( cd $tree && env "$@" xcodebuild test-without-building -scheme BobV1 -configuration Release ENABLE_TESTABILITY=YES -destination "id=$SIM" -derivedDataPath $dd -parallel-testing-enabled NO ${=TESTS} 2>&1 | tee $OUT/test.log | grep -E "error:|failed|Executed|TEST (EXECUTE|SUCCEEDED|FAILED)" | tail -15; exit ${pipestatus[1]} )
  local st=$?
  cp -f $OUT/test.log $KEEP/test_${tree:t}.log 2>/dev/null          # (test.log is rewritten by the next run: keep each one)
  echo "-- failing tests:"; grep -E "Test Case .* failed \(" $OUT/test.log | sed 's/.*-\[BobV1Tests\.//' | sort -u
  grep -E ": error: -\[BobV1Tests" $OUT/test.log | sed "s/.*error: -\[BobV1Tests\.//" | cut -c1-300          # (one line per failed assertion: "Executed N tests, with K failures" counts assertions, not tests)
  return $st
}
TESTS="-only-testing:BobV1Tests/RoomSFXCountTests/testCountRoomSoundRequests -only-testing:BobV1Tests/HapticSinkRegressionTests"
echo "== approved $APPROVED"
run $WT/gate_approved $WT/dd_gate_approved TEST_RUNNER_SFXCOUNT_OUT=$OUT/base.txt TEST_RUNNER_HAPTICSINK_OUT=$OUT/hbase.txt || { echo "GATE FAIL: approved build run"; exit 1; }
FAIL=0
TESTS="-only-testing:BobV1Tests/RoomSFXCountTests -only-testing:BobV1Tests/HapticSinkRegressionTests -only-testing:BobV1Tests/HapticCueTests -only-testing:BobV1Tests/EmoteFeetTests -only-testing:BobV1Tests/GroupEmoteFeetTests -only-testing:BobV1Tests/GroupEmoteTests -only-testing:BobV1Tests/LineupTests"
echo "== HEAD $HEADC"
run $WT/gate_head $WT/dd_gate_head TEST_RUNNER_SFXCOUNT_BASELINE=$OUT/base.txt TEST_RUNNER_SFXCOUNT_OUT=$OUT/head.txt TEST_RUNNER_HAPTICSINK_OUT=$OUT/hhead.txt || FAIL=1
# touch / cuddle haptics at the sink: HEAD >= approved, every channel
for key in transient wobble continuous; do
  a=$(grep -o "$key=[0-9]*" $OUT/hbase.txt | cut -d= -f2); h=$(grep -o "$key=[0-9]*" $OUT/hhead.txt | cut -d= -f2)
  echo "haptic sink $key: approved ${a:-?} head ${h:-?}"
  [[ -z "$a" || -z "$h" || $h -lt $a ]] && { echo "GATE FAIL: touch haptic sink calls ($key) dropped"; FAIL=1; }
done
echo "== per-kind table (approved / head)"
python3 -I - $OUT/base.txt $OUT/head.txt 2>&1 <<'PY' | tee $OUT/table.txt
import sys
def parse(p):
    try: return {k: int(v) for k, v in (t.split("=") for t in open(p).read().split()[1:])}
    except Exception: return {}
a, h = parse(sys.argv[1]), parse(sys.argv[2])
for k in sorted(set(a) | set(h)):
    flag = "  <-- below 90%" if a.get(k, 0) >= 12 and h.get(k, 0) < 0.9 * a[k] else ""
    print(f"{k:28s}{a.get(k,0):6d}{h.get(k,0):6d}{flag}")
PY
[[ $FAIL -eq 0 ]] && echo "GATE PASSED" || echo "GATE FAILED"
exit $FAIL
