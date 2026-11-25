"""Rebuild the slide's stair blocks with an open stair (slide-steps-r1). Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python build_slide_steps.py -- <old decor_slide.bin> <out dir> [z2f db]
Writes <out dir>/slide.obj + slide.json (tools/convert_decor_art.py format) and slide_steps.blend.

Why: the jelly's belly (about 1.17 across) at the climb spots sank 22-35 cm into the stair blocks (the probe's chord measure counts every sample of the centre -> skin
line inside solid). The blocks are rebuilt (mesh units = game units / 1.25):
  - two deck cheeks (x .62..0.74) keep the old deck front under the posts / rails;
  - step 1 (top .22) is deeper (runs forward under step 2) so the stand-1 feet have a tread;
  - step 2 (top .44) starts further forward (z2f) and the deck front between the cheeks is recessed (db): the belly's lower front at the stand-1 / stand-2 spots is in empty space.
Everything else in the old mesh (chute, posts, rails, deck back) is copied untouched. Colours / ao follow the old per-class gradients, so ParkSlideSkin's classes are kept.
"""
import sys, struct, json, os, math
import bpy, bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OLD, OUT = argv[0], argv[1]
Z2F = float(argv[2]) if len(argv) > 2 else -0.80          # step 2 front (mesh units)
DB = float(argv[3]) if len(argv) > 3 else -0.50           # deck front face between the cheeks
os.makedirs(OUT, exist_ok=True)

d = open(OLD, "rb").read()
nv, ni, npart = struct.unpack_from("<III", d, 0); o = 12 + 40 * npart
pivot = struct.unpack_from("<3f", d, 12 + 16 + 12)
V = [struct.unpack_from("<11f", d, o + 44 * i) for i in range(nv)]; o += 44 * nv
I = struct.unpack_from("<%dH" % ni, d, o)

# welded components of the old mesh
key = lambda i: tuple(round(x, 3) for x in V[i][:3])
par = {}
def find(x):
    while par.setdefault(x, x) != x: par[x] = par[par[x]]; x = par[x]
    return x
for t in range(0, ni, 3):
    for a in I[t + 1:t + 3]: par[find(key(I[t]))] = find(key(a))
comp = {}
for t in range(0, ni, 3): comp.setdefault(find(key(I[t])), []).append(t)
drop = set()
for r, ts in comp.items():
    vs = [V[I[t + k]] for t in ts for k in range(3)]
    zmin = min(v[2] for v in vs); zmax = max(v[2] for v in vs); ymax = max(v[1] for v in vs)
    if zmin > -1.41 and zmax < 0.11 and ymax < 0.67 and len(ts) in (216, 108): drop.add(r)
assert len(drop) == 2, drop
keep_tris = [t for r, ts in comp.items() if r not in drop for t in ts]

# per-class colour / ao ramps by absolute height (mesh units), taken from the old blocks
RAMPS = {
    "step1": [(0, (.81, .25, .37), .55), (.06, (.81, .25, .37), .6), (.16, (.81, .25, .37), .8), (.195, (.83, .3, .4), .87), (.202, (.84, .33, .43), .89), (.22, (.85, .39, .47), .92)],
    "step2": [(0, (.87, .23, .16), .55), (.06, (.87, .23, .16), .6), (.38, (.87, .23, .16), 1.0), (.415, (.88, .28, .2), 1.0), (.422, (.88, .31, .23), 1.0), (.44, (.89, .37, .28), 1.0)],
    "deck": [(0, (.74, .46, .08), .55), (.08, (.76, .48, .08), .57), (.58, (.95, .6, .1), 1.0), (.626, (.95, .62, .12), 1.0), (.637, (.95, .63, .14), 1.0), (.66, (.94, .65, .17), 1.0)],
}
def ramp(cls, y):
    r = RAMPS[cls]
    if y <= r[0][0]: return r[0][1], r[0][2]
    for (y0, c0, a0), (y1, c1, a1) in zip(r, r[1:]):
        if y <= y1:
            f = (y - y0) / (y1 - y0)
            return tuple(c0[k] + (c1[k] - c0[k]) * f for k in range(3)), a0 + (a1 - a0) * f
    return r[-1][1], r[-1][2]

