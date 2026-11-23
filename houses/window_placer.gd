class_name WindowPlacer
extends RefCounted
## Daylight as data. Windows are computed ONCE, on the finished plan,
## before anything is built, and every later stage treats the list as
## fixed input: the builder cuts exactly these holes, the furnisher
## knows where the glass is, and no later wall split may cross a
## window's centre (see nudge_split_clear_of_windows).

const GLAZING_FRACTION: float = 0.10 # window area >= ~10% of floor area
const SILL: float = 0.85
const HEADER: float = 2.25
const WET_SILL: float = 1.6
const WET_WIDTH: float = 0.6
const CORNER_MARGIN: float = 0.6

static func place_windows(plan: Dictionary) -> Array:
	var windows: Array = []
	var footprint: Rect2 = plan["footprint"]
	for room in plan["rooms"]:
		if room["type"] == "hall":
			continue # halls borrow light through doorways
		var rect: Rect2 = room["rect"]
		var walls: Array = _exterior_walls(rect, footprint)
		if walls.is_empty():
			continue
		var is_wet: bool = room["type"] == "bathroom" or room["type"] == "wc"
		if is_wet:
			var wall: String = walls[0]
			windows.append(_make_window(room["name"], wall, rect, WET_WIDTH, WET_SILL, 2.2))
			continue
		var width: float = clampf(rect.get_area() * GLAZING_FRACTION / (HEADER - SILL), 0.9, 2.4)
		windows.append(_make_window(room["name"], walls[0], rect, width, SILL, HEADER))
		if walls.size() > 1:
			# Corner room: a second window on the other exterior wall,
			# at 0.7x width. The cheapest luxury in housing.
			windows.append(_make_window(room["name"], walls[1], rect, width * 0.7, SILL, HEADER))
	plan["windows"] = windows
	return windows

static func _exterior_walls(rect: Rect2, footprint: Rect2) -> Array:
	var walls: Array = []
	if absf(rect.position.y - footprint.position.y) < 0.02:
		walls.append("N")
	if absf(rect.end.y - footprint.end.y) < 0.02:
		walls.append("S")
	if absf(rect.position.x - footprint.position.x) < 0.02:
		walls.append("W")
	if absf(rect.end.x - footprint.end.x) < 0.02:
		walls.append("E")
	return walls

static func _make_window(room_name: String, wall: String, rect: Rect2, width: float, sill: float, header: float) -> Dictionary:
	var center: Vector2
	match wall:
		"N", "S":
			var y: float = rect.position.y if wall == "N" else rect.end.y
			var cx: float = clampf(rect.get_center().x, rect.position.x + CORNER_MARGIN + width * 0.5, rect.end.x - CORNER_MARGIN - width * 0.5)
			center = Vector2(cx, y)
		"W", "E":
			var x: float = rect.position.x if wall == "W" else rect.end.x
			var cy: float = clampf(rect.get_center().y, rect.position.y + CORNER_MARGIN + width * 0.5, rect.end.y - CORNER_MARGIN - width * 0.5)
			center = Vector2(x, cy)
	return {"room": room_name, "wall": wall, "center": center, "width": width, "sill": sill, "header": header}

# The split discipline, as a helper: when a wall split is proposed at
# position p along an axis that carries windows, shift it the smallest
# amount that clears every window centre by half the window's width
# plus a margin. A split may move; it may never cross a window centre.
# (Idea credited to Frank Gennari's 3DWorld — shift_val_to_not_intersect_window —
# reimplemented here in our own code; see Sources & further reading.)
static func nudge_split_clear_of_windows(p: float, windows_on_axis: Array, margin: float = 0.15) -> float:
	var result: float = p
	for window in windows_on_axis:
		var c: float = window["axis_center"]
		var half: float = float(window["width"]) * 0.5 + margin
		if absf(result - c) < half:
			result = c + half if result >= c else c - half
	return result
