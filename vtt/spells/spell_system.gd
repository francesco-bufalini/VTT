extends Node

const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const WallGeometry = preload("res://vtt/spells/wall_geometry.gd")
const SpellTargetOverlay2D = preload("res://vtt/spells/spell_target_overlay_2d.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const ReachGeometry = preload("res://vtt/flanking_system.gd")
const TargetRules = preload("res://vtt/spells/spell_target_rules.gd")
const TargetInput = preload("res://vtt/spells/spell_target_input.gd")
const ALL_COLLISION_LAYERS := 0xFFFFFFFF
const AOE_PICK_LAYER := 1 << 20
const TOKEN_PICK_COLLISION_MASK := ALL_COLLISION_LAYERS & ~AOE_PICK_LAYER
const ACTIVATABLE_TARGET_MODES := [
	"self_token",
	"self_emanation",
	"teleport_self",
	"token_then_point",
	"token_then_token",
	"token_then_multi_token",
	"token_then_multi_point",
	"summon",
	"transform_self",
	"token_then_transform",
	"token_then_multi_transform",
	"resize_token",
	"token_then_chain",
	"token_then_direction",
	"wall_design"
]

var board_root: Node3D
var ui_root: CanvasLayer
var panel: PanelContainer
var search_input: LineEdit
var search_results: ItemList
var class_tree: Tree
var spell_title: Label
var spell_meta: Label
var spell_description: RichTextLabel
var slot_row: HBoxContainer
var slot_selector: OptionButton
var activate_button: Button
var instruction_label: Label
var _overlay_2d: Control
var wall_mode_menu: PopupMenu
var wall_orientation_menu: PopupMenu
var summon_count_menu: PopupMenu
var saving_throw_dialog: ConfirmationDialog

var _selected_spell_id: String = ""
var _selected_spell_data: Dictionary = {}
var _pending_spell_id: String = ""
var _pending_spell_data: Dictionary = {}
var _targeting_phase: String = ""
var _pending_caster: Node3D = null
var _directional_pitch_degrees: int = 0
var _selected_slot_level: int = 0
var _pending_targets: Array[Node3D] = []
var _committed_targets: Array[Node3D] = []
var _pending_target_points: Array[Vector3] = []
var _pending_target_history: Array[Dictionary] = []
var _pending_chain_primary: Node3D = null
var _post_cast_cleanup_pending: bool = false
var _summon_total_count: int = 1
var _summon_created_count: int = 0
var _transformation_dialog_targets: Array[Node3D] = []
var _transformation_dialog_index: int = 0
var _saving_throw_targets: Array[Node3D] = []
var _saving_throw_index: int = 0
var _saving_throw_caster_origin: Vector3 = Vector3.ZERO
var _saving_throw_undo_recorded: bool = false
var _restore_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _wall_mode: String = ""
var _wall_points: Array[Vector3] = []
var _wall_center: Vector3 = Vector3.ZERO
var _wall_radius_world: float = 0.0
var _wall_start_angle: float = 0.0
var _wall_sweep: float = 0.0
var _wall_previous_cursor_angle: float = 0.0
var _wall_damage_side: int = 0
var _wall_orientation: String = ""


var _remote_owner := ""
var _remote_caster: Node3D
var _remote_input_active := false
var _remote_starting := false
var _remote_pick_token: Node3D
var _remote_pick_point: Dictionary = {}
var _remote_outcome := ""
var _remote_instruction := ""
var _remote_mouse_restore := Input.MOUSE_MODE_VISIBLE
var _remote_ui_restore := false

func setup(root: Node3D) -> void:
	board_root = root
	call_deferred("_initialize")


func _process(_delta: float) -> void:
	if not _remote_owner.is_empty() and is_targeting():
		return
	# Previews are cleared synchronously by _reset_cast_state(). Repeating
	# that cleanup every rendered frame while idle does redundant scene-tree
	# work (notably on geometry-heavy encounter maps).
	if _pending_spell_id.is_empty():
		return
	_update_spell_preview()


func _initialize() -> void:
	if board_root == null or not is_instance_valid(board_root):
		return

	ui_root = board_root.get_node_or_null("UI") as CanvasLayer
	if ui_root == null:
		push_error("SpellSystem: UI CanvasLayer non trovato.")
		return

	_build_panel()
	_build_instruction_label()
	_overlay_2d = SpellTargetOverlay2D.new()
	ui_root.add_child(_overlay_2d)
	_overlay_2d.call(
		"setup", board_root, self, _measurement_tool(),
		board_root.get_node_or_null("Camera3D")
	)
	_build_saving_throw_dialog()
	_build_summon_count_menu()
	_build_wall_mode_menu()
	_build_wall_orientation_menu()
	_populate_class_tree()
	_refresh_search_results("")
	_select_spell("burning_hands")


func _build_summon_count_menu() -> void:
	summon_count_menu = PopupMenu.new()
	summon_count_menu.name = "SummonCountMenu"
	summon_count_menu.hide_on_item_selection = false
	summon_count_menu.id_pressed.connect(_on_summon_count_selected)
	summon_count_menu.popup_hide.connect(_on_summon_count_menu_hidden)
	ui_root.add_child(summon_count_menu)


func _on_summon_count_menu_hidden() -> void:
	if (
		_targeting_phase == "summon_count"
		and not _pending_spell_id.is_empty()
	):
		call_deferred("_cancel_pending_cast")


func _build_wall_mode_menu() -> void:
	wall_mode_menu = PopupMenu.new()
	wall_mode_menu.name = "WallModeMenu"
	wall_mode_menu.id_pressed.connect(_on_wall_mode_selected)
	ui_root.add_child(wall_mode_menu)


func _build_wall_orientation_menu() -> void:
	wall_orientation_menu = PopupMenu.new()
	wall_orientation_menu.name = "WallOrientationMenu"
	wall_orientation_menu.add_item("Intradosso", 0)
	wall_orientation_menu.add_item("Estradosso", 1)
	wall_orientation_menu.id_pressed.connect(
		_on_wall_orientation_selected
	)
	ui_root.add_child(wall_orientation_menu)


func _show_wall_orientation_menu(spell_data: Dictionary) -> void:
	_targeting_phase = "wall_orientation"
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var orientation_help: String = (
		"Intradosso = verso il centro; Estradosso = verso l'esterno."
		if _wall_mode == "circle"
		else "Intradosso = lato sinistro rispetto al verso di disegno; Estradosso = lato destro."
	)
	_set_instruction(
		"%s: scegli Intradosso o Estradosso. %s"
		% [
			String(spell_data.get("name", "Muro")),
			orientation_help
		]
	)

	var window_size: Vector2i = Vector2i(get_tree().root.get_visible_rect().size)
	DialogLayout.popup_menu(
		wall_orientation_menu, (window_size - Vector2i(180, 60)) / 2
	)


func _on_wall_orientation_selected(id: int) -> void:
	_wall_orientation = "intradosso" if id == 0 else "estradosso"
	_wall_damage_side = _wall_orientation_side()
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var spell_data: Dictionary = _pending_spell()
	_commit_wall_path(spell_data)


func _wall_orientation_side() -> int:
	if _wall_mode != "circle":
		# Per un percorso lineare, l'intradosso è il lato sinistro
		# rispetto al verso con cui il muro è stato disegnato.
		return 1 if _wall_orientation == "intradosso" else -1

	var positive_sweep: bool = _wall_sweep >= 0.0
	if _wall_orientation == "intradosso":
		return 1 if positive_sweep else -1
	return -1 if positive_sweep else 1


func _show_wall_mode_menu(spell_data: Dictionary) -> void:
	wall_mode_menu.clear()
	var modes_value: Variant = spell_data.get("wall_modes", ["polyline"])
	if not modes_value is Array:
		_cancel_pending_cast()
		return

	var modes: Array = modes_value
	if modes.size() == 1:
		_begin_wall_mode(String(modes[0]))
		return

	for mode_value: Variant in modes:
		var mode: String = String(mode_value)
		var label: String = mode
		match mode:
			"polyline":
				label = "Muro lineare / segmentato"
			"circle":
				label = "Muro circolare / arco"
			"globe":
				label = "Globo"
			"dome":
				label = "Cupola emisferica"
		var item_index: int = wall_mode_menu.item_count
		wall_mode_menu.add_item(label, item_index)
		wall_mode_menu.set_item_metadata(item_index, mode)

	_targeting_phase = "wall_mode"
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var window_size: Vector2i = Vector2i(get_tree().root.get_visible_rect().size)
	DialogLayout.popup_menu(
		wall_mode_menu, (window_size - Vector2i(240, 80)) / 2
	)


func _on_wall_mode_selected(id: int) -> void:
	if (
		wall_mode_menu == null
		or id < 0
		or id >= wall_mode_menu.item_count
	):
		return
	var mode: String = String(
		wall_mode_menu.get_item_metadata(id)
	)
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_begin_wall_mode(mode)


func _begin_wall_mode(mode: String) -> void:
	_wall_mode = mode
	_wall_points.clear()
	_wall_center = Vector3.ZERO
	_wall_radius_world = 0.0
	_wall_start_angle = 0.0
	_wall_sweep = 0.0
	_wall_previous_cursor_angle = 0.0
	_wall_damage_side = 0
	_wall_orientation = ""
	_hide_wall_preview()

	var spell_data: Dictionary = _pending_spell()
	match mode:
		"polyline":
			_targeting_phase = "wall_start"
			_set_instruction(
				"%s: scegli il punto iniziale del muro entro %d ft."
				% [
					String(spell_data.get("name", "Muro")),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		"circle", "globe", "dome":
			_targeting_phase = "wall_center"
			_set_instruction(
				"%s: scegli il centro entro %d ft."
				% [
					String(spell_data.get("name", "Muro")),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		_:
			_cancel_pending_cast()


func is_panel_open() -> bool:
	return panel != null and panel.visible


func is_targeting() -> bool:
	return not _pending_spell_id.is_empty()


func has_post_cast_cleanup() -> bool:
	return _post_cast_cleanup_pending


func has_runtime_spell_effect(
	spell_id: String,
	spell_name: String = "",
	source: String = ""
) -> bool:
	return not _runtime_spell_reference(spell_id, spell_name, source).is_empty()


func activate_spell_from_caster(
	spell_id: String,
	caster: Node3D,
	spell_name: String = "",
	source: String = "",
	cast_slot_level: int = -1,
	caster_context: Dictionary = {}
) -> bool:
	if not _remote_input_active and not is_targeting():
		_remote_owner = ""
		_remote_caster = null
	if spell_id.is_empty() or caster == null or not is_instance_valid(caster):
		return false

	# Character sheets can contain entries saved before the runtime area
	# catalogue was regenerated. Resolve through the same all_spells() data
	# used by the normal spell browser so sheet casting and browser casting
	# always agree on VTT support.
	var spell_data: Dictionary = _runtime_spell_reference(
		spell_id,
		spell_name,
		source
	)
	if spell_data.is_empty():
		return false
	# Preserve the class/origin-specific ability and save DC for the whole
	# targeting lifecycle instead of falling back to the primary class.
	for field: String in ["spellcasting_ability", "spell_attack_bonus", "spell_save_dc", "source_class"]:
		if caster_context.has(field):
			spell_data["caster_" + field] = caster_context[field]

	var resolved_spell_id: String = String(
		spell_data.get("id", spell_id)
	)
	_selected_spell_id = resolved_spell_id
	_selected_spell_data = spell_data.duplicate(true)
	_configure_slot_selector(spell_data)
	var base_level: int = int(spell_data.get("level", 0))
	if cast_slot_level >= 0:
		_selected_slot_level = (
			clampi(cast_slot_level, base_level, 9) if base_level > 0 else 0
		)
	_activate_selected_spell()

	if (
		_pending_spell_id != resolved_spell_id
		or _targeting_phase != "caster"
	):
		return false

	_begin_cast_with_caster(caster, _pending_spell())
	return true


func _runtime_spell_reference(
	spell_id: String,
	spell_name: String = "",
	source: String = ""
) -> Dictionary:
	var direct: Dictionary = SpellCatalog.catalog_spell(spell_id)
	if (
		not direct.is_empty()
		and SpellCatalog.is_runtime_usable(direct)
	):
		return direct

	var normalized_name: String = spell_name.strip_edges().to_lower()
	var normalized_source: String = source.strip_edges().to_lower()
	for candidate: Dictionary in SpellCatalog.all_spells():
		var candidate_id: String = String(candidate.get("id", ""))
		var id_match: bool = candidate_id == spell_id
		var name_match: bool = (
			not normalized_name.is_empty()
			and String(candidate.get("name", "")).strip_edges().to_lower()
			== normalized_name
		)
		var source_match: bool = (
			normalized_source.is_empty()
			or String(candidate.get("source", "")).strip_edges().to_lower()
			== normalized_source
		)
		if (
			(id_match or (name_match and source_match))
			and SpellCatalog.is_runtime_usable(candidate)
		):
			return candidate.duplicate(true)

	return {}


func _set_spell_affected_targets(
	tokens: Array,
	active: bool = true
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if (
		measurement_tool != null
		and measurement_tool.has_method(
			"set_spell_affected_token_highlight"
		)
	):
		measurement_tool.call(
			"set_spell_affected_token_highlight",
			tokens,
			active
		)
		return
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("set_affected_token_highlight")
	):
		board_root.call("set_affected_token_highlight", tokens)


func _set_spell_geometry_highlight(
	start: Vector3,
	end: Vector3,
	spell_data: Dictionary,
	caster: Node3D = null
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if (
		measurement_tool != null
		and measurement_tool.has_method("set_spell_affected_geometry")
	):
		measurement_tool.call(
			"set_spell_affected_geometry",
			start,
			end,
			String(spell_data.get("aoe_shape", "sphere")),
			_spell_style(spell_data),
			_spell_line_width_world(spell_data),
			true
		)
		return

	_set_spell_affected_targets(
		_spell_targets_in_geometry(
			start,
			end,
			spell_data,
			caster
		),
		true
	)


func dismiss_post_cast_visuals() -> bool:
	if not _post_cast_cleanup_pending:
		return false

	_post_cast_cleanup_pending = false
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		if measurement_tool.has_method("clear_post_cast_spell_visuals"):
			measurement_tool.call("clear_post_cast_spell_visuals")
		elif measurement_tool.has_method("clear_transient_spell_aoes"):
			measurement_tool.call("clear_transient_spell_aoes")
		if measurement_tool.has_method(
			"set_spell_affected_token_highlight"
		):
			measurement_tool.call(
				"set_spell_affected_token_highlight",
				[],
				false
			)
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("set_affected_token_highlight")
	):
		board_root.call("set_affected_token_highlight", [])
	return true


func dismiss_post_cast_visual_at_screen(
	screen_position: Vector2
) -> bool:
	var measurement_tool: Node = _measurement_tool()
	if (
		measurement_tool == null
		or not measurement_tool.has_method(
			"remove_post_cast_spell_visual_at_screen"
		)
	):
		return false

	var removed: bool = false
	if _is_2d_view() and _overlay_2d != null:
		removed = bool(_overlay_2d.call("remove_area_at_screen", screen_position))
	if not removed:
		removed = bool(
			measurement_tool.call(
				"remove_post_cast_spell_visual_at_screen",
				screen_position
			)
		)
	if not removed:
		return false

	# The red preview belongs to the last selected geometry. Clear it even
	# when other held areas remain; their own grid highlighting is independent.
	_set_spell_affected_targets([], false)

	var has_remaining: bool = false
	if measurement_tool.has_method("has_post_cast_spell_visuals"):
		has_remaining = bool(
			measurement_tool.call("has_post_cast_spell_visuals")
		)
	_post_cast_cleanup_pending = has_remaining

	if not has_remaining:
		if measurement_tool.has_method(
			"set_spell_affected_token_highlight"
		):
			measurement_tool.call(
				"set_spell_affected_token_highlight",
				[],
				false
			)
		if (
			board_root != null
			and is_instance_valid(board_root)
			and board_root.has_method("set_affected_token_highlight")
		):
			board_root.call("set_affected_token_highlight", [])

	return true


func _pending_spell() -> Dictionary:
	if _pending_spell_id.is_empty():
		return {}
	if (
		not _pending_spell_data.is_empty()
		and String(_pending_spell_data.get("id", "")) == _pending_spell_id
	):
		return _pending_spell_data

	# Compatibility fallback for casts started by older code paths.
	var fallback: Dictionary = SpellCatalog.spell(_pending_spell_id)
	if not fallback.is_empty():
		_pending_spell_data = fallback.duplicate(true)
	return _pending_spell_data


func toggle_panel() -> void:
	if panel == null:
		return
	if panel.visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if panel == null:
		return

	_cancel_pending_cast(false)
	_restore_mouse_mode = Input.mouse_mode
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	search_input.grab_focus()


func close_panel() -> void:
	if panel == null:
		return

	panel.hide()
	_cancel_pending_cast(false)
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = _restore_mouse_mode


func handle_input(event: InputEvent) -> bool:
	if not _remote_owner.is_empty() and not _remote_input_active and is_targeting():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_pending_cast(false)
			_return_control_to_camera()
			return true
		return false
	if _pending_spell_id.is_empty():
		return false
	if _targeting_phase in [
		"saving_throw",
		"summon_token_dialog",
		"transform_token_dialog",
		"resize_token_dialog"
	]:
		return false

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.ctrl_pressed and key_event.keycode == KEY_Z:
				if _targeting_phase.begins_with("wall_"):
					_undo_wall_step()
					return true
				return false

			if key_event.keycode == KEY_ESCAPE:
				_cancel_pending_cast()
				return true

			if (
				_targeting_phase == "multi_target_tokens"
				and key_event.keycode in [KEY_BACKSPACE, KEY_DELETE]
			):
				_undo_last_multi_target_selection()
				return true

			if (
				_targeting_phase == "wall_segment"
				and key_event.keycode == KEY_ENTER
				and _wall_points.size() >= 2
			):
				_prepare_or_commit_wall()
				return true

			if (
				_targeting_phase == "chain_secondary"
				and key_event.keycode == KEY_ENTER
				and _pending_chain_primary != null
				and is_instance_valid(_pending_chain_primary)
			):
				_cast_chain_lightning(
					_pending_caster,
					_pending_chain_primary,
					_pending_targets,
					_pending_spell()
				)
				_finish_cast()
				return true

			if (
				_targeting_phase == "teleport_passengers"
				and key_event.keycode == KEY_ENTER
			):
				_begin_teleport_destination(
					_pending_spell()
				)
				return true

			if (
				_targeting_phase == "transform_multi_targets"
				and key_event.keycode == KEY_ENTER
				and not _pending_targets.is_empty()
			):
				_begin_token_transformations(
					_pending_targets.duplicate(),
					_pending_spell()
				)
				return true

			var pending_data: Dictionary = SpellCatalog.spell(
				_pending_spell_id
			)
			if (
				_targeting_phase == "caster"
				and bool(pending_data.get("allow_pitch", false))
				and key_event.keycode in [KEY_UP, KEY_DOWN]
			):
				_adjust_directional_pitch(
					45 if key_event.keycode == KEY_UP else -45
				)
				return true

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed:
			return false

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_pending_cast()
			return true

		var can_adjust_point_depth: bool = (
			_targeting_phase in [
				"point",
				"direction_point",
				"multi_target_points",
				"summon_point"
			]
		)
		if _targeting_phase in ["target_token", "multi_target_tokens"]:
			var point_target_spell: Dictionary = SpellCatalog.spell(
				_pending_spell_id
			)
			can_adjust_point_depth = bool(
				point_target_spell.get("allow_point_target", false)
			)
		if can_adjust_point_depth:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_point_depth(-1.0)
				return true
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_point_depth(1.0)
				return true

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return false

		var screen_position: Vector2 = mouse_event.position
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			screen_position = get_viewport().get_visible_rect().size * 0.5

		return _confirm_targeting_selection(screen_position)

	return false


# A logical selection action works with either screen-projected candidates
# or token/world-point input already resolved by a remote mobile client.
# Keep phase-specific side effects explicit: spells, walls and teleports
# require different transitions and must not share a generic commit handler.
func _confirm_targeting_selection(screen_position: Vector2) -> bool:
	match _targeting_phase:
		"caster":
			_try_select_caster(screen_position)
			return true
		"point":
			_try_select_point(screen_position)
			return true
		"target_token":
			_try_select_target_token(screen_position)
			return true
		"teleport_passengers":
			_try_select_teleport_passenger(screen_position)
			return true
		"teleport_destination":
			_try_select_teleport_destination(screen_position)
			return true
		"multi_target_tokens":
			_try_select_multi_target(screen_position)
			return true
		"multi_target_points":
			_try_select_multi_point(screen_position)
			return true
		"summon_point":
			_try_select_summon_point(screen_position)
			return true
		"transform_target":
			_try_select_transformation_target(screen_position)
			return true
		"transform_multi_targets":
			_try_select_transformation_multi_target(screen_position)
			return true
		"resize_target":
			_try_select_resize_target(screen_position)
			return true
		"chain_primary":
			_try_select_chain_primary(screen_position)
			return true
		"chain_secondary":
			_try_select_chain_secondary(screen_position)
			return true
		"direction_point":
			_try_select_direction_point(screen_position)
			return true
		"wall_start":
			_try_wall_start(screen_position)
			return true
		"wall_segment":
			_try_wall_segment(screen_position)
			return true
		"wall_center":
			_try_wall_center(screen_position)
			return true
		"wall_radius":
			_try_wall_radius(screen_position)
			return true
		"wall_arc_start":
			_try_wall_arc_start(screen_position)
			return true
		"wall_arc_end":
			_try_wall_arc_end(screen_position)
			return true
	return false

func _summon_count_choices(spell_data: Dictionary) -> Array[int]:
	var choices: Array[int] = []
	var base_level: int = int(spell_data.get("level", 0))
	var slot_delta: int = maxi(
		0,
		_selected_slot_level - base_level
	)
	var per_slot: int = maxi(
		int(spell_data.get("summon_count_per_slot_above_base", 0)),
		0
	)

	var multiplier: int = 1
	var multiplier_rules_value: Variant = spell_data.get(
		"summon_count_multiplier_rules",
		[]
	)
	if multiplier_rules_value is Array:
		for rule_value: Variant in multiplier_rules_value:
			if not rule_value is Dictionary:
				continue
			var rule: Dictionary = rule_value as Dictionary
			var min_slot: int = int(rule.get("min_slot", 0))
			var max_slot: int = int(rule.get("max_slot", min_slot))
			if (
				_selected_slot_level >= min_slot
				and _selected_slot_level <= max_slot
			):
				multiplier = maxi(
					multiplier,
					int(rule.get("multiplier", 1))
				)

	var options_value: Variant = spell_data.get("summon_count_options", [])
	if options_value is Array:
		for option_value: Variant in options_value:
			var option_count: int = int(option_value) * multiplier
			if option_count > 0 and not (option_count in choices):
				choices.append(option_count)
	if not choices.is_empty():
		choices.sort()
		return choices

	var minimum: int = int(spell_data.get("summon_count_min", 0))
	var maximum: int = int(spell_data.get("summon_count_max", 0))
	if minimum > 0 and maximum >= minimum:
		var maxima_value: Variant = spell_data.get(
			"summon_count_max_by_slot",
			{}
		)
		var slot_key: String = str(_selected_slot_level)
		if (
			maxima_value is Dictionary
			and (maxima_value as Dictionary).has(slot_key)
		):
			maximum = int(
				(maxima_value as Dictionary).get(slot_key, maximum)
			)
		else:
			maximum += per_slot * slot_delta
		for count: int in range(minimum, maximum + 1):
			choices.append(count)
		return choices

	var fixed_count: int = maxi(
		int(spell_data.get("summon_count", 1)),
		1
	)
	fixed_count += per_slot * slot_delta
	choices.append(fixed_count)
	return choices


func _begin_summon_count_or_point(spell_data: Dictionary) -> void:
	var choices: Array[int] = _summon_count_choices(spell_data)
	if choices.is_empty():
		choices.append(1)

	if choices.size() == 1:
		_summon_total_count = choices[0]
		_begin_summon_point_selection(spell_data)
		return

	summon_count_menu.clear()
	for index: int in range(choices.size()):
		var count: int = choices[index]
		var label: String = (
			"1 creatura" if count == 1 else "%d creature" % count
		)
		summon_count_menu.add_item(label, index)
		summon_count_menu.set_item_metadata(index, count)

	_targeting_phase = "summon_count"
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_instruction(
		"%s: scegli quante creature evocare."
		% String(spell_data.get("name", "Evocazione"))
	)

	var window_size: Vector2i = Vector2i(get_tree().root.get_visible_rect().size)
	DialogLayout.popup_menu(
		summon_count_menu, (window_size - Vector2i(180, 80)) / 2
	)


func _on_summon_count_selected(id: int) -> void:
	if (
		summon_count_menu == null
		or id < 0
		or id >= summon_count_menu.item_count
	):
		return

	_summon_total_count = maxi(
		int(summon_count_menu.get_item_metadata(id)),
		1
	)
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_begin_summon_point_selection(_pending_spell())
	summon_count_menu.hide()


func _begin_summon_point_selection(spell_data: Dictionary) -> void:
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	_targeting_phase = "summon_point"
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hide_spell_preview()
	_set_instruction(
		"%s: scegli il punto per la creatura %d/%d entro %d ft · Esc per annullare"
		% [
			String(spell_data.get("name", "Evocazione")),
			_summon_created_count + 1,
			_summon_total_count,
			int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
		]
	)


func _try_select_summon_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var point_spell: Dictionary = spell_data.duplicate(true)
	if bool(spell_data.get("summon_requires_ground", false)):
		point_spell["requires_ground"] = true

	var point_data: Dictionary = _point_target_data(
		screen_position,
		point_spell
	)
	if not bool(point_data.get("valid", false)):
		if bool(point_data.get("out_of_range", false)):
			_set_instruction(
				"Punto fuori range: %d ft / %d ft."
				% [
					int(point_data.get("distance_feet", 0)),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		elif bool(spell_data.get("summon_requires_ground", false)):
			_set_instruction(
				"Scegli un punto valido sul terreno entro gittata."
			)
		else:
			_set_instruction(
				"Scegli una superficie o una cella valida entro gittata."
			)
		return

	var summon_point: Vector3 = point_data.get(
		"point",
		Vector3.ZERO
	)
	if _point_target_already_selected(summon_point):
		_set_instruction(
			"Questo punto è già usato da un'altra creatura evocata."
		)
		return
	_pending_target_points.append(summon_point)

	_targeting_phase = "summon_token_dialog"
	_hide_spell_preview()
	_hide_spell_range_preview()
	_set_instruction(
		"%s: configura il token evocato %d/%d."
		% [
			String(spell_data.get("name", "Evocazione")),
			_summon_created_count + 1,
			_summon_total_count
		]
	)

	if not board_root.has_method("open_token_generation_at"):
		_cancel_pending_cast()
		return

	board_root.call(
		"open_token_generation_at",
		summon_point,
		Callable(self, "_on_summon_token_created"),
		Callable(self, "_on_summon_token_generation_canceled"),
		not bool(point_data.get("in_air", false))
	)


func _on_summon_token_created(created_token: CharacterBody3D) -> void:
	if _pending_spell_id.is_empty():
		return
	if created_token == null or not is_instance_valid(created_token):
		_cancel_pending_cast()
		return

	_summon_created_count += 1
	if _summon_created_count >= _summon_total_count:
		_finish_cast()
		return

	_begin_summon_point_selection(_pending_spell())


func _on_summon_token_generation_canceled() -> void:
	if not _pending_spell_id.is_empty():
		_cancel_pending_cast()


func _transformation_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var target: Node3D = _token_at_screen(screen_position)
	if target == null:
		return {"valid": false}

	var range_feet: float = _effective_spell_range_feet(
		spell_data,
		_pending_caster
	)
	var actual_distance_feet: float = _token_target_distance_feet(_pending_caster, target)
	if actual_distance_feet > range_feet + 0.001:
		return {
			"valid": false,
			"out_of_range": true,
			"target": target,
			"distance_feet": int(round(actual_distance_feet))
		}

	return {"valid": true, "target": target}


func _try_select_transformation_target(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _transformation_target_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		if bool(target_data.get("out_of_range", false)):
			_set_instruction(
				"Bersaglio fuori range: %d ft / %d ft."
				% [
					int(target_data.get("distance_feet", 0)),
					int(round(_effective_spell_range_feet(
						spell_data,
						_pending_caster
					)))
				]
			)
		else:
			_set_instruction("Seleziona un token valido da trasformare.")
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null:
		return
	_begin_token_transformations([target], spell_data)


func _try_select_transformation_multi_target(
	screen_position: Vector2
) -> void:
	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _transformation_target_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		_set_instruction("Seleziona un token valido entro gittata.")
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null:
		return
	if target in _pending_targets:
		_set_instruction("Questo bersaglio è già stato selezionato.")
		return

	_pending_targets.append(target)
	var maximum: int = maxi(
		int(spell_data.get("transform_max_targets", 0)),
		0
	)
	if maximum > 0 and _pending_targets.size() >= maximum:
		_begin_token_transformations(
			_pending_targets.duplicate(),
			spell_data
		)
		return
	_update_transformation_multi_instruction(spell_data)


func _update_transformation_multi_instruction(
	spell_data: Dictionary
) -> void:
	var maximum: int = maxi(
		int(spell_data.get("transform_max_targets", 0)),
		0
	)
	var maximum_label: String = (
		"/%d" % maximum if maximum > 0 else ""
	)
	_set_instruction(
		"%s: scegli i token da trasformare %d%s · Invio per confermare · Esc per annullare"
		% [
			String(spell_data.get("name", "Trasformazione")),
			_pending_targets.size(),
			maximum_label
		]
	)


func _begin_token_transformations(
	targets: Array[Node3D],
	spell_data: Dictionary
) -> void:
	if targets.is_empty():
		_cancel_pending_cast()
		return
	_transformation_dialog_targets = targets.duplicate()
	_transformation_dialog_index = 0
	_open_current_transformation_dialog(spell_data)


func _open_current_transformation_dialog(
	spell_data: Dictionary
) -> void:
	if _transformation_dialog_index >= _transformation_dialog_targets.size():
		var transformed_targets: Array[Node3D] = (
			_transformation_dialog_targets.duplicate()
		)
		_complete_spell_cast(
			spell_data,
			transformed_targets,
			_pending_caster
		)
		return

	var target: Node3D = _transformation_dialog_targets[
		_transformation_dialog_index
	]
	if target == null or not is_instance_valid(target):
		_transformation_dialog_index += 1
		_open_current_transformation_dialog(spell_data)
		return
	if not target is CharacterBody3D:
		_cancel_pending_cast()
		return
	if not board_root.has_method("open_token_transformation"):
		_cancel_pending_cast()
		return

	_targeting_phase = "transform_token_dialog"
	_hide_spell_preview()
	_hide_spell_range_preview()
	_set_instruction(
		"%s: scegli il nuovo aspetto del token %d/%d."
		% [
			String(spell_data.get("name", "Trasformazione")),
			_transformation_dialog_index + 1,
			_transformation_dialog_targets.size()
		]
	)
	board_root.call(
		"open_token_transformation",
		target as CharacterBody3D,
		Callable(self, "_on_transformation_token_applied"),
		Callable(self, "_on_transformation_token_canceled")
	)


func _on_transformation_token_applied(
	_transformed_token: CharacterBody3D
) -> void:
	if _pending_spell_id.is_empty():
		return
	_transformation_dialog_index += 1
	_open_current_transformation_dialog(_pending_spell())


func _on_transformation_token_canceled() -> void:
	var restored_any: bool = false
	for index: int in range(_transformation_dialog_index):
		var target: Node3D = _transformation_dialog_targets[index]
		if (
			target != null
			and is_instance_valid(target)
			and target.has_method("restore_previous_transformation")
		):
			restored_any = bool(
				target.call("restore_previous_transformation")
			) or restored_any

	if (
		restored_any
		and board_root.has_method(
			"_refresh_token_views_after_appearance_change"
		)
	):
		board_root.call("_refresh_token_views_after_appearance_change")
	_cancel_pending_cast()


func _try_select_resize_target(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _transformation_target_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		_set_instruction("Seleziona un token valido entro gittata.")
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null or not target is CharacterBody3D:
		return
	if not board_root.has_method("open_token_resize_menu"):
		_cancel_pending_cast()
		return

	_targeting_phase = "resize_token_dialog"
	_hide_spell_preview()
	_hide_spell_range_preview()
	_set_instruction(
		"%s: scegli la nuova taglia del bersaglio."
		% String(spell_data.get("name", "Enlarge/Reduce"))
	)
	board_root.call(
		"open_token_resize_menu",
		target as CharacterBody3D,
		Callable(self, "_on_resize_token_applied"),
		Callable(self, "_on_resize_token_canceled")
	)


func _on_resize_token_applied(resized_token: CharacterBody3D) -> void:
	if _pending_spell_id.is_empty():
		return
	var targets: Array[Node3D] = [resized_token]
	_complete_spell_cast(
		_pending_spell(),
		targets,
		_pending_caster
	)


func _on_resize_token_canceled() -> void:
	if not _pending_spell_id.is_empty():
		_cancel_pending_cast()


func _try_select_caster(screen_position: Vector2) -> void:
	# Use the same 2D icon picking as token selection, including elevated
	# tokens and tokens whose 3D bodies are occluded by scenery.
	var caster: Node3D = _token_at_screen(screen_position)
	if caster == null:
		_set_instruction("Seleziona un token come origine dell'incantesimo.")
		return
	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	_begin_cast_with_caster(caster, spell_data)


func _begin_cast_with_caster(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	if caster == null or not is_instance_valid(caster):
		_cancel_pending_cast()
		return
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	# Keep the caster available through every targeting branch so a
	# successfully completed cast can be logged with combat context.
	_pending_caster = caster

	var target_mode: String = String(spell_data.get("target_mode", ""))
	match target_mode:
		"self_token":
			_cast_spell_from_caster(caster, spell_data)
			_complete_spell_cast(
				spell_data,
				_caster_direction_spell_targets(caster, spell_data),
				caster
			)
		"token_then_point":
			_pending_caster = caster
			_targeting_phase = "point"
			_hide_spell_preview()
			var point_range_feet: int = int(
				round(_effective_spell_range_feet(spell_data, caster))
			)
			_set_instruction(
				"%s: mira un punto entro %d ft e clicca · Shift = griglia/profondità manuale · rotellina regola la profondità · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					point_range_feet
				]
			)
		"token_then_token":
			_pending_caster = caster
			_targeting_phase = "target_token"
			_hide_spell_preview()
			var token_range_feet: int = int(
				round(_effective_spell_range_feet(spell_data, caster))
			)
			var token_target_label: String = (
				"un altro token o un punto"
				if bool(spell_data.get("allow_point_target", false))
				else "un altro token"
			)
			_set_instruction(
				"%s: mira %s entro %d ft e clicca · WASD + mouse per muoverti · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					token_target_label,
					token_range_feet
				]
			)
		"token_then_multi_token":
			_pending_caster = caster
			_pending_targets.clear()
			_pending_target_points.clear()
			_pending_target_history.clear()
			_targeting_phase = "multi_target_tokens"
			_hide_spell_preview()
			_update_multi_target_instruction(spell_data)
		"token_then_multi_point":
			_pending_caster = caster
			_pending_targets.clear()
			_pending_target_points.clear()
			_targeting_phase = "multi_target_points"
			_hide_spell_preview()
			_clear_spell_fixed_previews()
			_update_multi_point_instruction(spell_data)
		"transform_self":
			_pending_caster = caster
			_pending_targets.clear()
			_hide_spell_preview()
			_begin_token_transformations([caster], spell_data)
		"token_then_transform":
			_pending_caster = caster
			_pending_targets.clear()
			_targeting_phase = "transform_target"
			_hide_spell_preview()
			_set_instruction(
				"%s: scegli un token da trasformare entro %d ft · Esc per annullare"
				% [
					String(spell_data.get("name", "Trasformazione")),
					int(round(_effective_spell_range_feet(
						spell_data,
						caster
					)))
				]
			)
		"token_then_multi_transform":
			_pending_caster = caster
			_pending_targets.clear()
			_targeting_phase = "transform_multi_targets"
			_hide_spell_preview()
			_update_transformation_multi_instruction(spell_data)
		"resize_token":
			_pending_caster = caster
			_pending_targets.clear()
			_targeting_phase = "resize_target"
			_hide_spell_preview()
			_set_instruction(
				"%s: scegli il token da ridimensionare entro %d ft · Esc per annullare"
				% [
					String(spell_data.get("name", "Enlarge/Reduce")),
					int(round(_effective_spell_range_feet(
						spell_data,
						caster
					)))
				]
			)
		"summon":
			_pending_caster = caster
			_pending_target_points.clear()
			_summon_created_count = 0
			_hide_spell_preview()
			_begin_summon_count_or_point(spell_data)
		"teleport_self":
			_pending_caster = caster
			_pending_targets.clear()
			_hide_spell_preview()
			var max_passengers: int = int(
				spell_data.get("teleport_max_passengers", 0)
			)
			if max_passengers > 0:
				_targeting_phase = "teleport_passengers"
				_set_instruction(
					"%s: clicca fino a %d token aggiuntivi entro %d ft, oppure premi Invio per continuare senza/finire la selezione."
					% [
						String(spell_data.get("name", "Teletrasporto")),
						max_passengers,
						int(spell_data.get("teleport_passenger_range_feet", 5))
					]
				)
			else:
				_begin_teleport_destination(spell_data)
		"token_then_chain":
			_pending_caster = caster
			_pending_targets.clear()
			_pending_chain_primary = null
			_targeting_phase = "chain_primary"
			_hide_spell_preview()
			_set_instruction(
				"%s: scegli il bersaglio primario entro %d ft · Esc per annullare"
				% [
					String(spell_data.get("name", "Incantesimo")),
					int(round(_effective_spell_range_feet(spell_data, caster)))
				]
			)
		"self_emanation":
			_pending_caster = caster
			_cast_self_emanation(caster, spell_data)
			_complete_spell_cast(
				spell_data,
				_spell_targets_in_geometry(
					caster.global_position,
					_area_endpoint(caster.global_position, spell_data),
					spell_data,
					caster
				),
				caster
			)
		"wall_design":
			_pending_caster = caster
			_hide_spell_preview()
			_show_wall_mode_menu(spell_data)
		"token_then_direction":
			_pending_caster = caster
			_hide_spell_preview()
			if String(spell_data.get("aoe_shape", "")) == "cone":
				_cast_spell_from_caster(caster, spell_data)
				_complete_spell_cast(
					spell_data,
					_caster_direction_spell_targets(caster, spell_data),
					caster
				)
			else:
				_targeting_phase = "direction_point"
				var direction_range_feet: int = int(
					_direction_limit_feet(spell_data)
				)
				_set_instruction(
					"%s: mira un punto o un token entro %d ft per scegliere la direzione · la linea arriva sempre a %d ft · clicca per confermare · Esc per annullare"
					% [
						String(spell_data.get("name", "Incantesimo")),
						direction_range_feet,
						direction_range_feet
					]
				)
		_:
			_cancel_pending_cast()


func _try_select_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var point_data: Dictionary = _point_target_data(
		screen_position,
		spell_data
	)
	if not bool(point_data.get("valid", false)):
		if bool(point_data.get("out_of_range", false)):
			_set_instruction(
				"Punto fuori range: %d ft / %d ft. Scegli un punto più vicino."
				% [
					int(point_data.get("distance_feet", 0)),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		elif bool(spell_data.get("requires_ground", false)):
			_set_instruction(
				"Questo incantesimo richiede un punto su una superficie orizzontale."
			)
		else:
			_set_instruction(
				"Seleziona una superficie o una cella valida della griglia 3D."
			)
		return

	var target_point: Vector3 = point_data.get(
		"point",
		Vector3.ZERO
	)
	_commit_point_spell_cast(
		_pending_caster,
		target_point,
		spell_data
	)


func _commit_point_spell_cast(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	if caster == null or not is_instance_valid(caster):
		_cancel_pending_cast()
		return

	var endpoint: Vector3 = _area_endpoint(target_point, spell_data)
	var targets: Array[Node3D] = _point_spell_targets(
		target_point,
		spell_data,
		caster
	)
	_cast_spell_at_point(caster, target_point, spell_data)
	_complete_spell_cast(spell_data, targets, caster)
	# The confirmed area remains the authority for red hitboxes. This avoids
	# freezing the last affected token list after the preview stops moving.
	_set_spell_geometry_highlight(
		target_point,
		endpoint,
		spell_data,
		caster
	)


func _try_select_target_token(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var target_data: Dictionary = _target_or_point_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		if bool(target_data.get("out_of_range", false)):
			_set_instruction(
				"Bersaglio fuori range: %d ft / %d ft. Scegli un bersaglio più vicino."
				% [
					int(target_data.get("distance_feet", 0)),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		elif bool(spell_data.get("allow_point_target", false)):
			_set_instruction(
				"Seleziona un token o un punto valido entro gittata."
			)
		else:
			_set_instruction(
				"Seleziona un altro token valido come bersaglio."
			)
		return

	if String(target_data.get("kind", "")) == "point":
		var target_point: Vector3 = target_data.get("point", Vector3.ZERO)
		_cast_spell_at_point_target(
			_pending_caster,
			target_point,
			spell_data
		)
		_complete_spell_cast(
			spell_data,
			_point_spell_targets(
				target_point,
				spell_data,
				_pending_caster
			),
			_pending_caster
		)
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null:
		return

	_cast_spell_at_token(
		_pending_caster,
		target,
		spell_data
	)
	var direct_targets: Array[Node3D] = [target]
	_complete_spell_cast(
		spell_data,
		direct_targets,
		_pending_caster
	)


func _try_select_multi_target(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _target_or_point_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		_set_instruction(
			"Seleziona un token o un punto valido entro gittata."
			if bool(spell_data.get("allow_point_target", false))
			else "Seleziona un token valido entro gittata."
		)
		return

	var allow_repeat: bool = bool(
		spell_data.get("allow_repeat_targets", true)
	)
	if String(target_data.get("kind", "")) == "point":
		var target_point: Vector3 = target_data.get("point", Vector3.ZERO)
		if not allow_repeat and _point_target_already_selected(target_point):
			_set_instruction("Questo punto è già stato selezionato.")
			return
		_pending_target_points.append(target_point)
		_pending_target_history.append({
			"kind": "point",
			"point": target_point
		})
	else:
		var target: Node3D = target_data.get("target") as Node3D
		if target == null:
			return
		if not allow_repeat and target in _pending_targets:
			_set_instruction("Questo bersaglio è già stato selezionato.")
			return
		_pending_targets.append(target)
		_pending_target_history.append({
			"kind": "token",
			"target": target
		})

	_set_spell_affected_targets(_pending_targets, true)

	if (
		_pending_targets.size() + _pending_target_points.size()
		>= _required_target_clicks(spell_data)
	):
		_cast_multi_target_spell(
			_pending_caster,
			_pending_targets,
			_pending_target_points,
			spell_data
		)
		var selected_targets: Array[Node3D] = _pending_targets.duplicate()
		_complete_spell_cast(
			spell_data,
			selected_targets,
			_pending_caster
		)
		return

	_update_multi_target_instruction(spell_data)


func _undo_last_multi_target_selection() -> void:
	var spell_data: Dictionary = _pending_spell()
	if _pending_target_history.is_empty():
		_update_multi_target_instruction(spell_data)
		return

	var entry: Dictionary = _pending_target_history.pop_back()
	match String(entry.get("kind", "")):
		"token":
			if not _pending_targets.is_empty():
				_pending_targets.remove_at(_pending_targets.size() - 1)
		"point":
			if not _pending_target_points.is_empty():
				_pending_target_points.remove_at(
					_pending_target_points.size() - 1
				)

	_set_spell_affected_targets(_pending_targets, true)
	_update_multi_target_instruction(spell_data)


func _try_select_multi_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var point_data: Dictionary = _point_target_data(
		screen_position,
		spell_data
	)
	if not bool(point_data.get("valid", false)):
		if bool(point_data.get("out_of_range", false)):
			_set_instruction(
				"Punto fuori range: %d ft / %d ft."
				% [
					int(point_data.get("distance_feet", 0)),
					int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
				]
			)
		else:
			_set_instruction("Seleziona un punto valido entro gittata.")
		return

	var target_point: Vector3 = point_data.get("point", Vector3.ZERO)
	if _point_target_already_selected(target_point):
		_set_instruction("Scegli un punto diverso.")
		return

	_pending_target_points.append(target_point)
	_refresh_multi_point_previews(spell_data)
	if _pending_target_points.size() >= _required_target_clicks(spell_data):
		_cast_multi_point_spell(
			_pending_caster,
			_pending_target_points,
			spell_data
		)
		var affected_targets: Array[Node3D] = []
		for selected_point: Vector3 in _pending_target_points:
			for target: Node3D in _point_spell_targets(
				selected_point,
				spell_data,
				_pending_caster
			):
				if not (target in affected_targets):
					affected_targets.append(target)
		_set_spell_affected_targets(affected_targets, true)
		_committed_targets = affected_targets.duplicate()
		_finish_cast()
		return

	_update_multi_point_instruction(spell_data)


func _update_multi_point_instruction(spell_data: Dictionary) -> void:
	_set_instruction(
		"%s: scegli punti diversi %d/%d entro %d ft · Shift = griglia/profondità manuale · Esc per annullare"
		% [
			String(spell_data.get("name", "Incantesimo")),
			_pending_target_points.size(),
			_required_target_clicks(spell_data),
			int(round(_effective_spell_range_feet(spell_data, _pending_caster)))
		]
	)


func _refresh_multi_point_previews(spell_data: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var starts: Array[Vector3] = []
	var ends: Array[Vector3] = []
	for point: Vector3 in _pending_target_points:
		starts.append(point)
		ends.append(_area_endpoint(point, spell_data))

	measurement_tool.call(
		"show_spell_fixed_previews",
		starts,
		ends,
		String(spell_data.get("aoe_shape", "sphere")),
		_spell_style(spell_data),
		_spell_line_width_world(spell_data)
	)


func _clear_spell_fixed_previews() -> void:
	var measurement_tool: Node = _measurement_tool()
	if (
		measurement_tool != null
		and measurement_tool.has_method("clear_spell_fixed_previews")
	):
		measurement_tool.call("clear_spell_fixed_previews")


func _begin_teleport_destination(spell_data: Dictionary) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return
	_targeting_phase = "teleport_destination"
	_hide_spell_preview()
	_set_instruction(
		"%s: scegli una superficie solida libera entro %d ft."
		% [
			String(spell_data.get("name", "Teletrasporto")),
			int(spell_data.get("teleport_distance_feet", 0))
		]
	)


func _try_select_teleport_passenger(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var target: Node3D = _token_at_screen(screen_position)
	if target == null or target == _pending_caster:
		_set_instruction("Seleziona un altro token vicino al caster, oppure premi Invio.")
		return

	var passenger_range_feet: float = float(
		spell_data.get("teleport_passenger_range_feet", 5.0)
	)
	if (
		_token_target_distance_feet(_pending_caster, target) > passenger_range_feet + 0.001
	):
		_set_instruction(
			"Il token deve trovarsi entro %d ft dal caster."
			% int(passenger_range_feet)
		)
		return

	if target in _pending_targets:
		_pending_targets.erase(target)
	else:
		var max_passengers: int = int(
			spell_data.get("teleport_max_passengers", 0)
		)
		if _pending_targets.size() >= max_passengers:
			_set_instruction(
				"Hai già selezionato il numero massimo di passeggeri. Premi Invio."
			)
			return
		_pending_targets.append(target)

	var passenger_limit: int = int(
		spell_data.get("teleport_max_passengers", 0)
	)
	if _pending_targets.size() >= passenger_limit and passenger_limit > 0:
		_begin_teleport_destination(spell_data)
		return

	_set_instruction(
		"%s: passeggeri %d/%d. Clicca per aggiungere/rimuovere, oppure premi Invio."
		% [
			String(spell_data.get("name", "Teletrasporto")),
			_pending_targets.size(),
			passenger_limit
		]
	)


func _try_select_teleport_destination(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var target_rules: Dictionary = spell_data.duplicate(true)
	target_rules["range_feet"] = float(
		spell_data.get("teleport_distance_feet", 0.0)
	)
	target_rules["requires_ground"] = true
	var point_data: Dictionary = _point_target_data(
		screen_position,
		target_rules
	)
	if not bool(point_data.get("valid", false)):
		if bool(point_data.get("out_of_range", false)):
			_set_instruction(
				"Destinazione fuori gittata: %d ft / %d ft."
				% [
					int(point_data.get("distance_feet", 0)),
					int(target_rules.get("range_feet", 0))
				]
			)
		else:
			_set_instruction(
				"Scegli una superficie solida orizzontale e libera."
			)
		return

	var target_point: Vector3 = point_data.get("point", Vector3.ZERO)
	if not _cast_teleport(
		_pending_caster,
		_pending_targets,
		target_point,
		spell_data
	):
		_set_instruction(
			"La destinazione o una posizione dei passeggeri è occupata."
		)
		return
	_finish_cast()


func _token_half_height(token: Node3D) -> float:
	if token == null:
		return _cell_size()
	var height_cells: float = 2.0
	var value: Variant = token.get("token_height_cells")
	if value is float or value is int:
		height_cells = float(value)
	return maxf(0.05, height_cells * _cell_size() * 0.5)


func _snap_teleport_destination(
	token: Node3D,
	point: Vector3
) -> Vector3:
	var result: Vector3 = point
	if token != null and token.has_method("snap_destination"):
		var snapped_value: Variant = token.call(
			"snap_destination",
			point
		)
		if snapped_value is Vector3:
			result = snapped_value
	return result


func _teleport_destination_is_free(
	token: Node3D,
	target: Vector3,
	teleporting: Array[Node3D]
) -> bool:
	if token == null or not is_instance_valid(token):
		return false

	var collision: CollisionShape3D = token.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision == null or collision.shape == null:
		return true

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(
		token.global_basis,
		target + Vector3.UP * 0.025
	)
	var mask_value: Variant = token.get("collision_mask")
	if mask_value is int:
		query.collision_mask = int(mask_value)
	else:
		query.collision_mask = ALL_COLLISION_LAYERS

	var exclusions: Array[RID] = []
	for moving_token: Node3D in teleporting:
		if moving_token != null and is_instance_valid(moving_token):
			if moving_token is CollisionObject3D:
				exclusions.append((moving_token as CollisionObject3D).get_rid())
	query.exclude = exclusions

	return (
		board_root.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	)


func _cast_teleport(
	caster: Node3D,
	passengers: Array[Node3D],
	target_surface: Vector3,
	spell_data: Dictionary
) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false

	var teleporting: Array[Node3D] = [caster]
	for passenger: Node3D in passengers:
		if passenger != null and is_instance_valid(passenger):
			teleporting.append(passenger)

	var caster_origin: Vector3 = caster.global_position
	var caster_target: Vector3 = target_surface + Vector3.UP * _token_half_height(caster)
	caster_target = _snap_teleport_destination(caster, caster_target)

	var targets: Array[Vector3] = [caster_target]
	for index: int in range(1, teleporting.size()):
		var passenger: Node3D = teleporting[index]
		var relative: Vector3 = passenger.global_position - caster_origin
		var passenger_target: Vector3 = caster_target + relative
		passenger_target = _snap_teleport_destination(
			passenger,
			passenger_target
		)
		targets.append(passenger_target)

	for index: int in range(teleporting.size()):
		if not _teleport_destination_is_free(
			teleporting[index],
			targets[index],
			teleporting
		):
			return false

	if board_root.has_method("push_undo_state"):
		board_root.call("push_undo_state")

	var departure_radius: float = float(
		spell_data.get("teleport_departure_aoe_radius_feet", 0.0)
	)
	if departure_radius > 0.0:
		var departure_tool: Node = _measurement_tool()
		if departure_tool != null:
			var departure_endpoint: Vector3 = (
				caster_origin
				+ Vector3.RIGHT
				* (departure_radius / 5.0 * _cell_size())
			)
			departure_tool.call(
				"show_transient_aoe",
				caster_origin,
				departure_endpoint,
				"sphere",
				float(spell_data.get("transient_seconds", 5.0)),
				String(
					spell_data.get(
						"teleport_departure_style",
						"thunder_step"
					)
				)
			)

	var measurement_tool: Node = _measurement_tool()
	var teleport_style: String = _spell_style(spell_data)
	if measurement_tool != null:
		measurement_tool.call(
			"show_teleport_cloud",
			caster_origin,
			teleport_style,
			0.55
		)

	_animate_teleport_tokens(
		teleporting,
		targets,
		caster_target,
		teleport_style
	)
	_broadcast_spell_visual_event({
		"mode": "teleport",
		"origin": _sync_event_v3(caster_origin),
		"target": _sync_event_v3(caster_target),
		"style": teleport_style,
		"departure_radius_world": departure_radius / 5.0 * _cell_size(),
		"departure_style": String(
			spell_data.get("teleport_departure_style", "thunder_step")
		),
		"duration": float(spell_data.get("transient_seconds", 5.0))
	})
	return true


func _animate_teleport_tokens(
	teleporting: Array[Node3D],
	targets: Array[Vector3],
	caster_target: Vector3,
	teleport_style: String
) -> void:
	# Keep teleportation discrete, but give the departure cloud time to build
	# before the tokens disappear and reappear at their destination.
	await get_tree().create_timer(0.28).timeout

	for token: Node3D in teleporting:
		if token != null and is_instance_valid(token):
			token.visible = false

	await get_tree().create_timer(0.12).timeout

	for index: int in range(teleporting.size()):
		var token: Node3D = teleporting[index]
		if token == null or not is_instance_valid(token):
			continue
		token.global_position = targets[index]
		var velocity_value: Variant = token.get("velocity")
		if velocity_value is Vector3:
			token.set("velocity", Vector3.ZERO)
		var support_value: Variant = token.get("grid_support")
		if support_value != null:
			token.set("grid_support", null)

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call(
			"show_teleport_cloud",
			caster_target,
			teleport_style,
			0.62
		)

	await get_tree().create_timer(0.08).timeout
	for token: Node3D in teleporting:
		if token != null and is_instance_valid(token):
			token.visible = true


func _try_select_chain_primary(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _target_token_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		_set_instruction("Scegli un bersaglio primario valido entro gittata.")
		return

	var primary: Node3D = target_data.get("target") as Node3D
	if primary == null:
		return

	_pending_chain_primary = primary
	_pending_targets.clear()
	_targeting_phase = "chain_secondary"
	_hide_spell_preview()
	_update_chain_instruction(spell_data)


func _try_select_chain_secondary(screen_position: Vector2) -> void:
	if (
		_pending_chain_primary == null
		or not is_instance_valid(_pending_chain_primary)
	):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _chain_secondary_target_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		_set_instruction(
			"Scegli un bersaglio diverso entro %d ft dal bersaglio primario."
			% int(spell_data.get("secondary_range_feet", 30))
		)
		return

	var target: Node3D = target_data.get("target") as Node3D
	if target == null:
		return

	_pending_targets.append(target)
	if _pending_targets.size() >= _required_chain_secondaries(spell_data):
		_cast_chain_lightning(
			_pending_caster,
			_pending_chain_primary,
			_pending_targets,
			spell_data
		)
		_finish_cast()
		return

	_update_chain_instruction(spell_data)


func _try_select_direction_point(screen_position: Vector2) -> void:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		_cancel_pending_cast()
		return

	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	var direction_data: Dictionary = _direction_target_data(
		screen_position,
		spell_data
	)
	if not bool(direction_data.get("valid", false)):
		if bool(direction_data.get("out_of_range", false)):
			_set_instruction(
				"Punto fuori gittata: %d ft / %d ft. Mira più vicino al caster."
				% [
					int(direction_data.get("distance_feet", 0)),
					int(_direction_limit_feet(spell_data))
				]
			)
		else:
			_set_instruction(
				"Mira una superficie, una cella della griglia 3D o un altro token."
			)
		return

	var target_point: Vector3 = direction_data.get(
		"point",
		Vector3.ZERO
	)
	_cast_directional_spell_to_point(
		_pending_caster,
		target_point,
		spell_data
	)
	_complete_spell_cast(
		spell_data,
		_direction_spell_targets(
			_pending_caster,
			target_point,
			spell_data
		),
		_pending_caster
	)


func _try_wall_start(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var point_data: Dictionary = _wall_point_data(
		screen_position,
		spell_data,
		true
	)
	if not bool(point_data.get("valid", false)):
		_set_instruction("Scegli un punto iniziale valido entro gittata.")
		return

	var start: Vector3 = point_data.get("point", Vector3.ZERO)
	_wall_points.clear()
	_wall_points.append(start)
	_targeting_phase = "wall_segment"
	_hide_spell_range_preview()
	_update_wall_segment_instruction(spell_data)


func _try_wall_segment(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var target_data: Dictionary = _wall_segment_target_data(
		screen_position,
		spell_data
	)
	if not bool(target_data.get("valid", false)):
		return

	var endpoint: Vector3 = target_data.get("point", Vector3.ZERO)
	if (
		_wall_points.is_empty()
		or _wall_points[_wall_points.size() - 1].distance_to(endpoint)
			< _cell_size() * 0.05
	):
		return

	_wall_points.append(endpoint)
	if _wall_remaining_world(spell_data) <= _cell_size() * 0.01:
		_prepare_or_commit_wall()
		return

	_update_wall_segment_instruction(spell_data)


func _try_wall_center(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var point_data: Dictionary = _wall_point_data(
		screen_position,
		spell_data,
		true
	)
	if not bool(point_data.get("valid", false)):
		_set_instruction("Scegli un centro valido entro gittata.")
		return

	_wall_center = point_data.get("point", Vector3.ZERO)
	_targeting_phase = "wall_radius"
	_hide_spell_range_preview()
	var max_radius_feet: float = _wall_max_radius_feet(spell_data)
	_set_instruction(
		"%s: scegli il raggio (massimo %.0f ft)."
		% [
			String(spell_data.get("name", "Muro")),
			max_radius_feet
		]
	)


func _try_wall_radius(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var radius_data: Dictionary = _wall_radius_data(
		screen_position,
		spell_data
	)
	if not bool(radius_data.get("valid", false)):
		return

	_wall_radius_world = float(
		radius_data.get("radius_world", 0.0)
	)
	if _wall_radius_world <= _cell_size() * 0.05:
		return

	if _wall_mode in ["globe", "dome"]:
		var measurement_tool: Node = _measurement_tool()
		if measurement_tool != null:
			measurement_tool.call(
				"add_spell_wall_globe",
				_wall_center,
				_wall_radius_world,
				_spell_style(spell_data),
				_wall_mode == "dome",
				_wall_metadata()
			)
		_finish_cast()
		return

	_targeting_phase = "wall_arc_start"
	_set_instruction(
		"%s: scegli il punto iniziale dell'arco sulla circonferenza."
		% String(spell_data.get("name", "Muro"))
	)


func _try_wall_arc_start(screen_position: Vector2) -> void:
	var spell_data: Dictionary = _pending_spell()
	var point_data: Dictionary = _wall_point_data(
		screen_position,
		spell_data,
		false
	)
	if not bool(point_data.get("valid", false)):
		return

	var projected: Vector3 = WallGeometry.project_to_circle(
		_wall_center,
		point_data.get("point", _wall_center + Vector3.RIGHT),
		_wall_radius_world
	)
	_wall_start_angle = WallGeometry.angle_on_circle(
		_wall_center,
		projected
	)
	_wall_previous_cursor_angle = _wall_start_angle
	_wall_sweep = 0.0
	_targeting_phase = "wall_arc_end"
	_set_instruction(
		"%s: percorri la circonferenza e clicca il punto finale. Cliccando subito il punto iniziale crei il cerchio completo."
		% String(spell_data.get("name", "Muro"))
	)


func _try_wall_arc_end(_screen_position: Vector2) -> void:
	if absf(_wall_sweep) < 0.05:
		_wall_sweep = TAU

	_wall_points = WallGeometry.sample_arc(
		_wall_center,
		_wall_radius_world,
		_wall_start_angle,
		_wall_sweep
	)
	_prepare_or_commit_wall()


func _prepare_or_commit_wall() -> void:
	if _wall_points.size() < 2:
		return
	var spell_data: Dictionary = _pending_spell()
	_show_wall_orientation_menu(spell_data)


func _undo_wall_step() -> void:
	var spell_data: Dictionary = _pending_spell()

	if wall_orientation_menu != null and wall_orientation_menu.visible:
		wall_orientation_menu.hide()
	if wall_mode_menu != null and wall_mode_menu.visible:
		wall_mode_menu.hide()
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	match _targeting_phase:
		"wall_orientation":
			_wall_orientation = ""
			_wall_damage_side = 0
			_targeting_phase = (
				"wall_arc_end"
				if _wall_mode == "circle"
				else "wall_segment"
			)
			_set_instruction(
				"%s: orientamento annullato; modifica il muro o conferma di nuovo."
				% String(spell_data.get("name", "Muro"))
			)
		"wall_segment":
			if _wall_points.size() > 1:
				_wall_points.pop_back()
				_update_wall_segment_instruction(spell_data)
			else:
				_wall_points.clear()
				_targeting_phase = "wall_start"
				_set_instruction(
					"%s: scegli di nuovo il punto iniziale."
					% String(spell_data.get("name", "Muro"))
				)
		"wall_arc_end":
			_wall_sweep = 0.0
			_targeting_phase = "wall_arc_start"
			_set_instruction(
				"%s: scegli di nuovo il punto iniziale dell'arco."
				% String(spell_data.get("name", "Muro"))
			)
		"wall_arc_start":
			_wall_radius_world = 0.0
			_targeting_phase = "wall_radius"
			_set_instruction(
				"%s: scegli di nuovo il raggio."
				% String(spell_data.get("name", "Muro"))
			)
		"wall_radius":
			_wall_center = Vector3.ZERO
			_targeting_phase = "wall_center"
			_set_instruction(
				"%s: scegli di nuovo il centro."
				% String(spell_data.get("name", "Muro"))
			)
		"wall_center", "wall_start", "wall_mode":
			_wall_mode = ""
			_wall_points.clear()
			_pending_caster = null
			_targeting_phase = "caster"
			_set_instruction(
				"%s: scegli di nuovo il caster."
				% String(spell_data.get("name", "Muro"))
			)

	_hide_wall_preview()


func _commit_wall_path(spell_data: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null or _wall_points.size() < 2:
		return

	measurement_tool.call(
		"add_spell_wall_path",
		_wall_points,
		_wall_height_world(spell_data),
		_wall_thickness_world(spell_data),
		_spell_style(spell_data),
		_wall_damage_side,
		_wall_metadata()
	)
	_finish_cast()


func _wall_metadata() -> Dictionary:
	return {
		"spell_id": _pending_spell_id,
		"mode": _wall_mode,
		"orientation": _wall_orientation,
		"slot_level": _selected_slot_level,
		"circle_center": [
			_wall_center.x,
			_wall_center.y,
			_wall_center.z
		],
		"circle_radius_world": _wall_radius_world,
		"circle_sweep": _wall_sweep
	}


func _wall_point_data(
	screen_position: Vector2,
	spell_data: Dictionary,
	require_range: bool
) -> Dictionary:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return {"valid": false}

	var point_data: Dictionary = _raw_point_input(screen_position)
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	if bool(spell_data.get("wall_requires_ground", false)):
		if bool(point_data.get("in_air", true)):
			return {"valid": false}
		var normal: Vector3 = point_data.get("normal", Vector3.ZERO)
		if normal.dot(Vector3.UP) < 0.5:
			return {"valid": false}

	var point: Vector3 = point_data.get("point", Vector3.ZERO)
	if require_range:
		if _pending_caster == null or not is_instance_valid(_pending_caster):
			return {"valid": false}
		var range_result: Dictionary = TargetRules.point_in_range(
			_pending_caster.global_position, point,
			_effective_spell_range_feet(spell_data, _pending_caster), _cell_size()
		)
		if not bool(range_result.get("valid", false)):
			return range_result

	return {
		"valid": true,
		"point": point
	}


func _wall_segment_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _wall_points.is_empty():
		return {"valid": false}

	var point_data: Dictionary = _wall_point_data(
		screen_position,
		spell_data,
		false
	)
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	var last_point: Vector3 = _wall_points[_wall_points.size() - 1]
	var target: Vector3 = point_data.get("point", last_point)
	var remaining: float = _wall_remaining_world(spell_data)
	var clamped: Vector3 = WallGeometry.clamp_endpoint(
		last_point,
		target,
		remaining
	)
	return {
		"valid": true,
		"point": clamped
	}


func _wall_radius_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	var point_data: Dictionary = _wall_point_data(
		screen_position,
		spell_data,
		false
	)
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	var point: Vector3 = point_data.get("point", _wall_center)
	var horizontal: Vector3 = point - _wall_center
	horizontal.y = 0.0
	var max_radius_world: float = (
		_wall_max_radius_feet(spell_data)
		/ 5.0 * _cell_size()
	)
	return {
		"valid": true,
		"radius_world": clampf(
			horizontal.length(),
			_cell_size() * 0.25,
			max_radius_world
		)
	}


func _wall_remaining_world(spell_data: Dictionary) -> float:
	var maximum: float = (
		float(spell_data.get("wall_max_length_feet", 0.0))
		/ 5.0 * _cell_size()
	)
	return maxf(
		0.0,
		maximum - WallGeometry.path_length(_wall_points)
	)


func _wall_max_radius_feet(spell_data: Dictionary) -> float:
	if _wall_mode in ["globe", "dome"]:
		return float(
			spell_data.get("wall_globe_max_radius_feet", 10.0)
		)
	return float(
		spell_data.get("wall_circle_max_radius_feet", 10.0)
	)


func _wall_height_world(spell_data: Dictionary) -> float:
	var height_feet: float = float(
		spell_data.get("wall_height_feet", 10.0)
	)
	if _wall_mode == "circle":
		height_feet = float(
			spell_data.get(
				"wall_circle_height_feet",
				height_feet
			)
		)
	return height_feet / 5.0 * _cell_size()


func _wall_thickness_world(spell_data: Dictionary) -> float:
	return maxf(
		float(spell_data.get("wall_thickness_feet", 1.0))
		/ 5.0 * _cell_size(),
		_cell_size() * 0.025
	)


func _update_wall_segment_instruction(spell_data: Dictionary) -> void:
	var remaining_feet: float = (
		_wall_remaining_world(spell_data)
		/ _cell_size() * 5.0
	)
	_set_instruction(
		"%s: clicca per aggiungere segmenti · %.1f ft rimasti · Invio per terminare."
		% [
			String(spell_data.get("name", "Muro")),
			remaining_feet
		]
	)


func _update_wall_preview(
	screen_position: Vector2,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	match _targeting_phase:
		"wall_start", "wall_center", "wall_mode":
			_hide_wall_preview()

		"wall_segment":
			var target_data: Dictionary = _wall_segment_target_data(
				screen_position,
				spell_data
			)
			if not bool(target_data.get("valid", false)):
				_hide_wall_preview()
				return
			var preview_points: Array[Vector3] = []
			for wall_point: Vector3 in _wall_points:
				preview_points.append(wall_point)
			preview_points.append(
				target_data.get("point", preview_points[-1])
			)
			measurement_tool.call(
				"show_wall_path_preview",
				preview_points,
				_wall_height_world(spell_data),
				_wall_thickness_world(spell_data),
				_spell_style(spell_data),
				0
			)

		"wall_radius":
			var radius_data: Dictionary = _wall_radius_data(
				screen_position,
				spell_data
			)
			if not bool(radius_data.get("valid", false)):
				_hide_wall_preview()
				return
			var radius_world: float = float(
				radius_data.get("radius_world", 0.0)
			)
			if _wall_mode in ["globe", "dome"]:
				measurement_tool.call(
					"show_wall_globe_preview",
					_wall_center,
					radius_world,
					_spell_style(spell_data),
					_wall_mode == "dome"
				)
			else:
				var circle_points: Array[Vector3] = (
					WallGeometry.sample_full_circle(
						_wall_center,
						radius_world
					)
				)
				measurement_tool.call(
					"show_wall_path_preview",
					circle_points,
					_wall_height_world(spell_data),
					_wall_thickness_world(spell_data),
					_spell_style(spell_data),
					0
				)

		"wall_arc_start":
			var full_circle: Array[Vector3] = (
				WallGeometry.sample_full_circle(
					_wall_center,
					_wall_radius_world
				)
			)
			measurement_tool.call(
				"show_wall_path_preview",
				full_circle,
				_wall_height_world(spell_data),
				_wall_thickness_world(spell_data),
				_spell_style(spell_data),
				0
			)

		"wall_arc_end":
			var point_data: Dictionary = _wall_point_data(
				screen_position,
				spell_data,
				false
			)
			if bool(point_data.get("valid", false)):
				var projected: Vector3 = WallGeometry.project_to_circle(
					_wall_center,
					point_data.get(
						"point",
						_wall_center + Vector3.RIGHT
					),
					_wall_radius_world
				)
				var angle: float = WallGeometry.angle_on_circle(
					_wall_center,
					projected
				)
				var delta: float = WallGeometry.unwrap_delta(
					_wall_previous_cursor_angle,
					angle
				)
				if absf(_wall_sweep) < TAU - 0.0001:
					_wall_sweep = clampf(
						_wall_sweep + delta,
						-TAU,
						TAU
					)
				_wall_previous_cursor_angle = angle

			var arc_points: Array[Vector3] = WallGeometry.sample_arc(
				_wall_center,
				_wall_radius_world,
				_wall_start_angle,
				_wall_sweep
			)
			measurement_tool.call(
				"show_wall_path_preview",
				arc_points,
				_wall_height_world(spell_data),
				_wall_thickness_world(spell_data),
				_spell_style(spell_data),
				0
			)



func _hide_wall_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("hide_wall_preview", true)


func _update_spell_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return
	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		# Invalidated runtime spells must exit the full targeting lifecycle.
		_cancel_pending_cast()
		return

	var screen_position: Vector2 = (
		get_viewport().get_mouse_position()
		if _is_2d_view()
		else get_viewport().get_visible_rect().size * 0.5
	)
	_update_spell_range_preview(spell_data)
	if _targeting_phase.begins_with("wall_"):
		_set_spell_affected_targets([], true)
		_hide_spell_preview()
		_update_wall_preview(screen_position, spell_data)
		return

	# Only these phases retain highlights independent of the moving preview.
	# In particular, a rejected multi-target candidate must not erase the
	# already selected targets. Saving throws have their own held targets.
	if _targeting_phase == "multi_target_tokens":
		_set_spell_affected_targets(_pending_targets, true)
	elif _targeting_phase == "saving_throw":
		_set_spell_affected_targets(_saving_throw_targets, true)
	elif _targeting_phase not in ["caster", "point", "multi_target_points", "direction_point"]:
		_set_spell_affected_targets([], true)

	var preview: Dictionary = _resolve_spell_preview(screen_position, spell_data)
	if not bool(preview.get("valid", false)):
		if _targeting_phase in ["caster", "point", "multi_target_points", "direction_point"]:
			_set_spell_affected_targets([], true)
		_hide_spell_preview()
		return

	var start: Vector3 = preview.get("start", Vector3.ZERO)
	var end: Vector3 = preview.get("end", Vector3.ZERO)
	var shape: String = String(preview.get("shape", "line"))
	var style: String = String(preview.get("style", _spell_style(spell_data)))
	if preview.has("width"):
		measurement_tool.call("show_spell_preview", start, end, shape, style,
			float(preview["width"]))
	else:
		measurement_tool.call("show_spell_preview", start, end, shape, style)
	if bool(preview.get("highlight_geometry", false)):
		_set_spell_geometry_highlight(start, end, spell_data,
			preview.get("caster", _pending_caster) as Node3D)


# Every active targeting phase resolves its own input and rules; the renderer
# only sees an ephemeral, normalized geometry result. Committed AoEs, walls,
# teleportation, chained targets and saving throws remain separate states.
func _resolve_spell_preview(screen_position: Vector2, spell_data: Dictionary) -> Dictionary:
	match _targeting_phase:
		"caster":
			var hovered: Node3D = _token_at_screen(screen_position)
			if hovered == null:
				return {}
			var mode: String = String(spell_data.get("target_mode", ""))
			if mode == "self_token" or (
				mode == "token_then_direction"
				and String(spell_data.get("aoe_shape", "")) == "cone"
			):
				return _direction_preview(
					_directional_spell_geometry(hovered, spell_data),
					spell_data, hovered, "cone"
				)
			if mode == "self_emanation":
				return _area_preview(hovered.global_position, spell_data, hovered)
		"point", "multi_target_points":
			if _pending_caster == null or not is_instance_valid(_pending_caster):
				return {}
			var point_data: Dictionary = _point_target_data(screen_position, spell_data)
			if bool(point_data.get("valid", false)):
				return _area_preview(
					point_data.get("point", Vector3.ZERO), spell_data, _pending_caster
				)
		"target_token", "multi_target_tokens":
			var target_data: Dictionary = _target_or_point_data(screen_position, spell_data)
			var endpoint: Dictionary = _preview_target_endpoint(target_data)
			if bool(endpoint.get("valid", false)):
				var projectile_style: String = (
					String(spell_data.get("projectile_style", _spell_style(spell_data)))
					if _targeting_phase == "target_token"
					else String(spell_data.get("projectile_style", "magic_missile"))
				)
				return _line_preview(
					_token_spell_origin(_pending_caster),
					endpoint.get("point", Vector3.ZERO),
					projectile_style
				)
		"transform_target", "transform_multi_targets", "resize_target":
			var transform_data: Dictionary = _transformation_target_data(
				screen_position, spell_data
			)
			var target: Node3D = transform_data.get("target") as Node3D
			if bool(transform_data.get("valid", false)) and target != null:
				return _line_preview(_token_spell_origin(_pending_caster),
					_token_spell_origin(target), _spell_style(spell_data))
		"summon_point":
			var summon_spell: Dictionary = spell_data.duplicate(true)
			if bool(spell_data.get("summon_requires_ground", false)):
				summon_spell["requires_ground"] = true
			var summon_data: Dictionary = _point_target_data(
				screen_position, summon_spell
			)
			if bool(summon_data.get("valid", false)):
				var point: Vector3 = summon_data.get("point", Vector3.ZERO)
				return _line_preview(point,
					point + Vector3.RIGHT * _cell_size() * 0.45,
					_spell_style(spell_data), "sphere")
		"chain_primary", "chain_secondary":
			var secondary: bool = _targeting_phase == "chain_secondary"
			var chain_data: Dictionary = (
				_chain_secondary_target_data(screen_position, spell_data)
				if secondary else _target_token_data(screen_position, spell_data)
			)
			var chain_target: Node3D = chain_data.get("target") as Node3D
			if bool(chain_data.get("valid", false)) and chain_target != null:
				return _line_preview(
					_token_spell_origin(_pending_chain_primary if secondary else _pending_caster),
					_token_spell_origin(chain_target), "chain_lightning"
				)
		"direction_point":
			var direction_data: Dictionary = _direction_target_data(
				screen_position, spell_data
			)
			if bool(direction_data.get("valid", false)):
				return _direction_preview(
					_direction_geometry_from_point(
						_pending_caster,
						direction_data.get("point", Vector3.ZERO),
						spell_data
					), spell_data, _pending_caster, "line"
				)
	return {}


func _preview_target_endpoint(target_data: Dictionary) -> Dictionary:
	if not bool(target_data.get("valid", false)):
		return {}
	if String(target_data.get("kind", "")) == "point":
		return {"valid": true, "point": target_data.get("point", Vector3.ZERO)}
	var token: Node3D = target_data.get("target") as Node3D
	if token == null:
		return {}
	return {"valid": true, "point": _token_spell_origin(token)}


func _line_preview(start: Vector3, end: Vector3, style: String,
	shape: String = "line") -> Dictionary:
	return {"valid": true, "start": start, "end": end,
		"shape": shape, "style": style}


func _area_preview(origin: Vector3, spell_data: Dictionary,
	caster: Node3D) -> Dictionary:
	return {
		"valid": true, "start": origin,
		"end": _area_endpoint(origin, spell_data),
		"shape": String(spell_data.get("aoe_shape", "sphere")),
		"style": _spell_style(spell_data),
		"width": _spell_line_width_world(spell_data),
		"highlight_geometry": true, "caster": caster
	}


func _direction_preview(geometry: Dictionary, spell_data: Dictionary,
	caster: Node3D, fallback_shape: String) -> Dictionary:
	if geometry.is_empty():
		return {}
	return {
		"valid": true,
		"start": geometry.get("start", Vector3.ZERO),
		"end": geometry.get("end", Vector3.ZERO),
		"shape": String(spell_data.get("aoe_shape", fallback_shape)),
		"style": _spell_style(spell_data),
		"width": _spell_line_width_world(spell_data),
		"highlight_geometry": true, "caster": caster
	}

func _token_at_screen(screen_position: Vector2) -> Node3D:
	if _remote_input_active:
		# Remote selection is already a token reference, not a map position.
		return _remote_pick_token
	return TargetInput.token_from_screen(
		board_root, screen_position, _is_2d_view(), TOKEN_PICK_COLLISION_MASK
	)


const RANGE_PREVIEW_PHASES := [
	"point", "target_token", "multi_target_tokens",
	"multi_target_points", "summon_point", "transform_target",
	"transform_multi_targets", "resize_target", "teleport_passengers",
	"teleport_destination", "chain_primary", "chain_secondary",
	"direction_point", "wall_start", "wall_center"
]


# The 2D HUD and 3D range mesh share one description of visible reach.
# Cast-specific constraints such as passenger proximity stay independent.
func targeting_range_info(spell_data: Dictionary) -> Dictionary:
	if (
		_pending_caster == null or not is_instance_valid(_pending_caster)
		or _targeting_phase not in RANGE_PREVIEW_PHASES
		or not bool(spell_data.get("show_range_preview", true))
	):
		return {}
	var source: Node3D = _pending_caster
	var feet: float = _effective_spell_range_feet(spell_data, source)
	if _targeting_phase == "chain_secondary":
		if _pending_chain_primary != null and is_instance_valid(_pending_chain_primary):
			source = _pending_chain_primary
			feet = float(spell_data.get("secondary_range_feet", 30.0))
	elif _targeting_phase in ["teleport_destination", "teleport_passengers"]:
		feet = float(spell_data.get("teleport_distance_feet", feet))
	if feet <= 0.0:
		return {}
	var footprint: float = _cell_size() * 0.5
	if source.has_method("get_footprint_cells"):
		footprint *= maxf(0.5, float(source.call("get_footprint_cells")))
	return {"source": source, "feet": feet, "footprint": footprint}

func _update_spell_range_preview(spell_data: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return
	var info: Dictionary = targeting_range_info(spell_data)
	if info.is_empty():
		measurement_tool.call("hide_spell_range_preview")
		return
	var source: Node3D = info["source"] as Node3D
	measurement_tool.call(
		"show_spell_range_preview", source.global_position,
		_spell_range_world(float(info["feet"])), float(info["footprint"])
	)

func _spell_range_world(range_feet: float) -> float:
	# One conversion for spell range overlays and target validation.
	return range_feet / 5.0 * _cell_size()

func _direction_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var token_target: Node3D = _token_at_screen(screen_position)
	if token_target != null:
		if token_target == _pending_caster:
			return {"valid": false}
		return _validate_direction_point(
			_token_spell_origin(token_target),
			spell_data
		)

	var point_data: Dictionary = _raw_point_input(screen_position)
	if not bool(point_data.get("valid", false)):
		return {"valid": false}

	return _validate_direction_point(
		point_data.get("point", Vector3.ZERO),
		spell_data
	)


func _validate_direction_point(
	point: Vector3,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}

	var validated: Dictionary = TargetRules.point_in_range(
		_pending_caster.global_position, point,
		_direction_limit_feet(spell_data), _cell_size()
	)
	if not bool(validated.get("valid", false)):
		return validated

	var origin: Vector3 = _token_spell_origin(_pending_caster)
	if origin.distance_squared_to(point) < 0.0001:
		return {"valid": false}

	return {
		"valid": true,
		"point": point
	}


func _chain_secondary_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	return _chain_secondary_candidate(_token_at_screen(screen_position), spell_data)


func _chain_secondary_candidate(candidate: Node3D, spell_data: Dictionary) -> Dictionary:
	if candidate in _pending_targets:
		return {"valid": false}
	# A secondary bolt originates from the primary victim, not the caster.
	return TargetRules.token_in_range(
		_pending_chain_primary, candidate,
		float(spell_data.get("secondary_range_feet", 30.0)), _cell_size()
	)


# Input adapters provide candidates; eligibility does not depend on which
# projection (2D, 3D, remote phone) supplied the token.
func _target_token_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	return _target_token_candidate(_token_at_screen(screen_position), spell_data)


func _target_token_candidate(candidate: Node3D, spell_data: Dictionary) -> Dictionary:
	return TargetRules.token_in_range(
		_pending_caster, candidate,
		_effective_spell_range_feet(spell_data, _pending_caster), _cell_size()
	)


# Spell HUDs use precisely the same tactical-footprint test as token picks.
# Measurement tools intentionally do not inherit this spell policy.
func _token_within_spell_range(
	source: Node3D,
	candidate: Node3D,
	range_feet: float,
	exclude_source: bool = true
) -> bool:
	return bool(TargetRules.token_in_range(
		source, candidate, range_feet, _cell_size(), exclude_source
	).get("valid", false))


func _target_or_point_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	var hovered: Node3D = _token_at_screen(screen_position)
	if hovered != null or not bool(spell_data.get("allow_point_target", false)):
		return _target_or_point_candidate(hovered, {}, spell_data)
	var force_grid: bool = Input.is_key_pressed(KEY_SHIFT)
	var air_distance: float = (
		-1.0 if force_grid else _point_target_air_distance_world(spell_data)
	)
	return _target_or_point_candidate(
		null, _raw_point_input(screen_position, air_distance, force_grid),
		spell_data
	)


func _target_or_point_candidate(
	candidate: Node3D,
	point_input: Dictionary,
	spell_data: Dictionary
) -> Dictionary:
	if candidate != null:
		# A token rejected by the rules must not silently become a point.
		var target_result: Dictionary = _target_token_candidate(candidate, spell_data)
		target_result["kind"] = "token"
		return target_result
	if not bool(spell_data.get("allow_point_target", false)):
		return {"valid": false}
	var point_result: Dictionary = _validate_spell_point(point_input, spell_data)
	point_result["kind"] = "point"
	return point_result

func _is_2d_view() -> bool:
	return (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("is_2d_view_enabled")
		and bool(board_root.call("is_2d_view_enabled"))
	)


func _screen_2d_point_data(screen_position: Vector2) -> Dictionary:
	return TargetInput.top_down_point(board_root, screen_position)

func _point_target_already_selected(point: Vector3) -> bool:
	var tolerance: float = _cell_size() * 0.05
	for selected_point: Vector3 in _pending_target_points:
		if selected_point.distance_to(point) <= tolerance:
			return true
	return false


func _raw_point_input(
	screen_position: Vector2,
	preferred_air_distance_world: float = -1.0,
	force_grid_target: bool = false
) -> Dictionary:
	if _remote_input_active:
		return _remote_pick_point.duplicate()
	return TargetInput.point_from_screen(
		board_root, _measurement_tool(), screen_position, _is_2d_view(),
		preferred_air_distance_world, force_grid_target
	)

func _point_target_data(
	screen_position: Vector2,
	spell_data: Dictionary
) -> Dictionary:
	var force_grid_target: bool = Input.is_key_pressed(KEY_SHIFT)
	var air_distance: float = (
		-1.0 if force_grid_target
		else _point_target_air_distance_world(spell_data)
	)
	return _validate_spell_point(
		_raw_point_input(screen_position, air_distance, force_grid_target),
		spell_data
	)


func _validate_spell_point(
	point_input: Dictionary,
	spell_data: Dictionary
) -> Dictionary:
	if _pending_caster == null or not is_instance_valid(_pending_caster):
		return {"valid": false}
	if not bool(point_input.get("valid", false)):
		return {"valid": false}
	if bool(spell_data.get("requires_ground", false)):
		if bool(point_input.get("in_air", true)):
			return {"valid": false}
		var normal: Vector3 = point_input.get("normal", Vector3.ZERO)
		if normal.dot(Vector3.UP) < 0.5:
			return {"valid": false}
	var target_point: Vector3 = point_input.get("point", Vector3.ZERO)
	var validated: Dictionary = TargetRules.point_in_range(
		_pending_caster.global_position, target_point,
		_effective_spell_range_feet(spell_data, _pending_caster), _cell_size()
	)
	if not bool(validated.get("valid", false)):
		return validated
	validated["in_air"] = bool(point_input.get("in_air", false))
	validated["normal"] = point_input.get("normal", Vector3.ZERO)
	return validated

func _point_target_air_distance_feet(
	spell_data: Dictionary
) -> float:
	# Le aree che devono stare sul terreno mantengono il raycast classico:
	# il depth automatico in aria le renderebbe inutilizzabili a distanza.
	if bool(spell_data.get("requires_ground", false)):
		return -1.0

	var shape: String = String(
		spell_data.get("aoe_shape", "")
	)
	match shape:
		"sphere":
			return maxf(
				_effective_aoe_radius_feet(spell_data) * 2.0,
				5.0
			)
		"cylinder", "circle":
			return maxf(
				float(spell_data.get("aoe_radius_feet", 5.0)) * 2.0,
				5.0
			)
		"cube", "flat_square":
			return maxf(
				float(spell_data.get("aoe_side_feet", 5.0)),
				5.0
			)
		_:
			return -1.0


func _point_target_air_distance_world(
	spell_data: Dictionary
) -> float:
	var distance_feet: float = _point_target_air_distance_feet(
		spell_data
	)
	if distance_feet <= 0.0:
		return -1.0
	return maxf(
		distance_feet / 5.0 * _cell_size(),
		_cell_size()
	)


func _spell_line_width_world(spell_data: Dictionary) -> float:
	var width_feet: float = float(
		spell_data.get("line_width_feet", -1.0)
	)
	if width_feet <= 0.0:
		return -1.0
	return width_feet / 5.0 * _cell_size()


func _area_endpoint(
	origin: Vector3,
	spell_data: Dictionary
) -> Vector3:
	var shape: String = String(spell_data.get("aoe_shape", "sphere"))
	if shape == "sphere":
		var radius_feet: float = _effective_aoe_radius_feet(spell_data)
		return (
			origin
			+ Vector3.RIGHT
			* (radius_feet / 5.0 * _cell_size())
		)
	if shape in ["cube", "flat_square"]:
		var side_feet: float = float(
			spell_data.get("aoe_side_feet", 10.0)
		)
		return (
			origin
			+ Vector3.RIGHT
			* (side_feet * 0.5 / 5.0 * _cell_size())
		)
	if shape == "cylinder":
		var radius_world: float = (
			float(spell_data.get("aoe_radius_feet", 5.0))
			/ 5.0 * _cell_size()
		)
		var height_world: float = (
			float(spell_data.get("aoe_height_feet", 5.0))
			/ 5.0 * _cell_size()
		)
		return origin + Vector3(radius_world, height_world, 0.0)

	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 1)
	)
	return origin + Vector3.FORWARD * float(length_cells) * _cell_size()


func _directional_spell_geometry(
	caster: Node3D,
	spell_data: Dictionary
) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	var direction: Vector3 = -caster.global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	var right_axis: Vector3 = direction.cross(Vector3.UP).normalized()
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT

	direction = (
		Basis(
			right_axis,
			deg_to_rad(float(_directional_pitch_degrees))
		)
		* direction
	).normalized()

	var origin: Vector3 = _token_spell_origin(caster)
	if String(spell_data.get("aoe_shape", "")) == "cone":
		var horizontal_forward: Vector3 = Vector3(
			direction.x,
			0.0,
			direction.z
		)
		if horizontal_forward.length_squared() < 0.0001:
			horizontal_forward = -caster.global_transform.basis.z
			horizontal_forward.y = 0.0
		if horizontal_forward.length_squared() > 0.0001:
			origin += horizontal_forward.normalized() * _cell_size()

	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 3)
	)
	return {
		"start": origin,
		"end": (
			origin
			+ direction * float(length_cells) * _cell_size()
		)
	}


func _direction_geometry_from_point(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	var origin: Vector3 = _token_spell_origin(caster)
	var direction: Vector3 = target_point - origin
	if direction.length_squared() < 0.0001:
		return {}
	direction = direction.normalized()

	if bool(spell_data.get("directional_cube", false)):
		var side_feet: float = float(
			spell_data.get("aoe_side_feet", 15.0)
		)
		var half_world: float = side_feet * 0.5 / 5.0 * _cell_size()
		var cube_center: Vector3 = origin + direction * half_world
		return {
			"start": cube_center,
			"end": cube_center + Vector3.RIGHT * half_world
		}

	var length_cells: int = int(
		spell_data.get("aoe_length_cells", 1)
	)
	return {
		"start": origin,
		"end": (
			origin
			+ direction * float(length_cells) * _cell_size()
		)
	}


func _token_spell_origin(token: Node3D) -> Vector3:
	if token == null or not is_instance_valid(token):
		return Vector3.ZERO
	if token.has_method("get_spell_origin_position"):
		var origin_value: Variant = token.call("get_spell_origin_position")
		if origin_value is Vector3:
			return origin_value
	return token.global_position


func _hide_spell_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("hide_spell_preview")


func _hide_spell_range_preview() -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("hide_spell_range_preview")


func _adjust_point_depth(step_cells: float) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call(
			"adjust_spell_target_depth",
			step_cells
		)


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "SpellPanel"
	# Spell browser: fixed to the left side, almost half the viewport.
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.48
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	# The runtime toolbar occupies the top strip (10–55 px). Leave its
	# buttons, including "Chiudi", fully visible and clickable.
	panel.offset_top = 66.0
	panel.offset_right = -4.0
	panel.offset_bottom = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# The spell browser is an editing/targeting UI, not an overlay preview:
	# make it fully opaque so the 3D scene and encounter HUD cannot bleed
	# through the controls.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.028, 0.036, 1.0)
	panel_style.border_color = Color(0.42, 0.34, 0.22, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", panel_style)

	panel.hide()
	ui_root.add_child(panel)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 12)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(outer_margin)

	var root_layout: VBoxContainer = VBoxContainer.new()
	root_layout.add_theme_constant_override("separation", 8)
	outer_margin.add_child(root_layout)

	var header: HBoxContainer = HBoxContainer.new()
	root_layout.add_child(header)

	var title: Label = Label.new()
	title.text = "Incantesimi"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "Chiudi"
	close_button.custom_minimum_size = Vector2(72, 28)
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 270
	root_layout.add_child(body)

	var browser: VBoxContainer = VBoxContainer.new()
	browser.custom_minimum_size = Vector2(250, 0)
	browser.add_theme_constant_override("separation", 6)
	body.add_child(browser)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Cerca incantesimo..."
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(_refresh_search_results)
	browser.add_child(search_input)

	var search_label: Label = Label.new()
	search_label.text = "Risultati ricerca"
	search_label.add_theme_font_size_override("font_size", 12)
	browser.add_child(search_label)

	search_results = ItemList.new()
	search_results.custom_minimum_size = Vector2(0, 78)
	search_results.select_mode = ItemList.SELECT_SINGLE
	search_results.item_selected.connect(_on_search_item_selected)
	browser.add_child(search_results)

	var class_label: Label = Label.new()
	class_label.text = "Liste incantesimi per classe"
	class_label.add_theme_font_size_override("font_size", 12)
	browser.add_child(class_label)

	class_tree = Tree.new()
	class_tree.hide_root = true
	class_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	class_tree.item_selected.connect(_on_tree_item_selected)
	browser.add_child(class_tree)

	var details: VBoxContainer = VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	body.add_child(details)

	spell_title = Label.new()
	spell_title.text = "Seleziona un incantesimo"
	spell_title.add_theme_font_size_override("font_size", 22)
	details.add_child(spell_title)

	spell_meta = Label.new()
	spell_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spell_meta.modulate = Color(0.76, 0.79, 0.86, 1.0)
	details.add_child(spell_meta)

	slot_row = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	var slot_label: Label = Label.new()
	slot_label.text = "Slot:"
	slot_row.add_child(slot_label)
	slot_selector = OptionButton.new()
	slot_selector.custom_minimum_size = Vector2(150, 30)
	slot_selector.item_selected.connect(_on_slot_selected)
	slot_row.add_child(slot_selector)
	details.add_child(slot_row)
	slot_row.hide()

	spell_description = RichTextLabel.new()
	spell_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spell_description.fit_content = false
	spell_description.scroll_active = true
	spell_description.selection_enabled = true
	details.add_child(spell_description)

	activate_button = Button.new()
	activate_button.text = "Attiva incantesimo"
	activate_button.custom_minimum_size = Vector2(0, 36)
	activate_button.disabled = true
	activate_button.pressed.connect(_activate_selected_spell)
	details.add_child(activate_button)


func _build_instruction_label() -> void:
	instruction_label = Label.new()
	instruction_label.name = "SpellInstruction"
	instruction_label.anchor_left = 0.2
	instruction_label.anchor_top = 0.0
	instruction_label.anchor_right = 0.8
	instruction_label.anchor_bottom = 0.0
	instruction_label.offset_top = 52.0
	instruction_label.offset_bottom = 86.0
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 18)
	instruction_label.add_theme_color_override(
		"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.9)
	)
	instruction_label.add_theme_constant_override("outline_size", 5)
	instruction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_label.hide()
	ui_root.add_child(instruction_label)


func _build_saving_throw_dialog() -> void:
	saving_throw_dialog = ConfirmationDialog.new()
	saving_throw_dialog.name = "SpellSavingThrowDialog"
	saving_throw_dialog.title = "Tiro salvezza"
	saving_throw_dialog.ok_button_text = "SÌ"
	saving_throw_dialog.cancel_button_text = "NO"
	saving_throw_dialog.confirmed.connect(
		func() -> void:
			_resolve_current_saving_throw(true)
	)
	saving_throw_dialog.canceled.connect(
		func() -> void:
			_resolve_current_saving_throw(false)
	)
	ui_root.add_child(saving_throw_dialog)


func _populate_class_tree() -> void:
	class_tree.clear()
	var root: TreeItem = class_tree.create_item()

	for class_label: String in SpellCatalog.class_names():
		var class_item: TreeItem = class_tree.create_item(root)
		class_item.set_text(
			0,
			SpellCatalog.class_display_name(class_label)
		)
		class_item.set_collapsed(true)

		for level: int in range(SpellCatalog.LEVEL_NAMES.size()):
			var level_item: TreeItem = class_tree.create_item(class_item)
			level_item.set_text(
				0,
				SpellCatalog.LEVEL_NAMES[level]
			)
			level_item.set_collapsed(true)

			var spells: Array[Dictionary] = (
				SpellCatalog.spells_for_class_and_level(
					class_label,
					level
				)
			)
			for spell_data: Dictionary in spells:
				var spell_item: TreeItem = class_tree.create_item(level_item)
				spell_item.set_text(
					0,
					String(spell_data.get("name", "Incantesimo"))
				)
				spell_item.set_metadata(
					0,
					spell_data.duplicate(true)
				)


func _refresh_search_results(query: String) -> void:
	search_results.clear()
	var normalized_query: String = query.strip_edges().to_lower()

	for spell_data: Dictionary in SpellCatalog.all_spells():
		var spell_name: String = String(spell_data.get("name", ""))
		if (
			not normalized_query.is_empty()
			and normalized_query not in spell_name.to_lower()
		):
			continue

		var index: int = search_results.add_item(spell_name)
		search_results.set_item_metadata(
			index,
			spell_data.duplicate(true)
		)


func _on_search_item_selected(index: int) -> void:
	var metadata: Variant = search_results.get_item_metadata(index)
	_select_spell_metadata(metadata)


func _on_tree_item_selected() -> void:
	var item: TreeItem = class_tree.get_selected()
	if item == null:
		return

	var metadata: Variant = item.get_metadata(0)
	if metadata == null:
		return
	_select_spell_metadata(metadata)


func _select_spell_metadata(metadata: Variant) -> void:
	if metadata is Dictionary:
		_show_spell_data((metadata as Dictionary).duplicate(true))
		return

	var spell_id: String = String(metadata)
	if spell_id.is_empty():
		return
	_select_spell(spell_id)


func _select_spell(spell_id: String) -> void:
	var spell_data: Dictionary = SpellCatalog.catalog_spell(spell_id)
	if spell_data.is_empty():
		return
	_show_spell_data(spell_data)


func _show_spell_data(spell_data: Dictionary) -> void:
	if spell_data.is_empty():
		return

	var spell_id: String = String(spell_data.get("id", ""))
	if spell_id.is_empty():
		return

	_selected_spell_id = spell_id
	_selected_spell_data = spell_data.duplicate(true)
	spell_title.text = String(spell_data.get("name", "Incantesimo"))

	var classes_value: Variant = spell_data.get("classes", [])
	var classes_text: String = ""
	if classes_value is Array:
		var class_names: PackedStringArray = PackedStringArray()
		for class_value: Variant in classes_value:
			class_names.append(
				SpellCatalog.class_display_name(String(class_value))
			)
		classes_text = ", ".join(class_names)

	var target_text: String = String(
		spell_data.get("target", "")
	)
	if target_text.is_empty():
		match String(spell_data.get("target_mode", "")):
			"token_then_token":
				target_text = (
					"Un token o un punto entro gittata"
					if bool(spell_data.get("allow_point_target", false))
					else "Un token entro gittata"
				)
			"token_then_multi_token":
				target_text = (
					"Più token o punti entro gittata"
					if bool(spell_data.get("allow_point_target", false))
					else "Più token entro gittata"
				)
			"token_then_multi_point":
				target_text = "Più punti distinti entro gittata"
			"summon":
				target_text = "Punto/i di evocazione entro gittata"
			"transform_self":
				target_text = "Self"
			"token_then_transform":
				target_text = "Un token entro gittata"
			"token_then_multi_transform":
				target_text = "Più token entro gittata"
			"resize_token":
				target_text = "Un token entro gittata"
			"token_then_point":
				target_text = "Un punto entro gittata"
			"self_token", "self_emanation":
				target_text = "Self"
			"wall_design":
				target_text = "Un punto entro gittata"
			_:
				target_text = "Self"

	var area_text: String = String(
		spell_data.get("area", "")
	)
	if area_text.is_empty():
		if String(spell_data.get("aoe_shape", "")) == "cone":
			area_text = "%d-foot cone" % (
				int(spell_data.get("aoe_length_cells", 0)) * 5
			)

	spell_meta.text = (
		"%s · %s · %s\n"
		+ "Tempo di lancio: %s | Range: %s\n"
		+ "Bersaglio: %s | Area: %s\n"
		+ "Componenti: %s | Durata: %s\n"
		+ "Classi: %s"
	) % [
		SpellCatalog.LEVEL_NAMES[int(spell_data.get("level", 0))],
		String(spell_data.get("school", "")),
		String(spell_data.get("source", "")),
		String(spell_data.get("casting_time", "")),
		String(spell_data.get("range", "")),
		target_text,
		area_text,
		String(spell_data.get("components", "")),
		String(spell_data.get("duration", "")),
		classes_text
	]

	_configure_slot_selector(spell_data)
	var level17_text: String = String(
		spell_data.get("level17_damage", "")
	)
	var cantrip_note: String = ""
	if int(spell_data.get("level", 0)) == 0:
		cantrip_note = "\n\nVTT: trucchetto trattato come lanciato da un personaggio di livello 17."
		if not level17_text.is_empty():
			cantrip_note += " Danno di riferimento: " + level17_text + "."

	spell_description.text = (
		String(spell_data.get("description", ""))
		+ "\n\nAi livelli superiori: "
		+ String(spell_data.get("higher_levels", ""))
		+ cantrip_note
	)
	var runtime_supported: bool = SpellCatalog.is_runtime_usable(
		_selected_spell_data
	)
	activate_button.disabled = not runtime_supported
	activate_button.text = (
		"Attiva incantesimo"
		if runtime_supported
		else "Effetto VTT non disponibile"
	)


func _activate_selected_spell() -> void:
	if not _remote_input_active and not is_targeting():
		_remote_owner = ""
		_remote_caster = null
	if _selected_spell_id.is_empty() or _selected_spell_data.is_empty():
		return

	var spell_data: Dictionary = _selected_spell_data.duplicate(true)
	if not SpellCatalog.is_runtime_usable(spell_data):
		return

	# Existing spell areas stay on the map until the user clicks the area.
	if board_root.has_method("clear_token_selection"):
		board_root.call("clear_token_selection")
	_set_spell_affected_targets([], true)

	var target_mode: String = String(
		spell_data.get("target_mode", "")
	)
	if target_mode not in ACTIVATABLE_TARGET_MODES:
		return

	_pending_spell_id = _selected_spell_id
	_pending_spell_data = spell_data.duplicate(true)
	_targeting_phase = "caster"
	_pending_caster = null
	_pending_targets.clear()
	_pending_target_points.clear()
	_pending_target_history.clear()
	_committed_targets.clear()
	_pending_chain_primary = null
	_directional_pitch_degrees = 0

	var measurement_tool: Node = _measurement_tool()
	if measurement_tool != null:
		measurement_tool.call("set_measurement_mode", false)
	var measurement_label: Label = board_root.get_node_or_null(
		"UI/MeasurementModeLabel"
	) as Label
	if measurement_label != null:
		measurement_label.hide()

	var camera: Camera3D = board_root.get_node_or_null("Camera3D") as Camera3D
	if (
		camera != null
		and _remote_owner.is_empty()
		and camera.has_method("is_first_person")
		and bool(camera.call("is_first_person"))
		and camera.has_method("exit_first_person")
	):
		camera.call("exit_first_person")

	panel.hide()
	board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE if _is_2d_view() else Input.MOUSE_MODE_CAPTURED
	)

	if bool(spell_data.get("allow_pitch", false)):
		_update_directional_instruction(spell_data)
	else:
		_set_instruction(
			"%s: mira un token e clicca per scegliere il caster · WASD + mouse per muoverti · Esc per annullare"
			% String(spell_data.get("name", "Incantesimo"))
		)


func _sync_event_v3(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _sync_event_vector3(value: Variant) -> Vector3:
	if value is Dictionary:
		return Vector3(
			float((value as Dictionary).get("x", 0.0)),
			float((value as Dictionary).get("y", 0.0)),
			float((value as Dictionary).get("z", 0.0))
		)
	return Vector3.ZERO


func _broadcast_spell_visual_event(event: Dictionary) -> void:
	if (
		event.is_empty()
		or board_root == null
		or not is_instance_valid(board_root)
		or not board_root.has_method("broadcast_sync_event")
	):
		return
	var payload := event.duplicate(true)
	payload["type"] = "spell_visual"
	payload["spell_id"] = _pending_spell_id
	board_root.call("broadcast_sync_event", payload)


func _broadcast_aoe_sync_visual(
	start: Vector3,
	end: Vector3,
	shape: String,
	style: String,
	duration: float,
	width_world: float
) -> void:
	_broadcast_spell_visual_event({
		"mode": "aoe",
		"start": _sync_event_v3(start),
		"end": _sync_event_v3(end),
		"shape": shape,
		"style": style,
		"duration": duration,
		"width_world": width_world
	})


func _broadcast_projectile_sync_visual(
	start: Vector3,
	finish: Vector3,
	style: String,
	travel_seconds: float
) -> void:
	_broadcast_spell_visual_event({
		"mode": "projectile",
		"start": _sync_event_v3(start),
		"finish": _sync_event_v3(finish),
		"style": style,
		"travel_seconds": travel_seconds
	})


func _broadcast_projectile_impact_sync_visual(
	start: Vector3,
	finish: Vector3,
	projectile_style: String,
	travel_seconds: float,
	impact_shape: String,
	impact_radius_world: float,
	impact_style: String,
	duration: float
) -> void:
	_broadcast_spell_visual_event({
		"mode": "projectile_impact",
		"start": _sync_event_v3(start),
		"finish": _sync_event_v3(finish),
		"projectile_style": projectile_style,
		"travel_seconds": travel_seconds,
		"impact_shape": impact_shape,
		"impact_radius_world": impact_radius_world,
		"impact_style": impact_style,
		"duration": duration
	})


func replay_sync_visual_event(event: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return
	var mode := String(event.get("mode", ""))
	match mode:
		"aoe":
			measurement_tool.call(
				"show_transient_aoe",
				_sync_event_vector3(event.get("start")),
				_sync_event_vector3(event.get("end")),
				String(event.get("shape", "sphere")),
				float(event.get("duration", 5.0)),
				String(event.get("style", "")),
				float(event.get("width_world", 0.0))
			)
		"projectile":
			measurement_tool.call(
				"show_spell_projectile",
				_sync_event_vector3(event.get("start")),
				_sync_event_vector3(event.get("finish")),
				String(event.get("style", "")),
				float(event.get("travel_seconds", 0.65))
			)
		"projectile_impact":
			measurement_tool.call(
				"show_spell_projectile_with_impact",
				_sync_event_vector3(event.get("start")),
				_sync_event_vector3(event.get("finish")),
				String(event.get("projectile_style", "")),
				float(event.get("travel_seconds", 0.65)),
				String(event.get("impact_shape", "sphere")),
				float(event.get("impact_radius_world", 0.0)),
				String(event.get("impact_style", "")),
				float(event.get("duration", 5.0))
			)
		"projectiles":
			var projectiles_value: Variant = event.get("projectiles", [])
			if projectiles_value is Array:
				for projectile_value: Variant in projectiles_value as Array:
					if not projectile_value is Dictionary:
						continue
					var projectile: Dictionary = projectile_value as Dictionary
					measurement_tool.call(
						"show_spell_projectile",
						_sync_event_vector3(projectile.get("start")),
						_sync_event_vector3(projectile.get("finish")),
						String(projectile.get("style", "")),
						float(projectile.get("travel_seconds", 0.65))
					)
		"meteor_impacts":
			var impacts_value: Variant = event.get("impacts", [])
			if impacts_value is Array:
				for impact_value: Variant in impacts_value as Array:
					if not impact_value is Dictionary:
						continue
					var impact: Dictionary = impact_value as Dictionary
					measurement_tool.call(
						"show_spell_projectile_with_impact",
						_sync_event_vector3(impact.get("start")),
						_sync_event_vector3(impact.get("finish")),
						String(impact.get("projectile_style", "")),
						float(impact.get("travel_seconds", 0.8)),
						String(impact.get("shape", "sphere")),
						float(impact.get("radius_world", 0.0)),
						String(impact.get("style", "")),
						float(impact.get("duration", 5.0))
					)
		"aoes":
			var aoes_value: Variant = event.get("aoes", [])
			if aoes_value is Array:
				for aoe_value: Variant in aoes_value as Array:
					if not aoe_value is Dictionary:
						continue
					var aoe: Dictionary = aoe_value as Dictionary
					measurement_tool.call(
						"show_transient_aoe",
						_sync_event_vector3(aoe.get("start")),
						_sync_event_vector3(aoe.get("end")),
						String(aoe.get("shape", "sphere")),
						float(aoe.get("duration", 5.0)),
						String(aoe.get("style", "")),
						float(aoe.get("width_world", 0.0))
					)
		"teleport":
			_replay_synced_teleport_visual(event)


func _replay_synced_teleport_visual(event: Dictionary) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return
	var origin := _sync_event_vector3(event.get("origin"))
	var target := _sync_event_vector3(event.get("target"))
	var style := String(event.get("style", "teleport"))
	var departure_radius_world := float(
		event.get("departure_radius_world", 0.0)
	)
	if departure_radius_world > 0.0:
		measurement_tool.call(
			"show_transient_aoe",
			origin,
			origin + Vector3.RIGHT * departure_radius_world,
			"sphere",
			float(event.get("duration", 5.0)),
			String(event.get("departure_style", style))
		)
	measurement_tool.call("show_teleport_cloud", origin, style, 0.55)
	await get_tree().create_timer(0.40).timeout
	measurement_tool.call("show_teleport_cloud", target, style, 0.62)


func _cast_spell_from_caster(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	_cast_directional_aoe(caster, spell_data)


func _cast_spell_at_point(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var endpoint: Vector3 = _area_endpoint(target_point, spell_data)
	var shape: String = String(spell_data.get("aoe_shape", "sphere"))
	var style: String = _spell_style(spell_data)
	if bool(spell_data.get("persistent", false)):
		measurement_tool.call(
			"add_spell_aoe",
			target_point,
			endpoint,
			shape,
			style,
			Color(0.0, 0.0, 0.0, -1.0),
			_spell_line_width_world(spell_data),
			float(spell_data.get("movable_aoe_feet", 0.0)),
			String(spell_data.get("movable_aoe_mode", "free")),
			caster.global_position
		)
	else:
		if measurement_tool.has_method("show_held_spell_aoe"):
			measurement_tool.call(
				"show_held_spell_aoe",
				target_point,
				endpoint,
				shape,
				style,
				_spell_line_width_world(spell_data)
			)
		else:
			measurement_tool.call(
				"show_transient_aoe",
				target_point,
				endpoint,
				shape,
				float(spell_data.get("transient_seconds", 5.0)),
				style,
				_spell_line_width_world(spell_data),
				false
			)
	_broadcast_aoe_sync_visual(
		target_point,
		endpoint,
		shape,
		style,
		float(spell_data.get("transient_seconds", 5.0)),
		_spell_line_width_world(spell_data)
	)

func _cast_directional_aoe(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var geometry: Dictionary = _directional_spell_geometry(
		caster,
		spell_data
	)
	if geometry.is_empty():
		return

	var duration: float = float(
		spell_data.get("transient_seconds", 5.0)
	)

	measurement_tool.call(
		"show_transient_aoe",
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		String(spell_data.get("aoe_shape", "cone")),
		duration,
		_spell_style(spell_data),
		_spell_line_width_world(spell_data)
	)
	_broadcast_aoe_sync_visual(
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		String(spell_data.get("aoe_shape", "cone")),
		_spell_style(spell_data),
		duration,
		_spell_line_width_world(spell_data)
	)

func _cast_directional_spell_to_point(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var geometry: Dictionary = _direction_geometry_from_point(
		caster,
		target_point,
		spell_data
	)
	if geometry.is_empty():
		return

	if bool(spell_data.get("persistent", false)):
		measurement_tool.call(
			"add_spell_aoe",
			geometry.get("start", Vector3.ZERO),
			geometry.get("end", Vector3.ZERO),
			String(spell_data.get("aoe_shape", "line")),
			_spell_style(spell_data),
			Color(0.0, 0.0, 0.0, -1.0),
			_spell_line_width_world(spell_data)
		)
	else:
		measurement_tool.call(
			"show_transient_aoe",
			geometry.get("start", Vector3.ZERO),
			geometry.get("end", Vector3.ZERO),
			String(spell_data.get("aoe_shape", "line")),
			float(spell_data.get("transient_seconds", 5.0)),
			_spell_style(spell_data),
			_spell_line_width_world(spell_data)
		)
	_broadcast_aoe_sync_visual(
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		String(spell_data.get("aoe_shape", "line")),
		_spell_style(spell_data),
		float(spell_data.get("transient_seconds", 5.0)),
		_spell_line_width_world(spell_data)
	)

func _cast_spell_at_token(
	caster: Node3D,
	target: Node3D,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var start: Vector3 = _token_spell_origin(caster)
	var finish: Vector3 = _token_spell_origin(target)
	var projectile_style: String = String(
		spell_data.get("projectile_style", "")
	)
	var travel_seconds: float = float(
		spell_data.get("projectile_travel_seconds", 0.65)
	)
	var impact_radius: float = float(
		spell_data.get("impact_aoe_radius_feet", 0.0)
	)

	if bool(spell_data.get("persistent_link", false)):
		measurement_tool.call(
			"add_spell_aoe",
			start,
			finish,
			"line",
			_spell_style(spell_data)
		)
		_broadcast_aoe_sync_visual(
			start,
			finish,
			"line",
			_spell_style(spell_data),
			float(spell_data.get("transient_seconds", 5.0)),
			_spell_line_width_world(spell_data)
		)
		return

	if impact_radius > 0.0:
		var resolved_projectile_style := (
			projectile_style
			if not projectile_style.is_empty()
			else _spell_style(spell_data)
		)
		var resolved_impact_style := String(
			spell_data.get("impact_style", _spell_style(spell_data))
		)
		var impact_radius_world := impact_radius / 5.0 * _cell_size()
		var impact_duration := float(
			spell_data.get("transient_seconds", 5.0)
		)
		measurement_tool.call(
			"show_spell_projectile_with_impact",
			start,
			finish,
			resolved_projectile_style,
			travel_seconds,
			String(spell_data.get("impact_aoe_shape", "sphere")),
			impact_radius_world,
			resolved_impact_style,
			impact_duration
		)
		_broadcast_projectile_impact_sync_visual(
			start,
			finish,
			resolved_projectile_style,
			travel_seconds,
			String(spell_data.get("impact_aoe_shape", "sphere")),
			impact_radius_world,
			resolved_impact_style,
			impact_duration
		)
		return

	if not projectile_style.is_empty():
		measurement_tool.call(
			"show_spell_projectile",
			start,
			finish,
			projectile_style,
			travel_seconds
		)
		_broadcast_projectile_sync_visual(
			start,
			finish,
			projectile_style,
			travel_seconds
		)
		return

	var spec_value: Variant = spell_data.get("map_effect_spec", {})
	if not spec_value is Dictionary:
		return
	var spec: Dictionary = spec_value as Dictionary
	var targeting_value: Variant = spec.get("targeting", {})
	if not targeting_value is Dictionary:
		return
	if String(
		(targeting_value as Dictionary).get("type", "")
	) != "token":
		return

	var shape: String = String(spell_data.get("aoe_shape", ""))
	if shape.is_empty():
		return

	var endpoint: Vector3 = _area_endpoint(finish, spell_data)
	var style: String = _spell_style(spell_data)
	if bool(spell_data.get("persistent", false)):
		measurement_tool.call(
			"add_spell_aoe",
			finish,
			endpoint,
			shape,
			style,
			Color(0.0, 0.0, 0.0, -1.0),
			_spell_line_width_world(spell_data)
		)
	else:
		measurement_tool.call(
			"show_transient_aoe",
			finish,
			endpoint,
			shape,
			float(spell_data.get("transient_seconds", 5.0)),
			style,
			_spell_line_width_world(spell_data)
		)
	_broadcast_aoe_sync_visual(
		finish,
		endpoint,
		shape,
		style,
		float(spell_data.get("transient_seconds", 5.0)),
		_spell_line_width_world(spell_data)
	)

func _cast_spell_at_point_target(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var start: Vector3 = _token_spell_origin(caster)
	var projectile_style: String = String(
		spell_data.get("projectile_style", "")
	)
	var travel_seconds: float = float(
		spell_data.get("projectile_travel_seconds", 0.65)
	)
	var impact_radius: float = float(
		spell_data.get("impact_aoe_radius_feet", 0.0)
	)

	if impact_radius > 0.0:
		var resolved_projectile_style := (
			projectile_style
			if not projectile_style.is_empty()
			else _spell_style(spell_data)
		)
		var resolved_impact_style := String(
			spell_data.get("impact_style", _spell_style(spell_data))
		)
		var impact_radius_world := impact_radius / 5.0 * _cell_size()
		var impact_duration := float(
			spell_data.get("transient_seconds", 5.0)
		)
		measurement_tool.call(
			"show_spell_projectile_with_impact",
			start,
			target_point,
			resolved_projectile_style,
			travel_seconds,
			String(spell_data.get("impact_aoe_shape", "sphere")),
			impact_radius_world,
			resolved_impact_style,
			impact_duration
		)
		_broadcast_projectile_impact_sync_visual(
			start,
			target_point,
			resolved_projectile_style,
			travel_seconds,
			String(spell_data.get("impact_aoe_shape", "sphere")),
			impact_radius_world,
			resolved_impact_style,
			impact_duration
		)
		return

	if not projectile_style.is_empty():
		measurement_tool.call(
			"show_spell_projectile",
			start,
			target_point,
			projectile_style,
			travel_seconds
		)
		_broadcast_projectile_sync_visual(
			start,
			target_point,
			projectile_style,
			travel_seconds
		)
		return

	_cast_spell_at_point(caster, target_point, spell_data)


func _cast_self_emanation(
	caster: Node3D,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return
	var center: Vector3 = caster.global_position
	var endpoint: Vector3 = _area_endpoint(center, spell_data)
	var shape: String = String(spell_data.get("aoe_shape", "sphere"))
	var style: String = _spell_style(spell_data)
	if bool(spell_data.get("persistent", false)):
		var follow_target: Node3D = null
		if bool(spell_data.get("follow_caster", true)):
			follow_target = caster
		measurement_tool.call(
			"add_spell_aoe",
			center,
			endpoint,
			shape,
			style,
			Color(0.0, 0.0, 0.0, -1.0),
			_spell_line_width_world(spell_data),
			0.0,
			"free",
			Vector3(INF, INF, INF),
			follow_target
		)
	else:
		measurement_tool.call(
			"show_transient_aoe",
			center,
			endpoint,
			shape,
			float(spell_data.get("transient_seconds", 5.0)),
			style,
			_spell_line_width_world(spell_data)
		)
	_broadcast_aoe_sync_visual(
		center,
		endpoint,
		shape,
		style,
		float(spell_data.get("transient_seconds", 5.0)),
		_spell_line_width_world(spell_data)
	)

func _cast_multi_target_spell(
	caster: Node3D,
	targets: Array[Node3D],
	target_points: Array[Vector3],
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var start: Vector3 = _token_spell_origin(caster)
	var style: String = String(
		spell_data.get("projectile_style", "")
	)
	if style.is_empty():
		return
	var travel_seconds: float = float(
		spell_data.get("projectile_travel_seconds", 0.65)
	)

	# _try_select_multi_target calls this only after all required targets
	# have been selected, so the projectiles begin together.
	for target: Node3D in targets:
		if target == null or not is_instance_valid(target):
			continue
		measurement_tool.call(
			"show_spell_projectile",
			start,
			_token_spell_origin(target),
			style,
			travel_seconds
		)

	for target_point: Vector3 in target_points:
		measurement_tool.call(
			"show_spell_projectile",
			start,
			target_point,
			style,
			travel_seconds
		)

	var projectiles: Array = []
	for target: Node3D in targets:
		if target != null and is_instance_valid(target):
			projectiles.append({
				"start": _sync_event_v3(start),
				"finish": _sync_event_v3(_token_spell_origin(target)),
				"style": style,
				"travel_seconds": travel_seconds
			})
	for target_point: Vector3 in target_points:
		projectiles.append({
			"start": _sync_event_v3(start),
			"finish": _sync_event_v3(target_point),
			"style": style,
			"travel_seconds": travel_seconds
		})
	_broadcast_spell_visual_event({
		"mode": "projectiles",
		"projectiles": projectiles
	})


func _cast_multi_point_spell(
	_caster: Node3D,
	target_points: Array[Vector3],
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var style: String = _spell_style(spell_data)
	var shape: String = String(spell_data.get("aoe_shape", "sphere"))
	var radius_feet: float = float(
		spell_data.get("aoe_radius_feet", 5.0)
	)
	var radius_world: float = radius_feet / 5.0 * _cell_size()
	var duration: float = float(
		spell_data.get("transient_seconds", 5.0)
	)

	if String(spell_data.get("id", "")) == "meteor_swarm":
		var drop_height_world: float = (
			float(spell_data.get("meteor_drop_height_feet", 60.0))
			/ 5.0
			* _cell_size()
		)
		var travel_seconds: float = float(
			spell_data.get("projectile_travel_seconds", 0.8)
		)
		var projectile_style: String = String(
			spell_data.get("projectile_style", style)
		)
		var impacts: Array = []
		for point: Vector3 in target_points:
			var meteor_start := point + Vector3.UP * drop_height_world
			measurement_tool.call(
				"show_spell_projectile_with_impact",
				meteor_start,
				point,
				projectile_style,
				travel_seconds,
				shape,
				radius_world,
				style,
				duration
			)
			impacts.append({
				"start": _sync_event_v3(meteor_start),
				"finish": _sync_event_v3(point),
				"projectile_style": projectile_style,
				"travel_seconds": travel_seconds,
				"shape": shape,
				"radius_world": radius_world,
				"style": style,
				"duration": duration
			})
		_broadcast_spell_visual_event({
			"mode": "meteor_impacts",
			"impacts": impacts
		})
		return

	var aoes: Array = []
	for point: Vector3 in target_points:
		var endpoint := point + Vector3.RIGHT * radius_world
		measurement_tool.call(
			"show_transient_aoe",
			point,
			endpoint,
			shape,
			duration,
			style,
			_spell_line_width_world(spell_data)
		)
		aoes.append({
			"start": _sync_event_v3(point),
			"end": _sync_event_v3(endpoint),
			"shape": shape,
			"duration": duration,
			"style": style,
			"width_world": _spell_line_width_world(spell_data)
		})
	_broadcast_spell_visual_event({"mode": "aoes", "aoes": aoes})

func _cast_chain_lightning(
	_caster: Node3D,
	_primary: Node3D,
	_secondaries: Array[Node3D],
	_spell_data: Dictionary
) -> void:
	# Chain-only visual effects are disabled together with all spell
	# animations. Chain spells are filtered out until they gain a map effect.
	return

func _cast_fireball(
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var radius_feet: float = float(
		spell_data.get("aoe_radius_feet", 20.0)
	)
	var radius_world: float = (
		radius_feet / 5.0 * _cell_size()
	)
	var endpoint: Vector3 = (
		target_point + Vector3.RIGHT * radius_world
	)
	var duration: float = float(
		spell_data.get("transient_seconds", 5.0)
	)

	measurement_tool.call(
		"show_transient_aoe",
		target_point,
		endpoint,
		String(spell_data.get("aoe_shape", "sphere")),
		duration,
		String(spell_data.get("id", "fireball"))
	)

func _cast_persistent_sphere(
	target_point: Vector3,
	spell_data: Dictionary
) -> void:
	var measurement_tool: Node = _measurement_tool()
	if measurement_tool == null:
		return

	var radius_feet: float = float(
		spell_data.get("aoe_radius_feet", 15.0)
	)
	var radius_world: float = (
		radius_feet / 5.0 * _cell_size()
	)
	var endpoint: Vector3 = (
		target_point + Vector3.RIGHT * radius_world
	)

	measurement_tool.call(
		"add_spell_aoe",
		target_point,
		endpoint,
		String(spell_data.get("aoe_shape", "sphere")),
		String(spell_data.get("id", ""))
	)


func _spell_targets_in_geometry(
	start: Vector3,
	end: Vector3,
	spell_data: Dictionary,
	caster: Node3D = null
) -> Array[Node3D]:
	var targets: Array[Node3D] = []
	var shape: String = String(
		spell_data.get("aoe_shape", "sphere")
	)
	var exclude_caster: bool = TargetRules.excludes_caster(spell_data)

	var measurement_tool: Node = _measurement_tool()
	if (
		measurement_tool != null
		and measurement_tool.has_method(
			"spell_geometry_affected_tokens"
		)
	):
		var affected_value: Variant = measurement_tool.call(
			"spell_geometry_affected_tokens",
			start,
			end,
			shape,
			_spell_style(spell_data),
			_spell_line_width_world(spell_data)
		)
		if affected_value is Array:
			return TargetRules.filter_affected(
				affected_value, caster, spell_data
			)

	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is Node3D:
			continue
		var token: Node3D = node as Node3D
		if token == null or not is_instance_valid(token):
			continue
		if exclude_caster and caster != null and token == caster:
			continue
		if _token_inside_spell_geometry(
			_token_spell_origin(token),
			start,
			end,
			shape,
			spell_data
		):
			targets.append(token)
	return targets


# The same policy is applied to an active casting HUD, but the general
# measurement/creature-intersection list deliberately remains inclusive.
func _filter_spell_affected_targets(
	candidates: Array,
	spell_data: Dictionary,
	caster: Node3D
) -> Array[Node3D]:
	return TargetRules.filter_affected(candidates, caster, spell_data)


func _token_inside_spell_geometry(
	point: Vector3,
	start: Vector3,
	end: Vector3,
	shape: String,
	spell_data: Dictionary
) -> bool:
	var tolerance: float = _cell_size() * 0.45

	match shape:
		"sphere":
			var radius: float = (
				_effective_aoe_radius_feet(spell_data)
				/ 5.0
				* _cell_size()
			)
			return point.distance_to(start) <= radius + tolerance

		"cube":
			var half_side: float = (
				float(spell_data.get("aoe_side_feet", 10.0))
				* 0.5
				/ 5.0
				* _cell_size()
			)
			var delta: Vector3 = point - start
			return (
				absf(delta.x) <= half_side + tolerance
				and absf(delta.y) <= half_side + tolerance
				and absf(delta.z) <= half_side + tolerance
			)

		"flat_square":
			var half_square: float = (
				float(spell_data.get("aoe_side_feet", 10.0))
				* 0.5
				/ 5.0
				* _cell_size()
			)
			var flat_delta: Vector3 = point - start
			return (
				absf(flat_delta.x) <= half_square + tolerance
				and absf(flat_delta.z) <= half_square + tolerance
				and absf(flat_delta.y) <= _cell_size() * 1.5
			)

		"cylinder":
			var radius_world: float = (
				float(spell_data.get("aoe_radius_feet", 5.0))
				/ 5.0
				* _cell_size()
			)
			var height_world: float = (
				float(spell_data.get("aoe_height_feet", 5.0))
				/ 5.0
				* _cell_size()
			)
			var cylinder_delta: Vector3 = point - start
			var horizontal: Vector2 = Vector2(
				cylinder_delta.x,
				cylinder_delta.z
			)
			return (
				horizontal.length() <= radius_world + tolerance
				and cylinder_delta.y >= -tolerance
				and cylinder_delta.y <= height_world + tolerance
			)

		"line":
			var line_axis: Vector3 = end - start
			var line_length: float = line_axis.length()
			if line_length < 0.0001:
				return false
			var line_direction: Vector3 = line_axis / line_length
			var from_start: Vector3 = point - start
			var along: float = from_start.dot(line_direction)
			if along < -tolerance or along > line_length + tolerance:
				return false
			var closest: Vector3 = start + line_direction * clampf(
				along,
				0.0,
				line_length
			)
			var half_width: float = (
				maxf(
					float(spell_data.get("line_width_feet", 5.0)),
					5.0
				)
				* 0.5
				/ 5.0
				* _cell_size()
			)
			return point.distance_to(closest) <= half_width + tolerance

		"cone":
			var cone_axis: Vector3 = end - start
			var cone_length: float = cone_axis.length()
			if cone_length < 0.0001:
				return false
			var cone_direction: Vector3 = cone_axis / cone_length
			var cone_delta: Vector3 = point - start
			var cone_along: float = cone_delta.dot(cone_direction)
			if cone_along < -tolerance or cone_along > cone_length + tolerance:
				return false
			var radial_vector: Vector3 = (
				cone_delta - cone_direction * cone_along
			)
			# D&D cones are as wide at a given distance as that distance.
			return radial_vector.length() <= maxf(cone_along, 0.0) + tolerance

	return false


func _point_spell_targets(
	point: Vector3,
	spell_data: Dictionary,
	caster: Node3D
) -> Array[Node3D]:
	return _spell_targets_in_geometry(
		point,
		_area_endpoint(point, spell_data),
		spell_data,
		caster
	)


func _direction_spell_targets(
	caster: Node3D,
	target_point: Vector3,
	spell_data: Dictionary
) -> Array[Node3D]:
	var geometry: Dictionary = _direction_geometry_from_point(
		caster,
		target_point,
		spell_data
	)
	if geometry.is_empty():
		return []
	return _spell_targets_in_geometry(
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		spell_data,
		caster
	)


func _caster_direction_spell_targets(
	caster: Node3D,
	spell_data: Dictionary
) -> Array[Node3D]:
	var geometry: Dictionary = _directional_spell_geometry(
		caster,
		spell_data
	)
	if geometry.is_empty():
		return []
	return _spell_targets_in_geometry(
		geometry.get("start", Vector3.ZERO),
		geometry.get("end", Vector3.ZERO),
		spell_data,
		caster
	)


func _spell_needs_saving_throw_resolution(
	spell_data: Dictionary
) -> bool:
	var conditions_value: Variant = spell_data.get(
		"condition_inflict",
		[]
	)
	if conditions_value is Array and not (conditions_value as Array).is_empty():
		return true

	var transformation_mode: String = String(
		spell_data.get("transformation_mode", "")
	)
	if (
		transformation_mode in ["appearance", "resize"]
		and String(spell_data.get("target_mode", "")) != "transform_self"
	):
		var saves_value: Variant = spell_data.get("saving_throw", [])
		if saves_value is Array and not (saves_value as Array).is_empty():
			return true

	return bool(
		spell_data.get("forced_movement_on_failed_save", false)
	)


func _complete_spell_cast(
	spell_data: Dictionary,
	targets: Array[Node3D],
	caster: Node3D = null
) -> void:
	_committed_targets = targets.duplicate()
	_set_spell_affected_targets(targets, true)
	if not _spell_needs_saving_throw_resolution(spell_data):
		_finish_cast()
		return
	# Only targets that fail the saving throw receive persistent effects.
	_committed_targets.clear()

	var unique_targets: Array[Node3D] = []
	for target: Node3D in targets:
		if (
			target != null
			and is_instance_valid(target)
			and not (target in unique_targets)
		):
			unique_targets.append(target)

	if unique_targets.is_empty():
		_finish_cast()
		return

	_saving_throw_targets = unique_targets
	_saving_throw_index = 0
	_saving_throw_undo_recorded = false
	_saving_throw_caster_origin = (
		caster.global_position
		if caster != null and is_instance_valid(caster)
		else Vector3.ZERO
	)
	_targeting_phase = "saving_throw"

	_hide_spell_preview()
	_clear_spell_fixed_previews()
	_hide_spell_range_preview()
	_hide_wall_preview()
	board_root.set("_ui_owns_mouse", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_current_saving_throw_prompt(spell_data)


func _show_current_saving_throw_prompt(
	spell_data: Dictionary
) -> void:
	if (
		saving_throw_dialog == null
		or _saving_throw_index >= _saving_throw_targets.size()
	):
		_finish_cast()
		return

	var target: Node3D = _saving_throw_targets[_saving_throw_index]
	if target == null or not is_instance_valid(target):
		_saving_throw_index += 1
		_show_current_saving_throw_prompt(spell_data)
		return

	var target_name: String = target.name
	if target.has_method("get_display_name"):
		var display_name: String = String(
			target.call("get_display_name")
		).strip_edges()
		if not display_name.is_empty():
			target_name = display_name

	var saves_value: Variant = spell_data.get("saving_throw", [])
	var save_label: String = "tiro salvezza"
	if saves_value is Array and not (saves_value as Array).is_empty():
		var labels: PackedStringArray = PackedStringArray()
		for save_value: Variant in saves_value:
			var label: String = String(save_value).strip_edges()
			if not label.is_empty():
				labels.append(label.capitalize())
		if not labels.is_empty():
			save_label = "TS %s" % "/".join(labels)

	saving_throw_dialog.dialog_text = (
		"%s\n%s per %s superato?\n\nSÌ = superato · NO = fallito"
		% [
			String(spell_data.get("name", "Incantesimo")),
			save_label,
			target_name
		]
	)
	DialogLayout.popup(saving_throw_dialog, Vector2i(500, 220), 0.92)


func _resolve_current_saving_throw(succeeded: bool) -> void:
	if _targeting_phase != "saving_throw":
		return

	var spell_data: Dictionary = _pending_spell()
	if spell_data.is_empty():
		_cancel_pending_cast()
		return

	if _saving_throw_index < _saving_throw_targets.size():
		var target: Node3D = _saving_throw_targets[_saving_throw_index]
		if target != null and is_instance_valid(target):
			var transformation_mode: String = String(
				spell_data.get("transformation_mode", "")
			)
			if (
				succeeded
				and transformation_mode in ["appearance", "resize"]
				and target.has_method("restore_previous_transformation")
			):
				if not _saving_throw_undo_recorded:
					if board_root.has_method("push_undo_state"):
						board_root.call("push_undo_state")
					_saving_throw_undo_recorded = true
				target.call("restore_previous_transformation")
				if board_root.has_method(
					"_refresh_token_views_after_appearance_change"
				):
					board_root.call(
						"_refresh_token_views_after_appearance_change"
					)
			elif not succeeded:
				if not (target in _committed_targets):
					_committed_targets.append(target)
				if not _saving_throw_undo_recorded:
					if board_root.has_method("push_undo_state"):
						board_root.call("push_undo_state")
					_saving_throw_undo_recorded = true
				_apply_failed_saving_throw_effects(target, spell_data)

	_saving_throw_index += 1
	if _saving_throw_index >= _saving_throw_targets.size():
		_finish_cast()
		return

	call_deferred(
		"_show_current_saving_throw_prompt",
		spell_data
	)


func _apply_failed_saving_throw_effects(
	target: Node3D,
	spell_data: Dictionary
) -> void:
	var conditions_value: Variant = spell_data.get(
		"condition_inflict",
		[]
	)
	if conditions_value is Array and target.has_method("set_condition"):
		for condition_value: Variant in conditions_value:
			var condition_id: String = String(
				condition_value
			).strip_edges().to_lower()
			if not condition_id.is_empty():
				target.call("set_condition", condition_id, true)

	if bool(spell_data.get("forced_movement_on_failed_save", false)):
		var distance_feet: float = float(
			spell_data.get("forced_movement_feet", 0.0)
		)
		if distance_feet > 0.0 and target.has_method("apply_forced_movement"):
			var direction: Vector3 = (
				target.global_position
				- _saving_throw_caster_origin
			)
			direction.y = 0.0
			if direction.length_squared() > 0.0001:
				target.call(
					"apply_forced_movement",
					direction.normalized(),
					distance_feet / 5.0 * _cell_size()
				)


func _hide_all_spell_previews() -> void:
	_hide_spell_preview()
	_clear_spell_fixed_previews()
	_hide_spell_range_preview()
	_hide_wall_preview()


func _reset_cast_state(
	restore_mouse: bool,
	preserve_spell_highlight: bool = false
) -> void:
	if saving_throw_dialog != null and saving_throw_dialog.visible:
		saving_throw_dialog.hide()
	_saving_throw_targets.clear()
	_saving_throw_index = 0
	_saving_throw_undo_recorded = false
	_hide_all_spell_previews()
	if not preserve_spell_highlight:
		_set_spell_affected_targets([], false)
	if wall_mode_menu != null and wall_mode_menu.visible:
		wall_mode_menu.hide()
	if wall_orientation_menu != null and wall_orientation_menu.visible:
		wall_orientation_menu.hide()
	if summon_count_menu != null and summon_count_menu.visible:
		summon_count_menu.hide()
	board_root.set("_ui_owns_mouse", false)
	_pending_spell_id = ""
	_pending_spell_data.clear()
	_targeting_phase = ""
	_pending_caster = null
	_pending_targets.clear()
	_committed_targets.clear()
	_pending_target_points.clear()
	_pending_target_history.clear()
	_pending_chain_primary = null
	_summon_total_count = 1
	_summon_created_count = 0
	_transformation_dialog_targets.clear()
	_transformation_dialog_index = 0
	_directional_pitch_degrees = 0
	_wall_mode = ""
	_wall_points.clear()
	_wall_center = Vector3.ZERO
	_wall_radius_world = 0.0
	_wall_sweep = 0.0
	_wall_damage_side = 0
	_wall_orientation = ""
	if instruction_label != null:
		instruction_label.hide()
	if restore_mouse:
		Input.mouse_mode = _restore_mouse_mode


func _return_control_to_camera() -> void:
	if not _remote_owner.is_empty():
		Input.mouse_mode = _remote_mouse_restore
		board_root.set("_ui_owns_mouse", _remote_ui_restore)
		return
	if board_root != null and is_instance_valid(board_root):
		if board_root.has_method("capture_camera_control"):
			board_root.call("capture_camera_control")
			return
		board_root.set("_ui_owns_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _log_spell_use() -> void:
	if (
		_pending_caster == null
		or not is_instance_valid(_pending_caster)
	):
		return
	var spell_data := _pending_spell()
	if spell_data.is_empty():
		return
	var roller_value: Variant = board_root.get("dice_roller_chat")
	if not roller_value is Node:
		return
	var roller := roller_value as Node
	if (
		roller == null
		or not is_instance_valid(roller)
		or not roller.has_method("log_action")
	):
		return
	var spell_name := String(
		spell_data.get("name", "Incantesimo")
	).strip_edges()
	if spell_name.is_empty():
		spell_name = "Incantesimo"
	roller.call(
		"log_action",
		"usa %s" % spell_name,
		_pending_caster
	)


func _finish_cast() -> void:
	if not _remote_owner.is_empty():
		_remote_outcome = "completed"
	# Applying spell origins during targeting previews would leave effects
	# behind if the user presses Esc. Commit exactly once at successful finish.
	if board_root != null and is_instance_valid(board_root) and board_root.has_method("apply_cast_spell_effects"):
		var resolved_targets: Array = _committed_targets.duplicate()
		if not _spell_needs_saving_throw_resolution(_pending_spell()):
			for target: Node3D in _pending_targets:
				if target != null and is_instance_valid(target) and not (target in resolved_targets):
					resolved_targets.append(target)
		if (
			resolved_targets.is_empty()
			and _pending_caster != null
			and String(_pending_spell().get("target_mode", "")) in [
				"self_token", "self_emanation", "transform_self", "teleport_self"
			]
		):
			resolved_targets.append(_pending_caster)
		board_root.call("apply_cast_spell_effects", _pending_caster, _pending_spell(), resolved_targets)
	_log_spell_use()
	# The red hitbox is a *targeting preview*, never a persistent condition.
	# Clear it as soon as the cast finishes. Confirmed point AoEs explicitly
	# reapply their area geometry in _commit_point_spell_cast(), so the click-
	# to-dismiss area workflow remains unchanged.
	var measurement: Node = _measurement_tool()
	_post_cast_cleanup_pending = (
		measurement != null
		and measurement.has_method("has_post_cast_spell_visuals")
		and bool(measurement.call("has_post_cast_spell_visuals"))
	)
	_reset_cast_state(false, false)
	_return_control_to_camera()


func _cancel_pending_cast(restore_mouse: bool = true) -> void:
	if not _remote_owner.is_empty() and not _remote_starting:
		_remote_outcome = "cancelled"
	if board_root != null and is_instance_valid(board_root) and board_root.has_method("cancel_origin_spell_cast"):
		board_root.call("cancel_origin_spell_cast", _pending_caster, _pending_spell())
	_post_cast_cleanup_pending = false
	_reset_cast_state(false, false)
	if restore_mouse:
		_return_control_to_camera()


func _adjust_directional_pitch(delta_degrees: int) -> void:
	_directional_pitch_degrees = clampi(
		_directional_pitch_degrees + delta_degrees,
		-90,
		90
	)
	var spell_data: Dictionary = _pending_spell()
	_update_directional_instruction(spell_data)


func _update_directional_instruction(spell_data: Dictionary) -> void:
	var pitch_label: String = "frontale"
	if _directional_pitch_degrees > 0:
		pitch_label = "+%d° verso l'alto" % _directional_pitch_degrees
	elif _directional_pitch_degrees < 0:
		pitch_label = "%d° verso il basso" % abs(_directional_pitch_degrees)

	_set_instruction(
		"%s: mira un token e clicca · ↑/↓ inclinazione: %s · WASD + mouse per muoverti · Esc per annullare"
		% [
			String(spell_data.get("name", "Incantesimo")),
			pitch_label
		]
	)




func _configure_slot_selector(spell_data: Dictionary) -> void:
	var base_level: int = int(spell_data.get("level", 0))
	slot_selector.clear()
	if base_level <= 0:
		_selected_slot_level = 0
		slot_row.hide()
		return

	for slot_level: int in range(base_level, 10):
		slot_selector.add_item("%d° livello" % slot_level, slot_level)
	slot_selector.select(0)
	_selected_slot_level = base_level
	slot_row.show()


func _on_slot_selected(index: int) -> void:
	if index < 0 or index >= slot_selector.item_count:
		return
	_selected_slot_level = slot_selector.get_item_id(index)


func _effective_aoe_radius_feet(spell_data: Dictionary) -> float:
	var base_radius: float = float(
		spell_data.get("aoe_radius_feet", 5.0)
	)
	var base_level: int = int(spell_data.get("level", 0))
	var per_slot: float = float(
		spell_data.get("radius_per_slot_above_base", 0.0)
	)
	if base_level <= 0 or _selected_slot_level <= base_level:
		return base_radius
	return (
		base_radius
		+ per_slot * float(_selected_slot_level - base_level)
	)


func _required_target_clicks(spell_data: Dictionary) -> int:
	var base_count: int = int(spell_data.get("base_target_clicks", 1))
	var base_level: int = int(spell_data.get("level", 0))
	var per_slot: int = int(
		spell_data.get("target_clicks_per_slot_above_base", 0)
	)
	return maxi(
		1,
		base_count
		+ per_slot * maxi(0, _selected_slot_level - base_level)
	)


func _update_multi_target_instruction(spell_data: Dictionary) -> void:
	var required: int = _required_target_clicks(spell_data)
	var repeat_note: String = (
		" · puoi selezionare più volte lo stesso bersaglio"
		if bool(spell_data.get("allow_repeat_targets", true))
		else ""
	)
	var undo_note: String = (
		" · Backspace annulla ultima selezione"
		if not _pending_target_history.is_empty()
		else ""
	)
	_set_instruction(
		"%s: scegli i bersagli %d/%d%s%s · Esc annulla incantesimo"
		% [
			String(spell_data.get("name", "Incantesimo")),
			_pending_targets.size() + _pending_target_points.size(),
			required,
			repeat_note,
			undo_note
		]
	)


func _required_chain_secondaries(spell_data: Dictionary) -> int:
	var base_count: int = int(
		spell_data.get("base_secondary_targets", 3)
	)
	var base_level: int = int(spell_data.get("level", 6))
	var per_slot: int = int(
		spell_data.get("secondary_targets_per_slot_above_base", 0)
	)
	return maxi(
		1,
		base_count
		+ per_slot * maxi(0, _selected_slot_level - base_level)
	)


func _update_chain_instruction(spell_data: Dictionary) -> void:
	var required: int = _required_chain_secondaries(spell_data)
	_set_instruction(
		"%s: scegli bersagli secondari entro %d ft dal primo %d/%d · Invio per terminare prima · Esc per annullare"
		% [
			String(spell_data.get("name", "Incantesimo")),
			int(spell_data.get("secondary_range_feet", 30)),
			_pending_targets.size(),
			required
		]
	)


func _direction_limit_feet(spell_data: Dictionary) -> float:
	if spell_data.has("direction_limit_feet"):
		return maxf(
			float(spell_data.get("direction_limit_feet", 0.0)),
			5.0
		)
	return _effective_spell_range_feet(spell_data, _pending_caster)


func _spell_style(spell_data: Dictionary) -> String:
	return String(
		spell_data.get(
			"visual_style",
			spell_data.get("id", "")
		)
	)


func _measurement_tool() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null
	return board_root.get_node_or_null("MeasurementTool")


func _cell_size() -> float:
	return maxf(float(board_root.get("cell_size")), 0.001)


func _token_target_distance_feet(source: Node3D, target: Node3D) -> float:
	# Match precisely the metric used by the on-board reach arrows, including
	# corner adjacency, vertical offsets and both tokens' occupied cells.
	return ReachGeometry.token_tactical_distance_feet(
		source, target, _cell_size()
	)


func _effective_spell_range_feet(
	spell_data: Dictionary,
	_caster: Node3D = null
) -> float:
	var configured_range: float = float(spell_data.get("range_feet", 0.0))
	var range_label: String = String(
		spell_data.get("range", "")
	).strip_edges().to_lower()

	# Nel VTT Touch occupa sempre la cella adiacente: 5 ft. La reach della
	# creatura resta una proprietà separata per attacchi/opportunità e non
	# può ridurre o ampliare la gittata di un incantesimo Touch.
	if range_label.begins_with("touch"):
		return 5.0

	# Nessuna gittata tattica può collassare a 0: anche dati incompleti,
	# Self o vecchie entry senza range_feet mantengono il minimo di una cella.
	return maxf(configured_range, 5.0)


func _set_instruction(message: String) -> void:
	if not _remote_owner.is_empty() and is_targeting():
		_remote_instruction = message
		return
	instruction_label.text = message
	instruction_label.show()


# Snapshot input is an alternate pointer source for the existing targeting
# lifecycle, not a second implementation of spell mechanics or AoE geometry.
func begin_remote_spell(caster: Node3D, owner: String, request: Dictionary) -> Dictionary:
	if is_targeting():
		return {"ok": false, "error": "Un incantesimo è già in selezione sulla board. Completa o annulla prima quello."}
	_remote_owner = owner
	_remote_caster = caster
	_remote_outcome = "active"
	_remote_instruction = ""
	_remote_mouse_restore = Input.mouse_mode
	_remote_ui_restore = bool(board_root.get("_ui_owns_mouse"))
	_remote_starting = true
	_remote_input_active = true
	var context: Dictionary = {}
	var raw: Variant = request.get("context", {})
	if raw is Dictionary:
		for key: String in ["spellcasting_ability", "spell_attack_bonus", "spell_save_dc", "source_class"]:
			if raw.has(key):
				context[key] = raw[key]
	var accepted := activate_spell_from_caster(String(request.get("spell_id", "")), caster,
		String(request.get("name", "")), String(request.get("source", "")), int(request.get("slot_level", -1)), context)
	_remote_starting = false
	_remote_input_active = false
	Input.mouse_mode = _remote_mouse_restore
	board_root.set("_ui_owns_mouse", _remote_ui_restore)
	if not accepted:
		_remote_owner = ""
		_remote_caster = null
		return {"ok": false, "error": "Questo incantesimo non ha un effetto attivabile sulla board."}
	return {"ok": true, "targeting": remote_targeting_status(caster, owner)}

func remote_targeting_status(caster: Node3D, owner: String) -> Dictionary:
	if owner.is_empty() or owner != _remote_owner or caster != _remote_caster:
		return {}
	var selected: Array[String] = []
	for token: Node3D in _pending_targets:
		if is_instance_valid(token) and token.has_method("get_token_id"):
			selected.append(String(token.call("get_token_id")))
	return {"active": is_targeting(), "phase": _targeting_phase, "outcome": _remote_outcome,
		"instruction": ("Risolvi la scelta o il tiro salvezza sul desktop, poi premi Aggiorna." if _targeting_phase in ["saving_throw", "summon_count", "summon_token_dialog", "transform_token_dialog", "resize_token_dialog", "wall_mode", "wall_orientation"] else "Tocca un bersaglio o un punto sulla mappa. Selezioni: %d." % _pending_target_history.size()), "selected_ids": selected,
		"range_feet": _effective_spell_range_feet(_pending_spell(), caster) if is_targeting() else 0.0,
		"area_shape": String(_pending_spell().get("aoe_shape", "")),
		"area_radius_feet": _effective_aoe_radius_feet(_pending_spell()),
		"area_side_feet": float(_pending_spell().get("aoe_side_feet", 10))}

func remote_target_input(caster: Node3D, owner: String, target: Node3D, point: Dictionary, command: String) -> Dictionary:
	if owner != _remote_owner or caster != _remote_caster:
		return {"ok": false, "error": "Nessun incantesimo di questa creatura è in selezione."}
	if not is_targeting():
		return {"ok": true, "targeting": remote_targeting_status(caster, owner)}
	_remote_input_active = true
	_remote_pick_token = target
	_remote_pick_point = point
	var previous_mouse := Input.mouse_mode
	var previous_ui: bool = bool(board_root.get("_ui_owns_mouse"))
	if command == "cancel":
		_cancel_pending_cast(false)
		_return_control_to_camera()
	elif command == "finish":
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_ENTER
		handle_input(key)
	else:
		_update_spell_preview()
		_confirm_targeting_selection(Vector2.ZERO)
	_remote_input_active = false
	_remote_pick_token = null
	_remote_pick_point = {}
	if is_targeting() and _targeting_phase != "saving_throw":
		Input.mouse_mode = previous_mouse
		board_root.set("_ui_owns_mouse", previous_ui)
	return {"ok": true, "targeting": remote_targeting_status(caster, owner)}

func remote_preview_input(caster: Node3D, owner: String, point: Dictionary, projection: Dictionary) -> Dictionary:
	if owner != _remote_owner or caster != _remote_caster or not is_targeting():
		return {"ok": false, "error": "Nessun incantesimo di questa creatura è in selezione."}
	_remote_input_active = true
	_remote_pick_token = null
	_remote_pick_point = point
	_update_spell_preview()
	_remote_input_active = false
	_remote_pick_point = {}
	var contour: Array = _overlay_2d.mobile_preview_contour(projection) if is_instance_valid(_overlay_2d) else []
	var affected: Array[String] = []
	var measure: Node = _measurement_tool()
	if contour.size() >= 3:
		var touched: Array = measure.call(
			"spell_geometry_affected_tokens",
			measure.get("_spell_preview_start"),
			measure.get("_spell_preview_end"),
			String(measure.get("_spell_preview_shape")),
			String(measure.get("_spell_preview_style")),
			float(measure.get("_spell_preview_line_width"))
		)
		for token: Node3D in _filter_spell_affected_targets(
			touched, _pending_spell(), _pending_caster
		):
			if board_root.is_ancestor_of(token) and token.is_visible_in_tree() and token.has_method("get_token_id"):
				affected.append(String(token.call("get_token_id")))
	return {"ok": true, "preview": {"points": contour, "valid": not contour.is_empty(), "affected_ids": affected}}
