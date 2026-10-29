extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := root.get_node("TokenPackManager")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://vtt/data/token_catalog_offline.json"))
	assert(manager._accept_catalog_text(JSON.stringify(catalog), false))
	var count := 0
	for entry: Dictionary in catalog.tokens:
		if entry.get("release_tag", "") != "characters":
			continue
		count += 1
		var url := String(entry.token_image_url)
		assert(manager.get_bestiary_token_url(entry.id) == url)
		assert(FileAccess.get_sha256(entry.token_image_path) == entry.token_image_sha256)
		assert(manager.get_bestiary_texture(url) != null)
		# A pre-artwork cache must not erase the bundled image for the same PCK.
		var legacy := entry.duplicate(true)
		for key in ["token_image_url", "token_image_path", "token_image_sha256", "token_image_bytes"]:
			legacy.erase(key)
		assert(manager._accept_catalog_text(JSON.stringify({"tokens": [legacy]}), false))
		assert(manager.get_bestiary_token_url(entry.id) == url)
	assert(count == 12)
	assert(manager.get_bestiary_token_url("ape").contains("Ape.webp"))
	print("PASS: twelve character 2D tokens load offline, survive older caches and preserve bestiary lookup")
	quit()
