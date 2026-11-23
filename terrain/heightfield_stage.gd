@tool
extends StageBase
## Chapter 9 proof stage — Heightfields & Meshes.
## Scene: res://stages/stage_terrain_heightfield.tscn (this script is
## attached to its root; exports step / master_seed are set there).
##
## Steps (cumulative, PLAN.md Ch. 9):
##   step 0 — raw noise heightfield mesh, flat-shaded, single tint ramp
##   step 1 — island falloff applied (edges sink below sea level)
##   step 2 — water plane at sea level + vertex-colour splat by height
##            (sand → grass → forest → rock → snow)
##   step 3 — slope-aware splat: steep faces turn to rock whatever their
##            height, and a darker wet-sand band hugs the shoreline
##
## Data first: _compute_heights() returns a PackedFloat32Array grid —
## pure data, no nodes. _build_mesh() turns that data into an ArrayMesh.
## All randomness/noise comes from the SeedBank "terrain" stream via
## WorldConfig, seeded by the master_seed export. Same seed, same island.

const SIZE: float = 120.0 ## Island patch is SIZE × SIZE metres.
const RES: int = 97 ## Vertices per side (RES-1 quads per side).
const AMPLITUDE: float = 12.0
const NOISE_FREQUENCY: float = 0.028
const NOISE_OCTAVES: int = 5
const WATER_SIZE: float = 3000.0 ## Water reaches the horizon, not the patch edge.


func build_step(p_step: int) -> void:
	_sync_config()
	var heights: PackedFloat32Array = _compute_heights(p_step)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Heightfield"
	mesh_instance.mesh = _build_mesh(heights, p_step)
	generated_root.add_child(mesh_instance)
	if p_step >= 2:
		generated_root.add_child(_build_seabed())
		generated_root.add_child(_build_water())


## Pure data: the height grid for a step. Index = iz * RES + ix.
func _compute_heights(p_step: int) -> PackedFloat32Array:
	var noise: FastNoiseLite = config.noise(SeedBank.STREAM_TERRAIN, NOISE_FREQUENCY, NOISE_OCTAVES)
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	for iz in RES:
		for ix in RES:
			var x: float = -SIZE * 0.5 + SIZE * float(ix) / float(RES - 1)
			var z: float = -SIZE * 0.5 + SIZE * float(iz) / float(RES - 1)
			var n: float = noise.get_noise_2d(x, z)
			var base: float = n * 0.5 + 0.5 # 0..1 rolling hills
			var h: float = 0.0
			if p_step == 0:
				# Raw noise: no falloff — hills run off every edge.
				h = base * 13.0 - 3.0
			else:
				# Island falloff: 1 at the centre, 0 at/beyond the rim.
				var dist: float = Vector2(x, z).length() / (SIZE * 0.5)
				var fall: float = clampf(1.0 - smoothstep(0.42, 1.02, dist), 0.0, 1.0)
				fall = pow(fall, 1.25)
				h = base * AMPLITUDE * fall + fall * 1.5 - 3.0
			heights[iz * RES + ix] = h
	return heights


func _height_from(heights: PackedFloat32Array, ix: int, iz: int) -> float:
	return heights[iz * RES + ix]


func _vertex_at(heights: PackedFloat32Array, ix: int, iz: int) -> Vector3:
	var x: float = -SIZE * 0.5 + SIZE * float(ix) / float(RES - 1)
	var z: float = -SIZE * 0.5 + SIZE * float(iz) / float(RES - 1)
	return Vector3(x, _height_from(heights, ix, iz), z)


## Builder: grid data → flat-shaded ArrayMesh (one face normal per tri).
func _build_mesh(heights: PackedFloat32Array, p_step: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for iz in RES - 1:
		for ix in RES - 1:
			var a: Vector3 = _vertex_at(heights, ix, iz)
			var b: Vector3 = _vertex_at(heights, ix, iz + 1)
			var c: Vector3 = _vertex_at(heights, ix + 1, iz)
			var d: Vector3 = _vertex_at(heights, ix + 1, iz + 1)
			# Godot front faces wind CLOCKWISE seen from the front (above),
			# so the triangles are passed a,c,b / b,c,d — the reverse of
			# the order that produced a +Y cross product. _append_tri
			# still assigns the upward face normal for lighting.
			_append_tri(verts, normals, colors, a, c, b, p_step)
			_append_tri(verts, normals, colors, b, c, d, p_step)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


func _append_tri(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, p_a: Vector3, p_b: Vector3, p_c: Vector3, p_step: int) -> void:
	var face_normal: Vector3 = (p_b - p_a).cross(p_c - p_a).normalized()
	# Winding is clockwise-from-above (Godot's front-face rule), which
	# makes the raw cross product point DOWN. A heightfield's lighting
	# normal always points up — flip it back.
	if face_normal.y < 0.0:
		face_normal = -face_normal
	for p in [p_a, p_b, p_c]:
		verts.append(p)
		normals.append(face_normal)
		colors.append(_color_for_height(p.y, p_step, face_normal.y))


## The tint rule of the stage. Step 2 is the book's first splat map:
## colour is a pure function of height (plus a flat underwater sand).
func _color_for_height(h: float, p_step: int, slope_y: float = 1.0) -> Color:
	if p_step < 2:
		var t: float = clampf((h + 3.0) / 16.0, 0.0, 1.0)
		return Color(0.16, 0.20, 0.13).lerp(Color(0.48, 0.47, 0.40), t)
	if p_step >= 3:
		# Slope rule first: a steep face is rock, whatever its height.
		if h >= 0.9 and slope_y < 0.72:
			return Color(0.36, 0.33, 0.31)
		# Wet-sand band just above the waterline.
		if h >= 0.25 and h < 0.55:
			return Color(0.52, 0.42, 0.27)
	if h < -0.8:
		return Color(0.04, 0.16, 0.28) # deep seabed — blends with the water
	if h < 0.25:
		return Color(0.45, 0.40, 0.27) # underwater / shoreline sand
	if h < 0.9:
		return Color(0.72, 0.62, 0.38) # beach sand
	if h < 3.2:
		return Color(0.16, 0.42, 0.14) # grass
	if h < 5.8:
		return Color(0.07, 0.27, 0.10) # forest green
	if h < 8.2:
		return Color(0.38, 0.36, 0.34) # rock
	return Color(0.90, 0.91, 0.94) # snow


## A deep floor under the whole sea, so the water's transparency shows
## the same colour everywhere — otherwise the terrain patch's own
## seabed would show through as a square outline around the island.
func _build_seabed() -> MeshInstance3D:
	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	var plane := PlaneMesh.new()
	plane.size = Vector2(WATER_SIZE, WATER_SIZE)
	seabed.mesh = plane
	seabed.position = Vector3(0.0, -3.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.16, 0.28)
	mat.roughness = 1.0
	seabed.material_override = mat
	return seabed


func _build_water() -> MeshInstance3D:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(WATER_SIZE, WATER_SIZE)
	water.mesh = plane
	water.position = Vector3(0.0, config.sea_level, 0.0)
	var mat := StandardMaterial3D.new()
	# Nearly opaque on purpose: at lower alpha the submerged terrain
	# patch shows through as a square outline around the island (its
	# shading differs from the open seabed plane's). 0.95 keeps a hint
	# of depth at the shoreline without the patch edge appearing.
	mat.albedo_color = Color(0.05, 0.25, 0.55, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.05
	water.material_override = mat
	return water
