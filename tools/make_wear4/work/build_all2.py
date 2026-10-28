import sys
import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from wl import *
mods=[]
import items2_head; mods.append(items2_head)
try:
    import items2_other; mods.append(items2_other)
except ImportError as e: print("no items2_other",e)
only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
REG=[]
for m in mods: REG+=m.REG
for iid,fn,kw,anchor in REG:
    if only and iid not in only: continue
    reset(); meta=fn(**kw); a=meta.pop('anchor_rest',None) or anchor
    meta['colourway']=iid
    info=export(iid,a,meta); print("EXPORT",iid,info['tris'],flush=True)
