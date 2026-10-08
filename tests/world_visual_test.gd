extends SceneTree
## Native-render environment review; outputs reproducible screenshots without gameplay UI.

var _suffix: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var world := preload("res://scenes/world.tscn").instantiate() as WaterhouseWorld
	if "baseline" in OS.get_cmdline_user_args():
		world.batch_static_boxes = false
		_suffix = "_unbatched"
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.06
	camera.far = 180.0
	world.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	camera.position = Vector3(-21, 2.25, 36)
	camera.look_at(Vector3(6, 4, -27))
	await _capture("res://artifacts/world_start.png")
	camera.position = Vector3(21.0, 2.25, 13)
	camera.look_at(Vector3(20.7, -0.4, -5))
	await _capture("res://artifacts/world_broken_deck.png")
	camera.position = Vector3(0, 4.0, 40)
	camera.look_at(Vector3(0, -0.2, 2))
	await _capture("res://artifacts/world_water.png")
	world.environment.fog_density = 0.055
	world.environment.fog_light_color = Color(0.015, 0.10, 0.115)
	camera.position = Vector3(-8, -4.0, 22)
	camera.look_at(Vector3(-10, -6.1, 16))
	await _capture("res://artifacts/world_underwater.png")
	world.queue_free()
	await process_frame
	quit(0)


func _capture(path: String) -> void:
	for i in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var output_path := path.get_basename() + _suffix + ".png"
	var result := root.get_texture().get_image().save_png(output_path)
	if result != OK:
		push_error("Failed to save world visual evidence: " + output_path)
	else:
		print("WORLD_RENDER_CAPTURE ", output_path)
