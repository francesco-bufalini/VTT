extends RefCounted

var b
var radii := PackedFloat32Array()
const SLICES := 96

func build(builder) -> void:
	b = builder
	measure_body()
	garments()
	hair_locks()
	b._ornaments()
	if b.luminous:
		b._destiny_regalia()
		for node in b.root.get_children():
			var label := String(node.get_meta("visual_role",node.name))
			if label.begins_with("DestinyStaff") or label.begins_with("StaffSpear"):
				node.free()
				continue
			if label.begins_with("BranchingHeaddress") or label.begins_with("CrownBranch") or label.begins_with("HangingSilverTress"):
				node.position.z += 6*b.units
			if String(node.name).begins_with("WovenBlindfold"):
				b.root.remove_child(node)
				node.free()
		var silver: ShaderMaterial = b.cloth.duplicate()
		silver.set_shader_parameter("cloth_color",Color(.53,.55,.53))
		var band := func(u: float,v: float) -> Vector3:
			return fitted(132.5+v*6.0,u*TAU,.22)
		b._surface("FittedBlindfold",64,12,band,silver)
		for y in [132.5,138.5]:
			var rim := func(u: float,v: float) -> Vector3:
				return fitted(y,u*TAU,lerpf(-.6,.22,v))
			b._surface("BlindfoldHem",96,2,rim,silver)
		for node in b.root.get_children():
			if String(node.name).begins_with("Sclera") or String(node.name).begins_with("Iris") or String(node.name).begins_with("Pupil"):
				node.visible = false
	accessories()
	if not b.luminous:
		lightning()

func lightning() -> void:
	for bolt in range(3):
		var material := ShaderMaterial.new()
		material.shader = preload("res://encounter/kaos_lightning.gdshader")
		material.set_shader_parameter("phase",bolt*.71)
		var sample := func(u: float,v: float) -> Vector3:
			var segment := v*18
			var i := floorf(segment)
			var jag := lerpf(sin(i*12.7+bolt)*2,sin((i+1)*12.7+bolt)*2,fposmod(segment,1.0))
			var a := bolt*TAU/3+v*.8
			return Vector3(sin(a)*(23+jag)+(u-.5)*.24,62+v*58,cos(a)*(20+jag))
		b._surface("SpeedLightning",1,18,sample,material)

# Measure the imported anatomy once; clothing follows its radial sections.
func measure_body() -> void:
	radii.resize(146*SLICES)
	for node in b.root.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Anatomy"):
			continue
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for raw in vertices:
			var p: Vector3 = node.transform*raw/b.units
			p.z *= b.front
			if not b.luminous and p.y>122 and p.y<130 and (absf(p.x)>9 or absf(p.z)>14):
				continue
			if not b.luminous and p.y>=84 and p.y<=97 and (absf(p.x)>14 or absf(p.z)>14):
				continue
			if not b.luminous and p.y>126 and absf(p.x)>10:
				continue
			if not b.luminous and p.y > 65 and p.y < 110 and absf(p.x) > 18:
				continue
			if p.y>110 and absf(p.x)>21 or p.y>85 and absf(p.x)>24:
				continue
			var y := clampi(roundi(p.y),0,145)
			var a := posmod(roundi(atan2(p.x,p.z)/TAU*SLICES),SLICES)
			var index := y*SLICES+a
			radii[index] = maxf(radii[index],Vector2(p.x,p.z).length())
	var filled := radii.duplicate()
	for y in range(1,145):
		for a in range(SLICES):
			var r := 0.0
			for dy in range(-1,2):
				for da in range(-2,3):
					r = maxf(r,radii[(y+dy)*SLICES+posmod(a+da,SLICES)])
			filled[y*SLICES+a] = r
	radii = filled
	for pass_index in range(3):
		var smooth := radii.duplicate()
		for y in range(1,145):
			for a in range(SLICES):
				var i := y*SLICES+a
				smooth[i] = (radii[i]*4+radii[i-SLICES]+radii[i+SLICES]+radii[y*SLICES+posmod(a-1,SLICES)]+radii[y*SLICES+posmod(a+1,SLICES)])/8
		radii = smooth

