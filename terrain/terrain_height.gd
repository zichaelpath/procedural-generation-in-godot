class_name TerrainHeight
extends RefCounted

## Pure-data terrain: aligned grids for height, moisture, temperature
## and biome ID. One index function for every grid, so any two grids
## can be combined point for point without resampling.
##
## Assembled across Part I + Part II:
##   Ch5  base grids + climate pipeline (generate_heights REPLACED by Ch10)
##   Ch6  rule labels (cell_roll / build_rule_labels / compare_classifiers)
##   Ch7  carve_rivers (flow param untyped: FlowField is Part I's file;
##        the calls on it are dynamic so this file compiles standalone)
##   Ch8  load_grid / refresh_climate
##   Ch9  continuous query layer (height_at REPLACED by Ch13 dispatch)
##   Ch10 falloff pass, domain warp, noise variants (generate_heights)
##   Ch11 hydraulic + thermal erosion (called from generate())
##   Ch12 scatter-density grid (the terrain's output contract)
##   Ch13 noise-backed endless mode + detail_at()
##
## NOTE (project integration): the project's core/world_config.gd does
## not yet carry Listing 5.1's terrain_* fields, so generate() reads
## them through _cfg() with the chapter defaults as fallback.

var cells: int = 128
var world_size: float = 400.0
var height_scale: float = 30.0
var sea_level: float = 5.0

var heights: PackedFloat32Array = PackedFloat32Array()
var moisture: PackedFloat32Array = PackedFloat32Array()
var temperature: PackedFloat32Array = PackedFloat32Array()
var biomes: PackedByteArray = PackedByteArray()
var rule_labels: PackedStringArray = PackedStringArray()

var _master_seed: int = 20261119

# --- Chapter 10: falloff + warp + variants ---
# Falloff: composition over chaos. 0 = none, 1 = radial island, 2 = continent.
var falloff_mode: int = 1
var falloff_curve: Curve
# Warp strength in world metres: how far a sample point may be displaced.
var warp_strength: float = 35.0
# 0 = FBM hills, 1 = ridged crests, 2 = billow swells, 3 = red-noise continent.
var variant: int = 0

# --- Chapter 11: erosion ---
var erode_droplets: int = 30000
var erode_min_height: float = 3.0  # droplets never touch the coast band
# Capacity/speed factor (Listing 11.1 hardcodes 4.0). TUNED per the
# chapter's own Exercise 1 ("tune the capacity constant until clear
# valleys carve"): at this project's scale a one-cell step drops
# 0.3-3.0 m, and the listing's 4.0 makes capacity explode — droplets
# dig to the -2 floor in one step and deposit the load as spikes.
# 0.15 keeps per-step erosion in centimetres, where channels carve
# (0.22 and 0.30 were tested too: deposition loads spike into cones).
var erode_capacity: float = 0.15
var thermal_iterations: int = 40
var thermal_talus: float = 0.9  # max allowed height difference per cell step
var erosion_preview: bool = false
var thermal_preview: bool = false

# --- Chapter 12: scatter density (output contract) ---
var scatter_density: PackedFloat32Array = PackedFloat32Array()

# How much plant life each biome wants. Data, not logic — Part III's
# scatter system samples this grid and never asks why a cell is lush.
const BIOME_DENSITY := {
	0: 0.0,   # ocean
	1: 0.02,  # beach
	2: 0.05,  # desert
	3: 0.35,  # grassland
	4: 0.85,  # forest
	5: 1.0,   # rainforest
	6: 0.6,   # taiga
	7: 0.08,  # tundra
	8: 0.0,   # rock
	9: 0.0,   # snow
}

# --- Chapter 13: noise-backed (endless) mode ---
var noise_backed: bool = false
var _height_noise: FastNoiseLite
var _warp_noise: FastNoiseLite
var _detail_noise: FastNoiseLite


func row_width() -> int:
	return cells + 1  # fence posts, not panels: 128 cells = 129 points

func index(ix: int, iz: int) -> int:
	return iz * row_width() + ix

func cell_size() -> float:
	return world_size / float(cells)

