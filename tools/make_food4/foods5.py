"""Hand-held replacements (2026-11-16, the owner: "Remove foods in bowls it looks weird because they eat with hands").
Cinnamon roll (was the Ramen bowl), Fruit skewer (was the Fruit cup; Mac & cheese went to the existing Donut), plus the café's Ice cream cone (replaces the
sundae's cup, same id `sundae`) and Jelly puff (replaces the Jelly Cup, id `jellycup`). One piece per mesh, same conventions as foods4.py:
Blender units (x10 = game units), z up, bottom sits on z = 0, piece fits inside +-0.8 across and about 1.5 high like the cupcake and the donut.
Register in foods.BUILD; run.py exports them:  FOOD4_OUT=<dir> blender -b -P run.py -- cinnamonroll fruitskewer sundae jellycup"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import foods
from foods4 import blob, sweep, rr_slab, subdiv, scale_all, BEV
V = Vector
BUILD = {}

def catmull(pts, per=10, closed=False):
    P = [V(p) for p in pts]; n = len(P); out = []
    rng = range(n) if closed else range(n-1)
    for i in rng:
        p0 = P[(i-1) % n] if (closed or i > 0) else P[0]
        p1 = P[i]; p2 = P[(i+1) % n]
        p3 = P[(i+2) % n] if (closed or i+2 < n) else P[-1]
        for k in range(per):
            t = k/per; t2 = t*t; t3 = t2*t
            out.append(0.5*((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3))
    if not closed: out.append(P[-1])
    return out

def ribbon(path, w, h, corner=0.05, bulge=0.0, flare=0.0):
    """A band standing on its edge along an xy path (z = base height of the band): rounded rectangle cross-section w wide (radial) and h tall.
    w and h may be functions of the sample index i (a band that thins out or shrinks toward its end)."""
    n = len(path)
    bm = bmesh.new(); rings = []
    m = None
    for i, p in enumerate(path):
        wi = w(i) if callable(w) else w; hi = h(i) if callable(h) else h
        sec = poly_pts_rounded([(-wi/2, 0), (wi/2, 0), (wi/2, hi), (-wi/2, hi)], min(corner, hi*0.45, wi*0.45), 3)
        m = len(sec)
        d = (path[min(i+1, n-1)] - path[max(i-1, 0)]); d.z = 0; d.normalize()
        u = V((d.y, -d.x, 0))
        rings.append([bm.verts.new(V((p.x, p.y, p.z)) + u*(cx*(1.0 + bulge*math.sin(math.pi*min(max(cz/hi, 0.0), 1.0)) + flare*(1.0 - min(max(cz/hi, 0.0), 1.0))**2)) + V((0, 0, cz))) for (cx, cz) in sec])
    for i in range(n-1):
        for k in range(m):
            j = (k+1) % m
            bm.faces.new([rings[i][k], rings[i][j], rings[i+1][j], rings[i+1][k]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    return bm

# ================================================================ CINNAMON ROLL v4 (was: Ramen bowl)
def cinnamonroll(v=0):
    """A puffy bakery roll: a fat rounded dough rope coiled 3.3 turns round a small core. Every turn bulges out and each one sits a little higher than the one outside it,
    so the side shows stacked rounded layers (never a straight wall), the base is a touch wider, the strip ends as a low tail on the outer edge, and a dark cinnamon-sugar
    line runs in every crease. Soft, flat melted glaze follows the swirl (plus a pool in the middle) with three short drips; a few cinnamon specks on top."""
    pitch = 0.172; r0 = 0.12; turns = 3.3
    th_end = turns*2*math.pi
    def rad(th): return r0 + pitch*th/(2*math.pi) + 0.016*math.sin(th*1.9 + 0.7) + 0.010*math.sin(th*4.6)
    def pt(th, off=0.0): return V(((rad(th) + off)*math.cos(th), (rad(th) + off)*math.sin(th), 0.0))
    def hgt(r): return 0.70 - 0.37*min(1.0, (r/0.80)**1.2)                                                       # the crown of the turn at radius r: each turn higher than the one outside
    N = 110
    ths = [th_end*i/N for i in range(N+1)]
    dough = [pt(t) for t in ths]
    def puff(t): return 1.0 + 0.06*math.sin(t*1.0 + 0.4) + 0.035*math.sin(t*2.7)
    def tail(i): return sstep(0.90, 0.985, i/N)
    def dh(i): return hgt(rad(ths[i]))*puff(ths[i])*(1.0 - 0.50*tail(i))
    def dw(i): return 0.196*(1.0 + 0.07*math.sin(ths[i]*1.3))*(1.0 - 0.22*tail(i))
    def dc(p, n):
        r = math.hypot(p.x, p.y)
        golden = mix((0.93, 0.68, 0.34), (0.99, 0.80, 0.46), sstep(0.2, 1.0, nz(p, 5.0, 1))*0.6)
        if n.z > 0.65: return mix(golden, (0.99, 0.82, 0.50), sstep(0.6, 1.0, n.z)*0.5)
        if n.z > 0.15: return mix((0.62, 0.32, 0.10), (0.80, 0.46, 0.16), sstep(0.15, 0.65, n.z))                 # caramelised shoulders
        return mix((0.78, 0.48, 0.20), (0.92, 0.66, 0.32), sstep(0.02, 0.30, p.z))                               # a toasted foot, golden above
    commit(ribbon(dough, dw, dh, 0.09, flare=0.22), dc, mods=BEV(0.015, 2), sharp=70)
    # the cinnamon-sugar line: dark, thin, deep in every crease between two turns (the creases are where the ropes meet)
    fth = [(th_end - 2*math.pi - 0.3)*i/70 for i in range(71)]
    fill = [pt(t, pitch*0.5) for t in fth]
    def fh(i): return max(0.10, hgt(rad(fth[i]) + pitch*0.5)*puff(fth[i]) - 0.045)
    commit(ribbon(fill, 0.052, fh, 0.02), lambda p, n: mix((0.34, 0.16, 0.06), (0.52, 0.28, 0.12), sstep(0.3, 1.0, nz(p, 12.0, 2))*0.7), sharp=60)
    core = lathe([(0, 0), (0.10, 0), (0.11, 0.04), (0.11, 0.58), (0.08, 0.66), (0, 0.68)], 16)
    commit(core, lambda p, n: (0.96, 0.74, 0.40) if n.z > 0.5 else (0.84, 0.54, 0.24), sharp=60)
    # glaze: a soft pool in the middle and a wide, flat, melted strip following the crown of the coil
    CREAM = lambda p, n: mix((0.97, 0.93, 0.86), (1.0, 0.995, 0.97), sstep(0.2, 1.0, n.z))
    commit(blob(0.27, 0.25, 0.075, 3), CREAM, sharp=80, xf=xf_rt((0.0, 0.0, hgt(0.0) - 0.065)))
    i0 = int(N*0.20); i1 = int(N*0.90)
    strip = [V((dough[i].x, dough[i].y, dh(i) - 0.050)) for i in range(i0, i1)]
    def gw(j): return 0.050 + 0.060*(0.5 + 0.5*math.sin(j*0.19 + 1.0))*(0.7 + 0.3*math.sin(j*0.07)) 
    commit(ribbon(strip, gw, 0.070, 0.030), CREAM, mods=BEV(0.014, 2), sharp=60)
    # three short, soft drips of uneven length hanging on the outer wall (rounded ends)
    for frac, L, wd in ((0.885, 0.20, 0.060), (0.79, 0.11, 0.052), (0.70, 0.16, 0.056)):
        i = int(N*frac); q = dough[i]; aa = math.atan2(q.y, q.x); ro = math.hypot(q.x, q.y) + dw(i)*0.5 - 0.004
        zr = dh(i)
        cx = ro*math.cos(aa); cy = ro*math.sin(aa)
        # one smooth teardrop: wide where it leaves the glaze, tapering to a rounded tip
        rt = wd*0.86
        prof = [(0.0, -L - rt)]
        for k in range(1, 6):
            ph = math.radians(90 - 18*k)                                # rounded bulb at the tip
            prof.append((rt*math.cos(ph), -L - rt*math.sin(ph)*1.0))
        for k in range(1, 10):
            t = 1.0 - k/9.0                                             # body: wide at the top, tapering to the bulb
            prof.append((rt + (wd*1.12 - rt)*(1.0 - t)**0.9, -L*t))
        cap = wd*1.12
        for k in range(1, 6):
            ph = math.radians(18*k)
            prof.append((cap*math.cos(ph), cap*0.8*math.sin(ph)))          # a rounded top that melts into the glaze
        drip = lathe(prof, 14)
        commit(drip, (1.0, 0.985, 0.95), sharp=80, xf=xf_rt((cx, cy, zr - 0.055), rotz=aa, scale=(0.75, 1.0, 1.0)))
    # a few small cinnamon specks, scattered unevenly on the glaze strip and the dough (none on the pool, none side by side)
    r = random.Random(5)
    for frac, jit in ((0.29, 0.010), (0.37, -0.012), (0.49, 0.006), (0.58, -0.008), (0.69, 0.012), (0.80, -0.006), (0.84, 0.010)):
        i = int(N*frac); q = dough[i]
        commit(blob(0.017, 0.013, 0.008, 1), (0.34, 0.16, 0.06), sharp=80,
               xf=xf_rt((q.x*(1 + jit), q.y*(1 + jit), dh(i) + 0.018), rotz=r.uniform(0, 3.1)))
    scale_all(0.97)
BUILD['cinnamonroll'] = cinnamonroll

# ================================================================ FRUIT SKEWER (was: Fruit cup)
def fruitskewer(v=0):
    zc = 0.30                                                          # height of the skewer's axis
    # the bamboo stick, a round knob at the left end and a point at the right
    tube((-0.84, 0, zc), (0.56, 0, zc), 0.032, 8, (0.88, 0.70, 0.42))
    commit(blob(0.07, 0.06, 0.06, 2), (0.80, 0.60, 0.34), sharp=80, xf=xf_rt((-0.85, 0, zc)))
    # (kept short on purpose: three of these lie end to end on the plate, so one must be shorter than the spacing)
    # 1. a strawberry, point to the right, green leaves at the left
    bm = ico(4)
    def sb(p):
        t = (p.z + 1)/2                                                # 0 at the leafy end ... 1 at the tip
        k = 1.0 - 0.80*max(0.0, (t - 0.45)/0.55)**1.5
        return (p.z*0.30 - 0.60, p.x*0.285*k, zc + p.y*0.265*k)
    move(bm, sb)
    def sc(p, n):
        if p.x > -0.62 and False: return (0.9, 0.14, 0.22)
        return mix((0.90, 0.12, 0.20), (1.0, 0.34, 0.36), sstep(0.1, 0.9, n.z)*0.6)
    commit(bm, sc, sharp=70)
    for k in range(18):
        th = 2.4*k; u = (k % 6)/6.0
        x = -0.60 + (-0.24 + 0.52*(0.1 + 0.8*u)); ang = th
        yy = math.cos(ang); zz = math.sin(ang)
        t = (x + 0.84)/0.60
        rr = 0.285*(1.0 - 0.80*max(0.0, (t - 0.45)/0.55)**1.5) + 0.004
        commit(blob(0.012, 0.016, 0.009, 1), (1.0, 0.88, 0.50), sharp=80, xf=xf_rt((x, rr*yy*0.97, zc + rr*0.93*zz), rotx=ang))
    for k in range(5):                                                   # the leafy top
        a = 2*math.pi*k/5
        commit(blob(0.12, 0.05, 0.016, 2), (0.34, 0.70, 0.28), sharp=80, xf=xf_rt((-0.84, 0.13*math.cos(a), zc + 0.13*math.sin(a)), rotx=a, rotz=0.0) @ xf_rt((0.06, 0, 0)))
    # 2. a cube of pineapple
    cx = -0.20
    bm = rr_slab(0.155, 0.155, -0.155, 0.155, 0.045)
    me_xf = xf_rt((cx, 0, zc), rotz=0.15, rotx=math.pi/2, roty=0.3)
    # rr_slab stands along z; a cube is cube, so just rotate it a little for a casual look
    displace(bm, lambda p, n: 0.012*nz(p, 14.0, 4) if True else None)
    commit(bm, lambda p, n: mix((1.0, 0.86, 0.30), (1.0, 0.95, 0.55), sstep(0.2, 1.0, n.z)*0.7) if n.z > -0.4 else (0.96, 0.78, 0.20), mods=BEV(0.04, 2), sharp=60, xf=me_xf)
    for k in range(5):                                                   # little pineapple pits on the faces
        commit(blob(0.022, 0.022, 0.01, 1), (0.92, 0.68, 0.16), sharp=80, xf=xf_rt((cx + (k-2)*0.05, -0.15, zc + (0.08 if k % 2 else -0.06)), rotx=math.pi/2))
    # 3. a kiwi slice, face toward the camera of the skewer line (disc across the stick)
    kx = 0.15
    bm = lathe([(0, -0.07), (0.30, -0.07), (0.32, -0.05), (0.32, 0.05), (0.30, 0.07), (0, 0.07)], 40)
    def kc(p, n):
        if abs(n.x) < 0.5: return (0.46, 0.38, 0.20)                                     # the furry skin
        d = math.hypot(p.y, p.z - zc)
        c = mix((1.0, 0.97, 0.80), (0.52, 0.82, 0.22), sstep(0.04, 0.16, d))
        c = mix(c, (0.38, 0.70, 0.14), sstep(0.19, 0.29, d))
        return mix(c, (0.46, 0.38, 0.20), sstep(0.29, 0.32, d))
    commit(bm, kc, sharp=70, xf=xf_rt((kx, 0, zc), roty=math.pi/2))
    for k in range(12):
        a = 2*math.pi*k/12
        commit(blob(0.020, 0.012, 0.010, 1), (0.08, 0.07, 0.05), sharp=80, xf=xf_rt((kx - 0.073, 0.115*math.cos(a), zc + 0.115*math.sin(a)), rotx=a))
        commit(blob(0.020, 0.012, 0.010, 1), (0.08, 0.07, 0.05), sharp=80, xf=xf_rt((kx + 0.073, 0.115*math.cos(a), zc + 0.115*math.sin(a)), rotx=a))
    scale_all(0.95)
BUILD['fruitskewer'] = fruitskewer

# ================================================================ ICE CREAM CONE (the café's sundae slot)
def icecream(v=0):
    Hc = 0.62
    prof = [(0.12, 0.0), (0.17, 0.0)]
    for i in range(1, 13):
        t = i/12; prof.append((0.17 + 0.26*t**0.9, Hc*t))
    prof += [(0.44, Hc + 0.02), (0.42, Hc + 0.04), (0.0, Hc - 0.04)]
    bm = lathe(prof, 72)
    def wc(p, n):
        a = math.atan2(p.y, p.x); z = p.z
        l = math.sin(a*5.0 + z*17.0); m = math.sin(a*5.0 - z*17.0)
        if z > Hc - 0.015: return (0.80, 0.55, 0.26)
        line = min(abs(l), abs(m))
        return (0.70, 0.43, 0.18) if line < 0.20 else mix((0.93, 0.72, 0.40), (0.88, 0.62, 0.30), sstep(0.1, 0.6, p.z)*0.0 + sstep(0.0, 1.0, nz(p, 6.0, 1))*0.5)
    commit(bm, wc, sharp=70)
    # scoop 1 (vanilla) with a ruffled skirt, scoop 2 (strawberry)
    s1 = ico(3)
    move(s1, lambda p: (p.x*0.43, p.y*0.43, Hc + 0.20 + p.z*0.36))
    commit(s1, lambda p, n: mix((1.0, 0.93, 0.76), (1.0, 0.98, 0.88), sstep(0.2, 1.0, n.z)*0.7), sharp=80)
    skirt = bmesh.new(); segs = 40; rows_ = [(0.46, Hc + 0.06), (0.50, Hc + 0.12), (0.47, Hc + 0.20), (0.40, Hc + 0.25)]
    grid = []
    for (rr, zz) in rows_:
        grid.append([skirt.verts.new(((rr + 0.025*math.sin(i*2*math.pi*9/segs))*math.cos(2*math.pi*i/segs), (rr + 0.025*math.sin(i*2*math.pi*9/segs))*math.sin(2*math.pi*i/segs), zz)) for i in range(segs)])
    for k in range(len(rows_)-1):
        for i in range(segs):
            j = (i+1) % segs
            skirt.faces.new([grid[k][i], grid[k][j], grid[k+1][j], grid[k+1][i]])
    skirt.faces.new(grid[0][::-1]); skirt.faces.new(grid[-1])
    commit(skirt, lambda p, n: (1.0, 0.95, 0.82), sharp=80)
    s2 = ico(3)
    move(s2, lambda p: (p.x*0.36, p.y*0.36, Hc + 0.62 + p.z*0.31))
    commit(s2, lambda p, n: mix((1.0, 0.60, 0.70), (1.0, 0.78, 0.84), sstep(0.2, 1.0, n.z)*0.7), sharp=80)
    # chocolate drizzle spiralling over the top scoop
    path = [V((0.30*math.cos(0.5 + k*0.42)*(1.0 - k/34.0*0.65), 0.30*math.sin(0.5 + k*0.42)*(1.0 - k/34.0*0.65), Hc + 0.34 + (k/34.0)*0.50)) for k in range(34)]
    commit(sweep(path, 0.030, 6), (0.38, 0.20, 0.12), sharp=80)
    r = random.Random(4)                                                 # sprinkles
    cols = [(0.4, 0.7, 1.0), (1.0, 0.9, 0.3), (1.0, 1.0, 1.0), (0.6, 0.9, 0.5), (0.95, 0.4, 0.55)]
    for k in range(18):
        a = r.uniform(0, 6.28); ph = r.uniform(0.15, 1.2)
        px = 0.37*math.sin(ph)*math.cos(a); py = 0.37*math.sin(ph)*math.sin(a); pz = Hc + 0.62 + 0.32*math.cos(ph)
        commit(blob(0.05, 0.014, 0.014, 1), cols[k % 5], sharp=80, xf=xf_rt((px, py, pz), rotz=a + 1.2))
    commit(ico(3, 0.13), lambda p, n: (0.85, 0.08, 0.16) if n.z < 0.8 else (0.55, 0.05, 0.1), sharp=80, xf=xf_rt((0.0, 0.0, Hc + 0.62 + 0.36 + 0.05)))
    commit(sweep([(0, 0, Hc + 1.1), (0.03, 0.01, Hc + 1.22), (0.11, 0.02, Hc + 1.25)], 0.012, 5), (0.35, 0.6, 0.28), sharp=80)
    scale_all(0.78)
BUILD['sundae'] = icecream

# ================================================================ JELLY PUFF (the café's jellycup slot): a cream puff with jelly-blue glaze
def jellypuff(v=0):
    # the bottom shell
    prof = [(0, 0), (0.30, 0), (0.46, 0.04), (0.58, 0.16), (0.60, 0.30), (0.56, 0.40), (0, 0.40)]
    bm = lathe(prof, 40); subdiv(bm, 1)
    displace(bm, lambda p, n: 0.018*nz(p, 6.0, 2) if p.z > 0.02 else None)
    sh = lambda p, n: mix((0.80, 0.50, 0.22), (0.93, 0.68, 0.34), sstep(0.0, 0.5, p.z)*0.4 + sstep(0.3, 1.0, nz(p, 5.0, 1))*0.4)
    commit(bm, sh, sharp=60)
    # the cream: a fat piped ring between the halves, with a swirl that shows over the middle
    ring = bmesh.new(); n = 32; m = 10; grid = []
    for a_i in range(n):
        a = 2*math.pi*a_i/n; row = []
        for k in range(m):
            b = 2*math.pi*k/m; R = 0.50 + 0.10*math.cos(b) + 0.015*math.sin(a*6)
            row.append(ring.verts.new((R*math.cos(a), R*math.sin(a), 0.43 + 0.10*math.sin(b))))
        grid.append(row)
    for a_i in range(n):
        j = (a_i+1) % n
        for k in range(m):
            q = (k+1) % m
            ring.faces.new([grid[a_i][k], grid[j][k], grid[j][q], grid[a_i][q]])
    commit(ring, (1.0, 0.98, 0.94), sharp=80)
    swirl = lathe([(0, 0.40), (0.42, 0.40), (0.44, 0.50), (0.36, 0.60), (0.26, 0.58), (0.20, 0.68), (0.10, 0.70), (0.0, 0.80)], 28)
    commit(swirl, (1.0, 0.98, 0.94), sharp=80)
    # the lid: a lower dome set a little back so the cream shows, glazed
    lid = [(0, 0.50)]
    for k in range(1, 9):
        a = k/8*math.pi/2; lid.append((0.60*math.sin(a), 0.50 + 0.36*(1 - math.cos(a))*1.0 + 0.0))
    lid = [(0, 0.60), (0.28, 0.61), (0.50, 0.56), (0.58, 0.50), (0.60, 0.46)][::-1][::-1]
    prof2 = [(0.58, 0.46), (0.60, 0.50), (0.56, 0.62), (0.44, 0.78), (0.26, 0.88), (0.0, 0.92)]
    bm = lathe(prof2, 40); subdiv(bm, 1)
    displace(bm, lambda p, n: 0.016*nz(p, 6.0, 5))
    def lc(p, n):
        c = sh(p, n)
        gl = sstep(0.62, 0.78, p.z)
        return mix(c, (0.50, 0.72, 0.99), gl*0.92)                              # jelly-blue glaze over the top
    commit(bm, lc, sharp=60, xf=xf_rt((0.0, 0.0, 0.0)))
    # the glaze drips
    for (a, l) in [(0.4, 0.10), (2.1, 0.14), (3.6, 0.08), (5.0, 0.12)]:
        x = 0.46*math.cos(a); y = 0.46*math.sin(a)
        commit(sweep([V((x, y, 0.70)), V((x*1.12, y*1.12, 0.62)), V((x*1.2, y*1.2, 0.62 - l))], 0.035, 6), (0.50, 0.72, 0.99), sharp=80)
    r = random.Random(2)                                                         # sugar dust and sprinkles
    for k in range(20):
        a = r.uniform(0, 6.28); ph = r.uniform(0.0, 0.9)
        rr = 0.40*math.sin(ph)
        commit(blob(0.032, 0.012, 0.012, 1), (1.0, 1.0, 1.0) if k % 3 else (1.0, 0.85, 0.35), sharp=80,
               xf=xf_rt((rr*math.cos(a), rr*math.sin(a), 0.89 - 0.55*(rr/0.45)**2*0.55 + 0.01), rotz=a))
BUILD['jellycup'] = jellypuff

foods.BUILD.update(BUILD)
