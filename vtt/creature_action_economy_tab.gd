extends VBoxContainer
signal class_feature_requested(id: String)
signal skill_requested(key: String)
signal attack_requested(attack_id: String, damage: bool)
signal basic_action_requested(action_id: String)
signal tracker_change_requested(tracker_id: String, delta: int, maximum: int)
signal cast_spell_requested(spell_id: String, grant_id: String)
signal class_spell_requested(spell_id: String, class_id: String)
signal open_spellbook_requested()
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Skills5e = preload("res://vtt/creature_skills_5etools.gd")
## Local-only action overview. Neither casting nor sheet calculations require a server.
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Features = preload("res://vtt/creature_features.gd")
const ClassSelections = preload("res://vtt/class_spell_selection.gd")
const SpellSelections = preload("res://vtt/creature_spellcasting_tab.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const FeatureRules = preload("res://vtt/feature_timing_recovery_rules.gd")
const SheetStyle = preload("res://vtt/creature_sheet_style.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

const ACTION_SUPPLEMENTS_PATH := "res://vtt/data/action_feature_overrides.json"
const RULES_PATH := "res://vtt/data/combat_actions_5etools.json"
const OPTIONS_PATH := "user://action_overview.cfg"
static var _rules_cache: Dictionary = {}
const GENERAL_ACTIONS_PATH := "res://vtt/data/combat_action_supplements_5etools.json"
static var _general_actions_cache: Array[Dictionary] = []
static var _general_actions_loaded := false

static func _general_supplements() -> Array[Dictionary]:
	if not _general_actions_loaded:
		_general_actions_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GENERAL_ACTIONS_PATH))
		if parsed is Dictionary and int(parsed.get("version", -1)) == 1:
			for raw: Variant in parsed.get("entries", []):
				if raw is Dictionary:
					_general_actions_cache.append(raw)
	return _general_actions_cache
static var _supplement_cache: Array[Dictionary] = []
static var _supplements_loaded := false

static func _feature_supplements() -> Array[Dictionary]:
	if not _supplements_loaded:
		_supplements_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTION_SUPPLEMENTS_PATH))
		if parsed is Dictionary:
			for raw: Variant in parsed.get("entries", []):
				if raw is Dictionary:
					_supplement_cache.append(raw)
	return _supplement_cache

# Original vector pictograms: fixed atlas cells avoid font/emoji differences across devices.
# Both atlases live in pwa/ so Godot and the offline browser render identical glyphs.
# Original 98-icon pack: 64px cells. Keys are in the same order as manifest.json.
const GENERATED_ICON_KEYS = SheetStyle.GENERATED_ICON_KEYS
const GENERATED_ICON_ATLASES = SheetStyle.GENERATED_ICON_ATLASES
const HEADER_ICON_KEYS := ["weapon", "flight", "sleight_of_hand", "dash", "reaction_trigger"]
const CONTROL_ICONS: Texture2D = preload("res://vtt/icons/action_controls.svg")
const CONTROL_ICON_KEYS := ["dice", "settings", "alternate"]
const GOLD := Color("edbd77")
const INK := Color("f5eee5")
const MUTED := Color("c7bdb1")

const GROUPS := ["Azione", "Azione bonus", "Azione gratuita", "Movimento", "Reazione"]
var _sections: Array[VBoxContainer] = []
var _panels: Array[PanelContainer] = []
var _section_counts: Array[Label] = []
var _layout_two: HBoxContainer
var _layout_left: VBoxContainer
var _layout_right: VBoxContainer
var _layout_one: VBoxContainer
var _skill_list: VBoxContainer
var _skill_buttons: GridContainer
var _record: Dictionary = {}
var _enabled_variants: Array = []
var _options_path := OPTIONS_PATH
var _settings_dialog: AcceptDialog
var _expanded_actions: Dictionary = {}
var _tree_toggles: Array[Button] = []
var _expand_all: Button
var _trackers: Dictionary = {}

static func best_skills(record: Dictionary, count: int = 4) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if record.is_empty():
		return results
	for skill: Dictionary in Skills5e.SKILLS:
		var key := String(skill["id"])
		results.append({"id": key, "label": String(skill["label"]),
			"bonus": Bonuses.value(record, "skill:" + key)})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["bonus"]) != int(b["bonus"]):
			return int(a["bonus"]) > int(b["bonus"])
		return String(a["label"]).nocasecmp_to(String(b["label"])) < 0
	)
	return results.slice(0, mini(count, results.size()))

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var settings := ConfigFile.new()
	if settings.load(_options_path) == OK:
		_enabled_variants = settings.get_value("2014", "variants", [])
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var caption := Label.new()
	caption.text = "Azioni e opzioni"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_color_override("font_color", GOLD)
	toolbar.add_child(caption)
	_expand_all = _action_button("Espandi tutto")
	_expand_all.name = "ExpandAll"
	_expand_all.pressed.connect(func() -> void:
		var expand := _has_closed_groups()
		for toggle: Button in _tree_toggles:
			if is_instance_valid(toggle): toggle.button_pressed = expand
		_sync_expand_all())
	toolbar.add_child(_expand_all)
	var options := _action_button("", "Regole varianti 2014")
	options.name = "VariantSettings"
	options.icon = _icon_texture("settings")
	options.expand_icon = true
	options.add_theme_constant_override("icon_max_width", 23)
	options.custom_minimum_size = Vector2(34, 34)
	options.pressed.connect(_open_variant_settings)
	toolbar.add_child(options)
	_layout_two = HBoxContainer.new()
	_layout_two.add_theme_constant_override("separation", 12)
	_layout_two.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_layout_two)
	_layout_left = VBoxContainer.new()
	_layout_right = VBoxContainer.new()
	for column: VBoxContainer in [_layout_left, _layout_right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 10)
		_layout_two.add_child(column)
	_layout_one = VBoxContainer.new()
	_layout_one.add_theme_constant_override("separation", 10)
	add_child(_layout_one)
	for index: int in range(GROUPS.size()):
		var panel := PanelContainer.new()
		panel.name = "Actions_" + GROUPS[index].replace(" ", "_")
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Subtle bevel and bottom shadow; keep one inexpensive flat stylebox.
		var style := _surface(Color("221d1cf7"), Color("c99750"), 11, 11)
		style.border_width_top = 2
		style.shadow_color = Color(0, 0, 0, 0.42)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 3)
		panel.add_theme_stylebox_override("panel", style)
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 5)
		panel.add_child(section)
		var header := HBoxContainer.new()
		section.add_child(header)
		header.add_theme_constant_override("separation", 12)
		header.add_child(_icon(HEADER_ICON_KEYS[index], 38))
		var header_text := VBoxContainer.new()
		header_text.add_theme_constant_override("separation", 2)
		header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(header_text)
		var heading := Label.new()
		heading.text = GROUPS[index]
		heading.add_theme_font_size_override("font_size", 23)
		heading.add_theme_color_override("font_color", GOLD)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_text.add_child(heading)
		var count := Label.new()
		count.text = "0"
		count.tooltip_text = "Azioni disponibili in questa categoria"
		count.add_theme_font_size_override("font_size", 12)
		count.add_theme_color_override("font_color", Color(0.95, 0.78, 0.51))
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.custom_minimum_size = Vector2(28, 24)
		count.add_theme_stylebox_override("normal", _surface(Color("2c2724"), Color("785a39"), 6, 4))
		header.add_child(count)
		_section_counts.append(count)
		_layout_one.add_child(panel)
		_sections.append(section)
		_panels.append(panel)
	_skill_list = VBoxContainer.new()
	_skill_list.name = "ProveAbilita"
	_skill_list.add_theme_constant_override("separation", 5)
	var skill_heading_row := HBoxContainer.new()
	skill_heading_row.add_theme_constant_override("separation", 8)
	_skill_list.add_child(skill_heading_row)
	skill_heading_row.add_child(_icon("proficiency", 20))
	var skills_heading := Label.new()
	skills_heading.text = "Prove di abilità · 4 bonus più alti"
	skills_heading.add_theme_font_size_override("font_size", 15)
	skills_heading.add_theme_color_override("font_color", Color(1.0, 0.78, 0.49))
	skill_heading_row.add_child(skills_heading)
	_skill_buttons = GridContainer.new()
	_skill_buttons.columns = 1
	_skill_buttons.add_theme_constant_override("h_separation", 5)
	_skill_buttons.add_theme_constant_override("v_separation", 5)
	_skill_list.add_child(_skill_buttons)
	_sections[0].add_child(_skill_list)
	resized.connect(_arrange_columns)
	call_deferred("_arrange_columns")