BEVEL = 0.06
def box(lo, hi, cls):
    bev = min(BEVEL, 0.4 * (hi[0] - lo[0]), 0.4 * (hi[2] - lo[2]))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((hi[0] if v.co.x > 0 else lo[0]), (hi[1] if v.co.y > 0 else lo[1]), (hi[2] if v.co.z > 0 else lo[2])))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=2, profile=0.5, affect='EDGES')
    bm.normal_update()
    verts = []
    for v in bm.verts:
        c, a = ramp(cls, v.co.y)
        verts.append((tuple(v.co), tuple(v.normal), c, a))
    idx = {v.index: k for k, v in enumerate(bm.verts)}
    tris = []
    for f in bm.faces:
        vs = [idx[v.index] for v in f.verts]
        for k in range(1, len(vs) - 1): tris.append((vs[0], vs[k], vs[k + 1]))
    bm.free()
    return verts, tris

X = 0.74; XD = 0.62; XT = 0.74            # outer half width, deck cheeks' inner edge (under the posts), treads' half width (full width)
H1, H2, H3 = 0.21, 0.44, 0.66          # step 1 top 1.2 cm under the stand height: the belly at the first stand just touches the tread, and the probe reads any touch as >= 5 cm
pieces = [
    # deck cheeks under the rails / posts (the old deck front stays there), both sides
    *[(( XD if s > 0 else -X, 0, -0.92), (X if s > 0 else -XD, H3, DB), "deck") for s in (1, -1)],
    # step 1: deeper, runs forward under step 2
    ((-XT, 0, -1.40), (XT, H1, Z2F), "step1"),
    # step 2: set back
    ((-XT, 0, Z2F), (XT, H2, DB), "step2"),
    # deck main block (back part, unchanged back plane z .10)
    ((-X, 0, DB), (X, H3, 0.10), "deck"),
]
# the old deck's back end is at z .10 (the chute starts at .07): keep it
import random
JIT = int(os.environ.get("SLIDE_JITTER", "1"))
rnd = random.Random(JIT)
new_v, new_t = [], []
for lo, hi, cls in pieces:
    # (a 0.2-0.4 mm nudge per piece: the probe's voxeliser counts crossings per 2 cm column centre in float32, and a centre that sits exactly on a face diagonal
    # is counted twice or never -> a phantom 2 cm pole of "solid" up to the top. tools/make_slide_steps/check_columns.py proves the result has none.)
    j = [rnd.uniform(-0.0004, 0.0004) for _ in range(3)]
    lo = (lo[0] + j[0], lo[1], lo[2] + j[2]); hi = (hi[0] + j[0], hi[1], hi[2] - j[2] * 0.7)
    vs, ts = box(lo, hi, cls)
    base = len(new_v); new_v += vs; new_t += [(a + base, b + base, c + base) for a, b, c in ts]

lines = ["# slide-steps-r1: open stair"]
verts_out = [(V[i][:3], V[i][3:6], V[i][6:9], V[i][9], V[i][10]) for i in range(nv)]
remap = {}
kept_v = sorted({I[t + k] for t in keep_tris for k in range(3)})
for n, i in enumerate(kept_v): remap[i] = n
out_v = [verts_out[i] for i in kept_v]
off = len(out_v)
for p, n, c, a in new_v: out_v.append((p, n, c, a, 0.0))
tri_out = [tuple(remap[I[t + k]] for k in range(3)) for t in keep_tris] + [(a + off, b + off, c + off) for a, b, c in new_t]
lines.append("o slide")
for p, n, c, a, w in out_v: lines.append("v %.6f %.6f %.6f %.5f %.5f %.5f %.4f %.4f" % (*p, *c, a, w))
for p, n, c, a, w in out_v: lines.append("vn %.5f %.5f %.5f" % n)
for a, b, c in tri_out: lines.append("f %d//%d %d//%d %d//%d" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))
open(os.path.join(OUT, "slide.obj"), "w").write("\n".join(lines) + "\n")
json.dump({"sub_meshes": [{"name": "slide", "material": "plain", "pivot": list(pivot)}]}, open(os.path.join(OUT, "slide.json"), "w"))
print("kept verts", len(kept_v), "new verts", len(new_v), "total", len(out_v), "tris", len(tri_out))

# a .blend of the result for reference / renders
me = bpy.data.meshes.new("slide"); me.from_pydata([p for p, *_ in out_v], [], tri_out)
ob = bpy.data.objects.new("slide", me); bpy.context.collection.objects.link(ob)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "slide_steps.blend"))
