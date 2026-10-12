extends RefCounted

# 5etools item semantics shared by inventory, attack calculations and saves.
# The compact item catalog stores type M/R/S, damage, range and properties.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const ItemInstance = preload("res://vtt/item_instance.gd")

static var _catalog_by_id: Dictionary = {}
const WEAPON_SIZES := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]


# The saved override exists only when an individual weapon differs from its wielder.
static func weapon_size(record: Dictionary, owned: Dictionary) -> String:
	var raw: Variant = owned.get("instance_overrides", {})
	var explicit: String = String((raw as Dictionary).get("weapon_size", "")) if raw is Dictionary else ""
	if explicit in WEAPON_SIZES:
		return explicit
	var creature_size: String = String(record.get("size_name", "Medium"))
	return creature_size if creature_size in WEAPON_SIZES else "Medium"


# DMG 2014, monster weapon sizing: Small/Medium (and Tiny) use catalog dice;
# Large, Huge and Gargantuan weapons have 2x, 3x and 4x weapon dice.
static func weapon_dice_multiplier(size_name: String) -> int:
	match size_name:
		"Large": return 2
		"Huge": return 3
		"Gargantuan": return 4
		_: return 1




static func reset_catalog() -> void:
	_catalog_by_id.clear()


static func entry_for(saved: Dictionary) -> Dictionary:
	var item_id: String = String(saved.get("id", ""))
	if _catalog_by_id.is_empty():
		for item: Dictionary in Catalog.entries("items"):
			_catalog_by_id[String(item.get("id", ""))] = item
	var definition: Dictionary = _catalog_by_id.get(item_id, saved)
	return ItemInstance.resolve(definition, saved)


static func kind(entry: Dictionary) -> String:
	if String(entry.get("category", "")) == "documents":
		return "document"
	var type_code := String(entry.get("type", "")).split("|")[0].to_upper()
	if type_code in ["M", "R"] and (
		not String(entry.get("weapon_category", "")).is_empty()
		or not String(entry.get("damage", "")).is_empty()
		or entry.has("properties")
	):
		return "weapon"
	if type_code == "S":
		return "shield"
	if type_code in ["LA", "MA", "HA"]:
		return "armor"
	if type_code in ["AT", "INS", "T", "SCF", "GS", "P", "MNT"]:
		return "tool"
	if String(entry.get("id", "")).begins_with("magic_item:"):
		return "magic"
	return "other"


static func category_name(entry: Dictionary) -> String:
	match kind(entry):
		"weapon": return "Armi"
		"shield": return "Scudi"
		"armor": return "Armature"
		"tool": return "Strumenti"
		"magic": return "Oggetti magici"
		"document": return "Documenti"
		_: return "Altri oggetti"


static func has_property(entry: Dictionary, code: String) -> bool:
	return Catalog.has_property(entry, code)


static func is_two_handed(entry: Dictionary) -> bool:
	return has_property(entry, "2H")


# 5etools reqAttune/req_attune is either a boolean or a conditional
# requirement string ("by a spellcaster", etc.). Never compare a String
# with false: Godot 4 rejects mixed-type == / != operations at runtime.
static func requires_attunement(entry: Dictionary) -> bool:
	var requirement: Variant = entry.get("req_attune", entry.get("reqAttune", false))
	if requirement is bool:
		return requirement
	if requirement is String:
		return not String(requirement).strip_edges().is_empty()
	return false


static func slots(saved: Dictionary) -> Array:
	var value: Variant = saved.get("equipped_slots", [])
	if value is Array:
		return (value as Array).duplicate()
	return []


# Item ownership is distinct from activation. Equipment-dependent traits
# remain visible in the sheet but grant nothing until actually equipped.
static func origin_active(saved: Dictionary) -> bool:
	if int(saved.get("quantity", 1)) <= 0 or not bool(saved.get("active", true)):
		return false
	var entry: Dictionary = entry_for(saved)
	if requires_attunement(entry) and not bool(saved.get("attuned", false)):
		return false
	var category: String = kind(entry)
	var equipped: Array = slots(saved)
	if category == "armor":
		return "body" in equipped
	if category == "shield":
		return "off" in equipped
	if category == "weapon":
		return "main" in equipped or "off" in equipped
	return bool(saved.get("equipped", false))


