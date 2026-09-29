"""Bake the authored skeletal flight pose into a topology-safe glTF morph."""
import bpy
from pathlib import Path
HERE=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(HERE/'kaos_airborne.blend'))
flight={o.name:[v.co.copy() for v in o.data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}
bpy.ops.wm.open_mainfile(filepath=str(HERE/'kaos_one_hand.blend'))
grip={o.name:[v.co.copy() for v in o.data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}
bpy.ops.wm.open_mainfile(filepath=str(HERE/'kaos_climbing.blend'))
for obj in bpy.context.scene.objects:
    if obj.type!='MESH' or obj.name not in flight:continue
    assert len(obj.data.vertices)==len(flight[obj.name]),'Matching authoring topology required'
    if obj.data.shape_keys:obj.shape_key_clear()
    obj.shape_key_add(name='Basis')
    target=obj.shape_key_add(name='Airborne')
    for v,p in zip(target.data,flight[obj.name]):v.co=p
    assert len(obj.data.vertices)==len(grip[obj.name])
    target=obj.shape_key_add(name='OneHandGrip')
    for v,p in zip(target.data,grip[obj.name]):v.co=p
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'kaos_climbing.blend'))
bpy.ops.export_scene.gltf(filepath=str(HERE.parent/'kaos_climbing.glb'),export_format='GLB',export_yup=True,export_animations=False,export_morph=True)
