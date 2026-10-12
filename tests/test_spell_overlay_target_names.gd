extends SceneTree

const SpellTargetOverlay2D = preload("res://vtt/spells/spell_target_overlay_2d.gd")
const AttackRangeOverlay2D = preload("res://vtt/attack_range_overlay_2d.gd")


class FakeToken:
	extends Node3D

	var visible_name: String = ""

	func get_display_name() -> String:
		return visible_name


class FakeSheet:
	extends Node

	var creature_names: Dictionary = {"npc-42": "Duergar"}

	func get_owned_creature_name_index() -> Dictionary:
		return creature_names.duplicate()


class FakeMeasure:
	extends Node3D

	var affected: Array[Node3D] = []

	func spell_geometry_affected_tokens(
		_start: Vector3, _end: Vector3, _shape: String,
		_style: String = "", _width: float = -1.0
	) -> Array[Node3D]:
		return affected.duplicate()


func _fail(reason: String) -> void:
	push_error("Spell 2D overlay layering / target names: " + reason)
	quit(1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := Node3D.new()
	root.add_child(board)
	var sheet := FakeSheet.new()
	sheet.name = "CreatureArea"
	board.add_child(sheet)
	var spell := Node.new()
	board.add_child(spell)
	var measure := FakeMeasure.new()
	board.add_child(measure)
	var camera := Camera3D.new()
	board.add_child(camera)
	var canvas := CanvasLayer.new()
	board.add_child(canvas)

	var token_overlay := Control.new()
	token_overlay.z_index = -50
	canvas.add_child(token_overlay)
	var aoe: Control = SpellTargetOverlay2D.new()
	canvas.add_child(aoe)
	aoe.call("setup", board, spell, measure, camera)
	var attack_range: Control = AttackRangeOverlay2D.new()
	canvas.add_child(attack_range)
	attack_range.call("setup", board, spell)
	var sheet_panel := PanelContainer.new()
	sheet_panel.z_index = 30
	canvas.add_child(sheet_panel)
	if not (token_overlay.z_index < aoe.z_index and aoe.z_index < sheet_panel.z_index):
		_fail("spell AoE should be above portraits, below creature sheets")
		return
	if not (token_overlay.z_index < attack_range.z_index and attack_range.z_index < sheet_panel.z_index):
		_fail("weapon range overlay should stay below creature sheets")
		return
	if aoe.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("spell overlay intercepts clicks meant for UI controls")
		return

	var named := FakeToken.new()
	named.name = "token_123"
	named.visible_name = "Sciamano duergar"
	named.add_to_group("dnd_token")
	board.add_child(named)
	if String(aoe.call("_target_display_name", named)) != "Sciamano duergar":
		_fail("explicit token display name lost to internal ID")
		return

	var linked := FakeToken.new()
	linked.name = "Token"
	linked.set_meta("creature_id", "npc-42")
	linked.add_to_group("dnd_token")
	board.add_child(linked)
	if String(aoe.call("_target_display_name", linked)) != "Duergar":
		_fail("linked creature sheet name was not resolved")
		return

	var remote := FakeToken.new()
	remote.name = "token_678"
	remote.set_meta("master_creature_name", "Guardia")
	remote.add_to_group("dnd_token")
	board.add_child(remote)
	if String(aoe.call("_target_display_name", remote)) != "Guardia":
		_fail("remote creature metadata name was not resolved")
		return

	var same_name := FakeToken.new()
	same_name.name = "token_679"
	same_name.visible_name = "Duergar"
	same_name.add_to_group("dnd_token")
	board.add_child(same_name)
	measure.affected = [linked, same_name]
	var names: Array[String] = aoe.call(
		"_target_names", Vector3.ZERO, Vector3.RIGHT, "sphere", -1.0
	)
	if names.size() != 2 or names[0] != "Duergar" or names[1] != "Duergar":
		_fail("two different creatures with the same name were collapsed")
		return

	same_name.visible_name = "Duergar capitano"
	names = aoe.call("_target_names", Vector3.ZERO, Vector3.RIGHT, "sphere", -1.0)
	if names.size() != 2 or names[1] != "Duergar capitano":
		_fail("target names remained cached after renaming a token")
		return

	board.queue_free()
	await process_frame
	print("PASS: spell/weapon overlay ordering and real affected-creature names")
	quit()
