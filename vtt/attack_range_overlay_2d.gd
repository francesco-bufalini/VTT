extends Control

const RangeGeometry = preload("res://vtt/attack_range_geometry.gd")
const NORMAL_COLOR := Color(0.22, 0.68, 1.0, 0.96)
const LONG_COLOR := Color(1.0, 0.61, 0.22, 0.98)

var board: Node3D
var attack: Node
var camera: Camera3D
var _was_active: bool = false


func setup(root: Node3D, attack_system: Node) -> void:
	board = root
	attack = attack_system
	camera = root.get_node_or_null("Camera3D") as Camera3D
	name = "AttackRangeOverlay2D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 70


func _active() -> bool:
	return (
		board != null and is_instance_valid(board)
		and attack != null and is_instance_valid(attack)
		and camera != null and is_instance_valid(camera)
		and board.has_method("is_2d_view_enabled")
		and bool(board.call("is_2d_view_enabled"))
		and (
			bool(attack.call("is_targeting"))
			or bool(attack.call("are_all_reaches_visible"))
		)
	)


func _process(_delta: float) -> void:
	var active_now: bool = _active()
	if active_now or _was_active:
		queue_redraw()
	_was_active = active_now


func _screen_polygon(center: Vector3, half_footprint: float, radius: float) -> PackedVector2Array:
	var floor_y: float = (
		float(camera.call("get_top_down_level"))
		if camera.has_method("get_top_down_level")
		else center.y
	)
	var vertices: PackedVector2Array = RangeGeometry.rounded_footprint_perimeter(
		half_footprint, radius
	)
	var projected := PackedVector2Array()
	for v: Vector2 in vertices:
		projected.append(
			camera.unproject_position(Vector3(center.x + v.x, floor_y, center.z + v.y))
		)
	return projected


func _paint_range(vertices: PackedVector2Array, tint: Color, fill_alpha: float) -> void:
	if vertices.size() < 3:
		return
	var fill: Color = tint
	fill.a = fill_alpha
	draw_colored_polygon(vertices, fill)
	var closed: PackedVector2Array = PackedVector2Array(vertices)
	closed.append(vertices[0])
	draw_polyline(closed, tint, 2.8, true)


func _draw_legend(normal_feet: float, long_feet: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var normal_text: String = "Normale  %d ft" % int(round(normal_feet))
	var has_long: bool = long_feet > normal_feet
	var outer_text: String = "Lunga  %d ft  (svantaggio)" % int(round(long_feet))
	var panel_width: float = 278.0 if has_long else 174.0
	var panel_height: float = 64.0 if has_long else 40.0
	var pos: Vector2 = Vector2(maxf(8.0, size.x - panel_width - 18.0), 76.0)
	draw_rect(Rect2(pos, Vector2(panel_width, panel_height)), Color(0.03, 0.045, 0.07, 0.88))
	draw_rect(Rect2(pos, Vector2(panel_width, panel_height)), Color(0.48, 0.57, 0.66, 0.65), false, 1.0)
	draw_circle(pos + Vector2(13.0, 21.0), 4.0, NORMAL_COLOR)
	draw_string(font, pos + Vector2(25.0, 26.0), normal_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color.WHITE)
	if has_long:
		draw_circle(pos + Vector2(13.0, 46.0), 4.0, LONG_COLOR)
		draw_string(font, pos + Vector2(25.0, 51.0), outer_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color.WHITE)


func _draw() -> void:
	if not _active():
		return
	if not bool(attack.call("is_targeting")):
		_draw_all_reaches()
		return
	var caster: CharacterBody3D = attack.get("_attacker") as CharacterBody3D
	if caster == null or not is_instance_valid(caster):
		return
	var normal_feet: float = float(attack.get("_range_normal_feet"))
	var long_feet: float = float(attack.get("_range_long_feet"))
	var cell_size: float = maxf(0.001, float(board.get("cell_size")))
	if normal_feet <= 0.0:
		return
	var half_footprint: float = cell_size * 0.5
	if caster.has_method("get_footprint_cells"):
		half_footprint *= maxf(0.5, float(caster.call("get_footprint_cells")))
	if long_feet > normal_feet:
		_paint_range(
			_screen_polygon(caster.global_position, half_footprint, long_feet / 5.0 * cell_size),
			LONG_COLOR, 0.035
		)
	_paint_range(
		_screen_polygon(caster.global_position, half_footprint, normal_feet / 5.0 * cell_size),
		NORMAL_COLOR, 0.055
	)
	_draw_legend(normal_feet, long_feet)



func _draw_all_reaches() -> void:
	# The global reach toggle displays the current weapon of each token.
	# Show both outlines for ranged weapons; do not draw many translucent
	# overlapping discs when several creatures occupy the same battlefield.
	var cell_size: float = maxf(0.001, float(board.get("cell_size")))
	for value: Variant in attack.call("_reach_tokens"):
		if not value is CharacterBody3D:
			continue
		var token: CharacterBody3D = value as CharacterBody3D
		if token == null or not is_instance_valid(token):
			continue
		var normal_feet: float = 5.0
		if token.has_method("get_reach_feet"):
			normal_feet = maxf(5.0, float(token.call("get_reach_feet")))
		var long_feet: float = float(token.get_meta("active_weapon_long_range_feet", 0.0))
		var half_footprint: float = cell_size * 0.5
		if token.has_method("get_footprint_cells"):
			half_footprint *= maxf(0.5, float(token.call("get_footprint_cells")))
		if long_feet > normal_feet:
			_paint_range(
				_screen_polygon(token.global_position, half_footprint, long_feet / 5.0 * cell_size),
				LONG_COLOR, 0.0
			)
		_paint_range(
			_screen_polygon(token.global_position, half_footprint, normal_feet / 5.0 * cell_size),
			NORMAL_COLOR, 0.0
		)
