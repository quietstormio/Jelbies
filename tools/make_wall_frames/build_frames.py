"""Wall picture frames (2026-11-20): Natural wood, White, Pastel, Gold (ornate), each built for three shapes (portrait 3:4, square, landscape 4:3).
Headless Blender, game orientation: the frame stands in the xy plane, +z toward the room, z = 0 is the wall side, the picture opening is centred on the
origin and is 1.0 high (the game scales the whole piece uniformly by the picture's height, so a corner never stretches). Mitred / rounded corners come from
lofting ONE closed moulding profile around the opening, so the straight runs and the corners are the same surface.

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_frames.py -- [frame ids ...]

Exports frame_<id>_<shape>.obj + .json to $DECOR_EXPORT (default tools/make_wall_frames/export). Then:
  python3 tools/convert_wall_frames.py tools/make_wall_frames/export BobV1/Room/Resources     -> wallframe_<id>_<shape>.bin
"""
import sys, os, math, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dk
from dk import *
import numpy as np

SHAPES = {"portrait": 0.75, "square": 1.0, "landscape": 4.0 / 3.0}      # opening width / opening height (the opening is 1.0 high)
HH = 0.5

def loop(hw, hh, d, rc0, arc_n, run_n):
    """One closed loop around the opening, offset outward by d: a rounded rectangle (arc_n = 1 gives a mitred sharp corner)."""
    X, Y = hw + d, hh + d
    rc = rc0 + d if rc0 > 0 else 0.0
    pts = []
    corners = [((X - rc, -(Y - rc)), -90), ((X - rc, Y - rc), 0), ((-(X - rc), Y - rc), 90), ((-(X - rc), -(Y - rc)), 180)]
    ends = []
    for (cx, cy), a0 in corners:
        arc = []
        if arc_n == 1 or rc <= 1e-6:
            sx = 1 if cx >= 0 else -1; sy = 1 if cy >= 0 else -1
            arc = [(sx * X, sy * Y)] if arc_n == 1 else [(sx * X, sy * Y)] * arc_n
        else:
            for k in range(arc_n):
                t = math.radians(a0 + 90.0 * k / (arc_n - 1))
                arc.append((cx + rc * math.cos(t), cy + rc * math.sin(t)))
        ends.append(arc)
    for i in range(4):
        a = ends[i]; b = ends[(i + 1) % 4]
        pts += a
        p0 = a[-1]; p1 = b[0]
        for k in range(1, run_n + 1):
            t = k / (run_n + 1)
            pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    return pts

def moulding(hw, profile, color, rc0=0.0, arc_n=1, run_n=5, sharp=50):
    """Loft the closed (d, z) profile around the opening as a closed solid."""
    bm = bmesh.new()
    rings = []
    for d, z in profile:
        ring = [bm.verts.new((x, y, z)) for x, y in loop(hw, HH, d, rc0, arc_n, run_n)]
        rings.append(ring)
    n = len(rings[0]); m = len(rings)
    for k in range(m):
        k2 = (k + 1) % m
        for i in range(n):
            j = (i + 1) % n
            vs = [rings[k][i], rings[k][j], rings[k2][j], rings[k2][i]]
            u = []
            for v in vs:
                if v not in u: u.append(v)
            if len(u) >= 3 and len(set(tuple(v.co) for v in u)) >= 3:
                try: bm.faces.new(u)
                except ValueError: pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    return commit(bm, color, sharp=sharp)

# ---- colours ---------------------------------------------------------------
def lite(c, up=0.20, dn=0.16):
    """Lit from the upper left: faces that look up / left take a lighter tone, faces that look down / right a deeper one."""
    def f(p, n):
        k = 0.5 + 0.5 * max(-1.0, min(1.0, n.y * 0.65 - n.x * 0.35))
        return mix(deep(c, dn), tint(c, up), k)
    return f

WOODA = hx('#D8AC78'); WOODB = hx('#B2825A')
def wood_color(hw):
    def f(p, n):
        horiz = abs(p.y) / (HH + 0.1) > abs(p.x) / (hw + 0.1)
        u = (p.x, p.y * 36.0, p.z * 8.0) if horiz else (p.x * 36.0, p.y, p.z * 8.0)
        g = lib.nz(u, 1.0, 3.7) * 0.5 + 0.5
        g2 = lib.nz((u[0] * 2.3, u[1] * 2.3, u[2]), 1.0, 9.1) * 0.5 + 0.5
        base = mix(WOODB, WOODA, 0.25 + 0.55 * g * 0.7 + 0.3 * g2 * 0.5)
        return lite(base, 0.16, 0.14)(p, n)
    return f

def build_wood(hw):
    prof = [(0, 0), (0, 0.030), (0.008, 0.041), (0.020, 0.046), (0.034, 0.046), (0.050, 0.052), (0.064, 0.050), (0.072, 0.040), (0.075, 0.026), (0.075, 0)]
    prof = [(d * 1.25, z) for d, z in prof]
    moulding(hw, prof, wood_color(hw), run_n=7)
    return 0.075 * 1.25, 0.052

def build_white(hw):
    prof = [(0, 0), (0, 0.028), (0.005, 0.036), (0.014, 0.036), (0.020, 0.028), (0.030, 0.028), (0.088, 0.030), (0.098, 0.034), (0.100, 0.026), (0.100, 0)]
    moulding(hw, prof, lite(hx('#F4F0E6'), 0.10, 0.12), run_n=4)
    return 0.100, 0.036

