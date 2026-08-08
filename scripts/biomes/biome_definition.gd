@tool
class_name BiomeDefinition
extends Resource


@export_category("Identity")

@export var biome_name: String = "New Biome"

@export_range(0.0, 100.0, 0.1)
var selection_weight: float = 1.0

# Used only when biome debug coloring is enabled.
@export var debug_color: Color = Color.MAGENTA


@export_category("Terrain Appearance")

# The desired terrain color for this biome.
@export var terrain_tint: Color = Color(
	0.72,
	0.58,
	0.40,
	1.0
)


@export_category("Sediment Layers")

@export var sediment_enabled: bool = false

@export_range(0.0, 1.0, 0.01)
var sediment_strength: float = 1.0

# Height of one sediment band in meters.
@export_range(0.25, 50.0, 0.25)
var sediment_layer_height: float = 4.0

# Amount that the layers can bend vertically.
@export_range(0.0, 20.0, 0.1)
var sediment_distortion: float = 1.5

# Fraction of each band used to blend into the next one.
@export_range(0.0, 0.5, 0.01)
var sediment_edge_blend: float = 0.08

@export var sediment_colors: Array[Color] = [
	Color(0.55, 0.20, 0.10, 1.0),
	Color(0.78, 0.36, 0.16, 1.0),
	Color(0.72, 0.55, 0.34, 1.0),
	Color(0.44, 0.16, 0.09, 1.0)
]

@export_category("Props")

@export var prop_rules: Array[BiomePropSpawnRule] = []

func get_surface_tint(
	world_y: float,
	distortion_noise: float
) -> Color:
	if (
		not sediment_enabled
		or sediment_colors.size() < 2
	):
		return terrain_tint

	var layer_height := maxf(
		sediment_layer_height,
		0.001
	)

	var shifted_height := (
		world_y
		+ distortion_noise
		* sediment_distortion
	)

	var layer_position := (
		shifted_height / layer_height
	)

	var layer_number := floori(
		layer_position
	)

	var layer_fraction := fposmod(
		layer_position,
		1.0
	)

	var color_count := sediment_colors.size()

	var current_index := posmod(
		layer_number,
		color_count
	)

	var next_index := posmod(
		layer_number + 1,
		color_count
	)

	var current_color: Color = (
		sediment_colors[current_index]
	)

	var next_color: Color = (
		sediment_colors[next_index]
	)

	var next_color_amount := 0.0

	if sediment_edge_blend > 0.0:
		var blend_start := (
			1.0 - sediment_edge_blend
		)

		next_color_amount = smoothstep(
			blend_start,
			1.0,
			layer_fraction
		)

	var sediment_color := current_color.lerp(
		next_color,
		next_color_amount
	)

	return terrain_tint.lerp(
		sediment_color,
		sediment_strength
	)
	
func get_prop_density(
	prop_definition: BiomePropDefinition
) -> float:
	if prop_definition == null:
		return 0.0

	for rule in prop_rules:
		if rule == null:
			continue

		if rule.prop == prop_definition:
			return maxf(
				rule.density_per_square_km,
				0.0
			)

	return 0.0
