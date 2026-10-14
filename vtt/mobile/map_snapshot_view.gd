extends Control
## A cached map with client-side zoom/pan. Coordinates always map back to
## the original image, so selection never drifts when magnified or dragged.
signal map_tapped(pixel: Vector2, target_id: String)
var texture: ImageTexture
var snapshot: Dictionary = {}
var zoom := 1.0
var pan := Vector2.ZERO
var selected_ids: Array[String] = []
var _fingers: Dictionary = {}
var _last_center := Vector2.ZERO
var _last_distance := 0.0
var _gesture_start := Vector2.ZERO
var _gesture_moved := false
var _mouse_down := false

func load_snapshot(value: Dictionary) -> bool:
	if value.get("format") != "webp" or not value.get("image") is String or String(value.image).length() > 1800000:
		return false
	var image := Image.new()
	if image.load_webp_from_buffer(Marshalls.base64_to_raw(value.image)) != OK or image.is_empty():
		return false
	if image.get_width() > 2048 or image.get_height() > 2048:
		return false
	var same_view: bool = snapshot.get("token_id", "") == value.get("token_id", "") and is_equal_approx(float(snapshot.get("field_feet", 0)), float(value.get("field_feet", 0)))
	texture = ImageTexture.create_from_image(image)
	snapshot = value.duplicate(true)
	if not same_view:
		zoom = 1.0
		pan = Vector2.ZERO
	_clamp_pan()
	queue_redraw()
	return true

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void: _clamp_pan(); queue_redraw())

func _base_scale() -> float:
	return minf(size.x / float(texture.get_width()), size.y / float(texture.get_height())) if texture != null else 1.0

func _base_origin() -> Vector2:
	return (size - Vector2(texture.get_size()) * _base_scale()) * 0.5 if texture != null else Vector2.ZERO

func image_to_local(pixel: Vector2) -> Vector2:
	return _base_origin() + pan + pixel * _base_scale() * zoom

func local_to_image(point: Vector2) -> Vector2:
	return (point - _base_origin() - pan) / maxf(0.0001, _base_scale() * zoom)

func _clamp_pan() -> void:
	if texture == null:
		return
	var extent := Vector2(texture.get_size()) * _base_scale() * zoom
	var origin := _base_origin() + pan
	for axis: int in range(2):
		origin[axis] = (size[axis] - extent[axis]) * 0.5 if extent[axis] <= size[axis] else clampf(origin[axis], size[axis] - extent[axis], 0.0)
	pan = origin - _base_origin()

func zoom_by(factor: float, anchor: Vector2 = Vector2(-1, -1)) -> void:
	if texture == null:
		return
	if anchor.x < 0:
		anchor = size * 0.5
	var pixel := local_to_image(anchor)
	zoom = clampf(zoom * factor, 1.0, 8.0)
	pan = anchor - _base_origin() - pixel * _base_scale() * zoom
	_clamp_pan()
	queue_redraw()

func _gesture_center() -> Vector2:
	var center := Vector2.ZERO
	for value: Vector2 in _fingers.values():
		center += value
	return center / maxf(1, _fingers.size())

func _gesture_distance() -> float:
	return (_fingers.values()[0] as Vector2).distance_to(_fingers.values()[1]) if _fingers.size() >= 2 else 0.0

