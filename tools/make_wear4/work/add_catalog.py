#!/usr/bin/env python3
"""Registers every art/export/<id>.json that is not yet in art/wear_catalog.json (new pieces), and refreshes the tris / verts of all of them."""
import json, os
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art")
cat = json.load(open(os.path.join(A, "wear_catalog.json")))
for f in sorted(os.listdir(os.path.join(A, "export"))):
    if not f.endswith(".json") or f.startswith("_") or f.startswith("digit_"): continue
    i = f[:-5]
    j = json.load(open(os.path.join(A, "export", f)))
    if i not in cat["items"]:
        cat["items"][i] = dict(title=j["title"], slot=j["slot"], anchor=j["anchor"], anchor_rest=j["anchor_rest"], tags=j["tags"], price=j["price"], tris=j["tris"], verts=j["verts"], files=[i + ".obj", i + ".json"])
        print("added", i)
    else:
        cat["items"][i]["tris"] = j["tris"]; cat["items"][i]["verts"] = j["verts"]
json.dump(cat, open(os.path.join(A, "wear_catalog.json"), "w"), indent=1)
