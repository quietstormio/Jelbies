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

def ss(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def top_edge(phi, yc, ys=0.74, yb=0.69, x0=0.25, x1=0.40, pw=1.0):
    """Neckline height round the body. FRONT half, as a function of x (0.57*|cos phi|): flat at yc for |x| < x0, a smooth scoop climbing to ys at x1 (the climb stays under 0.575 at |x| < 0.3:
    keep-out), then a LEVEL shoulder across the arm root to the side; BACK half: level to the side, then a quick smooth fall to yb (by 0.6 rad round the back: the wing fans start at y 0.73, |x| 0.29)."""
    c, s = math.cos(phi), math.sin(phi); x = 0.57 * abs(c)
    if s >= 0:
        t = max(0.0, min(1.0, (x - x0) / (x1 - x0)))
        return yc + (ys - yc) * ss(t ** pw)
    ang = math.asin(min(1.0, -s)); t = (ang - 0.05) / 0.55
    return ys - (ys - yb) * ss(t)

ARM_PHI = 0.12
def make_cols(p0, p1, smin=0.100, smax=0.38):
    """Column azimuths from p0 to p1: dense round the arm roots (azimuth 0.12 and pi - 0.12) so the armholes are rounder, coarse on the chest and back."""
    out = [p0]; p = p0
    while p < p1 - 1e-6:
        d = min(abs(wrap(p - ARM_PHI)), abs(wrap(p - (math.pi - ARM_PHI))))
        d2 = min(abs(wrap(p - 0.92)), abs(wrap(p - (math.pi - 0.92))))                 # the front scoop (x 0.25 .. 0.45) needs columns too: a smooth neckline
        w = max(math.exp(-(d / 0.75) ** 2), math.exp(-(d2 / 0.34) ** 2))
        p += smax - (smax - smin) * w; out.append(p)
    sc = (p1 - p0) / (out[-1] - p0)
    return [p0 + (q - p0) * sc for q in out]

def fold_lips(part, lipw=0.012, lipd=0.009, shade=0.88, only=None):
    """Every open edge of the sheet gets an inward-folded lip (a strip lipw wide turned toward the body and lipd closer to it, facing inward): an edge always shows cloth, never the see-through gap."""
    P = part['P']; F = part['F']; N = part['N']; C = part['C']
    ec = {}
    for f in F:
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]; key = (min(a, b), max(a, b)); ec.setdefault(key, []).append((a, b))
    bnd = [dirs[0] for dirs in ec.values() if len(dirs) == 1 and (only is None or (dirs[0][0] in only and dirs[0][1] in only))]
    adj = {}
    for f in F:
        cen = (np.array(P[f[0]]) + np.array(P[f[1]]) + np.array(P[f[2]])) / 3
        for v in f: adj.setdefault(v, []).append(cen)
    lip = {}
    for a, b in bnd:
        for v in (a, b):
            if v in lip: continue
            p = np.array(P[v]); n = np.array(N[v]); d = np.mean(adj[v], 0) - p; d = d - n * np.dot(d, n)
            ln = np.linalg.norm(d); d = d / ln if ln > 1e-9 else np.zeros(3)
            lip[v] = len(P); P.append(tuple(p + d * lipw - n * lipd)); N.append(tuple(-n)); C.append(tuple(c * shade for c in C[v]))
    for a, b in bnd:
        F.append((b, a, lip[a])); F.append((b, lip[a], lip[b]))
    return part

