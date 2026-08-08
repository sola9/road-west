class_name PropManager
extends Node3D


@export_category("References")

@export var player: Node3D
@export var world_generator: WorldGenerator
@export var biome_generator: BiomeGenerator
@export var floating_origin: FloatingOrigin


@export_category("Streaming")

@export_range(32.0, 512.0, 32.0, "suffix:m")
var chunk_size: float = 128.0

@export_range(1, 12, 1)
var render_distance: int = 4

@export_range(0, 4, 1)
var unload_margin: int = 1


@export_category("Generation Queue")

@export_range(0.5, 20.0, 0.5)
var generation_budget_ms: float = 2.0

@export_range(1, 4, 1)
var max_chunks_per_frame: int = 1


@export_category("Placement")

@export_range(0.25, 10.0, 0.25, "suffix:m")
var slope_sample_distance: float = 2.0


var loaded_chunks: Dictionary = {}
var desired_chunks: Dictionary = {}
var queued_chunks: Dictionary = {}

var generation_queue: Array[Vector2i] = []

var current_player_chunk: Vector2i = Vector2i.ZERO
var has_current_player_chunk: bool = false


var prop_definitions: Array[BiomePropDefinition] = []

# BiomePropDefinition -> maximum density found in any biome.
var maximum_density_by_prop: Dictionary = {}

func _ready() -> void:
	if player == null:
		push_error(
			"PropManager does not have a player assigned."
		)
		return

	if world_generator == null:
		push_error(
			"PropManager does not have a WorldGenerator assigned."
		)
		return

	if biome_generator == null:
		push_error(
			"PropManager does not have a BiomeGenerator assigned."
		)
		return

	if floating_origin == null:
		push_error(
			"PropManager does not have a FloatingOrigin assigned."
		)
		return

	world_generator.ensure_configured()

	_build_prop_registry()

	if not floating_origin.origin_shifted.is_connected(
		_on_origin_shifted
	):
		floating_origin.origin_shifted.connect(
			_on_origin_shifted
		)

	_update_chunks(true)
	
func _process(_delta: float) -> void:
	_update_chunks(false)
	_process_generation_queue()
	
func _build_prop_registry() -> void:
	prop_definitions.clear()
	maximum_density_by_prop.clear()

	for biome in biome_generator.biomes:
		if biome == null:
			continue

		for rule in biome.prop_rules:
			if rule == null:
				continue

			if rule.prop == null:
				continue

			var definition: BiomePropDefinition = (
				rule.prop
			)

			if not prop_definitions.has(
				definition
			):
				prop_definitions.append(
					definition
				)

			var current_maximum: float = float(
				maximum_density_by_prop.get(
					definition,
					0.0
				)
			)

			var rule_density := maxf(
				rule.density_per_square_km,
				0.0
			)

			if rule_density > current_maximum:
				maximum_density_by_prop[
					definition
				] = rule_density
				
func _world_position_to_chunk(
	local_position: Vector3
) -> Vector2i:
	var absolute_x := (
		floating_origin.local_to_absolute_x(
			float(local_position.x)
		)
	)

	var absolute_z := (
		floating_origin.local_to_absolute_z(
			float(local_position.z)
		)
	)

	return Vector2i(
		floori(
			(absolute_x + chunk_size * 0.5)
			/ chunk_size
		),
		floori(
			(absolute_z + chunk_size * 0.5)
			/ chunk_size
		)
	)
	
func _update_chunks(force_update: bool) -> void:
	var new_player_chunk := (
		_world_position_to_chunk(
			player.global_position
		)
	)

	if (
		not force_update
		and has_current_player_chunk
		and new_player_chunk
			== current_player_chunk
	):
		return

	current_player_chunk = new_player_chunk
	has_current_player_chunk = true

	desired_chunks.clear()

	for offset_z in range(
		-render_distance,
		render_distance + 1
	):
		for offset_x in range(
			-render_distance,
			render_distance + 1
		):
			var coordinate := (
				current_player_chunk
				+ Vector2i(
					offset_x,
					offset_z
				)
			)

			desired_chunks[coordinate] = true

			if not loaded_chunks.has(
				coordinate
			):
				_queue_chunk(coordinate)

	var chunks_to_remove: Array[Vector2i] = []

	for key in loaded_chunks.keys():
		var coordinate: Vector2i = key

		if _is_chunk_in_range(
			coordinate,
			render_distance + unload_margin
		):
			continue

		chunks_to_remove.append(
			coordinate
		)

	for coordinate in chunks_to_remove:
		var chunk: PropChunk = (
			loaded_chunks.get(coordinate)
			as PropChunk
		)

		loaded_chunks.erase(coordinate)

		if is_instance_valid(chunk):
			chunk.queue_free()

	_sort_generation_queue()
	
