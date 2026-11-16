extends SceneTree

const ChessRules = preload("res://vtt/chess/chess_rules.gd")
const ChessScene = preload("res://vtt/chess/wizard_chess.tscn")


func _initialize() -> void:
	call_deferred("run")


func _empty() -> Array[String]:
	var cells: Array[String] = []
	for i in range(64):
		cells.append(".")
	return cells


func _index(cells: Array[String], file: int, rank: int, piece: String) -> void:
	cells[rank * 8 + file] = piece


func _has(moves: Array[Dictionary], to: Vector2i) -> bool:
	for move in moves:
		if move["to"] == to:
			return true
	return false


func run() -> void:
	var chess = ChessRules.new()
	var legal_total := 0
	for rank in range(8):
		for file in range(8):
			legal_total += chess.legal_moves(Vector2i(file, rank)).size()
	assert(legal_total == 20, "The initial board must offer exactly 20 white moves")
	assert(chess.turn == "w", "White always moves first")
	assert(chess.piece(Vector2i(4, 6)) == "wP")
	assert(chess.piece(Vector2i(4, 1)) == "bP")
	assert(not chess.play(Vector2i(4, 1), Vector2i(4, 3)), "Black cannot move first")
	assert(chess.play(Vector2i(4, 6), Vector2i(4, 4))) # e2-e4
	assert(chess.turn == "b")
	assert(not chess.play(Vector2i(3, 6), Vector2i(3, 4)), "A side cannot move twice")
	assert(chess.play(Vector2i(4, 1), Vector2i(4, 3))) # e7-e5
	assert(chess.turn == "w")
	assert(chess.undo())
	assert(chess.turn == "b" and chess.piece(Vector2i(4, 1)) == "bP")
	assert(chess.undo(), "Undo must keep the full history, not just the last move")
	assert(chess.turn == "w" and chess.piece(Vector2i(4, 6)) == "wP")

	# Wizard pawn dash can prevent the traditional Fool's Mate.
	chess.reset()
	assert(chess.play(Vector2i(5, 6), Vector2i(5, 5))) # f3
	assert(chess.play(Vector2i(4, 1), Vector2i(4, 3))) # ...e5
	assert(chess.play(Vector2i(6, 6), Vector2i(6, 4))) # g4
	assert(chess.play(Vector2i(3, 0), Vector2i(7, 4))) # ...Qh4#
	assert(not chess.finished and chess.in_check("w"))
	assert(_has(chess.power_moves(Vector2i(7, 6)), Vector2i(6, 5)), "The h-pawn can shield its king diagonally")
	assert(chess.play_power(Vector2i(7, 6), Vector2i(6, 5)))
	assert(not chess.in_check("w"), "Pawn dash ends the queen's check")
	assert(chess.undo() and chess.in_check("w"))
	assert(chess.undo() and not chess.in_check("w"))

	# Both castling types and castling-right revocation.
	var cells := _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 0, 7, "wR")
	_index(cells, 7, 7, "wR")
	_index(cells, 4, 0, "bK")
	assert(chess.set_position(cells, "w", {"wK": true, "wQ": true}))
	var king_moves: Array[Dictionary] = chess.legal_moves(Vector2i(4, 7))
	assert(_has(king_moves, Vector2i(6, 7)) and _has(king_moves, Vector2i(2, 7)))
	assert(chess.play(Vector2i(4, 7), Vector2i(6, 7)))
	assert(chess.piece(Vector2i(5, 7)) == "wR")
	assert(chess.piece(Vector2i(7, 7)) == ".")
	assert(not bool(chess.castling["wK"]) and not bool(chess.castling["wQ"]))

	# En passant may be played only immediately after the double pawn step.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 4, 3, "wP") # e5
	_index(cells, 3, 1, "bP") # d7
	assert(chess.set_position(cells, "b"))
	assert(chess.play(Vector2i(3, 1), Vector2i(3, 3)))
	assert(_has(chess.legal_moves(Vector2i(4, 3)), Vector2i(3, 2)))
	assert(chess.play(Vector2i(4, 3), Vector2i(3, 2)))
	assert(chess.piece(Vector2i(3, 3)) == "." and chess.piece(Vector2i(3, 2)) == "wP")
	assert(chess.captured_pieces["b"] == ["P"], "En passant sends the pawn to the owner\u0027s captured pool")

	# Underpromotion must not silently turn into a queen.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 0, 1, "wP")
	assert(chess.set_position(cells, "w"))
	assert(chess.play(Vector2i(0, 1), Vector2i(0, 0), "N"))
	assert(chess.piece(Vector2i(0, 0)) == "wN")

	# Classic stalemate.
	cells = _empty()
	_index(cells, 0, 0, "bK") # a8
	_index(cells, 2, 2, "wK") # c6
	_index(cells, 1, 2, "wQ") # b6
	assert(chess.set_position(cells, "b"))
	assert(chess.finished and "stallo" in chess.status)

	# A captured piece belongs to its original owner, who may restore it once
	# at the start of a later turn, then must play a normal move.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 0, 4, "wR") # a4
	_index(cells, 0, 1, "bN") # a7
	_index(cells, 7, 1, "bP") # h7
	assert(chess.set_position(cells, "w"))
	assert(chess.available_transformations().is_empty())
	assert(not chess.transform(Vector2i(0, 4), "N"), "You cannot invent lost pieces")
	assert(chess.play(Vector2i(0, 4), Vector2i(0, 1))) # Rxa7
	assert(chess.turn == "b" and chess.captured_pieces["b"] == ["N"])
	assert(not chess.transform(Vector2i(4, 0), "N"), "Kings are never transformable")
	assert(not chess.transform(Vector2i(0, 1), "N"), "Enemy pieces cannot be transformed")
	assert(chess.transform(Vector2i(7, 1), "N"), "Replace a friendly pawn with the captured knight")
	assert(chess.turn == "b" and chess.piece(Vector2i(7, 1)) == "bN")
	assert(chess.captured_pieces["b"].is_empty() and chess.transformed_this_turn)
	assert(not chess.transform(Vector2i(7, 1), "N"), "Only one transformation per turn")
	var transformed_snapshot: Dictionary = chess.export_state()
	var reloaded = ChessRules.new()
	assert(reloaded.restore_state(transformed_snapshot))
	assert(reloaded.piece(Vector2i(7, 1)) == "bN" and reloaded.transformed_this_turn)
	assert(reloaded.available_transformations().is_empty())
	assert(chess.play(Vector2i(7, 1), Vector2i(5, 2))) # ...Nf6
	assert(chess.turn == "w" and not chess.transformed_this_turn)
	assert(chess.piece(Vector2i(5, 2)) == "bN")
	assert(chess.active_transforms["b"]["square"] == [5, 2], "Transformation follows the token")
	var moved_snapshot: Dictionary = chess.export_state()
	assert(reloaded.restore_state(moved_snapshot))
	assert(reloaded.active_transforms["b"]["square"] == [5, 2], "Save preserves transformed identity")
	assert(reloaded.play(Vector2i(4, 7), Vector2i(3, 7)), "White completes the next move")
	assert(reloaded.turn == "b" and reloaded.piece(Vector2i(5, 2)) == "bP",
		"At the start of Black's next turn, the knight returns to the original pawn")
	assert(reloaded.active_transforms.is_empty())
	assert(reloaded.undo() and reloaded.piece(Vector2i(5, 2)) == "bN",
		"Undo of the opponent's move restores the temporary form")
	assert(reloaded.active_transforms.has("b"))
	assert(chess.play(Vector2i(4, 7), Vector2i(3, 7)))
	assert(chess.turn == "b" and chess.piece(Vector2i(5, 2)) == "bP")
	assert(chess.active_transforms.is_empty())
	assert(chess.undo() and chess.piece(Vector2i(5, 2)) == "bN")
	assert(chess.turn == "w" and not chess.transformed_this_turn)
	assert(chess.undo() and chess.piece(Vector2i(7, 1)) == "bN")
	assert(chess.turn == "b" and chess.transformed_this_turn)
	assert(chess.undo() and chess.piece(Vector2i(7, 1)) == "bP")
	assert(chess.captured_pieces["b"] == ["N"] and not chess.transformed_this_turn)
	assert(chess.play(Vector2i(7, 1), Vector2i(7, 2)), "You may skip transformation")

	# The transformation remains active during the opponent's move and
	# the opponent can capture it. Recover the *original* captured kind.
	cells = _empty()
	_index(cells, 7, 7, "wK")
	_index(cells, 0, 7, "wR")
	_index(cells, 7, 0, "bK")
	_index(cells, 0, 3, "bP")
	var capture_state: Dictionary = {
		"board": cells.duplicate(), "turn": "b", "castling": {},
		"en_passant": [-1, -1], "captured_pieces": {"w": [], "b": ["Q"]}
	}
	assert(chess.restore_state(capture_state))
	assert(chess.transform(Vector2i(0, 3), "Q"))
	assert(chess.play(Vector2i(0, 3), Vector2i(0, 4))) # ...Qa4
	assert(chess.active_transforms.has("b") and chess.piece(Vector2i(0, 4)) == "bQ")
	assert(chess.play(Vector2i(0, 7), Vector2i(0, 4))) # Rxa4
	assert(not chess.active_transforms.has("b"), "The captured token cannot respawn")
	assert(chess.captured_pieces["b"] == ["P"], "Capture restores original identity in reserves")
	assert(chess.undo())
	assert(chess.piece(Vector2i(0, 4)) == "bQ" and chess.active_transforms.has("b"))

	# Both colors may have their own temporary transformation simultaneously.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 7, 6, "wP")
	_index(cells, 7, 1, "bP")
	var both_state: Dictionary = {
		"board": cells.duplicate(), "turn": "w", "castling": {},
		"en_passant": [-1, -1], "captured_pieces": {"w": ["N"], "b": ["B"]}
	}
	assert(chess.restore_state(both_state))
	assert(chess.transform(Vector2i(7, 6), "N"))
	assert(chess.play(Vector2i(7, 6), Vector2i(5, 5))) # Nf3
	assert(chess.transform(Vector2i(7, 1), "B"))
	assert(chess.play(Vector2i(7, 1), Vector2i(6, 2))) # ...Bg6
	assert(chess.piece(Vector2i(5, 5)) == "wP" and chess.piece(Vector2i(6, 2)) == "bB")
	assert(not chess.active_transforms.has("w") and chess.active_transforms.has("b"))
	assert(chess.play(Vector2i(4, 7), Vector2i(3, 7))) # Kd1
	assert(chess.piece(Vector2i(6, 2)) == "bP" and chess.active_transforms.is_empty())

	# A rook replaced on its starting square loses castling rights permanently.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 7, 7, "wR")
	_index(cells, 4, 0, "bK")
	var rights_state: Dictionary = {
		"board": cells.duplicate(), "turn": "w", "castling": {"wK": true},
		"en_passant": [-1, -1], "captured_pieces": {"w": ["N"], "b": []}
	}
	assert(chess.restore_state(rights_state))
	assert(chess.transform(Vector2i(7, 7), "N"))
	assert(not chess.castling["wK"])
	assert(chess.undo() and chess.castling["wK"])

	# Transformations may allow an escape from what would normally be mate.
	chess.reset()
	assert(chess.play(Vector2i(5, 6), Vector2i(5, 5))) # f3
	assert(chess.play(Vector2i(4, 1), Vector2i(4, 3))) # ...e5
	assert(chess.play(Vector2i(6, 6), Vector2i(6, 4))) # g4
	var mate_state: Dictionary = chess.export_state()
	mate_state["captured_pieces"]["w"] = ["N"]
	assert(chess.restore_state(mate_state))
	assert(chess.play(Vector2i(3, 0), Vector2i(7, 4))) # ...Qh4+
	assert(not chess.finished, "A possible recovery prevents premature checkmate")
	assert(chess.transform(Vector2i(5, 5), "N"))
	assert(chess.play(Vector2i(5, 5), Vector2i(7, 4)), "The recovered knight can capture the checking queen")

	# Material kept in a reserve prevents an automatic insufficient-material draw.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	var kings_state: Dictionary = {
		"board": cells.duplicate(), "turn": "w", "castling": {},
		"en_passant": [-1, -1], "captured_pieces": {"w": ["Q"], "b": []}
	}
	assert(chess.restore_state(kings_state))
	assert(not chess.finished, "Restorable material may still enable a future mate")

	# P: three-square dash is per physical pawn and can be undone.
	chess.reset()
	assert(_has(chess.power_moves(Vector2i(0, 6)), Vector2i(0, 3)))
	assert(chess.play_power(Vector2i(0, 6), Vector2i(0, 3)))
	assert(chess.piece(Vector2i(0, 3)) == "wP")
	var pawn_uid := chess.piece_id(Vector2i(0, 3))
	assert(chess._used(pawn_uid, "dash"))
	assert(chess.play(Vector2i(4, 1), Vector2i(4, 3)))
	assert(chess.power_moves(Vector2i(0, 3)).is_empty(), "A pawn gets one dash per game")
	assert(chess.undo() and chess.undo())
	assert(not chess._used(chess.piece_id(Vector2i(0, 6)), "dash"))
	assert(chess.play_power(Vector2i(0, 6), Vector2i(0, 3)))

	# R: a horizontal magic wall prevents enemy traversal and attacks.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 0, 4, "wR") # a4
	_index(cells, 7, 1, "bR") # h7
	assert(chess.set_position(cells, "w"))
	assert(chess.activate_wall(Vector2i(0, 4), "rank"))
	assert(chess.walls.size() == 1 and chess.wall_at(Vector2i(3, 4)) == ["w"])
	assert(not chess.activate_wall(Vector2i(0, 4), "file"))
	assert(chess.play(Vector2i(4, 7), Vector2i(3, 7)))
	assert(not _has(chess.legal_moves(Vector2i(7, 1)), Vector2i(7, 4)))
	assert(not _has(chess.legal_moves(Vector2i(7, 1)), Vector2i(7, 6)))
	assert(_has(chess.legal_moves(Vector2i(7, 1)), Vector2i(7, 3)))
	assert(chess.undo() and chess.walls.size() == 1)
	assert(chess.undo() and chess.walls.is_empty(), "Wall disappears when action undone")

	# B (light square): resurrect a captured allied token on an adjacent tile.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 5, 7, "wB") # f1: light square
	var revival_state: Dictionary = {
		"board": cells.duplicate(), "turn": "w", "castling": {},
		"en_passant": [-1, -1], "captured_pieces": {"w": ["N"], "b": []}
	}
	assert(chess.restore_state(revival_state))
	assert(chess.can_revive(Vector2i(5, 7)))
	assert(chess.revive(Vector2i(5, 7), Vector2i(4, 6), "N"))
	assert(chess.piece(Vector2i(4, 6)) == "wN" and chess.turn == "w")
	assert(chess.captured_pieces["w"].is_empty())
	assert(not chess.can_revive(Vector2i(5, 7)))
	assert(chess.undo() and chess.piece(Vector2i(4, 6)) == ".")
	assert(chess.captured_pieces["w"] == ["N"])

	# B (dark square): curse an enemy token so it can neither transform nor revive.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 2, 7, "wB") # c1: dark square
	_index(cells, 0, 3, "wR") # a5
	_index(cells, 0, 1, "bP") # a7
	assert(chess.set_position(cells, "w"))
	assert(chess.can_curse(Vector2i(2, 7)))
	assert(chess.curse(Vector2i(2, 7), Vector2i(0, 1)))
	assert(chess.is_cursed(Vector2i(0, 1)) and not chess.can_curse(Vector2i(2, 7)))
	assert(chess.play(Vector2i(0, 3), Vector2i(0, 1))) # Rxa7
	assert(chess.captured_pieces["b"] == ["P"] and chess.available_transformations().is_empty())
	assert(chess.undo() and chess.is_cursed(Vector2i(0, 1)))
	assert(chess.undo() and not chess.is_cursed(Vector2i(0, 1)))

	# N: sweep every enemy on the long-then-short L-shaped path.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 4, 0, "bK")
	_index(cells, 1, 7, "wN") # b1
	_index(cells, 1, 6, "bP") # b2
	_index(cells, 1, 5, "bP") # b3
	_index(cells, 2, 5, "bP") # c3
	assert(chess.set_position(cells, "w"))
	assert(_has(chess.power_moves(Vector2i(1, 7)), Vector2i(2, 5)))
	assert(chess.play_power(Vector2i(1, 7), Vector2i(2, 5)))
	assert(chess.captured_pieces["b"].size() == 3, "Sweep captures all three enemy pawns")
	assert(chess.piece(Vector2i(1, 6)) == "." and chess.piece(Vector2i(1, 5)) == ".")
	assert(chess.piece(Vector2i(2, 5)) == "wN")
	var knight_uid := chess.piece_id(Vector2i(2, 5))
	assert(chess._used(knight_uid, "sweep"))
	assert(chess.undo() and not chess._used(chess.piece_id(Vector2i(1, 7)), "sweep"))

	# Q: coup can be declared on the opponent's turn, transferring the royal role.
	cells = _empty()
	_index(cells, 4, 7, "wK")
	_index(cells, 3, 7, "wQ")
	_index(cells, 7, 0, "bK")
	_index(cells, 4, 5, "bR") # e3, attacking the former white king
	assert(chess.set_position(cells, "b"))
	assert(chess.queen_coup(Vector2i(3, 7)))
	assert(chess.turn == "b" and chess.is_royal(Vector2i(3, 7)))
	assert(not chess.is_royal(Vector2i(4, 7)) and chess.coup_used["w"])
	assert(not chess.queen_coup(Vector2i(3, 7)), "Only one coup per color")
	assert(chess.play(Vector2i(4, 5), Vector2i(4, 7)),
		"The former king is now an ordinary capturable piece")
	assert(chess.captured_pieces["w"] == ["K"] and not chess.finished)
	assert(chess.king_square("w") == Vector2i(3, 7))
	var coup_snapshot: Dictionary = chess.export_state()
	var coup_reload = ChessRules.new()
	assert(coup_reload.restore_state(coup_snapshot))
	assert(coup_reload.king_square("w") == Vector2i(3, 7) and coup_reload.coup_used["w"])
	assert(coup_reload.undo() and coup_reload.piece(Vector2i(4, 7)) == "wK")
	assert(coup_reload.undo() and coup_reload.is_royal(Vector2i(4, 7)))
	assert(not coup_reload.coup_used["w"], "Undo restores the original king")

	# Persistence is per scenario, independent from VTT map snapshots.
	chess.reset()
	assert(chess.play(Vector2i(4, 6), Vector2i(4, 4)))
	var state: Dictionary = chess.export_state()
	var loaded = ChessRules.new()
	assert(loaded.restore_state(state))
	assert(loaded.turn == "b" and loaded.piece(Vector2i(4, 4)) == "wP")

	var scene: Node3D = ChessScene.instantiate()
	root.add_child(scene)
	await process_frame
	assert(scene.get_node("ChessTable") != null)
	assert(scene.get_node("ChessTokens").get_child_count() == 32,
		"The scenario must spawn all 32 generic chess piece tokens")
	# The visible interface exposes captured pieces and transforms the selected token.
	var visual_game = scene.get("game")
	assert(visual_game.restore_state(rights_state))
	scene.call("_refresh")
	var controls: HFlowContainer = scene.get("_transform_buttons")
	assert(controls.get_child_count() == 5, "Transformation buttons remain persistent")
	var buttons: Dictionary = scene.get("_transform_option_buttons")
	var knight_button: Button = buttons["N"]
	assert(knight_button.visible)
	knight_button.pressed.emit() # Exercise the actual signal and refreshing in its callback.
	assert(is_instance_valid(knight_button), "Selecting a transformation must not delete the pressed button")
	assert(buttons["N"] == knight_button and controls.get_child_count() == 5)
	scene.call("_select_cell", Vector2i(7, 7))
	assert(visual_game.piece(Vector2i(7, 7)) == "wN")
	assert(scene.get_node("ChessTokens").get_child_count() == 3,
		"Only the changed piece is replaced: no duplicated visual tokens")
	assert(is_instance_valid(knight_button) and controls.get_child_count() == 5)
	scene.queue_free()
	await process_frame
	print("PASS: wizard chess board, turns, legality, mate, stalemate, castle, en passant, promotion, undo, persistence, temporary transformation, UI safety")
	quit()
