extends VBoxContainer

# The traits sheet is a unified, level-ordered list. The data retains its
# catalog identifiers and source books; the UI exposes only useful origins.
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const RaceRules = preload("res://vtt/creature_race_rules.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const TraitText = preload("res://vtt/five_tools_rich_text.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Items = preload("res://vtt/creature_item_rules.gd")

var _origin_choice: OptionButton
var _search: LineEdit
var _counter: Label
var _scroll: ScrollContainer
var _cards_container: VBoxContainer
var _features: Array[Dictionary] = []
var _cards: Dictionary = {}
var _expanded: Dictionary = {}
var _active_origin := ""
var _record_id := ""


func setup() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	add_child(toolbar)
	var origin_caption := Label.new()
	origin_caption.text = "Origine"
	toolbar.add_child(origin_caption)
	_origin_choice = OptionButton.new()
	_origin_choice.fit_to_longest_item = false
	_origin_choice.custom_minimum_size.x = 190
	_origin_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_choice.item_selected.connect(_on_origin_selected)
	toolbar.add_child(_origin_choice)

	_search = LineEdit.new()
	_search.placeholder_text = "Cerca un privilegio…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _rebuild())
	add_child(_search)
	var actions := HBoxContainer.new()
	add_child(actions)
	_counter = Label.new()
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.add_theme_color_override("font_color", Color(0.74, 0.68, 0.60))
	actions.add_child(_counter)
	var expand := Button.new()
	expand.text = "Espandi tutti"
	expand.pressed.connect(func() -> void: _set_all_expanded(true))
	actions.add_child(expand)
	var collapse := Button.new()
	collapse.text = "Comprimi"
	collapse.pressed.connect(func() -> void: _set_all_expanded(false))
	actions.add_child(collapse)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Rebuilding expanded cards must not drag the scroll to the focused button.
	_scroll.follow_focus = false
	add_child(_scroll)
	_cards_container = VBoxContainer.new()
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.add_theme_constant_override("separation", 7)
	_scroll.add_child(_cards_container)
	load_record({})


func load_record(record: Dictionary) -> void:
	var record_id: String = String(record.get("id", ""))
	if record_id != _record_id:
		_expanded.clear()
		_active_origin = ""
		_search.clear()
	_record_id = record_id
	_features = collect_features(record)
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	for feature: Dictionary in _features:
		var sid: String = "feature:" + String(feature.get("key", ""))
		feature["inactive"] = bool(feature.get("inactive", false)) or not bool(enabled.get(sid, true))
	var previous_origin: String = _active_origin
	_origin_choice.clear()
	_origin_choice.add_item("Tutte le origini")
	_origin_choice.set_item_metadata(0, "")
	var origins: Dictionary = {}
	for feature: Dictionary in _features:
		origins[String(feature["origin_key"])] = String(feature["origin"])
	var labels: Array = origins.keys()
	labels.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String(origins[a]).naturalnocasecmp_to(String(origins[b])) < 0
	)
	for key: Variant in labels:
		_origin_choice.add_item(String(origins[key]))
		_origin_choice.set_item_metadata(_origin_choice.item_count - 1, String(key))
	_active_origin = ""
	for i: int in range(_origin_choice.item_count):
		if String(_origin_choice.get_item_metadata(i)) == previous_origin:
			_origin_choice.select(i)
			_active_origin = previous_origin
			break
	if _active_origin.is_empty():
		_origin_choice.select(0)
	_rebuild()


func _on_origin_selected(index: int) -> void:
	_active_origin = String(_origin_choice.get_item_metadata(index))
	_rebuild()


func _set_all_expanded(opened: bool) -> void:
	for feature: Dictionary in _features:
		_expanded[String(feature["key"])] = opened
	_rebuild()


func _visible_features() -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var query: String = _search.text.strip_edges().to_lower()
	for feature: Dictionary in _features:
		if not _active_origin.is_empty() and String(feature["origin_key"]) != _active_origin:
			continue
		if not query.is_empty() and query not in (
			String(feature["name"]) + " " + String(feature["origin"])
		).to_lower():
			continue
		matches.append(feature)
	return matches


