"""The Park seesaw as a Blender-headless model (game coordinates: x along the plank, y up, +z toward the camera; units as ParkToys.swift, the game draws it 1.4x).

  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_park_seesaw/build_seesaw.py -- A      (or B)
  python3 -I tools/make_park_seesaw/convert_seesaw.py tools/make_park_seesaw/export_A BobV1/Room/Resources   (writes decor_seesaw.bin)

Parts (exact names, contract v2): base, plank (pivot 0,.27,0), bumperL (pivot -.96,0,0), bumperR (pivot .96,0,0), seatL (pivot -.62,.3775,0), seatR (pivot .62,.3775,0). Vertices are absolute (the pivot is only the turning point).
One final colour set, taken from the park's slide (chute, step timber, timber, deep-green posts) plus one cream; render with tools/make_park_seesaw/render_seesaw.py.
Geometry is built as lofted rings (rounded-rectangle outlines with bevel profiles) and lathes; the AO is baked with BVH ray casts at rest. Exports OBJ + JSON in the format
tools/convert_decor_art.py reads (the shared tool files are not modified).
"""
import sys, os, math, json
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANT = (sys.argv[sys.argv.index("--") + 1:] or ["A"])[0] if "--" in sys.argv else "A"
OUT = os.environ.get("SEESAW_EXPORT", os.path.join(HERE, "export_" + VARIANT))

def s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def lin(c): return tuple(s2l(x) for x in c)
def mul(c, k): return tuple(min(1.0, x * k) for x in c)

# ---- palette (sRGB): the slide's muted terracotta chute (0.72, 0.41, 0.28), calm honey wood, cream ----
TERRA = (0.72, 0.41, 0.28)        # slide chute (cushions)
WOOD = (0.64, 0.46, 0.27)         # slide step timber (beam)
CREAM = (0.88, 0.84, 0.74)        # handles AND axle caps
FULC = (0.52, 0.35, 0.20)         # slide timber (block, cheeks)
FCAPS = CREAM
BUMP = (0.125, 0.3375, 0.225)     # slide posts' deep green (0.10, 0.27, 0.18) lightened 25% so the domes do not read as rocks

# ---------------------------------------------------------------- mesh kit
class Part:
    def __init__(self): self.P = []; self.N = []; self.F = []; self.C = []
    def add_grid(self, rings, caps=(True, True), color=(1, 1, 1), smooth_caps=False):
        """rings: list of closed rings of 3D points (a ring whose points coincide is a pole). Faces are oriented outward; vertex normals are smooth."""
        ids = []
        for ring in rings:
            pts = [np.array(p, float) for p in ring]; row = []
            if max(np.linalg.norm(p - pts[0]) for p in pts) < 1e-7:
                self.P.append(pts[0]); row = [len(self.P) - 1] * len(pts)
            else:
                for p in pts: self.P.append(p); row.append(len(self.P) - 1)
            ids.append(row)
        faces = []
        for k in range(len(ids) - 1):
            n = len(ids[k])
            for i in range(n):
                j = (i + 1) % n
                q = [ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]]
                u = []
                for v in q:
                    if v not in u: u.append(v)
                if len(u) == 4: faces += [(q[0], q[1], q[2]), (q[0], q[2], q[3])]
                elif len(u) == 3: faces.append(tuple(u))
        used = sorted({i for r in ids for i in r})
        cen = np.mean([self.P[i] for i in used], axis=0)
        def fn(f): return np.cross(self.P[f[1]] - self.P[f[0]], self.P[f[2]] - self.P[f[0]])
        s = sum(np.dot(fn(f), self.P[f[0]] - cen) for f in faces)
        if s < 0: faces = [(a, c, b) for a, b, c in faces]
        nrm = {}
        for f in faces:
            n_ = fn(f)
            for v in f: nrm[v] = nrm.get(v, 0) + n_
        while len(self.N) < len(self.P): self.N.append(np.array([0, 1.0, 0]))
        for v, n_ in nrm.items():
            L = np.linalg.norm(n_); self.N[v] = n_ / L if L > 0 else np.array([0, 1.0, 0])
        self.F += faces
        while len(self.C) < len(self.P): self.C.append(color)
        # flat caps (own vertices, exact axis normal): the flat top of a cushion or beam stays flat
        for first in (True, False):
            if not caps[0 if first else 1]: continue
            ring = ids[0] if first else ids[-1]; nxt = ids[1] if first else ids[-2]
            c0 = np.mean([self.P[i] for i in ring], axis=0); c1 = np.mean([self.P[i] for i in nxt], axis=0)
            nn = c0 - c1; nn = nn / np.linalg.norm(nn)
            self.P.append(c0); self.N.append(nn); self.C.append(color); cid = len(self.P) - 1
            dup = []
            for i in ring: self.P.append(self.P[i].copy()); self.N.append(((self.N[i] * 0.35 + nn * 0.65) / np.linalg.norm(self.N[i] * 0.35 + nn * 0.65)) if smooth_caps else nn); self.C.append(color); dup.append(len(self.P) - 1)
            n = len(dup)
            for i in range(n):
                a, b = dup[i], dup[(i + 1) % n]
                if np.linalg.norm(self.P[a] - self.P[b]) < 1e-9: continue
                t = (cid, a, b)
                g = np.cross(self.P[t[1]] - self.P[t[0]], self.P[t[2]] - self.P[t[0]])
                if np.dot(g, nn) < 0: t = (t[0], t[2], t[1])
                self.F.append(t)

