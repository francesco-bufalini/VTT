extends RefCounted

# A small reusable popup for local catalog creation. The normal homebrew
# loader remains the single source of truth for definitions and stable IDs.
const Store = preload("res://vtt/quick_custom_catalog.gd")
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")
const KINDS := [
	["skill", "Abilità"], ["tool", "Strumenti"], ["language", "Linguaggi"],
	["weapon", "Armi"], ["armor", "Armature"], ["save", "Tiri salvezza"],
	["expertise", "Maestria"]
]


static func _options(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys: Array[String] = []
	match kind:
		"skill", "expertise":
			for key: String in Rules.SKILLS:
				keys.append(key)
		"tool":
			for group: String in Rules.TOOL_TYPE_FALLBACK:
				for key: String in Rules.TOOL_TYPE_FALLBACK[group]:
					if key not in keys:
						keys.append(key)
		"language":
			for entry: Dictionary in Rules.language_options():
				var key: String = String(entry.get("key", ""))
				if key not in keys:
					keys.append(key)
		"weapon":
			keys.append_array(["simple", "martial", "all"])
		"armor":
			for key: String in Rules.ARMORS:
				keys.append(key)
		"save":
			for key: String in Rules.ABILITIES:
				keys.append(key)
	keys.sort()
	for key: String in keys:
		result.append({"key": key, "label": key.capitalize()})
	return result


static func _add_field(panel: VBoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	panel.add_child(label)


static func create_popup(parent: Control, category: String, on_created: Callable) -> void:
	if category not in Store.ALLOWED:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = {
		"backgrounds": "Nuovo background personalizzato",
		"feats": "Nuovo talento personalizzato",
		"items": "Nuovo oggetto personalizzato"
	}[category]
	dialog.ok_button_text = "Salva nel catalogo"
	dialog.cancel_button_text = "Annulla"
	parent.add_child(dialog)
	dialog.popup_hide.connect(func() -> void: dialog.queue_free())
	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(330, 220)
	dialog.add_child(scroller)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 310
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(form)
	_add_field(form, "Nome")
	var name := LineEdit.new()
	name.placeholder_text = "Nome del contenuto personalizzato"
	form.add_child(name)
	_add_field(form, "Descrizione")
	var description := TextEdit.new()
	description.custom_minimum_size.y = 92
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(description)
	var proficiencies: Array[Dictionary] = []
	if category != "items":
		_add_field(form, "Competenze concesse (puoi aggiungerne più di una)")
		var pick_row := HBoxContainer.new()
		form.add_child(pick_row)
		var kind := OptionButton.new()
		kind.custom_minimum_size.x = 120
		for pair: Array in KINDS:
			kind.add_item(String(pair[1]))
			kind.set_item_metadata(kind.item_count - 1, String(pair[0]))
		pick_row.add_child(kind)
		var chosen := OptionButton.new()
		chosen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick_row.add_child(chosen)
		var granted := ItemList.new()
		granted.custom_minimum_size.y = 80
		form.add_child(granted)
		var actions := HBoxContainer.new()
		form.add_child(actions)
		var add := Button.new()
		add.text = "+ Competenza"
		actions.add_child(add)
		var remove := Button.new()
		remove.text = "Rimuovi selezionata"
		actions.add_child(remove)
		var choices: Array[Dictionary] = []
		var update_choices := func(_selected: int) -> void:
			chosen.clear()
			choices.clear()
			var selected_kind: String = String(kind.get_item_metadata(kind.selected))
			for entry: Dictionary in _options(selected_kind):
				choices.append(entry)
				chosen.add_item(String(entry["label"]))
		kind.item_selected.connect(update_choices)
		update_choices.call(0)
		add.pressed.connect(func() -> void:
			if chosen.selected < 0 or chosen.selected >= choices.size():
				return
			var entry: Dictionary = choices[chosen.selected]
			var grant: Dictionary = {
				"kind": String(kind.get_item_metadata(kind.selected)),
				"key": String(entry["key"])
			}
			if grant in proficiencies:
				return
			proficiencies.append(grant)
			granted.add_item("%s · %s" % [
				kind.get_item_text(kind.selected), entry["label"]])
		)
		remove.pressed.connect(func() -> void:
			var indices: PackedInt32Array = granted.get_selected_items()
			if not indices.is_empty():
				proficiencies.remove_at(indices[0])
				granted.remove_item(indices[0])
		)
	var item_type: OptionButton
	var rarity: OptionButton
	var value: SpinBox
	if category == "items":
		_add_field(form, "Tipo")
		item_type = OptionButton.new()
		for pair: Array in [
			["Oggetto", "other", "OTH"], ["Oggetto magico", "magic", "OTH"],
			["Arma", "weapon", "M"], ["Armatura", "armor", "LA"],
			["Scudo", "shield", "S"], ["Strumento", "tool", "T"]
		]:
			item_type.add_item(String(pair[0]))
			item_type.set_item_metadata(item_type.item_count - 1,
				{"custom_item_type": pair[1], "type": pair[2]})
		form.add_child(item_type)
		_add_field(form, "Rarità")
		rarity = OptionButton.new()
		for pair: Array in [
			["Comune / non magico", "none"], ["Comune", "common"],
			["Non comune", "uncommon"], ["Raro", "rare"],
			["Molto raro", "very rare"], ["Leggendario", "legendary"],
			["Artefatto", "artifact"]
		]:
			rarity.add_item(String(pair[0]))
			rarity.set_item_metadata(rarity.item_count - 1, String(pair[1]))
		form.add_child(rarity)
		_add_field(form, "Valore (mo)")
		value = SpinBox.new()
		value.min_value = 0
		value.max_value = 100000000
		value.step = 1
		value.rounded = true
		form.add_child(value)
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(message)
	dialog.confirmed.connect(func() -> void:
		if name.text.strip_edges().is_empty():
			return
		var details: Dictionary = {}
		if category == "items":
			details = (item_type.get_item_metadata(item_type.selected) as Dictionary).duplicate(true)
			details["rarity"] = String(rarity.get_item_metadata(rarity.selected))
			details["value"] = int(value.value)
		var saved: Dictionary = Store.create(category, name.text, description.text,
			proficiencies, details)
		if not saved.is_empty() and on_created.is_valid():
			on_created.call(saved)
	)
	DialogLayout.popup(dialog, Vector2i(520, 490), 0.90)
	name.grab_focus.call_deferred()


static func delete_popup(parent: Control, entry: Dictionary, on_removed: Callable) -> void:
	if not Store.is_custom(entry):
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Elimina contenuto personalizzato"
	dialog.ok_button_text = "Elimina"
	dialog.cancel_button_text = "Annulla"
	dialog.dialog_text = "Eliminare '%s' dal catalogo locale?\nLe copie già assegnate ai personaggi non saranno cancellate automaticamente." % String(entry.get("name", ""))
	parent.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		if Store.remove(entry) and on_removed.is_valid():
			on_removed.call()
	)
	dialog.popup_hide.connect(func() -> void: dialog.queue_free())
	DialogLayout.popup(dialog, Vector2i(455, 200), 0.90)
