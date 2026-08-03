class_name FloatingOrigin
extends Node


signal origin_shifted(shift: Vector3)


@export_category("References")
@export var player: Node3D


@export_category("Origin Shifting")

# How far the player can travel locally before a shift occurs.
@export var shift_threshold: float = 1024.0

# Snap shifts to this interval. Using the terrain chunk size is ideal.
@export var shift_grid_size: float = 64.0


# Store large logical coordinates as scalar GDScript floats rather
# than Vector2 or Vector3 values.
var origin_offset_x: float = 0.0
var origin_offset_z: float = 0.0

var shift_in_progress: bool = false


func _ready() -> void:
	if player == null:
		push_error("FloatingOrigin does not have a player assigned.")
		set_physics_process(false)
		return

	if shift_threshold <= 0.0:
		push_error("FloatingOrigin shift threshold must be positive.")
		set_physics_process(false)
		return

	if shift_grid_size <= 0.0:
		push_error("FloatingOrigin shift grid size must be positive.")
		set_physics_process(false)
		return

	# Default player scripts usually have priority 0. Larger values run
	# later, so the shift occurs after the player's normal movement.
	process_physics_priority = 1000


func _physics_process(_delta: float) -> void:
	if shift_in_progress:
		return

	var player_position := player.global_position

	var horizontal_distance := maxf(
		absf(player_position.x),
		absf(player_position.z)
	)

	if horizontal_distance < shift_threshold:
		return

	var shift := Vector3(
		snappedf(player_position.x, shift_grid_size),
		0.0,
		snappedf(player_position.z, shift_grid_size)
	)

	if (
		is_zero_approx(shift.x)
		and is_zero_approx(shift.z)
	):
		return

	_apply_origin_shift(shift)


func _apply_origin_shift(shift: Vector3) -> void:
	shift_in_progress = true

	# Increase the logical offset first.
	origin_offset_x += float(shift.x)
	origin_offset_z += float(shift.z)

	# Bring the player back toward Godot's local origin.
	player.global_position -= shift
	player.reset_physics_interpolation()

	# Signals are emitted synchronously. Terrain, road, and future
	# world-object managers shift their currently loaded nodes here.
	origin_shifted.emit(shift)

	shift_in_progress = false


func local_to_absolute_x(local_x: float) -> float:
	return origin_offset_x + local_x


func local_to_absolute_z(local_z: float) -> float:
	return origin_offset_z + local_z


func absolute_to_local_x(absolute_x: float) -> float:
	return absolute_x - origin_offset_x


func absolute_to_local_z(absolute_z: float) -> float:
	return absolute_z - origin_offset_z


func get_absolute_player_x() -> float:
	return local_to_absolute_x(
		float(player.global_position.x)
	)


func get_absolute_player_z() -> float:
	return local_to_absolute_z(
		float(player.global_position.z)
	)
