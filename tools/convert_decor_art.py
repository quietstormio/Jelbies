#!/usr/bin/env python3
"""Convert the Blender decor exports (OBJ with `o <part>` groups + JSON) into bundled decor_<id>.bin files.

usage: convert_decor_art.py <export_dir> <out_dir>

decor_<id>.bin (little endian): u32 vertexCount, u32 indexCount, u32 partCount,
  partCount x { char name[16] (NUL padded), u32 firstIndex, u32 indexCount, u32 material (0 plain, 5 lamp), f32 pivot[3] },
  vertexCount x 11 float32 (pos xyz, normal xyz, linear rgb, ao, w), indexCount x u16.
Indices are global vertex indices; each part owns a contiguous index range. OBJ: `v x y z r g b ao w`, `vn`, `o name`, `f a//a b//b c//c`.
"""
import json, struct, sys, os

IDS = ("cushion ball rug plant nightlight toybox beanbag bouncymat "
       "loveseat petbed pouf rockingchair armchair swing diningset bookshelf wardrobe divider floorlamp slide monstera "
       "duck blocks spintop toycar yarnball drum soccerball minigoal").split()
# the pieces whose exported frame came out inside-out (see below); every other piece is trusted as exported (open surfaces such as the slide chute or the ropes
# have a legitimately negative signed volume)
FLIP_FIX = {"bouncymat"}

def convert(src, meta, fix=False):
    pos, col, nrm, ao, w, parts = [], [], [], [], [], []
    for line in open(src):
        t = line.split()
        if not t or t[0].startswith("#"): continue
        if t[0] == "o": parts.append([t[1], []])
        elif t[0] == "v":
            pos.append(tuple(map(float, t[1:4]))); col.append(tuple(map(float, t[4:7])))
            ao.append(float(t[7]) if len(t) > 7 else 1.0); w.append(float(t[8]) if len(t) > 8 else 0.0)
        elif t[0] == "vn": nrm.append(tuple(map(float, t[1:4])))
        elif t[0] == "f":
            idx = [int(x.split("//")[0]) - 1 for x in t[1:]]
            for k in range(1, len(idx) - 1): parts[-1][1] += [idx[0], idx[k], idx[k + 1]]
    assert len(pos) == len(nrm) == len(col) and len(pos) < 65536, src
    # the artist's bouncymat frame came out inside-out (normals and winding both point into the solid, so it culls away from above):
    # flip every closed connected component whose signed volume is negative
    flipped = 0
    for part in (parts if fix else []):
        ix = part[1]
        key = lambda i: (round(pos[i][0], 3), round(pos[i][1], 3), round(pos[i][2], 3))
        par = {}
        def find(x):
            while par.setdefault(x, x) != x: par[x] = par[par[x]]; x = par[x]
            return x
        for t in range(0, len(ix), 3):
            for a in ix[t + 1:t + 3]: par[find(key(ix[t]))] = find(key(a))
        vol = {}
        for t in range(0, len(ix), 3):
            a, b, c = [pos[i] for i in ix[t:t + 3]]
            v = (a[0] * (b[1] * c[2] - b[2] * c[1]) + a[1] * (b[2] * c[0] - b[0] * c[2]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6
            r = find(key(ix[t])); vol[r] = vol.get(r, 0) + v
        flip = set()
        for t in range(0, len(ix), 3):
            if vol[find(key(ix[t]))] < -1e-3:
                ix[t + 1], ix[t + 2] = ix[t + 2], ix[t + 1]
                flip.update(ix[t:t + 3])
        for i in flip: nrm[i] = tuple(-x for x in nrm[i])
        flipped += len(flip)
    info = {s["name"]: s for s in meta["sub_meshes"]}
    tris = []
    head = b""
    for name, ix in parts:
        s = info[name]
        assert len(name.encode()) <= 15, name
        mat = 5 if s["material"] == "lamp" else 0
        head += struct.pack("<16sIII3f", name.encode(), len(tris), len(ix), mat, *s["pivot"])
        tris += ix
    data = struct.pack("<III", len(pos), len(tris), len(parts)) + head
    for p, n, c, a, ww in zip(pos, nrm, col, ao, w):
        data += struct.pack("<11f", *p, *n, *c, a, ww)
    data += struct.pack("<%dH" % len(tris), *tris)
    if flipped: print("  flipped", flipped, "inside-out vertices")
    return data, len(pos), len(tris) // 3, [p[0] for p in parts]

def main():
    exp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for i in IDS:
        meta = json.load(open(os.path.join(exp, i + ".json")))
        data, nv, nt, names = convert(os.path.join(exp, i + ".obj"), meta, i in FLIP_FIX)
        open(os.path.join(out, "decor_%s.bin" % i), "wb").write(data)
        print(i, nv, "verts", nt, "tris", len(data), "bytes", names)

main()
