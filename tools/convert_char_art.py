#!/usr/bin/env python3
"""Convert the approved character-feature art (Pip's spines, Moss's daisy, Lavender's wings) into the bundle.

usage: convert_char_art.py <char_art_dir> <out_dir>
  <char_art_dir>  holds compat.json, wing_limits*.json and export/<id>.obj + .json (the character art lab)
  <out_dir>       = BobV1/Features : writes Resources/feature_<id>.bin, Resources/wear_<variant>.bin (the hat variants Moss's daisy sits on)
                    and Resources/feature_compat.json (the per-wearable rule table, the feature animation data and the flap-hop keyframes)

Re-runnable: everything is derived from the files; only the files this tool owns are removed first (feature_*.bin, feature_compat.json and the
listed hat variants). The variant hats live HERE, not in Wear/Resources, because convert_wear_art.py wipes every wear_*.bin there on re-run; the
app bundle is flat, so WearMeshes.art("beanie_honey_nopom") still finds them.

The .bin layout is the decor / wear one (DecorMeshes.load): u32 vertexCount, u32 indexCount, u32 partCount,
  partCount x { char name[16], u32 firstIndex, u32 indexCount, u32 material, f32 pivot[3] }, vertexCount x 11 float32 (pos, normal, LINEAR rgb,
  ao, w), indexCount x u16. Positions are REST-space offsets from the feature's anchor (anchor_rest in the sidecar); the anchor goes to the json.
"""
import json, struct, sys, os

FEATURES = ["pip_c_final", "moss_a_final", "moss_a_final_onhat", "lav_a_final"]
VARIANTS = ["beanie_honey_nopom", "beanie_pink_nopom", "cap_team_pink_nobutton", "cap_team_sky_nobutton", "party_hat_nopom", "party_hat_short"]
TOP = 1.3458                     # the crown of the egg: head_top anchor y (BobForm.top)
DYS = [-0.2, -0.16, -0.12, -0.08, -0.04, 0.0, 0.04, 0.08, 0.12, 0.16]
# a colourway shares its sibling's measured wing table (work/wingsolve.py ALIAS)
ALIAS = {"beanie_honey": "beanie_pink", "cap_team_sky": "cap_team_pink", "bucket_hat_pink": "bucket_hat", "scarf_sky": "scarf_cosy",
         "sash_sky": "sash_pink", "bib_pink": "bib_sky", "bowtie_sky": "bowtie_pink", "bandana_mint": "bandana_coral"}


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


def r3(v): return [round(float(x), 5) for x in v]


