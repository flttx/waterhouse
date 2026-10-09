extends SceneTree
## Verifies actual Music playback and the threat/mission state contract.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		push_error("Music test timed out")
		quit(1))
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func context(music: WaterhouseMusicDirector, seconds: float, threat: float = 0.0, submerged: bool = false, stage: int = 0, progress: float = 0.0, region: String = "main_hall") -> void:
	music.update_context(seconds, threat, submerged, stage, progress, region)
	music._advance(seconds)


func _run() -> void:
	var music := WaterhouseMusicDirector.new()
	root.add_child(music)
	await process_frame
	music.set_process(false)
	expect(music.segment.playing and music.segment_id == "title", "title score plays outside active game")
	expect(AudioServer.get_bus_index("Music") >= 0, "standalone director creates Music bus")
	expect(music.synchronized.stream_count == 3, "three layers use one native synchronized stream")
	var equal_lengths := true
	for index in range(3):
		var stream := music.synchronized.get_sync_stream(index) as AudioStreamOggVorbis
		equal_lengths = equal_lengths and stream != null
		if stream != null:
			equal_lengths = equal_lengths and absf(stream.get_length() - 96.0) < 0.03 and stream.loop
	expect(equal_lengths, "all three imported Ogg layers loop on an identical 96 second timeline")
	music.set_flow("playing")
	expect(music.stems.playing and not music.segment.playing, "run starts synchronized stems and stops title")
	expect(music.silence_remaining >= 20.0 and music.silence_remaining <= 45.0, "run begins with a 20 to 45 second music rest")
	context(music, 1.9, 0.4)
	expect(music.state == "calm", "brief moderate threat does not reveal danger through music")
	context(music, 0.2, 0.3)
	context(music, 1.9, 0.4)
	expect(music.state == "calm", "lower threat resets the consecutive two second dwell")
	context(music, 0.11, 0.4)
	expect(music.state == "uneasy" and music.stem_gains.y > 0.0, "sustained moderate threat introduces texture")
	context(music, 0.1, 0.8)
	expect(music.state == "danger" and music.stem_gains.z > 0.0, "high threat immediately adds danger pulse")
	context(music, 7.9, 0.0)
	expect(music.state == "danger", "danger remains for nearly eight quiet seconds")
	context(music, 0.1, 0.3)
	context(music, 7.9, 0.0)
	expect(music.state == "danger", "renewed uncertainty restarts the quiet interval")
	context(music, 0.11, 0.0)
	expect(music.state == "calm", "eight continuously safe seconds releases threat state")
	music._advance(6.1)
	expect(music.stem_gains.length() < 0.001, "danger layers fade completely within six seconds")
	music.cue_event("windup")
	expect(music.state == "danger" and music.duck_remaining > 0.0, "windup adds urgency while ducking score for audible warning")
	context(music, 7.0)
	music.cue_event("windup")
	context(music, 7.0)
	expect(music.state == "danger", "a new attack warning restarts the safe interval")
	context(music, 1.1)
	expect(music.state == "calm", "danger can resolve after the final attack warning even without high numeric threat")
	music.cue_event("windup")
	music._advance(0.1)
	expect(absf(linear_to_db(music.duck_gain) + 6.0) < 0.1, "critical warning ducks music by six decibels")
	music._advance(2.0)
	expect(is_equal_approx(music.duck_gain, 1.0), "score recovers after warning without leaving permanent duck")
	context(music, 8.1)
	context(music, 0.1, 0.0, true)
	expect(music.segment_id == "first_dive" and music.cue_counts.get("first_dive", 0) == 1, "first submersion cues first dive once")
	context(music, 0.1, 0.0, true)
	music.cue_event("first_dive")
	expect(music.cue_counts.get("first_dive", 0) == 1, "repeated dive event cannot restart the one shot")
	context(music, 0.1, 0.0, false, 4, 0.0, "reservoir")
	expect(music.segment_id == "reservoir", "reservoir entry adds its own one time segment")
	context(music, 0.1, 0.0, false, 6, 0.0)
	music._advance(2.0)
	var low_pump_gain := music.segment_gain
	expect(music.segment_id == "pump" and music.segment.playing, "purge phase begins looped pump score")
	context(music, 2.0, 0.0, false, 6, 0.9)
	expect(music.segment_gain > low_pump_gain, "pump density increases with real purge progress")
	expect(music.stem_gains.y > 0.0 and music.stem_gains.z > 0.0, "final purge phase introduces synchronized texture and pulse layers")
	music.cue_event("reservoir")
	expect(music.segment_id == "pump", "visited reservoir cannot replace purge score")
	context(music, 2.0, 0.9, false, 6, 0.9)
	expect(music.segment_gain <= 0.001 and music.stem_gains.z > 0.0, "danger suppresses the mission score")
	context(music, 0.1, 0.9, false, 7, 1.0)
	expect(not music.segment.playing and not music.cue_counts.has("egress"), "pressure completion stops pump and does not falsely cue escape")
	music.cue_event("egress")
	expect(music.segment_id == "egress", "actual exit activation cues egress")
	expect(music.state == "calm", "safe evacuation releases stale danger immediately")
	context(music, 1.0)
	expect(music.segment_gain > 0.0, "safe egress score becomes audible before victory")
	await create_timer(0.3).timeout
	var played_position := music.stems.get_playback_position()
	expect(played_position > 0.05, "native audio clock advances synchronized stream")
	music.set_flow("map")
	var paused_position := music.stems.get_playback_position()
	var paused_duck := music.duck_remaining
	var paused_state := music.state
	await create_timer(0.3).timeout
	context(music, 25.0, 0.0)
	expect(absf(music.stems.get_playback_position() - paused_position) < 0.04, "map preserves real stream playback position")
	expect(music.state == paused_state and is_equal_approx(music.duck_remaining, paused_duck), "map freezes threat and duck timers")
	music.set_flow("playing")
	await create_timer(0.3).timeout
	expect(music.stems.get_playback_position() > paused_position + 0.1, "closing map resumes shared audio clock")
	music.set_flow("paused")
	paused_position = music.stems.get_playback_position()
	await create_timer(0.2).timeout
	expect(absf(music.stems.get_playback_position() - paused_position) < 0.04 and music.segment.stream_paused, "pause freezes both synchronized layers and mission voice")
	music.set_flow("playing")
	context(music, 0.5, 0.0, true)
	expect(music.music_filter.cutoff_hz > 9000.0 and music.music_filter.cutoff_hz < 18000.0, "water lightly filters score without strong world muffle")
	music.set_flow("won")
	expect(not music.stems.playing and music.segment_id == "won", "victory interrupts all gameplay layers")
	music._advance(1.0)
	var remaining := music.terminal_remaining
	music.set_flow("won")
	expect(is_equal_approx(music.terminal_remaining, remaining), "repeated victory flow does not restart ending")
	music._advance(20.0)
	expect(not music.segment.playing, "victory release ends after twenty seconds")
	music.set_flow("playing")
	expect(music.cue_counts.is_empty() and music.state == "calm" and music.stems.playing, "retry starts a clean run without stale once markers")
	music.reset_music()
	music.set_flow("playing")
	expect(music.stems.playing and music.run_started, "reset followed by same playing flow restarts the native synchronized clock")
	music.set_flow("dead")
	music._advance(5.1)
	expect(not music.segment.playing and not music.stems.playing, "death ending stops after five seconds")
	for index in range(10):
		music.set_flow("playing")
		music.cue_event("first_dive")
		music.set_flow("dead")
	expect(music.get_child_count() == 2, "ten retries retain only two bounded score voices")
	music.set_flow("playing")
	music._advance(46.0)
	expect(music.exploration_remaining >= 12.0 and music.exploration_remaining <= 24.0, "calm exploration starts a bounded short music passage")
	music._advance(25.0)
	expect(music.silence_remaining >= 20.0 and music.silence_remaining <= 45.0, "calm passage leaves a new twenty to forty five second rest")
	music.queue_free()
	await process_frame
	# The WASAPI mixing thread releases retired playback handles asynchronously.
	await create_timer(0.15).timeout
	print("MUSIC TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
