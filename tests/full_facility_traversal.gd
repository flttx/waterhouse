extends SceneTree
## Full native ten-device run. No teleport, direct operate(), health or oxygen overrides.
## Exploration difficulty supplies the real 100 s breath profile; enemies alone are disabled.

const WATCHDOG_MSEC: int = 180000
const PLAYING: int = 1
const DEAD: int = 3
const WON: int = 4
const DEVICE_ORDER: PackedStringArray = ["breaker", "valve_south", "valve_north", "archive", "annex_valve", "tier_valve", "overflow_valve", "reservoir_valve", "pump", "exit"]
const EXPECTED_STAGES: PackedInt32Array = [1, 1, 2, 3, 4, 4, 4, 5, 6, 7]

var game: Node3D
var player: PlayerController
var world: WaterhouseWorld
var navigation: WaterhouseNavigation
var devices: Dictionary
var failures: int = 0
var checks: int = 0
var completed: PackedStringArray = []
var physics_steps: int = 0
var simulated_seconds: float = 0.0
var travel_meters: float = 0.0
var minimum_oxygen: float = 100.0
var last_position: Vector3
var ladder_uses: int = 0
var climb_fallbacks: int = 0
var started_msec: int = Time.get_ticks_msec()
var started_run: bool = false
var finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() - started_msec > WATCHDOG_MSEC:
		push_error("FAIL: full facility watchdog 180 s; completed=%s feet=%s steps=%d" % [completed, player.global_position if is_instance_valid(player) else Vector3.INF, physics_steps])
		print("FULL_FACILITY_SENTINEL=FAILED_WATCHDOG")
		quit(1)
	return false


func _check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
	return condition


func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "interact"]:
		Input.action_release(action)


func _aim(direction: Vector3) -> void:
	player.rotation.y = atan2(-direction.x, -direction.z)
	var pitch := clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -1.48, 1.48)
	player.set("_pitch", pitch)
	(player.get_node("Head") as Node3D).rotation.x = pitch


func _space_clear() -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.68
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 0.9)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	query.margin = 0.0
	var space := world.get_world_3d().direct_space_state
	var hits := space.intersect_shape(query, 1)
	if not hits.is_empty():
		var collider := hits[0]["collider"] as Node3D
		return _check(false, "native capsule penetrated %s at %s (feet %s)" % [collider.get_path(), collider.global_position, player.global_position])
	var sphere := SphereShape3D.new()
	sphere.radius = 0.075
	query.shape = sphere
	query.transform = player.camera.global_transform
	hits = space.intersect_shape(query, 1)
	if not hits.is_empty():
		var collider := hits[0]["collider"] as Node3D
		return _check(false, "native camera penetrated %s at %s" % [collider.get_path(), player.camera.global_position])
	return true


func _step() -> bool:
	await physics_frame
	if not started_run:
		return true
	physics_steps += 1
	simulated_seconds += Engine.time_scale / float(Engine.physics_ticks_per_second)
	travel_meters += player.global_position.distance_to(last_position)
	last_position = player.global_position
	minimum_oxygen = minf(minimum_oxygen, player.oxygen)
	if player.health <= 0.0 or int(game.get("flow")) == DEAD:
		return _check(false, "player died during the real run; feet %s oxygen %.2f" % [player.global_position, player.oxygen])
	if physics_steps % 12 == 0 and not _space_clear():
		return false
	return failures == 0


func _frames(count: int) -> bool:
	for index in range(count):
		if not await _step():
			return false
	return true


func _move_to(target: Vector3, label: String, expect_win: bool = false) -> bool:
	_release()
	var elapsed: float = 0.0
	var timeout := maxf(15.0, player.global_position.distance_to(target) / 2.0 + 8.0)
	var checkpoint := player.global_position
	var checkpoint_clock: float = 0.0
	var stalled: float = 0.0
	while elapsed < timeout and player.enabled:
		if expect_win and int(game.get("flow")) == WON:
			break
		if player.global_position.distance_to(target) < 0.24:
			break
		_aim(target - player.global_position)
		Input.action_press("move_forward")
		if not await _step():
			_release()
			return false
		var step := Engine.time_scale / float(Engine.physics_ticks_per_second)
		elapsed += step
		checkpoint_clock += step
		if checkpoint_clock >= 0.8:
			stalled = stalled + checkpoint_clock if player.global_position.distance_to(checkpoint) < 0.08 else 0.0
			checkpoint = player.global_position
			checkpoint_clock = 0.0
			if stalled > 3.0:
				break
	_release()
	if not await _frames(4):
		return false
	var reached := player.global_position.distance_to(target) < 0.46 or (expect_win and int(game.get("flow")) == WON and player.global_position.z < -53.0)
	if not reached:
		return _check(false, "%s stalled/expired; feet %s target %s elapsed %.2f" % [label, player.global_position, target, elapsed])
	return true


