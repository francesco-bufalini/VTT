extends Node

signal status_changed(message: String)
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const CreaturePresence = preload("res://network/creature_presence.gd")
const PORT := 45454
const SNAPSHOT_VERSION := 6
const MAGIC := "DND_MAP_SYNC_V6"
const LOCAL_SAVE_MAGIC := "DND_MAP_LOCAL_V1"
const BACKUP_DIR := "user://map_sync_backups"
const MAX_BACKUPS := 20
const MAX_BYTES := 4 * 1024 * 1024
const BULK_SEND_TIMEOUT_MS := 3000
const TAILSCALE_PEER_REFRESH_MS := 15000
const AUTO_SYNC_POLL_MS := 150
const AUTO_SYNC_DEBOUNCE_MS := 280
const AUTO_SYNC_REMOTE_SUPPRESS_MS := 900
const AUTO_SYNC_RETRY_MS := 2000
const GROUPS := ["dnd_token", "tactical_platform", "encounter_obstacle"]
const TOKEN_CONDITIONS := [
	"blinded", "charmed", "deafened", "exhaustion", "frightened",
	"grappled", "incapacitated", "invisible", "paralyzed", "petrified",
	"poisoned", "prone", "restrained", "stunned", "unconscious",
	"concentrating", "surprised", "hidden", "dead"
]
const SYNC_APPEARANCE_META := "board_sync_authoritative_appearance"
const SYNC_APPEARANCE_REVISION_META := "board_sync_appearance_revision"
const SYNC_APPEARANCE_KEYS := [
	"token_pack_id",
	"footprint",
	"size_name",
	"color",
	"height_cells",
	"reach_feet",
	"visual_asset",
	"visual_native_footprint",
	"visual_front_quarter_turns",
	"transformation_history"
]
const MobileMapCapture = preload("res://network/mobile_map_capture.gd")
var _mobile_capture_busy := false
var _mobile_views: Dictionary = {}
const MapDataController = preload("res://vtt/map_data_controller.gd")
var map_data_controller: MapDataController
var board_root: Node
var token_scene: PackedScene
var tokens_root: Node
var measurement_tool: Node
var server := TCPServer.new()
var port: int = PORT
var connections: Array = []
var receiving := false
var session_key := ""
var _tailscale_last_error := ""
var _tailscale_peer_cache: Array[String] = []
var _tailscale_peer_cache_updated_msec := 0
var _tailscale_peer_refresh_thread: Thread = null
var _lan_presence: Node = null
var _bulk_generation := 0
var _bulk_pending := 0
var _bulk_total := 0
var _bulk_accepted := 0
var _bulk_rejected := 0
var _bulk_failed := 0
var _pending_token_pack_ids: Array[String] = []
var _active_token_pack_id := ""
var auto_sync_enabled := true
var _auto_sync_initialized := false
var _auto_sync_last_signature := ""
var _auto_sync_candidate_signature := ""
var _auto_sync_candidate_since_msec := 0
var _auto_sync_last_poll_msec := 0
var _auto_sync_suppress_until_msec := 0
var _auto_sync_retry_after_msec := 0
var _applying_received_snapshot := false

func setup(root: Node, scene: PackedScene, tokens: Node, measure: Node) -> void:
	board_root = root
	token_scene = scene
	tokens_root = tokens
	measurement_tool = measure
	map_data_controller = MapDataController.new()
	map_data_controller.name = "MapDataController"
	add_child(map_data_controller)
	map_data_controller.use_board(get_tactical_map_data)
	map_data_controller.set_action_provider(_handle_mobile_action)
	_connect_token_pack_manager()
	_request_tailscale_peer_refresh()


func _connect_token_pack_manager() -> void:
	if TokenPackManager == null:
		return
	var catalog_callback := Callable(self, "_on_token_pack_catalog_updated")
	if not TokenPackManager.catalog_updated.is_connected(catalog_callback):
		TokenPackManager.catalog_updated.connect(catalog_callback)
	var downloaded_callback := Callable(self, "_on_token_pack_downloaded")
	if not TokenPackManager.token_downloaded.is_connected(downloaded_callback):
		TokenPackManager.token_downloaded.connect(downloaded_callback)
	var download_failed_callback := Callable(self, "_on_token_pack_download_failed")
	if not TokenPackManager.token_download_failed.is_connected(download_failed_callback):
		TokenPackManager.token_download_failed.connect(download_failed_callback)
	var mounted_callback := Callable(self, "_on_token_pack_mounted")
	if not TokenPackManager.token_mounted.is_connected(mounted_callback):
		TokenPackManager.token_mounted.connect(mounted_callback)
	var mount_failed_callback := Callable(self, "_on_token_pack_mount_failed")
	if not TokenPackManager.token_mount_failed.is_connected(mount_failed_callback):
		TokenPackManager.token_mount_failed.connect(mount_failed_callback)


func set_auto_sync_enabled(enabled: bool) -> void:
	if auto_sync_enabled == enabled:
		return
	auto_sync_enabled = enabled
	_auto_sync_initialized = false
	_auto_sync_candidate_signature = ""
	_auto_sync_candidate_since_msec = 0
	_auto_sync_retry_after_msec = 0
	if enabled:
		status_changed.emit("Sincronizzazione automatica attiva")
	else:
		status_changed.emit("Sincronizzazione automatica disattivata")


func is_auto_sync_enabled() -> bool:
	return auto_sync_enabled


func sync_local_change_now() -> Error:
	if not auto_sync_enabled or _applying_received_snapshot:
		return OK
	if session_key.is_empty():
		return ERR_INVALID_PARAMETER

	var snapshot := create_snapshot()
	if snapshot.is_empty():
		return ERR_BUSY
	var signature := _snapshot_signature(snapshot)

	# Unlike the polling path, an explicit UI mutation must never become the
	# initial baseline without being sent. This is important when a token is
	# edited immediately after a scene/session starts.
	var error := send_snapshot_to_tailnet(session_key)
	if error == OK:
		_auto_sync_initialized = true
		_auto_sync_last_signature = signature
		_auto_sync_candidate_signature = ""
		_auto_sync_candidate_since_msec = 0
		_auto_sync_retry_after_msec = 0
	else:
		# Keep the state dirty so the normal debounced poll retries it.
		_auto_sync_initialized = true
		_auto_sync_candidate_signature = signature
		_auto_sync_candidate_since_msec = Time.get_ticks_msec()
		_auto_sync_retry_after_msec = (
			_auto_sync_candidate_since_msec + AUTO_SYNC_RETRY_MS
		)
	return error


func broadcast_sync_event(sync_event: Dictionary) -> Error:
	if not auto_sync_enabled or sync_event.is_empty():
		return OK
	if session_key.is_empty():
		return ERR_INVALID_PARAMETER
	var error := send_snapshot_to_tailnet(session_key, sync_event)
	if error == OK:
		var snapshot := create_snapshot()
		if not snapshot.is_empty():
			_auto_sync_initialized = true
			_auto_sync_last_signature = _snapshot_signature(snapshot)
			_auto_sync_candidate_signature = ""
			_auto_sync_candidate_since_msec = 0
	return error


func _poll_auto_sync() -> void:
	if (
		not auto_sync_enabled
		or _applying_received_snapshot
		or board_root == null
		or not is_instance_valid(board_root)
		or session_key.is_empty()
	):
		return
	var now := Time.get_ticks_msec()
	if now < _auto_sync_suppress_until_msec:
		return
	if now < _auto_sync_retry_after_msec:
		return
	if now - _auto_sync_last_poll_msec < AUTO_SYNC_POLL_MS:
		return
	_auto_sync_last_poll_msec = now

	var snapshot := create_snapshot()
	if snapshot.is_empty():
		return
	var signature := _snapshot_signature(snapshot)
	if not _auto_sync_initialized:
		_auto_sync_initialized = true
		_auto_sync_last_signature = signature
		_auto_sync_candidate_signature = ""
		return
	if signature == _auto_sync_last_signature:
		_auto_sync_candidate_signature = ""
		_auto_sync_candidate_since_msec = 0
		return
	if signature != _auto_sync_candidate_signature:
		_auto_sync_candidate_signature = signature
		_auto_sync_candidate_since_msec = now
		return
	if now - _auto_sync_candidate_since_msec < AUTO_SYNC_DEBOUNCE_MS:
		return

	var error := send_snapshot_to_tailnet(session_key, {}, true)
	if error == OK:
		_auto_sync_last_signature = signature
		_auto_sync_candidate_signature = ""
		_auto_sync_candidate_since_msec = 0
		_auto_sync_retry_after_msec = 0
	else:
		# Keep the candidate dirty so a transient missing peer/cache does not
		# silently consume the change. Peer discovery refreshes asynchronously.
		_auto_sync_candidate_since_msec = now
		_auto_sync_retry_after_msec = now + AUTO_SYNC_RETRY_MS


func _snapshot_signature(snapshot: Dictionary) -> String:
	var comparable := snapshot.duplicate(true)
	# Snapshot V6 creati da versioni precedenti possono ancora contenere
	# "camera". Ignorala nella firma: camera/vista sono sempre locali.
	comparable.erase("camera")
	return JSON.stringify(comparable).sha256_text()


func _accept_received_snapshot(snapshot: Dictionary) -> void:
	_auto_sync_initialized = true
	var local_snapshot := create_snapshot()
	_auto_sync_last_signature = _snapshot_signature(
		local_snapshot if not local_snapshot.is_empty() else snapshot
	)
	_auto_sync_candidate_signature = ""
	_auto_sync_candidate_since_msec = 0
	_auto_sync_suppress_until_msec = (
		Time.get_ticks_msec() + AUTO_SYNC_REMOTE_SUPPRESS_MS
	)


func _replay_sync_event(sync_event: Dictionary) -> void:
	if (
		board_root != null
		and is_instance_valid(board_root)
		and board_root.has_method("replay_sync_event")
	):
		board_root.call("replay_sync_event", sync_event)


func _camera_state() -> Dictionary:
	if board_root == null or not is_instance_valid(board_root):
		return {}
	var camera := board_root.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return {}
	return _transform(camera.global_transform)


func _apply_camera_state(value: Variant) -> void:
	if not _valid_transform_payload(value):
		return
	var camera := board_root.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	if camera.has_method("is_first_person") and bool(camera.call("is_first_person")):
		if camera.has_method("exit_first_person"):
			camera.call("exit_first_person")
	camera.global_transform = _dict_transform(value)


