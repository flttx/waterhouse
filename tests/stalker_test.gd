extends SceneTree

class TestPlayer extends CharacterBody3D:
	var in_water: bool = true
	var light_on: bool = false
	var dead: bool = false
	var health: float = 100.0
	func take_damage(amount: float, _reason: String, _source: Node3D = null) -> void:
		health -= amount
		dead = health <= 0.0

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _watchdog() -> void:
	if not _finished:
		push_error("STALKER WATCHDOG: test did not reach final sentinel")
		quit(2)

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(_watchdog)
	if OS.get_cmdline_user_args().has("--visual"):
		await _render_models()
		return
	for species in ["angler", "crab"]:
		await _test_species(species)
	_finished = true
	print("STALKER_REACHED_FINAL: ", _checks - _failures, "/", _checks, " passed")
	quit(1 if _failures else 0)

func _test_species(species: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var wet := species == "angler"
	var center := Vector3(51.5, -5.5, 2.0) if wet else Vector3(-45.0, 2.98, -25.0)
	var blocker := _add_box(world, Vector3(51.5, -5.0, 0.0) if wet else Vector3(-45.0, 1.85, -25.0), Vector3(2.0, 7.0, 5.0) if wet else Vector3(2.0, 2.4, 4.0))
	_add_box(world, Vector3(51.5, -10.5, 2.0) if wet else Vector3(-45.0, 0.15, -25.0), Vector3(29.0, 1.0, 32.0) if wet else Vector3(24.0, 1.0, 22.0))
	var player := TestPlayer.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.in_water = wet
	world.add_child(player)
	var creature := (load("res://scenes/" + species + ".tscn") as PackedScene).instantiate() as WaterhouseStalker
	world.add_child(creature)
	creature.player = player
	await _frames(5)
	_check(creature._navigation_ready and creature._graph.get_point_count() > 12, species + ": native obstacle navigation built")
	_check(creature._skeleton != null and creature._skeleton.get_bone_count() >= 27 and creature._animation != null and not creature._walk_clip.is_empty(), species + ": original rig and locomotion source present")
	if not wet:
		_check(creature._legs.size() == 8 and not creature._animation.active, "crab: broken source preset replaced with eight planted native skeletal chains")
	_check(not creature._skin_materials.is_empty() and creature._skin_materials[0].get_shader_parameter("skin_texture") != null, species + ": original textures preserved")
	creature.global_position = center + Vector3(-7.0, 0.0, 0.0)
	player.global_position = center + Vector3(7.0, -0.75 if wet else -2.33, 0.0)
	creature._heading = Vector3.RIGHT
	creature.state = WaterhouseStalker.State.PATROL
	creature._refresh_player_properties()
	await _frames(2)
	_check(not creature._has_line_of_sight(creature._player_position()), species + ": native wall blocks vision")
	for sample in 30:
		creature._sense_player(0.16)
	_check(creature.awareness == 0.0, species + ": occluded player not detected")
	creature.enabled = true
	creature.hear_noise(player.global_position, 1.0)
	creature.enabled = false
	_check(creature.state == WaterhouseStalker.State.PATROL, species + ": concrete muffles distant noise")
	blocker.queue_free()
	await _frames(2)
	creature._noise_cooldown = 0.0
	creature.enabled = true
	creature.hear_noise(player.global_position, 0.05)
	creature.enabled = false
	_check(creature.state == WaterhouseStalker.State.PATROL, species + ": quiet distant steps do not trigger investigation")
	creature.enabled = true
	creature.hear_noise(player.global_position, 1.2)
	creature.enabled = false
	_check(creature.state == WaterhouseStalker.State.INVESTIGATE, species + ": loud unobstructed noise triggers investigation")
	creature._heading = Vector3.RIGHT
	player.global_position.x = creature.global_position.x + 6.0
	player.light_on = true
	await _frames(2)
	for sample in 40:
		creature._sense_player(0.16)
	_check(creature.state == WaterhouseStalker.State.CHASE, species + ": sustained actual sight produces pursuit")
	player.in_water = not wet
	creature._update_state(0.1)
	_check(creature.state == WaterhouseStalker.State.SEARCH, species + ": leaving required medium ends pursuit")
	player.in_water = wet
	player.global_position.x = creature.global_position.x + 2.0
	creature.state = WaterhouseStalker.State.CHASE
	creature._attack_left = -1.0
	creature._attack_cooldown = 0.0
	await _frames(2)
	creature._update_attack(0.1)
	_check(creature._attack_left >= 0.9 and player.health == 100.0, species + ": readable attack windup before damage")
	creature._update_attack(0.2)
	_check(player.health == 100.0, species + ": windup allows escape")
	player.global_position.x += 8.0
	await _frames(2)
	creature._update_attack(2.0)
	_check(player.health == 100.0 and creature.state == WaterhouseStalker.State.RETREAT, species + ": dodged strike retreats")
	player.global_position.x = creature.global_position.x + 2.0
	creature.state = WaterhouseStalker.State.CHASE
	creature._attack_left = -1.0
	creature._attack_cooldown = 0.0
	await _frames(2)
	creature._update_attack(0.1)
	creature._update_attack(2.0)
	_check(player.dead, species + ": connected strike calls real damage")
	player.dead = false
	player.health = 100.0
	creature.state = WaterhouseStalker.State.CHASE
	creature._last_saw_player = false
	creature._lost_seconds = 4.0
	creature._update_state(0.1)
	_check(creature.state == WaterhouseStalker.State.SEARCH, species + ": losing sight searches remembered target")
	creature._state_age = 11.0
	creature._update_state(0.1)
	_check(creature.state == WaterhouseStalker.State.RETREAT, species + ": bounded search gives quiet interval")
	creature.apply_difficulty({"speed_multiplier": 0.8, "detection_multiplier": 0.65, "attack_damage": 45.0, "attack_windup": 1.35, "quiet_multiplier": 1.3})
	var easy_speed := creature.speed_multiplier
	var easy_range := creature.detection_multiplier
	var easy_windup := creature.attack_windup
	creature.apply_difficulty({"speed_multiplier": 1.16, "detection_multiplier": 1.35, "attack_windup": 0.65})
	_check(creature.speed_multiplier > easy_speed and creature.detection_multiplier > easy_range and creature.attack_windup < easy_windup, species + ": difficulty ordering changes active AI")
	creature.apply_difficulty({"speed_multiplier": "bad", "attack_damage": INF})
	_check(creature.speed_multiplier == 1.0 and creature.attack_damage == 100.0, species + ": malformed difficulty falls back safely")
	creature.reset_creature()
	_check(creature.state == WaterhouseStalker.State.DORMANT and creature.awareness == 0.0 and creature._attack_left < 0.0, species + ": reset clears all attack state")
	creature.player = null
	creature.state = WaterhouseStalker.State.PATROL
	creature._goal = center + Vector3(-6.0, 0.0, -3.0)
	creature.enabled = true
	var origin := creature.global_position
	var previous := origin
	var travel: float = 0.0
	Engine.time_scale = 4.0
	var safe := true
	for frame in 150:
		await physics_frame
		travel += creature.global_position.distance_to(previous)
		previous = creature.global_position
		safe = safe and creature._within_territory(creature.global_position)
	Engine.time_scale = 1.0
	creature.enabled = false
	_check(travel > 3.0, species + ": patrol makes actual physical progress")
	_check(safe, species + ": physical locomotion remains inside territory")
	if not wet:
		var foot_clearance := creature.global_position.y - 2.3 - 0.65
		_check(creature.is_on_floor() and foot_clearance >= -0.002 and foot_clearance < 0.05, "crab: capsule contact and model feet share actual ground within physics safe margin")
	var paused_position := creature.global_position
	var age := creature._state_age
	await _frames(5)
	_check(creature.global_position == paused_position and creature._state_age == age, species + ": pause freezes simulation")
	world.queue_free()
	await _frames(2)

func _add_box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)

