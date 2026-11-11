#!/usr/bin/env python3
"""Reads a converted decor_seesaw.bin (format: BobV1/Room/DecorMeshes.swift), prints the contract-v2 numbers and CHECKS them (non-zero exit on a miss).
usage: python3 -I read_seesaw.py <decor_seesaw.bin> [contract.txt]

Game posing rule at plank angle th (about z through the plank pivot, positive raises +x):
  plank = rotated by th; each seat = translated by d(th) = R(th) h - h, h = seat pivot - plank pivot (never rotated);
  each bumper = scaled in y about its floor pivot so its top stays just under the plank's underside."""
import sys, struct, math
import numpy as np
from scipy.spatial import cKDTree

path = sys.argv[1]
d = open(path, "rb").read()
nv, ni, npart = struct.unpack_from("<III", d, 0)
headEnd = 12 + npart * 40; vertEnd = headEnd + nv * 44
assert len(d) == vertEnd + ni * 2 and ni % 3 == 0, "size mismatch: file does not parse"
V = np.frombuffer(d, dtype="<f4", count=nv * 11, offset=headEnd).reshape(nv, 11).astype(float)
I = np.frombuffer(d, dtype="<u2", count=ni, offset=vertEnd).astype(int)
parts = {}
for p in range(npart):
    name, first, cnt, mat, px, py, pz = struct.unpack_from("<16sIII3f", d, 12 + p * 40)
    name = name.split(b"\0")[0].decode()
    parts[name] = dict(pivot=np.array((px, py, pz), float), tri=I[first:first + cnt].reshape(-1, 3), mat=mat)
out = []; fails = []
def say(s=""): out.append(s); print(s)
def check(label, ok, detail=""):
    say("  CHECK %-62s %s %s" % (label, "ok" if ok else "MISS", detail))
    if not ok: fails.append(label)

