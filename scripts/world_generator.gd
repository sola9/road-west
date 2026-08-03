class_name WorldGenerator
extends Node

@export var floating_origin: FloatingOrigin

@export_category("World")
@export var world_seed: int = 12345


@export_category("Terrain Shape")
@export var macro_height: float = 7.5
@export var rolling_height: float = 4.5
@export var mesa_height: float = 4.5
@export var ridge_height: float = 2.75
@export var detail_height: float = 0.6
@export_range(0.0, 1.0) var lowland_depth: float = 0.55


@export_category("Road Shape")
@export var road_width: float = 8.0
@export var road_blend_width: float = 18.0
@export var road_curve_amplitude: float = 90.0
@export var road_curve_sample_distance: float = 2.0


@export_category("Road Earthworks")
@export var road_ground_sample_spacing: float = 24.0
@export_range(1, 10) var road_ground_sample_radius: int = 4
@export var road_max_cut_depth: float = 1.0
@export var road_ground_clearance: float = 0.15
@export var road_valley_floor: float = 1.75
@export var road_valley_variation: float = 1.5

# Include these if you added the later embankment controls.
@export var road_embankment_trigger: float = 1.25
@export var road_embankment_transition: float = 1.0
@export var road_max_embankment_height: float = 1.5


var terrain_noise := FastNoiseLite.new()
var rolling_noise := FastNoiseLite.new()
var mesa_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()

var road_curve_noise := FastNoiseLite.new()
var road_height_noise := FastNoiseLite.new()

var road_height_cache: Dictionary = {}
var is_configured := false


func _ready() -> void:
	ensure_configured()
	
	if floating_origin != null:
		if not floating_origin.origin_shifted.is_connected(
			_on_origin_shifted
		):
			floating_origin.origin_shifted.connect(
				_on_origin_shifted
			)


func ensure_configured() -> void:
	if is_configured:
		return

	_configure_noise()
	road_height_cache.clear()
	is_configured = true
	
func _configure_noise() -> void:
	# ---------------------------------------------------------
	# Broad regional terrain
	# ---------------------------------------------------------
	terrain_noise.seed = world_seed
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.0011
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 3
	terrain_noise.fractal_gain = 0.45
	terrain_noise.fractal_lacunarity = 2.0

	# ---------------------------------------------------------
	# Medium-scale rolling desert hills
	# ---------------------------------------------------------
	rolling_noise.seed = world_seed + 3127
	rolling_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rolling_noise.frequency = 0.0028
	rolling_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	rolling_noise.fractal_octaves = 3
	rolling_noise.fractal_gain = 0.4
	rolling_noise.fractal_lacunarity = 2.0

	# ---------------------------------------------------------
	# Mesa regions
	# ---------------------------------------------------------
	mesa_noise.seed = world_seed + 6211
	mesa_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mesa_noise.frequency = 0.0008
	mesa_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	mesa_noise.fractal_octaves = 2
	mesa_noise.fractal_gain = 0.4

	# Distort the mesa regions so their boundaries are less round.
	mesa_noise.domain_warp_enabled = true
	mesa_noise.domain_warp_type = \
		FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	mesa_noise.domain_warp_amplitude = 90.0
	mesa_noise.domain_warp_frequency = 0.0012
	mesa_noise.domain_warp_fractal_type = \
		FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE

	# ---------------------------------------------------------
	# Ridgelines
	# ---------------------------------------------------------
	ridge_noise.seed = world_seed + 9473
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.frequency = 0.002
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.fractal_octaves = 2
	ridge_noise.fractal_gain = 0.4

	# ---------------------------------------------------------
	# Fine surface detail
	# ---------------------------------------------------------
	detail_noise.seed = world_seed + 9137
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.03
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 2
	detail_noise.fractal_gain = 0.4

	# ---------------------------------------------------------
	# Horizontal road curves
	# ---------------------------------------------------------
	road_curve_noise.seed = world_seed + 27183
	road_curve_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	road_curve_noise.frequency = 0.0007
	road_curve_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

	# ---------------------------------------------------------
	# Raised road profile through low areas
	# ---------------------------------------------------------
	road_height_noise.seed = world_seed + 41729
	road_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	road_height_noise.frequency = 0.0015
	road_height_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

func noise_to_zero_one(value: float) -> float:
	return clampf(
		value * 0.5 + 0.5,
		0.0,
		1.0
	)