def rrect(a, b, r, k):
    """Rounded-rectangle outline (half sizes a, b, corner radius r, k segments per corner), ccw, consecutive duplicates removed."""
    r = max(min(r, a, b), 1e-4); pts = []
    for q, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        cx, cy = sx * (a - r), sy * (b - r)
        for i in range(k + 1):
            t = math.radians(90 * q + 90 * i / k)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    out = []
    for p in pts:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-6: out.append(p)
    if math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < 1e-6: out.pop()
    return out

def dshape(a, bot, top_c, d, segs):
    """A 'D': half circle (radius a-d, centre height top_c) on top, flat bottom at height bot; inset by d."""
    r = a - d; pts = [(r * math.cos(math.pi * i / segs), top_c + r * math.sin(math.pi * i / segs)) for i in range(segs + 1)]
    return pts + [(-r, bot + d), (r, bot + d)]

def loft(part, a, b, r, k, prof, mapf, color, caps=(True, True), outline=None, smooth_caps=False):
    """prof: [(inset, h)...]; every ring is the rounded rectangle inset by `inset` (or outline(inset)); mapf(u, v, h) -> xyz."""
    ol = outline or (lambda d: rrect(a - d, b - d, r - d, k))
    rings = [[mapf(u, v, h) for (u, v) in ol(d)] for d, h in prof]
    part.add_grid(rings, caps, color, smooth_caps)

def lathe(part, prof, sides, origin, axis, color, caps=(False, False)):
    """prof: [(radius, t)...] along axis 'x'|'y'|'z' through origin."""
    ax = {"x": (np.array([1., 0, 0]), np.array([0, 1., 0]), np.array([0, 0, 1.])), "y": (np.array([0, 1., 0]), np.array([0, 0, 1.]), np.array([1., 0, 0])),
          "z": (np.array([0, 0, 1.]), np.array([1., 0, 0]), np.array([0, 1., 0]))}[axis]
    o = np.array(origin, float); rings = []
    for r, t in prof:
        rings.append([o + ax[0] * t + (ax[1] * math.cos(2 * math.pi * i / sides) + ax[2] * math.sin(2 * math.pi * i / sides)) * r for i in range(sides)])
    part.add_grid(rings, caps, color)

