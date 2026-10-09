extends SceneTree
## A scripted real-mixer preview, plus actual settings UI captures at two resolutions.

var failures: int = 0
var complete: bool = false


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		if not complete:
			push_error("Audio capture timed out")
			quit(1))
	call_deferred("_run")


func wait_real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await wait_real(0.3)
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		game.hud.show_page("settings")
		await wait_real(0.2)
		var sliders: Array[Node] = game.hud.menu.find_children("*_slider", "HSlider", true, false)
		if sliders.size() != 6:
			failures += 1
			push_error("Settings must expose six keyboard-accessible sliders")
		for slider: HSlider in sliders:
			if not Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(slider.get_global_rect()):
				failures += 1
				push_error("Settings slider clips outside viewport: " + slider.name)
		var focused := root.gui_get_focus_owner()
		if focused == null or focused.name != "brightness_slider":
			failures += 1
			push_error("Settings must initially focus the first interactive control")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := "res://artifacts/audio_settings_%dx%d.png" % [dimensions.x, dimensions.y]
			if root.get_texture().get_image().save_png(path) != OK:
				failures += 1
				push_error("Settings capture failed")
	game.hud.show_page("title")
	var master := AudioServer.get_bus_index("Master")
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(master, recorder)
	var effect_index := AudioServer.get_bus_effect_count(master) - 1
	game.soundscape.set_mix("volume", 0.75)
	game.soundscape.set_mix("sfx_volume", 1.0)
	game.soundscape.set_mix("ambient_volume", 0.8)
	game.soundscape.set_mix("music_volume", 0.6)
	recorder.set_recording_active(true)
	await wait_real(3.0)
	game.start_run()
	game._set_enemies_enabled(false)
	Input.action_press("move_forward")
	await wait_real(2.0)
	Input.action_release("move_forward")
	player_event(game, "climb_start")
	await wait_real(0.7)
	player_event(game, "climb_end")
	game.player.reset_at(Vector3(-10, -5, 16))
	game.player.enabled = false
	player_event(game, "splash")
	player_event(game, "dive")
	await wait_real(6.0)
	game.player.oxygen = 15.0
	await wait_real(4.0)
	var creature: Node3D = game.enemies[0]
	creature.global_position = game.player.global_position + Vector3(5, 0, 0)
	creature.emit_signal("omen", creature.global_position, 0.85)
	await wait_real(3.0)
	creature.emit_signal("attack_started")
	game.threat = 0.85
	await wait_real(4.0)
	game.player.reset_at(Vector3(-21, 0.72, -25))
	game.player.enabled = false
	player_event(game, "surface")
	game.threat = 0.0
	await wait_real(3.0)
	game.stage = 6
	game.purge_remaining = 25.0
	game.soundscape.start_pump(game.devices["pump"].global_position)
	await wait_real(5.0)
	game.stage = 7
	game.soundscape.one_shot("pressure_ready", -10.0)
	game.soundscape.music.cue_event("egress")
	await wait_real(3.0)
	game.exit_started = true
	game._on_win()
	await wait_real(6.0)
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	if recording == null or recording.get_length() < 35.0 or recording.save_to_wav("res://artifacts/audio-mix-preview.wav") != OK:
		failures += 1
		push_error("Native mixer did not produce the complete audition recording")
	else:
		print("AUDIO_CAPTURE real_mixer_seconds=", recording.get_length(), " rate=", recording.mix_rate)
	AudioServer.remove_bus_effect(master, effect_index)
	game.queue_free()
	await wait_real(0.3)
	complete = true
	print("AUDIO CAPTURE: %d failures" % failures)
	quit(1 if failures else 0)


func player_event(game: Node3D, cue: String) -> void:
	game.player.audio_event.emit(cue)
