extends SceneTree
## Render through the actual GPU viewport; never use --headless for this tool.
var game: Node3D


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for i in 35:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("title.png")
	game.start_run()
	game.creature.enabled = false
	game.player.enabled = false
	game.hud.tutorial.visible = false
	game.elapsed = 120.0
	game.hud.notice_time = 0.0
	game.player.reset_at(Vector3(-21, 0.72, 28))
	game.player.rotation.y = -0.95
	game.player.camera.look_at(Vector3(5, 0.8, -18))
	for i in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("waterhouse.png")
	game.player.reset_at(Vector3(-4, -5, 14))
	game.player.camera.look_at(Vector3(-10, -6, 16))
	game.player.in_water = true
	game.player.submerged = true
	game.creature.global_position = Vector3(8, -6, -4)
	game.creature.visible = true
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("underwater.png")
	game.player.reset_at(Vector3(-5.5, -6.6, -3))
	game.player.camera.look_at(Vector3(0, -5, -5))
	game.player.in_water = true
	game.player.submerged = true
	game.creature.global_position = Vector3(0, -5.0, -5)
	game.creature.rotation.y = 0.0
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("leviathan.png")
	game.player.reset_at(Vector3(1.4, 0.72, -45.4))
	game.player.camera.look_at(Vector3(0, 2.0, -55.5))
	game.gate.position.y = 7.6
	game.gate.collision_layer = 0
	game.exit_started = true
	for i in 35:
		await process_frame
	await RenderingServer.frame_post_draw
	_save("escape_passage.png")
	print("GPU monitors: %d FPS / %d draw calls / %d visible objects" % [int(Performance.get_monitor(Performance.TIME_FPS)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	print("GPU CAPTURE COMPLETE")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()


func _save(filename: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png("res://artifacts/" + filename)
	if error != OK:
		push_error("Unable to save capture: " + error_string(error))
	else:
		print("Saved " + filename)