func _is_chunk_in_range(
	coordinate: Vector2i,
	distance: int
) -> bool:
	var offset := (
		coordinate - current_player_chunk
	)

	return (
		absi(offset.x) <= distance
		and absi(offset.y) <= distance
	)
	
func _queue_chunk(
	coordinate: Vector2i
) -> void:
	if queued_chunks.has(coordinate):
		return

	if loaded_chunks.has(coordinate):
		return

	queued_chunks[coordinate] = true
	generation_queue.append(coordinate)
	
func _sort_generation_queue() -> void:
	generation_queue.sort_custom(
		_compare_chunk_priority
	)


func _compare_chunk_priority(
	first: Vector2i,
	second: Vector2i
) -> bool:
	return (
		_get_chunk_distance_squared(first)
		>
		_get_chunk_distance_squared(second)
	)


func _get_chunk_distance_squared(
	coordinate: Vector2i
) -> int:
	var offset := (
		coordinate - current_player_chunk
	)

	return (
		offset.x * offset.x
		+ offset.y * offset.y
	)
	
func _process_generation_queue() -> void:
	if generation_queue.is_empty():
		return

	var frame_start_usec := (
		Time.get_ticks_usec()
	)

	var processed_count := 0

	while (
		not generation_queue.is_empty()
		and processed_count
			< max_chunks_per_frame
	):
		var elapsed_usec := (
			Time.get_ticks_usec()
			- frame_start_usec
		)

		if (
			elapsed_usec
			>= generation_budget_ms * 1000.0
		):
			break

		var coordinate: Vector2i = (
			generation_queue.pop_back()
		)

		queued_chunks.erase(coordinate)

		if not desired_chunks.has(
			coordinate
		):
			continue

		if loaded_chunks.has(
			coordinate
		):
			continue

		_create_chunk(coordinate)

		processed_count += 1
		
func _create_chunk(
	coordinate: Vector2i
) -> void:
	var chunk := PropChunk.new()

	add_child(chunk)

	chunk.setup(
		coordinate,
		chunk_size,
		floating_origin
	)

	loaded_chunks[coordinate] = chunk

	for definition in prop_definitions:
		if definition == null:
			continue

		if definition.mesh == null:
			continue

		var transforms := (
			_generate_prop_transforms(
				chunk,
				definition
			)
		)

		chunk.add_prop_instances(
			definition,
			transforms
		)
		
