extends SceneTree

const PlayerStore = preload("res://vtt/player_character_store.gd")
const MasterStore = preload("res://vtt/master_creature_store.gd")

func _initialize() -> void:
	var source: Dictionary = {"kind": "character", "name": "Druid", "class": "Druid", "level": 3,
		"origin_spell_variants": {"feature:class|phb|druid|circle spells": "coast"}}
	for store: Variant in [PlayerStore.new(), MasterStore.new()]:
		var normalized: Dictionary = store.normalize_character(source) if store is PlayerStore else store.normalize_creature(source)
		assert(normalized.get("origin_spell_variants", {}) == source["origin_spell_variants"])
		normalized["origin_spell_variants"]["feature:class|phb|druid|circle spells"] = "forest"
		assert(source["origin_spell_variants"].values() == ["coast"], "Normalization must not alias source choices")
	print("PASS: native character and creature normalization preserve PWA spell-variant choices")
	quit()