func _climb_to(destination: Vector3) -> bool:
	_release()
	_aim(Vector3(destination.x - player.global_position.x, 0, destination.z - player.global_position.z))
	if not await _frames(2):
		return false
	if not _check(player.get_climb_prompt() != "", "real ladder prompt at " + str(player.global_position)):
		return false
	Input.action_press("interact")
	if not await _frames(2):
		return false
	Input.action_release("interact")
	if not bool(player.get("_climbing")) and player.global_position.y < 0.0:
		# Native Input's just-pressed state can be consumed before a headless physics tick.
		# The controller's same collision-validated E handler remains a permitted fallback.
		climb_fallbacks += 1
		if not player.climb_nearest():
			return _check(false, "E action and native climb handler rejected ladder")
	var wait_seconds: float = 0.0
	while bool(player.get("_climbing")) and wait_seconds < 2.0:
		if not await _step():
			return false
		wait_seconds += Engine.time_scale / float(Engine.physics_ticks_per_second)
	if not await _frames(5):
		return false
	ladder_uses += 1
	return _check(player.global_position.distance_to(destination) < 0.30 and player.is_on_floor() and not player.in_water, "real E climb reaches deck " + str(destination))


func _navigate_to(goal: Vector3, label: String, expect_win: bool = false) -> bool:
	if not await _step():
		return false
	var route := navigation.get_route(player.global_position, goal, player.in_water, player.oxygen)
	if route["status"] == "blocked":
		# A physically moved escape gate invalidates the previously validated graph.
		if bool(game.get("exit_started")):
			if not await _step():
				return false
			route = navigation.get_route(player.global_position, goal, player.in_water, player.oxygen)
		if route["status"] == "blocked":
			return _check(false, "%s has no native route: %s, feet %s goal %s" % [label, route["message"], player.global_position, goal])
	var points: Array[Vector3] = route["points"]
	print("FULL_ROUTE %s points=%d distance=%.1f" % [label, points.size(), float(route["distance"])])
	for index in range(points.size()):
		var next := points[index]
		var previous := player.global_position
		var ladder := navigation.is_ladder_segment(previous, next)
		if ladder and next.y > 0.1:
			if not await _climb_to(next):
				return false
		else:
			if not ladder and not navigation.is_segment_clear(previous, next):
				return _check(false, "%s returned an illegal native edge %s -> %s" % [label, previous, next])
			if not await _move_to(next, "%s waypoint %d" % [label, index], expect_win):
				return false
			if expect_win and int(game.get("flow")) == WON:
				return true
	if expect_win and int(game.get("flow")) == WON:
		return true
	if player.global_position.distance_to(goal) >= 0.24:
		if not navigation.is_segment_clear(player.global_position, goal):
			return _check(false, "safe final approach is blocked for " + label)
		return await _move_to(goal, label + " final approach", expect_win)
	return true


func _operate(id: String) -> bool:
	var device := devices[id] as WaterhouseDevice
	_release()
	_aim(device.global_position - player.camera.global_position)
	if not await _frames(3):
		return false
	if not _check(bool(device.available) and game.call("_find_device") == device, "actual 2.8 m interaction ray and prerequisite reach " + id):
		return false
	Input.action_press("interact")
	var held: float = 0.0
	while not device.completed and held < device.duration + 8.0:
		_aim(device.global_position - player.camera.global_position)
		if not await _step():
			_release()
			return false
		held += Engine.time_scale / float(Engine.physics_ticks_per_second)
	Input.action_release("interact")
	if not _check(device.completed and device.progress >= 1.0, "held E completes " + id):
		return false
	completed.append(id)
	print("FULL_DEVICE_COMPLETED id=%s stage=%d feet=%s oxygen=%.2f health=%.2f held=%.2f" % [id, int(game.get("stage")), player.global_position, player.oxygen, player.health, held])
	return true


