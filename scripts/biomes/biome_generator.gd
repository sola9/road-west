class_name BiomeGenerator
extends Node


@export_category("Biomes")

@export var biomes: Array[BiomeDefinition] = []


@export_category("Region Generation")

# Approximate size of biome territories.
@export_range(1000.0, 100000.0, 1000.0)
var region_size: float = 30000.0

# Moves each region center away from a perfect grid.
@export_range(0.0, 0.45, 0.01)
var region_center_jitter: float = 0.35

# Physical width of the biome blending zone.
@export_range(100.0, 10000.0, 100.0)
var transition_width: float = 2500.0

# Curves otherwise straight Voronoi-style borders.
@export_range(0.0, 10000.0, 100.0)
var boundary_warp_amplitude: float = 3000.0

@export_range(0.000001, 0.001, 0.000001)
var boundary_warp_frequency: float = 0.00004

@export var maximum_cached_regions: int = 256

@export_category("Sediment")

@export_range(0.0001, 0.05, 0.0001)
var sediment_noise_frequency: float = 0.0015


var _world_seed: int = 0
var _configured: bool = false

var _region_cache: Dictionary = {}

var _warp_x_noise := FastNoiseLite.new()
var _warp_z_noise := FastNoiseLite.new()
var _sediment_noise := FastNoiseLite.new()


func configure(new_world_seed: int) -> void:
	_world_seed = new_world_seed

	_region_cache.clear()

	_warp_x_noise.seed = _world_seed + 4103
	_warp_x_noise.noise_type = (
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	)
	_warp_x_noise.frequency = boundary_warp_frequency

	_warp_z_noise.seed = _world_seed + 7919
	_warp_z_noise.noise_type = (
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	)
	_warp_z_noise.frequency = boundary_warp_frequency

	_sediment_noise.seed = _world_seed + 12011
	_sediment_noise.noise_type = (
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	)
	_sediment_noise.frequency = (
		sediment_noise_frequency
	)

	_configured = true
	
func sample(
	world_x: float,
	world_z: float
) -> BiomeSample:
	var result := BiomeSample.new()

	if biomes.is_empty():
		return result

	if not _configured:
		push_error(
			"BiomeGenerator.sample() called before configure()."
		)
		return result

	var warped_position := _get_warped_position(
		world_x,
		world_z
	)

	var base_cell := Vector2i(
		floori(
			warped_position.x / region_size
		),
		floori(
			warped_position.y / region_size
		)
	)

	var nearest_region: BiomeRegionPoint
	var second_region: BiomeRegionPoint

	var nearest_distance_squared := INF
	var second_distance_squared := INF

	# Search a 5x5 region around the queried point.
	for offset_z in range(-2, 3):
		for offset_x in range(-2, 3):
			var cell := (
				base_cell
				+ Vector2i(
					offset_x,
					offset_z
				)
			)

			var region := _get_region_point(cell)

			var distance_squared := (
				warped_position.distance_squared_to(
					region.center
				)
			)

			if (
				distance_squared
				< nearest_distance_squared
			):
				second_distance_squared = (
					nearest_distance_squared
				)

				second_region = nearest_region

				nearest_distance_squared = (
					distance_squared
				)

				nearest_region = region

			elif (
				distance_squared
				< second_distance_squared
			):
				second_distance_squared = (
					distance_squared
				)

				second_region = region

	if nearest_region == null:
		return result

	result.primary_biome = (
		biomes[nearest_region.biome_index]
	)

	if second_region == null:
		return result

	result.secondary_biome = (
		biomes[second_region.biome_index]
	)

	# If neighboring territories happen to choose the same biome,
	# they should visually behave as one larger biome.
	if (
		result.primary_biome
		== result.secondary_biome
	):
		result.secondary_weight = 0.0
		result.primary_weight = 1.0
		return result

	var nearest_distance := sqrt(
		nearest_distance_squared
	)

	var second_distance := sqrt(
		second_distance_squared
	)

	# Near a Voronoi border these distances become similar.
	var distance_difference := (
		second_distance
		- nearest_distance
	)

	# The factor of two converts the difference between the two
	# seed distances into approximately the physical transition
	# width around their boundary.
	var normalized_difference := clampf(
		distance_difference
		/ maxf(
			transition_width * 2.0,
			0.001
		),
		0.0,
		1.0
	)

	var boundary_falloff := smoothstep(
		0.0,
		1.0,
		normalized_difference
	)

	result.secondary_weight = (
		0.5
		* (1.0 - boundary_falloff)
	)

	result.primary_weight = (
		1.0
		- result.secondary_weight
	)

	return result
	
