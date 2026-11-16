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

	# Fool's mate: the next move must be disallowed because the game is over.
	chess.reset()
	assert(chess.play(Vector2i(5, 6), Vector2i(5, 5))) # f3
	assert(chess.play(Vector2i(4, 1), Vector2i(4, 3))) # ...e5
	assert(chess.play(Vector2i(6, 6), Vector2i(6, 4))) # g4
	assert(chess.play(Vector2i(3, 0), Vector2i(7, 4))) # ...Qh4#
	assert(chess.finished and "SCACCO MATTO" in chess.status)
	assert(not chess.play(Vector2i(4, 6), Vector2i(4, 5)))
	assert(chess.undo() and not chess.finished)

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
	scene.queue_free()
	await process_frame
	print("PASS: wizard chess board, turns, legality, mate, stalemate, castle, en passant, promotion, undo, persistence")
	quit()