func radius_at(y: float,a: float) -> float:
	if not b.luminous and y > 96 and y <= 117:
		# Smooth torso-only envelope: lowered hands must not deform the belt or sash.
		var width := 12.5 + 6.5*smoothstep(94,110,y)
		var depth := 10.0 + 3.5*smoothstep(94,110,y)
		return 1.0/sqrt(pow(sin(a)/width,2)+pow(cos(a)/depth,2))+2.0*cos(a)
	var fy := clampf(y,1,144)
	var iy := floori(fy)
	var fa := fposmod(a/TAU*SLICES,SLICES)
	var ia := floori(fa)
	var next := (ia+1)%SLICES
	return lerpf(lerpf(radii[iy*SLICES+ia],radii[iy*SLICES+next],fa-ia),lerpf(radii[(iy+1)*SLICES+ia],radii[(iy+1)*SLICES+next],fa-ia),fy-iy)

func fitted(y: float,a: float,padding: float=0.8) -> Vector3:
	var r := radius_at(y,a)+padding
	return Vector3(sin(a)*r,y,cos(a)*r*b.front)

func garments() -> void:
	if not b.luminous:
		kaos_veil()
		return
	if b.luminous:
		var bodice := func(u: float,v: float) -> Vector3:
			var a := u*TAU
			var y := 77+v*(36-2*cos(a))
			return fitted(y,a,1.0+sin(u*PI*24+v*4)*.22)
		b._surface("AnatomyFittedBodice",96,72,bodice,b.cloth)
	for side in [-1.0,1.0]:
		if not b.luminous and side<0:
			continue
		var sash := func(u: float,v: float) -> Vector3:
			var a: float = side*(.63-v*1.2)+(u-.5)*.62
			return fitted(116-v*(38 if b.luminous else 26),a,1.55+sin(u*PI*10)*.2)
		b._surface("BodyFollowingSash",28,72,sash,b.cloth)
	var burgundy: ShaderMaterial = b.cloth.duplicate()
	burgundy.set_shader_parameter("cloth_color",Color(.19,.035,.058))
	for panel in range(10):
		if not b.luminous and panel in [0,1,9]:
			continue
		var a0 := float(panel)/10.0*TAU
		var skirt := func(u: float,v: float) -> Vector3:
			var a := a0+(u-.5)*.82
			var waist := 77.0 if b.luminous else 90.0
			var hip := radius_at(waist,a)+1.2
			var r := lerpf(hip,25.0,v)+sin(u*PI*8+v*2)*(.3+v*.9)
			var wind := v*v*(2.0 if b.luminous else 11.0)
			return Vector3(sin(a)*r+wind,waist+1-v*(waist-5-panel%3*3),b.front*cos(a)*r)
		b._surface("TailoredSkirtPanel",32,64,skirt,burgundy if b.luminous and panel%3==0 else b.cloth)
	var loin := func(u: float,v: float) -> Vector3:
		var a := (u-.5)*.7
		var waist := 77.0 if b.luminous else 90.0
		var r := lerpf(radius_at(waist,a)+2,21,v)+sin(u*PI*8)*.4
		return Vector3(sin(a)*r,waist+1-v*(43 if b.luminous else 41),b.front*cos(a)*r)
	b._surface("CentralEmbroideredDrape",32,48,loin,burgundy if b.luminous else b.cloth)
	if not b.luminous:
		var cape := func(u: float,v: float) -> Vector3:
			return Vector3((u-.5)*(22+v*36)+v*v*19,116-v*76,b.front*(-9-v*24+sin(u*PI*9+v*3)*(1+v*2)))
		b._surface("ShoulderAnchoredMantle",64,64,cape,b.cloth)

