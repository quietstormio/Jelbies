"""Garment redesign concept round (2026-11-14): hoodie, raincoat, cardigan, puffer vest, hero cape as REAL garments (offline Blender previews only).
Same ids / slots / anchors as today's pieces; NOT exported into the app. All five tops share ONE engine, `tunic`: a thin cloth sheet that hugs the
bare egg (offset ~1.6 cm) between a hem and a neckline, with a real closed armhole cut round each arm nub (3 cm clearance, measured on the cloth).
Preview them with  preview.py -- OUT LABEL new/<id>  (the `new/` prefix selects this file)."""
from kit5 import *
import items7 as I7

BIB = BIB_ANCHOR

# ------------------------------------------------------------------ shared engine
def arm_d(P):
    P = np.asarray(P, float)
    d, _ = B.armSDF(np.abs(P[..., 0]), P[..., 1], P[..., 2])
    return d

def skin_pt(y, phi, off):
    """egg point pushed `off` along the surface normal, with the downward tilt of the normal limited (the belly curves under: a hem must not slide down and out)."""
    e = B.egg_point(y, phi); n = B.egg_grad(e); n[1] = max(n[1], -0.2); n /= np.linalg.norm(n)
    return e + n * off

def skin_h(y, phi, off):
    e = B.egg_point(y, phi); n = B.egg_grad(e); h = np.array([n[0], 0.0, n[2]]); h /= np.linalg.norm(h)
    return e + h * off, h

def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi

def top_edge(phi, yc, ys=0.73, yb=0.69, kind='U', u0=0.35, pw=1.5):
    """Neckline height round the body: yc at the centre front (U: a flat-bottomed scoop |x|<~0.2; V: a pointed V), rising to ys over the arm roots, ~yb round the back.
    Front rule: at |x| < 0.3 the edge stays <= 0.575 (mouth keep-out)."""
    c, s = math.cos(phi), math.sin(phi); u = abs(c)
    if s >= 0:
        if kind == 'U':
            t = max(0.0, min(1.0, (u - u0) / (1 - u0))); g = t * t * (3 - 2 * t)
        else:
            up = math.sqrt(u * u + 0.0025) - 0.05; g = max(0.0, up) ** pw
        return yc + (ys - yc) * g
    t = min(1.0, -s); g = t * t * (3 - 2 * t)
    return ys - (ys - yb) * g

