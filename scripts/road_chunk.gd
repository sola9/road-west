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
var floating_origin: FloatingOrigin

var absolute_origin_z: float = 0.0
var absolute_reference_x: float = 0.0


func generate(
	new_chunk_index: int,
	new_chunk_length: float,
	new_world_generator: WorldGenerator,
	new_floating_origin: FloatingOrigin
) -> void:
	chunk_index = new_chunk_index
	chunk_length = new_chunk_length
	world_generator = new_world_generator
	floating_origin = new_floating_origin

	absolute_origin_z = (
		float(chunk_index) * chunk_length
		- chunk_length * 0.5
	)

	# Use a reference X near the middle of the road chunk. Road mesh
	# vertices will remain close to this local origin.
	var midpoint_z := (
		absolute_origin_z
		+ chunk_length * 0.5
	)

	absolute_reference_x = (
		world_generator.get_road_center_x(midpoint_z)
	)

	position = Vector3(
		floating_origin.absolute_to_local_x(
			absolute_reference_x
		),
		0.0,
		floating_origin.absolute_to_local_z(
			absolute_origin_z
		)
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

	# Prepare a bounded UV offset for this road chunk.
	var repeats_per_chunk := (
		chunk_length / texture_repeat_length
	)

	var bounded_uv_base := fposmod(
		float(chunk_index) * repeats_per_chunk,
		1024.0
	)

	for segment_index in range(segment_count + 1):
		var local_center_z := (
			float(segment_index) * segment_length
		)

		var world_center_z: float = (
			absolute_origin_z + local_center_z
		)

		var center_x := (
			world_generator.get_road_center_x(
				world_center_z
			)
		)

		var side_direction := (
			world_generator.get_road_side_direction(
				world_center_z
			)
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

		var left_height := (
			world_generator.get_road_height(
				left_world_z
			)
			+ road_height_offset
		)

		var right_height := (
			world_generator.get_road_height(
				right_world_z
			)
			+ road_height_offset
		)

		var left_local := Vector3(
			left_world_x - absolute_reference_x,
			left_height,
			left_world_z - absolute_origin_z
		)

		var right_local := Vector3(
			right_world_x - absolute_reference_x,
			right_height,
			right_world_z - absolute_origin_z
		)

		var uv_z := (
			bounded_uv_base
			+ local_center_z / texture_repeat_length
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
