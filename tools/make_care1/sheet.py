"""Contact sheet of the care items (one EEVEE render each, then stitched by the caller): blender -b -P sheet.py -- <outdir> [ids]"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "make_food4"))
import care
from care import *
import run as R
out = sys.argv[sys.argv.index("--")+1]
ids = sys.argv[sys.argv.index("--")+2:] or list(BUILD)
for i in ids:
    reset(); BUILD[i]()
    P, N, C, F = merged()
    zmin = min(p[2] for p in P); P = [(p[0], p[1], p[2]-zmin) for p in P]
    R.setup_scene(520, 520)
    ob = R.make_mesh((P, N, C, F), 'hero'); ob.rotation_euler = (0, 0, 0.5)
    zmax = max(p[2] for p in P)
    R.camera((0, 0, zmax*0.45), math.radians(25), math.radians(28), max(zmax, 2.5)*3.0, 55, 520, 520)
    R.render(os.path.join(out, f"care_{i}.png"))
