extends CharacterBody3D

const TOKEN_LIBRARY_MANIFEST := "res://assets/tokens/token_library.json"
const IMPORTED_VISUAL_NAME := "ImportedVisual"
const TOKEN_OVERLAY_NAME := "TokenOverlay"
const CONDITION_RINGS_NAME := "ConditionRings"
# Protezione contro asset importati con bounds corrotti o unita' errate.
const MAX_IMPORTED_EXTENT_PER_FOOTPRINT := 3.0

# Condizioni standard D&D 5e / SRD. Gli ID rimangono in inglese per essere
# stabili nei salvataggi; etichette e pittogrammi sono solo presentazione.
const CONDITION_DEFINITIONS := [
	# Le 15 condizioni ufficiali D&D 5e / SRD.
	{"id": "blinded", "name": "Accecato", "icon": "🙈", "official": true},
	{"id": "charmed", "name": "Affascinato", "icon": "💘", "official": true},
	{"id": "deafened", "name": "Assordato", "icon": "🔇", "official": true},
	{"id": "exhaustion", "name": "Sfinimento", "icon": "🥱", "official": true},
	{"id": "frightened", "name": "Spaventato", "icon": "😨", "official": true},
	{"id": "grappled", "name": "Afferrato", "icon": "🪢", "official": true},
	{"id": "incapacitated", "name": "Incapacitato", "icon": "⛔", "official": true},
	{"id": "invisible", "name": "Invisibile", "icon": "👻", "official": true},
	{"id": "paralyzed", "name": "Paralizzato", "icon": "🧊", "official": true},
	{"id": "petrified", "name": "Pietrificato", "icon": "🗿", "official": true},
	{"id": "poisoned", "name": "Avvelenato", "icon": "☠️", "official": true},
	{"id": "prone", "name": "Prono", "icon": "⬇️", "official": true},
	{"id": "restrained", "name": "Trattenuto", "icon": "⛓️", "official": true},
	{"id": "stunned", "name": "Stordito", "icon": "💫", "official": true},
	{"id": "unconscious", "name": "Privo di sensi", "icon": "😴", "official": true},

	# Marker tattici utili nel VTT. Non sono condizioni ufficiali SRD.
	{"id": "concentrating", "name": "Concentrazione", "icon": "🧠", "official": false},
	{"id": "surprised", "name": "Sorpreso", "icon": "❗", "official": false},
	{"id": "hidden", "name": "Nascosto", "icon": "🥷", "official": false},
	{"id": "dead", "name": "Morto", "icon": "💀", "official": false},
	{
		"id": "flying",
		"name": "Volante",
		"icon": "🪽",
		"official": false,
		"automatic": true,
		"ring": false
	},
]

@export var cell_size: float = 1.0
@export var gravity_multiplier: float = 1.0
@export var terminal_velocity: float = 40.0
@export var token_height_cells: float = 2.0
@export var flying: bool = true
@export var visual_asset_path: String = ""
@export var visual_native_footprint_cells: float = 0.0
@export_range(0, 3, 1) var visual_front_quarter_turns: int = 0
@export var token_display_name: String = ""
@export var token_id: String = ""
@export var token_pack_id: String = ""
@export var party_id: String = ""
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
var _visual_native_footprint_cells: float = 1.0
var _rig_type: String = "static"
var _animation_set: String = ""
var _default_animation: String = ""
var _uses_manifest_default: bool = false
var _conditions: Array[String] = []
var _automatic_conditions: Array[String] = []
var _automatic_condition_elapsed: float = 0.0
const AUTOMATIC_CONDITION_INTERVAL := 0.25
var _reach_feet: float = 5.0
var _reach_overridden: bool = false
var _condition_rings_root: Node3D
var _overlay_root: Node3D
var _name_label: Label3D
var _status_label: Label3D
var _flanking_badge_root: Node3D
var _flanking_badge_border: MeshInstance3D
var _flanking_badge_background: MeshInstance3D
var _flanking_badge_label: Label3D
var _flanking_badge_border_material: StandardMaterial3D
var _flanking_badge_background_material: StandardMaterial3D
var _hp_bar_root: Node3D
var _hp_bar_mesh: MeshInstance3D
var _hp_bar_material: StandardMaterial3D
var _hp_bar_label: Label3D
var _player_hp_current: int = 0
var _player_hp_max: int = 0
var _hp_bar_show_percentage: bool = true
var movement_validator: Callable
var grid_support: Node3D
# The visible VolumetricGrid is the primary vertical support for tactical
# tokens. Physics bodies remain a fallback for places without grid cells.
var volumetric_grid: Node3D
var _support_transform: Transform3D
var _transformation_history: Array[Dictionary] = []
const MAX_TRANSFORMATION_HISTORY := 16


func _ready() -> void:
	add_to_group("dnd_token")
	platform_floor_layers = 1
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_gravity = float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	_ensure_token_id()
	_size_name = default_size_name
	_footprint_cells = maxf(default_footprint_cells, 0.5)
	_reach_feet = _default_reach_feet()
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
	_automatic_condition_elapsed += delta
	if _automatic_condition_elapsed >= AUTOMATIC_CONDITION_INTERVAL:
		_automatic_condition_elapsed = 0.0
		_refresh_automatic_flying_condition()

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

	# Grid-first landing: stop at the rendered top face before the CharacterBody
	# can enter the solid mesh underneath. This also prevents fast falls from
	# tunnelling through a thin tactical cell.
	var grid_landing_y := _grid_landing_center_y(delta)
	if grid_landing_y < INF:
		global_position.y = grid_landing_y
		velocity = Vector3.ZERO
		grid_support = null
		_snap_horizontal_to_grid()
		_finish_gravity_after_landing()
		return

	# No tactical cell under the footprint: preserve the old physical-floor
	# behavior for carts, special platforms and non-gridded terrain.
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


