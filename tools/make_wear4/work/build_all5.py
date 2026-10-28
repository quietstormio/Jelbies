"""Batch 4 builder: blender -b -P build_all5.py -- [ids...]   (writes ../art/export/<id>.obj + .json)"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wl import *
import items5
mods = [items5]
for name in ("items6", "items7", "items8"):
    try:
        mods.append(__import__(name))
    except ImportError as e:
        print("no", name, e)
only = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
REG = []
for m in mods: REG += m.REG
import re, subprocess
def old_rows():
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
    txt = subprocess.run(['git', '-C', root, 'show', 'HEAD:BobV1/Wear/WearGenerated.swift'], capture_output=True, text=True).stdout
    out = {}
    for m in re.finditer(r'Row\(look: \.(\w+), art: "(\w*)", storeID: "[^"]*", title: "([^"]*)", slot: \.(\w+), anchor: \.(\w+), anchorRest: SIMD3\([^)]*\), price: (\d+), tags: \[([^\]]*)\], batch: (\d+)', txt):
        look, art, title, slot, anchor, price, tags, batch = m.groups()
        if art: out[art] = dict(title=title, slot=slot, price=int(price), tags=[t.strip(' .') for t in tags.split(',')], batch=int(batch))
    return out
OLD = old_rows()
for iid, fn, kw, anchor in REG:
    if only and iid not in only: continue
    reset(); meta = fn(**kw); a = meta.pop('anchor_rest', None) or anchor
    meta['colourway'] = iid
    if iid in OLD:                       # an upgrade of a shipped piece keeps its shop row
        o = OLD[iid]
        meta.update(title=o['title'], price=o['price'], tags=o['tags'], batch=o['batch'])
    else:
        meta['batch'] = 4
    info = export(iid, a, meta); print("EXPORT", iid, info['tris'], info['verts'], flush=True)

# species variants (art/variants/*.obj -> Features/Resources/wear_<id>.bin by the converter): same look, another mesh
for m in mods:
    for iid, fn, kw, anchor in getattr(m, 'VARIANTS', []):
        if only and iid not in only: continue
        reset(); meta = fn(**kw); a = meta.pop('anchor_rest', None) or anchor
        meta['colourway'] = iid
        info = export(iid, a, meta, outdir=W + "/variants"); print("EXPORT", iid, info['tris'], info['verts'], flush=True)

try:
    import kit5
    print("PIPGAPS (y_lo, y_hi, gap) on Pip's back centre line:", [tuple(round(x, 3) for x in g) for g in kit5.pip_gap_report()])
except Exception as e:
    print("PIPGAPS failed", e)
