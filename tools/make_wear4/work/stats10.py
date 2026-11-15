"""Numbers for the items10 concept garments: blender -b -P stats10.py -- [ids]   (offline; prints one block per item, incl. the Pip variants)"""
import sys, os, json, struct, math
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import numpy as np
import items10 as I
from items10 import *
ids = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [r[0] for r in I.REG]
wb = open(os.path.join(HERE, '..', '..', '..', 'BobV1', 'Features', 'Resources', 'feature_lav_a_final.bin'), 'rb').read()
nv_, ni_, np_ = struct.unpack_from('<III', wb, 0)
WV = np.frombuffer(wb, '<f4', nv_ * 11, 12 + 40 * np_).reshape(nv_, 11)[:, :3] + np.array([0, 0.55, -0.5172])
g = json.load(open(os.path.join(HERE, '..', 'art', 'pip_geometry.json')))
SP = np.array(g['spikeVertices'])[:, :3]; SP = np.concatenate([SP, SP * np.array([-1, 1, 1])])
TS = [s for s in g['tailSpheres'] if float(B.sdf(s[0], s[1], s[2])) > 0.0]
def mind(A, Bv):
    best = 9
    for i in range(0, len(A), 200):
        d = np.linalg.norm(A[i:i + 200, None, :] - Bv[None], axis=2).min(); best = min(best, d)
    return best
VAR = {'hoodie': dict(sleeves_on=True), 'raincoat': dict(sleeves_on=True), 'cardigan_cable': dict(sleeves_on=True)}
for spec in [(i, False) for i in ids] + [(i, True) for i in ids if i in ('hoodie', 'raincoat', 'cape_hero', 'cardigan_cable', 'vest_puffer')]:
    iid, pip = spec
    fn = [r for r in I.REG if r[0] == iid][0][1]
    fn(pip=pip, **(VAR.get(iid, {})))
    P = np.array([q for p in PARTS for q in p['P']]); T = sum(len(p['F']) for p in PARTS)
    CL = ('body', 'coat', 'panel', 'collar+1', 'collar-1')
    NS = [i for i, p in enumerate(PARTS) if not p['name'].startswith(('sleeve', 'cuff'))]
    Pn = np.array([q for p in PARTS if not p['name'].startswith(('sleeve', 'cuff')) for q in p['P']]); Ps = np.array([q for p in PARTS if p['name'].startswith(('sleeve', 'cuff')) for q in p['P']])
    Pc = np.array([q for p in PARTS if p['name'] in CL for q in p['P']])
    sd = B.sdf_pts(Pc); ad = arm_d(Pn); sda = B.sdf_pts(P); sla = arm_d(Ps) if len(Ps) else np.array([0.0])
    z = P[:, 2] > 0.1
    ell = np.hypot(P[z, 0] / 0.15, (P[z, 1] - 0.651) / 0.10).min() if z.any() else 9
    fr = z & (np.abs(P[:, 0]) < 0.3); top = P[fr, 1].max() if fr.any() else 0
    parts = {}
    for p in PARTS: parts[p['name']] = parts.get(p['name'], 0) + len(p['P'])
    print("%-20s %s verts %4d tris %4d | keepout ellipse min %.3f (>=1 ok), front top y %.3f (<=0.575 ok) | cloth skin offset min %.3f max %.3f (cloth verts %d) | arm min %.3f (sleeve-to-nub %.3f..%.3f) | all-parts skin offset min %.3f max %.3f | wing min %.3f%s" % (
        iid, 'PIP' if pip else '   ', len(P), T, ell, top, sd.min(), sd.max(), len(Pc), ad.min(), sla.min(), sla.max(), sda.min(), sda.max(), mind(P, WV),
        (" | pip spike min %.3f, tail min %.3f" % (mind(P, SP), min(float((np.linalg.norm(P - np.array(s[:3]), axis=1) - s[3]).min()) for s in TS))) if pip else ""))
    print("     parts:", parts)
