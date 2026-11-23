@tool
extends Node2D

## Environments stage: builds the climate data for the book's master
## seed and shows every grid as a picture. Data first — the mesh
## arrives in Chapter 9; these previews are how we debug until then.
##
## NOTE (@tool): Listing 5.4 is printed without @tool, but the chapter's
## own ENGINE screenshot requires the biome preview to be visible in the
## editor, which only happens if the stage generates at edit time.

@export var preview_size: int = 320
@export var use_montreal: bool = false

var data: TerrainHeight
var flow: FlowField

func _ready() -> void:
	if use_montreal:
		load_montreal()
		_set_preview($UI/Previews/HeightPreview, _height_image())
		_set_preview($UI/Previews/MoisturePreview, _moisture_image())
		_set_preview($UI/Previews/BiomePreview, _biome_image())
		return
	var config := WorldConfig.new()
	config.master_seed = 20261119
	# Part I terrain sea level (Listing 5.1: 5.0). WorldConfig's shared
	# sea_level default is 0.0 at the Part II stages' scale, so the
	# terrain value is set on this stage's own config instance.
	config.sea_level = 5.0
	data = TerrainHeight.new()
	data.generate(config)
	_set_preview($UI/Previews/HeightPreview, _height_image())
	_set_preview($UI/Previews/MoisturePreview, _moisture_image())
	_set_preview($UI/Previews/BiomePreview, _biome_image())
	_set_preview($UI/Previews/RulePreview, _rule_image())
	_set_preview($UI/Previews/DisagreementPreview, _disagreement_image())
	flow = FlowField.new()
	# NOTE: Listing 7.4 sets flow.width AFTER calling filled_heights(),
	# but filled_heights() reads width to find the edge cells — with
	# width still 0 the fill silently returns the source unchanged.
	# The chapter text itself says width is set before the fill; the
	# assignment is moved above the call to match it.
	flow.width = data.row_width()
	var filled: PackedFloat32Array = flow.filled_heights(data.heights)
	flow.compute(filled, data.row_width(), data.sea_level)
	flow.watershed_labels()
	data.carve_rivers(flow, 60.0, 2.0)
	_set_preview($UI/Previews/FlowPreview, _flow_image())
	_set_preview($UI/Previews/WatershedPreview, _watershed_image())
	_set_preview($UI/Previews/HeightPreview, _height_image())  # re-show, carved
	# Carving re-ran classify_all() and build_rule_labels() (Listing 7.4's
	# own comment: "every height-derived answer is stale"), so the biome,
	# rule and disagreement previews are re-shown too — Listing 7.4 only
	# re-shows the height preview, which would leave them pre-carve.
	_set_preview($UI/Previews/BiomePreview, _biome_image())
	_set_preview($UI/Previews/RulePreview, _rule_image())
	_set_preview($UI/Previews/DisagreementPreview, _disagreement_image())

func _set_preview(rect: TextureRect, img: Image) -> void:
	# FIX (captures): as printed, no listing ever reads the preview_size
	# export, and Godot's Keep Aspect Centered stretch does not upscale
	# the 129x129 grid image — the previews would render at native size.
	# Resizing to preview_size here makes the export real. NEAREST keeps
	# categorical biome colours pure (no blended in-between colours).
	img.resize(preview_size, preview_size, Image.INTERPOLATE_NEAREST)
	rect.texture = ImageTexture.create_from_image(img)

func _blank_image() -> Image:
	return Image.create(data.row_width(), data.row_width(), false, Image.FORMAT_RGB8)

func _height_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			var v: float = clampf(data.grid_height(ix, iz) / data.height_scale, 0.0, 1.0)
			img.set_pixel(ix, iz, Color(v, v, v))
	return img

func _moisture_image() -> Image:
	var img: Image = _blank_image()
	var dry := Color(0.55, 0.42, 0.25)
	var wet := Color(0.15, 0.35, 0.75)
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			img.set_pixel(ix, iz, dry.lerp(wet, data.moisture_at(ix, iz)))
	return img

func _biome_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			img.set_pixel(ix, iz, _biome_color(data.biome_at(ix, iz)))
	return img

