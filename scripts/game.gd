extends Node3D
## Owns the escape contract. World, player, creature and UI have separate lifetimes.

enum Flow { TITLE, PLAYING, PAUSED, DEAD, WON, MAP }
const START := Vector3(-21.0, 0.72, 36.0)
const PURGE_SECONDS := 85.0
const DEVICE_DATA := [
	["breaker", "01 · 配电柜", "恢复维护电源", Vector3(27, 1.6, 25), 6.0, 0],
	["valve_south", "02A · 南泄压阀", "关闭南侧泄压阀", Vector3(-10, -6, 16), 12.0, 1],
	["valve_north", "02B · 北泄压阀", "关闭北侧泄压阀", Vector3(10, -8, -17), 12.0, 1],
	["archive", "03 · 安全继电器", "解除档案区安全联锁", Vector3(-48, 1.6, -25), 6.0, 2],
	["annex_valve", "04 · 过滤池调压器", "隔离过滤池压力", Vector3(51, -5, 3), 10.0, 3],
	["tier_valve", "05A · 阶梯池泄压阀", "关闭阶梯池泄压阀", Vector3(-82, -5, 13), 10.0, 4],
	["overflow_valve", "05B · 溢流池泄压阀", "关闭北溢流池泄压阀", Vector3(108, -6, -49), 10.0, 4],
	["reservoir_valve", "05C · 地下库泄压阀", "关闭地下水库泄压阀", Vector3(137, -7, 43), 10.0, 4],
	["pump", "06 · 排水控制", "启动排水泵", Vector3(-28, 1.6, -25), 8.0, 5],
	["exit", "07 · 北侧闸门", "解锁逃生闸门", Vector3(0, 1.6, -44), 5.0, 7],
]
var world: WaterhouseWorld
var player: PlayerController
var creature: WaterhouseCreature
var hud: WaterhouseHUD
var soundscape: WaterhouseSoundscape
var flow: Flow = Flow.TITLE
var stage: int = 0
var valves_closed: int = 0
var outer_valves_closed: int = 0
var purge_remaining: float = PURGE_SECONDS
var elapsed: float = 0.0
var decoys: int = 3
var devices: Dictionary[String, WaterhouseDevice] = {}
var focused_device: WaterhouseDevice
var threat: float = 0.0
var title_camera: Camera3D
var gate: StaticBody3D
var gate_mesh: MeshInstance3D
var base_fog_density: float = 0.008
var base_fog_color := Color(0.07, 0.14, 0.17)
var base_ambient_energy: float = 0.42
var was_in_water: bool = false
var exit_started: bool = false
var gate_tween: Tween
var mechanical_clock: float = 0.0
var pump_noise_clock: float = 0.0
var settings := {"brightness": 1.12, "volume": 0.75, "sensitivity": 0.0022, "bob": 1.0, "grain": 1.0, "difficulty": "survival"}
var enemies: Array[CharacterBody3D] = []
var enemy_threats: Dictionary[int, float] = {}
var selected_difficulty: String = "survival"
var run_difficulty: String = "survival"
var navigation: WaterhouseNavigation
var navigation_clock: float = 0.0
var navigation_result: Dictionary = {"points": [], "action": "", "status": "route"}
var map_return_flow: Flow = Flow.PLAYING


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	world = preload("res://scenes/world.tscn").instantiate() as WaterhouseWorld
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = preload("res://scenes/player.tscn").instantiate() as PlayerController
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.world = world
	add_child(player)
	player.reset_at(START)
	player.rotation.y = -0.5
	player.enabled = false
	creature = preload("res://scenes/leviathan.tscn").instantiate() as WaterhouseCreature
	creature.process_mode = Node.PROCESS_MODE_PAUSABLE
	creature.player = player
	add_child(creature)
	creature.enabled = false
	enemies.append(creature)
	_build_enemies()
	navigation = WaterhouseNavigation.new()
	navigation.configure(world)
	_build_devices()
	_build_gate()
	_build_notes()
	title_camera = Camera3D.new()
	title_camera.position = Vector3(-17.8, 3.2, 39)
	title_camera.fov = 72.0
	title_camera.far = 220.0
	add_child(title_camera)
	title_camera.look_at(Vector3(5, 1.0, -12))
	title_camera.make_current()
	hud = WaterhouseHUD.new()
	add_child(hud)
	soundscape = WaterhouseSoundscape.new()
	add_child(soundscape)
	player.died.connect(_on_death)
	player.noise_emitted.connect(_on_player_noise)
	for enemy: CharacterBody3D in enemies:
		enemy.connect("omen", _on_omen)
		enemy.connect("threat_changed", _track_enemy_threat.bind(enemy.get_instance_id()))
		enemy.connect("attack_started", _on_enemy_attack.bind(enemy))
	hud.start_requested.connect(start_run)
	hud.restart_requested.connect(start_run)
	hud.resume_requested.connect(resume_run)
	hud.quit_requested.connect(func() -> void: get_tree().quit())
	hud.setting_changed.connect(_on_setting)
	hud.difficulty_changed.connect(_on_difficulty_changed)
	hud.map_requested.connect(open_map)
	hud.map_close_requested.connect(close_map)
	if world.environment != null:
		base_fog_density = world.environment.fog_density
		base_fog_color = world.environment.fog_light_color
		base_ambient_energy = world.environment.ambient_light_energy
	_load_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--play" in OS.get_cmdline_user_args():
		start_run()


