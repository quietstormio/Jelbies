#!/bin/zsh
# Real-app chirp check: do the Jelbies actually make their roaming sounds in the REAL app (not a unit soak)?
# Creates its OWN simulator, installs a Release app, launches the day room with 3 Jelbies and `-AudioLog 1`, skips the first 20 s, then counts `[audio] chirp`
# lines (the ones AudioHub.chirp prints after every guard) over a fixed 90 s window and prints the drop-reason histogram of every `[audio] req` line.
#   scripts/realapp-chirp-check.sh /path/to/BobV1.app          install this already-built Release simulator app
#   scripts/realapp-chirp-check.sh --build /path/to/derivedData  build Release for the simulator into that derived-data dir first
# Exit codes: 0 pass, 1 chirps/min below the floor, 2 setup failed, 3 INVALID RUN (the simulator was starved, see below: the result says nothing about the app).
#
# CHIRP_FLOOR (default 3 chirps/min, 3 Jelbies): the unit soak (BobV1Tests/RoomSFXCountTests, scripts/baseline-roomsfx.txt) shows roughly 5 chirp / babble
# requests per minute for three roaming Jelbies; the floor is 60 % of that. It is provisional: it was chosen BEFORE a non-starved real-app capture existed
# (the host was overloaded when this was written), so re-calibrate it from the first healthy run (60 % of that rate).
# The floor assumes a NON-starved sim. A loaded Mac or a headless simulator can deliver a frame every few seconds; the Jelbies then barely move and zero chirps
# is expected. So the run is rejected (exit 3) unless the simulated seconds (sum of the per-window `N steps` of the `[melon] perf:` lines / 60) reach 80 % of
# the 90 s window. Never use pkill / killall / `simctl shutdown all`: only the sim this script created is shut down and deleted (trap), even on failure.
set -u
ROOT=${0:A:h:h}
FLOOR=${CHIRP_FLOOR:-3}
SKIP=20; WINDOW=90
APP=""; BUILD_DD=""
if [[ "${1:-}" == "--build" ]]; then BUILD_DD=${2:?derived data dir}; else APP=${1:?usage: realapp-chirp-check.sh <BobV1.app> | --build <derivedData>}; fi
OUT=$(mktemp -d /tmp/chirpcheck.XXXXXX)
SIM=""
cleanup() {
  [[ -n "$SIM" ]] && { xcrun simctl shutdown $SIM 2>/dev/null; xcrun simctl delete $SIM 2>/dev/null; }
  rm -rf $OUT
}
trap cleanup EXIT

if [[ -n "$BUILD_DD" ]]; then
  xcodebuild -project $ROOT/BobV1.xcodeproj -scheme BobV1 -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath $BUILD_DD \
    ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO build > $OUT/build.log 2>&1 || { tail -20 $OUT/build.log; exit 2; }
  APP=$BUILD_DD/Build/Products/Release-iphonesimulator/BobV1.app
fi
[[ -d "$APP" ]] || { echo "no app at $APP"; exit 2; }

# the newest iOS runtime that has an iPhone 17 device type
RT=$(xcrun simctl list -j runtimes | python3 -I -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform", "iOS") == "iOS"
      and any(d["identifier"].endswith("iPhone-17") for d in r.get("supportedDeviceTypes", []))]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')
[[ -n "$RT" ]] || { echo "no iOS runtime with an iPhone 17"; exit 2; }
SIM=$(xcrun simctl create chirpcheck-$$ com.apple.CoreSimulator.SimDeviceType.iPhone-17 $RT) || exit 2
xcrun simctl boot $SIM && xcrun simctl bootstatus $SIM >/dev/null 2>&1
xcrun simctl install $SIM "$APP" || exit 2

# the console stream is read live: the window is cut by the log's own timestamps, not by when the shell started
timeout $((SKIP + WINDOW + 25)) xcrun simctl launch --console --terminate-running-process $SIM io.mgsllc.BobV1 \
  -SetRoster bob,pip,moss -MainMenu 0 -Intro 0 -Jelbies.started.v1 YES -ClockHour 12 -BlobDrops.v1 1024 -AudioLog 1 > $OUT/console.log 2>&1

python3 -I - $OUT/console.log $SKIP $WINDOW $FLOOR <<'PY'
import re, sys, collections, datetime
path, skip, window, floor = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
ts = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)")
def t(line):
    m = ts.match(line)
    return datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp() if m else None
lines = open(path, errors="replace").read().splitlines()
first = next((t(l) for l in lines if "first frame drawn" in l and t(l)), None) or next((t(l) for l in lines if t(l)), None)
if first is None: print("no console output"); sys.exit(2)
lo, hi = first + skip, first + skip + window
hist = collections.Counter(); chirps = 0; steps = 0
for l in lines:
    x = t(l)
    if x is None or not (lo <= x < hi): continue
    if "[audio] chirp " in l: chirps += 1
    m = re.search(r"\[audio\] req (\S+) slot \S+ -> (.*)$", l)
    if m: hist[(m.group(1), m.group(2).split(" ")[0] if m.group(2).startswith(("level", "scene")) else m.group(2))] += 1
    m = re.search(r"(\d+) steps\), skin", l)
    if m: steps += int(m.group(1))
sim_s = steps / 60.0
print(f"window {window:.0f} s after +{skip:.0f} s: {chirps} chirps = {chirps * 60 / window:.1f} per minute (floor {floor}); simulated {sim_s:.1f} s of {window:.0f} s")
print("drop-reason histogram (request, reason: count):")
for (what, why), n in sorted(hist.items(), key=lambda kv: -kv[1]): print(f"  {what:24s} {why:20s} {n}")
if sim_s < 0.8 * window:
    print(f"INVALID RUN: the simulator was starved ({sim_s:.1f} simulated s in {window:.0f} s wall); the chirp rate says nothing. Retry on a less loaded Mac."); sys.exit(3)
if chirps * 60 / window < floor: print("FAIL: below the floor"); sys.exit(1)
print("PASS")
PY
