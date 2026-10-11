extends Node

# Read-only, role-independent reference browser. Creature sheets belong to CreatureArea.
const BestiaryClient = preload("res://vtt/bestiary_5etools_client.gd")
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const FiveToolsText = preload("res://vtt/five_tools_rich_text.gd")

const SECTIONS := {
	"Bestiario": "monsters",
	"Incantesimi": "spells",
	"Oggetti magici": "magic_items",
	"Oggetti mondani": "mundane_items",
	"Documenti": "documents",
	"Armi": "weapons",
	"Armature": "armor",
	"Strumenti": "tools",
	"Classi": "classes",
	"Razze e specie": "races",
	"Talenti": "feats",
	"Background": "backgrounds",
	"Privilegi di classe": "class_features",
	"Tratti della specie": "species_traits",
	"Privilegi opzionali": "optional_features",
	"Condizioni": "conditions",
	"Effetti": "effects",
	"Malattie": "diseases"
}
var board_root: Node3D
var _panel: PanelContainer
var _category: OptionButton
var _filter: LineEdit
var _list: ItemList
var _details: RichTextLabel
var _status: Label
var _client: Node
var _monsters: Array[Dictionary] = []
var _shown: Array[Dictionary] = []
var _active_request := ""

func setup(root: Node3D) -> void:
	board_root = root
	_client = BestiaryClient.new()
	_client.name = "CompendiumBestiaryClient"
	add_child(_client)
	_client.call("setup")
	_client.catalog_ready.connect(_on_bestiary_ready)
	_client.catalog_failed.connect(func(message: String) -> void: _status.text = message)
	_client.creature_ready.connect(_on_creature_ready)
	_client.creature_failed.connect(_on_creature_failed)
	_build_ui()
	_monsters = ContentCatalog.home_entries("monsters")
	_refresh()
	if DisplayServer.get_name() != "headless":
		_client.call("load_catalog")

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CompendioPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 26.0
	_panel.offset_top = 52.0
	_panel.offset_right = -26.0
	_panel.offset_bottom = -24.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.z_index = 30
	_panel.hide()
	(board_root.get_node("UI") as CanvasLayer).add_child(_panel)
	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "Compendio · Catalogo e contenuti personalizzati"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var reload := Button.new()
	reload.text = "Aggiorna"
	reload.pressed.connect(_reload)
	header.add_child(reload)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(hide_panel)
	header.add_child(close)
	_status = Label.new()
	outer.add_child(_status)
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 410
	outer.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	columns.add_child(left)
	_category = OptionButton.new()
	for section: String in SECTIONS.keys():
		_category.add_item(section)
		_category.set_item_metadata(_category.item_count - 1, String(SECTIONS[section]))
	_category.item_selected.connect(func(_index: int) -> void: _refresh())
	left.add_child(_category)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Cerca per nome o fonte..."
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_query: String) -> void: _refresh())
	left.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_show_selected)
	_list.item_activated.connect(_show_selected)
	left.add_child(_list)
	_details = RichTextLabel.new()
	FiveToolsText.style(_details)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(_details)

func is_panel_open() -> bool:
	return _panel != null and _panel.visible

func toggle_panel() -> void:
	if is_panel_open():
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	var creature_area: Node = board_root.get_node_or_null("CreatureArea")
	if creature_area != null and creature_area.has_method("is_panel_open") and bool(creature_area.call("is_panel_open")):
		creature_area.call("hide_panel")
	_panel.show()
	if board_root.has_method("release_camera_control"):
		board_root.call("release_camera_control")

func hide_panel() -> void:
	_panel.hide()
	if board_root.has_method("capture_camera_control"):
		board_root.call("capture_camera_control")

func _unhandled_input(event: InputEvent) -> void:
	if is_panel_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_panel()
		get_viewport().set_input_as_handled()

func _reload() -> void:
	ContentCatalog.reload_homebrew()
	_refresh()
	if DisplayServer.get_name() != "headless":
		_client.call("load_catalog", true)

func _on_bestiary_ready(entries: Array[Dictionary]) -> void:
	_monsters = ContentCatalog.merge("monsters", entries)
	if _current_category() == "monsters":
		_refresh()

func _current_category() -> String:
	if _category == null or _category.selected < 0:
		return "monsters"
	return String(_category.get_item_metadata(_category.selected))

func _entries_for(category: String) -> Array[Dictionary]:
	if category == "monsters":
		return _monsters
	if category == "spells":
		return SpellCatalog.all_spells()
	if category in ["conditions", "diseases", "effects"]:
		var found: Array[Dictionary] = []
		for definition: Dictionary in ContentCatalog.condition_definitions():
			if String(definition.get("category", "conditions")) == category:
				found.append(definition)
		return found
	return PlayerCatalog.entries(category)

func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	_shown.clear()
	_details.text = ""
	var needle := _filter.text.strip_edges().to_lower()
	for entry: Dictionary in _entries_for(_current_category()):
		var label := String(entry.get("name", ""))
		var source := String(entry.get("source", ""))
		var searchable := (label + " " + source).to_lower()
		if not needle.is_empty() and needle not in searchable:
			continue
		_shown.append(entry)
		_list.add_item("%s · %s" % [label, source])
		if _shown.size() >= 350:
			break
	_status.text = "%d risultati (max 350). Apri una voce per consultarne il testo." % _shown.size()

