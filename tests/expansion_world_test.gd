extends SceneTree
## Native input traverses both expanded wings continuously from the original spawn.
## Add -- visual to capture the new areas with the active GPU renderer.

var world: WaterhouseWorld
var player: PlayerController
var failures: int = 0
var checked_steps: int = 0
var started_msec: int = Time.get_ticks_msec()


func _initialize() -> void:
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > 300000:
		push_error("FAIL: expansion traversal exceeded 300 s; unfinished coroutine")
		quit(1)
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame


func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump"]:
		Input.action_release(action)


func _aim(direction: Vector3) -> void:
	player.rotation.y = atan2(-direction.x, -direction.z)
	var pitch := clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -1.48, 1.48)
	player.set("_pitch", pitch)
	(player.get_node("Head") as Node3D).rotation.x = pitch


func _body_clear() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27
	shape.height = 1.68
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(player.global_basis, player.global_position + Vector3.UP * 0.9)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	query.margin = 0.0
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _move_to(target: Vector3, label: String, timeout: float = 40.0) -> bool:
	_release()
	var elapsed: float = 0.0
	var checkpoint := player.global_position
	var checkpoint_clock: float = 0.0
	var stalled: float = 0.0
	var penetration: bool = false
	while elapsed < timeout and player.global_position.distance_to(target) > 0.28 and player.enabled:
		_aim(target - player.global_position)
		Input.action_press("move_forward")
		await physics_frame
		var step := Engine.time_scale / float(Engine.physics_ticks_per_second)
		elapsed += step
		checkpoint_clock += step
		checked_steps += 1
		if checked_steps % 12 == 0 and not _body_clear():
			penetration = true
			break
		if checkpoint_clock >= 0.8:
			stalled = stalled + checkpoint_clock if player.global_position.distance_to(checkpoint) < 0.08 else 0.0
			checkpoint = player.global_position
			checkpoint_clock = 0.0
			if stalled > 3.0:
				break
	_release()
	await _frames(4)
	var reached := player.global_position.distance_to(target) < 0.44 and not penetration
	_check(reached, "%s via native input, feet %s" % [label, player.global_position])
	return reached


func _route(points: Array[Vector3], label: String) -> bool:
	for index in range(points.size()):
		if not await _move_to(points[index], "%s %d" % [label, index + 1]):
			return false
	return true


