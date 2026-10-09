class_name WaterhouseSoundscape
extends Node
## Physical sound and listener mixing; AI hearing remains a separate gameplay signal.

const MANIFEST_PATH := "res://assets/audio/audio_v2_manifest.json"
const MAX_VOICES := 32
const ROOM_GROUPS := ["hall", "corridor", "mechanical", "archive", "reservoir", "egress"]
const ROOM_WET := [0.28, 0.13, 0.17, 0.09, 0.38, 0.12]
const ROOM_SIZE := [0.88, 0.56, 0.67, 0.43, 0.96, 0.61]

var air: AudioStreamPlayer
var water: AudioStreamPlayer
var heartbeat: AudioStreamPlayer
var creature_voice: AudioStreamPlayer3D
var pump_voice: AudioStreamPlayer3D
var music: WaterhouseMusicDirector
var master_volume: float = 0.75
var step_clock: float = 0.0
var omen_clock: float = 0.0
var air_bus: int = 0
var muffle: AudioEffectLowPassFilter
var enabled: bool = false
var flow: String = "title"
var room_group: String = "hall"
var room_mix: Array[float] = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var underwater_mix: float = 0.0
var occlusion_checks: int = 0
var cues: Dictionary = {}
var _world: WaterhouseWorld
var _player: PlayerController
var _voices: Array[Dictionary] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _ambient: Array[AudioStreamPlayer] = []
var _filters: Dictionary = {}
var _reverbs: Array[AudioEffectReverb] = []
var _streams: Dictionary = {}
var _last_variant: Dictionary = {}
var _actor_cooldowns: Dictionary = {}
var _event_cooldowns: Dictionary = {}
var _occlusion_clock: float = 0.0
var _decoration_clock: float = 5.0
var _breath_clock: float = 0.0
var _was_low_oxygen: bool = false
var _serial: int = 0
var _pump_entry: Dictionary = {}
var _room_from: Array[float] = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _room_elapsed: float = 2.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_read_manifest()
	_make_buses()
	# Keep imported WAV loop contracts for existing scenes and saved regression tools.
	air = _loop("res://assets/audio/facility.wav", "EnvironmentAir", -60.0)
	water = AudioStreamPlayer.new()
	water.stream = _cue_stream("submerged", true)
	water.bus = "Environment"
	water.volume_db = -60.0
	add_child(water)
	heartbeat = _loop(str(cues["heartbeat"]["files"][0]), "Body", -60.0)
	creature_voice = _spatial_voice("WorldWater", 90.0, 18.0)
	creature_voice.stream = load("res://assets/audio/leviathan.wav")
	pump_voice = _spatial_voice("WorldAir", 100.0, 12.0)
	pump_voice.stream = _cue_stream("pump", true)
	pump_voice.volume_db = -15.0
	_pump_entry = _make_slot(pump_voice, MAX_VOICES - 4)
	_pump_entry["cue"] = "pump"
	_pump_entry["volume"] = -15.0
	_pump_entry["priority"] = 3
	for group: String in ROOM_GROUPS:
		var voice := AudioStreamPlayer.new()
		voice.stream = _cue_stream("ambient_" + group, true)
		voice.bus = "EnvironmentAir"
		voice.volume_db = -80.0
		add_child(voice)
		_ambient.append(voice)
	for index in range(MAX_VOICES - 4):
		var voice := _spatial_voice("WorldAir", 85.0, 8.0)
		_voices.append(_make_slot(voice, index))
	for index in range(4):
		var voice := AudioStreamPlayer.new()
		voice.bus = "UI"
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_ui_voices.append(voice)
	music = WaterhouseMusicDirector.new()
	add_child(music)
	set_volume(master_volume)
	set_mix("sfx_volume", 1.0)
	set_mix("ambient_volume", 0.8)
	set_mix("music_volume", 0.6)


func configure(world: WaterhouseWorld, player: PlayerController) -> void:
	_world = world
	_player = player


func _read_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("Required audio manifest is missing: " + MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or not parsed.get("cues") is Dictionary:
		push_error("Audio manifest must contain a cues dictionary")
		return
	cues = parsed["cues"]
	for cue: String in cues:
		if not cues[cue] is Dictionary or not cues[cue].get("files") is Array or cues[cue]["files"].is_empty():
			push_error("Audio manifest has an invalid cue: " + cue)
			cues = {}
			return
		for path: String in cues[cue].get("files", []):
			if not ResourceLoader.exists(path):
				push_error("Required audio asset is missing: " + path)
			else:
				_streams[path] = load(path)


func _bus(name_value: String, send: String) -> int:
	var index := AudioServer.get_bus_index(name_value)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name_value)
	_send(index, send)
	return index


