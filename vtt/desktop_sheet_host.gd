extends "res://network/pwa_host.gd"
## Static assets only. Private archive operations use the embedded WebView IPC,
## never the HTTP listener or the phone's PwaHost/pairing credential.

func _ready() -> void:
	set_process(false)

func start() -> Error:
	_token = "static-desktop-shell"
	_listen_port = 0
	return _start_listener()

func origin() -> String:
	return "http://127.0.0.1:%d" % _server.get_local_port()

func _input(_event: InputEvent) -> void:
	pass

func _handle_http(client: Dictionary, method: String, path: String, _headers: Dictionary, _body: PackedByteArray) -> void:
	if method != "GET":
		_answer(client, 405, {"error": "static_only"})
		return
	if path == "/" or path == "/index.html":
		var html := FileAccess.get_file_as_string("res://pwa/index.html")
		html = html.replace('<script type="module" src="/main.js"></script>', '<script type="module" src="/desktop/main.js"></script>')
		html = html.replace("</head>", '<link rel="stylesheet" href="/desktop/desktop.css"></head>')
		html = html.replace("<title>VTT Mobile</title>", "<title>VTT · Creature</title>")
		_respond(client, 200, "text/html; charset=utf-8", html.to_utf8_buffer())
		return
	if path in ["/desktop/main.js", "/desktop/bridge.js", "/desktop/storage.js", "/desktop/desktop.css"]:
		var mime := "text/css" if path.ends_with(".css") else "text/javascript"
		_respond(client, 200, mime, FileAccess.get_file_as_bytes("res://pwa" + path))
		return
	if path == "/sw.js":
		_answer(client, 404, {"error": "no_desktop_service_worker"})
		return
	if path == "/api/status":
		_answer(client, 200, {"protocol": 1, "desktop_online": false})
		return
	if path == "/catalog/bestiary.json" or path.begins_with("/catalog/bestiary/"):
		_serve_bestiary(client, path)
		return
	if path == "/catalog/spells.json":
		_respond(client, 200, "application/json", public_spells_json())
		return
	if FILES.has(path):
		var asset: Array = FILES[path]
		var bytes := FileAccess.get_file_as_bytes(asset[0])
		if path.ends_with(".js"):
			# Remap the existing modules at delivery, leaving mobile sources intact.
			bytes = bytes.get_string_from_utf8().replace('"./storage.js"', '"/desktop/storage.js"').replace("'./storage.js'", "'/desktop/storage.js'").to_utf8_buffer()
		_respond(client, 200, asset[1], bytes)
		return
	_answer(client, 404, {"error": "not_found"})
