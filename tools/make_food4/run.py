import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib, foods, lib
from lib import *
import foods3
import foods4
from foods import BUILD
V = Vector

FLOOR = dict(minipizza=-0.26, minipizza_whole=-0.26)    # offset (u) of the mesh bottom below the piece centre in the game (default -0.56)
VARIANTS = dict(nuggets=1)

def make_mesh(data, name):
    P, N, C, F = data
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in P], [], [tuple(f) for f in F])
    me.shade_smooth()
    me.normals_split_custom_set_from_vertices([tuple(n) for n in N])
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(C):
        ca.data[i].color = (*lin(c), 1.0)
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.get('foodmat')
    if mat is None:
        mat = bpy.data.materials.new('foodmat'); mat.use_nodes = True
        nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
        cn = nt.nodes.new('ShaderNodeVertexColor'); cn.layer_name = 'Col'
        nt.links.new(cn.outputs['Color'], bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value = 0.62
        for k in ('Specular IOR Level',):
            if k in bsdf.inputs: bsdf.inputs[k].default_value = 0.3
    ob.data.materials.append(mat)
    return ob

def build(fid, v=0):
    reset(); BUILD[fid](v)
    P, N, C, F = merged()
    zmin = min(p[2] for p in P)
    P = [(p[0], p[1], p[2]-zmin) for p in P]          # sit on z = 0
    return (P, N, C, F), len(F)

def export(fid, data, ntri, variant=None):
    P, N, C, F = data
    off = FLOOR.get(fid, -0.56)
    G = [(p[0]*0.1, (p[2]+off)*0.1, -p[1]*0.1) for p in P]       # game units, y up, +z toward the camera
    GN = [(n[0], n[2], -n[1]) for n in N]
    name = fid if variant in (None, 0) else f"{fid}_{variant}"
    with open(f"{S}/export/{name}.obj", "w") as fh:
        fh.write(f"# {name}: game units (y up, +z toward camera), piece centre at origin, bottom at y={off*0.1:.3f}\n# v x y z r g b  (r g b = LINEAR vertex colour)\n")
        for g, c in zip(G, C): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f\n" % (*g, *lin(c)))
        for n in GN: fh.write("vn %.4f %.4f %.4f\n" % n)
        for a, b, c in F: fh.write("f %d//%d %d//%d %d//%d\n" % (a+1, a+1, b+1, b+1, c+1, c+1))
    mn = [min(g[i] for g in G) for i in range(3)]; mx = [max(g[i] for g in G) for i in range(3)]
    grip = [0.0, 0.0, 0.0]
    if fid == "popsicle": grip = [0.0, off*0.1 + 0.016, -0.12]
    info = dict(id=name, tris=len(F), verts=len(G), bounds_min=[round(x, 4) for x in mn], bounds_max=[round(x, 4) for x in mx],
                size=[round(mx[i]-mn[i], 4) for i in range(3)], pivot="mesh origin = piece centre (same convention as StoreFoodModels: plate surface at y = floor_offset)",
                floor_offset_y=round(off*0.1, 3), grip_point=grip, color_space="linear RGB in extra v columns", units="game units, scale s multiplies")
    json.dump(info, open(f"{S}/export/{name}.json", "w"), indent=1)
    return info

# ---------------- scene ----------------
def setup_scene(W, H):
    sc = bpy.context.scene
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
    try: sc.eevee.taa_render_samples = 48
    except Exception: pass
    for k, val in (('use_raytracing', False), ('use_shadows', True)):
        try: setattr(sc.eevee, k, val)
        except Exception: pass
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes['Background']; bg.inputs['Color'].default_value = (0.93, 0.88, 0.78, 1); bg.inputs['Strength'].default_value = 0.55
    sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 1.5; sun.angle = math.radians(22); sun.color = (1.0, 0.96, 0.88)
    so = bpy.data.objects.new('sun', sun); bpy.context.scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(48), math.radians(8), math.radians(-35))
    fill = bpy.data.lights.new('fill', 'AREA'); fill.energy = 35; fill.size = 8; fill.color = (1.0, 0.9, 0.85)
    fo = bpy.data.objects.new('fill', fill); bpy.context.scene.collection.objects.link(fo)
    fo.location = (4, -6, 5); fo.rotation_euler = (math.radians(55), 0, math.radians(35))