func _send(index: int, target: String) -> void:
	if AudioServer.get_bus_send(index) == target:
		return
	# Godot 4.7.2 set_bus_send writes StringName without the mixer's lock.
	# A concurrent _mix_step can observe its transient null pointer and crash.
	AudioServer.lock()
	AudioServer.set_bus_send(index, target)
	AudioServer.unlock()


func _make_buses() -> void:
	for bus_name: String in ["SFX", "Environment", "Music", "UI"]:
		_bus(bus_name, "Master")
	_bus("UI", "SFX")
	for bus_name: String in ["WorldAir", "WorldWater", "Body", "Facility"]:
		_bus(bus_name, "SFX")
	_bus("EnvironmentAir", "Environment")
	_bus("EnvironmentWater", "Environment")
	for bus_name: String in ["WorldAir", "WorldWater", "EnvironmentAir", "EnvironmentWater", "Facility"]:
		var index := AudioServer.get_bus_index(bus_name)
		var filter: AudioEffectLowPassFilter
		if AudioServer.get_bus_effect_count(index) == 0:
			filter = AudioEffectLowPassFilter.new()
			filter.cutoff_hz = 18000.0
			AudioServer.add_bus_effect(index, filter)
			var reverb := AudioEffectReverb.new()
			reverb.room_size = 0.88
			reverb.wet = 0.22
			AudioServer.add_bus_effect(index, reverb)
		else:
			filter = AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
		_filters[bus_name] = filter
		_reverbs.append(AudioServer.get_bus_effect(index, 1) as AudioEffectReverb)
	air_bus = AudioServer.get_bus_index("WorldAir")
	muffle = _filters["WorldAir"]
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, limiter)


func _loop(path: String, bus_name: String, volume: float) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.stream = _load_loop(path)
	voice.bus = bus_name
	voice.volume_db = volume
	add_child(voice)
	return voice


func _spatial_voice(bus_name: String, distance: float, unit: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.bus = bus_name
	voice.max_distance = distance
	voice.unit_size = unit
	voice.max_db = 0.0
	add_child(voice)
	return voice


func _make_slot(voice: AudioStreamPlayer3D, index: int) -> Dictionary:
	# Filters are allocated once with the pool, never during a sound or ray query.
	var bus_name := "SoundSlot%02d" % index
	var bus := _bus(bus_name, "WorldAir")
	var filter: AudioEffectLowPassFilter
	if AudioServer.get_bus_effect_count(bus) == 0:
		filter = AudioEffectLowPassFilter.new()
		filter.cutoff_hz = 18000.0
		AudioServer.add_bus_effect(bus, filter)
	else:
		filter = AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	AudioServer.set_bus_effect_enabled(bus, 0, false)
	voice.bus = bus_name
	return {"voice": voice, "bus": bus, "filter": filter, "priority": 0, "serial": 0, "owner": null, "body": false, "water": false, "occluded": false, "occlusion_mix": 0.0, "cue": "", "volume": -12.0}


func _load_loop(path: String) -> AudioStreamWAV:
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream


func _cue_stream(cue: String, looping: bool = false) -> AudioStream:
	if not cues.has(cue):
		push_error("Unknown audio cue: " + cue)
		return null
	var files: Array = cues[cue].get("files", [])
	if files.is_empty():
		push_error("Audio cue has no files: " + cue)
		return null
	var variant := _rng.randi_range(0, files.size() - 1)
	if files.size() > 1 and variant == int(_last_variant.get(cue, -1)):
		variant = (variant + _rng.randi_range(1, files.size() - 1)) % files.size()
	_last_variant[cue] = variant
	var path: String = files[variant]
	if not _streams.has(path):
		_streams[path] = load(path)
	var stream: AudioStream = _streams[path]
	if looping and stream is AudioStreamWAV:
		stream = stream.duplicate()
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = roundi(stream.get_length() * (stream as AudioStreamWAV).mix_rate)
	elif looping and stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func set_volume(value: float) -> void:
	set_mix("volume", value)


func set_mix(key: String, value: float) -> void:
	var names := {"volume": "Master", "sfx_volume": "SFX", "ambient_volume": "Environment", "music_volume": "Music"}
	if not names.has(key):
		return
	var amount := clampf(value, 0.0, 1.0)
	if key == "volume":
		master_volume = amount
	var bus := AudioServer.get_bus_index(names[key])
	if bus >= 0:
		AudioServer.set_bus_mute(bus, amount == 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(amount, 0.0001)))