def tunic(name, levels, top_fn, off_fn, col_fn, ncols=40, slot=None, m_arm=0.032, edge_up=0.006, hole_col=None, top_col=None, edge_col=None, c0=(0.12, 0.48)):
    """levels: ascending absolute y of the rows (levels[0] = hem). top_fn(phi) = neckline. off_fn(phi, y) = stand-off from the egg. col_fn(phi, y, p) = rgb.
    slot: half-angle (rad) of a gap at the back centre (Pip's tail / spikes): the sheet is then open there (its two edges rolled like the armholes).
    Armholes: every vertex whose cloth point is < m_arm from the arm nub is dropped with its cells; the vertices round the hole are then snapped onto the m_arm contour."""
    if slot:
        p0, p1 = 1.5 * math.pi + slot, 1.5 * math.pi - slot + 2 * math.pi
        phis = [p0 + (p1 - p0) * i / (ncols - 1) for i in range(ncols)]
    else:
        phis = [2 * math.pi * i / ncols for i in range(ncols)]
    N = len(phis); closed_u = not slot
    pos = {}                              # (i, k) -> [phi, y, kind]
    rows = []                             # rows[i][j] -> (i, k) vertex key
    for i, phi in enumerate(phis):
        top = top_fn(phi); col = []; k = 0; jt = len(levels)
        for j, L in enumerate(levels):
            if j == 0 or L < top - 0.012:
                pos[(i, k)] = [phi, L, 'hem' if j == 0 else 'mid']; col.append((i, k)); k += 1
            else: jt = j; break
        pos[(i, k)] = [phi, top, 'top']
        while len(col) < len(levels): col.append((i, k))
        rows.append(col)
    def cloth(key, extra=0.0):
        phi, y, kind = pos[key]
        return skin_pt(y, phi, off_fn(phi, y) + extra)
    inside = {}
    for key in pos: inside[key] = bool(arm_d(cloth(key)) < m_arm)
    cells = []; dropped = []
    for i in range(N if closed_u else N - 1):
        i2 = (i + 1) % N
        for j in range(len(levels) - 1):
            ids = [rows[i][j], rows[i2][j], rows[i2][j + 1], rows[i][j + 1]]
            if any(inside[k] for k in ids): dropped.append(ids)
            else: cells.append(ids)
    edge = set()
    for ids in dropped:
        for k in ids:
            if not inside[k]: edge.add(k)
    # snap the boundary vertices onto the m_arm contour (march towards the hole centre in (phi*R, y))
    R_ = 0.55
    for key in edge:
        phi, y, kind = pos[key]
        pc = c0[0] if math.cos(phi) >= 0 else math.pi - c0[0]
        dphi = wrap(pc - phi)
        def q(t): return phi + dphi * t, y + (c0[1] - y) * t
        if arm_d(cloth(key)) < m_arm: continue
        lo, hi = 0.0, 1.0
        for _ in range(18):
            m = 0.5 * (lo + hi); ph, yy = q(m)
            if arm_d(skin_pt(yy, ph, off_fn(ph, yy))) < m_arm: hi = m
            else: lo = m
        ph, yy = q(lo); pos[key][0] = ph; pos[key][1] = yy
    if slot:
        for i in (0, N - 1):
            for k in rows[i]: edge.add(k)
    # compact the used vertices
    used = {}
    F = []
    for ids in cells:
        quad = []
        for k in ids:
            if k not in quad: quad.append(k)
        for a in quad:
            if a not in used: used[a] = len(used)
        if len(quad) == 4: F += [(used[quad[0]], used[quad[1]], used[quad[2]]), (used[quad[0]], used[quad[2]], used[quad[3]])]
        elif len(quad) == 3: F.append((used[quad[0]], used[quad[1]], used[quad[2]]))
    keys = sorted(used, key=lambda k: used[k])
    P = []; C = []
    for key in keys:
        phi, y, kind = pos[key]
        is_edge = key in edge
        up = edge_up if (is_edge or kind == 'top') else 0.0
        p = skin_pt(y, phi, off_fn(phi, y) + up)
        P.append(p)
        c = col_fn(phi, y, p)
        if is_edge and hole_col is not None: c = hole_col(phi, y, c)
        elif kind == 'top' and top_col is not None: c = top_col(phi, y, c)
        C.append(c)
    return add_part(name, P, F, C, hint=lambda p: egg_n(p))

def ribbon(name, path_fn, nt, halfw, prof, colfn, hint=None):
    """A strip along path_fn(t) -> (centre point, across direction, normal) with cross-section stand-offs prof = [(w -1..1, extra offset)...]."""
    P = []; C = []
    for a in range(nt):
        t = a / (nt - 1); c, ac, nn = path_fn(t)
        for w, e in prof:
            P.append(c + ac * w * halfw + nn * e); C.append(colfn(t, w))
    nw = len(prof); F = []
    for a in range(nt - 1):
        for b in range(nw - 1):
            i0 = a * nw + b; F += [(i0, i0 + 1, i0 + nw + 1), (i0, i0 + nw + 1, i0 + nw)]
    return add_part(name, P, F, C, hint=hint or (lambda p: full_n(p)))

def front_line(y0, y1, off, x=0.0, halfw=0.02, prof=None, nt=8, name='placket', colfn=None):
    """A vertical strip down the centre front (x = 0) from y0 to y1 lying `off` above the skin."""
    prof = prof or [(-1.0, -0.004), (-0.4, 0.002), (0.4, 0.002), (1.0, -0.004)]
    def pf(t):
        y = y0 + (y1 - y0) * t; p, n = body_pt(x, y, off); return p, np.array([1.0, 0, 0]), n
    return ribbon(name, pf, nt, halfw, prof, colfn)