func _get_warped_position(
	world_x: float,
	world_z: float
) -> Vector2:
	var warp_x := (
		_warp_x_noise.get_noise_2d(
			world_x,
			world_z
		)
		* boundary_warp_amplitude
	)

	var warp_z := (
		_warp_z_noise.get_noise_2d(
			world_x,
			world_z
		)
		* boundary_warp_amplitude
	)

	return Vector2(
		world_x + warp_x,
		world_z + warp_z
	)


func _get_region_point(
	cell: Vector2i
) -> BiomeRegionPoint:
	if _region_cache.has(cell):
		var cached_region := (
			_region_cache.get(cell)
			as BiomeRegionPoint
		)

		if cached_region != null:
			return cached_region

	var random := RandomNumberGenerator.new()
	random.seed = _get_cell_seed(cell)

	var region := BiomeRegionPoint.new()

	var cell_center := Vector2(
		(float(cell.x) + 0.5) * region_size,
		(float(cell.y) + 0.5) * region_size
	)

	var maximum_jitter := (
		region_size
		* region_center_jitter
	)

	region.center = (
		cell_center
		+ Vector2(
			random.randf_range(
				-maximum_jitter,
				maximum_jitter
			),
			random.randf_range(
				-maximum_jitter,
				maximum_jitter
			)
		)
	)

	region.biome_index = _choose_biome_index(
		random.randf()
	)

	_region_cache[cell] = region
	
	if _region_cache.size() > maximum_cached_regions:
		_region_cache.clear()

		# Reinsert the region we just generated so this call
		# still leaves the requested region cached.
		_region_cache[cell] = region

	return region


func _get_cell_seed(
	cell: Vector2i
) -> int:
	var result := _world_seed

	result ^= (
		cell.x * 73856093
	)

	result ^= (
		cell.y * 19349663
	)

	return result


func _choose_biome_index(
	random_value: float
) -> int:
	var total_weight := 0.0

	for biome in biomes:
		if biome == null:
			continue

		total_weight += maxf(
			biome.selection_weight,
			0.0
		)

	if total_weight <= 0.0:
		return 0

	var target_weight := (
		random_value * total_weight
	)

	var accumulated_weight := 0.0
	var fallback_index := 0

	for index in range(biomes.size()):
		var biome: BiomeDefinition = biomes[index]

		if biome == null:
			continue

		fallback_index = index

		accumulated_weight += maxf(
			biome.selection_weight,
			0.0
		)

		if target_weight <= accumulated_weight:
			return index

	return fallback_index
	
func get_terrain_color(
	world_x: float,
	world_y: float,
	world_z: float,
	use_debug_color: bool = false
) -> Color:
	var biome_sample := sample(
		world_x,
		world_z
	)

	if biome_sample.primary_biome == null:
		return Color.WHITE

	if use_debug_color:
		return biome_sample.get_debug_color()

	var distortion_noise := (
		_sediment_noise.get_noise_2d(
			world_x,
			world_z
		)
	)

	var primary_color := (
		biome_sample.primary_biome.get_surface_tint(
			world_y,
			distortion_noise
		)
	)

	if (
		biome_sample.secondary_biome == null
		or biome_sample.secondary_weight <= 0.0
	):
		return primary_color

	var secondary_color := (
		biome_sample.secondary_biome.get_surface_tint(
			world_y,
			distortion_noise
		)
	)

	return primary_color.lerp(
		secondary_color,
		biome_sample.secondary_weight
	)
