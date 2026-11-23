@tool
extends Node3D

## Part III stage. The `step` export is the part's screenshot
## contract (fixed in Chapter 15, appended by later chapters):
##   0 = scatter comparison dots   1 = chunk-border pair + pooling
##   2 = ecology proxies           3-4 = 2D plants (Ch 16)
##   5-8 = 3D plants (Ch 17-18)    9-12 = grass/wind/hillside (Ch 19)
##
## Integration notes (project harness, same pattern as
## terrain/terrain_stage.gd — the chapters' plain runtime script
## cannot be screenshotted by the book's tools):
## - @tool + rebuild() / apply_camera_preset_by_name() are the
##   capture harness's interface (tools/book_capture.gd).
## - config.sea_level is set to the chapter value 5.0 on the stage's
##   own config instance (WorldConfig's shared default is 0.0).
## - The TerrainHeight island is built once per master seed and
##   cached across step rebuilds (it is a function of the seed only);
##   rebuild() is memoised on (step, seed) so the harness's repeated
##   rebuild calls do not regrow the hillside.
## - Steps 5-8 are a LAB: the island mesh is hidden and a plain
##   ground plane (LabGround, built in code under Lab3D) grounds the
##   plants at y=0, as the chapters' lab framings require ("against
##   the sky"); on the island surface the lab plants would be buried
##   inside the centre peak.
## - The default camera preset dispatches per step (each step's
##   caption framing); --camera=pruned selects step 8's side framing.

@export var step: int = 2:
	set(value):
		step = value
		if _built:
			rebuild()
@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if _built:
			rebuild()
@export var scatter_min_dist: float = 3.4
@export var ecology_attempts: int = 2600

var config: WorldConfig
var data: TerrainHeight

var _built: bool = false
var _built_key: String = ""
var _data_seed: int = -1

@onready var terrain_mesh: TerrainMesh = $TerrainMesh
@onready var water: MeshInstance3D = $Water
@onready var sun: DirectionalLight3D = $Sun
@onready var demo: Node3D = $ScatterDemo
@onready var lab2d: CanvasLayer = $Lab2D
@onready var turtle: Turtle2D = $Lab2D/Turtle2D
@onready var lab3d: Node3D = $Lab3D
@onready var turtle3d: Turtle3D = $Lab3D/Turtle3D
@onready var skinned: MeshInstance3D = $Lab3D/SkinnedPlant
@onready var recursive_plant: MeshInstance3D = $Lab3D/RecursivePlant
@onready var world: Node3D = $World
@onready var stage_camera: Camera3D = $CameraRig/Camera3D

const DIRECTIVE_PATH := "/tmp/book_stage_directive.txt"
const ARRANGED_PATH := "/tmp/book_stage_arranged.txt"
# Part III's private capture handshake (same pattern as Part IV's
# dungeon stage): when several workers capture at once, the shared
# directive/arranged files are rewritten by foreign wrappers, so
# this stage prefers its own file pair when present.
const P3_DIRECTIVE_PATH := "/tmp/p3_stage_directive.txt"
const P3_ARRANGED_PATH := "/tmp/p3_stage_arranged.txt"

func _ready() -> void:
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_built = true
	rebuild()
	apply_camera_preset_by_name("preset")
	if Engine.is_editor_hint() and (FileAccess.file_exists(P3_DIRECTIVE_PATH) or FileAccess.file_exists(DIRECTIVE_PATH)):
		_arrange_from_directive()

## The capture harness (tools/book_capture.gd) calls rebuild() after
## setting step/seed; the editor plugin calls it too. Memoised: a
## rebuild with unchanged (step, seed) is a no-op.

func rebuild() -> void:
	if not _built or terrain_mesh == null:
		return
	var key: String = str(step) + ":" + str(master_seed)
	if key == _built_key:
		return
	_built_key = key
	_build()

func _build() -> void:
	config = WorldConfig.new()
	config.master_seed = master_seed
	config.sea_level = 5.0  # Listing 5.1's chapter value; see header note
	if data == null or _data_seed != master_seed:
		data = TerrainHeight.new()
		data.generate(config)
		_data_seed = master_seed
	terrain_mesh.rebuild(data)
	terrain_mesh.apply_splat_material()
	_build_water()
	# Clear the previous step's generated content + registries.
	for child in demo.get_children():
		demo.remove_child(child)
		child.free()
	for holder in _lab_leaf_holders:
		if is_instance_valid(holder):
			holder.get_parent().remove_child(holder)
			holder.free()
	_lab_leaf_holders.clear()
	_leaf_holders.clear()
	_leaf_mats.clear()
	_shrub_leaf_mats.clear()
	if step < 11 or step > 12:
		for child in world.get_children():
			world.remove_child(child)
			child.free()
	# Visibility contract per step (chapter stage notes).
	lab2d.visible = step == 3 or step == 4
	lab3d.visible = step >= 5 and step <= 8
	demo.visible = step <= 2 or step == 9 or step == 10
	terrain_mesh.visible = not (step >= 5 and step <= 8)
	water.visible = terrain_mesh.visible
	turtle.visible = step == 3
	var row: Node2D = get_node_or_null("Lab2D/JitterRow") as Node2D
	if row != null:
		row.visible = step == 4
	turtle3d.visible = step == 5
	_ensure_lab_ground()
	match step:
		0: _show_distributions()
		1: _show_chunk_pair()
		2: _show_ecology()
		3: _show_gallery()
		4: _show_jitter_row()
		5: _show_turtle_3d()
		6: _show_skinned_tree()
		7: _show_species_trio()
		8: _show_colonization()
		9: _show_grass()
		10: _show_grass()
		11: _show_hillside(false)
		12: _show_hillside(true)
	apply_camera_preset_by_name("preset")

