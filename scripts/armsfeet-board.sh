#!/bin/bash
# Usage: armsfeet-board.sh <simulator udid> <path to a built SIMULATOR BobV1.app (Release)> <output dir>
# The fixed real-app board for arms and feet: records the same scenes with the same launch arguments every time, cuts fixed frames
# and writes ONE labelled contact sheet <output dir>/board.png (each tile = the creature's crop, enlarged ~3x). Compare boards by eye between builds.
# Scenes: Jelly Spring pages (UI test SpringArmUITests, needs the test build next to the app: <dd>/Build/Products/Release-iphonesimulator/BobV1.app),
#   own wave, guest wave, walk/run with three at home, pull race with one at home, Show with one at home, first two seconds after launch with one at home.
# -FootLog 1 is on in every room scene: <out>/footlog/<scene>.jsonl + footlog_summary.txt (gap / pull events per scene; the Spring scene has none).
# Guards: before each recording 1-min load < 6 and no xcodebuild (QUIET_XB_MAX=n tolerates n of other people's xcodebuild processes; load < 6 still applies) (30 s sleeps, max 25 min, then the scene is skipped and says so); kills only its own PIDs.
# Env: ONLY="wave_own race_pull1" runs just those scenes (names as in the scene lines below, "spring" too). Needs python3 with PIL, numpy, scipy. Delete the simulator yourself.
# Tiles are timed from t0 = the first frame that differs from the pre-launch screen, so a slow start does not move them.
set -u
U="${1:?usage: armsfeet-board.sh <udid> <BobV1.app> <out dir>}"; APP="${2:?app}"; OUT="${3:?out dir}"
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
mkdir -p "$OUT/vid" "$OUT/footlog" "$OUT/frames"; OUT="$(cd "$OUT" && pwd)"; APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
DD="$(cd "$APP/../../../.." && pwd)"; BID=io.mgsllc.BobV1
FFMPEG=/opt/homebrew/bin/ffmpeg
: > "$OUT/scenes.tsv"; : > "$OUT/footlog_summary.txt"

quiet() { local i l n; for i in $(seq 1 50); do l=$(sysctl -n vm.loadavg | awk '{print $2}'); n=$(pgrep -x xcodebuild | wc -l | tr -d ' ')
  if awk "BEGIN{exit !($l < 6)}" && [ "$n" -le "${QUIET_XB_MAX:-0}" ]; then return 0; fi; sleep 30; done; return 1; }
want() { [ -z "${ONLY:-}" ] && return 0; for w in $ONLY; do [ "$w" = "$1" ] && return 0; done; return 1; }

xcrun simctl boot "$U" 2>/dev/null; xcrun simctl bootstatus "$U" -b >/dev/null 2>&1
xcrun simctl install "$U" "$APP" || { echo "install failed"; exit 1; }
xcrun simctl status_bar "$U" override --time 9:41 >/dev/null 2>&1

