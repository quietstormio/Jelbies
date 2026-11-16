"""Preview renders of the CONVERTED park_camp_*.bin (vertex colour x baked AO) on a green ground, soft sun; 1200 px wide.
  Blender -b -P tools/make_camp_fence/render_fence.py -- <Resources dir> <out dir> [samples]
Writes post.png rail.png gate_post.png tent.png yard_assembled.png (a 4.2 x 7.0 yard: 3 x 5 bays of 1.4, gate bay in the front, tent back left, 0.9 pastel blob)."""
import sys, os, math, struct
import numpy as np
import bpy
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
RES, OUTDIR = args[0], args[1]; SAMPLES = int(args[2]) if len(args) > 2 else 48
os.makedirs(OUTDIR, exist_ok=True)

def read_bin(path):
    d = open(path, "rb").read(); nv, ni, npart = struct.unpack_from("<III", d, 0)
    he = 12 + npart * 40; ve = he + nv * 44
    return np.frombuffer(d, "<f4", nv * 11, he).reshape(nv, 11), np.frombuffer(d, "<u2", ni, ve).astype(int).reshape(-1, 3)
def g2b(p): return (p[0], -p[2], p[1])

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.render.resolution_x = 1200; sc.render.resolution_y = 800; sc.view_settings.view_transform = "Standard"; sc.cycles.max_bounces = 4
def s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
MAT = bpy.data.materials.new("vc"); MAT.use_nodes = True; nt = MAT.node_tree; nt.nodes.clear()
a1 = nt.nodes.new("ShaderNodeAttribute"); a1.attribute_name = "col"; a2 = nt.nodes.new("ShaderNodeAttribute"); a2.attribute_name = "ao"
mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MULTIPLY"; mx.inputs[0].default_value = 1.0
nt.links.new(a1.outputs["Color"], mx.inputs[6]); nt.links.new(a2.outputs["Color"], mx.inputs[7])
bs = nt.nodes.new("ShaderNodeBsdfPrincipled"); bs.inputs["Roughness"].default_value = 0.62
out = nt.nodes.new("ShaderNodeOutputMaterial"); nt.links.new(mx.outputs[2], bs.inputs["Base Color"]); nt.links.new(bs.outputs[0], out.inputs[0])
GM = bpy.data.materials.new("lawn"); GM.use_nodes = True
GM.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (s2l(0.30), s2l(0.50), s2l(0.25), 1); GM.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
bpy.ops.mesh.primitive_plane_add(size=60); bpy.context.active_object.data.materials.append(GM)
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.62, 0.78, 1.0, 1); bg.inputs["Strength"].default_value = 0.9
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.0; sun.angle = math.radians(9); sun.color = (1.0, 0.96, 0.88)
so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(48), 0, math.radians(-125))

MESH = {}
def mesh_for(n):
    if n in MESH: return MESH[n]
    V, F = read_bin(os.path.join(RES, "park_camp_%s.bin" % n))
    me = bpy.data.meshes.new(n); me.from_pydata([g2b(p) for p in V[:, 0:3]], [], [tuple(f) for f in F]); me.update()
    for p in me.polygons: p.use_smooth = True
    me.normals_split_custom_set_from_vertices([g2b(x) for x in V[:, 3:6]])
    ca = me.color_attributes.new("col", "FLOAT_COLOR", "POINT"); ca.data.foreach_set("color", np.hstack([V[:, 6:9], np.ones((len(V), 1))]).ravel())
    aa = me.color_attributes.new("ao", "FLOAT_COLOR", "POINT"); aa.data.foreach_set("color", np.hstack([np.repeat(V[:, 9:10], 3, 1), np.ones((len(V), 1))]).ravel())
    me.materials.append(MAT); MESH[n] = me; return me
def place(n, x, z, yaw=0.0):
    ob = bpy.data.objects.new(n, mesh_for(n)); sc.collection.objects.link(ob)
    ob.location = g2b((x, 0, z)); ob.rotation_euler = (0, 0, -yaw); return ob   # yaw about game y (up) = about blender z, sign flipped by the z mapping
def clear():
    for o in [o for o in bpy.data.objects if o.type == "MESH" and o.name.split(".")[0] in ("post", "rail", "gate_post", "tent", "blob")]: bpy.data.objects.remove(o)
def blob():
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=g2b((0.2, 0.45, 0.6))); o = bpy.context.active_object; o.name = "blob"
    o.scale = (1, 1, 1.0); bpy.ops.object.shade_smooth()
    m = bpy.data.materials.new("blobm"); m.use_nodes = True; m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (s2l(0.72), s2l(0.60), s2l(0.90), 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35; o.data.materials.append(m)
def camera(pos, target, lens=45):
    for o in [o for o in bpy.data.objects if o.type == "CAMERA"]: bpy.data.objects.remove(o)
    cam = bpy.data.cameras.new("c"); co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); cam.lens = lens
    co.location = g2b(pos); co.rotation_euler = (Vector(g2b(target)) - Vector(co.location)).to_track_quat("-Z", "Y").to_euler(); sc.camera = co
def shot(name):
    sc.render.filepath = os.path.join(OUTDIR, name + ".png"); bpy.ops.render.render(write_still=True); print("RENDERED", sc.render.filepath, flush=True)

sc.render.resolution_y = 900
for n, pos, tgt in (("post", (0.7, 0.55, 1.1), (0, 0.3, 0)), ("gate_post", (1.0, 0.75, 1.9), (0, 0.45, 0)), ("rail", (1.0, 0.5, 1.7), (0, 0.27, 0)), ("tent", (1.8, 1.3, 3.0), (0, 0.65, 0))):
    clear(); place(n, 0, 0); camera(pos, tgt, 50); shot(n)

# yard: 3 x 5 bays of 1.4 -> 4.2 x 7.0 (x -2.1..2.1, z -3.5..3.5); the front (+z) bay in the middle is the gate opening
clear(); S = 1.4; X = 2.1; Z = 3.5
for i in range(4): place("post", -X + i * S, -Z)
for j in range(1, 5): place("post", -X, -Z + j * S); place("post", X, -Z + j * S)
for x in (-X, X): place("post", x, Z)
for x in (-S / 2, S / 2): place("gate_post", x, Z)
for i in range(3): place("rail", -X + S / 2 + i * S, -Z)
for j in range(5):
    for x in (-X, X): place("rail", x, -Z + S / 2 + j * S, yaw=math.pi / 2)
place("rail", -X + S / 2, Z); place("rail", X - S / 2, Z)
place("tent", -1.9, -4.6, 0.0)
blob()
camera((6.2, 6.4, 9.2), (0, 0.4, -0.2), 40); shot("yard_assembled")