func _biome_color(id: int) -> Color:
	match id:
		BiomeClassifier.OCEAN: return Color(0.13, 0.28, 0.42)
		BiomeClassifier.BEACH: return Color(0.76, 0.70, 0.47)
		BiomeClassifier.DESERT: return Color(0.82, 0.66, 0.38)
		BiomeClassifier.GRASSLAND: return Color(0.45, 0.60, 0.28)
		BiomeClassifier.FOREST: return Color(0.20, 0.42, 0.20)
		BiomeClassifier.RAINFOREST: return Color(0.10, 0.38, 0.22)
		BiomeClassifier.TAIGA: return Color(0.30, 0.42, 0.30)
		BiomeClassifier.TUNDRA: return Color(0.62, 0.62, 0.52)
		BiomeClassifier.ROCK: return Color(0.45, 0.42, 0.40)
		BiomeClassifier.SNOW: return Color(0.92, 0.93, 0.95)
	return Color(1, 0, 1)  # magenta: an unclassified cell is a BUG, shown loudly

func _rule_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			img.set_pixel(ix, iz, _label_color(data.rule_labels[data.index(ix, iz)]))
	return img

func _label_color(label: String) -> Color:
	match label:
		"Ocean": return Color(0.13, 0.28, 0.42)
		"Beach": return Color(0.76, 0.70, 0.47)
		"Desert": return Color(0.82, 0.66, 0.38)
		"Grassland": return Color(0.45, 0.60, 0.28)
		"Forest": return Color(0.20, 0.42, 0.20)
		"Rainforest": return Color(0.10, 0.38, 0.22)
		"Taiga": return Color(0.30, 0.42, 0.30)
		"Tundra": return Color(0.62, 0.62, 0.52)
		"Rock": return Color(0.45, 0.42, 0.40)
		"Snow": return Color(0.92, 0.93, 0.95)
	return Color(1, 0, 1)

func _disagreement_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			var id_name: String = _id_name(data.biome_at(ix, iz))
			var same: bool = id_name == data.rule_labels[data.index(ix, iz)]
			img.set_pixel(ix, iz, Color(0.95, 0.95, 0.95) if same else Color(0.85, 0.15, 0.10))
	return img

func _id_name(id: int) -> String:
	match id:
		BiomeClassifier.OCEAN: return "Ocean"
		BiomeClassifier.BEACH: return "Beach"
		BiomeClassifier.DESERT: return "Desert"
		BiomeClassifier.GRASSLAND: return "Grassland"
		BiomeClassifier.FOREST: return "Forest"
		BiomeClassifier.RAINFOREST: return "Rainforest"
		BiomeClassifier.TAIGA: return "Taiga"
		BiomeClassifier.TUNDRA: return "Tundra"
		BiomeClassifier.ROCK: return "Rock"
		BiomeClassifier.SNOW: return "Snow"
	return "?"

func _flow_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			var i: int = data.index(ix, iz)
			var a: float = flow.accumulation[i]
			# Log scale: accumulation spans 1..10000+, and a linear ramp
			# would show only the single biggest river.
			var v: float = clampf(log(maxf(a, 1.0)) / log(10000.0), 0.0, 1.0)
			if data.grid_height(ix, iz) < data.sea_level:
				img.set_pixel(ix, iz, Color(0.05, 0.08, 0.12))
			else:
				img.set_pixel(ix, iz, Color(0.1, 0.1, 0.1).lerp(Color(0.3, 0.6, 1.0), v))
	return img

func _watershed_image() -> Image:
	var img: Image = _blank_image()
	for iz in range(data.row_width()):
		for ix in range(data.row_width()):
			if data.grid_height(ix, iz) < data.sea_level:
				img.set_pixel(ix, iz, Color(0.05, 0.08, 0.12))
				continue
			var label: int = flow.labels[data.index(ix, iz)]
			# Categorical colour from a hash of the label: neighbouring
			# catchments must differ, with no implied ordering.
			var h: float = float(absi(hash("watershed:" + str(label))) % 360) / 360.0
			img.set_pixel(ix, iz, Color.from_hsv(h, 0.55, 0.85))
	return img

func load_montreal() -> void:
	var config := WorldConfig.new()
	config.master_seed = 20261119
	data = TerrainHeight.new()
	data.generate(config)  # sizes the grids; heights are replaced next
	data.sea_level = 16.0  # tuned against the real river; see text
	var result: Dictionary = HeightmapImport.import_grid(
			"res://terrain/data/montreal_heightmap.png", 233.0, 2.0)
	if result.is_empty():
		push_error("Montreal import failed; staying on the noise island.")
		return
	data.load_grid(result["heights"], int(result["points"]), 24000.0, 466.0)
	var lookout: Vector2 = GeoReference.latlon_to_world(
			45.5048, -73.5878, 45.4000, -73.7500, 24000.0)
	print("Mount Royal lookout at world ", lookout,
			" — check the height preview near map centre.")
