"""Phenax miniature: fitted Greek-reference anatomy and original mask/drapery."""
import bpy,math,importlib.util
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).parent
spec=importlib.util.spec_from_file_location('anatomy',HERE.parent.parent/'makehuman/build_anatomy.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.build('male',token=True)
for obj in bpy.context.scene.objects:obj.rotation_euler=(0,0,0)
body=bpy.data.objects['Anatomy']
skin=m.material('PhenaxCosmicSkin',(.028,.011,.027),metallic=.15,roughness=.45)
gold=m.material('PhenaxAgedGold',(.62,.34,.10),metallic=.8,roughness=.3)
cloth=m.material('PhenaxMidnightCloth',(.045,.038,.048),roughness=.8)
body.data.materials.clear();body.data.materials.append(skin)

def mesh(name,points,faces,material,smooth=True):
    data=bpy.data.meshes.new(name);data.from_pydata([m.blender(Vector(p)) for p in points],[],faces);data.update()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);data.materials.append(material)
    for f in data.polygons:f.use_smooth=smooth
    return obj

def cord(name,points,width,material):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=width;curve.bevel_resolution=2
    spline=curve.splines.new('POLY');spline.points.add(len(points)-1)
    for dst,p in zip(spline.points,points):dst.co=(*m.blender(Vector(p)),1)
    obj=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(obj);curve.materials.append(material)

# Mask is a shaped metal shell, with sockets and a projecting nose ridge.
for side in [-1,1]:
    points=[(side*.25,145,9),(side*5.8,143,8),(side*6.5,137,10),
            (side*4.8,134,12),(side*3.8,129,11),(side*.4,127.5,13),
            (side*.4,135,14.3),(side*1.8,139,11.2),
            (side*4.5,139,11),(side*1.8,137.8,12)]
    mask=mesh('GoldenMask',points,[(0,1,8,7),(1,2,8),(2,3,9,8),(3,4,5,6,9),(6,7,9),(4,5,6)],gold,False)
    solid=mask.modifiers.new('MetalThickness','SOLIDIFY');solid.thickness=.35
    for j in range(3):
        cord('MaskWing',[(side*(5+j*.7),140-j,7),(side*(9+j*1.2),146+j*2,4),(side*(10+j*1.6),150+j*3,2)],.6-j*.12,gold)
    # Forearm vambraces fit the existing arm instead of floating bracelet rings.
    for y in [79,84,90]:
        cord('GoldArmRings',[(side*20+math.sin(a)*2.5,y,3+math.cos(a)*2.5) for a in [i/32*math.tau for i in range(33)]],.35,gold)
    for j in range(4):
        cord('VambraceRib',[(side*20+math.sin(j/4*math.tau)*2.5,y,3+math.cos(j/4*math.tau)*2.5) for y in [78,84,91]],.45,gold)
    # A broad asymmetric stole, supported at the shoulders and trailing behind.
    points=[];faces=[]
    for row in range(33):
        t=row/32
        for column in range(9):
            u=column/8
            points.append((side*(8+u*9+math.sin(t*math.pi)*13),119-93*t,
                           4-24*t+math.sin(t*9+u*2)*2+math.sin(u*math.pi*5)*1.2))
    for row in range(32):
        for column in range(8):
            a=row*9+column;faces.append((a,a+1,a+10,a+9))
    obj=mesh('FateStole',points,faces,cloth)
    solid=obj.modifiers.new('FabricThickness','SOLIDIFY');solid.thickness=.22
    for edge in [0,8]:cord('StoleBorder',[points[row*9+edge] for row in range(33)],.22,gold)
# Modest layered loincloth, with a gathered rather than cylindrical silhouette.
points=[];faces=[]
for row in range(17):
    t=row/16
    for column in range(33):
        u=column/32
        points.append(((u-.5)*27,118-t*8-math.sin(u*math.pi)*5,
                       8+math.sin(u*math.pi)*3+math.sin(t*math.pi*5)*.6))
for row in range(16):
    for column in range(32):
        a=row*33+column;faces.append((a,a+1,a+34,a+33))
mesh('GatheredShoulderWrap',points,faces,cloth)
cord('WrapBorder',[points[16*33+i] for i in range(33)],.2,gold)
points=[];faces=[]
for row in range(25):
    t=row/24
    for column in range(49):
        a=column/48*math.tau
        r=12+t*4+math.sin(a*12)*t*.8
        points.append((math.sin(a)*r,77-t*51,(math.cos(a)*r*.8)))
for row in range(24):
    for column in range(48):
        a=row*49+column;faces.append((a,a+1,a+50,a+49))
mesh('LayeredRobe',points,faces,cloth)
cord('WaistGirdle',[(math.sin(a)*12.5,77,math.cos(a)*10.2) for a in [i/48*math.tau for i in range(49)]],.7,gold)
# UVs for the existing licensed fabric normal map.
for obj in list(bpy.context.scene.objects):
    if obj.type!='MESH' or obj==body:continue
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project();bpy.ops.object.mode_set(mode='OBJECT')
texture=cloth.node_tree.nodes.new('ShaderNodeTexImage')
texture.image=bpy.data.images.load(str(HERE.parent.parent/'polyhaven/leather_red_02_nor_gl_1k.jpg'))
texture.image.colorspace_settings.name='Non-Color'
normal=cloth.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.35
cloth.node_tree.links.new(texture.outputs['Color'],normal.inputs['Color'])
cloth.node_tree.links.new(normal.outputs['Normal'],cloth.node_tree.nodes['Principled BSDF'].inputs['Normal'])
bpy.ops.object.empty_add();root=bpy.context.object;root.name='Phenax'
for obj in list(bpy.context.scene.objects):
    if obj!=root:obj.parent=root
root.rotation_euler.z=math.pi
root.scale=(1/50,)*3
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'phenax.blend'))
bpy.ops.export_scene.gltf(filepath=str(HERE.parent/'phenax.glb'),export_format='GLB',export_yup=True,export_animations=False)
