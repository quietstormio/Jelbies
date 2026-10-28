#!/usr/bin/env python3
"""Mouth keep-out check on the exported art: no front vertex (z>0.1) inside the ellipse c(0,.651) r(.15,.10), and nothing of a body/neck piece
above y 0.51 on the front belly (|x|<0.3). usage: check_keepout.py [ids...]"""
import json, os, sys, math
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art", "export")
ids = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(A) if f.endswith(".json") and not f.startswith(("_", "digit")))
bad = 0
for i in ids:
    j = json.load(open(os.path.join(A, i + ".json")))
    if j["slot"] in ("hands",): continue
    a = j["anchor_rest"] if not j.get("authored_local") else [0, 0, 0]
    worst = 9; top = -9
    for ln in open(os.path.join(A, i + ".obj")):
        if not ln.startswith("v "): continue
        t = ln.split(); x, y, z = float(t[1]) + a[0], float(t[2]) + a[1], float(t[3]) + a[2]
        if z < 0.1: continue
        v = math.hypot(x / 0.15, (y - 0.651) / 0.10)
        if j["slot"] in ("face", "body", "neck"): worst = min(worst, v)
        if j["slot"] in ("body", "neck") and abs(x) < 0.3: top = max(top, y)
    flag = ""
    if j["slot"] in ("face", "body", "neck") and worst < 1.0: flag = "  <-- INSIDE THE MOUTH KEEP-OUT"; bad += 1
    if j["slot"] in ("body", "neck") and top > 0.575: flag += "  <-- high on the front (%.3f)" % top
    print("%-20s slot %-5s min ellipse %.3f top-front y %.3f%s" % (i, j["slot"], worst, top, flag))
print("violations:", bad)
