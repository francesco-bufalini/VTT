extends Node

# A mount is any other creature token or an item with a stable item_id.
# Mounted riders remain regular tokens with their own sheets and initiative.
const KIND_TOKEN := "token"
const KIND_ITEM := "item"
const META_KIND := "mount_target_kind"
const META_ID := "mount_target_id"
const META_LOCAL := "mount_local_position"

var board: Node3D


func setup(owner_board: Node3D) -> void:
	board = owner_board
	# Run after token physics and ItemController (-10).
	process_physics_priority = 100


func _physics_process(_delta: float) -> void:
	refresh_all()


func is_mounted(rider: CharacterBody3D) -> bool:
	return rider != null and is_instance_valid(rider) and not String(
		rider.get_meta(META_ID, "")
	).is_empty()


func get_target(rider: CharacterBody3D) -> Node3D:
	if not is_mounted(rider) or board == null:
		return null
	var identity := String(rider.get_meta(META_ID, ""))
	var kind := String(rider.get_meta(META_KIND, ""))
	if kind == KIND_TOKEN:
		for value: Node in get_tree().get_nodes_in_group("dnd_token"):
			if (
				value is CharacterBody3D
				and board.is_ancestor_of(value)
				and not value.is_queued_for_deletion()
				and value.has_method("get_token_id")
				and String(value.call("get_token_id")) == identity
			):
				return value as Node3D
	elif kind == KIND_ITEM and board.get("item_controller") != null:
		for item: StaticBody3D in board.item_controller.items:
			if is_instance_valid(item) and String(item.get("item_id")) == identity:
				return item
	return null


func can_mount(rider: CharacterBody3D, target: Node3D) -> bool:
	if rider == null or target == null or not is_instance_valid(target):
		return false
	if rider == target or not board.is_ancestor_of(rider):
		return false
	if not board.is_ancestor_of(target):
		return false
	if not (
		(target is CharacterBody3D and target.is_in_group("dnd_token"))
		or (target is StaticBody3D and target.is_in_group("dnd_item"))
	):
		return false
	# Do not allow mount chains that loop back onto their own rider.
	var ancestor: Node3D = target
	var visited: Dictionary = {}
	while ancestor is CharacterBody3D:
		if ancestor == rider:
			return false
		if visited.has(ancestor):
			return false
		visited[ancestor] = true
		ancestor = get_target(ancestor as CharacterBody3D)
	return true


func mount(rider: CharacterBody3D, target: Node3D) -> bool:
	if not can_mount(rider, target):
		return false
	var kind := KIND_TOKEN if target is CharacterBody3D else KIND_ITEM
	var identity := (
		String(target.call("get_token_id"))
		if kind == KIND_TOKEN
		else String(target.get("item_id"))
	)
	if identity.is_empty():
		return false
	var rider_half_height := _half_height(rider)
	var world_position := target.global_position
	if kind == KIND_TOKEN:
		var deck: Node3D = target.get_node_or_null("ChariotDeck") as Node3D
		if deck != null and is_instance_valid(deck):
			world_position = deck.to_global(
				Vector3.UP * (rider_half_height + 0.01 * board.cell_size)
			)
		else:
			world_position.y += _half_height(target as CharacterBody3D) + rider_half_height
	else:
		world_position = target.to_global(
			Vector3.UP * (rider_half_height + 0.01 * board.cell_size)
		)
	rider.set_meta(META_KIND, kind)
	rider.set_meta(META_ID, identity)
	rider.set_meta(META_LOCAL, target.to_local(world_position))
	# Prevent gravity and incidental floor-support detection from fighting the mount.
	if rider.has_method("set_flying"):
		rider.call("set_flying", true)
	rider.set("grid_support", null)
	rider.global_position = world_position
	rider.velocity = Vector3.ZERO
	return true


func dismount(rider: CharacterBody3D) -> void:
	if rider == null or not is_instance_valid(rider):
		return
	for key: String in [META_KIND, META_ID, META_LOCAL]:
		if rider.has_meta(key):
			rider.remove_meta(key)
	# Leave the token suspended at its current height. Gravity is an explicit
	# VTT action and should not automatically trigger when dismounting.


func refresh_all() -> void:
	if board == null or not is_instance_valid(board):
		return
	var visited: Dictionary = {}
	for value: Node in get_tree().get_nodes_in_group("dnd_token"):
		if value is CharacterBody3D and board.is_ancestor_of(value):
			_follow(value as CharacterBody3D, visited, {})


func _follow(rider: CharacterBody3D, visited: Dictionary, ancestors: Dictionary) -> void:
	if visited.has(rider):
		return
	if ancestors.has(rider):
		dismount(rider)
		return
	ancestors[rider] = true
	if not is_mounted(rider):
		visited[rider] = true
		return
	var target: Node3D = get_target(rider)
	if target == null or target == rider:
		dismount(rider)
		visited[rider] = true
		return
	if target is CharacterBody3D:
		_follow(target as CharacterBody3D, visited, ancestors)
	if not is_mounted(rider):
		visited[rider] = true
		return
	var local_value: Variant = rider.get_meta(META_LOCAL, Vector3.ZERO)
	var local: Vector3 = local_value if local_value is Vector3 else Vector3.ZERO
	rider.global_position = target.to_global(local)
	rider.velocity = Vector3.ZERO
	rider.set("grid_support", null)
	visited[rider] = true


func _half_height(token: CharacterBody3D) -> float:
	return maxf(float(token.get("token_height_cells")), 0.1) * maxf(
		float(token.get("cell_size")), 0.001
	) * 0.5
