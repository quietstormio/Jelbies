#!/usr/bin/env python3
"""Convert the Blender food exports (OBJ with linear vertex colours + JSON) into compact bundled binaries.

usage: convert_food_art.py <export_dir> <out_dir> [id ...]   (no ids = every known id the export has)

Output food_<id>.bin (little endian): u32 vertexCount, u32 indexCount, then vertexCount x 10 float32 (pos xyz, normal xyz, linear rgb, ao),
then indexCount x u16. OBJ format: `v x y z r g b` or `v x y z r g b ao w` (ao -> normal.w, default 1; w ignored), `vn`, `f a//a b//b c//c` (same index for position and normal).
GAIN tweaks colours after the fact (per food, linear multipliers) so the in-game lighting reads right.
"""
import json, struct, sys, os

IDS = "nuggets nuggets_1 nuggets_2 fries sushi sandwich minipizza taco donut popsicle onigiri cookie swirl pancakes sundae fizzmac cafetable_1 cafetable_2 cafetable_3 minipizza_whole cheeseburger ramen macncheese fruitcup pancakestack cakeslice cupcake dumplings drink_boba_shell drink_boba_deco drink_boba_ice drink_smoothie_shell drink_smoothie_deco drink_smoothie_float drink_lemonade_shell drink_lemonade_deco drink_lemonade_ice drink_cocoa_deco drink_cocoa_float".split()
GAIN = {}  # id -> (r, g, b) linear multiplier, filled in after looking at the in-game captures

def convert(src, dst):
    pos, col, nrm, ao, tris = [], [], [], [], []
    for line in open(src):
        t = line.split()
        if not t: continue
        if t[0] == "v": pos.append(tuple(map(float, t[1:4]))); col.append(tuple(map(float, t[4:7]))); ao.append(float(t[7]) if len(t) > 7 else 1.0)
        elif t[0] == "vn": nrm.append(tuple(map(float, t[1:4])))
        elif t[0] == "f":
            idx = [int(x.split("//")[0]) - 1 for x in t[1:]]
            for k in range(1, len(idx) - 1): tris += [idx[0], idx[k], idx[k + 1]]
    assert len(pos) == len(nrm) == len(col) and len(pos) < 65536, src
    return pos, nrm, col, ao, tris

def main():
    exp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for i in (sys.argv[3:] or IDS):
        if not os.path.exists(os.path.join(exp, i + ".obj")): continue          # convert only what the export has
        pos, nrm, col, ao, tris = convert(os.path.join(exp, i + ".obj"), None)
        g = GAIN.get(i, (1, 1, 1))
        data = struct.pack("<II", len(pos), len(tris))
        for p, n, c, a in zip(pos, nrm, col, ao):
            data += struct.pack("<10f", *p, *n, *(min(1.0, c[k] * g[k]) for k in range(3)), a)
        data += struct.pack("<%dH" % len(tris), *tris)
        open(os.path.join(out, "food_%s.bin" % i), "wb").write(data)
        meta = json.load(open(os.path.join(exp, i + ".json")))
        print(i, len(pos), "verts", len(tris) // 3, "tris", len(data), "bytes", "grip", meta.get("grip_point"))

main()