func _rebuild() -> void:
	for child: Node in _cards_container.get_children():
		_cards_container.remove_child(child)
		child.queue_free()
	_cards.clear()
	var visible: Array[Dictionary] = _visible_features()
	_counter.text = "%d tratti e descrizioni" % visible.size()
	if visible.is_empty():
		var hint := Label.new()
		hint.text = "Nessun privilegio da mostrare."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards_container.add_child(hint)
		return

	var last_group := ""
	var last_level := -1
	for feature: Dictionary in visible:
		var group: String = String(feature.get("category", "altro"))
		var level: int = int(feature["level"])
		if group != last_group:
			var section := PanelContainer.new()
			var band := StyleBoxFlat.new()
			band.bg_color = Color(0.16, 0.22, 0.26, 0.96)
			band.set_content_margin_all(10)
			band.set_corner_radius_all(5)
			section.add_theme_stylebox_override("panel", band)
			var category_heading := Label.new()
			category_heading.text = {"razza": "RAZZA E SOTTORAZZA", "background": "BACKGROUND",
				"classi": "CLASSI E SOTTOCLASSI", "talenti": "TALENTI",
				"oggetti": "OGGETTI E DOCUMENTI", "mostro": "TRATTI DEL MOSTRO"}.get(group, "ALTRI TRATTI")
			category_heading.add_theme_font_size_override("font_size", 17)
			category_heading.add_theme_color_override("font_color", Color(0.82, 0.90, 0.94))
			section.add_child(category_heading)
			_cards_container.add_child(section)
			last_group = group
			last_level = -1
		if group == "classi" and level != last_level:
			var level_label := Label.new()
			level_label.text = "LIVELLO %d" % level
			level_label.add_theme_font_size_override("font_size", 13)
			level_label.add_theme_color_override("font_color", Color(0.87, 0.71, 0.49))
			_cards_container.add_child(level_label)
			last_level = level

		var key: String = String(feature["key"])
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.17, 0.14, 0.14, 0.94)
		background.border_color = Color(0.42, 0.32, 0.26, 0.82)
		background.set_border_width_all(1)
		background.set_corner_radius_all(6)
		background.set_content_margin_all(9)
		if bool(feature.get("inactive", false)):
			background.border_color = Color(0.45, 0.40, 0.40, 0.45)
			card.modulate.a = 0.64
		card.add_theme_stylebox_override("panel", background)
		_cards_container.add_child(card)
		_cards[key] = card
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 5)
		card.add_child(body)
		var opened: bool = bool(_expanded.get(key, false))
		var heading := Button.new()
		heading.text = ("%s  %s" % ["▾" if opened else "▸", String(feature["name"])])
		heading.tooltip_text = "Mostra o nascondi la descrizione di questo tratto"
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.clip_text = true
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.pressed.connect(_toggle.bind(key))
		body.add_child(heading)
		var source := Label.new()
		source.text = String(feature["origin"]) + (
			" · " + String(feature["book"]) if not String(feature["book"]).is_empty() else ""
		)
		source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		source.add_theme_font_size_override("font_size", 12)
		source.add_theme_color_override("font_color", Color(0.73, 0.66, 0.57))
		body.add_child(source)
		if opened:
			var details := RichTextLabel.new()
			TraitText.style(details)
			details.fit_content = true
			details.scroll_active = false
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var raw: Variant = feature.get("entries", "")
			var description: String = TraitText.blocks(raw).strip_edges()
			details.text = description if not description.is_empty() else TraitText.meta(
				"Descrizione non disponibile nel catalogo."
			)
			body.add_child(details)


func _toggle(key: String) -> void:
	var previous_scroll: int = _scroll.scroll_vertical
	_expanded[key] = not bool(_expanded.get(key, false))
	_rebuild()
	_scroll.scroll_vertical = previous_scroll
	call_deferred("_restore_scroll", previous_scroll)


