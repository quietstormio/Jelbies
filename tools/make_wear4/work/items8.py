"""Batch 4 neck loops (2026-10-27): every neck piece is one continuous loop round the body at the neck line (dipping at the front below the mouth,
rising at the back over Pip's tail root and between Lavender's wings): gold chain, silk scarf, pearls, whistle lanyard, cosy scarves, bow-tie band,
and the new Diamond J chain."""
from kit5 import *
from items5 import circle_poly
import items3
import items_other as IO

NEW = ('diamond_j',)

def loop_tube(name, front, off, rad, sides, col, n=36, side=0.50, back=0.56, flat=1.0, radfn=None):
    pts = [ring_pt(2 * math.pi * i / n, front, off, side, back) for i in range(n + 1)]
    tube_curve(name, pts, rad, sides, col, cap=False, flat=flat, radfn=radfn)

def loop_beads(prefix, n, front, off, radii, col, side=0.50, back=0.56, segs=6, phase=0.5, flat_link=True):
    for k in range(n):
        phi = 2 * math.pi * (k + phase) / n
        p, t, h, up = ring_frame(phi, front, off, side, back)
        bead('%s%d' % (prefix, k), p, radii, col, rot=np.stack([t, h, up], 1), segs=segs)

# ============================ GOLD CHAIN (chunky Cuban links, full loop) =======
def chain_gold(gold=hx('#FFC41F'), **k):
    reset()
    def gcol(p, n):
        w = max(0.0, n[1] * 0.55 + n[2] * 0.45)
        return mix((0.80, 0.46, 0.02), mix((1.0, 0.84, 0.18), (1.0, 0.97, 0.62), 0.55), 0.18 + 0.82 * w ** 1.1)      # saturated gold (no brown ink mix); the shader adds the polish
    FR = 0.43
    n = 26                                   # truly interlocking oval links: alternately flat on the body and on edge, each threaded through its neighbours
    for k_ in range(n):
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.046)
        if k_ % 2 == 0: X, Y, N = t, up, h        # flat link: lies against the body
        else: X, Y, N = t, h, up                   # link on edge
        ring_loop('link%d' % k_, p, X, Y, N, circle_poly(1.0, 10, 0.098, 0.046), lambda px, py: 0.040, 0.020, gcol, n=10, e=2.2, sides=4)
    p, t, h, up = ring_frame(math.pi / 2, FR, 0.058)
    Rm = np.stack([t, h, -up], 1).tolist()
    pc = p - up * 0.120
    lathe_y('coin', [(0.0, -0.020), (0.100, -0.020), (0.118, -0.008), (0.118, 0.014), (0.100, 0.026), (0.0, 0.026)], 14, lambda q, nq: mix((0.85, 0.52, 0.03), mix((1.0, 0.86, 0.2), (1.0, 0.97, 0.62), 0.5), 0.5 + 0.5 * nq[1]), centre=tuple(pc), rotm=Rm, sharp=45)
    sp = star_poly(0.060, 0.028, 5, rad=0.007)
    slab_part('star', sp, 0.008, lambda q, nq: (1.0, 0.93, 0.5), lambda px, py, pz: tuple(pc + t * px + up * py + h * (0.026 + pz)), cuts=0)
    ring_loop('bail', p - up * 0.040, t, h, up, circle_poly(1.0, 12, 0.030, 0.048), lambda px, py: 0.020, 0.010, gcol, n=12, e=2.2, sides=5)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly'], price=70, title='Gold chain',
                desc='A chunky Cuban-link gold chain: twenty-six real oval rings, alternately flat and on edge so each is threaded through its neighbours, high-polish gold, in one continuous loop round the body at the neck line, with a big coin pendant on a ring bail at the front (y~0.31). Its own budget (2800 vertices / 3000 triangles).')

