#!/bin/zsh
# Contact-emote captures in the REAL app. Usage: scripts/contact_capture.sh <out dir> [name prefixes to run, e.g. "swayHug lieDown"; default all rows of scripts/contact_scenes.tsv]
# Run it from the checkout of the branch to capture (g-perfint = BEFORE, g-contactmig = AFTER; that branch needs Melon/ContactDemo.swift, the GameScreen hook and
# BobV1UITests/ContactCaptureUITests.swift: merge g-contactcap into it first). Env: SECS (18), CONFIG (Release), SIM (simulator name, default contactcap; created if missing).
# Own simulator + DerivedData (dd_contactcap/ in the checkout); delete both after: xcrun simctl delete contactcap; rm -rf dd_contactcap
# The 6th column of a row = its own seconds (the lie-down takes ~14 s to start). Output per row and angle: <out>/<name>_<angle>.mp4 (cropped to the floor), the PNG frames in <out>/<name>_<angle>/, <name>_<angle>.demolog (did the emote start).
# (xcrun simctl io recordVideo wrote 0-byte .mov files on this machine, so the clips are built from the screenshot frames, ~6 fps.)
set -u
OUT=${1:?out dir}; shift; ONLY=("$@"); SECS0=${SECS:-18}; CONFIG=${CONFIG:-Release}; SIM=${SIM:-contactcap}
cd "$(dirname "$0")/.."; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
UDID=$(xcrun simctl list devices | awk -v n="$SIM" '$1==n {gsub(/[()]/,"",$2); print $2; exit}')
[ -n "$UDID" ] || UDID=$(xcrun simctl create $SIM "iPhone 18 Pro")
xcrun simctl boot $UDID 2>/dev/null; xcrun simctl bootstatus $UDID -b >/dev/null
DEST="platform=iOS Simulator,id=$UDID"
xcodebuild build-for-testing -project BobV1.xcodeproj -scheme BobV1 -configuration $CONFIG -destination "$DEST" -derivedDataPath dd_contactcap ENABLE_TESTABILITY=YES -quiet || exit 1
grep -v '^#' scripts/contact_scenes.tsv | while IFS=$'\t' read -r NAME CAST KIND ANGLES ARGS ROWSECS; do
  SECS=${ROWSECS:-${SECS0}}; [ "$ARGS" = "-" ] && ARGS=""
  [ -n "$NAME" ] || continue
  if [ ${#ONLY[@]} -gt 0 ]; then ok=0; for p in $ONLY; do [[ $NAME == $p* ]] && ok=1; done; [ $ok = 1 ] || continue; fi
  for ANGLE in ${(s:,:)ANGLES}; do
    S=${NAME}_$ANGLE; rm -f $OUT/$S.demolog
    TEST_RUNNER_CAPTURE_OUT=$OUT TEST_RUNNER_CAPTURE_NAME=$NAME TEST_RUNNER_CAPTURE_CAST=$CAST TEST_RUNNER_CAPTURE_KIND=$KIND TEST_RUNNER_CAPTURE_ANGLE=$ANGLE \
      TEST_RUNNER_CAPTURE_ARGS="$ARGS" TEST_RUNNER_CAPTURE_SECS=$SECS xcodebuild test-without-building -project BobV1.xcodeproj -scheme BobV1 -configuration $CONFIG \
      -destination "$DEST" -derivedDataPath dd_contactcap -only-testing:BobV1UITests/ContactCaptureUITests/testScene </dev/null >$OUT/xcodebuild_$S.log 2>&1
    ( cd $OUT/$S 2>/dev/null && N=$(ls f_*.png | wc -l) && ffmpeg -loglevel error -y -framerate $(( N / SECS > 0 ? N / SECS : 1 )) -pattern_type glob -i 'f_*.png' \
        -vf "crop=iw:ih*0.5:0:ih*0.2,scale=-2:900" -pix_fmt yuv420p ../$S.mp4 </dev/null ) || echo "FAILED $S"
    echo "$S: $(cat $OUT/$S.demolog 2>/dev/null | grep -v ' \(start\|at\) ' | tr '\n' ';')"
  done
done
echo "done: $OUT"
