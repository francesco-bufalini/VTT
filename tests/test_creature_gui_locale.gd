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
	preview.text = "SALTO IN LUNGO\nCon rincorsa (almeno 10 ft): 12 ft"
	preview.set_meta("creature_gui_text", true)
	sheet.add_child(preview)
	var compendium := RichTextLabel.new()
	compendium.text = "Storia" # Bestiary and feature descriptions stay verbatim.
	sheet.add_child(compendium)
	var catalog := ItemList.new()
	catalog.add_item("Storia")
	sheet.add_child(catalog)
	var natural_ac := Label.new()
	natural_ac.text = "CA naturale · formula"
	sheet.add_child(natural_ac)
	var hand := OptionButton.new()
	hand.add_item("Niente", 0)
	hand.add_item("Longsword · due mani", 1)
	hand.select(1)
	sheet.add_child(hand)
	var equipment_hint := Label.new()
	equipment_hint.text = "Mano secondaria"
	sheet.add_child(equipment_hint)
	var owned_name := Button.new()
	owned_name.text = "Storia"
	owned_name.set_meta("creature_gui_data", true)
	sheet.add_child(owned_name)
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
	assert(preview.text == "LONG JUMP\nWith a run-up (at least 10 ft): 12 ft")
	assert(owned_name.text == "Storia", "Player-created creature names must not be translated")
	assert(unrelated.text == "Chiudi", "Localization must not touch unrelated VTT controls")
	assert(natural_ac.text == "Natural AC · formula"
		and hand.get_item_text(0) == "None"
		and hand.get_item_text(1) == "Longsword · two-handed"
		and hand.selected == 1
		and equipment_hint.text == "Off hand",
		"Equipment UI must use creature-only locale without translating item names")
	assert(Locale.text_for("Equipaggiato", "en") == "Equipped"
		and Locale.text_for("Indossata", "en") == "Worn",
		"Owned item status labels must be translated")

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
	assert(hand.get_item_text(0) == "Niente"
		and hand.get_item_text(1) == "Longsword · due mani"
		and natural_ac.text == "CA naturale · formula")
	Locale.apply(sheet, "en")
	assert(ability.text == "STR" and skill.text == "Acrobatics · DEX")
	assert(tabs.get_tab_title(0) == "Statistics")

	# Newly introduced creature editors and statuses must not silently fall
	# back to Italian. Interpolated names and values remain unchanged.
	assert(Locale.text_for("Incantesimi attivi", "en") == "Active spells")
	assert(Locale.text_for("Rages", "it") == "Rages" and Locale.text_for("Wild Shape", "it") == "Wild Shape",
		"5etools feature and resource names must never be manually translated")
	assert(Locale.text_for("Caratteristica degli incantesimi", "en") == "Spellcasting ability")
	assert(Locale.text_for("Interrompi concentrazione", "en") == "End concentration")
	assert(Locale.text_for("Automatica", "en") == "Automatic")
	assert(Locale.text_for("Caratteristica: SAG  ·  Tiro per colpire: +5  ·  CD: 14\nConcentrazione: Bless", "en")
		== "Ability: WIS  ·  Spell attack: +5  ·  DC: 14\nConcentration: Bless",
		"Spellcasting summaries translate their GUI labels without changing the spell name")
	assert(Locale.text_for("Talenti posseduti", "en") == "Owned feats")
	assert(Locale.text_for("Only if finesse", "it") == "Solo se accurata")
	assert(Locale.text_for("Diseases / magical diseases", "it") == "Malattie / malattie magiche")
	assert(Locale.text_for("Livello 4", "en") == "Level 4")
	assert(Locale.text_for("Senza origine (2)", "en") == "Without origin (2)")
	assert(Locale.text_for("12 risultati", "en") == "12 results")
	assert(Locale.text_for("143 risultati (mostrati i primi 120; affina la ricerca)", "en")
		== "143 results (showing the first 120; refine the search)")
	assert(Locale.text_for("Dardo Incantato lanciato · nessun effetto VTT associato.", "en")
		== "Dardo Incantato cast · no associated VTT effect.")
	assert(Locale.text_for("Lancia Magic Missile (livello 3). Scegli quale slot consumare.", "en")
		== "Cast Magic Missile (level 3). Choose which slot to spend.")
	assert(Locale.text_for("3° livello · 2 rimasti", "en") == "Level 3 · 2 remaining")
	assert(Locale.text_for("Fonte: PHB", "en") == "Source: PHB")
	assert(Locale.text_for("Camminata: base 30 + bonus cumulabili +5 = 35 ft", "en")
		== "Walking: base 30 + stacking bonuses +5 = 35 ft")
	assert(Locale.text_for("Risultati: 250 di 300 · Affina i filtri per vedere gli altri", "en")
		== "Results: 250 of 300 · Refine filters to see more")
	assert(Locale.text_for("Starting Fighter", "it") == "Iniziale Fighter")
	assert(Locale.text_for("Multiclass Wizard", "it") == "Multiclasse Wizard")
	assert(Locale.text_for("Impossibile salvare inventario: permessi", "en")
		== "Could not save inventory: permessi")
	assert(Locale.text_for("⚠ Da scegliere: Acrobazia", "en")
		== "⚠ Choices required: Acrobazia")
	assert(Locale.text_for("PF della forma non disponibili: errore · Inserisci PF manualmente.", "en")
		== "Form HP unavailable: errore · Enter HP manually.")
	var deletion: String = "Eliminare definitivamente 'Aria' dal tuo archivio?\nVerranno eliminati anche i suoi token presenti nella scena."
	assert(Locale.text_for(deletion, "en")
		== "Permanently delete 'Aria' from your archive?\nAll of its tokens in the scene will also be deleted.")
	assert(Locale.text_for("Una descrizione personalizzata di un incantesimo.", "en")
		== "Una descrizione personalizzata di un incantesimo.")

	var transient_dialog := ConfirmationDialog.new()
	transient_dialog.title = "Aggiungi un incantesimo attivo"
	transient_dialog.ok_button_text = "Applica"
	var transient_hint := Label.new()
	transient_hint.text = "Nessun incantesimo attivo."
	transient_dialog.add_child(transient_hint)
	sheet.add_child(transient_dialog)
	Locale.apply(transient_dialog, "en")
	assert(transient_dialog.title == "Add an active spell"
		and transient_dialog.ok_button_text == "Apply"
		and transient_hint.text == "No active spells.")
	Locale.apply(transient_dialog, "it")
	assert(transient_dialog.title == "Aggiungi un incantesimo attivo"
		and transient_hint.text == "Nessun incantesimo attivo.")

	# Titles, picker options and contextual hints added by the creature editors
	# must all work in English without modifying catalog or user-provided names.
	for row: Array in [
		["MINIATURE", "MINIATURES"],
		["TALENTI", "FEATS"],
		["Caratteristiche e abilità", "Abilities and skills"],
		["✕  Sezioni", "✕  Sections"],
		["Incantesimi concessi dalle origini", "Spells granted by origins"],
		["Incantesimi concessi dalle origini (talenti, razze, privilegi, oggetti)",
			"Spells granted by origins (feats, races, features, items)"],
		["Origini che concedono incantesimi", "Spell-granting origins"],
		["⚙ Origine e dettagli", "⚙ Origin and details"],
		["Cerca incantesimo...", "Search spells..."],
		["Scegli incantesimo…", "Choose a spell…"],
		["Metamagia · seleziona le opzioni da applicare a questo lancio",
			"Metamagic · choose options to apply to this casting"],
		["Prove di abilità · 4 bonus più alti", "Skill checks · 4 highest bonuses"],
		["Regole varianti · 2014", "Variant rules · 2014"],
		["Bonus con dadi · per origine", "Dice bonuses · by origin"],
		["Completa il bonus del talento", "Complete feat bonus"],
		["Cerca per nome…", "Search by name…"],
		["Mostra i dettagli dell'origine e della lista", "Show details of the origin and spell list"],
		["Invia una copia…", "Send a copy…"],
		["Nessuna", "None"],
		["Scegli base…", "Choose base…"],
		["Azioni della creatura", "Creature actions"],
		["Tracker (anche di un'altra origine)", "Tracker (including one from another origin)"],
		["Apri il testo originale su 5etools", "Open the original text on 5etools"],
	]:
		assert(Locale.text_for(String(row[0]), "en") == String(row[1]),
			"Untranslated English creature UI: " + String(row[0]))
	for row: Array in [
		["4 tratti", "4 traits"],
		["Slot 3° livello", "Level 3 slot"],
		["Patto · 2° livello", "Pact · level 2"],
		["Slot · liv. 3+", "Slot · lvl. 3+"],
		["4 incantesimi selezionati · Cambia", "4 spells selected · Change"],
		["Mostra altri incantesimi (3 rimanenti)", "Show more spells (3 remaining)"],
		["Invia Runa del drago: scegli destinatari", "Send Runa del drago: choose recipients"],
		["Lancia Aria d'Acqua. Gli slot disponibili possono provenire da qualsiasi classe.",
			"Cast Aria d'Acqua. Available slots may come from any class."],
		["Lista: Druido", "List: Druido"],
	]:
		assert(Locale.text_for(String(row[0]), "en") == String(row[1]),
			"Untranslated dynamic English UI: " + String(row[0]))
	var section_panel := VBoxContainer.new()
	sheet.add_child(section_panel)
	var section_header := Label.new()
	section_header.text = "Incantesimi concessi dalle origini"
	section_panel.add_child(section_header)
	var section_picker := OptionButton.new()
	section_picker.add_item("Senza tracker", 42)
	section_panel.add_child(section_picker)
	Locale.apply(section_panel, "en")
	assert(section_header.text == "Spells granted by origins"
		and section_picker.get_item_text(0) == "No tracker"
		and section_picker.get_item_id(0) == 42)
	Locale.apply(section_panel, "it")
	assert(section_header.text == "Incantesimi concessi dalle origini"
		and section_picker.get_item_text(0) == "Senza tracker")
	assert(Locale.text_for("Wild Shape", "en") == "Wild Shape"
		and Locale.text_for("Runa del drago", "en") == "Runa del drago",
		"Localized UI must leave catalog and free-form data untouched")

	# Persistence remains a local GUI preference, not a creature-data field.
	var previous := Locale.read_locale()
	Locale.write_locale("en")
	assert(Locale.read_locale() == "en")
	Locale.write_locale("it")
	assert(Locale.read_locale() == "it")
	Locale.write_locale(previous)
	print("PASS: creature GUI localization")
	quit()