func start_run() -> void:
	reset_sound()
	enabled = true
	flow = "playing"
	for voice in _ambient:
		voice.play()
	water.play()
	heartbeat.play()
	# The six new rooms replace the original full-volume global facility loop.
	air.volume_db = -60.0
	music.set_flow("playing")


func set_flow(value: String) -> void:
	flow = value
	if value in ["dead", "won", "title"]:
		_stop_world()
		enabled = false
	elif value == "playing":
		enabled = true
	var paused := value in ["paused", "map"]
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stream_paused = paused
		elif child is AudioStreamPlayer and (child as AudioStreamPlayer).bus != "UI":
			(child as AudioStreamPlayer).stream_paused = paused
	if music:
		music.set_flow(value)


func update(delta: float, swimmer: PlayerController, threat: float, region_id: String = "", stage: int = 0, purge_ratio: float = 0.0) -> void:
	_player = swimmer
	if not enabled or flow in ["paused", "map", "dead", "won", "title"]:
		return
	step_clock -= delta
	omen_clock -= delta
	_breath_clock -= delta
	_occlusion_clock -= delta
	_decoration_clock -= delta
	_tick_cooldowns(delta)
	_update_rooms(delta, region_id)
	_update_medium(delta, swimmer.submerged)
	_update_voices(delta)
	_update_movement(swimmer)
	if _occlusion_clock <= 0.0:
		_update_occlusion()
		_occlusion_clock = 0.2
	if _decoration_clock <= 0.0:
		_decoration(region_id)
		_decoration_clock = _rng.randf_range(9.0, 20.0)
	water.volume_db = lerpf(-70.0, -19.0, underwater_mix)
	heartbeat.volume_db = lerpf(heartbeat.volume_db, -24.0 if threat > 0.65 or swimmer.oxygen < 20.0 else -70.0, minf(1.0, delta * 2.0))
	if swimmer.submerged and swimmer.oxygen < 25.0 and _breath_clock <= 0.0:
		player_event("breath_low")
		_breath_clock = 4.0 if swimmer.oxygen > 10.0 else 2.7
	elif not swimmer.submerged and swimmer.stamina < 30.0 and _breath_clock <= 0.0:
		player_event("breath_run")
		_breath_clock = 3.3
	_was_low_oxygen = swimmer.oxygen < 30.0 if swimmer.submerged else _was_low_oxygen
	music.update_context(delta, threat, swimmer.submerged, stage, purge_ratio, region_id)


func _tick_cooldowns(delta: float) -> void:
	for key in _actor_cooldowns.keys():
		_actor_cooldowns[key] = maxf(0.0, float(_actor_cooldowns[key]) - delta)
	for key in _event_cooldowns.keys():
		_event_cooldowns[key] = maxf(0.0, float(_event_cooldowns[key]) - delta)


func _group(region: String) -> String:
	if region in ["pump_room", "power_room"]:
		return "mechanical"
	if region == "archives":
		return "archive"
	if region == "reservoir":
		return "reservoir"
	if region == "egress":
		return "egress"
	if region.contains("link") or region.contains("connector") or region.contains("corridor") or region.contains("canal"):
		return "corridor"
	return "hall"


func _update_rooms(delta: float, region: String) -> void:
	var next_group := _group(region)
	if next_group != room_group:
		_room_from.assign(room_mix)
		_room_elapsed = 0.0
		room_group = next_group
	_room_elapsed = minf(2.0, _room_elapsed + delta)
	var wet := 0.0
	var size_value := 0.0
	for index in range(ROOM_GROUPS.size()):
		var target := 1.0 if ROOM_GROUPS[index] == room_group else 0.0
		room_mix[index] = lerpf(_room_from[index], target, _room_elapsed / 2.0)
		_ambient[index].volume_db = linear_to_db(maxf(room_mix[index] * db_to_linear(-23.0), 0.0001))
		wet += room_mix[index] * ROOM_WET[index]
		size_value += room_mix[index] * ROOM_SIZE[index]
	for reverb in _reverbs:
		if reverb:
			reverb.wet = wet
			reverb.room_size = size_value


