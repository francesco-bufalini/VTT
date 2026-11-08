extends Control
## Fixed-size grid for calibrating map images without resizing the grid itself.

const PIXELS_PER_CELL := 26.0
const GRID_COLOR := Color(0.83, 0.91, 1.0, 0.67)
const ORIGIN_COLOR := Color(1.0, 0.72, 0.29, 0.95)

var map_texture: Texture2D
var width_cells := 12.0
var height_cells := 12.0
var offset_x := 0.0
var offset_z := 0.0


func set_preview(
	texture: Texture2D, width_value: float, height_value: float,
	x_value: float, z_value: float
) -> void:
	map_texture = texture
	width_cells = width_value
	height_cells = height_value
	offset_x = x_value
	offset_z = z_value
	queue_redraw()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.085, 0.105))
	var center: Vector2 = size * 0.5
	if map_texture != null:
		var image_size := Vector2(width_cells, height_cells) * PIXELS_PER_CELL
		var image_center := center + Vector2(offset_x, offset_z) * PIXELS_PER_CELL
		draw_texture_rect(
			map_texture,
			Rect2(image_center - image_size * 0.5, image_size),
			false
		)
	# Grid spacing and origin never depend on image dimensions or offsets.
	var start_x := fposmod(center.x, PIXELS_PER_CELL)
	var start_y := fposmod(center.y, PIXELS_PER_CELL)
	for column: int in range(ceili(size.x / PIXELS_PER_CELL) + 1):
		var x := start_x + float(column) * PIXELS_PER_CELL
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID_COLOR, 1.0)
	for row: int in range(ceili(size.y / PIXELS_PER_CELL) + 1):
		var y := start_y + float(row) * PIXELS_PER_CELL
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR, 1.0)
	draw_line(
		Vector2(center.x, 0), Vector2(center.x, size.y),
		ORIGIN_COLOR, 1.5
	)
	draw_line(
		Vector2(0, center.y), Vector2(size.x, center.y),
		ORIGIN_COLOR, 1.5
	)
