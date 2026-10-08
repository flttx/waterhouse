extends SceneTree
## Full running main scene: 9 real entities, 8 species, live player/camera and HUD.
## Teleports are fixtures for encounter regions, not a complete human playthrough.

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			push_error("ALL CREATURES WATCHDOG: no final sentinel")
			quit(2))
	AudioServer.set_bus_mute(0, true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	await _frames(6)
	game.call("start_run")
	var world := game.get("world") as WaterhouseWorld
	var player := game.get("player") as PlayerController
	var enemies: Array[CharacterBody3D] = []
	var species: Dictionary[String, bool] = {}
	for candidate: CharacterBody3D in game.get("enemies"):
		enemies.append(candidate)
		species[str(candidate.get_meta("species"))] = true
		_check(_renderable(candidate), candidate.name + ": actual geometry and compiled materials are present")
	_check(enemies.size() == 9 and species.size() == 8, "actual game creates nine entities and eight distinct species")
	_check(player.enabled and player.camera.is_current() and int(game.get("flow")) == 1, "main player, camera and gameplay loop run normally")
	if enemies.size() != 9:
		await _cleanup(game)
		_finished = true
		print("ALL_CREATURES_REACHED_FINAL: bad entity contract")
		quit(1)
		return
	var phases: Array[Vector3] = [
		world.nav_targets["valve_south"], world.nav_targets["archive"],
		world.nav_targets["annex_valve"], world.nav_targets["tier_valve"],
		world.nav_targets["reservoir_valve"], Vector3(84.5, -2.8, -43),
		Vector3(-32, -4.1, -83), Vector3(80, -4.1, 73),
	]
	var previous: Array[Vector3] = []
	var origins: Array[Vector3] = []
	var travel: Array[float] = []
	var overlaps: Array[int] = []
	var active: Array[bool] = []
	var colonies_moved: Array[bool] = []
	for enemy in enemies:
		previous.append(enemy.global_position)
		origins.append(enemy.global_position)
		travel.append(0.0)
		overlaps.append(0)
		active.append(true)
		colonies_moved.append(false)
	var old_ticks := Engine.physics_ticks_per_second
	var old_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 2400
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 40.0
	var simulated: float = 0.0
	var largest_delta: float = 0.0
	var phase: int = -1
	var noise_clock: float = 0.0
	var marker_clock: float = 0.0
	var marker_safe: bool = true
	var live_camera: bool = true
	var colony_structure: bool = true
	var territory_safe: bool = true
	var hunter_stall: float = 0.0
	var longest_hunter_stall: float = 0.0
	var player_healthy: bool = true
	var sound_safe: bool = true
	var soundscape := game.get("soundscape") as WaterhouseSoundscape
	var native_player_steps: int = 0
	while simulated < 120.0:
		await physics_frame
		var delta := player.get_physics_process_delta_time()
		simulated += delta
		largest_delta = maxf(largest_delta, delta)
		native_player_steps += 1
		live_camera = live_camera and player.camera.is_current() and player.enabled
		player_healthy = player_healthy and player.health > 0.0 and int(game.get("flow")) == 1
		sound_safe = sound_safe and soundscape.water.volume_db >= -80.0 and soundscape.water.volume_db <= 0.0 and soundscape.air.volume_db >= -80.0 and soundscape.air.volume_db <= 0.0 and soundscape.heartbeat.volume_db >= -80.0 and soundscape.heartbeat.volume_db <= 0.0
		var next_phase := mini(7, int(simulated / 15.0))
		if next_phase != phase:
			phase = next_phase
			player.reset_at(phases[phase])
			player.health = 10000.0
			player.breath_seconds = 180.0
			player._update_medium(false)
			noise_clock = 0.0
		noise_clock -= delta
		if noise_clock <= 0.0:
			player.noise_emitted.emit(player.global_position, 1.15)
			noise_clock = 4.0
		for index in enemies.size():
			var enemy := enemies[index]
			var kind := str(enemy.get_meta("species"))
			var movement := previous[index].distance_to(enemy.global_position)
			travel[index] += movement
			previous[index] = enemy.global_position
			active[index] = active[index] and bool(enemy.get("enabled")) and enemy.is_physics_processing()
			for node in enemy.find_children("*", "CollisionShape3D", false, false):
				var collision := node as CollisionShape3D
				if collision.disabled or collision.shape == null:
					continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = collision.shape
				query.transform = collision.global_transform
				query.collision_mask = 1
				query.exclude = [enemy.get_rid()]
				query.margin = 0.0
				var hits := enemy.get_world_3d().direct_space_state.intersect_shape(query, 1)
				if not hits.is_empty():
					overlaps[index] += 1
					if overlaps[index] < 3:
						print("ALL BODY OVERLAP ", enemy.name, " pos=", enemy.global_position, " collider=", (hits[0]["collider"] as Node).name)
			if kind == "hunter":
				hunter_stall = hunter_stall + delta if movement < delta * 0.15 else 0.0
				longest_hunter_stall = maxf(longest_hunter_stall, hunter_stall)
				territory_safe = territory_safe and world.is_water(enemy.global_position)
			elif kind == "lurker":
				territory_safe = territory_safe and enemy.global_position.distance_to(origins[index]) < 0.02
			elif kind == "drifter":
				var hazard := enemy as WaterhouseHazard
				colony_structure = colony_structure and hazard._colony.size() == 5
				for bell in hazard._colony:
					var rest: Vector3 = bell.get_meta("rest")
					colonies_moved[index] = colonies_moved[index] or bell.position.distance_to(rest) > 0.05
				territory_safe = territory_safe and world.is_water(enemy.global_position) and enemy.global_position.distance_to(origins[index]) < 1.7
		marker_clock -= delta
		if marker_clock <= 0.0:
			marker_clock = 1.0
			var markers: Array[Dictionary] = game.call("_monster_markers")
			marker_safe = marker_safe and markers.size() == enemies.size()
			for index in mini(markers.size(), enemies.size()):
				var marker_position: Vector3 = markers[index]["position"]
				marker_safe = marker_safe and marker_position.distance_to(enemies[index].global_position) < 0.001 and str(markers[index]["name"]) == enemies[index].name
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_physics_steps_per_frame = old_steps
	_check(largest_delta <= 0.018 and simulated >= 120 and native_player_steps >= 7100, "120 seconds use native ~1/60-second player/AI physics steps")
	_check(live_camera and player_healthy, "live main player/camera survive all eight native encounter regions")
	_check(marker_safe, "map markers continually match all nine actually moving entities")
	_check(territory_safe, "native hunter/lurker/colonies remain in their water territories")
	_check(longest_hunter_stall < 2.0, "actual game's canal hunter has no persistent obstruction stall")
	_check(colony_structure, "both game colonies contain five independently animated native bells")
	_check(sound_safe, "main sound mixing remains finite and bounded through region changes")
	for index in enemies.size():
		var enemy := enemies[index]
		var kind := str(enemy.get_meta("species"))
		_check(active[index], enemy.name + ": AI stayed enabled and processed native physics")
		_check(overlaps[index] == 0, enemy.name + ": actual entity shapes never penetrated real world")
		if kind == "hunter":
			_check(travel[index] > 200.0, "actual game hunter travels across the long outer waterway")
		elif kind == "drifter":
			_check(travel[index] > 8.0 and colonies_moved[index], enemy.name + ": native colony and separate bell positions move")
		print("ALL ENTITY ", enemy.name, " species=", kind, " travel=", snappedf(travel[index], 0.1), " overlaps=", overlaps[index], " end=", enemy.global_position)
	print("ALL METRICS time=", snappedf(simulated, 0.01), " steps=", native_player_steps, " hunter_stall=", snappedf(longest_hunter_stall, 0.01))
	game.call("pause_run")
	var paused_positions: Array[Vector3] = []
	for enemy in enemies:
		paused_positions.append(enemy.global_position)
	await _frames(5)
	var pause_safe: bool = true
	for index in enemies.size():
		pause_safe = pause_safe and enemies[index].global_position == paused_positions[index]
	_check(pause_safe and paused and int(game.get("flow")) == 2, "actual pause freezes all nine native entities")
	game.call("resume_run")
	_check(not paused and int(game.get("flow")) == 1 and player.camera.is_current(), "actual resume restores gameplay and player camera")
	await _cleanup(game)
	_finished = true
	print("ALL_CREATURES_REACHED_FINAL: ", _checks - _failures, "/", _checks, " passed")
	print("LIMIT: teleported high-health player exercises native encounters; this does not certify a human playthrough or full skinned triangle collision.")
	quit(1 if _failures else 0)

func _cleanup(game: Node3D) -> void:
	game.set("flow", 0)
	(game.get("player") as PlayerController).enabled = false
	game.call("_set_enemies_enabled", false)
	(game.get("soundscape") as WaterhouseSoundscape).enabled = false
	for node in game.find_children("*", "", true, false):
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
			(node as AudioStreamPlayer).stream = null
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stop()
			(node as AudioStreamPlayer3D).stream = null
	await create_timer(0.25, true, false, true).timeout
	game.queue_free()
	await process_frame
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func _renderable(body: Node3D) -> bool:
	var count: int = 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			return false
		count += 1
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material is ShaderMaterial:
				var skin := material as ShaderMaterial
				if skin.shader == null or skin.shader.get_shader_uniform_list().is_empty():
					return false
	return count > 0

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