def tunic(name, levels, top_fn, off_fn, col_fn, lm=0.40, slot=None, m_arm=0.046, edge_up=0.004, snap=(), lip=True, smin=0.100, smax=0.38, c0=(0.12, 0.48), rib=None):
    """levels: ascending absolute y of the numeric rows (levels[0] = hem; two levels 1.5 mm apart make a CRISP colour/offset step). top_fn(phi) = neckline.
    off_fn(phi, L, ci) = stand-off from the egg, col_fn(phi, L, p, ci) = rgb (L = the row's nominal level, 99 for the neckline rib rows, ci = column index).
    rib = w: the top w of the sheet (two extra rows, a 2 mm step below them) is a separate neckline rib. Rows above lm follow the neckline (no stair-steps), rows below stay level.
    slot: half-angle (rad) of a gap at the back centre (Pip). Armholes: vertices whose cloth point is < m_arm from the arm nub are dropped with their cells; the vertices round the hole are snapped onto the contour.
    Every open edge gets an inward lip (fold_lips)."""
    if slot: phis = make_cols(1.5 * math.pi + slot, 1.5 * math.pi - slot + 2 * math.pi, smin, smax)
    else: phis = make_cols(0.0, 2 * math.pi, smin, smax)[:-1]
    for tgt in snap:
        j = min(range(len(phis)), key=lambda q: abs(wrap(phis[q] - tgt)))
        if slot and abs(wrap(tgt - 1.5 * math.pi)) < slot + 0.12: continue
        if abs(wrap(phis[j] - tgt)) < 0.09 and not (slot and j in (0, len(phis) - 1)): phis[j] = phis[j] + wrap(tgt - phis[j])
    k = 0                                                              # no column gap wider than 0.41 rad (the cloth chord would dip under the skin: sagitta)
    while k < len(phis) - (1 if slot else 0):
        nxt = phis[k + 1] if k + 1 < len(phis) else phis[0] + 2 * math.pi
        if nxt - phis[k] > 0.41: phis.insert(k + 1, 0.5 * (phis[k] + nxt)); continue
        k += 1
    N = len(phis); closed_u = not slot
    pos = {}; rows = []
    Lt = levels[-1]; nl = len(levels)
    for i, phi in enumerate(phis):
        top = top_fn(phi); tt = top - (rib + 0.002 if rib else 0.0)
        for j, L in enumerate(levels):
            y = L if L <= lm else lm + (tt - lm) * (L - lm) / (Lt - lm)
            kind = 'hem' if j == 0 else 'mid'
            if not rib and j == nl - 1: y = top; kind = 'top'
            pos[(i, j)] = [phi, y, kind, L]
        if rib:
            pos[(i, nl)] = [phi, top - rib, 'rib', 99.0]; pos[(i, nl + 1)] = [phi, top, 'top', 99.0]
        rows.append([(i, j) for j in range(nl + (2 if rib else 0))])
    nr = nl + (2 if rib else 0)
    def cloth(key, extra=0.0):
        phi, y, kind, L = pos[key]
        return skin_pt(y, phi, off_fn(phi, L, key[0]) + extra)
    inside = {key: bool(arm_d(cloth(key)) < m_arm) for key in pos}
    cells = []; dropped = []
    for i in range(N if closed_u else N - 1):
        i2 = (i + 1) % N
        for j in range(nr - 1):
            ids = [rows[i][j], rows[i2][j], rows[i2][j + 1], rows[i][j + 1]]
            (dropped if any(inside[k] for k in ids) else cells).append(ids)
    edge = set()
    for ids in dropped:
        for k in ids:
            if not inside[k]: edge.add(k)
    for key in edge:
        phi, y, kind, Lnom = pos[key]
        pc = c0[0] if math.cos(phi) >= 0 else math.pi - c0[0]
        dphi = wrap(pc - phi)
        def q(t): return phi + dphi * t, y + (c0[1] - y) * t
        lo, hi = 0.0, 1.0
        for _ in range(18):
            m = 0.5 * (lo + hi); ph, yy = q(m)
            if arm_d(skin_pt(yy, ph, off_fn(ph, Lnom, key[0]))) < m_arm: hi = m
            else: lo = m
        ph, yy = q(lo); pos[key][0] = ph; pos[key][1] = yy
    if slot:
        for i in (0, N - 1):
            for k in rows[i]: edge.add(k)
    used = {}; F = []
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
        phi, y, kind, Lnom = pos[key]
        up = edge_up if (key in edge or kind == 'top') else 0.0
        P.append(skin_pt(y, phi, off_fn(phi, Lnom, key[0]) + up))
        C.append(col_fn(phi, Lnom, P[-1], key[0]))
    part = add_part(name, P, F, C, hint=lambda p: egg_n(p))
    if lip: fold_lips(part)
    return part

