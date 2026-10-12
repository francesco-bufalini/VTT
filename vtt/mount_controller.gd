extends Node

# A linked token retains its position and facing relative to another token.
# Keep the existing mount metadata so old maps and network snapshots still load.
# Legacy item targets remain supported for saved scenes.
const KIND_TOKEN := "token"
const KIND_ITEM := "item"
const META_KIND := "mount_target_kind"
const META_ID := "mount_target_id"
const META_LOCAL := "mount_local_position"
const META_LOCAL_YAW := "mount_local_yaw"

var board: Node3D
# Temporary collision exceptions prevent members of a linked pair from
# blocking each other's movement. WeakRefs avoid retaining deleted tokens.
var _collision_links: Dictionary = {}


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
	# A cart cannot simultaneously follow its driver and carry that driver
	# as a mounted rider: this would create a transport dependency cycle.
	if target is StaticBody3D and rider.has_method("get_token_id"):
		if String(target.get("linked_token_id")) == String(rider.call("get_token_id")):
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
	# Capture the current transform instead of lifting or centering the
	# follower on its leader. These local offsets rotate with the leader.
	var local_position: Vector3 = target.to_local(rider.global_position)
	var local_yaw: float = wrapf(
		rider.global_rotation.y - target.global_rotation.y, -PI, PI
	)
	rider.set_meta(META_KIND, kind)
	rider.set_meta(META_ID, identity)
	rider.set_meta(META_LOCAL, local_position)
	rider.set_meta(META_LOCAL_YAW, local_yaw)
	# Linked tokens must not fall independently while the leader moves.
	if rider.has_method("set_flying"):
		rider.call("set_flying", true)
	rider.set("grid_support", null)
	rider.velocity = Vector3.ZERO
	_reconcile_collision_links()
	return true


func dismount(rider: CharacterBody3D) -> void:
	if rider == null or not is_instance_valid(rider):
		return
	for key: String in [META_KIND, META_ID, META_LOCAL, META_LOCAL_YAW]:
		if rider.has_meta(key):
			rider.remove_meta(key)
	_reconcile_collision_links()
	# Leave the token suspended at its current height. Gravity is an explicit
	# VTT action and should not automatically trigger when dismounting.


func refresh_all() -> void:
	if board == null or not is_instance_valid(board):
		return
	var visited: Dictionary = {}
	for value: Node in get_tree().get_nodes_in_group("dnd_token"):
		if value is CharacterBody3D and board.is_ancestor_of(value):
			_follow(value as CharacterBody3D, visited, {})
	_reconcile_collision_links()


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
	var yaw_value: Variant = rider.get_meta(META_LOCAL_YAW, null)
	var local_yaw: float = 0.0
	if yaw_value is float or yaw_value is int:
		local_yaw = float(yaw_value)
	else:
		# Older snapshots only stored the relative position. Preserve the
		# follower's current facing when upgrading one of those links.
		local_yaw = wrapf(
			rider.global_rotation.y - target.global_rotation.y, -PI, PI
		)
		rider.set_meta(META_LOCAL_YAW, local_yaw)
	rider.global_position = target.to_global(local)
	rider.global_rotation.y = target.global_rotation.y + local_yaw
	rider.velocity = Vector3.ZERO
	rider.set("grid_support", null)
	visited[rider] = true


func _reconcile_collision_links() -> void:
	if board == null or not is_instance_valid(board):
		return
	var wanted: Dictionary = {}
	for value: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not value is CharacterBody3D or not board.is_ancestor_of(value):
			continue
		var rider: CharacterBody3D = value as CharacterBody3D
		if not is_mounted(rider):
			continue
		var target: Node3D = get_target(rider)
		if target is PhysicsBody3D:
			wanted[rider.get_instance_id()] = [weakref(rider), weakref(target)]

	for rider_id: Variant in _collision_links.keys():
		var previous: Array = _collision_links[rider_id]
		var old_rider: PhysicsBody3D = previous[0].get_ref() as PhysicsBody3D
		var old_target: PhysicsBody3D = previous[1].get_ref() as PhysicsBody3D
		var new_pair: Array = wanted.get(rider_id, [])
		var unchanged: bool = (
			new_pair.size() == 2
			and new_pair[0].get_ref() == old_rider
			and new_pair[1].get_ref() == old_target
		)
		if not unchanged and is_instance_valid(old_rider) and is_instance_valid(old_target):
			old_rider.remove_collision_exception_with(old_target)
			old_target.remove_collision_exception_with(old_rider)

	for rider_id: Variant in wanted.keys():
		var pair: Array = wanted[rider_id]
		var rider: PhysicsBody3D = pair[0].get_ref() as PhysicsBody3D
		var target: PhysicsBody3D = pair[1].get_ref() as PhysicsBody3D
		var previous: Array = _collision_links.get(rider_id, [])
		if (
			previous.size() != 2
			or previous[0].get_ref() != rider
			or previous[1].get_ref() != target
		):
			rider.add_collision_exception_with(target)
			target.add_collision_exception_with(rider)
	_collision_links = wanted
