extends Node3D

## Capstone clearance: instance the REAL stage_9_world at step 6
## (the world_check.tscn pattern), let it build, then run
## audit_clearance.gd's identical measurement over the world
## builder's network and terrain. The capstone terrain is
## noise-backed with city edits registered on it, so
## terrain.height_at IS the surface truth here (base + edits) —
## ribbon corner heights and terrain samples both read it, exactly
## as RoadBuilder's facet_height() does on this field.
## Output: CAPSTONE_CLEARANCE_JSON block + /tmp/clearance_capstone.json

const AuditClearance := preload("res://tools/audit_clearance.gd")


func _ready() -> void:
	var packed: PackedScene = load("res://stages/stage_9_world.tscn")
	var stage: Node = packed.instantiate()
	add_child(stage)
	await get_tree().create_timer(2.0).timeout
	var builder: WorldBuilder = stage.builder
	if builder == null or builder.network == null or builder.terrain == null:
		push_error("capstone clearance: builder/network/terrain missing")
		get_tree().quit()
		return
	print("capstone clearance: build complete, measuring ...")
	var report: Dictionary = AuditClearance.measure(
		builder.network, builder.terrain)
	report["step"] = "capstone_6"
	report["city_edits"] = builder.terrain.city_edit_count()
	report["stage_times"] = builder.stage_times
	var total_ms: int = 0
	for k in builder.stage_times.keys():
		total_ms += int(builder.stage_times[k])
	report["build_ms_total_stages"] = total_ms
	var text: String = JSON.stringify(report, "  ")
	print("CAPSTONE_CLEARANCE_JSON_BEGIN")
	print(text)
	print("CAPSTONE_CLEARANCE_JSON_END")
	var f := FileAccess.open("/tmp/clearance_capstone.json",
		FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	get_tree().quit()