def sleeves(prefix, sleeve_col, cuff_col, o_top=0.052, o_cuff=0.016, h_cuff=0.85, nth=14, cuff_len=0.14, cuff_off=0.017):
    """SHORT SLEEVES (rest-pose mock): a soft shell over the upper part of each arm nub (the nub is a bulb on the side of the egg: axis a -> b, radius 0.058 -> 0.15, z flattened 1.15),
    standing o_top off it at the shoulder (so its rim overlaps the cloth edge of the armhole: no skin shows at the join) and o_cuff off it at the cuff, which ends h_cuff of the way to the tip;
    the tip stays bare. The part of the shell inside the egg is clipped away (rim snapped to 2.2 cm off the egg) and the rim is folded in (fold_lips)."""
    a = np.array([0.517, 0.605, 0.06]); b = np.array([0.55, 0.46, 0.06]); Ln = np.linalg.norm(b - a); d = (b - a) / Ln
    ex = np.array([-d[1], d[0], 0.0]); ez = np.array([0.0, 0.0, 1.0])
    R = lambda h: 0.058 + (0.15 - 0.058) * h
    def oh(h): return o_top + (o_cuff - o_top) * ss((h + 0.2) / (h_cuff + 0.2))
    def solve_r(cen, dirv, o):
        """distance r along dirv from cen at which the arm SDF equals o (exact arm skin + o)."""
        lo, hi = 0.0, 0.45
        if float(arm_d(cen)) > o: return 0.0
        for _ in range(22):
            m = 0.5 * (lo + hi)
            if float(arm_d(cen + dirv * m)) < o: lo = m
            else: hi = m
        return 0.5 * (lo + hi)
    def ring(spec, th):
        kind, v, extra = spec
        e = ex * math.cos(th) + ez * math.sin(th)
        if kind == 'cap':
            cen = a.copy(); dirv = -d * math.cos(v) + e * math.sin(v); o = oh(0)
            return cen + dirv * solve_r(cen, dirv, o), cen
        cen = a + (b - a) * v; o = oh(v) + extra
        return cen + e * solve_r(cen, e, o), cen
    def build(rings, nm, colfn, side, rib_amp=0.0, lipset='rim'):
        V = []; CEN = []
        for r, spec in enumerate(rings):
            row = []; crow = []
            for t in range(nth):
                th = 2 * math.pi * t / nth
                p, cen = ring(spec, th)
                if rib_amp: p = p + (ex * math.cos(th) + ez * math.sin(th)) * (rib_amp if t % 2 else -rib_amp)
                row.append(p); crow.append(cen)
            V.append(row); CEN.append(crow)
        sdf = lambda p: float(B.bodySDF(p[0], p[1], p[2]))
        ins = [[sdf(V[r][t]) < 0.022 for t in range(nth)] for r in range(len(rings))]
        pole = (rings[0][0] == 'cap' and rings[0][1] == 0.0)
        cells = []; drop = []
        for r in range(len(rings) - 1):
            for t in range(nth):
                t2 = (t + 1) % nth
                ids = [(r, t), (r, t2), (r + 1, t2), (r + 1, t)]
                if pole and r == 0: ids = [(0, 0), (1, t2), (1, t)]
                (drop if any(ins[k[0]][k[1]] for k in ids) else cells).append(ids)
        rim = set()
        for ids in drop:
            for (r, t) in ids:
                if not ins[r][t]: rim.add((r, t))
        for (r, t) in rim:
            cen = CEN[r][t]
            lo, hi = 0.0, 1.0
            for _ in range(18):
                m = 0.5 * (lo + hi); p = V[r][t] + (cen - V[r][t]) * m
                if sdf(p) < 0.022 or float(arm_d(p)) < 0.012: hi = m
                else: lo = m
            V[r][t] = V[r][t] + (cen - V[r][t]) * lo
        used = {}; F = []
        for ids in cells:
            ids = list(dict.fromkeys(ids))
            for k in ids:
                if k not in used: used[k] = len(used)
            if len(ids) == 4: F += [(used[ids[0]], used[ids[1]], used[ids[2]]), (used[ids[0]], used[ids[2]], used[ids[3]])]
            elif len(ids) == 3: F.append((used[ids[0]], used[ids[1]], used[ids[2]]))
        keys = sorted(used, key=lambda k: used[k])
        P = [V[r][t] for (r, t) in keys]
        if side < 0: P = [np.array([-p[0], p[1], p[2]]) for p in P]
        C = [colfn(np.array(p), rings[r]) for (r, t), p in zip(keys, P)]
        part = add_part(nm, P, F, C, hint=lambda p: full_n(p))
        if lipset == 'rim': only = {used[k] for k in rim if k in used}
        else: only = {used[k] for k in used if k[0] == len(rings) - 1 or k in rim}
        fold_lips(part, 0.010, 0.007, only=only)
        return part
    body_rings = [('cap', 0.0, 0), ('cap', math.radians(45), 0), ('h', 0.0, 0), ('h', 0.22, 0), ('h', 0.44, 0), ('h', 0.64, 0), ('h', h_cuff, 0)]
    cuff_rings = [('h', h_cuff, cuff_off - oh(h_cuff)), ('h', h_cuff + cuff_len, cuff_off - oh(h_cuff + cuff_len))]
    for side in (1, -1):
        build(body_rings, 'sleeve%+d' % side, lambda p, spec: sleeve_col, side)
        build(cuff_rings, 'cuff%+d' % side, lambda p, spec: cuff_col, side, rib_amp=0.0025, lipset='end')