say("file %s: %d verts, %d indices (%d tris), %d parts, %d bytes (parses: size = header + verts + indices)" % (path, nv, ni, ni // 3, npart, len(d)))
say("normals unit-length max err %.4f; ao range %.3f..%.3f; colours linear range %.3f..%.3f" % (abs(np.linalg.norm(V[:, 3:6], axis=1) - 1).max(), V[:, 9].min(), V[:, 9].max(), V[:, 6:9].min(), V[:, 6:9].max()))
total = 0
for name, p in parts.items():
    used = np.unique(p["tri"]); pos = V[used, 0:3]
    p["pos"] = pos; p["used"] = used
    lo, hi = pos.min(0), pos.max(0); total += len(p["tri"])
    say("part %-8s pivot (%.4f, %.4f, %.4f)  tris %4d  bbox x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]" % (name, *p["pivot"], len(p["tri"]), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
say("total triangles %d" % total)
check("six parts in order", list(parts.keys()) == ["base", "plank", "bumperL", "bumperR", "seatL", "seatR"], str(list(parts.keys())))
check("pivots", all(np.allclose(parts[n]["pivot"], v, atol=1e-4) for n, v in [("plank", (0, 0.27, 0)), ("seatL", (-0.62, 0.3775, 0)), ("seatR", (0.62, 0.3775, 0)), ("bumperL", (-0.96, 0, 0)), ("bumperR", (0.96, 0, 0))]))
check("total triangles <= 1750 (1900 acceptable)", total <= 1900, "(%d)" % total)
allp = np.vstack([p["pos"] for p in parts.values()])
say("whole footprint: |x| <= %.4f, |z| <= %.4f, max y %.4f" % (abs(allp[:, 0]).max(), abs(allp[:, 2]).max(), allp[:, 1].max()))

def tris_of(part, mask=None):
    T = V[:, 0:3][parts[part]["tri"]]
    return T if mask is None else T[mask]

def top_y(part, x, z, lowest=False, T=None):
    """highest (or lowest) surface y at (x, z) by vertical ray against triangles"""
    T = tris_of(part) if T is None else T
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    d0 = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    ok = np.abs(d0) > 1e-12
    l1 = ((b[:, 2] - c[:, 2]) * (x - c[:, 0]) + (c[:, 0] - b[:, 0]) * (z - c[:, 2])) / np.where(ok, d0, 1)
    l2 = ((c[:, 2] - a[:, 2]) * (x - c[:, 0]) + (a[:, 0] - c[:, 0]) * (z - c[:, 2])) / np.where(ok, d0, 1)
    l3 = 1 - l1 - l2; e = -1e-9
    hit = ok & (l1 >= e) & (l2 >= e) & (l3 >= e)
    if not hit.any(): return None
    ys = l1[hit] * a[hit, 1] + l2[hit] * b[hit, 1] + l3[hit] * c[hit, 1]
    return ys.min() if lowest else ys.max()

def srgb2lin(c): c = np.array(c); return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
LC = {"cream": srgb2lin((0.88, 0.84, 0.74)), "terra": srgb2lin((0.72, 0.41, 0.28)), "wood": srgb2lin((0.64, 0.46, 0.27))}
def tri_is(part, cname):
    """mask of the part's triangles whose first vertex has the palette colour"""
    return np.linalg.norm(V[parts[part]["tri"][:, 0], 6:9] - LC[cname], axis=1) < 0.01

say()
def l2s(c): return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 1e-9), 1 / 2.4) - 0.055)
for name, p in parts.items():
    cols = np.unique(np.round(l2s(V[p["used"], 6:9]), 3), axis=0)
    say("stored colour (sRGB) %-8s %s" % (name, " ".join("(%.3f, %.3f, %.3f)" % tuple(c) for c in cols)))
say()

# ---- seats: pad (terracotta) and barrel (cream)
for sx, nm in ((-1, "seatL"), (1, "seatR")):
    padT = tris_of(nm, tri_is(nm, "terra")); barT = tris_of(nm, tri_is(nm, "cream"))
    ys = []
    for x in np.linspace(sx * 0.62 - 0.28, sx * 0.62 + 0.28, 29):
        for z in np.linspace(-0.14, 0.14, 15): ys.append(top_y(nm, x, z, T=padT))
    ys = np.array(ys, float); sit = top_y(nm, sx * 0.66, 0, T=padT)
    say("%s pad: top at sit point (%.2f, 0) = %.4f; flat area |x-%.2f|<=0.28, |z|<=0.14: min %.4f max %.4f (spread %.4f), %d samples" % (nm, sx * 0.66, sit, sx * 0.62, ys.min(), ys.max(), ys.max() - ys.min(), len(ys)))
    check(nm + " sit top 0.475 +-0.004 and flat +-0.004", abs(sit - 0.475) <= 0.004 and abs(ys.min() - 0.475) <= 0.004 and abs(ys.max() - 0.475) <= 0.004)
    pv = padT.reshape(-1, 3); lowest = pv[:, 1].min()
    say("%s pad underside lowest y %.4f (barrel excluded); pad x[%.4f, %.4f] z[%.4f, %.4f]" % (nm, lowest, pv[:, 0].min(), pv[:, 0].max(), pv[:, 2].min(), pv[:, 2].max()))
    check(nm + " pad underside 0.410 +-0.003", abs(lowest - 0.410) <= 0.003)
    check(nm + " pad x range 0.27..0.97", abs(min(abs(pv[:, 0])) - 0.27) < 0.003 and abs(max(abs(pv[:, 0])) - 0.97) < 0.003)
    bv = barT.reshape(-1, 3); cyl = bv[abs(bv[:, 2]) < 0.12]
    cx = (cyl[:, 0].min() + cyl[:, 0].max()) / 2; cy = (cyl[:, 1].min() + cyl[:, 1].max()) / 2; rr = (cyl[:, 1].max() - cyl[:, 1].min()) / 2
    say("%s barrel: centre (%.4f, %.4f), radius %.4f (round-1 text said 0.0325 touching; 0.035 = sunk a hair), z extent [%.4f, %.4f], x[%.4f, %.4f]" % (nm, cx, cy, rr, bv[:, 2].min(), bv[:, 2].max(), bv[:, 0].min(), bv[:, 0].max()))
    check(nm + " barrel centre (+-0.62, 0.3775), r 0.0325..0.036, |z|<=0.17", abs(cx - sx * 0.62) < 0.002 and abs(cy - 0.3775) < 0.002 and 0.0325 <= rr <= 0.036 and abs(bv[:, 2]).max() <= 0.17)
    check(nm + " barrel touches/sinks into beam top and pad underside", cy - rr <= 0.345 + 1e-4 and cy + rr >= 0.410 - 1e-4, "(bottom %.4f, top %.4f)" % (cy - rr, cy + rr))

# ---- beam and handles
bm = tri_is("plank", "wood"); beamT = tris_of("plank", bm)
tb0 = top_y("plank", 0, 0, T=beamT); ub0 = top_y("plank", 0, 0, True, T=beamT)
tbp = top_y("plank", 0.96, 0, T=beamT); tbm = top_y("plank", -0.96, 0, T=beamT); ubp = top_y("plank", 0.96, 0, True, T=beamT); ubm = top_y("plank", -0.96, 0, True, T=beamT)
say("beam top at x=0: %.4f, underside x=0: %.4f; at x=+0.96 top %.4f underside %.4f; at x=-0.96 top %.4f underside %.4f" % (tb0, ub0, tbp, ubp, tbm, ubm))
check("beam top 0.345 / underside 0.255 at x=0 and +-0.96", all(abs(v - w) < 0.002 for v, w in [(tb0, 0.345), (ub0, 0.255), (tbp, 0.345), (tbm, 0.345), (ubp, 0.255), (ubm, 0.255)]))
bp = beamT.reshape(-1, 3)
check("beam x +-1.05, z +-0.17", abs(bp[:, 0].max() - 1.05) < 0.002 and abs(bp[:, 0].min() + 1.05) < 0.002 and abs(abs(bp[:, 2]).max() - 0.17) < 0.002)
ch = tri_is("plank", "cream"); handleT = tris_of("plank", ch)
H = handleT.reshape(-1, 3)
for sx in (-1, 1):
    h = H[np.sign(H[:, 0]) == sx]
    say("handle %s: x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]  (max |x| %.4f; crossbar top %.4f)" % ("R" if sx > 0 else "L", h[:, 0].min(), h[:, 0].max(), h[:, 1].min(), h[:, 1].max(), h[:, 2].min(), h[:, 2].max(), abs(h[:, 0]).max(), h[:, 1].max()))
    check("handle %s top 0.6347 +-0.002, |x| <= 0.235, flare bottom 0.332" % ("R" if sx > 0 else "L"), abs(h[:, 1].max() - 0.6347) <= 0.002 and abs(h[:, 0]).max() <= 0.235 and abs(h[:, 1].min() - 0.332) < 0.002)
bH = [parts[n]["pos"][:, 1].max() for n in ("bumperL", "bumperR")]
say("bumperL rest height %.4f (floor y %.4f), radius %.4f; bumperR rest height %.4f, radius %.4f" % (bH[0], parts["bumperL"]["pos"][:, 1].min(), (parts["bumperL"]["pos"][:, 0].max() - parts["bumperL"]["pos"][:, 0].min()) / 2,
    bH[1], (parts["bumperR"]["pos"][:, 0].max() - parts["bumperR"]["pos"][:, 0].min()) / 2))
check("bumpers 0.11 high, r 0.10, centres +-0.96", all(abs(v - 0.11) < 0.001 for v in bH))

B = parts["base"]["pos"]
say("base: footprint |x| <= %.4f, |z| <= %.4f, block top (y at x=0,z=0) %.4f; cheek tops y %.4f; axle cap outer z %.4f" % (abs(B[:, 0]).max(), abs(B[:, 2]).max(), top_y("base", 0, 0), B[:, 1].max(), abs(B[:, 2]).max()))
check("base block top 0.15, cheek tops 0.37, |x| <= 0.24", abs(top_y("base", 0, 0) - 0.15) < 0.002 and abs(B[:, 1].max() - 0.37) < 0.002 and abs(B[:, 0]).max() <= 0.24)
chk = B[(abs(B[:, 0]) < 0.1) & (B[:, 1] > 0.2)]
say("cheek inner face |z| min %.4f (contract 0.185)" % abs(chk[:, 2]).min())
check("cheek inner face 0.185", abs(abs(chk[:, 2]).min() - 0.185) < 0.002)
ax = B[(abs(B[:, 2]) > 0.25) & (B[:, 1] > 0.2)]   # axle caps only (the block's z reaches 0.27 too, but below 0.15)
say("axle caps: centre y %.4f (contract 0.27)" % ((ax[:, 1].min() + ax[:, 1].max()) / 2))
check("axle on the pivot y 0.27", abs((ax[:, 1].min() + ax[:, 1].max()) / 2 - 0.27) < 0.002)

# ---- the two angles, from the measured numbers
PY = parts["plank"]["pivot"][1]; dep = PY - ub0; bh = max(bH)
def solve(Hh):
    lo, hi = 0.0, 0.6
    for _ in range(60):
        m = (lo + hi) / 2
        if PY - 0.96 * math.tan(m) - dep / math.cos(m) > Hh: lo = m
        else: hi = m
    return lo
touch = solve(bh); big = solve(0.77 * bh)
say("angle of first touch (underside meets bumper top %.3f at x 0.96): %.4f rad; largest ride angle (bumper pressed to 77%% = %.4f): %.4f rad" % (bh, touch, 0.77 * bh, big))
check("first touch ~0.150, largest ~0.176 (+-0.002)", abs(touch - 0.150) <= 0.002 and abs(big - 0.176) <= 0.002)

# ---- clearances under the game's posing rule
def sample(T, step):
    pts = [T.reshape(-1, 3)]
    for a, b, c in T:
        n = max(1, int(math.ceil(max(np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c)) / step)))
        for i in range(n + 1):
            for j in range(n + 1 - i):
                u, v = i / n, j / n; pts.append(((1 - u - v) * a + u * b + v * c)[None])
    return np.vstack(pts)