func _set_variant_enabled(id: String, enabled: bool) -> Error:
	var next := _enabled_variants.duplicate()
	if enabled and id not in next: next.append(id)
	if not enabled: next.erase(id)
	var config := ConfigFile.new()
	config.set_value("2014", "variants", next)
	var error := config.save(_options_path)
	if error != OK: return error
	_enabled_variants = next
	load_record(_record)
	return OK

func _open_variant_settings() -> void:
	if is_instance_valid(_settings_dialog):
		_settings_dialog.queue_free()
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = "Regole varianti · 2014"
	_settings_dialog.get_ok_button().text = "Chiudi"
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_settings_dialog.add_child(body)
	var hint := Label.new()
	hint.text = "Le regole varianti di combattimento aggiungono opzioni alla scheda. Le altre servono da promemoria e non hanno effetti automatici. Apri la fonte per leggere il testo completo."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	body.add_child(hint)
	var filter := LineEdit.new()
	filter.placeholder_text = "Cerca per nome, fonte o categoria…"
	body.add_child(filter)
	var status := Label.new()
	status.hide()
	body.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for rule: Dictionary in _catalog().get("variants", []):
		var row := HBoxContainer.new()
		var id := String(rule["id"])
		row.set_meta("variant_id", id)
		row.set_meta("search", (String(rule["name"]) + " " + String(rule["source"]) + " " + String(rule.get("category", ""))).to_lower())
		list.add_child(row)
		var check := CheckButton.new()
		check.text = "%s · %s, p. %d" % [rule["name"], rule["source"], int(rule.get("page", 0))]
		check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.button_pressed = id in _enabled_variants
		check.toggled.connect(func(enabled: bool) -> void:
			var error := _set_variant_enabled(id, enabled)
			if error != OK:
				check.set_pressed_no_signal(id in _enabled_variants)
				status.text = "Impossibile salvare la scelta: " + error_string(error)
				status.show())
		row.add_child(check)
		var source := _action_button("", "Apri la fonte 5etools")
		source.icon = _icon_texture("book")
		source.expand_icon = true
		source.add_theme_constant_override("icon_max_width", 22)
		source.custom_minimum_size = Vector2(34, 34)
		source.pressed.connect(func() -> void: OS.shell_open(String(rule["source_url"])))
		row.add_child(source)
	filter.text_changed.connect(func(query: String) -> void:
		for row: Control in list.get_children():
			row.visible = query.strip_edges().to_lower() in String(row.get_meta("search", "")))
	add_child(_settings_dialog)
	DialogLayout.popup(_settings_dialog, Vector2i(780, 580), 0.92)

func _arrange_columns() -> void:
	if _panels.size() != GROUPS.size() or _layout_one == null:
		return
	# The desktop canvas is 1152 logical pixels wide; its archive content
	# is about 830px after the sidebar and margins, even on a large display.
	var narrow := size.x < 800
	_layout_two.visible = not narrow
	_layout_one.visible = narrow
	for i: int in range(_panels.size()):
		var parent: VBoxContainer = (
			_layout_one if narrow else _layout_left if i == 0 else _layout_right
		)
		var panel: PanelContainer = _panels[i]
		if panel.get_parent() != parent:
			panel.reparent(parent)
	# Only actions occupy the first desktop column.
	for index: int in range(_panels.size()):
		var panel: PanelContainer = _panels[index]
		panel.get_parent().move_child(panel, index if narrow else maxi(0, index - 1))



static func _timing(value: Variant) -> int:
	if value is Array:
		var costs := _activation_costs(value)
		return 1 if 0 in costs and 1 in costs else int(costs[0]) if not costs.is_empty() else 0
	if value is Dictionary:
		for key: String in ["unit", "type", "action_type", "activation_type", "time"]:
			if value.has(key):
				return _timing(value[key])
		return 0
	var s := String(value).to_lower()
	if "reaction" in s or "reazione" in s:
		return 4
	if "bonus" in s:
		return 1
	if "free" in s or "gratuit" in s or "interact" in s:
		return 2
	if "move" in s or "movimento" in s:
		return 3
	return 0

