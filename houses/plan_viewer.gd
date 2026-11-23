@tool
class_name PlanViewer
extends Control
## Pure 2D floor-plan renderer. Takes room Dictionaries (name / type /
## zone / rect, in metres) and draws them scaled to fit. It never
## generates anything — generation lives in the stage and the layouts.
## It DOES judge, a little: highlight modes and a flagged list are the
## debugging instruments Chapters 27–29 grade plans with.
##
## Integration notes (project harness):
## - @tool so the plan is visible in the editor for ENGINE captures.
## - Ch 29 Listing 29.8's V2 door drawing is adapted to this file's
##   actual helpers (_origin()/_scale()/PAPER): the listing's
##   _to_screen()/scale_factor/bg names do not exist in Listing 26.1.
## - _draw_windows() accepts BOTH window formats: Ch 26's classic
##   {side, center:float} and Ch 30 WindowPlacer's {wall, center:Vector2}.

const ZONE_COLORS: Dictionary = {
	"social": Color(0.95, 0.75, 0.45),
	"private": Color(0.55, 0.70, 0.95),
	"service": Color(0.65, 0.85, 0.60),
	"circulation": Color(0.80, 0.80, 0.78),
}
const PAPER := Color(0.96, 0.94, 0.90)
const WALL := Color(0.15, 0.15, 0.15)
const FLAG_FILL := Color(0.9, 0.25, 0.2, 0.35)
const FLAG_LINE := Color(0.85, 0.15, 0.1)
const HIGHLIGHT_MODES: Array = ["none", "small", "skinny", "no_exterior"]

var plan: Array = []
var footprint: Rect2 = Rect2(0, 0, 10, 8)
var show_zones: bool = true
var highlight_mode: String = "none"
var flagged: Array = []
var doors: Array = []
var doors_v2: Array = [] # Ch 29: name-keyed doors from DoorGraph.build_doors()
var windows: Array = []
var desks: Array = []
var entrance_index: int = -1
var specs_mode: bool = false
var specs: Array = []

func set_plan(new_plan: Array, new_footprint: Rect2) -> void:
	plan = new_plan
	footprint = new_footprint
	specs_mode = false
	queue_redraw()

func set_specs(new_specs: Array, new_footprint: Rect2) -> void:
	# Step 1's budget view: no layout exists yet, so rooms are drawn as
	# horizontal budget bars — target area as bar length, in m².
	specs = new_specs
	footprint = new_footprint
	specs_mode = true
	queue_redraw()

func set_flagged(names: Array) -> void:
	flagged = names
	queue_redraw()

func set_doors(new_doors: Array) -> void:
	doors = new_doors
	doors_v2 = []
	queue_redraw()

func set_doors_v2(new_doors: Array) -> void:
	doors_v2 = new_doors
	doors = []
	queue_redraw()

func set_windows(new_windows: Array) -> void:
	windows = new_windows
	queue_redraw()

func set_desks(new_desks: Array) -> void:
	desks = new_desks
	queue_redraw()

func set_entrance(index: int) -> void:
	entrance_index = index
	queue_redraw()

func _scale() -> float:
	var avail: Vector2 = size - Vector2(48, 72)
	return minf(avail.x / footprint.size.x, avail.y / footprint.size.y)

func _origin() -> Vector2:
	return (size - Vector2(0, 24) - footprint.size * _scale()) * 0.5

func _px(r: Rect2) -> Rect2:
	return Rect2(_origin() + (r.position - footprint.position) * _scale(), r.size * _scale())

func _to_screen(p: Vector2) -> Vector2:
	return _origin() + (p - footprint.position) * _scale()

