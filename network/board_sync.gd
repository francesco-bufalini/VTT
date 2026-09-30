extends Node

signal status_changed(message: String)
const PORT := 45454
const SNAPSHOT_VERSION := 4
const MAGIC := "DND_MAP_SYNC_V4"
const BACKUP_DIR := "user://map_sync_backups"
const MAX_BACKUPS := 20
const MAX_BYTES := 4 * 1024 * 1024
const BULK_SEND_TIMEOUT_MS := 3000
const GROUPS := ["dnd_token", "tactical_platform", "encounter_obstacle"]
const TOKEN_CONDITIONS := [
	"blinded", "charmed", "deafened", "exhaustion", "frightened",
	"grappled", "incapacitated", "invisible", "paralyzed", "petrified",
	"poisoned", "prone", "restrained", "stunned", "unconscious",
	"concentrating", "surprised", "hidden", "dead"
]
var board_root: Node
var token_scene: PackedScene
var tokens_root: Node
var measurement_tool: Node
var server := TCPServer.new()
var connections: Array = []
var receiving := false
var session_key := ""
var _tailscale_last_error := ""
var _bulk_generation := 0
var _bulk_pending := 0
var _bulk_total := 0
var _bulk_accepted := 0
var _bulk_rejected := 0
var _bulk_failed := 0

func setup(root: Node, scene: PackedScene, tokens: Node, measure: Node) -> void:
	board_root = root
	token_scene = scene
	tokens_root = tokens
	measurement_tool = measure


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
	if not enabled:
		status_changed.emit("Ricezione disattivata")
		return OK
	if session_key.is_empty():
		status_changed.emit("Inserisci un codice sessione condiviso")
		return ERR_INVALID_PARAMETER
	var error := server.listen(PORT)
	receiving = error == OK
	status_changed.emit("In ascolto sulla porta TCP %d" % PORT if receiving else error_string(error))
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
		status_changed.emit("Connessione e invio in corso…")
	else:
		status_changed.emit(error_string(error))
	return error


func send_snapshot_to_tailnet(key: String) -> Error:
	var clean_key: String = key.strip_edges()
	if clean_key.is_empty():
		status_changed.emit("Numero partita non valido")
		return ERR_INVALID_PARAMETER

	var payload: PackedByteArray = _snapshot_payload(clean_key)
	if payload.is_empty():
		return ERR_BUSY

	var hosts: Array[String] = _tailscale_peer_ipv4s()
	if hosts.is_empty():
		status_changed.emit(
			"Nessun nodo Tailscale trovato. %s" % _tailscale_last_error
		)
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
			"Trovati %d nodi Tailscale, ma nessuna connessione è partita"
			% _bulk_total
		)
		return ERR_CANT_CONNECT

	status_changed.emit(
		"Trovati %d nodi Tailscale · invio in corso…" % _bulk_total
	)
	return OK


func _snapshot_payload(key: String) -> PackedByteArray:
	var snapshot: Dictionary = create_snapshot()
	if snapshot.is_empty():
		status_changed.emit("Attendi la fine dell'avanzamento")
		return PackedByteArray()

	var payload: PackedByteArray = JSON.stringify(
		{
			"magic": MAGIC,
			"key": key.strip_edges(),
			"snapshot": snapshot
		}
	).to_utf8_buffer()
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
	var error: Error = peer.connect_to_host(host, PORT)
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


func _tailscale_peer_ipv4s() -> Array[String]:
	_tailscale_last_error = ""
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
		_tailscale_last_error = (
			"Impossibile eseguire o leggere 'tailscale status --json'. "
			+ "Controlla che Tailscale sia installato."
		)
		return []

	var peers_value: Variant = (parsed as Dictionary).get("Peer", {})
	if not peers_value is Dictionary:
		_tailscale_last_error = "Il JSON di Tailscale non contiene Peer."
		return []

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

	if hosts.is_empty():
		_tailscale_last_error = "Il comando funziona, ma non ha restituito IPv4 peer."
	return hosts


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
		status_changed.emit(
			"Sincronizzazione conclusa · ricevute %d/%d · rifiutate %d · non raggiungibili %d"
			% [
				_bulk_accepted,
				_bulk_total,
				_bulk_rejected,
				_bulk_failed
			]
		)


func _process(_delta: float) -> void:
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
				if message.get("magic") != MAGIC:
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
						accepted = apply_snapshot(snapshot)
						if not accepted:
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

