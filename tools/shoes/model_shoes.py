"""Model the nine Jelbie shoes in Blender and export <case>.json (see tools/shoes/convert_shoe_art.py for the next step).

  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/shoes/model_shoes.py -- <foot_bean.json> <outdir> [--preview <pngdir>] [--only name,name]
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import shoekit as K
from shoekit import *

argv = sys.argv[sys.argv.index("--") + 1:]
BEAN = json.load(open(argv[0])); OUT = argv[1]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
os.makedirs(OUT, exist_ok=True)
skin = K.Skin(BEAN)
SOLE_TOP = 0.034

# ------------------------------------------------------------------ helpers on the skin
def top_y(z, x=0.0):
    h = skin.smooth_hit(np.array([x, 0.5, z]), np.array([0, -1, 0.0]))
    return None if h is None else h[0][1]

def over_path(z, deg0=-80, deg1=80, n=17, yfrac=0.5, lift=0.0, thick=None):
    """Points over the foot at height-position z, from angle deg0 to deg1 around the length axis (0 = straight up); returns P, N (shell-offset)."""
    ty = top_y(z)
    if ty is None: return None
    yc = ty * yfrac
    P, N = [], []
    for d in np.linspace(deg0, deg1, n):
        t = math.radians(d)
        h = skin.smooth_hit(np.array([0, yc, z]), np.array([math.sin(t), math.cos(t), 0]))
        if h is None: continue
        if h[0][1] < SOLE_TOP + 0.004: continue
        P.append(h[0] + h[1] * (thick(h[0][None])[0] + lift if thick else lift)); N.append(h[1])
    return np.array(P), np.array(N)

def back_path(y, deg, n=15, thick=None, lift=0.0, zc=0.0):
    """Round the back of the foot at height y: from the left side (-deg) over the heel (0) to the right side (+deg)."""
    P, N = [], []
    for d in np.linspace(-deg, deg, n):
        t = math.radians(d)
        h = skin.smooth_hit(np.array([0, y, zc]), np.array([math.sin(t), 0, -math.cos(t)]))
        if h is None: continue
        P.append(h[0] + h[1] * ((thick(h[0][None])[0] if thick else 0) + lift)); N.append(h[1])
    return np.array(P), np.array(N)

def front_path(yfn, deg, n=13, thick=None, lift=0.0, zc=0.0):
    P, N = [], []
    for d in np.linspace(-deg, deg, n):
        t = math.radians(d)
        h = skin.smooth_hit(np.array([0, yfn(d), zc]), np.array([math.sin(t), 0, math.cos(t)]))
        if h is None: continue
        P.append(h[0] + h[1] * ((thick(h[0][None])[0] if thick else 0) + lift)); N.append(h[1])
    return np.array(P), np.array(N)

def side_path(sign, zy, lift=0.0, thick=None, yc=None):
    """Points on the side wall (x sign) along the (z, y) polyline `zy`: cast along the x axis from the middle."""
    P, N = [], []
    for z, y in zy:
        h = skin.smooth_hit(np.array([0, y, z]), np.array([sign, 0, 0]))
        if h is None: continue
        P.append(h[0] + h[1] * ((thick(h[0][None])[0] if thick else 0) + lift)); N.append(h[1])
    return np.array(P), np.array(N)

def collar(y, colour, thick, r=0.007, lift=0.0):
    o = outline_at(skin, y, 48, (0.0, 0.0))
    P2, _ = offset2d(o[:, :2], 0.0)
    pts = []
    for x, z in P2:
        d = np.array([x, 0, z]); d = d / max(np.linalg.norm(d), 1e-9)
        h = skin.smooth_hit(np.array([0, y, 0]) + d * 0.0, d) if False else None
        pts.append((x, y, z))
    pts = np.array(pts)
    # push out along the horizontal normal by the shell thickness
    c = pts.mean(0)
    out = pts + normalize((pts - c) * np.array([1, 0, 1])) * (thick(pts)[:, None] + lift)
    return tube(out, r, colour, sides=7, closed=True, caps=False)

PARTS = {}
def shoe(name):
    def deco(fn):
        PARTS[name] = fn
        return fn
    return deco

CLIP = [0.03, 0.19]

def mk_sole(top, flare):
    CLIP[0] = max(CLIP[0], top + 0.003)
    return Sole(skin, top=top, flare=flare, n=36)

def upper_cut(y0=0.026, y1=0.19):
    CLIP[0], CLIP[1] = y0 + 0.004, y1
    c = Cut(skin.V, skin.N, skin.F)
    c.cut(lambda V: V[:, 1] - y0); c.cut(lambda V: y1 - V[:, 1])
    c = c.keep(lambda V: V[:, 1] - y0).keep(lambda V: y1 - V[:, 1])
    return c

def panel_part(field, thick, colour, height=0.004, ramp=0.006, base=None, flag=0, extra=None, fine=False):
    lv = [ramp * k / 3 for k in (1, 2, 3)]
    if base is None:
        base = Cut(skin.V1, skin.N1, skin.F1) if fine else Cut(skin.V, skin.N, skin.F)
        base.cut(lambda V: V[:, 1] - CLIP[0]); base.cut(lambda V: CLIP[1] - V[:, 1])
        base = base.keep(lambda V: V[:, 1] - CLIP[0]).keep(lambda V: CLIP[1] - V[:, 1])
    c = K.panel(skin, field, lv, base=base, fine=fine)
    def raise_fn(V0):
        f = field(V0)
        h = height * K.smooth(0, ramp, f)
        return h if extra is None else h + extra(V0)
    return to_part(c, thick, colour, raise_fn=raise_fn, flag=flag)

# ------------------------------------------------------------------ shared pieces
rng = np.random.default_rng(7)

def piping(c, th, colour, pred, r=0.0065, lift=0.0, sides=6):
    """A tube following the boundary of the cut upper where pred(mid) (a rolled collar / elastic edge)."""
    parts = []
    for loop in K.boundary_loops(c, pred):
        if len(loop) < 6: continue
        loop = loop[::3]
        P = c.V0[loop] + c.N0[loop] * (th(c.V0[loop])[:, None] + lift)
        closed = np.linalg.norm(P[0] - P[-1]) < 0.045 and len(loop) > 10
        parts.append(tube(P, r, colour, sides=sides, closed=closed, caps=not closed))
    return parts

def piping_ring(y, th, colour, lift=0.0, r=0.004, n=28):
    """A thin tube round the boot at height y (the cuff's edge line)."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        h = skin.smooth_hit(np.array([0, y, 0.0]), np.array([math.sin(t), 0, math.cos(t)]))
        if h is None: continue
        pts.append(h[0] + h[1] * (th(h[0][None])[0] + lift))
    return [tube(np.array(pts), r, colour, sides=5, closed=True, caps=False)] if len(pts) > 6 else []

def drop(p, n, size, colour):
    """A raindrop decal: a teardrop of raised triangles on the shell (point up)."""
    n = np.asarray(n) / np.linalg.norm(n)
    up = np.array([0, 1.0, 0]); up = up - n * (up @ n); up /= np.linalg.norm(up); side = np.cross(n, up)
    prof = []
    for k in range(12):
        t = 2 * math.pi * k / 12
        x, y = math.sin(t), -math.cos(t)
        # round bottom, pointed top
        r = 1.0 if y < 0.0 else max(0.0, 1.0 - y) * 0.9 + 0.1 * (1 - y)
        prof.append((x * r * 0.7, y * (1.5 if y > 0 else 1.0)))
    V = [p + n * 0.004 * 1.0 + up * 0.0]
    for x, y in prof: V.append(p + n * 0.0015 + side * x * size + up * y * size)
    V.append(p + n * 0.004)
    # fan from the centre
    F = [(0, 1 + k, 1 + (k + 1) % 12) for k in range(12)]
    part = Part(np.array(V[:13]), F, colour, weld=False)
    fn = np.cross(part.V[part.F[:, 1]] - part.V[part.F[:, 0]], part.V[part.F[:, 2]] - part.V[part.F[:, 0]])
    if (fn @ n).sum() < 0: part.F = part.F[:, ::-1].copy()
    return part

def laces(zs, th, colour, deg=72, half=0.0075, height=0.0035, lift=0.0043, eyelet=None, n=11, yfrac=0.5):
    parts = []
    for z in zs:
        r = over_path(z, -deg, deg, n, thick=th, lift=lift, yfrac=yfrac)
        if r is None or len(r[0]) < 4: continue
        P, N = r
        parts.append(make_ribbon(P, N, half, height, colour))
        if eyelet is not None:
            for k in (0, len(P) - 1):
                parts.append(dome(P[k] + N[k] * 0.002, N[k], half, 0.003, eyelet, sides=6, rings=1))
    return parts

def side_stripes(s_list, zy, th, colour, half=0.010, height=0.0035, lift=0.0):
    parts = []
    for s in s_list:
        P, N = side_path(s, zy, lift=lift, thick=th)
        if len(P) > 2: parts.append(make_ribbon(P, N, half, height, colour))
    return parts

def blob(c3, r3):
    c3 = np.asarray(c3, float); r3 = np.asarray(r3, float)
    return lambda V: (1.0 - np.linalg.norm((V - c3) / r3, axis=1)) * float(np.min(r3))

def spot(point_fn_dir, th, colour, rad, height, ramp=0.004, base=None):
    """A round raised patch on the skin around a point found by a ray (origin, direction)."""
    o, d = point_fn_dir
    h = skin.smooth_hit(np.array(o), np.array(d))
    if h is None: return None
    p, n = h
    return panel_part(blob(p, [rad] * 3), th, colour, height, ramp, base=base)

def star_field(cz, cy, R, r, sign, rot=90.0):
    def f(V):
        dz, dy = V[:, 2] - cz, V[:, 1] - cy
        dist = np.sqrt(dz * dz + dy * dy) + 1e-9
        th = np.degrees(np.arctan2(dy, dz)) - rot
        a = np.abs(((th + 36) % 72) - 36)             # 0 at a tip ... 36 at the inner vertex
        rho = R + (r - R) * (a / 36.0)
        return np.minimum(rho - dist, (sign * V[:, 0] - 0.04) * 0.5)
    return f

def hit_over(z, x=0.0, y0=0.5):
    h = skin.smooth_hit(np.array([x, y0, z]), np.array([0, -1, 0.0]))
    return h

def bow(p, n, colour, knot_colour, size=1.0, lat=(1, 0, 0), th_lift=0.0):
    """A little bow on the skin at p (normal n): two ellipse loops (flattened tubes) and a knot."""
    n = np.asarray(n) / np.linalg.norm(n)
    a = np.asarray(lat, float); a = a - n * (a @ n); a /= np.linalg.norm(a)
    b = np.cross(n, a)
    parts = []
    for sgn in (-1, 1):
        pts = []
        for k in range(18):
            t = 2 * math.pi * k / 18
            l = sgn * 0.034 * size * (1 - math.cos(t)) / 2
            f = 0.020 * size * math.sin(t) * (0.45 + 0.55 * (1 - math.cos(t)) / 2)
            u = 0.006 * size * (1 - math.cos(t)) / 2
            pts.append(p + n * (0.005 * size + u) + a * l + b * f)
        parts.append(tube(np.array(pts), 0.0055 * size, colour, sides=6, closed=True, caps=False, squash=0.65, up=n))
    parts.append(uvsphere(p + n * 0.007 * size, [0.0075 * size] * 3, knot_colour, 8, 6))
    # tails
    for sgn in (-1, 1):
        pts = [p + n * 0.004 * size + a * sgn * 0.004 * size + b * (-0.004 * size), p + n * 0.003 * size + a * sgn * 0.018 * size - b * 0.020 * size,
               p + n * 0.003 * size + a * sgn * 0.026 * size - b * 0.034 * size]
        parts.append(tube(np.array(pts), 0.0045 * size, colour, sides=5, caps=True, squash=0.6, up=n))
    return parts

# ------------------------------------------------------------------ 1. mint sneakers
@shoe("sneakerMint")
def mint():
    mint_c, white, teal, navy = hexc("8fe3c4"), hexc("fbfbf6"), hexc("2fb59a"), hexc("2a3f4f")
    th = lambda V: 0.010 * np.ones(len(V))
    up = upper_cut(0.026, 0.17)
    parts = [to_part(up, th, mint_c)]
    parts += piping(up, th, white, lambda m: m[1] > 0.1, r=0.0075, lift=0.001)
    sole = mk_sole(SOLE_TOP, 0.016)
    parts.append(sole.build([(0, 0.010, navy), (0.010, 0.019, white), (0.019, 0.025, teal), (0.025, SOLE_TOP, white)], ledge_colour=white))
    parts.append(panel_part(lambda V: V[:, 2] - 0.095, th, white, 0.005))
    parts.append(panel_part(lambda V: -0.085 - V[:, 2], th, teal, 0.004))
    parts.append(panel_part(lambda V: np.minimum(0.026 - np.abs(V[:, 0]), np.minimum(V[:, 2] + 0.01, 0.085 - V[:, 2])), th, hexc("c8f5e6"), 0.005))
    parts += laces((0.0, 0.030, 0.060), th, white, eyelet=hexc("8c99a0"))
    for off in (0.0, 0.022):             # a pair of slanted side stripes
        parts += side_stripes((-1, 1), [(z + off * 0.0, 0.038 + (z + 0.07 - off) * 0.55) for z in np.linspace(-0.065 + off, 0.045 + off, 8)], th, teal, half=0.0055, height=0.003)
    return parts

# ------------------------------------------------------------------ 2. sunny sandals
@shoe("sneakerSun")
def sandals():
    sun, cork, tan, white = hexc("ffcf3d"), hexc("f4dcae"), hexc("b9814f"), hexc("fff8e8")
    th = lambda V: 0.004 * np.ones(len(V))
    parts = []
    sole = mk_sole(0.036, 0.017)
    parts.append(sole.build([(0, 0.012, tan), (0.012, 0.036, cork)], ledge_colour=cork, ledge_in=0.05))
    for z, half in ((0.075, 0.021), (-0.075, 0.016)):
        r = over_path(z, -118, 118, 21, thick=th, lift=0.0, yfrac=0.45)
        if r is None: continue
        P, N = r
        parts.append(make_ribbon(P, N, half, 0.009, sun))
        for k in (0, len(P) - 1):
            parts.append(dome(P[k] + N[k] * 0.003, N[k], 0.011, 0.007, white, sides=8, rings=1))
    # a daisy on the toe strap
    h = hit_over(0.075)
    if h is not None:
        p, n = h; p = p + n * (0.004 + 0.007)
        a = np.array([1.0, 0, 0]); a = a - n * (a @ n); a /= np.linalg.norm(a); b = np.cross(n, a)
        for k in range(6):
            t = 2 * math.pi * k / 6
            parts.append(uvsphere(p + (a * math.cos(t) + b * math.sin(t)) * 0.0165 + n * 0.001, [0.0105, 0.0045, 0.0105], white, 8, 5, rot=np.column_stack([a, n, b])))
        parts.append(uvsphere(p + n * 0.004, [0.0085, 0.006, 0.0085], hexc("f4a62a"), 8, 5, rot=np.column_stack([a, n, b])))
    for sx in (-1, 1):             # a thin strap from the toe strap down to the sole at each side of the toes
        pass
    return parts

# ------------------------------------------------------------------ 3. coral clogs
@shoe("sneakerCoral")
def clogs():
    coral, dark, cream, white = hexc("ff7f6b"), hexc("d94f45"), hexc("f6e6cf"), hexc("fff4e6")
    th = lambda V: 0.014 * np.ones(len(V))
    up = upper_cut(0.026, 0.17)
    parts = [to_part(up, th, coral)]
    parts += piping(up, th, dark, lambda m: m[1] > 0.1, r=0.0085, lift=0.0)
    sole = mk_sole(0.038, 0.018)
    parts.append(sole.build([(0, 0.012, dark), (0.012, 0.038, cream)], ledge_colour=cream, ledge_in=0.05))
    parts.append(panel_part(lambda V: V[:, 2] - 0.10, th, hexc("ff9a88"), 0.006, ramp=0.008))       # the rounded bumper
    # perforations (a hex of dark holes on the toe box)
    holes = [(0.0, 0.085), (0.028, 0.085), (-0.028, 0.085), (0.014, 0.060), (-0.014, 0.060), (0.0, 0.035), (0.028, 0.035), (-0.028, 0.035), (0.014, 0.110), (-0.014, 0.110)]
    for x, z in holes:
        h = hit_over(z, x)
        if h is None: continue
        p, n = h
        parts.append(dome(p + n * (th(p[None])[0] - 0.001), n, 0.0075, 0.0015, hexc("7a2a2a"), sides=10, rings=1))
    # heel strap with pivots: a band round the back, riveted at the sides
    r = back_path(0.105, 100, 19, thick=th, lift=0.0)
    if len(r[0]) > 4:
        P, N = r; parts.append(make_ribbon(P, N, 0.013, 0.006, dark))
        for k in (0, len(P) - 1):
            parts.append(dome(P[k] + N[k] * 0.004, N[k], 0.011, 0.006, white, sides=8, rings=1))
    return parts

# ------------------------------------------------------------------ 4. rain boots
@shoe("rainBoots")
def rainboots():
    yel, dyel, navy, white, blue = hexc("ffc81e"), hexc("ffb000"), hexc("27324f"), hexc("fff6d8"), hexc("4aa8ff")
    th = lambda V: 0.012 * np.ones(len(V))
    up = upper_cut(0.026, 0.185)
    parts = [to_part(up, th, yel)]
    sole = mk_sole(SOLE_TOP, 0.015)
    parts.append(sole.build([(0, 0.012, navy), (0.012, SOLE_TOP, yel)], ledge_colour=yel))
    parts.append(panel_part(lambda V: V[:, 2] - 0.11, th, dyel, 0.004, ramp=0.007))
    parts.append(panel_part(lambda V: np.minimum(V[:, 1] - 0.138, 0.185 - V[:, 1]), th, white, 0.008, ramp=0.008))      # the folded cuff
    parts += piping(up, th, white, lambda m: m[1] > 0.1, r=0.0085, lift=0.005)
    parts += piping_ring(0.138, th, navy, lift=0.0075, r=0.0035)
    for s in (-1, 1):                         # raindrops
        for (z, y) in ((-0.03, 0.085), (0.025, 0.07), (-0.075, 0.07)):
            h = skin.smooth_hit(np.array([0, y, z]), np.array([s, 0, 0]))
            if h is None: continue
            p, n = h
            parts.append(drop(p + n * (th(p[None])[0] - 0.001), n, 0.011, blue))
    return parts

# ------------------------------------------------------------------ 5. glitter shoes (mary janes)
@shoe("glitterShoes")
def glitter():
    pink, gold, rose, white = hexc("ff6fb5"), hexc("ffd86b"), hexc("ffa6d4"), hexc("ffffff")
    th = lambda V: 0.010 * np.ones(len(V))
    up = upper_cut(0.026, 0.17)
    parts = [to_part(up, th, pink)]
    parts += piping(up, th, rose, lambda m: m[1] > 0.1, r=0.006, lift=0.001)
    sole = mk_sole(0.030, 0.014)
    parts.append(sole.build([(0, 0.010, hexc("ffe9f4")), (0.010, 0.030, rose)], ledge_colour=rose))
    parts.append(panel_part(lambda V: V[:, 2] - 0.10, th, hexc("ff9ccc"), 0.003))
    # the mary-jane strap and button
    r = over_path(0.035, -112, 112, 21, thick=th, lift=0.0, yfrac=0.45)
    P, N = r
    parts.append(make_ribbon(P, N, 0.011, 0.005, gold))
    parts.append(dome(P[-1] + N[-1] * 0.004, N[-1], 0.011, 0.007, hexc("fff0b0"), sides=8, rings=1))
    parts.append(dome(P[0] + N[0] * 0.004, N[0], 0.011, 0.007, hexc("fff0b0"), sides=8, rings=1))
    # sequins: little four-pointed diamonds all over (they twinkle in the app)
    pts = []
    V0, N0 = skin.V, skin.N
    cand = np.where((V0[:, 1] > 0.045) & (V0[:, 1] < 0.17) & (np.abs(V0[:, 2] - 0.035) > 0.025))[0]
    rng.shuffle(cand)
    chosen = []
    for i in cand:
        if all(np.linalg.norm(V0[i] - V0[j]) > 0.030 for j in chosen): chosen.append(i)
        if len(chosen) >= 44: break
    for k, i in enumerate(chosen):
        col = [gold, white, hexc("ffd0ea")][k % 3]
        parts.append(octa(V0[i] + N0[i] * (th(V0[i][None])[0] - 0.0005), N0[i], 0.0078 + 0.0015 * (k % 3), col, flag=2))
    return parts

# ------------------------------------------------------------------ 6. high-tops
@shoe("hightopRed")
def hightops():
    red, white, black = hexc("e63a3a"), hexc("fffaf0"), hexc("1f1f26")
    th = lambda V: 0.011 * np.ones(len(V))
    up = upper_cut(0.026, 0.195)
    parts = [to_part(up, th, red)]
    parts += piping(up, th, white, lambda m: m[1] > 0.12, r=0.0095, lift=0.0015)
    sole = mk_sole(0.038, 0.018)
    parts.append(sole.build([(0, 0.010, black), (0.010, 0.026, white), (0.026, 0.031, red), (0.031, 0.038, white)], ledge_colour=white, ledge_in=0.04))
    parts.append(panel_part(lambda V: V[:, 2] - 0.09, th, white, 0.006, ramp=0.007))
    parts.append(panel_part(lambda V: np.minimum(0.028 - np.abs(V[:, 0]), np.minimum(V[:, 2] + 0.06, 0.08 - V[:, 2])), th, hexc("fff0e6"), 0.005))
    parts += laces((-0.04, -0.012, 0.016, 0.044, 0.072), th, white, eyelet=hexc("d9d9d9"), half=0.007, height=0.0038, yfrac=0.55)
    for s in (-1, 1):
        parts.append(panel_part(star_field(-0.035, 0.105, 0.030, 0.013, s), th, white, 0.0045, ramp=0.003, fine=True))
    parts.append(panel_part(lambda V: -0.09 - V[:, 2], th, white, 0.004))
    return parts

# ------------------------------------------------------------------ 7. ballet flats
@shoe("balletPink")
def ballet():
    pink, deep, suede, white = hexc("ffb3d1"), hexc("ff86b6"), hexc("e8c9a9"), hexc("fff4f8")
    th = lambda V: 0.008 * np.ones(len(V))
    vamp = lambda V: (0.050 + 0.12 * K.smooth(0.02, 0.085, V[:, 2])) - V[:, 1]       # the opening edge: low at the heel and sides, over the toes up front
    c = Cut(skin.V, skin.N, skin.F)
    CLIP[0], CLIP[1] = 0.024, 0.2
    c.cut(lambda V: V[:, 1] - 0.020); c.cut(vamp)
    up = c.keep(lambda V: V[:, 1] - 0.020).keep(vamp)
    parts = [to_part(up, th, pink)]
    parts += piping(up, th, deep, lambda m: m[1] > 0.04, r=0.0058, lift=0.0)
    sole = mk_sole(0.020, 0.011)
    parts.append(sole.build([(0, 0.008, suede), (0.008, 0.020, pink)], ledge_colour=pink, ledge_in=0.03))
    parts.append(panel_part(lambda V: V[:, 2] - 0.115, th, hexc("ffc6de"), 0.003, ramp=0.006))
    # criss-cross ribbons (from the opening round the ankle) and a bow at the vamp
    h = hit_over(0.075)
    if h is not None:
        p, n = h
        parts += bow(p + n * th(p[None])[0], n, deep, hexc("ff5fa2"), size=1.7, lat=(1, 0, 0))
    return parts

# ------------------------------------------------------------------ 8. frog boots
@shoe("frogBoots")
def frog():
    green, dg, lime, belly = hexc("66d45a"), hexc("2f8f3a"), hexc("d9f27a"), hexc("e8f8a8")
    th = lambda V: 0.012 * np.ones(len(V))
    up = upper_cut(0.026, 0.18)
    parts = [to_part(up, th, green)]
    parts += piping(up, th, dg, lambda m: m[1] > 0.1, r=0.0085, lift=0.002)
    sole = mk_sole(0.034, 0.015)
    parts.append(sole.build([(0, 0.012, dg), (0.012, 0.034, lime)], ledge_colour=lime))
    parts.append(panel_part(lambda V: V[:, 2] - 0.135, th, belly, 0.004, ramp=0.008))                      # pale chin / belly at the front
    # wide smile across the toes (corners up)
    r = front_path(lambda d: 0.052 + 0.03 * (d / 58.0) ** 2, 58, 15, thick=th, lift=0.0)
    if len(r[0]) > 4:
        P, N = r; parts.append(make_ribbon(P, N, 0.0055, 0.004, hexc("1d5c2a")))
    for sx in (-1, 1):                                                                                      # nostril dots
        h = hit_over(0.14, sx * 0.012)
        if h is not None:
            p, n = h; parts.append(dome(p + n * (th(p[None])[0] - 0.001), n, 0.0045, 0.003, hexc("1d5c2a"), sides=6, rings=1))
    # eyes bulging on top of the toes
    for sx in (-1, 1):
        h = hit_over(0.085, sx * 0.05)
        if h is None: continue
        p, n = h
        base = p + n * th(p[None])[0]
        parts.append(uvsphere(base + n * 0.006, [0.026, 0.022, 0.026], green, 10, 7))
        eye = base + n * 0.019
        parts.append(uvsphere(eye + np.array([0, 0, 0.002]), [0.0215, 0.0215, 0.0215], hexc("ffffff"), 10, 7))
        parts.append(uvsphere(eye + np.array([sx * -0.002, 0.003, 0.0165]), [0.0105, 0.0105, 0.0105], hexc("1d1d24"), 8, 6))
        parts.append(uvsphere(eye + np.array([sx * 0.0005, 0.011, 0.0225]), [0.0038] * 3, hexc("ffffff"), 6, 4))
    for (z, y, s) in ((-0.05, 0.10, 1), (-0.05, 0.10, -1), (-0.09, 0.08, 1), (-0.09, 0.08, -1), (0.0, 0.07, 1), (0.0, 0.07, -1)):
        h = skin.smooth_hit(np.array([0, y, z]), np.array([s, 0, 0]))
        if h is None: continue
        p, n = h
        parts.append(dome(p + n * (th(p[None])[0] - 0.001), n, 0.011, 0.004, dg, sides=8, rings=1))
    return parts

# ------------------------------------------------------------------ 9. light-up sneakers
@shoe("sneakerLightup")
def lightup():
    navy, white, grey = hexc("262a4a"), hexc("f4f6ff"), hexc("8e96b8")
    glow = hexc("48eaff")
    th = lambda V: 0.011 * np.ones(len(V))
    up = upper_cut(0.026, 0.17)
    parts = [to_part(up, th, navy)]
    parts += piping(up, th, white, lambda m: m[1] > 0.1, r=0.0085, lift=0.001)
    sole = mk_sole(0.040, 0.018)
    parts.append(sole.build([(0, 0.010, grey), (0.010, 0.020, white), (0.020, 0.028, glow, 1), (0.028, 0.040, white)], ledge_colour=white, ledge_in=0.04))
    parts.append(panel_part(lambda V: V[:, 2] - 0.09, th, white, 0.005, ramp=0.007))
    parts.append(panel_part(lambda V: V[:, 2] - 0.155, th, glow, 0.007, ramp=0.004, flag=1))      # glowing toe tip
    parts += laces((0.0, 0.030, 0.060), th, hexc("c8d0ff"), eyelet=glow)
    for s in (-1, 1):                                                                                  # glowing side bolts
        parts += side_stripes((s,), [(-0.06, 0.04), (-0.02, 0.085), (0.0, 0.06), (0.04, 0.105)], th, glow, half=0.0085, height=0.0035)
    for p in parts[-2:]:
        p.flag = np.full(len(p.V), 1)
    return parts

# ------------------------------------------------------------------ build + preview
def build(name):
    parts = PARTS[name]()
    if "--counts" in argv: print(name, [len(p.V) for p in parts])
    V, F, C, fl, N = K.finish(parts, name, OUT)
    print(name, len(V), "verts", len(F), "tris")
    return V, F, C, fl, N

def preview(results):
    import bpy
    from mathutils import Vector
    scene = bpy.context.scene
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"; sh.color_type = "VERTEX"; sh.show_shadows = False; sh.show_cavity = False
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 640; scene.render.resolution_y = 640
    scene.world = bpy.data.worlds.new("w"); scene.world.color = (0.9, 0.85, 0.8)
    for name, (V, F, C, fl, N) in results.items():
        for o in list(bpy.data.objects): bpy.data.objects.remove(o)
        def addmesh(V, F, C, nm, norms=None):
            me = bpy.data.meshes.new(nm)
            me.from_pydata([tuple(v) for v in V], [], [tuple(f) for f in F])
            me.update()
            ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
            for i, c in enumerate(C): ca.data[i].color = (c[0], c[1], c[2], 1)
            for p in me.polygons: p.use_smooth = True
            if norms is not None: me.normals_split_custom_set_from_vertices([tuple(n) for n in norms])
            ob = bpy.data.objects.new(nm, me); ob.rotation_euler = (math.pi / 2, 0, 0); scene.collection.objects.link(ob); return ob
        addmesh(V, F, C, name, N)
        bean = np.array(BEAN["pos"]); bt = np.array(BEAN["tris"]).reshape(-1, 3)
        addmesh(bean, bt, np.tile(K.srgb(0.55, 0.72, 0.97), (len(bean), 1)), "bean", np.array(BEAN["nrm"]))
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
        views = {"q": (0.55, 0.9, 0.35), "side": (1.0, 0.0, 0.25), "front": (0.3, 1.0, 0.65)}
        conv = lambda v: Vector((v[0], -v[2], v[1]))
        tgt = conv((0, 0.07, 0.02))
        for vn, (dx, dz, el) in views.items():
            d = conv(Vector((dx, el, dz)).normalized())
            cam.location = tgt + d * 1.1
            cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
            cam.data.type = "ORTHO"; cam.data.ortho_scale = 0.55
            scene.render.filepath = "%s/%s_%s.png" % (PREVIEW, name, vn)
            bpy.ops.render.render(write_still=True)

res = {}
for n in PARTS:
    if ONLY and n not in ONLY: continue
    res[n] = build(n)
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    preview(res)
