extends SceneTree
## TEMPORARY Part 0 scene builder (capture-recovery worker).
## Builds every Part 0 lab scene + main.tscn + remap_curve.tres to the
## chapter specs. Trees are assembled OUTSIDE the SceneTree so no
## _ready() generation runs and nothing runtime-generated is baked in:
## only authored nodes get owner set, exactly like an editor save.

var failures: int = 0


func _initialize() -> void:
	_build_curve()
	_build_seed_demo()
	_build_main()
	_build_dice_lab()
	_build_noise_gallery()
	_build_noise_explorer()
	_build_fractal_explorer()
	_build_sampling_lab()
	_build_sampling_probe()
	_build_distribution_bench()
	_build_remap_lab()
	_build_grid_playground()
	_build_height_field_demo()
	_build_debug_panel_demo()
	_build_seed_browser()
	_build_determinism_test()
	print("BUILDER DONE failures=", failures)
	quit(1 if failures > 0 else 0)


# ---------- helpers ----------

func _save_scene(root_node: Node, path: String) -> void:
	for child in root_node.get_children():
		_set_owner_recursive(child, root_node)
	var ps := PackedScene.new()
	var perr: Error = ps.pack(root_node)
	if perr != OK:
		print("PACK FAIL ", path, " err=", perr)
		failures += 1
		return
	var serr: Error = ResourceSaver.save(ps, path)
	print("SAVED ", path, " save_err=", serr)
	if serr != OK:
		failures += 1
	root_node.free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)


func _script(path: String) -> Script:
	return load(path) as Script


func _light() -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = "DirectionalLight3D"
	l.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	l.shadow_enabled = true
	return l


func _env(aces: bool) -> WorldEnvironment:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.25, 0.45, 0.75)
	mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	mat.ground_bottom_color = Color(0.05, 0.09, 0.14)
	mat.ground_horizon_color = Color(0.55, 0.65, 0.75)
	var sky := Sky.new()
	sky.sky_material = mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.ambient_light_sky_contribution = 0.5
	if aces:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	return we


func _cam(pos: Vector3, rot: Vector3) -> Camera3D:
	var c := Camera3D.new()
	c.name = "Camera3D"
	c.position = pos
	c.rotation_degrees = rot
	c.current = true
	return c


func _full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c


func _place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	return c


