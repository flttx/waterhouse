extends SceneTree

class TestPlayer extends CharacterBody3D:
	var in_water: bool = true
	var light_on: bool = true
	var dead: bool = false
	var health: float = 100.0
	func take_damage(amount: float, _reason: String) -> void:
		health -= amount
		dead = health <= 0.0

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			push_error("GIANTS WATCHDOG: no final sentinel")
			quit(2))
	if OS.get_cmdline_user_args().has("--visual"):
		await _render_models()
		return
	var fixture := Node3D.new()
	root.add_child(fixture)
	if OS.get_cmdline_user_args().has("--actual"):
		fixture.add_child((load("res://scenes/world.tscn") as PackedScene).instantiate())
	else:
		_add_pool(fixture, Rect2(98, 19, 78, 48), 22.0)
		_add_pool(fixture, Rect2(-103, -13, 42, 58), 24.0)
	var player := TestPlayer.new()
	player.collision_layer = 2
	player.collision_mask = 1
	fixture.add_child(player)
	var whale := (load("res://scenes/whale.tscn") as PackedScene).instantiate() as WaterhouseWhale
	fixture.add_child(whale)
	whale.player = player
	var colossus := (load("res://scenes/colossus.tscn") as PackedScene).instantiate() as WaterhouseColossus
	fixture.add_child(colossus)
	colossus.player = player
	for frame in 5:
		await physics_frame
	_check(whale._navigation_ready and whale._graph.get_point_count() > 300, "whale: native deep-basin graph built")
	_check(whale._skeleton != null and whale._bone_rest.size() == whale._skeleton.get_bone_count() and whale._bone_rest.size() > 25, "whale: original skeleton posed along travelled curve")
	_check(not whale._skin_materials.is_empty() and not colossus._skin_materials.is_empty(), "both giants preserve actual GLB textures")
	var model_bounds := _model_bounds(colossus)
	_check(model_bounds.size.y > 17.0 and model_bounds.size.y < 20.0 and model_bounds.position.y > -24.0, "actual transformed colossus mesh fits its 20-metre art and pool-depth contract")
	print("COLOSSUS MODEL BOUNDS ", model_bounds)
	_check(_body_clear(whale, "HeadCollision") and _body_clear(colossus, "BodyCollision"), "actual giant spawn shapes fit pool floors and walls")
	whale.state = WaterhouseCreature.State.PATROL
	player.global_position = whale.global_position + Vector3(2.0, -0.75, 0.0)
	whale._refresh_player_properties()
	for sample in 50:
		whale._sense_player(0.16)
	_check(whale.awareness == 0.0 and whale.state == WaterhouseCreature.State.PATROL, "blind whale never detects silent flashlight user")
	whale.enabled = true
	whale.hear_noise(player.global_position, 1.2)
	whale._noise_cooldown = 0.0
	whale.hear_noise(player.global_position, 1.2)
	whale.enabled = false
	_check(whale.state == WaterhouseCreature.State.CHASE, "repeated audible disturbance produces blind pursuit")
	var heard := whale._last_seen
	player.global_position.x += 10.0
	for sample in 25:
		whale._sense_player(0.16)
	whale._update_state(0.1)
	_check(whale._last_seen == heard, "blind hunter retains heard location without tracking silent movement")
	for sample in 10:
		whale._sense_player(0.16)
	whale._update_state(0.1)
	_check(whale.state == WaterhouseCreature.State.SEARCH, "lost sound leads to search instead of omniscient pursuit")
	player.global_position = whale.global_position + Vector3(2.0, -0.75, 0.0)
	whale.state = WaterhouseCreature.State.CHASE
	whale._attack_left = -1.0
	await physics_frame
	whale._update_attack(0.1)
	_check(whale._attack_left > 1.2 and player.health == 100.0, "blind whale has a readable bite windup")
	var wall := _box(fixture, whale.global_position + Vector3(1.0, 0.0, 0.0), Vector3(0.4, 9.0, 6.0))
	await physics_frame
	whale._update_attack(2.0)
	_check(player.health == 100.0, "whale bite cannot pass an actual concrete wall")
	wall.queue_free()
	await physics_frame
	player.global_position = Vector3(0.0, -6.0, 0.0)
	whale.state = WaterhouseCreature.State.CHASE
	whale._update_state(0.1)
	_check(whale.state == WaterhouseCreature.State.SEARCH, "whale stops at the edge of its own basin")
	colossus.global_position.y = -6.0
	colossus.state = WaterhouseColossus.State.WATCH
	player.global_position = colossus.global_position + WaterhouseColossus.MOUTH + Vector3(0.0, -0.75, -6.0)
	colossus._refresh_player_properties()
	wall = _box(fixture, colossus.global_position + Vector3(0, 0, -6.0), Vector3(10, 20, 1))
	await physics_frame
	for sample in 30:
		colossus._sense_player(0.16)
	_check(colossus.awareness == 0.0, "colossus many-eye detection respects concrete cover")
	wall.queue_free()
	await physics_frame
	for sample in 50:
		colossus._sense_player(0.16)
	colossus._update_state(0.1)
	_check(colossus.state == WaterhouseColossus.State.WINDUP and colossus._attack_left > 1.8 and player.health == 100.0, "surfaced colossus locks a target before a long telegraph")
	var locked := colossus._attack_target
	player.global_position.x += 5.0
	colossus._update_state(2.0)
	colossus._state_age = 0.3
	colossus._update_state(0.1)
	_check(player.health == 100.0 and colossus._attack_target == locked, "lateral movement dodges the fixed tentacle strike")
	player.global_position = locked - Vector3.UP * 0.75
	colossus.state = WaterhouseColossus.State.WATCH
	colossus._last_saw_player = true
	colossus.awareness = 1.0
	colossus._last_seen = locked
	colossus._update_state(0.1)
	colossus._update_state(2.0)
	colossus._state_age = 0.3
	colossus._update_state(0.1)
	_check(player.dead, "completed tentacle strike applies real player damage")
	colossus._state_age = 1.1
	colossus._update_state(0.1)
	_check(colossus.state == WaterhouseColossus.State.RETREAT, "colossus gives a retreat window after every strike")
	whale.apply_difficulty({"attack_damage": 45.0, "attack_windup": 1.35, "speed_multiplier": 0.8})
	colossus.apply_difficulty({"attack_damage": 45.0, "attack_windup": 1.35, "quiet_multiplier": 1.3})
	_check(whale.attack_damage == 45.0 and colossus.attack_windup == 1.35, "difficulty parameters propagate to both distinctive attacks")
	whale.apply_difficulty({})
	colossus.apply_difficulty({})
	whale.player = null
	colossus.player = null
	whale.reset_creature()
	colossus.reset_creature()
	_check(whale.awareness == 0 and colossus.awareness == 0 and colossus._attack_left < 0, "retry resets both giant encounter states")
	await _simulate(whale, colossus)
	_finished = true
	print("GIANTS_REACHED_FINAL: ", _checks - _failures, "/", _checks, " passed")
	quit(1 if _failures else 0)

