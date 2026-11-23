extends Control
## Seed browser: the part's signature tool.
## Contains NO generation logic — it calls FieldGenerators for data
## and FieldView for pictures, twelve worlds at a time. Favourites
## persist to user:// as a plain JSON list of seeds: a shareable
## shortlist of worlds, possible only because same seed = same world.

const GRID_COUNT: int = 12
const GRID_FIELD_SIZE: int = 25
const FAVOURITES_PATH: String = "user://favourite_seeds.json"

var current_seed: int = 20261119
var favourites: Array[int] = []
var _grid_rects: Array[TextureRect] = []

@onready var seed_edit: LineEdit = $TopBar/SeedEdit
@onready var main_preview: TextureRect = $Body/MainPreview
@onready var seed_grid: GridContainer = $Body/SeedGrid
@onready var fav_label: Label = $FavLabel


func _ready() -> void:
	_load_favourites()
	for i in GRID_COUNT:
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(110, 110)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		seed_grid.add_child(rect)
		_grid_rects.append(rect)
	$TopBar/PrevButton.pressed.connect(func() -> void: _set_seed(current_seed - 1))
	$TopBar/NextButton.pressed.connect(func() -> void: _set_seed(current_seed + 1))
	$TopBar/GoButton.pressed.connect(func() -> void: _set_seed(int(seed_edit.text)))
	$TopBar/FavButton.pressed.connect(_on_favourite_pressed)
	_set_seed(current_seed)


func _set_seed(new_seed: int) -> void:
	current_seed = new_seed
	seed_edit.text = str(current_seed)
	_render()


func _render() -> void:
	var main_field: HeightField = FieldGenerators.fractal_height_field(current_seed)
	main_preview.texture = FieldView.texture_from_values(main_field.heights, main_field.size, FieldView.Ramp.HEIGHT)
	for i in GRID_COUNT:
		var s: int = current_seed + i
		var small: HeightField = FieldGenerators.fractal_height_field(s, GRID_FIELD_SIZE, 5.2)
		_grid_rects[i].texture = FieldView.texture_from_values(small.heights, small.size, FieldView.Ramp.HEIGHT)
	_update_fav_label()


func _on_favourite_pressed() -> void:
	if not favourites.has(current_seed):
		favourites.append(current_seed)
		_save_favourites()
	_update_fav_label()


func _update_fav_label() -> void:
	fav_label.text = "Favourites: %s" % (str(favourites) if not favourites.is_empty() else "—")


func _save_favourites() -> void:
	var file := FileAccess.open(FAVOURITES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(favourites))


func _load_favourites() -> void:
	if not FileAccess.file_exists(FAVOURITES_PATH):
		return
	var file := FileAccess.open(FAVOURITES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		favourites.clear()
		for v in parsed:
			favourites.append(int(v))