def flat_obj(prof, segs, col, name):
    bm = lathe(prof, segs)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.shade_smooth()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*lin(col), 1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.7
    ob.data.materials.append(m); return ob

def add_plate(r):
    prof = [(0, -0.12), (r*0.72, -0.12), (r*0.88, -0.06), (r, 0.0), (r+0.03, 0.06), (r-0.03, 0.09), (r*0.9, 0.0), (r*0.5, -0.03+0.0), (0, -0.03)]
    # plate: top surface at z=0 inside, raised rim
    prof = [(0, -0.2), (r*0.8, -0.2), (r*0.97, -0.12), (r+0.04, 0.02), (r+0.04, 0.09), (r-0.05, 0.1), (r-0.14, 0.0), (r*0.6, -0.0), (0, 0.0)]
    flat_obj(prof, 64, (1.0, 0.99, 0.96), 'plate')
    flat_obj([(r-0.13, 0.002), (r-0.05, 0.002), (r-0.05, 0.004), (r-0.13, 0.004)] if False else [(r*0.0+0.0, 0.0)] , 3, (1, 1, 1), 'x') if False else None
    fl = flat_obj([(0, -0.2), (40, -0.2)], 8, (1.0, 0.985, 0.93), 'floor')

def camera(target, az, el, dist, lens, W, H):
    cam = bpy.data.cameras.new('c'); cam.lens = lens; cam.sensor_width = 36
    co = bpy.data.objects.new('c', cam); bpy.context.scene.collection.objects.link(co)
    t = V(target)
    pos = t + V((math.sin(az)*math.cos(el), -math.cos(az)*math.cos(el), math.sin(el)))*dist
    co.location = pos
    d = (t - pos); co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = co

def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

LAYOUT = {}
def place_plate(fid, datas):
    if fid == "minipizza":
        add_plate(3.7)
        T = V((0, -1.2, 0))
        for k, a in enumerate([0.7, 0.0, -0.7]):
            ob = make_mesh(datas[k % len(datas)], f'p{k}')
            ob.rotation_euler = (0, 0, a)
            ob.location = T + V((math.sin(a)*-1.3*-1, 0, 0))*0 + V((0, 0, 0))
            # tip (0,-1.3) rotated -> keep tips at T
            R = Matrix.Rotation(a, 3, 'Z')
            ob.location = T - R @ V((0, -1.3, 0)) + V((0, 0, 0))
    else:
        add_plate(3.0)
        xs = [-1.75, 0.0, 1.75]; ys = [0.05, -0.3, 0.05]
        yaws = [0.25, -0.15, 0.1] if fid not in ("popsicle",) else [0.0, 0.0, 0.0]
        if fid == 'taco': yaws = [1.45, 1.6, 1.35]
        if fid == "sandwich": yaws = [0, 0, 0]
        for k in range(3):
            ob = make_mesh(datas[k % len(datas)], f'p{k}')
            ob.location = (xs[k], ys[k], 0.0); ob.rotation_euler = (0, 0, yaws[k])

def main(ids):
    for fid in ids:
        nv = VARIANTS.get(fid, 1)
        datas = []
        for v in range(nv):
            d, n = build(fid, v); datas.append(d)
            info = export(fid, d, n, v)
            print("EXPORT", info['id'], info['tris'], info['size'])
        # plate render (the whole pizza is one big piece: hero only)
        if fid != 'minipizza_whole':
            setup_scene(1000, 640)
            place_plate(fid, datas)
            camera((0, -0.35, 0.3), 0.0, math.radians(36), 10.6 if fid == 'minipizza' else 9.6, 55, 1000, 640)
            render(f"{S}/renders/{fid}_plate.png")
        # hero
        setup_scene(700, 700)
        add_plate(3.6 if fid == 'minipizza_whole' else 1.7)
        ob = make_mesh(datas[0], 'hero'); ob.rotation_euler = (0, 0, {'nuggets': 0.3, 'taco': 1.2}.get(fid, 0.0))
        camera((0, 0, 0.35 if fid != 'popsicle' else 0.3), math.radians(28), math.radians(34), {'minipizza': 6.2, 'minipizza_whole': 9.5}.get(fid, 4.3), 55, 700, 700)
        render(f"{S}/renders/{fid}_hero.png")

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--")+1:]
    main(args)