func valid_snapshot(snapshot: Variant) -> bool:
	if (
		not snapshot is Dictionary
		or int(snapshot.get("version", -1)) != SNAPSHOT_VERSION
		or snapshot.get("scene") != board_root.scene_file_path
	):
		return false
	if not snapshot.get("objects") is Array or snapshot.objects.size() > 4096 or not measurement_tool.valid_aoes(snapshot.get("aoes")):
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
	for item in snapshot.objects:
		if not item is Dictionary or not item.get("id") is String or item.id.is_empty() or ids.has(item.id):
			return false
		ids[item.id] = true
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
			for channel in ["r", "g", "b", "a"]:
				var value: Variant = item.color.get(channel)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 1:
					return false
			if not item.get("size_name") is String or not item.get("flying") is bool:
				return false
			if item.has("gravity_applied") and not item.get("gravity_applied") is bool:
				return false
			if item.has("support_id") and not item.get("support_id") is String:
				return false
			# V4 makes logical token state mandatory. This prevents an older
			# client from silently accepting a snapshot without names/conditions
			# and then broadcasting blank state back to the table.
			if not item.get("display_name") is String:
				return false
			if String(item.get("display_name", "")).length() > 80:
				return false
			if not item.get("conditions") is Array:
				return false
			var condition_values: Array = item.get("conditions", [])
			if condition_values.size() > TOKEN_CONDITIONS.size():
				return false
			var seen_conditions: Dictionary = {}
			for condition_value: Variant in condition_values:
				if not condition_value is String:
					return false
				var condition_id := String(condition_value)
				if not (condition_id in TOKEN_CONDITIONS) or seen_conditions.has(condition_id):
					return false
				seen_conditions[condition_id] = true
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
			if item.has("visual_asset"):
				if not item.get("visual_asset") is String:
					return false
				var visual_asset := String(item.get("visual_asset", ""))
				if (
					not visual_asset.is_empty()
					and not visual_asset.begins_with("res://assets/tokens/")
				):
					return false
		if not item.get("name") is String or not item.get("visible") is bool:
			return false
	return true

func create_snapshot() -> Dictionary:
	var objects: Array = []
	var seen := {}
	for group_name in GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or seen.has(node) or not board_root.is_ancestor_of(node) or node.is_queued_for_deletion(): continue
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
	return {
		"version": SNAPSHOT_VERSION,
		"scene": board_root.scene_file_path,
		"objects": objects,
		"aoes": aoes,
		"encounter": state,
		"initiative": initiative
	}

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
	_restore_token_supports(wanted)
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

func _sync_id(node: Node3D) -> String:
	if node.has_meta("sync_id"): return String(node.get_meta("sync_id"))
	var id := "path:" + String(board_root.get_path_to(node)); node.set_meta("sync_id",id); return id

func _serialize_node(node: Node3D, group_name: String) -> Dictionary:
	var data := {"id":_sync_id(node),"group":group_name,"path":String(board_root.get_path_to(node)),"scene":node.scene_file_path,"name":node.name,"transform":_transform(node.global_transform),"visible":node.visible}
	if group_name == "dnd_token":
		data["kind"]="token"; data["flying"]=bool(node.get("flying")); data["footprint"]=float(node.get("_footprint_cells")); data["size_name"]=String(node.get("_size_name")); data["color"]=_token_color(node)
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
		data["height_cells"] = float(node.get("token_height_cells"))
		data["display_name"] = (
			String(node.call("get_display_name"))
			if node.has_method("get_display_name")
			else ""
		)
		data["conditions"] = (
			node.call("get_conditions")
			if node.has_method("get_conditions")
			else []
		)
		if node.has_method("get_visual_asset_path"):
			data["visual_asset"] = String(node.call("get_visual_asset_path"))
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
	node.visible=bool(data.get("visible",true)); node.set_meta("sync_id",String(data.get("id","")))
	if data.get("kind","") == "token":
		# Applicare prima l'asset esplicito disattiva l'eventuale miniatura
		# di default caricata dal token_scene appena istanziato.
		if data.has("visual_asset") and node.has_method("set_visual_asset"):
			var visual_asset := String(data.get("visual_asset", ""))
			if not visual_asset.is_empty():
				node.call("set_visual_asset", visual_asset)
		if data.has("height_cells"):
			node.set(
				"token_height_cells",
				maxf(float(data.get("height_cells", 2.0)), 0.1)
			)
		if node.has_method("configure"): node.call("configure",_dict_color(data.get("color",{})),float(board_root.get("cell_size")),String(data.get("size_name","Medium")),float(data.get("footprint",1.0)))
		var gravity_applied: bool = bool(data.get("gravity_applied", false))
		if gravity_applied and node.has_method("apply_gravity"):
			node.call("apply_gravity")
		elif node.has_method("set_flying"):
			node.call("set_flying", true)
		if node.has_method("set_display_name"):
			node.call("set_display_name", String(data.get("display_name", "")))
		if node.has_method("set_conditions"):
			node.call("set_conditions", data.get("conditions", []))
	# configure() snaps tokens; restore the exact shared transform afterwards.
	node.global_transform = _dict_transform(data.get("transform", {}))

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
	var name:=dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".json"): files.append(name)
		name=dir.get_next()
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
