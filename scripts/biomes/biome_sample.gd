class_name BiomeSample
extends RefCounted


var primary_biome: BiomeDefinition
var secondary_biome: BiomeDefinition

var primary_weight: float = 1.0
var secondary_weight: float = 0.0


func get_debug_color() -> Color:
	if primary_biome == null:
		return Color.WHITE

	if (
		secondary_biome == null
		or secondary_weight <= 0.0
	):
		return primary_biome.debug_color

	return primary_biome.debug_color.lerp(
		secondary_biome.debug_color,
		secondary_weight
	)