func _valid_transform_payload(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var transform: Dictionary = value as Dictionary
	var basis_value: Variant = transform.get("basis", [])
	if not basis_value is Array or (basis_value as Array).size() != 3:
		return false
	var vectors: Array = (basis_value as Array).duplicate()
	vectors.append(transform.get("origin"))
	for vector_value: Variant in vectors:
		if not vector_value is Dictionary:
			return false
		var vector: Dictionary = vector_value as Dictionary
		for axis: String in ["x", "y", "z"]:
			var component: Variant = vector.get(axis)
			if (
				not (component is float or component is int)
				or not is_finite(float(component))
				or absf(float(component)) > 100000.0
			):
				return false
	return absf(_dict_transform(transform).basis.determinant()) >= 0.000001


func _initiative_tracker() -> Node:
	if board_root == null or not is_instance_valid(board_root):
		return null
	var property_value: Variant = board_root.get("initiative_tracker")
	if property_value is Node and is_instance_valid(property_value):
		return property_value as Node
	return board_root.get_node_or_null("InitiativeTracker")

func listen(enabled: bool, key: String) -> Error:
	server.stop()
	receiving = false
	for item in connections:
		item.peer.disconnect_from_host()
	connections.clear()
	session_key = key.strip_edges()
	if map_data_controller != null:
		map_data_controller.serve(false, session_key)
	if not enabled:
		status_changed.emit("Ricezione disattivata")
		return OK
	if session_key.is_empty():
		status_changed.emit("Inserisci un codice sessione condiviso")
		return ERR_INVALID_PARAMETER
	var error := server.listen(port)
	receiving = error == OK
	var tactical_message := ""
	if map_data_controller != null and receiving:
		var tactical_error := map_data_controller.serve(true, session_key)
		if tactical_error != OK:
			tactical_message = " · Schede mobile: " + error_string(tactical_error)
	status_changed.emit(("In ascolto sulla porta TCP %d" % port if receiving else error_string(error)) + tactical_message)
	return error

func send_snapshot(host: String, key: String) -> Error:
	if host.strip_edges().is_empty() or key.strip_edges().is_empty():
		status_changed.emit("Inserisci indirizzo e codice sessione")
		return ERR_INVALID_PARAMETER
	var payload: PackedByteArray = _snapshot_payload(key)
	if payload.is_empty():
		return ERR_BUSY
	var error: Error = _queue_snapshot_payload(
		host.strip_edges(),
		payload,
		30000,
		false
	)
	if error == OK:
		status_changed.emit("Connessione e invio in corsoâ€¦")
	else:
		status_changed.emit(error_string(error))
	return error


func send_snapshot_to_tailnet(
	key: String,
	sync_event: Dictionary = {},
	use_cached_peers: bool = false
) -> Error:
	var clean_key: String = key.strip_edges()
	if clean_key.is_empty():
		status_changed.emit("Numero partita non valido")
		return ERR_INVALID_PARAMETER

	var payload: PackedByteArray = _snapshot_payload(clean_key, sync_event)
	if payload.is_empty():
		return ERR_BUSY

	var hosts: Array[String] = _collect_sync_peer_ipv4s(use_cached_peers)
	if hosts.is_empty():
		status_changed.emit("Nessun altro VTT trovato nella partita (LAN o Tailscale)")
		return ERR_DOES_NOT_EXIST

	_bulk_generation += 1
	_bulk_total = hosts.size()
	_bulk_pending = 0
	_bulk_accepted = 0
	_bulk_rejected = 0
	_bulk_failed = 0

	for host: String in hosts:
		var error: Error = _queue_snapshot_payload(
			host,
			payload,
			BULK_SEND_TIMEOUT_MS,
			true,
			_bulk_generation
		)
		if error == OK:
			_bulk_pending += 1
		else:
			_bulk_failed += 1

	if _bulk_pending == 0:
		status_changed.emit(
			"Trovati %d dispositivi, ma nessuna connessione è partita"
			% _bulk_total
		)
		return ERR_CANT_CONNECT

	status_changed.emit(
		"Trovati %d dispositivi · invio in corso…" % _bulk_total
	)
	return OK


func _snapshot_payload(
	key: String,
	sync_event: Dictionary = {}
) -> PackedByteArray:
	var snapshot: Dictionary = create_snapshot()
	if snapshot.is_empty():
		status_changed.emit("Attendi la fine dell'avanzamento")
		return PackedByteArray()

	var message := {
		"magic": MAGIC,
		"key": key.strip_edges(),
		"snapshot": snapshot
	}
	if not sync_event.is_empty():
		message["event"] = sync_event.duplicate(true)
	var payload: PackedByteArray = JSON.stringify(message).to_utf8_buffer()
	if payload.size() > MAX_BYTES:
		status_changed.emit("La mappa supera il limite di sincronizzazione")
		return PackedByteArray()
	return payload


func _queue_snapshot_payload(
	host: String,
	payload: PackedByteArray,
	timeout_ms: int,
	quiet: bool,
	bulk_id: int = -1
) -> Error:
	var peer := StreamPeerTCP.new()
	var error: Error = peer.connect_to_host(host, port)
	if error != OK:
		return error

	var frame := StreamPeerBuffer.new()
	frame.put_u32(payload.size())
	frame.put_data(payload)
	connections.append(
		{
			"peer": peer,
			"out": frame.data_array,
			"sent": 0,
			"buffer": PackedByteArray(),
			"size": -1,
			"sender": true,
			"quiet": quiet,
			"bulk_id": bulk_id,
			"host": host,
			"deadline": Time.get_ticks_msec() + timeout_ms
		}
	)
	return OK


# The presence service verifies that a LAN peer really is running VTT in the
# same game. Mobile clients are intentionally excluded from TCP map/chat pushes:
# they poll the desktop's tactical UDP service instead.
func set_lan_presence(presence: Node) -> void:
	_lan_presence = presence


func get_presence_discovery_hosts() -> Array[String]:
	return CreaturePresence.discovery_targets(get_cached_tailscale_peer_ipv4s())


func get_session_peer_ipv4s() -> Array[String]:
	return _collect_sync_peer_ipv4s(true)


func _collect_sync_peer_ipv4s(use_cached: bool) -> Array[String]:
	var hosts: Array[String] = (
		get_cached_tailscale_peer_ipv4s()
		if use_cached
		else _tailscale_peer_ipv4s()
	)
	if _lan_presence == null or not is_instance_valid(_lan_presence):
		return hosts
	for host: String in _lan_presence.call("get_online_desktop_ipv4s"):
		if not hosts.has(host):
			hosts.append(host)
	return hosts


func get_cached_tailscale_peer_ipv4s() -> Array[String]:
	var now := Time.get_ticks_msec()
	if (
		_tailscale_peer_cache_updated_msec <= 0
		or now - _tailscale_peer_cache_updated_msec
		>= TAILSCALE_PEER_REFRESH_MS
	):
		_request_tailscale_peer_refresh()
	return _tailscale_peer_cache.duplicate()


func _request_tailscale_peer_refresh() -> void:
	if (
		_tailscale_peer_refresh_thread != null
		and _tailscale_peer_refresh_thread.is_started()
	):
		return
	_tailscale_peer_refresh_thread = Thread.new()
	var error := _tailscale_peer_refresh_thread.start(
		Callable(self, "_query_tailscale_peer_ipv4s")
	)
	if error != OK:
		_tailscale_peer_refresh_thread = null


func _poll_tailscale_peer_refresh() -> void:
	if (
		_tailscale_peer_refresh_thread == null
		or not _tailscale_peer_refresh_thread.is_started()
		or _tailscale_peer_refresh_thread.is_alive()
	):
		return
	var result: Variant = _tailscale_peer_refresh_thread.wait_to_finish()
	_tailscale_peer_refresh_thread = null
	if not result is Dictionary:
		return
	var data := result as Dictionary
	var hosts_value: Variant = data.get("hosts", [])
	if hosts_value is Array:
		_tailscale_peer_cache.clear()
		for value: Variant in hosts_value as Array:
			var host := String(value).strip_edges()
			if not host.is_empty():
				_tailscale_peer_cache.append(host)
	_tailscale_last_error = String(data.get("error", ""))
	_tailscale_peer_cache_updated_msec = Time.get_ticks_msec()


func _tailscale_peer_ipv4s() -> Array[String]:
	var result := _query_tailscale_peer_ipv4s()
	_tailscale_last_error = String(result.get("error", ""))
	_tailscale_peer_cache.clear()
	var hosts_value: Variant = result.get("hosts", [])
	if hosts_value is Array:
		for value: Variant in hosts_value as Array:
			var host := String(value).strip_edges()
			if not host.is_empty():
				_tailscale_peer_cache.append(host)
	_tailscale_peer_cache_updated_msec = Time.get_ticks_msec()
	return _tailscale_peer_cache.duplicate()


func _query_tailscale_peer_ipv4s() -> Dictionary:
	var candidates: Array[String] = []

	if OS.get_name() == "Windows":
		var program_files: String = OS.get_environment("ProgramFiles")
		if not program_files.is_empty():
			candidates.append(
				program_files.path_join("Tailscale").path_join("tailscale.exe")
			)
		var program_files_x86: String = OS.get_environment("ProgramFiles(x86)")
		if not program_files_x86.is_empty():
			candidates.append(
				program_files_x86.path_join("Tailscale").path_join("tailscale.exe")
			)
		candidates.append("tailscale.exe")
	else:
		candidates.append("tailscale")
		candidates.append("/usr/bin/tailscale")
		candidates.append("/usr/local/bin/tailscale")

	var parsed: Variant = null
	var attempted: Array[String] = []
	for executable: String in candidates:
		if executable in attempted:
			continue
		attempted.append(executable)

		var output: Array = []
		var exit_code: int = OS.execute(
			executable,
			PackedStringArray(["status", "--json"]),
			output
		)
		if exit_code != 0:
			continue

		var raw: String = ""
		for chunk: Variant in output:
			raw += String(chunk)
		parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			break

	if not parsed is Dictionary:
		return {
			"hosts": [],
			"error": (
				"Impossibile eseguire o leggere 'tailscale status --json'. "
				+ "Controlla che Tailscale sia installato."
			)
		}

	var peers_value: Variant = (parsed as Dictionary).get("Peer", {})
	if not peers_value is Dictionary:
		return {
			"hosts": [],
			"error": "Il JSON di Tailscale non contiene Peer."
		}

	var hosts: Array[String] = []
	var seen: Dictionary = {}
	for peer_value: Variant in (peers_value as Dictionary).values():
		if not peer_value is Dictionary:
			continue
		var ips_value: Variant = (peer_value as Dictionary).get(
			"TailscaleIPs",
			[]
		)
		if not ips_value is Array:
			continue
		for ip_value: Variant in ips_value:
			var ip: String = String(ip_value).strip_edges()
			if ip.is_empty() or ip.contains(":") or seen.has(ip):
				continue
			if not ip.is_valid_ip_address():
				continue
			seen[ip] = true
			hosts.append(ip)

	return {
		"hosts": hosts,
		"error": (
			"Il comando funziona, ma non ha restituito IPv4 peer."
			if hosts.is_empty()
			else ""
		)
	}


func _finish_bulk_attempt(item: Dictionary, accepted: bool, rejected: bool) -> void:
	if int(item.get("bulk_id", -1)) != _bulk_generation:
		return
	if _bulk_pending <= 0:
		return

	_bulk_pending -= 1
	if accepted:
		_bulk_accepted += 1
	elif rejected:
		_bulk_rejected += 1
	else:
		_bulk_failed += 1

	if _bulk_pending == 0:
		if (
			auto_sync_enabled
			and (_bulk_rejected > 0 or _bulk_failed > 0)
		):
			_mark_current_state_dirty_for_retry()
		status_changed.emit(
			"Sincronizzazione conclusa Â· ricevute %d/%d Â· rifiutate %d Â· non raggiungibili %d"
			% [
				_bulk_accepted,
				_bulk_total,
				_bulk_rejected,
				_bulk_failed
			]
		)


func _mark_current_state_dirty_for_retry() -> void:
	if (
		board_root == null
		or not is_instance_valid(board_root)
		or _applying_received_snapshot
	):
		return
	var snapshot := create_snapshot()
	if snapshot.is_empty():
		return
	var now := Time.get_ticks_msec()
	var signature := _snapshot_signature(snapshot)
	_auto_sync_initialized = true
	# Do not keep the optimistic signature that was recorded when the TCP send
	# merely started. A rejected ACK means the current state is still dirty.
	_auto_sync_last_signature = ""
	_auto_sync_candidate_signature = signature
	_auto_sync_candidate_since_msec = (
		now - AUTO_SYNC_DEBOUNCE_MS
	)
	_auto_sync_retry_after_msec = now + AUTO_SYNC_RETRY_MS


func _process(_delta: float) -> void:
	_poll_tailscale_peer_refresh()
	_poll_auto_sync()
	if (
		_tailscale_peer_refresh_thread == null
		and (
			_tailscale_peer_cache_updated_msec <= 0
			or Time.get_ticks_msec() - _tailscale_peer_cache_updated_msec
			>= TAILSCALE_PEER_REFRESH_MS
		)
	):
		_request_tailscale_peer_refresh()

	if server.is_connection_available():
		var peer := server.take_connection()
		if connections.size() >= 8:
			peer.disconnect_from_host()
		else:
			connections.append({"peer": peer, "buffer": PackedByteArray(), "size": -1, "sender": false, "deadline": Time.get_ticks_msec() + 30000})
	for index in range(connections.size() - 1, -1, -1):
		var item: Dictionary = connections[index]
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if Time.get_ticks_msec() > item.deadline or peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
			if item.sender:
				_finish_bulk_attempt(item, false, false)
				if not bool(item.get("quiet", false)):
					status_changed.emit("Invio non confermato: connessione interrotta o timeout")
			peer.disconnect_from_host()
			connections.remove_at(index)
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if item.sender and item.sent < item.out.size():
			var result := peer.put_partial_data(item.out.slice(item.sent, mini(item.sent + 65536, item.out.size())))
			if result[0] != OK:
				item.deadline = 0
			else:
				item.sent += result[1]
		var available := peer.get_available_bytes()
		if available > 0:
			var result := peer.get_data(mini(available, 65536))
			if result[0] != OK:
				item.deadline = 0
				continue
			item.buffer.append_array(result[1])
		if item.sender:
			if item.buffer.size() > 0:
				var accepted_by_receiver: bool = item.buffer[0] == 1
				_finish_bulk_attempt(
					item,
					accepted_by_receiver,
					not accepted_by_receiver
				)
				if not bool(item.get("quiet", false)):
					status_changed.emit("Mappa ricevuta e applicata" if accepted_by_receiver else "Mappa rifiutata: controlla partita, scena e stato della mappa")
				peer.disconnect_from_host()
				connections.remove_at(index)
			continue
		if item.size == -1 and item.buffer.size() >= 4:
			item.size = item.buffer.decode_u32(0)
			item.buffer = item.buffer.slice(4)
			if item.size <= 0 or item.size > MAX_BYTES:
				item.deadline = 0
				continue
		if item.size > 0 and item.buffer.size() >= item.size:
			var message: Variant = JSON.parse_string(
				item.buffer.slice(0, item.size).get_string_from_utf8()
			)
			var accepted := false
			var reject_reason := "messaggio non valido"
			if message is Dictionary:
				if message.get("magic") not in [MAGIC, "DND_MAP_SYNC_V5"]:
					reject_reason = "protocollo non compatibile"
				elif message.get("key") != session_key:
					reject_reason = "numero partita diverso"
				else:
					var snapshot: Variant = message.get("snapshot")
					if not valid_snapshot(snapshot):
						reject_reason = "snapshot/scena non compatibile"
					elif create_snapshot().is_empty():
						reject_reason = "stato locale non sincronizzabile"
					elif not _save_backup(
						create_snapshot(),
						"before_receive"
					):
						reject_reason = "backup locale fallito"
					else:
						_applying_received_snapshot = true
						accepted = apply_snapshot(snapshot)
						_applying_received_snapshot = false
						if accepted:
							_accept_received_snapshot(snapshot)
							var sync_event: Variant = message.get("event", {})
							if sync_event is Dictionary and not (sync_event as Dictionary).is_empty():
								_replay_sync_event(sync_event as Dictionary)
						else:
							reject_reason = "applicazione snapshot fallita"
			peer.put_data(PackedByteArray([1 if accepted else 0]))
			status_changed.emit(
				"Mappa ricevuta; backup locale salvato"
				if accepted
				else "Mappa rifiutata: %s" % reject_reason
			)
			connections.remove_at(index)

func _exit_tree() -> void:
	server.stop()
	for item in connections:
		item.peer.disconnect_from_host()
	if (
		_tailscale_peer_refresh_thread != null
		and _tailscale_peer_refresh_thread.is_started()
	):
		_tailscale_peer_refresh_thread.wait_to_finish()
	_tailscale_peer_refresh_thread = null

func valid_snapshot(snapshot: Variant) -> bool:
	if (
		not snapshot is Dictionary
		or int(snapshot.get("version", -1)) not in [5, SNAPSHOT_VERSION]
		or snapshot.get("scene") != board_root.scene_file_path
	):
		return false
	if not snapshot.get("objects") is Array or snapshot.objects.size() > 4096 or not measurement_tool.valid_aoes(snapshot.get("aoes")):
		return false
	if snapshot.has("camera") and not _valid_transform_payload(snapshot.get("camera")):
		return false
	var controller := board_root.get_node_or_null("EncounterProgressController")
	if controller != null:
		if not snapshot.get("encounter") is Dictionary or not controller._valid_state(snapshot.encounter) or controller.is_advancing:
			return false
	var initiative_tracker: Node = _initiative_tracker()
	if initiative_tracker == null:
		return false
	if not snapshot.get("initiative") is Dictionary:
		return false
	if not bool(
		initiative_tracker.call(
			"valid_state",
			snapshot.get("initiative")
		)
	):
		return false
	var ids := {}
	var item_token_ids: Dictionary = {}
	for item in snapshot.objects:
		if not item is Dictionary or not item.get("id") is String or item.id.is_empty() or ids.has(item.id):
			return false
		ids[item.id] = true
		if item.get("kind") == "token":
			item_token_ids[item.id] = true
		if item.get("kind") not in ["token", "physical"] or item.get("group") not in GROUPS:
			return false
		var transform: Variant = item.get("transform")
		if not transform is Dictionary or not transform.get("basis") is Array or transform.basis.size() != 3:
			return false
		for vector in transform.basis + [transform.get("origin")]:
			if not vector is Dictionary:
				return false
			for axis in ["x", "y", "z"]:
				var value: Variant = vector.get(axis)
				if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 100000:
					return false
		if absf(_dict_transform(transform).basis.determinant()) < 0.000001:
			return false
		if item.kind == "token":
			if not item.get("footprint") is float and not item.get("footprint") is int:
				return false
			if float(item.footprint) <= 0 or float(item.footprint) > 100 or not item.get("color") is Dictionary:
				return false
			if item.has("reach_feet"):
				var reach_value: Variant = item.get("reach_feet")
				if not (reach_value is float or reach_value is int):
					return false
				if (
					not is_finite(float(reach_value))
					or float(reach_value) <= 0.0
					or float(reach_value) > 1000.0
				):
					return false
			for channel in ["r", "g", "b", "a"]:
				var value: Variant = item.color.get(channel)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 1:
					return false
			if not item.get("size_name") is String or not item.get("flying") is bool:
				return false
			if item.has("appearance_revision"):
				var appearance_revision_value: Variant = item.get(
					"appearance_revision"
				)
				if not (
					appearance_revision_value is int
					or appearance_revision_value is float
				):
					return false
				var appearance_revision_number := float(
					appearance_revision_value
				)
				if (
					not is_finite(appearance_revision_number)
					or appearance_revision_number
					!= floor(appearance_revision_number)
					or appearance_revision_number < 0.0
					or appearance_revision_number > 2147483647.0
				):
					return false
			if item.has("gravity_applied") and not item.get("gravity_applied") is bool:
				return false
			if item.has("support_id") and not item.get("support_id") is String:
				return false
			if item.has("mount_target_id"):
				if (
					not item.get("mount_target_id") is String
					or String(item.get("mount_target_id")).is_empty()
					or String(item.get("mount_target_id")).length() > 96
					or String(item.get("mount_target_kind", "")) not in ["token", "item"]
				):
					return false
				var mount_local: Variant = item.get("mount_local_position")
				if not mount_local is Dictionary:
					return false
				for axis: String in ["x", "y", "z"]:
					var coordinate: Variant = mount_local.get(axis)
					if (
						not (coordinate is float or coordinate is int)
						or not is_finite(float(coordinate))
						or absf(float(coordinate)) > 100000
					):
						return false
				if item.has("mount_local_yaw"):
					var local_yaw: Variant = item.get("mount_local_yaw")
					if (
						not (local_yaw is float or local_yaw is int)
						or not is_finite(float(local_yaw))
						or absf(float(local_yaw)) > TAU
					):
						return false
			elif (
				item.has("mount_target_kind")
				or item.has("mount_local_position")
				or item.has("mount_local_yaw")
			):
				return false
			# V4 makes logical token state mandatory. This prevents an older
			# client from silently accepting a snapshot without names/conditions
			# and then broadcasting blank state back to the table.
			if not item.get("display_name") is String:
				return false
			if String(item.get("display_name", "")).length() > 80:
				return false
			if item.has("party_id") and not item.get("party_id") is String:
				return false
			var party_id := String(item.get("party_id", "")).strip_edges()
			if party_id.length() > 80:
				return false
			if not item.get("conditions") is Array:
				return false
			var condition_values: Array = item.get("conditions", [])
			if condition_values.size() > 128:
				return false
			var seen_conditions: Dictionary = {}
			for condition_value: Variant in condition_values:
				if not condition_value is String:
					return false
				var condition_id := String(condition_value)
				if not ContentCatalog.valid_effect_id(condition_id) or seen_conditions.has(condition_id):
					return false
				seen_conditions[condition_id] = true
			# Token effects are persisted in map snapshots and across peers.
			# They remain independent of the owner's private creature archive.
			var active_spell_value: Variant = item.get("active_spell_ids", [])
			if not active_spell_value is Array or active_spell_value.size() > 128:
				return false
			var seen_spells: Dictionary = {}
			for spell_value: Variant in active_spell_value:
				if not spell_value is String:
					return false
				var spell_id: String = String(spell_value).strip_edges()
				if spell_id.is_empty() or spell_id.length() > 192 or seen_spells.has(spell_id):
					return false
				seen_spells[spell_id] = true
			var concentrating_value: Variant = item.get("concentrating_spell_id", "")
			if not concentrating_value is String or String(concentrating_value).length() > 192:
				return false
			if item.has("condition_presentations"):
				var presentations: Variant = item.get("condition_presentations")
				if not presentations is Array or presentations.size() > 128:
					return false
				var presentation_ids: Dictionary = {}
				for presentation: Variant in presentations:
					if not presentation is Dictionary:
						return false
					if presentation.size() != 3 or not presentation.has("id") or not presentation.has("name") or not presentation.has("icon"):
						return false
					var presentation_id: Variant = presentation.get("id")
					if not presentation_id is String or presentation_id not in condition_values or presentation_ids.has(presentation_id):
						return false
					presentation_ids[presentation_id] = true
					if not presentation.get("name") is String or String(presentation.name).length() > 120 or not presentation.get("icon") is String or String(presentation.icon).length() > 16:
						return false
			if item.has("height_cells"):
				var height_value: Variant = item.get("height_cells")
				if not (height_value is float or height_value is int):
					return false
				if (
					not is_finite(float(height_value))
					or float(height_value) <= 0.0
					or float(height_value) > 100.0
				):
					return false
			if item.has("visual_native_footprint"):
				var native_footprint_value: Variant = item.get(
					"visual_native_footprint"
				)
				if not (
					native_footprint_value is float
					or native_footprint_value is int
				):
					return false
				if (
					not is_finite(float(native_footprint_value))
					or float(native_footprint_value) <= 0.0
					or float(native_footprint_value) > 100.0
				):
					return false
			if item.has("token_pack_id") and not item.get("token_pack_id") is String:
				return false
			var token_pack_id := String(item.get("token_pack_id", "")).strip_edges()
			if not token_pack_id.is_empty() and not _valid_token_pack_id(token_pack_id):
				return false
			if item.has("visual_asset"):
				if not item.get("visual_asset") is String:
					return false
				var visual_asset := String(item.get("visual_asset", ""))
				if not _valid_token_visual_asset(visual_asset, token_pack_id):
					return false
			var front_value: Variant = item.get(
				"visual_front_quarter_turns",
				-1
			)
			if not (front_value is int or front_value is float):
				return false
			var front_number: float = float(front_value)
			if (
				not is_finite(front_number)
				or front_number != floor(front_number)
				or int(front_number) < 0
				or int(front_number) > 3
			):
				return false
			if item.has("transformation_history"):
				var history_value: Variant = item.get(
					"transformation_history",
					[]
				)
				if not history_value is Array:
					return false
				var history: Array = history_value as Array
				if history.size() > 16:
					return false
				for state_value: Variant in history:
					if not state_value is Dictionary:
						return false
					var appearance: Dictionary = state_value as Dictionary
					if not appearance.get("visual_asset", "") is String:
						return false
					var previous_visual := String(
						appearance.get("visual_asset", "")
					)
					if (
						appearance.has("token_pack_id")
						and not appearance.get("token_pack_id") is String
					):
						return false
					var previous_pack_id := String(
						appearance.get("token_pack_id", "")
					).strip_edges()
					if (
						not previous_pack_id.is_empty()
						and not _valid_token_pack_id(previous_pack_id)
					):
						return false
					if not _valid_token_visual_asset(
						previous_visual,
						previous_pack_id
					):
						return false
					if not appearance.get("display_name", "") is String:
						return false
					if not appearance.get("size_name", "") is String:
						return false
					if appearance.has("visual_native_footprint"):
						var previous_native: Variant = appearance.get(
							"visual_native_footprint"
						)
						if not (
							previous_native is float
							or previous_native is int
						):
							return false
						if (
							not is_finite(float(previous_native))
							or float(previous_native) <= 0.0
							or float(previous_native) > 100.0
						):
							return false
					for numeric_key: String in [
						"footprint",
						"height_cells",
						"reach_feet"
					]:
						var numeric_value: Variant = appearance.get(
							numeric_key
						)
						if not (
							numeric_value is float
							or numeric_value is int
						):
							return false
						if float(numeric_value) <= 0.0:
							return false
					var previous_front: Variant = appearance.get(
						"visual_front_quarter_turns",
						0
					)
					if not (
						previous_front is int
						or previous_front is float
					):
						return false
					var previous_front_number := float(previous_front)
					if (
						not is_finite(previous_front_number)
						or previous_front_number != floor(previous_front_number)
						or int(previous_front_number) < 0
						or int(previous_front_number) > 3
					):
						return false
					if not appearance.get("reach_overridden", false) is bool:
						return false
		if not item.get("name") is String or not item.get("visible") is bool:
			return false

	if snapshot.has("health_bars"):
		var health_value: Variant = snapshot.get("health_bars", [])
		if not health_value is Array or (health_value as Array).size() > 4096:
			return false
		var seen_health_tokens: Dictionary = {}
		for entry_value: Variant in health_value as Array:
			if not entry_value is Dictionary:
				return false
			var entry: Dictionary = entry_value as Dictionary
			var token_id_value: Variant = entry.get("token_id")
			if not token_id_value is String:
				return false
			var health_token_id := String(token_id_value).strip_edges()
			if (
				health_token_id.is_empty()
				or health_token_id.length() > 96
				or seen_health_tokens.has(health_token_id)
				or not item_token_ids.has(health_token_id)
			):
				return false
			seen_health_tokens[health_token_id] = true
			var percent_value: Variant = entry.get("percent")
			if not (percent_value is float or percent_value is int):
				return false
			var percent := float(percent_value)
			if (
				not is_finite(percent)
				or percent < 0.0
				or percent > 100.0
			):
				return false

	if board_root.get("item_controller") != null:
		if not board_root.item_controller.valid_items(snapshot.get("items", []), item_token_ids):
			return false
	elif snapshot.has("items") and snapshot.items != []:
		return false
	return _valid_mount_links(snapshot, item_token_ids)


func _valid_mount_links(snapshot: Dictionary, token_ids: Dictionary) -> bool:
	var item_ids: Dictionary = {}
	var item_drivers: Dictionary = {}
	for value: Variant in snapshot.get("items", []):
		if value is Dictionary:
			var item_id := String(value.get("id", ""))
			item_ids[item_id] = true
			item_drivers[item_id] = String(value.get("linked_token_id", ""))
	var parents: Dictionary = {}
	for value: Variant in snapshot.get("objects", []):
		if not value is Dictionary or not value.has("mount_target_id"):
			continue
		if String(value.get("kind", "")) != "token":
			return false
		var token_id := String(value.get("id", ""))
		var target_id := String(value.get("mount_target_id", ""))
		var target_kind := String(value.get("mount_target_kind", ""))
		if target_kind == "token":
			if not token_ids.has(target_id) or token_id == target_id:
				return false
			parents[token_id] = target_id
		elif not item_ids.has(target_id):
			return false
		elif String(item_drivers.get(target_id, "")) == token_id:
			# An item must not be simultaneously pulled by its own rider.
			return false
	for rider_id: Variant in parents.keys():
		var checked: Dictionary = {}
		var current_id := String(rider_id)
		while parents.has(current_id):
			if checked.has(current_id):
				return false
			checked[current_id] = true
			current_id = String(parents[current_id])
	return true

func _effective_party_id(value: String) -> String:
	var clean := value.strip_edges().left(80)
	return clean if not clean.is_empty() else "Default"


func _party_key(value: String) -> String:
	return _effective_party_id(value).to_lower()


func _party_manifest_from_objects(objects: Array) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	for value: Variant in objects:
		if not value is Dictionary:
			continue
		var data: Dictionary = value as Dictionary
		if String(data.get("kind", "")) != "token":
			continue
		var token_id := String(data.get("id", "")).strip_edges()
		if token_id.is_empty():
			continue
		var party_id := _effective_party_id(
			String(data.get("party_id", ""))
		)
		var key := _party_key(party_id)
		if not by_key.has(key):
			by_key[key] = {
				"id": party_id,
				"token_ids": []
			}
		var entry: Dictionary = by_key[key]
		var token_ids: Array = entry.get("token_ids", [])
		token_ids.append(token_id)
		entry["token_ids"] = token_ids
		by_key[key] = entry

	var parties: Array[Dictionary] = []
	for key: Variant in by_key.keys():
		var entry: Dictionary = (by_key[key] as Dictionary).duplicate(true)
		var token_ids: Array = entry.get("token_ids", [])
		token_ids.sort()
		entry["token_ids"] = token_ids
		parties.append(entry)
	parties.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := String(a.get("id", ""))
			var b_id := String(b.get("id", ""))
			if _party_key(a_id) == "default":
				return _party_key(b_id) != "default"
			if _party_key(b_id) == "default":
				return false
			return a_id.naturalnocasecmp_to(b_id) < 0
	)
	return parties


