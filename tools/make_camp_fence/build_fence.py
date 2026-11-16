"""Jelmiko Camp yard props as Blender-headless models: fence post, one rail bay, gate post, tent.
Mesh kit (Part / rrect / loft / lathe / bake_ao) copied from tools/make_park_seesaw/build_seesaw.py. Game coordinates: y up, +z toward the camera, units = game units
(the seesaw's units, drawn at scale 1 here), origin on the ground at the centre of the footprint. Rail runs along x; the tent's door faces +z.

  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_camp_fence/build_fence.py
  python3 -I tools/make_camp_fence/convert_fence.py tools/make_camp_fence/export BobV1/Room/Resources     (writes park_camp_{post,rail,gate_post,tent}.bin)
Exports OBJ + JSON (format of tools/convert_decor_art.py) per prop into tools/make_camp_fence/export (or $CAMP_EXPORT).
"""
import sys, os, math, json
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("CAMP_EXPORT", os.path.join(HERE, "export"))

def s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def lin(c): return tuple(s2l(x) for x in c)

# ---- palette (sRGB): warm honey wood like the boards, paler cream caps, the tent in the slide's terracotta-orange with cream stripes ----
WOOD = (0.80, 0.60, 0.36)         # posts
RAIL = (0.84, 0.64, 0.39)         # rails: a touch lighter
CREAM = (0.93, 0.88, 0.76)        # post caps, gate knob, tent stripes
ORANGE = (0.86, 0.47, 0.28)       # tent
DARK = (0.24, 0.15, 0.12)         # tent opening
PINK = (0.96, 0.58, 0.68)         # pennant
POLE = (0.72, 0.53, 0.32)

# ---- sizes (game units) ----
SPACING = 1.40                    # post-to-post (plan 3.3)
POST_R, POST_H = 0.085, 0.50      # body radius and height of the wood; the cap dome takes it to 0.61
GATE_R, GATE_H = 0.10, 0.80       # gate post wood; knob top at 0.93
RAIL_LEN = SPACING - 2 * POST_R + 0.02   # 1.25: face to face of two posts plus 1 cm sunk into each
RAIL_Y = (0.17, 0.35)             # centre heights of the two rails
RAIL_H, RAIL_D = 0.075, 0.055     # rail height and depth
TENT_W, TENT_D, TENT_H = 1.6, 1.15, 1.1

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


# ---------------------------------------------------------------- the models
def sphere_prof(c, r, n=6):
    return [(r * math.cos(math.radians(a)), c + r * math.sin(math.radians(a))) for a in np.linspace(-90, 90, 2 * n + 1)]

def build_post():
    p = Part()
    lathe(p, [(0.0, 0.0), (0.068, 0.0), (0.082, 0.012), (POST_R, 0.04), (POST_R, 0.47), (0.078, 0.51), (0.0, 0.52)], 12, (0, 0, 0), "y", WOOD)
    cap = [(0.0885, 0.494), (0.099, 0.510), (0.100, 0.535), (0.088, 0.572), (0.056, 0.597), (0.0, 0.608)]
    lathe(p, cap, 12, (0, 0, 0), "y", CREAM)
    return p

def build_gate_post():
    p = Part()
    lathe(p, [(0.0, 0.0), (0.082, 0.0), (0.097, 0.014), (GATE_R, 0.045), (GATE_R, 0.74), (0.088, 0.785), (0.0, 0.80)], 12, (0, 0, 0), "y", WOOD)
    lathe(p, sphere_prof(0.84, 0.08), 12, (0, 0, 0), "y", CREAM)
    return p

def build_rail():
    p = Part(); L = RAIL_LEN / 2
    prof = [(0.014, -L), (0.0, -L + 0.014), (0.0, L - 0.014), (0.014, L)]
    for y0 in RAIL_Y:
        loft(p, RAIL_D / 2, RAIL_H / 2, RAIL_D / 2, 3, prof, lambda u, v, h, y0=y0: (h, y0 + v, u), RAIL, smooth_caps=True)
    return p

def fillet_poly(verts, radii, k):
    """Closed ccw polygon with rounded corners (radius per vertex, k segments each)."""
    n = len(verts); out = []
    for i in range(n):
        P = np.array(verts[i], float); A = np.array(verts[i - 1], float) - P; B = np.array(verts[(i + 1) % n], float) - P
        A /= np.linalg.norm(A); B /= np.linalg.norm(B)
        ang = math.acos(max(-1, min(1, np.dot(A, B)))); r = max(radii[i], 1e-4)
        t = r / math.tan(ang / 2); C = P + (A + B) / np.linalg.norm(A + B) * (r / math.sin(ang / 2))
        T0, T1 = P + A * t, P + B * t
        a0 = math.atan2(*(T0 - C)[::-1]); a1 = math.atan2(*(T1 - C)[::-1])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for j in range(k + 1):
            q = a0 + da * j / k; out.append((C[0] + r * math.cos(q), C[1] + r * math.sin(q)))
    return out

