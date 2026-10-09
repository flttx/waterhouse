extends SceneTree
## New species only: native sensing, damage, GPU previews and a real canal turn.

class TestPlayer extends CharacterBody3D:
	var in_water: bool = true
	var light_on: bool = true
	var health: float = 100.0
	var dead: bool = false
	var camera: Camera3D
	var fleeing: bool = false
	func _physics_process(_delta: float) -> void:
		if fleeing:
			velocity = Vector3.RIGHT * 4.7
			move_and_slide()
	func take_damage(amount: float, _reason: String, _source: Node3D = null) -> void:
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
			push_error("HAZARD WATCHDOG: missing final sentinel")
			quit(2))
	if OS.get_cmdline_user_args().has("--visual"):
		await _render_models()
		return
	for species in ["hunter", "lurker", "drifter"]:
		await _test_species(species)
	await _canal_corner()
	await _continuous_chase()
	_finished = true
	print("HAZARD_REACHED_FINAL: ", _checks - _failures, "/", _checks, " passed")
	quit(1 if _failures else 0)

func _test_species(species: String) -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := TestPlayer.new()
	player.collision_layer = 2
	player.camera = Camera3D.new()
	player.camera.position.y = 0.75
	player.add_child(player.camera)
	fixture.add_child(player)
	var creature := WaterhouseHazard.new()
	creature.species = species
	creature.home = Vector3(-8, -3, 0)
	fixture.add_child(creature)
	creature.player = player
	creature.set_physics_process(false)
	player.global_position = Vector3(8, -3.75, 0)
	var cover := _box(fixture, Vector3(0, -3, 0), Vector3(1, 7, 6))
	await _frames(3)
	_check(_renderable(creature), species + ": native body meshes and compiled shader uniforms are populated")
	_check(not creature._visible_player(), species + ": actual concrete blocks camera visibility")
	creature.enabled = true
	creature.hear_noise(player.global_position, 1.0)
	_check(creature._noise_left == 0.0, species + ": distant sound is muffled or ignored behind actual concrete")
	cover.queue_free()
	await _frames(2)
	creature.reset_creature()
	creature.enabled = true
	creature.hear_noise(creature.global_position + Vector3(6, 0, 0), 0.0)
	_check(creature._noise_left == 0.0, species + ": zero loudness never creates an alarm")
	creature.reset_creature()
	creature.enabled = true
	creature.hear_noise(player.global_position, 0.05)
	_check(creature._noise_left == 0.0, species + ": quiet distant motion stays unnoticed")
	creature.hear_noise(player.global_position, 1.2)
	_check(creature._noise_left > 0.0 if species != "drifter" else creature._noise_left == 0.0, species + ": loud-noise response matches ecological role")
	creature.reset_creature()
	player.global_position = creature.global_position + Vector3(2.0, -0.6, 0.0)
	player.health = 100.0
	player.dead = false
	player.in_water = false
	await _frames(2)
	_check(not creature._visible_player(), species + ": shore medium prevents visual attack eligibility")
	creature.enabled = true
	creature._physics_process(0.2)
	_check(player.health == 100.0, species + ": dry target never takes damage")
	player.in_water = true
	creature.reset_creature()
	creature.enabled = true
	await _frames(2)
	creature._physics_process(0.2)
	if species == "drifter":
		_check(player.health < 100.0 and player.health > 0.0, "drifter: nearby tentacle contact applies survivable poison damage")
		_check(creature._colony.size() == 5, "drifter: five native bells with individual tentacle meshes")
		var bell := creature._colony[0]
		var before := bell.position
		creature._physics_process(0.7)
		_check(bell.position != before, "drifter: bells physically animate independently")
		var health := player.health
		cover = _box(fixture, creature.global_position + Vector3(1.0, 0, 0), Vector3(0.2, 8, 6))
		await _frames(2)
		creature._cooldown = 0.0
		creature._physics_process(0.2)
		_check(player.health == health, "drifter: poison cannot pass actual cover")
		cover.queue_free()
	else:
		_check(creature._windup >= 0.8 and player.health == 100.0, species + ": readable windup precedes real damage")
		creature._physics_process(0.2)
		_check(player.health == 100.0, species + ": no damage during windup")
		player.in_water = false
		creature._physics_process(2.0)
		_check(player.health == 100.0, species + ": leaving water dodges pending strike")
		player.in_water = true
		creature.reset_creature()
		creature.enabled = true
		creature._sense_clock = 0.0
		creature._physics_process(0.2)
		creature._physics_process(2.0)
		_check(player.dead and creature._quiet > 0.0, species + ": completed hit invokes real damage and recovery")
		player.dead = false
		player.health = 100.0
		creature._seen = true
		creature.reset_creature()
		_check(not creature._seen and creature._windup < 0.0, species + ": retry clears cached observation and attack")
		if species == "hunter":
			player.in_water = true
			creature.state = WaterhouseHazard.State.PATROL
			creature._cooldown = 100.0
			creature._sense_clock = 0.0
			creature._physics_process(0.2)
			player.in_water = false
			creature._sense_clock = 0.0
			creature._lost = 2.3
			creature._physics_process(0.2)
			_check(creature.state == WaterhouseHazard.State.SEARCH, "hunter: lost visual target enters search")
			creature._search_left = 0.05
			creature._physics_process(0.2)
			_check(creature.state == WaterhouseHazard.State.RETREAT, "hunter: bounded search returns to quiet patrol")
		else:
			var anchored := creature.global_position
			creature._physics_process(2.0)
			_check(creature.global_position == anchored, "lurker: body remains anchored to its own territory")
	creature.enabled = false
	var frozen_position := creature.global_position
	var age := creature._age
	creature._physics_process(1.0)
	_check(creature.global_position == frozen_position and creature._age == age, species + ": enabled switch freezes simulation")
	creature.apply_difficulty({"speed_multiplier": 0.8, "attack_damage": 45.0, "attack_windup": 1.35})
	var easy_speed := creature.speed_multiplier
	var easy_windup := creature.attack_windup
	creature.apply_difficulty({"speed_multiplier": 1.16, "attack_windup": 0.65})
	_check(creature.speed_multiplier > easy_speed and creature.attack_windup < easy_windup, species + ": difficulty changes movement and strike timing")
	fixture.queue_free()
	await _frames(2)