def pouch(name, y0, y1, wfn, D, color_fn, off0=0.020, nu=11, nv=10, gap=0.0, hint_dir=None, peak=0.0):
    """A soft rounded pouch lying on the BACK: footprint y0..y1 with half-width wfn(v) (m), standing off0 at its rim and off0 + D*bulge in the middle.
    gap > 0: two lobes (x >= gap) and (x <= -gap), no cloth in the middle (Pip's spike row)."""
    def build(side, nm):
        P = []; C = []
        for b in range(nv):
            v = b / (nv - 1); y = y0 + (y1 - y0) * v; w = wfn(v)
            for a in range(nu):
                u = a / (nu - 1)                           # 0 at the middle, 1 at the rim
                x = (gap + (w - gap) * u) * side if gap > 0 else (2 * u - 1) * w
                if gap > 0 and w <= gap + 0.004: x = side * (gap + 0.004 * u)
                t = (y - B.lift) / B.bodyH; aw = float(B.halfWidth(t))
                ph = 1.5 * math.pi + math.asin(max(-0.98, min(0.98, x / aw)))
                uu = abs(x) / max(w, 1e-6) if gap == 0 else (abs(x) - gap) / max(w - gap, 1e-3)
                rim = max(0.0, 1 - (abs(2 * uu - 1) if gap > 0 else uu) ** 2.2) ** 0.55
                bul = max(0.0, math.sin(math.pi * min(1.0, max(0.0, v)))) ** 0.5
                d = D * rim * bul * (1 + peak * v)
                P.append(skin_pt(y, ph, off0 + d)); C.append(color_fn(x, y, u, v))
        F = []
        for b in range(nv - 1):
            for a in range(nu - 1):
                i0 = b * nu + a; F += [(i0, i0 + 1, i0 + nu + 1), (i0, i0 + nu + 1, i0 + nu)]
        return add_part(nm, P, F, C, hint=lambda p: full_n(p))
    if gap > 0:
        build(1, name); return build(-1, name + '2')
    return build(1, name)

# ------------------------------------------------------------------ puffer vest
def vest_puffer(main=hx('#2E7C85'), trim=hx('#1F5760'), zip_=GOLD, pip=False, **k):
    reset()
    y_hem = 0.22; rolls = 4; ytop_roll = 0.25; rh = 0.112
    levels = [y_hem, 0.245]
    for r in range(rolls):
        for q in (1, 2, 3, 4): levels.append(ytop_roll + rh * (r + q / 4.0))
    levels = [l for l in levels if l < 0.74]
    def puff(y):
        if y < 0.25: return 0.0
        s = ((y - ytop_roll) / rh) % 1.0
        return abs(math.sin(math.pi * s)) ** 0.7
    def cw(phi):                                         # stand-collar weight: sides + back, none on the front V
        c, s = math.cos(phi), math.sin(phi)
        return smooth01(0.45, 0.8, abs(c)) if s >= 0 else 1.0
    def off(phi, y):
        if y < 0.25: return 0.022
        o = 0.014 + 0.022 * puff(y)
        if y > 0.66: o += 0.016 * cw(phi) * smooth01(0.66, 0.73, y)
        return o
    def col(phi, y, p):
        w = puff(y) if y >= 0.25 else 0.0
        c = mix(deep(main, 0.30), mix(tint(main, 0.22), (0.85, 1.0, 1.0), 0.12), 0.05 + 0.95 * w ** 1.4)
        if y < 0.25: c = mix(deep(trim, 0.15), trim, 0.5 + 0.5 * math.cos(26 * phi))
        if y > 0.675: c = mix(c, tint(trim, 0.20), 0.55 * cw(phi))
        return c
    top = lambda phi: top_edge(phi, 0.50, ys=0.74, yb=0.665, kind='U')
    tunic('body', levels, top, off, col, ncols=36, slot=(0.42 if pip else None), m_arm=0.040,
          hole_col=lambda phi, y, c: mix(c, tint(trim, 0.20), 0.75), top_col=lambda phi, y, c: mix(c, tint(trim, 0.2), 0.75))
    pts = [body_pt(0.0, y, 0.040)[0] + np.array([0, 0, 0.002]) for y in np.linspace(0.250, 0.50, 9)]
    tube_curve('zip', pts, 0.011, 4, lambda p, n: mix(deep(zip_, 0.25), tint(zip_, 0.4), 0.5 + 0.5 * n[2]), cap=True)
    bead('pull', body_pt(0.0, 0.452, 0.050)[0], (0.020, 0.034, 0.012), lambda p, n: mix(deep(zip_, 0.2), tint(zip_, 0.6), 0.5 + 0.5 * n[2]), segs=6)
    return dict(anchor='chest', slot='body', tags=['cool', 'sporty'], price=65, title='Puffer vest', desc='concept')


