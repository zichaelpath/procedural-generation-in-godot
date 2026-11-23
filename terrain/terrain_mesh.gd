@tool
class_name TerrainMesh
extends MeshInstance3D

## Builder half of the terrain pipeline: reads a TerrainHeight (data) and
## produces an ArrayMesh. Knows triangles, knows nothing about noise.
##
## Assembled across Part II:
##   Ch9  rebuild (smooth/flat), height ramp vertex colours
##   Ch12 biome vertex colour (tint) + apply_splat_material()
##   Ch13 build_chunk_mesh() + skirt (static, array-based)
##   Ch14 add_heightmap_collision()
##
## Integration notes (see chapter discrepancy report):
## - flat_shaded is an @export here (Listing 9.3 declares a plain var)
##   because the chapter's own engine shot requires it in the Inspector.
## - The ramp/splat materials are assigned via material_override
##   (GeometryInstance3D): the listings' `surface_material_override`
##   is not a Godot 4 property and errors at runtime.
## - use_biome_colors / use_splat / grey_mode are stage display switches:
##   steps 0-1 show the grey shape pass, steps 2-6 the height ramp,
##   step 7 the biome tint + splat path (Listing 12.2's arrangement).

@export var flat_shaded: bool = false

# Ramp thresholds in metres of height, editable live in the Inspector.
# Art direction belongs here, not buried in the colour function.
@export var sand_top: float = 6.5
@export var grass_end: float = 16.0
@export var rock_end: float = 24.0
@export var blend: float = 2.5  # metres of soft transition at each boundary

@export var use_biome_colors: bool = false
@export var use_splat: bool = false
@export var grey_mode: bool = false

var _material: StandardMaterial3D

func rebuild(data: TerrainHeight) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(data.cells):
		for ix in range(data.cells):
			# Cell corners: a b / c d in plan view (x right, z down-screen).
			var a: Vector3 = _vertex(data, ix, iz)
			var b: Vector3 = _vertex(data, ix + 1, iz)
			var c: Vector3 = _vertex(data, ix, iz + 1)
			var d: Vector3 = _vertex(data, ix + 1, iz + 1)
			# Winding: Godot front faces are CLOCKWISE seen from the
			# front, so from above the working order is a,b,c / b,d,c.
			# (Listing 9.2's a,c,b / b,c,d is counter-clockwise from
			# above and renders inside-out in Godot — see the chapter
			# discrepancy report; Ch9 Exercise 1's symptom, in the
			# listing itself. The proof stage's working order agrees.)
			_add_tri(st, data, a, b, c,
					_corner_color(data, ix, iz), _corner_color(data, ix + 1, iz), _corner_color(data, ix, iz + 1))
			_add_tri(st, data, b, d, c,
					_corner_color(data, ix + 1, iz), _corner_color(data, ix + 1, iz + 1), _corner_color(data, ix, iz + 1))
	if flat_shaded:
		# Normals were set per-triangle inside _add_tri; do NOT smooth them.
		pass
	else:
		st.generate_normals()  # averages face normals at shared vertices
	mesh = st.commit()
	if use_splat:
		apply_splat_material()
	else:
		material_override = _get_material()

func _vertex(data: TerrainHeight, ix: int, iz: int) -> Vector3:
	var wp: Vector2 = data.grid_to_world(ix, iz)
	return Vector3(wp.x, data.grid_height(ix, iz), wp.y)

func _corner_color(data: TerrainHeight, ix: int, iz: int) -> Color:
	if grey_mode:
		# Steps 0-1 display convention (Chapter 9): judge shape before
		# colour — a neutral grey ramp over the same heights.
		var t: float = clampf(data.grid_height(ix, iz) / data.height_scale, 0.0, 1.0)
		var g: float = lerpf(0.07, 0.30, t)
		return Color(g, g, g * 1.02)
	if use_biome_colors:
		return biome_color(data, ix, iz)
	return height_color(data.grid_height(ix, iz))

