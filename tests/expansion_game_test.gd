extends SceneTree
## Difficulty and map lifecycle run against the complete native game.
var failures: int = 0
var checks: int = 0
var reached_end: bool = false


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	create_timer(40.0, true, false, true).timeout.connect(func() -> void:
		push_error("Expansion game watchdog: final sentinel missing")
		quit(1))
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)


func run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	check(game.devices.size() == 10, "expanded objective contract has ten native devices")
	check(game.world.map_regions.size() == 19 and game.world.water_regions.size() == 10, "map describes nineteen real regions and ten water volumes")
	check(game.world.ladders.size() == 16, "all sixteen real climb exits remain available")
	var kinds: Dictionary = {}
	for enemy: CharacterBody3D in game.enemies:
		kinds[enemy.get_meta("species")] = true
		check(not bool(enemy.get("enabled")), "title freezes " + enemy.name)
	check(game.enemies.size() == 9 and kinds.size() == 8, "nine runtime actors represent eight different species")
	var expected := {"exploration": [100.0, 5, "map"], "survival": [60.0, 3, "direction"], "abyss": [45.0, 2, "hidden"]}
	for key: String in WaterhouseDifficulty.KEYS:
		game.selected_difficulty = key
		game.hud.set_difficulty(key)
		game.start_run()
		check(game.run_difficulty == key, key + " applies on new run")
		check(game.player.breath_seconds == expected[key][0] and game.decoys == expected[key][1], key + " sets breath and inventory")
		var all_active := true
		for enemy: CharacterBody3D in game.enemies:
			all_active = all_active and bool(enemy.get("enabled"))
		check(all_active, key + " retains every actual enemy AI")
		game._set_enemies_enabled(false)
		await physics_frame
		game._update_guidance()
		check(game.hud.navigation_mode == expected[key][2], key + " matches reference navigation mode")
		check(game.hud.mission.visible == (key != "abyss"), key + " enforces objective visibility")
		var fixed_key: String = game.run_difficulty
		game._on_difficulty_changed("abyss" if key != "abyss" else "exploration")
		check(game.run_difficulty == fixed_key and game.selected_difficulty == key, "active run cannot mutate difficulty from menu signal")
	game.selected_difficulty = "survival"
	game.hud.set_difficulty("survival")
	game.start_run()
	game._set_enemies_enabled(false)
	await physics_frame
	var original_elapsed: float = game.elapsed
	var original_position: Vector3 = game.player.global_position
	game.open_map()
	check(game.flow == game.Flow.MAP and paused and game.hud.current_page == "map", "map opens with native tree paused")
	game._process(5.0)
	check(game.elapsed == original_elapsed and game.player.global_position == original_position, "map freezes clock and player position")
	game.close_map()
	check(game.flow == game.Flow.PLAYING and not paused and game.hud.current_page == "game", "map close returns to unpaused gameplay")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "windowed map close recaptures the mouse")
	game.pause_run()
	game.open_map()
	game.close_map()
	check(game.flow == game.Flow.PAUSED and paused and game.hud.current_page == "pause", "map opened from pause returns to pause")
	game.resume_run()
	game.devices["breaker"].operate(7.0)
	var markers: Array[Dictionary] = game.get_map_markers()
	var completed_markers := 0
	var current_markers := 0
	for marker: Dictionary in markers:
		completed_markers += 1 if marker["completed"] else 0
		current_markers += 1 if marker["current"] else 0
	check(markers.size() == 10 and completed_markers == 1 and current_markers == 1, "map tracks real completed and nearest active objective")
	game.player.take_damage(200.0, "测试失败条件")
	var all_stopped := true
	for enemy: CharacterBody3D in game.enemies:
		all_stopped = all_stopped and not bool(enemy.get("enabled"))
	check(game.flow == game.Flow.DEAD and all_stopped, "death freezes all nine enemies")
	game.start_run()
	check(game.stage == 0 and game.outer_valves_closed == 0 and game.devices["archive"].progress == 0.0, "restart clears expanded objective state")
	check(WaterhouseDifficulty.profile("corrupt")["breath_seconds"] == 60.0, "invalid saved difficulty uses validated survival defaults")
	game._set_enemies_enabled(false)
	game.player.enabled = false
	reached_end = true
	game.queue_free()
	await process_frame
	await create_timer(0.3, true, false, true).timeout
	check(reached_end, "expansion lifecycle reached final sentinel")
	print("EXPANSION GAME: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
