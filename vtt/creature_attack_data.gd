extends RefCounted

# Stable combat attack definitions. The remaining creature reach_feet field
# is only a derived compatibility value for token opportunity/reach overlays.
const Rules = preload("res://vtt/creature_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")


static func definitions(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind: String = String(record.get("kind", "character"))
	var stat: Dictionary = record.get("stat_block", {})
	for section: String in ["action", "bonus", "reaction", "legendary", "mythic"]:
		var raw_section: Variant = stat.get(section, [])
		if not raw_section is Array:
			continue
		for index: int in range((raw_section as Array).size()):
			var raw: Variant = (raw_section as Array)[index]
			if not raw is Dictionary:
				continue
			var action: Dictionary = raw as Dictionary
			var title: String = String(action.get("name", "")).strip_edges()
			if title.is_empty():
				continue
			var text_value: String = JSON.stringify(action.get("entries", []))
			var hit_tag: String = _capture(text_value, "\\{@hit\\s*([+-]?\\d+)\\}")
			if hit_tag.is_empty():
				hit_tag = _capture(text_value, "([+-]\\d+)\\s+to\\s+hit")
			var has_attack: bool = (
				not hit_tag.is_empty()
				or "{@atk " in text_value
				or "weapon attack:" in text_value.to_lower()
				or "spell attack:" in text_value.to_lower()
			)
			if not has_attack:
				continue
			var reach: String = _capture(text_value.to_lower(), "reach\\s*(\\d+)\\s*(?:ft|feet)")
			var ranged_distance_text: String = _capture(text_value.to_lower(), "range\\s*(\\d+)\\s*(?:/|ft|feet)")
			var ranged_long_text: String = _capture(text_value.to_lower(), "range\\s*\\d+\\s*/\\s*(\\d+)")
			var ranged: bool = (
				"ranged" in text_value.to_lower()
				or "{@atk rw}" in text_value
				or "{@atk rs}" in text_value
			)
			var dice: String = _capture(text_value, "\\{@damage\\s*([^}]+)\\}")
			if dice.is_empty():
				dice = _capture(text_value, "(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)*)")
			var distance_feet: int = 5
			if ranged and not ranged_distance_text.is_empty():
				distance_feet = int(ranged_distance_text)
			elif not reach.is_empty():
				distance_feet = int(reach)
			var melee: bool = not ranged or "melee or ranged" in text_value.to_lower()
			result.append({
				"id": "monster:%s:%d" % [section, index],
				"name": title, "source": section, "melee": melee,
				"range_feet": maxi(5, distance_feet),
				"long_range_feet": maxi(0, int(ranged_long_text)) if ranged and not ranged_long_text.is_empty() else 0,
				"melee_reach_feet": maxi(5, int(reach)) if not reach.is_empty() else 5,
				"proficient": true, "damage": dice,
				"base_hit": int(hit_tag) if not hit_tag.is_empty() else 0,
				"hit_known": not hit_tag.is_empty(),
				"source_ability": "dex" if ranged else "str",
				"raw": action.duplicate(true)
			})
	# Carried weapons are not attack options until equipped. The same item can
	# occupy both hands when at least two copies are owned.
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		for slot: String in ["main", "off"]:
			var owned: Dictionary = Items.occupying(inventory, slot)
			if owned.is_empty():
				continue
			var entry: Dictionary = Items.entry_for(owned)
			if Items.kind(entry) != "weapon":
				continue
			var item_id: String = String(owned.get("id", ""))
			var is_ranged := String(entry.get("type", "")).split("|")[0].to_upper() == "R"
			var reach := 10 if Items.has_property(entry, "R") else 5
			var normal_range := Items.item_range(entry)
			var base_id := "item:" + ("off:" if slot == "off" else "") + item_id
			var name := String(entry.get("name", owned.get("name", "Arma")))
			result.append({
				"id": base_id, "name": name + (" · secondaria" if slot == "off" else ""),
				"source": "item", "melee": not is_ranged,
				"range_feet": maxi(5, normal_range) if is_ranged else reach,
				"long_range_feet": Items.item_range(entry, true) if is_ranged else 0,
				"proficient": false, "damage": String(entry.get("damage", "")),
				"item_entry": entry, "slot": slot, "thrown": false,
				"weapon_size": Items.weapon_size(record, owned),
				"base_hit": 0
			})
			if not is_ranged and Items.has_property(entry, "T") and normal_range > 0:
				result.append({
					"id": "item:throw:" + slot + ":" + item_id,
					"name": name + " · lancio" + (" (secondaria)" if slot == "off" else ""),
					"source": "item", "melee": false,
					"range_feet": normal_range,
					"long_range_feet": Items.item_range(entry, true),
					"proficient": false, "damage": String(entry.get("damage", "")),
					"item_entry": entry, "slot": slot, "thrown": true,
					"weapon_size": Items.weapon_size(record, owned),
					"base_hit": 0
				})
	# These are fictional hand weapons, not permanent character attacks:
	# a strike is available only while explicitly selected in either hand.
	var special_hands: Array = [String(record.get("hand_main_special", "none")),
		String(record.get("hand_off_special", "none"))]
	if "unarmed" in special_hands:
		result.append({
			"id": "unarmed", "name": "Colpo senz'armi",
			"source": "unarmed", "melee": true, "range_feet": 5,
			"proficient": true, "damage": "", "base_hit": 0
		})
	if "improvised" in special_hands:
		result.append({
			"id": "improvised", "name": "Arma improvvisata",
			"source": "improvised", "melee": true, "range_feet": 5,
			"proficient": false, "damage": "1d4", "base_hit": 0
		})
	return result


static func _capture(text_value: String, expression: String) -> String:
	var pattern: RegEx = RegEx.create_from_string(expression)
	if pattern == null:
		return ""
	var match_value: RegExMatch = pattern.search(text_value)
	return match_value.get_string(1) if match_value != null else ""


static func override_for(record: Dictionary, attack_id: String) -> Dictionary:
	var source: Variant = record.get("attack_overrides", {})
	if source is Dictionary:
		var entry: Variant = (source as Dictionary).get(attack_id, {})
		if entry is Dictionary:
			return entry as Dictionary
	return {}


static func range_for(record: Dictionary, attack: Dictionary) -> int:
	var settings: Dictionary = override_for(record, String(attack.get("id", "")))
	var base: int = int(settings.get("range_feet", attack.get("range_feet", 5)))
	return clampi(Bonuses.add(record, "attack_range:" + String(attack.get("id", "")), base), 5, 1000)


static func long_range_for(record: Dictionary, attack: Dictionary) -> int:
	# The extended distance is a separate, origin-modifiable formula.
	# A melee attack must never acquire a long range from a stray bonus.
	var original: int = int(attack.get("long_range_feet", 0))
	if bool(attack.get("melee", false)) or original <= 0:
		return 0
	var settings: Dictionary = override_for(record, String(attack.get("id", "")))
	var base: int = int(settings.get("long_range_feet", original))
	return clampi(Bonuses.add(record, "attack_long_range:" + String(attack.get("id", "")), base), 5, 5000)


static func ability_modifier(record: Dictionary) -> int:
	var ability: String = "dex" if String(record.get("attack_ability", "str")) == "dex" else "str"
	return Bonuses.value(record, "ability_mod:" + ability)


static func _ability_delta_for_monster(_record: Dictionary, _attack: Dictionary) -> int:
	# Bestiary attacks have no structured Finesse flag and publish a complete
	# attack/damage modifier: do not reinterpret it using the global preference.
	return 0


static func _attack_ability_modifier(record: Dictionary, attack: Dictionary) -> int:
	var item_value: Variant = attack.get("item_entry", {})
	if item_value is Dictionary and not (item_value as Dictionary).is_empty():
		var ability: String = Items.attack_ability(record, item_value as Dictionary, bool(attack.get("thrown", false)))
		return Bonuses.value(record, "ability_mod:" + ability)
	if String(attack.get("id", "")) in ["unarmed", "improvised"]:
		return Bonuses.value(record, "ability_mod:str")
	return ability_modifier(record)


static func attack_bonus(record: Dictionary, attack: Dictionary, proficiency: int) -> int:
	if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) not in ["item", "unarmed", "improvised"]:
		# Published monster hit modifiers already include proficiency.
		return Bonuses.add(record, "attack_hit:" + String(attack.get("id", "")), int(attack.get("base_hit", 0)) + _ability_delta_for_monster(record, attack))
	var trained: bool = false
	if String(attack.get("id", "")) == "unarmed":
		# All creatures are proficient with unarmed strikes under 5e rules.
		trained = true
	elif String(attack.get("id", "")) == "improvised":
		trained = Proficiencies.has_proficiency(record, "weapon", "improvised")
	elif String(attack.get("source", "")) == "item":
		var item_value: Variant = attack.get("item_entry", {})
		if item_value is Dictionary:
			trained = Proficiencies.weapon_proficient(record, item_value)
	else:
		trained = bool(attack.get("proficient", false))
	return Bonuses.add(record, "attack_hit:" + String(attack.get("id", "")), _attack_ability_modifier(record, attack) + (proficiency if trained else 0))


