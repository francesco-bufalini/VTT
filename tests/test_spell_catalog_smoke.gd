extends SceneTree

const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")


func _initialize() -> void:
	call_deferred("run")


func _expect(value: bool, message: String) -> bool:
	if value:
		return true
	push_error("Spell catalog smoke: " + message)
	quit(1)
	return false


func run() -> void:
	var fireball: Dictionary = SpellCatalog.spell("fireball")
	if not _expect(not fireball.is_empty(), "Fireball missing"):
		return
	if not _expect(
		String(fireball.get("aoe_shape", "")) == "sphere",
		"Fireball geometry changed"
	):
		return
	if not _expect(
		is_equal_approx(float(fireball.get("aoe_radius_feet", 0.0)), 20.0),
		"Fireball radius changed"
	):
		return

	var lightning_bolt: Dictionary = SpellCatalog.spell("lightning_bolt")
	if not _expect(not lightning_bolt.is_empty(), "Lightning Bolt missing"):
		return
	if not _expect(
		String(lightning_bolt.get("aoe_shape", "")) == "line",
		"Lightning Bolt geometry changed"
	):
		return

	var misty_step: Dictionary = SpellCatalog.spell("misty_step")
	if not _expect(not misty_step.is_empty(), "Misty Step missing"):
		return
	if not _expect(
		String(misty_step.get("target_mode", "")) == "teleport_self",
		"Misty Step targeting changed"
	):
		return

	var hold_person: Dictionary = SpellCatalog.spell("hold_person")
	if not _expect(not hold_person.is_empty(), "Hold Person missing"):
		return
	var conditions: Array = hold_person.get("condition_inflict", [])
	if not _expect("paralyzed" in conditions, "Hold Person condition changed"):
		return

	var find_familiar: Dictionary = SpellCatalog.spell("find_familiar")
	if not _expect(not find_familiar.is_empty(), "Find Familiar missing"):
		return
	if not _expect(
		String(find_familiar.get("target_mode", "")) == "summon",
		"Find Familiar summon targeting changed"
	):
		return

	print("PASS: representative spell catalog mechanics")
	quit()