func set_volumetric_grid(grid: Node3D) -> void:
	volumetric_grid = grid
	call_deferred("refresh_automatic_conditions")


func refresh_automatic_conditions() -> void:
	_automatic_condition_elapsed = 0.0
	_refresh_automatic_flying_condition()


func _refresh_automatic_flying_condition() -> void:
	if (
		volumetric_grid == null
		or not is_instance_valid(volumetric_grid)
		or not volumetric_grid.has_method(
			"has_grid_cell_immediately_below"
		)
	):
		return

	var half_height := token_height_cells * cell_size * 0.5
	var base_y := global_position.y - half_height
	var has_support := bool(
		volumetric_grid.call(
			"has_grid_cell_immediately_below",
			global_position,
			_footprint_cells,
			base_y,
			cell_size * 0.10
		)
	)
	_set_automatic_condition("flying", not has_support)


func _set_automatic_condition(
	condition_id: String,
	enabled: bool
) -> void:
	var normalized := condition_id.strip_edges().to_lower()
	if not _condition_is_automatic(normalized):
		return
	var changed := false
	if enabled:
		if not (normalized in _automatic_conditions):
			_automatic_conditions.append(normalized)
			changed = true
	else:
		if normalized in _automatic_conditions:
			_automatic_conditions.erase(normalized)
			changed = true
	if changed:
		_update_status_overlay()


static func support_is_immediately_below(
	base_y: float,
	support_top_y: float,
	cell_size_value: float
) -> bool:
	if support_top_y >= INF:
		return false
	var safe_cell := maxf(cell_size_value, 0.001)
	return absf(base_y - support_top_y) <= safe_cell * 0.10 + 0.0001


func _grid_landing_center_y(delta: float) -> float:
	if (
		volumetric_grid == null
		or not is_instance_valid(volumetric_grid)
		or not volumetric_grid.has_method("get_support_top_for_footprint")
	):
		return INF

	var half_height := token_height_cells * cell_size * 0.5
	var current_bottom := global_position.y - half_height
	var projected_bottom := current_bottom + velocity.y * delta

	# Allow one half-cell above the current bottom so an already half-embedded
	# token is repaired onto the grid on its next gravity tick.
	var max_support_y := current_bottom + cell_size * 0.55
	var min_support_y := projected_bottom - cell_size * 0.05
	var value: Variant = volumetric_grid.call(
		"get_support_top_for_footprint",
		global_position,
		_footprint_cells,
		max_support_y,
		min_support_y
	)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return INF

	var support_top := float(value)
	if support_top >= INF:
		return INF

	# Land when the next gravity step would reach/cross the cell top, or repair
	# a token whose bottom is already inside that grid cell.
	if (
		projected_bottom <= support_top + cell_size * 0.02
		or current_bottom < support_top
	):
		return support_top + half_height + cell_size * 0.005

	return INF


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


func apply_forced_movement(
	world_direction: Vector3,
	distance_world: float
) -> bool:
	var direction: Vector3 = world_direction
	direction.y = 0.0
	if direction.length_squared() < 0.0001 or distance_world <= 0.0:
		return false
	direction = direction.normalized()

	var destination: Vector3 = global_position + direction * distance_world
	destination = snap_destination(destination)

	if (
		movement_validator.is_valid()
		and not movement_validator.call(self, destination)
	):
		return false

	var delta: Vector3 = destination - global_position
	if delta.length_squared() < 0.0001:
		return false

	move_and_collide(delta)
	_snap_horizontal_to_grid()
	velocity = Vector3.ZERO
	grid_support = null
	return true


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
	if not _reach_overridden:
		_reach_feet = _default_reach_feet()

	set_token_size(_footprint_cells)
	set_token_color(token_color)
	_snap_horizontal_to_grid()


func set_visual_asset(
	path: String,
	native_footprint_override: float = 0.0
) -> bool:
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
		if native_footprint_override > 0.0:
			_visual_native_footprint_cells = maxf(
				native_footprint_override,
				0.5
			)
		visual_asset_path = requested_path
		_apply_imported_visual_front()
		_position_imported_visual()
		return true

	# Token packs may be absent locally. Do not ask ResourceLoader about a
	# path that is not in the virtual filesystem: Godot logs a hard debugger
	# error even when ResourceLoader.exists() is only used as a probe.
	var source_exists := FileAccess.file_exists(requested_path)
	var remap_exists := FileAccess.file_exists(requested_path + ".remap")
	if not source_exists and not remap_exists:
		return false
	if not ResourceLoader.exists(requested_path):
		return false

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

	var profile := _profile_for_visual(requested_path)
	_clear_imported_visual()
	_set_procedural_visuals_visible(false)
	imported.name = IMPORTED_VISUAL_NAME
	imported.set_meta("token_imported_visual", true)
	_imported_visual_base_basis = imported.transform.basis
	var native_footprint := maxf(default_footprint_cells, 0.5)
	if visual_native_footprint_cells > 0.0:
		native_footprint = visual_native_footprint_cells
	if not profile.is_empty():
		native_footprint = maxf(
			float(profile.get("footprint", native_footprint)),
			0.5
		)
	if native_footprint_override > 0.0:
		native_footprint = maxf(native_footprint_override, 0.5)
	_visual_native_footprint_cells = native_footprint
	visuals.add_child(imported)
	_configure_imported_animation(imported, profile)

	visual_asset_path = requested_path
	_loaded_visual_asset_path = requested_path
	_apply_imported_visual_front()
	_position_imported_visual()
	return true


