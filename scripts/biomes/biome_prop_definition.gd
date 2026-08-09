@tool
class_name BiomePropDefinition
extends Resource


@export_category("Identity")

@export var prop_name: String = "New Prop"

# Give every prop type a different number.
# This keeps procedural placement deterministic.
@export var spawn_seed_offset: int = 0


@export_category("Visual")

@export var mesh: Mesh

@export_range(0.05, 10.0, 0.05)
var minimum_scale: float = 0.8

@export_range(0.05, 10.0, 0.05)
var maximum_scale: float = 1.2

@export var random_y_rotation: bool = true

# Useful if the imported model's base is not exactly at Y = 0.
@export_range(-5.0, 5.0, 0.01, "suffix:m")
var vertical_offset: float = 0.0


@export_category("Placement")

@export_range(0.0, 89.0, 1.0, "degrees")
var maximum_slope_degrees: float = 35.0

# Extra space beyond the asphalt edge.
@export_range(0.0, 100.0, 0.5, "suffix:m")
var road_clearance: float = 4.0

@export_category("Collision")

@export var collision_enabled: bool = false

@export var collision_shape: Shape3D

# Use these only if the collision shape does not line up with
# the visual mesh's origin.
@export var collision_offset: Vector3 = Vector3.ZERO

@export var collision_rotation_degrees: Vector3 = Vector3.ZERO
