extends Node

enum CellState { NORMAL, THREATENED, COLLAPSED }
const NEIGHBORS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var threatened_cells: Array[Vector2i] = []
var collapsed_cells: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()
var config: Resource
var allowed_area: Node3D
var cell_size: float = 1.0
var _collapsed: Dictionary = {}
var collapse_geometry: Node3D

func initialize(settings: Resource, area: Node3D, size: float, seed_value: int) -> void:
	config = settings
	allowed_area = area
	cell_size = size
	rng.seed = seed_value
	threatened_cells.clear()
	collapsed_cells.clear()
	_collapsed.clear()

func generate_threats() -> void:
	threatened_cells.clear()
	var available: Array[Vector2i] = []
	for cell: Vector2i in allowed_area.get_cells():
		if not _collapsed.has(cell):
			available.append(cell)
	var selected: Dictionary = {}
	var count := rng.randi_range(config.hazard_cluster_min, maxi(config.hazard_cluster_min, config.hazard_cluster_max))
	for _cluster in range(count):
		if available.is_empty():
			break
		var start := available[rng.randi_range(0, available.size() - 1)]
		var frontier: Array[Vector2i] = [start]
		var queued: Dictionary = {start: true}
		var size := rng.randi_range(config.hazard_cluster_size_min, maxi(config.hazard_cluster_size_min, config.hazard_cluster_size_max))
		for _cell_index in range(size):
			if frontier.is_empty():
				break
			var index := rng.randi_range(0, frontier.size() - 1)
			var cell := frontier[index]
			frontier.remove_at(index)
			selected[cell] = true
			available.erase(cell)
			threatened_cells.append(cell)
			for offset: Vector2i in NEIGHBORS:
				var neighbor := cell + offset
				if allowed_area.contains_cell(neighbor) and not _collapsed.has(neighbor) and not selected.has(neighbor) and not queued.has(neighbor):
					queued[neighbor] = true
					frontier.append(neighbor)

func resolve_threats() -> Array[Vector2i]:
	var resolved: Array[Vector2i] = threatened_cells.duplicate()
	for cell in resolved:
		_collapsed[cell] = true
		collapsed_cells.append(cell)
	threatened_cells.clear()
	return resolved

func get_cell_state(cell: Vector2i) -> CellState:
	if _collapsed.has(cell):
		return CellState.COLLAPSED
	return CellState.THREATENED if threatened_cells.has(cell) else CellState.NORMAL

func can_move_token(token: CharacterBody3D, destination: Vector3) -> bool:
	# Ground hazards must not block flight or the moving shoulder deck.
	var feet_y: float = destination.y - token.token_height_cells * cell_size * 0.5
	if feet_y > 0.15 * cell_size:
		return true
	if not config.block_collapsed_cells:
		return true
	var extent: Vector2 = token.get_footprint_extent()
	var x_axis: Vector3 = token.global_basis.x.abs()*extent.x
	var z_axis: Vector3 = token.global_basis.z.abs()*extent.y
	var half := Vector2(x_axis.x+z_axis.x,x_axis.z+z_axis.z)*.5-Vector2.ONE*.001
	var low := Vector2i(floori((destination.x - half.x) / cell_size), floori((destination.z - half.y) / cell_size))
	var high := Vector2i(floori((destination.x + half.x) / cell_size), floori((destination.z + half.y) / cell_size))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			if _collapsed.has(Vector2i(x, z)):
				return false
	return true

func serialize_cells(cells_to_save: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell in cells_to_save:
		result.append([cell.x, cell.y])
	return result

func restore(threatened: Array, collapsed: Array, rng_state: int) -> void:
	threatened_cells.clear()
	collapsed_cells.clear()
	_collapsed.clear()
	for pair: Array in collapsed:
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		collapsed_cells.append(cell)
		_collapsed[cell] = true
	for pair: Array in threatened:
		threatened_cells.append(Vector2i(int(pair[0]), int(pair[1])))
	rng.state = rng_state
