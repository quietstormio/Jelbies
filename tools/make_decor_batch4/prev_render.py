"""Quick look at exported OBJs (vertex colours, workbench): Blender -b -P prev_render.py -- <export dir> <out dir> ids..."""
import sys, os, bpy, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]; E, O, ids = a[0], a[1], a[2:]
os.makedirs(O, exist_ok=True)
def load(path):
    V = []; C = []; F = []
    for line in open(path):
        t = line.split()
        if not t: continue
        if t[0] == "v": V.append(tuple(map(float, t[1:4]))); C.append(tuple(map(float, t[4:7])))
        elif t[0] == "f": F.append(tuple(int(x.split("//")[0]) - 1 for x in t[1:4]))
    me = bpy.data.meshes.new("m"); me.from_pydata(V, [], F); me.update()
    ca = me.color_attributes.new("c", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(C): ca.data[i].color = (c[0], c[1], c[2], 1)
    return me, V
for iid in ids:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    me, V = load(f"{E}/{iid}.obj")
    ob = bpy.data.objects.new(iid, me); bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons: p.use_smooth = True
    sc = bpy.context.scene; sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading; sh.light = "STUDIO"; sh.color_type = "VERTEX"; sh.show_shadows = True
    sc.render.resolution_x = sc.render.resolution_y = 520
    sc.display.shading.background_type = "VIEWPORT"; sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.55, 0.52, 0.5)
    hh = max(v[1] for v in V); wx = max(abs(v[0]) for v in V)
    # game coords y up, +z toward camera; blender is z up: remap by rotating the object
    ob.rotation_euler = (math.pi / 2, 0, 0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    for name, (az, el) in (("a", (28, 18)), ("b", (-32, 14))):
        d = 3.0 + hh * 1.5; tgt = Vector((0, 0, hh * 0.45))
        azr, elr = math.radians(az), math.radians(el)
        # game +z (toward viewer) -> blender -y after the x-rotation
        cam.location = tgt + Vector((math.sin(azr) * math.cos(elr), -math.cos(azr) * math.cos(elr), math.sin(elr))) * d
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 50
        sc.render.filepath = f"{O}/{iid}_{name}.png"; bpy.ops.render.render(write_still=True)
    print("PREV", iid)