# ---------------------------------------------------------------- the model
def build():
    base, plank, bl, br = Part(), Part(), Part(), Part()
    seats = {-1: Part(), 1: Part()}
    # --- plank: beam (stadium, top 0.345, underside 0.255, bevelled all round); the plank pivots at (0, 0.27, 0)
    beam = [(0.030, 0.255), (0.009, 0.2625), (0.0, 0.282), (0.0, 0.318), (0.009, 0.3375), (0.030, 0.345)]
    loft(plank, 1.05, 0.17, 0.17, 5, beam, lambda u, v, h: (u, h, v), WOOD, smooth_caps=True)
    # --- seats: each its own part (pivot = hinge point (+-0.62, 0.3775, 0)); puffy rounded pad with a closed underside, flat top 0.475 over |x-0.62|<=0.28, |z|<=0.14
    # plus a cream barrel hinge along z (radius 0.035: sunk 0.0025 into the beam top 0.345 and the pad underside 0.410)
    cush = [(0.050, 0.410), (0.0, 0.430), (0.0, 0.452), (0.012, 0.467), (0.055, 0.475)]
    HY = 0.3775; RB = 0.035; ZH = 0.150; ZC = 0.115
    for sx in (-1, 1):
        loft(seats[sx], 0.35, 0.20, 0.085, 5, cush, lambda u, v, h, sx=sx: (sx * (0.62 + u), h, v), TERRA, smooth_caps=True)
        e45 = RB * math.sqrt(0.5)   # end caps: a 45 degree ring, then the pole (a rounded end)
        bprof = [(0.0, -ZH), (e45, -ZC - e45), (RB, -ZC), (RB, ZC), (e45, ZC + e45), (0.0, ZH)]
        lathe(seats[sx], bprof, 16, (sx * 0.62, HY, 0), "z", CREAM)
    # --- T handles at |x| = 0.20: centre post + crossbar along z (top 0.6347), round caps; post starts at the lowered beam (flare bottom 0.332)
    for sx in (-1, 1):
        x = sx * 0.20
        lathe(plank, [(0.031, 0.332), (0.0245, 0.358), (0.024, 0.600)], 8, (x, 0, 0), "y", CREAM)
        zb = 0.110; rb = 0.026; yb = 0.636 - rb
        s50, c50 = math.sin(math.radians(50)), math.cos(math.radians(50))
        prof = [(0.0, -zb - rb), (rb * s50, -zb - rb * c50), (rb, -zb), (rb, zb), (rb * s50, zb + rb * c50), (0.0, zb + rb)]
        lathe(plank, prof, 10, (x, yb, 0), "z", CREAM)
    # --- base: low rounded block (0.15 high), two cheeks with rounded tops (top 0.37), axle ends with round caps on the pivot (y 0.27)
    blk = [(0.035, 0.0), (0.010, 0.014), (0.0, 0.045), (0.0, 0.095), (0.050, 0.150)]
    ax_ = lambda h: 0.24 - (0.24 - 0.173) * (h / 0.15); bz_ = lambda h: 0.27 - (0.27 - 0.255) * (h / 0.15)
    rings = [[(u, h, v) for (u, v) in rrect(ax_(h) - d, bz_(h) - d, 0.09 - d, 3)] for d, h in blk]
    base.add_grid(rings, (False, True), FULC, True)
    cheek = [(0.012, 0.185), (0.0, 0.197), (0.0, 0.218), (0.012, 0.230)]
    cap = [(0.050, 0.226), (0.052, 0.240), (0.040, 0.262), (0.0, 0.272)]
    for sz in (-1, 1):
        loft(base, 0, 0, 0, 0, cheek, lambda u, v, h, sz=sz: (u, v, sz * h), FULC, outline=lambda d: dshape(0.11, 0.11, 0.26, d, 10), smooth_caps=True)
        lathe(base, [(r, sz * t) for r, t in cap], 14, (0, 0.27, 0), "z", FCAPS)
    # --- rubber bumpers: dome 0.10 radius, 0.11 high, pivot at the floor centre
    dome = [(0.100, 0.0), (0.0975, 0.035), (0.078, 0.080), (0.040, 0.104), (0.0, 0.110)]
    lathe(bl, dome, 12, (-0.96, 0, 0), "y", BUMP); lathe(br, dome, 12, (0.96, 0, 0), "y", BUMP)
    return [("base", (0, 0, 0), base), ("plank", (0, 0.27, 0), plank), ("bumperL", (-0.96, 0, 0), bl), ("bumperR", (0.96, 0, 0), br),
            ("seatL", (-0.62, HY, 0), seats[-1]), ("seatR", (0.62, HY, 0), seats[1])]