# The tooltip uses exactly the same components as attack_bonus, including
# published monster totals and the optional weapon enhancement.
static func attack_bonus_formula(record: Dictionary, attack: Dictionary, proficiency: int) -> String:
	var total: int = attack_bonus(record, attack, proficiency)
	if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) not in ["item", "unarmed", "improvised"]:
		return "Bestiario %+d + bonus cumulabili %+d = %+d (competenza già inclusa)" % [
			int(attack.get("base_hit", 0)), Bonuses.bonus(record, "attack_hit:" + String(attack.get("id", ""))), total
		]
	var trained: bool = String(attack.get("id", "")) == "unarmed"
	if String(attack.get("id", "")) == "improvised":
		trained = Proficiencies.has_proficiency(record, "weapon", "improvised")
	elif String(attack.get("source", "")) == "item":
		var entry: Variant = attack.get("item_entry", {})
		if entry is Dictionary:
			trained = Proficiencies.weapon_proficient(record, entry as Dictionary)
	elif not trained:
		trained = bool(attack.get("proficient", false))
	return "Caratteristica %+d + competenza %+d + bonus cumulabili %+d = %+d" % [
		_attack_ability_modifier(record, attack), proficiency if trained else 0,
		Bonuses.bonus(record, "attack_hit:" + String(attack.get("id", ""))), total
	]


