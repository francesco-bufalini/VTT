extends SceneTree

const Player = preload("res://vtt/player_5etools_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const BonusTab = preload("res://vtt/creature_bonus_tab.gd")
const Compendium = preload("res://vtt/compendium.gd")
const CreatureArea = preload("res://vtt/creature_area.gd")

func _initialize() -> void:
	call_deferred("run")


func _entry(category: String, name: String, book: String) -> Dictionary:
	for row: Dictionary in Player.entries(category):
		if String(row.get("name", "")).nocasecmp_to(name) == 0 and String(row.get("source", "")) == book:
			return row
	return {}


func run() -> void:
	var acolyte: Dictionary = _entry("backgrounds", "Acolyte", "PHB")
	var alert: Dictionary = _entry("feats", "Alert", "PHB")
	var holding: Dictionary = _entry("magic_items", "Bag of Holding", "DMG")
	assert(not acolyte.is_empty() and not alert.is_empty() and not holding.is_empty(),
		"Core backgrounds, feats and magic items must be selectable.")
	assert(Player.description_text("backgrounds", acolyte).length() > 80,
		"Backgrounds must have detailed offline 5etools descriptions.")
	assert(Player.description_text("feats", alert).length() > 80,
		"Feats must have detailed offline 5etools descriptions.")
	assert(Player.description_text("magic_items", holding).length() > 80,
		"Magic items must have detailed offline 5etools descriptions.")
	var original: Dictionary = acolyte.duplicate(true)
	var enriched: Dictionary = Player.detailed_entry("backgrounds", acolyte)
	assert(enriched.has("entries") and acolyte == original,
		"Reading a description must not alter the shared structured catalog.")

	var owned: Dictionary = {"kind": "character", "background": "Acolyte",
		"background_source": "PHB", "feats_catalog": [{"name": "Alert", "source": "PHB"}]}
	var traits: Array[Dictionary] = Traits.collect_features(owned)
	var found_background := false
	var found_feat := false
	for trait: Dictionary in traits:
		if String(trait.get("origin", "")).begins_with("Background · Acolyte"):
			found_background = true
			assert(not String(trait.get("entries", "")).is_empty(), "Background feature has text.")
		if String(trait.get("origin", "")).begins_with("Talento · Alert"):
			found_feat = true
			assert("Descrizione:" in String(trait.get("entries", "")), "Owned feat shows description.")
	assert(found_background and found_feat, "Tratti must contain the background and owned feat.")

	var proficiency := ProficiencyTab.new()
	proficiency._rows = [{"origin_id": "background|phb|acolyte", "kind": "skill", "key": "insight",
		"disabled": false, "automatic": false}]
	proficiency._feats = [{"origin_id": "background|phb|acolyte", "name": "Alert",
		"disabled": false}]
	var preview: String = proficiency._origin_grants_tooltip("background|phb|acolyte")
	assert("Scelte già effettuate" in preview and "Insight" in preview and "Alert" in preview,
		"Proficiency origin hover must show user-selected proficiencies and feats.")
	proficiency.free()

	var bonuses := BonusTab.new()
	bonuses._rows = [{"origin_id": "background|phb|acolyte", "target": "ac",
		"expression": "2", "disabled": false}]
	bonuses._record = {"proficiency_choices": [{"origin_id": "background|phb|acolyte",
		"kind": "skill", "key": "insight", "disabled": false}]}
	preview = bonuses._origin_grants_tooltip("background|phb|acolyte")
	assert("Insight" in preview and "ac = 2" in preview,
		"Bonus origin hover must show existing selections and bonuses.")
	bonuses.free()

	var area := CreatureArea.new()
	var info_choice := OptionButton.new()
	info_choice.set_meta("catalog_category", "backgrounds")
	var info_preview: String = area._reference_preview(info_choice, acolyte)
	assert("Acolyte" in info_preview and "Shelter of the Faithful" in info_preview,
		"Info choices must expose their descriptions on hover.")
	info_choice.free()
	area.free()

	var compendium := Compendium.new()
	compendium._details = RichTextLabel.new()
	compendium._render_catalog_entry("backgrounds", acolyte)
	assert("Descrizione" in compendium._details.text and "Acolyte" in compendium._details.text,
		"Non-spell compendium entries must have a formatted description.")
	compendium._details.free()
	compendium.free()
	print("PASS: compendium descriptions, background/feat traits and origin hover selections")
	quit()