func _update_medium(delta: float, submerged: bool) -> void:
	underwater_mix = move_toward(underwater_mix, 1.0 if submerged else 0.0, delta / 0.5)
	for name_value: String in _filters:
		var filter: AudioEffectLowPassFilter = _filters[name_value]
		if not filter:
			continue
		var water_source := name_value.contains("Water")
		var above := 1500.0 if water_source else 18000.0
		var below := 10500.0 if water_source else 700.0
		filter.cutoff_hz = lerpf(above, below, underwater_mix)


func _update_voices(delta: float) -> void:
	for entry in _voices + [_pump_entry]:
		var voice: AudioStreamPlayer3D = entry["voice"]
		if not voice.playing:
			AudioServer.set_bus_effect_enabled(int(entry["bus"]), 0, false)
			continue
		var owner: Variant = entry["owner"]
		if entry["body"] and is_instance_valid(_player):
			voice.global_position = _player.camera.global_position
		elif owner != null:
			if not is_instance_valid(owner):
				voice.stop()
				continue
			voice.global_position = (owner as Node3D).global_position
			entry["water"] = _source_is_water(voice.global_position)
		entry["occlusion_mix"] = move_toward(float(entry["occlusion_mix"]), 1.0 if entry["occluded"] else 0.0, delta / 0.3)
		_route(entry)


func _route(entry: Dictionary) -> void:
	var voice: AudioStreamPlayer3D = entry["voice"]
	var bus: int = entry["bus"]
	var filter: AudioEffectLowPassFilter = entry["filter"]
	if entry["body"]:
		_send(bus, "Body")
		AudioServer.set_bus_effect_enabled(bus, 0, false)
		return
	var environment_cue := str(cues.get(entry["cue"], {}).get("category", "")) == "environment"
	var route := "Environment" if environment_cue else "World"
	_send(bus, route + ("Water" if entry["water"] else "Air"))
	AudioServer.set_bus_effect_enabled(bus, 0, float(entry["occlusion_mix"]) > 0.001)
	if filter:
		filter.cutoff_hz = lerpf(18000.0, 1100.0, float(entry["occlusion_mix"]))
	voice.volume_db = float(entry.get("volume", -12.0)) - 7.0 * float(entry["occlusion_mix"])


func _source_is_water(location: Vector3) -> bool:
	return is_instance_valid(_world) and _world.is_underwater(location)


func _update_occlusion() -> void:
	occlusion_checks = 0
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var nearest: Array[Dictionary] = []
	for entry in _voices + [_pump_entry]:
		var voice: AudioStreamPlayer3D = entry["voice"]
		if voice.playing and not entry["body"]:
			nearest.append(entry)
	nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["voice"] as Node3D).global_position.distance_squared_to(_player.global_position) < (b["voice"] as Node3D).global_position.distance_squared_to(_player.global_position))
	var origin := _player.camera.global_position
	for index in range(mini(8, nearest.size())):
		var entry: Dictionary = nearest[index]
		var voice: AudioStreamPlayer3D = entry["voice"]
		var query := PhysicsRayQueryParameters3D.create(origin, voice.global_position, 1, [_player.get_rid()])
		query.collide_with_areas = false
		var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
		entry["occluded"] = not hit.is_empty() and (hit["position"] as Vector3).distance_to(voice.global_position) > 0.25
		occlusion_checks += 1


func _update_movement(swimmer: PlayerController) -> void:
	if not swimmer.enabled or step_clock > 0.0 or swimmer.velocity.length() < 1.1:
		return
	if swimmer.in_water:
		one_shot("swim_fast" if swimmer.velocity.length() >= 3.2 else "swim", -25.0)
		step_clock = 0.6 if swimmer.velocity.length() >= 3.2 else 0.95
	elif swimmer.is_on_floor():
		var surface := "concrete"
		for index in range(swimmer.get_slide_collision_count()):
			var collision := swimmer.get_slide_collision(index)
			if collision.get_normal().y > 0.5 and collision.get_collider() is Node:
				surface = str((collision.get_collider() as Node).get_meta("audio_surface", "concrete"))
				break
		if surface not in ["dry_tile", "wet_tile", "metal", "concrete"]:
			surface = "concrete"
		one_shot("step_" + surface, -22.0 if swimmer.crouching else -15.0, swimmer.global_position + Vector3.UP * 0.15)
		step_clock = 0.7 if swimmer.crouching else (0.36 if swimmer.velocity.length() > 4.0 else 0.56)


