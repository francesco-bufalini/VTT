extends VBoxContainer
signal skill_requested(key: String)
signal basic_action_requested(action_id: String)
signal tracker_change_requested(tracker_id: String, delta: int, maximum: int)
signal cast_spell_requested(spell_id: String, grant_id: String)
signal open_spellbook_requested()
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Skills5e = preload("res://vtt/creature_skills_5etools.gd")
## Local-only action overview. Neither casting nor sheet calculations require a server.
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Features = preload("res://vtt/creature_features.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const FeatureRules = preload("res://vtt/feature_timing_recovery_rules.gd")
const DialogLayout = preload("res://vtt/dialog_layout.gd")

const ACTION_SUPPLEMENTS_PATH := "res://vtt/data/action_feature_overrides.json"
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
const ACTION_ICONS: Texture2D = preload("res://vtt/icons/action_dashboard.svg")
const ICON_KEYS := ["action", "bonus", "free", "movement", "reaction", "sword", "help", "shove", "prone", "stealth", "eye", "object", "speech", "target", "shield", "book", "spark", "flag", "skill", "hand"]
const GOLD := Color("edbd77")
const INK := Color("f5eee5")
const MUTED := Color("c7bdb1")

const GROUPS := ["Azione", "Azione bonus", "Azione gratuita", "Movimento", "Reazione"]
# SRD 5.1 (2014) and SRD 5.2 (2024): edition-specific names are deliberate.
const BASIC_2014 := [
 ["Attaccare", 0, "Attacco", "Effettua un attacco in mischia o a distanza."],
 ["Lanciare un incantesimo", 0, "Generale", "Il tempo di lancio dell'incantesimo determina l'azione richiesta."],
 ["Scattare", 0, "Generale", "Ottieni movimento aggiuntivo pari alla tua velocità."],
 ["Disimpegnarsi", 0, "Generale", "Il tuo movimento non provoca attacchi di opportunità per il resto del turno."],
 ["Schivare", 0, "Generale", "Gli attacchi contro di te hanno svantaggio e i TS Destrezza vantaggio, se applicabile."],
 ["Aiutare", 0, "Generale", "Seleziona un token bersaglio e applica solo la condizione Aiutato, senza altri effetti automatici."],
 ["Spingere", 0, "Attacco", "2014: sostituisce un attacco. Atletica contrapposta a Atletica/Acrobazia del bersaglio, che sceglie; sposta di 5 ft dopo il successo."],
 ["Buttare prono", 0, "Attacco", "2014: sostituisce un attacco. Atletica contrapposta a Atletica/Acrobazia del bersaglio; al successo applica Prono."],
 ["Nascondersi", 0, "Prova caratteristica", "Effettua una prova di Destrezza (Furtività)."],
 ["Cercare", 0, "Prova caratteristica", "Effettua una prova di Saggezza (Percezione) o Intelligenza (Indagare)."],
 ["Preparare", 0, "Generale", "Definisci una condizione e usa la reazione quando si verifica."],
 ["Usare un oggetto", 0, "Generale", "Utilizza un oggetto che richiede un'azione."]
]
const BASIC_2024 := [
 ["Attaccare", 0, "Attacco", "Effettua un attacco con un'arma o un colpo senz'armi."],
 ["Magia", 0, "Generale", "Lancia un incantesimo o attiva un oggetto o privilegio magico."],
 ["Scattare", 0, "Generale", "Ottieni movimento aggiuntivo pari alla tua velocità."],
 ["Disimpegnarsi", 0, "Generale", "Il tuo movimento non provoca attacchi di opportunità per il resto del turno."],
 ["Schivare", 0, "Generale", "Gli attacchi contro di te hanno svantaggio e i TS Destrezza vantaggio, se applicabile."],
 ["Aiutare", 0, "Generale", "Seleziona un token bersaglio e applica solo la condizione Aiutato, senza altri effetti automatici."],
 ["Spingere", 0, "Attacco", "2024: colpo senz'armi invece di un attacco; il bersaglio sceglie TS Forza o Destrezza contro CD 8 + competenza + mod. Forza. Fallimento: 5 ft."],
 ["Buttare prono", 0, "Attacco", "2024: colpo senz'armi invece di un attacco; il bersaglio sceglie TS Forza o Destrezza contro CD 8 + competenza + mod. Forza. Fallimento: Prono."],
 ["Nascondersi", 0, "Prova caratteristica", "Effettua una prova di Destrezza (Furtività)."],
 ["Cercare", 0, "Prova caratteristica", "Effettua una prova di Saggezza (Intuizione, Medicina, Percezione o Sopravvivenza)."],
 ["Studiare", 0, "Prova caratteristica", "Effettua una prova di Intelligenza (Arcano, Storia, Indagare, Natura o Religione)."],
 ["Influenzare", 0, "Prova caratteristica", "Effettua una prova sociale per influenzare una creatura."],
 ["Preparare", 0, "Generale", "Prepara una risposta da eseguire con la reazione."],
 ["Utilizzare", 0, "Generale", "Usa un oggetto non magico."]
]
const COMMON := [
 ["Interagire con un oggetto", 2, "Generale", "Una semplice interazione durante il movimento o un'azione."],
 ["Parlare brevemente", 2, "Generale", "Pronuncia poche parole quando puoi comunicare."],
 ["Muoversi", 3, "Movimento", "Usa il movimento disponibile, eventualmente suddividendolo fra le azioni."],
 ["Movimento furtivo", 3, "Movimento", "Muoviti cercando di restare nascosto. Per nasconderti effettua una prova di Destrezza (Furtività) usando Nascondersi; nel 2024 è una prova CD 15. Il movimento usa la normale velocità: non concede automaticamente la condizione Nascosto."],
 ["Attacco di opportunità", 4, "Attacco", "Attacco in mischia come reazione quando una creatura lascia la tua portata."]
]

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
		var style := StyleBoxFlat.new()
		style.bg_color = Color("201e1df7")
		style.border_color = Color("c99750")
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 5)
		panel.add_child(section)
		var header := HBoxContainer.new()
		section.add_child(header)
		header.add_theme_constant_override("separation", 12)
		header.add_child(_icon(ICON_KEYS[index], 38))
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
		var rule_hint := Label.new()
		rule_hint.text = [
			"Attacchi, incantesimi e prove di abilità",
			"Capacità che usano un'azione bonus",
			"Interazioni senza costo in azioni",
			"Usa la velocità disponibile",
			"Azioni in risposta a eventi"
		][index]
		rule_hint.add_theme_font_size_override("font_size", 12)
		rule_hint.add_theme_color_override("font_color", MUTED)
		rule_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header_text.add_child(rule_hint)
		_layout_one.add_child(panel)
		_sections.append(section)
		_panels.append(panel)
	_skill_list = VBoxContainer.new()
	_skill_list.name = "ProveAbilita"
	_skill_list.add_theme_constant_override("separation", 5)
	var skill_heading_row := HBoxContainer.new()
	skill_heading_row.add_theme_constant_override("separation", 8)
	_skill_list.add_child(skill_heading_row)
	skill_heading_row.add_child(_icon("skill", 20))
	var skills_heading := Label.new()
	skills_heading.text = "Prove di abilità · 4 migliori"
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
			_layout_one if narrow else _layout_left if i in [0, 3] else _layout_right
		)
		var panel: PanelContainer = _panels[i]
		if panel.get_parent() != parent:
			panel.reparent(parent)
	# Keep the primary action box first and movement directly below it.
	for index: int in range(_panels.size()):
		var panel: PanelContainer = _panels[index]
		var parent: Node = panel.get_parent()
		if narrow:
			parent.move_child(panel, index)
		elif index == 0 or index == 1 or index == 2:
			parent.move_child(panel, 0 if index != 2 else 1)
		elif index == 3:
			parent.move_child(panel, 1)
		else:
			parent.move_child(panel, 2)