# Grid point -> world position. The grid is centred on the origin.
func grid_to_world(ix: int, iz: int) -> Vector2:
	var step: float = cell_size()
	return Vector2(-world_size * 0.5 + float(ix) * step,
			-world_size * 0.5 + float(iz) * step)

func grid_height(ix: int, iz: int) -> float:
	return heights[index(ix, iz)]

func moisture_at(ix: int, iz: int) -> float:
	return moisture[index(ix, iz)]

func temperature_at(ix: int, iz: int) -> float:
	return temperature[index(ix, iz)]

func biome_at(ix: int, iz: int) -> int:
	return biomes[index(ix, iz)]

# Reads a WorldConfig field that may not exist yet in the project's
# config (Listing 5.1 fields), falling back to the chapter default.
func _cfg(config: WorldConfig, field: String, fallback: Variant) -> Variant:
	var v: Variant = config.get(field)
	return fallback if v == null else v

func generate(config: WorldConfig) -> void:
	_master_seed = config.master_seed
	cells = int(_cfg(config, "terrain_cells", 128))
	world_size = float(_cfg(config, "terrain_world_size", 400.0))
	height_scale = float(_cfg(config, "terrain_height_scale", 30.0))
	sea_level = float(_cfg(config, "sea_level", 5.0))
	generate_heights(config)
	# Chapter 11: erosion sits after shape, before judgement. The stage
	# gates the passes per step via erode_droplets / thermal_iterations
	# (0 = the pass runs zero work), so steps 0-4 stay un-eroded.
	erode_hydraulic(config, erosion_preview)
	erode_thermal(thermal_preview)
	generate_moisture(config)
	generate_temperature()
	classify_all()
	build_rule_labels()
	compute_scatter_density()

# --- Chapter 10, Listing 10.2: generate_heights REPLACED in full ---
# Warped sampling + variant branch + falloff as a separate pass.
func generate_heights(config: WorldConfig) -> void:
	heights.resize(row_width() * row_width())
	var noise: FastNoiseLite = SeedBank.noise_for(
			config.master_seed, "terrain", 0.008, 5)
	# The warp field: same stream family, lower frequency so the
	# displacement itself is smooth and coherent.
	var warp: FastNoiseLite = SeedBank.noise_for(
			config.master_seed, "terrain", 0.004, 2)
	var low: FastNoiseLite = SeedBank.noise_for(
			config.master_seed, "terrain", 0.002, 2)
	var single: FastNoiseLite = SeedBank.noise_for(
			config.master_seed, "terrain", 0.008, 1)
	for iz in range(row_width()):
		for ix in range(row_width()):
			var wp: Vector2 = grid_to_world(ix, iz)
			# STAGE ONE — sample the offset field at a DECORRELATED
			# position: (x + 5.2, z + 1.3), never at the point itself.
			# The second channel is the same field +1000 away — a
			# different separation, for a different joint (see text).
			var ox: float = warp.get_noise_2d(wp.x + 5.2, wp.y + 1.3) * warp_strength
			var oz: float = warp.get_noise_2d(wp.x + 5.2 + 1000.0, wp.y + 1.3 + 1000.0) * warp_strength
			# STAGE TWO — displace the sample point by the offset, then
			# re-sample: the height here is the height from over there,
			# chosen by a field that does not know it.
			var sx: float = wp.x + ox
			var sz: float = wp.y + oz
			var n: float = noise.get_noise_2d(sx, sz)
			var h: float
			if variant == 1 or variant == 2:
				h = sample_shaped(single, sx, sz) * height_scale
			else:
				var low_n: float = low.get_noise_2d(sx, sz)
				h = shape_height(n, low_n) * height_scale
			heights[index(ix, iz)] = h
	apply_falloff(config)

# --- Chapter 10, Listing 10.1: falloff ---
func build_falloff_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))    # interior: full height
	c.add_point(Vector2(0.55, 1.0))   # stay proud past halfway out
	c.add_point(Vector2(0.85, 0.35))  # commit to the descent
	c.add_point(Vector2(1.0, 0.0))    # rim: guaranteed below sea level
	return c

