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
# A stable identity follows each token through moves and captures.
var piece_ids: Array[int] = []
var piece_data: Dictionary = {}
var next_piece_id := 1
var captured_ids := {"w": [], "b": []}
var royal_ids := {"w": 0, "b": 0}
var coup_used := {"w": false, "b": false}
var walls: Array[Dictionary] = []
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
	piece_ids.clear()
	piece_data.clear()
	next_piece_id = 1
	captured_ids = {"w": [], "b": []}
	coup_used = {"w": false, "b": false}
	walls.clear()
	for i in range(board.size()):
		piece_ids.append(0)
		if board[i] != ".":
			var uid := _new_piece(board[i])
			piece_ids[i] = uid
			if board[i].ends_with("K"):
				royal_ids[board[i].substr(0, 1)] = uid
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


func _new_piece(code: String) -> int:
	var uid := next_piece_id
	next_piece_id += 1
	piece_data[str(uid)] = {"side": code.substr(0, 1), "used": [], "cursed": false}
	return uid


func piece_id(pos: Vector2i) -> int:
	return piece_ids[pos.y * 8 + pos.x] if inside(pos) else 0


func _data(uid: int) -> Dictionary:
	return piece_data.get(str(uid), {})


func _used(uid: int, power: String) -> bool:
	return power in _data(uid).get("used", [])


func _spend(uid: int, power: String) -> void:
	var info: Dictionary = _data(uid)
	var used: Array = info.get("used", [])
	if power not in used:
		used.append(power)
	info["used"] = used
	piece_data[str(uid)] = info


func is_cursed(pos: Vector2i) -> bool:
	return bool(_data(piece_id(pos)).get("cursed", false))


func is_royal(pos: Vector2i) -> bool:
	var code := piece(pos)
	return code != "." and piece_id(pos) == int(royal_ids.get(code.substr(0, 1), 0))


func _royal_square(side: String) -> Vector2i:
	var index := piece_ids.find(int(royal_ids.get(side, 0)))
	return Vector2i(index % 8, index / 8) if index != -1 else NO_SQUARE


func king_square(side: String) -> Vector2i:
	return _royal_square(side)


static func _find_king(cells: Array[String], side: String) -> Vector2i:
	var index := cells.find(side + "K")
	if index == -1:
		return NO_SQUARE
	return Vector2i(index % 8, index / 8)


static func _wall_blocks(lines: Array[Dictionary], side: String, from: Vector2i, to: Vector2i) -> bool:
	for wall in lines:
		if wall["owner"] == side:
			continue
		var index: int = wall["index"]
		var a: int = from.y if wall["axis"] == "rank" else from.x
		var b: int = to.y if wall["axis"] == "rank" else to.x
		if b == index or (a < index and b > index) or (a > index and b < index):
			return true
	return false


func wall_at(cell: Vector2i) -> Array[String]:
	var owners: Array[String] = []
	for wall in walls:
		if (wall["axis"] == "rank" and cell.y == wall["index"]) or (wall["axis"] == "file" and cell.x == wall["index"]):
			owners.append(String(wall["owner"]))
	return owners


static func _is_attacked(cells: Array[String], target: Vector2i, attacker: String, barriers: Array[Dictionary] = []) -> bool:
	# Pawns attack diagonally regardless of occupancy of their forward square.
	var forward := -1 if attacker == "w" else 1
	for dx in [-1, 1]:
		var source := target - Vector2i(dx, forward)
		if _at(cells, source) == attacker + "P" and not _wall_blocks(barriers, attacker, source, target):
			return true
	for delta in KNIGHT_JUMPS:
		if _at(cells, target + delta) == attacker + "N" and not _wall_blocks(barriers, attacker, target + delta, target):
			return true
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if (dx != 0 or dy != 0) and _at(cells, target + Vector2i(dx, dy)) == attacker + "K" and not _wall_blocks(barriers, attacker, target + Vector2i(dx, dy), target):
				return true
	for delta in STRAIGHTS + DIAGONALS:
		var pos: Vector2i = target + delta
		while inside(pos):
			if _wall_blocks(barriers, attacker, pos, target):
				break
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
	var king := king_square(side)
	return king != NO_SQUARE and _is_attacked(board, king, opposite(side), walls)