static func _activation_costs(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for part: Variant in value:
			for cost: int in _activation_costs(part):
				if cost not in result: result.append(cost)
	elif value is Dictionary:
		for key: String in ["unit", "type", "action_type", "activation_type", "time"]:
			if value.has(key): return _activation_costs(value[key])
	else:
		result.append(_timing(value))
	return result

static func _explicit_time(value: Variant) -> bool:
	if value == null:
		return false
	if value is String:
		return not String(value).strip_edges().is_empty()
	if value is Array or value is Dictionary:
		return not value.is_empty()
	return true

static func _description(value: Variant) -> String:
	if value is String:
		return String(value)
	if value is Array:
		var fragments: PackedStringArray = []
		for part: Variant in value:
			var fragment := _description(part)
			if not fragment.is_empty():
				fragments.append(fragment)
		return "\n".join(fragments)
	if value is Dictionary:
		for key: String in ["entries", "entry", "text", "description"]:
			if value.has(key):
				return _description(value[key])
	return ""

static func _entry(name: String, time: int, kind: String, detail: String, tracker: String = "", resource_id: String = "") -> Dictionary:
	return {"name": name, "time": time, "kind": kind, "detail": detail,
		"tracker": tracker, "tracker_id": resource_id}

static func _tracker_label(tracker_id: String, trackers: Dictionary) -> String:
	if tracker_id.is_empty():
		return ""
	if trackers.has(tracker_id):
		return String((trackers[tracker_id] as Dictionary).get("name", tracker_id))
	return tracker_id

static func _catalog() -> Dictionary:
	if _rules_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
			_rules_cache = parsed
	return _rules_cache

static func _source_text(text: String) -> String:
	var tags := RegEx.new()
	tags.compile("\\{@[^ {}]+ ([^{}|]+)(?:\\|[^{}]*)?\\}")
	for pass_index: int in range(8):
		var next := tags.sub(text, "$1", true)
		if next == text: break
		text = next
	return text

static func _feature_text(name: String, collected: Array[Dictionary], book: String = "PHB") -> String:
	for feature: Dictionary in collected:
		if not bool(feature.get("inactive", false)) and String(feature.get("name", "")).nocasecmp_to(name) == 0:
			var text := _source_text(_description(feature.get("entries", "")))
			if not text.is_empty():
				return text + "\n\n" + String(feature.get("origin", "")) + " · " + String(feature.get("book", ""))
	# Exact source/feature lookup also works for minimal legacy class records
	# whose subclass source metadata was not persisted by older versions.
	for category: String in ["class_features", "subclass_features"]:
		for feature: Dictionary in PlayerCatalog.entries(category):
			if String(feature.get("name", "")).nocasecmp_to(name) != 0 or String(feature.get("source", feature.get("class_source", ""))) != book: continue
			var detail := PlayerCatalog.detailed_entry(category, feature)
			var text := _source_text(PlayerCatalog.description_text(category, detail))
			if not text.is_empty(): return text + "\n\n" + name + " · " + book
	return ""

static func _base_entries(record: Dictionary, enabled: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var edition := "2024" if String(record.get("rules_version", "2014")) == "2024" else "2014"
	for raw: Dictionary in _catalog().get("actions", []):
		if raw.get("edition") != edition: continue
		var variant := String(raw.get("variant_id", ""))
		if not variant.is_empty() and variant not in enabled and not (variant == "healing_surges_dmg" and "healing_surges_bonus_dmg" in enabled): continue
		var times: Array = raw.get("timings", ["action"]).duplicate()
		if raw.get("id") == "healing_surge" and "healing_surges_bonus_dmg" in enabled:
			times = ["bonus"]
		var dual := "action" in times and "bonus" in times
		for when: Variant in times:
			if dual and when != "bonus": continue
			var row := _entry(String(raw["name"]), _timing(when), "Attacco" if not String(raw.get("parent_action", "")).is_empty() else "Generale", String(raw.get("description", "")))
			row.merge({"id": raw["id"], "catalog_id": raw["id"], "action_id": raw.get("action_id", ""),
				"skill_ids": raw.get("skills", []), "parent_action": raw.get("parent_action", ""), "alternate_action": dual,
				"source_label": "%s, p. %d" % [raw.get("source", ""), int(raw.get("page", 0))],
				"source_url": raw.get("source_url", ""), "optional": not variant.is_empty(), "origin": "general"}, true)
			result.append(row)
	return result

static func _normalize_alternatives(rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for original: Dictionary in rows:
		var row := original.duplicate(true)
		var id := String(row.get("id", ""))
		if id.is_empty():
			result.append(row)
			continue
		# Separate resources/payments are independent choices, not duplicate timings.
		var key := id + ":" + String(row.get("tracker_id", ""))
		if not seen.has(key):
			seen[key] = result.size()
			result.append(row)
			continue
		var index := int(seen[key])
		var previous: Dictionary = result[index]
		var a := int(previous.get("time", 0))
		var b := int(row.get("time", 0))
		if a == b:
			continue
		if a in [0, 1] and b in [0, 1]:
			var preferred: Dictionary = row if b == 1 else previous
			var standard: Dictionary = previous if a == 0 else row
			preferred["alternate_action"] = true
			if standard.get("origin", "personal") == "general":
				preferred["name"] = standard.get("name", preferred["name"])
			preferred["origin"] = standard.get("origin", "personal")
			preferred["source_label"] = standard.get("source_label", preferred.get("source_label", ""))
			preferred["source_url"] = standard.get("source_url", preferred.get("source_url", ""))
			if preferred.get("detail", "") != standard.get("detail", ""):
				preferred["detail"] = String(standard.get("detail", "")) + "\n\n" + String(preferred.get("detail", ""))
			result[index] = preferred
		else:
			# Action vs reaction has different triggers; retain both presentations.
			result.append(row)
	return result

static func attack_action_summary(record: Dictionary) -> Dictionary:
	var count := 1
	var notes: PackedStringArray = []
	for feature: Dictionary in Features.collect_features(record):
		if bool(feature.get("inactive", false)):
			continue
		var title := String(feature.get("name", "")).to_lower()
		var amount: int = {"extra attack": 2, "extra attack (2)": 3, "extra attack (3)": 4,
			"two extra attacks": 3, "three extra attacks": 4, "thirsting blade": 2,
			"devouring blade": 3}.get(title, 0)
		if int(amount) > 0:
			count = maxi(count, int(amount)) # Multiclass Extra Attack never stacks.
			notes.append(String(feature.get("name", "")) + " · " + _source_text(_description(feature.get("entries", ""))))
	for raw: Variant in record.get("stat_block", {}).get("action", []):
		if not raw is Dictionary or String(raw.get("name", "")).to_lower() not in ["multiattack", "multiattacco"]:
			continue
		var text := _source_text(_description(raw.get("entries", "")))
		notes.append("Multiattacco · " + text)
		# Presentation only: complex alternative routines retain their full text.
		var match_count := RegEx.create_from_string("(?i)makes (two|three|four|five|six|[2-9]) (?:melee |ranged |weapon )?attacks").search(text)
		if match_count != null:
			var number := match_count.get_string(1).to_lower()
			count = maxi(count, int({"two": 2, "three": 3, "four": 4, "five": 5, "six": 6}.get(number, number)))
	return {"count": count, "detail": "\n\n".join(notes)}


static func entries(record: Dictionary, enabled_variants: Array = []) -> Array[Dictionary]:
	var results := _base_entries(record, enabled_variants)
	if record.is_empty(): return results
	var personal_start := results.size()
	var collected := Features.collect_features(record)
	var tracker_list: Array[Dictionary] = Trackers.for_creature(record)
	var trackers: Dictionary = {}
	for resource: Dictionary in tracker_list:
		trackers[String(resource.get("id", ""))] = resource
	var seen: Dictionary = {}
	# Variant activations never create an extra tracker or spend a use here.
	for option: Dictionary in FeatureRules.action_entries(record, tracker_list):
		var source_detail := _feature_text(String(option.get("feature", "")), collected, "XPHB" if String(record.get("rules_version", "2014")) == "2024" else "PHB")
		var rule := _entry(String(option.get("name", "")), _timing(option.get("activation", "action")),
			"Capacità", source_detail, String(option.get("tracker", "")), String(option.get("tracker_id", "")))
		rule["rule_id"] = String(option.get("rule_id", ""))
		rule["id"] = String(option.get("action_id", ""))
		# Combat Wild Shape preserves the normal action option from Wild Shape.
		rule["alternate_action"] = rule["id"] == "wild_shape" and rule["time"] == 1 and String(record.get("rules_version", "2014")) == "2014"
		results.append(rule)
	# These are the same equipped attacks / monster attacks as the combat pane.
	for attack: Dictionary in Attacks.definitions(record):
		var id := String(attack.get("id", ""))
		seen[id] = true
		var time := 0
		if id.begins_with("monster:"):
			time = _timing(String(attack.get("source", "action")))
		elif String(attack.get("slot", "")) == "off" and Attacks.offhand_bonus_attack_allowed(record):
			time = 1
		var detail := _description(attack.get("raw", {}))
		if detail.is_empty():
			detail = String(attack.get("damage", ""))
		var range_feet := int(attack.get("range_feet", 5))
		detail += "\nPortata/gittata: %d ft" % range_feet
		var title := String(attack.get("name", "Attacco"))
		var attack_row := _entry(title, time, "Attacco", _source_text(detail))
		attack_row["attack_id"] = id
		attack_row["parent_action"] = "two_weapon" if time == 1 else "attack" if time == 0 else ""
		results.append(attack_row)
	# A monster's actions without attack rolls (breath weapons, special abilities)
	# still belong here; keep their structured stat-block section.
	var stat: Variant = record.get("stat_block", {})
	if stat is Dictionary:
		for section: String in ["action", "bonus", "reaction"]:
			var actions: Variant = stat.get(section, [])
			if not actions is Array:
				continue
			for i: int in range(actions.size()):
				if seen.has("monster:%s:%d" % [section, i]):
					continue
				var action: Variant = actions[i]
				if not action is Dictionary:
					continue
				var name := String(action.get("name", "")).strip_edges()
				if name.is_empty() or name.to_lower() in ["multiattack", "multiattacco"]:
					continue
				results.append(_entry(name, _timing(section), "Capacità", _description(action.get("entries", action))))
	# Only explicitly structured activations are classified. Passive features
	# remain in Tratti rather than being guessed from descriptive prose.
	var automatic: Dictionary = {}
	for feature: Dictionary in collected:
		if bool(feature.get("inactive", false)):
			continue
		var activation: Variant = null
		for key: String in ["action_type", "activation", "time"]:
			if _explicit_time(feature.get(key, null)):
				activation = feature[key]
				break
		if not _explicit_time(activation):
			continue
		var feature_id := String(feature.get("key", ""))
		automatic[feature_id] = true
		var tracker_id := String(feature.get("tracker_id", ""))
		if tracker_id.is_empty():
			for resource_id: String in trackers.keys():
				var resource: Dictionary = trackers[resource_id]
				if String(resource.get("origin_feature_key", "")) == feature_id or String(resource.get("origin_id", "")) == "feature:" + feature_id:
					tracker_id = resource_id
					break
		results.append(_entry(String(feature.get("name", "Capacità")), _timing(activation),
			String(feature.get("action_kind", "Capacità")), _source_text(_description(feature.get("entries", ""))),
			_tracker_label(tracker_id, trackers), tracker_id))
		var costs := _activation_costs(activation)
		results.back()["alternate_action"] = 0 in costs and 1 in costs
	# Small hand-checked structured supplements for class features whose 5etools
	# entries contain descriptions but no typed activation. Exact book/class/
	# feature matches avoid accidentally granting subclass or passive traits.
	for rule: Dictionary in _feature_supplements():
		# Cunning Action is represented by the generic alternative activation
		# rules; avoid another set of identically timed special abilities.
		if String(rule.get("feature_name", "")) == "Cunning Action":
			continue
		var matched_feature: Dictionary = {}
		for feature: Dictionary in collected:
			if bool(feature.get("inactive", false)):
				continue
			if String(feature.get("class_name", "")).nocasecmp_to(String(rule.get("class_name", ""))) != 0:
				continue
			if String(feature.get("class_source", "")).nocasecmp_to(String(rule.get("book", ""))) != 0:
				continue
			if String(feature.get("name", "")).nocasecmp_to(String(rule.get("feature_name", ""))) != 0:
				continue
			if int(feature.get("level", 0)) < int(rule.get("min_level", 1)):
				continue
			matched_feature = feature
			break
		if matched_feature.is_empty():
			continue
		var resource_label := String(rule.get("resource_name", ""))
		var tracker_id := ""
		for resource_id: String in trackers.keys():
			var resource: Dictionary = trackers[resource_id]
			if String(resource.get("name", "")).nocasecmp_to(resource_label) != 0:
				continue
			var owner_class := String(resource.get("origin_class", ""))
			if not owner_class.is_empty() and owner_class.nocasecmp_to(String(rule.get("class_name", ""))) != 0:
				continue
			tracker_id = resource_id
			break
		var supplement_entry := _entry(String(rule.get("display_name", rule.get("feature_name", ""))),
			_timing(rule.get("activation", "action")), "Capacità",
			_source_text(_description(matched_feature.get("entries", ""))),
			_tracker_label(tracker_id, trackers) if not tracker_id.is_empty() else resource_label, tracker_id)
		if String(rule.get("feature_name", "")) == "Wild Shape": supplement_entry["id"] = "wild_shape"
		results.append(supplement_entry)
	for grant in record.get("action_grants", []):
		if not grant is Dictionary or bool(grant.get("disabled", false)):
			continue
		var feature_id := String(grant.get("key", ""))
		if not feature_id.is_empty() and automatic.has(feature_id):
			continue
		var tracker_id := String(grant.get("tracker_id", ""))
		var grant_row := _entry(String(grant.get("name", grant.get("title", "Capacità"))),
			_timing(grant.get("action_type", grant.get("activation", "action"))),
			String(grant.get("type", "Capacità")), _description(grant.get("description", grant.get("entries", ""))),
			_tracker_label(tracker_id, trackers), tracker_id)
		grant_row["id"] = String(grant.get("key", grant.get("id", "")))
		results.append(grant_row)
		var activation: Variant = grant.get("action_type", grant.get("activation", "action"))
		var costs := _activation_costs(activation)
		if 0 in costs and 1 in costs:
			results.back()["time"] = 1
			results.back()["alternate_action"] = true
	for grant: Dictionary in OriginSpells.all_grants(record):
		if bool(grant.get("disabled", false)):
			continue
		var spell: Dictionary = Spells.catalog_spell(String(grant.get("spell_id", "")))
		if spell.is_empty() or not bool(spell.get("internal_grant", false)):
			continue
		var tracker_id := String(grant.get("tracker_id", ""))
		var mode := String(grant.get("payment_mode", "free"))
		var tracker := (_tracker_label(tracker_id, trackers) if mode == "tracker" else
			"Slot incantesimo" if mode == "slot" else "Nessuno")
		# VTT internal effect templates (e.g. Bardic Inspiration / Wild Shape)
		# are abilities, not spells: no spell-school or component semantics.
		var kind := "Capacità" if bool(spell.get("internal_grant", false)) else "Incantesimo"
		var grant_entry := _entry(String(spell.get("name", grant.get("spell_id", ""))),
			_timing(spell.get("time", spell.get("casting_time", "action"))), kind,
			_description(spell.get("entries", spell.get("description", ""))), tracker, tracker_id if mode == "tracker" else "")
		if String(spell.get("name", "")).to_lower() in ["wild shape", "forma selvatica"]:
			grant_entry["id"] = "wild_shape"
			grant_entry["detail"] = _feature_text("Wild Shape", collected)
		grant_entry["spell_id"] = String(grant.get("spell_id", ""))
		grant_entry["grant_id"] = String(grant.get("id", ""))
		results.append(grant_entry)
	for feature: Dictionary in preload("res://vtt/class_feature_activation.gd").entries(record):
		# Replace descriptive supplements by the same actionable class feature.
		for i: int in range(results.size() - 1, -1, -1):
			if String(results[i].get("name", "")) in [String(feature.name), String(feature.feature_name)]:
				results.remove_at(i)
		var feature_row := _entry(String(feature.name), _timing(feature.activation), "Capacità", String(feature.detail))
		feature_row["class_feature_id"] = feature.id
		feature_row["active"] = feature.get("active", false)
		results.append(feature_row)
	var routine := attack_action_summary(record)
	for row: Dictionary in results:
		if row.get("id", "") == "attack":
			row["attack_count"] = routine.count
			if int(routine.count) > 1:
				row["name"] = String(row.name) + " ×%d" % int(routine.count)
			if not String(routine.detail).is_empty():
				row["detail"] = String(row.get("detail", "")) + "\n\n" + String(routine.detail)
	for index: int in range(results.size()):
		results[index]["origin"] = "personal" if index >= personal_start else "general"
		results[index]["position"] = index
	return _normalize_alternatives(results.filter(func(row: Dictionary) -> bool: return String(row.get("kind", "")) != "Incantesimo"))

static func spell_entries(record: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen: Dictionary = {}
	var trackers: Dictionary = {}
	for tracker: Dictionary in Trackers.for_creature(record): trackers[String(tracker.get("id", ""))] = tracker
	var members := ClassSelections.classes(record)
	var selected := SpellSelections._copy_spell_array(record.get("prepared_spells", []))
	selected.append_array(SpellSelections._copy_spell_array(record.get("spells", [])))
	for value: Variant in selected:
		if not value is Dictionary and not value is String: continue
		var raw: Dictionary = value if value is Dictionary else {"id": value}
		var spell_id := SpellSelections._entry_id(raw)
		if spell_id.is_empty(): continue
		var spell := Spells.catalog_spell(spell_id)
		if spell.is_empty(): spell = raw
		spell = spell.duplicate(true)
		spell["id"] = spell_id
		if bool(spell.get("internal_grant", false)): continue
		var owners: Array[Dictionary] = []
		var sources := ClassSelections.sources(raw, record)
		for member: Dictionary in members:
			if member.id in sources: owners.append(member)
		if owners.is_empty() or "manual" in sources: owners.append({"id": "manual", "name": ""})
		for owner: Dictionary in owners:
			var key := spell_id + "|" + String(owner.id)
			if seen.has(key): continue
			seen[key] = true
			for row: Dictionary in _spell_rows(spell):
				row["class_id"] = owner.id
				row["tracker"] = (String(owner.get("name", "")) + " · " if owner.id != "manual" else "") + ("Trucchetto · nessuno slot" if int(spell.get("level", 0)) == 0 else "Slot · liv. %d+" % int(spell.get("level", 1)))
				output.append(row)
	for grant: Dictionary in OriginSpells.all_grants(record):
		if bool(grant.get("disabled", false)): continue
		var spell := Spells.catalog_spell(String(grant.get("spell_id", "")))
		if spell.is_empty() or bool(spell.get("internal_grant", false)): continue
		var mode := String(grant.get("payment_mode", "free"))
		var tracker_id := String(grant.get("tracker_id", "")) if mode == "tracker" else ""
		for row: Dictionary in _spell_rows(spell):
			row["grant_id"] = String(grant.get("id", ""))
			row["tracker_id"] = tracker_id
			row["tracker"] = _tracker_label(tracker_id, trackers) if mode == "tracker" else "Slot · liv. %d+" % int(spell.get("level", 1)) if mode == "slot" else "Senza consumo · " + String(grant.get("origin_name", "Origine"))
			output.append(row)
	return output

static func _spell_rows(spell: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var time: Variant = spell.get("time", spell.get("casting_time", []))
	var times: Array = time if time is Array else [time]
	var seen: Array[int] = []
	for raw: Variant in times:
		var unit := String(raw.get("unit", "") if raw is Dictionary else raw).to_lower().strip_edges().replace("_", " ")
		if raw is Dictionary and int(raw.get("number", 1)) != 1: continue
		if unit.begins_with("1 "): unit = unit.substr(2).strip_edges()
		if unit not in ["action", "bonus", "bonus action", "reaction", "azione", "azione bonus", "reazione"]: continue
		var timing := _timing(unit)
		if timing in seen: continue
		seen.append(timing)
		var row := _entry(String(spell.get("name", "Incantesimo")), timing, "Incantesimo", _description(spell.get("entries", spell.get("description", ""))))
		row["id"] = String(spell.get("id", ""))
		row["spell_id"] = String(spell.get("id", ""))
		row["origin"] = "general"
		rows.append(row)
	return rows


func _surface(background: Color, border: Color, radius: int = 7, padding: int = 8) -> StyleBoxFlat:
	return SheetStyle.surface(background, border, radius, padding)

func _action_style() -> StyleBoxFlat:
	var style := _surface(Color("352928f7"), Color("89643f"), 8, 8)
	style.border_color = Color("9c7048")
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style

func _icon_texture(key: String) -> AtlasTexture:
	var texture := AtlasTexture.new()
	# Preserve VTT's special controls (dice roll and activation variant).
	var control_index := CONTROL_ICON_KEYS.find(key)
	if key in ["dice", "alternate"] and control_index >= 0:
		texture.atlas = CONTROL_ICONS
		texture.region = Rect2(control_index * 64, 0, 64, 64)
		return texture
	var icon_index := GENERATED_ICON_KEYS.find(key)
	if icon_index < 0:
		icon_index = GENERATED_ICON_KEYS.find("weapon")
	texture.atlas = GENERATED_ICON_ATLASES[int(icon_index / 25)]
	texture.region = Rect2((icon_index % 25) * 64, 0, 64, 64)
	return texture

func _icon(key: String, extent: int = 28) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _icon_texture(key)
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _entry_icon(entry: Dictionary) -> String:
	if String(entry.get("id", "")).begins_with("movement_options_"): return "dash"
	if entry.get("id", "") == "ability_checks": return "skill"
	var title := String(entry.get("name", "")).to_lower()
	var kind := String(entry.get("kind", ""))
	var action_id := String(entry.get("action_id", ""))
	if action_id == "grapple" or "afferrar" in title or "grapple" in title: return "grapple"
	if action_id == "prone" or "prono" in title or "atterrar" in title: return "prone_alt"
	if action_id == "shove" or "spinger" in title: return "shove"
	if action_id == "help" or "aiutar" in title: return "help_alt"
	if "forma selvatica" in title or "wild shape" in title: return "wild_shape"
	if "ispirazione bardica" in title or "bardic inspiration" in title: return "bardic_inspiration"
	if title == "ira" or "rage" in title or "furia" in title: return "fire"
	if "nebbios" in title or "teletrasport" in title: return "misty_step"
	if "interrompere concentrazione" in title: return "break_concentration"
	if "concentrazione" in title: return "concentration"
	if "riposo" in title: return "rest_short"
	if "guarig" in title or "curar" in title or "energia" in title: return "healing"
	if "incantesim" in title or title == "magia": return "spell_cast"
	if kind == "Incantesimo": return "spell_cast"
	if "rapidità di mano" in title: return "sleight_of_hand"
	if "furtiv" in title or "nascond" in title: return "stealth_check"
	if "opportunit" in title: return "opportunity_attack"
	if "disarm" in title: return "maneuver"
	if "due armi" in title: return "weapon"
	if "attacc" in title: return "weapon"
	if "pugnale" in title or "spada" in title or "sword" in title or "arco" in title or "bow" in title: return "weapon"
	if "oggetto" in title or "utilizz" in title: return "interact"
	if "scudo" in title: return "armor"
	if "pozion" in title: return "potion"
	if "parlare" in title or "comunicar" in title: return "talk"
	if "influenz" in title: return "persuasion"
	if "schivar" in title: return "dodge"
	if "disimpegn" in title: return "disengage"
	if "cercar" in title or "indagar" in title: return "search"
	if "studiar" in title or "arcano" in title: return "arcana"
	if "marcare" in title: return "mark_enemy"
	if "preparar" in title: return "ready"
	if "scatt" in title or "muov" in title or int(entry.get("time", 0)) == 3: return "dash"
	return {"Attacco": "weapon", "Incantesimo": "spell_cast", "Capacità": "proficiency"}.get(kind, "action")

func _action_button(text: String, help: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = help
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size.y = 30
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("fff1cf"))
	button.add_theme_color_override("font_pressed_color", Color("fff1cf"))
	# Raised bevel, stronger edge on hover, recessed feel on press.
	var normal := _surface(Color("3b302d"), Color("9d754e"), 7, 6)
	normal.border_width_top = 2
	var hover := _surface(Color("574039"), Color("f2c779"), 7, 6)
	hover.border_width_top = 2
	hover.shadow_color = Color("d69f5040")
	hover.shadow_size = 4
	var pressed := _surface(Color("542a33"), Color("e8b76b"), 7, 6)
	pressed.shadow_size = 1
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", _surface(Color(0, 0, 0, 0), GOLD, 7, 6))
	return button

func _show_entry(entry: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = String(entry.get("name", "Capacità"))
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(body)
	var description := RichTextLabel.new()
	description.text = _source_text(String(entry.get("detail", "")))
	if description.text.is_empty(): description.text = "Testo del privilegio non disponibile nel catalogo locale."
	if not String(entry.get("source_label", "")).is_empty():
		description.text += "\n\nFonte: " + String(entry["source_label"])
	description.selection_enabled = true
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(description)
	var source_url := String(entry.get("source_url", ""))
	if not source_url.is_empty():
		var source := LinkButton.new()
		source.text = "Apri il testo originale su 5etools"
		source.pressed.connect(func() -> void: OS.shell_open(source_url))
		body.add_child(source)
	add_child(dialog)
	DialogLayout.popup(dialog, Vector2i(720, 360), 0.85)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)

func _add_entry(entry: Dictionary, target: VBoxContainer = null) -> void:
	var group_only := not (entry.get("children", []) as Array).is_empty() and String(entry.get("detail", "")).is_empty()
	var title := String(entry.get("name", ""))
	var detail := String(entry.get("detail", ""))
	var section: VBoxContainer = target if target != null else _sections[clampi(int(entry.get("time", 0)), 0, GROUPS.size() - 1)]
	var card := PanelContainer.new()
	card.set_meta("action_generated", true)
	card.set_meta("action_entry", entry)
	card.add_theme_stylebox_override("panel", _action_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	row.add_child(_icon(_entry_icon(entry)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var heading := Button.new()
	heading.text = title
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.flat = true
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", INK)
	heading.add_theme_color_override("font_hover_color", GOLD)
	heading.add_theme_color_override("font_pressed_color", GOLD)
	heading.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	heading.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	heading.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	heading.tooltip_text = detail
	if not group_only: heading.pressed.connect(_show_entry.bind(entry))
	info.add_child(heading)
	if not detail.is_empty():
		var brief := Label.new()
		brief.text = _source_text(detail).get_slice("\n", 0).strip_edges()
		if brief.text.length() > 82:
			brief.text = brief.text.substr(0, 79) + "…"
		brief.max_lines_visible = 1
		brief.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.add_theme_font_size_override("font_size", 11)
		brief.add_theme_color_override("font_color", MUTED)
		info.add_child(brief)
	var tracker_name := String(entry.get("tracker", "")).strip_edges()
	var tracker_id := String(entry.get("tracker_id", ""))
	var spell_id := String(entry.get("spell_id", ""))
	var grant_id := String(entry.get("grant_id", ""))
	# Keep spell launchers and resource counters in one stable, right-aligned
	# control column even in the two-column desktop view.
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 3)
	controls.size_flags_horizontal = Control.SIZE_SHRINK_END
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(controls)
	if not String(entry.get("class_feature_id", "")).is_empty():
		var activate := _action_button("Termina" if bool(entry.get("active", false)) else "Usa", "Attiva il privilegio con il consumo della relativa risorsa")
		activate.pressed.connect(func() -> void: class_feature_requested.emit(String(entry.class_feature_id)))
		controls.add_child(activate)
	if not spell_id.is_empty():
		var cast := _action_button("Usa" if String(entry.get("kind", "")) == "Capacità" else "Lancia",
			"Apri il lancio dell'incantesimo con scelta dello slot o consumo dalla sua origine")
		cast.pressed.connect(func() -> void:
			var class_id := String(entry.get("class_id", ""))
			if not class_id.is_empty(): class_spell_requested.emit(spell_id, class_id)
			else: cast_spell_requested.emit(spell_id, grant_id))
		controls.add_child(cast)
	if not tracker_id.is_empty() and _trackers.has(tracker_id):
		var tracker: Dictionary = _trackers[tracker_id]
		var base: int = maxi(0, int(tracker.get("max", 0)))
		var maximum := maxi(0, Bonuses.add(_record, "tracker:" + tracker_id, base))
		var spent: Dictionary = _record.get("resource_tracker_spent", {})
		var used := clampi(int(spent.get(tracker_id, 0)), 0, maximum)
		var tracker_caption := Label.new()
		tracker_caption.text = tracker_name
		tracker_caption.tooltip_text = tracker_name
		tracker_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tracker_caption.custom_minimum_size.x = 110
		tracker_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tracker_caption.add_theme_font_size_override("font_size", 10)
		tracker_caption.add_theme_color_override("font_color", Color(0.95, 0.76, 0.47))
		controls.add_child(tracker_caption)
		var counter := HBoxContainer.new()
		counter.add_theme_constant_override("separation", 3)
		counter.alignment = BoxContainer.ALIGNMENT_END
		controls.add_child(counter)
		var minus := _action_button("−", "Consuma 1 · " + tracker_name)
		minus.disabled = used >= maximum or bool(tracker.get("disabled", false))
		minus.pressed.connect(func() -> void: tracker_change_requested.emit(tracker_id, 1, maximum))
		counter.add_child(minus)
		var remaining := Label.new()
		remaining.text = "%d/%d" % [maximum - used, maximum]
		remaining.tooltip_text = tracker_name
		remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		remaining.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		remaining.custom_minimum_size.x = 47
		counter.add_child(remaining)
		var plus := _action_button("+", "Recupera 1 · " + tracker_name)
		plus.disabled = used <= 0 or bool(tracker.get("disabled", false))
		plus.pressed.connect(func() -> void: tracker_change_requested.emit(tracker_id, -1, maximum))
		counter.add_child(plus)
	elif not tracker_name.is_empty() and tracker_name not in ["Nessuno", "Nessuna risorsa"]:
		var tag := Label.new()
		tag.text = tracker_name
		if String(entry.get("kind", "")) == "Incantesimo": tag.custom_minimum_size.x = 110
		tag.tooltip_text = tracker_name
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(0.94, 0.72, 0.45))
		controls.add_child(tag)
	if bool(entry.get("alternate_action", false)):
		var alternate := _icon("alternate", 24)
		alternate.tooltip_text = "Disponibile anche come azione"
		alternate.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(alternate)
	var details := _action_button("›", "Mostra dettagli · " + title)
	details.name = "ActionDetails"
	details.add_theme_font_size_override("font_size", 22)
	details.add_theme_color_override("font_color", GOLD)
	details.custom_minimum_size = Vector2(30, 32)
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not group_only: details.pressed.connect(_show_entry.bind(entry))
	row.add_child(details)
	var tactical := String(entry.get("action_id", ""))
	if tactical in ["help", "shove", "prone", "grapple"]:
		var apply := _action_button("", "Scegli bersaglio · " + title)
		apply.icon = _icon_texture("target")
		apply.expand_icon = true
		apply.add_theme_constant_override("icon_max_width", 20)
		apply.custom_minimum_size = Vector2(30, 30)
		apply.pressed.connect(func() -> void: basic_action_requested.emit(tactical))
		controls.add_child(apply)
	var attack_id := String(entry.get("attack_id", ""))
	var disarm := String(entry.get("id", "")) == "disarm"
	if disarm:
		var weapon := Attacks.active_attack(_record)
		if String(weapon.get("source", "")) in ["item", "improvised"]:
			attack_id = String(weapon.get("id", ""))
	if not attack_id.is_empty() or disarm:
		var roll := _action_button("", ("Tiro per disarmare" if disarm else "Tira per colpire") + " · " + title)
		roll.disabled = attack_id.is_empty()
		if roll.disabled: roll.tooltip_text = "Equipaggia e seleziona un'arma per questo tiro"
		roll.icon = _icon_texture("dice")
		roll.expand_icon = true
		roll.add_theme_constant_override("icon_max_width", 22)
		roll.custom_minimum_size = Vector2(32, 32)
		roll.pressed.connect(func() -> void: attack_requested.emit(attack_id, false))
		controls.add_child(roll)
	var checks: Array = (entry.get("skill_ids", []) as Array).duplicate()
	if title in ["Nascondersi", "Movimento furtivo"]:
		checks.append("stealth")
	if not checks.is_empty():
		var checks_row := HFlowContainer.new()
		checks_row.add_theme_constant_override("h_separation", 4)
		content.add_child(checks_row)
		var seen_skills: Dictionary = {}
		for raw_skill: Variant in checks:
			var skill_id := String(raw_skill)
			if seen_skills.has(skill_id):
				continue
			seen_skills[skill_id] = true
			var label := skill_id.capitalize()
			for definition: Dictionary in Skills5e.SKILLS:
				if String(definition.get("id", "")) == skill_id:
					label = String(definition.get("label", skill_id))
					break
			var check := _action_button(label, "Tira " + label)
			check.icon = _icon_texture("dice")
			check.expand_icon = true
			check.add_theme_constant_override("icon_max_width", 20)
			check.custom_minimum_size.x = 42 + check.get_theme_font("font").get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			check.pressed.connect(func() -> void: skill_requested.emit("skill:" + skill_id))
			checks_row.add_child(check)

	var children: Array = entry.get("children", [])
	if not children.is_empty():
		var nested := VBoxContainer.new()
		nested.add_theme_constant_override("separation", 5)
		var key := String(entry.get("id", ""))
		var tree_heading := String(entry.get("children_heading", "Attacchi e manovre"))
		var toggle := _action_button("▸ %s · %d" % [tree_heading, children.size()])
		_tree_toggles.append(toggle)
		toggle.toggle_mode = true
		toggle.button_pressed = bool(_expanded_actions.get(key, false))
		nested.visible = toggle.button_pressed
		toggle.toggled.connect(func(open: bool) -> void:
			toggle.text = "%s %s · %d" % ["▾" if open else "▸", tree_heading, children.size()]
			nested.visible = open
			_expanded_actions[key] = open
			_sync_expand_all())
		if group_only:
			heading.pressed.connect(func() -> void: toggle.button_pressed = not toggle.button_pressed)
			details.pressed.connect(func() -> void: toggle.button_pressed = not toggle.button_pressed)
			details.tooltip_text = "Espandi o richiudi · " + title
		content.add_child(toggle)
		content.add_child(nested)
		toggle.text = "%s %s · %d" % ["▾" if toggle.button_pressed else "▸", tree_heading, children.size()]
		for index: int in range(children.size()):
			var branch := HBoxContainer.new()
			branch.name = "ActionTreeBranch"
			branch.add_theme_constant_override("separation", 8)
			nested.add_child(branch)
			var guide := Label.new()
			guide.text = "└─" if index == children.size() - 1 else "├─"
			guide.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			guide.custom_minimum_size.x = 24
			guide.add_theme_color_override("font_color", GOLD)
			branch.add_child(guide)
			var child_slot := VBoxContainer.new()
			child_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			branch.add_child(child_slot)
			_add_entry(children[index], child_slot)
	# The highest skill bonuses are a part of the action Skill Checks card.
	if String(entry.get("id", "")) == "ability_checks" and _skill_list != null:
		_skill_list.reparent(content)


func refresh_top_skills(record: Dictionary) -> void:
	if _skill_buttons == null:
		return
	for child: Node in _skill_buttons.get_children():
		_skill_buttons.remove_child(child)
		child.queue_free()
	for skill: Dictionary in best_skills(record):
		var key := String(skill["id"])
		var button := _action_button("", "Tira " + String(skill["label"]))
		button.custom_minimum_size.y = 38
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: skill_requested.emit("skill:" + key))
		_skill_buttons.add_child(button)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -10
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(row)
		row.add_child(_icon({"stealth": "stealth_check", "sleight of hand": "sleight_of_hand", "insight": "insight", "perception": "perception", "investigation": "investigation", "athletics": "athletics", "acrobatics": "acrobatics", "arcana": "arcana", "animal handling": "animal_handling", "medicine": "medicine", "survival": "survival", "nature": "nature", "persuasion": "persuasion", "deception": "deception", "intimidation": "intimidation", "religion": "religion", "history": "history"}.get(key, "skill"), 26))
		var caption := Label.new()
		caption.text = String(skill["label"])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", INK)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(caption)
		var ability := Label.new()
		for definition: Dictionary in Skills5e.SKILLS:
			if String(definition["id"]) == key:
				ability.text = String({"str": "FOR", "dex": "DES", "con": "COS", "int": "INT", "wis": "SAG", "cha": "CAR"}.get(String(definition["ability"]), ""))
		ability.add_theme_font_size_override("font_size", 12)
		ability.add_theme_color_override("font_color", MUTED)
		ability.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ability)
		var bonus := Label.new()
		bonus.text = "%+d" % int(skill["bonus"])
		bonus.custom_minimum_size.x = 42
		bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bonus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bonus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bonus.add_theme_stylebox_override("normal", _surface(Color("211e1e"), Color("86613f"), 5, 3))
		bonus.add_theme_color_override("font_color", GOLD)
		bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bonus)
		var arrow := Label.new()
		arrow.text = "›"
		arrow.add_theme_font_size_override("font_size", 24)
		arrow.add_theme_color_override("font_color", GOLD)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(arrow)


func _add_subheading(section: VBoxContainer, text: String) -> void:
	var band := PanelContainer.new()
	band.set_meta("action_generated", true)
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color("392a27")
	band_style.border_color = Color("92633f")
	band_style.border_width_top = 1
	band_style.border_width_bottom = 1
	band_style.set_corner_radius_all(5)
	band_style.content_margin_left = 8
	band_style.content_margin_top = 5
	band_style.content_margin_bottom = 5
	band.add_theme_stylebox_override("panel", band_style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.98, 0.79, 0.49))
	band.add_child(label)
	section.add_child(band)

func load_record(record: Dictionary) -> void:
	if _sections.is_empty():
		return
	_tree_toggles.clear()
	_sync_expand_all.call_deferred()
	_record = record.duplicate(true)
	# Detach the persistent quick-roll grid before generated cards are freed.
	if _skill_list != null and _skill_list.get_parent() != _sections[0]:
		_skill_list.reparent(_sections[0])
	_trackers.clear()
	for resource: Dictionary in Trackers.for_creature(record):
		_trackers[String(resource.get("id", ""))] = resource
	refresh_top_skills(record)
	for section: VBoxContainer in _sections:
		for child: Node in section.get_children():
			if child.has_meta("action_generated"):
				section.remove_child(child)
				child.queue_free()
	var grouped: Array = [[], [], [], [], []]
	var projected := entries(record, _enabled_variants)
	var parents: Dictionary = {}
	for entry: Dictionary in projected:
		if entry.get("id", "") in ["attack", "two_weapon"]:
			parents[String(entry["id"])] = entry
	var checks := {"id": "ability_checks", "name": "Prove di abilità", "time": 0,
		"kind": "skill", "detail": "", "origin": "general", "children": [],
		"children_heading": "Prove che richiedono un’azione"}
	var movement_groups: Dictionary = {}
	for timing: int in [0, 1, 3]:
		movement_groups[timing] = {"id": "movement_options_%d" % timing, "name": "Spostamento",
			"time": timing, "kind": "Movimento", "detail": "", "origin": "general",
			"children": [], "children_heading": "Opzioni di movimento"}
	for entry: Dictionary in projected:
		var parent := String(entry.get("parent_action", ""))
		var timing := int(entry.get("time", 0))
		if parent.is_empty() and movement_groups.has(timing) and (timing == 3 or entry.get("id", "") in ["dash", "disengage", "climb_large", "overrun", "tumble", "escape_grapple"]):
			movement_groups[timing]["children"].append(entry)
			continue
		if parent.is_empty() and int(entry.get("time", 0)) == 0 and not (entry.get("skill_ids", []) as Array).is_empty():
			checks["children"].append(entry)
			continue
		if parents.has(parent):
			var children: Array = parents[parent].get("children", [])
			children.append(entry)
			parents[parent]["children"] = children
			continue
		grouped[clampi(int(entry.get("time", 0)), 0, 4)].append(entry)
	for timing: int in movement_groups:
		if not movement_groups[timing]["children"].is_empty():
			grouped[timing].append(movement_groups[timing])
	if not checks["children"].is_empty():
		grouped[0].append(checks)
	var spell_groups: Dictionary = {}
	for spell: Dictionary in spell_entries(record):
		var timing := int(spell["time"])
		if not spell_groups.has(timing):
			spell_groups[timing] = {"id": "spells_%d" % timing, "name": "Incantesimi", "time": timing,
				"kind": "Incantesimo", "detail": "", "origin": "general", "children": [], "children_heading": "Incantesimi disponibili"}
		spell_groups[timing]["children"].append(spell)
	for timing: int in spell_groups: grouped[timing].append(spell_groups[timing])
	for i: int in range(GROUPS.size()):
		var section: VBoxContainer = _sections[i]
		_section_counts[i].text = "%d" % (grouped[i] as Array).size()
		var common: Array[Dictionary] = []
		var personal: Array[Dictionary] = []
		for item: Dictionary in grouped[i]:
			if String(item.get("origin", "general")) == "personal":
				personal.append(item)
			else:
				common.append(item)
		# Normal actions first, DMG optional alternatives last, within each time.
		common.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.get("optional", false)) != bool(b.get("optional", false)):
				return not bool(a.get("optional", false))
			return int(a.get("position", 0)) < int(b.get("position", 0))
		)
		if not personal.is_empty():
			_add_subheading(section, "Generali")
		for item: Dictionary in common:
			_add_entry(item)
		if not personal.is_empty():
			_add_subheading(section, "Dalla scheda")
		for item: Dictionary in personal:
			_add_entry(item)

func _has_closed_groups() -> bool:
	for toggle: Button in _tree_toggles:
		if is_instance_valid(toggle) and not toggle.button_pressed: return true
	return false

func _sync_expand_all() -> void:
	if not is_instance_valid(_expand_all): return
	_expand_all.disabled = _tree_toggles.is_empty()
	_expand_all.text = "Espandi tutto" if _has_closed_groups() else "Comprimi tutto"