func kaos_veil() -> void:
	# Waist-supported cloth; the braced knee exits through the right-hand slit.
	var veil := func(u: float,v: float) -> Vector3:
		var a := lerpf(-1.85,.45 if b.climbing else 1.8,u)
		var y := 91.0-v*57.0
		var lower := clampf((90-y)/56,0,1)
		var r := skirt_radius(y,a)
		r += sin(u*PI*22)*lower*.7
		return Vector3(sin(a)*r+lower*lower*3,y+sin(u*PI)*lower*2,b.front*cos(a)*r)
	b._surface("TailoredSkirtPanel",96,112,veil,b.cloth)
	var back := func(u: float,v: float) -> Vector3:
		var a := PI+(u-.5)*3.0
		var y := 91-v*59
		var lower := clampf((90-y)/58,0,1)
		var r := skirt_radius(y,a)
		r += sin(u*PI*18)*lower*.7
		return Vector3(sin(a)*r+lower*lower*6,y,b.front*cos(a)*r)
	b._surface("ShoulderAnchoredMantle",80,100,back,b.cloth)

func skirt_radius(y: float,a: float) -> float:
	var waist := radius_at(clampf(y,88,94),a)+.35
	return lerpf(waist,18.0,clampf((90-y)/58,0,1))

func keep_outside_head(center: Vector3, clearance: float) -> Vector3:
	if b.luminous or center.y<118 or center.y>147:
		return center
	var a := atan2(center.x,center.z)
	var shell := minf(radius_at(clampf(center.y,128,144),a),13.5)+clearance
	var influence := smoothstep(118,130,center.y)*(1.0-smoothstep(142,147,center.y))
	var radial := Vector2(center.x,center.z)
	if radial.length()<shell:
		radial = radial.lerp(radial.normalized()*shell,influence)
		center.x = radial.x
		center.z = radial.y
	return center

func hair_locks() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://encounter/silver_hair.gdshader")
	scalp_from_anatomy(material)
	# Closed tapered locks avoid the rectangular ends of the previous hair cards.
	for lock in range(88):
		var a := .35+float(lock)/87.0*(TAU-.7)
		var latitude := .30+float(lock%4)*.27
		var start := Vector3(sin(a)*sin(latitude)*7.9,135.8+cos(latitude)*9.5,6+cos(a)*sin(latitude)*8.3)
		var sample := func(u: float,v: float) -> Vector3:
			var angle := u*TAU
			var sweep := smoothstep(0,.35,v)
			var center := start+Vector3(sin(a)*(3*sweep+v*7)+v*v*(4 if b.luminous else 19),-v*(42+lock%7*4),-v*19)
			center.x += sin(v*9+lock*.7)*v*1.4
			center = keep_outside_head(center,.35)
			var width := ((.55+lock%3*.15)*pow(1-v,.65)+.015)*smoothstep(0,.08,v)
			return Vector3(center.x+cos(angle)*width,center.y,b.front*(center.z+sin(angle)*width*.42))
		b._surface("RootedSilverLock",8,44,sample,material)
	for side in [-1.0,1.0]:
		for lock in range(9):
			var sample := func(u: float,v: float) -> Vector3:
				var t := smoothstep(0,.3,v)
				var center := Vector3(side*(.5+lock*.18+t*6+v*7),145-v*(43+lock*2),7+t*7-v*6)
				if not b.luminous:
					center = Vector3(side*(5.6+lock*.13+v*5),142-v*(41+lock*2),8.5-v*9)
					center = keep_outside_head(center,.3)
				var width := (.48*pow(1-v,.6)+.015)*smoothstep(0,.07,v)
				return Vector3(center.x+cos(u*TAU)*width,center.y,b.front*(center.z+sin(u*TAU)*width*.5))
			b._surface("PartedTempleLock",8,40,sample,material)

