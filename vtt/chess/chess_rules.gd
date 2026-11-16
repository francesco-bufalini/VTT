extends RefCounted
## Pure, deterministic classical chess rules for Scacchi dei Maghi.
## Files are 0..7 (a..h); ranks 0..7 are shown black-to-white (8..1).
## Piece encoding: w/b for side, K/Q/R/B/N/P for kind, "." for empty.

const BACK_RANK := ["R", "N", "B", "Q", "K", "B", "N", "R"]
const KNIGHT_JUMPS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)
]
const STRAIGHTS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAGONALS := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const NO_SQUARE := Vector2i(-1, -1)

var board: Array[String] = []
var turn := "w"
var castling := {"wK": true, "wQ": true, "bK": true, "bQ": true}
var en_passant := NO_SQUARE
var halfmove_clock := 0
var fullmove_number := 1
var position_counts: Dictionary = {}
var history: Array[Dictionary] = []
# Each player keeps their own pieces previously captured by the opponent.
var captured_pieces := {"w": [], "b": []}
var transformed_this_turn := false
# Temporary forms keyed by owner. Square follows the token when it moves.
# Record: {"square": [file, rank], "original": "P"/"N"/"B"/"R"/"Q"}.
var active_transforms: Dictionary = {}
var finished := false
var status := ""


func _init() -> void:
	reset()


func reset() -> void:
	board.clear()
	for rank in range(8):
		for file in range(8):
			var code := "."
			match rank:
				0: code = "b" + BACK_RANK[file]
				1: code = "bP"
				6: code = "wP"
				7: code = "w" + BACK_RANK[file]
			board.append(code)
	turn = "w"
	castling = {"wK": true, "wQ": true, "bK": true, "bQ": true}
	en_passant = NO_SQUARE
	halfmove_clock = 0
	fullmove_number = 1
	history.clear()
	captured_pieces = {"w": [], "b": []}
	transformed_this_turn = false
	active_transforms.clear()
	position_counts.clear()
	finished = false
	_record_position()
	_evaluate()


static func inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < 8 and pos.y >= 0 and pos.y < 8


static func opposite(side: String) -> String:
	return "b" if side == "w" else "w"


static func _at(cells: Array[String], pos: Vector2i) -> String:
	if not inside(pos):
		return "."
	return cells[pos.y * 8 + pos.x]


static func _put(cells: Array[String], pos: Vector2i, code: String) -> void:
	cells[pos.y * 8 + pos.x] = code


func piece(pos: Vector2i) -> String:
	return _at(board, pos)


func king_square(side: String) -> Vector2i:
	return _find_king(board, side)


static func _find_king(cells: Array[String], side: String) -> Vector2i:
	var index := cells.find(side + "K")
	if index == -1:
		return NO_SQUARE
	return Vector2i(index % 8, index / 8)


static func _is_attacked(cells: Array[String], target: Vector2i, attacker: String) -> bool:
	# Pawns attack diagonally regardless of occupancy of their forward square.
	var forward := -1 if attacker == "w" else 1
	for dx in [-1, 1]:
		if _at(cells, target - Vector2i(dx, forward)) == attacker + "P":
			return true
	for delta in KNIGHT_JUMPS:
		if _at(cells, target + delta) == attacker + "N":
			return true
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if (dx != 0 or dy != 0) and _at(cells, target + Vector2i(dx, dy)) == attacker + "K":
				return true
	for delta in STRAIGHTS + DIAGONALS:
		var pos: Vector2i = target + delta
		while inside(pos):
			var code := _at(cells, pos)
			if code != ".":
				if code.begins_with(attacker):
					var kind := code.substr(1, 1)
					if kind == "Q" or (kind == "R" and delta in STRAIGHTS) or (kind == "B" and delta in DIAGONALS):
						return true
				break
			pos += delta
	return false


func in_check(side: String) -> bool:
	var king := _find_king(board, side)
	return king != NO_SQUARE and _is_attacked(board, king, opposite(side))


func _add_target(options: Array[Dictionary], from: Vector2i, to: Vector2i, extra: Dictionary = {}) -> void:
	if not inside(to):
		return
	var origin := piece(from)
	var destination := piece(to)
	if destination.begins_with(origin.substr(0, 1)) or destination.ends_with("K"):
		return
	var entry: Dictionary = {"to": to}
	entry.merge(extra)
	options.append(entry)


