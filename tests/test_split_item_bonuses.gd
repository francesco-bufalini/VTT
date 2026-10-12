extends SceneTree

const Bonuses = preload("res://vtt/creature_bonus_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var spare := {"id": "regression:split-blade", "name": "Blade", "type": "M", "damage": "1d8",
		"bonus_weapon": 2, "bonus_saving_throw": 1, "quantity": 1, "equipped_slots": []}
	var main := spare.duplicate(true)
	main.equipped_slots = ["main"]
	var off := spare.duplicate(true)
	off.equipped_slots = ["off"]
	var record := {"kind": "character", "inventory": [spare, main], "formula_bonuses": []}
	assert(Bonuses.bonus(record, "attack_hit:item:regression:split-blade") == 2,
		"An unequipped spare must not mask the equipped copy")
	assert(Bonuses.bonus(record, "save:wis") == 1)
	for inventory: Array in [[main, off], [off, main], [spare, off, main], [main, off, main]]:
		record.inventory = inventory
		for attack_id: String in ["item:regression:split-blade", "item:off:regression:split-blade",
			"item:throw:main:regression:split-blade", "item:throw:off:regression:split-blade"]:
			assert(Bonuses.bonus(record, "attack_hit:" + attack_id) == 2)
			assert(Bonuses.bonus(record, "attack_damage:" + attack_id) == 2,
				"Each hand must retain its own bonus independent of inventory order")
		assert(Bonuses.bonus(record, "save:wis") == 1, "Passive bonuses must not double across copies")
	off.active = false
	record.inventory = [off, main]
	assert(Bonuses.bonus(record, "attack_hit:item:off:regression:split-blade") == 0)
	assert(Bonuses.bonus(record, "attack_hit:item:regression:split-blade") == 2)
	var spare_armor := {"id": "regression:split-armor", "type": "HA", "ac": 18, "bonus_ac": 1,
		"quantity": 1, "equipped_slots": []}
	var worn := spare_armor.duplicate(true)
	worn.equipped_slots = ["body"]
	record.inventory = [spare_armor, worn]
	assert(Bonuses.bonus(record, "ac") == 1, "Spare armor must not suppress the worn armor bonus")
	var packed_ring := {"id": "regression:split-ring", "type": "RG", "bonus_saving_throw": 2,
		"quantity": 1, "equipped": false}
	var worn_ring := packed_ring.duplicate(true)
	worn_ring.equipped = true
	record.inventory = [packed_ring, worn_ring, worn_ring]
	assert(Bonuses.bonus(record, "save:wis") == 2, "Packed generic items must not mask or duplicate worn ones")
	print("PASS: split equipment bonuses, inventory ordering, both hands and unique passive grants")
	quit()