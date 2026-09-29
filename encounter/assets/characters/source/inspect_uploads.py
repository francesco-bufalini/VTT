import bpy, math
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).parent
OUT=Path('C:/Users/fedeb/Documents/Codex/outputs/imports')
OUT.mkdir(parents=True,exist_ok=True)
for path in (HERE/'uploaded').glob('*.obj'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=str(path),forward_axis='Y',up_axis='Z')
    objects=list(bpy.context.scene.objects)
    points=[o.matrix_world@v.co for o in objects if o.type=='MESH' for v in o.data.vertices]
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    print('MODEL',path.name,'BOUNDS',tuple(low),tuple(high),flush=True)
    for o in objects:
        if o.type=='MESH':print('OBJECT',o.name,len(o.data.vertices),len(o.data.polygons),flush=True)
    center=(low+high)/2
    size=max(high-low)
    for o in objects:
        if o.type=='MESH':
            o.data.materials.clear()
            for p in o.data.polygons:p.use_smooth=True
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=12
    scene.render.resolution_x=800
    scene.render.resolution_y=800
    scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('World')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.13,.13,.13,1)
    for offset,energy in [((1,-1,2),1400),((-1,-.4,1),900)]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*size)
        light=bpy.context.object
        light.data.energy=energy*size*size*.015
        light.data.shape='DISK';light.data.size=size
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=center+Vector((.9,-1.8,.55))*size)
    camera=bpy.context.object
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=size*1.2
    scene.camera=camera
    scene.render.filepath=str(OUT/(path.stem+'.png'))
    bpy.ops.render.render(write_still=True)
