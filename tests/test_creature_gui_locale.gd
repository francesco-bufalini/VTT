extends SceneTree

const Locale = preload("res://vtt/creature_gui_locale.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sheet := VBoxContainer.new()
	root.add_child(sheet)
	var heading := Label.new()
	heading.text = "ARCHIVIO DELLE CREATURE"
	sheet.add_child(heading)
	var ability := Label.new()
	ability.text = "STR"
	sheet.add_child(ability)
	var skill := Label.new()
	skill.text = "Acrobazia · DEX"
	sheet.add_child(skill)
	var status := Label.new()
	status.text = "Nessuna creatura corrispondente."
	sheet.add_child(status)
	var tooltip := Button.new()
	tooltip.text = "Chiudi"
	tooltip.tooltip_text = "Crea una nuova scheda di personaggio"
	sheet.add_child(tooltip)
	var choices := OptionButton.new()
	choices.add_item("Forza", 17)
	choices.add_item("Destrezza", 18)
	choices.select(0)
	sheet.add_child(choices)
	var menu := PopupMenu.new()
	menu.add_item("Cedi controllo…", 4)
	sheet.add_child(menu)
	var tabs := TabContainer.new()
	sheet.add_child(tabs)
	var statistics := Control.new()
	statistics.name = "Statistiche"
	tabs.add_child(statistics)
	var input := LineEdit.new()
	input.text = "Storia" # User data must never be translated.
	input.placeholder_text = "Cerca tra le mie creature…"
	sheet.add_child(input)
	var preview := RichTextLabel.new()
	preview.text = "SALTO IN LUNGO\\nCon rincorsa (almeno 10 ft): 12 ft"
	preview.set_meta("creature_gui_text", true)
	sheet.add_child(preview)
	var compendium := RichTextLabel.new()
	compendium.text = "Storia" # Bestiary and feature descriptions stay verbatim.
	sheet.add_child(compendium)
	var catalog := ItemList.new()
	catalog.add_item("Storia")
	sheet.add_child(catalog)
	var unrelated := Label.new()
	unrelated.text = "Chiudi"
	root.add_child(unrelated)

	Locale.apply(sheet, "en")
	assert(heading.text == "CREATURE ARCHIVE")
	assert(ability.text == "STR")
	assert(skill.text == "Acrobatics · DEX")
	assert(status.text == "No matching creatures.")
	assert(tooltip.text == "Close" and tooltip.tooltip_text == "Create a new character sheet")
	assert(choices.get_item_text(0) == "Strength" and choices.selected == 0 and choices.get_item_id(0) == 17)
	assert(menu.get_item_text(0) == "Transfer control…" and menu.get_item_id(0) == 4)
	assert(tabs.get_tab_title(0) == "Statistics" and statistics.name == "Statistiche")
	assert(input.text == "Storia" and input.placeholder_text == "Search my creatures…")
	assert(compendium.text == "Storia" and catalog.get_item_text(0) == "Storia")
	assert(preview.text == "LONG JUMP\\nWith a run-up (at least 10 ft): 12 ft")
	assert(unrelated.text == "Chiudi", "Localization must not touch unrelated VTT controls")

	# Dynamic UI updates and repeated passes must preserve the original source.
	status.text = "Iniziativa"
	Locale.apply(sheet, "en")
	Locale.apply(sheet, "en")
	assert(status.text == "Initiative")
	Locale.apply(sheet, "it")
	assert(heading.text == "ARCHIVIO DELLE CREATURE")
	assert(ability.text == "FOR", "Italian strength abbreviation must be FOR")
	assert(skill.text == "Acrobazia · DES", "Italian dexterity abbreviation must be DES")
	assert(status.text == "Iniziativa")
	assert(preview.text.begins_with("SALTO IN LUNGO"))
	assert(tooltip.text == "Chiudi")
	assert(tabs.get_tab_title(0) == "Statistiche")
	assert(choices.get_item_text(0) == "Forza" and choices.selected == 0)
	Locale.apply(sheet, "en")
	assert(ability.text == "STR" and skill.text == "Acrobatics · DEX")
	assert(tabs.get_tab_title(0) == "Statistics")

	# Persistence remains a local GUI preference, not a creature-data field.
	var previous := Locale.read_locale()
	Locale.write_locale("en")
	assert(Locale.read_locale() == "en")
	Locale.write_locale("it")
	assert(Locale.read_locale() == "it")
	Locale.write_locale(previous)
	print("PASS: creature GUI localization")
	quit()