func _restore_scroll(position: int) -> void:
	if _scroll != null:
		_scroll.scroll_vertical = position


func _ensure_visible(key: String) -> void:
	if _scroll != null and _cards.has(key) and is_instance_valid(_cards[key]):
		_scroll.ensure_control_visible(_cards[key] as Control)


func focus_feature(name: String, source_label: String = "") -> void:
	var target: Dictionary = {}
	var wanted_class: String = source_label.get_slice(" · ", 0).strip_edges()
	var wanted_book: String = source_label.get_slice(" · ", 1).strip_edges()
	for feature: Dictionary in _features:
		if String(feature["name"]).nocasecmp_to(name) != 0:
			continue
		if not wanted_class.is_empty() and (
			String(feature.get("class_name", "")).nocasecmp_to(wanted_class) != 0
			or (not wanted_book.is_empty() and String(feature["class_source"]).nocasecmp_to(wanted_book) != 0)
		):
			continue
		target = feature
		break
	if target.is_empty():
		for feature: Dictionary in _features:
			if String(feature["name"]).nocasecmp_to(name) == 0:
				target = feature
				break
	if target.is_empty():
		# Group trackers (e.g. Legendary Actions) point to a bestiary
		# section rather than to a specific action inside that section.
		for feature: Dictionary in _features:
			if String(feature["origin"]).to_lower().ends_with(name.to_lower()):
				target = feature
				break
	if target.is_empty():
		return
	_active_origin = String(target["origin_key"])
	for i: int in range(_origin_choice.item_count):
		if String(_origin_choice.get_item_metadata(i)) == _active_origin:
			_origin_choice.select(i)
			break
	_search.clear()
	_expanded[String(target["key"])] = true
	_rebuild()
	call_deferred("_ensure_visible", String(target["key"]))


# Formula/proficiency evaluation requests the same traits many times per edit.
# Compare complete snapshots so every field (including nested homebrew data)
# invalidates safely. Keep a small bound rather than retaining whole archives.
static var _feature_cache: Array[Dictionary] = []
static var _feature_revision := -1


static func collect_features(record: Dictionary) -> Array[Dictionary]:
	var revision: int = ContentCatalog.revision()
	if revision != _feature_revision:
		_feature_cache.clear()
		_feature_revision = revision
	for cached: Dictionary in _feature_cache:
		if cached["record"] == record:
			return (cached["features"] as Array[Dictionary]).duplicate(true)
	var features: Array[Dictionary] = _collect_features(record)
	if _feature_cache.size() >= 8:
		_feature_cache.pop_front()
	_feature_cache.append({"record": record.duplicate(true), "features": features.duplicate(true)})
	return features


