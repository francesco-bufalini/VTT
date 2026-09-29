"""Five cover-inspired miniatures using the existing CC0 MakeHuman library."""
import importlib.util
import math,sys
from pathlib import Path
import bpy
from mathutils import Vector

HERE=Path(__file__).parent
spec=importlib.util.spec_from_file_location('anatomy',HERE.parent.parent/'makehuman'/'build_anatomy.py')
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
PROFILES=[('horned','male',(.35,.39,.29),(.12,.10,.075),(.14,.12,.08)),
 ('ranger','male',(.52,.34,.23),(.22,.13,.075),(.075,.045,.025)),
 ('sun_elf','male',(.64,.47,.32),(.72,.65,.44),(.77,.65,.35)),
 ('hoplite','male',(.47,.31,.21),(.20,.14,.08),(.30,.035,.025)),
 ('night_elf','female',(.32,.33,.37),(.055,.045,.055),(.035,.025,.045)),
 ('feathered','female',(.40,.30,.19),(.13,.30,.33),(.55,.13,.045))]

def sphere(name,p,size,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=m.blender(Vector(p)))
    obj=bpy.context.object
    obj.name=name
    obj.scale=(size[0],size[2],size[1])
    obj.data.materials.append(mat)
    for f in obj.data.polygons: f.use_smooth=True
    return obj

def cord(name,points,width,mat):
    curve=bpy.data.curves.new(name,'CURVE')
    curve.dimensions='3D'
    curve.bevel_depth=width
    curve.bevel_resolution=2
    spline=curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for dst,p in zip(spline.points,points): dst.co=(*m.blender(Vector(p)),1)
    obj=bpy.data.objects.new(name,curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)