# ------------------------------------------------------------------ hoodie
def hood_col(main, trim):
    def f(x, y, u, v):
        base = mix(deep(main, 0.10), tint(main, 0.14), 0.5 + 0.5 * math.sin(math.pi * v))
        rim = max(smooth01(0.80, 1.0, u), smooth01(0.88, 1.0, abs(2 * v - 1)))
        seam = math.exp(-(x / 0.012) ** 2) * 0.4
        return mix(mix(base, deep(main, 0.28), seam), mix(trim, deep(trim, 0.08), 0.3), 0.85 * rim)
    return f

def hoodie(main=hx('#E8575F'), trim=CREAM, pip=False, **k):
    reset()
    levels = [0.23, 0.262, 0.30, 0.34, 0.38, 0.42, 0.46, 0.50, 0.54, 0.58, 0.62, 0.66, 0.70, 0.735]
    def off(phi, y):
        if y < 0.27: return 0.024
        return 0.016 + 0.004 * smooth01(0.27, 0.32, y)
    def col(phi, y, p):
        if y < 0.275:
            rib = 0.5 + 0.5 * math.cos(26 * phi)
            return mix(mix(trim, deep(trim, 0.18), 0.5 * (1 - rib)), deep(main, 0.1), 0.0)
        return mix(deep(main, 0.06), tint(main, 0.12), 0.5 + 0.5 * math.sin(3.0 * y + 1.3))
    top = lambda phi: top_edge(phi, 0.50, ys=0.74, yb=0.665, kind='U')
    tunic('body', levels, top, off, col, ncols=36, slot=(0.42 if pip else None), m_arm=0.040,
          hole_col=lambda phi, y, c: mix(c, deep(main, 0.22), 0.7), top_col=lambda phi, y, c: mix(c, deep(main, 0.20), 0.7))
    # kangaroo pocket on the lower front
    I7.pillow('pocket', math.pi / 2, 0.325, 0.33, 0.072, 0.012, None, off0=0.020, nu=11, nv=6, rim=0.7,
              colfn=lambda i, j: mix(deep(main, 0.20), tint(main, 0.08), 0.35 + 0.65 * math.sin(math.pi * j / 5.0) * (1 - 0.5 * abs(i - 5) / 5.0)))
    # two short drawcords beside the centre
    for s in (-1, 1):
        pts = [body_pt(s * x, y, 0.030)[0] for x, y in ((0.058, 0.498), (0.064, 0.470), (0.070, 0.438), (0.074, 0.405))]
        tube_curve('cord%+d' % s, pts, 0.0075, 5, trim, cap=True)
        bead('aglet%+d' % s, body_pt(s * 0.075, 0.392, 0.030)[0], (0.012, 0.020, 0.012), HONEY, segs=6)
    # hood resting behind the head: a soft rounded pouch on the upper back (two lobes round Pip's spikes)
    wfn = lambda v: 0.235 * max(0.0, 1 - ((2 * v - 0.85) / 1.15) ** 2) ** 0.5
    pouch('hood', 0.590, 1.000, wfn, 0.080, hood_col(main, trim), off0=0.024, nu=(6 if pip else 11), nv=10, gap=(0.10 if pip else 0.0))
    return dict(anchor='chest', slot='body', tags=['cool', 'cute', 'sweet'], price=65, title='Cosy hoodie', desc='concept')

