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

@export_category("Collision Activation")

# Props inside this radius receive collision.
@export_range(10.0, 500.0, 5.0, "suffix:m")
var collision_activation_distance: float = 100.0

# Collision remains active until beyond this distance.
# This prevents rapid toggling at exactly 100 m.
@export_range(10.0, 600.0, 5.0, "suffix:m")
var collision_deactivation_distance: float = 130.0

# We do not need to rescan collision every physics frame.
@export_range(0.05, 1.0, 0.05, "suffix:s")
var collision_update_interval: float = 0.15

# Limits how many new physics bodies can appear in one update.
@export_range(1, 64, 1)
var maximum_activations_per_update: int = 12


@export_category("Collision Layers")

@export_flags_3d_physics
var prop_collision_layer: int = 1

@export_flags_3d_physics
var prop_collision_mask: int = 1


var loaded_chunks: Dictionary = {}
var desired_chunks: Dictionary = {}
var queued_chunks: Dictionary = {}

var generation_queue: Array[Vector2i] = []

var current_player_chunk: Vector2i = Vector2i.ZERO
var has_current_player_chunk: bool = false


var prop_definitions: Array[BiomePropDefinition] = []

# BiomePropDefinition -> maximum density found in any biome.
var maximum_density_by_prop: Dictionary = {}

var collision_root: Node3D

# candidate_id -> StaticBody3D
var active_collision_proxies: Dictionary = {}

var collision_proxy_pool: Array[StaticBody3D] = []