func apply_falloff(config: WorldConfig) -> void:
	if falloff_mode == 0:
		return
	if falloff_curve == null:
		falloff_curve = build_falloff_curve()
	# Continent mode wobbles the distance field with low-frequency noise.
	var edge_noise: FastNoiseLite = null
	if falloff_mode == 2:
		edge_noise = SeedBank.noise_for(config.master_seed, "terrain", 0.006, 2)
	var half: float = world_size * 0.5
	for iz in range(row_width()):
		for ix in range(row_width()):
			var wp: Vector2 = grid_to_world(ix, iz)
			var d: float = clampf(wp.length() / (half * 1.42), 0.0, 1.0)
			if edge_noise != null:
				d += edge_noise.get_noise_2d(wp.x, wp.y) * 0.12
				d = clampf(d, 0.0, 1.0)
			var mask: float = falloff_curve.sample(d)
			var i: int = index(ix, iz)
			# Multiply, then pull the rim under the sea so the coast is a
			# promise: mask 0 -> height -2 (underwater), not height 0.
			heights[i] = lerpf(-2.0, heights[i], mask)

# --- Chapter 10, Listing 10.3: variants, shaped per octave ---
# The transform IS the geology. Raw noise in (-1..1), shaped value out (0..1).
func shape_height(n: float, low: float) -> float:
	match variant:
		1:  # ridged: fold at zero, flip, sharpen -> continuous crests
			var r: float = 1.0 - absf(n)
			return r * r
		2:  # billow: fold only -> rounded domes and dunes
			return absf(n)
		3:  # red noise: the big slow wave dominates, detail rides on top
			return clampf((low * 0.5 + 0.5) * 0.75 + (n * 0.5 + 0.5) * 0.25, 0.0, 1.0)
		_:  # standard FBM
			return n * 0.5 + 0.5

# One octave in (-1..1) -> shaped term in (0..1), per the variant.
func shape_term(n: float) -> float:
	match variant:
		1:  # ridged, per octave: fold, flip, sharpen — at every scale
			var r: float = 1.0 - absf(n)
			return r * r
		2:  # billow, per octave: fold only
			return absf(n)
		_:
			return n * 0.5 + 0.5

# Manual FBM: 5 octaves, frequency doubles, amplitude halves, and the
# shaping happens INSIDE the loop — that placement is the whole point.
func sample_shaped(single: FastNoiseLite, x: float, z: float) -> float:
	var sum: float = 0.0
	var norm: float = 0.0
	var amp: float = 1.0
	var freq_mul: float = 1.0
	for octave in range(5):
		single.frequency = 0.008 * freq_mul
		var n: float = single.get_noise_2d(x, z)
		sum += amp * shape_term(n)
		norm += amp
		amp *= 0.5
		freq_mul *= 2.0
	return sum / norm

# --- Chapter 5: climate pipeline ---
func generate_moisture(config: WorldConfig) -> void:
	moisture.resize(row_width() * row_width())
	# Own stream, own character: moisture swells more slowly than height.
	var m_noise: FastNoiseLite = SeedBank.noise_for(
			config.master_seed, "terrain_moisture", 0.005, 4)
	for iz in range(row_width()):
		for ix in range(row_width()):
			var wp: Vector2 = grid_to_world(ix, iz)
			var m: float = m_noise.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			var h: float = grid_height(ix, iz)
			# Cause 1: water is wet — coasts and floodplains hold moisture.
			if h < sea_level + 2.0:
				m += 0.25
			# Cause 2: altitude dries — the higher, the less it holds.
			m -= (h / height_scale) * 0.2
			moisture[index(ix, iz)] = clampf(m, 0.0, 1.0)

func generate_temperature() -> void:
	temperature.resize(row_width() * row_width())
	for iz in range(row_width()):
		for ix in range(row_width()):
			var wp: Vector2 = grid_to_world(ix, iz)
			# Latitude: warm at the world's middle band, cold at the edges.
			var lat: float = 1.0 - clampf(absf(wp.y) / (world_size * 0.5), 0.0, 1.0)
			# Lapse: temperature falls as height rises — why tropical
			# mountains can still wear snow.
			var lapse: float = (grid_height(ix, iz) / height_scale) * 0.35
			temperature[index(ix, iz)] = clampf(0.25 + lat * 0.65 - lapse, 0.0, 1.0)

