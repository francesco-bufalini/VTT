extends SceneTree

const DiceChatSync = preload("res://network/dice_chat_sync.gd")
const DiceRollerChat = preload("res://vtt/dice_roller_chat.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var board_sync: Script = load("res://network/board_sync.gd")
	# Chat/dice traffic must never share the map-sync socket/protocol.
	assert(DiceChatSync.PORT != board_sync.PORT)
	assert(DiceChatSync.MAGIC != board_sync.MAGIC)

	assert(DiceRollerChat.percentile_total(0, 0) == 100)
	assert(DiceRollerChat.percentile_total(0, 7) == 7)
	assert(DiceRollerChat.percentile_total(20, 0) == 20)
	assert(DiceRollerChat.percentile_total(90, 9) == 99)

	var roll := {
		"id": "test-roll-1",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 1,
		"die": "d20",
		"total": 20,
		"detail": ""
	}
	assert(DiceChatSync.valid_event(roll))

	var percentile := {
		"id": "test-roll-2",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 2,
		"die": "d%",
		"total": 100,
		"tens": 0,
		"ones": 0,
		"detail": "00 + 0"
	}
	assert(DiceChatSync.valid_event(percentile))

	var multi_roll := {
		"id": "test-roll-multi",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 3,
		"die": "d20",
		"count": 3,
		"modifier": 5,
		"rolls": [12, 7, 20],
		"total": 44,
		"detail": "[12, 7, 20] · +5"
	}
	assert(DiceChatSync.valid_event(multi_roll))
	assert(
		DiceRollerChat._roll_notation("d20", 3, 5)
		== "3d20 + 5"
	)
	assert(
		DiceRollerChat._roll_notation("d8", 2, -3)
		== "2d8 - 3"
	)
	assert(DiceRollerChat.choose_d20_pair(7, 18, "advantage") == 18)
	assert(DiceRollerChat.choose_d20_pair(7, 18, "disadvantage") == 7)
	assert(
		DiceRollerChat._roll_notation("d20", 1, 5, "advantage")
		== "1d20 (vant.) + 5"
	)

	var advantage_roll := {
		"id": "test-roll-advantage",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 4,
		"die": "d20",
		"count": 1,
		"modifier": 5,
		"roll_mode": "advantage",
		"candidate_rolls": [[7, 18]],
		"rolls": [18],
		"total": 23,
		"detail": "Vantaggio [7/18 → 18] · +5"
	}
	assert(DiceChatSync.valid_event(advantage_roll))
	var bad_advantage := advantage_roll.duplicate(true)
	bad_advantage["rolls"] = [7]
	bad_advantage["total"] = 12
	assert(not DiceChatSync.valid_event(bad_advantage))

	var multi_percentile := {
		"id": "test-roll-percentile-multi",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 4,
		"die": "d%",
		"count": 2,
		"modifier": -10,
		"rolls": [73, 100],
		"total": 163,
		"detail": "[73, 100] · 70+3=73, 00+0=100 · -10"
	}
	assert(DiceChatSync.valid_event(multi_percentile))

	var mismatched_total := multi_roll.duplicate(true)
	mismatched_total["total"] = 45
	assert(not DiceChatSync.valid_event(mismatched_total))

	var bad_die_result := multi_roll.duplicate(true)
	bad_die_result["rolls"] = [12, 21, 20]
	bad_die_result["total"] = 58
	assert(not DiceChatSync.valid_event(bad_die_result))

	var parsed_damage := DiceRollerChat.parse_dice_expression(
		"1d8 + 5 + 5d6"
	)
	assert(not parsed_damage.is_empty())
	assert(int(parsed_damage.get("modifier", 0)) == 5)
	var parsed_terms: Array = parsed_damage.get("terms", [])
	assert(parsed_terms.size() == 2)
	assert(int((parsed_terms[0] as Dictionary).get("count", 0)) == 1)
	assert(int((parsed_terms[0] as Dictionary).get("sides", 0)) == 8)
	assert(int((parsed_terms[1] as Dictionary).get("count", 0)) == 5)
	assert(int((parsed_terms[1] as Dictionary).get("sides", 0)) == 6)

	var formula_roll := {
		"id": "test-formula-roll",
		"kind": "roll",
		"author": "Tester",
		"timestamp": 5,
		"label": "Lyria · Danni · Pugnale + Attacco Furtivo",
		"die": "formula",
		"count": 6,
		"modifier": 5,
		"notation": "1d8 + 5 + 5d6",
		"terms": [
			{
				"count": 1,
				"sides": 8,
				"sign": 1,
				"rolls": [6]
			},
			{
				"count": 5,
				"sides": 6,
				"sign": 1,
				"rolls": [1, 2, 3, 4, 5]
			}
		],
		"total": 26,
		"detail": "1d8 [6] · 5d6 [1, 2, 3, 4, 5] · +5"
	}
	assert(DiceChatSync.valid_event(formula_roll))

	var bad_formula := formula_roll.duplicate(true)
	bad_formula["total"] = 27
	assert(not DiceChatSync.valid_event(bad_formula))

	var chat := {
		"id": "test-chat-1",
		"kind": "chat",
		"author": "Tester",
		"timestamp": 6,
		"text": "Ciao party"
	}
	assert(DiceChatSync.valid_event(chat))

	var bad_roll := roll.duplicate(true)
	bad_roll["total"] = 21
	assert(not DiceChatSync.valid_event(bad_roll))

	var bad_chat := chat.duplicate(true)
	bad_chat["text"] = ""
	assert(not DiceChatSync.valid_event(bad_chat))

	print("PASS: isolated dice/chat protocol and percentile dice")
	quit()