# ============================ SILK SCARF (full loop, knot, tails) ==============
def scarf_silk(base=hx('#2F3E6B'), ring=hx('#E8B84A'), dot=hx('#F4E9D6'), **k):
    reset()
    def pat(p, n):
        u = p[0] * 6.0 + p[1] * 2.0
        v = p[1] * 6.0 - p[0] * 2.0
        fu = u - math.floor(u) - 0.5
        fv = v - math.floor(v) - 0.5
        r = math.hypot(fu, fv)
        c = base
        if 0.26 < r < 0.38: c = ring
        elif r < 0.12: c = dot
        return mix(deep(c, 0.06), tint(c, 0.16), 0.5 + 0.5 * n[1] * 0.5)
    FR = 0.462
    def lf(phi):
        y = neck_y(phi, FR, 0.47, 0.54)
        return [eloop(y, phi, h, v) for h, v in ((0.014, 0.060), (0.052, 0.048), (0.076, 0.0), (0.052, -0.048), (0.014, -0.060))]
    torus('wrap', 32, lf, pat, sharp=60)
    kc, kn = body_pt(0.0, FR - 0.052, 0.112)
    xx, yy, nn = axes(kn)
    bead('knot', kc, (0.120, 0.078, 0.088), lambda p, n: mix(deep(base, 0.10), tint(base, 0.2), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=8)
    for s_ in (-1, 1):
        bead('ear%+d' % s_, kc + xx * (s_ * 0.105) + yy * 0.018 + nn * 0.004, (0.062, 0.070, 0.058), lambda p, n: mix(deep(base, 0.14), tint(base, 0.18), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=6)
    def tail(cx0, cx1, y0, y1, w, name, off, wav):
        nu, nv = 4, 6
        def fn(i, j):
            v = j / (nv - 1); u = i / (nu - 1) - 0.5
            cx = cx0 + (cx1 - cx0) * v + 0.016 * math.sin(4.0 * v + wav)
            y = y0 + (y1 - y0) * v
            ww = w * (1 + 0.65 * v)
            return body_pt(cx + u * ww, y, off + 0.010 * math.sin(3.0 * v + wav) * v)
        thick_sheet(name, fn, nu, nv, 0.012, lambda p, n: pat(p, n))
    tail(-0.040, -0.150, 0.430, 0.150, 0.115, 'tail_a', 0.096, 0.0)
    tail(0.040, 0.120, 0.430, 0.175, 0.105, 'tail_b', 0.100, 1.7)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly', 'sweet'], price=55, title='Silk scarf',
                desc='A silk neckerchief in navy printed with gold medallions: a thick rolled wrap in one continuous loop round the belly (y~0.46, rising at the back), a fat knot with two folded ends at the front centre (top y 0.52) and two flowing tails of fuller fabric.')

# ============================ PEARLS (full loop) ===============================
def pearls(pearl=hx('#FBF4EC'), clasp=HONEY, **k):
    reset()
    pcol = lambda q, n_v: mix(deep(pearl, 0.12), tint(pearl, 0.14), 0.5 + 0.5 * n_v[1])
    FR = 0.405
    loop_tube('string', FR, 0.040, 0.011, 4, deep(pearl, 0.25), n=32)
    n = 19
    for k_ in range(n):
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.042)
        bead('pearl%d' % k_, p, (0.046, 0.046, 0.046), pcol, segs=6)
    p, t, h, up = ring_frame(math.pi / 2, FR, 0.060)
    pd = p - up * 0.070
    bead('drop', pd, (0.046, 0.058, 0.040), lambda q, n_v: mix(deep(hx('#E98AA4'), 0.1), tint(hx('#E98AA4'), 0.25), 0.5 + 0.5 * n_v[1]), rot=np.stack([t, up, h], 1), segs=8)
    bead('cap', pd + up * 0.062, (0.026, 0.018, 0.020), clasp, rot=np.stack([t, up, h], 1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'sweet', 'cute'], price=65, title='Pearl necklace',
                desc='A pearl necklace in one continuous loop round the body at the neck line (nineteen big pearls on a thread), dipping to a pink drop in a gold cap at the front (y~0.34) and rising at the back. Below the mouth keep-out.')

