"""User-supplied Hanoverian horse; original wings, harness and chariot."""
import bpy,math
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(HERE/'uploaded/16272_Hanoverian_Horse_Jumping_V1.obj'),forward_axis='Y',up_axis='Z')
deps=bpy.context.evaluated_depsgraph_get()
sources=[]
for o in list(bpy.data.objects):
    if o.type=='MESH':
        mesh=bpy.data.meshes.new_from_object(o.evaluated_get(deps),depsgraph=deps)
        coords=[o.matrix_world@v.co for v in mesh.vertices]
        sources.append((o.name,mesh,coords))
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
allpoints=[p for _,_,coords in sources for p in coords]
lo=Vector(tuple(min(p[i] for p in allpoints) for i in range(3)))
hi=Vector(tuple(max(p[i] for p in allpoints) for i in range(3)))
scale=2.18/(hi.y-lo.y)
def mat(name,c,metal=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.43 if metal else .7
    return m
ivory=mat('IvoryCoat',(.71,.73,.69));white=mat('FlightFeathers',(.82,.83,.80))
gold=mat('AntiqueGold',(.48,.32,.11),.72);dark=mat('Harness',(.055,.028,.018));eye=mat('BlueEyes',(.025,.25,.35),.3)
for name,mesh,coords in sources:
    for v,p in zip(mesh.vertices,coords):
        v.co=Vector((-(p.x-(lo.x+hi.x)/2)*scale,-(p.y-(lo.y+hi.y)/2)*scale+1,(p.z-lo.z)*scale+.10))
    mesh.materials.clear();mesh.materials.append(eye if name.startswith('Sphere') else white if name.startswith('Bezier') else ivory)
    for f in mesh.polygons:f.material_index=0;f.use_smooth=True
    obj=bpy.data.objects.new('Horse_'+name,mesh);bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj
    dec=obj.modifiers.new('HorseGameLOD','DECIMATE');dec.ratio=.55
    bpy.ops.object.modifier_apply(modifier=dec.name)
def pos(p):return Vector((p[0],-p[2],p[1]))
def box(name,p,size,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos(p));o=bpy.context.object;o.name=name
    o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material)
    bevel=o.modifiers.new('SoftEdges','BEVEL');bevel.width=.025;bevel.segments=2
def ellipsoid(name,p,size,material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=pos(p));o=bpy.context.object;o.name=name
    o.scale=(size[0],size[2],size[1]);o.data.materials.append(material)
    for f in o.data.polygons:f.use_smooth=True
    return o
def rod(name,points,r,material):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=3
    s=c.splines.new('POLY');s.points.add(len(points)-1)
    for a,p in zip(s.points,points):a.co=(*pos(p),1)
    o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(material)
def feather(name,start,end,width,material):
    # Lenticular cross sections, curved shaft and pointed tip, not capsule feathers.
    a,b=Vector(start),Vector(end);direction=(b-a).normalized()
    across=direction.cross(Vector((0,1,0))).normalized()
    normal=across.cross(direction).normalized()
    vertices=[];faces=[]
    for j in range(17):
        t=j/16;center=a.lerp(b,t)+normal*(math.sin(t*math.pi)*.035)
        w=max(.001,width*math.sin(math.pi*(.08+.92*t))**.7)
        for k in range(8):
            angle=k/8*math.tau
            p=center+across*(math.cos(angle)*w)+normal*(math.sin(angle)*w*.10)
            vertices.append(pos(p))
    for j in range(16):
        for k in range(8):
            faces.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    faces.extend([tuple(reversed(range(8))),tuple(128+k for k in range(8))])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material)
    for f in mesh.polygons:f.use_smooth=True
    rod('FeatherShaft',[a,a.lerp(b,.45)+normal*.04,a.lerp(b,.92)],.004,ivory)
box('Deck',(0,.59,1),(2,.12,2),dark)
for side in [-1,1]:
    box('SidePanel',(side*1,.87,.8),(.065,.5,1.6),gold)
    rod('TopRail',[(side*1,1.16,.02),(side*1,1.16,1.6)],.035,gold)
    rod('Shaft',[(side*.42,.65,-.8),(side*.68,.65,.1)],.03,gold)
    rod('Rein',[(side*.15,1.1,-1.7),(side*.45,.95,-.2),(side*.8,1.1,.2)],.012,dark)
    shoulder=Vector((side*.22,.97,-1.12))
    elbow=Vector((side*.85,1.37,-.95))
    wrist=Vector((side*1.5,1.65,-1.23))
    rod('WingLeadingEdge',[shoulder,elbow,wrist],.075,ivory)
    for j in range(12):
        t=j/11;start=shoulder.lerp(wrist,t)
        feather('SecondaryFlightFeather',start,start+Vector((side*(.18+t*.15),-.12,.64-t*.12)),.095,white)
    for j in range(10):
        t=j/9;start=elbow.lerp(wrist,.55+t*.45)
        end=start+Vector((side*(.42+.5*t),.08+.16*t,.62-.8*t))
        feather('PrimaryFlightFeather',start,end,.105-t*.025,white)
    for row in range(3):
        for j in range(13):
            t=j/12;start=shoulder.lerp(wrist,t)+Vector((0,.035+row*.012,row*.095))
            feather('LayeredCovert',start,start+Vector((side*.09,-.02,.24)),.065,ivory if row==0 else white)
    # Wheels rotate in the vertical YZ plane.
    for radius in [.40,.32]:
        rod('WheelRim',[(side*1.09,.42+math.sin(a)*radius,1+math.cos(a)*radius) for a in [j/64*math.tau for j in range(65)]],.026,gold)
    for j in range(10):
        a=j/10*math.tau
        rod('Spoke',[(side*1.09,.42,1),(side*1.09,.42+math.sin(a)*.39,1+math.cos(a)*.39)],.012,gold)
box('FrontShield',(0,.87,.02),(2,.5,.065),gold)
for j in range(9):
    ellipsoid('ShieldBoss',((j-4)*.2,.92,-.035),(.055,.10,.035),gold)
bpy.ops.export_scene.gltf(filepath=str(HERE.parent/'pegasus_chariot.glb'),export_format='GLB',export_animations=False,export_yup=True)