func _pseudo_moves(from: Vector2i) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var code := piece(from)
	if code == ".":
		return options
	var side := code.substr(0, 1)
	var enemy := opposite(side)
	var kind := code.substr(1, 1)
	match kind:
		"P":
			var forward := -1 if side == "w" else 1
			var promotion_rank := 0 if side == "w" else 7
			var one := from + Vector2i(0, forward)
			if inside(one) and piece(one) == ".":
				_add_target(options, from, one, {"promotion": true} if one.y == promotion_rank else {})
				var start_rank := 6 if side == "w" else 1
				var two := from + Vector2i(0, 2 * forward)
				if from.y == start_rank and piece(two) == ".":
					_add_target(options, from, two)
			for dx in [-1, 1]:
				var to := from + Vector2i(dx, forward)
				if not inside(to):
					continue
				if piece(to).begins_with(enemy):
					_add_target(options, from, to, {"promotion": true} if to.y == promotion_rank else {})
				elif to == en_passant and piece(to) == "." and piece(Vector2i(to.x, from.y)) == enemy + "P":
					_add_target(options, from, to, {"en_passant": true})
		"N":
			for delta in KNIGHT_JUMPS:
				_add_target(options, from, from + delta)
		"B", "R", "Q":
			var directions: Array[Vector2i] = []
			if kind in ["B", "Q"]:
				directions.append_array(DIAGONALS)
			if kind in ["R", "Q"]:
				directions.append_array(STRAIGHTS)
			for delta in directions:
				var to := from + delta
				while inside(to):
					if piece(to) == ".":
						_add_target(options, from, to)
					else:
						_add_target(options, from, to)
						break
					to += delta
		"K":
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx != 0 or dy != 0:
						_add_target(options, from, from + Vector2i(dx, dy))
			var rank := 7 if side == "w" else 0
			if from == Vector2i(4, rank) and not _is_attacked(board, from, enemy):
				if bool(castling.get(side + "K", false)) and piece(Vector2i(7, rank)) == side + "R":
					if piece(Vector2i(5, rank)) == "." and piece(Vector2i(6, rank)) == ".":
						if not _is_attacked(board, Vector2i(5, rank), enemy) and not _is_attacked(board, Vector2i(6, rank), enemy):
							options.append({"to": Vector2i(6, rank), "castle": "K"})
				if bool(castling.get(side + "Q", false)) and piece(Vector2i(0, rank)) == side + "R":
					if piece(Vector2i(1, rank)) == "." and piece(Vector2i(2, rank)) == "." and piece(Vector2i(3, rank)) == ".":
						if not _is_attacked(board, Vector2i(3, rank), enemy) and not _is_attacked(board, Vector2i(2, rank), enemy):
							options.append({"to": Vector2i(2, rank), "castle": "Q"})
	return options


static func _apply_to(cells: Array[String], from: Vector2i, move: Dictionary, promotion: String = "Q") -> void:
	var to: Vector2i = move["to"]
	var moving := _at(cells, from)
	_put(cells, from, ".")
	if bool(move.get("en_passant", false)):
		_put(cells, Vector2i(to.x, from.y), ".")
	if String(move.get("castle", "")) != "":
		var rank := from.y
		if move["castle"] == "K":
			_put(cells, Vector2i(5, rank), _at(cells, Vector2i(7, rank)))
			_put(cells, Vector2i(7, rank), ".")
		else:
			_put(cells, Vector2i(3, rank), _at(cells, Vector2i(0, rank)))
			_put(cells, Vector2i(0, rank), ".")
	if bool(move.get("promotion", false)):
		moving = moving.substr(0, 1) + promotion
	_put(cells, to, moving)