func _node_party_id(node: Node3D) -> String:
	if node == null or not is_instance_valid(node):
		return "Default"
	if node.has_method("get_effective_party_id"):
		return _effective_party_id(
			String(node.call("get_effective_party_id"))
		)
	if node.has_method("get_party_id"):
		return _effective_party_id(String(node.call("get_party_id")))
	return _effective_party_id(String(node.get_meta("party_id", "")))


func _apply_party_manifest(value: Variant) -> void:
	if not value is Array:
		return
	var current := _current_nodes_by_id()
	for entry_value: Variant in (value as Array):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var party_id := String(entry.get("id", "")).strip_edges().left(80)
		if party_id.is_empty():
			continue
		var token_ids_value: Variant = entry.get("token_ids", [])
		if not token_ids_value is Array:
			continue
		var stored_party_id := "" if _party_key(party_id) == "default" else party_id
		for token_id_value: Variant in (token_ids_value as Array):
			var token_id := String(token_id_value).strip_edges()
			if token_id.is_empty():
				continue
			var node_value: Variant = current.get(token_id)
			if not node_value is Node3D:
				continue
			var node := node_value as Node3D
			if not node.is_in_group("dnd_token"):
				continue
			if node.has_method("set_party_id"):
				node.call("set_party_id", stored_party_id)
			else:
				node.set_meta("party_id", stored_party_id)


