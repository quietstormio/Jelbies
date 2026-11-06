#!/bin/zsh
# Real-app video of a hurdle jump (RaceLegsUITests). Usage: scripts/race_legs_capture.sh <out dir>   Env: SIM (udid), DD (derived data), SECS (70), CONFIG (Debug: the UI-test target does not build in Release).
set -u
OUT=${1:?out dir}; mkdir -p $OUT; OUT=$(cd $OUT && pwd); SECS=${SECS:-70}; CONFIG=${CONFIG:-Debug}; DD=${DD:?derived data}; UDID=${SIM:?sim udid}
cd "$(dirname "$0")/.."
rm -f $OUT/hurdle.mark $OUT/hurdle.mov
CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_SECS=$SECS xcodebuild test -project BobV1.xcodeproj -scheme BobV1 -configuration $CONFIG -destination "id=$UDID" -derivedDataPath $DD -parallel-testing-enabled NO -only-testing:BobV1UITests/RaceLegsUITests/testHurdleJump </dev/null >$OUT/xcodebuild.log 2>&1 &
TPID=$!
for i in {1..2400}; do [ -f $OUT/hurdle.mark ] && break; kill -0 $TPID 2>/dev/null || break; sleep 0.5; done
RPID=""
if [ -f $OUT/hurdle.mark ]; then xcrun simctl io $UDID recordVideo --codec h264 --force $OUT/hurdle.mov </dev/null >/dev/null 2>&1 & RPID=$!; fi
wait $TPID
if [ -n "$RPID" ]; then python3 -c "import os,signal,sys; os.kill(int(sys.argv[1]), signal.SIGINT)" $RPID; wait $RPID 2>/dev/null; sleep 1; fi
ls -la $OUT