# ------------------------------------------------------------------ raincoat
def raincoat(main=hx('#F4C13E'), trim=CREAM, toggle=hx('#7A4A2B'), pip=False, **k):
    reset()
    levels = [0.18, 0.205, 0.235, 0.265, 0.30, 0.34, 0.38, 0.42, 0.46, 0.50, 0.54, 0.58, 0.62, 0.66, 0.70, 0.735]
    def cw(phi):
        c, s = math.cos(phi), math.sin(phi)
        return smooth01(0.50, 0.85, abs(c)) if s >= 0 else 1.0
    def off(phi, y):
        o = 0.016 + 0.028 * (1 - smooth01(0.18, 0.52, y)) ** 1.3          # gentle A-line: 4.4 cm at the hem, 1.6 cm from the waist up
        if y > 0.64: o += 0.026 * cw(phi) * smooth01(0.64, 0.73, y)        # small collar
        return o
    def col(phi, y, p):
        c = mix(deep(main, 0.08), tint(main, 0.20), 0.5 + 0.5 * math.sin(2.6 * y + 0.9))
        if 0.215 < y < 0.265: c = mix(c, trim, 0.9 * smooth01(0.0, 1.0, 1 - abs(y - 0.24) / 0.025))
        if y > 0.675: c = mix(c, mix(deep(main, 0.14), trim, 0.35), 0.8 * cw(phi))
        return c
    top = lambda phi: top_edge(phi, 0.50, ys=0.74, yb=0.665, kind='U')
    tunic('coat', levels, top, off, col, ncols=36, slot=(0.42 if pip else None), m_arm=0.040,
          hole_col=lambda phi, y, c: mix(c, deep(main, 0.25), 0.7), top_col=lambda phi, y, c: mix(c, mix(deep(main, 0.1), trim, 0.5), 0.6))
    front_line(0.185, 0.495, 0.026, halfw=0.026, name='placket', prof=[(-1.0, -0.006), (-0.5, 0.002), (0.5, 0.002), (1.0, -0.006)], nt=10,
               colfn=lambda t, w: mix(deep(main, 0.10), tint(main, 0.25), 0.5 + 0.3 * (1 - abs(w))))
    for i, y in enumerate((0.31, 0.385, 0.455)):
        p, n = body_pt(0.0, y, 0.036); xx, yy, nn = axes(n)
        bead('toggle%d' % i, p, (0.030, 0.013, 0.013), lambda q, nq: mix(deep(toggle, 0.12), tint(toggle, 0.25), 0.5 + 0.5 * nq[2]), rot=np.stack([xx, yy, nn], 1), segs=6)
    wfn = lambda v: 0.215 * max(0.0, 1 - v ** 1.25) ** 0.7
    pouch('hood', 0.600, 1.000, wfn, 0.052, hood_col(main, trim), off0=0.024, nu=(6 if pip else 11), nv=12, gap=(0.10 if pip else 0.0), peak=1.1)
    return dict(anchor='chest', slot='body', tags=['cute', 'cool'], price=60, title='Yellow raincoat', desc='concept')