func _owned_health_bar_entries() -> Array[Dictionary]:
	var by_token: Dictionary = {}
	var current_nodes := _current_nodes_by_id()
	for area_name: String in ["CreatureArea", "PlayerArea", "MasterArea"]:
		var area := board_root.get_node_or_null(area_name)
		if (
			area == null
			or not is_instance_valid(area)
			or not area.has_method("get_owned_health_bar_sync_entries")
		):
			continue
		var entries_value: Variant = area.call(
			"get_owned_health_bar_sync_entries"
		)
		if not entries_value is Array:
			continue
		for entry_value: Variant in entries_value as Array:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value as Dictionary
			var token_id := String(
				entry.get("token_id", "")
			).strip_edges()
			var percent_value: Variant = entry.get("percent")
			if (
				token_id.is_empty()
				or by_token.has(token_id)
				or not current_nodes.has(token_id)
				or not (
					(current_nodes.get(token_id) as Node).is_in_group(
						"dnd_token"
					)
				)
				or not (percent_value is float or percent_value is int)
			):
				continue
			var percent := float(percent_value)
			if not is_finite(percent):
				continue
			by_token[token_id] = {
				"token_id": token_id,
				"percent": clampf(percent, 0.0, 100.0)
			}

	var result: Array[Dictionary] = []
	for token_id_value: Variant in by_token.keys():
		result.append(
			(by_token[token_id_value] as Dictionary).duplicate(true)
		)
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("token_id", "")).naturalnocasecmp_to(
				String(b.get("token_id", ""))
			) < 0
	)
	return result


func _locally_owned_health_token_ids() -> Dictionary:
	var owned: Dictionary = {}
	for entry: Dictionary in _owned_health_bar_entries():
		owned[String(entry.get("token_id", ""))] = true
	return owned


func _apply_partial_health_bars(value: Variant) -> void:
	if not value is Array:
		return
	var current := _current_nodes_by_id()
	var locally_owned := _locally_owned_health_token_ids()
	for entry_value: Variant in value as Array:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var token_id := String(entry.get("token_id", "")).strip_edges()
		if token_id.is_empty() or locally_owned.has(token_id):
			continue
		var node_value: Variant = current.get(token_id)
		if not node_value is Node3D:
			continue
		var token := node_value as Node3D
		if not token.has_method("set_synced_hit_point_percent"):
			continue
		token.call(
			"set_synced_hit_point_percent",
			float(entry.get("percent", 0.0))
		)


func create_snapshot() -> Dictionary:
	if board_root.get("item_controller") != null:
		board_root.item_controller.flush_motion()
	if board_root.get("mount_controller") != null:
		board_root.mount_controller.refresh_all()
	var objects: Array = []
	var seen := {}
	for group_name in GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or node.is_in_group("dnd_item") or seen.has(node) or not board_root.is_ancestor_of(node) or node.is_queued_for_deletion(): continue
			seen[node]=true; objects.append(_serialize_node(node as Node3D, group_name))
	var aoes: Array = []
	if is_instance_valid(measurement_tool) and measurement_tool.has_method("serialize_persistent_aoes"): aoes=measurement_tool.call("serialize_persistent_aoes")
	var controller := board_root.get_node_or_null("EncounterProgressController")
	var state: Dictionary = controller.get_save_state() if controller != null else {}
	if controller != null and state.is_empty(): return {}
	var initiative_tracker: Node = _initiative_tracker()
	if initiative_tracker == null:
		status_changed.emit("Iniziativa non disponibile: sincronizzazione annullata")
		return {}
	var initiative_value: Variant = initiative_tracker.call("get_save_state")
	if not initiative_value is Dictionary:
		status_changed.emit("Stato iniziativa non valido: sincronizzazione annullata")
		return {}
	var initiative: Dictionary = (
		initiative_value as Dictionary
	).duplicate(true)
	var snapshot := {
		"version": SNAPSHOT_VERSION,
		"scene": board_root.scene_file_path,
		"objects": objects,
		"parties": _party_manifest_from_objects(objects),
		"items": board_root.item_controller.serialize_items() if board_root.get("item_controller") != null else [],
		"aoes": aoes,
		"encounter": state,
		"initiative": initiative,
		"health_bars": _owned_health_bar_entries()
	}
	return snapshot


