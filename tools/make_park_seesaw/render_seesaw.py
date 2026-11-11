"""Renders the CONVERTED decor_seesaw.bin (vertex colours x baked AO, as the game shows it) on a lawn-green ground with soft sun and sky.

  Blender -b -t 4 -P tools/make_park_seesaw/render_seesaw.py -- <decor_seesaw.bin> <variant letter> <out dir> [views comma list: hero,tilt_left,tilt_right,side,side_tilt,close,close_high,close_low] [samples]
Posing (contract v2): plank rotated by the angle about its pivot, each seat TRANSLATED by R(angle) h - h (never rotated), pressed bumper scaled in y. Variant "R2" gives R2_<view>.png.
Game axes (x along the plank, y up, z toward the camera) are mapped to Blender by (x, -z, y).
"""
import sys, os, math, struct
import numpy as np
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
BIN, VAR, OUTDIR = args[0], args[1], args[2]
VIEWS = (args[3] if len(args) > 3 else "hero,tilt_left,tilt_right,side,side_tilt,close_high,close_low").split(",")
SAMPLES = int(args[4]) if len(args) > 4 else 48
os.makedirs(OUTDIR, exist_ok=True)

def read_bin(path):
    d = open(path, "rb").read()
    nv, ni, npart = struct.unpack_from("<III", d, 0)
    parts = []; head = 12; vend = head + npart * 40 + nv * 44 - nv * 44  # placeholder, recomputed below
    headEnd = 12 + npart * 40; vertEnd = headEnd + nv * 44
    V = np.frombuffer(d, dtype="<f4", count=nv * 11, offset=headEnd).reshape(nv, 11)
    I = np.frombuffer(d, dtype="<u2", count=ni, offset=vertEnd)
    for p in range(npart):
        name, first, cnt, mat, px, py, pz = struct.unpack_from("<16sIII3f", d, 12 + p * 40)
        parts.append(dict(name=name.split(b"\0")[0].decode(), first=first, count=cnt, pivot=(px, py, pz)))
    return V, I, parts

V, I, PARTS = read_bin(BIN)

def g2b(p): return (p[0], -p[2], p[1])

def part_data(part):
    idx = I[part["first"]:part["first"] + part["count"]].astype(int)
    used = sorted(set(idx)); remap = {g: i for i, g in enumerate(used)}
    return V[used].copy(), np.array([remap[g] for g in idx]).reshape(-1, 3)

def rot_z(P, N, ang, piv):
    c, s = math.cos(ang), math.sin(ang); P = P.copy(); N = N.copy()
    x = P[:, 0] - piv[0]; y = P[:, 1] - piv[1]
    P[:, 0] = piv[0] + c * x - s * y; P[:, 1] = piv[1] + s * x + c * y
    nx, ny = N[:, 0].copy(), N[:, 1].copy(); N[:, 0] = c * nx - s * ny; N[:, 1] = s * nx + c * ny
    return P, N

def make_mesh(name, verts, faces):
    pos = verts[:, 0:3]; nrm = verts[:, 3:6]; col = verts[:, 6:9]; ao = verts[:, 9]
    me = bpy.data.meshes.new(name)
    me.from_pydata([g2b(p) for p in pos], [], [tuple(f) for f in faces])
    me.update()
    for p in me.polygons: p.use_smooth = True
    me.normals_split_custom_set_from_vertices([g2b(n) for n in nrm])
    ca = me.color_attributes.new("col", "FLOAT_COLOR", "POINT"); ca.data.foreach_set("color", np.concatenate([np.hstack([col, np.ones((len(col), 1))]).ravel()]))
    aa = me.color_attributes.new("ao", "FLOAT_COLOR", "POINT"); aa.data.foreach_set("color", np.hstack([np.repeat(ao[:, None], 3, 1), np.ones((len(ao), 1))]).ravel())
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(MAT)
    return ob

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.render.threads_mode = "FIXED"; sc.render.threads = 4
sc.render.resolution_x = 1600; sc.render.resolution_y = 1000; sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
sc.cycles.max_bounces = 4

# material: vertex colour x baked AO
MAT = bpy.data.materials.new("vc"); MAT.use_nodes = True
nt = MAT.node_tree; nt.nodes.clear()
a1 = nt.nodes.new("ShaderNodeAttribute"); a1.attribute_name = "col"
a2 = nt.nodes.new("ShaderNodeAttribute"); a2.attribute_name = "ao"
mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MULTIPLY"; mx.inputs[0].default_value = 1.0
nt.links.new(a1.outputs["Color"], mx.inputs[6]); nt.links.new(a2.outputs["Color"], mx.inputs[7])
bs = nt.nodes.new("ShaderNodeBsdfPrincipled"); bs.inputs["Roughness"].default_value = 0.62
out = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(mx.outputs[2], bs.inputs["Base Color"]); nt.links.new(bs.outputs[0], out.inputs[0])