func _show_selected(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	var entry: Dictionary = _shown[index]
	if _current_category() == "monsters":
		_details.text = "Caricamento stat block di %s..." % String(entry.get("name", ""))
		if String(entry.get("origin", "")) == "homebrew":
			_render(entry)
			return
		_active_request = "compendium:%d" % Time.get_ticks_usec()
		_client.call("request_creature", String(entry.get("name", "")), String(entry.get("source", "")), _active_request)
	else:
		if _current_category() not in ["spells", "conditions", "diseases", "effects"]:
			_render_catalog_entry(_current_category(), entry)
		else:
			_render(entry)

func _render_catalog_entry(category: String, entry: Dictionary) -> void:
	var detailed: Dictionary = PlayerCatalog.detailed_entry(category, entry)
	# Structured facts stay visible even when the source contains no prose.
	var lines: PackedStringArray = [
		FiveToolsText.blocks(PlayerCatalog.info_text(detailed))
	]
	var raw: Variant = detailed.get("entries", detailed.get("description", detailed.get("text", "")))
	var description: String = FiveToolsText.blocks(raw).strip_edges()
	if not description.is_empty():
		lines.append(FiveToolsText.section("Descrizione"))
		lines.append(description)
	var fluff: String = FiveToolsText.blocks(detailed.get("fluff", [])).strip_edges()
	if not fluff.is_empty():
		lines.append(FiveToolsText.section("Approfondimento"))
		lines.append(fluff)
	if description.is_empty() and fluff.is_empty():
		lines.append(FiveToolsText.meta("Descrizione estesa non presente nei dati disponibili."))
	_details.text = "\n\n".join(lines)


func _on_creature_ready(request_key: String, stat: Dictionary) -> void:
	if request_key != _active_request or _current_category() != "monsters":
		return
	_active_request = ""
	_render(stat)

func _on_creature_failed(request_key: String, message: String) -> void:
	if request_key == _active_request:
		_active_request = ""
		_details.text = FiveToolsText.blocks(message)

func _render(entry: Dictionary) -> void:
	var lines: PackedStringArray = [FiveToolsText.title(String(entry.get("name", "Voce")))]
	var source: String = String(entry.get("source", ""))
	if not source.is_empty():
		lines.append(FiveToolsText.meta("Fonte: " + source))
	for field: String in [
		"level", "school", "casting_time", "range", "components", "duration",
		"size", "type", "cr", "ac", "hp", "speed"
	]:
		if entry.has(field):
			lines.append(FiveToolsText.meta("%s: %s" % [
				field.capitalize(), _plain(entry[field])
			]))
	var abilities: PackedStringArray = []
	for stat: String in ["str", "dex", "con", "int", "wis", "cha"]:
		if entry.has(stat):
			abilities.append("%s %s" % [stat.to_upper(), _plain(entry[stat])])
	if not abilities.is_empty():
		lines.append(FiveToolsText.meta("   ".join(abilities)))
	for field: String in [
		"save", "skill", "resist", "immune", "conditionImmune",
		"senses", "languages", "classes"
	]:
		if entry.has(field):
			lines.append(FiveToolsText.meta("%s: %s" % [
				field.capitalize(), _plain(entry[field])
			]))
	var headings: Dictionary = {
		"trait": "Tratti", "action": "Azioni", "bonus": "Azioni bonus",
		"reaction": "Reazioni", "legendary": "Azioni leggendarie",
		"mythic": "Azioni mitiche", "lairActions": "Azioni della tana",
		"spellcasting": "Incantesimi"
	}
	for field: String in headings:
		if entry.has(field):
			var content: String = FiveToolsText.blocks(entry[field])
			if not content.is_empty():
				lines.append(FiveToolsText.section(String(headings[field])))
				lines.append(content)
	for field: String in ["description", "higher_levels", "entries"]:
		if entry.has(field):
			var content: String = FiveToolsText.blocks(entry[field])
			if not content.is_empty():
				lines.append(content)
	if not entry.has("entries") and not entry.has("description"):
		var extra: String = ContentCatalog.description(entry)
		if not extra.is_empty() and lines.size() == 1:
			lines.append(FiveToolsText.blocks(extra))
	_details.text = "\n\n".join(lines)


func _plain(value: Variant) -> String:
	if value is String or value is int or value is float:
		return str(value)
	if value is Array:
		var parts := PackedStringArray()
		for item: Variant in value:
			parts.append(_plain(item))
		return "\n".join(parts)
	if value is Dictionary:
		var dict: Dictionary = value as Dictionary
		if dict.has("entries"):
			return String(dict.get("name", "")) + ": " + _plain(dict.get("entries", []))
		if dict.has("entry"):
			return String(dict.get("name", "")) + ": " + _plain(dict.get("entry", ""))
		var parts := PackedStringArray()
		for key: Variant in dict.keys():
			parts.append("%s: %s" % [str(key), _plain(dict[key])])
		return ", ".join(parts)
	return str(value)
