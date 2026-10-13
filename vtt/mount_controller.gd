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
	var yaw_value: Variant = null
	if rider.has_meta(META_LOCAL_YAW):
		yaw_value = rider.get_meta(META_LOCAL_YAW)
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


# A token-led formation can be moved from *any* of its members.
# Legacy item mounts deliberately return null: an item is not a token
# and cannot be repositioned by moving its passenger.
func get_token_group_root(token: CharacterBody3D) -> CharacterBody3D:
	if token == null or not is_instance_valid(token):
		return null
	var current: CharacterBody3D = token
	var seen: Dictionary = {}
	while is_mounted(current):
		if seen.has(current):
			return null
		seen[current] = true
		var target: Node3D = get_target(current)
		if not target is CharacterBody3D:
			return null
		current = target as CharacterBody3D
	return current


func is_in_token_group(token: CharacterBody3D) -> bool:
	var root: CharacterBody3D = get_token_group_root(token)
	if root == null:
		return false
	if root != token:
		return true
	for value: Node in get_tree().get_nodes_in_group("dnd_token"):
		if value is CharacterBody3D and value != token:
			if board.is_ancestor_of(value) and get_token_group_root(value as CharacterBody3D) == root:
				return true
	return false


# Apply a rigid world-space delta to the common leader. A delta calculated
# from the moved follower also rotates the formation *around that follower*,
# rather than snapping it back to its old parent-relative position.
func apply_explicit_token_motion(
	pivot: CharacterBody3D, previous_transform: Transform3D
) -> void:
	var root: CharacterBody3D = get_token_group_root(pivot)
	if root == null:
		return
	if root != pivot:
		var delta: Transform3D = pivot.global_transform * previous_transform.affine_inverse()
		root.global_transform = delta * root.global_transform
	refresh_all()


# Collision exceptions are required between *all* members of a rigid
# formation, including siblings, not only a follower and its ancestors.
# Otherwise moving a side token into the footprint of another member can
# be blocked even though both belong to the same moving group.
func _queue_collision_pair(
	wanted: Dictionary, first: PhysicsBody3D, second: PhysicsBody3D
) -> void:
	if first == second or not is_instance_valid(first) or not is_instance_valid(second):
		return
	var first_id: int = first.get_instance_id()
	var second_id: int = second.get_instance_id()
	var pair_id: String = "%d:%d" % [
		mini(first_id, second_id), maxi(first_id, second_id)
	]
	var previous: Array = _collision_links.get(pair_id, [])
	if (
		previous.size() == 2
		and previous[0].get_ref() == first
		and previous[1].get_ref() == second
	):
		wanted[pair_id] = previous
	else:
		wanted[pair_id] = [weakref(first), weakref(second)]


func _reconcile_collision_links() -> void:
	if board == null or not is_instance_valid(board):
		return
	var wanted: Dictionary = {}
	var groups: Dictionary = {}
	for value: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not value is CharacterBody3D or not board.is_ancestor_of(value):
			continue
		var rider: CharacterBody3D = value as CharacterBody3D
		var root: CharacterBody3D = get_token_group_root(rider)
		if root != null:
			var root_id: int = root.get_instance_id()
			if not groups.has(root_id):
				groups[root_id] = []
			(groups[root_id] as Array).append(rider)
		elif is_mounted(rider):
			# Retain collision handling for old item-based mount snapshots.
			var target: Node3D = get_target(rider)
			var visited: Dictionary = {}
			while target is PhysicsBody3D and not visited.has(target):
				visited[target] = true
				_queue_collision_pair(
					wanted, rider, target as PhysicsBody3D
				)
				if target is CharacterBody3D:
					target = get_target(target as CharacterBody3D)
				else:
					break

	for group_value: Variant in groups.values():
		var members: Array = group_value as Array
		for index: int in range(members.size()):
			for other: int in range(index + 1, members.size()):
				_queue_collision_pair(
					wanted,
					members[index] as PhysicsBody3D,
					members[other] as PhysicsBody3D
				)

	for pair_id: Variant in _collision_links.keys():
		var old_pair: Array = _collision_links[pair_id]
		var old_first: PhysicsBody3D = old_pair[0].get_ref() as PhysicsBody3D
		var old_second: PhysicsBody3D = old_pair[1].get_ref() as PhysicsBody3D
		if not wanted.has(pair_id):
			if is_instance_valid(old_first) and is_instance_valid(old_second):
				old_first.remove_collision_exception_with(old_second)
				old_second.remove_collision_exception_with(old_first)

	for pair_id: Variant in wanted.keys():
		var pair: Array = wanted[pair_id]
		var first: PhysicsBody3D = pair[0].get_ref() as PhysicsBody3D
		var second: PhysicsBody3D = pair[1].get_ref() as PhysicsBody3D
		if not _collision_links.has(pair_id):
			first.add_collision_exception_with(second)
			second.add_collision_exception_with(first)
	_collision_links = wanted
