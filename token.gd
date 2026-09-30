extends CharacterBody3D

const TOKEN_LIBRARY_MANIFEST := "res://assets/tokens/token_library.json"
const IMPORTED_VISUAL_NAME := "ImportedVisual"
const TOKEN_OVERLAY_NAME := "TokenOverlay"

# Condizioni standard D&D 5e / SRD. Gli ID rimangono in inglese per essere
# stabili nei salvataggi; etichette e pittogrammi sono solo presentazione.
const CONDITION_DEFINITIONS := [
	# Le 15 condizioni ufficiali D&D 5e / SRD.
	{"id": "blinded", "name": "Accecato", "icon": "[BL]", "official": true},
	{"id": "charmed", "name": "Affascinato", "icon": "[CH]", "official": true},
	{"id": "deafened", "name": "Assordato", "icon": "[DE]", "official": true},
	{"id": "exhaustion", "name": "Sfinimento", "icon": "[EX]", "official": true},
	{"id": "frightened", "name": "Spaventato", "icon": "[FR]", "official": true},
	{"id": "grappled", "name": "Afferrato", "icon": "[GR]", "official": true},
	{"id": "incapacitated", "name": "Incapacitato", "icon": "[IN]", "official": true},
	{"id": "invisible", "name": "Invisibile", "icon": "[IV]", "official": true},
	{"id": "paralyzed", "name": "Paralizzato", "icon": "[PA]", "official": true},
	{"id": "petrified", "name": "Pietrificato", "icon": "[PE]", "official": true},
	{"id": "poisoned", "name": "Avvelenato", "icon": "[PO]", "official": true},
	{"id": "prone", "name": "Prono", "icon": "[PR]", "official": true},
	{"id": "restrained", "name": "Trattenuto", "icon": "[RE]", "official": true},
	{"id": "stunned", "name": "Stordito", "icon": "[ST]", "official": true},
	{"id": "unconscious", "name": "Privo di sensi", "icon": "[UN]", "official": true},

	# Marker tattici utili nel VTT. Non sono condizioni ufficiali SRD.
	{"id": "concentrating", "name": "Concentrazione", "icon": "[CO]", "official": false},
	{"id": "surprised", "name": "Sorpreso", "icon": "[SU]", "official": false},
	{"id": "hidden", "name": "Nascosto", "icon": "[HI]", "official": false},
	{"id": "dead", "name": "Morto", "icon": "[KO]", "official": false},
]

@export var cell_size: float = 1.0
@export var gravity_multiplier: float = 1.0
@export var terminal_velocity: float = 40.0
@export var token_height_cells: float = 2.0
@export var flying: bool = true
@export var visual_asset_path: String = ""
@export_range(0, 3, 1) var visual_front_quarter_turns: int = 0
@export var token_display_name: String = ""
@export var default_size_name: String = "Medium"
@export var default_footprint_cells: float = 1.0

# D&D definisce la forma del cono, ma non una portata visiva universale.
# 12 celle = 60 ft è quindi solo un default configurabile.
@export var vision_cone_length_cells: float = 12.0

@onready var visuals: Node3D = $Visuals
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var selection_marker: MeshInstance3D = $SelectionMarker
@onready var facing_marker: Node3D = $FacingMarker
@onready var vision_cone: Node3D = $VisionCone

var _selected: bool = false
var _gravity: float = 9.8
var _footprint_cells: float = 1.0
var _size_name: String = "Medium"
var _loaded_visual_asset_path: String = ""
var _imported_visual_base_basis: Basis = Basis.IDENTITY
var _uses_manifest_default: bool = false
var _conditions: Array[String] = []
var _overlay_root: Node3D
var _name_label: Label3D
var _status_label: Label3D
var movement_validator: Callable
var grid_support: Node3D
var _support_transform: Transform3D


func _ready() -> void:
	add_to_group("dnd_token")
	platform_floor_layers = 1
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_gravity = float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	_size_name = default_size_name
	_footprint_cells = maxf(default_footprint_cells, 0.5)
	_load_configured_visual()
	_ensure_token_overlay()
	set_token_size(_footprint_cells)
	# I token partono sempre sospesi. La gravità viene attivata solo
	# esplicitamente dal comando "Applica gravità".
	set_flying(true)
	set_display_name(token_display_name)
	set_conditions(_conditions)
	set_selected(false)
	set_vision_cone_visible(false)


