class_name TerrainChunk
extends Node3D

@export var terrain_material: Material

@export_category("Terrain Shape")

@export var macro_height: float = 15 #was 7.5
@export var rolling_height: float = 4.5
@export var mesa_height: float = 4.5
@export var ridge_height: float = 5 #was 2.75
@export var detail_height: float = 0.6

@export_range(0.0, 1.0) var lowland_depth: float = 0.55

@export_category("Road Earthworks")

# The raised valley profile must exceed the normal road profile
# by this much before an embankment begins.
@export var road_embankment_trigger: float = 1.25

# Controls how gradually the embankment activates.
@export var road_embankment_transition: float = 1.0

# Maximum distance the road may be raised above the local ground.
@export var road_max_embankment_height: float = 1.5

# Distance between terrain samples along the road.
@export var road_ground_sample_spacing: float = 24.0
# Samples this many positions ahead and behind the current point.
@export_range(1, 10) var road_ground_sample_radius: int = 4
# How deeply the road is allowed to cut into a hill.
@export var road_max_cut_depth: float = 1.0
# Slightly raises the prepared terrain beneath the asphalt.
@export var road_ground_clearance: float = 0.15
# Minimum general road elevation in low terrain.
@export var road_valley_floor: float = 1.75
# Variation in the raised profile through valleys.
@export var road_valley_variation: float = 1.5

@export_category("Biome Rendering")

@export_range(1, 16, 1)
var biome_color_resolution: int = 4

@onready var terrain_mesh_instance: MeshInstance3D = $TerrainMesh
@onready var collision_shape: CollisionShape3D = \
	$TerrainMesh/StaticBody3D/CollisionShape3D

var world_generator: WorldGenerator

var chunk_coordinate := Vector2i.ZERO
var chunk_size: float = 64.0
var resolution: int = 32

var road_width: float = 8.0
var road_blend_width: float = 18.0

var terrain_noise: FastNoiseLite
var rolling_noise: FastNoiseLite
var mesa_noise: FastNoiseLite
var ridge_noise: FastNoiseLite
var detail_noise: FastNoiseLite

var road_curve_noise: FastNoiseLite
var road_height_noise: FastNoiseLite

var road_curve_amplitude: float = 90.0
var road_curve_sample_distance: float = 2.0

var road_height_cache: Dictionary = {}

var current_resolution: int = 0

var cached_height_data := PackedFloat32Array()
var cached_vertices_per_side: int = 0
var cached_step: float = 1.0

var floating_origin: FloatingOrigin

var absolute_origin_x: float = 0.0
var absolute_origin_z: float = 0.0

func generate(
	new_chunk_coordinate: Vector2i,
	new_chunk_size: float,
	new_resolution: int,
	new_world_generator: WorldGenerator,
	new_floating_origin: FloatingOrigin
) -> void:
	chunk_coordinate = new_chunk_coordinate
	chunk_size = new_chunk_size
	resolution = new_resolution
	current_resolution = new_resolution

	world_generator = new_world_generator
	floating_origin = new_floating_origin

	# These are permanent logical coordinates.
	absolute_origin_x = (
		float(chunk_coordinate.x) * chunk_size
		- chunk_size * 0.5
	)

	absolute_origin_z = (
		float(chunk_coordinate.y) * chunk_size
		- chunk_size * 0.5
	)

	# This is the temporary local Godot position.
	position = Vector3(
		floating_origin.absolute_to_local_x(
			absolute_origin_x
		),
		0.0,
		floating_origin.absolute_to_local_z(
			absolute_origin_z
		)
	)

	_generate_terrain()

func _generate_terrain() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	if terrain_material != null:
		surface_tool.set_material(terrain_material)

	var vertices_per_side := resolution + 1
	var step := chunk_size / float(resolution)

	# Store exactly the same heights used by the visible mesh.
	var height_data := PackedFloat32Array()
	cached_height_data = height_data
	cached_vertices_per_side = vertices_per_side
	cached_step = step
	height_data.resize(
		vertices_per_side * vertices_per_side
	)
	var biome_colors: Array[Color] = (
		_build_biome_color_grid()
	)

	for z_index in range(vertices_per_side):
		for x_index in range(vertices_per_side):
			var local_x := x_index * step
			var local_z := z_index * step

			var world_x: float = absolute_origin_x + local_x
			var world_z: float = absolute_origin_z + local_z

			var height := world_generator.get_world_height(
				world_x,
				world_z
			)
			
			var biome_color := (
				_sample_biome_color_grid(
					biome_colors,
					local_x,
					local_z
				)
			)	

			var vertex_index := (
				z_index * vertices_per_side
				+ x_index
			)

			height_data[vertex_index] = height

			surface_tool.set_color(
				biome_color
			)
			
			surface_tool.set_uv(
				_get_terrain_uv(local_x, local_z)
			)

			surface_tool.add_vertex(
				Vector3(
					local_x,
					height,
					local_z
				)
			)

	for z_index in range(resolution):
		for x_index in range(resolution):
			var top_left := (
				z_index * vertices_per_side
				+ x_index
			)

			var top_right := top_left + 1

			var bottom_left := (
				(z_index + 1) * vertices_per_side
				+ x_index
			)

			var bottom_right := bottom_left + 1

			surface_tool.add_index(top_left)
			surface_tool.add_index(top_right)
			surface_tool.add_index(bottom_left)

			surface_tool.add_index(top_right)
			surface_tool.add_index(bottom_right)
			surface_tool.add_index(bottom_left)

	surface_tool.generate_normals()

	var generated_mesh: ArrayMesh = surface_tool.commit()

	if generated_mesh == null:
		push_error(
			"Terrain mesh generation failed for chunk %s"
			% chunk_coordinate
		)
		return

	terrain_mesh_instance.mesh = generated_mesh

	if terrain_material != null:
		terrain_mesh_instance.material_override = terrain_material

	