def tent_outline(d, hw=TENT_W / 2 * 1.093, h=TENT_H * 1.19, rb=0.07, ra=0.17, k=4):
    """Rounded A-frame section (x, y), ccw, inset by d (edges offset by d: the triangle shrinks about its incentre)."""
    V = [(hw, 0.0), (0.0, h), (-hw, 0.0)]
    sa, sb = math.hypot(hw, h), 2 * hw
    rho = (2 * hw * h / 2) / ((2 * sa + sb) / 2); inc = (0.0, rho)         # incentre / inradius of the triangle
    s = (rho - d) / rho
    W = [(inc[0] + (x - inc[0]) * s, inc[1] + (y - inc[1]) * s) for x, y in V]
    return fillet_poly(W, [max(rb - d, 0.01), max(ra - d, 0.02), max(rb - d, 0.01)], k)

def pennant_outline(L, H, d):
    """A small rounded pennant (round at the pole, pointed at the tip, which is softened by the inset); inset d shrinks it about its centre."""
    pts = []
    for i in range(16):
        a = 2 * math.pi * i / 16
        x = L * 0.5 * (1 + math.cos(a)); y = H * 0.5 * math.sin(a) * (1 - 0.82 * x / L)
        pts.append((x, y))
    cx, cy = L * 0.42, 0.0; s = max(0.2, 1 - d / (H * 0.5))
    return [(cx + (x - cx) * s, cy + (y - cy) * s) for x, y in pts]

def build_tent():
    p = Part(); D = TENT_D; N = 7; zs = [-D / 2 + D * i / N for i in range(N + 1)]
    for i in range(N):
        z0, z1 = zs[i], zs[i + 1]
        col = ORANGE if i % 2 == 0 else CREAM
        prof = [(0.0, z0), (0.0, z1)]
        if i == 0: prof = [(0.05, z0), (0.016, z0 + 0.014), (0.0, z0 + 0.045)] + prof[1:]
        if i == N - 1: prof = prof[:1] + [(0.0, z1 - 0.045), (0.016, z1 - 0.014), (0.05, z1)]
        loft(p, 0, 0, 0, 0, prof, lambda u, v, h: (u, v, h), col, caps=(i == 0, i == N - 1), outline=tent_outline)
    # the dark opening: a rounded arch standing 1.4 cm proud of the front face
    zf = D / 2
    door = [(0.03, zf - 0.02), (0.0, zf - 0.01), (0.0, zf + 0.006), (0.014, zf + 0.016)]
    loft(p, 0, 0, 0, 0, door, lambda u, v, h: (u, v, h), DARK, outline=lambda d: dshape(0.27, 0.0, 0.36, d, 10))
    # pole on the ridge with a pink pennant
    lathe(p, [(0.0, TENT_H - 0.25), (0.017, TENT_H - 0.25), (0.014, 1.50), (0.0, 1.50)], 8, (0, 0, 0), "y", POLE)
    lathe(p, sphere_prof(1.515, 0.026, 4), 10, (0, 0, 0), "y", CREAM)
    fl = [(0.018, -0.011), (0.0, -0.005), (0.0, 0.005), (0.018, 0.011)]
    loft(p, 0, 0, 0, 0, fl, lambda u, v, h: (0.012 + u, 1.36 + v, h), PINK, outline=lambda d: pennant_outline(0.30, 0.17, d), smooth_caps=True)
    return p

def export(name, p, ao):
    os.makedirs(OUT, exist_ok=True)
    lines = [], []
    with open(os.path.join(OUT, name + ".obj"), "w") as fh:
        fh.write("# %s: game coordinates. v x y z r g b ao w (rgb LINEAR)\n" % name)
        for q, c, a in zip(p.P, p.C, ao): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f %.3f %.3f\n" % (*q, *lin(c), a, 0.0))
        for n in p.N: fh.write("vn %.4f %.4f %.4f\n" % tuple(n))
        fh.write("o %s\n" % name)
        for a, b, c in p.F: fh.write("f %d//%d %d//%d %d//%d\n" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))
    P = np.array(p.P)
    info = dict(id=name, tris=len(p.F), verts=len(P), sub_meshes=[dict(name=name, pivot=[0, 0, 0], material="plain", tris=len(p.F))],
                bounds_min=[round(float(x), 4) for x in P.min(0)], bounds_max=[round(float(x), 4) for x in P.max(0)], anchor_rest=[0, 0, 0])
    json.dump(info, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    return info

for nm, fn in (("post", build_post), ("rail", build_rail), ("gate_post", build_gate_post), ("tent", build_tent)):
    part = fn(); ao = bake_ao([(nm, (0, 0, 0), part)])[nm]
    i = export(nm, part, ao)
    print("EXPORT", nm, i["tris"], "tris", i["verts"], "verts", i["bounds_min"], i["bounds_max"])
