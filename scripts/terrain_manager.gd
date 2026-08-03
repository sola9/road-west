class_name TerrainManager
extends Node3D

@export var player: Node3D
@export var terrain_chunk_scene: PackedScene
@export var world_generator: WorldGenerator
@export var floating_origin: FloatingOrigin

@export_category("Chunk Settings")
@export var chunk_size: float = 64.0
@export_range(4, 128) var chunk_resolution: int = 32

@export_category("Generation")
@export var world_seed: int = 12345

@export var player_spawn_clearance: float = 5.0

@export_category("Generation Queue")

# Maximum time the queue should spend generating chunks per frame.
@export_range(0.5, 20.0, 0.5)
var generation_budget_ms: float = 4.0

# Additional hard limit, regardless of elapsed time.
@export_range(1, 8)
var max_chunks_per_frame: int = 1

@export_category("Collision")

@export_range(0, 5)
var collision_distance: int = 1

@export_category("Streaming Range")
@export_range(1, 60) var render_distance: int = 16
# Side distance as a fraction of render_distance.
@export_range(0.1, 1.0, 0.05)
var side_distance_fraction: float = 0.7

# Rear distance as a fraction of render_distance.
@export_range(0.1, 1.0, 0.05)
var rear_distance_fraction: float = 0.4

@export_range(0, 4)
var unload_margin: int = 1

@export_category("Terrain LOD")

@export_range(4, 128, 1)
var near_lod_resolution: int = 32

@export_range(4, 128, 1)
var medium_lod_resolution: int = 16

@export_range(4, 128, 1)
var far_lod_resolution: int = 8

# Normalized distance through the direction-aware render region.
# 0.0 is the player and 1.0 is the outer render boundary.
@export_range(0.05, 0.9, 0.05)
var medium_lod_start_fraction: float = 0.35

@export_range(0.1, 1.0, 0.05)
var far_lod_start_fraction: float = 0.70

var desired_chunks: Dictionary = {}
var queued_chunks: Dictionary = {}
var generation_queue: Array[Vector2i] = []

var loaded_chunks: Dictionary = {}
var current_player_chunk := Vector2i(999999, 999999)
var current_heading_sector: int = -1

func _ready() -> void:
	if world_generator == null:
		push_error("TerrainManager does not have a WorldGenerator assigned.")
		return

	world_generator.ensure_configured()

	if player == null:
		push_error("TerrainManager does not have a player assigned.")
		return

	if terrain_chunk_scene == null:
		push_error("TerrainManager does not have a chunk scene assigned.")
		return
		
	if floating_origin == null:
		push_error("TerrainManager does not have a FloatingOrigin assigned.")
		return

	if not floating_origin.origin_shifted.is_connected(
		_on_origin_shifted
	):
		floating_origin.origin_shifted.connect(
			_on_origin_shifted
		)
		
	var starting_coordinate := _world_position_to_chunk(
		player.global_position
	)

	if not loaded_chunks.has(starting_coordinate):
		_create_chunk(starting_coordinate,near_lod_resolution)

	_update_chunks(true)
	call_deferred("_place_player_on_terrain")


func _process(_delta: float) -> void:
	_update_chunks(false)
	_process_generation_queue()
	