static func occupying(inventory: Variant, slot: String) -> Dictionary:
	if inventory is Array:
		for value: Variant in inventory:
			if value is Dictionary:
				var item: Dictionary = value
				if int(item.get("quantity", 0)) > 0 and slot in slots(item):
					return item
	return {}


# An equipped shield does not suppress fallback unarmed/improvised options.
# Check only occupied hand slots, not weapons merely owned in the inventory.
static func has_equipped_weapon(inventory: Variant) -> bool:
	for slot: String in ["main", "off"]:
		var saved: Dictionary = occupying(inventory, slot)
		if not saved.is_empty() and kind(entry_for(saved)) == "weapon":
			return true
	return false


static func equipped_armor(inventory: Variant) -> Dictionary:
	var owned: Dictionary = occupying(inventory, "body")
	if not owned.is_empty() and kind(entry_for(owned)) == "armor":
		return owned
	return {}


# Heavy armor ignores Dexterity, including negative modifiers. An explicit
# nonzero cap can opt a custom heavy armor into the usual DEX calculation.
static func armor_uses_dexterity(entry: Dictionary) -> bool:
	var type_code := String(entry.get("type", "")).split("|")[0].to_upper()
	return type_code != "HA" or int(entry.get("dexterity_max", 0)) != 0

# An armor replaces the AC base, it does not add an armor bonus to another
# base. Light/medium/heavy armor differ in permitted Dexterity modifiers.
static func armor_base(record: Dictionary) -> Dictionary:
	var owned: Dictionary = equipped_armor(record.get("inventory", []))
	if owned.is_empty():
		return {"equipped": false, "value": int(record.get("armor_class_base", 10)), "description": "Base manuale"}
	var entry: Dictionary = entry_for(owned)
	var type_code: String = String(entry.get("type", "")).split("|")[0].to_upper()
	var dex: int = int(record.get("effective_armor_dex", 0))
	var limit: int = 99
	if type_code == "MA":
		limit = 2
	elif type_code == "HA":
		limit = 0
	if entry.has("dexterity_max"):
		limit = int(entry["dexterity_max"])
	var allowed: int = mini(dex, limit) if armor_uses_dexterity(entry) else 0
	var base: int = int(entry.get("ac", 10))
	return {"equipped": true, "value": base + allowed,
		"description": "%s: %d %+d DES" % [String(entry.get("name", owned.get("name", "Armatura"))), base, allowed]}


static func shield_bonus(inventory: Variant) -> int:
	var shield: Dictionary = occupying(inventory, "off")
	if shield.is_empty():
		return 0
	var entry: Dictionary = entry_for(shield)
	if kind(entry) != "shield":
		return 0
	# The base value and a magic +AC bonus are separate structured fields.
	return maxi(0, int(entry.get("ac", 2)))


static func item_range(entry: Dictionary, long_range: bool = false) -> int:
	var ranges := String(entry.get("range", "")).split("/")
	if ranges.is_empty():
		return 0
	return maxi(0, int(ranges[1] if long_range and ranges.size() > 1 else ranges[0]))


static func attack_ability(record: Dictionary, entry: Dictionary, thrown: bool = false) -> String:
	var type_code := String(entry.get("type", "")).split("|")[0].to_upper()
	if type_code == "R" and not thrown:
		# Finesse ranged weapons such as the 2014 dart may also use STR.
		if has_property(entry, "F") and String(record.get("attack_ability", "str")) == "str":
			return "str"
		return "dex"
	# Thrown melee weapons keep their melee modifier in the 2014 rules.
	if String(record.get("attack_ability", "str")) == "dex" and has_property(entry, "F"):
		return "dex"
	return "str"


static func valid_slot(entry: Dictionary, slot: String) -> bool:
	var item_kind := kind(entry)
	return (item_kind == "weapon" and slot in ["main", "off"] and (slot == "main" or not is_two_handed(entry))) or (slot == "off" and item_kind == "shield") or (slot == "body" and item_kind == "armor")