func one_shot(cue: String, volume: float = -12.0, location: Vector3 = Vector3.INF) -> void:
	if cue == "step":
		cue = "step_concrete"
	elif cue == "alarm":
		cue = "pressure_ready"
	if cue.begins_with("ui_"):
		_play_ui(cue)
		return
	if not enabled or flow != "playing":
		return
	var priority := 3 if cue in ["breath_low", "pressure_ready", "relay", "gate", "pump_start", "valve_done"] else 2
	if cue in ["drip", "vent", "pipe", "stress"]:
		priority = 0
	_play_pooled(cue, volume, location, priority)
	if priority == 3:
		music.duck(1.2, -6.0)


func _play_pooled(cue: String, volume: float, location: Vector3, priority: int, owner: Node3D = null) -> void:
	var selected: Dictionary = {}
	var lowest := INF
	for entry in _voices:
		var voice: AudioStreamPlayer3D = entry["voice"]
		if not voice.playing:
			selected = entry
			break
		var distance := voice.global_position.distance_to(_player.global_position) if is_instance_valid(_player) else 0.0
		var rank := float(entry["priority"]) * 1000.0 - distance
		if rank < lowest:
			lowest = rank
			selected = entry
	if selected.is_empty() or ((selected["voice"] as AudioStreamPlayer3D).playing and int(selected["priority"]) > priority):
		return
	if (selected["voice"] as AudioStreamPlayer3D).playing and int(selected["priority"]) == priority and is_instance_valid(_player):
		var incoming_distance := location.distance_squared_to(_player.global_position) if location.is_finite() else 0.0
		if incoming_distance > (selected["voice"] as Node3D).global_position.distance_squared_to(_player.global_position):
			return
	var stream := _cue_stream(cue)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = selected["voice"]
	voice.stop()
	_serial += 1
	selected["priority"] = priority
	selected["serial"] = _serial
	selected["owner"] = owner
	selected["body"] = not location.is_finite()
	selected["water"] = _source_is_water(location) if location.is_finite() else false
	selected["occluded"] = false
	selected["occlusion_mix"] = 0.0
	selected["volume"] = volume
	selected["cue"] = cue
	voice.stream = stream
	voice.pitch_scale = _rng.randf_range(0.97, 1.03)
	voice.global_position = location if location.is_finite() else (_player.camera.global_position if is_instance_valid(_player) else Vector3.ZERO)
	_route(selected)
	voice.volume_db = volume
	voice.play()


func _play_ui(cue: String) -> void:
	var stream := _cue_stream(cue)
	if stream == null:
		return
	var voice: AudioStreamPlayer = _ui_voices[0]
	for candidate in _ui_voices:
		if not candidate.playing:
			voice = candidate
			break
	voice.stop()
	voice.stream = stream
	voice.volume_db = -18.0
	voice.play()


func terminal_impact(cue: String) -> void:
	# Old world voices stop on death; the actual fatal impact gets one fresh body cue.
	if flow == "dead" and cue.ends_with("_hit") and cues.has(cue):
		_play_ui(cue)


func player_event(cue: String) -> void:
	if cue.begins_with("ui_"):
		_play_ui(cue)
		return
	if not enabled or flow != "playing":
		return
	if float(_event_cooldowns.get(cue, 0.0)) > 0.0:
		return
	_event_cooldowns[cue] = 0.25
	one_shot(cue, -18.0 if cue != "hurt" else -13.0)
	if cue == "surface" and _was_low_oxygen:
		one_shot("gasp", -15.0)
		_was_low_oxygen = false
	if cue == "dive":
		music.cue_event("first_dive")


func creature_event(enemy: Node3D, event: String, strength: float = 1.0) -> void:
	if not enabled or not is_instance_valid(enemy) or flow != "playing":
		return
	var id := enemy.get_instance_id()
	var key := "%s:%s" % [id, "omen" if event == "locomotion" else event]
	if float(_actor_cooldowns.get(key, 0.0)) > 0.0:
		return
	var species := str(enemy.get_meta("species", "leviathan"))
	var suffix := "omen" if event == "locomotion" else event
	_actor_cooldowns[key] = 12.0 if event == "omen" else (9.0 if event == "locomotion" else 0.5)
	_play_pooled(species + "_" + suffix, lerpf(-25.0, -10.0, clampf(strength, 0.0, 1.0)), enemy.global_position, 3 if event in ["windup", "hit"] else 1, enemy)
	if event in ["windup", "hit"]:
		music.duck(1.4, -6.0)
		if event == "windup":
			music.cue_event("windup")


