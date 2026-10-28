"""Batch 4 new pieces (2026-10-27): Viking helmet, cable-knit pom beanie, tennis visor, quilted puffer vest, cable cardigan, silk patterned neck scarf,
chunky gold chain, quilted crossbody bag. Abstract shapes only: no logos, no brand marks."""
from kit5 import *
from items2_head import torus, thick_sheet
from items_head import shell

NEW = ('viking_hat', 'beanie_cable', 'visor_tennis', 'vest_puffer', 'cardigan_cable', 'scarf_silk', 'chain_gold', 'bag_crossbody')

def egg_pt(y, phi, off=0.0):
    p = B.egg_point(y, phi)
    return p + hdir(p) * off

# ============================ VIKING HELMET ====================================
def viking(steel=hx('#A9B8C8'), band=hx('#6C7C8E'), horn=BONE, rivet=hx('#E1B65A'), **k):
    reset(); segs = 24
    y0 = lambda phi: 1.050 + 0.034 * math.sin(phi)
    rows = [('a', 0.012, 0.012), ('a', -0.004, 0.034), ('a', 0.016, 0.062), ('a', 0.070, 0.076)]
    for f, o in ((0.0, 0.092), (0.30, 0.140), (0.60, 0.170), (0.84, 0.170), (0.96, 0.150)): rows.append(('k', f, o))
    rows.append(('pole', 0, 0.130))
    def col(p, n):
        h = (p[1] - 1.10) / 0.40
        return mix(deep(steel, 0.30), tint(steel, 0.55), 0.20 + 0.80 * max(0.0, min(1.0, h * 0.8 + 0.5 * max(0, n[1]))))
    shell('dome', segs, y0, rows, col)
    def bl(phi):
        yb = y0(phi)
        return [eloop(yb, phi, h, v) for h, v in ((0.040, -0.026), (0.080, -0.026), (0.092, -0.006), (0.092, 0.066), (0.082, 0.084), (0.044, 0.082))]
    torus('band', segs, bl, lambda p, n: mix(deep(band, 0.22), tint(band, 0.30), 0.35 + 0.65 * max(0, n[1] * 0.5 + 0.5)), sharp=55)
    for i_, ph in enumerate((math.radians(55), math.radians(125), math.radians(20), math.radians(160))):
        bead('rivet%d' % i_, eloop(y0(ph) + 0.030, ph, 0.100, 0.0), (0.016, 0.016, 0.013), rivet, segs=6)
    pb = eloop(y0(math.pi / 2) + 0.030, math.pi / 2, 0.100, 0.0)
    lathe_y('boss', [(0.0, 0.0), (0.052, 0.0), (0.056, 0.010), (0.044, 0.026), (0.0, 0.030)], 12, lambda p, n: mix(deep(rivet, 0.15), tint(rivet, 0.25), 0.5 + 0.5 * n[1]), centre=tuple(pb), rotm=np.array(rot_x(math.pi / 2)).tolist(), sharp=60)
    for s in (-1, 1):
        phi = 0.0 if s > 0 else math.pi
        base = egg_pt(1.108, phi, 0.092)
        bead('cup%+d' % s, base + np.array([s * 0.014, 0, 0]), (0.062, 0.066, 0.060), lambda p, n: mix(deep(band, 0.2), tint(band, 0.3), 0.5 + 0.5 * n[1]), segs=8)
        pth = [base + np.array([s * dx, dy, dz]) for dx, dy, dz in ((0.0, 0.0, 0.0), (0.075, 0.020, 0.004), (0.140, 0.075, 0.016), (0.182, 0.155, 0.034), (0.196, 0.245, 0.056), (0.186, 0.325, 0.080), (0.172, 0.372, 0.092))]
        def hcol(p, n, base=base):
            t = max(0.0, min(1.0, (p[1] - base[1]) / 0.40))
            c = mix(horn, hx('#D6C396'), t * 0.6)
            return mix(deep(c, 0.12), tint(c, 0.2), 0.5 + 0.5 * n[1] * 0.5)
        tube_curve('horn%+d' % s, pth, 0.066, 8, hcol, cap=True, radfn=lambda t: 0.066 * (1 - t) ** 0.8 + 0.012, flat=0.95)
    return dict(anchor='head_top', slot='head', tags=['cool', 'sporty'], price=80, title='Viking helmet',
                desc='A proper rounded steel dome (crown about 0.12 above the head, enclosing it: CrownFit) with a thick rolled brim band (no nose guard), golden rivets and a front boss, topped by two curved bone horns on metal cups. Front band edge y~1.08, above the brows.')

