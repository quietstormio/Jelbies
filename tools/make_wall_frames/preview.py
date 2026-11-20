"""Quick look at a built frame in Blender (workbench, vertex colours): called from build_frames.py with --preview <dir>."""
import bpy, os, math
import dk
from mathutils import Vector

def srgb_to_lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def render(iid, out_dir):
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    verts = []; faces = []; cols = []
    off = 0
    for g in dk.GROUPS:
        for p in g['parts']:
            verts += p['P']; cols += p['C']; faces += [(a + off, b + off, c + off) for a, b, c in p['F']]; off += len(p['P'])
    me = bpy.data.meshes.new('f'); me.from_pydata(verts, [], faces); me.update()
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(cols): ca.data[i].color = (*[srgb_to_lin(x) for x in c], 1.0)
    for pl in me.polygons: pl.use_smooth = True
    ob = bpy.data.objects.new('f', me); bpy.context.scene.collection.objects.link(ob)
    # a plain wall plane behind it
    wall = bpy.data.meshes.new('w'); wall.from_pydata([(-3, -3, -0.001), (3, -3, -0.001), (3, 3, -0.001), (-3, 3, -0.001)], [], [(0, 1, 2, 3)])
    wo = bpy.data.objects.new('w', wall); bpy.context.scene.collection.objects.link(wo)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'VERTEX'; sh.studio_light = 'rim.sl' if False else sh.studio_light
    sc.render.resolution_x = 900; sc.render.resolution_y = 900
    cam = bpy.data.objects.new('c', bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.6
    cam.location = (0.0, -0.45, 3.0); cam.rotation_euler = (math.radians(8), 0, 0)
    sc.view_settings.view_transform = 'Standard'
    os.makedirs(out_dir, exist_ok=True)
    sc.render.filepath = os.path.join(out_dir, iid + ".png")
    bpy.ops.render.render(write_still=True)
