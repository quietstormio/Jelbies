"""Build the Park's foliage in headless Blender and export OBJ+JSON (2026-11-09 redesign: structured trees, not cotton-ball canopies).

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_foliage.py -- [ids...]
  python3 convert.py <export dir> BobV1/Room/Resources        # -> park_<id>.bin (same .bin format as decor_<id>.bin)

Assets: tree_a oak (wide, layered), tree_b beech/maple (tall oval), tree_c birch (airy, pale trunk), pine_a / pine_b spruce (tiers of drooping bough fans),
bush_a / bush_b shrubs, flowers (grass + small garden flowers), and cheap far-row variants <id>_far (about a third of the triangles).
Game coordinates (y up, +z toward the camera, origin = trunk foot / clump centre on the ground). Parts: "bark", "leaf", "bloom".
Every shape is CLOSED (the renderer culls back faces). Colours are baked per vertex: sun term (sun dir 0.45,0.8,0.4), AO between clumps, dark interior,
hue variation clump to clump. `bloom` parts are neutral cream so the game can tint them per bush.
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dk import *
from lib import nz
from mathutils import Vector
import bmesh

SUN = Vector((0.45, 0.8, 0.4)).normalized()
def clamp01(x): return max(0.0, min(1.0, x))
def rot_about(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis) @ v

# ---------------------------------------------------------------- palettes (sRGB)
PAL_OAK = dict(shade=(0.09, 0.23, 0.10), mid=(0.21, 0.42, 0.14), sun=(0.46, 0.62, 0.20))
PAL_BEECH = dict(shade=(0.10, 0.25, 0.11), mid=(0.24, 0.45, 0.15), sun=(0.50, 0.66, 0.21))
PAL_BIRCH = dict(shade=(0.16, 0.33, 0.12), mid=(0.33, 0.52, 0.17), sun=(0.60, 0.72, 0.27))
PAL_SPRUCE = dict(shade=(0.05, 0.16, 0.12), mid=(0.12, 0.31, 0.19), sun=(0.28, 0.48, 0.24))
PAL_FIR = dict(shade=(0.06, 0.19, 0.12), mid=(0.15, 0.35, 0.18), sun=(0.34, 0.54, 0.24))
PAL_BUSH = dict(shade=(0.10, 0.25, 0.11), mid=(0.23, 0.43, 0.16), sun=(0.44, 0.62, 0.21))
YG = (0.42, 0.56, 0.13); BG = (0.12, 0.36, 0.26)

def pal_mix(pal, t):
    return mix(pal['shade'], pal['mid'], t * 2) if t < 0.5 else mix(pal['mid'], pal['sun'], (t - 0.5) * 2)

def leaf_color(pal, clumps, me, cc, cr, y0, y1, hue=0.0, seed=0.0, sunk=0.0):
    """Vertex colour fn for a leaf clump: sun term, AO from the other clumps, dark interior, hue drift, fine speckle."""
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        h = clamp01((p.y - y0) / max(0.01, y1 - y0))
        q = p + n * 0.10
        occ = 0.0
        for i, (c, r) in enumerate(clumps):
            if i == me: continue
            d = (q - c).length
            if d < r: occ += (1 - d / r)
        occ = min(1.0, occ)
        outer = clamp01((p - cc).length / cr)
        t = clamp01(0.04 + 0.64 * s01 ** 1.4 + 0.30 * h - 0.45 * occ * (1 - 0.4 * s01) - sunk)
        t *= 0.52 + 0.48 * outer
        col = pal_mix(pal, t)
        if hue > 0: col = mix(col, YG, 0.28 * hue * (0.4 + t))
        elif hue < 0: col = mix(col, BG, 0.28 * -hue * (0.4 + t))
        sp = 1 + 0.08 * nz(p, 9.0, seed)
        return tuple(min(1.0, c * sp) for c in col)
    return fn

# ---------------------------------------------------------------- shapes
def clump_bm(r, flat, sub, bump, seed, tall=1.0):
    """A lobed leaf mass: displaced icosphere, large lobes plus leaf-scale bumps (smooth-shaded)."""
    bm = sph_bm(r, r * flat * tall, r, sub)
    for v in bm.verts:
        d = v.co.normalized()
        k = 1 + bump * (nz(d * 2.4, 1.0, seed) + 0.8 * nz(d * 5.2, 1.0, seed + 5) + 0.5 * nz(d * 10.0, 1.0, seed + 9))
        v.co = v.co * k
    return bm

def bough_bm(L, W, droop, thick=0.45, sides=6, segs=4, jag=0.0):
    """One tapered, down-curved spruce bough along +x (closed, pointed tip)."""
    bm = bmesh.new(); rings = []
    for k in range(segs + 1):
        t = k / segs
        c = Vector((L * t, -droop * t * t, 0))
        w = W * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.28 + t * 0.62))) * (1 - t) ** 0.55 if k < segs else 0.0
        w *= 1 + jag * (1 if k % 2 else -1)
        if k == segs: rings.append([bm.verts.new(c + Vector((0.02 * L, -0.05 * droop, 0)))] * sides)
        else: rings.append([bm.verts.new(c + Vector((0, math.sin(2 * math.pi * i / sides) * w * thick, math.cos(2 * math.pi * i / sides) * w))) for i in range(sides)])
    for k in range(segs):
        for i in range(sides):
            j = (i + 1) % sides
            vs = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            u = []
            for v in vs:
                if v not in u: u.append(v)
            if len(u) >= 3:
                try: bm.faces.new(u)
                except ValueError: pass
    bm.faces.new(rings[0][::-1])
    return bm

# ---------------------------------------------------------------- bark
BARK_SHADE = (0.20, 0.16, 0.13); BARK_SUN = (0.46, 0.38, 0.30)
def bark_fn(pale=False, seed=0.0):
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        if pale:
            c = mix((0.46, 0.45, 0.42), (0.93, 0.92, 0.86), s01)
            m = nz(Vector((p.x * 3, p.y * 16, p.z * 3)), 1.0, seed)
            if m > 0.18 and p.y > 0.2: c = mix(c, (0.12, 0.10, 0.09), clamp01((m - 0.18) * 5))
            return c
        c = mix(BARK_SHADE, BARK_SUN, s01 ** 1.2)
        k = 1 + 0.10 * nz(Vector((p.x * 7, p.y * 2.2, p.z * 7)), 1.0, seed)
        low = clamp01(1 - p.y / 1.2) * 0.18
        return tuple(max(0, min(1, x * k * (1 - low))) for x in c)
    return fn

# ---------------------------------------------------------------- tufts + crowns
def tufts_bm(items):
    """items: (pos, dir, L, W). One closed flattened bipyramid per tuft (a little leaf cluster), all in one bmesh."""
    bm = bmesh.new()
    for pos, d, L, W in items:
        q = Vector((1, 0, 0)).rotation_difference(d.normalized()).to_matrix()
        loc = [(0, 0, 0), (L, 0, 0), (L * 0.4, W, 0), (L * 0.4, -W, 0), (L * 0.4, 0, W * 0.45), (L * 0.4, 0, -W * 0.45)]
        v = [bm.verts.new(pos + q @ Vector(p)) for p in loc]
        A, B, C, D, E_, F = v
        for f in ((A, C, E_), (A, E_, D), (A, D, F), (A, F, C), (B, E_, C), (B, D, E_), (B, F, D), (B, C, F)):
            bm.faces.new(f)
    return bm

def crown_dome(rng, Rh, yb, Hc, nbig, rbig, tiers, droop):
    out = [(Vector((0, yb + Hc * 0.93, 0)), rbig * 1.05)]
    for i in range(nbig):
        a = rng.uniform(0, 6.283); rho = min(1.0, rng.random() ** 0.62)
        prof = math.sqrt(max(0, 1 - rho * rho)) ** 0.8
        v = rng.choice(tiers)
        y = yb + Hc * prof * v - droop * Hc * max(0, rho - 0.7) / 0.3
        r = rbig * (0.72 + 0.6 * (1 - rho)) * rng.uniform(0.85, 1.15)
        out.append((Vector((math.cos(a) * rho * Rh, y, math.sin(a) * rho * Rh * 0.95)), r))
    return out

def crown_oval(rng, Rh, yb, Hc, nbig, rbig, droop=0.0, shell=0.0):
    yc = yb + Hc / 2; out = []
    for i in range(nbig):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        f = shell + (1 - shell) * rng.random() ** 0.45
        p = Vector((d.x * Rh * f, yc + d.y * Hc / 2 * f, d.z * Rh * f))
        rho = math.hypot(p.x, p.z) / Rh
        p.y -= droop * Hc * 0.5 * rho * rho
        out.append((p, rbig * (0.7 + 0.5 * (1 - f)) * rng.uniform(0.85, 1.15)))
    return out

def limbs(rng, top, Rh, yb, Hc, nm, r0, bfn, sides, lod, sub_n=(2, 3), up=0.0):
    """Heavy main limbs from the fork into the crown, each forking into sub-limbs and twigs; the crown clumps sit on top, limbs show in the gaps below."""
    tips = []
    az0 = rng.uniform(0, 6.283)
    sd = max(4, sides - (2 if lod else 0))
    for i in range(nm):
        az = az0 + i / nm * 6.283 + rng.uniform(-0.3, 0.3)
        dx, dz = math.cos(az), math.sin(az)
        M = Vector((dx * Rh * 0.42, yb + Hc * (0.30 + up) + rng.uniform(-0.1, 0.1), dz * Rh * 0.42))
        mid = (top + M) * 0.5 + Vector((0, 0.05, 0)) + Vector((dz, 0, -dx)) * rng.uniform(-0.12, 0.12)
        add_tube([top, mid, M], 0.05, bfn, sides=sd + 1, radfn=lambda t: r0 * 0.62 * (1 - 0.35 * t))
        for j in range(rng.choice(sub_n)):
            az2 = az + rng.uniform(-0.8, 0.8)
            E = Vector((math.cos(az2) * Rh * rng.uniform(0.70, 0.92), yb + Hc * rng.uniform(0.28, 0.62 + up), math.sin(az2) * Rh * rng.uniform(0.70, 0.92)))
            mid2 = (M + E) * 0.5 + Vector((0, 0.08, 0))
            add_tube([M, mid2, E], 0.04, bfn, sides=max(4, sd - 1), radfn=lambda t: r0 * 0.34 * (1 - 0.55 * t))
            tips.append(E)
            if not lod:
                for k in range(2):
                    T2 = E + Vector((rng.uniform(-0.3, 0.3), rng.uniform(0.15, 0.45), rng.uniform(-0.3, 0.3)))
                    add_tube([E, T2], 0.02, bfn, sides=4, radfn=lambda t: r0 * 0.14 * (1 - 0.6 * t))
    return tips

def deciduous(iid, seed, spec, pal, lod=0, pale=False):
    rng = random.Random(seed); lib.reset(); reset()
    sides = 8 if lod == 0 else 5
    bfn = bark_fn(pale, seed)
    kind = spec['kind']
    begin("bark")
    H = spec['trunk']; r0 = spec['r0']; Rh = spec['Rh']; Hc = spec['Hc']; yb = spec.get('yb', H + 0.1)
    if pale:
        for k in range(spec['stems']):
            a = k / spec['stems'] * 6.283 + 0.6
            lean = Vector((math.cos(a), 0, math.sin(a))) * (0.10 + 0.08 * k)
            pts = [Vector((lean.x * (t ** 1.5) * 1.2, H * t, lean.z * (t ** 1.5) * 1.2)) for t in [i / 13 for i in range(14)]]
            add_tube(pts, 0.1, bfn, sides=6 if lod == 0 else 4, radfn=lambda t, k=k: r0 * (1 + 0.5 * max(0, 1 - t * 8) ** 2) * (1 - 0.55 * t) * (1 - 0.08 * k), cap=True)
        top = Vector((0.04, H, 0.02))
    else:
        pts = [Vector((0, H * t, 0)) for t in [i / 6 for i in range(7)]]
        add_tube(pts, 0.1, bfn, sides=sides, radfn=lambda t: r0 * (1 + spec['flare'] * max(0, 1 - t * 3.2) ** 2) * (1 - 0.34 * t), cap=True)
        top = pts[-1]
    tips = limbs(rng, top, Rh, yb, Hc, spec['nm'], r0, bfn, sides, lod, up=spec.get('up', 0.0))
    nb, ns = spec['nbig'], spec['nsmall']
    if lod: nb, ns = max(8, int(nb * 0.62)), int(ns * 0.5)
    if kind == 'dome': cl = crown_dome(rng, Rh, yb, Hc, nb, spec['rbig'], spec['tiers'], spec['droop'])
    else: cl = crown_oval(rng, Rh, yb, Hc, nb, spec['rbig'], spec.get('droop', 0.0), spec.get('shell', 0.0))
    sm = []
    for i in range(ns):
        c, r = cl[rng.randrange(len(cl))]
        d = Vector((rng.uniform(-1, 1), rng.uniform(-0.25, 1), rng.uniform(-1, 1))).normalized()
        sm.append((c + d * r * 0.85, r * rng.uniform(0.35, 0.55)))
    flat = spec['flat']; tall = spec.get('tall', 1.0)
    allc = cl + sm
    ctr = Vector((0, yb + Hc * 0.5, 0)); cr = max(Rh, Hc * 0.5) * 1.15
    y0 = yb; y1 = yb + Hc
    begin("leaf")
    for i, (c, r) in enumerate(allc):
        big = i < len(cl)
        sub = 3 if (big and i < (9 if lod == 0 else 2)) else (2 if (big or lod == 0) else 1)
        col = leaf_color(pal, allc, i, ctr, cr, y0, y1, hue=rng.uniform(-1, 1), seed=i * 3.1)
        if lod: r *= 1.22
        commit(clump_bm(r, flat, sub, spec.get('bump', 0.2), seed + i * 1.7, tall), col, sharp=100, xf=T(tuple(c), ry=rng.uniform(0, 6.28)))
    nt = spec['ntuft'] if lod == 0 else spec['ntuft'] // 3
    items = []
    tries = 0
    while len(items) < nt and tries < nt * 6:
        tries += 1
        c, r = allc[rng.randrange(len(allc))]
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1) * 0.8, rng.gauss(0, 1))).normalized()
        p = c + Vector((d.x * r, d.y * r * flat * tall, d.z * r)) * 0.96
        if sum(1 for (c2, r2) in allc if (p - c2).length < r2 * 0.92) > 0: continue
        out = d + Vector((0, -0.35 - 0.3 * rng.random(), 0))
        L = spec['tuft'] * rng.uniform(0.8, 1.4) * (1.7 if lod else 1.0)
        items.append((p, out, L, L * 0.42))
    tcol = leaf_color(pal, allc, -1, ctr, cr, y0, y1, hue=0.0, seed=77)
    def tfn(p, n):
        h = nz(p, 2.6, 5.0)
        c = tcol(p, n)
        c = mix(c, YG if h > 0 else BG, 0.22 * abs(h))
        return tuple(min(1.0, x * 1.12) for x in c)
    if items: commit(tufts_bm(items), tfn, sharp=100)
    return dict(kind="tree", canopy_radius=Rh, height=y1)

OAK = dict(kind='dome', trunk=0.95, r0=0.20, flare=0.7, Rh=1.55, Hc=1.85, yb=1.2, nm=5, nbig=24, rbig=0.46, nsmall=40, flat=0.66, bump=0.30,
           tiers=[0.42, 0.62, 0.80, 0.97], droop=0.40, ntuft=420, tuft=0.17)
BEECH = dict(kind='oval', trunk=1.2, r0=0.14, flare=0.6, Rh=1.1, Hc=2.7, yb=1.15, nm=4, nbig=26, rbig=0.40, nsmall=40, flat=0.84, tall=1.1, bump=0.28,
             droop=0.15, ntuft=420, tuft=0.16, up=0.1, shell=0.25)
BIRCH = dict(kind='oval', trunk=2.2, r0=0.085, flare=0.4, Rh=1.15, Hc=2.5, yb=1.45, nm=4, nbig=64, rbig=0.17, nsmall=30, flat=0.9, tall=2.3, bump=0.30,
             droop=1.0, ntuft=380, tuft=0.14, stems=3, up=0.1, shell=0.45)

# ---------------------------------------------------------------- conifers
def conifer(iid, seed, tiers=9, H=3.8, R=1.15, pal=PAL_SPRUCE, lod=0, trunk_h=0.8):
    rng = random.Random(seed); lib.reset(); reset()
    begin("bark")
    bfn = bark_fn(False, seed)
    add_tube([Vector((0, 0, 0)), Vector((0, 0.5, 0)), Vector((0, 1.4, 0)), Vector((0, H * 0.8, 0)), Vector((0, H, 0))], 0.1, bfn, sides=6 if lod else 8,
             radfn=lambda t: 0.15 * (1 + 0.9 * max(0, 1 - t * 8) ** 2) * (1 - 0.88 * t))
    begin("leaf")
    ytop = H
    ring = []
    tl = []
    for t in range(tiers):
        f = t / (tiers - 1)
        y = trunk_h + (H * 0.93 - trunk_h) * f
        rr = R * (1 - f) ** 0.8 * 1.0 + 0.10
        nb = max(5, int(round((13 - 4 * f) * (0.62 if lod else 1.0))))
        ring.append((y, rr, nb))
    def cfn(y, rr):
        def fn(p, n):
            s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
            h = clamp01((p.y - trunk_h) / (H - trunk_h))
            outer = clamp01(math.hypot(p.x, p.z) / max(0.1, rr))
            under = clamp01(1 - (p.y - (y - 0.5)) * 0.0)
            t = clamp01(0.04 + 0.60 * s01 ** 1.5 + 0.22 * h) * (0.42 + 0.58 * outer ** 0.8)
            col = pal_mix(pal, t)
            col = mix(col, YG, 0.10 * t) if t > 0.5 else col
            return tuple(min(1, c * (1 + 0.07 * nz(p, 8.0, y))) for c in col)
        return fn
    for ti, (y, rr, nb) in enumerate(ring):
        ph = rng.uniform(0, 6.28)
        for i in range(nb):
            a = ph + i / nb * 6.283 + rng.uniform(-0.12, 0.12)
            L = rr * rng.uniform(0.82, 1.12)
            W = max(0.12, rr * 0.50) * rng.uniform(0.9, 1.2)
            dr = L * rng.uniform(0.28, 0.42)
            bm = bough_bm(L, W, dr, thick=0.60, sides=5 if lod else 6, segs=3 if lod else 4, jag=0.10)
            # roll slightly so the fan's top planes face up and out
            xm = T((0, y + rng.uniform(-0.04, 0.04), 0), ry=-a, rz=rng.uniform(0.05, 0.22))
            commit(bm, cfn(y, rr), sharp=100, xf=xm)
            for kk in range(2 if lod else 4):
                t = rng.uniform(0.35, 0.95); sd = rng.choice((-1, 1))
                pw = xm @ Vector((L * t, -dr * t * t + 0.01, sd * W * 0.55 * (1 - t) ** 0.5))
                dw = xm.to_3x3() @ Vector((0.7, -0.45, sd * 0.9))
                tl.append((pw, dw, 0.13 * (1.6 if lod else 1.0) * rng.uniform(0.8, 1.3), 0.05 * (1.6 if lod else 1.0)))
            if lod == 0 and rr > 0.55 and i % 2 == 0:
                # shorter, higher inner boughs fill the middle and give the tier thickness
                bm2 = bough_bm(L * 0.62, W * 0.9, dr * 0.5, thick=0.5, sides=5, segs=3, jag=0.06)
                commit(bm2, cfn(y + 0.14, rr), sharp=100, xf=T((0, y + 0.13, 0), ry=-(a + 0.5 / nb * 6.283), rz=rng.uniform(0.12, 0.3)))
    commit(tufts_bm(tl), cfn(H * 0.5, R), sharp=100)
    # a pointed leader
    lead = lathe_bm([(0, ring[-1][0] - 0.1), (0.13, ring[-1][0] - 0.02), (0.09, ring[-1][0] + 0.3), (0.0, H + 0.12)], 6)
    commit(lead, cfn(H, 0.2), sharp=60)
    return dict(kind="conifer", canopy_radius=R, height=H + 0.12)

# ---------------------------------------------------------------- shrubs
def bush(iid, seed, R=1.0, nbl=14, hedge=False, lod=0):
    rng = random.Random(seed); lib.reset(); reset()
    cl = []
    if hedge:
        cl.append((Vector((0, 0.27 * R, 0)), 1.0))
    else:
        cl.append((Vector((0, 0.42 * R, 0)), 0.40 * R))
        for i in range(11):
            a = rng.uniform(0, 6.28); d = R * rng.uniform(0.25, 0.80)
            hh = R * (0.20 + 0.45 * (1 - d / R))
            cl.append((Vector((math.cos(a) * d * 1.1, hh * rng.uniform(0.7, 1.1), math.sin(a) * d * 0.85)), R * rng.uniform(0.20, 0.30)))
    ctr = Vector((0, 0.4 * R, 0))
    begin("bark")
    for k in range(3):
        a = rng.uniform(0, 6.28)
        add_tube([Vector((math.cos(a) * 0.08, 0, math.sin(a) * 0.08)), Vector((math.cos(a) * 0.14, 0.2 * R, math.sin(a) * 0.14))], 0.02, bark_fn(False, seed), sides=4, radfn=lambda t: 0.035 * (1 - 0.4 * t))
    begin("leaf")
    allc = [(c, r) for c, r in cl]
    items = []
    if hedge:
        # a clipped hedge: a squarish rounded run with a leafy, slightly irregular surface
        bm = pill_bm(1.0, 0.27, 0.27, 0.42, 4)
        for v in bm.verts:
            d = v.co.normalized()
            v.co = v.co * (1 + 0.05 * (nz(d * 6.0, 1.0, seed) + 0.6 * nz(d * 13.0, 1.0, seed + 3)))
        hc = leaf_color(PAL_BUSH, [(Vector((0, 0.27, 0)), 0.5)], -1, Vector((0, 0.27, 0)), 1.1, 0.0, 0.55, hue=0.3, seed=2.0, sunk=0.03)
        commit(bm, hc, sharp=100, xf=T((0, 0.27, 0)))
        for k in range(320):
            a = rng.uniform(0, 6.283)
            d = Vector((rng.uniform(-1, 1) * 0.9, math.sin(a) * 0.7 + 0.1, math.cos(a) * 0.7))
            p = Vector((d.x * 0.97, 0.27 + d.y * 0.27, d.z * 0.27))
            items.append((p, Vector((d.x * 0.3, d.y, d.z)) + Vector((0, -0.25, 0)), 0.12 * rng.uniform(0.8, 1.3), 0.05))
    else:
        for i, (c, r) in enumerate(cl):
            col = leaf_color(PAL_BUSH, allc, i, ctr, R * 1.1, 0.0, R * 0.95, hue=rng.uniform(-1, 1), seed=i * 2.3, sunk=0.03)
            commit(clump_bm(r, 0.80, 3 if i == 0 else 2, 0.28, seed + i * 2.1), col, sharp=100, xf=T(tuple(c), ry=rng.uniform(0, 6.28)))
        for k in range(150):
            c, r = cl[rng.randrange(len(cl))]
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1) * 0.8, rng.gauss(0, 1))).normalized()
            p = c + Vector((d.x * r, d.y * r * 0.8, d.z * r)) * 0.96
            if sum(1 for (c2, r2) in allc if (p - c2).length < r2 * 0.9) > 0: continue
            items.append((p, d + Vector((0, -0.3, 0)), 0.13 * rng.uniform(0.8, 1.3), 0.055))
    tc = leaf_color(PAL_BUSH, allc, -1, ctr, R * 1.1, 0.0, R * 0.95, hue=0.0, seed=5.0)
    if items: commit(tufts_bm(items), lambda p, n: tuple(min(1, x * 1.15) for x in tc(p, n)), sharp=100)
    begin("bloom")
    if not hedge:
        for k in range(nbl):
            c, r = cl[rng.randrange(len(cl))]
            d = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1), rng.uniform(-1, 1))).normalized()
            p = c + Vector((d.x * r, d.y * r * 0.8, d.z * r)) * 1.05
            def bcol(q, n): return mix((0.72, 0.68, 0.64), (1.0, 0.99, 0.96), clamp01(n.dot(SUN) * 0.5 + 0.5))
            commit(sph_bm(0.045, 0.035, 0.045, 1), bcol, sharp=100, xf=T(tuple(p)))
    return dict(kind="bush")

def flowers(iid, seed):
    rng = random.Random(seed); lib.reset(); reset()
    g0 = (0.10, 0.27, 0.10); g1 = (0.42, 0.62, 0.20)
    begin("leaf")
    def gcol(p, n): return mix(g0, g1, clamp01(p.y / 0.34) ** 0.8)
    for _ in range(34):
        a = rng.uniform(0, 6.28); d = math.sqrt(rng.random()) * 0.40
        base = Vector((math.cos(a) * d, 0, math.sin(a) * d * 0.85))
        hgt = rng.uniform(0.14, 0.32) * (1.15 - 0.5 * d / 0.4)
        dr = a + rng.uniform(-0.9, 0.9)
        lean = Vector((math.cos(dr), 0, math.sin(dr))) * hgt * rng.uniform(0.25, 0.7)
        pts = [base, base + lean * 0.3 + Vector((0, hgt * 0.55, 0)), base + lean + Vector((0, hgt, 0))]
        add_tube(pts, 0.02, gcol, sides=3, radfn=lambda t: 0.020 * (1 - 0.95 * t))
    begin("bloom")
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.uniform(-0.3, 0.3); d = 0.06 if k == 0 else rng.uniform(0.12, 0.34)
        fh = rng.uniform(0.20, 0.34)
        pos = Vector((math.cos(a) * d, fh, math.sin(a) * d * 0.85))
        commit(sph_bm(0.062, 0.045, 0.062, 1), lambda p, n: mix((0.70, 0.66, 0.62), (1.0, 0.99, 0.96), clamp01(n.dot(SUN) * 0.5 + 0.5)), sharp=100, xf=T(tuple(pos)))
    return dict(kind="flowers")

REG = [
    ("tree_a", lambda: deciduous("tree_a", 11, OAK, PAL_OAK)),
    ("tree_b", lambda: deciduous("tree_b", 23, BEECH, PAL_BEECH)),
    ("tree_c", lambda: deciduous("tree_c", 37, BIRCH, PAL_BIRCH, pale=True)),
    ("pine_a", lambda: conifer("pine_a", 5, tiers=9, H=3.9, R=1.15, pal=PAL_SPRUCE)),
    ("pine_b", lambda: conifer("pine_b", 9, tiers=8, H=3.1, R=1.0, pal=PAL_FIR)),
    ("tree_a_far", lambda: deciduous("tree_a_far", 11, OAK, PAL_OAK, lod=1)),
    ("tree_b_far", lambda: deciduous("tree_b_far", 23, BEECH, PAL_BEECH, lod=1)),
    ("tree_c_far", lambda: deciduous("tree_c_far", 37, BIRCH, PAL_BIRCH, lod=1, pale=True)),
    ("pine_a_far", lambda: conifer("pine_a_far", 5, tiers=8, H=3.9, R=1.15, pal=PAL_SPRUCE, lod=1)),
    ("pine_b_far", lambda: conifer("pine_b_far", 9, tiers=7, H=3.1, R=1.0, pal=PAL_FIR, lod=1)),
    ("bush_a", lambda: bush("bush_a", 3, nbl=12)),
    ("bush_b", lambda: bush("bush_b", 8, nbl=10, R=0.9)),
    ("hedge", lambda: bush("hedge", 5, R=1.0, hedge=True)),
    ("flowers", lambda: flowers("flowers", 4)),
]

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import lib
    for iid, fn in REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], [(s["name"], s["tris"]) for s in info["sub_meshes"]], info["bounds_min"], info["bounds_max"], flush=True)
