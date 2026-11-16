#!/usr/bin/env python3
"""Converts the camp prop exports with the shared converter's convert() (imported by path; the shared file is not modified).
usage: convert_fence.py <export_dir> <out_dir>   -> <out_dir>/park_camp_{post,rail,gate_post,tent}.bin (decor .bin format, see tools/convert_decor_art.py)"""
import sys, os, json, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cda", os.path.join(HERE, "..", "convert_decor_art.py")); cda = importlib.util.module_from_spec(spec); spec.loader.exec_module(cda)
exp, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for n in ("post", "rail", "gate_post", "tent"):
    meta = json.load(open(os.path.join(exp, n + ".json")))
    data, nv, nt, names = cda.convert(os.path.join(exp, n + ".obj"), meta)
    open(os.path.join(out, "park_camp_%s.bin" % n), "wb").write(data)
    print("park_camp_" + n, nv, "verts", nt, "tris", len(data), "bytes", names)
