extends RefCounted
## Desktop helper. Runs only fixed, argument-separated Tailscale commands.
## Never invokes Funnel or a shell. Does not erase unrelated Serve mappings.
const LOCAL_PORT := 8765

# Nonblocking pipes keep the board and loopback PWA server responsive even
# while Tailscale waits for browser approval or an unavailable daemon.
static func _run_process(binary: String, arguments: PackedStringArray, timeout_ms: int = 15000) -> Dictionary:
	var process := OS.execute_with_pipe(binary, arguments, false)
	if process.is_empty():
		return {"ok": false, "started": false, "message": "Installa Tailscale e accedi alla tua tailnet."}
	var pid: int = process.pid
	var output := PackedByteArray()
	var errors := PackedByteArray()
	var deadline := Time.get_ticks_msec() + timeout_ms
	while true:
		output.append_array(process.stdio.get_buffer(65536))
		errors.append_array(process.stderr.get_buffer(65536))
		var running := OS.is_process_running(pid)
		if output.size() + errors.size() > 2 * 1024 * 1024 or (running and Time.get_ticks_msec() >= deadline):
			OS.kill(pid)
			process.stdio.close()
			process.stderr.close()
			return {"ok": false, "started": true, "message": "Tailscale non risponde entro il limite. Controlla Tailscale e l'eventuale autorizzazione nel browser, poi riprova. " + errors.get_string_from_utf8() + output.get_string_from_utf8()}
		if not running:
			# Drain remaining buffered output after exit, without blocking.
			var tail: PackedByteArray = process.stdio.get_buffer(65536)
			var error_tail: PackedByteArray = process.stderr.get_buffer(65536)
			output.append_array(tail)
			errors.append_array(error_tail)
			if tail.is_empty() and error_tail.is_empty():
				break
		await (Engine.get_main_loop() as SceneTree).process_frame
	var exit_code := OS.get_process_exit_code(pid)
	process.stdio.close()
	process.stderr.close()
	return {"ok": exit_code == 0, "started": true,
		"message": output.get_string_from_utf8().strip_edges() if exit_code == 0 else (errors.get_string_from_utf8() + output.get_string_from_utf8()).strip_edges()}


static func _command(arguments: PackedStringArray) -> Dictionary:
	var binary := "tailscale"
	if OS.get_name() == "Windows" and FileAccess.file_exists("C:/Program Files/Tailscale/tailscale.exe"):
		binary = "C:/Program Files/Tailscale/tailscale.exe"
	return await _run_process(binary, arguments)


static func parse_serve_status(value: Variant) -> Dictionary:
	# The status payload can contain multiple HTTPS listeners, paths, and
	# TCP forwards. VTT may only touch the single root 443 -> localhost:8765.
	var current := false
	var occupied := false
	if not value is Dictionary:
		return {"active": false, "other_rules": false}
	var web_value: Variant = (value as Dictionary).get("Web", {})
	if web_value is Dictionary:
		for host_key: Variant in (web_value as Dictionary).keys():
			var host_value: Variant = (web_value as Dictionary)[host_key]
			if not host_value is Dictionary:
				continue
			var handlers: Variant = (host_value as Dictionary).get("Handlers", {})
			if not handlers is Dictionary:
				continue
			for path_value: Variant in (handlers as Dictionary).keys():
				var path_name := String(path_value)
				var handler: Variant = (handlers as Dictionary)[path_value]
				var proxy := ""
				if handler is Dictionary:
					proxy = String((handler as Dictionary).get("Proxy", "")).trim_suffix("/")
				if String(host_key).ends_with(":443") and path_name == "/" and proxy in [
					"http://127.0.0.1:8765",
					"http://localhost:8765"
				]:
					current = true
				else:
					occupied = true
	var tcp: Variant = (value as Dictionary).get("TCP", {})
	if tcp is Dictionary:
		for port_value: Variant in (tcp as Dictionary).keys():
			var port := String(port_value)
			var config: Variant = (tcp as Dictionary)[port_value]
			# Tailscale creates a TCP:443 HTTPS listener alongside Web:443.
			# It belongs to our web Serve, not a competing service.
			if port != "443" or not config is Dictionary or not bool((config as Dictionary).get("HTTPS", false)):
				occupied = true
	var services: Variant = (value as Dictionary).get("Services", {})
	if services is Dictionary and not (services as Dictionary).is_empty():
		occupied = true
	return {"active": current, "other_rules": occupied}


static func get_status() -> Dictionary:
	var result := await _command(PackedStringArray(["serve", "status", "--json"]))
	if not result.ok:
		return {"ok": false, "active": false, "other_rules": false, "message": result.message}
	var raw := String(result.message)
	# No Serve config is a normal, not an error, state.
	if raw.find("No serve config") >= 0 or raw.is_empty():
		return {"ok": true, "active": false, "other_rules": false, "message": ""}
	var parsed: Variant = JSON.parse_string(raw)
	if raw == "null":
		return {"ok": true, "active": false, "other_rules": false, "message": ""}
	if not parsed is Dictionary:
		return {"ok": false, "active": false, "other_rules": false, "message": "Impossibile leggere lo stato di Tailscale Serve."}
	var state := parse_serve_status(parsed)
	state["ok"] = true
	state["message"] = ""
	return state


static func set_enabled(enabled: bool) -> Dictionary:
	var state := await get_status()
	if not state.ok:
		return state
	if enabled == bool(state.active):
		return state
	if bool(state.other_rules):
		return {"ok": false, "active": state.active, "other_rules": true,
			"message": "Tailscale Serve contiene altre condivisioni: modifica manualmente la configurazione per non sovrascriverle."}
	# The explicit HTTPS port makes teardown avoid the blanket 'serve off'.
	var arguments := PackedStringArray(
		["serve", "--bg", "--yes", "--https=443", str(LOCAL_PORT)]
		if enabled else
		["serve", "--https=443", "off"]
	)
	var applied := await _command(arguments)
	if not applied.ok:
		return {"ok": false, "active": state.active, "other_rules": state.other_rules,
			"message": applied.message}
	var updated := await get_status()
	if updated.ok and bool(updated.active) != enabled:
		updated["ok"] = false
		updated["message"] = "Tailscale non ha confermato il nuovo stato."
	return updated