func get_visual_asset_path() -> String:
	return _loaded_visual_asset_path


func get_visual_native_footprint_cells() -> float:
	return _visual_native_footprint_cells


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
		requested_path = _profile_visual_asset(profile)
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


func _profile_visual_asset(profile: Dictionary) -> String:
	var path := String(profile.get("visual_asset", "")).strip_edges()
	if not path.is_empty():
		return path
	# Manifest v2 compatibility.
	return String(profile.get("obj", "")).strip_edges()


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
			if _profile_visual_asset(profile) == requested:
				return profile.duplicate(true)
	return {}


func _default_visual_asset_path() -> String:
	return _profile_visual_asset(_default_token_profile())


func get_rig_type() -> String:
	return _rig_type


func get_animation_set() -> String:
	return _animation_set


func play_visual_animation(animation_name: String) -> bool:
	var imported := _get_imported_visual()
	if imported == null:
		return false
	var player := _find_animation_player(imported)
	if player == null:
		return false
	var resolved := _resolve_animation_name(player, animation_name)
	if resolved == &"":
		return false
	player.play(resolved)
	return true


func _configure_imported_animation(
	imported: Node3D,
	profile: Dictionary
) -> void:
	_rig_type = String(profile.get("rig_type", "static"))
	_animation_set = String(profile.get("animation_set", ""))
	_default_animation = String(profile.get("default_animation", ""))

	imported.set_meta("rig_type", _rig_type)
	imported.set_meta("animation_set", _animation_set)
	imported.set_meta("skeleton_profile", String(
		profile.get("skeleton_profile", "")
	))

	var player := _find_animation_player(imported)
	if player == null:
		return

	# Optional hook for a shared CC0 AnimationLibrary (for example a
	# retargeted humanoid library). Converter-generated manifests leave this
	# empty until a project library is assigned, so no external asset is bundled.
	var library_path := String(
		profile.get("animation_library", "")
	).strip_edges()
	if not library_path.is_empty():
		var library_resource := ResourceLoader.load(library_path)
		if library_resource is AnimationLibrary:
			if not player.has_animation_library(&"shared"):
				player.add_animation_library(
					&"shared",
					library_resource as AnimationLibrary
				)

	if not _default_animation.is_empty():
		var resolved := _resolve_animation_name(
			player,
			_default_animation
		)
		if resolved != &"":
			player.play(resolved)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _resolve_animation_name(
	player: AnimationPlayer,
	animation_name: String
) -> StringName:
	var requested := animation_name.strip_edges()
	if requested.is_empty():
		return &""

	var exact := StringName(requested)
	if player.has_animation(exact):
		return exact

	var shared := StringName("shared/%s" % requested)
	if player.has_animation(shared):
		return shared

	var requested_lower := requested.to_lower()
	for candidate_value: String in player.get_animation_list():
		var candidate := StringName(candidate_value)
		var candidate_text := candidate_value.to_lower()
		if (
			candidate_text == requested_lower
			or candidate_text.ends_with("/" + requested_lower)
		):
			return candidate
	return &""


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
	_visual_native_footprint_cells = 1.0
	_rig_type = "static"
	_animation_set = ""
	_default_animation = ""


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


func _imported_visual_xz_radius() -> float:
	var imported := _get_imported_visual()
	if imported == null:
		return 0.0
	return _accumulate_imported_xz_radius(
		imported,
		imported.transform,
		0.0
	)


func _position_imported_visual() -> void:
	var imported := _get_imported_visual()
	if imported == null:
		return

	var bounds := _imported_visual_y_bounds()
	var min_y: float = 0.0
	var local_height: float = token_height_cells
	if bounds.x < INF and bounds.y > -INF:
		min_y = bounds.x
		local_height = maxf(bounds.y - bounds.x, 0.1)

	# La traslazione e' nello spazio locale della mesh. La scala relativa alla
	# taglia scelta viene applicata sul nodo Visuals, quindi qui centriamo la
	# geometria usando la sua altezza nativa.
	imported.position = Vector3(
		0.0,
		-local_height * 0.5 - min_y,
		0.0
	)


func set_token_size(footprint_cells: float) -> void:
	_footprint_cells = maxf(footprint_cells, 0.5)

	var imported_bounds := _imported_visual_y_bounds()
	var visual_scale_ratio := 1.0
	if _get_imported_visual() != null:
		visual_scale_ratio = (
			_footprint_cells
			/ maxf(_visual_native_footprint_cells, 0.5)
		)

		# Le miniature possono sporgere dal footprint (ali, code, armi), ma
		# alcuni OBJ hanno bounds chiaramente corrotti. Limitiamo solo gli
		# outlier estremi a 3x il footprint scelto.
		var max_extent_cells: float = maxf(
			_footprint_cells * MAX_IMPORTED_EXTENT_PER_FOOTPRINT,
			1.5
		)
		var local_radius: float = _imported_visual_xz_radius()
		if local_radius > 0.0001:
			visual_scale_ratio = minf(
				visual_scale_ratio,
				max_extent_cells / (local_radius * 2.0)
			)

		if imported_bounds.x < INF and imported_bounds.y > -INF:
			var local_height: float = maxf(
				imported_bounds.y - imported_bounds.x,
				0.1
			)
			visual_scale_ratio = minf(
				visual_scale_ratio,
				max_extent_cells / local_height
			)
			token_height_cells = clampf(
				local_height * visual_scale_ratio,
				0.1,
				max_extent_cells
			)

	var width: float = _footprint_cells * cell_size
	var height: float = token_height_cells * cell_size

	var new_shape: BoxShape3D = BoxShape3D.new()
	new_shape.size = Vector3(width, height, width)
	collision_shape.shape = new_shape

	if _get_imported_visual() != null:
		visuals.scale = (
			Vector3.ONE * cell_size * visual_scale_ratio
		)
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
	_update_condition_rings()


