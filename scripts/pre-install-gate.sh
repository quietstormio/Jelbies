#!/bin/bash
# Usage: pre-install-gate.sh <simulator udid> <derived data path> [<path to a built device BobV1.app>]
# Arms / feet / clothing-prep gate to run BEFORE any phone install. Exit 0 = GATE PASS, non-zero = GATE FAIL.
# Steps: (1) check-date-ops on the device app if given; (2) build-for-testing (Release, testability);
# (3) run each suite below serially with test-without-building; (4) print one table.
# Env: GATE_SKIP_BUILD=1 reuse the existing build in <derived data>; GATE_SUITES="A B" override the list;
#      GATE_SUITE_CAP=seconds per suite (default 1500); GATE_LOG_DIR=where the logs go (default <dd>/gate-logs).
# Guards: waits (30 s sleeps, max 25 min) for 1-min load < 8 and <= 1 xcodebuild before each xcodebuild; never pkill/killall; only kills its own PID on a cap.
#
# Deliberately EXCLUDED (red or not proven today):
#   SocialFeetTests       red today (known failures, pre-existing).
#   GroupEmoteFeetTests   red today (known failures, pre-existing).
#   OnePieceInvariantTests never seen to finish (runs cut off); Phase 2 of the install-gate round decides.
#   WearBandTests         red today.
#   JellyFinalTests.testTable fails because a switch is on for phone test builds (JellyLook/JellyFinal are compared by hand vs the base commit instead).
udid="${1:?usage: pre-install-gate.sh <simulator udid> <derived data path> [device BobV1.app]}"
dd="${2:?derived data path}"; devapp="${3:-}"
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"; cd "$root" || exit 2
logs="${GATE_LOG_DIR:-$dd/gate-logs}"; mkdir -p "$logs"
cap="${GATE_SUITE_CAP:-1500}"
suites="${GATE_SUITES:-ArmCapTests ArmBlendTests RaceArmsTests RaceFeetTests RaceWallTests WristbandFitTests WaveInterruptTests WearPrepTimeTests}"
[ -z "${GATE_SUITES:-}" ] && [ -f BobV1Tests/RacePullArmsTests.swift ] && suites="$suites RacePullArmsTests"
export TEST_RUNNER_WEARPREP_CEILING=1
fail=0; rows=()

wait_quiet() { # bounded: 50 x 30 s = 25 min
  local i l n
  for i in $(seq 1 50); do
    l=$(sysctl -n vm.loadavg | awk '{print $2}'); n=$(pgrep -x xcodebuild | wc -l | tr -d ' ')
    if awk "BEGIN{exit !($l < 8)}" && [ "$n" -le 1 ]; then return 0; fi
    echo "gate: waiting (load $l, xcodebuild $n)"; sleep 30
  done
  echo "GATE EXPIRED: machine never quiet for 25 min"; return 1
}

run_capped() { # run_capped <seconds> <logfile> cmd...  ; kills only its own child on cap
  local secs="$1" log="$2"; shift 2
  caffeinate -i "$@" >"$log" 2>&1 & local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$t" -ge "$secs" ]; then echo "gate: cap hit, stopping own pid $pid"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; fi
    sleep 5; t=$((t+5))
  done
  wait "$pid"
}

if [ -n "$devapp" ]; then
  if "$here/check-date-ops.sh" "$devapp"; then rows+=("check-date-ops|-|0|ok"); else rows+=("check-date-ops|-|1|FAIL"); fail=1; fi
fi

xb=(xcodebuild -project BobV1.xcodeproj -scheme BobV1 -configuration Release -destination "id=$udid" -derivedDataPath "$dd" ENABLE_TESTABILITY=YES)
if [ "${GATE_SKIP_BUILD:-0}" != 1 ]; then
  wait_quiet || exit 3
  echo "gate: build-for-testing ..."
  if ! run_capped 3000 "$logs/build.log" "${xb[@]}" build-for-testing; then
    tail -20 "$logs/build.log"; echo "GATE FAIL: build failed (log $logs/build.log)"; exit 1
  fi
fi

for s in $suites; do
  wait_quiet || { rows+=("$s|0|-|NOT RUN (gate expired)"); fail=1; continue; }
  echo "gate: $s ..."
  run_capped "$cap" "$logs/$s.log" "${xb[@]}" test-without-building -parallel-testing-enabled NO "-only-testing:BobV1Tests/$s"; rc=$?
  line=$(grep -E "Executed [0-9]+ tests?, with .*[0-9]+ failures?" "$logs/$s.log" | tail -1)
  run=$(echo "$line" | sed -E 's/.*Executed ([0-9]+) tests?.*/\1/'); f=$(echo "$line" | sed -E 's/.* ([0-9]+) failures?.*/\1/'); sk=$(echo "$line" | sed -nE 's/.* ([0-9]+) tests? skipped.*/\1/p')
  if [ -z "$line" ] || [ "$run" = 0 ]; then rows+=("$s|0|-|NOT RUN (rc $rc)"); fail=1
  elif [ "$f" != 0 ] || [ "$rc" != 0 ]; then rows+=("$s|$run|$f|FAIL"); fail=1
  else rows+=("$s|$run|$f|ok${sk:+ ($sk skipped)}"); fi
done

echo; printf '%-24s %10s %9s  %s\n' SUITE TESTS-RUN FAILURES RESULT
for r in "${rows[@]}"; do IFS='|' read -r a b c d <<<"$r"; printf '%-24s %10s %9s  %s\n' "$a" "$b" "$c" "$d"; done
if [ $fail = 0 ]; then echo "GATE PASS"; else echo "GATE FAIL (logs in $logs)"; fi
exit $fail
