extends SceneTree

const Catalog = preload("res://vtt/content_catalog.gd")
const Enrichment = preload("res://vtt/content_enrichment.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var folder := "user://test_native_homebrew_" + str(Time.get_ticks_usec())
	var integration_folder := folder.path_join("integrations")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(integration_folder))
	var native_path: String = folder.path_join("native.json")
	var original_text: String = FileAccess.get_file_as_string("res://homebrew/examples/native_5etools.json")
	assert(not original_text.is_empty())
	var file := FileAccess.open(native_path, FileAccess.WRITE)
	file.store_string(original_text)
	file.close()
	Catalog.reload_homebrew([folder])
	var creatures: Array[Dictionary] = Catalog.home_entries("monsters")
	var spells: Array[Dictionary] = Catalog.home_entries("spells")
	var items: Array[Dictionary] = Catalog.home_entries("items")
	assert(creatures.size() == 1 and creatures[0].id == "homebrew:hbx:monsters:crystal_owl")
	assert(spells.size() == 1 and spells[0].id == "homebrew:hbx:spells:prism_pulse")
	assert(items.size() == 1 and items[0].id == "homebrew:hbx:items:prismatic_sword")
	assert(spells[0].has("entries") and not spells[0].has("target_mode"))
	var plain: Dictionary = Spells.catalog_spell(String(spells[0].id))
	assert(String(plain.get("target_mode", "")).is_empty(), "No guessed 5etools geometry for homebrew")

	var overlay_path := integration_folder.path_join("custom.json")
	var overlay := {
		"schema_version": 1,
		"category": "spells",
		"entries": [
			{"id": String(spells[0].id), "fields": {"target_mode": "token_then_point", "range_feet": 60, "aoe_shape": "sphere", "aoe_radius_feet": 10, "name": "WRONG"}}
		]
	}
	var metadata := FileAccess.open(overlay_path, FileAccess.WRITE)
	metadata.store_string(JSON.stringify(overlay))
	metadata.close()
	Enrichment.reload([integration_folder])
	var extended: Dictionary = Spells.catalog_spell(String(spells[0].id))
	assert(extended.get("name") == "Prism Pulse", "Enrichment must not replace compendium identity")
	assert(extended.get("target_mode") == "token_then_point")
	assert(float(extended.get("aoe_radius_feet", 0)) == 10.0)
	assert(Spells.is_runtime_usable(extended))
	assert(Enrichment.diagnostics.size() == 1, "Protected identity must be rejected")
	assert(not Catalog.home_entries("spells")[0].has("aoe_radius_feet"), "Source remains unchanged")
	assert(FileAccess.get_file_as_string(native_path) == original_text, "Native JSON remains intact")

	Enrichment.reload()
	assert(Enrichment.extension_for("spells", "meteor_swarm").has("meteor_drop_height_feet"),
		"Existing authored mechanics must survive separation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(overlay_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(native_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(integration_folder))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	Catalog.reload_homebrew()
	print("PASS: native 5etools import, separate runtime metadata, protected source identity")
	quit()