func handle_screen_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var local: Vector2 = event.position - global_position
		if event.pressed:
			if _fingers.is_empty() and not Rect2(Vector2.ZERO, size).has_point(local):
				return false
			if _fingers.is_empty():
				_gesture_start = local
				_gesture_moved = false
			else:
				_gesture_moved = true
			_fingers[event.index] = local
			_last_center = _gesture_center()
			_last_distance = _gesture_distance()
			return true
		if not _fingers.has(event.index):
			return false
		var tap: bool = _fingers.size() == 1 and not _gesture_moved and not event.canceled
		_fingers.erase(event.index)
		_last_center = _gesture_center()
		_last_distance = _gesture_distance()
		if tap:
			_tap(local)
		return true
	if event is InputEventScreenDrag and _fingers.has(event.index):
		var local: Vector2 = event.position - global_position
		_fingers[event.index] = local
		var center := _gesture_center()
		var distance := _gesture_distance()
		if _fingers.size() >= 2:
			_gesture_moved = true
			pan += center - _last_center
			if _last_distance > 1.0 and distance > 1.0:
				zoom_by(distance / _last_distance, center)
		elif local.distance_to(_gesture_start) >= 10 or _gesture_moved:
			_gesture_moved = true
			pan += center - _last_center
		_clamp_pan()
		_last_center = center
		_last_distance = distance
		queue_redraw()
		return true
	return false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
	elif event is InputEventPanGesture:
		pan -= event.delta * 20
		_clamp_pan()
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.2, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.0 / 1.2, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_gesture_start = event.position
				_gesture_moved = false
			elif _mouse_down:
				_mouse_down = false
				if not _gesture_moved:
					_tap(event.position)
	elif event is InputEventMouseMotion and _mouse_down:
		if event.position.distance_to(_gesture_start) >= 10 or _gesture_moved:
			_gesture_moved = true
			pan += event.relative
			_clamp_pan()
			queue_redraw()

func _tap(local: Vector2) -> void:
	if texture == null:
		return
	var pixel := local_to_image(local)
	if not Rect2(Vector2.ZERO, Vector2(texture.get_size())).has_point(pixel):
		return
	var id := ""
	var best := INF
	for marker: Dictionary in snapshot.get("markers", []):
		var delta := pixel - Vector2(float(marker.x), float(marker.y))
		var distance := delta.length()
		var threshold := maxf(float(marker.radius), 20.0 / maxf(_base_scale() * zoom, 0.001))
		if distance <= threshold and distance < best:
			best = distance
			id = String(marker.get("id", ""))
	map_tapped.emit(pixel, id)

func _draw() -> void:
	if texture == null:
		return
	var scale_factor := _base_scale() * zoom
	var extent := Vector2(texture.get_size()) * scale_factor
	draw_texture_rect(texture, Rect2(image_to_local(Vector2.ZERO), extent), false)
	for contour: Dictionary in snapshot.get("contours", []):
		var points := PackedVector2Array()
		for point: Array in contour.get("points", []):
			points.append(image_to_local(Vector2(float(point[0]), float(point[1]))))
		if points.size() < 2:
			continue
		points.append(points[0])
		draw_polyline(points, Color("ffaa42") if bool(contour.get("long", false)) else Color("61ed86"), 2.0, true)
	var font := ThemeDB.fallback_font
	for marker: Dictionary in snapshot.get("markers", []):
		var point := image_to_local(Vector2(float(marker.x), float(marker.y)))
		var radius := maxf(4.0, float(marker.radius) * scale_factor)
		var color := Color("ffdc70") if bool(marker.get("selected", false)) else Color("a5d6fa")
		if String(marker.get("id", "")) in selected_ids or bool(marker.get("affected", false)):
			color = Color("ff6666")
		draw_rect(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2), color, false, 2)
		var label := String(marker.get("name", ""))
		var label_point := point + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, radius + 16)
		draw_string_outline(font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
		var cells := int(marker.get("elevation_cells", 0))
		if cells != 0:
			var altitude := "%+d □" % cells
			var altitude_point := point + Vector2(radius + 4, 4)
			draw_string_outline(font, altitude_point, altitude, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
			draw_string(font, altitude_point, altitude, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var status := String(marker.get("status_text", ""))
		if not status.is_empty():
			var status_point := point + Vector2(-radius, -radius - 5)
			draw_string_outline(font, status_point, status, HORIZONTAL_ALIGNMENT_LEFT, 200, 12, 3, Color.BLACK)
			draw_string(font, status_point, status, HORIZONTAL_ALIGNMENT_LEFT, 200, 12, Color.WHITE)