func _physics_process(delta: float) -> void:
	# L'aggancio a carro/piattaforma non dipende dalla gravita: un token
	# sospeso ma appoggiato al carro continua a seguirne il transform.
	if is_instance_valid(grid_support):
		global_position = (
			grid_support.global_transform
			* (_support_transform.affine_inverse() * global_position)
		)
		_support_transform = grid_support.global_transform
		if grid_support.has_meta("passenger_deck_extent"):
			var local := grid_support.to_local(global_position)
			var extent: Vector2 = grid_support.get_meta("passenger_deck_extent")
			var half_height := token_height_cells * cell_size * 0.5
			if (
				absf(local.x) < extent.x * 0.5
				and absf(local.z) < extent.y * 0.5
				and absf(local.y - half_height) < cell_size * 0.12
			):
				local.y = half_height + 0.01 * cell_size
				global_position = grid_support.to_global(local)
				velocity = Vector3.ZERO
				return
			grid_support = null

	if flying:
		_snap_horizontal_to_grid()
		velocity = Vector3.ZERO
		return

	if is_on_floor():
		velocity.y = -0.05
	else:
		velocity.y = maxf(
			velocity.y - (_gravity * gravity_multiplier * delta),
			-terminal_velocity
		)

	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	if is_on_floor():
		grid_support = null
		for index in range(get_slide_collision_count()):
			var hit := get_slide_collision(index)
			var body := hit.get_collider() as Node3D
			if (
				body != null
				and body.is_in_group("tactical_platform")
				and hit.get_normal().dot(Vector3.UP) > 0.7
			):
				grid_support = body
				_support_transform = body.global_transform
				break

		# "Applica gravita" vale solo per questa caduta. Appena il token
		# atterra torna sospeso, mantenendo l'eventuale supporto del carro.
		_snap_horizontal_to_grid()
		_finish_gravity_after_landing()


func set_flying(enabled: bool) -> void:
	flying = enabled
	velocity = Vector3.ZERO
	grid_support = null
	platform_floor_layers = 0 if enabled else 1
	if is_instance_valid(selection_marker):
		var material: StandardMaterial3D = selection_marker.mesh.material.duplicate()
		if enabled:
			material.albedo_color = Color(0.3, 0.85, 1)
			material.emission = Color(0.1, 0.5, 0.8)
		selection_marker.material_override = material


func apply_gravity() -> void:
	# X/Z sono fissate prima della caduta: la gravita modifica solo Y.
	_snap_horizontal_to_grid()
	set_flying(false)


func _finish_gravity_after_landing() -> void:
	flying = true
	velocity = Vector3.ZERO
	platform_floor_layers = 0


func is_motion_in_progress() -> bool:
	return not flying


func nudge_vertical(steps: int) -> void:
	move_and_collide(Vector3.UP * steps * cell_size)
	velocity.y = 0
	grid_support = null


func configure(
	token_color: Color,
	new_cell_size: float = 1.0,
	size_name: String = "Medium",
	footprint_cells: float = 1.0
) -> void:
	cell_size = maxf(new_cell_size, 0.001)

	var resolved_size_name := size_name
	var resolved_footprint := maxf(footprint_cells, 0.5)
	if _uses_manifest_default:
		var default_profile := _default_token_profile()
		if not default_profile.is_empty():
			resolved_size_name = String(
				default_profile.get("size_name", resolved_size_name)
			)
			resolved_footprint = maxf(
				float(default_profile.get("footprint", resolved_footprint)),
				0.5
			)
			token_height_cells = maxf(
				float(
					default_profile.get(
						"height_cells",
						token_height_cells
					)
				),
				0.1
			)

	_size_name = resolved_size_name
	_footprint_cells = resolved_footprint

	set_token_size(_footprint_cells)
	set_token_color(token_color)
	_snap_horizontal_to_grid()


