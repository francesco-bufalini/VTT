extends SceneTree

const MotionLinks = preload("res://vtt/mount_controller.gd")


class DummyToken extends CharacterBody3D:
	var token_id: String = ""
	var flying: bool = false
	var grid_support: Node3D

	func get_token_id() -> String:
		return token_id

	func set_flying(value: bool) -> void:
		flying = value


func _initialize() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error("Linked token motion: " + reason)
	quit(1)


func _spawn(board: Node3D, token_id: String, pos: Vector3, yaw: float) -> DummyToken:
	var token := DummyToken.new()
	token.token_id = token_id
	board.add_child(token)
	token.add_to_group("dnd_token")
	token.global_position = pos
	token.global_rotation.y = yaw
	return token


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.0001


func _same_yaw(a: float, b: float) -> bool:
	return absf(wrapf(a - b, -PI, PI)) < 0.0001


func _run() -> void:
	var board := Node3D.new()
	root.add_child(board)
	var links: Node = MotionLinks.new()
	board.add_child(links)
	links.call("setup", board)

	var leader := _spawn(
		board, "leader", Vector3(2.0, 1.0, 4.0), deg_to_rad(45.0)
	)
	var follower := _spawn(
		board, "follower", Vector3(5.0, 3.0, -1.0), deg_to_rad(-30.0)
	)
	var initial_position: Vector3 = follower.global_position
	var initial_yaw: float = follower.global_rotation.y
	var local_position: Vector3 = leader.to_local(initial_position)
	var local_yaw: float = wrapf(initial_yaw - leader.global_rotation.y, -PI, PI)

	if not bool(links.call("mount", follower, leader)):
		_fail("initial association was rejected")
		return
	if not _near(follower.global_position, initial_position) or not _same_yaw(
		follower.global_rotation.y, initial_yaw
	):
		_fail("association must not teleport or rotate the follower")
		return
	if not follower.get_collision_exceptions().has(leader):
		_fail("linked tokens must not block each other's movement")
		return

	leader.global_position += Vector3(3.0, -2.0, 1.0)
	links.call("refresh_all")
	if not _near(follower.global_position, leader.to_global(local_position)):
		_fail("translation did not preserve the local XYZ offset")
		return

	leader.global_rotation.y += PI / 4.0
	links.call("refresh_all")
	if (
		not _near(follower.global_position, leader.to_global(local_position))
		or not _same_yaw(follower.global_rotation.y, leader.global_rotation.y + local_yaw)
	):
		_fail("45-degree turn must rotate both offset and relative facing")
		return

	var tail := _spawn(board, "tail", Vector3(8.0, 4.0, 2.0), PI / 6.0)
	if not bool(links.call("mount", tail, follower)):
		_fail("nested association was rejected")
		return
	var tail_local: Vector3 = follower.to_local(tail.global_position)
	var tail_yaw: float = wrapf(
		tail.global_rotation.y - follower.global_rotation.y, -PI, PI
	)
	if bool(links.call("can_mount", leader, tail)):
		_fail("cyclic associations must be rejected")
		return

	leader.global_rotation.y -= PI / 2.0
	leader.global_position += Vector3(-2.0, 1.0, 4.0)
	links.call("refresh_all")
	if not _near(follower.global_position, leader.to_global(local_position)):
		_fail("negative 90-degree turn did not move the follower")
		return
	if (
		not _near(tail.global_position, follower.to_global(tail_local))
		or not _same_yaw(tail.global_rotation.y, follower.global_rotation.y + tail_yaw)
	):
		_fail("nested followers did not keep their local transform")
		return

	links.call("dismount", follower)
	if follower.get_collision_exceptions().has(leader):
		_fail("detaching must restore collision between formerly linked tokens")
		return
	var detached: Vector3 = follower.global_position
	var detached_yaw: float = follower.global_rotation.y
	leader.global_position += Vector3(7.0, 0.0, 0.0)
	leader.global_rotation.y += PI / 2.0
	links.call("refresh_all")
	if not _near(follower.global_position, detached) or not _same_yaw(
		follower.global_rotation.y, detached_yaw
	):
		_fail("detached token still followed its former leader")
		return
	if not _near(tail.global_position, follower.to_global(tail_local)):
		_fail("detaching an intermediate token broke its own followers")
		return

	print("PASS: linked token motion, rotation, elevation, chains, cycles, detachment")
	quit()