for name,sex,skin_color,cloth_color,hair_color in PROFILES:
    if '--male-only' in sys.argv and sex!='male':continue
    m.build(sex,token=True)
    for obj in bpy.context.scene.objects:
        obj.rotation_euler=(0,0,0)
    body=bpy.data.objects['Anatomy']
    skin=m.material('Skin',skin_color,roughness=.72)
    cloth=m.material('TexturedClothes',cloth_color,roughness=.8)
    hair=m.material('Hair',hair_color,roughness=.8)
    gold=m.material('AntiqueMetal',(.38,.27,.105),metallic=.7,roughness=.4)
    nodes=cloth.node_tree.nodes
    normal=nodes.new('ShaderNodeTexImage')
    normal.image=bpy.data.images.load(str(HERE.parent.parent/'polyhaven'/'leather_red_02_nor_gl_1k.jpg'),check_existing=True)
    normal.image.colorspace_settings.name='Non-Color'
    normal_map=nodes.new('ShaderNodeNormalMap')
    normal_map.inputs['Strength'].default_value=.45
    cloth.node_tree.links.new(normal.outputs['Color'],normal_map.inputs['Color'])
    cloth.node_tree.links.new(normal_map.outputs['Normal'],nodes['Principled BSDF'].inputs['Normal'])
    if name=='ranger':
        texture=nodes.new('ShaderNodeTexImage')
        texture.image=bpy.data.images.load(str(HERE.parent.parent/'polyhaven'/'leather_red_02_coll1_1k.jpg'),check_existing=True)
        cloth.node_tree.links.new(texture.outputs['Color'],nodes['Principled BSDF'].inputs['Base Color'])
    body.data.materials.clear()
    for mat in [skin,cloth,hair,gold]: body.data.materials.append(mat)
    for face in body.data.polygons:
        p=face.center
        face.material_index=0 if p.z>124 or (abs(p.x)>16 and p.z<82) else 1
        if p.z>140 or (p.z>129 and p.y>0): face.material_index=2
        if name=='ranger' and 127<p.z<133 and p.y<-8: face.material_index=2
    bpy.context.view_layer.objects.active=body
    dec=body.modifiers.new('MiniatureLOD','DECIMATE')
    dec.ratio=.85
    bpy.ops.object.modifier_apply(modifier=dec.name)
    # Draped shoulder cloak, with visible folds and a central fastening.
    vertices=[]
    faces=[]
    for j in range(25):
        t=j/24
        for i in range(25):
            u=i/24
            vertices.append(m.blender(Vector(((u-.5)*(27+t*9),118-t*80,-8-t*8+math.sin(u*math.pi*10)*t))))
    for j in range(24):
        for i in range(24):
            a=j*25+i
            faces.append((a,a+1,a+26,a+25))
    mesh=bpy.data.meshes.new('Cloak')
    mesh.from_pydata(vertices,[],faces)
    cloak=bpy.data.objects.new('Cloak',mesh)
    bpy.context.collection.objects.link(cloak)
    mesh.materials.append(cloth)
    for f in mesh.polygons:f.use_smooth=True
    for side in [-1,1]:
        sphere('Pauldron',(side*13,115,0),(5,3.2,5),gold if name in ['horned','sun_elf','hoplite'] else cloth)
        sphere('Brooch',(side*8,116,9),(1.3,1.3,.6),gold)
    if name=='horned':
        for s in [-1,1]:
            cord('CurvedHorn',[(s*(6+math.sin(t*math.pi)*7),141+math.sin(t*math.pi)*9,3-t*7) for t in [i/20 for i in range(21)]],1.15,gold)
        cord('Staff',[(25,0,5),(25,143,5)],.7,gold)
        sphere('Amber',(25,144,5),(2.5,4,2.5),m.material('Amber',(.8,.3,.045)))
    if name in ['ranger','sun_elf']:
        for i in range(20):
            a=i/20*math.tau
            if math.cos(a)>.65:continue
            cord('Hair',[(math.sin(a)*(7+t*3),141-t*(25 if name=='sun_elf' else 16),5+math.cos(a)*7-t*5) for t in [j/12 for j in range(13)]],.65,hair)
        if name=='ranger':
            sphere('Backpack',(0,99,-13),(10,15,5),cloth)
            sphere('Beard',(0,130,11),(4,4,2),hair)
    if name=='hoplite':
        sphere('Helmet',(0,141,5),(8,6,8),gold)
        for side in [-1,1]:cord('CheekGuard',[(side*6,139,12),(side*6,129,12)],1.7,gold)
        for i in range(18):
            a=i/17*math.pi
            cord('RedCrest',[(0,142+math.sin(a)*6,5+math.cos(a)*8),(0,144+math.sin(a)*16,5+math.cos(a)*12)],1.0,hair)
        cord('Spear',[(25,0,6),(25,156,6)],.7,gold)
        sphere('Shield',(-25,99,8),(11,15,2),gold)
    if name=='night_elf':
        for side in [-1,1]:
            sphere('PointedEar',(side*8,136,4),(3,1.2,1),skin)
            cord('HoodEdge',[(side*(7+t*3),145-t*21,7+t*2) for t in [j/15 for j in range(16)]],1.4,cloth)
        sphere('Hood',(0,141,1),(8,7,7),cloth)
        sphere('DrapedBelly',(0,91,8),(10,11,7),cloth)
    # Layered armor, seams and feather-shaped plates remain legible at token scale.
    for side in [-1,1]:
        for row in range(4):
            sphere('ShoulderLamella',(side*(13+row*.65),115-row*2,1),(5.1,1.6,5.2),gold if name!='ranger' else cloth)
        for y in [83,85,87]:
            cord('BracerTrim',[(side*20+math.sin(a)*2.0,y,3+math.cos(a)*2.0) for a in [j/24*math.tau for j in range(25)]],.20,gold)
    cord('Belt',[(math.sin(a)*14,77,math.cos(a)*11) for a in [j/48*math.tau for j in range(49)]],.65,gold)
    for j in range(9):
        sphere('BeltMedallion',((j-4)*2.3,76,11),(.65,.9,.35),gold)
    if name=='feathered':
        colors=[m.material('Feather'+str(i),c,roughness=.6) for i,c in enumerate([(.045,.28,.33),(.65,.16,.045),(.72,.47,.08),(.18,.35,.46)])]
        for side in [-1,1]:
            for row in range(3):
                for j in range(12):
                    p=(side*(12+j*1.0),114-row*9-j*.7,-3-row)
                    feather=sphere('LayeredFeather',p,(1.4,9+row, .45),colors[(j+row)%4])
                    feather.rotation_euler.y=side*.4
            for j in range(8):
                feather=sphere('CrestFeather',(side*(2+j*.8),145+j*.5,3-j*.5),(1.1,8,.45),colors[j%4])
                feather.rotation_euler.y=side*.4
        beak=sphere('AvianMask',(0,135,15),(2.3,1.6,5),gold)
        cord('FeatherStaff',[(25,0,5),(25,150,5)],.65,gold)
        for j in range(5):sphere('StaffPlume',(25+(j-2),153,5),(1,6,.4),colors[j%4])
    bpy.ops.object.empty_add()
    root=bpy.context.object
    root.name=name
    for obj in list(bpy.context.scene.objects):
        if obj!=root: obj.parent=root
    root.rotation_euler.z=math.pi
    root.scale=(1/72.5,)*3
    bpy.ops.export_scene.gltf(filepath=str(HERE.parent/('party_'+name+'.glb')),export_format='GLB',export_yup=True,export_animations=False)