func classify_all() -> void:
	biomes.resize(row_width() * row_width())
	for iz in range(row_width()):
		for ix in range(row_width()):
			var i: int = index(ix, iz)
			biomes[i] = BiomeClassifier.classify(
					heights[i], moisture[i], temperature[i],
					sea_level, height_scale)

# --- Chapter 6, Listing 6.2: rule labels ---
# A per-cell roll in 0..1 from a position hash: deterministic per cell,
# independent of visit order, no RNG state to keep in step.
func cell_roll(ix: int, iz: int) -> float:
	var key: String = str(master_seed_key()) + ":" + str(ix) + ":" + str(iz) + ":rule_biome"
	return float(absi(hash(key)) % 1000) / 1000.0

func master_seed_key() -> int:
	return _master_seed

func build_rule_labels() -> void:
	rule_labels.resize(row_width() * row_width())
	for iz in range(row_width()):
		for ix in range(row_width()):
			var i: int = index(ix, iz)
			rule_labels[i] = BiomeClassifier.classify_rule_table(
					heights[i], moisture[i], temperature[i],
					sea_level, height_scale, cell_roll(ix, iz))

# The same cell through BOTH classifiers, side by side.
func compare_classifiers(ix: int, iz: int) -> Dictionary:
	var i: int = index(ix, iz)
	return {
		"whittaker_id": biome_at(ix, iz),
		"rule_label": rule_labels[i],
		"roll": cell_roll(ix, iz),
	}

# --- Chapter 7, Listing 7.4: river carving ---
# Seats the largest rivers in shallow channels. Invented terrain only:
# measured landscapes (Chapter 8) arrive already carved by real water.
# (flow is Part I's FlowField; called dynamically — see header note.)
func carve_rivers(flow: RefCounted, threshold: float, max_depth: float) -> void:
	var log_lo: float = log(threshold)
	var log_hi: float = log(10000.0)
	var accumulation: PackedFloat32Array = flow.get("accumulation")
	for i in range(heights.size()):
		if heights[i] < sea_level:
			continue
		if not bool(flow.call("is_river", i, threshold)):
			continue
		var w: float = clampf((log(accumulation[i]) - log_lo) / (log_hi - log_lo), 0.0, 1.0)
		heights[i] -= lerpf(0.3, max_depth, w)
	# Carving changed heights, so every height-derived answer is stale.
	generate_temperature()
	classify_all()
	build_rule_labels()
	compute_scatter_density()  # Chapter 12: carved ground re-publishes density

# --- Chapter 8, Listing 8.2: imported grids ---
# Swaps this terrain's heights for an imported grid, sampled at this
# grid's world positions, then re-runs the whole climate pipeline.
# Everything downstream is unchanged — that is the point.
func load_grid(source: PackedFloat32Array, source_points: int,
		source_world_size: float, source_height_scale: float) -> void:
	world_size = source_world_size
	height_scale = source_height_scale
	heights.resize(row_width() * row_width())
	for iz in range(row_width()):
		for ix in range(row_width()):
			var wp: Vector2 = grid_to_world(ix, iz)
			heights[index(ix, iz)] = _sample_source(
					source, source_points, source_world_size, wp)
	refresh_climate()