# ============================ WHISTLE (lanyard loop) ===========================
def whistle(strap=SKY, metal=hx('#C9D3DC'), mouth=CORAL, **k):
    reset()
    scol = lambda p, n: mix(deep(strap, 0.14), tint(strap, 0.2), 0.5 + 0.5 * n[1])
    FR = 0.445
    loop_tube('strap', FR, 0.040, 0.024, 5, scol, n=40, flat=0.8)
    c, t, h, up = ring_frame(math.pi / 2, FR, 0.056)
    ring = [c - up * 0.020 + t * (0.028 * math.cos(a)) + up * (0.034 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 11)]
    tube_curve('ring', ring, 0.011, 5, deep(metal, 0.2), cap=False)
    wc = c - up * 0.110 + h * 0.020
    mcol = lambda p, nn: mix(deep(metal, 0.12), tint(metal, 0.32), 0.5 + 0.5 * nn[1])
    bead('chamber', wc, (0.088, 0.078, 0.070), mcol, segs=8)
    bead('cap', wc + up * 0.070, (0.040, 0.018, 0.034), deep(metal, 0.18), segs=6)
    lathe_y('mouthpiece', [(0.0, 0.0), (0.046, 0.0), (0.044, 0.140), (0.0, 0.142)], 10, lambda p, nn: mix(deep(mouth, 0.1), tint(mouth, 0.2), 0.5 + 0.5 * nn[1]), centre=tuple(wc + np.array([0.054, 0.0, 0.002])), rotm=np.array(rot_z(-math.pi / 2)).tolist(), sharp=70)
    bead('hole', wc + np.array([0.0, 0.024, 0.062]), (0.030, 0.013, 0.012), INK, segs=6)
    return dict(anchor='neck', slot='neck', tags=['sporty', 'cool'], price=30, title='Coach whistle',
                desc='A coach whistle on a thick rounded sky lanyard in one continuous loop round the body at the neck line, dipping to a ring at the front (y~0.44) with a big silver whistle and coral mouthpiece hanging to y~0.31; the loop rises at the back. Below the mouth keep-out.')

# ============================ COSY SCARVES + BOW TIE (full loops) ==============
def bow_tie_band(main=PINK, **k):
    meta = IO.bow_tie(main=main, **k)
    FR = 0.470
    torus('band', 28, lambda phi: [eloop(neck_y(phi, FR, 0.472, 0.54), phi, h, v) for h, v in ((0.018, 0.016), (0.034, 0.012), (0.038, 0.0), (0.034, -0.012), (0.018, -0.016))], lambda p, n: mix(deep(main, 0.2), tint(main, 0.2), 0.5 + 0.5 * n[1]), sharp=60)
    meta['desc'] += ' A slim band of the same colour continues round the sides and the back so the bow sits on a continuous loop.'
    return meta

# ============================ DIAMOND J CHAIN ==================================
def l2s(x):
    """Inverse of lib.lin: the sRGB-ish number that export() turns into the LINEAR value x (used to smuggle pave grid coordinates through the colour)."""
    return x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055

PLAT_BEZEL = (0.62, 0.68, 0.78)        # sRGB; linear r stays under 0.42 so the shader's gem mask (smoothstep .42-.55 on linear r) reads it as metal
PLAT_BRIGHT = (0.80, 0.85, 0.94)