# ============================ CABLE-KNIT POM BEANIE ===========================
def beanie_cable(main=hx('#F1E6D2'), cuff=hx('#E4D3B6'), pom=hx('#FBF6EE'), **k):
    reset(); segs = 28
    y0 = lambda phi: 1.012 + 0.04 * math.sin(phi)
    rows = [('a', 0.010, 0.006), ('a', -0.002, 0.026), ('a', 0.012, 0.050), ('a', 0.048, ribbed(0.060, 0.005, 16)), ('a', 0.090, ribbed(0.056, 0.005, 16)), ('a', 0.100, 0.046)]
    # the cables: twisted ridges that run up the crown (a phase shift per row makes them braid)
    for j, (f, o) in enumerate(((0.0, 0.052), (0.14, 0.058), (0.28, 0.062), (0.42, 0.063), (0.56, 0.062), (0.70, 0.058), (0.82, 0.052), (0.92, 0.044), (0.975, 0.034))):
        rows.append(('k', f, (lambda ph, j=j, o=o: o + 0.012 * math.cos(8 * ph + 0.95 * j) * (1 - 0.5 * j / 8.0))))
    rows.append(('pole', 0, 0.026))
    def col(p, n):
        phi = math.atan2(p[2], p[0]); dy = p[1] - y0(phi)
        if dy < 0.10:
            rib = 0.5 + 0.5 * math.cos(16 * phi)
            return mix(cuff, deep(cuff, 0.16), 0.40 * (1 - rib))
        # cable stripes: darker valleys between braids
        v = 0.5 + 0.5 * math.cos(8 * phi + 0.95 * max(0, (p[1] - 1.1) / 0.035))
        return mix(deep(main, 0.30), tint(main, 0.10), 0.20 + 0.80 * v)
    shell('knit', segs, y0, rows, col)
    # a big fluffy pom on a short tail at the back so the crown stays clear (Moss's sprout sits on top)
    yp = 1.28
    c = egg_pt(yp, 3 * math.pi / 2, 0.040) + np.array([0, 0.060, -0.065])
    ico_part('pom', tuple(c), (0.110, 0.105, 0.110), lambda p, n: mix(deep(pom, 0.10), pom, 0.5 + 0.5 * n[1]), sub=1, fuzz=0.08, seed=7)
    return dict(anchor='head_top', slot='head', tags=['cute', 'sweet'], price=45, title='Cable-knit beanie',
                desc='Cream cable-knit beanie: braided ridges up the crown, a ribbed cuff and a fluffy pom on a tail at the back (the crown stays free for the sprout). Cuff edge above the brows.')