var _lab_ground: MeshInstance3D = null

func _ensure_lab_ground() -> void:
	if not (step >= 5 and step <= 8):
		if _lab_ground != null:
			_lab_ground.visible = false
		return
	if _lab_ground == null:
		_lab_ground = MeshInstance3D.new()
		_lab_ground.name = "LabGround"
		var plane := PlaneMesh.new()
		plane.size = Vector2(80.0, 80.0)
		_lab_ground.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.42, 0.24)
		mat.roughness = 1.0
		_lab_ground.material_override = mat
		_lab_ground.position = Vector3(0.0, -0.02, 0.0)
		lab3d.add_child(_lab_ground)
	_lab_ground.visible = true

func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(config.terrain_world_size * 3.0, config.terrain_world_size * 3.0)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	water.material_override = mat
	water.position.y = config.sea_level

## Step 0: three distributions over one rectangle, as dots (data
## first) — the verdict is read off the panels, not asserted.
func _show_distributions() -> void:
	var region := Vector2(60.0, 40.0)
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_SCATTER)
	var panels: Dictionary = {
		"random": Scatter.random_points(region, 300, rng),
		"jittered": Scatter.jittered_grid(region, scatter_min_dist, rng),
		"poisson": Scatter.poisson_disc(region, scatter_min_dist, rng),
	}
	var x_off: float = -70.0
	for key in ["random", "jittered", "poisson"]:
		var pts: Array = panels[key]
		print("Step 0 — ", key, ": ", pts.size(), " points")
		_add_dots(pts, Vector3(x_off, 0.0, -20.0))
		x_off += 70.0

func _add_dots(pts: Array, offset: Vector3) -> void:
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.35
	dot_mesh.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	dot_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot_mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		var p: Vector2 = pts[i]
		var ground: float = data.height_at(offset.x + p.x, offset.z + p.y)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(offset.x + p.x, ground + 0.3, offset.z + p.y)))
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	demo.add_child(holder)

## Step 1: two adjacent chunks, one border, no seam. The right chunk
## is filled with the left chunk's points pre-loaded (Section 15.3);
## the closest cross-border pair is printed and must be >= MIN_DIST.
func _show_chunk_pair() -> void:
	var manager := ChunkManager.new()
	manager.setup(data, config)
	var left_coord := Vector2i(0, 0)
	var right_coord := Vector2i(1, 0)
	var left_data: ChunkData = manager.get_or_generate_data(left_coord)
	ChunkScatter.fill_chunk(left_data, config, [])
	var neighbours: Array[Vector2] = []
	for item in left_data.scatter:
		var wp: Vector3 = item["position"]
		neighbours.append(Vector2(wp.x - config.chunk_size_m, wp.z))
	var right_data: ChunkData = manager.get_or_generate_data(right_coord)
	ChunkScatter.fill_chunk(right_data, config, neighbours)
	var worst: float = INF
	for a in left_data.scatter:
		for b in right_data.scatter:
			var pa: Vector3 = a["position"]
			var pb: Vector3 = b["position"]
			worst = minf(worst, Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)))
	print("Step 1 — chunk pair: left ", left_data.scatter.size(), ", right ",
		right_data.scatter.size(), " | closest cross-border pair: ", worst,
		" (minimum distance ", ChunkScatter.MIN_DIST, ")")
	for chunk_data in [left_data, right_data]:
		var node := TerrainChunk.new()
		demo.add_child(node)
		node.build_from_data(chunk_data, config, null)
		node.build_collision(chunk_data, config)
		node.add_child(ChunkScatter.build_holder(chunk_data, config))

## Step 2: one ecology pass over the island's centre, rendered with
## proxy instancing. Chapter 19 re-renders this same manifest shape
## with hero trees; the placement does not change.
func _show_ecology() -> void:
	var region := Rect2(-60.0, -60.0, 120.0, 120.0)
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_SCATTER)
	var manifest: Array[Dictionary] = Scatter.ecology_scatter(data, region, ecology_attempts, rng)
	var counts: Dictionary = {"tree": 0, "shrub": 0, "rock": 0}
	for item in manifest:
		counts[item["kind"]] = int(counts[item["kind"]]) + 1
	print("Step 2 — ecology manifest: ", manifest.size(), " placed — ", counts)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.15
	trunk_mesh.height = 1.5
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.15
	canopy_mesh.height = 2.1
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.25, 0.45, 0.2)
	canopy_mesh.material = canopy_mat
	var shrub_mesh := SphereMesh.new()
	shrub_mesh.radius = 0.55
	shrub_mesh.height = 0.8
	var shrub_mat := StandardMaterial3D.new()
	shrub_mat.albedo_color = Color(0.4, 0.5, 0.22)
	shrub_mesh.material = shrub_mat
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.44, 0.42)
	rock_mesh.material = rock_mat
	var by_kind: Dictionary = {"tree": [], "shrub": [], "rock": []}
	for item in manifest:
		by_kind[item["kind"]].append(item)
	_add_instanced(trunk_mesh, by_kind["tree"], 0.75)
	_add_instanced(canopy_mesh, by_kind["tree"], 2.4)
	_add_instanced(shrub_mesh, by_kind["shrub"], 0.4)
	_add_instanced(rock_mesh, by_kind["rock"], 0.3)

func _add_instanced(mesh: Mesh, items: Array, y_offset: float) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var item: Dictionary = items[i]
		var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(item["position"]) + Vector3(0.0, y_offset * float(item["scale"]), 0.0)))
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	demo.add_child(holder)

# --- Chapter 16: 2D turtle + gallery (steps 3-4) ---

var _gallery_index: int = 0

