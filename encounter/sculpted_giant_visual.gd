extends RefCounted

var root: Node3D
var units: float
var skin: Material
var cloth: ShaderMaterial
var gold: Material
var hair: StandardMaterial3D
var front: float
var luminous: bool
var anatomy_override: String = ""
var climbing: bool = false

func build(parent: Node3D, scale_units: float, body: Material, _marble: Material, trim: Material, is_luminous: bool) -> void:
	root = parent
	units = scale_units
	skin = body
	gold = trim.duplicate()
	gold.metallic = 0.72
	gold.roughness = 0.38
	luminous = is_luminous
	front = 1.0 if luminous else -1.0
	cloth = ShaderMaterial.new()
	cloth.shader = preload("res://encounter/woven_cloth.gdshader")
	preload("res://encounter/pbr_assets.gd").apply(cloth,"quatrefoil_jacquard_fabric")
	cloth.set_shader_parameter("cloth_color", Color(0.18, 0.23, 0.14) if luminous else Color(0.71, 0.73, 0.69))
	hair = StandardMaterial3D.new()
	hair.albedo_color = Color(0.72, 0.71, 0.65)
	hair.roughness = 0.64
	hair.cull_mode = BaseMaterial3D.CULL_DISABLED
	_import_anatomy()
	preload("res://encounter/hero_costume.gd").new().build(self)
	var face_anchor := Marker3D.new()
	face_anchor.name = "FaceAnchor"
	face_anchor.position = (_sphere_surface(Vector3(0,136,11)) if luminous else Vector3(0,136,-11))*units
	root.add_child(face_anchor)
	if luminous:
		_conform_to_sphere()
		var points := [Vector3(0.0, 139.5, 11.2), Vector3(-42.0, 113.0, 8.0), Vector3(42.0, 112.5, 8.0)]
		var names := ["ForeheadSealAnchor", "LeftWristSealAnchor", "RightWristSealAnchor"]
		for index in range(3):
			var anchor := Marker3D.new()
			anchor.name = names[index]
			anchor.position = _sphere_surface(points[index]) * units
			root.add_child(anchor)
		var light := OmniLight3D.new()
		light.name = "KlothisSoftRadiance"
		light.position = _sphere_surface(Vector3(0.0, 114.0, 38.0)) * units
		light.omni_range = 340 * units
		light.light_color = Color(0.66, 0.82, 1.0)
		light.light_energy = 2.4
		root.add_child(light)

func _import_anatomy() -> void:
	var path := "res://encounter/assets/characters/klothis_anatomy.glb" if luminous else "res://encounter/assets/characters/kaos_anatomy.glb"
	if not anatomy_override.is_empty():
		path = anatomy_override
	var model: Node3D = load(path).instantiate()
	root.add_child(model)
	for source: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var label := String(source.name)
		if not luminous and (label.begins_with("Iris") or label.begins_with("Pupil")):
			continue
		var node := MeshInstance3D.new()
		node.name = source.name
		node.set_meta("visual_role",String(source.name))
		node.mesh = source.mesh
		var relative := root.global_transform.affine_inverse() * source.global_transform
		node.transform = Transform3D(relative.basis.scaled(Vector3.ONE*units),relative.origin*units)
		if label.begins_with("Anatomy") or (not luminous and label.begins_with("Sclera")):
			node.material_override = skin
		root.add_child(node)
	root.remove_child(model)
	model.free()

func _instance(label: String, mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.set_meta("visual_role",label)
	node.mesh = mesh
	node.position = point * units
	node.material_override = material
	root.add_child(node)
	return node

# Shared indexed vertices produce smooth normals instead of disconnected facets.
func _surface(label: String, columns: int, rows: int, sampler: Callable, material: Material, reverse: bool = false) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows + 1):
		for column in range(columns + 1):
			var uv := Vector2(float(column)/columns, float(row)/rows)
			surface.set_uv(uv)
			surface.add_vertex(sampler.call(uv.x, uv.y) * units)
	for row in range(rows):
		for column in range(columns):
			var a := row * (columns + 1) + column
			var indices := [a, a+1, a+columns+2, a, a+columns+2, a+columns+1] if not reverse else [a, a+columns+2, a+1, a, a+columns+1, a+columns+2]
			for index in indices:
				surface.add_index(index)
	surface.generate_normals()
	surface.generate_tangents()
	_instance(label, surface.commit(), Vector3.ZERO, material)

