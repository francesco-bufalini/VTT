extends SceneTree

const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Distinct instances of the same class trait must show source and level,
	# never three indistinguishable "Ability Score Improvement" options.
	var sources: Array[Dictionary] = []
	for level: int in [4, 8, 12]:
		sources.append({
			"id": "feature:barbarian|phb|asi|%d" % level,
			"name": "Tratto · Ability Score Improvement",
			"group": "feature", "class_name": "Barbarian",
			"class_source": "PHB", "level": level, "category": "classi"
		})
	var labels: Dictionary = OriginChoices.display_labels(sources)
	var seen: Dictionary = {}
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		var level: int = int(source.get("level", 0))
		var label: String = String(labels.get(sid, ""))
		assert("Barbarian" in label and "livello %d" % level in label and "PHB" in label,
			"Feature labels must expose class, acquisition level and source")
		assert(not seen.has(label), "Repeated feature instances must have unique labels")
		seen[label] = true

	# Unstructured homebrew duplicate names still receive distinct, stable
	# ordinals instead of leaking internal IDs to the user.
	var legacy: Array[Dictionary] = [
		{"id": "feature:customA", "name": "Tratto · Twin Power"},
		{"id": "feature:customB", "name": "Tratto · Twin Power"}
	]
	var legacy_labels: Dictionary = OriginChoices.display_labels(legacy)
	assert(String(legacy_labels["feature:customA"]).ends_with("#1"))
	assert(String(legacy_labels["feature:customB"]).ends_with("#2"))

	# Exercise the exact picker used by the Talenti editor: sources come from
	# several subsystems, with class/level metadata resolved by live identity.
	var record: Dictionary = {
		"kind": "character", "rules_version": "2014",
		"class": "Barbarian", "class_source": "PHB", "level": 12,
		"classes": [{"name": "Barbarian", "source": "PHB", "level": 12}],
		"inventory": [], "feats_catalog": [],
		"proficiency_origins": [], "proficiency_choices": [], "formula_bonuses": []
	}
	var real_features: Array[Dictionary] = Traits.collect_features(record)
	var levels: Dictionary = {}
	for feature: Dictionary in real_features:
		if String(feature.get("name", "")) == "Ability Score Improvement" and String(feature.get("class_name", "")) == "Barbarian":
			levels[int(feature.get("level", 0))] = "feature:" + String(feature.get("key", ""))
	for level: int in [4, 8, 12]:
		assert(levels.has(level), "Barbarian ASI feature at level %d must exist" % level)

	var available: Array[Dictionary] = OriginChoices.available(record)
	var available_by_id: Dictionary = {}
	for source: Dictionary in available:
		available_by_id[String(source.get("id", ""))] = source
	for level: int in [4, 8, 12]:
		var sid: String = String(levels[level])
		assert(available_by_id.has(sid), "Each ASI trait identity must stay selectable")
		assert(int((available_by_id[sid] as Dictionary).get("level", -1)) == level,
			"Live feature metadata must survive saved/bonus source deduplication")

	var picker := OptionButton.new()
	root.add_child(picker)
	OriginChoices.populate(picker, record)
	var selected_ids: Dictionary = {}
	var picker_labels: Dictionary = {}
	for index: int in range(picker.item_count):
		var source: Dictionary = picker.get_item_metadata(index)
		var sid: String = String(source.get("id", ""))
		if sid not in levels.values():
			continue
		var label: String = picker.get_item_text(index)
		assert("Barbarian" in label and "livello %d" % int(source.get("level", 0)) in label,
			"The right-side Talenti origin dropdown needs the full context")
		assert(not picker_labels.has(label), "The user must be able to distinguish every ASI dropdown entry")
		picker_labels[label] = true
		selected_ids[sid] = true
		picker.select(index)
		assert(String(OriginChoices.selected(picker).get("id", "")) == sid,
			"Display-only labels must not change origin identifiers")
	assert(selected_ids.size() == 3, "The dropdown must expose all three ASI origins")
	picker.queue_free()
	await process_frame
	print("PASS: repeated ASI origins distinguished in feat editor selector without changing IDs")
	quit()
