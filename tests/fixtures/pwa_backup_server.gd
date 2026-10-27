extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	await process_frame
	await process_frame
	var host := root.get_node("PwaHost")
	var probe := TCPServer.new()
	assert(probe.listen(0, "127.0.0.1") == OK)
	var port := probe.get_local_port()
	probe.stop()
	host.set("_listen_port", port)
	host.set("_token", "e".repeat(64))
	var store: RefCounted = host.get("_backup_store")
	var folder := OS.get_environment("VTT_BACKUP_TEST_DIR")
	assert(not folder.is_empty())
	store.set("root_path", folder)
	assert(host.call("_start_listener") == OK)
	print("BACKUP_TEST_ORIGIN=http://127.0.0.1:%d" % port)