# ============================ TENNIS VISOR ====================================
def visor(band=hx('#F7F3EA'), brim=hx('#F7F3EA'), under=hx('#3C6E8F'), trim=hx('#E96C6C'), **k):
    reset(); segs = 40
    y0 = lambda phi: 1.050 + 0.026 * math.sin(phi)
    def lp(phi):
        yb = y0(phi)
        return [eloop(yb, phi, h, v) for h, v in ((0.030, -0.026), (0.052, -0.030), (0.062, -0.016), (0.062, 0.036), (0.050, 0.050), (0.030, 0.046))]
    torus('band', segs, lp, lambda p, n: mix(deep(band, 0.10), tint(band, 0.1), 0.5 + 0.5 * n[1] * 0.6), sharp=60)
    # sweat stripe
    torus('stripe', segs, lambda phi: [eloop(y0(phi) + 0.014, phi, h, v) for h, v in ((0.0625, -0.003), (0.0665, 0.0), (0.0665, 0.014), (0.0625, 0.017))], trim, sharp=60)
    # the brim: a curved bill that sweeps forward and a little down, rounded front corners
    nu, nv = 17, 6
    def fn(i, j):
        u = i / (nu - 1) * 2 - 1                     # across, -1..1
        v = j / (nv - 1)                              # 0 at the band, 1 at the edge
        phi = math.pi / 2 - u * math.radians(62)
        base = B.egg_point(y0(phi) + 0.020, phi)
        h = hdir(base)
        reach = (0.040 + 0.250 * (v ** 1.0)) * (1 - 0.30 * abs(u) ** 2.6) * (1.0)
        drop = -0.050 * v ** 1.6 - 0.030 * v * abs(u) ** 2
        p = base + h * (0.056 + reach) + np.array([0, drop, 0])
        n = h * 0.4 + np.array([0, 1.0, 0])
        return p, n / np.linalg.norm(n)
    thick_sheet('bill', fn, nu, nv, 0.026, lambda p, n: brim, color_in=lambda p, n: under)
    return dict(anchor='head_top', slot='head', tags=['sporty', 'cute'], price=35, title='Tennis visor',
                desc='White tennis visor: a soft headband with a coral sweat stripe and a curved bill with a blue underside, open on top so the crown (and the sprout) stay free. Perching piece (never moved by CrownFit). Bill edge above the brows.')

# ============================ VEST + CARDIGAN (front-opening garments with armholes) =====
def angd(a, b):
    return abs((a - b + math.pi) % (2 * math.pi) - math.pi)

def top_edge(phi, front=0.505, back=0.625, notch=0.335, vtip=0.445, vhalf=0.34, side_half=0.56):
    """The garment's top edge round the body (phi 0 = +x, pi/2 = front): the front panels reach y .505 with only a shallow V at the centre (nothing on the
    front above y .51), deep armhole notches round the arm nubs at the sides, and a higher back (the collar side)."""
    side = min(angd(phi, 0.0), angd(phi, math.pi))
    base = 0.565 - 0.06 * max(-1.0, min(1.0, math.sin(phi) * 3.0))
    y = notch + (base - notch) * smooth01(0.0, side_half, side)
    df = angd(phi, math.pi / 2)
    if base < 0.54 and df < vhalf:
        y = min(y, vtip + (front - vtip) * smooth01(0.0, vhalf, df))
    return y

