#!/usr/bin/env python3
"""usage: convert.py <export_dir> <out_dir>  -> park_<id>.bin (same format as decor_<id>.bin; see tools/convert_decor_art.py)."""
import sys, os, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from convert_decor_art import convert
IDS = "tree_a tree_b tree_c pine_a pine_b tree_a_far tree_b_far tree_c_far pine_a_far pine_b_far bush_a bush_b hedge hedge_low flowers".split()
exp, out = sys.argv[1], sys.argv[2]
for i in IDS:
    meta = json.load(open(os.path.join(exp, i + ".json")))
    data, nv, nt, names = convert(os.path.join(exp, i + ".obj"), meta)
    open(os.path.join(out, "park_%s.bin" % i), "wb").write(data)
    print(i, nv, "verts", nt, "tris", names)