## Step 3: print the growth ladder, then show gallery species 0.
## Keys 1-5 switch species while the stage runs.
func _show_gallery() -> void:
	lab2d.visible = true
	var rules: Dictionary = {"F": "FF+[-F+F]-[+F-F]"}
	for gen in range(0, 6):
		var result: String = LSystem.expand("F", rules, gen)
		print("Generation ", gen, " — length ", result.length())
	_show_species(0)

func _show_species(idx: int) -> void:
	_gallery_index = idx
	var sp: Dictionary = PlantGallery.SPECIES[idx]
	var grown: String = LSystem.expand(str(sp["axiom"]), sp["rules"], int(sp["iterations"]))
	# Algae draws with A/B symbols: transform DATA to fit the
	# interpreter instead of growing the interpreter to fit the data.
	if str(sp["name"]).begins_with("Algae"):
		grown = grown.replace("A", "F").replace("B", "F")
	# Parameters first, string last: the string assignment is the
	# final redraw, with the species' physics already in place.
	turtle.angle_degrees = float(sp["angle"])
	turtle.segment_length = float(sp["length"])
	turtle.source_string = grown
	print("Species: ", sp["name"])

## Step 4: the jitter row (Listing 16.7's harness lives here) plus
## the stochastic proof: three expansions from ONE plants stream,
## replayed from a FRESH stream, must match length for length.
func _show_jitter_row() -> void:
	lab2d.visible = true
	turtle.visible = false
	var weighted_rules: Dictionary = {
		"F": [
			[0.7, "FF+[-F+F]-[+F-F]"],
			[0.3, "F[+F][-F]F"],
		],
	}
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	var first_lengths: Array[int] = []
	for n in 3:
		first_lengths.append(LSystem.expand_stochastic("F", weighted_rules, 4, rng).length())
	var rng2: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	var second_lengths: Array[int] = []
	for n in 3:
		second_lengths.append(LSystem.expand_stochastic("F", weighted_rules, 4, rng2).length())
	print("Stochastic replay — first: ", first_lengths, " second: ", second_lengths,
		" identical: ", first_lengths == second_lengths)
	# The row itself: 8 individuals of one species, per-plant child
	# seeds drawn in stream order, jitter at the section's 15%.
	var plant_string: String = LSystem.expand("F", {"F": "FF+[-F+F]-[+F-F]"}, 4)
	var stream: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	for n in 8:
		var t: Turtle2D = get_node("Lab2D/JitterRow/Turtle%d" % (n + 1)) as Turtle2D
		var child := RandomNumberGenerator.new()
		child.seed = stream.randi()
		t.jitter_rng = child
		t.length_jitter = 0.15
		t.angle_jitter_degrees = 25.0 * 0.15
		t.angle_degrees = 25.0
		t.segment_length = 3.5
		t.source_string = plant_string

# --- Chapter 17: 3D turtle, skinning, species (steps 5-7) ---

var _bark_mat: StandardMaterial3D
var _lab_leaf_holders: Array[MultiMeshInstance3D] = []

func _make_bark_material() -> void:
	_bark_mat = StandardMaterial3D.new()
	_bark_mat.vertex_color_use_as_albedo = true
	_bark_mat.roughness = 0.9

## Step 5: the gallery bush in 3D, boxes and all — the roll inside
## the brackets is what opens the crown into a volume.
func _show_turtle_3d() -> void:
	lab3d.visible = true
	var rules: Dictionary = {"F": "FF+[\\-F+F]-[+F-F]"}
	turtle3d.grow(LSystem.expand("F", rules, 4))

## Step 6: grow with the turtle (data), skin with TreeBuilder,
## canopy with build_leaves. The second build_mesh call proves the
## branch cache: unique branches stay flat, reuses jump.
func _show_skinned_tree() -> void:
	lab3d.visible = true
	_make_bark_material()
	var rules: Dictionary = {"F": "FF+[\\-F+F]-[+F-F]"}
	turtle3d.grow(LSystem.expand("F", rules, 4))
	turtle3d.visible = false  # we only wanted its segment data
	var species: Dictionary = TreeBuilder.SPECIES["Oak"]
	skinned.mesh = TreeBuilder.build_mesh(turtle3d.segments, 8, species)
	skinned.material_override = _bark_mat
	TreeBuilder.build_mesh(turtle3d.segments, 8, species)  # cache proof; mesh discarded
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	_add_leaf_holder(turtle3d.segments, rng, species, Vector3.ZERO)

## Step 7: three species, one algorithm. Change nothing but the
## row name and the whole tree changes kind — skeleton, bark,
## taper, leaves, dead stubs.
## (Project integration: Listing 17.8 names this _show_species(),
## but Listing 16.5 already defines _show_species(idx) in this file
## and GDScript has no overloading — renamed _show_species_trio()
## here; the listing body is otherwise verbatim.)
func _show_species_trio() -> void:
	lab3d.visible = true
	_make_bark_material()
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TREES)
	var holders: Array[MeshInstance3D] = [$Lab3D/SpeciesA, $Lab3D/SpeciesB, $Lab3D/SpeciesC]
	var names: Array[String] = ["Oak", "Pine", "Willow"]
	for i in names.size():
		var species: Dictionary = TreeBuilder.SPECIES[names[i]]
		var segments: Array[Dictionary] = TreeBuilder.recursive_skeleton(
			Vector3.ZERO, Vector3.UP, float(species["start_length"]),
			int(species["depth"]), species, rng)
		holders[i].mesh = TreeBuilder.build_mesh(segments, 8, species)
		holders[i].material_override = _bark_mat
		_add_leaf_holder(segments, rng, species, holders[i].position)

# --- Chapter 18: space colonization (step 8) ---

