import bpy
from pathlib import Path
from mathutils import Vector

root = Path(__file__).parent
vertices, groups = [], {}
group = ""
for line in (root / "base.obj").read_text().splitlines():
    fields = line.split()
    if not fields:
        continue
    if fields[0] == "v":
        vertices.append(Vector(tuple(map(float, fields[1:4]))))
    elif fields[0] == "g":
        group = fields[1]
        groups.setdefault(group, set())
    elif fields[0] == "f":
        groups[group].update(int(f.split('/')[0])-1 for f in fields[1:])
for sex in ("male", "female"):
    points = [v.copy() for v in vertices]
    for name in (f"caucasian-{sex}-young.target", f"universal-{sex}-young-{'maxmuscle' if sex == 'male' else 'averagemuscle'}-averageweight.target"):
        for line in (root/name).read_text().splitlines():
            f=line.split()
            if len(f)==4 and not line.startswith('#'):
                points[int(f[0])] += Vector(tuple(map(float,f[1:])))
    print(sex, 'bounds',[(min(points[i][axis] for i in groups['body']),max(points[i][axis] for i in groups['body'])) for axis in range(3)])
    for name in ['joint-ground','joint-pelvis','joint-neck','joint-head','joint-mouth','joint-l-eye','joint-l-shoulder','joint-l-elbow','joint-l-hand','joint-l-upper-leg','joint-l-knee','joint-l-ankle','joint-l-foot-1']:
        p=sum((points[i] for i in groups[name]),Vector())/len(groups[name])
        print(name,tuple(round(x,4) for x in p))
