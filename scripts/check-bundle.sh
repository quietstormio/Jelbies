#!/bin/bash
# Usage: check-bundle.sh <path to a built BobV1.app>. Exit 0 + one OK line if the bundle is complete, exit 1 + a FAIL list otherwise.
# Why (2026-11-15): an install went on with an app that had lost its sound files and most models (the reused build folder had
# product files removed by the system, Xcode still said BUILD SUCCEEDED). Before a phone build remove the product app first
# (rm -rf <derived data>/Build/Products/Release-iphoneos/BobV1.app) so every resource is copied again.
# Rule for "expected in the bundle": every tracked file under BobV1/ is copied FLAT (by file name) into the bundle root, except the
# compiled / folded-in kinds: *.swift, *.metal (-> default.metallib), *.h (headers), and anything inside *.xcassets (-> Assets.car).
# Checked against complete device and simulator bundles: nothing reported missing. Needs only bash, git, find, comm.
app="${1:?usage: check-bundle.sh path/to/BobV1.app}"
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
[ -d "$app" ] || { echo "FAIL: $app is not a directory"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$root" ls-files BobV1 | grep -vE '\.(swift|metal|h)$' | grep -v '\.xcassets/' | sed 's|.*/||' | LC_ALL=C sort -u >"$tmp/expected"
(cd "$app" && find . -maxdepth 1 -type f | sed 's|^\./||') | LC_ALL=C sort -u >"$tmp/have"
LC_ALL=C comm -23 "$tmp/expected" "$tmp/have" >"$tmp/missing"
problems=()
nmiss=$(wc -l <"$tmp/missing" | tr -d ' ')
if [ "$nmiss" != 0 ]; then
  problems+=("$nmiss expected resource file(s) missing from the bundle (first 20):")
  while IFS= read -r l; do problems+=("    $l"); done < <(head -20 "$tmp/missing")
  [ "$nmiss" -gt 20 ] && problems+=("    ... and $((nmiss - 20)) more")
fi
exe=BobV1   # the main executable is named after the target, whatever the .app folder is called
for f in "$exe" Assets.car default.metallib Info.plist PlugIns/JelbiesWidget.appex; do
  if [ -d "$app/$f" ]; then [ -n "$(ls -A "$app/$f" 2>/dev/null)" ] || problems+=("$f is an empty folder")
  elif [ ! -e "$app/$f" ]; then problems+=("$f is missing")
  elif [ ! -s "$app/$f" ]; then problems+=("$f is empty"); fi
done
if [ ${#problems[@]} -gt 0 ]; then
  echo "FAIL: $app is not a complete bundle:"; printf '  %s\n' "${problems[@]}"; exit 1
fi
n=$(wc -l <"$tmp/expected" | tr -d ' '); na=$(grep -c '\.m4a$' "$tmp/expected"); nb=$(grep -c '\.bin$' "$tmp/expected")
echo "OK: $app has all $n expected resource files ($na audio, $nb .bin) plus executable, Assets.car, default.metallib, Info.plist, widget"