func _canal_corner() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate() as WaterhouseWorld
	fixture.add_child(world)
	var hunter := WaterhouseHazard.new()
	hunter.species = "hunter"
	hunter.world = world
	hunter.home = Vector3(174, -3, -83)
	hunter.patrol_points = world.canal_patrol_points.duplicate()
	fixture.add_child(hunter)
	await _frames(5)
	_check(hunter._ready_graph and hunter._graph.get_point_count() > 100, "hunter: actual ring AStar3D contains full patrol network")
	var old_ticks := Engine.physics_ticks_per_second
	var old_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 1800
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 30.0
	hunter.enabled = true
	var simulated: float = 0.0
	var travelled: float = 0.0
	var previous := hunter.global_position
	var overlaps: int = 0
	var longest_stall: float = 0.0
	var stall: float = 0.0
	var territory_safe: bool = true
	while simulated < 45.0:
		await physics_frame
		var delta := hunter.get_physics_process_delta_time()
		simulated += delta
		var moved := previous.distance_to(hunter.global_position)
		travelled += moved
		previous = hunter.global_position
		stall = stall + delta if moved < delta * 0.15 else 0.0
		longest_stall = maxf(longest_stall, stall)
		territory_safe = territory_safe and world.is_water(hunter.global_position)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hunter._shape
		query.transform = Transform3D(Basis.IDENTITY, hunter.global_position)
		query.collision_mask = 1
		query.exclude = [hunter.get_rid()]
		query.margin = 0.0
		if not hunter.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			overlaps += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_physics_steps_per_frame = old_steps
	hunter.enabled = false
	_check(travelled > 80.0 and hunter.global_position.x > 181.0 and hunter.global_position.z > -10.0, "hunter: real north-east corner is rounded into east canal")
	_check(longest_stall < 2.0, "hunter: corner path never remains blocked for two seconds")
	_check(overlaps == 0 and territory_safe, "hunter: real sphere stays in water without static penetration")
	print("HUNTER CORNER travel=", snappedf(travelled, 0.1), " stall=", longest_stall, " overlaps=", overlaps, " end=", hunter.global_position)
	fixture.queue_free()
	await _frames(2)

