extends Control
## Grid playground: a flat row-major array pretending to be 2D.
## index = z * width + x. Learn it here; use it forever.

const COLS: int = 16
const ROWS: int = 12
const CELL: int = 40
const ORIGIN := Vector2(16, 16)

var cells: Array[int] = []
var hover_cell: Vector2i = Vector2i(-1, -1)

@onready var moore_toggle: CheckBox = $MooreToggle
@onready var cell_label: Label = $CellLabel


func _ready() -> void:
	cells.resize(COLS * ROWS)
	cells.fill(0)
	# A deliberately ASYMMETRIC wall pattern (an L), sprinkled from
	# the dungeon stream: if x/z ever get swapped, the L transposes
	# and you see the bug immediately.
	var wall_cells: Array[Vector2i] = [
		Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6),
		Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6),
		Vector2i(11, 2), Vector2i(11, 3), Vector2i(12, 3),
	]
	for c in wall_cells:
		cells[index_of(c.x, c.y)] = 1
	queue_redraw()


## THE formula. Everything grid-shaped in this book uses it.
func index_of(x: int, z: int) -> int:
	return z * COLS + x


## The inverse: index -> (column, row).
func cell_of(index: int) -> Vector2i:
	return Vector2i(index % COLS, index / COLS)


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < COLS and z >= 0 and z < ROWS


## Von Neumann neighbourhood: the 4 orthogonal neighbours.
func neighbours_4(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + dir
		if in_bounds(n.x, n.y):
			result.append(n)
	return result


## Moore neighbourhood: all 8 surrounding cells.
func neighbours_8(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var n := Vector2i(cell.x + dx, cell.y + dz)
			if in_bounds(n.x, n.y):
				result.append(n)
	return result


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local: Vector2 = (event as InputEventMouseMotion).position - ORIGIN
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		hover_cell = cell if in_bounds(cell.x, cell.y) else Vector2i(-1, -1)
		if hover_cell.x >= 0:
			cell_label.text = "cell (%d, %d) · index %d" % [hover_cell.x, hover_cell.y, index_of(hover_cell.x, hover_cell.y)]
		else:
			cell_label.text = "outside the grid"
		queue_redraw()


func _draw() -> void:
	for z in ROWS:
		for x in COLS:
			var rect := Rect2(ORIGIN + Vector2(x * CELL, z * CELL), Vector2(CELL - 2, CELL - 2))
			var col: Color = Color(0.16, 0.17, 0.2) if cells[index_of(x, z)] == 0 else Color(0.55, 0.3, 0.25)
			draw_rect(rect, col)
	if hover_cell.x >= 0:
		var neighbours: Array[Vector2i] = neighbours_8(hover_cell) if moore_toggle.button_pressed else neighbours_4(hover_cell)
		for n in neighbours:
			var rect := Rect2(ORIGIN + Vector2(n.x * CELL, n.y * CELL), Vector2(CELL - 2, CELL - 2))
			draw_rect(rect, Color(0.9, 0.8, 0.25))
		var rect := Rect2(ORIGIN + Vector2(hover_cell.x * CELL, hover_cell.y * CELL), Vector2(CELL - 2, CELL - 2))
		draw_rect(rect, Color.WHITE, false, 2.0)