func _tex_rect(node_name: String, min_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.custom_minimum_size = min_size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return t


func _label(node_name: String, text: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	return l


func _vbox_with_label_rect(vbox_name: String, label_text: String, rect_name: String, rect_min: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = vbox_name
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_label("Label", label_text))
	v.add_child(_tex_rect(rect_name, rect_min))
	return v


# ---------- resources ----------

func _build_curve() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(0.5, 0.45))
	curve.add_point(Vector2(1.0, 0.95))
	var err: Error = ResourceSaver.save(curve, "res://debug/remap_curve.tres")
	print("SAVED res://debug/remap_curve.tres err=", err)
	if err != OK:
		failures += 1


# ---------- scenes ----------

func _build_seed_demo() -> void:
	var root_node := Node3D.new()
	root_node.name = "SeedDemo"
	root_node.set_script(_script("res://debug/seed_demo.gd"))
	var scatter := Node3D.new()
	scatter.name = "Scatter"
	root_node.add_child(scatter)
	root_node.add_child(_light())
	root_node.add_child(_env(false))
	root_node.add_child(_cam(Vector3(0, 22, 30), Vector3(-36, 0, 0)))
	var ui := CanvasLayer.new()
	ui.name = "UI"
	var seeded := Button.new()
	seeded.name = "SeededButton"
	seeded.text = "Rebuild — Seed 42"
	_place(seeded, 16, 16, 210, 40)
	var random_b := Button.new()
	random_b.name = "RandomButton"
	random_b.text = "Rebuild — True Random"
	_place(random_b, 16, 64, 230, 40)
	ui.add_child(seeded)
	ui.add_child(random_b)
	root_node.add_child(ui)
	_save_scene(root_node, "res://debug/seed_demo.tscn")


func _build_main() -> void:
	var root_node := Node3D.new()
	root_node.name = "Main"
	root_node.set_script(_script("res://main.gd"))
	root_node.set("master_seed", 20261119)
	root_node.add_child(_light())
	root_node.add_child(_env(true))
	root_node.add_child(_cam(Vector3(0, 60, 85), Vector3(-35, 0, 0)))
	var stage := Node3D.new()
	stage.name = "Stage"
	root_node.add_child(stage)
	var ui := CanvasLayer.new()
	ui.name = "DebugUI"
	var panel := PanelContainer.new()
	panel.name = "PanelContainer"
	_place(panel, 12, 12, 230, 150)
	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	_full_rect(vbox)
	var seed_field := LineEdit.new()
	seed_field.name = "SeedField"
	seed_field.placeholder_text = "Master seed"
	seed_field.text = "20261119"
	var regen := Button.new()
	regen.name = "RegenButton"
	regen.text = "Regenerate"
	var stream_label := Label.new()
	stream_label.name = "StreamLabel"
	stream_label.text = "Streams: —"
	vbox.add_child(seed_field)
	vbox.add_child(regen)
	vbox.add_child(stream_label)
	panel.add_child(vbox)
	ui.add_child(panel)
	root_node.add_child(ui)
	var cerr: Error = regen.connect("pressed", Callable(root_node, "_on_regen_button_pressed"), Object.CONNECT_PERSIST)
	print("main RegenButton connection err=", cerr)
	_save_scene(root_node, "res://main.tscn")


func _build_dice_lab() -> void:
	var root_node := Control.new()
	root_node.name = "DiceLab"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/dice_lab.gd"))
	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	_full_rect(vbox)
	vbox.offset_left = 16.0
	vbox.offset_top = 16.0
	vbox.offset_right = -16.0
	vbox.offset_bottom = -16.0
	var run_button := Button.new()
	run_button.name = "RunButton"
	run_button.text = "Run the lab"
	var output := RichTextLabel.new()
	output.name = "Output"
	output.fit_content = false
	output.scroll_active = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(run_button)
	vbox.add_child(output)
	root_node.add_child(vbox)
	var cerr: Error = run_button.connect("pressed", Callable(root_node, "_on_run_button_pressed"), Object.CONNECT_PERSIST)
	print("dice RunButton connection err=", cerr)
	_save_scene(root_node, "res://debug/dice_lab.tscn")


func _gallery_hbox() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 16)
	hbox.add_child(_vbox_with_label_rect("VBoxValue", "Value", "ValueRect", Vector2(256, 256)))
	hbox.add_child(_vbox_with_label_rect("VBoxPerlin", "Perlin / Gradient", "PerlinRect", Vector2(256, 256)))
	hbox.add_child(_vbox_with_label_rect("VBoxSimplex", "Simplex", "SimplexRect", Vector2(256, 256)))
	return hbox


func _build_noise_gallery() -> void:
	var root_node := Control.new()
	root_node.name = "NoiseGallery"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/noise_gallery.gd"))
	var hbox := _gallery_hbox()
	_full_rect(hbox)
	hbox.offset_left = 16.0
	hbox.offset_top = 16.0
	hbox.offset_right = -16.0
	hbox.offset_bottom = -16.0
	root_node.add_child(hbox)
	_save_scene(root_node, "res://debug/noise_gallery.tscn")


func _build_noise_explorer() -> void:
	var root_node := Control.new()
	root_node.name = "NoiseExplorer"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/noise_explorer.gd"))
	var hbox := _gallery_hbox()
	_place(hbox, 16, 16, 1248, 292)
	root_node.add_child(hbox)
	var hbox2 := HBoxContainer.new()
	hbox2.name = "HBoxContainer2"
	hbox2.add_theme_constant_override("separation", 16)
	_place(hbox2, 16, 324, 1248, 380)
	hbox2.add_child(_tex_rect("LineRect", Vector2(256, 64)))
	hbox2.add_child(_tex_rect("SliceRect", Vector2(256, 256)))
	hbox2.add_child(_tex_rect("CellularRect", Vector2(256, 256)))
	root_node.add_child(hbox2)
	_save_scene(root_node, "res://debug/noise_explorer.tscn")