func _climb(index: int) -> bool:
	var destination := world.ladders[index]
	var approach_x: float = 38.0 if destination.x < 51.5 else 65.0
	if index < 4:
		approach_x = signf(destination.x) * 18.3
	elif index >= 8:
		var approaches: Array[float] = [-99, -65, 80, 136, 102, 172, -110, 182]
		approach_x = approaches[index - 8]
	if not await _move_to(Vector3(approach_x, -1.43, destination.z), "ladder %d swim approach" % (index + 1)):
		return false
	_check(player.get_climb_prompt() != "", "ladder %d proximity prompt" % (index + 1))
	var accepted := player.climb_nearest()
	_check(accepted, "ladder %d collision-validated climb" % (index + 1))
	if not accepted:
		return false
	await _frames(35)
	var dry := player.global_position.distance_to(destination) < 0.18 and player.is_on_floor() and not player.in_water
	_check(dry and _body_clear(), "ladder %d reaches real dry deck" % (index + 1))
	return dry


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "flashlight"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	world = preload("res://scenes/world.tscn").instantiate() as WaterhouseWorld
	root.add_child(world)
	player = preload("res://scenes/player.tscn").instantiate() as PlayerController
	world.add_child(player)
	player.world = world
	player.head_bob_enabled = false
	player.reset_at(Vector3(-21, 0.7, 36))
	_check(world.ladders.size() == 16, "sixteen authored ladders retain four original destinations")
	_check(world.water_regions.size() == 10 and world.map_regions.size() == 19, "map publishes all dry areas and ten water footprints")
	_check(world.is_water(Vector3(51, -5, 3)) and not world.is_water(Vector3(51, -11.1, 3)), "annex water respects 10 m basin floor")
	_check(not world.is_water(Vector3(35.5, -1, 3)) and not world.is_water(Vector3(-48, -1, -25)), "dry wings never become swimming volumes")
	_check(world.region_at(Vector3(-48, 1.6, -25)) == "西侧封存档案库" and world.region_at(Vector3(51, -5, 3)) == "第八过滤池", "regional location lookup matches authored objectives")
	_check(world.annex_water_material.get_shader_parameter("pool_center") == Vector2(51.5, 2), "annex foam and analytic reflections use their own pool center")
	_check(world.is_water(Vector3(-82, -23, 13)) and not world.is_water(Vector3(-82, -25.1, 13)), "tier baths honor the colossus 24 m deep well")
	_check(world.is_water(Vector3(137, -21, 43)) and not world.is_water(Vector3(137, -23.1, 43)), "reservoir honors the whale 22 m deep basin")
	_check(world.navigation_points.size() > 100 and world.navigation_edges.size() > 100 and world.navigation_ladder_edges.size() == 16, "facility graph includes authored dry, swim, dive and ladder routes")
	if "visual" in OS.get_cmdline_user_args():
		await _visuals()
		quit(failures)
		return
	if "outer" in OS.get_cmdline_user_args():
		await _outer_traversal()
		quit(failures)
		return
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 120
	player.enabled = true
	await _frames(10)
	_check(player.is_on_floor(), "original southern spawn settles on native floor")
	if not await _route([Vector3(-21, 0.65, -25), Vector3(-28, 0.65, -25), Vector3(-36, 0.65, -25), Vector3(-46, 0.65, -25)], "main hall to pump room and archive"):
		quit(maxi(1, failures))
		return
	_check(world.region_at(player.global_position) == "西侧封存档案库" and _body_clear(), "archive central aisle is physically reachable")
	if not await _route([Vector3(-28, 0.65, -25), Vector3(-21, 0.65, -25), Vector3(-21, 0.65, -44), Vector3(21, 0.65, -44), Vector3(21, 0.65, -5), Vector3(21, -1.43, 0)], "return and traverse original broken deck"):
		quit(maxi(1, failures))
		return
	if not await _climb(1):
		quit(maxi(1, failures))
		return
	if not await _route([Vector3(21, 0.65, 25), Vector3(28, 0.65, 25), Vector3(35.5, 0.65, 25), Vector3(35.5, 0.65, 19.5), Vector3(35.5, 0.65, 8), Vector3(38, -1.43, 8)], "power room to east corridor and filter basin"):
		quit(maxi(1, failures))
		return
	if not await _climb(6):
		quit(maxi(1, failures))
		return
	if not await _route([Vector3(35.5, 0.65, -8), Vector3(38, -1.43, -8)], "west annex deck") or not await _climb(4):
		quit(maxi(1, failures))
		return
	if not await _route([Vector3(38, -1.43, -8), Vector3(65, -1.43, -8)], "annex clear north swim lane") or not await _climb(5):
		quit(maxi(1, failures))
		return
	if not await _route([Vector3(67.5, 0.65, 8), Vector3(65, -1.43, 8)], "east annex deck") or not await _climb(7):
		quit(maxi(1, failures))
		return
	if not await _route([Vector3(65, -1.43, 8), Vector3(51, -1.43, 8), Vector3(51, -6.4, 5.3)], "reach submerged bypass bay"):
		quit(maxi(1, failures))
		return
	_check(player.submerged and player.health > 0.0 and _body_clear(), "bypass can be approached underwater within breathable dive time")
	if not await _move_to(Vector3(51, -1.43, 5.3), "rise vertically above bypass without a roof"):
		quit(maxi(1, failures))
		return
	_check(not player.submerged and player.oxygen > 0.0, "filter objective supports immediate surface recovery")
	print("EXPANSION_NATIVE_STEPS=", checked_steps)
	_release()
	world.queue_free()
	await process_frame
	quit(failures)


