class_name RoadChunk
extends Node3D


@export var road_material: Material
@export var road_height_offset: float = 0.02

# Approximate distance between road cross sections.
@export_range(0.25, 8.0, 0.25)
var target_segment_length: float = 2.0

@export var texture_repeat_length: float = 8.0


@onready var road_mesh_instance: MeshInstance3D = $RoadMesh


var chunk_index: int
var chunk_length: float
var world_generator: WorldGenerator


func generate(
	new_chunk_index: int,
	new_chunk_length: float,
	new_world_generator: WorldGenerator
) -> void:
	chunk_index = new_chunk_index
	chunk_length = new_chunk_length
	world_generator = new_world_generator

	# Center road chunks around their integer coordinate, matching
	# the convention used by the terrain chunks.
	position = Vector3(
		0.0,
		0.0,
		chunk_index * chunk_length - chunk_length * 0.5
	)

	_generate_road()


func _generate_road() -> void:
	var segment_count := maxi(
		1,
		ceili(chunk_length / target_segment_length)
	)

	var segment_length := (
		chunk_length / float(segment_count)
	)

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	if road_material != null:
		surface_tool.set_material(road_material)

	for segment_index in range(segment_count + 1):
		var local_center_z := (
			float(segment_index) * segment_length
		)

		var world_center_z := (
			position.z + local_center_z
		)

		var center_x := world_generator.get_road_center_x(
			world_center_z
		)

		var side_direction := \
			world_generator.get_road_side_direction(
				world_center_z
			)

		var half_width := (
			world_generator.road_width * 0.5
		)

		var left_world_x := (
			center_x
			- side_direction.x * half_width
		)

		var left_world_z := (
			world_center_z
			- side_direction.y * half_width
		)

		var right_world_x := (
			center_x
			+ side_direction.x * half_width
		)

		var right_world_z := (
			world_center_z
			+ side_direction.y * half_width
		)

		# Sample each edge at its actual Z position. This keeps a
		# curved, sloped road from twisting unnaturally.
		var left_height := (
			world_generator.get_road_height(left_world_z)
			+ road_height_offset
		)

		var right_height := (
			world_generator.get_road_height(right_world_z)
			+ road_height_offset
		)

		var left_local := Vector3(
			left_world_x - position.x,
			left_height,
			left_world_z - position.z
		)

		var right_local := Vector3(
			right_world_x - position.x,
			right_height,
			right_world_z - position.z
		)

		var uv_z := (
			world_center_z / texture_repeat_length
		)

		surface_tool.set_normal(Vector3.UP)
		surface_tool.set_uv(Vector2(0.0, uv_z))
		surface_tool.add_vertex(left_local)

		surface_tool.set_normal(Vector3.UP)
		surface_tool.set_uv(Vector2(1.0, uv_z))
		surface_tool.add_vertex(right_local)

	for segment_index in range(segment_count):
		var left_current := segment_index * 2
		var right_current := left_current + 1
		var left_next := left_current + 2
		var right_next := left_current + 3

		# Preserve the winding that already works for your road.
		surface_tool.add_index(left_current)
		surface_tool.add_index(right_current)
		surface_tool.add_index(left_next)

		surface_tool.add_index(right_current)
		surface_tool.add_index(right_next)
		surface_tool.add_index(left_next)

	var generated_mesh := surface_tool.commit()
	road_mesh_instance.mesh = generated_mesh

	if road_material != null:
		road_mesh_instance.material_override = road_material
