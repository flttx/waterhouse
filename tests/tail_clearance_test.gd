extends SceneTree
## Audit actual skinned vertices, not just the head collider, during repeated goal reversals.
const SkinGeometry = preload("res://tests/skin_geometry.gd")
var failures: int = 0
var finished: bool = false
var capture_camera: Camera3D
var cells: Dictionary = {}
const CELL := 4.0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		if not finished:
			push_error("TAIL watchdog: no final sentinel")
			quit(2))
	var fixture := Node3D.new()
	root.add_child(fixture)
	var world := preload("res://scenes/world.tscn").instantiate()
	fixture.add_child(world)
	_index_colliders(world)
	if OS.get_cmdline_user_args().has("--capture"):
		_setup_capture(world)
	var actors: Array[WaterhouseCreature] = []
	for species in ["leviathan", "whale"]:
		var actor := load("res://scenes/" + species + ".tscn").instantiate() as WaterhouseCreature
		fixture.add_child(actor)
		actor._rng.seed = 20261010 + actors.size()
		actors.append(actor)
		_audit_rest_geometry(actor, species)
	for frame in 6:
		await physics_frame
	var goals: Array = [
		[Vector3(-14, -7, -32), Vector3(14, -10, 30), Vector3(-14, -7, 30), Vector3(14, -10, -30)],
		[Vector3(112, -10, 31), Vector3(162, -14, 55), Vector3(112, -10, 55), Vector3(162, -14, 31)],
	]
	var previous: Array[Vector3] = [actors[0].global_position, actors[1].global_position]
	var travel: Array[float] = [0.0, 0.0]
	var overlaps: Array[int] = [0, 0]
	var sampled: Array[int] = [0, 0]
	var stall: Array[float] = [0.0, 0.0]
	var maximum_stall: Array[float] = [0.0, 0.0]
	var original_ticks := Engine.physics_ticks_per_second
	var original_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 1200
	Engine.max_physics_steps_per_frame = 128
	Engine.time_scale = 20.0
	for actor in actors:
		actor.enabled = true
	var simulated := 0.0
	var next_sample := 0.0
	var captured := false
	while simulated < 120.0:
		await physics_frame
		var delta := actors[0].get_physics_process_delta_time()
		simulated += delta
		for index in actors.size():
			var actor := actors[index]
			# Repeated opposite goals exercise native navigation and swept movement.
			actor.state = WaterhouseCreature.State.INVESTIGATE
			actor._state_age = 0.0
			actor._goal = goals[index][int(simulated / 15.0) % 4]
			var moved := actor.global_position.distance_to(previous[index])
			travel[index] += moved
			stall[index] = stall[index] + delta if moved < delta * 0.1 else 0.0
			maximum_stall[index] = maxf(maximum_stall[index], stall[index])
			previous[index] = actor.global_position
		if simulated >= next_sample:
			next_sample += 2.0
			for index in actors.size():
				var points := SkinGeometry.vertices_world(actors[index])
				sampled[index] += points.size()
				for point in points:
					if _penetrates(point):
						overlaps[index] += 1
						if overlaps[index] <= 3:
							print("TAIL overlap actor=", index, " t=", simulated, " point=", point)
		if capture_camera != null and not captured and simulated > 35.0:
			captured = true
			for index in actors.size():
				await _capture_actor(actors[index], index)
	for index in actors.size():
		actors[index].enabled = false
		_check(sampled[index] > 1000000, "Both full meshes must be audited repeatedly")
		_check(overlaps[index] == 0, "Skinned body penetrates actual facility: " + str(index))
		_check(travel[index] > 70.0 and maximum_stall[index] < 8.0, "Body protection must not freeze actor " + str(index))
		print("TAIL actor=", index, " sampled=", sampled[index], " overlaps=", overlaps[index], " travel=", travel[index], " stall=", maximum_stall[index])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = original_ticks
	Engine.max_physics_steps_per_frame = original_steps
	fixture.queue_free()
	await process_frame
	finished = true
	print("TAIL CLEARANCE failures=", failures, " simulated=", simulated)
	quit(1 if failures > 0 else 0)

