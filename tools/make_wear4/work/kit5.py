"""Wear sweep (batch 4) kit: thick frames, rounded sweeps and quilting helpers shared by items5.py / items6.py.
Everything is authored in the Jelly's REST space like wl.py (y up, +z = face, world units)."""
from wl import *
import items_other as IO
from items_other import axes, body_pt, FACE_ANCHOR, NECK_ANCHOR, BIB_ANCHOR, _eye_frames
from items2_head import torus, thick_sheet, eloop, hdir, uvsphere, gem, basis_to, phi_of
from items2_other import WAIST_ANCHOR, BACK_ANCHOR
import items_head as IH
from items_head import shell, ribbed

UP = np.array([0, 1, 0.])
H = (0.0, B.top, 0.0)
BLACK = hx('#1E1C24'); GOLD = hx('#E8B84A'); SILVER = hx('#C9D3DC'); STEEL = hx('#9FB0C0'); BONE = hx('#EFE3C8'); NAVY = hx('#2F3E6B')

def spow(v, e):
    return math.copysign(abs(v) ** (2.0 / e), v)

def smooth01(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def lit(c, k=0.18, d=0.12):
    return lambda p, n: mix(deep(c, d), tint(c, k), 0.5 + 0.5 * n[1] * 0.7)

def resample_closed(poly, n):
    P = [np.array(p, float) for p in poly]
    P.append(P[0])
    seg = [np.linalg.norm(P[i + 1] - P[i]) for i in range(len(P) - 1)]
    L = sum(seg)
    out = []
    j = 0
    acc = 0.0
    for k in range(n):
        d = L * k / n
        while j < len(seg) - 1 and acc + seg[j] < d:
            acc += seg[j]
            j += 1
        t = (d - acc) / max(seg[j], 1e-9)
        out.append(P[j] + (P[j + 1] - P[j]) * t)
    return out

def ring_loop(name, c, X, Y, N, outline, wfn, depth, color, n=72, e=2.6, sides=14, zfn=None, ofs=0.0):
    """A thick closed band round a 2D outline (CCW) drawn on the plane (X, Y) at centre c, lifted along N.
    wfn(px, py) = band width at that outline point, depth = half thickness along N, e = squareness of the section."""
    pts = resample_closed(outline, n)
    out = []
    for i in range(n):
        t = pts[(i + 1) % n] - pts[i - 1]
        t = t / max(np.linalg.norm(t), 1e-9)
        o2 = np.array([t[1], -t[0]])
        out.append((pts[i], o2))
    def loopfn(phi):
        i = int(round(phi / (2 * math.pi) * n)) % n
        p, o2 = out[i]
        a = wfn(p[0], p[1]) / 2
        z0 = zfn(p[0], p[1]) if zfn else 0.0
        base = c + X * p[0] + Y * p[1] + N * z0
        ob = X * o2[0] + Y * o2[1]
        ps = []
        for k in range(sides):
            th = 2 * math.pi * k / sides
            ps.append(base + ob * (a * spow(math.cos(th), e) + ofs) + N * (depth * spow(math.sin(th), e)))
        return ps
    return torus(name, n, loopfn, color, sharp=65)

def sweep(name, pts, vdir, hv, ht, color, e=3.0, sides=12, cap=True, radfn=None):
    """A bar along a path: section superellipse hv (along `vdir(p)`, the width of the bar) by ht (thickness across it)."""
    pts = [np.array(p, float) for p in pts]
    n = len(pts)
    P = []
    F = []
    for k, p in enumerate(pts):
        d = pts[min(k + 1, n - 1)] - pts[max(k - 1, 0)]
        d /= np.linalg.norm(d) + 1e-12
        v = np.array(vdir(p), float)
        v = v - d * np.dot(v, d)
        v /= np.linalg.norm(v) + 1e-12
        u = np.cross(d, v)
        s = radfn(k / (n - 1)) if radfn else 1.0
        for i in range(sides):
            a = 2 * math.pi * i / sides
            P.append(p + (v * spow(math.cos(a), e) * hv + u * spow(math.sin(a), e) * ht) * s)
    for k in range(n - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b, c, d = k * sides + i, k * sides + j, (k + 1) * sides + j, (k + 1) * sides + i
            F += [(a, b, c), (a, c, d)]
    if cap:
        for ring, rev in ((0, True), (n - 1, False)):
            ci = len(P)
            P.append(pts[ring])
            base = ring * sides
            for i in range(sides):
                j = (i + 1) % sides
                F.append((ci, base + j, base + i) if rev else (ci, base + i, base + j))
    part = add_part(name, P, F, color, flip_auto=False)
    vol = sum(np.dot(np.array(part['P'][a]), np.cross(np.array(part['P'][b]), np.array(part['P'][c]))) for a, b, c in F)
    if vol < 0:
        part['F'] = [(a, c, b) for a, b, c in part['F']]
        part['N'] = [tuple(-np.array(x)) for x in part['N']]
    return part

def mirror_poly(poly, s):
    """The +x eye's outline for side s (-1 mirrors x and keeps CCW)."""
    if s > 0:
        return list(poly)
    return [(-x, y) for x, y in poly][::-1]

def smooth_poly(pts, rad, arc=5):
    return lib.poly_pts_rounded(pts, rad, arc=arc)

def eye_frames(stand, y_off=-0.006):
    out = []
    for s in (-1, 1):
        c = B.front_surface(s * B.eyeX, B.eyeY + y_off)
        n = full_n(c)
        x, y, n = axes(n)
        out.append((s, c + n * stand, x, y, n))
    return out

def temple_path(frames, s, y, off=0.020, lift=0.0, phi_end=None, dx=0.12):
    """From the outer rim hug the egg round to the side of the head at height y."""
    _, c, x, yy, n = [f for f in frames if f[0] == s][0]
    t = (y - B.lift) / B.bodyH
    a, d = float(B.halfWidth(t)), float(B.halfDepth(t))
    c = c + x * (s * dx)
    ph0 = math.atan2(c[2] / d, c[0] / a)
    if s > 0:
        ph0 = min(ph0, math.radians(80))
    else:
        ph0 = max(ph0, math.radians(100))
    end = phi_end if phi_end is not None else (math.radians(8) if s > 0 else math.radians(172))
    pts = []
    for ph in np.linspace(ph0, end, 8):
        p = B.egg_point(y, ph)
        pts.append(p + egg_n(p) * off)
    return pts

def plate_shell(name, ys, offs, col, segs=40, phi0=0.0, phi1=2 * math.pi, wrap=True):
    """Torso shell conforming to the egg (like items4.torso_shell)."""
    def pt(i, j):
        phi = phi0 + (phi1 - phi0) * (i / segs if wrap else i / (segs - 1))
        e = B.egg_point(ys[j], phi)
        o = offs[j]
        o = o(phi) if callable(o) else o
        return e + hdir(e) * o
    return grid_surface(name, pt, segs, len(ys), col, closed_u=wrap, hint=lambda p: IH.egg_hint(p))

def keepout_value(p):
    """Mouth keep-out ellipse c(0,.651) r(.15,.10): < 1 means inside."""
    return math.hypot((p[0]) / 0.15, (p[1] - 0.651) / 0.10)

def bead(name, c, radii, color, rot=None, segs=8):
    """A cheap ellipsoid (a revolved 5-ring profile, ~segs*6 tris): radii = (x, y, z) in the local frame, rot = columns (x, y, z) in rest space."""
    rx, ry, rz = radii
    prof = [(0.0, -ry), (rx * 0.80, -ry * 0.62), (rx, 0.0), (rx * 0.80, ry * 0.62), (0.0, ry)]
    return lathe_y(name, prof, segs, color, centre=tuple(c), scale=(1.0, rz / max(rx, 1e-6)), rotm=(None if rot is None else np.array(rot).tolist()), sharp=85)

def dome_round(name, c, r, color, segs=8):
    return bead(name, c, (r, r, r), color, segs=segs)

PIP_MODE = False

def pip_rise(phi):
    """Pip variants only: the loop climbs the back in a smooth arch (up to 0.60 higher at the back centre) to pass over his tail root and his back spike."""
    if not PIP_MODE: return 0.0
    th = (phi - 1.5 * math.pi + math.pi) % (2 * math.pi) - math.pi
    return 0.60 * math.exp(-(th / 0.6) ** 2)

def neck_y(phi, front, side=0.50, back=0.56):
    """Height of a neck-line loop round the body at angle phi (pi/2 = front): dips to `front` at the front, `side` round the sides, rises to `back` at
    the back centre so it rides over Pip's tail root and passes between Lavender's wings."""
    s = math.sin(phi)
    f = max(0.0, s) ** 2
    b = max(0.0, -s) ** 8
    return side - (side - front) * f + (back - side) * b + pip_rise(phi)

def ring_pt(phi, front, off, side=0.50, back=0.56):
    y = neck_y(phi, front, side, back)
    e = B.egg_point(y, phi)
    return e + hdir(e) * off

def ring_frame(phi, front, off, side=0.50, back=0.56):
    """(point, tangent, outward, up) on a neck-line loop."""
    p = ring_pt(phi, front, off, side, back)
    d = 0.01
    t = ring_pt(phi - d, front, off, side, back) - ring_pt(phi + d, front, off, side, back)      # screen-right at the front (+x)
    t = t / np.linalg.norm(t)
    h = hdir(p)
    up = np.cross(h, t)
    up = up / np.linalg.norm(up)
    return p, t, h, up

def stroke_poly(path, w, cap_n=6):
    """Outline of a thick stroke along a 2D polyline with round ends (CCW)."""
    P = [np.array(p, float) for p in path]
    n = len(P)
    L, R, tans = [], [], []
    for i in range(n):
        t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        t = t / np.linalg.norm(t)
        tans.append(t)
        o = np.array([-t[1], t[0]])
        L.append(P[i] + o * w / 2)
        R.append(P[i] - o * w / 2)
    def cap(c, t):
        o = np.array([-t[1], t[0]])
        return [c + (o * math.sin(math.pi / 2 - math.pi * k / cap_n) + t * math.cos(math.pi / 2 - math.pi * k / cap_n)) * w / 2 for k in range(1, cap_n)]
    out = R + cap(P[-1], tans[-1]) + L[::-1] + cap(P[0], -tans[0])
    return [tuple(q) for q in out]

def gem(name, c, r, color, rot=None, sides=5):
    """A small faceted-looking bipyramid brilliant (about 10 triangles)."""
    prof = [(0.0, -r * 0.85), (r, 0.0), (r * 0.55, r * 0.40), (0.0, r * 0.46)]
    return lathe_y(name, prof, sides, color, centre=tuple(c), rotm=(None if rot is None else np.array(rot).tolist()), sharp=88)

