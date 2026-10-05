extends Node

signal seal_broken(index: int)
signal all_seals_broken
signal changed

const ANCHORS = ["ForeheadSealAnchor", "LeftWristSealAnchor", "RightWristSealAnchor"]
@export var break_damage: float = 100.0
var damage: Array[float] = [0.0, 0.0, 0.0]
var _visuals: Array[Node3D] = []
var _tweens: Array[Tween] = []
var _rings: Array[Mesh] = []
var _fragments: Array[MultiMeshInstance3D] = []
var _units: float

func setup(visual: Node3D, units: float) -> void:
	_units = units
	for anchor_name in ANCHORS:
		var anchor: Node3D = visual.get_node(anchor_name)
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 1.8 * units
		mesh.outer_radius = 2.5 * units
		mesh.rings = 48
		mesh.ring_segments = 12
		ring.mesh = mesh
		ring.rotation.x = PI / 2
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.8, 0.67, 0.35)
		material.metallic = 0.65
		material.emission_enabled = true
		material.emission = Color(0.7, 0.85, 1.0)
		material.emission_energy_multiplier = 1.8
		ring.material_override = material
		anchor.add_child(ring)
		_visuals.append(ring)
		_rings.append(mesh)
		var fragments := MultiMeshInstance3D.new()
		fragments.multimesh = MultiMesh.new()
		fragments.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var shard := BoxMesh.new()
		shard.size = Vector3(0.55,0.25,1.3)*units
		shard.material = material
		fragments.multimesh.mesh = shard
		fragments.multimesh.instance_count = 8
		fragments.visible = false
		ring.add_child(fragments)
		_fragments.append(fragments)

func register_damage(index: int, amount: float) -> void:
	if index < 0 or index >= 3 or not is_finite(amount) or amount <= 0 or damage[index] >= break_damage:
		return
	damage[index] = minf(break_damage, damage[index] + amount)
	if damage[index] >= break_damage:
		_animate_break(index)
		seal_broken.emit(index)
		if damage.all(func(value: float): return value >= break_damage):
			all_seals_broken.emit()
	changed.emit()

func restore(values: Array) -> void:
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for index in range(3):
		damage[index] = clampf(float(values[index]), 0, break_damage)
		if index < _visuals.size():
			_visuals[index].scale = Vector3.ONE
			_visuals[index].mesh = _rings[index]
			_visuals[index].rotation = Vector3(PI/2,0,0)
			_fragments[index].visible = false
			_visuals[index].visible = damage[index] < break_damage
	changed.emit()

func replay_break(index: int) -> void:
	if index < 0 or index >= _visuals.size():
		return
	for tween: Tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()
	var ring := _visuals[index]
	ring.visible = true
	ring.scale = Vector3.ONE
	ring.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	ring.mesh = _rings[index]
	_fragments[index].visible = false
	_animate_break(index)


func _animate_break(index: int) -> void:
	if index >= _visuals.size():
		return
	var ring := _visuals[index]
	ring.mesh = null
	_fragments[index].visible = true
	var tween := create_tween()
	_tweens.append(tween)
	tween.tween_method(func(t: float): _scatter(index,t),0.0,1.0,0.7)
	tween.tween_callback(func(): ring.visible = false)
	tween.tween_callback(func(): _tweens.erase(tween))

func _scatter(index: int, progress: float) -> void:
	for piece in range(8):
		var angle := TAU*piece/8.0
		var point := Vector3(cos(angle),0,sin(angle))*(2.2+progress*7.0)*_units
		point.z += progress*progress*5.0*_units
		var basis := Basis(Vector3.UP,angle+progress*3).scaled(Vector3.ONE*(1.0-progress*0.8))
		_fragments[index].multimesh.set_instance_transform(piece,Transform3D(basis,point))