def ribbon(name, path_fn, nt, halfw, prof, colfn, hint=None):
    """A strip along path_fn(t) -> (centre point, across direction, normal) with cross-section stand-offs prof = [(w -1..1, extra offset)...]."""
    P = []; C = []
    for a in range(nt):
        t = a / (nt - 1); c, ac, nn = path_fn(t)
        for w, e in prof:
            hw = halfw(t) if callable(halfw) else halfw
            P.append(c + ac * w * hw + nn * e); C.append(colfn(t, w))
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

def pouch(name, y0, y1, wfn, D, color_fn, off0=0.020, nu=11, nv=10, gap=0.0, peak=0.0, lip=True):
    """A soft rounded pouch lying on the BACK: footprint y0..y1 with half-width wfn(v) (m), standing off0 at its rim and off0 + D*bulge in the middle (open edge folded in by fold_lips).
    gap > 0: two lobes (|x| >= gap), no cloth in the middle (Pip's spike row)."""
    def build(side, nm):
        P = []; C = []
        for b in range(nv):
            v = b / (nv - 1); y = y0 + (y1 - y0) * v; w = wfn(v)
            for a in range(nu):
                u = a / (nu - 1)
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
        part = add_part(nm, P, F, C, hint=lambda p: full_n(p))
        if lip: fold_lips(part, 0.010, 0.008)
        return part
    if gap > 0:
        build(1, name); return build(-1, name + '2')
    return build(1, name)

def stripe(ci): return ci % 2

def cwf(phi):
    """stand-collar weight: sides + back, none on the front scoop"""
    c, s = math.cos(phi), math.sin(phi)
    return smooth01(0.35, 0.8, abs(c)) if s >= 0 else 1.0

TOPF = lambda phi: top_edge(phi, 0.50, ys=0.74, yb=0.69)

# ------------------------------------------------------------------ puffer vest
def vest_puffer(main=hx('#2E7C85'), trim=hx('#1F5760'), zip_=GOLD, pip=False, **k):
    reset()
    ytop_roll = 0.25; rh = 0.112
    levels = [0.22, 0.245, 0.2465]
    for r in range(4):
        for q in (1, 2, 3): levels.append(ytop_roll + rh * (r + q / 3.0))
    def puff(L):
        if L < 0.25: return 0.0
        return abs(math.sin(math.pi * (((L - ytop_roll) / rh) % 1.0))) ** 0.7
    def off(phi, L, ci):
        if L == 99.0: return 0.016 + 0.020 * cwf(phi)                                # rolled stand collar (sides + back)
        if L < 0.2466: return 0.022 + (0.003 if ci % 2 else -0.003)                   # ribbed hem band (geometry ribs)
        return 0.014 + 0.022 * puff(L)
    def col(phi, L, p, ci):
        if L == 99.0 or L < 0.2466: return trim
        return mix(deep(main, 0.30), mix(tint(main, 0.22), (0.85, 1.0, 1.0), 0.12), 0.05 + 0.95 * puff(L) ** 1.4)
    tunic('body', levels, TOPF, off, col, lm=0.44, rib=0.030, slot=(0.42 if pip else None), m_arm=0.046, smin=0.100, smax=0.38)
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