func _ensure_token_id() -> void:
	if not token_id.strip_edges().is_empty():
		token_id = token_id.strip_edges().left(96)
		return
	var micros := int(Time.get_unix_time_from_system() * 1000000.0)
	token_id = "token_%d_%d" % [micros, get_instance_id()]


func set_token_id(value: String) -> void:
	var clean := value.strip_edges()
	if clean.is_empty():
		_ensure_token_id()
		return
	token_id = clean.left(96)


func get_token_id() -> String:
	_ensure_token_id()
	return token_id


func set_token_pack_id(value: String) -> void:
	token_pack_id = value.strip_edges().left(96)


func get_token_pack_id() -> String:
	return token_pack_id.strip_edges()


func set_display_name(value: String) -> void:
	token_display_name = value.strip_edges()
	_ensure_token_overlay()
	if is_instance_valid(_name_label):
		_name_label.text = token_display_name
		_name_label.visible = not token_display_name.is_empty()


func get_display_name() -> String:
	return token_display_name


func set_party_id(value: String) -> void:
	party_id = value.strip_edges().left(80)


func get_party_id() -> String:
	return party_id


func get_effective_party_id() -> String:
	var clean := party_id.strip_edges()
	return clean if not clean.is_empty() else "Default"


func get_condition_definitions() -> Array:
	return CONDITION_DEFINITIONS.duplicate(true)


func get_conditions() -> Array[String]:
	# Only persistent/manual conditions are serialized.
	return _conditions.duplicate()


func get_automatic_conditions() -> Array[String]:
	return _automatic_conditions.duplicate()


func get_active_condition_display_parts() -> PackedStringArray:
	var parts := PackedStringArray()
	for definition: Dictionary in CONDITION_DEFINITIONS:
		var condition_id := String(definition.get("id", ""))
		if (
			condition_id in _conditions
			or condition_id in _automatic_conditions
		):
			parts.append(
				"%s %s" % [
					String(definition.get("icon", "•")),
					String(definition.get("name", condition_id))
				]
			)
	return parts


func has_condition(condition_id: String) -> bool:
	var normalized := condition_id.strip_edges().to_lower()
	return (
		normalized in _conditions
		or normalized in _automatic_conditions
	)


func set_condition(condition_id: String, enabled: bool) -> void:
	var normalized := condition_id.strip_edges().to_lower()
	if (
		not _is_valid_condition(normalized)
		or _condition_is_automatic(normalized)
	):
		return
	if enabled:
		if not (normalized in _conditions):
			_conditions.append(normalized)
	else:
		_conditions.erase(normalized)
	_update_status_overlay()
	_update_condition_rings()


func set_conditions(value: Variant) -> void:
	var resolved: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if not item is String:
				continue
			var normalized := String(item).strip_edges().to_lower()
			if (
				_is_valid_condition(normalized)
				and not _condition_is_automatic(normalized)
				and not (normalized in resolved)
			):
				resolved.append(normalized)
	_conditions = resolved
	_update_status_overlay()
	_update_condition_rings()


func _is_valid_condition(condition_id: String) -> bool:
	for definition: Dictionary in CONDITION_DEFINITIONS:
		if String(definition.get("id", "")) == condition_id:
			return true
	return false


func _condition_is_automatic(condition_id: String) -> bool:
	for definition: Dictionary in CONDITION_DEFINITIONS:
		if String(definition.get("id", "")) == condition_id:
			return bool(definition.get("automatic", false))
	return false


func _condition_ring_color(condition_id: String) -> Color:
	match condition_id:
		"blinded":
			return Color(1.0, 0.88, 0.12, 1.0)
		"charmed":
			return Color(1.0, 0.20, 0.72, 1.0)
		"deafened":
			return Color(0.10, 0.78, 1.0, 1.0)
		"exhaustion":
			return Color(0.58, 0.34, 0.14, 1.0)
		"frightened":
			return Color(0.62, 0.22, 1.0, 1.0)
		"grappled":
			return Color(1.0, 0.43, 0.08, 1.0)
		"incapacitated":
			return Color(0.72, 0.72, 0.76, 1.0)
		"invisible":
			return Color(0.25, 1.0, 0.82, 1.0)
		"paralyzed":
			return Color(0.12, 0.38, 1.0, 1.0)
		"petrified":
			return Color(0.42, 0.54, 0.62, 1.0)
		"poisoned":
			# Richiesta esplicita: avvelenato = verde.
			return Color(0.12, 0.92, 0.24, 1.0)
		"prone":
			return Color(1.0, 0.62, 0.04, 1.0)
		"restrained":
			return Color(1.0, 0.16, 0.10, 1.0)
		"stunned":
			return Color(1.0, 1.0, 0.18, 1.0)
		"unconscious":
			return Color(0.20, 0.22, 0.52, 1.0)
		"concentrating":
			return Color(0.88, 0.18, 1.0, 1.0)
		"surprised":
			return Color(1.0, 0.94, 0.80, 1.0)
		"hidden":
			return Color(0.04, 0.58, 0.48, 1.0)
		"dead":
			return Color(0.38, 0.02, 0.03, 1.0)
		_:
			return Color.WHITE


