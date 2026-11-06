#!/bin/zsh
# Real-app video of sleeping Jelbies, no XCTest (the XCTest host mutes the audio hub, so no PLAYED lines). Usage: scripts/sleep_video_capture.sh <out dir> <name>
# Env: SIM (udid), APP (BobV1.app), SECS (90), ROSTER (bob,teddy,panda). Rotate the sim by hand first for landscape.
set -u
OUT=${1:?out dir}; NAME=${2:?name}; mkdir -p $OUT; SECS=${SECS:-90}; UDID=${SIM:?}; APP=${APP:?}; ROSTER=${ROSTER:-bob,teddy,panda}
xcrun simctl install $UDID $APP || exit 1
xcrun simctl terminate $UDID io.mgsllc.BobV1 2>/dev/null
xcrun simctl launch --console $UDID io.mgsllc.BobV1 -ClockHour 3 -SleepNow 1 -AudioLog 1 -MainMenu 0 -Intro 0 -Jelbies.started.v1 YES -SetRoster $ROSTER -BlobDrops.v1 1024 </dev/null >$OUT/$NAME.log 2>&1 &
LPID=$!
sleep 25    # let them go to bed
xcrun simctl io $UDID recordVideo --codec h264 --force $OUT/$NAME.mov </dev/null >/dev/null 2>&1 &
RPID=$!
date +%s > $OUT/$NAME.t0
sleep $SECS
date +%s > $OUT/$NAME.t1
python3 -I -c "import os,signal,sys; os.kill(int(sys.argv[1]), signal.SIGINT)" $RPID; wait $RPID 2>/dev/null; sleep 1
xcrun simctl terminate $UDID io.mgsllc.BobV1
wait $LPID 2>/dev/null
echo captured
