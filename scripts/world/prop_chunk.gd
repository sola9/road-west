class_name PropChunk
extends Node3D


var chunk_coordinate: Vector2i = Vector2i.ZERO
var chunk_size: float = 128.0

var absolute_origin_x: float = 0.0
var absolute_origin_z: float = 0.0

var floating_origin: FloatingOrigin


func setup(
	new_coordinate: Vector2i,
	new_chunk_size: float,
	new_floating_origin: FloatingOrigin
) -> void:
	chunk_coordinate = new_coordinate
	chunk_size = new_chunk_size
	floating_origin = new_floating_origin

	absolute_origin_x = (
		float(chunk_coordinate.x) * chunk_size
		- chunk_size * 0.5
	)

	absolute_origin_z = (
		float(chunk_coordinate.y) * chunk_size
		- chunk_size * 0.5
	)

	position = Vector3(
		floating_origin.absolute_to_local_x(
			absolute_origin_x
		),
		0.0,
		floating_origin.absolute_to_local_z(
			absolute_origin_z
		)
	)

	name = "PropChunk_%d_%d" % [
		chunk_coordinate.x,
		chunk_coordinate.y
	]


func add_prop_instances(
	definition: BiomePropDefinition,
	transforms: Array[Transform3D]
) -> void:
	if definition == null:
		return

	if definition.mesh == null:
		return

	if transforms.is_empty():
		return

	var multimesh := MultiMesh.new()

	# Set the format before instance_count.
	multimesh.transform_format = (
		MultiMesh.TRANSFORM_3D
	)

	multimesh.mesh = definition.mesh
	multimesh.instance_count = transforms.size()

	for index in range(transforms.size()):
		multimesh.set_instance_transform(
			index,
			transforms[index]
		)

	var instance := MultiMeshInstance3D.new()

	instance.name = (
		"%s_MultiMesh"
		% definition.prop_name
	)

	instance.multimesh = multimesh

	add_child(instance)