func _simulate(whale: WaterhouseWhale, colossus: WaterhouseColossus) -> void:
	var old_ticks := Engine.physics_ticks_per_second
	var old_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 2400
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 40.0
	whale.enabled = true
	colossus.enabled = true
	var previous := whale.global_position
	var origin := colossus.global_position
	var distance: float = 0.0
	var surfaced: bool = false
	var overlaps: int = 0
	var pose_safe: bool = true
	var simulated: float = 0.0
	while simulated < 120.0:
		await physics_frame
		simulated += whale.get_physics_process_delta_time()
		distance += previous.distance_to(whale.global_position)
		previous = whale.global_position
		surfaced = surfaced or colossus.global_position.y - origin.y > 3.0
		if not _body_clear(whale, "HeadCollision") or not _body_clear(colossus, "BodyCollision"):
			overlaps += 1
		for point in whale._history:
			pose_safe = pose_safe and WaterhouseWhale.POOL.has_point(Vector2(point.x, point.z))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_physics_steps_per_frame = old_steps
	whale.enabled = false
	colossus.enabled = false
	_check(distance > 100.0, "120 native seconds: blind whale patrol makes sustained physical progress")
	_check(surfaced, "120 native seconds: colossus surfaces and sinks autonomously")
	_check(overlaps == 0, "120 native seconds: real giant body shapes never overlap pool walls/floor")
	_check(pose_safe, "120 native seconds: entire whale spine history remains inside its basin")
	var before := whale.global_position
	var age := colossus._state_age
	for frame in 5:
		await physics_frame
	_check(whale.global_position == before and colossus._state_age == age, "pause freezes both giants")
	print("GIANTS METRICS whale_travel=", snappedf(distance, 0.1), " shape_overlaps=", overlaps, " time=", simulated)

func _body_clear(body: CharacterBody3D, collision_name: String) -> bool:
	var collision := body.get_node(collision_name) as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _model_bounds(body: Node3D) -> AABB:
	var result := AABB()
	var first: bool = true
	for node in body.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		for corner in 8:
			var point := mesh_instance.global_transform * bounds.get_endpoint(corner)
			if first:
				result.position = point
				first = false
			else:
				result = result.expand(point)
	return result

func _add_pool(parent: Node3D, bounds: Rect2, depth: float) -> void:
	var center := bounds.get_center()
	_box(parent, Vector3(center.x, -depth - 0.5, center.y), Vector3(bounds.size.x, 1, bounds.size.y))
	for side in [-0.5, 0.5]:
		_box(parent, Vector3(center.x + bounds.size.x * side, -depth * 0.5, center.y), Vector3(1, depth + 4, bounds.size.y + 1))
		_box(parent, Vector3(center.x, -depth * 0.5, center.y + bounds.size.y * side), Vector3(bounds.size.x + 1, depth + 4, 1))

func _box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)

func _render_models() -> void:
	root.mode = Window.MODE_MINIMIZED
	for name in ["whale", "colossus"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1200, 800)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.035, 0.055, 0.07)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.42, 0.51, 0.55)
		environment.ambient_light_energy = 0.75
		var environment_node := WorldEnvironment.new()
		environment_node.environment = environment
		viewport.add_child(environment_node)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		light.light_energy = 2.4
		viewport.add_child(light)
		var creature := (load("res://scenes/" + name + ".tscn") as PackedScene).instantiate() as CharacterBody3D
		viewport.add_child(creature)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(178, 3, 79) if name == "whale" else Vector3(-61, 0, -5)
		camera.look_at(Vector3(140, -12, 44) if name == "whale" else Vector3(-88, -12, 27))
		camera.fov = 43.0
		camera.current = true
		for frame in 12:
			await process_frame
		RenderingServer.force_draw(false)
		_check(viewport.get_texture().get_image().save_png("res://artifacts/" + name + "_preview.png") == OK, name + ": actual GPU preview saved")
		viewport.queue_free()
		await process_frame
	_finished = true
	print("GIANTS_VISUAL_REACHED_FINAL")
	quit(1 if _failures else 0)