func set_visual_asset(path: String) -> bool:
	var requested_path: String = path.strip_edges()
	if not requested_path.is_empty():
		_uses_manifest_default = false
	if requested_path.is_empty():
		requested_path = _default_visual_asset_path()
	if requested_path.is_empty():
		return false

	if (
		requested_path == _loaded_visual_asset_path
		and _get_imported_visual() != null
	):
		visual_asset_path = requested_path
		_apply_imported_visual_front()
		_position_imported_visual()
		return true

	var resource: Resource = ResourceLoader.load(requested_path)
	if resource == null:
		push_warning(
			"Token: impossibile caricare la miniatura %s" % requested_path
		)
		return false

	var imported: Node3D = null
	if resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = resource as Mesh
		imported = mesh_instance
	elif resource is PackedScene:
		var scene_instance: Node = (resource as PackedScene).instantiate()
		if scene_instance is Node3D:
			imported = scene_instance as Node3D
		else:
			scene_instance.queue_free()

	if imported == null:
		push_warning(
			"Token: formato visuale non supportato per %s" % requested_path
		)
		return false

	_clear_imported_visual()
	_set_procedural_visuals_visible(false)
	imported.name = IMPORTED_VISUAL_NAME
	imported.set_meta("token_imported_visual", true)
	_imported_visual_base_basis = imported.transform.basis
	visuals.add_child(imported)

	visual_asset_path = requested_path
	_loaded_visual_asset_path = requested_path
	_apply_imported_visual_front()
	_position_imported_visual()
	return true


func get_visual_asset_path() -> String:
	return _loaded_visual_asset_path


func set_visual_front_quarter_turns(value: int) -> void:
	visual_front_quarter_turns = ((value % 4) + 4) % 4
	_apply_imported_visual_front()
	_position_imported_visual()


func get_visual_front_quarter_turns() -> int:
	return visual_front_quarter_turns


func _apply_imported_visual_front() -> void:
	var imported := _get_imported_visual()
	if imported == null:
		return
	var angle := deg_to_rad(
		90.0 * float(visual_front_quarter_turns)
	)
	imported.transform.basis = (
		Basis(Vector3.UP, angle) * _imported_visual_base_basis
	)


func _load_configured_visual() -> void:
	var requested_path: String = visual_asset_path.strip_edges()
	var profile: Dictionary = {}

	if requested_path.is_empty():
		profile = _default_token_profile()
		requested_path = String(profile.get("obj", "")).strip_edges()
		_uses_manifest_default = not requested_path.is_empty()
	else:
		profile = _profile_for_visual(requested_path)

	if not profile.is_empty():
		_size_name = String(profile.get("size_name", _size_name))
		_footprint_cells = maxf(
			float(profile.get("footprint", _footprint_cells)),
			0.5
		)
		token_height_cells = maxf(
			float(profile.get("height_cells", token_height_cells)),
			0.1
		)

	if not requested_path.is_empty():
		var should_remain_default := _uses_manifest_default
		set_visual_asset(requested_path)
		_uses_manifest_default = should_remain_default


