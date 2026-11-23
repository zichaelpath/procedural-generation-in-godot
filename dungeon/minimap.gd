@tool
class_name Minimap
extends Control
## The minimap is a READER: rooms, doors, and role icons drawn
## from DungeonData. It exists to prove a point — data-first
## generation makes late features cheap — and to be genuinely
## useful while seed-sweeping.

var data: DungeonData = null
var revealed: Dictionary = {}   # room_id -> true
var reveal_all: bool = false    # cartographer mode

func set_dungeon(new_data: DungeonData) -> void:
	data = new_data
	revealed.clear()
	if data != null and data.entrance_room >= 0:
		revealed[data.entrance_room] = true
	queue_redraw()

func reveal_room(room_id: int) -> void:
	revealed[room_id] = true
	queue_redraw()

func _scale_factor() -> float:
	if data == null or data.width == 0:
		return 1.0
	return minf(size.x / float(data.width), size.y / float(data.height))

func _cell_to_map(cell: Vector2i) -> Vector2:
	return Vector2(cell) * _scale_factor()

func _draw() -> void:
	if data == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08))
	var s: float = _scale_factor()
	for room in data.rooms:
		var id: int = int(room["id"])
		if not reveal_all and not revealed.has(id):
			continue
		var rect: Rect2i = room["rect"]
		var map_rect := Rect2(_cell_to_map(rect.position), Vector2(rect.size) * s)
		draw_rect(map_rect, Color(0.45, 0.4, 0.32))
		_draw_room_icon(room, map_rect)
	for edge in data.edges:
		var door: Vector2i = edge["door_tile"]
		if not reveal_all and not (revealed.has(int(edge["a"])) and revealed.has(int(edge["b"]))):
			continue
		var kind: String = str(edge.get("kind", "open"))
		var col: Color = Color(0.95, 0.3, 0.3) if kind == "locked" else Color(0.9, 0.75, 0.3)
		draw_circle(_cell_to_map(door) + Vector2.ONE * s * 0.5, 2.5, col)

func _draw_room_icon(room: Dictionary, map_rect: Rect2) -> void:
	if data == null:
		return
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
		draw_string(get_theme_default_font(), map_rect.position + Vector2(3, 11),
			letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.9, 0.4))