func _add_tri(st: SurfaceTool, data: TerrainHeight,
		p1: Vector3, p2: Vector3, p3: Vector3,
		c1: Color, c2: Color, c3: Color) -> void:
	if flat_shaded:
		# One normal for the whole face: the cross product of its edges.
		# With Godot's clockwise-from-above winding the raw cross
		# product points DOWN; a heightfield's lighting normal always
		# points up — flip it back (the proof stage does the same).
		var n: Vector3 = (p2 - p1).cross(p3 - p1).normalized()
		if n.y < 0.0:
			n = -n
		st.set_normal(n)
	var pts: Array[Vector3] = [p1, p2, p3]
	var cols: Array[Color] = [c1, c2, c3]
	for k in range(3):
		var p: Vector3 = pts[k]
		# UVs in 0..1 across the whole world so Chapter 12's splat
		# material maps once over the terrain.
		st.set_uv(Vector2((p.x + data.world_size * 0.5) / data.world_size,
				(p.z + data.world_size * 0.5) / data.world_size))
		st.set_color(cols[k])
		st.add_vertex(p)

func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		# Project practice (the proof stage does the same): specular
		# wash flattens the ramp under the stage's bright sky ambient.
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material

# The ramp: height in, colour out. Small and replaceable on purpose —
# Chapter 12 replaces its insides with biome colour + a splat shader,
# and nothing around it has to change.
func height_color(h: float) -> Color:
	var sand := Color(0.76, 0.70, 0.47)
	var grass := Color(0.32, 0.55, 0.25)
	var rock := Color(0.45, 0.42, 0.40)
	var snow := Color(0.92, 0.93, 0.95)
	if h < sand_top:
		var w: float = inverse_lerp(sand_top - blend, sand_top, h)
		return sand.lerp(grass, clampf(w, 0.0, 1.0)) if h > sand_top - blend else sand
	elif h < grass_end:
		var w2: float = inverse_lerp(grass_end - blend, grass_end, h)
		return grass.lerp(rock, clampf(w2, 0.0, 1.0)) if h > grass_end - blend else grass
	elif h < rock_end:
		var w3: float = inverse_lerp(rock_end - blend, rock_end, h)
		return rock.lerp(snow, clampf(w3, 0.0, 1.0)) if h > rock_end - blend else rock
	return snow

# --- Chapter 12, Listing 12.2: biome colour + splat material ---

# One flat colour per biome; the BLEND comes from neighbour averaging,
# never from blurring the data grid itself.
func biome_base_color(id: int) -> Color:
	match id:
		BiomeClassifier.OCEAN: return Color(0.13, 0.28, 0.42)
		BiomeClassifier.BEACH: return Color(0.76, 0.70, 0.47)
		BiomeClassifier.DESERT: return Color(0.82, 0.66, 0.38)
		BiomeClassifier.GRASSLAND: return Color(0.45, 0.60, 0.28)
		BiomeClassifier.FOREST: return Color(0.20, 0.42, 0.20)
		BiomeClassifier.RAINFOREST: return Color(0.10, 0.38, 0.22)
		BiomeClassifier.TAIGA: return Color(0.30, 0.42, 0.30)
		BiomeClassifier.TUNDRA: return Color(0.62, 0.62, 0.52)
		BiomeClassifier.ROCK: return Color(0.45, 0.42, 0.40)
		BiomeClassifier.SNOW: return Color(0.92, 0.93, 0.95)
	return Color(1, 0, 1)  # magenta: an unclassified cell is a BUG, shown loudly

func biome_color(data: TerrainHeight, ix: int, iz: int) -> Color:
	# Home cell votes twice, each existing neighbour once: identity
	# survives, borders grade over a few cells.
	var total: Color = biome_base_color(data.biome_at(ix, iz)) * 2.0
	var votes: float = 2.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ix + d.x
		var nz: int = iz + d.y
		if nx >= 0 and nz >= 0 and nx <= data.cells and nz <= data.cells:
			total += biome_base_color(data.biome_at(nx, nz))
			votes += 1.0
	var col: Color = total / votes
	# Shoreline reads: underwater ground darkens and cools (seen through
	# the plane); the band just above sea level is always beach.
	if data.grid_height(ix, iz) < data.sea_level:
		return col * Color(0.55, 0.65, 0.75)
	if data.grid_height(ix, iz) < data.sea_level + 1.2:
		return Color(0.76, 0.70, 0.47)
	return col