def brilliant_stone(name, c, rb, frame):
    """A low-profile round brilliant in a bezel: one revolved part (10 sides, 4 rings + the table centre, smooth normals).
    Ring 0 / 1 = the platinum bezel wall + lip (metal in the shader), ring 2 = the girdle, 3 = the crown, then the table centre. The star-facet look is vertex colour
    (alternating bright / icy sectors on the girdle and crown) + the shader's quantised-normal fire."""
    t, h, up = frame
    prof = [(rb, 0.0), (rb * 0.97, 0.20 * rb), (rb * 0.84, 0.31 * rb), (rb * 0.52, 0.53 * rb), (0.0, 0.64 * rb)]
    def col(p, n):
        d = np.array(p) - np.array(c)
        x, y, z = float(np.dot(d, t)), float(np.dot(d, h)), float(np.dot(d, up))
        yy = y / rb
        if yy < 0.25: return PLAT_BEZEL
        sec = int(round(math.atan2(z, x) / (math.pi / 5))) % 10
        alt = sec % 2
        r = math.hypot(x, z) / rb
        ice, white = (0.68, 0.84, 1.0), (0.97, 0.99, 1.0)
        if r > 0.70: return ice if alt else white                   # girdle
        if r > 0.2: return white if alt else ice                    # crown, shifted half a facet
        return (0.97, 0.99, 1.0)                                    # table
    return lathe_y(name, prof, 10, col, centre=tuple(c), rotm=np.stack([t, h, up], 1).tolist(), sharp=88)

def _proj_st(q, path):
    """(arc length s, signed lateral n) of the 2D point q against the polyline `path`."""
    P0 = np.array(path[0], float); P1 = np.array(path[1], float); Pn = np.array(path[-1], float); Pm = np.array(path[-2], float)
    e0 = (P0 - P1) / np.linalg.norm(P0 - P1); e1 = (Pn - Pm) / np.linalg.norm(Pn - Pm)
    pre = 0.15
    path = [tuple(P0 + e0 * pre)] + list(path) + [tuple(Pn + e1 * 0.15)]        # extend the ends so the round caps keep a running cell grid
    best = None; acc = -pre
    for i in range(len(path) - 1):
        a = np.array(path[i]); b = np.array(path[i + 1]); d = b - a; L = float(np.linalg.norm(d)); d /= L
        u = float(np.clip(np.dot(q - a, d), 0, L)); pt = a + d * u
        dist = float(np.linalg.norm(q - pt))
        if best is None or dist < best[0]:
            nn = float(d[0] * (q[1] - pt[1]) - d[1] * (q[0] - pt[0]))
            best = (dist, acc + u, nn)
        acc += L
    return best[1], best[2]

def stroke_outline(path, w, cap_n=6):
    """Outline (CCW) of a round-capped stroke along a 2D polyline: the right side forward, the end cap round the front from right to left, the left side
    back, the start cap round the back (kit5.stroke_poly's caps run the wrong way round, which pinches horns out of the ends)."""
    P = [np.array(p, float) for p in path]; n = len(P)
    L, R, T = [], [], []
    for i in range(n):
        t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]; t /= np.linalg.norm(t); T.append(t)
        o = np.array([-t[1], t[0]]); L.append(P[i] + o * w / 2); R.append(P[i] - o * w / 2)
    def cap(c, t, a0):
        o = np.array([-t[1], t[0]])
        return [c + (o * math.sin(a0 + math.pi * k / cap_n) + t * math.cos(a0 + math.pi * k / cap_n)) * w / 2 for k in range(1, cap_n)]
    return [tuple(q) for q in R + cap(P[-1], T[-1], -math.pi / 2) + L[::-1] + cap(P[0], -T[0], -math.pi / 2)]

