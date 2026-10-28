"""Toolkit for modelling the Jelbie shoes (runs inside Blender: Blender -b -P model_shoes.py -- <foot_bean.json> <outdir>).

Everything is foot-local: sole plane y = 0, footprint centre near the origin, toe +z, x lateral (shoes are symmetric about x = 0, so one model serves
both feet; the app mirrors it with the foot). A shoe is a list of Parts (numpy arrays) merged at the end.

The upper is the foot bean's own Catmull-Clark surface pushed out along its normals (so every shoe is shaped to the foot), the sole is a real lofted slab with a
rounded rim, and everything else (toe caps, stripes, laces, straps, eyes, bows, studs ...) is real raised / swept geometry: panels are triangles of the upper cut exactly
along an iso-line of a field and raised with a rounded ramp, ribbons / tubes are swept along rays cast onto the skin.
"""
import json, math
import numpy as np
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def srgb(r, g, b):
    def f(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return np.array([f(r), f(g), f(b)])


def hexc(h):
    h = h.lstrip("#")
    return srgb(*(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def normalize(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


# ---------------------------------------------------------------- the foot skin
class Skin:
    """The foot bean itself (coarse: V, N, F, with the app's own vertex normals) plus one midpoint subdivision of it (fine: V1, N1, F1) that panels are cut from."""

    def __init__(self, bean):
        self.V = np.array(bean["pos"]); self.N = np.array(bean["nrm"]); self.F = np.array(bean["tris"]).reshape(-1, 3)
        fn = np.cross(self.V[self.F[:, 1]] - self.V[self.F[:, 0]], self.V[self.F[:, 2]] - self.V[self.F[:, 0]])
        if (fn * self.N[self.F].sum(1)).sum() < 0: self.F = self.F[:, ::-1].copy()
        V1, N1 = list(self.V), list(self.N)
        edge = {}
        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in edge:
                V1.append((V1[a] + V1[b]) / 2); n = N1[a] + N1[b]; N1.append(n / np.linalg.norm(n)); edge[k] = len(V1) - 1
            return edge[k]
        F1 = []
        for a, b, c in self.F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            F1 += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        self.V1, self.N1, self.F1 = np.array(V1), np.array(N1), np.array(F1)
        self.bvh = BVHTree.FromPolygons([tuple(v) for v in self.V], [tuple(f) for f in self.F])
        self.top = self.V[:, 1].max()

    def ray(self, o, d):
        """First hit of the skin from `o` along `d`: (point, outward normal) or None."""
        h = self.bvh.ray_cast(Vector(o), Vector(d), 5.0)
        if h[0] is None: return None
        n = np.array(h[1]); n = n / np.linalg.norm(n)
        if np.dot(n, d) < 0: pass
        return np.array(h[0]), n

    def smooth_hit(self, o, d):
        """Like ray(), but with the smooth interpolated normal."""
        h = self.bvh.ray_cast(Vector(o), Vector(d), 5.0)
        if h[0] is None: return None
        p = np.array(h[0]); fi = h[2]
        tri = self.F[fi]
        A, B, C = self.V[tri]
        v0, v1, v2 = B - A, C - A, p - A
        d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
        den = d00 * d11 - d01 * d01
        b1 = (d11 * d20 - d01 * d21) / den; b2 = (d00 * d21 - d01 * d20) / den
        n = (1 - b1 - b2) * self.N[tri[0]] + b1 * self.N[tri[1]] + b2 * self.N[tri[2]]
        return p, n / np.linalg.norm(n)


def vnormals(V, F, weld=False):
    """Area-weighted vertex normals; `weld` shares them between vertices at the same position (hard colour edges stay smooth)."""
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    N = np.zeros_like(V)
    for k in range(3): np.add.at(N, F[:, k], fn)
    if weld:
        keys = {}
        ids = np.zeros(len(V), dtype=np.int64)
        for i, p in enumerate(np.round(V, 5)):
            ids[i] = keys.setdefault(tuple(p), len(keys))
        S = np.zeros((len(keys), 3)); np.add.at(S, ids, N); N = S[ids]
    return normalize(N)


# ---------------------------------------------------------------- parts
class Part:
    """A piece of a shoe: positions V, triangles F (counter-clockwise from outside), per-vertex colour C (linear), flag (0 plain, 1 glow, 2 sparkle anchor)."""

    def __init__(self, V, F, C, flag=0, name="", weld=True, N=None):
        self.V = np.asarray(V, float); self.F = np.asarray(F, int).reshape(-1, 3)
        C = np.asarray(C, float)
        self.C = np.tile(C, (len(self.V), 1)) if C.ndim == 1 else C
        self.flag = np.full(len(self.V), flag) if np.isscalar(flag) else np.asarray(flag)
        self.name = name; self.weld = weld; self.N = N


def merge(parts):
    V, F, C, fl, N = [], [], [], [], []
    o = 0
    for p in parts:
        n = p.N if p.N is not None else vnormals(p.V, p.F, weld=p.weld)
        V.append(p.V); F.append(p.F + o); C.append(p.C); fl.append(p.flag); N.append(n)
        o += len(p.V)
    return np.concatenate(V), np.concatenate(F), np.concatenate(C), np.concatenate(fl), np.concatenate(N)


# ---------------------------------------------------------------- cutting the skin along iso-lines
class Cut:
    """Triangles with per-vertex base position V0 and base normal N0 (carried through cuts)."""

    def __init__(self, V0, N0, F):
        self.V0, self.N0, self.F = V0.copy(), N0.copy(), F.copy()

    def cut(self, fn, iso=0.0):
        """Split every triangle along fn(V0) = iso (fn is evaluated at the vertices and interpolated linearly along edges)."""
        f = fn(self.V0) - iso
        V0, N0 = list(self.V0), list(self.N0)
        fv = list(f)
        edge = {}
        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key in edge: return edge[key]
            t = fv[a] / (fv[a] - fv[b])
            V0.append(V0[a] + (V0[b] - V0[a]) * t); n = N0[a] + (N0[b] - N0[a]) * t
            N0.append(n / np.linalg.norm(n)); fv.append(0.0)
            edge[key] = len(V0) - 1
            return edge[key]
        out = []
        eps = 1e-9
        for tri in self.F:
            a, b, c = tri
            s = [fv[a] > eps, fv[b] > eps, fv[c] > eps]
            z = [abs(fv[a]) <= eps, abs(fv[b]) <= eps, abs(fv[c]) <= eps]
            sg = [(1 if fv[i] > eps else (-1 if fv[i] < -eps else 0)) for i in tri]
            if (max(sg) <= 0 or min(sg) >= 0):            # entirely on one side (or touching)
                out.append((a, b, c)); continue
            # find the vertex alone on its side
            idx = list(tri)
            pos = [i for i in range(3) if sg[i] > 0]; neg = [i for i in range(3) if sg[i] < 0]
            if len(pos) == 1 and len(neg) == 1:           # one vertex on the line (sg 0): split into two triangles
                zi = [i for i in range(3) if sg[i] == 0][0]
                p, n_, zz = idx[pos[0]], idx[neg[0]], idx[zi]
                m = mid(p, n_)
                # keep orientation: rebuild as two triangles in the original cyclic order
                cyc = [idx[(zi + k) % 3] for k in range(3)]   # zz, x, y (cyclic)
                x, y = cyc[1], cyc[2]
                m = mid(x, y)
                out.append((zz, x, m)); out.append((zz, m, y)); continue
            lone = pos[0] if len(pos) == 1 else neg[0]
            cyc = [idx[(lone + k) % 3] for k in range(3)]  # lone, b, c in cyclic order
            l, b_, c_ = cyc
            m1, m2 = mid(l, b_), mid(c_, l)
            out.append((l, m1, m2)); out.append((m1, b_, c_)); out.append((m1, c_, m2))
        self.V0 = np.array(V0); self.N0 = np.array(N0); self.F = np.array(out)
        return self

    def keep(self, fn, iso=0.0, above=True):
        f = fn(self.V0) - iso
        g = f if above else -f
        ok = (g[self.F] >= -1e-7).all(1)
        F = self.F[ok]
        used = np.unique(F)
        remap = -np.ones(len(self.V0), dtype=np.int64); remap[used] = np.arange(len(used))
        c = Cut(self.V0[used], self.N0[used], remap[F])
        return c


def panel(skin, field, levels=(0.0,), keep_above=True, base=None, fine=False):
    """The part of the skin where field >= 0, cut exactly on the contour and on every `levels` iso-line (so a height ramp has vertices to stand on)."""
    c = (Cut(skin.V1, skin.N1, skin.F1) if fine else Cut(skin.V, skin.N, skin.F)) if base is None else base
    c = Cut(c.V0, c.N0, c.F)
    for lv in sorted(set(levels) | {0.0}): c.cut(field, lv)
    return c.keep(field, 0.0)


# ---------------------------------------------------------------- swept things
def frame_along(P):
    """Tangents of a polyline."""
    T = np.zeros_like(P)
    T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]
    return normalize(T)


def ribbon(P, Nrm, half, height, colour, profile=((-1, 0.0), (-0.78, 1.0), (0.78, 1.0), (1, 0.0)), up=(0, 0, 1), flag=0, closed=False, lift=0.0):
    """A flat band lying on the skin: P = points on the surface (already offset to the shell), Nrm = surface normals, `half` = half width
    (scalar or per point), `height` = raised amount. Width direction = `up` projected onto the surface (z by default, i.e. across a lace line it runs along the foot)."""
    P = np.asarray(P); Nrm = np.asarray(Nrm)
    W = np.cross(frame_along(P), Nrm)
    W = normalize(W)
    half = np.broadcast_to(np.asarray(half, float), (len(P),))
    V = []
    for k, (s, h) in enumerate(profile):
        V.append(P + Nrm * (lift + height * h) + W * (half * s)[:, None])
    m = len(profile)
    V = np.stack(V, 1).reshape(-1, 3)             # point-major
    F = []
    n = len(P)
    for i in range(n - (0 if closed else 1)):
        i2 = (i + 1) % n
        for k in range(m - 1):
            a, b, c, d = i * m + k, i * m + k + 1, i2 * m + k + 1, i2 * m + k
            F += [(a, d, c), (a, c, b)]
    return V, np.array(F), Nrm


def make_ribbon(P, Nrm, half, height, colour, flip=False, **kw):
    V, F, _ = ribbon(P, Nrm, half, height, colour, **kw)
    part = Part(V, F, colour, flag=kw.get("flag", 0))
    return orient_out(part, Nrm.mean(0), P.mean(0))


def orient_out(part, nref, pref):
    """Flip the triangles when most of them face against the average outward normal of the surface the part lies on."""
    fn = np.cross(part.V[part.F[:, 1]] - part.V[part.F[:, 0]], part.V[part.F[:, 2]] - part.V[part.F[:, 0]])
    if (fn @ np.asarray(nref)).sum() < 0: part.F = part.F[:, ::-1].copy()
    return part


def tube(path, radii, colour, sides=6, closed=False, caps=True, flag=0, squash=1.0, up=None):
    """A tube swept along `path`; radii scalar or per point; squash flattens the section along `up` (default: first frame normal)."""
    path = np.asarray(path, float); n = len(path)
    r = np.broadcast_to(np.asarray(radii, float), (n,))
    T = frame_along(path)
    if closed:
        T = normalize(np.roll(path, -1, 0) - np.roll(path, 1, 0))
    a = np.array([0.0, 1.0, 0.0]) if up is None else np.asarray(up, float)
    N0 = a - T[0] * (a @ T[0])
    if np.linalg.norm(N0) < 1e-6: N0 = np.cross(T[0], [1, 0, 0])
    N0 = N0 / np.linalg.norm(N0)
    ring = []
    prev = N0
    for i in range(n):
        Ni = prev - T[i] * (prev @ T[i]); Ni = Ni / max(np.linalg.norm(Ni), 1e-9)
        Bi = np.cross(T[i], Ni)
        prev = Ni
        pts = []
        for s in range(sides):
            t = 2 * math.pi * s / sides
            pts.append(path[i] + (Ni * math.cos(t) * squash + Bi * math.sin(t)) * r[i])
        ring.append(pts)
    V = [p for rg in ring for p in rg]
    F = []
    last = n if closed else n - 1
    for i in range(last):
        i2 = (i + 1) % n
        for s in range(sides):
            s2 = (s + 1) % sides
            a_, b_, c_, d_ = i * sides + s, i * sides + s2, i2 * sides + s2, i2 * sides + s
            F += [(a_, b_, c_), (a_, c_, d_)]
    if caps and not closed:
        for end, sgn in ((0, 1), (n - 1, -1)):
            ci = len(V); V.append(path[end] + T[end] * (-sgn) * r[end] * 0.0)
            for s in range(sides):
                s2 = (s + 1) % sides
                if end == 0: F.append((ci, end * sides + s2, end * sides + s))
                else: F.append((ci, end * sides + s, end * sides + s2))
    V = np.array(V)
    part = Part(V, F, colour, flag=flag)
    c = V.mean(0)
    # orient: outward from the tube axis
    fn = np.cross(V[part.F[:, 1]] - V[part.F[:, 0]], V[part.F[:, 2]] - V[part.F[:, 0]])
    cen = V[part.F].mean(1)
    axis_pt = np.array([path[np.argmin(np.linalg.norm(path - x, axis=1))] for x in cen])
    if (fn * (cen - axis_pt)).sum() < 0: part.F = part.F[:, ::-1].copy()
    return part


def uvsphere(c, radii, colour, nu=10, nv=7, flag=0, rot=None):
    c = np.asarray(c, float); radii = np.asarray(radii, float) * np.ones(3)
    V = [c + radii * np.array([0, 1, 0])]
    for j in range(1, nv):
        ph = math.pi * j / nv
        for i in range(nu):
            th = 2 * math.pi * i / nu
            V.append(c + radii * np.array([math.sin(ph) * math.cos(th), math.cos(ph), math.sin(ph) * math.sin(th)]))
    V.append(c - radii * np.array([0, 1, 0]))
    V = np.array(V)
    if rot is not None: V = c + (V - c) @ np.asarray(rot).T
    F = []
    for i in range(nu): F.append((0, 1 + i, 1 + (i + 1) % nu))
    for j in range(nv - 2):
        for i in range(nu):
            a, b = 1 + j * nu + i, 1 + j * nu + (i + 1) % nu
            F += [(a, a + nu, b + nu), (a, b + nu, b)]
    last = len(V) - 1
    for i in range(nu): F.append((last, 1 + (nv - 2) * nu + (i + 1) % nu, 1 + (nv - 2) * nu + i))
    p = Part(V, F, colour, flag=flag)
    fn = np.cross(V[p.F[:, 1]] - V[p.F[:, 0]], V[p.F[:, 2]] - V[p.F[:, 0]])
    if (fn * (V[p.F].mean(1) - c)).sum() < 0: p.F = p.F[:, ::-1].copy()
    return p


def dome(c, n, r, h, colour, sides=8, flag=0, rings=2, shape=None):
    """A little raised disc / bump on the shell at point c with outward normal n (radius r, height h)."""
    n = np.asarray(n) / np.linalg.norm(n)
    a = np.cross(n, [0, 0, 1]);
    if np.linalg.norm(a) < 0.1: a = np.cross(n, [1, 0, 0])
    a = a / np.linalg.norm(a); b = np.cross(n, a)
    V = [c + n * h]
    prof = [(0.8, 0.8), (1.0, 0.0)] if rings == 1 else [(0.45, 0.93), (0.85, 0.62), (1.0, 0.0)]
    for (rad, hh) in prof:
        for i in range(sides):
            t = 2 * math.pi * i / sides
            V.append(c + n * h * hh + (a * math.cos(t) + b * math.sin(t)) * r * rad)
    m = len(prof)
    V = np.array(V); F = []
    for i in range(sides): F.append((0, 1 + i, 1 + (i + 1) % sides))
    for k in range(m - 1):
        for i in range(sides):
            i2 = (i + 1) % sides
            p, q = 1 + k * sides + i, 1 + (k + 1) * sides + i
            p2, q2 = 1 + k * sides + i2, 1 + (k + 1) * sides + i2
            F += [(p, q, q2), (p, q2, p2)]
    part = Part(V, F, colour, flag=flag)
    fn = np.cross(V[part.F[:, 1]] - V[part.F[:, 0]], V[part.F[:, 2]] - V[part.F[:, 0]])
    if (fn @ n).sum() < 0: part.F = part.F[:, ::-1].copy()
    return part


def octa(c, n, r, colour, flag=0):
    """A little four-pointed diamond (glitter stud) standing on the shell."""
    n = np.asarray(n) / np.linalg.norm(n)
    a = np.cross(n, [0, 0, 1])
    if np.linalg.norm(a) < 0.1: a = np.cross(n, [1, 0, 0])
    a = a / np.linalg.norm(a); b = np.cross(n, a)
    V = np.array([c + n * r * 0.75, c + a * r, c + b * r, c - a * r, c - b * r, c - n * r * 0.1])
    F = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 1), (5, 2, 1), (5, 3, 2), (5, 4, 3), (5, 1, 4)]
    p = Part(V, F, colour, flag=flag, weld=False)
    fn = np.cross(V[p.F[:, 1]] - V[p.F[:, 0]], V[p.F[:, 2]] - V[p.F[:, 0]])
    if (fn * (V[p.F].mean(1) - c)).sum() < 0: p.F = p.F[:, ::-1].copy()
    return p


# ---------------------------------------------------------------- the sole slab
def outline_at(skin, y, n=48, centre=(0.0, 0.0), yref=None):
    """The skin's horizontal cross-section at height y: points (x, z) at n angles, found by casting rays outward from the footprint centre line."""
    pts = []
    cz = centre[1]
    for k in range(n):
        th = 2 * math.pi * k / n
        d = np.array([math.sin(th), 0, math.cos(th)])
        # march outward from inside: the bean at height y is hit from far away inwards
        o = np.array([centre[0] + d[0] * 0.6, y, cz + d[2] * 0.6])
        h = skin.bvh.ray_cast(Vector(o), Vector(-d), 2.0)
        if h[0] is None:
            pts.append((centre[0], cz, th)); continue
        p = np.array(h[0]); pts.append((p[0], p[2], th))
    return np.array(pts)


def offset2d(P, d):
    """Offset a closed 2D polygon (n,2) outward by d (counter-clockwise from above assumed by sign test)."""
    n = len(P)
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    N = np.stack([T[:, 1], -T[:, 0]], 1)
    N = normalize(N)
    c = P.mean(0)
    if ((P - c) * N).sum() < 0: N = -N
    return P + N * d, N


class Sole:
    """A solid sole slab: rings (y, outward inset, colour) from the bottom up, rounded; a flat bottom cap; the top ledge is where the upper stands."""

    def __init__(self, skin, top=0.034, flare=0.016, centre=(0.0, 0.02), n=56, bottom=-0.005):
        self.skin, self.top, self.flare, self.centre, self.n, self.bottom = skin, top, flare, centre, n, bottom
        o = outline_at(skin, top, n, centre)
        self.base2d = o[:, :2]

    def build(self, bands, ledge_colour=None, ledge_in=0.03, heel_extra=0.0, toe_extra=0.0):
        """bands: list of (y0, y1, colour) from bottom to top covering [0, top]; consecutive bands share an edge with a hard colour change.
        Rim bevel: the bottom edge rounds over 0.006, the top edge over 0.005."""
        base = self.base2d
        c = np.array(self.centre)
        FL = []
        def ring(y, inset):
            P, Nn = offset2d(base, self.flare - inset)
            return np.column_stack([P[:, 0], np.full(len(P), y), P[:, 1]]), Nn
        V, F, C = [], [], []
        def add_ring(y, inset, col, fl=0):
            R, Nn = ring(y, inset); s = len(V); V.extend(R); C.extend([col] * len(R)); FL.extend([fl] * len(R)); return s
        # profile points (y, inset) with colour of the band they bound
        prof = []
        bevB, bevT = 0.007, 0.006
        def inset_at(y):
            b = 0.0
            if y < bevB: b = bevB * (1 - math.sqrt(max(0.0, 1 - ((bevB - y) / bevB) ** 2)))
            if y > self.top - bevT: b = bevT * (1 - math.sqrt(max(0.0, 1 - ((y - (self.top - bevT)) / bevT) ** 2)))
            return b
        rings_idx = []
        for band in bands:
            y0, y1, col = band[:3]; bfl = band[3] if len(band) > 3 else 0
            ys = sorted(set([y0, y1] + [v for v in (bevB * 0.4, bevB, self.top - bevT, self.top - bevT * 0.4) if y0 < v < y1]))
            ids = []
            for y in ys:
                yy = self.bottom if y <= 1e-9 else y
                ids.append(add_ring(yy, inset_at(y), col, bfl))
            rings_idx.append(ids)
        n = self.n
        for ids in rings_idx:
            for a, b in zip(ids[:-1], ids[1:]):
                for i in range(n):
                    i2 = (i + 1) % n
                    F += [(a + i, b + i2, b + i), (a + i, a + i2, b + i2)]
        # bottom cap: concentric rings (so the sole keeps following the foot's round bottom when the bean morphs to a ball), then a fan
        bi = rings_idx[0][0]
        cb = len(V); V.append(np.array([0.0, self.bottom - 0.010, 0.0])); C.append(bands[0][2]); FL.append(0)
        prev = None
        cap_rings = []
        for f in (0.2, 0.4, 0.6, 0.8):
            s0 = len(V)
            for i in range(n):
                q = V[bi + i]
                V.append(np.array([c[0] + (q[0] - c[0]) * f, self.bottom - 0.010 * (1 - f) ** 2, c[1] + (q[2] - c[1]) * f])); C.append(bands[0][2]); FL.append(0)
            cap_rings.append(s0)
        first = cap_rings[0]
        for i in range(n): F.append((cb, first + i, first + (i + 1) % n))
        chain = cap_rings + [bi]
        for a, b in zip(chain[:-1], chain[1:]):
            for i in range(n):
                i2 = (i + 1) % n
                F += [(a + i, b + i, b + i2), (a + i, b + i2, a + i2)]
        # top ledge: from the top ring inwards
        top_ring = rings_idx[-1][-1]
        lc = ledge_colour if ledge_colour is not None else bands[-1][2]
        inner, _ = offset2d(base, -ledge_in)
        s = len(V)
        for i in range(n):
            V.append(np.array([inner[i, 0], self.top, inner[i, 1]])); C.append(lc); FL.append(0)
        # a separate copy of the top ring in the ledge colour
        s2 = len(V)
        outer, _ = offset2d(base, self.flare - inset_at(self.top))
        for i in range(n):
            V.append(np.array([outer[i, 0], self.top, outer[i, 1]])); C.append(lc); FL.append(0)
        for i in range(n):
            i2 = (i + 1) % n
            F += [(s2 + i, s + i, s + i2), (s2 + i, s + i2, s2 + i2)]
        V = np.array(V); F = np.array(F)
        part = Part(V, F, np.array(C), flag=np.array(FL), name="sole")
        # orient: outward from the slab centre (the bottom cap faces down, ledge up)
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        cen = V[F].mean(1)
        mid = np.array([c[0], self.top / 2, c[1]])
        sgn = 0
        side = np.abs(fn[:, 1]) < 0.5 * np.linalg.norm(fn, axis=1)
        if ((fn[side] * (cen[side] - mid)).sum()) < 0: part.F = part.F[:, ::-1].copy()
        # the flat triangles: the bottom cap must face down, the ledge up (the global flip above only knows the walls)
        F2 = part.F.copy()
        fn = np.cross(V[F2[:, 1]] - V[F2[:, 0]], V[F2[:, 2]] - V[F2[:, 0]])
        flat = np.abs(fn[:, 1]) > 0.9 * np.linalg.norm(fn, axis=1)
        want_down = V[F2].mean(1)[:, 1] < self.top / 2
        wrong = flat & ((fn[:, 1] < 0) != want_down)
        F2[wrong] = F2[wrong][:, ::-1]
        part.F = F2
        return part


# ---------------------------------------------------------------- shells and finishing
def shell_points(skin, V0, N0, thick, extra=0.0):
    return V0 + N0 * (thick(V0) + extra)[:, None] if np.ndim(extra) else V0 + N0 * (thick(V0)[:, None] + extra)


def to_part(cutmesh, thick, colour, raise_fn=None, flag=0, name="", field=None):
    V0, N0, F = cutmesh.V0, cutmesh.N0, cutmesh.F
    h = thick(V0)
    if raise_fn is not None: h = h + raise_fn(V0)
    return Part(V0 + N0 * h[:, None], F, colour, flag=flag, name=name)


def finish(parts, name, outdir):
    V, F, C, fl, N = merge(parts)
    # a rest normal per vertex, ao 1
    data = dict(pos=V.tolist(), nrm=N.tolist(), col=C.tolist(), flag=[int(x) for x in fl], ao=[1.0] * len(V), idx=F.flatten().tolist())
    json.dump(data, open("%s/%s.json" % (outdir, name), "w"))
    return V, F, C, fl, N


def boundary_loops(c, pred):
    """Ordered boundary loops of a Cut mesh restricted to edges whose midpoint satisfies pred(mid). Returns a list of index lists."""
    cnt = {}
    for t in c.F:
        for k in range(3):
            a, b = t[k], t[(k + 1) % 3]
            key = (min(a, b), max(a, b)); cnt.setdefault(key, []).append((a, b))
    edges = [v[0] for k, v in cnt.items() if len(v) == 1 and pred((c.V0[k[0]] + c.V0[k[1]]) / 2)]
    nxt = {}
    for a, b in edges: nxt.setdefault(a, []).append(b)
    loops, used = [], set()
    for a, b in edges:
        if (a, b) in used: continue
        loop = [a]; cur = b; used.add((a, b))
        while cur != a and len(loop) < 5000:
            loop.append(cur)
            opts = [x for x in nxt.get(cur, []) if (cur, x) not in used]
            if not opts: break
            used.add((cur, opts[0])); cur = opts[0]
        loops.append(loop)
    return loops
