#!/bin/zsh
cd "$(dirname "$0")"
/Applications/Blender.app/Contents/MacOS/Blender -b -P build_all5.py -- "$@" 2>&1 | grep -E "EXPORT|Traceback|Error|line [0-9]+," | awk '/EXPORT/{printf "%-20s tris %5d verts %5d %s\n",$2,$3,$4,(($3>1300||$4>1000)?"OVER":"")} !/EXPORT/{print}'