func _world_position_to_chunk(
	local_position: Vector3
) -> Vector2i:
	var absolute_x: float = (
		floating_origin.local_to_absolute_x(
			float(local_position.x)
		)
	)

	var absolute_z: float = (
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
	if player == null:
		return

	var new_player_chunk := _world_position_to_chunk(
		player.global_position
	)

	var new_heading_sector := _get_heading_sector()

	var chunk_changed := (
		new_player_chunk != current_player_chunk
	)

	var heading_changed := (
		new_heading_sector != current_heading_sector
	)

	if (
		not force_update
		and not chunk_changed
		and not heading_changed
	):
		return

	var should_update_existing_lods := (
		force_update or chunk_changed
	)

	current_player_chunk = new_player_chunk
	current_heading_sector = new_heading_sector

	desired_chunks.clear()

	var maximum_search_distance := render_distance

	for z_offset in range(
		-maximum_search_distance,
		maximum_search_distance + 1
	):
		for x_offset in range(
			-maximum_search_distance,
			maximum_search_distance + 1
		):
			var coordinate := (
				current_player_chunk
				+ Vector2i(x_offset, z_offset)
			)

			if not _is_chunk_in_render_region(coordinate):
				continue

			desired_chunks[coordinate] = true

			var desired_resolution := (
				_get_desired_resolution(coordinate)
			)

			var existing_chunk := (
				loaded_chunks.get(coordinate)
				as TerrainChunk
			)

			if not is_instance_valid(existing_chunk):
				if not queued_chunks.has(coordinate):
					_queue_chunk(coordinate)

			elif should_update_existing_lods:
				if (
					desired_resolution
					> existing_chunk.current_resolution
					and not queued_chunks.has(coordinate)
				):
					_queue_chunk(coordinate)

	var chunks_to_remove: Array[Vector2i] = []

	for key in loaded_chunks.keys():
		var coordinate: Vector2i = key

		if not desired_chunks.has(coordinate):
			chunks_to_remove.append(coordinate)

	for coordinate in chunks_to_remove:
		_remove_chunk(coordinate)

	_sort_generation_queue()
	_update_collision_states()
		
func _create_chunk(
	coordinate: Vector2i,
	target_resolution: int
) -> void:
	var chunk := (
		terrain_chunk_scene.instantiate()
		as TerrainChunk
	)

	if chunk == null:
		push_error(
			"Terrain chunk scene root must use TerrainChunk."
		)
		return

	add_child(chunk)

	chunk.generate(
		coordinate,
		chunk_size,
		target_resolution,
		world_generator,
		floating_origin
	)

	loaded_chunks[coordinate] = chunk

	var collision_should_be_active := (
		_should_chunk_have_collision(coordinate)
		and target_resolution == near_lod_resolution
	)

	chunk.set_collision_active(
		collision_should_be_active
	)

func _remove_chunk(coordinate: Vector2i) -> void:
	var chunk: TerrainChunk = loaded_chunks.get(coordinate)

	if is_instance_valid(chunk):
		chunk.queue_free()

	loaded_chunks.erase(coordinate)
	
func _place_player_on_terrain() -> void:
	var player_chunk_coordinate := _world_position_to_chunk(
		player.global_position
	)

	var chunk := loaded_chunks.get(
		player_chunk_coordinate
	) as TerrainChunk

	if chunk == null:
		push_error(
			"Could not find terrain chunk beneath player at %s"
			% player_chunk_coordinate
		)
		return

	var absolute_x: float = (
		floating_origin.local_to_absolute_x(
			float(player.global_position.x)
		)
	)

	var absolute_z: float = (
		floating_origin.local_to_absolute_z(
			float(player.global_position.z)
		)
	)

	var ground_height := world_generator.get_world_height(
		absolute_x,
		absolute_z
	)

	player.global_position.y = (
		ground_height
		+ player_spawn_clearance
	)

	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO

func _queue_chunk(coordinate: Vector2i) -> void:
	queued_chunks[coordinate] = true
	generation_queue.append(coordinate)
	
func _chunk_priority(
	coordinate: Vector2i
) -> float:
	var offset_chunks := coordinate - current_player_chunk

	var offset := Vector2(
		float(offset_chunks.x),
		float(offset_chunks.y)
	)

	var forward := _get_player_forward_2d()
	var right := _get_player_right_2d()

	var forward_distance := offset.dot(forward)
	var sideways_distance := absf(
		offset.dot(right)
	)

	var longitudinal_limit: float

	if forward_distance >= 0.0:
		longitudinal_limit = float(render_distance)
	else:
		longitudinal_limit = float(
			_get_rear_render_distance()
		)

	var sideways_limit := float(
		_get_side_render_distance()
	)

	var normalized_forward := (
		forward_distance / longitudinal_limit
	)

	var normalized_sideways := (
		sideways_distance / sideways_limit
	)

	var normalized_distance := (
		normalized_forward * normalized_forward
		+ normalized_sideways * normalized_sideways
	)

	# Give chunks ahead of the player a small priority advantage.
	var forward_bonus := maxf(
		forward_distance,
		0.0
	) * 0.05

	var priority := normalized_distance - forward_bonus

	if _should_chunk_have_collision(coordinate):
		priority -= 1000.0

	var existing_chunk := (
		loaded_chunks.get(coordinate)
		as TerrainChunk
	)

	if is_instance_valid(existing_chunk):
		var desired_resolution := (
			_get_desired_resolution(coordinate)
		)

		# Prefer upgrades over downgrades.
		if desired_resolution > existing_chunk.current_resolution:
			priority -= 100.0

	return priority


func _compare_chunk_priority(
	first: Vector2i,
	second: Vector2i
) -> bool:
	return (
		_chunk_priority(first)
		> _chunk_priority(second)
	)


func _sort_generation_queue() -> void:
	generation_queue.sort_custom(
		_compare_chunk_priority
	)
	
func _process_generation_queue() -> void:
	if generation_queue.is_empty():
		return

	var frame_start_usec := Time.get_ticks_usec()
	var processed_count := 0

	while (
		not generation_queue.is_empty()
		and processed_count < max_chunks_per_frame
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
			#generation_queue.pop_front()
			generation_queue.pop_back()
		)

		queued_chunks.erase(coordinate)

		# This chunk may no longer be wanted.
		if not desired_chunks.has(coordinate):
			continue

		var desired_resolution := (
			_get_desired_resolution(coordinate)
		)

		var existing_chunk := (
			loaded_chunks.get(coordinate)
			as TerrainChunk
		)

		if is_instance_valid(existing_chunk):
			if (
				existing_chunk.current_resolution
				== desired_resolution
			):
				continue

			_rebuild_chunk(
				existing_chunk,
				coordinate,
				desired_resolution
			)
		else:
			_create_chunk(
				coordinate,
				desired_resolution
			)

		processed_count += 1
		
func _update_collision_states() -> void:
	for key in loaded_chunks.keys():
		var coordinate: Vector2i = key

		var chunk := (
			loaded_chunks.get(coordinate)
			as TerrainChunk
		)

		if not is_instance_valid(chunk):
			continue

		var needs_collision := (
			_should_chunk_have_collision(coordinate)
		)

		var has_correct_lod := (
			chunk.current_resolution
			== near_lod_resolution
		)

		chunk.set_collision_active(
			needs_collision and has_correct_lod
		)

		# Queue an urgent high-resolution rebuild if a collision-ring
		# chunk is currently too coarse.
		if (
			needs_collision
			and not has_correct_lod
			and not queued_chunks.has(coordinate)
		):
			_queue_chunk(coordinate)

func _get_side_render_distance() -> int:
	return maxi(
		1,
		ceili(
			float(render_distance)
			* side_distance_fraction
		)
	)


func _get_rear_render_distance() -> int:
	return maxi(
		1,
		ceili(
			float(render_distance)
			* rear_distance_fraction
		)
	)
	
func _get_player_forward_2d() -> Vector2:
	var forward_3d: Vector3 = (
		-player.global_transform.basis.z
	)

	var forward_2d := Vector2(
		forward_3d.x,
		forward_3d.z
	)

	if forward_2d.length_squared() < 0.0001:
		return Vector2.UP

	return forward_2d.normalized()
	
func _get_player_right_2d() -> Vector2:
	var forward := _get_player_forward_2d()

	return Vector2(
		forward.y,
		-forward.x
	)
	
func _is_chunk_in_render_region(
	coordinate: Vector2i,
	margin: int = 0
) -> bool:
	return (
		_get_normalized_render_distance(
			coordinate,
			margin
		)
		<= 1.0
	)

func _get_heading_sector() -> int:
	var forward := _get_player_forward_2d()
	var angle := atan2(forward.y, forward.x)

	# Convert the full circle into eight 45-degree sectors.
	var sector_size := TAU / 8.0

	return posmod(
		floori(
			(angle + sector_size * 0.5)
			/ sector_size
		),
		8
	)

func _get_normalized_render_distance(
	coordinate: Vector2i,
	margin: int = 0
) -> float:
	var offset_chunks := coordinate - current_player_chunk

	var offset := Vector2(
		float(offset_chunks.x),
		float(offset_chunks.y)
	)

	var forward := _get_player_forward_2d()
	var right := _get_player_right_2d()

	var forward_distance := offset.dot(forward)
	var sideways_distance := absf(
		offset.dot(right)
	)

	var longitudinal_limit: float

	if forward_distance >= 0.0:
		longitudinal_limit = float(
			render_distance + margin
		)
	else:
		longitudinal_limit = float(
			_get_rear_render_distance() + margin
		)

	var sideways_limit := float(
		_get_side_render_distance() + margin
	)

	if (
		longitudinal_limit <= 0.0
		or sideways_limit <= 0.0
	):
		return INF

	var normalized_forward := (
		forward_distance / longitudinal_limit
	)

	var normalized_sideways := (
		sideways_distance / sideways_limit
	)

	return sqrt(
		normalized_forward * normalized_forward
		+ normalized_sideways * normalized_sideways
	)

func _get_desired_resolution(
	coordinate: Vector2i
) -> int:
	# Any chunk that needs active collision should use the highest
	# visual resolution as well.
	if _should_chunk_have_collision(coordinate):
		return near_lod_resolution

	var normalized_distance := (
		_get_normalized_render_distance(coordinate)
	)

	if normalized_distance < medium_lod_start_fraction:
		return near_lod_resolution

	if normalized_distance < far_lod_start_fraction:
		return medium_lod_resolution

	return far_lod_resolution

func _rebuild_chunk(
	chunk: TerrainChunk,
	coordinate: Vector2i,
	target_resolution: int
) -> void:
	if not is_instance_valid(chunk):
		return

	# Temporarily disable collision while replacing its mesh and
	# heightmap shape.
	chunk.set_collision_active(false)

	chunk.generate(
		coordinate,
		chunk_size,
		target_resolution,
		world_generator,
		floating_origin
	)

	var collision_should_be_active := (
		_should_chunk_have_collision(coordinate)
		and target_resolution == near_lod_resolution
	)

	chunk.set_collision_active(
		collision_should_be_active
	)
	
func _should_chunk_have_collision(
	coordinate: Vector2i
) -> bool:
	var offset := coordinate - current_player_chunk

	# Chebyshev distance produces a square collision ring.
	var distance := maxi(
		absi(offset.x),
		absi(offset.y)
	)

	return distance <= collision_distance

func _on_origin_shifted(shift: Vector3) -> void:
	for key in loaded_chunks.keys():
		var coordinate: Vector2i = key

		var chunk: TerrainChunk = (
			loaded_chunks.get(coordinate)
			as TerrainChunk
		)

		if not is_instance_valid(chunk):
			continue

		chunk.global_position -= shift
		chunk.reset_physics_interpolation()
