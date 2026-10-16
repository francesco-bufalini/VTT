extends SceneTree

const Pending = preload("res://vtt/creature_pending_choices.gd")
const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const BonusTab = preload("res://vtt/creature_bonus_tab.gd")
const FeatsTab = preload("res://vtt/creature_feats_tab.gd")
const CreatureArea = preload("res://vtt/creature_area.gd")


func _initialize() -> void:
	call_deferred("_run")


func _record() -> Dictionary:
	return {
		"kind": "character", "rules_version": "2014",
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"feats_catalog": [{"name": "Telepathic", "source": "TCE", "origin_id": ""}],
		"formula_bonuses": [], "proficiency_origins": [], "proficiency_choices": [],
		"inventory": [], "classes": []
	}


func _run() -> void:
	var record: Dictionary = _record()
	var sid: String = "feat|tce|telepathic"
	var missing: Array[Dictionary] = Pending.missing_feat_abilities(record)
	assert(missing.size() == 1 and String(missing[0].get("origin_id", "")) == sid)
	assert(missing[0].get("from", []) == ["int", "wis", "cha"])
	assert(Bonuses.value(record, "ability:int") == 10, "No choice means no invented bonus")
	var warnings: Dictionary = Pending.section_warnings(record)
	assert(warnings.has(3), "Bonus menu needs its warning")
	assert(not warnings.has(2), "Feat section must not ask for a choice handled in Bonus")

	# The top-level View and edit warning and the matching dropdown entry
	# must be visible without opening the Bonus editor first.
	var creature_area := CreatureArea.new()
	var section_picker := OptionButton.new()
	for title: String in ["Niente", "Competenze", "Talenti", "Bonus", "Tracker", "Resistenze"]:
		section_picker.add_item(title)
	var global_warning := Label.new()
	creature_area.set("_editor_section_picker", section_picker)
	creature_area.set("_editor_choice_warning", global_warning)
	creature_area.call("_refresh_choice_warnings", record)
	assert(global_warning.visible)
	assert(section_picker.get_item_text(3).begins_with("⚠ "), "Bonus menu item should be marked")
	assert(not section_picker.get_item_text(2).begins_with("⚠ "), "Talenti is not the choice editor")
	assert("Telepathic" in global_warning.tooltip_text)

	# A muted feat no longer asks for a choice, until reactivated.
	record.proficiency_origins = [{"id": sid, "name": "Telepathic", "group": "feat", "disabled": true}]
	assert(Pending.missing_feat_abilities(record).is_empty())
	record.proficiency_origins = []

	# The Bonus tab includes a source even when the automatic row does not
	# exist yet and completes it using the same warning-dialog approach as
	# the Proficiency tab.
	var captures: Array = []
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var bonuses := BonusTab.new()
	ui.add_child(bonuses)
	bonuses.setup(func(rows: Array, origins: Array, feats: Array = [], _dice: Array = []) -> void:
		captures.append({"rows": rows, "origins": origins, "feats": feats})
	)
	bonuses.load_record(record)
	var found_warning: bool = false
	var cards: VBoxContainer = bonuses.get("_origin_cards") as VBoxContainer
	for card: Node in cards.get_children():
		for child: Node in card.get_children():
			if child is HBoxContainer:
				for control: Node in child.get_children():
					if control is Button and String((control as Button).text) == "⚠":
						found_warning = true
	assert(found_warning, "An unchosen Telepathic must appear on the Bonus origin list with a warning")
	bonuses.call("_open_feat_ability_choice", sid)
	var picker: OptionButton = bonuses.get("_choice_selector") as OptionButton
	assert(picker.item_count == 4)
	assert(String(picker.get_item_metadata(1)) == "int")
	picker.select(1)
	bonuses.call("_apply_feat_ability_choice")
	assert(not captures.is_empty(), "Completing the choice must notify the creature sheet")
	var sent: Dictionary = captures.back()
	assert(not (sent.get("feats", []) as Array).is_empty(), "The selected feat must be saved in the callback")
	record.feats_catalog = sent.get("feats", [])
	assert(Bonuses.value(record, "ability:int") == 11)
	assert(Pending.missing_feat_abilities(record).is_empty())
	assert(not Pending.section_warnings(record).has(3), "Warning disappears after selection")
	# A completed choice stays editable from the same Bonus origin.
	bonuses.load_record(record)
	bonuses.call("_open_feat_ability_choice", sid)
	assert(picker.selected == 1, "Edit dialog should show the existing INT choice")
	picker.select(2)
	bonuses.call("_apply_feat_ability_choice")
	assert(captures.size() >= 2, "Editing existing selection must notify the sheet")
	record.feats_catalog = (captures.back() as Dictionary).get("feats", [])
	assert(Bonuses.value(record, "ability:int") == 10, "Changing the pick removes its old bonus")
	assert(Bonuses.value(record, "ability:wis") == 11)
	creature_area.call("_refresh_choice_warnings", record)
	assert(not global_warning.visible, "Completing the last choice clears top-level warning")
	assert(not section_picker.get_item_text(3).begins_with("⚠ "), "Dropdown item clears its warning")
	record.feats_catalog = [
		{"name": "Telepathic", "source": "TCE", "ability_choice": "wis", "origin_id": ""},
		{"name": "Telepathic", "source": "TCE", "ability_choice": "wis", "origin_id": "custom|2"}
	]
	assert(Bonuses.value(record, "ability:wis") == 11, "Two origins must not double a single feat's bonus")
	record.feats_catalog = []
	assert(Bonuses.value(record, "ability:wis") == 10)
	assert(Pending.missing_feat_abilities(record).is_empty())

	# Choosing proficiencies is independent and its missing quota belongs
	# to the Competenze dropdown item, not Bonus.
	var incomplete: Dictionary = {"id": "source:test", "requirements": [{
		"kind": "skill", "count": 1, "data": {"choose": {"from": ["arcana", "history"]}}
	}]}
	assert(Proficiencies.requirement_missing(incomplete, [], {"source:test": true}).size() == 1)
	ui.queue_free()
	await process_frame
	print("PASS: feat bonus warnings, selection, activation, and provenance")
	quit()
