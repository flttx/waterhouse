extends SceneTree
## Integration regression: real scenes and signals; no external test framework.
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Game flow test timed out")
		quit(1))
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	expect(game.flow == game.Flow.TITLE, "title starts without simulation")
	expect(not game.player.enabled and not game.creature.enabled, "menu disables both actors")
	expect(game.devices.size() == 10, "all ten physical escape devices exist")
	expect(game.enemies.size() == 9, "nine actors from eight distinct species exist")
	expect(game.soundscape.air.stream != null, "offline audio asset loaded")
	expect(game.soundscape.air.stream.loop_mode != 0, "facility ambience loops")
	expect(game.soundscape.water.stream.loop_mode != 0, "underwater ambience loops")
	game.selected_difficulty = "survival"
	game.start_run()
	game._set_enemies_enabled(false)
	expect(game.flow == game.Flow.PLAYING and game.stage == 0, "start creates fresh escape run")
	expect(game.player.enabled and game.player.health == 100.0, "start restores player")
	expect(game.devices["breaker"].available, "breaker is first objective")
	game.devices["pump"].operate(100.0)
	expect(not game.devices["pump"].completed and game.stage == 0, "locked pump cannot skip objectives")
	game.devices["exit"].operate(100.0)
	expect(not game.exit_started, "locked gate cannot trigger escape")
	game.devices["breaker"].operate(1.0)
	expect(not game.devices["breaker"].completed, "device requires sustained operation")
	game.devices["breaker"].operate(6.0)
	expect(game.stage == 1, "breaker signal unlocks underwater valves")
	expect(game.devices["valve_south"].available and game.devices["valve_north"].available, "both diving routes are available")
	game.devices["valve_north"].operate(12.1)
	expect(game.stage == 1 and game.valves_closed == 1, "one valve alone cannot unlock pump")
	game.devices["valve_north"].operate(50.0)
	expect(game.valves_closed == 1, "completed valve cannot increment twice")
	game.devices["valve_south"].operate(12.1)
	expect(game.stage == 2 and game.devices["archive"].available, "both main valves unlock archive interlock")
	game.devices["pump"].operate(100.0)
	expect(not game.devices["pump"].completed, "expanded interlocks prevent an early pump start")
	game.devices["archive"].operate(6.1)
	expect(game.stage == 3 and game.devices["annex_valve"].available, "archive unlocks filter regulation")
	game.devices["annex_valve"].operate(10.1)
	expect(game.stage == 4, "filter regulation unlocks three outer pools")
	game.devices["tier_valve"].operate(10.1)
	game.devices["overflow_valve"].operate(10.1)
	expect(game.stage == 4 and not game.devices["pump"].available, "two outer valves cannot skip the reservoir")
	game.devices["reservoir_valve"].operate(10.1)
	expect(game.stage == 5 and game.devices["pump"].available, "all three outer valves unlock pump")
	game.devices["pump"].operate(8.1)
	expect(game.stage == 6 and game.creature.pressure == 1.0, "pump raises encounter pressure")
	expect(game.soundscape.pump_voice.playing, "pump produces positional sound")
	game.pause_run()
	var frozen_time: float = game.elapsed
	var frozen_pressure: float = game.purge_remaining
	game._process(10.0)
	expect(game.elapsed == frozen_time and game.purge_remaining == frozen_pressure, "pause freezes escape timers")
	expect(paused and game.hud.current_page == "pause", "pause freezes native scene tree and focuses menu")
	game.resume_run()
	game._set_enemies_enabled(false)
	expect(not paused and game.flow == game.Flow.PLAYING, "resume restores game")
	game._process(86.0)
	expect(game.stage == 7 and game.devices["exit"].available, "pressure timer unlocks north exit")
	game.devices["exit"].operate(5.1)
	expect(game.exit_started and not game.player.enabled, "gate opening begins ending safely")
	game.start_run()
	game._set_enemies_enabled(false)
	expect(not game.gate_tween.is_valid(), "restart cancels an earlier gate animation")
	game.stage = 7
	game._refresh_devices()
	game.devices["exit"].operate(5.1)
	game._on_gate_opened()
	expect(game.flow == game.Flow.PLAYING and game.player.enabled, "opening alone does not complete escape")
	game.player.global_position = Vector3(0, 0.7, -54)
	game._physics_process(0.016)
	expect(game.flow == game.Flow.WON and game.hud.current_page == "won", "escape ending shown")
	game.start_run()
	game._set_enemies_enabled(false)
	expect(game.stage == 0 and game.valves_closed == 0 and game.decoys == 3, "retry clears objective and inventory state")
	expect(not game.devices["exit"].completed and not game.exit_started, "retry clears exit state")
	game.player.take_damage(200.0, "测试死亡")
	expect(game.flow == game.Flow.DEAD and game.hud.current_page == "dead", "real death signal displays retry screen")
	expect(not game.creature.enabled and not game.player.enabled, "death disables gameplay")
	game.start_run()
	game._set_enemies_enabled(false)
	expect(game.player.health == 100.0 and game.player.oxygen == 100.0, "death retry restores health and breath")
	game._throw_decoy()
	expect(game.decoys == 2 and get_nodes_in_group("decoys").size() == 1, "decoy uses real native projectile")
	game._throw_decoy()
	game._throw_decoy()
	game._throw_decoy()
	expect(game.decoys == 0 and get_nodes_in_group("decoys").size() == 3, "decoy stock cannot underflow")
	game.player.enabled = false
	game._set_enemies_enabled(false)
	print("GAME FLOW: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await process_frame
	# Native audio cleanup is committed on a mixer tick, not a rendered frame.
	await create_timer(0.2).timeout
	quit(1 if failures else 0)
