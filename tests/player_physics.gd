extends SceneTree
## Native controller contracts, then each ladder in the actual authored world.
## Run: godot --headless --path . --script res://tests/player_physics.gd

class WaterFixture extends Node3D:
	var ladders: Array[Vector3] = [Vector3(20.0, 0.65, 0.0)]
	func is_water(point: Vector3) -> bool:
		return absf(point.x) < 19.0 and absf(point.z) < 42.0 and point.y < 0.0 and point.y > -13.0

var player: CharacterBody3D
var fixture: WaterFixture
var failures: int = 0
var started_msec: int = Time.get_ticks_msec()
var completed_world_checks: bool = false

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > 120000:
		push_error("FAIL: physics regression exceeded 120 s; a coroutine may have aborted")
		quit(1)
	return false

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func input_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

func run() -> void:
	input_action("move_left", KEY_A)
	input_action("move_right", KEY_D)
	input_action("move_forward", KEY_W)
	input_action("move_back", KEY_S)
	input_action("sprint", KEY_SHIFT)
	input_action("crouch", KEY_CTRL)
	input_action("jump", KEY_SPACE)
	input_action("flashlight", KEY_F)
	fixture = WaterFixture.new()
	root.add_child(fixture)
	var deck := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.0, 8.0)
	collider.shape = shape
	deck.add_child(collider)
	deck.position = Vector3(20.5, 0.15, 0.0)
	fixture.add_child(deck)
	var packed: PackedScene = load("res://scenes/player.tscn")
	player = packed.instantiate()
	fixture.add_child(player)
	player.set("world", fixture)
	player.call("reset_at", Vector3(20.5, 0.72, 0.0))
	player.set("enabled", true)
	await frames(12)
	check(absf(player.position.y - 0.65) < 0.02, "feet sit on deck at y=0.65")
	Input.action_press("crouch")
	await frames(20)
	check(bool(player.get("crouching")), "crouch engaged")
	var body_collider: CollisionShape3D = player.get_node("CollisionShape3D")
	check(absf((body_collider.shape as CapsuleShape3D).height - 1.12) < 0.01, "crouch changes native capsule height")
	Input.action_release("crouch")
	await frames(20)
	check(not bool(player.get("crouching")), "stand restored when clear")
	player.call("reset_at", Vector3(0.0, -1.43, 0.0))
	await frames(120)
	check(bool(player.get("in_water")), "body enters water")
	check(not bool(player.get("submerged")), "surface eyes above water")
	check(absf(player.position.y + 1.43) < 0.03, "idle surface buoyancy stable")
	Input.action_press("crouch")
	await frames(100)
	Input.action_release("crouch")
	await frames(60)
	check(player.position.y < -3.0 and bool(player.get("submerged")), "Ctrl descends and submerges eyes")
	check(float(player.get("oxygen")) < 99.0, "underwater breath depletes")
	player.set("enabled", false)
	var paused_position: Vector3 = player.position
	var paused_oxygen: float = float(player.get("oxygen"))
	await frames(60)
	check(player.position.is_equal_approx(paused_position) and float(player.get("oxygen")) == paused_oxygen, "disabled freezes physics and drowning")
	player.set("enabled", true)
	player.call("reset_at", Vector3(18.4, -1.43, 0.0))
	await frames(5)
	check(player.call("get_climb_prompt") != "", "near-surface ladder prompt available")
	check(bool(player.call("climb_nearest")), "clear ladder path accepted")
	await frames(70)
	check(player.position.distance_to(Vector3(20.0, 0.65, 0.0)) < 0.09, "native climb reaches deck without teleport")
	check(not bool(player.get("in_water")), "climb exits water")
	Input.action_press("crouch")
	await frames(10)
	var roof := StaticBody3D.new()
	var roof_collider := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(2.0, 0.3, 2.0)
	roof_collider.shape = roof_shape
	roof.add_child(roof_collider)
	roof.position = Vector3(20.0, 2.1, 0.0)
	fixture.add_child(roof)
	await frames(3)
	Input.action_release("crouch")
	await frames(20)
	check(bool(player.get("crouching")), "overhead obstacle prevents standing")
	roof.queue_free()
	await frames(20)
	check(not bool(player.get("crouching")), "stands after overhead obstacle clears")
	var barrier := StaticBody3D.new()
	var barrier_collider := CollisionShape3D.new()
	var barrier_shape := BoxShape3D.new()
	barrier_shape.size = Vector3(0.2, 2.0, 2.0)
	barrier_collider.shape = barrier_shape
	barrier.add_child(barrier_collider)
	barrier.position = Vector3(19.35, 1.8, 0.0)
	fixture.add_child(barrier)
	player.call("reset_at", Vector3(18.4, -1.43, 0.0))
	await frames(5)
	check(not bool(player.call("climb_nearest")), "blocked climb path rejected by native sweep")
	barrier.queue_free()
	player.call("reset_at", Vector3(0.0, -4.0, 0.0))
	player.set("oxygen", 0.0)
	player.set("health", 0.1)
	await frames(5)
	check(float(player.get("health")) == 0.0 and not bool(player.get("enabled")), "oxygen exhaustion triggers death and freezes controller")
	player.call("reset_at", Vector3(20.5, 0.72, 0.0))
	check(float(player.get("health")) == 100.0 and float(player.get("oxygen")) == 100.0, "restart restores survival state")
	fixture.queue_free()
	await frames(3)
	await actual_world_ladders()
	check(completed_world_checks, "actual world ladder regression completed without coroutine abort")
	print("PLAYER_PHYSICS_FAILURES=" + str(failures))
	quit(failures)


