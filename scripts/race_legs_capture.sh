#!/bin/zsh
# Real-app video of a hurdle jump (RaceLegsUITests). Usage: scripts/race_legs_capture.sh <out dir>   Env: TEST_RUNNER_CAPTURE_ROSTER (e.g. lavender,teddy), TEST_RUNNER_CAPTURE_EARLY=1 (record from launch), TEST_RUNNER_CAPTURE_JUMP_EVERY=<s> (-RaceJumpEvery), SIM (udid), DD (derived data), SECS (70), CONFIG (Release with ENABLE_TESTABILITY=YES: the Debug sim steps at ~270 ms per frame, too slow to race).
set -u
OUT=${1:?out dir}; mkdir -p $OUT; OUT=$(cd $OUT && pwd); SECS=${SECS:-70}; CONFIG=${CONFIG:-Release}; DD=${DD:?derived data}; UDID=${SIM:?sim udid}
cd "$(dirname "$0")/.."
xcodebuild build-for-testing -project BobV1.xcodeproj -scheme BobV1 -configuration $CONFIG -destination "id=$UDID" -derivedDataPath $DD ENABLE_TESTABILITY=YES -quiet || exit 1
rm -f $OUT/hurdle.mark $OUT/hurdle.mov
CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_SECS=$SECS xcodebuild test-without-building -project BobV1.xcodeproj -scheme BobV1 -configuration $CONFIG -destination "id=$UDID" -derivedDataPath $DD -parallel-testing-enabled NO -only-testing:BobV1UITests/RaceLegsUITests/testHurdleJump </dev/null >$OUT/xcodebuild.log 2>&1 &
TPID=$!
for i in {1..2400}; do [ -f $OUT/hurdle.mark ] && break; kill -0 $TPID 2>/dev/null || break; sleep 0.5; done
RPID=""
if [ -f $OUT/hurdle.mark ]; then xcrun simctl io $UDID recordVideo --codec h264 --force $OUT/hurdle.mov </dev/null >$OUT/record.log 2>&1 & RPID=$!; fi
wait $TPID
if [ -n "$RPID" ]; then python3 -c "import os,signal,sys; os.kill(int(sys.argv[1]), signal.SIGINT)" $RPID; wait $RPID 2>/dev/null; sleep 1; fi
ls -la $OUT
