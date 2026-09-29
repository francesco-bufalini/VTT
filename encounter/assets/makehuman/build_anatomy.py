"""Build original posed variants from CC0 MakeHuman data; no MakeHuman code used."""
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix, Quaternion

ROOT = Path(__file__).parent
OUT = ROOT.parent / "characters"
OUT.mkdir(exist_ok=True)
(OUT/'source').mkdir(exist_ok=True)

# Preserve OBJ vertex IDs because .target deltas refer to the original topology.
def read_source():
    vertices, uvs, faces, groups = [], [], [], {}
    group = ""
    for line in (ROOT / "base.obj").read_text().splitlines():
        fields = line.split()
        if not fields or fields[0].startswith('#'):
            continue
        if fields[0] == 'v':
            vertices.append(Vector(tuple(map(float,fields[1:4]))))
        elif fields[0] == 'vt':
            uvs.append(tuple(map(float,fields[1:3])))
        elif fields[0] == 'g':
            group=fields[1]
            groups.setdefault(group,set())
        elif fields[0] == 'f':
            corners=[tuple(int(n)-1 for n in f.split('/') if n) for f in fields[1:]]
            groups[group].update(c[0] for c in corners)
            if group == 'body':
                faces.append(corners)
    return vertices,uvs,faces,groups

def material(name,color,metallic=0,roughness=0.5):
    result=bpy.data.materials.new(name)
    result.diffuse_color=(*color,1)
    result.use_nodes=True
    bsdf=result.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Roughness'].default_value=roughness
    bsdf.inputs['Metallic'].default_value=metallic
    return result

def blender(point):
    return Vector((point.x,-point.z,point.y))

def clamp(value, minimum, maximum):
    return max(minimum, min(maximum, value))

def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 0.0
    t = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

def bell(value, center, width):
    return math.exp(-((value - center) / width) ** 2)

def sculpt_klothis(points, body_ids):
    result = [p.copy() for p in points]
    for index in body_ids:
        p = result[index]
        y = p.y
        ax = abs(p.x)

        torso_mask = 1.0 - smoothstep(15.0, 22.0, ax)
        lower_mask = 1.0 - smoothstep(17.0, 24.0, ax)

        hips = bell(y, 77.0, 12.0) * lower_mask
        upper_thigh = bell(y, 62.0, 18.0) * lower_mask
        waist = bell(y, 95.0, 9.0) * torso_mask
        bust = bell(y, 109.0, 10.5) * torso_mask
        shoulder = bell(y, 117.5, 7.5) * torso_mask

        p.x *= (
            1.0
            + 0.12 * hips
            + 0.055 * upper_thigh
            - 0.11 * waist
            + 0.045 * bust
            + 0.025 * shoulder
        )
        p.z *= (
            1.0
            + 0.075 * hips
            + 0.035 * upper_thigh
            - 0.05 * waist
            + 0.13 * bust
        )

        if y > 127.0 and ax < 8.8:
            lower_face = bell(y, 132.5, 4.6)
            p.x *= 1.0 - 0.045 * lower_face
            p.z *= 1.0 + 0.018 * lower_face

    return result

