extends Node3D

# Coordinates use the template grid's world origin and cell_size.
@export var cells: Rect2i = Rect2i(-38, 0, 76, 114)
@export var excluded_cells: Array[Vector2i] = []

func contains_cell(cell: Vector2i) -> bool:
	return cells.has_point(cell) and not excluded_cells.has(cell)

func get_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(cells.position.x, cells.end.x):
		for z in range(cells.position.y, cells.end.y):
			var cell := Vector2i(x, z)
			if contains_cell(cell):
				result.append(cell)
	return result
