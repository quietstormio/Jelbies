#!/bin/zsh
# Pulls the on-device ring log (Application Support/jlog.txt, last ~2000 lines: Show flow, picks, Skip / Home, audio events) off a phone. No root needed.
# usage: scripts/jlog-pull.sh <device name or id> [bundle id] [out file]
DEV=${1:?device name or id}; BID=${2:-io.mgsllc.BobV1}; OUT=${3:-./jlog.txt}
xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer --domain-identifier "$BID" --source "Library/Application Support/jlog.txt" --destination "$OUT" && tail -40 "$OUT"