func _room_is_flagged(room: Dictionary) -> bool:
	if String(room["name"]) in flagged:
		return true
	if not room.has("rect"):
		return false
	var rect: Rect2 = room["rect"]
	match highlight_mode:
		"small":
			return rect.get_area() < float(room.get("min", 0.0))
		"skinny":
			return maxf(rect.size.x, rect.size.y) / minf(rect.size.x, rect.size.y) > 2.5
		"no_exterior":
			var tol: float = 0.05
			return not (
				rect.position.x <= footprint.position.x + tol
				or rect.position.y <= footprint.position.y + tol
				or rect.end.x >= footprint.end.x - tol
				or rect.end.y >= footprint.end.y - tol
			)
	return false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.13, 0.15))
	if specs_mode:
		_draw_specs()
		return
	if plan.is_empty():
		return
	draw_rect(_px(footprint), PAPER)
	var font: Font = get_theme_default_font()
	for room in plan:
		var rect: Rect2 = room["rect"]
		var fill: Color = PAPER.darkened(0.08)
		if show_zones:
			fill = ZONE_COLORS.get(room["zone"], fill)
		draw_rect(_px(rect), fill)
		draw_rect(_px(rect), WALL, false, 2.0)
	for room in plan:
		if _room_is_flagged(room):
			var px: Rect2 = _px(room["rect"])
			draw_rect(px, FLAG_FILL)
			draw_rect(px, FLAG_LINE, false, 3.0)
	for room in plan:
		var px: Rect2 = _px(room["rect"])
		var area: float = room["rect"].get_area()
		draw_string(font, px.position + Vector2(6, 18), String(room["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.1, 0.1, 0.1))
		draw_string(font, px.position + Vector2(6, 34), "%.1f m²" % area, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.25, 0.25))
	if not doors_v2.is_empty():
		_draw_v2_doors()
	elif not doors.is_empty():
		_draw_doors()
	_draw_windows()
	_draw_desks()
	_draw_entrance()
	var dim_text: String = "%.1f × %.1f m" % [footprint.size.x, footprint.size.y]
	draw_string(font, Vector2(16, size.y - 12), dim_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(font, Vector2(16, size.y - 32), "Highlight: " + highlight_mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.7))
	if show_zones:
		var lx: float = size.x - 340.0
		for zone_name in ZONE_COLORS.keys():
			draw_rect(Rect2(lx, size.y - 44, 14, 14), ZONE_COLORS[zone_name])
			draw_rect(Rect2(lx, size.y - 44, 14, 14), WALL, false, 1.0)
			draw_string(font, Vector2(lx + 20, size.y - 32), zone_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
			lx += 20.0 + font.get_string_size(zone_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0

func _draw_specs() -> void:
	var font: Font = get_theme_default_font()
	var total: float = 0.0
	for s in specs:
		total += float(s["target"])
	draw_string(font, Vector2(24, 36), "Program budget — footprint %.1f m², targets sum to %.1f m² (slack is distributed by the layout)" % [footprint.get_area(), total], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	var y: float = 64.0
	var max_target: float = 1.0
	for s in specs:
		max_target = maxf(max_target, float(s["target"]))
	for s in specs:
		var bar_w: float = (size.x - 360.0) * float(s["target"]) / max_target
		var col: Color = ZONE_COLORS.get(s["zone"], PAPER)
		draw_rect(Rect2(24, y, bar_w, 22), col)
		draw_rect(Rect2(24, y, bar_w, 22), WALL, false, 1.0)
		var label: String = "%s (%s) — target %.1f m², min %.1f m²" % [s["name"], s["type"], float(s["target"]), float(s["min"])]
		draw_string(font, Vector2(32 + bar_w, y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		y += 32.0

func _draw_doors() -> void:
	var s: float = _scale()
	for d in doors:
		if not d.has("center"):
			continue
		var c: Vector2 = _origin() + (Vector2(d["center"]) - footprint.position) * s
		var w_px: float = float(d["width"]) * s
		var gap: Rect2
		if bool(d.get("horizontal", false)):
			gap = Rect2(c - Vector2(w_px * 0.5, 3.0), Vector2(w_px, 6.0))
		else:
			gap = Rect2(c - Vector2(3.0, w_px * 0.5), Vector2(6.0, w_px))
		draw_rect(gap, PAPER)
		draw_rect(gap, WALL, false, 1.0)

func _draw_v2_doors() -> void:
	# Ch 29 Listing 29.8, adapted to Listing 26.1's helpers (see header).
	for door in doors_v2:
		var center: Vector2 = _to_screen(door["center"])
		var width_px: float = float(door["width"]) * _scale()
		var kind: String = door["kind"]
		if kind == "entrance":
			# A green wedge on the street edge, pointing into the house.
			var tip: Vector2 = center + Vector2(0, -width_px * 0.7)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-width_px * 0.5, 0), center + Vector2(width_px * 0.5, 0), tip]),
				Color(0.2, 0.75, 0.3))
		elif kind == "opening":
			# A gap band across the shared wall: plan colour, wide.
			var size: Vector2 = Vector2(6.0, width_px) if door["vertical"] else Vector2(width_px, 6.0)
			draw_rect(Rect2(center - size * 0.5, size), PAPER)
			draw_rect(Rect2(center - size * 0.5, size), Color(0.2, 0.2, 0.2), false, 1.0)
		else:
			# A door: wall-coloured gap with a dark outline, like Ch 28.
			var size: Vector2 = Vector2(6.0, width_px) if door["vertical"] else Vector2(width_px, 6.0)
			draw_rect(Rect2(center - size * 0.5, size), PAPER)
			draw_rect(Rect2(center - size * 0.5, size), Color(0.2, 0.2, 0.2), false, 1.5)

func _draw_windows() -> void:
	var s: float = _scale()
	for w in windows:
		if w.has("wall"):
			# Ch 30 WindowPlacer format: {room, wall, center:Vector2, width, sill, header}.
			var c: Vector2 = _to_screen(Vector2(w["center"]))
			var half_w: float = float(w["width"]) * 0.5 * s
			var horiz: bool = String(w["wall"]) == "N" or String(w["wall"]) == "S"
			var a2: Vector2 = c - (Vector2(half_w, 0) if horiz else Vector2(0, half_w))
			var b2: Vector2 = c + (Vector2(half_w, 0) if horiz else Vector2(0, half_w))
			draw_line(a2, b2, Color(0.35, 0.65, 0.95), 5.0)
			continue
		var side: String = w["side"]
		var centre: float = float(w["center"])
		var half: float = float(w["width"]) * 0.5 * s
		var a: Vector2
		var b: Vector2
		match side:
			"N":
				a = _origin() + Vector2(centre * s - half, 0)
				b = _origin() + Vector2(centre * s + half, 0)
			"S":
				a = _origin() + Vector2(centre * s - half, footprint.size.y * s)
				b = _origin() + Vector2(centre * s + half, footprint.size.y * s)
			"W":
				a = _origin() + Vector2(0, centre * s - half)
				b = _origin() + Vector2(0, centre * s + half)
			"E":
				a = _origin() + Vector2(footprint.size.x * s, centre * s - half)
				b = _origin() + Vector2(footprint.size.x * s, centre * s + half)
		draw_line(a, b, Color(0.35, 0.65, 0.95), 5.0)

func _draw_entrance() -> void:
	if entrance_index < 0 or entrance_index >= plan.size():
		return
	var rect: Rect2 = plan[entrance_index]["rect"]
	var s: float = _scale()
	var cx: float = _origin().x + (rect.position.x + rect.size.x * 0.5 - footprint.position.x) * s
	var by: float = _origin().y + (rect.end.y - footprint.position.y) * s
	var tri: PackedVector2Array = [Vector2(cx - 9, by + 12), Vector2(cx + 9, by + 12), Vector2(cx, by + 1)]
	draw_colored_polygon(tri, Color(0.9, 0.2, 0.15))
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(cx - 34, by + 28), "FRONT DOOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.3, 0.25))

func _draw_desks() -> void:
	var s: float = _scale()
	for desk in desks:
		var c: Vector2 = _origin() + (Vector2(desk["pos"]) - footprint.position) * s
		draw_circle(c, 3.5, Color(0.20, 0.35, 0.75))
		var facing: Vector2 = Vector2(0, -1) if float(desk["rot_deg"]) < 90.0 else Vector2(0, 1)
		draw_line(c, c + facing * 7.0, Color(0.20, 0.35, 0.75), 1.5)
