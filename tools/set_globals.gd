extends SceneTree
## One-off setup (Part III worker): register Ch19 §19.2's shader
## globals in project settings, exactly as the editor's
## Project Settings -> Rendering -> Shader Globals panel would.
func _init() -> void:
	ProjectSettings.set_setting("shader_globals/wind_strength", {"type": "float", "value": 0.35})
	ProjectSettings.set_setting("shader_globals/wind_direction", {"type": "vec2", "value": Vector2(0.84, 0.54)})
	var err: Error = ProjectSettings.save()
	print("GLOBALS_SAVED err=", err)
	print("wind_strength=", ProjectSettings.get_setting("shader_globals/wind_strength"))
	print("wind_direction=", ProjectSettings.get_setting("shader_globals/wind_direction"))
	quit(0)