func _torso_point(u: float, v: float) -> Vector3:
	var angle := u * TAU
	var width := 9.4 + 3.0*exp(-pow((v-0.15)/0.2, 2)) - 2.6*exp(-pow((v-0.43)/0.16, 2)) + 4.0*exp(-pow((v-0.76)/0.19, 2))
	width *= 1.0 - 0.65*smoothstep(0.86, 1.0, v)
	var depth := width * (0.58 if luminous else 0.62)
	var chest := 0.6 * maxf(0, cos(angle)) * exp(-pow((v-0.7)/0.2, 2))
	return Vector3(sin(angle)*width, 64+v*61, (cos(angle)*depth+chest)*front)

func _face_point(u: float, v: float) -> Vector3:
	var angle := u * TAU
	var latitude := v * PI
	var y := cos(latitude) * 9.0
	var x := sin(angle) * sin(latitude) * 5.8
	var z := cos(angle) * sin(latitude) * 5.25
	var forward := smoothstep(0.1, 0.8, cos(angle))
	var jaw := 1.0 - 0.23*smoothstep(1.0, 7.0, -y)
	x *= jaw
	var nose := 1.5*exp(-pow(x/0.75, 2)-pow((y+0.15)/2.2, 2))
	var cheeks := 0.32*exp(-pow((absf(x)-2.6)/1.2, 2)-pow((y+0.8)/1.6, 2))
	var sockets := 0.38*exp(-pow((absf(x)-2.1)/1.0, 2)-pow((y-1.2)/0.75, 2))
	var lips := 0.22*exp(-pow(x/1.65, 4)-pow((y+3.1)/0.4, 2))
	z += (nose+cheeks-sockets+lips) * forward
	return Vector3(x, 136+y, z*front)

func _ellipsoid(point: Vector3, size: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 48
	mesh.rings = 24
	_instance("AnatomicalDetail", mesh, point, material).scale = size * units

func _tube(label: String, points: Array, radii: Array, material: Material) -> void:
	var sample := func(u: float, v: float) -> Vector3:
		var f := v * (points.size()-1)
		var index := mini(int(f), points.size()-2)
		var t := f-index
		var a: Vector3 = points[index]
		var b: Vector3 = points[index+1]
		var before: Vector3 = points[maxi(0,index-1)]
		var after: Vector3 = points[mini(points.size()-1,index+2)]
		var center := a.cubic_interpolate(b, before, after, t)
		var axis := (a.cubic_interpolate(b, before, after, minf(1, t+0.001))-a.cubic_interpolate(b, before, after, maxf(0, t-0.001))).normalized()
		var right := axis.cross(Vector3.FORWARD).normalized()
		if right.length_squared() < 0.1:
			right = Vector3.RIGHT
		var other := axis.cross(right).normalized()
		var radius := lerpf(radii[index], radii[index+1], smoothstep(0,1,t))
		return center + (right*cos(u*TAU)+other*sin(u*TAU))*radius
	_surface(label, 32, maxi(16, points.size()*12), sample, material, true)

func _face_details() -> void:
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.5,0.48,0.41) if luminous else Color(0.6,0.55,0.38)
	eye.roughness = 0.3
	var iris := StandardMaterial3D.new()
	iris.albedo_color = Color(0.16,0.12,0.065)
	var lip := StandardMaterial3D.new()
	lip.albedo_color = Color(0.40,0.25,0.19) if luminous else Color(0.1,0.09,0.1)
	for side in [-1.0,1.0]:
		_ellipsoid(Vector3(side*2.1,137.2,front*4.86),Vector3(0.93,0.30,0.16),eye)
		_ellipsoid(Vector3(side*2.1,137.2,front*5.09),Vector3(0.25,0.28,0.07),iris)
		_tube("Brow",[Vector3(side*1.0,138.3,front*4.97),Vector3(side*2.1,138.6,front*4.96),Vector3(side*3.05,138.35,front*4.48)],[0.08,0.13,0.04],iris)
	_tube("Mouth",[Vector3(-1.35,132.8,front*4.86),Vector3(0,132.65,front*5.11),Vector3(1.35,132.8,front*4.86)],[0.05,0.13,0.05],lip)
	for side in [-1.0,1.0]:
		_ellipsoid(Vector3(side*5.4,135.8,0),Vector3(0.65,1.65,0.95),skin)