def rotz(P, th, piv):
    c, s = math.cos(th), math.sin(th); q = P.copy(); x = P[:, 0] - piv[0]; y = P[:, 1] - piv[1]
    q[:, 0] = piv[0] + c * x - s * y; q[:, 1] = piv[1] + s * x + c * y; return q
def inside(pts, part):
    T = tris_of(part); a, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    dirn = np.array([0.0123, 1.0, 0.0071]); dirn /= np.linalg.norm(dirn)
    pv = np.cross(dirn, e2); det = (e1 * pv).sum(1); okd = np.abs(det) > 1e-12; res = np.zeros(len(pts), bool)
    for k, o in enumerate(pts):
        tv = o - a; u = (tv * pv).sum(1) / np.where(okd, det, 1); qv = np.cross(tv, e1); v = (qv * dirn).sum(1) / np.where(okd, det, 1); t = (qv * e2).sum(1) / np.where(okd, det, 1)
        res[k] = (okd & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)).sum() % 2 == 1
    return res

piv = parts["plank"]["pivot"]; ANG = np.arange(-0.19, 0.1901, 0.01)
base_s = sample(tris_of("base"), 0.012); tree_base = cKDTree(base_s)
plank_s = sample(tris_of("plank"), 0.02); ps = plank_s[(np.abs(plank_s[:, 0]) < 0.55) & (plank_s[:, 1] < 0.62)]
beam_s = sample(beamT, 0.008)
beam_top_s = beam_s  # all beam surface samples; the nearest ones to a pad underside are the top face

