extends RefCounted
## Per-cast changes; never change the catalogue or charge a cancelled preview.
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const ClassFeatures = preload("res://vtt/class_feature_activation.gd")
const ELEMENTS := ["acid", "cold", "fire", "lightning", "poison", "thunder"]

static func plan(record: Dictionary, spell: Dictionary, slot_level: int, selection: Dictionary) -> Dictionary:
	var names: Array = selection.get("names", [])
	var known: Dictionary = {}
	for option: Dictionary in ClassFeatures.metamagic_options(record): known[option.name] = option
	var seen: Dictionary = {}
	var ordinary := 0
	var cost := 0
	var revised := String(record.get("rules_version", "2014")) == "2024"
	for raw: Variant in names:
		var name := String(raw)
		if not known.has(name) or seen.has(name): return {"ok": false, "message": "Opzione di Metamagia non disponibile o duplicata."}
		seen[name] = true
		if name not in ["Empowered Spell", "Seeking Spell"]: ordinary += 1
		cost += maxi(1, slot_level) if name == "Twinned Spell" and not revised else int(known[name].cost)
	if ordinary > 1: return {"ok": false, "message": "Non puoi combinare queste opzioni di Metamagia."}
	var modified := apply_to_spell(spell, slot_level, selection, revised)
	if not bool(modified.get("ok", false)): return modified
	var tracker := ClassFeatures.tracker_named(record, "Sorcery Points", "Sorcerer")
	if cost > ClassFeatures.remaining(record, tracker): return {"ok": false, "message": "Punti stregoneria insufficienti."}
	modified["cost"] = cost
	modified["tracker"] = tracker
	return modified

static func apply_to_spell(spell: Dictionary, slot_level: int, selection: Dictionary, revised: bool) -> Dictionary:
	var modified := spell.duplicate(true)
	var notes: PackedStringArray = []
	var names: Array = selection.get("names", [])
	if names.size() > 3: return {"ok": false, "message": "Troppe opzioni di Metamagia."}
	for raw: Variant in names:
		var name := String(raw)
		match name:
			"Distant Spell":
				var range_feet := int(modified.get("range_feet", 0))
				if "touch" in String(modified.get("range", "")).to_lower(): range_feet = 30
				elif range_feet >= 5: range_feet *= 2
				else: return {"ok": false, "message": "Incantesimo Distante richiede gittata di almeno 5 ft o contatto."}
				modified["range_feet"] = mini(range_feet, 100000)
				modified["range"] = "%d feet" % int(modified.range_feet)
			"Quickened Spell":
				var timing := String(modified.get("casting_time", modified.get("time", ""))).to_lower()
				if timing not in ["action", "1 action", "1 azione"]: return {"ok": false, "message": "Incantesimo Rapido richiede tempo di lancio di un’azione."}
				modified["casting_time"] = "Bonus Action"
				modified["time"] = "bonus"
			"Subtle Spell":
				var components := String(modified.get("components", ""))
				var material := components.find("M")
				var kept := components.substr(material) if material >= 0 else ""
				if revised and not ("gp" in kept.to_lower() or "consum" in kept.to_lower()): kept = ""
				modified["components"] = kept
				# Costly/consumed material components are never silently removed.
			"Extended Spell":
				var seconds := duration_seconds(modified.get("duration", ""))
				if seconds < 60: return {"ok": false, "message": "Incantesimo Esteso richiede durata di almeno un minuto."}
				modified["requires_concentration"] = ActiveSpells.requires_concentration(spell)
				modified["duration"] = "%d seconds" % mini(86400, seconds * 2)
				modified["metamagic_duration_seconds"] = mini(86400, seconds * 2)
			"Twinned Spell":
				if not bool(selection.get("eligible_targeting", false)):
					return {"ok": false, "message": "Conferma i requisiti di bersaglio di Incantesimo Raddoppiato per questa edizione."}
				if revised:
					if slot_level < 1 or slot_level >= 9: return {"ok": false, "message": "Incantesimo Raddoppiato richiede uno slot di livello inferiore al 9°."}
					modified["metamagic_effective_level"] = slot_level + 1
					modified["target_mode"] = "token_then_multi_token"
					var per_slot := maxi(1, int(modified.get("target_clicks_per_slot_above_base", 1)))
					modified["base_target_clicks"] = int(modified.get("base_target_clicks", 1)) + per_slot
					modified["allow_repeat_targets"] = false
				else:
					if modified.has("aoe_shape") or int(modified.get("range_feet", 0)) <= 0: return {"ok": false, "message": "Un incantesimo ad area o con gittata Personale non può essere raddoppiato."}
					modified["target_mode"] = "token_then_multi_token"
					modified["base_target_clicks"] = 2
					modified["target_clicks_per_slot_above_base"] = 0
					modified["allow_repeat_targets"] = false
			"Transmuted Spell":
				var element := String(selection.get("damage_type", ""))
				if element not in ELEMENTS: return {"ok": false, "message": "Scegli il tipo di danno elementale."}
				modified["metamagic_damage_type"] = element
				modified["damage_type"] = element
				var original_damage := String(modified.get("level17_damage", ""))
				for original: String in ELEMENTS:
					original_damage = original_damage.replace(original.capitalize(), element.capitalize())
				modified["level17_damage"] = original_damage
			"Careful Spell", "Heightened Spell", "Empowered Spell", "Seeking Spell":
				modified[{"Heightened Spell": "metamagic_save_disadvantage", "Careful Spell": "metamagic_careful", "Empowered Spell": "metamagic_empowered", "Seeking Spell": "metamagic_seeking"}[name]] = true
				# The base VTT spell does not roll target saves/damage; these
				# flags accompany the confirmed cast for the same table resolution.
			_:
				return {"ok": false, "message": "Metamagia sconosciuta."}
		notes.append(name)
	modified["metamagic"] = selection.duplicate(true)
	modified["metamagic_notes"] = ", ".join(notes)
	return {"ok": true, "spell": modified}

static func duration_seconds(raw: Variant) -> int:
	if raw is Array:
		for entry: Variant in raw:
			var seconds := duration_seconds(entry)
			if seconds > 0: return seconds
		return 0
	if raw is Dictionary:
		var duration: Variant = raw.get("duration", raw)
		if duration is Dictionary:
			return int(duration.get("amount", 0)) * int({"round": 6, "minute": 60, "hour": 3600, "day": 86400}.get(String(duration.get("type", "")), 0))
		return 0
	var found := RegEx.create_from_string("(?i)([0-9]+) (round|minute|hour|day|second)").search(String(raw))
	return int(found.get_string(1)) * int({"round": 6, "minute": 60, "hour": 3600, "day": 86400, "second": 1}.get(found.get_string(2).to_lower(), 0)) if found != null else 0