# scene <name> <species to track csv> <crop size px> <times s after the app appears> <seconds to record> <newgame csv> <launch args...>
scene() {
  local name="$1" sp="$2" size="$3" times="$4" secs="$5" ng="$6"; shift 6
  want "$name" || return 0
  quiet || { echo "SKIPPED $name: machine never quiet"; return 0; }
  xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1
  local c; c=$(xcrun simctl get_app_container "$U" "$BID" data 2>/dev/null); [ -n "$c" ] && rm -f "$c/Documents/foot_log.jsonl"
  rm -f "$OUT/vid/$name.mp4"; rm -rf "$OUT/frames/$name"
  xcrun simctl io "$U" recordVideo --codec h264 --force "$OUT/vid/$name.mp4" >/dev/null 2>&1 & local rp=$!; sleep 1.5
  xcrun simctl launch "$U" "$BID" -NewGame "$ng" -NewGameCoins 10000 -NeedsHappy 1 -Mute 1 -MainMenu 0 -FootLog 1 "$@" </dev/null >/dev/null 2>&1
  sleep "$secs"
  kill -INT "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
  c=$(xcrun simctl get_app_container "$U" "$BID" data 2>/dev/null)
  [ -f "$c/Documents/foot_log.jsonl" ] && cp "$c/Documents/foot_log.jsonl" "$OUT/footlog/$name.jsonl"
  xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1
  printf '%s\t%s\t%s\t%s\n' "$name" "$sp" "$size" "$times" >> "$OUT/scenes.tsv"
  echo "$name: $( [ -f "$OUT/footlog/$name.jsonl" ] && wc -l < "$OUT/footlog/$name.jsonl" || echo 0) foot-log events"
}
# tracked species = the -NewGame names (bob blue, pip yellow, moss green, lavender purple); crop sizes in video pixels (iPhone 17 Pro recording, 1206x2622)
scene wave_own   bob          500 2,2.5,3,3.5,4,4.5,5,5.5,6,7 16 bob -GameAction wave -GameActionDelay 3 -BlobWaveSide 1
scene guest_wave bob          500 21,22,23,24,25,26,27,28 42 bob -SeedFriends 3 -InviteGuest 1 -GuestGoodbye 25 -BlobWaveSide 1
scene walk_run3  bob,pip,moss 500 3,6,9,12,15,18 26 bob,pip,moss
scene race_pull1 lavender     500 3,6,10,14,18,22,26,30,34,38 50 lavender -RaceStart 1 -RaceJelly 0 -RaceSeed 7 -RaceAuto 4 -RaceCourse ripple -RaceControl pull -RaceJumpEvery 3
scene show1      lavender     500 6,12,20,30,40,50,60,70 80 lavender -ShowStart 1 -ShowAuto 1
scene launch1    lavender     500 0.0,0.3,0.6,0.9,1.2,1.5,1.8,2.1 10 lavender

# the Jelly Spring pages: the UI test switches through the seven species while a recording runs
if want spring; then
  if quiet; then
    xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1; rm -f "$OUT/vid/spring.mp4"; rm -rf "$OUT/frames/spring"
    mkdir -p "$OUT/spring_marks"; rm -f "$OUT/spring_marks/marks.txt"
    xcrun simctl io "$U" recordVideo --codec h264 --force "$OUT/vid/spring.mp4" >/dev/null 2>&1 & rp=$!
    python3 -I -c "import time; print(time.time())" > "$OUT/spring_marks/vstart.txt"; sleep 1.5      # (wall clock when the recording was started: the python page finder aligns the UI test's marks.txt to the video with it)
    ( cd "$root" && TEST_RUNNER_SPRING_OUT="$OUT/spring_marks" TEST_RUNNER_SPRING_MODE=calm TEST_RUNNER_SPRING_FLAG="-BlobWaveSide 1 -PickerYaw -0.5" TEST_RUNNER_SPRING_ROUNDS=1 \
      caffeinate -i xcodebuild test-without-building -project BobV1.xcodeproj -scheme BobV1 -configuration Release -destination "id=$U" -derivedDataPath "$DD" \
      -only-testing:BobV1UITests/SpringArmUITests -parallel-testing-enabled NO > "$OUT/spring_test.log" 2>&1 )
    kill -INT "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
    printf '%s\t%s\t%s\t%s\n' spring fixed "${SPRING_SIZE:-700}" spring >> "$OUT/scenes.tsv"
    grep -E "Test Case.*(passed|failed|skipped)|TEST (SUCCEEDED|FAILED)" "$OUT/spring_test.log" | tail -2
  else echo "SKIPPED spring: machine never quiet"; fi
fi

# foot log summary
for f in "$OUT"/footlog/*.jsonl; do [ -f "$f" ] || continue; echo "$(basename "$f" .jsonl): $(wc -l < "$f") events; first: $(head -c 300 "$f" | head -1)" >> "$OUT/footlog_summary.txt"; done
[ -s "$OUT/footlog_summary.txt" ] || echo "no foot-log events in any scene (clean)" > "$OUT/footlog_summary.txt"
python3 -I "$here/armsfeet-board.py" "$OUT"
