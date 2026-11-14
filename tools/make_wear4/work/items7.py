"""Batch 4 upgrades of the flat-looking pieces (2026-10-27): racing sashes, jersey bibs, bandanas, tutu, hero cape, pearls, flower lei, coach whistle,
backpack. Same ids / slots / anchors / titles / prices as before; more volume (pillowed bands, rolled hems, piping, raised dots, folds), more detail."""
from kit5 import *
from items2_head import torus, thick_sheet, eloop, hdir, uvsphere, gem, basis_to, phi_of
import items2_other as IO2

NEW = ()

def surf_frame(x, y, off):
    p, n = body_pt(x, y, off)
    xx, yy, z = axes(n)
    return p, xx, yy, z

# ============================ SASH ==========================================
def sash_y(phi):
    """Centre-line height of the closed diagonal sash at azimuth phi (0 = +x right hip, pi/2 = front, pi = -x left shoulder, 3pi/2 = back), a 2-harmonic curve through four
    heights: LOW over the right hip (0.265: under the hanging arm bulb, bottom y~0.31), HIGH over the left shoulder (0.70: above the arm root, top ~0.66), 0.46 on the chest
    (top edge 0.50, under the mouth keep-out) and 0.555 at the back centre line (between Pip's tail-root swell, top 0.544, and his next spike group, 0.574+)."""
    return 0.495 - 0.2175 * math.cos(phi) - 0.0475 * math.sin(phi) - 0.0125 * math.cos(2 * phi)

