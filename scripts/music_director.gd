class_name WaterhouseMusicDirector
extends Node
## A single synchronized stream keeps all three score stems on the same clock.

const MUSIC_PATH := "res://assets/audio/music/"
const STEM_NAMES := ["base", "texture", "pulse"]
const VALID_FLOWS := ["title", "playing", "paused", "map", "dead", "won"]
const TERMINAL_LENGTHS := {"dead": 5.0, "won": 20.0}

var flow: String = "title"
var state: String = "calm"
var synchronized: AudioStreamSynchronized
var stems: AudioStreamPlayer
var segment: AudioStreamPlayer
var segment_id: String = ""
var cue_counts: Dictionary = {}
var music_bus: int = -1
var music_filter: AudioEffectLowPassFilter
var high_threat_time: float = 0.0
var safe_time: float = 0.0
var silence_remaining: float = 0.0
var exploration_remaining: float = 0.0
var terminal_remaining: float = 0.0
var duck_remaining: float = 0.0
var duck_gain: float = 1.0
var duck_target: float = 1.0
var stem_gains := Vector3.ZERO
var segment_gain: float = 0.0
var threat_level: float = 0.0
var underwater: bool = false
var current_stage: int = 0
var purge_progress: float = 0.0
var region: String = ""
var run_started: bool = false
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _terminal_started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_bus()
	synchronized = AudioStreamSynchronized.new()
	synchronized.stream_count = 3
	for index in range(3):
		synchronized.set_sync_stream(index, _load_stream(STEM_NAMES[index], true))
		synchronized.set_sync_stream_volume(index, -80.0)
	stems = AudioStreamPlayer.new()
	stems.name = "SynchronizedMusic"
	stems.stream = synchronized
	stems.bus = "Music"
	add_child(stems)
	segment = AudioStreamPlayer.new()
	segment.name = "MusicSegment"
	segment.bus = "Music"
	segment.volume_db = -80.0
	add_child(segment)
	_play_segment("title", true)


func _setup_bus() -> void:
	music_bus = AudioServer.get_bus_index("Music")
	if music_bus < 0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus, "Music")
		AudioServer.lock()
		AudioServer.set_bus_send(music_bus, "Master")
		AudioServer.unlock()
	for index in range(AudioServer.get_bus_effect_count(music_bus)):
		var effect := AudioServer.get_bus_effect(music_bus, index)
		if effect is AudioEffectLowPassFilter:
			music_filter = effect as AudioEffectLowPassFilter
			break
	if music_filter == null:
		music_filter = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(music_bus, music_filter)
	music_filter.cutoff_hz = 18000.0


func _load_stream(id: String, looping: bool = false) -> AudioStream:
	var key := id + ("_loop" if looping else "_once")
	if _streams.has(key):
		return _streams[key] as AudioStream
	var path := MUSIC_PATH + id + ".ogg"
	if not ResourceLoader.exists(path):
		push_error("Missing required music asset: " + path)
		return null
	var stream := (load(path) as AudioStream).duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = looping
	_streams[key] = stream
	return stream


func set_flow(next_flow: String) -> void:
	if not VALID_FLOWS.has(next_flow):
		return
	if next_flow == flow and not (flow == "playing" and not run_started) and not (flow == "title" and not segment.playing):
		return
	var previous := flow
	flow = next_flow
	var freezing := flow == "paused" or flow == "map"
	stems.stream_paused = freezing
	segment.stream_paused = freezing
	if freezing:
		return
	if flow == "playing":
		if previous == "title" or previous == "dead" or previous == "won" or not run_started:
			reset_music()
			run_started = true
			stems.play()
			silence_remaining = _rng.randf_range(20.0, 45.0)
	elif flow == "title":
		reset_music()
		_play_segment("title", true)
	elif flow == "dead" or flow == "won":
		reset_music()
		_terminal_started = true
		terminal_remaining = float(TERMINAL_LENGTHS[flow])
		_play_segment(flow)


func update_context(delta: float, threat: float, submerged: bool, stage: int, purge_ratio: float, region_id: String) -> void:
	if flow != "playing":
		return
	threat_level = clampf(threat, 0.0, 1.0)
	underwater = submerged
	current_stage = stage
	purge_progress = clampf(purge_ratio, 0.0, 1.0)
	region = region_id
	if submerged:
		cue_event("first_dive")
	if region_id == "reservoir":
		cue_event("reservoir")
	if threat_level > 0.7:
		state = "danger"
		high_threat_time = 0.0
		safe_time = 0.0
	elif state == "calm":
		high_threat_time = high_threat_time + delta if threat_level > 0.35 else 0.0
		if high_threat_time >= 2.0:
			state = "uneasy"
			safe_time = 0.0
	else:
		safe_time = safe_time + delta if threat_level < 0.25 else 0.0
		if safe_time >= 8.0:
			state = "calm"
			safe_time = 0.0
			high_threat_time = 0.0
			exploration_remaining = 0.0
			silence_remaining = _rng.randf_range(20.0, 45.0)
	if stage == 6 and segment_id != "pump" and not cue_counts.has("pump"):
		cue_event("pump")
	elif stage != 6 and segment_id == "pump":
		segment.stop()
		segment_id = ""
		duck()


