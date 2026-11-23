class_name HeightField
extends RefCounted
## The book's fundamental terrain DATA class. No nodes, no scene
## tree: just a flat grid of heights (row-major, index = z*size + x,
## exactly as §4.1 taught), a size, and a cell size in metres.
## Generators produce these; builders consume them; neither knows
## the other exists. That separation is the pipeline contract.
## (Chapter 4, Listing 4.2.)

var size: int = 0  # sample points per side (size x size points)
var cell_size: float = 1.0  # metres between neighbouring points
var heights: PackedFloat32Array = PackedFloat32Array()


func _init(p_size: int, p_cell_size: float) -> void:
	size = p_size
	cell_size = p_cell_size
	heights.resize(size * size)


func index_of(x: int, z: int) -> int:
	return z * size + x


func get_point(x: int, z: int) -> float:
	return heights[index_of(x, z)]


func set_point(x: int, z: int, value: float) -> void:
	heights[index_of(x, z)] = value


## Metres spanned by the field. size - 1, because 65 points have
## only 64 gaps between them. This off-by-one has bitten every
## terrain programmer alive; it lives here so it bites exactly once.
func world_extent() -> float:
	return float(size - 1) * cell_size