func apply_splat_material() -> void:
	var mat := ShaderMaterial.new()
	var sh: Shader = load("res://terrain/terrain.gdshader")
	mat.shader = sh
	mat.set_shader_parameter("grass_tex", load("res://terrain/textures/grass.png"))
	mat.set_shader_parameter("rock_tex", load("res://terrain/textures/rock.png"))
	mat.set_shader_parameter("sand_tex", load("res://terrain/textures/sand.png"))
	mat.set_shader_parameter("snow_tex", load("res://terrain/textures/snow.png"))
	material_override = mat

# --- Chapter 13, Listing 13.4: the array-based chunk mesh path ---

## Builds one chunk's ArrayMesh from supplied heights + normals, with
## an optional downward SKIRT strip around the perimeter (Section 13.4).
static func build_chunk_mesh(heights: PackedFloat32Array, verts_per_side: int,
		cell_size: float, normals: PackedVector3Array,
		skirt_depth: float = 0.0) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for gz in range(verts_per_side - 1):
		for gx in range(verts_per_side - 1):
			var i00: int = gz * verts_per_side + gx
			var i10: int = i00 + 1
			var i01: int = i00 + verts_per_side
			var i11: int = i01 + 1
			# Winding as in rebuild(): clockwise from above (Listing
			# 13.4's i00,i01,i10 order is the same inside-out bug as
			# Listing 9.2's — see the discrepancy report).
			for idx in [i00, i10, i01, i10, i11, i01]:
				var vx: int = idx % verts_per_side
				var vz: int = idx / verts_per_side
				verts.append(Vector3(float(vx) * cell_size, heights[idx], float(vz) * cell_size))
				norms.append(normals[idx] if normals.size() == heights.size() else Vector3.UP)
				cols.append(Color(1, 1, 1))
				indices.append(verts.size() - 1)  # the vertex just appended
	if skirt_depth > 0.0:
		_append_skirt(verts, norms, cols, indices, heights, verts_per_side, cell_size, skirt_depth)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _append_skirt(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, indices: PackedInt32Array,
		heights: PackedFloat32Array, side: int, cell_size: float, depth: float) -> void:
	# A downward strip around the chunk's perimeter: from each border
	# vertex straight down. It hides any crack between neighbours
	# behind real geometry.
	var perimeter: Array[int] = []
	for gx in range(side):
		perimeter.append(gx)                       # north edge
	for gz in range(1, side):
		perimeter.append(gz * side + (side - 1))   # east edge
	for gx in range(side - 2, -1, -1):
		perimeter.append((side - 1) * side + gx)   # south edge
	for gz in range(side - 2, 0, -1):
		perimeter.append(gz * side)                # west edge
	for i in range(perimeter.size()):
		var a: int = perimeter[i]
		var b: int = perimeter[(i + 1) % perimeter.size()]
		var ax: int = a % side
		var az: int = a / side
		var bx: int = b % side
		var bz: int = b / side
		var top_a := Vector3(float(ax) * cell_size, heights[a], float(az) * cell_size)
		var top_b := Vector3(float(bx) * cell_size, heights[b], float(bz) * cell_size)
		var base: int = verts.size()
		verts.append_array(PackedVector3Array([top_a, top_b,
				Vector3(top_b.x, top_b.y - depth, top_b.z), top_a,
				Vector3(top_b.x, top_b.y - depth, top_b.z),
				Vector3(top_a.x, top_a.y - depth, top_a.z)]))
		for k in range(6):
			norms.append(Vector3.UP)
			cols.append(Color(1, 1, 1))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2,
				base + 3, base + 4, base + 5]))

# --- Chapter 14, Listing 14.2: collision ---

## Builds a HeightMapShape3D from the same grid the mesh came from, so
## what you see is exactly what you stand on. map_data wants the grid
## in row-major order with x fastest — the same layout as our arrays.
func add_heightmap_collision(data: TerrainHeight) -> StaticBody3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = data.cells + 1
	shape.map_depth = data.cells + 1
	shape.map_data = data.heights.duplicate()
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	# HeightMapShape3D is centred on its node; our mesh origin is the
	# grid's corner, so shift the body to the grid's centre.
	body.position = Vector3(data.world_size * 0.5, 0.0, data.world_size * 0.5)
	return body
