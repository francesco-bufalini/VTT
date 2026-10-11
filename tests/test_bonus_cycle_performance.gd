extends SceneTree

# Reproducible synthetic benchmark. It does not open or write user:// files.
# Run: godot --headless --path . --script res://tests/test_bonus_cycle_performance.gd
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const VALUE_RUNS := 100
const NORMALIZE_RUNS := 25


func _initialize() -> void:
	call_deferred("run")


func _record() -> Dictionary:
	return {
		"kind": "character", "level": 3, "classes": [],
		"abilities": {"str": 14, "dex": 12, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"ability_bonuses": {},
		"max_hp_base": 18, "max_hp_bonus": 0,
		"armor_class_base": 12, "armor_class_bonus": 0,
		"speed_base": 30, "speed_bonus": 0,
		"initiative_bonus": 0,
		"proficiency_choices": [], "proficiency_origins": [],
		"formula_bonuses": [], "inventory": []
	}


func _grant(id: String, target: String, expression: String) -> Dictionary:
	return {"id": id, "target": target, "expression": expression, "origin_id": ""}


func _bench_value(label: String, record: Dictionary, target: String) -> void:
	var started: int = Time.get_ticks_usec()
	var checksum: int = 0
	for i: int in range(VALUE_RUNS):
		checksum += Bonuses.value(record, target)
	var elapsed: int = Time.get_ticks_usec() - started
	print("PERF bonus ", label, ": ", VALUE_RUNS, " calls in ",
		"%.3f" % (float(elapsed) / 1000.0), " ms (",
		"%.1f" % (float(elapsed) / float(VALUE_RUNS)),
		" us/call), checksum=", checksum)


func _bench_normalize(label: String, record: Dictionary) -> void:
	var store := PlayerStore.new()
	var started: int = Time.get_ticks_usec()
	var last: Dictionary = {}
	for i: int in range(NORMALIZE_RUNS):
		last = store.normalize_character(record)
	var elapsed: int = Time.get_ticks_usec() - started
	assert(not last.is_empty())
	print("PERF normalize ", label, ": ", NORMALIZE_RUNS, " calls in ",
		"%.3f" % (float(elapsed) / 1000.0), " ms (",
		"%.1f" % (float(elapsed) / float(NORMALIZE_RUNS)),
		" us/call)")


func run() -> void:
	print("PERF flags: skip_archive=", OS.get_environment("VTT_PERF_SKIP_INITIATIVE_ARCHIVE"),
		" skip_structured=", OS.get_environment("VTT_PERF_SKIP_STRUCTURED_BONUSES"))

	var plain: Dictionary = _record()
	assert(Bonuses.value(plain, "ability:str") == 14)

	var acyclic: Dictionary = _record()
	acyclic["formula_bonuses"] = [
		_grant("score", "ability:str", "2"),
		_grant("modifier", "ability_mod:str", "1"),
		_grant("initiative", "initiative", "str_mod")
	]
	assert(Bonuses.value(acyclic, "ability:str") == 16)
	assert(Bonuses.value(acyclic, "ability_mod:str") == 4)
	assert(Bonuses.value(acyclic, "initiative") == 5,
		"An acyclic formula chain must have stable effective values")

	var self_cycle: Dictionary = _record()
	self_cycle["formula_bonuses"] = [_grant("self", "ability:str", "str_mod")]
	assert(Bonuses.value(self_cycle, "ability:str") == 14,
		"A self-referential score/modifier bonus must be ignored")
	assert("Dipendenza circolare" in Bonuses.description(self_cycle, "ability:str"),
		"Direct circular references should be diagnosed")

	var direct_cycle: Dictionary = _record()
	direct_cycle["formula_bonuses"] = [_grant("self", "ability:str", "str_score + 1")]
	assert(Bonuses.value(direct_cycle, "ability:str") == 14)

	var mutual: Dictionary = _record()
	mutual["formula_bonuses"] = [
		_grant("str_depends_dex", "ability:str", "dex_mod + 2"),
		_grant("dex_depends_str", "ability:dex", "str_mod + 2")
	]
	var mutual_str: int = Bonuses.value(mutual, "ability:str")
	var mutual_dex: int = Bonuses.value(mutual, "ability:dex")
	for i: int in range(10):
		assert(Bonuses.value(mutual, "ability:str") == mutual_str)
		assert(Bonuses.value(mutual, "ability:dex") == mutual_dex)
	print("CYCLE mutual: STR=", mutual_str, " DEX=", mutual_dex,
		" (diagnostic only; partial circular-grant handling may be order dependent)")
	print("CYCLE mutual detail STR: ", Bonuses.description(mutual, "ability:str"))
	print("CYCLE mutual detail DEX: ", Bonuses.description(mutual, "ability:dex"))

	var long_cycle: Dictionary = _record()
	long_cycle["formula_bonuses"] = [
		_grant("a", "ability:str", "dex_mod"),
		_grant("b", "ability:dex", "wis_mod"),
		_grant("c", "ability:wis", "str_mod")
	]
	print("CYCLE long: STR=", Bonuses.value(long_cycle, "ability:str"),
		" DEX=", Bonuses.value(long_cycle, "ability:dex"),
		" WIS=", Bonuses.value(long_cycle, "ability:wis"))

	_bench_value("plain", plain, "initiative")
	_bench_value("acyclic", acyclic, "initiative")
	_bench_value("self_cycle", self_cycle, "ability:str")
	_bench_value("mutual_cycle", mutual, "ability:str")
	_bench_value("long_cycle", long_cycle, "ability:str")
	_bench_normalize("plain", plain)
	_bench_normalize("acyclic", acyclic)
	_bench_normalize("mutual_cycle", mutual)
	print("PASS: bonus cycle safety and synthetic performance diagnostics")
	quit()
