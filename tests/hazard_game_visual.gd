extends SceneTree
## Frozen visual QA in the actual main scene and the actual player's flashlight.
## This deliberately relocates the Hunter; it is not a playthrough/AI test.

var _failures: int = 0
var _finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			push_error("HAZARD GAME VISUAL WATCHDOG")
			quit(2))
	root.mode = Window.MODE_MINIMIZED
	AudioServer.set_bus_mute(0, true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	viewport.add_child(game)
	await process_frame
	game.call("_set_enemies_enabled", false)
	game.set("flow", 0)
	var player := game.get("player") as PlayerController
	player.enabled = false
	player.set_physics_process(false)
	var hud := game.get("hud") as WaterhouseHUD
	hud.menu.hide()
	hud.interface.hide()
	hud.effect.set_shader_parameter("underwater", 1.0)
	hud.effect.set_shader_parameter("injury", 0.0)
	var world := game.get("world") as WaterhouseWorld
	for species in ["hunter", "lurker"]:
		var enemy: WaterhouseHazard
		for candidate: CharacterBody3D in game.get("enemies"):
			if str(candidate.get_meta("species")) == species:
				enemy = candidate as WaterhouseHazard
				break
		if enemy == null:
			_failures += 1
			push_error("Missing real game species: " + species)
			continue
		if species == "hunter":
			enemy.home = Vector3(-32.0, -3.0, -83.0)
			enemy.reset_creature()
			enemy.rotation.y = -PI / 2.0
		var eye_position := enemy.global_position + (Vector3(6.0, 0.0, 0.75) if species == "hunter" else Vector3(0.5, 0.0, -4.0))
		player.reset_at(eye_position - Vector3.UP * PlayerController.STANDING_EYE)
		player._update_camera(1.0, false)
		player.camera.look_at(enemy.global_position)
		player.camera.make_current()
		game.call("_update_environment", 1.0)
		var frozen := enemy.global_position
		for frame in 24:
			await process_frame
		RenderingServer.force_draw(false)
		var output: String = "res://artifacts/" + str(species) + "_in_game.png"
		var result := viewport.get_texture().get_image().save_png(output)
		var valid := result == OK and player.submerged and player.light_on and player._flashlight.visible and player.camera.is_current() and enemy.global_position == frozen and not enemy.enabled
		if not valid:
			_failures += 1
			push_error("Invalid in-game frozen visual fixture: " + species)
		print("HAZARD REAL VIEW ", species, " result=", result, " camera=", player.camera.global_position, " creature=", enemy.global_position, " fog=", world.environment.fog_density, " flashlight=", player._flashlight.light_energy)
	game.set("flow", 0)
	for node in game.find_children("*", "", true, false):
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
			(node as AudioStreamPlayer).stream = null
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stop()
			(node as AudioStreamPlayer3D).stream = null
	await create_timer(0.25, true, false, true).timeout
	viewport.queue_free()
	await process_frame
	await process_frame
	_finished = true
	print("HAZARD_GAME_VISUAL_REACHED_FINAL failures=", _failures)
	quit(1 if _failures else 0)