# ------------------------------------------------------------------ cardigan
def cardigan(main=hx('#E6D8BC'), trim=hx('#C2AC84'), button=hx('#3B2A22'), pip=False, **k):
    reset()
    levels = [0.21, 0.245, 0.285, 0.325, 0.365, 0.405, 0.445, 0.485, 0.525, 0.565, 0.605, 0.645, 0.685, 0.72]
    def off(phi, y):
        return 0.024 if y < 0.25 else 0.016
    def col(phi, y, p):
        if y < 0.25:
            rib = 0.5 + 0.5 * math.cos(26 * phi); return mix(deep(trim, 0.10), tint(trim, 0.10), rib)
        cab = 0.5 + 0.5 * math.cos(8.0 * phi + 0.55 * math.sin(55 * y))              # braided cable ribs: broad columns that wiggle
        return mix(tint(main, 0.08), deep(main, 0.22), 0.55 * smooth01(0.35, 0.8, cab))
    top = lambda phi: top_edge(phi, 0.42, ys=0.74, yb=0.665, kind='V', pw=1.5)
    tunic('body', levels, top, off, col, ncols=44, slot=(0.42 if pip else None), m_arm=0.040,
          hole_col=lambda phi, y, c: mix(c, deep(trim, 0.05), 0.75), top_col=lambda phi, y, c: mix(c, deep(trim, 0.12), 0.95), edge_up=0.009)
    front_line(0.205, 0.425, 0.026, halfw=0.030, name='band', prof=[(-1.0, -0.006), (-0.5, 0.003), (0.5, 0.003), (1.0, -0.006)], nt=9,
               colfn=lambda t, w: mix(deep(trim, 0.10), tint(trim, 0.20), 0.5 + 0.4 * (1 - abs(w))))
    for i, y in enumerate((0.265, 0.325, 0.385)):
        p, n = body_pt(0.0, y, 0.036); xx, yy, nn = axes(n)
        bead('button%d' % i, p, (0.021, 0.021, 0.010), lambda q, nq: mix(button, hx('#7A6256'), 0.35 * max(0.0, nq[2])), rot=np.stack([xx, yy, nn], 1), segs=8)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet'], price=60, title='Cable cardigan', desc='concept')

