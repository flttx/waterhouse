extends SceneTree
## Input-driven physical traversal and the game's actual 2.8 m interaction ray.
## Initial placement is game.start_run(); traversal never teleports the player.
## Run: godot --headless --path . --script res://tests/traversal_test.gd

var game: Node3D
var player: CharacterBody3D
var camera: Camera3D
var world: Node3D
var failures: int = 0
var checked_steps: int = 0
var started_msec: int = Time.get_ticks_msec()
var hit_devices: Dictionary[String, bool] = {}
var completed_exit_checks: bool = false


func _initialize() -> void:
	call_deferred("run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > 180000:
		push_error("FAIL: traversal exceeded 180 s; a coroutine may have aborted")
		quit(1)
	return false


func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame


func release_movement() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "sprint", "interact"]:
		Input.action_release(action)


func aim_direction(direction: Vector3) -> void:
	player.rotation.y = atan2(-direction.x, -direction.z)
	var pitch: float = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.set("_pitch", clampf(pitch, -1.48, 1.48))
	var head := player.get_node("Head") as Node3D
	head.rotation.x = clampf(pitch, -1.48, 1.48)


func body_clear() -> bool:
	# A slightly inset copy ignores legitimate floor/slide contact, while detecting
	# penetration into native static geometry throughout every traversal segment.
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


func move_to(target: Vector3, label: String, tolerance: float = 0.35, timeout: float = 45.0, expect_win: bool = false) -> bool:
	release_movement()
	var elapsed: float = 0.0
	var stalled_time: float = 0.0
	var last_checkpoint: Vector3 = player.global_position
	var checkpoint_clock: float = 0.0
	var penetration: bool = false
	while elapsed < timeout:
		if expect_win and int(game.get("flow")) == 4:
			break
		if not expect_win and player.global_position.distance_to(target) <= tolerance:
			break
		if not bool(player.get("enabled")):
			break
		aim_direction(target - player.global_position)
		Input.action_press("move_forward")
		await physics_frame
		var step: float = Engine.time_scale / float(Engine.physics_ticks_per_second)
		elapsed += step
		checkpoint_clock += step
		checked_steps += 1
		if checked_steps % 12 == 0 and not body_clear():
			penetration = true
			break
		if checkpoint_clock >= 0.8:
			stalled_time = stalled_time + checkpoint_clock if player.global_position.distance_to(last_checkpoint) < 0.08 else 0.0
			last_checkpoint = player.global_position
			checkpoint_clock = 0.0
			if stalled_time > 3.0:
				break
	release_movement()
	await frames(4)
	var reached: bool = (int(game.get("flow")) == 4 and player.global_position.z < -53.0) if expect_win else player.global_position.distance_to(target) < tolerance + 0.12
	check(reached and not penetration, "%s reachable through native movement (feet %s)" % [label, str(player.global_position)])
	return reached and not penetration


func ray_hits(device_id: String) -> void:
	var devices: Dictionary = game.get("devices")
	var device := devices[device_id] as Node3D
	aim_direction(device.global_position - camera.global_position)
	await frames(3)
	var hit: bool = game.call("_find_device") == device
	check(hit, "2.8 m interaction ray hits " + device_id)
	if hit:
		hit_devices[device_id] = true


func climb_at(ladder_index: int) -> bool:
	var ladders: Array = world.get("ladders")
	var destination: Vector3 = ladders[ladder_index]
	var reached: bool = await move_to(Vector3(signf(destination.x) * 18.3, -1.43, destination.z), "ladder %d water approach" % (ladder_index + 1))
	if not reached:
		return false
	check(player.call("get_climb_prompt") != "", "ladder %d surface prompt" % (ladder_index + 1))
	var accepted: bool = bool(player.call("climb_nearest"))
	check(accepted, "ladder %d physical climb accepted" % (ladder_index + 1))
	if not accepted:
		return false
	await frames(35)
	check(player.global_position.distance_to(destination) < 0.18 and player.is_on_floor(), "ladder %d reached dry deck" % (ladder_index + 1))
	return player.global_position.distance_to(destination) < 0.18


func route(points: Array[Vector3], label: String) -> bool:
	for index: int in range(points.size()):
		if not await move_to(points[index], "%s %d" % [label, index + 1]):
			return false
	return true