def build(sex, token=False, climbing=False, airborne=False, one_hand=False):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    source,uvs,faces,groups=read_source()
    for name in (f'caucasian-{sex}-young.target',f"universal-{sex}-young-{'maxmuscle' if sex=='male' else 'averagemuscle'}-averageweight.target"):
        for line in (ROOT/name).read_text().splitlines():
            fields=line.split()
            if len(fields)==4 and not fields[0].startswith('#'):
                source[int(fields[0])]+=Vector(tuple(map(float,fields[1:])))
    low=min(source[i].y for i in groups['body'])
    high=max(source[i].y for i in groups['body'])
    scale=145.0/(high-low)
    points=[Vector((v.x*scale,(v.y-low)*scale,v.z*scale)) for v in source]
    if sex == 'male':
        import importlib.util
        spec=importlib.util.spec_from_file_location('greek_physique',ROOT/'greek_physique.py')
        greek=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(greek)
        points=greek.fit(points,groups['body'])
        if not token:
            for i,p in enumerate(points):
                chest=bell(p.y,113,13)
                neck=bell(p.y,126,5)*(1-smoothstep(6,11,abs(p.x)))
                p.x *= 1+.25*chest+.32*neck
                p.z *= 1+.20*chest+.30*neck
                p.y += 2.3*bell(p.y,120,7)
                # Recess the chin without changing lips, nose or the accepted torso.
                p.z -= 5.2*bell(p.y,128.5,2.2)*smoothstep(4,9,p.z)*(1-smoothstep(4,9,abs(p.x)))
                face = smoothstep(4,9,p.z)*(1-smoothstep(7,10,abs(p.x)))
                p.x *= 1-.055*bell(p.y,130,3.0)*face
                p.x *= 1-.06*bell(p.y,135,2.0)*face*(1-smoothstep(2,4,abs(p.x)))
                p.z -= .45*bell(p.y,130.3,1.5)*face
                hips = bell(p.y,72,11)*(1-smoothstep(83,88,p.y))
                p.x *= 1-.045*hips
                p.z *= 1-.08*hips
    if sex == 'female':
        points = sculpt_klothis(points, groups['body'])
    def joint(name):
        ids=groups['joint-'+name]
        return sum((points[i] for i in ids),Vector())/len(ids)
    used=sorted(groups['body'])
    ids={old:new for new,old in enumerate(used)}
    mesh=bpy.data.meshes.new('AnatomicalTopology')
    mesh.from_pydata([blender(points[i]) for i in used],[],[[ids[c[0]] for c in face] for face in faces])
    mesh.update()
    uv_layer=mesh.uv_layers.new(name='MakeHumanUV')
    for polygon,face in zip(mesh.polygons,faces):
        polygon.use_smooth=True
        for loop,corner in zip(polygon.loop_indices,face):
            uv_layer.data[loop].uv=uvs[corner[1]]
    body=bpy.data.objects.new('Anatomy',mesh)
    bpy.context.collection.objects.link(body)
    body.data.materials.append(material('AnatomySurface',(0.025,0.03,0.04) if sex=='male' else (0.52,0.39,0.32),roughness=0.65))
    bpy.ops.object.armature_add()
    rig=bpy.context.object
    rig.name='AuthoringRig'
    bpy.ops.object.mode_set(mode='EDIT')
    rig.data.edit_bones.remove(rig.data.edit_bones[0])
    rest={}
    def bone(name,start,end,parent=None):
        b=rig.data.edit_bones.new(name)
        b.head=blender(start)
        b.tail=blender(end)
        if parent:
            b.parent=rig.data.edit_bones[parent]
        rest[name]=(start.copy(),end.copy())
    pelvis=joint('pelvis')
    neck=joint('neck')
    chest=pelvis.lerp(neck,0.72)
    bone('hips',pelvis-Vector((0,5,0)),pelvis)
    bone('spine',pelvis,chest,'hips')
    bone('chest',chest,neck,'spine')
    bone('head',neck,Vector((0,145,4)),'chest')
    for side in ('l','r'):
        shoulder,elbow,hand=[joint(side+'-'+part) for part in ('shoulder','elbow','hand')]
        bone('clavicle.'+side,chest,shoulder,'chest')
        bone('upperarm.'+side,shoulder,elbow,'clavicle.'+side)
        bone('forearm.'+side,elbow,hand,'upperarm.'+side)
        bone('hand.'+side,hand,hand+(hand-elbow).normalized()*6,'forearm.'+side)
        if sex=='male' and not token:
            for digit in range(1,6):
                for segment in range(1,4):
                    name=f'finger{digit}.{segment}.{side}'
                    parent='hand.'+side if segment==1 else f'finger{digit}.{segment-1}.{side}'
                    bone(name,joint(f'{side}-finger-{digit}-{segment}'),joint(f'{side}-finger-{digit}-{segment+1}'),parent)
        hip,knee,ankle,foot=[joint(side+'-'+part) for part in ('upper-leg','knee','ankle','foot-1')]
        bone('thigh.'+side,hip,knee,'hips')
        bone('shin.'+side,knee,ankle,'thigh.'+side)
        bone('foot.'+side,ankle,foot,'shin.'+side)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    # A single deformation across hand and forearm prevents a pinched wrist seam.
    if sex=='male' and not token:
        for side in ('l','r'):
            hand_group=body.vertex_groups['hand.'+side]
            forearm_group=body.vertex_groups['forearm.'+side]
            weights=[]
            for vertex in body.data.vertices:
                amount=next((g.weight for g in vertex.groups if g.group==hand_group.index),0)
                if amount: weights.append((vertex.index,amount))
            for index,amount in weights:
                forearm_group.add([index],amount,'ADD')
            body.vertex_groups.remove(hand_group)
    # Explicit eye groups avoid automatic weights on tiny disconnected eyeballs.
    eye_objects=[]
    for side in ('l','r'):
        eye=joint(side+'-eye')
        for label,offset,size,color in [('Sclera',0,1.0,(0.34,0.32,0.26)),('Iris',0.80,0.52,(0.25,0.16,0.055)),('Pupil',1.04,0.22,(0.009,0.008,0.007))]:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,location=blender(eye+Vector((0,0,offset))))
            obj=bpy.context.object
            obj.name=label+'.'+side
            obj.scale=(size,size if label=='Sclera' else 0.19,size)
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            obj.data.materials.append(material(label,color,roughness=0.28))
            for p in obj.data.polygons:
                p.use_smooth=True
            group=obj.vertex_groups.new(name='head')
            group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
            modifier=obj.modifiers.new('Pose','ARMATURE')
            modifier.object=rig
            eye_objects.append(obj)
    def pose_segment(name,start,end):
        a,b=rest[name]
        old=(blender(b)-blender(a)).normalized()
        new=(blender(end)-blender(start)).normalized()
        rotation=old.rotation_difference(new)
        basis=rotation.to_matrix() @ rig.data.bones[name].matrix_local.to_3x3()
        matrix=basis.to_4x4()
        matrix.translation=blender(start)
        stretch=(end-start).length/(b-a).length
        matrix=matrix @ Matrix.Diagonal((1,stretch,1,1))
        rig.pose.bones[name].matrix=matrix
        bpy.context.view_layer.update()
    for side,sign in [('l',1),('r',-1)]:
        if sex=='female':
            shoulder=joint(side+'-shoulder')
            if sign>0:
                elbow,wrist=Vector((28.0,115.0,4.0)),Vector((42.0,112.5,7.0))
                hand_end=wrist+Vector((6.0,-1.5,1.0))
            else:
                elbow,wrist=Vector((-28.0,115.5,4.0)),Vector((-42.0,113.0,7.0))
                hand_end=wrist+Vector((-6.0,-1.7,1.2))
        else:
            shoulder=Vector((sign*14,116,0))
        if sex!='female' and sign>0:
            elbow,wrist=Vector((18,97,7)),Vector((20,77,15))
            hand_end=wrist+Vector((0,6,2))
        elif sex!='female':
            elbow,wrist=Vector((-18,96,-7)),Vector((-20,75,-15))
            hand_end=wrist+Vector((-2,-6,3))
        if climbing:
            elbow,wrist=Vector((sign*26,125,23)),Vector((sign*28,140,46))
            if one_hand and sign<0:
                elbow,wrist=Vector((-29,108,18)),Vector((-37,112,40))
        if airborne:
            elbow,wrist=Vector((sign*16,95,0)),Vector((sign*17,75,2))
        if token:
            shoulder=joint(side+'-shoulder')
            elbow,wrist=Vector((sign*19,96,0)),Vector((sign*20,77,3))
        if sex=='male' or token:
            hand_end=wrist+(wrist-elbow).normalized()*6
        pose_segment('clavicle.'+side,chest,shoulder)
        pose_segment('upperarm.'+side,shoulder,elbow)
        pose_segment('forearm.'+side,elbow,wrist)
        pose_segment('hand.'+side,wrist,hand_end)
        if sex=='male' and not token:
            # Curl phalanges in their local frames; the wrist and arm remain unchanged.
            palm_center=(joint(side+'-finger-2-1')+joint(side+'-finger-5-1'))*.5
            palm_axis=(joint(side+'-finger-5-1')-joint(side+'-finger-2-1')).normalized()
            forward=(palm_center-joint(side+'-hand')).normalized()
            inward=forward.cross(palm_axis).normalized()*sign
            if inward.x*sign>0:
                inward=-inward
            for digit in range(1,6):
                for segment,angle in enumerate(([35,45,45] if digit==1 else [68,88,55]),1):
                    name=f'finger{digit}.{segment}.{side}'
                    a,z=rest[name]
                    direction=(z-a).normalized()
                    curl=inward if digit!=1 else (palm_center-a).normalized()
                    axis=blender(direction.cross(curl)).normalized()
                    local_axis=rig.data.bones[name].matrix_local.to_3x3().inverted() @ axis
                    pb=rig.pose.bones[name]
                    pb.rotation_mode='QUATERNION'
                    pb.rotation_quaternion=Quaternion(local_axis,math.radians(angle))
            bpy.context.view_layer.update()
    if sex=='male' and not token:
        for side,sign in [('l',1),('r',-1)]:
            hip=joint(side+'-upper-leg')
            knee=Vector((sign*8,42 if sign>0 else 40,14 if sign>0 else -7))
            ankle=Vector((sign*8,13 if sign>0 else 6,20 if sign>0 else -12))
            foot=ankle+Vector((0,-5,9))
            if climbing:
                knee=Vector((sign*14,58,42)) if sign<0 else Vector((sign*8,40,0))
                ankle=Vector((sign*16,35,62)) if sign<0 else Vector((sign*8,6,0))
                foot=ankle+Vector((0,-5,7))
            if airborne:
                knee=Vector((sign*8,40,0))
                ankle=Vector((sign*8,6,0))
                foot=ankle+Vector((0,-5,9))
            pose_segment('thigh.'+side,hip,knee)
            pose_segment('shin.'+side,knee,ankle)
            pose_segment('foot.'+side,ankle,foot)
    if airborne:
        head=rig.pose.bones['head']
        head.rotation_mode='XYZ'
        head.rotation_euler.x=math.radians(-24)
    if sex=='female':
        leg_targets = {
            'l': (
                Vector((8.7,74.0,1.8)),
                Vector((9.2,40.2,3.5)),
                Vector((8.2,6.2,2.8)),
                Vector((8.0,1.0,12.8))
            ),
            'r': (
                Vector((-8.7,74.0,1.8)),
                Vector((-10.4,41.8,6.2)),
                Vector((-11.0,6.8,5.0)),
                Vector((-11.8,1.2,14.2))
            )
        }
        for side in ('l','r'):
            hip,knee,ankle,foot=leg_targets[side]
            pose_segment('thigh.'+side,hip,knee)
            pose_segment('shin.'+side,knee,ankle)
            pose_segment('foot.'+side,ankle,foot)
        head=rig.pose.bones['head']
        head.rotation_mode='XYZ'
        head.rotation_euler=(math.radians(4.0),math.radians(-3.0),math.radians(2.0))
    bpy.context.view_layer.update()
    for obj in [body]+eye_objects:
        bpy.context.view_layer.objects.active=obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        transform=obj.matrix_world.copy()
        obj.parent=None
        obj.matrix_world=transform
    bpy.data.objects.remove(rig,do_unlink=True)
    # Subdivision refines joints, ears, nostrils and lips without synthetic spheres.
    bpy.context.view_layer.objects.active=body
    sub=body.modifiers.new('AnatomySubdivision','SUBSURF')
    sub.levels=1 if token else 2
    bpy.ops.object.modifier_apply(modifier=sub.name)
    for obj in [body]+eye_objects:
        if sex=='male':
            obj.matrix_world=Matrix.Rotation(math.pi,4,'Z') @ obj.matrix_world
        obj.select_set(True)
    if token:
        return
    name='kaos_anatomy' if sex=='male' else 'klothis_anatomy'
    if climbing:
        name='kaos_climbing'
    if airborne:
        name='kaos_airborne'
    if one_hand:
        name='kaos_one_hand'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=False,export_animations=False,export_yup=True)
    print(name,'vertices',len(body.data.vertices),'faces',len(body.data.polygons))

def main():
    targets=['male','female']
    if '--' in sys.argv:
        args=sys.argv[sys.argv.index('--')+1:]
        if '--sex' in args:
            sex_arg=args[args.index('--sex')+1]
            targets=[sex_arg]
    for target in targets:
        build(target,climbing='--climbing' in sys.argv,airborne='--airborne' in sys.argv,one_hand='--one-hand' in sys.argv)

if __name__ == '__main__':
    main()
