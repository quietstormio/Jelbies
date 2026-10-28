import sys, importlib
import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from wl import *
import items_head
mods=[items_head]
try:
    import items_other; mods.append(items_other)
except ImportError as e: print("no items_other",e)
only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
REG=[]
for m in mods: REG+=m.REG
anch={'head_top':(0,B.top,0)}
summary=[]
for iid,fn,kw,anchor in REG:
    if only and iid not in only and iid.split('__')[0] not in only: continue
    reset(); meta=fn(**kw); a=meta.pop('anchor_rest',None) or anchor
    meta['anchor']=meta.get('anchor','x')
    meta['colourway']=kw.get('_cw',iid)
    info=export(iid,a,meta); summary.append((iid,info['tris'],info['verts']))
    print("EXPORT",iid,info['tris'])
json.dump(summary,open(W+"/export/_summary.json","w"))