func camera_clear() -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.075
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = camera.global_transform
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	query.margin = 0.0
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func exit_corridor_test() -> void:
	# Earlier devices are physical/ray probes, so unlock only the exit prerequisite.
	# The exit device, gate tween, collision changes and win trigger all run normally.
	var devices: Dictionary = game.get("devices")
	var exit_device := devices["exit"] as Node3D
	game.set("stage", 7)
	game.call("_refresh_devices")
	check(bool(exit_device.get("available")), "escape prerequisites unlock the real exit device")
	check(bool(exit_device.call("operate", 6.0)), "real exit device starts gate sequence")
	check(bool(exit_device.get("completed")) and not bool(player.get("enabled")), "gate sequence holds player while the shutter rises")
	var previous_time_scale: float = Engine.time_scale
	Engine.time_scale = 40.0
	var wait_steps: int = 0
	while not bool(player.get("enabled")) and wait_steps < 1000:
		await physics_frame
		wait_steps += 1
	Engine.time_scale = previous_time_scale
	print("GATE_OPEN_WAIT_FRAMES=" + str(wait_steps))
	var resumed: bool = bool(player.get("enabled")) and int(game.get("flow")) == 1
	check(resumed, "actual gate tween restores walking before victory")
	if not resumed:
		return
	var gate := game.get("gate") as StaticBody3D
	check(gate.collision_layer == 0 and gate.global_position.y > 7.5, "opened gate physically clears the north passage")
	check(int(game.get("flow")) != 4, "opening gate alone does not trigger victory")
	if not await route([Vector3(1.4, 0.65, -43.4), Vector3(1.4, 0.65, -46), Vector3(0, 0.65, -46.6)], "walk around console into opened north passage"):
		return
	check(body_clear() and camera_clear(), "native body and camera clear the real north wall opening")
	if not await move_to(Vector3(0, 0.65, -53.1), "walk evacuation corridor across actual win threshold", 0.02, 20.0, true):
		return
	check(int(game.get("flow")) == 4 and player.global_position.z < -53.0 and absf(player.global_position.x) < 2.4, "physical evacuation threshold triggers WON")
	check(body_clear() and camera_clear() and float(player.get("health")) > 0.0, "escaped body and camera remain outside corridor walls")
	completed_exit_checks = true


func run() -> void:
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 120
	if not FileAccess.file_exists("res://scripts/world.gd"):
		check(false, "actual world script exists")
		quit(failures)
		return
	var main := load("res://scenes/main.tscn") as PackedScene
	if main == null:
		check(false, "main scene loads")
		quit(failures)
		return
	game = main.instantiate() as Node3D
	if game == null or game.get_script() == null or not game.has_method("start_run"):
		check(false, "main scene instantiates valid game script")
		if game != null:
			game.free()
		quit(failures)
		return
	root.add_child(game)
	await frames(4)
	game.call("start_run")
	game.call("_set_enemies_enabled", false)
	player = game.get("player") as CharacterBody3D
	camera = player.get("camera") as Camera3D
	world = game.get("world") as Node3D
	var creature := game.get("creature") as Node3D
	creature.set("enabled", false)
	creature.set_physics_process(false)
	creature.set_process(false)
	var soundscape := game.get("soundscape") as Node
	soundscape.set("enabled", false)
	player.set("head_bob_enabled", false)
	await frames(5)
	check(player.is_on_floor(), "game.start_run grounds player on southern deck")
	var success: bool = await route([
		Vector3(-21, 0.65, 44), Vector3(21, 0.65, 44),
		Vector3(21, 0.65, 25), Vector3(25.0, 0.65, 25),
	], "southern bridge and breaker room")
	if success:
		await ray_hits("breaker")
	if success:
		success = await route([Vector3(21, 0.65, 25), Vector3(21, 0.65, 12), Vector3(21, -1.43, 2)], "eastern broken walkway forces water entry")
	if success:
		check(bool(player.get("in_water")) and not player.is_on_floor(), "broken eastern walkway places player in actual water volume")
		success = await route([Vector3(21, -1.43, -2), Vector3(18, -1.43, -2)], "swim through break into main pool")
	if success:
		success = await route([Vector3(-10, -1.43, 18.0), Vector3(-10, -7.62, 18.0)], "southern valve dive")
	if success:
		check(bool(player.get("submerged")), "southern valve requires submerged approach")
		await ray_hits("valve_south")
	if success:
		success = await route([Vector3(-10, -1.43, 18), Vector3(18.0, -1.43, 12)], "surface and regain breath")
	if success:
		await frames(120)
		check(float(player.get("oxygen")) > 98.0, "surface restores oxygen before northern dive")
		success = await route([Vector3(18.0, -1.43, -15), Vector3(10, -1.43, -15), Vector3(10, -9.62, -15)], "swim past broken eastern walkway and northern dive")
	if success:
		check(bool(player.get("submerged")), "northern valve requires deep-water approach")
		await ray_hits("valve_north")
	if success:
		success = await route([Vector3(10, -1.43, -15)], "surface after northern valve")
	if success:
		success = await climb_at(3)
	if success:
		success = await route([Vector3(21, 0.65, -43), Vector3(-21, 0.65, -43), Vector3(-21, 0.65, -25), Vector3(-26, 0.65, -25)], "northern bridge and pump room")
	if success:
		await ray_hits("pump")
	if success:
		success = await route([Vector3(-21, 0.65, -25), Vector3(-21, 0.65, -43), Vector3(-1.8, 0.65, -43.4)], "exit gate approach")
	if success:
		await ray_hits("exit")
	check(success, "continuous physical route visits all five escape devices")
	check(hit_devices.size() == 5, "all five real interaction rays were asserted")
	if success:
		await exit_corridor_test()
	check(completed_exit_checks, "root traversal completed gate and evacuation assertions without coroutine abort")
	release_movement()
	print("TRAVERSAL_PHYSICS_STEPS=" + str(checked_steps))
	print("TRAVERSAL_FAILURES=" + str(failures))
	player.set("enabled", false)
	game.set_process(false)
	game.set_physics_process(false)
	game.queue_free()
	await frames(4)
	# Audio playback resources are released by the mixer on its next native tick.
	await create_timer(0.25, true, false, true).timeout
	game = null
	player = null
	camera = null
	world = null
	call_deferred("quit", failures)
