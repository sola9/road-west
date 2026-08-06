class_name RoadChunk
extends Node3D


@export var road_material: Material
@export var road_height_offset: float = 0.02

# Approximate distance between road cross sections.
@export_range(0.25, 8.0, 0.25)
var target_segment_length: float = 2.0

@export var texture_repeat_length: float = 8.0

@export_category("Road Markings")

@export var yellow_line_material: Material
@export var white_line_material: Material

# Width of each individual yellow line.
@export var center_line_width: float = 0.14

# Empty space between the two yellow lines.
@export var center_line_gap: float = 0.16

@export var edge_line_width: float = 0.14

# Distance from the asphalt edge to the center of the white line.
@export var edge_line_inset: float = 0.45

# Prevents markings from flickering against the asphalt.
@export var marking_height_offset: float = 0.025

@onready var road_mesh_instance: MeshInstance3D = $RoadMesh
@onready var road_markings_instance: MeshInstance3D = \
	$RoadMarkings


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
	_generate_markings()


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
		
func _generate_markings() -> void:
	var markings_mesh := ArrayMesh.new()

	var half_center_gap := center_line_gap * 0.5
	var half_center_width := center_line_width * 0.5

	var center_offset := (
		half_center_gap
		+ half_center_width
	)

	var center_offsets: Array[float] = [
		-center_offset,
		center_offset
	]

	_append_marking_surface(
		markings_mesh,
		center_offsets,
		center_line_width,
		yellow_line_material,
		0.0
	)

	var road_half_width := (
		world_generator.road_width * 0.5
	)

	var edge_offset := (
		road_half_width
		- edge_line_inset
	)

	var edge_offsets: Array[float] = [
		-edge_offset,
		edge_offset
	]

	_append_marking_surface(
		markings_mesh,
		edge_offsets,
		edge_line_width,
		white_line_material,
		10.0
	)

	road_markings_instance.mesh = markings_mesh

func _append_marking_surface(
	target_mesh: ArrayMesh,
	lateral_offsets: Array[float],
	line_width: float,
	line_material: Material,
	pattern_group_offset: float
) -> void:
	if line_material == null:
		return

	if lateral_offsets.is_empty():
		return

	var segment_count := maxi(
		1,
		ceili(
			chunk_length
			/ target_segment_length
		)
	)

	var segment_length := (
		chunk_length
		/ float(segment_count)
	)

	var repeats_per_chunk := (
		chunk_length
		/ texture_repeat_length
	)

	const UV_WRAP_CHUNKS: int = 128

	var wrapped_chunk_index := posmod(
		chunk_index,
		UV_WRAP_CHUNKS
	)

	var bounded_uv_base := (
		float(wrapped_chunk_index)
		* repeats_per_chunk
	)

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_material(line_material)

	var first_strip_vertex := 0

	for strip_index in range(lateral_offsets.size()):
		var lateral_offset: float = lateral_offsets[strip_index]

		# Give each strip a deterministic but different pattern offset.
		var pattern_offset := Vector2(
			float(strip_index) * 17.37,
			float(strip_index) * 31.91
		)

		for segment_index in range(segment_count + 1):
			var local_center_z := (
				float(segment_index)
				* segment_length
			)

			var world_center_z := (
				absolute_origin_z
				+ local_center_z
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

			var first_lateral_position := (
				lateral_offset
				- line_width * 0.5
			)

			var second_lateral_position := (
				lateral_offset
				+ line_width * 0.5
			)

			var first_world_x := (
				center_x
				+ side_direction.x
				* first_lateral_position
			)

			var first_world_z := (
				world_center_z
				+ side_direction.y
				* first_lateral_position
			)

			var second_world_x := (
				center_x
				+ side_direction.x
				* second_lateral_position
			)

			var second_world_z := (
				world_center_z
				+ side_direction.y
				* second_lateral_position
			)

			var first_height := (
				world_generator.get_road_height(
					first_world_z
				)
				+ road_height_offset
				+ marking_height_offset
			)

			var second_height := (
				world_generator.get_road_height(
					second_world_z
				)
				+ road_height_offset
				+ marking_height_offset
			)

			var first_local := Vector3(
				first_world_x
					- absolute_reference_x,
				first_height,
				first_world_z
					- absolute_origin_z
			)

			var second_local := Vector3(
				second_world_x
					- absolute_reference_x,
				second_height,
				second_world_z
					- absolute_origin_z
			)

			var uv_z := (
				bounded_uv_base
				+ local_center_z
				/ texture_repeat_length
			)

			surface_tool.set_normal(Vector3.UP)
			surface_tool.set_uv(Vector2(0.0, uv_z))
			surface_tool.set_uv2(pattern_offset)
			surface_tool.add_vertex(first_local)

			surface_tool.set_normal(Vector3.UP)
			surface_tool.set_uv(Vector2(1.0, uv_z))
			surface_tool.set_uv2(pattern_offset)
			surface_tool.add_vertex(second_local)

		for segment_index in range(segment_count):
			var first_current := (
				first_strip_vertex
				+ segment_index * 2
			)

			var second_current := (
				first_current + 1
			)

			var first_next := (
				first_current + 2
			)

			var second_next := (
				first_current + 3
			)

			surface_tool.add_index(first_current)
			surface_tool.add_index(second_current)
			surface_tool.add_index(first_next)

			surface_tool.add_index(second_current)
			surface_tool.add_index(second_next)
			surface_tool.add_index(first_next)

		first_strip_vertex += (
			segment_count + 1
		) * 2

	surface_tool.commit(target_mesh)