func _add_target(options: Array[Dictionary], from: Vector2i, to: Vector2i, extra: Dictionary = {}) -> void:
	if not inside(to):
		return
	var origin := piece(from)
	var destination := piece(to)
	if destination.begins_with(origin.substr(0, 1)) or is_royal(to) or _wall_blocks(walls, origin.substr(0, 1), from, to):
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
					if _wall_blocks(walls, side, from, to):
						break
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
			if from == Vector2i(4, rank) and is_royal(from) and not bool(coup_used[side]) and not _is_attacked(board, from, enemy, walls):
				if bool(castling.get(side + "K", false)) and piece(Vector2i(7, rank)) == side + "R":
					if piece(Vector2i(5, rank)) == "." and piece(Vector2i(6, rank)) == ".":
						if not _is_attacked(board, Vector2i(5, rank), enemy, walls) and not _is_attacked(board, Vector2i(6, rank), enemy, walls) and not _wall_blocks(walls, side, from, Vector2i(6, rank)) and not _wall_blocks(walls, side, Vector2i(7, rank), Vector2i(5, rank)):
							options.append({"to": Vector2i(6, rank), "castle": "K"})
				if bool(castling.get(side + "Q", false)) and piece(Vector2i(0, rank)) == side + "R":
					if piece(Vector2i(1, rank)) == "." and piece(Vector2i(2, rank)) == "." and piece(Vector2i(3, rank)) == ".":
						if not _is_attacked(board, Vector2i(3, rank), enemy, walls) and not _is_attacked(board, Vector2i(2, rank), enemy, walls) and not _wall_blocks(walls, side, from, Vector2i(2, rank)) and not _wall_blocks(walls, side, Vector2i(0, rank), Vector2i(3, rank)):
							options.append({"to": Vector2i(2, rank), "castle": "Q"})
	return options


static func _apply_to(cells: Array[String], from: Vector2i, move: Dictionary, promotion: String = "Q") -> void:
	var to: Vector2i = move["to"]
	var moving := _at(cells, from)
	_put(cells, from, ".")
	if bool(move.get("en_passant", false)):
		_put(cells, Vector2i(to.x, from.y), ".")
	for at in move.get("sweep", []):
		_put(cells, at, ".")
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
		var king := to if piece_id(from) == int(royal_ids[turn]) else king_square(turn)
		if king != NO_SQUARE and not _is_attacked(hypothetical, king, opposite(turn), walls):
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
	for i in range(captured_pieces[turn].size()):
		var kind: String = captured_pieces[turn][i]
		var uid: int = captured_ids[turn][i]
		if kind not in available and not bool(_data(uid).get("cursed", false)):
			available.append(kind)
	return available


func transform(at: Vector2i, kind: String) -> bool:
	if finished or transformed_this_turn or active_transforms.has(turn) or not inside(at) or kind not in available_transformations():
		return false
	var previous := piece(at)
	if not previous.begins_with(turn) or is_royal(at) or is_cursed(at):
		return false
	var reserve_index := -1
	for i in range(captured_pieces[turn].size()):
		if captured_pieces[turn][i] == kind and not bool(_data(captured_ids[turn][i]).get("cursed", false)):
			reserve_index = i
			break
	if reserve_index == -1:
		return false
	history.append(_state_without_history())
	captured_pieces[turn].remove_at(reserve_index)
	captured_ids[turn].remove_at(reserve_index)
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