def s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
GM = bpy.data.materials.new("lawn"); GM.use_nodes = True
GM.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (s2l(0.30), s2l(0.50), s2l(0.25), 1)
GM.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
bpy.ops.mesh.primitive_plane_add(size=40); gr = bpy.context.active_object; gr.data.materials.append(GM)

# world: soft sky; sun with a wide angle for soft shadows
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.62, 0.78, 1.0, 1); bg.inputs["Strength"].default_value = 0.85
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.2; sun.angle = math.radians(9); sun.color = (1.0, 0.96, 0.88)
so = bpy.data.objects.new("sun", sun); bpy.context.scene.collection.objects.link(so)
so.rotation_euler = (math.radians(48), 0, math.radians(-125))   # sun from the upper left front

def build_scene(angle=0.0):
    for ob in [o for o in bpy.data.objects if o.name.startswith("part_")]: bpy.data.objects.remove(ob)
    datas = {p["name"]: part_data(p) for p in PARTS}
    pv = [p["pivot"] for p in PARTS if p["name"] == "plank"][0]
    DEP = pv[1] - 0.255      # plank pivot height minus the beam underside
    for p in PARTS:
        v, f = datas[p["name"]]; v = v.copy()
        if p["name"] == "plank" and angle != 0.0:
            P, N = rot_z(v[:, 0:3], v[:, 3:6], angle, pv); v[:, 0:3] = P; v[:, 3:6] = N
        if p["name"] in ("seatL", "seatR") and angle != 0.0:
            # the game's rule: a seat is only TRANSLATED by d = R(angle) h - h (h = hinge point minus plank pivot), never rotated
            hx, hy = p["pivot"][0] - pv[0], p["pivot"][1] - pv[1]; c_, s_ = math.cos(angle), math.sin(angle)
            v[:, 0] += c_ * hx - s_ * hy - hx; v[:, 1] += s_ * hx + c_ * hy - hy
        if p["name"] in ("bumperL", "bumperR") and angle != 0.0:
            # the pressed bumper (low end) is scaled in height so its apex just meets the plank's underside, as the game does
            side = -1 if p["name"] == "bumperL" else 1
            pressed = (angle > 0 and side < 0) or (angle < 0 and side > 0)
            if pressed:
                s_, c_ = math.sin(angle), math.cos(angle); k = 1.0
                for x, y in zip(v[:, 0], v[:, 1]):
                    if y < 0.01: continue
                    yu = pv[1] + x * math.tan(angle) - DEP / c_        # underside line at world x (contract: 0.27 - 0.96 tan a - 0.015 / cos a)
                    k = min(k, (yu - 0.004) / y)
                v[:, 1] *= k; print("BUMPER", p["name"], "scale", round(k, 3))
        ob = make_mesh("part_" + p["name"], v, f); ob.rotation_euler = (0, 0, 0)

def camera(pos, target, lens=45, ortho=None):
    for o in [o for o in bpy.data.objects if o.type == "CAMERA"]: bpy.data.objects.remove(o)
    cam = bpy.data.cameras.new("c"); co = bpy.data.objects.new("c", cam); bpy.context.scene.collection.objects.link(co)
    cam.lens = lens
    if ortho: cam.type = "ORTHO"; cam.ortho_scale = ortho
    co.location = g2b(pos)
    d = Vector(g2b(target)) - Vector(co.location)
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()      # level: up stays +Z
    sc.camera = co

VIEWSPEC = {
    "hero": dict(angle=0.0, pos=(1.7, 1.15, 2.6), target=(0, 0.28, 0), lens=42),
    "tilt_left": dict(angle=0.176, pos=(1.7, 1.15, 2.6), target=(0, 0.3, 0), lens=42),
    "tilt_right": dict(angle=-0.176, pos=(1.7, 1.15, 2.6), target=(0, 0.3, 0), lens=42),
    "side": dict(angle=0.0, pos=(0, 0.33, 8), target=(0, 0.33, 0), lens=50, ortho=2.9),
    "side_tilt": dict(angle=0.176, pos=(0, 0.33, 8), target=(0, 0.33, 0), lens=50, ortho=2.9),
    "close": dict(angle=0.0, pos=(1.25, 0.55, 1.25), target=(0.45, 0.48, 0), lens=50),
    # full tilt (+0.176 raises +x): the right seat is HIGH, the left seat LOW; low and close cameras
    "close_high": dict(angle=0.176, pos=(1.15, 0.42, 0.95), target=(0.62, 0.5, 0), lens=50),
    "close_low": dict(angle=0.176, pos=(-0.5, 0.2, 0.9), target=(-0.62, 0.32, 0), lens=50),
}
for v in VIEWS:
    sp = VIEWSPEC[v]; build_scene(sp["angle"]); camera(sp["pos"], sp["target"], sp["lens"], sp.get("ortho"))
    sc.render.filepath = os.path.join(OUTDIR, "%s_%s.png" % (VAR, v)); bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath, flush=True)
