extends SceneTree

const Serve = preload("res://network/tailscale_serve.gd")
var frames := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--auth-child" in OS.get_cmdline_user_args():
		print("Serve is not enabled on your tailnet.\nTo enable, visit:\n\nhttps://login.tailscale.com/f/serve?node=test-node")
		await create_timer(10).timeout
		quit()
		return
	if "--slow-child" in OS.get_cmdline_user_args():
		OS.delay_msec(1000)
		print("child-output")
		quit()
		return
	assert(Serve.authorization_url("https://login.tailscale.com.evil/f/serve?node=x").is_empty())
	assert(Serve.authorization_url("https://login.tailscale.com/f/serve?node=x&redirect=evil").is_empty())
	var foreign_port := Serve.parse_serve_status({"Web": {"example.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8765"}}}}})
	assert(not foreign_port.active and foreign_port.other_rules, "Another HTTPS port must not be treated as VTT's 443 mapping")
	process_frame.connect(func() -> void: frames += 1)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/test_tailscale_async.gd", "--", "--slow-child"])
	var result: Dictionary = await Serve._run_process(OS.get_executable_path(), args, 10000)
	assert(result.ok, str(result))
	assert("child-output" in result.message, "Child output must be drained")
	assert(frames > 10, "External command must not block frames")
	var start := Time.get_ticks_msec()
	result = await Serve._run_process(OS.get_executable_path(), args, 150)
	assert(not result.ok and "entro il limite" in result.message)
	assert(Time.get_ticks_msec() - start < 3000, "Timeout must be bounded")
	args[args.size() - 1] = "--auth-child"
	start = Time.get_ticks_msec()
	result = await Serve._run_process(OS.get_executable_path(), args, 5000)
	assert(not result.ok and result.get("authorization_url", "") == "https://login.tailscale.com/f/serve?node=test-node", str(result))
	assert(Time.get_ticks_msec() - start < 4000, "Authorization must be detected before timeout")
	print("PASS: Tailscale commands preserve frames, capture output and time out")
	quit()