func _render_models() -> void:
	root.mode = Window.MODE_MINIMIZED
	for species in ["hunter", "lurker", "drifter"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1100, 750)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.027, 0.047, 0.057)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.37, 0.48, 0.49)
		environment.ambient_light_energy = 0.7
		var env_node := WorldEnvironment.new()
		env_node.environment = environment
		viewport.add_child(env_node)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -25, 0)
		light.light_energy = 2.2
		viewport.add_child(light)
		var creature := WaterhouseHazard.new()
		creature.species = species
		creature.home = Vector3.ZERO
		viewport.add_child(creature)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(6, 2.2, -7)
		camera.look_at(Vector3(0, -0.8 if species == "drifter" else 0, 0))
		camera.fov = 46.0
		camera.current = true
		for frame in 16:
			await process_frame
		_check(_renderable(creature), species + ": actual native geometry/materials are renderable")
		RenderingServer.force_draw(false)
		_check(viewport.get_texture().get_image().save_png("res://artifacts/" + species + "_preview.png") == OK, species + ": native GPU preview saved")
		viewport.queue_free()
		await process_frame
	_finished = true
	print("HAZARD_VISUAL_REACHED_FINAL")
	quit(1 if _failures else 0)

func _continuous_chase() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := TestPlayer.new()
	player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	player.collision_layer = 2
	player.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var body_shape := CollisionShape3D.new()
	body_shape.shape = capsule
	body_shape.position.y = 0.9
	player.add_child(body_shape)
	player.camera = Camera3D.new()
	player.camera.position.y = 0.75
	player.add_child(player.camera)
	fixture.add_child(player)
	player.global_position = Vector3(12.0, -3.75, 0.0)
	var hunter := WaterhouseHazard.new()
	hunter.species = "hunter"
	hunter.home = Vector3(0.0, -3.0, 0.0)
	fixture.add_child(hunter)
	hunter.player = player
	await _frames(3)
	player.fleeing = true
	hunter.enabled = true
	var old_ticks := Engine.physics_ticks_per_second
	var old_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 1200
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 20.0
	var simulated: float = 0.0
	var noise_clock: float = 0.0
	var continuously_visible: bool = true
	var chased: bool = false
	var retreat_at: float = -1.0
	var quiet_observed: bool = false
	while simulated < 33.0:
		await physics_frame
		var delta := hunter.get_physics_process_delta_time()
		simulated += delta
		if retreat_at < 0.0:
			continuously_visible = continuously_visible and hunter._visible_player()
		chased = chased or hunter.state == WaterhouseHazard.State.CHASE
		if hunter.state == WaterhouseHazard.State.RETREAT and retreat_at < 0.0:
			retreat_at = simulated
			player.fleeing = false
			player.in_water = false
		quiet_observed = quiet_observed or (retreat_at > 0.0 and hunter._quiet > 8.0)
		noise_clock -= delta
		if noise_clock <= 0.0 and retreat_at < 0.0:
			hunter.hear_noise(player.global_position, 1.2)
			noise_clock = 0.5
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_physics_steps_per_frame = old_steps
	hunter.enabled = false
	_check(chased and continuously_visible and retreat_at >= 19.9 and retreat_at <= 20.5, "hunter: continuous real camera visibility plus repeated noise still ends pursuit at twenty seconds")
	_check(quiet_observed and hunter.state == WaterhouseHazard.State.PATROL, "hunter: forced retreat provides a real quiet interval and restores patrol")
	_check(player.health == 100.0, "continuous-chase fixture uses native fleeing movement rather than taking a bite to force retreat")
	print("HUNTER CONTINUOUS CHASE retreat_at=", retreat_at, " end_state=", hunter.state_name(), " player=", player.global_position, " hunter=", hunter.global_position)
	fixture.queue_free()
	await _frames(2)

func _box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	return body

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
	return count > 20

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