func _ensure_condition_rings_root() -> void:
	if is_instance_valid(_condition_rings_root):
		return
	_condition_rings_root = get_node_or_null(
		CONDITION_RINGS_NAME
	) as Node3D
	if _condition_rings_root == null:
		_condition_rings_root = Node3D.new()
		_condition_rings_root.name = CONDITION_RINGS_NAME
		add_child(_condition_rings_root)


func _clear_condition_rings() -> void:
	_ensure_condition_rings_root()
	for child: Node in _condition_rings_root.get_children():
		_condition_rings_root.remove_child(child)
		child.queue_free()


func _accumulate_imported_xz_radius(
	node: Node3D,
	transform_to_visuals: Transform3D,
	current_radius: float
) -> float:
	var result := current_radius
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var aabb: AABB = mesh_instance.get_aabb()
			for endpoint_index: int in range(8):
				var point: Vector3 = (
					transform_to_visuals
					* aabb.get_endpoint(endpoint_index)
				)
				result = maxf(
					result,
					Vector2(point.x, point.z).length()
				)

	for child_node: Node in node.get_children():
		if child_node is Node3D:
			var child := child_node as Node3D
			result = _accumulate_imported_xz_radius(
				child,
				transform_to_visuals * child.transform,
				result
			)
	return result


func _visual_horizontal_radius_world() -> float:
	var fallback := _footprint_cells * cell_size * 0.5
	var imported := _get_imported_visual()
	if imported == null:
		return fallback

	var local_radius := _accumulate_imported_xz_radius(
		imported,
		imported.transform,
		0.0
	)
	var horizontal_scale := maxf(
		absf(visuals.scale.x),
		absf(visuals.scale.z)
	)
	return maxf(fallback, local_radius * horizontal_scale)


