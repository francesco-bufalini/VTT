extends Control
## Cached compressed map image with vector range contours and token markers.
var texture: ImageTexture
var snapshot: Dictionary = {}

func load_snapshot(value: Dictionary) -> bool:
	if value.get("format") != "webp" or not value.get("image") is String or String(value.image).length() > 1800000:
		return false
	var image := Image.new()
	if image.load_webp_from_buffer(Marshalls.base64_to_raw(value.image)) != OK or image.is_empty():
		return false
	if image.get_width() > 2048 or image.get_height() > 2048:
		return false
	texture = ImageTexture.create_from_image(image)
	snapshot = value.duplicate(true)
	queue_redraw()
	return true

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if texture == null:
		return
	var source := Vector2(texture.get_size())
	var scale_factor := minf(size.x / source.x, size.y / source.y)
	var extent := source * scale_factor
	var origin := (size - extent) * 0.5
	draw_texture_rect(texture, Rect2(origin, extent), false)
	for contour: Dictionary in snapshot.get("contours", []):
		var points := PackedVector2Array()
		for point: Array in contour.get("points", []):
			points.append(origin + Vector2(float(point[0]), float(point[1])) * scale_factor)
		if points.size() < 2:
			continue
		points.append(points[0])
		draw_polyline(points, Color("ffaa42") if bool(contour.get("long", false)) else Color("61ed86"), 2.0, true)
	var font := ThemeDB.fallback_font
	for marker: Dictionary in snapshot.get("markers", []):
		var point := origin + Vector2(float(marker.x), float(marker.y)) * scale_factor
		var radius := maxf(4.0, float(marker.radius) * scale_factor)
		var color := Color("ffdc70") if bool(marker.get("selected", false)) else Color("a5d6fa")
		draw_rect(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2), color, false, 1.5)
		var label := String(marker.get("name", ""))
		var label_point := point + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, radius + 14)
		draw_string_outline(font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
		draw_string(font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