def garment(main, trim, pat, ybot, off_fn, name, segs=30, rows=11, collar=0.022, pip=False, hem_rows=2):
    """Rows 0..hem_rows-1 are the ribbed hem band. pip=True: Pip's tail leaves the lower back (y~0.47), so his garment is open at the back (a tail slot)."""
    if pip:
        p0, p1 = math.radians(312.0), math.radians(312.0 + 276.0)
        segs = 28
    else:
        p0, p1 = 0.0, 2 * math.pi
    def phi_i(i): return p0 + (p1 - p0) * (i / (segs - 1 if pip else segs))
    def pt(i, j):
        phi = phi_i(i)
        yt = top_edge(phi)
        f = j / (rows - 1)
        y = ybot + (yt - ybot) * f
        e = B.egg_point(y, phi)
        return e + hdir(e) * off_fn(phi, f, j)
    grid_surface(name, pt, segs, rows, None, closed_u=not pip, hint=lambda p: IH.egg_hint(p), gcol=lambda i, j: (mix(deep(trim, 0.2), trim, 0.5 + 0.5 * math.cos(26 * phi_i(i))) if j < hem_rows else pat(i, j, segs, rows)))
    n_t = 36 if pip else 44
    pts = []
    for q in range(n_t + 1):
        phi = p0 + (p1 - p0) * q / n_t
        e = B.egg_point(top_edge(phi), phi)
        pts.append(e + hdir(e) * (off_fn(phi, 1.0, rows - 1) + 0.006))
    tube_curve('edge', pts, collar, 4, lambda p, n: mix(deep(trim, 0.15), tint(trim, 0.22), 0.5 + 0.5 * n[1]), cap=True)
    # the vertical front opening: a placket band down the middle from the hem to the V
    cp = []
    for t in np.linspace(0.0, 1.0, 8):
        y = ybot + 0.012 + (top_edge(math.pi / 2) - ybot - 0.012) * t
        e = B.egg_point(y, math.pi / 2)
        cp.append(e + hdir(e) * (off_fn(math.pi / 2, t, min(rows - 1, int(t * (rows - 1)))) + 0.010))
    tube_curve('placket', cp, 0.020, 4, lambda p, n: mix(deep(trim, 0.2), tint(trim, 0.25), 0.5 + 0.5 * n[1]), cap=True)
    if pip:
        for k_, phi in enumerate((p0, p1)):
            col_pts = []
            for f in np.linspace(0.0, 1.0, 5):
                y = ybot + (top_edge(phi) - ybot) * f
                e = B.egg_point(y, phi)
                col_pts.append(e + hdir(e) * (off_fn(phi, f, int(f * (rows - 1))) + 0.004))
            tube_curve('slot%d' % k_, col_pts, collar * 0.8, 4, lambda p, n: mix(deep(trim, 0.15), tint(trim, 0.22), 0.5 + 0.5 * n[1]), cap=True)
    return cp

def vest_puffer(main=hx('#2E7C85'), trim=hx('#1F5760'), zip_=GOLD, pip=False, **k):
    reset()
    ybot = 0.205
    BAFF = 4.0
    def puff(ff):
        # a pillow profile: rounded crest, pinched seam
        return abs(math.sin(math.pi * BAFF * ff)) ** 0.6
    def off(phi, f, j):
        if j < 2: return 0.040 + 0.010 * math.cos(26 * phi) * 0.5 + 0.006
        ff = (f - 0.2) / 0.8
        return 0.036 + 0.030 * puff(ff) * (0.85 + 0.15 * math.cos(10 * phi))
    def pat(i, j, segs, rows):
        f = (j / (rows - 1) - 0.2) / 0.8
        w = puff(f)
        # soft sheen on the crest of every baffle, deep teal in the seams
        return mix(deep(main, 0.55), mix(tint(main, 0.55), (0.85, 1.0, 1.0), 0.25), 0.05 + 0.95 * w ** 1.6)
    cp = garment(main, trim, pat, ybot, off, 'body', segs=30, rows=13, collar=0.022, pip=pip)
    # a clear zip: dark tape either side of a gold chain of teeth, and a big pull
    zp = [c + np.array([0.0, 0.0, 0.016]) for c in cp]
    tube_curve('zip', zp, 0.013, 4, lambda p, n: mix(deep(zip_, 0.25), tint(zip_, 0.4), 0.5 + 0.5 * n[2]), cap=True)
    bead('pull', zp[-2] + np.array([0.0, -0.036, 0.016]), (0.024, 0.044, 0.016), lambda p, n: mix(deep(zip_, 0.2), tint(zip_, 0.6), 0.5 + 0.5 * n[2]), segs=6)
    return dict(anchor='chest', slot='body', tags=['cool', 'sporty'], price=65, title='Puffer vest',
                desc='A teal puffer vest with four puffy horizontal quilted baffles (soft sheen on the crests, pinched seams) from a ribbed hem band (y 0.2) up to the front panels at y 0.505 with a shallow V, deep armholes round the arm nubs, a higher back with a piped collar edge and a chunky gold zip with a big pull down the middle front. Pip variant: open over his tail root.')

