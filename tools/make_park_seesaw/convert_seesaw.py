#!/usr/bin/env python3
"""Converts the seesaw export with the shared converter's own convert() (imported by path, the shared file is not modified).
usage: convert_seesaw.py <export_dir> <out_dir>   -> <out_dir>/decor_seesaw.bin"""
import sys, os, json, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cda", os.path.join(HERE, "..", "convert_decor_art.py")); cda = importlib.util.module_from_spec(spec); spec.loader.exec_module(cda)
exp, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
meta = json.load(open(os.path.join(exp, "seesaw.json")))
data, nv, nt, names = cda.convert(os.path.join(exp, "seesaw.obj"), meta)
open(os.path.join(out, "decor_seesaw.bin"), "wb").write(data)
print("seesaw", nv, "verts", nt, "tris", len(data), "bytes", names)
