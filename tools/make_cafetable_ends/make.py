#!/usr/bin/env python3
"""The café's ENDS table (feeding-old-r1, 2026-11-18): the three-place table shortened to the home tray's ends layout (half width 0.55, was 1.0).

Same mesh, same vertex colours / AO as food_cafetable_3.bin (the Blender export), so the style and materials are identical: only the span between the end legs is cut.
Every vertex with |x| >= B is moved d = 0.45 toward the middle (legs, end handles and their rims keep their size), the zone A < |x| < B is compressed linearly, |x| <= A is unchanged.
Writes <out>/cafetable_ends.obj + .json in the Blender-export format `tools/convert_food_art.py` reads (v x y z r g b ao, vn, f a//a ...).

usage: make.py <food_cafetable_3.bin> <out_dir>      then:  convert_food_art.py <out_dir> BobV1/Dining/Resources cafetable_ends
"""
import struct, sys, os, json
A, B, D = 0.30, 0.55, 0.45

def warp(x):
    s, a = (1 if x >= 0 else -1), abs(x)
    if a <= A: return x
    if a >= B: return s * (a - D)
    t = (a - A) / (B - A)                      # A..B maps onto A..(B - D)
    return s * (A + t * ((B - D) - A))

src, out = sys.argv[1], sys.argv[2]
d = open(src, "rb").read()
nv, ni = struct.unpack("<II", d[:8])
V = [struct.unpack("<10f", d[8 + k * 40: 48 + k * 40]) for k in range(nv)]
I = struct.unpack("<%dH" % ni, d[8 + nv * 40:])
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "cafetable_ends.obj"), "w") as f:
    for v in V: f.write("v %.6f %.6f %.6f %.6f %.6f %.6f %.6f\n" % (warp(v[0]), v[1], v[2], v[6], v[7], v[8], v[9]))
    for v in V: f.write("vn %.6f %.6f %.6f\n" % v[3:6])
    for k in range(0, ni, 3): f.write("f %d//%d %d//%d %d//%d\n" % (I[k]+1, I[k]+1, I[k+1]+1, I[k+1]+1, I[k+2]+1, I[k+2]+1))
json.dump({"id": "cafetable_ends", "grip_point": None, "note": "cafetable_3 shortened to half width 0.55"}, open(os.path.join(out, "cafetable_ends.json"), "w"))
print("ok", nv, "verts")