func omen(location: Vector3, strength: float) -> void:
	# Compatibility callers without an actor use a positional pooled voice.
	if omen_clock > 0.0 or not enabled:
		return
	_play_pooled("leviathan_omen", lerpf(-20.0, -9.0, clampf(strength, 0.0, 1.0)), location, 1)
	omen_clock = 9.0


func start_pump(location: Vector3) -> void:
	pump_voice.global_position = location
	_pump_entry["water"] = _source_is_water(location)
	_pump_entry["occluded"] = false
	_pump_entry["occlusion_mix"] = 0.0
	_route(_pump_entry)
	one_shot("pump_start", -12.0, location)
	pump_voice.play()


func stop_cue(cue: String) -> void:
	for entry in _voices:
		if entry["cue"] == cue:
			(entry["voice"] as AudioStreamPlayer3D).stop()
			entry["owner"] = null
			AudioServer.set_bus_effect_enabled(int(entry["bus"]), 0, false)
	if cue == "pump":
		pump_voice.stop()


func debug_snapshot() -> Dictionary:
	var active: Array[Dictionary] = []
	for entry in _voices:
		var voice: AudioStreamPlayer3D = entry["voice"]
		if not voice.playing:
			continue
		var owner: Variant = entry["owner"]
		var filter: AudioEffectLowPassFilter = entry["filter"]
		active.append({"cue": entry["cue"], "path": voice.stream.resource_path, "priority": entry["priority"], "owner_id": owner.get_instance_id() if is_instance_valid(owner) else 0, "position": voice.global_position, "occluded": entry["occluded"], "occlusion_mix": entry["occlusion_mix"], "cutoff_hz": filter.cutoff_hz if filter else 18000.0, "water": entry["water"], "paused": voice.stream_paused, "volume_db": voice.volume_db})
	var ui_count := 0
	for voice in _ui_voices:
		if voice.playing:
			ui_count += 1
	return {"active_voices": active, "active_voice_count": active.size() + ui_count, "capacity": MAX_VOICES, "room": room_group, "room_mix": room_mix.duplicate(), "underwater_mix": underwater_mix, "flow": flow, "occlusion_checks": occlusion_checks, "actor_cooldowns": _actor_cooldowns.duplicate(), "allocated_voices": _voices.size() + _ui_voices.size()}


func _decoration(region_id: String) -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_player):
		return
	for region in _world.map_regions:
		if str(region["id"]) != region_id:
			continue
		var bounds: Rect2 = region["bounds"]
		var cue := "pipe" if room_group == "mechanical" else ("stress" if room_group == "archive" else "drip")
		# A fixed wall/ceiling point belongs to the authored room, never to the listener.
		var location := Vector3(bounds.position.x + bounds.size.x * 0.22, 3.2, bounds.position.y + 0.6)
		_play_pooled(cue, -28.0, location, 0)
		break


func _stop_world() -> void:
	for entry in _voices:
		(entry["voice"] as AudioStreamPlayer3D).stop()
		(entry["voice"] as AudioStreamPlayer3D).stream_paused = false
		entry["owner"] = null
		AudioServer.set_bus_effect_enabled(int(entry["bus"]), 0, false)
	for voice in _ambient:
		voice.stop()
		voice.stream_paused = false
	for voice: AudioStreamPlayer in [air, water, heartbeat]:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream_paused = false
	if is_instance_valid(pump_voice):
		pump_voice.stop()
		pump_voice.stream_paused = false
		AudioServer.set_bus_effect_enabled(int(_pump_entry["bus"]), 0, false)
	if is_instance_valid(creature_voice):
		creature_voice.stop()
		creature_voice.stream_paused = false


func reset_sound() -> void:
	_stop_world()
	for voice in _ui_voices:
		voice.stop()
	step_clock = 0.0
	omen_clock = 0.0
	_breath_clock = 0.0
	_decoration_clock = 5.0
	_occlusion_clock = 0.0
	underwater_mix = 0.0
	_actor_cooldowns.clear()
	_event_cooldowns.clear()
	_last_variant.clear()
	_was_low_oxygen = false
	room_mix = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	_room_from.assign(room_mix)
	_room_elapsed = 2.0
	room_group = "hall"
	water.volume_db = -70.0
	heartbeat.volume_db = -70.0
	_update_medium(0.0, false)
	if music:
		music.reset_music()


func _exit_tree() -> void:
	_stop_world()
	for voice in _ui_voices:
		voice.stop()
