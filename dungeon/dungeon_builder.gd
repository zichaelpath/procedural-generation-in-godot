@tool
class_name DungeonBuilder
extends Node2D
## The dumb renderer: reads DungeonData, writes a TileMapLayer. The
## TileSet is four coloured squares generated in code — no art assets,
## so the data stays the star. Ch 25 adds dressing markers beside it;
## the tile contract never changes.

const CELL: int = 16

var layer: TileMapLayer = null
var tint_root: Node2D = null

const TILE_COLORS: Array = [
	Color(0.13, 0.13, 0.17),  # WALL
	Color(0.55, 0.48, 0.38),  # FLOOR
	Color(0.68, 0.6, 0.47),   # CORRIDOR
	Color(0.9, 0.55, 0.2),    # DOOR
]

func _ready() -> void:
	layer = TileMapLayer.new()
	layer.tile_set = _make_tileset()
	add_child(layer)
	tint_root = Node2D.new()
	add_child(tint_root)

func _make_tileset() -> TileSet:
	# One atlas image: 4 squares side by side, one per tile type.
	var img := Image.create(CELL * 4, CELL, false, Image.FORMAT_RGBA8)
	for t in range(4):
		var col: Color = TILE_COLORS[t]
		for y in range(CELL):
			for x in range(CELL):
				img.set_pixel(t * CELL + x, y, col)
	var tex := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(CELL, CELL)
	for t in range(4):
		source.create_tile(Vector2i(t, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_source(source, 0)
	return ts

func render(data: DungeonData) -> void:
	if layer == null:
		_ready()
	layer.clear()
	for y in range(data.height):
		for x in range(data.width):
			var pos := Vector2i(x, y)
			layer.set_cell(pos, 0, Vector2i(data.get_tile(pos), 0))
	_render_room_tints(data)

func _render_room_tints(data: DungeonData) -> void:
	# Tagged rooms (e.g. "grand" from Ch 21) get a translucent tint
	# polygon above the tiles, so metadata is visible at a glance.
	for child in tint_root.get_children():
		child.queue_free()
	for room in data.rooms:
		if (room["tags"] as Array).has("grand"):
			var rect: Rect2i = room["rect"]
			var poly := Polygon2D.new()
			var origin := Vector2(rect.position) * CELL
			var size := Vector2(rect.size) * CELL
			poly.polygon = PackedVector2Array([
				origin, origin + Vector2(size.x, 0),
				origin + size, origin + Vector2(0, size.y)])
			poly.color = Color(0.95, 0.8, 0.25, 0.18)
			tint_root.add_child(poly)

func print_ascii(data: DungeonData) -> void:
	print(data.to_ascii())