func _sample_source(source: PackedFloat32Array, points: int,
		source_world_size: float, wp: Vector2) -> float:
	# World position -> fractional source-grid position.
	var fx: float = (wp.x + source_world_size * 0.5) / source_world_size * float(points - 1)
	var fz: float = (wp.y + source_world_size * 0.5) / source_world_size * float(points - 1)
	var x0: int = clampi(int(floor(fx)), 0, points - 2)
	var z0: int = clampi(int(floor(fz)), 0, points - 2)
	var tx: float = clampf(fx - float(x0), 0.0, 1.0)
	var tz: float = clampf(fz - float(z0), 0.0, 1.0)
	var stride: int = points
	var h00: float = source[z0 * stride + x0]
	var h10: float = source[z0 * stride + x0 + 1]
	var h01: float = source[(z0 + 1) * stride + x0]
	var h11: float = source[(z0 + 1) * stride + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

# Re-derives every height-dependent field. Used after load_grid() and
# by any future pass that replaces heights wholesale.
func refresh_climate() -> void:
	# Moisture needs a config for its stream; rebuild a minimal one from
	# the stored seed so refresh stays callable from anywhere.
	var config := WorldConfig.new()
	config.master_seed = _master_seed
	generate_moisture(config)
	generate_temperature()
	classify_all()
	build_rule_labels()
	compute_scatter_density()

# --- Chapter 9, Listing 9.1: the continuous query layer ---
# Grid accessors answer at fence posts; these answer anywhere.
# (height_at itself is the Chapter 13 dispatch version, below.)

func world_to_grid_f(world_x: float, world_z: float) -> Vector2:
	var step: float = cell_size()
	return Vector2((world_x + world_size * 0.5) / step,
			(world_z + world_size * 0.5) / step)

# The data-side normal: finite differences on the height grid.
# Systems that make DECISIONS (plants, roads, cities) ask this —
# they never read normals off the rendered mesh.
func get_normal(ix: int, iz: int) -> Vector3:
	var step: float = cell_size()
	var cx: int = clampi(ix, 1, cells - 1)
	var cz: int = clampi(iz, 1, cells - 1)
	var dx: float = (grid_height(cx + 1, cz) - grid_height(cx - 1, cz)) / (2.0 * step)
	var dz: float = (grid_height(cx, cz + 1) - grid_height(cx, cz - 1)) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()

func slope_at(x: float, z: float) -> float:
	# 0 = flat, approaching 1 = vertical. From the data normal.
	if noise_backed:
		# No grid exists in endless mode: finite differences on the
		# continuous field itself (same idea, one level up).
		var e: float = 2.0
		var dx: float = (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
		var dz: float = (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
		return 1.0 - Vector3(-dx, 1.0, -dz).normalized().y
	var g: Vector2 = world_to_grid_f(x, z)
	var n: Vector3 = get_normal(clampi(int(g.x), 0, cells),
			clampi(int(g.y), 0, cells))
	return 1.0 - n.y

func biome_at_world(x: float, z: float) -> int:
	if noise_backed or biomes.is_empty():
		return BiomeClassifier.GRASSLAND
	var g: Vector2 = world_to_grid_f(x, z)
	return biome_at(clampi(int(g.x), 0, cells), clampi(int(g.y), 0, cells))

# --- Chapter 13, Listing 13.2: noise-backed mode + height_at dispatch ---

func use_noise_field(cfg: WorldConfig) -> void:
	noise_backed = true
	_master_seed = cfg.master_seed
	_height_noise = SeedBank.noise_for(cfg.master_seed, "terrain", 0.0016, 5)
	_warp_noise = SeedBank.noise_for(cfg.master_seed, "terrain", 0.0007, 2)
	_detail_noise = SeedBank.noise_for(cfg.master_seed, "terrain", 0.045, 2)

# REPLACES Chapter 9's height_at(): grid-backed islands dispatch to the
# original bilinear read; noise-backed worlds evaluate the field.
# --- City edits (added in Chapter 43) -----------------------------------
# Part VIII's named seam (§38.2): civilisation edits the heightfield.
# The base field — grid or noise — is NEVER written to. An edit is a
# small record; height_at() applies the records, in registration
# order, after the base query. One function, one truth, two authors
# writing in a fixed order. (Technique family: Gennari's 3DWorld
# civilisation flattening, GPLv3 — idea reimplemented, no code used;
# the edit-list-inside-the-query repair for a function-backed field
# is this book's own.)
#
# Edit records:
#   plot:    {"kind": "plot", "center": Vector2, "half_size": Vector2,
#             "yaw": float, "height": float, "blend": float}
#   segment: {"kind": "segment", "from": Vector2, "to": Vector2,
#             "half_width": float, "height_from": float,
#             "height_to": float, "blend": float}
var _city_edits: Array[Dictionary] = []


func clear_city_edits() -> void:
	_city_edits.clear()


func city_edit_count() -> int:
	return _city_edits.size()


## Flatten one rotated rectangle to a target height: inside the
## rectangle the ground IS the target; across the blend distance (in metres) outside
## its edge the edit fades back to whatever the ground was before
## this edit. Parcels call this with their frame's yaw (Ch 39).
func flatten_plot(center: Vector2, half_size: Vector2, yaw: float, target_height: float, blend: float) -> void:
	_city_edits.append({
		"kind": "plot", "center": center, "half_size": half_size,
		"yaw": yaw, "height": target_height, "blend": blend,
	})


## Terrace one road segment: level across its width, sloping along
## its length from height_from to height_to. The heights are captured
## by the CALLER at registration time (from the pre-edit surface), so
## the record is a surveyed fact, not a live query.
func terrace_road_segment(from_point: Vector2, to_point: Vector2, half_width: float, height_from: float, height_to: float, blend: float) -> void:
	_city_edits.append({
		"kind": "segment", "from": from_point, "to": to_point,
		"half_width": half_width, "height_from": height_from,
		"height_to": height_to, "blend": blend,
	})


## The union of every edit's footprint, grown by its blend — the
## region whose ChunkData any edit may have invalidated.
func city_edit_bounds() -> Rect2:
	var bounds := Rect2()
	var first: bool = true
	for edit: Dictionary in _city_edits:
		var r := Rect2()
		if str(edit["kind"]) == "plot":
			var c: Vector2 = edit["center"]
			var h: Vector2 = edit["half_size"]
			var grow: float = h.length() + float(edit["blend"])
			r = Rect2(c - Vector2(grow, grow), Vector2(grow, grow) * 2.0)
		else:
			var a: Vector2 = edit["from"]
			var b: Vector2 = edit["to"]
			var grow2: float = float(edit["half_width"]) + float(edit["blend"])
			var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(grow2, grow2)
			var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(grow2, grow2)
			r = Rect2(lo, hi - lo)
		if first:
			bounds = r
			first = false
		else:
			bounds = bounds.merge(r)
	return bounds


# REPLACES Chapter 13's height_at() (whose body becomes
# _base_height_at() below, unchanged). Same signature, same contract:
# "the ground's height at this point" — now including the city's
# surveyed edits, because the city is part of the ground's truth.
func height_at(x: float, z: float) -> float:
	var result: float = _base_height_at(x, z)
	if _city_edits.is_empty():
		return result
	var point := Vector2(x, z)
	for edit: Dictionary in _city_edits:
		result = _apply_city_edit(result, point, edit)
	return result


## Chapter 13's height_at(), verbatim, renamed. Grid-backed fields
## dispatch to the bilinear grid read; noise-backed fields evaluate
## the field. Nothing else in the project calls this — judges and
## registration code that need the PRE-EDIT surface call it too,
## deliberately, and say so at the call site.
func _base_height_at(x: float, z: float) -> float:
	if noise_backed:
		return _noise_height(x, z)
	var g: Vector2 = world_to_grid_f(x, z)
	var ix: int = clampi(int(g.x), 0, cells - 1)
	var iz: int = clampi(int(g.y), 0, cells - 1)
	var fx: float = clampf(g.x - float(ix), 0.0, 1.0)
	var fz: float = clampf(g.y - float(iz), 0.0, 1.0)
	var h00: float = grid_height(ix, iz)
	var h10: float = grid_height(ix + 1, iz)
	var h01: float = grid_height(ix, iz + 1)
	var h11: float = grid_height(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func _apply_city_edit(current: float, point: Vector2, edit: Dictionary) -> float:
	var blend: float = maxf(float(edit.get("blend", 8.0)), 0.01)
	if str(edit.get("kind", "")) == "plot":
		var center: Vector2 = edit["center"]
		var half_size: Vector2 = edit["half_size"]
		var yaw: float = float(edit.get("yaw", 0.0))
		# Judge the point in the plot's own rotated frame (Ch 39's
		# frames are rotated by the borough; an axis-aligned test
		# would flatten a diamond and call it a parcel).
		var local: Vector2 = (point - center).rotated(-yaw)
		var outside: Vector2 = local.abs() - half_size
		var dist_outside: float = 0.0
		if outside.x > 0.0 or outside.y > 0.0:
			dist_outside = Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length()
		var weight: float = 1.0 - smoothstep(0.0, blend, dist_outside)
		return lerpf(current, float(edit["height"]), weight)
	if str(edit.get("kind", "")) == "segment":
		var a: Vector2 = edit["from"]
		var b: Vector2 = edit["to"]
		var ab: Vector2 = b - a
		var length_sq: float = ab.length_squared()
		var along: float = 0.0
		if length_sq > 0.0001:
			along = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
		var closest: Vector2 = a + ab * along
		var dist: float = point.distance_to(closest)
		var half_width: float = float(edit["half_width"])
		var weight_seg: float = 1.0 - smoothstep(half_width, half_width + blend, dist)
		var target: float = lerpf(float(edit["height_from"]), float(edit["height_to"]), along)
		return lerpf(current, target, weight_seg)
	return current

func _noise_height(x: float, z: float) -> float:
	# Domain warp (Chapter 10): displace the sample position, then sample.
	var warp_strength: float = 180.0
	var wx: float = x + _warp_noise.get_noise_2d(x + 5000.0, z) * warp_strength
	var wz: float = z + _warp_noise.get_noise_2d(x, z + 5000.0) * warp_strength
	var n: float = _height_noise.get_noise_2d(wx, wz)  # -1..1
	# Ridged lift on the high end (Chapter 10) so mountains get crests.
	var ridged: float = 1.0 - absf(_height_noise.get_noise_2d(wx * 2.3, wz * 2.3))
	var base: float = pow(maxf(n * 0.5 + 0.5, 0.0), 1.6) * 55.0
	var peaks: float = pow(maxf(ridged - 0.72, 0.0) / 0.28, 2.0) * 60.0 * smoothstep(18.0, 45.0, base)
	return base + peaks - 6.0  # -6 puts real coastline below sea level

## Fine surface detail, world-space, shared by every chunk. HOW MUCH of
## it a chunk shows is a chunk-local decision (Section 13.2); the detail
## field itself is global so the window can fade it without a seam.
func detail_at(x: float, z: float) -> float:
	if _detail_noise == null:
		return 0.0
	return _detail_noise.get_noise_2d(x, z) * 0.9  # ~ +/- 0.9 m of bump

# --- Chapter 11, Listing 11.1: hydraulic erosion (droplet method) ---
func _height_and_gradient(x: float, z: float) -> Array:
	# Bilinear height + finite-difference gradient at a CONTINUOUS
	# position (in grid coordinates). Droplets live between grid points.
	var ix: int = clampi(int(x), 0, cells - 1)
	var iz: int = clampi(int(z), 0, cells - 1)
	var fx: float = x - float(ix)
	var fz: float = z - float(iz)
	var h00: float = grid_height(ix, iz)
	var h10: float = grid_height(ix + 1, iz)
	var h01: float = grid_height(ix, iz + 1)
	var h11: float = grid_height(ix + 1, iz + 1)
	var h: float = lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	var gx: float = (h10 - h00) * (1.0 - fz) + (h11 - h01) * fz
	var gz: float = (h01 - h00) * (1.0 - fx) + (h11 - h10) * fx
	return [h, gx, gz]

func erode_hydraulic(config: WorldConfig, preview: bool = false) -> void:
	var droplet_count: int = erode_droplets / 4 if preview else erode_droplets
	var sample_step: float = 2.0 if preview else 1.0
	if droplet_count <= 0:
		return
	# Droplet placement comes from the terrain stream: same seed,
	# same rain, same rivers.
	var rng: RandomNumberGenerator = SeedBank.stream_for(
			config.master_seed, "terrain")
	for drop in range(droplet_count):
		# Position in grid coordinates; velocity and load start empty.
		var pos := Vector2(rng.randf_range(1.0, float(cells - 1)),
				rng.randf_range(1.0, float(cells - 1)))
		var dir := Vector2.ZERO
		var speed: float = 1.0
		var water: float = 1.0
		var sediment: float = 0.0
		for lifetime in range(30):
			var sample: Array = _height_and_gradient(pos.x, pos.y)
			var h: float = sample[0]
			if h < erode_min_height:
				break  # reached the protected coast band / sea
			var grad := Vector2(sample[1], sample[2])
			# Inertia: mostly old direction, partly new downhill.
			dir = (dir * 0.7 + (-grad) * 0.3)
			if dir.length() < 0.0001:
				break  # flat ground: the droplet gives up
			dir = dir.normalized()
			pos += dir * sample_step
			if pos.x < 1.0 or pos.y < 1.0 or pos.x > float(cells - 1) or pos.y > float(cells - 1):
				break
			var new_sample: Array = _height_and_gradient(pos.x, pos.y)
			var new_h: float = new_sample[0]
			var drop_h: float = new_h - h  # negative when we went downhill
			# Capacity: fast + steep + wet carries more.
			var capacity: float = maxf(-drop_h * speed * water * erode_capacity, 0.01)
			if sediment > capacity or drop_h > 0.0:
				# Deposit a fraction of the load (or enough to fill a rise).
				var amount: float = minf(sediment * 0.3, sediment) if drop_h <= 0.0 else minf(drop_h, sediment)
				sediment -= amount
				_apply_bilinear(pos, amount)
			else:
				# Erode a fraction of the shortfall — never all at once.
				var amount2: float = minf((capacity - sediment) * 0.3,
						maxf(-drop_h, 0.001))
				sediment += amount2
				_apply_bilinear(pos, -amount2)
			speed = sqrt(maxf(speed * speed + (-drop_h) * erode_capacity, 0.0))
			water *= 0.99  # evaporation ends every droplet eventually

func _apply_bilinear(pos: Vector2, delta: float) -> void:
	# Spread a height change over the 4 corners of the cell the droplet
	# stands in, weighted by closeness. Without this, droplets dig
	# single-cell trenches and the terrain looks scratched.
	var ix: int = clampi(int(pos.x), 0, cells - 1)
	var iz: int = clampi(int(pos.y), 0, cells - 1)
	var fx: float = pos.x - float(ix)
	var fz: float = pos.y - float(iz)
	_add_height(ix, iz, delta * (1.0 - fx) * (1.0 - fz))
	_add_height(ix + 1, iz, delta * fx * (1.0 - fz))
	_add_height(ix, iz + 1, delta * (1.0 - fx) * fz)
	_add_height(ix + 1, iz + 1, delta * fx * fz)

func _add_height(ix: int, iz: int, delta: float) -> void:
	var i: int = index(ix, iz)
	heights[i] = maxf(heights[i] + delta, -2.0)

# --- Chapter 11, Listing 11.2: thermal erosion ---
func erode_thermal(preview: bool = false) -> void:
	var iterations: int = thermal_iterations / 4 if preview else thermal_iterations
	var cell_step: int = 2 if preview else 1
	var max_diff: float = thermal_talus  # per one-cell step (cell_size metres)
	for it in range(iterations):
		# Work on a delta array so a pass never reads its own writes:
		# decide everything from one snapshot, then apply together.
		var delta := PackedFloat32Array()
		delta.resize(heights.size())
		for iz in range(1, cells, cell_step):
			for ix in range(1, cells, cell_step):
				var i: int = index(ix, iz)
				var h: float = heights[i]
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = index(ix + d.x, iz + d.y)
					var diff: float = h - heights[ni]
					if diff > max_diff:
						# Move a quarter of the EXCESS downhill.
						var move: float = (diff - max_diff) * 0.25
						delta[i] -= move
						delta[ni] += move
		for i in range(heights.size()):
			heights[i] = maxf(heights[i] + delta[i], -2.0)

# --- Chapter 12, Listing 12.3: scatter density ---
func compute_scatter_density() -> void:
	scatter_density.resize(row_width() * row_width())
	for i in range(biomes.size()):
		scatter_density[i] = BIOME_DENSITY.get(biomes[i], 0.1)