def main():
    art, out = sys.argv[1], sys.argv[2]
    exp = os.path.join(art, "export")
    res = os.path.join(out, "Resources")
    os.makedirs(res, exist_ok=True)
    for f in os.listdir(res):
        if (f.startswith("feature_") and f.endswith(".bin")) or f == "feature_compat.json" or f in ["wear_%s.bin" % v for v in VARIANTS]:
            os.remove(os.path.join(res, f))
    meshes = {}
    for i in FEATURES:
        data, nv, nt, names = convert(os.path.join(exp, i + ".obj"))
        open(os.path.join(res, "feature_%s.bin" % i), "wb").write(data)
        meshes[i] = dict(vertices=nv, triangles=nt, parts=names)
        print("feature", i, nv, "verts", nt, "tris", len(names), "parts")
    variants = {}
    for v in VARIANTS:
        data, nv, nt, names = convert(os.path.join(exp, v + ".obj"))
        open(os.path.join(res, "wear_%s.bin" % v), "wb").write(data)
        j = json.load(open(os.path.join(exp, v + ".json")))
        variants[v] = dict(of=j["variant_of"], vertices=nv, triangles=nt)
        print("variant", v, "of", j["variant_of"], nv, "verts", nt, "tris")

    # ---- the animation data of each feature
    pip = json.load(open(os.path.join(exp, "pip_c_final.json")))
    spines = [dict(part=s["part"], zone=s["zone"], base=r3(s["base_rest"]), normal=r3(s["normal_rest"]), axis=r3(s["axis_rest"]),
                   pivot=r3(s["wobble_pivot_local"]), height=s["height"], maxDeg=s["wobble"]["max_deg"], hz=s["wobble"]["spring_hz"],
                   damping=s["wobble"]["damping"], lag=s["wobble"]["phase_lag_s"]) for s in pip["spikes"]]
    def daisy(idn):
        m = json.load(open(os.path.join(exp, idn + ".json")))
        return dict(id=idn, anchor=r3(m["anchor_rest"]), stemPivot=r3(m["stem_pivot_rest"]), flowerCentre=r3(m["flower_centre_rest"]),
                    flowerNormal=r3(m["flower_normal"]), petals=m["night"]["petal_parts"], closeDeg=m["night"]["close_deg"],
                    idleDeg=m["sway"]["idle_deg"], idleHz=m["sway"]["idle_hz"], headLag=m["sway"]["head_pivot_lag_s"], droopDeg=22, closeTime=1.2)
    lav = json.load(open(os.path.join(exp, "lav_a_final.json")))
    wings = {k: dict(hinge=r3(w["hinge_rest"]), flapAxis=r3(w["flap_axis_rest"]), spreadAxis=r3(w["spread_axis_rest"]), parts=w["parts"])
             for k, w in lav["wings"].items()}
    hop = json.load(open(os.path.join(exp, "lavender_flap_hop_s1.json")))
    keys = [dict(t=k["t"], lift=k["lift"], drift=k["drift"], sy=k["sy"], pitchDeg=k["pitch_deg"], flap=k["flap"], spread=k["spread"], dangle=k["foot_dangle"])
            for k in hop["keyframes"]]
    osc = hop["flap_oscillation"]
    hopOut = dict(total=hop["total_s"], maxLift=hop["body_max_lift"], drift=hop["forward_drift_total"], keyframes=keys,
                  oscFrom=osc["applies_between_t"][0], oscTo=osc["applies_between_t"][1],
                  lift=dict(mean=osc["lift_phase"]["mean"], amp=osc["lift_phase"]["amp"], hz=osc["lift_phase"]["f_hz"]),
                  hover=dict(mean=osc["hover"]["mean"], amp=osc["hover"]["amp"], hz=osc["hover"]["f_hz"]),
                  decay=dict(mean=osc["decay"]["mean"], amp=osc["decay"]["amp"], hz=osc["decay"]["f_hz"]))

    # ---- the per-wearable rules (compat.json), normalised for the game
    compat = json.load(open(os.path.join(art, "compat.json")))
    pairs = {}
    for wid, r in compat["pairs"].items():
        p = r.get("pip_c_final", {}); m = r.get("moss_a_final", {}); l = r.get("lav_a_final", {})
        rec = dict(slot=r["slot"], pipHide=sorted(p.get("hide_parts", [])))
        if m.get("rule") == "hide-feature": rec["moss"] = dict(rule="hide")
        elif m.get("rule") in ("adjust-feature", "adjust-wearable"):
            if "daisy_xf" in m:
                xf = m["daisy_xf"]; rec["moss"] = dict(rule="adjust", anchor=r3(xf["anchor"]), tilt=float(xf["tilt"]), sink=float(xf["sink"]))
            else:
                # the shift form is a plain lift of the on-hat sprout by anchor_shift_y (work/verify_daisy.py): anchor (0, TOP + shift, 0), no tilt, no sink
                rec["moss"] = dict(rule="adjust", anchor=[0.0, round(TOP + m["anchor_shift_y"], 5), 0.0], tilt=0.0, sink=0.0)
            if m.get("wearable_variant"): rec["moss"]["variant"] = m["wearable_variant"]
        else: rec["moss"] = dict(rule="ok")
        if l.get("rule") == "hide-feature": rec["lav"] = dict(rule="hide")
        else:
            rec["lav"] = dict(rule="ok" if l.get("rule") == "ok" else "adjust", dy=float(l.get("wing_dy", 0.0)), flapMin=float(l.get("flap_min", -40)),
                              flapMax=float(l.get("flap_max", 75)), spreadMax=float(l.get("spread_max", 40)))
        pairs[wid] = rec

    # ---- the measured wing clearance per wearable and vertical shift (the runtime intersection for worn combinations, work/wingsolve.py)
    T = {}
    for f in ("wing_limits.json", "wing_limits2.json", "wing_limits3.json", "wing_limits4.json"):
        path = os.path.join(art, f)
        if not os.path.exists(path): continue
        for w, d in json.load(open(path)).items():
            for dy, v in d.items():
                T.setdefault(w, {})[str(round(float(dy), 2))] = [v["min_flap"], v["max_flap"]] if v["rest_ok"] else None
    limits = {}
    for wid in pairs:
        src = ALIAS.get(wid, wid)
        if src in T: limits[wid] = T[src]

    spec = dict(version=1, top=TOP, dys=DYS, meshes=meshes, variants=variants, spines=spines, daisy=daisy("moss_a_final"), daisyOnHat=daisy("moss_a_final_onhat"),
                wings=dict(anchor=r3(lav["anchor_rest"]), sides=wings), hop=hopOut, pairs=pairs, wingLimits=limits)
    json.dump(spec, open(os.path.join(res, "feature_compat.json"), "w"), indent=0, sort_keys=True)
    print("wrote feature_compat.json:", len(pairs), "wearable rules,", len(limits), "wing tables,", len(keys), "hop keys")


main()
