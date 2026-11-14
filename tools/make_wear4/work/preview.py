"""Headless preview of a wearable on the rest body (no app, no GPU): blender -b -P preview.py -- OUTDIR LABEL ITEM [flags]
ITEM = <art id>[:key=value,...] (looked up in items5..9 REG + VARIANTS, kwargs overridden). flags: --pip (draw Pip's spikes + tail), --views=front,q34,side,q34b,back,room,top
The body is drawn from wl.surface_ray (whole body, arms and feet). Writes OUTDIR/LABEL_<view>.png (Workbench, back faces culled like the app)."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import bpy, bmesh, math, json
import numpy as np
from mathutils import Vector
from wl import *
import lib
args = sys.argv[sys.argv.index('--') + 1:]
outdir, label, spec = args[0], args[1], args[2]
flags = [a for a in args[3:] if a.startswith('--')]
PIP = '--pip' in flags
VIEWS = ['front', 'q34', 'side', 'q34b', 'back', 'room', 'top']
for f in flags:
    if f.startswith('--views='): VIEWS = f[8:].split(',')
RES = int([f for f in flags if f.startswith('--res=')][0][6:]) if any(f.startswith('--res=') for f in flags) else 520
os.makedirs(outdir, exist_ok=True)

def find(iid):
    for name in ("items5", "items6", "items7", "items8", "items9"):
        m = __import__(name)
        for rid, fn, kw, anchor in m.REG:
            if rid == iid: return fn, dict(kw), anchor
        for rid, fn, kw, anchor in getattr(m, 'VARIANTS', []):
            if rid == iid: return fn, dict(kw), anchor
    raise SystemExit("unknown item " + iid)
iid, _, kws = spec.partition(':')
fn, kw, anchor = find(iid)
for kv in [k for k in kws.split(',') if k]:
    k, v = kv.split('='); kw[k] = eval(v)
reset(); meta = fn(**kw)
print("ITEM", iid, "tris", tri_count(), "verts", sum(len(p['P']) for p in PARTS))

# ---------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x = sc.render.resolution_y = RES
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'VERTEX'
sc.display.shading.show_backface_culling = True
sc.display.shading.show_cavity = False; sc.display.shading.show_shadows = False
sc.view_settings.view_transform = 'Standard'
sc.display.shading.background_type = 'WORLD'
sc.world = bpy.data.worlds.new('w'); sc.world.color = (0.93, 0.80, 0.66)
sc.render.film_transparent = False

def mk_obj(name, P, N, C, F, smooth=True):
    me = bpy.data.meshes.new(name); me.from_pydata([tuple(p) for p in P], [], [tuple(f) for f in F]); me.update()
    if N is not None:
        try: me.normals_split_custom_set_from_vertices([tuple(n) for n in N])
        except Exception as e: print("normals", e)
    for p in me.polygons: p.use_smooth = True
    a = me.color_attributes.new('c', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(C): a.data[i].color = (*c, 1.0)
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob); return ob

# body
ys = np.linspace(0.105, B.top - 0.003, 150); phs = np.linspace(0, 2 * math.pi, 160, endpoint=False)
Y, PH = np.meshgrid(ys, phs, indexing='ij')
BP, BN = surface_ray(Y, PH, arms=True)
nY, nP = Y.shape; P = BP.reshape(-1, 3); Nn = BN.reshape(-1, 3)
F = []
for j in range(nY - 1):
    for i in range(nP):
        a = j * nP + i; b = j * nP + (i + 1) % nP; c = (j + 1) * nP + (i + 1) % nP; d = (j + 1) * nP + i
        F += [(a, c, b), (a, d, c)]
bodycol = (0.45, 0.66, 0.92)
C = [lin(bodycol)] * len(P)
mk_obj('body', P, Nn, C, F)
if PIP:
    g = json.load(open(os.path.join(HERE, '..', 'art', 'pip_geometry.json')))
    sp = [v for v in g['spikeVertices']]
    bm = bmesh.new()
    for v in sp:
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.009, matrix=__import__('mathutils').Matrix.Translation(v[:3]))
    me = bpy.data.meshes.new('spk'); bm.to_mesh(me); a = me.color_attributes.new('c', 'FLOAT_COLOR', 'POINT')
    for i in range(len(me.vertices)): a.data[i].color = (*lin((0.95, 0.55, 0.15)), 1)
    sc.collection.objects.link(bpy.data.objects.new('spk', me))
    bm2 = bmesh.new()
    for s in g['tailSpheres']:
        if float(B.sdf(s[0], s[1], s[2])) > 0.0:
            bmesh.ops.create_uvsphere(bm2, u_segments=14, v_segments=8, radius=s[3], matrix=__import__('mathutils').Matrix.Translation(s[:3]))
    me2 = bpy.data.meshes.new('tail'); bm2.to_mesh(me2); a = me2.color_attributes.new('c', 'FLOAT_COLOR', 'POINT')
    for i in range(len(me2.vertices)): a.data[i].color = (*lin((0.90, 0.45, 0.12)), 1)
    sc.collection.objects.link(bpy.data.objects.new('tail', me2))

# item (parts are already in rest space)
Pm, Nm, Cm, Fm = lib.merged()
mk_obj('item', Pm, Nm, [lin(c) if False else c for c in Cm], Fm)
# colours in PARTS are sRGB -> linear for Workbench
ob = bpy.data.objects['item']; a = ob.data.color_attributes['c']
for i, c in enumerate(Cm): a.data[i].color = (*lin(c), 1.0)

if '--wb' not in flags:
    sc.render.engine = 'BLENDER_EEVEE'
    sc.eevee.taa_render_samples = 16
    mat = bpy.data.materials.new('m'); mat.use_nodes = True; nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']; at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_name = 'c'
    nt.links.new(at.outputs['Color'], bsdf.inputs['Base Color']); bsdf.inputs['Roughness'].default_value = 0.65
    mat.use_backface_culling = True
    for o in bpy.data.objects:
        if o.type == 'MESH': o.data.materials.append(mat)
    sc.view_settings.view_transform = 'Standard'
    sc.world.use_nodes = True; bg = sc.world.node_tree.nodes['Background']; bg.inputs['Color'].default_value = (0.93, 0.80, 0.66, 1); bg.inputs['Strength'].default_value = 0.55
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 2.2; sc.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(25)); sun.data.angle = math.radians(25)
    sun.rotation_euler = (math.radians(-55), math.radians(15), math.radians(20))
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 85; cam.data.clip_end = 50
TARGET = Vector((0, 0.50, 0))
def view(name):
    # (azimuth deg from +z toward +x, elevation deg, distance, target y)
    return dict(front=(0, 4, 4.4, 0.50), q34=(38, 6, 4.4, 0.50), side=(90, 4, 4.4, 0.50), q34b=(142, 6, 4.4, 0.50), back=(180, 4, 4.4, 0.50),
                room=(12, 35, 4.8, 0.55), top=(15, 66, 4.6, 0.45), low=(0, -8, 4.4, 0.50))[name]
FOC = [f for f in flags if f.startswith('--focus=')]
BODYC = [f for f in flags if f.startswith('--body=')]
for v in VIEWS:
    az, el, dist, ty = view(v)
    if FOC: ty, dist = [float(x) for x in FOC[0][8:].split(',')]; az = math.radians(az); el = math.radians(el)
    t = Vector((0, ty, 0))
    cam.location = t + Vector((math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el))) * dist
    zc_ = (cam.location - t).normalized(); xc_ = Vector((0, 1, 0)).cross(zc_).normalized(); yc_ = zc_.cross(xc_)
    from mathutils import Matrix
    cam.matrix_world = Matrix(((xc_.x, yc_.x, zc_.x, cam.location.x), (xc_.y, yc_.y, zc_.y, cam.location.y), (xc_.z, yc_.z, zc_.z, cam.location.z), (0, 0, 0, 1)))
    sc.render.filepath = os.path.join(outdir, f"{label}_{v}.png"); bpy.ops.render.render(write_still=True)
print("DONE", label)
