import sys
sys.path.insert(0,"/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/decor_art")
import importlib
from dk import *
mods=[importlib.import_module(m) for m in ('pieces_a','pieces_b') if os.path.exists("/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/decor_art/%s.py"%m)]
only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for m in mods:
    for iid, fn in m.REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta); print("EXPORT", iid, info['tris'], info['verts'], [ (s['name']) for s in info['sub_meshes']][:6], info['bounds_min'], info['bounds_max'], flush=True)
