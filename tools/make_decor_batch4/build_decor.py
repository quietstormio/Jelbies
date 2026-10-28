"""Build the batch-4 toys in headless Blender and export OBJ+JSON for tools/convert_decor_art.py.

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_decor.py -- [ids...]

Exports to $DECOR_EXPORT (default tools/make_decor_batch4/export). Then:
  python3 tools/convert_decor_art.py <export dir> BobV1/Room/Resources
"""
import sys, os, importlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dk import *
mods = [importlib.import_module(m) for m in ("pieces_toys", "pieces_polish")]
only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for m in mods:
    for iid, fn in m.REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], [s["name"] for s in info["sub_meshes"]][:10], info["bounds_min"], info["bounds_max"], flush=True)