func save_snapshot_to_file(path: String) -> Error:
	var clean_path := path.strip_edges()
	if clean_path.is_empty():
		status_changed.emit("Percorso di salvataggio non valido")
		return ERR_INVALID_PARAMETER
	if clean_path.get_extension().is_empty():
		clean_path += ".vttmap"

	var snapshot := create_snapshot()
	if snapshot.is_empty():
		status_changed.emit("Impossibile salvare la mappa nello stato corrente")
		return ERR_BUSY

	var file := FileAccess.open(clean_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		status_changed.emit(
			"Salvataggio mappa fallito: %s" % error_string(open_error)
		)
		return open_error

	var payload := {
		"magic": LOCAL_SAVE_MAGIC,
		"saved_at": Time.get_datetime_string_from_system(),
		"snapshot": snapshot
	}
	file.store_string(JSON.stringify(payload, "  "))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		status_changed.emit(
			"Salvataggio mappa fallito: %s" % error_string(write_error)
		)
		return write_error

	status_changed.emit("Mappa salvata in locale: %s" % clean_path)
	return OK


func load_snapshot_from_file(path: String) -> Error:
	var clean_path := path.strip_edges()
	if clean_path.is_empty():
		status_changed.emit("Percorso della mappa non valido")
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(clean_path):
		status_changed.emit("Mappa locale non trovata: %s" % clean_path)
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		status_changed.emit(
			"Apertura mappa fallita: %s" % error_string(open_error)
		)
		return open_error
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		status_changed.emit("Il file selezionato non contiene una mappa VTT valida")
		return ERR_PARSE_ERROR

	var root: Dictionary = parsed as Dictionary
	var snapshot_value: Variant = root
	if root.has("magic"):
		if String(root.get("magic", "")) != LOCAL_SAVE_MAGIC:
			status_changed.emit("Formato mappa locale non riconosciuto")
			return ERR_INVALID_DATA
		snapshot_value = root.get("snapshot", {})

	if not snapshot_value is Dictionary:
		status_changed.emit("Snapshot locale mancante o non valido")
		return ERR_INVALID_DATA
	var snapshot: Dictionary = snapshot_value as Dictionary
	if not valid_snapshot(snapshot):
		status_changed.emit(
			"Mappa locale incompatibile con la scena o la versione corrente"
		)
		return ERR_INVALID_DATA

	var current_snapshot := create_snapshot()
	if current_snapshot.is_empty():
		status_changed.emit("Stato locale non salvabile: caricamento annullato")
		return ERR_BUSY
	if not _save_backup(current_snapshot, "before_local_load"):
		status_changed.emit("Backup locale fallito: caricamento annullato")
		return ERR_CANT_CREATE
	if not apply_snapshot(snapshot):
		status_changed.emit("Applicazione della mappa locale fallita")
		return ERR_INVALID_DATA

	status_changed.emit("Mappa locale caricata: %s" % clean_path)
	return OK


func apply_snapshot(snapshot: Dictionary) -> bool:
	if not valid_snapshot(snapshot): return false
	var controller := board_root.get_node_or_null("EncounterProgressController")
	if controller != null and not controller.load_state(snapshot.encounter): return false
	if board_root.has_method("_clear_selection"): board_root._clear_selection()
	var wanted := {}
	for item in snapshot.get("objects",[]):
		if item is Dictionary: wanted[String(item.get("id",""))]=item
	var existing := _current_nodes_by_id()
	for id in existing.keys():
		if not wanted.has(id):
			var n: Node = existing[id]
			if is_instance_valid(n) and n.is_in_group("dnd_token") and n.get_parent() == tokens_root: n.queue_free()
	for id in wanted.keys():
		var data: Dictionary = wanted[id]
		var node: Node3D = existing.get(id) as Node3D
		if node == null:
			node = _instantiate_from_data(data)
		if node == null:
			continue
		_apply_node_data(node, data)
		if data.get("kind", "") == "token":
			if not node.has_method("get_display_name") or not node.has_method("get_conditions"):
				return false
			if String(node.call("get_display_name")) != String(data.get("display_name", "")):
				return false
			var applied_conditions: Variant = node.call("get_conditions")
			if not applied_conditions is Array:
				return false
			var expected_conditions: Array = data.get("conditions", [])
			if (applied_conditions as Array) != expected_conditions:
				return false


	_apply_party_manifest(snapshot.get("parties", []))
	_apply_partial_health_bars(snapshot.get("health_bars", []))
	if board_root.get("item_controller") != null:
		board_root.item_controller.apply_items(snapshot.get("items", []))
	_restore_token_supports(wanted)
	if board_root.get("mount_controller") != null:
		board_root.mount_controller.refresh_all()
	if is_instance_valid(measurement_tool) and measurement_tool.has_method("apply_persistent_aoes"): measurement_tool.call("apply_persistent_aoes", snapshot.get("aoes",[]))
	var initiative_tracker: Node = _initiative_tracker()
	if initiative_tracker == null:
		return false
	if not bool(
		initiative_tracker.call(
			"load_state",
			snapshot.get("initiative")
		)
	):
		return false
	var token_list_value: Variant = board_root.get("token_list")
	if token_list_value is Node and is_instance_valid(token_list_value):
		var token_list_node := token_list_value as Node
		if token_list_node.has_method("refresh"):
			token_list_node.call("refresh")
	var flanking_value: Variant = board_root.get("flanking_system")
	if flanking_value is Node and is_instance_valid(flanking_value):
		var flanking_node := flanking_value as Node
		if flanking_node.has_method("refresh_now"):
			flanking_node.call_deferred("refresh_now")
	_queue_snapshot_token_packs(snapshot)
	# Ownership changes are public token metadata. The receiving installation
	# creates/reattaches its private sheet without an acceptance dialog.
	var creature_area := board_root.get_node_or_null("CreatureArea")
	if creature_area != null and creature_area.has_method("refresh_owned_sheets"):
		creature_area.call_deferred("refresh_owned_sheets")
	return true

func _restore_token_supports(wanted: Dictionary) -> void:
	var current: Dictionary = _current_nodes_by_id()
	for token_id: Variant in wanted.keys():
		var data_value: Variant = wanted[token_id]
		if not data_value is Dictionary:
			continue
		var data: Dictionary = data_value as Dictionary
		if String(data.get("kind", "")) != "token":
			continue
		var support_id := String(data.get("support_id", ""))
		if support_id.is_empty():
			continue
		var token: Node3D = current.get(String(token_id)) as Node3D
		var support: Node3D = current.get(support_id) as Node3D
		if token == null or support == null:
			continue
		token.set("grid_support", support)
		token.set("_support_transform", support.global_transform)


func _current_nodes_by_id() -> Dictionary:
	var out := {}; var seen := {}
	for group_name in GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or seen.has(node) or not board_root.is_ancestor_of(node) or node.is_queued_for_deletion(): continue
			seen[node]=true; out[_sync_id(node as Node3D)]=node
	return out

func get_sync_id_for_node(node: Node3D) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	return _sync_id(node)


func _sync_id(node: Node3D) -> String:
	if node.is_in_group("dnd_token") and node.has_method("get_token_id"):
		var token_identity := String(node.call("get_token_id")).strip_edges()
		if not token_identity.is_empty():
			node.set_meta("sync_id", token_identity)
			return token_identity
	if node.has_meta("sync_id"):
		return String(node.get_meta("sync_id"))
	var id := "path:" + String(board_root.get_path_to(node))
	node.set_meta("sync_id", id)
	return id

func _serialize_node(node: Node3D, group_name: String) -> Dictionary:
	var data := {"id":_sync_id(node),"group":group_name,"path":String(board_root.get_path_to(node)),"scene":node.scene_file_path,"name":String(node.name),"transform":_transform(node.global_transform),"visible":node.visible}
	if group_name == "dnd_token":
		data["kind"]="token"; data["flying"]=bool(node.get("flying"));
		data["token_id"] = (
			String(node.call("get_token_id"))
			if node.has_method("get_token_id")
			else String(data.get("id", ""))
		)
		data["appearance_revision"] = maxi(
			int(node.get_meta(SYNC_APPEARANCE_REVISION_META, 0)),
			0
		)
		var token_pack_id := ""
		if node.has_method("get_token_pack_id"):
			token_pack_id = String(node.call("get_token_pack_id")).strip_edges()
		if token_pack_id.is_empty() and node.has_method("get_visual_asset_path"):
			token_pack_id = _pack_id_from_visual_asset(
				String(node.call("get_visual_asset_path"))
			)
		if not token_pack_id.is_empty():
			data["token_pack_id"] = token_pack_id
		data["footprint"]=float(node.get("_footprint_cells")); data["size_name"]=String(node.get("_size_name")); data["color"]=_token_color(node)
		# Nuovo significato esplicito: i salvataggi precedenti non avevano
		# gravity_applied e vengono quindi migrati come token sospesi.
		data["gravity_applied"] = not bool(node.get("flying"))
		var support_value: Variant = node.get("grid_support")
		if (
			support_value is Node3D
			and is_instance_valid(support_value)
			and board_root.is_ancestor_of(support_value as Node3D)
		):
			data["support_id"] = _sync_id(support_value as Node3D)
		var mount_id := String(node.get_meta("mount_target_id", ""))
		var mount_local: Variant = node.get_meta("mount_local_position", Vector3.ZERO)
		if not mount_id.is_empty() and mount_local is Vector3:
			data["mount_target_kind"] = String(node.get_meta("mount_target_kind", ""))
			data["mount_target_id"] = mount_id
			data["mount_local_position"] = _v3(mount_local as Vector3)
			if node.has_meta("mount_local_yaw"):
				data["mount_local_yaw"] = float(node.get_meta("mount_local_yaw"))
		data["height_cells"] = float(node.get("token_height_cells"))
		data["display_name"] = (
			String(node.call("get_display_name"))
			if node.has_method("get_display_name")
			else ""
		)
		data["party_id"] = (
			String(node.call("get_party_id"))
			if node.has_method("get_party_id")
			else String(node.get_meta("party_id", ""))
		)
		for field: String in [
			"creature_id", "creature_owner_id", "default_miniature_id",
			"master_creature_id", "master_creature_name", "master_creature_side"
		]:
			if node.has_meta(field):
				data[field] = String(node.get_meta(field))
		if node.has_meta("player_character_id"):
			data["player_character_id"] = String(
				node.get_meta("player_character_id")
			)
			data["player_character_name"] = String(
				node.get_meta("player_character_name", "")
			)
		data["condition_presentations"] = node.call("get_condition_presentations") if node.has_method("get_condition_presentations") else []
		data["conditions"] = (
			node.call("get_conditions")
			if node.has_method("get_conditions")
			else []
		)
		data["active_spell_ids"] = (
			node.call("get_active_spell_ids")
			if node.has_method("get_active_spell_ids") else []
		)
		data["concentrating_spell_id"] = (
			String(node.call("get_concentrating_spell_id"))
			if node.has_method("get_concentrating_spell_id") else ""
		)
		data["reach_feet"] = (
			float(node.call("get_reach_feet"))
			if node.has_method("get_reach_feet")
			else maxf(5.0, float(node.get("_footprint_cells")) * 5.0)
		)
		if node.has_method("get_visual_asset_path"):
			data["visual_asset"] = String(node.call("get_visual_asset_path"))
		if node.has_method("get_visual_native_footprint_cells"):
			data["visual_native_footprint"] = float(
				node.call("get_visual_native_footprint_cells")
			)
		data["visual_front_quarter_turns"] = (
			int(node.call("get_visual_front_quarter_turns"))
			if node.has_method("get_visual_front_quarter_turns")
			else 0
		)
		if node.has_method("get_transformation_history"):
			data["transformation_history"] = node.call(
				"get_transformation_history"
			)
		_preserve_received_token_appearance(node, data)
	else: data["kind"]="physical"
	return data

func _instantiate_from_data(data: Dictionary) -> Node3D:
	var instance: Node
	if data.get("kind","") == "token" and token_scene != null:
		instance=token_scene.instantiate(); tokens_root.add_child(instance)
	else:
		# Static/procedural scenery is owned by the matching scene and encounter state.
		return null
	if not instance is Node3D:
		instance.queue_free()
		return null
	var node := instance as Node3D; node.name=String(data.get("name",node.name)); node.set_meta("sync_id",String(data.get("id","")))
	return node

func _apply_node_data(node: Node3D, data: Dictionary) -> void:
	var old_conditions: Array = (
		node.call("get_conditions") if node.has_method("get_conditions") else []
	)
	var old_active_spells: Array = (
		node.call("get_active_spell_ids") if node.has_method("get_active_spell_ids") else []
	)
	var old_concentration: String = (
		String(node.call("get_concentrating_spell_id"))
		if node.has_method("get_concentrating_spell_id") else ""
	)
	node.visible=bool(data.get("visible",true))
	if data.get("kind","") == "token" and node.has_method("set_token_id"):
		var restored_token_id := String(data.get("token_id", "")).strip_edges()
		if restored_token_id.is_empty():
			var legacy_id := String(data.get("id", "")).strip_edges()
			if legacy_id.begins_with("token_"):
				restored_token_id = legacy_id
		if not restored_token_id.is_empty():
			node.call("set_token_id", restored_token_id)
	node.set_meta("sync_id", _sync_id(node))
	if data.get("kind","") == "token":
		var incoming_appearance_revision := maxi(
			int(data.get("appearance_revision", 0)),
			0
		)
		var local_appearance_revision := maxi(
			int(node.get_meta(SYNC_APPEARANCE_REVISION_META, 0)),
			0
		)
		var apply_shared_appearance := (
			incoming_appearance_revision >= local_appearance_revision
		)
		if apply_shared_appearance:
			node.set_meta(
				SYNC_APPEARANCE_REVISION_META,
				incoming_appearance_revision
			)
		var token_pack_id := String(data.get("token_pack_id", "")).strip_edges()
		if token_pack_id.is_empty():
			token_pack_id = _pack_id_from_visual_asset(
				String(data.get("visual_asset", ""))
			)
		if apply_shared_appearance and node.has_method("set_token_pack_id"):
			node.call("set_token_pack_id", token_pack_id)
		# Applicare prima l'asset esplicito disattiva l'eventuale miniatura
		# di default caricata dal token_scene appena istanziato.
		if (
			apply_shared_appearance
			and data.has("visual_asset")
			and node.has_method("set_visual_asset")
		):
			var visual_asset := String(data.get("visual_asset", ""))
			if not visual_asset.is_empty():
				var native_footprint := maxf(
					float(
						data.get(
							"visual_native_footprint",
							data.get("footprint", 1.0)
						)
					),
					0.5
				)
				var visual_applied := bool(
					node.call(
						"set_visual_asset",
						visual_asset,
						native_footprint
					)
				)
				if not visual_applied and not token_pack_id.is_empty():
					node.set_meta(
						"pending_token_pack_native_footprint",
						native_footprint
					)
				elif (
					visual_applied
					and node.has_meta("pending_token_pack_native_footprint")
				):
					node.remove_meta("pending_token_pack_native_footprint")
		if (
			apply_shared_appearance
			and data.has("visual_front_quarter_turns")
			and node.has_method("set_visual_front_quarter_turns")
		):
			node.call(
				"set_visual_front_quarter_turns",
				int(data.get("visual_front_quarter_turns", 0))
			)
		if apply_shared_appearance and data.has("height_cells"):
			node.set(
				"token_height_cells",
				maxf(float(data.get("height_cells", 2.0)), 0.1)
			)
		if apply_shared_appearance and node.has_method("configure"):
			node.call(
				"configure",
				_dict_color(data.get("color", {})),
				float(board_root.get("cell_size")),
				String(data.get("size_name", "Medium")),
				float(data.get("footprint", 1.0))
			)
		if (
			apply_shared_appearance
			and data.has("reach_feet")
			and node.has_method("set_reach_feet")
		):
			node.call(
				"set_reach_feet",
				float(data.get("reach_feet", 5.0)),
				true
			)
		elif apply_shared_appearance and node.has_method("reset_reach_to_default"):
			# Snapshot precedenti: migrazione trasparente dal footprint/taglia.
			node.call("reset_reach_to_default")
		var gravity_applied: bool = bool(data.get("gravity_applied", false))
		if gravity_applied and node.has_method("apply_gravity"):
			node.call("apply_gravity")
		elif node.has_method("set_flying"):
			node.call("set_flying", true)
		for key: String in [
			"mount_target_kind", "mount_target_id",
			"mount_local_position", "mount_local_yaw"
		]:
			if node.has_meta(key):
				node.remove_meta(key)
		if data.has("mount_target_id"):
			node.set_meta("mount_target_kind", String(data.get("mount_target_kind", "")))
			node.set_meta("mount_target_id", String(data.get("mount_target_id", "")))
			node.set_meta("mount_local_position", _dv3(data.get("mount_local_position", {})))
			if data.has("mount_local_yaw"):
				node.set_meta("mount_local_yaw", float(data.get("mount_local_yaw", 0.0)))
		if node.has_method("set_display_name"):
			node.call("set_display_name", String(data.get("display_name", "")))
		if node.has_method("set_party_id"):
			node.call("set_party_id", String(data.get("party_id", "")))
		elif not String(data.get("party_id", "")).strip_edges().is_empty():
			node.set_meta("party_id", String(data.get("party_id", "")))
		elif node.has_meta("party_id"):
			node.remove_meta("party_id")
		var character_id: String = String(
			data.get("player_character_id", "")
		)
		if character_id.is_empty():
			if node.has_meta("player_character_id"):
				node.remove_meta("player_character_id")
			if node.has_meta("player_character_name"):
				node.remove_meta("player_character_name")
		else:
			node.set_meta("player_character_id", character_id)
			node.set_meta(
				"player_character_name",
				String(data.get("player_character_name", ""))
			)
		for field: String in [
			"creature_id", "creature_owner_id", "default_miniature_id",
			"master_creature_id", "master_creature_name", "master_creature_side"
		]:
			var value := String(data.get(field, "")).strip_edges()
			if not value.is_empty():
				node.set_meta(field, value)
			elif node.has_meta(field):
				node.remove_meta(field)
		if node.has_method("set_condition_presentations"):
			node.call("set_condition_presentations", data.get("condition_presentations", []))
		if node.has_method("set_active_spell_ids"):
			node.call("set_active_spell_ids", data.get("active_spell_ids", []))
		if node.has_method("set_concentrating_spell_id"):
			node.call("set_concentrating_spell_id", String(data.get("concentrating_spell_id", "")))
		# Apply the incoming conditions last so manual concentration markers
		# remain valid even without a named spell, and removal clears stale ids.
		if node.has_method("set_conditions"):
			node.call("set_conditions", data.get("conditions", []))
		if apply_shared_appearance and node.has_method(
			"set_transformation_history"
		):
			node.call(
				"set_transformation_history",
				data.get("transformation_history", [])
			)
		if apply_shared_appearance:
			_remember_received_token_appearance(node, data)
		# Only propagate changed tactical effects to an owned private sheet.
		# Do not persist on every incoming map snapshot or polling update.
		var effects_changed := false
		if node.has_method("get_conditions"):
			effects_changed = old_conditions != node.call("get_conditions")
		if node.has_method("get_active_spell_ids"):
			effects_changed = effects_changed or old_active_spells != node.call("get_active_spell_ids")
		if node.has_method("get_concentrating_spell_id"):
			effects_changed = effects_changed or old_concentration != String(node.call("get_concentrating_spell_id"))
		if board_root != null and effects_changed:
			var creature_area: Node = board_root.get_node_or_null("CreatureArea")
			if creature_area != null and creature_area.has_method("sync_linked_token_status"):
				creature_area.call_deferred("sync_linked_token_status", node)
	# configure() snaps tokens; restore the exact shared transform afterwards.
	node.global_transform = _dict_transform(data.get("transform", {}))


func _serialized_token_appearance(data: Dictionary) -> Dictionary:
	var appearance: Dictionary = {}
	for key_value: Variant in SYNC_APPEARANCE_KEYS:
		var key := String(key_value)
		if data.has(key):
			appearance[key] = data.get(key)
	return appearance


func _remember_received_token_appearance(
	node: Node3D,
	data: Dictionary
) -> void:
	# The network representation is authoritative until this client performs
	# an explicit local appearance edit. Never infer an edit from local mesh
	# state: mounting a pack or recalculating native footprint can legitimately
	# change the local representation without changing the shared token.
	var authoritative := _serialized_token_appearance(data)
	node.set_meta(SYNC_APPEARANCE_META, authoritative.duplicate(true))


func mark_token_appearance_locally_edited(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Appearance has its own causal revision. Movement and unrelated map
	# actions never advance it, so an older full-scene snapshot cannot undo a
	# newer explicit token edit.
	var next_revision := maxi(
		int(node.get_meta(SYNC_APPEARANCE_REVISION_META, 0)) + 1,
		1
	)
	node.set_meta(SYNC_APPEARANCE_REVISION_META, next_revision)
	if node.has_meta(SYNC_APPEARANCE_META):
		node.remove_meta(SYNC_APPEARANCE_META)
	var live_data := _serialize_node(node, "dnd_token")
	var authoritative := _serialized_token_appearance(live_data)
	node.set_meta(SYNC_APPEARANCE_META, authoritative.duplicate(true))


func _preserve_received_token_appearance(
	node: Node3D,
	data: Dictionary
) -> void:
	if not node.has_meta(SYNC_APPEARANCE_META):
		return
	var stored_value: Variant = node.get_meta(SYNC_APPEARANCE_META)
	if not stored_value is Dictionary:
		node.remove_meta(SYNC_APPEARANCE_META)
		return

	# Movement, gravity, initiative changes, another token moving, etc. must
	# never rewrite this token's shared visual state from a peer-local mesh
	# representation. Reuse exactly what was received.
	var authoritative: Dictionary = stored_value as Dictionary
	for key_value: Variant in SYNC_APPEARANCE_KEYS:
		var key := String(key_value)
		if authoritative.has(key):
			data[key] = authoritative.get(key)
		else:
			data.erase(key)


func _remote_visual_path(token_pack_id: String) -> String:
	return (
		"res://remote_tokens/%s/%s_visual.res"
		% [token_pack_id, token_pack_id]
	)


func _valid_token_pack_id(token_pack_id: String) -> bool:
	var clean := token_pack_id.strip_edges()
	return (
		not clean.is_empty()
		and clean.length() <= 96
		and not clean.contains("/")
		and not clean.contains("\\")
		and not clean.contains("..")
		and not clean.contains(":")
	)


func _pack_id_from_visual_asset(visual_asset: String) -> String:
	var clean := visual_asset.strip_edges()
	var prefix := "res://remote_tokens/"
	if not clean.begins_with(prefix):
		return ""
	var remainder := clean.substr(prefix.length())
	var slash_index := remainder.find("/")
	if slash_index <= 0:
		return ""
	var token_pack_id := remainder.left(slash_index)
	if not _valid_token_pack_id(token_pack_id):
		return ""
	if clean != _remote_visual_path(token_pack_id):
		return ""
	return token_pack_id


func _valid_token_visual_asset(
	visual_asset: String,
	token_pack_id: String = ""
) -> bool:
	var clean := visual_asset.strip_edges()
	if clean.is_empty():
		return true
	if clean.begins_with("res://assets/tokens/"):
		return not clean.contains("..")
	var resolved_pack_id := token_pack_id.strip_edges()
	if resolved_pack_id.is_empty():
		resolved_pack_id = _pack_id_from_visual_asset(clean)
	return (
		_valid_token_pack_id(resolved_pack_id)
		and clean == _remote_visual_path(resolved_pack_id)
	)


func _queue_snapshot_token_packs(snapshot: Dictionary) -> void:
	for item_value: Variant in snapshot.get("objects", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value as Dictionary
		if String(item.get("kind", "")) != "token":
			continue
		var current_pack_id := String(
			item.get("token_pack_id", "")
		).strip_edges()
		if current_pack_id.is_empty():
			current_pack_id = _pack_id_from_visual_asset(
				String(item.get("visual_asset", ""))
			)
		_queue_token_pack_id(current_pack_id)
		var history_value: Variant = item.get("transformation_history", [])
		if history_value is Array:
			var history: Array = history_value as Array
			for state_value: Variant in history:
				if not state_value is Dictionary:
					continue
				var appearance: Dictionary = state_value as Dictionary
				var previous_pack_id := String(
					appearance.get("token_pack_id", "")
				).strip_edges()
				if previous_pack_id.is_empty():
					previous_pack_id = _pack_id_from_visual_asset(
						String(appearance.get("visual_asset", ""))
					)
				_queue_token_pack_id(previous_pack_id)
	_process_token_pack_queue()


func _queue_token_pack_id(token_pack_id: String) -> void:
	var clean := token_pack_id.strip_edges()
	if (
		not _valid_token_pack_id(clean)
		or clean == _active_token_pack_id
		or _pending_token_pack_ids.has(clean)
	):
		return
	_pending_token_pack_ids.append(clean)


func _process_token_pack_queue() -> void:
	if TokenPackManager == null or not _active_token_pack_id.is_empty():
		return
	while not _pending_token_pack_ids.is_empty():
		var candidate_index := -1
		for index in range(_pending_token_pack_ids.size()):
			if TokenPackManager.has_token(_pending_token_pack_ids[index]):
				candidate_index = index
				break
		if candidate_index < 0:
			# Il catalogo remoto potrebbe essere ancora in aggiornamento.
			return

		var token_pack_id := _pending_token_pack_ids[candidate_index]
		_pending_token_pack_ids.remove_at(candidate_index)
		if TokenPackManager.is_mounted(token_pack_id):
			_apply_mounted_pack_to_tokens(token_pack_id)
			continue

		_active_token_pack_id = token_pack_id
		if TokenPackManager.is_downloaded(token_pack_id):
			var mount_error := TokenPackManager.mount_token(token_pack_id)
			if mount_error == OK:
				# token_mounted continua la coda; evitare reentrancy qui.
				return
			_active_token_pack_id = ""
			push_warning(
				"BoardSync: mount automatico fallito per %s: %s"
				% [token_pack_id, error_string(mount_error)]
			)
			continue

		var download_error := TokenPackManager.download_token(token_pack_id)
		if download_error == OK:
			return
		_active_token_pack_id = ""
		if download_error == ERR_BUSY:
			_pending_token_pack_ids.push_front(token_pack_id)
			return
		push_warning(
			"BoardSync: download automatico fallito per %s: %s"
			% [token_pack_id, error_string(download_error)]
		)


func _apply_mounted_pack_to_tokens(token_pack_id: String) -> void:
	if board_root == null or not is_instance_valid(board_root):
		return
	var visual_asset := _remote_visual_path(token_pack_id)
	for node_value: Variant in get_tree().get_nodes_in_group("dnd_token"):
		if not node_value is Node3D:
			continue
		var node: Node3D = node_value as Node3D
		if not board_root.is_ancestor_of(node):
			continue
		var node_pack_id := ""
		if node.has_method("get_token_pack_id"):
			node_pack_id = String(node.call("get_token_pack_id")).strip_edges()
		if node_pack_id != token_pack_id or not node.has_method("set_visual_asset"):
			continue
		var fallback_native := 1.0
		if node.has_method("get_footprint_cells"):
			fallback_native = maxf(
				float(node.call("get_footprint_cells")),
				0.5
			)
		var native_footprint := float(
			node.get_meta(
				"pending_token_pack_native_footprint",
				fallback_native
			)
		)
		if bool(node.call("set_visual_asset", visual_asset, native_footprint)):
			if node.has_meta("pending_token_pack_native_footprint"):
				node.remove_meta("pending_token_pack_native_footprint")


func _on_token_pack_catalog_updated(_entries: Array[Dictionary]) -> void:
	_process_token_pack_queue()


func _on_token_pack_downloaded(token_pack_id: String, _cache_path: String) -> void:
	if token_pack_id == _active_token_pack_id:
		var mount_error := TokenPackManager.mount_token(token_pack_id)
		if mount_error != OK:
			_active_token_pack_id = ""
			push_warning(
				"BoardSync: mount dopo download fallito per %s: %s"
				% [token_pack_id, error_string(mount_error)]
			)
			_process_token_pack_queue()
	elif _active_token_pack_id.is_empty():
		_process_token_pack_queue()


func _on_token_pack_download_failed(token_pack_id: String, message: String) -> void:
	if token_pack_id == _active_token_pack_id:
		_active_token_pack_id = ""
		push_warning(
			"BoardSync: download automatico fallito per %s: %s"
			% [token_pack_id, message]
		)
	_process_token_pack_queue()


func _on_token_pack_mounted(token_pack_id: String, _scene_path: String) -> void:
	_apply_mounted_pack_to_tokens(token_pack_id)
	if token_pack_id == _active_token_pack_id:
		_active_token_pack_id = ""
	_process_token_pack_queue()


func _on_token_pack_mount_failed(token_pack_id: String, message: String) -> void:
	if token_pack_id == _active_token_pack_id:
		_active_token_pack_id = ""
		push_warning(
			"BoardSync: mount automatico fallito per %s: %s"
			% [token_pack_id, message]
		)
	_process_token_pack_queue()


func _save_backup(snapshot: Dictionary, reason: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP_DIR))
	var stamp := Time.get_datetime_string_from_system().replace(":","-") + "_" + str(Time.get_ticks_usec())
	var path := "%s/%s_%s.json" % [BACKUP_DIR,stamp,reason]
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(snapshot,"  "))
	var success := f.get_error() == OK
	f.close()
	_rotate_backups()
	return success

func _rotate_backups() -> void:
	var dir := DirAccess.open(BACKUP_DIR); if dir == null: return
	var files: Array[String]=[]; dir.list_dir_begin()
	var entry_name:=dir.get_next()
	while not entry_name.is_empty():
		if not dir.current_is_dir() and entry_name.ends_with(".json"): files.append(entry_name)
		entry_name=dir.get_next()
	dir.list_dir_end(); files.sort()
	while files.size()>MAX_BACKUPS: DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_DIR.path_join(files.pop_front())))

