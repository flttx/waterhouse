extends SceneTree
## Real world/player/creature integration. Stationary swimmers keep native
## capsules, camera, medium detection and damage, but omit controls/oxygen.
## High health lets both encounters finish rather than ending on first death.

var _checks: int = 0
var _failures: int = 0
var _simulated: float = 0.0
var _travel: float = 0.0
var _collisions: int = 0
var _clearance_contacts: int = 0
var _stall: float = 0.0
var _longest_stall: float = 0.0
var _largest_step: float = 0.0
var _patrol_seen: bool = false
var _retreats: int = 0
var _quiet_after_retreat: bool = false
var _south_investigate: bool = false
var _south_chase: bool = false
var _north_investigate: bool = false
var _north_chase: bool = false
var _cover_seen: bool = false
var _search_after_cover: bool = false


func _initialize() -> void:
	create_timer(25.0, true, false, true).timeout.connect(func() -> void:
		push_error("CREATURE WORLD TEST WATCHDOG: real-time limit exceeded")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_msec()
	var fixture := Node3D.new()
	root.add_child(fixture)
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate() as WaterhouseWorld
	fixture.add_child(world)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerController
	player.world = world
	fixture.add_child(player)
	player.enabled = true
	player.set_physics_process(false)
	player.reset_at(Vector3(-21.0, 0.72, 36.0))
	player.health = 10000.0
	var creature := (load("res://scenes/leviathan.tscn") as PackedScene).instantiate() as WaterhouseCreature
	creature.player = player
	fixture.add_child(creature)
	player.noise_emitted.connect(creature.hear_noise)
	creature._rng.seed = 20261008
	creature.reset_creature()
	for frame in 5:
		await physics_frame
	_expect(creature._sphere_is_clear(creature.global_position), "actual spawn head is clear of waterhouse structures")
	_expect(creature._navigation_ready and creature._graph.get_point_count() > 450, "real waterhouse builds a traversable underwater graph")
	print("WORLD GRAPH nodes=", creature._graph.get_point_count(), " quiet_start=", creature._quiet_left)
	var original_ticks := Engine.physics_ticks_per_second
	var original_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 2400
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 40.0
	creature.enabled = true
	var last_position := creature.global_position
	var last_state := creature.state
	var phase: int = 0
	var phase_started: float = 0.0
	var noise_clock: float = 0.0
	var covered: bool = false
	while _simulated < 120.0:
		await physics_frame
		var delta := creature.get_physics_process_delta_time()
		_largest_step = maxf(_largest_step, delta)
		_simulated += delta
		var movement := creature.global_position.distance_to(last_position)
		_travel += movement
		last_position = creature.global_position
		if movement < delta * 0.25:
			_stall += delta
		else:
			_stall = 0.0
		_longest_stall = maxf(_longest_stall, _stall)
		if not creature._sphere_is_clear(creature.global_position):
			_clearance_contacts += 1
		var body_query := creature._shape_query(creature.global_position)
		body_query.margin = 0.0
		var body_hits := creature.get_world_3d().direct_space_state.intersect_shape(body_query, 1)
		if not body_hits.is_empty():
			_collisions += 1
			if _collisions < 6:
				print("WORLD BODY OVERLAP pos=", creature.global_position, " collider=", (body_hits[0]["collider"] as Node).name)
		if creature.state != last_state:
			print("WORLD STATE t=", snappedf(_simulated, 0.1), " phase=", phase, " ", creature.state_name(), " pos=", creature.global_position)
			if creature.state == WaterhouseCreature.State.RETREAT:
				_retreats += 1
			if last_state == WaterhouseCreature.State.RETREAT and creature.state == WaterhouseCreature.State.DORMANT:
				_quiet_after_retreat = true
			last_state = creature.state
		if phase == 0 and creature.state == WaterhouseCreature.State.PATROL:
			_patrol_seen = true
			phase = 1
			phase_started = _simulated
			_place_swimmer(player, Vector3(-8.9, -7.62, 18.2))
			noise_clock = 0.0
		elif phase == 1:
			_south_investigate = _south_investigate or creature.state == WaterhouseCreature.State.INVESTIGATE
			_south_chase = _south_chase or creature.state == WaterhouseCreature.State.CHASE
			if _south_chase and not covered:
				covered = _try_shelter(player, creature, Vector3(-10.0, -6.0, 16.0), -1.0)
				_cover_seen = _cover_seen or covered
			if covered and creature.state == WaterhouseCreature.State.SEARCH:
				_search_after_cover = true
			if _simulated - phase_started >= 28.0:
				phase = 2
				phase_started = _simulated
				_place_swimmer(player, Vector3(9.0, -9.62, -19.2))
				noise_clock = 0.0
		elif phase == 2:
			_north_investigate = _north_investigate or creature.state == WaterhouseCreature.State.INVESTIGATE
			_north_chase = _north_chase or creature.state == WaterhouseCreature.State.CHASE
			if _simulated - phase_started >= 29.0:
				phase = 3
				player.reset_at(Vector3(-21.0, 0.72, 36.0))
		noise_clock -= delta
		if phase in [1, 2] and noise_clock <= 0.0 and not (phase == 1 and covered):
			# Actual public noise signal: a loud metal decoy at the objective.
			player.noise_emitted.emit(player.global_position, 1.8)
			noise_clock = 3.0
	creature.enabled = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = original_ticks
	Engine.max_physics_steps_per_frame = original_steps
	_expect(_largest_step <= 0.018 and _simulated >= 119.9, "120 simulated seconds retain native ~1/60-second physics steps")
	_expect(_collisions == 0, "head never penetrates real static walls, baffles, platforms or pool floor")
	_expect(_travel > 70.0 and _longest_stall < 4.0, "patrol/investigation keeps moving without a long obstruction stall")
	_expect(_patrol_seen, "initial quiet interval naturally transitions to patrol")
	_expect(_south_investigate and _south_chase, "south valve noise plus real camera visibility naturally produces pursuit")
	_expect(_north_investigate and _north_chase, "north valve noise plus real camera visibility naturally produces pursuit")
	_expect(_cover_seen and _search_after_cover, "real submerged baffle breaks visibility and naturally produces search")
	_expect(_retreats >= 2 and _quiet_after_retreat, "encounters naturally retreat and restore a quiet interval")
	print("WORLD METRICS simulated=", snappedf(_simulated, 0.01), " travel=", snappedf(_travel, 0.1), " stall=", snappedf(_longest_stall, 0.01), " overlaps=", _collisions, " clearance_margin_contacts=", _clearance_contacts, " retreat_count=", _retreats, " wall_ms=", Time.get_ticks_msec() - started)
	print("CREATURE WORLD TESTS: ", _checks - _failures, "/", _checks, " passed")
	print("LIMIT: stationary high-health fixtures omit player inputs/oxygen and do not certify difficulty or a full human playthrough.")
	quit(1 if _failures > 0 else 0)


func _place_swimmer(player: PlayerController, feet_position: Vector3) -> void:
	player.reset_at(feet_position)
	player.health = 10000.0
	player._update_medium(false)


func _try_shelter(player: PlayerController, creature: WaterhouseCreature, center: Vector3, side: float) -> bool:
	var original := player.global_position
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape
	for offset in [Vector3(0.0, -1.62, side * 1.5), Vector3(side, -1.62, side * 1.5), Vector3(-side, -1.62, side * 1.8), Vector3(side, -1.62, 0.0)]:
		var point: Vector3 = center + offset
		if not player._shape_clear(capsule, point):
			continue
		_place_swimmer(player, point)
		if player.in_water and player.submerged and not creature._has_line_of_sight(player.camera.global_position):
			print("WORLD COVER camera=", player.camera.global_position, " head=", creature.global_position)
			return true
	_place_swimmer(player, original)
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