func _index_colliders(node: Node) -> void:
	if node is CollisionShape3D and not node.disabled:
		var parent := node.get_parent() as CollisionObject3D
		if parent != null and parent.collision_layer & 1:
			var extent := Vector3.ZERO
			if node.shape is BoxShape3D:
				extent = node.shape.size * 0.5
			elif node.shape is CylinderShape3D:
				extent = Vector3(node.shape.radius, node.shape.height * 0.5, node.shape.radius)
			else:
				_check(false, "Unsupported scenery shape in mesh audit: " + node.shape.get_class())
			var minimum := Vector3(INF, INF, INF)
			var maximum := -minimum
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						var corner: Vector3 = node.global_transform * (extent * Vector3(x, y, z))
						minimum = minimum.min(corner)
						maximum = maximum.max(corner)
			var entry: Array = [node.global_transform.affine_inverse(), extent, node.shape is CylinderShape3D]
			var lower := Vector3i((minimum / CELL).floor())
			var upper := Vector3i((maximum / CELL).floor())
			for x in range(lower.x, upper.x + 1):
				for y in range(lower.y, upper.y + 1):
					for z in range(lower.z, upper.z + 1):
						var key := Vector3i(x, y, z)
						if not cells.has(key):
							cells[key] = []
						cells[key].append(entry)
	for child in node.get_children():
		_index_colliders(child)

func _penetrates(point: Vector3) -> bool:
	for entry: Array in cells.get(Vector3i((point / CELL).floor()), []):
		var local: Vector3 = entry[0] * point
		var extent: Vector3 = entry[1]
		# Ignore sub-millimetre contact noise, not visible intersection.
		if absf(local.y) < extent.y - 0.001:
			if entry[2]:
				if Vector2(local.x, local.z).length() < extent.x - 0.001:
					return true
			elif absf(local.x) < extent.x - 0.001 and absf(local.z) < extent.z - 0.001:
				return true
	return false

func _audit_rest_geometry(actor: WaterhouseCreature, species: String) -> void:
	var source := Node3D.new()
	var scale_value := 22.0 if species == "leviathan" else 28.0
	source.scale = Vector3.ONE * scale_value
	source.rotation.y = PI
	source.position = Vector3(0, -1.65 if species == "leviathan" else -2.8, (0.49133 if species == "leviathan" else 0.489749) * scale_value)
	var model_path := "leviathan_rig" if species == "leviathan" else "whale"
	source.add_child(load("res://assets/models/" + model_path + ".glb").instantiate())
	root.add_child(source)
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var original := SkinGeometry.vertices_from(source_skeleton, source, true)
	var rebound := SkinGeometry.vertices_world(actor, true)
	_check(original.size() == rebound.size(), "Rebinding must preserve all source vertices")
	var maximum_error := 0.0
	var inverse := actor.global_transform.affine_inverse()
	for index in mini(original.size(), rebound.size()):
		maximum_error = maxf(maximum_error, original[index].distance_to(inverse * rebound[index]))
	_check(maximum_error < 0.002, "Rebinding altered source shape: " + species + " error=" + str(maximum_error))
	print("TAIL rest shape ", species, " vertices=", original.size(), " max_error=", maximum_error)
	source.queue_free()

func _setup_capture(world: WaterhouseWorld) -> void:
	# Diagnostic cutaway only: show the actual skinned mesh and nearby colliders.
	# Production water and lighting are unchanged.
	root.size = Vector2i(1440, 900)
	for mesh in world.find_children("*", "MeshInstance3D", true, false):
		var material: Material = mesh.material_override
		if material is ShaderMaterial and material.shader.resource_path.ends_with("water.gdshader"):
			mesh.visible = false
	world.environment.fog_enabled = false
	world.environment.ambient_light_energy = 1.3
	capture_camera = Camera3D.new()
	capture_camera.fov = 75
	root.add_child(capture_camera)
	capture_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-75, 15, 0)
	light.light_energy = 1.5
	root.add_child(light)

func _capture_actor(actor: WaterhouseCreature, index: int) -> void:
	var center := actor._spine_sample(11.0 if index == 0 else 14.0)
	capture_camera.position = center + Vector3(0, 26, 0)
	capture_camera.look_at(center, Vector3.FORWARD)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var result := root.get_texture().get_image().save_png("res://artifacts/tail_turn_" + str(index) + ".png")
	_check(result == OK, "Could not save diagnostic tail image")