func _generate_prop_transforms(
	chunk: PropChunk,
	definition: BiomePropDefinition
) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []

	var maximum_density: float = float(
		maximum_density_by_prop.get(
			definition,
			0.0
		)
	)

	if maximum_density <= 0.0:
		return transforms

	var square_meters := (
		chunk_size * chunk_size
	)

	var square_kilometers := (
		square_meters / 1000000.0
	)

	var expected_candidates := (
		maximum_density
		* square_kilometers
	)

	var candidate_count := floori(
		expected_candidates
	)

	var fractional_candidate := (
		expected_candidates
		- float(candidate_count)
	)

	var random := RandomNumberGenerator.new()

	random.seed = _get_prop_seed(
		chunk.chunk_coordinate,
		definition.spawn_seed_offset
	)

	if random.randf() < fractional_candidate:
		candidate_count += 1

	for _candidate_index in range(
		candidate_count
	):
		var local_x := random.randf_range(
			0.0,
			chunk_size
		)

		var local_z := random.randf_range(
			0.0,
			chunk_size
		)

		var world_x := (
			chunk.absolute_origin_x
			+ local_x
		)

		var world_z := (
			chunk.absolute_origin_z
			+ local_z
		)

		var biome_sample := (
			biome_generator.sample(
				world_x,
				world_z
			)
		)

		var local_density := (
			_get_local_prop_density(
				definition,
				biome_sample
			)
		)

		if local_density <= 0.0:
			continue

		var spawn_probability := clampf(
			local_density
			/ maximum_density,
			0.0,
			1.0
		)

		if random.randf() > spawn_probability:
			continue

		if not _passes_road_clearance(
			definition,
			world_x,
			world_z
		):
			continue

		var height := (
			world_generator.get_world_height(
				world_x,
				world_z
			)
		)

		if not _passes_slope_check(
			definition,
			world_x,
			world_z
		):
			continue

		var scale := random.randf_range(
			definition.minimum_scale,
			definition.maximum_scale
		)

		var yaw := 0.0

		if definition.random_y_rotation:
			yaw = random.randf_range(
				0.0,
				TAU
			)

		var basis := Basis(
			Vector3.UP,
			yaw
		)

		basis = basis.scaled(
			Vector3.ONE * scale
		)

		var local_position := Vector3(
			local_x,
			height
				+ definition.vertical_offset,
			local_z
		)

		transforms.append(
			Transform3D(
				basis,
				local_position
			)
		)

	return transforms
	
func _get_local_prop_density(
	definition: BiomePropDefinition,
	sample: BiomeSample
) -> float:
	if sample == null:
		return 0.0

	if sample.primary_biome == null:
		return 0.0

	var primary_density := (
		sample.primary_biome.get_prop_density(
			definition
		)
	)

	var secondary_density := 0.0

	if sample.secondary_biome != null:
		secondary_density = (
			sample.secondary_biome
				.get_prop_density(
					definition
				)
		)

	return (
		primary_density
			* sample.primary_weight
		+
		secondary_density
			* sample.secondary_weight
	)
	
func _get_prop_seed(
	coordinate: Vector2i,
	prop_seed_offset: int
) -> int:
	var result: int = (
		world_generator.world_seed
	)

	result ^= (
		coordinate.x * 73856093
	)

	result ^= (
		coordinate.y * 19349663
	)

	result ^= (
		prop_seed_offset * 83492791
	)

	return result
	
func _passes_road_clearance(
	definition: BiomePropDefinition,
	world_x: float,
	world_z: float
) -> bool:
	var road_center_x := (
		world_generator.get_road_center_x(
			world_z
		)
	)

	var distance_from_center := absf(
		world_x - road_center_x
	)

	var minimum_distance := (
		world_generator.road_width * 0.5
		+ definition.road_clearance
	)

	return (
		distance_from_center
		>= minimum_distance
	)
	
func _passes_slope_check(
	definition: BiomePropDefinition,
	world_x: float,
	world_z: float
) -> bool:
	if (
		definition.maximum_slope_degrees
		>= 89.0
	):
		return true

	var distance := slope_sample_distance

	var left_height := (
		world_generator.get_world_height(
			world_x - distance,
			world_z
		)
	)

	var right_height := (
		world_generator.get_world_height(
			world_x + distance,
			world_z
		)
	)

	var back_height := (
		world_generator.get_world_height(
			world_x,
			world_z - distance
		)
	)

	var forward_height := (
		world_generator.get_world_height(
			world_x,
			world_z + distance
		)
	)

	var normal := Vector3(
		left_height - right_height,
		distance * 2.0,
		back_height - forward_height
	).normalized()

	var slope_radians := acos(
		clampf(
			normal.dot(Vector3.UP),
			-1.0,
			1.0
		)
	)

	var slope_degrees := rad_to_deg(
		slope_radians
	)

	return (
		slope_degrees
		<= definition.maximum_slope_degrees
	)
	
func _on_origin_shifted(
	shift: Vector3
) -> void:
	for key in loaded_chunks.keys():
		var coordinate: Vector2i = key

		var chunk: PropChunk = (
			loaded_chunks.get(coordinate)
			as PropChunk
		)

		if not is_instance_valid(chunk):
			continue

		chunk.global_position -= shift
		chunk.reset_physics_interpolation()
		
