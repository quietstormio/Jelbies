#!/usr/bin/env python3
"""Convert the wall frame exports (tools/make_wall_frames) into bundled wallframe_<id>_<shape>.bin files (same format as decor_<id>.bin, see convert_decor_art.py).

usage: convert_wall_frames.py <export_dir> <out_dir>
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_decor_art import convert

def main():
    exp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for fid in ("wood", "white", "pastel", "gold"):
        for shape in ("portrait", "square", "landscape"):
            i = f"frame_{fid}_{shape}"
            if not os.path.exists(os.path.join(exp, i + ".json")): print("skip", i); continue
            meta = json.load(open(os.path.join(exp, i + ".json")))
            data, nv, nt, names = convert(os.path.join(exp, i + ".obj"), meta)
            open(os.path.join(out, "wall%s.bin" % i), "wb").write(data)
            print(i, nv, "verts", nt, "tris", len(data), "bytes", names)

if __name__ == "__main__":
    main()
