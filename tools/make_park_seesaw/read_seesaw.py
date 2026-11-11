#!/usr/bin/env python3
"""Reads a converted decor_seesaw.bin (format: BobV1/Room/DecorMeshes.swift) and prints the contract numbers.
usage: python3 -I read_seesaw.py <decor_seesaw.bin> [contract.txt]"""
import sys, struct, math
import numpy as np

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
    tri = I[first:first + cnt].reshape(-1, 3)
    parts[name] = dict(pivot=(px, py, pz), tri=tri, mat=mat)
out = []
def say(s=""): out.append(s); print(s)

say("file %s: %d verts, %d indices (%d tris), %d parts, %d bytes (parses: size = header + verts + indices)" % (path, nv, ni, ni // 3, npart, len(d)))
say("normals unit-length max err %.4f; ao range %.3f..%.3f; colours linear range %.3f..%.3f" % (abs(np.linalg.norm(V[:, 3:6], axis=1) - 1).max(), V[:, 9].min(), V[:, 9].max(), V[:, 6:9].min(), V[:, 6:9].max()))
total = 0
for name, p in parts.items():
    used = np.unique(p["tri"]); pos = V[used, 0:3]
    p["pos"] = pos; p["used"] = used
    lo, hi = pos.min(0), pos.max(0); total += len(p["tri"])
    say("part %-8s pivot (%.3f, %.3f, %.3f)  tris %4d  bbox x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]" % (name, *p["pivot"], len(p["tri"]), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
say("total triangles %d" % total)
allp = np.vstack([p["pos"] for p in parts.values()])
say("whole footprint: |x| <= %.4f, |z| <= %.4f, max y %.4f" % (abs(allp[:, 0]).max(), abs(allp[:, 2]).max(), allp[:, 1].max()))

def top_y(part, x, z, lowest=False):
    """highest (or lowest) surface y of a part at (x, z) by vertical ray against its triangles"""
    p = parts[part]; T = V[:, 0:3][p["tri"]]
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

say()
def l2s(c): return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 1e-9), 1 / 2.4) - 0.055)
for name, p in parts.items():
    cols = np.unique(np.round(l2s(V[p["used"], 6:9]), 3), axis=0)
    say("stored colour (sRGB) %-8s %s" % (name, " ".join("(%.3f, %.3f, %.3f)" % tuple(c) for c in cols)))
say()
for sx in (-1, 1):
    ys = []
    for x in np.linspace(sx * 0.62 - 0.28, sx * 0.62 + 0.28, 29):
        for z in np.linspace(-0.14, 0.14, 15):
            y = top_y("plank", x, z); ys.append(y)
    ys = np.array(ys, float)
    say("cushion %s: top at sit point (%.2f, 0) = %.4f; flat area |x-%.2f|<=0.28, |z|<=0.14: min %.4f max %.4f (spread %.4f), %d samples" % ("R" if sx > 0 else "L", sx * 0.66, top_y("plank", sx * 0.66, 0), sx * 0.62, ys.min(), ys.max(), ys.max() - ys.min(), len(ys)))
say("beam top at x=0 centre: %.4f, beam underside at x=0: %.4f; plank underside at x=+0.96: %.4f, at x=-0.96: %.4f" % (top_y("plank", 0, 0), top_y("plank", 0, 0, True), top_y("plank", 0.96, 0, True), top_y("plank", -0.96, 0, True)))
beam_z = parts["plank"]["pos"]
# handle vertices: the cream ones
cream = np.array([0.88, 0.84, 0.74]); lc = np.where(cream <= 0.04045, cream / 12.92, ((cream + 0.055) / 1.055) ** 2.4)
pu = parts["plank"]["used"]; isH = np.linalg.norm(V[pu, 6:9] - lc, axis=1) < 0.01
H = V[pu][isH, 0:3]
for sx in (-1, 1):
    h = H[np.sign(H[:, 0]) == sx]
    say("handle %s: x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]  (max |x| %.4f; crossbar top %.4f)" % ("R" if sx > 0 else "L", h[:, 0].min(), h[:, 0].max(), h[:, 1].min(), h[:, 1].max(), h[:, 2].min(), h[:, 2].max(), abs(h[:, 0]).max(), h[:, 1].max()))
say("bumperL rest height %.4f (floor y %.4f), radius %.4f; bumperR rest height %.4f, radius %.4f" % (parts["bumperL"]["pos"][:, 1].max(), parts["bumperL"]["pos"][:, 1].min(), (parts["bumperL"]["pos"][:, 0].max() - parts["bumperL"]["pos"][:, 0].min()) / 2,
    parts["bumperR"]["pos"][:, 1].max(), (parts["bumperR"]["pos"][:, 0].max() - parts["bumperR"]["pos"][:, 0].min()) / 2))
B = parts["base"]["pos"]
say("base: footprint |x| <= %.4f, |z| <= %.4f, block top (max y over |x|<0.2,|z|<0.17) %.4f; cheek tops y %.4f; axle cap outer z %.4f" % (abs(B[:, 0]).max(), abs(B[:, 2]).max(), top_y("base", 0, 0), B[:, 1].max(), abs(B[:, 2]).max()))
# cheek inner faces: base vertices with |x|<0.1 and y>0.25 : their smallest |z|
chk = B[(abs(B[:, 0]) < 0.1) & (B[:, 1] > 0.25)]
cz = np.unique(np.round(abs(B[(abs(B[:, 0]) < 0.12) & (B[:, 1] > 0.25) & (B[:, 1] < 0.45)][:, 2]), 4))
say("cheek inner face |z| min %.4f (contract 0.185); cheek z layers (|z|) %s" % (abs(chk[:, 2]).min(), [float(x) for x in cz]))

# ---- clearance of the plank swinging +-0.26 rad against the base
def samples(part, step):
    p = parts[part]; T = V[:, 0:3][p["tri"]]; pts = [V[p["used"], 0:3]]
    for a, b, c in T:
        n = max(1, int(math.ceil(max(np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c)) / step)))
        for i in range(n + 1):
            for j in range(n + 1 - i):
                u, v = i / n, j / n; pts.append(((1 - u - v) * a + u * b + v * c)[None])
    return np.vstack(pts)