def hoodie(main=hx('#E8575F'), trim=CREAM, pip=False, sleeves_on=False, **k):
    reset()
    levels = [0.23, 0.262, 0.2635, 0.32, 0.40, 0.47, 0.54, 0.61, 0.67]
    def off(phi, L, ci):
        if L == 99.0: return 0.021
        if L < 0.263: return 0.025 + (0.003 if ci % 2 else -0.003)      # ribbed hem band (geometry ribs)
        return 0.016
    def col(phi, L, p, ci):
        return trim if (L == 99.0 or L < 0.263) else main
    sl = sleeves_on
    tunic('body', levels, TOPF, off, col, lm=0.40, rib=0.022, slot=(0.42 if pip else None), m_arm=(0.030 if sl else 0.046), smin=(0.12 if sl else 0.10), smax=(0.40 if sl else 0.38))
    I7.pillow('pocket', math.pi / 2, 0.325, 0.33, 0.072, 0.012, None, off0=0.020, nu=9, nv=5, rim=0.7,
              colfn=lambda i, j: mix(deep(main, 0.20), tint(main, 0.08), 0.35 + 0.65 * math.sin(math.pi * j / 5.0) * (1 - 0.5 * abs(i - 5) / 5.0)))
    for s_ in (-1, 1):
        pts = [body_pt(s_ * x, y, 0.030)[0] for x, y in ((0.058, 0.498), (0.064, 0.470), (0.070, 0.438), (0.074, 0.405))]
        tube_curve('cord%+d' % s_, pts, 0.0075, 5, trim, cap=True)
        bead('aglet%+d' % s_, body_pt(s_ * 0.075, 0.392, 0.030)[0], (0.012, 0.020, 0.012), HONEY, segs=6)
    wfn = lambda v: 0.235 * max(0.0, 1 - ((2 * v - 0.85) / 1.15) ** 2) ** 0.5
    pouch('hood', 0.590, 1.000, wfn, 0.080, hood_col(main, trim), off0=0.024, nu=(6 if pip else 8), nv=7, gap=(0.10 if pip else 0.0))
    if sl: sleeves('s', main, trim)
    return dict(anchor='chest', slot='body', tags=['cool', 'cute', 'sweet'], price=65, title='Cosy hoodie', desc='concept')

# ------------------------------------------------------------------ raincoat
def raincoat(main=hx('#F4C13E'), trim=CREAM, toggle=hx('#7A4A2B'), pip=False, sleeves_on=False, **k):
    reset()
    levels = [0.18, 0.21, 0.2115, 0.27, 0.34, 0.41, 0.49, 0.57, 0.64, 0.70]
    def off(phi, L, ci):
        if L == 99.0: return 0.016 + 0.004 + 0.012 * cwf(phi)                        # small rolled collar (sides + back)
        return 0.016 + 0.040 * (1 - ss((L - 0.18) / 0.34)) ** 1.3                      # gentle A-line: 4 cm flare at the hem
    def col(phi, L, p, ci):
        return trim if (L == 99.0 or L < 0.2113) else main                           # cream hem band + cream neckline roll, crisp steps
    sl = sleeves_on
    tunic('coat', levels, TOPF, off, col, lm=0.40, rib=0.020, slot=(0.42 if pip else None), m_arm=(0.030 if sl else 0.046), smin=(0.12 if sl else 0.10), smax=(0.40 if sl else 0.38))
    front_line(0.185, 0.495, 0.026, halfw=0.026, name='placket', prof=[(-1.0, -0.006), (-0.5, 0.002), (0.5, 0.002), (1.0, -0.006)], nt=10, colfn=lambda t, w: mix(deep(main, 0.12), deep(main, 0.12), 0.5))
    for i, y in enumerate((0.31, 0.385, 0.455)):
        p, n = body_pt(0.0, y, 0.036); xx, yy, nn = axes(n)
        bead('toggle%d' % i, p, (0.030, 0.013, 0.013), lambda q, nq: mix(deep(toggle, 0.12), tint(toggle, 0.25), 0.5 + 0.5 * nq[2]), rot=np.stack([xx, yy, nn], 1), segs=6)
    wfn = lambda v: 0.215 * max(0.0, 1 - ((2 * v - 0.80) / 1.20) ** 2) ** 0.5 * (1 - 0.30 * v * v)
    pouch('hood', 0.590, 1.000, wfn, 0.068, hood_col(main, trim), off0=0.024, nu=(6 if pip else 8), nv=7, gap=(0.10 if pip else 0.0), peak=0.35)
    if sl: sleeves('s', main, trim)
    return dict(anchor='chest', slot='body', tags=['cute', 'cool'], price=60, title='Yellow raincoat', desc='concept')

