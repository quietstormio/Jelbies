import sys
sys.path.insert(0,"/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/wear_art/work")
from wl import *
import items4
only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for iid,fn,kw,anchor in items4.REG:
    if only and iid not in only: continue
    reset(); meta=fn(**kw); a=meta.pop('anchor_rest',None) or anchor
    meta['colourway']=iid
    info=export(iid,a,meta); print("EXPORT",iid,info['tris'],info['verts'],flush=True)