# Multiply only the weapon's dice; flat magic, ability and origin bonuses stay fixed.
static func weapon_size_dice(base: String, size_name: String) -> String:
	var multiplier: int = Items.weapon_dice_multiplier(size_name)
	if multiplier <= 1:
		return base
	var pattern := RegEx.create_from_string("^(\\s*)(\\d+)d(\\d+)")
	var found: RegExMatch = pattern.search(base) if pattern != null else null
	if found == null:
		return base
	var count: int = int(found.get_string(2))
	var die: int = int(found.get_string(3))
	var extra: String = "%dd%d" % [count * (multiplier - 1), die]
	return base.substr(0, found.get_end()) + " + " + extra + base.substr(found.get_end())


# 5etools stores selected features/feats as structured character choices.
# Do not infer a Fighting Style from merely having Fighter/Ranger levels.
static func has_two_weapon_style(record: Dictionary) -> bool:
	if bool(record.get("two_weapon_fighting", false)):
		return true
	for field: String in ["fighting_styles", "proficiency_choices", "proficiency_origins", "selected_features", "feats_catalog", "trait_choices"]:
		var raw: Variant = record.get(field, [])
		if not raw is Array:
			continue
		for value: Variant in raw:
			var label: String = ""
			if value is Dictionary:
				var row: Dictionary = value
				if bool(row.get("disabled", false)):
					continue
				label = String(row.get("name", row.get("label", row.get("key", ""))))
				for field_name: String in ["fighting_style", "fightingStyle", "selected_style", "selected", "choice"]:
					if row.has(field_name) and not row[field_name] is bool:
						label += " " + String(row[field_name])
			else:
				label = String(value)
			if label.to_lower().contains("two-weapon fighting"):
				return true
	return false


static func has_dual_wielder(record: Dictionary) -> bool:
	for raw: Variant in record.get("feats_catalog", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("disabled", false)):
			if String((raw as Dictionary).get("name", "")).to_lower() == "dual wielder":
				return true
	return false