func _transform(t: Transform3D) -> Dictionary: return {"basis":[_v3(t.basis.x),_v3(t.basis.y),_v3(t.basis.z)],"origin":_v3(t.origin)}
func _dict_transform(d: Variant) -> Transform3D:
	if not d is Dictionary: return Transform3D.IDENTITY
	var b=d.get("basis",[]); var basis:=Basis.IDENTITY
	if b is Array and b.size()==3: basis=Basis(_dv3(b[0]),_dv3(b[1]),_dv3(b[2]))
	return Transform3D(basis,_dv3(d.get("origin",{})))
func _v3(v: Vector3)->Dictionary: return {"x":v.x,"y":v.y,"z":v.z}
func _dv3(v: Variant)->Vector3:
	if v is Dictionary: return Vector3(float(v.get("x",0)),float(v.get("y",0)),float(v.get("z",0)))
	return Vector3.ZERO
func _token_color(node: Node3D)->Dictionary:
	var visuals=node.get_node_or_null("Visuals")
	if visuals != null:
		for c in visuals.get_children():
			if c is MeshInstance3D and c.material_override is StandardMaterial3D: return _color((c.material_override as StandardMaterial3D).albedo_color)
	return _color(Color.WHITE)
func _color(c:Color)->Dictionary: return {"r":c.r,"g":c.g,"b":c.b,"a":c.a}
func _dict_color(v:Variant)->Color:
	if v is Dictionary: return Color(float(v.get("r",1)),float(v.get("g",1)),float(v.get("b",1)),float(v.get("a",1)))
	return Color.WHITE

