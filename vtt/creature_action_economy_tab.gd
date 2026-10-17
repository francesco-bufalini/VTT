extends VBoxContainer
signal skill_requested(key: String)
signal basic_action_requested(action_id: String)
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Skills5e = preload("res://vtt/creature_skills_5etools.gd")
## Local-only action overview. Neither casting nor sheet calculations require a server.
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Features = preload("res://vtt/creature_features.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")
const Spells = preload("res://vtt/spells/spell_catalog.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")

const ACTION_SUPPLEMENTS_PATH := "res://vtt/data/action_feature_overrides.json"
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
var _skill_list: VBoxContainer

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
	var skills_heading := Label.new()
	skills_heading.text = "Prova abilità · 4 bonus più alti"
	skills_heading.add_theme_font_size_override("font_size", 17)
	add_child(skills_heading)
	_skill_list = VBoxContainer.new()
	add_child(_skill_list)
	for heading_text: String in GROUPS:
		var section := VBoxContainer.new()
		var heading := Label.new()
		heading.text = heading_text
		heading.add_theme_font_size_override("font_size", 19)
		section.add_child(heading)
		add_child(section)
		_sections.append(section)

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
	if record.is_empty():
		return results
	var trackers: Dictionary = {}
	for resource: Dictionary in Trackers.for_creature(record):
		trackers[String(resource.get("id", ""))] = resource
	var seen: Dictionary = {}
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
		results.append(_entry(String(spell.get("name", id)), _timing(time), "Incantesimo", detail, tracker))
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
		results.append(_entry(String(spell.get("name", grant.get("spell_id", ""))),
			_timing(spell.get("time", spell.get("casting_time", "action"))), kind,
			_description(spell.get("entries", spell.get("description", ""))), tracker, tracker_id if mode == "tracker" else ""))
	return results

func _add_entry(entry: Dictionary) -> void:
	var title := String(entry.get("name", ""))
	var detail := String(entry.get("detail", ""))
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.tooltip_text = detail
	button.set_meta("action_generated", true)
	button.pressed.connect(func() -> void:
		var action_id := String(entry.get("action_id", ""))
		if not action_id.is_empty():
			basic_action_requested.emit(action_id)
			return
		var dialog := AcceptDialog.new()
		dialog.title = title
		dialog.dialog_text = detail if not detail.is_empty() else "Nessuna descrizione disponibile."
		add_child(dialog)
		dialog.popup_centered_ratio(0.75)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.close_requested.connect(dialog.queue_free)
	)
	_sections[clampi(int(entry.get("time", 0)), 0, GROUPS.size() - 1)].add_child(button)

func refresh_top_skills(record: Dictionary) -> void:
	if _skill_list == null:
		return
	for child: Node in _skill_list.get_children():
		_skill_list.remove_child(child)
		child.queue_free()
	for skill: Dictionary in best_skills(record):
		var key := String(skill["id"])
		var button := Button.new()
		button.text = "%s  %+d" % [skill["label"], int(skill["bonus"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: skill_requested.emit("skill:" + key))
		_skill_list.add_child(button)

func load_record(record: Dictionary) -> void:
	if _sections.is_empty():
		return
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
		var group: Array = grouped[i]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var key_a := String(a.get("tracker", "")) + "|" + String(a.get("kind", ""))
			var key_b := String(b.get("tracker", "")) + "|" + String(b.get("kind", ""))
			return key_a.nocasecmp_to(key_b) < 0
		)
		var last_heading := ""
		for entry: Dictionary in group:
			var tracker := String(entry.get("tracker", ""))
			var heading := (tracker if not tracker.is_empty() else "Nessuna risorsa") + " · " + String(entry.get("kind", "Capacità"))
			if heading != last_heading:
				var label := Label.new()
				label.text = heading
				label.set_meta("action_generated", true)
				label.add_theme_font_size_override("font_size", 13)
				label.add_theme_color_override("font_color", Color(0.78, 0.79, 0.69))
				section.add_child(label)
				last_heading = heading
			_add_entry(entry)