func cue_event(id: String) -> void:
	if flow != "playing":
		return
	if id == "windup" or id == "attack_windup":
		state = "danger"
		safe_time = 0.0
		duck()
		return
	if id == "critical" or id == "low_oxygen" or id == "device_complete":
		duck()
		return
	if not ["first_dive", "reservoir", "pump", "egress"].has(id) or cue_counts.has(id):
		return
	if id == "egress":
		# The actual exit event disables all enemies; release their stale threat now.
		state = "calm"
		high_threat_time = 0.0
		safe_time = 0.0
		threat_level = 0.0
	cue_counts[id] = 1
	if id == "first_dive" or id == "reservoir":
		if segment.playing and ["pump", "egress"].has(segment_id):
			return
	_play_segment(id, id == "pump")


func _play_segment(id: String, looping: bool = false) -> void:
	segment.stop()
	segment.stream = _load_stream(id, looping)
	segment_id = id
	segment_gain = 0.0
	segment.volume_db = -80.0
	if segment.stream != null:
		segment.play()


func duck(seconds: float = 1.2, amount_db: float = -6.0) -> void:
	duck_remaining = maxf(duck_remaining, maxf(seconds, 0.0))
	duck_target = minf(duck_target, db_to_linear(minf(amount_db, 0.0)))


func reset_music() -> void:
	stems.stop()
	segment.stop()
	stems.stream_paused = false
	segment.stream_paused = false
	state = "calm"
	segment_id = ""
	cue_counts.clear()
	high_threat_time = 0.0
	safe_time = 0.0
	silence_remaining = 0.0
	exploration_remaining = 0.0
	terminal_remaining = 0.0
	duck_remaining = 0.0
	duck_target = 1.0
	duck_gain = 1.0
	stem_gains = Vector3.ZERO
	segment_gain = 0.0
	current_stage = 0
	purge_progress = 0.0
	underwater = false
	run_started = false
	_terminal_started = false
	_apply_gains()


func _process(delta: float) -> void:
	_advance(delta)


func _exit_tree() -> void:
	stems.stop()
	segment.stop()
	stems.stream = null
	segment.stream = null
	_streams.clear()


func _advance(delta: float) -> void:
	if flow == "paused" or flow == "map":
		return
	duck_remaining = maxf(0.0, duck_remaining - delta)
	if duck_remaining <= 0.0:
		duck_target = 1.0
	duck_gain = move_toward(duck_gain, duck_target, delta * (8.0 if duck_target < duck_gain else 1.5))
	var targets := Vector3.ZERO
	var target_segment: float = 0.0
	if flow == "playing":
		if state == "calm":
			if exploration_remaining > 0.0:
				exploration_remaining = maxf(0.0, exploration_remaining - delta)
				if exploration_remaining <= 0.0:
					silence_remaining = _rng.randf_range(20.0, 45.0)
			else:
				# Count the rest after the previous score has faded to silence.
				if stem_gains.length() < 0.001 and not segment.playing:
					silence_remaining = maxf(0.0, silence_remaining - delta)
				if silence_remaining <= 0.0:
					exploration_remaining = _rng.randf_range(12.0, 24.0)
			if exploration_remaining > 0.0 and not segment.playing:
				targets.x = db_to_linear(-15.0)
		elif state == "uneasy":
			targets = Vector3(db_to_linear(-14.0), db_to_linear(-20.0), 0.0)
		else:
			targets = Vector3(db_to_linear(-13.0), db_to_linear(-15.0), db_to_linear(-12.0))
		if state == "calm" and segment.playing:
			target_segment = db_to_linear(-13.0)
			if segment_id == "pump":
				target_segment = db_to_linear(lerpf(-20.0, -11.0, floorf(purge_progress * 3.0) / 3.0))
				targets.x = db_to_linear(-24.0)
				if purge_progress >= 1.0 / 3.0:
					targets.y = db_to_linear(-24.0)
				if purge_progress >= 2.0 / 3.0:
					targets.z = db_to_linear(-22.0)
		elif state == "uneasy" and segment.playing:
			target_segment = db_to_linear(-25.0)
	elif flow == "title":
		target_segment = db_to_linear(-14.0)
	elif _terminal_started:
		terminal_remaining = maxf(0.0, terminal_remaining - delta)
		if terminal_remaining > 0.0:
			target_segment = db_to_linear(-12.0) * minf(1.0, terminal_remaining / 2.0)
		else:
			segment.stop()
			_terminal_started = false
	var rise_rate := 0.18
	var fade_rate := db_to_linear(-12.0) / 6.0
	stem_gains.x = move_toward(stem_gains.x, targets.x, delta * (rise_rate if targets.x > stem_gains.x else fade_rate))
	stem_gains.y = move_toward(stem_gains.y, targets.y, delta * (rise_rate if targets.y > stem_gains.y else fade_rate))
	stem_gains.z = move_toward(stem_gains.z, targets.z, delta * (rise_rate if targets.z > stem_gains.z else fade_rate))
	segment_gain = move_toward(segment_gain, target_segment, delta * 0.2)
	music_filter.cutoff_hz = lerpf(music_filter.cutoff_hz, 9500.0 if underwater else 18000.0, minf(1.0, delta * 2.0))
	_apply_gains()


func _apply_gains() -> void:
	for index in range(3):
		synchronized.set_sync_stream_volume(index, linear_to_db(maxf(stem_gains[index], 0.0001)))
	stems.volume_db = linear_to_db(maxf(duck_gain, 0.0001))
	segment.volume_db = linear_to_db(maxf(segment_gain * duck_gain, 0.0001))
