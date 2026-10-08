extends SceneTree
## Actual authored world, actual imported skins and actual physics shapes.
## Accelerated clock retains 1/60-second integration, with a real-time watchdog.

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			push_error("MULTI CREATURE WATCHDOG: missing final sentinel")
			quit(2))
	var fixture := Node3D.new()
	root.add_child(fixture)
	fixture.add_child((load("res://scenes/world.tscn") as PackedScene).instantiate())
	var creatures: Array[CharacterBody3D] = []
	for name in ["leviathan", "angler", "crab", "whale", "colossus"]:
		var creature := (load("res://scenes/" + name + ".tscn") as PackedScene).instantiate() as CharacterBody3D
		fixture.add_child(creature)
		creatures.append(creature)
		creature.set("enabled", true)
	for frame in 5:
		await physics_frame
	for creature in creatures:
		if creature is WaterhouseColossus:
			_check((creature as WaterhouseColossus)._arms.size() == 2, "Colossus: native strike tentacles ready")
		else:
			_check(bool(creature.get("_navigation_ready")), String(creature.name) + ": real-world native navigation ready")
	var previous: Array[Vector3] = []
	var travel: Array[float] = []
	var overlaps: Array[int] = []
	var safe: Array[bool] = []
	var pose_safe: Array[bool] = []
	for creature in creatures:
		previous.append(creature.global_position)
		travel.append(0.0)
		overlaps.append(0)
		safe.append(true)
		pose_safe.append(true)
	var ticks := Engine.physics_ticks_per_second
	var steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 2400
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 40.0
	var simulated: float = 0.0
	var max_delta: float = 0.0
	var pose_frame: int = 0
	while simulated < 120.0:
		await physics_frame
		var delta := creatures[0].get_physics_process_delta_time()
		simulated += delta
		max_delta = maxf(max_delta, delta)
		pose_frame += 1
		for index in creatures.size():
			var creature := creatures[index]
			travel[index] += creature.global_position.distance_to(previous[index])
			previous[index] = creature.global_position
			var collision := creature.get_node("HeadCollision" if creature.has_node("HeadCollision") else "BodyCollision") as CollisionShape3D
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = collision.shape
			query.transform = collision.global_transform
			query.collision_mask = 1
			query.exclude = [creature.get_rid()]
			query.margin = 0.0
			var hits := creature.get_world_3d().direct_space_state.intersect_shape(query, 1)
			if not hits.is_empty():
				overlaps[index] += 1
				if overlaps[index] < 3:
					print("BODY OVERLAP ", creature.name, " ", creature.global_position, " ", (hits[0]["collider"] as Node).name)
			if creature is WaterhouseStalker:
				safe[index] = safe[index] and bool(creature.call("_within_territory", creature.global_position))
			elif creature is WaterhouseWhale:
				safe[index] = safe[index] and WaterhouseWhale.POOL.has_point(Vector2(creature.global_position.x, creature.global_position.z))
			elif creature is WaterhouseColossus:
				safe[index] = safe[index] and WaterhouseColossus.POOL.has_point(Vector2(creature.global_position.x, creature.global_position.z))
			else:
				safe[index] = safe[index] and absf(creature.global_position.x) < 19.0 and absf(creature.global_position.z) < 42.0 and creature.global_position.y < 0.0 and creature.global_position.y > -13.0
			if pose_frame % 30 == 0 and not creature is WaterhouseColossus:
				var skeleton := creature.get("_skeleton") as Skeleton3D
				for bone in skeleton.get_bone_count():
					var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
					pose_safe[index] = pose_safe[index] and pose.origin.is_finite() and pose.origin.distance_to(creature.global_position) < (35.0 if creature is WaterhouseCreature else 12.0)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = ticks
	Engine.max_physics_steps_per_frame = steps
	_check(max_delta <= 0.018 and simulated >= 120.0, "120 seconds retain native physics step size")
	for index in creatures.size():
		var creature := creatures[index]
		creature.set("enabled", false)
		var minimum_travel := 3.0 if creature is WaterhouseColossus else (70.0 if creature is WaterhouseCreature else 20.0)
		_check(travel[index] > minimum_travel, String(creature.name) + ": autonomous encounters produce sustained locomotion")
		_check(overlaps[index] == 0, String(creature.name) + ": real entity shape never penetrates world")
		_check(safe[index], String(creature.name) + ": remains inside its biome")
		if not creature is WaterhouseColossus:
			_check(pose_safe[index], String(creature.name) + ": imported skeleton remains finite and proportionate")
		print("MULTI METRICS ", creature.name, " travel=", snappedf(travel[index], 0.1), " overlaps=", overlaps[index], " end=", creature.global_position)
	_finished = true
	print("MULTI_CREATURE_REACHED_FINAL: ", _checks - _failures, "/", _checks, " passed")
	print("LIMIT: autonomous locomotion/skeleton/territory test does not replace a human chase and visual animation assessment.")
	quit(1 if _failures else 0)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