static func _collect_features(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if record.is_empty():
		return result
	var kind: String = String(record.get("kind", ""))
	if kind == "monster":
		_collect_monster(record, result)
	else:
		_collect_species(record, result)

	# A selected background contributes readable traits too (not just
	# structured proficiencies). Preserve each named feature as a separate card.
	var background_name: String = String(record.get("background", "")).strip_edges()
	var background_book: String = String(record.get("background_source", ""))
	var background_id: String = String(record.get("background_id", ""))
	if not background_name.is_empty():
		for candidate: Dictionary in PlayerCatalog.entries("backgrounds"):
			if not background_id.is_empty() and String(candidate.get("id", "")) == background_id:
				pass
			elif (String(candidate.get("name", "")).nocasecmp_to(background_name) != 0
				or (not background_book.is_empty() and String(candidate.get("source", "")) != background_book)):
				continue
			var background: Dictionary = PlayerCatalog.detailed_entry("backgrounds", candidate)
			var origin: String = "Background · " + background_name
			var origin_key: String = "background|" + String(background.get("source", "")).to_lower() + "|" + background_name.to_lower()
			var raw_entries: Variant = background.get("entries", background.get("description", []))
			_append(result, {"id": "overview", "name": "Descrizione · " + background_name,
				"source": String(background.get("source", "")),
				"entries": PlayerCatalog.description_text("backgrounds", background),
				"feats": background.get("feats", [])},
				1, origin, origin_key, "", "", 0)
			var found_named := false
			if raw_entries is Array:
				for section: Variant in raw_entries:
					if not section is Dictionary:
						continue
					var section_data: Dictionary = section
					if String(section_data.get("name", "")).strip_edges().is_empty():
						continue
					if not section_data.has("entries") and not section_data.has("entry"):
						continue
					var feature: Dictionary = section_data.duplicate(true)
					feature["entries"] = section_data.get("entries", section_data.get("entry", ""))
					feature["source"] = String(background.get("source", ""))
					_append(result, feature, 1, origin, origin_key, "", "", 2)
					found_named = true
			if not found_named:
				_append(result, {
					"name": "Tratti del background · " + background_name,
					"source": String(background.get("source", "")),
					"entries": raw_entries
				}, 1, origin, origin_key, "", "", 2)
			break

	# Explicitly selected feats are traits in their own right. Their full
	# descriptions are loaded on demand; no mechanics are inferred from prose.
	var raw_feats: Variant = record.get("feats_catalog", [])
	if raw_feats is Array:
		var all_feats: Array[Dictionary] = PlayerCatalog.entries("feats")
		var seen_feats: Dictionary = {}
		for raw_feat: Variant in raw_feats:
			if not raw_feat is Dictionary:
				continue
			var owned: Dictionary = raw_feat
			var source_id: String = Proficiencies.feat_source_id(owned)
			if seen_feats.has(source_id):
				continue
			seen_feats[source_id] = true
			var feat_name: String = String(owned.get("name", ""))
			if feat_name.is_empty():
				continue
			var feat_source: String = String(owned.get("source", ""))
			var feat_entry: Dictionary = PlayerCatalog.detailed_entry("feats", owned)
			for candidate: Dictionary in all_feats:
				if String(candidate.get("name", "")) == feat_name and String(candidate.get("source", "")) == feat_source:
					feat_entry = PlayerCatalog.detailed_entry("feats", candidate)
					break
			var feat_id: String = String(owned.get("id", ""))
			if feat_id.is_empty():
				feat_id = feat_name.to_lower() + "|" + feat_source.to_lower()
			_append(result, {
				"id": feat_id, "name": feat_name, "source": feat_source,
				"feats": feat_entry.get("feats", []),
				"entries": PlayerCatalog.info_text(feat_entry, PlayerCatalog.description_text("feats", feat_entry))
			}, 1, "Talento · " + feat_name, "feat|" + feat_id, "", "", 3)

	# Inventory entries remain visible as traits while owned. Equipment
	# controls only their effective origins, not whether the item exists.
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		var owned_groups: Dictionary = {}
		for raw_owned: Variant in inventory:
			if not raw_owned is Dictionary:
				continue
			var owned: Dictionary = raw_owned
			if int(owned.get("quantity", 1)) <= 0:
				continue
			var item_id: String = String(owned.get("id", ""))
			if item_id.is_empty():
				continue
			if not owned_groups.has(item_id):
				owned_groups[item_id] = {"owned": owned, "active": false, "quantity": 0}
			var group: Dictionary = owned_groups[item_id]
			group["active"] = bool(group.get("active", false)) or Items.origin_active(owned)
			group["quantity"] = int(group.get("quantity", 0)) + int(owned.get("quantity", 1))
		for item_id: String in owned_groups.keys():
			var group: Dictionary = owned_groups[item_id]
			var owned: Dictionary = group["owned"]
			var definition: Dictionary = Items.entry_for(owned)
			var detailed: Dictionary = PlayerCatalog.detailed_entry("items", definition)
			var inactive: bool = not bool(group.get("active", false))
			var description: String = PlayerCatalog.description_text("items", detailed)
			if description.is_empty():
				description = String(owned.get("description", definition.get("description", "")))
			var item_label: String = String(owned.get("name", definition.get("name", item_id)))
			var count: int = int(group.get("quantity", 1))
			_append(result, {"id": "overview", "name": "Descrizione · " + item_label + (" ×%d" % count if count > 1 else ""),
				"source": String(definition.get("source", "")), "entries": description,
				"inactive": inactive, "feats": definition.get("feats", [])},
				0, "Oggetto · " + item_label, "item:" + item_id, "", "", 4)

	# User-defined origins also have a visible trait, rather than existing
	# only as provenance labels in the bonus/proficiency editors.
	var manual: Variant = record.get("proficiency_origins", [])
	if manual is Array:
		for raw_origin: Variant in manual:
			if not raw_origin is Dictionary:
				continue
			var origin: Dictionary = raw_origin
			if String(origin.get("group", "")) != "custom":
				continue
			var sid: String = String(origin.get("id", ""))
			if sid.is_empty():
				continue
			var origin_name: String = String(origin.get("name", sid))
			_append(result, {"id": "overview",
				"name": "Origine · " + origin_name,
				"entries": origin.get("description", "Origine personalizzata."),
				"inactive": bool(origin.get("disabled", false))},
				0, origin_name, sid, "", "", 5)

	var raw_classes: Variant = record.get("classes", [])
	var classes: Array = raw_classes as Array if raw_classes is Array else []
	if classes.is_empty() and not String(record.get("class", "")).is_empty():
		classes = [{
			"name": record.get("class", ""),
			"source": record.get("class_source", ""),
			"level": record.get("level", 1),
			"subclass": record.get("subclass", ""),
			"subclass_source": record.get("subclass_source", "")
		}]
	var class_features: Array[Dictionary] = PlayerCatalog.entries("class_features")
	var subclass_features: Array[Dictionary] = PlayerCatalog.entries("subclass_features")
	for raw: Variant in classes:
		if not raw is Dictionary:
			continue
		var definition: Dictionary = raw as Dictionary
		var class_label: String = String(definition.get("name", ""))
		if class_label.is_empty() or class_label.to_lower() == "mostro":
			continue
		var class_book: String = String(definition.get("source", record.get("class_source", "")))
		var class_level: int = clampi(int(definition.get("level", 1)), 1, 20)
		var class_origin: String = "Classe · " + class_label
		var class_key: String = "class|" + class_book.to_lower() + "|" + class_label.to_lower()
		for class_entry: Dictionary in PlayerCatalog.entries("classes"):
			if String(class_entry.get("name", "")).nocasecmp_to(class_label) != 0 or String(class_entry.get("source", "")) != class_book:
				continue
			var overview: Dictionary = PlayerCatalog.detailed_entry("classes", class_entry)
			_append(result, {"id": "overview", "name": "Descrizione · " + class_label,
				"source": class_book, "entries": PlayerCatalog.description_text("classes", overview),
				"feats": class_entry.get("feats", [])},
				1, class_origin, class_key, class_label, class_book, 0)
			break
		# Level-one synthetic feature: a structured 5etools class overview.
		# The source ID used by the proficiency editor remains the same.
		for source: Dictionary in Proficiencies.candidate_sources(record):
			if String(source.get("group", "")) != "class":
				continue
			var indexed: Dictionary = source.get("data", {})
			if String(indexed.get("name", "")).nocasecmp_to(class_label) != 0 or String(indexed.get("source", "")) != class_book:
				continue
			_append(result, {
				"name": ("Multiclass " if String(source.get("mode", "starting")) == "multiclass" else "Starting ") + class_label,
				"source": class_book,
				"entries": Proficiencies.starting_description(source)
			}, 1, class_origin, class_key, class_label, class_book, 0)
			break
		for feature: Dictionary in class_features:
			if String(feature.get("class_name", "")).nocasecmp_to(class_label) != 0:
				continue
			if not class_book.is_empty() and String(feature.get("class_source", "")) != class_book:
				continue
			var level: int = int(feature.get("level", 0))
			if level < 1 or level > class_level:
				continue
			_append(result, feature, level, class_origin, class_key, class_label, class_book)
		var subclass_name: String = String(definition.get("subclass", ""))
		if subclass_name.is_empty():
			continue
		var subclass_book: String = String(definition.get("subclass_source", ""))
		var subclass_origin: String = "Sottoclasse · %s / %s" % [class_label, subclass_name]
		var subclass_key: String = class_key + "|subclass|" + subclass_name.to_lower() + "|" + subclass_book.to_lower()
		for subclass_entry: Dictionary in PlayerCatalog.entries("subclasses"):
			if String(subclass_entry.get("name", subclass_entry.get("short_name", ""))).nocasecmp_to(subclass_name) != 0:
				continue
			if String(subclass_entry.get("source", "")) != subclass_book:
				continue
			_append(result, {"id": "overview", "name": "Descrizione · " + subclass_name,
				"source": subclass_book, "entries": PlayerCatalog.description_text("subclasses", subclass_entry),
				"feats": subclass_entry.get("feats", [])},
				1, subclass_origin, subclass_key, class_label, class_book, 0)
			break
		for feature: Dictionary in subclass_features:
			if String(feature.get("class_name", feature.get("className", ""))).nocasecmp_to(class_label) != 0:
				continue
			if not class_book.is_empty() and String(feature.get("class_source", "")) != class_book:
				continue
			if (
				String(feature.get("subclass_name", feature.get("subclassName", ""))).nocasecmp_to(subclass_name) != 0
				and String(feature.get("subclass_short_name", "")).nocasecmp_to(subclass_name) != 0
			):
				continue
			if not subclass_book.is_empty() and String(feature.get("subclass_source", "")) != subclass_book:
				continue
			var level: int = int(feature.get("level", 0))
			if level < 1 or level > class_level:
				continue
			_append(result, feature, level, subclass_origin, subclass_key, class_label, class_book)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var categories: Array[String] = ["razza", "background", "classi", "talenti", "oggetti", "mostro", "altro"]
		var group_a: int = categories.find(String(a.get("category", "altro")))
		var group_b: int = categories.find(String(b.get("category", "altro")))
		if group_a != group_b:
			return group_a < group_b
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		var by_origin: int = String(a["origin"]).naturalnocasecmp_to(String(b["origin"]))
		if by_origin != 0:
			return by_origin < 0
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	return result


static func _append(
	output: Array[Dictionary], feature: Dictionary, level: int, origin: String,
	origin_key: String, class_label: String = "", class_book: String = "",
	rank: int = 2
) -> void:
	var name: String = String(feature.get("name", "")).strip_edges()
	if name.is_empty():
		return
	var key: String = String(feature.get("id", ""))
	if key.is_empty():
		key = "%s|%d|%s" % [origin_key, level, name.to_lower()]
	# Disambiguate a feature appearing in two independently selected sources.
	key = origin_key + "|" + key
	var description: Variant = feature.get("entries", feature.get("description", ""))
	if description is String and String(description).strip_edges().is_empty():
		description = ContentCatalog.description(feature)
	var category: String = "altro"
	if origin_key.begins_with("species|") or origin_key.begins_with("race|") or origin_key.begins_with("subrace|"):
		category = "razza"
	elif origin_key.begins_with("background|"):
		category = "background"
	elif origin_key.begins_with("class|"):
		category = "classi"
	elif origin_key.begins_with("feat|"):
		category = "talenti"
	elif origin_key.begins_with("item:"):
		category = "oggetti"
	elif origin_key.begins_with("monster|"):
		category = "mostro"
	output.append({
		"key": key, "name": name, "level": level, "rank": rank, "category": category,
		"inactive": bool(feature.get("inactive", false)),
		"feats": feature.get("feats", []),
		"origin": origin, "origin_key": origin_key,
		"book": String(feature.get("source", "")),
		"class_name": class_label, "class_source": class_book,
		"entries": description, "bonuses": feature.get("bonuses", [])
	})


static func _collect_species(record: Dictionary, output: Array[Dictionary]) -> void:
	var species: String = String(record.get("species", ""))
	var species_book: String = String(record.get("species_source", ""))
	var species_id: String = String(record.get("species_id", ""))
	if species.is_empty():
		return
	var subrace_name := String(record.get("subrace", ""))
	var effective := RaceRules.effective_race(
		{"name": species, "source": species_book},
		{"name": subrace_name, "source": record.get("subrace_source", "")}
		if not subrace_name.is_empty() else {})
	var wanted_name: String = String(effective.get("name", species))
	var wanted_source: String = String(effective.get("source", species_book))
	for race: Dictionary in PlayerCatalog.entries("races"):
		if not (
			(subrace_name.is_empty() and not species_id.is_empty() and String(race.get("id", "")) == species_id)
			or (String(race.get("name", "")).nocasecmp_to(wanted_name) == 0
				and String(race.get("source", "")) == wanted_source)
		):
			continue
		_append(output, {"id": "overview", "name": "Descrizione · " + species,
			"source": wanted_source, "entries": PlayerCatalog.description_text("races", race),
			"feats": race.get("feats", [])},
			1, "Specie · " + species, "species|" + species_id + "|" + species_book, "", "", 0)
		var raw: Variant = race.get("entries", race.get("description", []))
		if raw is Array:
			for index: int in range((raw as Array).size()):
				var entry: Variant = (raw as Array)[index]
				if entry is Dictionary:
					var entry_data: Dictionary = (entry as Dictionary).duplicate(true)
					if String(entry_data.get("name", "")).is_empty():
						entry_data["name"] = "Altri tratti · %d" % (index + 1)
					entry_data["entries"] = (entry as Dictionary).get("entries", entry)
					entry_data["source"] = wanted_source
					_append(output, entry_data, maxi(1, int(entry_data.get("level", 1))),
						"Specie · " + species, "species|" + species_id + "|" + species_book, "", "", 1)
				elif entry is String and not String(entry).strip_edges().is_empty():
					_append(output, {"name": "Tratto · %d" % (index + 1), "entries": entry, "source": species_book},
						1, "Specie · " + species,
						"species|" + species_id + "|" + species_book, "", "", 1)
		else:
			_append(output, {"name": "Tratti della specie", "entries": raw, "source": species_book},
				1, "Specie · " + species, "species|" + species_id + "|" + species_book, "", "", 1)
		break


static func _collect_monster(record: Dictionary, output: Array[Dictionary]) -> void:
	var raw: Variant = record.get("stat_block", {})
	if not raw is Dictionary:
		return
	var stat: Dictionary = raw as Dictionary
	var categories: Array[Dictionary] = [
		{"key": "trait", "label": "Tratti"},
		{"key": "action", "label": "Azioni"},
		{"key": "bonus", "label": "Azioni bonus"},
		{"key": "reaction", "label": "Reazioni"},
		{"key": "legendary", "label": "Azioni leggendarie"},
		{"key": "mythic", "label": "Azioni mitiche"},
		{"key": "lairActions", "label": "Azioni della tana"}
	]
	for category: Dictionary in categories:
		var section: String = String(category["key"])
		var raw_entries: Variant = stat.get(section, [])
		if not raw_entries is Array:
			continue
		for index: int in range((raw_entries as Array).size()):
			var raw_entry: Variant = (raw_entries as Array)[index]
			if raw_entry is Dictionary:
				var item: Dictionary = (raw_entry as Dictionary).duplicate(true)
				if String(item.get("name", "")).is_empty():
					item["name"] = "%s · %d" % [category["label"], index + 1]
				if not item.has("entries"):
					item["entries"] = raw_entry
				item["source"] = String(stat.get("source", ""))
				_append(output, item, 0, "Mostro · " + String(category["label"]),
					"monster|" + section, "", "", 0)
			elif raw_entry is String and not String(raw_entry).strip_edges().is_empty():
				_append(output, {
					"name": "%s · %d" % [category["label"], index + 1],
					"entries": raw_entry, "source": String(stat.get("source", ""))
				}, 0, "Mostro · " + String(category["label"]), "monster|" + section, "", "", 0)
