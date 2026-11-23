@tool
class_name DungeonOverlay
extends Node2D
## Debug view of the room graph, drawn over the tile render:
## circles at room centres, lines along edges. Deliberately ugly
## and deliberately honest — a picture OF the data, never a
## replacement for it. Ch 24 extends the edge colours for locks.
##
## Capture integration (Part IV screenshot contract): the overlay
## also draws the markers the chapter captions require — the brass
## key's room (Ch 24 render), WFC pillar cells (Ch 25 step 16), and
## the dressing / spawn manifests (Ch 25 step 18). In markers_only
## mode it draws ONLY those markers (no graph lines), which is how
## the dressed finale render shows manifests without graph clutter.
## The listings' graph drawing below is unchanged.

var data: DungeonData = null
var cell: int = 16
var markers_only: bool = false

func show_data(p_data: DungeonData, p_cell: int = 16) -> void:
	data = p_data
	cell = p_cell
	visible = true
	queue_redraw()

func _draw() -> void:
	if data == null:
		return
	if markers_only:
		_draw_markers()
		return
	for edge in data.edges:
		var a: Vector2i = data.room_by_id(int(edge["a"]))["center"]
		var b: Vector2i = data.room_by_id(int(edge["b"]))["center"]
		var kind: String = str(edge.get("kind", "locked" if str(edge["locked_key"]) != "" else "open"))
		var pa: Vector2 = _to_px(a)
		var pb: Vector2 = _to_px(b)
		match kind:
			"locked":
				draw_line(pa, pb, Color(0.95, 0.3, 0.3), 2.5)
			"secret":
				# Dashed purple: eight short segments along the edge.
				for i in range(8):
					var t0: float = float(i) / 8.0
					var t1: float = t0 + 0.06
					draw_line(pa.lerp(pb, t0), pa.lerp(pb, t1), Color(0.75, 0.45, 0.95), 2.0)
			"one_way":
				draw_line(pa, pb, Color(0.3, 0.9, 0.95), 2.0)
				# Arrowhead at the b end: the permitted direction.
				var dirv: Vector2 = (pb - pa).normalized()
				var perp: Vector2 = Vector2(-dirv.y, dirv.x)
				draw_line(pb, pb - dirv * 9.0 + perp * 5.0, Color(0.3, 0.9, 0.95), 2.0)
				draw_line(pb, pb - dirv * 9.0 - perp * 5.0, Color(0.3, 0.9, 0.95), 2.0)
			_:
				draw_line(pa, pb, Color(0.3, 0.9, 0.95), 2.0)
	for room in data.rooms:
		var centre: Vector2i = room["center"]
		var is_entrance: bool = int(room["id"]) == data.entrance_room
		var col: Color = Color(0.3, 0.85, 0.35) if is_entrance else Color(0.95, 0.9, 0.4)
		draw_circle(_to_px(centre), 7.0, col)
		draw_arc(_to_px(centre), 7.0, 0.0, TAU, 24, Color.BLACK, 1.5)
		var role: String = str(data.roles.get(int(room["id"]), ""))
		var letter: String = ""
		match role:
			"entrance":
				letter = "E"
			"boss":
				letter = "B"
			"treasure":
				letter = "T"
		if letter != "":
			draw_string(ThemeDB.fallback_font, _to_px(centre) + Vector2(10, -8),
				letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.4))
	# Key markers: a gold diamond + "K" on every room holding a key,
	# so the Ch 24 lock & key render shows the key's home at a glance.
	for k in data.keys:
		var kroom: Dictionary = data.room_by_id(int(k["room_id"]))
		if kroom.is_empty():
			continue
		var kc: Vector2 = _to_px(kroom["center"])
		var d: float = 9.0
		draw_polyline(PackedVector2Array([
			kc + Vector2(0, -d), kc + Vector2(d, 0), kc + Vector2(0, d),
			kc + Vector2(-d, 0), kc + Vector2(0, -d)]), Color(1.0, 0.85, 0.2), 2.0)
		draw_string(ThemeDB.fallback_font, kc + Vector2(-5, 22),
			"K", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.2))

## Manifest markers (Ch 25): pillars from meta, then the dressing
## and spawn manifests, one shape/colour per kind. Drawn only in
## markers_only mode (steps 16 and 18/19 of the stage).
func _draw_markers() -> void:
	for p in data.meta.get("pillars", []):
		_draw_cell_marker(p, "pillar")
	for item in data.meta.get("dressing", []):
		_draw_cell_marker(item["cell"], str(item["kind"]))
	for item in data.meta.get("spawns", []):
		_draw_cell_marker(item["cell"], str(item["kind"]))

func _draw_cell_marker(tile: Vector2i, kind: String) -> void:
	var c: Vector2 = _to_px(tile)
	var half: float = cell * 0.32
	match kind:
		"pillar":
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), Color(0.85, 0.85, 0.9))
		"torch":
			draw_circle(c, 3.5, Color(1.0, 0.6, 0.15))
		"chest":
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), Color(0.95, 0.75, 0.2))
		"rubble":
			draw_circle(c, 4.0, Color(0.55, 0.52, 0.5))
		"brazier":
			draw_circle(c, 5.0, Color(0.95, 0.35, 0.15))
		"loot":
			var d: float = half
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d),
				c + Vector2(-d, 0), c + Vector2(0, -d)]), Color(1.0, 0.9, 0.25), 2.0)
		"enemy":
			draw_circle(c, 5.0, Color(0.9, 0.25, 0.25))
			draw_arc(c, 5.0, 0.0, TAU, 16, Color.BLACK, 1.5)
		"boss":
			draw_circle(c, 7.0, Color(0.85, 0.1, 0.35))
			draw_arc(c, 7.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.3), 2.0)
		_:
			draw_circle(c, 3.0, Color(0.9, 0.9, 0.9))

func _to_px(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * cell
