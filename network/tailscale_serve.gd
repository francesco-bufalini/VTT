extends RefCounted
## Desktop helper. Runs only fixed, argument-separated Tailscale commands.
## Never invokes Funnel or a shell. Does not erase unrelated Serve mappings.
const LOCAL_PORT := 8765

static func _command(arguments: PackedStringArray) -> Dictionary:
	var binaries: Array[String] = ["tailscale"]
	if OS.get_name() == "Windows":
		binaries.append("C:\\Program Files\\Tailscale\\tailscale.exe")
	var last_message := "Installa Tailscale e accedi alla tua tailnet."
	for binary: String in binaries:
		var output: Array = []
		var exit_code := OS.execute(binary, arguments, output, true)
		var message := "\n".join(output).strip_edges()
		if exit_code == 0:
			return {"ok": true, "message": message}
		if not message.is_empty():
			last_message = message
	return {"ok": false, "message": last_message}


static func parse_serve_status(value: Variant) -> Dictionary:
	# The status payload can contain multiple HTTPS listeners, paths, and
	# TCP forwards. VTT may only touch the single root 443 -> localhost:8765.
	var current := false
	var occupied := false
	if not value is Dictionary:
		return {"active": false, "other_rules": false}
	var web_value: Variant = (value as Dictionary).get("Web", {})
	if web_value is Dictionary:
		for host_value: Variant in (web_value as Dictionary).values():
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
				if path_name == "/" and proxy in [
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
	var result := _command(PackedStringArray(["serve", "status", "--json"]))
	if not result.ok:
		return {"ok": false, "active": false, "other_rules": false, "message": result.message}
	var raw := String(result.message)
	# No Serve config is a normal, not an error, state.
	if raw.find("No serve config") >= 0 or raw.is_empty():
		return {"ok": true, "active": false, "other_rules": false, "message": ""}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null:
		return {"ok": true, "active": false, "other_rules": false, "message": ""}
	if not parsed is Dictionary:
		return {"ok": false, "active": false, "other_rules": false, "message": "Impossibile leggere lo stato di Tailscale Serve."}
	var state := parse_serve_status(parsed)
	state["ok"] = true
	state["message"] = ""
	return state


static func set_enabled(enabled: bool) -> Dictionary:
	var state := get_status()
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
	var applied := _command(arguments)
	if not applied.ok:
		return {"ok": false, "active": state.active, "other_rules": state.other_rules,
			"message": applied.message}
	var updated := get_status()
	if updated.ok and bool(updated.active) != enabled:
		updated["ok"] = false
		updated["message"] = "Tailscale non ha confermato il nuovo stato."
	return updated