static func _timing(value: Variant) -> int:
	if value is Array:
		return _timing(value[0]) if not value.is_empty() else 0
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

static func entries(record: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for row: Array in (BASIC_2024 if String(record.get("rules_version", "2014")) == "2024" else BASIC_2014):
		var entry := _entry(String(row[0]), int(row[1]), String(row[2]), String(row[3]))
		match String(row[0]):
			"Aiutare": entry["action_id"] = "help"
			"Spingere": entry["action_id"] = "shove"
			"Buttare prono": entry["action_id"] = "prone"
		results.append(entry)
	for row: Array in COMMON:
		results.append(_entry(String(row[0]), int(row[1]), String(row[2]), String(row[3])))
	# Curated 5etools supplements are driven by a versioned JSON file. The
	# same file ships with both native builds and the offline/browser client.
	var selected_edition := "2024" if String(record.get("rules_version", "2014")) == "2024" else "2014"
	for supplement: Dictionary in _general_supplements():
		if String(supplement.get("edition", "")) != selected_edition:
			continue
		var description := String(supplement.get("description", ""))
		description += "\nFonte: %s, p. %d" % [String(supplement.get("source", "")), int(supplement.get("page", 0))]
		if bool(supplement.get("optional", false)):
			description += "\nRegola opzionale: richiede l'approvazione del DM."
		for when: Variant in supplement.get("timings", []):
			var rule := _entry(String(supplement.get("name", "")), _timing(when),
				"Regola opzionale" if bool(supplement.get("optional", false)) else "Generale",
				description, String(supplement.get("tracker", "")))
			rule["skill_ids"] = supplement.get("skills", [])
			rule["action_id"] = String(supplement.get("action_id", ""))
			rule["catalog_id"] = String(supplement.get("id", ""))
			rule["optional"] = bool(supplement.get("optional", false))
			results.append(rule)
	if record.is_empty():
		return results
	var personal_start := results.size()
	var tracker_list: Array[Dictionary] = Trackers.for_creature(record)
	var trackers: Dictionary = {}
	for resource: Dictionary in tracker_list:
		trackers[String(resource.get("id", ""))] = resource
	var seen: Dictionary = {}
	# Variant activations never create an extra tracker or spend a use here.
	for option: Dictionary in FeatureRules.action_entries(record, tracker_list):
		var rule := _entry(String(option.get("name", "")), _timing(option.get("activation", "action")),
			"Capacità", String(option.get("detail", "")), String(option.get("tracker", "")), String(option.get("tracker_id", "")))
		rule["rule_id"] = String(option.get("rule_id", ""))
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
		results.append(_entry(title, time, "Attacco", detail))
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
				if name.is_empty():
					continue
				results.append(_entry(name, _timing(section), "Capacità", _description(action.get("entries", action))))
	# Only explicitly structured activations are classified. Passive features
	# remain in Tratti rather than being guessed from descriptive prose.
	var automatic: Dictionary = {}
	var collected: Array[Dictionary] = Features.collect_features(record)
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
			String(feature.get("action_kind", "Capacità")), _description(feature.get("entries", "")),
			_tracker_label(tracker_id, trackers), tracker_id))
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
		results.append(_entry(String(rule.get("display_name", rule.get("feature_name", ""))),
			_timing(rule.get("activation", "action")), "Capacità",
			String(rule.get("description", "")) + "\n" + _description(matched_feature.get("entries", "")),
			_tracker_label(tracker_id, trackers) if not tracker_id.is_empty() else resource_label, tracker_id))
	for grant in record.get("action_grants", []):
		if not grant is Dictionary or bool(grant.get("disabled", false)):
			continue
		var feature_id := String(grant.get("key", ""))
		if not feature_id.is_empty() and automatic.has(feature_id):
			continue
		var tracker_id := String(grant.get("tracker_id", ""))
		results.append(_entry(String(grant.get("name", grant.get("title", "Capacità"))),
			_timing(grant.get("action_type", grant.get("activation", "action"))),
			String(grant.get("type", "Capacità")), _description(grant.get("description", grant.get("entries", ""))),
			_tracker_label(tracker_id, trackers), tracker_id))
	# Regular selections are distinct from origin-granted casts: the same spell
	# may appear twice if it can consume two different resource pools.
	var regular_seen: Dictionary = {}
	var selected: Array = []
	for key: String in ["prepared_spells", "spells"]:
		var raw_selection: Variant = record.get(key, [])
		if raw_selection is Array:
			selected.append_array(raw_selection)
	for raw: Variant in selected:
		var id := ""
		if raw is String:
			id = String(raw)
		elif raw is Dictionary:
			id = String(raw.get("id", ""))
		if id.is_empty() or regular_seen.has(id):
			continue
		regular_seen[id] = true
		var spell: Dictionary = Spells.catalog_spell(id)
		if spell.is_empty() and raw is Dictionary:
			spell = raw
		if spell.is_empty():
			continue
		var time: Variant = spell.get("time", spell.get("casting_time", "action"))
		var level := int(spell.get("level", 0))
		var tracker := "Nessuno" if level == 0 else "Slot incantesimo"
		var detail := "Livello: %d\n" % level + _description(spell.get("entries", spell.get("description", "")))
		var cast_entry := _entry(String(spell.get("name", id)), _timing(time), "Incantesimo", detail, tracker)
		cast_entry["spell_id"] = id
		results.append(cast_entry)
	for grant: Dictionary in OriginSpells.all_grants(record):
		if bool(grant.get("disabled", false)):
			continue
		var spell: Dictionary = Spells.catalog_spell(String(grant.get("spell_id", "")))
		if spell.is_empty():
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
		grant_entry["spell_id"] = String(grant.get("spell_id", ""))
		grant_entry["grant_id"] = String(grant.get("id", ""))
		results.append(grant_entry)
	for index: int in range(results.size()):
		results[index]["origin"] = "personal" if index >= personal_start else "general"
		results[index]["position"] = index
	return results