def bevelled_slab(name, path, nrows, base_off, T1, T2, T3, cell, bev, lip, edge_wall_n=0.25):
    """A bold J stroke as ONE open mesh wrapped on the front of the body (the back is never seen): ring A (back, z 0) -> B (wall top, z T1) -> C (bevel, T2)
    -> D (the raised pave face, T3), polished rounded edge normals, the top face D triangulated flat. The D face carries the PAVE GRID in its vertex colour
    (rg = cell coordinates along / across the stroke, b = 2 marks pave; the shader draws a clean grid of little stones there)."""
    from mathutils.geometry import tessellate_polygon
    from mathutils import Vector as V3
    wD = nrows * cell
    w = wD + 2 * (bev + lip)
    rings2 = [stroke_outline(path, w), stroke_outline(path, w), stroke_outline(path, w - 2 * bev), stroke_outline(path, wD)]
    zs = [0.0, T1, T2, T3]
    n = len(rings2[0])
    area = sum(rings2[0][i][0] * rings2[0][(i + 1) % n][1] - rings2[0][(i + 1) % n][0] * rings2[0][i][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0
    def outward(poly, i):
        a = np.array(poly[i - 1]); b = np.array(poly[i]); c = np.array(poly[(i + 1) % len(poly)])
        e1 = b - a; e2 = c - b
        n1 = np.array([e1[1], -e1[0]]) / (np.linalg.norm(e1) + 1e-12); n2 = np.array([e2[1], -e2[0]]) / (np.linalg.norm(e2) + 1e-12)
        o = (n1 + n2); o = o / (np.linalg.norm(o) + 1e-12)
        return o * sgn
    P = []; N = []; C = []
    ring_n = [(1.0, 0.0), (0.80, 0.60), (0.40, 0.92), (0.0, 1.0)]          # soft rounded edge
    for k in range(4):
        for i in range(n):
            q = np.array(rings2[k][i])
            p0 = B.front_surface(q[0], q[1]); nz_ = full_n(p0); nz_ = nz_ / np.linalg.norm(nz_)
            upv = np.array([0, 1.0, 0]) - nz_ * nz_[1]; upv /= np.linalg.norm(upv)
            tv = np.cross(upv, nz_)
            P.append(p0 + nz_ * (base_off + zs[k]))
            o = outward(rings2[k], i)
            oc, zc = ring_n[k]
            nv = (tv * o[0] + upv * o[1]) * oc + nz_ * zc
            N.append(nv / np.linalg.norm(nv))
            s_, n_ = _proj_st(q, path)
            u = s_ / cell + 50.0; v = n_ / cell + nrows / 2.0 + 50.0
            flag = 2.0 if k == 3 else 0.5
            C.append((l2s(u), l2s(v), l2s(flag)))
    F = []
    for k in range(3):
        for i in range(n):
            j = (i + 1) % n
            a, b_, c, d = k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i
            F += [(a, b_, c), (a, c, d)]
    tri = tessellate_polygon([[V3((x, y, 0)) for x, y in rings2[3]]])
    for t3 in tri: F.append(tuple(3 * n + int(i) for i in t3))
    # the winding is irrelevant (the loader trusts the vertex normals) but keep it consistent anyway
    return add_part(name, P, F, C, N=np.array(N), flip_auto=False)

def diamond_j(**k):
    reset()
    FR = 0.470
    OFF = 0.034
    # ---- the chain: ONE continuous row of round brilliants in touching platinum bezels, equal arc spacing, a stone at the front centre
    ph = np.linspace(math.pi / 2, math.pi / 2 + 2 * math.pi, 721)
    pts = np.array([ring_pt(a, FR, OFF) for a in ph])
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1); cum = np.concatenate([[0], np.cumsum(seg)]); Ltot = cum[-1]
    N_ST = int(round(Ltot / 0.098))
    spacing = Ltot / N_ST
    rb = 0.5 * spacing * 1.05
    print('DIAMOND chain length %.3f stones %d spacing %.4f bezel r %.4f' % (Ltot, N_ST, spacing, rb))
    for k_ in range(N_ST):
        phi = float(np.interp(spacing * k_, cum, ph))
        p, t, h, up = ring_frame(phi, FR, OFF)
        brilliant_stone('gem%02d' % k_, p, rb, (t, h, up))
    # ---- the J: a classic capital J (stem on the right, round bowl curving left, hook tip at ~40 % of the height, slim serif bar mostly left of the stem),
    # stroke ~21 % of the height, shallow soft-edged body with a thin polished rim round the pave face. Absolute rest coordinates, wrapped on the belly.
    H = 0.25; yTop = 0.408
    c_ = 0.0185; bev, lip = 0.006, 0.006
    w_ = 2 * c_ + 2 * (bev + lip)                        # 0.061
    R = 0.052; stem_x = 0.056
    cy = yTop - H + R + w_ / 2
    y0 = yTop - w_ / 2
    path = [(stem_x, y0 + (cy - y0) * i / 4) for i in range(4)]
    cx = stem_x - R
    sweep = math.radians(200)
    for k_ in range(0, 13):
        a_ = -sweep * k_ / 12
        path.append((cx + R * math.cos(a_), cy + R * math.sin(a_)))
    bevelled_slab('jbody', path, 2, 0.030, 0.016, 0.024, 0.030, c_, bev, lip)
    wb = 1 * c_ + 2 * (bev + lip)
    yb = yTop - wb / 2
    bevelled_slab('jbar', [(stem_x - 0.110, yb), (stem_x + 0.024, yb)], 1, 0.030, 0.019, 0.027, 0.034, c_, bev, lip)
    # the bail: a bright ring through the front stone, carrying the J
    p, t, h, up = ring_frame(math.pi / 2, FR, OFF)
    bc = p - up * 0.026 + h * 0.020
    bp = []
    for a in np.linspace(0, 2 * math.pi, 11):
        bp.append(bc + up * (0.026 * math.cos(a)) + t * (0.013 * math.sin(a)))
    tube_curve('bail', bp, 0.0075, 5, lambda q, nq: PLAT_BRIGHT, cap=False)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'cool'], price=450, title='Diamond J chain',
                desc='An iced-out tennis chain: one continuous row of round brilliant-cut stones (low domes, star-faceted by vertex colour, shader fire) in touching platinum bezels in one loop round the body at the neck line, with a bold rounded J pendant on a bail at the front centre (below the mouth keep-out): a thick bevelled mirror-platinum body with a raised pave face (a clean grid of small stones drawn by the gem shader, material 8). Parts: gemNN stones (material 6), jbody + jbar (8), bail (7). The stones and the J twinkle (Swift adds the glints). The hero item: budget 2200 vertices.')