func _hand(wrist: Vector3) -> void:
	_ellipsoid(wrist+Vector3(0,2.2,0),Vector3(2.3,3.3,1.1),skin)
	for finger in range(4):
		var x := (finger-1.5)*1.07
		var length := 4.6-absf(finger-1.0)*0.6
		var start := wrist+Vector3(x,4.1,0)
		_tube("Finger",[start,start+Vector3(x*0.12,length*0.55,front*0.15),start+Vector3(x*0.22,length,front*0.75)],[0.55,0.44,0.29],skin)
	_tube("Thumb",[wrist+Vector3(-1.9,1,0),wrist+Vector3(-3.5,2.8,front*0.5),wrist+Vector3(-4,4,front)],[0.7,0.55,0.35],skin)

func _gown_point(u: float, v: float) -> Vector3:
	var opening := 0.22 if luminous else 0.65
	var angle := opening + u*(TAU-2*opening)
	var folds := sin(angle*22 + v*0.6)*(0.3+v*0.8) + sin(angle*43-v)*0.16
	var radius := 11.0 + v*9.0 + sin(v*PI)*1.5 + folds
	var y := 76-v*74+sin(angle*7)*v*0.7
	return Vector3(sin(angle)*radius,y,cos(angle)*radius*front)

func _mantle() -> void:
	for side in [-1.0,1.0]:
		var sample := func(u: float,v: float) -> Vector3:
			var width := 2.3+v*3.5
			var x: float = side*(8.5+sin(v*PI)*2.0)+(u-0.5)*width
			var y := 116-v*83+sin(u*PI)*1.4
			var z := front*(7.8+v*9+sin(u*PI*6)*0.38+sin(v*7)*0.65)
			return Vector3(x,y,z)
		_surface("EmbroideredStole",32,72,sample,cloth)
		_ellipsoid(Vector3(side*9,115,front*8),Vector3(2.6,2.6,0.55),gold)
	if luminous:
		var veil := func(u: float,v: float) -> Vector3:
			var angle := 0.3+u*(PI-0.6)
			var x := cos(angle)*(8+v*16)
			var y := 137+sin(angle)*10-v*48
			var z := -front*(1+v*15)+sin(u*30)*0.3
			return Vector3(x,y,z)
		_surface("ScallopedVeil",96,64,veil,cloth)

func _hair() -> void:
	var scalp := func(u: float, v: float) -> Vector3:
		var a := u*TAU
		var latitude := v * (1.04 + (1-cos(a))*0.34)
		return Vector3(sin(a)*sin(latitude)*5.94,136+cos(latitude)*9.15,cos(a)*sin(latitude)*5.4*front)
	_surface("PartedHairCap",96,40,scalp,hair,front<0)
	for lock in range(20):
		var angle := 0.20+float(lock)/19*(TAU-0.4)
		var sample := func(u: float,v: float) -> Vector3:
			var a := angle+(u-0.5)*0.28
			var radius := 5.8+v*12
			var x := sin(a)*radius+sin(v*5+lock)*v*2
			var y := 143-v*(36+lock%5*6)+sin(u*PI)*0.3
			var z := -front*(4+v*15)+cos(a)*2.0
			z += sin(u*PI*10)*0.08
			return Vector3(x,y,z)
		_surface("SculptedHairLock",12,40,sample,hair)

func _ring(point: Vector3, radius: float, thickness: float, rotation: Vector3) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = (radius-thickness)*units
	mesh.outer_radius = (radius+thickness)*units
	mesh.rings = 96
	mesh.ring_segments = 16
	_instance("EngravedGold",mesh,point,gold).rotation = rotation

func _ornaments() -> void:
	if luminous:
		_ring(Vector3(0,76,0),11,0.35,Vector3.ZERO)
		_ring(Vector3(0,123,0),4.1,0.22,Vector3.ZERO)
	if not luminous:
		for segment in range(14):
			if segment in [2, 7, 11]:
				continue
			var a := TAU*segment/14.0
			var b := a + TAU/15.0
			var center := Vector3(0,137,4)
			_tube("BrokenCrown", [center+Vector3(cos(a),sin(a),0)*11.5,center+Vector3(cos((a+b)*0.5),sin((a+b)*0.5),0)*11.5,center+Vector3(cos(b),sin(b),0)*11.5], [0.3,0.3,0.18], gold)
			var radial := Vector3(cos(a),sin(a),0)
			_tube("CrownRay",[center+radial*11.8,center+radial*(14.0+segment%3)],[0.22,0.025],gold)
	for jewel in range(16):
		if not luminous:
			break
		var angle := TAU*jewel/16.0
		_ellipsoid(Vector3(sin(angle)*11,76,cos(angle)*11),Vector3(0.5,0.85,0.35),gold)