## Step 8: four species, one algorithm, identical dials.
## Only the point clouds differ — including the fourth, whose
## cloud is offset downwind of its trunk (the exercise, pre-built
## so the captures can prove it).
func _show_colonization() -> void:
	lab3d.visible = true
	_make_bark_material()
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TREES)
	var jobs: Array = [
		[$Lab3D/TreeBall, SpaceColonization.cloud_ball(Vector3(-6, 2.6, 0), 1.5, 260, rng), Vector3(-6, 0, 0)],
		[$Lab3D/TreeUmbrella, SpaceColonization.cloud_umbrella(Vector3(-2, 3.4, 0), 1.9, 240, rng), Vector3(-2, 0, 0)],
		[$Lab3D/TreeCone, SpaceColonization.cloud_cone(Vector3(2, 1.6, 0), 3.2, 0.95, 260, rng), Vector3(2, 0, 0)],
		# Wind-pruned: the cloud floats downwind (+x) and slightly
		# low, so the trunk must lean and all growth streams one way.
		[$Lab3D/TreePruned, SpaceColonization.cloud_umbrella(Vector3(6 + 1.7, 2.9, 0), 1.8, 240, rng), Vector3(6, 0, 0)],
	]
	for job in jobs:
		var sc := SpaceColonization.new()
		var segments: Array[Dictionary] = sc.grow(job[1], job[2], rng)
		var holder: MeshInstance3D = job[0]
		# PROJECT FIX (Listing 18.3 inconsistency, chapter untouched):
		# the job's cloud points and trunk base are already in lab
		# world coordinates, so the grown segments carry the tree's
		# placement. The holder nodes ALSO sit at x = -6/-2/+2/+6 in
		# the scene, which applied the offset twice (trees landed at
		# -12/-4/+4/+12). Zero the holder transform and pass a zero
		# leaf offset so each tree stands where its cloud was defined.
		holder.position = Vector3.ZERO
		holder.mesh = TreeBuilder.build_mesh(segments, 8, TreeBuilder.SPECIES["Oak"])
		holder.material_override = _bark_mat
		_add_leaf_holder(segments, rng, TreeBuilder.SPECIES["Oak"], Vector3.ZERO)

# --- Chapter 19: grass (steps 9-10) ---

## Step 9: one grass chunk over the island's centre, still air.
## Step 10 runs this same function — the only difference is the
## material Listing 19.3 swaps in underneath it.
func _show_grass() -> void:
	demo.visible = true
	var rng: RandomNumberGenerator = SeedBank.stream_for(config.master_seed, SeedBank.STREAM_DRESSING)
	GrassField.build_for_chunk(demo, Rect2(-25.0, -5.0, 50.0, 50.0), 25000, data, rng)

# --- Chapter 19: leaf holders, seasons, wind (Listings 19.3/19.5) ---

var _leaf_holders: Array[MultiMeshInstance3D] = []
var _leaf_mats: Array[ShaderMaterial] = []
var _shrub_leaf_mats: Array[ShaderMaterial] = []

func _make_leaf_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://plants/leaf_wind.gdshader")
	mat.set_shader_parameter("leaf_texture", load("res://plants/leaf.png"))
	_leaf_mats.append(mat)
	return mat

func _add_leaf_holder(segments: Array[Dictionary], rng: RandomNumberGenerator, species: Dictionary, offset: Vector3, parent: Node3D = null, scale_factor: float = 1.0) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = _make_leaf_material()
	var holder := MultiMeshInstance3D.new()
	holder.name = "LeafCards%d" % _leaf_holders.size()
	holder.multimesh = TreeBuilder.build_leaves(segments, quad,
		float(species.get("leaf_density", 1.0)), 2, rng,
		float(species.get("leaf_coherence", 0.0)))
	holder.position = offset
	holder.scale = Vector3.ONE * scale_factor
	holder.set_meta("leaf_full_count", holder.multimesh.instance_count)
	var host: Node3D = parent if parent != null else lab3d
	host.add_child(holder)
	_leaf_holders.append(holder)
	if host == lab3d:
		_lab_leaf_holders.append(holder)
	print("Leaves placed: ", holder.multimesh.instance_count)
	return holder

var wind_strength: float = 0.35
var current_season: String = "summer"

## Presentation only: recolours and thins the EXISTING world.
## Nothing here places, grows, or regenerates anything — that is
## the entire point of a season.
func apply_season(season_name: String) -> void:
	current_season = season_name
	var row: Dictionary = Seasons.SEASONS[season_name]
	sun.light_color = row["sun_color"]
	sun.light_energy = float(row["sun_energy"])
	var gm: Material = GrassField.grass_material()
	if gm is ShaderMaterial:
		(gm as ShaderMaterial).set_shader_parameter("season_tint", row["grass"])
	for mat in _leaf_mats:
		mat.set_shader_parameter("canopy_tint", row["canopy"])
	for mat in _shrub_leaf_mats:
		mat.set_shader_parameter("canopy_tint", row["shrub"])
	var density: float = float(row["leaf_density"])
	for holder in _leaf_holders:
		if not is_instance_valid(holder) or holder.multimesh == null:
			continue
		var full: int = int(holder.get_meta("leaf_full_count"))
		holder.multimesh.instance_count = int(round(float(full) * density))
	print("Season: ", season_name, " (leaf density ", density, ")")

func _set_wind(value: float) -> void:
	wind_strength = clampf(value, 0.0, 1.5)
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	print("Wind strength: ", snappedf(wind_strength, 0.01))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if step >= 10:
		if key.keycode == KEY_Q:
			_set_wind(wind_strength - 0.1)
		elif key.keycode == KEY_E:
			_set_wind(wind_strength + 0.1)
	if step == 12:
		if key.keycode == KEY_F1:
			apply_season("spring")
		elif key.keycode == KEY_F2:
			apply_season("summer")
		elif key.keycode == KEY_F3:
			apply_season("autumn")
		elif key.keycode == KEY_F4:
			apply_season("winter")
		elif key.keycode == KEY_R:
			_world_seed += 1
			_build_hillside(_world_seed)

