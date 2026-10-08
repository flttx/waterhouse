extends SceneTree

class TestPlayer extends CharacterBody3D:
	var in_water: bool = true
	var light_on: bool = false
	var noise_level: float = 0.0
	var health: float = 100.0
	var dead: bool = false
	var camera: Camera3D

	func take_damage(amount: float, _reason: String) -> void:
		health -= amount
		dead = health <= 0.0


var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_add_box(world, Vector3(0.0, -13.5, 0.0), Vector3(40.0, 1.0, 86.0))
	_add_box(world, Vector3(0.0, -6.0, 0.0), Vector3(3.0, 12.0, 6.0))
	_add_box(world, Vector3(-20.0, -6.0, 0.0), Vector3(1.0, 14.0, 86.0))
	_add_box(world, Vector3(20.0, -6.0, 0.0), Vector3(1.0, 14.0, 86.0))
	_add_box(world, Vector3(0.0, -6.0, -43.0), Vector3(40.0, 14.0, 1.0))
	_add_box(world, Vector3(0.0, -6.0, 43.0), Vector3(40.0, 14.0, 1.0))
	var player := TestPlayer.new()
	player.collision_layer = 2
	player.collision_mask = 1
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	player_shape.shape = capsule
	player_shape.position.y = 0.85
	player.add_child(player_shape)
	world.add_child(player)
	var scene := load("res://scenes/leviathan.tscn") as PackedScene
	var creature := scene.instantiate() as WaterhouseCreature
	world.add_child(creature)
	creature.player = player
	await _frames(5)
	_check(creature._navigation_ready and creature._graph.get_point_count() > 500, "underwater AStar3D grid contains traversable nodes")
	_check(creature._skeleton != null and creature._skeleton.get_bone_count() == 34, "original 34-bone Tripo rig is active")
	_check(creature._bone_rest.size() == 34 and not creature._skin_materials.is_empty(), "native skinning and original textured mesh are configured")

	creature.global_position = Vector3(-9.0, -5.0, 0.0)
	player.global_position = Vector3(9.0, -5.75, 0.0)
	creature._heading = Vector3.RIGHT
	creature._refresh_player_properties()
	await _frames(2)
	_check(not creature._has_line_of_sight(creature._player_position()), "concrete pillar blocks actual player visibility")
	creature.awareness = 0.0
	for iteration in 30:
		creature._sense_player(0.16)
	_check(creature.awareness == 0.0, "occluded target does not accumulate visual awareness")

	creature.global_position = Vector3(-12.0, -5.0, 12.0)
	creature.state = WaterhouseCreature.State.PATROL
	player.global_position = Vector3(12.0, -5.75, 12.0)
	player.light_on = false
	await _frames(2)
	for iteration in 10:
		creature._sense_player(0.16)
	_check(creature.awareness == 0.0, "dark target outside visual range remains hidden")
	player.light_on = true
	for iteration in 25:
		creature._sense_player(0.16)
	_check(creature.state == WaterhouseCreature.State.CHASE, "flashlight raises detection range and produces chase")

	player.in_water = false
	player.global_position.y = 1.5
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.SEARCH, "leaving the water immediately ends pursuit")
	creature.state = WaterhouseCreature.State.CHASE
	creature._attack_left = 0.01
	creature._update_attack(1.0)
	_check(player.health == 100.0, "a shore player cannot be attacked")
	creature.enabled = true
	creature.state = WaterhouseCreature.State.PATROL
	creature._noise_cooldown = 0.0
	creature.hear_noise(creature.global_position + Vector3(0.0, 6.0, -8.0), 1.0)
	creature.enabled = false
	_check(creature.state == WaterhouseCreature.State.INVESTIGATE and creature._goal.y <= -2.59, "shore noise lures creature below water rather than onto land")

	player.in_water = true
	player.light_on = false
	creature.global_position = Vector3(10.0, -5.0, -15.0)
	player.global_position = Vector3(12.5, -5.75, -15.0)
	creature.state = WaterhouseCreature.State.CHASE
	creature._attack_cooldown = 0.0
	creature._attack_left = -1.0
	await _frames(2)
	creature._update_attack(0.1)
	_check(creature._attack_left > 0.8 and player.health == 100.0, "close attack begins with a readable 0.9-second windup")
	creature._update_attack(0.3)
	_check(player.health == 100.0, "windup causes no immediate damage")
	player.global_position.x = 18.0
	await _frames(2)
	creature._update_attack(1.0)
	_check(player.health == 100.0 and creature.state == WaterhouseCreature.State.RETREAT, "escaping the strike radius avoids damage and gives recovery time")
	player.global_position.x = 12.0
	creature.state = WaterhouseCreature.State.CHASE
	creature._attack_cooldown = 0.0
	creature._attack_left = -1.0
	await _frames(2)
	creature._update_attack(0.1)
	creature._update_attack(1.0)
	_check(player.dead and player.health <= 0.0, "a completed unobstructed attack invokes player death")
	player.dead = false
	player.health = 100.0

	creature.global_position = Vector3(-9.0, -5.0, 0.0)
	player.global_position = Vector3(9.0, -5.75, 0.0)
	creature.state = WaterhouseCreature.State.CHASE
	creature.awareness = 1.0
	creature._lost_seconds = 0.0
	creature._last_seen = player.global_position
	await _frames(2)
	for iteration in 30:
		creature._sense_player(0.16)
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.SEARCH, "broken line of sight transitions to remembered-position search")
	creature._state_age = 14.0
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.RETREAT, "search has a bounded duration")

	creature.player = null
	creature.global_position = Vector3(-9.0, -5.0, 0.0)
	creature._goal = Vector3(9.0, -5.0, 0.0)
	creature._heading = Vector3.RIGHT
	creature._path_clock = 0.0
	creature._state_age = 0.0
	creature.state = WaterhouseCreature.State.INVESTIGATE
	creature._plan_route()
	_check(creature._path.size() > 2, "obstructed destination produces a route around the pillar")
	var clear_segments := true
	for segment in range(1, creature._path.size()):
		clear_segments = clear_segments and creature._clear_motion(creature._path[segment - 1], creature._path[segment])
	_check(clear_segments, "each navigation edge is swept with the real body radius")
	var origin := creature.global_position
	var clear_during_movement := true
	creature.enabled = true
	Engine.time_scale = 3.0
	for frame in 150:
		await physics_frame
		clear_during_movement = clear_during_movement and creature._sphere_is_clear(creature.global_position)
	creature.enabled = false
	Engine.time_scale = 1.0
	_check(clear_during_movement, "moving pursuit body never enters pillar, walls, or floor")
	_check(creature.global_position.distance_to(origin) > 5.0, "obstacle routing continues moving rather than remaining stuck")
	_check(creature._history.size() > 100, "moving head records a curved history for the long skinned body")

	creature.state = WaterhouseCreature.State.DORMANT
	creature._quiet_left = 0.01
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.PATROL, "quiet interval schedules a fresh encounter")
	creature._state_age = 36.0
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.RETREAT, "encounter returns to retreat without permanent pursuit")
	creature._state_age = 12.0
	creature._update_state(0.1)
	_check(creature.state == WaterhouseCreature.State.DORMANT and creature._quiet_left >= 40.0, "retreat restores a 40-to-70-second quiet interval")
	creature.reset_creature()
	_check(creature.awareness == 0.0 and creature.state == WaterhouseCreature.State.DORMANT and creature._attack_left < 0.0, "restart clears threat, attack, and state timers")
	print("CREATURE TESTS: ", _checks - _failures, "/", _checks, " passed")
	quit(1 if _failures > 0 else 0)


func _add_box(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)


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
