"""Preview renders of exported OBJs on a sky-blue background with flat (baked) colours: Blender -b -P prev.py -- <export dir> <out dir> ids..."""
import sys, os, bpy, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]; E, O, ids = a[0], a[1], a[2:]
os.makedirs(O, exist_ok=True)
def load(path):
    V = []; C = []; F = []; N = []
    for line in open(path):
        t = line.split()
        if not t: continue
        if t[0] == "v": V.append(tuple(map(float, t[1:4]))); C.append(tuple(map(float, t[4:7])))
        elif t[0] == "f": F.append(tuple(int(x.split("//")[0]) - 1 for x in t[1:4]))
    me = bpy.data.meshes.new("m"); me.from_pydata(V, [], F); me.update()
    ca = me.color_attributes.new("c", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(C): ca.data[i].color = (c[0] * 1.35, c[1] * 1.35, c[2] * 1.35, 1)
    return me, V
for iid in ids:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    me, V = load(f"{E}/{iid}.obj")
    ob = bpy.data.objects.new(iid, me); bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons: p.use_smooth = True
    sc = bpy.context.scene; sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading; sh.light = "STUDIO"; sh.color_type = "VERTEX"; sh.show_shadows = False; sh.show_cavity = False
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    R = int(os.environ.get("PREV_RES", "560")); sc.render.resolution_x = R; sc.render.resolution_y = R
    w = bpy.data.worlds.new("w"); w.color = (0.62, 0.78, 0.95); sc.world = w
    sh.background_type = "WORLD"
    hh = max(v[1] for v in V)
    ob.rotation_euler = (math.pi / 2, 0, 0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    for name, (az, el) in (("a", (24, 12)), ("b", (-50, 20))):
        d = 3.2 + hh * 1.5; tgt = Vector((0, 0, hh * 0.47))
        azr, elr = math.radians(az), math.radians(el)
        cam.location = tgt + Vector((math.sin(azr) * math.cos(elr), -math.cos(azr) * math.cos(elr), math.sin(elr))) * d
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 50
        sc.render.filepath = f"{O}/{iid}_{name}.png"; bpy.ops.render.render(write_still=True)
    print("PREV", iid)
