extends RefCounted
## Exact rule data and a single tactical executor shared by desktop and mobile.
## Checks are adjudicated at the table: the VTT never invents a successful roll.
const ACTIONS := ["help", "shove", "prone"]
const SIZES := ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]

static func edition(record: Dictionary) -> String:
	return "2024" if String(record.get("rules_version", "2014")) == "2024" else "2014"

static func shove_details(record: Dictionary, athletics_bonus: int = 0, strength_modifier: int = 0, proficiency: int = 0) -> Dictionary:
	if edition(record) == "2024":
		return {"edition": "2024", "dc": 8 + strength_modifier + proficiency,
			"check": "Tiro salvezza a scelta del bersaglio: Forza o Destrezza.",
			"action": "Sostituisce un attacco con un colpo senz'armi. Fallimento del TS: prono o spostamento di 5 ft."}
	return {"edition": "2014", "athletics_bonus": athletics_bonus,
		"check": "Forza (Atletica) contro Forza (Atletica) o Destrezza (Acrobazia) del bersaglio. Il difensore vince i pareggi.",
		"action": "Sostituisce un attacco dell'azione Attaccare. Successo: prono o spostamento di 5 ft."}

static func _size(node: Node3D) -> int:
	var name := String(node.get("_size_name")) if "_size_name" in node else String(node.get_meta("size_name", "Medium"))
	var index := SIZES.find(name)
	return index if index >= 0 else 2

static func validate(board: Node, actor: CharacterBody3D, target: CharacterBody3D, mode: String) -> Dictionary:
	if mode not in ACTIONS:
		return {"ok": false, "error": "Azione sconosciuta."}
	if board == null or actor == null or target == null or not is_instance_valid(actor) or not is_instance_valid(target):
		return {"ok": false, "error": "Token non disponibile."}
	if not board.is_ancestor_of(actor) or not board.is_ancestor_of(target):
		return {"ok": false, "error": "Il bersaglio non appartiene alla mappa."}
	if actor == target:
		return {"ok": false, "error": "Seleziona un'altra creatura."}
	if mode == "help":
		return {"ok": true}
	if _size(target) > _size(actor) + 1:
		return {"ok": false, "error": "Il bersaglio supera di oltre una taglia l'attaccante."}
	var cell := maxf(0.01, float(board.get("cell_size")))
	var reach := 5.0
	if actor.has_method("get_reach_feet"):
		reach = maxf(5.0, float(actor.call("get_reach_feet")))
	var a := actor.global_position
	var b := target.global_position
	var dx := absf(a.x - b.x) / cell
	var dz := absf(a.z - b.z) / cell
	var footprint := 1.0
	if actor.has_method("get_footprint_cells") and target.has_method("get_footprint_cells"):
		footprint = maxf(1.0, (float(actor.call("get_footprint_cells")) + float(target.call("get_footprint_cells"))) / 2.0)
	var gap := maxf(0.0, maxf(dx, dz) - footprint) * 5.0
	if gap > reach - 5.0 + 0.001:
		return {"ok": false, "error": "Bersaglio fuori portata per una spinta."}
	return {"ok": true}

static func execute(board: Node, actor: CharacterBody3D, target: CharacterBody3D, mode: String, success_confirmed: bool = false) -> Dictionary:
	var valid: Dictionary = validate(board, actor, target, mode)
	if not bool(valid.get("ok", false)):
		return valid
	if mode == "help":
		board.call("_set_token_status", target, "helped", true)
		return {"ok": true, "condition": "helped"}
	if not success_confirmed:
		return {"ok": false, "error": "Prima risolvi la prova contrapposta (2014) o il tiro salvezza (2024), quindi conferma il successo."}
	if mode == "prone":
		board.call("_set_token_status", target, "prone", true)
		return {"ok": true, "condition": "prone"}
	# Forced movement: never use normal movement controls, which could charge
	# movement, trigger opportunity attacks or move a mounted group.
	var delta := target.global_position - actor.global_position
	var direction := Vector3(signf(delta.x), 0, signf(delta.z))
	if direction.length_squared() < 0.5:
		return {"ok": false, "error": "Impossibile stabilire la direzione della spinta."}
	var offset := direction * maxf(float(board.get("cell_size")), 0.01)
	if target.test_move(target.global_transform, offset):
		return {"ok": false, "error": "La casella di destinazione è occupata o ostruita."}
	if board.has_method("push_undo_state"):
		board.call("push_undo_state")
	target.global_position += offset
	if board.has_method("_sync_explicit_token_change"):
		board.call_deferred("_sync_explicit_token_change", target)
	return {"ok": true, "moved": true}