func _update_condition_rings() -> void:
	_clear_condition_rings()
	if _conditions.is_empty():
		return

	var visual_radius := _visual_horizontal_radius_world()
	var clearance := 0.12 * cell_size
	var ring_spacing := 0.11 * cell_size
	var half_thickness := 0.025 * cell_size
	var waist_y := token_height_cells * cell_size * 0.05

	var ring_index := 0
	for definition: Dictionary in CONDITION_DEFINITIONS:
		var condition_id := String(definition.get("id", ""))
		if (
			not (condition_id in _conditions)
			or not bool(definition.get("ring", true))
		):
			continue

		var center_radius := (
			visual_radius
			+ clearance
			+ float(ring_index) * ring_spacing
		)
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(
			center_radius - half_thickness,
			0.01
		)
		torus.outer_radius = center_radius + half_thickness
		torus.rings = 48
		torus.ring_segments = 10

		var color := _condition_ring_color(condition_id)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.35

		var ring := MeshInstance3D.new()
		ring.name = "Condition_%s" % condition_id
		ring.mesh = torus
		ring.material_override = material
		ring.position = Vector3(0.0, waist_y, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_condition_rings_root.add_child(ring)
		ring_index += 1


func _ensure_token_overlay() -> void:
	if is_instance_valid(_overlay_root):
		_ensure_health_bar()
		_update_overlay_position()
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

	_ensure_health_bar()
	_update_overlay_position()


func _ensure_flanking_badge() -> void:
	if _overlay_root == null or not is_instance_valid(_overlay_root):
		return
	if (
		is_instance_valid(_flanking_badge_root)
		and is_instance_valid(_flanking_badge_border)
		and is_instance_valid(_flanking_badge_background)
		and is_instance_valid(_flanking_badge_label)
	):
		return

	_flanking_badge_root = (
		_overlay_root.get_node_or_null("FlankingBadge") as Node3D
	)
	if _flanking_badge_root == null:
		_flanking_badge_root = Node3D.new()
		_flanking_badge_root.name = "FlankingBadge"
		_overlay_root.add_child(_flanking_badge_root)

	for legacy_name: String in ["Border", "Background", "Label"]:
		var legacy := _flanking_badge_root.get_node_or_null(legacy_name)
		if legacy != null:
			_flanking_badge_root.remove_child(legacy)
			legacy.queue_free()

	_flanking_badge_border = MeshInstance3D.new()
	_flanking_badge_border.name = "Border"
	_flanking_badge_border.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_flanking_badge_root.add_child(_flanking_badge_border)

	var border_quad := QuadMesh.new()
	border_quad.size = Vector2(2.22 * cell_size, 0.46 * cell_size)
	_flanking_badge_border.mesh = border_quad

	_flanking_badge_border_material = StandardMaterial3D.new()
	_flanking_badge_border_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	_flanking_badge_border_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	_flanking_badge_border_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flanking_badge_border_material.no_depth_test = true
	_flanking_badge_border_material.albedo_color = Color(
		0.72, 0.48, 0.20, 0.82
	)
	_flanking_badge_border_material.render_priority = 1
	_flanking_badge_border.material_override = (
		_flanking_badge_border_material
	)

	_flanking_badge_background = MeshInstance3D.new()
	_flanking_badge_background.name = "Background"
	_flanking_badge_background.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_flanking_badge_root.add_child(_flanking_badge_background)

	var background_quad := QuadMesh.new()
	background_quad.size = Vector2(2.12 * cell_size, 0.38 * cell_size)
	_flanking_badge_background.mesh = background_quad

	_flanking_badge_background_material = StandardMaterial3D.new()
	_flanking_badge_background_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	_flanking_badge_background_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	_flanking_badge_background_material.cull_mode = (
		BaseMaterial3D.CULL_DISABLED
	)
	_flanking_badge_background_material.no_depth_test = true
	_flanking_badge_background_material.albedo_color = Color(
		0.035, 0.04, 0.05, 0.90
	)
	_flanking_badge_background_material.render_priority = 2
	_flanking_badge_background.material_override = (
		_flanking_badge_background_material
	)

	_flanking_badge_label = Label3D.new()
	_flanking_badge_label.name = "Label"
	_flanking_badge_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_flanking_badge_label.fixed_size = false
	_flanking_badge_label.no_depth_test = true
	_flanking_badge_label.font_size = 22
	_flanking_badge_label.outline_size = 4
	_flanking_badge_label.modulate = Color(1.0, 0.94, 0.82, 1.0)
	_flanking_badge_label.outline_modulate = Color(0.03, 0.035, 0.045, 1.0)
	_flanking_badge_label.text = "🗡️  Affiancato"
	_flanking_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flanking_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flanking_badge_root.add_child(_flanking_badge_label)

	_flanking_badge_border.position.z = 0.0
	_flanking_badge_background.position.z = 0.004 * cell_size
	_flanking_badge_label.position.z = 0.008 * cell_size
	_flanking_badge_root.visible = false


func set_flanking_indicator_visible(value: bool) -> void:
	if not is_instance_valid(_flanking_badge_root):
		_ensure_token_overlay()
	if is_instance_valid(_flanking_badge_root):
		_flanking_badge_root.visible = value


func is_flanking_indicator_visible() -> bool:
	return (
		is_instance_valid(_flanking_badge_root)
		and _flanking_badge_root.visible
	)


func _update_flanking_badge_facing() -> void:
	if (
		not is_instance_valid(_flanking_badge_root)
		or not _flanking_badge_root.visible
	):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return
	var target := camera.global_position
	if _flanking_badge_root.global_position.distance_squared_to(target) <= 0.000001:
		return
	# Rotate the entire badge as one object. Border, background and text
	# therefore never acquire different front/back orientations.
	_flanking_badge_root.look_at(target, Vector3.UP, true)


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
	if is_instance_valid(_flanking_badge_root):
		_flanking_badge_root.position = Vector3(
			0.0,
			0.66 * cell_size,
			0.0
		)
	if is_instance_valid(_flanking_badge_border):
		var border_quad := _flanking_badge_border.mesh as QuadMesh
		if border_quad != null:
			border_quad.size = Vector2(
				2.22 * cell_size,
				0.46 * cell_size
			)
	if is_instance_valid(_flanking_badge_background):
		var background_quad := _flanking_badge_background.mesh as QuadMesh
		if background_quad != null:
			background_quad.size = Vector2(
				2.12 * cell_size,
				0.38 * cell_size
			)
		_flanking_badge_background.position.z = 0.004 * cell_size
	if is_instance_valid(_flanking_badge_label):
		_flanking_badge_label.pixel_size = 0.0082 * cell_size
		_flanking_badge_label.position = Vector3(
			0.0,
			0.0,
			0.008 * cell_size
		)
	if is_instance_valid(_hp_bar_root):
		_hp_bar_root.position = Vector3(0.0, 0.34 * cell_size, 0.0)
		_update_health_bar_visual()


func _ensure_health_bar() -> void:
	if _overlay_root == null or not is_instance_valid(_overlay_root):
		return
	if (
		is_instance_valid(_hp_bar_root)
		and is_instance_valid(_hp_bar_mesh)
		and is_instance_valid(_hp_bar_label)
	):
		return

	_hp_bar_root = _overlay_root.get_node_or_null("HealthBar") as Node3D
	if _hp_bar_root == null:
		_hp_bar_root = Node3D.new()
		_hp_bar_root.name = "HealthBar"
		_overlay_root.add_child(_hp_bar_root)

	# Remove the old two-billboard implementation if this scene survives a
	# script reload. Two independently billboarded quads drift apart when the
	# camera rotates because their local offsets are not billboarded together.
	for legacy_name: String in ["Background", "Fill"]:
		var legacy := _hp_bar_root.get_node_or_null(legacy_name)
		if legacy != null:
			_hp_bar_root.remove_child(legacy)
			legacy.queue_free()

	_hp_bar_mesh = _hp_bar_root.get_node_or_null("Bar") as MeshInstance3D
	if _hp_bar_mesh == null:
		_hp_bar_mesh = MeshInstance3D.new()
		_hp_bar_mesh.name = "Bar"
		_hp_bar_mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_hp_bar_root.add_child(_hp_bar_mesh)

	_hp_bar_material = _hp_bar_mesh.material_override as StandardMaterial3D
	if _hp_bar_material == null:
		_hp_bar_material = StandardMaterial3D.new()
		_hp_bar_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
		)
		_hp_bar_material.billboard_mode = (
			BaseMaterial3D.BILLBOARD_ENABLED
		)
		_hp_bar_material.vertex_color_use_as_albedo = true
		_hp_bar_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hp_bar_material.transparency = (
			BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		_hp_bar_mesh.material_override = _hp_bar_material

	_hp_bar_label = _hp_bar_root.get_node_or_null("Percent") as Label3D
	if _hp_bar_label == null:
		_hp_bar_label = Label3D.new()
		_hp_bar_label.name = "Percent"
		_hp_bar_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hp_bar_label.fixed_size = false
		_hp_bar_label.font_size = 22
		_hp_bar_label.outline_size = 7
		_hp_bar_label.modulate = Color.WHITE
		_hp_bar_root.add_child(_hp_bar_label)

	_update_health_bar_visual()


func set_player_hit_points(current_hp: int, max_hp: int) -> void:
	_player_hp_current = current_hp
	_player_hp_max = maxi(0, max_hp)
	_hp_bar_show_percentage = true
	_ensure_token_overlay()
	_ensure_health_bar()
	_update_health_bar_visual()


func set_master_hit_points(current_hp: int, max_hp: int) -> void:
	_player_hp_current = current_hp
	_player_hp_max = maxi(0, max_hp)
	_hp_bar_show_percentage = false
	_ensure_token_overlay()
	_ensure_health_bar()
	_update_health_bar_visual()


func clear_player_hit_points() -> void:
	_player_hp_current = 0
	_player_hp_max = 0
	_hp_bar_show_percentage = true
	if is_instance_valid(_hp_bar_root):
		_hp_bar_root.visible = false


func clear_master_hit_points() -> void:
	_player_hp_current = 0
	_player_hp_max = 0
	_hp_bar_show_percentage = false
	if is_instance_valid(_hp_bar_root):
		_hp_bar_root.visible = false


func get_player_hit_points() -> Dictionary:
	return {
		"current": _player_hp_current,
		"max": _player_hp_max,
	}


func _update_health_bar_visual() -> void:
	if not is_instance_valid(_hp_bar_root):
		return
	if _player_hp_max <= 0:
		_hp_bar_root.visible = false
		return

	_hp_bar_root.visible = true
	var clamped_current := clampi(
		_player_hp_current,
		0,
		_player_hp_max
	)
	var ratio := clampf(
		float(clamped_current) / float(_player_hp_max),
		0.0,
		1.0
	)
	var width := maxf(1.45, _footprint_cells * 1.05) * cell_size
	var height := 0.14 * cell_size

	if is_instance_valid(_hp_bar_mesh):
		# Black total HP and red remaining HP are vertices of ONE billboarded
		# mesh. They therefore rotate, scale and translate as one object from
		# every camera direction.
		var bar_mesh := ImmediateMesh.new()
		bar_mesh.surface_begin(
			Mesh.PRIMITIVE_TRIANGLES,
			_hp_bar_material
		)

		var half_width := width * 0.5
		var half_height := height * 0.5
		var black := Color(0.015, 0.015, 0.02, 1.0)
		_add_hp_bar_quad(
			bar_mesh,
			-half_width,
			half_width,
			-half_height,
			half_height,
			0.0,
			black
		)

		if ratio > 0.0:
			var inset := height * 0.12
			var inner_left := -half_width + inset
			var inner_right_max := half_width - inset
			var inner_width := maxf(
				0.0,
				inner_right_max - inner_left
			)
			var red_right := inner_left + inner_width * ratio
			var red := Color(0.92, 0.08, 0.08, 1.0)
			_add_hp_bar_quad(
				bar_mesh,
				inner_left,
				red_right,
				-half_height + inset,
				half_height - inset,
				0.002 * cell_size,
				red
			)

		bar_mesh.surface_end()
		_hp_bar_mesh.mesh = bar_mesh

	if is_instance_valid(_hp_bar_label):
		_hp_bar_label.text = "%d%%" % roundi(ratio * 100.0)
		_hp_bar_label.pixel_size = 0.008 * cell_size
		_hp_bar_label.position = Vector3(
			0.0,
			0.12 * cell_size,
			0.008 * cell_size
		)
		_hp_bar_label.visible = _hp_bar_show_percentage


func _add_hp_bar_quad(
	mesh: ImmediateMesh,
	left: float,
	right: float,
	bottom: float,
	top: float,
	z_offset: float,
	color: Color
) -> void:
	if mesh == null or right <= left or top <= bottom:
		return

	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(left, bottom, z_offset))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(right, bottom, z_offset))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(right, top, z_offset))

	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(left, bottom, z_offset))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(right, top, z_offset))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(left, top, z_offset))


