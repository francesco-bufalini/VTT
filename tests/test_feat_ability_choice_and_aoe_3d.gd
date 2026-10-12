extends SceneTree

const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Store = preload("res://vtt/player_character_store.gd")
const Overlay = preload("res://vtt/spells/spell_target_overlay_2d.gd")


class Board3D:
	extends Node3D

	func is_2d_view_enabled() -> bool:
		return false


class FakeSpell:
	extends Node

	var _targeting_phase: String = "point"
	var _pending_targets: Array[Node3D] = []
	var _pending_target_points: Array[Vector3] = []

	func is_targeting() -> bool:
		return true


class FakeMeasure:
	extends Node3D

	var affected: Array[Node3D] = []
	var _held_spell_aoes: Array[Node3D] = []
	var persistent_aoes: Array = []
	var _aoe_nodes: Array[Node3D] = []
	var _spell_preview: MeshInstance3D
	var _spell_range_preview: MeshInstance3D

	func spell_geometry_affected_tokens(
		_start: Vector3, _end: Vector3, _shape: String,
		_style: String = "", _width: float = -1.0
	) -> Array[Node3D]:
		return affected.duplicate()


class NamedTarget:
	extends Node3D

	func get_display_name() -> String:
		return "Duergar"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tce: Dictionary = Structured.feat_ability_choice({"name": "Telepathic", "source": "TCE"})
	assert(int(tce.get("amount", 0)) == 1)
	assert(tce.get("from", []) == ["int", "wis", "cha"])
	var xphb: Dictionary = Structured.feat_ability_choice({"name": "Telepathic", "source": "XPHB"})
	assert(int(xphb.get("amount", 0)) == 1)
	assert(xphb.get("from", []) == ["int", "wis", "cha"])
	assert(Structured.feat_ability_choice({"name": "Ability Score Improvement", "source": "XPHB"}).is_empty(),
		"Two-score ASI must not be reduced to one automatic +1")

	var record: Dictionary = {
		"kind": "character", "level": 3,
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"feats_catalog": [{"name": "Telepathic", "source": "TCE", "origin_id": ""}],
		"formula_bonuses": [], "proficiency_origins": [], "proficiency_choices": [],
		"inventory": []
	}
	assert(Bonuses.value(record, "ability:int") == 10, "Unchosen feat must not arbitrarily pick a score")
	(record.feats_catalog[0] as Dictionary)["ability_choice"] = "int"
	assert(Bonuses.value(record, "ability:int") == 11)
	assert(Bonuses.value(record, "ability:wis") == 10)
	var found: bool = false
	for grant: Dictionary in Bonuses.grants(record):
		if String(grant.get("id", "")) == "auto|feat|tce|telepathic|ability_choice|ability:int":
			found = true
			assert(bool(grant.get("automatic", false)))
	assert(found, "Chosen ability should be an automatic, origin-linked grant")

	(record.feats_catalog[0] as Dictionary)["ability_choice"] = "wis"
	assert(Bonuses.value(record, "ability:int") == 10, "Previous choice must be withdrawn")
	assert(Bonuses.value(record, "ability:wis") == 11)
	(record.feats_catalog[0] as Dictionary)["ability_choice"] = "str"
	assert(Bonuses.value(record, "ability:str") == 10, "Invalid ability choice must not grant an extra score")
	(record.feats_catalog[0] as Dictionary)["ability_choice"] = "cha"
	assert(Bonuses.value(record, "ability:cha") == 11)
	record.proficiency_origins = [{
		"id": "feat|tce|telepathic", "name": "Telepathic", "group": "feat", "disabled": true
	}]
	assert(Bonuses.value(record, "ability:cha") == 10, "Muting feat must withdraw its ability increase")
	record.proficiency_origins = []
	var restored: Dictionary = Store.new().normalize_character(record)
	assert(String((restored.feats_catalog[0] as Dictionary).get("ability_choice", "")) == "cha",
		"Choice must survive save normalization")
	assert(Bonuses.value(restored, "ability:cha") == 11)
	restored.feats_catalog = []
	assert(Bonuses.value(restored, "ability:cha") == 10, "Removing feat must withdraw the bonus")

	record.feats_catalog = [{"name": "Telepathic", "source": "XPHB", "ability_choice": "int"}]
	assert(Bonuses.value(record, "ability:int") == 11, "2024 feat uses implied +1 amount")
	record.feats_catalog = [{"name": "Actor", "source": "PHB"}]
	assert(Bonuses.value(record, "ability:cha") == 11, "Existing fixed feat bonuses must not regress")

	var board := Board3D.new()
	root.add_child(board)
	var spell := FakeSpell.new()
	board.add_child(spell)
	var measure := FakeMeasure.new()
	board.add_child(measure)
	var camera := Camera3D.new()
	board.add_child(camera)
	var overlay: Control = Overlay.new()
	board.add_child(overlay)
	overlay.call("setup", board, spell, measure, camera)
	assert(bool(overlay.call("_is_active")), "3D view must keep the AoE target list active")
	assert(not bool(overlay.call("_is_2d_view")), "3D view should not paint 2D AoE circles")
	var target := NamedTarget.new()
	target.name = "token_99"
	target.add_to_group("dnd_token")
	board.add_child(target)
	measure.affected = [target]
	var names: Array[String] = overlay.call("_target_names", Vector3.ZERO, Vector3.ONE, "sphere", -1.0)
	assert(names == ["Duergar"], "3D target list must use same human-readable names as 2D")
	board.queue_free()
	await process_frame
	print("PASS: structured feat ability choices and 3D AoE target list")
	quit()
