#!/bin/bash
# Usage: phone-install.sh <device udid> <derived data path>
# The ONE way to put a build on the phone: remove the product app, build Release, run check-date-ops and check-bundle, install.
# Every step is printed as "phone-install: <step> ..."; the first failure prints "PHONE INSTALL STOPPED: <reason>" and exits non-zero,
# so nothing after a failed step runs. There is no option that skips the two checks.
# Why (2026-11-15): a phone install went on with an app bundle that had lost its sound files, because the build, the checks and the
# install were separate hand-typed steps with time between them.
# Env: PHONE_INSTALL_DRY=1        print the commands for steps 2, 3 and 6 instead of running them (1, 4, 5 still run if an app exists)
#      PHONE_INSTALL_SKIP_BUILD=1 skip steps 2 and 3 and install the app that is there (checks 4 and 5 still decide)
#      PHONE_INSTALL_LAUNCH=1     add a last step that launches the app (no launch arguments, see below)
#      PHONE_INSTALL_JOBS=N       xcodebuild -jobs (default 8)
#      PHONE_INSTALL_LOG_DIR=dir  where build.log and installs.log go (default <derived data>/phone-install-logs)
udid="${1:?usage: phone-install.sh <device udid> <derived data path>}"
dd="${2:-}"
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"; cd "$root" || exit 2
dry="${PHONE_INSTALL_DRY:-0}"; skipbuild="${PHONE_INSTALL_SKIP_BUILD:-0}"

stop() { echo "PHONE INSTALL STOPPED: $*"; exit 1; }

# 1. clean tracked tree
echo "phone-install: checking the working tree ..."
[ -n "$dd" ] || stop "derived data path is empty"
dirty="$(git status --porcelain --untracked-files=no 2>&1)" || stop "git status failed: $dirty"
[ -z "$dirty" ] || { echo "$dirty"; stop "uncommitted changes to tracked files in $root"; }
branch="$(git rev-parse --abbrev-ref HEAD)"; sha="$(git rev-parse --short=8 HEAD)"
echo "phone-install: building branch $branch at $sha"

# derived data folder must be one we may delete in
case "$dd" in /) stop "derived data path is /";; esac
if [ -e "$dd" ] && [ ! -d "$dd/Build" ] && [ ! -e "$dd/info.plist" ]; then
  stop "$dd does not look like a derived data folder (no Build/ or info.plist)"
fi
app="$dd/Build/Products/Release-iphoneos/BobV1.app"
logdir="${PHONE_INSTALL_LOG_DIR:-$dd/phone-install-logs}"
build=(caffeinate -i nice xcodebuild -project BobV1.xcodeproj -scheme BobV1 -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$dd" -allowProvisioningUpdates -jobs "${PHONE_INSTALL_JOBS:-8}" build)
inst=(xcrun devicectl device install app --device "$udid" "$app")

if [ "$skipbuild" = 1 ]; then
  echo "phone-install: steps 2 and 3 skipped (PHONE_INSTALL_SKIP_BUILD=1), using the app that is there"
else
  # 2. remove the product app (only this exact path)
  echo "phone-install: removing the product app ..."
  if [ "$dry" = 1 ]; then echo "  WOULD RUN: rm -rf \"$app\""; else rm -rf "$app" || stop "could not remove $app"; fi
  # 3. build
  echo "phone-install: building (log $logdir/build.log) ..."
  if [ "$dry" = 1 ]; then echo "  WOULD RUN: ${build[*]} > $logdir/build.log"
  else
    mkdir -p "$logdir" || stop "cannot create $logdir"
    "${build[@]}" >"$logdir/build.log" 2>&1; rc=$?
    [ $rc = 0 ] || { tail -20 "$logdir/build.log"; stop "build failed (exit $rc, log $logdir/build.log)"; }
    grep -q '\*\* BUILD SUCCEEDED \*\*' "$logdir/build.log" || stop "no BUILD SUCCEEDED in $logdir/build.log"
  fi
fi

# 4 and 5. the checks (no way to skip them)
okline=""
if [ "$dry" = 1 ] && [ ! -d "$app" ]; then
  echo "phone-install: checks 4 and 5 skipped in the dry run: no app at $app"
else
  [ -d "$app" ] || stop "no app at $app"
  echo "phone-install: check-date-ops ..."
  "$here/check-date-ops.sh" "$app" || stop "check-date-ops failed for $app"
  echo "phone-install: check-bundle ..."
  okline="$("$here/check-bundle.sh" "$app")" || { echo "$okline"; stop "check-bundle failed for $app"; }
  echo "$okline"
fi

# 6. install
echo "phone-install: installing on $udid ..."
if [ "$dry" = 1 ]; then echo "  WOULD RUN: ${inst[*]}"
else "${inst[@]}"; rc=$?; [ $rc = 0 ] || stop "devicectl install failed (exit $rc)"; fi

# optional launch. NEVER add launch arguments here: a launch with dev arguments is a separate, deliberate act.
if [ "${PHONE_INSTALL_LAUNCH:-0}" = 1 ]; then
  echo "phone-install: launching ..."
  if [ "$dry" = 1 ]; then echo "  WOULD RUN: xcrun devicectl device process launch --device $udid --terminate-existing io.mgsllc.BobV1"
  else xcrun devicectl device process launch --device "$udid" --terminate-existing io.mgsllc.BobV1 || stop "launch failed"; fi
fi

# 7. final block
if [ "$dry" = 1 ]; then echo "PHONE INSTALL DRY RUN FINISHED (nothing was removed, built or installed)"; exit 0; fi
size="$(du -sh "$app" | awk '{print $1}')"
counts="$(echo "$okline" | sed -nE 's/.*\(([0-9]+) audio, ([0-9]+) \.bin\).*/\1 audio, \2 .bin/p')"
block="PHONE INSTALL DONE
  branch: $branch
  commit: $sha
  app size: $size
  bundle: $counts
  time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "$block"
mkdir -p "$logdir" && { echo "$block"; echo; } >>"$logdir/installs.log"
exit 0
