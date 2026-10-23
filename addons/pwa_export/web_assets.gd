@tool
extends EditorExportPlugin
const Host = preload("res://network/pwa_host.gd")

func _get_name() -> String:
	return "PwaSourceAssets"

func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("pc"): return
	# Export filters do not retain source files for imported textures. The web
	# host needs SVG sprites and PNG bytes, not Godot's remapped .ctex resources.
	# Use the actual public allowlist so native icons and web icons stay in sync.
	var included: Dictionary = {}
	for asset: Array in Host.FILES.values():
		var source := String(asset[0])
		if source.get_extension() not in ["svg", "png"] or included.has(source): continue
		var bytes := FileAccess.get_file_as_bytes(source)
		if bytes.is_empty():
			push_error("Missing PWA export asset: " + source)
			continue
		add_file(source, bytes, false)
		included[source] = true
