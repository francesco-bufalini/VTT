extends "res://network/board_sync.gd"

# Avoid external peer-discovery processes in this focused scene-loading test.
func _request_tailscale_peer_refresh() -> void:
	pass
