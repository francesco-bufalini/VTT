extends Resource
@export var giant_max_hp: float = 202.0
@export var regeneration_per_round: float = 10.0
@export var avatar_max_hp: float = 200.0

@export_range(1.0, 1000000.0) var slow_damage_threshold: float = 100.0
@export_range(0, 30) var hazard_cluster_min: int = 12
@export_range(0, 30) var hazard_cluster_max: int = 18
@export_range(1, 200) var hazard_cluster_size_min: int = 35
@export_range(1, 200) var hazard_cluster_size_max: int = 75
@export_range(1, 30) var obstacle_min_height_cells: int = 4
@export_range(0.01, 1.0) var obstacle_coverage_threshold: float = 0.5
@export_range(0.0, 1.0) var tall_debris_fraction: float = 0.4
@export_range(4, 20) var debris_max_height_cells: int = 8
@export var encounter_seed: int = 0
@export_range(0.05, 15.0) var advance_duration: float = 2.0
@export var block_collapsed_cells: bool = true
@export var debug_panel_enabled: bool = false
