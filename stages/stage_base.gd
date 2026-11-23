@tool
class_name StageBase
extends Node3D
## Reusable stage framework for every stage scene in the book project.
## See stages/README.md — later stage builders follow that pattern exactly.
##
## A stage scene that uses this framework has this fixed node layout:
##
##   <StageRoot>            (script extends StageBase, @tool)
##   ├── DirectionalLight3D (fixed sun, shadows on)
##   ├── WorldEnvironment   (ProceduralSky, ACES tonemap)
##   ├── CameraRig (Node3D)
##   │   └── PresetCamera (Camera3D, current = true)  ← the named camera preset
##   ├── Generated (Node3D) ← build_step() puts ALL generated nodes here
##   └── DebugUI (CanvasLayer)
##       └── PanelContainer/VBoxContainer: SeedField, StepSpin, RegenButton, InfoLabel
##
## Exports (set in the Inspector — this is what ENGINE screenshots show):
##   step        — which build step to show; changing it rebuilds live (@tool)
##   master_seed — the world seed; changing it rebuilds live (@tool)
##
## Subclasses override build_step() ONLY. They read `config` (a WorldConfig
## whose master_seed matches the export) and add nodes under `generated_root`.
## Generation is data-first and deterministic: all randomness comes from
## SeedBank streams via config.stream() / config.noise().

@export var step: int = 0:
	set(value):
		step = value
		if is_inside_tree() and is_node_ready():
			_sync_config()
			rebuild()

@export var master_seed: int = 20261119:
	set(value):
		master_seed = value
		if is_inside_tree() and is_node_ready():
			_sync_config()
			rebuild()

## The camera preset every screenshot of this stage uses. Subclasses may
## override the VALUES in their scene, never the node names.
const CAMERA_PRESET_POSITION := Vector3(0.0, 40.0, 58.0)
const CAMERA_PRESET_ROTATION_DEGREES := Vector3(-34.0, 0.0, 0.0)
## Second named preset: a low oblique "shoreline" view, for stages whose
## subject reads better near ground level. Select it in captures with
## book_capture's --camera=low. The default preset stays "preset".
const CAMERA_PRESET_LOW_POSITION := Vector3(0.0, 11.0, 44.0)
const CAMERA_PRESET_LOW_ROTATION_DEGREES := Vector3(-12.0, 0.0, 0.0)

var config: WorldConfig

@onready var generated_root: Node3D = $Generated
@onready var preset_camera: Camera3D = $CameraRig/PresetCamera


func _ready() -> void:
	_sync_config()
	apply_camera_preset()
	_wire_debug_ui()
	rebuild()


func _sync_config() -> void:
	if config == null:
		config = WorldConfig.new()
	config.master_seed = master_seed


## Fixed camera rig: every capture of a stage uses exactly this framing,
## so renders are comparable across steps, chapters, and machines.
func apply_camera_preset() -> void:
	apply_camera_preset_by_name("preset")


## Named camera presets: "preset" (the default aerial) or "low".
func apply_camera_preset_by_name(preset_name: String) -> void:
	var cam: Camera3D = get_node_or_null("CameraRig/PresetCamera") as Camera3D
	if cam == null:
		return
	if preset_name == "low":
		cam.position = CAMERA_PRESET_LOW_POSITION
		cam.rotation_degrees = CAMERA_PRESET_LOW_ROTATION_DEGREES
	else:
		cam.position = CAMERA_PRESET_POSITION
		cam.rotation_degrees = CAMERA_PRESET_ROTATION_DEGREES
	cam.current = true


## Clear Generated and rebuild the current step. Safe to call any time.
func rebuild() -> void:
	if generated_root == null:
		generated_root = get_node_or_null("Generated") as Node3D
	if generated_root == null:
		return
	for child in generated_root.get_children():
		generated_root.remove_child(child)
		child.free()
	build_step(step)
	_update_info_label()


## Override in subclasses: build step `p_step` under generated_root.
func build_step(_p_step: int) -> void:
	pass


# --- Debug UI (runtime only; in the editor the Inspector is the UI) ---

func _wire_debug_ui() -> void:
	if Engine.is_editor_hint():
		return
	var seed_field: LineEdit = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/SeedField") as LineEdit
	if seed_field != null:
		seed_field.text = str(master_seed)
	var step_spin: SpinBox = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/StepSpin") as SpinBox
	if step_spin != null:
		step_spin.value = float(step)
		step_spin.value_changed.connect(_on_step_spin_changed)
	var regen: Button = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/RegenButton") as Button
	if regen != null:
		regen.pressed.connect(_on_regenerate_pressed)


func _update_info_label() -> void:
	if Engine.is_editor_hint():
		return
	var info: Label = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/InfoLabel") as Label
	if info != null:
		info.text = "Seed %d · Step %d" % [master_seed, step]
	var step_spin: SpinBox = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/StepSpin") as SpinBox
	if step_spin != null:
		step_spin.set_value_no_signal(float(step))


func _on_step_spin_changed(value: float) -> void:
	step = int(value)


func _on_regenerate_pressed() -> void:
	var seed_field: LineEdit = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/SeedField") as LineEdit
	if seed_field != null and seed_field.text.is_valid_int():
		master_seed = int(seed_field.text)
	var step_spin: SpinBox = get_node_or_null("DebugUI/PanelContainer/VBoxContainer/StepSpin") as SpinBox
	if step_spin != null:
		step = int(step_spin.value)
	rebuild()