func _surface(background: Color, border: Color, radius: int = 7, padding: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style

func _action_style() -> StyleBoxFlat:
	return _surface(Color("2c2726f7"), Color("89643f"))

func _icon_texture(key: String) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ACTION_ICONS
	texture.region = Rect2(maxi(0, ICON_KEYS.find(key)) * 64, 0, 64, 64)
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
	var title := String(entry.get("name", "")).to_lower()
	if "incantesim" in title or title == "magia": return "spark"
	if "furtiv" in title or "nascond" in title: return "stealth"
	if "opportunit" in title: return "sword"
	if "attacc" in title or "disarm" in title: return "sword"
	if "aiutar" in title: return "help"
	if "spinger" in title: return "shove"
	if "prono" in title: return "prone"
	if "oggetto" in title or "utilizz" in title or "scudo" in title: return "object"
	if "parlare" in title or "influenz" in title: return "speech"
	if "concentrazione" in title: return "target"
	if "schivar" in title or "disimpegn" in title: return "shield"
	if "cercar" in title: return "eye"
	if "studiar" in title: return "book"
	if "marcare" in title or "preparar" in title: return "flag"
	if "muov" in title or "scatt" in title or int(entry.get("time", 0)) == 3: return "movement"
	return {"Attacco": "sword", "Incantesimo": "spark", "Capacità": "bonus"}.get(String(entry.get("kind", "")), "action")

func _action_button(text: String, help: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = help
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size.y = 30
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("fff1cf"))
	button.add_theme_color_override("font_pressed_color", Color("fff1cf"))
	button.add_theme_stylebox_override("normal", _surface(Color("392d2c"), Color("987047"), 6, 5))
	button.add_theme_stylebox_override("hover", _surface(Color("503835"), GOLD, 6, 5))
	button.add_theme_stylebox_override("pressed", _surface(Color("612d38"), GOLD, 6, 5))
	button.add_theme_stylebox_override("focus", _surface(Color(0, 0, 0, 0), GOLD, 6, 5))
	return button

func _show_entry(entry: Dictionary) -> void:
	var action_id := String(entry.get("action_id", ""))
	if not action_id.is_empty():
		basic_action_requested.emit(action_id)
		return
	if String(entry.get("name", "")) == "Lanciare un incantesimo":
		open_spellbook_requested.emit()
		return
	var dialog := AcceptDialog.new()
	dialog.title = String(entry.get("name", "Capacità"))
	var description := RichTextLabel.new()
	description.text = String(entry.get("detail", "Nessuna descrizione disponibile."))
	description.selection_enabled = true
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(description)
	add_child(dialog)
	DialogLayout.popup(dialog, Vector2i(720, 360), 0.85)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)

