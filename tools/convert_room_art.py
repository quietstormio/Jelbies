#!/usr/bin/env python3
"""Convert the Blender room exports (export/rooms/room_<id>.obj + .json) into BobV1/Room/Resources/room_<id>.bin (same format as the decor bins).

usage: convert_room_art.py <export_dir> <out_dir>
Room-world game coordinates: floor y = 0, back wall z = -5. Each room must stay under 65536 vertices (u16 indices).
"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_decor_art import convert

IDS = ["loft", "cabin"]

def main():
    exp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for i in IDS:
        meta = json.load(open(os.path.join(exp, "room_%s.json" % i)))
        data, nv, nt, names = convert(os.path.join(exp, "room_%s.obj" % i), meta)
        assert nv < 65536 and nt <= 15000, (i, nv, nt)
        open(os.path.join(out, "room_%s.bin" % i), "wb").write(data)
        print("room_%s.bin" % i, nv, "vertices", nt, "triangles", names)

if __name__ == "__main__":
    main()