func _update_status_overlay() -> void:
	_ensure_token_overlay()
	# Conditions are rendered by the shared 2D tactical badge together with
	# derived states such as Affiancato. Keep the legacy 3D label disabled so
	# names/HP/conditions never overlap or duplicate one another.
	if is_instance_valid(_status_label):
		_status_label.text = ""
		_status_label.visible = false



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


func _default_reach_feet() -> float:
	# 5 ft per Medium o inferiore, poi +5 ft per ogni cella di footprint.
	return maxf(5.0, _footprint_cells * 5.0)


func set_reach_feet(value: float, overridden: bool = true) -> void:
	if value <= 0.0:
		reset_reach_to_default()
		return
	_reach_feet = clampf(value, 5.0, 1000.0)
	_reach_overridden = overridden


func reset_reach_to_default() -> void:
	_reach_overridden = false
	_reach_feet = _default_reach_feet()


func get_reach_feet() -> float:
	return _reach_feet


func is_reach_overridden() -> bool:
	return _reach_overridden


func get_size_name() -> String:
	return _size_name


func set_size_category(
	size_name: String,
	footprint_cells: float,
	update_default_reach: bool = false
) -> void:
	# Il nodo root sta al centro del collider: conserva la quota della base
	# quando la nuova forma ha un'altezza diversa.
	var base_y: float = (
		global_position.y
		- token_height_cells * cell_size * 0.5
	)

	_size_name = size_name
	_footprint_cells = maxf(footprint_cells, 0.5)
	if update_default_reach and not _reach_overridden:
		_reach_feet = _default_reach_feet()
	set_token_size(_footprint_cells)

	global_position.y = (
		base_y
		+ token_height_cells * cell_size * 0.5
	)