func get_natural_height(
	world_x: float,
	world_z: float
) -> float:
	# ---------------------------------------------------------
	# 1. Broad regional elevation
	# ---------------------------------------------------------
	var macro_value := terrain_noise.get_noise_2d(
		world_x,
		world_z
	)

	var macro_terrain := macro_value * macro_height

	# Make low regions shallower than high regions. This produces
	# wide desert basins without making them extremely deep.
	if macro_terrain < 0.0:
		macro_terrain *= lowland_depth

	# ---------------------------------------------------------
	# 2. Medium-scale rolling hills
	# ---------------------------------------------------------
	var rolling_terrain := rolling_noise.get_noise_2d(
		world_x,
		world_z
	) * rolling_height

	# ---------------------------------------------------------
	# 3. Mesa regions
	# ---------------------------------------------------------
	var mesa_source := noise_to_zero_one(
		mesa_noise.get_noise_2d(
			world_x,
			world_z
		)
	)

	# Values below 0.58 produce no mesa.
	# Values above 0.76 produce the flat mesa height.
	var mesa_shape := smoothstep(
		0.58,
		0.76,
		mesa_source
	)

	var mesa_terrain := mesa_shape * mesa_height

	# ---------------------------------------------------------
	# 4. Ridgelines
	# ---------------------------------------------------------
	var ridge_source := ridge_noise.get_noise_2d(
		world_x,
		world_z
	)

	# Noise values near zero form the center of a ridge.
	var ridge_center := clampf(
		1.0 - absf(ridge_source),
		0.0,
		1.0
	)

	var ridge_shape := smoothstep(
		0.72,
		0.93,
		ridge_center
	)

	# Ridges are more common around higher mesa regions.
	var ridge_region_mask := smoothstep(
		0.4,
		0.7,
		mesa_source
	)

	var ridge_terrain := (
		ridge_shape
		* ridge_height
		* ridge_region_mask
	)

	# ---------------------------------------------------------
	# 5. Small surface detail
	# ---------------------------------------------------------
	var surface_detail := detail_noise.get_noise_2d(
		world_x,
		world_z
	) * detail_height

	return (
		macro_terrain
		+ rolling_terrain
		+ mesa_terrain
		+ ridge_terrain
		+ surface_detail
	)

func get_world_height(
	world_x: float,
	world_z: float
) -> float:
	var natural_height := get_natural_height(
		world_x,
		world_z
	)

	var road_center_x := get_road_center_x(world_z)

	var distance_from_road := absf(
		world_x - road_center_x
	)

	var road_base_height := get_road_height(world_z)

	var flatten_start := road_width * 0.5
	var flatten_end := flatten_start + road_blend_width

	var terrain_weight := smoothstep(
		flatten_start,
		flatten_end,
		distance_from_road
	)

	return lerpf(
		road_base_height,
		natural_height,
		terrain_weight
	)
	
func get_road_height(world_z: float) -> float:
	# Snapping avoids nearly identical floating-point values becoming
	# separate dictionary keys.
	var cache_key := snappedf(world_z, 0.01)

	if road_height_cache.has(cache_key):
		return road_height_cache[cache_key] as float

	var result := calculate_road_height(world_z)
	road_height_cache[cache_key] = result

	return result
	
func calculate_road_height(world_z: float) -> float:
	var road_center_x := get_road_center_x(world_z)

	var local_ground := get_natural_height(
		road_center_x,
		world_z
	)

	var smoothed_ground := get_smoothed_ground_below_road(
		world_z
	)

	# Normal terrain-following road profile.
	var hill_following_height := maxf(
		smoothed_ground,
		local_ground - road_max_cut_depth
	)

	hill_following_height += road_ground_clearance

	# Optional raised profile through valleys.
	var raised_valley_height := (
		road_height_noise.get_noise_1d(world_z)
		* road_valley_variation
		+ road_valley_floor
	)

	var valley_difference := (
		raised_valley_height
		- hill_following_height
	)

	var target_height := hill_following_height

	# Only activate the raised valley profile when it exceeds
	# the regular road profile by a meaningful amount.
	if valley_difference > road_embankment_trigger:
		var activation := smoothstep(
			road_embankment_trigger,
			road_embankment_trigger
				+ road_embankment_transition,
			valley_difference
		)

		# Subtracting the trigger prevents a sudden height jump
		# when the embankment first activates.
		var activated_valley_height := (
			raised_valley_height
			- road_embankment_trigger
		)

		target_height = lerpf(
			hill_following_height,
			maxf(
				hill_following_height,
				activated_valley_height
			),
			activation
		)

	# Prevent terrain smoothing or the valley profile from creating
	# an excessively tall embankment.
	var maximum_allowed_height := (
		local_ground
		+ road_ground_clearance
		+ road_max_embankment_height
	)

	return minf(
		target_height,
		maximum_allowed_height
	)
	
func get_road_center_x(world_z: float) -> float:
	return road_curve_noise.get_noise_1d(world_z) * road_curve_amplitude
	
func get_road_side_direction(world_z: float) -> Vector2:
	var sample_distance := road_curve_sample_distance

	var previous_center_x := get_road_center_x(
		world_z - sample_distance
	)

	var next_center_x := get_road_center_x(
		world_z + sample_distance
	)

	var tangent := Vector2(
		next_center_x - previous_center_x,
		sample_distance * 2.0
	).normalized()

	return Vector2(tangent.y, -tangent.x)
	
func get_smoothed_ground_below_road(
	world_z: float
) -> float:
	var weighted_height := 0.0
	var total_weight := 0.0

	for sample_offset in range(
		-road_ground_sample_radius,
		road_ground_sample_radius + 1
	):
		var sample_z := (
			world_z
			+ float(sample_offset)
			* road_ground_sample_spacing
		)

		var sample_x := get_road_center_x(sample_z)

		# Samples near the requested position have more influence.
		var sample_weight := float(
			road_ground_sample_radius
			+ 1
			- absi(sample_offset)
		)

		var sample_height := get_natural_height(
			sample_x,
			sample_z
		)

		weighted_height += sample_height * sample_weight
		total_weight += sample_weight

	if total_weight <= 0.0:
		return 0.0

	return weighted_height / total_weight
	
func clear_runtime_caches() -> void:
	road_height_cache.clear()
	
func _on_origin_shifted(_shift: Vector3) -> void:
	clear_runtime_caches()