# ------------------------------------------------------------------ cardigan
def cardigan(main=hx('#E6D8BC'), trim=hx('#C2AC84'), button=hx('#3B2A22'), pip=False, sleeves_on=False, ridges=True, **k):
    reset()
    dark = deep(trim, 0.40)
    levels = [0.21, 0.245, 0.2465, 0.30, 0.36, 0.44, 0.52, 0.60, 0.66, 0.70]
    CAB = [0.95, 1.30, math.pi - 0.95, math.pi - 1.30, 1.5 * math.pi - 0.55, 1.5 * math.pi, 1.5 * math.pi + 0.55]
    top = lambda phi: top_edge(phi, 0.42, ys=0.74, yb=0.69, x0=0.10, x1=0.43, pw=1.8)
    def off(phi, L, ci):
        if L == 99.0: return 0.020
        if L < 0.2466: return 0.025 + (0.003 if ci % 2 else -0.003)                   # ribbed hem band (geometry ribs)
        return 0.016
    def col(phi, L, p, ci):
        return dark if (L == 99.0 or L < 0.2466) else main
    sl = sleeves_on
    tunic('body', levels, top, off, col, lm=0.36, rib=0.022, slot=(0.42 if pip else None), m_arm=(0.030 if sl else 0.046), snap=CAB, smin=(0.12 if sl else 0.10), smax=(0.40 if sl else 0.38))
    front_line(0.205, 0.425, 0.026, halfw=0.016, name='band', prof=[(-1.0, -0.006), (-0.5, 0.003), (0.5, 0.003), (1.0, -0.006)], nt=9, colfn=lambda t, w: dark)
    # knit texture: narrow raised ridges (2 per front panel, 3 on the back), 3.5 mm proud, each with its own vertex column
    ridge_col = mix(main, deep(main, 0.20), 0.6)
    for ri, ph in enumerate(CAB):
        if not ridges or (pip and abs(wrap(ph - 1.5 * math.pi)) < 0.5): continue
        yt = min(0.60, top(ph) - 0.07)
        def path(t, ph=ph, yt=yt):
            y = 0.285 + (yt - 0.285) * t; c = skin_pt(y, ph, 0.016); d = 1e-3
            c2 = skin_pt(y, ph + d, 0.016); tg = c2 - c; tg /= np.linalg.norm(tg)
            n = B.egg_grad(c); return c, tg, n
        ribbon('ridge%d' % ri, path, 5, 0.0075, [(-1.0, 0.0), (0.0, 0.0035), (1.0, 0.0)], lambda t, w: ridge_col, hint=lambda p: egg_n(p))
    for i, y in enumerate((0.265, 0.325, 0.385)):
        p, n = body_pt(0.0, y, 0.036); xx, yy, nn = axes(n)
        bead('button%d' % i, p, (0.021, 0.021, 0.010), lambda q, nq: mix(button, hx('#7A6256'), 0.35 * max(0.0, nq[2])), rot=np.stack([xx, yy, nn], 1), segs=8)
    if sl: sleeves('s', main, dark)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet'], price=60, title='Cable cardigan', desc='concept')