func _add_entry(entry: Dictionary) -> void:
	var title := String(entry.get("name", ""))
	var detail := String(entry.get("detail", ""))
	var section: VBoxContainer = _sections[clampi(int(entry.get("time", 0)), 0, GROUPS.size() - 1)]
	var card := PanelContainer.new()
	card.set_meta("action_generated", true)
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
	heading.pressed.connect(_show_entry.bind(entry))
	info.add_child(heading)
	if not detail.is_empty():
		var brief := Label.new()
		brief.text = detail.get_slice("\n", 0).strip_edges()
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
	if not spell_id.is_empty():
		var cast := _action_button("Lancia · slot" if tracker_name == "Slot incantesimo" else "Lancia",
			"Apri il lancio dell'incantesimo con scelta dello slot o consumo dalla sua origine")
		cast.pressed.connect(func() -> void: cast_spell_requested.emit(spell_id, grant_id))
		controls.add_child(cast)
	elif title == "Lanciare un incantesimo" or title == "Magia":
		var open := _action_button("Incantesimi", "Apri la scheda Poteri per scegliere cosa lanciare")
		open.pressed.connect(func() -> void: open_spellbook_requested.emit())
		controls.add_child(open)
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
		tag.tooltip_text = tracker_name
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(0.94, 0.72, 0.45))
		controls.add_child(tag)
	var details := _action_button("›", "Mostra dettagli · " + title)
	details.name = "ActionDetails"
	details.add_theme_font_size_override("font_size", 22)
	details.add_theme_color_override("font_color", GOLD)
	details.custom_minimum_size = Vector2(30, 32)
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.pressed.connect(_show_entry.bind(entry))
	row.add_child(details)
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
			var check := _action_button("↳ Tira " + label)
			check.pressed.connect(func() -> void: skill_requested.emit("skill:" + skill_id))
			checks_row.add_child(check)

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
		var icon_key := "stealth" if key == "stealth" else "hand" if key == "sleight of hand" else "eye" if key in ["insight", "perception", "investigation"] else "skill"
		row.add_child(_icon(icon_key, 26))
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
	band_style.bg_color = Color(0, 0, 0, 0)
	band_style.border_color = Color("735336")
	band_style.border_width_bottom = 1
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
	_record = record.duplicate(true)
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
	for entry: Dictionary in entries(record):
		grouped[clampi(int(entry.get("time", 0)), 0, 4)].append(entry)
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
		# Keep the skills inside Azione, after the common actions, before
		# attacks/spells and features granted specifically to this creature.
		if i == 0 and _skill_list != null:
			section.move_child(_skill_list, section.get_child_count() - 1)
		if not personal.is_empty():
			_add_subheading(section, "Dalla scheda")
		for item: Dictionary in personal:
			_add_entry(item)