var collision_update_accumulator: float = 0.0

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
	collision_root = Node3D.new()
	collision_root.name = "PropCollisionProxies"
	add_child(collision_root)

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
		
		_release_collision_for_chunk(
			coordinate
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
		chunk.add_collision_candidates(
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

		var chunk := (
			loaded_chunks.get(coordinate)
			as PropChunk
		)

		if not is_instance_valid(chunk):
			continue

		chunk.global_position -= shift
		chunk.reset_physics_interpolation()

	for key in active_collision_proxies.keys():
		var candidate_id: String = key

		var body := (
			active_collision_proxies.get(
				candidate_id
			)
			as StaticBody3D
		)

		if not is_instance_valid(body):
			continue

		body.global_position -= shift
		body.reset_physics_interpolation()
		
func _physics_process(
	delta: float
) -> void:
	collision_update_accumulator += delta

	if (
		collision_update_accumulator
		< collision_update_interval
	):
		return

	collision_update_accumulator = 0.0

	_update_collision_proxies()
	
func _create_collision_proxy() -> StaticBody3D:
	var body := StaticBody3D.new()

	body.name = "PropCollisionProxy"

	body.collision_layer = (
		prop_collision_layer
	)

	body.collision_mask = (
		prop_collision_mask
	)

	var collision_shape := (
		CollisionShape3D.new()
	)

	collision_shape.name = (
		"CollisionShape3D"
	)

	collision_shape.disabled = true

	body.add_child(
		collision_shape
	)

	collision_root.add_child(
		body
	)

	return body
	
func _acquire_collision_proxy() -> StaticBody3D:
	if not collision_proxy_pool.is_empty():
		var body: StaticBody3D = (
			collision_proxy_pool.pop_back()
		)

		return body

	return _create_collision_proxy()
	
func _release_collision_proxy(
	body: StaticBody3D
) -> void:
	if not is_instance_valid(body):
		return

	var collision_shape := (
		body.get_node_or_null(
			"CollisionShape3D"
		)
		as CollisionShape3D
	)

	if collision_shape != null:
		collision_shape.disabled = true
		collision_shape.shape = null

	body.name = "UnusedPropCollisionProxy"

	collision_proxy_pool.append(body)
	
func _activate_collision_candidate(
	candidate: PropCollisionCandidate
) -> void:
	if candidate == null:
		return

	if candidate.definition == null:
		return

	if candidate.definition.collision_shape == null:
		return

	if active_collision_proxies.has(
		candidate.candidate_id
	):
		return

	var chunk := (
		loaded_chunks.get(
			candidate.chunk_coordinate
		)
		as PropChunk
	)

	if not is_instance_valid(chunk):
		return

	var body := (
		_acquire_collision_proxy()
	)

	body.name = (
		"Collision_%s"
		% candidate.definition.prop_name
	)

	body.collision_layer = (
		prop_collision_layer
	)

	body.collision_mask = (
		prop_collision_mask
	)

	# Use the exact same transform as the visual MultiMesh
	# instance, converted through its PropChunk.
	body.global_transform = (
		chunk.global_transform
		* candidate.local_transform
	)

	var collision_shape := (
		body.get_node(
			"CollisionShape3D"
		)
		as CollisionShape3D
	)

	collision_shape.shape = (
		candidate.definition.collision_shape
	)

	collision_shape.position = (
		candidate.definition.collision_offset
	)

	collision_shape.rotation_degrees = (
		candidate.definition
			.collision_rotation_degrees
	)

	# The body's transform already contains the visual prop's
	# uniform scale.
	collision_shape.scale = Vector3.ONE

	collision_shape.disabled = false

	body.reset_physics_interpolation()

	active_collision_proxies[
		candidate.candidate_id
	] = body
	
func _deactivate_collision_candidate(
	candidate_id: String
) -> void:
	var body := (
		active_collision_proxies.get(
			candidate_id
		)
		as StaticBody3D
	)

	active_collision_proxies.erase(
		candidate_id
	)

	if not is_instance_valid(body):
		return

	_release_collision_proxy(body)
	
func _deactivate_distant_collision() -> void:
	var player_position := (
		player.global_position
	)

	var deactivation_distance := maxf(
		collision_deactivation_distance,
		collision_activation_distance
	)

	var distance_squared_limit := (
		deactivation_distance
		* deactivation_distance
	)

	var candidates_to_remove: Array[String] = []

	for key in active_collision_proxies.keys():
		var candidate_id: String = key

		var body := (
			active_collision_proxies.get(
				candidate_id
			)
			as StaticBody3D
		)

		if not is_instance_valid(body):
			candidates_to_remove.append(
				candidate_id
			)
			continue

		var offset_x := (
			body.global_position.x
			- player_position.x
		)

		var offset_z := (
			body.global_position.z
			- player_position.z
		)

		var distance_squared := (
			offset_x * offset_x
			+ offset_z * offset_z
		)

		if (
			distance_squared
			> distance_squared_limit
		):
			candidates_to_remove.append(
				candidate_id
			)

	for candidate_id in candidates_to_remove:
		_deactivate_collision_candidate(
			candidate_id
		)
		
func _get_nearby_collision_candidates() -> Array[PropCollisionCandidate]:
	var result: Array[PropCollisionCandidate] = []

	var chunk_search_radius := (
		ceili(
			collision_activation_distance
			/ chunk_size
		)
		+ 1
	)

	var player_position := (
		player.global_position
	)

	var activation_distance_squared := (
		collision_activation_distance
		* collision_activation_distance
	)

	for offset_z in range(
		-chunk_search_radius,
		chunk_search_radius + 1
	):
		for offset_x in range(
			-chunk_search_radius,
			chunk_search_radius + 1
		):
			var coordinate := (
				current_player_chunk
				+ Vector2i(
					offset_x,
					offset_z
				)
			)

			var chunk := (
				loaded_chunks.get(
					coordinate
				)
				as PropChunk
			)

			if not is_instance_valid(chunk):
				continue

			for candidate in (
				chunk.collision_candidates
			):
				if candidate == null:
					continue

				if active_collision_proxies.has(
					candidate.candidate_id
				):
					continue

				var candidate_transform := (
					chunk.global_transform
					* candidate.local_transform
				)

				var candidate_position := (
					candidate_transform.origin
				)

				var offset_candidate_x := (
					candidate_position.x
					- player_position.x
				)

				var offset_candidate_z := (
					candidate_position.z
					- player_position.z
				)

				var distance_squared := (
					offset_candidate_x
						* offset_candidate_x
					+ offset_candidate_z
						* offset_candidate_z
				)

				if (
					distance_squared
					<= activation_distance_squared
				):
					result.append(
						candidate
					)

	return result
	
func _get_candidate_distance_squared(
	candidate: PropCollisionCandidate
) -> float:
	var chunk := (
		loaded_chunks.get(
			candidate.chunk_coordinate
		)
		as PropChunk
	)

	if not is_instance_valid(chunk):
		return INF

	var candidate_transform := (
		chunk.global_transform
		* candidate.local_transform
	)

	var candidate_position := (
		candidate_transform.origin
	)

	var player_position := (
		player.global_position
	)

	var offset_x := (
		candidate_position.x
		- player_position.x
	)

	var offset_z := (
		candidate_position.z
		- player_position.z
	)

	return (
		offset_x * offset_x
		+ offset_z * offset_z
	)
	
func _compare_collision_candidates(
	first: PropCollisionCandidate,
	second: PropCollisionCandidate
) -> bool:
	return (
		_get_candidate_distance_squared(first)
		<
		_get_candidate_distance_squared(second)
	)
	
func _update_collision_proxies() -> void:
	if not has_current_player_chunk:
		return

	# First return distant bodies to the pool.
	_deactivate_distant_collision()

	var candidates := (
		_get_nearby_collision_candidates()
	)

	if candidates.is_empty():
		return

	candidates.sort_custom(
		_compare_collision_candidates
	)

	var activation_count := mini(
		candidates.size(),
		maximum_activations_per_update
	)

	for index in range(
		activation_count
	):
		_activate_collision_candidate(
			candidates[index]
		)
		
func _release_collision_for_chunk(
	coordinate: Vector2i
) -> void:
	var chunk := (
		loaded_chunks.get(
			coordinate
		)
		as PropChunk
	)

	if not is_instance_valid(chunk):
		return

	for candidate in (
		chunk.collision_candidates
	):
		if candidate == null:
			continue

		if active_collision_proxies.has(
			candidate.candidate_id
		):
			_deactivate_collision_candidate(
				candidate.candidate_id
			)
			