# (a) plank vs base
worst = 9.0; wa = None; viol = 0
for th in ANG:
    q = rotz(ps, th, piv); viol += inside(q[(q[:, 1] < 0.40) & (np.abs(q[:, 0]) < 0.3)], "base").sum()
    m = tree_base.query(q)[0].min()
    if m < worst: worst, wa = m, th
say()
say("(a) plank vs base, theta -0.19..+0.19 step 0.01: points inside the base total %d; smallest surface-to-surface sample distance %.4f at %+.2f rad" % (viol, worst, wa))
check("(a) plank never inside the base, distance >= 0.01", viol == 0 and worst >= 0.01)

# (b) pad vs beam, (c) seat vs handle on its side, (d) low seat vs ground and pressed bumper, (e) seat vs base
bw = {}; cw = {}; dg = (9.0, None); dbm = (9.0, None); ew = (9.0, None); hfloor = (9.0, None)
for sx, nm in ((-1, "seatL"), (1, "seatR")):
    padT = tris_of(nm, tri_is(nm, "terra")); pad_s = sample(padT, 0.015); seat_s = sample(tris_of(nm), 0.015)
    hv = np.array([sx * 0.62, parts[nm]["pivot"][1] - PY, 0.0])
    hand_s = sample(handleT[np.sign(handleT[:, 0, 0] + handleT[:, 1, 0] + handleT[:, 2, 0]) == sx], 0.012)
    bw[nm] = (9.0, None); cw[nm] = (9.0, None)
    for th in ANG:
        c, s = math.cos(th), math.sin(th)
        dd = np.array([c * hv[0] - s * hv[1] - hv[0], s * hv[0] + c * hv[1] - hv[1], 0.0])
        padq = pad_s + dd; seatq = seat_s + dd
        beamq = cKDTree(rotz(beam_top_s, th, piv))
        mb = beamq.query(padq)[0].min()
        if mb < bw[nm][0]: bw[nm] = (mb, th)
        handq = cKDTree(rotz(hand_s, th, piv))
        mc = handq.query(seatq)[0].min()
        if mc < cw[nm][0]: cw[nm] = (mc, th)
        me = tree_base.query(seatq)[0].min()
        if me < ew[0]: ew = (me, th, nm)
        # ground and pressed bumper: the seat is the LOW one when the plank end on its side is down (th>0 lowers -x)
        low = (th > 0 and sx < 0) or (th < 0 and sx > 0)
        if low:
            gmin = seatq[:, 1].min()
            if gmin < dg[0]: dg = (gmin, th)
            # bumper under this seat: scaled so its top stays just under the underside line at the bumper's x
            bx = sx * 0.96; bname = "bumperL" if sx < 0 else "bumperR"
            Pb = parts[bname]["pos"]; k = 1.0
            for x, y in zip(Pb[:, 0], Pb[:, 1]):
                if y < 0.01: continue
                yu = PY + x * math.tan(th) - dep / math.cos(th); k = min(k, (yu - 0.004) / y)
            k = max(k, 0.0); top = k * bh
            near = seatq[np.hypot(seatq[:, 0] - bx, seatq[:, 2]) <= 0.10]
            clr = (near[:, 1].min() - top) if len(near) else 9.0
            if clr < dbm[0]: dbm = (clr, th, nm, k)