# --- Chapter 19: the living hillside (steps 11-12, Listing 19.6) ---

const HILLSIDE_REGION := Rect2(-60.0, -60.0, 120.0, 120.0)
const HERO_TREE_CAP: int = 24
var _shrub_mat: StandardMaterial3D = null
var _world_seed: int = 0

func _show_hillside(autumn_first: bool) -> void:
	lab3d.visible = false
	demo.visible = false
	_world_seed = config.master_seed
	if autumn_first:
		current_season = "autumn"
	else:
		current_season = "summer"
	_build_hillside(_world_seed)

## The conductor: one seed -> one living hillside. Terrain is
## the stage's own (master seed, built in _ready); everything
## LIVING on it is a function of (land, world_seed) alone.
func _build_hillside(world_seed: int) -> void:
	var started: int = Time.get_ticks_msec()
	if world.get_child_count() > 0:
		# Clear IN PLACE: the World node keeps its identity (and
		# its Scene-dock row) across rebuilds. Children leave the
		# tree immediately and are freed at frame end.
		for child in world.get_children():
			world.remove_child(child)
			child.queue_free()
	_leaf_holders.clear()
	_leaf_mats.clear()
	_shrub_leaf_mats.clear()
	_make_bark_material()
	# 1. Placement: Chapter 15's ecology pass, untouched.
	var scatter_rng: RandomNumberGenerator = SeedBank.stream_for(world_seed, SeedBank.STREAM_SCATTER)
	var manifest: Array[Dictionary] = Scatter.ecology_scatter(data, HILLSIDE_REGION, ecology_attempts, scatter_rng)
	var trees: Array[Dictionary] = []
	var shrubs: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	for item in manifest:
		match String(item["kind"]):
			"tree": trees.append(item)
			"shrub": shrubs.append(item)
			"rock": rocks.append(item)
	# 2. Heroes in front, proxies behind (Chapter 18's casting).
	var tree_rng: RandomNumberGenerator = SeedBank.stream_for(world_seed, SeedBank.STREAM_TREES)
	_place_hero_trees(trees.slice(0, mini(HERO_TREE_CAP, trees.size())), tree_rng)
	_place_proxies(trees.slice(mini(HERO_TREE_CAP, trees.size())), rocks)
	# 3. Shrubs and accents from the plants stream.
	var plant_rng: RandomNumberGenerator = SeedBank.stream_for(world_seed, SeedBank.STREAM_PLANTS)
	_place_shrubs(shrubs, plant_rng)
	_place_accents(trees, plant_rng)
	# 4. Grass: four chunks tiling the region, 100k blades.
	var grass_rng: RandomNumberGenerator = SeedBank.stream_for(world_seed, SeedBank.STREAM_DRESSING)
	for cx in 2:
		for cz in 2:
			var rect := Rect2(-60.0 + cx * 60.0, -60.0 + cz * 60.0, 60.0, 60.0)
			GrassField.build_for_chunk(world, rect, 25000, data, grass_rng)
	apply_season(current_season)
	print("Hillside (seed ", world_seed, "): heroes ", mini(HERO_TREE_CAP, trees.size()),
		", proxy trees ", maxi(0, trees.size() - HERO_TREE_CAP), ", shrubs ", shrubs.size(),
		", rocks ", rocks.size(), " — built in ", Time.get_ticks_msec() - started, " ms",
		" — streams: scatter/trees/plants/dressing")

func _place_hero_trees(placements: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var species_names: Array[String] = ["Oak", "Willow", "Pine"]
	for i in placements.size():
		var item: Dictionary = placements[i]
		var pos: Vector3 = item["position"]
		var species: Dictionary = TreeBuilder.SPECIES[species_names[i % 3]]
		var sc := SpaceColonization.new()
		var cloud: Array[Vector3]
		match i % 3:
			0: cloud = SpaceColonization.cloud_ball(Vector3(0, 3.1, 0), 1.6, 240, rng)
			1: cloud = SpaceColonization.cloud_umbrella(Vector3(0, 3.3, 0), 1.9, 220, rng)
			_: cloud = SpaceColonization.cloud_cone(Vector3(0, 1.7, 0), 3.1, 0.95, 240, rng)
		var segments: Array[Dictionary] = sc.grow(cloud, Vector3.ZERO, rng)
		var holder := MeshInstance3D.new()
		holder.name = "HeroTree%d" % i
		holder.mesh = TreeBuilder.build_mesh(segments, 8, species)
		holder.material_override = _bark_mat
		holder.position = pos
		holder.scale = Vector3.ONE * float(item["scale"])
		world.add_child(holder)
		_add_leaf_holder(segments, rng, species, pos, world, float(item["scale"]))

## Chapter 15's step-2 instancing helper, generalised with the
## parent it was always going to need: same per-item yaw/scale
## from the manifest, same y-offset in item-scaled metres.
func _add_instanced_under(parent_node: Node3D, mesh: Mesh, items: Array, y_offset: float, holder_name: String = "") -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var item: Dictionary = items[i]
		var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(item["position"]) + Vector3(0.0, y_offset * float(item["scale"]), 0.0)))
	var holder := MultiMeshInstance3D.new()
	if holder_name != "":
		holder.name = holder_name
	holder.multimesh = mm
	parent_node.add_child(holder)

func _place_proxies(proxy_trees: Array[Dictionary], rocks: Array[Dictionary]) -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.15
	trunk_mesh.height = 1.5
	_add_instanced_under(world, trunk_mesh, proxy_trees, 0.75, "ProxyTrunks")
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.15
	canopy_mesh.height = 2.1
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.25, 0.45, 0.2)
	canopy_mesh.material = canopy_mat
	_add_instanced_under(world, canopy_mesh, proxy_trees, 2.4, "ProxyCanopies")
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.44, 0.42)
	rock_mesh.material = rock_mat
	_add_instanced_under(world, rock_mesh, rocks, 0.3, "Rocks")

