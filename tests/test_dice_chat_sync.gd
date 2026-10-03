extends SceneTree

const BoardSync = preload("res://network/board_sync.gd")
const DiceChatSync = preload("res://network/dice_chat_sync.gd")
const DiceRollerChat = preload("res://vtt/dice_roller_chat.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Chat/dice traffic must never share the map-sync socket/protocol.
	assert(DiceChatSync.PORT != BoardSync.PORT)
	assert(DiceChatSync.MAGIC != BoardSync.MAGIC)

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

	var chat := {
		"id": "test-chat-1",
		"kind": "chat",
		"author": "Tester",
		"timestamp": 3,
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