def sash(field=SKY, trim=CREAM, star=PINK, **k):
    """A full closed diagonal sash (bandolier) worn round the whole body: over the left shoulder above the arm root, across the chest, under the right arm and back
    up across the back. Built on wl.surface_ray so it hugs the skin all the way round (the old one was front-only)."""
    reset(); NA = 56; HW = 0.042
    rows = [(-1.0, 0.010), (-0.86, 0.030), (0.0, 0.037), (0.86, 0.030), (1.0, 0.010)]
    R_ = 0.52
    def path(phi):
        d = 1e-3
        return sash_y(phi), (sash_y(phi + d) - sash_y(phi - d)) / (2 * d)       # (y, dy/dphi)
    def skin(phi, w, off):
        y0, dy = path(phi)
        t = np.array([R_, dy]); t /= np.linalg.norm(t)                          # (arc length, height) direction of the path
        perp = np.array([-t[1], t[0]])                                          # across the band: +w goes up-and-forward
        ph = phi + perp[0] * w * HW / R_; y = y0 + perp[1] * w * HW
        return surface_at(y, ph, off=off)
    cols = [2 * math.pi * i / NA for i in range(NA)]
    def pt(i, j):
        w, off = rows[j]; return skin(cols[i], w, off)[0]
    # the band is a closed ring: columns wrap
    P = []
    for j in range(len(rows)):
        for i in range(NA): P.append(pt(i, j))
    def gcol(i, j):
        w = rows[j][0]
        return mix(deep(trim, 0.1), trim, 0.5) if abs(w) >= 0.85 else mix(deep(field, 0.12), tint(field, 0.12), 0.35 + 0.65 * (1 - abs(w)))
    grid_surface('band', lambda i, j: pt(i, j), NA, len(rows), None, closed_u=True, hint=lambda p: full_n(p), gcol=gcol)
    # stars: three on the chest, laid on the band
    def frame_at(phi, off):
        p, n = skin(phi, 0.0, off)
        y0, dy = path(phi)
        tdir = skin(phi + 0.02, 0.0, off)[0] - skin(phi - 0.02, 0.0, off)[0]
        tdir = tdir - n * np.dot(tdir, n); tdir /= np.linalg.norm(tdir)
        up = np.cross(n, tdir)
        return p, tdir, up, n
    for k_, ph in enumerate((math.radians(62), math.radians(90), math.radians(118))):
        p, xx, yy, nn = frame_at(ph, 0.040)
        if xx[0] < 0: xx, yy = -xx, -yy                                           # screen-right first
        sp = lib.poly_pts_rounded([((0.040 if q % 2 == 0 else 0.019) * math.cos(math.pi / 2 + math.pi * q / 5), (0.040 if q % 2 == 0 else 0.019) * math.sin(math.pi / 2 + math.pi * q / 5)) for q in range(10)], 0.007, arc=1)
        slab_part('star%d' % k_, sp, 0.012, lambda pq, nq: mix(deep(star, 0.1), tint(star, 0.3), 0.5 + 0.5 * nq[2]),
                  lambda px, py, pz, p=p, xx=xx, yy=yy, nn=nn: tuple(p + xx * px + yy * py + nn * (pz - 0.002)), cuts=0, sharp=40)
    # a ruffled rosette at the low end (right hip, front) with two short ribbon tails
    phr = math.radians(22)
    p, xx, yy, nn = frame_at(phr, 0.044)
    Rm = np.stack([xx, nn, -yy], 1).tolist()
    prof = [(0.0, 0.0), (0.056, 0.0), (0.064, 0.010), (0.054, 0.022), (0.038, 0.028), (0.0, 0.030)]
    lathe_y('rosette', prof, 10, lambda q, nq: mix(deep(star, 0.12), tint(star, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p), rotm=Rm, sharp=60)
    lathe_y('rosette2', [(0.0, 0.0), (0.034, 0.0), (0.038, 0.010), (0.026, 0.018), (0.0, 0.020)], 8, lambda q, nq: mix(deep(field, 0.1), tint(field, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p + nn * 0.026), rotm=Rm, sharp=60)
    bead('rbutton', p + nn * 0.050, (0.014, 0.014, 0.011), GOLD, segs=6)
    for s_, dphi in ((1, 0.00), (-1, 0.06)):
        def fn(i, j, s_=s_, dphi=dphi):
            v = j / 4.0; u = i / 2.0 - 0.5
            y = sash_y(phr) - 0.015 - 0.095 * v
            ph = phr + dphi - 0.05 * s_ * v + u * 0.07 * (1 + 0.5 * v)
            pp, nq = surface_at(y, ph, off=0.050 - 0.006 * v); return pp, nq
        thick_sheet('tail%+d' % s_, fn, 3, 5, 0.010, lambda pq, nq: mix(deep(star, 0.1), tint(star, 0.2), 0.5))
    return dict(anchor='chest', slot='body', tags=['sporty', 'sparkly'], price=50, title='Racing sash', ao_flat=True, emit=0.14,
                desc='A full closed diagonal racing sash (0.074 wide) worn round the whole body: over the left shoulder above the arm root (centre y 0.70), across the chest below the mouth (0.46), under the right arm (0.265), and back up across the back (0.50 at the centre line, between Pip\'s spikes). Cream piped edges, three stars on the chest and a ruffled rosette with two ribbon tails at the right hip.')

# ============================ BIB ==========================================
BIB_C = (0.0, 0.355)
def bib(field=CREAM, trim=SKY, **k):
    reset(); segs = 32; hw, hh = 0.20, 0.125
    rings = [(1.0, 0.012, 'trim'), (0.985, 0.030, 'trim'), (0.905, 0.034, 'trim'), (0.9045, 0.030, 'field'), (0.55, 0.0325, 'field'), (0.0, 0.034, 'field')]
    def pt(i, j):
        s, off, _ = rings[j]; a_ = 2 * math.pi * i / segs
        c, sn = math.cos(a_), math.sin(a_)
        x = hw * s * np.sign(c) * abs(c) ** 0.5; y = BIB_C[1] + hh * s * np.sign(sn) * abs(sn) ** 0.5
        p, n = body_pt(x, y, off + 0.004); return p
    grid_surface('plate', pt, segs, len(rings), None, hint=lambda p: full_n(p), gcol=lambda i, j: trim if rings[j][2] == 'trim' else field)
    # a rolled rim tube round the plate edge
    pts = []
    for i in range(48):
        a_ = 2 * math.pi * i / 48; c, sn = math.cos(a_), math.sin(a_)
        x = hw * 0.97 * np.sign(c) * abs(c) ** 0.5; y = BIB_C[1] + hh * 0.97 * np.sign(sn) * abs(sn) ** 0.5
        pts.append(body_pt(x, y, 0.040)[0])
    pts.append(pts[0])
    tube_curve('rim', pts, 0.0095, 6, lambda p, n: mix(deep(trim, 0.16), tint(trim, 0.22), 0.5 + 0.5 * n[1]), cap=False)
    # four safety pins at the corners
    for sx, sy in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        p, xx, yy, nn = surf_frame(sx * 0.178, BIB_C[1] + sy * 0.100, 0.046)
        ico_part('pin%+d%+d' % (sx, sy), tuple(p), (0.014, 0.014, 0.010), SILVER, sub=1, rot=np.stack([xx, yy, nn], 1).tolist())
        tube_curve('pinbar%+d%+d' % (sx, sy), [p - xx * 0.020, p + xx * 0.020], 0.0042, 5, SILVER, cap=True)
    nc, nn = body_pt(0.0, BIB_C[1], 0.034 + 0.004)
    return dict(anchor='chest', slot='body', tags=['sporty'], price=20, title='Jersey bib (number plate)',
                desc='A raised, rounded number plate with a rolled rim and four silver safety pins, pinned to the belly in the team colour. Digits are separate meshes placed on number_anchor.',
                number_anchor_rest=[round(float(v), 4) for v in nc], number_height=0.18, number_normal=[round(float(v), 4) for v in nn], plate_half_size=[hw, hh])

# ============================ BANDANA ======================================
def bandana(main=CORAL, dots=CREAM, trim=CREAM, **k):
    reset()
    yc = 0.505; X0 = 0.46
    torus('band', 36, lambda phi: [eloop(neck_y(phi, yc, yc, 0.55), phi, h, v) for h, v in ((0.020, 0.024), (0.034, 0.018), (0.040, 0.0), (0.034, -0.018), (0.020, -0.024))], lambda p, n: mix(deep(main, 0.12), tint(main, 0.16), 0.5 + 0.5 * n[1] * 0.6), sharp=60)
    nu, nv = 9, 7; y_top = yc - 0.012; y_tip = 0.270; hw = 0.215
    def tri(i, j):
        v = j / (nv - 1); u = (i / (nu - 1)) * 2 - 1
        y = y_tip + (y_top - y_tip) * v; w = hw * v
        x = u * w
        ripple = 0.007 * math.sin(5.0 * v + 3.0 * u) * v
        p, n = body_pt(x, y, 0.040 + 0.014 * math.sin(math.pi * (1 - abs(u)) * 0.5) * v + ripple); return p, n
    thick_sheet('cloth', tri, nu, nv, 0.012, lambda p, n: mix(deep(main, 0.08), tint(main, 0.14), 0.5 + 0.5 * n[1] * 0.5))
    for s_ in (-1, 1):                                 # rolled hems along the two long edges
        pp = []
        for v in np.linspace(0, 1, 9):
            y = y_tip + (y_top - y_tip) * v; x = s_ * hw * v * 0.98
            pp.append(body_pt(x, y, 0.048)[0])
        tube_curve('hem%+d' % s_, pp, 0.0100, 6, lambda p, n: mix(deep(trim, 0.1), tint(trim, 0.2), 0.5 + 0.5 * n[1]), cap=True)
    for k_, (x, y) in enumerate(((0.0, 0.440), (-0.075, 0.415), (0.075, 0.415), (0.0, 0.365), (-0.038, 0.322), (0.038, 0.322), (0.128, 0.468), (-0.128, 0.468), (0.040, 0.470), (-0.040, 0.470))):
        p, xx, yy, nn = surf_frame(x, y, 0.056)
        ico_part('pd%d' % k_, tuple(p), (0.021, 0.021, 0.011), dots, sub=1, rot=np.stack([xx, yy, nn], 1).tolist())
    p, xx, yy, nn = surf_frame(0.30, yc, 0.066)
    ico_part('knot', tuple(p), (0.056, 0.050, 0.046), lambda q, nq: mix(deep(main, 0.14), tint(main, 0.14), 0.5 + 0.5 * nq[2]), sub=2, rot=np.stack([xx, yy, nn], 1).tolist())
    for s_ in (-1, 1):
        def fn(i, j, s_=s_):
            v = j / 3.0; u = i / 2.0 - 0.5
            q = np.array([0.30 + s_ * 0.025 + u * 0.030 + s_ * 0.030 * v, yc - 0.020 - 0.085 * v])
            return body_pt(q[0], q[1], 0.062 - 0.008 * v)
        thick_sheet('end%+d' % s_, fn, 3, 4, 0.010, lambda pq, nq: mix(deep(main, 0.1), tint(main, 0.2), 0.5))
    return dict(anchor='neck', slot='neck', tags=['cool', 'sporty'], price=25, title='Bandana',
                desc='A neckerchief: a plumped rolled band across the belly at y~0.505 (top <=0.54), big side knots, and a thick polka-dot triangle with rolled cream hems hanging to y 0.27. All below the mouth keep-out.')

# ============================ TUTU =========================================
def _ring_mesh(name, rows, close_i, colfn, close_k=True, cap_ends=True):
    """A tube-like grid: rows[i][k] = point k of cross-section i. close_i: sections wrap round (a ring); otherwise the two end sections are capped.
    The cross-section is always closed. Faces point outward (signed volume check). colfn(i, k, p) -> rgb."""
    NI = len(rows); NK = len(rows[0]); P = []; C = []
    for i in range(NI):
        for k in range(NK): P.append(tuple(rows[i][k])); C.append(colfn(i, k, np.array(rows[i][k])))
    F = []
    for i in range(NI if close_i else NI - 1):
        i2 = (i + 1) % NI
        for k in range(NK):
            k2 = (k + 1) % NK
            a, b, c, d = i * NK + k, i2 * NK + k, i2 * NK + k2, i * NK + k2
            F += [(a, b, c), (a, c, d)]
    if not close_i and cap_ends:
        for ring, rev in ((0, True), (NI - 1, False)):
            ctr = np.mean([rows[ring][k] for k in range(NK)], 0); ci = len(P); P.append(tuple(ctr)); C.append(colfn(ring, 0, ctr))
            for k in range(NK):
                k2 = (k + 1) % NK; a, b = ring * NK + k, ring * NK + k2
                F.append((ci, b, a) if rev else (ci, a, b))
    Pn = np.array(P); vol = sum(np.dot(Pn[a], np.cross(Pn[b], Pn[c])) for a, b, c in F)
    if vol < 0: F = [(a, c, b) for a, b, c in F]
    return add_part(name, P, F, C, flip_auto=False)

def _fold_layer(name, inner, hem, colfn, close_i):
    """A thin double-sided tulle layer: a top surface and an underside (0.006 lower) that SHARE the hem vertices, so the edge is one rounded rim (no slab, no coplanar sheets).
    inner / hem: per-column points of the top surface edges."""
    N = len(inner); P = []; C = []
    for i in range(N): P.append(tuple(inner[i])); C.append(colfn(i, 0))
    for i in range(N): P.append(tuple(hem[i])); C.append(colfn(i, 1))
    for i in range(N): P.append(tuple(np.array(inner[i]) - np.array([0, 0.009, 0]))); C.append(colfn(i, 2))
    Ft = []; Fb = []
    for i in range(N if close_i else N - 1):
        i2 = (i + 1) % N
        a, b, c, d = i, i2, N + i2, N + i
        Ft += [(a, b, c), (a, c, d)]
        a, b, c, d = 2 * N + i, 2 * N + i2, N + i2, N + i
        Fb += [(a, c, b), (a, d, c)]
    Pn = np.array(P)
    n0 = np.cross(Pn[Ft[0][1]] - Pn[Ft[0][0]], Pn[Ft[0][2]] - Pn[Ft[0][0]])
    if n0[1] < 0: Ft = [(a, c, b) for a, b, c in Ft]; Fb = [(a, c, b) for a, b, c in Fb]
    return add_part(name, P, Ft + Fb, C, flip_auto=False)

def tutu(pink=PINK, lav=LAV, band=None, pip=False, yb=0.32, **k):
    """Ballet tutu: a snug waistband on the body at height yb and three thin tulle layers that leave it and flare OUT AND DOWN (28 / 38 / 48 degrees below horizontal),
    each with a scalloped hem (16 soft waves, staggered per layer), 80 columns, a slightly different pink per layer, and a small bow on the front.
    Hems end at y ~0.13 on the chest (the shoes show under it) and ~0.06 at the hips / back. Budget: <=1000 vertices / <=1300 triangles (WearMeshes), so the layers are single cones folded on a shared rim, not slabs.
    pip=True: open over Pip's tail root (a slot +-40 deg round the back centre)."""
    reset()
    band = band or deep(pink, 0.22)
    p0, p1 = (math.radians(310.0), math.radians(590.0)) if pip else (0.0, 2 * math.pi)
    def phis(n):
        return [p0 + (p1 - p0) * (i / (n - 1 if pip else n)) for i in range(n)]
    # the BASE band is open over the very back (+-22 deg, hidden under the tulle): on Pip his tail swings through that stretch (WearBandTests 'inside a limb' 0.1445 vs 0.14)
    b0, b1 = (p0, p1) if pip else (1.5 * math.pi + 0.385, 3.5 * math.pi - 0.385)
    def bphis(n): return [b0 + (b1 - b0) * i / (n - 1) for i in range(n)]
    # --- waistband: a rounded ring hugging the egg
    hin = lambda phi: 0.010 + 0.016 * math.cos(phi) ** 2            # stand-off of the band's inner edge: 1 cm at the front / back (Pip's tail), 2.6 cm at the hips (the skin bulges there in a lean)
    def sec_at(phi):
        h0 = hin(phi); return [(h0, 0.020), (h0 + 0.022, 0.022), (h0 + 0.022, -0.022), (h0, -0.020)]
    NB = 22 if pip else 26
    dip = max(0.0, yb - 0.252)                                       # the band (top +0.026) dips to y 0.252 at the hips so it passes UNDER the hanging arm bulbs (bottom y~0.31) and their blend into the body
    bdip = max(0.0, yb - 0.245)                                       # ... and 0.245 at the back centre: lower on the back keeps the band off the root of Pip's tail (the tail swell tops out at y 0.54)
    yl = lambda phi: yb - dip * math.cos(phi) ** 2 - bdip * max(0.0, -math.sin(phi)) ** 2
    rows = [[eloop(yl(ph), ph, h, v) for h, v in sec_at(ph)] for ph in bphis(NB)]
    _ring_mesh('waistband', rows, False, lambda i, k, p: mix(deep(band, 0.10), tint(band, 0.28), 0.5 + 0.5 * (sec_at(0.0)[k][1] / 0.026) * 0.7))
    # --- tulle layers: (colour, attach dy, angle below horizontal, reach, hem wave phase)
    LAY = [(mix(tint(pink, 0.55), CREAM, 0.30), 0.004, 28.0, 0.120, 0.0), (tint(pink, 0.22), -0.008, 38.0, 0.140, 1.0), (mix(pink, lav, 0.38), -0.020, 48.0, 0.150, 2.0)]
    NC = 62 if pip else 80
    for li, (c, dy, ang, reach, ph) in enumerate(LAY):
        inner = []; hem = []
        cols = phis(NC)
        for phi in cols:
            e = B.egg_point(yl(phi) + dy, phi); h = hdir(e)
            s = math.sqrt(math.sin(8 * phi + 0.5 * ph * math.pi) ** 2 + 0.06) / math.sqrt(1.06)      # ~0.2 at the cusps (hem lifts, blunt: no needle tips edge-on), 1 mid-scallop
            L = reach * (1 - 0.09 * (1 - s))
            inner.append(e + h * (hin(phi) + 0.012))
            hem.append(e + h * (hin(phi) + 0.012 + L) + np.array([0, -L * math.tan(math.radians(ang)) + 0.020 * (1 - s), 0]))
        def cf(i, k, c=c):
            return deep(c, 0.18) if k == 0 else (tint(c, 0.14) if k == 1 else deep(c, 0.10))
        _fold_layer('layer%d' % li, inner, hem, cf, not pip)
    # --- a small neat bow on the front of the band
    p, n = surface_at(yb + 0.034, math.pi / 2, off=0.044)
    xx, yy, nn = axes(n); Rm = np.stack([xx, yy, nn], 1)
    for s_ in (-1, 1):
        bead('bow%+d' % s_, p + xx * s_ * 0.044 + nn * 0.002, (0.050, 0.027, 0.018), lambda q, nq: mix(deep(pink, 0.26), tint(pink, 0.12), 0.5 + 0.5 * nq[2]), rot=Rm, segs=6)
    bead('bowknot', p + nn * 0.008, (0.021, 0.021, 0.017), deep(pink, 0.34), segs=6)
    return dict(anchor='waist', slot='body', tags=['cute', 'sweet', 'sparkly'], price=60, title='Ballet tutu',
                desc='A fluffy ballet tutu: a snug waistband at y %.2f with three thin tulle layers flaring out and down (28 / 38 / 48 degrees below horizontal, reach 0.12 / 0.14 / 0.15), 16 staggered scalloped waves per hem, a small bow on the front. Pip\'s variant is open over his tail root.' % yb)

# ============================ CAPE =========================================
def cape(main=None, lining=HONEY, trim=CREAM, pip=False, **k):
    """pip=True: two half-capes with a slot between them over Pip's tail root (the tail leaves the lower back at y~0.47)."""
    main = main or IO2.RED
    reset(); nv = 7
    y_top = 0.68; y_bot = 0.16
    panels = [(200.0, 238.0, 6), (302.0, 340.0, 6)] if pip else [(200.0, 340.0, 13)]
    def col(p, nn):
        r = np.array([p[0], 0, p[2]]); outer = float(np.dot(np.array([nn[0], nn[1], nn[2]]), r)) > 0
        c = main if outer else lining
        if p[1] < 0.225: c = trim if outer else tint(lining, 0.2)
        s = math.sin(5.0 * math.atan2(p[2], p[0]) * 2.0)
        return mix(c, deep(c, 0.18), 0.22 * max(0.0, s))
    def surf(u, v, a0, a1):
        phi = math.radians(a0 + (a1 - a0) * u)
        fold = 0.018 * math.sin(math.pi * (u * (1 if pip else 5.0) + 0.6)) * v ** 1.2
        y = y_top + (y_bot - y_top) * v - 0.030 * v ** 3 * math.cos(math.pi * (u * 4)) - 0.012 * v * abs(math.sin(math.pi * u * 2.5))
        off = 0.040 + 0.215 * v ** 1.5 + fold
        base = B.egg_point(y, phi); h = hdir(base); p = base + h * off
        n = h + np.array([0, 0.15 * v, 0]); return p, n
    for pi_, (a0, a1, nu) in enumerate(panels):
        thick_sheet('panel%d' % pi_, lambda i, j, a0=a0, a1=a1, nu=nu: surf(i / (nu - 1), j / (nv - 1), a0, a1), nu, nv, 0.024, col)
    pts = []
    for i in range(12):
        phi = math.radians(200 + 140 * i / 11); base = B.egg_point(y_top + 0.004, phi); pts.append(base + hdir(base) * 0.046)
    tube_curve('collar', pts, 0.036, 6, lambda p, nn: mix(deep(trim, 0.10), tint(trim, 0.1), 0.5 + 0.5 * nn[1]), cap=True, flat=0.9)
    edges = [panels[0][0], panels[0][1]] + ([panels[1][0], panels[1][1]] if pip else [])
    for ph in edges:
        pp = []
        for v in np.linspace(0.02, 0.98, 7):
            y = y_top + (y_bot - y_top) * v - 0.030 * v ** 3
            base = B.egg_point(y, math.radians(ph)); pp.append(base + hdir(base) * (0.040 + 0.215 * v ** 1.5 + 0.008))
        tube_curve('edge%d' % int(ph), pp, 0.0095, 4, lambda p, nn: mix(deep(trim, 0.1), tint(trim, 0.15), 0.5 + 0.5 * nn[1]), cap=True)
    for ph in (340, 200):
        base = B.egg_point(y_top + 0.004, math.radians(ph)); c = base + hdir(base) * 0.064
        bead('clasp%d' % ph, c, (0.044, 0.044, 0.036), lambda p, nn: mix(deep(HONEY, 0.12), tint(HONEY, 0.2), 0.5 + 0.5 * nn[1]), segs=8)
    sp = star_poly(0.115, 0.050, 5, rad=0.012)
    yst = 0.43; vst = (y_top - yst) / (y_top - y_bot)
    if pip:      # the emblem moves onto the left half (the centre back is the tail slot)
        ph = math.radians(219.0)
        base = B.egg_point(yst, ph); h = hdir(base); cen = base + h * (0.040 + 0.215 * vst ** 1.5 + 0.022)
        tx = np.array([-h[2], 0, h[0]])
        slab_part('emblem', sp, 0.020, lambda p, nn: mix(deep(HONEY, 0.1), tint(HONEY, 0.25), 0.5 + 0.5 * nn[2]), lambda px, py, pz: tuple(cen + tx * px * 0.8 + np.array([0, py, 0]) + h * pz), cuts=0, sharp=40)
    else:
        zst = -(float(B.halfDepth((yst - B.lift) / B.bodyH)) + 0.040 + 0.215 * vst ** 1.5 + 0.022)
        slab_part('emblem', sp, 0.020, lambda p, nn: mix(deep(HONEY, 0.1), tint(HONEY, 0.25), 0.5 + 0.5 * nn[2]), lambda px, py, pz: (px, yst + py, zst - pz), cuts=0, sharp=40)
    return dict(anchor='back', slot='body', tags=['cool', 'sparkly', 'cute'], price=70, title='Hero cape',
                desc='A fuller hero cape (honey lining, cream trim) with pleated folds, a thick rolled collar, trimmed edges, gold clasps and a puffy star emblem; hem y~0.16. Nothing on the front. Pip\'s variant is split into two halves over his tail root.')

# ============================ PEARLS =======================================
def pearls(pearl=hx('#FBF4EC'), clasp=HONEY, **k):
    reset()
    pcol = lambda q, n_v: mix(deep(pearl, 0.12), tint(pearl, 0.14), 0.5 + 0.5 * n_v[1])
    def swag(x0, ytop, depth, n_, rad, name):
        def pxy(t):
            x = -x0 + 2 * x0 * t; return x, ytop - depth * (1 - (x / x0) ** 2)
        ts = np.linspace(0, 1, 400); xy = np.array([pxy(t) for t in ts])
        seg = np.linalg.norm(np.diff(xy, axis=0), axis=1); L = np.concatenate([[0], np.cumsum(seg)])
        for k_ in range(n_):
            d = L[-1] * (k_ + 0.5) / n_; i = int(np.searchsorted(L, d)); x, y = xy[min(i, len(xy) - 1)]
            p, nn = body_pt(x, y, 0.042)
            bead('%s%d' % (name, k_), p, (rad, rad, rad), pcol, segs=8)
    swag(0.34, 0.520, 0.110, 9, 0.0470, 'pearl')
    swag(0.30, 0.545, 0.072, 7, 0.036, 'inner')
    for s_ in (-1, 1):
        p, nn = body_pt(s_ * 0.345, 0.520, 0.044)
        bead('spacer%+d' % s_, p, (0.022, 0.030, 0.022), clasp, segs=6)
    p, nn = body_pt(0.0, 0.378, 0.060); xx, yy, z = axes(nn)
    bead('drop', p, (0.046, 0.058, 0.040), lambda q, n_v: mix(deep(hx('#E98AA4'), 0.1), tint(hx('#E98AA4'), 0.25), 0.5 + 0.5 * n_v[1]), rot=np.stack([xx, yy, z], 1), segs=8)
    bead('cap', p + yy * 0.062, (0.026, 0.018, 0.020), clasp, rot=np.stack([xx, yy, z], 1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'sweet', 'cute'], price=65, title='Pearl necklace',
                desc='A two-strand pearl necklace: nine big pearls on the long swag down to a pink drop in a gold cap at y~0.38, and a shorter strand of seven above it, with gold spacer beads at the shoulders. Lowest points on the centre line, below the mouth keep-out.')

# ============================ LEI ==========================================
def lei(cols=None, leaf=MINT, **k):
    reset(); cols = cols or [CORAL, PINK, HONEY, LAV, CORAL, PINK, HONEY, LAV]
    NF = len(cols)
    def ring_y(phi):
        s = max(0.0, math.sin(phi)); return 0.462 - 0.062 * s ** 2 + pip_rise(phi, 0.462)
    pts = []
    for i in range(37):
        phi = 2 * math.pi * i / 36; e = B.egg_point(ring_y(phi), phi); pts.append(e + hdir(e) * 0.040)
    tube_curve('string', pts, 0.024, 4, lambda p, n: mix(deep(leaf, 0.2), tint(leaf, 0.2), 0.5 + 0.5 * n[1]), cap=False)
    lobes = []
    for q in range(10):
        a = 2 * math.pi * q / 10
        r = 0.080 if q % 2 == 0 else 0.042
        lobes.append((r * math.cos(a), r * math.sin(a)))
    petals = [(x_, y_) for x_, y_ in lobes][::-1]
    for i, c in enumerate(cols):
        phi = math.pi / 2 + 2 * math.pi * (i - NF / 2 + 0.5) / NF
        e = B.egg_point(ring_y(phi), phi); n = egg_n(e); x, y, nn = axes(n); ctr = e + hdir(e) * 0.060
        slab_part('f%d' % i, petals, 0.020, lambda p, nn_, c=c: mix(deep(c, 0.10), tint(c, 0.28), 0.5 + 0.5 * nn_[2]), lambda px, py, pz, ctr=ctr, x=x, y=y, nn=nn: tuple(ctr + x * px + y * py + nn * (pz - 0.004)), cuts=0, sharp=45)
        bead('c%d' % i, ctr + nn * 0.020, (0.026, 0.026, 0.018), HONEY if c != HONEY else CORAL, rot=np.stack([x, y, nn], 1), segs=6)
        phl = phi + math.pi / NF; e2 = B.egg_point(ring_y(phl), phl); n2 = egg_n(e2); x2, y2, nn2 = axes(n2)
        bead('l%d' % i, e2 + hdir(e2) * 0.050, (0.064, 0.030, 0.016), lambda p, nn_: mix(deep(leaf, 0.2), tint(leaf, 0.2), 0.5 + 0.5 * nn_[2]), rot=np.stack([x2, y2, nn2], 1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['sweet', 'cute', 'sparkly'], price=45, title='Flower lei',
                desc='A fuller flower lei: ten big five-lobe blooms with domed centres and leaves on a thick green cord circling the belly, dipping to a V at the front (y~0.40; nothing above 0.51).')

# ============================ WHISTLE ======================================
def whistle(strap=SKY, metal=hx('#C9D3DC'), mouth=CORAL, **k):
    reset()
    scol = lambda p, n: mix(deep(strap, 0.14), tint(strap, 0.2), 0.5 + 0.5 * n[1])
    for s in (-1, 1):
        pts = []
        for v in np.linspace(0, 1, 11):
            x = s * (0.30 * (1 - v) + 0.012 * v); y = 0.515 + (0.446 - 0.515) * v - 0.008 * math.sin(math.pi * v)
            pts.append(body_pt(x, y, 0.040)[0])
        tube_curve('strap%+d' % s, pts, 0.026, 8, scol, cap=True, flat=0.75)
    ring = []
    c, cn = body_pt(0.0, 0.440, 0.060)
    for a in np.linspace(0, 2 * math.pi, 15): ring.append(c + np.array([0.028 * math.cos(a), 0.034 * math.sin(a), 0.0]))
    tube_curve('ring', ring, 0.011, 6, deep(metal, 0.2), cap=False)
    wc, wn = body_pt(0.0, 0.350, 0.080)
    mcol = lambda p, nn: mix(deep(metal, 0.12), tint(metal, 0.32), 0.5 + 0.5 * nn[1])
    ico_part('chamber', tuple(wc), (0.088, 0.078, 0.070), mcol, sub=2)
    ico_part('cap', tuple(wc + np.array([0, 0.070, 0])), (0.040, 0.018, 0.034), deep(metal, 0.18), sub=1)
    lathe_y('mouthpiece', [(0.0, 0.0), (0.046, 0.0), (0.044, 0.140), (0.0, 0.142)], 12, lambda p, nn: mix(deep(mouth, 0.1), tint(mouth, 0.2), 0.5 + 0.5 * nn[1]), centre=tuple(wc + np.array([0.054, 0.0, 0.002])), rotm=np.array(rot_z(-math.pi / 2)).tolist(), sharp=70)
    ico_part('hole', tuple(wc + np.array([0.0, 0.024, 0.062])), (0.030, 0.013, 0.012), INK, sub=1)
    ico_part('shine', tuple(wc + np.array([-0.026, 0.022, 0.034])), (0.016, 0.010, 0.008), tint(metal, 0.7), sub=1)
    return dict(anchor='neck', slot='neck', tags=['sporty', 'cool'], price=30, title='Coach whistle',
                desc='A coach whistle on a thick rounded sky lanyard in a V from the shoulders to a ring at (0,0.44); a big silver whistle with a coral mouthpiece hangs to y~0.31. All below the mouth keep-out.')

# ============================ BACKPACK =====================================
def pillow(name, phic, yc, hphi, hy, D, color, off0=0.010, nu=12, nv=12, colfn=None, rim=0.6):
    """A rounded pillow lying ON the back (or any all-round skin patch): footprint hphi (rad of egg azimuth) by hy (m) round (phic, yc), standing off the skin by
    off0 at its rim and off0 + D at the middle, with a steep rounded wall. One open, single-sided mesh (its underside is against the body, never seen)."""
    def fn(i, j):
        u = 2.0 * i / (nu - 1) - 1.0; v = 2.0 * j / (nv - 1) - 1.0
        # square -> rounded square (rim) : blend the square with the disc map
        uu = u * (1 - rim + rim * math.sqrt(max(0.0, 1 - v * v / 2))); vv = v * (1 - rim + rim * math.sqrt(max(0.0, 1 - u * u / 2)))
        r2 = max(abs(u), abs(v))
        d = D * math.sqrt(max(0.0, 1 - r2 ** 5)) if r2 < 1 else 0.0
        return surface_at(yc + vv * hy, phic + uu * hphi, off=off0 + d)[0]
    return grid_surface(name, fn, nu, nv, color, closed_u=False, hint=lambda p: full_n(p), gcol=colfn)

def _snap(p, off):
    """Project a point onto the whole-body skin and stand it `off` off it along the SDF gradient (3 Newton steps): keeps a strap on the skin across the groove between the chest and an arm."""
    p = np.array(p, float)
    for _ in range(4):
        d = float(B.sdf_pts(p)); g = B.grad(p); p = p - g * (d - off)
    return p

def backpack(main=SKY, flap=CORAL, strap=None, pip=False, **k):
    """A backpack seated on the upper-middle back, rim 4 mm off the skin, pillowed 10 cm out (taller body, flap, front pocket, two side pockets, buckle, top handle), on two thin
    shoulder straps that each loop an arm root and stay within ~1.3 cm of the skin all the way: over the top of the arm root (y 0.70), down just in front of it, under the arm bulb (y 0.26)
    and back into the pack. pip=True: the same pack at 0.78 scale high enough (centre y 0.74) to clear the root of Pip's tail (top 0.544); the spikes it covers hide by the existing rule."""
    reset(); strap = strap or deep(main, 0.28)
    BK = 1.5 * math.pi
    sc = 0.78 if pip else 1.0
    yc = 0.74 if pip else 0.56
    hp, hy = 0.46 * sc, 0.25 * sc
    pillow('pack', BK, yc, hp, hy, 0.105 * sc, None, off0=0.004, nu=14, nv=14, colfn=lambda i, j: mix(deep(main, 0.14), tint(main, 0.18), 0.5 + 0.5 * math.sin(math.pi * j / 13)))
    pillow('flap', BK, yc + 0.145 * sc, hp * 1.02, 0.108 * sc, 0.122 * sc, None, off0=0.004, nu=12, nv=6, colfn=lambda i, j: mix(deep(flap, 0.12), tint(flap, 0.18), 0.4 + 0.6 * math.sin(math.pi * j / 5)))
    pillow('pocket', BK, yc - 0.125 * sc, hp * 0.70, 0.088 * sc, 0.138 * sc, None, off0=0.004, nu=10, nv=6, colfn=lambda i, j: mix(deep(flap, 0.20), tint(flap, 0.10), 0.5 + 0.5 * math.sin(math.pi * j / 5)))
    for s_ in (-1, 1):
        pillow('side%+d' % s_, BK + s_ * hp * 1.12, yc - 0.10 * sc, 0.09 * sc, 0.10 * sc, 0.085 * sc, None, off0=0.004, nu=6, nv=6, rim=0.8, colfn=lambda i, j: mix(deep(flap, 0.22), tint(flap, 0.08), 0.5))
    pb, nb = surface_at(yc + 0.035 * sc, BK, off=0.160 * sc)
    bead('buckle', pb, (0.040 * sc, 0.030 * sc, 0.016), GOLD, rot=np.stack(axes(nb), 1), segs=6)
    hpts = [surface_at(yc + hy - 0.01 + 0.07 * sc * math.sin(math.pi * t), BK + (t - 0.5) * 0.32 * sc, off=0.100 * sc + 0.012 * math.sin(math.pi * t))[0] for t in np.linspace(0, 1, 9)]
    tube_curve('handle', hpts, 0.014 * sc, 5, strap, cap=True)
    # straps: closed loop on the skin round each arm root (right arm: azimuth PC - PR .. PC + PR; the left strap is the mirror image)
    NS = 56; HW = 0.022; R_ = 0.52
    PC, PR = -0.33, 0.93                 # back end -1.26 (inside the pack), front end +0.60 (z 0.29: just in front of the arm bulb)
    YC, RU, RD = ((0.52, 0.18, 0.26) if pip else (0.495, 0.205, 0.235))
    rows = [(-1.0, 0.004), (0.0, 0.012), (1.0, 0.004)]
    def loop(th):
        yy = YC + (RU if math.sin(th) > 0 else RD) * math.sin(th)
        return PC + PR * math.cos(th), yy
    for s in (1, -1):
        def spt(i, j, s=s):
            th = 2 * math.pi * i / NS; d = 1e-3
            p0 = loop(th - d); p1 = loop(th + d)
            t = np.array([R_ * (p1[0] - p0[0]), p1[1] - p0[1]]); t /= np.linalg.norm(t); perp = np.array([-t[1], t[0]])
            ph, y = loop(th); w, off = rows[j]
            phh = ph + perp[0] * w * HW / R_; yy = y + perp[1] * w * HW
            phh = phh if s > 0 else math.pi - phh
            return _snap(surface_at(yy, phh, off=off)[0], off)
        grid_surface('strap%+d' % s, spt, NS, len(rows), None, closed_u=True, hint=lambda p: full_n(p),
                     gcol=lambda i, j: deep(strap, 0.22) if abs(rows[j][0]) > 0.9 else mix(deep(strap, 0.08), tint(strap, 0.16), 0.6))
    return dict(anchor='back', slot='body', tags=['cute', 'sporty'], price=50, title='Little backpack', variant='backpack_sky_pip' if pip else None,
                desc='A backpack seated on the upper-middle back (0.46 rad wide, 0.50 tall, rim 4 mm off the skin, pillowed to ~10 cm) with a flap, a front pocket, two side pockets, a buckle and a top handle, on two thin shoulder straps that each loop an arm root snug to the skin: over the top (y 0.70), down just in front, under the arm bulb (y 0.26) and into the pack.')

REG = [
    ('sash_pink', sash, dict(field=PINK, star=SKY), BIB_ANCHOR),
    ('sash_sky', sash, dict(), BIB_ANCHOR),
    ('bib_pink', bib, dict(field=CREAM, trim=PINK), BIB_ANCHOR),
    ('bib_sky', bib, dict(), BIB_ANCHOR),
    ('bandana_coral', bandana, dict(main=CORAL), NECK_ANCHOR),
    ('bandana_mint', bandana, dict(main=MINT), NECK_ANCHOR),
    ('tutu_pink', tutu, dict(), WAIST_ANCHOR),
    ('cape_hero', cape, dict(), BACK_ANCHOR),
    ('lei', lei, dict(), NECK_ANCHOR),
    ('backpack_sky', backpack, dict(), BACK_ANCHOR),
]
VARIANTS = [('backpack_sky_pip', backpack, dict(pip=True), BACK_ANCHOR), ('cape_hero_pip', cape, dict(pip=True), BACK_ANCHOR), ('tutu_pink_pip', tutu, dict(pip=True), WAIST_ANCHOR)]