func _outer_traversal() -> void:
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 120
	player.enabled = true
	await _frames(10)
	if not await _outer_route([Vector3(-21, 0.65, -25), Vector3(-28, 0.65, -24), Vector3(-36, 0.65, -24), Vector3(-54, 0.65, -24), Vector3(-60, 0.65, -25), Vector3(-107.5, 0.65, -25), Vector3(-107.5, 0.65, 15), Vector3(-101.5, 0.65, 15), Vector3(-101.5, 0.65, 1), Vector3(-99, -1.43, 1)], "west archive connector and tier baths"):
		return
	if not await _climb(8):
		return
	if not await _outer_route([Vector3(-99, -1.43, 1), Vector3(-82, -1.43, 20), Vector3(-82, -6.62, 20), world.nav_targets["tier_valve"], Vector3(-82, -1.43, 15.4)], "tier valve open-roof dive") or not await _climb(9):
		return
	if not await _outer_route([Vector3(-62.5, 0.65, 43.5), Vector3(-101.5, 0.65, 43.5), Vector3(-101.5, 0.65, 15), Vector3(-107.5, 0.65, 15), Vector3(-107.5, 0.65, -78.5), Vector3(138.5, 0.65, -78.5), Vector3(138.5, 0.65, -75.5), Vector3(138.5, 0.65, -49), Vector3(137.25, 0.65, -49), Vector3(125.5, 3.36, -49), Vector3(123, 3.35, -49)], "north canal to overflow and walkable diving tower"):
		return
	_check(player.is_on_floor() and player.global_position.y > 3.25, "native slope reaches 3 m diving platform")
	if not await _outer_route([Vector3(125.5, 3.36, -49), Vector3(137.25, 0.65, -49), Vector3(138.5, 0.65, -49), Vector3(138.5, 0.65, -60), Vector3(136, -1.43, -60), Vector3(108, -1.43, -42), Vector3(108, -7.62, -42), world.nav_targets["overflow_valve"], Vector3(108, -1.43, -46.6)], "overflow task and immediate surfacing"):
		return
	if not await _climb(10) or not await _move_to(Vector3(80, -1.43, -49), "re-enter overflow after western ladder") or not await _climb(11):
		return
	if not await _outer_route([Vector3(138.5, 0.65, -28.5), Vector3(138.5, 0.65, -8), Vector3(174.5, 0.65, -8), Vector3(174.5, 0.65, 20.5), Vector3(174.5, 0.65, 54), Vector3(172, -1.43, 54), Vector3(137, -1.43, 50), Vector3(137, -8.62, 50), world.nav_targets["reservoir_valve"], Vector3(137, -1.43, 45.4)], "east gallery junction to reservoir task"):
		return
	if not await _climb(12) or not await _move_to(Vector3(102, -1.43, 36), "re-enter reservoir after western ladder") or not await _climb(13):
		return
	if not await _outer_route([Vector3(174.5, 0.65, 65.5), Vector3(174.5, 0.65, 68.5), Vector3(179.5, 0.65, 68.5), Vector3(179.5, 0.65, -8), Vector3(182, -1.43, -8)], "south dry junction and east canal") or not await _climb(15):
		return
	if not await _outer_route([Vector3(182, -1.43, -8), Vector3(184, -1.43, -8), Vector3(184, -1.43, 73), Vector3(-112, -1.43, 73), Vector3(-112, -1.43, -25)], "connected canal water loop") or not await _climb(14):
		return
	_check(world.region_at(player.global_position) == "西环形输水渠" and player.health > 0.0, "outer facility closes a real playable dry-and-water loop")
	print("OUTER_FACILITY_NATIVE_STEPS=", checked_steps)
	_release()
	world.queue_free()
	await process_frame


func _outer_route(points: Array[Vector3], label: String) -> bool:
	for index in range(points.size()):
		var timeout := maxf(40.0, player.global_position.distance_to(points[index]) / 2.0 + 5.0)
		if not await _move_to(points[index], "%s %d" % [label, index + 1], timeout):
			return false
	return true


func _visuals() -> void:
	root.size = Vector2i(1440, 900)
	player.enabled = false
	player.camera.current = false
	var camera := Camera3D.new()
	camera.fov = 78.0
	camera.far = 180.0
	world.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	camera.position = Vector3(-35.2, 2.25, -23.4)
	camera.look_at(Vector3(-49.5, 2.2, -28.5))
	await _capture("res://artifacts/expansion_archive.png")
	camera.position = Vector3(35.6, 2.3, 17.5)
	camera.look_at(Vector3(54, 1.6, -8))
	await _capture("res://artifacts/expansion_filter_pool.png")
	camera.position = Vector3(40.2, 2.25, 25)
	camera.look_at(Vector3(61, 2.25, 23))
	await _capture("res://artifacts/expansion_filter_corridor.png")
	world.environment.fog_density = 0.055
	world.environment.fog_light_color = Color(0.015, 0.10, 0.115)
	camera.position = Vector3(51, -3.8, 10.5)
	camera.look_at(Vector3(51, -5.1, 3))
	await _capture("res://artifacts/expansion_filter_underwater.png")
	world.environment.fog_density = 0.005
	world.environment.fog_light_color = Color(0.035, 0.075, 0.085)
	camera.position = Vector3(-107.5, 2.25, 40)
	camera.look_at(Vector3(-111.5, 1.6, -58))
	await _capture("res://artifacts/expansion_ring_canal.png")
	camera.position = Vector3(-101.5, 2.25, 28)
	camera.look_at(Vector3(-74, 2.5, -1))
	await _capture("res://artifacts/expansion_tier_baths.png")
	camera.position = Vector3(138.5, 2.25, -41)
	camera.look_at(Vector3(114, 3.8, -53))
	await _capture("res://artifacts/expansion_overflow_tower.png")
	camera.position = Vector3(174.5, 2.25, 38)
	camera.look_at(Vector3(126, 3.8, 45))
	await _capture("res://artifacts/expansion_reservoir.png")
	world.queue_free()
	await process_frame


func _capture(path: String) -> void:
	for index in range(100):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	_check(result == OK and image.get_width() == 1440, "GPU capture " + path)
	print("EXPANSION_RENDER_FPS=", Performance.get_monitor(Performance.TIME_FPS))
