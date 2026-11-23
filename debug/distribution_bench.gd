extends Node3D
## Distribution bench: the same blocks scattered four ways.
## Uniform = no opinion. Bell = ordinary is common.
## Weighted table = the designer's rarity language.
## Halton = even coverage with zero randomness at all.

const BLOCKS_PER_ROW: int = 300
const ROW_LENGTH: float = 36.0
const HALTON_ROW_DEPTH: float = 8.0

const CATEGORY_COLORS: Array[Color] = [
	Color(0.35, 0.75, 0.35),  # 0 common — green
	Color(0.3, 0.55, 0.95),   # 1 uncommon — blue
	Color(0.85, 0.6, 0.2),    # 2 rare — amber
	Color(0.9, 0.3, 0.85),    # 3 epic — magenta
]
const WEIGHTS: Array[int] = [60, 25, 12, 3]

var _block_mesh: BoxMesh

@onready var uniform_row: Node3D = $UniformRow
@onready var bell_row: Node3D = $BellRow
@onready var weighted_row: Node3D = $WeightedRow
@onready var halton_row: Node3D = $HaltonRow
@onready var histogram_label: Label = $CanvasLayer/HistogramLabel


func _ready() -> void:
	_block_mesh = BoxMesh.new()
	_block_mesh.size = Vector3(0.8, 0.8, 0.8)
	var report: Array[String] = []
	report.append(_fill_row(uniform_row, "uniform"))
	report.append(_fill_row(bell_row, "bell"))
	report.append(_fill_row(weighted_row, "weighted"))
	report.append(_fill_row(halton_row, "halton"))
	histogram_label.text = "\n".join(report)


func _fill_row(row_root: Node3D, mode: String) -> String:
	# Each row draws from the SAME stream name but a fresh generator,
	# so the rows stay comparable and reproducible. The halton row
	# creates its stream like the others but never draws from it:
	# its positions come from a sequence, not from randomness.
	var rng := SeedBank.stream_for(20261119, SeedBank.STREAM_SCATTER)
	var counts: Array[int] = [0, 0, 0, 0]
	for i in BLOCKS_PER_ROW:
		var category: int = 0
		match mode:
			"uniform":
				category = rng.randi_range(0, 3)
			"bell":
				# Bell centred on 1.5 across the four categories.
				category = clampi(int(round(rng.randfn(1.5, 0.75))), 0, 3)
			"weighted":
				category = pick_weighted(rng, WEIGHTS)
			"halton":
				# No RNG draw at all: the colour simply cycles, so this
				# row's story is purely about WHERE the points land.
				category = i % CATEGORY_COLORS.size()
		counts[category] += 1
		var block := MeshInstance3D.new()
		block.mesh = _block_mesh
		if mode == "halton":
			# The Halton index starts at 1: index 0 is the corner
			# point (0, 0), which would park one block in the corner.
			var point: Vector2 = halton_point(i + 1)
			block.position = Vector3(
				lerpf(-ROW_LENGTH * 0.5, ROW_LENGTH * 0.5, point.x),
				0.4,
				lerpf(-HALTON_ROW_DEPTH * 0.5, HALTON_ROW_DEPTH * 0.5, point.y))
		else:
			var t: float = float(i) / float(BLOCKS_PER_ROW - 1)
			block.position = Vector3(lerpf(-ROW_LENGTH * 0.5, ROW_LENGTH * 0.5, t), 0.4, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CATEGORY_COLORS[category]
		block.material_override = mat
		row_root.add_child(block)
	var pcts: Array[String] = []
	for c in counts:
		pcts.append("%.1f%%" % (100.0 * float(c) / float(BLOCKS_PER_ROW)))
	return "%s: %s" % [mode, " / ".join(pcts)]


## The book's weighted pick. Weights are relative; the roll is a
## dart thrown at a ruler divided into segments sized by weight.
static func pick_weighted(rng: RandomNumberGenerator, weights: Array[int]) -> int:
	var total: int = 0
	for w in weights:
		total += w
	var roll: int = rng.randi_range(0, total - 1)
	var running: int = 0
	for i in weights.size():
		running += weights[i]
		if roll < running:
			return i
	return weights.size() - 1


## One Halton point in the unit square: base 2 for x, base 3 for z.
## Two different bases keep the points from lining up on a grid, and
## the sequence fills the square evenly with zero randomness — every
## new point lands in one of the biggest remaining gaps.
static func halton_point(index: int) -> Vector2:
	return Vector2(radical_inverse(index, 2), radical_inverse(index, 3))


## The radical inverse: write `index` in `base`, reverse its digits
## after the point, and read the result back as a fraction in 0..1.
## Example in base 2: 6 is 110, reversed after the point it is 0.011,
## which is 0.375. Deterministic — no RNG is involved anywhere.
static func radical_inverse(index: int, base: int) -> float:
	var result: float = 0.0
	var place: float = 1.0 / float(base)
	var remaining: int = index
	while remaining > 0:
		result += place * float(remaining % base)
		remaining = remaining / base
		place /= float(base)
	return result