# Allowlisted projection for mobile sheets. Never serialize map assets,
# private creature records, exact HP, encounter secrets or scene paths.
func get_tactical_map_data() -> Dictionary:
	var tokens: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if not node is Node3D or not board_root.is_ancestor_of(node) or node.is_queued_for_deletion() or not node.is_visible_in_tree():
			continue
		tokens.append({
			"id": get_sync_id_for_node(node),
			"name": String(node.call("get_display_name")) if node.has_method("get_display_name") else String(node.name),
			"conditions": node.call("get_conditions") if node.has_method("get_conditions") else [],
			"active_spell_ids": node.call("get_active_spell_ids") if node.has_method("get_active_spell_ids") else [],
			"concentrating_spell_id": String(node.call("get_concentrating_spell_id")) if node.has_method("get_concentrating_spell_id") else ""
		})
	var combat: Dictionary = {"active": false, "round": 1, "active_index": -1, "entries": []}
	var tracker := _initiative_tracker()
	if tracker != null:
		var state: Dictionary = tracker.call("get_save_state")
		for key: String in ["active", "round", "active_index"]:
			combat[key] = state.get(key, combat[key])
		var visible_ids: Dictionary = {}
		for token: Dictionary in tokens:
			visible_ids[token.id] = true
		var entries: Array = []
		var projected_active_index := -1
		var all_entries: Array = state.get("entries", [])
		var active_index := int(state.get("active_index", -1))
		for index in range(all_entries.size()):
			var row: Dictionary = all_entries[index]
			var token_id := String(row.get("token_id", ""))
			if not token_id.is_empty() and not visible_ids.has(token_id):
				continue
			entries.append({"token_id": token_id, "name": String(row.get("name", "")), "initiative": int(row.get("initiative", 0))})
			if index == active_index:
				projected_active_index = entries.size() - 1
		combat["entries"] = entries
		combat["active_index"] = projected_active_index
	return {"version": 1, "tokens": tokens, "combat": combat, "mobile_protocol": 2}


func _visible_mobile_token(id: String) -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if node is CharacterBody3D and board_root.is_ancestor_of(node) and not node.is_queued_for_deletion() and node.is_visible_in_tree() and get_sync_id_for_node(node) == id:
			return node as CharacterBody3D
	return null