def bake_ao(parts):
    """Per-vertex AO by cosine-weighted ray casts against the whole piece at rest plus the ground; clamped 0.6..1."""
    V = []; F = []
    for _, _, p in parts:
        o = len(V); V += [tuple(q) for q in p.P]; F += [(a + o, b + o, c + o) for a, b, c in p.F]
    g = 6.0; o = len(V); V += [(-g, 0, -g), (g, 0, -g), (g, 0, g), (-g, 0, g)]; F += [(o, o + 2, o + 1), (o, o + 3, o + 2)]
    tree = BVHTree.FromPolygons(V, F)
    rng = np.random.default_rng(7); K = 40; out = {}
    for name, _, p in parts:
        ao = []
        for q, n in zip(p.P, p.N):
            n = Vector(n); t = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized(); bt = n.cross(t)
            occ = 0.0
            for _ in range(K):
                u1, u2 = rng.random(), rng.random(); r_ = math.sqrt(u1); ph = 2 * math.pi * u2
                d = (t * (r_ * math.cos(ph)) + bt * (r_ * math.sin(ph)) + n * math.sqrt(max(0.0, 1 - u1))).normalized()
                hit = tree.ray_cast(Vector(q) + n * 0.003, d, 0.22)
                if hit[0] is not None: occ += 1.0 - hit[3] / 0.22 * 0.6
            ao.append(max(0.6, min(1.0, 1.0 - 0.75 * occ / K)))
        out[name] = ao
    return out

def export(parts, ao):
    os.makedirs(OUT, exist_ok=True)
    allP = []; lines = []; vn = []; groups = []; off = 0
    for name, piv, p in parts:
        for q, n, c, a in zip(p.P, p.N, p.C, ao[name]):
            lines.append("v %.5f %.5f %.5f %.4f %.4f %.4f %.3f %.3f\n" % (*q, *lin(c), a, 0.0)); vn.append("vn %.4f %.4f %.4f\n" % tuple(n)); allP.append(q)
        groups.append((name, piv, [(a + off, b + off, c + off) for a, b, c in p.F])); off += len(p.P)
    with open(os.path.join(OUT, "seesaw.obj"), "w") as fh:
        fh.write("# seesaw variant %s: game coordinates. v x y z r g b ao w (rgb LINEAR)\n" % VARIANT)
        fh.writelines(lines); fh.writelines(vn)
        for name, piv, faces in groups:
            fh.write("o %s\n" % name)
            for a, b, c in faces: fh.write("f %d//%d %d//%d %d//%d\n" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))
    P = np.array(allP)
    info = dict(id="seesaw", tris=sum(len(g[2]) for g in groups), verts=len(P), variant=VARIANT,
                sub_meshes=[dict(name=n, pivot=list(map(float, piv)), material="plain", tris=len(f)) for n, piv, f in groups],
                bounds_min=[round(float(x), 4) for x in P.min(0)], bounds_max=[round(float(x), 4) for x in P.max(0)], anchor_rest=[0, 0, 0])
    json.dump(info, open(os.path.join(OUT, "seesaw.json"), "w"), indent=1)
    return info

parts = build()
info = export(parts, bake_ao(parts))
print("EXPORT seesaw", VARIANT, info["tris"], "tris", info["verts"], "verts", [(s["name"], s["tris"]) for s in info["sub_meshes"]], info["bounds_min"], info["bounds_max"])