for nm in ("seatL", "seatR"):
    say("(b) %s PAD vs rotated beam: smallest distance %.4f at %+.2f rad (>= 0.004 required)" % (nm, *bw[nm]))
    check("(b) %s pad vs beam >= 0.004" % nm, bw[nm][0] >= 0.004)
for nm in ("seatL", "seatR"):
    say("(c) %s vs rotated handle on its side: smallest distance %.4f at %+.2f rad (>= 0.02 required)" % (nm, *cw[nm]))
    check("(c) %s vs handle >= 0.02" % nm, cw[nm][0] >= 0.02)
say("(d) low seat lowest point above ground y=0: lowest %.4f at %+.2f rad; low seat above the pressed bumper top: smallest clearance %.4f at %+.2f rad (%s, bumper scale %.3f)" % (dg[0], dg[1], dbm[0], dbm[1], dbm[2], dbm[3]))
check("(d) low seat above ground and pressed bumper", dg[0] > 0 and dbm[0] > 0)
say("(e) extra: any seat vs the base: smallest distance %.4f at %+.2f rad (%s)" % (ew[0], ew[1], ew[2]))
check("(e) seat vs base >= 0.01", ew[0] >= 0.01)
say("RESULT: %s" % ("ALL CHECKS PASS" if not fails else "%d MISS: %s" % (len(fails), "; ".join(fails))))
if len(sys.argv) > 2: open(sys.argv[2], "w").write("\n".join(out) + "\n")
sys.exit(1 if fails else 0)