nat_of = {'scarf': 0.466, 'lei': 0.462}

def pipify(fn, rad=0.045):
    """The Pip variant of a neck loop: the same piece at the SAME height, with one small smooth bump where it crosses his back centre line to thread a gap
    between two real back spikes (kit5.pip_rise / pip_back_y read art/pip_geometry.json). `rad` = the cord's thickness there."""
    def f(**kw):
        import kit5
        kit5.PIP_MODE = True; kit5.PIP_RAD = rad
        try:
            meta = fn(**kw)
            kit5.tail_over()
            return meta
        finally:
            kit5.PIP_MODE = False
    return f

import items4
REG = [
    ('chain_gold', chain_gold, dict(), NECK_ANCHOR),
    ('scarf_silk', scarf_silk, dict(), NECK_ANCHOR),
    ('pearls', pearls, dict(), NECK_ANCHOR),
    ('whistle_coach', whistle, dict(), NECK_ANCHOR),
    ('bowtie_pink', bow_tie_band, dict(main=PINK), NECK_ANCHOR),
    ('bowtie_sky', bow_tie_band, dict(main=SKY), NECK_ANCHOR),
    ('diamond_j', diamond_j, dict(), NECK_ANCHOR),
    ('scarf_cosy', items3.scarf, dict(), NECK_ANCHOR),
    ('cowboy_hat', items4.cowboy_hat, dict(), H),
    ('hair_bow', items4.hair_bow, dict(), H),
    ('scarf_sky', items3.scarf, dict(a=SKY, b=CREAM), NECK_ANCHOR),
]

import items7
# Pip neck variants are gone: the loops keep their natural height; a covered spike hides (FeatureCompat.coveredSpikes). tail_over (kit5) was tried and dropped:
# pushing the sparse tube vertices out of the tail sphere stretches them into sheets.
VARIANTS = []