static func offhand_bonus_attack_allowed(record: Dictionary) -> bool:
	var inventory: Variant = record.get("inventory", [])
	var main: Dictionary = Items.occupying(inventory, "main")
	var off: Dictionary = Items.occupying(inventory, "off")
	if main.is_empty() or off.is_empty():
		return false
	var main_entry: Dictionary = Items.entry_for(main)
	var off_entry: Dictionary = Items.entry_for(off)
	if Items.kind(main_entry) != "weapon" or Items.kind(off_entry) != "weapon":
		return false
	var main_melee: bool = String(main_entry.get("type", "")).split("|")[0].to_upper() != "R"
	var off_melee: bool = String(off_entry.get("type", "")).split("|")[0].to_upper() != "R"
	var main_light: bool = Items.has_property(main_entry, "L")
	var off_light: bool = Items.has_property(off_entry, "L")
	if String(record.get("rules_version", "2014")) == "2024":
		# The Light property also applies to ranged weapons in 2024.
		# Dual Wielder extends the second weapon to one-handed melee weapons,
		# but still requires a Light attack as its trigger.
		return main_light and (off_light or (has_dual_wielder(record) and off_melee))
	# 2014 Two-Weapon Fighting requires two one-handed melee weapons.
	# The Dual Wielder feat removes their Light requirement, not the
	# melee requirement. Thrown attacks retain the same offhand rule.
	return main_melee and off_melee and ((main_light and off_light) or has_dual_wielder(record))


static func damage_label(record: Dictionary, attack: Dictionary) -> String:
	var source: String = String(attack.get("source", ""))
	var base: String = String(attack.get("damage", "")).strip_edges()
	var modifier: int = (
		_ability_delta_for_monster(record, attack)
		if String(record.get("kind", "")) == "monster" and source not in ["item", "unarmed", "improvised"]
		else _attack_ability_modifier(record, attack)
	)
	# The off-hand bonus-action strike keeps its normal attack roll. In 5e
	# the ability modifier is omitted from DAMAGE, unless negative or the
	# character has selected the Two-Weapon Fighting style.
	if source == "item" and String(attack.get("slot", "")) == "off":
		if offhand_bonus_attack_allowed(record) and not has_two_weapon_style(record):
			modifier = mini(0, modifier)
	modifier += Bonuses.bonus(record, "attack_damage:" + String(attack.get("id", "")))
	if String(attack.get("id", "")) == "unarmed":
		return str(maxi(1, 1 + modifier)) + " contundenti"
	if String(attack.get("id", "")) == "improvised":
		return "1d4" + (" %+d" % modifier if modifier != 0 else "") + " contundenti"
	if source == "item":
		var entry: Dictionary = attack.get("item_entry", {})
		var settings: Dictionary = override_for(record, String(attack.get("id", "")))
		if base.is_empty():
			return "Nessun danno automatico (effetto speciale)"
		var inventory: Variant = record.get("inventory", [])
		if (
			not bool(attack.get("thrown", false))
			and String(attack.get("slot", "")) == "main"
			and Items.has_property(entry, "V")
			and Items.occupying(inventory, "off").is_empty()
			and bool(record.get("hand_grip_two_handed", settings.get("two_handed", false)))
			and not String(entry.get("versatile_damage", "")).is_empty()
		):
			base = String(entry.get("versatile_damage", ""))
		var damage_type := Catalog._damage_type_name(String(entry.get("damage_type", "")))
		var size_name: String = String(attack.get("weapon_size", "Medium"))
		var resized: String = weapon_size_dice(base, size_name)
		var size_note := " (taglia %s)" % size_name if resized != base else ""
		return resized + (" %+d" % modifier if modifier != 0 else "") + (" " + damage_type if not damage_type.is_empty() else "") + size_note
	if base.is_empty():
		return "Come da bestiario"
	if String(record.get("kind", "")) == "monster" and modifier == 0:
		return base
	return base + (" %+d" % modifier if modifier != 0 else "")


static func max_melee_range(record: Dictionary) -> float:
	var maximum: float = 5.0
	for attack: Dictionary in definitions(record):
		if bool(attack.get("melee", false)):
			var value: float = float(range_for(record, attack))
			if attack.has("melee_reach_feet") and "ranged" in JSON.stringify(attack.get("raw", {})).to_lower():
				var settings: Dictionary = override_for(record, String(attack.get("id", "")))
				if not settings.has("range_feet"):
					value = float(clampi(Bonuses.add(record, "attack_range:" + String(attack.get("id", "")), int(attack.get("melee_reach_feet", 5))), 5, 1000))
			maximum = maxf(maximum, value)
	return maximum


