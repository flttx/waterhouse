extends SceneTree
## Renders an isolated bent pose for art QA, without launching the game flow.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_MINIMIZED
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.065, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.45, 0.5)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -25.0, 0.0)
	light.light_color = Color(0.68, 0.83, 0.85)
	light.light_energy = 2.5
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(19.0, 8.0, 8.0)
	camera.look_at(Vector3(1.0, -3.0, 0.0))
	camera.fov = 58.0
	camera.current = true
	var creature := (load("res://scenes/leviathan.tscn") as PackedScene).instantiate() as WaterhouseCreature
	world.add_child(creature)
	creature.global_position = Vector3(0.0, -3.0, -10.0)
	creature._heading = Vector3.FORWARD
	creature._history.clear()
	for sample in 100:
		var distance := float(sample) * 0.3
		creature._history.append(creature.global_position + Vector3(3.8 * sin(distance / 11.0), 0.0, distance))
	creature._pose_body()
	for frame in 8:
		await process_frame
	RenderingServer.force_draw(false)
	var screenshot := viewport.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		push_error("No rendering device available for the creature visual check")
		quit(2)
		return
	var output := "res://artifacts/creature_preview.png"
	var result := screenshot.save_png(output)
	print("CREATURE VISUAL: ", output, " result=", result)
	quit(0 if result == OK else 1)
