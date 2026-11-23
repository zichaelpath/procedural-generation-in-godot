class_name StreetLamps
extends RefCounted

## A dressing generator, written to the book's contracts from a
## blank file (Ch 45's worked extension). Consumes ONLY published
## products: the network's draw segments (Ch 37) and height_at().
## Draws ONLY from the dressing stream (registered in Ch 2, waited
## until now). Publishes data (positions) before nodes. Reports.
##
## Integration adaptation vs Listing 45.1 as printed (call site
## only): Part VIII's built RoadNetwork stores draw segments as
## {"a": node, "b": node, "road": r} indices into network.nodes —
## not the {"from","to"} Vector2 pair the listing's text assumes.
## _segment_ends() reads whichever form the network published.

const SPACING: float = 28.0 # metres between lamps, per segment side

var lamp_count: int = 0


func _segment_ends(network: RoadNetwork, segment: Dictionary) -> Array[Vector2]:
	if segment.has("from") and segment.has("to"):
		return [segment["from"] as Vector2, segment["to"] as Vector2]
	var na: Vector3 = network.nodes[int(segment["a"])]
	var nb: Vector3 = network.nodes[int(segment["b"])]
	return [Vector2(na.x, na.z), Vector2(nb.x, nb.z)]


func lamp_positions(network: RoadNetwork, terrain: TerrainHeight, master_seed: int) -> Array[Vector3]:
	var rng: RandomNumberGenerator = SeedBank.stream_for(
		master_seed, SeedBank.STREAM_DRESSING)
	var out: Array[Vector3] = []
	for segment: Dictionary in network.segments:
		var ends: Array[Vector2] = _segment_ends(network, segment)
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var length: float = a.distance_to(b)
		if length < SPACING:
			continue
		var dir: Vector2 = (b - a) / length
		var side: Vector2 = Vector2(-dir.y, dir.x)
		# Alternate sides along the segment — a street rhythm, rolled
		# once per segment from the dressing stream, so re-dressing
		# never touches any other system's dice.
		var side_sign: float = 1.0 if rng.randf() < 0.5 else -1.0
		var steps: int = int(length / SPACING)
		for i: int in range(1, steps + 1):
			var p: Vector2 = a + dir * (float(i) * SPACING) + side * side_sign * 6.0
			out.append(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
			side_sign = -side_sign
	return out


func build(network: RoadNetwork, terrain: TerrainHeight, master_seed: int, host: Node3D) -> void:
	var positions: Array[Vector3] = lamp_positions(network, terrain, master_seed)
	lamp_count = positions.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 4.2, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = positions.size()
	for i: int in range(positions.size()):
		var t := Transform3D(Basis(), positions[i] + Vector3(0.0, 2.1, 0.0))
		multi.set_instance_transform(i, t)
	var holder := MultiMeshInstance3D.new()
	holder.name = "StreetLamps"
	holder.multimesh = multi
	holder.material_override = mat
	host.add_child(holder)
	print("[dressing] street lamps: ", lamp_count, " placed from the dressing stream")
