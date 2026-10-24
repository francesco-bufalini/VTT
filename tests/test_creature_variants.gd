extends SceneTree
const Archive = preload("res://vtt/creature_archive.gd")
func _initialize() -> void:
	var archive := Archive.new()
	archive.setup()
	for kind: String in ["character", "monster"]:
		var record: Dictionary = archive.create_character() if kind == "character" else archive.create_monster({"name": "Wolf", "hp": {"average": 11}}, "ally")
		record.name = "Base"
		record.current_hp = 30
		record["variants"] = [{"id": "alias", "name": "Alias", "sections": ["name", "appearance", "hp"], "sources": {}, "values": {"name": "Ombra", "current_miniature_id": "wolf", "current_hp": 7, "max_hp_base": 11}}]
		record["current_form_id"] = "alias"
		record["variant_schema_version"] = 1
		var normalized: Dictionary = archive._normalize(record)
		assert(normalized.variants == record.variants and normalized.current_form_id == "alias")
		var effective := Archive.resolve_form(normalized)
		assert(effective.name == "Ombra" and effective.current_hp == 7)
		assert(effective.id == normalized.id and effective.owner_id == normalized.owner_id)
		var next := Archive.apply_public_form_patch(normalized, {"name": "Spia", "current_miniature_id": "ape", "conditions": ["poisoned"]})
		assert(next.name == "Base" and next.current_hp == 30)
		assert(next.variants[0].values.name == "Spia" and next.variants[0].values.current_miniature_id == "ape")
		assert(next.conditions == ["poisoned"])
		next.current_form_id = ""
		assert(Archive.resolve_form(next).name == "Base")
	var complete := {"id": "base", "kind": "monster", "stat_block": {"name": "Dragon", "legendary": [{"name": "Tail"}]}, "current_form_id": "wolf", "variants": [{"id": "wolf", "sections": ["*"], "values": {"id": "must-not-change", "stat_block": {"name": "Wolf"}}}]}
	var replaced := Archive.resolve_form(complete)
	assert(replaced.id == "base" and replaced.stat_block.name == "Wolf" and not replaced.stat_block.has("legendary"))
	print("PASS: native archive preserves variants for characters and monsters; public name/appearance changes keep the base intact")
	quit()