func actual_world_ladders() -> void:
	if not FileAccess.file_exists("res://scripts/world.gd") or not ResourceLoader.exists("res://scenes/world.tscn"):
		check(false, "actual world scene and script exist for ladder regression")
		return
	var world_scene := load("res://scenes/world.tscn") as PackedScene
	if world_scene == null:
		check(false, "actual world scene loads")
		return
	var actual_world := world_scene.instantiate() as Node3D
	if actual_world == null or actual_world.get_script() == null or not actual_world.has_method("is_water"):
		check(false, "actual world script instantiated with water contract")
		if actual_world != null:
			actual_world.free()
		return
	root.add_child(actual_world)
	var player_scene := load("res://scenes/player.tscn") as PackedScene
	player = player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set("world", actual_world)
	player.set("enabled", true)
	await frames(3)
	var ladder_value: Variant = actual_world.get("ladders")
	if not ladder_value is Array:
		check(false, "actual world exposes a typed ladder array")
		player.queue_free()
		actual_world.queue_free()
		await frames(3)
		return
	var actual_ladders: Array = ladder_value
	check(actual_ladders.size() == 16, "expanded world exposes sixteen climb exits")
	for index: int in range(actual_ladders.size()):
		var destination: Vector3 = actual_ladders[index]
		var water_start := Vector3.INF
		for offset: Vector3 in [Vector3(2.2, 0, 0), Vector3(-2.2, 0, 0), Vector3(0, 0, 2.2), Vector3(0, 0, -2.2)]:
			var candidate := Vector3(destination.x + offset.x, -1.43, destination.z + offset.z)
			if bool(actual_world.call("is_water", candidate)):
				water_start = candidate
				break
		if not water_start.is_finite():
			check(false, "ladder %d has adjacent real water" % (index + 1))
			continue
		player.call("reset_at", water_start)
		await frames(5)
		check(bool(player.get("in_water")), "actual ladder %d starts inside water" % (index + 1))
		check(player.call("get_climb_prompt") != "", "actual ladder %d has reachable prompt" % (index + 1))
		check(bool(player.call("climb_nearest")), "actual ladder %d path and destination clear" % (index + 1))
		await frames(65)
		check(player.position.distance_to(destination) < 0.16, "actual ladder %d reaches deck feet" % (index + 1))
		check(player.is_on_floor() and not bool(player.get("in_water")), "actual ladder %d ends grounded outside water" % (index + 1))
	player.queue_free()
	actual_world.queue_free()
	await frames(3)
	completed_world_checks = true