func _read_token_manifest() -> Dictionary:
	if not FileAccess.file_exists(TOKEN_LIBRARY_MANIFEST):
		return {}
	var file := FileAccess.open(TOKEN_LIBRARY_MANIFEST, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _default_token_profile() -> Dictionary:
	var manifest := _read_token_manifest()
	if manifest.is_empty():
		return {}

	var default_value: Variant = manifest.get("default", {})
	if default_value is Dictionary:
		return (default_value as Dictionary).duplicate(true)

	var default_path := String(default_value).strip_edges()
	if not default_path.is_empty():
		return _profile_for_visual(default_path)

	var default_id := String(manifest.get("default_id", "")).strip_edges()
	var tokens: Variant = manifest.get("tokens", [])
	if tokens is Array:
		for value: Variant in tokens:
			if value is Dictionary:
				var profile := value as Dictionary
				if String(profile.get("id", "")) == default_id:
					return profile.duplicate(true)
	return {}


func _profile_for_visual(path: String) -> Dictionary:
	var requested := path.strip_edges()
	if requested.is_empty():
		return {}
	var tokens: Variant = _read_token_manifest().get("tokens", [])
	if not tokens is Array:
		return {}
	for value: Variant in tokens:
		if value is Dictionary:
			var profile := value as Dictionary
			if String(profile.get("obj", "")).strip_edges() == requested:
				return profile.duplicate(true)
	return {}


func _default_visual_asset_path() -> String:
	return String(_default_token_profile().get("obj", "")).strip_edges()


func _get_imported_visual() -> Node3D:
	return visuals.get_node_or_null(IMPORTED_VISUAL_NAME) as Node3D


func _clear_imported_visual() -> void:
	var current := _get_imported_visual()
	if current == null:
		return
	visuals.remove_child(current)
	current.queue_free()
	_loaded_visual_asset_path = ""
	_imported_visual_base_basis = Basis.IDENTITY


func _set_procedural_visuals_visible(value: bool) -> void:
	for child_node: Node in visuals.get_children():
		if child_node.has_meta("token_imported_visual"):
			continue
		if child_node is VisualInstance3D:
			(child_node as VisualInstance3D).visible = value


func _accumulate_imported_y_bounds(
	node: Node3D,
	transform_to_visuals: Transform3D,
	bounds: Vector2
) -> Vector2:
	var result := bounds

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var aabb: AABB = mesh_instance.get_aabb()
			for endpoint_index: int in range(8):
				var point: Vector3 = (
					transform_to_visuals * aabb.get_endpoint(endpoint_index)
				)
				result.x = minf(result.x, point.y)
				result.y = maxf(result.y, point.y)

	for child_node: Node in node.get_children():
		if child_node is Node3D:
			var child := child_node as Node3D
			result = _accumulate_imported_y_bounds(
				child,
				transform_to_visuals * child.transform,
				result
			)

	return result


func _imported_visual_y_bounds() -> Vector2:
	var imported := _get_imported_visual()
	if imported == null:
		return Vector2(INF, -INF)

	# Ignore the root translation because this function is used to determine it,
	# but preserve any source rotation/scale on the imported root.
	var root_transform := Transform3D(
		imported.transform.basis,
		Vector3.ZERO
	)
	return _accumulate_imported_y_bounds(
		imported,
		root_transform,
		Vector2(INF, -INF)
	)


func _position_imported_visual() -> void:
	var imported := _get_imported_visual()
	if imported == null:
		return

	var bounds := _imported_visual_y_bounds()
	var min_y: float = 0.0
	if bounds.x < INF and bounds.y > -INF:
		min_y = bounds.x

	# Align the actual visible mesh bottom with the collision body's floor.
	# This also repairs older converted OBJ files whose local Y minimum is not 0.
	imported.position = Vector3(
		0.0,
		-token_height_cells * 0.5 - min_y,
		0.0
	)


func set_token_size(footprint_cells: float) -> void:
	_footprint_cells = maxf(footprint_cells, 0.5)

	var imported_bounds := _imported_visual_y_bounds()
	if imported_bounds.x < INF and imported_bounds.y > -INF:
		token_height_cells = maxf(
			imported_bounds.y - imported_bounds.x,
			0.1
		)

	var width: float = _footprint_cells * cell_size
	var height: float = token_height_cells * cell_size

	var new_shape: BoxShape3D = BoxShape3D.new()
	new_shape.size = Vector3(width, height, width)
	collision_shape.shape = new_shape

	if _get_imported_visual() != null:
		# I modelli convertiti sono gia' espressi in celle Godot:
		# la base e' stata scalata esattamente al footprint D&D.
		visuals.scale = Vector3.ONE * cell_size
	else:
		var horizontal_visual_scale: float = maxf(0.55, _footprint_cells)
		visuals.scale = Vector3(
			horizontal_visual_scale,
			cell_size,
			horizontal_visual_scale
		)

	selection_marker.scale = Vector3(
		_footprint_cells,
		1.0,
		_footprint_cells
	)
	selection_marker.position.y = -(height * 0.5) + 0.02

	var facing_scale: float = clampf(_footprint_cells * 0.72, 0.62, 1.65)
	facing_marker.scale = Vector3(facing_scale, 1.0, facing_scale)
	facing_marker.position.y = -(height * 0.5) + 0.045

	var eye_height: float = height * 0.38
	var ground_y: float = -(height * 0.5) + 0.055

	if vision_cone.has_method("configure"):
		vision_cone.call(
			"configure",
			cell_size,
			vision_cone_length_cells,
			eye_height,
			ground_y
		)

	_position_imported_visual()
	_update_overlay_position()


func set_display_name(value: String) -> void:
	token_display_name = value.strip_edges()
	_ensure_token_overlay()
	if is_instance_valid(_name_label):
		_name_label.text = token_display_name
		_name_label.visible = not token_display_name.is_empty()


func get_display_name() -> String:
	return token_display_name


func get_condition_definitions() -> Array:
	return CONDITION_DEFINITIONS.duplicate(true)


func get_conditions() -> Array[String]:
	return _conditions.duplicate()


func has_condition(condition_id: String) -> bool:
	return condition_id.strip_edges().to_lower() in _conditions


func set_condition(condition_id: String, enabled: bool) -> void:
	var normalized := condition_id.strip_edges().to_lower()
	if not _is_valid_condition(normalized):
		return
	if enabled:
		if not (normalized in _conditions):
			_conditions.append(normalized)
	else:
		_conditions.erase(normalized)
	_update_status_overlay()


func set_conditions(value: Variant) -> void:
	var resolved: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if not item is String:
				continue
			var normalized := String(item).strip_edges().to_lower()
			if _is_valid_condition(normalized) and not (normalized in resolved):
				resolved.append(normalized)
	_conditions = resolved
	_update_status_overlay()


func _is_valid_condition(condition_id: String) -> bool:
	for definition: Dictionary in CONDITION_DEFINITIONS:
		if String(definition.get("id", "")) == condition_id:
			return true
	return false


func _ensure_token_overlay() -> void:
	if is_instance_valid(_overlay_root):
		return

	_overlay_root = get_node_or_null(TOKEN_OVERLAY_NAME) as Node3D
	if _overlay_root == null:
		_overlay_root = Node3D.new()
		_overlay_root.name = TOKEN_OVERLAY_NAME
		add_child(_overlay_root)

	_name_label = _overlay_root.get_node_or_null("Name") as Label3D
	if _name_label == null:
		_name_label = Label3D.new()
		_name_label.name = "Name"
		_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_label.fixed_size = false
		_name_label.font_size = 32
		_name_label.outline_size = 8
		_name_label.modulate = Color(1.0, 0.97, 0.88, 1.0)
		_name_label.visible = false
		_overlay_root.add_child(_name_label)

	_status_label = _overlay_root.get_node_or_null("Statuses") as Label3D
	if _status_label == null:
		_status_label = Label3D.new()
		_status_label.name = "Statuses"
		_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_status_label.fixed_size = false
		_status_label.font_size = 24
		_status_label.outline_size = 7
		_status_label.modulate = Color(1.0, 0.82, 0.35, 1.0)
		_status_label.visible = false
		_overlay_root.add_child(_status_label)

	_update_overlay_position()


func _update_overlay_position() -> void:
	if not is_instance_valid(_overlay_root):
		return
	var top_y := token_height_cells * cell_size * 0.5
	_overlay_root.position = Vector3(0.0, top_y + 0.28 * cell_size, 0.0)
	if is_instance_valid(_name_label):
		# Label3D con fixed_size=false: la sua dimensione e' in unita' del
		# mondo, quindi si comporta come il token e si rimpicciolisce con la
		# distanza dalla camera.
		_name_label.pixel_size = 0.012 * cell_size
		_name_label.position = Vector3.ZERO
	if is_instance_valid(_status_label):
		_status_label.pixel_size = 0.010 * cell_size
		_status_label.position = Vector3(0.0, -0.22 * cell_size, 0.0)


func _update_status_overlay() -> void:
	_ensure_token_overlay()
	if not is_instance_valid(_status_label):
		return
	var icons: PackedStringArray = []
	for definition: Dictionary in CONDITION_DEFINITIONS:
		var condition_id := String(definition.get("id", ""))
		if condition_id in _conditions:
			icons.append(String(definition.get("icon", "•")))
	_status_label.text = "  ".join(icons)
	_status_label.visible = not icons.is_empty()



func set_token_color(token_color: Color) -> void:
	var body_material: StandardMaterial3D = StandardMaterial3D.new()
	body_material.albedo_color = token_color
	body_material.roughness = 0.62
	body_material.metallic = 0.04

	var head_material: StandardMaterial3D = StandardMaterial3D.new()
	head_material.albedo_color = token_color.lightened(0.16)
	head_material.roughness = 0.7

	for child_node: Node in visuals.get_children():
		if child_node.has_meta("token_imported_visual"):
			continue
		if child_node is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child_node as MeshInstance3D

			# Il piccolo visore frontale usa il proprio materiale dorato.
			if child_node.name == "FacingVisor":
				continue

			if child_node.name == "Head":
				mesh_instance.material_override = head_material
			else:
				mesh_instance.material_override = body_material


func set_selected(value: bool) -> void:
	_selected = value

	if is_instance_valid(selection_marker):
		selection_marker.visible = value


func is_selected() -> bool:
	return _selected


func set_vision_cone_visible(value: bool) -> void:
	if is_instance_valid(vision_cone):
		vision_cone.visible = value


func is_vision_cone_visible() -> bool:
	return is_instance_valid(vision_cone) and vision_cone.visible


func get_size_name() -> String:
	return _size_name


func get_footprint_cells() -> float:
	return _footprint_cells

func get_footprint_extent() -> Vector2:
	return Vector2.ONE*_footprint_cells*cell_size

func get_movement_exclusions() -> Array[RID]:
	return [get_rid()]


func get_spell_origin_position() -> Vector3:
	# Il nodo Head procedurale resta nell'albero anche quando e' nascosto.
	# Con una miniatura importata non deve quindi essere usato come origine.
	if _get_imported_visual() == null:
		var head: Node3D = get_node_or_null("Visuals/Head") as Node3D
		if head != null:
			return head.global_position

	return (
		global_position
		+ Vector3.UP * token_height_cells * cell_size * 0.39
	)


func get_first_person_camera_position() -> Vector3:
	var eye_height: float = token_height_cells * cell_size * 0.38
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var forward_offset: float = maxf(
		0.16,
		_footprint_cells * cell_size * 0.18
	)

	return (
		global_position
		+ Vector3.UP * eye_height
		+ forward * forward_offset
	)


func nudge_grid(grid_direction: Vector2i) -> void:
	# Le frecce sono relative all'orientamento del token:
	# su = avanti, giu = indietro, sinistra/destra = movimento laterale.
	# In questo modo "avanti" coincide sempre con la freccia dorata e con
	# la direzione della visuale in prima persona.
	var local_step: Vector3 = Vector3(
		float(grid_direction.x),
		0.0,
		float(grid_direction.y)
	)
	var world_step: Vector3 = global_transform.basis * local_step
	world_step.y = 0.0

	# Il token può essere orientato anche a 45°. L'arrotondamento produce
	# quindi il passo ortogonale o diagonale coerente con la direzione visiva.
	world_step.x = round(world_step.x)
	world_step.z = round(world_step.z)

	var destination := global_position + world_step * cell_size
	if movement_validator.is_valid() and not movement_validator.call(self, destination):
		return
	if move_and_collide(destination - global_position) == null:
		_snap_horizontal_to_grid()


func rotate_grid(rotation_steps: int) -> void:
	rotation.y += deg_to_rad(45.0 * float(rotation_steps))
	rotation.y = snappedf(rotation.y, PI / 4.0)


func snap_horizontal_to_grid() -> void:
	_snap_horizontal_to_grid()


func _snap_horizontal_to_grid() -> void:
	# La griglia tattica e' globale: con cell_size == 1, X e Z sono
	# coordinate intere anche quando il token e' sospeso.
	global_position.x = _snap_coordinate(global_position.x)
	global_position.z = _snap_coordinate(global_position.z)


func _snap_coordinate(value: float) -> float:
	return round(value / cell_size) * cell_size


func snap_destination(point: Vector3, _support: Node3D = null) -> Vector3:
	var snapped := point
	snapped.x = _snap_coordinate(snapped.x)
	snapped.z = _snap_coordinate(snapped.z)
	return snapped