func _wait_pressure(pump_elapsed: float) -> bool:
	Engine.time_scale = 40.0
	Engine.physics_ticks_per_second = 2400
	var wait_steps: int = 0
	while int(game.get("stage")) == 6 and wait_steps < 10000:
		if not await _step():
			return false
		wait_steps += 1
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 120
	return _check(int(game.get("stage")) == 7 and float(game.get("purge_remaining")) <= 0.0 and float(game.get("elapsed")) - pump_elapsed >= 84.9, "real 85 s pressure timer unlocks exit; physics ticks=" + str(wait_steps))


func _run() -> void:
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 120
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "real main scene loads"):
		await _finish(false)
		return
	game = scene.instantiate() as Node3D
	root.add_child(game)
	await physics_frame
	await physics_frame
	game.set("selected_difficulty", "exploration")
	game.call("start_run")
	game.call("_set_enemies_enabled", false)
	player = game.get("player") as PlayerController
	world = game.get("world") as WaterhouseWorld
	navigation = game.get("navigation") as WaterhouseNavigation
	devices = game.get("devices")
	player.head_bob_enabled = false
	last_position = player.global_position
	started_run = true
	if not await _frames(5):
		await _finish(false)
		return
	if not _check(devices.size() == 10 and player.breath_seconds == 100.0 and player.health == 100.0 and int(game.get("flow")) == PLAYING, "real exploration run starts with ten devices, 100 s breath and normal health"):
		await _finish(false)
		return
	var pump_elapsed: float = 0.0
	for index in range(DEVICE_ORDER.size()):
		var id := DEVICE_ORDER[index]
		if not await _navigate_to(world.nav_targets[id], id):
			await _finish(false)
			return
		if id == "exit" and not await _wait_pressure(pump_elapsed):
			await _finish(false)
			return
		if not await _operate(id) or not _check(int(game.get("stage")) == EXPECTED_STAGES[index], "actual stage contract after " + id):
			await _finish(false)
			return
		if id == "pump":
			pump_elapsed = float(game.get("elapsed"))
	if not _check(bool(game.get("exit_started")) and not player.enabled and int(game.get("flow")) == PLAYING, "exit E operation opens gate without awarding victory"):
		await _finish(false)
		return
	Engine.time_scale = 40.0
	Engine.physics_ticks_per_second = 2400
	var gate_steps: int = 0
	while not player.enabled and gate_steps < 800:
		if not await _step():
			await _finish(false)
			return
		gate_steps += 1
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 120
	var gate := game.get("gate") as StaticBody3D
	if not _check(player.enabled and int(game.get("flow")) == PLAYING and gate.collision_layer == 0 and gate.global_position.y >= 7.5, "actual gate tween restores walking before WON"):
		await _finish(false)
		return
	if not await _navigate_to(Vector3(0, 0.65, -54), "walk through opened north gate", true):
		await _finish(false)
		return
	var success := completed.size() == 10 and int(game.get("flow")) == WON and player.global_position.z < -53.0 and absf(player.global_position.x) < 2.4 and player.health > 0.0 and _space_clear()
	_check(success, "ten real E-operated devices and physical north-corridor crossing trigger WON alive")
	await _finish(success)


func _finish(success: bool) -> void:
	finished = true
	_release()
	print("FULL_FACILITY checks=%d failures=%d devices=%d steps=%d travel_m=%.2f simulated_s=%.2f minimum_oxygen=%.2f ladders=%d climb_fallbacks=%d wall_s=%.2f" % [checks, failures, completed.size(), physics_steps, travel_meters, simulated_seconds, minimum_oxygen, ladder_uses, climb_fallbacks, float(Time.get_ticks_msec() - started_msec) / 1000.0])
	print("FULL_FACILITY_SENTINEL=" + ("PASSED_TEN_DEVICES_AND_NATIVE_EXIT" if success and failures == 0 else "FAILED"))
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
		await process_frame
	quit(0 if success and failures == 0 else 1)
