extends Node3D
## The book's stage + debug bench. Holds the WorldConfig, and (from
## Chapter 2) the debug UI: a seed field and a Regenerate button.
## Later parts plug their generators into regenerate() — the bench
## itself never changes shape again.

@export var master_seed: int = 20261119

var config: WorldConfig

@onready var stage: Node3D = $Stage
@onready var seed_field: LineEdit = $DebugUI/PanelContainer/VBoxContainer/SeedField
@onready var stream_label: Label = $DebugUI/PanelContainer/VBoxContainer/StreamLabel


func _ready() -> void:
	config = WorldConfig.new()
	config.master_seed = master_seed
	seed_field.text = str(config.master_seed)
	regenerate()


func regenerate() -> void:
	# Stream-isolation proof, printed to the Output panel:
	# terrain draws -> plants goes on a 1,000-draw adventure -> terrain again.
	var terrain := SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TERRAIN)
	var first_five: Array[int] = []
	for i in 5:
		first_five.append(terrain.randi_range(0, 999999))

	var plants := SeedBank.stream_for(config.master_seed, SeedBank.STREAM_PLANTS)
	for i in 1000:
		plants.randf()

	var terrain_again := SeedBank.stream_for(config.master_seed, SeedBank.STREAM_TERRAIN)
	var second_five: Array[int] = []
	for i in 5:
		second_five.append(terrain_again.randi_range(0, 999999))

	print("Seed ", config.master_seed, " terrain stream: ", first_five)
	print("After 1,000 plants draws, terrain stream: ", second_five)
	print("Isolated: ", first_five == second_five)
	stream_label.text = "Terrain stream stable: %s" % str(first_five == second_five)


func _on_regen_button_pressed() -> void:
	var typed: int = int(seed_field.text)
	config.master_seed = typed
	master_seed = typed
	regenerate()
