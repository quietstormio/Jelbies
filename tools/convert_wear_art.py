#!/usr/bin/env python3
"""Convert the Blender wearable exports into bundled wear_<id>.bin files, the shoe paint specs, and the generated Swift tables.

usage: convert_wear_art.py <wear_art_dir> <out_wear_dir>
  <wear_art_dir>  holds wear_catalog.json, export/<id>.obj + .json, shoe_paint_spec.json, shoe_paint_spec_2.json
  <out_wear_dir>  = BobV1/Wear : writes Resources/wear_<id>.bin, Resources/wear_digit_<n>.bin, Resources/shoe_paint_spec*.json and WearGenerated.swift

Re-runnable (the art-polish agent may update exports in place): everything below is derived from the files, nothing is cached.

wear_<id>.bin uses the decor layout (little endian): u32 vertexCount, u32 indexCount, u32 partCount,
  partCount x { char name[16], u32 firstIndex, u32 indexCount, u32 material (0 plain), f32 pivot[3] (part centroid) },
  vertexCount x 11 float32 (pos xyz, normal xyz, LINEAR rgb, ao, w), indexCount x u16 (global vertex indices).
Positions are the artist's REST-space offsets from the item's anchor (arm-local for gloves / wristbands / mitts); the anchor and everything else the
game needs (slot, price, tags, title) goes to WearGenerated.swift so the enum and the catalogue can never disagree with the art.
"""
import json, struct, sys, os, shutil

TITLES = {  # store names (the art titles repeat across colourways)
    "bandana_coral": "Coral bandana", "bandana_mint": "Mint bandana", "beanie_honey": "Honey pom-pom beanie", "beanie_pink": "Pink pom-pom beanie",
    "bib_pink": "Pink jersey bib", "bib_sky": "Sky jersey bib", "bowtie_pink": "Pink bow tie", "bowtie_sky": "Sky bow tie",
    "cap_team_pink": "Pink team cap", "cap_team_sky": "Sky team cap", "glove_pink": "Pink mittens", "glove_sky": "Sky mittens",
    "sash_pink": "Pink racing sash", "sash_sky": "Sky racing sash", "bucket_hat": "Mint bucket hat", "bucket_hat_pink": "Pink bucket hat",
    "scarf_cosy": "Coral cosy scarf", "scarf_sky": "Sky cosy scarf", "wristbands_sky": "Sky wristbands",
}
SHOE_OLD = [  # (case, store id, title, price, tags, paint style, batch); 2026-10-27 shoe sweep: Sun became sandals and Coral clogs (the raw case names stay for old saves)
    ("sneakerMint", "shoe-mint", "Mint sneakers", 30, ["sporty", "cute"], "sneaker_mint", 1),
    ("sneakerSun", "shoe-sun", "Sunny sandals", 30, ["sweet", "cute"], "sneaker_sun", 1),
    ("sneakerCoral", "shoe-coral", "Coral clogs", 30, ["cute", "cool"], "sneaker_coral", 1),
    ("rainBoots", "shoe-rain", "Rain boots", 45, ["cute", "cool"], "rainboot", 1),
    ("glitterShoes", "shoe-glitter", "Glitter shoes", 60, ["sparkly", "sweet"], "glitter", 1),
]
SHOE_NEW = {  # catalogue key -> (case, store id, paint style)
    "shoe_hightop_red": ("hightopRed", "shoe-hightop", "hightop_red"),
    "shoe_ballet_pink": ("balletPink", "shoe-ballet", "ballet_pink"),
    "shoe_frog_boots": ("frogBoots", "shoe-frog", "frog_boots"),
    "shoe_sneaker_lightup": ("sneakerLightup", "shoe-lightup", "sneaker_lightup"),
}

def camel(s):
    p = s.split("_")
    return p[0] + "".join(x.capitalize() for x in p[1:])

def convert(src):
    pos, col, nrm, ao, w, parts = [], [], [], [], [], []
    for line in open(src):
        t = line.split()
        if not t or t[0].startswith("#"): continue
        if t[0] == "o": parts.append([t[1], []])
        elif t[0] == "v":
            pos.append(tuple(map(float, t[1:4]))); col.append(tuple(map(float, t[4:7])))
            ao.append(float(t[7]) if len(t) > 7 else 1.0); w.append(float(t[8]) if len(t) > 8 else 0.0)
        elif t[0] == "vn": nrm.append(tuple(map(float, t[1:4])))
        elif t[0] == "f":
            idx = [int(x.split("//")[0]) - 1 for x in t[1:]]
            for k in range(1, len(idx) - 1): parts[-1][1] += [idx[0], idx[k], idx[k + 1]]
    assert len(pos) == len(nrm) == len(col) and len(pos) < 65536, src
    tris, head = [], b""
    for name, ix in parts:
        used = sorted(set(ix))
        c = [sum(pos[i][a] for i in used) / len(used) for a in range(3)]
        head += struct.pack("<16sIII3f", name.encode()[:15], len(tris), len(ix), 0, *c)
        tris += ix
    data = struct.pack("<III", len(pos), len(tris), len(parts)) + head
    for p, n, c, a, ww in zip(pos, nrm, col, ao, w):
        data += struct.pack("<11f", *p, *n, *c, a, ww)
    data += struct.pack("<%dH" % len(tris), *tris)
    return data, len(pos), len(tris) // 3, [p[0] for p in parts]