def build_pastel(hw):
    prof = [(0, 0), (0, 0.020)]
    for k in range(1, 12):
        t = k / 12.0
        prof.append((0.095 * t, 0.020 + 0.050 * math.sin(math.pi * t) ** 0.8))
    prof += [(0.095, 0.020), (0.095, 0)]
    moulding(hw, prof, lite(hx('#F5B8C8'), 0.22, 0.10), rc0=0.035, arc_n=7, run_n=5, sharp=80)
    return 0.095, 0.070

def gold_color(c, hi, lo):
    def f(p, n):
        k = 0.5 + 0.5 * max(-1.0, min(1.0, n.y * 0.6 - n.x * 0.3 + n.z * 0.25))
        v = 0.5 + 0.5 * lib.nz((p.x * 9, p.y * 9, p.z * 9), 1.0, 2.2)
        return mix(mix(lo, c, min(1.0, k * 1.25)), hi, max(0.0, (k - 0.5) * 2.2) * (0.7 + 0.3 * v))
    return f

def build_gold(hw):
    GOLD = hx('#D8A22C'); GHI = hx('#FFF0A6'); GLO = hx('#6F430A')
    prof = [(0, 0), (0, 0.030), (0.010, 0.048), (0.026, 0.056), (0.036, 0.046), (0.044, 0.040), (0.056, 0.060), (0.074, 0.076),
            (0.095, 0.080), (0.112, 0.066), (0.122, 0.050), (0.128, 0.052), (0.136, 0.062), (0.146, 0.060), (0.154, 0.046), (0.160, 0.030), (0.160, 0)]
    col = gold_color(GOLD, GHI, GLO)
    moulding(hw, prof, col, run_n=8)
    # corner rosettes (a domed disc, a boss and a ring of petals) and a smaller medallion in the middle of each run
    def rosette(cx, cy, R, z):
        add_sph((cx, cy, z), (R, R, R * 0.38), col, sub=2)
        add_sph((cx, cy, z + R * 0.30), (R * 0.46, R * 0.46, R * 0.40), col, sub=2)
        for k in range(8):
            a = 2 * math.pi * k / 8
            add_sph((cx + R * 0.78 * math.cos(a), cy + R * 0.78 * math.sin(a), z - R * 0.02), (R * 0.28, R * 0.28, R * 0.22), col, sub=1)
    c = 0.080
    for sx in (-1, 1):
        for sy in (-1, 1): rosette(sx * (hw + c), sy * (HH + c), 0.105, 0.074)
    for sy in (-1, 1): rosette(0, sy * (HH + c), 0.060, 0.074)
    for sx in (-1, 1): rosette(sx * (hw + c), 0, 0.060, 0.074)
    return 0.160 + 0.025, 0.080 + 0.014          # (the rosettes stand a little beyond the moulding)

REG = [("wood", build_wood), ("white", build_white), ("pastel", build_pastel), ("gold", build_gold)]

def export_frame(iid, meta, depth):
    P = []; N = []; C = []
    for g in dk.GROUPS:
        for p in g['parts']:
            for q, n, c in zip(p['P'], p['N'], p['C']): P.append(q); N.append(n); C.append(c)
    faces = []; off = 0
    for g in dk.GROUPS:
        for p in g['parts']:
            faces += [(a + off, b + off, c + off) for a, b, c in p['F']]; off += len(p['P'])
    P = np.array(P); Nn = np.array(N)
    # ambient occlusion: the part of the moulding that is near the wall is darker (the reveal), the front is open
    ao = np.clip(0.80 + 0.20 * np.clip(P[:, 2] / depth, 0, 1), 0.7, 1.0)
    os.makedirs(dk.OUT, exist_ok=True)
    with open(f"{dk.OUT}/{iid}.obj", "w") as fh:
        fh.write(f"# {iid}: opening 1.0 high centred on the origin, +z toward the room, z = 0 on the wall. v x y z r g b ao w (rgb LINEAR)\n")
        for q, c, a in zip(P, C, ao): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f %.3f %.3f\n" % (*q, *lin(c), a, 0.0))
        for n in Nn: fh.write("vn %.4f %.4f %.4f\n" % tuple(n))
        fh.write("o frame\n")
        for a, b, c in faces: fh.write("f %d//%d %d//%d %d//%d\n" % (a + 1, a + 1, b + 1, b + 1, c + 1, c + 1))
    mn = P.min(0); mx = P.max(0)
    info = dict(id=iid, tris=len(faces), verts=len(P), sub_meshes=[dict(name="frame", pivot=[0, 0, 0], material="plain", tris=len(faces))],
                bounds_min=[round(float(x), 4) for x in mn], bounds_max=[round(float(x), 4) for x in mx])
    info.update(meta)
    json.dump(info, open(f"{dk.OUT}/{iid}.json", "w"), indent=1)
    return info

if __name__ == "__main__":
    only = [a for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []) if not a.startswith("-") and a in dict(REG)]
    for fid, fn in REG:
        if only and fid not in only: continue
        for shape, ratio in SHAPES.items():
            dk.reset(); dk.begin('frame')
            border, depth = fn(ratio / 2.0)
            info = export_frame(f"frame_{fid}_{shape}", dict(border=border, opening_w=ratio, opening_h=1.0), depth)
            print("EXPORT", fid, shape, info["tris"], info["verts"], info["bounds_min"], info["bounds_max"], flush=True)
            if "--preview" in sys.argv and shape in ("portrait", "landscape"):
                import preview; preview.render(f"frame_{fid}_{shape}", sys.argv[sys.argv.index("--preview") + 1])
