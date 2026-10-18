extends SceneTree
const Area = preload("res://vtt/creature_area.gd")
const Runtime = preload("res://vtt/class_feature_activation.gd")
class Archive extends RefCounted:
	var saved: Dictionary
	var writes := 0
	func list_owned() -> Array[Dictionary]: return [saved.duplicate(true)]
	func save(record: Dictionary) -> Error:
		saved = record.duplicate(true)
		writes += 1
		return OK
class SpellRuntime extends Node:
	var context: Dictionary
	func has_runtime_spell_effect(_id: String, _name: String, _source: String) -> bool: return true
	func activate_spell_from_caster(_id: String, _caster: Node3D, _name: String, _source: String, _level: int, data: Dictionary) -> bool:
		context = data.duplicate(true)
		return true
class Sheet extends Area:
	var fixture: Dictionary
	var token: CharacterBody3D
	var status: String
	func _current() -> Dictionary: return fixture
	func hide_panel() -> void: pass
	func show_panel() -> void: pass
	func _set_status(message: String) -> void: status = message
	func _update_external_record(record: Dictionary) -> void: fixture = record.duplicate(true)
	func find_linked_token_for_creature(_id: String) -> CharacterBody3D: return token
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sheet := Sheet.new()
	root.add_child(sheet)
	sheet.fixture = {"id": "meta_caster", "kind": "character", "rules_version": "2014", "classes": [{"name": "Sorcerer", "source": "PHB", "level": 5}], "optional_features_catalog": [{"name": "Distant Spell", "source": "PHB"}], "resource_tracker_spent": {}}
	var archive := Archive.new()
	archive.saved = sheet.fixture.duplicate(true)
	sheet._archive = archive
	sheet._selected_id = "meta_caster"
	var board := Node3D.new()
	root.add_child(board)
	sheet.board_root = board
	var runtime := SpellRuntime.new()
	runtime.name = "SpellSystem"
	board.add_child(runtime)
	sheet.token = CharacterBody3D.new()
	board.add_child(sheet.token)
	sheet.token.set_meta("creature_id", "meta_caster")
	var spell := {"id": "sample", "name": "Sample", "level": 1, "range": "60 feet", "range_feet": 60, "duration": "Instantaneous", "metamagic": {"names": ["Distant Spell"]}}
	assert(sheet._on_spellcasting_cast_requested(spell, 1))
	assert(archive.writes == 0, "Starting a preview never charges metamagic")
	sheet.cancel_origin_spell_cast(sheet.token, spell)
	assert(sheet._pending_metamagic_cast.is_empty() and archive.writes == 0)
	assert(sheet._on_spellcasting_cast_requested(spell, 1))
	sheet.complete_origin_spell_cast(sheet.token, spell)
	assert(archive.writes == 1)
	assert(int(archive.saved.resource_tracker_spent.values()[0]) == 1)
	sheet.complete_origin_spell_cast(sheet.token, spell)
	assert(archive.writes == 1, "A duplicate completion never charges twice")
	sheet.fixture.active_class_features = {"rage": {"name": "Ira"}}
	sheet.fixture.classes.append({"name": "Barbarian", "source": "PHB", "level": 1})
	assert(not sheet._on_spellcasting_cast_requested(spell, 1))
	assert(archive.writes == 1)
	board.queue_free()
	sheet.queue_free()
	print("PASS: metamagic preview cancellation, exactly-once commit, and Rage spellcasting prohibition")
	quit()
