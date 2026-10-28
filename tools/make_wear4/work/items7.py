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
def sash(field=SKY, trim=CREAM, star=PINK, **k):
    reset(); nL = 11; W_ = 0.074
    a = np.array([-0.42, 0.600]); b = np.array([0.33, 0.255])
    d = (b - a) / np.linalg.norm(b - a); perp = np.array([-d[1], d[0]])
    rows = [(-1.0, 0.012), (-0.90, 0.024), (-0.5, 0.036), (0.0, 0.042), (0.5, 0.036), (0.90, 0.024), (1.0, 0.012)]
    def pt(i, j):
        t = i / (nL - 1); w, off = rows[j]
        taper = 1.0 - 0.55 * (abs(2 * t - 1) ** 6)
        q = a + (b - a) * t + perp * W_ * w * taper
        p, n = body_pt(q[0], q[1], off * (0.4 + 0.6 * taper)); return p
    grid_surface('band', pt, nL, len(rows), None, closed_u=False, hint=lambda p: full_n(p),
                 gcol=lambda i, j: mix(deep(trim, 0.1), trim, 0.5) if abs(rows[j][0]) >= 0.89 else mix(deep(field, 0.12), tint(field, 0.12), 0.35 + 0.65 * (1 - abs(rows[j][0]))))
    # raised piping along both edges
    for s in (-1, 1):
        pts = []
        for t in np.linspace(0.03, 0.97, 12):
            taper = 1.0 - 0.55 * (abs(2 * t - 1) ** 6)
            q = a + (b - a) * t + perp * W_ * 0.93 * s * taper
            pts.append(body_pt(q[0], q[1], 0.040)[0])
        tube_curve('pipe%+d' % s, pts, 0.0085, 4, lambda p, n: mix(deep(trim, 0.12), tint(trim, 0.2), 0.5 + 0.5 * n[1]), cap=True)
    ang = math.atan2(d[1], d[0])
    for k_, t in enumerate((0.22, 0.5, 0.78)):
        q = a + (b - a) * t
        p, xx, yy, nn = surf_frame(q[0], q[1], 0.046)
        sp = star_poly(0.040, 0.019, 5, rad=0.007)
        slab_part('star%d' % k_, sp, 0.014, lambda pq, nq: mix(deep(star, 0.1), tint(star, 0.3), 0.5 + 0.5 * nq[2]),
                  lambda px, py, pz, p=p, xx=xx, yy=yy, nn=nn: tuple(p + xx * (px * math.cos(ang) - py * math.sin(ang)) + yy * (px * math.sin(ang) + py * math.cos(ang)) + nn * (pz - 0.004)), cuts=0, sharp=40)
    # a ruffled rosette at the low end with two short ribbon tails
    p, xx, yy, nn = surf_frame(0.305, 0.262, 0.052)
    Rm = np.stack([xx, nn, -yy], 1).tolist()
    prof = [(0.0, 0.0), (0.062, 0.0), (0.072, 0.010), (0.062, 0.022), (0.044, 0.028), (0.0, 0.030)]
    lathe_y('rosette', prof, 12, lambda q, nq: mix(deep(star, 0.12), tint(star, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p), rotm=Rm, sharp=60)
    lathe_y('rosette2', [(0.0, 0.0), (0.040, 0.0), (0.044, 0.010), (0.030, 0.018), (0.0, 0.020)], 10, lambda q, nq: mix(deep(field, 0.1), tint(field, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p + nn * 0.026), rotm=Rm, sharp=60)
    bead('rbutton', p + nn * 0.052, (0.016, 0.016, 0.012), GOLD, segs=6)
    for s_, dx in ((1, 0.020), (-1, -0.026)):
        def fn(i, j, s_=s_, dx=dx):
            v = j / 5.0; u = i / 2.0 - 0.5
            q = np.array([0.305 + dx + u * 0.040 * (1 + 0.5 * v) + s_ * 0.012 * v, 0.248 - 0.100 * v])
            pp, nq = body_pt(q[0], q[1], 0.050 - 0.006 * v); return pp, nq
        thick_sheet('tail%+d' % s_, fn, 3, 6, 0.010, lambda pq, nq: mix(deep(star, 0.1), tint(star, 0.2), 0.5))
    return dict(anchor='chest', slot='body', tags=['sporty', 'sparkly'], price=50, title='Racing sash',
                desc='A pillowed diagonal racing sash (0.15 wide, 0.04 tall) with cream piping, three puffy stars and a ruffled rosette with two ribbon tails at the low end. Ends stop at |x|=0.42; whole sash below the mouth keep-out.')

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
def tutu(pink=PINK, lav=LAV, band=None, pip=False, **k):
    """pip=True: open over Pip's tail root (a slot +-40 deg round the back centre): the layers are open sweeps instead of closed rings."""
    reset(); yb = 0.255
    band = band or deep(pink, 0.22)
    p0, p1 = (math.radians(310.0), math.radians(590.0)) if pip else (0.0, 2 * math.pi)
    NS = 18 if pip else 24
    def sweep_ring(name, loopfn, colfn, K):
        if not pip:
            torus(name, NS, lambda phi: loopfn(phi), colfn, sharp=70); return
        def pt(i, j):
            return loopfn(p0 + (p1 - p0) * j / (NS - 1))[i]
        grid_surface(name, pt, K, NS, None, closed_u=True, hint=lambda p: np.array([p[0], 0.2, p[2]]), gcol=lambda i, j: colfn(np.array([0, 0.2, 0]), np.array([0, 0.5, 0])))
    sweep_ring('waistband', lambda phi: [eloop(yb, phi, h, v) for h, v in ((0.012, 0.030), (0.044, 0.026), (0.050, 0.0), (0.044, -0.026), (0.012, -0.030))], lambda p, n: mix(deep(band, 0.1), tint(band, 0.25), 0.5 + 0.5 * n[1] * 0.6), 5)
    LAY = [(mix(tint(pink, 0.40), CREAM, 0.10), 0.125, 0.0, 0.0), (tint(lav, 0.22), 0.205, -0.045, 1.0), (tint(pink, 0.30), 0.285, -0.090, 2.0)]
    for li, (c, hem, dy, ph) in enumerate(LAY):
        def lf(phi, c=c, hem=hem, dy=dy, ph=ph):
            rf = 1 + 0.07 * math.cos(8 * phi + ph)
            sag = 0.026 * (0.5 + 0.5 * math.cos(8 * phi + ph + 1.0))
            out = []
            for t in (0.0, 0.5, 1.0):
                h = 0.040 + (hem * rf - 0.040) * t
                y = yb + 0.034 + dy * t + 0.040 * t - 0.056 * t * t - sag * t ** 3
                out.append(eloop(y + 0.022, phi, h, 0.0))
            for t in (1.0, 0.5, 0.0):
                h = 0.040 + (hem * rf - 0.040) * t
                y = yb + 0.034 + dy * t + 0.040 * t - 0.056 * t * t - sag * t ** 3
                out.append(eloop(y - 0.014, phi, h, 0.0))
            return out
        sweep_ring('layer%d' % li, lf, lambda p, n, c=c: mix(deep(c, 0.14), tint(c, 0.18), min(1.0, max(0.0, (0.30 - p[1]) / 0.22) * 0.8 + 0.2 * (0.5 + 0.5 * n[1]))), 6)
    p, xx, yy, nn = surf_frame(0.0, yb, 0.064)
    Rm = np.stack([xx, yy, nn], 1)
    for s_ in (-1, 1):
        bead('bow%+d' % s_, p + xx * s_ * 0.050 + nn * 0.004, (0.058, 0.032, 0.022), lambda q, nq: mix(deep(pink, 0.28), tint(pink, 0.1), 0.5 + 0.5 * nq[2]), rot=Rm, segs=6)
    bead('bowknot', p + nn * 0.012, (0.026, 0.026, 0.022), deep(pink, 0.32), segs=6)
    return dict(anchor='waist', slot='body', tags=['cute', 'sweet', 'sparkly'], price=60, title='Ballet tutu',
                desc='A fuller three-layer ruffled tulle tutu (thick edged layers with scalloped hems, perkier and shorter than before) on a puffy waistband with a satin bow at the front. Layers all y<=0.29; clear of arms and feet. Pip\'s variant is open over his tail root.')

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
def backpack(main=SKY, flap=CORAL, strap=None, pip=False, **k):
    reset(); strap = strap or deep(main, 0.28)
    zc = -0.625
    F = 0.50 if pip else 1.0                      # the Pip variant: a smaller pack high between the shoulder blades, above his tail root
    Y0 = 1.15 if pip else 0.55
    if pip: zc = -(float(B.halfDepth((Y0 - B.lift) / B.bodyH)) + 0.10)
    IO2.sellip('pack', (0, Y0, zc), (0.225 * F, 0.255 * F, 0.125 * F), 0.5, lambda p, n: mix(deep(main, 0.12), tint(main, 0.15), 0.5 + 0.5 * n[1] * 0.6), nu=14, nv=7)
    IO2.sellip('flap', (0, Y0 + 0.125 * F, zc - 0.006 * F), (0.232 * F, 0.110 * F, 0.134 * F), 0.5, lambda p, n: mix(deep(flap, 0.12), tint(flap, 0.15), 0.5 + 0.5 * n[1] * 0.6), nu=14, nv=5)
    IO2.sellip('pocket', (0, Y0 - 0.095 * F, zc - 0.116 * F), (0.150 * F, 0.088 * F, 0.056 * F), 0.5, lambda p, n: mix(deep(flap, 0.18), tint(flap, 0.1), 0.5 + 0.5 * n[1] * 0.5), nu=10, nv=5)
    # side bottle pockets
    for s in (-1, 1):
        IO2.sellip('side%+d' % s, (s * 0.200 * F, Y0 - 0.080 * F, zc + 0.01 * F), (0.050 * F, 0.100 * F, 0.070 * F), 0.55, lambda p, n: mix(deep(flap, 0.2), tint(flap, 0.1), 0.5 + 0.5 * n[1] * 0.5), nu=8, nv=5)
    bead('buckle', (0, Y0 + 0.035 * F, zc - 0.142 * F), (0.040 * F, 0.030 * F, 0.016 * F), GOLD, segs=6)
    tube_curve('handle', [(-0.06 * F, Y0 + 0.27 * F, zc), (-0.06 * F, Y0 + 0.33 * F, zc), (0.06 * F, Y0 + 0.33 * F, zc), (0.06 * F, Y0 + 0.27 * F, zc)], 0.016 * F, 6, strap, cap=True)
    for s in (1, -1):
        spec = [(0.58, 282, 0.040), (0.64, 298, 0.042), (0.690, 318, 0.046), (0.715, 336, 0.050), (0.712, 346, 0.054), (0.700, 353, 0.058)]
        Pc = []
        for y, ph, off in spec:
            phi = math.radians(ph); phi = phi if s > 0 else math.pi - phi
            p = B.egg_point(y, phi); Pc.append(p + hdir(p) * off)
        tg = [(Pc[min(j + 1, len(Pc) - 1)] - Pc[max(j - 1, 0)]) for j in range(len(Pc))]
        def fn(i, j, Pc=Pc, tg=tg):
            u = i / 2 - 0.5; c = Pc[j]; t = tg[j] / np.linalg.norm(tg[j]); n = hdir(c)
            ac = np.cross(n, t); ac /= np.linalg.norm(ac); return c + ac * u * 0.085, n
        thick_sheet('strap%+d' % s, fn, 3, len(Pc), 0.030, lambda p, nn: mix(deep(strap, 0.05), tint(strap, 0.14), 0.5 + 0.5 * nn[1] * 0.5))
    return dict(anchor='back', slot='body', tags=['cute', 'sporty'], price=50, title='Little backpack', variant='backpack_sky_pip' if pip else None,
                desc='A rounded backpack on the back (pack centre y 0.42, z -0.585) with a flap, a zipped front pocket, two side bottle pockets, a buckle and a top handle, on padded shoulder straps that end tucked behind the arm roots.')

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