def swiftstr(s): return json.dumps(s)

def main():
    art, out = sys.argv[1], sys.argv[2]
    res = os.path.join(out, "Resources")
    os.makedirs(res, exist_ok=True)
    cat = json.load(open(os.path.join(art, "wear_catalog.json")))
    exp = os.path.join(art, "export")
    for f in os.listdir(res):
        if f.startswith("wear_") and f.endswith(".bin"): os.remove(os.path.join(res, f))
    entries = []
    for i, meta in cat["items"].items():
        j = json.load(open(os.path.join(exp, i + ".json")))
        data, nv, nt, names = convert(os.path.join(exp, i + ".obj"))
        open(os.path.join(res, "wear_%s.bin" % i), "wb").write(data)
        print(i, nv, "verts", nt, "tris", len(data), "bytes", len(names), "parts")
        a = j["anchor_rest"]
        entries.append(dict(case=camel(i), art=i, store="wear-" + i, title=TITLES.get(i, j["title"]), slot=j["slot"], anchor=j["anchor"], rest=a,
                            price=j["price"], tags=j["tags"], batch=j.get("batch", 1), verts=nv, tris=nt, style=""))
    for k, (case, sid, style) in SHOE_NEW.items():
        m = cat["shoes_paint_2"]["items"][k]
        entries.append(dict(case=case, art="", store=sid, title=m["title"], slot="feet", anchor="feet", rest=[0, 0, 0], price=m["price"], tags=m["tags"],
                            batch=2, verts=0, tris=0, style=style))
    for case, sid, title, price, tags, style, batch in SHOE_OLD:
        entries.append(dict(case=case, art="", store=sid, title=title, slot="feet", anchor="feet", rest=[0, 0, 0], price=price, tags=tags, batch=batch,
                            verts=0, tris=0, style=style))
    for n in range(10):
        data, nv, nt, names = convert(os.path.join(exp, "digit_%d.obj" % n))
        open(os.path.join(res, "wear_digit_%d.bin" % n), "wb").write(data)
    for s in ("shoe_paint_spec.json", "shoe_paint_spec_2.json"): shutil.copy(os.path.join(art, s), os.path.join(res, s))
    bib = json.load(open(os.path.join(exp, "bib_sky.json")))

    feet = [e for e in entries if e["slot"] == "feet"]
    # the five original shoes first (their raw values are in old saves), then the new shoes, then the rest
    feet.sort(key=lambda e: [x[0] for x in SHOE_OLD].index(e["case"]) if e["case"] in [x[0] for x in SHOE_OLD] else 99)
    rest = [e for e in entries if e["slot"] != "feet"]
    ordered = feet + rest
    L = []
    L.append("// GENERATED by tools/convert_wear_art.py from the Blender wearable exports. Do not edit by hand: re-run the converter.")
    L.append("// One WearLook per piece of the wardrobe (the raw values of the five original shoes are kept for old saves).")
    L.append("")
    L.append("import simd")
    L.append("")
    L.append("nonisolated enum WearLook: String, CaseIterable, Codable, Sendable {")
    L.append("    case " + ", ".join(e["case"] for e in ordered))
    L.append("}")
    L.append("")
    L.append("nonisolated enum WearGenerated {")
    L.append("    struct Row: Sendable {")
    L.append("        let look: WearLook, art: String, storeID: String, title: String, slot: WearSlot, anchor: WearAnchor, anchorRest: SIMD3<Float>")
    L.append("        let price: Int, tags: [WearTag], batch: Int, paintStyle: String, vertices: Int, triangles: Int")
    L.append("    }")
    L.append("    static let rows: [Row] = [")
    for e in ordered:
        r = e["rest"]
        L.append("        Row(look: .%s, art: %s, storeID: %s, title: %s, slot: .%s, anchor: .%s, anchorRest: SIMD3(%.5f, %.5f, %.5f), price: %d, tags: [%s], batch: %d, paintStyle: %s, vertices: %d, triangles: %d),"
                 % (e["case"], swiftstr(e["art"]), swiftstr(e["store"]), swiftstr(e["title"]), e["slot"], camel(e["anchor"]), r[0], r[1], r[2], e["price"],
                    ", ".join("." + t for t in e["tags"]), e["batch"], swiftstr(e["style"]), e["verts"], e["tris"]))
    L.append("    ]")
    L.append("    /// The bib plate's number placement (bib_sky.json; identical for bib_pink).")
    L.append("    static let bibNumberAnchor = SIMD3<Float>(%.5f, %.5f, %.5f)" % tuple(bib["number_anchor_rest"]))
    L.append("    static let bibNumberNormal = SIMD3<Float>(%.5f, %.5f, %.5f)" % tuple(bib["number_normal"]))
    L.append("    static let bibNumberHeight: Float = %.4f" % bib["number_height"])
    L.append("    static let bibPlateHalf = SIMD2<Float>(%.4f, %.4f)" % tuple(bib["plate_half_size"]))
    L.append("}")
    open(os.path.join(out, "WearGenerated.swift"), "w").write("\n".join(L) + "\n")
    print("wrote", len(entries), "looks")

main()
