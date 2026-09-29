"""Fit the existing animation topology to the uploaded statue's exposed torso.

The source includes a pedestal, robe and raised arm, not a riggable nude body.
Sample its unclothed half and mirror it, retaining the original joints and UVs.
"""
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import math

def fit(points, body_ids):
    path=Path(__file__).parent.parent/'characters/source/uploaded/21521_Greek_God_v1_NEW.obj'
    vertices=[];faces=[]
    for line in path.read_text().splitlines():
        fields=line.split()
        if not fields:continue
        if fields[0]=='v':vertices.append(Vector(tuple(map(float,fields[1:4]))))
        elif fields[0]=='f':faces.append([int(f.split('/')[0])-1 for f in fields[1:]])
    tree=BVHTree.FromPolygons(vertices,faces)
    def smooth(a,b,x):
        t=max(0,min(1,(x-a)/(b-a)))
        return t*t*(3-2*t)
    count=0
    original=[p.copy() for p in points]
    for index in body_ids:
        p=points[index]
        weight=smooth(77,86,p.y)*(1-smooth(114,124,p.y))*(1-smooth(11,17,abs(p.x)))
        if weight<=0:continue
        # Blender source Z is height, negative Y is the front of the statue.
        height=5.85+(p.y-77)/41*3.05
        direction=Vector((abs(p.x),-p.z,0)).normalized()
        hit,normal,face,distance=tree.ray_cast(Vector((0,0,height))+direction*4,-direction,4)
        if hit is None or abs(hit.x)>1.65:continue
        target=Vector((math.copysign(hit.x*10.2,p.x),p.y,-hit.y*10.2))
        # Keep a bounded adjustment at seams; the source topology never reaches the rig.
        delta=target-p
        if delta.length>2.5:delta=delta.normalized()*2.5
        points[index]=p+delta*weight*.8
        count+=1
    # Smooth transferred displacement without smoothing the original anatomy.
    neighbors={i:set() for i in body_ids}
    group=''
    for line in (Path(__file__).parent/'base.obj').read_text().splitlines():
        fields=line.split()
        if not fields:continue
        if fields[0]=='g':group=fields[1]
        if fields[0]=='f' and group=='body':
            ids=[int(f.split('/')[0])-1 for f in fields[1:]]
            for a,b in zip(ids,ids[1:]+ids[:1]):neighbors[a].add(b);neighbors[b].add(a)
    delta={i:points[i]-original[i] for i in body_ids}
    for iteration in range(16):
        delta={i:delta[i]*.35+sum((delta[j] for j in ns),Vector())*(.65/len(ns)) if ns else delta[i] for i,ns in neighbors.items()}
    for i in body_ids:points[i]=original[i]+delta[i]
    print('Greek God reference fit:',count,'torso vertices')
    return points