def cardigan(main=hx('#E6D8BC'), trim=hx('#C2AC84'), button=hx('#3B2A22'), pip=False, **k):
    reset()
    ybot = 0.195
    CAB = (0.60, 1.0, 1.55, 3.20, 4.55, 5.20, 5.85)           # three narrow cable columns on the front panels and a pair at the back (phi in radians)
    def cab(phi):
        w = 0.0
        for c in CAB:
            d = angd(phi, c)
            w = max(w, math.exp(-(d / 0.085) ** 2))
        return w
    def off(phi, f, j):
        if j < 2: return 0.040 + 0.010 * math.cos(26 * phi) * 0.5 + 0.006
        return 0.040 + 0.007 * cab(phi) * (0.6 + 0.4 * math.cos(30 * f))
    def pat(i, j, segs, rows):
        phi = 2 * math.pi * i / segs
        w = cab(phi)
        return mix(tint(main, 0.06), deep(main, 0.22), 0.55 * w)
    cp = garment(main, trim, pat, ybot, off, 'body', segs=30, rows=11, collar=0.024, pip=pip)
    for i_ in range(5):
        t = (i_ + 0.5) / 5
        c = cp[min(len(cp) - 1, int(t * (len(cp) - 1) + 0.5))]
        bead('button%d' % i_, c + np.array([0.0, 0.0, 0.022]), (0.030, 0.030, 0.015), lambda p, n: mix(button, hx('#7A6256'), 0.35 * max(0.0, n[2])), segs=6)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet'], price=60, title='Cable cardigan',
                desc='A soft oatmeal knit cardigan: mostly smooth, with just a few subtle vertical cable lines, a ribbed hem band (y 0.2), a darker-oatmeal button placket down the middle front with five dark buttons, front panels up to y 0.505 with a shallow V, deep armholes round the arm nubs and a higher back with a collar edge. Pip variant: open over his tail root.')