## Powers that replace an ordinary move: Pawn's rush and Knight's sweep.
func power_moves(from: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if finished or not inside(from) or not piece(from).begins_with(turn):
		return result
	var uid := piece_id(from)
	var kind := piece(from).substr(1, 1)
	if kind == "P" and not _used(uid, "dash"):
		var forward := -1 if turn == "w" else 1
		for steps in range(1, 4):
			var to := from + Vector2i(0, forward * steps)
			if not inside(to) or piece(to) != "." or _wall_blocks(walls, turn, from, to):
				break
			var entry: Dictionary = {"to": to, "power": "dash"}
			if to.y == (0 if turn == "w" else 7):
				entry["promotion"] = true
			result.append(entry)
		for dx in [-1, 1]:
			var diag := from + Vector2i(dx, forward)
			if inside(diag) and not piece(diag).begins_with(turn) and not is_royal(diag) and not _wall_blocks(walls, turn, from, diag):
				var entry: Dictionary = {"to": diag, "power": "dash"}
				if diag.y == (0 if turn == "w" else 7):
					entry["promotion"] = true
				result.append(entry)
	elif kind == "N" and not _used(uid, "sweep"):
		for offset in KNIGHT_JUMPS:
			var to := from + offset
			if not inside(to):
				continue
			# Follow the long leg first, then the short leg (three squares total).
			var long_step := Vector2i(signi(offset.x), 0) if absi(offset.x) == 2 else Vector2i(0, signi(offset.y))
			var short_step := Vector2i(0, signi(offset.y)) if absi(offset.x) == 2 else Vector2i(signi(offset.x), 0)
			var p1 := from + long_step
			var p2 := p1 + long_step
			var route: Array[Vector2i] = [p1, p2, p2 + short_step]
			var valid := true
			var previous := from
			for at in route:
				if not inside(at) or piece(at).begins_with(turn) or is_royal(at) or _wall_blocks(walls, turn, previous, at):
					valid = false
					break
				previous = at
			if valid:
				result.append({"to": to, "power": "sweep", "sweep": [p1, p2]})
	var safe: Array[Dictionary] = []
	for move in result:
		var hypothetical: Array[String] = board.duplicate()
		_apply_to(hypothetical, from, move)
		var king := move["to"] if uid == int(royal_ids[turn]) else king_square(turn)
		if king != NO_SQUARE and not _is_attacked(hypothetical, king, opposite(turn), walls):
			safe.append(move)
	return safe


func _capture_at(at: Vector2i, victim_side: String) -> void:
	if piece(at) == ".":
		return
	var uid := piece_id(at)
	if uid == int(royal_ids[victim_side]):
		return
	var kind := piece(at).substr(1, 1)
	if active_transforms.has(victim_side):
		var record: Dictionary = active_transforms[victim_side]
		if _transform_square(record) == at:
			kind = String(record["original"])
			active_transforms.erase(victim_side)
	captured_pieces[victim_side].append(kind)
	captured_ids[victim_side].append(uid)
	_revoke_corner(at)
	piece_ids[at.y * 8 + at.x] = 0


func _commit_move(from: Vector2i, chosen: Dictionary, promotion: String) -> bool:
	var to: Vector2i = chosen["to"]
	var moving := piece(from)
	var moving_side := turn
	var uid := piece_id(from)
	history.append(_state_without_history())
	var victim_side := opposite(moving_side)
	var victims: Array[Vector2i] = []
	if bool(chosen.get("en_passant", false)):
		victims.append(Vector2i(to.x, from.y))
	elif piece(to) != ".":
		victims.append(to)
	for at in chosen.get("sweep", []):
		if piece(at) != "." and at not in victims:
			victims.append(at)
	for at in victims:
		_capture_at(at, victim_side)
	_apply_to(board, from, chosen, promotion)
	piece_ids[from.y * 8 + from.x] = 0
	piece_ids[to.y * 8 + to.x] = uid
	if chosen.has("castle"):
		var rook_from := Vector2i(7, from.y) if chosen["castle"] == "K" else Vector2i(0, from.y)
		var rook_to := Vector2i(5, from.y) if chosen["castle"] == "K" else Vector2i(3, from.y)
		piece_ids[rook_to.y * 8 + rook_to.x] = piece_id(rook_from)
		piece_ids[rook_from.y * 8 + rook_from.x] = 0
	if active_transforms.has(moving_side):
		var record: Dictionary = active_transforms[moving_side]
		if _transform_square(record) == from:
			record["square"] = [to.x, to.y]
			active_transforms[moving_side] = record
	if moving.ends_with("K") and uid == int(royal_ids[moving_side]):
		castling[moving_side + "K"] = false
		castling[moving_side + "Q"] = false
	if moving.ends_with("R"):
		_revoke_corner(from)
	if bool(chosen.get("promotion", false)):
		var info: Dictionary = _data(uid)
		info["promoted"] = promotion
		piece_data[str(uid)] = info
	if chosen.has("power"):
		_spend(uid, String(chosen["power"]))
	en_passant = NO_SQUARE
	if moving.ends_with("P") and absi(to.y - from.y) == 2 and not chosen.has("power"):
		en_passant = Vector2i(from.x, (from.y + to.y) / 2)
	halfmove_clock = 0 if moving.ends_with("P") or not victims.is_empty() else halfmove_clock + 1
	if moving_side == "b":
		fullmove_number += 1
	turn = opposite(turn)
	transformed_this_turn = false
	_revert_transformation(turn)
	_record_position()
	_evaluate()
	return true


func play(from: Vector2i, to: Vector2i, promotion: String = "Q") -> bool:
	if finished or promotion not in ["Q", "R", "B", "N"]:
		return false
	for candidate in legal_moves(from):
		if candidate["to"] == to:
			return _commit_move(from, candidate, promotion)
	return false


func play_power(from: Vector2i, to: Vector2i, promotion: String = "Q") -> bool:
	if finished or promotion not in ["Q", "R", "B", "N"]:
		return false
	for candidate in power_moves(from):
		if candidate["to"] == to:
			return _commit_move(from, candidate, promotion)
	return false


## Free powers may be activated before the ordinary move on the owner's turn.
func activate_wall(from: Vector2i, axis: String) -> bool:
	if finished or axis not in ["rank", "file"] or not inside(from) or piece(from) != turn + "R":
		return false
	var uid := piece_id(from)
	if _used(uid, "wall"):
		return false
	history.append(_state_without_history())
	_spend(uid, "wall")
	walls.append({"owner": turn, "axis": axis, "index": from.y if axis == "rank" else from.x})
	_record_position()
	_evaluate()
	return true


func can_revive(from: Vector2i) -> bool:
	return not finished and inside(from) and piece(from) == turn + "B" and (from.x + from.y) % 2 == 0 and not _used(piece_id(from), "revive")


func available_revivals(from: Vector2i) -> Array[String]:
	var result: Array[String] = []
	if not can_revive(from):
		return result
	for i in range(captured_pieces[turn].size()):
		var kind: String = captured_pieces[turn][i]
		if kind not in result and not bool(_data(captured_ids[turn][i]).get("cursed", false)):
			result.append(kind)
	return result


func revive(from: Vector2i, to: Vector2i, kind: String) -> bool:
	if kind not in available_revivals(from) or not inside(to) or piece(to) != "." or maxi(absi(to.x - from.x), absi(to.y - from.y)) != 1:
		return false
	if _wall_blocks(walls, turn, from, to):
		return false
	var reserve_index := -1
	for i in range(captured_pieces[turn].size()):
		if captured_pieces[turn][i] == kind and not bool(_data(captured_ids[turn][i]).get("cursed", false)):
			reserve_index = i
			break
	if reserve_index == -1:
		return false
	var trial: Array[String] = board.duplicate()
	_put(trial, to, turn + kind)
	if _is_attacked(trial, king_square(turn), opposite(turn), walls):
		return false
	history.append(_state_without_history())
	var uid: int = captured_ids[turn][reserve_index]
	captured_ids[turn].remove_at(reserve_index)
	captured_pieces[turn].remove_at(reserve_index)
	_put(board, to, turn + kind)
	piece_ids[to.y * 8 + to.x] = uid
	_spend(piece_id(from), "revive")
	halfmove_clock = 0
	_record_position()
	_evaluate()
	return true


func can_curse(from: Vector2i) -> bool:
	return not finished and inside(from) and piece(from) == turn + "B" and (from.x + from.y) % 2 == 1 and not _used(piece_id(from), "curse")


func curse(from: Vector2i, target: Vector2i) -> bool:
	if not can_curse(from) or not inside(target) or not piece(target).begins_with(opposite(turn)) or is_royal(target):
		return false
	history.append(_state_without_history())
	var uid := piece_id(target)
	var info: Dictionary = _data(uid)
	info["cursed"] = true
	piece_data[str(uid)] = info
	_spend(piece_id(from), "curse")
	_record_position()
	_evaluate()
	return true


## The queen takes the crown without spending the ordinary move, even if
## activated while the opponent is to move. Only one coup per color.
func queen_coup(at: Vector2i) -> bool:
	if finished or not inside(at) or not piece(at).ends_with("Q"):
		return false
	var side := piece(at).substr(0, 1)
	if bool(coup_used[side]) or piece_id(at) == int(royal_ids[side]):
		return false
	if active_transforms.has(side) and _transform_square(active_transforms[side]) == at:
		return false
	history.append(_state_without_history())
	royal_ids[side] = piece_id(at)
	coup_used[side] = true
	castling[side + "K"] = false
	castling[side + "Q"] = false
	_record_position()
	_evaluate()
	return true

func _position_key() -> String:
	return JSON.stringify(board) + ":" + turn + ":" + JSON.stringify(castling) + ":" + str(en_passant) + ":" + JSON.stringify(captured_ids) + ":" + JSON.stringify(royal_ids) + ":" + JSON.stringify(walls) + ":" + JSON.stringify(piece_data) + ":" + str(transformed_this_turn) + ":" + JSON.stringify(active_transforms)


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
		if not previous.begins_with(turn) or piece_ids[index] == int(royal_ids[turn]) or bool(_data(piece_ids[index]).get("cursed", false)):
			continue
		for kind in available_transformations():
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
		"active_transforms": active_transforms.duplicate(true),
		"piece_ids": piece_ids.duplicate(), "piece_data": piece_data.duplicate(true),
		"next_piece_id": next_piece_id, "captured_ids": captured_ids.duplicate(true),
		"royal_ids": royal_ids.duplicate(), "coup_used": coup_used.duplicate(),
		"walls": walls.duplicate(true)
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
	if not data.has("royal_ids") and (parsed.count("wK") != 1 or parsed.count("bK") != 1):
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
			if kind not in ["P", "N", "B", "R", "Q", "K"]:
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
	var raw_ids: Variant = data.get("piece_ids", [])
	var raw_info: Variant = data.get("piece_data", {})
	var raw_captured: Variant = data.get("captured_ids", {})
	var raw_royals: Variant = data.get("royal_ids", {})
	if not raw_ids is Array or not raw_info is Dictionary:
		return false
	var parsed_ids: Array[int] = []
	var parsed_info: Dictionary = {}
	var parsed_captured := {"w": [], "b": []}
	var parsed_royals := {"w": 0, "b": 0}
	var id_next := 1
	if raw_ids.size() == 64 and raw_royals is Dictionary and raw_captured is Dictionary:
		for uid in raw_ids:
			if not uid is int or uid < 0:
				return false
			parsed_ids.append(uid)
		parsed_info = raw_info.duplicate(true)
		for side in ["w", "b"]:
			var raw_pool: Variant = raw_captured.get(side, [])
			if not raw_pool is Array or raw_pool.size() != parsed_reserves[side].size():
				return false
			parsed_captured[side] = raw_pool.duplicate()
			parsed_royals[side] = int(raw_royals.get(side, 0))
		id_next = int(data.get("next_piece_id", 1))
		for i in range(64):
			if parsed[i] == "." and parsed_ids[i] != 0:
				return false
			if parsed[i] != "." and (parsed_ids[i] == 0 or not parsed_info.has(str(parsed_ids[i]))):
				return false
		for side in ["w", "b"]:
			if parsed_ids.find(parsed_royals[side]) < 0:
				return false
	else:
		# Saves from before piece powers receive stable identities on import.
		for i in range(64):
			parsed_ids.append(0)
			if parsed[i] != ".":
				parsed_ids[i] = id_next
				parsed_info[str(id_next)] = {"side": parsed[i].substr(0, 1), "used": [], "cursed": false}
				if parsed[i].ends_with("K"):
					parsed_royals[parsed[i].substr(0, 1)] = id_next
				id_next += 1
		for side in ["w", "b"]:
			for kind in parsed_reserves[side]:
				parsed_info[str(id_next)] = {"side": side, "used": [], "cursed": false}
				parsed_captured[side].append(id_next)
				id_next += 1
	if id_next < 1:
		return false
	var raw_walls: Variant = data.get("walls", [])
	var raw_coup: Variant = data.get("coup_used", {})
	if not raw_walls is Array or not raw_coup is Dictionary:
		return false
	for line in raw_walls:
		if not line is Dictionary or line.get("owner") not in ["w", "b"] or line.get("axis") not in ["rank", "file"] or not line.get("index") is int or int(line["index"]) not in range(8):
			return false
	board = parsed
	piece_ids = parsed_ids
	piece_data = parsed_info
	next_piece_id = id_next
	captured_ids = parsed_captured
	royal_ids = parsed_royals
	coup_used = {"w": bool(raw_coup.get("w", false)), "b": bool(raw_coup.get("b", false))}
	walls.clear()
	for line in raw_walls:
		walls.append(line.duplicate(true))
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
