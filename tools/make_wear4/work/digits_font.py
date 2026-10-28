import sys
sys.path.insert(0,".")
from wl import *
FONT="/System/Library/Fonts/Supplemental/Arial Black.ttf"
def font_digit_part(d,res=3,bev=0.035,ext=0.07,bres=2,col=CREAM):
    cu=bpy.data.curves.new('t','FONT'); cu.body=str(d); cu.font=bpy.data.fonts.load(FONT)
    cu.extrude=ext; cu.bevel_depth=bev; cu.bevel_resolution=bres; cu.resolution_u=res; cu.offset=0.0
    cu.align_x='CENTER'; cu.align_y='CENTER'
    ob=bpy.data.objects.new('t',cu); bpy.context.scene.collection.objects.link(ob)
    dg=bpy.context.evaluated_depsgraph_get(); me=bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bm=bmesh.new(); bm.from_mesh(me); bpy.data.meshes.remove(me)
    # normalise: height 1 (y extent), centred on bbox in x,y,z
    xs=[v.co.x for v in bm.verts]; ys=[v.co.y for v in bm.verts]; zs=[v.co.z for v in bm.verts]
    h=max(ys)-min(ys); cx=(max(xs)+min(xs))/2; cy=(max(ys)+min(ys))/2; cz=(max(zs)+min(zs))/2
    for v in bm.verts: v.co=Vector(((v.co.x-cx)/h,(v.co.y-cy)/h,(v.co.z-cz)/h))
    return bm
def digit(d,col=CREAM,**k):
    reset()
    import bmesh as b
    for res,bres in ((3,1),(2,1),(2,0),(1,1),(1,0)):
        bm=font_digit_part(d,res=res,bres=bres,col=col); t=b.ops.triangulate(bm.copy() if False else bm,faces=bm.faces[:]) or 0
        if len(bm.faces)<=400: break
        bm.free()
    closed(bm,col,'digit',sharp=40)
    return dict(anchor='number',slot='body',tags=['sporty'],price=0,title=f'Digit {d}',authored_local=True,
      desc='Unit digit (height 1, centred on its box, +z out of the plate): bevelled extrusion of Arial Black. Scale by number_height; tint by replacing vertex colours.',anchor_rest=[0,0,0])
if __name__=='__main__':
    for d in range(10):
        reset(); bm=font_digit_part(d); n=len(bm.faces)
        import bmesh as b; b.ops.triangulate(bm,faces=bm.faces[:]); print("DIG",d,len(bm.faces)); bm.free()
