#!/bin/zsh
# Real-app capture of the track meet with a roster of two (RaceThreeUITests). Usage: scripts/race_three_capture.sh <out dir>   Env: ROSTER (teddy,panda), SEED (7), SIM (udid), DD (derived data, already built-for-testing in Release with ENABLE_TESTABILITY=YES), SECS (90).
# Launches with -Mute 1 (the simulator audio path stalled the main thread about 1 s per frame once the race music started). Streams the app's [melon] perf lines to <out>/perf.log (a run under ~20 fps is starved: do not trust it).
set -u
OUT=${1:?out dir}; mkdir -p $OUT; OUT=$(cd $OUT && pwd); SECS=${SECS:-90}; DD=${DD:?derived data}; UDID=${SIM:?sim udid}
cd "$(dirname "$0")/.."
setopt nonomatch; rm -f $OUT/race.mark $OUT/race.mov $OUT/s_*.png
CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_SECS=$SECS TEST_RUNNER_CAPTURE_ROSTER=${ROSTER:-teddy,panda} TEST_RUNNER_CAPTURE_LANDSCAPE=${LANDSCAPE:-0} TEST_RUNNER_CAPTURE_SEED=${SEED:-7} xcodebuild test-without-building -project BobV1.xcodeproj -scheme BobV1 -configuration Release -destination "id=$UDID" -derivedDataPath $DD -parallel-testing-enabled NO -only-testing:BobV1UITests/RaceThreeUITests/testThreeRacers </dev/null >$OUT/xcodebuild.log 2>&1 &
TPID=$!
xcrun simctl spawn $UDID log stream --style compact --predicate 'eventMessage CONTAINS "[melon]"' </dev/null >$OUT/perf.log 2>&1 &
LPID=$!
for i in {1..2400}; do [ -f $OUT/race.mark ] && break; kill -0 $TPID 2>/dev/null || break; sleep 0.5; done
RPID=""
if [ -f $OUT/race.mark ]; then xcrun simctl io $UDID recordVideo --codec h264 --force $OUT/race.mov </dev/null >/dev/null 2>&1 & RPID=$!; fi
wait $TPID
if [ -n "$RPID" ]; then python3 -c "import os,signal,sys; os.kill(int(sys.argv[1]), signal.SIGINT)" $RPID; wait $RPID 2>/dev/null; sleep 1; fi
kill $LPID 2>/dev/null
ls $OUT | head -5; ls $OUT | wc -l
