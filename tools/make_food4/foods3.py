import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import foods
from foods import rotate_parts
V = Vector

def arc(cx, cy, r, a0, a1, n=8):
    return [(cx+r*math.cos(a0+(a1-a0)*k/n), cy+r*math.sin(a0+(a1-a0)*k/n)) for k in range(n+1)]

# ============================ ICE POP v3 ============================
def popsicle3(v=0):
    W, L, T = 0.46, 1.55, 0.42
    rb = 0.14; rt = 0.43
    # bite scallops at the round (near) end, left corner (concave): chord B -> A, going ccw
    B = V((-W, -L/2+0.52, 0)); A = V((0.04, -L/2, 0))
    chord = A-B; u = chord.normalized(); Mc = (A+B)/2
    n_in = V((-u.y, u.x, 0))
    if n_in.dot(V((0, 0, 0))-Mc) < 0: n_in = -n_in
    bite = []; nseg = 2
    for i in range(nseg):
        P0 = B + chord*(i/nseg); P1 = B + chord*((i+1)/nseg); M = (P0+P1)/2; h = (P1-P0).length/2
        for k in range(1 if i else 0, 7):
            th = math.pi*k/6
            q = M - u*h*math.cos(th) + n_in*h*1.1*math.sin(th)
            bite.append((q.x, q.y))
    outl = []
    outl += arc(W-rb, L/2-rb, rb, 0, math.pi/2, 4)
    outl += arc(-W+rb, L/2-rb, rb, math.pi/2, math.pi, 4)
    outl += bite
    outl += arc(W-rt, -L/2+rt, rt, 1.5*math.pi, 2*math.pi, 8)
    bm = slab(outl, 0.0, T, cuts=0)
    Aor = (1.0, 0.56, 0.22); Cpk = (0.98, 0.40, 0.60)
    BITEC = (1.0, 0.84, 0.82)
    def pc(p, n):
        t = (p.y + L/2)/L
        c = mix(Aor, Cpk, sstep(0.20, 0.80, t))
        if n.z > 0.2: c = mix(c, (1.0, 0.98, 0.96), sstep(0.07, 0.0, abs(p.x+0.22))*sstep(0.55, 0.9, t)*sstep(1.0, 0.85, t)*0.35)
        if abs(n.z) < 0.7 and (V((p.x, p.y, 0))-Mc).length < 0.5 and p.y < B.y+0.03: c = mix(c, BITEC, 0.9)
        c = mix(c, (c[0]*0.93, c[1]*0.88, c[2]*0.9), sstep(0.5, 0.0, n.z)*0.5)
        return c
    commit(bm, pc, mods=[('BEVEL', dict(width=0.15, segments=2, limit_method='ANGLE', angle_limit=math.radians(35)))], sharp=60)
    # cream band with two drips, a thin proud coat all round
    ylo0, yhi0 = 0.14, 0.40
    def yhi(x): return yhi0 + 0.045*math.sin(x*6.5+0.6)
    def ylo(x):
        d1 = 0.34*math.exp(-((x+0.20)/0.11)**2); d2 = 0.20*math.exp(-((x-0.22)/0.09)**2)
        return ylo0 + 0.04*math.sin(x*7.0) - d1 - d2
    Wc = W + 0.025; N = 24
    xs = [-Wc + 2*Wc*i/N for i in range(N+1)]
    poly = [(x, ylo(max(-W, min(W, x)))) for x in xs] + [(x, yhi(max(-W, min(W, x)))) for x in xs[::-1]]
    bm = slab(poly, -0.022, T+0.022, cuts=0)
    def cc(p, n):
        c = (1.0, 0.95, 0.82)
        c = mix(c, (1.0, 1.0, 0.97), sstep(0.2, 1.0, n.z)*0.55)
        c = mix(c, (0.93, 0.84, 0.70), sstep(0.6, -0.2, n.z)*0.55)
        return c
    commit(bm, cc, mods=[('BEVEL', dict(width=0.05, segments=1, limit_method='ANGLE', angle_limit=math.radians(35)))], sharp=60)
    # stick
    so = arc(0.0, 0.95, 0.1, 0.0, math.pi, 6) + [(-0.1, 0.35), (0.1, 0.35)]
    bm = slab(so, 0.12, 0.2, cuts=0)
    commit(bm, lambda p, n: mix((0.95, 0.82, 0.58), (0.85, 0.66, 0.42), sstep(0.2, 0.6, nz(V((p.x*40, p.y*3, p.z*40)), 1.0)*0.5+0.5)*0.6),
           mods=[('BEVEL', dict(width=0.018, segments=1, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=60, xf=xf_rt((0, L/2, 0)))

# ============================ ONIGIRI v3 ============================
def onigiri3(v=0):
    TR = [(-0.80, -0.50), (0.80, -0.50), (0.0, 0.90)]
    base = poly_pts_rounded(TR, 0.17, 5)
    cx = sum(p[0] for p in TR)/3; cy = sum(p[1] for p in TR)/3
    # resample by arclength
    pts = [V((x, y, 0)) for x, y in base]
    seg = [(pts[(i+1) % len(pts)]-pts[i]).length for i in range(len(pts))]
    tot = sum(seg)
    NN = 44
    def at(s):
        s %= tot
        for i, l in enumerate(seg):
            if s <= l: return pts[i].lerp(pts[(i+1) % len(pts)], s/l)
            s -= l
    O = [at(tot*i/NN + 0.001) for i in range(NN)]
    C = V((cx, cy, 0))
    # outward normals from neighbours
    nrm = []
    for i in range(NN):
        t = O[(i+1) % NN]-O[i-1]; nr = V((t.y, -t.x, 0)).normalized()
        if nr.dot(O[i]-C) < 0: nr = -nr
        nrm.append(nr)
    Hf, Hb, rho = 0.40, 0.26, 0.15
    rows = []   # (s, d, z, back?)
    rows.append((0.0, 0.0, Hf+0.05))
    rows.append((0.28, 0.0, Hf+0.045))
    rows.append((0.55, 0.0, Hf+0.035))
    rows.append((0.78, 0.0, Hf+0.02))
    for th in (0, 45, 90):
        t = math.radians(th); rows.append((1.0, rho*(1-math.sin(t)), Hf-rho+rho*math.cos(t)))
    for th in (45, 0):
        t = math.radians(th); rows.append((1.0, rho*(1-math.sin(t)), -(Hb-rho+rho*math.cos(t))))
    rows.append((0.0, 0.0, -Hb-0.01))
    bm = bmesh.new(); grid = []
    for (s, d, z) in rows:
        if s == 0.0:
            grid.append([bm.verts.new((C.x, C.y, z))]*NN); continue
        grid.append([bm.verts.new((C.x+s*(O[i].x-C.x)-nrm[i].x*d, C.y+s*(O[i].y-C.y)-nrm[i].y*d, z)) for i in range(NN)])
    for k in range(len(rows)-1):
        for i in range(NN):
            j = (i+1) % NN
            vs = []
            for q in (grid[k][i], grid[k][j], grid[k+1][j], grid[k+1][i]):
                if q not in vs: vs.append(q)
            if len(vs) >= 3:
                try: bm.faces.new(vs)
                except ValueError: pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if min(vv.co.z for vv in bm.verts) > -1: pass
    nori_src = bm.copy()
    # grain bumps: ridged cellular-ish noise, strong on the faces and weaker on the rim
    def grain(p, n):
        g = 0.012*nz(p, 15.0, 2) + 0.006*nz(p, 29.0, 5) + 0.006*nz(p, 6.0, 9)
        return g*(0.55 + 0.45*abs(n.z))
    displace(bm, grain)
    def rc(p, n):
        c = (1.0, 0.985, 0.94)
        s = nz(p, 26.0, 2)
        c = mix(c, (0.91, 0.88, 0.80), sstep(0.0, -0.8, s)*0.55)
        c = mix(c, (1.0, 1.0, 1.0), sstep(0.25, 0.8, s)*0.5)
        c = mix(c, (0.92, 0.89, 0.82), sstep(0.5, -0.6, n.z)*0.5)
        # shade the underside / bottom
        c = mix(c, (0.88, 0.84, 0.76), sstep(-0.3, -1.0, n.z)*0.6)
        return c
    commit(bm, rc, sharp=75)
    # nori sash: bottom band wrapping over the front, rim and back
    ycut = -0.14
    bmesh.ops.bisect_plane(nori_src, geom=nori_src.verts[:]+nori_src.edges[:]+nori_src.faces[:], plane_co=(0, ycut, 0), plane_no=(0, 1, 0), clear_outer=True)
    nori_src.normal_update()
    for vv in nori_src.verts:
        edge = sstep(0.0, 0.07, ycut - vv.co.y)
        vv.co += vv.normal*(0.010+0.020*edge)
    def nc(p, n):
        c = mix((0.07, 0.13, 0.11), (0.14, 0.21, 0.17), sstep(0.0, 0.8, nz(p, 8.0, 1)*0.5+0.5)*0.6)
        c = mix(c, (0.20, 0.28, 0.23), sstep(0.5, 1.0, n.z)*0.25)
        return c
    commit(nori_src, nc, sharp=80)
    # umeboshi dab + sesame on the top
    bm = ico(2, 1.0)
    move(bm, lambda p: (p.x*0.15, p.y*0.12, p.z*0.06))
    commit(bm, (0.86, 0.26, 0.36), sharp=80, xf=xf_rt((0.0, 0.42, Hf+0.045)))
    r = random.Random(4)
    for k in range(5):
        a = r.uniform(0, 6.28); rr = r.uniform(0.0, 0.3)
        bm = ico(1, 1.0); move(bm, lambda p: (p.x*0.034, p.y*0.02, p.z*0.016))
        commit(bm, (0.1, 0.1, 0.1), sharp=80, xf=xf_rt((0.0+rr*math.cos(a)*0.9, 0.18+rr*math.sin(a)*0.9, Hf+0.052), rotz=a))
    rotate_parts(Matrix.Rotation(math.radians(82), 4, 'X'))

foods.BUILD['popsicle'] = popsicle3
foods.BUILD['onigiri'] = onigiri3