func _destiny_regalia() -> void:
	var silver_cloth := cloth.duplicate()
	silver_cloth.set_shader_parameter("cloth_color", Color(0.67,0.70,0.69))
	var blindfold := func(u: float,v: float) -> Vector3:
		var a := (u-0.5)*2.9
		return Vector3(sin(a)*5.95,135.8+v*3.5+sin(u*19)*0.1,cos(a)*5.6)
	_surface("WovenBlindfold",64,16,blindfold,silver_cloth)
	var burgundy := cloth.duplicate()
	burgundy.set_shader_parameter("cloth_color",Color(0.26,0.045,0.075))
	var drape := func(u: float,v: float) -> Vector3:
		var a := -0.7+u*1.7
		var r := 11.8+v*9.6+sin(u*32+v*2)*0.65
		return Vector3(sin(a)*r,88-v*86+sin(u*PI)*10,cos(a)*r)
	_surface("BurgundyDrapery",64,80,drape,burgundy,true)
	for side in [-1.0,1.0]:
		_tube("BranchingHeaddress",[Vector3(side*4,142,0),Vector3(side*8,150,-1),Vector3(side*15,151,-2),Vector3(side*19,146,-1),Vector3(side*23,150,0)],[1.4,1.3,1.0,0.55,0.03],gold)
		_tube("CrownBranch",[Vector3(side*10,151,-1),Vector3(side*11,156,-1),Vector3(side*8,159,0)],[0.8,0.4,0.025],gold)
		_tube("HangingSilverTress",[Vector3(side*18,147,0),Vector3(side*22,131,2),Vector3(side*29,111,4),Vector3(side*25,91,8)],[1.3,1.1,0.7,0.05],hair)
		_ring(Vector3(side*17,147,0),1.6,0.2,Vector3.ZERO)
	_tube("DestinyStaff",[Vector3(37,10,10),Vector3(37,61,10),Vector3(37,118,10)],[0.65,0.65,0.45],gold)
	_tube("StaffSpear",[Vector3(37,118,10),Vector3(37,130,10),Vector3(37,143,10)],[0.4,2.0,0.02],gold)
	_tube("SpindleThread",[Vector3(-31,91,12),Vector3(-31,84,12),Vector3(-31,77,12)],[0.08,0.08,0.08],hair)
	_tube("DestinySpindle",[Vector3(-31,78,12),Vector3(-31,72,12),Vector3(-31,66,12)],[1.6,2.5,1.6],silver_cloth)
	_ring(Vector3(-31,78,12),2.8,0.3,Vector3.ZERO)
	_ring(Vector3(-31,66,12),2.8,0.3,Vector3.ZERO)
	_tube("SpindlePoint",[Vector3(-31,65,12),Vector3(-31,57,12)],[1.6,0.01],gold)

# Map only the replaceable visual onto the sphere; gameplay roots stay untouched.
func _sphere_surface(point: Vector3) -> Vector3:
	# Bend along the surface normal, retaining full depth instead of compressing Z.
	var base := Vector3(point.x,point.y-160,sqrt(maxf(1,220*220-point.x*point.x-pow(point.y-160,2))))
	return Vector3(0,160,-230)+base+base.normalized()*(point.z+9.0)

func _conform_to_sphere() -> void:
	for child in root.get_children():
		if not child is MeshInstance3D or child.mesh == null or child.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in range(vertices.size()):
			vertices[index] = _sphere_surface((child.transform * vertices[index])/units)*units
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var surface := SurfaceTool.new()
		surface.create_from(mesh,0)
		surface.generate_normals()
		surface.generate_tangents()
		var original_material: Material = child.mesh.surface_get_material(0)
		child.mesh = surface.commit()
		child.mesh.surface_set_material(0,original_material)
		child.transform = Transform3D.IDENTITY