# ------------------------------------------------------------------ hero cape
def cape(main=None, lining=HONEY, trim=CREAM, pip=False, **k):
    main = main or I7.IO2.RED
    reset()
    ycl = lambda phi: top_edge(phi, 0.47, ys=0.720, yb=0.645, kind='V', pw=1.9)
    COFF = 0.026
    # collar band: two halves from the clasp (front centre, y 0.47) over the shoulders to the back centre (Pip: stops 0.3 rad short of it, round the spike row)
    for side in (1, -1):
        end = (0.32 if pip else 0.0)
        def path(t, side=side, end=end):
            def pt(tt): return math.pi / 2 - side * ((math.pi - end) * tt + 0.02)
            ph = pt(t); d = 1e-3
            c = skin_pt(ycl(ph), ph, COFF); c2 = skin_pt(ycl(pt(min(1, t + d))), pt(min(1, t + d)), COFF); c1 = skin_pt(ycl(pt(max(0, t - d))), pt(max(0, t - d)), COFF)
            tg = (c2 - c1); tg /= np.linalg.norm(tg)
            n = B.egg_grad(c); ac = np.cross(tg, n); ac /= np.linalg.norm(ac)
            return c, ac, n
        ribbon('collar%+d' % side, path, 30, 0.030, [(-1.0, -0.008), (-0.55, 0.004), (0.0, 0.007), (0.55, 0.004), (1.0, -0.008)],
               lambda t, w: mix(deep(trim, 0.08), tint(trim, 0.10), 0.5 + 0.5 * (1 - abs(w))), hint=lambda p: egg_n(p))
    pc, nc = body_pt(0.0, 0.478, 0.046); xx, yy, nn = axes(nc)
    bead('clasp', pc, (0.040, 0.040, 0.014), lambda p, n: mix(deep(HONEY, 0.12), tint(HONEY, 0.25), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=10)
    bead('clasp_gem', pc + nn * 0.011, (0.018, 0.018, 0.008), lambda p, n: mix(deep(CORAL, 0.1), tint(CORAL, 0.35), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=8)
    # the hanging panel: back only, from the collar down to y ~0.16, folds, wavy hem, <= 6 cm flare (skin offset 2.6 cm at the collar, 6 cm at the hem)
    NU, NV = (6 if pip else 10), 8
    HEM = 0.170
    GAP = 0.30                                              # Pip: slot half-width as a fraction of the half width (x ~ +-0.12 .. the tail root is wider: see below)
    if pip: GAP = 0.55
    def panel_pt(side_lo, side_hi, a, b):
        u = a / (NU - 1); v = b / (NV - 1)
        xs = side_lo + (side_hi - side_lo) * u
        ytop = ycl(1.5 * math.pi + math.asin(max(-0.97, min(0.97, 0.40 * xs / 0.57)))) - 0.012
        yhem = HEM + 0.026 * math.sin(2 * math.pi * (xs * 1.75) + 0.6)
        y = ytop + (yhem - ytop) * v
        X = (0.40 + 0.05 * v ** 1.4) * xs
        aw = float(B.halfWidth((y - B.lift) / B.bodyH))
        ph = 1.5 * math.pi + math.asin(max(-0.985, min(0.985, X / aw)))
        fold = 0.015 * math.sin(2 * math.pi * 1.75 * xs + 0.5) * (v ** 0.8)
        off = 0.026 + 0.028 * v ** 1.4 + fold
        p, h = skin_h(y, ph, off)
        return p, h
    halves = [(GAP, 1.0), (-1.0, -GAP)] if pip else [(-1.0, 1.0)]
    for lo, hi in halves:
        cmain = lambda p, n: (mix(deep(main, 0.14), tint(main, 0.14), 0.5 + 0.5 * math.sin(11.0 * p[0] + 0.5)) if p[1] > 0.215 else mix(trim, deep(trim, 0.10), 0.3))
        cin = lambda p, n: mix(deep(lining, 0.08), tint(lining, 0.12), 0.5 + 0.5 * math.sin(6 * p[0]))
        thick_sheet('panel', lambda a, b, lo=lo, hi=hi: panel_pt(lo, hi, a, b), NU, NV, 0.012, cmain, cin)
    # star emblem on the back
    ys_ = 0.43; xs0 = (-0.80 if pip else 0.0)
    v = None; bestd = 9
    for b in range(64):
        vv = b / 63; ytop = ycl(1.5 * math.pi + math.asin(max(-0.97, min(0.97, 0.40 * xs0 / 0.57)))) - 0.012; yy = ytop + (HEM - ytop) * vv
        if abs(yy - ys_) < bestd: bestd = abs(yy - ys_); v = vv; y = yy
    X = (0.40 + 0.04 * v ** 1.4) * xs0; aw = float(B.halfWidth((y - B.lift) / B.bodyH))
    ph = 1.5 * math.pi + math.asin(max(-0.985, min(0.985, X / aw)))
    cen, h = skin_h(y, ph, 0.026 + 0.030 * v ** 1.4 + 0.006); ax = np.cross(np.array([0, 1.0, 0]), h); ax /= np.linalg.norm(ax)
    sp = star_poly(0.070, 0.032, 5, rad=0.010)
    slab_part('emblem', sp, 0.012, lambda p, nn: mix(deep(HONEY, 0.1), tint(HONEY, 0.25), 0.5 + 0.5 * nn[2]), lambda px, py, pz: tuple(cen - ax * px + np.array([0, py, 0]) + h * pz), cuts=0, sharp=40)
    return dict(anchor='back', slot='body', tags=['cool', 'sparkly', 'cute'], price=70, title='Hero cape', desc='concept')

REG = [
    ('hoodie', hoodie, dict(), BIB),
    ('raincoat', raincoat, dict(), BIB),
    ('cardigan_cable', cardigan, dict(), BIB),
    ('vest_puffer', vest_puffer, dict(), BIB),
    ('cape_hero', cape, dict(), BACK_ANCHOR),
]
VARIANTS = [('hoodie_pip', hoodie, dict(pip=True), BIB), ('raincoat_pip', raincoat, dict(pip=True), BIB), ('cardigan_cable_pip', cardigan, dict(pip=True), BIB),
            ('vest_puffer_pip', vest_puffer, dict(pip=True), BIB), ('cape_hero_pip', cape, dict(pip=True), BACK_ANCHOR)]
