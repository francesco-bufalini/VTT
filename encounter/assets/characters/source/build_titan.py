"""Reuse the licensed anatomical source as one instanced stone relief mesh."""
import bpy
import bmesh
from pathlib import Path
from mathutils import Vector
root = Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(root/'kaos_anatomy.blend'))
body = bpy.data.objects.get('Anatomy')
for obj in list(bpy.data.objects):
    if obj != body:
        bpy.data.objects.remove(obj, do_unlink=True)
body.rotation_euler = (0,0,0)
bm=bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z<127 or abs(v.co.x)>10],context='VERTS')
for v in bm.verts:
    v.co -= Vector((0,-6,136))
    # Slightly exaggerated brow/cheek planes read as monumental relief.
    v.co.x *= 1.1
bm.to_mesh(body.data)
bm.free()
body.name='TitanRelief'
dec=body.modifiers.new('ReliefLOD','DECIMATE')
dec.ratio=.45
bpy.context.view_layer.objects.active=body
bpy.ops.object.modifier_apply(modifier=dec.name)
bpy.ops.export_scene.gltf(filepath=str(root.parent/'titan_relief.glb'),export_format='GLB',export_yup=True,export_animations=False)
