extends SceneTree
## Native audio regression: actual sources, world rays, settings UI and retry lifecycle.

var checks: int = 0
var failures: int = 0
var finished: bool = false
var audio_events: Array[String] = []
var damage_sources: Array[Node3D] = []


func _initialize() -> void:
	create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		if not finished:
			push_error("Audio regression timed out before completion")
			quit(1))
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func active(sound: WaterhouseSoundscape, cue: String = "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in sound._voices:
		if (entry["voice"] as AudioStreamPlayer3D).playing and (cue.is_empty() or entry["cue"] == cue):
			found.append(entry)
	return found


func frames(count: int = 3) -> void:
	for frame in range(count):
		await physics_frame


func _run() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await frames()
	var sound: WaterhouseSoundscape = game.soundscape
	var player: PlayerController = game.player
	player.audio_event.connect(func(cue: String) -> void: audio_events.append(cue))
	player.damaged.connect(func(_amount: float, source: Node3D) -> void: damage_sources.append(source))
	expect(sound.cues.size() >= 60, "required v2 sound manifest is loaded")
	expect(sound.music.segment.playing and sound.music.segment_id == "title", "title has real music playback")
	for key: String in ["volume", "sfx_volume", "ambient_volume", "music_volume"]:
		expect(game.settings.has(key), "settings contain " + key)
	for pair: Array in [["volume", "Master"], ["sfx_volume", "SFX"], ["ambient_volume", "Environment"], ["music_volume", "Music"]]:
		var bus := AudioServer.get_bus_index(pair[1])
		sound.set_mix(pair[0], 0.0)
		expect(AudioServer.is_bus_mute(bus), "zero truly mutes " + pair[1])
		sound.set_mix(pair[0], 0.75)
		expect(not AudioServer.is_bus_mute(bus), "positive volume restores " + pair[1])
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") == OK:
		for pair: Array in [["sfx_volume", 1.0], ["ambient_volume", 0.8], ["music_volume", 0.6]]:
			if not saved.has_section_key("preferences", pair[0]):
				expect(is_equal_approx(float(game.settings[pair[0]]), pair[1]), "legacy preferences get default " + pair[0])
	game.start_run()
	game._set_enemies_enabled(false)
	await frames()
	expect(sound.music.stems.playing, "game starts synchronized score")
	expect(sound._voices.size() + sound._ui_voices.size() == 32, "instant sound pool has a fixed 32 voice budget")
	var previous := ""
	var varied := true
	for sample in range(12):
		var stream := sound._cue_stream("step_metal")
		var path := stream.resource_path
		# Duplicated streams keep source provenance in the choice cache.
		var chosen := str(sound._last_variant.get("step_metal", ""))
		var identity := chosen if not chosen.is_empty() else path
		varied = varied and identity != previous
		previous = identity
	expect(varied, "frequent footsteps never repeat the same variant consecutively")
	for group: String in ["main_hall", "filter_corridor", "pump_room", "archives", "reservoir", "egress"]:
		sound._update_rooms(2.0, group)
		var total := 0.0
		for gain: float in sound.room_mix:
			total += gain
		expect(absf(total - 1.0) < 0.01, "region crossfade preserves mix weight: " + group)
	sound._update_rooms(2.0, "main_hall")
	sound._update_rooms(0.5, "archives")
	expect(sound.room_mix[0] > 0.0 and sound.room_mix[3] > 0.0, "region transition overlaps two real ambience streams")
	sound._update_medium(0.25, true)
	expect(sound.underwater_mix > 0.0 and sound.underwater_mix < 1.0, "water entry interpolates rather than snapping")
	sound._update_medium(0.5, true)
	expect((sound._filters["WorldAir"] as AudioEffectLowPassFilter).cutoff_hz < 1000.0, "airborne sounds are muffled underwater")
	expect((sound._filters["WorldWater"] as AudioEffectLowPassFilter).cutoff_hz > 9000.0, "waterborne threats retain audible detail underwater")
	sound._update_medium(0.5, false)
	var creature: Node3D = game.enemies[0]
	var original := creature.global_position
	sound.creature_event(creature, "omen", 0.8)
	var voices := active(sound, "leviathan_omen")
	expect(voices.size() == 1, "real creature emits species-specific positional omen")
	sound.creature_event(creature, "omen", 0.8)
	expect(active(sound, "leviathan_omen").size() == 1, "same creature respects omen cooldown")
	sound.creature_event(game.enemies[1], "omen", 0.8)
	expect(active(sound).size() >= 2, "another creature has an independent omen cooldown")
	creature.global_position += Vector3(3, 0, 0)
	sound._update_voices(0.1)
	if not voices.is_empty():
		expect((voices[0]["voice"] as Node3D).global_position.is_equal_approx(creature.global_position), "moving creature sound follows its actual source")
	creature.global_position = original
	sound.creature_event(creature, "windup")
	expect(sound.music.state == "danger", "attack windup immediately raises score danger")
	expect(active(sound, "leviathan_hit").is_empty(), "attack windup does not fake an impact")
	player.take_damage(1.0, "audio regression", creature)
	expect(damage_sources.back() == creature and active(sound, "leviathan_hit").size() == 1, "actual damage carries its source and plays its hit cue")
	var noise_before := player.noise_level
	sound.set_mix("sfx_volume", 0.0)
	expect(player.noise_level == noise_before, "audio mute does not modify gameplay noise")
	sound.set_mix("sfx_volume", 0.75)
	sound.set_mix("ambient_volume", 0.0)
	sound.one_shot("metal", -14.0, player.camera.global_position + Vector3(1, 0, 0))
	voices = active(sound, "metal")
	expect(voices.size() == 1 and AudioServer.get_bus_send(int(voices[0]["bus"])) == "WorldAir", "decoy impact belongs to world effects rather than ambience")
	expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("Environment")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "ambient mute preserves active decoy effect routing")
	sound.set_mix("ambient_volume", 0.8)
	# A real static wall, ray and listener exercise occlusion in the native world.
	game.start_run()
	game._set_enemies_enabled(false)
	await frames()
	var wall := StaticBody3D.new()
	wall.position = player.camera.global_position + Vector3(1.5, 0, 0)
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 4, 4)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	await frames()
	sound.one_shot("stress", -12.0, player.camera.global_position + Vector3(3, 0, 0))
	sound._update_occlusion()
	voices = active(sound, "stress")
	expect(not voices.is_empty() and voices[0]["occluded"], "real wall occludes the positional cue")
	if not voices.is_empty():
		await create_timer(0.35).timeout
		expect((voices[0]["filter"] as AudioEffectLowPassFilter).cutoff_hz < 2000.0 and float(voices[0]["occlusion_mix"]) > 0.9, "blocked source smoothly applies its real low-pass filter")
	wall.queue_free()
	await frames()
	sound._update_occlusion()
	voices = active(sound, "stress")
	expect(not voices.is_empty() and not voices[0]["occluded"], "removing the wall restores direct sound")
	for index in range(50):
		sound.one_shot("drip", -24.0, player.camera.global_position + Vector3(index + 2, 0, 0))
	expect(active(sound).size() <= 28, "dense decoration cannot allocate beyond the world pool")
	sound.one_shot("breath_low", -12.0)
	expect(active(sound, "breath_low").size() == 1, "critical oxygen sound survives pool pressure")
	expect(sound.music.duck_remaining > 0.0, "critical sound ducks the score")
	sound._update_occlusion()
	expect(sound.occlusion_checks <= 8, "occlusion uses at most eight rays per update")
	sound.one_shot("valve", -14.0, player.camera.global_position)
	sound.stop_cue("valve")
	expect(active(sound, "valve").is_empty(), "stopping interaction ends its mechanical cue")
	game.pause_run()
	await frames()
	expect(sound.music.stems.stream_paused, "pause freezes score playback")
	sound.player_event("ui_confirm")
	var ui_active := false
	for voice: AudioStreamPlayer in sound._ui_voices:
		ui_active = ui_active or (voice.playing and not voice.stream_paused)
	expect(ui_active, "menu feedback remains available during pause")
	game.resume_run()
	game.open_map()
	expect(sound.music.stems.stream_paused, "map freezes the score too")
	game.close_map()
	expect(not sound.music.stems.stream_paused, "closing the map resumes the score")
	var node_count := sound.get_child_count()
	for retry in range(10):
		game.start_run()
		game._set_enemies_enabled(false)
		expect(sound.music.stems.playing and sound.music.cue_counts.is_empty(), "retry %d starts a fresh score timeline" % retry)
		expect(active(sound).is_empty() and not sound.pump_voice.playing and sound.get_child_count() == node_count, "retry %d clears sources without accumulating nodes" % retry)
	player.enabled = false
	player.velocity = Vector3(3.8, 0, 0)
	sound.step_clock = 0.0
	sound._update_movement(player)
	expect(active(sound).is_empty(), "frozen character does not produce fake footsteps during gate animation")
	player.enabled = true
	player.velocity = Vector3.ZERO
	game.enemy_threats[creature.get_instance_id()] = 0.95
	game.threat = 0.95
	sound.music.cue_event("windup")
	game.stage = 7
	game._refresh_devices()
	game.devices["exit"].operate(100.0)
	expect(game.threat == 0.0 and game.enemy_threats.is_empty(), "actual gate activation clears disabled enemies' stale threat")
	expect(sound.music.state == "calm" and sound.music.segment_id == "egress", "actual safe exit can release its score during door animation")
	game._on_death("audio regression")
	expect(active(sound).is_empty() and not sound.water.playing, "death stops all world sources")
	expect(sound.music.segment_id == "dead" and sound.music.segment.playing, "death keeps its terminal music")
	game.start_run()
	game._set_enemies_enabled(false)
	player.take_damage(100.0, "fatal audio regression", creature)
	var terminal_impact := false
	for voice: AudioStreamPlayer in sound._ui_voices:
		terminal_impact = terminal_impact or voice.playing
	expect(game.flow == game.Flow.DEAD and active(sound).is_empty() and terminal_impact, "fatal real hit survives old world cleanup as one body impact")
	await create_timer(1.2).timeout
	terminal_impact = false
	for voice: AudioStreamPlayer in sound._ui_voices:
		terminal_impact = terminal_impact or voice.playing
	expect(not terminal_impact, "fatal impact finishes without leaving a looping death source")
	game.start_run()
	game._set_enemies_enabled(false)
	game.exit_started = true
	game._on_win()
	expect(sound.music.segment_id == "won" and sound.music.segment.playing, "victory plays the release segment")
	paused = false
	game.queue_free()
	await frames()
	await create_timer(0.2).timeout
	finished = true
	print("AUDIO: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