func legal_moves(from: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if finished or not inside(from):
		return result
	var code := piece(from)
	if code == "." or not code.begins_with(turn):
		return result
	for move in _pseudo_moves(from):
		var hypothetical: Array[String] = board.duplicate()
		_apply_to(hypothetical, from, move)
		var king := _find_king(hypothetical, turn)
		if king != NO_SQUARE and not _is_attacked(hypothetical, king, opposite(turn)):
			result.append(move)
	return result


func _revoke_corner(pos: Vector2i) -> void:
	if pos == Vector2i(0, 7):
		castling["wQ"] = false
	elif pos == Vector2i(7, 7):
		castling["wK"] = false
	elif pos == Vector2i(0, 0):
		castling["bQ"] = false
	elif pos == Vector2i(7, 0):
		castling["bK"] = false


## A player may exchange one non-king piece for one of their captured pieces
## before making the ordinary move of their turn. Recovered pieces are spent.
func available_transformations() -> Array[String]:
	var available: Array[String] = []
	if finished or transformed_this_turn:
		return available
	for kind in captured_pieces.get(turn, []):
		if kind not in available:
			available.append(kind)
	return available


func transform(at: Vector2i, kind: String) -> bool:
	if finished or transformed_this_turn or active_transforms.has(turn) or not inside(at) or kind not in available_transformations():
		return false
	var previous := piece(at)
	if not previous.begins_with(turn) or previous.ends_with("K"):
		return false
	history.append(_state_without_history())
	captured_pieces[turn].erase(kind)
	if previous.ends_with("R"):
		_revoke_corner(at)
	_put(board, at, turn + kind)
	active_transforms[turn] = {"square": [at.x, at.y], "original": previous.substr(1, 1)}
	transformed_this_turn = true
	# En passant remains possible during the ordinary move of this turn.
	# Transforming changes material and therefore resets the draw clock.
	halfmove_clock = 0
	_record_position()
	_evaluate()
	return true


static func _transform_square(record: Dictionary) -> Vector2i:
	var at: Array = record["square"]
	return Vector2i(int(at[0]), int(at[1]))


func _revert_transformation(side: String) -> void:
	if not active_transforms.has(side):
		return
	var record: Dictionary = active_transforms[side]
	var at := _transform_square(record)
	if inside(at) and piece(at).begins_with(side):
		_put(board, at, side + String(record["original"]))
	active_transforms.erase(side)


func play(from: Vector2i, to: Vector2i, promotion: String = "Q") -> bool:
	if finished or promotion not in ["Q", "R", "B", "N"]:
		return false
	var chosen: Dictionary = {}
	for candidate in legal_moves(from):
		if candidate["to"] == to:
			chosen = candidate
			break
	if chosen.is_empty():
		return false
	history.append(_state_without_history())
	var moving := piece(from)
	var moving_side := turn
	var captured_at := Vector2i(to.x, from.y) if bool(chosen.get("en_passant", false)) else to
	var captured := piece(captured_at)
	var captured_kind := captured.substr(1, 1)
	var victim_side := opposite(moving_side)
	if active_transforms.has(victim_side):
		var victim_record: Dictionary = active_transforms[victim_side]
		if _transform_square(victim_record) == captured_at:
			# A captured disguised piece counts as its original kind.
			captured_kind = String(victim_record["original"])
			active_transforms.erase(victim_side)
	_apply_to(board, from, chosen, promotion)
	if captured != ".":
		captured_pieces[victim_side].append(captured_kind)
	if active_transforms.has(moving_side):
		var own_record: Dictionary = active_transforms[moving_side]
		if _transform_square(own_record) == from:
			own_record["square"] = [to.x, to.y]
			active_transforms[moving_side] = own_record
	if moving.ends_with("K"):
		castling[moving_side + "K"] = false
		castling[moving_side + "Q"] = false
	if moving.ends_with("R"):
		_revoke_corner(from)
	if captured.ends_with("R"):
		_revoke_corner(to)
	en_passant = NO_SQUARE
	if moving.ends_with("P") and absi(to.y - from.y) == 2:
		en_passant = Vector2i(from.x, (from.y + to.y) / 2)
	halfmove_clock = 0 if moving.ends_with("P") or captured != "." or bool(chosen.get("en_passant", false)) else halfmove_clock + 1
	if moving_side == "b":
		fullmove_number += 1
	turn = opposite(turn)
	transformed_this_turn = false
	# Once the opponent has played, restore this player's transformed piece
	# BEFORE evaluating check, legal moves, and possible game over.
	_revert_transformation(turn)
	_record_position()
	_evaluate()
	return true


func _position_key() -> String:
	return JSON.stringify(board) + ":" + turn + ":" + JSON.stringify(castling) + ":" + str(en_passant) + ":" + JSON.stringify(captured_pieces) + ":" + str(transformed_this_turn) + ":" + JSON.stringify(active_transforms)


func _record_position() -> void:
	var key := _position_key()
	position_counts[key] = int(position_counts.get(key, 0)) + 1


func _has_legal_move() -> bool:
	for y in range(8):
		for x in range(8):
			var at := Vector2i(x, y)
			if piece(at).begins_with(turn) and not legal_moves(at).is_empty():
				return true
	return false


func _insufficient_material() -> bool:
	# A captured piece may return, so kings alone do not guarantee a dead position.
	if not captured_pieces["w"].is_empty() or not captured_pieces["b"].is_empty() or not active_transforms.is_empty():
		return false
	var minors: Array[Dictionary] = []
	for i in range(board.size()):
		var code := board[i]
		if code == "." or code.ends_with("K"):
			continue
		if code.ends_with("P") or code.ends_with("R") or code.ends_with("Q"):
			return false
		minors.append({"code": code, "color": (i % 8 + i / 8) % 2})
	if minors.size() <= 1:
		return true
	# One bishop on each side, both restricted to the same square color.
	return minors.size() == 2 and minors[0]["code"].ends_with("B") and minors[1]["code"].ends_with("B") and minors[0]["code"].substr(0, 1) != minors[1]["code"].substr(0, 1) and minors[0]["color"] == minors[1]["color"]


## Test whether a turn that has no legal ordinary move can be rescued
## by exchanging a piece; otherwise checkmate/stalemate remains definitive.
func _has_transform_escape() -> bool:
	if transformed_this_turn or captured_pieces[turn].is_empty():
		return false
	for index in range(board.size()):
		var previous := board[index]
		if not previous.begins_with(turn) or previous.ends_with("K"):
			continue
		for kind in captured_pieces[turn]:
			var old_rights: Dictionary = castling.duplicate()
			if previous.ends_with("R"):
				_revoke_corner(Vector2i(index % 8, index / 8))
			board[index] = turn + kind
			var has_reply := _has_legal_move()
			board[index] = previous
			castling = old_rights
			if has_reply:
				return true
	return false


func _evaluate() -> void:
	finished = false
	var check := in_check(turn)
	var side_name := "bianchi" if turn == "w" else "neri"
	var has_move := _has_legal_move()
	if not has_move and not _has_transform_escape():
		finished = true
		if check:
			status = "SCACCO MATTO! Vincono i neri." if turn == "w" else "SCACCO MATTO! Vincono i bianchi."
		else:
			status = "PATTA per stallo."
	elif halfmove_clock >= 100:
		finished = true
		status = "PATTA: regola delle 50 mosse."
	elif int(position_counts.get(_position_key(), 0)) >= 3:
		finished = true
		status = "PATTA: triplice ripetizione."
	elif _insufficient_material():
		finished = true
		status = "PATTA: materiale insufficiente."
	elif not has_move:
		status = "Nessuna mossa disponibile: i %s devono trasformare un pezzo." % side_name
	elif check:
		status = "SCACCO al re dei %s! Tocca ai %s." % [side_name, side_name]
	else:
		status = "Turno dei %s." % side_name


func _state_without_history() -> Dictionary:
	return {
		"board": board.duplicate(), "turn": turn, "castling": castling.duplicate(),
		"en_passant": [en_passant.x, en_passant.y],
		"halfmove_clock": halfmove_clock, "fullmove_number": fullmove_number,
		"position_counts": position_counts.duplicate(true),
		"captured_pieces": captured_pieces.duplicate(true),
		"transformed_this_turn": transformed_this_turn,
		"active_transforms": active_transforms.duplicate(true)
	}


func export_state() -> Dictionary:
	var result := _state_without_history()
	result["history"] = history.duplicate(true)
	return result


func restore_state(data: Dictionary) -> bool:
	var raw_board: Variant = data.get("board")
	if not raw_board is Array or raw_board.size() != 64:
		return false
	var parsed: Array[String] = []
	for code in raw_board:
		if not code is String or (code != "." and code not in [
			"wK", "wQ", "wR", "wB", "wN", "wP", "bK", "bQ", "bR", "bB", "bN", "bP"
		]):
			return false
		parsed.append(code)
	if parsed.count("wK") != 1 or parsed.count("bK") != 1:
		return false
	var next_turn: Variant = data.get("turn")
	var rights: Variant = data.get("castling")
	var ep: Variant = data.get("en_passant")
	if next_turn not in ["w", "b"] or not rights is Dictionary or not ep is Array or ep.size() != 2:
		return false
	if not ep[0] is int or not ep[1] is int:
		return false
	var target := Vector2i(ep[0], ep[1])
	if target != NO_SQUARE and (not inside(target) or target.y not in [2, 5]):
		return false
	var half: int = int(data.get("halfmove_clock", 0))
	var full: int = int(data.get("fullmove_number", 1))
	if half < 0 or full < 1:
		return false
	var reserves: Variant = data.get("captured_pieces", {"w": [], "b": []})
	if not reserves is Dictionary:
		return false
	var parsed_reserves := {"w": [], "b": []}
	for side in ["w", "b"]:
		var entries: Variant = reserves.get(side, [])
		if not entries is Array or entries.size() > 32:
			return false
		for kind in entries:
			if kind not in ["P", "N", "B", "R", "Q"]:
				return false
			parsed_reserves[side].append(kind)
	var used: Variant = data.get("transformed_this_turn", false)
	if not used is bool:
		return false
	var source_transforms: Variant = data.get("active_transforms", {})
	if not source_transforms is Dictionary:
		return false
	var parsed_transforms: Dictionary = {}
	for side in source_transforms:
		if side not in ["w", "b"]:
			return false
		var record: Variant = source_transforms[side]
		if not record is Dictionary:
			return false
		var coordinates: Variant = record.get("square")
		var original: Variant = record.get("original")
		if not coordinates is Array or coordinates.size() != 2 or not coordinates[0] is int or not coordinates[1] is int:
			return false
		if original not in ["P", "N", "B", "R", "Q"]:
			return false
		var at := Vector2i(coordinates[0], coordinates[1])
		if not inside(at) or not parsed[at.y * 8 + at.x].begins_with(side):
			return false
		parsed_transforms[side] = {"square": [at.x, at.y], "original": original}
	# Legacy save directly after a transformation: retrieve the original kind
	# from the last undo snapshot (old saves had no transformation metadata).
	if not data.has("active_transforms") and used and not parsed_transforms.has(next_turn):
		var snapshots: Variant = data.get("history", [])
		if snapshots is Array and not snapshots.is_empty():
			var before: Variant = snapshots.back()
			if before is Dictionary and before.get("board") is Array and before["board"].size() == 64:
				for i in range(64):
					var previous: Variant = before["board"][i]
					if previous is String and previous.begins_with(next_turn) and not previous.ends_with("K") and previous != parsed[i]:
						parsed_transforms[next_turn] = {"square": [i % 8, i / 8], "original": previous.substr(1, 1)}
						break
	board = parsed
	turn = next_turn
	castling = {
		"wK": bool(rights.get("wK", false)), "wQ": bool(rights.get("wQ", false)),
		"bK": bool(rights.get("bK", false)), "bQ": bool(rights.get("bQ", false))
	}
	en_passant = target
	halfmove_clock = half
	fullmove_number = full
	captured_pieces = parsed_reserves
	transformed_this_turn = used
	active_transforms = parsed_transforms
	position_counts = data.get("position_counts", {}).duplicate(true) if data.get("position_counts") is Dictionary else {}
	history.clear()
	var previous: Variant = data.get("history", [])
	if previous is Array and previous.size() <= 512:
		for state in previous:
			if state is Dictionary:
				history.append(state.duplicate(true))
	if position_counts.is_empty():
		_record_position()
	_evaluate()
	return true


func undo() -> bool:
	if history.is_empty():
		return false
	var previous: Dictionary = history.pop_back()
	var remaining: Array[Dictionary] = history.duplicate(true)
	if not restore_state(previous):
		history = remaining
		return false
	history = remaining
	return true


## Deterministic setup for tests and authored puzzle positions.
func set_position(cells: Array[String], active_side: String, rights: Dictionary = {}, target: Vector2i = NO_SQUARE) -> bool:
	var state := {
		"board": cells.duplicate(), "turn": active_side, "castling": rights,
		"en_passant": [target.x, target.y], "halfmove_clock": 0,
		"fullmove_number": 1, "position_counts": {}, "history": []
	}
	return restore_state(state)
