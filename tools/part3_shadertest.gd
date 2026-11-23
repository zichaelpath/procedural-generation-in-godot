extends SceneTree
func _init() -> void:
	for path in ["res://plants/wind_bend.gdshader", "res://plants/leaf_wind.gdshader"]:
		var sh: Shader = load(path) as Shader
		var mat := ShaderMaterial.new()
		mat.shader = sh
		print("MADE material for ", path, " code_len=", sh.code.length())
	print("SHADERTEST done")
	quit(0)