func get_appearance_state() -> Dictionary:
	return {
		"token_pack_id": get_token_pack_id(),
		"visual_asset": get_visual_asset_path(),
		"visual_native_footprint": _visual_native_footprint_cells,
		"visual_front_quarter_turns": get_visual_front_quarter_turns(),
		"display_name": get_display_name(),
		"party_id": get_party_id(),
		"conditions": get_conditions(),
		"size_name": _size_name,
		"footprint": _footprint_cells,
		"height_cells": token_height_cells,
		"reach_feet": _reach_feet,
		"reach_overridden": _reach_overridden
	}


func apply_appearance_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false

	var base_y: float = (
		global_position.y
		- token_height_cells * cell_size * 0.5
	)

	set_token_pack_id(String(state.get("token_pack_id", "")))

	var visual_asset: String = String(
		state.get("visual_asset", "")
	).strip_edges()
	if not visual_asset.is_empty():
		var native_footprint := maxf(
			float(
				state.get(
					"visual_native_footprint",
					state.get("footprint", _footprint_cells)
				)
			),
			0.5
		)
		if not set_visual_asset(visual_asset, native_footprint):
			return false
	else:
		_clear_imported_visual()
		_set_procedural_visuals_visible(true)
		visual_asset_path = ""
		_loaded_visual_asset_path = ""
		_uses_manifest_default = false
		_visual_native_footprint_cells = 1.0

	set_visual_front_quarter_turns(
		int(state.get("visual_front_quarter_turns", 0))
	)
	token_height_cells = maxf(
		float(state.get("height_cells", token_height_cells)),
		0.1
	)
	_size_name = String(state.get("size_name", _size_name))
	_footprint_cells = maxf(
		float(state.get("footprint", _footprint_cells)),
		0.5
	)
	set_token_size(_footprint_cells)

	_reach_feet = maxf(
		float(state.get("reach_feet", _default_reach_feet())),
		5.0
	)
	_reach_overridden = bool(state.get("reach_overridden", false))
	set_display_name(String(state.get("display_name", token_display_name)))
	set_party_id(String(state.get("party_id", party_id)))
	set_conditions(state.get("conditions", _conditions))
	global_position.y = (
		base_y
		+ token_height_cells * cell_size * 0.5
	)
	return true


func push_transformation_state() -> void:
	_transformation_history.append(get_appearance_state())
	while _transformation_history.size() > MAX_TRANSFORMATION_HISTORY:
		_transformation_history.remove_at(0)


func has_previous_transformation() -> bool:
	return not _transformation_history.is_empty()


func restore_previous_transformation() -> bool:
	if _transformation_history.is_empty():
		return false
	var previous: Dictionary = _transformation_history.pop_back()
	return apply_appearance_state(previous)


func get_transformation_history() -> Array:
	return _transformation_history.duplicate(true)


func set_transformation_history(value: Variant) -> void:
	_transformation_history.clear()
	if not value is Array:
		return
	var history_values: Array = value as Array
	for item_value: Variant in history_values:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = (item_value as Dictionary).duplicate(true)
		var visual_asset: String = String(
			item.get("visual_asset", "")
		).strip_edges()
		if not _is_supported_token_visual_path(visual_asset):
			continue
		var history_pack_id := String(
			item.get("token_pack_id", "")
		).strip_edges()
		if history_pack_id.length() > 96:
			continue
		_transformation_history.append(item)
		if _transformation_history.size() >= MAX_TRANSFORMATION_HISTORY:
			break


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
	# Il centro dei cubi della VolumetricGrid e' a n + 0.5 celle.
	# I footprint dispari (1x1, 3x3, ...) devono quindi stare sui centri
	# delle celle; quelli pari (2x2, 4x4, ...) sugli incroci, cosi' i bordi
	# del token coincidono sempre con le linee della griglia.
	global_position.x = _snap_coordinate(global_position.x)
	global_position.z = _snap_coordinate(global_position.z)


func _grid_snap_offset_cells() -> float:
	var rounded_footprint := roundi(_footprint_cells)
	if is_equal_approx(_footprint_cells, float(rounded_footprint)):
		return 0.5 if abs(rounded_footprint) % 2 == 1 else 0.0

	# Tiny e altri footprint frazionari restano centrati dentro una cella,
	# invece di finire su una linea/intersezione.
	return 0.5


func _snap_coordinate(value: float) -> float:
	var safe_cell_size := maxf(cell_size, 0.001)
	var offset_cells := _grid_snap_offset_cells()
	return (
		(round(value / safe_cell_size - offset_cells) + offset_cells)
		* safe_cell_size
	)


func snap_destination(point: Vector3, _support: Node3D = null) -> Vector3:
	var snapped_point := point
	snapped_point.x = _snap_coordinate(snapped_point.x)
	snapped_point.z = _snap_coordinate(snapped_point.z)
	return snapped_point


func _is_supported_token_visual_path(path: String) -> bool:
	var clean := path.strip_edges()
	if clean.is_empty():
		return true
	if clean.begins_with("res://assets/tokens/"):
		return not clean.contains("..")
	if clean.begins_with("res://remote_tokens/"):
		return (
			not clean.contains("..")
			and clean.ends_with("_visual.res")
		)
	return false