def inside(pts, part):
    T = V[:, 0:3][parts[part]["tri"]]; a, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    dirn = np.array([0.0123, 1.0, 0.0071]); dirn /= np.linalg.norm(dirn)
    pv = np.cross(dirn, e2); det = (e1 * pv).sum(1); okd = np.abs(det) > 1e-12; res = np.zeros(len(pts), bool)
    for k, o in enumerate(pts):
        tv = o - a; u = (tv * pv).sum(1) / np.where(okd, det, 1); qv = np.cross(tv, e1); v = (qv * dirn).sum(1) / np.where(okd, det, 1); t = (qv * e2).sum(1) / np.where(okd, det, 1)
        res[k] = (okd & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)).sum() % 2 == 1
    return res
base_s = samples("base", 0.012); plank_s = samples("plank", 0.02)
piv = np.array([0, 0.34, 0.0]); worst = 9.0; worst_ang = None; viol = 0
sel = (np.abs(plank_s[:, 0]) < 0.55) & (plank_s[:, 1] < 0.62)
ps = plank_s[sel]
try:
    from scipy.spatial import cKDTree
    tree = cKDTree(base_s)
    def mind(P): return tree.query(P)[0].min()
except Exception:
    def mind(P):
        m = 9.0
        for i in range(0, len(P), 200): m = min(m, np.sqrt(((P[i:i + 200, None, :] - base_s[None]) ** 2).sum(2)).min())
        return m
for ang in np.arange(-0.26, 0.2601, 0.02):
    c, s = math.cos(ang), math.sin(ang); q = ps.copy(); x = q[:, 0] - piv[0]; y = q[:, 1] - piv[1]
    q[:, 0] = piv[0] + c * x - s * y; q[:, 1] = piv[1] + s * x + c * y
    ins = inside(q[(q[:, 1] < 0.45) & (np.abs(q[:, 0]) < 0.3)], "base").sum(); viol += ins
    m = mind(q)
    if m < worst: worst, worst_ang = m, ang
say("plank vs base through +-0.26 rad (step 0.02, %d plank samples near the base, %d base samples): points inside the base total %d; smallest surface-to-surface sample distance %.4f at %.2f rad" % (len(ps), len(base_s), viol, worst, worst_ang))
# the contract's own geometric reasons
bt = B[(abs(B[:, 0]) < 0.24)]
wood = np.array([0.64, 0.46, 0.27]); lw = np.where(wood <= 0.04045, wood / 12.92, ((wood + 0.055) / 1.055) ** 2.4)
isW = np.linalg.norm(V[pu, 6:9] - lw, axis=1) < 0.01; bz = abs(V[pu][isW][:, 2]).max()
say("(beam z extent +-%.4f vs cheek inner face %.4f: z gap %.4f at every angle; a rotation about z does not change z)" % (bz, abs(chk[:, 2]).min(), abs(chk[:, 2]).min() - bz))
if len(sys.argv) > 2: open(sys.argv[2], "w").write("\n".join(out) + "\n")
