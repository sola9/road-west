class_name PropCollisionCandidate
extends RefCounted


var candidate_id: String = ""

var chunk_coordinate: Vector2i = Vector2i.ZERO

var definition: BiomePropDefinition

# Transform relative to the PropChunk.
var local_transform: Transform3D = Transform3D.IDENTITY