func _place_shrubs(placements: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	# Six stochastic variants, built once, instanced everywhere.
	var rules: Dictionary = {"F": [
		[3.0, "FF+[\\-F+F]-[+F-F]"],
		[1.0, "FF-[/-F+F]+[\\F-F]"],
	]}
	var shrub_species: Dictionary = {
		"bark": Color(0.30, 0.26, 0.14), "twig": Color(0.35, 0.48, 0.18),
		"base_radius": 0.05, "taper": 0.80, "depth_step": 0.72,
		"leaf_density": 1.4, "leaf_coherence": 0.15,
	}
	var by_variant: Dictionary = {}
	for i in placements.size():
		var v: int = i % 6
		if not by_variant.has(v):
			by_variant[v] = []
		by_variant[v].append(placements[i])
	for v in by_variant.keys():
		turtle3d.angle_degrees = 26.0
		turtle3d.segment_length = 0.16
		turtle3d.grow(LSystem.expand_stochastic("F", rules, 3, rng))
		var segments: Array[Dictionary] = turtle3d.segments.duplicate()
		var branch_mesh: ArrayMesh = TreeBuilder.build_mesh(segments, 5, shrub_species)
		var items: Array = by_variant[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = branch_mesh
		mm.instance_count = items.size()
		for i in items.size():
			var item: Dictionary = items[i]
			var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"]))
			mm.set_instance_transform(i, Transform3D(basis, item["position"]))
		var holder := MultiMeshInstance3D.new()
		holder.name = "Shrubs%d" % int(v)
		holder.multimesh = mm
		holder.material_override = _bark_mat
		world.add_child(holder)
		# Leaves: build_leaves works in the variant's local space;
		# compose each placement transform with each local leaf
		# transform to flatten the hierarchy into one MultiMesh.
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		var leaf_mat: ShaderMaterial = _make_leaf_material()
		_shrub_leaf_mats.append(leaf_mat)
		quad.material = leaf_mat
		var local_leaves: MultiMesh = TreeBuilder.build_leaves(segments, quad, 1.4, 1, rng, 0.15)
		var leaf_mm := MultiMesh.new()
		leaf_mm.transform_format = MultiMesh.TRANSFORM_3D
		leaf_mm.mesh = quad
		leaf_mm.instance_count = items.size() * local_leaves.instance_count
		var n: int = 0
		for i in items.size():
			var item: Dictionary = items[i]
			var place := Transform3D(
				Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"])),
				item["position"])
			for j in local_leaves.instance_count:
				leaf_mm.set_instance_transform(n, place * local_leaves.get_instance_transform(j))
				n += 1
		var leaf_holder := MultiMeshInstance3D.new()
		leaf_holder.name = "ShrubLeaves%d" % int(v)
		leaf_holder.multimesh = leaf_mm
		leaf_holder.set_meta("leaf_full_count", leaf_mm.instance_count)
		world.add_child(leaf_holder)
		_leaf_holders.append(leaf_holder)

func _place_accents(tree_placements: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	# The composed focal point: three recursive trees in a
	# clearing the manifest itself left empty.
	var clearing := Vector3.ZERO
	var best_gap: float = -1.0
	for gx in range(-40, 41, 8):
		for gz in range(-40, 41, 8):
			var spot := Vector2(float(gx), float(gz))
			var h: float = data.height_at(spot.x, spot.y)
			if h < data.sea_level + 1.0 or data.slope_at(spot.x, spot.y) > 0.08:
				continue
			var nearest: float = INF
			for item in tree_placements:
				var p: Vector3 = item["position"]
				nearest = minf(nearest, spot.distance_to(Vector2(p.x, p.z)))
			if nearest > best_gap:
				best_gap = nearest
				clearing = Vector3(spot.x, h, spot.y)
	if best_gap < 3.0:
		print("Accents skipped: the manifest left no clearing")
		return
	var species: Dictionary = TreeBuilder.SPECIES["Oak"]
	var offsets: Array[Vector3] = [Vector3(-2.5, 0, 0.5), Vector3(0.5, 0, -2.0), Vector3(2.8, 0, 1.2)]
	for off in offsets:
		var pos: Vector3 = clearing + off
		pos.y = data.height_at(pos.x, pos.z)
		var segments: Array[Dictionary] = TreeBuilder.recursive_skeleton(
			Vector3.ZERO, Vector3.UP, float(species["start_length"]),
			int(species["depth"]), species, rng)
		var holder := MeshInstance3D.new()
		holder.name = "AccentTree"
		holder.mesh = TreeBuilder.build_mesh(segments, 8, species)
		holder.material_override = _bark_mat
		holder.position = pos
		world.add_child(holder)
		_add_leaf_holder(segments, rng, species, pos, world)
	print("Accents planted in the clearing at ", clearing, " (gap ", snappedf(best_gap, 0.1), " m)")

# --- Camera presets (called by tools/book_capture.gd) ---
# The default preset dispatches per step: every render of a step
# uses exactly its caption framing, so captures are comparable.
# Named extra: "pruned" (step 8's side camera on the fourth tree).

func apply_camera_preset_by_name(preset_name: String) -> void:
	if stage_camera == null:
		return
	stage_camera.fov = 75.0
	match preset_name:
		"pruned":
			stage_camera.fov = 55.0
			_look_camera(Vector3(6.6, 2.7, 7.6), Vector3(7.0, 2.4, 0.0))
			return
		"topdown":
			stage_camera.position = Vector3(30.0, 85.0, 0.0)
			stage_camera.rotation_degrees = Vector3(-89.5, 0.0, 0.0)
			return
		"hillside":
			_look_camera(Vector3(0.0, 30.0, 70.0), Vector3(0.0, 6.0, -10.0))
			return
		_:
			pass
	match step:
		0:
			stage_camera.position = Vector3(30.0, 85.0, 0.0)
			stage_camera.rotation_degrees = Vector3(-89.5, 0.0, 0.0)
		1:
			_look_camera(Vector3(64.0, 55.0, 105.0), Vector3(64.0, 4.0, 10.0))
		2:
			_look_camera(Vector3(0.0, 58.0, 98.0), Vector3(0.0, 7.0, 0.0))
		3, 4:
			_look_camera(Vector3(0.0, 110.0, 175.0), Vector3(0.0, 5.0, 0.0))
		5:
			_look_camera(Vector3(3.4, 2.6, 5.6), Vector3(0.0, 1.3, 0.0))
		6:
			# The finished 4-generation turtle tree is ~15.7 m tall
			# (measured) — frame the whole spire against the sky.
			_look_camera(Vector3(8.0, 7.0, 14.0), Vector3(0.0, 6.5, 0.0))
		7:
			_look_camera(Vector3(0.3, 2.4, 7.2), Vector3(0.3, 1.6, 0.0))
		8:
			stage_camera.fov = 50.0
			_look_camera(Vector3(-2.0, 3.4, 10.5), Vector3(-2.0, 2.0, 0.0))
		9, 10:
			if data != null:
				_look_camera(Vector3(0.0, data.height_at(0.0, 36.0) + 1.15, 36.0),
					Vector3(0.0, data.height_at(0.0, 6.0) + 0.55, 6.0))
			else:
				_look_camera(Vector3(0.0, 12.0, 36.0), Vector3(0.0, 10.0, 6.0))
		11, 12:
			# One shared framing for the summer/autumn pair (the
			# Ch19 shot list requires the same camera for both).
			_look_camera(Vector3(0.0, 30.0, 70.0), Vector3(0.0, 6.0, -10.0))
		_:
			_look_camera(Vector3(0.0, 58.0, 98.0), Vector3(0.0, 7.0, 0.0))
	if not Engine.is_editor_hint():
		stage_camera.current = true

func _look_camera(pos: Vector3, target: Vector3) -> void:
	stage_camera.position = pos
	if stage_camera.is_inside_tree():
		stage_camera.look_at(target, Vector3.UP)
	else:
		stage_camera.look_at_from_position(pos, target, Vector3.UP)

# --- Editor arrangement for ENGINE captures ---
# tools/capture_engine2.sh writes a directive file before launching
# the editor; after the shared book_stage plugin has done its own
# arrangement (step=2, root selected), this applies the shot's real
# step / selection and writes the arranged file the wrapper polls
# for. select: root | Turtle2D | Turtle3D | World | Lab3D.
# Turtle2D additionally shows the Fern (the Ch16 shot list's
# Inspector values: angle 22, segment 4.0) and uses the 2D screen.

func _arrange_from_directive() -> void:
	await get_tree().create_timer(6.0).timeout
	# Prefer this part's PRIVATE directive: the shared directive
	# file is rewritten by every worker's capture wrapper, and
	# foreign steps kept landing in this stage's shots during the
	# busy capture window (Part IV's dungeon stage hit the same
	# failure and adopted the same pattern).
	var use_private: bool = FileAccess.file_exists(P3_DIRECTIVE_PATH)
	var path: String = P3_DIRECTIVE_PATH if use_private else DIRECTIVE_PATH
	var txt: String = FileAccess.get_file_as_string(path)
	var want_step: int = step
	var want_select: String = ""
	for line in txt.split("\n"):
		if line.begins_with("step="):
			want_step = int(line.trim_prefix("step="))
		elif line.begins_with("select="):
			want_select = line.trim_prefix("select=")
	step = want_step  # setter rebuilds at the requested step
	if want_select == "Turtle2D":
		_show_species(2)  # Fern: angle 22 / length 4.0 per the shot list
	_own_generated()
	var node: Node = self
	if want_select != "" and want_select != "root":
		var found: Node = find_child(want_select, true, false)
		if found != null:
			node = found
	if want_select == "Turtle2D":
		EditorInterface.set_main_screen_editor("2D")
	else:
		EditorInterface.set_main_screen_editor("3D")
		_frame_editor_camera()
	_expand_scene_tree()
	# Selection goes LAST and twice: expanding the tree / switching
	# screens can drop it back to the root (terrain stage's lesson).
	_select_in_editor(node)
	# The Ch16/Ch17/Ch19 captions read receipt lines from the
	# Output panel; expand it, then rebuild once more so fresh
	# receipts land in the now-visible log, auto-scrolled to them
	# (Part IV's dungeon-stage technique).
	if step in [3, 6, 12]:
		await _expand_output_panel()
		_built_key = ""
		rebuild()
		if want_select == "Turtle2D":
			_show_species(2)
		_select_in_editor(node)
	# The re-print rebuild recreated the generated nodes without
	# owners; the Scene dock only displays owned nodes, so own
	# them again before shaping (an unowned World shows no
	# children in the dock at all).
	_own_generated()
	# Shape the dock AFTER the final rebuild: clearing a holder
	# in place drops its expansion state, so shaping earlier
	# leaves World collapsed in the frame.
	if step == 12:
		_shape_tree_for_hillside()
		_select_in_editor(node)
	if step == 6:
		_shape_tree_for_lab("Lab3D")
		_select_in_editor(node)
	# Settle briefly before signalling "arranged": under load the
	# editor may not have presented the arranged frame yet, and
	# the X11 grab would catch the boot splash or a stale window.
	await get_tree().create_timer(2.0).timeout
	if want_select != "Turtle2D":
		_frame_editor_camera()
	_select_in_editor(node)
	if use_private:
		var pf: FileAccess = FileAccess.open(P3_ARRANGED_PATH, FileAccess.WRITE)
		if pf != null:
			pf.store_string("plants arranged step=%d select=%s\n" % [step, want_select])
			pf.close()
	else:
		var f: FileAccess = FileAccess.open(ARRANGED_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string("arranged step=%d select=%s\n" % [step, want_select])
			f.close()
	print("BOOK_STAGE_ARRANGED step=", step, " select=", want_select)

func _select_in_editor(node: Node) -> void:
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)

func _frame_editor_camera() -> void:
	# The editor's 3D camera opens wherever the last session left
	# it (usually inside the island); frame the stage like the
	# render preset for this step. The spatial editor's camera is
	# a real Camera3D in its viewport (terrain stage's approach).
	var vp: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var pos: Vector3 = Vector3(0.0, 85.0, 150.0)
	var target: Vector3 = Vector3(0.0, 5.0, 0.0)
	match step:
		6:
			pos = Vector3(9.0, 7.0, 16.0)
			target = Vector3(0.0, 6.0, 0.0)
		12:
			pos = Vector3(0.0, 42.0, 105.0)
			target = Vector3(0.0, 5.0, -5.0)
	var t: Transform3D = Transform3D.IDENTITY.translated(pos)
	t = t.looking_at(target, Vector3.UP)
	cam.global_transform = t

func _expand_output_panel() -> void:
	# Godot 4.7's bottom panel tabs are drawn and hit-tested by
	# the internal EditorBottomPanel control itself — a full
	# control-tree dump contains no "Output" Button to press.
	# The faithful equivalent of the reader's click on the Output
	# tab is a simulated click pushed through the editor window's
	# viewport at the tab's position (first tab in the bottom
	# strip of the 1920x1080 editor window). Technique adopted
	# from Part IV's dungeon stage, which hit the same wall.
	# The panel's starting state is NOT predictable here: the
	# editor layout is per-project and shared by every stage's
	# capture sessions, so the toggle is made state-aware — the
	# 3D viewport's height is measured around the click, and a
	# click that grew it (closing an open panel) is followed by
	# a second click that reopens it.
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var vp: Viewport = base.get_viewport()
	var pos := Vector2(320, 1056)
	var view3d: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var h0: float = view3d.size.y if view3d != null else 0.0
	_click_bottom_output_tab(vp, pos)
	await get_tree().create_timer(0.4).timeout
	if view3d != null and view3d.size.y > h0 - 10.0:
		_click_bottom_output_tab(vp, pos)
		await get_tree().create_timer(0.4).timeout

func _click_bottom_output_tab(vp: Viewport, pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev)

func _shape_tree_for_hillside() -> void:
	# Step 12's caption reads the World container's children in
	# the dock: collapse the two labs so World and the first of
	# its holders fit the dock's height, and scroll World up.
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var trees: Array[Tree] = []
	_collect_trees(base, trees)
	for t in trees:
		var root_item: TreeItem = t.get_root()
		if root_item == null or root_item.get_text(0) != name:
			continue
		var child: TreeItem = root_item.get_first_child()
		while child != null:
			match child.get_text(0):
				"Lab2D", "Lab3D":
					child.set_collapsed(true)
				"World":
					child.set_collapsed(false)
					if t.has_method("scroll_to_item"):
						t.scroll_to_item(child, false)
			child = child.get_next()

func _shape_tree_for_lab(lab_name: String) -> void:
	# Step 6's caption reads Lab3D's children in the dock
	# (Turtle3D, SkinnedPlant, the leaf holder): collapse the
	# other containers so the lab's rows fit the dock's height,
	# and scroll the lab up.
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var trees: Array[Tree] = []
	_collect_trees(base, trees)
	for t in trees:
		var root_item: TreeItem = t.get_root()
		if root_item == null or root_item.get_text(0) != name:
			continue
		var child: TreeItem = root_item.get_first_child()
		while child != null:
			if child.get_text(0) == lab_name:
				child.set_collapsed(false)
				if t.has_method("scroll_to_item"):
					# Scroll to the lab's LAST child: the whole
					# lab then fits between its header and the
					# dock's bottom edge (the leaf holder is
					# created last and sits at the fold).
					var last: TreeItem = child
					var sub: TreeItem = child.get_first_child()
					while sub != null:
						last = sub
						sub = sub.get_next()
					t.scroll_to_item(last, false)
			elif child.get_text(0) in ["Lab2D", "Lab3D", "World"]:
				child.set_collapsed(true)
			child = child.get_next()

func _own_generated() -> void:
	# Generated children get the edited scene as owner in the editor
	# ONLY (so the Scene dock shows them in ENGINE shots); runtime
	# builds never set owner, per the project rule that generated
	# nodes are never baked into the .tscn on save.
	var edited_root: Node = get_tree().edited_scene_root
	if edited_root == null or edited_root != self:
		return
	_own_recursive(self, edited_root)

func _own_recursive(node: Node, edited_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = edited_root
		_own_recursive(child, edited_root)

func _expand_scene_tree() -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var trees: Array[Tree] = []
	_collect_trees(base, trees)
	for t in trees:
		var root_item: TreeItem = t.get_root()
		if root_item != null and root_item.get_text(0) == name:
			_expand_item(root_item)

func _collect_trees(node: Node, out: Array[Tree]) -> void:
	if node is Tree:
		out.append(node as Tree)
	for child in node.get_children():
		_collect_trees(child, out)

func _expand_item(item: TreeItem) -> void:
	item.set_collapsed(false)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_expand_item(child)
		child = child.get_next()