func scalp_from_anatomy(material: Material) -> void:
	for node in b.root.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Anatomy"):
			continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in range(vertices.size()):
				indices[index] = index
		var transformed := PackedVector3Array()
		var include := PackedByteArray()
		for raw in vertices:
			var p: Vector3 = node.transform*raw/b.units
			p.z *= b.front
			include.append(int(absf(p.x)<10 and (p.y>140 or (p.y>130 and (p.z<5 or absf(p.x)>6.6)))))
			p += (p-Vector3(0,136,6)).normalized()*.23
			p.z *= b.front
			transformed.append(p)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0,indices.size(),3):
			if not (include[indices[i]] and include[indices[i+1]] and include[indices[i+2]]):
				continue
			for j in range(3):
				var p := transformed[indices[i+j]]
				st.set_uv(Vector2(atan2(p.x,p.z*b.front-6)/TAU,(145-p.y)/20))
				st.add_vertex(p*b.units)
		st.generate_normals()
		b._instance("AnatomicalHairline",st.commit(),Vector3.ZERO,material)

func accessories() -> void:
	for side in [-1.0,1.0]:
		var center := fitted(114 if b.luminous else 91,side*.6,2.0 if b.luminous else .5)
		for ring in range(3):
			b._ring(center,2.4-ring*.6,.16,Vector3(PI/2,0,0))
		b._ellipsoid(center+Vector3(0,0,b.front*.3),Vector3(.6,.85,.3),b.gold)
		for band in range(3):
			if b.luminous:
				b._ring(Vector3(side*(41+band*.6),112.8,7),2.1,.16,Vector3(0,0,PI/2))
			else:
				var wrist := Vector3(-20,79,-15) if side<0 else Vector3(20,77,15)
				var elbow := Vector3(-18,97,-7) if side<0 else Vector3(18,96,7)
				if b.climbing:
					wrist = Vector3(side*28,140,-46)
					elbow = Vector3(side*26,125,-23)
				var axis := (wrist-elbow).normalized()
				var fit := cuff_section(wrist-axis*(1.8-band*.55),axis)
				var rotation := Basis(Quaternion(Vector3.UP,axis)).get_euler()
				b._ring(Vector3(fit.x,fit.y,fit.z),fit.w+.12,.16,rotation)
	var belt := func(u: float,v: float) -> Vector3:
		return fitted(76+v*2.2 if b.luminous else 88+v*6,u*TAU,1.2 if b.luminous else .25)
	b._surface("FittedMetalGirdle",96,8,belt,b.gold)
	if not b.luminous:
		var collar := func(u: float,v: float) -> Vector3:
			return collar_point(124.0+v*4.5,u*TAU,.3)
		b._surface("FittedGoldCollar",96,20,collar,b.gold)
		for height in [124.0,128.5]:
			var rim := func(u: float,v: float) -> Vector3:
				return collar_point(height+(v-.5)*.35,u*TAU,.46)
			b._surface("GoldCollarRim",96,2,rim,b.gold)
	if b.luminous:
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(.27,.035,.065)
		for strand in range(5):
			var points: Array = []
			var widths: Array = []
			for i in range(13):
				var t := i/12.0
				points.append(Vector3(42-t*30+sin(t*7+strand)*3,112.5-t*80,9+t*8))
				widths.append(.09)
			b._tube("WristBoundFateThread",points,widths,red)

func collar_point(y: float,a: float,padding: float) -> Vector3:
	var r := minf(radius_at(y,a),12.0) + padding+.3
	return Vector3(sin(a)*r,y,cos(a)*r*b.front)

func cuff_section(origin: Vector3,axis: Vector3) -> Vector4:
	var points := PackedVector3Array()
	var center := Vector3.ZERO
	for node in b.root.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Anatomy"):
			continue
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for raw in vertices:
			var p: Vector3 = node.transform*raw/b.units
			if absf((p-origin).dot(axis))<.45 and p.distance_to(origin)<8:
				points.append(p)
				center += p
	if points.is_empty():
		return Vector4(origin.x,origin.y,origin.z,2)
	center /= points.size()
	var radius := 0.0
	for p in points:
		var d := p-center
		radius = maxf(radius,(d-axis*d.dot(axis)).length())
	return Vector4(center.x,center.y,center.z,radius)