func _handle_mobile_action(action: String, payload: Dictionary) -> Dictionary:
	var target := _visible_mobile_token(String(payload.get("token_id", "")))
	if target == null:
		return {"ok": false, "error": "Il token non è più presente o visibile sulla mappa."}
	if action == "move_token":
		var step: String = String(payload.get("direction", ""))
		var directions := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
		if not directions.has(step) or not board_root.has_method("nudge_token_from_mobile"):
			return {"ok": false, "error": "Movimento non disponibile."}
		var moved: bool = board_root.call("nudge_token_from_mobile", target, directions[step])
		return {"ok": true, "moved": moved, "token_id": get_sync_id_for_node(target)}
	if action == "set_condition":
		var id: String = String(payload.get("condition_id", ""))
		if not payload.get("enabled") is bool:
			return {"ok": false, "error": "Condizione non valida."}
		for definition: Dictionary in ContentCatalog.condition_definitions(String(target.get_meta("rules_version", "2014"))):
			if String(definition.get("id", "")) == id:
				board_root.call("_set_token_status", target, id, payload.enabled)
				return {"ok": true}
		return {"ok": false, "error": "Condizione sconosciuta."}
	if action in ["begin_spell", "target_spell", "cancel_spell", "finish_spell", "preview_spell"]:
		return _mobile_spell_action(action, payload, target)
	if action == "target_attack":
		var victim := _visible_mobile_token(String(payload.get("target_id", "")))
		var attack_system: Node = board_root.get_node_or_null("AttackSystem")
		if victim == null or attack_system == null or not payload.get("attack") is Dictionary:
			return {"ok": false, "error": "Bersaglio non disponibile."}
		for key: String in ["range_feet", "long_range_feet"]:
			var value: Variant = payload.attack.get(key, 0)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 10000:
				return {"ok": false, "error": "Gittata non valida."}
		return attack_system.call("select_mobile_preview_target", target, victim, payload.attack)
	if action == "place_token":
		return _place_mobile_token(payload.get("creature", {}), target)
	if action != "snapshot":
		return {"ok": false, "error": "Comando sconosciuto."}
	if _mobile_capture_busy:
		return {"ok": false, "error": "Acquisizione in corso. Riprova tra un istante."}
	var field: Variant = payload.get("field_feet", 120)
	var attack: Variant = payload.get("attack", {})
	if not (field is float or field is int) or not is_finite(float(field)) or not attack is Dictionary:
		return {"ok": false, "error": "Parametri snapshot non validi."}
	for key: String in ["range_feet", "long_range_feet"]:
		var value: Variant = attack.get(key, 0)
		# Reject non-finite geometry before projecting or allocating buffers.
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0 or float(value) > 10000:
			return {"ok": false, "error": "Gittata non valida."}
	var spell_status := _mobile_spell_status(target, String(payload.get("owner_id", "")))
	if bool(spell_status.get("active", false)):
		attack = {"range_feet": float(spell_status.get("range_feet", 5)), "melee": true}
	var range_feet: float = maxf(float(attack.get("range_feet", target.call("get_reach_feet"))), float(attack.get("long_range_feet", target.get_meta("active_weapon_long_range_feet", 0) if attack.is_empty() else 0)))
	var field_feet := MobileMapCapture.field_for_range(range_feet) if not attack.is_empty() else 60.0
	_mobile_capture_busy = true
	var result: Dictionary = await MobileMapCapture.capture(board_root as Node3D, target, field_feet, attack)
	_mobile_capture_busy = false
	result["token_id"] = String(payload.get("token_id", ""))
	result["attack"] = attack.duplicate(true)
	result["targeting"] = spell_status
	if bool(result.get("ok", false)):
		var key := Crypto.new().generate_random_bytes(12).hex_encode()
		_mobile_views[key] = {"projection": result.get("_projection", {}), "token_id": result.token_id, "at": Time.get_ticks_msec()}
		while _mobile_views.size() > 32:
			_mobile_views.erase(_mobile_views.keys()[0])
		result["snapshot_id"] = key
		result.erase("_projection")
	return result

func _mobile_spell_status(caster: Node3D, owner: String) -> Dictionary:
	var runtime: Node = board_root.get_node_or_null("SpellSystem")
	if runtime == null or not runtime.has_method("remote_targeting_status"):
		return {}
	return runtime.call("remote_targeting_status", caster, owner)

func _mobile_spell_action(action: String, payload: Dictionary, caster: CharacterBody3D) -> Dictionary:
	var runtime: Node = board_root.get_node_or_null("SpellSystem")
	var owner := String(payload.get("owner_id", ""))
	if runtime == null or owner.is_empty() or String(caster.get_meta("creature_owner_id", "")) != owner:
		return {"ok": false, "error": "Piazza prima la tua creatura sulla mappa del desktop."}
	if action == "begin_spell":
		return runtime.call("begin_remote_spell", caster, owner, payload)
	if action in ["cancel_spell", "finish_spell"]:
		return runtime.call("remote_target_input", caster, owner, null, {}, "cancel" if action == "cancel_spell" else "finish")
	var victim := _visible_mobile_token(String(payload.get("target_id", "")))
	var point_data: Dictionary = {}
	var projection: Dictionary = {}
	if victim != null:
		point_data = {"valid": true, "point": victim.global_position, "in_air": true, "normal": Vector3.UP}
	elif not String(payload.get("target_id", "")).is_empty():
		return {"ok": false, "error": "Il bersaglio non è più disponibile. Aggiorna lo snapshot."}
	if victim == null:
		var key := String(payload.get("snapshot_id", ""))
		var pixel: Variant = payload.get("pixel")
		if not _mobile_views.has(key) or not pixel is Array or pixel.size() != 2:
			return {"ok": false, "error": "Aggiorna lo snapshot prima di scegliere il punto."}
		var view: Dictionary = _mobile_views[key]
		if view.token_id != get_sync_id_for_node(caster) or Time.get_ticks_msec() - int(view.at) > 600000:
			return {"ok": false, "error": "Snapshot scaduto: premi Aggiorna."}
		if not (pixel[0] is float or pixel[0] is int) or not (pixel[1] is float or pixel[1] is int):
			return {"ok": false, "error": "Punto non valido."}
		var x := float(pixel[0])
		var y := float(pixel[1])
		if not is_finite(x) or not is_finite(y) or x < 0 or y < 0 or x > MobileMapCapture.SIZE.x or y > MobileMapCapture.SIZE.y:
			return {"ok": false, "error": "Punto fuori dalla mappa."}
		projection = view.projection
		var scale_factor := float(projection.size) / float(MobileMapCapture.SIZE.y)
		var world := Vector3(float(projection.x) + (x - MobileMapCapture.SIZE.x * 0.5) * scale_factor, float(projection.y), float(projection.z) + (y - MobileMapCapture.SIZE.y * 0.5) * scale_factor)
		var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * 0.12, world + Vector3.DOWN * 1000, 1)
		var hit := caster.get_world_3d().direct_space_state.intersect_ray(query)
		point_data = {"valid": true, "point": hit.get("position", world), "in_air": hit.is_empty(), "normal": hit.get("normal", Vector3.UP)}
	if action == "preview_spell":
		if projection.is_empty():
			return {"ok": false, "error": "Aggiorna lo snapshot prima di mirare."}
		return runtime.call("remote_preview_input", caster, owner, point_data, projection)
	return runtime.call("remote_target_input", caster, owner, victim, point_data, "select")

func _place_mobile_token(value: Variant, support: CharacterBody3D) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "Creatura non valida."}
	var creature: Dictionary = value
	for key: String in ["id", "owner_id", "name", "current_miniature_id", "default_miniature_id", "size_name"]:
		if not creature.get(key, "") is String or String(creature.get(key, "")).length() > 256:
			return {"ok": false, "error": "Identità creatura non valida."}
	var id := String(creature.get("id", ""))
	var owner := String(creature.get("owner_id", ""))
	if id.is_empty() or owner.length() < 16:
		return {"ok": false, "error": "Identità creatura mancante."}
	var footprint: Variant = creature.get("footprint", 1.0)
	if not (footprint is float or footprint is int) or not is_finite(float(footprint)) or float(footprint) < 0.5 or float(footprint) > 30:
		return {"ok": false, "error": "Dimensioni creatura non valide."}
	var reach: Variant = creature.get("reach_feet", 5)
	var conditions: Variant = creature.get("conditions", [])
	if not (reach is float or reach is int) or not is_finite(float(reach)) or float(reach) < 0 or float(reach) > 10000 or not conditions is Array or conditions.size() > 64:
		return {"ok": false, "error": "Parametri tattici non validi."}
	for condition: Variant in conditions:
		if not condition is String or condition.length() > 256:
			return {"ok": false, "error": "Condizione non valida."}
	var miniature := String(creature.get("current_miniature_id", ""))
	if miniature.is_empty():
		miniature = String(creature.get("default_miniature_id", ""))
	var profile: Dictionary = board_root.call("_identity_profile_by_id", miniature)
	if profile.is_empty():
		return {"ok": false, "error": "La miniatura scelta sul telefono non è disponibile nel catalogo del desktop."}
	var token: CharacterBody3D
	for node: Node in get_tree().get_nodes_in_group("dnd_token"):
		if node is CharacterBody3D and board_root.is_ancestor_of(node) and not node.is_queued_for_deletion() and String(node.get_meta("creature_id", "")) == id and String(node.get_meta("creature_owner_id", "")) == owner:
			token = node as CharacterBody3D
			break
	if token == support:
		return {"ok": false, "error": "Scegli un altro token come riferimento."}
	var undo: Dictionary = board_root.call("begin_undo_transaction") if board_root.has_method("begin_undo_transaction") else {}
	var created := token == null
	var previous: Dictionary = token.call("get_appearance_state") if not created else {}
	var previous_transform: Transform3D = token.global_transform if not created else Transform3D.IDENTITY
	var previous_default: Variant = token.get_meta("default_miniature_id", "") if not created else ""
	if token == null:
		token = token_scene.instantiate() as CharacterBody3D
		# Assign ownership before adding to the board: never create a private PC sheet.
		token.set_meta("creature_id", id)
		token.set_meta("creature_owner_id", owner)
		tokens_root.add_child(token)
		token.call("configure", Color.WHITE, float(board_root.get("cell_size")), String(creature.get("size_name", "Medium")), float(footprint))
	token.set_meta("default_miniature_id", String(creature.get("default_miniature_id", miniature)))
	token.call("set_display_name", String(creature.get("name", "Creatura")))
	token.call("set_size_category", String(creature.get("size_name", "Medium")), float(footprint), false)
	token.call("set_token_pack_id", miniature)
	board_root.call("apply_creature_sheet_appearance", token, creature)
	token.call("set_reach_feet", float(reach), true)
	token.call("set_conditions", conditions)
	var position := _mobile_adjacent_position(token, support)
	if position == Vector3.INF:
		if created:
			token.queue_free()
		else:
			token.call("apply_appearance_state", previous)
			token.global_transform = previous_transform
			token.set_meta("default_miniature_id", previous_default)
		return {"ok": false, "error": "Non c’è spazio libero accanto al token scelto. Scegli un altro riferimento."}
	if board_root.has_method("commit_undo_transaction"):
		board_root.call("commit_undo_transaction", undo)
	elif board_root.has_method("push_undo_state"):
		board_root.call("push_undo_state")
	_queue_token_pack_id(miniature)
	_process_token_pack_queue()
	token.global_position = position
	token.call("set_flying", true)
	if token.has_method("set_top_down_token_enabled"):
		token.call("set_top_down_token_enabled", bool(board_root.call("is_2d_view_enabled")))
	mark_token_appearance_locally_edited(token)
	board_root.call_deferred("_sync_explicit_token_change", token)
	return {"ok": true, "token_id": get_sync_id_for_node(token), "creature_id": id,
		"name": String(token.call("get_display_name"))}

# Check adjacent footprints at the reference token's base level. Keep the
# reference separate: moving it must not carry the new creature along.
func _mobile_adjacent_position(token: CharacterBody3D, reference: CharacterBody3D) -> Vector3:
	var cell := float(board_root.get("cell_size"))
	var width := float(token.call("get_footprint_cells")) * cell
	var height := float(token.get("token_height_cells")) * cell
	var offset := (width + float(reference.call("get_footprint_cells")) * cell) * 0.5
	var base := reference.global_position.y - float(reference.get("token_height_cells")) * cell * 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(width - cell * 0.04, 0.01), maxf(height - cell * 0.04, 0.01), maxf(width - cell * 0.04, 0.01))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = token.collision_mask
	query.exclude = [token.get_rid()]
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var candidate := Vector3(reference.global_position.x + direction.x * offset, base + height * 0.5, reference.global_position.z + direction.y * offset)
		var blocked := false
		# Include freshly placed bodies before their next physics update.
		for other: Node in get_tree().get_nodes_in_group("dnd_token"):
			if other == token or other.is_queued_for_deletion() or not board_root.is_ancestor_of(other):
				continue
			var other_half := float(other.call("get_footprint_cells")) * cell * 0.5
			var other_height := float(other.get("token_height_cells")) * cell
			var delta: Vector3 = (other as Node3D).global_position - candidate
			if absf(delta.x) < width * 0.5 + other_half - cell * 0.02 and absf(delta.z) < width * 0.5 + other_half - cell * 0.02 and absf(delta.y) < (height + other_height) * 0.5 - cell * 0.02:
				blocked = true
				break
		if blocked:
			continue
		query.transform = Transform3D(token.global_basis.orthonormalized(), candidate)
		if not token.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		var validator: Callable = token.get("movement_validator")
		if validator.is_valid() and not validator.call(token, candidate):
			continue
		return candidate
	return Vector3.INF