func _setup_input() -> void:
	var actions := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "jump": [KEY_SPACE],
		"interact": [KEY_E], "flashlight": [KEY_F], "decoy": [KEY_Q], "pause": [KEY_ESCAPE], "map": [KEY_M],
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func _build_devices() -> void:
	for data: Array in DEVICE_DATA:
		var device := WaterhouseDevice.new()
		device.device_id = data[0]
		device.title = data[1]
		device.description = data[2]
		device.position = data[3]
		device.duration = data[4]
		device.required_stage = data[5]
		add_child(device)
		device.activated.connect(_on_device_activated)
		devices[device.device_id] = device
	_refresh_devices()


func _build_gate() -> void:
	gate = StaticBody3D.new()
	gate.name = "EscapeGate"
	gate.position = Vector3(0, 2.95, -46)
	gate.collision_layer = 1
	add_child(gate)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.6, 0.35)
	shape.shape = box
	gate.add_child(shape)
	gate_mesh = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	gate_mesh.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.22, 0.22)
	material.metallic = 0.65
	material.roughness = 0.42
	gate_mesh.material_override = material
	gate.add_child(gate_mesh)
	for i in 8:
		var rib := MeshInstance3D.new()
		var rib_mesh := BoxMesh.new()
		rib_mesh.size = Vector3(3.8, 0.07, 0.09)
		rib.mesh = rib_mesh
		rib.position = Vector3(0, float(i) * 0.5 - 1.8, 0.22)
		rib.material_override = material
		gate.add_child(rib)
	var exit_label := Label3D.new()
	exit_label.text = "E X I T   /   出口"
	exit_label.position = Vector3(0, 5.7, -45.7)
	exit_label.font_size = 58
	exit_label.pixel_size = 0.008
	exit_label.modulate = Color(0.40, 0.83, 0.63)
	add_child(exit_label)


func _build_notes() -> void:
	var note := Label3D.new()
	note.text = "蓄 水 厅  0 4\n维修撤离规程\n\n配电 → 主池两阀 → 西档案联锁\n东过滤调压 → 外环三池泄压\n西泵房排水 → 北闸门撤离\n\nM  设施平面图\n设备操作会发声。请勿独自下水。"
	note.font_size = 38
	note.pixel_size = 0.008
	note.outline_size = 5
	note.modulate = Color(0.73, 0.79, 0.66)
	note.position = Vector3(-23.6, 2.65, 35)
	note.rotation.y = PI / 2.0
	add_child(note)
	for entry: Array in [["东侧配电 →", Vector3(0, 2.2, 44), 0.0], ["← 泵房  /  北侧出口 ↑", Vector3(-23.6, 2.6, -15), PI / 2.0], ["断桥 / 使用梯子", Vector3(22.2, 1.5, 8), 0.0]]:
		var label := Label3D.new()
		label.text = entry[0]
		label.position = entry[1]
		label.rotation.y = entry[2]
		label.font_size = 40
		label.pixel_size = 0.008
		label.modulate = Color(0.67, 0.62, 0.40)
		add_child(label)