# ------------------------------------------------------------------ hero cape
def cape(main=None, lining=HONEY, trim=CREAM, pip=False, **k):
    main = main or I7.IO2.RED
    reset()
    ycl = lambda phi: top_edge(phi, 0.47, ys=0.715, yb=0.65, x0=0.15, x1=0.45, pw=1.8)
    COFF = 0.026
    for side in (1, -1):
        end = (0.32 if pip else 0.0)
        def path(t, side=side, end=end):
            def pt(tt): return math.pi / 2 - side * ((math.pi - end) * tt + 0.02)
            ph = pt(t); d = 1e-3
            c = skin_pt(ycl(ph), ph, COFF); c2 = skin_pt(ycl(pt(min(1, t + d))), pt(min(1, t + d)), COFF); c1 = skin_pt(ycl(pt(max(0, t - d))), pt(max(0, t - d)), COFF)
            tg = (c2 - c1); tg /= np.linalg.norm(tg)
            n = B.egg_grad(c); ac = np.cross(tg, n); ac /= np.linalg.norm(ac)
            return c, ac, n
        part = ribbon('collar%+d' % side, path, 40, (lambda t: 0.025 - 0.006 * min(1.0, t * 2.0)), [(-1.0, -0.006), (0.0, 0.007), (1.0, -0.006)],
                      lambda t, w: mix(deep(trim, 0.05), tint(trim, 0.10), 0.5) if abs(w) > 0.9 else mix(deep(main, 0.10), tint(main, 0.14), 0.5 + 0.5 * (1 - abs(w))), hint=lambda p: egg_n(p))
        fold_lips(part, 0.008, 0.005)
    pc, nc = body_pt(0.0, 0.478, 0.046); xx, yy, nn = axes(nc)
    bead('clasp', pc, (0.046, 0.046, 0.016), lambda p, n: mix(deep(HONEY, 0.12), tint(HONEY, 0.25), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=12)
    bead('clasp_gem', pc + nn * 0.012, (0.021, 0.021, 0.009), lambda p, n: mix(deep(CORAL, 0.1), tint(CORAL, 0.35), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=8)
    NU, NV = (6 if pip else 11), 7
    HEM = 0.170
    GAP = 0.55 if pip else 0.30
    def ytop_of(xs): return ycl(1.5 * math.pi + math.asin(max(-0.97, min(0.97, 0.40 * xs / 0.57)))) - 0.012
    def panel_pt(lo, hi, a, b):
        u = a / (NU - 1); v = b / (NV - 1)
        xs = lo + (hi - lo) * u
        ytop = ytop_of(xs); yhem = HEM + 0.022 * math.sin(2 * math.pi * (xs * 0.75) + 0.6)
        y = ytop + (yhem - ytop) * v
        X = (0.40 + 0.05 * v ** 1.4) * xs
        aw = float(B.halfWidth((y - B.lift) / B.bodyH))
        ph = 1.5 * math.pi + math.asin(max(-0.985, min(0.985, X / aw)))
        fold = 0.015 * math.sin(2 * math.pi * 1.75 * xs + 0.5) * (v ** 0.8)
        return skin_h(y, ph, 0.026 + 0.028 * v ** 1.4 + fold)
    halves = [(GAP, 1.0), (-1.0, -GAP)] if pip else [(-1.0, 1.0)]
    for lo, hi in halves:
        cmain = lambda p, n: (mix(deep(main, 0.14), tint(main, 0.14), 0.5 + 0.5 * math.sin(11.0 * p[0] + 0.5)) if p[1] > 0.215 else mix(trim, deep(trim, 0.10), 0.3))
        cin = lambda p, n: mix(deep(lining, 0.08), tint(lining, 0.12), 0.5 + 0.5 * math.sin(6 * p[0]))
        thick_sheet('panel', lambda a, b, lo=lo, hi=hi: panel_pt(lo, hi, a, b), NU, NV, 0.012, cmain, cin)
    ys_ = 0.43; xs0 = (-0.80 if pip else 0.0)
    ytp = ytop_of(xs0); v = (ytp - ys_) / (ytp - HEM); y = ys_
    X = (0.40 + 0.05 * v ** 1.4) * xs0; aw = float(B.halfWidth((y - B.lift) / B.bodyH))
    ph = 1.5 * math.pi + math.asin(max(-0.985, min(0.985, X / aw)))
    cen, h = skin_h(y, ph, 0.026 + 0.028 * v ** 1.4 + 0.006); ax = np.cross(np.array([0, 1.0, 0]), h); ax /= np.linalg.norm(ax)
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
VARIANTS = [('hoodie_sleeves', hoodie, dict(sleeves_on=True), BIB), ('raincoat_sleeves', raincoat, dict(sleeves_on=True), BIB), ('cardigan_cable_sleeves', cardigan, dict(sleeves_on=True), BIB),
            ('hoodie_sleeves_pip', hoodie, dict(sleeves_on=True, pip=True), BIB), ('hoodie_pip', hoodie, dict(pip=True), BIB), ('raincoat_pip', raincoat, dict(pip=True), BIB), ('cardigan_cable_pip', cardigan, dict(pip=True), BIB),
            ('vest_puffer_pip', vest_puffer, dict(pip=True), BIB), ('cape_hero_pip', cape, dict(pip=True), BACK_ANCHOR)]