func _build_fractal_explorer() -> void:
	var root_node := Node3D.new()
	root_node.name = "FractalExplorer"
	root_node.set_script(_script("res://debug/fractal_explorer.gd"))
	root_node.add_child(_light())
	root_node.add_child(_cam(Vector3(0, 55, 70), Vector3(-38, 0, 0)))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	root_node.add_child(mesh_instance)
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer"
	var preview := _tex_rect("OctavePreview", Vector2(256, 256))
	_place(preview, 16, 16, 256, 256)
	layer.add_child(preview)
	var lac := HSlider.new()
	lac.name = "LacunaritySlider"
	lac.min_value = 1.5
	lac.max_value = 3.0
	lac.step = 0.05
	lac.value = 2.0
	_place(lac, 16, 288, 256, 24)
	layer.add_child(lac)
	var gain_s := HSlider.new()
	gain_s.name = "GainSlider"
	gain_s.min_value = 0.2
	gain_s.max_value = 0.8
	gain_s.step = 0.05
	gain_s.value = 0.5
	_place(gain_s, 16, 320, 256, 24)
	layer.add_child(gain_s)
	var names: Array[String] = ["Oct1", "Oct2", "Oct4", "Oct8"]
	var texts: Array[String] = ["1", "2", "4", "8"]
	for i in 4:
		var b := Button.new()
		b.name = names[i]
		b.text = texts[i]
		_place(b, 1024.0 + float(i) * 64.0, 16, 56, 36)
		layer.add_child(b)
	root_node.add_child(layer)
	_save_scene(root_node, "res://debug/fractal_explorer.tscn")


func _build_sampling_lab() -> void:
	var root_node := Control.new()
	root_node.name = "SamplingLab"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/sampling_lab.gd"))
	var probe_label := _label("ProbeLabel", "")
	_place(probe_label, 16, 528, 1000, 28)
	root_node.add_child(probe_label)
	_save_scene(root_node, "res://debug/sampling_lab.tscn")


func _build_sampling_probe() -> void:
	var root_node := Node.new()
	root_node.name = "SamplingProbe"
	root_node.set_script(_script("res://debug/sampling_probe.gd"))
	_save_scene(root_node, "res://debug/sampling_probe.tscn")


func _build_distribution_bench() -> void:
	var root_node := Node3D.new()
	root_node.name = "DistributionBench"
	root_node.set_script(_script("res://debug/distribution_bench.gd"))
	root_node.add_child(_light())
	root_node.add_child(_cam(Vector3(0, 26, 30), Vector3(-48, 0, 0)))
	var row_names: Array[String] = ["UniformRow", "BellRow", "WeightedRow", "HaltonRow"]
	var row_z: Array[float] = [-10.0, 0.0, 10.0, 20.0]
	for i in 4:
		var row := Node3D.new()
		row.name = row_names[i]
		row.position = Vector3(0, 0, row_z[i])
		root_node.add_child(row)
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer"
	var hist := _label("HistogramLabel", "")
	_place(hist, 16, 16, 1100, 96)
	layer.add_child(hist)
	root_node.add_child(layer)
	_save_scene(root_node, "res://debug/distribution_bench.tscn")


func _build_remap_lab() -> void:
	var root_node := Control.new()
	root_node.name = "RemapLab"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/remap_lab.gd"))
	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 16)
	_place(hbox, 16, 16, 832, 288)
	hbox.add_child(_tex_rect("BeforeRect", Vector2(256, 256)))
	hbox.add_child(_tex_rect("AfterRect", Vector2(256, 256)))
	root_node.add_child(hbox)
	var picker := OptionButton.new()
	picker.name = "ModePicker"
	picker.add_item("Linear")
	picker.add_item("Smoothstep")
	picker.add_item("Power 2.2")
	picker.add_item("Curve")
	picker.selected = 0
	_place(picker, 16, 320, 220, 40)
	root_node.add_child(picker)
	var sea := HSlider.new()
	sea.name = "SeaSlider"
	sea.min_value = 0.0
	sea.max_value = 1.0
	sea.step = 0.01
	sea.value = 0.45
	_place(sea, 252, 328, 300, 24)
	root_node.add_child(sea)
	_save_scene(root_node, "res://debug/remap_lab.tscn")


