extends Node3D

@export var default_cell_size: float = 1.0
@export var default_length_cells: float = 12.0
@export var radial_segments: int = 28

var _cell_size: float = 1.0
var _length_cells: float = 12.0
var _eye_height: float = 0.76
var _ground_y: float = -0.94

var _volume: MeshInstance3D
var _ground_projection: MeshInstance3D
var _outline: MeshInstance3D


func _ready() -> void:
	_cell_size = default_cell_size
	_length_cells = default_length_cells
	_create_mesh_nodes()
	_rebuild()


func configure(
	new_cell_size: float,
	new_length_cells: float,
	new_eye_height: float,
	new_ground_y: float
) -> void:
	_cell_size = maxf(new_cell_size, 0.001)
	_length_cells = maxf(new_length_cells, 0.0)
	_eye_height = new_eye_height
	_ground_y = new_ground_y

	if is_inside_tree():
		if _volume == null:
			_create_mesh_nodes()
		_rebuild()


func _create_mesh_nodes() -> void:
	if _volume != null:
		return

	_volume = MeshInstance3D.new()
	_volume.name = "ConeVolume"
	add_child(_volume)

	_ground_projection = MeshInstance3D.new()
	_ground_projection.name = "GroundProjection"
	add_child(_ground_projection)

	_outline = MeshInstance3D.new()
	_outline.name = "ConeOutline"
	add_child(_outline)


func _rebuild() -> void:
	var length: float = _length_cells * _cell_size
	if length <= 0.001:
		visible = false
		return

	# Regola del cono D&D 5e: la larghezza alla distanza d è d.
	# Quindi al termine del cono il diametro è length e il raggio length / 2.
	var radius: float = length * 0.5
	var apex: Vector3 = Vector3(0.0, _eye_height, 0.0)
	var base_center: Vector3 = Vector3(0.0, _eye_height, -length)

	var volume_material: StandardMaterial3D = StandardMaterial3D.new()
	volume_material.albedo_color = Color(0.18, 0.72, 1.0, 0.075)
	volume_material.emission_enabled = true
	volume_material.emission = Color(0.02, 0.22, 0.5, 1.0)
	volume_material.emission_energy_multiplier = 0.35
	volume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	volume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	volume_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var volume_mesh: ImmediateMesh = ImmediateMesh.new()
	volume_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, volume_material)

	var safe_segments: int = maxi(radial_segments, 8)
	for i: int in range(safe_segments):
		var angle_a: float = TAU * float(i) / float(safe_segments)
		var angle_b: float = TAU * float(i + 1) / float(safe_segments)

		var point_a: Vector3 = Vector3(
			cos(angle_a) * radius,
			_eye_height + sin(angle_a) * radius,
			-length
		)
		var point_b: Vector3 = Vector3(
			cos(angle_b) * radius,
			_eye_height + sin(angle_b) * radius,
			-length
		)

		volume_mesh.surface_add_vertex(apex)
		volume_mesh.surface_add_vertex(point_a)
		volume_mesh.surface_add_vertex(point_b)

		volume_mesh.surface_add_vertex(base_center)
		volume_mesh.surface_add_vertex(point_b)
		volume_mesh.surface_add_vertex(point_a)

	volume_mesh.surface_end()
	_volume.mesh = volume_mesh

	var projection_material: StandardMaterial3D = StandardMaterial3D.new()
	projection_material.albedo_color = Color(0.05, 0.75, 1.0, 0.16)
	projection_material.emission_enabled = true
	projection_material.emission = Color(0.0, 0.28, 0.72, 1.0)
	projection_material.emission_energy_multiplier = 0.6
	projection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	projection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projection_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var projection_mesh: ImmediateMesh = ImmediateMesh.new()
	projection_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, projection_material)
	projection_mesh.surface_add_vertex(Vector3(0.0, _ground_y, -0.03))
	projection_mesh.surface_add_vertex(Vector3(-radius, _ground_y, -length))
	projection_mesh.surface_add_vertex(Vector3(radius, _ground_y, -length))
	projection_mesh.surface_end()
	_ground_projection.mesh = projection_mesh

	var outline_material: StandardMaterial3D = StandardMaterial3D.new()
	outline_material.albedo_color = Color(0.3, 0.88, 1.0, 0.75)
	outline_material.emission_enabled = true
	outline_material.emission = Color(0.04, 0.45, 0.9, 1.0)
	outline_material.emission_energy_multiplier = 1.0
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var outline_mesh: ImmediateMesh = ImmediateMesh.new()
	outline_mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	outline_mesh.surface_add_vertex(Vector3(0.0, _ground_y + 0.012, 0.0))
	outline_mesh.surface_add_vertex(
		Vector3(-radius, _ground_y + 0.012, -length)
	)
	outline_mesh.surface_add_vertex(Vector3(0.0, _ground_y + 0.012, 0.0))
	outline_mesh.surface_add_vertex(
		Vector3(radius, _ground_y + 0.012, -length)
	)
	outline_mesh.surface_add_vertex(
		Vector3(-radius, _ground_y + 0.012, -length)
	)
	outline_mesh.surface_add_vertex(
		Vector3(radius, _ground_y + 0.012, -length)
	)
	outline_mesh.surface_end()
	_outline.mesh = outline_mesh