# ============================ CROSSBODY BAG ====================================
def bag_crossbody(main=hx('#F0D9B5'), strap=hx('#8B5A3C'), gold=GOLD, **k):
    reset()
    # strap: from the left shoulder (ends tucked behind the arm root) down across the belly to the bag at the right hip
    a = np.array([-0.42, 0.600]); b = np.array([0.300, 0.282])
    d = (b - a) / np.linalg.norm(b - a); perp = np.array([-d[1], d[0]])
    nL = 17; W_ = 0.052
    rows = [(-1.0, 0.016), (-0.7, 0.026), (-0.3, 0.030), (0.3, 0.030), (0.7, 0.026), (1.0, 0.016)]
    def pt(i, j):
        t = i / (nL - 1); w, off = rows[j]
        q = a + (b - a) * t + perp * W_ * w
        p, n = body_pt(q[0], q[1], off); return p
    grid_surface('strap', pt, nL, len(rows), strap, closed_u=False, hint=lambda p: full_n(p), gcol=lambda i, j: mix(deep(strap, 0.12), tint(strap, 0.14), 0.5 + 0.1 * (j - 2.5)))
    for t in np.linspace(0.06, 0.94, 13):
        q = a + (b - a) * t
        p, n = body_pt(q[0] + perp[0] * W_ * 0.9, q[1] + perp[1] * W_ * 0.9, 0.032)
    for s in (-1, 1):
        pts = []
        for t in np.linspace(0.0, 1.0, 14):
            q = a + (b - a) * t + perp * W_ * 0.80 * s
            pts.append(body_pt(q[0], q[1], 0.030)[0])
        tube_curve('stitch%+d' % s, pts, 0.0035, 4, deep(strap, 0.3), cap=True)
    # the bag: a puffy quilted pouch at the right hip, hung on the strap end
    c, n = body_pt(0.290, 0.222, 0.0)
    xx, yy, z = axes(n)
    ctr = c + z * 0.056
    Rm = np.stack([xx, yy, z], 1)
    nu, nv = 14, 12
    hw, hh, dp = 0.150, 0.114, 0.062
    def bp(i, j):
        ph = 2 * math.pi * i / nu; th = -math.pi / 2 + math.pi * j / (nv - 1)
        e = 0.42
        ux = spow(math.cos(th) * math.cos(ph), 2 / (2 * e) * 1.0) if False else math.copysign(abs(math.cos(th) * math.cos(ph)) ** 0.45, math.cos(th) * math.cos(ph))
        uy = math.copysign(abs(math.cos(th) * math.sin(ph)) ** 0.45, math.cos(th) * math.sin(ph))
        uz = math.copysign(abs(math.sin(th)) ** 0.5, math.sin(th))
        quilt = 1 + 0.07 * math.cos(2 * math.pi * ux * 2.0) * math.cos(2 * math.pi * uy * 2.0) * (abs(uz) > 0.2)
        return ctr + Rm @ np.array([hw * ux, hh * uy, dp * uz * quilt])
    def bcol(p, n_):
        q = Rm.T @ (np.array(p) - ctr)
        qx = (q[0] / hw) * 2.0; qy = (q[1] / hh) * 2.0
        v = 0.5 + 0.5 * math.cos(2 * math.pi * qx) * math.cos(2 * math.pi * qy)
        return mix(deep(main, 0.22), tint(main, 0.16), 0.30 + 0.70 * v)
    grid_surface('pouch', bp, nu, nv, bcol, hint=lambda p: np.array(p) - ctr)
    # flap + gold clasp + hanging ring where the strap joins
    fl = [ctr + Rm @ np.array([hw * 1.0 * math.cos(a_), hh * 0.30 + hh * 0.70 * math.sin(a_), dp * 0.96]) for a_ in np.linspace(math.pi * 1.05, math.pi * 1.95, 9)]
    tube_curve('flap', [ctr + Rm @ np.array([x_, hh * 0.18 - 0.02 * (1 - (x_ / hw) ** 2), dp * 0.98]) for x_ in np.linspace(-hw * 0.96, hw * 0.96, 13)], 0.0085, 6, deep(main, 0.30), cap=True)
    p_cl = ctr + Rm @ np.array([0, hh * 0.18 - 0.02, dp * 1.06])
    lathe_y('clasp', [(0.0, 0.0), (0.030, 0.0), (0.033, 0.008), (0.026, 0.016), (0.0, 0.019)], 16, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p_cl), rotm=np.stack([xx, z, -yy], 1).tolist(), sharp=55)
    p_ring = ctr + Rm @ np.array([-hw * 0.78, hh * 0.80, dp * 0.35])
    ico_part('ring', tuple(p_ring), (0.024, 0.024, 0.016), gold, sub=1)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet', 'sparkly'], price=75, title='Quilted crossbody bag',
                desc='A small quilted cream bag with a gold clasp, hung at the right hip on a brown strap that crosses the belly from the left shoulder (ends tucked behind the arm root). Strap top y 0.60 at the side, 0.45 at the centre line: below the mouth keep-out.')

VARIANTS = [('vest_puffer_pip', vest_puffer, dict(pip=True), BIB_ANCHOR), ('cardigan_cable_pip', cardigan, dict(pip=True), BIB_ANCHOR)]
REG = [
    ('viking_hat', viking, dict(), H),
    ('beanie_cable', beanie_cable, dict(), H),
    ('visor_tennis', visor, dict(), H),
    ('vest_puffer', vest_puffer, dict(), BIB_ANCHOR),
    ('cardigan_cable', cardigan, dict(), BIB_ANCHOR),
    ('bag_crossbody', bag_crossbody, dict(), BIB_ANCHOR),
]
