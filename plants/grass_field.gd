class_name GrassField
extends RefCounted

## Grass as data: one tapered quad, instanced by the tens of
## thousands. Placement obeys the terrain (water and steep vetoes);
## moisture bakes each blade's tint and height at build time, so
## the per-frame cost of "a meadow" is one draw call per chunk.

const DRY_TINT := Color(1.10, 0.90, 0.50)   # instance tints, not raw colours:
const LUSH_TINT := Color(0.72, 1.05, 0.68)  # they multiply the blade gradient

static var _material: Material = null

static func blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.035, 0.0, 0.0), Vector3(0.035, 0.0, 0.0),
		Vector3(0.010, 1.0, 0.0), Vector3(-0.010, 1.0, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	# Normals point UP, not out: the classic grass trick. Every
	# blade is lit like the ground it stands on, so the field
	# reads as one surface instead of a hundred thousand cards.
	var normals := PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func grass_material() -> Material:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://plants/wind_bend.gdshader")
	_material = mat
	return _material

static func build_for_chunk(parent: Node3D, rect: Rect2, count: int, terrain: TerrainHeight, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var min_y: float = INF
	var max_y: float = -INF
	for n in count:
		var x: float = rng.randf_range(rect.position.x, rect.end.x)
		var z: float = rng.randf_range(rect.position.y, rect.end.y)
		var h: float = terrain.height_at(x, z)
		if h < terrain.sea_level + 0.15:
			continue  # underwater: vetoed
		if terrain.slope_at(x, z) > 0.10:
			continue  # too steep: grass there reads as a bug
		var moist: float = Scatter.moisture_at_world(terrain, x, z)
		var yaw: float = rng.randf_range(0.0, TAU)
		var height_scale: float = 0.55 + moist * 0.75
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1.0, height_scale, 1.0))
		transforms.append(Transform3D(basis, Vector3(x, h - 0.03, z)))
		colours.append(DRY_TINT.lerp(LUSH_TINT, moist))
		min_y = minf(min_y, h)
		max_y = maxf(max_y, h)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colours[i])
	var holder := MultiMeshInstance3D.new()
	holder.name = "Grass"
	holder.multimesh = mm
	holder.material_override = grass_material()
	# THE line. Without it the whole chunk vanishes whenever the
	# chunk's ORIGIN leaves the screen (frustum culling uses this
	# box, and the default box is one blade at the origin).
	holder.custom_aabb = AABB(
		Vector3(rect.position.x, min_y - 0.5, rect.position.y),
		Vector3(rect.size.x, (max_y - min_y) + 2.5, rect.size.y))
	parent.add_child(holder)
	print("Grass chunk: ", transforms.size(), " of ", count, " blades placed")
	return holder
