#!/bin/bash
# usage: run.sh <export dir>   builds all foliage, renders previews to <export dir>/prev
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
export DECOR_EXPORT="$1"
BL=/Applications/Blender.app/Contents/MacOS/Blender
$BL -b -P "$HERE/build_foliage.py" 2>&1 | grep -E "EXPORT|Error|Traceback|line " || true
$BL -b -P "$HERE/../make_decor_batch4/prev_render.py" -- "$1" "$1/prev" tree_a tree_b tree_c pine_a pine_b bush_a bush_b flowers 2>&1 | grep -E "PREV|Error" || true
