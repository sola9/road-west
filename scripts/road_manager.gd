class_name RoadManager
extends Node3D


@export var player: Node3D
@export var world_generator: WorldGenerator
@export var road_chunk_scene: PackedScene

@export var road_chunk_length: float = 64.0
@export_range(1, 30) var render_distance: int = 8


var loaded_chunks: Dictionary = {}
var current_player_chunk: int = 2147483647


func _ready() -> void:
	if player == null:
		push_error("RoadManager does not have a player assigned.")
		return

	if world_generator == null:
		push_error("RoadManager does not have a WorldGenerator assigned.")
		return

	if road_chunk_scene == null:
		push_error("RoadManager does not have a road chunk scene assigned.")
		return

	world_generator.ensure_configured()
	_update_chunks(true)


func _process(_delta: float) -> void:
	_update_chunks(false)


func _world_z_to_chunk(world_z: float) -> int:
	return floori(
		(world_z + road_chunk_length * 0.5)
		/ road_chunk_length
	)


func _update_chunks(force_update: bool) -> void:
	var new_player_chunk := _world_z_to_chunk(
		player.global_position.z
	)

	if (
		not force_update
		and new_player_chunk == current_player_chunk
	):
		return

	current_player_chunk = new_player_chunk

	var required_chunks: Dictionary = {}

	for offset in range(
		-render_distance,
		render_distance + 1
	):
		var chunk_index := (
			current_player_chunk + offset
		)

		required_chunks[chunk_index] = true

		if not loaded_chunks.has(chunk_index):
			_create_chunk(chunk_index)

	var chunks_to_remove: Array[int] = []

	for key in loaded_chunks.keys():
		var chunk_index := int(key)

		if not required_chunks.has(chunk_index):
			chunks_to_remove.append(chunk_index)

	for chunk_index in chunks_to_remove:
		_remove_chunk(chunk_index)


func _create_chunk(chunk_index: int) -> void:
	var chunk := (
		road_chunk_scene.instantiate()
		as RoadChunk
	)

	if chunk == null:
		push_error(
			"Road chunk scene root must use RoadChunk."
		)
		return

	add_child(chunk)

	chunk.generate(
		chunk_index,
		road_chunk_length,
		world_generator
	)

	loaded_chunks[chunk_index] = chunk


func _remove_chunk(chunk_index: int) -> void:
	var chunk := loaded_chunks.get(
		chunk_index
	) as RoadChunk

	if is_instance_valid(chunk):
		chunk.queue_free()

	loaded_chunks.erase(chunk_index)
