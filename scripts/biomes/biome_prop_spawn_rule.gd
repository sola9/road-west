@tool
class_name BiomePropSpawnRule
extends Resource


@export var prop: BiomePropDefinition

@export_range(0.0, 10000.0, 1.0)
var density_per_square_km: float = 100.0
