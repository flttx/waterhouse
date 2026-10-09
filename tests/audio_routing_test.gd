extends SceneTree
## Exercises the production routing helper while the native WASAPI mixer is active.
## Unguarded set_bus_send previously crashed at 0x31d6c57; never run unsafe mode in CI.

var writes: int = 0
var finished: bool = false


func _initialize() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func() -> void:
		if not finished:
			push_error("Audio routing stress did not reach its completion sentinel")
			quit(1))
	call_deferred("_run")


func _run() -> void:
	var sound := WaterhouseSoundscape.new()
	root.add_child(sound)
	sound.music.reset_music()
	sound.set_volume(0.25)
	var index := sound._bus("RoutingRegression", "WorldAir")
	var stream := sound._cue_stream("pump", true)
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = -38.0
	voice.bus = "RoutingRegression"
	root.add_child(voice)
	voice.play()
	await create_timer(0.3).timeout
	var peak := AudioServer.get_bus_peak_volume_left_db(index, 0)
	if peak < -70.0:
		push_error("Routing stress requires an active native mixer, not a silent fixture")
		quit(1)
		return
	for frame in range(600):
		for change in range(5000):
			sound._send(index, "WorldWater" if change % 2 == 0 else "WorldAir")
			writes += 1
		await process_frame
	if writes != 3000000 or AudioServer.get_bus_send(index) != "WorldAir":
		push_error("Routing stress did not complete every real route transition")
		quit(1)
		return
	voice.stop()
	voice.stream = null
	voice.queue_free()
	sound.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	finished = true
	print("AUDIO ROUTING: 3000000 locked production transitions / 0 failures; mixer_peak_db=", peak)
	quit()
