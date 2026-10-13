extends SceneTree

const Traits = preload("res://vtt/creature_traits_tab.gd")
const Origins = preload("res://vtt/creature_proficiency_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var item: Dictionary = {
		"id": "test:blade", "name": "Test Blade", "type": "M",
		"damage": "1d8", "quantity": 1, "active": true,
		"equipped_slots": ["main"], "feats": [{"Alert|PHB": true}]
	}
	var record: Dictionary = {
		"kind": "character", "rules_version": "2014",
		"species": "Elf", "species_source": "PHB",
		"background": "Acolyte", "background_source": "PHB",
		"class": "Fighter", "class_source": "PHB",
		"classes": [{"name": "Fighter", "source": "PHB", "level": 3}],
		"inventory": [item],
		"feats_catalog": [{"id": "feat:independent", "name": "Independent", "source": "HB", "origin_id": ""}],
		"proficiency_origins": [], "proficiency_choices": [], "formula_bonuses": []
	}
	var entries: Array[Dictionary] = Traits.collect_features(record)
	var ordering: Array[String] = ["razza", "background", "classi", "talenti", "oggetti", "mostro", "altro"]
	var previous := -1
	var present: Dictionary = {}
	var item_trait := false
	var class_overview := false
	for feature: Dictionary in entries:
		var section: String = String(feature.get("category", "altro"))
		var order: int = ordering.find(section)
		assert(order >= previous, "Trait categories must be strictly grouped in canonical order")
		previous = order
		present[section] = true
		if section == "oggetti" and "Test Blade" in String(feature.get("name", "")):
			item_trait = true
		if section == "classi" and "Descrizione · Fighter" in String(feature.get("name", "")):
			class_overview = true
	assert(present.has("razza") and present.has("background") and present.has("classi")
		and present.has("talenti") and present.has("oggetti"),
		"Species, background, classes, feats and inventory must all be represented in Traits")
	assert(item_trait and class_overview,
		"Inventory and class overview descriptions are independent trait cards")

	var archived_document: Dictionary = {
		"id": "doc:test:secret", "name": "Note segrete",
		"category": "documents", "quantity": 1,
		"description": "Testo del documento"
	}
	record["inventory"] = [item, archived_document]
	record["proficiency_origins"] = [{
		"id": "custom|legacy", "name": "Origine di vecchio salvataggio",
		"group": "custom", "disabled": false
	}]
	var filtered_traits: Array[Dictionary] = Traits.collect_features(record)
	var document_trait_found := false
	var manual_origin_trait_found := false
	var physical_item_remains := false
	for feature: Dictionary in filtered_traits:
		if "Note segrete" in String(feature.get("name", "")):
			document_trait_found = true
		if "Origine di vecchio salvataggio" in String(feature.get("name", "")):
			manual_origin_trait_found = true
		if "Test Blade" in String(feature.get("name", "")):
			physical_item_remains = true
	assert(not document_trait_found and not manual_origin_trait_found and physical_item_remains,
		"Documents and legacy custom origins are not traits; regular items remain visible")
	record["inventory"] = [item]
	record["proficiency_origins"] = []

	var eligible: Array[Dictionary] = Origins.trait_origins(record, true)
	var structured_source := ""
	for source: Dictionary in eligible:
		if String(source.get("origin_key", "")) == "item:test:blade":
			structured_source = String(source.get("id", ""))
	assert(not structured_source.is_empty(),
		"Only explicit 5etools feats metadata marks a trait as an automatic feat source")
	assert(Origins._fixed_feat_refs([{"Alert|PHB": true}, {"choose": {"from": ["Tough|PHB"]}}]).size() == 1,
		"Fixed structured grants are distinguishable from selectable feat choices")

	# Ownership and equipment are separate. A sheathed weapon remains a trait
	# and source, but its benefits and all feat descendants go inactive.
	var parent: Dictionary = {"id": "feat:ancestor", "name": "Ancestor", "source": "HB",
		"origin_id": "item:test:blade", "disabled": false}
	var child: Dictionary = {"id": "feat:descendant", "name": "Descendant", "source": "HB",
		"origin_id": "feat|hb|ancestor", "disabled": false}
	var independent: Dictionary = parent.duplicate(true)
	independent["origin_id"] = ""
	record["feats_catalog"] = [parent, child]
	record["proficiency_choices"] = [
		{"kind": "skill", "key": "arcana", "origin_id": "feat|hb|descendant", "disabled": false},
		{"kind": "skill", "key": "arcana", "origin_id": "", "disabled": false}
	]
	record["formula_bonuses"] = [
		{"id": "test:bonus", "origin_id": "feat|hb|descendant",
			"target": "initiative", "expression": "2", "disabled": false}]
	var enabled: Dictionary = Origins.origin_enabled_map(record)
	assert(bool(enabled.get("item:test:blade", false))
		and bool(enabled.get("feat|hb|descendant", false)), "Equipped item activates feat descendant")
	item["equipped_slots"] = []
	record["inventory"] = [item]
	enabled = Origins.origin_enabled_map(record)
	assert(not bool(enabled.get("item:test:blade", true))
		and not bool(enabled.get("feat|hb|ancestor", true))
		and not bool(enabled.get("feat|hb|descendant", true)),
		"Unequipping disables item origins and their feat descendants")
	Origins.reconcile_origin_dependents(record)
	assert((record["feats_catalog"] as Array).size() >= 2
		and (record["formula_bonuses"] as Array).size() == 1,
		"Unequipping must not permanently erase any owned feat or grant")
	item["equipped_slots"] = ["main"]
	record["inventory"] = [item]
	enabled = Origins.origin_enabled_map(record)
	assert(bool(enabled.get("feat|hb|descendant", false)),
		"Re-equipping restores the whole origin chain")

	# Two distinct grants of the same feat. Removing the item must preserve
	# both the independent source of that feat and its downstream benefits.
	record["feats_catalog"] = [parent, independent, child]
	record["inventory"] = []
	Origins.reconcile_origin_dependents(record)
	var grant_from_item := false
	var grant_independent := false
	var descendant_exists := false
	for feat: Variant in record.get("feats_catalog", []):
		if String(feat.get("origin_id", "")) == "item:test:blade":
			grant_from_item = true
		if String(feat.get("name", "")) == "Ancestor" and String(feat.get("origin_id", "")) == "":
			grant_independent = true
		if String(feat.get("name", "")) == "Descendant":
			descendant_exists = true
	assert(not grant_from_item and grant_independent and descendant_exists,
		"A second source keeps the feat and all its descendants after deleting an item")
	record["feats_catalog"] = [child]
	Origins.reconcile_origin_dependents(record)
	assert((record["feats_catalog"] as Array).is_empty()
		and (record["formula_bonuses"] as Array).is_empty()
		and (record["proficiency_choices"] as Array).size() == 1,
		"Removing the last feat source recursively prunes descendants, but not independent skills")
	print("PASS: unified ordered trait categories, structured feat grants, equipment and origin-chain cleanup")
	quit()
