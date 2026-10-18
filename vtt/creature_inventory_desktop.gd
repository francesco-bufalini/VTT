extends VBoxContainer
# Desktop-only presentation. The owning inventory tab remains the single
# authority for saved item state, equipped slots, infusions and notifications.
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const DocumentStore = preload("res://vtt/document_homebrew.gd")
const BonusRules = preload("res://vtt/creature_bonus_rules.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

const QUANTITY_COLUMN := 4
const MINUS_BUTTON := 100
const PLUS_BUTTON := 101
const REMOVE_BUTTON := 102
const MENU_REMOVE := 1
const MENU_CATALOG := 2

var _tab: Node
var _owned_tree: Tree
var _scroll_tree: Tree
var _attunement_tree: Tree
var _main: OptionButton
var _off: OptionButton
var _armor: OptionButton
var _main_size: OptionButton
var _off_size: OptionButton
var _context_menu: PopupMenu
var _context_index := -1
var _maximum: SpinBox
var _maximum_label: Label
var _owned_heading: Label
var _scroll_heading: Label
var _equipment_heading: Label
var _attune_label: Label
var _slot_indices: Dictionary = {}
var _record: Dictionary = {}
var _minus_icon: Texture2D
var _plus_icon: Texture2D
var _remove_icon: Texture2D
var _updating := false
# One inventory table owns the current highlight.
var _active_view := "owned"


func _t(it: String, en: String) -> String:
	return en if String(_tab.get("_gui_language")) == "en" else it


func setup(tab: Node, description: Control) -> void:
	_tab = tab
	# The description and search list must not swallow wheel events needed by
	# the outer creature sheet when their own viewport reaches its boundary.
	description.mouse_force_pass_scroll_events = true
	description.set_meta("pass_wheel_to_sheet", true)
	var catalog_list: ItemList = _tab.get("_catalog_list")
	catalog_list.mouse_force_pass_scroll_events = true
	catalog_list.set_meta("pass_wheel_to_sheet", true)
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minus_icon = _symbol_texture(false)
	_plus_icon = _symbol_texture(true)
	_remove_icon = _remove_texture()
	var heading := Label.new()
	_owned_heading = heading
	heading.text = _t("Oggetti posseduti", "Owned items")
	heading.add_theme_font_size_override("font_size", 15)
	add_child(heading)
	_owned_tree = _make_tree([_t("Equip.", "Equipped"), _t("Valore", "Value"), _t("Peso", "Weight"), _t("Rarità", "Rarity"), _t("Quantità", "Quantity"), _t("Fonte", "Source"), _t("Proprietà / CA", "Properties / AC"), _t("Nome", "Name")], 185)
	_owned_tree.columns = 8
	_owned_tree.set_column_expand(7, true)
	for column: int in range(7):
		_owned_tree.set_column_expand(column, false)
	for column: int in range(8):
		_owned_tree.set_column_custom_minimum_width(column, [65, 65, 60, 77, 104, 52, 122, 235][column])
	_owned_tree.item_selected.connect(_on_owned_selected)
	_owned_tree.gui_input.connect(_on_owned_mouse_event)
	_owned_tree.item_edited.connect(_on_owned_edited)
	_owned_tree.button_clicked.connect(_on_quantity_button)
	add_child(_owned_tree)

	var scroll_heading := Label.new()
	_scroll_heading = scroll_heading
	scroll_heading.text = _t("Pergamene possedute", "Owned spell scrolls")
	scroll_heading.add_theme_font_size_override("font_size", 15)
	add_child(scroll_heading)
	_scroll_tree = _make_tree([_t("Quantità", "Quantity"), _t("Livello", "Level"), _t("Incantesimo", "Spell")], 100)
	_scroll_tree.columns = 3
	_scroll_tree.set_column_expand(0, false)
	_scroll_tree.set_column_expand(1, false)
	_scroll_tree.set_column_custom_minimum_width(0, 104)
	_scroll_tree.set_column_custom_minimum_width(1, 58)
	_scroll_tree.item_selected.connect(_on_scroll_selected)
	_scroll_tree.gui_input.connect(_on_scroll_mouse_event)
	_scroll_tree.item_edited.connect(_on_scroll_edited)
	_scroll_tree.button_clicked.connect(_on_quantity_button)
	add_child(_scroll_tree)

	var description_parent: Node = description.get_parent()
	description_parent.remove_child(description)
	add_child(description)
	var equipment_heading := Label.new()
	_equipment_heading = equipment_heading
	equipment_heading.text = _t("Equipaggiamento", "Equipment")
	equipment_heading.add_theme_font_size_override("font_size", 15)
	add_child(equipment_heading)
	var triangle := VBoxContainer.new()
	triangle.add_theme_constant_override("separation", 5)
	add_child(triangle)
	var hands := HBoxContainer.new()
	hands.add_theme_constant_override("separation", 12)
	triangle.add_child(hands)
	_main = _slot_picker(hands, _t("Mano principale", "Main hand"), "main")
	_off = _slot_picker(hands, _t("Mano secondaria", "Off hand"), "off")
	var armor_row := HBoxContainer.new()
	armor_row.alignment = BoxContainer.ALIGNMENT_CENTER
	triangle.add_child(armor_row)
	_armor = _slot_picker(armor_row, _t("Armatura", "Armor"), "body")

	_context_menu = PopupMenu.new()
	_context_menu.add_item(_t("Rimuovi", "Remove"), MENU_REMOVE)
	_context_menu.add_item(_t("Vedi nel bestiario", "View in bestiary"), MENU_CATALOG)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

	var attune_heading := HBoxContainer.new()
	add_child(attune_heading)
	var attune_label := Label.new()
	_attune_label = attune_label
	attune_label.text = _t("Oggetti che richiedono sintonia", "Attunement items")
	attune_label.add_theme_font_size_override("font_size", 15)
	attune_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attune_heading.add_child(attune_label)
	_maximum_label = Label.new()
	_maximum_label.text = _t("Massimo", "Maximum")
	attune_heading.add_child(_maximum_label)
	_maximum = SpinBox.new()
	_maximum.min_value = 0
	_maximum.max_value = 99
	_maximum.step = 1
	_maximum.rounded = true
	_maximum.custom_minimum_size.x = 65
	_maximum.value_changed.connect(_on_maximum_changed)
	attune_heading.add_child(_maximum)
	_attunement_tree = _make_tree([_t("Sintonia", "Attuned"), _t("Oggetto", "Item")], 100)
	_attunement_tree.columns = 2
	_attunement_tree.set_column_expand(0, false)
	_attunement_tree.set_column_custom_minimum_width(0, 95)
	_attunement_tree.item_edited.connect(_on_attunement_edited)
	_attunement_tree.item_selected.connect(_on_attunement_selected)
	add_child(_attunement_tree)


# Desktop headings are built once; changing the creature language must also
# refresh columns and slot captions, not only the saved item rows.
func refresh_captions() -> void:
	if _owned_tree == null:
		return
	_owned_heading.text = _t("Oggetti posseduti", "Owned items")
	_scroll_heading.text = _t("Pergamene possedute", "Owned spell scrolls")
	_equipment_heading.text = _t("Equipaggiamento", "Equipment")
	_attune_label.text = _t("Oggetti che richiedono sintonia", "Attunement items")
	for column: int in range(8):
		_owned_tree.set_column_title(column, [
			_t("Equip.", "Equipped"), _t("Valore", "Value"), _t("Peso", "Weight"), _t("Rarità", "Rarity"),
			_t("Quantità", "Quantity"), _t("Fonte", "Source"), _t("Proprietà / CA", "Properties / AC"),
			_t("Nome", "Name")][column])
	for column: int in range(3):
		_scroll_tree.set_column_title(column, [
			_t("Quantità", "Quantity"), _t("Livello", "Level"), _t("Incantesimo", "Spell")][column])
	for column: int in range(2):
		_attunement_tree.set_column_title(column, [
			_t("Sintonia", "Attuned"), _t("Oggetto", "Item")][column])
	(_main.get_parent().get_child(0) as Label).text = _t("Mano principale", "Main hand")
	(_off.get_parent().get_child(0) as Label).text = _t("Mano secondaria", "Off hand")
	(_armor.get_parent().get_child(0) as Label).text = _t("Armatura", "Armor")
	_maximum_label.text = _t("Massimo", "Maximum")
	_context_menu.set_item_text(0, _t("Rimuovi", "Remove"))
	_context_menu.set_item_text(1, _t("Vedi nel bestiario", "View in bestiary"))
	refresh()


func _make_tree(captions: Array, height: float) -> Tree:
	var tree := Tree.new()
	tree.hide_root = true
	tree.hide_folding = true
	tree.columns = captions.size()
	tree.column_titles_visible = true
	tree.select_mode = Tree.SELECT_ROW
	tree.custom_minimum_size.y = height
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Do not trap the parent sheet's wheel events inside short Tree lists.
	tree.mouse_force_pass_scroll_events = true
	tree.add_theme_stylebox_override("panel", preload("res://vtt/creature_sheet_style.gd").section_style())
	for column: int in range(captions.size()):
		tree.set_column_title(column, _t(String(captions[column]), String(captions[column])))
	return tree


func _slot_picker(parent: BoxContainer, label: String, slot: String) -> OptionButton:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(group)
	var caption := Label.new()
	caption.text = label
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	group.add_child(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	group.add_child(row)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.x = 148 if slot != "body" else 200
	picker.clip_text = true
	picker.fit_to_longest_item = false
	picker.item_selected.connect(_on_slot_selected.bind(slot))
	row.add_child(picker)
	if slot in ["main", "off"]:
		var weapon_size := OptionButton.new()
		weapon_size.custom_minimum_size.x = 116
		weapon_size.fit_to_longest_item = false
		weapon_size.clip_text = true
		weapon_size.tooltip_text = _t("Taglia dell'arma impugnata", "Equipped weapon size")
		weapon_size.item_selected.connect(_on_slot_size_selected.bind(slot))
		row.add_child(weapon_size)
		if slot == "main":
			_main_size = weapon_size
		else:
			_off_size = weapon_size
	return picker


func _symbol_texture(plus: bool) -> Texture2D:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x: int in range(2, 12):
		for y: int in range(6, 8):
			img.set_pixel(x, y, Color(0.87, 0.85, 0.72))
	if plus:
		for x: int in range(6, 8):
			for y: int in range(2, 12):
				img.set_pixel(x, y, Color(0.87, 0.85, 0.72))
	return ImageTexture.create_from_image(img)


func _remove_texture() -> Texture2D:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for n: int in range(3, 11):
		img.set_pixel(n, n, Color(0.96, 0.55, 0.49))
		img.set_pixel(13 - n, n, Color(0.96, 0.55, 0.49))
	return ImageTexture.create_from_image(img)


func load_record(record: Dictionary) -> void:
	_record = record.duplicate(true)
	_active_view = "owned"
	refresh()


func maximum_base() -> int:
	return int(_maximum.value) if _maximum != null else 3


func _on_maximum_changed(value: float) -> void:
	if _updating:
		return
	_record["attunement_max_base"] = int(value)
	# Keep the owning inventory model authoritative when switching to mobile.
	_tab.set("_attunement_max_base", int(value))
	_tab.call("_publish")
	refresh()


func _rows() -> Array:
	var raw: Variant = _tab.get("_inventory")
	return raw if raw is Array else []


func _definition(owned: Dictionary) -> Dictionary:
	return _tab.call("_catalog_entry", owned)


func _is_spell_scroll(owned: Dictionary, entry: Dictionary) -> bool:
	if DocumentStore.is_document(owned):
		return false
	var kind_code := String(entry.get("type", "")).split("|")[0].to_upper()
	var name := String(entry.get("name", owned.get("name", ""))).to_lower()
	return kind_code == "SC" or name.contains("spell scroll") or name.contains("pergamena di incantesimo")


func _spell_label(owned: Dictionary, entry: Dictionary) -> String:
	var raw: Variant = entry.get("spell_name", entry.get("spellName", entry.get("spell", "")))
	if raw is Dictionary:
		raw = (raw as Dictionary).get("name", "")
	elif raw is Array:
		raw = (raw as Array)[0] if not (raw as Array).is_empty() else ""
		if raw is Dictionary:
			raw = (raw as Dictionary).get("name", "")
	var spell_name := String(raw).strip_edges()
	if not spell_name.is_empty():
		return spell_name
	var name := String(owned.get("name", entry.get("name", ""))).strip_edges()
	# A generic scroll (e.g. "Spell Scroll (3rd Level)") names no spell.
	# Never present its level as though it were the incantation's name.
	var generic := RegEx.create_from_string("(?i)^(?:spell scroll|pergamena di incantesimo)\\s*(?:\\(.*\\))?$")
	if generic.search(name) != null:
		return _t("Incantesimo non specificato", "Unspecified spell")
	return name


func _spell_level(entry: Dictionary) -> String:
	var raw: Variant = entry.get("spell_level", entry.get("spellLevel", entry.get("level", "")))
	if raw != null and str(raw) != "":
		return str(raw)
	var name := String(entry.get("name", ""))
	var regex := RegEx.create_from_string("(\\d+)(?:st|nd|rd|th|°|º)?[- ]level")
	var match_result := regex.search(name.to_lower())
	return match_result.get_string(1) if match_result != null else "—"


func _formatted_number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, float(int(value))) else "%.2f" % value


func _value_total(entry: Dictionary, quantity: int) -> String:
	var raw: Variant = entry.get("value_gp", null)
	if raw != null and (raw is float or raw is int):
		return _formatted_number(float(raw) * quantity) + " mo"
	raw = entry.get("value", null)
	if raw is float or raw is int:
		return _formatted_number(float(raw) * quantity / 100.0) + " mo"
	return "—"


func _weight_total(entry: Dictionary, quantity: int) -> String:
	var raw: Variant = entry.get("weight", null)
	if raw is float or raw is int:
		return _formatted_number(float(raw) * quantity) + " lb"
	return "—"


func _characteristic(entry: Dictionary) -> String:
	var kind: String = ItemRules.kind(entry)
	if kind == "weapon":
		var properties: Variant = entry.get("properties", [])
		if properties is Array:
			var names := PackedStringArray()
			var labels := {
				"F": _t("Accurata", "Finesse"), "L": _t("Leggera", "Light"),
				"T": _t("Lancio", "Thrown"), "V": _t("Versatile", "Versatile"),
				"H": _t("Pesante", "Heavy"), "2H": _t("Due mani", "Two-handed"),
				"A": _t("Munizioni", "Ammunition"), "R": _t("Portata", "Reach"),
				"LD": _t("Caricamento", "Loading"), "RLD": _t("Ricarica", "Reload")
			}
			for property: Variant in properties:
				var code: String = String(property).split("|")[0].to_upper()
				names.append(String(labels.get(code, code)))
			return ", ".join(names) if not names.is_empty() else "—"
		return str(properties) if str(properties) != "" else "—"
	if kind == "shield":
		return "CA +%s" % str(entry.get("ac", 2))
	if kind == "armor":
		var base: String = str(entry.get("ac", 10))
		var armor_type: String = String(entry.get("type", "")).split("|")[0].to_upper()
		var limit: int = 2 if armor_type == "MA" else (0 if armor_type == "HA" else -1)
		if entry.has("dexterity_max"):
			limit = int(entry["dexterity_max"])
		if armor_type == "HA" and limit == 0:
			return "CA " + base
		if limit >= 0:
			return "CA " + base + " + min(DES, %d)" % limit
		return "CA " + base + " + DES"
	return "—"


func _rarity_label(entry: Dictionary) -> String:
	var rarity: String = String(entry.get("rarity", "")).strip_edges().to_lower()
	if rarity.is_empty() or rarity == "none":
		return "—"
	if String(_tab.get("_gui_language")) == "en":
		return rarity.capitalize()
	var italian := {
		"common": "Comune", "uncommon": "Non comune", "rare": "Raro",
		"very rare": "Molto raro", "legendary": "Leggendario",
		"artifact": "Artefatto", "varies": "Variabile"
	}
	return String(italian.get(rarity, rarity.capitalize()))


func _quantity_cell(cell: TreeItem, column: int, quantity: int, locked: bool) -> void:
	cell.set_cell_mode(column, TreeItem.CELL_MODE_STRING)
	cell.set_text(column, str(quantity))
	cell.set_editable(column, not locked)
	if quantity <= 1:
		cell.add_button(column, _remove_icon, REMOVE_BUTTON, false, _t("Rimuovi oggetto", "Remove item"))
	else:
		cell.add_button(column, _minus_icon, MINUS_BUTTON, locked, _t("Diminuisci", "Decrease"))
	cell.add_button(column, _plus_icon, PLUS_BUTTON, locked or quantity >= 99999, _t("Aumenta", "Increase"))


func refresh() -> void:
	if _tab == null or _owned_tree == null or not is_inside_tree():
		return
	_updating = true
	var selected_index: int = int(_tab.call("_selected_inventory_index"))
	_owned_tree.clear()
	_scroll_tree.clear()
	_attunement_tree.clear()
	var owned_root := _owned_tree.create_item()
	var scroll_root := _scroll_tree.create_item()
	var attune_root := _attunement_tree.create_item()
	var items := _rows()
	var attuned_count := 0
	for index: int in range(items.size()):
		if not items[index] is Dictionary:
			continue
		var owned: Dictionary = items[index]
		var entry: Dictionary = _definition(owned)
		var quantity: int = maxi(1, int(owned.get("quantity", 1)))
		var is_scroll: bool = _is_spell_scroll(owned, entry)
		var row: TreeItem = (scroll_root if is_scroll else owned_root).create_child()
		row.set_metadata(0, index)
		var locked: bool = DocumentStore.is_document(owned) or (owned.get("infusion", {}) is Dictionary and not (owned.get("infusion", {}) as Dictionary).is_empty())
		if is_scroll:
			_quantity_cell(row, 0, quantity, locked)
			row.set_text(1, _spell_level(entry))
			row.set_text(2, _spell_label(owned, entry))
		else:
			var kind: String = ItemRules.kind(entry)
			var slots: Array = ItemRules.slots(owned)
			var equipped := bool(owned.get("equipped", false))
			var icon := ""
			if "main" in slots:
				icon += "⚔"
			if "off" in slots:
				icon += "🛡"
			if "body" in slots:
				icon += "▣"
			if kind not in ["weapon", "armor", "shield", "document"]:
				icon = "✓" if equipped else ""
				# An outlined empty cell makes the double-click target explicit
				# without turning it into a single-click checkbox.
				row.set_custom_bg_color(0, Color(0.73, 0.63, 0.43, 0.70), true)
				row.set_tooltip_text(0, _t("Doppio clic nella casella per (dis)equipaggiare", "Double-click the outlined box to equip or stow"))
			if ItemRules.requires_attunement(entry) and bool(owned.get("attuned", false)) and icon.is_empty():
				icon = "✦"
			row.set_text(0, icon)
			row.set_custom_font_size(0, 12)
			row.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
			row.set_text(1, _value_total(entry, quantity))
			row.set_text(2, _weight_total(entry, quantity))
			row.set_text(3, _rarity_label(entry))
			_quantity_cell(row, QUANTITY_COLUMN, quantity, locked)
			row.set_text(5, String(entry.get("source", owned.get("source", ""))).to_upper())
			row.set_text(6, _characteristic(entry))
			row.set_tooltip_text(6, _characteristic(entry))
			row.set_text(7, String(owned.get("name", "")))
		if index == selected_index and _active_view == ("scroll" if is_scroll else "owned"):
			row.select(0)
		if ItemRules.requires_attunement(entry):
			var attune_row := attune_root.create_child()
			attune_row.set_metadata(0, index)
			attune_row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			attune_row.set_editable(0, true)
			var attuned: bool = bool(owned.get("attuned", false))
			attune_row.set_checked(0, attuned)
			attune_row.set_text(1, String(owned.get("name", "")))
			if index == selected_index and _active_view == "attunement":
				attune_row.select(0)
			if attuned:
				attuned_count += 1
				for col: int in range(2):
					attune_row.set_custom_bg_color(col, Color(0.22, 0.38, 0.29, 0.62))
	_record["inventory"] = items.duplicate(true)
	var bonus: int = BonusRules.bonus(_record, "attunement_max")
	var maximum: int = maxi(0, int(_record.get("attunement_max_base", 3)) + bonus)
	_maximum.set_value_no_signal(int(_record.get("attunement_max_base", 3)))
	_maximum.tooltip_text = _t("Base modificabile; bonus dei privilegi: %+d" % bonus, "Editable base; feature bonuses: %+d" % bonus)
	_maximum_label.text = _t("Sintonia %d/%d · Base" % [attuned_count, maximum], "Attuned %d/%d · Base" % [attuned_count, maximum])
	_rebuild_pickers(items)
	_updating = false


func _rebuild_pickers(items: Array) -> void:
	for slot: String in ["main", "off", "body"]:
		var picker: OptionButton = _main if slot == "main" else (_off if slot == "off" else _armor)
		picker.clear()
		_slot_indices[slot] = [-1]
		picker.add_item(_t("Nessuno", "None"))
		var selected := 0
		var main_owned: Dictionary = ItemRules.occupying(items, "main")
		var locked: bool = slot == "off" and not main_owned.is_empty() and (
			ItemRules.is_two_handed(_definition(main_owned)) or bool(_record.get("hand_grip_two_handed", false)))
		for index: int in range(items.size()):
			if not items[index] is Dictionary:
				continue
			var owned: Dictionary = items[index]
			var entry: Dictionary = _definition(owned)
			if int(owned.get("quantity", 0)) <= 0 or not ItemRules.valid_slot(entry, slot):
				continue
			if slot == "main" and ItemRules.kind(entry) == "shield":
				continue
			picker.add_item(String(owned.get("name", "")))
			(_slot_indices[slot] as Array).append(index)
			if slot in ItemRules.slots(owned):
				selected = picker.item_count - 1
		if locked:
			picker.set_item_text(0, _t("Occupata · due mani", "Occupied · two hands"))
			selected = 0
		picker.select(selected)
		picker.disabled = locked
		if locked:
			picker.tooltip_text = _t("La mano è occupata da un'arma impugnata a due mani", "Hand occupied by a two-handed weapon")
		else:
			picker.tooltip_text = ""
		if slot in ["main", "off"]:
			var size_picker: OptionButton = _main_size if slot == "main" else _off_size
			size_picker.clear()
			size_picker.add_item(_t("Creatura", "Creature") + " (" + _t(String(_tab.get("_creature_size_name")), String(_tab.get("_creature_size_name"))) + ")")
			for size_name: String in ItemRules.WEAPON_SIZES:
				size_picker.add_item(size_name)
			var equipped_weapon: Dictionary = ItemRules.occupying(items, slot)
			var is_weapon := not equipped_weapon.is_empty() and ItemRules.kind(_definition(equipped_weapon)) == "weapon"
			var overrides: Variant = equipped_weapon.get("instance_overrides", {})
			var size_name: String = String((overrides as Dictionary).get("weapon_size", "")) if overrides is Dictionary else ""
			size_picker.select(ItemRules.WEAPON_SIZES.find(size_name) + 1 if is_weapon else 0)
			size_picker.disabled = not is_weapon or locked


func _select_saved(index: int, view: String = "") -> void:
	var list: ItemList = _tab.get("_inventory_list")
	if index < 0 or index >= _rows().size():
		return
	if view in ["owned", "scroll", "attunement"]:
		_active_view = view
		# Godot Trees have independent selections. Keep one visible highlight.
		for other: Tree in [_owned_tree, _scroll_tree, _attunement_tree]:
			if (view == "owned" and other == _owned_tree) or (view == "scroll" and other == _scroll_tree) or (view == "attunement" and other == _attunement_tree):
				continue
			other.deselect_all()
	list.select(index)
	_tab.call("_on_inventory_selected", index)


func _on_owned_selected() -> void:
	if _updating:
		return
	var selected: TreeItem = _owned_tree.get_selected()
	if selected != null:
		_select_saved(int(selected.get_metadata(0)), "owned")


func _on_scroll_selected() -> void:
	if _updating:
		return
	var selected: TreeItem = _scroll_tree.get_selected()
	if selected != null:
		_select_saved(int(selected.get_metadata(0)), "scroll")


func _on_attunement_selected() -> void:
	if _updating:
		return
	var selected: TreeItem = _attunement_tree.get_selected()
	if selected != null:
		_select_saved(int(selected.get_metadata(0)), "attunement")


func _on_owned_mouse_event(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if _updating or click == null or not click.pressed or not click.double_click or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _owned_tree.get_column_at_position(click.position) != 0:
		return
	var selected: TreeItem = _owned_tree.get_item_at_position(click.position)
	if selected == null:
		return
	var index: int = int(selected.get_metadata(0))
	var owned: Dictionary = _rows()[index]
	var entry: Dictionary = _definition(owned)
	if ItemRules.kind(entry) in ["weapon", "armor", "shield", "document"] or ItemRules.requires_attunement(entry):
		return
	# A click still holds the Tree's mouse selection lock. Deferred mutation
	# avoids clearing its rows from within that event's synchronous callbacks.
	call_deferred("_apply_generic_equipment", index, not bool(owned.get("equipped", false)))


func _apply_generic_equipment(index: int, equipped: bool) -> void:
	if index < 0 or index >= _rows().size():
		return
	_select_saved(index, "owned")
	_tab.call("_set_generic_equipment", equipped)


func _update_quantity(index: int, requested: int) -> void:
	var rows := _rows()
	if index < 0 or index >= rows.size():
		return
	var entry: Dictionary = _definition(rows[index])
	_select_saved(index, "scroll" if _is_spell_scroll(rows[index], entry) else "owned")
	var spinner: SpinBox = _tab.get("_quantity")
	spinner.set_value_no_signal(clampi(requested, 1, 99999))
	_tab.call("_on_quantity_changed", float(clampi(requested, 1, 99999)))
	# The owning tab refreshes the desktop tables after the event is over.


func _on_quantity_button(item: TreeItem, _column: int, button_id: int, _mouse_button: int) -> void:
	if _updating or button_id not in [MINUS_BUTTON, PLUS_BUTTON]:
		return
	var index: int = int(item.get_metadata(0))
	var quantity: int = int(_rows()[index].get("quantity", 1))
	call_deferred("_update_quantity", index, quantity + (1 if button_id == PLUS_BUTTON else -1))


func _on_owned_edited() -> void:
	if _updating or _owned_tree.get_edited_column() != QUANTITY_COLUMN:
		return
	var row: TreeItem = _owned_tree.get_edited()
	if row != null:
		call_deferred("_update_quantity", int(row.get_metadata(0)), int(row.get_text(QUANTITY_COLUMN)))


func _on_scroll_edited() -> void:
	if _updating or _scroll_tree.get_edited_column() != 0:
		return
	var row: TreeItem = _scroll_tree.get_edited()
	if row != null:
		call_deferred("_update_quantity", int(row.get_metadata(0)), int(row.get_text(0)))


func _on_attunement_edited() -> void:
	if _updating or _attunement_tree.get_edited_column() != 0:
		return
	var row: TreeItem = _attunement_tree.get_edited()
	if row != null:
		call_deferred("_apply_attunement", int(row.get_metadata(0)), row.is_checked(0))


func _apply_attunement(index: int, attuned: bool) -> void:
	if index < 0 or index >= _rows().size():
		return
	_select_saved(index, "attunement")
	_tab.call("_set_attunement", attuned)


func _on_slot_selected(choice: int, slot: String) -> void:
	if _updating:
		return
	var indices: Array = _slot_indices.get(slot, [])
	if choice < 0 or choice >= indices.size():
		return
	var index: int = int(indices[choice])
	if index < 0:
		_tab.call("_clear_slot", slot)
	else:
		_select_saved(index)
		_tab.call("_equip_selected", slot)
