extends SceneTree

const Spells = preload("res://vtt/spells/spell_catalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var classic := Spells.catalog_spell("phb2014_fireball")
	var modern := Spells.catalog_spell("fireball")
	assert(String(classic.get("source", "")) == "PHB")
	assert(String(modern.get("source", "")) == "XPHB")
	assert(String(classic.get("description", "")) != String(modern.get("description", "")))
	assert("increases by 1d6" in String(classic.get("higher_levels", "")))
	assert(not (classic.get("map_effect_spec", {}) as Dictionary).is_empty())
	assert(classic.get("map_geometry_source", "") == "2024-counterpart")
	assert(classic.get("map_effect_spec", {}) == modern.get("map_effect_spec", {}))
	assert(String(classic.get("aoe_shape", "")) == String(modern.get("aoe_shape", "")))
	assert(is_equal_approx(float(classic.get("range_feet", 0)), 150.0))

	# Direct lookup and searchable lists must carry the same authoritative
	# source and condition metadata for spells with manual visual overrides.
	for entry: Dictionary in Spells.all_spells():
		var direct: Dictionary = Spells.catalog_spell(String(entry.id))
		for field: String in ["source", "classes", "condition_inflict", "saving_throw", "misc_tags"]:
			assert(entry.get(field, []) == direct.get(field, []), "Catalog paths disagree on %s for %s" % [field, entry.id])

	var classic_lists: Array[Dictionary] = Spells.all_spells_for_rules("2014")
	var modern_lists: Array[Dictionary] = Spells.all_spells_for_rules("2024")
	assert(classic_lists.size() > 350)
	assert(modern_lists.size() > 350)
	var found_classic := false
	var found_modern := false
	var inherited_geometry_count := 0
	for item: Dictionary in classic_lists:
		assert(String(item.get("source", "")) not in ["XPHB", "EFA"])
		var reference_id := String(item.get("geometry_reference_id", item.get("original_id", "")))
		var counterpart := Spells.catalog_spell(reference_id)
		if counterpart.get("source", "") == "XPHB" and counterpart.has("map_effect_spec"):
			inherited_geometry_count += 1
			assert(item.get("map_geometry_source", "") == "2024-counterpart")
			for field: String in ["map_effect_spec", "aoe_shape", "target_mode"]:
				assert(item.get(field) == counterpart.get(field), "2014 geometry differs from counterpart: %s / %s" % [item.id, field])
		if String(item.get("id", "")) == "phb2014_fireball":
			found_classic = true
		assert(String(item.get("id", "")) != "fireball")
	for item: Dictionary in modern_lists:
		if String(item.get("id", "")) == "fireball":
			found_modern = true
	assert(found_classic and found_modern)
	assert(inherited_geometry_count > 10, "The catalog must retain nonempty 2024 area specifications for 2014 spells")

	# 2024 geometry still resolves for possessive names with different slugs
	# and for PHB spells whose 2024 reprint changed its display name.
	var named := Spells.catalog_spell("phb2014_bigby_s_hand")
	var named_modern := Spells.catalog_spell("bigbys_hand")
	assert(named.get("map_effect_spec", {}) == named_modern.get("map_effect_spec", {}))
	assert(String(named.get("source", "")) == "PHB")
	assert(named.get("original_id", "") == named_modern.id)

	var renamed := Spells.catalog_spell("phb2014_feeblemind")
	var renamed_modern := Spells.catalog_spell("befuddlement")
	assert(String(renamed.get("name", "")) == "Feeblemind")
	assert(renamed.get("map_effect_spec", {}) == renamed_modern.get("map_effect_spec", {}))
	assert(String(renamed.get("source", "")) == "PHB")
	assert(renamed.get("geometry_reference_id", "") == renamed_modern.id)
	print("PASS: 2014 PHB rules with 2024 map geometry and independent spell catalogues (%d inherited area specifications)" % inherited_geometry_count)
	quit()
