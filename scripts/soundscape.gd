class_name WaterhouseSoundscape
extends Node
## Offline generated WAV assets are routed through above/below-water buses.

var air: AudioStreamPlayer
var water: AudioStreamPlayer
var heartbeat: AudioStreamPlayer
var creature_voice: AudioStreamPlayer3D
var pump_voice: AudioStreamPlayer3D
var master_volume: float = 0.75
var step_clock: float = 0.0
var omen_clock: float = 0.0
var air_bus: int = 0
var muffle: AudioEffectLowPassFilter
var enabled: bool = false


func _ready() -> void:
	if AudioServer.get_bus_index("Facility") == -1:
		AudioServer.add_bus()
		air_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(air_bus, "Facility")
		AudioServer.set_bus_send(air_bus, "Master")
		muffle = AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 17000.0
		AudioServer.add_bus_effect(air_bus, muffle)
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.88
		reverb.wet = 0.22
		AudioServer.add_bus_effect(air_bus, reverb)
	else:
		air_bus = AudioServer.get_bus_index("Facility")
		muffle = AudioServer.get_bus_effect(air_bus, 0) as AudioEffectLowPassFilter
	air = _loop("res://assets/audio/facility.wav", "Facility", -16.0)
	water = _loop("res://assets/audio/submerged.wav", "Master", -60.0)
	heartbeat = _loop("res://assets/audio/heartbeat.wav", "Master", -60.0)
	creature_voice = AudioStreamPlayer3D.new()
	creature_voice.stream = load("res://assets/audio/leviathan.wav")
	creature_voice.bus = "Facility"
	creature_voice.max_distance = 80.0
	creature_voice.unit_size = 18.0
	creature_voice.volume_db = -6.0
	add_child(creature_voice)
	pump_voice = AudioStreamPlayer3D.new()
	pump_voice.stream = _load_loop("res://assets/audio/pump.wav")
	pump_voice.bus = "Facility"
	pump_voice.unit_size = 12.0
	pump_voice.max_distance = 100.0
	pump_voice.volume_db = -13.0
	add_child(pump_voice)
	set_volume(master_volume)


func _loop(path: String, bus_name: String, volume: float) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.stream = _load_loop(path)
	voice.bus = bus_name
	voice.volume_db = volume
	add_child(voice)
	voice.play()
	return voice


func _load_loop(path: String) -> AudioStreamWAV:
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream


func set_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func update(delta: float, swimmer: PlayerController, threat: float) -> void:
	var under: float = 1.0 if swimmer.submerged and enabled else 0.0
	water.volume_db = lerpf(water.volume_db, -13.0 if under > 0.5 else -60.0, minf(1.0, delta * 3.0))
	air.volume_db = lerpf(air.volume_db, -26.0 if under > 0.5 else -16.0, minf(1.0, delta * 2.0))
	muffle.cutoff_hz = lerpf(muffle.cutoff_hz, 650.0 if under > 0.5 else 17000.0, minf(1.0, delta * 4.0))
	heartbeat.volume_db = lerpf(heartbeat.volume_db, -17.0 if threat > 0.65 and enabled else -60.0, minf(1.0, delta * 2.0))
	step_clock -= delta
	omen_clock -= delta
	if enabled and swimmer.velocity.length() > 1.1 and step_clock <= 0.0:
		if swimmer.in_water:
			one_shot("swim", -25.0)
			step_clock = 0.95
		elif swimmer.is_on_floor():
			one_shot("step", -18.0 if swimmer.crouching else -10.0)
			step_clock = 0.7 if swimmer.crouching else (0.36 if swimmer.velocity.length() > 4.0 else 0.56)


func one_shot(cue: String, volume: float = -12.0, location: Vector3 = Vector3.INF) -> void:
	var path := "res://assets/audio/%s.wav" % cue
	if not ResourceLoader.exists(path):
		return
	if location.is_finite():
		var voice := AudioStreamPlayer3D.new()
		voice.stream = load(path)
		voice.bus = "Facility"
		voice.volume_db = volume
		voice.unit_size = 8.0
		voice.max_distance = 65.0
		add_child(voice)
		voice.global_position = location
		voice.finished.connect(voice.queue_free)
		voice.play()
	else:
		var voice := AudioStreamPlayer.new()
		voice.stream = load(path)
		voice.bus = "Facility"
		voice.volume_db = volume
		add_child(voice)
		voice.finished.connect(voice.queue_free)
		voice.play()


func omen(location: Vector3, strength: float) -> void:
	if omen_clock > 0.0 or not enabled:
		return
	creature_voice.global_position = location
	creature_voice.volume_db = lerpf(-13.0, -3.0, strength)
	creature_voice.play()
	omen_clock = 9.0


func start_pump(location: Vector3) -> void:
	pump_voice.global_position = location
	pump_voice.play()


func reset_sound() -> void:
	pump_voice.stop()
	creature_voice.stop()
	step_clock = 0.0
	omen_clock = 0.0


func _exit_tree() -> void:
	# Release native audio playbacks before the scene and its WAV resources leave.
	for child in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