func _render_models() -> void:
	root.mode = Window.MODE_MINIMIZED
	for species in ["angler", "crab"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1100, 750)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.035, 0.055, 0.07)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.42, 0.51, 0.55)
		environment.ambient_light_energy = 0.7
		var environment_node := WorldEnvironment.new()
		environment_node.environment = environment
		world.add_child(environment_node)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		light.light_energy = 2.0
		world.add_child(light)
		var creature := (load("res://scenes/" + species + ".tscn") as PackedScene).instantiate() as WaterhouseStalker
		world.add_child(creature)
		creature.set_physics_process(false)
		creature.global_position = Vector3(0, 1.85 if species == "angler" else 2.3, 0)
		if creature._animation != null:
			creature._animation.speed_scale = 1.0
			creature._animation.seek(0.8, true)
			if species == "crab":
				creature._animation.active = false
				creature._skeleton.reset_bone_poses()
				for leg in creature._legs:
					leg["foot"] = creature.global_transform * (leg["tip"] as Vector3)
					leg["step"] = -1.0
				for sample in 25:
					creature.global_position += Vector3(0.012, 0, -0.012)
					creature._pose_crab_legs(1.0 / 60.0, 0.017)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(7.0, 6.0, -9.0)
		camera.look_at(Vector3(0.0, 1.8 if species == "angler" else 0.8, 0.0))
		camera.fov = 45.0
		camera.current = true
		for frame in 12:
			await process_frame
		RenderingServer.force_draw(false)
		var result := viewport.get_texture().get_image().save_png("res://artifacts/" + species + "_preview.png")
		_check(result == OK, species + ": GPU preview saved")
		viewport.queue_free()
		await process_frame
	_finished = true
	print("STALKER_VISUAL_REACHED_FINAL")
	quit(1 if _failures else 0)