func _update_collision(
	height_data: PackedFloat32Array,
	vertices_per_side: int,
	step: float
) -> void:
	if height_data.is_empty():
		collision_shape.shape = null
		return

	var heightmap := HeightMapShape3D.new()

	heightmap.map_width = vertices_per_side
	heightmap.map_depth = vertices_per_side

	# HeightMapShape3D normally places points one unit apart.
	#
	# We scale the collision uniformly by `step`, so its X/Z spacing
	# matches the visible terrain. Because Y is also scaled, the stored
	# heights must be divided by `step`.
	var scaled_height_data := PackedFloat32Array()
	scaled_height_data.resize(height_data.size())

	for index in range(height_data.size()):
		scaled_height_data[index] = (
			height_data[index] / step
		)

	heightmap.map_data = scaled_height_data

	# HeightMapShape3D is centered around its CollisionShape3D.
	# The visible mesh extends from 0 to chunk_size locally, so move
	# the collision shape to the center of the chunk.
	collision_shape.position = Vector3(
		chunk_size * 0.5,
		0.0,
		chunk_size * 0.5
	)

	# Uniform scaling avoids the unsupported non-uniform scaling case.
	collision_shape.scale = Vector3(
		step,
		step,
		step
	)

	collision_shape.shape = heightmap
	
func set_collision_active(active: bool) -> void:
	if collision_shape == null:
		return

	if (
		active
		and collision_shape.shape == null
		and not cached_height_data.is_empty()
	):
		_update_collision(
			cached_height_data,
			cached_vertices_per_side,
			cached_step
		)

	collision_shape.set_deferred(
		"disabled",
		not active
	)

@export var terrain_texture_repeat_length: float = 8.0

const UV_CHUNK_WRAP: int = 256


func _get_terrain_uv(
	local_x: float,
	local_z: float
) -> Vector2:
	var wrapped_chunk_x := posmod(
		chunk_coordinate.x,
		UV_CHUNK_WRAP
	)

	var wrapped_chunk_z := posmod(
		chunk_coordinate.y,
		UV_CHUNK_WRAP
	)

	var wrapped_world_x := (
		float(wrapped_chunk_x) * chunk_size
		+ local_x
	)

	var wrapped_world_z := (
		float(wrapped_chunk_z) * chunk_size
		+ local_z
	)

	return Vector2(
		wrapped_world_x
			/ terrain_texture_repeat_length,
		wrapped_world_z
			/ terrain_texture_repeat_length
	)

func _build_biome_color_grid() -> Array[Color]:
	var grid_resolution := mini(
		biome_color_resolution,
		resolution
	)

	var vertices_per_side := (
		grid_resolution + 1
	)

	var colors: Array[Color] = []
	colors.resize(
		vertices_per_side
		* vertices_per_side
	)

	for grid_z in range(vertices_per_side):
		for grid_x in range(vertices_per_side):
			var normalized_x := (
				float(grid_x)
				/ float(grid_resolution)
			)

			var normalized_z := (
				float(grid_z)
				/ float(grid_resolution)
			)

			var local_x := (
				normalized_x * chunk_size
			)

			var local_z := (
				normalized_z * chunk_size
			)

			var world_x: float = (
				absolute_origin_x
				+ local_x
			)

			var world_z: float = (
				absolute_origin_z
				+ local_z
			)

			var world_y: float = (
				world_generator.get_world_height(
					world_x,
					world_z
				)
			)

			var color := (
				world_generator
				.get_biome_terrain_color(
					world_x,
					world_y,
					world_z
				)
			)

			var index := (
				grid_z * vertices_per_side
				+ grid_x
			)

			colors[index] = color

	return colors

func _sample_biome_color_grid(
	colors: Array[Color],
	local_x: float,
	local_z: float
) -> Color:
	var grid_resolution := mini(
		biome_color_resolution,
		resolution
	)

	var vertices_per_side := (
		grid_resolution + 1
	)

	var normalized_x := clampf(
		local_x / chunk_size,
		0.0,
		1.0
	)

	var normalized_z := clampf(
		local_z / chunk_size,
		0.0,
		1.0
	)

	var grid_x := (
		normalized_x
		* float(grid_resolution)
	)

	var grid_z := (
		normalized_z
		* float(grid_resolution)
	)

	var x0 := floori(grid_x)
	var z0 := floori(grid_z)

	var x1 := mini(
		x0 + 1,
		grid_resolution
	)

	var z1 := mini(
		z0 + 1,
		grid_resolution
	)

	var blend_x := (
		grid_x - float(x0)
	)

	var blend_z := (
		grid_z - float(z0)
	)

	var color_00: Color = colors[
		z0 * vertices_per_side + x0
	]

	var color_10: Color = colors[
		z0 * vertices_per_side + x1
	]

	var color_01: Color = colors[
		z1 * vertices_per_side + x0
	]

	var color_11: Color = colors[
		z1 * vertices_per_side + x1
	]

	var color_top := color_00.lerp(
		color_10,
		blend_x
	)

	var color_bottom := color_01.lerp(
		color_11,
		blend_x
	)

	return color_top.lerp(
		color_bottom,
		blend_z
	)