# The currently chosen attack drives tactical range, not the first melee
# definition in bestiary order. Old sheets without a choice fall back to the
# equipped main-hand weapon, then their first available attack.
static func active_attack(record: Dictionary) -> Dictionary:
	var attacks: Array[Dictionary] = definitions(record)
	var selected: String = String(record.get("equipped_attack_id", ""))
	# A character can explicitly choose an unarmed or improvised strike
	# without removing equipment. Neither fallback is generated for monsters.
	if not selected.is_empty():
		for attack: Dictionary in attacks:
			if String(attack.get("id", "")) == selected:
				return attack
	for attack: Dictionary in attacks:
		if String(attack.get("slot", "")) == "main" and not bool(attack.get("thrown", false)):
			return attack
	return attacks[0] if not attacks.is_empty() else {}


static func active_range(record: Dictionary) -> float:
	var attack: Dictionary = active_attack(record)
	if attack.is_empty():
		return 5.0
	# Hybrid bestiary attacks use the melee reach for engagement, regardless
	# of their longer ranged alternative.
	if bool(attack.get("melee", false)) and attack.has("melee_reach_feet"):
		var setting: Dictionary = override_for(record, String(attack.get("id", "")))
		if not setting.has("range_feet"):
			return float(clampi(Bonuses.add(record, "attack_range:" + String(attack.get("id", "")), int(attack.get("melee_reach_feet", 5))), 5, 1000))
	return float(range_for(record, attack))


# Legacy migration helper, no longer called by the sheet. A newly owned
# weapon is never automatically placed in an empty hand.
static func equip_first_inventory_weapon(record: Dictionary) -> bool:
	var raw: Variant = record.get("inventory", [])
	if not raw is Array or Items.has_equipped_weapon(raw):
		return false
	var rows: Array = raw
	for index: int in range(rows.size()):
		if not rows[index] is Dictionary:
			continue
		var owned: Dictionary = rows[index]
		if int(owned.get("quantity", 0)) <= 0 or Items.kind(Items.entry_for(owned)) != "weapon":
			continue
		var slots: Array = Items.slots(owned)
		if Items.is_two_handed(Items.entry_for(owned)):
			# Do not leave a shield/offhand item in the same two hands.
			for other_index: int in range(rows.size()):
				if not rows[other_index] is Dictionary:
					continue
				var other: Dictionary = rows[other_index]
				var other_slots: Array = Items.slots(other)
				other_slots.erase("off")
				other["equipped_slots"] = other_slots
				rows[other_index] = other
			slots.erase("off")
		elif "off" in slots and int(owned.get("quantity", 1)) == 1:
			slots.erase("off")
		if not "main" in slots:
			slots.append("main")
		owned["equipped_slots"] = slots
		rows[index] = owned
		record["inventory"] = rows
		return true
	return false


# Extract an actual dice formula without its displayed damage-type suffix.
# Fixed damage and unstructured effects are not passed to the dice parser.
static func damage_expression(record: Dictionary, attack: Dictionary) -> String:
	var display: String = damage_label(record, attack)
	var pattern: RegEx = RegEx.create_from_string(
		"^\\s*(\\d+d\\d+(?:\\s*[+-]\\s*(?:\\d+d\\d+|\\d+))*)"
	)
	if pattern == null:
		return ""
	var found: RegExMatch = pattern.search(display.to_lower())
	return found.get_string(1).replace(" ", "") if found != null else ""


# Tactical reach is determined by the first available melee attack in the
# sheet's order; a later long-reach attack must not silently enlarge it.
static func first_melee_range(record: Dictionary) -> float:
	for attack: Dictionary in definitions(record):
		if not bool(attack.get("melee", false)):
			continue
		var settings := override_for(record, String(attack.get("id", "")))
		if settings.has("range_feet"):
			return float(range_for(record, attack))
		# A bestiary attack that supports both melee and ranged modes must
		# use its melee reach, never the projectile range.
		if attack.has("melee_reach_feet") and "ranged" in JSON.stringify(
			attack.get("raw", {})
		).to_lower():
			return float(clampi(Bonuses.add(record, "attack_range:" + String(attack.get("id", "")), int(attack.get("melee_reach_feet", 5))), 5, 1000))
		return float(range_for(record, attack))
	return 5.0