func start_run() -> void:
	if gate_tween != null and gate_tween.is_valid():
		gate_tween.kill()
	get_tree().paused = false
	flow = Flow.PLAYING
	stage = 0
	valves_closed = 0
	outer_valves_closed = 0
	purge_remaining = PURGE_SECONDS
	elapsed = 0.0
	run_difficulty = selected_difficulty
	var profile := WaterhouseDifficulty.profile(run_difficulty)
	decoys = int(profile["decoys"])
	player.breath_seconds = float(profile["breath_seconds"])
	threat = 0.0
	exit_started = false
	pump_noise_clock = 0.0
	was_in_water = false
	focused_device = null
	navigation_clock = 0.0
	navigation_result = {"points": [], "action": "", "status": "route"}
	enemy_threats.clear()
	for device: WaterhouseDevice in devices.values():
		device.reset_device()
	_refresh_devices()
	for decoy in get_tree().get_nodes_in_group("decoys"):
		decoy.queue_free()
	gate.position.y = 2.95
	gate.collision_layer = 1
	player.reset_at(START)
	player.rotation.y = -0.5
	player.enabled = true
	player.camera.make_current()
	for enemy: CharacterBody3D in enemies:
		enemy.call("apply_difficulty", profile)
		enemy.call("reset_creature")
		enemy.set("enabled", true)
		enemy.set("pressure", 0.0)
	soundscape.reset_sound()
	soundscape.enabled = true
	hud.effect.set_shader_parameter("injury", 0.0)
	hud.effect.set_shader_parameter("underwater", 0.0)
	hud.show_page("game")
	hud.notify("东侧配电柜仍有备用电源。先沿南侧通道过去。", 9.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_run() -> void:
	if flow != Flow.PLAYING:
		return
	flow = Flow.PAUSED
	get_tree().paused = true
	hud.show_page("pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_run() -> void:
	if flow != Flow.PAUSED:
		return
	get_tree().paused = false
	flow = Flow.PLAYING
	hud.show_page("game")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if flow == Flow.PLAYING:
			pause_run()
		elif flow == Flow.PAUSED:
			resume_run()
		elif flow == Flow.MAP:
			close_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		if flow == Flow.MAP:
			close_map()
		elif flow in [Flow.PLAYING, Flow.PAUSED]:
			open_map()
		get_viewport().set_input_as_handled()
	elif flow == Flow.PLAYING and event.is_action_pressed("decoy"):
		_throw_decoy()


func _process(delta: float) -> void:
	if flow != Flow.PLAYING:
		return
	elapsed += delta
	if stage == 6:
		purge_remaining = maxf(0.0, purge_remaining - delta)
		pump_noise_clock -= delta
		if pump_noise_clock <= 0.0:
			_broadcast_noise(devices["pump"].global_position, 0.8)
			pump_noise_clock = 9.0
		if purge_remaining <= 0.0:
			stage = 7
			_refresh_devices()
			hud.notify("排水压力已建立。北侧闸门现在可以手动打开。", 9.0)
			soundscape.one_shot("relay", -10.0)
	if player.in_water and not was_in_water:
		soundscape.one_shot("splash", -14.0, player.global_position)
	was_in_water = player.in_water
	hud.update_status(player, objective_text(), decoys, threat, delta, elapsed)
	_update_guidance()
	soundscape.update(delta, player, threat)
	_update_environment(delta)


func _physics_process(delta: float) -> void:
	if flow != Flow.PLAYING:
		return
	navigation_clock -= delta
	if navigation_clock <= 0.0:
		var goal := current_goal()
		if goal != null:
			navigation_result = navigation.get_route(player.global_position, _navigation_goal(goal), player.in_water, player.oxygen)
		navigation_clock = 0.55
	if exit_started:
		if player.enabled and player.global_position.z < -53.0 and absf(player.global_position.x) < 2.4:
			_on_win()
		return
	focused_device = _find_device()
	if focused_device != null:
		if focused_device.completed:
			hud.show_interaction("已完成 · " + focused_device.description)
		elif not focused_device.available:
			hud.show_interaction(_locked_message(focused_device))
		else:
			hud.show_interaction("按住 E · " + focused_device.description, focused_device.progress)
			if Input.is_action_pressed("interact"):
				focused_device.operate(delta)
				mechanical_clock -= delta
				if mechanical_clock <= 0.0:
					_on_player_noise(focused_device.global_position, 0.72)
					soundscape.one_shot("valve" if focused_device.is_valve else "relay", -17.0, focused_device.global_position)
					mechanical_clock = 1.9
	else:
		var climb_prompt := player.get_climb_prompt()
		hud.show_interaction(climb_prompt)
		if not climb_prompt.is_empty() and Input.is_action_just_pressed("interact"):
			if player.climb_nearest():
				soundscape.one_shot("step", -16.0)


func _find_device() -> WaterhouseDevice:
	var origin := player.camera.global_position
	var end := origin - player.camera.global_basis.z * 2.8
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 4)
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit["collider"]
	if collider.has_meta("device"):
		return collider.get_meta("device") as WaterhouseDevice
	return null


func _refresh_devices() -> void:
	for device: WaterhouseDevice in devices.values():
		device.set_available(device.required_stage == stage and not device.completed)


func _locked_message(device: WaterhouseDevice) -> String:
	if device.device_id == "exit" and stage == 6:
		return "压力不足 · 排水还需 %d 秒" % ceili(purge_remaining)
	match device.device_id:
		"valve_south", "valve_north": return "没有维护电源 · 先恢复东侧配电"
		"archive": return "安全联锁未上电 · 先关闭主池两阀"
		"annex_valve": return "过滤池锁定 · 先解除档案安全联锁"
		"tier_valve", "overflow_valve", "reservoir_valve": return "外环设备锁定 · 先隔离东过滤池"
		"pump": return "外环压力仍未隔离 · 先关闭三处外池阀门"
		"exit": return "闸门锁定 · 先启动西侧排水泵"
	return "设备离线"


func _on_device_activated(device: WaterhouseDevice) -> void:
	match device.device_id:
		"breaker":
			stage = 1
			hud.notify("维护电源恢复。两处琥珀色阀门，在南北深水区。", 9.0)
			_broadcast_noise(device.global_position, 1.0)
			_set_pressure(0.25)
		"valve_south", "valve_north":
			valves_closed += 1
			if valves_closed == 2:
				stage = 2
				hud.notify("主池已隔离。进入西侧档案区，解除安全联锁。", 8.0)
			else:
				hud.notify("一处泄压阀已关闭。另一处仍在深水中。", 7.0)
			_broadcast_noise(device.global_position, 0.9)
		"archive":
			stage = 3
			hud.notify("安全联锁已解除。前往东侧过滤池下潜调压。", 8.0)
		"annex_valve":
			stage = 4
			hud.notify("外环管线已接入：阶梯池、北溢流池、地下水库都需要泄压。", 10.0)
		"tier_valve", "overflow_valve", "reservoir_valve":
			outer_valves_closed += 1
			if outer_valves_closed == 3:
				stage = 5
				hud.notify("三处外池已隔离。返回西侧泵房启动排水。", 8.0)
			else:
				hud.notify("外环隔离进度 %d / 3。打开地图寻找下一处泄压阀。" % outer_valves_closed, 7.0)
			_broadcast_noise(device.global_position, 1.0)
		"pump":
			stage = 6
			purge_remaining = PURGE_SECONDS
			_set_pressure(1.0)
			soundscape.start_pump(device.global_position)
			hud.notify("泵已启动。返回北侧闸门，等待压力建立。", 8.0)
		"exit":
			exit_started = true
			player.enabled = false
			_set_enemies_enabled(false)
			soundscape.one_shot("gate", -9.0, gate.global_position)
			gate.collision_layer = 0
			gate_tween = create_tween()
			gate_tween.tween_property(gate, "position:y", 7.6, 3.0).set_trans(Tween.TRANS_SINE)
			gate_tween.tween_callback(_on_gate_opened)
	_refresh_devices()
	navigation_clock = 0.0
	soundscape.one_shot("relay", -14.0, device.global_position)


func objective_text() -> String:
	if exit_started:
		return "08  穿过北侧撤离通道，离开水房"
	match stage:
		0: return "01  恢复东侧配电柜的维护电源"
		1:
			if valves_closed == 0: return "02  下潜关闭两处泄压阀  ·  0 / 2"
			return "02  关闭%s泄压阀  ·  1 / 2" % ("北侧深水" if devices["valve_south"].completed else "南侧水下")
		2: return "03  进入西侧观察档案区，解除安全联锁"
		3: return "04  前往东侧过滤池，下潜操作调压器"
		4: return "05  关闭三处外池泄压阀  ·  %d / 3" % outer_valves_closed
		5: return "06  返回西侧泵房，启动排水泵"
		6: return "07  返回北侧闸门  ·  压力建立还需 %d 秒" % ceili(purge_remaining)
		7: return "07  按住 E 打开北侧闸门，逃离水房"
	return ""


func _on_player_noise(pos: Vector3, loudness: float) -> void:
	if flow == Flow.PLAYING:
		_broadcast_noise(pos, loudness)


func _on_omen(pos: Vector3, strength: float) -> void:
	if flow != Flow.PLAYING:
		return
	soundscape.omen(pos, strength)
	if world.water_material != null:
		world.water_material.set_shader_parameter("ripple_origin", pos)
		world.water_material.set_shader_parameter("ripple_strength", strength)


func _throw_decoy() -> void:
	if decoys <= 0:
		hud.notify("金属诱饵已用尽。", 3.0)
		return
	decoys -= 1
	var decoy := preload("res://scripts/decoy.gd").new()
	add_child(decoy)
	decoy.add_to_group("decoys")
	decoy.global_position = player.camera.global_position - player.camera.global_basis.z * 0.6
	decoy.linear_velocity = -player.camera.global_basis.z * 10.0 + Vector3.UP * 2.2
	decoy.landed.connect(func(pos: Vector3) -> void:
		if flow != Flow.PLAYING: return
		_broadcast_noise(pos, 1.8)
		soundscape.one_shot("metal", -4.0, pos))


func _update_environment(delta: float) -> void:
	if world.environment == null:
		return
	var target_density: float = 0.075 if player.submerged else base_fog_density
	var target_color := Color(0.015, 0.13, 0.135) if player.submerged else base_fog_color
	var blend := minf(1.0, delta * 3.0)
	world.environment.fog_density = lerpf(world.environment.fog_density, target_density, blend)
	world.environment.fog_light_color = world.environment.fog_light_color.lerp(target_color, blend)
	world.environment.ambient_light_energy = lerpf(world.environment.ambient_light_energy, base_ambient_energy * (0.68 if player.submerged else 1.0), blend)


func _on_death(reason: String) -> void:
	if flow != Flow.PLAYING:
		return
	flow = Flow.DEAD
	player.enabled = false
	_set_enemies_enabled(false)
	soundscape.enabled = false
	soundscape.reset_sound()
	hud.result_reason = reason
	hud.show_page("dead")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_win() -> void:
	if flow != Flow.PLAYING or not exit_started:
		return
	flow = Flow.WON
	player.enabled = false
	_set_enemies_enabled(false)
	soundscape.enabled = false
	soundscape.reset_sound()
	hud.result_time = elapsed
	hud.show_page("won")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_gate_opened() -> void:
	if flow != Flow.PLAYING or not exit_started:
		return
	player.enabled = true
	hud.show_interaction("")
	hud.notify("闸门已打开。穿过通道，回到空气中。", 7.0)


func _on_setting(key: String, value: float) -> void:
	settings[key] = value
	match key:
		"brightness": hud.effect.set_shader_parameter("brightness", value)
		"volume": soundscape.set_volume(value)
		"sensitivity": player.mouse_sensitivity = value
		"bob": player.head_bob_enabled = value > 0.5
		"grain": hud.effect.set_shader_parameter("grain_enabled", value)
	_save_settings()


func _save_settings() -> void:
	var config := ConfigFile.new()
	for setting: String in settings:
		config.set_value("preferences", setting, settings[setting])
	var error := config.save("user://settings.cfg")
	if error != OK:
		push_warning("Unable to save player settings: %s" % error_string(error))


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		for key: String in settings:
			var value: Variant = config.get_value("preferences", key, settings[key])
			if value is float or value is int:
				settings[key] = float(value)
			elif key == "difficulty" and value is String:
				settings[key] = WaterhouseDifficulty.normalize_key(value)
	hud.brightness = clampf(settings["brightness"], 1.0, 1.5)
	hud.volume = clampf(settings["volume"], 0.0, 1.0)
	hud.sensitivity = clampf(settings["sensitivity"], 0.0008, 0.005)
	hud.bob = settings["bob"] > 0.5
	hud.reduced_grain = settings["grain"] < 0.5
	player.mouse_sensitivity = hud.sensitivity
	player.head_bob_enabled = hud.bob
	soundscape.set_volume(hud.volume)
	hud.effect.set_shader_parameter("brightness", hud.brightness)
	hud.effect.set_shader_parameter("grain_enabled", 0.0 if hud.reduced_grain else 1.0)
	selected_difficulty = WaterhouseDifficulty.normalize_key(str(settings["difficulty"]))
	hud.set_difficulty(selected_difficulty)


func _build_enemies() -> void:
	creature.set_meta("species", "leviathan")
	var scenes := {"angler": "res://scenes/angler.tscn", "crab": "res://scenes/crab.tscn", "whale": "res://scenes/whale.tscn", "colossus": "res://scenes/colossus.tscn"}
	for species: String in scenes:
		var path: String = scenes[species]
		if not ResourceLoader.exists(path):
			push_error("Required creature scene missing: " + path)
			continue
		var packed := load(path) as PackedScene
		var enemy := packed.instantiate() as CharacterBody3D
		_register_enemy(enemy, species)
	var hunter := WaterhouseHazard.new()
	hunter.species = "hunter"
	hunter.patrol_points = world.canal_patrol_points.duplicate()
	if not hunter.patrol_points.is_empty():
		hunter.home = hunter.patrol_points[0]
	_register_enemy(hunter, "hunter")
	var lurker := WaterhouseHazard.new()
	lurker.species = "lurker"
	lurker.home = Vector3(86, -2.2, -43)
	_register_enemy(lurker, "lurker")
	for pos: Vector3 in [Vector3(-32, -3, -83), Vector3(80, -3, 73)]:
		var drifter := WaterhouseHazard.new()
		drifter.species = "drifter"
		drifter.home = pos
		_register_enemy(drifter, "drifter")


func _register_enemy(enemy: CharacterBody3D, species: String) -> void:
	enemy.name = species.capitalize() + str(enemies.size())
	enemy.set("player", player)
	enemy.set("enabled", false)
	if enemy is WaterhouseHazard:
		(enemy as WaterhouseHazard).world = world
	enemy.set_meta("species", species)
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemies.append(enemy)


func _set_enemies_enabled(value: bool) -> void:
	for enemy: CharacterBody3D in enemies:
		enemy.set("enabled", value)


func _set_pressure(value: float) -> void:
	for enemy: CharacterBody3D in enemies:
		enemy.set("pressure", value)


func _broadcast_noise(pos: Vector3, loudness: float) -> void:
	for enemy: CharacterBody3D in enemies:
		enemy.call("hear_noise", pos, loudness)


func _track_enemy_threat(value: float, instance_id: int) -> void:
	enemy_threats[instance_id] = clampf(value, 0.0, 1.0)
	threat = 0.0
	for amount: float in enemy_threats.values():
		threat = maxf(threat, amount)


func _on_enemy_attack(enemy: CharacterBody3D) -> void:
	if flow == Flow.PLAYING:
		soundscape.one_shot("metal" if enemy.get_meta("species") == "crab" else "splash", -8.0, enemy.global_position)


func current_goal() -> WaterhouseDevice:
	if exit_started or stage == 6:
		return devices["exit"]
	var nearest: WaterhouseDevice
	var best: float = INF
	for device: WaterhouseDevice in devices.values():
		if not device.available or device.completed:
			continue
		var distance := player.global_position.distance_squared_to(device.global_position)
		if distance < best:
			nearest = device
			best = distance
	return nearest


func _navigation_goal(device: WaterhouseDevice) -> Vector3:
	if exit_started:
		return Vector3(0, 0.65, -54)
	if world.nav_targets.has(device.device_id):
		return world.nav_targets[device.device_id]
	var point := device.global_position + Vector3(0, 0, 2)
	point.y = device.global_position.y - 1.62 if device.global_position.y < 0.0 else 0.65
	return point


func get_map_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var goal := current_goal()
	for device: WaterhouseDevice in devices.values():
		markers.append({"id": device.device_id, "title": device.title, "position": device.global_position, "completed": device.completed, "available": device.available, "current": device == goal})
	return markers


func _monster_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: CharacterBody3D in enemies:
		result.append({"position": enemy.global_position, "name": enemy.name, "small": str(enemy.get_meta("species")) in ["drifter", "lurker"]})
	return result


func _route_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for value: Variant in navigation_result.get("points", []):
		if value is Vector3:
			points.append(value)
	return points


func _update_guidance() -> void:
	var goal := current_goal()
	var completed := 0
	for device: WaterhouseDevice in devices.values():
		completed += 1 if device.completed else 0
	var goal_pos: Vector3 = player.global_position if goal == null else goal.global_position
	var caption: String = "" if goal == null else goal.description
	if exit_started:
		goal_pos = Vector3(0, 0.65, -54)
		caption = "走出北侧撤离通道"
	hud.update_goal(caption, goal_pos, player.global_position, player.rotation.y, world.region_at(player.global_position), run_difficulty, completed, devices.size())
	var action: String = navigation_result.get("action", "continue")
	var status: String = navigation_result.get("status", "route")
	if stage == 6:
		action = "wait"
		status = "waiting"
	hud.update_navigation(world.map_regions, world.water_regions, get_map_markers(), player.global_position, player.rotation.y, run_difficulty, _route_points(), _monster_markers(), action, status, player.camera.global_position.y - player.global_position.y)


func open_map() -> void:
	if flow not in [Flow.PLAYING, Flow.PAUSED]:
		return
	map_return_flow = flow
	flow = Flow.MAP
	get_tree().paused = true
	hud.show_map(world.map_regions, world.water_regions, get_map_markers(), player.global_position, player.rotation.y, _monster_markers(), _route_points(), player.camera.global_position.y - player.global_position.y)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_map() -> void:
	if flow != Flow.MAP:
		return
	flow = map_return_flow
	get_tree().paused = flow == Flow.PAUSED
	hud.show_page("pause" if flow == Flow.PAUSED else "game")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if flow == Flow.PAUSED else Input.MOUSE_MODE_CAPTURED


func _on_difficulty_changed(key: String) -> void:
	if flow != Flow.TITLE:
		return
	selected_difficulty = WaterhouseDifficulty.normalize_key(key)
	settings["difficulty"] = selected_difficulty
	_save_settings()