func _build_grid_playground() -> void:
	var root_node := Control.new()
	root_node.name = "GridPlayground"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/grid_playground.gd"))
	var toggle := CheckBox.new()
	toggle.name = "MooreToggle"
	toggle.text = "Moore (8-way) neighbours"
	_place(toggle, 16, 512, 300, 32)
	root_node.add_child(toggle)
	var cell_label := _label("CellLabel", "")
	_place(cell_label, 300, 512, 500, 32)
	root_node.add_child(cell_label)
	_save_scene(root_node, "res://debug/grid_playground.tscn")


func _build_height_field_demo() -> void:
	var root_node := Node3D.new()
	root_node.name = "HeightFieldDemo"
	root_node.set_script(_script("res://debug/height_field_demo.gd"))
	root_node.set("master_seed", 20261119)
	root_node.add_child(_light())
	root_node.add_child(_env(true))
	root_node.add_child(_cam(Vector3(70, 65, 70), Vector3(-38, 45, 0)))
	_save_scene(root_node, "res://debug/height_field_demo.tscn")


func _build_debug_panel_demo() -> void:
	var root_node := Control.new()
	root_node.name = "DebugPanelDemo"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/debug_panel_demo.gd"))
	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.add_theme_constant_override("separation", 16)
	_full_rect(hbox)
	hbox.offset_left = 16.0
	hbox.offset_top = 16.0
	hbox.offset_right = -16.0
	hbox.offset_bottom = -56.0
	hbox.add_child(_vbox_with_label_rect("VBoxGray", "Grayscale", "GrayRect", Vector2(300, 300)))
	hbox.add_child(_vbox_with_label_rect("VBoxHeight", "Height ramp", "HeightRect", Vector2(300, 300)))
	hbox.add_child(_vbox_with_label_rect("VBoxMoisture", "Moisture ramp", "MoistureRect", Vector2(300, 300)))
	root_node.add_child(hbox)
	var stats := _label("StatsLabel", "")
	_place(stats, 16, 668, 1200, 28)
	root_node.add_child(stats)
	_save_scene(root_node, "res://debug/debug_panel_demo.tscn")


func _build_seed_browser() -> void:
	var root_node := Control.new()
	root_node.name = "SeedBrowser"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/seed_browser.gd"))
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.add_theme_constant_override("separation", 8)
	_place(top, 16, 16, 1248, 40)
	var prev_b := Button.new()
	prev_b.name = "PrevButton"
	prev_b.text = "< Prev"
	var seed_edit := LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.custom_minimum_size = Vector2(180, 0)
	var go_b := Button.new()
	go_b.name = "GoButton"
	go_b.text = "Go"
	var next_b := Button.new()
	next_b.name = "NextButton"
	next_b.text = "Next >"
	var fav_b := Button.new()
	fav_b.name = "FavButton"
	fav_b.text = "★ Favourite"
	top.add_child(prev_b)
	top.add_child(seed_edit)
	top.add_child(go_b)
	top.add_child(next_b)
	top.add_child(fav_b)
	root_node.add_child(top)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 16)
	_place(body, 16, 68, 1248, 556)
	var main_preview := _tex_rect("MainPreview", Vector2(400, 400))
	body.add_child(main_preview)
	var grid := GridContainer.new()
	grid.name = "SeedGrid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	root_node.add_child(body)
	var fav_label := _label("FavLabel", "Favourites: —")
	_place(fav_label, 16, 640, 1200, 28)
	root_node.add_child(fav_label)
	_save_scene(root_node, "res://debug/seed_browser.tscn")


func _build_determinism_test() -> void:
	var root_node := Control.new()
	root_node.name = "DeterminismTest"
	_full_rect(root_node)
	root_node.set_script(_script("res://debug/determinism_test.gd"))
	var output := RichTextLabel.new()
	output.name = "Output"
	_full_rect(output)
	output.offset_left = 16.0
	output.offset_top = 16.0
	output.offset_right = -16.0
	output.offset_bottom = -16.0
	root_node.add_child(output)
	_save_scene(root_node, "res://debug/determinism_test.tscn")
